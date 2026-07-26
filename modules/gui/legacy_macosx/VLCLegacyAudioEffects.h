/*****************************************************************************
 * VLCLegacyAudioEffects.h: audio effects window for the legacy interface
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

#define LEGACY_EQ_BANDS 10

/* Port of VLCAudioEffectsWindowController (3.0.23): Equalizer (with the
 * NSUserDefaults preset system), Compressor, Spatializer and Filter panes,
 * plus the profile system at the bottom of the window. */
@interface VLCLegacyAudioEffects : VLCLegacyHUDController
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;

    NSPopUpButton *profilePopup;
    NSButton *applyProfileCheckbox;

    /* Equalizer */
    NSButton *equalizerEnableCheckbox;
    NSButton *equalizerTwoPassCheckbox;
    NSPopUpButton *equalizerPresetsPopup;
    NSSlider *equalizerPreampSlider;
    NSSlider *equalizerBandSliders[LEGACY_EQ_BANDS];
    NSTextField *equalizerBandFields[LEGACY_EQ_BANDS];

    /* Compressor */
    NSButton *compressorEnableCheckbox;
    NSButton *compressorResetButton;
    NSSlider *compressorSliders[7];
    NSTextField *compressorFields[7];

    /* Spatializer */
    NSButton *spatializerEnableCheckbox;
    NSButton *spatializerResetButton;
    NSSlider *spatializerSliders[5];
    NSTextField *spatializerFields[5];

    /* Filter */
    NSButton *filterNormLevelCheckbox;
    NSSlider *filterNormLevelSlider;
    NSTextField *filterNormLevelLabel;
    NSButton *filterKaraokeCheckbox;
    NSButton *filterHeadPhoneCheckbox;
    NSButton *filterScaleTempoCheckbox;
    NSButton *filterStereoEnhancerCheckbox;
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;

/* mirrors -[VLCAudioEffectsWindowController saveCurrentProfileAtTerminate] */
- (void)saveCurrentProfileAtTerminate;

@end
