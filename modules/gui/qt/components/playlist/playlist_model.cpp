/*****************************************************************************
 * playlist_model.cpp : Manage playlist model
 ****************************************************************************
 * Copyright (C) 2006-2011 the VideoLAN team
 * $Id$
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Ilkka Ollakkka <ileoo (at) videolan dot org>
 *          Jakob Leben <jleben@videolan.org>
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
#include "components/playlist/playlist_model.hpp"
#include "input_manager.hpp"                            /* THEMIM */
#include "util/qt_dirs.hpp"
#include "recents.hpp"                                  /* Open:: */

#include <vlc_intf_strings.h>                           /* I_DIR */
#include <vlc_services_discovery.h>
#include <vlc_url.h>

#include "sorting.h"

#include <cassert>
#include <cctype>
#include <QDateTime>
#include <QFont>
#include <QAction>
#include <QStack>
#include <QBrush>
#include <QTimer>
#include <QVector>

static char *displayTrackTitle( input_item_t *input )
{
    char *title = input_item_GetTitleFbName( input );
    if( !title )
        return NULL;
    char *discText = input_item_GetDiscNumber( input );
    char *trackText = input_item_GetTrackNumber( input );
    unsigned long disc = discText ? strtoul( discText, NULL, 10 ) : 0;
    unsigned long track = trackText ? strtoul( trackText, NULL, 10 ) : 0;
    free( discText );
    free( trackText );
    if( !track )
        return title;

    char prefix[64];
    if( disc )
        snprintf( prefix, sizeof(prefix), "%lu.%lu. ", disc, track );
    else
        snprintf( prefix, sizeof(prefix), "%lu. ", track );
    if( !strncmp( title, prefix, strlen(prefix) ) )
        return title;
    if( !disc && isdigit( static_cast<unsigned char>( title[0] ) ) )
    {
        char *endDisc;
        strtoul( title, &endDisc, 10 );
        if( *endDisc == '.' && isdigit( static_cast<unsigned char>( endDisc[1] ) ) )
        {
            char *endTrack;
            unsigned long embeddedTrack = strtoul( endDisc + 1, &endTrack, 10 );
            if( embeddedTrack == track && !strncmp( endTrack, ". ", 2 ) )
                return title;
        }
    }
    char *formatted = NULL;
    if( asprintf( &formatted, "%s%s", prefix, title ) < 0 )
        formatted = NULL;
    free( title );
    return formatted;
}

static bool isExplicitRandomAction( input_item_t *input )
{
    return input && input_item_IsPowerVLCRandomAction( input );
}

static bool isPowerVLCIndexItem( input_item_t *input )
{
    return input && input_item_IsPowerVLCLazyIndex( input );
}

static void collectPlaylistItemIds( playlist_item_t *item, QSet<int> &ids )
{
    if( item == NULL )
        return;
    ids.insert( item->i_id );
    for( int i = 0; i < item->i_children; ++i )
        collectPlaylistItemIds( item->pp_children[i], ids );
}

static bool isSearchSubtreeLoaded( playlist_item_t *item )
{
    if( item == NULL )
        return true;
    for( int i = 0; i < item->i_children; ++i )
    {
        playlist_item_t *child = item->pp_children[i];
        if( child->p_input != NULL
         && !isExplicitRandomAction( child->p_input )
         && ( child->p_input->i_type == ITEM_TYPE_DIRECTORY
           || isPowerVLCIndexItem( child->p_input ) )
         && child->i_children <= 0 )
            return false;
        if( child->i_children > 0 && !isSearchSubtreeLoaded( child ) )
            return false;
    }
    return true;
}

/*************************************************************************
 * Playlist model implementation
 *************************************************************************/

PLModel::PLModel( playlist_t *_p_playlist,  /* THEPL */
                  intf_thread_t *_p_intf,   /* main Qt p_intf */
                  playlist_item_t * p_root,
                  QObject *parent )         /* Basic Qt parent */
                  : VLCModel( _p_intf, parent )
{
    p_playlist        = _p_playlist;

    rootItem          = NULL; /* PLItem rootItem, will be set in rebuild( ) */
    latestSearch      = QString();
    pendingRandomPlaybackId = -1;
    pendingRandomBranchId = -1;
    pendingNodePlaybackId = -1;
    pendingNodeBrowseId = -1;
    pendingNodePlaybackRetries = 0;

    rebuild( p_root );
    connect( THEMIM->getIM(), &InputManager::metaChanged,
             this, QOverload<input_item_t *>::of(&PLModel::processInputItemUpdate), Qt::DirectConnection );
    connect( THEMIM, &MainInputManager::inputChanged,
             this, QOverload<>::of(&PLModel::processInputItemUpdate), Qt::DirectConnection );
    connect( THEMIM, &MainInputManager::playlistItemAppended,
             this, &PLModel::processItemAppend );
    connect( THEMIM, &MainInputManager::playlistItemRemoved,
             this, &PLModel::processItemRemoval );
}

PLModel::~PLModel()
{
    delete rootItem;
}

Qt::DropActions PLModel::supportedDropActions() const
{
    return Qt::CopyAction | Qt::MoveAction;
}

Qt::ItemFlags PLModel::flags( const QModelIndex &index ) const
{
    Qt::ItemFlags flags = QAbstractItemModel::flags( index );

    const PLItem *item = index.isValid() ? getItem( index ) : rootItem;

    bool userTarget = index.isValid()
        && ( isUserPlaylistsRoot( index ) || isUserPlaylistFolder( index )
          || isUserPlaylist( index ) );
    if( canEdit() || userTarget )
    {
        vlc_playlist_locker pl_lock ( THEPL );

        playlist_item_t *plItem =
            playlist_ItemGetById( p_playlist, item->i_playlist_id );

        if ( plItem && ( plItem->i_children > -1 ) )
            flags |= Qt::ItemIsDropEnabled;
    }
    flags |= Qt::ItemIsDragEnabled;

    return flags;
}

QStringList PLModel::mimeTypes() const
{
    QStringList types;
    types << "vlc/qt-input-items";
    return types;
}

bool modelIndexLessThen( const QModelIndex &i1, const QModelIndex &i2 )
{
    if( !i1.isValid() || !i2.isValid() ) return false;
    PLItem *item1 = static_cast<PLItem*>( i1.internalPointer() );
    PLItem *item2 = static_cast<PLItem*>( i2.internalPointer() );
    if( item1->hasSameParent( item2 ) ) return i1.row() < i2.row();
    else return *item1 < *item2;
}

QMimeData *PLModel::mimeData( const QModelIndexList &indexes ) const
{
    PlMimeData *plMimeData = new PlMimeData();
    QModelIndexList list;

    foreach( const QModelIndex &index, indexes ) {
        if( index.isValid() && index.column() == 0 )
            list.append(index);
    }

    std::sort(list.begin(), list.end(), modelIndexLessThen);

    AbstractPLItem *item = NULL;
    foreach( const QModelIndex &index, list ) {
        if( item )
        {
            AbstractPLItem *testee = getItem( index );
            while( testee->parent() )
            {
                if( testee->parent() == item ||
                    testee->parent() == item->parent() ) break;
                testee = testee->parent();
            }
            if( testee->parent() == item ) continue;
            item = getItem( index );
        }
        else
            item = getItem( index );

        input_item_t *input = static_cast<PLItem*>(item)->inputItem();
        if( !isExplicitRandomAction( input ) )
            plMimeData->appendItem( input );
    }

    return plMimeData;
}

/* Drop operation */
bool PLModel::dropMimeData( const QMimeData *data, Qt::DropAction action,
        int row, int, const QModelIndex &parent )
{
    bool copy = action == Qt::CopyAction;
    if( !copy && action != Qt::MoveAction )
        return true;

    const PlMimeData *plMimeData = qobject_cast<const PlMimeData*>( data );
    if( plMimeData )
    {
        if( isInsideUserPlaylists( parent ) )
        {
            QVector<int> ids;
            bool sourcesInside = true;
            {
                vlc_playlist_locker pl_lock( THEPL );
                foreach( input_item_t *input, plMimeData->inputItems() )
                {
                    playlist_item_t *item = playlist_ItemGetByInput(
                        p_playlist, input );
                    if( !item ) continue;
                    ids.append( item->i_id );
                    bool inside = false;
                    for( playlist_item_t *cursor = item; cursor;
                         cursor = cursor->p_parent )
                        if( cursor->p_input
                         && input_item_IsPowerVLCUserPlaylistsRoot(
                                cursor->p_input ) )
                        { inside = true; break; }
                    sourcesInside &= inside;
                }
            }
            if( ids.isEmpty() ) return false;
            services_discovery_playlist_drop_t request = {
                itemId( parent ), row, (size_t)ids.size(), ids.constData(),
                !sourcesInside
            };
            return playlist_ServicesDiscoveryControl( THEPL,
                "powervlc_library", SD_CMD_POWERVLC_PLAYLIST_DROP,
                &request ) == VLC_SUCCESS;
        }
        if( copy )
            dropAppendCopy( plMimeData, getItem( parent ), row );
        else
            dropMove( plMimeData, getItem( parent ), row );
    }
    return true;
}

void PLModel::dropAppendCopy( const PlMimeData *plMimeData, PLItem *target, int pos )
{
    vlc_playlist_locker pl_lock ( THEPL );

    playlist_item_t *p_parent =
        playlist_ItemGetByInput( p_playlist, target->inputItem() );
    if( !p_parent ) return;

    if( pos == -1 ) pos = PLAYLIST_END;

    QList<input_item_t*> inputItems = plMimeData->inputItems();

    foreach( input_item_t* p_input, inputItems )
    {
        playlist_item_t *p_item = playlist_ItemGetByInput( p_playlist, p_input );
        if( !p_item ) continue;
        pos = playlist_NodeAddCopy( p_playlist, p_item, p_parent, pos );
    }
}

void PLModel::dropMove( const PlMimeData * plMimeData, PLItem *target, int row )
{
    QList<input_item_t*> inputItems = plMimeData->inputItems();
    QList<PLItem*> model_items;
    playlist_item_t **pp_items;
    pp_items = (playlist_item_t **)
               calloc( inputItems.count(), sizeof( playlist_item_t* ) );
    if ( !pp_items ) return;

    int model_pos;

    {
        vlc_playlist_locker pl_lock ( THEPL );

        playlist_item_t *p_parent =
            playlist_ItemGetByInput( p_playlist, target->inputItem() );

        if( !p_parent || row > p_parent->i_children )
        {
            free( pp_items );
            return;
        }

        int new_pos = model_pos = row == -1 ? p_parent->i_children : row;
        int i = 0;

        foreach( input_item_t *p_input, inputItems )
        {
            playlist_item_t *p_item = playlist_ItemGetByInput( p_playlist, p_input );
            if( !p_item ) continue;

            PLItem *item = findByInputLocked( rootItem, p_input );
            if( !item ) continue;

            /* Better not try to move a node into itself.
               Abort the whole operation in that case,
               because it is ambiguous. */
            AbstractPLItem *climber = target;
            while( climber )
            {
                if( climber == item )
                {
                    free( pp_items );
                    return;
                }
                climber = climber->parent();
            }

            if( item->parent() == target &&
                target->children.indexOf( item ) < new_pos )
                model_pos--;

            model_items.append( item );
            pp_items[i] = p_item;
            i++;
        }

        if( model_items.isEmpty() )
        {
            free( pp_items );
            return;
        }

        playlist_TreeMoveMany( p_playlist, i, pp_items, p_parent, new_pos );
    }

    foreach( PLItem *item, model_items )
        takeItem( item );

    insertChildren( target, model_items, model_pos );
    free( pp_items );
}

void PLModel::activateItem( const QModelIndex &index )
{
    assert( index.isValid() );
    const PLItem *item = getItem( index );
    assert( item );

    vlc_playlist_locker pl_lock( THEPL );

    playlist_item_t *p_item = playlist_ItemGetById( p_playlist, item->i_playlist_id );
    activateItem( p_item );
}

/* Convenient overloaded private version of activateItem
 * Must be entered with PL lock */
void PLModel::activateItem( playlist_item_t *p_item )
{
    if( !p_item ) return;
    /* A newer activation always supersedes a branch that is still being
     * materialised. It must never start playing later under the user's
     * explicitly selected track. */
    pendingNodePlaybackId = -1;
    pendingNodeBrowseId = -1;
    pendingNodePlaybackRetries = 0;
    if( p_item->p_input
     && isExplicitRandomAction( p_item->p_input ) )
    {
        pendingRandomPlaybackId = p_item->i_id;
        pendingRandomBranchId = -1;
        playlist_powervlc_random_result_t resolved;
        playlist_PowerVLCRandomResolve( p_playlist, p_item, -1, &resolved );
        pendingRandomBranchId = resolved.i_branch_id;
        if( resolved.p_browse )
            libvlc_MetadataRequest( p_intf->obj.libvlc,
                resolved.p_browse->p_input, META_REQUEST_OPTION_SCOPE_ANY,
                120000, resolved.p_browse );
        else if( resolved.p_track )
        {
            pendingRandomPlaybackId = -1;
            pendingRandomBranchId = -1;
            playlist_ViewPlay( p_playlist, resolved.p_scope,
                               resolved.p_track );
        }
        else
        {
            pendingRandomPlaybackId = -1;
            pendingRandomBranchId = -1;
        }
        if( pendingRandomPlaybackId >= 0 )
            QTimer::singleShot( 150, this,
                                SLOT(retryPendingRandomPlayback()) );
        return;
    }
    const bool indexedNode = isPowerVLCIndexItem( p_item->p_input );
    const bool browsableNode = p_item->p_input != NULL
        && (p_item->p_input->i_type == ITEM_TYPE_DIRECTORY || indexedNode);
    if( p_item->i_children >= 0 || browsableNode )
    {
        /* A compact media-library branch is loaded one level at a time.
         * Resolve the complete first album/track asynchronously instead of
         * mistaking an unmaterialised branch for a playable leaf. */
        pendingNodePlaybackId = p_item->i_id;
        pendingNodeBrowseId = -1;
        pendingNodePlaybackRetries = 0;
        QTimer::singleShot( 0, this, SLOT(retryPendingNodePlayback()) );
        return;
    }
    /* The immediate parent is the logical album/letter group. Using the
     * discovery root mixes in the duplicate leaves of private Random XSPFs. */
    playlist_item_t *scope = p_item->p_parent;
    if( !scope )
        scope = playlist_ItemGetById( p_playlist, rootItem->id() );
    if( scope ) playlist_ViewPlay( p_playlist, scope, p_item );
}

void PLModel::retryPendingNodePlayback()
{
    if( pendingNodePlaybackId < 0 )
        return;

    bool retry = false;
    {
        vlc_playlist_locker pl_lock( p_playlist );
        playlist_item_t *root = playlist_ItemGetById(
            p_playlist, pendingNodePlaybackId );
        if( root == NULL )
        {
            pendingNodePlaybackId = -1;
            pendingNodeBrowseId = -1;
            return;
        }

        playlist_item_t *cursor = root;
        playlist_item_t *album = NULL;
        while( cursor != NULL )
        {
            if( cursor->p_input != NULL
             && input_item_IsPowerVLCAlbumScope( cursor->p_input ) )
                album = cursor;

            playlist_item_t *next = NULL;
            if( cursor->i_children >= 0 )
            {
                for( int i = 0; i < cursor->i_children; ++i )
                {
                    playlist_item_t *candidate = cursor->pp_children[i];
                    if( candidate != NULL && candidate->p_input != NULL
                     && !isExplicitRandomAction( candidate->p_input ) )
                    {
                        next = candidate;
                        break;
                    }
                }
            }
            if( next != NULL )
            {
                cursor = next;
                continue;
            }

            const bool indexed = isPowerVLCIndexItem( cursor->p_input );
            const bool browsable = cursor->p_input != NULL
                && (cursor->p_input->i_type == ITEM_TYPE_DIRECTORY || indexed);
            if( browsable )
            {
                const qint64 now = QDateTime::currentMSecsSinceEpoch();
                if( pendingNodeBrowseId != cursor->i_id
                 && (!browseRequestedIds.contains( cursor->i_id )
                  || now - browseRequestedIds.value( cursor->i_id ) >= 150000) )
                {
                    pendingNodeBrowseId = cursor->i_id;
                    browseRequestedIds.insert( cursor->i_id, now );
                    libvlc_MetadataRequest( p_intf->obj.libvlc,
                        cursor->p_input, META_REQUEST_OPTION_SCOPE_ANY,
                        120000, cursor );
                }
                retry = true;
            }
            else if( cursor != root )
            {
                pendingNodePlaybackId = -1;
                pendingNodeBrowseId = -1;
                /* Library navigation must remain within the selected album,
                 * so Next stops at its final track. */
                playlist_ViewPlay( p_playlist, album ? album : root, cursor );
            }
            else
            {
                pendingNodePlaybackId = -1;
                pendingNodeBrowseId = -1;
            }
            break;
        }
    }
    if( retry && pendingNodePlaybackRetries++ < 800 )
        QTimer::singleShot( 150, this, SLOT(retryPendingNodePlayback()) );
    else if( retry )
    {
        pendingNodePlaybackId = -1;
        pendingNodeBrowseId = -1;
    }
}

/****************** Base model mandatory implementations *****************/
QVariant PLModel::data( const QModelIndex &index, const int role ) const
{
    if( !index.isValid() )
        return QVariant();

    switch( role )
    {

        case Qt::FontRole:
        {
            QFont font = customFont;
            if( isRandomAction( index ) ) font.setItalic( true );
            return font;
        }

        case Qt::DisplayRole:
        {
            PLItem *item = getItem( index );
            int metadata = columnToMeta( index.column() );
            if( metadata == COLUMN_END )
                return QVariant();

            QString returninfo;
            if( metadata == COLUMN_NUMBER )
            {
                returninfo = QString::number( index.row() + 1 );
            }
            else if( metadata == COLUMN_COVER )
            {
                QString artUrl;
                artUrl = InputManager::decodeArtURL( item->inputItem() );
                if( artUrl.isEmpty() )
                {
                    for( int i = 0; i < item->childCount(); i++ )
                    {
                        artUrl = InputManager::decodeArtURL( item->child( i )->inputItem() );
                        if( !artUrl.isEmpty() )
                            break;
                    }
                }
                return artUrl;
            }
            else
            {
                char *psz = metadata == COLUMN_TITLE
                    ? displayTrackTitle( item->inputItem() )
                    : psz_column_meta( item->inputItem(), metadata );
                returninfo = qfu( psz );
                free( psz );
            }

            return QVariant( returninfo );
        }

        case Qt::DecorationRole:
        {
            switch( columnToMeta(index.column()) )
            {
                case COLUMN_TITLE:
                {
                    PLItem *item = getItem( index );
                    /* Used to segfault here because i_type wasn't always initialized */
                    int idx = item->inputItem()->i_type;
                    if( item->inputItem()->b_net && item->inputItem()->i_type == ITEM_TYPE_FILE )
                        idx = ITEM_TYPE_STREAM;
                    return QVariant( icons[idx] );
                }
                case COLUMN_COVER:
                    /* !warn: changes tree item line height. Otherwise, override
                     * delegate's sizehint */
                    return getArtPixmap( index, QSize(16,16) );
                default:
                    break;
            }
            break;
        }

        case Qt::BackgroundRole:
            if( isCurrent( index ) )
                return QVariant( QBrush( Qt::gray ) );
            break;

        case CURRENT_ITEM_ROLE:
            return QVariant( isCurrent( index ) );

        case CURRENT_ITEM_CHILD_ROLE:
            return QVariant( isParent( index, currentIndex() ) );

        case LEAF_NODE_ROLE:
            return QVariant( isLeaf( index ) );

        case RATING_ROLE:
        {
            if( columnToMeta( index.column() ) != COLUMN_TITLE
             || !isLeaf( index ) || isRandomAction( index ) )
                return QVariant();
            char *value = input_item_GetRating( getInputItem( index ) );
            int rating = value ? (int)strtol( value, NULL, 10 ) : 0;
            free( value );
            return rating >= 1 && rating <= 5 ? QVariant( rating ) : QVariant();
        }

        default:
            break;
    }

    return QVariant();
}

void PLModel::collectRatings( const QModelIndex &index,
                              QMap<QString, int> &ratings ) const
{
    if( !index.isValid() || isRandomAction( index ) ) return;
    const int children = rowCount( index );
    if( children > 0 )
    {
        for( int row = 0; row < children; ++row )
            collectRatings( this->index( row, 0, index ), ratings );
        return;
    }
    input_item_t *input = getInputItem( index );
    if( input == NULL || input->i_type != ITEM_TYPE_FILE ) return;
    QByteArray uri = getURI( index ).toUtf8();
    char *path = vlc_uri2path( uri.constData() );
    if( path == NULL ) return;
    char *value = input_item_GetRating( input );
    int rating = value ? (int)strtol( value, NULL, 10 ) : 0;
    free( value );
    ratings.insert( qfu( path ), rating >= 0 && rating <= 5 ? rating : 0 );
    free( path );
}

QStringList PLModel::ratingPaths( const QModelIndexList &indexes,
                                  int *commonRating ) const
{
    QMap<QString, int> ratings;
    foreach( const QModelIndex &index, indexes )
        collectRatings( index.sibling( index.row(), 0 ), ratings );
    int common = -1;
    for( QMap<QString, int>::const_iterator it = ratings.constBegin();
         it != ratings.constEnd(); ++it )
    {
        if( common < 0 ) common = it.value();
        else if( common != it.value() ) { common = -2; break; }
    }
    if( commonRating ) *commonRating = common;
    return ratings.keys();
}

bool PLModel::setData( const QModelIndex &index, const QVariant & value, int role )
{
    switch( role )
    {
    case Qt::FontRole:
        customFont = value.value<QFont>();
        return true;
    default:
        return VLCModel::setData( index, value, role );
    }
}

/* Seek from current index toward the top and see if index is one of parent nodes */
bool PLModel::isParent( const QModelIndex &index, const QModelIndex &current ) const
{
    if( !index.isValid() )
        return false;

    if( index == current )
        return true;

    if( !current.isValid() || !current.parent().isValid() )
        return false;

    return isParent( index, current.parent() );
}

bool PLModel::isLeaf( const QModelIndex &index ) const
{
    bool b_isLeaf = false;

    vlc_playlist_locker pl_lock ( THEPL );

    playlist_item_t *plItem =
        playlist_ItemGetById( p_playlist, itemId( index ) );

    if( plItem )
        b_isLeaf = plItem->i_children == -1;

    return b_isLeaf;
}

PLItem* PLModel::getItem( const QModelIndex & index ) const
{
    PLItem *item = static_cast<PLItem *>( VLCModel::getItem( index ) );
    if ( item == NULL ) item = rootItem;
    return item;
}

QModelIndex PLModel::index( const int row, const int column, const QModelIndex &parent )
                  const
{
    PLItem *parentItem = parent.isValid() ? getItem( parent ) : rootItem;

    PLItem *childItem = static_cast<PLItem*>(parentItem->child( row ));
    if( childItem )
        return createIndex( row, column, childItem );
    else
        return QModelIndex();
}

QModelIndex PLModel::indexByPLID( const int i_plid, const int c ) const
{
    return index( findByPLId( rootItem, i_plid ), c );
}

QModelIndex PLModel::indexByInputItem( const input_item_t *item, const int c ) const
{
    return index( findByInput( rootItem, item ), c );
}

QModelIndex PLModel::rootIndex() const
{
    return index( findByPLId( rootItem, rootItem->id() ), 0 );
}

bool PLModel::isTree() const
{
    return ( ( rootItem && rootItem->id() != p_playlist->p_playing->i_id )
             || var_InheritBool( p_intf, "playlist-tree" ) );
}

/* Return the index of a given item */
QModelIndex PLModel::index( PLItem *item, int column ) const
{
    if( !item ) return QModelIndex();
    AbstractPLItem *parent = item->parent();
    if( parent )
        return createIndex( parent->lastIndexOf( item ),
                            column, item );
    return QModelIndex();
}

QModelIndex PLModel::currentIndex() const
{
    int currentId = -1;
    {
        vlc_playlist_locker pl_lock( THEPL );
        playlist_item_t *current = playlist_CurrentPlayingItem( THEPL );
        if( current ) currentId = current->i_id;
    }
    PLItem *item = findByPLId( rootItem, currentId );
    if( !item ) return QModelIndex();

    PLItem *random = static_cast<PLItem *>( item->parent() );
    while( random && !isExplicitRandomAction( random->p_input ) )
        random = static_cast<PLItem *>( random->parent() );
    if( random && random->parent() )
    {
        PLItem *scope = static_cast<PLItem *>( random->parent() );
        PLItem *visible = findVisibleRandomCounterpart( scope, item->getURI() );
        if( visible ) item = visible;
    }
    return index( item, 0 );
}

bool PLModel::isCurrent( const QModelIndex &candidate ) const
{
    if( !candidate.isValid() )
        return false;
    QModelIndex current = currentIndex();
    return current.isValid() && itemId( candidate ) == itemId( current );
}

PLItem *PLModel::findVisibleRandomCounterpart( PLItem *root,
                                               const QString &uri ) const
{
    foreach( AbstractPLItem *abstractChild, root->children )
    {
        PLItem *child = static_cast<PLItem *>( abstractChild );
        if( isExplicitRandomAction( child->p_input ) )
            continue;
        if( child->getURI() == uri )
            return child;
        PLItem *match = findVisibleRandomCounterpart( child, uri );
        if( match ) return match;
    }
    return NULL;
}

QModelIndex PLModel::parent( const QModelIndex &index ) const
{
    if( !index.isValid() ) return QModelIndex();

    PLItem *childItem = getItem( index );
    if( !childItem )
    {
        msg_Err( p_playlist, "Item not found" );
        return QModelIndex();
    }

    PLItem *parentItem = static_cast<PLItem*>(childItem->parent());
    if( !parentItem || parentItem == rootItem ) return QModelIndex();
    if( !parentItem->parent() )
    {
        msg_Err( p_playlist, "No parent found, trying row 0. Please report this" );
        return createIndex( 0, 0, parentItem );
    }
    return createIndex(parentItem->row(), 0, parentItem);
}

int PLModel::rowCount( const QModelIndex &parent ) const
{
    if( parent.isValid()
     && isExplicitRandomAction( getInputItem( parent ) ) )
        return 0;
    PLItem *parentItem = parent.isValid() ? getItem( parent ) : rootItem;
    return parentItem->childCount();
}

bool PLModel::hasChildren( const QModelIndex &parent ) const
{
    if( rowCount( parent ) > 0 )
        return true;
    if( !parent.isValid() )
        return false;
    if( !latestSearch.isEmpty()
     && latestSearchScopeIds.contains( itemId( parent ) ) )
        return true;

    /* unbrowsed directories (file browser folders, radio directory
     * countries...) get their expand decoration right away: expanding
     * them triggers the browse (see ensureBrowsed()) */
    input_item_t *p_input = getInputItem( parent );
    if( isExplicitRandomAction( p_input ) )
        return false;
    bool indexed = isPowerVLCIndexItem( p_input );
    return p_input != NULL && (p_input->i_type == ITEM_TYPE_DIRECTORY
                            || indexed);
}

bool PLModel::isRandomAction( const QModelIndex &index ) const
{
    return index.isValid()
        && isExplicitRandomAction( getInputItem( index ) );
}

void PLModel::ensureBrowsed( const QModelIndex &index )
{
    if( !index.isValid() || rowCount( index ) > 0 )
        return;

    input_item_t *p_input = getInputItem( index );
    bool indexed = isPowerVLCIndexItem( p_input );
    if( p_input == NULL || (p_input->i_type != ITEM_TYPE_DIRECTORY
                         && !indexed) )
        return;

    /* a directory still childless once its request is surely over
     * (failed fetch) can be retried by folding and unfolding it again */
    int i_id = itemId( index );
    qint64 now = QDateTime::currentMSecsSinceEpoch();
    if( browseRequestedIds.contains( i_id )
     && now - browseRequestedIds.value( i_id ) < 150000 )
        return;

    /* expanding an unbrowsed directory sends it to the preparser: its
     * sub-items reach the model through the regular playlist callbacks.
     * The network scope is required for on-line directories (radio
     * directory countries...), else the preparser silently skips them;
     * the explicit timeout replaces the 5-second preparse default, far
     * too short for the biggest countries of an on-line radio directory. */
    playlist_Lock( p_playlist );
    playlist_item_t *p_item = playlist_ItemGetById( p_playlist, i_id );
    /* i_children on the core item: the view may just be filtering
     * everything out, which is no reason to fetch again */
    if( p_item != NULL && p_item->p_input != NULL && p_item->i_children <= 0 )
    {
        browseRequestedIds.insert( i_id, now );
        libvlc_MetadataRequest( p_intf->obj.libvlc, p_item->p_input,
                                META_REQUEST_OPTION_SCOPE_ANY, 120000, p_item );
    }
    playlist_Unlock( p_playlist );
}

void PLModel::releaseBrowsed( const QModelIndex &index )
{
    if( !index.isValid() )
        return;
    int id = itemId( index );
    browseRequestedIds.remove( id );
    playlist_Lock( p_playlist );
    playlist_item_t *item = playlist_ItemGetById( p_playlist, id );
    char *uri = item && item->p_input ? input_item_GetURI( item->p_input )
                                     : NULL;
    bool indexed = uri && strstr( uri, "/powervlc-media-index/music-" );
    free( uri );
    if( indexed )
    {
        libvlc_MetadataCancel( p_intf->obj.libvlc, item );
        playlist_NodeEmpty( p_playlist, item );
    }
    playlist_Unlock( p_playlist );
}

/************************* Lookups *****************************/
PLItem *PLModel::findByPLId( PLItem *root, int i_id ) const
{
    if( !root ) return NULL;

    if( root->id() == i_id )
        return root;

    /* traverse the tree (in depth first) iteratively to avoid stack overflow */

    struct RemainingChildren {
        QList<AbstractPLItem *>::const_iterator next;
        QList<AbstractPLItem *>::const_iterator end;
    };

    QStack<RemainingChildren> stack;
    if( root->childCount() )
        stack.push( {root->children.cbegin(), root->children.cend()} );

    while ( !stack.isEmpty() )
    {
        RemainingChildren &remainingChildren = stack.top();

        PLItem *item = static_cast<PLItem *>( *remainingChildren.next );
        if( item->id() == i_id )
            return item;

        if( ++remainingChildren.next == remainingChildren.end )
            /* there are no more children at this depth level */
            stack.pop();

        if( item->childCount() )
            stack.push( {item->children.cbegin(), item->children.cend()} );
    }
    return NULL;
}

PLItem *PLModel::findByInput( PLItem *root, const input_item_t *input ) const
{
    int i_id;
    {
        playlist_item_t *item;

        vlc_playlist_locker pl_lock ( THEPL );
        item = playlist_ItemGetByInput( THEPL, input );
        if( item == NULL )
            return NULL;
        i_id = item->i_id;
    }
    return findByPLId( root, i_id );
}

PLItem *PLModel::findByInputLocked( PLItem *root, const input_item_t *input ) const
{
    PL_ASSERT_LOCKED;

    playlist_item_t* item = playlist_ItemGetByInput( THEPL, input );
    if( item == NULL )
        return NULL;
    return findByPLId( root, item->i_id );
}

PLModel::pl_nodetype PLModel::getPLRootType() const
{
    vlc_playlist_locker pl_lock ( THEPL );

    /* can't rely on rootitem as it depends on view / rebuild() */
    AbstractPLItem *plitem = rootItem;
    while( plitem->parent() )plitem = plitem->parent();

    if( plitem->id() == p_playlist->p_playing->i_id )
        return ROOTTYPE_CURRENT_PLAYING;

    if( p_playlist->p_media_library &&
        plitem->id() == p_playlist->p_media_library->i_id )
        return ROOTTYPE_MEDIA_LIBRARY;

    return ROOTTYPE_OTHER;
}

bool PLModel::canEdit() const
{
    return ( getPLRootType() != ROOTTYPE_OTHER );
}

/************************* Updates handling *****************************/

/**** Events processing ****/
void PLModel::processInputItemUpdate( )
{
    input_thread_t *p_input = THEMIM->getInput();
    if( !p_input ) return;

    /* Prefer the exact playlist item chosen by playlist_ViewPlay().  The
     * same input exists in several media-library categories, so a lookup by
     * input alone can highlight an unrelated occurrence. */
    QModelIndex current = currentIndex();
    if( current.isValid() )
        emit currentIndexChanged( current );
    else
    {
        PLItem *item = findByInput( rootItem, input_GetItem( p_input ) );
        if( item ) emit currentIndexChanged( index( item, 0 ) );
    }

    processInputItemUpdate( input_GetItem( p_input ) );
}

void PLModel::processInputItemUpdate( input_item_t *p_item )
{
    if( !p_item ) return;
    updateTreeItemsForInput( rootItem, p_item );
}

void PLModel::processItemRemoval( int i_pl_itemid )
{
    if( i_pl_itemid <= 0 ) return;
    removeItem( findByPLId( rootItem, i_pl_itemid ) );
}

void PLModel::processItemAppend( int i_pl_itemid, int i_pl_itemidparent )
{
    playlist_item_t *p_item = NULL;
    PLItem *newItem = NULL;
    int pos;

    /* Find the Parent */
    PLItem *nodeParentItem = findByPLId( rootItem, i_pl_itemidparent );
    if( !nodeParentItem ) return;

    /* Search for an already matching children */
    foreach( AbstractPLItem *existing, nodeParentItem->children )
        if( existing->id() == i_pl_itemid ) return;

    /* Find the child */
    {
        vlc_playlist_locker pl_lock ( THEPL );

        p_item = playlist_ItemGetById( p_playlist, i_pl_itemid );
        if( !p_item || p_item->i_flags & PLAYLIST_DBL_FLAG )
            return;

        for( pos = p_item->p_parent->i_children - 1; pos >= 0; pos-- )
            if( p_item->p_parent->pp_children[pos] == p_item ) break;

        newItem = new PLItem( p_item, nodeParentItem );
    }

    /* We insert the newItem (children) inside the parent */
    beginInsertRows( index( nodeParentItem, 0 ), pos, pos );
    nodeParentItem->insertChild( newItem, pos );
    endInsertRows();
    if ( newItem->inputItem() == THEMIM->currentInputItem() )
        emit currentIndexChanged( index( newItem, 0 ) );

    if( pendingRandomPlaybackId >= 0 )
        QTimer::singleShot( 150, this, SLOT(retryPendingRandomPlayback()) );

    if( latestSearch.isEmpty() ) return;
    filter( latestSearch, index( rootItem, 0), false /*FIXME*/ );
}

void PLModel::retryPendingRandomPlayback()
{
    if( pendingRandomPlaybackId < 0 ) return;
    bool retry = false;
    {
        vlc_playlist_locker pl_lock( THEPL );
        playlist_item_t *action = playlist_ItemGetById(
            p_playlist, pendingRandomPlaybackId );
        playlist_powervlc_random_result_t resolved;
        int previousBranch = pendingRandomBranchId;
        playlist_PowerVLCRandomResolve( p_playlist, action,
                                       pendingRandomBranchId, &resolved );
        pendingRandomBranchId = resolved.i_branch_id;
        if( resolved.p_track )
        {
            pendingRandomPlaybackId = -1;
            pendingRandomBranchId = -1;
            playlist_ViewPlay( p_playlist, resolved.p_scope,
                               resolved.p_track );
        }
        else if( resolved.p_browse )
        {
            if( previousBranch != resolved.i_branch_id )
                libvlc_MetadataRequest( p_intf->obj.libvlc,
                    resolved.p_browse->p_input, META_REQUEST_OPTION_SCOPE_ANY,
                    120000, resolved.p_browse );
            retry = true;
        }
        else
        {
            pendingRandomPlaybackId = -1;
            pendingRandomBranchId = -1;
        }
    }
    if( retry )
        QTimer::singleShot( 150, this,
                            SLOT(retryPendingRandomPlayback()) );
}

void PLModel::rebuild( playlist_item_t *p_root )
{
    beginResetModel();

    {
        vlc_playlist_locker pl_lock ( THEPL );

        if( rootItem ) rootItem->clearChildren();
        if( p_root ) // Can be NULL
        {
            if ( rootItem ) delete rootItem;
            rootItem = new PLItem( p_root );
        }
        assert( rootItem );
        /* Recreate from root */
        updateChildren( rootItem );
    }

    /* And signal the view */
    endResetModel();
    if( p_root ) emit rootIndexChanged();
}

void PLModel::takeItem( PLItem *item )
{
    assert( item );
    PLItem *parent = static_cast<PLItem*>(item->parent());
    assert( parent );
    int i_index = parent->indexOf( item );

    beginRemoveRows( index( parent, 0 ), i_index, i_index );
    parent->takeChildAt( i_index );
    endRemoveRows();
}

void PLModel::insertChildren( PLItem *node, QList<PLItem*>& items, int i_pos )
{
    assert( node );
    int count = items.count();
    if( !count ) return;
    beginInsertRows( index( node, 0 ), i_pos, i_pos + count - 1 );
    for( int i = 0; i < count; i++ )
    {
        node->children.insert( i_pos + i, items[i] );
        items[i]->parentItem = node;
    }
    endInsertRows();
}

void PLModel::removeItem( PLItem *item )
{
    if( !item ) return;

    if( item->parent() ) {
        int i = item->parent()->indexOf( item );
        beginRemoveRows( index( static_cast<PLItem*>(item->parent()), 0), i, i );
        item->parent()->children.removeAt(i);
        delete item;
        endRemoveRows();
    }
    else delete item;

    if(item == rootItem)
    {
        rootItem = NULL;
        rebuild( p_playlist->p_playing );
    }
}

/* This function must be entered WITH the playlist lock */
void PLModel::updateChildren( PLItem *root )
{
    playlist_item_t *p_node = playlist_ItemGetById( p_playlist, root->id() );
    updateChildren( p_node, root );
}

/* This function must be entered WITH the playlist lock */
void PLModel::updateChildren( playlist_item_t *p_node, PLItem *root )
{
    for( int i = 0; i < p_node->i_children ; i++ )
    {
        if( p_node->pp_children[i]->i_flags & PLAYLIST_DBL_FLAG ) continue;
        PLItem *newItem =  new PLItem( p_node->pp_children[i], root );
        root->appendChild( newItem );
        if( p_node->pp_children[i]->i_children != -1 )
            updateChildren( p_node->pp_children[i], newItem );
    }
}

/* Function doesn't need playlist-lock, as we don't touch playlist_item_t stuff here*/
void PLModel::updateTreeItem( PLItem *item )
{
    if( !item ) return;
    emit dataChanged( index( item, 0 ) , index( item, columnCount( QModelIndex() ) - 1 ) );
}

void PLModel::updateTreeItemsForInput( PLItem *root, input_item_t *input )
{
    if( root == NULL || input == NULL ) return;
    input_item_t *candidate = root->inputItem();
    bool same = candidate == input;
    if( !same )
    {
        char *candidateUri = candidate ? input_item_GetURI( candidate ) : NULL;
        char *inputUri = input_item_GetURI( input );
        same = candidateUri && inputUri && !strcmp( candidateUri, inputUri );
        free( candidateUri ); free( inputUri );
    }
    if( same ) updateTreeItem( root );
    for( int i = 0; i < root->childCount(); ++i )
        updateTreeItemsForInput( static_cast<PLItem *>( root->child( i ) ),
                                 input );
}

/************************* Actions ******************************/

/**
 * Deletion, don't delete items childrens if item is going to be
 * delete allready, so we remove childrens from selection-list.
 */
void PLModel::doDelete( QModelIndexList selected )
{
    bool userPlaylistSelection = false;
    foreach( const QModelIndex &index, selected )
        if( index.column() == 0 && isInsideUserPlaylists( index )
         && !isUserPlaylistsRoot( index ) )
        {
            userPlaylistSelection = true;
            break;
        }
    if( userPlaylistSelection )
    {
        foreach( const QModelIndex &index, selected )
        {
            if( index.column() != 0 || !isInsideUserPlaylists( index )
             || isUserPlaylistsRoot( index ) )
                continue;
            services_discovery_playlist_item_t request = { itemId( index ) };
            playlist_ServicesDiscoveryControl( THEPL, "powervlc_library",
                SD_CMD_POWERVLC_PLAYLIST_DELETE, &request );
        }
        return;
    }
    if( !canEdit() ) return;

    while( !selected.isEmpty() )
    {
        QModelIndex index = selected[0];
        selected.removeAt( 0 );

        if( index.column() != 0 ) continue;

        PLItem *item = getItem( index );
        if( item->childCount() )
            recurseDelete( item->children, &selected );

        PL_LOCK;
        playlist_item_t *p_root = playlist_ItemGetById( p_playlist,
                                                        item->id() );
        if( p_root != NULL )
            playlist_NodeDelete( p_playlist, p_root );
        PL_UNLOCK;

        if( p_root != NULL )
            removeItem( item );
    }
}

void PLModel::recurseDelete( QList<AbstractPLItem*> children, QModelIndexList *fullList )
{
    for( int i = children.count() - 1; i >= 0 ; i-- )
    {
        PLItem *item = static_cast<PLItem *>(children[i]);
        if( item->childCount() )
            recurseDelete( item->children, fullList );
        fullList->removeAll( index( item, 0 ) );
    }
}

/******* Volume III: Sorting and searching ********/
void PLModel::shuffle()
{
    msg_Dbg( p_intf, "Shuffling playlist items");

    sortInternal( indexByPLID( rootItem->id(), 0 ),
                  SORT_RANDOM, ORDER_NORMAL );
}

void PLModel::sort( const int column, Qt::SortOrder order )
{
    sort( QModelIndex(), indexByPLID( rootItem->id(), 0 ) , column, order );
}

void PLModel::sort( QModelIndex caller, QModelIndex rootIndex, const int column, Qt::SortOrder order )
{
    msg_Dbg( p_intf, "Sorting by column %i, order %i", column, order );

    int meta = columnToMeta( column );
    if( meta == COLUMN_END || meta == COLUMN_COVER ) return;

    input_item_t* p_caller_item = caller.isValid()
        ? static_cast<AbstractPLItem*>( caller.internalPointer() )->inputItem()
        : NULL;

    sortInternal( rootIndex, i_column_sorting( meta ),
                  order == Qt::AscendingOrder ?
                      ORDER_NORMAL : ORDER_REVERSE );

    /* if we have popup item, try to make sure that you keep that item visible */
    if( p_caller_item )
    {
        QModelIndex idx = indexByInputItem( p_caller_item, 0 );

        emit currentIndexChanged( idx );
    }
    else if( currentIndex().isValid() )
        emit currentIndexChanged( currentIndex() );
}

void PLModel::sortInternal( QModelIndex rootIndex, int mode, int type )
{
    PLItem *item = ( rootIndex.isValid() ) ? getItem( rootIndex )
                                           : rootItem;
    if( !item ) return;

    int i_root_id = item->id();

    QModelIndex qIndex = index( item, 0 );
    int count = item->childCount();
    if( count )
    {
        beginRemoveRows( qIndex, 0, count - 1 );
        item->clearChildren();
        endRemoveRows( );
    }

    {
        vlc_playlist_locker pl_lock ( THEPL );

        playlist_item_t *p_root = playlist_ItemGetById( p_playlist,
                                                        i_root_id );
        if( p_root )
        {
            playlist_RecursiveNodeSort( p_playlist, p_root, mode, type );
        }

        if( count )
        {
            beginInsertRows( qIndex, 0, count - 1 );
            updateChildren( item );
            endInsertRows( );
        }
    }
}

void PLModel::filter( const QString& search_text, const QModelIndex & idx, bool b_recursive )
{
    const QString normalizedSearch = search_text.trimmed();
    latestSearch = normalizedSearch;

    /** \todo Fire the search with a small delay ? */
    {
        vlc_playlist_locker pl_lock ( THEPL );

        playlist_item_t *p_root = playlist_ItemGetById( p_playlist,
                                                        itemId( idx ) );
        assert( p_root );
        playlist_LiveSearchUpdate( p_playlist, p_root, qtu( normalizedSearch ),
                                   b_recursive );
        if( idx.isValid() )
        {
            PLItem *searchRoot = getItem( idx );

            beginRemoveRows( idx, 0, searchRoot->childCount() - 1 );
            searchRoot->clearChildren();
            endRemoveRows();

            beginInsertRows( idx, 0, searchRoot->childCount() - 1 );
            updateChildren( searchRoot ); // The PL_LOCK is needed here
            endInsertRows();

            return;
        }
    }

    rebuild();
}

bool PLModel::isPowerVLCLibraryRoot() const
{
    char *name = rootItem && rootItem->p_input
               ? input_item_GetName( rootItem->p_input ) : NULL;
    QString rootName = name ? qfu( name ) : QString();
    bool result = rootName == QStringLiteral( "PowerVLC Media Library" )
               || rootName == qtr( "PowerVLC Media Library" );
    free( name );
    return result;
}

bool PLModel::isUserPlaylistsRoot( const QModelIndex &index ) const
{
    if( !index.isValid() ) return false;
    PLItem *item = getItem( index );
    return item && input_item_IsPowerVLCUserPlaylistsRoot( item->inputItem() );
}

bool PLModel::isUserPlaylistFolder( const QModelIndex &index ) const
{
    if( !index.isValid() ) return false;
    PLItem *item = getItem( index );
    return item && input_item_IsPowerVLCPlaylistFolder( item->inputItem() );
}

bool PLModel::isUserPlaylist( const QModelIndex &index ) const
{
    if( !index.isValid() ) return false;
    PLItem *item = getItem( index );
    return item && input_item_IsPowerVLCUserPlaylist( item->inputItem() );
}

bool PLModel::isPowerVLCDeviceStructure( const QModelIndex &index ) const
{
    if( !index.isValid() ) return false;
    PLItem *item = getItem( index );
    return item && input_item_IsPowerVLCDeviceStructure( item->inputItem() );
}

bool PLModel::isInsideUserPlaylists( const QModelIndex &index ) const
{
    if( !index.isValid() ) return false;
    for( AbstractPLItem *cursor = getItem( index ); cursor;
         cursor = cursor->parent() )
    {
        PLItem *item = static_cast<PLItem *>( cursor );
        if( input_item_IsPowerVLCUserPlaylistsRoot( item->inputItem() ) )
            return true;
    }
    return false;
}

void PLModel::createUserPlaylist( const QModelIndex &parent,
                                  const QString &name, bool folder )
{
    if( name.trimmed().isEmpty() || !parent.isValid() ) return;
    const QByteArray utf8Name = name.trimmed().toUtf8();
    services_discovery_playlist_create_t request = {
        itemId( parent ), utf8Name.constData(), folder
    };
    playlist_ServicesDiscoveryControl( THEPL, "powervlc_library",
        SD_CMD_POWERVLC_PLAYLIST_CREATE, &request );
}

void PLModel::renameUserPlaylist( const QModelIndex &index,
                                  const QString &name )
{
    if( name.trimmed().isEmpty() || !index.isValid() ) return;
    const QByteArray utf8Name = name.trimmed().toUtf8();
    services_discovery_playlist_rename_t request = {
        itemId( index ), utf8Name.constData()
    };
    playlist_ServicesDiscoveryControl( THEPL, "powervlc_library",
        SD_CMD_POWERVLC_PLAYLIST_RENAME, &request );
}

void PLModel::filterScopes( const QString &searchText,
                            const QSet<int> &scopeIds )
{
    const QString normalizedSearch = searchText.trimmed();
    latestSearch = normalizedSearch;
    latestSearchScopeIds = normalizedSearch.isEmpty() ? QSet<int>() : scopeIds;
    {
        vlc_playlist_locker pl_lock( THEPL );
        playlist_item_t *root = playlist_ItemGetById( p_playlist,
                                                       rootItem->i_playlist_id );
        if( root == NULL )
            return;
        playlist_LiveSearchUpdate( p_playlist, root, "", true );
        if( !normalizedSearch.isEmpty() )
            for( int id : scopeIds )
            {
                playlist_item_t *scope = playlist_ItemGetById( p_playlist, id );
                if( scope != NULL )
                    playlist_LiveSearchUpdate( p_playlist, scope,
                                               qtu( normalizedSearch ), true );
            }
    }
    rebuild();
}

bool PLModel::areSearchScopesLoaded( const QSet<int> &scopeIds ) const
{
    vlc_playlist_locker pl_lock( THEPL );
    for( int id : scopeIds )
    {
        playlist_item_t *scope = playlist_ItemGetById( p_playlist, id );
        if( !isSearchSubtreeLoaded( scope ) )
            return false;
    }
    return true;
}

QSet<int> PLModel::protectedSearchItemIds() const
{
    QSet<int> ids;
    vlc_playlist_locker pl_lock( THEPL );
    playlist_item_t *current = playlist_CurrentPlayingItem( p_playlist );
    playlist_item_t *album = NULL;
    for( playlist_item_t *item = current; item != NULL; item = item->p_parent )
    {
        ids.insert( item->i_id );
        if( album == NULL && item->p_input != NULL
         && input_item_IsPowerVLCAlbumScope( item->p_input ) )
            album = item;
    }
    if( album != NULL )
        collectPlaylistItemIds( album, ids );
    return ids;
}

void PLModel::removeAll()
{
    if( rowCount() < 1 ) return;

    QModelIndexList l;
    for( int i = 0; i < rowCount(); i++)
    {
        QModelIndex indexrecord = index( i, 0, QModelIndex() );
        l.append( indexrecord );
    }
    doDelete(l);
}

void PLModel::createNode( QModelIndex index, QString name )
{
    if( name.isEmpty() )
        return;

    vlc_playlist_locker pl_lock ( THEPL );

    index = index.parent();
    if ( !index.isValid() ) index = rootIndex();
    playlist_item_t *p_item = playlist_ItemGetById( p_playlist, itemId( index ) );
    if( p_item )
        playlist_NodeCreate( p_playlist, qtu( name ), p_item, PLAYLIST_END, 0 );
}

void PLModel::renameNode( QModelIndex index, QString name )
{
    if( name.isEmpty() || !index.isValid() ) return;

    vlc_playlist_locker pl_lock ( THEPL );

    if ( !index.isValid() ) index = rootIndex();
    input_item_t* p_input = this->getInputItem( index );
    input_item_SetName( p_input, qtu( name ) );
    playlist_t *p_playlist = THEPL;
    input_item_WriteMeta( VLC_OBJECT(p_playlist), p_input );
}

bool PLModel::action( QAction *action, const QModelIndexList &indexes )
{
    QModelIndex index;
    actionsContainerType a = action->data().value<actionsContainerType>();

    switch ( a.action )
    {

    case ACTION_PLAY:
        if ( !indexes.empty() && indexes.first().isValid() )
        {
            if( isCurrent( indexes.first() ) )
                playlist_Resume(THEPL);
            else
                activateItem( indexes.first() );
            return true;
        }
        break;

    case ACTION_PAUSE:
        if ( !indexes.empty() && indexes.first().isValid() )
        {
            playlist_Pause(THEPL);
            return true;
        }
        break;

    case ACTION_ADDTOPLAYLIST:
    {
        vlc_playlist_locker pl_lock ( THEPL );

        foreach( const QModelIndex &currentIndex, indexes )
        {
            playlist_item_t *p_item = playlist_ItemGetById( THEPL, itemId( currentIndex ) );
            if( !p_item ) continue;

            playlist_NodeAddCopy( THEPL, p_item,
                                  THEPL->p_playing,
                                  PLAYLIST_END );
        }
        return true;
    }

    case ACTION_REMOVE:
        doDelete( indexes );
        return true;

    case ACTION_SHUFFLE:
        shuffle();
        return true;

    case ACTION_SORT:
        if ( !indexes.empty() )
            index = indexes.first();

        sort( index, rootIndex(),
              a.column > 0 ? a.column - 1 : -a.column - 1,
              a.column > 0 ? Qt::AscendingOrder : Qt::DescendingOrder );
        return true;

    case ACTION_CLEAR:
        removeAll();
        return true;

    case ACTION_ENQUEUEFILE:
        foreach( const QString &uri, a.uris )
            Open::openMRL( p_intf, uri.toLatin1().constData(),
                           false, getPLRootType() == ROOTTYPE_CURRENT_PLAYING );
        return true;

    case ACTION_ENQUEUEDIR:
        if( a.uris.isEmpty() ) break;

        Open::openMRL( p_intf, a.uris.first().toLatin1().constData(),
                       false, getPLRootType() == ROOTTYPE_CURRENT_PLAYING );

        return true;

    case ACTION_ENQUEUEGENERIC:
        foreach( const QString &uri, a.uris )
        {
            QStringList options = a.options.split( " :" );
            Open::openMRLwithOptions( p_intf, uri, &options, false );
        }
        return true;

    default:
        break;
    }
    return false;
}

bool PLModel::isSupportedAction( actions action, const QModelIndex &index ) const
{
    AbstractPLItem const* item = VLCModel::getItem( index );

    switch ( action )
    {
    case ACTION_ADDTOPLAYLIST:
        /* Only if we are not already in Current Playing */
        return getPLRootType() != ROOTTYPE_CURRENT_PLAYING;
    case ACTION_SORT:
    case ACTION_SHUFFLE:
        return rowCount();
    case ACTION_PLAY:
    {
        if( !item )
            return false;

        {
            vlc_playlist_locker pl_lock ( THEPL );

            if( playlist_Status( THEPL ) != PLAYLIST_RUNNING )
                return true;
        }

        return !isCurrent( index );
    }
    case ACTION_PAUSE:
    {
        if( !isCurrent( index ) )
            return false;

        vlc_playlist_locker pl_lock ( THEPL );

        return playlist_Status( THEPL ) == PLAYLIST_RUNNING;
    }
    case ACTION_STREAM:
    case ACTION_SAVE:
    case ACTION_INFO:
        return item;
    case ACTION_REMOVE:
        return item && !isPowerVLCDeviceStructure( index )
                    && ( !item->readOnly()
                      || ( isInsideUserPlaylists( index )
                        && !isUserPlaylistsRoot( index ) ) );
    case ACTION_EXPLORE:
    {
        if( !item )
            return false;

        char*  psz_path = vlc_uri2path( qtu( item->getURI() ) );
        free(  psz_path );
        return psz_path != NULL;
    }
    case ACTION_CREATENODE:
            return canEdit() && isTree() && ( !item || !item->readOnly() );
    case ACTION_RENAMENODE:
            return item && !isLeaf( index ) && !item->readOnly();
    case ACTION_CLEAR:
            return canEdit() && rowCount();
    case ACTION_ENQUEUEFILE:
    case ACTION_ENQUEUEDIR:
    case ACTION_ENQUEUEGENERIC:
        return canEdit();
    case ACTION_SAVETOPLAYLIST:
        return getPLRootType() == ROOTTYPE_CURRENT_PLAYING && rowCount();
    default:
        return false;
    }
    return false;
}

/******************* Drag and Drop helper class ******************/
PlMimeData::~PlMimeData()
{
    foreach( input_item_t *p_item, _inputItems )
        input_item_Release( p_item );
}

void PlMimeData::appendItem( input_item_t *p_item )
{
    input_item_Hold( p_item );
    _inputItems.append( p_item );
}

QList<input_item_t*> PlMimeData::inputItems() const
{
    return _inputItems;
}

QStringList PlMimeData::formats () const
{
    QStringList fmts;
    fmts << "vlc/qt-input-items";
    return fmts;
}
