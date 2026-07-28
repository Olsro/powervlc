/*****************************************************************************
 * VLCLegacyAddons.m: Addons Manager window (legacy interface)
 *****************************************************************************
 * Copyright © 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "VLCLegacyAddons.h"
#import "misc.h"

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/*****************************************************************************
 * manager callbacks (arbitrary core threads -> main thread)
 *****************************************************************************/

static void addonFoundCallback(addons_manager_t *manager,
                               addon_entry_t *entry)
{
    VLCLegacyAddons *controller = (VLCLegacyAddons *)manager->owner.sys;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    addon_entry_Hold(entry);
    [controller performSelectorOnMainThread:@selector(addAddonEntry:)
                                 withObject:[NSValue valueWithPointer:entry]
                              waitUntilDone:NO];
    [pool release];
}

static void addonsDiscoveryEndedCallback(addons_manager_t *manager)
{
    VLCLegacyAddons *controller = (VLCLegacyAddons *)manager->owner.sys;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [controller performSelectorOnMainThread:@selector(discoveryEnded)
                                 withObject:nil
                              waitUntilDone:NO];
    [pool release];
}

static void addonChangedCallback(addons_manager_t *manager,
                                 addon_entry_t *entry)
{
    (void)entry;
    VLCLegacyAddons *controller = (VLCLegacyAddons *)manager->owner.sys;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [controller performSelectorOnMainThread:@selector(refreshDisplayedList)
                                 withObject:nil
                              waitUntilDone:NO];
    [pool release];
}

@implementation VLCLegacyAddons

- (id)initWithIntf:(intf_thread_t *)intf
{
    if (self = [super init]) {
        p_intf = intf;
        addons = [[NSMutableArray alloc] init];
        displayedAddons = [[NSMutableArray alloc] init];

        struct addons_manager_owner owner = {
            self,
            addonFoundCallback,
            addonsDiscoveryEndedCallback,
            addonChangedCallback,
        };
        p_manager = addons_manager_New(VLC_OBJECT(p_intf), &owner);
    }
    return self;
}

- (void)releaseHeldEntries
{
    unsigned i;
    for (i = 0; i < [addons count]; i++)
        addon_entry_Release((addon_entry_t *)
            [[addons objectAtIndex:i] pointerValue]);
    [addons removeAllObjects];
    [displayedAddons removeAllObjects];
}

- (void)dealloc
{
    [self releaseHeldEntries];
    if (p_manager)
        addons_manager_Delete(p_manager);
    [addons release];
    [displayedAddons release];
    [window release];
    [super dealloc];
}

/*****************************************************************************
 * window
 *****************************************************************************/

- (NSTextField *)plainLabel:(NSString *)text frame:(NSRect)frame
                         in:(NSView *)parent bold:(BOOL)bold
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame]
        autorelease];
    [field setEditable:NO];
    [field setBordered:NO];
    [field setDrawsBackground:NO];
    [[field cell] setFont:bold ? [NSFont boldSystemFontOfSize:11]
                                : [NSFont systemFontOfSize:11]];
    VLCLegacySetCellLineBreakMode([field cell], NSLineBreakByTruncatingTail);
    [field setStringValue:text];
    [parent addSubview:field];
    return field;
}

- (void)buildWindow
{
    window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 640, 480)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSResizableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:_NS("Addons Manager")];
    VLCLegacyDenyNativeFullscreen(window);
    [window setReleasedWhenClosed:NO];
    [window setMinSize:NSMakeSize(560, 400)];
    NSView *content = [window contentView];
    NSRect bounds = [content bounds];

    /* top bar: type filter + installed-only */
    typeSwitcher = [[[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(16, bounds.size.height - 36, 200, 24)
            pullsDown:NO] autorelease];
    static const struct { const char *title; int type; } types[6] = {
        { N_("All"), -1 },
        { N_("Playlist parsers"), ADDON_PLAYLIST_PARSER },
        { N_("Service Discovery"), ADDON_SERVICE_DISCOVERY },
        { N_("Interfaces"), ADDON_INTERFACE },
        { N_("Art and meta fetchers"), ADDON_META },
        { N_("Extensions"), ADDON_EXTENSION },
    };
    int i;
    for (i = 0; i < 6; i++) {
        [typeSwitcher addItemWithTitle:_NS(types[i].title)];
        [[typeSwitcher lastItem] setTag:types[i].type];
    }
    [typeSwitcher setTarget:self];
    [typeSwitcher setAction:@selector(filtersChanged:)];
    [typeSwitcher setAutoresizingMask:NSViewMinYMargin];
    [content addSubview:typeSwitcher];

    localOnlyCheckbox = [[[NSButton alloc]
        initWithFrame:NSMakeRect(230, bounds.size.height - 34, 210, 18)]
        autorelease];
    [localOnlyCheckbox setButtonType:NSSwitchButton];
    [localOnlyCheckbox setTitle:_NS("Show Installed Only")];
    [localOnlyCheckbox setTarget:self];
    [localOnlyCheckbox setAction:@selector(filtersChanged:)];
    [localOnlyCheckbox setAutoresizingMask:NSViewMinYMargin];
    [content addSubview:localOnlyCheckbox];

    downloadCatalogButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(bounds.size.width - 216,
                                 bounds.size.height - 40, 200, 28)]
        autorelease];
    [downloadCatalogButton setTitle:_NS("Find more addons online")];
    [downloadCatalogButton setBezelStyle:NSRoundedBezelStyle];
    [downloadCatalogButton setTarget:self];
    [downloadCatalogButton setAction:@selector(downloadCatalog:)];
    [downloadCatalogButton setAutoresizingMask:
        NSViewMinXMargin | NSViewMinYMargin];
    [content addSubview:downloadCatalogButton];

    spinner = [[[NSProgressIndicator alloc]
        initWithFrame:NSMakeRect(bounds.size.width - 240,
                                 bounds.size.height - 34, 16, 16)]
        autorelease];
    [spinner setStyle:NSProgressIndicatorSpinningStyle];
    [spinner setDisplayedWhenStopped:NO];
    [spinner setAutoresizingMask:NSViewMinXMargin | NSViewMinYMargin];
    [content addSubview:spinner];

    /* table */
    NSScrollView *scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 170, bounds.size.width,
                                 bounds.size.height - 218)] autorelease];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    table = [[[NSTableView alloc]
        initWithFrame:[[scroll contentView] bounds]] autorelease];
    static const struct { const char *identifier; const char *title;
                          float width; } columns[4] = {
        { "installed", N_("Installed"), 70 },
        { "name",      N_("Name"),      280 },
        { "author",    N_("Author"),    120 },
        { "type",      N_("Type"),      120 },
    };
    for (i = 0; i < 4; i++) {
        NSTableColumn *column = [[[NSTableColumn alloc]
            initWithIdentifier:[NSString stringWithUTF8String:
                columns[i].identifier]] autorelease];
        [[column headerCell] setStringValue:_NS(columns[i].title)];
        [column setWidth:columns[i].width];
        [column setEditable:NO];
        [table addTableColumn:column];
    }
    [table setDataSource:(id)self];
    [table setDelegate:(id)self];
    [table setAllowsMultipleSelection:NO];
    [scroll setDocumentView:table];
    [content addSubview:scroll];

    /* details */
    nameField = [self plainLabel:@""
        frame:NSMakeRect(16, 140, bounds.size.width - 200, 17)
           in:content bold:YES];
    [nameField setAutoresizingMask:NSViewWidthSizable];
    authorField = [self plainLabel:@""
        frame:NSMakeRect(16, 120, bounds.size.width - 200, 15)
           in:content bold:NO];
    [authorField setAutoresizingMask:NSViewWidthSizable];
    versionField = [self plainLabel:@""
        frame:NSMakeRect(16, 102, bounds.size.width - 200, 15)
           in:content bold:NO];
    [versionField setAutoresizingMask:NSViewWidthSizable];

    NSScrollView *descriptionScroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(16, 16, bounds.size.width - 200, 80)]
        autorelease];
    [descriptionScroll setHasVerticalScroller:YES];
    [descriptionScroll setBorderType:NSBezelBorder];
    [descriptionScroll setAutoresizingMask:NSViewWidthSizable];
    descriptionView = [[[NSTextView alloc]
        initWithFrame:[[descriptionScroll contentView] bounds]]
        autorelease];
    [descriptionView setEditable:NO];
    [descriptionView setFont:[NSFont systemFontOfSize:11]];
    [descriptionScroll setDocumentView:descriptionView];
    [content addSubview:descriptionScroll];

    installButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(bounds.size.width - 156, 60, 140, 32)]
        autorelease];
    [installButton setTitle:_NS("Install")];
    [installButton setBezelStyle:NSRoundedBezelStyle];
    [installButton setTarget:self];
    [installButton setAction:@selector(installSelection:)];
    [installButton setEnabled:NO];
    [installButton setAutoresizingMask:NSViewMinXMargin];
    [content addSubview:installButton];

    [window center];
}

- (void)showWindow
{
    if (!window)
        [self buildWindow];
    if (!b_subscribed) {
        b_subscribed = YES;
        if (p_manager) {
            /* the locally installed addons, like 3.0 at window open */
            addons_manager_LoadCatalog(p_manager);
        }
    }
    [window makeKeyAndOrderFront:nil];
}

/*****************************************************************************
 * data flow
 *****************************************************************************/

- (void)addAddonEntry:(NSValue *)entryValue
{
    /* the callback already held the entry for us */
    [addons addObject:entryValue];
    [self refreshDisplayedList];
}

- (void)discoveryEnded
{
    [spinner stopAnimation:nil];
    [downloadCatalogButton setEnabled:YES];
    [self refreshDisplayedList];
}

- (NSString *)typeName:(int)type
{
    switch (type) {
    case ADDON_EXTENSION:         return _NS("Extensions");
    case ADDON_PLAYLIST_PARSER:   return _NS("Playlist parsers");
    case ADDON_SERVICE_DISCOVERY: return _NS("Service Discovery");
    case ADDON_INTERFACE:         return _NS("Interfaces");
    case ADDON_META:              return _NS("Art and meta fetchers");
    case ADDON_SKIN2:             return _NS("Skins");
    }
    return _NS("Unknown");
}

- (void)refreshDisplayedList
{
    [displayedAddons removeAllObjects];
    int typeFilter = (int)[[typeSwitcher selectedItem] tag];
    BOOL localOnly = [localOnlyCheckbox state] == NSOnState;

    unsigned i;
    for (i = 0; i < [addons count]; i++) {
        addon_entry_t *entry = (addon_entry_t *)
            [[addons objectAtIndex:i] pointerValue];
        vlc_mutex_lock(&entry->lock);
        BOOL matches = (typeFilter == -1 || entry->e_type == typeFilter)
            && (!localOnly || entry->e_state == ADDON_INSTALLED);
        vlc_mutex_unlock(&entry->lock);
        if (matches)
            [displayedAddons addObject:[addons objectAtIndex:i]];
    }
    [table reloadData];
    [self tableViewSelectionDidChange:nil];
}

- (void)filtersChanged:(id)sender
{
    [self refreshDisplayedList];
}

- (void)downloadCatalog:(id)sender
{
    if (!p_manager)
        return;
    [downloadCatalogButton setEnabled:NO];
    [spinner startAnimation:nil];
    addons_manager_Gather(p_manager, "repo://");
}

- (addon_entry_t *)selectedEntry
{
    NSInteger row = [table selectedRow];
    if (row < 0 || (unsigned)row >= [displayedAddons count])
        return NULL;
    return (addon_entry_t *)
        [[displayedAddons objectAtIndex:row] pointerValue];
}

- (void)installSelection:(id)sender
{
    addon_entry_t *entry = [self selectedEntry];
    if (!entry || !p_manager)
        return;
    addon_uuid_t uuid;
    vlc_mutex_lock(&entry->lock);
    memcpy(uuid, entry->uuid, sizeof(uuid));
    BOOL installed = entry->e_state == ADDON_INSTALLED;
    vlc_mutex_unlock(&entry->lock);

    if (installed)
        addons_manager_Remove(p_manager, uuid);
    else
        addons_manager_Install(p_manager, uuid);
}

/*****************************************************************************
 * table
 *****************************************************************************/

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[displayedAddons count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (row < 0 || (unsigned)row >= [displayedAddons count])
        return @"";
    addon_entry_t *entry = (addon_entry_t *)
        [[displayedAddons objectAtIndex:row] pointerValue];
    NSString *identifier = [column identifier];
    NSString *result = @"";

    vlc_mutex_lock(&entry->lock);
    if ([identifier isEqualToString:@"installed"])
        result = entry->e_state == ADDON_INSTALLED ? @"✔" : @"✘";
    else if ([identifier isEqualToString:@"name"])
        result = entry->psz_name
            ? [NSString stringWithUTF8String:entry->psz_name] : @"";
    else if ([identifier isEqualToString:@"author"])
        result = entry->psz_author
            ? [NSString stringWithUTF8String:entry->psz_author] : @"";
    else if ([identifier isEqualToString:@"type"])
        result = [self typeName:entry->e_type];
    vlc_mutex_unlock(&entry->lock);
    return result ? result : @"";
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    addon_entry_t *entry = [self selectedEntry];
    if (!entry) {
        [nameField setStringValue:@""];
        [authorField setStringValue:@""];
        [versionField setStringValue:@""];
        [descriptionView setString:@""];
        [installButton setEnabled:NO];
        return;
    }
    vlc_mutex_lock(&entry->lock);
    [nameField setStringValue:entry->psz_name
        ? [NSString stringWithUTF8String:entry->psz_name] : @""];
    [authorField setStringValue:entry->psz_author
        ? [NSString stringWithUTF8String:entry->psz_author] : @""];
    [versionField setStringValue:entry->psz_version
        ? [NSString stringWithUTF8String:entry->psz_version] : @""];
    [descriptionView setString:entry->psz_description
        ? [NSString stringWithUTF8String:entry->psz_description] : @""];
    BOOL manageable = (entry->e_flags & ADDON_MANAGEABLE) != 0;
    [installButton setEnabled:manageable];
    [installButton setTitle:entry->e_state == ADDON_INSTALLED
        ? _NS("Uninstall") : _NS("Install")];
    vlc_mutex_unlock(&entry->lock);
}

@end
