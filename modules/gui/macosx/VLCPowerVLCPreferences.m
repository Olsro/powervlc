/*****************************************************************************
 * VLCPowerVLCPreferences.m: lightweight media-library preference panes
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "VLCPowerVLCPreferences.h"
#import "VLCMain.h"
#import "VLCMainWindow.h"
#import "VLCSidebarDataSource.h"

#include <vlc_configuration.h>
#include <vlc_playlist.h>
#include <vlc_services_discovery.h>

static NSString *PVLCConfigString(intf_thread_t *intf, const char *name)
{
    char *value = config_GetPsz(intf, name);
    NSString *result = value ? [NSString stringWithUTF8String:value] : @"";
    free(value);
    return result ?: @"";
}

static NSArray *PVLCDeviceConfigLines(NSString *value)
{
    /* Newlines are accepted for migration/current-session compatibility;
     * pipes are the durable on-disk record separator. */
    NSString *normalized = [value stringByReplacingOccurrencesOfString:@"|"
                                                             withString:@"\n"];
    return [normalized componentsSeparatedByString:@"\n"];
}

static NSString *PVLCEscape(NSString *value)
{
    NSString *normalized = value ? value : @"";
    const unsigned char *bytes = (const unsigned char *)[normalized UTF8String];
    NSMutableString *result = [NSMutableString string];
    for (; *bytes; bytes++) {
        unsigned char c = *bytes;
        if (c >= 0x20 && c != '%' && c != '\t' && c != '\r' && c != '\n'
         && c != '|' && c != ';')
            [result appendFormat:@"%c", c];
        else
            [result appendFormat:@"%%%02X", c];
    }
    return result;
}

static NSString *PVLCUnescape(NSString *value)
{
    NSString *decoded = [value stringByReplacingPercentEscapesUsingEncoding:
                                      NSUTF8StringEncoding];
    return decoded ?: value ?: @"";
}

static NSTextField *PVLCLabel(NSString *text, NSRect frame)
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    label.editable = NO;
    label.selectable = NO;
    label.bordered = NO;
    label.drawsBackground = NO;
    label.stringValue = text;
    return label;
}

static NSButton *PVLCButton(NSString *title, id target, SEL action, NSRect frame)
{
    NSButton *button = [[NSButton alloc] initWithFrame:frame];
    button.title = title;
    button.bezelStyle = NSRoundedBezelStyle;
    button.target = target;
    button.action = action;
    return button;
}

static NSTableView *PVLCTable(NSRect frame, NSArray *columns)
{
    NSTableView *table = [[NSTableView alloc] initWithFrame:frame];
    table.usesAlternatingRowBackgroundColors = YES;
    table.allowsMultipleSelection = NO;
    for (NSDictionary *definition in columns) {
        NSTableColumn *column = [[NSTableColumn alloc]
            initWithIdentifier:[definition objectForKey:@"id"]];
        [[column headerCell] setStringValue:[definition objectForKey:@"title"]];
        [column setWidth:[[definition objectForKey:@"width"] doubleValue]];
        [table addTableColumn:column];
    }
    return table;
}

static NSScrollView *PVLCScrollForTable(NSTableView *table, NSRect frame)
{
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:frame];
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    scroll.documentView = table;
    return scroll;
}

static void PVLCSetFixedPaneHeight(NSView *view, CGFloat height)
{
    [view addConstraint:[NSLayoutConstraint constraintWithItem:view
        attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual
        toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1.
        constant:height]];
}

@interface VLCPowerVLCPreferences ()
{
    intf_thread_t *_intf;
    NSTextField *_managedFolder;
    NSTableView *_folderTable;
    NSTableView *_smartTable;
    NSTextField *_monitorInterval;
    NSTextField *_libraryComponentLimit;
    NSTextField *_libraryPathLimit;
    NSMutableArray *_folders;
    NSMutableArray *_smartPlaylists;

    NSTableView *_deviceTable;
    NSTextField *_deviceComponentLimit;
    NSTextField *_devicePathLimit;
    NSMutableArray *_devices;
}
@end

@implementation VLCPowerVLCPreferences

- (instancetype)initWithInterface:(intf_thread_t *)intf
{
    self = [super init];
    if (self) {
        _intf = intf;
        _folders = [NSMutableArray array];
        _smartPlaylists = [NSMutableArray array];
        _devices = [NSMutableArray array];
        [self buildMediaLibraryView];
        [self buildPortablePlayersView];
        [self reload];
    }
    return self;
}

- (NSTextField *)fieldAt:(NSRect)frame inView:(NSView *)view
{
    NSTextField *field = [[NSTextField alloc] initWithFrame:frame];
    [view addSubview:field];
    return field;
}

- (void)buildMediaLibraryView
{
    _mediaLibraryView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 680, 650)];
    [_mediaLibraryView setTranslatesAutoresizingMaskIntoConstraints:NO];
    PVLCSetFixedPaneHeight(_mediaLibraryView, 650.);
    [_mediaLibraryView addSubview:PVLCLabel(_NS("Managed Media Folder"),
                                            NSMakeRect(20, 610, 260, 20))];
    _managedFolder = [self fieldAt:NSMakeRect(20, 580, 530, 24)
                            inView:_mediaLibraryView];
    [_mediaLibraryView addSubview:PVLCButton(_NS("Choose…"), self,
        @selector(chooseManagedFolder:), NSMakeRect(560, 578, 100, 28))];
    /* Keep enough room for translations which wrap to three lines (notably
     * French).  A two-line frame silently clipped the end of the hint. */
    NSTextField *hint = PVLCLabel(_NS("Music dropped into the Media Library is copied into the managed folder with portable names. Videos remain in the scanned folders and keep their original tree."), NSMakeRect(20, 520, 640, 54));
    hint.cell.wraps = YES;
    hint.cell.lineBreakMode = NSLineBreakByWordWrapping;
    [_mediaLibraryView addSubview:hint];

    [_mediaLibraryView addSubview:PVLCLabel(_NS("Library Folders"),
                                            NSMakeRect(20, 490, 250, 20))];
    _folderTable = PVLCTable(NSMakeRect(0, 0, 620, 116), @[
        @{@"id": @"path", @"title": _NS("Folder"), @"width": @390},
        @{@"id": @"monitor", @"title": _NS("Monitor"), @"width": @90},
        @{@"id": @"cache", @"title": _NS("Shared cache"), @"width": @110}
    ]);
    _folderTable.dataSource = self;
    _folderTable.delegate = self;
    for (NSString *identifier in @[@"monitor", @"cache"]) {
        NSTableColumn *column = [_folderTable tableColumnWithIdentifier:identifier];
        NSButtonCell *toggle = [[NSButtonCell alloc] init];
        toggle.buttonType = NSSwitchButton;
        toggle.title = @"";
        [column setDataCell:toggle];
        [column setEditable:YES];
    }
    _folderTable.toolTip = _NS("Uncheck Shared cache to keep this folder's database in the managed media folder. It remains visible while a network volume is offline.");
    [_mediaLibraryView addSubview:PVLCScrollForTable(_folderTable,
                                    NSMakeRect(20, 362, 640, 126))];
    [_mediaLibraryView addSubview:PVLCButton(_NS("Add…"), self,
        @selector(addFolder:), NSMakeRect(20, 328, 90, 28))];
    [_mediaLibraryView addSubview:PVLCButton(_NS("Edit…"), self,
        @selector(editFolder:), NSMakeRect(116, 328, 90, 28))];
    [_mediaLibraryView addSubview:PVLCButton(_NS("Remove"), self,
        @selector(removeFolder:), NSMakeRect(212, 328, 90, 28))];

    [_mediaLibraryView addSubview:PVLCLabel(_NS("Smart Playlists"),
                                            NSMakeRect(20, 296, 250, 20))];
    _smartTable = PVLCTable(NSMakeRect(0, 0, 620, 102), @[
        @{@"id": @"name", @"title": _NS("Name"), @"width": @240},
        @{@"id": @"summary", @"title": _NS("Rules"), @"width": @370}
    ]);
    _smartTable.dataSource = self;
    _smartTable.delegate = self;
    _smartTable.target = self;
    _smartTable.doubleAction = @selector(editSmartPlaylist:);
    [_mediaLibraryView addSubview:PVLCScrollForTable(_smartTable,
                                    NSMakeRect(20, 182, 640, 112))];
    [_mediaLibraryView addSubview:PVLCButton(_NS("New…"), self,
        @selector(addSmartPlaylist:), NSMakeRect(20, 148, 90, 28))];
    [_mediaLibraryView addSubview:PVLCButton(_NS("Edit…"), self,
        @selector(editSmartPlaylist:), NSMakeRect(116, 148, 90, 28))];
    [_mediaLibraryView addSubview:PVLCButton(_NS("Remove"), self,
        @selector(removeSmartPlaylist:), NSMakeRect(212, 148, 90, 28))];

    [_mediaLibraryView addSubview:PVLCLabel(_NS("Maintenance"),
                                            NSMakeRect(20, 112, 250, 20))];
    [_mediaLibraryView addSubview:PVLCLabel(_NS("Maximum idle monitoring interval (seconds)"),
                                            NSMakeRect(20, 82, 540, 20))];
    _monitorInterval = [self fieldAt:NSMakeRect(580, 79, 80, 24)
                              inView:_mediaLibraryView];
    [_mediaLibraryView addSubview:PVLCLabel(_NS("Maximum file/folder name (bytes)"),
                                            NSMakeRect(20, 50, 250, 20))];
    _libraryComponentLimit = [self fieldAt:NSMakeRect(275, 47, 80, 24)
                                    inView:_mediaLibraryView];
    [_mediaLibraryView addSubview:PVLCLabel(_NS("Maximum complete path (bytes)"),
                                            NSMakeRect(370, 50, 210, 20))];
    _libraryPathLimit = [self fieldAt:NSMakeRect(580, 47, 80, 24)
                               inView:_mediaLibraryView];
}

- (void)buildPortablePlayersView
{
    _portablePlayersView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 680, 650)];
    [_portablePlayersView setTranslatesAutoresizingMaskIntoConstraints:NO];
    PVLCSetFixedPaneHeight(_portablePlayersView, 650.);
    NSTextField *intro = PVLCLabel(_NS("PowerVLC keeps originals unchanged. Each player receives portable copies and an incremental .powervlcdevice.db binary index."), NSMakeRect(20, 600, 640, 40));
    intro.cell.wraps = YES;
    [_portablePlayersView addSubview:intro];
    _deviceTable = PVLCTable(NSMakeRect(0, 0, 620, 350), @[
        @{@"id": @"name", @"title": _NS("Player"), @"width": @170},
        @{@"id": @"path", @"title": _NS("Folder"), @"width": @320},
        @{@"id": @"kind", @"title": _NS("Type"), @"width": @120}
    ]);
    _deviceTable.dataSource = self;
    _deviceTable.delegate = self;
    _deviceTable.target = self;
    _deviceTable.doubleAction = @selector(editDevice:);
    [_portablePlayersView addSubview:PVLCScrollForTable(_deviceTable,
                                    NSMakeRect(20, 230, 640, 360))];
    [_portablePlayersView addSubview:PVLCButton(_NS("Add…"), self,
        @selector(addDevice:), NSMakeRect(20, 194, 90, 28))];
    [_portablePlayersView addSubview:PVLCButton(_NS("Edit…"), self,
        @selector(editDevice:), NSMakeRect(116, 194, 90, 28))];
    [_portablePlayersView addSubview:PVLCButton(_NS("Remove"), self,
        @selector(removeDevice:), NSMakeRect(212, 194, 90, 28))];
    [_portablePlayersView addSubview:PVLCLabel(_NS("FAT32 and Legacy Player Limits"),
                                               NSMakeRect(20, 152, 320, 20))];
    [_portablePlayersView addSubview:PVLCLabel(_NS("Maximum file/folder name (bytes)"),
                                               NSMakeRect(20, 116, 250, 20))];
    _deviceComponentLimit = [self fieldAt:NSMakeRect(275, 113, 80, 24)
                                   inView:_portablePlayersView];
    [_portablePlayersView addSubview:PVLCLabel(_NS("Maximum complete path (bytes)"),
                                               NSMakeRect(370, 116, 210, 20))];
    _devicePathLimit = [self fieldAt:NSMakeRect(580, 113, 80, 24)
                              inView:_portablePlayersView];
}

- (void)reload
{
    NSString *managed = PVLCConfigString(_intf, "powervlc-ml-managed-folder");
    if (![managed length])
        managed = [NSHomeDirectory() stringByAppendingPathComponent:
                                      @"Music/PowerVLC media library"];
    _managedFolder.stringValue = managed;
    [_folders removeAllObjects];
    for (NSString *line in [PVLCConfigString(_intf, "powervlc-ml-folders")
                                  componentsSeparatedByString:@"\n"]) {
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        if ([parts count] < 2) continue;
        NSString *flags = [parts objectAtIndex:0];
        NSString *path = PVLCUnescape([[parts subarrayWithRange:
            NSMakeRange(1, [parts count] - 1)] componentsJoinedByString:@"\t"]);
        [_folders addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
            path, @"path", @([flags rangeOfString:@"m"].location != NSNotFound),
            @"monitor", @([flags rangeOfString:@"d"].location != NSNotFound),
            @"cache", nil]];
    }
    [_folderTable reloadData];

    [_smartPlaylists removeAllObjects];
    for (NSString *line in [PVLCConfigString(_intf,
             "powervlc-ml-smart-playlists") componentsSeparatedByString:@"\n"]) {
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        if ([parts count] < 4) continue;
        NSString *summary = [NSString stringWithFormat:_NS("%@ match, limit %@"),
            [[parts objectAtIndex:1] isEqualToString:@"any"] ? _NS("any") : _NS("all"),
            [[parts objectAtIndex:2] intValue] ? [parts objectAtIndex:2] : _NS("none")];
        [_smartPlaylists addObject:@{@"raw": line,
            @"name": PVLCUnescape([parts objectAtIndex:0]), @"summary": summary}];
    }
    [_smartTable reloadData];
    _monitorInterval.intValue = config_GetInt(_intf, "powervlc-ml-monitor-interval");
    _libraryComponentLimit.intValue = config_GetInt(_intf, "powervlc-ml-max-component");
    _libraryPathLimit.intValue = config_GetInt(_intf, "powervlc-ml-max-path");

    [_devices removeAllObjects];
    for (NSString *line in PVLCDeviceConfigLines(
                         PVLCConfigString(_intf, "powervlc-devices"))) {
        NSArray *parts = [line componentsSeparatedByString:@"\t"];
        if ([parts count] < 10) continue;
        [_devices addObject:@{@"raw": line,
            @"name": PVLCUnescape([parts objectAtIndex:0]),
            @"path": PVLCUnescape([parts objectAtIndex:1]),
            @"kind": [[parts objectAtIndex:2] isEqualToString:@"ipod"]
                        ? _NS("Apple iPod")
                        : [[parts objectAtIndex:2] isEqualToString:@"rockbox"]
                        ? _NS("Rockbox") : _NS("USB / storage")}];
    }
    [_deviceTable reloadData];
    _deviceComponentLimit.intValue = config_GetInt(_intf,
                                             "powervlc-device-max-component");
    _devicePathLimit.intValue = config_GetInt(_intf, "powervlc-device-max-path");
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView == _folderTable) return [_folders count];
    if (tableView == _smartTable) return [_smartPlaylists count];
    return [_devices count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    NSDictionary *value = tableView == _folderTable ? [_folders objectAtIndex:row]
                         : tableView == _smartTable ? [_smartPlaylists objectAtIndex:row]
                                                   : [_devices objectAtIndex:row];
    NSString *identifier = [column identifier];
    if ([identifier isEqualToString:@"monitor"] || [identifier isEqualToString:@"cache"])
        return @([[value objectForKey:identifier] boolValue]);
    return [value objectForKey:identifier];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)value
   forTableColumn:(NSTableColumn *)column row:(NSInteger)row
{
    if (tableView != _folderTable || row < 0 || row >= (NSInteger)[_folders count])
        return;
    NSString *identifier = [column identifier];
    if (![identifier isEqualToString:@"monitor"] &&
        ![identifier isEqualToString:@"cache"])
        return;
    [[_folders objectAtIndex:row] setObject:@([value boolValue])
                                      forKey:identifier];
}

- (NSString *)chooseFolderWithTitle:(NSString *)title initial:(NSString *)initial
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = YES;
    panel.canChooseFiles = NO;
    panel.allowsMultipleSelection = NO;
    panel.canCreateDirectories = YES;
    panel.message = title;
    if ([initial length]) panel.directoryURL = [NSURL fileURLWithPath:initial];
    return [panel runModal] == NSOKButton ? [[panel URL] path] : nil;
}

- (void)chooseManagedFolder:(id)sender
{
    NSString *path = [self chooseFolderWithTitle:_NS("Choose Managed Media Folder")
                                         initial:_managedFolder.stringValue];
    if (path) _managedFolder.stringValue = path;
}

- (void)addFolder:(id)sender
{
    NSString *path = [self chooseFolderWithTitle:_NS("Add Library Folder")
                                         initial:NSHomeDirectory()];
    if (!path) return;
    for (NSDictionary *folder in _folders)
        if ([[folder objectForKey:@"path"] isEqualToString:path]) return;
    BOOL cache = YES;
    NSString *db = [path stringByAppendingPathComponent:@".powervlcmediafolder.db"];
    if ([[NSFileManager defaultManager] fileExistsAtPath:db]) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = _NS("Existing Media Cache");
        alert.informativeText = _NS("This folder already contains a PowerVLC media cache. Use it instead of scanning everything again?");
        [alert addButtonWithTitle:_NS("Use Cache")];
        [alert addButtonWithTitle:_NS("Scan Again")];
        cache = [alert runModal] == NSAlertFirstButtonReturn;
    }
    [_folders addObject:[NSMutableDictionary dictionaryWithObjectsAndKeys:
        path, @"path", @NO, @"monitor", @(cache), @"cache", nil]];
    [_folderTable reloadData];
}

- (void)removeFolder:(id)sender
{
    NSInteger row = _folderTable.selectedRow;
    if (row >= 0) { [_folders removeObjectAtIndex:row]; [_folderTable reloadData]; }
}

- (void)editFolder:(id)sender
{
    NSInteger row = _folderTable.selectedRow;
    if (row < 0 || row >= (NSInteger)[_folders count]) return;
    NSMutableDictionary *folder = [_folders objectAtIndex:row];
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 470, 92)];
    NSTextField *path = PVLCLabel([folder objectForKey:@"path"],
                                  NSMakeRect(0, 66, 470, 20));
    [[path cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [view addSubview:path];
    NSButton *monitor = [[NSButton alloc] initWithFrame:NSMakeRect(0, 34, 300, 24)];
    monitor.buttonType = NSSwitchButton;
    monitor.title = _NS("Monitor this folder");
    monitor.state = [[folder objectForKey:@"monitor"] boolValue] ? NSOnState : NSOffState;
    [view addSubview:monitor];
    NSButton *cache = [[NSButton alloc] initWithFrame:NSMakeRect(0, 4, 430, 24)];
    cache.buttonType = NSSwitchButton;
    cache.title = _NS("Use a shared cache stored in this folder");
    cache.state = [[folder objectForKey:@"cache"] boolValue] ? NSOnState : NSOffState;
    [view addSubview:cache];
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Edit Library Folder");
    alert.informativeText = _NS("When Shared cache is disabled, the database is kept in the managed media folder so tracks remain visible while this folder is offline.");
    alert.accessoryView = view;
    [alert addButtonWithTitle:_NS("Save")];
    [alert addButtonWithTitle:_NS("Cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    [folder setObject:@(monitor.state == NSOnState) forKey:@"monitor"];
    [folder setObject:@(cache.state == NSOnState) forKey:@"cache"];
    [_folderTable reloadData];
}

- (NSDictionary *)runSmartEditorForRaw:(NSString *)raw
{
    NSArray *parts = [raw componentsSeparatedByString:@"\t"];
    NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 650, 390)];
    [accessory addSubview:PVLCLabel(_NS("Name"), NSMakeRect(0, 360, 90, 20))];
    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(95, 356, 330, 24)];
    if ([parts count] >= 1) name.stringValue = PVLCUnescape([parts objectAtIndex:0]);
    [accessory addSubview:name];
    [accessory addSubview:PVLCLabel(_NS("Match"), NSMakeRect(0, 326, 90, 20))];
    NSPopUpButton *match = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(95, 322, 220, 26)];
    [match addItemsWithTitles:@[_NS("all rules"), _NS("any rule")]];
    if ([parts count] > 1 && [[parts objectAtIndex:1] isEqualToString:@"any"])
        [match selectItemAtIndex:1];
    [accessory addSubview:match];
    [accessory addSubview:PVLCLabel(_NS("Item limit (0 = none)"), NSMakeRect(330, 326, 170, 20))];
    NSTextField *limit = [[NSTextField alloc] initWithFrame:NSMakeRect(505, 322, 75, 24)];
    limit.intValue = [parts count] > 2 ? [[parts objectAtIndex:2] intValue] : 0;
    [accessory addSubview:limit];

    NSArray *fieldIds = @[@"title", @"artist", @"album", @"path", @"type",
                          @"size", @"modified", @"rating"];
    NSArray *fieldNames = @[_NS("Title"), _NS("Artist"), _NS("Album"),
        _NS("Path"), _NS("Media type"), _NS("File size"),
        _NS("Modified date"), _NS("Rating (0–5)")];
    NSArray *operatorIds = @[@"contains", @"not_contains", @"is", @"is_not",
        @"greater", @"less", @"starts_with", @"ends_with", @"after", @"before"];
    NSArray *operatorNames = @[_NS("contains"), _NS("does not contain"),
        _NS("is"), _NS("is not"), _NS("is greater than"),
        _NS("is less than"), _NS("starts with"), _NS("ends with"),
        _NS("is after"), _NS("is before")];
    NSMutableArray *savedRules = [NSMutableArray array];
    if ([parts count] >= 4) {
        NSString *encodedRules = [[parts subarrayWithRange:NSMakeRange(3, [parts count] - 3)] componentsJoinedByString:@"\t"];
        for (NSString *rule in [encodedRules componentsSeparatedByString:@";"]) {
            NSArray *bits = [rule componentsSeparatedByString:@"|"];
            if ([bits count] >= 3)
                [savedRules addObject:@{
                    @"field": PVLCUnescape([bits objectAtIndex:0]),
                    @"operator": PVLCUnescape([bits objectAtIndex:1]),
                    @"value": PVLCUnescape([[bits subarrayWithRange:
                        NSMakeRange(2, [bits count] - 2)] componentsJoinedByString:@"|"])}];
        }
    }
    [accessory addSubview:PVLCLabel(_NS("Use"), NSMakeRect(0, 292, 36, 20))];
    [accessory addSubview:PVLCLabel(_NS("Field"), NSMakeRect(40, 292, 140, 20))];
    [accessory addSubview:PVLCLabel(_NS("Condition"), NSMakeRect(185, 292, 175, 20))];
    [accessory addSubview:PVLCLabel(_NS("Value"), NSMakeRect(365, 292, 270, 20))];
    NSMutableArray *enabledControls = [NSMutableArray array];
    NSMutableArray *fieldControls = [NSMutableArray array];
    NSMutableArray *operatorControls = [NSMutableArray array];
    NSMutableArray *valueControls = [NSMutableArray array];
    const NSUInteger rowCount = MAX((NSUInteger)4, MIN((NSUInteger)8,
                                                       [savedRules count] + 1));
    for (NSUInteger row = 0; row < rowCount; ++row) {
        CGFloat y = 258 - row * 32;
        NSButton *enabled = [[NSButton alloc] initWithFrame:NSMakeRect(5, y, 24, 24)];
        enabled.buttonType = NSSwitchButton; enabled.title = @"";
        NSPopUpButton *field = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(35, y - 1, 145, 26)];
        [field addItemsWithTitles:fieldNames];
        NSPopUpButton *op = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(180, y - 1, 180, 26)];
        [op addItemsWithTitles:operatorNames];
        NSTextField *value = [[NSTextField alloc] initWithFrame:NSMakeRect(365, y, 270, 24)];
        if (row < [savedRules count]) {
            NSDictionary *saved = [savedRules objectAtIndex:row];
            NSUInteger fieldIndex = [fieldIds indexOfObject:[saved objectForKey:@"field"]];
            NSUInteger operatorIndex = [operatorIds indexOfObject:[saved objectForKey:@"operator"]];
            if (fieldIndex != NSNotFound) [field selectItemAtIndex:fieldIndex];
            if (operatorIndex != NSNotFound) [op selectItemAtIndex:operatorIndex];
            value.stringValue = [saved objectForKey:@"value"];
            enabled.state = NSOnState;
        }
        [accessory addSubview:enabled]; [accessory addSubview:field];
        [accessory addSubview:op]; [accessory addSubview:value];
        [enabledControls addObject:enabled]; [fieldControls addObject:field];
        [operatorControls addObject:op]; [valueControls addObject:value];
    }
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText = _NS("Smart Playlist"); alert.accessoryView = accessory;
    [alert addButtonWithTitle:_NS("Save")]; [alert addButtonWithTitle:_NS("Cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn || ![[name.stringValue
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] length]) return nil;
    NSMutableArray *encoded = [NSMutableArray array];
    for (NSUInteger row = 0; row < rowCount; ++row) {
        if ([[enabledControls objectAtIndex:row] state] != NSOnState) continue;
        NSUInteger fieldIndex = [[fieldControls objectAtIndex:row] indexOfSelectedItem];
        NSUInteger operatorIndex = [[operatorControls objectAtIndex:row] indexOfSelectedItem];
        NSString *value = [[valueControls objectAtIndex:row] stringValue];
        [encoded addObject:[NSString stringWithFormat:@"%@|%@|%@",
            PVLCEscape([fieldIds objectAtIndex:fieldIndex]),
            PVLCEscape([operatorIds objectAtIndex:operatorIndex]),
            PVLCEscape(value)]];
    }
    if (![encoded count]) [encoded addObject:@"title|contains|"];
    NSString *matchId = match.indexOfSelectedItem == 1 ? @"any" : @"all";
    NSString *saved = [NSString stringWithFormat:@"%@\t%@\t%d\t%@",
        PVLCEscape(name.stringValue), matchId, MAX(0, limit.intValue),
        [encoded componentsJoinedByString:@";"]];
    NSString *summary = [NSString stringWithFormat:_NS("%@ match, %lu rules, limit %@"),
        matchId, (unsigned long)[encoded count], limit.intValue > 0 ?
        [NSString stringWithFormat:@"%d", limit.intValue] : _NS("none")];
    return @{@"raw": saved, @"name": name.stringValue, @"summary": summary};
}

- (void)addSmartPlaylist:(id)sender
{
    NSDictionary *value = [self runSmartEditorForRaw:@""];
    if (value) { [_smartPlaylists addObject:value]; [_smartTable reloadData]; }
}

- (void)editSmartPlaylist:(id)sender
{
    NSInteger row = _smartTable.selectedRow;
    if (row < 0) return;
    NSDictionary *value = [self runSmartEditorForRaw:
                            [[_smartPlaylists objectAtIndex:row] objectForKey:@"raw"]];
    if (value) { [_smartPlaylists replaceObjectAtIndex:row withObject:value]; [_smartTable reloadData]; }
}

- (void)removeSmartPlaylist:(id)sender
{
    NSInteger row = _smartTable.selectedRow;
    if (row >= 0) { [_smartPlaylists removeObjectAtIndex:row]; [_smartTable reloadData]; }
}

- (NSDictionary *)runDeviceEditorForRaw:(NSString *)raw
{
    NSArray *old = [raw componentsSeparatedByString:@"\t"];
    NSView *v = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 680, 250)];
    NSMutableArray *controls = [NSMutableArray array];
    NSArray *labels = @[_NS("Name"), _NS("Mount point or folder"), _NS("Device type"),
        _NS("Transcode copies"), _NS("Preferred codec"), _NS("Bitrate (kb/s)"),
        _NS("Map Album Artist to Composer (Apple iPod)")];
    for (NSUInteger i = 0; i < [labels count]; i++)
        [v addSubview:PVLCLabel([labels objectAtIndex:i], NSMakeRect(0, 220 - i * 34, 270, 20))];
    NSTextField *name = [[NSTextField alloc] initWithFrame:NSMakeRect(275, 216, 395, 24)];
    NSTextField *path = [[NSTextField alloc] initWithFrame:NSMakeRect(275, 182, 395, 24)];
    NSPopUpButton *kind = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(275, 148, 300, 26)];
    [kind addItemsWithTitles:@[_NS("USB / storage player"),
        _NS("Apple iPod (libgpod)"), _NS("Rockbox player")]];
    NSButton *transcode = [[NSButton alloc] initWithFrame:NSMakeRect(275, 116, 24, 24)];
    transcode.buttonType = NSSwitchButton; transcode.title = @"";
    NSPopUpButton *codec = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(275, 80, 220, 26)];
    [codec addItemsWithTitles:@[ @"MP3", @"AAC / M4A", @"FLAC" ]];
    [codec selectItemAtIndex:1];
    NSTextField *bitrate = [[NSTextField alloc] initWithFrame:NSMakeRect(275, 46, 110, 24)];
    NSButton *albumArtistComposer = [[NSButton alloc]
        initWithFrame:NSMakeRect(275, 12, 24, 24)];
    albumArtistComposer.buttonType = NSSwitchButton;
    albumArtistComposer.title = @"";
    [controls addObjectsFromArray:@[name, path, kind, transcode, codec, bitrate,
                                    albumArtistComposer]];
    for (NSView *control in controls) [v addSubview:control];
    if ([old count] >= 10) {
        name.stringValue = PVLCUnescape([old objectAtIndex:0]); path.stringValue = PVLCUnescape([old objectAtIndex:1]);
        NSString *oldKind = [old objectAtIndex:2];
        [kind selectItemAtIndex:[oldKind isEqualToString:@"ipod"] ? 1
                              : [oldKind isEqualToString:@"rockbox"] ? 2 : 0];
        transcode.state = [[old objectAtIndex:3] intValue] ? NSOnState : NSOffState;
        NSString *codecId = [old objectAtIndex:4];
        [codec selectItemAtIndex:[codecId isEqualToString:@"flac"] ? 2
                              : [codecId isEqualToString:@"mp3"] ? 0 : 1];
        bitrate.intValue = MAX(64, [[old objectAtIndex:5] intValue] ?: 256);
        albumArtistComposer.state = [[old objectAtIndex:6] intValue]
                                  ? NSOnState : NSOffState;
    } else bitrate.intValue = 256;
    NSAlert *alert = [[NSAlert alloc] init]; alert.messageText = _NS("Portable Player"); alert.accessoryView = v;
    [alert addButtonWithTitle:_NS("Save")]; [alert addButtonWithTitle:_NS("Cancel")];
    if ([alert runModal] != NSAlertFirstButtonReturn || ![name.stringValue length] || ![path.stringValue length]) return nil;
    /* A Rockbox iPod legitimately contains both .rockbox and iPod_Control.
     * addDevice: already supplies an automatic initial choice; after the
     * editor is shown, the user's explicit popup selection is authoritative. */
    NSString *codecId = codec.indexOfSelectedItem == 1 ? @"aac" : codec.indexOfSelectedItem == 2 ? @"flac" : @"mp3";
    NSString *saved = [@[PVLCEscape(name.stringValue), PVLCEscape(path.stringValue),
        kind.indexOfSelectedItem == 1 ? @"ipod"
        : kind.indexOfSelectedItem == 2 ? @"rockbox" : @"storage",
        transcode.state == NSOnState ? @"1" : @"0", codecId,
        [NSString stringWithFormat:@"%d", MAX(64, bitrate.intValue)],
        kind.indexOfSelectedItem == 1
            && albumArtistComposer.state == NSOnState ? @"1" : @"0",
        @"0", @"0", @""] componentsJoinedByString:@"\t"];
    return @{@"raw": saved, @"name": name.stringValue, @"path": path.stringValue,
        @"kind": kind.indexOfSelectedItem == 1 ? _NS("Apple iPod")
        : kind.indexOfSelectedItem == 2 ? _NS("Rockbox") : _NS("USB / storage")};
}

- (void)addDevice:(id)sender
{
    NSString *path = [self chooseFolderWithTitle:_NS("Choose Portable Player") initial:@"/Volumes"];
    if (!path) return;
    NSString *kind = [[NSFileManager defaultManager] fileExistsAtPath:
                       [path stringByAppendingPathComponent:@"iPod_Control"]] ? @"ipod"
                   : [[NSFileManager defaultManager] fileExistsAtPath:
                       [path stringByAppendingPathComponent:@".rockbox"]] ? @"rockbox"
                   : @"storage";
    NSString *seed = [NSString stringWithFormat:@"%@\t%@\t%@\t0\taac\t256\t0\t0\t0\t",
        PVLCEscape([path lastPathComponent]), PVLCEscape(path), kind];
    NSDictionary *value = [self runDeviceEditorForRaw:seed];
    if (value) {
        [_devices addObject:value]; [_deviceTable reloadData];
        [self applyPortablePlayers];
    }
}

- (void)editDevice:(id)sender
{
    NSInteger row = _deviceTable.selectedRow;
    if (row < 0) return;
    NSDictionary *value = [self runDeviceEditorForRaw:[[_devices objectAtIndex:row] objectForKey:@"raw"]];
    if (value) {
        [_devices replaceObjectAtIndex:row withObject:value];
        [_deviceTable reloadData];
        [self applyPortablePlayers];
    }
}

- (void)removeDevice:(id)sender
{
    NSInteger row = _deviceTable.selectedRow;
    if (row >= 0) {
        [_devices removeObjectAtIndex:row]; [_deviceTable reloadData];
        [self applyPortablePlayers];
    }
}

- (void)applyPortablePlayers
{
    NSArray *oldLines = PVLCDeviceConfigLines(
                         PVLCConfigString(_intf, "powervlc-devices"));
    NSMutableArray *deviceLines = [NSMutableArray array];
    for (NSDictionary *device in _devices)
        [deviceLines addObject:[device objectForKey:@"raw"]];
    NSString *deviceConfig = [deviceLines componentsJoinedByString:@"|"];
    config_PutPsz(_intf, "powervlc-devices", deviceConfig.UTF8String);
    var_Create(_intf->obj.libvlc, "powervlc-devices", VLC_VAR_STRING);
    var_SetString(_intf->obj.libvlc, "powervlc-devices", deviceConfig.UTF8String);
    /* Device services are updated live. Persist the same value immediately
     * so a crash or forced termination cannot make a player disappear on the
     * next launch after it was already visible in the sidebar. */
    config_SaveConfigFile(_intf);

    playlist_t *playlist = pl_Get(_intf);
    for (NSUInteger index = 0; index < 64; ++index) {
        NSString *oldLine = index < [oldLines count]
                          ? [oldLines objectAtIndex:index] : @"";
        NSString *newLine = index < [deviceLines count]
                          ? [deviceLines objectAtIndex:index] : @"";
        if ([oldLine isEqualToString:newLine]) continue;
        NSString *chain = [NSString stringWithFormat:@"powervlc_device{index=%lu}",
                                                   (unsigned long)index];
        if ([oldLine length]
         && playlist_IsServicesDiscoveryLoaded(playlist, chain.UTF8String))
            playlist_ServicesDiscoveryRemove(playlist, chain.UTF8String);
        if ([newLine length])
            playlist_ServicesDiscoveryAdd(playlist, chain.UTF8String);
    }
    [[[[VLCMain sharedInstance] mainWindow] sidebarDataSource] reloadSidebar];
}

- (void)save
{
    NSString *newManagedFolder = _managedFolder.stringValue;
    BOOL folderConfigurationChanged = ![newManagedFolder isEqualToString:
        PVLCConfigString(_intf, "powervlc-ml-managed-folder")];
    config_PutPsz(_intf, "powervlc-ml-managed-folder", [_managedFolder.stringValue UTF8String]);
    NSMutableArray *folderLines = [NSMutableArray array];
    for (NSDictionary *folder in _folders) {
        NSString *flags = [NSString stringWithFormat:@"%@%@",
            [[folder objectForKey:@"monitor"] boolValue] ? @"m" : @"",
            [[folder objectForKey:@"cache"] boolValue] ? @"d" : @""];
        [folderLines addObject:[NSString stringWithFormat:@"%@\t%@", flags,
                                PVLCEscape([folder objectForKey:@"path"])]];
    }
    NSString *folderConfiguration = [folderLines componentsJoinedByString:@"\n"];
    folderConfigurationChanged |= ![folderConfiguration isEqualToString:
        PVLCConfigString(_intf, "powervlc-ml-folders")];
    config_PutPsz(_intf, "powervlc-ml-folders",
                  folderConfiguration.UTF8String);
    NSMutableArray *smartLines = [NSMutableArray array];
    for (NSDictionary *smart in _smartPlaylists) [smartLines addObject:[smart objectForKey:@"raw"]];
    NSString *smartConfiguration = [smartLines componentsJoinedByString:@"\n"];
    BOOL smartConfigurationChanged = ![smartConfiguration isEqualToString:
        PVLCConfigString(_intf, "powervlc-ml-smart-playlists")];
    config_PutPsz(_intf, "powervlc-ml-smart-playlists",
                  smartConfiguration.UTF8String);
    config_PutInt(_intf, "powervlc-ml-monitor-interval", MAX(15, _monitorInterval.intValue));
    config_PutInt(_intf, "powervlc-ml-max-component", MAX(48, _libraryComponentLimit.intValue));
    config_PutInt(_intf, "powervlc-ml-max-path", MAX(96, _libraryPathLimit.intValue));
    config_PutInt(_intf, "powervlc-device-max-component", MAX(32, _deviceComponentLimit.intValue));
    config_PutInt(_intf, "powervlc-device-max-path", MAX(96, _devicePathLimit.intValue));
    [self applyPortablePlayers];

    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *branch in @[@"Music", @"Movies", @"Shows", @"Podcasts", @"Playlists"])
        [manager createDirectoryAtPath:[_managedFolder.stringValue stringByAppendingPathComponent:branch]
           withIntermediateDirectories:YES attributes:nil error:nil];
    playlist_t *playlist = pl_Get(_intf);
    if (folderConfigurationChanged
     && playlist_IsServicesDiscoveryLoaded(playlist, "powervlc_library"))
        playlist_ServicesDiscoveryControl(playlist, "powervlc_library",
                                           SD_CMD_POWERVLC_RESCAN);
    if (smartConfigurationChanged) {
        if (playlist_IsServicesDiscoveryLoaded(playlist, "powervlc_library"))
            playlist_ServicesDiscoveryControl(playlist, "powervlc_library",
                SD_CMD_POWERVLC_LIBRARY_RELOAD_SMART);
    }
}

@end
