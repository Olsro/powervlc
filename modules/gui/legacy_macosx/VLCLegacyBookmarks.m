/*****************************************************************************
 * VLCLegacyBookmarks.m: bookmarks window for the legacy interface
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

#import "VLCLegacyBookmarks.h"
#import "VLCLegacyCoreInteraction.h"
#import "misc.h"

#include <vlc_playlist.h>
#include <vlc_input.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/* NSInteger fallback for pre-10.5 SDKs (see VLCLegacyMainWindow.h) */
#ifndef NSINTEGER_DEFINED
typedef int NSInteger;
typedef unsigned int NSUInteger;
#define NSINTEGER_DEFINED 1
#endif

@implementation VLCLegacyBookmarks

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
{
    if (self = [super init]) {
        core = [interaction retain];
        p_intf = [interaction intf];
        names = [[NSMutableArray alloc] init];
        times = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [clipExportTimer invalidate];
    if (clipExport)
        free(input_ClipExportFinish(clipExport));
    [window release];
    [names release];
    [times release];
    [core release];
    [super dealloc];
}

- (NSButton *)makeButton:(NSString *)title action:(SEL)action
                       x:(float)x y:(float)y width:(float)width
                      in:(NSView *)parent
{
    NSButton *button = [[[NSButton alloc]
        initWithFrame:NSMakeRect(x, y, width, 28)] autorelease];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:self];
    [button setAction:action];
    [parent addSubview:button];
    return button;
}

- (void)buildWindow
{
    window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 760, 400)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                           | NSResizableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:_NS("Bookmarks")];
    [window setMinSize:NSMakeSize(680, 300)];
    VLCLegacyDenyNativeFullscreen(window);
    [window setReleasedWhenClosed:NO];
    NSView *content = [window contentView];

    [self makeButton:_NS("Add") action:@selector(add:)
                   x:12 y:10 width:88 in:content];
    [self makeButton:_NS("Remove") action:@selector(remove:)
                   x:106 y:10 width:88 in:content];
    [self makeButton:_NS("Go!") action:@selector(go:)
                   x:200 y:10 width:88 in:content];

    clipButton = [self makeButton:_NS("Make clip") action:@selector(makeClip:)
                   x:12 y:44 width:130 in:content];
    shareButton = [self makeButton:_NS("Share…")
                   action:@selector(exportCurrent:)
                   x:148 y:44 width:105 in:content];
    [self makeButton:_NS("Import…") action:@selector(importBookmarks:)
                   x:259 y:44 width:105 in:content];
    [self makeButton:_NS("Export all…") action:@selector(exportAll:)
                   x:370 y:44 width:125 in:content];
    [self makeButton:_NS("Delete all saved…") action:@selector(clearAllSaved:)
                   x:501 y:44 width:175 in:content];

    NSScrollView *scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 82, 760, 318)] autorelease];
    [scroll setHasVerticalScroller:YES];
    if ([scroll respondsToSelector:@selector(setAutohidesScrollers:)])
        [scroll setAutohidesScrollers:YES];
    [scroll setBorderType:NSBezelBorder];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    table = [[[NSTableView alloc]
        initWithFrame:[[scroll contentView] bounds]] autorelease];
    NSTableColumn *nameColumn =
        [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [[nameColumn headerCell] setStringValue:_NS("Name")];
    [nameColumn setWidth:590];
    [nameColumn setEditable:YES];
    [table addTableColumn:nameColumn];
    NSTableColumn *timeColumn =
        [[[NSTableColumn alloc] initWithIdentifier:@"time"] autorelease];
    [[timeColumn headerCell] setStringValue:_NS("Time")];
    [timeColumn setWidth:80];
    [timeColumn setEditable:NO];
    [table addTableColumn:timeColumn];
    [table setDataSource:(id)self];
    [table setDelegate:(id)self];
    [table setTarget:self];
    [table setDoubleAction:@selector(go:)];
    [scroll setDocumentView:table];
    [content addSubview:scroll];

    [window center];
}

- (void)showWindow
{
    if (!window)
        [self buildWindow];
    [self reload];
    [window makeKeyAndOrderFront:nil];
}

- (void)reload
{
    [names removeAllObjects];
    [times removeAllObjects];

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        seekpoint_t **pp_bookmarks;
        int i_bookmarks;
        if (input_Control(p_input, INPUT_GET_BOOKMARKS, &pp_bookmarks,
                          &i_bookmarks) == VLC_SUCCESS) {
            int i;
            for (i = 0; i < i_bookmarks; i++) {
                [names addObject:pp_bookmarks[i]->psz_name
                    ? [NSString stringWithUTF8String:
                        pp_bookmarks[i]->psz_name]
                    : @""];
                int seconds =
                    (int)(pp_bookmarks[i]->i_time_offset / CLOCK_FREQ);
                [times addObject:[NSString stringWithFormat:@"%02d:%02d:%02d",
                    seconds / 3600, (seconds / 60) % 60, seconds % 60]];
                vlc_seekpoint_Delete(pp_bookmarks[i]);
            }
            free(pp_bookmarks);
        }
        vlc_object_release(p_input);
    }
    [table reloadData];
    [clipButton setEnabled:[table selectedRow] >= 0 && clipExport == NULL];
    [shareButton setEnabled:[names count] > 0];
}

/*****************************************************************************
 * actions
 *****************************************************************************/

- (void)add:(id)sender
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;

    seekpoint_t *sp = vlc_seekpoint_New();
    if (sp) {
        sp->i_time_offset = var_GetInteger(p_input, "time");
        /* INPUT_ADD_BOOKMARK duplicates the seekpoint and names unnamed
         * bookmarks itself */
        input_Control(p_input, INPUT_ADD_BOOKMARK, sp);
        vlc_seekpoint_Delete(sp);
    }
    vlc_object_release(p_input);
    [self reload];
}

- (void)remove:(id)sender
{
    int row = (int)[table selectedRow];
    if (row < 0)
        return;
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    input_Control(p_input, INPUT_DEL_BOOKMARK, row);
    vlc_object_release(p_input);
    [self reload];
}

- (void)go:(id)sender
{
    int row = (int)[table clickedRow];
    if (row < 0)
        row = (int)[table selectedRow];
    if (row < 0)
        return;
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    input_Control(p_input, INPUT_SET_BOOKMARK, row);
    vlc_object_release(p_input);
}

- (void)showError:(NSString *)title message:(NSString *)message
{
    NSRunAlertPanel(title, @"%@", _NS("OK"), nil, nil, message);
}

- (NSString *)savePathWithName:(NSString *)name
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setRequiredFileType:@"json"];
    if ([panel runModalForDirectory:nil file:name] != NSOKButton)
        return nil;
    return [panel filename];
}

- (void)exportCurrent:(id)sender
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    NSString *path = [self savePathWithName:@"bookmarks.pvlcbookmarks.json"];
    if (path && input_BookmarksExport(p_input,
                                      [path fileSystemRepresentation])
                != VLC_SUCCESS)
        [self showError:_NS("Export failed")
                message:_NS("The bookmarks file could not be written.")];
    vlc_object_release(p_input);
}

- (void)exportAll:(id)sender
{
    NSString *path =
        [self savePathWithName:@"all-bookmarks.pvlcbookmarks.json"];
    if (path && input_BookmarksExportAll(p_intf,
                                         [path fileSystemRepresentation])
                != VLC_SUCCESS)
        [self showError:_NS("Export failed")
                message:_NS("The bookmarks collection could not be written.")];
}

- (void)importBookmarks:(id)sender
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    int result = [panel runModalForDirectory:nil file:nil
                   types:[NSArray arrayWithObject:@"json"]];
    if (result == NSOKButton) {
        const char *path = [[panel filename] fileSystemRepresentation];
        int importResult = p_input ? input_BookmarksImport(p_input, path)
                                   : input_BookmarksImportAll(p_intf, path);
        if (importResult != VLC_SUCCESS)
            [self showError:_NS("Import failed")
                    message:p_input
                        ? _NS("This is not a valid PowerVLC bookmarks file.")
                        : _NS("A single-content file requires its content to be open. Without an open content, import an exported collection.")];
    }
    if (p_input)
        vlc_object_release(p_input);
    [self reload];
}

- (void)clearAllSaved:(id)sender
{
    int answer = NSRunCriticalAlertPanel(
        _NS("Delete all saved bookmarks?"),
        @"%@", _NS("Delete"), _NS("Cancel"), nil,
        _NS("This permanently deletes bookmarks for every content and every disc title. This action cannot be undone."));
    if (answer != NSAlertDefaultReturn)
        return;
    input_BookmarksClearAll(p_intf);
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        input_Control(p_input, INPUT_CLEAR_BOOKMARKS);
        vlc_object_release(p_input);
    }
    [self reload];
}

static NSString *legacyBookmarkDuration(vlc_tick_t duration)
{
    int seconds = (int)(duration / CLOCK_FREQ);
    return [NSString stringWithFormat:@"%02d:%02d:%02d",
            seconds / 3600, (seconds / 60) % 60, seconds % 60];
}

- (void)makeClip:(id)sender
{
    int selected = (int)[table selectedRow];
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input || selected < 0 || clipExport) {
        if (p_input)
            vlc_object_release(p_input);
        return;
    }

    seekpoint_t **pp_bookmarks = NULL;
    int i_bookmarks = 0;
    vlc_tick_t length = var_GetInteger(p_input, "length");
    if (length <= 0
        || input_Control(p_input, INPUT_GET_BOOKMARKS, &pp_bookmarks,
                         &i_bookmarks) != VLC_SUCCESS
        || selected >= i_bookmarks) {
        if (pp_bookmarks) {
            int i;
            for (i = 0; i < i_bookmarks; i++)
                vlc_seekpoint_Delete(pp_bookmarks[i]);
            free(pp_bookmarks);
        }
        vlc_object_release(p_input);
        return;
    }

    vlc_tick_t start = pp_bookmarks[selected]->i_time_offset;
    vlc_tick_t stop = length;
    int i;
    for (i = 0; i < i_bookmarks; i++) {
        vlc_tick_t candidate = pp_bookmarks[i]->i_time_offset;
        if (candidate > start && candidate < stop)
            stop = candidate;
        vlc_seekpoint_Delete(pp_bookmarks[i]);
    }
    free(pp_bookmarks);
    if (stop <= start) {
        vlc_object_release(p_input);
        return;
    }

    NSString *message = [NSString stringWithFormat:
        _NS("Clip duration: %@\n\nCreating the clip can take some time, especially for discs and network content."),
        legacyBookmarkDuration(stop - start)];
    int answer = NSRunAlertPanel(_NS("Create clip?"), @"%@",
                                 _NS("Create"), _NS("Cancel"), nil, message);
    if (answer != NSAlertDefaultReturn) {
        vlc_object_release(p_input);
        return;
    }

    clipExport = input_ClipExportNew(p_intf, p_input, start, stop);
    if (clipExport) {
        clipExportTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
            target:self selector:@selector(pollClipExport:)
            userInfo:nil repeats:YES];
    } else {
        /* Optical discs and inputs with several titles use the existing
         * real-time recording path because they have no standalone file to
         * remux in the background. */
        var_SetInteger(p_input, "record-stop-time", stop);
        var_SetInteger(p_input, "record-start-time", start);
        var_SetFloat(p_input, "record-clip-position",
                     (float)((double)start / (double)length));
        if (var_GetInteger(p_input, "state") == PAUSE_S)
            playlist_TogglePause(pl_Get(p_intf));
    }
    vlc_object_release(p_input);
    [clipButton setEnabled:NO];
}

- (void)pollClipExport:(NSTimer *)timer
{
    if (!clipExport || input_ClipExportIsRunning(clipExport))
        return;
    [clipExportTimer invalidate];
    clipExportTimer = nil;
    char *psz_file = input_ClipExportFinish(clipExport);
    clipExport = NULL;
    if (psz_file) {
        NSString *path = [NSString stringWithUTF8String:psz_file];
        NSString *message = [NSString stringWithFormat:
            _NS("The clip was saved as %@."), [path lastPathComponent]];
        NSRunAlertPanel(_NS("Clip saved"), @"%@", _NS("OK"),
                        nil, nil, message);
    } else
        [self showError:_NS("Clip failed")
                message:_NS("The clip could not be created.")];
    free(psz_file);
    [clipButton setEnabled:[table selectedRow] >= 0];
}

/*****************************************************************************
 * table data source
 *****************************************************************************/

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[names count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (row < 0 || (unsigned)row >= [names count])
        return @"";
    if ([[column identifier] isEqualToString:@"name"])
        return [names objectAtIndex:row];
    return [times objectAtIndex:row];
}

- (void)tableView:(NSTableView *)tableView
    setObjectValue:(id)value
    forTableColumn:(NSTableColumn *)column
               row:(NSInteger)row
{
    if (![[column identifier] isEqualToString:@"name"]
        || row < 0 || (unsigned)row >= [names count])
        return;

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    seekpoint_t **pp_bookmarks = NULL;
    int i_bookmarks = 0;
    if (input_Control(p_input, INPUT_GET_BOOKMARKS, &pp_bookmarks,
                      &i_bookmarks) == VLC_SUCCESS) {
        if (row < i_bookmarks) {
            NSString *newName = [value description];
            if ([newName length] == 0)
                newName = _NS("Untitled");
            free(pp_bookmarks[row]->psz_name);
            pp_bookmarks[row]->psz_name = strdup([newName UTF8String]);
            input_Control(p_input, INPUT_CHANGE_BOOKMARK,
                          pp_bookmarks[row], (int)row);
        }
        int i;
        for (i = 0; i < i_bookmarks; i++)
            vlc_seekpoint_Delete(pp_bookmarks[i]);
        free(pp_bookmarks);
    }
    vlc_object_release(p_input);
    [self reload];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    [clipButton setEnabled:[table selectedRow] >= 0 && clipExport == NULL];
}

@end
