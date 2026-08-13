/*****************************************************************************
 * VLCFSPanelController.m: macOS fullscreen controls window controller
 *****************************************************************************
 * Copyright (C) 2006-2016 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Jérôme Decoodt <djc at videolan dot org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
 *          Marvin Scholz <epirat07 at gmail dot com>
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

#import "VLCFSPanelController.h"
#import "VLCCoreInteraction.h"
#import "CompatibilityFixes.h"
#import "VLCMain.h"
#import "VLCSeekThumbnailer.h"

@interface VLCFSPanelController () {
    BOOL _isCounting;
    BOOL _isFadingIn;

    // Only used to track changes and trigger centering of FS panel
    NSRect _associatedVoutFrame;
    // Used to ask for current constraining rect on movement
    NSWindow *_associatedVoutWindow;

    int _chaptersRetryTicks;
    /* identité seule, jamais déréférencée (cf. -updateChapters) */
    char *_chaptersUri;     /* identité du média, cf. -updateChapters */
}

@end

@implementation VLCFSPanelController

static NSString *kAssociatedFullscreenRect = @"VLCFullscreenAssociatedWindowRect";

+ (void)initialize
{
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys: NSStringFromRect(NSZeroRect), kAssociatedFullscreenRect, nil];

    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
}


#pragma mark -
#pragma mark Initialization

- (id)init
{
    self = [super initWithWindowNibName:@"VLCFullScreenPanel"];
    if (self) {
        NSString *rectStr = [[NSUserDefaults standardUserDefaults] stringForKey:kAssociatedFullscreenRect];
        _associatedVoutFrame = NSRectFromString(rectStr);
    }
    return self;
}

- (void)windowDidLoad
{
    [super windowDidLoad];

    /* Do some window setup that is not possible in IB */
    [self.window setOpaque:NO];
    [self.window setAlphaValue:0.0f];
    [self.window setMovableByWindowBackground:NO];
    [self.window setLevel:NSModalPanelWindowLevel];
    [self.window setStyleMask:self.window.styleMask | NSResizableWindowMask];
    [self.window setBackgroundColor:[NSColor clearColor]];

    /* Set autosave name after we changed window mask to resizable */
    [self.window setFrameAutosaveName:@"VLCFullscreenControls"];

#ifdef MAC_OS_X_VERSION_10_10
    /* Inject correct background view depending on OS support */
    if (OSX_YOSEMITE_AND_HIGHER) {
        [self injectVisualEffectView];

        // Large panel configuration (only for modern macOS versions)
        if (var_InheritBool(getIntf(), "macosx-large-text")) {
            NSFont *textFont = [NSFont systemFontOfSize:16.];

            self.mediaTitle.font = textFont;
            self.elapsedTime.font = textFont;
            self.remainingOrTotalTime.font = textFont;

            [_heightMaxConstraint setConstant:42. + 8.];
        }

    } else {
        [self injectBackgroundView];
    }
#else
    /* Compiled with old SDK, always use legacy style */
    [self injectBackgroundView];
#endif

    [self setupControls];
}

#define setupButton(target, title, desc)                                              \
    [target accessibilitySetOverrideValue:title                                       \
                             forAttribute:NSAccessibilityTitleAttribute];             \
    [target accessibilitySetOverrideValue:desc                                        \
                             forAttribute:NSAccessibilityDescriptionAttribute];       \
    [target setToolTip:title];

- (void)setupControls
{
    /* Setup translations for buttons */
    setupButton(_playPauseButton,
                _NS("Play/Pause"),
                _NS("Play/Pause the current media"));
    setupButton(_nextButton,
                _NS("Next"),
                _NS("Go to next item"));
    setupButton(_previousButton,
                _NS("Previous"),
                _NS("Go to the previous item"));
    setupButton(_forwardButton,
                _NS("Forward"),
                _NS("Seek forward"));
    setupButton(_backwardButton,
                _NS("Backward"),
                _NS("Seek backward"));
    setupButton(_fullscreenButton,
                _NS("Leave fullscreen"),
                _NS("Leave fullscreen"));
    setupButton(_volumeSlider,
                _NS("Volume"),
                _NS("Adjust the volume"));
    /* no static tooltip on the time slider: it shows the live
     * time/chapter/preview tooltip on hover, like the main window bar */
    [_timeSlider accessibilitySetOverrideValue:_NS("Position")
                                  forAttribute:NSAccessibilityTitleAttribute];
    [_timeSlider accessibilitySetOverrideValue:
        _NS("Adjust the current playback position")
                                  forAttribute:NSAccessibilityDescriptionAttribute];
    [_timeSlider setSliderStyleDark];
    [_timeSlider setHoverDelegate:self];

    /* Setup other controls */
    [_volumeSlider setMaxValue:[[VLCCoreInteraction sharedInstance] maxVolume]];
    [_volumeSlider setIntValue:AOUT_VOLUME_DEFAULT];
    [_volumeSlider setDefaultValue:AOUT_VOLUME_DEFAULT];

    /* Identifier to store the state of the remaining or total time label,
     * this is the same identifier as used for the window playback cotrols
     * so the state is shared between those.
     */
    [_remainingOrTotalTime setRemainingIdentifier:@"DisplayTimeAsTimeRemaining"];

    /* chapter separators on the seek bar, refetched with the input and on
     * title/chapter changes (parity with the main window bar and the Qt
     * fullscreen controller) */
    NSNotificationCenter *center = [NSNotificationCenter defaultCenter];
    [center addObserver:self
               selector:@selector(fsChaptersPossiblyChanged:)
                   name:VLCInputChangedNotification
                 object:nil];
    [center addObserver:self
               selector:@selector(fsChaptersPossiblyChanged:)
                   name:VLCInputTitleChangedNotification
                 object:nil];
    /* the clip creation mode drives this seek bar exactly like the one of
     * the windowed controls: two knobs for the bounds, a marker for the
     * playback position */
    [center addObserver:self
               selector:@selector(clipCreationModeChanged:)
                   name:VLCClipCreationModeChangedNotification
                 object:nil];
    [self updateChapters];
    [self syncClipCreationMode];
}

#pragma mark -
#pragma mark Clip creation mode (same behaviour as the windowed controls)

- (void)clipCreationModeChanged:(NSNotification *)aNotification
{
    [self syncClipCreationMode];
}

- (void)syncClipCreationMode
{
    VLCCoreInteraction *coreInteraction = [VLCCoreInteraction sharedInstance];
    if ([coreInteraction clipCreationMode]) {
        [_timeSlider setClipEndValue:[coreInteraction clipEndPosition] * 10000.];
        [_timeSlider setFloatValue:(float)([coreInteraction clipStartPosition] * 10000.)];
        [_timeSlider setPlaybackMarkerValue:[coreInteraction clipStartPosition] * 10000.];
        [_timeSlider setClipKnobsActive:YES];
    } else {
        [_timeSlider setClipKnobsActive:NO];
        [self updatePositionAndTime];
    }
}

- (void)fsChaptersPossiblyChanged:(NSNotification *)aNotification
{
    [self updateChapters];
}

/* same INPUT_GET_TITLE_INFO rules as VLCControlsBarCommon: only usable
 * when the seekpoints carry time offsets */
- (void)updateChapters
{
    NSArray *fractions = nil;
    NSArray *names = nil;

    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (p_input) {
        vlc_tick_t duration = input_item_GetDuration(input_GetItem(p_input));
        input_title_t *p_title = NULL;
        int i_title_id = -1;
        if (duration > 0
            && input_Control(p_input, INPUT_GET_TITLE_INFO, &p_title, &i_title_id)
               == VLC_SUCCESS && p_title) {
            if (p_title->i_seekpoint > 1
                && p_title->seekpoint[p_title->i_seekpoint - 1]->i_time_offset > 0) {
                NSMutableArray *mutableFractions =
                    [NSMutableArray arrayWithCapacity:p_title->i_seekpoint];
                NSMutableArray *mutableNames =
                    [NSMutableArray arrayWithCapacity:p_title->i_seekpoint];
                for (int i = 0; i < p_title->i_seekpoint; i++) {
                    seekpoint_t *point = p_title->seekpoint[i];
                    [mutableFractions addObject:
                        [NSNumber numberWithDouble:
                            (double)point->i_time_offset / (double)duration]];
                    /* cf. VLCControlsBarCommon : nommer les chapitres
                     * anonymes plutôt que de laisser le survol vide */
                    [mutableNames addObject:
                        (point->psz_name != NULL && *point->psz_name != '\0')
                        ? toNSStr(point->psz_name)
                        : [NSString stringWithFormat:_NS("Chapter %i"), i + 1]];
                }
                fractions = mutableFractions;
                names = mutableNames;
            }
            vlc_input_title_Delete(p_title);
        } else if (p_title) {
            vlc_input_title_Delete(p_title);
        }
        vlc_object_release(p_input);
    }

    /* même garde que VLCControlsBarCommon : un résultat vide sur la MÊME
     * entrée veut dire « pas maintenant » (la durée d'un DVD retombe
     * transitoirement à zéro), surtout pas « il n'y a plus de chapitres » */
    /* ⚠⚠⚠ Identifier le média par son URI et non par le pointeur d'entrée :
     * un `input_thread_t` neuf retombe souvent à l'adresse de celui qu'on
     * vient de fermer, si bien que deux fichiers successifs passaient pour le
     * même — et la garde ci-dessous laissait alors les marqueurs du PRÉCÉDENT
     * sur un fichier sans chapitres. */
    char *psz_uri = NULL;
    if (p_input != NULL) {
        input_item_t *p_item = input_GetItem(p_input);
        if (p_item != NULL)
            psz_uri = input_item_GetURI(p_item);
    }
    BOOL sameMedia = (psz_uri != NULL && _chaptersUri != NULL
                      && strcmp(psz_uri, _chaptersUri) == 0);
    if (!sameMedia) {
        free(_chaptersUri);
        _chaptersUri = psz_uri;
        psz_uri = NULL;
    }
    free(psz_uri);

    if (fractions == nil && sameMedia
        && [_timeSlider chapterFractions] != nil)
        return;

    [_timeSlider setChapterFractions:fractions];
    [_timeSlider setChapterNames:names];
}

#pragma mark -
#pragma mark Hover thumbnails (delegate of the time slider)

- (void)slider:(VLCSlider *)slider hoverThumbnailWantedAtFraction:(double)fraction
{
    [[VLCSeekThumbnailer sharedInstance] thumbnailAtFraction:fraction
                                                  completion:^(NSImage *image, double f) {
        if (image)
            [slider setHoverThumbnail:image forFraction:f];
    }];
}

- (void)sliderHoverEnded:(VLCSlider *)slider
{
    /* pending requests die of old age (generation counter) */
}

#undef setupButton

#pragma mark -
#pragma mark Control Actions

- (IBAction)togglePlayPause:(id)sender
{
    [[VLCCoreInteraction sharedInstance] playOrPause];
}

- (IBAction)jumpForward:(id)sender
{
    static NSTimeInterval last_event = 0;
    if (([NSDate timeIntervalSinceReferenceDate] - last_event) > 0.16) {
        /* We just skipped 4 "continuous" events, otherwise we are too fast */
        [[VLCCoreInteraction sharedInstance] forwardExtraShort];
        last_event = [NSDate timeIntervalSinceReferenceDate];
    }
}

- (IBAction)jumpBackward:(id)sender
{
    static NSTimeInterval last_event = 0;
    if (([NSDate timeIntervalSinceReferenceDate] - last_event) > 0.16) {
        /* We just skipped 4 "continuous" events, otherwise we are too fast */
        [[VLCCoreInteraction sharedInstance] backwardExtraShort];
        last_event = [NSDate timeIntervalSinceReferenceDate];
    }
}

- (IBAction)gotoPrevious:(id)sender
{
    [[VLCCoreInteraction sharedInstance] previous];
}

- (IBAction)gotoNext:(id)sender
{
    [[VLCCoreInteraction sharedInstance] next];
}

- (IBAction)toggleFullscreen:(id)sender
{
    [[VLCCoreInteraction sharedInstance] toggleFullscreen];
}

- (IBAction)timeSliderUpdate:(id)sender
{
    switch([[NSApp currentEvent] type]) {
        case NSLeftMouseUp:
            /* Ignore mouse up, as this is a continuous slider and
             * when the user does a single click to a position on the slider,
             * the action is called twice, once for the mouse down and once
             * for the mouse up event. This results in two short seeks one
             * after another to the same position, which results in weird
             * audio quirks.
             */
            return;
        case NSLeftMouseDown:
        case NSLeftMouseDragged:
            break;

        default:
            return;
    }
    input_thread_t *p_input;
    p_input = pl_CurrentInput(getIntf());

    if (p_input) {
        vlc_value_t pos;
        VLCCoreInteraction *coreInteraction = [VLCCoreInteraction sharedInstance];
        if ([coreInteraction clipCreationMode]) {
            /* both knobs define the clip bounds; moving either one seeks
             * there so the user previews what the clip will contain
             * (routing identical to VLCControlsBarCommon) */
            [coreInteraction noteClipInteraction];
            float f_updated;
            NSInteger activeKnob = [_timeSlider activeClipKnob];
            if (activeKnob == 2) {
                f_updated = (float)[_timeSlider clipEndValue];
                [coreInteraction setClipEndPosition:f_updated / 10000.];
                [coreInteraction setClipSelectedKnob:2];
            } else if (activeKnob == 3) {
                /* scrub between the bounds: seek only, bounds untouched */
                f_updated = (float)[_timeSlider playbackMarkerValue];
            } else {
                f_updated = [_timeSlider floatValue];
                [coreInteraction setClipStartPosition:f_updated / 10000.];
                [coreInteraction setClipSelectedKnob:1];
            }
            pos.f_float = f_updated / 10000.;
        } else {
            pos.f_float = [_timeSlider floatValue] / 10000.;
        }
        var_Set(p_input, "position", pos);
        vlc_object_release(p_input);
    }
    [[[VLCMain sharedInstance] mainWindow] updateTimeSlider];
}

- (IBAction)volumeSliderUpdate:(id)sender
{
    [[VLCCoreInteraction sharedInstance] setVolume:[sender intValue]];
}

#pragma mark -
#pragma mark Metadata and state updates

- (void)setPlay
{
    [_playPauseButton setState:NSOffState];
    [_playPauseButton setToolTip: _NS("Play")];
}

- (void)setPause
{
    [_playPauseButton setState:NSOnState];
    [_playPauseButton setToolTip: _NS("Pause")];
}

- (void)setStreamTitle:(NSString *)title
{
    [_mediaTitle setStringValue:title];
}

- (void)updatePositionAndTime
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());

    /* If nothing is playing, reset times and slider */
    if (!p_input) {
        [_timeSlider setFloatValue:0.0];
        [_timeSlider setMediaDuration:0.];
        [_elapsedTime setStringValue:@""];
        [_remainingOrTotalTime setHidden:YES];
        return;
    }

    /* même rattrapage que VLCControlsBarCommon : les décalages temporels des
     * points de chapitre d'un DVD arrivent APRÈS les deux notifications qui
     * déclenchent -updateChapters, et la barre restait sans marqueur */
    if ([_timeSlider chapterFractions] == nil && ++_chaptersRetryTicks >= 8) {
        _chaptersRetryTicks = 0;
        [self updateChapters];
    }

    vlc_value_t pos;
    char psz_time[MSTRTIME_MAX_SIZE];

    var_Get(p_input, "position", &pos);
    float f_updated = 10000. * pos.f_float;
    VLCCoreInteraction *coreInteraction = [VLCCoreInteraction sharedInstance];
    if ([coreInteraction clipCreationMode]) {
        /* the knobs hold the clip bounds; only the thin marker follows
         * the playback position */
        [_timeSlider setPlaybackMarkerValue:f_updated];
        [_timeSlider setFloatValue:(float)([coreInteraction clipStartPosition] * 10000.)];
        [_timeSlider setClipEndValue:[coreInteraction clipEndPosition] * 10000.];
    } else {
        [_timeSlider setFloatValue:f_updated];
    }


    int64_t t = var_GetInteger(p_input, "time");
    vlc_tick_t dur = input_item_GetDuration(input_GetItem(p_input));

    /* the hover tooltip needs the duration to turn a position into a time:
     * without it the slider shows nothing at all (parity with the main
     * window controls bar) */
    [_timeSlider setMediaDuration:(dur > 0 ? (double)dur / CLOCK_FREQ : 0.)];

    /* Update total duration (right field) */
    if (dur <= 0) {
        [_remainingOrTotalTime setHidden:YES];
    } else {
        [_remainingOrTotalTime setHidden:NO];

        vlc_tick_t remaining = 0;
        if (dur > t)
            remaining = dur - t;
        NSString *remainingTime = [NSString stringWithFormat:@"-%s", secstotimestr(psz_time, (remaining / 1000000))];
        NSString *totalTime = toNSStr(secstotimestr(psz_time, (dur / 1000000)));

        [_remainingOrTotalTime setTime:totalTime withRemainingTime:remainingTime];
    }

    /* Update current position (left field) */
    NSString *playbackPosition = toNSStr(secstotimestr(psz_time, t / CLOCK_FREQ));

    [_elapsedTime setStringValue:playbackPosition];
    vlc_object_release(p_input);
}

- (void)setSeekable:(BOOL)seekable
{
    // Workaround graphical issues in Mojave.
    // TODO: This needs a proper fix
    [_forwardButton setEnabled:NO];
    [_backwardButton setEnabled:NO];
    [_nextButton setEnabled:NO];
    [_nextButton setEnabled:YES];
    [_previousButton setEnabled:NO];
    [_previousButton setEnabled:YES];
    [_fullscreenButton setEnabled:NO];
    [_fullscreenButton setEnabled:YES];

    [_timeSlider setEnabled:seekable];
    [_forwardButton setEnabled:seekable];
    [_backwardButton setEnabled:seekable];
}

- (void)setVolumeLevel:(int)value
{
    [_volumeSlider setIntValue:value];
    [_volumeSlider setToolTip: [NSString stringWithFormat:_NS("Volume: %i %%"), (value*200)/AOUT_VOLUME_MAX]];
}

#pragma mark -
#pragma mark Window interactions

- (void)fadeIn
{
    if (!var_InheritBool(getIntf(), "macosx-fspanel"))
        return;

    if (_isFadingIn)
        return;

    [self stopAutohideTimer];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        _isFadingIn = YES;
        [context setDuration:0.4f];
        [[self.window animator] setAlphaValue:1.0f];
    } completionHandler:^{
        _isFadingIn = NO;
        [self startAutohideTimer];
    }];
}

- (void)fadeOut
{
    /* the seek tooltip is a window of its own: it would survive the panel
     * fading away under the mouse */
    [_timeSlider hideHoverTooltip];
    [NSAnimationContext runAnimationGroup:^(NSAnimationContext * _Nonnull context) {
        [context setDuration:0.4f];
        [[self.window animator] setAlphaValue:0.0f];
    } completionHandler:nil];
}

- (void)centerPanel
{
    NSRect windowFrame = [self.window frame];
    windowFrame = [self contrainFrameToAssociatedVoutWindow:windowFrame];

    /* Calculate coordinates for centered position */
    NSRect limitFrame = _associatedVoutWindow.frame;
    windowFrame.origin.x = (limitFrame.size.width - windowFrame.size.width) / 2 + limitFrame.origin.x;
    windowFrame.origin.y = (limitFrame.size.height / 5) - windowFrame.size.height + limitFrame.origin.y;

    [self.window setFrame:windowFrame display:YES animate:NO];
}

- (NSRect)contrainFrameToAssociatedVoutWindow:(NSRect)frame
{
    NSRect limitFrame = _associatedVoutWindow.frame;

    // Limit rect to limitation view
    if (frame.origin.x < limitFrame.origin.x)
        frame.origin.x = limitFrame.origin.x;
    if (frame.origin.y < limitFrame.origin.y)
        frame.origin.y = limitFrame.origin.y;

    // Limit size (could be needed after resolution changes)
    if (frame.size.height > limitFrame.size.height)
        frame.size.height = limitFrame.size.height;
    if (frame.size.width > limitFrame.size.width)
        frame.size.width = limitFrame.size.width;

    if (frame.origin.x + frame.size.width > limitFrame.origin.x + limitFrame.size.width)
        frame.origin.x = limitFrame.origin.x + limitFrame.size.width - frame.size.width;
    if (frame.origin.y + frame.size.height > limitFrame.origin.y + limitFrame.size.height)
        frame.origin.y = limitFrame.origin.y + limitFrame.size.height - frame.size.height;

    return frame;
}

- (void)setNonActive
{
    [_timeSlider hideHoverTooltip];
    [self.window orderOut:self];
}

- (void)setActive
{
    [self.window orderFront:self];
    [self fadeIn];
}

#pragma mark -
#pragma mark Misc interactions

- (void)hideMouse
{
    [NSCursor setHiddenUntilMouseMoves:YES];
}

- (void)setVoutWasUpdated:(VLCWindow *)voutWindow
{
    _associatedVoutWindow = voutWindow;

    NSRect voutRect = voutWindow.frame;

    // In some cases, the FSPanel frame has moved outside of the
    // vout view --> Also re-center in this case
    NSRect currentFrame = [self.window frame];
    NSRect constrainedFrame = [self contrainFrameToAssociatedVoutWindow: currentFrame];

    if (!NSEqualRects(_associatedVoutFrame, voutRect) ||
        !NSEqualRects(currentFrame, constrainedFrame)) {
        _associatedVoutFrame = voutRect;
        [[NSUserDefaults standardUserDefaults] setObject:NSStringFromRect(_associatedVoutFrame) forKey:kAssociatedFullscreenRect];

        [self centerPanel];
    }

}

#pragma mark -
#pragma mark Autohide timer management

- (void)startAutohideTimer
{
    /* Do nothing if timer is already in place */
    if (_isCounting)
        return;

    /* Get timeout and make sure it is not lower than 1 second */
    int _timeToKeepVisibleInSec = MAX(var_CreateGetInteger(getIntf(), "mouse-hide-timeout") / 1000, 1);

    _hideTimer = [NSTimer scheduledTimerWithTimeInterval:_timeToKeepVisibleInSec
                                                  target:self
                                                selector:@selector(autohideCallback:)
                                                userInfo:nil
                                                 repeats:NO];
    _isCounting = YES;
}

- (void)stopAutohideTimer
{
    [_hideTimer invalidate];
    _isCounting = NO;
}

- (void)autohideCallback:(NSTimer *)timer
{
    if (!NSMouseInRect([NSEvent mouseLocation], [self.window frame], NO)) {
        [self fadeOut];
        [self hideMouse];
    }
    _isCounting = NO;
}

#pragma mark -
#pragma mark Helpers

#ifdef MAC_OS_X_VERSION_10_10
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"

/**
 Create an image mask for the NSVisualEffectView
 with rounded corners in the given rect

 This is necessary as clipping the VisualEffectView using the layers
 rounded corners is not possible when using the NSColor clearColor
 as background color.

 \note  The returned image will have the necessary \c capInsets and
        \c capResizingMode set.

 \param bounds  The rect for the image size
 */
- (NSImage *)maskImageWithBounds:(NSRect)bounds
{
    static const float radius = 8.0;
    NSImage *img = [NSImage imageWithSize:bounds.size flipped:YES drawingHandler:^BOOL(NSRect dstRect) {
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:bounds xRadius:radius yRadius:radius];
        [[NSColor blackColor] setFill];
        [path fill];
        return YES;
    }];
    [img setCapInsets:NSEdgeInsetsMake(radius, radius, radius, radius)];
    [img setResizingMode:NSImageResizingModeStretch];
    return img;
}

/**
 Injects the visual effect view in the Windows view hierarchy

 This is necessary as we can't use the NSVisualEffect view on
 all macOS Versions and therefore need to dynamically insert it.

 \warning Never call both, \c injectVisualEffectView and \c injectBackgroundView
 */
- (void)injectVisualEffectView
{
    /* Setup the view */
    NSVisualEffectView *view = [[NSVisualEffectView alloc] initWithFrame:self.window.contentView.frame];
    [view setMaskImage:[self maskImageWithBounds:self.window.contentView.bounds]];
    [view setBlendingMode:NSVisualEffectBlendingModeBehindWindow];
    [view setMaterial:NSVisualEffectMaterialDark];
    [view setState:NSVisualEffectStateActive];
    [view setAutoresizesSubviews:YES];

    /* Inject view in view hierarchy */
    [self.window setContentView:view];
    [_controlsView setAppearance:[NSAppearance appearanceNamed:NSAppearanceNameVibrantDark]];
    [self.window.contentView addSubview:_controlsView];
}
#pragma clang diagnostic pop
#endif

/**
 Injects the standard background view in the Windows view hierarchy

 This is necessary on macOS versions that do not support the
 NSVisualEffectView that usually is injected.

 \warning Never call both, \c injectVisualEffectView and \c injectBackgroundView
 */
- (void)injectBackgroundView
{
    /* Setup the view */
    CGColorRef color = CGColorCreateGenericGray(0.0, 0.8);
    NSView *view = [[NSView alloc] initWithFrame:self.window.contentView.frame];
    [view setWantsLayer:YES];
    [view.layer setBackgroundColor:color];
    [view.layer setCornerRadius:8.0];
    [view setAutoresizesSubviews:YES];
    CGColorRelease(color);

    /* Inject view in view hierarchy */
    [self.window setContentView:view];
    [self.window.contentView addSubview:_controlsView];

    // Needed on old OS to allow correct resizing of window
    [self.window setMaxSize:NSMakeSize(4068, 84.)];
    [self.window setMinSize:NSMakeSize(480, 84.)];
}

- (void)dealloc
{
    [self stopAutohideTimer];
}


@end
