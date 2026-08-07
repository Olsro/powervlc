/*****************************************************************************
 * powervlc_browser_addon.cpp : PowerVLC browser add-on installation
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
 * The browser half of PowerVLC: it hands what the browser is playing over to
 * the player, and lets the player read pages the user has opened -- which is
 * the only way in on a browser older than Firefox 69, since those refuse to
 * run a bookmarklet on a page carrying a security policy. Exactly what the
 * macOS interfaces offer in their Help menu (macosx_browser_addon.m); this is
 * the same feature for the Qt interface, so Windows and Linux users of those
 * same retro browsers are not left out.
 *
 * Handing the file to the browser is the whole of it: the browser then shows
 * its own install prompt, which is where this belongs -- the player has no
 * business installing anything inside somebody's browser.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "qt.hpp"
#include "util/powervlc_browser_addon.hpp"

#include <QDesktopServices>
#include <QDir>
#include <QFileInfo>
#include <QMessageBox>
#include <QProcess>
#include <QUrl>

#ifdef _WIN32
# include <windows.h>
# include <shlwapi.h>
# include <shellapi.h>
#endif

QString PowerVLCBrowserAddonPath( void )
{
    char *psz_dir = config_GetDataDir();
    if( psz_dir == NULL )
        return QString();

    QString path = QDir( qfu( psz_dir ) ).filePath( "powervlc.xpi" );
    free( psz_dir );

    if( !QFileInfo( path ).isFile() )
        return QString();
    return path;
}

/*
 * The browser the user actually browses with, which is the only application
 * worth putting the add-on in.
 *
 * ⚠ Handing the .xpi to the system's file association instead would be wrong
 * on BOTH platforms: an .xpi is a zip, so the association is an archive
 * manager far more often than a browser, and the user would get a file listing
 * where they expected an install prompt. So the browser is looked up
 * explicitly, exactly as the macOS interfaces do with
 * LSCopyDefaultHandlerForURLScheme.
 */
#ifdef _WIN32
/* AssocQueryStringW() dates from Windows XP, so this holds on the 32-bit
 * build as well as on ARM64. */
static bool OpenWithDefaultBrowser( const QString &addon )
{
    wchar_t browser[MAX_PATH];
    DWORD len = MAX_PATH;

    if( FAILED( AssocQueryStringW( ASSOCF_NONE, ASSOCSTR_EXECUTABLE,
                                   L"http", NULL, browser, &len ) ) )
        return false;

    /* quoted: the add-on lives under Program Files, which has a space in it */
    const QString arg = QLatin1Char( '"' )
                      + QDir::toNativeSeparators( addon )
                      + QLatin1Char( '"' );

    HINSTANCE res = ShellExecuteW( NULL, L"open", browser,
                                   (const wchar_t *)arg.utf16(),
                                   NULL, SW_SHOWNORMAL );
    return (INT_PTR)res > 32;
}

#else /* POSIX desktops */

static bool OpenWithDefaultBrowser( const QString &addon )
{
    QStringList browsers;

    /* $BROWSER is the user's own answer, so it comes first. It is a
     * colon-separated list, like $PATH. */
    const QString env = QString::fromLocal8Bit( qgetenv( "BROWSER" ) );
    if( !env.isEmpty() )
        browsers << env.split( QLatin1Char( ':' ), QString::SkipEmptyParts );

    /* Then what the desktop says its browser is. The answer is a desktop
     * file name ("firefox.desktop"), and dropping the suffix names the
     * program itself in every case that matters here -- parsing the Exec=
     * line out of the desktop file would buy nothing on these browsers. */
    QProcess xdg;
    xdg.start( QStringLiteral( "xdg-settings" ),
               QStringList() << QStringLiteral( "get" )
                             << QStringLiteral( "default-web-browser" ) );
    if( xdg.waitForFinished( 2000 ) )
    {
        QString name = QString::fromLocal8Bit(
                           xdg.readAllStandardOutput() ).trimmed();
        if( name.endsWith( QLatin1String( ".desktop" ) ) )
            name.chop( 8 );
        if( !name.isEmpty() )
            browsers << name;
    }

    /* Then the distribution's own indirection, and finally the browsers this
     * add-on exists for -- the ones too old to run a bookmarklet. */
    browsers << QStringLiteral( "x-www-browser" )
             << QStringLiteral( "sensible-browser" )
             << QStringLiteral( "firefox" )
             << QStringLiteral( "basilisk" )
             << QStringLiteral( "palemoon" )
             << QStringLiteral( "waterfox" )
             << QStringLiteral( "librewolf" )
             << QStringLiteral( "seamonkey" );

    foreach( const QString &browser, browsers )
        if( QProcess::startDetached( browser, QStringList() << addon ) )
            return true;

    return false;
}
#endif

void PowerVLCInstallBrowserAddon( QWidget *parent )
{
    const QString addon = PowerVLCBrowserAddonPath();

    if( !addon.isEmpty() )
    {
        if( OpenWithDefaultBrowser( addon ) )
            return;

        /* No default browser, or it turned the file down: let the system try
         * whatever it has. Better a file manager than a menu item that looks
         * broken. */
        if( QDesktopServices::openUrl( QUrl::fromLocalFile( addon ) ) )
            return;
    }

    /* Same wording as the macOS interfaces, so the three of them share one
     * string to translate -- and so the answer is the same wherever it is
     * read. Dragging the file onto a browser window always works, including
     * on the old browsers this add-on exists for. */
    QMessageBox::warning( parent, qtr( "Error" ),
                          qtr( "PowerVLC could not open the add-on with your "
                               "browser. Drag share/powervlc.xpi from the "
                               "application onto a browser window to install "
                               "it." ) );
}
