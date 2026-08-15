/*****************************************************************************
 * VLCLegacyMainWindow.m: main window for the legacy Mac OS X interface
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

#import "VLCLegacyMainWindow.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyControls.h"
#import "VLCLegacySeekThumbnailer.h"
#import "VLCLegacyMain.h"
#import "VLCLegacyMenu.h"
#import "VLCLegacyHUDWindow.h"
#import "VLCLegacyVoutWindow.h"
#import "misc.h"

/* SetSystemUIMode(): menu bar/Dock hiding available since Mac OS X 10.2 */
#import <Carbon/Carbon.h>

/* typed objc_msgSend for -setStyleMask: (10.6+, absent from the old SDK
 * headers). <objc/message.h> is a 10.5+ SDK split; the 10.4u SDK declares
 * objc_msgSend in <objc/objc-runtime.h>. */
#if defined(__has_include)
# if __has_include(<objc/message.h>)
#  import <objc/message.h>
# else
#  import <objc/objc-runtime.h>
# endif
#else
# import <objc/objc-runtime.h>
#endif

#include <ctype.h>
#include <fcntl.h>      /* open() — journal de bascule synchrone */
#include <unistd.h>     /* write(), fsync(), close() */

#include <vlc_playlist.h>
#include <vlc_charset.h>
#include <vlc_input.h>
#include <vlc_input_item.h>
#include <vlc_services_discovery.h>
#include <vlc_strings.h>
#include <vlc_url.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

#define SIDEBAR_WIDTH 150.0f
#define BOTTOM_BAR_HEIGHT 36.0f
/* height of the Subscribe / Unsubscribe strip under the podcast list */
#define PODCAST_BAR_HEIGHT 32.0f

/* Accents, case, Latin ligatures and typographic punctuation folded away,
 * through the very function the core-side search uses: the display filter
 * and the playback flags must agree on what matches. */
static NSString *VLCLegacyFoldedString(NSString *string)
{
    if (!string)
        return @"";
    char *psz_folded = vlc_strfold([string UTF8String]);
    if (!psz_folded)
        return string;
    NSString *folded = [NSString stringWithUTF8String:psz_folded];
    free(psz_folded);
    return folded ? folded : string;
}

static NSString *timeToString(int64_t us)
{
    if (us < 0)
        us = 0;
    int seconds = (int)(us / CLOCK_FREQ);
    if (seconds >= 3600)
        return [NSString stringWithFormat:@"%d:%02d:%02d",
                seconds / 3600, (seconds / 60) % 60, seconds % 60];
    return [NSString stringWithFormat:@"%02d:%02d",
            seconds / 60, seconds % 60];
}

/*****************************************************************************
 * VLCLegacyVideoView: VLC 3.0 in-window video behaviors
 *****************************************************************************/

/* Corner grip of the bare window ("Hide controls during playback"): a
 * drag started that close to a corner resizes, anywhere else moves. The
 * video view paints the matching cursors over the same zones -- without
 * them nothing tells the user the corners are grips, the window manager
 * having no frame left to draw. */
#define VLC_LEGACY_HIDDEN_CORNER_ZONE 24.0f

/* Diagonal resize cursors have never been public API; they have however
 * been there since 10.0 under these names. Guarded, with the horizontal
 * one as a fallback -- the drag is driven by the width anyway. */
static NSCursor *VLCLegacyCornerResizeCursor(BOOL northWestSouthEast)
{
    SEL sel = northWestSouthEast
        ? @selector(_windowResizeNorthWestSouthEastCursor)
        : @selector(_windowResizeNorthEastSouthWestCursor);
    if ([NSCursor respondsToSelector:sel]) {
        NSCursor *cursor = [NSCursor performSelector:sel];
        if (cursor != nil)
            return cursor;
    }
    return [NSCursor resizeLeftRightCursor];
}

/* A click on the video must leave the keyboard where the shortcuts are
 * handled. Two window arrangements host the video and both need help:
 * the embedded child window (see VLCLegacyVideoHostWindow) deliberately
 * refuses key status while windowed, and AppKit then simply leaves the
 * key status wherever it was -- click an extension dialog, click back on
 * the video, and Space still goes to the dialog, with no controls bar
 * left to click when they are auto-hidden. The plain arrangement (video
 * as a subview of the main window) keys itself, but only if the click
 * reaches the window, which the vout views do not guarantee. */
static void VLCLegacyRestoreKeyWindowForVideoClick(NSWindow *window)
{
    if (window == nil)
        return;
    if ([window canBecomeKeyWindow]) {
        if (![window isKeyWindow])
            [window makeKeyWindow];
        return;
    }
    NSWindow *parent = [window parentWindow];
    if (parent != nil && ![parent isKeyWindow])
        [parent makeKeyWindow];
}

@implementation VLCLegacyVideoView

- (BOOL)isOpaque
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor blackColor] set];
    NSRectFill(dirtyRect);
}

/* The vout OpenGL view forwards unhandled events up the responder chain;
 * double-click toggles fullscreen, exactly like VLCVideoWindowCommon --
 * except while the controls are auto-hidden, where it brings them back
 * (a plain click only focuses the window, dragging moves it). */
- (void)mouseDown:(NSEvent *)event
{
    extern VLCLegacyMainWindow *VLCLegacyGetMainWindow(void);
    VLCLegacyMainWindow *controller = VLCLegacyGetMainWindow();

    VLCLegacyRestoreKeyWindowForVideoClick([self window]);

    if ([event clickCount] == 2) {
        if ([controller controlsHiddenForPlayback])
            [controller revealControlsForPlayback];
        else
            [core toggleFullscreen];
        return;
    }
    /* dragging the picture always moves the window, controls hidden or
     * not; only the auto-hidden state adds the corner resize zones (there
     * is no window frame left to grab there) */
    if (![controller videoIsFullscreen]) {
        /* screen point, 10.2-safe */
        NSPoint p = [[self window] convertBaseToScreen:
                        [event locationInWindow]];
        [controller beginVideoDragAtScreenPoint:p
                                    allowResize:[controller controlsHiddenForPlayback]];
    }
    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event
{
    extern VLCLegacyMainWindow *VLCLegacyGetMainWindow(void);
    VLCLegacyMainWindow *controller = VLCLegacyGetMainWindow();

    if (![controller videoIsFullscreen]) {
        NSPoint p = [[self window] convertBaseToScreen:
                        [event locationInWindow]];
        [controller dragHiddenControlsToScreenPoint:p];
        return;
    }
    [super mouseDragged:event];
}

- (void)mouseUp:(NSEvent *)event
{
    extern VLCLegacyMainWindow *VLCLegacyGetMainWindow(void);
    [VLCLegacyGetMainWindow() endVideoDrag];
    [super mouseUp:event];
}

- (void)keyDown:(NSEvent *)event
{
    /* Full 3.0.23 behavior: every key goes to the core hotkey engine */
    if (!VLCLegacyHandleKeyEvent([core intf], event))
        [super keyDown:event];
}


- (void)scrollWheel:(NSEvent *)event
{
    /* wheel = volume + native OSD bar, through the core hotkeys */
    VLCLegacyHandleScrollWheel([core intf], event);
}

/* Right-click: the full contextual vout menu of 3.0, owned by the menu
 * controller (dynamic track submenus included) */
- (NSMenu *)menuForEvent:(NSEvent *)event
{
    id delegate = [NSApp delegate];
    if ([delegate respondsToSelector:@selector(menuController)]) {
        id menuController = [delegate performSelector:@selector(menuController)];
        if ([menuController respondsToSelector:@selector(voutMenu)])
            return [menuController performSelector:@selector(voutMenu)];
    }
    return nil;
}

/* explicit popup: 10.6 does not reliably reach menuForEvent through the
 * vout subview */
- (void)rightMouseDown:(NSEvent *)event
{
    NSMenu *menu = [self menuForEvent:event];
    if (menu)
        [NSMenu popUpContextMenu:menu withEvent:event forView:self];
    else
        [super rightMouseDown:event];
}

/* Dropping a media on the video plays it immediately (3.0.23 behavior) */
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    if ([[[sender draggingPasteboard] types]
            containsObject:NSFilenamesPboardType])
        return NSDragOperationCopy;
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSArray *files = [[sender draggingPasteboard]
        propertyListForType:NSFilenamesPboardType];
    if (![files count])
        return NO;
    id delegate = [NSApp delegate];
    if ([delegate isKindOfClass:[VLCLegacyMain class]])
        [[(VLCLegacyMain *)delegate mainWindowController]
            addPaths:files playFirst:YES];
    return YES;
}

@end

/* Dark table header cell (10.4-safe custom drawing) */
/* Playlist snapshot rows.  A plain NSMutableDictionary is unusable as an
 * NSOutlineView item on big nodes: NSDictionary hashes to its key count
 * (every row collides) and compares by deep content, so the outline's
 * internal row map turns collapse/expand of a node with thousands of
 * children (an on-line radio directory) into minutes of CPU.  This
 * subclass behaves like the dictionary it wraps but keeps the default
 * pointer identity/hash. */
@interface VLCLegacyPLEntry : NSMutableDictionary
{
    NSMutableDictionary *backing;
}
@end

@implementation VLCLegacyPLEntry

- (id)init
{
    return [self initWithCapacity:4];
}

- (id)initWithCapacity:(NSUInteger)capacity
{
    if ((self = [super init]))
        backing = [[NSMutableDictionary alloc] initWithCapacity:capacity];
    return self;
}

- (id)initWithObjects:(id const [])objects
              forKeys:(id<NSCopying> const [])keys
                count:(NSUInteger)count
{
    if ((self = [self initWithCapacity:count])) {
        NSUInteger i;
        for (i = 0; i < count; i++)
            [backing setObject:objects[i] forKey:keys[i]];
    }
    return self;
}

- (void)dealloc
{
    [backing release];
    [super dealloc];
}

- (NSUInteger)count
{
    return [backing count];
}

- (id)objectForKey:(id)key
{
    return [backing objectForKey:key];
}

- (NSEnumerator *)keyEnumerator
{
    return [backing keyEnumerator];
}

- (void)setObject:(id)object forKey:(id<NSCopying>)key
{
    [backing setObject:object forKey:key];
}

- (void)removeObjectForKey:(id)key
{
    [backing removeObjectForKey:key];
}

- (NSUInteger)hash
{
    return (NSUInteger)self;
}

- (BOOL)isEqual:(id)other
{
    return other == self;
}

@end

/* value-comparison of two snapshot trees, replacing the isEqualToArray
 * the pointer-identity rows made meaningless (linear, once per rebuild) */
static BOOL VLCLegacySnapshotValueEqual(id a, id b)
{
    if (a == b)
        return YES;
    if (!a || !b)
        return NO;
    return [a isEqual:b];
}

static BOOL VLCLegacySnapshotRowsEqual(NSArray *a, NSArray *b)
{
    if ([a count] != [b count])
        return NO;
    NSUInteger i, count = [a count];
    for (i = 0; i < count; i++) {
        NSDictionary *rowA = [a objectAtIndex:i];
        NSDictionary *rowB = [b objectAtIndex:i];
        if (!VLCLegacySnapshotValueEqual([rowA objectForKey:@"id"],
                                         [rowB objectForKey:@"id"])
         || !VLCLegacySnapshotValueEqual([rowA objectForKey:@"title"],
                                         [rowB objectForKey:@"title"])
         || !VLCLegacySnapshotValueEqual([rowA objectForKey:@"duration"],
                                         [rowB objectForKey:@"duration"])
         || !VLCLegacySnapshotValueEqual([rowA objectForKey:@"arturl"],
                                         [rowB objectForKey:@"arturl"])
         || !VLCLegacySnapshotValueEqual([rowA objectForKey:@"browse"],
                                         [rowB objectForKey:@"browse"]))
            return NO;
        NSArray *childrenA = [rowA objectForKey:@"children"];
        NSArray *childrenB = [rowB objectForKey:@"children"];
        if ((childrenA != nil) != (childrenB != nil))
            return NO;
        if (childrenA && !VLCLegacySnapshotRowsEqual(childrenA, childrenB))
            return NO;
    }
    return YES;
}

/* Reloading a services discovery joins its thread, which may sit in a
 * network fetch: never do it on the main thread. */
struct VLCLegacySDReload {
    playlist_t *playlist;
    char *name;
};

static volatile bool s_sdReloadBusy = false;
static vlc_thread_t s_sdReloadThread;
static BOOL s_sdReloadJoinable = NO;   /* main thread only */

static void *VLCLegacySDReloadThread(void *data)
{
    struct VLCLegacySDReload *req = data;
    playlist_ServicesDiscoveryRemove(req->playlist, req->name);
    playlist_ServicesDiscoveryAdd(req->playlist, req->name);
    free(req->name);
    free(req);
    s_sdReloadBusy = false;
    return NULL;
}

/* VLCLegacySelectRow with the extending variant, same 10.2 fallback */
static void VLCLegacyExtendSelectRow(NSTableView *table, NSInteger row,
                                     BOOL extend)
{
    Class indexSetClass = NSClassFromString(@"NSIndexSet");
    if (indexSetClass != Nil
     && [table respondsToSelector:
            @selector(selectRowIndexes:byExtendingSelection:)])
        [table selectRowIndexes:[indexSetClass indexSetWithIndex:(NSUInteger)row]
           byExtendingSelection:extend];
    else
        [table selectRow:row byExtendingSelection:extend];
}

/* a service node counts as empty when it only carries the error
 * placeholder its script added after a failed discovery */
static BOOL VLCLegacySDNodeLooksEmpty(playlist_item_t *p_node)
{
    if (!p_node)
        return NO;
    if (p_node->i_children <= 0)
        return YES;
    if (p_node->i_children == 1) {
        playlist_item_t *p_child = p_node->pp_children[0];
        if (p_child->i_children < 0 && p_child->p_input
         && p_child->p_input->psz_uri
         && !strcmp(p_child->p_input->psz_uri, "vlc://nop"))
            return YES;
    }
    return NO;
}

@interface VLCLegacyDarkHeaderCell : NSTableHeaderCell
@end
@implementation VLCLegacyDarkHeaderCell
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [[NSColor colorWithCalibratedWhite:0.22 alpha:1.0] set];
    NSRectFill(cellFrame);
    [[NSColor colorWithCalibratedWhite:0.10 alpha:1.0] set];
    NSRectFill(NSMakeRect(NSMaxX(cellFrame) - 1, cellFrame.origin.y,
                          1, cellFrame.size.height));
    NSRectFill(NSMakeRect(cellFrame.origin.x, NSMaxY(cellFrame) - 1,
                          cellFrame.size.width, 1));
    NSMutableDictionary *attributes =
        [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [NSFont boldSystemFontOfSize:11], NSFontAttributeName,
            [NSColor colorWithCalibratedWhite:0.85 alpha:1.0],
            NSForegroundColorAttributeName, nil];
    [[self stringValue] drawAtPoint:
        NSMakePoint(cellFrame.origin.x + 6, cellFrame.origin.y + 3)
                     withAttributes:attributes];
}
@end

/* Split view with a themed divider */
@interface VLCLegacySplitView : NSSplitView
@end
@implementation VLCLegacySplitView
- (void)drawDividerInRect:(NSRect)rect
{
    if (VLCLegacyDarkMode()) {
        [[NSColor colorWithCalibratedWhite:0.08 alpha:1.0] set];
        NSRectFill(rect);
    } else
        [super drawDividerInRect:rect];
}
@end

/* Dropzone container: dropping a media there plays it immediately, like
 * the 3.0.23 dropzone. */
@interface VLCLegacyDropView : NSView
{
@public
    VLCLegacyMainWindow *controller;   /* weak */
}
@end

@implementation VLCLegacyDropView

/* clicking the empty playlist area takes the focus away from the
 * search field, like the 3.0 window */
- (void)mouseDown:(NSEvent *)event
{
    [[self window] makeFirstResponder:nil];
    [super mouseDown:event];
}

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    if ([[[sender draggingPasteboard] types]
            containsObject:NSFilenamesPboardType])
        return NSDragOperationCopy;
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSArray *files = [[sender draggingPasteboard]
        propertyListForType:NSFilenamesPboardType];
    if (![files count])
        return NO;
    [controller addPaths:files playFirst:YES];
    return YES;
}

@end

/* Plain drop-accepting view filling itself with the themed table
 * background; dropping anywhere on the playlist area must work (3.0). */
@interface VLCLegacySolidView : VLCLegacyDropView
@end
@implementation VLCLegacySolidView
- (void)drawRect:(NSRect)dirtyRect
{
    [VLCLegacyTableBackgroundColor() set];
    NSRectFill(dirtyRect);
}
@end

/* Borderless fullscreen host window; must accept key status so Escape and
 * Space keep working in fullscreen. */
@interface VLCLegacyBorderlessWindow : NSWindow
@end

@implementation VLCLegacyBorderlessWindow
- (BOOL)canBecomeKeyWindow
{
    return YES;
}
@end

/*****************************************************************************
 * VLCLegacyVideoHostWindow (chantier F) : fenêtre enfant sans bordure qui
 * héberge la vidéo intégrée, en fenêtré comme en plein écran.
 *****************************************************************************
 * Intérêt : son numéro de fenêtre CGS ne change JAMAIS. La sortie vidéo
 * accélérée lie sa surface à ce numéro ; avec l'ancienne bascule (création
 * d'une fenêtre de plein écran + déménagement de la vue vidéo) le numéro
 * changeait, la surface restait attachée à une fenêtre invisible et il fallait
 * ROUVRIR le décodeur matériel (écran noir jusqu'au prochain en-tête de
 * séquence). Ici le plein écran n'est qu'un `setFrame:` : le WindowServer
 * remet la surface à l'échelle, la bascule est instantanée.
 *
 * `keyable` : en fenêtré la fenêtre hôte NE DOIT PAS prendre le statut de
 * fenêtre clé (la fenêtre principale deviendrait inactive et perdrait le
 * routage clavier) ; en plein écran elle le doit, sans quoi Échap et Espace ne
 * répondent plus. Les gestes sont ceux de la fenêtre vidéo autonome.
 *****************************************************************************/

extern VLCLegacyCoreInteraction *VLCLegacyGetCore(void);

@interface VLCLegacyVideoHostWindow : NSWindow
{
@public
    BOOL keyable;
}
@end

@implementation VLCLegacyVideoHostWindow
- (BOOL)canBecomeKeyWindow
{
    return keyable;
}

- (void)mouseDown:(NSEvent *)event
{
    /* see VLCLegacyRestoreKeyWindowForVideoClick: this window refuses to
     * be key while windowed, so it has to hand the keyboard back to its
     * parent itself */
    VLCLegacyRestoreKeyWindowForVideoClick(self);

    if ([event clickCount] == 2) {
        [VLCLegacyGetCore() toggleFullscreen];
        return;
    }
    [super mouseDown:event];
}

- (void)keyDown:(NSEvent *)event
{
    if (!VLCLegacyHandleKeyEvent([VLCLegacyGetCore() intf], event))
        [super keyDown:event];
}

- (void)scrollWheel:(NSEvent *)event
{
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
@end

/*****************************************************************************
 * VLCLegacyTimeField: the 3.0 time display — click toggles elapsed and
 * remaining time, double-click opens the "Jump to Time" panel
 *****************************************************************************/

@interface VLCLegacyTimeField : NSTextField
{
@public
    VLCLegacyMainWindow *controller;   /* weak */
}
@end

@implementation VLCLegacyTimeField

- (void)mouseDown:(NSEvent *)event
{
    if ([event clickCount] >= 2)
        [controller showJumpToTimePanel];
    else
        [controller toggleTimeDisplay];
}

@end

/*****************************************************************************
 * VLCLegacyHostWindow: hotkey routing of VLCMainWindow
 *****************************************************************************/

extern VLCLegacyCoreInteraction *VLCLegacyGetCore(void);

/* Port of -[VLCMainWindow performKeyEquivalent:]: keys matching a
 * configured core hotkey reach the core no matter which control has
 * focus, so Space pauses audio-only playback even while the playlist
 * table is first responder. */
@interface VLCLegacyHostWindow : NSWindow
@end

@implementation VLCLegacyHostWindow

/* while "Hide controls during playback" strips the title bar (the window
 * turns borderless on 10.6+), the keyboard must keep working: a plain
 * borderless NSWindow refuses key status */
- (BOOL)canBecomeKeyWindow
{
    return YES;
}

- (BOOL)canBecomeMainWindow
{
    return YES;
}

/* when a list (playlist outline, sidebar) has keyboard focus, the plain
 * navigation keys belong to it — arrows move/fold, Return activates —
 * not to the core hotkeys (key-nav-*).  DVD menu navigation still gets
 * them whenever the video view has focus.
 * ⚠ Clip creation trims the selected bound by one frame with the
 * arrows, and on an AUDIO item the playlist is the only thing on screen,
 * so the list always holds the focus: the mode wins there, otherwise the
 * arrows would be dead exactly where trimming by hand matters most. */
static BOOL VLCLegacyKeyBelongsToFocusedList(NSWindow *window, NSEvent *event)
{
    if ([event modifierFlags] & (NSControlKeyMask | NSAlternateKeyMask
                               | NSShiftKeyMask | NSCommandKeyMask))
        return NO;
    if ([VLCLegacyGetCore() clipCreationMode])
        return NO;
    if (![[window firstResponder] isKindOfClass:[NSTableView class]])
        return NO;
    NSString *chars = [event charactersIgnoringModifiers];
    if (![chars length])
        return NO;
    unichar key = [chars characterAtIndex:0];
    return key == NSUpArrowFunctionKey || key == NSDownArrowFunctionKey
        || key == NSLeftArrowFunctionKey || key == NSRightArrowFunctionKey
        || key == NSEnterCharacter || key == NSCarriageReturnCharacter;
}

- (BOOL)performKeyEquivalent:(NSEvent *)event
{
    /* never steal keystrokes from text editing (search field) */
    if ([[self firstResponder] isKindOfClass:[NSText class]])
        return [super performKeyEquivalent:event];

    if (VLCLegacyKeyBelongsToFocusedList(self, event))
        return [super performKeyEquivalent:event];

    /* Command+<digit> on a keyboard whose digits need Shift: substitute the
     * digit the key bears, or neither the menu nor the core would match
     * (see VLCLegacyEventWithDigitRowFallback). Done before anything else
     * so both paths below see the same event -- and AFTER the text editing
     * guard above, which must keep the real characters. */
    event = VLCLegacyEventWithDigitRowFallback(event);

    intf_thread_t *p_intf = [VLCLegacyGetCore() intf];
    int match = VLCLegacyEventHotkeyMatch(p_intf, event);
    /* the transport keys the core must always see, even when a menu item
     * carries the same equivalent (same list as VLCMainWindow) */
    if (match == 2)
        return VLCLegacyHandleKeyEvent(p_intf, event);

    /* ⚠ The menu has to be looked up TWICE, because no single way of doing it
     * works on both ends of the supported range -- measured, not guessed:
     *
     *  - on 10.2 (iBook G3, Jaguar 10.2.8) asking [NSApp mainMenu] straight
     *    out DOES fire the item: Command+0 halved the window;
     *  - on macOS 15 that same call never matched anything (traced on all
     *    four window size shortcuts). There, the menu is only reached by
     *    REFUSING the key, so that AppKit carries on with its own dispatch.
     *
     * Refusing alone is not enough either: it left Command+0 dead on Jaguar.
     * So: ask, and if that draws a blank, refuse -- never hand the key to the
     * core in between, which is what used to happen and what broke Half Size
     * on modern systems. The core binds Command+0 TWICE upstream (key-zoom-half
     * AND key-subtitle-text-scale-normal, see libvlc-module.c) and resolves it
     * to the subtitle scale, so the shortcut moved the subtitle size instead of
     * the window.
     * A key no menu item claims comes back as a plain key press, and -keyDown:
     * below (or the video view's) hands it to the core exactly as before. */
    if ([[NSApp mainMenu] performKeyEquivalent:event])
        return YES;
    return [super performKeyEquivalent:event];
}

/* Older AppKit releases do not reliably offer modifier-less key presses
 * to performKeyEquivalent:; unhandled ones bubble up here instead */
- (void)keyDown:(NSEvent *)event
{
    if (VLCLegacyKeyBelongsToFocusedList(self, event)) {
        [super keyDown:event];
        return;
    }
    intf_thread_t *p_intf = [VLCLegacyGetCore() intf];
    if (VLCLegacyEventHotkeyMatch(p_intf, event)
        && VLCLegacyHandleKeyEvent(p_intf, event))
        return;
    [super keyDown:event];
}

/* ★ Relais des « souris déplacée » vers la fenêtre vidéo enfant.
 *
 * AppKit ne distribue les événements NSMouseMoved qu'à la fenêtre CLÉ — le
 * -setAcceptsMouseMovedEvents:YES d'une fenêtre non clé ne sert à rien. En
 * FENÊTRÉ la vidéo vit dans VLCLegacyVideoHostWindow, une fenêtre enfant qui
 * refuse délibérément ce statut (keyable = NO, sans quoi la fenêtre principale
 * perdrait le routage clavier) : la vue du vout n'y voit donc jamais passer le
 * pointeur. Les clics, eux, sont routés par test de survol et arrivent bien,
 * d'où des menus DVD/Blu-ray qui « réagissent mal » (aucun surlignage ne suit
 * la souris, le clic valide le bouton resté sélectionné) plutôt que pas du
 * tout. En PLEIN ÉCRAN la fenêtre hôte est clé : rien à relayer, ce qui
 * explique que le défaut ne se voie qu'en fenêtré.
 *
 * On resynthétise l'événement dans le repère de l'enfant : réacheminer
 * l'original enverrait des coordonnées de la fenêtre PRINCIPALE, que le
 * -[NSView convertPoint:fromView:nil] du vout interpréterait dans celles de
 * l'enfant (le vout convertit toujours depuis SA fenêtre, pas celle de
 * l'événement). */
- (void)relayMouseMovedToVideoChild:(NSEvent *)event
{
    NSEnumerator *children = [[self childWindows] objectEnumerator];
    NSWindow *child;

    while ((child = [children nextObject]) != nil) {
        if (![child isKindOfClass:[VLCLegacyVideoHostWindow class]]
            || [child isKeyWindow])
            continue;

        NSPoint screen = [self convertBaseToScreen:[event locationInWindow]];
        NSPoint local = [child convertScreenToBase:screen];
        /* hitTest: attend le point dans le repère du SUPERVIEW du receveur ;
         * pour une contentView c'est le repère de base de la fenêtre. */
        NSView *hit = [[child contentView] hitTest:local];
        if (hit == nil)
            return;

        NSEvent *relayed = [NSEvent mouseEventWithType:NSMouseMoved
                                              location:local
                                         modifierFlags:[event modifierFlags]
                                             timestamp:[event timestamp]
                                          windowNumber:[child windowNumber]
                                               context:nil
                                           eventNumber:0
                                            clickCount:0
                                              pressure:0.0];
        if (relayed != nil)
            [hit mouseMoved:relayed];
        return;
    }
}

- (void)sendEvent:(NSEvent *)event
{
    if ([event type] == NSMouseMoved)
        [self relayMouseMovedToVideoChild:event];
    [super sendEvent:event];
}

@end

/* default main window title ("Lecteur multimédia PowerVLC" in French) */
static NSString *VLCLegacyDefaultWindowTitle(void)
{
    return [NSString stringWithUTF8String:
        vlc_gettext("PowerVLC media player")];
}

/*****************************************************************************
 * VLCLegacySidebarCell: source-list text cell with a leading icon,
 * the 3.0 sidebar look (PXSourceList) for the plain NSTableView
 *****************************************************************************/

@interface VLCLegacySidebarCell : NSTextFieldCell
{
    NSImage *icon;
    BOOL headerStyle;   /* draw the title at the bottom of a taller row */
    int badge;          /* item count pill on the right, hidden when 0 */
}
- (void)setIcon:(NSImage *)image;
- (void)setHeaderStyle:(BOOL)flag;
- (void)setBadge:(int)count;
@end

@implementation VLCLegacySidebarCell

- (void)setIcon:(NSImage *)image
{
    [icon autorelease];
    icon = [image retain];
}

- (void)setHeaderStyle:(BOOL)flag
{
    headerStyle = flag;
}

- (void)setBadge:(int)count
{
    badge = count;
}

- (id)copyWithZone:(NSZone *)zone
{
    VLCLegacySidebarCell *copy = [super copyWithZone:zone];
    copy->icon = [icon retain];
    return copy;
}

- (void)dealloc
{
    [icon release];
    [super dealloc];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    NSRect frame = cellFrame;
    if (headerStyle && frame.size.height > 18.0f) {
        /* the extra row height is spacing ABOVE the category title */
        float extra = frame.size.height - 18.0f;
        if ([controlView isFlipped])
            frame.origin.y += extra;
        frame.size.height = 18.0f;
    }
    if (icon) {
        NSSize size = [icon size];
        NSRect iconRect =
            NSMakeRect(frame.origin.x + 2,
                       frame.origin.y + (frame.size.height - size.height) / 2,
                       size.width, size.height);
        /* pre-10.6 flip handling: no respectFlipped: on 10.4 */
        BOOL wasFlipped = [icon isFlipped];
        [icon setFlipped:[controlView isFlipped]];
        [icon drawInRect:iconRect
                fromRect:NSZeroRect
               operation:NSCompositeSourceOver
                fraction:1.0f];
        [icon setFlipped:wasFlipped];
        float shift = size.width + 6;
        frame.origin.x += shift;
        frame.size.width -= shift;
    }
    /* the 3.0 badge pill (PXSourceListBadgeCell look): rounded rect on
     * the right with the item count, only when > 0 */
    if (badge > 0 && !headerStyle) {
        NSString *text = [NSString stringWithFormat:@"%d", badge];
        NSFont *font = [NSFont boldSystemFontOfSize:11];
        BOOL selected = [self isHighlighted];
        NSColor *pillColor = selected
            ? [NSColor whiteColor]
            : [NSColor colorWithCalibratedRed:152.0f / 255.0f
                                        green:168.0f / 255.0f
                                         blue:202.0f / 255.0f
                                        alpha:1.0f];
        NSColor *textColor = selected
            ? [NSColor colorWithCalibratedRed:153.0f / 255.0f
                                        green:169.0f / 255.0f
                                         blue:203.0f / 255.0f
                                        alpha:1.0f]
            : [NSColor whiteColor];
        NSDictionary *attributes = [NSDictionary
            dictionaryWithObjectsAndKeys:
                font, NSFontAttributeName,
                textColor, NSForegroundColorAttributeName, nil];
        NSSize textSize = [text sizeWithAttributes:attributes];
        float pillHeight = textSize.height + 1.0f;
        float pillWidth = textSize.width + 10.0f;
        if (pillWidth < pillHeight)
            pillWidth = pillHeight;
        /* pinned to the very right of the cell (next to the scroller),
         * growing leftwards with the number of digits */
        NSRect pill = NSMakeRect(
            NSMaxX(frame) - pillWidth - 2.0f,
            frame.origin.y + (frame.size.height - pillHeight) / 2.0f,
            pillWidth, pillHeight);
        [pillColor set];
        [VLCLegacyRoundedRectPath(pill, pillHeight / 2.0f) fill];
        [text drawAtPoint:NSMakePoint(pill.origin.x + 5.0f,
                                      pill.origin.y + 0.5f)
           withAttributes:attributes];
        frame.size.width -= pillWidth + 4.0f;
    }
    /* vertically center the label on the row (the default text cell
     * draws top-aligned next to the taller 16 px icons) */
    if (!headerStyle) {
        float textHeight = [[self attributedStringValue] size].height;
        if (textHeight > 0 && textHeight < frame.size.height) {
            float inset = (frame.size.height - textHeight) / 2.0f;
            if ([controlView isFlipped])
                frame.origin.y += inset;
            frame.size.height = textHeight;
        }
    }
    [super drawInteriorWithFrame:frame inView:controlView];
}

@end

/*****************************************************************************
 * VLCLegacyMainWindow
 *****************************************************************************/

/* Set from playlist callbacks (arbitrary threads); the refresh timer only
 * rebuilds the table snapshot when something actually changed, so an idle
 * or paused player no longer burns CPU walking the playlist every 300 ms */
static volatile BOOL s_playlistDirty = YES;
/* bumped on every change: lets the refresh tell "one edit" from a long
 * burst (a service discovery like Icecast adds thousands of stations
 * one by one) and coalesce the reloads */
static volatile int s_playlistChangeCounter = 0;

static int PlaylistChangedCallback(vlc_object_t *p_this,
                                   const char *psz_variable,
                                   vlc_value_t oldval, vlc_value_t newval,
                                   void *param)
{
    (void)p_this; (void)psz_variable; (void)oldval; (void)newval;
    (void)param;
    s_playlistDirty = YES;
    s_playlistChangeCounter++;
    return VLC_SUCCESS;
}

/* every playlist change the snapshot must reflect: items added/removed,
 * item metadata (title, duration, artwork), current item (bold row) */
static const char *const changeVariables[] = {
    "playlist-item-append", "playlist-item-deleted", "item-change",
    "leaf-to-parent", "input-current"
};

/* internal drag flavour: identifies a drag that started in our own outline
 * (VLCPLItemPasteboadType port). The actual dragged rows are kept in the
 * draggedItems ivar; the pasteboard only carries a marker. */
static NSString *const VLCLegacyPlaylistItemPboardType =
    @"VLCLegacyPlaylistItemPboardType";

/* NSUserDefaults key for the persisted cover-art panel height */
static NSString *const VLCLegacyArtHeightKey = @"VLCLegacySidebarArtHeight";
#define VLC_ART_DIVIDER_THICKNESS 6.0
#define VLC_ART_MIN_HEIGHT        40.0
#define VLC_ART_MIN_LIST_HEIGHT   80.0

/* Base for the views stacked in the sidebar pane.
 *
 * That pane is a bare NSView: it has no -drawRect:, so it never erases
 * anything, and on 10.4/10.5 AppKit there is no per-view backing store to
 * clear either. A subview that leaves part of its bounds unpainted, or
 * that is moved or resized, therefore leaves its previous pixels on the
 * screen — the trails seen on a G3 while dragging the artwork divider or
 * resizing the window. Both hazards are handled here: every pixel of the
 * dirty rect is painted, and moving the view repaints what it stops
 * covering. */
@interface VLCLegacySidebarView : NSView
- (void)eraseBackground:(NSRect)rect;
- (void)invalidateVacatedArea:(NSRect)oldFrame;
@end

@implementation VLCLegacySidebarView
/* we paint every pixel of our bounds, so AppKit can skip what is behind */
- (BOOL)isOpaque { return YES; }

- (void)eraseBackground:(NSRect)rect
{
    /* CLAMP: the rect handed to -drawRect: is the region invalidated in
     * the enclosing pane, which is routinely TALLER than this view (the
     * pane invalidates its whole height). Filling it as-is would paint
     * over the sibling views — it blanked the sidebar list and the cover
     * during development. Only ever paint our own bounds. */
    NSRect fill = NSIntersectionRect(rect, [self bounds]);
    if (NSIsEmptyRect(fill))
        return;

    NSColor *background = [[self window] backgroundColor];
    if (!background)
        background = [NSColor windowBackgroundColor];
    /* a textured window hands out a pattern colour: anchor it on the
     * window, not on this view, or the fill shows a seam */
    if ([[NSGraphicsContext currentContext]
            respondsToSelector:@selector(setPatternPhase:)])
        [[NSGraphicsContext currentContext]
            setPatternPhase:[self convertPoint:NSZeroPoint toView:nil]];
    [background set];
    NSRectFill(fill);
}

- (void)drawRect:(NSRect)dirtyRect
{
    [self eraseBackground:dirtyRect];
}

- (void)invalidateVacatedArea:(NSRect)oldFrame
{
    NSRect updated = [self frame];
    if (NSEqualRects(oldFrame, updated))
        return;
    /* repaint what we stop covering: nothing else in this pane erases */
    [[self superview] setNeedsDisplayInRect:NSUnionRect(oldFrame, updated)];
    [self setNeedsDisplay:YES];
}

/* -setFrame: is not the only path in: the autoresizing machinery moves
 * and resizes through -setFrameOrigin:/-setFrameSize: directly */
- (void)setFrame:(NSRect)frame
{
    NSRect old = [self frame];
    [super setFrame:frame];
    [self invalidateVacatedArea:old];
}

- (void)setFrameSize:(NSSize)size
{
    NSRect old = [self frame];
    [super setFrameSize:size];
    [self invalidateVacatedArea:old];
}

- (void)setFrameOrigin:(NSPoint)origin
{
    NSRect old = [self frame];
    [super setFrameOrigin:origin];
    [self invalidateVacatedArea:old];
}
@end

/* A thin draggable handle sitting between the sidebar list and the cover
 * art at the bottom of it; dragging it resizes the art panel. The height
 * is remembered across sessions (see the controller's persistence). */
@protocol VLCLegacyArtDividerDelegate <NSObject>
- (void)artDividerDraggedToPaneY:(CGFloat)y;
@end

@interface VLCLegacyArtDivider : VLCLegacySidebarView
{
    id<VLCLegacyArtDividerDelegate> dragDelegate;   /* weak */
}
- (void)setDragDelegate:(id<VLCLegacyArtDividerDelegate>)delegate;
@end

@implementation VLCLegacyArtDivider
- (void)setDragDelegate:(id<VLCLegacyArtDividerDelegate>)delegate
{
    dragDelegate = delegate;
}
- (BOOL)isFlipped { return NO; }
- (void)drawRect:(NSRect)dirtyRect
{
    NSRect b = [self bounds];
    /* erase first: the handle only draws a hairline, the rest of it would
     * otherwise keep the pixels of wherever it was dragged from */
    [self eraseBackground:dirtyRect];
    /* A subtle separator line along the top edge of the handle.
     * ⚠ NSRectFill() copies, it does not blend: the 15%-alpha colour lands
     * in the backing store as it is, and where that store has no alpha to
     * spend -- 10.2 -- the "subtle" hairline comes out solid black. Filling
     * through NSCompositeSourceOver blends it against what is already
     * there, which is what was meant, on every version. */
    [[NSColor colorWithCalibratedWhite:(VLCLegacyDarkMode() ? 1.0 : 0.0)
                                 alpha:0.15] set];
    NSRectFillUsingOperation(NSMakeRect(0, b.size.height - 1,
                                        b.size.width, 1),
                             NSCompositeSourceOver);
}
- (void)resetCursorRects
{
    [self addCursorRect:[self bounds] cursor:VLCLegacyResizeUpDownCursor()];
}
- (void)mouseDown:(NSEvent *)event    { [self relayDrag:event]; }
- (void)mouseDragged:(NSEvent *)event { [self relayDrag:event]; }
- (void)relayDrag:(NSEvent *)event
{
    NSView *pane = [self superview];
    NSPoint p = [pane convertPoint:[event locationInWindow] fromView:nil];
    [dragDelegate artDividerDraggedToPaneY:p.y];
}
@end

/* Cover-art view. NSImageView's built-in NSScaleProportionally uses the
 * low-quality (nearest-neighbour) scaler on the old AppKit, so a full-size
 * album cover shown in the narrow sidebar comes out blocky on the low-DPI
 * screens these machines drive (modern/Retina Macs hide it). We draw the
 * image ourselves with NSImageInterpolationHigh: the smooth scaler runs
 * once per redraw and gives a clean downscale. Fit is aspect-proportional,
 * centred, matching the previous NSScaleProportionally look. */
@interface VLCLegacyArtImageView : VLCLegacySidebarView
{
    NSImage *artImage;
}
- (void)setImage:(NSImage *)image;
@end

@implementation VLCLegacyArtImageView
- (void)setImage:(NSImage *)image
{
    if (image == artImage)
        return;
    [image retain];
    [artImage release];
    artImage = image;
    [self setNeedsDisplay:YES];
}
- (void)dealloc
{
    [artImage release];
    [super dealloc];
}
- (void)drawRect:(NSRect)dirtyRect
{
    /* the cover is aspect-fitted and centred, so it never covers the whole
     * view: erase before drawing it, otherwise the bands on either side
     * keep the previous size (or the previous cover) on screen */
    [self eraseBackground:dirtyRect];

    NSSize src = artImage ? [artImage size] : NSZeroSize;
    if (src.width <= 0 || src.height <= 0)
        return;
    NSRect b = [self bounds];
    /* aspect-fit inside the panel (NSScaleProportionally parity) */
    CGFloat scale = b.size.width / src.width;
    CGFloat sy = b.size.height / src.height;
    if (sy < scale)
        scale = sy;
    NSSize drawn = NSMakeSize(src.width * scale, src.height * scale);
    NSRect dst = NSMakeRect(b.origin.x + (b.size.width  - drawn.width)  / 2.0,
                            b.origin.y + (b.size.height - drawn.height) / 2.0,
                            drawn.width, drawn.height);
    if ([[NSGraphicsContext currentContext]
            respondsToSelector:@selector(setImageInterpolation:)])
        [[NSGraphicsContext currentContext]
            setImageInterpolation:NSImageInterpolationHigh];
    [artImage drawInRect:dst
                fromRect:NSZeroRect
               operation:NSCompositeSourceOver
                fraction:1.0];
}
@end

@implementation VLCLegacyMainWindow

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
{
    if (self = [super init]) {
        core = [interaction retain];
        p_intf = [interaction intf];
        items = [[NSMutableArray alloc] init];
        artworkCache = [[NSMutableDictionary alloc] init];
        expandedItemIds = [[NSMutableSet alloc] init];
        browseRequestedIds = [[NSMutableDictionary alloc] init];
        dirCheckCache = [[NSMutableDictionary alloc] init];
        sidebarItems = [[NSMutableArray alloc] init];
        activatedServices = [[NSMutableSet alloc] init];
        sidebarSelection = 1;   /* the Playlist row (below the header) */
        currentItemId = -1;
        showTimeRemaining = [[NSUserDefaults standardUserDefaults]
            boolForKey:@"DisplayTimeAsTimeRemaining"];
        NSArray *storedColumns = [[NSUserDefaults standardUserDefaults]
            stringArrayForKey:@"VLCLegacyPlaylistColumns"];
        visibleColumns = storedColumns
            ? [[NSMutableArray alloc] initWithArray:storedColumns]
            : [[NSMutableArray alloc] initWithObjects:
                @"title", @"duration", nil];
        fileSizeCache = [[NSMutableDictionary alloc] init];
        lastRepeatState = -1;
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [updateTimer invalidate];
    [fsVideoWindow release];
    [videoHostWindow release];
    [jumpPanel release];
    [sidebarScroll release];
    [sidebarPane release];
    [sidebarArtUrl release];
    [searchString release];
    [searchStringFolded release];
    [visibleColumns release];
    [fileSizeCache release];
    [resumeTrackedURI release];
    [fsBlackWindows release];
    [window release];
    [items release];
    [draggedItems release];
    [artworkCache release];
    [expandedItemIds release];
    [browseRequestedIds release];
    [dirCheckCache release];
    [sidebarItems release];
    [activatedServices release];
    [core release];
    [super dealloc];
}

/*****************************************************************************
 * UI construction (main thread only)
 *****************************************************************************/

/* both themes use the 3.0 bottom bar artwork (rectangular framed buttons);
 * the dark set carries the -dark suffixes */
static NSString *themedImage(NSString *lightName, NSString *darkName)
{
    return VLCLegacyDarkMode() ? darkName : lightName;
}

- (void)setupWindow
{
    /* Geometry cloned from the VLC 3.0 main window */
    NSRect contentRect = NSMakeRect(200, 200, 690, 440);
    window = [[VLCLegacyHostWindow alloc] initWithContentRect:contentRect
                                         styleMask:NSTitledWindowMask
                                                  | NSClosableWindowMask
                                                  | NSMiniaturizableWindowMask
                                                  | NSResizableWindowMask
                                           backing:NSBackingStoreBuffered
                                             defer:NO];
    [window setTitle:VLCLegacyDefaultWindowTitle()];
    [window setMinSize:NSMakeSize(604, 310)];
    /* the green button must zoom, never enter Lion's native full screen:
     * the legacy fullscreen is the borderless path in VLCLegacyVoutWindow */
    VLCLegacyDenyNativeFullscreen(window);
    /* The controller owns the window (released in -dealloc) */
    [window setReleasedWhenClosed:NO];
    [window setDelegate:(id)self];
    /* DVD/BD menu navigation: dvdnav only knows where the pointer is from
     * the vout's mouse-moved events, which AppKit does not deliver unless
     * the hosting window asks for them */
    [window setAcceptsMouseMovedEvents:YES];
    if (VLCLegacyDarkMode())
        [window setBackgroundColor:
            [NSColor colorWithCalibratedWhite:0.16 alpha:1.0]];
    NSView *content = [window contentView];
    /* Modern macOS only: layer-back the WHOLE content view. A non-layered
     * window with an old-style NSOpenGL surface inside composites the
     * surface over everything (the controls bar turned invisible under
     * video); with the full subtree layered, the GL becomes a properly
     * z-ordered layer. Mixed layered/non-layered siblings do NOT fix it. */
    VLCLegacyEnableLayerBackingIfModern(content);
    float W = contentRect.size.width;

    /* --- bottom bar, VLC 3.0 style --- */
    VLCLegacyBottomBarView *bar = [[[VLCLegacyBottomBarView alloc]
        initWithFrame:NSMakeRect(0, 0, W, BOTTOM_BAR_HEIGHT)] autorelease];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [content addSubview:bar];
    bottomBar = bar;    /* "Hide controls during playback" needs a handle */

    /* The 3.0 framed buttons at their natural sizes: the transport
     * cluster is flush like MainWindow.xib, stop and the playlist
     * toggle stand apart. Tooltips are the 3.0 ones. The exact frames
     * come from -layoutControlsBar (they depend on the View menu
     * toggles). */
    previousButton = VLCLegacyImageButton(bar,
        themedImage(@"previous-6btns", @"previous-6btns-dark"),
        themedImage(@"previous-6btns-pressed", @"previous-6btns-dark-pressed"),
        NSMakeRect(12, 7, 29, 23), self, @selector(prev:));
    [previousButton setToolTip:_NS("Previous")];
    /* combined previous/seek button (3.0 semantics: click changes item,
     * holding seeks); becomes a plain seek button in jump-buttons mode */
    backwardButton = VLCLegacyImageButton(bar,
        themedImage(@"backward-3btns", @"backward-3btns-dark"),
        themedImage(@"backward-3btns-pressed", @"backward-3btns-dark-pressed"),
        NSMakeRect(12, 7, 29, 23), self, @selector(bwd:));
    [backwardButton setToolTip:_NS("Backward")];
    [backwardButton setContinuous:YES];
    playButton = VLCLegacyImageButton(bar,
        themedImage(@"play", @"play_dark"),
        themedImage(@"play-pressed", @"play-pressed_dark"),
        NSMakeRect(41, 7, 27, 23), self, @selector(playPause:));
    [playButton setToolTip:_NS("Play")];
    forwardButton = VLCLegacyImageButton(bar,
        themedImage(@"forward-3btns", @"forward-3btns-dark"),
        themedImage(@"forward-3btns-pressed", @"forward-3btns-dark-pressed"),
        NSMakeRect(68, 7, 29, 23), self, @selector(fwd:));
    [forwardButton setToolTip:_NS("Forward")];
    [forwardButton setContinuous:YES];
    nextButton = VLCLegacyImageButton(bar,
        themedImage(@"next-6btns", @"next-6btns-dark"),
        themedImage(@"next-6btns-pressed", @"next-6btns-dark-pressed"),
        NSMakeRect(97, 7, 29, 23), self, @selector(next:));
    [nextButton setToolTip:_NS("Next")];
    stopButton = VLCLegacyImageButton(bar,
        themedImage(@"stop", @"stop_dark"),
        themedImage(@"stop-pressed", @"stop-pressed_dark"),
        NSMakeRect(105, 7, 29, 23), self, @selector(stop:));
    [stopButton setToolTip:_NS("Stop")];
    /* playlist-1btn is the standalone variant: playlist-btn is a segment
     * asset without its right border, which looked clipped */
    viewToggleButton = VLCLegacyImageButton(bar,
        themedImage(@"playlist-1btn", @"playlist-1btn-dark"),
        themedImage(@"playlist-1btn-pressed", @"playlist-1btn-dark-pressed"),
        NSMakeRect(144, 7, 29, 23), self, @selector(toggleView:));
    [viewToggleButton setToolTip:_NS("Show/Hide Playlist")];

    /* optional repeat/shuffle cluster (View > Show Shuffle & Repeat
     * Buttons), flush after the playlist toggle like 3.0 -- repeat FIRST
     * then shuffle (the 3.0 order; repeat.png is a middle segment whose
     * flat right edge must abut the shuffle cap) */
    repeatButton = VLCLegacyImageButton(bar,
        themedImage(@"repeat", @"repeat_dark"),
        themedImage(@"repeat-pressed", @"repeat-pressed_dark"),
        NSMakeRect(173, 7, 28, 23), self, @selector(cycleRepeat:));
    [repeatButton setToolTip:_NS("Repeat")];
    shuffleButton = VLCLegacyImageButton(bar,
        themedImage(@"shuffle", @"shuffle_dark"),
        themedImage(@"shuffle-pressed", @"shuffle-pressed_dark"),
        NSMakeRect(201, 7, 29, 23), self, @selector(shuffle:));
    [shuffleButton setToolTip:_NS("Shuffle")];

    /* like 3.0: no elapsed field on the left, the seek bar follows the
     * buttons directly */
    seekSlider = [[[VLCLegacySeekSlider alloc]
        initWithFrame:NSMakeRect(186, 8, W - 186 - 196, 21)] autorelease];
    /* no static tooltip: the slider shows a live time/chapter/preview
     * tooltip on hover, a "Position" one would fight with it */
    [(VLCLegacySeekSlider *)seekSlider setHoverDelegate:self];
    VLCLegacyProgressSliderCell *seekCell =
        [[[VLCLegacyProgressSliderCell alloc] init] autorelease];
    [seekSlider setCell:seekCell];
    [seekSlider setMinValue:0.0];
    [seekSlider setMaxValue:1.0];
    [seekSlider setFloatValue:0.f];
    [seekSlider setContinuous:NO];
    [seekSlider setTarget:self];
    [seekSlider setAction:@selector(seeked:)];
    [seekSlider setAutoresizingMask:NSViewWidthSizable];
    [bar addSubview:seekSlider];

    VLCLegacyTimeField *clickableTime = [[[VLCLegacyTimeField alloc]
        initWithFrame:NSMakeRect(W - 192, 10, 56, 15)] autorelease];
    clickableTime->controller = self;
    durationField = clickableTime;
    [durationField setEditable:NO];
    [durationField setSelectable:NO];
    [durationField setBordered:NO];
    [durationField setDrawsBackground:NO];
    [durationField setAlignment:NSRightTextAlignment];
    [[durationField cell] setFont:[NSFont systemFontOfSize:10.5]];
    [durationField setTextColor:VLCLegacyTextColor()];
    [durationField setStringValue:@"00:00"];
    [durationField setAutoresizingMask:NSViewMinXMargin];
    [bar addSubview:durationField];

    muteButton = VLCLegacyImageButton(bar,
        themedImage(@"volume-low", @"volume-low_dark"),
        nil, NSMakeRect(W - 130, 12, 5, 11), self, @selector(mute:));
    [muteButton setToolTip:_NS("Mute")];
    [muteButton setAutoresizingMask:NSViewMinXMargin];

    /* drawn like VLCVolumeSliderCell: thin line with the 100% tick,
     * range up to 125% like the 3.0 window */
    volumeSlider = [[[NSSlider alloc]
        initWithFrame:NSMakeRect(W - 118, 9, 60, 17)] autorelease];
    [volumeSlider setToolTip:
        [NSString stringWithFormat:_NS("Volume: %i %%"), 100]];
    VLCLegacyProgressSliderCell *volumeCell =
        [[[VLCLegacyProgressSliderCell alloc] init] autorelease];
    [volumeCell setKnobInset:1.0f];
    [volumeCell setVolumeStyle:YES];
    [volumeSlider setCell:volumeCell];
    [volumeSlider setMinValue:0.0];
    [volumeSlider setMaxValue:1.25];
    [volumeSlider setFloatValue:[core volume]];
    [volumeSlider setContinuous:YES];
    [volumeSlider setTarget:self];
    [volumeSlider setAction:@selector(volumeChanged:)];
    [volumeSlider setAutoresizingMask:NSViewMinXMargin];
    [bar addSubview:volumeSlider];

    volumeMaxButton = VLCLegacyImageButton(bar,
        themedImage(@"volume-high", @"volume-high_dark"),
        nil, NSMakeRect(W - 52, 12, 13, 11),
        self, @selector(volumeMax:));
    [volumeMaxButton setToolTip:_NS("Full Volume")];
    [volumeMaxButton setAutoresizingMask:NSViewMinXMargin];

    /* optional audio effects button (View > Show Audio Effects Button),
     * left of fullscreen like 3.0 */
    effectsButton = VLCLegacyImageButton(bar,
        themedImage(@"effects-one-button", @"effects-one-button_dark"),
        themedImage(@"effects-one-button-pressed",
                    @"effects-one-button-pressed-dark"),
        NSMakeRect(W - 63, 7, 29, 23), self, @selector(effects:));
    [effectsButton setToolTip:_NS("Audio Effects")];
    [effectsButton setAutoresizingMask:NSViewMinXMargin];

    fullscreenButton = VLCLegacyImageButton(bar,
        themedImage(@"fullscreen-one-button", @"fullscreen-one-button_dark"),
        themedImage(@"fullscreen-one-button-pressed",
                    @"fullscreen-one-button-pressed_dark"),
        NSMakeRect(W - 34, 7, 29, 23), self, @selector(fullscreen:));
    [fullscreenButton setToolTip:_NS("Fullscreen")];
    [fullscreenButton setAutoresizingMask:NSViewMinXMargin];

    /* place everything according to the View menu toggles */
    [self layoutControlsBar];

    /* --- split view: sidebar | playlist area --- */
    NSRect upperRect = NSMakeRect(0, BOTTOM_BAR_HEIGHT, W,
                                  contentRect.size.height - BOTTOM_BAR_HEIGHT);
    splitView = [[[VLCLegacySplitView alloc] initWithFrame:upperRect]
        autorelease];
    [splitView setVertical:YES];
    [splitView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    /* sidebar (VLC 3.0 source list look) inside a retained pane so
     * View > Show Sidebar can detach and re-attach it; the bottom of
     * the pane shows the cover art of the playing item (Qt parity).
     * A draggable divider lets the user resize the art panel; its
     * height is restored from the previous session. */
    {
        NSNumber *saved = [[NSUserDefaults standardUserDefaults]
            objectForKey:VLCLegacyArtHeightKey];
        artPanelHeight = saved ? [saved doubleValue] : 120.0;
    }
    sidebarPane = [[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, SIDEBAR_WIDTH,
                                 upperRect.size.height)];
    sidebarScroll = [[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 0, SIDEBAR_WIDTH, 10)];
    /* vertical placement is driven by -layoutSidebarArtStack, not the
     * autoresizing machinery, so keep only the width follow-through */
    [sidebarScroll setAutoresizingMask:NSViewWidthSizable];
    sidebarArtView = [[[VLCLegacyArtImageView alloc]
        initWithFrame:NSMakeRect(0, 0, SIDEBAR_WIDTH, 10)] autorelease];
    [sidebarArtView setAutoresizingMask:NSViewWidthSizable];
    [sidebarArtView setImage:VLCLegacyImage(@"noart")];
    sidebarArtDivider = [[[VLCLegacyArtDivider alloc]
        initWithFrame:NSMakeRect(0, 0, SIDEBAR_WIDTH,
                                 VLC_ART_DIVIDER_THICKNESS)] autorelease];
    [sidebarArtDivider setAutoresizingMask:NSViewWidthSizable];
    [(VLCLegacyArtDivider *)sidebarArtDivider setDragDelegate:(id)self];
    [sidebarPane addSubview:sidebarScroll];
    [sidebarPane addSubview:sidebarArtView];
    [sidebarPane addSubview:sidebarArtDivider];
    [sidebarScroll setHasVerticalScroller:YES];
    if ([sidebarScroll respondsToSelector:@selector(setAutohidesScrollers:)])
        [sidebarScroll setAutohidesScrollers:YES];
    [sidebarScroll setBorderType:NSNoBorder];
    /* relayout the art stack whenever the pane changes height (window
     * resize, Show Sidebar re-attach) */
    [sidebarPane setPostsFrameChangedNotifications:YES];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(sidebarPaneFrameChanged:)
               name:NSViewFrameDidChangeNotification
             object:sidebarPane];
    [self layoutSidebarArtStack];

    sidebarTable = [[[NSTableView alloc]
        initWithFrame:[[sidebarScroll contentView] bounds]] autorelease];
    [sidebarTable setHeaderView:nil];
    [sidebarTable setBackgroundColor:VLCLegacySidebarBackgroundColor()];
    [sidebarTable setRowHeight:20];
    NSTableColumn *sidebarColumn =
        [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [sidebarColumn setWidth:SIDEBAR_WIDTH - 16];
    /* the column follows the pane width, or the count badge pinned to
     * the right edge of the cell gets clipped by the scroll view */
    if ([sidebarColumn respondsToSelector:@selector(setResizingMask:)])
        [sidebarColumn setResizingMask:NSTableColumnAutoresizingMask];
    if ([sidebarTable respondsToSelector:@selector(setColumnAutoresizingStyle:)])
        [sidebarTable setColumnAutoresizingStyle:
            NSTableViewLastColumnOnlyAutoresizingStyle];
    [sidebarColumn setEditable:NO];
    VLCLegacySidebarCell *sidebarCell =
        [[[VLCLegacySidebarCell alloc] initTextCell:@""] autorelease];
    /* single line: long service names must truncate, not wrap out of
     * the 20 px row */
    [sidebarCell setWraps:NO];
    VLCLegacySetCellLineBreakMode(sidebarCell, NSLineBreakByTruncatingTail);
    [sidebarColumn setDataCell:sidebarCell];
    [sidebarTable addTableColumn:sidebarColumn];
    [sidebarTable setDataSource:(id)self];
    [sidebarTable setDelegate:(id)self];
    [sidebarTable registerForDraggedTypes:
        [NSArray arrayWithObjects:NSFilenamesPboardType,
            VLCLegacyPlaylistItemPboardType, nil]];
    [sidebarScroll setDocumentView:sidebarTable];
    [sidebarTable sizeLastColumnToFit];
    [self buildSidebarModel];

    /* right side: playlist table + dropzone */
    rightContainer = [[[VLCLegacySolidView alloc]
        initWithFrame:NSMakeRect(0, 0, W - SIDEBAR_WIDTH,
                                 upperRect.size.height)] autorelease];
    ((VLCLegacyDropView *)rightContainer)->controller = self;
    [rightContainer registerForDraggedTypes:
        [NSArray arrayWithObject:NSFilenamesPboardType]];

    NSRect rightBounds = [rightContainer bounds];
    const float topStripHeight = 28;

    /* top strip: current view title (left) + search field (right), like
     * the 3.0 main window header */
    VLCLegacyBottomBarView *topStrip = [[[VLCLegacyBottomBarView alloc]
        initWithFrame:NSMakeRect(0, rightBounds.size.height - topStripHeight,
                                 rightBounds.size.width, topStripHeight)]
        autorelease];
    [topStrip setAutoresizingMask:NSViewWidthSizable | NSViewMinYMargin];
    [rightContainer addSubview:topStrip];

    viewTitleLabel = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(10, 6, 260, 17)] autorelease];
    [viewTitleLabel setEditable:NO];
    [viewTitleLabel setBordered:NO];
    [viewTitleLabel setDrawsBackground:NO];
    [[viewTitleLabel cell] setFont:[NSFont boldSystemFontOfSize:12]];
    [viewTitleLabel setTextColor:VLCLegacyTextColor()];
    [viewTitleLabel setStringValue:_NS("Playlist")];
    [topStrip addSubview:viewTitleLabel];

    searchField = VLCLegacyMakeSearchField(
        NSMakeRect(rightBounds.size.width - 166, 3, 156, 22),
        self, @selector(searchChanged:));
    [searchField setAutoresizingMask:NSViewMinXMargin];
    [topStrip addSubview:searchField];

    NSRect tableRect = NSMakeRect(0, 0, rightBounds.size.width,
                                  rightBounds.size.height - topStripHeight);
    playlistScroll = [[[NSScrollView alloc] initWithFrame:tableRect]
        autorelease];
    [playlistScroll setHasVerticalScroller:YES];
    if ([playlistScroll respondsToSelector:@selector(setAutohidesScrollers:)])
        [playlistScroll setAutohidesScrollers:YES];
    [playlistScroll setBorderType:NSNoBorder];
    [playlistScroll setAutoresizingMask:NSViewWidthSizable
                                       | NSViewHeightSizable];

    /* an outline view: the media library, podcasts... are trees in the
     * core playlist and 3.0 presents them hierarchically */
    playlistTable = [[[VLCLegacyStripedOutlineView alloc]
        initWithFrame:[[playlistScroll contentView] bounds]] autorelease];
    if ([playlistTable respondsToSelector:@selector(setUsesAlternatingRowBackgroundColors:)])
        [playlistTable setUsesAlternatingRowBackgroundColors:!VLCLegacyDarkMode()];
    /* Only the last column follows the width of the table. Without this the
     * Duration column keeps for ever the sliver it was given while the
     * table was still narrower than its columns. */
    VLCLegacyResizeLastColumnOnly(playlistTable);
    if (VLCLegacyDarkMode())
        [playlistTable setBackgroundColor:VLCLegacyTableBackgroundColor()];
    [playlistTable setRowHeight:20];
    [playlistTable setIndentationPerLevel:13.0];
    [playlistTable setAutoresizesOutlineColumn:NO];

    NSTableColumn *artColumn =
        [[[NSTableColumn alloc] initWithIdentifier:@"art"] autorelease];
    if (VLCLegacyDarkMode())
        [artColumn setHeaderCell:
            [[[VLCLegacyDarkHeaderCell alloc] initTextCell:@""] autorelease]];
    /* AppKit's default header cell reads "Field" */
    [[artColumn headerCell] setStringValue:@""];
    /* 3.0 keeps a narrow empty status column here, no artwork */
    [artColumn setWidth:18];
    [artColumn setEditable:NO];
    [playlistTable addTableColumn:artColumn];

    /* the text columns come from the View > Playlist Table Columns set */
    [self rebuildPlaylistColumns];

    [playlistTable setDataSource:(id)self];
    [playlistTable setDelegate:(id)self];
    [playlistTable setTarget:self];
    [playlistTable setDoubleAction:@selector(playSelectedItem:)];
    /* contextual menu: items, order and separators of PlaylistMenu.xib */
    NSMenu *contextMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSMenuItem *menuItem;
    menuItem = [contextMenu addItemWithTitle:_NS("Play")
                                      action:@selector(playSelectedItem:)
                               keyEquivalent:@""];
    [menuItem setTarget:self];
    menuItem = [contextMenu addItemWithTitle:_NS("Delete")
                                      action:@selector(deleteSelectedItems:)
                               keyEquivalent:@""];
    [menuItem setTarget:self];
    [contextMenu addItem:[NSMenuItem separatorItem]];
    menuItem = [contextMenu addItemWithTitle:_NS("Select All")
                                      action:@selector(selectAllItems:)
                               keyEquivalent:@""];
    [menuItem setTarget:self];
    [contextMenu addItem:[NSMenuItem separatorItem]];
    /* the legacy playlist is flat: both stay visible but disabled, so
     * the menu matches the 3.0 layout */
    menuItem = [contextMenu addItemWithTitle:_NS("Expand All")
                                      action:@selector(recursiveExpandOrCollapseNode:)
                               keyEquivalent:@""];
    [menuItem setTarget:self];
    menuItem = [contextMenu addItemWithTitle:_NS("Collapse All")
                                      action:@selector(recursiveExpandOrCollapseNode:)
                               keyEquivalent:@""];
    [menuItem setTarget:self];
    menuItem = [contextMenu addItemWithTitle:_NS("Media Information...")
                                      action:@selector(showItemInfo:)
                               keyEquivalent:@""];
    [menuItem setTarget:self];
    menuItem = [contextMenu addItemWithTitle:_NS("Reveal in Finder")
                                      action:@selector(revealItemInFinder:)
                               keyEquivalent:@""];
    [menuItem setTarget:self];
    [contextMenu addItem:[NSMenuItem separatorItem]];
    menuItem = [contextMenu addItemWithTitle:_NS("Shuffle playlist")
                                      action:@selector(shufflePlaylist:)
                               keyEquivalent:@""];
    [menuItem setTarget:self];
    menuItem = [contextMenu addItemWithTitle:_NS("Add File...")
                                      action:@selector(addFilesToPlaylist:)
                               keyEquivalent:@""];
    [menuItem setTarget:self];
    [playlistTable setMenu:contextMenu];
    [playlistTable setAllowsMultipleSelection:YES];
    [playlistTable registerForDraggedTypes:
        [NSArray arrayWithObjects:NSFilenamesPboardType,
            VLCLegacyPlaylistItemPboardType, nil]];
    /* allow the rows to be a drag source: move/copy inside the app, and
     * copy out to the Finder / other apps (10.4 defaults forbid leaving) */
    /* 10.3; below it, dragging rows out of the playlist is simply not
     * offered -- dropping media INTO it is a separate mechanism and keeps
     * working */
    if ([playlistTable respondsToSelector:
            @selector(setDraggingSourceOperationMask:forLocal:)]) {
        [playlistTable setDraggingSourceOperationMask:
            NSDragOperationCopy | NSDragOperationMove forLocal:YES];
        [playlistTable setDraggingSourceOperationMask:
            NSDragOperationCopy forLocal:NO];
    }
    [playlistScroll setDocumentView:playlistTable];
    [rightContainer addSubview:playlistScroll];

    /* Podcast strip: sits at the bottom of the playlist area, right above
     * the controls bar, and is revealed only while the Podcasts service is
     * the selected sidebar entry (same place as the 3.0 podcastView). */
    podcastBar = [[[VLCLegacyBottomBarView alloc]
        initWithFrame:NSMakeRect(0, 0, rightBounds.size.width,
                                 PODCAST_BAR_HEIGHT)] autorelease];
    [podcastBar setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    {
        NSButton *button = [[[NSButton alloc]
            initWithFrame:NSMakeRect(10, 3, 130, 26)] autorelease];
        [button setTitle:_NS("Subscribe")];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTarget:self];
        [button setAction:@selector(subscribePodcast:)];
        [podcastBar addSubview:button];

        button = [[[NSButton alloc]
            initWithFrame:NSMakeRect(146, 3, 130, 26)] autorelease];
        [button setTitle:_NS("Unsubscribe")];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setTarget:self];
        [button setAction:@selector(unsubscribePodcast:)];
        [podcastBar addSubview:button];
        podcastRemoveButton = button;
    }
    VLCLegacySetViewHidden(podcastBar, YES);
    podcastBarVisible = NO;
    [rightContainer addSubview:podcastBar];

    /* dropzone, shown while the playlist is empty (3.0 style) */
    dropzoneView = [[[VLCLegacyDropView alloc]
        initWithFrame:NSMakeRect((tableRect.size.width - 240) / 2,
                                 (tableRect.size.height - 220) / 2,
                                 240, 220)] autorelease];
    ((VLCLegacyDropView *)dropzoneView)->controller = self;
    [dropzoneView registerForDraggedTypes:
        [NSArray arrayWithObject:NSFilenamesPboardType]];
    [dropzoneView setAutoresizingMask:NSViewMinXMargin | NSViewMaxXMargin
                                     | NSViewMinYMargin | NSViewMaxYMargin];

    NSImageView *dropImage = [[[NSImageView alloc]
        initWithFrame:NSMakeRect(64, 96, 112, 112)] autorelease];
    [dropImage setImage:VLCLegacyImage(VLCLegacyDarkMode()
        ? @"mj-dropzone-dark" : @"dropzone")];
    [dropImage setEditable:NO];
    /* NSImageView registers itself as a drag destination and would
     * swallow drops over the icon; the surrounding dropzone must get
     * them (VLCDropDisabledImageView does the same) */
    /* -unregisterDraggedTypes is 10.3; below it, a view that never
     * registered a type has nothing to unregister anyway */
    if ([dropImage respondsToSelector:@selector(unregisterDraggedTypes)])
        [dropImage unregisterDraggedTypes];
    [dropzoneView addSubview:dropImage];

    NSTextField *dropLabel = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(0, 62, 240, 22)] autorelease];
    [dropLabel setEditable:NO];
    [dropLabel setBordered:NO];
    [dropLabel setDrawsBackground:NO];
    [dropLabel setAlignment:NSCenterTextAlignment];
    [[dropLabel cell] setFont:[NSFont boldSystemFontOfSize:14]];
    [dropLabel setTextColor:VLCLegacySecondaryTextColor()];
    [dropLabel setStringValue:_NS("Drop media here")];
    [dropzoneView addSubview:dropLabel];

    NSButton *dropButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(30, 20, 180, 28)] autorelease];
    [dropButton setTitle:_NS("Open media...")];
    [dropButton setBezelStyle:NSRoundedBezelStyle];
    [dropButton setTarget:self];
    [dropButton setAction:@selector(openFiles:)];
    [dropzoneView addSubview:dropButton];
    [rightContainer addSubview:dropzoneView];

    [splitView addSubview:sidebarPane];
    [splitView addSubview:rightContainer];
    [splitView setDelegate:(id)self];
    [content addSubview:splitView];
    /* initial divider position */
    [splitView adjustSubviews];
    [sidebarPane setFrameSize:
        NSMakeSize(SIDEBAR_WIDTH, upperRect.size.height)];
    [splitView adjustSubviews];

    /* --- embedded video view, hidden until a vout asks for it --- */
    videoView = [[[VLCLegacyVideoView alloc] initWithFrame:upperRect]
        autorelease];
    videoView->core = core;
    /* On modern macOS (Rosetta test machines), the old-style NSOpenGL
     * surface of the vout view is composited over the WHOLE window and
     * blacks out the controls bar; layer-backing the video view makes
     * AppKit clip it properly. Never applied on the old targets (the
     * selector only exists from 10.5 and layer-backed GL is risky on
     * their GPUs), where the surface path behaves. */
    VLCLegacyEnableLayerBackingIfModern(videoView);
    [videoView registerForDraggedTypes:
        [NSArray arrayWithObject:NSFilenamesPboardType]];
    [videoView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview:videoView];
    VLCLegacySetViewHidden(videoView, YES);
    /* Keep the controls bar the TOPMOST sibling: on modern macOS the
     * vout's GL surface bleeds one bar-height below the video view
     * whatever the layer frames say; with the bar stacked above it the
     * bleed stays behind the (opaque) bar. Harmless on the old targets. */
    [bar retain];
    [bar removeFromSuperview];
    [content addSubview:bar];
    [bar release];

    /* Periodic refresh; scheduled in the default run loop mode so it pauses
     * while a slider is being tracked (event-tracking mode) and thus never
     * fights the user's drag.
     * ⚠ Cadence réduite sous Mac OS X 10.3 et avant : chaque tic qui déplace le
     * slider salit la barre entière, et le redessin (fond + champs de temps)
     * y coûte ~140 ms — le rendu de glyphes passe par un RPC au serveur de
     * polices À CHAQUE passage (mesuré au PC-sampling sur l'iBook G3 : 43 %
     * du temps mur du thread principal à 0,3 s d'intervalle, pendant que le
     * décodage DVD se bat pour le même cœur). À 1 s le coût tombe au tiers ;
     * 10.4+ garde la fluidité du slider de VLC 3.0. */
    updateTimer = [NSTimer scheduledTimerWithTimeInterval:
                       (VLCLegacyOSVersionAtLeast(10, 4, 0) ? 0.3 : 1.0)
                                                   target:self
                                                 selector:@selector(refresh:)
                                                 userInfo:nil
                                                  repeats:YES];

    playlist_t *p_playlist = pl_Get(p_intf);
    unsigned i;
    for (i = 0; i < sizeof(changeVariables) / sizeof(changeVariables[0]);
         i++)
        var_AddCallback(p_playlist, changeVariables[i],
                        PlaylistChangedCallback, NULL);

    [window center];
    [window makeKeyAndOrderFront:nil];

    /* The playlist columns were sized against the width the table had before
     * the split view laid it out, which left the last one (Duration) a few
     * pixels wide. From 10.4 the next resize of the table hands the slack
     * back to it; on 10.2 nothing resizes it again, so fit it once here, now
     * that the window is up and the widths are the real ones. */
    [playlistTable sizeLastColumnToFit];
}

- (void)mute:(id)sender      { [core toggleMute]; }
/* "Full Volume" caps at 125%, like the 3.0 slider range */
- (void)volumeMax:(id)sender { [core setVolume:1.25f];
                               [volumeSlider setFloatValue:1.25f]; }

/*****************************************************************************
 * configurable controls bar (View menu, VLC 3.0 parity)
 *****************************************************************************/

- (void)layoutControlsBar
{
    BOOL showJump = var_InheritBool(p_intf,
        "legacy-macosx-show-playback-buttons") ? YES : NO;
    BOOL showPlaymode = var_InheritBool(p_intf,
        "legacy-macosx-show-playmode-buttons") ? YES : NO;
    BOOL showEffects = var_InheritBool(p_intf,
        "legacy-macosx-show-effects-button") ? YES : NO;
    NSView *bar = [playButton superview];
    float W = [bar frame].size.width;

    /* Left cluster, 3.0 semantics: the base is ALWAYS the combined
     * backward/play/forward trio; the jump toggle ADDS previous/next
     * around it (5 buttons) and turns backward/forward into plain seek
     * buttons (6-buttons artwork). */
    float x = 12;
    VLCLegacySetViewHidden(previousButton, !showJump);
    VLCLegacySetViewHidden(nextButton, !showJump);
    if (showJump) {
        [previousButton setFrame:NSMakeRect(x, 7, 29, 23)];
        x += 29;
        [backwardButton setFrame:NSMakeRect(x, 7, 28, 23)];
        x += 28;
        [playButton setFrame:NSMakeRect(x, 7, 27, 23)];
        x += 27;
        [forwardButton setFrame:NSMakeRect(x, 7, 28, 23)];
        x += 28;
        [nextButton setFrame:NSMakeRect(x, 7, 29, 23)];
        x += 29;
        [backwardButton setImage:VLCLegacyImageSized(
            themedImage(@"backward-6btns", @"backward-6btns-dark"),
            NSMakeSize(28, 23))];
        [backwardButton setAlternateImage:VLCLegacyImageSized(
            themedImage(@"backward-6btns-pressed",
                        @"backward-6btns-dark-pressed"),
            NSMakeSize(28, 23))];
        [forwardButton setImage:VLCLegacyImageSized(
            themedImage(@"forward-6btns", @"forward-6btns-dark"),
            NSMakeSize(28, 23))];
        [forwardButton setAlternateImage:VLCLegacyImageSized(
            themedImage(@"forward-6btns-pressed",
                        @"forward-6btns-dark-pressed"),
            NSMakeSize(28, 23))];
    } else {
        [backwardButton setFrame:NSMakeRect(x, 7, 29, 23)];
        x += 29;
        [playButton setFrame:NSMakeRect(x, 7, 27, 23)];
        x += 27;
        [forwardButton setFrame:NSMakeRect(x, 7, 29, 23)];
        x += 29;
        [backwardButton setImage:VLCLegacyImageSized(
            themedImage(@"backward-3btns", @"backward-3btns-dark"),
            NSMakeSize(29, 23))];
        [backwardButton setAlternateImage:VLCLegacyImageSized(
            themedImage(@"backward-3btns-pressed",
                        @"backward-3btns-dark-pressed"),
            NSMakeSize(29, 23))];
        [forwardButton setImage:VLCLegacyImageSized(
            themedImage(@"forward-3btns", @"forward-3btns-dark"),
            NSMakeSize(29, 23))];
        [forwardButton setAlternateImage:VLCLegacyImageSized(
            themedImage(@"forward-3btns-pressed",
                        @"forward-3btns-dark-pressed"),
            NSMakeSize(29, 23))];
    }
    x += 8;
    [stopButton setFrame:NSMakeRect(x, 7, 29, 23)];
    x += 29 + 10;
    [viewToggleButton setFrame:NSMakeRect(x, 7, 29, 23)];
    x += 29;
    /* segment artwork when the repeat/shuffle cluster is flush after
     * the playlist toggle, standalone artwork otherwise (3.0 does the
     * same asset swap; 3.0 order: playlist, repeat, shuffle) */
    [viewToggleButton setImage:VLCLegacyImageSized(
        showPlaymode ? themedImage(@"playlist-btn", @"playlist_dark")
                     : themedImage(@"playlist-1btn", @"playlist-1btn-dark"),
        NSMakeSize(29, 23))];
    [viewToggleButton setAlternateImage:VLCLegacyImageSized(
        showPlaymode
            ? themedImage(@"playlist-btn-pressed", @"playlist-pressed_dark")
            : themedImage(@"playlist-1btn-pressed",
                          @"playlist-1btn-dark-pressed"),
        NSMakeSize(29, 23))];
    VLCLegacySetViewHidden(shuffleButton, !showPlaymode);
    VLCLegacySetViewHidden(repeatButton, !showPlaymode);
    if (showPlaymode) {
        [repeatButton setFrame:NSMakeRect(x, 7, 28, 23)];
        x += 28;
        [shuffleButton setFrame:NSMakeRect(x, 7, 29, 23)];
        x += 29;
    }

    /* right cluster; everything shifts left when the effects button is
     * shown, and the fullscreen artwork becomes the paired segment */
    float off = showEffects ? 29 : 0;
    [fullscreenButton setFrame:NSMakeRect(W - 34, 7, 29, 23)];
    [fullscreenButton setImage:VLCLegacyImageSized(
        showEffects
            ? themedImage(@"fullscreen-double-buttons",
                          @"fullscreen-double-buttons_dark")
            : themedImage(@"fullscreen-one-button",
                          @"fullscreen-one-button_dark"),
        NSMakeSize(29, 23))];
    [fullscreenButton setAlternateImage:VLCLegacyImageSized(
        showEffects
            ? themedImage(@"fullscreen-double-buttons-pressed",
                          @"fullscreen-double-buttons-pressed_dark")
            : themedImage(@"fullscreen-one-button-pressed",
                          @"fullscreen-one-button-pressed_dark"),
        NSMakeSize(29, 23))];
    VLCLegacySetViewHidden(effectsButton, !showEffects);
    if (showEffects) {
        [effectsButton setFrame:NSMakeRect(W - 63, 7, 29, 23)];
        [effectsButton setImage:VLCLegacyImageSized(
            themedImage(@"effects-double-buttons",
                        @"effects-double-buttons_dark"),
            NSMakeSize(29, 23))];
        [effectsButton setAlternateImage:VLCLegacyImageSized(
            themedImage(@"effects-double-buttons-pressed",
                        @"effects-double-buttons-pressed_dark"),
            NSMakeSize(29, 23))];
    }
    [volumeMaxButton setFrame:NSMakeRect(W - 52 - off, 12, 13, 11)];
    [volumeSlider setFrame:NSMakeRect(W - 118 - off, 9, 60, 17)];
    [muteButton setFrame:NSMakeRect(W - 130 - off, 12, 5, 11)];
    [durationField setFrame:NSMakeRect(W - 192 - off, 10, 56, 15)];

    float seekX = x + 13;
    [seekSlider setFrame:NSMakeRect(seekX, 8, W - 196 - off - seekX, 21)];
    [bar setNeedsDisplay:YES];
}

- (void)toggleBarOption:(const char *)name
{
    config_PutInt(p_intf, name, !var_InheritBool(p_intf, name));
    [self layoutControlsBar];
}

- (void)toggleJumpButtons
{
    [self toggleBarOption:"legacy-macosx-show-playback-buttons"];
}

- (void)togglePlaymodeButtons
{
    [self toggleBarOption:"legacy-macosx-show-playmode-buttons"];
}

- (void)toggleEffectsButton
{
    [self toggleBarOption:"legacy-macosx-show-effects-button"];
}

- (void)shuffle:(id)sender
{
    [core togglePlaylistBool:"random"];
}

/* off -> repeat all -> repeat one -> off, like the 3.0 repeat button */
- (void)cycleRepeat:(id)sender
{
    playlist_t *p_playlist = pl_Get(p_intf);
    bool loop = var_GetBool(p_playlist, "loop");
    bool repeat = var_GetBool(p_playlist, "repeat");
    if (!loop && !repeat) {
        var_SetBool(p_playlist, "loop", true);
        var_SetBool(p_playlist, "repeat", false);
    } else if (loop) {
        var_SetBool(p_playlist, "loop", false);
        var_SetBool(p_playlist, "repeat", true);
    } else {
        var_SetBool(p_playlist, "loop", false);
        var_SetBool(p_playlist, "repeat", false);
    }
}

- (void)effects:(id)sender
{
    id delegate = [NSApp delegate];
    if ([delegate respondsToSelector:@selector(audioEffectsController)])
        [[delegate performSelector:@selector(audioEffectsController)]
            performSelector:@selector(showWindow)];
}

/*****************************************************************************
 * sidebar visibility (View > Show Sidebar)
 *****************************************************************************/

/* Position the sidebar list, the divider and the cover art inside the
 * pane. The art keeps its user-set height (clamped to the available
 * space); the list takes whatever is left above it. */
- (void)layoutSidebarArtStack
{
    if (!sidebarPane || !sidebarScroll || !sidebarArtView)
        return;
    CGFloat W = [sidebarPane bounds].size.width;
    CGFloat H = [sidebarPane bounds].size.height;
    CGFloat div = VLC_ART_DIVIDER_THICKNESS;

    CGFloat h = artPanelHeight;
    CGFloat maxH = H - VLC_ART_MIN_LIST_HEIGHT - div;
    if (h > maxH) h = maxH;
    if (h < VLC_ART_MIN_HEIGHT) h = VLC_ART_MIN_HEIGHT;
    /* degenerate: pane too short to honour the minimums */
    if (h + div > H) h = (H > div) ? H - div : 0;

    [sidebarArtView setFrame:NSMakeRect(0, 0, W, h)];
    [sidebarArtDivider setFrame:NSMakeRect(0, h, W, div)];
    [sidebarScroll setFrame:NSMakeRect(0, h + div, W,
                                       (H > h + div) ? H - h - div : 0)];
}

- (void)sidebarPaneFrameChanged:(NSNotification *)notification
{
    [self layoutSidebarArtStack];
}

/* VLCLegacyArtDividerDelegate: the user dragged the handle. Convert the
 * pane-space y into an art height, clamp it, relayout and persist. */
- (void)artDividerDraggedToPaneY:(CGFloat)y
{
    CGFloat H = [sidebarPane bounds].size.height;
    CGFloat div = VLC_ART_DIVIDER_THICKNESS;
    CGFloat h = y - div / 2.0;
    CGFloat maxH = H - VLC_ART_MIN_LIST_HEIGHT - div;
    if (h > maxH) h = maxH;
    if (h < VLC_ART_MIN_HEIGHT) h = VLC_ART_MIN_HEIGHT;
    artPanelHeight = h;
    [self layoutSidebarArtStack];
    [[NSUserDefaults standardUserDefaults]
        setObject:[NSNumber numberWithDouble:artPanelHeight]
           forKey:VLCLegacyArtHeightKey];
}

- (BOOL)sidebarVisible
{
    return [sidebarPane superview] != nil;
}

- (void)toggleSidebar
{
    if ([self sidebarVisible]) {
        [sidebarPane removeFromSuperview];
        [splitView adjustSubviews];
    } else {
        [splitView addSubview:sidebarPane
                   positioned:NSWindowBelow
                   relativeTo:rightContainer];
        [sidebarPane setFrameSize:
            NSMakeSize(SIDEBAR_WIDTH, [splitView frame].size.height)];
        [splitView adjustSubviews];
    }
}

- (void)showPlaylistView
{
    [window makeKeyAndOrderFront:nil];
    if (videoActive && !VLCLegacyViewIsHidden(videoView)) {
        playlistViewWanted = YES;
        VLCLegacySetViewHidden(videoView, YES);
        VLCLegacySetViewHidden(splitView, NO);
        [self detachVideoHostWindow];   /* cf. -toggleView: */
    }
}

/* -[VLCMainWindow highlightSearchField:] simply selects the text; here the
 * field lives in the playlist strip, which the video view covers while a
 * movie plays, so bring that view back first -- a Find that leaves the
 * caret in a hidden field would do nothing at all. */
- (void)highlightSearchField
{
    [self showPlaylistView];
    [searchField selectText:nil];
}

/*****************************************************************************
 * playlist table columns (View > Playlist Table Columns)
 *****************************************************************************/

/* identifier, header msgid and width of every available column, in the
 * 3.0 menu order; the identifier doubles as the snapshot dictionary key */
static const struct {
    const char *identifier;
    const char *title;
    float width;
} column_defs[11] = {
    { "tracknumber", N_("Track Number"), 44 },
    { "title",       N_("Title"),        300 },
    { "author",      N_("Author"),       120 },
    { "duration",    N_("Duration"),     60 },
    { "genre",       N_("Genre"),        80 },
    { "album",       N_("Album"),        120 },
    { "description", N_("Description"),  150 },
    { "date",        N_("Date"),         60 },
    { "language",    N_("Language"),     70 },
    { "uri",         N_("URI"),          200 },
    { "filesize",    N_("File Size"),    70 },
};

- (void)rebuildPlaylistColumns
{
    /* AppKit silently refuses to remove the current outline column:
     * park the disclosure triangles on the artwork column (never
     * removed) while rebuilding, else the old title column survives as
     * a duplicate */
    NSTableColumn *artColumn = [playlistTable tableColumnWithIdentifier:@"art"];
    if (artColumn)
        [playlistTable setOutlineTableColumn:artColumn];

    /* drop every text column, keep the artwork one */
    NSArray *columns = [[[playlistTable tableColumns] copy] autorelease];
    unsigned i;
    for (i = 0; i < [columns count]; i++) {
        NSTableColumn *column = [columns objectAtIndex:i];
        if (![[column identifier] isEqualToString:@"art"])
            [playlistTable removeTableColumn:column];
    }

    msg_Dbg(p_intf, "playlist table columns: %s",
            [[visibleColumns componentsJoinedByString:@","] UTF8String]);
    int d;
    for (d = 0; d < 11; d++) {
        NSString *identifier =
            [NSString stringWithUTF8String:column_defs[d].identifier];
        if (![visibleColumns containsObject:identifier])
            continue;
        NSTableColumn *column = [[[NSTableColumn alloc]
            initWithIdentifier:identifier] autorelease];
        if (VLCLegacyDarkMode())
            [column setHeaderCell:[[[VLCLegacyDarkHeaderCell alloc]
                initTextCell:@""] autorelease]];
        [[column headerCell] setStringValue:_NS(column_defs[d].title)];
        [column setWidth:column_defs[d].width];
        [column setEditable:NO];
        [playlistTable addTableColumn:column];
        /* the disclosure triangles live in the title column, like the
         * 3.0 outline (title cannot be toggled off) */
        if ([identifier isEqualToString:@"title"])
            [playlistTable setOutlineTableColumn:column];
    }
    [playlistTable sizeLastColumnToFit];
    [playlistTable reloadData];
    [self restoreExpandedItems];
}

- (BOOL)playlistColumnShown:(NSString *)identifier
{
    return [visibleColumns containsObject:identifier];
}

- (void)togglePlaylistColumn:(NSString *)identifier
{
    if ([visibleColumns containsObject:identifier])
        [visibleColumns removeObject:identifier];
    else {
        /* keep the canonical order regardless of toggle order */
        [visibleColumns addObject:identifier];
        NSMutableArray *ordered = [NSMutableArray array];
        int d;
        for (d = 0; d < 11; d++) {
            NSString *known = [NSString stringWithUTF8String:
                column_defs[d].identifier];
            if ([visibleColumns containsObject:known])
                [ordered addObject:known];
        }
        [visibleColumns setArray:ordered];
    }
    [[NSUserDefaults standardUserDefaults]
        setObject:visibleColumns forKey:@"VLCLegacyPlaylistColumns"];
    [self rebuildPlaylistColumns];
    /* the snapshot may lack the fields of a freshly added column */
    [self rebuildItemsSnapshot];
}

/*****************************************************************************
 * contextual menu extras (PlaylistMenu.xib behaviors)
 *****************************************************************************/

- (void)selectAllItems:(id)sender
{
    [playlistTable selectAll:sender];
}

/* Expand All / Collapse All (the sender's title tells them apart, both
 * context-menu items share this action like the 3.0 selectors) */
- (void)recursiveExpandOrCollapseNode:(id)sender
{
    BOOL expand = [[sender title] isEqualToString:_NS("Expand All")];
    if (expand)
        [playlistTable expandItem:nil expandChildren:YES];
    else
        [playlistTable collapseItem:nil collapseChildren:YES];
}

- (void)shufflePlaylist:(id)sender
{
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    playlist_item_t *p_root = [self currentRootLocked:p_playlist];
    /* never shuffle the media library, like 3.0 */
    if (p_root && p_root != p_playlist->p_media_library)
        playlist_RecursiveNodeSort(p_playlist, p_root,
                                   SORT_RANDOM, ORDER_NORMAL);
    playlist_Unlock(p_playlist);
    [self rebuildItemsSnapshot];
}

- (void)addFilesToPlaylist:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    /* folders too, like -[VLCOpenWindowController openFileWithAction:]: a
     * directory is a playlist item of its own, browsed when it is opened */
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:YES];
    [panel setTitle:_NS("Open File")];
    [panel setPrompt:_NS("Open")];
    if ([panel runModal] != NSOKButton)
        return;

    /* insert after the selected row, like -[VLCPlaylist addFilesToPlaylist:] */
    int row = (int)[playlistTable selectedRow];
    int position = row >= 0 ? row + 1 : PLAYLIST_END;

    playlist_t *p_playlist = pl_Get(p_intf);
    NSArray *urls = [panel URLs];
    unsigned i;
    for (i = 0; i < [urls count]; i++) {
        char *psz_uri = vlc_path2uri(
            [[[urls objectAtIndex:i] path] UTF8String], "file");
        if (!psz_uri)
            continue;
        input_item_t *p_input = input_item_New(psz_uri, NULL);
        VLCLegacyNoteRecentItem([NSString stringWithUTF8String:psz_uri]);
        free(psz_uri);
        if (!p_input)
            continue;
        playlist_Lock(p_playlist);
        playlist_item_t *p_root = [self currentRootLocked:p_playlist];
        if (p_root)
            playlist_NodeAddInput(p_playlist, p_input, p_root,
                position == PLAYLIST_END ? PLAYLIST_END : position + (int)i);
        playlist_Unlock(p_playlist);
        input_item_Release(p_input);
    }
    [self rebuildItemsSnapshot];
}

/*****************************************************************************
 * time field (single click / double click, like VLCTimeField)
 *****************************************************************************/

- (void)toggleTimeDisplay
{
    showTimeRemaining = !showTimeRemaining;
    [[NSUserDefaults standardUserDefaults]
        setBool:showTimeRemaining forKey:@"DisplayTimeAsTimeRemaining"];
    [self refresh:nil];
}

- (void)showJumpToTimePanel
{
    if (!jumpPanel) {
        jumpPanel = [[NSPanel alloc]
            initWithContentRect:NSMakeRect(0, 0, 300, 110)
                      styleMask:NSTitledWindowMask | NSClosableWindowMask
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [jumpPanel setTitle:_NS("Jump to Time")];
        [jumpPanel setReleasedWhenClosed:NO];
        NSView *content = [jumpPanel contentView];

        NSTextField *label = [[[NSTextField alloc]
            initWithFrame:NSMakeRect(16, 74, 268, 17)] autorelease];
        [label setEditable:NO];
        [label setBordered:NO];
        [label setDrawsBackground:NO];
        [[label cell] setFont:[NSFont systemFontOfSize:12]];
        [label setStringValue:_NS("Jump to Time")];
        [content addSubview:label];

        jumpField = [[[NSTextField alloc]
            initWithFrame:NSMakeRect(16, 46, 268, 22)] autorelease];
        [[jumpField cell] setFont:[NSFont systemFontOfSize:12]];
        [[jumpField cell] setWraps:NO];
        [[jumpField cell] setScrollable:YES];
        [jumpField setStringValue:@"00:00:00"];
        [content addSubview:jumpField];

        NSButton *okButton = [[[NSButton alloc]
            initWithFrame:NSMakeRect(200, 8, 88, 28)] autorelease];
        [okButton setTitle:_NS("OK")];
        [okButton setBezelStyle:NSRoundedBezelStyle];
        [okButton setKeyEquivalent:@"\r"];
        [okButton setTarget:self];
        [okButton setAction:@selector(jumpToTimeOK:)];
        [content addSubview:okButton];

        NSButton *cancelButton = [[[NSButton alloc]
            initWithFrame:NSMakeRect(108, 8, 88, 28)] autorelease];
        [cancelButton setTitle:_NS("Cancel")];
        [cancelButton setBezelStyle:NSRoundedBezelStyle];
        [cancelButton setKeyEquivalent:@"\033"];
        [cancelButton setTarget:self];
        [cancelButton setAction:@selector(jumpToTimeCancel:)];
        [content addSubview:cancelButton];

        [jumpPanel center];
    }
    /* Le panneau est réutilisé : préremplir à chaque ouverture avec la
     * position courante, pas avec la dernière valeur saisie. */
    {
        int64_t current = 0;
        input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
        if (p_input) {
            current = var_GetInteger(p_input, "time") / CLOCK_FREQ;
            vlc_object_release(p_input);
        }
        [jumpField setStringValue:[NSString stringWithFormat:@"%02lld:%02lld:%02lld",
            (long long)(current / 3600),
            (long long)((current / 60) % 60),
            (long long)(current % 60)]];
    }
    [jumpPanel makeKeyAndOrderFront:nil];
    [jumpField selectText:nil];
}

- (void)jumpToTimeCancel:(id)sender
{
    [jumpPanel orderOut:sender];
}

- (void)jumpToTimeOK:(id)sender
{
    NSArray *components =
        [[jumpField stringValue] componentsSeparatedByString:@":"];
    unsigned count = (unsigned)[components count];
    long long seconds = 0;
    unsigned i;
    for (i = 0; i < count && i < 3; i++)
        seconds = seconds * 60
                + [[components objectAtIndex:i] intValue];

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        if (var_GetBool(p_input, "can-seek"))
            var_SetInteger(p_input, "time",
                           (int64_t)seconds * CLOCK_FREQ);
        vlc_object_release(p_input);
    }
    [jumpPanel orderOut:sender];
}

- (void)showWindow
{
    [window makeKeyAndOrderFront:nil];
}

/* Closing the main window stops playback, like 3.0 */
- (void)windowWillClose:(NSNotification *)notification
{
    if ([notification object] == window)
        [core stop];
}

- (void)shutdown
{
    /* quitting mid-playback must remember the position too */
    [self storeResumePosition];
    [resumeTrackedURI release];
    resumeTrackedURI = nil;
    [updateTimer invalidate];
    updateTimer = nil;
    [self stopHiddenCornerCursorWatch];
    playlist_t *p_playlist = pl_Get(p_intf);
    unsigned i;
    for (i = 0; i < sizeof(changeVariables) / sizeof(changeVariables[0]);
         i++)
        var_DelCallback(p_playlist, changeVariables[i],
                        PlaylistChangedCallback, NULL);
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(hideVideoHostWindowNow)
                                               object:nil];
    [fsVideoWindow orderOut:nil];
    [self closeVideoHostWindow];
    [window orderOut:nil];
}

/*****************************************************************************
 * embedded video (main thread only)
 *****************************************************************************/

/* La vidéo est-elle en plein écran ? (ancien chemin : fenêtre dédiée créée à la
 * volée ; chemin fenêtre enfant : la même fenêtre hôte, agrandie) */
- (BOOL)videoIsFullscreen
{
    return fsVideoWindow != nil || videoHostFullscreen;
}

/* Chantier F — rectangle ÉCRAN de la zone vidéo dans la fenêtre principale
 * (celui qu'occupe la liste de lecture quand il n'y a pas de vidéo). C'est le
 * cadre de la fenêtre hôte en mode fenêtré. */
- (NSRect)videoHostWindowedFrameForNow
{
    NSRect r = [splitView frame];
    /* ⚠ pas de variable nommée `super` : `[super …]` serait un appel à la
     * superclasse, pas à la vue. */
    NSView *parentView = [splitView superview];
    if (parentView)
        r = [parentView convertRect:r toView:nil];  /* → coords fenêtre */
    r.origin = [window convertBaseToScreen:r.origin];
    return r;
}

/* Crée la fenêtre hôte et y déménage la vue vidéo (une seule fois, au début de
 * la lecture : ensuite elle ne bouge plus, c'est tout l'intérêt). */
- (void)openVideoHostWindow
{
    if (videoHostWindow)
        return;

    NSRect frame = [self videoHostWindowedFrameForNow];
    if (frame.size.width < 1 || frame.size.height < 1)
        return;                       /* fenêtre pas encore posée */

    VLCLegacyVideoHostWindow *host = [[VLCLegacyVideoHostWindow alloc]
        initWithContentRect:frame
                  styleMask:NSBorderlessWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    host->keyable = NO;               /* fenêtré : la principale reste clé */
    [host setBackgroundColor:[NSColor blackColor]];
    [host setReleasedWhenClosed:NO];
    /* Sans ombre, quelle que soit l'option « ombres des fenêtres » : cette
     * fenêtre enfant est POSÉE SUR la fenêtre principale et n'en dépasse
     * pas, son ombre tomberait donc sur le contenu de celle-ci (la barre de
     * contrôles). C'est la fenêtre principale qui porte l'ombre du groupe.
     * S'y ajoute la raison de toujours : le recalcul d'ombre à chaque image
     * transforme chaque flush en remap de surface. */
    [host setHasShadow:NO];
    [host setAcceptsMouseMovedEvents:YES];
    VLCLegacyDenyNativeFullscreen(host);

    [videoView retain];
    [videoView removeFromSuperview];
    [videoView setFrame:[[host contentView] bounds]];
    [[host contentView] addSubview:videoView];
    [videoView release];

    videoHostWindow = host;
    videoHostWindowedFrame = frame;
    /* Idem : ne pas exposer la fenêtre hôte si l'utilisateur regarde la liste
     * (un DVD recrée son vout à chaque transition menu/titre). */
    if (!VLCLegacyViewIsHidden(videoView))
        [window addChildWindow:videoHostWindow ordered:NSWindowAbove];
    [self syncVideoSubviews];
}

/* Masquage DIFFÉRÉ de la fenêtre hôte.
 * Sur un DVD, le cœur DÉTRUIT et RECRÉE le vout à chaque transition (menu →
 * titre, changement de format, arrêt sur image) : la vidéo passe donc par
 * releaseVideoView/acquireVideoView plusieurs fois par lecture. Démonter la
 * fenêtre hôte à chaque fois la faisait disparaître puis réapparaître à
 * l'écran (constaté sur « Le Voyage de Chihiro »). On diffère le masquage : si
 * une nouvelle vidéo arrive dans la foulée, il est annulé et rien ne bouge. */
#define VLC_LEGACY_VIDEOHOST_HIDE_DELAY 1.0

/* ⚠ Retirer la fenêtre hôte SANS emporter la fenêtre principale : tant qu'elle
 * est fenêtre ENFANT, un simple -orderOut: ordonne tout le groupe hors écran et
 * PowerVLC disparaît entièrement (constaté sur 10.4, au bouton Stop comme à la
 * bascule vers la liste de lecture). On détache d'abord, puis on remonte la
 * fenêtre principale. */
- (void)detachVideoHostWindow
{
    if (videoHostWindow == nil)
        return;
    NSWindow *parent = [videoHostWindow parentWindow];
    if (parent != nil)
        [parent removeChildWindow:videoHostWindow];
    [videoHostWindow orderOut:nil];
    [window orderFront:nil];
}

/* Remettre la fenêtre hôte en place : ré-attachée à la principale (sinon elle
 * ne suit plus ses déplacements) ET recalée sur la zone vidéo. */
- (void)attachVideoHostWindow
{
    if (videoHostWindow == nil)
        return;
    if ([videoHostWindow parentWindow] == nil)
        [window addChildWindow:videoHostWindow ordered:NSWindowAbove];
    [self syncVideoHostFrame];
    [self syncVideoSubviews];
}

- (void)hideVideoHostWindowNow
{
    if (!videoHostWindow || videoActive)
        return;                       /* une nouvelle vidéo est arrivée */
    [self detachVideoHostWindow];
    /* ⚠ Ne réinitialiser le choix « vue liste » QUE si la lecture est
     * vraiment arrêtée. Un DVD fait disparaître sa vidéo plus d'une seconde à
     * chaque transition (menu → titre, engagement du décodage matériel) : ce
     * masquage différé s'exécute alors en pleine lecture, et remettre le
     * drapeau à zéro faisait reprendre le dessus à la vidéo juste après. */
    {
        playlist_t *p_playlist = pl_Get(p_intf);
        if (p_playlist != NULL && playlist_Status(p_playlist) == PLAYLIST_STOPPED)
            playlistViewWanted = NO;
    }
    /* La lecture s'est vraiment arrêtée : la liste de lecture reprend sa place
     * (c'est ici, et non dans -releaseVideoView, puisque ce dernier peut n'être
     * qu'une transition entre deux vouts du même DVD). */
    VLCLegacySetViewHidden(splitView, NO);
    [window setHasShadow:YES];
}

/* Rend la vue vidéo à la fenêtre principale et démonte la fenêtre hôte. */
- (void)closeVideoHostWindow
{
    if (!videoHostWindow)
        return;
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(hideVideoHostWindowNow)
                                               object:nil];

    [videoView retain];
    [videoView removeFromSuperview];
    [videoView setFrame:[splitView frame]];
    /* sous la barre de contrôles, comme à la sortie du plein écran */
    [[window contentView] addSubview:videoView
                          positioned:NSWindowBelow
                          relativeTo:nil];
    [videoView release];

    [[videoHostWindow parentWindow] removeChildWindow:videoHostWindow];
    [videoHostWindow orderOut:nil];
    [videoHostWindow release];
    videoHostWindow = nil;
    videoHostFullscreen = NO;
}

/* Les fenêtres enfants suivent les DÉPLACEMENTS du parent, pas ses
 * REDIMENSIONNEMENTS : on recadre à la main. Le -reshape de la vue vidéo
 * republie alors la géométrie, et la surface accélérée suit. */
- (void)syncVideoHostFrame
{
    if (!videoHostWindow || videoHostFullscreen)
        return;
    /* Vue LISTE DE LECTURE : la fenêtre hôte a été retirée (cf. -toggleView:)
     * et doit le rester. Sans ce garde-fou, un simple redimensionnement de la
     * fenêtre la remettait à l'écran par -setFrame:display:YES, et la vidéo
     * réapparaissait par-dessus la liste. */
    if (VLCLegacyViewIsHidden(videoView))
        return;
    NSRect frame = [self videoHostWindowedFrameForNow];
    if (frame.size.width < 1 || frame.size.height < 1)
        return;
    videoHostWindowedFrame = frame;
    if (!NSEqualRects(frame, [videoHostWindow frame]))
        [videoHostWindow setFrame:frame display:YES animate:NO];
    /* ⚠ La vue vidéo vit DANS la fenêtre hôte : son cadre doit être celui du
     * contenu de cette fenêtre, pas celui de la zone de liste (exprimé, lui,
     * dans la fenêtre principale). Sans ce recalage, une relance après Stop
     * réutilisait la fenêtre hôte avec une vue décalée de la hauteur de la
     * barre de titre — image trop haute, bande noire en bas. */
    if ([videoView window] == videoHostWindow)
        [videoView setFrame:[[videoHostWindow contentView] bounds]];
    [self syncVideoSubviews];
}

- (NSView *)videoViewIfVisible
{
    if (videoView == nil || VLCLegacyViewIsHidden(videoView))
        return nil;
    return videoView;
}

- (NSView *)acquireVideoView
{
    if (videoActive)
        return nil;
    videoActive = YES;
    /* The window server recomputes the window shadow whenever content
     * near the edges changes: with 25 GL frames a second that turns
     * every flush into a surface remap (io_connect_map_memory storm,
     * one windowed frame in three late). Classic Tiger video-player
     * trick: drop the shadow while video plays -- now under the user's
     * control through "legacy-macosx-window-shadows" (off by default on
     * the slowest slices, where it is worth measurable frames).
     * ⚠ Not below 10.3: there, a shadowless window that shrinks leaves its
     * old pixels behind on the desktop -- the window server never repaints
     * what it uncovered. The measurement that justifies dropping the shadow
     * was made on 10.4 anyway. */
    /* Une surface ATI doit toujours être engagée sur une fenêtre sans ombre.
     * Le choix utilisateur reste mémorisé et l'ombre revient à l'arrêt ; il ne
     * peut pas modifier la forme de la fenêtre sous une surface déjà committée. */
    BOOL hwArmed = VLCLegacyHwDecoderArmed(p_intf);
    if ((!VLCLegacyWindowShadows() || hwArmed)
     && VLCLegacyOSVersionAtLeast(10, 3, 0))
        [window setHasShadow:NO];
    [videoView setFrame:[splitView frame]];
    /* ⚠ Ne PAS reprendre le dessus si l'utilisateur regarde la liste de
     * lecture : un DVD recrée son vout à chaque transition (menu → titre,
     * engagement du décodage matériel), et la vidéo revenait alors d'elle-même
     * quelques secondes après la bascule. */
    if (!playlistViewWanted) {
        VLCLegacySetViewHidden(videoView, NO);
        VLCLegacySetViewHidden(splitView, YES);
    }
    [window makeKeyAndOrderFront:nil];
    if (videoHostWindow) {
        /* Réutilisation : le masquage différé est annulé, la vidéo reprend dans
         * la MÊME fenêtre — donc le même numéro CGS, donc aucune réouverture du
         * décodeur matériel entre deux vouts d'un même DVD. */
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(hideVideoHostWindowNow)
                                                   object:nil];
        if (playlistViewWanted)
            [self detachVideoHostWindow];
        else
            [self attachVideoHostWindow];   /* ré-attache ET recale */
    } else if (var_InheritBool(p_intf, "legacy-macosx-childvideo")
            && VLCLegacyOSVersionAtLeast(10, 4, 0)) {
        /* ⚠ Mesuré sur 10.2.1 : la fenêtre enfant se crée, se place et
         * s'ordonne sans erreur, et n'affiche RIEN — le vout tourne (126
         * images, ponctualité parfaite) dans une surface que le WindowServer
         * ne compose pas. La même vidéo apparaît immédiatement dès que la vue
         * reste dans la fenêtre principale. Le chantier F n'a jamais été
         * validé ailleurs que sur 10.4 ; en dessous on garde le chemin
         * classique, qui coûte une réouverture du vout au plein écran et
         * rien d'autre. */
        [self openVideoHostWindow];
    }
    if (!videoHostWindow)
        [window makeFirstResponder:videoView];
    return videoView;
}

- (void)releaseVideoView
{
    if (!videoActive)
        return;
    if ([self videoIsFullscreen])
        [self setVideoFullscreenFromNumber:[NSNumber numberWithBool:NO]];
    videoActive = NO;
    VLCLegacySetViewHidden(videoView, YES);
    /* La fenêtre hôte SURVIT au vout : un DVD en recrée un à chaque transition
     * (menu → titre…) et la démonter à chaque fois la faisait clignoter. Elle
     * est seulement masquée, et encore, après un délai — annulé si une nouvelle
     * vidéo arrive entre-temps. Elle n'est vraiment détruite qu'au -shutdown. */
    if (videoHostWindow) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self
                                                 selector:@selector(hideVideoHostWindowNow)
                                                   object:nil];
        [self performSelector:@selector(hideVideoHostWindowNow)
                   withObject:nil
                   afterDelay:VLC_LEGACY_VIDEOHOST_HIDE_DELAY];
        return;                 /* splitView/ombre rétablis au vrai arrêt */
    }
    VLCLegacySetViewHidden(splitView, NO);
    [window setHasShadow:YES];
}

/* Applique le réglage « ombres des fenêtres » à la fenêtre déjà à l'écran :
 * la case des préférences agit tout de suite, sans attendre la lecture
 * suivante. Hors lecture l'ombre est de toute façon présente.
 * ⛔ JAMAIS remettre l'ombre pendant une session matérielle armée : la
 * surface REMPLACEMENT est committée sur la forme sans ombre, et tout
 * changement de forme en cours de session fige le WindowServer ou déforme
 * la surface (mesures du 14/08/2026). L'ombre reviendra au prochain arrêt. */
- (void)applyWindowShadowSetting
{
    BOOL hwArmed = VLCLegacyHwDecoderArmed(p_intf);
    if (videoActive && hwArmed && VLCLegacyOSVersionAtLeast(10, 3, 0))
        [window setHasShadow:NO];
    else if (VLCLegacyWindowShadows())
        [window setHasShadow:YES];
    else if (videoActive && VLCLegacyOSVersionAtLeast(10, 3, 0))
        [window setHasShadow:NO];
}

/*****************************************************************************
 * "Hide controls during playback" (Video menu, legacy-macosx-hide-controls)
 *****************************************************************************/

- (BOOL)controlsHiddenForPlayback
{
    return controlsHiddenForPlayback;
}

/* While hidden, the video zone is the whole content view; the splitView
 * frame must follow because the child video window mirrors it. */
- (void)layoutVideoZoneForHiddenControls
{
    NSRect bounds = [[window contentView] bounds];
    [splitView setFrame:bounds];
    if (!videoHostWindow)
        [videoView setFrame:bounds];
    [self syncVideoHostFrame];
    [self syncVideoSubviews];
}

- (void)layoutVideoZoneForVisibleControls
{
    NSRect bounds = [[window contentView] bounds];
    NSRect upper = NSMakeRect(0, BOTTOM_BAR_HEIGHT, bounds.size.width,
                              bounds.size.height - BOTTOM_BAR_HEIGHT);
    [splitView setFrame:upper];
    if (!videoHostWindow)
        [videoView setFrame:upper];
    [self syncVideoHostFrame];
    [self syncVideoSubviews];
}

/* Every picture transformation -- zoom, crop, aspect ratio, the rotation
 * of the video effects, or simply another item -- reaches the interface
 * as the vout asking for a window size, and that is also what a plain
 * restart does. Three cases to tell apart:
 *  - a restart asks for the size it asked for last time: ignored, so the
 *    size the user settled on survives every loop;
 *  - the request keeps the picture SHAPE and only changes its scale:
 *    that is a zoom (Half/Normal/Double, or the matching hotkeys), an
 *    explicit "make it this big", so the requested size is taken as is;
 *  - the request changes the SHAPE (crop, aspect ratio, rotation,
 *    another item): the new shape is fitted inside the box the user is
 *    watching in, so it never grows. Cropping used to blow the window up
 *    instead, bare window or not, because the core drops the zoom factor
 *    on a crop change and then asks for the natural size of the media.
 * The box only follows what the user asks for (a zoom, a hand resize),
 * never a shape change, so going 16:9 -> 4:3 -> 16:9 lands back on the
 * very same window instead of shrinking a little every time.
 * Returns NSZeroSize when the request must be ignored. */
/* The zoom factor the vout is currently applying, 0 when there is no
 * video to ask. */
- (float)currentVideoZoom
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get([core intf]));
    if (!p_input)
        return 0.f;
    vout_thread_t *p_vout = input_GetVout(p_input);
    vlc_object_release(p_input);
    if (!p_vout)
        return 0.f;

    float zoom = var_GetFloat(p_vout, "zoom");
    vlc_object_release(p_vout);
    return zoom;
}

- (NSSize)pictureSizeForRequest:(NSSize)requested currentArea:(NSSize)area
{
    if (requested.width <= 0.f || requested.height <= 0.f)
        return NSZeroSize;

    NSSize previous = lastRequestedVideoSize;
    lastRequestedVideoSize = requested;
    if (previous.width == requested.width
        && previous.height == requested.height)
        return NSZeroSize;

    /* Half / Normal / Double, and the hotkeys that do the same, all go
     * through the vout's "zoom": that is how a scale change the *user*
     * asked for is told apart from one the stream decided on its own. */
    float zoom = [self currentVideoZoom];
    float previousZoom = lastVideoZoom;
    lastVideoZoom = zoom;

    float ratio = requested.width / requested.height;
    BOOL sameShape = (previous.width > 0.f && previous.height > 0.f
        && fabsf(ratio - previous.width / previous.height) <= ratio * 0.005f);

    /* the very first request opens the window at the size of the media,
     * as it always did */
    if (previous.width <= 0.f || previous.height <= 0.f) {
        pictureBox = requested;
        return requested;
    }

    if (sameShape) {
        /* ⚠ Same shape, another size, and nobody asked to zoom: an
         * adaptive stream switching variant. Following it made the window
         * take the pixel size of each variant and end up filling the
         * screen on its own, one step at a time. */
        if (zoom <= 0.f || zoom == previousZoom)
            return NSZeroSize;

        pictureBox = requested;
        return requested;
    }

    NSSize box = pictureBox;
    if (box.width <= 0.f || box.height <= 0.f)
        box = area;
    if (box.width <= 0.f || box.height <= 0.f)
        return requested;
    float fitW = box.width / requested.width;
    float fitH = box.height / requested.height;
    float fit = fitW < fitH ? fitW : fitH;
    return NSMakeSize((float)floor(requested.width * fit + 0.5f),
                      (float)floor(requested.height * fit + 0.5f));
}

- (void)hiddenWindowFollowVideoSize:(NSSize)requested
{
    NSRect frame = [window frame];
    NSRect content = VLCLegacyContentRectForFrameRect(window, frame);
    NSSize picture = [self pictureSizeForRequest:requested
                                     currentArea:content.size];
    if (picture.width <= 0.f || picture.height <= 0.f)
        return;

    /* keep it on the screen, at the ratio it just took */
    NSScreen *screen = [window screen];
    if (!screen)
        screen = [NSScreen mainScreen];
    NSRect visible = [screen visibleFrame];
    float fitW = visible.size.width / picture.width;
    float fitH = visible.size.height / picture.height;
    float fit = fitW < fitH ? fitW : fitH;
    if (fit < 1.f) {
        picture.width = (float)floor(picture.width * fit + 0.5f);
        picture.height = (float)floor(picture.height * fit + 0.5f);
    }
    if (picture.width < 160.f || picture.height < 90.f)
        return;

    /* grow or shrink from the top left corner, where the eye is */
    content.origin.y += content.size.height - picture.height;
    content.size = picture;
    NSRect newFrame = VLCLegacyFrameRectForContentRect(window, content);
    if (NSMaxY(newFrame) > NSMaxY(visible))
        newFrame.origin.y = NSMaxY(visible) - newFrame.size.height;
    [window setFrame:newFrame display:YES];
    [self layoutVideoZoneForHiddenControls];
}

/* Show the resize cursor over the four corner grips of the bare window.
 *
 * ⚠ Cursor RECTS cannot do this job: the embedded video lives in a child
 * window that deliberately refuses key status (see
 * VLCLegacyVideoHostWindow), and AppKit only applies the cursor rects of
 * the key window -- measured, the rects work when the video sits in the
 * main window (legacy-macosx-childvideo off) and never otherwise. So the
 * pointer is polled instead, the same trick the seek bar tooltip uses
 * for the same reason (no tracking areas before 10.5). The arrow is put
 * back only when WE changed it, so the cursor the core hides during
 * playback is left alone. */
- (void)startHiddenCornerCursorWatch
{
    [self stopHiddenCornerCursorWatch];
    hiddenCursorTimer = [[NSTimer scheduledTimerWithTimeInterval:0.1
                                                          target:self
                                                        selector:@selector(hiddenCornerCursorTick:)
                                                        userInfo:nil
                                                         repeats:YES] retain];
}

- (void)stopHiddenCornerCursorWatch
{
    if (hiddenCursorTimer != nil) {
        [hiddenCursorTimer invalidate];
        [hiddenCursorTimer release];
        hiddenCursorTimer = nil;
    }
    if (hiddenCursorZone != 0) {
        [[NSCursor arrowCursor] set];
        hiddenCursorZone = 0;
    }
}

- (void)hiddenCornerCursorTick:(NSTimer *)timer
{
    if (!controlsHiddenForPlayback) {
        [self stopHiddenCornerCursorWatch];
        return;
    }

    NSRect frame = [window frame];
    NSPoint p = [NSEvent mouseLocation];
    float z = VLC_LEGACY_HIDDEN_CORNER_ZONE;
    int zone = 0;                       /* 0 none, 1 NW/SE, 2 NE/SW */
    if (NSMouseInRect(p, frame, NO)
        && frame.size.width >= 2 * z && frame.size.height >= 2 * z) {
        BOOL left = (p.x - NSMinX(frame) <= z);
        BOOL right = (NSMaxX(frame) - p.x <= z);
        BOOL bottom = (p.y - NSMinY(frame) <= z);
        BOOL top = (NSMaxY(frame) - p.y <= z);
        if ((left && top) || (right && bottom))
            zone = 1;
        else if ((right && top) || (left && bottom))
            zone = 2;
    }

    if (zone == hiddenCursorZone)
        return;
    hiddenCursorZone = zone;
    if (zone == 0)
        [[NSCursor arrowCursor] set];
    else
        [VLCLegacyCornerResizeCursor(zone == 1) set];
}

- (void)hideControlsForPlayback
{
    if (controlsHiddenForPlayback || !videoActive
        || [self videoIsFullscreen])
        return;

    /* where the picture sits on screen right now: the window then
     * shrinks onto exactly that rectangle, so the picture neither moves
     * nor changes size. Starting from the video view, the aspect-ratio
     * correction the vout applies inside it is replayed so its thin
     * black bands go away too. */
    NSRect inWindow = [videoView convertRect:[videoView bounds] toView:nil];
    NSRect screenRect;
    screenRect.origin = [[videoView window] convertBaseToScreen:
                            inWindow.origin];
    screenRect.size = inWindow.size;
    if (lastNativeVideoSize.width > 0. && lastNativeVideoSize.height > 0.
        && screenRect.size.width > 0. && screenRect.size.height > 0.) {
        float scale_w = screenRect.size.width / lastNativeVideoSize.width;
        float scale_h = screenRect.size.height / lastNativeVideoSize.height;
        float scale = scale_w < scale_h ? scale_w : scale_h;
        NSSize picture = NSMakeSize(
            (float)floor(lastNativeVideoSize.width * scale + 0.5),
            (float)floor(lastNativeVideoSize.height * scale + 0.5));
        screenRect.origin.x +=
            (float)floor((screenRect.size.width - picture.width) / 2 + 0.5);
        screenRect.origin.y +=
            (float)floor((screenRect.size.height - picture.height) / 2 + 0.5);
        screenRect.size = picture;
    }

    /* a video view caught mid-relayout or mid-teardown (playback ending,
     * a DVD transition, the playlist view coming and going) measures
     * next to nothing: shrinking the window onto that would leave a
     * sliver behind and there would be no picture to watch anyway */
    if (screenRect.size.width < 160.f || screenRect.size.height < 90.f)
        return;

    controlsHiddenForPlayback = YES;
    frameBeforeHidingControls = [window frame];
    lastRequestedVideoSize = lastNativeVideoSize;
    pictureBox = screenRect.size;

    VLCLegacySetViewHidden(bottomBar, YES);

    /* the title bar can only go where -setStyleMask: exists (10.6+);
     * the PowerPC systems this interface targets keep it, only the
     * controls bar goes -- the picture geometry is preserved anyway */
    styleMaskChangedForHiddenControls = NO;
    if ([window respondsToSelector:@selector(setStyleMask:)]) {
        /* ⚠ BORDERLESS SEUL, sans NSResizableWindowMask : sur 10.6 le bit
         * « redimensionnable » sans le bit « titré » n'est pas une
         * combinaison que l'AppKit d'alors accepte, et la barre de titre
         * RESTE -- mesuré par sonde sur Snow Leopard 10.6.8 : masque 8, cadre
         * inchangé à 382 px pour 360 px de contenu ; masque 0, cadre ramené à
         * 360 px. Rien n'est perdu, le redimensionnement par les coins étant
         * fait à la main (-dragHiddenControlsToScreenPoint:) et la fenêtre
         * gardant le statut de fenêtre clé par -canBecomeKeyWindow. */
        typedef NSUInteger (*GetMaskFn)(id, SEL);
        typedef void (*SetMaskFn)(id, SEL, NSUInteger);
        styleMaskBeforeHidingControls =
            ((GetMaskFn)objc_msgSend)(window, @selector(styleMask));
        /* ⚠ mémoriser le titre AVANT : changer le masque recrée le cadre de
         * fenêtre, et le titre est perdu au passage. Le relire au retour
         * ([window title]) ne rend qu'une chaîne VIDE -- constaté sur Snow
         * Leopard : boutons de fenêtre présents, titre absent. */
        [titleBeforeHidingControls release];
        titleBeforeHidingControls = [[window title] copy];
        ((SetMaskFn)objc_msgSend)(window, @selector(setStyleMask:),
            (NSUInteger)NSBorderlessWindowMask);
        styleMaskChangedForHiddenControls = YES;
    }

    NSRect frame = VLCLegacyFrameRectForContentRect(window, screenRect);
    [window setFrame:frame display:YES];
    hiddenControlsInitialFrame = frame;
    [self layoutVideoZoneForHiddenControls];

    [window makeKeyAndOrderFront:nil];
    if (!videoHostWindow)
        [window makeFirstResponder:videoView];

    [core setControlsHiddenForPlayback:YES];
    [self startHiddenCornerCursorWatch];
}

- (void)revealControlsForPlayback
{
    if (!controlsHiddenForPlayback)
        return;
    controlsHiddenForPlayback = NO;
    mouseOutsideSince = 0;
    autoHideRevealTicks = 0;

    /* the frame before hiding, carried over by whatever the user moved
     * or resized the naked window to meanwhile */
    NSRect hiddenFrame = [window frame];
    NSRect frame = frameBeforeHidingControls;
    frame.origin.x += hiddenFrame.origin.x
                    - hiddenControlsInitialFrame.origin.x;
    frame.origin.y += hiddenFrame.origin.y
                    - hiddenControlsInitialFrame.origin.y;
    frame.size.width += hiddenFrame.size.width
                      - hiddenControlsInitialFrame.size.width;
    frame.size.height += hiddenFrame.size.height
                       - hiddenControlsInitialFrame.size.height;

    VLCLegacySetViewHidden(bottomBar, NO);
    if (styleMaskChangedForHiddenControls) {
        typedef void (*SetMaskFn)(id, SEL, NSUInteger);
        ((SetMaskFn)objc_msgSend)(window, @selector(setStyleMask:),
                                  styleMaskBeforeHidingControls);
        styleMaskChangedForHiddenControls = NO;
        /* a fresh titled frame comes up blank -- and asking the window for
         * its own title gives "" by then, so restore the copy taken before */
        [window setTitle:titleBeforeHidingControls ?
                             titleBeforeHidingControls : @""];
    }

    /* keep the whole window on the screen (the title bar coming back on
     * top could push it under the menu bar) */
    NSScreen *screen = [window screen];
    if (!screen)
        screen = [NSScreen mainScreen];
    NSRect visible = [screen visibleFrame];
    if (NSMaxY(frame) > NSMaxY(visible))
        frame.origin.y = NSMaxY(visible) - frame.size.height;

    [window setFrame:frame display:YES];
    [self layoutVideoZoneForVisibleControls];
    [window makeKeyAndOrderFront:nil];

    [core setControlsHiddenForPlayback:NO];
    [self stopHiddenCornerCursorWatch];
}

/* Driven by the refresh tick: 10.2 has no tracking primitive worth the
 * name for this, and a 3 s delay does not need one. */
- (void)updateAutoHideControls
{
    BOOL enabled = [core autoHideControls];
    BOOL fullscreen = [self videoIsFullscreen];
    BOOL videoShown = videoActive && !playlistViewWanted
                      && !VLCLegacyViewIsHidden(videoView);

    if (controlsHiddenForPlayback) {
        /* Fullscreen reveals them on the way in (see
         * -setVideoFullscreenFromNumber:); doing it from here as well would
         * re-lay the windowed frame out on top of the fullscreen one. */
        if (fullscreen)
            return;
        if (!enabled) {
            [self revealControlsForPlayback];
            return;
        }
        /* the video being gone is often transient (loop restart, next
         * playlist item, DVD menu transition): only give up once it has
         * been gone for a few consecutive ticks (~3 s) */
        if (!videoShown) {
            autoHideRevealTicks++;
            int threshold = VLCLegacyOSVersionAtLeast(10, 4, 0) ? 10 : 3;
            if (autoHideRevealTicks >= threshold)
                [self revealControlsForPlayback];
        } else {
            autoHideRevealTicks = 0;
        }
        return;
    }

    autoHideRevealTicks = 0;
    /* the video being on show is the whole condition: a pause hides just
     * as well (the OSD is the feedback then), the playlist view never
     * does */
    if (!enabled || fullscreen || !videoShown) {
        mouseOutsideSince = 0;
        return;
    }
    if (NSMouseInRect([NSEvent mouseLocation], [window frame], NO)) {
        mouseOutsideSince = 0;
        return;
    }
    double now = [NSDate timeIntervalSinceReferenceDate];
    if (mouseOutsideSince == 0) {
        mouseOutsideSince = now;
        return;
    }
    if (now - mouseOutsideSince >= 3.0)
        [self hideControlsForPlayback];
}

- (void)beginHiddenControlsDragAtScreenPoint:(NSPoint)point
{
    [self beginVideoDragAtScreenPoint:point allowResize:YES];
}

/* ⚠ A drag is only ever honoured between a mouse-down on the picture and
 * the matching mouse-up. Without that, any stray -mouseDragged: reaching
 * the video view -- the one that follows a click whose press was eaten by
 * the menu tracking loop, for instance -- was taken as the continuation of
 * whatever drag happened last, and moved the window by the difference
 * between two unrelated pointer positions. */
- (void)endVideoDrag
{
    videoDragActive = NO;
}

- (void)beginVideoDragAtScreenPoint:(NSPoint)point allowResize:(BOOL)allowResize
{
    videoDragActive = YES;
    hiddenDragStartMouse = point;
    hiddenDragStartFrame = [window frame];
    hiddenDragStartOrigin = hiddenDragStartFrame.origin;

    if (!allowResize) {
        /* with the controls up the window still has its own frame and
         * resize control: dragging the picture only MOVES it */
        hiddenDragResizeH = 0;
        hiddenDragResizeV = 0;
        hiddenDragIsResize = NO;
        return;
    }

    /* corner zones resize, everything else moves */
    float zone = VLC_LEGACY_HIDDEN_CORNER_ZONE;
    hiddenDragResizeH =
        (point.x - NSMinX(hiddenDragStartFrame) <= zone) ? -1 :
        ((NSMaxX(hiddenDragStartFrame) - point.x <= zone) ? 1 : 0);
    hiddenDragResizeV =
        (point.y - NSMinY(hiddenDragStartFrame) <= zone) ? -1 :
        ((NSMaxY(hiddenDragStartFrame) - point.y <= zone) ? 1 : 0);
    hiddenDragIsResize = (hiddenDragResizeH != 0 && hiddenDragResizeV != 0);
}

/* Keeps enough of the window on the screen to grab it again: the picture
 * is the whole grab area here, so a window dragged fully past an edge
 * could not be brought back at all. Dragging it PARTLY out stays allowed,
 * as everywhere else on the system. */
- (NSPoint)dragOriginKeptReachable:(NSPoint)origin
{
    NSRect visible = [[window screen] visibleFrame];
    NSRect frame = [window frame];
    float margin = (frame.size.width < 120.f) ? frame.size.width : 120.f;
    float vmargin = (frame.size.height < 60.f) ? frame.size.height : 60.f;

    if (origin.x + frame.size.width < NSMinX(visible) + margin)
        origin.x = NSMinX(visible) + margin - frame.size.width;
    if (origin.x > NSMaxX(visible) - margin)
        origin.x = NSMaxX(visible) - margin;

    if (origin.y + frame.size.height > NSMaxY(visible))
        origin.y = NSMaxY(visible) - frame.size.height;
    if (origin.y + frame.size.height < NSMinY(visible) + vmargin)
        origin.y = NSMinY(visible) + vmargin - frame.size.height;

    return origin;
}

- (void)dragHiddenControlsToScreenPoint:(NSPoint)point
{
    if (!videoDragActive)
        return;

    if (!hiddenDragIsResize) {
        NSPoint origin = NSMakePoint(
            hiddenDragStartOrigin.x + (point.x - hiddenDragStartMouse.x),
            hiddenDragStartOrigin.y + (point.y - hiddenDragStartMouse.y));
        [window setFrameOrigin:[self dragOriginKeptReachable:origin]];
        return;
    }

    /* the window IS the picture: one dimension drives, the ratio gives
     * the other, and the corner opposite the grabbed one stays put */
    float width = hiddenDragStartFrame.size.width
        + (point.x - hiddenDragStartMouse.x) * hiddenDragResizeH;
    if (width < 160.f)
        width = 160.f;
    float ratio = (lastNativeVideoSize.width > 0.
                   && lastNativeVideoSize.height > 0.)
        ? lastNativeVideoSize.height / lastNativeVideoSize.width
        : hiddenDragStartFrame.size.height / hiddenDragStartFrame.size.width;
    NSRect frame = hiddenDragStartFrame;
    frame.size.width = width;
    frame.size.height = (float)floor(width * ratio + 0.5);
    if (hiddenDragResizeH < 0)
        frame.origin.x = NSMaxX(hiddenDragStartFrame) - frame.size.width;
    if (hiddenDragResizeV < 0)
        frame.origin.y = NSMaxY(hiddenDragStartFrame) - frame.size.height;

    [window setFrame:frame display:YES];
    /* resizing by hand redefines the box a later crop fits into */
    pictureBox = frame.size;
    [self layoutVideoZoneForHiddenControls];
}

/* Old-style NSOpenGLContext surfaces do not reliably track window resizes;
 * re-setting the vout subview frame forces a context update. */
- (void)syncVideoSubviews
{
    NSArray *subviews = [videoView subviews];
    unsigned i;
    for (i = 0; i < [subviews count]; i++)
        [[subviews objectAtIndex:i] setFrame:[videoView bounds]];
}

- (void)setVideoViewSizeFromValue:(NSValue *)value
{
    if (!videoActive || [self videoIsFullscreen])
        return;
    NSSize size = [value sizeValue];
    /* remembered for the picture-fit of the auto-hidden window */
    lastNativeVideoSize = size;
    /* While the controls are auto-hidden the frame is exactly the
     * picture the user watches: a plain input restart (loop, next item)
     * must not blow it back up to the decorated size, but a genuine
     * ratio change -- a crop, an aspect ratio, an item of another shape
     * -- has to be followed, otherwise cropping looks like it does
     * nothing and puts bands back inside the bare window. */
    if (controlsHiddenForPlayback) {
        [self hiddenWindowFollowVideoSize:size];
        return;
    }
    /* see -pictureSizeForRequest:currentArea: -- the bare window is the
     * picture itself, the decorated one keeps its chrome around it, but
     * both follow the same rule */
    size = [self pictureSizeForRequest:size currentArea:[videoView frame].size];
    if (size.width <= 0.f || size.height <= 0.f)
        return;
    /* Resize the window so the video area gets the requested size, keeping
     * the top-left corner in place (VLC 3.0 behavior). -setFrame: bypasses
     * -minSize, so clamp explicitly like VLC 3.0 does. */
    NSSize minSize = [window minSize];
    if (size.width < minSize.width)
        size.width = minSize.width;
    if (size.height < minSize.height - BOTTOM_BAR_HEIGHT)
        size.height = minSize.height - BOTTOM_BAR_HEIGHT;
    NSRect frame = [window frame];
    NSRect contentr =
        VLCLegacyContentRectForFrameRect(window, frame);
    float newHeight = size.height + BOTTOM_BAR_HEIGHT;
    contentr.origin.y += contentr.size.height - newHeight;
    contentr.size.width = size.width;
    contentr.size.height = newHeight;
    NSRect newFrame = VLCLegacyFrameRectForContentRect(window, contentr);

    /* Keep the whole window (bottom bar included!) on the screen: a 720p
     * video on a 800px display would otherwise push the controls below
     * the screen edge. */
    NSScreen *screen = [window screen];
    if (!screen)
        screen = [NSScreen mainScreen];
    NSRect visible = [screen visibleFrame];
    if (newFrame.size.width > visible.size.width)
        newFrame.size.width = visible.size.width;
    if (newFrame.size.height > visible.size.height)
        newFrame.size.height = visible.size.height;
    if (NSMaxX(newFrame) > NSMaxX(visible))
        newFrame.origin.x = NSMaxX(visible) - newFrame.size.width;
    if (newFrame.origin.x < visible.origin.x)
        newFrame.origin.x = visible.origin.x;
    if (NSMaxY(newFrame) > NSMaxY(visible))
        newFrame.origin.y = NSMaxY(visible) - newFrame.size.height;
    if (newFrame.origin.y < visible.origin.y)
        newFrame.origin.y = visible.origin.y;

    [window setFrame:newFrame display:YES animate:NO];
    [self syncVideoSubviews];
}

/* Écran de destination du plein écran : legacy-macosx-vdev (0 = celui de la
 * fenêtre), même correspondance que le menu des préférences. */
- (NSScreen *)fullscreenScreen
{
    NSScreen *screen = [window screen];
    int i_vdev = (int)var_InheritInteger(p_intf, "legacy-macosx-vdev");
    if (i_vdev) {
        NSArray *screens = [NSScreen screens];
        unsigned si;
        for (si = 0; si < [screens count]; si++) {
            NSScreen *candidate = [screens objectAtIndex:si];
            if ([[[candidate deviceDescription]
                    objectForKey:@"NSScreenNumber"] intValue] == i_vdev) {
                screen = candidate;
                break;
            }
        }
    }
    return screen ? screen : [NSScreen mainScreen];
}

/* Écrans secondaires noircis pendant le plein écran (legacy-macosx-black). */
- (void)openBlackScreensExcept:(NSScreen *)screen
{
    if (!var_InheritBool(p_intf, "legacy-macosx-black"))
        return;
    NSArray *screens = [NSScreen screens];
    unsigned si;
    if (!fsBlackWindows)
        fsBlackWindows = [[NSMutableArray alloc] init];
    for (si = 0; si < [screens count]; si++) {
        NSScreen *other = [screens objectAtIndex:si];
        if (other == screen)
            continue;
        NSWindow *black = [[[NSWindow alloc]
            initWithContentRect:[other frame]
                      styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered
                          defer:NO] autorelease];
        [black setBackgroundColor:[NSColor blackColor]];
        [black setReleasedWhenClosed:NO];
        [black setLevel:NSNormalWindowLevel];
        [black orderFront:nil];
        [fsBlackWindows addObject:black];
    }
}

- (void)closeBlackScreens
{
    if (!fsBlackWindows)
        return;
    unsigned si;
    for (si = 0; si < [fsBlackWindows count]; si++)
        [[fsBlackWindows objectAtIndex:si] orderOut:nil];
    [fsBlackWindows removeAllObjects];
}


/* Chantier F — bascule plein écran de la fenêtre HÔTE : un redimensionnement,
 * rien d'autre. La vue vidéo ne déménage pas, le numéro de fenêtre ne change
 * pas → la sortie accélérée continue sans réouverture ni image noire. */
- (void)setVideoHostFullscreen:(BOOL)enter
{
    if (enter == videoHostFullscreen) {
        return;
    }

    VLCLegacyVideoHostWindow *host = (VLCLegacyVideoHostWindow *)videoHostWindow;

    if (enter) {
        NSScreen *screen = [self fullscreenScreen];
        videoHostWindowedFrame = [host frame];
        /* La relation parent/enfant est CONSERVÉE en plein écran : une fenêtre
         * enfant est toujours au-dessus de son parent, donc la fenêtre
         * principale ne peut pas réapparaître par-dessus la vidéo (constaté
         * quand on détachait : elle repassait devant). La fenêtre elle-même ne
         * change pas — seul son cadre grandit. */
        [self openBlackScreensExcept:screen];
        /* Barre de menus masquée AVANT l'agrandissement : dans l'autre ordre
         * elle reste visible par-dessus la vidéo le temps d'un rafraîchissement. */
        if ([screen hasMenuBar] || [screen hasDock])
            SetSystemUIMode(kUIModeAllHidden, kUIOptionAutoShowMenuBar);
        host->keyable = YES;          /* Échap / Espace en plein écran */
        [host setFrame:[screen frame] display:YES animate:NO];
        videoHostFullscreen = YES;
        /* ⚠ The view does not follow the window on its own here: growing
         * the host window leaves the video view at the size it had, and
         * since a Cocoa view keeps its origin at the BOTTOM the picture
         * ends up sitting on the bottom edge with a black band above it --
         * the screen visibly not covered. The heavy path (a dedicated
         * fullscreen window) has always set the frame explicitly; this one
         * relied on an autoresizing mask that the hidden-controls layout
         * can have replaced with an explicit frame.
         * ⚠ Not all the way up on a notched screen: the window does cover
         * the whole display, but the picture stops below the camera strip,
         * which the window's BLACK background then fills (see
         * VLCLegacySafeContentRect). */
        if ([videoView window] == host)
            [videoView setFrame:VLCLegacySafeContentRect(host, screen)];
        [self syncVideoSubviews];
        [host makeKeyAndOrderFront:nil];
        [host makeFirstResponder:videoView];
    } else {
        SetSystemUIMode(kUIModeNormal, 0);
        [self closeBlackScreens];
        videoHostFullscreen = NO;
        host->keyable = NO;           /* fenêtré : la principale redevient clé */
        [host setFrame:videoHostWindowedFrame display:YES animate:NO];
        if ([videoView window] == host)
            [videoView setFrame:[[host contentView] bounds]];
        [self syncVideoSubviews];
        [self syncVideoHostFrame];    /* la fenêtre a pu bouger entre-temps */
        [window makeKeyAndOrderFront:nil];
    }
}

/* VOUT_WINDOW_SET_STATE for the embedded picture (Video > Float on Top).
 * The video is hosted by the main window and, in windowed playback, by a
 * borderless CHILD of it: AppKit keeps a child ordered above its parent but
 * does not carry a level change over to it, so raise both. */
- (void)setVideoAboveOthersFromNumber:(NSNumber *)above
{
    int level = [above boolValue] ? NSFloatingWindowLevel : NSNormalWindowLevel;
    [window setLevel:level];
    if (videoHostWindow)
        [videoHostWindow setLevel:level];
}

- (void)setVideoFullscreenFromNumber:(NSNumber *)fullscreen
{
    BOOL enter = [fullscreen boolValue];
    if (!videoActive) {
        return;
    }

    /* ⚠ Fullscreen must start from the normal window state. With the
     * controls auto-hidden the window IS the picture, and the frames the
     * transition saves and restores are that bare frame; worse, the
     * auto-hide tick reveals the controls as soon as it notices fullscreen
     * -- which lays the *windowed* frame back over the fullscreen one, and
     * leaves the picture the size it had in a window, with black around.
     * Revealing here, before anything is resized, is what the modern
     * interface does in -windowWillEnterFullScreen:. */
    if (enter && controlsHiddenForPlayback)
        [self revealControlsForPlayback];

    if (videoHostWindow) {
        [self setVideoHostFullscreen:enter];
        return;
    }

    /* ⚠⚠ CHEMIN LOURD : pas de fenêtre hôte ⇒ on CRÉE une fenêtre sans bordure
     * et on y DÉMÉNAGE la vue vidéo. Avec la sortie QuickDraw, changer de
     * fenêtre change de port QuickDraw, donc impose de détruire et recréer la
     * séquence de décompression QuickTime. C'est le chemin le plus exposé, et
     * c'est précisément celui que ma première instrumentation ne couvrait pas —
     * le témoin ne montrait AUCUNE étape parce qu'il regardait l'autre branche. */

    if ((enter && fsVideoWindow) || (!enter && !fsVideoWindow)) {
        return;
    }

    if (enter) {
        /* fullscreen device (legacy-macosx-vdev): 0 = the window's own
         * screen, otherwise the CGDirectDisplayID of the wanted screen
         * (same tags as the preferences popup) */
        NSScreen *screen = [self fullscreenScreen];
        fsVideoWindow = [[VLCLegacyBorderlessWindow alloc]
            initWithContentRect:[screen frame]
                      styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [self openBlackScreensExcept:screen];
        [fsVideoWindow setBackgroundColor:[NSColor blackColor]];
        [fsVideoWindow setReleasedWhenClosed:NO];
        [fsVideoWindow setAcceptsMouseMovedEvents:YES];
        [videoView retain];
        preFullscreenVideoFrame = [videoView frame];   /* pour la restitution */
        [videoView removeFromSuperview];
        /* écran à encoche : l'image s'arrête sous la bande de la caméra, que
         * le fond noir de la fenêtre remplit (VLCLegacySafeContentRect) */
        [videoView setFrame:VLCLegacySafeContentRect(fsVideoWindow, screen)];
        [[fsVideoWindow contentView] addSubview:videoView];
        [videoView release];
        if ([screen hasMenuBar] || [screen hasDock])
            SetSystemUIMode(kUIModeAllHidden, kUIOptionAutoShowMenuBar);
        [self syncVideoSubviews];
        [fsVideoWindow makeKeyAndOrderFront:nil];
        [fsVideoWindow makeFirstResponder:videoView];
    } else {
        SetSystemUIMode(kUIModeNormal, 0);
        [self closeBlackScreens];
        [videoView retain];
        [videoView removeFromSuperview];
        /* ★ Restituer le cadre MÉMORISÉ à l'aller, et non celui du splitView :
         * ce dernier avait rétréci entre-temps (1024x576 au démarrage de la
         * vidéo, 690x404 à la sortie du plein écran), d'où une vidéo tassée
         * dans un coin et le reste du cadre en blanc — le framebuffer OpenGL
         * n'étant jamais peint quand le décodage matériel est en mode
         * remplacement. */
        if (preFullscreenVideoFrame.size.width > 0
            && preFullscreenVideoFrame.size.height > 0)
            [videoView setFrame:preFullscreenVideoFrame];
        else
            [videoView setFrame:[splitView frame]];
        /* re-insert BELOW the controls bar: appending it last would put
         * the GL surface back over the bar (the setupWindow stacking
         * fix would be undone on every fullscreen exit) */
        [[window contentView] addSubview:videoView
                              positioned:NSWindowBelow
                              relativeTo:nil];
        [videoView release];
        [fsVideoWindow orderOut:nil];
        [fsVideoWindow release];
        fsVideoWindow = nil;
        [self syncVideoSubviews];
        [window makeKeyAndOrderFront:nil];
        [window makeFirstResponder:videoView];
    }
}

/*****************************************************************************
 * control actions
 *****************************************************************************/

- (void)playPause:(id)sender
{
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    bool b_empty = playlist_IsEmpty(p_playlist);
    playlist_Unlock(p_playlist);

    if (b_empty)
        [self openFiles:sender];
    else
        [core togglePlayPause];
}

- (void)stop:(id)sender          { [core stop]; }
- (void)next:(id)sender          { [core next]; }
- (void)prev:(id)sender          { [core previous]; }
- (void)fullscreen:(id)sender    { [core toggleFullscreen]; }

/* Combined backward/forward buttons (VLCControlsBarCommon semantics):
 * in jump-buttons mode they are plain seek buttons; otherwise a single
 * click changes item, holding them (continuous button) seeks in
 * extrashort steps and suppresses the item change. */
- (void)fwd:(id)sender
{
    if (var_InheritBool(p_intf, "legacy-macosx-show-playback-buttons")) {
        [core jumpExtraShort:YES];
        return;
    }
    double now = [NSDate timeIntervalSinceReferenceDate];
    if (!justTriggeredNext) {
        justTriggeredNext = YES;
        lastForwardEvent = 0;
        [self performSelector:@selector(resetNextButton)
                   withObject:nil afterDelay:0.40];
    } else if (now - lastForwardEvent > 0.16) {
        lastForwardEvent = now;
        [core jumpExtraShort:YES];
        [NSObject cancelPreviousPerformRequestsWithTarget:self
            selector:@selector(resetNextButton) object:nil];
        [self performSelector:@selector(resetNextButton)
                   withObject:nil afterDelay:0.40];
    }
}

- (void)resetNextButton
{
    if (lastForwardEvent == 0)   /* plain click: no hold-seek happened */
        [core next];
    justTriggeredNext = NO;
}

- (void)bwd:(id)sender
{
    if (var_InheritBool(p_intf, "legacy-macosx-show-playback-buttons")) {
        [core jumpExtraShort:NO];
        return;
    }
    double now = [NSDate timeIntervalSinceReferenceDate];
    if (!justTriggeredPrevious) {
        justTriggeredPrevious = YES;
        lastBackwardEvent = 0;
        [self performSelector:@selector(resetPreviousButton)
                   withObject:nil afterDelay:0.40];
    } else if (now - lastBackwardEvent > 0.16) {
        lastBackwardEvent = now;
        [core jumpExtraShort:NO];
        [NSObject cancelPreviousPerformRequestsWithTarget:self
            selector:@selector(resetPreviousButton) object:nil];
        [self performSelector:@selector(resetPreviousButton)
                   withObject:nil afterDelay:0.40];
    }
}

- (void)resetPreviousButton
{
    if (lastBackwardEvent == 0)
        [core previous];
    justTriggeredPrevious = NO;
}

- (void)volumeChanged:(id)sender
{
    [core setVolume:[sender floatValue]];
}

- (void)seeked:(id)sender
{
    if ([core clipCreationMode]) {
        /* both knobs define the clip bounds; moving either one seeks
         * there so the user previews what the clip will contain */
        VLCLegacyProgressSliderCell *seekCell =
            (VLCLegacyProgressSliderCell *)[seekSlider cell];
        float fraction;
        int knob = [seekCell activeClipKnob];
        if (knob == 2) {
            fraction = (float)[seekCell clipEndValue];
            [core setClipEndPosition:fraction];
            [core setClipSelectedKnob:2];
        } else if (knob == 3) {
            /* scrub between the bounds: seek only, bounds untouched */
            fraction = (float)[seekCell playbackMarkerValue];
        } else {
            fraction = [sender floatValue];
            [core setClipStartPosition:fraction];
            [core setClipSelectedKnob:1];
        }
        [core setPositionFraction:fraction];
        return;
    }
    [core setPositionFraction:[sender floatValue]];
}

/* hover delegate of the seek slider: fired once the mouse has settled
 * for a second (the slider debounces so a frantic hover cannot spam a
 * secondary decode, which matters a lot on a G3) */
- (void)seekSlider:(VLCLegacySeekSlider *)slider
        hoverThumbnailWantedAtFraction:(double)fraction
{
    [[VLCLegacySeekThumbnailer sharedInstance]
        requestThumbnailWithIntf:p_intf fraction:fraction forSlider:slider];
}

/* bare arrow keys pressed while the slider is the first responder
 * (clip mode): one-frame nudge of the selected bound */
- (void)seekSlider:(VLCLegacySeekSlider *)slider
        clipStepFrames:(int)direction
{
    [core clipStepFrames:direction];
}

/* chapter separators on the seek bar and names for its hover tooltip,
 * same INPUT_GET_TITLE_INFO rules as the Qt and modern seek sliders:
 * only usable when the seekpoints carry time offsets */
- (void)updateChaptersForInput:(input_thread_t *)p_input
                      duration:(int64_t)i_length
{

    VLCLegacyProgressSliderCell *cell =
        (VLCLegacyProgressSliderCell *)[seekSlider cell];

    int title = p_input ? (int)var_GetInteger(p_input, "title") : -1;

    /* ⚠⚠⚠ IDENTIFIER LE MÉDIA PAR SON URI, pas par le pointeur d'entrée.
     * Un `input_thread_t` fraîchement alloué retombe très souvent à la MÊME
     * adresse que celui qu'on vient de fermer : avec (pointeur, titre) pour
     * seule identité, deux fichiers successifs passaient pour le même média,
     * et la garde « un sondage vide n'efface pas » conservait alors les
     * marqueurs du PRÉCÉDENT sur un fichier qui n'a aucun chapitre.
     * Constaté en enchaînant deux vidéos. L'URI, elle, ne ment pas. */
    char *psz_uri = NULL;
    if (p_input != NULL) {
        input_item_t *p_item = input_GetItem(p_input);
        if (p_item != NULL)
            psz_uri = input_item_GetURI(p_item);
    }
    BOOL sameMedia = ((psz_uri == NULL && chaptersUri == NULL)
                      || (psz_uri != NULL && chaptersUri != NULL
                          && strcmp(psz_uri, chaptersUri) == 0))
                     && title == chaptersTitle;
    BOOL sameSource = sameMedia && i_length == chaptersDuration;

    if (!sameMedia) {
        free(chaptersUri);
        chaptersUri = psz_uri;      /* on en prend la propriété */
        psz_uri = NULL;
    }
    free(psz_uri);
    /* ⚠⚠ NE JAMAIS mémoriser un ÉCHEC de façon définitive. Sur un DVD, la
     * durée et le numéro de titre sont publiés AVANT que les points de
     * chapitre ne portent leurs décalages temporels : la première passe ne
     * trouvait rien, le triplet (entrée, titre, durée) ne bougeait plus
     * ensuite, et les marqueurs n'apparaissaient alors JAMAIS de toute la
     * lecture. D'où un symptôme qui dépend de l'ordre d'arrivée — le même
     * disque montrait ses chapitres une fois sur deux, et seul le
     * redémarrage de l'application semblait « corriger » quoi que ce soit.
     * On ne court-circuite donc que sur un résultat POSITIF ; sinon on
     * retente, mais pas à chaque sondage (INPUT_GET_TITLE_INFO recopie tout
     * l'arbre des titres, trois fois par seconde ce serait cher sur un G3). */
    if (sameSource && [cell chapterFractions] != nil)
        return;
    if (sameSource && ++chaptersRetryTicks < 8)   /* ~2,5 s */
        return;
    chaptersRetryTicks = 0;
    chaptersTitle = title;
    chaptersDuration = i_length;

    NSArray *fractions = nil;
    NSArray *names = nil;
    if (p_input && i_length > 0) {
        input_title_t *p_title = NULL;
        int i_title_id = -1;
        if (input_Control(p_input, INPUT_GET_TITLE_INFO, &p_title,
                          &i_title_id) == VLC_SUCCESS && p_title) {
            if (p_title->i_seekpoint > 1
                && p_title->seekpoint[p_title->i_seekpoint - 1]->i_time_offset
                   > 0) {
                NSMutableArray *mutableFractions = [NSMutableArray
                    arrayWithCapacity:p_title->i_seekpoint];
                NSMutableArray *mutableNames = [NSMutableArray
                    arrayWithCapacity:p_title->i_seekpoint];
                int i;
                for (i = 0; i < p_title->i_seekpoint; i++) {
                    seekpoint_t *point = p_title->seekpoint[i];
                    /* beaucoup de disques numérotent leurs chapitres sans
                     * les nommer : sans repli, le survol n'affichait que
                     * l'heure. « Chapter %i » existe déjà au catalogue. */
                    NSString *name =
                        (point->psz_name != NULL && *point->psz_name != '\0')
                        ? [NSString stringWithUTF8String:point->psz_name]
                        : [NSString stringWithFormat:_NS("Chapter %i"), i + 1];
                    [mutableFractions addObject:
                        [NSNumber numberWithDouble:
                            (double)point->i_time_offset / (double)i_length]];
                    [mutableNames addObject:name ? name : @""];
                }
                fractions = mutableFractions;
                names = mutableNames;
            }
            vlc_input_title_Delete(p_title);
        }
    }

    /* the common case is "no chapters, again": do not trigger a repaint
     * of the whole track every poll for it */
    if (!fractions && ![cell chapterFractions])
        return;
    /* ⚠⚠ Ne pas EFFACER des marqueurs déjà trouvés sur un simple échec de
     * sondage. Sur un DVD la durée retombe transitoirement à zéro (frontière
     * de cellule, bascule de domaine) : le triplet changeait, on recalculait,
     * on ne trouvait rien, et la barre perdait ses chapitres EN PLEINE
     * LECTURE. Tant que le média est le même (même entrée, même titre), un
     * résultat vide veut dire « pas maintenant », pas « il n'y en a plus » ;
     * un vrai changement de titre ou la fin de lecture, eux, font tomber
     * `sameMedia` et nettoient bien la barre. */
    if (!fractions && sameMedia)
        return;
    [cell setChapterFractions:fractions names:names];
    [seekSlider setNeedsDisplay:YES];
}

- (void)searchChanged:(id)sender
{
    [searchString release];
    searchString = [[sender stringValue] copy];
    /* the display filter must agree with the core-side flags, which are
     * set from the folded needle too */
    [searchStringFolded release];
    searchStringFolded = [VLCLegacyFoldedString(searchString) retain];
    [self rebuildItemsSnapshot];
}

/* Only ever called on 10.2, where the search field is a plain NSTextField
 * and would otherwise wait for Return: VLCLegacyMakeSearchField() makes us
 * its delegate in that case and in no other. */
- (void)controlTextDidChange:(NSNotification *)notification
{
    if ([notification object] == searchField)
        [self searchChanged:searchField];
}

/* View toggle button: switch between video and playlist, like the 3.0
 * playlist button */
- (void)toggleView:(id)sender
{
    if (!videoActive)
        return;
    BOOL showPlaylist = VLCLegacyViewIsHidden(videoView) == NO;
    playlistViewWanted = showPlaylist;
    VLCLegacySetViewHidden(videoView, showPlaylist);
    VLCLegacySetViewHidden(splitView, !showPlaylist);
    /* ⚠ Pendant la lecture, la vue vidéo n'est PAS dans la fenêtre principale :
     * elle vit dans une FENÊTRE HÔTE posée pile sur la zone de la liste (cf.
     * -openVideoHostWindow). Masquer la vue ne faisait donc que noircir cette
     * fenêtre, qui continuait de recouvrir la liste de lecture — le bouton
     * paraissait sans effet (constaté sur 10.4 ET 10.5, avec ou sans décodage
     * matériel). Il faut retirer la fenêtre hôte, et la remettre au retour. */
    if (videoHostWindow != nil) {
        if (showPlaylist)
            [self detachVideoHostWindow];
        else
            [self attachVideoHostWindow];
    }
}

- (void)openFiles:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    /* folders too, like -[VLCLegacyOpen openFile] and -addFilesToPlaylist: */
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:YES];
    [panel setTitle:_NS("Open File")];
    [panel setPrompt:_NS("Open")];
    if ([panel runModal] != NSOKButton)
        return;

    NSMutableArray *paths = [NSMutableArray array];
    NSArray *urls = [panel URLs];
    unsigned count = (unsigned)[urls count];
    unsigned i;
    for (i = 0; i < count; i++)
        [paths addObject:[[urls objectAtIndex:i] path]];
    [self addPaths:paths playFirst:YES];
}

/* Une chaîne qui porte DÉJÀ un schéma (« dvdsimple://… », « http://… ») est une
 * MRL, pas un chemin : la passer à vlc_path2uri(…, "file") la transformerait en
 * nom de fichier RELATIF, donc en `file:///Users/…/dvdsimple%3A///Volumes/…`.
 * Grammaire RFC 3986 : ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) ":".
 * ⚠ Un chemin absolu commence par « / » et n'a donc jamais de schéma ; sur HFS
 * un nom de fichier PEUT contenir « : », mais jamais avant le premier « / ». */
static BOOL VLCLegacyStringIsMRL(NSString *s)
{
    const char *p = [s UTF8String];
    if (p == NULL || !isalpha((unsigned char) *p))
        return NO;
    for (p++; *p != '\0'; p++) {
        if (*p == ':')
            return p[1] != '\0';          /* schéma non vide suivi de quelque chose */
        if (!isalnum((unsigned char) *p) && *p != '+' && *p != '-' && *p != '.')
            return NO;
    }
    return NO;
}

- (void)addPaths:(NSArray *)paths playFirst:(BOOL)play
{
    playlist_t *p_playlist = pl_Get(p_intf);
    unsigned count = (unsigned)[paths count];
    unsigned i;
    for (i = 0; i < count; i++) {
        NSString *entry = [paths objectAtIndex:i];
        /* ⚠⚠ Ce chemin reçoit AUSSI les arguments de lancement, que le
         * délégué NSApplication relaie en « openFile ». Une MRL passée en
         * ligne de commande y arrivait donc telle quelle et repartait en
         * chemin de fichier bidon — un SECOND item, mort, ajouté avec
         * playFirst ⇒ il PRÉEMPTAIT le vrai, d'où le « incoming request -
         * stopping current input » juste après un « successfully opened ». */
        char *psz_uri = VLCLegacyStringIsMRL(entry)
                      ? strdup([entry UTF8String])
                      : vlc_path2uri([entry UTF8String], "file");
        if (!psz_uri)
            continue;
        playlist_Add(p_playlist, psz_uri, play && i == 0);
        VLCLegacyNoteRecentItem([NSString stringWithUTF8String:psz_uri]);
        free(psz_uri);
    }
}

/*****************************************************************************
 * sidebar
 *****************************************************************************/

/* every sidebar entry is mutable: the badge counts are updated live */
- (void)addSidebarHeader:(NSString *)title
{
    [sidebarItems addObject:
        [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"header", @"kind", title, @"title", nil]];
}

/* the 3.0 sidebar icons (VLCSidebarDataSource artwork) */
- (NSImage *)sidebarIcon:(NSString *)name
{
    NSImage *icon = VLCLegacyImage(name);
    if (!icon) {
        icon = [[[NSApp applicationIconImage] copy] autorelease];
        if (!icon)
            return nil;
    }
    [icon setSize:NSMakeSize(16, 16)];
    return icon;
}

/* per-service icon, same mapping as VLCSidebarDataSource */
- (NSImage *)sidebarIconForSD:(const char *)name category:(int)category
{
    switch (category) {
    case SD_CAT_INTERNET:
        return [self sidebarIcon:@"sidebar-podcast"];
    case SD_CAT_DEVICES:
    case SD_CAT_LAN:
        return [self sidebarIcon:@"sidebar-local"];
    case SD_CAT_MYCOMPUTER:
        if (!strncmp(name, "video_dir", 9))
            return [self sidebarIcon:@"sidebar-movie"];
        if (!strncmp(name, "audio_dir", 9))
            return [self sidebarIcon:@"sidebar-music"];
        if (!strncmp(name, "picture_dir", 11))
            return [self sidebarIcon:@"sidebar-pictures"];
        return [self sidebarIcon:@"NSApplicationIcon"];
    }
    return nil;
}

/* Deterministic order for known SD modules: the module-bank order behind
 * vlc_sd_GetNames varies between builds, so the plain probe order differs
 * from one machine to another. 3.0 shows Internet as Podcasts, Jamendo,
 * Icecast and My Computer as Videos, Music, Pictures; reproduce that.
 * Unknown modules sort after the ranked ones, keeping their probe order. */
- (int)sidebarSDRank:(const char *)name
{
    if (!name)
        return 1000;
    /* lua SD arrive as lua{sd='jamendo'}: rank on the inner script name */
    const char *key = name;
    char buf[64];
    const char *p = strstr(name, "sd='");
    if (p) {
        p += 4;
        size_t n = 0;
        while (p[n] && p[n] != '\'' && n < sizeof(buf) - 1) {
            buf[n] = p[n];
            n++;
        }
        buf[n] = '\0';
        key = buf;
    }
    static const char *const order[] = {
        "podcast", "jamendo", "icecast",           /* INTERNET */
        "video_dir", "audio_dir", "picture_dir",   /* MY COMPUTER */
    };
    int i;
    for (i = 0; i < (int)(sizeof(order) / sizeof(order[0])); i++)
        if (!strncmp(key, order[i], strlen(order[i])))
            return i;
    return 1000;
}

- (void)buildSidebarModel
{
    [sidebarItems removeAllObjects];

    [self addSidebarHeader:_NS("LIBRARY")];
    [sidebarItems addObject:
        [NSMutableDictionary dictionaryWithObjectsAndKeys:
            @"playlist", @"kind", _NS("Playlist"), @"title",
            [self sidebarIcon:@"sidebar-playlist"], @"icon", nil]];
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    BOOL hasML = p_playlist->p_media_library != NULL;
    playlist_Unlock(p_playlist);
    if (hasML)
        [sidebarItems addObject:
            [NSMutableDictionary dictionaryWithObjectsAndKeys:
                @"ml", @"kind", _NS("Media Library"), @"title",
                [self sidebarIcon:@"sidebar-playlist"], @"icon", nil]];

    /* services discovery, grouped like the 3.0 sidebar */
    char **names = NULL, **longnames = NULL;
    int *categories = NULL;
    names = vlc_sd_GetNames(p_intf, &longnames, &categories);
    if (names) {
        static const struct { int cat; const char *title; } sections[4] = {
            { SD_CAT_MYCOMPUTER, N_("MY COMPUTER") },
            { SD_CAT_DEVICES,    N_("DEVICES") },
            { SD_CAT_LAN,        N_("LOCAL NETWORK") },
            { SD_CAT_INTERNET,   N_("INTERNET") },
        };
        int section;
        for (section = 0; section < 4; section++) {
            /* gather this category's entries... */
            int idx[64];
            int nidx = 0;
            int i;
            for (i = 0; names[i]; i++) {
                if (categories[i] == sections[section].cat
                 && nidx < (int)(sizeof(idx) / sizeof(idx[0])))
                    idx[nidx++] = i;
            }
            /* ...then order them (stable insertion sort by preferred rank,
             * a handful of items per category) */
            int a;
            for (a = 1; a < nidx; a++) {
                int v = idx[a];
                int rv = [self sidebarSDRank:names[v]];
                int b = a - 1;
                while (b >= 0 && [self sidebarSDRank:names[idx[b]]] > rv) {
                    idx[b + 1] = idx[b];
                    b--;
                }
                idx[b + 1] = v;
            }
            if (nidx > 0)
                [self addSidebarHeader:_NS(sections[section].title)];
            for (a = 0; a < nidx; a++) {
                i = idx[a];
                NSImage *icon = [self sidebarIconForSD:names[i]
                                              category:categories[i]];
                [sidebarItems addObject:
                    [NSMutableDictionary dictionaryWithObjectsAndKeys:
                        @"sd", @"kind",
                        [NSString stringWithUTF8String:
                            vlc_gettext(longnames[i])],
                        @"title",
                        [NSString stringWithUTF8String:names[i]], @"sd",
                        icon, @"icon",
                        nil]];
            }
        }
        int i;
        for (i = 0; names[i]; i++) {
            free(names[i]);
            free(longnames[i]);
        }
        free(names);
        free(longnames);
        free(categories);
    }
    [sidebarTable reloadData];
}

/* resolves the currently selected sidebar entry to a playlist node */
- (playlist_item_t *)currentRootLocked:(playlist_t *)p_playlist
{
    if (sidebarSelection < 0
     || (unsigned)sidebarSelection >= [sidebarItems count])
        return p_playlist->p_playing;
    NSDictionary *entry = [sidebarItems objectAtIndex:sidebarSelection];
    NSString *kind = [entry objectForKey:@"kind"];
    if ([kind isEqualToString:@"ml"] && p_playlist->p_media_library)
        return p_playlist->p_media_library;
    if ([kind isEqualToString:@"sd"]) {
        /* the SD node lives under the hidden root, named by longname */
        const char *psz_name = [[entry objectForKey:@"title"] UTF8String];
        playlist_item_t *p_root = &p_playlist->root;
        int i;
        for (i = 0; i < p_root->i_children; i++) {
            playlist_item_t *p_node = p_root->pp_children[i];
            if (p_node->p_input && p_node->p_input->psz_name
             && !strcmp(p_node->p_input->psz_name, psz_name))
                return p_node;
        }
        return p_playlist->p_playing;
    }
    return p_playlist->p_playing;
}

/*****************************************************************************
 * podcasts
 *****************************************************************************/

/* "podcast-urls" is one pipe-separated string, shared by the module and
 * its stored configuration. */
- (NSArray *)podcastUrls
{
    char *psz_urls = config_GetPsz(p_intf, "podcast-urls");
    if (!psz_urls || !*psz_urls) {
        free(psz_urls);
        return [NSArray array];
    }
    NSArray *urls = [[NSString stringWithUTF8String:psz_urls]
        componentsSeparatedByString:@"|"];
    free(psz_urls);
    return urls;
}

- (void)setPodcastUrls:(NSArray *)urls
{
    const char *psz_urls = [[urls componentsJoinedByString:@"|"] UTF8String];
    /* the running module watches the playlist variable, the preference
     * carries the list over to the next launch: both need the update */
    config_PutPsz(p_intf, "podcast-urls", psz_urls);
    var_SetString(pl_Get(p_intf), "podcast-urls", psz_urls);
    /* the module rebuilds its node in its own thread; the periodic
     * refresh picks the result up, this only shortens the wait */
    [self rebuildItemsSnapshot];
    [self updatePodcastRemoveButton];
}

/* Unsubscribe acts on the list selection, so it only makes sense while a
 * feed row -- not an episode -- is selected. */
- (void)updatePodcastRemoveButton
{
    if (!podcastBarVisible)
        return;
    [podcastRemoveButton setEnabled:
        [[self selectedPodcastFeedUrls] count] > 0];
}

/* the podcast service is a plain C module: its sidebar entry carries the
 * module name verbatim (the Lua ones read lua{sd='...'}) */
- (BOOL)podcastRowIsSelected
{
    if (sidebarSelection < 0
     || (unsigned)sidebarSelection >= [sidebarItems count])
        return NO;
    NSString *sd = [[sidebarItems objectAtIndex:sidebarSelection]
        objectForKey:@"sd"];
    return sd != nil && [sd isEqualToString:@"podcast"];
}

- (void)setPodcastBarVisible:(BOOL)visible
{
    if (!podcastBar || podcastBarVisible == visible)
        return;
    podcastBarVisible = visible;
    if (visible)
        [self updatePodcastRemoveButton];
    VLCLegacySetViewHidden(podcastBar, !visible);
    /* the table has no flexible margin, only a flexible size: shifting
     * it once by the strip height holds across every later resize */
    NSRect frame = [playlistScroll frame];
    frame.origin.y += visible ? PODCAST_BAR_HEIGHT : -PODCAST_BAR_HEIGHT;
    frame.size.height -= visible ? PODCAST_BAR_HEIGHT : -PODCAST_BAR_HEIGHT;
    if (frame.size.height < 0.0f)
        frame.size.height = 0.0f;
    [playlistScroll setFrame:frame];
}

- (void)subscribePodcast:(id)sender
{
    NSString *url = VLCLegacyRunTextPrompt(
        _NS("Subscribe to a podcast"),
        _NS("Enter URL of the podcast to subscribe to:"),
        _NS("Subscribe"), _NS("Cancel"), @"");
    if (!url)
        return;
    url = [url stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    /* an empty entry would add a bogus feed, a duplicate would be
     * dropped by the module anyway */
    if ([url length] == 0)
        return;
    NSMutableArray *urls =
        [NSMutableArray arrayWithArray:[self podcastUrls]];
    if ([urls containsObject:url])
        return;
    [urls addObject:url];
    [self setPodcastUrls:urls];
}

/* Feed URLs of the rows selected in the list. Only the top-level rows
 * are feeds; their children are the episodes and unsubscribing on one of
 * those would silently drop the whole podcast. */
- (NSArray *)selectedPodcastFeedUrls
{
    NSMutableArray *urls = [NSMutableArray array];
    NSArray *selection = VLCLegacySelectedRows(playlistTable);
    playlist_t *p_playlist = pl_Get(p_intf);
    unsigned i;
    for (i = 0; i < [selection count]; i++) {
        NSInteger row = (NSInteger)[[selection objectAtIndex:i] intValue];
        NSDictionary *entry = [playlistTable itemAtRow:row];
        /* -parentForItem: would say the same but is 10.4 */
        if (!entry || [playlistTable levelForRow:row] != 0)
            continue;
        char *psz_uri = NULL;
        playlist_Lock(p_playlist);
        playlist_item_t *p_item = playlist_ItemGetById(p_playlist,
            [[entry objectForKey:@"id"] intValue]);
        if (p_item && p_item->p_input)
            psz_uri = input_item_GetURI(p_item->p_input);
        playlist_Unlock(p_playlist);
        if (!psz_uri)
            continue;
        [urls addObject:[NSString stringWithUTF8String:psz_uri]];
        free(psz_uri);
    }
    return urls;
}

/* Delete on the podcast list means unsubscribe: dropping the node alone
 * would leave the feed in the configuration and the module would put it
 * straight back. NO when the selection holds no feed. */
- (BOOL)unsubscribeSelectedPodcasts
{
    NSArray *selected = [self selectedPodcastFeedUrls];
    if ([selected count] == 0)
        return NO;
    NSMutableArray *urls =
        [NSMutableArray arrayWithArray:[self podcastUrls]];
    NSUInteger before = [urls count];
    [urls removeObjectsInArray:selected];
    if ([urls count] == before)
        return NO;
    [self setPodcastUrls:urls];
    return YES;
}

/* No confirmation panel: the feeds to drop are the ones selected in the
 * list, which is unambiguous, and re-subscribing is one URL away. */
- (void)unsubscribePodcast:(id)sender
{
    [self unsubscribeSelectedPodcasts];
}

/*****************************************************************************
 * playlist table
 *****************************************************************************/

- (void)playSelectedItem:(id)sender
{
    int row = (int)[playlistTable clickedRow];
    if (row < 0) {
        row = (int)[playlistTable selectedRow];
        if (row < 0)
            return;
    }
    NSDictionary *entry = [playlistTable itemAtRow:row];
    if (!entry)
        return;

    int itemId = [[entry objectForKey:@"id"] intValue];
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    /* Resolve by id: the item may have been deleted since the snapshot */
    playlist_item_t *p_item = playlist_ItemGetById(p_playlist, itemId);
    if (p_item) {
        /* double-clicking a node starts playing inside it (3.0) */
        if (p_item->i_children >= 0)
            playlist_ViewPlay(p_playlist, p_item, NULL);
        else
            /* Play the leaf within the shown root so playback continues
             * through its siblings. Passing NULL as the node makes the core
             * default to the current status node (p_playing), which is wrong
             * for a Media Library leaf: it is not under p_playing, so the
             * "current" queue would be built from the playlist and playback
             * would stop after this one track. currentRootLocked is the root
             * the leaf actually lives in (Playlist, Media Library, SD). */
            playlist_ViewPlay(p_playlist,
                              [self currentRootLocked:p_playlist], p_item);
    }
    playlist_Unlock(p_playlist);
}

- (void)deleteSelectedItems:(id)sender
{
    NSArray *selection = VLCLegacySelectedRows(playlistTable);
    if (![selection count])
        return;

    /* on the podcast list the delete shortcut unsubscribes instead */
    if ([self podcastRowIsSelected] && [self unsubscribeSelectedPodcasts])
        return;

    /* collect the ids first: the outline rows shift as nodes go away */
    NSMutableArray *ids = [NSMutableArray array];
    unsigned i;
    for (i = 0; i < [selection count]; i++) {
        NSInteger row = (NSInteger)[[selection objectAtIndex:i] intValue];
        NSDictionary *entry = [playlistTable itemAtRow:row];
        if (entry)
            [ids addObject:[entry objectForKey:@"id"]];
    }
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    for (i = 0; i < [ids count]; i++) {
        playlist_item_t *p_item = playlist_ItemGetById(p_playlist,
            [[ids objectAtIndex:i] intValue]);
        if (p_item)
            playlist_NodeDelete(p_playlist, p_item);
    }
    playlist_Unlock(p_playlist);
    [self rebuildItemsSnapshot];
}

/* context menu: media info window is owned by the app delegate */
- (void)showItemInfo:(id)sender
{
    id delegate = [NSApp delegate];
    if ([delegate respondsToSelector:@selector(mediaInfoController)])
        [[delegate performSelector:@selector(mediaInfoController)]
            performSelector:@selector(showWindow)];
}

- (void)revealItemInFinder:(id)sender
{
    int row = (int)[playlistTable clickedRow];
    if (row < 0)
        row = (int)[playlistTable selectedRow];
    NSDictionary *entry = row >= 0 ? [playlistTable itemAtRow:row] : nil;
    if (!entry)
        return;
    int itemId = [[entry objectForKey:@"id"] intValue];
    playlist_t *p_playlist = pl_Get(p_intf);
    char *psz_uri = NULL;
    playlist_Lock(p_playlist);
    playlist_item_t *p_item = playlist_ItemGetById(p_playlist, itemId);
    if (p_item && p_item->p_input)
        psz_uri = input_item_GetURI(p_item->p_input);
    playlist_Unlock(p_playlist);
    if (!psz_uri)
        return;
    char *psz_path = vlc_uri2path(psz_uri);
    if (psz_path) {
        [[NSWorkspace sharedWorkspace] selectFile:
            [NSString stringWithUTF8String:psz_path]
                         inFileViewerRootedAtPath:@""];
        free(psz_path);
    }
    free(psz_uri);
}

/*****************************************************************************
 * table data sources (playlist table and sidebar share the controller)
 *****************************************************************************/

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    if (tableView == sidebarTable)
        return (NSInteger)[sidebarItems count];
    return 0;   /* the playlist view is an outline now */
}

/* outline data source (playlist tree) */
- (NSInteger)outlineView:(NSOutlineView *)outlineView
    numberOfChildrenOfItem:(id)item
{
    NSArray *children = item ? [item objectForKey:@"children"] : items;
    return (NSInteger)[children count];
}

- (id)outlineView:(NSOutlineView *)outlineView
            child:(NSInteger)index
           ofItem:(id)item
{
    NSArray *children = item ? [item objectForKey:@"children"] : items;
    if (index < 0 || (unsigned)index >= [children count])
        return nil;
    return [children objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return [item objectForKey:@"children"] != nil;
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (tableView == sidebarTable) {
        if (row < 0 || (unsigned)row >= [sidebarItems count])
            return @"";
        return [[sidebarItems objectAtIndex:row] objectForKey:@"title"];
    }
    return nil;
}

- (id)outlineView:(NSOutlineView *)outlineView
    objectValueForTableColumn:(NSTableColumn *)column
                       byItem:(id)item
{
    if (!item)
        return nil;

    /* like the 3.0 playlist, the narrow leading column stays empty (no
     * artwork thumbnails): the playing row is marked by its bold font */
    if ([[column identifier] isEqualToString:@"art"])
        return nil;

    /* file sizes are resolved lazily (stat during the snapshot walk would
     * run disk I/O under the playlist lock) and cached per path */
    if ([[column identifier] isEqualToString:@"filesize"]) {
        NSString *path = [item objectForKey:@"path"];
        if (![path length])
            return @"";
        NSString *cached = [fileSizeCache objectForKey:path];
        if (cached)
            return cached;
        NSDictionary *attributes = [[NSFileManager defaultManager]
            fileAttributesAtPath:path traverseLink:YES];
        NSNumber *size = [attributes objectForKey:NSFileSize];
        NSString *formatted = @"";
        if (size) {
            double bytes = [size doubleValue];
            if (bytes >= 1024.0 * 1024.0 * 1024.0)
                formatted = [NSString stringWithFormat:@"%.1f GiB",
                             bytes / (1024.0 * 1024.0 * 1024.0)];
            else if (bytes >= 1024.0 * 1024.0)
                formatted = [NSString stringWithFormat:@"%.1f MiB",
                             bytes / (1024.0 * 1024.0)];
            else
                formatted = [NSString stringWithFormat:@"%.1f KiB",
                             bytes / 1024.0];
        }
        [fileSizeCache setObject:formatted forKey:path];
        return formatted;
    }
    return [item objectForKey:[column identifier]];
}

/* sidebar styling and selection rules */
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
    if (tableView == sidebarTable) {
        if (row < 0 || (unsigned)row >= [sidebarItems count])
            return NO;
        return ![[[sidebarItems objectAtIndex:row] objectForKey:@"kind"]
            isEqualToString:@"header"];
    }
    return YES;
}

- (void)outlineView:(NSOutlineView *)outlineView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
               item:(id)item
{
    if (VLCLegacyDarkMode() && [cell respondsToSelector:
            @selector(setTextColor:)])
        [cell setTextColor:VLCLegacyTextColor()];
    /* the playing item is bold, like the VLC 3.0 playlist */
    if (![[column identifier] isEqualToString:@"art"] && item) {
        BOOL isCurrent =
            [[item objectForKey:@"id"] intValue] == currentItemId;
        NSFont *font = [cell font];
        if (font) {
            NSFontManager *manager = [NSFontManager sharedFontManager];
            [cell setFont:isCurrent
                ? [manager convertFont:font toHaveTrait:NSBoldFontMask]
                : [manager convertFont:font
                       toNotHaveTrait:NSBoldFontMask]];
        }
    }
}

- (void)tableView:(NSTableView *)tableView
    willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)column
                row:(NSInteger)row
{
    if (tableView != sidebarTable)
        return;
    NSDictionary *entry = row >= 0 && (unsigned)row < [sidebarItems count]
        ? [sidebarItems objectAtIndex:row] : nil;
    BOOL isHeader =
        [[entry objectForKey:@"kind"] isEqualToString:@"header"];
    if (isHeader) {
        [cell setFont:[NSFont boldSystemFontOfSize:9]];
        [cell setTextColor:
            [NSColor colorWithCalibratedWhite:0.44 alpha:1.0]];
    } else {
        [cell setFont:[NSFont systemFontOfSize:11]];
        [cell setTextColor:VLCLegacyDarkMode()
            ? VLCLegacyTextColor() : [NSColor blackColor]];
    }
    if ([cell isKindOfClass:[VLCLegacySidebarCell class]]) {
        [(VLCLegacySidebarCell *)cell setIcon:
            isHeader ? nil : [entry objectForKey:@"icon"]];
        [(VLCLegacySidebarCell *)cell setHeaderStyle:isHeader];
        [(VLCLegacySidebarCell *)cell setBadge:
            [[entry objectForKey:@"badge"] intValue]];
    }
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    [self updatePodcastRemoveButton];
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    if ([notification object] != sidebarTable)
        return;
    int row = (int)[sidebarTable selectedRow];
    if (row < 0 || (unsigned)row >= [sidebarItems count])
        return;
    NSDictionary *entry = [sidebarItems objectAtIndex:row];
    if ([[entry objectForKey:@"kind"] isEqualToString:@"header"])
        return;
    sidebarSelection = row;
    [viewTitleLabel setStringValue:[entry objectForKey:@"title"]];
    /* Subscribe / Unsubscribe belong to the podcast list only */
    [self setPodcastBarVisible:[self podcastRowIsSelected]];

    /* activate the services discovery on first use, like 3.0 */
    NSString *sd = [entry objectForKey:@"sd"];
    if (sd && ![activatedServices containsObject:sd]) {
        /* Lua-backed directories (their chain reads lua{sd='...'}) can
         * be very slow on this class of hardware (Icecast parses ~20 MB
         * of XML in Lua): ask before the first activation. */
        if ([sd hasPrefix:@"lua{"]) {
            NSInteger answer = NSRunAlertPanel(
                _NS("Enable this service?"),
                @"%@",
                _NS("Yes"), _NS("No"), nil,
                _NS("This service uses a Lua script. Loading it can be "
                    "slow and may affect the performance of this machine. "
                    "Do you want to continue?"));
            if (answer != NSAlertDefaultReturn) {
                /* back to the playlist view */
                sidebarSelection = 1;
                VLCLegacySelectRow(sidebarTable, 1);
                [self rebuildItemsSnapshot];
                return;
            }
        }
        playlist_ServicesDiscoveryAdd(pl_Get(p_intf), [sd UTF8String]);
        [activatedServices addObject:sd];
    } else if (sd && !s_sdReloadBusy) {
        /* an on-line service left empty (network hiccup during its
         * one-shot discovery) has no other way to retry: selecting it
         * again restarts the module, in the background (removing a
         * service joins its thread, which may sit in a network fetch) */
        playlist_t *p_playlist = pl_Get(p_intf);
        BOOL isEmpty = NO;
        playlist_Lock(p_playlist);
        playlist_item_t *p_node = playlist_ChildSearchName(&p_playlist->root,
            [[entry objectForKey:@"title"] UTF8String]);
        isEmpty = VLCLegacySDNodeLooksEmpty(p_node);
        playlist_Unlock(p_playlist);
        if (isEmpty) {
            /* reclaim the previous, finished reload thread (there is no
             * detached variant in this core) */
            if (s_sdReloadJoinable) {
                vlc_join(s_sdReloadThread, NULL);
                s_sdReloadJoinable = NO;
            }
            struct VLCLegacySDReload *req = calloc(1, sizeof(*req));
            char *name = strdup([sd UTF8String]);
            if (req && name) {
                req->playlist = p_playlist;
                req->name = name;
                s_sdReloadBusy = true;
                if (vlc_clone(&s_sdReloadThread, VLCLegacySDReloadThread,
                              req, VLC_THREAD_PRIORITY_LOW) == 0) {
                    /* ownership moved to the thread */
                    s_sdReloadJoinable = YES;
                    req = NULL;
                    name = NULL;
                } else {
                    s_sdReloadBusy = false;
                }
            }
            if (req || name) {
                free(name);
                free(req);
            }
        }
    }
    [self rebuildItemsSnapshot];
}

/* dropping media on the sidebar Playlist / Media Library rows (3.0) */
- (NSDragOperation)tableView:(NSTableView *)tableView
                validateDrop:(id <NSDraggingInfo>)info
                 proposedRow:(NSInteger)row
       proposedDropOperation:(NSTableViewDropOperation)operation
{
    if (tableView == sidebarTable) {
        NSArray *pbTypes = [[info draggingPasteboard] types];
        if (![pbTypes containsObject:NSFilenamesPboardType]
         && ![pbTypes containsObject:VLCLegacyPlaylistItemPboardType])
            return NSDragOperationNone;
        int r;
        for (r = 0; (unsigned)r < [sidebarItems count]; r++) {
            NSString *kind = [[sidebarItems objectAtIndex:r]
                objectForKey:@"kind"];
            if (([kind isEqualToString:@"playlist"]
              || [kind isEqualToString:@"ml"])
             && (row == r || operation == NSTableViewDropAbove)) {
                if (row != r)
                    continue;
                [tableView setDropRow:r
                        dropOperation:NSTableViewDropOn];
                return NSDragOperationCopy;
            }
        }
        return NSDragOperationNone;
    }
    if ([[[info draggingPasteboard] types]
            containsObject:NSFilenamesPboardType])
        return NSDragOperationCopy;
    return NSDragOperationNone;
}

/* --- the playlist outline as a drag SOURCE (VLC 3.0 parity) --------------
 * Any row shown under Library / My Computer / a playlist can be grabbed and
 * dropped: reordered inside the tree, copied onto the Playlist or Media
 * Library sidebar rows, or dragged out to the Finder and other apps (as
 * files, when the items are local). Mirrors VLCPLModel / VLCSidebarDataSource. */

/* recursively gather the on-disk paths of the dragged rows (nodes included) */
- (void)collectLocalPaths:(NSArray *)array into:(NSMutableArray *)paths
{
    unsigned i;
    for (i = 0; i < [array count]; i++) {
        NSDictionary *entry = [array objectAtIndex:i];
        NSString *path = [entry objectForKey:@"path"];
        if (path)
            [paths addObject:path];
        NSArray *children = [entry objectForKey:@"children"];
        if (children)
            [self collectLocalPaths:children into:paths];
    }
}

/* YES when item is node itself or one of its descendants (by playlist id) */
- (BOOL)item:(NSDictionary *)item isInNode:(NSDictionary *)node
{
    if (!item)
        return NO;                 /* the root target is never inside a node */
    if (item == node
     || [[item objectForKey:@"id"] isEqual:[node objectForKey:@"id"]])
        return YES;
    NSArray *children = [node objectForKey:@"children"];
    unsigned i;
    for (i = 0; i < [children count]; i++) {
        if ([self item:item isInNode:[children objectAtIndex:i]])
            return YES;
    }
    return NO;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
         writeItems:(NSArray *)draggedRows
       toPasteboard:(NSPasteboard *)pboard
{
    if (outlineView != playlistTable || ![draggedRows count])
        return NO;

    [draggedItems autorelease];
    draggedItems = [draggedRows retain];

    NSMutableArray *types = [NSMutableArray
        arrayWithObject:VLCLegacyPlaylistItemPboardType];
    NSMutableArray *paths = [NSMutableArray array];
    [self collectLocalPaths:draggedRows into:paths];
    if ([paths count])
        [types addObject:NSFilenamesPboardType];

    [pboard declareTypes:types owner:self];
    [pboard setData:[NSData data] forType:VLCLegacyPlaylistItemPboardType];
    if ([paths count])
        [pboard setPropertyList:paths forType:NSFilenamesPboardType];
    return YES;
}

/* move the dragged rows under p_parent at index via playlist_TreeMoveMany */
- (BOOL)moveDraggedItemsInto:(NSDictionary *)targetItem
                     atIndex:(NSInteger)index
{
    unsigned count = [draggedItems count];
    if (!count)
        return NO;

    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);

    playlist_item_t *p_parent = targetItem
        ? playlist_ItemGetById(p_playlist,
              [[targetItem objectForKey:@"id"] intValue])
        : [self currentRootLocked:p_playlist];
    if (!p_parent || p_parent->i_children < 0) {
        playlist_Unlock(p_playlist);
        return NO;
    }

    playlist_item_t **pp_items =
        (playlist_item_t **)calloc(count, sizeof(playlist_item_t *));
    if (!pp_items) {
        playlist_Unlock(p_playlist);
        return NO;
    }
    unsigned i, j = 0;
    for (i = 0; i < count; i++) {
        playlist_item_t *p_item = playlist_ItemGetById(p_playlist,
            [[[draggedItems objectAtIndex:i] objectForKey:@"id"] intValue]);
        if (p_item)
            pp_items[j++] = p_item;
    }

    int target = p_parent->i_children;   /* dropping on a node → append */
    if (index != NSOutlineViewDropOnItemIndex) {
        /* the outline shows a snapshot, and a live search hides rows from
         * it: the displayed child index is not the core one.  Translate it
         * through the id of the row the insertion point aims at (without a
         * search the two coincide, so this is a no-op then). */
        NSArray *siblings = targetItem ? [targetItem objectForKey:@"children"]
                                       : items;
        if (index >= 0 && (unsigned)index < [siblings count]) {
            int i_id = [[[siblings objectAtIndex:index]
                            objectForKey:@"id"] intValue];
            int k;
            for (k = 0; k < p_parent->i_children; k++) {
                if (p_parent->pp_children[k]->i_id == i_id) {
                    target = k;
                    break;
                }
            }
        }
    }

    BOOL ok = j > 0
        && playlist_TreeMoveMany(p_playlist, (int)j, pp_items,
                                 p_parent, target) == VLC_SUCCESS;
    playlist_Unlock(p_playlist);
    free(pp_items);

    if (ok) {
        s_playlistDirty = YES;
        [self rebuildItemsSnapshot];
    }
    return ok;
}

/* services discovery trees mirror an external source (on-line radio
 * directories...): the user cannot reorder them or drop files into
 * them.  Dragging OUT of them (to the sidebar Playlist / Media
 * Library) stays possible: that path does not come through here.
 *
 * ⚠ The test is the IDENTITY of the root, not PLAYLIST_RO_FLAG: the core
 * creates BOTH p_playing and p_media_library with that flag (engine.c),
 * where it only means "this node itself may not be deleted" -- and
 * PLAYLIST_NO_INHERIT_FLAG keeps their children out of it. Testing the
 * flag therefore declared the Playlist and the Media Library read-only
 * too, which killed every drop and every reorder on the playlist area
 * (only the "Drop media here" dropzone, which never goes through the
 * outline, kept working). The modern interface tests the root type the
 * same way (VLCPLModel -editAllowed). */
- (BOOL)currentRootIsReadOnly
{
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    playlist_item_t *p_root = [self currentRootLocked:p_playlist];
    BOOL readOnly = p_root != p_playlist->p_playing
                 && p_root != p_playlist->p_media_library;
    playlist_Unlock(p_playlist);
    return readOnly;
}

/* where a snapshot row sits in the tree: its parent row (nil at the top
 * level) and its rank among that parent's children.  -parentForItem: would
 * answer the first half, but it is 10.4 and this interface still runs on
 * 10.2. */
- (BOOL)locateItem:(id)needle
           inArray:(NSArray *)array
            parent:(id)parentItem
         outParent:(id *)outParent
          outIndex:(NSInteger *)outIndex
{
    unsigned i;
    for (i = 0; i < [array count]; i++) {
        id entry = [array objectAtIndex:i];
        if (entry == needle) {
            *outParent = parentItem;
            *outIndex = (NSInteger)i;
            return YES;
        }
        NSArray *children = [entry objectForKey:@"children"];
        if (children && [self locateItem:needle
                                 inArray:children
                                  parent:entry
                               outParent:outParent
                                outIndex:outIndex])
            return YES;
    }
    return NO;
}

/* dropping files, or our own rows, on the playlist outline */
- (NSDragOperation)outlineView:(NSOutlineView *)outlineView
                  validateDrop:(id <NSDraggingInfo>)info
                  proposedItem:(id)item
            proposedChildIndex:(NSInteger)index
{
    NSPasteboard *pboard = [info draggingPasteboard];

    if ([self currentRootIsReadOnly])
        return NSDragOperationNone;

    /* internal move: reorder / re-parent inside the playlist tree */
    if ([[pboard types] containsObject:VLCLegacyPlaylistItemPboardType]) {
        /* ⚠ AppKit falls back on "drop ON" (childIndex ==
         * NSOutlineViewDropOnItemIndex) as soon as it refuses to aim at a
         * row -- over the row being dragged, or over a leaf.  On the root
         * (item nil) that reached -moveDraggedItemsInto:atIndex: as "append
         * at the end": the row flew to the BOTTOM of the playlist instead
         * of landing where the pointer was, which read as "dropped above,
         * inserted below".  Retarget the proposal at the real insertion
         * point, the way every other outline behaves.  A genuine node keeps
         * its own "drop inside me" meaning, and so does the empty area
         * below the last row (no row under the pointer). */
        if (index == NSOutlineViewDropOnItemIndex
         && !(item && [item objectForKey:@"children"])) {
            NSPoint loc = [outlineView convertPoint:[info draggingLocation]
                                           fromView:nil];
            NSInteger row = [outlineView rowAtPoint:loc];
            id parentItem = nil;
            NSInteger childIndex = -1;
            if (row >= 0
             && [self locateItem:[outlineView itemAtRow:row]
                         inArray:items
                          parent:nil
                       outParent:&parentItem
                        outIndex:&childIndex]) {
                /* the outline is flipped: past the middle means below */
                NSRect rowRect = [outlineView rectOfRow:row];
                item = parentItem;
                index = childIndex + (loc.y > NSMidY(rowRect) ? 1 : 0);
                [outlineView setDropItem:item dropChildIndex:index];
            }
        }
        /* dropping ON a leaf is meaningless: only nodes hold children */
        if (item && index == NSOutlineViewDropOnItemIndex
         && ![item objectForKey:@"children"])
            return NSDragOperationNone;
        /* refuse to drop a node inside its own subtree */
        unsigned i;
        for (i = 0; i < [draggedItems count]; i++) {
            if ([self item:item isInNode:[draggedItems objectAtIndex:i]])
                return NSDragOperationNone;
        }
        return NSDragOperationMove;
    }
    if ([[pboard types] containsObject:NSFilenamesPboardType])
        return NSDragOperationCopy;
    return NSDragOperationNone;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
         acceptDrop:(id <NSDraggingInfo>)info
               item:(id)item
         childIndex:(NSInteger)index
{
    NSPasteboard *pboard = [info draggingPasteboard];

    if ([self currentRootIsReadOnly])
        return NO;

    if ([[pboard types] containsObject:VLCLegacyPlaylistItemPboardType])
        return [self moveDraggedItemsInto:item atIndex:index];

    NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
    if (![files count])
        return NO;

    /* honour the shown root: when the Media Library is selected, dropping
     * files onto its view must add them to the Media Library, not fall
     * through to the Playlist (playlist_Add always targets p_playing). */
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    BOOL intoML = p_playlist->p_media_library != NULL
               && [self currentRootLocked:p_playlist]
                      == p_playlist->p_media_library;
    playlist_Unlock(p_playlist);
    if (intoML) {
        [self addPaths:files toMediaLibrary:YES];
        return YES;
    }

    [self addPaths:files playFirst:NO];
    return YES;
}

/* Split view: keep the sidebar narrow. CGFloat/NSInteger are REQUIRED
 * here: with float/int the x86_64 ABI mismatches (float return read as
 * double) and the divider jumps off-screen, making the sidebar vanish. */
- (CGFloat)splitView:(NSSplitView *)sender
    constrainMinCoordinate:(CGFloat)proposedMin
               ofSubviewAt:(NSInteger)offset
{
    return 110.0;
}

- (CGFloat)splitView:(NSSplitView *)sender
    constrainMaxCoordinate:(CGFloat)proposedMax
               ofSubviewAt:(NSInteger)offset
{
    return 260.0;
}

- (BOOL)splitView:(NSSplitView *)sender canCollapseSubview:(NSView *)subview
{
    return NO;
}

/* keep the single sidebar column matching the pane width (the badge is
 * pinned to the cell's right edge) */
- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
    [sidebarTable sizeLastColumnToFit];
}

/* taller header rows give each sidebar category some air (3.0 look) */
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
    if (tableView != sidebarTable)
        return [tableView rowHeight];
    if (row > 0 && (unsigned)row < [sidebarItems count]
        && [[[sidebarItems objectAtIndex:row] objectForKey:@"kind"]
               isEqualToString:@"header"])
        return 32.0;
    return 20.0;
}

/* drag & drop of files onto the playlist */
/* copy the dragged rows into the Playlist or Media Library node */
- (BOOL)copyDraggedItemsToRootOfKind:(NSString *)kind
{
    unsigned count = [draggedItems count];
    if (!count)
        return NO;

    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    playlist_item_t *p_node =
        ([kind isEqualToString:@"ml"] && p_playlist->p_media_library)
            ? p_playlist->p_media_library
            : p_playlist->p_playing;
    unsigned i;
    for (i = 0; i < count; i++) {
        playlist_item_t *p_item = playlist_ItemGetById(p_playlist,
            [[[draggedItems objectAtIndex:i] objectForKey:@"id"] intValue]);
        if (p_item)
            playlist_NodeAddCopy(p_playlist, p_item, p_node, PLAYLIST_END);
    }
    playlist_Unlock(p_playlist);

    s_playlistDirty = YES;
    [self rebuildItemsSnapshot];
    return YES;
}

- (BOOL)tableView:(NSTableView *)tableView
       acceptDrop:(id <NSDraggingInfo>)info
              row:(NSInteger)row
    dropOperation:(NSTableViewDropOperation)operation
{
    NSPasteboard *pboard = [info draggingPasteboard];

    /* one of our own rows dropped on a sidebar Playlist / Media Library
     * row: copy the selection into that node */
    if (tableView == sidebarTable
     && [[pboard types] containsObject:VLCLegacyPlaylistItemPboardType]) {
        NSString *kind = @"playlist";
        if (row >= 0 && (unsigned)row < [sidebarItems count])
            kind = [[sidebarItems objectAtIndex:row] objectForKey:@"kind"];
        return [self copyDraggedItemsToRootOfKind:kind];
    }

    NSArray *files = [pboard propertyListForType:NSFilenamesPboardType];
    if (![files count])
        return NO;

    if (tableView == sidebarTable) {
        NSString *kind = @"playlist";
        if (row >= 0 && (unsigned)row < [sidebarItems count])
            kind = [[sidebarItems objectAtIndex:row] objectForKey:@"kind"];
        if ([kind isEqualToString:@"ml"]) {
            [self addPaths:files toMediaLibrary:YES];
            return YES;
        }
        [self addPaths:files playFirst:NO];
        return YES;
    }

    [self addPaths:files playFirst:NO];
    return YES;
}

- (void)addPaths:(NSArray *)paths toMediaLibrary:(BOOL)ml
{
    playlist_t *p_playlist = pl_Get(p_intf);
    unsigned i;
    for (i = 0; i < [paths count]; i++) {
        char *psz_uri = vlc_path2uri([[paths objectAtIndex:i] UTF8String],
                                     "file");
        if (!psz_uri)
            continue;
        input_item_t *p_input = input_item_New(psz_uri, NULL);
        free(psz_uri);
        if (!p_input)
            continue;
        playlist_Lock(p_playlist);
        playlist_item_t *p_root = ml && p_playlist->p_media_library
            ? p_playlist->p_media_library : p_playlist->p_playing;
        playlist_NodeAddInput(p_playlist, p_input, p_root, PLAYLIST_END);
        playlist_Unlock(p_playlist);
        input_item_Release(p_input);
    }
    [self rebuildItemsSnapshot];
}

/*****************************************************************************
 * periodic refresh
 *****************************************************************************/

/* one snapshot dictionary for a playlist item; nodes recurse into
 * "children". Returns nil when the subtree is filtered out by the
 * search string. Must run under the playlist lock. */
- (NSMutableDictionary *)snapshotEntryForItemLocked:(playlist_item_t *)p_item
{
    if (!p_item->p_input)
        return nil;
    BOOL isNode = p_item->i_children >= 0;
    /* directories from the file browsers (My Videos, My Music...) only
     * become nodes once browsed: show their disclosure triangle right
     * away and browse on first expansion */
    BOOL isUnbrowsedDir = !isNode
        && p_item->p_input->i_type == ITEM_TYPE_DIRECTORY;

    char *psz_title = input_item_GetTitleFbName(p_item->p_input);
    NSString *title = psz_title
        ? [NSString stringWithUTF8String:psz_title] : @"";
    free(psz_title);

    NSMutableArray *children = nil;
    if (isNode) {
        children = [NSMutableArray array];
        int i;
        for (i = 0; i < p_item->i_children; i++) {
            NSMutableDictionary *child =
                [self snapshotEntryForItemLocked:p_item->pp_children[i]];
            if (child)
                [children addObject:child];
        }
    }

    if ([searchString length]
     && [VLCLegacyFoldedString(title) rangeOfString:searchStringFolded].location
            == NSNotFound) {
        /* the playing item stays visible even if a live-stream title
         * update made it stop matching the filter */
        playlist_item_t *p_now =
            playlist_CurrentPlayingItem(pl_Get(p_intf));
        BOOL isCurrent = p_now && p_now->i_id == p_item->i_id;
        /* a node stays visible while any descendant matches */
        if (!isCurrent && (!isNode || ![children count]))
            return nil;
    }

    NSMutableDictionary *entry =
        [VLCLegacyPLEntry dictionaryWithObjectsAndKeys:
            [NSNumber numberWithInt:p_item->i_id], @"id",
            title, @"title",
            nil];
    if (isUnbrowsedDir) {
        [entry setObject:[NSMutableArray array] forKey:@"children"];
        [entry setObject:[NSNumber numberWithBool:YES] forKey:@"browse"];
        return entry;
    }
    if (children) {
        [entry setObject:children forKey:@"children"];
        return entry;   /* 3.0 leaves the value columns empty on nodes */
    }

    NSString *duration =
        timeToString(input_item_GetDuration(p_item->p_input));
    [entry setObject:duration forKey:@"duration"];
    char *psz_art = input_item_GetArtworkURL(p_item->p_input);
    if (psz_art) {
        NSString *artUrl = [NSString stringWithUTF8String:psz_art];
        if (artUrl)
            [entry setObject:artUrl forKey:@"arturl"];
        free(psz_art);
    }

    /* extra columns (View > Playlist Table Columns); every string
     * is checked: invalid UTF-8 would make stringWithUTF8String
     * return nil and setObject:forKey: throw */
    char *psz_value;
    NSString *value;
#define META_FIELD(getter, key) \
    do { \
        psz_value = getter(p_item->p_input); \
        value = psz_value && *psz_value \
            ? [NSString stringWithUTF8String:psz_value] : nil; \
        if (value) \
            [entry setObject:value forKey:key]; \
        free(psz_value); \
    } while (0)
    META_FIELD(input_item_GetTrackNum, @"tracknumber");
    META_FIELD(input_item_GetArtist, @"author");
    META_FIELD(input_item_GetGenre, @"genre");
    META_FIELD(input_item_GetAlbum, @"album");
    META_FIELD(input_item_GetDescription, @"description");
    META_FIELD(input_item_GetDate, @"date");
    META_FIELD(input_item_GetLanguage, @"language");
#undef META_FIELD
    psz_value = input_item_GetURI(p_item->p_input);
    if (psz_value) {
        char *psz_path = vlc_uri2path(psz_value);
        if (psz_path) {
            value = [NSString stringWithUTF8String:psz_path];
            if (value)
                [entry setObject:value forKey:@"path"];
            free(psz_path);
        }
        vlc_uri_decode(psz_value);
        value = [NSString stringWithUTF8String:psz_value];
        if (value)
            [entry setObject:value forKey:@"uri"];
        free(psz_value);
    }
    return entry;
}

/* re-open the nodes the user had expanded, walking parents first */
- (void)restoreExpandedInArray:(NSArray *)array
{
    unsigned i;
    for (i = 0; i < [array count]; i++) {
        NSDictionary *entry = [array objectAtIndex:i];
        NSArray *children = [entry objectForKey:@"children"];
        if (!children)
            continue;
        if ([expandedItemIds containsObject:[entry objectForKey:@"id"]])
            [playlistTable expandItem:entry];
        [self restoreExpandedInArray:children];
    }
}

- (void)restoreExpandedItems
{
    [self restoreExpandedInArray:items];
}

- (void)outlineViewItemDidExpand:(NSNotification *)notification
{
    NSDictionary *entry =
        [[notification userInfo] objectForKey:@"NSObject"];
    NSNumber *itemId = [entry objectForKey:@"id"];
    if (!itemId)
        return;
    [expandedItemIds addObject:itemId];

    /* expanding an unbrowsed directory sends it to the preparser: its
     * subitems attach to the playlist item and the next snapshot shows
     * them (the expanded state is kept by id across reloads).  A
     * directory still childless once its request is surely over (failed
     * fetch) can be retried by folding and unfolding it again. */
    if ([[entry objectForKey:@"browse"] boolValue]) {
        NSDate *lastRequest = [browseRequestedIds objectForKey:itemId];
        if (lastRequest && [lastRequest timeIntervalSinceNow] > -150.0)
            return;
        playlist_t *p_playlist = pl_Get(p_intf);
        playlist_Lock(p_playlist);
        playlist_item_t *p_item =
            playlist_ItemGetById(p_playlist, [itemId intValue]);
        /* i_children on the core item: the view may just be filtering
         * everything out, which is no reason to fetch again */
        if (p_item && p_item->p_input && p_item->i_children <= 0) {
            [browseRequestedIds setObject:[NSDate date] forKey:itemId];
            /* the network scope is required for on-line directories
             * (radio directory countries...), else the preparser
             * silently skips them; the timeout keeps a wedged fetch
             * from blocking the (serial) preparser forever */
            libvlc_MetadataRequest(p_playlist->obj.libvlc,
                                   p_item->p_input,
                                   META_REQUEST_OPTION_SCOPE_ANY,
                                   120000, p_item);
        }
        playlist_Unlock(p_playlist);
    }
}

- (void)outlineViewItemDidCollapse:(NSNotification *)notification
{
    NSNumber *itemId = [[[notification userInfo] objectForKey:@"NSObject"]
        objectForKey:@"id"];
    if (itemId)
        [expandedItemIds removeObject:itemId];
}

/* the 3.0 sidebar badges: number of children of the Playlist and Media
 * Library nodes, shown only when > 0. Must run under the playlist lock. */
- (void)updateSidebarBadgesLocked:(playlist_t *)p_playlist
{
    BOOL changed = NO;
    unsigned i;
    for (i = 0; i < [sidebarItems count]; i++) {
        NSMutableDictionary *entry = [sidebarItems objectAtIndex:i];
        NSString *kind = [entry objectForKey:@"kind"];
        playlist_item_t *p_node = NULL;
        if ([kind isEqualToString:@"playlist"])
            p_node = p_playlist->p_playing;
        else if ([kind isEqualToString:@"ml"])
            p_node = p_playlist->p_media_library;
        if (!p_node)
            continue;
        int count = p_node->i_children > 0 ? p_node->i_children : 0;
        if ([[entry objectForKey:@"badge"] intValue] != count) {
            [entry setObject:[NSNumber numberWithInt:count]
                      forKey:@"badge"];
            changed = YES;
        }
    }
    if (changed)
        [sidebarTable setNeedsDisplay:YES];
}

/* Directories reach the playlist as plain leaves until they are read
 * (their input type only becomes DIRECTORY once browsed): detect them
 * with a cached stat OUTSIDE the playlist lock so their disclosure
 * triangle shows right away (My Videos/My Music/My Pictures browsing) */
- (void)markBrowsableDirsInArray:(NSArray *)array
{
    unsigned i;
    for (i = 0; i < [array count]; i++) {
        NSMutableDictionary *entry = [array objectAtIndex:i];
        NSArray *children = [entry objectForKey:@"children"];
        if (children) {
            [self markBrowsableDirsInArray:children];
            continue;
        }
        NSString *path = [entry objectForKey:@"path"];
        if (![path length])
            continue;
        NSNumber *isDir = [dirCheckCache objectForKey:path];
        if (!isDir) {
            BOOL b = NO;
            [[NSFileManager defaultManager] fileExistsAtPath:path
                                               isDirectory:&b];
            isDir = [NSNumber numberWithBool:b];
            [dirCheckCache setObject:isDir forKey:path];
        }
        if ([isDir boolValue]) {
            [entry setObject:[NSMutableArray array] forKey:@"children"];
            [entry setObject:[NSNumber numberWithBool:YES]
                      forKey:@"browse"];
        }
    }
}

/* header title of the item list: selected view name, with the total
 * duration of the node appended for the playlist and the media library,
 * exactly like the modern interface (" — H:MM:SS", days first if any) */
- (void)updateViewTitleWithDuration:(int64_t)duration
{
    NSString *title = nil;
    if (sidebarSelection >= 0
        && (unsigned)sidebarSelection < [sidebarItems count])
        title = [[sidebarItems objectAtIndex:sidebarSelection]
                    objectForKey:@"title"];
    if (!title)
        title = _NS("Playlist");

    if (duration >= CLOCK_FREQ) {
        int64_t total = duration / CLOCK_FREQ;
        int sec = (int)(total % 60);
        int min = (int)((total % 3600) / 60);
        int hours = (int)((total % 86400) / 3600);
        int days = (int)(total / 86400);
        NSString *timeString;
        if (days > 0)
            timeString = [NSString stringWithFormat:@"%i:%i:%02i:%02i",
                          days, hours, min, sec];
        else
            timeString = [NSString stringWithFormat:@"%i:%02i:%02i",
                          hours, min, sec];
        /* em dash through UTF-8 explicitly: 10.2's Foundation reads
         * high-bit bytes of CONSTANT strings as MacRoman (",Äî") */
        title = [NSString stringWithFormat:@"%@%@%@", title,
                 [NSString stringWithUTF8String:" \xE2\x80\x94 "],
                 timeString];
    }

    if (![[viewTitleLabel stringValue] isEqualToString:title])
        [viewTitleLabel setStringValue:title];
}

- (void)rebuildItemsSnapshot
{
    NSMutableArray *fresh = [NSMutableArray array];
    playlist_t *p_playlist = pl_Get(p_intf);

    /* changes signalled during the rebuild keep the flag armed */
    s_playlistDirty = NO;

    playlist_Lock(p_playlist);
    playlist_item_t *p_current = playlist_CurrentPlayingItem(p_playlist);
    int newCurrentId = p_current ? p_current->i_id : -1;
    playlist_item_t *p_root = [self currentRootLocked:p_playlist];
    if (p_root) {
        int i;
        /* keep the core-side search flags in sync with the display filter:
         * on a dead stream the playlist advances through the leaves the
         * core considers enabled, so without these flags it would fall
         * back on items the filter hides.  Re-run on every rebuild so
         * items appended after the search (radio directory still loading)
         * are filtered too. */
        if ([searchString length]) {
            /* the core folds the needle itself, feed it the raw string */
            playlist_LiveSearchUpdate(p_playlist, p_root,
                                      [searchString UTF8String], true);
            searchFlagsWereSet = YES;
            /* the playing item must stay in the playback set even if a
             * live-stream title update made it stop matching */
            if (p_current)
                p_current->i_flags &= ~PLAYLIST_DBL_FLAG;
        } else if (searchFlagsWereSet) {
            playlist_LiveSearchUpdate(p_playlist, p_root, "", true);
            searchFlagsWereSet = NO;
        }
        for (i = 0; i < p_root->i_children; i++) {
            NSMutableDictionary *entry = [self
                snapshotEntryForItemLocked:p_root->pp_children[i]];
            if (entry)
                [fresh addObject:entry];
        }
    }
    [self updateSidebarBadgesLocked:p_playlist];
    /* total duration for the header, playlist and media library only
     * (parity with the modern interface) */
    int64_t headerDuration = 0;
    if (p_root && (p_root == p_playlist->p_playing
                   || p_root == p_playlist->p_media_library))
        headerDuration = playlist_GetNodeDuration(p_root);
    playlist_Unlock(p_playlist);

    [self updateViewTitleWithDuration:headerDuration];
    [self markBrowsableDirsInArray:fresh];

    /* the playing item is shown bold, so its change needs a redraw too */
    BOOL currentChanged = newCurrentId != currentItemId;
    currentItemId = newCurrentId;

    /* a reload rebuilds pointer-identity rows: keep the selection by
     * playlist id, like the expanded state, or every keyboard-driven
     * expand/play would drop it */
    NSMutableSet *selectedIds = [NSMutableSet set];
    NSArray *selectedRows = VLCLegacySelectedRows(playlistTable);
    unsigned s;
    for (s = 0; s < [selectedRows count]; s++) {
        id row = [playlistTable itemAtRow:
                     [[selectedRows objectAtIndex:s] intValue]];
        NSNumber *ident = [row objectForKey:@"id"];
        if (ident)
            [selectedIds addObject:ident];
    }

    BOOL reloaded = NO;
    if (!VLCLegacySnapshotRowsEqual(fresh, items)) {
        /* between reloadData (rows are fresh pointer-identity objects,
         * so everything momentarily folds and the scrollers clamp to
         * the top) and restoreExpandedItems, the scroll position is
         * lost: put it back once the tree has its final shape */
        NSRect visible = [playlistTable visibleRect];
        [items setArray:fresh];
        [playlistTable reloadData];
        [self restoreExpandedItems];
        [playlistTable scrollPoint:visible.origin];
        reloaded = YES;
    } else if (currentChanged) {
        [playlistTable reloadData];
        reloaded = YES;
    }

    if (reloaded && [selectedIds count]) {
        int r, rowCount = (int)[playlistTable numberOfRows];
        BOOL extend = NO;
        for (r = 0; r < rowCount; r++) {
            NSNumber *ident =
                [[playlistTable itemAtRow:r] objectForKey:@"id"];
            if (ident && [selectedIds containsObject:ident]) {
                VLCLegacyExtendSelectRow(playlistTable, r, extend);
                extend = YES;
            }
        }
    }

    /* the dropzone only makes sense on the (empty) playlist view */
    BOOL isPlaylistView = sidebarSelection >= 0
        && (unsigned)sidebarSelection < [sidebarItems count]
        && [[[sidebarItems objectAtIndex:sidebarSelection]
                objectForKey:@"kind"] isEqualToString:@"playlist"];
    BOOL showDropzone = [items count] == 0 && isPlaylistView
                     && ![searchString length];
    VLCLegacySetViewHidden(dropzoneView, !showDropzone);
    VLCLegacySetViewHidden(playlistScroll, showDropzone);
}

/* cover art of the playing item at the bottom of the sidebar (the same
 * presentation as the Qt interface); "noart" placeholder otherwise */
- (void)updateSidebarArtForInput:(input_thread_t *)p_input
{
    NSString *artUrl = @"";
    if (p_input) {
        char *psz_art = input_item_GetArtworkURL(input_GetItem(p_input));
        if (psz_art) {
            NSString *s = [NSString stringWithUTF8String:psz_art];
            if (s)
                artUrl = s;
            free(psz_art);
        }
    }
    if (sidebarArtUrl && [artUrl isEqualToString:sidebarArtUrl])
        return;
    [sidebarArtUrl release];
    sidebarArtUrl = [artUrl retain];

    NSImage *art = nil;
    if ([artUrl length]) {
        art = [artworkCache objectForKey:artUrl];
        if (!art) {
            char *psz_path = vlc_uri2path([artUrl UTF8String]);
            if (psz_path) {
                art = [[[NSImage alloc] initWithContentsOfFile:
                    [NSString stringWithUTF8String:psz_path]] autorelease];
                free(psz_path);
            }
            if (!art)
                art = (NSImage *)[NSNull null];
            [artworkCache setObject:art forKey:artUrl];
        }
        if (art == (NSImage *)[NSNull null])
            art = nil;
    }
    [sidebarArtView setImage:art ? art : VLCLegacyImage(@"noart")];
}

- (void)refresh:(NSTimer *)timer
{
    playlist_t *p_playlist = pl_Get(p_intf);

    /* transport state */
    playlist_Lock(p_playlist);
    int status = playlist_Status(p_playlist);
    playlist_Unlock(p_playlist);
    BOOL nowPlaying = (status == PLAYLIST_RUNNING);

    [self updateAutoHideControls];
    if (nowPlaying != playing) {
        playing = nowPlaying;
        NSString *base = playing
            ? themedImage(@"pause", @"pause_dark")
            : themedImage(@"play", @"play_dark");
        NSString *pressed = playing
            ? themedImage(@"pause-pressed", @"pause-pressed_dark")
            : themedImage(@"play-pressed", @"play-pressed_dark");
        [playButton setImage:
            VLCLegacyImageSized(base, NSMakeSize(27, 23))];
        [playButton setAlternateImage:
            VLCLegacyImageSized(pressed, NSMakeSize(27, 23))];
    }

    /* shuffle/repeat artwork tracks the playlist state (3.0 look) */
    if (!VLCLegacyViewIsHidden(shuffleButton)) {
        BOOL shuffleOn = [core playlistBool:"random"];
        if (shuffleOn != lastShuffleOn) {
            lastShuffleOn = shuffleOn;
            [shuffleButton setImage:VLCLegacyImageSized(shuffleOn
                ? themedImage(@"shuffle-blue", @"shuffle-blue_dark")
                : themedImage(@"shuffle", @"shuffle_dark"),
                NSMakeSize(29, 23))];
            [shuffleButton setAlternateImage:VLCLegacyImageSized(shuffleOn
                ? themedImage(@"shuffle-blue-pressed",
                              @"shuffle-blue-pressed_dark")
                : themedImage(@"shuffle-pressed", @"shuffle-pressed_dark"),
                NSMakeSize(29, 23))];
        }
        int repeatState = [core playlistBool:"loop"] ? 1
                        : ([core playlistBool:"repeat"] ? 2 : 0);
        if (repeatState != lastRepeatState) {
            lastRepeatState = repeatState;
            NSString *base, *pressed;
            if (repeatState == 1) {
                base = themedImage(@"repeat-all", @"repeat-all-blue_dark");
                pressed = themedImage(@"repeat-all-pressed",
                                      @"repeat-all-blue-pressed_dark");
            } else if (repeatState == 2) {
                base = themedImage(@"repeat-one", @"repeat-one-blue_dark");
                pressed = themedImage(@"repeat-one-pressed",
                                      @"repeat-one-blue-pressed_dark");
            } else {
                base = themedImage(@"repeat", @"repeat_dark");
                pressed = themedImage(@"repeat-pressed",
                                      @"repeat-pressed_dark");
            }
            [repeatButton setImage:
                VLCLegacyImageSized(base, NSMakeSize(28, 23))];
            [repeatButton setAlternateImage:
                VLCLegacyImageSized(pressed, NSMakeSize(28, 23))];
        }
    }

    /* time / position; the window title shows the current item (3.0) */
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (p_input) {
        /* follow input-title-format like Qt and the 3.0 interface do: its
         * default ($Z) puts "now playing" first, so a stream whose track
         * changes under it (webradio ICY metadata) is readable at a glance
         * instead of only in the media information panel */
        char *psz_title = NULL;
        char *psz_format = var_InheritString(p_intf, "input-title-format");
        if (psz_format) {
            psz_title = vlc_strfinput(p_input, psz_format);
            free(psz_format);
        }
        if (!psz_title || !*psz_title) {
            free(psz_title);
            psz_title = input_item_GetTitleFbName(input_GetItem(p_input));
        }
        if (psz_title) {
            NSString *title =
                [NSString stringWithUTF8String:psz_title];
            free(psz_title);
            if ([title length] && ![[window title] isEqualToString:title])
                [window setTitle:title];
            /* « Afficher la vidéo dans la fenêtre principale » décochée : la
             * fenêtre vidéo autonome porte le même titre (c'est ici, et non à
             * sa création, que le format input-title-format est composé). */
            {
                NSWindow *voutWindow = VLCLegacyCurrentVoutWindow();
                if (voutWindow != nil && [title length]
                 && ![[voutWindow title] isEqualToString:title])
                    [voutWindow setTitle:title];
            }
        }
        int64_t i_time = var_GetInteger(p_input, "time");
        int64_t i_length = var_GetInteger(p_input, "length");
        NSString *timeString;
        if (showTimeRemaining && i_length > 0) {
            int64_t remaining = i_length - i_time;
            if (remaining < 0)
                remaining = 0;
            timeString = [NSString stringWithFormat:@"-%@",
                          timeToString(remaining)];
        } else
            timeString = timeToString(i_time);
        [self setField:durationField toString:timeString];
        float position = var_GetFloat(p_input, "position");
        [(VLCLegacySeekSlider *)seekSlider
            setMediaDuration:(double)i_length / CLOCK_FREQ];
        [self updateChaptersForInput:p_input duration:i_length];
        VLCLegacyProgressSliderCell *clipCell =
            (VLCLegacyProgressSliderCell *)[seekSlider cell];
        if ([core clipCreationMode]) {
            /* the knobs hold the clip bounds; only the thin marker
             * follows the playback position */
            if (![clipCell clipKnobsActive])
                [clipCell setClipKnobsActive:YES];
            [seekSlider setDoubleValue:[core clipStartPosition]];
            [clipCell setClipEndValue:[core clipEndPosition]];
            [clipCell setPlaybackMarkerValue:position];
            [seekSlider setNeedsDisplay:YES];
        } else {
        if ([clipCell clipKnobsActive]) {
            [clipCell setClipKnobsActive:NO];
            [seekSlider setNeedsDisplay:YES];
        }
        /* setFloatValue: repaints the whole slider (gradient track,
         * bezier knob) plus the bar strip behind it, but on long media
         * the 0.3 s poll advances the position by far less than a pixel
         * of knob travel (a 2 h DVD moves the knob one pixel every
         * ~18 s on a 400 px slider).  Only push values that move the
         * knob visibly: skip deltas below one pixel of the range.
         * Jumps (chapter change, seek from menu/hotkey, item change)
         * are way above the threshold and still update instantly. */
        float sliderWidth = [seekSlider frame].size.width;
        if (sliderWidth < 300.f)
            sliderWidth = 300.f;
        float delta = [seekSlider floatValue] - position;
        if (delta < 0.f)
            delta = -delta;
        if (delta >= 1.0f / sliderWidth)
            [seekSlider setFloatValue:position];
        }
        BOOL canSeek = var_GetBool(p_input, "can-seek") ? YES : NO;
        if ([seekSlider isEnabled] != canSeek)
            [seekSlider setEnabled:canSeek];

        /* 3.0 (VLCControlsBarCommon updateTimeSlider) only animates the
         * buffering bar while the input is opening ("cache" is not a
         * buffering indicator: live streams keep refilling it forever).
         * NSControl does not repaint when only a cell flag changes, so
         * invalidate on transitions or the last animation frame stays
         * painted on inputs whose position never moves (radios). */
        int state = (int)var_GetInteger(p_input, "state");
        BOOL buffering = state == INIT_S || state == OPENING_S;
        VLCLegacyProgressSliderCell *seekCell =
            (VLCLegacyProgressSliderCell *)[seekSlider cell];
        if ([seekCell indefinite] != buffering || buffering) {
            [seekCell setIndefinite:buffering];
            [seekSlider setNeedsDisplay:YES];
        }
        [self trackResumeForInput:p_input];
        [self updateSidebarArtForInput:p_input];
        /* clip creation mode: leave it on item change/end, pause at the
         * end bound, follow a core-side end of the recording */
        [core updateClipModeForInput:p_input];
        vlc_object_release(p_input);
    } else {
        [core updateClipModeForInput:NULL];
        [(VLCLegacySeekSlider *)seekSlider setMediaDuration:0.0];
        [self updateChaptersForInput:NULL duration:0];
        [self trackResumeForInput:NULL];
        [self updateSidebarArtForInput:NULL];
        if (![[window title] isEqualToString:VLCLegacyDefaultWindowTitle()])
            [window setTitle:VLCLegacyDefaultWindowTitle()];
        [self setField:durationField toString:@"00:00"];
        if ([seekSlider floatValue] != 0.f)
            [seekSlider setFloatValue:0.f];
        if ([seekSlider isEnabled])
            [seekSlider setEnabled:NO];
        VLCLegacyProgressSliderCell *seekCell =
            (VLCLegacyProgressSliderCell *)[seekSlider cell];
        if ([seekCell indefinite]) {
            [seekCell setIndefinite:NO];
            [seekSlider setNeedsDisplay:YES];
        }
        /* Stop leaves NO input, so the branch above -- the only place that
         * puts the clip knobs away -- never runs: the seek bar kept its two
         * knobs while -updateClipModeForInput: had already left the mode and
         * the menu had gone back to "Enter Clip Creation Mode". */
        if ([seekCell clipKnobsActive]) {
            [seekCell setClipKnobsActive:NO];
            [seekSlider setNeedsDisplay:YES];
        }
    }

    /* keep an active A->B loop looping (level-polled, like 3.0) */
    [core updateAtoB];

    /* volume may have been changed from menus/hotkeys (display clamps
     * at the 125% end of the slider) */
    float volume = [core volume];
    if (volume > 1.25f)
        volume = 1.25f;
    if (volume >= 0.f && [volumeSlider floatValue] != volume)
        [volumeSlider setFloatValue:volume];

    /* The snapshot rebuild walks the whole playlist; only do it when a
     * playlist callback reported a change (plus a low-frequency safety
     * pass), so a paused or idle player stays quiet. Bursts (a service
     * discovery adding thousands of stations one by one) are coalesced:
     * wait for two quiet ticks before reloading, with a 3 s cap so a
     * very long burst still shows progress. */
    if (s_playlistDirty) {
        int changeCount = s_playlistChangeCounter;
        BOOL stillChurning = changeCount != lastSeenChangeCount;
        lastSeenChangeCount = changeCount;
        burstTicks++;
        if ((!stillChurning && burstTicks >= 2) || burstTicks >= 10) {
            burstTicks = 0;
            refreshTicks = 0;
            [self rebuildItemsSnapshot];
        }
    } else if (++refreshTicks >= 17) {
        burstTicks = 0;
        refreshTicks = 0;
        [self rebuildItemsSnapshot];
    }
}

/*****************************************************************************
 * "Continue playback where you left off" (VLC 3.0 parity)
 * Same NSUserDefaults keys as VLCInputManager: recentlyPlayedMedia
 * (uri -> seconds) and recentlyPlayedMediaList (30 most recent uris).
 *****************************************************************************/

#define RESUME_DICT_KEY @"recentlyPlayedMedia"
#define RESUME_LIST_KEY @"recentlyPlayedMediaList"

/* commit the last observed position of the tracked input to the defaults;
 * positions near the edges clear the entry instead (3.0 heuristics) */
- (void)storeResumePosition
{
    if (!resumeTrackedURI)
        return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    if ([defaults dictionaryForKey:RESUME_DICT_KEY])
        [dict addEntriesFromDictionary:
            [defaults dictionaryForKey:RESUME_DICT_KEY]];
    NSMutableArray *list = [NSMutableArray array];
    if ([defaults arrayForKey:RESUME_LIST_KEY])
        [list addObjectsFromArray:[defaults arrayForKey:RESUME_LIST_KEY]];

    if (resumeLastLength >= (int64_t)180 * CLOCK_FREQ
     && resumeLastTime >= (int64_t)60 * CLOCK_FREQ
     && resumeLastTime <= resumeLastLength - (int64_t)60 * CLOCK_FREQ) {
        [dict setObject:
            [NSNumber numberWithInt:(int)(resumeLastTime / CLOCK_FREQ)]
                 forKey:resumeTrackedURI];
        [list removeObject:resumeTrackedURI];
        [list addObject:resumeTrackedURI];
        while ([list count] > 30) {
            [dict removeObjectForKey:[list objectAtIndex:0]];
            [list removeObjectAtIndex:0];
        }
    } else {
        [dict removeObjectForKey:resumeTrackedURI];
        [list removeObject:resumeTrackedURI];
    }
    [defaults setObject:dict forKey:RESUME_DICT_KEY];
    [defaults setObject:list forKey:RESUME_LIST_KEY];
    /* called at stop/quit: flush now, the old-OS exit path does not
     * reliably run the lazy CFPreferences write-back */
    [defaults synchronize];
}

- (void)trackResumeForInput:(input_thread_t *)p_input
{
    if (!p_input) {
        if (resumeTrackedURI) {
            [self storeResumePosition];
            [resumeTrackedURI release];
            resumeTrackedURI = nil;
        }
        return;
    }

    char *psz_uri = input_item_GetURI(input_GetItem(p_input));
    if (!psz_uri)
        return;
    NSString *uri = [NSString stringWithUTF8String:psz_uri];
    free(psz_uri);

    if (!resumeTrackedURI || ![resumeTrackedURI isEqualToString:uri]) {
        [self storeResumePosition];
        [resumeTrackedURI release];
        resumeTrackedURI = [uri retain];
        resumeHandled = NO;
        resumeLastTime = 0;
        resumeLastLength = 0;
    }

    resumeLastTime = var_GetInteger(p_input, "time");
    resumeLastLength = var_GetInteger(p_input, "length");

    if (resumeHandled || resumeLastLength <= 0)
        return;
    resumeHandled = YES;

    int setting = (int)var_InheritInteger(p_intf,
        "legacy-macosx-continue-playback");
    if (setting == 2 /* Never */)
        return;
    NSNumber *stored = [[[NSUserDefaults standardUserDefaults]
        dictionaryForKey:RESUME_DICT_KEY] objectForKey:uri];
    if (!stored || [stored intValue] <= 0)
        return;
    int64_t i_target = (int64_t)[stored intValue] * CLOCK_FREQ;
    if (i_target >= resumeLastLength)
        return;

    if (setting == 0 /* Ask */) {
        char *psz_title =
            input_item_GetTitleFbName(input_GetItem(p_input));
        NSString *name = psz_title
            ? [NSString stringWithUTF8String:psz_title] : uri;
        free(psz_title);
        /* the input keeps playing behind the panel, like the 3.0
         * non-blocking resume dialog */
        int ret = NSRunAlertPanel(_NS("Continue playback?"),
            [NSString stringWithFormat:
                _NS("Playback of \"%@\" will continue at %@"),
                name, timeToString(i_target)],
            _NS("Continue"), _NS("Restart playback"), nil);
        if (ret != NSAlertDefaultReturn)
            return;
    }
    var_SetInteger(p_input, "time", i_target);
}

/*****************************************************************************
 * Chantier F — la fenêtre hôte de la vidéo suit la fenêtre principale
 *****************************************************************************
 * Les fenêtres enfants suivent les déplacements du parent toutes seules, mais
 * PAS ses redimensionnements ; et elles ne se miniaturisent pas avec lui (elle
 * resterait affichée seule à l'écran). D'où ces quatre notifications.
 *****************************************************************************/

/* While the controls are auto-hidden the window IS the picture: keep it
 * exactly that when the user resizes it, otherwise black bands come back
 * inside the bare window the feature exists to get rid of. Outside that
 * state the window resizes freely and the vout letterboxes, as always. */
/* ⚠ Only the USER reaches this: -setFrame: does not consult the delegate.
 * That is what makes it the right place to record the box a later crop
 * fits into -- windowDidResize: fires on our own resizes too, and the
 * box would follow every crop instead of only the user. */
- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)proposedSize
{
    if (sender != window)
        return proposedSize;

    if (!controlsHiddenForPlayback) {
        if (videoActive && !VLCLegacyViewIsHidden(videoView)) {
            /* the proposed size is a FRAME: the title bar comes off with
             * the content rect, the controls bar by hand */
            NSRect content = VLCLegacyContentRectForFrameRect(window,
                NSMakeRect(0, 0, proposedSize.width, proposedSize.height));
            pictureBox = NSMakeSize(content.size.width,
                                    content.size.height - BOTTOM_BAR_HEIGHT);
        }
        return proposedSize;
    }

    if (lastNativeVideoSize.width <= 0. || lastNativeVideoSize.height <= 0.)
        return proposedSize;

    proposedSize.height = (float)floor(proposedSize.width
        * lastNativeVideoSize.height / lastNativeVideoSize.width + 0.5);
    return proposedSize;
}

- (void)windowDidResize:(NSNotification *)notification
{
    if ([notification object] != window)
        return;
    [self syncVideoHostFrame];
    /* the hidden window has no controls bar to leave room for */
    if (controlsHiddenForPlayback)
        [self layoutVideoZoneForHiddenControls];
}

- (void)windowDidMove:(NSNotification *)notification
{
    if ([notification object] == window)
        [self syncVideoHostFrame];
}

/*****************************************************************************
 * Pause the video playback when minimized (VLC 3.0 parity)
 *****************************************************************************/

- (void)windowDidMiniaturize:(NSNotification *)notification
{
    if ([notification object] != window)
        return;
    /* Une fenêtre enfant ne se miniaturise pas avec son parent : la retirer,
     * sinon la vidéo reste seule à l'écran, fenêtre principale rangée. */
    if (videoHostWindow && !videoHostFullscreen) {
        [[videoHostWindow parentWindow] removeChildWindow:videoHostWindow];
        [videoHostWindow orderOut:nil];
    }
    if (!var_InheritBool(p_intf, "legacy-macosx-pause-minimized"))
        return;
    if (videoActive && playing) {
        [core togglePlayPause];
        pausedByMiniaturize = YES;
    }
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
    if ([notification object] != window)
        return;
    if (videoHostWindow && !videoHostFullscreen
     && [videoHostWindow parentWindow] == nil) {
        [window addChildWindow:videoHostWindow ordered:NSWindowAbove];
        [self syncVideoHostFrame];
    }
    if (!pausedByMiniaturize)
        return;
    pausedByMiniaturize = NO;
    if (!playing)
        [core togglePlayPause];
}

/* NSControl redraws on every setStringValue:, even an identical one */
- (void)setField:(NSTextField *)field toString:(NSString *)string
{
    if (![[field stringValue] isEqualToString:string])
        [field setStringValue:string];
}

/* activation rules of -[VLCPlaylist validateMenuItem:] (3.0) */
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL action = [item action];
    BOOL hasSelection = [playlistTable numberOfSelectedRows] > 0
                     || [playlistTable clickedRow] >= 0;

    if (action == @selector(recursiveExpandOrCollapseNode:)) {
        /* only meaningful when the current view has at least one node */
        unsigned i;
        for (i = 0; i < [items count]; i++)
            if ([[items objectAtIndex:i] objectForKey:@"children"])
                return YES;
        return NO;
    }
    if (action == @selector(playSelectedItem:)
     || action == @selector(deleteSelectedItems:)
     || action == @selector(showItemInfo:))
        return hasSelection;
    if (action == @selector(revealItemInFinder:)) {
        int row = (int)[playlistTable clickedRow];
        if (row < 0)
            row = (int)[playlistTable selectedRow];
        NSDictionary *entry =
            row >= 0 ? [playlistTable itemAtRow:row] : nil;
        return [[entry objectForKey:@"path"] length] > 0;
    }
    if (action == @selector(selectAllItems:))
        return [items count] > 0;
    if (action == @selector(shufflePlaylist:)) {
        if (![items count])
            return NO;
        /* the media library must not be shuffled, like 3.0 */
        playlist_t *p_playlist = pl_Get(p_intf);
        playlist_Lock(p_playlist);
        playlist_item_t *p_root = [self currentRootLocked:p_playlist];
        BOOL isML = p_root == p_playlist->p_media_library;
        playlist_Unlock(p_playlist);
        return !isML;
    }
    return YES;
}

@end
