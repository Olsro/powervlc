/*****************************************************************************
 * VLCLegacyAbout.h: about window for the legacy Mac OS X interface
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

/* Port of the 2.2/3.0 about window: application icon on the left, name,
 * version and compilation info, the "join us" blurb, trademark/copyright
 * lines, and the underlined Credits / License / Authors links that swap
 * the right side for a slowly auto-scrolling text. */
@interface VLCLegacyAbout : NSObject
{
    intf_thread_t *p_intf;
    NSWindow *window;

    NSTextField *nameVersionField;
    NSTextField *revisionField;
    NSTextView *joinusField;
    NSTextField *trademarksField;
    NSTextField *copyrightField;
    NSTextField *attributionField;

    NSScrollView *creditsScroll;
    NSTextView *creditsView;
    NSString *authorsText;
}

- (id)initWithIntf:(intf_thread_t *)intf;
- (void)showAbout;

@end
