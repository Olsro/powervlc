/*****************************************************************************
 * misc.h: custom code
 *****************************************************************************
 * Copyright (C) 2012 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne at videolan dot org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
 *          Pierre d'Herbemont <pdherbemont # videolan dot org>
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

/* NSInteger/CGFloat only appeared with the 10.5 SDK; the 10.4 toolchain
 * needs the historical definitions (32-bit only, which is all 10.4 GUIs
 * ever were) */
#ifndef NSINTEGER_DEFINED
typedef int NSInteger;
typedef unsigned int NSUInteger;
#define NSINTEGER_DEFINED 1
#endif
#ifndef CGFLOAT_DEFINED
typedef float CGFloat;
#define CGFLOAT_DEFINED 1
#endif

/* NSEvent -> VLC "key-pressed" forwarding, port of -[VLCVoutView keyDown:]
 * (VLC 3.0.23): Escape always leaves fullscreen, every other key goes to
 * the core hotkey engine so ALL configured shortcuts work during playback
 * (arrows for seeking, volume keys, etc.). Returns YES when handled. */
BOOL VLCLegacyHandleKeyEvent(intf_thread_t *p_intf, NSEvent *event);

/* Checks a key press against the configured core hotkeys ("key-*" options),
 * so windows only steal from the responder chain the keys the core will
 * actually use (Space for play/pause, configured seek keys, ...). Returns
 * 0 when nothing matches, 2 when the key is one of the transport keys the
 * core must see even before menu equivalents (the "forced" list of
 * -[VLCMainWindow performKeyEquivalent:]), 1 for any other match. */
int VLCLegacyEventHotkeyMatch(intf_thread_t *p_intf, NSEvent *event);

/* Scroll wheel over the video: volume goes through VLCLegacyStepVolume
 * (with OSD), the other directions are forwarded as KEY_MOUSEWHEEL* to
 * the core hotkeys. */
void VLCLegacyHandleScrollWheel(intf_thread_t *p_intf, NSEvent *event);

/* Single volume-stepping entry point of the interface: the volume always
 * lands on the multiple of 5% nearest to the current value in the
 * direction of the change. b_osd shows the hotkeys-style OSD (wheel). */
void VLCLegacyStepVolume(intf_thread_t *p_intf, int direction, bool b_osd);

/* Runtime OS version test (SystemVersion.plist: works from 10.4 up, no
 * Gestalt/CoreServices dependency and no @available, forbidden here). */
BOOL VLCLegacyOSVersionAtLeast(int major, int minor, int micro);

/* Spawns a detached "sleep 1; open -n <bundle>" and returns; the caller
 * quits VLC afterwards so the new instance starts fresh (used when
 * switching between the legacy and modern interfaces). */
void VLCLegacyRelaunchApplication(void);

/* Layer-backs a video hosting view on macOS 10.14+ only: there the
 * old-style NSOpenGL surface of the vout is composited over the whole
 * window (it blacked out the controls bar); layer-backing makes AppKit
 * clip it. The old targets keep the plain surface path (layer-backed GL
 * is 10.5+ and risky on their GPUs). Safe no-op below 10.14. */
void VLCLegacyEnableLayerBackingIfModern(NSView *view);

/* Denies Lion's native full screen (the green button) on a legacy window.
 * The legacy UI has its own borderless fullscreen path, and modern AppKit
 * hands EVERY resizable window a native fullscreen button by default —
 * so it has to be refused on the window itself. Shadowing
 * "macosx-nativefullscreenmode" (intf.m) only governs the modern module's
 * own code, never AppKit. Safe no-op below 10.7. */
void VLCLegacyDenyNativeFullscreen(NSWindow *window);

/* PowerVLC: opens a VideoLAN (or sub-domain) URL, but only after the user
 * confirms a warning (translated through the usual gettext catalog) about this
 * being an unofficial fork. Used by every legacy button/link that redirects to
 * VideoLAN. */
void VLCLegacyConfirmAndOpenVideoLANURL(NSURL *url);

@interface NSScreen (VLCAdditions)
- (BOOL)hasMenuBar;
- (BOOL)hasDock;
- (CGDirectDisplayID)displayID;
@end
