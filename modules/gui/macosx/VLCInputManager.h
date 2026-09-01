/*****************************************************************************
 * VLCInputManager.h: MacOS X interface module
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

#import <Cocoa/Cocoa.h>

#include <vlc_common.h>
#import <vlc_interface.h>

#import <IOKit/pwr_mgt/IOPMLib.h>           /* for sleep prevention */

@class VLCMain;

extern NSString *VLCPlayerRateChanged;

@interface VLCInputManager : NSObject

- (id)initWithMain:(VLCMain *)o_mainObj;
- (void)deinit;

- (void)inputThreadChanged;

- (void)playbackStatusUpdated;
- (void)playbackPositionUpdated;

- (void)onPlaybackHasEnded:(id)sender;

- (BOOL)hasInput;

/* Handles the keyboard while the resume choice is displayed in the video
 * OSD. Returns YES when the key belongs to the prompt and must not reach the
 * regular hotkey engine (notably Escape, which would leave fullscreen). */
- (BOOL)handleResumeOSDKey:(unsigned int)key;

/* Cancels only the ten-second automatic dismissal. The resume question and
 * its timer stay alive so the stereo OSD remains visible until the user
 * explicitly confirms a choice. */
- (void)noteResumeOSDUserInteraction;

@end
