/*****************************************************************************
 * VLCLegacyAddons.h: Addons Manager window (legacy interface)
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
#include <vlc_addons.h>

/* NSInteger/CGFloat only appeared with the 10.5 SDK */
#ifndef NSINTEGER_DEFINED
typedef int NSInteger;
typedef unsigned int NSUInteger;
#define NSINTEGER_DEFINED 1
#endif
#ifndef CGFLOAT_DEFINED
typedef float CGFloat;
#define CGFLOAT_DEFINED 1
#endif

/* Port of VLCAddonsWindowController (3.0.23): type filter, installed-only
 * filter, online catalog download, install/uninstall. The core addons
 * manager reports through plain C callbacks, marshalled to the main
 * thread. */
@interface VLCLegacyAddons : NSObject
{
    intf_thread_t *p_intf;
    addons_manager_t *p_manager;

    NSWindow *window;
    NSPopUpButton *typeSwitcher;
    NSButton *localOnlyCheckbox;
    NSButton *downloadCatalogButton;
    NSButton *installButton;
    NSTableView *table;
    NSProgressIndicator *spinner;
    NSTextField *nameField;
    NSTextField *authorField;
    NSTextField *versionField;
    NSTextView *descriptionView;
    NSTextField *statusField;          /* what the manager is doing */
    NSProgressIndicator *installProgress;

    NSMutableArray *addons;          /* NSValue-wrapped held entries */
    NSMutableArray *displayedAddons; /* filtered view of the above */
    BOOL b_subscribed;

    /* the install/remove in flight, so that its outcome can be reported:
     * the core only tells us "something changed", never whether it worked */
    addon_uuid_t pending_uuid;
    BOOL b_pending;
    BOOL b_pending_install;   /* NO when the pending request is a removal */
    NSString *pendingName;
}

- (id)initWithIntf:(intf_thread_t *)intf;
- (void)showWindow;

/* main-thread trampolines for the manager callbacks */
- (void)addAddonEntry:(NSValue *)entryValue;
- (void)discoveryEnded;
- (void)refreshDisplayedList;

@end
