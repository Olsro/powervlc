/*****************************************************************************
 * VLCLegacyMessages.h: Messages and Errors windows (legacy interface)
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

/* Port of VLCLogWindowController: live view over the libvlc log, with
 * save and clear. The log callback is only registered while the window
 * is visible. */
@interface VLCLegacyMessages : NSObject
{
    intf_thread_t *p_intf;
    NSWindow *window;
    NSTextView *logView;
    BOOL subscribed;
}

- (id)initWithIntf:(intf_thread_t *)intf;
- (void)showWindow;
/* must run before the interface dies (unhooks the libvlc log callback) */
- (void)shutdown;

/* main-thread trampoline for the log callback */
- (void)appendLine:(NSString *)line;

@end

/* Port of VLCErrorWindowController fed by the core dialog provider:
 * collects the error dialogs (vlc_dialog_display_error) in a table. */
@interface VLCLegacyErrorPanel : NSObject
{
    intf_thread_t *p_intf;
    NSWindow *window;
    NSTableView *table;
    NSMutableArray *errors;   /* array of "title: text" strings */
}

- (id)initWithIntf:(intf_thread_t *)intf;
- (void)showWindow;

/* called (on the main thread) by the dialog provider */
- (void)addError:(NSString *)line;

@end
