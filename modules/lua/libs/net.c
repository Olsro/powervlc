/*****************************************************************************
 * net.c: Network related functions
 *****************************************************************************
 * Copyright (C) 2007-2008 the VideoLAN team
 * $Id$
 *
 * Authors: Antoine Cellerier <dionoea at videolan tod org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <assert.h>
#include <errno.h>
#include <ctype.h>
#ifdef _WIN32
#include <io.h>
#endif
#ifdef HAVE_POLL
#include <poll.h>       /* poll structures and defines */
#endif
#include <sys/stat.h>

#include <vlc_common.h>
#include <vlc_network.h>
#include <vlc_tls.h>
#include <vlc_url.h>
#include <vlc_fs.h>
#include <vlc_interrupt.h>

#include "../vlc.h"
#include "../libs.h"
#include "misc.h"

static vlclua_dtable_t *vlclua_get_dtable( lua_State *L )
{
    return vlclua_get_object( L, vlclua_get_dtable );
}

vlc_interrupt_t *vlclua_set_interrupt( lua_State *L )
{
    vlclua_dtable_t *dt = vlclua_get_dtable( L );
    return vlc_interrupt_set( dt->interrupt );
}

/** Maps an OS file descriptor to a VLC Lua file descriptor */
static int vlclua_fd_map( lua_State *L, int fd )
{
    vlclua_dtable_t *dt = vlclua_get_dtable( L );

    /* A failed net_Connect*() returns -1. Casting that value to unsigned
     * before checking it made it look larger than 3, so it was inserted in
     * the Lua descriptor table and returned to scripts as descriptor 3.
     * They would then poll/send on a phantom socket forever instead of
     * handling the connection failure (notably eMule's EC bootstrap). */
    if( fd < 0 || (unsigned)fd < 3u )
        return -1;

#ifndef NDEBUG
    for( unsigned i = 0; i < dt->fdc; i++ )
        assert( dt->fdv[i] != fd );
#endif

    for( unsigned i = 0; i < dt->fdc; i++ )
    {
        if( dt->fdv[i] == -1 )
        {
            dt->fdv[i] = fd;
            return 3 + i;
        }
    }

    if( dt->fdc >= 64 )
        return -1;

    int *fdv = realloc( dt->fdv, (dt->fdc + 1) * sizeof (dt->fdv[0]) );
    if( unlikely(fdv == NULL) )
        return -1;

    dt->fdv = fdv;
    dt->fdv[dt->fdc] = fd;
    fd = 3 + dt->fdc;
    dt->fdc++;
    return fd;
}

static int vlclua_fd_map_safe( lua_State *L, int fd )
{
    int luafd = vlclua_fd_map( L, fd );
    if( luafd == -1 )
        net_Close( fd );
    return luafd;
}

/** Gets the OS file descriptor mapped to a VLC Lua file descriptor */
static int vlclua_fd_get( lua_State *L, unsigned idx )
{
    vlclua_dtable_t *dt = vlclua_get_dtable( L );

    if( idx < 3u )
        return idx;
    idx -= 3;
    return (idx < dt->fdc) ? dt->fdv[idx] : -1;
}

/** Gets the VLC Lua file descriptor mapped from an OS file descriptor */
static int vlclua_fd_get_lua( lua_State *L, int fd )
{
    vlclua_dtable_t *dt = vlclua_get_dtable( L );

    if( (unsigned)fd < 3u )
        return fd;
    for( unsigned i = 0; i < dt->fdc; i++ )
        if( dt->fdv[i] == fd )
            return 3 + i;
    return -1;
}

/** Unmaps an OS file descriptor from VLC Lua */
static void vlclua_fd_unmap( lua_State *L, unsigned idx )
{
    vlclua_dtable_t *dt = vlclua_get_dtable( L );
    int fd;

    if( idx < 3u )
        return; /* Never close stdin/stdout/stderr. */

    idx -= 3;
    if( idx >= dt->fdc )
        return;

    fd = dt->fdv[idx];
    dt->fdv[idx] = -1;
    while( dt->fdc > 0 && dt->fdv[dt->fdc - 1] == -1 )
        dt->fdc--;
    /* realloc() not really needed */
#ifndef NDEBUG
    for( unsigned i = 0; i < dt->fdc; i++ )
        assert( dt->fdv[i] != fd );
#else
    (void) fd;
#endif
}

static void vlclua_fd_unmap_safe( lua_State *L, unsigned idx )
{
    int fd = vlclua_fd_get( L, idx );

    vlclua_fd_unmap( L, idx );
    if( fd != -1 )
        net_Close( fd );
}

/*****************************************************************************
 * Net listen
 *****************************************************************************/
static int vlclua_net_listen_close( lua_State * );
static int vlclua_net_accept( lua_State * );
static int vlclua_net_fds( lua_State * );
static int vlclua_net_port( lua_State * );

static const luaL_Reg vlclua_net_listen_reg[] = {
    { "accept", vlclua_net_accept },
    { "fds", vlclua_net_fds },
    { "port", vlclua_net_port },
    { "close", vlclua_net_listen_close },
    { NULL, NULL }
};

static int vlclua_net_listen_tcp( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_host = luaL_checkstring( L, 1 );
    int i_port = luaL_checkint( L, 2 );
    int *pi_fd = NULL;

    /* net_ListenTCP() on Jaguar rejects service "0" before bind(), while
     * binding port zero is precisely the race-free way to ask the kernel for
     * a private local port.  Extensions use this for short-lived loopback
     * relays, so provide that narrow, IPv4-only case directly. */
    if( i_port == 0 && !strcmp( psz_host, "127.0.0.1" ) )
    {
        int fd = vlc_socket( AF_INET, SOCK_STREAM, IPPROTO_TCP, true );
        if( fd != -1 )
        {
            struct sockaddr_in addr;
            memset( &addr, 0, sizeof( addr ) );
            addr.sin_family = AF_INET;
            addr.sin_port = htons( 0 );
            addr.sin_addr.s_addr = htonl( INADDR_LOOPBACK );
            if( bind( fd, (const struct sockaddr *)&addr, sizeof( addr ) ) == 0
             && listen( fd, 4 ) == 0 )
            {
                pi_fd = malloc( 2 * sizeof( *pi_fd ) );
                if( pi_fd != NULL )
                {
                    pi_fd[0] = fd;
                    pi_fd[1] = -1;
                }
                else
                    net_Close( fd );
            }
            else
                net_Close( fd );
        }
    }
    else
        pi_fd = net_ListenTCP( p_this, psz_host, i_port );
    if( pi_fd == NULL )
        return luaL_error( L, "Cannot listen on %s:%d", psz_host, i_port );

    for( unsigned i = 0; pi_fd[i] != -1; i++ )
        if( vlclua_fd_map( L, pi_fd[i] ) == -1 )
        {
            while( i > 0 )
                vlclua_fd_unmap( L, vlclua_fd_get_lua( L, pi_fd[--i] ) );

            net_ListenClose( pi_fd );
            return luaL_error( L, "Cannot listen on %s:%d", psz_host, i_port );
        }

    int **ppi_fd = lua_newuserdata( L, sizeof( int * ) );
    *ppi_fd = pi_fd;

    if( luaL_newmetatable( L, "net_listen" ) )
    {
        lua_newtable( L );
        luaL_register( L, NULL, vlclua_net_listen_reg );
        lua_setfield( L, -2, "__index" );
        lua_pushcfunction( L, vlclua_net_listen_close );
        lua_setfield( L, -2, "__gc" );
    }

    lua_setmetatable( L, -2 );
    return 1;
}

static int vlclua_net_listen_close( lua_State *L )
{
    int **ppi_fd = (int**)luaL_checkudata( L, 1, "net_listen" );
    int *pi_fd = *ppi_fd;

    if( pi_fd == NULL )
        return 0;

    for( unsigned i = 0; pi_fd[i] != -1; i++ )
        vlclua_fd_unmap( L, vlclua_fd_get_lua( L, pi_fd[i] ) );

    net_ListenClose( pi_fd );
    *ppi_fd = NULL;
    return 0;
}

static int vlclua_net_fds( lua_State *L )
{
    int **ppi_fd = (int**)luaL_checkudata( L, 1, "net_listen" );
    int *pi_fd = *ppi_fd;

    if( pi_fd == NULL )
        return 0;

    int i_count = 0;
    while( pi_fd[i_count] != -1 )
        lua_pushinteger( L, vlclua_fd_get_lua( L, pi_fd[i_count++] ) );

    return i_count;
}

/* Return the effective TCP port of a listener.  Passing port 0 to
 * vlc.net.listen_tcp() is the only race-free way for an extension to obtain
 * a private loopback port, but until now Lua had no way to find out which
 * port the kernel selected. */
static int vlclua_net_port( lua_State *L )
{
    int **ppi_fd = (int**)luaL_checkudata( L, 1, "net_listen" );
    struct sockaddr_storage addr;
    socklen_t i_len = sizeof( addr );

    if( *ppi_fd == NULL || (*ppi_fd)[0] == -1
     || getsockname( (*ppi_fd)[0], (struct sockaddr *)&addr, &i_len ) )
        return 0;

    lua_pushinteger( L, ntohs( net_GetPort( (struct sockaddr *)&addr ) ) );
    return 1;
}

static int vlclua_net_accept( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    int **ppi_fd = (int**)luaL_checkudata( L, 1, "net_listen" );
    if( *ppi_fd == NULL )
    {
        lua_pushinteger( L, -1 );
        return 1;
    }
    int i_fd = net_Accept( p_this, *ppi_fd );

    lua_pushinteger( L, vlclua_fd_map_safe( L, i_fd ) );
    return 1;
}

/*****************************************************************************
 *
 *****************************************************************************/
static int vlclua_net_connect_tcp( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_host = luaL_checkstring( L, 1 );
    int i_port = luaL_checkint( L, 2 );
    int i_timeout = luaL_optinteger( L, 3, -1 );
    int i_old_timeout = 0;
    int i_old_type = 0;

    /* net_ConnectTCP() uses the inherited ipv4-timeout setting.  Extensions
     * that probe many peer addresses need a much shorter per-address limit,
     * especially on slow machines.  Override it only for this synchronous
     * call, then restore the extension object's previous state. */
    if( i_timeout >= 0 )
    {
        if( i_timeout < 50 )
            i_timeout = 50;
        else if( i_timeout > 60000 )
            i_timeout = 60000;
        i_old_type = var_Type( p_this, "ipv4-timeout" );
        if( i_old_type == 0 )
            var_Create( p_this, "ipv4-timeout", VLC_VAR_INTEGER );
        i_old_timeout = var_GetInteger( p_this, "ipv4-timeout" );
        var_SetInteger( p_this, "ipv4-timeout", i_timeout );
    }
    int i_fd = -1;
#ifdef _WIN32
    /* Winsock SOCKET values are not MSVCRT file descriptors. vlc_dup() uses
     * _dup() on Windows, so applying it to vlc_tls_GetFD() fails with EBADF
     * after the TCP handshake; closing the wrapper then leaves Lua with -1.
     * This manifested as Soulseek failing outright and aMule accepting and
     * immediately losing a new EC connection twice a second. The direct
     * connector returns ownership of the Winsock socket and already honors
     * the temporary ipv4-timeout value above. */
    i_fd = net_ConnectTCP( p_this, psz_host, i_port );
#else
    /* The stream-access TCP path uses the newer resolver/socket race and is
     * reliable on Jaguar, while the historical net_ConnectTCP() path can
     * reject an otherwise reachable IPv4 endpoint there. Keep Lua's raw-fd
     * API by duplicating the connected socket before releasing its wrapper. */
    vlc_tls_t *p_socket = vlc_tls_SocketOpenTCP( p_this, psz_host, i_port );
    if( p_socket != NULL )
    {
        i_fd = vlc_dup( vlc_tls_GetFD( p_socket ) );
        vlc_tls_Close( p_socket );
    }
#endif
    if( i_timeout >= 0 )
    {
        var_SetInteger( p_this, "ipv4-timeout", i_old_timeout );
        if( i_old_type == 0 )
            var_Destroy( p_this, "ipv4-timeout" );
    }
    lua_pushinteger( L, vlclua_fd_map_safe( L, i_fd ) );
    return 1;
}

static int vlclua_net_close( lua_State *L )
{
    int i_fd = luaL_checkint( L, 1 );
    vlclua_fd_unmap_safe( L, i_fd );
    return 0;
}

static int vlclua_net_send( lua_State *L )
{
    int fd = vlclua_fd_get( L, luaL_checkint( L, 1 ) );
    size_t i_len;
    const char *psz_buffer = luaL_checklstring( L, 2, &i_len );

    i_len = (size_t)luaL_optinteger( L, 3, i_len );
    lua_pushinteger( L,
        (fd != -1) ? send( fd, psz_buffer, i_len, MSG_NOSIGNAL ) : -1 );
    return 1;
}

static int vlclua_net_recv( lua_State *L )
{
    int fd = vlclua_fd_get( L, luaL_checkint( L, 1 ) );
    size_t i_len = (size_t)luaL_optinteger( L, 2, 1 );
    char psz_buffer[i_len];

    ssize_t i_ret = (fd != -1) ? recv( fd, psz_buffer, i_len, 0 ) : -1;
    if( i_ret > 0 )
        lua_pushlstring( L, psz_buffer, i_ret );
    else
        lua_pushnil( L );
    return 1;
}

static bool ascii_header_name_equals( const char *psz_name, size_t i_len,
                                      const char *psz_expected )
{
    size_t i_expected = strlen( psz_expected );
    if( i_len != i_expected )
        return false;
    for( size_t i = 0; i < i_len; ++i )
    {
        unsigned char left = (unsigned char)psz_name[i];
        unsigned char right = (unsigned char)psz_expected[i];
        /* Jaguar's locale-backed tolower() is not reliable in a plug-in
         * loaded by a process whose locale was initialized before libintl.
         * HTTP field names are ASCII by definition, so fold them directly. */
        if( left >= 'A' && left <= 'Z' ) left += 'a' - 'A';
        if( right >= 'A' && right <= 'Z' ) right += 'a' - 'A';
        if( left != right )
            return false;
    }
    return true;
}

static bool ssdp_header( const char *psz_reply, size_t i_reply,
                         const char *psz_name, const char **ppsz_value,
                         size_t *pi_value )
{
    const char *p = psz_reply, *p_end = psz_reply + i_reply;
    while( p < p_end )
    {
        const char *p_line_end = memchr( p, '\n', (size_t)(p_end - p) );
        if( p_line_end == NULL )
            p_line_end = p_end;
        const char *p_colon = memchr( p, ':', (size_t)(p_line_end - p) );
        if( p_colon != NULL && ascii_header_name_equals( p,
                (size_t)(p_colon - p), psz_name ) )
        {
            const char *p_value = p_colon + 1;
            while( p_value < p_line_end &&
                   (*p_value == ' ' || *p_value == '\t') )
                ++p_value;
            const char *p_value_end = p_line_end;
            while( p_value_end > p_value &&
                   (p_value_end[-1] == '\r' || p_value_end[-1] == ' ' ||
                    p_value_end[-1] == '\t') )
                --p_value_end;
            if( p_value_end > p_value )
            {
                *ppsz_value = p_value;
                *pi_value = (size_t)(p_value_end - p_value);
                return true;
            }
            return false;
        }
        p = p_line_end < p_end ? p_line_end + 1 : p_end;
    }
    return false;
}

/* Generic SSDP M-SEARCH used by PowerVLC's UPnP modules. Unlike the older
 * IGD convenience call this returns every unique LOCATION, so media servers
 * and SAT>IP devices can share the same small UDP implementation.
 *
 * vlc.net.ssdp_discover( target-or-target-table [, timeout_ms] )
 *   -> { { location=..., st=..., usn=..., server=... }, ... }
 */
static int vlclua_net_ssdp_discover( lua_State *L )
{
    int i_timeout = luaL_optinteger( L, 2, 1800 );
    if( i_timeout < 200 ) i_timeout = 200;
    else if( i_timeout > 10000 ) i_timeout = 10000;

    int fd = vlc_socket( AF_INET, SOCK_DGRAM, IPPROTO_UDP, true );
    if( fd == -1 )
    {
        lua_pushnil( L );
        lua_pushliteral( L, "cannot create SSDP discovery socket" );
        return 2;
    }

    struct sockaddr_in dst;
    memset( &dst, 0, sizeof( dst ) );
    dst.sin_family = AF_INET;
    dst.sin_port = htons( 1900 );
    dst.sin_addr.s_addr = htonl( 0xEFFFFFFA ); /* 239.255.255.250 */

    size_t i_targets = lua_istable( L, 1 ) ? lua_objlen( L, 1 ) : 1;
    for( size_t i = 0; i < i_targets; ++i )
    {
        const char *psz_target;
        if( lua_istable( L, 1 ) )
        {
            lua_rawgeti( L, 1, (int)i + 1 );
            psz_target = luaL_checkstring( L, -1 );
        }
        else
            psz_target = luaL_checkstring( L, 1 );

        char psz_request[512];
        int i_request = snprintf( psz_request, sizeof( psz_request ),
            "M-SEARCH * HTTP/1.1\r\n"
            "HOST: 239.255.255.250:1900\r\n"
            "MAN: \"ssdp:discover\"\r\n"
            "MX: 1\r\n"
            "ST: %s\r\n\r\n", psz_target );
        if( i_request > 0 && (size_t)i_request < sizeof( psz_request ) )
            sendto( fd, psz_request, (size_t)i_request, 0,
                    (const struct sockaddr *)&dst, sizeof( dst ) );
        if( lua_istable( L, 1 ) ) lua_pop( L, 1 );
    }

    lua_newtable( L );
    char **ppsz_seen = NULL;
    size_t i_seen = 0;
    vlc_tick_t i_deadline = mdate() + (vlc_tick_t)i_timeout * 1000;
    while( !vlc_killed() )
    {
        vlc_tick_t i_now = mdate();
        if( i_now >= i_deadline ) break;
        int i_left = (int)((i_deadline - i_now + 999) / 1000);
        /* The Jaguar select()-backed poll compatibility layer historically
         * recognised POLLRDNORM but not Darwin's distinct POLLIN bit. */
        struct pollfd ufd = { .fd = fd, .events = POLLRDNORM };
        int val = vlc_poll_i11e( &ufd, 1, i_left );
        if( val == -1 && errno == EINTR ) continue;
        if( val <= 0 ) break;

        char psz_reply[8193];
        ssize_t i_reply = recvfrom( fd, psz_reply, sizeof( psz_reply ) - 1,
                                    0, NULL, NULL );
        if( i_reply <= 0 ) continue;
        psz_reply[i_reply] = '\0';

        const char *psz_location; size_t i_location;
        if( !ssdp_header( psz_reply, (size_t)i_reply, "location",
                          &psz_location, &i_location ) )
            continue;

        bool b_duplicate = false;
        for( size_t i = 0; i < i_seen; ++i )
            if( strlen( ppsz_seen[i] ) == i_location &&
                !memcmp( ppsz_seen[i], psz_location, i_location ) )
            { b_duplicate = true; break; }
        if( b_duplicate ) continue;

        char *psz_copy = strndup( psz_location, i_location );
        char **ppsz_new = realloc( ppsz_seen,
                                   (i_seen + 1) * sizeof( *ppsz_seen ) );
        if( psz_copy == NULL || ppsz_new == NULL )
        { free( psz_copy ); break; }
        ppsz_seen = ppsz_new;
        ppsz_seen[i_seen++] = psz_copy;

        lua_newtable( L );
        lua_pushlstring( L, psz_location, i_location );
        lua_setfield( L, -2, "location" );
        const char *psz_value; size_t i_value;
        const char *const ppsz_headers[] = { "st", "usn", "server" };
        for( size_t i = 0; i < ARRAY_SIZE( ppsz_headers ); ++i )
            if( ssdp_header( psz_reply, (size_t)i_reply, ppsz_headers[i],
                             &psz_value, &i_value ) )
            {
                lua_pushlstring( L, psz_value, i_value );
                lua_setfield( L, -2, ppsz_headers[i] );
            }
        lua_rawseti( L, -2, (int)i_seen );
    }

    for( size_t i = 0; i < i_seen; ++i ) free( ppsz_seen[i] );
    free( ppsz_seen );
    net_Close( fd );
    return 1;
}

/* Discover an Internet Gateway Device without pulling libupnp into the Lua
 * plug-in.  The actual device description and SOAP actions are handled by
 * vlc.http in Lua; this small UDP step is all that HTTP cannot provide. */
static int vlclua_net_upnp_discover( lua_State *L )
{
    int i_timeout = luaL_optinteger( L, 1, 1600 );
    if( i_timeout < 200 )
        i_timeout = 200;
    else if( i_timeout > 5000 )
        i_timeout = 5000;

    int fd = vlc_socket( AF_INET, SOCK_DGRAM, IPPROTO_UDP, true );
    if( fd == -1 )
        goto error_socket;

    const char *const ppsz_targets[] = {
        "upnp:rootdevice",
        "urn:schemas-upnp-org:device:InternetGatewayDevice:1",
        "urn:schemas-upnp-org:device:InternetGatewayDevice:2",
        "urn:schemas-upnp-org:service:WANIPConnection:1",
        "urn:schemas-upnp-org:service:WANIPConnection:2",
        "urn:schemas-upnp-org:service:WANPPPConnection:1",
        "ssdp:all",
    };
    struct sockaddr_in dst;
    memset( &dst, 0, sizeof( dst ) );
    dst.sin_family = AF_INET;
    dst.sin_port = htons( 1900 );
    dst.sin_addr.s_addr = htonl( 0xEFFFFFFA ); /* 239.255.255.250 */

    /* Select the interface carrying the default route explicitly.  This is
     * needed not only on multi-homed Windows hosts: Jaguar may otherwise pick
     * loopback for 239/8 when no multicast route has been installed yet. */
    struct in_addr local_addr;
    local_addr.s_addr = htonl( INADDR_ANY );
    /* Route probing must be synchronous. With a non-blocking UDP socket,
     * connect() can report EINPROGRESS on Jaguar and local_addr remains
     * INADDR_ANY, silently skipping the multicast membership below. */
    int route_fd = vlc_socket( AF_INET, SOCK_DGRAM, IPPROTO_UDP, false );
    if( route_fd != -1 )
    {
        struct sockaddr_in route_dst = dst;
        /* Query the default unicast route, not 224.0.0.0/4: Windows creates
         * an equal-cost multicast route for disconnected adapters too.  A
         * UDP connect sends no packet and TEST-NET-1 is never contacted. */
        route_dst.sin_port = htons( 9 );
        route_dst.sin_addr.s_addr = htonl( 0xC0000201 ); /* 192.0.2.1 */
        struct sockaddr_in local;
        socklen_t local_len = sizeof( local );
        if( connect( route_fd, (const struct sockaddr *)&route_dst,
                     sizeof( route_dst ) ) == 0 &&
            getsockname( route_fd, (struct sockaddr *)&local, &local_len ) == 0 )
        {
            local_addr = local.sin_addr;
            setsockopt( fd, IPPROTO_IP, IP_MULTICAST_IF,
                        (const char *)&local_addr, sizeof( local_addr ) );
        }
        net_Close( route_fd );
    }

#ifdef __APPLE__
    /* Jaguar does not deliver SSDP replies on this Ethernet interface until
     * the client has joined 239.255.255.250. Bind to the SSDP port as well:
     * this emits the IGMP membership report old switches expect and matches
     * the behaviour of period UPnP clients. */
    if( local_addr.s_addr != htonl( INADDR_ANY ) )
    {
        int reuse = 1;
        setsockopt( fd, SOL_SOCKET, SO_REUSEADDR,
                    (const char *)&reuse, sizeof( reuse ) );
# ifdef SO_REUSEPORT
        setsockopt( fd, SOL_SOCKET, SO_REUSEPORT,
                    (const char *)&reuse, sizeof( reuse ) );
# endif
        struct sockaddr_in bind_addr;
        memset( &bind_addr, 0, sizeof( bind_addr ) );
        bind_addr.sin_family = AF_INET;
        bind_addr.sin_port = htons( 1900 );
        bind_addr.sin_addr.s_addr = htonl( INADDR_ANY );
        bind( fd, (const struct sockaddr *)&bind_addr, sizeof( bind_addr ) );

        struct ip_mreq membership;
        membership.imr_multiaddr = dst.sin_addr;
        membership.imr_interface = local_addr;
        setsockopt( fd, IPPROTO_IP, IP_ADD_MEMBERSHIP,
                    (const char *)&membership, sizeof( membership ) );
    }
#endif

    for( size_t i = 0; i < ARRAY_SIZE( ppsz_targets ); ++i )
    {
        char psz_request[512];
        int i_request = snprintf( psz_request, sizeof( psz_request ),
            "M-SEARCH * HTTP/1.1\r\n"
            "HOST: 239.255.255.250:1900\r\n"
            "MAN: \"ssdp:discover\"\r\n"
            "MX: 1\r\n"
            "ST: %s\r\n\r\n", ppsz_targets[i] );
        if( i_request > 0 && (size_t)i_request < sizeof( psz_request ) )
            sendto( fd, psz_request, (size_t)i_request, 0,
                    (const struct sockaddr *)&dst, sizeof( dst ) );
    }

    vlc_tick_t i_deadline = mdate() + (vlc_tick_t)i_timeout * 1000;
    while( !vlc_killed() )
    {
        vlc_tick_t i_now = mdate();
        if( i_now >= i_deadline )
            break;
        int i_left = (int)((i_deadline - i_now + 999) / 1000);
        struct pollfd ufd = { .fd = fd, .events = POLLRDNORM };
        int val = vlc_poll_i11e( &ufd, 1, i_left );
        if( val == -1 && errno == EINTR )
            continue;
        if( val <= 0 )
            break;

        char psz_reply[8193];
        struct sockaddr_storage peer;
        socklen_t i_peer = sizeof( peer );
        ssize_t i_reply = recvfrom( fd, psz_reply, sizeof( psz_reply ) - 1, 0,
                                    (struct sockaddr *)&peer, &i_peer );
        if( i_reply <= 0 )
            continue;
        psz_reply[i_reply] = '\0';

        const char *psz_location = NULL;
        size_t i_location = 0;
        const char *p = psz_reply, *p_end = psz_reply + i_reply;
        while( p < p_end )
        {
            const char *p_line_end = memchr( p, '\n', (size_t)(p_end - p) );
            if( p_line_end == NULL )
                p_line_end = p_end;
            const char *p_colon = memchr( p, ':', (size_t)(p_line_end - p) );
            if( p_colon != NULL &&
                ascii_header_name_equals( p, (size_t)(p_colon - p), "location" ) )
            {
                const char *p_value = p_colon + 1;
                while( p_value < p_line_end &&
                       (*p_value == ' ' || *p_value == '\t') )
                    ++p_value;
                const char *p_value_end = p_line_end;
                while( p_value_end > p_value &&
                       (p_value_end[-1] == '\r' || p_value_end[-1] == ' ' ||
                        p_value_end[-1] == '\t') )
                    --p_value_end;
                if( p_value_end > p_value )
                {
                    psz_location = p_value;
                    i_location = (size_t)(p_value_end - p_value);
                }
                break;
            }
            p = p_line_end < p_end ? p_line_end + 1 : p_end;
        }
        if( psz_location == NULL )
            continue;

        char psz_local[NI_MAXNUMERICHOST];
        struct sockaddr_storage local;
        socklen_t i_local = sizeof( local );
        int i_port = 0;
        if( connect( fd, (struct sockaddr *)&peer, i_peer ) ||
            getsockname( fd, (struct sockaddr *)&local, &i_local ) ||
            vlc_getnameinfo( (struct sockaddr *)&local, i_local, psz_local,
                             sizeof( psz_local ), &i_port, NI_NUMERICHOST ) )
            continue;

        lua_pushlstring( L, psz_location, i_location );
        lua_pushstring( L, psz_local );
        net_Close( fd );
        return 2;
    }

    net_Close( fd );
    lua_pushnil( L );
    lua_pushliteral( L, "no UPnP Internet Gateway Device found" );
    return 2;

error_socket:
    lua_pushnil( L );
    lua_pushliteral( L, "cannot create UPnP discovery socket" );
    return 2;
}

/*****************************************************************************
 *
 *****************************************************************************/
/* Takes a { fd : events } table as first arg and modifies it to { fd : revents } */
static int vlclua_net_poll( lua_State *L )
{
    luaL_checktype( L, 1, LUA_TTABLE );
    int i_timeout = luaL_optinteger( L, 2, -1 );

    int i_fds = 0;
    lua_pushnil( L );
    while( lua_next( L, 1 ) )
    {
        i_fds++;
        lua_pop( L, 1 );
    }

    if( i_fds == 0 )
    {
        lua_pushinteger( L, 0 );
        return 1;
    }

    struct pollfd *p_fds = xmalloc( i_fds * sizeof( *p_fds ) );
    int *luafds = xmalloc( i_fds * sizeof( *luafds ) );

    lua_pushnil( L );
    for( int i = 0; lua_next( L, 1 ); i++ )
    {
        luafds[i] = luaL_checkint( L, -2 );
        p_fds[i].fd = vlclua_fd_get( L, luafds[i] );
        p_fds[i].events = luaL_checkinteger( L, -1 );
        p_fds[i].events &= POLLIN | POLLOUT | POLLPRI;
        lua_pop( L, 1 );
    }

    vlc_interrupt_t *oint = vlclua_set_interrupt( L );
    int ret = 1, val = -1;

    do
    {
        if( vlc_killed() )
            break;
        val = vlc_poll_i11e( p_fds, i_fds, i_timeout );
    }
    while( val == -1 && errno == EINTR );

    vlc_interrupt_set( oint );

    for( int i = 0; i < i_fds; i++ )
    {
        lua_pushinteger( L, luafds[i] );
        lua_pushinteger( L, (val >= 0) ? p_fds[i].revents : 0 );
        lua_settable( L, 1 );
    }
    lua_pushinteger( L, val );

    free( luafds );
    free( p_fds );

    if( val == -1 )
        return luaL_error( L, "Interrupted." );
    return ret;
}

/*****************************************************************************
 *
 *****************************************************************************/
/*
static int vlclua_fd_open( lua_State *L )
{
}
*/

#ifndef _WIN32
static int vlclua_fd_write( lua_State *L )
{
    int fd = vlclua_fd_get( L, luaL_checkint( L, 1 ) );
    size_t i_len;
    const char *psz_buffer = luaL_checklstring( L, 2, &i_len );

    i_len = (size_t)luaL_optinteger( L, 3, i_len );
    lua_pushinteger( L, (fd != -1) ? vlc_write( fd, psz_buffer, i_len ) : -1 );
    return 1;
}

static int vlclua_fd_read( lua_State *L )
{
    int fd = vlclua_fd_get( L, luaL_checkint( L, 1 ) );
    size_t i_len = (size_t)luaL_optinteger( L, 2, 1 );
    char psz_buffer[i_len];

    ssize_t i_ret = (fd != -1) ? read( fd, psz_buffer, i_len ) : -1;
    if( i_ret > 0 )
        lua_pushlstring( L, psz_buffer, i_ret );
    else
        lua_pushnil( L );
    return 1;
}
#endif

/*****************************************************************************
 *
 *****************************************************************************/
static int vlclua_stat( lua_State *L )
{
    const char *psz_path = luaL_checkstring( L, 1 );
    struct stat s;
    if( vlc_stat( psz_path, &s ) )
        return 0;
        //return luaL_error( L, "Couldn't stat %s.", psz_path );
    lua_newtable( L );
    if( S_ISREG( s.st_mode ) )
        lua_pushliteral( L, "file" );
    else if( S_ISDIR( s.st_mode ) )
        lua_pushliteral( L, "dir" );
#ifdef S_ISCHR
    else if( S_ISCHR( s.st_mode ) )
        lua_pushliteral( L, "character device" );
#endif
#ifdef S_ISBLK
    else if( S_ISBLK( s.st_mode ) )
        lua_pushliteral( L, "block device" );
#endif
#ifdef S_ISFIFO
    else if( S_ISFIFO( s.st_mode ) )
        lua_pushliteral( L, "fifo" );
#endif
#ifdef S_ISLNK
    else if( S_ISLNK( s.st_mode ) )
        lua_pushliteral( L, "symbolic link" );
#endif
#ifdef S_ISSOCK
    else if( S_ISSOCK( s.st_mode ) )
        lua_pushliteral( L, "socket" );
#endif
    else
        lua_pushliteral( L, "unknown" );
    lua_setfield( L, -2, "type" );
    lua_pushinteger( L, s.st_mode );
    lua_setfield( L, -2, "mode" );
    lua_pushinteger( L, s.st_uid );
    lua_setfield( L, -2, "uid" );
    lua_pushinteger( L, s.st_gid );
    lua_setfield( L, -2, "gid" );
    lua_pushinteger( L, s.st_size );
    lua_setfield( L, -2, "size" );
    lua_pushinteger( L, s.st_atime );
    lua_setfield( L, -2, "access_time" );
    lua_pushinteger( L, s.st_mtime );
    lua_setfield( L, -2, "modification_time" );
    lua_pushinteger( L, s.st_ctime );
    lua_setfield( L, -2, "creation_time" );
    return 1;
}

static int vlclua_opendir( lua_State *L )
{
    const char *psz_dir = luaL_checkstring( L, 1 );
    DIR *p_dir;
    int i = 0;

    if( ( p_dir = vlc_opendir( psz_dir ) ) == NULL )
        return luaL_error( L, "cannot open directory `%s'.", psz_dir );

    lua_newtable( L );
    for( ;; )
    {
        const char *psz_filename = vlc_readdir( p_dir );
        if( !psz_filename ) break;
        i++;
        lua_pushstring( L, psz_filename );
        lua_rawseti( L, -2, i );
    }
    closedir( p_dir );
    return 1;
}

/*****************************************************************************
 *
 *****************************************************************************/
static const luaL_Reg vlclua_net_intf_reg[] = {
    { "listen_tcp", vlclua_net_listen_tcp },
    { "connect_tcp", vlclua_net_connect_tcp },
    { "close", vlclua_net_close },
    { "send", vlclua_net_send },
    { "recv", vlclua_net_recv },
    { "upnp_discover", vlclua_net_upnp_discover },
    { "ssdp_discover", vlclua_net_ssdp_discover },
    { "poll", vlclua_net_poll },
#ifndef _WIN32
    { "read", vlclua_fd_read },
    { "write", vlclua_fd_write },
#endif
    /* The following functions do not depend on intf_thread_t and do not really
     * belong in net.* but are left here for backward compatibility: */
    { "url_parse", vlclua_url_parse /* deprecated since 3.0.0 */ },
    { "stat", vlclua_stat }, /* Not really "net" */
    { "opendir", vlclua_opendir }, /* Not really "net" */
    { NULL, NULL }
};

static void luaopen_net_intf( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_net_intf_reg );
#define ADD_CONSTANT( value )    \
    lua_pushinteger( L, POLL##value ); \
    lua_setfield( L, -2, "POLL"#value );
    ADD_CONSTANT( IN )
    ADD_CONSTANT( PRI )
    ADD_CONSTANT( OUT )
    ADD_CONSTANT( ERR )
    ADD_CONSTANT( HUP )
    ADD_CONSTANT( NVAL )
    lua_setfield( L, -2, "net" );
}

int vlclua_fd_init( lua_State *L, vlclua_dtable_t *dt )
{
    dt->interrupt = vlc_interrupt_create();
    if( unlikely(dt->interrupt == NULL) )
        return -1;
    dt->fdv = NULL;
    dt->fdc = 0;
    vlclua_set_object( L, vlclua_get_dtable, dt );
    luaopen_net_intf( L );
    return 0;
}

void vlclua_fd_interrupt( vlclua_dtable_t *dt )
{
    vlc_interrupt_kill( dt->interrupt );
}

/** Releases all (leaked) VLC Lua file descriptors. */
void vlclua_fd_cleanup( vlclua_dtable_t *dt )
{
    for( unsigned i = 0; i < dt->fdc; i++ )
        if( dt->fdv[i] != -1 )
            net_Close( dt->fdv[i] );
    free( dt->fdv );
    vlc_interrupt_destroy(dt->interrupt);
}
