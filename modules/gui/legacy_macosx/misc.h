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

/* Command+<digit> for a keyboard whose digits need Shift (AZERTY, QWERTZ):
 * returns the same event carrying the digit its key BEARS, so menu
 * equivalents and core hotkeys match. Returns the event untouched when it
 * is not concerned. See the implementation for why this is needed. */
NSEvent *VLCLegacyEventWithDigitRowFallback(NSEvent *event);

/* Gives a menu item the key equivalent of a core hotkey option ("key-quit",
 * "key-snapshot", ...), the way -[VLCMainMenu setupMenus] does: the menu
 * bar then shows whatever the user configured in the Preferences instead of
 * the compiled-in default. Clears the equivalent when the option is unset.
 * Port of -[VLCStringUtility VLCKeyToString:]/-VLCModifiersToCocoa:. */
void VLCLegacyApplyHotkeyToMenuItem(intf_thread_t *p_intf, NSMenuItem *item,
                                    const char *psz_option);

/* Single volume-stepping entry point of the interface: the volume always
 * lands on the multiple of 5% nearest to the current value in the
 * direction of the change. b_osd shows the hotkeys-style OSD (wheel). */
void VLCLegacyStepVolume(intf_thread_t *p_intf, int direction, bool b_osd);

/* Runtime OS version test (SystemVersion.plist: works from 10.4 up, no
 * Gestalt/CoreServices dependency and no @available, forbidden here). */
BOOL VLCLegacyOSVersionAtLeast(int major, int minor, int micro);

/* Window drop shadows ("legacy-macosx-window-shadows"): read once at
 * interface startup and refreshed when the preferences are saved. The
 * video paths drop the shadow while playing when this returns NO (measured
 * on the G3: ~16% more late pictures with it, on an already saturated
 * machine). Default is on everywhere but the G3 slice (see macosx.c). */
BOOL VLCLegacyWindowShadows(void);
void VLCLegacySetWindowShadows(BOOL enabled);

/* True while the MPEG-2 decoder has published its hardware-display bus.
 * The vout window uses this before the ATI surface is committed, when the
 * context pointer itself can legitimately still be NULL. */
BOOL VLCLegacyHwDecoderArmed(intf_thread_t *p_intf);

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

/* Three AppKit conveniences the interface uses arrived in 10.3, and on 10.2 a
 * single missing .objc_class_name_ symbol stops the WHOLE plug-in from
 * loading -- there is no interface at all, not just no search field. So none
 * of them may be named literally: [NSSearchField alloc] emits a hard link
 * reference, NSClassFromString(@"NSSearchField") does not.
 *
 * These keep one code path for every target rather than a version gate: on
 * 10.3+ each helper does exactly what the literal spelling did. */

/* An NSSearchField where there is one, a plain NSTextField on 10.2. Both are
 * text fields with a target and an action, so 10.2 loses the magnifier and
 * the cancel button and searches on Return instead of on every keystroke --
 * unless the target implements -controlTextDidChange:, which the helper wires
 * up for it (and only in the fallback, so 10.3+ does not fire twice). */
NSTextField *VLCLegacyMakeSearchField(NSRect frame, id target, SEL action);

/* -selectedRowIndexes (10.3), as an ascending array of NSNumbers.
 * -selectedRowEnumerator gives the same rows on 10.2. */
NSArray *VLCLegacySelectedRows(NSTableView *table);

/* -selectRowIndexes:byExtendingSelection: (10.3), single row, replacing the
 * selection. -selectRow:byExtendingSelection: is the 10.2 spelling. */
void VLCLegacySelectRow(NSTableView *table, NSInteger row);

/* NSMenu got a delegate in 10.3. On 10.2 -setDelegate: is not merely
 * ineffective, it raises NSInvalidArgumentException -- and AppKit swallows
 * exceptions raised inside a -performSelectorOnMainThread:, so the rest of
 * the interface setup is skipped and the application draws nothing at all,
 * with the reason left only in /var/tmp/console.log. Returns NO when there
 * is no delegate to set. */
BOOL VLCLegacySetMenuDelegate(NSMenu *menu, id delegate);

/* Creates a menu that rebuilds itself before it is shown: the delegate where
 * there is one, and below 10.3 an NSMenu subclass whose -update calls
 * -menuNeedsUpdate: itself. AppKit calls -update on a menu it is about to
 * display, submenus included, which is precisely when the delegate would
 * have fired.
 * ⚠ -validateMenuItem: is NOT an option for this: AppKit does not validate
 * an item that carries a submenu, so a rebuild hung off it never runs, and
 * the submenu stays empty -- an empty submenu simply does not open, which is
 * how "Audio Device" and "Crop" came to do nothing at all on 10.2. */
NSMenu *VLCLegacyMakeDynamicMenu(NSString *title, id controller);

/* Whether NSMenu delegates work here at all, for the code that has to
 * choose between the two ways of refreshing a dynamic menu. */
BOOL VLCLegacyMenuDelegatesAvailable(void);

/* -[NSView setHidden:] is 10.3 as well, and it is the one missing method the
 * interface cannot simply skip: whole panels are shown and hidden with it.
 * Below 10.3 the view is detached from its superview instead and put back
 * where it was, which is how this was written before -setHidden: existed. */
void VLCLegacySetViewHidden(NSView *view, BOOL hidden);
BOOL VLCLegacyViewIsHidden(NSView *view);

/* Drops what the two functions above remember about a view, which they key by
 * its ADDRESS. A view they detached outlives its owner otherwise, and the next
 * allocation that lands on the freed address inherits its record: the widget
 * an extension dialog builds there is then taken for one already hidden and
 * never detaches again. Call this before letting go of a view for good. */
void VLCLegacyForgetHiddenView(NSView *view);

/* -[NSTableView setColumnAutoresizingStyle:] is 10.4, and its 10.0 ancestor
 * is the reverse switch: -setAutoresizesAllColumnsToFit:NO gives exactly the
 * "last column only" behaviour. It matters more than it sounds -- with all
 * columns resizing proportionally, a column that was squeezed once (the
 * table is laid out before it is put in the window, so the last column gets
 * shrunk to fit) keeps its share of the width for good, which is how the
 * Duration column ended up 15 pixels wide. */
void VLCLegacyResizeLastColumnOnly(NSTableView *table);

/* An outline view that stripes its rows itself where AppKit will not:
 * -setUsesAlternatingRowBackgroundColors: is 10.3, and without it a playlist
 * is a flat white page with no line to follow. Identical to a plain
 * NSOutlineView from 10.3 on. */
@interface VLCLegacyStripedOutlineView : NSOutlineView
@end

/* -[NSView viewWithTag:] walks the view TREE, so it cannot find a view that
 * VLCLegacySetViewHidden() has detached -- and the caller that hid it by tag
 * is usually the one that wants to show it again. (The Preferences toolbar
 * did exactly that: hidden on "Show All", gone for good on the way back.)
 * This looks in the detached set too. */
NSView *VLCLegacyViewWithTag(NSView *root, NSInteger tag);

/* -[NSCell setLineBreakMode:] is only used from 10.5: Tiger advertises it but
 * its NSTextFieldCell implementation crashes in the fullscreen panel. Earlier
 * systems use -setWraps:, losing the ellipsis but retaining safe clipping. */
void VLCLegacySetCellLineBreakMode(NSCell *cell, NSLineBreakMode mode);

/* +[NSFont systemFontSizeForControlSize:] is 10.3. Small and regular are the
 * only sizes this interface asks for, and both have had their own accessor
 * since 10.0. */
CGFloat VLCLegacySystemFontSizeForControlSize(NSControlSize size);

/* +[NSCursor resizeUpDownCursor] is 10.3; the arrow stands in for it. */
NSCursor *VLCLegacyResizeUpDownCursor(void);

/* -[NSPopUpButton selectItemWithTag:] is 10.4, and searching the items for
 * the tag is what it does. Leaves the selection alone if no item matches. */
void VLCLegacySelectItemWithTag(NSPopUpButton *popup, NSInteger tag);

/* -[NSSavePanel setAllowedFileTypes:] is 10.3; -setRequiredFileType: is the
 * single-extension ancestor and all this interface ever needs. */
void VLCLegacySetPanelFileType(NSSavePanel *panel, NSString *extension);

/* The -[NSWindow contentRectForFrameRect:] / -frameRectForContentRect: pair
 * is 10.3. The class methods that take a style mask are not, and give the
 * same answer for a window whose style is known. */
NSRect VLCLegacyContentRectForFrameRect(NSWindow *window, NSRect frame);
NSRect VLCLegacyFrameRectForContentRect(NSWindow *window, NSRect content);

/* The one sort the preferences need, without NSSortDescriptor (10.3) nor
 * -sortUsingDescriptors: (also 10.3): case-insensitive, on the "title" key
 * of each NSDictionary in the array. */
void VLCLegacySortDictionariesByTitle(NSMutableArray *array);

@interface NSScreen (VLCAdditions)
- (BOOL)hasMenuBar;
- (BOOL)hasDock;
- (CGDirectDisplayID)displayID;
/* Hauteur de la bande réservée en haut de l'écran : l'encoche des MacBook Pro
 * 14/16 pouces. Zéro partout ailleurs. */
- (CGFloat)vlcTopSafeAreaInset;
@end

/* Le cadre à donner à la VUE vidéo dans une fenêtre de plein écran.
 *
 * ⚠ La FENÊTRE, elle, garde tout l'écran : une fenêtre qu'on rétrécit pour
 * éviter l'encoche laisse voir le BUREAU dans la bande, et une fenêtre-cache
 * posée par-dessus est repoussée par AppKit (mesuré : y=950 demandé, y=118
 * obtenu, quel que soit le niveau). C'est donc le fond NOIR de la fenêtre de
 * plein écran qui remplit la bande — le rendu du plein écran natif — et la
 * vue vidéo qui s'arrête dessous. */
NSRect VLCLegacySafeContentRect(NSWindow *window, NSScreen *screen);
