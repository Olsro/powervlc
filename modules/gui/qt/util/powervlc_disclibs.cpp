/*****************************************************************************
 * powervlc_disclibs.cpp : PowerVLC Blu-ray helper-library folders
 ****************************************************************************
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
 * libaacs and libbdplus are shipped with the player, but neither can do
 * anything until the user puts their own files next to them: a key database
 * for AACS, a virtual machine and its conversion tables for BD+. Both read
 * them from a hidden directory nobody should have to type out, so the Help
 * menu offers to open it -- creating it on the way, because it does not exist
 * until something has been written there.
 *
 * The directory itself comes from the core (config_GetDiscLibDir), which is
 * also what the key database importer uses: a menu that opened a folder the
 * importer does not write to would be a bug nobody could see.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "qt.hpp"
#include "util/powervlc_disclibs.hpp"

#include <vlc_modules.h>

#include <QDesktopServices>
#include <QDir>
#include <QMessageBox>
#include <QUrl>

/* "libbluray", not "bluray": module_find() only ever compares
 * pp_shortcuts[0], which is the module's object name (the plugin is built as
 * liblibbluray_plugin). The "bluray" of add_shortcut() sits at index 1 and can
 * never match. */
bool PowerVLCHasBluray( void )
{
    return module_exists( "libbluray" );
}

void PowerVLCOpenDiscLibFolder( QWidget *parent, const char *psz_lib )
{
    char *psz_dir = config_GetDiscLibDir( psz_lib );
    QString dir = psz_dir ? qfu( psz_dir ) : QString();
    free( psz_dir );

    if( !dir.isEmpty() && QDir().mkpath( dir )
     && QDesktopServices::openUrl( QUrl::fromLocalFile( dir ) ) )
        return;

    /* The msgid keeps VLC's own "%s" rather than Qt's "%1" so that the three
     * interfaces of this player share a single string to translate. */
    QMessageBox::warning( parent, qtr( "Error" ),
                          QString( qtr( "The folder %s could not be opened." ) )
                          .replace( QLatin1String( "%s" ),
                                    dir.isEmpty() ? qfu( psz_lib ) : dir ) );
}
