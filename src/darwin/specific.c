
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
#include <vlc_configuration.h>                        /* config_GetDataDir() */
#include "../libvlc.h"
#include <dirent.h>                                                /* *dir() */
#include <unistd.h>                                              /* access() */
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

                /* ★ Sur Mac OS X 10.3 et antérieur, AppleLanguages contient
                 * des NOMS de langues à l'ancienne (« French », « English »,
                 * « German »…) et non des codes ISO comme depuis 10.4. Poser
                 * LANG=French ne dit rien à gettext, qui retombait alors en
                 * anglais alors que le système est en français. On canonicalise
                 * donc en code de langue ; la fonction n'existant pas partout,
                 * une petite table couvre les noms courants en dernier ressort. */
                CFStringGetCString( user_language_string_ref,
                                    psz_locale, sizeof(psz_locale),
                                    kCFStringEncodingUTF8 );

                /* ⚠ Ne canonicaliser QUE si l'on a bien un nom en clair, et
                 * jamais un identifiant qui est déjà utilisable.
                 * CFLocaleCreateCanonicalLanguageIdentifierFromString() rend un
                 * identifiant BCP-47 : sur un système moderne elle transforme
                 * le « fr_FR » parfaitement valable renvoyé au-dessus en
                 * « fr-FR », et gettext ne découpe que sur '_', '.' et '@' --
                 * il cherche alors share/locale/fr-FR/, qui n'existe pas (seul
                 * fr/ existe) et retombe en anglais. Mesuré : un Mac réglé en
                 * français affichait un lecteur en anglais. */
                if ( strlen( psz_locale ) > 3
                  && strchr( psz_locale, '_' ) == NULL
                  && strchr( psz_locale, '-' ) == NULL )
                {
                    CFStringRef (*canonicalize)( CFAllocatorRef, CFStringRef ) =
                        CFLocaleCreateCanonicalLanguageIdentifierFromString;
                    CFStringRef canonical = ( canonicalize != NULL )
                        ? canonicalize( NULL, user_language_string_ref ) : NULL;

                    if ( canonical != NULL )
                    {
                        CFStringGetCString( canonical, psz_locale,
                                            sizeof(psz_locale),
                                            kCFStringEncodingUTF8 );
                        CFRelease( canonical );
                    }
                }

                /* Toujours un nom en clair (10.2, ou canonicalisation muette) ? */
                if ( strlen( psz_locale ) > 3 && strchr( psz_locale, '_' ) == NULL )
                {
                    static const char *const ppsz_names[][2] = {
                        { "English",    "en" }, { "French",     "fr" },
                        { "German",     "de" }, { "Spanish",    "es" },
                        { "Italian",    "it" }, { "Dutch",      "nl" },
                        { "Japanese",   "ja" }, { "Portuguese", "pt" },
                        { "Swedish",    "sv" }, { "Danish",     "da" },
                        { "Finnish",    "fi" }, { "Norwegian",  "no" },
                        { "Polish",     "pl" }, { "Russian",    "ru" },
                        { "Korean",     "ko" }, { "Chinese",    "zh" },
                        { "Czech",      "cs" }, { "Hungarian",  "hu" },
                        { "Turkish",    "tr" }, { "Greek",      "el" },
                        { "Catalan",    "ca" }, { "Ukrainian",  "uk" },
                        { "Hebrew",     "he" }, { "Arabic",     "ar" },
                        { "Thai",       "th" }, { "Romanian",   "ro" },
                    };
                    for ( size_t i = 0; i < ARRAY_SIZE(ppsz_names); i++ )
                        if ( !strcasecmp( psz_locale, ppsz_names[i][0] ) )
                        {
                            strcpy( psz_locale, ppsz_names[i][1] );
                            break;
                        }
                }
                /* Filet de sécurité : quoi qu'il arrive, gettext veut un nom
                 * POSIX. Une étiquette BCP-47 qui aurait survécu ("fr-FR",
                 * "zh-Hans-CN") est ramenée à language[_TERRITORY]. */
                char *p_sep = strchr( psz_locale, '-' );
                if ( p_sep != NULL )
                {
                    *p_sep = '_';
                    char *p_next = strchr( p_sep + 1, '-' );
                    if ( p_next != NULL )
                        *p_next = '\0';
                }

                setenv( "LANG", psz_locale, 1 );
            }
            CFRelease( preferred_locales );
        }
        if ( all_locales != NULL )
            CFRelease( all_locales );
    }
#endif

    /* ★ La libfontconfig des contribs est compilée avec son fichier de
     * configuration par défaut sous le préfixe de BUILD, inexistant sur les
     * machines cibles : chaque utilisateur de fontconfig (libass, résolution
     * de polices BD-J dans libbluray) imprimait « Fontconfig error: Cannot
     * load default config file » sur stderr avant de se replier sur la
     * configuration intégrée. On pointe FONTCONFIG_FILE sur le fonts.conf
     * embarqué dans le bundle (share/fontconfig/) -- ici, car system_Init()
     * précède le chargement des greffons et fontconfig ne lit la variable
     * qu'à sa première initialisation, bien plus tard. setenv(…, 0) laisse
     * la main à un réglage utilisateur préexistant. */
    if( getenv( "FONTCONFIG_FILE" ) == NULL )
    {
        char *datadir = config_GetDataDir();
        if( datadir != NULL )
        {
            char *conf;
            if( asprintf( &conf, "%s/fontconfig/fonts.conf", datadir ) != -1 )
            {
                if( access( conf, R_OK ) == 0 )
                    setenv( "FONTCONFIG_FILE", conf, 0 );
                free( conf );
            }
            free( datadir );
        }
    }
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
