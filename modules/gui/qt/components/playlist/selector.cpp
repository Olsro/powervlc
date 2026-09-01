/*****************************************************************************
 * selector.cpp : Playlist source selector
 ****************************************************************************
 * Copyright (C) 2006-2009 the VideoLAN team
 * $Id$
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Jean-Baptiste Kempf
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
#include "components/playlist/selector.hpp"
#include "playlist_model.hpp"                /* plMimeData */
#include "input_manager.hpp"                 /* MainInputManager, for podcast */

#include <QApplication>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QInputDialog>
#include <QMessageBox>
#include <QMimeData>
#include <QDragMoveEvent>
#include <QTreeWidgetItem>
#include <QHBoxLayout>
#include <QPainter>
#include <QPalette>
#include <QScrollBar>
#include <QResource>
#include <QMenu>
#include <QDialog>
#include <QHeaderView>
#include <QTableWidget>
#include <QTimer>
#include <QUrl>
#include <QVBoxLayout>
#include <QVector>
#include <assert.h>

#include <vlc_playlist.h>
#include <vlc_services_discovery.h>
#include <vlc_url.h>

#define PVLC_ML_SCAN_ACTIVE "powervlc-ml-scan-active"
#define PVLC_ML_SCAN_DONE   "powervlc-ml-scan-done"
#define PVLC_ML_SCAN_TOTAL  "powervlc-ml-scan-total"

static void clearTransferStatus( services_discovery_transfer_status_t *status )
{
    for( size_t i = 0; i < status->i_count; ++i )
    {
        free( status->p_items[i].psz_source );
        free( status->p_items[i].psz_destination );
    }
    free( status->p_items );
    memset( status, 0, sizeof( *status ) );
}

static QString transferStageText( services_discovery_transfer_stage_e stage )
{
    switch( stage )
    {
        case SD_TRANSFER_QUEUED: return qtr( "Queued" );
        case SD_TRANSFER_COPYING: return qtr( "Copying" );
        case SD_TRANSFER_TRANSCODING: return qtr( "Transcoding" );
        case SD_TRANSFER_COMPLETED: return qtr( "Completed" );
        case SD_TRANSFER_FAILED: return qtr( "Failed" );
        case SD_TRANSFER_CANCELLED: return qtr( "Cancelled" );
    }
    return QString();
}

/* Reloading a services discovery joins its thread, which may sit in a
 * network fetch: never do it on the UI thread. */
struct sd_reload_request
{
    playlist_t *playlist;
    char *name;
};

static volatile bool b_sd_reload_busy = false;
static vlc_thread_t sd_reload_thread;
static bool b_sd_reload_joinable = false;   /* UI thread only */

static void *RunSDReload( void *data )
{
    struct sd_reload_request *req = (struct sd_reload_request *)data;
    playlist_ServicesDiscoveryRemove( req->playlist, req->name );
    playlist_ServicesDiscoveryAdd( req->playlist, req->name );
    free( req->name );
    free( req );
    b_sd_reload_busy = false;
    return NULL;
}

void SelectorActionButton::paintEvent( QPaintEvent *event )
{
    QPainter p( this );
    QColor color = palette().color( QPalette::HighlightedText );
    color.setAlpha( 80 );
    if( underMouse() )
        p.fillRect( rect(), color );
    p.setPen( color );
    int frame = style()->pixelMetric( QStyle::PM_DefaultFrameWidth, 0, this );
    p.drawLine( rect().topLeft() + QPoint( 0, frame ),
                rect().bottomLeft() - QPoint( 0, frame ) );
    QFramelessButton::paintEvent( event );
}

PLSelItem::PLSelItem ( QTreeWidgetItem *i, const QString& text, bool category )
    : qitem(i), lblAction( NULL), lblIcon( NULL )
{
    layout = new QHBoxLayout( this );
    layout->setContentsMargins(0,0,0,0);
    layout->addSpacing( 3 );

    lbl = new QElidingLabel( text );
    layout->addWidget(lbl, 1);

    /* Index widgets do not automatically contribute their minimum height to
     * QTreeWidget rows with every native style (notably Windows XP).  Keep
     * the item hint in sync, and give category headings a little breathing
     * room from the final child in the preceding section. */
    int height = qMax( category ? 28 : 22, fontMetrics().height() + 8 );
    setMinimumHeight( height );
    qitem->setSizeHint( 0, QSize( 0, height ) );
}

void PLSelItem::setIcon( const QIcon& icon, const QSize& size )
{
    if( lblIcon == NULL )
    {
        lblIcon = new QLabel( this );
        layout->insertWidget( 1, lblIcon, 0, Qt::AlignVCenter );
        layout->insertSpacing( 2, 3 );
    }

    lblIcon->setFixedSize( size );
    lblIcon->setPixmap( icon.pixmap( size ) );

    const int height = qMax( minimumHeight(), size.height() + 4 );
    setMinimumHeight( height );
    qitem->setSizeHint( 0, QSize( 0, height ) );
}

void PLSelItem::addAction( ItemAction act, const QString& tooltip )
{
    if( lblAction ) return; //might change later

    QIcon icon;

    switch( act )
    {
    case ADD_ACTION:
        icon = QIcon( ":/buttons/playlist/playlist_add.svg" ); break;
    case RM_ACTION:
        icon = QIcon( ":/buttons/playlist/playlist_remove.svg" ); break;
    default:
        return;
    }

    lblAction = new SelectorActionButton();
    lblAction->setIcon( icon );
    int icon_size = fontMetrics().height();
    lblAction->setIconSize( QSize( icon_size, icon_size ) );
    lblAction->setMinimumWidth( lblAction->sizeHint().width() + icon_size );

    if( !tooltip.isEmpty() ) lblAction->setToolTip( tooltip );

    layout->addWidget( lblAction, 0 );
    lblAction->hide();

    connect( lblAction, &SelectorActionButton::clicked, this, &PLSelItem::triggerAction );
}


PLSelector::PLSelector( QWidget *p, intf_thread_t *_p_intf )
           : QTreeWidget( p ), p_intf(_p_intf), powerLibraryItem( NULL ),
             powerDevicesRoot( NULL ), powerDeviceBusy( false )
{
    /* Properties */
    setFrameStyle( QFrame::NoFrame );
    setAttribute( Qt::WA_MacShowFocusRect, false );
    viewport()->setAutoFillBackground( false );
    setIconSize( QSize( 24,24 ) );
    setIndentation( 12 );
    setHeaderHidden( true );
    setRootIsDecorated( true );
    setAlternatingRowColors( false );
    setContextMenuPolicy( Qt::CustomContextMenu );

    /* drops */
    viewport()->setAcceptDrops(true);
    setDropIndicatorShown(true);
    invisibleRootItem()->setFlags( invisibleRootItem()->flags() & ~Qt::ItemIsDropEnabled );

    setMinimumHeight( 120 );

    /* Podcasts */
    podcastsParent = NULL;
    podcastsParentId = -1;

    /* Podcast connects */
    connect( THEMIM, &MainInputManager::playlistItemAppended,
             this, &PLSelector::plItemAdded );
    connect( THEMIM, &MainInputManager::playlistItemRemoved,
             this, &PLSelector::plItemRemoved );
    connect( THEMIM->getIM(), &InputManager::metaChanged,
             this, &PLSelector::inputItemUpdate, Qt::DirectConnection );

    createItems();

    setRootIsDecorated( false );
    setIndentation( 5 );
    /* Expand at least to show level 2 */
    for ( int i = 0; i < topLevelItemCount(); i++ )
        expandItem( topLevelItem( i ) );

    /***
     * We need to react to both clicks and activation (enter-key) here.
     * We use curItem to avoid rebuilding twice.
     * See QStyle::SH_ItemView_ActivateItemOnSingleClick
     ***/
    curItem = NULL;
    connect( this, &PLSelector::itemActivated,
             this, &PLSelector::setSource );
    connect( this, &PLSelector::itemClicked,
             this, &PLSelector::setSource );
    connect( this, &QTreeWidget::customContextMenuRequested,
             this, &PLSelector::showContextMenu );
    QTimer *deviceTimer = new QTimer( this );
    connect( deviceTimer, &QTimer::timeout, this,
             &PLSelector::updatePowerDeviceTransfers );
    deviceTimer->start( 250 );
}

PLSelector::~PLSelector()
{
    if( podcastsParent )
    {
        int c = podcastsParent->childCount();
        for( int i = 0; i < c; i++ )
        {
            QTreeWidgetItem *item = podcastsParent->child(i);
            input_item_t *p_input = item->data( 0, IN_ITEM_ROLE ).value<input_item_t*>();
            input_item_Release( p_input );
        }
    }
}

PLSelItem * putSDData( PLSelItem* item, const char* name, const char* longname )
{
    item->treeItem()->setData( 0, NAME_ROLE, qfu( name ) );
    item->treeItem()->setData( 0, LONGNAME_ROLE, qfu( longname ) );
    return item;
}

PLSelItem * putPLData( PLSelItem* item, playlist_item_t* plItem )
{
    item->treeItem()->setData( 0, PL_ITEM_ROLE, QVariant::fromValue( plItem ) );
/*    item->setData( 0, PL_ITEM_ID_ROLE, plItem->i_id );
    item->setData( 0, IN_ITEM_ROLE, QVariant::fromValue( (void*) plItem->p_input ) ); );*/
    return item;
}

/*
 * Reads and updates the playlist's duration as [xx:xx] after the label in the tree
 * item - the treeview item to get the duration for
 * prefix - the string to use before the time (should be the category name)
 */
void PLSelector::updateTotalDuration( PLSelItem* item, const char* prefix )
{
    /* Getting  the playlist */
    QVariant playlistVariant = item->treeItem()->data( 0, PL_ITEM_ROLE );
    playlist_item_t* node = playlistVariant.value<playlist_item_t*>();

    /* Get the duration of the playlist item */
    playlist_Lock( THEPL );
    vlc_tick_t mt_duration = playlist_GetNodeDuration( node );
    playlist_Unlock( THEPL );

    /* Formatting time */
    QString qs_timeLabel( prefix );

    int i_seconds = mt_duration / 1000000;
    int i_minutes = i_seconds / 60;
    i_seconds = i_seconds % 60;
    if( i_minutes >= 60 )
    {
        int i_hours = i_minutes / 60;
        i_minutes = i_minutes % 60;
        qs_timeLabel += QString(" [%1:%2:%3]").arg( i_hours ).arg( i_minutes, 2, 10, QChar('0') ).arg( i_seconds, 2, 10, QChar('0') );
    }
    else
        qs_timeLabel += QString( " [%1:%2]").arg( i_minutes, 2, 10, QChar('0') ).arg( i_seconds, 2, 10, QChar('0') );

    item->setText( qs_timeLabel );
}

void PLSelector::createItems()
{
    /* PL */
    playlistItem = putPLData( addItem( PL_ITEM_TYPE, N_("Playlist"), true ),
                              THEPL->p_playing );
    playlistItem->treeItem()->setData( 0, SPECIAL_ROLE, QVariant( IS_PL ) );
    playlistItem->treeItem()->setData( 0, Qt::DecorationRole, QIcon( ":/sidebar/playlist.svg" ) );
    setCurrentItem( playlistItem->treeItem() );

    /* ML */
    if( THEPL->p_media_library )
    {
        PLSelItem *ml = putPLData( addItem( PL_ITEM_TYPE,
                                           N_("Catch-all Media Library"), true ),
          THEPL->p_media_library );
        ml->treeItem()->setData( 0, SPECIAL_ROLE, QVariant( IS_ML ) );
        ml->treeItem()->setData( 0, Qt::DecorationRole, QIcon( ":/sidebar/library.svg" ) );
    }

    /* The PowerVLC library is a first-class source, next to Playlist and the
     * legacy catch-all node, rather than a generic My Computer service. */
    PLSelItem *powerLibrary = addItem( SD_TYPE, N_("Media Library"), true );
    powerLibraryItem = powerLibrary->treeItem();
    powerLibrary->treeItem()->setData( 0, SPECIAL_ROLE, QVariant( IS_POWER_ML ) );
    powerLibrary->treeItem()->setData( 0, SD_CATEGORY_ROLE, SD_CAT_MYCOMPUTER );
    powerLibrary->treeItem()->setData( 0, Qt::DecorationRole,
                                       QIcon( ":/sidebar/library.svg" ) );
    putSDData( powerLibrary, "powervlc_library", N_("PowerVLC Media Library") );

    /* SD nodes */
    myComputerItem = addItem( CATEGORY_TYPE, N_("My Computer"), false, true )->treeItem();
    QTreeWidgetItem *devices = addItem( CATEGORY_TYPE, N_("Devices"), false, true )->treeItem();
    powerDevicesRoot = devices;
    QTreeWidgetItem *lan = addItem( CATEGORY_TYPE, N_("Local Network"), false, true )->treeItem();
    QTreeWidgetItem *internet = addItem( CATEGORY_TYPE, N_("Internet"), false, true )->treeItem();

#define NOT_SELECTABLE(w) w->setFlags( w->flags() ^ Qt::ItemIsSelectable );
    NOT_SELECTABLE( myComputerItem );
    NOT_SELECTABLE( devices );
    NOT_SELECTABLE( lan );
    NOT_SELECTABLE( internet );
#undef NOT_SELECTABLE

    /* SD subnodes */
    char **ppsz_longnames;
    int *p_categories;
    char **ppsz_names = vlc_sd_GetNames( THEPL, &ppsz_longnames, &p_categories );
    if( !ppsz_names )
        return;

    char **ppsz_name = ppsz_names, **ppsz_longname = ppsz_longnames;
    int *p_category = p_categories;
    for( ; *ppsz_name; ppsz_name++, ppsz_longname++, p_category++ )
    {
        //msg_Dbg( p_intf, "Adding a SD item: %s", *ppsz_longname );

        PLSelItem *selItem;
        QIcon icon;
        QString name( *ppsz_name );
        if( name == "powervlc_library" )
        {
            free( *ppsz_name );
            free( *ppsz_longname );
            continue;
        }
        const bool powerDevice = name.startsWith( "powervlc_device{" );
        switch( *p_category )
        {
        case SD_CAT_INTERNET:
            {
            selItem = addItem( SD_TYPE, *ppsz_longname, false, false, internet );
            if( name.startsWith( "podcast" ) )
            {
                selItem->treeItem()->setData( 0, SPECIAL_ROLE, QVariant( IS_PODCAST ) );
                selItem->addAction( ADD_ACTION, qtr( "Subscribe to a podcast" ) );
                connect( selItem, &PLSelItem::action, this, &PLSelector::podcastAdd );
                podcastsParent = selItem->treeItem();
                icon = QIcon( ":/sidebar/podcast.svg" );
            }
            else if ( name.startsWith( "lua{" ) )
            {
                int i_head = name.indexOf( "sd='" ) + 4;
                int i_tail = name.indexOf( '\'', i_head );
                QString iconname = QString( ":/sidebar/sd/%1.svg" ).arg( name.mid( i_head, i_tail - i_head ) );
                QResource resource( iconname );
                if ( !resource.isValid() )
                    icon = QIcon( ":/sidebar/network.svg" );
                else
                    icon = QIcon( iconname );
            }
            }
            break;
        case SD_CAT_DEVICES:
            name = name.mid( 0, name.indexOf( '{' ) );
            selItem = addItem( SD_TYPE, *ppsz_longname, powerDevice, false,
                               name == "disc" ? myComputerItem : devices );
            if ( name == "xcb_apps" )
                icon = QIcon( ":/sidebar/screen.svg" );
            else if ( name == "mtp" )
                icon = QIcon( ":/sidebar/mtp.svg" );
            else if ( name == "disc" )
            {
                icon = QIcon( ":/sidebar/disc.svg" );
                selItem->treeItem()->setData( 0, SPECIAL_ROLE,
                                              QVariant( IS_AUDIO_CD ) );
            }
            else if ( powerDevice )
                icon = QIcon( ":/sidebar/mtp.svg" );
            else
                icon = QIcon( ":/sidebar/capture.svg" );
            break;
        case SD_CAT_LAN:
            selItem = addItem( SD_TYPE, *ppsz_longname, false, false, lan );
            icon = QIcon( ":/sidebar/lan.svg" );
            break;
        case SD_CAT_MYCOMPUTER:
            name = name.mid( 0, name.indexOf( '{' ) );
            selItem = addItem( SD_TYPE, *ppsz_longname, false, false, myComputerItem );
            if ( name == "video_dir" )
                icon = QIcon( ":/sidebar/movie.svg" );
            else if ( name == "audio_dir" )
                icon = QIcon( ":/sidebar/music.svg" );
            else if ( name == "picture_dir" )
                icon = QIcon( ":/sidebar/pictures.svg" );
            else
                icon = QIcon( ":/sidebar/movie.svg" );
            break;
        default:
            selItem = addItem( SD_TYPE, *ppsz_longname );
        }

        selItem->treeItem()->setData( 0, SD_CATEGORY_ROLE, *p_category );
        if( powerDevice )
            selItem->treeItem()->setData( 0, SPECIAL_ROLE,
                                          QVariant( IS_POWER_DEVICE ) );
        putSDData( selItem, *ppsz_name, *ppsz_longname );
        if ( ! icon.isNull() )
            selItem->treeItem()->setData( 0, Qt::DecorationRole, icon );

        free( *ppsz_name );
        free( *ppsz_longname );
    }
    free( ppsz_names );
    free( ppsz_longnames );
    free( p_categories );

    /* Keep My Computer even when no local SD is available: live network
     * locations are attached here by Connect to Server. */
    /* Keep the Devices group alive: portable-player profiles can be added
     * from Preferences without restarting the interface. */
    if( lan->childCount() == 0 ) delete lan;
    if( internet->childCount() == 0 ) delete internet;
}

void PLSelector::reloadPowerDevices()
{
    if( powerDevicesRoot == NULL ) return;
    for( int i = powerDevicesRoot->childCount() - 1; i >= 0; --i )
    {
        QTreeWidgetItem *item = powerDevicesRoot->child( i );
        if( item->data( 0, SPECIAL_ROLE ).toInt() == IS_POWER_DEVICE )
            delete powerDevicesRoot->takeChild( i );
    }
    char **longnames = NULL; int *categories = NULL;
    char **names = vlc_sd_GetNames( THEPL, &longnames, &categories );
    if( names == NULL ) return;
    for( int i = 0; names[i] != NULL; ++i )
    {
        QString chain = qfu( names[i] );
        if( chain.startsWith( "powervlc_device{" ) )
        {
            PLSelItem *entry = addItem( SD_TYPE, longnames[i], true, false,
                                        powerDevicesRoot );
            entry->setIcon( QIcon( ":/sidebar/mtp.svg" ), QSize( 16, 16 ) );
            putSDData( entry, names[i], longnames[i] );
            entry->treeItem()->setData( 0, SPECIAL_ROLE, IS_POWER_DEVICE );
            entry->treeItem()->setData( 0, SD_CATEGORY_ROLE, SD_CAT_DEVICES );
        }
        free( names[i] ); free( longnames[i] );
    }
    free( names ); free( longnames ); free( categories );
    powerDevicesRoot->setExpanded( true );
}

bool PLSelector::addNetworkLocation( const QString& mrl )
{
    for( int i = 0; i < myComputerItem->childCount(); ++i )
    {
        QTreeWidgetItem *existing = myComputerItem->child( i );
        if( existing->data( 0, NETWORK_MRL_ROLE ).toString() == mrl )
        {
            myComputerItem->setExpanded( true );
            setCurrentItem( existing );
            curItem = NULL;
            setSource( existing );
            return true;
        }
    }

    const QUrl url( mrl );
    QString title = url.host();
    QString path = url.path();
    while( path.endsWith( '/' ) ) path.chop( 1 );
    const QString leaf = path.section( '/', -1 );
    if( !leaf.isEmpty() ) title += QStringLiteral( " — " ) + leaf;
    if( title.isEmpty() ) title = mrl;

    input_item_t *input = input_item_NewDirectory( qtu( mrl ), qtu( title ),
                                                   ITEM_NET );
    if( input == NULL )
        return false;

    playlist_Lock( THEPL );
    playlist_item_t *plItem = playlist_NodeAddInput( THEPL, input,
                                                      &THEPL->root,
                                                      PLAYLIST_END );
    const int itemId = plItem ? plItem->i_id : -1;
    if( plItem )
        libvlc_MetadataRequest( p_intf->obj.libvlc, input,
                                static_cast<input_item_meta_request_option_t>(
                                    META_REQUEST_OPTION_SCOPE_ANY |
                                    META_REQUEST_OPTION_DO_INTERACT ), 120000,
                                plItem );
    playlist_Unlock( THEPL );
    input_item_Release( input );
    if( itemId < 0 )
        return false;

    PLSelItem *network = addItem( PL_ITEM_TYPE, qtu( title ), false, false,
                                  myComputerItem );
    network->treeItem()->setData( 0, PL_ITEM_ROLE,
                                  QVariant::fromValue( plItem ) );
    network->treeItem()->setData( 0, PL_ITEM_ID_ROLE, itemId );
    network->treeItem()->setData( 0, NETWORK_MRL_ROLE, mrl );
    network->treeItem()->setData( 0, SPECIAL_ROLE, QVariant( IS_NETWORK ) );
    /* Keep the server icon and its text in the same layout.  QTreeWidget's
     * native decoration rectangle can overlap an index widget on older
     * Windows styles (notably the XP style once several siblings exist). */
    network->setIcon( QIcon( ":/sidebar/network.svg" ), iconSize() );
    network->addAction( RM_ACTION, qtr( "Eject this network location" ) );
    connect( network, &PLSelItem::action, this, &PLSelector::networkRemove );

    myComputerItem->setExpanded( true );
    setCurrentItem( network->treeItem() );
    curItem = NULL;
    setSource( network->treeItem() );
    return true;
}

void PLSelector::networkRemove( PLSelItem *network )
{
    if( network == NULL ) return;
    QTreeWidgetItem *item = network->treeItem();
    const int id = item->data( 0, PL_ITEM_ID_ROLE ).toInt();

    setCurrentItem( playlistItem->treeItem() );
    curItem = NULL;
    setSource( playlistItem->treeItem() );

    playlist_Lock( THEPL );
    playlist_item_t *plItem = playlist_ItemGetById( THEPL, id );
    if( plItem ) playlist_NodeDelete( THEPL, plItem );
    playlist_Unlock( THEPL );
    delete item;
}

void PLSelector::updatePowerDeviceTransfers()
{
    if( powerLibraryItem != NULL )
    {
        QString title = qtr( "Media Library" );
        if( var_GetBool( p_intf->obj.libvlc, PVLC_ML_SCAN_ACTIVE ) )
        {
            const uint64_t done = var_GetInteger( p_intf->obj.libvlc,
                                                   PVLC_ML_SCAN_DONE );
            const uint64_t total = var_GetInteger( p_intf->obj.libvlc,
                                                    PVLC_ML_SCAN_TOTAL );
            if( total > 0 )
            {
                const uint64_t remaining = total > done ? total - done : 0;
                title = qtr( remaining == 1
                    ? "Media Library — scanning %1% · %2 file remaining"
                    : "Media Library — scanning %1% · %2 files remaining" )
                    .arg( qMin<uint64_t>( 100, done * 100 / total ) )
                    .arg( remaining );
            }
            else title = qtr( "Media Library — scanning…" );
        }
        PLSelItem *widget = itemWidget( powerLibraryItem );
        if( widget && widget->text() != title ) widget->setText( title );
        powerLibraryItem->setText( 0, title );
    }
    if( powerDevicesRoot == NULL ) return;
    bool selectedDeviceDeleting = false;
    for( int i = 0; i < powerDevicesRoot->childCount(); ++i )
    {
        QTreeWidgetItem *item = powerDevicesRoot->child( i );
        if( item->data( 0, SPECIAL_ROLE ).toInt() != IS_POWER_DEVICE ) continue;
        const QString service = item->data( 0, NAME_ROLE ).toString();
        const QString base = item->data( 0, LONGNAME_ROLE ).toString();
        bool active = false;
        bool pendingChanges = false;
        bool commitFailed = false;
        unsigned activity = SD_DEVICE_IDLE;
        uint64_t totalBytes = 0, freeBytes = 0;
        if( playlist_IsServicesDiscoveryLoaded( THEPL, qtu( service ) ) )
        {
            services_discovery_transfer_status_t status = {};
            if( playlist_ServicesDiscoveryControl( THEPL, qtu( service ),
                    SD_CMD_POWERVLC_DEVICE_TRANSFERS, &status ) == VLC_SUCCESS ) {
                active = status.b_synchronizing;
                pendingChanges = status.b_pending_changes;
                commitFailed = status.b_commit_failed;
                activity = status.i_activity;
                totalBytes = status.i_total_bytes;
                freeBytes = status.i_free_bytes;
            }
            clearTransferStatus( &status );
        }
        QString operation;
        if( activity == SD_DEVICE_LOADING_ITUNESDB ) operation = qtr( "Loading iTunesDB…" );
        else if( activity == SD_DEVICE_LOADING_CONTENTS ) operation = qtr( "Loading contents…" );
        else if( activity == SD_DEVICE_UPDATING_ITUNESDB ) operation = qtr( "Updating iTunesDB…" );
        else if( activity == SD_DEVICE_DELETING ) operation = qtr( "Deleting…" );
        else if( active ) operation = qtr( "Synchronizing" );
        else if( commitFailed ) operation = qtr( "Finalization failed — changes still pending" );
        else if( pendingChanges ) operation = qtr( "Changes pending finalization" );
        QString title = operation.isEmpty() ? base : base + " (" + operation + ")";
        if( totalBytes > 0 )
            title += qtr( " — %1 GB free of %2 GB (%3%)" )
                .arg( (double)freeBytes / 1000000000., 0, 'f', 1 )
                .arg( (double)totalBytes / 1000000000., 0, 'f', 1 )
                .arg( (unsigned)((freeBytes * 100) / totalBytes) );
        PLSelItem *widget = itemWidget( item );
        if( widget && widget->text() != title ) widget->setText( title );
        item->setText( 0, title );
        if( item == currentItem() && activity == SD_DEVICE_DELETING )
            selectedDeviceDeleting = true;
    }
    if( selectedDeviceDeleting != powerDeviceBusy )
    {
        powerDeviceBusy = selectedDeviceDeleting;
        emit powerDeviceBusyChanged( powerDeviceBusy );
    }
}

QString PLSelector::currentPowerDeviceService() const
{
    QTreeWidgetItem *item = currentItem();
    return item && item->data( 0, SPECIAL_ROLE ).toInt() == IS_POWER_DEVICE
         ? item->data( 0, NAME_ROLE ).toString() : QString();
}

void PLSelector::showPowerDeviceTransfers( const QString &service,
                                           const QString &deviceName )
{
    QDialog *dialog = new QDialog( this );
    dialog->setAttribute( Qt::WA_DeleteOnClose );
    dialog->setWindowTitle( qtr( "Transfer History — %1" ).arg( deviceName ) );
    dialog->resize( 780, 380 );
    QVBoxLayout *layout = new QVBoxLayout( dialog );
    QTableWidget *table = new QTableWidget( dialog );
    table->setColumnCount( 4 );
    table->setHorizontalHeaderLabels( QStringList() << qtr( "File" )
        << qtr( "Destination" ) << qtr( "Step" ) << qtr( "Progress" ) );
    table->horizontalHeader()->setStretchLastSection( false );
    table->horizontalHeader()->setSectionResizeMode( 0, QHeaderView::ResizeToContents );
    table->horizontalHeader()->setSectionResizeMode( 1, QHeaderView::Stretch );
    table->horizontalHeader()->setSectionResizeMode( 2, QHeaderView::ResizeToContents );
    table->horizontalHeader()->setSectionResizeMode( 3, QHeaderView::ResizeToContents );
    table->setEditTriggers( QAbstractItemView::NoEditTriggers );
    table->setAlternatingRowColors( true );
    layout->addWidget( table );
    QHBoxLayout *actions = new QHBoxLayout;
    QPushButton *cancelSelected = new QPushButton(
                                    qtr( "Cancel Selected Transfer" ), dialog );
    QPushButton *cancelAll = new QPushButton( qtr( "Cancel All Transfers" ),
                                              dialog );
    actions->addWidget( cancelSelected ); actions->addWidget( cancelAll );
    actions->addStretch(); layout->addLayout( actions );

    QTimer *timer = new QTimer( dialog );
    auto refresh = [this, service, table]() {
        qulonglong selectedId = 0;
        if( table->currentRow() >= 0 && table->item( table->currentRow(), 0 ) )
            selectedId = table->item( table->currentRow(), 0 )
                              ->data( Qt::UserRole ).toULongLong();
        services_discovery_transfer_status_t status = {};
        if( playlist_ServicesDiscoveryControl( THEPL, qtu( service ),
                SD_CMD_POWERVLC_DEVICE_TRANSFERS, &status ) != VLC_SUCCESS )
            return;
        table->setRowCount( (int)status.i_count );
        for( size_t n = 0; n < status.i_count; ++n )
        {
            services_discovery_transfer_item_t *item =
                &status.p_items[status.i_count - n - 1];
            QString source = QFileInfo( QFile::decodeName(
                                        item->psz_source ) ).fileName();
            QTableWidgetItem *sourceItem = new QTableWidgetItem( source );
            sourceItem->setData( Qt::UserRole,
                                 QVariant::fromValue<qulonglong>( item->i_id ) );
            table->setItem( (int)n, 0, sourceItem );
            if( selectedId && selectedId == item->i_id )
                table->setCurrentCell( (int)n, 0 );
            table->setItem( (int)n, 1, new QTableWidgetItem(
                            QFile::decodeName( item->psz_destination ) ) );
            table->setItem( (int)n, 2, new QTableWidgetItem(
                            transferStageText( item->i_stage ) ) );
            table->setItem( (int)n, 3, new QTableWidgetItem(
                            QStringLiteral( "%1 %" ).arg( item->i_progress ) ) );
        }
        clearTransferStatus( &status );
    };
    connect( cancelSelected, &QPushButton::clicked, dialog,
             [this, service, table, refresh]() {
        int row = table->currentRow();
        QTableWidgetItem *item = row >= 0 ? table->item( row, 0 ) : NULL;
        if( item == NULL ) return;
        services_discovery_transfer_cancel_t request = {
            item->data( Qt::UserRole ).toULongLong()
        };
        playlist_ServicesDiscoveryControl( THEPL, qtu( service ),
            SD_CMD_POWERVLC_DEVICE_CANCEL_TRANSFER, &request );
        refresh();
    } );
    connect( cancelAll, &QPushButton::clicked, dialog,
             [this, service, refresh]() {
        playlist_ServicesDiscoveryControl( THEPL, qtu( service ),
                                            SD_CMD_POWERVLC_DEVICE_CANCEL_ALL );
        refresh();
    } );
    connect( timer, &QTimer::timeout, dialog, refresh );
    refresh(); timer->start( 250 ); dialog->show();
}

void PLSelector::showContextMenu( const QPoint& point )
{
    QTreeWidgetItem *item = itemAt( point );
    if( item == NULL ) return;
    const int special = item->data( 0, SPECIAL_ROLE ).toInt();
    QMenu menu( this );
    if( special == IS_NETWORK )
    {
        QAction *eject = menu.addAction( qtr( "Eject" ) );
        if( menu.exec( viewport()->mapToGlobal( point ) ) == eject )
            networkRemove( itemWidget( item ) );
        return;
    }
    if( special == IS_AUDIO_CD )
    {
        setSource( item );
        QAction *import = menu.addAction( qtr( "Import Audio CD into Media Library" ) );
        if( menu.exec( viewport()->mapToGlobal( point ) ) == import )
            importAudioCD( item );
        return;
    }
    if( special != IS_POWER_ML && special != IS_POWER_DEVICE ) return;

    setSource( item );
    const QString name = item->data( 0, NAME_ROLE ).toString();
    if( !playlist_IsServicesDiscoveryLoaded( THEPL, qtu( name ) ) ) return;
    if( special == IS_POWER_ML )
    {
        QAction *rescan = menu.addAction( qtr( "Rescan Media Library" ) );
        if( menu.exec( viewport()->mapToGlobal( point ) ) == rescan )
            playlist_ServicesDiscoveryControl( THEPL, qtu( name ),
                                               SD_CMD_POWERVLC_RESCAN );
        return;
    }

    QAction *commit = menu.addAction( qtr( "Finalize Changes" ) );
    services_discovery_transfer_status_t commitStatus = {};
    const bool commitStatusOK = playlist_ServicesDiscoveryControl(
        THEPL, qtu( name ), SD_CMD_POWERVLC_DEVICE_TRANSFERS,
        &commitStatus ) == VLC_SUCCESS;
    commit->setEnabled( commitStatusOK && commitStatus.b_pending_changes
                                      && !commitStatus.b_synchronizing );
    clearTransferStatus( &commitStatus );
    menu.addSeparator();
    QAction *history = menu.addAction( qtr( "Transfer History…" ) );
    menu.addSeparator();
    QAction *backup = menu.addAction( qtr( "Back Up…" ) );
    QAction *refresh = menu.addAction( qtr( "Refresh" ) );
    QAction *selected = menu.exec( viewport()->mapToGlobal( point ) );
    if( selected == commit )
    {
        if( playlist_ServicesDiscoveryControl( THEPL, qtu( name ),
                SD_CMD_POWERVLC_DEVICE_COMMIT ) != VLC_SUCCESS )
            QMessageBox::warning( this, qtr( "Unable to Finalize Changes" ),
                qtr( "The portable player is unavailable. Your changes remain pending and can be validated after reconnecting it." ) );
    }
    else if( selected == history )
        showPowerDeviceTransfers( name, item->data( 0, LONGNAME_ROLE ).toString() );
    else if( selected == refresh )
        playlist_ServicesDiscoveryControl( THEPL, qtu( name ),
                                           SD_CMD_POWERVLC_RESCAN );
    else if( selected == backup )
    {
        QString target = QFileDialog::getExistingDirectory(
            this, qtr( "Choose Backup Folder" ), QDir::homePath() );
        if( !target.isEmpty() )
            playlist_ServicesDiscoveryControl( THEPL, qtu( name ),
                SD_CMD_POWERVLC_DEVICE_BACKUP, qtu( target ) );
    }
}

static void collectAudioCDTracks( playlist_item_t *node,
                                  QVector<input_item_t *> &tracks )
{
    if( node == NULL ) return;
    if( node->i_children > 0 )
    {
        for( int i = 0; i < node->i_children; ++i )
            collectAudioCDTracks( node->pp_children[i], tracks );
        return;
    }
    if( node->p_input == NULL ) return;
    char *uri = input_item_GetURI( node->p_input );
    bool track = uri && !strncmp( uri, "cdda://", 7 )
              && input_item_GetDuration( node->p_input ) > 0;
    free( uri );
    if( track ) tracks.append( input_item_Hold( node->p_input ) );
}

void PLSelector::importAudioCD( QTreeWidgetItem *item )
{
    QVector<input_item_t *> tracks;
    playlist_item_t *root = item->data( 0, PL_ITEM_ROLE )
                                 .value<playlist_item_t *>();
    playlist_Lock( THEPL );
    collectAudioCDTracks( root, tracks );
    playlist_Unlock( THEPL );
    if( tracks.isEmpty() )
    {
        QMessageBox::information( this, qtr( "Import Audio CD" ),
            qtr( "Open the Audio CD once so its tracks are displayed, then run the import again." ) );
        return;
    }
    if( !playlist_IsServicesDiscoveryLoaded( THEPL, "powervlc_library" )
     && playlist_ServicesDiscoveryAdd( THEPL, "powervlc_library" ) != VLC_SUCCESS )
    {
        for( input_item_t *track : tracks ) input_item_Release( track );
        return;
    }
    int imported = 0;
    for( input_item_t *track : tracks )
    {
        char *uri = input_item_GetURI( track );
        char *title = input_item_GetTitleFbName( track );
        char *artist = input_item_GetMeta( track, vlc_meta_Artist );
        char *album = input_item_GetMeta( track, vlc_meta_Album );
        services_discovery_import_t request = {
            uri, title, artist, album, track
        };
        if( playlist_ServicesDiscoveryControl( THEPL, "powervlc_library",
                SD_CMD_POWERVLC_IMPORT, &request ) == VLC_SUCCESS ) imported++;
        free( uri ); free( title ); free( artist ); free( album );
        input_item_Release( track );
    }
    QMessageBox::information( this, qtr( "Import Audio CD" ),
        qtr( "%1 tracks are being imported as lossless FLAC files in the managed library." )
            .arg( imported ) );
}

void PLSelector::setSource( QTreeWidgetItem *item )
{
    if( !item || item == curItem )
        return;

    bool b_ok;
    int i_type = item->data( 0, TYPE_ROLE ).toInt( &b_ok );
    if( !b_ok || i_type == CATEGORY_TYPE )
        return;

    bool sd_loaded;
    if( i_type == SD_TYPE )
    {
        QString qs = item->data( 0, NAME_ROLE ).toString();
        sd_loaded = playlist_IsServicesDiscoveryLoaded( THEPL, qtu( qs ) );
        if( !sd_loaded )
        {
            if ( playlist_ServicesDiscoveryAdd( THEPL, qtu( qs ) ) != VLC_SUCCESS )
                return ;

            services_discovery_descriptor_t test;

            if ( playlist_ServicesDiscoveryControl( THEPL, qtu( qs ),
                                                    SD_CMD_DESCRIPTOR, &test ) == VLC_SUCCESS )
            {
                item->setData( 0, CAP_SEARCH_ROLE, (test.i_capabilities & SD_CAP_SEARCH) );
            }
        }
        else
        {
            /* an on-line service left empty (network hiccup during its
             * one-shot discovery) has no other way to retry: selecting
             * it again restarts the module, in the background (removing
             * a service joins its thread, which may sit in a network
             * fetch — doing that here would freeze the UI) */
            bool b_empty = false;
            playlist_Lock( THEPL );
            playlist_item_t *p_node = playlist_ChildSearchName( &(THEPL->root),
                vlc_gettext(qtu(item->data(0, LONGNAME_ROLE).toString())) );
            if( p_node != NULL )
            {
                if( p_node->i_children <= 0 )
                    b_empty = true;
                else if( p_node->i_children == 1 )
                {
                    /* only the error placeholder a service script adds
                     * after a failed discovery */
                    playlist_item_t *p_child = p_node->pp_children[0];
                    b_empty = p_child->i_children < 0 && p_child->p_input
                           && p_child->p_input->psz_uri
                           && !strcmp( p_child->p_input->psz_uri, "vlc://nop" );
                }
            }
            playlist_Unlock( THEPL );
            const int special = item->data( 0, SPECIAL_ROLE ).toInt();
            if( b_empty && special != IS_POWER_ML
             && special != IS_POWER_DEVICE && !b_sd_reload_busy )
            {
                /* reclaim the previous, finished reload thread (there is
                 * no detached variant in this core) */
                if( b_sd_reload_joinable )
                {
                    vlc_join( sd_reload_thread, NULL );
                    b_sd_reload_joinable = false;
                }
                struct sd_reload_request *req =
                    (struct sd_reload_request *)calloc( 1, sizeof( *req ) );
                char *name = strdup( qtu( qs ) );
                if( req != NULL && name != NULL )
                {
                    req->playlist = THEPL;
                    req->name = name;
                    b_sd_reload_busy = true;
                    if( vlc_clone( &sd_reload_thread, RunSDReload, req,
                                   VLC_THREAD_PRIORITY_LOW ) == 0 )
                    {
                        b_sd_reload_joinable = true;
                        req = NULL;
                        name = NULL; /* owned by the thread */
                    }
                    else
                        b_sd_reload_busy = false;
                }
                free( name );
                free( req );
            }
        }
    }

    curItem = item;

    /* */
    playlist_Lock( THEPL );
    playlist_item_t *pl_item = NULL;

    /* Special case for podcast */
    // FIXME: simplify
    if( i_type == SD_TYPE )
    {
        /* Find the right item for the SD */
        /* FIXME: searching by name - what could possibly go wrong? */
        pl_item = playlist_ChildSearchName( &(THEPL->root),
            vlc_gettext(qtu(item->data(0, LONGNAME_ROLE).toString())) );

        /* Podcasts */
        if( item->data( 0, SPECIAL_ROLE ).toInt() == IS_PODCAST )
        {
            if( pl_item && !sd_loaded )
            {
                podcastsParentId = pl_item->i_id;
                for( int i=0; i < pl_item->i_children; i++ )
                    addPodcastItem( pl_item->pp_children[i] );
            }
            pl_item = NULL; //to prevent activating it
        }
    }
    else
        pl_item = item->data( 0, PL_ITEM_ROLE ).value<playlist_item_t*>();

    playlist_Unlock( THEPL );

    /* */
    if( pl_item )
    {
        int special = item->data( 0, SPECIAL_ROLE ).toInt();
        emit categoryActivated( pl_item, special == IS_POWER_ML
                                      || special == IS_POWER_DEVICE );
        int i_cat = item->data( 0, SD_CATEGORY_ROLE ).toInt();
        emit SDCategorySelected( i_cat == SD_CAT_INTERNET
                                 || i_cat == SD_CAT_LAN );
    }
}

PLSelItem * PLSelector::addItem (
    SelectorItemType type, const char* str, bool drop, bool bold,
    QTreeWidgetItem* parentItem )
{
  QTreeWidgetItem *item = parentItem ?
      new QTreeWidgetItem( parentItem ) : new QTreeWidgetItem( this );

  PLSelItem *selItem = new PLSelItem( item, qtr( str ),
                                      type == CATEGORY_TYPE );


  if ( bold ) {
      auto updateStyle = [selItem]() {
          selItem->setStyleSheet( "font-weight: bold;" );
      };
      updateStyle();
//same as Qt::AA_UseStyleSheetPropagationInWidgetStyles
#if !HAS_QT57
      connect(qApp, &QApplication::paletteChanged, selItem, [updateStyle](){
          updateStyle();
      });
#endif
  }
  setItemWidget( item, 0, selItem );
  item->setData( 0, TYPE_ROLE, (int)type );
  if( !drop ) item->setFlags( item->flags() & ~Qt::ItemIsDropEnabled );

  return selItem;
}

PLSelItem *PLSelector::addPodcastItem( playlist_item_t *p_item )
{
    input_item_Hold( p_item->p_input );

    char *psz_name = input_item_GetName( p_item->p_input );
    PLSelItem *item = addItem( PL_ITEM_TYPE,  psz_name, false, false, podcastsParent );
    free( psz_name );

    item->addAction( RM_ACTION, qtr( "Remove this podcast subscription" ) );
    item->treeItem()->setData( 0, PL_ITEM_ROLE, QVariant::fromValue( p_item ) );
    item->treeItem()->setData( 0, PL_ITEM_ID_ROLE, QVariant(p_item->i_id) );
    item->treeItem()->setData( 0, IN_ITEM_ROLE, QVariant::fromValue( p_item->p_input ) );
    connect( item, &PLSelItem::action, this, &PLSelector::podcastRemove );
    return item;
}

QStringList PLSelector::mimeTypes() const
{
    QStringList types;
    types << "vlc/qt-input-items" << "text/uri-list";
    return types;
}

bool PLSelector::dropMimeData ( QTreeWidgetItem * parent, int,
    const QMimeData * data, Qt::DropAction )
{
    if( !parent ) return false;

    QVariant type = parent->data( 0, TYPE_ROLE );
    if( type == QVariant() ) return false;

    int i_truth = parent->data( 0, SPECIAL_ROLE ).toInt();
    if( i_truth != IS_PL && i_truth != IS_ML && i_truth != IS_POWER_ML
     && i_truth != IS_POWER_DEVICE )
        return false;

    if( i_truth == IS_POWER_DEVICE )
    {
        const QString service = parent->data( 0, NAME_ROLE ).toString();
        if( !playlist_IsServicesDiscoveryLoaded( THEPL, qtu( service ) )
         && playlist_ServicesDiscoveryAdd( THEPL, qtu( service ) )
                                                        != VLC_SUCCESS )
            return false;
        bool queued = false;
        const PlMimeData *plMimeData = qobject_cast<const PlMimeData *>( data );
        if( plMimeData )
            for( input_item_t *input : plMimeData->inputItems() )
            {
                char *uri = input_item_GetURI( input );
                char *path = uri ? vlc_uri2path( uri ) : NULL;
                free( uri );
                if( path == NULL ) continue;
                services_discovery_import_t request = {
                    path, NULL, NULL, NULL, input
                };
                queued |= playlist_ServicesDiscoveryControl( THEPL,
                    qtu( service ), SD_CMD_POWERVLC_DEVICE_ADD, &request )
                    == VLC_SUCCESS;
                free( path );
            }
        for( const QUrl &url : data->urls() )
        {
            if( !url.isLocalFile() ) continue;
            QByteArray path = QFile::encodeName( url.toLocalFile() );
            services_discovery_import_t request = {
                path.constData(), NULL, NULL, NULL, NULL
            };
            queued |= playlist_ServicesDiscoveryControl( THEPL,
                qtu( service ), SD_CMD_POWERVLC_DEVICE_ADD, &request )
                == VLC_SUCCESS;
        }
        return queued;
    }

    if( i_truth == IS_POWER_ML )
    {
        const QString service = parent->data( 0, NAME_ROLE ).toString();
        if( !playlist_IsServicesDiscoveryLoaded( THEPL, qtu( service ) )
         && playlist_ServicesDiscoveryAdd( THEPL, qtu( service ) ) != VLC_SUCCESS )
            return false;
        bool imported = false;
        const PlMimeData *plMimeData = qobject_cast<const PlMimeData *>( data );
        if( plMimeData )
        {
            const QList<input_item_t *> inputItems = plMimeData->inputItems();
            for( input_item_t *input : inputItems )
            {
                char *uri = input_item_GetURI( input );
                char *path = uri ? vlc_uri2path( uri ) : NULL;
                free( uri );
                if( path == NULL ) continue;
                char *title = input_item_GetTitle( input );
                char *artist = input_item_GetArtist( input );
                char *album = input_item_GetAlbum( input );
                services_discovery_import_t request = { path, title, artist, album, NULL };
                imported |= playlist_ServicesDiscoveryControl( THEPL,
                    qtu( service ), SD_CMD_POWERVLC_IMPORT, &request ) == VLC_SUCCESS;
                free( path ); free( title ); free( artist ); free( album );
            }
        }
        for( const QUrl &url : data->urls() )
        {
            if( !url.isLocalFile() ) continue;
            QByteArray path = QFile::encodeName( url.toLocalFile() );
            services_discovery_import_t request = { path.constData(), NULL, NULL, NULL, NULL };
            imported |= playlist_ServicesDiscoveryControl( THEPL,
                qtu( service ), SD_CMD_POWERVLC_IMPORT, &request ) == VLC_SUCCESS;
        }
        return imported;
    }

    bool to_pl = ( i_truth == IS_PL );

    const PlMimeData *plMimeData = qobject_cast<const PlMimeData*>( data );
    if( !plMimeData ) return false;

    QList<input_item_t*> inputItems = plMimeData->inputItems();

    playlist_Lock( THEPL );

    foreach( input_item_t *p_input, inputItems )
    {
        playlist_item_t *p_item = playlist_ItemGetByInput( THEPL, p_input );
        if( !p_item ) continue;

        playlist_NodeAddCopy( THEPL, p_item,
                              to_pl ? THEPL->p_playing : THEPL->p_media_library,
                              PLAYLIST_END );
    }

    playlist_Unlock( THEPL );

    return true;
}

void PLSelector::dragMoveEvent ( QDragMoveEvent * event )
{
    event->setDropAction( Qt::CopyAction );
    QAbstractItemView::dragMoveEvent( event );
}

void PLSelector::plItemAdded( int item, int parent )
{
    updateTotalDuration(playlistItem, "Playlist");
    if( parent != podcastsParentId || podcastsParent == NULL ) return;

    playlist_Lock( THEPL );

    playlist_item_t *p_item = playlist_ItemGetById( THEPL, item );
    if( !p_item ) {
        playlist_Unlock( THEPL );
        return;
    }

    int c = podcastsParent->childCount();
    for( int i = 0; i < c; i++ )
    {
        QTreeWidgetItem *podItem = podcastsParent->child(i);
        if( podItem->data( 0, PL_ITEM_ID_ROLE ).toInt() == item )
        {
          //msg_Dbg( p_intf, "Podcast already in: (%d) %s", item, p_item->p_input->psz_uri);
          playlist_Unlock( THEPL );
          return;
        }
    }

    //msg_Dbg( p_intf, "Adding podcast: (%d) %s", item, p_item->p_input->psz_uri );
    addPodcastItem( p_item );

    playlist_Unlock( THEPL );

    podcastsParent->setExpanded( true );
}

void PLSelector::plItemRemoved( int id )
{
    updateTotalDuration(playlistItem, "Playlist");
    if( !podcastsParent ) return;

    int c = podcastsParent->childCount();
    for( int i = 0; i < c; i++ )
    {
        QTreeWidgetItem *item = podcastsParent->child(i);
        if( item->data( 0, PL_ITEM_ID_ROLE ).toInt() == id )
        {
            input_item_t *p_input = item->data( 0, IN_ITEM_ROLE ).value<input_item_t*>();
            //msg_Dbg( p_intf, "Removing podcast: (%d) %s", id, p_input->psz_uri );
            input_item_Release( p_input );
            delete item;
            return;
        }
    }
}

void PLSelector::inputItemUpdate( input_item_t *arg )
{
    updateTotalDuration(playlistItem, "Playlist");

    if( podcastsParent == NULL )
        return;

    int c = podcastsParent->childCount();
    for( int i = 0; i < c; i++ )
    {
        QTreeWidgetItem *item = podcastsParent->child(i);
        input_item_t *p_input = item->data( 0, IN_ITEM_ROLE ).value<input_item_t*>();
        if( p_input == arg )
        {
            PLSelItem *si = itemWidget( item );
            char *psz_name = input_item_GetName( p_input );
            si->setText( qfu( psz_name ) );
            free( psz_name );
            return;
        }
    }
}

void PLSelector::podcastAdd( PLSelItem * )
{
    assert( podcastsParent );

    bool ok;
    QString url = QInputDialog::getText( this, qtr( "Subscribe" ),
                                         qtr( "Enter URL of the podcast to subscribe to:" ),
                                         QLineEdit::Normal, QString(), &ok );
    if( !ok || url.isEmpty() ) return;

    setSource( podcastsParent ); //to load the SD in case it's not loaded

    QString request("ADD:");
    request += url.trimmed();
    var_SetString( THEPL, "podcast-request", qtu( request ) );
}

void PLSelector::podcastRemove( PLSelItem* item )
{
    QString question ( qtr( "Do you really want to unsubscribe from %1?" ) );
    question = question.arg( item->text() );
    QMessageBox::StandardButton res =
        QMessageBox::question( this, qtr( "Unsubscribe" ), question,
                               QMessageBox::Yes | QMessageBox::No,
                               QMessageBox::No );
    if( res == QMessageBox::No ) return;

    input_item_t *input = item->treeItem()->data( 0, IN_ITEM_ROLE ).value<input_item_t*>();
    if( !input ) return;

    QString request("RM:");
    char *psz_uri = input_item_GetURI( input );
    request += qfu( psz_uri );
    var_SetString( THEPL, "podcast-request", qtu( request ) );
    free( psz_uri );
}

PLSelItem * PLSelector::itemWidget( QTreeWidgetItem *item )
{
    return ( static_cast<PLSelItem*>( QTreeWidget::itemWidget( item, 0 ) ) );
}

void PLSelector::drawBranches ( QPainter * painter, const QRect & rect, const QModelIndex & index ) const
{
    if( !model()->hasChildren( index ) ) return;
    QStyleOption option;
    option.initFrom( this );
    option.rect = rect.adjusted( rect.width() - indentation(), 0, 0, 0 );
    style()->drawPrimitive( isExpanded( index ) ?
                            QStyle::PE_IndicatorArrowDown :
                            QStyle::PE_IndicatorArrowRight, &option, painter );
}

void PLSelector::getCurrentItemInfos( int* type, bool* can_delay_search, QString *string)
{
    *type = currentItem()->data( 0, TYPE_ROLE ).toInt();
    *string = currentItem()->data( 0, NAME_ROLE ).toString();
    *can_delay_search = currentItem()->data( 0, CAP_SEARCH_ROLE ).toBool();
}

int PLSelector::getCurrentItemCategory()
{
    return currentItem()->data( 0, SPECIAL_ROLE ).toInt();
}

void PLSelector::wheelEvent( QWheelEvent *e )
{
    if( verticalScrollBar()->isVisible() && (
        (verticalScrollBar()->value() != verticalScrollBar()->minimum() && e->angleDelta().y() >= 0 ) ||
        (verticalScrollBar()->value() != verticalScrollBar()->maximum() && e->angleDelta().y() < 0 )
        ) )
        QApplication::sendEvent(verticalScrollBar(), e);

    // Accept this event in order to prevent unwanted volume up/down changes
    e->accept();
}
