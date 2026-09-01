/*****************************************************************************
* VLCSidebarDataSource.m: MacOS X interface module
*****************************************************************************
* Copyright (C) 2021 VLC authors and VideoLAN
* $Id$
*
* Authors: Felix Paul Kühne <fkuehne -at- videolan -dot- org>
*          Jon Lech Johansen <jon-vl@nanocrew.net>
*          Christophe Massiot <massiot@via.ecp.fr>
*          Derk-Jan Hartman <hartman at videolan.org>
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

#import "VLCSidebarDataSource.h"

#import <vlc_services_discovery.h>
#import <vlc_input_item.h>
#import <vlc_playlist.h>
#import <vlc_url.h>

#import "PXSourceList/PXSourceList.h"
#import "PXSourceList/PXSourceListDataSource.h"

#import "CompatibilityFixes.h"

#import "VLCMain.h"
#import "VLCPlaylist.h"
#import "VLCMainWindow.h"
#import "VLCSourceListTableCellView.h"
#import "VLCSourceListItem.h"

#define PVLC_ML_SCAN_ACTIVE "powervlc-ml-scan-active"
#define PVLC_ML_SCAN_DONE   "powervlc-ml-scan-done"
#define PVLC_ML_SCAN_TOTAL  "powervlc-ml-scan-total"

static void VLCCollectAudioCDTracks(playlist_item_t *node,
                                     NSMutableArray *tracks)
{
    if (!node) return;
    if (node->i_children > 0) {
        for (int i = 0; i < node->i_children; i++)
            VLCCollectAudioCDTracks(node->pp_children[i], tracks);
        return;
    }
    if (!node->p_input) return;
    char *uri = input_item_GetURI(node->p_input);
    BOOL isTrack = uri && !strncmp(uri, "cdda://", 7)
                && input_item_GetDuration(node->p_input) > 0;
    free(uri);
    if (isTrack)
        [tracks addObject:[NSValue valueWithPointer:
                           input_item_Hold(node->p_input)]];
}

static NSArray *VLCSidebarFilePathsFromPasteboard(NSPasteboard *pasteboard)
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

static void VLCDeviceTransferStatusClear(services_discovery_transfer_status_t *status)
{
    for (size_t i = 0; i < status->i_count; ++i) {
        free(status->p_items[i].psz_source);
        free(status->p_items[i].psz_destination);
    }
    free(status->p_items);
    memset(status, 0, sizeof(*status));
}

static NSString *VLCDeviceTransferStage(services_discovery_transfer_stage_e stage)
{
    switch (stage) {
        case SD_TRANSFER_QUEUED: return _NS("Queued");
        case SD_TRANSFER_COPYING: return _NS("Copying");
        case SD_TRANSFER_TRANSCODING: return _NS("Transcoding");
        case SD_TRANSFER_COMPLETED: return _NS("Completed");
        case SD_TRANSFER_FAILED: return _NS("Failed");
        case SD_TRANSFER_CANCELLED: return _NS("Cancelled");
    }
    return @"";
}

@interface VLCDeviceTransferWindowController : NSWindowController
    <NSTableViewDataSource, NSWindowDelegate>
@property (copy) NSString *service;
@property (strong) NSArray *rows;
@property (strong) NSTableView *table;
@property (strong) NSTimer *timer;
- (instancetype)initWithService:(NSString *)service title:(NSString *)title;
@end

@implementation VLCDeviceTransferWindowController

- (instancetype)initWithService:(NSString *)service title:(NSString *)title
{
    NSWindow *window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 780, 360)
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                            NSWindowStyleMaskResizable
                    backing:NSBackingStoreBuffered defer:NO];
    self = [super initWithWindow:window];
    if (!self) return nil;
    _service = [service copy];
    window.title = [NSString stringWithFormat:_NS("Transfer History — %@"), title];
    window.delegate = self;
    NSRect bounds = window.contentView.bounds;
    NSScrollView *scroll = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 44, bounds.size.width, bounds.size.height - 44)];
    scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    scroll.hasVerticalScroller = YES;
    _table = [[NSTableView alloc] initWithFrame:scroll.bounds];
    NSArray *identifiers = @[@"source", @"destination", @"stage", @"progress"];
    NSArray *titles = @[_NS("File"), _NS("Destination"), _NS("Step"), _NS("Progress")];
    CGFloat widths[] = { 235, 265, 135, 90 };
    for (NSUInteger i = 0; i < identifiers.count; ++i) {
        NSTableColumn *column = [[NSTableColumn alloc]
            initWithIdentifier:[identifiers objectAtIndex:i]];
        column.title = [titles objectAtIndex:i]; column.width = widths[i];
        [_table addTableColumn:column];
    }
    _table.dataSource = self;
    _table.usesAlternatingRowBackgroundColors = YES;
    scroll.documentView = _table;
    [window.contentView addSubview:scroll];
    NSButton *cancelSelected = [[NSButton alloc]
        initWithFrame:NSMakeRect(12, 8, 180, 28)];
    cancelSelected.title = _NS("Cancel Selected Transfer");
    cancelSelected.bezelStyle = NSBezelStyleRounded;
    cancelSelected.target = self;
    cancelSelected.action = @selector(cancelSelected:);
    cancelSelected.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [window.contentView addSubview:cancelSelected];
    NSButton *cancelAll = [[NSButton alloc]
        initWithFrame:NSMakeRect(202, 8, 150, 28)];
    cancelAll.title = _NS("Cancel All Transfers");
    cancelAll.bezelStyle = NSBezelStyleRounded;
    cancelAll.target = self;
    cancelAll.action = @selector(cancelAll:);
    cancelAll.autoresizingMask = NSViewMaxXMargin | NSViewMaxYMargin;
    [window.contentView addSubview:cancelAll];
    [window center];
    [self refresh:nil];
    _timer = [NSTimer scheduledTimerWithTimeInterval:0.25 target:self
        selector:@selector(refresh:) userInfo:nil repeats:YES];
    return self;
}

- (void)cancelSelected:(id)sender
{
    NSInteger row = self.table.selectedRow;
    if (row < 0 || (NSUInteger)row >= self.rows.count) return;
    services_discovery_transfer_cancel_t request = {
        .i_id = [[[self.rows objectAtIndex:(NSUInteger)row]
                   objectForKey:@"id"] unsignedLongLongValue]
    };
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()), self.service.UTF8String,
        SD_CMD_POWERVLC_DEVICE_CANCEL_TRANSFER, &request);
    [self refresh:nil];
}

- (void)cancelAll:(id)sender
{
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()), self.service.UTF8String,
                                      SD_CMD_POWERVLC_DEVICE_CANCEL_ALL);
    [self refresh:nil];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{ return self.rows.count; }

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column
            row:(NSInteger)row
{
    return [[self.rows objectAtIndex:(NSUInteger)row]
            objectForKey:column.identifier];
}

- (void)refresh:(NSTimer *)timer
{
    services_discovery_transfer_status_t status = { 0 };
    if (playlist_ServicesDiscoveryControl(pl_Get(getIntf()), self.service.UTF8String,
            SD_CMD_POWERVLC_DEVICE_TRANSFERS, &status) != VLC_SUCCESS)
        return;
    NSMutableArray *rows = [NSMutableArray arrayWithCapacity:status.i_count];
    for (size_t n = status.i_count; n > 0; --n) {
        services_discovery_transfer_item_t *item = &status.p_items[n - 1];
        NSString *source = toNSStr(item->psz_source ?: "");
        NSString *destination = toNSStr(item->psz_destination ?: "");
        [rows addObject:@{
            @"id": @(item->i_id),
            @"source": source.lastPathComponent ?: source,
            @"destination": destination,
            @"stage": VLCDeviceTransferStage(item->i_stage),
            @"progress": [NSString stringWithFormat:@"%u %%", item->i_progress]
        }];
    }
    self.rows = rows;
    [self.table reloadData];
    VLCDeviceTransferStatusClear(&status);
}

- (void)windowWillClose:(NSNotification *)notification
{ [self.timer invalidate]; self.timer = nil; }

@end

@interface VLCSidebarDataSource() <PXSourceListDataSource, PXSourceListDelegate>
{
    NSMutableArray *o_sidebaritems;
    NSMutableArray *_networkItems;
    NSMutableDictionary *_deviceBaseTitles;
    NSMutableDictionary *_transferWindows;
    NSTimer *_deviceStatusTimer;
    VLCSourceListItem *_powerLibraryItem;
}

@end

@implementation VLCSidebarDataSource

- (id)init
{
    self = [super init];
    if (self) {
        _networkItems = [[NSMutableArray alloc] init];
        _deviceBaseTitles = [[NSMutableDictionary alloc] init];
        _transferWindows = [[NSMutableDictionary alloc] init];
        _deviceStatusTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
            target:self selector:@selector(updateDeviceTransferState:)
            userInfo:nil repeats:YES];
    }
    return self;
}

- (void)dealloc
{ [_deviceStatusTimer invalidate]; }

- (void)reloadSidebar
{
    BOOL isAReload = NO;
    if (o_sidebaritems)
        isAReload = YES;

    BOOL darkMode = NO;
    if (@available(macOS 10.14, *)) {
        NSApplication *app = [NSApplication sharedApplication];
        if ([app.effectiveAppearance.name isEqualToString:NSAppearanceNameDarkAqua]) {
            darkMode = YES;
        }
    }

    o_sidebaritems = [[NSMutableArray alloc] init];
    VLCSourceListItem *libraryItem = [VLCSourceListItem itemWithTitle:_NS("LIBRARY") identifier:@"library"];
    VLCSourceListItem *playlistItem = [VLCSourceListItem itemWithTitle:_NS("Playlist") identifier:@"playlist"];
    [playlistItem setIcon: sidebarImageFromRes(@"sidebar-playlist", darkMode)];
    VLCSourceListItem *medialibraryItem = [VLCSourceListItem itemWithTitle:_NS("Catch-all Media Library") identifier:@"medialibrary"];
    [medialibraryItem setIcon: sidebarImageFromRes(@"sidebar-playlist", darkMode)];
    VLCSourceListItem *powerLibraryItem = [VLCSourceListItem itemWithTitle:_NS("Media Library") identifier:@"powervlc_library"];
    _powerLibraryItem = powerLibraryItem;
    [powerLibraryItem setIcon: sidebarImageFromRes(@"sidebar-playlist", darkMode)];
    [powerLibraryItem setSdtype: SD_CAT_MYCOMPUTER];
    VLCSourceListItem *mycompItem = [VLCSourceListItem itemWithTitle:_NS("MY COMPUTER") identifier:@"mycomputer"];
    VLCSourceListItem *devicesItem = [VLCSourceListItem itemWithTitle:_NS("DEVICES") identifier:@"devices"];
    VLCSourceListItem *lanItem = [VLCSourceListItem itemWithTitle:_NS("LOCAL NETWORK") identifier:@"localnetwork"];
    VLCSourceListItem *internetItem = [VLCSourceListItem itemWithTitle:_NS("INTERNET") identifier:@"internet"];

    /* SD subnodes, inspired by the Qt intf */
    char **ppsz_longnames = NULL;
    int *p_categories = NULL;
    char **ppsz_names = vlc_sd_GetNames(pl_Get(getIntf()), &ppsz_longnames, &p_categories);
    if (!ppsz_names)
        msg_Err(getIntf(), "no sd item found"); //TODO
    char **ppsz_name = ppsz_names, **ppsz_longname = ppsz_longnames;
    int *p_category = p_categories;
    NSMutableArray *internetItems = [[NSMutableArray alloc] init];
    NSMutableArray *devicesItems = [[NSMutableArray alloc] init];
    NSMutableArray *lanItems = [[NSMutableArray alloc] init];
    NSMutableArray *mycompItems = [[NSMutableArray alloc] init];
    [_deviceBaseTitles removeAllObjects];
    NSString *o_identifier;
    for (; ppsz_name && *ppsz_name; ppsz_name++, ppsz_longname++, p_category++) {
        o_identifier = toNSStr(*ppsz_name);
        if (!strcmp(*ppsz_name, "powervlc_library")) {
            free(*ppsz_name);
            free(*ppsz_longname);
            continue;
        }
        switch (*p_category) {
            case SD_CAT_INTERNET:
                [internetItems addObject: [VLCSourceListItem itemWithTitle: _NS(*ppsz_longname) identifier: o_identifier]];
                [[internetItems lastObject] setIcon: sidebarImageFromRes(@"sidebar-podcast", darkMode)];
                [[internetItems lastObject] setSdtype: SD_CAT_INTERNET];
                break;
            case SD_CAT_DEVICES:
                if (!strcmp(*ppsz_name, "disc")) {
                    [mycompItems addObject:[VLCSourceListItem itemWithTitle:
                        _NS(*ppsz_longname) identifier:o_identifier]];
                    [[mycompItems lastObject] setIcon:sidebarImageFromRes(@"sidebar-local", darkMode)];
                    [[mycompItems lastObject] setSdtype:SD_CAT_DEVICES];
                } else {
                    [devicesItems addObject: [VLCSourceListItem itemWithTitle: _NS(*ppsz_longname) identifier: o_identifier]];
                    if ([o_identifier hasPrefix:@"powervlc_device{"]) {
                        [_deviceBaseTitles setObject:_NS(*ppsz_longname)
                                             forKey:o_identifier];
                        [[devicesItems lastObject]
                            setServiceRootTitle:_NS(*ppsz_longname)];
                    }
                    [[devicesItems lastObject] setIcon: sidebarImageFromRes(@"sidebar-local", darkMode)];
                    [[devicesItems lastObject] setSdtype: SD_CAT_DEVICES];
                }
                break;
            case SD_CAT_LAN:
                [lanItems addObject: [VLCSourceListItem itemWithTitle: _NS(*ppsz_longname) identifier: o_identifier]];
                [[lanItems lastObject] setIcon: sidebarImageFromRes(@"sidebar-local", darkMode)];
                [[lanItems lastObject] setSdtype: SD_CAT_LAN];
                break;
            case SD_CAT_MYCOMPUTER:
                [mycompItems addObject: [VLCSourceListItem itemWithTitle: _NS(*ppsz_longname) identifier: o_identifier]];
                if (!strncmp(*ppsz_name, "video_dir", 9))
                    [[mycompItems lastObject] setIcon: sidebarImageFromRes(@"sidebar-movie", darkMode)];
                else if (!strncmp(*ppsz_name, "audio_dir", 9))
                    [[mycompItems lastObject] setIcon: sidebarImageFromRes(@"sidebar-music", darkMode)];
                else if (!strncmp(*ppsz_name, "picture_dir", 11))
                    [[mycompItems lastObject] setIcon: sidebarImageFromRes(@"sidebar-pictures", darkMode)];
                else
                    [[mycompItems lastObject] setIcon: [NSImage imageNamed:@"NSApplicationIcon"]];
                [[mycompItems lastObject] setSdtype: SD_CAT_MYCOMPUTER];
                break;
            default:
                msg_Warn(getIntf(), "unknown SD type found, skipping (%s)", *ppsz_name);
                break;
        }

        free(*ppsz_name);
        free(*ppsz_longname);
    }
    [mycompItems addObjectsFromArray:_networkItems];
    [mycompItem setChildren: [NSArray arrayWithArray: mycompItems]];
    [devicesItem setChildren: [NSArray arrayWithArray: devicesItems]];
    [lanItem setChildren: [NSArray arrayWithArray: lanItems]];
    [internetItem setChildren: [NSArray arrayWithArray: internetItems]];
    free(ppsz_names);
    free(ppsz_longnames);
    free(p_categories);

    [libraryItem setChildren: [NSArray arrayWithObjects:playlistItem,
                               medialibraryItem, powerLibraryItem, nil]];
    [o_sidebaritems addObject: libraryItem];
    if ([mycompItem hasChildren])
        [o_sidebaritems addObject: mycompItem];
    if ([devicesItem hasChildren])
        [o_sidebaritems addObject: devicesItem];
    if ([lanItem hasChildren])
        [o_sidebaritems addObject: lanItem];
    if ([internetItem hasChildren])
        [o_sidebaritems addObject: internetItem];

    [_sidebarView reloadData];
    [_sidebarView setDropItem:playlistItem dropChildIndex:NSOutlineViewDropOnItemIndex];
    [_sidebarView setDropItem:powerLibraryItem dropChildIndex:NSOutlineViewDropOnItemIndex];
    [_sidebarView registerForDraggedTypes:@[NSFilenamesPboardType,
                                             NSURLPboardType,
                                             @"VLCPlaylistItemPboardType"]];

    [_sidebarView setDataSource:self];
    [_sidebarView setDelegate:self];

    [_sidebarView expandItem:libraryItem expandChildren:YES];

    if (isAReload) {
        [_sidebarView expandItem:nil expandChildren:YES];
    }
}

- (void)updateDeviceTransferState:(NSTimer *)timer
{
    playlist_t *playlist = pl_Get(getIntf());
    BOOL scanActive = var_GetBool(getIntf()->obj.libvlc, PVLC_ML_SCAN_ACTIVE);
    uint64_t scanDone = var_GetInteger(getIntf()->obj.libvlc, PVLC_ML_SCAN_DONE);
    uint64_t scanTotal = var_GetInteger(getIntf()->obj.libvlc, PVLC_ML_SCAN_TOTAL);
    NSString *libraryTitle = _NS("Media Library");
    if (scanActive) {
        if (scanTotal > 0) {
            uint64_t remaining = scanTotal > scanDone ? scanTotal - scanDone : 0;
            unsigned percent = (unsigned)MIN(100, (scanDone * 100) / scanTotal);
            libraryTitle = [NSString stringWithFormat:
                remaining == 1
                    ? _NS("Media Library — scanning %u%% · %llu file remaining")
                    : _NS("Media Library — scanning %u%% · %llu files remaining"),
                percent, (unsigned long long)remaining];
        } else {
            libraryTitle = [NSString stringWithFormat:
                scanDone == 1
                    ? _NS("Media Library — scanning… · %llu file indexed")
                    : _NS("Media Library — scanning… · %llu files indexed"),
                (unsigned long long)scanDone];
        }
    }
    if (_powerLibraryItem && ![_powerLibraryItem.title isEqualToString:libraryTitle]) {
        _powerLibraryItem.title = libraryTitle;
        [_sidebarView reloadItem:_powerLibraryItem];
        NSInteger selected = _sidebarView.selectedRow;
        if (selected >= 0 && [_sidebarView itemAtRow:selected] == _powerLibraryItem)
            [[[[VLCMain sharedInstance] mainWindow] categoryLabel]
                setStringValue:libraryTitle];
    }
    BOOL selectedDeviceDeleting = NO;
    for (VLCSourceListItem *group in o_sidebaritems) {
        for (VLCSourceListItem *item in group.children) {
            NSString *service = item.identifier;
            NSString *base = [_deviceBaseTitles objectForKey:service];
            if (!base) continue;
            BOOL synchronizing = NO;
            BOOL pendingChanges = NO;
            BOOL commitFailed = NO;
            unsigned activity = SD_DEVICE_IDLE;
            uint64_t totalBytes = 0, freeBytes = 0;
            if (playlist_IsServicesDiscoveryLoaded(playlist, service.UTF8String)) {
                services_discovery_transfer_status_t status = { 0 };
                if (playlist_ServicesDiscoveryControl(playlist, service.UTF8String,
                        SD_CMD_POWERVLC_DEVICE_TRANSFERS, &status) == VLC_SUCCESS) {
                    synchronizing = status.b_synchronizing;
                    pendingChanges = status.b_pending_changes;
                    commitFailed = status.b_commit_failed;
                    activity = status.i_activity;
                    totalBytes = status.i_total_bytes;
                    freeBytes = status.i_free_bytes;
                }
                VLCDeviceTransferStatusClear(&status);
            }
            NSString *operation = nil;
            if (activity == SD_DEVICE_LOADING_ITUNESDB)
                operation = _NS("Loading iTunesDB…");
            else if (activity == SD_DEVICE_LOADING_CONTENTS)
                operation = _NS("Loading contents…");
            else if (activity == SD_DEVICE_UPDATING_ITUNESDB)
                operation = _NS("Updating iTunesDB…");
            else if (activity == SD_DEVICE_DELETING)
                operation = _NS("Deleting…");
            else if (synchronizing)
                operation = _NS("Synchronizing");
            else if (commitFailed)
                operation = _NS("Finalization failed — changes still pending");
            else if (pendingChanges)
                operation = _NS("Changes pending finalization");
            NSString *title = operation
                ? [base stringByAppendingFormat:@" (%@)", operation] : base;
            if (totalBytes > 0) {
                unsigned percent = (unsigned)((freeBytes * 100) / totalBytes);
                title = [title stringByAppendingFormat:@" — %.1f GB %@ %.1f GB (%u%%)",
                    (double)freeBytes / 1000000000., _NS("free of"),
                    (double)totalBytes / 1000000000., percent];
            }
            if (![item.title isEqualToString:title]) {
                item.title = title;
                [_sidebarView reloadItem:item];
                NSInteger selected = _sidebarView.selectedRow;
                if (selected >= 0 && [_sidebarView itemAtRow:selected] == item)
                    [[[[VLCMain sharedInstance] mainWindow] categoryLabel]
                        setStringValue:title];
            }
            NSInteger selected = _sidebarView.selectedRow;
            if (selected >= 0 && [_sidebarView itemAtRow:selected] == item
             && activity == SD_DEVICE_DELETING)
                selectedDeviceDeleting = YES;
        }
    }
    [[[[VLCMain sharedInstance] mainWindow] outlineView]
        setEnabled:!selectedDeviceDeleting];
}

- (BOOL)addNetworkLocation:(NSString *)mrl
{
    for (VLCSourceListItem *item in _networkItems) {
        if ([item.networkMRL isEqualToString:mrl]) {
            [self reloadSidebar];
            [_sidebarView expandItem:nil expandChildren:YES];
            NSInteger row = [_sidebarView rowForItem:item];
            if (row >= 0)
                [_sidebarView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                          byExtendingSelection:NO];
            return YES;
        }
    }

    NSURL *url = [NSURL URLWithString:mrl];
    NSString *title = [url host];
    NSString *pathName = [[url path] lastPathComponent];
    if ([pathName length] > 0)
        title = [NSString stringWithFormat:@"%@ — %@", title, pathName];
    if (![title length])
        title = mrl;

    input_item_t *input = input_item_NewDirectory([mrl UTF8String],
                                                   [title UTF8String], ITEM_NET);
    if (!input)
        return NO;

    playlist_t *p_playlist = pl_Get(getIntf());
    PL_LOCK;
    playlist_item_t *playlistItem = playlist_NodeAddInput(p_playlist, input,
                                                           &p_playlist->root,
                                                           PLAYLIST_END);
    NSInteger itemId = playlistItem ? playlistItem->i_id : -1;
    if (playlistItem)
        libvlc_MetadataRequest(getIntf()->obj.libvlc, input,
                               META_REQUEST_OPTION_SCOPE_ANY |
                               META_REQUEST_OPTION_DO_INTERACT, 120000,
                               playlistItem);
    PL_UNLOCK;
    input_item_Release(input);
    if (itemId < 0)
        return NO;

    VLCSourceListItem *sidebarItem = [VLCSourceListItem
        itemWithTitle:title identifier:[NSString stringWithFormat:@"network-%ld",
                                        (long)itemId]];
    sidebarItem.icon = sidebarImageFromRes(@"sidebar-local", NO);
    sidebarItem.playlistItemId = itemId;
    sidebarItem.networkMRL = mrl;
    [_networkItems addObject:sidebarItem];

    [self reloadSidebar];
    [_sidebarView expandItem:nil expandChildren:YES];
    NSInteger row = [_sidebarView rowForItem:sidebarItem];
    if (row >= 0)
        [_sidebarView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSUInteger)row]
                  byExtendingSelection:NO];
    [[_sidebarView window] makeKeyAndOrderFront:nil];
    return YES;
}

- (NSString *)selectedPowerDeviceService
{
    NSInteger row = _sidebarView.selectedRow;
    if (row < 0) return nil;
    VLCSourceListItem *item = [_sidebarView itemAtRow:row];
    NSString *service = item.identifier;
    return [service hasPrefix:@"powervlc_device{"] ? service : nil;
}

- (IBAction)ejectNetworkLocation:(id)sender
{
    VLCSourceListItem *item = [sender representedObject];
    if (![item isKindOfClass:[VLCSourceListItem class]] || item.playlistItemId < 0)
        return;

    playlist_t *p_playlist = pl_Get(getIntf());
    PL_LOCK;
    [[[[VLCMain sharedInstance] playlist] model] changeRootItem:p_playlist->p_playing];
    playlist_item_t *playlistItem = playlist_ItemGetById(p_playlist,
                                                          (int)item.playlistItemId);
    if (playlistItem)
        playlist_NodeDelete(p_playlist, playlistItem);
    PL_UNLOCK;

    [_networkItems removeObjectIdenticalTo:item];
    [self reloadSidebar];
    [_sidebarView selectRowIndexes:[NSIndexSet indexSetWithIndex:1]
              byExtendingSelection:NO];
}

#pragma mark -
#pragma mark Side Bar Data handling
/* taken under BSD-new from the PXSourceList sample project, adapted for VLC */
- (NSUInteger)sourceList:(PXSourceList*)sourceList numberOfChildrenOfItem:(id)item
{
    //Works the same way as the NSOutlineView data source: `nil` means a parent item
    if (item==nil)
        return [o_sidebaritems count];
    else
        return [[item children] count];
}


- (id)sourceList:(PXSourceList*)aSourceList child:(NSUInteger)index ofItem:(id)item
{
    //Works the same way as the NSOutlineView data source: `nil` means a parent item
    if (item==nil)
        return [o_sidebaritems objectAtIndex:index];
    else
        return [[item children] objectAtIndex:index];
}

- (BOOL)sourceList:(PXSourceList*)aSourceList isItemExpandable:(id)item
{
    return [item hasChildren];
}

- (BOOL)sourceList:(PXSourceList*)aSourceList itemHasIcon:(id)item
{
    return ([item icon] != nil);
}


- (NSImage*)sourceList:(PXSourceList*)aSourceList iconForItem:(id)item
{
    return [item icon];
}

- (NSMenu*)sourceList:(PXSourceList*)aSourceList menuForEvent:(NSEvent*)theEvent item:(id)item
{
    if ([theEvent type] == NSRightMouseDown || ([theEvent type] == NSLeftMouseDown && ([theEvent modifierFlags] & NSControlKeyMask) == NSControlKeyMask)) {
        if (item != nil) {
            if ([item playlistItemId] >= 0)
            {
                NSMenu *m = [[NSMenu alloc] init];
                NSMenuItem *eject = [m addItemWithTitle:_NS("Eject")
                                                  action:@selector(ejectNetworkLocation:)
                                           keyEquivalent:@""];
                [eject setTarget:self];
                [eject setRepresentedObject:item];
                return m;
            }
            if ([item sdtype] > 0)
            {
                NSMenu *m = [[NSMenu alloc] init];
                playlist_t * p_playlist = pl_Get(getIntf());
                BOOL sd_loaded = playlist_IsServicesDiscoveryLoaded(p_playlist, [[item identifier] UTF8String]);
                if ([[item identifier] isEqualToString:@"powervlc_library"] && sd_loaded) {
                    NSMenuItem *rescan = [m addItemWithTitle:_NS("Rescan Media Library")
                                                     action:@selector(rescanPowerVLCLibrary:)
                                              keyEquivalent:@""];
                    [rescan setTarget:self];
                    return m;
                }
                if ([[item identifier] hasPrefix:@"powervlc_device{"] && sd_loaded) {
                    NSMenuItem *commit = [m addItemWithTitle:_NS("Finalize Changes")
                                                      action:@selector(commitPowerVLCDeviceChanges:)
                                               keyEquivalent:@""];
                    [commit setTarget:self];
                    [commit setRepresentedObject:[item identifier]];
                    services_discovery_transfer_status_t status = { 0 };
                    BOOL statusOK = playlist_ServicesDiscoveryControl(
                        p_playlist, [[item identifier] UTF8String],
                        SD_CMD_POWERVLC_DEVICE_TRANSFERS,
                        &status) == VLC_SUCCESS;
                    [commit setEnabled:statusOK && status.b_pending_changes
                                             && !status.b_synchronizing];
                    VLCDeviceTransferStatusClear(&status);
                    [m addItem:[NSMenuItem separatorItem]];
                    NSMenuItem *history = [m addItemWithTitle:_NS("Transfer History…")
                                                      action:@selector(showPowerVLCDeviceTransfers:)
                                               keyEquivalent:@""];
                    [history setTarget:self];
                    [history setRepresentedObject:item];
                    [m addItem:[NSMenuItem separatorItem]];
                    NSMenuItem *backup = [m addItemWithTitle:_NS("Back Up…")
                                                      action:@selector(backupPowerVLCDevices:)
                                               keyEquivalent:@""];
                    [backup setTarget:self];
                    [backup setRepresentedObject:[item identifier]];
                    [m addItem:[NSMenuItem separatorItem]];
                    NSMenuItem *refresh = [m addItemWithTitle:_NS("Refresh")
                                                       action:@selector(refreshPowerVLCDevices:)
                                                keyEquivalent:@""];
                    [refresh setTarget:self];
                    [refresh setRepresentedObject:[item identifier]];
                    return m;
                }
                if ([[item identifier] isEqualToString:@"disc"] && sd_loaded) {
                    NSMenuItem *import = [m addItemWithTitle:
                        _NS("Import Audio CD into Media Library")
                        action:@selector(importPowerVLCAudioCD:)
                        keyEquivalent:@""];
                    [import setTarget:self];
                    return m;
                }
                if (!sd_loaded)
                    [m addItemWithTitle:_NS("Enable") action:@selector(sdmenuhandler:) keyEquivalent:@""];
                else
                    [m addItemWithTitle:_NS("Disable") action:@selector(sdmenuhandler:) keyEquivalent:@""];
                [[m itemAtIndex:0] setRepresentedObject: [item identifier]];
                return m;
            }
        }
    }

    return nil;
}

- (IBAction)showPowerVLCDeviceTransfers:(id)sender
{
    VLCSourceListItem *item = [sender representedObject];
    NSString *service = item.identifier;
    VLCDeviceTransferWindowController *controller =
        [_transferWindows objectForKey:service];
    if (!controller || !controller.window.visible) {
        NSString *title = [_deviceBaseTitles objectForKey:service] ?: item.title;
        controller = [[VLCDeviceTransferWindowController alloc]
                       initWithService:service title:title];
        [_transferWindows setObject:controller forKey:service];
    }
    [controller showWindow:nil];
    [controller.window makeKeyAndOrderFront:nil];
}

- (IBAction)rescanPowerVLCLibrary:(id)sender
{
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()), "powervlc_library",
                                       SD_CMD_POWERVLC_RESCAN);
}

- (IBAction)refreshPowerVLCDevices:(id)sender
{
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()),
                                       [[sender representedObject] UTF8String],
                                       SD_CMD_POWERVLC_RESCAN);
}

- (IBAction)commitPowerVLCDeviceChanges:(id)sender
{
    int result = playlist_ServicesDiscoveryControl(pl_Get(getIntf()),
        [[sender representedObject] UTF8String], SD_CMD_POWERVLC_DEVICE_COMMIT);
    if (result != VLC_SUCCESS) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.alertStyle = NSAlertStyleWarning;
        alert.messageText = _NS("Unable to Finalize Changes");
        alert.informativeText = _NS("The portable player is unavailable. Your changes remain pending and can be validated after reconnecting it.");
        [alert runModal];
    }
}

- (IBAction)backupPowerVLCDevices:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.canCreateDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.message = _NS("Choose Backup Folder");
    if ([panel runModal] != NSOKButton)
        return;
    playlist_ServicesDiscoveryControl(pl_Get(getIntf()),
        [[sender representedObject] UTF8String],
        SD_CMD_POWERVLC_DEVICE_BACKUP, [[[panel URL] path] fileSystemRepresentation]);
}

- (IBAction)importPowerVLCAudioCD:(id)sender
{
    NSMutableArray *tracks = [NSMutableArray array];
    playlist_t *p_playlist = pl_Get(getIntf());
    PL_LOCK;
    VLCCollectAudioCDTracks(&p_playlist->root, tracks);
    PL_UNLOCK;
    if (![tracks count]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = _NS("Import Audio CD");
        alert.informativeText = _NS("Open the Audio CD once so its tracks are displayed, then run the import again.");
        [alert runModal];
        return;
    }
    if (!playlist_IsServicesDiscoveryLoaded(p_playlist, "powervlc_library")
     && playlist_ServicesDiscoveryAdd(p_playlist, "powervlc_library") != VLC_SUCCESS) {
        for (NSValue *value in tracks)
            input_item_Release([value pointerValue]);
        return;
    }
    NSUInteger imported = 0;
    for (NSValue *value in tracks) {
        input_item_t *track = [value pointerValue];
        char *uri = input_item_GetURI(track);
        char *title = input_item_GetTitleFbName(track);
        char *artist = input_item_GetMeta(track, vlc_meta_Artist);
        char *album = input_item_GetMeta(track, vlc_meta_Album);
        services_discovery_import_t request = { uri, title, artist, album, track };
        if (playlist_ServicesDiscoveryControl(p_playlist, "powervlc_library",
              SD_CMD_POWERVLC_IMPORT, &request) == VLC_SUCCESS) imported++;
        free(uri); free(title); free(artist); free(album);
        input_item_Release(track);
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Import Audio CD");
    alert.informativeText = [NSString stringWithFormat:
        _NS("%lu tracks are being imported as lossless FLAC files in the managed library."),
        (unsigned long)imported];
    [alert runModal];
}

#pragma mark -
#pragma mark Side Bar Delegate Methods
/* taken under BSD-new from the PXSourceList sample project, adapted for VLC */
- (BOOL)sourceList:(PXSourceList*)aSourceList isGroupAlwaysExpanded:(id)group
{
    if ([[group identifier] isEqualToString:@"library"])
        return YES;

    return NO;
}

- (void)sourceListSelectionDidChange:(NSNotification *)notification
{
    [(VLCMainWindow *)[_sidebarView window] sourceListSelectionDidChange:notification];
}

- (NSView *)sourceList:(PXSourceList *)aSourceList viewForItem:(id)item
{
    PXSourceListItem *sourceListItem = item;

    if ([aSourceList levelForItem:item] == 0) {
        PXSourceListTableCellView *cellView = [aSourceList makeViewWithIdentifier:@"HeaderCell" owner:nil];

        cellView.textField.editable = NO;
        cellView.textField.selectable = NO;
        cellView.textField.stringValue = sourceListItem.title ? sourceListItem.title : @"";

        return cellView;
    }

    VLCSourceListTableCellView * cellView = [aSourceList makeViewWithIdentifier:@"DataCell" owner:nil];

    cellView.textField.editable = NO;
    cellView.textField.selectable = NO;
    cellView.textField.stringValue = sourceListItem.title ? sourceListItem.title : @"";
    cellView.imageView.image = [sourceListItem icon];

    // Badge count
    {
        playlist_t *p_playlist = pl_Get(getIntf());
        playlist_item_t *p_pl_item = NULL;
        NSInteger i_playlist_size = 0;

        if ([[sourceListItem identifier] isEqualToString: @"playlist"]) {
            p_pl_item = p_playlist->p_playing;
        } else if ([[sourceListItem identifier] isEqualToString: @"medialibrary"]) {
            p_pl_item = p_playlist->p_media_library;
        }

        PL_LOCK;
        if (p_pl_item)
            i_playlist_size = p_pl_item->i_children;
        PL_UNLOCK;

        if (p_pl_item) {
            cellView.badgeView.integerValue = i_playlist_size;
        } else {
            cellView.badgeView.integerValue = sourceListItem.badgeValue.integerValue;
        }
    }

    return cellView;
}

- (NSDragOperation)sourceList:(PXSourceList *)aSourceList validateDrop:(id <NSDraggingInfo>)info proposedItem:(id)item proposedChildIndex:(NSInteger)index
{
    if ([[item identifier] isEqualToString:@"playlist"]
     || [[item identifier] isEqualToString:@"medialibrary"]
     || [[item identifier] isEqualToString:@"powervlc_library"]
     || [[item identifier] hasPrefix:@"powervlc_device{"]) {
        NSPasteboard *o_pasteboard = [info draggingPasteboard];
        if ([[o_pasteboard types] containsObject: VLCPLItemPasteboadType]
         || [VLCSidebarFilePathsFromPasteboard(o_pasteboard) count] > 0)
            return NSDragOperationGeneric;
    }
    return NSDragOperationNone;
}

- (BOOL)sourceList:(PXSourceList *)aSourceList acceptDrop:(id <NSDraggingInfo>)info item:(id)item childIndex:(NSInteger)index
{
    NSPasteboard *o_pasteboard = [info draggingPasteboard];

    playlist_t * p_playlist = pl_Get(getIntf());
    playlist_item_t *p_node;

    if ([[item identifier] hasPrefix:@"powervlc_device{"]) {
        NSString *service = [item identifier];
        if (!playlist_IsServicesDiscoveryLoaded(p_playlist, [service UTF8String])
         && playlist_ServicesDiscoveryAdd(p_playlist, [service UTF8String])
                                                        != VLC_SUCCESS)
            return NO;
        NSMutableArray *paths = [NSMutableArray array];
        NSMutableDictionary *inputsByPath = [NSMutableDictionary dictionary];
        if ([[o_pasteboard types] containsObject:VLCPLItemPasteboadType]) {
            NSArray *dragged = [[[VLCMain sharedInstance] playlist] draggedItems];
            PL_LOCK;
            for (id draggedItem in dragged) {
                playlist_item_t *playlistItem = playlist_ItemGetById(
                    p_playlist, [draggedItem plItemId]);
                char *uri = playlistItem && playlistItem->p_input
                          ? input_item_GetURI(playlistItem->p_input) : NULL;
                char *path = uri ? vlc_uri2path(uri) : NULL;
                free(uri);
                if (path) {
                    NSString *sourcePath = toNSStr(path);
                    [paths addObject:sourcePath];
                    if (playlistItem->p_input) {
                        input_item_Hold(playlistItem->p_input);
                        NSValue *old = [inputsByPath objectForKey:sourcePath];
                        if (old) input_item_Release([old pointerValue]);
                        [inputsByPath setObject:[NSValue valueWithPointer:
                                                playlistItem->p_input]
                                         forKey:sourcePath];
                    }
                    free(path);
                }
            }
            PL_UNLOCK;
        }
        for (NSString *path in VLCSidebarFilePathsFromPasteboard(o_pasteboard))
            if (![paths containsObject:path]) [paths addObject:path];
        BOOL queued = NO;
        for (NSString *path in paths) {
            input_item_t *input = [[inputsByPath objectForKey:path] pointerValue];
            services_discovery_import_t request = {
                [path fileSystemRepresentation], NULL, NULL, NULL, input
            };
            if (playlist_ServicesDiscoveryControl(p_playlist,
                    [service UTF8String], SD_CMD_POWERVLC_DEVICE_ADD,
                    &request) == VLC_SUCCESS)
                queued = YES;
        }
        for (NSValue *value in [inputsByPath allValues])
            input_item_Release([value pointerValue]);
        return queued;
    }

    if ([[item identifier] isEqualToString:@"powervlc_library"]) {
        if (!playlist_IsServicesDiscoveryLoaded(p_playlist, "powervlc_library")
         && playlist_ServicesDiscoveryAdd(p_playlist, "powervlc_library") != VLC_SUCCESS)
            return NO;
        NSMutableArray *paths = [NSMutableArray array];
        if ([[o_pasteboard types] containsObject:@"VLCPlaylistItemPboardType"]) {
            NSArray *dragged = [[[VLCMain sharedInstance] playlist] draggedItems];
            PL_LOCK;
            for (id draggedItem in dragged) {
                playlist_item_t *playlistItem = playlist_ItemGetById(
                    p_playlist, [draggedItem plItemId]);
                char *path = playlistItem && playlistItem->p_input
                           ? vlc_uri2path(playlistItem->p_input->psz_uri) : NULL;
                if (path) {
                    [paths addObject:toNSStr(path)];
                    free(path);
                }
            }
            PL_UNLOCK;
        }
        for (NSString *path in VLCSidebarFilePathsFromPasteboard(o_pasteboard))
            if (![paths containsObject:path]) [paths addObject:path];
        BOOL imported = NO;
        for (NSString *path in paths) {
            services_discovery_import_t request = {
                [path fileSystemRepresentation], NULL, NULL, NULL, NULL
            };
            if (playlist_ServicesDiscoveryControl(p_playlist,
                    "powervlc_library", SD_CMD_POWERVLC_IMPORT,
                    &request) == VLC_SUCCESS)
                imported = YES;
        }
        return imported;
    }

    if ([[item identifier] isEqualToString:@"playlist"])
        p_node = p_playlist->p_playing;
    else
        p_node = p_playlist->p_media_library;

    if ([[o_pasteboard types] containsObject: @"VLCPlaylistItemPboardType"]) {
        NSArray * array = [[[VLCMain sharedInstance] playlist] draggedItems];

        NSUInteger count = [array count];

        PL_LOCK;
        for(NSUInteger i = 0; i < count; i++) {
            playlist_item_t *p_item = playlist_ItemGetById(p_playlist, [[array objectAtIndex:i] plItemId]);
            if (!p_item) continue;
            playlist_NodeAddCopy(p_playlist, p_item, p_node, PLAYLIST_END);
        }
        PL_UNLOCK;

        return YES;
    }

    // check if dropped item is a file
    NSArray *items = [[[VLCMain sharedInstance] playlist] createItemsFromExternalPasteboard:o_pasteboard];
    if (items.count == 0)
        return NO;

    [[[VLCMain sharedInstance] playlist] addPlaylistItems:items
                                         withParentItemId:p_node->i_id
                                                    atPos:-1
                                            startPlayback:NO];
    return YES;
}

- (id)sourceList:(PXSourceList *)aSourceList persistentObjectForItem:(id)item
{
    return [item identifier];
}

- (id)sourceList:(PXSourceList *)aSourceList itemForPersistentObject:(id)object
{
    /* the following code assumes for sakes of simplicity that only the top level
     * items are allowed to have children */

    NSArray * array = [NSArray arrayWithArray: o_sidebaritems]; // read-only arrays are noticebly faster
    NSUInteger count = [array count];
    if (count < 1)
        return nil;

    for (NSUInteger x = 0; x < count; x++) {
        id item = [array objectAtIndex:x]; // save one objc selector call
        if ([[item identifier] isEqualToString:object])
            return item;
    }

    return nil;
}

@end
