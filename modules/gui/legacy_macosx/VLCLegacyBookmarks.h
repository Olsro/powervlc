/*****************************************************************************
 * VLCLegacyBookmarks.h: bookmarks window for the legacy interface
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

#import <Cocoa/Cocoa.h>

#include <vlc_common.h>
#include <vlc_interface.h>

@class VLCLegacyCoreInteraction;

/* Port of VLCBookmarksWindowController: add/remove/jump-to bookmarks of the
 * currently playing input. The table works on a snapshot (arrays of names
 * and times) rebuilt from INPUT_GET_BOOKMARKS. */
@interface VLCLegacyBookmarks : NSObject
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;

    NSWindow *window;
    NSTableView *table;
    NSMutableArray *names;   /* NSString */
    NSMutableArray *times;   /* NSString, formatted */
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;
- (void)showWindow;

@end
