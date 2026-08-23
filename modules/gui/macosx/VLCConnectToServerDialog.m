/*****************************************************************************
 * VLCConnectToServerDialog.m: Connect to Server dialog
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *****************************************************************************/

#import "VLCConnectToServerDialog.h"

#import "VLCMain.h"
#import "VLCMainMenu.h"
#import "VLCMainWindow.h"
#import "VLCSidebarDataSource.h"
#import "VLCStringUtility.h"

#import <vlc_modules.h>
#import <vlc_playlist.h>

NSString * const VLCConnectToServerRecentsKey =
    @"VLCConnectToServerRecents";
static const NSUInteger VLCConnectToServerMaxRecents = 8;

@interface VLCConnectToServerDialog () <NSComboBoxDataSource,
                                         NSComboBoxDelegate,
                                         NSControlTextEditingDelegate>
{
    NSComboBox *_addressField;
    NSButton *_connectButton;
    NSMutableArray *_recents;
}
- (NSArray *)supportedSchemes;
- (NSString *)currentMRL;
- (void)addNetworkLocationAfterDialog:(NSString *)mrl;
@end

@implementation VLCConnectToServerDialog

- (id)init
{
    if (self = [super init]) {
        NSArray *stored = [[NSUserDefaults standardUserDefaults]
            stringArrayForKey:VLCConnectToServerRecentsKey];
        _recents = stored ? [stored mutableCopy] : [NSMutableArray array];
    }
    return self;
}

- (NSArray *)supportedSchemes
{
    NSMutableArray *schemes = [NSMutableArray array];
    if (module_exists("webdav"))
        [schemes addObjectsFromArray:@[@"webdav", @"webdavs"]];
    if (module_exists("smb2") || module_exists("dsm") || module_exists("smb"))
        [schemes addObject:@"smb"];
    if (module_exists("ftp"))
        [schemes addObjectsFromArray:@[@"ftp", @"ftps", @"ftpes"]];
    if (module_exists("sftp"))
        [schemes addObject:@"sftp"];
    if (module_exists("nfs"))
        [schemes addObject:@"nfs"];
    if (module_exists("afp"))
        [schemes addObject:@"afp"];
    return schemes;
}

- (NSView *)accessoryView
{
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 430, 58)];

    _addressField = [[NSComboBox alloc] initWithFrame:NSMakeRect(0, 28, 430, 26)];
    [_addressField setUsesDataSource:YES];
    [_addressField setDataSource:self];
    [_addressField setDelegate:self];
    [_addressField setCompletes:YES];
    [[_addressField cell] setPlaceholderString:@"smb://user@server.example.com/"];
    [view addSubview:_addressField];

    NSTextField *hint = [[NSTextField alloc]
        initWithFrame:NSMakeRect(0, 0, 430, 20)];
    [hint setEditable:NO];
    [hint setSelectable:NO];
    [hint setBezeled:NO];
    [hint setDrawsBackground:NO];
    [hint setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
    [hint setStringValue:[NSString stringWithFormat:_NS("Supported protocols: %@"),
        [[self supportedSchemes] componentsJoinedByString:@", "]]];
    [view addSubview:hint];
    return view;
}

- (void)show
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:_NS("Connect to Server")];
    [alert setInformativeText:_NS("Enter a server address to browse.")];
    _connectButton = [alert addButtonWithTitle:_NS("Connect")];
    [_connectButton setEnabled:NO];
    [alert addButtonWithTitle:_NS("Cancel")];
    [alert setAccessoryView:[self accessoryView]];
    [[alert window] setInitialFirstResponder:_addressField];

    if ([alert runModal] != NSAlertFirstButtonReturn)
        return;

    NSString *mrl = [self currentMRL];
    if (!mrl)
        return;

    [_recents removeObject:mrl];
    [_recents insertObject:mrl atIndex:0];
    while ([_recents count] > VLCConnectToServerMaxRecents)
        [_recents removeLastObject];
    [[NSUserDefaults standardUserDefaults] setObject:_recents
                                               forKey:VLCConnectToServerRecentsKey];

    /* Let NSAlert finish tearing down its modal session before preparsing the
     * server.  A URI without userinfo asks for credentials immediately; if
     * that request is emitted while runModal is still unwinding, AppKit can
     * leave VLC's login dialog waiting in the core without ever presenting
     * its window. */
    [self performSelector:@selector(addNetworkLocationAfterDialog:)
               withObject:mrl
               afterDelay:0.0];
}

- (void)addNetworkLocationAfterDialog:(NSString *)mrl
{
    if ([[[[VLCMain sharedInstance] mainWindow] sidebarDataSource]
            addNetworkLocation:mrl])
        VLCNoteRecentStream(mrl);
}

- (NSInteger)numberOfItemsInComboBox:(NSComboBox *)comboBox
{
    return [_recents count];
}

- (id)comboBox:(NSComboBox *)comboBox objectValueForItemAtIndex:(NSInteger)index
{
    return [_recents objectAtIndex:(NSUInteger)index];
}

- (NSString *)comboBox:(NSComboBox *)comboBox completedString:(NSString *)string
{
    for (NSString *entry in _recents)
        if ([[entry lowercaseString] hasPrefix:[string lowercaseString]])
            return entry;
    return nil;
}

- (void)controlTextDidChange:(NSNotification *)notification
{
    [_connectButton setEnabled:[self currentMRL] != nil];
}

- (void)comboBoxSelectionDidChange:(NSNotification *)notification
{
    NSInteger index = [_addressField indexOfSelectedItem];
    if (index >= 0 && index < (NSInteger)[_recents count])
        [_addressField setStringValue:[_recents objectAtIndex:(NSUInteger)index]];
    [_connectButton setEnabled:[self currentMRL] != nil];
}

- (NSString *)currentMRL
{
    NSString *input = [[_addressField stringValue]
        stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    NSURL *url = [NSURL URLWithString:input];
    NSString *scheme = [[url scheme] lowercaseString];
    if (![input length] || ![scheme length] || ![[url host] length]
        || ![[self supportedSchemes] containsObject:scheme])
        return nil;
    return input;
}

@end
