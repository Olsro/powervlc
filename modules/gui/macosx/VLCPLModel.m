/*****************************************************************************
 * VLCPLItem.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2014 VLC authors and VideoLAN
 * $Id$
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

#import "VLCPLModel.h"

#import "misc.h"    /* VLCByteCountFormatter */

#import "VLCPlaylist.h"
#import "VLCStringUtility.h"
#import "VLCMain.h"
#import "VLCMainWindowControlsBar.h"
#import "VLCMainMenu.h"
#import "VLCPlaylistInfo.h"
#import "VLCMainWindow.h"
#import "VLCSidebarDataSource.h"

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif
#include <assert.h>
#include <ctype.h>
#include <string.h>

#include <vlc_playlist.h>
#include <vlc_input_item.h>
#include <vlc_input.h>
#include <vlc_url.h>
#include <vlc_services_discovery.h>

static BOOL VLCPLItemIsUserPlaylistRoot(VLCPLItem *item)
{
    return item && input_item_IsPowerVLCUserPlaylistsRoot([item input]);
}

static BOOL VLCPLItemIsUserPlaylistFolder(VLCPLItem *item)
{
    return item && input_item_IsPowerVLCPlaylistFolder([item input]);
}

static BOOL VLCPLItemIsUserPlaylist(VLCPLItem *item)
{
    return item && input_item_IsPowerVLCUserPlaylist([item input]);
}

static BOOL VLCPLItemIsInsideUserPlaylists(VLCPLItem *item)
{
    for (VLCPLItem *cursor = item; cursor; cursor = [cursor parent])
        if (VLCPLItemIsUserPlaylistRoot(cursor))
            return YES;
    return NO;
}

/* Keep the library's disc/track prefix stable when the input replaces the
 * XSPF title with freshly parsed metadata after playback starts. */
static char *VLCPLDisplayTitle(input_item_t *input)
{
    char *title = input_item_GetTitleFbName(input);
    if (!title)
        return NULL;

    char *discText = input_item_GetDiscNumber(input);
    char *trackText = input_item_GetTrackNumber(input);
    unsigned long disc = discText ? strtoul(discText, NULL, 10) : 0;
    unsigned long track = trackText ? strtoul(trackText, NULL, 10) : 0;
    free(discText);
    free(trackText);
    if (!track)
        return title;

    char prefix[64];
    if (disc)
        snprintf(prefix, sizeof(prefix), "%lu.%lu. ", disc, track);
    else
        snprintf(prefix, sizeof(prefix), "%lu. ", track);
    if (!strncmp(title, prefix, strlen(prefix)))
        return title;

    /* Before playback, XSPF already supplies "disc.track. title", while
     * only its track number is exposed as metadata. Do not prefix it twice. */
    if (!disc && isdigit((unsigned char)title[0])) {
        char *endDisc;
        strtoul(title, &endDisc, 10);
        if (*endDisc == '.' && isdigit((unsigned char)endDisc[1])) {
            char *endTrack;
            unsigned long embeddedTrack = strtoul(endDisc + 1, &endTrack, 10);
            if (embeddedTrack == track && !strncmp(endTrack, ". ", 2))
                return title;
        }
    }

    char *formatted = NULL;
    if (asprintf(&formatted, "%s%s", prefix, title) < 0)
        formatted = NULL;
    free(title);
    return formatted;
}

static BOOL VLCPLItemIsPowerVLCRandomAction(VLCPLItem *item)
{
    if (!item)
        return NO;
    if (!input_item_IsPowerVLCRandomAction([item input]))
        return NO;
    for (VLCPLItem *ancestor = item; ancestor; ancestor = [ancestor parent]) {
        if (input_item_IsPowerVLCLazyIndex([ancestor input]))
            return YES;
    }
    return NO;
}

static BOOL VLCPLInputIsPowerVLCIndex(input_item_t *input)
{
    return input && input_item_IsPowerVLCLazyIndex(input);
}

static NSArray *VLCFilePathsFromPasteboard(NSPasteboard *pasteboard)
{
    NSMutableArray *paths = [NSMutableArray array];
    NSArray *legacy = [pasteboard propertyListForType:NSFilenamesPboardType];
    if ([legacy isKindOfClass:[NSArray class]])
        [paths addObjectsFromArray:legacy];
    NSArray *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in urls)
        if ([url isFileURL] && ![paths containsObject:[url path]])
            [paths addObject:[url path]];
    return paths;
}

@interface VLCPLModel ()
{
    playlist_t *p_playlist;
    __weak NSOutlineView *_outlineView;

    NSUInteger _retainedRowSelection;

    /* active search string, so items appended while the filter is on
     * (e.g. a radio directory still loading) get filtered too */
    NSString *_latestSearchString;
    NSSet *_latestSearchScopeItemIds;

    /* playlist root id -> ids of the expanded rows in that source. The
     * wrappers are rebuilt whenever the sidebar selection changes, so the
     * outline view cannot preserve this state on its own. */
    NSMutableDictionary *_expandedItemIdsByRootId;
    BOOL _stateRestorePending;
    NSSet *_pendingSelectedItemIds;
    NSUInteger _bulkTreeUpdateDepth;
}

- (void)VLCPLItemAppended:(NSArray *)valueArray;
- (void)VLCPLItemRemoved:(NSNumber *)value;
- (void)VLCPLItemUpdated;
- (void)VLCPLTreeUpdate:(NSNumber *)begin;
- (void)rememberExpandedItemsForCurrentRoot;
- (void)restoreExpandedItemsInNode:(VLCPLItem *)node
                           fromSet:(NSSet *)expandedIds;
- (void)restoreExpandedItemsForRootId:(NSNumber *)rootId;
- (NSSet *)selectedPlaylistItemIds;
- (void)restoreSelectedPlaylistItemIds:(NSSet *)itemIds;
- (void)rebuildVLCPLItem:(VLCPLItem *)item
        fromPlaylistItem:(playlist_item_t *)playlistItem;
- (VLCPLItem *)findLibrarySearchScopeByPlaylistId:(int)playlistId;
- (void)reflectDraggedItemsMovedTo:(VLCPLItem *)targetItem
                        childIndex:(NSInteger)index;

@end

static BOOL VLCInputMatchesLibrarySearch(input_item_t *input,
                                         NSString *needle)
{
    if (!input || ![needle length])
        return YES;
    if (input_item_IsPowerVLCRandomAction(input))
        return NO;
    char *values[] = {
        input_item_GetTitleFbName(input),
        input_item_GetArtist(input),
        input_item_GetAlbum(input),
        input_item_GetAlbumArtist(input)
    };
    BOOL matches = NO;
    for (NSUInteger i = 0; i < sizeof(values) / sizeof(values[0]); ++i) {
        if (values[i]) {
            NSString *value = [NSString stringWithUTF8String:values[i]];
            if (value && [value rangeOfString:needle
                options:(NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch)]
                .location != NSNotFound)
                matches = YES;
            free(values[i]);
        }
    }
    return matches;
}

#pragma mark -

static int VLCPLItemUpdated(vlc_object_t *p_this, const char *psz_var,
                         vlc_value_t oldval, vlc_value_t new_val, void *param)
{
    @autoreleasepool {
        VLCPLModel *model = (__bridge VLCPLModel*)param;
        [model performSelectorOnMainThread:@selector(VLCPLItemUpdated) withObject:nil waitUntilDone:NO];

        return VLC_SUCCESS;
    }
}

static int VLCPLItemAppended(vlc_object_t *p_this, const char *psz_var,
                          vlc_value_t oldval, vlc_value_t new_val, void *param)
{
    @autoreleasepool {
        /* playlist_InsertInputItemTree() brackets bulk service-discovery
         * publications.  Do not put one main-run-loop message per child on
         * the queue: the matching end notification rebuilds the model once
         * from the completed core tree. */
        if (var_GetBool(p_this, "playlist-item-tree-update"))
            return VLC_SUCCESS;
        playlist_item_t *p_item = new_val.p_address;
        int i_node = p_item->p_parent ? p_item->p_parent->i_id : -1;
        NSArray *o_val = [NSArray arrayWithObjects:[NSNumber numberWithInt:i_node], [NSNumber numberWithInt:p_item->i_id], nil];
        VLCPLModel *model = (__bridge VLCPLModel*)param;
        [model performSelectorOnMainThread:@selector(VLCPLItemAppended:) withObject:o_val waitUntilDone:NO];

        return VLC_SUCCESS;
    }
}

static int VLCPLItemRemoved(vlc_object_t *p_this, const char *psz_var,
                         vlc_value_t oldval, vlc_value_t new_val, void *param)
{
    @autoreleasepool {
        playlist_item_t *p_item = new_val.p_address;
        NSNumber *o_val = [NSNumber numberWithInt:p_item->i_id];
        VLCPLModel *model = (__bridge VLCPLModel*)param;
        [model performSelectorOnMainThread:@selector(VLCPLItemRemoved:) withObject:o_val waitUntilDone:NO];

        return VLC_SUCCESS;
    }
}

static int VLCPLTreeUpdate(vlc_object_t *p_this, const char *psz_var,
                           vlc_value_t oldval, vlc_value_t new_val, void *param)
{
    @autoreleasepool {
        VLCPLModel *model = (__bridge VLCPLModel*)param;
        NSNumber *begin = [NSNumber numberWithBool:new_val.b_bool];
        [model performSelectorOnMainThread:@selector(VLCPLTreeUpdate:)
                                withObject:begin waitUntilDone:NO];
        return VLC_SUCCESS;
    }
}

static int PlaybackModeUpdated(vlc_object_t *p_this, const char *psz_var,
                               vlc_value_t oldval, vlc_value_t new_val, void *param)
{
    @autoreleasepool {
        VLCPLModel *model = (__bridge VLCPLModel*)param;
        [model performSelectorOnMainThread:@selector(playbackModeUpdated) withObject:nil waitUntilDone:NO];

        return VLC_SUCCESS;
    }
}

static int VolumeUpdated(vlc_object_t *p_this, const char *psz_var,
                         vlc_value_t oldval, vlc_value_t new_val, void *param)
{
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[[VLCMain sharedInstance] mainWindow] updateVolumeSlider];
        });

        return VLC_SUCCESS;
    }
}

#pragma mark -

@implementation VLCPLModel

#pragma mark -
#pragma mark Init and Stuff

- (id)initWithOutlineView:(NSOutlineView *)outlineView playlist:(playlist_t *)pl rootItem:(playlist_item_t *)root;
{
    self = [super init];
    if (self) {
        p_playlist = pl;
        _outlineView = outlineView;
        _expandedItemIdsByRootId = [[NSMutableDictionary alloc] init];

        msg_Dbg(getIntf(), "Initializing playlist model");
        var_AddCallback(p_playlist, "item-change", VLCPLItemUpdated, (__bridge void *)self);
        var_AddCallback(p_playlist, "playlist-item-append", VLCPLItemAppended, (__bridge void *)self);
        var_AddCallback(p_playlist, "playlist-item-deleted", VLCPLItemRemoved, (__bridge void *)self);
        var_AddCallback(p_playlist, "playlist-item-tree-update", VLCPLTreeUpdate, (__bridge void *)self);
        var_AddCallback(p_playlist, "random", PlaybackModeUpdated, (__bridge void *)self);
        var_AddCallback(p_playlist, "repeat", PlaybackModeUpdated, (__bridge void *)self);
        var_AddCallback(p_playlist, "loop", PlaybackModeUpdated, (__bridge void *)self);
        var_AddCallback(p_playlist, "volume", VolumeUpdated, (__bridge void *)self);
        var_AddCallback(p_playlist, "mute", VolumeUpdated, (__bridge void *)self);

        PL_LOCK;
        _rootItem = [[VLCPLItem alloc] initWithPlaylistItem:root];
        [self rebuildVLCPLItem:_rootItem fromPlaylistItem:root];
        PL_UNLOCK;
    }

    return self;
}

- (void)dealloc
{
    msg_Dbg(getIntf(), "Deinitializing playlist model");
    var_DelCallback(p_playlist, "item-change", VLCPLItemUpdated, (__bridge void *)self);
    var_DelCallback(p_playlist, "playlist-item-append", VLCPLItemAppended, (__bridge void *)self);
    var_DelCallback(p_playlist, "playlist-item-deleted", VLCPLItemRemoved, (__bridge void *)self);
    var_DelCallback(p_playlist, "playlist-item-tree-update", VLCPLTreeUpdate, (__bridge void *)self);
    var_DelCallback(p_playlist, "random", PlaybackModeUpdated, (__bridge void *)self);
    var_DelCallback(p_playlist, "repeat", PlaybackModeUpdated, (__bridge void *)self);
    var_DelCallback(p_playlist, "loop", PlaybackModeUpdated, (__bridge void *)self);
    var_DelCallback(p_playlist, "volume", VolumeUpdated, (__bridge void *)self);
    var_DelCallback(p_playlist, "mute", VolumeUpdated, (__bridge void *)self);
}

- (void)changeRootItem:(playlist_item_t *)p_root;
{
    PL_ASSERT_LOCKED;
    [self rememberExpandedItemsForCurrentRoot];

    NSNumber *rootId = [NSNumber numberWithInt:p_root->i_id];
    _rootItem = [[VLCPLItem alloc] initWithPlaylistItem:p_root];
    [self rebuildVLCPLItem:_rootItem fromPlaylistItem:p_root];

    [_outlineView reloadData];
    [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];

    /* Callers hold the playlist lock. Expanding an unbrowsed directory can
     * start its preparser from the outline-view delegate, which also needs
     * that lock, so restore once the current main-loop pass has released it. */
    dispatch_async(dispatch_get_main_queue(), ^{
        [self restoreExpandedItemsForRootId:rootId];
    });
}

- (void)rememberExpandedItemsForCurrentRoot
{
    if (!_rootItem || !_outlineView)
        return;

    NSMutableSet *expandedIds = [NSMutableSet set];
    NSInteger rowCount = [_outlineView numberOfRows];
    for (NSInteger row = 0; row < rowCount; ++row) {
        VLCPLItem *item = [_outlineView itemAtRow:row];
        if ([item isKindOfClass:[VLCPLItem class]]
         && [_outlineView isItemExpanded:item])
            [expandedIds addObject:[NSNumber numberWithInt:[item plItemId]]];
    }

    NSNumber *rootId = [NSNumber numberWithInt:[_rootItem plItemId]];
    [_expandedItemIdsByRootId setObject:expandedIds forKey:rootId];
}

- (void)restoreExpandedItemsInNode:(VLCPLItem *)node
                           fromSet:(NSSet *)expandedIds
{
    for (VLCPLItem *child in [node children]) {
        NSNumber *itemId = [NSNumber numberWithInt:[child plItemId]];
        if (![expandedIds containsObject:itemId])
            continue;

        [_outlineView expandItem:child];

        /* Restore parents before descendants. An expanded descendant was
         * necessarily visible when saved, so all its ancestors are present
         * in the set as well. Limiting recursion to expanded branches also
         * avoids walking every station in large radio directories. */
        [self restoreExpandedItemsInNode:child fromSet:expandedIds];
    }
}

- (void)restoreExpandedItemsForRootId:(NSNumber *)rootId
{
    if ([_rootItem plItemId] != [rootId intValue])
        return; /* the user selected another source before this block ran */

    NSSet *expandedIds = [_expandedItemIdsByRootId objectForKey:rootId];
    if ([expandedIds count] > 0)
        [self restoreExpandedItemsInNode:_rootItem fromSet:expandedIds];
}

- (BOOL)hasChildren
{
    return [[_rootItem children] count] > 0;
}

- (PLRootType)currentRootType
{
    int i_root_id = [_rootItem plItemId];
    if (i_root_id == p_playlist->p_playing->i_id)
        return ROOT_TYPE_PLAYLIST;
    if (p_playlist->p_media_library && i_root_id == p_playlist->p_media_library->i_id)
        return ROOT_TYPE_MEDIALIBRARY;

    return ROOT_TYPE_OTHER;
}

- (BOOL)editAllowed
{
    return [self currentRootType] == ROOT_TYPE_MEDIALIBRARY ||
    [self currentRootType] == ROOT_TYPE_PLAYLIST;
}

- (BOOL)isPowerVLCLibraryRoot
{
    input_item_t *input = [_rootItem input];
    char *name = input ? input_item_GetName(input) : NULL;
    BOOL result = name && (!strcmp(name, "PowerVLC Media Library")
                        || !strcmp(name, _("PowerVLC Media Library")));
    free(name);
    return result;
}

- (BOOL)importPasteboardIntoPowerVLCLibrary:(NSPasteboard *)pasteboard
{
    playlist_t *playlist = pl_Get(getIntf());
    if (!playlist_IsServicesDiscoveryLoaded(playlist, "powervlc_library")
     && playlist_ServicesDiscoveryAdd(playlist, "powervlc_library") != VLC_SUCCESS)
        return NO;

    NSMutableArray *paths = [NSMutableArray arrayWithArray:
                              VLCFilePathsFromPasteboard(pasteboard)];
    if ([[pasteboard types] containsObject:VLCPLItemPasteboadType]) {
        PL_LOCK;
        for (VLCPLItem *dragged in _draggedItems) {
            playlist_item_t *item = playlist_ItemGetById(playlist,
                                                          [dragged plItemId]);
            char *path = item && item->p_input
                       ? vlc_uri2path(item->p_input->psz_uri) : NULL;
            if (path) {
                NSString *value = toNSStr(path);
                if (![paths containsObject:value]) [paths addObject:value];
                free(path);
            }
        }
        PL_UNLOCK;
    }

    BOOL imported = NO;
    for (NSString *path in paths) {
        services_discovery_import_t request = {
            [path fileSystemRepresentation], NULL, NULL, NULL, NULL
        };
        if (playlist_ServicesDiscoveryControl(playlist, "powervlc_library",
              SD_CMD_POWERVLC_IMPORT, &request) == VLC_SUCCESS)
            imported = YES;
    }
    return imported;
}

- (void)deleteSelectedItem
{
    // check if deletion is allowed
    if (![self editAllowed])
        return;

    NSIndexSet *selectedIndexes = [_outlineView selectedRowIndexes];
    _retainedRowSelection = [selectedIndexes firstIndex];
    if (_retainedRowSelection == NSNotFound)
        _retainedRowSelection = 0;

    [selectedIndexes enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL *stop) {
        VLCPLItem *item = [_outlineView itemAtRow: idx];
        if (!item)
            return;

        // model deletion is done via callback
        PL_LOCK;
        playlist_item_t *p_root = playlist_ItemGetById(p_playlist, [item plItemId]);
        if( p_root != NULL )
            playlist_NodeDelete(p_playlist, p_root);
        PL_UNLOCK;
    }];
}

- (void)rebuildVLCPLItem:(VLCPLItem *)item
{
    playlist_item_t *p_item = playlist_ItemGetById(p_playlist, [item plItemId]);
    [self rebuildVLCPLItem:item fromPlaylistItem:p_item];
}

- (void)rebuildVLCPLItem:(VLCPLItem *)item
        fromPlaylistItem:(playlist_item_t *)p_item
{
    [item clear];
    if (!p_item)
        return;
    int currPos = 0;
    for (int i = 0; i < p_item->i_children; ++i) {
        playlist_item_t *p_child = p_item->pp_children[i];
        if (p_child->i_flags & PLAYLIST_DBL_FLAG)
            continue;
        VLCPLItem *child = [[VLCPLItem alloc] initWithPlaylistItem:p_child];
        [item addChild:child atPos:currPos++];
        if (p_child->i_children >= 0)
            [self rebuildVLCPLItem:child fromPlaylistItem:p_child];
    }

}

- (VLCPLItem *)findItemByPlaylistId:(int)i_pl_id
{
    return [self findItemInnerByPlaylistId:i_pl_id node:_rootItem];
}

/* Library searches are scoped to the category rows immediately below the
 * library sections.  Looking those rows up with the generic depth-first
 * helper can walk tens of thousands of track wrappers before it reaches a
 * later category, which is especially visible while a scan is running. */
- (VLCPLItem *)findLibrarySearchScopeByPlaylistId:(int)i_pl_id
{
    if ([_rootItem plItemId] == i_pl_id)
        return _rootItem;
    for (VLCPLItem *section in [_rootItem children]) {
        if ([section plItemId] == i_pl_id)
            return section;
        for (VLCPLItem *category in [section children])
            if ([category plItemId] == i_pl_id)
                return category;
    }
    return nil;
}

- (VLCPLItem *)findItemInnerByPlaylistId:(int)i_pl_id node:(VLCPLItem *)node
{
    if ([node plItemId] == i_pl_id) {
        return node;
    }

    for (NSUInteger i = 0; i < [[node children] count]; ++i) {
        VLCPLItem *o_sub_item = [[node children] objectAtIndex:i];
        if ([o_sub_item plItemId] == i_pl_id) {
            return o_sub_item;
        }

        if (![o_sub_item isLeaf]) {
            VLCPLItem *o_returned = [self findItemInnerByPlaylistId:i_pl_id node:o_sub_item];
            if (o_returned)
                return o_returned;
        }
    }

    return nil;
}

#pragma mark -
#pragma mark Core events


- (void)VLCPLItemAppended:(NSArray *)valueArray
{
    if (_bulkTreeUpdateDepth > 0)
        return;
    int i_node = [[valueArray firstObject] intValue];
    int i_item = [[valueArray objectAtIndex:1] intValue];

    if (!_stateRestorePending) {
        [self rememberExpandedItemsForCurrentRoot];
        _pendingSelectedItemIds = [self selectedPlaylistItemIds];
        _stateRestorePending = YES;
    }
    NSNumber *rootId = [NSNumber numberWithInt:[_rootItem plItemId]];
    [self addItem:i_item withParentNode:i_node];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self restoreExpandedItemsForRootId:rootId];
        [self restoreSelectedPlaylistItemIds:_pendingSelectedItemIds];
        _pendingSelectedItemIds = nil;
        _stateRestorePending = NO;
    });

    // update badge in sidebar
    [[[VLCMain sharedInstance] mainWindow] updateWindow];

    /* A Random action may have requested its normal lazy letter after
     * playback started. Each appended node is another chance to resolve the
     * playing URI in that visible branch and move the selection there. */
    [[[VLCMain sharedInstance] playlist] scheduleRandomSelectionRetry];

    [[NSNotificationCenter defaultCenter] postNotificationName: VLCMediaKeySupportSettingChangedNotification
                                                        object: nil
                                                      userInfo: nil];
}

- (void)VLCPLTreeUpdate:(NSNumber *)begin
{
    if ([begin boolValue]) {
        if (_bulkTreeUpdateDepth++ == 0) {
            [self rememberExpandedItemsForCurrentRoot];
            _pendingSelectedItemIds = [self selectedPlaylistItemIds];
        }
        return;
    }

    if (_bulkTreeUpdateDepth == 0 || --_bulkTreeUpdateDepth > 0)
        return;

    NSNumber *rootId = [NSNumber numberWithInt:[_rootItem plItemId]];
    PL_LOCK;
    playlist_item_t *root = playlist_ItemGetById(p_playlist, [rootId intValue]);
    if (root) {
        _rootItem = [[VLCPLItem alloc] initWithPlaylistItem:root];
        [self rebuildVLCPLItem:_rootItem fromPlaylistItem:root];
    }
    PL_UNLOCK;
    [_outlineView reloadData];
    [self restoreExpandedItemsForRootId:rootId];
    [self restoreSelectedPlaylistItemIds:_pendingSelectedItemIds];
    _pendingSelectedItemIds = nil;

    [[[VLCMain sharedInstance] mainWindow] updateWindow];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:VLCMediaKeySupportSettingChangedNotification
                      object:nil userInfo:nil];
}

- (void)VLCPLItemRemoved:(NSNumber *)value
{
    int i_item = [value intValue];

    if (!_stateRestorePending) {
        [self rememberExpandedItemsForCurrentRoot];
        _pendingSelectedItemIds = [self selectedPlaylistItemIds];
        _stateRestorePending = YES;
    }
    NSNumber *rootId = [NSNumber numberWithInt:[_rootItem plItemId]];
    [self removeItem:i_item];
    dispatch_async(dispatch_get_main_queue(), ^{
        [self restoreExpandedItemsForRootId:rootId];
        [self restoreSelectedPlaylistItemIds:_pendingSelectedItemIds];
        _pendingSelectedItemIds = nil;
        _stateRestorePending = NO;
    });

    // update badge in sidebar
    [[[VLCMain sharedInstance] mainWindow] updateWindow];

    [[NSNotificationCenter defaultCenter] postNotificationName: VLCMediaKeySupportSettingChangedNotification
                                                        object: nil
                                                      userInfo: nil];
}

- (void)VLCPLItemUpdated
{
    VLCMain *instance = [VLCMain sharedInstance];
    [[instance mainWindow] updateName];

    [[instance currentMediaInfoPanel] updateMetadata];
}

- (void)addItem:(int)i_item withParentNode:(int)i_node
{
    NSSet *selectedIds = [self selectedPlaylistItemIds];
    VLCPLItem *o_parent = [self findItemByPlaylistId:i_node];
    if (!o_parent) {
        return;
    }

    /* The append notification is handed over to the main thread, so a
     * rebuild can run in between and pick the item up on its own -- that
     * is what selecting a service discovery does: the module starts
     * adding on its own thread and changeRootItem: reads the finished
     * tree. Adding it again would leave two rows for one playlist item
     * (a podcast subscription showing up twice). */
    if ([self findItemByPlaylistId:i_item]) {
        return;
    }

    PL_LOCK;
    playlist_item_t *p_item = playlist_ItemGetById(p_playlist, i_item);
    if (!p_item || p_item->i_flags & PLAYLIST_DBL_FLAG)
    {
        PL_UNLOCK;
        return;
    }

    /* a search is active: filter the new arrival like searchUpdate: would
     * have, both for the display and for the core (playback advance must
     * not fall back on items the view does not show) */
    BOOL inSearchScope = NO;
    for (playlist_item_t *ancestor = p_item; ancestor;
         ancestor = ancestor->p_parent) {
        if ([_latestSearchScopeItemIds containsObject:
                [NSNumber numberWithInt:ancestor->i_id]]) {
            inSearchScope = YES;
            break;
        }
    }
    if (inSearchScope && [_latestSearchString length] > 0
     && p_item->i_children == -1) {
        BOOL b_matches = VLCInputMatchesLibrarySearch(p_item->p_input,
                                                       _latestSearchString);
        if (!b_matches) {
            p_item->i_flags |= PLAYLIST_DBL_FLAG;
            PL_UNLOCK;
            return;
        }
    }

    int pos;
    for(pos = p_item->p_parent->i_children - 1; pos >= 0; pos--)
        if(p_item->p_parent->pp_children[pos] == p_item)
            break;

    VLCPLItem *o_new_item = [[VLCPLItem alloc] initWithPlaylistItem:p_item];
    PL_UNLOCK;
    if (pos < 0)
        return;

    [o_parent addChild:o_new_item atPos:pos];

    if ([o_parent plItemId] == [_rootItem plItemId])
        [_outlineView reloadData];
    else // only reload leafs this way, doing it with nil collapses width of title column
        [_outlineView reloadItem:o_parent reloadChildren:YES];
    [self restoreSelectedPlaylistItemIds:selectedIds];
}

- (NSSet *)selectedPlaylistItemIds
{
    NSMutableSet *ids = [NSMutableSet set];
    NSIndexSet *rows = [_outlineView selectedRowIndexes];
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        VLC_UNUSED(stop);
        VLCPLItem *item = [_outlineView itemAtRow:(NSInteger)row];
        if (item) [ids addObject:@([item plItemId])];
    }];
    return ids;
}

- (void)restoreSelectedPlaylistItemIds:(NSSet *)itemIds
{
    if ([[[VLCMain sharedInstance] playlist] restoreRandomActionSelection])
        return;
    if (![itemIds count]) return;
    NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
    for (NSInteger row = 0; row < [_outlineView numberOfRows]; ++row) {
        VLCPLItem *item = [_outlineView itemAtRow:row];
        if (item && [itemIds containsObject:@([item plItemId])])
            [rows addIndex:(NSUInteger)row];
    }
    if ([rows count])
        [_outlineView selectRowIndexes:rows byExtendingSelection:NO];
}

- (void)removeItem:(int)i_item
{
    VLCPLItem *o_item = [self findItemByPlaylistId:i_item];
    if (!o_item) {
        return;
    }

    VLCPLItem *o_parent = [o_item parent];
    [o_parent deleteChild:o_item];

    if ([o_parent plItemId] == [_rootItem plItemId])
        [_outlineView reloadData];
    else
        [_outlineView reloadItem:o_parent reloadChildren:YES];
}

- (void)updateItem:(input_item_t *)p_input_item
{
    PL_LOCK;
    playlist_item_t *pl_item = playlist_ItemGetByInput(p_playlist, p_input_item);
    if (!pl_item) {
        PL_UNLOCK;
        return;
    }
    VLCPLItem *item = [self findItemByPlaylistId:pl_item->i_id];
    PL_UNLOCK;

    if (!item)
        return;

    NSInteger row = [_outlineView rowForItem:item];
    if (row == -1)
        return;

    [_outlineView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndex:row]
                            columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [[_outlineView tableColumns] count])]];

}

- (VLCPLItem *)currentlyPlayingItem
{
    VLCPLItem *item = nil;

    PL_LOCK;
    playlist_item_t *p_current = playlist_CurrentPlayingItem(p_playlist);
    if (p_current)
        item = [self findItemByPlaylistId:p_current->i_id];
    PL_UNLOCK;
    return item;
}

- (void)playbackModeUpdated
{
    bool loop = var_GetBool(p_playlist, "loop");
    bool repeat = var_GetBool(p_playlist, "repeat");

    VLCMainWindowControlsBar *controlsBar = (VLCMainWindowControlsBar *)[[[VLCMain sharedInstance] mainWindow] controlsBar];
    VLCMainMenu *mainMenu = [[VLCMain sharedInstance] mainMenu];
    if (repeat) {
        [controlsBar setRepeatOne];
        [mainMenu setRepeatOne];
    } else if (loop) {
        [controlsBar setRepeatAll];
        [mainMenu setRepeatAll];
    } else {
        [controlsBar setRepeatOff];
        [mainMenu setRepeatOff];
    }

    [controlsBar setShuffle];
    [mainMenu setShuffle];
}

#pragma mark -
#pragma mark Sorting / Searching

- (void)sortPlaylistBy:(int)mode withOrder:(int)order
{
    PL_LOCK;
    playlist_item_t *p_root = playlist_ItemGetById(p_playlist, [_rootItem plItemId]);
    if (!p_root) {
        PL_UNLOCK;
        return;
    }

    playlist_RecursiveNodeSort(p_playlist, p_root, mode, order);

    [self rebuildVLCPLItem:_rootItem fromPlaylistItem:p_root];
    [_outlineView reloadData];
    PL_UNLOCK;
}

- (void)sortForColumn:(NSString *)o_column withMode:(int)i_mode
{
    int i_column = 0;
    if ([o_column isEqualToString:TRACKNUM_COLUMN])
        i_column = SORT_TRACK_NUMBER;
    else if ([o_column isEqualToString:TITLE_COLUMN])
        i_column = SORT_TITLE;
    else if ([o_column isEqualToString:ARTIST_COLUMN])
        i_column = SORT_ARTIST;
    else if ([o_column isEqualToString:GENRE_COLUMN])
        i_column = SORT_GENRE;
    else if ([o_column isEqualToString:DURATION_COLUMN])
        i_column = SORT_DURATION;
    else if ([o_column isEqualToString:ALBUM_COLUMN])
        i_column = SORT_ALBUM;
    else if ([o_column isEqualToString:DESCRIPTION_COLUMN])
        i_column = SORT_DESCRIPTION;
    else if ([o_column isEqualToString:URI_COLUMN])
        i_column = SORT_URI;
    else if ([o_column isEqualToString:FILESIZE_COLUMN])
        i_column = SORT_FILE_SIZE;
    else
        return;

    [self sortPlaylistBy:i_column withOrder:i_mode];
}

- (void)searchUpdate:(NSString *)o_search
{
    [self searchUpdate:o_search withinItemIds:nil];
}

- (void)searchUpdate:(NSString *)o_search withinItemIds:(NSSet *)itemIds
{
    NSString *normalized = [o_search stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSSet *previousScopeItemIds = _latestSearchScopeItemIds;
    _latestSearchString = [normalized length] > 0 ? [normalized copy] : nil;
    _latestSearchScopeItemIds = [normalized length] > 0
                              ? [itemIds copy] : nil;
    [self rememberExpandedItemsForCurrentRoot];
    NSNumber *rootId = [NSNumber numberWithInt:[_rootItem plItemId]];
    BOOL librarySearch = [self isPowerVLCLibraryRoot];
    NSMutableSet *affectedScopeItemIds = [NSMutableSet set];
    if (previousScopeItemIds)
        [affectedScopeItemIds unionSet:previousScopeItemIds];
    if (_latestSearchScopeItemIds)
        [affectedScopeItemIds unionSet:_latestSearchScopeItemIds];
    NSMutableArray *affectedWrappers = [NSMutableArray array];

    PL_LOCK;
    playlist_item_t *p_root = playlist_ItemGetById(p_playlist, [_rootItem plItemId]);
    if (!p_root) {
        PL_UNLOCK;
        return;
    }

    if (librarySearch) {
        /* Clear and rebuild only the categories touched by the previous or
         * current query.  Rebuilding the complete library used to allocate a
         * wrapper for every indexed occurrence on every keystroke. */
        for (NSNumber *itemId in previousScopeItemIds) {
            playlist_item_t *scope = playlist_ItemGetById(p_playlist,
                                                           [itemId intValue]);
            if (scope)
                playlist_LiveSearchUpdate(p_playlist, scope, "", true);
        }
        if ([normalized length]) {
            for (NSNumber *itemId in itemIds) {
                playlist_item_t *scope = playlist_ItemGetById(p_playlist,
                                                               [itemId intValue]);
                if (scope)
                    playlist_LiveSearchUpdate(p_playlist, scope,
                                              [normalized UTF8String], true);
            }
        }
        for (NSNumber *itemId in affectedScopeItemIds) {
            playlist_item_t *scope = playlist_ItemGetById(p_playlist,
                                                           [itemId intValue]);
            VLCPLItem *wrapper = [self findLibrarySearchScopeByPlaylistId:
                                                   [itemId intValue]];
            if (scope && wrapper) {
                [self rebuildVLCPLItem:wrapper fromPlaylistItem:scope];
                [affectedWrappers addObject:wrapper];
            }
        }
    } else {
        playlist_LiveSearchUpdate(p_playlist, p_root, "", true);
        if ([normalized length])
            playlist_LiveSearchUpdate(p_playlist, p_root,
                                      [normalized UTF8String], true);
        [self rebuildVLCPLItem:_rootItem fromPlaylistItem:p_root];
    }
    PL_UNLOCK;

    if (librarySearch) {
        for (VLCPLItem *wrapper in affectedWrappers)
            [_outlineView reloadItem:wrapper reloadChildren:YES];
    } else {
        [_outlineView reloadData];
    }
    [self restoreExpandedItemsForRootId:rootId];
}

@end

#pragma mark -
#pragma mark Outline view data source

@implementation VLCPLModel(NSOutlineViewDataSource)

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item
{
    if (VLCPLItemIsPowerVLCRandomAction(item))
        return 0;
    return !item ? [[_rootItem children] count] : [[item children] count];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    if (!item)
        return YES;
    input_item_t *p_input = [item input];
    if (VLCPLItemIsPowerVLCRandomAction(item))
        return NO;
    if ([_latestSearchString length]
     && [_latestSearchScopeItemIds containsObject:
            [NSNumber numberWithInt:[item plItemId]]])
        return YES;
    if ([[item children] count] > 0)
        return YES;

    /* unbrowsed directories (file browser folders, radio directory
     * countries...) get their disclosure triangle right away: expanding
     * them triggers the browse (see outlineViewItemDidExpand:) */
    return p_input && (p_input->i_type == ITEM_TYPE_DIRECTORY
                    || VLCPLInputIsPowerVLCIndex(p_input));
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item
{
    id obj = !item ? _rootItem : item;
    return [[obj children] objectAtIndex:index];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    id o_value = nil;
    char *psz_value;

    input_item_t *p_input = [item input];

    NSString * o_identifier = [tableColumn identifier];

    if ([o_identifier isEqualToString:TRACKNUM_COLUMN]) {
        psz_value = input_item_GetTrackNumber(p_input);
        o_value = toNSStr(psz_value);
        free(psz_value);

    } else if ([o_identifier isEqualToString:TITLE_COLUMN]) {
        psz_value = VLCPLDisplayTitle(p_input);
        o_value = toNSStr(psz_value);
        free(psz_value);
        if ([item isLeaf] && !VLCPLItemIsPowerVLCRandomAction(item)) {
            char *ratingValue = input_item_GetRating(p_input);
            unsigned rating = ratingValue
                ? (unsigned)strtoul(ratingValue, NULL, 10) : 0;
            free(ratingValue);
            if (rating > 0 && rating <= 5) {
                NSMutableString *stars = [NSMutableString string];
                for (unsigned i = 0; i < rating; ++i)
                    [stars appendString:@"★"];
                NSMutableParagraphStyle *style =
                    [[NSMutableParagraphStyle alloc] init];
                CGFloat indentation = ([outlineView levelForItem:item] + 1)
                                      * [outlineView indentationPerLevel];
                CGFloat stop = MAX(40.0, [tableColumn width]
                                           - indentation - 12.0);
                [style setTabStops:@[[[NSTextTab alloc]
                    initWithType:NSRightTabStopType location:stop]]];
                NSString *text = [NSString stringWithFormat:@"%@\t%@",
                    o_value ?: @"", stars];
                o_value = [[NSAttributedString alloc] initWithString:text
                    attributes:@{ NSParagraphStyleAttributeName: style }];
            }
        }

    } else if ([o_identifier isEqualToString:ARTIST_COLUMN]) {
        psz_value = input_item_GetArtist(p_input);
        o_value = toNSStr(psz_value);
        free(psz_value);

    } else if ([o_identifier isEqualToString:DURATION_COLUMN]) {
        char psz_duration[MSTRTIME_MAX_SIZE];
        vlc_tick_t dur = input_item_GetDuration(p_input);
        if (dur != -1) {
            secstotimestr(psz_duration, dur/1000000);
            o_value = toNSStr(psz_duration);
        }
        else
            o_value = @"--:--";

    } else if ([o_identifier isEqualToString:GENRE_COLUMN]) {
        psz_value = input_item_GetGenre(p_input);
        o_value = toNSStr(psz_value);
        free(psz_value);

    } else if ([o_identifier isEqualToString:ALBUM_COLUMN]) {
        psz_value = input_item_GetAlbum(p_input);
        o_value = toNSStr(psz_value);
        free(psz_value);

    } else if ([o_identifier isEqualToString:DESCRIPTION_COLUMN]) {
        psz_value = input_item_GetDescription(p_input);
        o_value = toNSStr(psz_value);
        free(psz_value);

    } else if ([o_identifier isEqualToString:DATE_COLUMN]) {
        psz_value = input_item_GetDate(p_input);
        o_value = toNSStr(psz_value);
        free(psz_value);

    } else if ([o_identifier isEqualToString:LANGUAGE_COLUMN]) {
        psz_value = input_item_GetLanguage(p_input);
        o_value = toNSStr(psz_value);
        free(psz_value);

    } else if ([o_identifier isEqualToString:URI_COLUMN]) {
        psz_value = vlc_uri_decode(input_item_GetURI(p_input));
        o_value = toNSStr(psz_value);
        free(psz_value);

    } else if ([o_identifier isEqualToString:FILESIZE_COLUMN]) {
        psz_value = input_item_GetURI(p_input);
        if (!psz_value)
            return @"";
        NSURL *url = [NSURL URLWithString:toNSStr(psz_value)];
        free(psz_value);
        if (![url isFileURL])
            return @"";

        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL b_isDir;
        if (![fileManager fileExistsAtPath:[url path] isDirectory:&b_isDir] || b_isDir)
            return @"";

        NSDictionary *attributes = [fileManager attributesOfItemAtPath:[url path] error:nil];
        if (!attributes)
            return @"";

        o_value = [VLCByteCountFormatter stringFromByteCount:[attributes fileSize] countStyle:NSByteCountFormatterCountStyleDecimal];

    }

    return o_value;
}

#pragma mark -
#pragma mark Drag and Drop support

- (void)reflectDraggedItemsMovedTo:(VLCPLItem *)targetItem
                        childIndex:(NSInteger)index
{
    NSInteger destination = index == NSOutlineViewDropOnItemIndex
                          ? [[targetItem children] count] : index;
    for (VLCPLItem *dragged in _draggedItems) {
        if ([dragged parent] == targetItem) {
            NSUInteger oldIndex = [[targetItem children]
                                  indexOfObjectIdenticalTo:dragged];
            if (oldIndex != NSNotFound && oldIndex < destination)
                --destination;
        }
    }
    for (VLCPLItem *dragged in _draggedItems)
        [[dragged parent] deleteChild:dragged];
    for (VLCPLItem *dragged in _draggedItems)
        [targetItem addChild:dragged atPos:(int)destination++];

    [_outlineView reloadItem:targetItem reloadChildren:YES];
    NSMutableIndexSet *selection = [NSMutableIndexSet indexSet];
    for (VLCPLItem *dragged in _draggedItems) {
        NSInteger row = [_outlineView rowForItem:dragged];
        if (row >= 0) [selection addIndex:(NSUInteger)row];
    }
    [_outlineView selectRowIndexes:selection byExtendingSelection:NO];
}

- (BOOL)isItem: (VLCPLItem *)p_item inNode: (VLCPLItem *)p_node
{
    while(p_item) {
        if ([p_item plItemId] == [p_node plItemId]) {
            return YES;
        }

        p_item = [p_item parent];
    }

    return NO;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView writeItems:(NSArray *)items toPasteboard:(NSPasteboard *)pboard
{
    NSMutableArray *transferable = [NSMutableArray array];
    for (VLCPLItem *item in items)
        if (!input_item_IsPowerVLCRandomAction([item input]))
            [transferable addObject:item];
    if (![transferable count])
        return NO;
    _draggedItems = [[NSMutableArray alloc] initWithArray:transferable];

    /* Add the data to the pasteboard object. */
    [pboard declareTypes: [NSArray arrayWithObject:VLCPLItemPasteboadType] owner: self];
    [pboard setData:[NSData data] forType:VLCPLItemPasteboadType];

    return YES;
}

- (NSDragOperation)outlineView:(NSOutlineView *)outlineView validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    NSPasteboard *o_pasteboard = [info draggingPasteboard];
    NSString *deviceService = [[[[VLCMain sharedInstance] mainWindow]
                                  sidebarDataSource] selectedPowerDeviceService];

    if (deviceService && VLCPLItemIsUserPlaylist(item)
     && [[o_pasteboard types] containsObject:VLCPLItemPasteboadType]
     && [_draggedItems count] > 0) {
        BOOL insideTarget = YES;
        for (VLCPLItem *dragged in _draggedItems) {
            VLCPLItem *cursor = dragged;
            while (cursor && cursor != item) cursor = [cursor parent];
            insideTarget &= cursor == item;
        }
        return insideTarget ? NSDragOperationMove : NSDragOperationCopy;
    }

    if ([self isPowerVLCLibraryRoot]) {
        BOOL internal = [[o_pasteboard types]
                          containsObject:VLCPLItemPasteboadType];
        if (VLCPLItemIsInsideUserPlaylists(item)) {
            BOOL targetPlaylist = VLCPLItemIsUserPlaylist(item);
            BOOL targetFolder = VLCPLItemIsUserPlaylistRoot(item)
                             || VLCPLItemIsUserPlaylistFolder(item);
            BOOL sourcesInside = internal && [_draggedItems count] > 0;
            for (VLCPLItem *dragged in _draggedItems)
                sourcesInside &= VLCPLItemIsInsideUserPlaylists(dragged);
            if (sourcesInside)
                return (targetPlaylist || targetFolder)
                     ? NSDragOperationMove : NSDragOperationNone;
            return targetPlaylist && internal
                 ? NSDragOperationCopy : NSDragOperationNone;
        }
        if (internal || [VLCFilePathsFromPasteboard(o_pasteboard) count] > 0)
            return NSDragOperationCopy;
    }

    /* Dropping ON items is not allowed if item is not a node */
    if (item) {
        if (index == NSOutlineViewDropOnItemIndex && [item isLeaf]) {
            return NSDragOperationNone;
        }
    }

    if (![self editAllowed])
        return NSDragOperationNone;

    /* Drop from the Playlist */
    if ([[o_pasteboard types] containsObject:VLCPLItemPasteboadType]) {
        NSUInteger count = [_draggedItems count];
        for (NSUInteger i = 0 ; i < count ; i++) {
            /* We refuse to Drop in a child of an item we are moving */
            if ([self isItem: item inNode: [_draggedItems objectAtIndex:i]]) {
                return NSDragOperationNone;
            }
        }
        BOOL sourcesInsideRoot = count > 0;
        for (VLCPLItem *dragged in _draggedItems)
            sourcesInsideRoot &= [self isItem:dragged inNode:_rootItem];
        /* Hovering the Playlist sidebar entry can replace the displayed root
         * before mouse-up.  The retained wrappers still belong to the media
         * library: treating them as an internal move bypasses NodeAddCopy's
         * virtual-action filter and imports Random rows into the queue. */
        return sourcesInsideRoot ? NSDragOperationMove : NSDragOperationCopy;
    }
    /* Drop from the Finder */
    else if ([VLCFilePathsFromPasteboard(o_pasteboard) count] > 0) {
        return NSDragOperationGeneric;
    }
    return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView acceptDrop:(id <NSDraggingInfo>)info item:(id)targetItem childIndex:(NSInteger)index
{
    NSPasteboard *o_pasteboard = [info draggingPasteboard];
    NSString *deviceService = [[[[VLCMain sharedInstance] mainWindow]
                                  sidebarDataSource] selectedPowerDeviceService];

    if (deviceService && VLCPLItemIsUserPlaylist(targetItem)
     && [[o_pasteboard types] containsObject:VLCPLItemPasteboadType]) {
        NSUInteger count = [_draggedItems count];
        if (!count) return NO;
        int *ids = calloc(count, sizeof(*ids));
        if (!ids) return NO;
        BOOL insideTarget = YES;
        for (NSUInteger i = 0; i < count; ++i) {
            VLCPLItem *dragged = [_draggedItems objectAtIndex:i];
            ids[i] = [dragged plItemId];
            VLCPLItem *cursor = dragged;
            while (cursor && cursor != targetItem) cursor = [cursor parent];
            insideTarget &= cursor == targetItem;
        }
        services_discovery_playlist_drop_t request = {
            [targetItem plItemId],
            index == NSOutlineViewDropOnItemIndex ? -1 : (int)index,
            count, ids, !insideTarget
        };
        int result = playlist_ServicesDiscoveryControl(p_playlist,
            deviceService.UTF8String, SD_CMD_POWERVLC_PLAYLIST_DROP, &request);
        free(ids);
        if (result == VLC_SUCCESS && insideTarget) {
            /* The device service has already moved the matching libgpod and
             * core-playlist entries in RAM.  Reflect that small change in the
             * Cocoa wrapper as well.  Waiting for a complete iPod tree refresh
             * used to rebuild every track and playlist occurrence and froze
             * the outline for seconds after a one-row reorder. */
            [self reflectDraggedItemsMovedTo:(VLCPLItem *)targetItem
                                   childIndex:index];
        }
        return result == VLC_SUCCESS;
    }

    if ([self isPowerVLCLibraryRoot]) {
        if (VLCPLItemIsInsideUserPlaylists(targetItem)
         && [[o_pasteboard types] containsObject:VLCPLItemPasteboadType]) {
            NSUInteger count = [_draggedItems count];
            if (!count) return NO;
            int *ids = calloc(count, sizeof(*ids));
            if (!ids) return NO;
            BOOL sourcesInside = YES;
            for (NSUInteger i = 0; i < count; ++i) {
                VLCPLItem *dragged = [_draggedItems objectAtIndex:i];
                ids[i] = [dragged plItemId];
                sourcesInside &= VLCPLItemIsInsideUserPlaylists(dragged);
            }
            services_discovery_playlist_drop_t request = {
                [targetItem plItemId],
                index == NSOutlineViewDropOnItemIndex ? -1 : (int)index,
                count, ids, !sourcesInside
            };
            int result = playlist_ServicesDiscoveryControl(p_playlist,
                "powervlc_library", SD_CMD_POWERVLC_PLAYLIST_DROP, &request);
            free(ids);
            if (result == VLC_SUCCESS && !request.b_copy)
                [self reflectDraggedItemsMovedTo:(VLCPLItem *)targetItem
                                       childIndex:index];
            return result == VLC_SUCCESS;
        }
        return [self importPasteboardIntoPowerVLCLibrary:o_pasteboard];
    }

    if (targetItem == nil) {
        targetItem = _rootItem;
    }

    /* Drag & Drop inside the playlist */
    if ([[o_pasteboard types] containsObject:VLCPLItemPasteboadType]) {

        NSMutableArray *o_filteredItems = [NSMutableArray arrayWithArray:_draggedItems];
        const NSUInteger draggedItemsCount = [_draggedItems count];
        for (NSInteger i = 0; i < [o_filteredItems count]; i++) {
            for (NSUInteger j = 0; j < draggedItemsCount; j++) {
                VLCPLItem *itemToCheck = [o_filteredItems objectAtIndex:i];
                VLCPLItem *nodeToTest = [_draggedItems objectAtIndex:j];
                if ([itemToCheck plItemId] == [nodeToTest plItemId])
                    continue;

                if ([self isItem:itemToCheck inNode:nodeToTest]) {
                    [o_filteredItems removeObjectAtIndex:i];
                    --i;
                    break;
                }
            }
        }

        NSUInteger count = [o_filteredItems count];
        if (count == 0)
            return NO;

        BOOL sourcesInsideRoot = YES;
        for (VLCPLItem *dragged in o_filteredItems)
            sourcesInsideRoot &= [self isItem:dragged inNode:_rootItem];

        playlist_item_t **pp_items = (playlist_item_t **)calloc(count, sizeof(playlist_item_t*));
        if (!pp_items)
            return NO;

        PL_LOCK;
        playlist_item_t *p_new_parent = playlist_ItemGetById(p_playlist, [targetItem plItemId]);
        if (!p_new_parent) {
            PL_UNLOCK;
            free(pp_items);
            return NO;
        }

        NSUInteger j = 0;
        for (NSUInteger i = 0; i < count; i++) {
            playlist_item_t *p_item = playlist_ItemGetById(p_playlist, [[o_filteredItems objectAtIndex:i] plItemId]);
            if (p_item)
                pp_items[j++] = p_item;
        }

        // drop on a node itself will append entries at the end
        if (index == NSOutlineViewDropOnItemIndex)
            index = p_new_parent->i_children;

        BOOL success = YES;
        if (sourcesInsideRoot) {
            success = playlist_TreeMoveMany(p_playlist, j, pp_items,
                                             p_new_parent, index)
                   == VLC_SUCCESS;
        } else {
            int position = (int)index;
            for (NSUInteger i = 0; i < j; ++i)
                position = playlist_NodeAddCopy(p_playlist, pp_items[i],
                                                 p_new_parent, position);
        }

        PL_UNLOCK;
        free(pp_items);
        if (!success)
            return NO;

        // FIXME: Fix below code to avoid rebuilding the whole model
        // rebuild our model
//        NSUInteger filteredItemsCount = [o_filteredItems count];
//        for(int i = 0; i < filteredItemsCount; ++i) {
//            VLCPLItem *o_item = [o_filteredItems objectAtIndex:i];
//            NSLog(@"delete child from parent %p", [o_item parent]);
//            [[o_item parent] deleteChild:o_item];
//            [targetItem addChild:o_item atPos:(int)index + i];
//        }

        PL_LOCK;
        [self rebuildVLCPLItem:_rootItem];
        PL_UNLOCK;

        [_outlineView reloadData];

        NSMutableIndexSet *selectedIndexes = [[NSMutableIndexSet alloc] init];
        for(NSUInteger i = 0; i < draggedItemsCount; ++i) {
            NSInteger row = [_outlineView rowForItem:[_draggedItems objectAtIndex:i]];
            if (row < 0)
                continue;

            [selectedIndexes addIndex:row];
        }

        if ([selectedIndexes count] == 0)
            [selectedIndexes addIndex:[_outlineView rowForItem:targetItem]];

        [_outlineView selectRowIndexes:selectedIndexes byExtendingSelection:NO];

        return YES;
    }

    // try file drop

    // drop on a node itself will append entries at the end
    static_assert(NSOutlineViewDropOnItemIndex == -1, "Expect NSOutlineViewDropOnItemIndex to be -1");

    NSArray *items = [[[VLCMain sharedInstance] playlist] createItemsFromExternalPasteboard:o_pasteboard];
    if (items.count == 0)
        return NO;

    [[[VLCMain sharedInstance] playlist] addPlaylistItems:items
                                         withParentItemId:[targetItem plItemId]
                                                    atPos:index
                                            startPlayback:NO];
    return YES;
}

@end
