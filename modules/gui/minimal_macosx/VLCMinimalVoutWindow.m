/*****************************************************************************
 * VLCMinimalVoutWindow.m: macOS minimal vout window
 *****************************************************************************
 * Copyright (C) 2007-2017 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan.org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
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

/*****************************************************************************
 * Preamble
 *****************************************************************************/

#import "VLCMinimalVoutWindow.h"
#import "misc.h"

#import <Cocoa/Cocoa.h>
/* SetSystemUIMode(): menu bar/Dock hiding available since Mac OS X 10.2,
 * unlike -[NSApplication setPresentationOptions:] which needs 10.6. */
#import <Carbon/Carbon.h>

@implementation VLCMinimalVoutWindow
- (id)initWithContentRect:(NSRect)contentRect
{
    if( self = [super initWithContentRect:contentRect
                                styleMask:NSBorderlessWindowMask
                                  backing:NSBackingStoreBuffered
                                    defer:NO])
    {
        initialFrame = contentRect;
        [self setBackgroundColor:[NSColor blackColor]];
        [self setHasShadow:YES];
        [self setMovableByWindowBackground:YES];
        [self center];
    }
    return self;
}

/* Main-thread trampoline for VOUT_WINDOW_SET_SIZE (see intf.m) */
- (void)setSizeFromValue:(NSValue *)value
{
    NSSize size = [value sizeValue];
    NSRect theFrame = [self frame];
    theFrame.size.width = size.width;
    theFrame.size.height = size.height;
    [self setFrame:theFrame display:YES animate:YES];
}

- (void)enterFullscreen
{
    NSScreen *screen = [self screen];

    initialFrame = [self frame];
    [self setFrame:[[self screen] frame] display:YES animate:YES];

    if ([screen hasMenuBar] || [screen hasDock])
        SetSystemUIMode(kUIModeAllHidden, kUIOptionAutoShowMenuBar);
}

- (void)leaveFullscreen
{
    SetSystemUIMode(kUIModeNormal, 0);
    [self setFrame:initialFrame display:YES animate:YES];
}

@end
