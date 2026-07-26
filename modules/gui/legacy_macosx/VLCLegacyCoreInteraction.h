/*****************************************************************************
 * VLCLegacyCoreInteraction.h: core interaction for the legacy interface
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

#import <Cocoa/Cocoa.h>

#include <vlc_common.h>
#include <vlc_interface.h>

@class VLCLegacyAppleRemote;
@class VLCLegacyMediaKeyTap;

/* Mac OS X 10.4-safe port of VLCCoreInteraction: plain ObjC 1 syntax (no
 * properties, no fast enumeration), manual retain/release. All the VLC core
 * primitives called here are thread-safe. */
@interface VLCLegacyCoreInteraction : NSObject
{
    intf_thread_t *p_intf;
    int64_t timeA;      /* A->B loop bounds, microseconds (0 = unset) */
    int64_t timeB;

    /* Apple Remote / media keys (created by setupRemoteAndMediaKeys
     * according to the legacy-macosx-appleremote/-mediakeys options) */
    VLCLegacyAppleRemote *remote;
    VLCLegacyMediaKeyTap *mediaKeyTap;
    BOOL b_remote_button_hold;   /* hold button repeat is active */
    BOOL b_mediakeyJustJumped;   /* anti-bounce for repeat-seeks */

    /* external music players (legacy-macosx-control-itunes) */
    BOOL b_has_itunes_paused;
    BOOL b_has_applemusic_paused;
    BOOL b_has_spotify_paused;
    NSTimer *externalResumeTimer;  /* one-shot, after playback stops */
    int lastPlaylistStatus;        /* last polled playlist_Status() */
    NSTimer *statusPollTimer;      /* 0.5 s playback-state poll */
}

- (id)initWithIntf:(intf_thread_t *)intf;
- (intf_thread_t *)intf;

/* transport */
- (void)play;
- (void)togglePlayPause;
- (void)stop;
- (void)next;
- (void)previous;
- (void)jumpWithSeconds:(int)seconds;
- (void)setPositionFraction:(float)fraction;

/* rate */
- (void)faster;
- (void)slower;
- (void)normalSpeed;
- (void)setPlaybackRate:(float)rate;
- (float)playbackRate;

/* record (var "record" on the current input) */
- (void)toggleRecord;
- (BOOL)recording;
- (BOOL)canRecord;

/* A->B loop, port of -[VLCCoreInteraction setAtoB]: first call sets A,
 * second sets B (loop starts), third clears. updateAtoB must be called
 * periodically (the main window refresh timer does). */
- (void)setAtoB;
- (void)resetAtoB;
- (void)updateAtoB;

/* seek by the configured "extrashort-jump-size" (bar hold-to-seek) */
- (void)jumpExtraShort:(BOOL)forward;

/* audio */
- (void)volumeUp;
- (void)volumeDown;
- (void)toggleMute;
- (BOOL)muted;
- (float)volume;
- (void)setVolume:(float)volume;

/* video */
- (void)toggleFullscreen;
- (void)setZoom:(float)factor;
- (void)snapshot;

/* generic hotkey-style action (ACTIONID_* from vlc_actions.h) */
- (void)triggerAction:(int)actionId;

/* playlist-object booleans (random / loop / repeat / video-on-top / fullscreen) */
- (void)togglePlaylistBool:(const char *)name;
- (BOOL)playlistBool:(const char *)name;

/* Video filter handling, port of VLCCoreInteraction (effects windows):
 * toggles a filter in the matching list option ("video-filter",
 * "sub-source", "video-splitter", by module capability) on the playlist
 * and the running vouts, and pushes a filter property live. */
- (void)setVideoFilter:(const char *)psz_name on:(BOOL)b_on;
- (void)setVideoFilterProperty:(const char *)psz_property
                     forFilter:(const char *)psz_filter
                     withValue:(vlc_value_t)value;

- (void)addSubtitleFileToCurrentInput:(NSString *)path;

/* Apple Remote, media keys and external-player control. setup creates
 * the helper objects according to the configuration and starts the
 * playback-state poll; shutdown undoes everything (safe to call the
 * pair again to apply changed preferences). start/stopListening follow
 * the application activation state (Apple Remote is exclusive). */
- (void)setupRemoteAndMediaKeys;
- (void)shutdownRemoteAndMediaKeys;
- (void)startListeningWithAppleRemote;
- (void)stopListeningWithAppleRemote;

@end

/* True when this machine is fast enough for the heaviest ("Best quality")
 * deinterlacer — yadif2x, which runs the motion-adaptive pass at double the
 * field rate (50 fields/s on PAL). Apple's own DVD Player greys that mode out
 * on slower Macs; we mirror it: among PowerPC only the G5 (7447/7450-class G4s
 * cannot sustain it), and always on Intel and Apple Silicon. Runtime check so
 * a universal slice grades correctly on whatever CPU actually runs it. */
bool VLCLegacyBestDeinterlaceAvailable(void);
