/*****************************************************************************
 * help.cpp : Help and About dialogs
 ****************************************************************************
 * Copyright (C) 2007 the VideoLAN team
 * $Id$
 *
 * Authors: Jean-Baptiste Kempf <jb (at) videolan.org>
 *          Rémi Duraffort <ivoire (at) via.ecp.fr>
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "qt.hpp"
#include "dialogs/help.hpp"
#include "util/qt_dirs.hpp"
#include "util/powervlc_links.hpp"

#include <vlc_about.h>
#include <vlc_intf_strings.h>

#ifdef UPDATE_CHECK
# include <vlc_update.h>
#endif

#include <QTextBrowser>
#include <QString>
#include <QUrl>
#include <QDialogButtonBox>
#include <QEvent>
#include <QDate>
#include <QPushButton>

#include <cassert>

HelpDialog::HelpDialog( intf_thread_t *_p_intf ) : QVLCFrame( _p_intf )

{
    setWindowTitle( qtr( "Help" ) );
    setWindowRole( "vlc-help" );
    setMinimumSize( 350, 300 );

    QVBoxLayout *layout = new QVBoxLayout( this );

    QTextBrowser *helpBrowser = new QTextBrowser( this );
    helpBrowser->setOpenExternalLinks( false );
    helpBrowser->setOpenLinks( false );
    helpBrowser->setHtml( qtr(I_LONGHELP) );

    QDialogButtonBox *closeButtonBox = new QDialogButtonBox( this );
    closeButtonBox->addButton(
        new QPushButton( qtr("&Close") ), QDialogButtonBox::RejectRole );
    closeButtonBox->setFocus();

    layout->addWidget( helpBrowser );
    layout->addWidget( closeButtonBox );

    connect( closeButtonBox, &QDialogButtonBox::rejected, this, &HelpDialog::close );
    connect( helpBrowser, &QTextBrowser::anchorClicked, this, &HelpDialog::onExternalLink );
    restoreWidgetPosition( "Help", QSize( 500, 450 ) );
}

HelpDialog::~HelpDialog()
{
    saveWidgetPosition( "Help" );
}

void HelpDialog::onExternalLink( const QUrl &url )
{
    PowerVLCConfirmOpenExternal( this, url.toString() );
}

AboutDialog::AboutDialog( intf_thread_t *_p_intf)
            : QVLCDialog( (QWidget*)_p_intf->p_sys->p_mi, _p_intf ), b_advanced( false )
{
    /* Build UI */
    ui.setupUi( this );
    setWindowTitle( qtr( "About" ) );
    setWindowRole( "vlc-about" );
    setWindowModality( Qt::WindowModal );

    QString linkColor;
    if ( var_InheritBool( p_intf, "qt-dark-palette" ) ) {
        ui.horizontalFrame->setStyleSheet("background-color: rgb(10, 10, 10);");
        ui.footer->setStyleSheet("background-color: rgb(25, 25, 25);");
        linkColor = "#ffa851";
    } else {
        ui.horizontalFrame->setStyleSheet("background-color: rgb(230, 230, 230);");
        ui.footer->setStyleSheet("background-color: rgb(245, 245, 245);");
        linkColor = "#0057ae";
    }

#ifdef POWERVLC_VERSION
    ui.version->setText( qtr("Version ") + qfu( POWERVLC_VERSION ) + qtr(" — Forked from VLC ") + qfu( VERSION_MESSAGE ) );
#else
    ui.version->setText(qfu( " " VERSION_MESSAGE ) );
#endif
    ui.title->setText("<html><head/><body><p><span style=\" font-size:26pt;\"> " + QStringLiteral("PowerVLC") + " </span></p></body></html>");
    QString translatedString = qtr( "<p>VLC media player is a free and open source media player, encoder, and streamer made by the volunteers of the <a href=\"http://www.videolan.org/\"><span style=\" text-decoration: underline; color:#0057ae;\">VideoLAN</span></a> community.</p><p>VLC uses its internal codecs, works on essentially every popular platform, and can read almost all files, CDs, DVDs, network streams, capture cards and other media formats!</p><p><a href=\"http://www.videolan.org/contribute/\"><span style=\" text-decoration: underline; color:#0057ae;\">Help and join us!</span></a>" );
    if ( var_InheritBool( p_intf, "qt-dark-palette" ) )
        translatedString.remove(QLatin1String("#0057ae"));
    QString attributionString = qtr( "PowerVLC Copyright © 2026 Olsro. PowerVLC is an unofficial fork of VLC, not affiliated with VideoLAN. PowerVLC could not have existed without all the contributors who have worked on VLC since its very beginning. A heartfelt thank you to each and every one of them." );
    ui.MainBlabla->setText("<html><head/><body>" + translatedString + "</p><p>" + attributionString + "</p></body> </html>");
    ui.MainBlabla->setOpenExternalLinks(false);
    connect( ui.MainBlabla, &QLabel::linkActivated, this, &AboutDialog::onExternalLink );

#if 0
    if( QDate::currentDate().dayOfYear() >= QT_XMAS_JOKE_DAY && var_InheritBool( p_intf, "qt-icon-change" ) )
        ui.iconVLC->setPixmap( QPixmap( ":/logo/vlc128-xmas.png" ) );
    else
        ui.iconVLC->setPixmap( QPixmap( ":/logo/vlc128.png" ) );
#endif

#if 0
    ifdef UPDATE_CHECK
#else
    ui.update->hide();
#endif

    /* GPL License */
    ui.licensePage->setText( qfu( psz_license ) );

    /* People who helped */
    ui.creditPage->setText( qfu( psz_thanks ) );

    /* People who wrote the software */
    ui.authorsPage->setText( qfu( psz_authors ) );

    ui.licenseButton->setText(QString("<html><head/><body><p><span style=\" text-decoration: underline; color:%1;\">%2</span></p></body></html>")
                           .arg(linkColor, qtr("License")));
	ui.licenseButton->installEventFilter(this);

	ui.authorsButton->setText(QString("<html><head/><body><p><span style=\" text-decoration: underline; color:%1;\">%2</span></p></body></html>")
							   .arg(linkColor, qtr("Authors")));
	ui.authorsButton->installEventFilter(this);

	ui.creditsButton->setText(QString("<html><head/><body><p><span style=\" text-decoration: underline; color:%1;\">%2</span></p></body></html>")
							   .arg(linkColor, qtr("Credits")));
	ui.creditsButton->installEventFilter(this);
    ui.version->installEventFilter( this );
}

void AboutDialog::onExternalLink( const QString &url )
{
    PowerVLCConfirmOpenExternal( this, url );
}

void AboutDialog::showLicense()
{
    ui.stackedWidget->setCurrentWidget( ui.licensePage );
}

void AboutDialog::showAuthors()
{
    ui.stackedWidget->setCurrentWidget( ui.authorsPage );
}

void AboutDialog::showCredit()
{
    ui.stackedWidget->setCurrentWidget( ui.creditPage );
}

bool AboutDialog::eventFilter(QObject *obj, QEvent *event)
{
    if (event->type() == QEvent::MouseButtonPress )
    {
        if( obj == ui.version )
        {
            if( !b_advanced )
            {
                ui.version->setText(qfu( VLC_CompileBy() )+ "@" + qfu( VLC_CompileHost() )
                    + " " + __DATE__ + " " + __TIME__);
                b_advanced = true;
            }
            else
            {
                ui.version->setText(qfu( " " VERSION_MESSAGE ) );
                b_advanced = false;
            }
            return true;
        }
        else if( obj == ui.licenseButton )
            showLicense();
        else if( obj == ui.authorsButton )
            showAuthors();
        else if( obj == ui.creditsButton )
            showCredit();

        return false;
    }

    return QVLCDialog::eventFilter( obj, event);
}

void AboutDialog::showEvent( QShowEvent *event )
{
    ui.stackedWidget->setCurrentWidget( ui.blablaPage );
    QVLCDialog::showEvent( event );
}

#ifdef UPDATE_CHECK

/*****************************************************************************
 * UpdateDialog
 *****************************************************************************/
/* callback to get information from the core */
static void UpdateCallback( void *data, bool b_ret )
{
    UpdateDialog* UDialog = (UpdateDialog *)data;
    QEvent* event;

    if( b_ret )
        event = new QEvent( UpdateDialog::UDOkEvent );
    else
        event = new QEvent( UpdateDialog::UDErrorEvent );

    QApplication::postEvent( UDialog, event );
}

const QEvent::Type UpdateDialog::UDOkEvent =
        (QEvent::Type)QEvent::registerEventType();
const QEvent::Type UpdateDialog::UDErrorEvent =
        (QEvent::Type)QEvent::registerEventType();

UpdateDialog::UpdateDialog( intf_thread_t *_p_intf ) : QVLCFrame( _p_intf )
{
    /* build Ui */
    ui.setupUi( this );
    ui.updateDialogButtonBox->addButton( new QPushButton( qtr("&Close"), this ),
                                         QDialogButtonBox::RejectRole );
    QPushButton *recheckButton = new QPushButton( qtr("&Recheck version"), this );
    ui.updateDialogButtonBox->addButton( recheckButton, QDialogButtonBox::ActionRole );

    ui.updateNotifyButtonBox->addButton( new QPushButton( qtr("&Yes"), this ),
                                         QDialogButtonBox::AcceptRole );
    ui.updateNotifyButtonBox->addButton( new QPushButton( qtr("&No"), this ),
                                         QDialogButtonBox::RejectRole );

    setWindowTitle( qtr( "VLC media player updates" ) );
    setWindowRole( "vlc-update" );

    BUTTONACT( recheckButton, UpdateOrDownload );
    connect( ui.updateDialogButtonBox, &QDialogButtonBox::rejected, this, &UpdateDialog::close );

    connect( ui.updateNotifyButtonBox, &QDialogButtonBox::accepted, this, &UpdateDialog::UpdateOrDownload );
    connect( ui.updateNotifyButtonBox, &QDialogButtonBox::rejected, this, &UpdateDialog::close );

    /* Create the update structure */
    p_update = update_New( p_intf );
    b_checked = false;

    setMinimumSize( 300, 300 );
    setMaximumSize( 500, 300 );

    restoreWidgetPosition( "Update", maximumSize() );

    /* Check for updates */
    UpdateOrDownload();
}

UpdateDialog::~UpdateDialog()
{
    update_Delete( p_update );
    saveWidgetPosition( "Update" );
}

/* Check for updates */
void UpdateDialog::UpdateOrDownload()
{
    if( !b_checked )
    {
        ui.stackedWidget->setCurrentWidget( ui.updateRequestPage );
        update_Check( p_update, UpdateCallback, this );
    }
    else
    {
        QString dest_dir = QDir::tempPath();
        if( !dest_dir.isEmpty() )
        {
            dest_dir = toNativeSepNoSlash( dest_dir ) + DIR_SEP;
            msg_Dbg( p_intf, "Downloading to folder: %s", qtu( dest_dir ) );
            toggleVisible();
            update_Download( p_update, qtu( dest_dir ) );
            /* FIXME: We should trigger a change to another dialog here ! */
        }
    }
}

/* Handle the events */
void UpdateDialog::customEvent( QEvent *event )
{
    if( event->type() == UDOkEvent )
        updateNotify( true );
    else
        updateNotify( false );
}

/* Notify the end of the update_Check */
void UpdateDialog::updateNotify( bool b_result )
{
    /* The update finish without errors */
    if( b_result )
    {
        if( update_NeedUpgrade( p_update ) )
        {
            ui.stackedWidget->setCurrentWidget( ui.updateNotifyPage );
            update_release_t *p_release = update_GetRelease( p_update );
            assert( p_release );
            b_checked = true;
            QString message = QString(
                    qtr( "A new version of VLC (%1.%2.%3%4) is available." ) )
                .arg( QString::number( p_release->i_major ) )
                .arg( QString::number( p_release->i_minor ) )
                .arg( QString::number( p_release->i_revision ) )
                .arg( p_release->i_extra == 0 ? QStringLiteral("") : QStringLiteral(".") + QString::number( p_release->i_extra ) );

            ui.updateNotifyLabel->setText( message );
            message = qfu( p_release->psz_desc ).replace( "\n", "<br/>" );

            /* Try to highlight releases featuring security changes */
            int i_index = message.indexOf( "security", Qt::CaseInsensitive );
            if ( i_index >= 0 )
            {
                message.insert( i_index + 8, "</font>" );
                message.insert( i_index, "<font style=\"color:red\">" );
            }
            ui.updateNotifyTextEdit->setHtml( message );

            /* Force the dialog to be shown */
            this->show();
        }
        else
        {
            ui.stackedWidget->setCurrentWidget( ui.updateDialogPage );
            ui.updateDialogLabel->setText(
                    qtr( "You have the latest version of VLC media player." ) );
        }
    }
    else
    {
        ui.stackedWidget->setCurrentWidget( ui.updateDialogPage );
        ui.updateDialogLabel->setText(
                    qtr( "An error occurred while checking for updates..." ) );
    }
}

#endif
