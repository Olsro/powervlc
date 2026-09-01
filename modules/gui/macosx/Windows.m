/*****************************************************************************
 * Windows.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2012-2014 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne -at- videolan -dot- org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "Windows.h"
#import "VLCMain.h"
#import "VLCInputManager.h"
#import "VLCCoreInteraction.h"
#import "VLCControlsBarCommon.h"
#import "VLCStringUtility.h"
#import "VLCVoutView.h"
#import "CompatibilityFixes.h"
#import "NSScreen+VLCAdditions.h"

#import <vlc_actions.h>
#import <vlc_playlist.h>
#import <vlc_input.h>

static BOOL VLCModernWindowInputIsBluRayDiscSession(void)
{
    input_thread_t *input = playlist_CurrentInput(pl_Get(getIntf()));
    if (input == NULL)
        return NO;
    const BOOL disc = var_GetBool(input, "bluray-disc-session");
    vlc_object_release(input);
    return disc;
}

/*****************************************************************************
 * VLCWindow
 *
 *  Missing extension to NSWindow
 *****************************************************************************/

@interface VLCWindow()
{
    BOOL b_canBecomeKeyWindow;
    BOOL b_isset_canBecomeKeyWindow;
    BOOL b_canBecomeMainWindow;
    BOOL b_isset_canBecomeMainWindow;
}
@end

@implementation VLCWindow

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask
                  backing:(NSBackingStoreType)backingType defer:(BOOL)flag
{
    self = [super initWithContentRect:contentRect styleMask:styleMask backing:backingType defer:flag];
    if (self) {
        /* we don't want this window to be restored on relaunch */
        [self setRestorable:NO];
    }
    return self;
}

- (void)setCanBecomeKeyWindow: (BOOL)canBecomeKey
{
    b_isset_canBecomeKeyWindow = YES;
    b_canBecomeKeyWindow = canBecomeKey;
}

- (BOOL)canBecomeKeyWindow
{
    if (b_isset_canBecomeKeyWindow)
        return b_canBecomeKeyWindow;

    return [super canBecomeKeyWindow];
}

- (void)setCanBecomeMainWindow: (BOOL)canBecomeMain
{
    b_isset_canBecomeMainWindow = YES;
    b_canBecomeMainWindow = canBecomeMain;
}

- (BOOL)canBecomeMainWindow
{
    if (b_isset_canBecomeMainWindow)
        return b_canBecomeMainWindow;

    return [super canBecomeMainWindow];
}

- (void)closeAndAnimate:(BOOL)animate
{
    // No animation, just close
    if (!animate) {
        [super close];
        return;
    }

    // Animate window alpha value
    [self setAlphaValue:1.0];
    __unsafe_unretained typeof(self) this = self;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context){
        [[NSAnimationContext currentContext] setDuration:0.9];
        [[this animator] setAlphaValue:0.0];
    } completionHandler:^{
        [this close];
    }];
}

- (void)orderOut:(id)sender animate:(BOOL)animate
{
    if (!animate) {
        [super orderOut:sender];
        return;
    }

    if ([self alphaValue] == 0.0) {
        [super orderOut:self];
        return;
    }
    __unsafe_unretained typeof(self) this = self;
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context){
        [[NSAnimationContext currentContext] setDuration:0.5];
        [[this animator] setAlphaValue:0.0];
    } completionHandler:^{
        [this orderOut:self];
    }];
}

- (void)orderFront:(id)sender animate:(BOOL)animate
{
    if (!animate) {
        [super orderFront:sender];
        [self setAlphaValue:1.0];
        return;
    }

    if (![self isVisible]) {
        [self setAlphaValue:0.0];
        [super orderFront:sender];
    } else if ([self alphaValue] == 1.0) {
        [super orderFront:self];
        return;
    }

    [NSAnimationContext beginGrouping];
    [[NSAnimationContext currentContext] setDuration:0.5];
    [[self animator] setAlphaValue:1.0];
    [NSAnimationContext endGrouping];
}

- (VLCVoutView *)videoView
{
    NSArray *o_subViews = [[self contentView] subviews];
    if ([o_subViews count] > 0) {
        id o_vout_view = [o_subViews firstObject];

        if ([o_vout_view class] == [VLCVoutView class])
            return (VLCVoutView *)o_vout_view;
    }

    return nil;
}

- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen
{
    if (!screen)
        screen = [self screen];
    NSRect screenRect = [screen frame];
    NSRect constrainedRect = [super constrainFrameRect:frameRect toScreen:screen];

    /*
     * Ugly workaround!
     * With Mavericks, there is a nasty bug resulting in grey bars on top in fullscreen mode.
     * It looks like this is enforced by the os because the window is in the way for the menu bar.
     *
     * According to the documentation, this constraining can be changed by overwriting this
     * method. But in this situation, even the received frameRect is already contrained with the
     * menu bars height substracted. This case is detected here, and the full height is
     * enforced again.
     *
     * See #9469 and radar://15583566
     */

    BOOL b_inFullscreen = [self fullscreen] || ([self respondsToSelector:@selector(inFullscreenTransition)] && [(VLCVideoWindowCommon *)self inFullscreenTransition]);

    if((OSX_MAVERICKS_AND_HIGHER && !OSX_YOSEMITE_AND_HIGHER) && b_inFullscreen && constrainedRect.size.width == screenRect.size.width
          && constrainedRect.size.height != screenRect.size.height
          && fabs(screenRect.size.height - constrainedRect.size.height) <= 25.) {

        msg_Dbg(getIntf(), "Contrain window height %.1f to screen height %.1f",
                constrainedRect.size.height, screenRect.size.height);
        constrainedRect.size.height = screenRect.size.height;
    }

    return constrainedRect;
}

@end

/*****************************************************************************
 * VLCVideoWindowCommon
 *
 *  Common code for main window, detached window and extra video window
 *****************************************************************************/

@interface VLCVideoWindowCommon()
{
    // variables for fullscreen handling
    VLCVideoWindowCommon *o_current_video_window;
    VLCWindow       * o_fullscreen_window;
    NSViewAnimation * o_fullscreen_anim1;
    NSViewAnimation * o_fullscreen_anim2;
    NSView          * o_temp_view;

    NSInteger i_originalLevel;

    BOOL b_video_view_was_hidden;

    NSRect frameBeforeLionFullscreen;

    // "Hide controls during playback" state
    NSTimer *o_autohide_controls_timer;     // 0.5 s poll, always on
    int i_autohide_outside_ticks;           // mouse outside the window
    int i_autohide_reveal_ticks;            // video gone
    NSWindowStyleMask i_stylemask_before_hiding_controls;
    BOOL _videoDragActive;                  // picture drag moves the window
    NSRect o_frame_before_hiding_controls;  // full frame to restore
    NSRect o_hidden_controls_initial_frame; // to keep drags across reveal
    NSSize o_last_requested_video_size;     // to spot a plain restart
    CGFloat f_last_video_zoom;              // to spot a zoom the user asked for
    NSSize o_picture_box;                   // box a shape change fits in
}

- (void)customZoom:(id)sender;
- (void)hasBecomeFullscreen;
- (void)hasEndedFullscreen;
@end

@implementation VLCVideoWindowCommon

#pragma mark -
#pragma mark Init

- (id)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)styleMask
                  backing:(NSBackingStoreType)backingType defer:(BOOL)flag
{
    if (@available(macOS 10.14, *)) {
        self = [super initWithContentRect:contentRect styleMask:styleMask
                                  backing:backingType defer:flag];
    } else {
        _darkInterface = config_GetInt(getIntf(), "macosx-interfacestyle");

        if (_darkInterface) {
            styleMask = NSBorderlessWindowMask | NSResizableWindowMask | NSMiniaturizableWindowMask;
        }

        self = [super initWithContentRect:contentRect styleMask:styleMask
                                  backing:backingType defer:flag];
    }

    /* we want to be moveable regardless of our style */
    [self setMovableByWindowBackground: YES];
    [self setCanBecomeKeyWindow:YES];

    o_temp_view = [[NSView alloc] init];
    [o_temp_view setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];

    return self;
}

/* in clip creation mode the bare arrow keys nudge the selected clip
 * bound by one frame, wherever the focus sits inside the window: the
 * event otherwise dies on whatever first responder holds it (the video
 * lives in a borderless child window that never becomes key, so the
 * VLCVoutView keyDown path is unreachable in embedded playback) */
- (void)keyDown:(NSEvent *)event
{
    /* In embedded playback this window, rather than VLCVoutView, is commonly
     * the key responder. Any keyboard activity must still stop the resume
     * prompt's automatic ten-second dismissal. Prompt-owned arrows/Enter/Esc
     * are handled in VLCVoutView when it is the responder; all other keys keep
     * their normal path below. */
    [[[VLCMain sharedInstance] inputManager]
        noteResumeOSDUserInteraction];

    NSString *characters = [event charactersIgnoringModifiers];
    BOOL bareKey = [characters length] == 1
        && !([event modifierFlags]
             & (NSShiftKeyMask | NSControlKeyMask | NSAlternateKeyMask
                | NSCommandKeyMask));
    if (bareKey) {
        unichar cocoaKey = [characters characterAtIndex:0];
        unsigned int vlcKey = CocoaKeyToVLC(cocoaKey);

        /* The embedded video lives in a borderless child window which does
         * not become key. Its parent consequently receives arrows and Enter,
         * while VLCVoutView (the normal hotkey forwarding path) never sees
         * them. This left initial BD-J language selectors keyboard-inert even
         * though the same keys worked later after focus happened to move.
         * Handle the resume OSD here too for the same responder topology. */
        if ([[[VLCMain sharedInstance] inputManager]
                handleResumeOSDKey:vlcKey])
            return;

        if ([[VLCCoreInteraction sharedInstance] clipCreationMode]) {
            unichar key = cocoaKey;
            if (key == NSLeftArrowFunctionKey
                || key == NSRightArrowFunctionKey) {
                [[VLCCoreInteraction sharedInstance]
                    clipStepFrames:(key == NSRightArrowFunctionKey ? 1 : -1)];
                return;
            }
        }

        switch (vlcKey) {
            case KEY_UP:
            case KEY_DOWN:
            case KEY_LEFT:
            case KEY_RIGHT: {
                var_SetInteger(getIntf()->obj.libvlc, "key-pressed", vlcKey);
                if (!VLCModernWindowInputIsBluRayDiscSession()) {
                    VLCCoreInteraction *core = [VLCCoreInteraction sharedInstance];
                    if (vlcKey == KEY_UP || vlcKey == KEY_DOWN)
                        [core scheduleVolumeOSD];
                    else
                        [core schedulePositionOSD];
                }
                return;
            }
            case KEY_ENTER:
                var_SetInteger(getIntf()->obj.libvlc, "key-pressed", vlcKey);
                return;
            default:
                break;
        }
    }
    [super keyDown:event];
}

- (void)awakeFromNib
{
    BOOL b_nativeFullscreenMode = var_InheritBool(getIntf(), "macosx-nativefullscreenmode");

    if (b_nativeFullscreenMode) {
        [self setCollectionBehavior: NSWindowCollectionBehaviorFullScreenPrimary];
    } else if (OSX_EL_CAPITAN_AND_HIGHER) {
        // Native fullscreen seems to be default on El Capitan, this disables it explicitely
        [self setCollectionBehavior: NSWindowCollectionBehaviorFullScreenAuxiliary];
    }

    if (!_darkInterface && self.titlebarView) {
        [self.titlebarView removeFromSuperview];
        self.titlebarView = nil;
    }

    /* "Hide controls during playback": polled, exactly like the other
     * two interfaces. A tracking area was tried first and lost hide
     * cycles -- a mouse-exited event that never comes (a warped pointer,
     * a window that changed under the cursor) leaves the machine with
     * nothing to re-arm it, and the feature silently stops working until
     * the mouse enters and leaves again. A half-second poll cannot miss
     * a state, whatever order the video, the playlist view and the
     * playback state settle in. */
    o_autohide_controls_timer = [NSTimer
        scheduledTimerWithTimeInterval:0.5
                                target:self
                              selector:@selector(autoHideControlsTick:)
                              userInfo:nil
                               repeats:YES];

    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(revealControlsNotification:)
               name:VLCRevealControlsNotification
             object:nil];

    [super awakeFromNib];
}

- (void)dealloc
{
    if (o_autohide_controls_timer) {
        [o_autohide_controls_timer invalidate];
        o_autohide_controls_timer = nil;
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)setTitle:(NSString *)title
{
    if (!title || [title length] < 1)
        return;

    if (_darkInterface && self.titlebarView)
        [self.titlebarView setWindowTitle: title];

    [super setTitle: title];
}

#pragma mark -
#pragma mark zoom / minimize / close

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    SEL s_menuAction = [menuItem action];

    if ((s_menuAction == @selector(performClose:)) || (s_menuAction == @selector(performMiniaturize:)) || (s_menuAction == @selector(performZoom:)))
        return YES;

    return [super validateMenuItem:menuItem];
}

- (BOOL)windowShouldClose:(id)sender
{
    return YES;
}

- (void)performClose:(id)sender
{
    if (!([self styleMask] & NSTitledWindowMask)) {
        [[NSNotificationCenter defaultCenter] postNotificationName:NSWindowWillCloseNotification object:self];

        [self close];
    } else
        [super performClose: sender];
}

- (void)performMiniaturize:(id)sender
{
    if (!([self styleMask] & NSTitledWindowMask))
        [self miniaturize: sender];
    else
        [super performMiniaturize: sender];
}

- (void)performZoom:(id)sender
{
    if (!([self styleMask] & NSTitledWindowMask))
        [self customZoom: sender];
    else
        [super performZoom: sender];
}

- (void)zoom:(id)sender
{
    if (!([self styleMask] & NSTitledWindowMask))
        [self customZoom: sender];
    else
        [super zoom: sender];
}

/**
 * Given a proposed frame rectangle, return a modified version
 * which will fit inside the screen.
 *
 * This method is based upon NSWindow.m, part of the GNUstep GUI Library, licensed under LGPLv2+.
 *    Authors:  Scott Christley <scottc@net-community.com>, Venkat Ajjanagadde <venkat@ocbi.com>,
 *              Felipe A. Rodriguez <far@ix.netcom.com>, Richard Frith-Macdonald <richard@brainstorm.co.uk>
 *    Copyright (C) 1996 Free Software Foundation, Inc.
 */
- (NSRect) customConstrainFrameRect: (NSRect)frameRect toScreen: (NSScreen*)screen
{
    NSRect screenRect = [screen visibleFrame];
    CGFloat difference;

    /* Move top edge of the window inside the screen */
    difference = NSMaxY (frameRect) - NSMaxY (screenRect);
    if (difference > 0) {
        frameRect.origin.y -= difference;
    }

    /* If the window is resizable, resize it (if needed) so that the
     bottom edge is on the screen or can be on the screen when the user moves
     the window */
    difference = NSMaxY (screenRect) - NSMaxY (frameRect);
    if (self.styleMask & NSResizableWindowMask) {
        CGFloat difference2;

        difference2 = screenRect.origin.y - frameRect.origin.y;
        difference2 -= difference;
        // Take in account the space between the top of window and the top of the
        // screen which can be used to move the bottom of the window on the screen
        if (difference2 > 0) {
            frameRect.size.height -= difference2;
            frameRect.origin.y += difference2;
        }

        /* Ensure that resizing doesn't makewindow smaller than minimum */
        difference2 = [self minSize].height - frameRect.size.height;
        if (difference2 > 0) {
            frameRect.size.height += difference2;
            frameRect.origin.y -= difference2;
        }
    }

    return frameRect;
}

#define DIST 3

/**
 Zooms the receiver.   This method calls the delegate method
 windowShouldZoom:toFrame: to determine if the window should
 be allowed to zoom to full screen.
 *
 * This method is based upon NSWindow.m, part of the GNUstep GUI Library, licensed under LGPLv2+.
 *    Authors:  Scott Christley <scottc@net-community.com>, Venkat Ajjanagadde <venkat@ocbi.com>,
 *              Felipe A. Rodriguez <far@ix.netcom.com>, Richard Frith-Macdonald <richard@brainstorm.co.uk>
 *    Copyright (C) 1996 Free Software Foundation, Inc.
 */
- (void) customZoom: (id)sender
{
    NSRect maxRect = [[self screen] visibleFrame];
    NSRect currentFrame = [self frame];

    if ([[self delegate] respondsToSelector: @selector(windowWillUseStandardFrame:defaultFrame:)]) {
        maxRect = [[self delegate] windowWillUseStandardFrame: self defaultFrame: maxRect];
    }

    maxRect = [self customConstrainFrameRect: maxRect toScreen: [self screen]];

    // Compare the new frame with the current one
    if ((fabs(NSMaxX(maxRect) - NSMaxX(currentFrame)) < DIST)
        && (fabs(NSMaxY(maxRect) - NSMaxY(currentFrame)) < DIST)
        && (fabs(NSMinX(maxRect) - NSMinX(currentFrame)) < DIST)
        && (fabs(NSMinY(maxRect) - NSMinY(currentFrame)) < DIST)) {
        // Already in zoomed mode, reset user frame, if stored
        if ([self frameAutosaveName] != nil) {
            [self setFrame: self.previousSavedFrame display: YES animate: YES];
            [self saveFrameUsingName: [self frameAutosaveName]];
        }
        return;
    }

    if ([self frameAutosaveName] != nil) {
        [self saveFrameUsingName: [self frameAutosaveName]];
        self.previousSavedFrame = [self frame];
    }

    [self setFrame: maxRect display: YES animate: YES];
}

#pragma mark -
#pragma mark Video window resizing logic

- (void)setWindowLevel:(NSInteger)i_state
{
    if (var_InheritBool(getIntf(), "video-wallpaper") || [self level] < NSNormalWindowLevel)
        return;

    if (!self.fullscreen && !_inFullscreenTransition)
        [self setLevel: i_state];

    // save it for restore if window is currently minimized or in fullscreen
    i_originalLevel = i_state;
}

- (NSRect)getWindowRectForProposedVideoViewSize:(NSSize)size
{
    NSSize windowMinSize = [self minSize];
    NSRect screenFrame = [[self screen] visibleFrame];

    /* ⚠ Le chrome (barre de titre + barre de contrôles) est mesuré plus bas
     * comme la DIFFÉRENCE entre la fenêtre et la vue vidéo : cela suppose que
     * la vue vidéo a déjà la taille que ses contraintes lui donnent. Au tout
     * premier vout d'une fenêtre détachée, Auto Layout n'a pas encore tourné
     * sur le nib et la mesure sortait 22 pt trop grande : la fenêtre s'ouvrait
     * d'autant trop haute et l'image, pourtant à l'échelle 1:1, se retrouvait
     * avec deux bandes noires (11 pt en haut, 11 en bas) que ni l'amont ni
     * l'interface legacy n'affichent. */
    [[self contentView] layoutSubtreeIfNeeded];

    NSRect topleftbase = NSMakeRect(0, [self frame].size.height, 0, 0);
    NSPoint topleftscreen = [self convertRectToScreen: topleftbase].origin;

    CGFloat f_width = size.width;
    CGFloat f_height = size.height;
    if (f_width < windowMinSize.width)
        f_width = windowMinSize.width;
    if (f_height < f_min_video_height)
        f_height = f_min_video_height;

    /* Calculate the window's new size */
    NSRect new_frame;
    new_frame.size.width = [self frame].size.width - [_videoView frame].size.width + f_width;
    new_frame.size.height = [self frame].size.height - [_videoView frame].size.height + f_height;
    new_frame.origin.x = topleftscreen.x;
    new_frame.origin.y = topleftscreen.y - new_frame.size.height;

    /* make sure the window doesn't exceed the screen size the window is on */
    if (new_frame.size.width > screenFrame.size.width) {
        new_frame.size.width = screenFrame.size.width;
        new_frame.origin.x = screenFrame.origin.x;
    }
    if (new_frame.size.height > screenFrame.size.height) {
        new_frame.size.height = screenFrame.size.height;
        new_frame.origin.y = screenFrame.origin.y;
    }
    if (new_frame.origin.y < screenFrame.origin.y)
        new_frame.origin.y = screenFrame.origin.y;

    CGFloat right_screen_point = screenFrame.origin.x + screenFrame.size.width;
    CGFloat right_window_point = new_frame.origin.x + new_frame.size.width;
    if (right_window_point > right_screen_point)
        new_frame.origin.x -= (right_window_point - right_screen_point);

    return new_frame;
}

- (void)resizeWindow
{
    // VOUT_WINDOW_SET_SIZE is triggered when exiting fullscreen. This event is ignored here
    // to avoid interference with the animation.
    if ([self fullscreen] || _inFullscreenTransition)
        return;

    /* see -pictureSizeForRequest:currentArea: -- the bare window is the
     * picture itself, the decorated one keeps its chrome around it, but
     * both follow the same rule */
    if (_controlsHiddenForPlayback) {
        [self hiddenWindowFollowVideoSize:self.nativeVideoSize];
        return;
    }

    NSSize picture = [self pictureSizeForRequest:self.nativeVideoSize
                                     currentArea:[self.videoView frame].size];
    if (picture.width <= 0. || picture.height <= 0.)
        return;

    NSRect window_rect = [self getWindowRectForProposedVideoViewSize:picture];
    [[self animator] setFrame:window_rect display:YES];
}

- (void)setNativeVideoSize:(NSSize)size
{
    _nativeVideoSize = size;

    if (var_InheritBool(getIntf(), "macosx-video-autoresize") && !var_InheritBool(getIntf(), "video-wallpaper"))
        [self resizeWindow];
}

- (NSSize)windowWillResize:(NSWindow *)window toSize:(NSSize)proposedFrameSize
{
    if (![[VLCMain sharedInstance] activeVideoPlayback] || self.nativeVideoSize.width == 0. || self.nativeVideoSize.height == 0. || window != self)
        return proposedFrameSize;

    // needed when entering lion fullscreen mode
    if (_inFullscreenTransition || [self fullscreen])
        return proposedFrameSize;

    if ([_videoView isHidden])
        return proposedFrameSize;

    /* while the controls are auto-hidden the window IS the picture: keep
     * it exactly that, whatever the aspect-ratio lock says -- letting it
     * go free here would just put black bands back inside the bare
     * window the feature exists to get rid of */
    if (_controlsHiddenForPlayback) {
        proposedFrameSize.height = round(proposedFrameSize.width
            * self.nativeVideoSize.height / self.nativeVideoSize.width);
        /* resizing by hand redefines the box a later crop fits into */
        o_picture_box = proposedFrameSize;
        return proposedFrameSize;
    }

    if ([[VLCCoreInteraction sharedInstance] aspectRatioIsLocked]) {
        NSRect videoWindowFrame = [self frame];
        NSRect viewRect = [_videoView convertRect:[_videoView bounds] toView: nil];
        NSRect contentRect = [self contentRectForFrameRect:videoWindowFrame];
        CGFloat marginy = viewRect.origin.y + videoWindowFrame.size.height - contentRect.size.height;
        CGFloat marginx = contentRect.size.width - viewRect.size.width;
        if (self.titlebarView && _darkInterface)
            marginy += [self.titlebarView frame].size.height;

        proposedFrameSize.height = (proposedFrameSize.width - marginx) * self.nativeVideoSize.height / self.nativeVideoSize.width + marginy;
    }

    /* resizing by hand redefines the box a later crop fits into: the
     * video area is the window minus whatever chrome it carries */
    NSSize chrome = NSMakeSize(
        [self frame].size.width - [_videoView frame].size.width,
        [self frame].size.height - [_videoView frame].size.height);
    o_picture_box = NSMakeSize(proposedFrameSize.width - chrome.width,
                               proposedFrameSize.height - chrome.height);

    return proposedFrameSize;
}

- (void)windowWillMiniaturize:(NSNotification *)notification
{
    // Set level to normal as a workaround for Mavericks bug causing window
    // to vanish from screen, see radar://15473716
    i_originalLevel = [self level];
    [self setLevel: NSNormalWindowLevel];
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
    [self setLevel: i_originalLevel];
}

#pragma mark -
#pragma mark Key events

- (void)flagsChanged:(NSEvent *)theEvent
{
    BOOL b_alt_pressed = ([theEvent modifierFlags] & NSAlternateKeyMask) != 0;
    [self.titlebarView informModifierPressed: b_alt_pressed];

    [super flagsChanged:theEvent];
}

#pragma mark -
#pragma mark Lion native fullscreen handling

- (void)hideControlsBar
{
    [[self.controlsBar bottomBarView] setHidden: YES];
    self.videoViewBottomConstraint.priority = 1;
}

- (void)showControlsBar
{
    [[self.controlsBar bottomBarView] setHidden: NO];
    self.videoViewBottomConstraint.priority = 999;
}

#pragma mark -
#pragma mark Hide controls during playback

- (BOOL)mouseIsInsideWindow
{
    return NSMouseInRect([NSEvent mouseLocation], [self frame], NO);
}

- (BOOL)shouldAutoHideControls
{
    if (![[VLCCoreInteraction sharedInstance] autoHideControls])
        return NO;
    if ([self fullscreen] || _inFullscreenTransition)
        return NO;
    /* the video being on show is the whole condition: a pause hides just
     * as well (the OSD is the feedback then), the playlist view never
     * does */
    return [self hasActiveVideo] && ![self.videoView isHidden];
}

/* The zoom factor the vout is currently applying, 0 when there is no
 * video to ask. */
- (CGFloat)currentVideoZoom
{
    VLCVoutView *videoView = [self videoView];
    vout_thread_t *p_vout = videoView != nil ? [videoView voutThread] : NULL;
    if (p_vout == NULL)
        return 0.;

    const CGFloat zoom = var_GetFloat(p_vout, "zoom");
    vlc_object_release(p_vout);
    return zoom;
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
- (NSSize)pictureSizeForRequest:(NSSize)requested currentArea:(NSSize)area
{
    if (requested.width <= 0. || requested.height <= 0.)
        return NSZeroSize;

    NSSize previous = o_last_requested_video_size;
    o_last_requested_video_size = requested;
    if (NSEqualSizes(previous, requested))
        return NSZeroSize;

    /* Half / Normal / Double, and the hotkeys that do the same, all go
     * through the vout's "zoom": that is how a scale change the *user*
     * asked for is told apart from one the stream decided on its own. */
    const CGFloat zoom = [self currentVideoZoom];
    const CGFloat previous_zoom = f_last_video_zoom;
    f_last_video_zoom = zoom;

    CGFloat ratio = requested.width / requested.height;
    BOOL sameShape = (previous.width > 0. && previous.height > 0.
        && fabs(ratio - previous.width / previous.height) <= ratio * 0.005);

    /* the very first request opens the window at the size of the media,
     * as it always did */
    if (previous.width <= 0. || previous.height <= 0.) {
        o_picture_box = requested;
        return requested;
    }

    if (sameShape) {
        /* ⚠ Same shape, another size, and nobody asked to zoom: this is
         * an adaptive stream switching variant, which it does several
         * times a programme. Following it made the window take the pixel
         * size of each variant and, one step up after another, end up
         * filling the screen on its own. The window belongs to the
         * viewer; only a shape change re-fits it (below). */
        if (zoom <= 0. || zoom == previous_zoom)
            return NSZeroSize;

        o_picture_box = requested;
        return requested;
    }

    NSSize box = o_picture_box;
    if (box.width <= 0. || box.height <= 0.)
        box = area;
    if (box.width <= 0. || box.height <= 0.)
        return requested;
    CGFloat fit = MIN(box.width / requested.width,
                      box.height / requested.height);
    return NSMakeSize(round(requested.width * fit),
                      round(requested.height * fit));
}

- (void)hiddenWindowFollowVideoSize:(NSSize)requested
{
    NSRect frame = [self frame];
    NSSize picture = [self pictureSizeForRequest:requested
                                     currentArea:frame.size];
    if (picture.width <= 0. || picture.height <= 0.)
        return;

    /* keep it on the screen, at the ratio it just took */
    NSRect visible = [[self screen] visibleFrame];
    CGFloat fit = MIN(1., MIN(visible.size.width / picture.width,
                              visible.size.height / picture.height));
    if (fit < 1.) {
        picture.width = round(picture.width * fit);
        picture.height = round(picture.height * fit);
    }
    if (picture.width < 160. || picture.height < 90.)
        return;

    /* grow or shrink from the top left corner, where the eye is */
    frame.origin.y += frame.size.height - picture.height;
    frame.size = picture;
    [self setFrame:[self customConstrainFrameRect:frame toScreen:[self screen]]
           display:YES];
}

/* Hiding waits for the mouse to have been outside the window for 3 s;
 * revealing waits for the video to have been gone for 2.5 s, since the
 * gaps of a loop restart or of an item transition are shorter than that
 * and must not count. Coming back over the window never reveals by
 * itself: that takes a double click on the video. */
- (void)autoHideControlsTick:(NSTimer *)timer
{
    if (_controlsHiddenForPlayback) {
        if (![[VLCCoreInteraction sharedInstance] autoHideControls]
            || [self fullscreen] || _inFullscreenTransition) {
            [self revealControlsForPlayback];
            return;
        }
        if ([self hasActiveVideo] && ![self.videoView isHidden])
            i_autohide_reveal_ticks = 0;
        else if (++i_autohide_reveal_ticks >= 5)
            [self revealControlsForPlayback];
        return;
    }

    i_autohide_reveal_ticks = 0;
    if (![self shouldAutoHideControls] || [self mouseIsInsideWindow]) {
        i_autohide_outside_ticks = 0;
        return;
    }
    if (++i_autohide_outside_ticks >= 6)
        [self hideControlsForPlayback];
}

- (void)hideControlsForPlayback
{
    if (_controlsHiddenForPlayback)
        return;

    /* where the picture sits on screen right now: the window then
     * shrinks onto exactly that rectangle, so the picture neither moves
     * nor changes size when the decorations go away. Starting from the
     * video view, the aspect-ratio correction the vout applies inside it
     * is replayed so its thin black bands go away too. */
    NSRect videoScreenRect = [self convertRectToScreen:
        [self.videoView convertRect:[self.videoView bounds] toView:nil]];
    NSSize nativeSize = [self nativeVideoSize];
    if (nativeSize.width > 0. && nativeSize.height > 0.
        && videoScreenRect.size.width > 0. && videoScreenRect.size.height > 0.) {
        CGFloat scale = MIN(videoScreenRect.size.width / nativeSize.width,
                            videoScreenRect.size.height / nativeSize.height);
        NSSize pictureSize = NSMakeSize(round(nativeSize.width * scale),
                                        round(nativeSize.height * scale));
        videoScreenRect.origin.x +=
            round((videoScreenRect.size.width - pictureSize.width) / 2.);
        videoScreenRect.origin.y +=
            round((videoScreenRect.size.height - pictureSize.height) / 2.);
        videoScreenRect.size = pictureSize;
    }

    /* a video view caught mid-relayout or mid-teardown (playback ending,
     * the playlist view coming and going) measures next to nothing:
     * shrinking the window onto that would leave a sliver behind and
     * there would be no picture to watch anyway */
    if (videoScreenRect.size.width < 160. || videoScreenRect.size.height < 90.)
        return;

    _controlsHiddenForPlayback = YES;
    o_frame_before_hiding_controls = [self frame];
    o_last_requested_video_size = nativeSize;
    o_picture_box = videoScreenRect.size;

    [self hideControlsBar];
    if (self.darkInterface && self.titlebarView) {
        /* same recipe as the fullscreen transition below */
        [self.titlebarView setHidden:YES];
        self.videoViewTopConstraint.priority = 1;
    } else {
        BOOL b_was_key = [self isKeyWindow];
        i_stylemask_before_hiding_controls = [self styleMask];
        [self setStyleMask:(NSBorderlessWindowMask | NSResizableWindowMask)];
        if (b_was_key)
            [self makeKeyAndOrderFront:nil];
    }

    /* borderless frame == content == picture */
    [self setFrame:videoScreenRect display:YES];
    o_hidden_controls_initial_frame = videoScreenRect;

    if ([[self.videoView subviews] count] > 0)
        [self makeFirstResponder:[[self.videoView subviews] firstObject]];

    [[VLCCoreInteraction sharedInstance] setControlsHiddenForPlayback:YES];
}

- (void)revealControlsForPlayback
{
    if (!_controlsHiddenForPlayback)
        return;
    _controlsHiddenForPlayback = NO;

    /* the window before hiding, carried over by whatever the user moved
     * or resized the naked window meanwhile: the picture lands back on
     * the very same pixels it occupies right now */
    NSRect hiddenFrame = [self frame];

    [self showControlsBar];
    if (self.darkInterface && self.titlebarView) {
        [self.titlebarView setHidden:NO];
        self.videoViewTopConstraint.priority = 999;
    } else {
        BOOL b_was_key = [self isKeyWindow];
        [self setStyleMask:i_stylemask_before_hiding_controls];
        if (b_was_key)
            [self makeKeyAndOrderFront:nil];
        /* setStyleMask: wipes the title of a fresh titled frame */
        [super setTitle:[self title]];
    }

    NSRect frame = o_frame_before_hiding_controls;
    frame.origin.x +=
        hiddenFrame.origin.x - o_hidden_controls_initial_frame.origin.x;
    frame.origin.y +=
        hiddenFrame.origin.y - o_hidden_controls_initial_frame.origin.y;
    frame.size.width +=
        hiddenFrame.size.width - o_hidden_controls_initial_frame.size.width;
    frame.size.height +=
        hiddenFrame.size.height - o_hidden_controls_initial_frame.size.height;
    [self setFrame:[self customConstrainFrameRect:frame toScreen:[self screen]]
           display:YES];

    [[VLCCoreInteraction sharedInstance] setControlsHiddenForPlayback:NO];
    /* the delay restarts from zero: the mouse being outside already is
     * not enough to hide again right away */
    i_autohide_outside_ticks = 0;
}

- (void)revealControlsNotification:(NSNotification *)notification
{
    [self revealControlsForPlayback];
}

/* Dragging the picture always moves the window, controls hidden or not
 * (it is the natural grab area, and while the controls are hidden there
 * is no title bar left at all). The events bubble up here from the vout
 * view, which never consumes them; a drag is not a plain click, so
 * nothing is revealed or toggled. */
- (void)mouseDown:(NSEvent *)o_event
{
    _videoDragActive = ![self fullscreen] && !_inFullscreenTransition;
    [super mouseDown:o_event];
}

/* ⚠ Without this the flag stayed on for the rest of the session, and any
 * later drag whose press had been taken by something else moved the
 * window instead of doing its own job. */
- (void)mouseUp:(NSEvent *)o_event
{
    _videoDragActive = NO;
    [super mouseUp:o_event];
}

/* Keeps enough of the window on the screen to grab it again. Dragging a
 * window partly past an edge is normal on macOS; losing it entirely is
 * not, and the picture is the whole grab area here. */
- (NSPoint)dragOriginKeptReachable:(NSPoint)origin
{
    NSRect visible = [[self screen] visibleFrame];
    NSRect frame = [self frame];
    const CGFloat margin = MIN(120., frame.size.width);

    if (origin.x + frame.size.width < NSMinX(visible) + margin)
        origin.x = NSMinX(visible) + margin - frame.size.width;
    if (origin.x > NSMaxX(visible) - margin)
        origin.x = NSMaxX(visible) - margin;

    /* The top edge may never go under the menu bar: from there the window
     * cannot be dragged back by its title bar. */
    if (origin.y + frame.size.height > NSMaxY(visible))
        origin.y = NSMaxY(visible) - frame.size.height;
    if (origin.y + frame.size.height < NSMinY(visible) + MIN(60., frame.size.height))
        origin.y = NSMinY(visible) + MIN(60., frame.size.height) - frame.size.height;

    return origin;
}

- (void)mouseDragged:(NSEvent *)o_event
{
    if (_videoDragActive) {
        /* ⚠ Move by the pointer's own delta, never from an anchor taken
         * at mouse-down: the anchor was read with +[NSEvent mouseLocation],
         * i.e. where the pointer is *when the event is handled*, and this
         * main thread does stall (an adaptive stream fetching its playlist
         * is enough). The pointer has moved by then, and the window jumped
         * by that error on the very first drag -- straight off the screen
         * on a wide monitor. The window can also be resized under the
         * pointer by the stream itself, which an anchor does not survive
         * either. */
        NSPoint origin = [self frame].origin;
        origin.x += [o_event deltaX];
        origin.y -= [o_event deltaY];
        [self setFrameOrigin:[self dragOriginKeptReachable:origin]];
        return;
    }
    [super mouseDragged:o_event];
}

#pragma mark -
#pragma mark Lion native fullscreen handling (continued)

- (void)becomeKeyWindow
{
    [super becomeKeyWindow];

    // change fspanel state for the case when multiple windows are in fullscreen
    if ([self hasActiveVideo] && [self fullscreen])
        [[[[VLCMain sharedInstance] mainWindow] fspanel] setActive];
    else
        [[[[VLCMain sharedInstance] mainWindow] fspanel] setNonActive];
}

- (void)resignKeyWindow
{
    [super resignKeyWindow];

    [[[[VLCMain sharedInstance] mainWindow] fspanel] setNonActive];
}

-(NSArray*)customWindowsToEnterFullScreenForWindow:(NSWindow *)window
{
    if (window == self) {
        return [NSArray arrayWithObject:window];
    }

    return nil;
}

- (NSArray*)customWindowsToExitFullScreenForWindow:(NSWindow*)window
{
    if (window == self) {
        return [NSArray arrayWithObject:window];
    }

    return nil;
}

- (void)window:window startCustomAnimationToEnterFullScreenWithDuration:(NSTimeInterval)duration
{
    [window setStyleMask:([window styleMask] | NSFullScreenWindowMask)];

    NSScreen *screen = [window screen];
    NSRect screenFrame = [screen frame];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:0.5 * duration];
        [[window animator] setFrame:screenFrame display:YES];
    } completionHandler:nil];
}

- (void)window:window startCustomAnimationToExitFullScreenWithDuration:(NSTimeInterval)duration
{
    [window setStyleMask:([window styleMask] & ~NSFullScreenWindowMask)];
    [[window animator] setFrame:frameBeforeLionFullscreen display:YES animate:YES];

    [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
        [context setDuration:0.5 * duration];
        [[window animator] setFrame:frameBeforeLionFullscreen display:YES animate:YES];
    } completionHandler:nil];
}

- (void)windowWillEnterFullScreen:(NSNotification *)notification
{
    /* fullscreen must start from the normal window state: with the
     * controls auto-hidden the style mask / titlebar are not what the
     * transition code expects to save and restore */
    [self revealControlsForPlayback];

    _windowShouldExitFullscreenWhenFinished = [[VLCMain sharedInstance] activeVideoPlayback];

    NSInteger i_currLevel = [self level];
    // self.fullscreen and _inFullscreenTransition must not be true yet
    [[[VLCMain sharedInstance] voutController] updateWindowLevelForHelperWindows: NSNormalWindowLevel];
    [self setLevel:NSNormalWindowLevel];
    i_originalLevel = i_currLevel;

    _inFullscreenTransition = YES;

    var_SetBool(pl_Get(getIntf()), "fullscreen", true);

    frameBeforeLionFullscreen = [self frame];

    if ([self hasActiveVideo]) {
        vout_thread_t *p_vout = getVoutForActiveWindow();
        if (p_vout) {
            var_SetBool(p_vout, "fullscreen", true);
            vlc_object_release(p_vout);
        }
    }

    if (_darkInterface) {
        [self.titlebarView setHidden:YES];
        self.videoViewTopConstraint.priority = 1;

        // shrink window height
        CGFloat f_titleBarHeight = [self.titlebarView frame].size.height;
        NSRect winrect = [self frame];

        winrect.size.height = winrect.size.height - f_titleBarHeight;
        [self setFrame: winrect display:NO animate:NO];
    }

    if (![_videoView isHidden]) {
        [self hideControlsBar];
    }

    [self setMovableByWindowBackground: NO];
}

- (void)windowDidEnterFullScreen:(NSNotification *)notification
{
    // Indeed, we somehow can have an "inactive" fullscreen (but a visible window!).
    // But this creates some problems when leaving fs over remote intfs, so activate app here.
    [NSApp activateIgnoringOtherApps:YES];

    [self setFullscreen: YES];
    _inFullscreenTransition = NO;

    if ([self hasActiveVideo]) {
        [[[[VLCMain sharedInstance] mainWindow] fspanel] setVoutWasUpdated:self];
        if (![_videoView isHidden])
            [[[[VLCMain sharedInstance] mainWindow] fspanel] setActive];
    }

    NSArray *subviews = [[self videoView] subviews];
    NSUInteger count = [subviews count];

    for (NSUInteger x = 0; x < count; x++) {
        if ([[subviews objectAtIndex:x] respondsToSelector:@selector(reshape)])
            [[subviews objectAtIndex:x] reshape];
    }
}

- (void)windowWillExitFullScreen:(NSNotification *)notification
{
    _inFullscreenTransition = YES;
    [self setFullscreen: NO];

    if ([self hasActiveVideo]) {
        var_SetBool(pl_Get(getIntf()), "fullscreen", false);

        vout_thread_t *p_vout = getVoutForActiveWindow();
        if (p_vout) {
            var_SetBool(p_vout, "fullscreen", false);
            vlc_object_release(p_vout);
        }
    }

    [NSCursor setHiddenUntilMouseMoves: NO];
    [[[[VLCMain sharedInstance] mainWindow] fspanel] setNonActive];

    if (_darkInterface) {
        [self.titlebarView setHidden:NO];
        self.videoViewTopConstraint.priority = 999;

        NSRect winrect = [self frame];
        CGFloat f_titleBarHeight = [self.titlebarView frame].size.height;
        winrect.size.height = winrect.size.height + f_titleBarHeight;
        [self setFrame: winrect display:NO animate:NO];
    }

    if (![_videoView isHidden]) {
        [self showControlsBar];
    }

    [self setMovableByWindowBackground: YES];
}

- (void)windowDidExitFullScreen:(NSNotification *)notification
{
    _inFullscreenTransition = NO;

    [[[VLCMain sharedInstance] voutController] updateWindowLevelForHelperWindows: i_originalLevel];
    [self setLevel:i_originalLevel];
}

#pragma mark -
#pragma mark Fullscreen Logic

- (NSRect)transformRect:(NSRect)src withSafeAreaFromScreen:(NSScreen *)screen multiplier:(CGFloat)multiplier
{
    if (@available (macOS 12, *)) {
        NSEdgeInsets insets = screen.safeAreaInsets;
        src.size.height -= multiplier * insets.top;
    }

    return src;
}

- (void)enterFullscreenWithAnimation:(BOOL)b_animation
{
    /* see -windowWillEnterFullScreen: */
    [self revealControlsForPlayback];

    NSMutableDictionary *dict1, *dict2;
    NSScreen *screen;
    NSRect screen_rect;
    NSRect rect;
    BOOL blackout_other_displays = var_InheritBool(getIntf(), "macosx-black");

    int64_t stereoDisplay = var_InheritInteger(getIntf(),
                                                "stereo3d-fullscreen-display");
    int64_t doviDisplay = var_InheritInteger(getIntf(),
                                             "dovi-fullscreen-display");
    int64_t configuredDisplay = var_InheritInteger(getIntf(), "macosx-vdev");
    screen = [NSScreen screenWithDisplayID:(CGDirectDisplayID)
              (stereoDisplay > 0 ? stereoDisplay :
               doviDisplay > 0 ? doviDisplay : configuredDisplay)];

    if (!screen) {
        msg_Dbg(getIntf(), "chosen screen isn't present, using current screen for fullscreen mode");
        screen = [self screen];
    }
    if (!screen) {
        msg_Dbg(getIntf(), "Using deepest screen");
        screen = [NSScreen deepestScreen];
    }

    screen_rect = [screen frame];
    // Cut of safe area at the top of the screen
    screen_rect = [self transformRect:screen_rect withSafeAreaFromScreen:screen multiplier:+1.];

    if (self.controlsBar)
        [self.controlsBar setFullscreenState:YES];
    [[[[VLCMain sharedInstance] mainWindow] controlsBar] setFullscreenState:YES];

    if (blackout_other_displays)
        [screen blackoutOtherScreens];

    /* Make sure we don't see the window flashes in float-on-top mode */
    NSInteger i_currLevel = [self level];
    // self.fullscreen must not be true yet
    [[[VLCMain sharedInstance] voutController] updateWindowLevelForHelperWindows: NSNormalWindowLevel];
    [self setLevel:NSNormalWindowLevel];
    i_originalLevel = i_currLevel; // would be overwritten by previous call

    /* Only create the o_fullscreen_window if we are not in the middle of the zooming animation */
    if (!o_fullscreen_window) {
        /* We can't change the styleMask of an already created NSWindow, so we create another window, and do eye catching stuff */

        rect = [[_videoView superview] convertRect: [_videoView frame] toView: nil]; /* Convert to Window base coord */
        rect.origin.x += [self frame].origin.x;
        rect.origin.y += [self frame].origin.y;

        o_fullscreen_window = [[VLCWindow alloc] initWithContentRect:rect styleMask: NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:YES];
        [o_fullscreen_window setBackgroundColor: [NSColor blackColor]];
        [o_fullscreen_window setCanBecomeKeyWindow: YES];
        [o_fullscreen_window setCanBecomeMainWindow: YES];
        [o_fullscreen_window setHasActiveVideo: YES];
        [o_fullscreen_window setFullscreen: YES];

        /* Make sure video view gets visible in case the playlist was visible before */
        b_video_view_was_hidden = [_videoView isHidden];
        [_videoView setHidden: NO];
        _videoView.translatesAutoresizingMaskIntoConstraints = YES;

        if (!b_animation) {
            /* We don't animate if we are not visible, instead we
             * simply fade the display */
            CGDisplayFadeReservationToken token;

            if (blackout_other_displays) {
                CGAcquireDisplayFadeReservation(kCGMaxDisplayReservationInterval, &token);
                CGDisplayFade(token, 0.5, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0, 0, 0, YES);
            }

            NSDisableScreenUpdates();
            [[_videoView superview] replaceSubview:_videoView with:o_temp_view];
            [o_temp_view setFrame:[_videoView frame]];
            [[o_fullscreen_window contentView] addSubview:_videoView];
            [_videoView setFrame: [[o_fullscreen_window contentView] frame]];
            [_videoView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
            NSEnableScreenUpdates();

            [screen setFullscreenPresentationOptions];

            [o_fullscreen_window setFrame:screen_rect display:YES animate:NO];

            [o_fullscreen_window orderFront:self animate:YES];

            [o_fullscreen_window setLevel:NSNormalWindowLevel];

            if (blackout_other_displays) {
                CGDisplayFade(token, 0.3, kCGDisplayBlendSolidColor, kCGDisplayBlendNormal, 0, 0, 0, NO);
                CGReleaseDisplayFadeReservation(token);
            }

            /* Will release the lock */
            [self hasBecomeFullscreen];

            return;
        }

        /* Make sure we don't see the _videoView disappearing of the screen during this operation */
        NSDisableScreenUpdates();
        [[_videoView superview] replaceSubview:_videoView with:o_temp_view];
        [o_temp_view setFrame:[_videoView frame]];
        [[o_fullscreen_window contentView] addSubview:_videoView];
        [_videoView setFrame: [[o_fullscreen_window contentView] frame]];
        [_videoView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

        [o_fullscreen_window makeKeyAndOrderFront:self];
        NSEnableScreenUpdates();
    }

    /* We are in fullscreen (and no animation is running) */
    if ([self fullscreen]) {
        /* Make sure we are hidden */
        [self orderOut: self];

        return;
    }

    if (o_fullscreen_anim1) {
        [o_fullscreen_anim1 stopAnimation];
    }
    if (o_fullscreen_anim2) {
        [o_fullscreen_anim2 stopAnimation];
    }

    [screen setFullscreenPresentationOptions];

    dict1 = [[NSMutableDictionary alloc] initWithCapacity:2];
    dict2 = [[NSMutableDictionary alloc] initWithCapacity:3];

    [dict1 setObject:self forKey:NSViewAnimationTargetKey];
    [dict1 setObject:NSViewAnimationFadeOutEffect forKey:NSViewAnimationEffectKey];

    [dict2 setObject:o_fullscreen_window forKey:NSViewAnimationTargetKey];
    [dict2 setObject:[NSValue valueWithRect:[o_fullscreen_window frame]] forKey:NSViewAnimationStartFrameKey];
    [dict2 setObject:[NSValue valueWithRect:screen_rect] forKey:NSViewAnimationEndFrameKey];

    /* Strategy with NSAnimation allocation:
     - Keep at most 2 animation at a time
     - leaveFullscreen/enterFullscreen are the only responsible for releasing and alloc-ing
     */
    o_fullscreen_anim1 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict1]];
    o_fullscreen_anim2 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict2]];

    [o_fullscreen_anim1 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim1 setDuration: 0.3];
    [o_fullscreen_anim1 setFrameRate: 30];
    [o_fullscreen_anim2 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim2 setDuration: 0.2];
    [o_fullscreen_anim2 setFrameRate: 30];

    [o_fullscreen_anim2 setDelegate: self];
    [o_fullscreen_anim2 startWhenAnimation: o_fullscreen_anim1 reachesProgress: 1.0];

    [o_fullscreen_anim1 startAnimation];
    /* fullscreenAnimation will be unlocked when animation ends */

    _inFullscreenTransition = YES;
}

- (void)hasBecomeFullscreen
{
    // Cover the top of the screen with the black window
    NSRect window_frame = [self transformRect:o_fullscreen_window.frame withSafeAreaFromScreen:o_fullscreen_window.screen multiplier:-1.];
    [o_fullscreen_window setFrame:window_frame display:YES];

    NSRect video_frame = [self transformRect:_videoView.frame withSafeAreaFromScreen:o_fullscreen_window.screen multiplier:+1.];
    _videoView.frame = video_frame;

    if ([[_videoView subviews] count] > 0)
        [o_fullscreen_window makeFirstResponder: [[_videoView subviews] firstObject]];

    [o_fullscreen_window makeKeyWindow];
    [o_fullscreen_window setAcceptsMouseMovedEvents: YES];

    /* tell the fspanel to move itself to front next time it's triggered */
    [[[[VLCMain sharedInstance] mainWindow] fspanel] setVoutWasUpdated:o_fullscreen_window];
    [[[[VLCMain sharedInstance] mainWindow] fspanel] setActive];

    if ([self isVisible])
        [self orderOut: self];

    _inFullscreenTransition = NO;
    [self setFullscreen:YES];
}

- (void)leaveFullscreenWithAnimation:(BOOL)b_animation
{
    NSMutableDictionary *dict1, *dict2;
    NSRect frame;
    BOOL blackout_other_displays = var_InheritBool(getIntf(), "macosx-black");

    if (self.controlsBar)
        [self.controlsBar setFullscreenState:NO];
    [[[[VLCMain sharedInstance] mainWindow] controlsBar] setFullscreenState:NO];

    /* We always try to do so */
    [NSScreen unblackoutScreens];

    [[_videoView window] makeKeyAndOrderFront: nil];

    /* Don't do anything if o_fullscreen_window is already closed */
    if (!o_fullscreen_window) {
        return;
    }

    // Convert black safe area from top screen
    NSRect window_frame = [self transformRect:o_fullscreen_window.frame withSafeAreaFromScreen:o_fullscreen_window.screen multiplier:+1.];
    [o_fullscreen_window setFrame:window_frame display:YES];

    NSRect video_frame = [self transformRect:_videoView.frame withSafeAreaFromScreen:o_fullscreen_window.screen multiplier:-1.];
    _videoView.frame = video_frame;

    [[[[VLCMain sharedInstance] mainWindow] fspanel] setNonActive];
    [NSCursor setHiddenUntilMouseMoves:NO];
    [[o_fullscreen_window screen] setNonFullscreenPresentationOptions];

    if (o_fullscreen_anim1) {
        [o_fullscreen_anim1 stopAnimation];
        o_fullscreen_anim1 = nil;
    }
    if (o_fullscreen_anim2) {
        [o_fullscreen_anim2 stopAnimation];
        o_fullscreen_anim2 = nil;
    }

    _inFullscreenTransition = YES;
    [self setFullscreen:NO];

    if (!b_animation) {
        /* We don't animate if we are not visible, instead we
         * simply fade the display */
        CGDisplayFadeReservationToken token;

        if (blackout_other_displays) {
            CGAcquireDisplayFadeReservation(kCGMaxDisplayReservationInterval, &token);
            CGDisplayFade(token, 0.3, kCGDisplayBlendNormal, kCGDisplayBlendSolidColor, 0, 0, 0, YES);
        }

        [self setAlphaValue:1.0];
        [self orderFront: self];

        /* Will release the lock */
        [self hasEndedFullscreen];

        if (blackout_other_displays) {
            CGDisplayFade(token, 0.5, kCGDisplayBlendSolidColor, kCGDisplayBlendNormal, 0, 0, 0, NO);
            CGReleaseDisplayFadeReservation(token);
        }

        return;
    }

    [self setAlphaValue: 0.0];
    [self orderFront: self];
    [[_videoView window] orderFront: self];

    frame = [[o_temp_view superview] convertRect: [o_temp_view frame] toView: nil]; /* Convert to Window base coord */
    frame.origin.x += [self frame].origin.x;
    frame.origin.y += [self frame].origin.y;

    dict2 = [[NSMutableDictionary alloc] initWithCapacity:2];
    [dict2 setObject:self forKey:NSViewAnimationTargetKey];
    [dict2 setObject:NSViewAnimationFadeInEffect forKey:NSViewAnimationEffectKey];

    o_fullscreen_anim2 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict2]];

    [o_fullscreen_anim2 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim2 setDuration: 0.3];
    [o_fullscreen_anim2 setFrameRate: 30];

    [o_fullscreen_anim2 setDelegate: self];

    dict1 = [[NSMutableDictionary alloc] initWithCapacity:3];

    [dict1 setObject:o_fullscreen_window forKey:NSViewAnimationTargetKey];
    [dict1 setObject:[NSValue valueWithRect:[o_fullscreen_window frame]] forKey:NSViewAnimationStartFrameKey];
    [dict1 setObject:[NSValue valueWithRect:frame] forKey:NSViewAnimationEndFrameKey];

    o_fullscreen_anim1 = [[NSViewAnimation alloc] initWithViewAnimations:[NSArray arrayWithObject:dict1]];

    [o_fullscreen_anim1 setAnimationBlockingMode: NSAnimationNonblocking];
    [o_fullscreen_anim1 setDuration: 0.2];
    [o_fullscreen_anim1 setFrameRate: 30];
    [o_fullscreen_anim2 startWhenAnimation: o_fullscreen_anim1 reachesProgress: 1.0];

    /* Make sure o_fullscreen_window is the frontmost window */
    [o_fullscreen_window orderFront: self];

    [o_fullscreen_anim1 startAnimation];
    /* fullscreenAnimation will be unlocked when animation ends */
}

- (void)hasEndedFullscreen
{
    _inFullscreenTransition = NO;
    [NSCursor setHiddenUntilMouseMoves:NO];

    /* This function is private and should be only triggered at the end of the fullscreen change animation */
    /* Make sure we don't see the _videoView disappearing of the screen during this operation */
    NSDisableScreenUpdates();
    [_videoView removeFromSuperviewWithoutNeedingDisplay];
    [[o_temp_view superview] replaceSubview:o_temp_view with:_videoView];
    // TODO Replace tmpView by an existing view (e.g. middle view)
    // TODO Use constraints for fullscreen window, reinstate constraints once the video view is added to the main window again
    [_videoView setFrame:[o_temp_view frame]];
    if ([[_videoView subviews] count] > 0)
        [self makeFirstResponder: [[_videoView subviews] firstObject]];

    [_videoView setHidden: b_video_view_was_hidden];

    [self makeKeyAndOrderFront:self];

    [o_fullscreen_window orderOut: self];
    NSEnableScreenUpdates();

    o_fullscreen_window = nil;

    [[[VLCMain sharedInstance] voutController] updateWindowLevelForHelperWindows: i_originalLevel];
    [self setLevel:i_originalLevel];

    [self setAlphaValue: config_GetFloat(getIntf(), "macosx-opaqueness")];
}

- (void)animationDidEnd:(NSAnimation*)animation
{
    NSArray *viewAnimations;
    if ([animation currentValue] < 1.0)
        return;

    /* Fullscreen ended or started (we are a delegate only for leaveFullscreen's/enterFullscren's anim2) */
    viewAnimations = [o_fullscreen_anim2 viewAnimations];
    if ([viewAnimations count] >=1 &&
        [[[viewAnimations firstObject] objectForKey: NSViewAnimationEffectKey] isEqualToString:NSViewAnimationFadeInEffect]) {
        /* Fullscreen ended */
        [self hasEndedFullscreen];
    } else {
        /* Fullscreen started */
        [self hasBecomeFullscreen];
    }
}

#pragma mark -
#pragma mark Accessibility stuff

- (NSArray *)accessibilityAttributeNames
{
    if (!_darkInterface || !self.titlebarView)
        return [super accessibilityAttributeNames];

    static NSMutableArray *attributes = nil;
    if (attributes == nil) {
        attributes = [[super accessibilityAttributeNames] mutableCopy];
        NSArray *appendAttributes = [NSArray arrayWithObjects:NSAccessibilitySubroleAttribute,
                                     NSAccessibilityCloseButtonAttribute,
                                     NSAccessibilityMinimizeButtonAttribute,
                                     NSAccessibilityZoomButtonAttribute, nil];

        for(NSString *attribute in appendAttributes) {
            if (![attributes containsObject:attribute])
                [attributes addObject:attribute];
        }
    }
    return attributes;
}

- (id)accessibilityAttributeValue: (NSString*)o_attribute_name
{
    if (_darkInterface && self.titlebarView) {
        VLCMainWindowTitleView *o_tbv = self.titlebarView;

        if ([o_attribute_name isEqualTo: NSAccessibilitySubroleAttribute])
            return NSAccessibilityStandardWindowSubrole;

        if ([o_attribute_name isEqualTo: NSAccessibilityCloseButtonAttribute])
            return [[o_tbv closeButton] cell];

        if ([o_attribute_name isEqualTo: NSAccessibilityMinimizeButtonAttribute])
            return [[o_tbv minimizeButton] cell];

        if ([o_attribute_name isEqualTo: NSAccessibilityZoomButtonAttribute])
            return [[o_tbv zoomButton] cell];
    }

    return [super accessibilityAttributeValue: o_attribute_name];
}

@end
