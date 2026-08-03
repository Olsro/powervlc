/*****************************************************************************
 * keystore.c: secret storage for Lua scripts
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

/* Extensions that talk to a server end up holding an API key or a session
 * token. Writing that to a file of their own leaves it in the clear; this
 * hands it to the core keystore instead, which on macOS is the Keychain,
 * the Secret Service on Linux, KWallet on KDE, and an encrypted file
 * elsewhere -- the very same storage the player uses for the passwords it
 * remembers.
 *
 * A script names its secret with a service and a user:
 *   vlc.keystore.store("jellyfin://example.org", "api-key", secret, label)
 *   vlc.keystore.find("jellyfin://example.org", "api-key")   -> secret
 *   vlc.keystore.remove("jellyfin://example.org", "api-key")
 */

#ifndef  _GNU_SOURCE
#   define  _GNU_SOURCE
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <stdbool.h>
#include <string.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_keystore.h>
#include <vlc_url.h>

#include "../vlc.h"
#include "../libs.h"

/* Splits "scheme://host/path" into the key/values the keystore indexes on.
 * A bare name is taken as the server, so a script needs no URL at all. */
struct vlc_lua_keystore_id
{
    vlc_url_t url;
    const char *ppsz_values[KEY_MAX];
};

static void KeystoreIdInit( struct vlc_lua_keystore_id *id,
                            const char *psz_service, const char *psz_user )
{
    VLC_KEYSTORE_VALUES_INIT( id->ppsz_values );
    memset( &id->url, 0, sizeof( id->url ) );

    if( strstr( psz_service, "://" ) != NULL
     && vlc_UrlParse( &id->url, psz_service ) == 0
     && id->url.psz_host != NULL )
    {
        id->ppsz_values[KEY_PROTOCOL] = id->url.psz_protocol;
        id->ppsz_values[KEY_SERVER] = id->url.psz_host;
        if( id->url.psz_path != NULL && id->url.psz_path[0] != '\0' )
            id->ppsz_values[KEY_PATH] = id->url.psz_path;
    }
    else
    {
        id->ppsz_values[KEY_PROTOCOL] = "lua";
        id->ppsz_values[KEY_SERVER] = psz_service;
    }

    if( psz_user != NULL && psz_user[0] != '\0' )
        id->ppsz_values[KEY_USER] = psz_user;
}

static void KeystoreIdClean( struct vlc_lua_keystore_id *id )
{
    vlc_UrlClean( &id->url );
}

/* vlc.keystore.store( service, user, secret [, label] ) -> true or nil, msg */
static int vlclua_keystore_store( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_service = luaL_checkstring( L, 1 );
    const char *psz_user = luaL_optstring( L, 2, NULL );
    size_t i_secret;
    const char *psz_secret = luaL_checklstring( L, 3, &i_secret );
    const char *psz_label = luaL_optstring( L, 4, "VLC extension" );

    vlc_keystore *p_keystore = vlc_keystore_create( p_this );
    if( p_keystore == NULL )
    {
        lua_pushnil( L );
        lua_pushliteral( L, "no keystore available" );
        return 2;
    }

    struct vlc_lua_keystore_id id;
    KeystoreIdInit( &id, psz_service, psz_user );
    int i_ret = vlc_keystore_store( p_keystore, id.ppsz_values,
                                    (const uint8_t *)psz_secret,
                                    (ssize_t)i_secret, psz_label );
    KeystoreIdClean( &id );
    vlc_keystore_release( p_keystore );

    if( i_ret != VLC_SUCCESS )
    {
        lua_pushnil( L );
        lua_pushliteral( L, "could not store the secret" );
        return 2;
    }
    lua_pushboolean( L, 1 );
    return 1;
}

/* vlc.keystore.find( service [, user] ) -> secret, user  (nil if unknown) */
static int vlclua_keystore_find( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_service = luaL_checkstring( L, 1 );
    const char *psz_user = luaL_optstring( L, 2, NULL );

    vlc_keystore *p_keystore = vlc_keystore_create( p_this );
    if( p_keystore == NULL )
    {
        lua_pushnil( L );
        return 1;
    }

    struct vlc_lua_keystore_id id;
    KeystoreIdInit( &id, psz_service, psz_user );
    vlc_keystore_entry *p_entries = NULL;
    unsigned i_count = vlc_keystore_find( p_keystore, id.ppsz_values,
                                          &p_entries );
    KeystoreIdClean( &id );

    int i_pushed = 1;
    if( i_count == 0 || p_entries == NULL || p_entries[0].p_secret == NULL )
        lua_pushnil( L );
    else
    {
        /* the secret is stored with its terminating nul, which has no
         * business being part of the string handed back */
        size_t i_len = p_entries[0].i_secret_len;
        while( i_len > 0 && p_entries[0].p_secret[i_len - 1] == '\0' )
            i_len--;
        lua_pushlstring( L, (const char *)p_entries[0].p_secret, i_len );
        if( p_entries[0].ppsz_values[KEY_USER] != NULL )
        {
            lua_pushstring( L, p_entries[0].ppsz_values[KEY_USER] );
            i_pushed = 2;
        }
    }

    if( p_entries != NULL )
        vlc_keystore_release_entries( p_entries, i_count );
    vlc_keystore_release( p_keystore );
    return i_pushed;
}

/* vlc.keystore.remove( service [, user] ) -> number of entries removed */
static int vlclua_keystore_remove( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_service = luaL_checkstring( L, 1 );
    const char *psz_user = luaL_optstring( L, 2, NULL );

    vlc_keystore *p_keystore = vlc_keystore_create( p_this );
    if( p_keystore == NULL )
    {
        lua_pushinteger( L, 0 );
        return 1;
    }

    struct vlc_lua_keystore_id id;
    KeystoreIdInit( &id, psz_service, psz_user );
    unsigned i_count = vlc_keystore_remove( p_keystore, id.ppsz_values );
    KeystoreIdClean( &id );
    vlc_keystore_release( p_keystore );

    lua_pushinteger( L, i_count );
    return 1;
}

static const luaL_Reg vlclua_keystore_reg[] = {
    { "store", vlclua_keystore_store },
    { "find", vlclua_keystore_find },
    { "remove", vlclua_keystore_remove },
    { NULL, NULL }
};

void luaopen_keystore( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_keystore_reg );
    lua_setfield( L, -2, "keystore" );
}
