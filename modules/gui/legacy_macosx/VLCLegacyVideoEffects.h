/*****************************************************************************
 * VLCLegacyVideoEffects.h: video effects window for the legacy interface
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

/* Port of VLCVideoEffectsWindowController (3.0.23): five panes (Basic,
 * Crop, Geometry, Color, Miscellaneous) toggling the core video filters
 * live, plus the NSUserDefaults-backed profile system. */
@interface VLCLegacyVideoEffects : VLCLegacyHUDController
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;

    NSPopUpButton *profilePopup;
    NSButton *applyProfileCheckbox;

    /* Basic */
    NSButton *adjustCheckbox;
    NSSlider *adjustHueSlider;
    NSSlider *adjustContrastSlider;
    NSSlider *adjustBrightnessSlider;
    NSButton *adjustBrightnessCheckbox;
    NSSlider *adjustSaturationSlider;
    NSSlider *adjustGammaSlider;
    NSButton *adjustResetButton;
    NSButton *sharpenCheckbox;
    NSSlider *sharpenSlider;
    NSButton *bandingCheckbox;
    NSSlider *bandingSlider;
    NSButton *grainCheckbox;
    NSSlider *grainSlider;

    /* Crop */
    NSTextField *cropTopTextField;
    NSStepper *cropTopStepper;
    NSTextField *cropLeftTextField;
    NSStepper *cropLeftStepper;
    NSTextField *cropRightTextField;
    NSStepper *cropRightStepper;
    NSTextField *cropBottomTextField;
    NSStepper *cropBottomStepper;
    NSButton *cropSyncTopBottomCheckbox;
    NSButton *cropSyncLeftRightCheckbox;

    /* Geometry */
    NSButton *transformCheckbox;
    NSPopUpButton *transformPopup;
    NSButton *zoomCheckbox;
    NSButton *puzzleCheckbox;
    NSTextField *puzzleRowsTextField;
    NSStepper *puzzleRowsStepper;
    NSTextField *puzzleColumnsTextField;
    NSStepper *puzzleColumnsStepper;
    NSButton *cloneCheckbox;
    NSTextField *cloneNumberTextField;
    NSStepper *cloneNumberStepper;
    NSButton *wallCheckbox;
    NSTextField *wallRowsTextField;
    NSStepper *wallRowsStepper;
    NSTextField *wallColumnsTextField;
    NSStepper *wallColumnsStepper;

    /* Color */
    NSButton *thresholdCheckbox;
    NSTextField *thresholdColorTextField;
    NSSlider *thresholdSaturationSlider;
    NSSlider *thresholdSimilaritySlider;
    NSButton *sepiaCheckbox;
    NSTextField *sepiaTextField;
    NSStepper *sepiaStepper;
    NSButton *gradientCheckbox;
    NSPopUpButton *gradientModePopup;
    NSButton *gradientColorCheckbox;
    NSButton *gradientCartoonCheckbox;
    NSButton *extractCheckbox;
    NSTextField *extractTextField;
    NSButton *invertCheckbox;
    NSButton *posterizeCheckbox;
    NSTextField *posterizeTextField;
    NSStepper *posterizeStepper;
    NSButton *blurCheckbox;
    NSSlider *blurSlider;
    NSButton *motiondetectCheckbox;
    NSButton *watereffectCheckbox;
    NSButton *wavesCheckbox;
    NSButton *psychedelicCheckbox;

    /* Miscellaneous */
    NSButton *addTextCheckbox;
    NSTextField *addTextTextTextField;
    NSPopUpButton *addTextPositionPopup;
    NSButton *addLogoCheckbox;
    NSTextField *addLogoLogoTextField;
    NSPopUpButton *addLogoPositionPopup;
    NSSlider *addLogoTransparencySlider;
    NSButton *anaglyphCheckbox;

    void *lastInputItem;   /* crop values reset when the input changes */
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;

/* mirrors -[VLCVideoEffectsWindowController saveCurrentProfileAtTerminate] */
- (void)saveCurrentProfileAtTerminate;

@end
