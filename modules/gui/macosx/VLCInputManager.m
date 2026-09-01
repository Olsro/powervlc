/*****************************************************************************
 * VLCInputManager.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2015 VLC authors and VideoLAN
 * $Id$
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

#import "VLCInputManager.h"

#include <vlc_url.h>

#import "VLCCoreInteraction.h"
#import "CompatibilityFixes.h"
#import "VLCExtensionsManager.h"
#import "VLCMain.h"
#import "VLCMainMenu.h"
#import "VLCMainWindow.h"
#import "VLCPlaylist.h"
#import "VLCPlaylistInfo.h"
#import "VLCResumeDialogController.h"
#import "VLCTrackSynchronizationWindowController.h"
#import "VLCVoutView.h"
#import "VLCRemoteControlService.h"
#import "VLCStringUtility.h"

#import "iTunes.h"
#import "Spotify.h"

#include <vlc_actions.h>
#include <vlc_vout_osd.h>

NSString *VLCPlayerRateChanged = @"VLCPlayerRateChanged";

@interface VLCInputManager()
- (void)updateMainMenu;
- (void)updateMainWindow;
- (void)updateMetaAndInfo;
- (void)updateDelays;
- (void)cancelResumeOSD;
- (void)resumeOSDTick:(NSTimer *)timer;
@end

#pragma mark Callbacks

static int InputThreadChanged(vlc_object_t *p_this, const char *psz_var,
                              vlc_value_t oldval, vlc_value_t new_val, void *param)
{
    @autoreleasepool {
        VLCInputManager *inputManager = (__bridge VLCInputManager *)param;
        [inputManager performSelectorOnMainThread:@selector(inputThreadChanged) withObject:nil waitUntilDone:NO];
    }

    return VLC_SUCCESS;
}

static NSDate *lastPositionUpdate = nil;

static int InputEvent(vlc_object_t *p_this, const char *psz_var,
                      vlc_value_t oldval, vlc_value_t new_val, void *param)
{
    @autoreleasepool {
        VLCInputManager *inputManager = (__bridge VLCInputManager *)param;

        switch (new_val.i_int) {
            case INPUT_EVENT_STATE:
                [inputManager performSelectorOnMainThread:@selector(playbackStatusUpdated) withObject: nil waitUntilDone:NO];
                break;
            case INPUT_EVENT_RATE:
                [[[VLCMain sharedInstance] mainMenu] performSelectorOnMainThread:@selector(updatePlaybackRate) withObject: nil waitUntilDone:NO];
                [[NSNotificationCenter defaultCenter] postNotificationName:VLCPlayerRateChanged object:nil];
                break;
            case INPUT_EVENT_POSITION:

                // Rate limit to 100 ms
                if (lastPositionUpdate && fabs([lastPositionUpdate timeIntervalSinceNow]) < 0.1)
                    break;

                lastPositionUpdate = [NSDate date];

                [inputManager performSelectorOnMainThread:@selector(playbackPositionUpdated) withObject:nil waitUntilDone:NO];
                break;
            case INPUT_EVENT_TITLE:
            case INPUT_EVENT_CHAPTER:
                [inputManager performSelectorOnMainThread:@selector(updateMainMenu) withObject: nil waitUntilDone:NO];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:VLCInputTitleChangedNotification
                                      object:nil];
                });
                break;
            case INPUT_EVENT_CACHE:
                [inputManager performSelectorOnMainThread:@selector(updateMainWindow) withObject:nil waitUntilDone:NO];
                break;
            case INPUT_EVENT_STATISTICS:
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[[VLCMain sharedInstance] currentMediaInfoPanel] updateStatistics];
                });
                break;
            case INPUT_EVENT_ES:
                break;
            case INPUT_EVENT_TELETEXT:
                break;
            case INPUT_EVENT_AOUT:
                break;
            case INPUT_EVENT_VOUT:
                break;
            case INPUT_EVENT_ITEM_META:
            case INPUT_EVENT_ITEM_INFO:
                [inputManager performSelectorOnMainThread:@selector(updateMainMenu) withObject: nil waitUntilDone:NO];
                [inputManager performSelectorOnMainThread:@selector(updateName) withObject: nil waitUntilDone:NO];
                [inputManager performSelectorOnMainThread:@selector(updateMetaAndInfo) withObject: nil waitUntilDone:NO];
                break;
            case INPUT_EVENT_BOOKMARK:
                dispatch_async(dispatch_get_main_queue(), ^{
                    [[NSNotificationCenter defaultCenter]
                        postNotificationName:VLCBookmarksChangedNotification object:nil];
                });
                break;
            case INPUT_EVENT_RECORD:
                dispatch_async(dispatch_get_main_queue(), ^{
                    BOOL b_recording = var_InheritBool(p_this, "record");
                    [[[VLCMain sharedInstance] mainMenu] updateRecordState: b_recording];
                    [[VLCCoreInteraction sharedInstance] recordStateChanged: b_recording];
                });
                break;
            case INPUT_EVENT_PROGRAM:
                [inputManager performSelectorOnMainThread:@selector(updateMainMenu) withObject: nil waitUntilDone:NO];
                break;
            case INPUT_EVENT_ITEM_EPG:
                break;
            case INPUT_EVENT_SIGNAL:
                break;

            case INPUT_EVENT_AUDIO_DELAY:
            case INPUT_EVENT_SUBTITLE_DELAY:
                [inputManager performSelectorOnMainThread:@selector(updateDelays) withObject:nil waitUntilDone:NO];
                break;

            case INPUT_EVENT_DEAD:
                [inputManager performSelectorOnMainThread:@selector(updateName) withObject: nil waitUntilDone:NO];
                [[[VLCMain sharedInstance] mainWindow] performSelectorOnMainThread:@selector(updateTimeSlider) withObject:nil waitUntilDone:NO];
                break;

            default:
                break;
        }

        return VLC_SUCCESS;
    }
}

#pragma mark -
#pragma mark InputManager implementation

@interface VLCInputManager()
{
    __weak VLCMain *o_main;

    input_thread_t *p_current_input;
    dispatch_queue_t informInputChangedQueue;

    /* sleep management */
    IOPMAssertionID systemSleepAssertionID;
    IOPMAssertionID monitorSleepAssertionID;

    IOPMAssertionID userActivityAssertionID;

    /* iTunes/Apple Music/Spotify play/pause support */
    BOOL b_has_itunes_paused;
    BOOL b_has_applemusic_paused;
    BOOL b_has_spotify_paused;

    NSTimer *hasEndedTimer;

    /* INPUT_EVENT_POSITION is the one common path for keyboard, OSD and
     * remote-control seeks.  Keep a short media/wall-clock baseline here so
     * feedback does not depend on which Cocoa window happened to receive the
     * key event. */
    vlc_tick_t feedbackLastMediaTime;
    NSTimeInterval feedbackLastWallTime;
    BOOL feedbackPositionPrimed;
    int feedbackLastPlaybackState;

    /* The resume question lives in the video OSD instead of a native panel:
     * it consequently follows the vout onto the 3D display and is duplicated
     * for both eyes by the stereo OSD compositor. The deadline starts only
     * once a vout exists, not while HDMI frame packing is being engaged. */
    NSTimer *resumeOSDTimer;
    vlc_tick_t resumeOSDTarget;
    NSTimeInterval resumeOSDDeadline;
    NSTimeInterval resumeOSDLastDraw;
    int resumeOSDLastCountdown;
    BOOL resumeOSDContinueSelected;
    BOOL resumeOSDAutoCloseCancelled;

    VLCRemoteControlService *_remoteControlService;
}
@end

@implementation VLCInputManager

+ (void)initialize
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
                                 [NSArray array], @"recentlyPlayedMediaList",
                                 [NSDictionary dictionary], @"recentlyPlayedMedia", nil];

    [defaults registerDefaults:appDefaults];
}

- (id)initWithMain:(VLCMain *)o_mainObj
{
    self = [super init];
    if (self) {
        intf_thread_t *p_intf = getIntf();
        msg_Dbg(p_intf, "Initializing input manager");

        o_main = o_mainObj;
        var_AddCallback(pl_Get(p_intf), "input-current", InputThreadChanged, (__bridge void *)self);

        informInputChangedQueue = dispatch_queue_create("org.videolan.vlc.inputChangedQueue", DISPATCH_QUEUE_SERIAL);

        if (@available(macOS 10.12.2, *)) {
            BOOL b_mediaKeySupport = var_InheritBool(p_intf, "macosx-mediakeys");
            if (b_mediaKeySupport) {
                _remoteControlService = [[VLCRemoteControlService alloc] init];
                [_remoteControlService subscribeToRemoteCommands];
            }
            [[NSNotificationCenter defaultCenter] addObserver:self
                                                     selector:@selector(coreChangedMediaKeySupportSetting:)
                                                         name:VLCMediaKeySupportSettingChangedNotification
                                                       object:nil];
        }
    }
    return self;
}

/*
 * TODO: Investigate if this can be moved to dealloc again. Current problems:
 * - dealloc might be never called of this object, as strong references could be in the
 *   (already stopped) main loop, preventing the refcount to go 0.
 * - Calling var_DelCallback waits for all callbacks to finish. Thus, while dealloc is already
 *   called, callback might grab a reference to this object again, which could cause trouble.
 */
- (void)deinit
{
    msg_Dbg(getIntf(), "Deinitializing input manager");

    [[NSNotificationCenter defaultCenter] removeObserver: self];

    [self cancelResumeOSD];

    if (p_current_input) {
        /* continue playback where you left off */
        [self storePlaybackPositionForItem:p_current_input];

        var_DelCallback(p_current_input, "intf-event", InputEvent, (__bridge void *)self);
        vlc_object_release(p_current_input);
        p_current_input = NULL;
    }

    if (@available(macOS 10.12.2, *)) {
        [_remoteControlService unsubscribeFromRemoteCommands];
    }

    var_DelCallback(pl_Get(getIntf()), "input-current", InputThreadChanged, (__bridge void *)self);

#if !OS_OBJECT_USE_OBJC
    dispatch_release(informInputChangedQueue);
#endif
}

- (void)inputThreadChanged
{
    [self cancelResumeOSD];
    feedbackPositionPrimed = NO;
    feedbackLastMediaTime = 0;
    feedbackLastWallTime = 0.;
    feedbackLastPlaybackState = -1;

    if (p_current_input) {
        var_DelCallback(p_current_input, "intf-event", InputEvent, (__bridge void *)self);
        vlc_object_release(p_current_input);
        p_current_input = NULL;

        [[o_main mainMenu] setRateControlsEnabled: NO];

        [[NSNotificationCenter defaultCenter] postNotificationName:VLCInputChangedNotification
                                                            object:nil];
    }

    input_thread_t *p_input_changed = NULL;

    // object is hold here and released then it is dead
    p_current_input = playlist_CurrentInput(pl_Get(getIntf()));
    if (p_current_input) {
        var_AddCallback(p_current_input, "intf-event", InputEvent, (__bridge void *)self);
        [self playbackStatusUpdated];
        [[o_main mainMenu] setRateControlsEnabled: YES];

        if ([o_main activeVideoPlayback] && [[[o_main mainWindow] videoView] isHidden]) {
            [[o_main mainWindow] changePlaylistState: psPlaylistItemChangedEvent];
        }

        p_input_changed = vlc_object_hold(p_current_input);

        [[o_main playlist] currentlyPlayingItemChanged];

        [self continuePlaybackWhereYouLeftOff:p_current_input];

        [[NSNotificationCenter defaultCenter] postNotificationName:VLCInputChangedNotification
                                                            object:nil];
    }

    [self updateMetaAndInfo];

    [self updateMainWindow];
    [self updateDelays];
    [self updateMainMenu];

    /*
     * Due to constraints within NSAttributedString's main loop runtime handling
     * and other issues, we need to inform the extension manager on a separate thread.
     * The serial queue ensures that changed inputs are propagated in the same order as they arrive.
     */
    dispatch_async(informInputChangedQueue, ^{
        [[o_main extensionsManager] inputChanged:p_input_changed];
        if (p_input_changed)
            vlc_object_release(p_input_changed);
    });
}

- (void)playbackPositionUpdated
{
    if (p_current_input) {
        const vlc_tick_t mediaTime = var_GetInteger(p_current_input, "time");
        const NSTimeInterval wallTime =
            [NSDate timeIntervalSinceReferenceDate];

        /* BD-J regularly switches playlists and resets the title clock when
         * moving between menu clips and the feature.  Those discontinuities
         * are not user seeks; the generic heuristic below used to turn them
         * into a duplicated stereo position OSD.  Real seek actions already
         * request their feedback explicitly through the hotkeys/UI path. */
        const BOOL blurayDiscSession =
            var_GetBool(p_current_input, "bluray-disc-session");
        if (feedbackPositionPrimed && !blurayDiscSession) {
            const NSTimeInterval wallDelta =
                wallTime - feedbackLastWallTime;

            /* A network/MVC seek can take several seconds before the first
             * new position event arrives.  Still compare those delayed
             * events, but require actual media movement below so a plain
             * decoder stall cannot masquerade as a backwards seek. */
            if (wallDelta >= 0. && wallDelta <= 30.) {
                double expectedDelta = 0.;
                if (var_GetInteger(p_current_input, "state") == PLAYING_S) {
                    float rate = var_GetFloat(p_current_input, "rate");
                    if (rate <= 0.f)
                        rate = 1.f;
                    expectedDelta = wallDelta * (double)CLOCK_FREQ * rate;
                }

                const double discontinuity =
                    (double)(mediaTime - feedbackLastMediaTime)
                    - expectedDelta;
                const double mediaDelta =
                    (double)(mediaTime - feedbackLastMediaTime);

                /* Normal demux jitter remains well below this threshold,
                 * whereas the default short jumps are about ten seconds.
                 * This callback already runs on the main thread and observes
                 * the post-seek time, so draw immediately: a delayed,
                 * coalescing selector could remain postponed by rapid key
                 * repeats. */
                if (fabs(discontinuity) >= 2. * (double)CLOCK_FREQ
                    && (wallDelta <= 1.5
                        || fabs(mediaDelta) >= 2. * (double)CLOCK_FREQ)) {
                    msg_Dbg(getIntf(), "seek feedback: media delta %.3f s, "
                            "wall delta %.3f s, discontinuity %.3f s",
                            mediaDelta / CLOCK_FREQ, wallDelta,
                            discontinuity / CLOCK_FREQ);
                    [[VLCCoreInteraction sharedInstance] showPosition];
                }
            }
        }

        feedbackLastMediaTime = mediaTime;
        feedbackLastWallTime = wallTime;
        feedbackPositionPrimed = YES;
    } else {
        feedbackPositionPrimed = NO;
    }

    [[[VLCMain sharedInstance] mainWindow] updateTimeSlider];
    [[[VLCMain sharedInstance] statusBarIcon] updateProgress];
    [_remoteControlService playbackPositionUpdated];
}

- (void)playbackStatusUpdated
{
    // On shutdown, input might not be dead yet. Cleanup actions like inhibit, itunes playback
    // and playback positon are done in different code paths (dealloc and appWillTerminate:).
    if ([[VLCMain sharedInstance] isTerminating]) {
        return;
    }

    intf_thread_t *p_intf = getIntf();
    int state = -1;
    if (p_current_input) {
        state = var_GetInteger(p_current_input, "state");
    }

    /* Confirm the transition before drawing. The immediate hotkey icon can
     * race the frame-packed vout recreation on Mavericks; this state event
     * is the stable common path for keyboard, mouse and remote controls. */
    if ((feedbackLastPlaybackState == PLAYING_S
         || feedbackLastPlaybackState == PAUSE_S)
        && (state == PLAYING_S || state == PAUSE_S)
        && state != feedbackLastPlaybackState) {
        [[VLCCoreInteraction sharedInstance]
            showPlaybackStateOSD:(state == PAUSE_S)];
    }
    feedbackLastPlaybackState = state;

    // cancel itunes timer if next item starts playing
    if (state > -1 && state != END_S) {
        if (hasEndedTimer) {
            [hasEndedTimer invalidate];
            hasEndedTimer = nil;
        }
    }

    if (state == PLAYING_S) {
        [self stopItunesPlayback];

        [self inhibitSleep];

        [[o_main mainMenu] setPause];
        [[o_main mainWindow] setPause];
    } else {
        [[o_main mainMenu] setSubmenusEnabled: FALSE];
        [[o_main mainMenu] setPlay];
        [[o_main mainWindow] setPlay];

        if (state == PAUSE_S)
            [self releaseSleepBlockers];

        if (state == END_S || state == -1) {
            /* continue playback where you left off */
            if (p_current_input)
                [self storePlaybackPositionForItem:p_current_input];

            if (hasEndedTimer) {
                [hasEndedTimer invalidate];
            }
            hasEndedTimer = [NSTimer scheduledTimerWithTimeInterval: 0.5
                                                             target: self
                                                           selector: @selector(onPlaybackHasEnded:)
                                                           userInfo: nil
                                                            repeats: NO];
        }
    }

    [self updateMainWindow];
    [self sendDistributedNotificationWithUpdatedPlaybackStatus];
    [_remoteControlService playbackStateChangedTo:state];
}

// Called when playback has ended and likely no subsequent media will start playing
- (void)onPlaybackHasEnded:(id)sender
{
    msg_Dbg(getIntf(), "Playback has been ended");

    [self releaseSleepBlockers];
    [self resumeItunesPlayback];
    hasEndedTimer = nil;
}

- (void)stopItunesPlayback
{
    intf_thread_t *p_intf = getIntf();
    int controlItunes = var_InheritInteger(p_intf, "macosx-control-itunes");
    if (controlItunes <= 0)
        return;

    // pause iTunes
    if (!b_has_itunes_paused) {
        iTunesApplication *iTunesApp = (iTunesApplication *) [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
        if (iTunesApp && [iTunesApp isRunning]) {
            if ([iTunesApp playerState] == iTunesEPlSPlaying) {
                msg_Dbg(p_intf, "pausing iTunes");
                [iTunesApp pause];
                b_has_itunes_paused = YES;
            }
        }
    }

    // pause Apple Music
    if (!b_has_applemusic_paused) {
        iTunesApplication *iTunesApp = (iTunesApplication *) [SBApplication applicationWithBundleIdentifier:@"com.apple.Music"];
        if (iTunesApp && [iTunesApp isRunning]) {
            if ([iTunesApp playerState] == iTunesEPlSPlaying) {
                msg_Dbg(p_intf, "pausing Apple Music");
                [iTunesApp pause];
                b_has_applemusic_paused = YES;
            }
        }
    }

    // pause Spotify
    if (!b_has_spotify_paused) {
        SpotifyApplication *spotifyApp = (SpotifyApplication *) [SBApplication applicationWithBundleIdentifier:@"com.spotify.client"];

        if (spotifyApp) {
            if ([spotifyApp respondsToSelector:@selector(isRunning)] && [spotifyApp respondsToSelector:@selector(playerState)]) {
                if ([spotifyApp isRunning] && [spotifyApp playerState] == kSpotifyPlayerStatePlaying) {
                    msg_Dbg(p_intf, "pausing Spotify");
                    [spotifyApp pause];
                    b_has_spotify_paused = YES;
                }
            }
        }
    }
}

- (void)resumeItunesPlayback
{
    intf_thread_t *p_intf = getIntf();
    if (var_InheritInteger(p_intf, "macosx-control-itunes") > 1) {
        if (b_has_itunes_paused) {
            iTunesApplication *iTunesApp = (iTunesApplication *) [SBApplication applicationWithBundleIdentifier:@"com.apple.iTunes"];
            if (iTunesApp && [iTunesApp isRunning]) {
                if ([iTunesApp playerState] == iTunesEPlSPaused) {
                    msg_Dbg(p_intf, "unpausing iTunes");
                    [iTunesApp playpause];
                }
            }
        }

        if (b_has_applemusic_paused) {
            iTunesApplication *iTunesApp = (iTunesApplication *) [SBApplication applicationWithBundleIdentifier:@"com.apple.Music"];
            if (iTunesApp && [iTunesApp isRunning]) {
                if ([iTunesApp playerState] == iTunesEPlSPaused) {
                    msg_Dbg(p_intf, "unpausing Apple Music");
                    [iTunesApp playpause];
                }
            }
        }

        if (b_has_spotify_paused) {
            SpotifyApplication *spotifyApp = (SpotifyApplication *) [SBApplication applicationWithBundleIdentifier:@"com.spotify.client"];
            if (spotifyApp) {
                if ([spotifyApp respondsToSelector:@selector(isRunning)] && [spotifyApp respondsToSelector:@selector(playerState)]) {
                    if ([spotifyApp isRunning] && [spotifyApp playerState] == kSpotifyPlayerStatePaused) {
                        msg_Dbg(p_intf, "unpausing Spotify");
                        [spotifyApp play];
                    }
                }
            }
        }
    }

    b_has_itunes_paused = NO;
    b_has_applemusic_paused = NO;
    b_has_spotify_paused = NO;
}

- (void)inhibitSleep
{
    BOOL shouldDisableScreensaver = var_InheritBool(getIntf(), "disable-screensaver");

    /* Declare user activity.
     This wakes the display if it is off, and postpones display sleep according to the users system preferences
     Available from 10.7.3 */
    if ([o_main activeVideoPlayback] && &IOPMAssertionDeclareUserActivity && shouldDisableScreensaver)
    {
        CFStringRef reasonForActivity = CFStringCreateWithCString(kCFAllocatorDefault, _("VLC media playback"), kCFStringEncodingUTF8);
        IOReturn success = IOPMAssertionDeclareUserActivity(reasonForActivity,
                                                            kIOPMUserActiveLocal,
                                                            &userActivityAssertionID);
        CFRelease(reasonForActivity);

        if (success != kIOReturnSuccess)
            msg_Warn(getIntf(), "failed to declare user activity");

    }

    // Only set assertion if no previous / active assertion exist. This is necessary to keep
    // audio only playback awake. If playback switched from video to audio or vice vesa, deactivate
    // the other assertion and activate the needed assertion instead.
    void(^activateAssertion)(CFStringRef, IOPMAssertionID*, IOPMAssertionID*) = ^void(CFStringRef assertionType, IOPMAssertionID* assertionIdRef, IOPMAssertionID* otherAssertionIdRef) {

        if (*otherAssertionIdRef > 0) {
            msg_Dbg(getIntf(), "Releasing old IOKit other assertion (%i)" , *otherAssertionIdRef);
            IOPMAssertionRelease(*otherAssertionIdRef);
            *otherAssertionIdRef = 0;
        }

        if (*assertionIdRef) {
            msg_Dbg(getIntf(), "Continue to use IOKit assertion %s (%i)", [(__bridge NSString *)(assertionType) UTF8String], *assertionIdRef);
            return;
        }

        CFStringRef reasonForActivity = CFStringCreateWithCString(kCFAllocatorDefault, _("VLC media playback"), kCFStringEncodingUTF8);

        IOReturn success = IOPMAssertionCreateWithName(assertionType, kIOPMAssertionLevelOn, reasonForActivity, assertionIdRef);
        CFRelease(reasonForActivity);

        if (success == kIOReturnSuccess)
            msg_Dbg(getIntf(), "Activated assertion %s through IOKit (%i)", [(__bridge NSString *)(assertionType) UTF8String], *assertionIdRef);
        else
            msg_Warn(getIntf(), "Failed to prevent system sleep through IOKit");
    };

    if ([o_main activeVideoPlayback] && shouldDisableScreensaver) {
        activateAssertion(kIOPMAssertionTypeNoDisplaySleep, &monitorSleepAssertionID, &systemSleepAssertionID);
    } else {
        activateAssertion(kIOPMAssertionTypeNoIdleSleep, &systemSleepAssertionID, &monitorSleepAssertionID);
    }

}

- (void)releaseSleepBlockers
{
    /* allow the system to sleep again */
    if (systemSleepAssertionID > 0) {
        msg_Dbg(getIntf(), "Releasing IOKit system sleep blocker (%i)" , systemSleepAssertionID);
        IOPMAssertionRelease(systemSleepAssertionID);
        systemSleepAssertionID = 0;
    }

    if (monitorSleepAssertionID > 0) {
        msg_Dbg(getIntf(), "Releasing IOKit monitor sleep blocker (%i)" , monitorSleepAssertionID);
        IOPMAssertionRelease(monitorSleepAssertionID);
        monitorSleepAssertionID = 0;
    }
}

- (void)updateMetaAndInfo
{
    if (!p_current_input) {
        [[[VLCMain sharedInstance] currentMediaInfoPanel] updatePanelWithItem:nil];
        [_remoteControlService metaDataChangedForCurrentMediaItem:NULL];
        return;
    }

    input_item_t *p_input_item = input_GetItem(p_current_input);

    [[[o_main playlist] model] updateItem:p_input_item];
    [[[VLCMain sharedInstance] currentMediaInfoPanel] updatePanelWithItem:p_input_item];
    [_remoteControlService metaDataChangedForCurrentMediaItem:p_input_item];
}

- (void)updateMainWindow
{
    [[o_main mainWindow] updateWindow];
}

- (void)updateName
{
    [[o_main mainWindow] updateName];
}

- (void)updateDelays
{
    [[[VLCMain sharedInstance] trackSyncPanel] updateValues];
}

- (void)updateMainMenu
{
    [[o_main mainMenu] setupMenus];
    [[o_main mainMenu] updatePlaybackRate];
    [[VLCCoreInteraction sharedInstance] resetAtoB];
}

- (void)sendDistributedNotificationWithUpdatedPlaybackStatus
{
    [[NSDistributedNotificationCenter defaultCenter] postNotificationName:@"VLCPlayerStateDidChange"
                                                                   object:nil
                                                                 userInfo:nil
                                                       deliverImmediately:YES];
}

- (void)coreChangedMediaKeySupportSetting: (NSNotification *)o_notification
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    BOOL b_mediaKeySupport = var_InheritBool(p_intf, "macosx-mediakeys");
    if (b_mediaKeySupport) {
        if (!_remoteControlService) {
            _remoteControlService = [[VLCRemoteControlService alloc] init];
        }
        [_remoteControlService subscribeToRemoteCommands];
    } else {
        [_remoteControlService unsubscribeFromRemoteCommands];
    }
}

- (BOOL)hasInput
{
    return p_current_input != NULL;
}

#pragma mark -
#pragma mark Resume logic

- (void)cancelResumeOSD
{
    BOOL hadPrompt = resumeOSDTarget > 0;
    [resumeOSDTimer invalidate];
    resumeOSDTimer = nil;
    resumeOSDTarget = 0;
    resumeOSDDeadline = 0.;
    resumeOSDLastDraw = 0.;
    resumeOSDLastCountdown = -1;
    resumeOSDAutoCloseCancelled = NO;

    if (hadPrompt && p_current_input) {
        vout_thread_t *p_vout = input_GetVout(p_current_input);
        if (p_vout) {
            vout_FlushSubpictureChannel(p_vout, VOUT_SPU_CHANNEL_OSD);
            vlc_object_release(p_vout);
        }
    }
}

- (void)finishResumeOSDContinuing:(BOOL)continuePlayback
{
    vlc_tick_t target = resumeOSDTarget;
    [self cancelResumeOSD];

    if (continuePlayback && target > 0 && p_current_input) {
        msg_Dbg(getIntf(), "continuing playback at %lld", target);
        var_SetInteger(p_current_input, "time", target);
    }
}

- (void)resumeOSDTick:(NSTimer *)timer
{
    VLC_UNUSED(timer);
    if (resumeOSDTarget <= 0 || !p_current_input) {
        [self cancelResumeOSD];
        return;
    }

    vout_thread_t *p_vout = input_GetVout(p_current_input);
    if (!p_vout)
        return;

    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    int countdown = -1;
    if (!resumeOSDAutoCloseCancelled) {
        if (resumeOSDDeadline <= 0.)
            resumeOSDDeadline = now + 10.;

        countdown = (int)(resumeOSDDeadline - now + .999);
        if (countdown <= 0) {
            vlc_object_release(p_vout);
            [self finishResumeOSDContinuing:NO];
            return;
        }
    }

    /* The vout OSD has a finite lifetime. Before interaction the changing
     * countdown naturally refreshes it once per second. Once automatic close
     * is cancelled, keep refreshing at the same quiet cadence so the choice
     * remains on screen indefinitely without redrawing four times per second. */
    if (countdown != resumeOSDLastCountdown
        || (resumeOSDAutoCloseCancelled && now - resumeOSDLastDraw >= 1.)) {
        resumeOSDLastCountdown = countdown;
        resumeOSDLastDraw = now;
        NSString *resumeTime = [[VLCStringUtility sharedInstance]
            stringForTime:resumeOSDTarget / CLOCK_FREQ];
        NSString *choices = resumeOSDContinueSelected
            ? [NSString stringWithFormat:@"[ %@ ]     %@",
                                         _NS("Continue"), _NS("Restart playback")]
            : [NSString stringWithFormat:@"  %@     [ %@ ]",
                                         _NS("Continue"), _NS("Restart playback")];
        NSString *message;
        if (resumeOSDAutoCloseCancelled)
            message = [NSString stringWithFormat:
                _NS("Continue at %@?\n%@\nLeft/Right: select   Enter: confirm   Esc: restart"),
                resumeTime, choices];
        else
            message = [NSString stringWithFormat:
                _NS("Continue at %@?\n%@\nLeft/Right: select   Enter: confirm   Esc: restart   (%d)"),
                resumeTime, choices, countdown];
        vout_OSDText(p_vout, VOUT_SPU_CHANNEL_OSD, 0,
                     VLC_TICK_FROM_MS(1250), [message UTF8String]);
    }
    vlc_object_release(p_vout);
}

- (void)showResumeOSDAtTime:(vlc_tick_t)target
{
    [self cancelResumeOSD];
    msg_Dbg(getIntf(), "showing resume choice in video OSD at %lld", target);
    resumeOSDTarget = target;
    resumeOSDContinueSelected = YES;
    resumeOSDDeadline = 0.;
    resumeOSDLastDraw = 0.;
    resumeOSDLastCountdown = -1;
    resumeOSDAutoCloseCancelled = NO;
    resumeOSDTimer = [NSTimer scheduledTimerWithTimeInterval:.25
                                                      target:self
                                                    selector:@selector(resumeOSDTick:)
                                                    userInfo:nil
                                                     repeats:YES];
    [self resumeOSDTick:resumeOSDTimer];
}

- (void)noteResumeOSDUserInteraction
{
    if (resumeOSDTarget <= 0 || resumeOSDAutoCloseCancelled)
        return;

    resumeOSDAutoCloseCancelled = YES;
    resumeOSDDeadline = 0.;
    resumeOSDLastCountdown = -1;
    resumeOSDLastDraw = 0.;
    msg_Dbg(getIntf(), "resume OSD auto-close cancelled by user interaction");
    [self resumeOSDTick:resumeOSDTimer];
}

- (BOOL)handleResumeOSDKey:(unsigned int)key
{
    if (resumeOSDTarget <= 0)
        return NO;

    /* Every key press grants unlimited decision time, including keys which
     * are not owned by this prompt and continue into the normal hotkey path. */
    [self noteResumeOSDUserInteraction];

    switch (key) {
        case KEY_LEFT:
        case KEY_UP:
            resumeOSDContinueSelected = YES;
            resumeOSDLastCountdown = -1;
            [self resumeOSDTick:resumeOSDTimer];
            return YES;
        case KEY_RIGHT:
        case KEY_DOWN:
            resumeOSDContinueSelected = NO;
            resumeOSDLastCountdown = -1;
            [self resumeOSDTick:resumeOSDTimer];
            return YES;
        case KEY_ENTER:
            [self finishResumeOSDContinuing:resumeOSDContinueSelected];
            return YES;
        case KEY_ESC:
            [self finishResumeOSDContinuing:NO];
            return YES;
        default:
            return NO;
    }
}


- (BOOL)isValidResumeItem:(input_item_t *)p_item
{
    char *psz_url = input_item_GetURI(p_item);
    NSString *urlString = toNSStr(psz_url);
    free(psz_url);

    if ([urlString isEqualToString:@""])
        return NO;

    NSURL *url = [NSURL URLWithString:urlString];

    if (![url isFileURL])
        return NO;

    BOOL isDir = false;
    if (![[NSFileManager defaultManager] fileExistsAtPath:[url path] isDirectory:&isDir])
        return NO;

    if (isDir)
        return NO;

    return YES;
}

- (void)continuePlaybackWhereYouLeftOff:(input_thread_t *)p_input_thread
{
    NSDictionary *recentlyPlayedFiles = [[NSUserDefaults standardUserDefaults] objectForKey:@"recentlyPlayedMedia"];
    if (!recentlyPlayedFiles)
        return;

    input_item_t *p_item = input_GetItem(p_input_thread);
    if (!p_item)
        return;

    /* allow the user to over-write the start/stop/run-time */
    float runTime = var_GetFloat(p_input_thread, "run-time");
    float startTime = var_GetFloat(p_input_thread, "start-time");
    float stopTime = var_GetFloat(p_input_thread, "stop-time");
    if (runTime > 0 || startTime > 0 || stopTime != 0)
        return;

    /* check for file existance before resuming */
    if (![self isValidResumeItem:p_item])
        return;

    char *psz_url = vlc_uri_decode(input_item_GetURI(p_item));
    if (!psz_url)
        return;
    NSString *url = toNSStr(psz_url);
    free(psz_url);

    NSNumber *lastPosition = [recentlyPlayedFiles objectForKey:url];
    if (!lastPosition || lastPosition.intValue <= 0)
        return;

    int settingValue = (int)var_InheritInteger(p_input_thread,
                                                "macosx-continue-playback");
    if (settingValue == 2) // never resume
        return;

    vlc_tick_t lastPos = (vlc_tick_t)lastPosition.intValue * CLOCK_FREQ;

    if (settingValue == 1) { // always
        msg_Dbg(getIntf(), "continuing playback at %lld", lastPos);
        var_SetInteger(p_input_thread, "time", lastPos);
        return;
    }

    [self showResumeOSDAtTime:lastPos];

}

static const int64_t MinimumDuration = 3 * 60 * 1000;
static const float MinimumStorePercent = 0.05;
static const float MaximumStorePercent = 0.95;
static const int64_t MinimumStoreTime = 60 * 1000;
static const int64_t MinimumStoreRemainingTime = 60 * 1000;

BOOL ShouldStorePlaybackPosition(float position, int64_t duration)
{
    int64_t positionTime = position * duration;
    int64_t remainingTime = duration - positionTime;

    if (duration < MinimumDuration) {
        return NO;
    }

    if (position < MinimumStorePercent && positionTime < MinimumStoreTime) {
        return NO;
    }

    if (position > MaximumStorePercent && remainingTime < MinimumStoreRemainingTime) {
        return NO;
    }

    return YES;
}

- (void)storePlaybackPositionForItem:(input_thread_t *)p_input_thread
{
    if (!var_InheritBool(getIntf(), "macosx-recentitems"))
        return;

    input_item_t *p_item = input_GetItem(p_input_thread);
    if (!p_item)
        return;

    if (![self isValidResumeItem:p_item])
        return;

    char *psz_url = vlc_uri_decode(input_item_GetURI(p_item));
    if (!psz_url)
        return;
    NSString *url = toNSStr(psz_url);
    free(psz_url);

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *mutDict = [[NSMutableDictionary alloc] initWithDictionary:[defaults objectForKey:@"recentlyPlayedMedia"]];

    float relativePos = var_GetFloat(p_input_thread, "position");
    vlc_tick_t pos = var_GetInteger(p_input_thread, "time") / CLOCK_FREQ;
    vlc_tick_t dur = input_item_GetDuration(p_item) / 1000000;

    NSMutableArray *mediaList = [[defaults objectForKey:@"recentlyPlayedMediaList"] mutableCopy];

    if (ShouldStorePlaybackPosition(relativePos, dur*1000)) {
        msg_Dbg(getIntf(), "Store current playback position of %f", relativePos);
        [mutDict setObject:[NSNumber numberWithInt:pos] forKey:url];

        [mediaList removeObject:url];
        [mediaList addObject:url];
        NSUInteger mediaListCount = mediaList.count;
        if (mediaListCount > 30) {
            for (NSUInteger x = 0; x < mediaListCount - 30; x++) {
                [mutDict removeObjectForKey:[mediaList firstObject]];
                [mediaList removeObjectAtIndex:0];
            }
        }
    } else {
        [mutDict removeObjectForKey:url];
        [mediaList removeObject:url];
    }
    [defaults setObject:mutDict forKey:@"recentlyPlayedMedia"];
    [defaults setObject:mediaList forKey:@"recentlyPlayedMediaList"];
    [defaults synchronize];
}

@end
