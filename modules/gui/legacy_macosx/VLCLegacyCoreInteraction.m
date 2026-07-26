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
#import "VLCLegacyAppleRemote.h"
#import "VLCLegacyMediaKeys.h"
#import "VLCLegacySystemVolume.h"
#import "misc.h"

#include <vlc_playlist.h>
#include <vlc_input.h>
#include <vlc_vout.h>
#include <vlc_actions.h>
#include <vlc_url.h>
#include <vlc_modules.h>
#include <vlc_configuration.h>
#include <vlc_charset.h>

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

@implementation VLCLegacyCoreInteraction

- (id)initWithIntf:(intf_thread_t *)intf
{
    if (self = [super init]) {
        p_intf = intf;
        /* startup state is "stopped": no resume must fire before the
         * first play->stop transition is seen by the poll timer */
        lastPlaylistStatus = PLAYLIST_STOPPED;
    }
    return self;
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

    /* NOTE: Play/Pause deliberately does NOT skip the video-cache-mb
     * fill wait (it used to, via INPUT_SET_VIDEO_CACHE_SKIP): playback
     * must never start before the look-ahead cache reached its
     * threshold. A pause during the wait is harmless -- the cache
     * keeps filling while paused. */
    playlist_TogglePause(p_playlist);
}

- (void)stop
{
    playlist_Stop(pl_Get(p_intf));
}

- (void)next
{
    playlist_Next(pl_Get(p_intf));
}

- (void)previous
{
    playlist_Prev(pl_Get(p_intf));
}

- (void)jumpWithSeconds:(int)seconds
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    if (var_GetBool(p_input, "can-seek"))
        var_SetInteger(p_input, "time-offset",
                       (int64_t)seconds * CLOCK_FREQ);
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
}

/*****************************************************************************
 * video
 *****************************************************************************/

- (void)toggleFullscreen
{
    playlist_t *p_playlist = pl_Get(p_intf);
    var_ToggleBool(p_playlist, "fullscreen");
    /* Forward to the active vout, if any, so it takes effect immediately */
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (p_input) {
        vout_thread_t *p_vout = input_GetVout(p_input);
        if (p_vout) {
            var_SetBool(p_vout, "fullscreen",
                        var_GetBool(p_playlist, "fullscreen"));
            vlc_object_release(p_vout);
        }
        vlc_object_release(p_input);
    }
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
