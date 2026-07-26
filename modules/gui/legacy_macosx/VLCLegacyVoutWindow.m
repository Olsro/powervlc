/*****************************************************************************
 * VLCLegacyVoutWindow.m: macOS minimal vout window
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

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "VLCLegacyVoutWindow.h"
#import "misc.h"
#import "VLCLegacyCoreInteraction.h"

/* provided by intf.m */
extern VLCLegacyCoreInteraction *VLCLegacyGetCore(void);

#import <Cocoa/Cocoa.h>
/* SetSystemUIMode(): menu bar/Dock hiding available since Mac OS X 10.2,
 * unlike -[NSApplication setPresentationOptions:] which needs 10.6. */
#import <Carbon/Carbon.h>

@implementation VLCLegacyVoutWindow
- (id)initWithContentRect:(NSRect)contentRect
{
    if( self = [super initWithContentRect:contentRect
                                styleMask:NSBorderlessWindowMask
                                  backing:NSBackingStoreBuffered
                                    defer:NO])
    {
        initialFrame = contentRect;
        [self setBackgroundColor:[NSColor blackColor]];
        /* No shadow: the window server recomputes it whenever content
         * near the edges changes, i.e. on every video frame — each GL
         * flush then remaps the window surface (profiled: one frame in
         * three late). Video players of the era all disabled it. */
        [self setHasShadow:NO];
        [self setMovableByWindowBackground:YES];
        /* DVD/BD menus need the vout's mouse-moved events */
        [self setAcceptsMouseMovedEvents:YES];
        /* modern macOS: clip the old-style GL surface (see misc.h) */
        VLCLegacyEnableLayerBackingIfModern([self contentView]);
        [self center];
    }
    return self;
}

/* Main-thread trampoline for VOUT_WINDOW_SET_STATE (see intf.m) */
- (void)setLevelFromNumber:(NSNumber *)value
{
    [self setLevel:[value integerValue]];
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

/* Borderless windows refuse key status by default; without this the
 * keyboard behaviors below never trigger. */
- (BOOL)canBecomeKeyWindow
{
    return YES;
}

/* VLC 3.0 behaviors: double-click toggles fullscreen, Space pauses,
 * Escape leaves fullscreen. The vout OpenGL view forwards unhandled
 * events up the responder chain. */
- (void)mouseDown:(NSEvent *)event
{
    if ([event clickCount] == 2) {
        [VLCLegacyGetCore() toggleFullscreen];
        return;
    }
    [super mouseDown:event];
}

- (void)keyDown:(NSEvent *)event
{
    /* Full 3.0.23 behavior: every key goes to the core hotkey engine */
    if (!VLCLegacyHandleKeyEvent([VLCLegacyGetCore() intf], event))
        [super keyDown:event];
}

- (void)scrollWheel:(NSEvent *)event
{
    /* wheel = volume + native OSD bar, through the core hotkeys */
    VLCLegacyHandleScrollWheel([VLCLegacyGetCore() intf], event);
}

- (void)rightMouseDown:(NSEvent *)event
{
    id delegate = [NSApp delegate];
    if ([delegate respondsToSelector:@selector(menuController)]) {
        id menuController =
            [delegate performSelector:@selector(menuController)];
        if ([menuController respondsToSelector:@selector(voutMenu)]) {
            [NSMenu popUpContextMenu:
                [menuController performSelector:@selector(voutMenu)]
                           withEvent:event
                             forView:[self contentView]];
            return;
        }
    }
    [super rightMouseDown:event];
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
