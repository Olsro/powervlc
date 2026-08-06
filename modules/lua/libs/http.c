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

/* vlc.stream() only issues GET requests and lets a script set no header at
 * all, which covers a plain read-only API and nothing else. Two things need
 * more: a POST for authentication (e.g. Jellyfin's
 * /Users/AuthenticateByName), and a GET carrying the session a site handed
 * out -- Cookie, and the User-Agent that session was issued to. So this
 * binding sends the request over the core's own TLS/TCP layer and returns
 * the raw answer to the script. */

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
#include <vlc_http.h>
#include <vlc_playlist.h>

#ifdef HAVE_ZLIB_H
# include <zlib.h>
#endif

#include "../vlc.h"
#include "../libs.h"

/* Authentication answers are a few kilobytes, a search page a few hundred;
 * anything close to this cap means the script is talking to the wrong
 * endpoint. */
#define HTTP_MAX_REPLY (8u << 20)

/* Enough to leave a redirect loop, few enough to notice one. */
#define HTTP_MAX_REDIRECTS 4

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
            if( i_cap >= HTTP_MAX_REPLY )
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

/* A site that fingerprints Accept-Encoding leaves no choice: the header has
 * to go out exactly as the browser sent it, so the answer comes back
 * compressed and has to be undone here. Returns a new buffer, or NULL when
 * the encoding is one we cannot undo -- better an error than a body of
 * binary rubbish handed to the script as if it were a page. */
static char *Inflate( const char *p_in, size_t i_in, size_t *pi_out )
{
#ifdef HAVE_ZLIB_H
    z_stream s;
    memset( &s, 0, sizeof( s ) );
    /* 32 lets zlib work out gzip or zlib framing on its own */
    if( inflateInit2( &s, 32 + MAX_WBITS ) != Z_OK )
        return NULL;

    size_t i_cap = i_in * 4 + 16384;
    char *p_out = malloc( i_cap );
    if( p_out == NULL )
    {
        inflateEnd( &s );
        return NULL;
    }

    s.next_in = (Bytef *)p_in;
    s.avail_in = (uInt)i_in;
    s.next_out = (Bytef *)p_out;
    s.avail_out = (uInt)i_cap;

    for( ;; )
    {
        int i_ret = inflate( &s, Z_NO_FLUSH );
        if( i_ret == Z_STREAM_END )
            break;
        if( i_ret != Z_OK )
        {
            inflateEnd( &s );
            free( p_out );
            return NULL;
        }
        if( s.avail_out != 0 )
            continue; /* input exhausted before the end of the stream */

        if( i_cap >= HTTP_MAX_REPLY )
        {
            inflateEnd( &s );
            free( p_out );
            return NULL;
        }
        size_t i_used = i_cap - s.avail_out;
        i_cap *= 2;
        char *p_new = realloc( p_out, i_cap );
        if( p_new == NULL )
        {
            inflateEnd( &s );
            free( p_out );
            return NULL;
        }
        p_out = p_new;
        s.next_out = (Bytef *)(p_out + i_used);
        s.avail_out = (uInt)(i_cap - i_used);
    }

    *pi_out = i_cap - s.avail_out;
    inflateEnd( &s );
    return p_out;
#else
    (void)p_in; (void)i_in; (void)pi_out;
    return NULL;
#endif
}

/*****************************************************************************
 * One request, one connection
 *****************************************************************************/

/* Sends psz_req (and psz_body, when there is one) to the host named by the
 * URL, and reads the whole answer back. Returns it, or NULL and an error
 * message in *ppsz_err. */
static char *Transact( vlc_object_t *p_this, const vlc_url_t *p_url,
                       bool b_tls, const char *psz_req,
                       const char *psz_body, size_t i_body,
                       size_t *pi_reply, const char **ppsz_err )
{
    unsigned i_port = p_url->i_port ? p_url->i_port : (b_tls ? 443 : 80);

    vlc_tls_creds_t *p_creds = NULL;
    vlc_tls_t *p_tls;
    if( b_tls )
    {
        p_creds = vlc_tls_ClientCreate( p_this );
        if( p_creds == NULL )
        {
            *ppsz_err = "TLS unavailable";
            return NULL;
        }
        p_tls = vlc_tls_SocketOpenTLS( p_creds, p_url->psz_host, i_port,
                                       "https", NULL, NULL );
    }
    else
        p_tls = vlc_tls_SocketOpenTCP( p_this, p_url->psz_host, i_port );

    if( p_tls == NULL )
    {
        if( p_creds != NULL )
            vlc_tls_Delete( p_creds );
        *ppsz_err = "connection failed";
        return NULL;
    }

    char *p_reply = NULL;
    if( vlc_tls_Write( p_tls, psz_req, strlen( psz_req ) ) >= 0
     && (i_body == 0 || vlc_tls_Write( p_tls, psz_body, i_body ) >= 0) )
        p_reply = ReadAll( p_tls, pi_reply );

    vlc_tls_Close( p_tls );
    if( p_creds != NULL )
        vlc_tls_Delete( p_creds );

    if( p_reply == NULL || *pi_reply == 0 )
    {
        free( p_reply );
        *ppsz_err = "no response";
        return NULL;
    }
    return p_reply;
}

static char *HeaderGet( const char *psz_hdr, const char *psz_name );

/* True when the header block announces chunked framing.
 *
 * Read as a header rather than looked for as one literal string. The value
 * is free to be spelled "Chunked", to be pushed away from the colon by any
 * amount of space, or to name other codings alongside -- and getting it
 * wrong is silent and total: the chunk sizes stay in the body and the
 * script is handed "229b\r\n[[..." where it expected a document. */
static bool ReplyIsChunked( const char *psz_hdr )
{
    char *psz_te = HeaderGet( psz_hdr, "Transfer-Encoding" );
    bool b_chunked = false;

    if( psz_te != NULL )
    {
        for( char *p = psz_te; *p; p++ )
            *p = tolower( (unsigned char)*p );
        b_chunked = strstr( psz_te, "chunked" ) != NULL;
        free( psz_te );
    }
    return b_chunked;
}

/* Splits a reply into its status, its header block and its body. The header
 * block is nul-terminated in place; the body keeps its own length, so it
 * may hold nul bytes. */
static bool SplitReply( char *p_reply, size_t i_reply, int *pi_status,
                        char **pp_hdr, char **pp_body, size_t *pi_body )
{
    if( i_reply < 13 || memcmp( p_reply, "HTTP/", 5 ) )
        return false;

    /* An interim answer -- "100 Continue" and its kind -- is a whole
     * header block of its own, ending in the very blank line the real one
     * is looked for by. Stepping over it keeps the search below from
     * stopping on the wrong reply and taking the real headers for the
     * body. */
    for( ;; )
    {
        int i_interim = atoi( p_reply + 9 );
        if( i_interim < 100 || i_interim >= 200 )
            break;

        char *p_next = NULL;
        for( size_t i = 0; i + 3 < i_reply; i++ )
            if( !memcmp( p_reply + i, "\r\n\r\n", 4 ) )
            {
                p_next = p_reply + i + 4;
                break;
            }
        if( p_next == NULL )
            return false;

        i_reply -= (size_t)(p_next - p_reply);
        p_reply = p_next;
        if( i_reply < 13 || memcmp( p_reply, "HTTP/", 5 ) )
            return false;
    }

    char *p_body = NULL;
    for( size_t i = 0; i + 3 < i_reply; i++ )
        if( !memcmp( p_reply + i, "\r\n\r\n", 4 ) )
        {
            p_body = p_reply + i + 4;
            break;
        }
    if( p_body == NULL )
        return false;

    *pi_status = atoi( p_reply + 9 );
    if( *pi_status == 0 )
        return false;

    size_t i_len = i_reply - (size_t)(p_body - p_reply);

    /* nul-terminates the header block, which is handed back untouched:
     * a Set-Cookie value is case-sensitive */
    p_body[-2] = '\0';
    if( ReplyIsChunked( p_reply ) )
        i_len = Dechunk( p_body, i_len );

    *pp_hdr = p_reply;
    *pp_body = p_body;
    *pi_body = i_len;
    return true;
}

/* Reads one header out of a nul-terminated header block, case-insensitively.
 * Returns a copy, or NULL. */
static char *HeaderGet( const char *psz_hdr, const char *psz_name )
{
    const size_t i_name = strlen( psz_name );

    for( const char *p = psz_hdr; p != NULL; )
    {
        const char *psz_eol = strstr( p, "\r\n" );
        if( !strncasecmp( p, psz_name, i_name ) && p[i_name] == ':' )
        {
            p += i_name + 1;
            while( *p == ' ' || *p == '\t' )
                p++;
            size_t i_len = psz_eol ? (size_t)(psz_eol - p) : strlen( p );
            return strndup( p, i_len );
        }
        p = psz_eol ? psz_eol + 2 : NULL;
    }
    return NULL;
}

/* A header a script hands us goes out verbatim, so it must not be able to
 * smuggle a second request in. */
static bool HeaderSane( const char *psz_name, const char *psz_value )
{
    if( psz_name == NULL || psz_value == NULL || *psz_name == '\0' )
        return false;
    return strpbrk( psz_name, "\r\n:" ) == NULL
        && strpbrk( psz_value, "\r\n" ) == NULL;
}

/* Turns the { name = value } table at the given index into header lines.
 * Returns an allocated block ("" when there is none), or NULL on error. */
static char *HeadersBuild( lua_State *L, int idx )
{
    if( lua_isnoneornil( L, idx ) )
        return strdup( "" );
    if( !lua_istable( L, idx ) )
        return NULL;

    char *psz_out = strdup( "" );
    lua_pushnil( L );
    while( psz_out != NULL && lua_next( L, idx ) != 0 )
    {
        /* lua_tostring() on the key would rewrite it in place and break
         * lua_next(), so only take real strings */
        if( lua_type( L, -2 ) == LUA_TSTRING && lua_isstring( L, -1 ) )
        {
            const char *psz_name = lua_tostring( L, -2 );
            const char *psz_value = lua_tostring( L, -1 );
            if( HeaderSane( psz_name, psz_value ) )
            {
                char *psz_new;
                if( asprintf( &psz_new, "%s%s: %s\r\n", psz_out, psz_name,
                              psz_value ) < 0 )
                    psz_new = NULL;
                free( psz_out );
                psz_out = psz_new;
            }
        }
        lua_pop( L, 1 );
    }
    return psz_out;
}

/* True when the script already set that header, so that a default never
 * goes out twice. */
static bool HeadersHave( const char *psz_headers, const char *psz_name )
{
    char *psz_found = HeaderGet( psz_headers, psz_name );
    bool b_have = psz_found != NULL;
    free( psz_found );
    return b_have;
}

/* A request with no User-Agent at all is not merely unusual, it gets turned
 * away: measured against a public Invidious instance, the very same GET
 * answers 403 without the header and 200 with any value in it. So say who
 * we are, using the name the rest of the player goes by -- unless the
 * script is replaying a session issued to a browser, in which case it
 * passes that browser's own name and this stays out of the way. */
static char *DefaultAgent( vlc_object_t *p_this, const char *psz_headers )
{
    if( HeadersHave( psz_headers, "User-Agent" ) )
        return strdup( "" );

    char *psz_ua = var_InheritString( p_this, "http-user-agent" );
    char *psz_line;
    if( asprintf( &psz_line, "User-Agent: %s\r\n",
                  psz_ua ? psz_ua : "PowerVLC" ) < 0 )
        psz_line = NULL;
    free( psz_ua );
    return psz_line;
}

/* Splits a URL and says whether it speaks TLS. */
static bool UrlSplit( const char *psz_url, vlc_url_t *p_url, bool *pb_tls )
{
    if( vlc_UrlParse( p_url, psz_url ) != 0 || p_url->psz_host == NULL
     || p_url->psz_protocol == NULL )
        return false;

    if( !strcasecmp( p_url->psz_protocol, "https" ) )
        *pb_tls = true;
    else if( !strcasecmp( p_url->psz_protocol, "http" ) )
        *pb_tls = false;
    else
        return false;
    return true;
}

/* Hands back the body ready to use, undoing any Content-Encoding. Returns
 * false when the encoding is one we cannot undo. *pp_free is what the
 * caller must release afterwards. */
static bool BodyPlain( const char *psz_hdr, char *p_body, size_t i_body,
                       const char **pp_out, size_t *pi_out, char **pp_free )
{
    *pp_out = p_body;
    *pi_out = i_body;
    *pp_free = NULL;

    char *psz_enc = HeaderGet( psz_hdr, "Content-Encoding" );
    if( psz_enc == NULL || *psz_enc == '\0'
     || !strcasecmp( psz_enc, "identity" ) )
    {
        free( psz_enc );
        return true;
    }
    free( psz_enc );

    size_t i_plain = 0;
    char *p_plain = Inflate( p_body, i_body, &i_plain );
    if( p_plain == NULL )
        return false;

    *pp_out = p_plain;
    *pi_out = i_plain;
    *pp_free = p_plain;
    return true;
}

/*****************************************************************************
 * vlc.http.get( url [, headers [, no_redirect]] )
 * Returns the status code, the body and the raw header block, or nil and an
 * error message.
 *****************************************************************************/
static int vlclua_http_get( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_start = luaL_checkstring( L, 1 );
    char *psz_headers = HeadersBuild( L, 2 );
    bool b_follow = !lua_toboolean( L, 3 );

    if( psz_headers == NULL )
    {
        lua_pushnil( L );
        lua_pushliteral( L, "invalid headers" );
        return 2;
    }

    char *psz_agent = DefaultAgent( p_this, psz_headers );
    /* a script replaying a browser session sends its own Accept */
    const char *psz_accept = HeadersHave( psz_headers, "Accept" )
                           ? "" : "Accept: */*\r\n";
    char *psz_url = strdup( psz_start );
    const char *psz_err = "out of memory";
    char *p_reply = NULL;
    int i_status = 0;
    char *p_hdr = NULL, *p_body = NULL;
    size_t i_reply = 0, i_body = 0;

    for( int i_hop = 0; psz_url != NULL && i_hop <= HTTP_MAX_REDIRECTS;
         i_hop++ )
    {
        vlc_url_t url;
        bool b_tls;
        if( !UrlSplit( psz_url, &url, &b_tls ) )
        {
            vlc_UrlClean( &url );
            psz_err = "invalid URL";
            break;
        }

        /* HTTP/1.0 on purpose: the answer simply ends with the connection,
         * no chunked framing, no keep-alive to time out on. */
        char *psz_req;
        int i_req = asprintf( &psz_req,
            /* HTTP/1.1, but asking the server to close: announcing 1.0
             * is a plain "not a browser" tell to the guards in front of
             * these sites, while "Connection: close" keeps the answer
             * ending with the connection, exactly as before. A server
             * that chunks anyway is undone by Dechunk(). */
            "GET %s%s%s HTTP/1.1\r\n"
            "Host: %s\r\n"
            "%s"
            "%s%s"
            "Connection: close\r\n"
            "\r\n",
            (url.psz_path && url.psz_path[0]) ? url.psz_path : "/",
            url.psz_option ? "?" : "", url.psz_option ? url.psz_option : "",
            url.psz_host, psz_accept,
            psz_agent ? psz_agent : "", psz_headers );

        if( i_req == -1 )
        {
            vlc_UrlClean( &url );
            break;
        }

        free( p_reply );
        p_reply = Transact( p_this, &url, b_tls, psz_req, NULL, 0, &i_reply,
                            &psz_err );
        free( psz_req );

        if( p_reply == NULL )
        {
            vlc_UrlClean( &url );
            break;
        }
        /* keep the failure test on SplitReply itself: i_status carries the
         * previous hop's value, so it says nothing about this one */
        bool b_split = SplitReply( p_reply, i_reply, &i_status, &p_hdr,
                                   &p_body, &i_body );

        /* One line per hop. A body that reaches a script in the wrong shape
         * is otherwise indistinguishable from a site that answered badly,
         * and the script only ever reports what it made of it. No %zu here:
         * Jaguar's printf does not know it. */
        msg_Dbg( p_this, "http: %s -> %s, status %d, %lu byte(s) read, "
                 "%lu of body, transfer-encoding %s", psz_url,
                 b_split ? "ok" : "malformed", i_status,
                 (unsigned long)i_reply, (unsigned long)i_body,
                 b_split && ReplyIsChunked( p_hdr ) ? "chunked" : "none" );

        if( !b_split )
        {
            vlc_UrlClean( &url );
            psz_err = "malformed response";
            free( p_reply );
            p_reply = NULL;
            break;
        }
        char *psz_next = NULL;
        if( b_follow && i_status >= 300 && i_status < 400 )
        {
            char *psz_loc = HeaderGet( p_hdr, "Location" );
            if( psz_loc != NULL && *psz_loc != '\0' )
            {
                if( strstr( psz_loc, "://" ) != NULL )
                    psz_next = psz_loc;
                else
                {
                    /* a bare path: keep the origin we are already on */
                    char psz_port[8] = "";
                    if( url.i_port != 0 )
                        snprintf( psz_port, sizeof( psz_port ), ":%u",
                                  (unsigned)url.i_port );
                    if( asprintf( &psz_next, "%s://%s%s%s%s",
                                  b_tls ? "https" : "http", url.psz_host,
                                  psz_port, psz_loc[0] == '/' ? "" : "/",
                                  psz_loc ) < 0 )
                        psz_next = NULL;
                    free( psz_loc );
                }
            }
            else
                free( psz_loc );
        }
        vlc_UrlClean( &url );

        if( psz_next == NULL )
        {
            free( psz_url );
            psz_url = NULL;
            free( psz_headers );
            free( psz_agent );

            const char *p_out; size_t i_out; char *p_free;
            if( !BodyPlain( p_hdr, p_body, i_body, &p_out, &i_out, &p_free ) )
            {
                free( p_reply );
                lua_pushnil( L );
                lua_pushliteral( L, "unsupported content encoding" );
                return 2;
            }
            lua_pushinteger( L, i_status );
            lua_pushlstring( L, p_out, i_out );
            lua_pushstring( L, p_hdr );
            free( p_free );
            free( p_reply );
            return 3;
        }

        free( psz_url );
        psz_url = psz_next;
        psz_err = "too many redirects";
    }

    free( psz_url );
    free( psz_headers );
    free( psz_agent );
    free( p_reply );
    lua_pushnil( L );
    lua_pushstring( L, psz_err );
    return 2;
}

/*****************************************************************************
 * vlc.http.post( url, body [, content_type [, authorization [, headers]]] )
 * Returns the HTTP status code and the response body, or nil and an
 * error message.
 *****************************************************************************/
static int vlclua_http_post( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_url = luaL_checkstring( L, 1 );
    size_t i_body;
    const char *psz_body = luaL_optlstring( L, 2, "", &i_body );
    const char *psz_ctype = luaL_optstring( L, 3, "application/json" );
    const char *psz_auth = luaL_optstring( L, 4, NULL );
    char *psz_headers = HeadersBuild( L, 5 );
    char *psz_agent = DefaultAgent( p_this, psz_headers );

    if( psz_headers == NULL )
    {
        lua_pushnil( L );
        lua_pushliteral( L, "invalid headers" );
        return 2;
    }

    vlc_url_t url;
    bool b_tls;
    if( !UrlSplit( psz_url, &url, &b_tls ) )
    {
        vlc_UrlClean( &url );
        free( psz_headers );
        lua_pushnil( L );
        lua_pushliteral( L, "invalid or unsupported URL" );
        return 2;
    }

    /* HTTP/1.0 on purpose: the answer simply ends with the connection,
     * no chunked framing, no keep-alive to time out on. */
    char *psz_req;
    int i_req = asprintf( &psz_req,
        "POST %s%s%s HTTP/1.0\r\n"
        "Host: %s\r\n"
        "%s"
        "Content-Type: %s\r\n"
        "Content-Length: %zu\r\n"
        "%s%s%s"
        "%s"
        "Connection: close\r\n"
        "\r\n",
        (url.psz_path && url.psz_path[0]) ? url.psz_path : "/",
        url.psz_option ? "?" : "", url.psz_option ? url.psz_option : "",
        url.psz_host, psz_agent ? psz_agent : "", psz_ctype, i_body,
        psz_auth ? "Authorization: " : "",
        psz_auth ? psz_auth : "", psz_auth ? "\r\n" : "",
        psz_headers );
    free( psz_headers );
    free( psz_agent );

    const char *psz_err = "out of memory";
    char *p_reply = NULL;
    size_t i_reply = 0;

    if( i_req != -1 )
    {
        p_reply = Transact( p_this, &url, b_tls, psz_req, psz_body, i_body,
                            &i_reply, &psz_err );
        free( psz_req );
    }
    vlc_UrlClean( &url );

    if( p_reply == NULL )
    {
        lua_pushnil( L );
        lua_pushstring( L, psz_err );
        return 2;
    }

    int i_status = 0;
    char *p_hdr = NULL, *p_out = NULL;
    size_t i_out = 0;
    if( !SplitReply( p_reply, i_reply, &i_status, &p_hdr, &p_out, &i_out ) )
    {
        free( p_reply );
        lua_pushnil( L );
        lua_pushliteral( L, "malformed response" );
        return 2;
    }

    const char *p_plain; size_t i_plain; char *p_free;
    if( !BodyPlain( p_hdr, p_out, i_out, &p_plain, &i_plain, &p_free ) )
    {
        free( p_reply );
        lua_pushnil( L );
        lua_pushliteral( L, "unsupported content encoding" );
        return 2;
    }
    lua_pushinteger( L, i_status );
    lua_pushlstring( L, p_plain, i_plain );
    lua_pushstring( L, p_hdr );
    free( p_free );
    free( p_reply );
    return 3;
}

/*****************************************************************************
 * vlc.http.setcookie( url, "name=value; path=/" )
 *
 * Puts a cookie in the jar the player shares with its HTTP access, so that
 * playback itself carries a session a script obtained on its own -- a
 * stream proxied by a site that sits behind an anti-bot check would 403
 * otherwise. Returns true on success.
 *****************************************************************************/
static int vlclua_http_setcookie( lua_State *L )
{
    const char *psz_url = luaL_checkstring( L, 1 );
    const char *psz_cookie = luaL_checkstring( L, 2 );

    playlist_t *p_playlist = vlclua_get_playlist_internal( L );
    if( p_playlist == NULL )
    {
        lua_pushboolean( L, 0 );
        return 1;
    }

    vlc_http_cookie_jar_t *p_jar =
        var_GetAddress( p_playlist, "http-cookies" );
    if( p_jar == NULL )
    {
        lua_pushboolean( L, 0 );
        return 1;
    }

    vlc_url_t url;
    bool b_tls;
    if( !UrlSplit( psz_url, &url, &b_tls ) )
    {
        vlc_UrlClean( &url );
        lua_pushboolean( L, 0 );
        return 1;
    }

    bool b_ok = vlc_http_cookies_store( p_jar, psz_cookie, url.psz_host,
        (url.psz_path && url.psz_path[0]) ? url.psz_path : "/" );
    vlc_UrlClean( &url );

    lua_pushboolean( L, b_ok );
    return 1;
}

static const luaL_Reg vlclua_http_reg[] = {
    { "get", vlclua_http_get },
    { "post", vlclua_http_post },
    { "setcookie", vlclua_http_setcookie },
    { NULL, NULL }
};

void luaopen_http( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_http_reg );
    lua_setfield( L, -2, "http" );
}
