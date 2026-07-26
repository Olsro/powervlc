/*****************************************************************************
 * VLCLegacyTrackSync.h: track synchronization window (legacy interface)
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

#import "VLCLegacyHUDWindow.h"

@class VLCLegacyCoreInteraction;

/* Port of VLCTrackSynchronizationWindowController (3.0.23): audio/video
 * delay, subtitle delay/speed/duration factor, applied to the current
 * input (and the vouts for the subsdelay filter). */
@interface VLCLegacyTrackSync : VLCLegacyHUDController
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;

    NSTextField *avAdvanceTextField;
    NSStepper *avStepper;
    NSTextField *svAdvanceTextField;
    NSStepper *svAdvanceStepper;
    NSTextField *svSpeedTextField;
    NSStepper *svSpeedStepper;
    NSTextField *svDurTextField;
    NSStepper *svDurStepper;

    NSTimer *refreshTimer;
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;

@end
