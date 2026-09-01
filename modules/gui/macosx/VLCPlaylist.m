/*****************************************************************************
 * VLCPlaylist.m: MacOS X interface module
 *****************************************************************************
* Copyright (C) 2002-2015 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Derk-Jan Hartman <hartman at videola/n dot org>
 *          Benjamin Pracht <bigben at videolan dot org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
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

/* TODO
 * add 'icons' for different types of nodes? (http://www.cocoadev.com/index.pl?IconAndTextInTableCell)
 * reimplement enable/disable item
 */


/*****************************************************************************
 * Preamble
 *****************************************************************************/
#include <stdlib.h>                                      /* malloc(), free() */
#include <sys/param.h>                                    /* for MAXPATHLEN */
#include <string.h>
#include <math.h>
#include <sys/mount.h>

#import "CompatibilityFixes.h"

#import "VLCMain.h"
#import "VLCPlaylist.h"
#import "VLCMainMenu.h"
#import "VLCPlaylistInfo.h"
#import "VLCResumeDialogController.h"
#import "VLCOpenWindowController.h"
#import "VLCMainWindow.h"
#import "VLCSidebarDataSource.h"

#include <vlc_actions.h>
#import <vlc_interface.h>
#include <vlc_services_discovery.h>
#include <vlc_url.h>

static BOOL VLCIsPowerVLCIndexItem(input_item_t *input)
{
    return input && input_item_IsPowerVLCLazyIndex(input);
}

/* Recursive NSOutlineView expansion is quadratic once AppKit has to maintain
 * tens of thousands of row entries, and it is fundamentally unbounded for a
 * lazy media-library node because every expansion requests another index
 * page. Keep the command useful for small, already materialised playlists,
 * but never let it turn a compact database view into the complete UI tree. */
static BOOL VLCPLItemCanExpandRecursively(VLCPLItem *item,
                                          NSUInteger *remaining)
{
    if (!item || !remaining || *remaining == 0)
        return NO;
    --*remaining;
    if (VLCIsPowerVLCIndexItem([item input]))
        return NO;
    for (VLCPLItem *child in [item children])
        if (!VLCPLItemCanExpandRecursively(child, remaining))
            return NO;
    return YES;
}

static BOOL VLCInputIsPowerVLCRandomAction(input_item_t *input)
{
    return input && input_item_IsPowerVLCRandomAction(input);
}

static NSInteger VLCInputPowerVLCIntegerOption(input_item_t *input,
                                                const char *prefix)
{
    if (!input || !prefix)
        return -1;
    const size_t length = strlen(prefix);
    NSInteger value = -1;
    vlc_mutex_lock(&input->lock);
    for (int i = 0; i < input->i_options; ++i) {
        const char *option = input->ppsz_options[i];
        if (!strncmp(option, prefix, length)) {
            char *end = NULL;
            long parsed = strtol(option + length, &end, 10);
            if (end && *end == '\0' && parsed >= 0)
                value = (NSInteger)parsed;
            break;
        }
    }
    vlc_mutex_unlock(&input->lock);
    return value;
}

static BOOL VLCPLItemIsPowerVLCRandomAction(VLCPLItem *item)
{
    return item && VLCInputIsPowerVLCRandomAction([item input]);
}

static unsigned VLCInputRating(input_item_t *input)
{
    char *value = input ? input_item_GetRating(input) : NULL;
    unsigned rating = value ? (unsigned)strtoul(value, NULL, 10) : 0;
    free(value);
    return rating <= 5 ? rating : 0;
}

static void VLCCollectRatingsInItem(VLCPLItem *item,
                                    NSMutableDictionary *ratings)
{
    if (!item || VLCPLItemIsPowerVLCRandomAction(item))
        return;
    if ([[item children] count] > 0) {
        for (VLCPLItem *child in [item children])
            VLCCollectRatingsInItem(child, ratings);
        return;
    }
    input_item_t *input = [item input];
    if (!input || input->i_type != ITEM_TYPE_FILE)
        return;
    char *uri = input_item_GetURI(input);
    char *path = uri ? vlc_uri2path(uri) : NULL;
    if (path) {
        NSString *key = [NSString stringWithUTF8String:path];
        if (key)
            [ratings setObject:@(VLCInputRating(input)) forKey:key];
    }
    free(path);
    free(uri);
}

static const NSInteger VLCPowerVLCRatingMenuTag = 0x50565254;
static const NSInteger VLCPowerVLCPlaylistSeparatorMenuTag = 0x50565030;
static const NSInteger VLCPowerVLCNewPlaylistMenuTag = 0x50565031;
static const NSInteger VLCPowerVLCNewPlaylistFolderMenuTag = 0x50565032;
static const NSInteger VLCPowerVLCRenamePlaylistMenuTag = 0x50565033;
static const NSInteger VLCPowerVLCDeletePlaylistMenuTag = 0x50565034;
static const NSInteger VLCPowerVLCAddToPlaylistMenuTag = 0x50565035;

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

static BOOL VLCPLItemIsUserPlaylistObject(VLCPLItem *item)
{
    return VLCPLItemIsUserPlaylistFolder(item)
        || VLCPLItemIsUserPlaylist(item);
}

static BOOL VLCPLItemIsPowerVLCDeviceStructure(VLCPLItem *item)
{
    return item && input_item_IsPowerVLCDeviceStructure([item input]);
}

static VLCPLItem *VLCFindUserPlaylistsRoot(VLCPLItem *item)
{
    if (!item)
        return nil;
    if (VLCPLItemIsUserPlaylistRoot(item))
        return item;
    for (VLCPLItem *child in [item children]) {
        VLCPLItem *found = VLCFindUserPlaylistsRoot(child);
        if (found)
            return found;
    }
    return nil;
}

static VLCPLItem *VLCPLItemContainingUserPlaylist(VLCPLItem *item)
{
    for (VLCPLItem *cursor = item; cursor; cursor = [cursor parent])
        if (VLCPLItemIsUserPlaylist(cursor))
            return cursor;
    return nil;
}

@interface VLCPlaylist ()
{
    NSImage *_descendingSortingImage;
    NSImage *_ascendingSortingImage;

    BOOL b_selected_item_met;
    BOOL b_isSortDescending;
    NSTableColumn *_sortTableColumn;

    BOOL b_playlistmenu_nib_loaded;

    VLCPLModel *_model;

    /* id -> NSDate of the last expand-to-browse preparse, so a
     * collapse/expand cycle does not re-request a directory while its
     * fetch may still be running — but can retry a failed one */
    NSMutableDictionary *_browseRequestedItemIds;
    BOOL _randomSelectionRetryPending;
    VLCPLItem *_activeRandomAction;
    NSArray *_randomActionAnchorPath;
    BOOL _pendingRandomPlayback;
    int _pendingRandomBranchId;
    BOOL _pendingNodePlayback;
    BOOL _nodePlaybackRetryPending;
    int _pendingNodePlaybackId;
    int _pendingNodeBrowseId;
    int _pendingNodeSelectionId;
    int _pendingNodeSelectionScopeId;
    NSString *_pendingNodeSelectionURI;
    NSArray *_pendingNodeSelectionPath;
    NSUInteger _pendingNodePlaybackRetries;
    NSUInteger _randomSelectionSettleGeneration;

    NSString *_pendingSearchText;
    NSMutableSet *_searchExpandedItemIds;
    NSSet *_searchScopeItemIds;
    NSUInteger _searchGeneration;
    NSUInteger _searchLoadRetries;
    uint64_t _searchBucketMasks[SD_POWERVLC_LIBRARY_VIEW_COUNT];
    NSArray *_searchBranchMatches;
    BOOL _searchUsesMemoryIndex;

    /* Values used while AppKit paints visible rows. Re-resolving the current
     * playlist item and deriving four font variants for every table cell made
     * fast scrolling needlessly expensive in large expanded branches. */
    NSInteger _displayedPlayingItemId;
    NSInteger _displayedPlayingScopeId;
    NSString *_displayedPlayingURI;
    NSFont *_playlistFont;
    NSFont *_playlistBoldFont;
    NSFont *_playlistItalicFont;
    NSFont *_playlistBoldItalicFont;

    // information for playlist table columns menu

    NSDictionary *_translationsForPlaylistTableColumns;
    NSArray *_menuOrderOfPlaylistTableColumns;
}

- (void)saveTableColumns;
- (VLCPLItem *)resolvedCurrentlyPlayingItem;
- (void)playPendingRandomActionIfReady;
- (void)playPendingNodeIfReady;
- (void)schedulePendingNodeRetry;
- (void)revealPendingNodeSelectionIfReady;
- (BOOL)restoreRandomActionAnchorIfNeeded;
- (VLCPLItem *)visibleCounterpartForRandomItem:(VLCPLItem *)item
                              letterToLoad:(VLCPLItem **)letterToLoad;
- (NSDictionary *)selectedPowerVLCRatings;
- (void)updateDisplayedPlayingItem:(VLCPLItem *)item;
@end

@implementation VLCPlaylist

- (void)outlineView:(NSOutlineView *)outlineView
    willDisplayOutlineCell:(id)cell
            forTableColumn:(NSTableColumn *)tableColumn
                      item:(id)item
{
    [cell setTransparent:VLCPLItemIsPowerVLCRandomAction(item)];
}

- (id)init
{
    self = [super init];
    if (self) {
        _ascendingSortingImage = [NSImage imageNamed:@"NSAscendingSortIndicator"];
        _descendingSortingImage = [NSImage imageNamed:@"NSDescendingSortIndicator"];

        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(applicationWillTerminate:) name: NSApplicationWillTerminateNotification object: nil];

        _browseRequestedItemIds = [[NSMutableDictionary alloc] init];
        _pendingRandomBranchId = -1;
        _pendingNodePlaybackId = -1;
        _pendingNodeBrowseId = -1;
        _pendingNodeSelectionId = -1;
        _pendingNodeSelectionScopeId = -1;
        _displayedPlayingItemId = -1;
        _displayedPlayingScopeId = -1;
        _searchExpandedItemIds = [[NSMutableSet alloc] init];


        _translationsForPlaylistTableColumns = [[NSDictionary alloc] initWithObjectsAndKeys:
                                                _NS("Track Number"),  TRACKNUM_COLUMN,
                                                _NS("Title"),         TITLE_COLUMN,
                                                _NS("Author"),        ARTIST_COLUMN,
                                                _NS("Duration"),      DURATION_COLUMN,
                                                _NS("Genre"),         GENRE_COLUMN,
                                                _NS("Album"),         ALBUM_COLUMN,
                                                _NS("Description"),   DESCRIPTION_COLUMN,
                                                _NS("Date"),          DATE_COLUMN,
                                                _NS("Language"),      LANGUAGE_COLUMN,
                                                _NS("URI"),           URI_COLUMN,
                                                _NS("File Size"),     FILESIZE_COLUMN,
                                                nil];
        // this array also assigns tags (index) to type of menu item
        _menuOrderOfPlaylistTableColumns = [[NSArray alloc] initWithObjects: TRACKNUM_COLUMN, TITLE_COLUMN,
                                            ARTIST_COLUMN, DURATION_COLUMN, GENRE_COLUMN, ALBUM_COLUMN,
                                            DESCRIPTION_COLUMN, DATE_COLUMN, LANGUAGE_COLUMN, URI_COLUMN,
                                            FILESIZE_COLUMN,nil];

    }
    return self;
}

static VLCPLItem *VLCFindPlaylistItemById(VLCPLItem *node, int itemId)
{
    if ([node plItemId] == itemId)
        return node;
    for (VLCPLItem *child in [node children]) {
        VLCPLItem *found = VLCFindPlaylistItemById(child, itemId);
        if (found)
            return found;
    }
    return nil;
}

static void VLCCollectPlaylistIds(playlist_item_t *node, NSMutableSet *ids)
{
    if (!node)
        return;
    [ids addObject:[NSNumber numberWithInt:node->i_id]];
    for (int i = 0; i < node->i_children; ++i)
        VLCCollectPlaylistIds(node->pp_children[i], ids);
}

- (NSSet *)protectedSearchItemIds
{
    NSMutableSet *ids = [NSMutableSet set];
    playlist_t *p_playlist = pl_Get(getIntf());
    PL_LOCK;
    playlist_item_t *current = playlist_CurrentPlayingItem(p_playlist);
    playlist_item_t *album = NULL;
    for (playlist_item_t *item = current; item; item = item->p_parent) {
        [ids addObject:[NSNumber numberWithInt:item->i_id]];
        if (!album && item->p_input
         && input_item_IsPowerVLCAlbumScope(item->p_input))
            album = item;
    }
    if (album)
        VLCCollectPlaylistIds(album, ids);
    PL_UNLOCK;
    return ids;
}

- (void)collapsePreviousSearchExpansion
{
    if (![_searchExpandedItemIds count])
        return;
    NSSet *protectedIds = [self protectedSearchItemIds];
    for (NSNumber *itemId in [_searchExpandedItemIds allObjects]) {
        if ([protectedIds containsObject:itemId])
            continue;
        VLCPLItem *item = VLCFindPlaylistItemById([_model rootItem],
                                                  [itemId intValue]);
        if (item && [_outlineView isItemExpanded:item])
            [_outlineView collapseItem:item collapseChildren:NO];
    }
    [_searchExpandedItemIds removeAllObjects];
}

- (NSSet *)currentlyOpenLibraryCategoryIds
{
    NSMutableSet *ids = [NSMutableSet set];
    VLCPLItem *root = [_model rootItem];
    for (VLCPLItem *section in [root children]) {
        if (![_outlineView isItemExpanded:section])
            continue;
        /* User playlists are a top-level section whose children are the
         * actual playlist/folder hierarchy. Opening the section therefore
         * opts the whole hierarchy into search, just as opening a Music
         * category does. Requiring every playlist to be expanded first made
         * tracks in a closed playlist impossible to find. */
        if (VLCPLItemIsUserPlaylistRoot(section)) {
            [ids addObject:[NSNumber numberWithInt:[section plItemId]]];
            continue;
        }
        for (VLCPLItem *category in [section children])
            if ([_outlineView isItemExpanded:category])
                [ids addObject:[NSNumber numberWithInt:[category plItemId]]];
    }
    return ids;
}

- (BOOL)requestSearchLoadingInItem:(VLCPLItem *)item
{
    BOOL pending = NO;
    for (VLCPLItem *child in [item children]) {
        input_item_t *input = [child input];
        BOOL browsable = input
            && !VLCInputIsPowerVLCRandomAction(input)
            && (input->i_type == ITEM_TYPE_DIRECTORY
             || VLCIsPowerVLCIndexItem(input));
        BOOL hasChildren = [[child children] count] > 0;
        if (browsable || hasChildren) {
            if (![_outlineView isItemExpanded:child]) {
                [_searchExpandedItemIds addObject:
                    [NSNumber numberWithInt:[child plItemId]]];
                [_outlineView expandItem:child];
            }
            if (browsable && !hasChildren)
                pending = YES;
        }
        if (hasChildren
         && [self requestSearchLoadingInItem:child])
            pending = YES;
    }
    return pending;
}

- (BOOL)requestSearchScopeLoading
{
    BOOL pending = NO;
    for (NSNumber *scopeId in _searchScopeItemIds) {
        VLCPLItem *scope = VLCFindPlaylistItemById([_model rootItem],
                                                   [scopeId intValue]);
        NSInteger view = VLCInputPowerVLCIntegerOption([scope input],
                         VLC_INPUT_OPTION_POWERVLC_LIBRARY_VIEW_PREFIX);
        if (_searchUsesMemoryIndex && view >= 0
         && view < SD_POWERVLC_LIBRARY_VIEW_COUNT) {
            uint64_t mask = _searchBucketMasks[view];
            for (VLCPLItem *child in [scope children]) {
                NSInteger bucket = VLCInputPowerVLCIntegerOption([child input],
                               VLC_INPUT_OPTION_POWERVLC_LIBRARY_BUCKET_PREFIX);
                if (bucket < 0 || bucket >= 64
                 || !(mask & (UINT64_C(1) << bucket)))
                    continue;
                BOOL hasChildren = [[child children] count] > 0;
                if (![_outlineView isItemExpanded:child]) {
                    [_searchExpandedItemIds addObject:
                        [NSNumber numberWithInt:[child plItemId]]];
                    [_outlineView expandItem:child];
                }
                if (!hasChildren)
                    pending = YES;
                if (!hasChildren)
                    continue;

                /* The service returns exact group/album paths from its
                 * in-memory metadata index. Expand only those paths instead
                 * of recursively materialising every artist and album in a
                 * matching letter. This is the difference between a handful
                 * of rows and tens of thousands on a G3. */
                for (NSDictionary *match in _searchBranchMatches) {
                    if ([[match objectForKey:@"view"] integerValue] != view
                     || [[match objectForKey:@"bucket"] integerValue] != bucket)
                        continue;
                    NSString *primaryName = [match objectForKey:@"primary"];
                    VLCPLItem *primary = nil;
                    for (VLCPLItem *candidate in [child children]) {
                        if (VLCPLItemIsPowerVLCRandomAction(candidate))
                            continue;
                        char *nameValue = input_item_GetName([candidate input]);
                        NSString *name = nameValue
                            ? [NSString stringWithUTF8String:nameValue] : @"";
                        free(nameValue);
                        if ([name caseInsensitiveCompare:primaryName]
                                                            == NSOrderedSame) {
                            primary = candidate;
                            break;
                        }
                    }
                    if (!primary)
                        continue;
                    BOOL primaryLoaded = [[primary children] count] > 0;
                    if (![_outlineView isItemExpanded:primary]) {
                        [_searchExpandedItemIds addObject:
                            [NSNumber numberWithInt:[primary plItemId]]];
                        [_outlineView expandItem:primary];
                    }
                    if (!primaryLoaded) {
                        pending = YES;
                        continue;
                    }
                    /* Albums view ends at the primary node. The other grouped
                     * views add one album level below artist/genre/year. */
                    if (view == 2)
                        continue;
                    NSString *albumName = [match objectForKey:@"secondary"];
                    for (VLCPLItem *album in [primary children]) {
                        if (VLCPLItemIsPowerVLCRandomAction(album))
                            continue;
                        char *nameValue = input_item_GetName([album input]);
                        NSString *name = nameValue
                            ? [NSString stringWithUTF8String:nameValue] : @"";
                        free(nameValue);
                        if ([name caseInsensitiveCompare:albumName]
                                                            != NSOrderedSame)
                            continue;
                        BOOL albumLoaded = [[album children] count] > 0;
                        if (![_outlineView isItemExpanded:album]) {
                            [_searchExpandedItemIds addObject:
                                [NSNumber numberWithInt:[album plItemId]]];
                            [_outlineView expandItem:album];
                        }
                        if (!albumLoaded)
                            pending = YES;
                        break;
                    }
                }
            }
        } else if ([self requestSearchLoadingInItem:scope]) {
            /* User playlists are not partitioned by the music index and use
             * the generic lazy traversal. They are normally shallow. */
            pending = YES;
        }
    }
    return pending;
}

- (void)expandSearchMatchesInItem:(VLCPLItem *)item
{
    if (!item || ![[item children] count])
        return;
    if (![_outlineView isItemExpanded:item]) {
        [_searchExpandedItemIds addObject:
            [NSNumber numberWithInt:[item plItemId]]];
        [_outlineView expandItem:item];
    }
    for (VLCPLItem *child in [item children])
        [self expandSearchMatchesInItem:child];
}

- (void)finishLibrarySearchForGeneration:(NSNumber *)generation
{
    if ([generation unsignedIntegerValue] != _searchGeneration)
        return;
    BOOL pending = [self requestSearchScopeLoading];
    if (pending && _searchLoadRetries++ < 800) {
        [self performSelector:@selector(finishLibrarySearchForGeneration:)
                   withObject:generation afterDelay:0.15];
        return;
    }
    [_model searchUpdate:_pendingSearchText withinItemIds:_searchScopeItemIds];
    for (NSNumber *scopeId in _searchScopeItemIds) {
        VLCPLItem *scope = VLCFindPlaylistItemById([_model rootItem],
                                                   [scopeId intValue]);
        [self expandSearchMatchesInItem:scope];
    }
}

- (void)applyDebouncedSearch
{
    _searchGeneration++;
    NSNumber *generation = [NSNumber numberWithUnsignedInteger:_searchGeneration];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                              selector:@selector(finishLibrarySearchForGeneration:)
                                                object:nil];
    [_model searchUpdate:@"" withinItemIds:nil];
    [self collapsePreviousSearchExpansion];
    if (![_pendingSearchText length]) {
        _searchScopeItemIds = nil;
        _searchBranchMatches = nil;
        return;
    }
    if (![_model isPowerVLCLibraryRoot]) {
        [_model searchUpdate:_pendingSearchText];
        return;
    }
    NSSet *openScopes = [self currentlyOpenLibraryCategoryIds];
    /* A no-result filter leaves an opened category with no visible children,
     * which makes AppKit report it as no longer expanded. Preserve precisely
     * those prior scopes so the next query can find results without requiring
     * a manual close/reopen cycle. */
    if ([_searchScopeItemIds count]) {
        NSMutableSet *continued = [NSMutableSet setWithSet:openScopes];
        for (NSNumber *scopeId in _searchScopeItemIds) {
            VLCPLItem *scope = VLCFindPlaylistItemById([_model rootItem],
                                                       [scopeId intValue]);
            if (scope && [[scope children] count] == 0)
                [continued addObject:scopeId];
        }
        openScopes = continued;
    }
    _searchScopeItemIds = openScopes;
    memset(_searchBucketMasks, 0, sizeof(_searchBucketMasks));
    services_discovery_library_search_t request = {
        .psz_query = [_pendingSearchText UTF8String],
        .i_view_mask = 0,
    };
    for (NSNumber *scopeId in _searchScopeItemIds) {
        VLCPLItem *scope = VLCFindPlaylistItemById([_model rootItem],
                                                   [scopeId intValue]);
        NSInteger view = VLCInputPowerVLCIntegerOption([scope input],
                         VLC_INPUT_OPTION_POWERVLC_LIBRARY_VIEW_PREFIX);
        if (view >= 0 && view < SD_POWERVLC_LIBRARY_VIEW_COUNT)
            request.i_view_mask |= UINT64_C(1) << view;
    }
    _searchUsesMemoryIndex = request.i_view_mask != 0
        && playlist_ServicesDiscoveryControl(pl_Get(getIntf()),
            "powervlc_library", SD_CMD_POWERVLC_LIBRARY_SEARCH, &request)
           == VLC_SUCCESS;
    if (_searchUsesMemoryIndex)
    {
        memcpy(_searchBucketMasks, request.p_bucket_masks,
               sizeof(_searchBucketMasks));
        NSMutableArray *matches = [NSMutableArray arrayWithCapacity:
                                                    request.i_match_count];
        for (size_t i = 0; i < request.i_match_count; ++i) {
            services_discovery_library_match_t *match = &request.p_matches[i];
            NSString *primary = match->psz_primary
                ? [NSString stringWithUTF8String:match->psz_primary] : @"";
            NSString *secondary = match->psz_secondary
                ? [NSString stringWithUTF8String:match->psz_secondary] : @"";
            [matches addObject:@{ @"view": @(match->i_view),
                                  @"bucket": @(match->i_bucket),
                                  @"primary": primary ?: @"",
                                  @"secondary": secondary ?: @"" }];
            free(match->psz_primary); free(match->psz_secondary);
        }
        free(request.p_matches);
        _searchBranchMatches = [matches copy];
    }
    else
        _searchBranchMatches = nil;
    _searchLoadRetries = 0;
    [self finishLibrarySearchForGeneration:generation];
}

- (void)searchUpdate:(NSString *)searchText
{
    NSString *trimmed = [searchText stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    _pendingSearchText = [trimmed copy];
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                              selector:@selector(applyDebouncedSearch)
                                                object:nil];
    [self performSelector:@selector(applyDebouncedSearch)
               withObject:nil afterDelay:0.35];
}

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *columnArray = [[NSMutableArray alloc] init];
    [columnArray addObject: [NSArray arrayWithObjects:TITLE_COLUMN, [NSNumber numberWithFloat:190.], nil]];
    [columnArray addObject: [NSArray arrayWithObjects:ARTIST_COLUMN, [NSNumber numberWithFloat:95.], nil]];
    [columnArray addObject: [NSArray arrayWithObjects:DURATION_COLUMN, [NSNumber numberWithFloat:95.], nil]];

    NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSArray arrayWithArray:columnArray], @"PlaylistColumnSelection", nil];

    [defaults registerDefaults:appDefaults];
}

- (VLCPLModel *)model
{
    return _model;
}

- (void)reloadStyles
{
    CGFloat rowHeight;
    if (var_InheritBool(getIntf(), "macosx-large-text")) {
        _playlistFont = [NSFont systemFontOfSize:13.];
        rowHeight = 21.;
    } else {
        _playlistFont = [NSFont systemFontOfSize:11.];
        rowHeight = 16.;
    }

    NSFontManager *fontManager = [NSFontManager sharedFontManager];
    _playlistFont = [fontManager convertFont:_playlistFont
        toNotHaveTrait:NSBoldFontMask | NSItalicFontMask];
    _playlistBoldFont = [fontManager convertFont:_playlistFont
                                     toHaveTrait:NSBoldFontMask];
    _playlistItalicFont = [fontManager convertFont:_playlistFont
                                       toHaveTrait:NSItalicFontMask];
    _playlistBoldItalicFont = [fontManager convertFont:_playlistBoldFont
                                           toHaveTrait:NSItalicFontMask];

    NSArray *columns = [_outlineView tableColumns];
    NSUInteger count = columns.count;
    for (NSUInteger x = 0; x < count; x++)
        [[[columns objectAtIndex:x] dataCell] setFont:_playlistFont];
    [_outlineView setRowHeight:rowHeight];
}

- (void)awakeFromNib
{
    // This is only called for the playlist popup menu
    [self initStrings];
}

- (void)setOutlineView:(VLCPlaylistView * __nullable)outlineView
{
    _outlineView = outlineView;
    [_outlineView setDelegate:self];

    playlist_t * p_playlist = pl_Get(getIntf());

    _model = [[VLCPLModel alloc] initWithOutlineView:_outlineView playlist:p_playlist rootItem:p_playlist->p_playing];
    [_outlineView setDataSource:_model];
    [_outlineView reloadData];

    [_outlineView setTarget: self];
    [_outlineView setDoubleAction: @selector(playItem:)];

    [_outlineView setAllowsEmptySelection: NO];
    [_outlineView registerForDraggedTypes:@[NSFilenamesPboardType,
                                             NSURLPboardType,
                                             @"VLCPlaylistItemPboardType"]];
    [_outlineView setIntercellSpacing: NSMakeSize (0.0, 1.0)];

    [self reloadStyles];
}

- (void)setPlaylistHeaderView:(NSTableHeaderView * __nullable)playlistHeaderView
{
    VLCMainMenu *mainMenu = [[VLCMain sharedInstance] mainMenu];
    _playlistHeaderView = playlistHeaderView;

    // Setup playlist table column selection for both context and main menu
    NSMenu *contextMenu = [[NSMenu alloc] init];
    [self setupPlaylistTableColumnsForMenu:contextMenu];
    [_playlistHeaderView setMenu:contextMenu];
    [self setupPlaylistTableColumnsForMenu:[[[VLCMain sharedInstance] mainMenu] playlistTableColumnsMenu]];

    NSArray *columnArray = [[NSUserDefaults standardUserDefaults] arrayForKey:@"PlaylistColumnSelection"];

    BOOL hasTitleItem = NO;

    for (NSArray *column in columnArray) {
        NSString *columnName = [column objectAtIndex:0];
        NSNumber *columnWidth = [column objectAtIndex:1];

        if ([columnName isEqualToString:STATUS_COLUMN])
            continue;

        // Memorize if we custom set always-enabled title item
        if ([columnName isEqualToString:TITLE_COLUMN]) {
            hasTitleItem = YES;
        }

        if(![self setPlaylistColumnTableState: NSOnState forColumn:columnName])
            continue;

        [[_outlineView tableColumnWithIdentifier:columnName] setWidth:[columnWidth floatValue]];
    }

    // Set the always enabled title item if not already done
    if (!hasTitleItem)
        [self setPlaylistColumnTableState:NSOnState forColumn:TITLE_COLUMN];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    /* let's make sure we save the correct widths and positions, since this likely changed since the last time the user played with the column selection */
    [self saveTableColumns];
}

- (void)initStrings
{
    [_playPlaylistMenuItem setTitle: _NS("Play")];
    [_deletePlaylistMenuItem setTitle: _NS("Delete")];
    [_recursiveExpandPlaylistMenuItem setTitle: _NS("Expand All")];
    [_recursiveCollapsePlaylistMenuItem setTitle: _NS("Collapse All")];
    [_selectAllPlaylistMenuItem setTitle: _NS("Select All")];
    [_infoPlaylistMenuItem setTitle: _NS("Media Information...")];
    [_revealInFinderPlaylistMenuItem setTitle: _NS("Reveal in Finder")];
    [_addFilesToPlaylistMenuItem setTitle: _NS("Add File...")];
    [_shufflePlaylistMenuItem setTitle: _NS("Shuffle playlist")];
}

- (void)playlistUpdated
{
    BOOL wasResolvingRandom = _pendingRandomPlayback || _activeRandomAction;
    [_outlineView reloadData];
    /* A lazy letter requested while following a Random action arrives through
     * playlist append callbacks. Retry the URI lookup as its nodes appear. */
    /* Loading a lazy Random branch inserts rows above the user's current
     * selection. Both NSOutlineView and VLCPLModel can otherwise restore the
     * preceding playing track (for example Charles Trenet while resolving a
     * Charles Pasi action), producing a visible detour. Anchor every
     * intermediate refresh to the exact Random row that was invoked. */
    if (wasResolvingRandom)
        [self restoreRandomActionAnchorIfNeeded];
    [self playPendingRandomActionIfReady];
    [self playPendingNodeIfReady];
    [self revealPendingNodeSelectionIfReady];
    if (wasResolvingRandom)
        [self currentlyPlayingItemChanged];
}

- (void)playbackModeUpdated
{
    [_model playbackModeUpdated];
}


- (BOOL)isSelectionEmpty
{
    return [_outlineView selectedRow] == -1;
}

- (BOOL)restoreRandomActionAnchorIfNeeded
{
    if (!_activeRandomAction)
        return NO;
    VLCPLItem *anchor = nil;
    if ([_randomActionAnchorPath count]) {
        VLCPLItem *cursor = [_model rootItem];
        for (NSString *component in _randomActionAnchorPath) {
            VLCPLItem *match = nil;
            for (VLCPLItem *child in [cursor children]) {
                char *name = input_item_GetName([child input]);
                BOOL same = name
                    && [component isEqualToString:
                        [NSString stringWithUTF8String:name]];
                free(name);
                if (same) {
                    match = child;
                    break;
                }
            }
            if (!match)
                return NO;
            cursor = match;
        }
        anchor = cursor;
    } else
        anchor = VLCFindPlaylistItemById([_model rootItem],
                                         [_activeRandomAction plItemId]);
    NSInteger row = anchor ? [_outlineView rowForItem:anchor] : -1;
    if (row >= 0) {
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                  byExtendingSelection:NO];
        return YES;
    }
    return NO;
}

- (BOOL)restoreRandomActionSelection
{
    return [self restoreRandomActionAnchorIfNeeded];
}

- (void)currentlyPlayingItemChanged
{
    VLCPLItem *item = [self resolvedCurrentlyPlayingItem];
    if (!item)
        return;

    /* Random resolution can briefly expose the previous current item or an
     * intermediate private-tree node before playPendingRandomActionIfReady:
     * has recorded the canonical visible path.  Navigating to that temporary
     * item produces a visible scroll/highlight detour (notably from an artist
     * Random action).  Wait for the exact pending path; the reveal method
     * below will perform the sole selection and scroll. */
    if ((_pendingRandomPlayback || _activeRandomAction)
     && _pendingNodeSelectionId < 0)
        return;

    /* A navigation-node double click starts the core item before the lazy
     * visible path has necessarily finished loading.  Selecting the first
     * equal occurrence here makes the outline jump to another category for
     * one refresh, then jump back when revealPendingNodeSelectionIfReady:
     * resolves the requested album.  Keep the user's viewport stable until
     * that exact scoped occurrence is available. */
    if (_pendingNodeSelectionId >= 0) {
        [self revealPendingNodeSelectionIfReady];
        return;
    }

    [self updateDisplayedPlayingItem:item];

    VLCPLItem *letterToLoad = nil;
    VLCPLItem *visibleItem =
        [self visibleCounterpartForRandomItem:item letterToLoad:&letterToLoad];
    if (visibleItem) {
        item = visibleItem;
        /* Playback can start before the normal letter -> artist -> album
         * branch has been materialised. Keep the action alive while every
         * lazy tree-update settles: the model can momentarily expose the leaf
         * and then rebuild/collapse the branch from its saved state. A later
         * explicit click replaces this action, while retaining it here lets
         * append callbacks reopen the exact branch and restore the bold row. */
    } else if (letterToLoad) {
        /* The private Random subtree must never be unfolded in the UI. Open
         * its normal letter sibling instead; the append callback above will
         * retry until the matching track URI is available. */
        [_outlineView expandItem:letterToLoad];
        return;
    }
    [self updateDisplayedPlayingItem:item];

    // Search for item row for selection
    NSInteger itemIndex = [_outlineView rowForItem:item];
    if (itemIndex < 0) {
        // Expand if needed. This must be done from root to child
        // item in order to work
        NSMutableArray *itemsToExpand = [NSMutableArray array];
        VLCPLItem *tmpItem = [item parent];
        while (tmpItem != nil) {
            [itemsToExpand addObject:tmpItem];
            tmpItem = [tmpItem parent];
        }

        for(int i = itemsToExpand.count - 1; i >= 0; i--) {
            VLCPLItem *currentItem = [itemsToExpand objectAtIndex:i];
            [_outlineView expandItem: currentItem];
        }
    }

    // Update highlight for currently playing item
    [_outlineView reloadData];

    // Search for row again
    itemIndex = [_outlineView rowForItem:item];
    if (itemIndex < 0) {
        return;
    }

    [_outlineView selectRowIndexes: [NSIndexSet indexSetWithIndex: itemIndex] byExtendingSelection: NO];
    [_outlineView scrollRowToVisible: itemIndex];
}

- (void)updateDisplayedPlayingItem:(VLCPLItem *)item
{
    _displayedPlayingItemId = item ? [item plItemId] : -1;
    _displayedPlayingScopeId = -1;
    _displayedPlayingURI = nil;
    if (!item)
        return;

    VLCPLItem *random = [item parent];
    while (random && !VLCPLItemIsPowerVLCRandomAction(random))
        random = [random parent];
    VLCPLItem *scope = random ? [random parent]
                              : (_activeRandomAction
                                 ? [_activeRandomAction parent] : nil);
    if (!scope)
        return;
    _displayedPlayingScopeId = [scope plItemId];
    char *uri = input_item_GetURI([item input]);
    if (uri) {
        _displayedPlayingURI = [NSString stringWithUTF8String:uri];
        free(uri);
    }
}

- (void)scheduleRandomSelectionRetry
{
    /* Ordinary playlist edits also emit append notifications. They must keep
     * the user's current selection and scroll position instead of jumping to
     * the playing row. Only a Random action needs this delayed retry. */
    if (!_pendingRandomPlayback && !_activeRandomAction)
        return;
    if (_randomSelectionRetryPending)
        return;
    _randomSelectionRetryPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        _randomSelectionRetryPending = NO;
        /* Lazy XSPF Random actions arrive through append callbacks rather
         * than a full playlist reload. Start playback as soon as their first
         * playable descendant has been parsed. */
        [self playPendingRandomActionIfReady];
        [self currentlyPlayingItemChanged];
    });
}

static BOOL VLCInputItemsHaveSameURI(input_item_t *a, input_item_t *b)
{
    char *aURI = a ? input_item_GetURI(a) : NULL;
    char *bURI = b ? input_item_GetURI(b) : NULL;
    BOOL same = aURI && bURI && !strcmp(aURI, bURI);
    free(aURI); free(bURI);
    return same;
}

static BOOL VLCPlaylistItemsHaveSameURI(VLCPLItem *a, VLCPLItem *b)
{
    return VLCInputItemsHaveSameURI(a ? [a input] : NULL,
                                    b ? [b input] : NULL);
}

static VLCPLItem *VLCFindItemWithURIString(VLCPLItem *node,
                                           const char *wantedURI)
{
    if (!node || !wantedURI)
        return nil;
    char *uri = input_item_GetURI([node input]);
    BOOL same = uri && !strcmp(uri, wantedURI);
    free(uri);
    if (same)
        return node;
    for (VLCPLItem *child in [node children]) {
        VLCPLItem *match = VLCFindItemWithURIString(child, wantedURI);
        if (match)
            return match;
    }
    return nil;
}

static VLCPLItem *VLCFindVisibleItemWithURIString(VLCPLItem *node,
                                                   const char *wantedURI)
{
    if (!node || !wantedURI)
        return nil;
    if (!VLCPLItemIsPowerVLCRandomAction(node)) {
        char *uri = input_item_GetURI([node input]);
        BOOL same = uri && !strcmp(uri, wantedURI);
        free(uri);
        if (same)
            return node;
        for (VLCPLItem *child in [node children]) {
            VLCPLItem *match = VLCFindVisibleItemWithURIString(child,
                                                               wantedURI);
            if (match)
                return match;
        }
    }
    return nil;
}

- (void)schedulePendingNodeRetry
{
    if (!_pendingNodePlayback || _nodePlaybackRetryPending)
        return;
    if (_pendingNodePlaybackRetries++ >= 800) {
        _pendingNodePlayback = NO;
        _pendingNodePlaybackId = -1;
        _pendingNodeBrowseId = -1;
        return;
    }
    _nodePlaybackRetryPending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 150 * NSEC_PER_MSEC),
                   dispatch_get_main_queue(), ^{
        _nodePlaybackRetryPending = NO;
        [self playPendingNodeIfReady];
    });
}

- (void)revealPendingNodeSelectionIfReady
{
    if (_pendingNodeSelectionId < 0)
        return;
    /* The core leaf used for playback can be a private occurrence created by
     * a compact-index XSPF. Prefer the matching URI below the node that the
     * user actually double-clicked, otherwise an equal hidden occurrence can
     * keep rowForItem: at -1 and leave only the first chevron expanded. */
    VLCPLItem *scope = VLCFindPlaylistItemById([_model rootItem],
                                                _pendingNodeSelectionScopeId);
    VLCPLItem *item = nil;
    if (scope && [_pendingNodeSelectionPath count]) {
        VLCPLItem *cursor = scope;
        NSUInteger componentIndex = 0;
        for (NSString *component in _pendingNodeSelectionPath) {
            /* Expanding each visible counterpart requests the next compact
             * index level. Its append callback will retry this method. */
            [_outlineView expandItem:cursor];
            VLCPLItem *match = nil;
            for (VLCPLItem *child in [cursor children]) {
                if (VLCPLItemIsPowerVLCRandomAction(child))
                    continue;
                char *name = input_item_GetName([child input]);
                BOOL same = name
                    && [component isEqualToString:[NSString stringWithUTF8String:name]];
                free(name);
                if (same) {
                    match = child;
                    break;
                }
            }
            if (!match) {
                [self restoreRandomActionAnchorIfNeeded];
                return;
            }
            cursor = match;
            if (++componentIndex < [_pendingNodeSelectionPath count])
                [_outlineView expandItem:cursor];
        }
        item = cursor;
    }
    if (!item && ![_pendingNodeSelectionPath count]
     && [_pendingNodeSelectionURI length])
        item = VLCFindVisibleItemWithURIString(scope,
                         [_pendingNodeSelectionURI UTF8String]);
    if (!item && ![_pendingNodeSelectionPath count]
     && ![_pendingNodeSelectionURI length])
        item = VLCFindPlaylistItemById([_model rootItem],
                                       _pendingNodeSelectionId);
    if (!item) {
        [self restoreRandomActionAnchorIfNeeded];
        return;
    }

    /* The input can start before the final playlist-append callback creates
     * its Cocoa wrapper. Once it exists, reuse the canonical current-item
     * path expansion so the exact occurrence is selected and bold. */
    NSMutableArray *path = [NSMutableArray array];
    for (VLCPLItem *cursor = [item parent]; cursor;
         cursor = [cursor parent])
        [path insertObject:cursor atIndex:0];
    for (VLCPLItem *cursor in path)
        [_outlineView expandItem:cursor];
    [_outlineView reloadData];
    NSInteger row = [_outlineView rowForItem:item];
    if (row >= 0) {
        [self updateDisplayedPlayingItem:item];
        [_outlineView reloadData];
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                  byExtendingSelection:NO];
        [_outlineView scrollRowToVisible:row];
        /* A successful reveal is not necessarily the final model callback.
         * Compact-index branches may append one last sibling immediately
         * afterwards. VLCPLModel then tries to restore the selection saved
         * before that append, which used to make a new Random action flash
         * the preceding action's track (for example N while resolving M).
         * Keep the pending path authoritative until the lazy branch has been
         * quiet for a short settling window. Every later reveal restarts the
         * window; an explicit user action invalidates it in playItem:. */
        NSUInteger settleGeneration = ++_randomSelectionSettleGeneration;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                       dispatch_get_main_queue(), ^{
            if (settleGeneration != _randomSelectionSettleGeneration)
                return;
            _pendingNodeSelectionId = -1;
            _pendingNodeSelectionScopeId = -1;
            _pendingNodeSelectionURI = nil;
            _pendingNodeSelectionPath = nil;
            _activeRandomAction = nil;
            _randomActionAnchorPath = nil;
        });
    } else
        [self restoreRandomActionAnchorIfNeeded];
}

- (void)playPendingNodeIfReady
{
    if (!_pendingNodePlayback || _pendingNodePlaybackId < 0)
        return;

    int playedId = -1;
    BOOL retry = NO;
    intf_thread_t *p_intf = getIntf();
    if (!p_intf) {
        _pendingNodePlayback = NO;
        return;
    }

    /* Follow the model presented by Cocoa. The compact database keeps its
     * insertion order internally, which is not necessarily the alphabetical
     * and track-number order visible to the user. */
    VLCPLItem *visibleRoot = VLCFindPlaylistItemById([_model rootItem],
                                                      _pendingNodePlaybackId);
    if (!visibleRoot) {
        _pendingNodePlayback = NO;
        _pendingNodePlaybackId = -1;
        _pendingNodeBrowseId = -1;
        return;
    }

    VLCPLItem *visibleCursor = visibleRoot;
    while (visibleCursor) {
        [_outlineView expandItem:visibleCursor];
        VLCPLItem *next = nil;
        for (VLCPLItem *candidate in [visibleCursor children]) {
            if (!VLCPLItemIsPowerVLCRandomAction(candidate)) {
                next = candidate;
                break;
            }
        }
        if (next) {
            visibleCursor = next;
            continue;
        }

        playlist_t *p_playlist = pl_Get(p_intf);
        PL_LOCK;
        playlist_item_t *root = playlist_ItemGetById(p_playlist,
                                                      _pendingNodePlaybackId);
        playlist_item_t *cursor = playlist_ItemGetById(p_playlist,
                                                [visibleCursor plItemId]);
        if (!root || !cursor) {
            _pendingNodePlayback = NO;
            _pendingNodePlaybackId = -1;
            _pendingNodeBrowseId = -1;
            PL_UNLOCK;
            return;
        }

        BOOL browsable = cursor->p_input
            && (cursor->p_input->i_type == ITEM_TYPE_DIRECTORY
             || VLCIsPowerVLCIndexItem(cursor->p_input));
        if (browsable) {
            int browseId = cursor->i_id;
            NSNumber *itemId = @(browseId);
            NSDate *lastRequest = [_browseRequestedItemIds objectForKey:itemId];
            if (_pendingNodeBrowseId != browseId
             && (!lastRequest || [lastRequest timeIntervalSinceNow] <= -150.0)) {
                _pendingNodeBrowseId = browseId;
                [_browseRequestedItemIds setObject:[NSDate date] forKey:itemId];
                input_item_meta_request_option_t options =
                    META_REQUEST_OPTION_SCOPE_ANY;
                if (VLCIsPowerVLCIndexItem(cursor->p_input))
                    options |= META_REQUEST_OPTION_NO_ART;
                libvlc_MetadataRequest(p_intf->obj.libvlc, cursor->p_input,
                                       options, 120000, cursor);
            }
            retry = YES;
        } else if (cursor != root) {
            playedId = cursor->i_id;
            _pendingNodeSelectionId = playedId;
            _pendingNodeSelectionScopeId = root->i_id;
            NSMutableArray *path = [NSMutableArray array];
            for (VLCPLItem *pathItem = visibleCursor;
                 pathItem && pathItem != visibleRoot;
                 pathItem = [pathItem parent]) {
                char *name = input_item_GetName([pathItem input]);
                if (name) {
                    [path insertObject:[NSString stringWithUTF8String:name]
                               atIndex:0];
                    free(name);
                }
            }
            _pendingNodeSelectionPath = [path copy];
            char *uri = input_item_GetURI(cursor->p_input);
            _pendingNodeSelectionURI = uri
                ? [NSString stringWithUTF8String:uri] : nil;
            free(uri);
            _pendingNodePlayback = NO;
            _pendingNodePlaybackId = -1;
            _pendingNodeBrowseId = -1;
            /* A navigation node chooses an album, but playback and Next stay
             * inside that album. */
            playlist_item_t *album = cursor->p_parent;
            while (album && album != root
                && (!album->p_input
                 || !input_item_IsPowerVLCAlbumScope(album->p_input)))
                album = album->p_parent;
            playlist_ViewPlay(p_playlist,
                              album && album != root ? album : root, cursor);
        } else {
            _pendingNodePlayback = NO;
            _pendingNodePlaybackId = -1;
            _pendingNodeBrowseId = -1;
        }
        PL_UNLOCK;
        break;
    }

    if (retry)
        [self schedulePendingNodeRetry];
    else if (playedId >= 0) {
        [self currentlyPlayingItemChanged];
        [self performSelector:@selector(revealPendingNodeSelectionIfReady)
                   withObject:nil afterDelay:0.15];
    }
}

- (void)playPendingRandomActionIfReady
{
    if (!_pendingRandomPlayback || !_activeRandomAction)
        return;
    playlist_t *p_playlist = pl_Get(getIntf());
    PL_LOCK;
    playlist_item_t *action = playlist_ItemGetById(
        p_playlist, [_activeRandomAction plItemId]);
    playlist_powervlc_random_result_t resolved;
    int previousBranch = _pendingRandomBranchId;
    playlist_PowerVLCRandomResolve(p_playlist, action, previousBranch,
                                   &resolved);
    _pendingRandomBranchId = resolved.i_branch_id;
    if (resolved.p_browse && previousBranch != resolved.i_branch_id) {
        libvlc_MetadataRequest(getIntf()->obj.libvlc,
                               resolved.p_browse->p_input,
                               META_REQUEST_OPTION_SCOPE_ANY, 120000,
                               resolved.p_browse);
    }
    if (resolved.p_track) {
        _pendingRandomPlayback = NO;
        _pendingRandomBranchId = -1;
        /* Keep _activeRandomAction until currentlyPlayingItemChanged: has
         * loaded and selected the canonical visible counterpart.  The
         * private Random path is the only stable description of the chosen
         * letter/artist/album while those lazy nodes are still absent. */
        _pendingNodeSelectionId = resolved.p_track->i_id;
        _pendingNodeSelectionScopeId = action->p_parent
                                     ? action->p_parent->i_id : -1;
        NSMutableArray *selectionPath = [NSMutableArray array];
        for (playlist_item_t *cursor = resolved.p_track;
             cursor && cursor != action->p_parent;
             cursor = cursor->p_parent) {
            if (!cursor->p_input
             || input_item_IsPowerVLCRandomAction(cursor->p_input))
                continue;
            char *name = input_item_GetName(cursor->p_input);
            if (name) {
                [selectionPath insertObject:
                    [NSString stringWithUTF8String:name] atIndex:0];
                free(name);
            }
        }
        _pendingNodeSelectionPath = [selectionPath copy];
        char *selectionURI = input_item_GetURI(resolved.p_track->p_input);
        _pendingNodeSelectionURI = selectionURI
            ? [NSString stringWithUTF8String:selectionURI] : nil;
        free(selectionURI);
        playlist_ViewPlay(p_playlist, resolved.p_scope, resolved.p_track);
    } else if (!resolved.p_browse) {
        _pendingRandomPlayback = NO;
        _pendingRandomBranchId = -1;
        _activeRandomAction = nil;
        _randomActionAnchorPath = nil;
    }
    PL_UNLOCK;
    if (_pendingRandomPlayback)
        [self scheduleRandomSelectionRetry];
    else if (resolved.p_track)
        [self scheduleRandomSelectionRetry];
}

- (VLCPLItem *)resolvedCurrentlyPlayingItem
{
    VLCPLItem *item = [[self model] currentlyPlayingItem];
    if (!_activeRandomAction)
        return item;

    char *currentURI = item ? input_item_GetURI([item input]) : NULL;
    if (!currentURI) {
        playlist_t *p_playlist = pl_Get(getIntf());
        PL_LOCK;
        playlist_item_t *current = playlist_CurrentPlayingItem(p_playlist);
        if (current && current->p_input)
            currentURI = input_item_GetURI(current->p_input);
        PL_UNLOCK;
    }
    VLCPLItem *privateItem =
        VLCFindItemWithURIString(_activeRandomAction, currentURI);
    free(currentURI);
    return privateItem ?: item;
}

static VLCPLItem *VLCFindVisibleItemWithURI(VLCPLItem *node,
                                            VLCPLItem *wanted)
{
    for (VLCPLItem *child in [node children]) {
        if (VLCPLItemIsPowerVLCRandomAction(child))
            continue;
        if (VLCPlaylistItemsHaveSameURI(child, wanted))
            return child;
        VLCPLItem *match = VLCFindVisibleItemWithURI(child, wanted);
        if (match)
            return match;
    }
    return nil;
}

- (VLCPLItem *)visibleCounterpartForRandomItem:(VLCPLItem *)item
                                  letterToLoad:(VLCPLItem **)letterToLoad
{
    NSMutableArray *privatePath = [NSMutableArray array];
    VLCPLItem *ancestor = [item parent];
    while (ancestor &&
           !VLCPLItemIsPowerVLCRandomAction(ancestor)) {
        [privatePath insertObject:ancestor atIndex:0];
        ancestor = [ancestor parent];
    }
    if (!ancestor)
        return item; /* ordinary playback, not a Random action */

    VLCPLItem *view = [ancestor parent];
    if (!view)
        return nil;

    /* A Random node embedded in a lazy letter/artist/album already has its
     * visible siblings in this exact parent.  Resolve there first.  Looking
     * by URI from the media-library root can select an identical copy under
     * another expanded view (Composers, Tracks, Recently Added...). */
    /* An embedded Random action (the one directly inside an already-visible
     * album) has no private category path, so a URI lookup in that album is
     * both exact and cheap.  A top-level Random action is different: its
     * private XSPF deliberately carries letter -> artist -> album.  Searching
     * the whole view by URI before following that path can select the first
     * duplicate occurrence already materialised under an unrelated artist.
     * This made F-Zero play correctly while the outline unfolded
     * "PeeWee and Michiko Hill".  Preserve the scoped shortcut only for the
     * path-less embedded action; top-level actions must resolve every named
     * ancestor before matching the leaf URI. */
    if ([privatePath count] == 0) {
        VLCPLItem *scopedMatch = VLCFindVisibleItemWithURI(view, item);
        if (scopedMatch)
            return scopedMatch;
    }

    /* The private path of a top-level action is, for example,
     * A -> album artist -> album -> track.  Walk the corresponding visible
     * path one component at a time.  If a lazy component is not populated
     * yet, expand precisely that component and retry after its append event. */
    VLCPLItem *visibleParent = view;
    for (VLCPLItem *privateNode in privatePath) {
        char *wantedTitle = input_item_GetTitleFbName([privateNode input]);
        VLCPLItem *visibleNode = nil;
        for (VLCPLItem *candidate in [visibleParent children]) {
            if (candidate == ancestor ||
                VLCPLItemIsPowerVLCRandomAction(candidate))
                continue;
            char *title = input_item_GetTitleFbName([candidate input]);
            BOOL same = wantedTitle && title && !strcmp(wantedTitle, title);
            free(title);
            if (same) {
                visibleNode = candidate;
                break;
            }
        }
        free(wantedTitle);
        if (!visibleNode) {
            if (letterToLoad)
                *letterToLoad = visibleParent;
            return nil;
        }
        visibleParent = visibleNode;
    }

    VLCPLItem *match = VLCPlaylistItemsHaveSameURI(visibleParent, item)
                     ? visibleParent
                     : VLCFindVisibleItemWithURI(visibleParent, item);
    if (!match && letterToLoad)
        *letterToLoad = visibleParent;
    return match;
}

#pragma mark -
#pragma mark Playlist actions

/* When called retrieves the selected outlineview row and plays that node or item */
- (IBAction)playItem:(id)sender
{
    intf_thread_t *p_intf = getIntf();
    playlist_t *p_playlist = pl_Get(p_intf);

    // ignore clicks on column header when handling double action
    if (sender == _outlineView && [_outlineView clickedRow] == -1)
        return;

    /* AppKit can keep the previous selection for a short time while a lazy
     * directory is being populated.  A double click must act on the row that
     * was actually clicked, otherwise identically named nodes such as
     * "Random" can open the sibling from the preceding media-library view. */
    NSInteger row = sender == _outlineView ? [_outlineView clickedRow]
                                           : [_outlineView selectedRow];
    VLCPLItem *o_item = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    if (!o_item)
        return;
    BOOL randomAction = VLCPLItemIsPowerVLCRandomAction(o_item);

    /* Any explicit click supersedes a lazy branch still being resolved. */
    _pendingNodePlayback = NO;
    _pendingNodePlaybackId = -1;
    _pendingNodeBrowseId = -1;
    _pendingNodeSelectionId = -1;
    _pendingNodeSelectionScopeId = -1;
    _pendingNodeSelectionURI = nil;
    _pendingNodeSelectionPath = nil;
    _pendingNodePlaybackRetries = 0;
    ++_randomSelectionSettleGeneration;

    /* Keep the exact action object until its lazy XSPF has been populated.
     * The core may expose another occurrence of the playing input as its
     * current playlist item, which is insufficient to recover the category
     * and the private letter/artist/album path afterwards. */
    _activeRandomAction = randomAction ? o_item : nil;
    _randomActionAnchorPath = nil;
    if (randomAction) {
        NSMutableArray *anchorPath = [NSMutableArray array];
        VLCPLItem *modelRoot = [_model rootItem];
        for (VLCPLItem *cursor = o_item;
             cursor && cursor != modelRoot; cursor = [cursor parent]) {
            char *name = input_item_GetName([cursor input]);
            if (name) {
                [anchorPath insertObject:[NSString stringWithUTF8String:name]
                                 atIndex:0];
                free(name);
            }
        }
        _randomActionAnchorPath = [anchorPath copy];
    }

    /* Install the new action above before changing the AppKit selection.
     * Selection/model callbacks query the logical anchor immediately;
     * selecting first left the preceding Random action active for that short
     * window (M could therefore jump to the earlier N branch).  With the new
     * anchor already authoritative, every Random entry follows the same
     * deterministic transition: clicked action, then resolved track. */
    if (randomAction && row >= 0)
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row]
                  byExtendingSelection:NO];

    PL_LOCK;
    playlist_item_t *p_item = playlist_ItemGetById(p_playlist, [o_item plItemId]);
    playlist_item_t *p_node = playlist_ItemGetById(p_playlist, [[[self model] rootItem] plItemId]);

    if (p_item && p_node) {
        /* A node is a playback scope, not a leaf in the root scope.  Passing
         * it as the leaf lets the core continue with an unrelated expanded
         * sibling after resolving identically named Random nodes. */
        if (randomAction) {
            _pendingRandomPlayback = YES;
            _pendingRandomBranchId = -1;
        } else if (p_item->i_children >= 0
                || (p_item->p_input
                 && (p_item->p_input->i_type == ITEM_TYPE_DIRECTORY
                  || VLCIsPowerVLCIndexItem(p_item->p_input)))) {
            /* Compact-library letters, artists and albums are lazy. Resolve
             * their first real album track level by level; never pass the
             * internal index URI to the input engine as if it were media. */
            _pendingNodePlayback = YES;
            _pendingNodePlaybackId = p_item->i_id;
            _pendingNodeBrowseId = -1;
            _pendingNodePlaybackRetries = 0;
        } else {
            /* A visible media leaf belongs to its immediate logical group.
             * Using the discovery root exposes the private duplicate tracks
             * carried by Random XSPFs, so Next can skip an album sibling. */
            playlist_item_t *scope = p_item->p_parent ? p_item->p_parent
                                                       : p_node;
            playlist_ViewPlay(p_playlist, scope, p_item);
        }
    }
    PL_UNLOCK;
    if (randomAction)
        [self playPendingRandomActionIfReady];
    else if (_pendingNodePlayback) {
        [_outlineView expandItem:o_item];
        [self playPendingNodeIfReady];
    }
}

- (IBAction)revealItemInFinder:(id)sender
{
    NSIndexSet *selectedRows = [_outlineView selectedRowIndexes];
    if (selectedRows.count < 1)
        return;

    VLCPLItem *o_item = [_outlineView itemAtRow:selectedRows.firstIndex];

    char *psz_url = input_item_GetURI([o_item input]);
    if (!psz_url)
        return;
    char *psz_path = vlc_uri2path(psz_url);
    NSString *path = toNSStr(psz_path);
    free(psz_url);
    free(psz_path);

    msg_Dbg(getIntf(), "Reveal url %s in finder", [path UTF8String]);
    [[NSWorkspace sharedWorkspace] selectFile: path inFileViewerRootedAtPath: path];
}

- (IBAction)selectAll:(id)sender
{
    [_outlineView selectAll: nil];
}

- (IBAction)showInfoPanel:(id)sender
{
    [[[VLCMain sharedInstance] currentMediaInfoPanel] toggleWindow:sender];
}

- (IBAction)addFilesToPlaylist:(id)sender
{
    NSIndexSet *selectedRows = [_outlineView selectedRowIndexes];

    NSInteger position = -1;
    VLCPLItem *parentItem = [[self model] rootItem];

    if (selectedRows.count >= 1) {
        position = selectedRows.firstIndex + 1;
        parentItem = [_outlineView itemAtRow:selectedRows.firstIndex];
        if ([parentItem parent] != nil)
            parentItem = [parentItem parent];
    }

    [[[VLCMain sharedInstance] open] openFileWithAction:^(NSArray *files) {
        [self addPlaylistItems:files
              withParentItemId:[parentItem plItemId]
                         atPos:position
                 startPlayback:NO];
    }];
}

/* Return the selected playlist-member ids only when every selected row is a
 * member of the same user playlist.  Removing such rows edits the playlist;
 * it must not fall through to the generic service-discovery deletion path. */
- (NSArray *)selectedUserPlaylistMemberIdsWithParent:(int *)parentId
{
    NSIndexSet *rows = [_outlineView selectedRowIndexes];
    if (![rows count])
        return nil;
    __block VLCPLItem *playlistNode = nil;
    __block BOOL valid = YES;
    NSMutableArray *ids = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        VLCPLItem *item = [_outlineView itemAtRow:(NSInteger)row];
        VLCPLItem *container = VLCPLItemContainingUserPlaylist(item);
        if (!item || !container || item == container
         || (playlistNode && playlistNode != container)) {
            valid = NO;
            *stop = YES;
            return;
        }
        playlistNode = container;
        [ids addObject:@([item plItemId])];
    }];
    if (!valid || !playlistNode || ![ids count])
        return nil;
    if (parentId)
        *parentId = [playlistNode plItemId];
    return ids;
}

- (IBAction)deleteItem:(id)sender
{
    NSString *service = [[[[VLCMain sharedInstance] mainWindow]
                           sidebarDataSource] selectedPowerDeviceService];
    if (service) {
        NSIndexSet *structuralSelection = [_outlineView selectedRowIndexes];
        __block BOOL containsStructure = NO;
        [structuralSelection enumerateIndexesUsingBlock:
            ^(NSUInteger row, BOOL *stop) {
            if (VLCPLItemIsPowerVLCDeviceStructure(
                    [_outlineView itemAtRow:(NSInteger)row])) {
                containsStructure = YES;
                *stop = YES;
            }
        }];
        if (containsStructure)
            return;
        /* Removing an occurrence from an iPod playlist is not a device-file
         * deletion. Keep the media in Music and only edit playlist members. */
        NSIndexSet *selectedRows = [_outlineView selectedRowIndexes];
        if ([selectedRows count] == 1) {
            VLCPLItem *selected = [_outlineView itemAtRow:
                                    (NSInteger)[selectedRows firstIndex]];
            if (VLCPLItemIsUserPlaylistRoot(selected))
                return;
            if (VLCPLItemIsUserPlaylistObject(selected)) {
                NSAlert *alert = [[NSAlert alloc] init];
                alert.messageText = _NS("Delete Playlist?");
                alert.informativeText = _NS("The playlist will be removed, but its media will remain on the player.");
                [alert addButtonWithTitle:_NS("Delete")];
                [alert addButtonWithTitle:_NS("Cancel")];
                if ([alert runModal] != NSAlertFirstButtonReturn) return;
                services_discovery_playlist_item_t request = {
                    [selected plItemId]
                };
                playlist_ServicesDiscoveryControl(pl_Get(getIntf()),
                    service.UTF8String, SD_CMD_POWERVLC_PLAYLIST_DELETE,
                    &request);
                return;
            }
        }
        __block VLCPLItem *playlistNode = nil;
        __block BOOL playlistMembersOnly = [selectedRows count] > 0;
        NSMutableArray *memberItems = [NSMutableArray array];
        [selectedRows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
            VLCPLItem *item = [_outlineView itemAtRow:(NSInteger)row];
            VLCPLItem *container = VLCPLItemContainingUserPlaylist(item);
            if (!item || item == container || !container
             || (playlistNode && playlistNode != container)) {
                playlistMembersOnly = NO; *stop = YES; return;
            }
            playlistNode = container;
            [memberItems addObject:item];
        }];
        if (playlistMembersOnly && playlistNode) {
            NSAlert *alert = [[NSAlert alloc] init];
            alert.messageText = _NS("Remove from Playlist?");
            alert.informativeText = [NSString stringWithFormat:
                _NS("%lu item(s) will be removed from this playlist. The media will remain on the player."),
                (unsigned long)[memberItems count]];
            [alert addButtonWithTitle:_NS("Remove from Playlist")];
            [alert addButtonWithTitle:_NS("Cancel")];
            if ([alert runModal] != NSAlertFirstButtonReturn) return;
            int *ids = calloc([memberItems count], sizeof(*ids));
            if (!ids) return;
            for (NSUInteger i = 0; i < [memberItems count]; ++i)
                ids[i] = [[memberItems objectAtIndex:i] plItemId];
            services_discovery_playlist_remove_t request = {
                [playlistNode plItemId], [memberItems count], ids
            };
            playlist_ServicesDiscoveryControl(pl_Get(getIntf()),
                service.UTF8String, SD_CMD_POWERVLC_PLAYLIST_REMOVE, &request);
            free(ids);
            return;
        }
        NSIndexSet *rows = [_outlineView selectedRowIndexes];
        int *itemIds = calloc([rows count], sizeof(*itemIds));
        if (!itemIds) return;
        __block NSUInteger itemIndex = 0;
        [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
            itemIds[itemIndex++] = [[_outlineView itemAtRow:(NSInteger)row]
                                                               plItemId];
        }];
        services_discovery_device_delete_resolve_t resolved = {
            itemIds, itemIndex, NULL, 0
        };
        int resolveResult = playlist_ServicesDiscoveryControl(
            pl_Get(getIntf()), service.UTF8String,
            SD_CMD_POWERVLC_DEVICE_RESOLVE_DELETE, &resolved);
        if (resolveResult != VLC_SUCCESS || resolved.i_count == 0) {
            free(itemIds);
            NSAlert *error = [[NSAlert alloc] init];
            error.messageText = _NS("Unable to Delete Selected Content");
            error.informativeText = _NS("PowerVLC could not resolve the selected rows to media stored on this player.");
            [error runModal];
            return;
        }
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = _NS("Delete Content from Portable Player?");
        alert.informativeText = [NSString stringWithFormat:
            _NS("%lu item(s) will be deleted from the player. This action cannot be undone."),
            (unsigned long)resolved.i_count];
        [alert addButtonWithTitle:_NS("Delete")];
        [alert addButtonWithTitle:_NS("Cancel")];
        if ([alert runModal] == NSAlertFirstButtonReturn) {
            services_discovery_device_delete_t request = {
                (const char *const *)resolved.ppsz_paths, resolved.i_count,
                itemIds, itemIndex
            };
            int result = playlist_ServicesDiscoveryControl(pl_Get(getIntf()),
                service.UTF8String, SD_CMD_POWERVLC_DEVICE_DELETE, &request);
            if (result != VLC_SUCCESS) {
                NSAlert *error = [[NSAlert alloc] init];
                error.messageText = _NS("Unable to Delete Selected Content");
                error.informativeText = _NS("The portable player rejected the deletion request. No content was changed.");
                [error runModal];
            } else
                _outlineView.enabled = NO;
        }
        for (size_t i = 0; i < resolved.i_count; ++i)
            free(resolved.ppsz_paths[i]);
        free(resolved.ppsz_paths);
        free(itemIds);
        return;
    }

    int userPlaylistId = -1;
    NSArray *memberIds = [self selectedUserPlaylistMemberIdsWithParent:
                                                    &userPlaylistId];
    if ([memberIds count]) {
        int *ids = calloc([memberIds count], sizeof(*ids));
        if (!ids) return;
        for (NSUInteger i = 0; i < [memberIds count]; ++i)
            ids[i] = [[memberIds objectAtIndex:i] intValue];
        services_discovery_playlist_remove_t request = {
            userPlaylistId, [memberIds count], ids
        };
        playlist_ServicesDiscoveryControl(pl_Get(getIntf()),
            "powervlc_library", SD_CMD_POWERVLC_PLAYLIST_REMOVE, &request);
        free(ids);
        return;
    }
    [_model deleteSelectedItem];
}

// Actions for playlist column selections


- (void)togglePlaylistColumnTable:(id)sender
{
    NSInteger i_new_state = ![sender state];
    NSInteger i_tag = [sender tag];

    NSString *column = [_menuOrderOfPlaylistTableColumns objectAtIndex:i_tag];

    [self setPlaylistColumnTableState:i_new_state forColumn:column];
}

- (BOOL)setPlaylistColumnTableState:(NSInteger)i_state forColumn:(NSString *)columnId
{
    NSUInteger i_tag = [_menuOrderOfPlaylistTableColumns indexOfObject: columnId];
    // prevent setting unknown columns
    if(i_tag == NSNotFound)
        return NO;

    // update state of menu items
    [[[_playlistHeaderView menu] itemWithTag: i_tag] setState: i_state];
    [[[[[VLCMain sharedInstance] mainMenu] playlistTableColumnsMenu] itemWithTag: i_tag] setState: i_state];

    // Change outline view
    if (i_state == NSOnState) {
        NSString *title = [_translationsForPlaylistTableColumns objectForKey:columnId];
        if (!title)
            return NO;

        NSTableColumn *tableColumn = [[NSTableColumn alloc] initWithIdentifier:columnId];
        [tableColumn setEditable:NO];
        [[tableColumn dataCell] setFont:[NSFont controlContentFontOfSize:11.]];

        [[tableColumn headerCell] setStringValue:[_translationsForPlaylistTableColumns objectForKey:columnId]];

        if ([columnId isEqualToString: TRACKNUM_COLUMN]) {
            [tableColumn setMinWidth:20.];
            [tableColumn setMaxWidth:70.];
            [[tableColumn headerCell] setStringValue:@"#"];

        } else {
            [tableColumn setMinWidth:42.];
        }

        [_outlineView addTableColumn:tableColumn];
        [_outlineView reloadData];
        [_outlineView setNeedsDisplay: YES];
    }
    else
        [_outlineView removeTableColumn: [_outlineView tableColumnWithIdentifier:columnId]];

    [_outlineView setOutlineTableColumn: [_outlineView tableColumnWithIdentifier:TITLE_COLUMN]];

    return YES;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if ([item action] == @selector(setPowerVLCRating:)) {
        NSDictionary *ratings = [self selectedPowerVLCRatings];
        NSNumber *common = nil;
        BOOL mixed = NO;
        for (NSNumber *value in [ratings allValues]) {
            if (!common) common = value;
            else if (![common isEqualToNumber:value]) { mixed = YES; break; }
        }
        unsigned candidate = (unsigned)[item.representedObject unsignedIntegerValue];
        [item setState:(!mixed && common && [common unsignedIntegerValue] == candidate)
                         ? NSOnState : NSOffState];
        return [ratings count] > 0;
    } else if ([item action] == @selector(revealItemInFinder:)) {
        NSIndexSet *selectedRows = [_outlineView selectedRowIndexes];
        if (selectedRows.count != 1)
            return NO;

        VLCPLItem *o_item = [_outlineView itemAtRow:selectedRows.firstIndex];

        /* Menu validation runs on AppKit's main thread.  In particular, a
         * mounted iPod can take a very long time to answer a stat(2), so do
         * not touch the volume merely because its contextual menu opened.
         * The reveal action already copes with a file disappearing. */
        char *psz_url = input_item_GetURI([o_item input]);
        NSURL *url = [NSURL URLWithString:toNSStr(psz_url)];
        free(psz_url);
        if (![url isFileURL])
            return NO;

    } else if ([item action] == @selector(deleteItem:)) {
        NSString *service = [[[[VLCMain sharedInstance] mainWindow]
                               sidebarDataSource] selectedPowerDeviceService];
        if (service) {
            __block BOOL deletable = YES;
            [[_outlineView selectedRowIndexes]
                enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
                if (VLCPLItemIsPowerVLCDeviceStructure(
                        [_outlineView itemAtRow:(NSInteger)row])) {
                    deletable = NO;
                    *stop = YES;
                }
            }];
            if (!deletable)
                return NO;
        }
        int playlistId = -1;
        BOOL userPlaylistMembers =
            [[self selectedUserPlaylistMemberIdsWithParent:&playlistId] count]
                                                                    > 0;
        return [_outlineView numberOfSelectedRows] > 0
            && (_model.editAllowed || service != nil || userPlaylistMembers);
    } else if ([item action] == @selector(selectAll:)) {
        return [_outlineView numberOfRows] > 0;
    } else if ([item action] == @selector(playItem:)) {
        return [_outlineView numberOfSelectedRows] > 0;
    } else if ([item action] == @selector(recursiveExpandOrCollapseNode:)) {
        return [_outlineView numberOfSelectedRows] > 0;
    } else if ([item action] == @selector(showInfoPanel:)) {
        return [_outlineView numberOfSelectedRows] > 0;
    } else if ([item action] == @selector(shufflePlaylist:)) {
        return ([_outlineView numberOfRows] > 0 &&
                [[self model] currentRootType] != ROOT_TYPE_MEDIALIBRARY &&
                _model.editAllowed);
    } else if ([item action] == @selector(burnPlaylistToAudioCD:)) {
        return [_outlineView numberOfSelectedRows] > 0;
    }

    return YES;
}

#pragma mark -
#pragma mark Helper for playlist table columns

- (void)setupPlaylistTableColumnsForMenu:(NSMenu *)menu
{
    NSMenuItem *menuItem;
    NSUInteger count = [_menuOrderOfPlaylistTableColumns count];
    for (NSUInteger i = 0; i < count; i++) {
        NSString *columnId = [_menuOrderOfPlaylistTableColumns objectAtIndex:i];
        NSString *title = [_translationsForPlaylistTableColumns objectForKey:columnId];
        menuItem = [menu addItemWithTitle:title
                                   action:@selector(togglePlaylistColumnTable:)
                            keyEquivalent:@""];
        [menuItem setTarget:self];
        [menuItem setTag:i];

        /* don't set a valid action for the title column selector, since we want it to be disabled */
        if ([columnId isEqualToString: TITLE_COLUMN])
            [menuItem setAction:nil];

    }
}

- (void)saveTableColumns
{
    NSMutableArray *arrayToSave = [[NSMutableArray alloc] init];
    NSArray *columns = [[NSArray alloc] initWithArray:[_outlineView tableColumns]];
    NSUInteger columnCount = [columns count];
    NSTableColumn *currentColumn;
    for (NSUInteger i = 0; i < columnCount; i++) {
        currentColumn = [columns objectAtIndex:i];
        [arrayToSave addObject:[NSArray arrayWithObjects:[currentColumn identifier], [NSNumber numberWithFloat:[currentColumn width]], nil]];
    }
    [[NSUserDefaults standardUserDefaults] setObject:arrayToSave forKey:@"PlaylistColumnSelection"];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

#pragma mark -
#pragma mark Item helpers

- (input_item_t *)createItem:(NSDictionary *)itemToCreateDict
{
    intf_thread_t *p_intf = getIntf();
    playlist_t *p_playlist = pl_Get(p_intf);

    input_item_t *p_input;
    BOOL b_rem = FALSE, b_dir = FALSE, b_writable = FALSE;
    NSString *uri, *name, *path;
    NSURL * url;
    NSArray *optionsArray;

    /* Get the item */
    uri = (NSString *)[itemToCreateDict objectForKey: @"ITEM_URL"];
    url = [NSURL URLWithString: uri];
    path = [url path];
    name = (NSString *)[itemToCreateDict objectForKey: @"ITEM_NAME"];
    optionsArray = (NSArray *)[itemToCreateDict objectForKey: @"ITEM_OPTIONS"];

    /* Keep ISO images as file:// inputs.  The access/demux probes can then
     * distinguish DVD images from Blu-ray images; forcing every .iso through
     * bluray:// makes ordinary DVD images fail before dvdnav can open them. */
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&b_dir] && b_dir &&
        [[NSWorkspace sharedWorkspace] getFileSystemInfoForPath:path isRemovable: &b_rem
                                                     isWritable:&b_writable isUnmountable:NULL description:NULL type:NULL] && b_rem && !b_writable && [url isFileURL]) {

        NSString *diskType = [[VLCStringUtility sharedInstance] getVolumeTypeFromMountPath: path];
        msg_Dbg(p_intf, "detected optical media of type %s in the file input", [diskType UTF8String]);

        if ([diskType isEqualToString: kVLCMediaDVD])
            uri = [NSString stringWithFormat: @"dvdnav://%@", [[VLCStringUtility sharedInstance] getBSDNodeFromMountPath: path]];
        else if ([diskType isEqualToString: kVLCMediaAudioDVD])
            uri = [NSString stringWithFormat: @"dvda://%@", [[VLCStringUtility sharedInstance] getBSDNodeFromMountPath: path]];
        else if ([diskType isEqualToString: kVLCMediaVideoTSFolder])
            uri = [NSString stringWithFormat: @"dvdnav://%@", path];
        else if ([diskType isEqualToString: kVLCMediaAudioCD])
            uri = [NSString stringWithFormat: @"cdda://%@", [[VLCStringUtility sharedInstance] getBSDNodeFromMountPath: path]];
        else if ([diskType isEqualToString: kVLCMediaVCD])
            uri = [NSString stringWithFormat: @"vcd://%@#0:0", [[VLCStringUtility sharedInstance] getBSDNodeFromMountPath: path]];
        else if ([diskType isEqualToString: kVLCMediaSVCD])
            uri = [NSString stringWithFormat: @"vcd://%@@0:0", [[VLCStringUtility sharedInstance] getBSDNodeFromMountPath: path]];
        else if ([diskType isEqualToString: kVLCMediaBD] || [diskType isEqualToString: kVLCMediaBDMVFolder])
            uri = [NSString stringWithFormat: @"bluray://%@", path];
        else
            msg_Warn(getIntf(), "unknown disk type, treating %s as regular input", [path UTF8String]);

        p_input = input_item_New([uri UTF8String], [[[NSFileManager defaultManager] displayNameAtPath:path] UTF8String]);
    }
    else
        p_input = input_item_New([uri fileSystemRepresentation], name ? [name UTF8String] : NULL);

    if (!p_input)
        return NULL;

    if (optionsArray) {
        NSUInteger count = [optionsArray count];
        for (NSUInteger i = 0; i < count; i++)
            input_item_AddOption(p_input, [[optionsArray objectAtIndex:i] UTF8String], VLC_INPUT_OPTION_TRUSTED);
    }

    /* Keep local files and streams in two distinct recent menus. Use the
     * possibly rewritten URI (optical media can start as a file URL). */
    if (var_InheritBool(getIntf(), "macosx-recentitems")) {
        NSURL *recentURL = [NSURL URLWithString:uri];
        if ([recentURL isFileURL])
            [[NSDocumentController sharedDocumentController]
                noteNewRecentDocumentURL:recentURL];
        else if (recentURL != nil)
            VLCNoteRecentStream(uri);
    }

    return p_input;
}

- (NSArray *)createItemsFromExternalPasteboard:(NSPasteboard *)pasteboard
{
    NSArray *o_array = [NSArray array];
    NSMutableArray *paths = [NSMutableArray array];
    NSArray *legacy = [pasteboard propertyListForType:NSFilenamesPboardType];
    if ([legacy isKindOfClass:[NSArray class]]) [paths addObjectsFromArray:legacy];
    NSArray *urls = [pasteboard readObjectsForClasses:@[[NSURL class]]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in urls)
        if ([url isFileURL] && ![paths containsObject:[url path]])
            [paths addObject:[url path]];
    NSArray *o_values = [paths sortedArrayUsingSelector:@selector(caseInsensitiveCompare:)];
    NSUInteger count = [o_values count];

    for (NSUInteger i = 0; i < count; i++) {
        NSDictionary *o_dic;
        char *psz_uri = vlc_path2uri([[o_values objectAtIndex:i] UTF8String], NULL);
        if (!psz_uri)
            continue;

        o_dic = [NSDictionary dictionaryWithObject:toNSStr(psz_uri) forKey:@"ITEM_URL"];
        free(psz_uri);

        o_array = [o_array arrayByAddingObject: o_dic];
    }

    return o_array;
}

- (void)addPlaylistItems:(NSArray*)array
{

    int i_plItemId = -1;

    // add items directly to media library if this is the current root
    if ([[self model] currentRootType] == ROOT_TYPE_MEDIALIBRARY)
        i_plItemId = [[[self model] rootItem] plItemId];

    BOOL b_autoplay = var_InheritBool(getIntf(), "macosx-autoplay");

    [self addPlaylistItems:array withParentItemId:i_plItemId atPos:-1 startPlayback:b_autoplay];
}

- (void)addPlaylistItems:(NSArray*)array tryAsSubtitle:(BOOL)isSubtitle
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (isSubtitle && array.count == 1 && p_input) {
        int i_result = input_AddSlave(p_input, SLAVE_TYPE_SPU,
                    [[[array firstObject] objectForKey:@"ITEM_URL"] UTF8String],
                    true, true, true);
        if (i_result == VLC_SUCCESS) {
            vlc_object_release(p_input);
            return;
        }
    }

    if (p_input)
        vlc_object_release(p_input);

    [self addPlaylistItems:array];
}

- (void)addPlaylistItems:(NSArray*)array withParentItemId:(int)i_plItemId atPos:(int)i_position startPlayback:(BOOL)b_start
{
    playlist_t * p_playlist = pl_Get(getIntf());
    PL_LOCK;

    playlist_item_t *p_parent = NULL;
    if (i_plItemId >= 0)
        p_parent = playlist_ItemGetById(p_playlist, i_plItemId);
    else
        p_parent = p_playlist->p_playing;

    if (!p_parent) {
        PL_UNLOCK;
        return;
    }

    NSUInteger count = [array count];
    int i_current_offset = 0;
    for (NSUInteger i = 0; i < count; ++i) {

        NSDictionary *o_current_item = [array objectAtIndex:i];
        input_item_t *p_input = [self createItem: o_current_item];
        if (!p_input)
            continue;

        int i_pos = (i_position == -1) ? PLAYLIST_END : i_position + i_current_offset++;
        playlist_item_t *p_item = playlist_NodeAddInput(p_playlist, p_input,
                                                        p_parent, i_pos);
        if (!p_item)
            continue;

        if (i == 0 && b_start) {
            playlist_ViewPlay(p_playlist, p_parent, p_item);
        }
        input_item_Release(p_input);
    }
    PL_UNLOCK;
}

- (IBAction)recursiveExpandOrCollapseNode:(id)sender
{
    bool expand = (sender == _recursiveExpandPlaylistMenuItem);

    NSIndexSet * selectedRows = [_outlineView selectedRowIndexes];
    NSUInteger count = [selectedRows count];
    NSUInteger indexes[count];
    [selectedRows getIndexes:indexes maxCount:count inIndexRange:nil];

    if (expand) {
        NSUInteger remaining = 256;
        for (NSUInteger i = 0; i < count; ++i) {
            VLCPLItem *selected = [_outlineView itemAtRow:indexes[i]];
            if (!VLCPLItemCanExpandRecursively(selected, &remaining)) {
                NSRunInformationalAlertPanel(
                    _NS("Cannot Expand Entire Section"),
                    @"%@", _NS("OK"), nil, nil,
                    _NS("This section is too large or loaded on demand. Expand only the branches you need."));
                return;
            }
        }
    }

    id item;
    playlist_item_t *p_item;
    for (NSUInteger i = 0; i < count; i++) {
        item = [_outlineView itemAtRow: indexes[i]];

        /* We need to collapse the node first, since OSX refuses to recursively
         expand an already expanded node, even if children nodes are collapsed. */
        if ([_outlineView isExpandable:item]) {
            [_outlineView collapseItem: item collapseChildren: YES];

            if (expand)
                [_outlineView expandItem: item expandChildren: YES];
        }

        selectedRows = [_outlineView selectedRowIndexes];
        [selectedRows getIndexes:indexes maxCount:count inIndexRange:nil];
    }
}

- (IBAction)shufflePlaylist:(id)sender
{
    if ([[self model] currentRootType] == ROOT_TYPE_MEDIALIBRARY)
        return;

    [[self model] sortPlaylistBy:SORT_RANDOM withOrder:ORDER_NORMAL];
}

static void VLCCollectBurnPaths(VLCPLItem *item, NSMutableArray *paths)
{
    if ([[item children] count]) {
        for (VLCPLItem *child in [item children]) VLCCollectBurnPaths(child, paths);
        return;
    }
    char *uri = input_item_GetURI([item input]);
    NSURL *url = uri ? [NSURL URLWithString:toNSStr(uri)] : nil;
    free(uri);
    if (![url isFileURL]) return;
    static NSSet *extensions;
    if (!extensions) extensions = [NSSet setWithObjects:@"aac", @"aif", @"aiff",
        @"alac", @"flac", @"m4a", @"mp3", @"ogg", @"opus", @"wav", nil];
    if ([extensions containsObject:[[[url path] pathExtension] lowercaseString]])
        [paths addObject:[url path]];
}

- (IBAction)burnPlaylistToAudioCD:(id)sender
{
    NSMutableArray *paths = [NSMutableArray array];
    NSIndexSet *rows = [_outlineView selectedRowIndexes];
    NSUInteger row = [rows firstIndex];
    while (row != NSNotFound) {
        VLCCollectBurnPaths([_outlineView itemAtRow:row], paths);
        row = [rows indexGreaterThanIndex:row];
    }
    paths = [NSMutableArray arrayWithArray:
        [[NSOrderedSet orderedSetWithArray:paths] array]];
    if (![paths count]) {
        NSAlert *empty = [[NSAlert alloc] init];
        empty.messageText = _NS("Burn Audio CD");
        empty.informativeText = _NS("The selection contains no local audio tracks.");
        [empty runModal]; return;
    }
    NSAlert *confirm = [[NSAlert alloc] init];
    confirm.messageText = _NS("Burn Audio CD");
    confirm.informativeText = [NSString stringWithFormat:
        _NS("Burn %lu tracks to the blank Audio CD?"), (unsigned long)[paths count]];
    [confirm addButtonWithTitle:_NS("Burn")]; [confirm addButtonWithTitle:_NS("Cancel")];
    if ([confirm runModal] != NSAlertFirstButtonReturn) return;

    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"PowerVLC-Audio-CD-%@",
         [[NSProcessInfo processInfo] globallyUniqueString]]];
    NSFileManager *manager = [NSFileManager defaultManager];
    if (![manager createDirectoryAtPath:directory withIntermediateDirectories:YES
                              attributes:nil error:nil]) return;
    NSUInteger number = 1;
    for (NSString *source in paths) {
        NSString *name = [NSString stringWithFormat:@"%03lu.%@",
            (unsigned long)number++, [source pathExtension]];
        NSString *target = [directory stringByAppendingPathComponent:name];
        if (![manager createSymbolicLinkAtPath:target withDestinationPath:source error:nil])
            [manager copyItemAtPath:source toPath:target error:nil];
    }
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/drutil";
    task.arguments = @[@"burn", @"-audio", @"-eject", directory];
    task.terminationHandler = ^(NSTask *finished) {
        [[NSFileManager defaultManager] removeItemAtPath:directory error:nil];
        if ([finished terminationStatus] != 0) dispatch_async(dispatch_get_main_queue(), ^{
            NSAlert *failed = [[NSAlert alloc] init];
            failed.messageText = _NS("Burn Audio CD");
            failed.informativeText = _NS("The disc burning process failed.");
            [failed runModal];
        });
    };
    [task launch];
}

- (NSArray *)selectedTopLevelPlaylistItemIds
{
    NSIndexSet *rows = [_outlineView selectedRowIndexes];
    NSMutableSet *allSelected = [NSMutableSet set];
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        VLC_UNUSED(stop);
        VLCPLItem *item = [_outlineView itemAtRow:(NSInteger)row];
        if (item && !VLCPLItemIsPowerVLCRandomAction(item))
            [allSelected addObject:@([item plItemId])];
    }];

    NSMutableArray *result = [NSMutableArray array];
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        VLC_UNUSED(stop);
        VLCPLItem *item = [_outlineView itemAtRow:(NSInteger)row];
        if (!item || VLCPLItemIsPowerVLCRandomAction(item))
            return;
        for (VLCPLItem *parent = [item parent]; parent;
             parent = [parent parent])
            if ([allSelected containsObject:@([parent plItemId])])
                return;
        [result addObject:@([item plItemId])];
    }];
    return result;
}

/* Build the destination menu from the core tree rather than the current
 * NSOutlineView wrappers.  A playlist folder may be collapsed (or its Cocoa
 * wrappers may be rebuilt while a scan notification arrives), but every
 * nested playlist must remain addressable from the context menu.  The
 * playlist lock is held by the caller while this immutable description is
 * produced. */
static NSArray *VLCUserPlaylistTargetDescriptions(playlist_item_t *parent,
                                                   NSSet *selectedIds,
                                                   BOOL parentBlocked)
{
    NSMutableArray *result = [NSMutableArray array];
    if (!parent || parent->i_children < 0)
        return result;
    for (int i = 0; i < parent->i_children; ++i) {
        playlist_item_t *child = parent->pp_children[i];
        if (!child || !child->p_input)
            continue;
        BOOL folder = input_item_IsPowerVLCPlaylistFolder(child->p_input);
        BOOL playlist = input_item_IsPowerVLCUserPlaylist(child->p_input);
        if (!folder && !playlist)
            continue;
        char *nameValue = input_item_GetName(child->p_input);
        NSString *name = nameValue
            ? [NSString stringWithUTF8String:nameValue] : @"";
        free(nameValue);
        BOOL blocked = parentBlocked
                    || [selectedIds containsObject:@(child->i_id)];
        if (folder) {
            NSArray *children = VLCUserPlaylistTargetDescriptions(child,
                selectedIds, blocked);
            [result addObject:@{ @"name": name ?: @"",
                                 @"folder": @YES,
                                 @"children": children }];
        } else {
            [result addObject:@{ @"name": name ?: @"",
                                 @"folder": @NO,
                                 @"id": @(child->i_id),
                                 @"blocked": @(blocked) }];
        }
    }
    return result;
}

- (NSUInteger)appendUserPlaylistTargets:(NSArray *)descriptions
                                  toMenu:(NSMenu *)menu
                                sourceIds:(NSArray *)sourceIds
{
    NSUInteger playlistCount = 0;
    for (NSDictionary *description in descriptions) {
        NSString *name = [description objectForKey:@"name"] ?: @"";
        if ([[description objectForKey:@"folder"] boolValue]) {
            NSMenu *folderMenu = [[NSMenu alloc] initWithTitle:name ?: @""];
            NSUInteger nested = [self appendUserPlaylistTargets:
                [description objectForKey:@"children"] toMenu:folderMenu
                sourceIds:sourceIds];
            NSMenuItem *folder = [[NSMenuItem alloc] initWithTitle:name ?: @""
                action:nil keyEquivalent:@""];
            folder.submenu = folderMenu;
            folder.enabled = nested > 0;
            [menu addItem:folder];
            playlistCount += nested;
        } else {
            NSMenuItem *target = [menu addItemWithTitle:name ?: @""
                action:@selector(addSelectionToUserPlaylist:)
                keyEquivalent:@""];
            target.target = self;
            /* Snapshot sources now. Looking up selected row indexes after a
             * submenu click can address unrelated items if the outline was
             * reloaded or filtered while the menu was open. */
            target.representedObject = @{
                @"targetId": [description objectForKey:@"id"],
                @"sourceIds": sourceIds
            };
            if ([[description objectForKey:@"blocked"] boolValue]) {
                target.action = nil;
                target.target = nil;
                target.enabled = NO;
            }
            ++playlistCount;
        }
    }
    return playlistCount;
}

- (void)addSelectionToUserPlaylist:(NSMenuItem *)sender
{
    NSDictionary *payload = [sender.representedObject
        isKindOfClass:[NSDictionary class]] ? sender.representedObject : nil;
    NSArray *sourceIds = [payload objectForKey:@"sourceIds"];
    NSNumber *targetId = [payload objectForKey:@"targetId"];
    if (![sourceIds count])
        return;
    int *ids = calloc([sourceIds count], sizeof(*ids));
    if (!ids)
        return;
    for (NSUInteger i = 0; i < [sourceIds count]; ++i)
        ids[i] = [[sourceIds objectAtIndex:i] intValue];
    services_discovery_playlist_drop_t request = {
        (int)[targetId intValue], -1,
        [sourceIds count], ids, true
    };
    NSString *deviceService = [[[[VLCMain sharedInstance] mainWindow]
                                  sidebarDataSource] selectedPowerDeviceService];
    const char *service = deviceService
                        ? deviceService.UTF8String : "powervlc_library";
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()), service,
        SD_CMD_POWERVLC_PLAYLIST_DROP, &request);
    free(ids);
}

- (NSMenu *)menuForEvent:(NSEvent *)o_event
{
    if (!b_playlistmenu_nib_loaded)
        b_playlistmenu_nib_loaded = [NSBundle loadNibNamed:@"PlaylistMenu" owner:self];

    NSPoint pt = [_outlineView convertPoint: [o_event locationInWindow] fromView: nil];
    int row = [_outlineView rowAtPoint:pt];
    if (row != -1 && ![[_outlineView selectedRowIndexes] containsIndex: row])
        [_outlineView selectRowIndexes:[NSIndexSet indexSetWithIndex:row] byExtendingSelection:NO];

    // TODO Reenable once per-item info panel is supported again
    _infoPlaylistMenuItem.hidden = YES;

    BOOL hasBurnItem = NO;
    for (NSMenuItem *menuItem in [_playlistMenu itemArray])
        if ([menuItem action] == @selector(burnPlaylistToAudioCD:))
            hasBurnItem = YES;
    if (!hasBurnItem) {
        [_playlistMenu addItem:[NSMenuItem separatorItem]];
        NSMenuItem *burn = [_playlistMenu addItemWithTitle:
            _NS("Burn Playlist to Audio CD…")
            action:@selector(burnPlaylistToAudioCD:) keyEquivalent:@""];
        [burn setTarget:self];
    }

    if (![_playlistMenu itemWithTag:VLCPowerVLCRatingMenuTag]) {
        NSMenu *ratings = [[NSMenu alloc] initWithTitle:_NS("Rating")];
        for (NSInteger value = 1; value <= 5; ++value) {
            NSMutableString *stars = [NSMutableString string];
            for (NSInteger starIndex = 0; starIndex < value; ++starIndex)
                [stars appendString:@"★"];
            NSMenuItem *star = [ratings addItemWithTitle:stars
                action:@selector(setPowerVLCRating:) keyEquivalent:@""];
            star.target = self;
            star.representedObject = @(value);
        }
        [ratings addItem:[NSMenuItem separatorItem]];
        NSMenuItem *clear = [ratings addItemWithTitle:_NS("No Rating")
            action:@selector(setPowerVLCRating:) keyEquivalent:@""];
        clear.target = self;
        clear.representedObject = @0;
        NSMenuItem *rating = [[NSMenuItem alloc] initWithTitle:_NS("Rating")
            action:nil keyEquivalent:@""];
        rating.tag = VLCPowerVLCRatingMenuTag;
        rating.submenu = ratings;
        [_playlistMenu addItem:[NSMenuItem separatorItem]];
        [_playlistMenu addItem:rating];
    }

    for (NSInteger tag = VLCPowerVLCPlaylistSeparatorMenuTag;
         tag <= VLCPowerVLCAddToPlaylistMenuTag; ++tag) {
        NSMenuItem *old = [_playlistMenu itemWithTag:tag];
        if (old) [_playlistMenu removeItem:old];
    }
    VLCPLItem *clicked = row >= 0 ? [_outlineView itemAtRow:row] : nil;
    NSString *deviceService = [[[[VLCMain sharedInstance] mainWindow]
                                  sidebarDataSource] selectedPowerDeviceService];
    BOOL canCreate = VLCPLItemIsUserPlaylistRoot(clicked)
                  || VLCPLItemIsUserPlaylistFolder(clicked);
    BOOL canEdit = VLCPLItemIsUserPlaylistObject(clicked);
    NSArray *selectedSourceIds = [self selectedTopLevelPlaylistItemIds];
    VLCPLItem *playlistsRoot = VLCFindUserPlaylistsRoot([_model rootItem]);
    NSMenu *addToMenu = [[NSMenu alloc] initWithTitle:
                                              _NS("Add to Playlist")];
    NSArray *targetDescriptions = nil;
    if (playlistsRoot) {
        playlist_t *playlist = pl_Get(getIntf());
        playlist_Lock(playlist);
        playlist_item_t *root = playlist_ItemGetById(playlist,
                                                     [playlistsRoot plItemId]);
        targetDescriptions = VLCUserPlaylistTargetDescriptions(root,
            [NSSet setWithArray:selectedSourceIds], NO);
        playlist_Unlock(playlist);
    }
    NSUInteger targetCount = targetDescriptions
        ? [self appendUserPlaylistTargets:targetDescriptions toMenu:addToMenu
                                sourceIds:selectedSourceIds] : 0;
    BOOL canAddToPlaylist = [selectedSourceIds count] > 0 && targetCount > 0;
    if (canCreate || canEdit || canAddToPlaylist) {
        NSMenuItem *separator = [NSMenuItem separatorItem];
        separator.tag = VLCPowerVLCPlaylistSeparatorMenuTag;
        [_playlistMenu addItem:separator];
        if (canAddToPlaylist) {
            NSMenuItem *addTo = [[NSMenuItem alloc] initWithTitle:
                _NS("Add to Playlist") action:nil keyEquivalent:@""];
            addTo.tag = VLCPowerVLCAddToPlaylistMenuTag;
            addTo.submenu = addToMenu;
            [_playlistMenu addItem:addTo];
        }
        if (canCreate) {
            NSMenuItem *newPlaylist = [_playlistMenu addItemWithTitle:
                _NS("New Playlist…") action:@selector(createUserPlaylist:)
                keyEquivalent:@""];
            newPlaylist.target = self;
            newPlaylist.tag = VLCPowerVLCNewPlaylistMenuTag;
            newPlaylist.representedObject = clicked;
            if (!deviceService) {
                NSMenuItem *newFolder = [_playlistMenu addItemWithTitle:
                    _NS("New Playlist Folder…")
                    action:@selector(createUserPlaylistFolder:)
                    keyEquivalent:@""];
                newFolder.target = self;
                newFolder.tag = VLCPowerVLCNewPlaylistFolderMenuTag;
                newFolder.representedObject = clicked;
            }
        }
        if (canEdit) {
            NSMenuItem *rename = [_playlistMenu addItemWithTitle:
                _NS("Rename…") action:@selector(renameUserPlaylist:)
                keyEquivalent:@""];
            rename.target = self;
            rename.tag = VLCPowerVLCRenamePlaylistMenuTag;
            rename.representedObject = clicked;
            NSMenuItem *remove = [_playlistMenu addItemWithTitle:
                _NS("Delete") action:@selector(deleteUserPlaylist:)
                keyEquivalent:@""];
            remove.target = self;
            remove.tag = VLCPowerVLCDeletePlaylistMenuTag;
            remove.representedObject = clicked;
        }
    }

    return _playlistMenu;
}

- (NSString *)promptForUserPlaylistName:(NSString *)title
                            initialValue:(NSString *)initialValue
{
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = title;
    [alert addButtonWithTitle:_NS("OK")];
    [alert addButtonWithTitle:_NS("Cancel")];
    NSTextField *field = [[NSTextField alloc] initWithFrame:
                           NSMakeRect(0, 0, 320, 24)];
    field.stringValue = initialValue ?: @"";
    alert.accessoryView = field;
    if ([alert runModal] != NSAlertFirstButtonReturn)
        return nil;
    NSString *name = [field.stringValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    return name.length ? name : nil;
}

- (void)createUserPlaylistAtItem:(VLCPLItem *)parent folder:(BOOL)folder
{
    if (!parent) return;
    NSString *name = [self promptForUserPlaylistName:
        folder ? _NS("New Playlist Folder") : _NS("New Playlist")
        initialValue:@""];
    if (!name) return;
    services_discovery_playlist_create_t request = {
        [parent plItemId], name.UTF8String, folder
    };
    NSString *deviceService = [[[[VLCMain sharedInstance] mainWindow]
                                  sidebarDataSource] selectedPowerDeviceService];
    const char *service = deviceService ? deviceService.UTF8String
                                        : "powervlc_library";
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()), service,
        SD_CMD_POWERVLC_PLAYLIST_CREATE, &request);
}

- (void)createUserPlaylist:(NSMenuItem *)sender
{
    [self createUserPlaylistAtItem:sender.representedObject folder:NO];
}

- (void)createUserPlaylistFolder:(NSMenuItem *)sender
{
    [self createUserPlaylistAtItem:sender.representedObject folder:YES];
}

- (void)renameUserPlaylist:(NSMenuItem *)sender
{
    VLCPLItem *item = sender.representedObject;
    if (!VLCPLItemIsUserPlaylistObject(item)) return;
    char *oldName = input_item_GetName([item input]);
    NSString *name = [self promptForUserPlaylistName:_NS("Rename Playlist")
        initialValue:oldName ? toNSStr(oldName) : @""];
    free(oldName);
    if (!name) return;
    services_discovery_playlist_rename_t request = {
        [item plItemId], name.UTF8String
    };
    NSString *deviceService = [[[[VLCMain sharedInstance] mainWindow]
                                  sidebarDataSource] selectedPowerDeviceService];
    const char *service = deviceService ? deviceService.UTF8String
                                        : "powervlc_library";
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()), service,
        SD_CMD_POWERVLC_PLAYLIST_RENAME, &request);
}

- (void)deleteUserPlaylist:(NSMenuItem *)sender
{
    VLCPLItem *item = sender.representedObject;
    if (!VLCPLItemIsUserPlaylistObject(item)) return;
    NSString *deviceService = [[[[VLCMain sharedInstance] mainWindow]
                                  sidebarDataSource] selectedPowerDeviceService];
    if (deviceService) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = _NS("Delete Playlist?");
        alert.informativeText = _NS("The playlist will be removed, but its media will remain on the player.");
        [alert addButtonWithTitle:_NS("Delete")];
        [alert addButtonWithTitle:_NS("Cancel")];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
    }
    services_discovery_playlist_item_t request = { [item plItemId] };
    const char *service = deviceService ? deviceService.UTF8String
                                        : "powervlc_library";
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()), service,
        SD_CMD_POWERVLC_PLAYLIST_DELETE, &request);
}

- (void)setPowerVLCRating:(NSMenuItem *)sender
{
    unsigned rating = (unsigned)[sender.representedObject unsignedIntegerValue];
    NSArray *paths = [[self selectedPowerVLCRatings] allKeys];
    if (![paths count])
        return;
    const char **utf8Paths = calloc([paths count], sizeof(*utf8Paths));
    if (!utf8Paths)
        return;
    for (NSUInteger i = 0; i < [paths count]; ++i)
        utf8Paths[i] = [[paths objectAtIndex:i] UTF8String];
    services_discovery_ratings_t request = {
        utf8Paths, [paths count], rating
    };
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()), "powervlc_library",
        SD_CMD_POWERVLC_SET_RATINGS, &request);
    free(utf8Paths);
    [_outlineView setNeedsDisplay:YES];
}

- (NSDictionary *)selectedPowerVLCRatings
{
    NSMutableDictionary *ratings = [NSMutableDictionary dictionary];
    NSIndexSet *rows = [_outlineView selectedRowIndexes];
    [rows enumerateIndexesUsingBlock:^(NSUInteger row, BOOL *stop) {
        VLC_UNUSED(stop);
        VLCCollectRatingsInItem([_outlineView itemAtRow:(NSInteger)row], ratings);
    }];
    return ratings;
}

- (void)outlineView:(NSOutlineView *)outlineView didClickTableColumn:(NSTableColumn *)aTableColumn
{
    int type = 0;
    NSString * identifier = [aTableColumn identifier];

    intf_thread_t *p_intf = getIntf();
    playlist_t *p_playlist = pl_Get(p_intf);

    if (_sortTableColumn == aTableColumn)
        b_isSortDescending = !b_isSortDescending;
    else
        b_isSortDescending = false;

    if (b_isSortDescending)
        type = ORDER_REVERSE;
    else
        type = ORDER_NORMAL;

    [[self model] sortForColumn:identifier withMode:type];

    /* Clear indications of any existing column sorting */
    NSUInteger count = [[_outlineView tableColumns] count];
    for (NSUInteger i = 0 ; i < count ; i++)
        [_outlineView setIndicatorImage:nil inTableColumn: [[_outlineView tableColumns] objectAtIndex:i]];

    [_outlineView setHighlightedTableColumn:nil];
    _sortTableColumn = aTableColumn;
    [_outlineView setHighlightedTableColumn:aTableColumn];

    if (b_isSortDescending)
        [_outlineView setIndicatorImage:_descendingSortingImage inTableColumn:aTableColumn];
    else
        [_outlineView setIndicatorImage:_ascendingSortingImage inTableColumn:aTableColumn];
}


- (void)outlineView:(NSOutlineView *)outlineView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn
               item:(id)item
{
    /* this method can be called when VLC is already dead, hence the extra checks */
    intf_thread_t * p_intf = getIntf();
    if (!p_intf)
        return;

    BOOL b_is_playing = _displayedPlayingItemId == [item plItemId];
    if (!b_is_playing && _displayedPlayingScopeId >= 0
     && [_displayedPlayingURI length]) {
        BOOL insideScope = NO;
        for (VLCPLItem *candidate = item; candidate;
             candidate = [candidate parent])
            if ([candidate plItemId] == _displayedPlayingScopeId) {
                insideScope = YES;
                break;
            }
        if (insideScope) {
            char *uri = input_item_GetURI([item input]);
            if (uri) {
                NSString *candidateURI = [NSString stringWithUTF8String:uri];
                b_is_playing = [candidateURI isEqualToString:
                                                   _displayedPlayingURI];
                free(uri);
            }
        }
    }

    BOOL randomAction = VLCPLItemIsPowerVLCRandomAction(item);
    NSFont *fontToUse = b_is_playing
        ? (randomAction ? _playlistBoldItalicFont : _playlistBoldFont)
        : (randomAction ? _playlistItalicFont : _playlistFont);
    [cell setFont:fontToUse];
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
    VLCPLItem *item = [[notification userInfo] objectForKey:@"NSObject"];
    if (![item isKindOfClass:[VLCPLItem class]])
        return;

    /* The search scope is defined by the open top-level categories.  If the
     * user opens another category while a query is active, include it
     * immediately.  Categories expanded by the search itself are already in
     * _searchScopeItemIds, so they do not recursively restart the search. */
    VLCPLItem *parent = [item parent];
    BOOL isLibraryCategory = parent && [parent parent] == [_model rootItem];
    NSNumber *expandedId = [NSNumber numberWithInt:[item plItemId]];
    if (isLibraryCategory && [_pendingSearchText length]
     && ![_searchScopeItemIds containsObject:expandedId]) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                  selector:@selector(applyDebouncedSearch)
                                                    object:nil];
        [self performSelector:@selector(applyDebouncedSearch)
                   withObject:nil afterDelay:0.0];
    }

    if ([[item children] count] > 0)
        return;

    /* expanding an unbrowsed directory (file browser folder, radio
     * directory country...) sends it to the preparser: its sub-items
     * reach the model through the regular playlist callbacks */
    input_item_t *p_input = [item input];
    if (!p_input || (p_input->i_type != ITEM_TYPE_DIRECTORY
                  && !VLCIsPowerVLCIndexItem(p_input)))
        return;

    /* a directory still childless once its request is surely over
     * (failed fetch) can be retried by folding and unfolding it again */
    NSNumber *itemId = [NSNumber numberWithInt:[item plItemId]];
    NSDate *lastRequest = [_browseRequestedItemIds objectForKey:itemId];
    if (lastRequest && [lastRequest timeIntervalSinceNow] > -150.0)
        return;

    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;
    playlist_t *p_playlist = pl_Get(p_intf);
    PL_LOCK;
    playlist_item_t *p_item = playlist_ItemGetById(p_playlist, [item plItemId]);
    /* i_children on the core item: the view may just be filtering
     * everything out, which is no reason to fetch again */
    if (p_item && p_item->p_input && p_item->i_children <= 0) {
        [_browseRequestedItemIds setObject:[NSDate date] forKey:itemId];
        /* the network scope is required for on-line directories, else the
         * preparser silently skips them; the explicit timeout replaces the
         * 5-second preparse default, far too short for the biggest
         * countries of an on-line radio directory */
        input_item_meta_request_option_t options = META_REQUEST_OPTION_SCOPE_ANY;
        if (VLCIsPowerVLCIndexItem(p_item->p_input))
            options |= META_REQUEST_OPTION_NO_ART;
        libvlc_MetadataRequest(p_intf->obj.libvlc, p_item->p_input,
                               options, 120000, p_item);
    }
    PL_UNLOCK;
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
    VLCPLItem *item = [[notification userInfo] objectForKey:@"NSObject"];
    if (![item isKindOfClass:[VLCPLItem class]])
        return;

    /* Collapsing is a presentation-only operation.  Emptying a lazy index
     * node here used to recursively delete the complete letter/category
     * branch while holding the global playlist lock.  Apart from defeating
     * the in-memory index cache, that made folding a large branch freeze the
     * UI for several seconds and caused the next expansion to hit the disk
     * again.  Keep both completed and in-flight results cached; a failed,
     * still-childless request remains retryable after the normal cooldown in
     * outlineViewItemDidExpand:. */
}

// TODO remove method
- (NSArray *)draggedItems
{
    return [[self model] draggedItems];
}

@end
