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
    [window release];
    [names release];
    [times release];
    [core release];
    [super dealloc];
}

- (NSButton *)makeButton:(NSString *)title action:(SEL)action x:(float)x
                      in:(NSView *)parent
{
    NSButton *button = [[[NSButton alloc]
        initWithFrame:NSMakeRect(x, 10, 88, 28)] autorelease];
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
        initWithContentRect:NSMakeRect(0, 0, 400, 280)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                           | NSResizableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:_NS("Bookmarks")];
    VLCLegacyDenyNativeFullscreen(window);
    [window setReleasedWhenClosed:NO];
    NSView *content = [window contentView];

    [self makeButton:_NS("Add") action:@selector(add:) x:12 in:content];
    [self makeButton:_NS("Remove") action:@selector(remove:) x:104
                  in:content];
    [self makeButton:_NS("Go!") action:@selector(go:) x:300 in:content];

    NSScrollView *scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 48, 400, 232)] autorelease];
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
    [nameColumn setWidth:280];
    [nameColumn setEditable:NO];
    [table addTableColumn:nameColumn];
    NSTableColumn *timeColumn =
        [[[NSTableColumn alloc] initWithIdentifier:@"time"] autorelease];
    [[timeColumn headerCell] setStringValue:_NS("Time")];
    [timeColumn setWidth:80];
    [timeColumn setEditable:NO];
    [table addTableColumn:timeColumn];
    [table setDataSource:(id)self];
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

@end
