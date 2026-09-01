/*****************************************************************************
 * standardpanel.cpp : The "standard" playlist panel : just a treeview
 ****************************************************************************
 * Copyright © 2000-2010 VideoLAN
 * $Id$
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Jean-Baptiste Kempf <jb@videolan.org>
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

#include "components/playlist/standardpanel.hpp"

#include "components/playlist/vlc_model.hpp"      /* VLCModel */
#include "components/playlist/playlist_model.hpp" /* PLModel */
#include "components/playlist/views.hpp"          /* 3 views */
#include "components/playlist/selector.hpp"       /* PLSelector */
#include "util/animators.hpp"                     /* PixmapAnimator */
#include "menus.hpp"                              /* Popup */
#include "input_manager.hpp"                      /* THEMIM */
#include "dialogs_provider.hpp"                   /* THEDP */
#include "recents.hpp"                            /* RecentMRL */
#include "dialogs/playlist.hpp"                   /* Playlist Dialog */
#include "dialogs/mediainfo.hpp"                  /* MediaInfoDialog */
#include "util/qt_dirs.hpp"
#include "util/imagehelper.hpp"

#include <vlc_services_discovery.h>               /* SD_CMD_SEARCH */
#include <vlc_intf_strings.h>                     /* POP_ */
#include <vlc_url.h>
#include <QMessageBox>
#include <QSet>

#define SPINNER_SIZE 32
#define I_NEW_DIR \
    I_DIR_OR_FOLDER( N_("Create Directory"), N_( "Create Folder" ) )
#define I_NEW_DIR_NAME \
    I_DIR_OR_FOLDER( N_( "Enter name for new directory:" ), \
                     N_( "Enter name for new folder:" ) )

#define I_RENAME_DIR \
    I_DIR_OR_FOLDER( N_("Rename Directory"), N_( "Rename Folder" ) )
#define I_RENAME_DIR_NAME \
    I_DIR_OR_FOLDER( N_( "Enter a new name for the directory:" ), \
                     N_( "Enter a new name for the folder:" ) )

#include <QHeaderView>
#include <QMenu>
#include <QMessageBox>
#include <QProcess>
#include <QStandardPaths>
#include <QTemporaryDir>
#include <QKeyEvent>
#include <QWheelEvent>
#include <QStackedLayout>
#include <QSignalMapper>
#include <QSettings>
#include <QStylePainter>
#include <QInputDialog>
#include <QDesktopServices>
#include <QUrl>
#include <QFont>
#include <QActionGroup>
#include <QTimer>

#include <assert.h>
#include <limits.h>
#include <stdlib.h>
#include <string.h>

#define DROPZONE_SIZE 112

/* local helper */
inline QModelIndex popupIndex( QAbstractItemView *view );
static void expandIndexPath( QTreeView *, const QModelIndex & );

static int powerVLCLibraryIntegerOption( input_item_t *input,
                                         const char *prefix )
{
    if( input == NULL || prefix == NULL )
        return -1;
    const size_t prefixLength = strlen( prefix );
    int value = -1;
    vlc_mutex_lock( &input->lock );
    for( int i = 0; i < input->i_options; ++i )
    {
        const char *option = input->ppsz_options[i];
        if( strncmp( option, prefix, prefixLength ) != 0 )
            continue;
        char *end = NULL;
        long parsed = strtol( option + prefixLength, &end, 10 );
        if( end != NULL && *end == '\0' && parsed >= 0 && parsed <= INT_MAX )
            value = (int)parsed;
        break;
    }
    vlc_mutex_unlock( &input->lock );
    return value;
}

static QString playlistItemName( VLCModel *model, const QModelIndex &index )
{
    input_item_t *input = model->getInputItem( index );
    char *name = input ? input_item_GetName( input ) : NULL;
    QString result = name ? qfu( name ) : QString();
    free( name );
    return result;
}

StandardPLPanel::StandardPLPanel( PlaylistWidget *_parent,
                                  intf_thread_t *_p_intf,
                                  playlist_item_t *p_root,
                                  PLSelector *_p_selector,
                                  VLCModel *_p_model )
                : QWidget( _parent ),
                  model( _p_model ),
                  p_intf( _p_intf ),
                  p_selector( _p_selector )
{
    viewStack = new QStackedLayout( this );
    viewStack->setSpacing( 0 ); viewStack->setContentsMargins( 0, 0, 0, 0 );
    setMinimumWidth( 300 );

    iconView    = NULL;
    treeView    = NULL;
    listView    = NULL;
    picFlowView = NULL;

    currentRootIndexPLId  = -1;
    lastActivatedPLItemId     = -1;
    listOnly = false;

    searchDelayTimer = new QTimer( this );
    searchDelayTimer->setSingleShot( true );
    searchDelayTimer->setInterval( 350 );
    connect( searchDelayTimer, &QTimer::timeout,
             this, &StandardPLPanel::applyDelayedLibrarySearch );
    searchLoadTimer = new QTimer( this );
    searchLoadTimer->setSingleShot( true );
    searchLoadTimer->setInterval( 150 );
    connect( searchLoadTimer, &QTimer::timeout,
             this, &StandardPLPanel::finishDelayedLibrarySearch );
    searchLoadRetries = 0;
    searchUsesMemoryIndex = false;
    memset( searchBucketMasks, 0, sizeof( searchBucketMasks ) );

    QList<QString> frames;
    frames << ":/util/wait1.svg";
    frames << ":/util/wait2.svg";
    frames << ":/util/wait3.svg";
    frames << ":/util/wait4.svg";
    spinnerAnimation = new PixmapAnimator( this, frames, SPINNER_SIZE, SPINNER_SIZE );
    connect( spinnerAnimation, &PixmapAnimator::pixmapReady, this, &StandardPLPanel::updateViewport );

    /* Saved Settings */
    int i_savedViewMode = getSettings()->value( "Playlist/view-mode", TREE_VIEW ).toInt();

    QFont font = QApplication::font();
    font.setPointSize( font.pointSize() + getSettings()->value( "Playlist/zoom", 0 ).toInt() );
    model->setData( QModelIndex(), font, Qt::FontRole );

    showView( i_savedViewMode );

    connect( THEMIM, &MainInputManager::leafBecameParent,
             this, QOverload<int>::of(&StandardPLPanel::browseInto), Qt::DirectConnection );

    connect( model, &VLCModel::currentIndexChanged,
             this, &StandardPLPanel::handleExpansion );
    connect( model, &VLCModel::rootIndexChanged, this, QOverload<>::of(&StandardPLPanel::browseInto) );

    setRootItem( p_root, false );
}

StandardPLPanel::~StandardPLPanel()
{
    getSettings()->beginGroup("Playlist");
    if( treeView )
        getSettings()->setValue( "headerStateV2", treeView->header()->saveState() );
    getSettings()->setValue( "view-mode", currentViewIndex() );
    getSettings()->setValue( "zoom",
                model->data( QModelIndex(), Qt::FontRole ).value<QFont>().pointSize()
                - QApplication::font().pointSize() );
    getSettings()->endGroup();
}

/* Unused anymore, but might be useful, like in right-click menu */
void StandardPLPanel::gotoPlayingItem()
{
    currentView->scrollTo( model->currentIndex() );
}

void StandardPLPanel::handleExpansion( const QModelIndex& index )
{
    assert( currentView );
    QModelIndex current = model->currentIndex();
    if( !current.isValid() )
        current = index;
    if( currentView != treeView && currentRootIndexPLId != -1
     && currentRootIndexPLId != model->itemId( current.parent() ) )
        browseInto( current.parent() );
    if( treeView != NULL && currentView == treeView )
        expandIndexPath( treeView, current );
    currentView->scrollTo( current );
    currentView->setCurrentIndex( current );
    currentView->viewport()->update();
}

void StandardPLPanel::popupPlView( const QPoint &point )
{
    QPoint globalPoint = currentView->viewport()->mapToGlobal( point );
    QModelIndex index = currentView->indexAt( point );
    if ( !index.isValid() )
    {
        currentView->clearSelection();
    }
    else if ( ! currentView->selectionModel()->selectedIndexes().contains( index ) )
    {
        currentView->selectionModel()->select( index, QItemSelectionModel::Select );
    }

    if( !popup( globalPoint ) ) THEDP->setPopupMenu();
}

/*********** Popup *********/
bool StandardPLPanel::popup( const QPoint &point )
{
    QModelIndex index = popupIndex( currentView ); /* index for menu logic only. Do not store.*/
    VLCModel *model = qobject_cast<VLCModel *>(currentView->model());
    PLModel *plModel = qobject_cast<PLModel *>(currentView->model());
    const bool userPlaylistsRoot = plModel && plModel->isUserPlaylistsRoot( index );
    const bool userPlaylistFolder = plModel && plModel->isUserPlaylistFolder( index );
    const bool userPlaylist = plModel && plModel->isUserPlaylist( index );

#define ADD_MENU_ENTRY( icon, title, act ) \
    if ( model->isSupportedAction( act, index ) )\
    {\
    action = menu.addAction( icon, title ); \
    container.action = act; \
    action->setData( QVariant::fromValue( container ) );\
    }

    /* */
    QMenu menu;
    QAction *action;
    VLCModelSubInterface::actionsContainerType container;

    /* Play/Stream/Info static actions */

    ADD_MENU_ENTRY( QIcon( ":/toolbar/play_b.svg" ), qtr(I_POP_PLAY),
                    VLCModelSubInterface::ACTION_PLAY )

    ADD_MENU_ENTRY( QIcon( ":/toolbar/pause_b.svg" ), qtr("Pause"),
                    VLCModelSubInterface::ACTION_PAUSE )

    ADD_MENU_ENTRY( QIcon( ":/menu/stream.svg" ), qtr(I_POP_STREAM),
                    VLCModelSubInterface::ACTION_STREAM )

    ADD_MENU_ENTRY( QIcon(), qtr(I_POP_SAVE),
                    VLCModelSubInterface::ACTION_SAVE );

    ADD_MENU_ENTRY( QIcon( ":/menu/info.svg" ), qtr(I_POP_INFO),
                    VLCModelSubInterface::ACTION_INFO );

    menu.addSeparator();

    ADD_MENU_ENTRY( QIcon( ":/type/folder-grey.svg" ), qtr(I_POP_EXPLORE),
                    VLCModelSubInterface::ACTION_EXPLORE );

    QIcon addIcon( ":/buttons/playlist/playlist_add.svg" );

    if( userPlaylistsRoot || userPlaylistFolder )
    {
        action = menu.addAction( addIcon, qtr( "New Playlist…" ) );
        action->setProperty( "powervlc-user-playlist-create", true );
        action = menu.addAction( QIcon( ":/type/folder-grey.svg" ),
                                 qtr( "New Playlist Folder…" ) );
        action->setProperty( "powervlc-user-playlist-folder-create", true );
    }
    if( userPlaylistFolder || userPlaylist )
    {
        action = menu.addAction( QIcon(), qtr( "Rename…" ) );
        action->setProperty( "powervlc-user-playlist-rename", true );
    }

    if( !userPlaylistsRoot && !userPlaylistFolder && !userPlaylist )
    {
        ADD_MENU_ENTRY( addIcon, qtr(I_POP_NEWFOLDER),
                        VLCModelSubInterface::ACTION_CREATENODE )

        ADD_MENU_ENTRY( QIcon(), qtr(I_POP_RENAMEFOLDER),
                        VLCModelSubInterface::ACTION_RENAMENODE )
    }

    menu.addSeparator();
    /* In PL or ML, allow to add a file/folder */
    ADD_MENU_ENTRY( addIcon, qtr(I_PL_ADDF),
                    VLCModelSubInterface::ACTION_ENQUEUEFILE )

    ADD_MENU_ENTRY( addIcon, qtr(I_PL_ADDDIR),
                    VLCModelSubInterface::ACTION_ENQUEUEDIR )

    ADD_MENU_ENTRY( addIcon, qtr(I_OP_ADVOP),
                    VLCModelSubInterface::ACTION_ENQUEUEGENERIC )

    ADD_MENU_ENTRY( QIcon(), qtr(I_PL_ADDPL),
                    VLCModelSubInterface::ACTION_ADDTOPLAYLIST );

    menu.addSeparator();
    ADD_MENU_ENTRY( QIcon(), qtr( I_PL_SAVE ),
                    VLCModelSubInterface::ACTION_SAVETOPLAYLIST );

    if( !currentView->selectionModel()->selectedRows().isEmpty() )
    {
        QAction *burn = menu.addAction( qtr( "Burn Playlist to Audio CD…" ) );
        burn->setProperty( "powervlc-audio-cd", true );
        QMenu *ratings = menu.addMenu( qtr( "Rating" ) );
        int commonRating = -1;
        if( plModel )
            plModel->ratingPaths( currentView->selectionModel()->selectedRows(),
                                  &commonRating );
        for( int value = 1; value <= 5; ++value )
        {
            QAction *star = ratings->addAction( QString( value, QChar( 0x2605 ) ) );
            star->setProperty( "powervlc-rating", value );
            star->setCheckable( true );
            star->setChecked( commonRating == value );
        }
        ratings->addSeparator();
        QAction *clear = ratings->addAction( qtr( "No Rating" ) );
        clear->setProperty( "powervlc-rating", 0 );
        clear->setCheckable( true );
        clear->setChecked( commonRating == 0 );
    }

    menu.addSeparator();

    /* Item removal */

    ADD_MENU_ENTRY( QIcon( ":/buttons/playlist/playlist_remove.svg" ), qtr(I_POP_DEL),
                    VLCModelSubInterface::ACTION_REMOVE );

    ADD_MENU_ENTRY( QIcon( ":/toolbar/clear.svg" ), qtr("Clear the playlist"),
                    VLCModelSubInterface::ACTION_CLEAR );

    menu.addSeparator();

    /* Playlist sorting */
    if ( model->isSupportedAction( VLCModelSubInterface::ACTION_SORT, index ) )
    {
        QMenu *sortingMenu = new QMenu( qtr( "Sort by" ), &menu );
        /* Choose what columns to show in sorting menu, not sure if this should be configurable*/
        QList<int> sortingColumns;
        sortingColumns << COLUMN_TITLE << COLUMN_ARTIST << COLUMN_ALBUM << COLUMN_TRACK_NUMBER << COLUMN_URI << COLUMN_DISC_NUMBER;
        container.action = VLCModelSubInterface::ACTION_SORT;
        foreach( int Column, sortingColumns )
        {
            action = sortingMenu->addAction( qfu( psz_column_title( Column ) ) + " " + qtr("Ascending") );
            container.column = model->columnFromMeta(Column) + 1;
            action->setData( QVariant::fromValue( container ) );

            action = sortingMenu->addAction( qfu( psz_column_title( Column ) ) + " " + qtr("Descending") );
            container.column = -1 * (model->columnFromMeta(Column)+1);
            action->setData( QVariant::fromValue( container ) );
        }
        menu.addMenu( sortingMenu );
    }
    if ( model->isSupportedAction( VLCModelSubInterface::ACTION_SHUFFLE, index ) )
    {
        ADD_MENU_ENTRY( QIcon(), qtr("Shuffle playlist"),
                    VLCModelSubInterface::ACTION_SHUFFLE );
    }

    /* Zoom */
    QMenu *zoomMenu = new QMenu( qtr( "Display size" ), &menu );
    zoomMenu->addAction( qtr( "Increase" ), this, SLOT( increaseZoom() ) );
    zoomMenu->addAction( qtr( "Decrease" ), this, SLOT( decreaseZoom() ) );
    menu.addMenu( zoomMenu );

    connect( &menu, &QMenu::triggered, this, &StandardPLPanel::popupAction );

    menu.addMenu( StandardPLPanel::viewSelectionMenu( this ) );

    /* Display and forward the result */
    if( !menu.isEmpty() )
    {
        menu.exec( point ); return true;
    }
    else return false;

#undef ADD_MENU_ENTRY
}

void StandardPLPanel::popupAction( QAction *action )
{
    PLModel *plModel = qobject_cast<PLModel *>( currentView->model() );
    QModelIndex playlistIndex = popupIndex( currentView );
    if( plModel && ( action->property( "powervlc-user-playlist-create" ).toBool()
                  || action->property( "powervlc-user-playlist-folder-create" ).toBool() ) )
    {
        const bool folder = action->property(
            "powervlc-user-playlist-folder-create" ).toBool();
        bool accepted = false;
        QString name = QInputDialog::getText(
            PlaylistDialog::getInstance( p_intf ),
            folder ? qtr( "New Playlist Folder" ) : qtr( "New Playlist" ),
            folder ? qtr( "Playlist folder name:" ) : qtr( "Playlist name:" ),
            QLineEdit::Normal, QString(), &accepted );
        if( accepted && !name.trimmed().isEmpty() )
            plModel->createUserPlaylist( playlistIndex, name, folder );
        return;
    }
    if( plModel
     && action->property( "powervlc-user-playlist-rename" ).toBool() )
    {
        bool accepted = false;
        QString name = QInputDialog::getText(
            PlaylistDialog::getInstance( p_intf ), qtr( "Rename" ),
            qtr( "New name:" ), QLineEdit::Normal,
            plModel->getTitle( playlistIndex ), &accepted );
        if( accepted && !name.trimmed().isEmpty() )
            plModel->renameUserPlaylist( playlistIndex, name );
        return;
    }
    if( action->property( "powervlc-audio-cd" ).toBool() )
    {
        burnAudioCD();
        return;
    }
    if( action->property( "powervlc-rating" ).isValid() )
    {
        unsigned rating = action->property( "powervlc-rating" ).toUInt();
        QStringList paths = plModel
            ? plModel->ratingPaths( currentView->selectionModel()->selectedRows(), NULL )
            : QStringList();
        QVector<QByteArray> storage;
        QVector<const char *> pointers;
        foreach( const QString &path, paths ) storage.append( path.toUtf8() );
        foreach( const QByteArray &path, storage ) pointers.append( path.constData() );
        if( !pointers.isEmpty() )
        {
            services_discovery_ratings_t request = {
                pointers.constData(), (size_t)pointers.size(), rating
            };
            playlist_ServicesDiscoveryControl( THEPL, "powervlc_library",
                SD_CMD_POWERVLC_SET_RATINGS, &request );
            currentView->viewport()->update();
        }
        return;
    }
    VLCModel *model = qobject_cast<VLCModel *>(currentView->model());
    VLCModelSubInterface::actionsContainerType a =
            action->data().value<VLCModelSubInterface::actionsContainerType>();
    QModelIndexList list = currentView->selectionModel()->selectedRows();
    QModelIndex index = popupIndex( currentView );
    char *path = NULL;
    OpenDialog *dialog;
    QString temp;
    QStringList uris;
    bool ok;

    /* first try to complete actions requiring missing parameters thru UI dialogs */
    switch( a.action )
    {
    case VLCModelSubInterface::ACTION_INFO:
        /* locally handled only */
        if( index.isValid() )
        {
            input_item_t* p_input = model->getInputItem( index );
            MediaInfoDialog *mid = new MediaInfoDialog( p_intf, p_input );
            mid->setParent( PlaylistDialog::getInstance( p_intf ),
                            Qt::Dialog );
            mid->show();
        }
        break;

    case VLCModelSubInterface::ACTION_EXPLORE:
        /* locally handled only */
        temp = model->getURI( index );
        if( ! temp.isEmpty() ) path = vlc_uri2path( temp.toLatin1().constData() );
        if( path == NULL ) return;
        temp = QFileInfo( qfu( path ) ).absolutePath();
        if( !QFileInfo( temp ).isDir() ) return;
        QDesktopServices::openUrl(
                    QUrl::fromLocalFile( temp ) );
        free( path );
        break;

    case VLCModelSubInterface::ACTION_STREAM:
        /* locally handled only */
        temp = model->getURI( index );
        if ( ! temp.isEmpty() )
        {
            QStringList tempList;
            tempList.append(temp);
            THEDP->streamingDialog( NULL, tempList, false );
        }
        break;

    case VLCModelSubInterface::ACTION_SAVE:
        /* locally handled only */
        temp = model->getURI( index );
        if ( ! temp.isEmpty() )
        {
            QStringList tempList;
            tempList.append(temp);
            THEDP->streamingDialog( NULL, tempList );
        }
        break;

    case VLCModelSubInterface::ACTION_CREATENODE:
        temp = QInputDialog::getText( PlaylistDialog::getInstance( p_intf ),
            qtr( I_NEW_DIR ), qtr( I_NEW_DIR_NAME ),
            QLineEdit::Normal, QString(), &ok);
        if ( !ok ) return;
        model->createNode( index, temp );
        break;

    case VLCModelSubInterface::ACTION_RENAMENODE:
        temp = QInputDialog::getText( PlaylistDialog::getInstance( p_intf ),
            qtr( I_RENAME_DIR ), qtr( I_RENAME_DIR_NAME ),
            QLineEdit::Normal, model->getTitle( index ), &ok);
        if ( !ok ) return;
        model->renameNode( index, temp );
        break;

    case VLCModelSubInterface::ACTION_ENQUEUEFILE:
        uris = THEDP->showSimpleOpen();
        if ( uris.isEmpty() ) return;
        uris.sort();
        a.uris = uris;
        action->setData( QVariant::fromValue( a ) );
        model->action( action, list );
        break;

    case VLCModelSubInterface::ACTION_ENQUEUEDIR:
        temp = DialogsProvider::getDirectoryDialog( p_intf );
        if ( temp.isEmpty() ) return;
        a.uris << temp;
        action->setData( QVariant::fromValue( a ) );
        model->action( action, list );
        break;

    case VLCModelSubInterface::ACTION_ENQUEUEGENERIC:
        dialog = OpenDialog::getInstance( this, p_intf, false, SELECT, true, true );
        dialog->showTab( OPEN_FILE_TAB );
        dialog->exec(); /* make it modal */
        a.uris = dialog->getMRLs( false );
        a.options = dialog->getOptions();
        if ( a.uris.isEmpty() ) return;
        action->setData( QVariant::fromValue( a ) );
        model->action( action, list );
        break;

    case VLCModelSubInterface::ACTION_SAVETOPLAYLIST:
        THEDP->savePlayingToPlaylist();
        break;
    default:
        model->action( action, list );
    }
}

static void collectBurnPaths( VLCModel *model, const QModelIndex &index,
                              QStringList &paths )
{
    if( model->rowCount( index ) > 0 )
    {
        for( int row = 0; row < model->rowCount( index ); ++row )
            collectBurnPaths( model, model->index( row, 0, index ), paths );
        return;
    }
    QUrl url( model->getURI( index ) );
    if( !url.isLocalFile() ) return;
    QString path = url.toLocalFile();
    const QString suffix = QFileInfo( path ).suffix().toLower();
    static const QStringList audio = QStringList() << "aac" << "aif" << "aiff"
        << "alac" << "flac" << "m4a" << "mp3" << "ogg" << "opus" << "wav";
    if( audio.contains( suffix ) ) paths << path;
}

void StandardPLPanel::burnAudioCD()
{
    VLCModel *playlistModel = qobject_cast<VLCModel *>( currentView->model() );
    QStringList paths;
    for( const QModelIndex &index : currentView->selectionModel()->selectedRows( 0 ) )
        collectBurnPaths( playlistModel, index, paths );
    paths.removeDuplicates();
    if( paths.isEmpty() )
    {
        QMessageBox::warning( this, qtr( "Burn Audio CD" ),
                              qtr( "The selection contains no local audio tracks." ) );
        return;
    }
    if( QMessageBox::question( this, qtr( "Burn Audio CD" ),
        qtr( "Burn %1 tracks to the blank Audio CD?" ).arg( paths.size() ) )
        != QMessageBox::Yes ) return;

    QTemporaryDir temporary( QDir::tempPath() + "/PowerVLC-Audio-CD-XXXXXX" );
    temporary.setAutoRemove( false );
    if( !temporary.isValid() ) return;
    int number = 1;
    for( const QString &source : paths )
    {
        QString extension = QFileInfo( source ).suffix();
        QString target = QDir( temporary.path() ).filePath(
            QString( "%1.%2" ).arg( number++, 3, 10, QLatin1Char( '0' ) )
                                .arg( extension ) );
        if( !QFile::link( source, target ) ) QFile::copy( source, target );
    }

    QString program;
    QStringList arguments;
#ifdef Q_OS_MAC
    program = "/usr/bin/drutil";
    arguments << "burn" << "-audio" << "-eject" << temporary.path();
#else
    program = QStandardPaths::findExecutable( "wodim" );
    if( program.isEmpty() ) program = QStandardPaths::findExecutable( "cdrecord" );
    bool pcmOnly = true;
    for( const QString &path : paths )
    {
        const QString suffix = QFileInfo( path ).suffix().toLower();
        if( suffix != "wav" && suffix != "aif" && suffix != "aiff" )
            pcmOnly = false;
    }
    if( program.isEmpty() || !pcmOnly )
    {
        QDir( temporary.path() ).removeRecursively();
        QMessageBox::information( this, qtr( "Burn Audio CD" ),
            qtr( "On this system, install wodim/cdrecord and use PCM WAV or AIFF tracks. PowerVLC can burn compressed tracks directly on macOS." ) );
        return;
    }
    arguments << "-v" << "-dao" << "-audio";
    QStringList staged = QDir( temporary.path() ).entryList( QDir::Files,
                                                             QDir::Name );
    for( const QString &file : staged )
        arguments << QDir( temporary.path() ).filePath( file );
#endif
    QProcess *process = new QProcess( this );
    const QString stagingPath = temporary.path();
    connect( process, static_cast<void (QProcess::*)(int, QProcess::ExitStatus)>(
        &QProcess::finished), this,
        [this, process, stagingPath]( int code, QProcess::ExitStatus status ) {
            QDir( stagingPath ).removeRecursively();
            if( status != QProcess::NormalExit || code != 0 )
                QMessageBox::warning( this, qtr( "Burn Audio CD" ),
                                      qtr( "The disc burning process failed." ) );
            process->deleteLater();
        } );
    process->start( program, arguments );
}

QMenu* StandardPLPanel::viewSelectionMenu( StandardPLPanel *panel )
{
    QMenu *viewMenu = new QMenu( qtr( "Playlist View Mode" ), panel );
    QSignalMapper *viewSelectionMapper = new QSignalMapper( viewMenu );
    connect( viewSelectionMapper, QSIGNALMAPPER_MAPPEDINT_SIGNAL, panel, &StandardPLPanel::showView );

    QActionGroup *viewGroup = new QActionGroup( viewMenu );
# define MAX_VIEW StandardPLPanel::VIEW_COUNT
    for( int i = 0; i < MAX_VIEW; i++ )
    {
        QAction *action = viewMenu->addAction( viewNames[i] );
        panel->viewActions.append( action );
        action->setCheckable( true );
        viewGroup->addAction( action );
        viewSelectionMapper->setMapping( action, i );
        connect( action, &QAction::triggered, viewSelectionMapper, QOverload<>::of(&QSignalMapper::map) );
        if( panel->currentViewIndex() == i )
            action->setChecked( true );
    }
    return viewMenu;
}

inline QModelIndex popupIndex( QAbstractItemView *view )
{
    QModelIndexList list = view->selectionModel()->selectedIndexes();
    if ( list.isEmpty() )
        return QModelIndex();
    else
        return list.first();
}

void StandardPLPanel::popupSelectColumn( QPoint )
{
    QMenu menu;
    assert( treeView );

    /* We do not offer the option to hide index 0 column, or
     * QTreeView will behave weird */
    for( int i = 1 << 1, j = 1; i < COLUMN_END; i <<= 1, j++ )
    {
        QAction* option = menu.addAction( qfu( psz_column_title( i ) ) );
        option->setCheckable( true );
        option->setChecked( !treeView->isColumnHidden( j ) );
        selectColumnsSigMapper->setMapping( option, j );
        connect( option, &QAction::triggered, selectColumnsSigMapper, QOverload<>::of(&QSignalMapper::map) );
    }
    menu.exec( QCursor::pos() );
}

void StandardPLPanel::toggleColumnShown( int i )
{
    treeView->setColumnHidden( i, !treeView->isColumnHidden( i ) );
}

/* Search in the playlist */
void StandardPLPanel::search( const QString& searchText )
{
    const QString normalizedSearchText = searchText.trimmed();
    int type;
    QString name;
    bool can_search;
    p_selector->getCurrentItemInfos( &type, &can_search, &name );

    if( type != SD_TYPE || !can_search )
    {
        PLModel *playlistModel = qobject_cast<PLModel *>( model );
        if( playlistModel != NULL && playlistModel->isPowerVLCLibraryRoot()
         && currentView == treeView )
        {
            pendingSearchText = normalizedSearchText;
            searchDelayTimer->start();
            return;
        }
        bool flat = ( currentView == iconView ||
                      currentView == listView ||
                      currentView == picFlowView );
        model->filter( normalizedSearchText,
                       flat ? currentView->rootIndex() : QModelIndex(),
                       !flat );
    }
}

QSet<int> StandardPLPanel::openLibraryCategoryIds() const
{
    QSet<int> ids;
    if( treeView == NULL )
        return ids;
    for( int row = 0; row < model->rowCount(); ++row )
    {
        QModelIndex section = model->index( row, 0, QModelIndex() );
        if( !treeView->isExpanded( section ) )
            continue;
        PLModel *playlistModel = qobject_cast<PLModel *>( model );
        if( playlistModel != NULL
         && playlistModel->isUserPlaylistsRoot( section ) )
        {
            ids.insert( model->itemId( section ) );
            continue;
        }
        for( int child = 0; child < model->rowCount( section ); ++child )
        {
            QModelIndex category = model->index( child, 0, section );
            if( treeView->isExpanded( category ) )
                ids.insert( model->itemId( category ) );
        }
    }
    return ids;
}

void StandardPLPanel::collapsePreviousSearchExpansion()
{
    PLModel *playlistModel = qobject_cast<PLModel *>( model );
    if( playlistModel == NULL || treeView == NULL )
        return;
    searchProtectedIds = playlistModel->protectedSearchItemIds();
    for( int id : searchExpandedIds )
    {
        if( searchProtectedIds.contains( id ) )
            continue;
        QModelIndex index = model->indexByPLID( id, 0 );
        if( index.isValid() )
            treeView->collapse( index );
    }
    searchExpandedIds.clear();
}

void StandardPLPanel::restoreProtectedSearchExpansion()
{
    if( treeView == NULL )
        return;
    for( int id : searchProtectedIds )
    {
        QModelIndex index = model->indexByPLID( id, 0 );
        QList<QModelIndex> path;
        for( QModelIndex cursor = index; cursor.isValid(); cursor = cursor.parent() )
            path.prepend( cursor );
        for( const QModelIndex &part : path )
            treeView->expand( part );
    }
}

static void expandIndexPath( QTreeView *view, const QModelIndex &index )
{
    QList<QModelIndex> path;
    for( QModelIndex cursor = index; cursor.isValid(); cursor = cursor.parent() )
        path.prepend( cursor );
    for( const QModelIndex &part : path )
        view->expand( part );
}

bool StandardPLPanel::requestSearchScopeLoading()
{
    if( treeView == NULL )
        return false;
    PLModel *playlistModel = qobject_cast<PLModel *>( model );
    if( playlistModel == NULL )
        return false;
    bool pending = false;
    for( int id : searchScopeIds )
    {
        QModelIndex scope = model->indexByPLID( id, 0 );
        if( !scope.isValid() )
            continue;
        treeView->expand( scope );
        const int view = powerVLCLibraryIntegerOption(
            model->getInputItem( scope ),
            VLC_INPUT_OPTION_POWERVLC_LIBRARY_VIEW_PREFIX );
        if( searchUsesMemoryIndex && view >= 0
         && view < SD_POWERVLC_LIBRARY_VIEW_COUNT )
        {
            const uint64_t mask = searchBucketMasks[view];
            for( int row = 0; row < model->rowCount( scope ); ++row )
            {
                QModelIndex bucketIndex = model->index( row, 0, scope );
                const int bucket = powerVLCLibraryIntegerOption(
                    model->getInputItem( bucketIndex ),
                    VLC_INPUT_OPTION_POWERVLC_LIBRARY_BUCKET_PREFIX );
                if( bucket < 0 || bucket >= 64
                 || !(mask & (UINT64_C(1) << bucket)) )
                    continue;
                if( !treeView->isExpanded( bucketIndex ) )
                {
                    searchExpandedIds.insert( model->itemId( bucketIndex ) );
                    treeView->expand( bucketIndex );
                }
                if( model->rowCount( bucketIndex ) == 0 )
                {
                    model->ensureBrowsed( bucketIndex );
                    pending = true;
                    continue;
                }
                for( const SearchBranchMatch &match : searchBranchMatches )
                {
                    if( match.view != (unsigned)view
                     || match.bucket != (unsigned)bucket )
                        continue;
                    QModelIndex primary;
                    for( int primaryRow = 0;
                         primaryRow < model->rowCount( bucketIndex );
                         ++primaryRow )
                    {
                        QModelIndex candidate = model->index( primaryRow, 0,
                                                              bucketIndex );
                        if( playlistModel->isRandomAction( candidate ) )
                            continue;
                        if( playlistItemName( model, candidate ).compare(
                                match.primary, Qt::CaseInsensitive ) == 0 )
                        {
                            primary = candidate;
                            break;
                        }
                    }
                    if( !primary.isValid() )
                        continue;
                    if( !treeView->isExpanded( primary ) )
                    {
                        searchExpandedIds.insert( model->itemId( primary ) );
                        treeView->expand( primary );
                    }
                    if( model->rowCount( primary ) == 0 )
                    {
                        model->ensureBrowsed( primary );
                        pending = true;
                        continue;
                    }
                    /* Albums view ends at the primary group. Other grouped
                     * views have one album level below it. */
                    if( view == 2 )
                        continue;
                    for( int albumRow = 0;
                         albumRow < model->rowCount( primary ); ++albumRow )
                    {
                        QModelIndex album = model->index( albumRow, 0, primary );
                        if( playlistModel->isRandomAction( album )
                         || playlistItemName( model, album ).compare(
                                match.secondary, Qt::CaseInsensitive ) != 0 )
                            continue;
                        if( !treeView->isExpanded( album ) )
                        {
                            searchExpandedIds.insert( model->itemId( album ) );
                            treeView->expand( album );
                        }
                        if( model->rowCount( album ) == 0 )
                        {
                            model->ensureBrowsed( album );
                            pending = true;
                        }
                        break;
                    }
                }
            }
        }
        else if( requestSearchLoadingInIndex( scope ) )
            pending = true;
    }
    return pending;
}

bool StandardPLPanel::requestSearchLoadingInIndex( const QModelIndex &index )
{
    bool pending = false;
    for( int row = 0; row < model->rowCount( index ); ++row )
    {
        QModelIndex child = model->index( row, 0, index );
        if( model->hasChildren( child ) )
        {
            if( !treeView->isExpanded( child ) )
            {
                searchExpandedIds.insert( model->itemId( child ) );
                treeView->expand( child );
            }
            if( model->rowCount( child ) == 0 )
            {
                model->ensureBrowsed( child );
                pending = true;
            }
        }
        if( model->rowCount( child ) > 0 )
            pending |= requestSearchLoadingInIndex( child );
    }
    return pending;
}

void StandardPLPanel::expandSearchMatches( const QModelIndex &index )
{
    if( !index.isValid() || model->rowCount( index ) <= 0 )
        return;
    if( !treeView->isExpanded( index ) )
    {
        searchExpandedIds.insert( model->itemId( index ) );
        treeView->expand( index );
    }
    for( int row = 0; row < model->rowCount( index ); ++row )
        expandSearchMatches( model->index( row, 0, index ) );
}

void StandardPLPanel::applyDelayedLibrarySearch()
{
    PLModel *playlistModel = qobject_cast<PLModel *>( model );
    if( playlistModel == NULL || treeView == NULL )
        return;

    searchLoadTimer->stop();
    searchScopeIds = openLibraryCategoryIds();
    /* Loading a lazy category rebuilds PLModel and can momentarily erase its
     * QTreeView expansion state. Keep scopes explicitly requested while a
     * query was active across that asynchronous rebuild. */
    searchScopeIds.unite( requestedSearchScopeIds );
    requestedSearchScopeIds.clear();
    collapsePreviousSearchExpansion();
    playlistModel->filterScopes( QString(), QSet<int>() );
    restoreProtectedSearchExpansion();
    for( int id : searchScopeIds )
    {
        QModelIndex scope = model->indexByPLID( id, 0 );
        if( scope.isValid() )
            expandIndexPath( treeView, scope );
    }
    if( pendingSearchText.isEmpty() )
    {
        searchScopeIds.clear();
        searchBranchMatches.clear();
        searchUsesMemoryIndex = false;
        return;
    }
    memset( searchBucketMasks, 0, sizeof( searchBucketMasks ) );
    searchBranchMatches.clear();
    services_discovery_library_search_t request = {};
    const QByteArray query = pendingSearchText.toUtf8();
    request.psz_query = query.constData();
    for( int id : searchScopeIds )
    {
        QModelIndex scope = model->indexByPLID( id, 0 );
        const int view = scope.isValid() ? powerVLCLibraryIntegerOption(
            model->getInputItem( scope ),
            VLC_INPUT_OPTION_POWERVLC_LIBRARY_VIEW_PREFIX ) : -1;
        if( view >= 0 && view < SD_POWERVLC_LIBRARY_VIEW_COUNT )
            request.i_view_mask |= UINT64_C(1) << view;
    }
    searchUsesMemoryIndex = request.i_view_mask != 0
        && playlist_ServicesDiscoveryControl( THEPL, "powervlc_library",
            SD_CMD_POWERVLC_LIBRARY_SEARCH, &request ) == VLC_SUCCESS;
    if( searchUsesMemoryIndex )
    {
        memcpy( searchBucketMasks, request.p_bucket_masks,
                sizeof( searchBucketMasks ) );
        for( size_t i = 0; i < request.i_match_count; ++i )
        {
            services_discovery_library_match_t *match = &request.p_matches[i];
            SearchBranchMatch copy = {
                match->i_view, match->i_bucket,
                qfu( match->psz_primary ? match->psz_primary : "" ),
                qfu( match->psz_secondary ? match->psz_secondary : "" )
            };
            searchBranchMatches.append( copy );
            free( match->psz_primary );
            free( match->psz_secondary );
        }
        free( request.p_matches );
    }
    searchLoadRetries = 0;
    finishDelayedLibrarySearch();
}

void StandardPLPanel::finishDelayedLibrarySearch()
{
    PLModel *playlistModel = qobject_cast<PLModel *>( model );
    if( playlistModel == NULL || treeView == NULL )
        return;
    if( requestSearchScopeLoading() && searchLoadRetries++ < 800 )
    {
        searchLoadTimer->start();
        return;
    }
    playlistModel->filterScopes( pendingSearchText, searchScopeIds );
    restoreProtectedSearchExpansion();
    for( int id : searchScopeIds )
    {
        QModelIndex scope = model->indexByPLID( id, 0 );
        if( scope.isValid() )
        {
            /* filterScopes() rebuilds the Qt model.  Expanding only the
             * category leaves its rebuilt Music parent collapsed, making a
             * successful indexed search look empty. Restore the complete
             * path before opening the exact matching descendants. */
            expandIndexPath( treeView, scope );
            expandSearchMatches( scope );
        }
    }
}

void StandardPLPanel::searchDelayed( const QString& searchText )
{
    int type;
    QString name;
    bool can_search;
    p_selector->getCurrentItemInfos( &type, &can_search, &name );

    if( type == SD_TYPE && can_search )
    {
        if( !name.isEmpty() && !searchText.isEmpty() )
            playlist_ServicesDiscoveryControl( THEPL, qtu( name ), SD_CMD_SEARCH,
                                              qtu( searchText ) );
    }
}

/* Set the root of the new Playlist */
/* This activated by the selector selection */
void StandardPLPanel::setRootItem( playlist_item_t *p_item, bool b )
{
    listOnly = b;
    for( int i = 0; i < viewActions.size(); ++i )
        viewActions[i]->setEnabled( !listOnly || i == TREE_VIEW );
    model->rebuild( p_item );
    if( listOnly && currentView != treeView )
        showView( TREE_VIEW );
}

void StandardPLPanel::browseInto( const QModelIndex &index )
{
    if( currentView == iconView || currentView == listView || currentView == picFlowView )
    {

        currentView->setRootIndex( index );

        /* When going toward root in LocationBar, scroll to the item
           that was previously as root */
        QModelIndex newIndex = model->indexByPLID(currentRootIndexPLId,0);
        while( newIndex.isValid() && (newIndex.parent() != index) )
            newIndex = newIndex.parent();
        if( newIndex.isValid() )
            currentView->scrollTo( newIndex );

        /* Store new rootindexid*/
        currentRootIndexPLId = model->itemId( index );

        model->ensureArtRequested( index );
    }

    emit viewChanged( index );
}

void StandardPLPanel::browseInto()
{
    browseInto( (currentRootIndexPLId != -1 && currentView != treeView) ?
                 model->indexByPLID( currentRootIndexPLId, 0 ) :
                 QModelIndex() );
}

void StandardPLPanel::wheelEvent( QWheelEvent *e )
{
    if( e->modifiers() & Qt::ControlModifier ) {
        int numSteps = e->angleDelta().y() / QWheelEvent::DefaultDeltasPerStep;
        if( numSteps > 0)
            increaseZoom();
        else if( numSteps < 0)
            decreaseZoom();
    }
    // Accept this event in order to prevent unwanted volume up/down changes
    e->accept();
}

bool StandardPLPanel::eventFilter ( QObject *obj, QEvent * event )
{
    if (event->type() == QEvent::KeyPress)
    {
        QKeyEvent *keyEvent = static_cast<QKeyEvent*>(event);
        if( keyEvent->key() == Qt::Key_Delete ||
            keyEvent->key() == Qt::Key_Backspace )
        {
            deleteSelection();
            return true;
        }
    }
    else if ( event->type() == QEvent::Paint )
    {/* Warn! Don't filter events from anything else than views ! */
        if ( model->rowCount() == 0 && p_selector->getCurrentItemCategory() == PL_ITEM_TYPE )
        {
            QWidget *viewport = qobject_cast<QWidget *>( obj );
            QStylePainter painter( viewport );

            QPixmap dropzone = ImageHelper::loadSvgToPixmap(":/dropzone.svg", DROPZONE_SIZE, DROPZONE_SIZE);
            QRect rect = viewport->geometry();
#if HAS_QT56
            qreal scale = dropzone.devicePixelRatio();
            QSize size = rect.size()  / 2 - dropzone.size() / (2 * scale);
#else
            QSize size = rect.size()  / 2 - dropzone.size() / 2;
#endif
            rect.adjust( 0, size.height(), 0 , 0 );
            painter.drawItemPixmap( rect, Qt::AlignHCenter, dropzone );
            /* now select the zone just below the drop zone and let Qt center
               the text by itself */
#if HAS_QT56
            rect.adjust( 0, dropzone.height() / scale + 10, 0, 0 );
#else
            rect.adjust( 0, dropzone.height() + 10, 0, 0 );
#endif
            rect.setRight( viewport->geometry().width() );
            rect.setLeft( 0 );
            painter.drawItemText( rect,
                                  Qt::AlignHCenter,
                                  palette(),
                                  true,
                                  qtr("Playlist is currently empty.\n"
                                      "Drop a file here or select a "
                                      "media source from the left."),
                                  QPalette::Text );
        }
        else if ( spinnerAnimation->state() == PixmapAnimator::Running )
        {
            if ( currentView->model()->rowCount() )
                spinnerAnimation->stop(); /* Trick until SD emits events */
            else
            {
                QWidget *viewport = qobject_cast<QWidget *>( obj );
                QStylePainter painter( viewport );
                const QPixmap& spinner = spinnerAnimation->getPixmap();
                QPoint point = viewport->geometry().center();
                point -= QPoint( spinner.width() / 2, spinner.height() / 2 );
                painter.drawPixmap( point, spinner );
            }
        }
    }
    return false;
}

void StandardPLPanel::deleteSelection()
{
    QModelIndexList list = currentView->selectionModel()->selectedIndexes();
    const QString service = p_selector->currentPowerDeviceService();
    if( !service.isEmpty() )
    {
        PLModel *playlistModel = qobject_cast<PLModel *>( model );
        for( const QModelIndex &index : list )
            if( playlistModel && playlistModel->isPowerVLCDeviceStructure( index ) )
                return;
        QVector<int> itemIds;
        for( const QModelIndex &index : list ) itemIds << model->itemId( index );
        services_discovery_device_delete_resolve_t resolved = {
            itemIds.constData(), (size_t)itemIds.size(), NULL, 0
        };
        if( playlist_ServicesDiscoveryControl( THEPL, qtu( service ),
                SD_CMD_POWERVLC_DEVICE_RESOLVE_DELETE, &resolved )
            != VLC_SUCCESS || resolved.i_count == 0 )
        {
            QMessageBox::warning( this, qtr( "Unable to Delete Selected Content" ),
                qtr( "PowerVLC could not resolve the selected rows to media stored on this player." ) );
            return;
        }
        if( QMessageBox::warning( this, qtr( "Delete Content from Portable Player?" ),
              qtr( "%1 item(s) will be permanently deleted from the player. "
                   "This action cannot be undone." ).arg( resolved.i_count ),
              QMessageBox::Ok | QMessageBox::Cancel, QMessageBox::Cancel )
            == QMessageBox::Ok )
        {
            services_discovery_device_delete_t request = {
                (const char *const *)resolved.ppsz_paths, resolved.i_count,
                itemIds.constData(), (size_t)itemIds.size()
            };
            if( playlist_ServicesDiscoveryControl( THEPL, qtu( service ),
                    SD_CMD_POWERVLC_DEVICE_DELETE, &request ) != VLC_SUCCESS )
                QMessageBox::warning( this,
                    qtr( "Unable to Delete Selected Content" ),
                    qtr( "The portable player rejected the deletion request. No content was changed." ) );
            else
                setEnabled( false );
        }
        for( size_t i = 0; i < resolved.i_count; ++i )
            free( resolved.ppsz_paths[i] );
        free( resolved.ppsz_paths );
        return;
    }
    model->doDelete( list );
}

void StandardPLPanel::createIconView()
{
    iconView = new PlIconView( model, this );
    iconView->setContextMenuPolicy( Qt::CustomContextMenu );
    connect( iconView, &PlIconView::customContextMenuRequested,
             this, &StandardPLPanel::popupPlView );
    connect( iconView, &PlIconView::activated,
             this, &StandardPLPanel::activate );
    iconView->installEventFilter( this );
    iconView->viewport()->installEventFilter( this );
    viewStack->addWidget( iconView );
}

void StandardPLPanel::createListView()
{
    listView = new PlListView( model, this );
    listView->setContextMenuPolicy( Qt::CustomContextMenu );
    connect( listView, &PlListView::customContextMenuRequested,
             this, &StandardPLPanel::popupPlView );
    connect( listView, &PlListView::activated,
             this, &StandardPLPanel::activate );
    listView->installEventFilter( this );
    listView->viewport()->installEventFilter( this );
    viewStack->addWidget( listView );
}

void StandardPLPanel::createCoverView()
{
    picFlowView = new PicFlowView( model, this );
    picFlowView->setContextMenuPolicy( Qt::CustomContextMenu );
    connect( picFlowView, &PicFlowView::customContextMenuRequested,
             this, &StandardPLPanel::popupPlView );
    connect( picFlowView, &PicFlowView::activated,
             this, &StandardPLPanel::activate );
    viewStack->addWidget( picFlowView );
    picFlowView->installEventFilter( this );
}

void StandardPLPanel::createTreeView()
{
    /* Create and configure the QTreeView */
    treeView = new PlTreeView( model, this );

    /* setModel after setSortingEnabled(true), or the model will sort immediately! */

    /* Connections for the TreeView */
    connect( treeView, &PlTreeView::activated,
             this, &StandardPLPanel::activate );
    connect( treeView, &PlTreeView::expanded,
             this, &StandardPLPanel::libraryCategoryExpanded );
    connect( treeView->header(), &QHeaderView::customContextMenuRequested,
             this, &StandardPLPanel::popupSelectColumn );
    connect( treeView, &PlTreeView::customContextMenuRequested,
             this, &StandardPLPanel::popupPlView );
    treeView->installEventFilter( this );
    treeView->viewport()->installEventFilter( this );

    /* SignalMapper for columns */
    selectColumnsSigMapper = new QSignalMapper( this );
    connect( selectColumnsSigMapper, QSIGNALMAPPER_MAPPEDINT_SIGNAL,
             this, &StandardPLPanel::toggleColumnShown );

    viewStack->addWidget( treeView );
}

void StandardPLPanel::libraryCategoryExpanded( const QModelIndex &index )
{
    PLModel *playlistModel = qobject_cast<PLModel *>( model );
    if( playlistModel == NULL || pendingSearchText.isEmpty()
     || !playlistModel->isPowerVLCLibraryRoot() )
        return;

    /* Only direct children of the Music section define search scopes.  A
     * programmatic expansion below that level must not restart the search. */
    QModelIndex section = index.parent();
    if( !section.isValid() || section.parent().isValid() )
        return;
    int id = model->itemId( index );
    if( searchScopeIds.contains( id ) )
        return;

    /* Do not rebuild the model from inside QTreeView::expanded.  Lazy
     * categories are populated asynchronously and an immediate rebuild can
     * invalidate the index while the mouse event is still being delivered,
     * opening a neighbouring category or leaving the view empty.  Reuse the
     * normal debounce: the local compact node has ample time to finish, then
     * the active query is applied to the newly opened scope. */
    requestedSearchScopeIds.insert( id );
    searchDelayTimer->start();
}

void StandardPLPanel::updateZoom( int i )
{
    QVariant fontdata = model->data( QModelIndex(), Qt::FontRole );
    QFont font = fontdata.value<QFont>();
    font.setPointSize( font.pointSize() + i );
    if ( font.pointSize() < 5 - QApplication::font().pointSize() ) return;
    if ( font.pointSize() > 3 + QApplication::font().pointSize() ) return;
    model->setData( QModelIndex(), font, Qt::FontRole );
}

void StandardPLPanel::showView( int i_view )
{
    if( listOnly ) i_view = TREE_VIEW;
    bool b_treeViewCreated = false;

    switch( i_view )
    {
    case ICON_VIEW:
    {
        if( iconView == NULL )
            createIconView();
        currentView = iconView;
        break;
    }
    case LIST_VIEW:
    {
        if( listView == NULL )
            createListView();
        currentView = listView;
        break;
    }
    case PICTUREFLOW_VIEW:
    {
        if( picFlowView == NULL )
            createCoverView();
        currentView = picFlowView;
        break;
    }
    default:
    case TREE_VIEW:
    {
        if( treeView == NULL )
        {
            createTreeView();
            b_treeViewCreated = true;
        }
        currentView = treeView;
        break;
    }
    }

    currentView->setModel( model );

    /* Restoring the header Columns must come after changeModel */
    if( b_treeViewCreated )
    {
        assert( treeView );
        if( getSettings()->contains( "Playlist/headerStateV2" ) )
        {
            treeView->header()->restoreState(getSettings()
                    ->value( "Playlist/headerStateV2" ).toByteArray() );
            /* if there is allready stuff in playlist, we don't sort it and we reset
               sorting */
            if( model->rowCount() )
            {
                treeView->header()->setSortIndicator( -1 , Qt::AscendingOrder );
            }
        }
        else
        {
            for( int m = 1, c = 0; m != COLUMN_END; m <<= 1, c++ )
            {
                treeView->setColumnHidden( c, !( m & COLUMN_DEFAULT ) );
                if( m == COLUMN_TITLE ) treeView->header()->resizeSection( c, 200 );
                else if( m == COLUMN_DURATION ) treeView->header()->resizeSection( c, 80 );
            }
        }
    }

    viewStack->setCurrentWidget( currentView );
    browseInto();
    gotoPlayingItem();
}

void StandardPLPanel::setWaiting( bool b )
{
    if ( b )
    {
        spinnerAnimation->setLoopCount( 20 ); /* Trick until SD emits an event */
        spinnerAnimation->start();
    }
    else
        spinnerAnimation->stop();
}

void StandardPLPanel::updateViewport()
{
    /* A single update on parent widget won't work */
    currentView->viewport()->repaint();
}

int StandardPLPanel::currentViewIndex() const
{
    if( currentView == treeView )
        return TREE_VIEW;
    else if( currentView == iconView )
        return ICON_VIEW;
    else if( currentView == listView )
        return LIST_VIEW;
    else
        return PICTUREFLOW_VIEW;
}

void StandardPLPanel::cycleViews()
{
    if( listOnly )
    {
        showView( TREE_VIEW );
        return;
    }
    if( currentView == iconView )
        showView( TREE_VIEW );
    else if( currentView == treeView )
        showView( LIST_VIEW );
    else if( currentView == listView )
#ifndef NDEBUG
        showView( PICTUREFLOW_VIEW  );
    else if( currentView == picFlowView )
#endif
        showView( ICON_VIEW );
    else
        vlc_assert_unreachable();
}

void StandardPLPanel::activate( const QModelIndex &index )
{
    if( currentView->model() == model )
    {
        /* If we are not a leaf node */
        const bool expandable = model->hasChildren( index )
            || !index.data( VLCModelSubInterface::LEAF_NODE_ROLE ).toBool();
        if( expandable )
        {
            if( currentView != treeView )
                browseInto( index );
            else
            {
                treeView->expand( index );
                model->activateItem( index );
            }
        }
        else
        {
            playlist_Lock( THEPL );
            playlist_item_t *p_item = playlist_ItemGetById( THEPL, model->itemId( index ) );
            if ( p_item )
            {
                p_item->i_flags |= PLAYLIST_SUBITEM_STOP_FLAG;
                lastActivatedPLItemId = p_item->i_id;
            }
            playlist_Unlock( THEPL );
            if ( p_item && index.isValid() )
                model->activateItem( index );
        }
    }
}

void StandardPLPanel::browseInto( int i_pl_item_id )
{
    if( i_pl_item_id != lastActivatedPLItemId ) return;

    QModelIndex index = model->indexByPLID( i_pl_item_id, 0 );

    if( currentView == treeView )
        treeView->setExpanded( index, true );
    else
        browseInto( index );

    lastActivatedPLItemId = -1;
}
