/*****************************************************************************
 * VLCLegacyConvertAndSave.h: Convert & Stream window (legacy interface)
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

/* NSInteger/CGFloat only appeared with the 10.5 SDK */
#ifndef NSINTEGER_DEFINED
typedef int NSInteger;
typedef unsigned int NSUInteger;
#define NSINTEGER_DEFINED 1
#endif
#ifndef CGFLOAT_DEFINED
typedef float CGFloat;
#define CGFLOAT_DEFINED 1
#endif

@class VLCLegacyCoreInteraction;
@class VLCLegacyHUDCloseButton;

/* Port of VLCConvertAndSaveWindowController (3.0.23): media selection,
 * encoding profiles (same NSUserDefaults keys and 16-field profile
 * strings), the Customize panel with its four tabs, the streaming
 * destination panel, and the :sout= composition. */
@interface VLCLegacyConvertAndSave : NSObject
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;

    NSWindow *window;

    /* media selection */
    NSTextField *mediaLabel;
    NSButton *openMediaButton;
    NSString *MRL;
    NSString *mediaName;

    /* profiles */
    NSPopUpButton *profilePopup;
    NSMutableArray *profileNames;
    NSMutableArray *profileValueList;
    NSMutableArray *currentProfile;   /* 16 field strings */

    /* destination */
    NSBox *destinationBox;
    NSButton *destinationFileButton;
    NSButton *destinationStreamButton;
    VLCLegacyHUDCloseButton *destinationCancelButton;
    NSView *fileDestinationView;
    NSTextField *fileDestinationLabel;
    NSButton *fileBrowseButton;
    NSView *streamDestinationView;
    NSTextField *streamSummaryLabel;
    NSButton *streamSetupButton;
    NSString *outputDestination;
    BOOL b_streaming;

    NSButton *okButton;

    /* customize panel */
    NSPanel *customizePanel;
    NSMatrix *encapMatrix;
    NSButton *vidCheckbox;
    NSButton *vidKeepCheckbox;
    NSPopUpButton *vidCodecPopup;
    NSTextField *vidBitrateField;
    NSTextField *vidFramerateField;
    NSTextField *vidWidthField;
    NSTextField *vidHeightField;
    NSPopUpButton *vidScalePopup;
    NSButton *audCheckbox;
    NSButton *audKeepCheckbox;
    NSPopUpButton *audCodecPopup;
    NSTextField *audBitrateField;
    NSTextField *audChannelsField;
    NSPopUpButton *audSampleratePopup;
    NSButton *subsCheckbox;
    NSPopUpButton *subsPopup;
    NSButton *subsOverlayCheckbox;
    BOOL customizeAccepted;

    /* stream panel */
    NSPanel *streamPanel;
    NSPopUpButton *streamTypePopup;
    NSTextField *streamAddressField;
    NSTextField *streamPortField;
    NSTextField *streamTTLField;
    NSStepper *streamTTLStepper;
    NSButton *streamSAPCheckbox;
    NSTextField *streamChannelField;
    NSMatrix *streamSDPMatrix;
    NSTextField *streamSDPField;
    NSButton *streamSDPBrowseButton;
    BOOL streamAccepted;
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;
- (void)showWindow;

@end
