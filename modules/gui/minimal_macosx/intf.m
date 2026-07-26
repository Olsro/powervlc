/*****************************************************************************
 * intf.m: macOS minimal interface module
 *****************************************************************************
 * Copyright (C) 2002-2017 VLC authors and VideoLAN
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
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import <vlc_common.h>
#import <vlc_playlist.h>
#import <vlc_interface.h>
#import <vlc_vout_window.h>

#import "VLCMinimalVoutWindow.h"

/*****************************************************************************
 * Local prototypes.
 *****************************************************************************/
static void Run (intf_thread_t *p_intf);

/*****************************************************************************
 * OpenIntf: initialize interface
 *****************************************************************************/
int OpenIntf (vlc_object_t *p_this)
{
    intf_thread_t *p_intf = (intf_thread_t*) p_this;
    msg_Dbg(p_intf, "Using minimal macosx interface");

    p_intf->p_sys = NULL;

    Run(p_intf);

    return VLC_SUCCESS;
}

/*****************************************************************************
 * CloseIntf: destroy interface
 *****************************************************************************/
void CloseIntf (vlc_object_t *p_this)
{
    intf_thread_t *p_intf = (intf_thread_t*) p_this;

    free(p_intf->p_sys);
}

/* Dock Connection */
typedef struct CPSProcessSerNum
{
        UInt32                lo;
        UInt32                hi;
} CPSProcessSerNum;

extern OSErr    CPSGetCurrentProcess(CPSProcessSerNum *psn);
extern OSErr    CPSEnableForegroundOperation(CPSProcessSerNum *psn, UInt32 _arg2, UInt32 _arg3, UInt32 _arg4, UInt32 _arg5);
extern OSErr    CPSSetFrontProcess(CPSProcessSerNum *psn);


/*****************************************************************************
 * Run: main loop
 *****************************************************************************/
static void Run(intf_thread_t *p_intf)
{
    CPSProcessSerNum PSN;
    /* Manual autorelease pool: @autoreleasepool lowers to runtime calls
     * (objc_autoreleasePoolPush) missing before Mac OS X 10.7, and this
     * module is only built when targeting releases without them. Same
     * reasoning for the manual retain/release throughout this file: ARC
     * requires the 10.6 runtime. */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    if (!CPSGetCurrentProcess(&PSN))
        if (!CPSEnableForegroundOperation(&PSN,0x03,0x3C,0x2C,0x1103))
            if (!CPSSetFrontProcess(&PSN))
                [NSApplication sharedApplication];
    [pool release];
}

/*****************************************************************************
 * Vout window management
 *****************************************************************************/
static int WindowControl(vout_window_t *, int i_query, va_list);

/* AppKit windows must be created and torn down on the main thread; blocks
 * and GCD being unavailable, marshal through performSelectorOnMainThread. */
@interface VLCMinimalWindowFactory : NSObject
{
@public
    NSRect rect;
    VLCMinimalVoutWindow *window;
}
- (void)createWindow;
@end

@implementation VLCMinimalWindowFactory
- (void)createWindow
{
    window = [[VLCMinimalVoutWindow alloc] initWithContentRect:rect];
    [window makeKeyAndOrderFront:nil];
}
@end

int WindowOpen(vout_window_t *p_wnd, const vout_window_cfg_t *cfg)
{
    if (cfg->type != VOUT_WINDOW_TYPE_INVALID
     && cfg->type != VOUT_WINDOW_TYPE_NSOBJECT)
        return VLC_EGENERIC;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    VLCMinimalWindowFactory *factory = [[VLCMinimalWindowFactory alloc] init];
    factory->rect = NSMakeRect(cfg->x, cfg->y, cfg->width, cfg->height);
    [factory performSelectorOnMainThread:@selector(createWindow)
                              withObject:nil
                           waitUntilDone:YES];
    VLCMinimalVoutWindow *o_window = factory->window;
    [factory release];

    if (!o_window) {
        msg_Err(p_wnd, "window creation failed");
        [pool release];
        return VLC_EGENERIC;
    }

    msg_Dbg(p_wnd, "returning video window with proposed position x=%i, y=%i, width=%i, height=%i", cfg->x, cfg->y, cfg->width, cfg->height);
    /* The window (created with a +1 retain above, released when closed) is
     * recovered from this view in WindowControl()/WindowClose(). */
    p_wnd->handle.nsobject = (void *)[[o_window contentView] retain];

    p_wnd->type = VOUT_WINDOW_TYPE_NSOBJECT;
    p_wnd->control = WindowControl;

    [pool release];

    vout_window_SetFullScreen(p_wnd, cfg->is_fullscreen);
    return VLC_SUCCESS;
}

static int WindowControl(vout_window_t *p_wnd, int i_query, va_list args)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSWindow* o_window = [(id)p_wnd->handle.nsobject window];
    if (!o_window) {
        msg_Err(p_wnd, "failed to recover cocoa window");
        [pool release];
        return VLC_EGENERIC;
    }

    int i_ret;
    switch (i_query) {
        case VOUT_WINDOW_SET_STATE:
        {
            unsigned i_state = va_arg(args, unsigned);

            [o_window setLevel:i_state];

            i_ret = VLC_SUCCESS;
            break;
        }
        case VOUT_WINDOW_SET_SIZE:
        {
            unsigned int i_width  = va_arg(args, unsigned int);
            unsigned int i_height = va_arg(args, unsigned int);
            NSValue *size = [NSValue valueWithSize:NSMakeSize(i_width, i_height)];
            [(VLCMinimalVoutWindow*)o_window
                performSelectorOnMainThread:@selector(setSizeFromValue:)
                                 withObject:size
                              waitUntilDone:NO];
            i_ret = VLC_SUCCESS;
            break;
        }
        case VOUT_WINDOW_SET_FULLSCREEN:
        {
            int i_full = va_arg(args, int);
            [(VLCMinimalVoutWindow*)o_window
                performSelectorOnMainThread:(i_full ? @selector(enterFullscreen)
                                                    : @selector(leaveFullscreen))
                                 withObject:nil
                              waitUntilDone:NO];
            i_ret = VLC_SUCCESS;
            break;
        }
        default:
            msg_Warn(p_wnd, "unsupported control query");
            i_ret = VLC_EGENERIC;
            break;
    }

    [pool release];
    return i_ret;
}

void WindowClose(vout_window_t *p_wnd)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSView *o_view = (id)p_wnd->handle.nsobject;
    NSWindow *o_window = [o_view window];
    if (o_window)
        /* -close releases the window (releasedWhenClosed defaults to YES
         * for windows created programmatically). */
        [o_window performSelectorOnMainThread:@selector(close)
                                   withObject:nil
                                waitUntilDone:NO];
    /* Balances the retain in WindowOpen(); deferred to the main thread so
     * the view outlives the pending close above. */
    [o_view performSelectorOnMainThread:@selector(release)
                             withObject:nil
                          waitUntilDone:NO];
    [pool release];
}
