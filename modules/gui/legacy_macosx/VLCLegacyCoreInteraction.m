/*****************************************************************************
 * VLCLegacyCoreInteraction.m: core interaction for the legacy interface
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

#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyMainWindow.h"
#import "VLCLegacyVoutWindow.h"
#import "VLCLegacyAppleRemote.h"
#import "VLCLegacyMediaKeys.h"
#import "VLCLegacySystemVolume.h"
#import "misc.h"

#include <vlc_playlist.h>
#include <vlc_input.h>
#include <vlc_vout.h>
#include <vlc_vout_osd.h>
#include <vlc_actions.h>
#include <vlc_url.h>
#include <vlc_modules.h>
#include <vlc_configuration.h>
#include <vlc_charset.h>

/* gettext through the bundle, like the other legacy files */
#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

#include <sys/sysctl.h>
#if defined(__ppc__) || defined(__ppc64__) || defined(__POWERPC__)
# include <mach/machine.h>          /* CPU_SUBTYPE_POWERPC_970 */
#endif

/* See VLCLegacyCoreInteraction.h. */
bool VLCLegacyBestDeinterlaceAvailable(void)
{
#if defined(__ppc__) || defined(__ppc64__) || defined(__POWERPC__)
    int subtype = 0;
    size_t len = sizeof(subtype);
    if (sysctlbyname("hw.cpusubtype", &subtype, &len, NULL, 0) == 0)
        return subtype == CPU_SUBTYPE_POWERPC_970;   /* G5 only among PowerPC */
    return false;                                    /* unknown PPC → be safe */
#else
    return true;                                     /* Intel / Apple Silicon */
#endif
}

/* the core hotkeys module redirects the jump actions to this input
 * variable while the clip creation mode is active (keys pressed on the
 * video window go straight to the hotkeys module, never through the
 * interface). Value convention: +-1 = one frame, else signed
 * microseconds. Fired from the hotkeys thread: hop to the main thread,
 * where the clip state lives, through every runloop mode the panel may
 * sit in. */
static int VLCLegacyClipStepCallback(vlc_object_t *p_this,
    const char *psz_var, vlc_value_t oldval, vlc_value_t newval,
    void *p_data)
{
    VLC_UNUSED(p_this); VLC_UNUSED(psz_var); VLC_UNUSED(oldval);
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [(VLCLegacyCoreInteraction *)p_data
        performSelectorOnMainThread:@selector(clipStepFromCallback:)
                         withObject:[NSNumber numberWithLongLong:newval.i_int]
                      waitUntilDone:NO
                              modes:[NSArray arrayWithObjects:
                                     NSDefaultRunLoopMode,
                                     NSEventTrackingRunLoopMode,
                                     NSModalPanelRunLoopMode, nil]];
    [pool release];
    return VLC_SUCCESS;
}

/* the core saw a double click on the video while the windowed controls
 * were auto-hidden ("intf-reveal-controls", src/video_output/event.h):
 * hop to the main thread and bring them back. ⚠ the three explicit modes:
 * NSRunLoopCommonModes is 10.5+, and without the tracking/modal modes the
 * call sits until the current drag ends. */
static int VLCLegacyRevealControlsCallback(vlc_object_t *p_this,
    const char *psz_var, vlc_value_t oldval, vlc_value_t newval,
    void *p_data)
{
    (void)p_this; (void)psz_var; (void)oldval; (void)newval;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    VLCLegacyCoreInteraction *core = (VLCLegacyCoreInteraction *)p_data;
    [core performSelectorOnMainThread:@selector(revealControlsFromCore)
                           withObject:nil
                        waitUntilDone:NO
                                modes:[NSArray arrayWithObjects:
                                          NSDefaultRunLoopMode,
                                          NSEventTrackingRunLoopMode,
                                          NSModalPanelRunLoopMode, nil]];
    [pool release];
    return VLC_SUCCESS;
}

@implementation VLCLegacyCoreInteraction

- (id)initWithIntf:(intf_thread_t *)intf
{
    if (self = [super init]) {
        p_intf = intf;
        /* startup state is "stopped": no resume must fire before the
         * first play->stop transition is seen by the poll timer */
        lastPlaylistStatus = PLAYLIST_STOPPED;

        /* "Hide controls during playback" plumbing shared with the
         * core: the bool tells it the controls are gone (fullscreen
         * OSD, video double-click rerouted), the trigger is the core
         * asking for them back. */
        b_autoHideControls =
            var_InheritBool(p_intf, "legacy-macosx-hide-controls");
        var_Create(p_intf->obj.libvlc, "intf-controls-hidden",
                   VLC_VAR_BOOL);
        var_Create(p_intf->obj.libvlc, "intf-reveal-controls",
                   VLC_VAR_VOID);
        var_AddCallback(p_intf->obj.libvlc, "intf-reveal-controls",
                        VLCLegacyRevealControlsCallback, self);
    }
    return self;
}

- (void)shutdownAutoHide
{
    var_DelCallback(p_intf->obj.libvlc, "intf-reveal-controls",
                    VLCLegacyRevealControlsCallback, self);
    var_SetBool(p_intf->obj.libvlc, "intf-controls-hidden", false);
}

/*****************************************************************************
 * Hide controls during playback
 *****************************************************************************/

- (BOOL)autoHideControls
{
    return b_autoHideControls;
}

- (void)setAutoHideControls:(BOOL)enabled
{
    if (b_autoHideControls == enabled)
        return;
    b_autoHideControls = enabled;
    config_PutInt(p_intf, "legacy-macosx-hide-controls", enabled);
    /* the window poll applies the new state on its next tick */
}

- (BOOL)controlsHiddenForPlayback
{
    return b_controlsHiddenForPlayback;
}

- (void)setControlsHiddenForPlayback:(BOOL)hidden
{
    b_controlsHiddenForPlayback = hidden;
    var_SetBool(p_intf->obj.libvlc, "intf-controls-hidden", hidden);
}

/* the core saw a double click on the video while the controls were
 * auto-hidden (src/video_output/event.h): back to the main thread, then
 * bring them back */
- (void)revealControlsFromCore
{
    extern VLCLegacyMainWindow *VLCLegacyGetMainWindow(void);
    [VLCLegacyGetMainWindow() revealControlsForPlayback];
    /* ⚠ Vidéo en fenêtre SÉPARÉE : c'est cette fenêtre-là qui a rétracté sa
     * barre. Et il faut les DEUX chemins — le double-clic remonte la chaîne
     * des répondeurs jusqu'à la fenêtre sur le vout moderne (vérifié arm64),
     * mais le vout d'époque le rapporte au CŒUR, qui déclenche ceci (le
     * masquage paraissait sinon irréversible sur l'iBook G3). */
    [VLCLegacyCurrentVoutWindow() revealControlsForPlayback];
}

/* While the controls are hidden the keyboard is the only control
 * surface: mirror on the video what the invisible interface would have
 * shown, with the same OSD the core hotkeys use in fullscreen. Actions
 * going through the core hotkeys (seeks, wheel volume) already display
 * theirs. */
- (void)osdDisplayVolume
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    vout_thread_t *p_vout = input_GetVout(p_input);
    vlc_object_release(p_input);
    if (!p_vout)
        return;
    if (!b_controlsHiddenForPlayback && !var_GetBool(p_vout, "fullscreen")) {
        vlc_object_release(p_vout);
        return;
    }
    float volume = playlist_VolumeGet(pl_Get(p_intf));
    if (volume >= 0.) {
        /* A subpicture channel retains one ephemeral OSD at a time.  Putting
         * the text immediately after the slider on the shared channel
         * replaced the slider before the vout could draw it. */
        static vout_thread_t *s_slider_vout = NULL;
        static int s_slider_channel = 0;
        if (s_slider_vout != p_vout) {
            s_slider_vout = p_vout;
            s_slider_channel = vout_RegisterSubpictureChannel(p_vout);
        }
        vout_FlushSubpictureChannel(p_vout, s_slider_channel);
        long percent = lroundf(volume * 100.f);
        vout_OSDSlider(p_vout, s_slider_channel,
                       (int)percent, OSD_VERT_SLIDER);
        vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, _("Volume %ld%%"),
                        percent);
    }
    vlc_object_release(p_vout);
}

- (void)osdDisplayIcon:(short)icon
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    vout_thread_t *p_vout = input_GetVout(p_input);
    vlc_object_release(p_input);
    if (!p_vout)
        return;
    if (!b_controlsHiddenForPlayback && !var_GetBool(p_vout, "fullscreen")) {
        vlc_object_release(p_vout);
        return;
    }
    /* Keep transport feedback independent from position/text OSD queued by
     * the state transition itself. */
    static vout_thread_t *s_icon_vout = NULL;
    static int s_icon_channel = 0;
    if (s_icon_vout != p_vout) {
        s_icon_vout = p_vout;
        s_icon_channel = vout_RegisterSubpictureChannel(p_vout);
    }
    vout_FlushSubpictureChannel(p_vout, s_icon_channel);
    vout_OSDIcon(p_vout, s_icon_channel, icon);
    vlc_object_release(p_vout);
}

- (void)osdDisplayMessage:(const char *)message
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    vout_thread_t *p_vout = input_GetVout(p_input);
    vlc_object_release(p_input);
    if (!p_vout)
        return;
    if (!b_controlsHiddenForPlayback && !var_GetBool(p_vout, "fullscreen")) {
        vlc_object_release(p_vout);
        return;
    }
    vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s", message);
    vlc_object_release(p_vout);
}

- (intf_thread_t *)intf
{
    return p_intf;
}

/*****************************************************************************
 * transport
 *****************************************************************************/

- (void)play
{
    playlist_Play(pl_Get(p_intf));
}

- (void)togglePlayPause
{
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    bool b_empty = playlist_IsEmpty(p_playlist);
    playlist_Unlock(p_playlist);
    if (b_empty)
        return;

    /* resuming after the automatic end-bound pause replays the clip
     * from its start bound instead of continuing past the end */
    if (b_clipCreationMode && clipPausedAtEnd) {
        input_thread_t *p_input = playlist_CurrentInput(p_playlist);
        if (p_input) {
            if (var_GetInteger(p_input, "state") == PAUSE_S) {
                clipPausedAtEnd = 0;
                var_SetFloat(p_input, "position", (float)clipStartPos);
                clipLastPollPos = clipStartPos;
            }
            vlc_object_release(p_input);
        }
    }

    /* NOTE: Play/Pause deliberately does NOT skip the video-cache-mb
     * fill wait (it used to, via INPUT_SET_VIDEO_CACHE_SKIP): playback
     * must never start before the look-ahead cache reached its
    * threshold. A pause during the wait is harmless -- the cache
     * keeps filling while paused. */
    int64_t state = -1;
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (p_input) {
        state = var_GetInteger(p_input, "state");
        vlc_object_release(p_input);
    }
    playlist_TogglePause(p_playlist);
    if (state != -1)
        [self osdDisplayIcon:(state != PAUSE_S ? OSD_PAUSE_ICON
                                               : OSD_PLAY_ICON)];
}

- (void)stop
{
    playlist_Stop(pl_Get(p_intf));
}

- (void)next
{
    playlist_Next(pl_Get(p_intf));
    [self osdDisplayMessage:_("Next")];
}

- (void)previous
{
    playlist_Prev(pl_Get(p_intf));
    [self osdDisplayMessage:_("Previous")];
}

- (void)jumpWithSeconds:(int)seconds
{
    /* in clip creation mode the step shortcuts become one-FRAME nudges
     * of the last-selected bound knob (surgical trimming) */
    if (b_clipCreationMode) {
        [self clipStepFrames:(seconds >= 0 ? 1 : -1)];
        return;
    }
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    if (var_GetBool(p_input, "can-seek")) {
        int64_t length = var_GetInteger(p_input, "length");
        int64_t time = var_GetInteger(p_input, "time");
        var_SetInteger(p_input, "time-offset",
                       (int64_t)seconds * CLOCK_FREQ);
        vout_thread_t *p_vout = input_GetVout(p_input);
        if (p_vout && length > 0) {
            int64_t target = time + (int64_t)seconds * CLOCK_FREQ;
            if (target < 0)
                target = 0;
            else if (target > length)
                target = length;
            static vout_thread_t *s_position_vout = NULL;
            static int s_position_channel = 0;
            if (s_position_vout != p_vout) {
                s_position_vout = p_vout;
                s_position_channel = vout_RegisterSubpictureChannel(p_vout);
            }
            vout_FlushSubpictureChannel(p_vout, s_position_channel);
            vout_OSDSlider(p_vout, s_position_channel,
                           (int)(target * 100 / length), OSD_HOR_SLIDER);
        }
        if (p_vout)
            vlc_object_release(p_vout);
    }
    vlc_object_release(p_input);
}

- (void)setPositionFraction:(float)fraction
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    if (var_GetBool(p_input, "can-seek")) {
        if (fraction < 0.f)
            fraction = 0.f;
        else if (fraction > 1.f)
            fraction = 1.f;
        var_SetFloat(p_input, "position", fraction);
    }
    vlc_object_release(p_input);
}

/*****************************************************************************
 * rate
 *****************************************************************************/

- (void)faster
{
    [self triggerAction:ACTIONID_FASTER];
}

- (void)slower
{
    [self triggerAction:ACTIONID_SLOWER];
}

- (void)normalSpeed
{
    [self triggerAction:ACTIONID_RATE_NORMAL];
}

- (void)setPlaybackRate:(float)rate
{
    if (rate <= 0.f)
        rate = 1.f;
    var_SetFloat(pl_Get(p_intf), "rate", rate);
}

- (float)playbackRate
{
    float f_rate = var_GetFloat(pl_Get(p_intf), "rate");
    return f_rate > 0.f ? f_rate : 1.f;
}

/*****************************************************************************
 * record (port of -[VLCCoreInteraction toggleRecord])
 *****************************************************************************/

- (void)toggleRecord
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    var_ToggleBool(p_input, "record");
    vlc_object_release(p_input);
}

- (BOOL)recording
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return NO;
    BOOL b_recording = var_GetBool(p_input, "record") ? YES : NO;
    vlc_object_release(p_input);
    return b_recording;
}

- (BOOL)canRecord
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return NO;
    BOOL b_can = var_GetBool(p_input, "can-record") ? YES : NO;
    vlc_object_release(p_input);
    return b_can;
}

/*****************************************************************************
 * Clip creation mode (port of -[VLCCoreInteraction toggleClipCreationMode]):
 * both seek bar knobs define the clip bounds with instant preview; Record
 * then saves exactly that range, bounded core-side by the
 * "record-clip-position" / "record-stop-time" input variables.
 *****************************************************************************/

- (BOOL)clipCreationMode { return b_clipCreationMode; }
- (double)clipStartPosition { return clipStartPos; }
- (double)clipEndPosition { return clipEndPos; }
- (BOOL)clipRecordingActive { return b_clipRecordingActive; }
- (int)clipSelectedKnob { return clipSelectedKnob; }
- (void)setClipSelectedKnob:(int)knob { clipSelectedKnob = knob; }

- (void)setClipStartPosition:(double)pos
{
    if (pos < 0.) pos = 0.;
    else if (pos > 1.) pos = 1.;
    clipStartPos = pos;
    clipLastInteraction = [NSDate timeIntervalSinceReferenceDate];
    clipPausedAtEnd = 0;
}

- (void)setClipEndPosition:(double)pos
{
    if (pos < 0.) pos = 0.;
    else if (pos > 1.) pos = 1.;
    clipEndPos = pos;
    clipLastInteraction = [NSDate timeIntervalSinceReferenceDate];
    clipPausedAtEnd = 0;

    /* follow a live adjustment of the end bound during a clip recording */
    if (b_clipRecordingActive) {
        input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
        if (p_input) {
            int64_t duration = var_GetInteger(p_input, "length");
            if (duration > 0)
                var_SetInteger(p_input, "record-stop-time",
                               (int64_t)(pos * (double)duration));
            vlc_object_release(p_input);
        }
    }
}

- (void)toggleClipCreationMode
{
    if (b_clipCreationMode) {
        [self exitClipCreationMode];
        return;
    }

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    if (!var_GetBool(p_input, "can-seek")) {
        vlc_object_release(p_input);
        return;
    }

    double pos = var_GetFloat(p_input, "position");
    int64_t duration = var_GetInteger(p_input, "length");
    /* the mode is bound to this input: hold it so the poll can detect a
     * change of item by pointer identity */
    clipInput = p_input; /* transfers the reference */

    /* the hotkeys module redirects the jump shortcuts here while the
     * variable exists (see VLCLegacyClipStepCallback) */
    var_Create(p_input, "clip-frame-step",
               VLC_VAR_INTEGER | VLC_VAR_ISCOMMAND);
    var_AddCallback(p_input, "clip-frame-step",
                    VLCLegacyClipStepCallback, self);

    /* place the end knob right next to the start knob: 10 seconds ahead,
     * bounded to stay between 1% and 5% of the item */
    double delta = 0.05;
    if (duration > 0) {
        delta = (double)(10 * CLOCK_FREQ) / (double)duration;
        if (delta > 0.05) delta = 0.05;
        else if (delta < 0.01) delta = 0.01;
    }

    if (pos < 0.) pos = 0.;
    else if (pos > 1.) pos = 1.;
    clipStartPos = pos;
    clipEndPos = pos + delta;
    if (clipEndPos > 1.) clipEndPos = 1.;
    clipLastPollPos = -1.;
    /* frame-step shortcuts default to the end bound */
    clipSelectedKnob = 2;
    clipPausedAtEnd = 0;
    b_clipCreationMode = YES;
}

/* move the last-selected clip bound by a signed amount of seconds and
 * preview it (accurate seek shows the very frame, even while paused) */
- (void)clipNudgeSelectedBoundBySeconds:(double)seconds
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;

    int64_t duration = var_GetInteger(p_input, "length");
    if (duration <= 0) {
        vlc_object_release(p_input);
        return;
    }

    double step = seconds * (double)CLOCK_FREQ / (double)duration;
    double target;
    if (clipSelectedKnob == 1) {
        target = clipStartPos + step;
        if (target < 0.) target = 0.;
        if (target > clipEndPos) target = clipEndPos;
        clipStartPos = target;
    } else {
        target = clipEndPos + step;
        if (target < clipStartPos) target = clipStartPos;
        if (target > 1.) target = 1.;
        /* through the setter: follows a live record-stop-time */
        [self setClipEndPosition:target];
    }
    clipLastInteraction = [NSDate timeIntervalSinceReferenceDate];
    clipPausedAtEnd = 0;

    var_SetFloat(p_input, "position", (float)target);
    vlc_object_release(p_input);
}

/* one-frame nudge, for surgical trimming; falls back to 25 fps when the
 * demux did not expose the video frame rate */
- (void)clipStepFrames:(int)direction
{
    double frameSec = 1. / 25.;
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        input_item_t *p_item = input_GetItem(p_input);
        if (p_item) {
            vlc_mutex_lock(&p_item->lock);
            int i;
            for (i = 0; i < p_item->i_es; i++) {
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
    }
    [self clipNudgeSelectedBoundBySeconds:direction * frameSec];
}

/* handles a jump redirected by the core hotkeys module (main thread) */
- (void)clipStepFromCallback:(NSNumber *)value
{
    long long v = [value longLongValue];
    /* small value = a count of frames (it ramps up while the key is held),
     * larger = microseconds; see the convention in hotkeys.c */
    if (v != 0 && v >= -1000 && v <= 1000)
        [self clipStepFrames:(int)v];
    else
        [self clipNudgeSelectedBoundBySeconds:(double)v / CLOCK_FREQ];
}

- (void)exitClipCreationMode
{
    if (!b_clipCreationMode)
        return;

    /* a running extraction has no reason to survive the mode */
    if (p_clipExport)
        [self finishClipExportCancelled:YES];

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        var_SetInteger(p_input, "record-stop-time", 0);
        var_SetInteger(p_input, "record-start-time", 0);
        if (b_clipRecordingActive)
            var_SetBool(p_input, "record", false);
        vlc_object_release(p_input);
    }
    b_clipRecordingActive = NO;
    b_clipCreationMode = NO;
    if (clipInput) {
        /* stop redirecting the jump hotkeys — on the input the mode was
         * entered on, which we still hold */
        if (var_Type(clipInput, "clip-frame-step") != 0) {
            var_DelCallback(clipInput, "clip-frame-step",
                            VLCLegacyClipStepCallback, self);
            var_Destroy(clipInput, "clip-frame-step");
        }
        vlc_object_release(clipInput);
        clipInput = NULL;
    }
}

/* Message on the video and in the log: a fast extraction is over in a
 * blink and the user needs to be told where it went. */
- (void)clipExportNotify:(NSString *)message
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        vout_thread_t *p_vout = input_GetVout(p_input);
        vlc_object_release(p_input);
        if (p_vout) {
            vout_OSDMessage(p_vout, VOUT_SPU_CHANNEL_OSD, "%s",
                            [message UTF8String]);
            vlc_object_release(p_vout);
        }
    }
    msg_Info(p_intf, "%s", [message UTF8String]);
}

/* Starts the fast extraction of [A..B] on a second headless input, at disk
 * speed and without touching the playback. NO when the core cannot extract
 * from this input (live stream, unknown length): the caller then falls
 * back to the realtime recording. */
- (BOOL)startClipExportForInput:(input_thread_t *)p_input
{
    if (p_clipExport)
        return YES;

    int64_t duration = var_GetInteger(p_input, "length");
    if (duration <= 0)
        return NO;

    p_clipExport = input_ClipExportNew(p_intf, p_input,
                                       (vlc_tick_t)(clipStartPos * (double)duration),
                                       (vlc_tick_t)(clipEndPos * (double)duration));
    if (!p_clipExport)
        return NO;

    [self clipExportNotify:_NS("Exporting clip…")];
    return YES;
}

- (void)finishClipExportCancelled:(BOOL)cancelled
{
    if (!p_clipExport)
        return;

    char *psz_file = input_ClipExportFinish(p_clipExport);
    p_clipExport = NULL;

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
}

- (BOOL)clipExportInProgress
{
    return p_clipExport != NULL;
}

/* the extraction input is a child of the interface: it cannot outlive it */
- (void)shutdownClipExport
{
    if (p_clipExport)
        [self finishClipExportCancelled:YES];
}

- (void)recordClipToggle
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;

    if (p_clipExport) {
        /* a fast extraction is running: give it up */
        [self finishClipExportCancelled:YES];
    } else if (b_clipRecordingActive) {
        /* cancel the running clip recording */
        var_SetInteger(p_input, "record-stop-time", 0);
        var_SetInteger(p_input, "record-start-time", 0);
        var_SetBool(p_input, "record", false);
        b_clipRecordingActive = NO;
    } else if ([self startClipExportForInput:p_input]) {
        /* extracted at disk speed by a second input; the playback the
         * user is watching is not disturbed at all */
    } else {
        /* arm the demux-paced stop bound, then let the core seek to the
         * clip start and start recording in ONE input control */
        int64_t duration = var_GetInteger(p_input, "length");
        var_SetInteger(p_input, "record-stop-time",
                       duration > 0
                           ? (int64_t)(clipEndPos * (double)duration) : 0);
        var_SetInteger(p_input, "record-start-time",
                       duration > 0
                           ? (int64_t)(clipStartPos * (double)duration) : 0);
        var_SetFloat(p_input, "record-clip-position", (float)clipStartPos);
        b_clipRecordingActive = YES;
        clipPausedAtEnd = 0; /* the record control seeks by itself */
        b_clipRecordWaitingForStart = YES;
        if (var_GetInteger(p_input, "state") == PAUSE_S)
            playlist_TogglePause(pl_Get(p_intf));
    }
    vlc_object_release(p_input);
}

- (void)updateClipModeForInput:(input_thread_t *)p_input
{
    /* collect a finished fast extraction (polled on the window's timer,
     * which keeps ticking even with the playback paused) */
    if (p_clipExport && !input_ClipExportIsRunning(p_clipExport))
        [self finishClipExportCancelled:NO];

    if (!b_clipCreationMode)
        return;

    /* the mode is bound to the item it was entered on */
    if (!p_input || p_input != clipInput
        || var_GetInteger(p_input, "state") == END_S) {
        [self exitClipCreationMode];
        return;
    }

    /* the record state may have been ended core-side (record-stop-time) */
    if (b_clipRecordingActive && !var_GetBool(p_input, "record")) {
        b_clipRecordingActive = NO;
        b_clipRecordWaitingForStart = NO;
    }

    double pos = var_GetFloat(p_input, "position");
    int state = (int)var_GetInteger(p_input, "state");

    /* end-bound pause state machine: 1 = pause requested, 2 = confirmed
     * (playlist_Pause is asynchronous — without the intermediate state a
     * naive check would bounce the playback to the start instantly);
     * playing again from 2 replays the clip from its start bound, also
     * for resume paths that skip togglePlayPause (hotkeys...) */
    if (clipPausedAtEnd == 1 && state == PAUSE_S)
        clipPausedAtEnd = 2;
    else if (clipPausedAtEnd == 2 && state == PLAYING_S) {
        clipPausedAtEnd = 0;
        var_SetFloat(p_input, "position", (float)clipStartPos);
        clipLastPollPos = clipStartPos;
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
    double endBound = clipEndPos;
    if (!b_clipRecordingActive && posPerSec > 0.) {
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
    /* A clip recording is armed while the playback usually sits AT the
     * end bound (the B knob was just previewed, or the end-bound pause is
     * holding there). The seek back to the clip start is part of the
     * record control and takes a moment: until the position has come back
     * inside the clip, the end-bound test below would fire on the stale
     * position and kill the recording on the spot -- an empty or
     * header-only file. */
    BOOL interacting =
        ([NSDate timeIntervalSinceReferenceDate] - clipLastInteraction) < 0.5;
    if (b_clipRecordWaitingForStart) {
        if (!b_clipRecordingActive || pos < endBound)
            b_clipRecordWaitingForStart = NO;
        if (b_clipRecordWaitingForStart) {
            clipLastPollPos = pos;
            return;
        }
    }
    if (!interacting && state == PLAYING_S) {
        if (posPerSec > 0. && pos < clipStartPos - 0.25 * posPerSec) {
            var_SetFloat(p_input, "position", (float)clipStartPos);
            clipLastPollPos = clipStartPos;
            return;
        }
        if (pos >= endBound) {
            if (b_clipRecordingActive) {
                /* backstop -- the core normally ended it at the bound */
                var_SetBool(p_input, "record", false);
                b_clipRecordingActive = NO;
            }
            playlist_Pause(pl_Get(p_intf));
            clipPausedAtEnd = 1;
        }
    }
    clipLastPollPos = pos;
}

/*****************************************************************************
 * A->B loop (port of -[VLCCoreInteraction setAtoB]/updateAtoB)
 *****************************************************************************/

- (void)setAtoB
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    if (timeA == 0)
        timeA = var_GetInteger(p_input, "time");
    else if (timeB == 0)
        timeB = var_GetInteger(p_input, "time");
    else
        [self resetAtoB];
    vlc_object_release(p_input);
}

- (void)resetAtoB
{
    timeA = 0;
    timeB = 0;
}

- (void)updateAtoB
{
    if (timeB == 0)
        return;
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    int64_t i_current = var_GetInteger(p_input, "time");
    if (i_current >= timeB || i_current < timeA)
        var_SetInteger(p_input, "time", timeA);
    vlc_object_release(p_input);
}

/*****************************************************************************
 * hold-to-seek jumps
 *****************************************************************************/

- (void)jumpExtraShort:(BOOL)forward
{
    if (b_clipCreationMode) {
        [self clipStepFrames:(forward ? 1 : -1)];
        return;
    }
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    if (var_GetBool(p_input, "can-seek")) {
        int i_interval = (int)var_InheritInteger(p_input,
                                                 "extrashort-jump-size");
        if (i_interval > 0) {
            int64_t val = (int64_t)i_interval * CLOCK_FREQ
                        * (forward ? 1 : -1);
            var_SetInteger(p_input, "time-offset", val);
        }
    }
    vlc_object_release(p_input);
}

/*****************************************************************************
 * audio
 *****************************************************************************/

/* 5% steps, always landing on a multiple of 5 (see VLCLegacyStepVolume) */
- (void)stepVolume:(int)direction
{
    VLCLegacyStepVolume(p_intf, direction, false);
    [self osdDisplayVolume];
}

- (void)volumeUp
{
    [self stepVolume:1];
}

- (void)volumeDown
{
    [self stepVolume:-1];
}

- (void)toggleMute
{
    playlist_MuteToggle(pl_Get(p_intf));
    if (playlist_MuteGet(pl_Get(p_intf)) > 0)
        [self osdDisplayIcon:OSD_MUTE_ICON];
    else
        [self osdDisplayVolume];
}

- (BOOL)muted
{
    return playlist_MuteGet(pl_Get(p_intf)) > 0;
}

- (float)volume
{
    float f = playlist_VolumeGet(pl_Get(p_intf));
    return f < 0.f ? 1.f : f;
}

- (void)setVolume:(float)volume
{
    playlist_VolumeSet(pl_Get(p_intf), volume);
    [self osdDisplayVolume];
}

/*****************************************************************************
 * video
 *****************************************************************************/

/* ★★★ BASCULE PLEIN ÉCRAN — DEUX DÉCLENCHEURS AU LIEU D'UN (corrigé 2026-08-05).
 *
 * L'ancienne version basculait la variable de la PLAYLIST **puis** posait aussi
 * celle du VOUT. Or la première se propage DÉJÀ au vout par le rappel
 * playlist→vout du cœur : le vout recevait donc **deux transitions
 * indépendantes**, lancées depuis le FIL PRINCIPAL. La reconstruction de la
 * fenêtre vidéo, elle, doit s'exécuter sur ce même fil principal — qui était
 * encore occupé à l'intérieur du second `var_SetBool`. D'où un GEL COMPLET.
 *
 * ⚠⚠ CE QUI A RENDU LE DIAGNOSTIC DIFFICILE, et qu'il faut retenir : le
 * DOUBLE-CLIC ne gèle PAS, alors que **Commande + F** gèle à tous les coups.
 * Le double-clic naît dans le fil du VOUT et ne bascule que la variable du
 * vout : le fil principal reste libre de construire la fenêtre. C'est
 * l'utilisateur qui a repéré cette différence — sans elle, j'avais attribué à
 * tort le gel à la capture d'écran puis à la republication de la surbrillance,
 * deux pistes que cette observation innocente.
 *
 * On s'aligne donc sur l'interface moderne (`VLCCoreInteraction.m`) : le VOUT
 * est le maître, la variable de la playlist n'est qu'un MIROIR — un
 * `var_SetBool` et non un second `var_ToggleBool`. Sans vout (rien en lecture),
 * la playlist reste le seul porteur de l'état. */
- (void)toggleFullscreen
{
    playlist_t *p_playlist = pl_Get(p_intf);
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    vout_thread_t *p_vout = p_input ? input_GetVout(p_input) : NULL;

    if (p_vout) {
        const bool b_fs = var_ToggleBool(p_vout, "fullscreen");
        var_SetBool(p_playlist, "fullscreen", b_fs);   /* miroir, pas 2e bascule */
        vlc_object_release(p_vout);
    }
    else
        var_ToggleBool(p_playlist, "fullscreen");

    if (p_input)
        vlc_object_release(p_input);
}

- (void)setZoom:(float)factor
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    vout_thread_t *p_vout = input_GetVout(p_input);
    if (p_vout) {
        var_SetFloat(p_vout, "zoom", factor);
        vlc_object_release(p_vout);
    }
    vlc_object_release(p_input);
}

- (void)snapshot
{
    [self triggerAction:ACTIONID_SNAPSHOT];
}

/*****************************************************************************
 * generic helpers
 *****************************************************************************/

- (void)triggerAction:(int)actionId
{
    /* Same dispatch as the hotkeys core: the action is executed by the core
     * with the proper target objects (input, vout, aout). */
    var_SetInteger(p_intf->obj.libvlc, "key-action", actionId);
}

- (void)togglePlaylistBool:(const char *)name
{
    playlist_t *p_playlist = pl_Get(p_intf);
    var_ToggleBool(p_playlist, name);

    /* "video-on-top" also has to reach the active vout */
    if (!strcmp(name, "video-on-top")) {
        input_thread_t *p_input = playlist_CurrentInput(p_playlist);
        if (p_input) {
            vout_thread_t *p_vout = input_GetVout(p_input);
            if (p_vout) {
                var_SetBool(p_vout, "video-on-top",
                            var_GetBool(p_playlist, "video-on-top"));
                vlc_object_release(p_vout);
            }
            vlc_object_release(p_input);
        }
    }
}

- (BOOL)playlistBool:(const char *)name
{
    return var_GetBool(pl_Get(p_intf), name);
}

- (void)addSubtitleFileToCurrentInput:(NSString *)path
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    char *psz_uri = vlc_path2uri([path UTF8String], "file");
    if (psz_uri) {
        input_AddSlave(p_input, SLAVE_TYPE_SPU, psz_uri, true, true, false);
        free(psz_uri);
    }
    vlc_object_release(p_input);
}

/*****************************************************************************
 * video filter handling (10.4-safe port of VLCCoreInteraction)
 *****************************************************************************/

/* every vout of the current input; caller releases each entry */
static int legacyGetVouts(intf_thread_t *p_intf, vout_thread_t ***ppp_vouts,
                          size_t *pi_count)
{
    *ppp_vouts = NULL;
    *pi_count = 0;
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return VLC_EGENERIC;
    int ret = input_Control(p_input, INPUT_GET_VOUTS, ppp_vouts, pi_count);
    vlc_object_release(p_input);
    return ret;
}

static const char *legacyGetFilterType(intf_thread_t *p_intf,
                                       const char *psz_name)
{
    module_t *p_obj = module_find(psz_name);
    if (!p_obj)
        return NULL;

    if (module_provides(p_obj, "video splitter"))
        return "video-splitter";
    if (module_provides(p_obj, "video filter"))
        return "video-filter";
    if (module_provides(p_obj, "sub source"))
        return "sub-source";
    if (module_provides(p_obj, "sub filter"))
        return "sub-filter";
    msg_Err(p_intf, "Unknown video filter type.");
    return NULL;
}

- (void)setVideoFilter:(const char *)psz_name on:(BOOL)b_on
{
    playlist_t *p_playlist = pl_Get(p_intf);
    char *psz_string, *psz_parser;

    const char *psz_filter_type = legacyGetFilterType(p_intf, psz_name);
    if (!psz_filter_type) {
        msg_Err(p_intf, "Unable to find filter module \"%s\".", psz_name);
        return;
    }

    msg_Dbg(p_intf, "will turn filter '%s' %s", psz_name,
            b_on ? "on" : "off");

    psz_string = var_InheritString(p_playlist, psz_filter_type);

    if (b_on) {
        if (psz_string == NULL)
            psz_string = strdup(psz_name);
        else if (strstr(psz_string, psz_name) == NULL) {
            char *psz_tmp;
            if (asprintf(&psz_tmp, "%s:%s", psz_string, psz_name) == -1)
                psz_tmp = NULL;
            free(psz_string);
            psz_string = psz_tmp;
        }
        if (!psz_string)
            return;
    } else {
        if (!psz_string)
            return;

        psz_parser = strstr(psz_string, psz_name);
        if (psz_parser) {
            if (*(psz_parser + strlen(psz_name)) == ':')
                memmove(psz_parser, psz_parser + strlen(psz_name) + 1,
                        strlen(psz_parser + strlen(psz_name) + 1) + 1);
            else
                *psz_parser = '\0';

            /* Remove trailing : : */
            if (strlen(psz_string) > 0
             && *(psz_string + strlen(psz_string) - 1) == ':')
                *(psz_string + strlen(psz_string) - 1) = '\0';
        } else {
            free(psz_string);
            return;
        }
    }
    var_SetString(p_playlist, psz_filter_type, psz_string);

    /* Try to set non splitter filters on the fly */
    if (strcmp(psz_filter_type, "video-splitter")) {
        vout_thread_t **pp_vouts;
        size_t i_vouts, i;
        if (!legacyGetVouts(p_intf, &pp_vouts, &i_vouts) && pp_vouts) {
            for (i = 0; i < i_vouts; i++) {
                var_SetString(pp_vouts[i], psz_filter_type, psz_string);
                vlc_object_release(pp_vouts[i]);
            }
            free(pp_vouts);
        }
    }

    free(psz_string);
}

- (void)setVideoFilterProperty:(const char *)psz_property
                     forFilter:(const char *)psz_filter
                     withValue:(vlc_value_t)value
{
    playlist_t *p_playlist = pl_Get(p_intf);
    int i_type = 0;
    bool b_is_command = false;

    const char *psz_filter_type = legacyGetFilterType(p_intf, psz_filter);
    if (!psz_filter_type) {
        msg_Err(p_intf, "Unable to find filter module \"%s\".", psz_filter);
        return;
    }

    vout_thread_t **pp_vouts = NULL;
    size_t i_vouts = 0, i;
    legacyGetVouts(p_intf, &pp_vouts, &i_vouts);

    if (pp_vouts && i_vouts > 0) {
        i_type = var_Type(pp_vouts[0], psz_property);
        b_is_command = (i_type & VLC_VAR_ISCOMMAND) != 0;
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
        var_SetString(p_playlist, psz_property,
                      EnsureUTF8(value.psz_string));
    else {
        msg_Err(p_intf,
                "Module %s's %s variable is of an unsupported type ( %d )",
                psz_filter, psz_property, i_type);
        b_is_command = false;
    }

    if (pp_vouts) {
        for (i = 0; i < i_vouts; i++) {
            if (b_is_command)
                var_SetChecked(pp_vouts[i], psz_property, i_type, value);
            vlc_object_release(pp_vouts[i]);
        }
        free(pp_vouts);
    }
}

/*****************************************************************************
 * Apple Remote / media keys (10.4-safe port of VLCCoreInteraction)
 *****************************************************************************/

- (void)setupRemoteAndMediaKeys
{
    if (var_InheritBool(p_intf, "legacy-macosx-appleremote") && !remote) {
        remote = [[VLCLegacyAppleRemote alloc] init];
        /* double-click on the play button toggles fullscreen */
        [remote setClickCountEnabledButtons:kRemoteButtonPlay];
        [remote setDelegate:self];
    }

    if (var_InheritBool(p_intf, "legacy-macosx-mediakeys")
        && !mediaKeyTap) {
        mediaKeyTap = [[VLCLegacyMediaKeyTap alloc]
            initWithDelegate:self];
        if (![mediaKeyTap startWatchingMediaKeys])
            msg_Warn(p_intf, "failed to enable media key support (needs "
                     "Mac OS X 10.5, and possibly the accessibility "
                     "permission)");
    }

    /* poll for playback-state transitions (external player control) */
    if (!statusPollTimer) {
        statusPollTimer = [[NSTimer
            scheduledTimerWithTimeInterval:0.5
                                    target:self
                                  selector:@selector(pollPlaylistStatus:)
                                  userInfo:nil
                                   repeats:YES] retain];
    }
}

- (void)shutdownRemoteAndMediaKeys
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    b_remote_button_hold = NO;

    if (remote) {
        [remote setDelegate:nil];
        [remote stopListening:self];
        [remote release];
        remote = nil;
    }
    if (mediaKeyTap) {
        [mediaKeyTap stopWatchingMediaKeys];
        [mediaKeyTap release];
        mediaKeyTap = nil;
    }
    if (statusPollTimer) {
        [statusPollTimer invalidate];
        [statusPollTimer release];
        statusPollTimer = nil;
    }
    if (externalResumeTimer) {
        [externalResumeTimer invalidate];
        [externalResumeTimer release];
        externalResumeTimer = nil;
    }
}

- (void)startListeningWithAppleRemote
{
    if (remote && var_InheritBool(p_intf, "legacy-macosx-appleremote"))
        [remote startListening:self];
}

- (void)stopListeningWithAppleRemote
{
    if (remote)
        [remote stopListening:self];
}

/* Helper for the remote control: triggers forward/backward and volume
 * up/down as long as the user holds the left/right, plus/minus button */
- (void)executeHoldActionForRemoteButton:(NSNumber *)buttonIdentifierNumber
{
    if (!b_remote_button_hold)
        return;

    switch ([buttonIdentifierNumber intValue]) {
        case kRemoteButtonRight_Hold:
            [self jumpWithSeconds:10];
            break;
        case kRemoteButtonLeft_Hold:
            [self jumpWithSeconds:-10];
            break;
        case kRemoteButtonVolume_Plus_Hold:
            if (var_InheritBool(p_intf, "legacy-macosx-appleremote-sysvol"))
                VLCLegacySystemVolumeUp();
            else
                [self volumeUp];
            break;
        case kRemoteButtonVolume_Minus_Hold:
            if (var_InheritBool(p_intf, "legacy-macosx-appleremote-sysvol"))
                VLCLegacySystemVolumeDown();
            else
                [self volumeDown];
            break;
    }
    if (b_remote_button_hold) {
        /* re-trigger the event */
        [self performSelector:@selector(executeHoldActionForRemoteButton:)
                   withObject:buttonIdentifierNumber
                   afterDelay:0.25];
    }
}

/* Apple Remote callback (delegate of VLCLegacyAppleRemote) */
- (void)appleRemoteButton:(AppleRemoteEventIdentifier)buttonIdentifier
              pressedDown:(BOOL)pressedDown
               clickCount:(unsigned int)count
{
    BOOL b_sysvol =
        var_InheritBool(p_intf, "legacy-macosx-appleremote-sysvol");

    switch (buttonIdentifier) {
        case k2009RemoteButtonFullscreen:
            [self toggleFullscreen];
            break;
        case k2009RemoteButtonPlay:
            [self togglePlayPause];
            break;
        case kRemoteButtonPlay:
            if (count >= 2)
                [self toggleFullscreen];
            else
                [self togglePlayPause];
            break;
        case kRemoteButtonVolume_Plus:
            if (b_sysvol)
                VLCLegacySystemVolumeUp();
            else
                [self volumeUp];
            break;
        case kRemoteButtonVolume_Minus:
            if (b_sysvol)
                VLCLegacySystemVolumeDown();
            else
                [self volumeDown];
            break;
        case kRemoteButtonRight:
            [self next];
            break;
        case kRemoteButtonLeft:
            [self previous];
            break;
        case kRemoteButtonRight_Hold:
        case kRemoteButtonLeft_Hold:
        case kRemoteButtonVolume_Plus_Hold:
        case kRemoteButtonVolume_Minus_Hold:
            /* simulate an event as long as the user holds the button */
            b_remote_button_hold = pressedDown;
            if (pressedDown) {
                [self performSelector:
                        @selector(executeHoldActionForRemoteButton:)
                           withObject:[NSNumber numberWithInt:
                               buttonIdentifier]];
            }
            break;
        case kRemoteButtonMenu:
            /* show the position OSD, like the modern interface */
            [self triggerAction:ACTIONID_POSITION];
            break;
        case kRemoteButtonPlay_Sleep:
        {
            NSAppleScript *script = [[NSAppleScript alloc] initWithSource:
                @"tell application \"System Events\" to sleep"];
            [script executeAndReturnError:nil];
            [script release];
            break;
        }
        default:
            /* other buttons are ignored */
            break;
    }
}

/*****************************************************************************
 * media keys (delegate of VLCLegacyMediaKeyTap)
 *****************************************************************************/

- (void)resetMediaKeyJump
{
    b_mediakeyJustJumped = NO;
}

- (void)mediaKeyTap:(VLCLegacyMediaKeyTap *)keyTap
   receivedMediaKey:(int)keyCode
              state:(int)keyState
             repeat:(BOOL)isRepeat
{
    (void)keyTap;
    if (keyCode == NX_KEYTYPE_PLAY && keyState == NX_KEYUP)
        [self togglePlayPause];

    if ((keyCode == NX_KEYTYPE_FAST || keyCode == NX_KEYTYPE_NEXT)
        && !b_mediakeyJustJumped) {
        if (keyState == NX_KEYUP && !isRepeat)
            [self next];
        else if (isRepeat) {
            [self jumpWithSeconds:10];
            b_mediakeyJustJumped = YES;
            [self performSelector:@selector(resetMediaKeyJump)
                       withObject:nil
                       afterDelay:0.25];
        }
    }

    if ((keyCode == NX_KEYTYPE_REWIND || keyCode == NX_KEYTYPE_PREVIOUS)
        && !b_mediakeyJustJumped) {
        if (keyState == NX_KEYUP && !isRepeat)
            [self previous];
        else if (isRepeat) {
            [self jumpWithSeconds:-10];
            b_mediakeyJustJumped = YES;
            [self performSelector:@selector(resetMediaKeyJump)
                       withObject:nil
                       afterDelay:0.25];
        }
    }
}

/*****************************************************************************
 * external music players (iTunes / Apple Music / Spotify)
 *
 * The modern interface uses ScriptingBridge (ObjC 2 only); here the same
 * behavior goes through NSAppleScript, available since 10.4. Only ever
 * called from timers, hence on the main thread, as NSAppleScript
 * requires.
 *****************************************************************************/

/* NSWorkspace launchedApplications (deprecated but present from 10.2 to
 * today) instead of NSRunningApplication (10.6+) */
- (BOOL)isAppRunning:(NSString *)bundleId
{
    NSArray *apps = [[NSWorkspace sharedWorkspace] launchedApplications];
    unsigned i;
    for (i = 0; i < [apps count]; i++) {
        NSDictionary *app = [apps objectAtIndex:i];
        NSString *identifier =
            [app objectForKey:@"NSApplicationBundleIdentifier"];
        if (identifier && [identifier isEqualToString:bundleId])
            return YES;
    }
    return NO;
}

/* one-line result of an AppleScript source, nil on error (autoreleased) */
- (NSString *)runAppleScript:(NSString *)source
{
    NSAppleScript *script =
        [[NSAppleScript alloc] initWithSource:source];
    NSAppleEventDescriptor *result = [script executeAndReturnError:nil];
    NSString *value = [[[result stringValue] retain] autorelease];
    [script release];
    return value;
}

/* pauses appName ("iTunes"...) when it is playing; returns YES when WE
 * paused it (so only then it may be resumed later) */
- (BOOL)pauseExternalPlayerNamed:(NSString *)appName
{
    NSString *state = [self runAppleScript:[NSString stringWithFormat:
        @"tell application \"%@\" to player state as string", appName]];
    if (state && [state isEqualToString:@"playing"]) {
        [self runAppleScript:[NSString stringWithFormat:
            @"tell application \"%@\" to pause", appName]];
        return YES;
    }
    return NO;
}

/* resumes appName when it is still paused (i.e. the user did not touch
 * it in between) */
- (void)resumeExternalPlayerNamed:(NSString *)appName
{
    NSString *state = [self runAppleScript:[NSString stringWithFormat:
        @"tell application \"%@\" to player state as string", appName]];
    if (state && [state isEqualToString:@"paused"])
        [self runAppleScript:[NSString stringWithFormat:
            @"tell application \"%@\" to play", appName]];
}

- (void)stopExternalPlayers
{
    if (var_InheritInteger(p_intf, "legacy-macosx-control-itunes") <= 0)
        return;

    if (!b_has_itunes_paused && [self isAppRunning:@"com.apple.iTunes"])
        b_has_itunes_paused = [self pauseExternalPlayerNamed:@"iTunes"];
    if (!b_has_applemusic_paused
        && [self isAppRunning:@"com.apple.Music"])
        b_has_applemusic_paused =
            [self pauseExternalPlayerNamed:@"Music"];
    if (!b_has_spotify_paused
        && [self isAppRunning:@"com.spotify.client"])
        b_has_spotify_paused = [self pauseExternalPlayerNamed:@"Spotify"];
}

- (void)resumeExternalPlayers
{
    if (var_InheritInteger(p_intf, "legacy-macosx-control-itunes") > 1) {
        if (b_has_itunes_paused
            && [self isAppRunning:@"com.apple.iTunes"])
            [self resumeExternalPlayerNamed:@"iTunes"];
        if (b_has_applemusic_paused
            && [self isAppRunning:@"com.apple.Music"])
            [self resumeExternalPlayerNamed:@"Music"];
        if (b_has_spotify_paused
            && [self isAppRunning:@"com.spotify.client"])
            [self resumeExternalPlayerNamed:@"Spotify"];
    }
    b_has_itunes_paused = NO;
    b_has_applemusic_paused = NO;
    b_has_spotify_paused = NO;
}

- (void)externalResumeTimerFired:(NSTimer *)timer
{
    (void)timer;
    [externalResumeTimer release];
    externalResumeTimer = nil;
    [self resumeExternalPlayers];
}

- (void)pollPlaylistStatus:(NSTimer *)timer
{
    (void)timer;
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    int status = playlist_Status(p_playlist);
    playlist_Unlock(p_playlist);

    if (status == lastPlaylistStatus)
        return;
    lastPlaylistStatus = status;

    if (status == PLAYLIST_RUNNING) {
        /* playback (re)started: no pending resume, pause the others */
        if (externalResumeTimer) {
            [externalResumeTimer invalidate];
            [externalResumeTimer release];
            externalResumeTimer = nil;
        }
        [self stopExternalPlayers];
    } else if (status == PLAYLIST_STOPPED) {
        /* small delay, like the modern interface: skipping between
         * items briefly reports "stopped" too */
        if (!externalResumeTimer) {
            externalResumeTimer = [[NSTimer
                scheduledTimerWithTimeInterval:0.5
                                        target:self
                                      selector:
                    @selector(externalResumeTimerFired:)
                                      userInfo:nil
                                       repeats:NO] retain];
        }
    }
}

@end
