/*****************************************************************************
 * powervlc_links.cpp : PowerVLC external-link confirmation helper
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "qt.hpp"
#include "util/powervlc_links.hpp"

#include <QDialog>
#include <QTextBrowser>
#include <QDialogButtonBox>
#include <QVBoxLayout>
#include <QDesktopServices>
#include <QUrl>

/* The warning is translated through VLC's usual gettext catalog (qtr), like
 * every other interface string, reusing the exact same msgid as the macOS
 * interface so the existing translations apply. The two Olsro links embedded in
 * the body are made clickable and open directly (they are not VideoLAN links). */
void PowerVLCConfirmOpenExternal( QWidget *parent, const QString &url )
{
    if( url.isEmpty() )
        return;

    QString body = qtr(
        "You are currently using PowerVLC, an open source fork with no ads and no tracking, created independently by Olsro for the community and distributed freely. This derivative version would not exist without VLC itself, so out of respect I have chosen to keep all the links and buttons referring to VideoLAN, as well as the list of contributors.\n\n"
        "To support me, I have a Patreon ( https://www.patreon.com/Olsro/ ) where I accept your donations. You can find me on GitHub ( https://github.com/Olsro ) and I invite you to share PowerVLC and to leave positive and/or constructive feedback if this project matters to you in your life.\n\n"
        "Please do not bother VideoLAN with bug reports and support requests, as this fork is absolutely unofficial and not supported by VideoLAN.\n\n"
        "By clicking \"Yes\", you will be redirected to the requested link." );

    /* Turn the plain-text body into rich text: escape it, preserve the
     * paragraph breaks, and make the two Olsro URLs clickable. */
    QString html = body.toHtmlEscaped();
    html.replace( QStringLiteral( "\n" ), QStringLiteral( "<br/>" ) );

    static const char *const links[] = {
        "https://www.patreon.com/Olsro/",
        "https://github.com/Olsro"
    };
    for( size_t i = 0; i < sizeof(links) / sizeof(links[0]); i++ )
    {
        QString u = QString::fromUtf8( links[i] );
        html.replace( u, QStringLiteral( "<a href=\"%1\">%1</a>" ).arg( u ) );
    }

    QDialog dialog( parent );
    dialog.setWindowTitle( qtr( "Warning!" ) );
    dialog.resize( 480, 320 );

    QVBoxLayout *layout = new QVBoxLayout( &dialog );

    QTextBrowser *browser = new QTextBrowser( &dialog );
    browser->setOpenExternalLinks( true );
    browser->setHtml( html );
    layout->addWidget( browser );

    QDialogButtonBox *buttonBox = new QDialogButtonBox( &dialog );
    buttonBox->addButton( qtr( "Yes" ), QDialogButtonBox::AcceptRole );
    buttonBox->addButton( qtr( "No" ), QDialogButtonBox::RejectRole );
    layout->addWidget( buttonBox );

    QObject::connect( buttonBox, &QDialogButtonBox::accepted, &dialog, &QDialog::accept );
    QObject::connect( buttonBox, &QDialogButtonBox::rejected, &dialog, &QDialog::reject );

    if( dialog.exec() == QDialog::Accepted )
        QDesktopServices::openUrl( QUrl( url ) );
}
