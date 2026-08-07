/*****************************************************************************
 * configuration.c: Generic lua<->vlc config interface
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
#ifndef  _GNU_SOURCE
#   define  _GNU_SOURCE
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <locale.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#ifdef _WIN32
# include <windows.h>   /* GetUserDefaultUILanguage(), GetLocaleInfoA() */
#endif

#include <vlc_common.h>

#include "../vlc.h"
#include "../libs.h"

/*****************************************************************************
 * Config handling
 *****************************************************************************/
static int vlclua_config_get( lua_State *L )
{
    vlc_object_t * p_this = vlclua_get_this( L );
    const char *psz_name = luaL_checkstring( L, 1 );
    switch( config_GetType( psz_name ) )
    {
        case VLC_VAR_STRING:
        {
            char *psz = config_GetPsz( p_this, psz_name );
            lua_pushstring( L, psz );
            free( psz );
            break;
        }

        case VLC_VAR_INTEGER:
            lua_pushinteger( L, config_GetInt( p_this, psz_name ) );
            break;

        case VLC_VAR_BOOL:
            lua_pushboolean( L, config_GetInt( p_this, psz_name ) );
            break;

        case VLC_VAR_FLOAT:
            lua_pushnumber( L, config_GetFloat( p_this, psz_name ) );
            break;

        default:
            return vlclua_error( L );

    }
    return 1;
}

static int vlclua_config_set( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_name = luaL_checkstring( L, 1 );
    switch( config_GetType( psz_name ) )
    {
        case VLC_VAR_STRING:
            config_PutPsz( p_this, psz_name, luaL_checkstring( L, 2 ) );
            break;

        case VLC_VAR_INTEGER:
            config_PutInt( p_this, psz_name, luaL_checkinteger( L, 2 ) );
            break;

        case VLC_VAR_BOOL:
            config_PutInt( p_this, psz_name, luaL_checkboolean( L, 2 ) );
            break;

        case VLC_VAR_FLOAT:
            config_PutFloat( p_this, psz_name,
                             luaL_checknumber( L, 2 ) );
            break;

        default:
            return vlclua_error( L );
    }
    return 0;
}

/*****************************************************************************
 * Directories configuration
 *****************************************************************************/
static int vlclua_datadir( lua_State *L )
{
    char *psz_data = config_GetDataDir();
    lua_pushstring( L, psz_data );
    free( psz_data );
    return 1;
}

static int vlclua_userdatadir( lua_State *L )
{
    char *dir = config_GetUserDir( VLC_DATA_DIR );
    lua_pushstring( L, dir );
    free( dir );
    return 1;
}

static int vlclua_homedir( lua_State *L )
{
    char *home = config_GetUserDir( VLC_HOME_DIR );
    lua_pushstring( L, home );
    free( home );
    return 1;
}

static int vlclua_configdir( lua_State *L )
{
    char *dir = config_GetUserDir( VLC_CONFIG_DIR );
    lua_pushstring( L, dir );
    free( dir );
    return 1;
}

static int vlclua_cachedir( lua_State *L )
{
    char *dir = config_GetUserDir( VLC_CACHE_DIR );
    lua_pushstring( L, dir );
    free( dir );
    return 1;
}

static int vlclua_datadir_list( lua_State *L )
{
    const char *psz_dirname = luaL_checkstring( L, 1 );
    char **ppsz_dir_list = NULL;
    int i = 1;

    if( vlclua_dir_list( psz_dirname, &ppsz_dir_list )
        != VLC_SUCCESS )
        return 0;
    lua_newtable( L );
    for( char **ppsz_dir = ppsz_dir_list; *ppsz_dir; ppsz_dir++ )
    {
        lua_pushstring( L, *ppsz_dir );
        lua_rawseti( L, -2, i );
        i ++;
    }
    vlclua_dir_list_free( ppsz_dir_list );
    return 1;
}

/* vlc.config.language()
 *
 * The language the player is actually running in, as a locale name
 * ("fr_FR.UTF-8", "de", ...), or an empty string when there is nothing to
 * say. A script has no other way to know: the "language" option has been
 * obsolete since 2.1, each interface applies the user's choice its own way
 * -- on Mac it becomes LANG before the core starts (bin/darwinvlc.m) --
 * and only the process locale has all of that already resolved.
 *
 * setlocale() first, because it is the truth for gettext and therefore for
 * what the user is reading; the environment after it, because a build that
 * never called setlocale() answers "C" and the variables are then the only
 * thing left. */
static int vlclua_language( lua_State *L )
{
#if defined(LC_MESSAGES) && !defined(_WIN32)
    const char *psz_locale = setlocale( LC_MESSAGES, NULL );
#else
    /* Windows has no LC_MESSAGES: the CRT's locale categories stop at
     * LC_TIME, and none of them answers "which language is the UI in".
     * (gettext's libintl.h does define the name, but as the token 1729 for
     * bindtextdomain() -- handing that to setlocale() is an invalid category,
     * which the UCRT answers with its invalid-parameter handler. Hence the
     * explicit _WIN32 exclusion rather than a bare #ifdef.) Nothing is lost
     * by going straight to the environment: winvlc.c puts the user's choice
     * -- command line, else the Lang registry value -- into LANG itself
     * before libvlc even starts. */
    const char *psz_locale = NULL;
#endif

    if( psz_locale == NULL || !strcmp( psz_locale, "C" )
     || !strcmp( psz_locale, "POSIX" ) )
    {
        static const char *const ppsz_vars[] = {
            "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG", NULL
        };
        psz_locale = NULL;
        for( const char *const *ppsz = ppsz_vars; *ppsz != NULL; ppsz++ )
        {
            /* set but empty is not an answer, and "or" would take it */
            const char *psz = getenv( *ppsz );
            if( psz != NULL && *psz != '\0' )
            {
                psz_locale = psz;
                break;
            }
        }
    }

#ifdef _WIN32
    /* Still nothing, and on Windows that is the ORDINARY case, not an edge
     * one: winvlc.c only writes LANG when a language was picked explicitly,
     * so a default install -- language left on "auto" -- reaches here with a
     * bare environment. Answering "" then told every script the player had no
     * language at all, and the Podcasts extension fell back to the American
     * store on a French machine.
     *
     * The user interface language is the right answer, not the regional
     * format: it is also what GNU libintl reads on Windows when LANG is
     * unset, so what a script is told matches what the user is reading.
     *
     * GetUserDefaultUILanguage() and the two ISO locale fields all date from
     * Windows 2000, so this holds on the XP build as well. */
    if( psz_locale == NULL )
    {
        char psz_lang[9], psz_ctry[9];
        LCID lcid = MAKELCID( GetUserDefaultUILanguage(), SORT_DEFAULT );

        if( GetLocaleInfoA( lcid, LOCALE_SISO639LANGNAME,
                            psz_lang, sizeof( psz_lang ) ) > 0 )
        {
            /* pushed from a local buffer rather than parked in a static one:
             * extensions each run on their own thread */
            char psz_win[20];

            if( GetLocaleInfoA( lcid, LOCALE_SISO3166CTRYNAME,
                                psz_ctry, sizeof( psz_ctry ) ) > 0 )
                snprintf( psz_win, sizeof( psz_win ), "%s_%s",
                          psz_lang, psz_ctry );
            else
                snprintf( psz_win, sizeof( psz_win ), "%s", psz_lang );

            lua_pushstring( L, psz_win );
            return 1;
        }
    }
#endif

    lua_pushstring( L, psz_locale != NULL ? psz_locale : "" );
    return 1;
}

/*****************************************************************************
 *
 *****************************************************************************/
static const luaL_Reg vlclua_config_reg[] = {
    { "get", vlclua_config_get },
    { "set", vlclua_config_set },
    { "datadir", vlclua_datadir },
    { "userdatadir", vlclua_userdatadir },
    { "homedir", vlclua_homedir },
    { "configdir", vlclua_configdir },
    { "cachedir", vlclua_cachedir },
    { "datadir_list", vlclua_datadir_list },
    { "language", vlclua_language },
    { NULL, NULL }
};

void luaopen_config( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_config_reg );
    lua_setfield( L, -2, "config" );
}

/* The extension scanner runs descriptor() in a state with nothing in it
 * -- no libraries, no vlc table -- so that scanning cannot do anything.
 * But descriptor() is what names the menu entry, and an entry the user
 * cannot read is a poor one, so that state is handed this one function
 * and no other: it only reads, and it reads the one thing a name needs. */
void luaopen_config_language( lua_State *L )
{
    lua_newtable( L );
    lua_pushcfunction( L, vlclua_language );
    lua_setfield( L, -2, "language" );
    lua_setfield( L, -2, "config" );
}
