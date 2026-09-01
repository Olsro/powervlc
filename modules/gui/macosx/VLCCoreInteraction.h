/*****************************************************************************
 * CoreInteraction.h: MacOS X interface module
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

#include <vlc_common.h>
#import <Cocoa/Cocoa.h>

/* Posted whenever the clip creation mode is entered or left */
extern NSString *VLCClipCreationModeChangedNotification;
extern NSString *VLCFullscreenFeedbackNotification;

@interface VLCCoreInteraction : NSObject

+ (VLCCoreInteraction *)sharedInstance;
@property (readwrite) int volume;
@property (readonly, nonatomic) float maxVolume;
@property (readwrite) int playbackRate;
@property (readonly) float internalPlaybackRate;
@property (nonatomic, readwrite) BOOL aspectRatioIsLocked;
@property (readonly) int durationOfCurrentPlaylistItem;
@property (readonly) NSURL * URLOfCurrentPlaylistItem;
@property (readonly) NSString * nameOfCurrentPlaylistItem;
@property (nonatomic, readwrite) BOOL mute;
@property (readonly) float currentPlaybackPosition;
@property (readonly) long long currentPlaybackTimeInSeconds;

- (void)playOrPause;
- (void)play;
- (void)pause;
- (void)stop;
- (void)faster;
- (void)slower;
- (void)normalSpeed;
- (void)toggleRecord;
- (void)next;
- (void)previous;
- (void)forward;        //LEGACY SUPPORT
- (void)backward;       //LEGACY SUPPORT
- (void)forwardExtraShort;
- (void)backwardExtraShort;
- (void)forwardShort;
- (void)backwardShort;
- (void)forwardMedium;
- (void)backwardMedium;
- (void)forwardLong;
- (void)backwardLong;
- (BOOL)seekToTime:(vlc_tick_t)time;

- (void)repeatOne;
- (void)repeatAll;
- (void)repeatOff;
- (void)shuffle;
- (void)setAtoB;
- (void)resetAtoB;
- (void)updateAtoB;

/* Clip creation mode: both seek bar knobs define the clip bounds
 * (fractional positions, 0..1); "Record" then saves exactly that range. */
@property (readonly) BOOL clipCreationMode;
@property (readwrite) double clipStartPosition;
@property (readwrite) double clipEndPosition;
@property (readonly) BOOL clipRecordingActive;
/* a fast extraction (second headless input, no playback involved) is
 * writing the clip right now */
@property (readonly) BOOL clipExportInProgress;
/* bound the frame-step shortcuts act on: 1 = start, 2 = end (the
 * default when entering the mode); follows the last knob the user
 * grabbed on the seek bar */
@property (readwrite) int clipSelectedKnob;
/* nudge the selected bound, with preview seek (also reached from the
 * core hotkeys module through "clip-frame-step"): by one frame for the
 * step shortcuts, by the configured jump size for the longer ones */
- (void)clipStepFrames:(int)direction;
- (void)clipNudgeSelectedBoundBySeconds:(double)seconds;
- (void)toggleClipCreationMode;
- (void)exitClipCreationMode;
- (void)updateClipRecording;
/* called on every knob drag/click, to suppress the end-bound auto-pause
 * while the user is interacting with the bounds */
- (void)noteClipInteraction;
/* record state as reported by INPUT_EVENT_RECORD */
- (void)recordStateChanged:(BOOL)b_recording;

/* "Hide controls during playback": master switch (menu Video, persisted
 * in "macosx-hide-controls"); the video windows poll it */
@property (nonatomic, readwrite) BOOL autoHideControls;
/* set by the video window while its controls are auto-hidden; mirrored
 * into the libvlc "intf-controls-hidden" bool so the core shows the
 * fullscreen-style OSD and reroutes the video double-click */
@property (nonatomic, readwrite) BOOL controlsHiddenForPlayback;

- (void)volumeUp;
- (void)volumeDown;
- (void)setVolumeFromVisibleControl:(int)value;
- (BOOL)shouldSuppressVolumeOSD;
- (void)toggleMute;
- (void)showVolumeOSD;
- (void)scheduleVolumeOSD;
- (void)showPlaybackStateOSD:(BOOL)paused;
- (void)showMuteOSD;
- (void)showPosition;
- (void)schedulePositionOSD;
- (void)startListeningWithAppleRemote;
- (void)stopListeningWithAppleRemote;

- (void)menuFocusActivate;
/* Blu-ray pop-up menu, drawn over the running movie (not the disc root menu).
 * -hasDiscPopupMenu tells whether the disc offers one at this very moment. */
- (BOOL)hasDiscPopupMenu;
- (void)showDiscPopupMenu;
- (void)showDiscRootMenu;
- (void)moveMenuFocusLeft;
- (void)moveMenuFocusRight;
- (void)moveMenuFocusUp;
- (void)moveMenuFocusDown;

- (void)addSubtitlesToCurrentInput:(NSArray *)paths;

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;

- (void)toggleFullscreen;

- (BOOL)fixIntfSettings;

- (void)setVideoFilter: (const char *)psz_name on:(BOOL)b_on;
- (void)setVideoFilterProperty: (const char *)psz_property forFilter: (const char *)psz_filter withValue: (vlc_value_t)value;

- (BOOL)keyEvent:(NSEvent *)o_event;
- (void)updateCurrentlyUsedHotkeys;
- (BOOL)hasDefinedShortcutKey:(NSEvent *)o_event force:(BOOL)b_force;

@end
