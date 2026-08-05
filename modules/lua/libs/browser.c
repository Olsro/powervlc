/*****************************************************************************
 * browser.c: hand an anti-bot challenge over to the user's own browser
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

/* A growing number of sites put a JavaScript proof-of-work (Anubis) or a
 * captcha in front of every page. PowerVLC does not solve those: it hands
 * the job to the browser the user already has -- even a Mac OS X 10.4
 * machine runs a current one -- and takes back the session the browser
 * legitimately earned.
 *
 * The handover needs somewhere for the browser to come back to, so this
 * binding puts a one-shot HTTP server on the loopback interface, behind an
 * unguessable path. Two pages live there: the instructions, and the return
 * point the browser hits with the answer.
 *
 * Everything the server does happens in C. The httpd runs its callbacks on
 * its own thread, and an extension's lua_State belongs to the extension
 * thread alone: touching it from here would be a race. The script polls
 * instead, on its own thread, through the lock below.
 */

#ifndef  _GNU_SOURCE
#   define  _GNU_SOURCE
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <stdbool.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#ifndef _WIN32
# include <unistd.h>
# include <sys/wait.h>
#else
# include <windows.h>
# include <shellapi.h>
#endif

#include <vlc_common.h>
#include <vlc_httpd.h>
#include <vlc_rand.h>
#include <vlc_url.h>

#include "../vlc.h"
#include "../libs.h"

/* A cookie header runs to a few hundred bytes; past this the caller is
 * being fed something that is not a session. */
#define HANDOFF_ARG_MAX 8192

/* Kept short on purpose: every failed bind logs an error. */
#define HANDOFF_PORT_FIRST 15821
#define HANDOFF_PORT_LAST  15828

/* How long the relay tab is trusted to still be there after its last poll. */
#define HANDOFF_RELAY_STALE (CLOCK_FREQ * 5)

typedef struct
{
    vlc_object_t *p_owner;   /* carries http-host/http-port for the host */
    httpd_host_t *p_host;
    httpd_url_t  *p_url_landing;
    httpd_url_t  *p_url_return;
    httpd_url_t  *p_url_next;
    httpd_url_t  *p_url_reply;
    httpd_url_t  *p_url_inject;

    char *psz_base;          /* http://127.0.0.1:PORT/<secret> */
    char *psz_landing;       /* served on psz_base */
    char *psz_thanks;        /* served on the return point, answer in hand */
    char *psz_empty;         /* ... and when it came back empty-handed */
    /* The relay script, served rather than shipped: the browser add-on
     * that puts it on the page takes it from here, so a page and the
     * player it talks to can never be two different versions. */
    char *psz_inject;

    /* written by the httpd thread, read by the script's thread */
    vlc_mutex_t lock;
    vlc_cond_t  wait;

    /* the session, when the page was able to read one out */
    bool  b_answered;
    char *psz_cookie;
    char *psz_agent;
    char *psz_origin;
    /* Measured on go-away: the check is bound to the exact Accept-Language
     * and Accept-Encoding the browser sent when it earned the session --
     * change a single q-value and the answer is a fresh challenge. Neither
     * can be guessed, and a page's script cannot read what its own
     * navigation sent, so take them off the browser's own request here. */
    char *psz_language;
    char *psz_encoding;
    /* Counts what the browser has handed over. A click that repeats the
     * same cookie is still news -- the page behind it has changed -- so a
     * script must be able to tell "again" from "nothing new". */
    uint64_t i_answer_seq;

    /* the relay: a tab sitting on the site, fetching on our behalf. This
     * is what a cookie marked HttpOnly leaves as the only way in -- the
     * script never sees the session, the browser just uses it. */
    mtime_t   i_last_poll;   /* 0 until a tab shows up */
    char     *psz_pending;   /* handed out on the next poll */
    uint64_t  i_seq;         /* which request that is */
    uint64_t  i_reply_seq;   /* which one came back */
    int       i_reply_status;
    char     *p_reply;
    size_t    i_reply_len;
    /* The core's httpd answers 413 to any request body of 64 kB or more,
     * and an ordinary search page is past that, so the answer arrives in
     * slices and is put back together here. */
    char     *p_acc;
    size_t    i_acc;
    uint64_t  i_acc_seq;
} vlclua_handoff_t;

/* A page that does not fit in this was never the page we asked for. */
#define HANDOFF_REPLY_MAX (8u << 20)

/*****************************************************************************
 * Small string helpers
 *****************************************************************************/

/* Replaces every occurrence of psz_token in psz_in. Returns a new string,
 * or NULL. */
static char *ReplaceAll( const char *psz_in, const char *psz_token,
                         const char *psz_with )
{
    const size_t i_token = strlen( psz_token );
    const size_t i_with = strlen( psz_with );
    if( i_token == 0 )
        return strdup( psz_in );

    /* count first: one pass to size, one to fill, no realloc dance */
    size_t i_count = 0;
    for( const char *p = psz_in; (p = strstr( p, psz_token )) != NULL;
         p += i_token )
        i_count++;

    char *psz_out = malloc( strlen( psz_in ) + i_count * i_with
                            - i_count * i_token + 1 );
    if( psz_out == NULL )
        return NULL;

    char *q = psz_out;
    const char *p = psz_in;
    for( ;; )
    {
        const char *psz_hit = strstr( p, psz_token );
        if( psz_hit == NULL )
            break;
        memcpy( q, p, (size_t)(psz_hit - p) );
        q += psz_hit - p;
        memcpy( q, psz_with, i_with );
        q += i_with;
        p = psz_hit + i_token;
    }
    strcpy( q, p );
    return psz_out;
}

/* Fills a page's placeholders in. Returns a new string, or NULL. */
static char *Expand( const char *psz_in, const char *psz_return,
                     const char *psz_base, const char *psz_origin )
{
    char *psz_tmp = ReplaceAll( psz_in, "{{RETURN}}", psz_return );
    if( psz_tmp == NULL )
        return NULL;
    char *psz_mid = ReplaceAll( psz_tmp, "{{BASE}}", psz_base );
    free( psz_tmp );
    if( psz_mid == NULL )
        return NULL;
    /* the origin on its own: a page checks the sender of a postMessage
     * against it, and a path would never match */
    char *psz_out = ReplaceAll( psz_mid, "{{ORIGIN}}", psz_origin );
    free( psz_mid );
    return psz_out;
}

/* Pulls one parameter out of a query string, percent-decoded. '+' is left
 * alone: encodeURIComponent() escapes it, so a '+' here is a real one. */
static char *ArgGet( const char *psz_args, const char *psz_key )
{
    if( psz_args == NULL )
        return NULL;

    const size_t i_key = strlen( psz_key );
    for( const char *p = psz_args; *p != '\0'; )
    {
        const char *psz_amp = strchr( p, '&' );
        const size_t i_pair = psz_amp ? (size_t)(psz_amp - p) : strlen( p );

        if( i_pair > i_key && p[i_key] == '='
         && !strncmp( p, psz_key, i_key ) )
        {
            const size_t i_val = i_pair - i_key - 1;
            if( i_val > HANDOFF_ARG_MAX )
                return NULL;
            char *psz_raw = strndup( p + i_key + 1, i_val );
            if( psz_raw == NULL )
                return NULL;
            char *psz_val = vlc_uri_decode_duplicate( psz_raw );
            free( psz_raw );
            return psz_val;
        }

        if( psz_amp == NULL )
            break;
        p = psz_amp + 1;
    }
    return NULL;
}

/*****************************************************************************
 * HTTP answers -- httpd thread
 *****************************************************************************/

static void AnswerBody( httpd_message_t *answer, const httpd_message_t *query,
                        const char *psz_mime, const char *p_data,
                        size_t i_len, bool b_cors )
{
    answer->i_proto   = HTTPD_PROTO_HTTP;
    answer->i_version = 1;
    answer->i_type    = HTTPD_MSG_ANSWER;
    answer->i_status  = 200;

    httpd_MsgAdd( answer, "Content-Type", "%s", psz_mime );
    /* the pages carry a one-shot secret: never let anything keep them */
    httpd_MsgAdd( answer, "Cache-Control", "no-store" );
    /* The relay endpoints are read by a script running on the site's own
     * origin, so they have to say who may read them. Nothing here is worth
     * hiding from a page: the secret in the path is the actual guard. */
    if( b_cors )
        httpd_MsgAdd( answer, "Access-Control-Allow-Origin", "*" );

    if( query->i_type != HTTPD_MSG_HEAD && i_len > 0 )
    {
        answer->p_body = malloc( i_len );
        if( answer->p_body != NULL )
        {
            memcpy( answer->p_body, p_data, i_len );
            answer->i_body = (int)i_len;
        }
    }
    /* HEAD must still announce what a GET would send */
    httpd_MsgAdd( answer, "Content-Length", "%zu", i_len );
}

static void AnswerHtml( httpd_message_t *answer, const httpd_message_t *query,
                        const char *psz_html )
{
    AnswerBody( answer, query, "text/html; charset=utf-8", psz_html,
                strlen( psz_html ), false );
}

static int LandingCallback( httpd_callback_sys_t *opaque, httpd_client_t *cl,
                            httpd_message_t *answer,
                            const httpd_message_t *query )
{
    vlclua_handoff_t *p_ho = (vlclua_handoff_t *)opaque;
    VLC_UNUSED(cl);

    if( answer == NULL || query == NULL )
        return VLC_SUCCESS;

    AnswerHtml( answer, query, p_ho->psz_landing );
    return VLC_SUCCESS;
}

/* The relay script itself, for the browser add-on.
 *
 * Until Firefox 69 a bookmarklet counted as inline script, so a page
 * carrying "script-src 'self'" -- every Invidious instance does -- simply
 * refused to run it, and clicking the bookmark did nothing at all. Every
 * browser these machines can run is older than that, so the add-on puts
 * the script on the page from chrome, where no page policy reaches, and
 * fetches it here. */
static int InjectCallback( httpd_callback_sys_t *opaque, httpd_client_t *cl,
                           httpd_message_t *answer,
                           const httpd_message_t *query )
{
    vlclua_handoff_t *p_ho = (vlclua_handoff_t *)opaque;
    VLC_UNUSED(cl);

    if( answer == NULL || query == NULL )
        return VLC_SUCCESS;

    const char *psz_js = p_ho->psz_inject ? p_ho->psz_inject : "";
    AnswerBody( answer, query, "application/javascript; charset=utf-8",
                psz_js, strlen( psz_js ), true );
    return VLC_SUCCESS;
}

static int ReturnCallback( httpd_callback_sys_t *opaque, httpd_client_t *cl,
                           httpd_message_t *answer,
                           const httpd_message_t *query )
{
    vlclua_handoff_t *p_ho = (vlclua_handoff_t *)opaque;
    VLC_UNUSED(cl);

    if( answer == NULL || query == NULL )
        return VLC_SUCCESS;

    const char *psz_args = (const char *)query->psz_args;
    char *psz_cookie = ArgGet( psz_args, "c" );
    char *psz_agent  = ArgGet( psz_args, "ua" );
    char *psz_origin = ArgGet( psz_args, "o" );
    const char *psz_hdr_lang = httpd_MsgGet( query, "Accept-Language" );
    const char *psz_hdr_enc  = httpd_MsgGet( query, "Accept-Encoding" );

    /* The bookmarklet reports the browser's own User-Agent; should it ever
     * fail to, the request itself carries it. */
    if( psz_agent == NULL || *psz_agent == '\0' )
    {
        free( psz_agent );
        const char *psz_hdr = httpd_MsgGet( query, "User-Agent" );
        psz_agent = strdup( psz_hdr ? psz_hdr : "" );
    }

    bool b_got = psz_cookie != NULL && *psz_cookie != '\0';
    if( b_got )
    {
        vlc_mutex_lock( &p_ho->lock );
        free( p_ho->psz_cookie );
        free( p_ho->psz_agent );
        free( p_ho->psz_origin );
        free( p_ho->psz_language );
        free( p_ho->psz_encoding );
        p_ho->psz_cookie = psz_cookie;
        p_ho->psz_agent  = psz_agent;
        p_ho->psz_origin = psz_origin;
        p_ho->psz_language = strdup( psz_hdr_lang ? psz_hdr_lang : "" );
        p_ho->psz_encoding = strdup( psz_hdr_enc ? psz_hdr_enc : "" );
        p_ho->b_answered = true;
        p_ho->i_answer_seq++;
        vlc_mutex_unlock( &p_ho->lock );

        /* The three header values are what a guard fingerprints, so an
         * absent one has to be visible; their content is stable and does
         * not belong in a log line every time. */
        msg_Dbg( (vlc_object_t *)p_ho->p_owner,
                 "handover: cookie %zu bytes, agent %s, "
                 "Accept-Language %s, Accept-Encoding %s",
                 strlen( psz_cookie ),
                 (psz_agent && *psz_agent) ? "ok" : "MISSING",
                 (psz_hdr_lang && *psz_hdr_lang) ? "ok" : "MISSING",
                 (psz_hdr_enc && *psz_hdr_enc) ? "ok" : "MISSING" );
    }
    else
    {
        free( psz_cookie );
        free( psz_agent );
        free( psz_origin );
    }

    AnswerHtml( answer, query, b_got ? p_ho->psz_thanks : p_ho->psz_empty );
    return VLC_SUCCESS;
}

/* The relay tab asks here for something to fetch. It answers "<id> <url>",
 * or nothing at all when the player wants nothing.
 *
 * The httpd host runs one poll loop for every client it has, so this must
 * never wait: the tab asks again in a moment instead. */
static int NextCallback( httpd_callback_sys_t *opaque, httpd_client_t *cl,
                         httpd_message_t *answer,
                         const httpd_message_t *query )
{
    vlclua_handoff_t *p_ho = (vlclua_handoff_t *)opaque;
    VLC_UNUSED(cl);

    if( answer == NULL || query == NULL )
        return VLC_SUCCESS;

    char *psz_work = NULL;

    vlc_mutex_lock( &p_ho->lock );
    p_ho->i_last_poll = mdate();
    if( p_ho->psz_pending != NULL )
    {
        if( asprintf( &psz_work, "%llu %s",
                      (unsigned long long)p_ho->i_seq,
                      p_ho->psz_pending ) < 0 )
            psz_work = NULL;
        else
        {
            /* handed out once: a tab that dies mid-fetch times the script
             * out rather than making a second tab redo the same work */
            free( p_ho->psz_pending );
            p_ho->psz_pending = NULL;
        }
    }
    vlc_mutex_unlock( &p_ho->lock );

    if( psz_work != NULL )
        msg_Dbg( (vlc_object_t *)p_ho->p_owner, "relay: asked %s",
                 strchr( psz_work, ' ' ) ? strchr( psz_work, ' ' ) + 1
                                         : psz_work );

    AnswerBody( answer, query, "text/plain; charset=utf-8",
                psz_work ? psz_work : "", psz_work ? strlen( psz_work ) : 0,
                true );
    free( psz_work );
    return VLC_SUCCESS;
}

/* ... and posts the answer back here, with ?id=<id>&s=<http status>. */
static int ReplyCallback( httpd_callback_sys_t *opaque, httpd_client_t *cl,
                          httpd_message_t *answer,
                          const httpd_message_t *query )
{
    vlclua_handoff_t *p_ho = (vlclua_handoff_t *)opaque;
    VLC_UNUSED(cl);

    if( answer == NULL || query == NULL )
        return VLC_SUCCESS;

    const char *psz_args = (const char *)query->psz_args;
    char *psz_id = ArgGet( psz_args, "id" );
    char *psz_status = ArgGet( psz_args, "s" );
    char *psz_last = ArgGet( psz_args, "last" );

    vlc_mutex_lock( &p_ho->lock );
    p_ho->i_last_poll = mdate();

    /* An answer to a request the script already gave up on is dropped:
     * taking it would hand the next call somebody else's page. */
    if( psz_id != NULL
     && strtoull( psz_id, NULL, 10 ) == p_ho->i_seq
     && p_ho->i_reply_seq != p_ho->i_seq )
    {
        if( p_ho->i_acc_seq != p_ho->i_seq )
        {
            /* first slice of this answer */
            free( p_ho->p_acc );
            p_ho->p_acc = NULL;
            p_ho->i_acc = 0;
            p_ho->i_acc_seq = p_ho->i_seq;
        }

        const size_t i_add = query->i_body > 0 && query->p_body != NULL
                           ? (size_t)query->i_body : 0;
        if( i_add > 0 && p_ho->i_acc + i_add <= HANDOFF_REPLY_MAX )
        {
            char *p_new = realloc( p_ho->p_acc, p_ho->i_acc + i_add );
            if( p_new != NULL )
            {
                memcpy( p_new + p_ho->i_acc, query->p_body, i_add );
                p_ho->p_acc = p_new;
                p_ho->i_acc += i_add;
            }
        }

        if( psz_last != NULL && atoi( psz_last ) != 0 )
        {
            free( p_ho->p_reply );
            p_ho->p_reply = p_ho->p_acc;
            p_ho->i_reply_len = p_ho->i_acc;
            p_ho->p_acc = NULL;
            p_ho->i_acc = 0;
            p_ho->i_reply_status = psz_status ? atoi( psz_status ) : 200;
            p_ho->i_reply_seq = p_ho->i_seq;
            msg_Dbg( (vlc_object_t *)p_ho->p_owner,
                     "relay: got HTTP %s, %zu bytes",
                     psz_status ? psz_status : "?", p_ho->i_reply_len );
            vlc_cond_broadcast( &p_ho->wait );
        }
    }
    vlc_mutex_unlock( &p_ho->lock );

    free( psz_id );
    free( psz_status );
    free( psz_last );

    AnswerBody( answer, query, "text/plain", "ok", 2, true );
    return VLC_SUCCESS;
}

/*****************************************************************************
 * Lua object
 *****************************************************************************/

static void HandoffStop( vlclua_handoff_t *p_ho )
{
    /* httpd_UrlDelete() waits for the clients still inside a callback, so
     * nothing touches the struct once they are all gone. */
    if( p_ho->p_url_reply != NULL )
    {
        httpd_UrlDelete( p_ho->p_url_reply );
        p_ho->p_url_reply = NULL;
    }
    if( p_ho->p_url_inject != NULL )
    {
        httpd_UrlDelete( p_ho->p_url_inject );
        p_ho->p_url_inject = NULL;
    }
    if( p_ho->p_url_next != NULL )
    {
        httpd_UrlDelete( p_ho->p_url_next );
        p_ho->p_url_next = NULL;
    }
    if( p_ho->p_url_return != NULL )
    {
        httpd_UrlDelete( p_ho->p_url_return );
        p_ho->p_url_return = NULL;
    }
    if( p_ho->p_url_landing != NULL )
    {
        httpd_UrlDelete( p_ho->p_url_landing );
        p_ho->p_url_landing = NULL;
    }
    if( p_ho->p_host != NULL )
    {
        httpd_HostDelete( p_ho->p_host );
        p_ho->p_host = NULL;
    }
    if( p_ho->p_owner != NULL )
    {
        vlc_object_release( p_ho->p_owner );
        p_ho->p_owner = NULL;
    }

    free( p_ho->psz_base );
    free( p_ho->psz_landing );
    free( p_ho->psz_thanks );
    free( p_ho->psz_empty );
    free( p_ho->psz_inject );
    free( p_ho->psz_cookie );
    free( p_ho->psz_agent );
    free( p_ho->psz_origin );
    free( p_ho->psz_language );
    free( p_ho->psz_encoding );
    free( p_ho->psz_pending );
    free( p_ho->p_reply );
    free( p_ho->p_acc );
    p_ho->psz_pending = NULL;
    p_ho->p_reply = NULL;
    p_ho->p_acc = NULL;
    p_ho->i_reply_len = 0;
    p_ho->i_acc = 0;
    /* poll() reads these under the same lock and would hand out a freed
     * pointer otherwise */
    p_ho->b_answered = false;
    p_ho->i_last_poll = 0;
    p_ho->psz_base = p_ho->psz_landing = NULL;
    p_ho->psz_thanks = p_ho->psz_empty = NULL;
    p_ho->psz_inject = NULL;
    p_ho->psz_cookie = p_ho->psz_agent = p_ho->psz_origin = NULL;
    p_ho->psz_language = p_ho->psz_encoding = NULL;
}

static int vlclua_handoff_url( lua_State *L )
{
    vlclua_handoff_t *p_ho =
        (vlclua_handoff_t *)luaL_checkudata( L, 1, "vlc_handoff" );
    if( p_ho->psz_base == NULL )
        return luaL_error( L, "handover already closed" );
    lua_pushstring( L, p_ho->psz_base );
    return 1;
}

/* nil while nothing came back, otherwise the answer. */
static int vlclua_handoff_poll( lua_State *L )
{
    vlclua_handoff_t *p_ho =
        (vlclua_handoff_t *)luaL_checkudata( L, 1, "vlc_handoff" );

    vlc_mutex_lock( &p_ho->lock );
    bool b_answered = p_ho->b_answered && p_ho->psz_cookie != NULL;
    char *psz_cookie = b_answered ? strdup( p_ho->psz_cookie ) : NULL;
    char *psz_agent  = b_answered && p_ho->psz_agent
                     ? strdup( p_ho->psz_agent ) : NULL;
    char *psz_origin = b_answered && p_ho->psz_origin
                     ? strdup( p_ho->psz_origin ) : NULL;
    char *psz_language = b_answered && p_ho->psz_language
                       ? strdup( p_ho->psz_language ) : NULL;
    char *psz_encoding = b_answered && p_ho->psz_encoding
                       ? strdup( p_ho->psz_encoding ) : NULL;
    lua_Integer i_seq = (lua_Integer)p_ho->i_answer_seq;
    vlc_mutex_unlock( &p_ho->lock );

    if( !b_answered )
    {
        lua_pushnil( L );
        return 1;
    }

    lua_newtable( L );
    lua_pushstring( L, psz_cookie ? psz_cookie : "" );
    lua_setfield( L, -2, "cookie" );
    lua_pushstring( L, psz_agent ? psz_agent : "" );
    lua_setfield( L, -2, "user_agent" );
    lua_pushstring( L, psz_origin ? psz_origin : "" );
    lua_setfield( L, -2, "origin" );
    lua_pushstring( L, psz_language ? psz_language : "" );
    lua_setfield( L, -2, "accept_language" );
    lua_pushstring( L, psz_encoding ? psz_encoding : "" );
    lua_setfield( L, -2, "accept_encoding" );
    lua_pushinteger( L, i_seq );
    lua_setfield( L, -2, "seq" );

    free( psz_cookie );
    free( psz_agent );
    free( psz_origin );
    free( psz_language );
    free( psz_encoding );
    return 1;
}

/* True while a relay tab is there to fetch on our behalf. */
static int vlclua_handoff_relay( lua_State *L )
{
    vlclua_handoff_t *p_ho =
        (vlclua_handoff_t *)luaL_checkudata( L, 1, "vlc_handoff" );

    vlc_mutex_lock( &p_ho->lock );
    bool b_live = p_ho->i_last_poll != 0
               && mdate() - p_ho->i_last_poll < HANDOFF_RELAY_STALE;
    vlc_mutex_unlock( &p_ho->lock );

    lua_pushboolean( L, b_live );
    return 1;
}

/* The core kills an extension that has shown no sign of life for ten
 * seconds (WATCH_TIMER_PERIOD): it puts up "Extension not responding, kill
 * it?" and kills outright when it cannot even show that. Waiting on a
 * browser is not a hung script, so say so while waiting -- measured on a
 * Tiger machine, one request the tab never answered took the whole player
 * down with it, this local server included. */
#define HANDOFF_KEEPALIVE (CLOCK_FREQ * 2)

static void KeepAlive( lua_State *L )
{
    lua_getglobal( L, "vlc" );
    if( lua_istable( L, -1 ) )
    {
        lua_getfield( L, -1, "keep_alive" );
        if( lua_isfunction( L, -1 ) )
        {
            if( lua_pcall( L, 0, 0, 0 ) != 0 )
                lua_pop( L, 1 ); /* the error message */
        }
        else
            lua_pop( L, 1 );
    }
    lua_pop( L, 1 );
}

/* h:fetch( url [, timeout_seconds] )
 *
 * Has the relay tab fetch a URL of the site it is sitting on, and waits for
 * it. Returns the status code and the body, or nil and an error message.
 *
 * One request at a time: the script is a single thread and asks for one
 * page at a time anyway. */
static int vlclua_handoff_fetch( lua_State *L )
{
    vlclua_handoff_t *p_ho =
        (vlclua_handoff_t *)luaL_checkudata( L, 1, "vlc_handoff" );
    const char *psz_url = luaL_checkstring( L, 2 );
    lua_Integer i_timeout = luaL_optinteger( L, 3, 30 );

    if( i_timeout < 1 )
        i_timeout = 1;

    vlc_mutex_lock( &p_ho->lock );

    if( p_ho->i_last_poll == 0
     || mdate() - p_ho->i_last_poll >= HANDOFF_RELAY_STALE )
    {
        vlc_mutex_unlock( &p_ho->lock );
        lua_pushnil( L );
        lua_pushliteral( L, "no relay" );
        return 2;
    }

    free( p_ho->psz_pending );
    p_ho->psz_pending = strdup( psz_url );
    p_ho->i_seq++;
    const uint64_t i_seq = p_ho->i_seq;

    mtime_t i_deadline = mdate() + CLOCK_FREQ * (mtime_t)i_timeout;
    while( p_ho->i_reply_seq != i_seq )
    {
        mtime_t i_now = mdate();
        if( i_now >= i_deadline )
            break; /* timed out */
        /* The relay has stopped asking for work: it is busy with a check,
         * or it is gone. Either way nobody is going to answer this one,
         * and sitting out the whole timeout is what gets the extension
         * killed. */
        if( i_now - p_ho->i_last_poll >= HANDOFF_RELAY_STALE )
            break;

        mtime_t i_slice = i_now + HANDOFF_KEEPALIVE;
        if( i_slice > i_deadline )
            i_slice = i_deadline;
        vlc_cond_timedwait( &p_ho->wait, &p_ho->lock, i_slice );
        if( p_ho->i_reply_seq == i_seq )
            break;

        /* Not under the lock: keep_alive takes the extension's own, and
         * an httpd callback must never be left waiting on ours. */
        vlc_mutex_unlock( &p_ho->lock );
        KeepAlive( L );
        vlc_mutex_lock( &p_ho->lock );
    }

    if( p_ho->i_reply_seq != i_seq )
    {
        /* let nothing hand this out afterwards */
        free( p_ho->psz_pending );
        p_ho->psz_pending = NULL;
        bool b_gone = mdate() - p_ho->i_last_poll >= HANDOFF_RELAY_STALE;
        vlc_mutex_unlock( &p_ho->lock );
        lua_pushnil( L );
        lua_pushstring( L, b_gone ? "relay gone" : "timeout" );
        return 2;
    }

    int i_status = p_ho->i_reply_status;
    char *p_body = p_ho->p_reply;
    size_t i_body = p_ho->i_reply_len;
    p_ho->p_reply = NULL;
    p_ho->i_reply_len = 0;
    vlc_mutex_unlock( &p_ho->lock );

    lua_pushinteger( L, i_status );
    lua_pushlstring( L, p_body ? p_body : "", i_body );
    free( p_body );
    return 2;
}

static int vlclua_handoff_close( lua_State *L )
{
    vlclua_handoff_t *p_ho =
        (vlclua_handoff_t *)luaL_checkudata( L, 1, "vlc_handoff" );
    HandoffStop( p_ho );
    return 0;
}

static int vlclua_handoff_gc( lua_State *L )
{
    vlclua_handoff_t *p_ho =
        (vlclua_handoff_t *)luaL_checkudata( L, 1, "vlc_handoff" );
    HandoffStop( p_ho );
    vlc_cond_destroy( &p_ho->wait );
    vlc_mutex_destroy( &p_ho->lock );
    return 0;
}

static const luaL_Reg vlclua_handoff_reg[] = {
    { "url",   vlclua_handoff_url },
    { "poll",  vlclua_handoff_poll },
    { "relay", vlclua_handoff_relay },
    { "fetch", vlclua_handoff_fetch },
    { "close", vlclua_handoff_close },
    { NULL, NULL }
};

/* vlc.browser.handoff{ landing = html, thanks = html }
 *
 * Both pages may use {{RETURN}} -- the URL the browser must come back to
 * with the answer -- and {{BASE}}, this handover's own address.
 *
 * Returns the handle, or nil and an error message. */
static int vlclua_browser_handoff( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    luaL_checktype( L, 1, LUA_TTABLE );

    lua_getfield( L, 1, "landing" );
    const char *psz_landing = luaL_checkstring( L, -1 );
    lua_getfield( L, 1, "thanks" );
    const char *psz_thanks = luaL_optstring( L, -1, psz_landing );
    lua_getfield( L, 1, "empty" );
    const char *psz_empty = luaL_optstring( L, -1, psz_thanks );
    lua_getfield( L, 1, "inject" );
    const char *psz_inject = luaL_optstring( L, -1, "" );

    /* 64 bits of path: the loopback is shared with every other process on
     * the machine, and the answer must reach nobody else. */
    uint8_t secret[8];
    vlc_rand_bytes( secret, sizeof( secret ) );
    char psz_secret[2 * sizeof( secret ) + 1];
    for( size_t i = 0; i < sizeof( secret ); i++ )
        sprintf( psz_secret + 2 * i, "%02x", secret[i] );

    vlclua_handoff_t *p_ho = lua_newuserdata( L, sizeof( *p_ho ) );
    memset( p_ho, 0, sizeof( *p_ho ) );
    vlc_mutex_init( &p_ho->lock );
    vlc_cond_init( &p_ho->wait );

    if( luaL_newmetatable( L, "vlc_handoff" ) )
    {
        lua_newtable( L );
        luaL_register( L, NULL, vlclua_handoff_reg );
        lua_setfield( L, -2, "__index" );
        lua_pushcfunction( L, vlclua_handoff_gc );
        lua_setfield( L, -2, "__gc" );
    }
    lua_setmetatable( L, -2 );

    /* The host reads its address off the object it is created under, so
     * give it one that says loopback. Without this it would inherit
     * --http-host and offer the handover to the whole network. */
    p_ho->p_owner = vlc_object_create( p_this, sizeof( *p_ho->p_owner ) );
    if( p_ho->p_owner == NULL )
    {
        lua_pushnil( L );
        lua_pushliteral( L, "out of memory" );
        return 2;
    }
    var_Create( p_ho->p_owner, "http-host", VLC_VAR_STRING );
    var_SetString( p_ho->p_owner, "http-host", "127.0.0.1" );
    var_Create( p_ho->p_owner, "http-port", VLC_VAR_INTEGER );

    unsigned i_port;
    for( i_port = HANDOFF_PORT_FIRST; i_port <= HANDOFF_PORT_LAST; i_port++ )
    {
        var_SetInteger( p_ho->p_owner, "http-port", (int64_t)i_port );
        p_ho->p_host = vlc_http_HostNew( p_ho->p_owner );
        if( p_ho->p_host != NULL )
            break;
    }
    if( p_ho->p_host == NULL )
    {
        HandoffStop( p_ho );
        lua_pushnil( L );
        lua_pushliteral( L, "no free loopback port" );
        return 2;
    }

    char *psz_path = NULL, *psz_return_path = NULL, *psz_return = NULL;
    char *psz_next_path = NULL, *psz_reply_path = NULL;
    char *psz_inject_path = NULL;
    if( asprintf( &psz_path, "/%s", psz_secret ) < 0
     || asprintf( &psz_return_path, "/%s/done", psz_secret ) < 0
     || asprintf( &psz_next_path, "/%s/next", psz_secret ) < 0
     || asprintf( &psz_reply_path, "/%s/reply", psz_secret ) < 0
     || asprintf( &psz_inject_path, "/%s/inject.js", psz_secret ) < 0
     || asprintf( &p_ho->psz_base, "http://127.0.0.1:%u/%s",
                  i_port, psz_secret ) < 0
     || asprintf( &psz_return, "http://127.0.0.1:%u/%s/done",
                  i_port, psz_secret ) < 0 )
    {
        free( psz_path );
        free( psz_return_path );
        free( psz_next_path );
        free( psz_reply_path );
        free( psz_inject_path );
        free( psz_return );
        HandoffStop( p_ho );
        lua_pushnil( L );
        lua_pushliteral( L, "out of memory" );
        return 2;
    }

    /* Substitute before serving: the pages are static from here on, so the
     * httpd thread only ever reads them. */
    char *psz_origin;
    if( asprintf( &psz_origin, "http://127.0.0.1:%u", i_port ) < 0 )
        psz_origin = NULL;
    if( psz_origin != NULL )
    {
        p_ho->psz_landing = Expand( psz_landing, psz_return, p_ho->psz_base,
                                    psz_origin );
        p_ho->psz_thanks = Expand( psz_thanks, psz_return, p_ho->psz_base,
                                   psz_origin );
        p_ho->psz_empty = Expand( psz_empty, psz_return, p_ho->psz_base,
                                  psz_origin );
        p_ho->psz_inject = Expand( psz_inject, psz_return, p_ho->psz_base,
                                   psz_origin );
    }
    free( psz_origin );
    free( psz_return );

    if( p_ho->psz_landing != NULL && p_ho->psz_thanks != NULL
     && p_ho->psz_empty != NULL )
    {
        p_ho->p_url_landing = httpd_UrlNew( p_ho->p_host, psz_path,
                                            NULL, NULL );
        p_ho->p_url_return = httpd_UrlNew( p_ho->p_host, psz_return_path,
                                           NULL, NULL );
        p_ho->p_url_next = httpd_UrlNew( p_ho->p_host, psz_next_path,
                                         NULL, NULL );
        p_ho->p_url_reply = httpd_UrlNew( p_ho->p_host, psz_reply_path,
                                          NULL, NULL );
        p_ho->p_url_inject = httpd_UrlNew( p_ho->p_host, psz_inject_path,
                                           NULL, NULL );
    }
    free( psz_path );
    free( psz_return_path );
    free( psz_next_path );
    free( psz_reply_path );
    free( psz_inject_path );

    if( p_ho->p_url_landing == NULL || p_ho->p_url_return == NULL
     || p_ho->p_url_next == NULL || p_ho->p_url_reply == NULL
     || p_ho->p_url_inject == NULL )
    {
        HandoffStop( p_ho );
        lua_pushnil( L );
        lua_pushliteral( L, "failed to publish the handover pages" );
        return 2;
    }

    httpd_UrlCatch( p_ho->p_url_landing, HTTPD_MSG_HEAD, LandingCallback,
                    (httpd_callback_sys_t *)p_ho );
    httpd_UrlCatch( p_ho->p_url_landing, HTTPD_MSG_GET, LandingCallback,
                    (httpd_callback_sys_t *)p_ho );
    httpd_UrlCatch( p_ho->p_url_return, HTTPD_MSG_HEAD, ReturnCallback,
                    (httpd_callback_sys_t *)p_ho );
    httpd_UrlCatch( p_ho->p_url_return, HTTPD_MSG_GET, ReturnCallback,
                    (httpd_callback_sys_t *)p_ho );
    httpd_UrlCatch( p_ho->p_url_next, HTTPD_MSG_GET, NextCallback,
                    (httpd_callback_sys_t *)p_ho );
    httpd_UrlCatch( p_ho->p_url_reply, HTTPD_MSG_POST, ReplyCallback,
                    (httpd_callback_sys_t *)p_ho );
    httpd_UrlCatch( p_ho->p_url_inject, HTTPD_MSG_HEAD, InjectCallback,
                    (httpd_callback_sys_t *)p_ho );
    httpd_UrlCatch( p_ho->p_url_inject, HTTPD_MSG_GET, InjectCallback,
                    (httpd_callback_sys_t *)p_ho );

    msg_Dbg( p_this, "browser handover waiting on %s", p_ho->psz_base );

    /* the userdata is already on top, above the fields read from the
     * argument table */
    return 1;
}

/* vlc.browser.open( url )
 *
 * Opens an address in whatever the user browses with. http(s) only, and
 * the address goes to the launcher as an argument -- never through a
 * shell -- so there is nothing to quote and nothing to inject.
 *
 * Returns true, or false and a message. */
static int vlclua_browser_open( lua_State *L )
{
    const char *psz_url = luaL_checkstring( L, 1 );

    if( strncmp( psz_url, "http://", 7 ) != 0
     && strncmp( psz_url, "https://", 8 ) != 0 )
    {
        lua_pushboolean( L, 0 );
        lua_pushliteral( L, "not a web address" );
        return 2;
    }

#ifdef _WIN32
    wchar_t *wurl = ToWide( psz_url );
    if( wurl == NULL )
    {
        lua_pushboolean( L, 0 );
        lua_pushliteral( L, "out of memory" );
        return 2;
    }
    HINSTANCE res = ShellExecuteW( NULL, L"open", wurl, NULL, NULL,
                                   SW_SHOWNORMAL );
    free( wurl );
    lua_pushboolean( L, (INT_PTR)res > 32 );
    return 1;
#else
# ifdef __APPLE__
    const char *psz_cmd = "/usr/bin/open";
# else
    const char *psz_cmd = "xdg-open";
# endif
    pid_t pid = fork();
    if( pid == 0 )
    {
        /* Nothing after a failed exec may come back into the player. */
        setsid();
        execlp( psz_cmd, psz_cmd, psz_url, (char *)NULL );
        _exit( 1 );
    }
    if( pid < 0 )
    {
        lua_pushboolean( L, 0 );
        lua_pushliteral( L, "cannot start the browser" );
        return 2;
    }
    /* Reaped here: the launcher hands over to the browser and returns at
     * once, and a zombie would sit in the player's process table until it
     * quits. */
    while( waitpid( pid, NULL, 0 ) < 0 && errno == EINTR )
        ;
    lua_pushboolean( L, 1 );
    return 1;
#endif
}

static const luaL_Reg vlclua_browser_reg[] = {
    { "handoff", vlclua_browser_handoff },
    { "open",    vlclua_browser_open },
    { NULL, NULL }
};

void luaopen_browser( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_browser_reg );
    lua_setfield( L, -2, "browser" );
}
