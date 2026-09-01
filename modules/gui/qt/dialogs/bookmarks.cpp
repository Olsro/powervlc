/*****************************************************************************
 * bookmarks.cpp : Bookmarks
 ****************************************************************************
 * Copyright (C) 2007-2008 the VideoLAN team
 *
 * Authors: Antoine Lejeune <phytos@via.ecp.fr>
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

#include "dialogs/bookmarks.hpp"
#include "input_manager.hpp"

#include <QHBoxLayout>
#include <QSpacerItem>
#include <QPushButton>
#include <QDialogButtonBox>
#include <QModelIndexList>
#include <QFileDialog>
#include <QFileInfo>
#include <QDir>
#include <QMessageBox>
#include <QTimer>

BookmarksDialog::BookmarksDialog( intf_thread_t *_p_intf ):QVLCFrame( _p_intf )
{
    b_ignore_updates = false;
    p_clipExport = NULL;
    setWindowFlags( Qt::Tool );
    setWindowOpacity( var_InheritFloat( p_intf, "qt-opacity" ) );
    setWindowTitle( qtr( "Edit Bookmarks" ) );
    setWindowRole( "vlc-bookmarks" );

    QHBoxLayout *layout = new QHBoxLayout( this );

    QDialogButtonBox *buttonsBox = new QDialogButtonBox( Qt::Vertical );
    QPushButton *addButton = new QPushButton( qtr( "Create" ) );
    addButton->setToolTip( qtr( "Create a new bookmark" ) );
    buttonsBox->addButton( addButton, QDialogButtonBox::ActionRole );
    delButton = new QPushButton( qtr( "Delete" ) );
    delButton->setToolTip( qtr( "Delete the selected item" ) );
    buttonsBox->addButton( delButton, QDialogButtonBox::ActionRole );
    clearButton = new QPushButton( qtr( "Clear" ) );
    clearButton->setToolTip( qtr( "Delete all the bookmarks" ) );
    buttonsBox->addButton( clearButton, QDialogButtonBox::ResetRole );
    clipButton = new QPushButton( qtr( "Make clip" ) );
    clipButton->setToolTip( qtr( "Make a clip up to the next bookmark or the end" ) );
    buttonsBox->addButton( clipButton, QDialogButtonBox::ActionRole );
    exportButton = new QPushButton( qtr( "Share…" ) );
    exportButton->setToolTip( qtr( "Export this content's bookmarks as JSON" ) );
    buttonsBox->addButton( exportButton, QDialogButtonBox::ActionRole );
    QPushButton *importButton = new QPushButton( qtr( "Import…" ) );
    buttonsBox->addButton( importButton, QDialogButtonBox::ActionRole );
    QPushButton *exportAllButton = new QPushButton( qtr( "Export all…" ) );
    buttonsBox->addButton( exportAllButton, QDialogButtonBox::ActionRole );
    QPushButton *clearAllButton = new QPushButton( qtr( "Delete all saved…" ) );
    clearAllButton->setToolTip( qtr( "Permanently delete every saved bookmark" ) );
    buttonsBox->addButton( clearAllButton, QDialogButtonBox::ResetRole );
    /* ?? Feels strange as Qt guidelines will put reject on top */
    buttonsBox->addButton( new QPushButton( qtr( "&Close" ) ),
                          QDialogButtonBox::RejectRole);

    bookmarksList = new QTreeWidget( this );
    bookmarksList->setRootIsDecorated( false );
    bookmarksList->setAlternatingRowColors( true );
    bookmarksList->setSelectionMode( QAbstractItemView::ExtendedSelection );
    bookmarksList->setSelectionBehavior( QAbstractItemView::SelectRows );
    bookmarksList->setEditTriggers( QAbstractItemView::SelectedClicked );
    bookmarksList->setColumnCount( 3 );
    bookmarksList->resize( sizeHint() );

    QStringList headerLabels;
    headerLabels << qtr( "Description" );
    headerLabels << qtr( "Bytes" );
    headerLabels << qtr( "Time" );
    bookmarksList->setHeaderLabels( headerLabels );

    layout->addWidget( buttonsBox );
    layout->addWidget( bookmarksList );

    connect( THEMIM->getIM(), &InputManager::bookmarksChanged,
             this, &BookmarksDialog::update );

    connect( bookmarksList, &QTreeWidget::activated, this,
             &BookmarksDialog::activateItem );
    connect( bookmarksList, &QTreeWidget::itemChanged,
             this, &BookmarksDialog::edit );
    connect( bookmarksList->model(), &QAbstractItemModel::rowsInserted,
             this, &BookmarksDialog::updateButtons );
    connect( bookmarksList->model(), &QAbstractItemModel::rowsRemoved,
             this, &BookmarksDialog::updateButtons );
    connect( bookmarksList->selectionModel(), &QItemSelectionModel::selectionChanged,
             this, &BookmarksDialog::updateButtons );
    BUTTONACT( addButton, add );
    BUTTONACT( delButton, del );
    BUTTONACT( clearButton, clear );
    BUTTONACT( clipButton, makeClip );
    BUTTONACT( exportButton, exportCurrent );
    BUTTONACT( importButton, importFile );
    BUTTONACT( exportAllButton, exportAll );
    BUTTONACT( clearAllButton, clearAll );
    connect( buttonsBox, &QDialogButtonBox::rejected, this, &BookmarksDialog::close );
    clipExportTimer = new QTimer( this );
    clipExportTimer->setInterval( 250 );
    connect( clipExportTimer, &QTimer::timeout,
             this, &BookmarksDialog::pollClipExport );
    updateButtons();

    restoreWidgetPosition( "Bookmarks", QSize( 435, 280 ) );
    updateGeometry();
}

BookmarksDialog::~BookmarksDialog()
{
    if( p_clipExport )
    {
        free( input_ClipExportFinish(p_clipExport) );
        p_clipExport = NULL;
    }
    saveWidgetPosition( "Bookmarks" );
}

void BookmarksDialog::updateButtons()
{
    clearButton->setEnabled( bookmarksList->model()->rowCount() > 0 );
    delButton->setEnabled( bookmarksList->selectionModel()->hasSelection() );
    clipButton->setEnabled( bookmarksList->selectionModel()->selectedRows().count() == 1
                            && p_clipExport == NULL );
    exportButton->setEnabled( bookmarksList->model()->rowCount() > 0 );
}

void BookmarksDialog::update()
{
    if ( b_ignore_updates ) return;
    input_thread_t *p_input = THEMIM->getInput();
    if( !p_input ) return;

    seekpoint_t **pp_bookmarks;
    int i_bookmarks = 0;

    if( bookmarksList->topLevelItemCount() > 0 )
    {
        bookmarksList->model()->removeRows( 0, bookmarksList->topLevelItemCount() );
    }

    if( input_Control( p_input, INPUT_GET_BOOKMARKS, &pp_bookmarks,
                       &i_bookmarks ) != VLC_SUCCESS )
        return;

    for( int i = 0; i < i_bookmarks; i++ )
    {
        vlc_tick_t total = pp_bookmarks[i]->i_time_offset;
        unsigned hours   = ( total / ( CLOCK_FREQ * 3600 ) );
        unsigned minutes = ( total % ( CLOCK_FREQ * 3600 ) ) / ( CLOCK_FREQ * 60 );
        float    seconds = ( total % ( CLOCK_FREQ * 60 ) ) / ( CLOCK_FREQ * 1. );

        QStringList row;
        row << QString( qfu( pp_bookmarks[i]->psz_name ) );
        row << qfu("-");
        row << QString( "%1:%2:%3" ).arg( hours, 2, 10, QChar('0')).arg( minutes, 2, 10, QChar('0')).arg(seconds, 10, 'f', 3, QChar('0'));

        QTreeWidgetItem *item = new QTreeWidgetItem( bookmarksList, row );
        item->setFlags( Qt::ItemIsSelectable | Qt::ItemIsEditable |
                        Qt::ItemIsUserCheckable | Qt::ItemIsEnabled);
        bookmarksList->insertTopLevelItem( i, item );
        vlc_seekpoint_Delete( pp_bookmarks[i] );
    }
    free( pp_bookmarks );
}

void BookmarksDialog::add()
{
    input_thread_t *p_input = THEMIM->getInput();
    if( !p_input ) return;

    seekpoint_t bookmark;

    if( !input_Control( p_input, INPUT_GET_BOOKMARK, &bookmark ) )
    {
        QString name = THEMIM->getIM()->getName() + " #"
                     + QString::number( bookmarksList->topLevelItemCount() );
        QByteArray raw = name.toUtf8();
        bookmark.psz_name = raw.data();

        input_Control( p_input, INPUT_ADD_BOOKMARK, &bookmark );
    }
}

void BookmarksDialog::del()
{
    input_thread_t *p_input = THEMIM->getInput();
    if( !p_input ) return;

    QModelIndexList selected = bookmarksList->selectionModel()->selectedRows();
    if ( !selected.empty() )
    {
        b_ignore_updates = true;
        /* Sort needed to make sure that selected elements are deleted in descending
           order, otherwise the indexes might change and wrong bookmarks are deleted. */
        std::sort( selected.begin(), selected.end() );
        QModelIndexList::Iterator it = selected.end();
        for( --it; it != selected.begin(); it-- )
        {
            input_Control( p_input, INPUT_DEL_BOOKMARK, (*it).row() );
        }
        input_Control( p_input, INPUT_DEL_BOOKMARK, (*it).row() );
        b_ignore_updates = false;
        update();
    }
}

void BookmarksDialog::clear()
{
    input_thread_t *p_input = THEMIM->getInput();
    if( !p_input ) return;

    input_Control( p_input, INPUT_CLEAR_BOOKMARKS );
}

void BookmarksDialog::clearAll()
{
    if( QMessageBox::warning(this, qtr("Delete all saved bookmarks?"),
            qtr("This permanently deletes bookmarks for every content and every disc title. This action cannot be undone."),
            QMessageBox::Yes | QMessageBox::Cancel, QMessageBox::Cancel)
        != QMessageBox::Yes )
        return;

    input_BookmarksClearAll( p_intf );
    input_thread_t *p_input = THEMIM->getInput();
    if( p_input )
        input_Control( p_input, INPUT_CLEAR_BOOKMARKS );
    update();
}

void BookmarksDialog::exportCurrent()
{
    input_thread_t *p_input = THEMIM->getInput();
    if( !p_input ) return;
    QString path = QFileDialog::getSaveFileName( this, qtr("Share bookmarks"),
        QDir::homePath() + "/bookmarks.pvlcbookmarks.json", qtr("PowerVLC bookmarks (*.json)" ) );
    if( path.isEmpty() ) return;
    if( input_BookmarksExport(p_input, qtu(path)) != VLC_SUCCESS )
        QMessageBox::critical( this, qtr("Export failed"),
                               qtr("The bookmarks file could not be written.") );
}

void BookmarksDialog::exportAll()
{
    QString path = QFileDialog::getSaveFileName( this, qtr("Export all bookmarks"),
        QDir::homePath() + "/all-bookmarks.pvlcbookmarks.json", qtr("PowerVLC bookmarks (*.json)" ) );
    if( path.isEmpty() ) return;
    if( input_BookmarksExportAll(p_intf, qtu(path)) != VLC_SUCCESS )
        QMessageBox::critical( this, qtr("Export failed"),
                               qtr("The bookmarks collection could not be written.") );
}

void BookmarksDialog::importFile()
{
    input_thread_t *p_input = THEMIM->getInput();
    QString path = QFileDialog::getOpenFileName( this, qtr("Import bookmarks"),
        QDir::homePath(), qtr("PowerVLC bookmarks (*.json);;JSON files (*.json)" ) );
    if( path.isEmpty() ) return;
    int result = p_input ? input_BookmarksImport(p_input, qtu(path))
                         : input_BookmarksImportAll(p_intf, qtu(path));
    if( result != VLC_SUCCESS )
        QMessageBox::critical( this, qtr("Import failed"),
            p_input ? qtr("This is not a valid PowerVLC bookmarks file.")
                    : qtr("A single-content file requires its content to be open. Without an open content, import an exported collection.") );
    update();
}

void BookmarksDialog::makeClip()
{
    input_thread_t *p_input = THEMIM->getInput();
    QModelIndexList rows = bookmarksList->selectionModel()->selectedRows();
    if( !p_input || rows.count() != 1 || p_clipExport ) return;

    seekpoint_t **pp_bookmarks = NULL;
    int i_bookmarks = 0;
    int64_t i_length = var_GetInteger( p_input, "length" );
    vlc_tick_t i_start = 0;
    vlc_tick_t i_stop = 0;
    char psz_duration[32];
    if( i_length <= 0 || input_Control(p_input, INPUT_GET_BOOKMARKS,
                                       &pp_bookmarks, &i_bookmarks) != VLC_SUCCESS )
        return;
    int i_selected = rows.first().row();
    if( i_selected < 0 || i_selected >= i_bookmarks ) goto cleanup;
    i_start = pp_bookmarks[i_selected]->i_time_offset;
    i_stop = i_length;
    for( int i = 0; i < i_bookmarks; i++ )
        if( pp_bookmarks[i]->i_time_offset > i_start
         && pp_bookmarks[i]->i_time_offset < i_stop )
            i_stop = pp_bookmarks[i]->i_time_offset;
    if( i_stop <= i_start ) goto cleanup;

    secstotimestr( psz_duration, (i_stop - i_start) / CLOCK_FREQ );
    if( QMessageBox::question(this, qtr("Create clip?"),
          qtr("Clip duration: %1\n\nCreating the clip can take some time, especially for discs and network content.")
              .arg(qfu(psz_duration)), QMessageBox::Yes | QMessageBox::Cancel,
          QMessageBox::Cancel) != QMessageBox::Yes )
        goto cleanup;

    p_clipExport = input_ClipExportNew( p_intf, p_input, i_start, i_stop );
    if( p_clipExport )
    {
        clipExportTimer->start();
    }
    else
    {
        /* DVD/Blu-ray titles cannot be cloned safely: record the selected
         * title in real time, with the same bounded core path as clip mode. */
        var_SetInteger( p_input, "record-stop-time", i_stop );
        var_SetInteger( p_input, "record-start-time", i_start );
        var_SetFloat( p_input, "record-clip-position",
                      (float)((double)i_start / (double)i_length) );
        if( var_GetInteger(p_input, "state") == PAUSE_S )
            playlist_TogglePause( THEPL );
        QMessageBox::information( this, qtr("Creating clip"),
            qtr("This content must be recorded in real time. Playback will continue until the clip is complete.") );
    }
cleanup:
    for( int i = 0; i < i_bookmarks; i++ )
        vlc_seekpoint_Delete( pp_bookmarks[i] );
    free( pp_bookmarks );
    updateButtons();
}

void BookmarksDialog::pollClipExport()
{
    if( !p_clipExport || input_ClipExportIsRunning(p_clipExport) ) return;
    clipExportTimer->stop();
    char *psz_file = input_ClipExportFinish( p_clipExport );
    p_clipExport = NULL;
    if( psz_file )
        QMessageBox::information( this, qtr("Clip saved"),
            qtr("The clip was saved as %1.").arg(QFileInfo(qfu(psz_file)).fileName()) );
    else
        QMessageBox::critical( this, qtr("Clip failed"),
                               qtr("The clip could not be created.") );
    free( psz_file );
    updateButtons();
}

void BookmarksDialog::edit( QTreeWidgetItem *item, int column )
{
    QStringList fields;
    // We can only edit a item if it is the last item selected
    if( bookmarksList->selectedItems().isEmpty() ||
        bookmarksList->selectedItems().last() != item )
        return;

    input_thread_t *p_input = THEMIM->getInput();
    if( !p_input )
        return;

    // We get the row number of the item
    int i_edit = bookmarksList->indexOfTopLevelItem( item );

    // We get the bookmarks list
    seekpoint_t** pp_bookmarks;
    seekpoint_t*  p_seekpoint = NULL;
    int i_bookmarks;

    if( input_Control( p_input, INPUT_GET_BOOKMARKS, &pp_bookmarks,
                       &i_bookmarks ) != VLC_SUCCESS )
        return;

    if( i_edit >= i_bookmarks )
        goto clear;

    // We modify the seekpoint
    p_seekpoint = pp_bookmarks[i_edit];
    if( column == 0 )
    {
        free( p_seekpoint->psz_name );
        p_seekpoint->psz_name = strdup( qtu( item->text( column ) ) );
    }
    else if( column == 2 )
    {
        fields = item->text( column ).split( ":",
                                      #if QT_VERSION >= QT_VERSION_CHECK(5, 14, 0)
                                        Qt::SkipEmptyParts
                                      #else
                                        QString::SkipEmptyParts
                                      #endif
                                    );
        if( fields.count() == 1 )
            p_seekpoint->i_time_offset = 1000000 * ( fields[0].toFloat() );
        else if( fields.count() == 2 )
            p_seekpoint->i_time_offset = 1000000 * ( fields[0].toInt() * 60 + fields[1].toInt() );
        else if( fields.count() == 3 )
            p_seekpoint->i_time_offset = 1000000 * ( fields[0].toInt() * 3600 + fields[1].toInt() * 60 + fields[2].toFloat() );
        else
        {
            msg_Err( p_intf, "Invalid string format for time" );
            goto clear;
        }
    }

    // Send the modification
    input_Control( p_input, INPUT_CHANGE_BOOKMARK, p_seekpoint, i_edit );

clear:
    // Clear the bookmark list
    for( int i = 0; i < i_bookmarks; i++)
        vlc_seekpoint_Delete( pp_bookmarks[i] );
    free( pp_bookmarks );
}

void BookmarksDialog::activateItem( QModelIndex index )
{
    input_thread_t *p_input = THEMIM->getInput();
    if( !p_input ) return;

    input_Control( p_input, INPUT_SET_BOOKMARK, index.row() );
}

void BookmarksDialog::toggleVisible()
{
    /* Update, to show existing bookmarks in case a new playlist
       was opened */
    if( !isVisible() )
    {
        update();
    }
    QVLCFrame::toggleVisible();
}
