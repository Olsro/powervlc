/*****************************************************************************
 * http.c: minimal HTTP(S) client requests for Lua scripts
 *****************************************************************************
 * Copyright (C) 2026 the PowerVLC team
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

/* vlc.stream() only issues GET requests, which covers every read-only API.
 * Some services however require a POST for authentication (e.g. Jellyfin's
 * /Users/AuthenticateByName), so this binding sends one request over the
 * core's own TLS/TCP layer and returns the raw answer to the script. */

#ifndef  _GNU_SOURCE
#   define  _GNU_SOURCE
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <stdbool.h>
#include <ctype.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_url.h>
#include <vlc_tls.h>

#include "../vlc.h"
#include "../libs.h"

/* Authentication answers are a few kilobytes; anything close to this cap
 * means the script is talking to the wrong endpoint. */
#define HTTP_POST_MAX_REPLY (8u << 20)

static char *ReadAll( vlc_tls_t *tls, size_t *pi_len )
{
    size_t i_size = 0, i_cap = 16384;
    char *p_buf = malloc( i_cap );
    if( p_buf == NULL )
        return NULL;

    for( ;; )
    {
        if( i_cap - i_size < 4096 )
        {
            if( i_cap >= HTTP_POST_MAX_REPLY )
                break;
            i_cap *= 2;
            char *p = realloc( p_buf, i_cap );
            if( p == NULL )
            {
                free( p_buf );
                return NULL;
            }
            p_buf = p;
        }
        ssize_t val = vlc_tls_Read( tls, p_buf + i_size, i_cap - i_size - 1,
                                    false );
        if( val <= 0 )
            break;
        i_size += (size_t)val;
    }

    p_buf[i_size] = '\0'; /* strtoul()/strstr() must never run off the end */
    *pi_len = i_size;
    return p_buf;
}

/* "Transfer-Encoding: chunked" is illegal towards our HTTP/1.0 request, but
 * a misbehaving proxy may still send it: undo it in place rather than hand
 * chunk sizes to the script. */
static size_t Dechunk( char *p_body, size_t i_len )
{
    size_t i_in = 0, i_out = 0;
    while( i_in < i_len )
    {
        unsigned long i_chunk = strtoul( p_body + i_in, NULL, 16 );
        if( i_chunk == 0 )
            break;
        const char *p_eol = memchr( p_body + i_in, '\n', i_len - i_in );
        if( p_eol == NULL )
            break;
        i_in = (size_t)(p_eol - p_body) + 1;
        if( i_chunk > i_len - i_in )
            i_chunk = i_len - i_in;
        memmove( p_body + i_out, p_body + i_in, i_chunk );
        i_out += i_chunk;
        i_in += i_chunk + 2; /* CRLF after the chunk data */
    }
    return i_out;
}

/* vlc.http.post( url, body [, content_type [, authorization]] )
 * Returns the HTTP status code and the response body, or nil and an
 * error message. */
static int vlclua_http_post( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_url = luaL_checkstring( L, 1 );
    size_t i_body;
    const char *psz_body = luaL_optlstring( L, 2, "", &i_body );
    const char *psz_ctype = luaL_optstring( L, 3, "application/json" );
    const char *psz_auth = luaL_optstring( L, 4, NULL );

    vlc_url_t url;
    if( vlc_UrlParse( &url, psz_url ) != 0 || url.psz_host == NULL
     || url.psz_protocol == NULL )
    {
        vlc_UrlClean( &url );
        lua_pushnil( L );
        lua_pushliteral( L, "invalid URL" );
        return 2;
    }

    bool b_tls;
    if( !strcasecmp( url.psz_protocol, "https" ) )
        b_tls = true;
    else if( !strcasecmp( url.psz_protocol, "http" ) )
        b_tls = false;
    else
    {
        vlc_UrlClean( &url );
        lua_pushnil( L );
        lua_pushliteral( L, "unsupported protocol" );
        return 2;
    }
    unsigned i_port = url.i_port ? url.i_port : (b_tls ? 443 : 80);

    vlc_tls_creds_t *p_creds = NULL;
    vlc_tls_t *p_tls;
    if( b_tls )
    {
        p_creds = vlc_tls_ClientCreate( p_this );
        if( p_creds == NULL )
        {
            vlc_UrlClean( &url );
            lua_pushnil( L );
            lua_pushliteral( L, "TLS unavailable" );
            return 2;
        }
        p_tls = vlc_tls_SocketOpenTLS( p_creds, url.psz_host, i_port,
                                       "https", NULL, NULL );
    }
    else
        p_tls = vlc_tls_SocketOpenTCP( p_this, url.psz_host, i_port );

    if( p_tls == NULL )
    {
        if( p_creds != NULL )
            vlc_tls_Delete( p_creds );
        vlc_UrlClean( &url );
        lua_pushnil( L );
        lua_pushliteral( L, "connection failed" );
        return 2;
    }

    /* HTTP/1.0 on purpose: the answer simply ends with the connection,
     * no chunked framing, no keep-alive to time out on. */
    char *psz_req;
    int i_req = asprintf( &psz_req,
        "POST %s%s%s HTTP/1.0\r\n"
        "Host: %s\r\n"
        "User-Agent: PowerVLC-Lua\r\n"
        "Content-Type: %s\r\n"
        "Content-Length: %zu\r\n"
        "%s%s%s"
        "Connection: close\r\n"
        "\r\n",
        (url.psz_path && url.psz_path[0]) ? url.psz_path : "/",
        url.psz_option ? "?" : "", url.psz_option ? url.psz_option : "",
        url.psz_host, psz_ctype, i_body,
        psz_auth ? "Authorization: " : "",
        psz_auth ? psz_auth : "", psz_auth ? "\r\n" : "" );
    vlc_UrlClean( &url );

    int i_status = 0;
    char *p_reply = NULL;
    size_t i_reply = 0;

    if( i_req != -1 )
    {
        if( vlc_tls_Write( p_tls, psz_req, strlen( psz_req ) ) >= 0
         && (i_body == 0 || vlc_tls_Write( p_tls, psz_body, i_body ) >= 0) )
            p_reply = ReadAll( p_tls, &i_reply );
        free( psz_req );
    }

    vlc_tls_Close( p_tls );
    if( p_creds != NULL )
        vlc_tls_Delete( p_creds );

    if( p_reply == NULL || i_reply == 0 )
    {
        free( p_reply );
        lua_pushnil( L );
        lua_pushliteral( L, "no response" );
        return 2;
    }

    /* Status line, then headers up to the empty line */
    if( i_reply > 12 && !memcmp( p_reply, "HTTP/", 5 ) )
        i_status = atoi( p_reply + 9 );

    char *p_body = NULL;
    for( size_t i = 0; i + 3 < i_reply; i++ )
        if( !memcmp( p_reply + i, "\r\n\r\n", 4 ) )
        {
            p_body = p_reply + i + 4;
            break;
        }

    if( i_status == 0 || p_body == NULL )
    {
        free( p_reply );
        lua_pushnil( L );
        lua_pushliteral( L, "malformed response" );
        return 2;
    }

    size_t i_hdr = (size_t)(p_body - p_reply);
    size_t i_len = i_reply - i_hdr;

    /* case-insensitive search bounded to the header block */
    p_reply[i_hdr - 1] = '\0';
    for( char *p = p_reply; *p; p++ )
        *p = tolower( (unsigned char)*p );
    if( strstr( p_reply, "transfer-encoding: chunked" ) != NULL )
        i_len = Dechunk( p_body, i_len );

    lua_pushinteger( L, i_status );
    lua_pushlstring( L, p_body, i_len );
    free( p_reply );
    return 2;
}

static const luaL_Reg vlclua_http_reg[] = {
    { "post", vlclua_http_post },
    { NULL, NULL }
};

void luaopen_http( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_http_reg );
    lua_setfield( L, -2, "http" );
}
