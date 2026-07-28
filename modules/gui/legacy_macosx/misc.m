/*****************************************************************************
 * misc.m: custom code
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

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "misc.h"
/* <objc/message.h> is a 10.5+ SDK split; the 10.4u SDK declares
 * objc_msgSend in <objc/objc-runtime.h> */
#if defined(__has_include)
# if __has_include(<objc/message.h>)
#  import <objc/message.h>
# else
#  import <objc/objc-runtime.h>
# endif
#else
# import <objc/objc-runtime.h>
#endif

#include <math.h>

#include <vlc_playlist.h>
#include <vlc_input.h>
#include <vlc_vout.h>
#include <vlc_vout_osd.h>
#include <vlc_actions.h>
#include <vlc_modules.h>
#include <vlc_plugin.h>    /* CONFIG_ITEM_KEY */

#import "VLCLegacyControls.h"   /* VLCLegacyDarkMode() */

/* PowerVLC: same gettext helper the other legacy files define locally */
#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

BOOL VLCLegacyOSVersionAtLeast(int major, int minor, int micro)
{
    static int s_version[3] = { -1, 0, 0 };
    if (s_version[0] < 0) {
        int a = 0, b = 0, c = 0;
        NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:
            @"/System/Library/CoreServices/SystemVersion.plist"];
        NSString *product = [dict objectForKey:@"ProductVersion"];
        if (product)
            sscanf([product UTF8String], "%d.%d.%d", &a, &b, &c);
        s_version[0] = a;
        s_version[1] = b;
        s_version[2] = c;
    }
    if (s_version[0] != major)
        return s_version[0] > major;
    if (s_version[1] != minor)
        return s_version[1] > minor;
    return s_version[2] >= micro;
}

void VLCLegacyEnableLayerBackingIfModern(NSView *view)
{
    if (!VLCLegacyOSVersionAtLeast(10, 14, 0)
     || ![view respondsToSelector:@selector(setWantsLayer:)])
        return;
    /* typed objc_msgSend call: the selector takes a BOOL, which
     * -performSelector: cannot carry */
    void (*setWantsLayer)(id, SEL, BOOL) =
        (void (*)(id, SEL, BOOL))objc_msgSend;
    setWantsLayer(view, @selector(setWantsLayer:), YES);
}

/* 10.7+; the constant does not exist in the 10.4u/10.5 SDKs the PowerPC
 * and 32-bit Intel targets build against */
#ifndef NSWindowCollectionBehaviorFullScreenNone
# define NSWindowCollectionBehaviorFullScreenNone (1 << 9)
#endif

void VLCLegacyDenyNativeFullscreen(NSWindow *window)
{
    if (!window
     || ![window respondsToSelector:@selector(setCollectionBehavior:)])
        return;
    /* typed objc_msgSend call: -setCollectionBehavior: takes a scalar
     * mask, which -performSelector: cannot carry, and the selector is
     * absent from the old SDKs so it cannot be sent literally either */
    void (*setBehavior)(id, SEL, NSUInteger) =
        (void (*)(id, SEL, NSUInteger))objc_msgSend;
    setBehavior(window, @selector(setCollectionBehavior:),
                (NSUInteger)NSWindowCollectionBehaviorFullScreenNone);
}

void VLCLegacyRelaunchApplication(void)
{
    NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:@"/bin/sh"];
    /* the bundle path travels as $0 of the shell, immune to quoting */
    [task setArguments:[NSArray arrayWithObjects:@"-c",
        @"sleep 1; exec /usr/bin/open -n \"$0\"", bundlePath, nil]];
    @try {
        [task launch];
    } @catch (NSException *e) {
    }
}

/* The volume always lands on the multiple of 5% nearest to the current
 * value in the direction of the change (89% + up = 90%, 89% + down =
 * 85%, 90% + up = 95%). The core hotkey handler cannot provide that
 * (aout_VolumeUpdate adds one step THEN rounds to the nearest multiple,
 * jumping two multiples from an intermediate value), so every volume
 * path of the interface goes through here instead. b_osd replicates
 * hotkeys.c DisplayVolume for the mouse wheel: vertical bar on its own
 * SPU channel in fullscreen, text on the shared OSD channel. */
void VLCLegacyStepVolume(intf_thread_t *p_intf, int direction, bool b_osd)
{
    playlist_t *p_playlist = pl_Get(p_intf);
    float vol = playlist_VolumeGet(p_playlist);
    if (vol < 0.f)
        vol = 1.f;
    int percent = (int)lroundf(vol * 100.f);
    int target;
    if (percent % 5 != 0)
        target = direction > 0
            ? (percent / 5 + 1) * 5
            : (percent / 5) * 5;
    else
        target = percent + direction * 5;
    if (target < 0)
        target = 0;
    else if (target > 125)
        target = 125;
    playlist_VolumeSet(p_playlist, target / 100.f);

    if (!b_osd)
        return;
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (!p_input)
        return;
    vout_thread_t *p_vout = input_GetVout(p_input);
    vlc_object_release(p_input);
    if (!p_vout)
        return;
    /* one bar channel per vout; the pointer is only compared, never
     * dereferenced when stale */
    static vout_thread_t *s_slider_vout = NULL;
    static int s_slider_chan = 0;
    if (s_slider_vout != p_vout) {
        s_slider_vout = p_vout;
        s_slider_chan = vout_RegisterSubpictureChannel(p_vout);
    }
    vout_FlushSubpictureChannel(p_vout, s_slider_chan);
    if (var_GetBool(p_vout, "fullscreen"))
        vout_OSDSlider(p_vout, s_slider_chan, target, OSD_VERT_SLIDER);
    vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD,
                    vlc_gettext("Volume %ld%%"), (long)target);
    vlc_object_release(p_vout);
}

/* does the pressed key match one of the (tab-separated) bindings of the
 * given core hotkey option? */
static bool KeyMatchesHotkey(intf_thread_t *p_intf, uint_fast32_t code,
                             const char *psz_name)
{
    char *psz_keys = var_InheritString(p_intf->obj.libvlc, psz_name);
    if (!psz_keys)
        return false;
    bool b_match = false;
    char *psz_state = NULL;
    char *psz_part;
    for (psz_part = strtok_r(psz_keys, "\t", &psz_state); psz_part;
         psz_part = strtok_r(NULL, "\t", &psz_state)) {
        if (vlc_str2keycode(psz_part) == code) {
            b_match = true;
            break;
        }
    }
    free(psz_keys);
    return b_match;
}

/* Port of the nskeys_to_vlckeys table of VLCStringUtility.m (3.0.23) */
static const struct
{
    unichar i_nskey;
    unsigned int i_vlckey;
} nskeys_to_vlckeys[] =
{
    { NSUpArrowFunctionKey, KEY_UP },
    { NSDownArrowFunctionKey, KEY_DOWN },
    { NSLeftArrowFunctionKey, KEY_LEFT },
    { NSRightArrowFunctionKey, KEY_RIGHT },
    { NSF1FunctionKey, KEY_F1 },
    { NSF2FunctionKey, KEY_F2 },
    { NSF3FunctionKey, KEY_F3 },
    { NSF4FunctionKey, KEY_F4 },
    { NSF5FunctionKey, KEY_F5 },
    { NSF6FunctionKey, KEY_F6 },
    { NSF7FunctionKey, KEY_F7 },
    { NSF8FunctionKey, KEY_F8 },
    { NSF9FunctionKey, KEY_F9 },
    { NSF10FunctionKey, KEY_F10 },
    { NSF11FunctionKey, KEY_F11 },
    { NSF12FunctionKey, KEY_F12 },
    { NSInsertFunctionKey, KEY_INSERT },
    { NSHomeFunctionKey, KEY_HOME },
    { NSEndFunctionKey, KEY_END },
    { NSPageUpFunctionKey, KEY_PAGEUP },
    { NSPageDownFunctionKey, KEY_PAGEDOWN },
    { NSMenuFunctionKey, KEY_MENU },
    { NSTabCharacter, KEY_TAB },
    { NSCarriageReturnCharacter, KEY_ENTER },
    { NSEnterCharacter, KEY_ENTER },
    { NSBackspaceCharacter, KEY_BACKSPACE },
    { NSDeleteCharacter, KEY_DELETE },
    { 0, 0 }
};

static unsigned int CocoaKeyToVLC(unichar i_key)
{
    unsigned int i;
    for (i = 0; nskeys_to_vlckeys[i].i_nskey != 0; i++)
        if (nskeys_to_vlckeys[i].i_nskey == i_key)
            return nskeys_to_vlckeys[i].i_vlckey;
    return (unsigned int)i_key;
}

BOOL VLCLegacyHandleKeyEvent(intf_thread_t *p_intf, NSEvent *event)
{
    if (!p_intf)
        return NO;

    /* Mac OS X 10.4 also routes KEY-UP events through NSWindow's
     * -performKeyEquivalent: (fixed in later releases): without this
     * filter every DVD menu arrow press navigated twice, once on press
     * and once on release. */
    if ([event type] != NSKeyDown)
        return NO;

    unsigned int modifiers = (unsigned int)[event modifierFlags];
    vlc_value_t val;
    val.i_int = 0;
    if (modifiers & NSShiftKeyMask)
        val.i_int |= KEY_MODIFIER_SHIFT;
    if (modifiers & NSControlKeyMask)
        val.i_int |= KEY_MODIFIER_CTRL;
    if (modifiers & NSAlternateKeyMask)
        val.i_int |= KEY_MODIFIER_ALT;
    if (modifiers & NSCommandKeyMask)
        val.i_int |= KEY_MODIFIER_COMMAND;

    NSString *characters = [event charactersIgnoringModifiers];
    if (![characters length])
        return NO;
    unichar key = [[characters lowercaseString] characterAtIndex:0];
    if (!key)
        return NO;

    /* Escape should always get you out of fullscreen (3.0.23 behavior) */
    if (key == (unichar)0x1b) {
        playlist_t *p_playlist = pl_Get(p_intf);
        if (var_GetBool(p_playlist, "fullscreen")) {
            var_ToggleBool(p_playlist, "fullscreen");
            input_thread_t *p_input = playlist_CurrentInput(p_playlist);
            if (p_input) {
                vout_thread_t *p_vout = input_GetVout(p_input);
                if (p_vout) {
                    var_SetBool(p_vout, "fullscreen", false);
                    vlc_object_release(p_vout);
                }
                vlc_object_release(p_input);
            }
        }
        return YES;
    }

    val.i_int |= (int)CocoaKeyToVLC(key);
    /* volume hotkeys use the interface stepping (multiples of 5%) and
     * never reach the core handler; per 3.0 behavior their OSD belongs
     * to the mouse wheel only */
    if (KeyMatchesHotkey(p_intf, (uint_fast32_t)val.i_int, "key-vol-up")) {
        VLCLegacyStepVolume(p_intf, 1, false);
        return YES;
    }
    if (KeyMatchesHotkey(p_intf, (uint_fast32_t)val.i_int, "key-vol-down")) {
        VLCLegacyStepVolume(p_intf, -1, false);
        return YES;
    }
    var_Set(p_intf->obj.libvlc, "key-pressed", val);
    return YES;
}

void VLCLegacyHandleScrollWheel(intf_thread_t *p_intf, NSEvent *event)
{
    if (!p_intf)
        return;
    float deltaY = (float)[event deltaY];
    float deltaX = (float)[event deltaX];
    vlc_value_t val;
    if (deltaY > 0.05f)
        val.i_int = KEY_MOUSEWHEELUP;
    else if (deltaY < -0.05f)
        val.i_int = KEY_MOUSEWHEELDOWN;
    else if (deltaX > 0.05f)
        val.i_int = KEY_MOUSEWHEELLEFT;
    else if (deltaX < -0.05f)
        val.i_int = KEY_MOUSEWHEELRIGHT;
    else
        return;

    /* wheel volume uses the interface stepping (multiples of 5%) with
     * the hotkeys-style OSD; the other wheel directions still reach the
     * core hotkeys */
    if (val.i_int == KEY_MOUSEWHEELUP || val.i_int == KEY_MOUSEWHEELDOWN) {
        VLCLegacyStepVolume(p_intf,
                            val.i_int == KEY_MOUSEWHEELUP ? 1 : -1, true);
        return;
    }

    var_Set(p_intf->obj.libvlc, "key-pressed", val);
}

static uint_fast32_t EventToVLCKey(NSEvent *event)
{
    unsigned int modifiers = (unsigned int)[event modifierFlags];
    uint_fast32_t code = 0;
    if (modifiers & NSShiftKeyMask)
        code |= KEY_MODIFIER_SHIFT;
    if (modifiers & NSControlKeyMask)
        code |= KEY_MODIFIER_CTRL;
    if (modifiers & NSAlternateKeyMask)
        code |= KEY_MODIFIER_ALT;
    if (modifiers & NSCommandKeyMask)
        code |= KEY_MODIFIER_COMMAND;

    NSString *characters = [event charactersIgnoringModifiers];
    if (![characters length])
        return 0;
    unichar key = [[characters lowercaseString] characterAtIndex:0];
    if (!key)
        return 0;
    return code | CocoaKeyToVLC(key);
}

int VLCLegacyEventHotkeyMatch(intf_thread_t *p_intf, NSEvent *event)
{
    /* -[VLCMainWindow performKeyEquivalent:] hands these to the core even
     * when a menu item carries the same key equivalent */
    static const char *const forced[] = {
        "key-vol-up", "key-vol-down", "key-vol-mute", "key-prev",
        "key-next", "key-jump+short", "key-jump-short"
    };

    if (!p_intf)
        return 0;
    uint_fast32_t code = EventToVLCKey(event);
    if (!code)
        return 0;

    module_t *p_main = module_find("core");
    if (!p_main)
        return 0;
    unsigned confsize;
    module_config_t *p_config = module_config_get(p_main, &confsize);
    int match = 0;
    unsigned i;
    for (i = 0; i < confsize && match != 2 && p_config; i++) {
        const module_config_t *p_item = &p_config[i];
        if (p_item->i_type != CONFIG_ITEM_KEY || !p_item->psz_name
            || strncmp(p_item->psz_name, "key-", 4)
            || !p_item->value.psz)
            continue;
        /* one hotkey option can hold several bindings, tab-separated */
        char *psz_copy = strdup(p_item->value.psz);
        if (!psz_copy)
            continue;
        char *psz_state = NULL;
        char *psz_part;
        for (psz_part = strtok_r(psz_copy, "\t", &psz_state); psz_part;
             psz_part = strtok_r(NULL, "\t", &psz_state)) {
            if (vlc_str2keycode(psz_part) != code)
                continue;
            match = 1;
            unsigned j;
            for (j = 0; j < sizeof(forced) / sizeof(forced[0]); j++) {
                if (!strcmp(p_item->psz_name, forced[j])) {
                    match = 2;
                    break;
                }
            }
            break;
        }
        free(psz_copy);
    }
    module_config_free(p_config);
    return match;
}

@implementation NSScreen (VLCAdditions)

- (BOOL)hasMenuBar
{
    return ([self displayID] == [[[NSScreen screens] objectAtIndex:0] displayID]);
}

- (BOOL)hasDock
{
    NSRect screen_frame = [self frame];
    NSRect screen_visible_frame = [self visibleFrame];
    CGFloat f_menu_bar_thickness = [self hasMenuBar] ? [[NSStatusBar systemStatusBar] thickness] : 0.0;

    BOOL b_found_dock = NO;
    if (screen_visible_frame.size.width < screen_frame.size.width)
        b_found_dock = YES;
    else if (screen_visible_frame.size.height + f_menu_bar_thickness < screen_frame.size.height)
        b_found_dock = YES;

    return b_found_dock;
}

- (CGDirectDisplayID)displayID
{
    return (CGDirectDisplayID)[[[self deviceDescription] objectForKey: @"NSScreenNumber"] intValue];
}

@end

void VLCLegacyConfirmAndOpenVideoLANURL(NSURL *url)
{
    if (url == nil)
        return;

    /* Translated through VLC's usual gettext catalog (_NS), like every other
     * interface string. The two Olsro links in the body are made clickable and
     * open directly (they are not VideoLAN links). */
    NSString *body = _NS(
        "You are currently using PowerVLC, an open source fork with no ads and no tracking, created independently by Olsro for the community and distributed freely. This derivative version would not exist without VLC itself, so out of respect I have chosen to keep all the links and buttons referring to VideoLAN, as well as the list of contributors.\n\n"
        "To support me, I have a Patreon ( https://www.patreon.com/Olsro/ ) where I accept your donations. You can find me on GitHub ( https://github.com/Olsro ) and I invite you to share PowerVLC and to leave positive and/or constructive feedback if this project matters to you in your life.\n\n"
        "Please do not bother VideoLAN with bug reports and support requests, as this fork is absolutely unofficial and not supported by VideoLAN.\n\n"
        "By clicking \"Yes\", you will be redirected to the requested link.");

    /* NSAlert is 10.3. Jaguar's AppKit exports the class symbol -- so the
     * plug-in links and loads -- but implements none of its methods, and
     * every one of them below would raise. NSRunAlertPanel has been there
     * since 10.0 and asks the same two-button question. */
    if (![NSAlert instancesRespondToSelector:@selector(setMessageText:)]) {
        if (NSRunAlertPanel(_NS("Warning!"), @"%@",
                            _NS("Yes"), _NS("No"), nil, body)
                == NSAlertDefaultReturn)
            [[NSWorkspace sharedWorkspace] openURL:url];
        return;
    }

    NSAlert *alert = [[[NSAlert alloc] init] autorelease];
    [alert setMessageText:_NS("Warning!")];

    /* -setAccessoryView: is 10.5+. There we render the body in an NSTextView so
     * the Olsro links are clickable; on 10.4 fall back to plain text. */
    if ([alert respondsToSelector:@selector(setAccessoryView:)]) {
        NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
            [NSFont systemFontOfSize:[NSFont systemFontSize]], NSFontAttributeName,
            [NSColor textColor], NSForegroundColorAttributeName, nil];
        NSMutableAttributedString *attributedBody = [[[NSMutableAttributedString alloc]
            initWithString:body attributes:attributes] autorelease];
        NSArray *links = [NSArray arrayWithObjects:
            @"https://www.patreon.com/Olsro/", @"https://github.com/Olsro", nil];
        unsigned i;
        for (i = 0; i < [links count]; i++) {
            NSString *link = [links objectAtIndex:i];
            NSRange range = [body rangeOfString:link];
            if (range.location != NSNotFound)
                [attributedBody addAttribute:NSLinkAttributeName
                                       value:[NSURL URLWithString:link]
                                       range:range];
        }
        NSScrollView *scrollView = [[[NSScrollView alloc]
            initWithFrame:NSMakeRect(0, 0, 440, 220)] autorelease];
        [scrollView setHasVerticalScroller:YES];
        [scrollView setDrawsBackground:NO];
        [scrollView setBorderType:NSNoBorder];
        NSTextView *textView = [[[NSTextView alloc]
            initWithFrame:NSMakeRect(0, 0, 440, 220)] autorelease];
        [textView setEditable:NO];
        [textView setSelectable:YES];
        [textView setDrawsBackground:NO];
        [textView setVerticallyResizable:YES];
        [textView setHorizontallyResizable:NO];
        [[textView textContainer] setContainerSize:NSMakeSize(440, 1.0e7)];
        [[textView textContainer] setWidthTracksTextView:YES];
        [[textView textStorage] setAttributedString:attributedBody];
        [scrollView setDocumentView:textView];
        [alert setAccessoryView:scrollView];
    } else {
        [alert setInformativeText:body];
    }

    [alert addButtonWithTitle:_NS("Yes")];
    [alert addButtonWithTitle:_NS("No")];

    if ([alert runModal] == NSAlertFirstButtonReturn)
        [[NSWorkspace sharedWorkspace] openURL:url];
}

/*****************************************************************************
 * 10.3 AppKit conveniences, resolved at runtime (see misc.h)
 *****************************************************************************/

NSTextField *VLCLegacyMakeSearchField(NSRect frame, id target, SEL action)
{
    Class searchClass = NSClassFromString(@"NSSearchField");
    NSTextField *field = [[[(searchClass ? searchClass : [NSTextField class])
        alloc] initWithFrame:frame] autorelease];
    id cell = [field cell];

    [cell setControlSize:NSSmallControlSize];
    [cell setFont:[NSFont systemFontOfSize:11]];
    [field setTarget:target];
    [field setAction:action];

    if (searchClass != Nil) {
        /* search as you type, rather than on Return */
        [cell setSendsWholeSearchString:NO];
        if ([cell respondsToSelector:
                @selector(setSendsSearchStringImmediately:)])
            [cell setSendsSearchStringImmediately:YES];
    } else if ([target respondsToSelector:@selector(controlTextDidChange:)]) {
        [field setDelegate:target];
    }
    return field;
}

NSArray *VLCLegacySelectedRows(NSTableView *table)
{
    NSMutableArray *rows = [NSMutableArray array];

    if ([table respondsToSelector:@selector(selectedRowIndexes)]) {
        id selection = [table selectedRowIndexes];
        NSUInteger index;

        for (index = [selection firstIndex]; index != (NSUInteger)NSNotFound;
             index = [selection indexGreaterThanIndex:index])
            [rows addObject:[NSNumber numberWithInt:(int)index]];
    } else {
        /* 10.2: an enumerator of NSNumbers, already in ascending order */
        NSEnumerator *e = [table performSelector:
            @selector(selectedRowEnumerator)];
        NSNumber *row;

        while ((row = [e nextObject]) != nil)
            [rows addObject:row];
    }
    return rows;
}

void VLCLegacySelectRow(NSTableView *table, NSInteger row)
{
    Class indexSetClass = NSClassFromString(@"NSIndexSet");

    if (indexSetClass != Nil
     && [table respondsToSelector:
            @selector(selectRowIndexes:byExtendingSelection:)])
        [table selectRowIndexes:[indexSetClass indexSetWithIndex:(NSUInteger)row]
           byExtendingSelection:NO];
    else
        [table selectRow:row byExtendingSelection:NO];
}

/* Views detached by VLCLegacySetViewHidden(), keyed by the view's address:
 * the superview it came from and the sibling it sat under, so it goes back
 * exactly where it was rather than on top of everything. Main thread only,
 * like the rest of the interface. */
static NSMutableDictionary *detachedViews;

/* Views asked to hide BEFORE they were inserted anywhere. That order is
 * natural to write and harmless with a real -setHidden:, but detaching a
 * view that is not attached yet does nothing -- and then whoever adds it
 * makes it visible. It cost the whole Preferences window, whose advanced
 * pane covered the simple one, and the video view over the playlist before
 * that. AppKit offers no hook on -addSubview:, so they are reconciled at
 * the end of the current run-loop cycle, by which time the interface has
 * finished building itself. */
static NSMutableArray *pendingHides;

@interface VLCLegacyHideReconciler : NSObject
@end

@implementation VLCLegacyHideReconciler

- (void)reconcile:(NSTimer *)timer
{
    NSArray *views = [[pendingHides copy] autorelease];
    unsigned i;

    (void)timer;
    [pendingHides removeAllObjects];

    for (i = 0; i < [views count]; i++) {
        NSView *view = [views objectAtIndex:i];

        if ([view superview] == nil) {
            /* still nowhere: keep waiting rather than lose the request */
            [pendingHides addObject:view];
            continue;
        }
        /* drop the "hidden while detached" record so the real detach runs */
        [detachedViews removeObjectForKey:[NSValue valueWithPointer:view]];
        VLCLegacySetViewHidden(view, YES);
    }

    if ([pendingHides count] > 0)
        [NSTimer scheduledTimerWithTimeInterval:0.0 target:self
                                       selector:@selector(reconcile:)
                                       userInfo:nil repeats:NO];
}

@end

void VLCLegacySetViewHidden(NSView *view, BOOL hidden)
{
    if (view == nil)
        return;

    if ([view respondsToSelector:@selector(setHidden:)]) {
        [view setHidden:hidden];
        return;
    }

    NSValue *key = [NSValue valueWithPointer:view];

    if (detachedViews == nil)
        detachedViews = [[NSMutableDictionary alloc] init];

    NSDictionary *entry = [detachedViews objectForKey:key];

    if (hidden) {
        NSView *superview = [view superview];

        if (entry != nil)
            return;                     /* already hidden */

        if (superview == nil) {
            /* Hidden before being inserted anywhere: remember the state so
             * -isHidden does not lie, and come back for it once the caller
             * has put the view somewhere (see VLCLegacyHideReconciler). */
            [detachedViews setObject:
                [NSDictionary dictionaryWithObject:view forKey:@"view"]
                               forKey:key];

            if (pendingHides == nil)
                pendingHides = [[NSMutableArray alloc] init];
            if (![pendingHides containsObject:view]) {
                [pendingHides addObject:view];
                [NSTimer scheduledTimerWithTimeInterval:0.0
                    target:[[[VLCLegacyHideReconciler alloc] init] autorelease]
                  selector:@selector(reconcile:)
                  userInfo:nil repeats:NO];
            }
            return;
        }

        /* The sibling drawn just below this one: re-inserting relative to
         * it restores the z-order, which matters wherever a hidden view
         * overlaps the one that replaces it (the video view and the
         * playlist share the same rectangle). */
        NSArray *siblings = [superview subviews];
        NSUInteger index = [siblings indexOfObject:view];
        NSView *below = (index != (NSUInteger)NSNotFound && index > 0)
            ? [siblings objectAtIndex:index - 1] : nil;

        NSMutableDictionary *record = [NSMutableDictionary dictionary];
        [record setObject:view forKey:@"view"];      /* keeps it alive */
        [record setObject:superview forKey:@"superview"];
        if (below != nil)
            [record setObject:below forKey:@"below"];
        /* A detached view misses every resize its superview goes through --
         * and the main window DOES resize while the playlist is hidden, to
         * fit the video. Recording the size it was detached at is what makes
         * -resizeWithOldSuperviewSize: able to catch it up on the way back;
         * without it the playlist came back laid out for the old window. */
        [record setObject:[NSValue valueWithSize:[superview bounds].size]
                   forKey:@"superviewSize"];
        [detachedViews setObject:record forKey:key];

        [view removeFromSuperview];
    } else {
        if (entry == nil)
            return;                     /* already visible */

        [pendingHides removeObject:view];

        NSView *superview = [entry objectForKey:@"superview"];
        NSView *below = [entry objectForKey:@"below"];

        if (superview == nil)
            ;                           /* was never attached; see above */
        else if (below != nil && [below superview] == superview)
            [superview addSubview:view positioned:NSWindowAbove
                       relativeTo:below];
        else
            [superview addSubview:view positioned:NSWindowBelow
                       relativeTo:nil];

        /* Apply the resizes it slept through, by its own autoresizing mask:
         * exactly what AppKit would have done had it stayed in place. */
        NSValue *oldSize = [entry objectForKey:@"superviewSize"];
        if (superview != nil && oldSize != nil)
            [view resizeWithOldSuperviewSize:[oldSize sizeValue]];

        [detachedViews removeObjectForKey:key];
    }
}

NSView *VLCLegacyViewWithTag(NSView *root, NSInteger tag)
{
    NSView *found = [root viewWithTag:tag];

    if (found != nil || detachedViews == nil)
        return found;

    NSEnumerator *e = [detachedViews objectEnumerator];
    NSDictionary *record;

    while ((record = [e nextObject]) != nil) {
        NSView *view = [record objectForKey:@"view"];

        if ([view tag] == tag)
            return view;
    }
    return nil;
}

BOOL VLCLegacyViewIsHidden(NSView *view)
{
    if (view == nil)
        return YES;
    if ([view respondsToSelector:@selector(isHidden)])
        return [view isHidden];
    return [detachedViews objectForKey:[NSValue valueWithPointer:view]] != nil;
}

void VLCLegacyResizeLastColumnOnly(NSTableView *table)
{
    if ([table respondsToSelector:@selector(setColumnAutoresizingStyle:)])
        [table setColumnAutoresizingStyle:
            NSTableViewLastColumnOnlyAutoresizingStyle];
    else
        [table setAutoresizesAllColumnsToFit:NO];
}

@implementation VLCLegacyStripedOutlineView

- (void)highlightSelectionInClipRect:(NSRect)clipRect
{
    /* From 10.3 on AppKit does this itself, and better (it follows the
     * user's appearance setting). */
    /* ⚠ -drawsBackground has no business being asked here: on NSTableView
     * it is 10.6, and asking cost the whole playlist -- an exception raised
     * inside -drawRect: leaves the view black. */
    if (![self respondsToSelector:
             @selector(setUsesAlternatingRowBackgroundColors:)]
     && !VLCLegacyDarkMode()) {
        /* Panther's own second row colour, which is what this is standing
         * in for. */
        NSColor *stripe = [NSColor colorWithCalibratedRed:0.929
                                                    green:0.953
                                                     blue:0.996
                                                    alpha:1.0];
        CGFloat step = [self rowHeight] + [self intercellSpacing].height;

        if (step > 0.0) {
            /* Rows are numbered from the top of the view, and every other
             * one is striped -- past the last row too, like AppKit. */
            int first = (int)floor(NSMinY(clipRect) / step);
            int last = (int)ceil(NSMaxY(clipRect) / step);
            int row;

            [stripe set];
            for (row = first; row <= last; row++) {
                if (row % 2 == 0)
                    continue;
                NSRectFill(NSIntersectionRect(clipRect,
                    NSMakeRect(NSMinX(clipRect), row * step,
                               NSWidth(clipRect), step)));
            }
        }
    }

    [super highlightSelectionInClipRect:clipRect];
}

@end

void VLCLegacySetCellLineBreakMode(NSCell *cell, NSLineBreakMode mode)
{
    if ([cell respondsToSelector:@selector(setLineBreakMode:)]) {
        VLCLegacySetCellLineBreakMode(cell, mode);
        return;
    }

    [cell setWraps:mode == NSLineBreakByWordWrapping
                || mode == NSLineBreakByCharWrapping];
}

CGFloat VLCLegacySystemFontSizeForControlSize(NSControlSize size)
{
    if ([NSFont respondsToSelector:@selector(systemFontSizeForControlSize:)])
        return [NSFont systemFontSizeForControlSize:size];

    switch (size) {
        case NSMiniControlSize:
        case NSSmallControlSize:
            return [NSFont smallSystemFontSize];
        default:
            return [NSFont systemFontSize];
    }
}

NSCursor *VLCLegacyResizeUpDownCursor(void)
{
    if ([NSCursor respondsToSelector:@selector(resizeUpDownCursor)])
        return VLCLegacyResizeUpDownCursor();
    return [NSCursor arrowCursor];
}

void VLCLegacySelectItemWithTag(NSPopUpButton *popup, NSInteger tag)
{
    if ([popup respondsToSelector:@selector(selectItemWithTag:)]) {
        [popup selectItemWithTag:tag];
        return;
    }

    NSInteger count = (NSInteger)[popup numberOfItems];
    NSInteger i;

    for (i = 0; i < count; i++)
        if ([[popup itemAtIndex:i] tag] == tag) {
            [popup selectItemAtIndex:i];
            return;
        }
}

void VLCLegacySetPanelFileType(NSSavePanel *panel, NSString *extension)
{
    if ([panel respondsToSelector:@selector(setAllowedFileTypes:)])
        [panel setAllowedFileTypes:[NSArray arrayWithObject:extension]];
    else
        [panel setRequiredFileType:extension];
}

NSRect VLCLegacyContentRectForFrameRect(NSWindow *window, NSRect frame)
{
    if ([window respondsToSelector:@selector(contentRectForFrameRect:)])
        return [window contentRectForFrameRect:frame];
    return [NSWindow contentRectForFrameRect:frame
                                   styleMask:[window styleMask]];
}

NSRect VLCLegacyFrameRectForContentRect(NSWindow *window, NSRect content)
{
    if ([window respondsToSelector:@selector(frameRectForContentRect:)])
        return [window frameRectForContentRect:content];
    return [NSWindow frameRectForContentRect:content
                                   styleMask:[window styleMask]];
}

BOOL VLCLegacyMenuDelegatesAvailable(void)
{
    return [NSMenu instancesRespondToSelector:@selector(setDelegate:)];
}

BOOL VLCLegacySetMenuDelegate(NSMenu *menu, id delegate)
{
    if (!VLCLegacyMenuDelegatesAvailable())
        return NO;

    [menu setDelegate:delegate];
    return YES;
}

/* The pre-10.3 stand-in for an NSMenu delegate (see misc.h). */
@interface VLCLegacyDynamicMenu : NSMenu
{
    id controller;   /* weak: it owns the menu, not the other way round */
}
- (void)setUpdateController:(id)c;
@end

@implementation VLCLegacyDynamicMenu

- (void)setUpdateController:(id)c
{
    controller = c;
}

- (void)update
{
    if ([controller respondsToSelector:@selector(menuNeedsUpdate:)])
        [controller menuNeedsUpdate:self];
    [super update];
}

@end

NSMenu *VLCLegacyMakeDynamicMenu(NSString *title, id controller)
{
    if (VLCLegacyMenuDelegatesAvailable()) {
        NSMenu *menu = [[[NSMenu alloc] initWithTitle:title] autorelease];

        [menu setDelegate:controller];
        return menu;
    }

    VLCLegacyDynamicMenu *menu =
        [[[VLCLegacyDynamicMenu alloc] initWithTitle:title] autorelease];

    [menu setUpdateController:controller];
    return menu;
}

static NSInteger VLCLegacyCompareTitles(id left, id right, void *context)
{
    VLC_UNUSED(context);
    return (NSInteger)[[left objectForKey:@"title"] caseInsensitiveCompare:
                       [right objectForKey:@"title"]];
}

void VLCLegacySortDictionariesByTitle(NSMutableArray *array)
{
    /* -sortUsingFunction:context: has been there since 10.0 and does not
     * need the array to be key-value coding compliant, which is what
     * NSSortDescriptor was buying us. */
    [array sortUsingFunction:VLCLegacyCompareTitles context:NULL];
}
