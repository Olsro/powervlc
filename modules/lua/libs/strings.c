/*****************************************************************************
 * strings.c
 *****************************************************************************
 * Copyright (C) 2007-2008 the VideoLAN team
 * $Id$
 *
 * Authors: Antoine Cellerier <dionoea at videolan tod org>
 *          Pierre d'Herbemont <pdherbemont # videolan.org>
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
#ifndef  _GNU_SOURCE
#   define  _GNU_SOURCE
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <limits.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_meta.h>
#include <vlc_charset.h>
#include <vlc_md5.h>
#ifdef HAVE_ZLIB_H
# include <zlib.h>
#endif

#include "../vlc.h"
#include "../libs.h"

/*****************************************************************************
 * String transformations
 *****************************************************************************/
static int vlclua_decode_uri( lua_State *L )
{
    int i_top = lua_gettop( L );
    int i;
    for( i = 1; i <= i_top; i++ )
    {
        const char *psz_cstring = luaL_checkstring( L, 1 );
        char *psz_string = vlc_uri_decode_duplicate( psz_cstring );
        lua_remove( L, 1 ); /* remove elements to prevent being limited by
                             * the stack's size (this function will work with
                             * up to (stack size - 1) arguments */
        lua_pushstring( L, psz_string );
        free( psz_string );
    }
    return i_top;
}

static int vlclua_encode_uri_component( lua_State *L )
{
    int i_top = lua_gettop( L );
    int i;
    for( i = 1; i <= i_top; i++ )
    {
        const char *psz_cstring = luaL_checkstring( L, 1 );
        char *psz_string = vlc_uri_encode( psz_cstring );
        lua_remove( L,1 );
        lua_pushstring( L, psz_string );
        free( psz_string );
    }
    return i_top;
}

static int vlclua_make_uri( lua_State *L )
{
    const char *psz_input = luaL_checkstring( L, 1 );
    const char *psz_scheme = luaL_optstring( L, 2, NULL );
    if( strstr( psz_input, "://" ) == NULL )
    {
        char *psz_uri = vlc_path2uri( psz_input, psz_scheme );
        lua_pushstring( L, psz_uri );
        free( psz_uri );
    }
    else
        lua_pushstring( L, psz_input );
    return 1;
}

static int vlclua_make_path( lua_State *L )
{
    const char *psz_input = luaL_checkstring( L, 1 );
    char *psz_path = vlc_uri2path( psz_input);
    lua_pushstring( L, psz_path );
    free( psz_path );
    return 1;
}

int vlclua_url_parse( lua_State *L )
{
    const char *psz_url = luaL_checkstring( L, 1 );
    vlc_url_t url;

    vlc_UrlParse( &url, psz_url );

    lua_newtable( L );
    lua_pushstring( L, url.psz_protocol );
    lua_setfield( L, -2, "protocol" );
    lua_pushstring( L, url.psz_username );
    lua_setfield( L, -2, "username" );
    lua_pushstring( L, url.psz_password );
    lua_setfield( L, -2, "password" );
    lua_pushstring( L, url.psz_host );
    lua_setfield( L, -2, "host" );
    lua_pushinteger( L, url.i_port );
    lua_setfield( L, -2, "port" );
    lua_pushstring( L, url.psz_path );
    lua_setfield( L, -2, "path" );
    lua_pushstring( L, url.psz_option );
    lua_setfield( L, -2, "option" );

    vlc_UrlClean( &url );

    return 1;
}

static int vlclua_resolve_xml_special_chars( lua_State *L )
{
    int i_top = lua_gettop( L );
    int i;
    for( i = 1; i <= i_top; i++ )
    {
        const char *psz_cstring = luaL_checkstring( L, 1 );
        char *psz_string = strdup( psz_cstring );
        lua_remove( L, 1 ); /* remove elements to prevent being limited by
                             * the stack's size (this function will work with
                             * up to (stack size - 1) arguments */
        vlc_xml_decode( psz_string );
        lua_pushstring( L, psz_string );
        free( psz_string );
    }
    return i_top;
}

static int vlclua_convert_xml_special_chars( lua_State *L )
{
    int i_top = lua_gettop( L );
    int i;
    for( i = 1; i <= i_top; i++ )
    {
        char *psz_string = vlc_xml_encode( luaL_checkstring(L,1) );
        lua_remove( L, 1 );
        lua_pushstring( L, psz_string );
        free( psz_string );
    }
    return i_top;
}

static int vlclua_from_charset( lua_State *L )
{
    if( lua_gettop( L ) < 2 ) return vlclua_error( L );

    size_t i_in_bytes;
    const char *psz_input = luaL_checklstring( L, 2, &i_in_bytes );
    if( i_in_bytes == 0 ) return vlclua_error( L );

    const char *psz_charset = luaL_checkstring( L, 1 );
    char *psz_output = FromCharset( psz_charset, psz_input, i_in_bytes );
    lua_pushstring( L, psz_output ? psz_output : "" );
    free( psz_output );
    return 1;
}

/* Hex digest of the argument, as md5sum prints it. Scripts need it for
 * protocols whose authentication is an MD5 token (Subsonic among them):
 * Lua 5.1 has no bit operators, so the core's implementation serves. */
static int vlclua_md5( lua_State *L )
{
    size_t i_len;
    const char *psz_input = luaL_checklstring( L, 1, &i_len );
    struct md5_s md5;
    InitMD5( &md5 );
    AddMD5( &md5, psz_input, i_len );
    EndMD5( &md5 );
    char *psz_hash = psz_md5_hash( &md5 );
    if( !psz_hash )
        return vlclua_error( L );
    lua_pushstring( L, psz_hash );
    free( psz_hash );
    return 1;
}

/* Inflate one zlib-wrapped byte string.  Soulseek search results and share
 * lists use this framing.  Keeping the work in zlib avoids a very expensive
 * pure-Lua bitstream decoder on PowerPC, while the explicit ceiling prevents
 * a peer from exhausting an old machine's memory with a compression bomb. */
static int vlclua_inflate( lua_State *L )
{
#ifdef HAVE_ZLIB_H
    size_t i_in;
    const char *p_in = luaL_checklstring( L, 1, &i_in );
    lua_Integer i_requested = luaL_optinteger( L, 2, 64 * 1024 * 1024 );
    const size_t i_hard_max = 128u * 1024u * 1024u;
    size_t i_max;

    if( i_requested <= 0 )
        return luaL_error( L, "inflate limit must be positive" );
    i_max = (size_t)i_requested;
    if( i_max > i_hard_max )
        i_max = i_hard_max;
    if( i_in > UINT_MAX || i_in > i_hard_max )
        return luaL_error( L, "compressed input is too large" );

    size_t i_cap = i_in * 4u + 4096u;
    if( i_cap < 16384u )
        i_cap = 16384u;
    if( i_cap > i_max )
        i_cap = i_max;

    char *p_out = malloc( i_cap );
    if( p_out == NULL )
        return vlclua_error( L );

    z_stream stream;
    memset( &stream, 0, sizeof( stream ) );
    stream.next_in = (Bytef *)p_in;
    stream.avail_in = (uInt)i_in;
    stream.next_out = (Bytef *)p_out;
    stream.avail_out = (uInt)i_cap;

    if( inflateInit( &stream ) != Z_OK )
    {
        free( p_out );
        return vlclua_error( L );
    }

    int i_ret;
    for( ;; )
    {
        i_ret = inflate( &stream, Z_NO_FLUSH );
        if( i_ret == Z_STREAM_END )
            break;
        if( i_ret != Z_OK )
            break;
        if( stream.avail_out != 0 )
            continue;
        if( i_cap >= i_max )
        {
            i_ret = Z_MEM_ERROR;
            break;
        }

        size_t i_used = i_cap;
        size_t i_new = i_cap * 2u;
        if( i_new > i_max )
            i_new = i_max;
        char *p_new = realloc( p_out, i_new );
        if( p_new == NULL )
        {
            i_ret = Z_MEM_ERROR;
            break;
        }
        p_out = p_new;
        i_cap = i_new;
        stream.next_out = (Bytef *)(p_out + i_used);
        stream.avail_out = (uInt)(i_cap - i_used);
    }

    size_t i_out = i_cap - stream.avail_out;
    inflateEnd( &stream );
    if( i_ret != Z_STREAM_END )
    {
        free( p_out );
        lua_pushnil( L );
        lua_pushliteral( L, "invalid or oversized zlib stream" );
        return 2;
    }

    lua_pushlstring( L, p_out, i_out );
    free( p_out );
    return 1;
#else
    (void)L;
    lua_pushnil( L );
    lua_pushliteral( L, "zlib support is unavailable" );
    return 2;
#endif
}

/* The folding the playlist search uses (case, accents, Latin ligatures
 * and typographic punctuation): a script filtering a list of its own
 * must match what the user would get from the search field. */
static int vlclua_fold( lua_State *L )
{
    const char *psz_input = luaL_checkstring( L, 1 );
    char *psz_folded = vlc_strfold( psz_input );
    if( !psz_folded )
        return vlclua_error( L );
    lua_pushstring( L, psz_folded );
    free( psz_folded );
    return 1;
}

/*****************************************************************************
 *
 *****************************************************************************/
static const luaL_Reg vlclua_strings_reg[] = {
    { "decode_uri", vlclua_decode_uri },
    { "encode_uri_component", vlclua_encode_uri_component },
    { "make_uri", vlclua_make_uri },
    { "make_path", vlclua_make_path },
    { "url_parse", vlclua_url_parse },
    { "resolve_xml_special_chars", vlclua_resolve_xml_special_chars },
    { "convert_xml_special_chars", vlclua_convert_xml_special_chars },
    { "from_charset", vlclua_from_charset },
    { "md5", vlclua_md5 },
    { "inflate", vlclua_inflate },
    { "fold", vlclua_fold },
    { NULL, NULL }
};

void luaopen_strings( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_strings_reg );
    lua_setfield( L, -2, "strings" );
}
