
/*****************************************************************************
 * darwin_specific.m: Darwin specific features
 *****************************************************************************
 * Copyright (C) 2001-2009 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Sam Hocevar <sam@zoy.org>
 *          Christophe Massiot <massiot@via.ecp.fr>
 *          Pierre d'Herbemont <pdherbemont@free.fr>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include "../libvlc.h"
#include <dirent.h>                                                /* *dir() */
#include <CoreFoundation/CoreFoundation.h>

#include <locale.h>

/*****************************************************************************
 * system_Init: fill in program path & retrieve language
 *****************************************************************************/
void system_Init(void)
{
#ifdef ENABLE_NLS
    /* Check if $LANG is set. */
    if( NULL == getenv("LANG") )
    {
        /*
           Retrieve the preferred language as chosen in  System Preferences.app
           (note that CFLocaleCopyCurrent() is not used because it returns the
            preferred locale not language)
        */
        CFArrayRef all_locales, preferred_locales;
        char psz_locale[50];

        /* CFLocaleCopyAvailableLocaleIdentifiers() only exists since Mac OS X
         * 10.4. Below that deployment target the SDK weak-imports it, so on a
         * 10.3 system the symbol resolves to NULL and calling it jumps to 0 --
         * and this runs from system_Init(), i.e. before anything else. Fall
         * back to the user's AppleLanguages preference, which is what
         * CFBundleCopyLocalizationsForPreferences() (available since 10.0)
         * intersects against anyway. */
        CFArrayRef (*copy_available_locales)(void) =
            CFLocaleCopyAvailableLocaleIdentifiers;

        if( copy_available_locales != NULL )
            all_locales = copy_available_locales();
        else
        {
            CFPropertyListRef languages = CFPreferencesCopyAppValue(
                CFSTR("AppleLanguages"), kCFPreferencesCurrentApplication );

            if( languages != NULL
             && CFGetTypeID( languages ) != CFArrayGetTypeID() )
            {
                CFRelease( languages );
                languages = NULL;
            }
            all_locales = languages;
        }

        preferred_locales = ( all_locales != NULL )
            ? CFBundleCopyLocalizationsForPreferences( all_locales, NULL )
            : NULL;

        if ( preferred_locales )
        {
            if ( CFArrayGetCount( preferred_locales ) )
            {
                CFStringRef user_language_string_ref = CFArrayGetValueAtIndex( preferred_locales, 0 );
                CFStringGetCString( user_language_string_ref, psz_locale, sizeof(psz_locale), kCFStringEncodingUTF8 );
                setenv( "LANG", psz_locale, 1 );
            }
            CFRelease( preferred_locales );
        }
        if ( all_locales != NULL )
            CFRelease( all_locales );
    }
#endif
}

/*****************************************************************************
 * system_Configure: check for system specific configuration options.
 *****************************************************************************/
void system_Configure( libvlc_int_t *p_this,
                       int i_argc, const char *const ppsz_argv[] )
{
    (void)p_this;
    (void)i_argc;
    (void)ppsz_argv;
}
