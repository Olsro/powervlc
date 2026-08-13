/*****************************************************************************
 * CoreInteraction.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2011-2021 Felix Paul Kühne
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne -at- videolan -dot- org>
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

#import "VLCCoreInteraction.h"
#import "VLCMain.h"
#import "VLCOpenWindowController.h"
#import "VLCPlaylist.h"
#import <math.h>
#import <vlc_playlist.h>
#import <vlc_input.h>
#import <vlc_actions.h>
#import <vlc_vout.h>
#import <vlc_vout_osd.h>
#import <vlc/vlc.h>
#import <vlc_strings.h>
#import <vlc_url.h>
#import <vlc_modules.h>
#import <vlc_charset.h>
#include <vlc_plugin.h>
#import "SPMediaKeyTap.h"
#import "AppleRemote.h"
#import "VLCInputManager.h"
#import "CompatibilityFixes.h"

#import "NSSound+VLCAdditions.h"

static int BossCallback(vlc_object_t *p_this, const char *psz_var,
                        vlc_value_t oldval, vlc_value_t new_val, void *param)
{
    @autoreleasepool {
        dispatch_async(dispatch_get_main_queue(), ^{
            [[VLCCoreInteraction sharedInstance] pause];
            [[NSApplication sharedApplication] hide:nil];
        });

        return VLC_SUCCESS;
    }
}

NSString *VLCClipCreationModeChangedNotification = @"VLCClipCreationModeChangedNotification";

/* the core hotkeys module redirects the extrashort/short jump actions to
 * this input variable while the clip creation mode is active (the key
 * events on the video window never reach the interface: they go straight
 * to the hotkeys module, which used to write time-offset) */
static int ClipStepCallback(vlc_object_t *p_this, const char *psz_var,
                            vlc_value_t oldval, vlc_value_t newval,
                            void *p_data)
{
    VLC_UNUSED(p_this); VLC_UNUSED(psz_var);
    VLC_UNUSED(oldval); VLC_UNUSED(p_data);
    /* value convention (see hotkeys.c): +-1 = one frame, else signed
     * microseconds */
    int64_t value = newval.i_int;
    /* hotkeys thread -> main thread, where the clip state lives */
    dispatch_async(dispatch_get_main_queue(), ^{
        if (value == 1 || value == -1)
            [[VLCCoreInteraction sharedInstance] clipStepFrames:(int)value];
        else
            [[VLCCoreInteraction sharedInstance]
                clipNudgeSelectedBoundBySeconds:(double)value / CLOCK_FREQ];
    });
    return VLC_SUCCESS;
}

/* the core fires this libvlc trigger when the video is double-clicked
 * while the windowed controls are auto-hidden (see
 * src/video_output/event.h): bring the controls back */
static int RevealControlsCallback(vlc_object_t *p_this, const char *psz_var,
                                  vlc_value_t oldval, vlc_value_t newval,
                                  void *p_data)
{
    VLC_UNUSED(p_this); VLC_UNUSED(psz_var);
    VLC_UNUSED(oldval); VLC_UNUSED(newval); VLC_UNUSED(p_data);
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter]
            postNotificationName:VLCRevealControlsNotification object:nil];
    });
    return VLC_SUCCESS;
}

@interface VLCCoreInteraction () <SPMediaKeyTapDelegate>
{
    int i_currentPlaybackRate;
    vlc_tick_t timeA, timeB;

    /* clip creation mode bookkeeping */
    double clipLastPollPos;              /* last polled position, -1 = none */
    NSTimeInterval clipLastInteraction;  /* last knob drag/click */
    /* end-bound pause bookkeeping: 0 = none, 1 = pause requested at the
     * crossing, 2 = pause confirmed (state seen paused). Playing again
     * from state 2 restarts at the clip start. The intermediate state
     * exists because playlist_Pause is asynchronous: right after the
     * crossing the input still reports PLAYING and a naive check would
     * bounce the playback to the start instantly. */
    int clipPausedAtEnd;
    /* A clip recording is armed while the playback usually sits AT the
     * end bound (the B knob was just previewed, or the end-bound pause
     * is holding there). The seek back to the clip start is part of the
     * record control and takes a moment: until the position has come
     * back inside the clip, the end-bound test below would fire on the
     * stale position and kill the recording on the spot. */
    BOOL clipRecordWaitingForStart;
    /* fast clip extraction: a second headless input writes the clip at
     * disk speed while the playback carries on untouched. Only used as a
     * fallback-free path: when the core refuses it (unseekable stream,
     * unknown length) the realtime recording above is used instead. */
    input_clip_export_t *p_clipExport;
    /* the interface polls on playback position events, which stop coming
     * when the playback is paused -- and recording a clip from a paused
     * playback is the normal case here */
    NSTimer *clipExportPollTimer;

    float f_maxVolume;

    /* media key support */
    BOOL b_mediaKeySupport;
    BOOL b_mediakeyJustJumped;
    SPMediaKeyTap *_mediaKeyController;
    BOOL b_mediaKeyTrapEnabled;

    AppleRemote *_remote;
    BOOL b_remote_button_hold; /* true as long as the user holds the left,right,plus or minus on the remote control */

    NSArray *_usedHotkeys;
}
@end

@implementation VLCCoreInteraction

#pragma mark - Initialization

+ (VLCCoreInteraction *)sharedInstance
{
    static VLCCoreInteraction *sharedInstance = nil;
    static dispatch_once_t pred;

    dispatch_once(&pred, ^{
        sharedInstance = [VLCCoreInteraction new];
    });

    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        intf_thread_t *p_intf = getIntf();
        clipLastPollPos = -1.;

        /* init media key support on earlier macOS versions
         * this feature is covered by VLCRemoteControlService in later releases */
        if (!OSX_SIERRA_AND_HIGHER) {
            b_mediaKeySupport = var_InheritBool(p_intf, "macosx-mediakeys");
            if (b_mediaKeySupport) {
                _mediaKeyController = [[SPMediaKeyTap alloc] initWithDelegate:self];
            }
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(coreChangedMediaKeySupportSetting:)
                                                         name:VLCMediaKeySupportSettingChangedNotification
                                                       object:nil];
        }

        /* init Apple Remote support */
        _remote = [[AppleRemote alloc] init];
        [_remote setClickCountEnabledButtons: kRemoteButtonPlay];
        [_remote setDelegate: self];

        /* the clip creation mode is bound to the item it was entered on:
         * leave it whenever the input stops or changes */
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(inputChangedForClipCreation:)
                                                     name:VLCInputChangedNotification
                                                   object:nil];

        var_AddCallback(p_intf->obj.libvlc, "intf-boss", BossCallback, (__bridge void *)self);

        /* "Hide controls during playback" plumbing shared with the core:
         * the bool tells the core the controls are gone (OSD like
         * fullscreen, double-click reveals instead of toggling
         * fullscreen), the void trigger is the core asking for them
         * back */
        _autoHideControls = var_InheritBool(p_intf, "macosx-hide-controls");
        var_Create(p_intf->obj.libvlc, "intf-controls-hidden", VLC_VAR_BOOL);
        var_Create(p_intf->obj.libvlc, "intf-reveal-controls", VLC_VAR_VOID);
        var_AddCallback(p_intf->obj.libvlc, "intf-reveal-controls",
                        RevealControlsCallback, (__bridge void *)self);
    }
    return self;
}

- (void)dealloc
{
    /* the extraction input is a child of the interface: it cannot outlive it */
    if (p_clipExport)
        [self finishClipExportCancelled:YES];

    intf_thread_t *p_intf = getIntf();
    var_DelCallback(p_intf->obj.libvlc, "intf-boss", BossCallback, (__bridge void *)self);
    var_DelCallback(p_intf->obj.libvlc, "intf-reveal-controls",
                    RevealControlsCallback, (__bridge void *)self);
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

#pragma mark - Hide controls during playback

- (void)setAutoHideControls:(BOOL)autoHideControls
{
    if (_autoHideControls == autoHideControls)
        return;
    _autoHideControls = autoHideControls;
    config_PutInt(getIntf(), "macosx-hide-controls", autoHideControls);
}

- (void)setControlsHiddenForPlayback:(BOOL)controlsHiddenForPlayback
{
    _controlsHiddenForPlayback = controlsHiddenForPlayback;
    var_SetBool(getIntf()->obj.libvlc, "intf-controls-hidden",
                controlsHiddenForPlayback);
}

/* While the controls are hidden the keyboard is the only control surface:
 * mirror on the video what the invisible interface would have shown, with
 * the same OSD the core hotkeys use in fullscreen. Actions going through
 * the hotkeys module (seeks…) already display theirs. */
- (void)osdDisplayVolume
{
    if (!_controlsHiddenForPlayback)
        return;
    vout_thread_t *p_vout = getVout();
    if (!p_vout)
        return;
    float volume = playlist_VolumeGet(pl_Get(getIntf()));
    if (volume >= 0.) {
        vout_OSDSlider(p_vout, VOUT_SPU_CHANNEL_OSD,
                       lroundf(volume * 100.f), OSD_VERT_SLIDER);
        vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, _("Volume %ld%%"),
                        lroundf(volume * 100.f));
    }
    vlc_object_release(p_vout);
}

- (void)osdDisplayIcon:(short)icon
{
    if (!_controlsHiddenForPlayback)
        return;
    vout_thread_t *p_vout = getVout();
    if (!p_vout)
        return;
    vout_OSDIcon(p_vout, VOUT_SPU_CHANNEL_OSD, icon);
    vlc_object_release(p_vout);
}

- (void)osdDisplayMessage:(const char *)message
{
    if (!_controlsHiddenForPlayback)
        return;
    vout_thread_t *p_vout = getVout();
    if (!p_vout)
        return;
    vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s", message);
    vlc_object_release(p_vout);
}


#pragma mark - Playback Controls

- (void)play
{
    playlist_t *p_playlist = pl_Get(getIntf());
    playlist_Play(p_playlist);
}

- (void)playOrPause
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    playlist_t *p_playlist = pl_Get(getIntf());

    if (p_input) {
        /* resuming after the automatic end-bound pause replays the clip
         * from its start bound instead of continuing past the end */
        if (_clipCreationMode && clipPausedAtEnd
            && var_GetInteger(p_input, "state") == PAUSE_S) {
            clipPausedAtEnd = 0;
            var_SetFloat(p_input, "position", (float)_clipStartPosition);
            clipLastPollPos = _clipStartPosition;
        }
        int64_t state = var_GetInteger(p_input, "state");
        playlist_TogglePause(p_playlist);
        vlc_object_release(p_input);
        [self osdDisplayIcon:(state != PAUSE_S ? OSD_PAUSE_ICON
                                               : OSD_PLAY_ICON)];

    } else {
        PLRootType root = [[[[VLCMain sharedInstance] playlist] model] currentRootType];
        if ([[[VLCMain sharedInstance] playlist] isSelectionEmpty] && (root == ROOT_TYPE_PLAYLIST || root == ROOT_TYPE_MEDIALIBRARY))
            [[[VLCMain sharedInstance] open] openFileGeneric];
        else
            [[[VLCMain sharedInstance] playlist] playItem:nil];
    }
}

- (void)pause
{
    playlist_t *p_playlist = pl_Get(getIntf());

    playlist_Pause(p_playlist);
}

- (void)stop
{
    playlist_Stop(pl_Get(getIntf()));
}

- (void)faster
{
    var_TriggerCallback(pl_Get(getIntf()), "rate-faster");
}

- (void)slower
{
    var_TriggerCallback(pl_Get(getIntf()), "rate-slower");
}

- (void)normalSpeed
{
    var_SetFloat(pl_Get(getIntf()), "rate", 1.);
}

- (void)toggleRecord
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    input_thread_t * p_input;
    p_input = pl_CurrentInput(p_intf);
    if (p_input) {
        var_Create(p_input, "record-stop-time", VLC_VAR_INTEGER);
        if (_clipCreationMode) {
            if (p_clipExport) {
                /* a fast extraction is running: give it up */
                [self finishClipExportCancelled:YES];
            } else if (_clipRecordingActive) {
                /* cancel the running clip recording */
                var_SetInteger(p_input, "record-stop-time", 0);
                var_SetInteger(p_input, "record-start-time", 0);
                var_SetBool(p_input, "record", false);
                _clipRecordingActive = NO;
            } else if ([self startClipExportForInput:p_input]) {
                /* extracted at disk speed by a second input; the playback
                 * the user is watching is not disturbed at all */
            } else {
                /* Arm the demux-paced stop bound, then let the core seek
                 * to the clip start and start recording in ONE input
                 * control ("record-clip-position"): the recording then
                 * begins at the very key frame the seek resumed from --
                 * the closest possible start before the clip bound without
                 * re-encoding. */
                vlc_tick_t duration = input_item_GetDuration(input_GetItem(p_input));
                var_SetInteger(p_input, "record-stop-time",
                               duration > 0 ? (vlc_tick_t)(_clipEndPosition * (double)duration) : 0);
                var_SetInteger(p_input, "record-start-time",
                               duration > 0 ? (vlc_tick_t)(_clipStartPosition * (double)duration) : 0);
                var_SetFloat(p_input, "record-clip-position", (float)_clipStartPosition);
                _clipRecordingActive = YES;
                clipPausedAtEnd = 0; /* the record control seeks by itself */
                clipRecordWaitingForStart = YES;
                if (var_GetInteger(p_input, "state") == PAUSE_S)
                    playlist_TogglePause(pl_Get(p_intf));
            }
        } else {
            /* a plain recording has no stop bound */
            var_SetInteger(p_input, "record-stop-time", 0);
            var_SetInteger(p_input, "record-start-time", 0);
            var_ToggleBool(p_input, "record");
        }
        vlc_object_release(p_input);
    }
}

#pragma mark - Clip creation mode

/* Message on the video AND in the status bar of the main window: a fast
 * export is over in a blink, the user needs to be told where it went. */
- (void)clipExportNotify:(NSString *)message
{
    vout_thread_t *p_vout = getVout();
    if (p_vout) {
        vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s", [message UTF8String]);
        vlc_object_release(p_vout);
    }
    msg_Info(getIntf(), "%s", [message UTF8String]);
}

/* Starts the fast extraction of [A..B]. Returns NO when the core cannot
 * extract from this input (live stream, unknown length...), which leaves
 * the caller with the realtime recording. */
- (BOOL)startClipExportForInput:(input_thread_t *)p_input
{
    if (p_clipExport)
        return YES;

    vlc_tick_t duration = input_item_GetDuration(input_GetItem(p_input));
    if (duration <= 0)
        return NO;

    vlc_tick_t start = (vlc_tick_t)(_clipStartPosition * (double)duration);
    vlc_tick_t stop = (vlc_tick_t)(_clipEndPosition * (double)duration);

    p_clipExport = input_ClipExportNew(getIntf(), p_input, start, stop);
    if (!p_clipExport)
        return NO;

    _clipExportInProgress = YES;
    clipExportPollTimer =
        [NSTimer scheduledTimerWithTimeInterval:0.25
                                         target:self
                                       selector:@selector(clipExportPollFired:)
                                       userInfo:nil
                                        repeats:YES];
    [self clipExportNotify:_NS("Exporting clip…")];
    [[NSNotificationCenter defaultCenter]
        postNotificationName:VLCClipCreationModeChangedNotification object:nil];
    return YES;
}

- (void)clipExportPollFired:(NSTimer *)timer
{
    if (p_clipExport && !input_ClipExportIsRunning(p_clipExport))
        [self finishClipExportCancelled:NO];
}

- (void)finishClipExportCancelled:(BOOL)cancelled
{
    if (!p_clipExport)
        return;

    [clipExportPollTimer invalidate];
    clipExportPollTimer = nil;

    char *psz_file = input_ClipExportFinish(p_clipExport);
    p_clipExport = NULL;
    _clipExportInProgress = NO;

    if (cancelled) {
        [self clipExportNotify:_NS("Clip export cancelled")];
    } else if (psz_file) {
        NSString *path = [NSString stringWithUTF8String:psz_file];
        [self clipExportNotify:[NSString stringWithFormat:@"%@ %@",
                                _NS("Clip saved:"), [path lastPathComponent]]];
    } else {
        [self clipExportNotify:_NS("Clip export failed")];
    }
    free(psz_file);

    [[NSNotificationCenter defaultCenter]
        postNotificationName:VLCClipCreationModeChangedNotification object:nil];
}

- (void)toggleClipCreationMode
{
    if (_clipCreationMode) {
        [self exitClipCreationMode];
        return;
    }

    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (!p_input)
        return;
    if (!var_GetBool(p_input, "can-seek")) {
        vlc_object_release(p_input);
        return;
    }

    double pos = var_GetFloat(p_input, "position");
    vlc_tick_t duration = input_item_GetDuration(input_GetItem(p_input));

    /* the hotkeys module redirects the step shortcuts here while the
     * variable exists (see ClipStepCallback) */
    var_Create(p_input, "clip-frame-step",
               VLC_VAR_INTEGER | VLC_VAR_ISCOMMAND);
    var_AddCallback(p_input, "clip-frame-step", ClipStepCallback, NULL);
    vlc_object_release(p_input);

    /* place the end knob right next to the start knob: 10 seconds ahead,
     * bounded to stay between 1% and 5% of the item so both knobs remain
     * distinguishable on short and very long media */
    double delta = 0.05;
    if (duration > 0) {
        delta = (double)(10 * CLOCK_FREQ) / (double)duration;
        if (delta > 0.05)
            delta = 0.05;
        else if (delta < 0.01)
            delta = 0.01;
    }

    if (pos < 0.)
        pos = 0.;
    else if (pos > 1.)
        pos = 1.;
    _clipStartPosition = pos;
    _clipEndPosition = pos + delta;
    if (_clipEndPosition > 1.)
        _clipEndPosition = 1.;

    /* the frame-step shortcuts default to the end bound until the user
     * grabs another knob */
    _clipSelectedKnob = 2;
    clipPausedAtEnd = 0;

    _clipCreationMode = YES;
    [[NSNotificationCenter defaultCenter] postNotificationName:VLCClipCreationModeChangedNotification
                                                        object:nil];
}

- (void)exitClipCreationMode
{
    if (!_clipCreationMode)
        return;

    /* a running extraction has no reason to survive the mode */
    if (p_clipExport)
        [self finishClipExportCancelled:YES];

    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (p_input) {
        var_Create(p_input, "record-stop-time", VLC_VAR_INTEGER);
        var_SetInteger(p_input, "record-stop-time", 0);
        var_SetInteger(p_input, "record-start-time", 0);
        if (_clipRecordingActive)
            var_SetBool(p_input, "record", false);
        /* stop redirecting the jump hotkeys (guarded: on an input change
         * this is a different input, without the variable — the dying
         * one takes its callbacks with it) */
        if (var_Type(p_input, "clip-frame-step") != 0) {
            var_DelCallback(p_input, "clip-frame-step", ClipStepCallback, NULL);
            var_Destroy(p_input, "clip-frame-step");
        }
        vlc_object_release(p_input);
    }
    _clipRecordingActive = NO;

    _clipCreationMode = NO;
    [[NSNotificationCenter defaultCenter] postNotificationName:VLCClipCreationModeChangedNotification
                                                        object:nil];
}

- (void)setClipEndPosition:(double)pos
{
    _clipEndPosition = pos;

    /* follow a live adjustment of the end bound during a clip recording */
    if (_clipRecordingActive) {
        input_thread_t *p_input = pl_CurrentInput(getIntf());
        if (p_input) {
            vlc_tick_t duration = input_item_GetDuration(input_GetItem(p_input));
            if (duration > 0) {
                var_Create(p_input, "record-stop-time", VLC_VAR_INTEGER);
                var_SetInteger(p_input, "record-stop-time",
                               (vlc_tick_t)(pos * (double)duration));
            }
            vlc_object_release(p_input);
        }
    }
}

- (void)noteClipInteraction
{
    clipLastInteraction = [NSDate timeIntervalSinceReferenceDate];
    /* any knob interaction invalidates the pending "replay from the
     * start" state: the user chose a new position themselves */
    clipPausedAtEnd = 0;
}

/* move the last-selected clip bound by a signed amount of seconds and
 * preview it (accurate seek: input-fast-seek is off by default, so the
 * very frame is shown, even while paused) */
- (void)clipNudgeSelectedBoundBySeconds:(double)seconds
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (!p_input)
        return;

    vlc_tick_t duration = input_item_GetDuration(input_GetItem(p_input));
    if (duration <= 0) {
        vlc_object_release(p_input);
        return;
    }

    double step = seconds * (double)CLOCK_FREQ / (double)duration;
    double target;
    if (_clipSelectedKnob == 1) {
        target = _clipStartPosition + step;
        if (target < 0.)
            target = 0.;
        if (target > _clipEndPosition)
            target = _clipEndPosition;
        _clipStartPosition = target;
    } else {
        target = _clipEndPosition + step;
        if (target < _clipStartPosition)
            target = _clipStartPosition;
        if (target > 1.)
            target = 1.;
        /* the setter follows a live recording's record-stop-time */
        [self setClipEndPosition:target];
    }
    [self noteClipInteraction];

    var_SetFloat(p_input, "position", (float)target);
    vlc_object_release(p_input);
}

/* one-frame nudge of the last-selected clip bound, for surgical
 * trimming. Falls back to 25 fps when the demux did not expose the
 * video frame rate. */
- (void)clipStepFrames:(int)direction
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (!p_input)
        return;

    input_item_t *p_item = input_GetItem(p_input);
    double frameSec = 1. / 25.;
    if (p_item) {
        vlc_mutex_lock(&p_item->lock);
        for (int i = 0; i < p_item->i_es; i++) {
            const es_format_t *fmt = p_item->es[i];
            if (fmt->i_cat == VIDEO_ES && fmt->video.i_frame_rate > 0
                && fmt->video.i_frame_rate_base > 0) {
                frameSec = (double)fmt->video.i_frame_rate_base
                         / (double)fmt->video.i_frame_rate;
                break;
            }
        }
        vlc_mutex_unlock(&p_item->lock);
    }
    vlc_object_release(p_input);

    [self clipNudgeSelectedBoundBySeconds:direction * frameSec];
}

/* the interfaces are told about any record state change through
 * INPUT_EVENT_RECORD; keep the clip recording flag in sync so the
 * demux-paced core stop (record-stop-time) is reflected here */
- (void)recordStateChanged:(BOOL)b_recording
{
    if (!b_recording) {
        _clipRecordingActive = NO;
        clipRecordWaitingForStart = NO;
    }
}

/* level-polled from the main window update path, like updateAtoB */
- (void)updateClipRecording
{
    /* a fast extraction runs beside the playback: collect it when it ends
     * (even if the mode was left in the meantime, which cannot happen
     * today -- leaving the mode cancels it) */
    if (p_clipExport && !input_ClipExportIsRunning(p_clipExport))
        [self finishClipExportCancelled:NO];

    if (!_clipCreationMode) {
        clipLastPollPos = -1.;
        return;
    }

    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (!p_input)
        return;

    double pos = var_GetFloat(p_input, "position");
    int state = (int)var_GetInteger(p_input, "state");

    /* end-bound pause state machine (see the ivar comment) */
    if (clipPausedAtEnd == 1 && state == PAUSE_S)
        clipPausedAtEnd = 2;
    else if (clipPausedAtEnd == 2 && state == PLAYING_S) {
        /* resumed by a path that does not go through -playOrPause
         * (hotkey, another interface...): same rule, replay the clip */
        clipPausedAtEnd = 0;
        var_SetFloat(p_input, "position", (float)_clipStartPosition);
        clipLastPollPos = _clipStartPosition;
        vlc_object_release(p_input);
        return;
    }

    /* one second as a fraction of the media, 0 when the length is unknown */
    int64_t i_length = var_GetInteger(p_input, "length");
    double posPerSec = i_length > 0 ? (double)CLOCK_FREQ / (double)i_length : 0.;

    /* A bound sitting at the very END of the media cannot be caught by the
     * poll: nothing is ever sampled between it and EOF, so the input runs
     * out, the item ends and the mode goes with it. Pause a hair earlier in
     * that case -- but NEVER while recording, where the exact stop belongs
     * to the core (record-stop-time, on the raw demux clock) and pulling the
     * preview back would truncate the clip. */
    double endBound = _clipEndPosition;
    if (!_clipRecordingActive && posPerSec > 0.) {
        double lastSafe = 1. - 0.5 * posPerSec;
        if (endBound > lastSafe)
            endBound = lastSafe;
    }

    /* The playback must never run OUTSIDE [A..B]: before A it is pulled
     * back to A, at B it pauses (and playing again replays from A, through
     * the state machine above). This is a LEVEL test, not the crossing it
     * used to be -- previewing the B frame and then playing past it was
     * allowed by design and no longer is. Suppressed right after a knob
     * interaction: dragging a bound seeks repeatedly around it and must not
     * leave the player paused. */
    BOOL interacting = ([NSDate timeIntervalSinceReferenceDate] - clipLastInteraction) < 0.5;
    if (clipRecordWaitingForStart) {
        /* see the ivar comment: wait for the seek that arms the clip
         * recording to land before testing the bounds again */
        if (!_clipRecordingActive || pos < endBound)
            clipRecordWaitingForStart = NO;
        if (clipRecordWaitingForStart) {
            clipLastPollPos = pos;
            vlc_object_release(p_input);
            return;
        }
    }
    if (!interacting && state == PLAYING_S) {
        if (posPerSec > 0. && pos < _clipStartPosition - 0.25 * posPerSec) {
            var_SetFloat(p_input, "position", (float)_clipStartPosition);
            clipLastPollPos = _clipStartPosition;
            vlc_object_release(p_input);
            return;
        }
        if (pos >= endBound) {
            if (_clipRecordingActive) {
                /* backstop -- the core normally ended it at the bound */
                var_SetBool(p_input, "record", false);
                _clipRecordingActive = NO;
            }
            playlist_Pause(pl_Get(getIntf()));
            clipPausedAtEnd = 1;
        }
    }
    clipLastPollPos = pos;
    vlc_object_release(p_input);
}

- (void)inputChangedForClipCreation:(NSNotification *)aNotification
{
    [self exitClipCreationMode];
}

- (void)setPlaybackRate:(int)i_value
{
    playlist_t * p_playlist = pl_Get(getIntf());

    double speed = pow(2, (double)i_value / 17);
    int rate = INPUT_RATE_DEFAULT / speed;
    if (i_currentPlaybackRate != rate)
        var_SetFloat(p_playlist, "rate", (float)INPUT_RATE_DEFAULT / (float)rate);
    i_currentPlaybackRate = rate;
}

- (int)playbackRate
{
    float f_rate;

    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return 0;

    input_thread_t * p_input;
    p_input = pl_CurrentInput(p_intf);
    if (p_input) {
        f_rate = var_GetFloat(p_input, "rate");
        vlc_object_release(p_input);
    }
    else
    {
        playlist_t * p_playlist = pl_Get(getIntf());
        f_rate = var_GetFloat(p_playlist, "rate");
    }

    double value = 17 * log(f_rate) / log(2.);
    int returnValue = (int) ((value > 0) ? value + .5 : value - .5);

    if (returnValue < -34)
        returnValue = -34;
    else if (returnValue > 34)
        returnValue = 34;

    i_currentPlaybackRate = returnValue;
    return returnValue;
}

- (float)internalPlaybackRate
{
    input_thread_t *p_input_thread = pl_CurrentInput(getIntf());
    float rate = 0.;

    if (p_input_thread) {
        rate = var_GetFloat(p_input_thread, "rate");
        vlc_object_release(p_input_thread);
    }

    return rate;
}

- (void)previous
{
    playlist_Prev(pl_Get(getIntf()));
    [self osdDisplayMessage:_("Previous")];
}

- (void)next
{
    playlist_Next(pl_Get(getIntf()));
    [self osdDisplayMessage:_("Next")];
}

- (int)durationOfCurrentPlaylistItem
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return 0;

    input_thread_t * p_input = pl_CurrentInput(p_intf);
    int64_t i_duration = -1;
    if (!p_input)
        return i_duration;

    input_Control(p_input, INPUT_GET_LENGTH, &i_duration);
    vlc_object_release(p_input);

    return (int)(i_duration / 1000000);
}

- (NSURL*)URLOfCurrentPlaylistItem
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return nil;

    input_thread_t *p_input = pl_CurrentInput(p_intf);
    if (!p_input)
        return nil;

    input_item_t *p_item = input_GetItem(p_input);
    if (!p_item) {
        vlc_object_release(p_input);
        return nil;
    }

    char *psz_uri = input_item_GetURI(p_item);
    if (!psz_uri) {
        vlc_object_release(p_input);
        return nil;
    }

    NSURL *o_url;
    o_url = [NSURL URLWithString:toNSStr(psz_uri)];
    free(psz_uri);
    vlc_object_release(p_input);

    return o_url;
}

- (NSString*)nameOfCurrentPlaylistItem
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return nil;

    input_thread_t *p_input = pl_CurrentInput(p_intf);
    if (!p_input)
        return nil;

    input_item_t *p_item = input_GetItem(p_input);
    if (!p_item) {
        vlc_object_release(p_input);
        return nil;
    }

    char *psz_uri = input_item_GetURI(p_item);
    if (!psz_uri) {
        vlc_object_release(p_input);
        return nil;
    }

    NSString *o_name = @"";
    char *format = var_InheritString(getIntf(), "input-title-format");
    if (format) {
        char *formated = vlc_strfinput(p_input, format);
        free(format);
        o_name = toNSStr(formated);
        free(formated);
    }

    NSURL * o_url = [NSURL URLWithString:toNSStr(psz_uri)];
    free(psz_uri);

    if ([o_name isEqualToString:@""]) {
        if ([o_url isFileURL])
            o_name = [[NSFileManager defaultManager] displayNameAtPath:[o_url path]];
        else
            o_name = [o_url absoluteString];
    }
    vlc_object_release(p_input);
    return o_name;
}

- (long long)currentPlaybackTimeInSeconds
{
    input_thread_t *p_input_thread = pl_CurrentInput(getIntf());
    long long timeInSeconds = 0;

    if (p_input_thread) {
        int64_t time = var_GetInteger(p_input_thread, "time");
        timeInSeconds = time / CLOCK_FREQ;
        vlc_object_release(p_input_thread);
    }

    return timeInSeconds;
}

- (float)currentPlaybackPosition
{
    input_thread_t * p_input_thread = pl_CurrentInput(getIntf());
    float position = 0.;

    if (p_input_thread) {
        position = var_GetFloat(p_input_thread, "position");
        vlc_object_release(p_input_thread);
    }

    return position;
}

- (void)forward
{
    //LEGACY SUPPORT
    [self forwardShort];
}

- (void)backward
{
    //LEGACY SUPPORT
    [self backwardShort];
}

- (void)jumpWithValue:(char *)p_value forward:(BOOL)b_value
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (!p_input)
        return;

    /* in clip creation mode the medium/long jumps resize the clip by
     * their configured amount through the selected bound (the frame
     * steps are intercepted before ever reaching here) */
    if (_clipCreationMode) {
        long long i_interval = var_InheritInteger(p_input, p_value);
        vlc_object_release(p_input);
        if (i_interval > 0)
            [self clipNudgeSelectedBoundBySeconds:
                (b_value ? 1. : -1.) * (double)i_interval];
        return;
    }

    bool b_seekable = var_GetBool(p_input, "can-seek");
    if (b_seekable) {
        long long i_interval = var_InheritInteger( p_input, p_value );
        if (i_interval > 0) {
            vlc_tick_t val = CLOCK_FREQ * i_interval;
            if (!b_value)
                val = val * -1;
            var_SetInteger( p_input, "time-offset", val );
        }
    }
    vlc_object_release(p_input);
}

/* in clip creation mode the step shortcuts become one-FRAME nudges of
 * the last-selected bound knob: trimming needs surgical precision, not
 * seconds-sized jumps (explicit user requirement) */
- (void)forwardExtraShort
{
    if (_clipCreationMode) {
        [self clipStepFrames:1];
        return;
    }
    [self jumpWithValue:"extrashort-jump-size" forward:YES];
}

- (void)backwardExtraShort
{
    if (_clipCreationMode) {
        [self clipStepFrames:-1];
        return;
    }
    [self jumpWithValue:"extrashort-jump-size" forward:NO];
}

- (void)forwardShort
{
    if (_clipCreationMode) {
        [self clipStepFrames:1];
        return;
    }
    [self jumpWithValue:"short-jump-size" forward:YES];
}

- (void)backwardShort
{
    if (_clipCreationMode) {
        [self clipStepFrames:-1];
        return;
    }
    [self jumpWithValue:"short-jump-size" forward:NO];
}

- (void)forwardMedium
{
    [self jumpWithValue:"medium-jump-size" forward:YES];
}

- (void)backwardMedium
{
    [self jumpWithValue:"medium-jump-size" forward:NO];
}

- (void)forwardLong
{
    [self jumpWithValue:"long-jump-size" forward:YES];
}

- (void)backwardLong
{
    [self jumpWithValue:"long-jump-size" forward:NO];
}

- (BOOL)seekToTime:(vlc_tick_t)time
{
    input_thread_t * p_input_thread = pl_CurrentInput(getIntf());
    if (p_input_thread) {
        bool b_seekable = var_GetBool(p_input_thread, "can-seek");
        if (b_seekable) {
            var_SetInteger(p_input_thread, "time", time);
            vlc_object_release(p_input_thread);
            return YES;
        }
        vlc_object_release(p_input_thread);
    }
    return NO;
}

- (void)shuffle
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    vlc_value_t val;
    playlist_t * p_playlist = pl_Get(p_intf);
    vout_thread_t *p_vout = getVout();

    var_Get(p_playlist, "random", &val);
    val.b_bool = !val.b_bool;
    var_Set(p_playlist, "random", val);
    if (val.b_bool) {
        if (p_vout) {
            vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s", _("Random On"));
            vlc_object_release(p_vout);
        }
        config_PutInt(p_playlist, "random", 1);
    }
    else
    {
        if (p_vout) {
            vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s", _("Random Off"));
            vlc_object_release(p_vout);
        }
        config_PutInt(p_playlist, "random", 0);
    }
}

- (void)repeatAll
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    playlist_t * p_playlist = pl_Get(p_intf);

    var_SetBool(p_playlist, "repeat", NO);
    var_SetBool(p_playlist, "loop", YES);
    config_PutInt(p_playlist, "repeat", NO);
    config_PutInt(p_playlist, "loop", YES);

    vout_thread_t *p_vout = getVout();
    if (p_vout) {
        vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s", _("Repeat All"));
        vlc_object_release(p_vout);
    }
}

- (void)repeatOne
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    playlist_t * p_playlist = pl_Get(p_intf);

    var_SetBool(p_playlist, "repeat", YES);
    var_SetBool(p_playlist, "loop", NO);
    config_PutInt(p_playlist, "repeat", YES);
    config_PutInt(p_playlist, "loop", NO);

    vout_thread_t *p_vout = getVout();
    if (p_vout) {
        vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s", _("Repeat One"));
        vlc_object_release(p_vout);
    }
}

- (void)repeatOff
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    playlist_t * p_playlist = pl_Get(p_intf);

    var_SetBool(p_playlist, "repeat", NO);
    var_SetBool(p_playlist, "loop", NO);
    config_PutInt(p_playlist, "repeat", NO);
    config_PutInt(p_playlist, "loop", NO);

    vout_thread_t *p_vout = getVout();
    if (p_vout) {
        vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s", _("Repeat Off"));
        vlc_object_release(p_vout);
    }
}

- (void)setAtoB
{
    if (!timeA) {
        input_thread_t * p_input = pl_CurrentInput(getIntf());
        if (p_input) {
            timeA = var_GetInteger(p_input, "time");
            vlc_object_release(p_input);
        }
    } else if (!timeB) {
        input_thread_t * p_input = pl_CurrentInput(getIntf());
        if (p_input) {
            timeB = var_GetInteger(p_input, "time");
            vlc_object_release(p_input);
        }
    } else
        [self resetAtoB];
}

- (void)resetAtoB
{
    timeA = 0;
    timeB = 0;
}

- (void)updateAtoB
{
    if (timeB) {
        input_thread_t * p_input = pl_CurrentInput(getIntf());
        if (p_input) {
            vlc_tick_t currentTime = var_GetInteger(p_input, "time");
            if ( currentTime >= timeB || currentTime < timeA)
                var_SetInteger(p_input, "time", timeA);
            vlc_object_release(p_input);
        }
    }
}

- (void)volumeUp
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    playlist_VolumeUp(pl_Get(p_intf), 1, NULL);
    [self osdDisplayVolume];
}

- (void)volumeDown
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    playlist_VolumeDown(pl_Get(p_intf), 1, NULL);
    [self osdDisplayVolume];
}

- (void)toggleMute
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    playlist_MuteToggle(pl_Get(p_intf));
    if (playlist_MuteGet(pl_Get(p_intf)) > 0)
        [self osdDisplayIcon:OSD_MUTE_ICON];
    else
        [self osdDisplayVolume];
}

- (BOOL)mute
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return NO;

    BOOL b_is_muted = NO;
    b_is_muted = playlist_MuteGet(pl_Get(p_intf)) > 0;

    return b_is_muted;
}

- (int)volume
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return 0;

    float volume = playlist_VolumeGet(pl_Get(p_intf));

    return lroundf(volume * AOUT_VOLUME_DEFAULT);
}

- (void)setVolume: (int)i_value
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    if (i_value >= self.maxVolume)
        i_value = self.maxVolume;

    float f_value = i_value / (float)AOUT_VOLUME_DEFAULT;

    playlist_VolumeSet(pl_Get(p_intf), f_value);
}

- (float)maxVolume
{
    if (f_maxVolume == 0.) {
        f_maxVolume = (float)var_InheritInteger(getIntf(), "macosx-max-volume") / 100. * AOUT_VOLUME_DEFAULT;
    }

    return f_maxVolume;
}

- (void)addSubtitlesToCurrentInput:(NSArray *)paths
{
    input_thread_t * p_input = pl_CurrentInput(getIntf());
    if (!p_input)
        return;

    NSUInteger count = [paths count];

    for (int i = 0; i < count ; i++) {
        char *mrl = vlc_path2uri([[[paths objectAtIndex:i] path] UTF8String], NULL);
        if (!mrl)
            continue;
        msg_Dbg(getIntf(), "loading subs from %s", mrl);

        int i_result = input_AddSlave(p_input, SLAVE_TYPE_SPU, mrl, true, true, true);
        if (i_result != VLC_SUCCESS)
            msg_Warn(getIntf(), "unable to load subtitles from '%s'", mrl);
        free(mrl);
    }
    vlc_object_release(p_input);
}

- (void)showPosition
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (p_input != NULL) {
        vout_thread_t *p_vout = input_GetVout(p_input);
        if (p_vout != NULL) {
            var_SetInteger(getIntf()->obj.libvlc, "key-action", ACTIONID_POSITION);
            vlc_object_release(p_vout);
        }
        vlc_object_release(p_input);
    }
}

#pragma mark - Drop support for files into the video, controls bar or drop box

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;
{
    NSArray *items = [[[VLCMain sharedInstance] playlist] createItemsFromExternalPasteboard:[sender draggingPasteboard]];

    if (items.count == 0)
        return NO;

    [[[VLCMain sharedInstance] playlist] addPlaylistItems:items tryAsSubtitle:YES];
    return YES;
}

#pragma mark - video output stuff

- (void)setAspectRatioIsLocked:(BOOL)b_value
{
    config_PutInt(getIntf(), "macosx-lock-aspect-ratio", b_value);
}

- (BOOL)aspectRatioIsLocked
{
    return config_GetInt(getIntf(), "macosx-lock-aspect-ratio");
}

- (void)toggleFullscreen
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    vout_thread_t *p_vout = getVoutForActiveWindow();
    if (p_vout) {
        BOOL b_fs = var_ToggleBool(p_vout, "fullscreen");
        var_SetBool(pl_Get(p_intf), "fullscreen", b_fs);
        vlc_object_release(p_vout);
    } else { // e.g. lion fullscreen toggle
        BOOL b_fs = var_ToggleBool(pl_Get(p_intf), "fullscreen");
        [[[VLCMain sharedInstance] voutController] setFullscreen:b_fs forWindow:nil withAnimation:YES];
    }
}

#pragma mark - uncommon stuff

- (BOOL)fixIntfSettings
{
    NSMutableString * o_workString;
    NSRange returnedRange;
    NSRange fullRange;
    BOOL b_needsRestart = NO;

    #define fixpref(pref) \
    o_workString = [[NSMutableString alloc] initWithFormat:@"%s", config_GetPsz(getIntf(), pref)]; \
    if ([o_workString length] > 0) \
    { \
        returnedRange = [o_workString rangeOfString:@"macosx" options: NSCaseInsensitiveSearch]; \
        if (returnedRange.location != NSNotFound) \
        { \
            if ([o_workString isEqualToString:@"macosx"]) \
                [o_workString setString:@""]; \
            fullRange = NSMakeRange(0, [o_workString length]); \
            [o_workString replaceOccurrencesOfString:@":macosx" withString:@"" options: NSCaseInsensitiveSearch range: fullRange]; \
            fullRange = NSMakeRange(0, [o_workString length]); \
            [o_workString replaceOccurrencesOfString:@"macosx:" withString:@"" options: NSCaseInsensitiveSearch range: fullRange]; \
            \
            config_PutPsz(getIntf(), pref, [o_workString UTF8String]); \
            b_needsRestart = YES; \
        } \
    }

    fixpref("control");
    fixpref("extraintf");
    #undef fixpref

    return b_needsRestart;
}

#pragma mark - video filter handling

- (const char *)getFilterType:(const char *)psz_name
{
    module_t *p_obj = module_find(psz_name);
    if (!p_obj) {
        return NULL;
    }

    if (module_provides(p_obj, "video splitter")) {
        return "video-splitter";
    } else if (module_provides(p_obj, "video filter")) {
        return "video-filter";
    } else if (module_provides(p_obj, "sub source")) {
        return "sub-source";
    } else if (module_provides(p_obj, "sub filter")) {
        return "sub-filter";
    } else {
        msg_Err(getIntf(), "Unknown video filter type.");
        return NULL;
    }
}

- (void)setVideoFilter: (const char *)psz_name on:(BOOL)b_on
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;
    playlist_t *p_playlist = pl_Get(p_intf);
    char *psz_string, *psz_parser;

    const char *psz_filter_type = [self getFilterType:psz_name];
    if (!psz_filter_type) {
        msg_Err(p_intf, "Unable to find filter module \"%s\".", psz_name);
        return;
    }

    msg_Dbg(p_intf, "will turn filter '%s' %s", psz_name, b_on ? "on" : "off");

    psz_string = var_InheritString(p_playlist, psz_filter_type);

    if (b_on) {
        if (psz_string == NULL) {
            psz_string = strdup(psz_name);
        } else if (strstr(psz_string, psz_name) == NULL) {
            char *psz_tmp = strdup([[NSString stringWithFormat: @"%s:%s", psz_string, psz_name] UTF8String]);
            free(psz_string);
            psz_string = psz_tmp;
        }
    } else {
        if (!psz_string)
            return;

        psz_parser = strstr(psz_string, psz_name);
        if (psz_parser) {
            if (*(psz_parser + strlen(psz_name)) == ':') {
                memmove(psz_parser, psz_parser + strlen(psz_name) + 1,
                        strlen(psz_parser + strlen(psz_name) + 1) + 1);
            } else {
                *psz_parser = '\0';
            }

            /* Remove trailing : : */
            if (strlen(psz_string) > 0 && *(psz_string + strlen(psz_string) -1) == ':')
                *(psz_string + strlen(psz_string) -1) = '\0';
        } else {
            free(psz_string);
            return;
        }
    }
    var_SetString(p_playlist, psz_filter_type, psz_string);

    /* Try to set non splitter filters on the fly */
    if (strcmp(psz_filter_type, "video-splitter")) {
        NSArray<NSValue *> *vouts = getVouts();
        if (vouts)
            for (NSValue * val in vouts) {
                vout_thread_t *p_vout = [val pointerValue];
                var_SetString(p_vout, psz_filter_type, psz_string);
                vlc_object_release(p_vout);
            }
    }

    free(psz_string);
}

- (void)setVideoFilterProperty: (char const *)psz_property
                     forFilter: (char const *)psz_filter
                     withValue: (vlc_value_t)value
{
    NSArray<NSValue *> *vouts = getVouts();
    intf_thread_t *p_intf = getIntf();
    playlist_t *p_playlist = pl_Get(p_intf);
    if (!p_intf)
        return;
    int i_type = 0;
    bool b_is_command = false;
    char const *psz_filter_type = [self getFilterType: psz_filter];
    if (!psz_filter_type) {
        msg_Err(p_intf, "Unable to find filter module \"%s\".", psz_filter);
        return;
    }

    if (vouts && [vouts count])
    {
        i_type = var_Type((vout_thread_t *)[[vouts firstObject] pointerValue], psz_property);
        b_is_command = i_type & VLC_VAR_ISCOMMAND;
    }
    if (!i_type)
        i_type = config_GetType(psz_property);

    i_type &= VLC_VAR_CLASS;
    if (i_type == VLC_VAR_BOOL)
        var_SetBool(p_playlist, psz_property, value.b_bool);
    else if (i_type == VLC_VAR_INTEGER)
        var_SetInteger(p_playlist, psz_property, value.i_int);
    else if (i_type == VLC_VAR_FLOAT)
        var_SetFloat(p_playlist, psz_property, value.f_float);
    else if (i_type == VLC_VAR_STRING)
        var_SetString(p_playlist, psz_property, EnsureUTF8(value.psz_string));
    else
    {
        msg_Err(p_intf,
                "Module %s's %s variable is of an unsupported type ( %d )",
                psz_filter, psz_property, i_type);
        b_is_command = false;
    }

    if (b_is_command)
        if (vouts)
            for (NSValue *ptr in vouts)
            {
                vout_thread_t *p_vout = [ptr pointerValue];
                var_SetChecked(p_vout, psz_property, i_type, value);
#ifndef NDEBUG
                int i_cur_type = var_Type(p_vout, psz_property);
                assert((i_cur_type & VLC_VAR_CLASS) == i_type);
                assert(i_cur_type & VLC_VAR_ISCOMMAND);
#endif
            }

    if (vouts)
        for (NSValue *ptr in vouts)
            vlc_object_release((vout_thread_t *)[ptr pointerValue]);
}

#pragma mark -
#pragma mark Media Key support

- (void)resetMediaKeyJump
{
    b_mediakeyJustJumped = NO;
}

- (void)coreChangedMediaKeySupportSetting: (NSNotification *)o_notification
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    b_mediaKeySupport = var_InheritBool(p_intf, "macosx-mediakeys");
    if (b_mediaKeySupport && !_mediaKeyController)
        _mediaKeyController = [[SPMediaKeyTap alloc] initWithDelegate:self];

    VLCMain *main = [VLCMain sharedInstance];
    if (b_mediaKeySupport && ([[[main playlist] model] hasChildren] ||
                              [[main inputManager] hasInput])) {
        if (!b_mediaKeyTrapEnabled) {
            msg_Dbg(p_intf, "Enabling media key support");
            if ([_mediaKeyController startWatchingMediaKeys]) {
                b_mediaKeyTrapEnabled = YES;
            } else {
                msg_Warn(p_intf, "Failed to enable media key support, likely "
                    "app needs to be whitelisted in Security Settings.");
            }
        }
    } else {
        if (b_mediaKeyTrapEnabled) {
            b_mediaKeyTrapEnabled = NO;
            msg_Dbg(p_intf, "Disabling media key support");
            [_mediaKeyController stopWatchingMediaKeys];
        }
    }
}

- (void)mediaKeyTap:(SPMediaKeyTap *)keyTap
   receivedMediaKey:(SPKeyCode)keyCode
              state:(SPKeyState)keyState
             repeat:(BOOL)isRepeat
{
    if (keyCode == SPKeyCodePlay && keyState == SPKeyStateUp)
            [self playOrPause];

    if ((keyCode == SPKeyCodeFastForward || keyCode == SPKeyCodeNext) && !b_mediakeyJustJumped) {
        if (keyState == SPKeyStateUp && !isRepeat)
            [self next];
        else if (isRepeat) {
            [self forwardShort];
            b_mediakeyJustJumped = YES;
            [self performSelector:@selector(resetMediaKeyJump)
                       withObject: NULL
                       afterDelay:0.25];
        }
    }

    if ((keyCode == SPKeyCodeRewind || keyCode == SPKeyCodePrevious) && !b_mediakeyJustJumped) {
        if (keyState == SPKeyStateUp && !isRepeat)
            [self previous];
        else if (isRepeat) {
            [self backwardShort];
            b_mediakeyJustJumped = YES;
            [self performSelector:@selector(resetMediaKeyJump)
                       withObject: NULL
                       afterDelay:0.25];
        }
    }
}

#pragma mark -
#pragma mark Apple Remote Control

- (void)startListeningWithAppleRemote
{
    [_remote startListening: self];
}

- (void)stopListeningWithAppleRemote
{
    [_remote stopListening:self];
}

#pragma mark - menu navigation
- (void)menuFocusActivate
{
    input_thread_t *p_input_thread = pl_CurrentInput(getIntf());
    if (p_input_thread == NULL)
        return;

    input_Control(p_input_thread, INPUT_NAV_ACTIVATE, NULL );
    vlc_object_release(p_input_thread);
}

- (BOOL)hasDiscPopupMenu
{
    input_thread_t *p_input_thread = pl_CurrentInput(getIntf());
    if (p_input_thread == NULL)
        return NO;

    BOOL b_available = input_HasPopupMenu(p_input_thread) ? YES : NO;
    vlc_object_release(p_input_thread);
    return b_available;
}

- (void)showDiscPopupMenu
{
    input_thread_t *p_input_thread = pl_CurrentInput(getIntf());
    if (p_input_thread == NULL)
        return;

    input_ShowPopupMenu(p_input_thread);
    vlc_object_release(p_input_thread);
}

- (void)moveMenuFocusLeft
{
    input_thread_t *p_input_thread = pl_CurrentInput(getIntf());
    if (p_input_thread == NULL)
        return;

    input_Control(p_input_thread, INPUT_NAV_LEFT, NULL );
    vlc_object_release(p_input_thread);
}

- (void)moveMenuFocusRight
{
    input_thread_t *p_input_thread = pl_CurrentInput(getIntf());
    if (p_input_thread == NULL)
        return;

    input_Control(p_input_thread, INPUT_NAV_RIGHT, NULL );
    vlc_object_release(p_input_thread);
}

- (void)moveMenuFocusUp
{
    input_thread_t *p_input_thread = pl_CurrentInput(getIntf());
    if (p_input_thread == NULL)
        return;

    input_Control(p_input_thread, INPUT_NAV_UP, NULL );
    vlc_object_release(p_input_thread);
}

- (void)moveMenuFocusDown
{
    input_thread_t *p_input_thread = pl_CurrentInput(getIntf());
    if (p_input_thread == NULL)
        return;

    input_Control(p_input_thread, INPUT_NAV_DOWN, NULL );
    vlc_object_release(p_input_thread);
}

/* Helper method for the remote control interface in order to trigger forward/backward and volume
 increase/decrease as long as the user holds the left/right, plus/minus button */
- (void) executeHoldActionForRemoteButton: (NSNumber*) buttonIdentifierNumber
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    if (b_remote_button_hold) {
        switch([buttonIdentifierNumber intValue]) {
            case kRemoteButtonRight_Hold:
                [self forward];
                break;
            case kRemoteButtonLeft_Hold:
                [self backward];
                break;
            case kRemoteButtonVolume_Plus_Hold:
                if (p_intf)
                    var_SetInteger(p_intf->obj.libvlc, "key-action", ACTIONID_VOL_UP);
                break;
            case kRemoteButtonVolume_Minus_Hold:
                if (p_intf)
                    var_SetInteger(p_intf->obj.libvlc, "key-action", ACTIONID_VOL_DOWN);
                break;
        }
        if (b_remote_button_hold) {
            /* trigger event */
            [self performSelector:@selector(executeHoldActionForRemoteButton:)
                       withObject:buttonIdentifierNumber
                       afterDelay:0.25];
        }
    }
}

/* Apple Remote callback */
- (void) appleRemoteButton: (AppleRemoteEventIdentifier)buttonIdentifier
               pressedDown: (BOOL) pressedDown
                clickCount: (unsigned int) count
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    switch(buttonIdentifier) {
        case k2009RemoteButtonFullscreen:
            [self toggleFullscreen];
            break;
        case k2009RemoteButtonPlay:
            [self playOrPause];
            break;
        case kRemoteButtonPlay:
            if (count >= 2)
                [self toggleFullscreen];
            else
                [self playOrPause];
            break;
        case kRemoteButtonVolume_Plus:
            if (config_GetInt(getIntf(), "macosx-appleremote-sysvol"))
                [NSSound increaseSystemVolume];
            else
                if (p_intf)
                    var_SetInteger(p_intf->obj.libvlc, "key-action", ACTIONID_VOL_UP);
            break;
        case kRemoteButtonVolume_Minus:
            if (config_GetInt(getIntf(), "macosx-appleremote-sysvol"))
                [NSSound decreaseSystemVolume];
            else
                if (p_intf)
                    var_SetInteger(p_intf->obj.libvlc, "key-action", ACTIONID_VOL_DOWN);
            break;
        case kRemoteButtonRight:
            if (config_GetInt(getIntf(), "macosx-appleremote-prevnext"))
                [self forward];
            else
                [self next];
            break;
        case kRemoteButtonLeft:
            if (config_GetInt(getIntf(), "macosx-appleremote-prevnext"))
                [self backward];
            else
                [self previous];
            break;
        case kRemoteButtonRight_Hold:
        case kRemoteButtonLeft_Hold:
        case kRemoteButtonVolume_Plus_Hold:
        case kRemoteButtonVolume_Minus_Hold:
            /* simulate an event as long as the user holds the button */
            b_remote_button_hold = pressedDown;
            if (pressedDown) {
                NSNumber* buttonIdentifierNumber = [NSNumber numberWithInt:buttonIdentifier];
                [self performSelector:@selector(executeHoldActionForRemoteButton:)
                           withObject:buttonIdentifierNumber];
            }
            break;
        case kRemoteButtonMenu:
            [self showPosition];
            break;
        case kRemoteButtonPlay_Sleep:
        {
            NSAppleScript * script = [[NSAppleScript alloc] initWithSource:@"tell application \"System Events\" to sleep"];
            [script executeAndReturnError:nil];
            break;
        }
        default:
            /* Add here whatever you want other buttons to do */
            break;
    }
}

#pragma mark -
#pragma mark Key Shortcuts

/*****************************************************************************
 * hasDefinedShortcutKey: Check to see if the key press is a defined VLC
 * shortcut key.  If it is, pass it off to VLC for handling and return YES,
 * otherwise ignore it and return NO (where it will get handled by Cocoa).
 *****************************************************************************/

- (BOOL)keyEvent:(NSEvent *)o_event
{
    BOOL eventHandled = NO;
    NSString * characters = [o_event charactersIgnoringModifiers];
    if ([characters length] > 0) {
        unichar key = [characters characterAtIndex: 0];

        if (key) {
            input_thread_t * p_input = pl_CurrentInput(getIntf());
            if (p_input != NULL) {
                vout_thread_t *p_vout = input_GetVout(p_input);

                if (p_vout != NULL) {
                    /* Escape */
                    if (key == (unichar) 0x1b) {
                        if (var_GetBool(p_vout, "fullscreen")) {
                            [self toggleFullscreen];
                            eventHandled = YES;
                        }
                    }
                    vlc_object_release(p_vout);
                }
                vlc_object_release(p_input);
            }
        }
    }
    return eventHandled;
}

- (BOOL)hasDefinedShortcutKey:(NSEvent *)o_event force:(BOOL)b_force
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return NO;

    unichar key = 0;
    vlc_value_t val;
    unsigned int i_pressed_modifiers = 0;

    val.i_int = 0;
    i_pressed_modifiers = [o_event modifierFlags];

    if (i_pressed_modifiers & NSControlKeyMask)
        val.i_int |= KEY_MODIFIER_CTRL;

    if (i_pressed_modifiers & NSAlternateKeyMask)
        val.i_int |= KEY_MODIFIER_ALT;

    if (i_pressed_modifiers & NSShiftKeyMask)
        val.i_int |= KEY_MODIFIER_SHIFT;

    if (i_pressed_modifiers & NSCommandKeyMask)
        val.i_int |= KEY_MODIFIER_COMMAND;

    NSString * characters = [o_event charactersIgnoringModifiers];
    if ([characters length] > 0) {
        key = [[characters lowercaseString] characterAtIndex: 0];

        /* handle Lion's default key combo for fullscreen-toggle in addition to our own hotkeys */
        if (key == 'f' && i_pressed_modifiers & NSControlKeyMask && i_pressed_modifiers & NSCommandKeyMask) {
            [self toggleFullscreen];
            return YES;
        }

        if (!b_force) {
            switch(key) {
                case NSDeleteCharacter:
                case NSDeleteFunctionKey:
                case NSDeleteCharFunctionKey:
                case NSBackspaceCharacter:
                case NSUpArrowFunctionKey:
                case NSDownArrowFunctionKey:
                case NSEnterCharacter:
                case NSCarriageReturnCharacter:
                    return NO;
            }
        }

        val.i_int |= CocoaKeyToVLC(key);

        BOOL b_found_key = NO;
        for (NSUInteger i = 0; i < [_usedHotkeys count]; i++) {
            NSString *str = [_usedHotkeys objectAtIndex:i];
            unsigned int i_keyModifiers = [[VLCStringUtility sharedInstance] VLCModifiersToCocoa: str];

            if ([[characters lowercaseString] isEqualToString: [[VLCStringUtility sharedInstance] VLCKeyToString: str]] &&
                (i_keyModifiers & NSShiftKeyMask)     == (i_pressed_modifiers & NSShiftKeyMask) &&
                (i_keyModifiers & NSControlKeyMask)   == (i_pressed_modifiers & NSControlKeyMask) &&
                (i_keyModifiers & NSAlternateKeyMask) == (i_pressed_modifiers & NSAlternateKeyMask) &&
                (i_keyModifiers & NSCommandKeyMask)   == (i_pressed_modifiers & NSCommandKeyMask)) {
                b_found_key = YES;
                break;
            }
        }

        if (b_found_key) {
            var_SetInteger(p_intf->obj.libvlc, "key-pressed", val.i_int);
            return YES;
        }
    }

    return NO;
}

- (void)updateCurrentlyUsedHotkeys
{
    NSMutableArray *mutArray = [[NSMutableArray alloc] init];
    /* Get the main Module */
    module_t *p_main = module_get_main();
    assert(p_main);
    unsigned confsize;
    module_config_t *p_config;

    p_config = module_config_get (p_main, &confsize);

    for (size_t i = 0; i < confsize; i++) {
        module_config_t *p_item = p_config + i;

        if (CONFIG_ITEM(p_item->i_type) && p_item->psz_name != NULL
            && !strncmp(p_item->psz_name , "key-", 4)
            && !EMPTY_STR(p_item->psz_text)) {
            if (p_item->value.psz)
                [mutArray addObject:toNSStr(p_item->value.psz)];
        }
    }
    module_config_free (p_config);

    _usedHotkeys = [[NSArray alloc] initWithArray:mutArray copyItems:YES];
}

@end
