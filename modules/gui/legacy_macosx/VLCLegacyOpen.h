/*****************************************************************************
 * VLCLegacyOpen.h: open dialogs for the legacy Mac OS X interface
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

@class VLCLegacyCoreInteraction;
@class VLCLegacyOutput;

/* tab indexes of the open window, in the 3.0 order */
enum {
    OPEN_TAB_FILE = 0,
    OPEN_TAB_DISC,
    OPEN_TAB_NETWORK,
    OPEN_TAB_CAPTURE
};

/* Programmatic port of VLCOpenWindowController (the 3.0 "Open Source"
 * window): one window, four panes (File, Disc, Network, Capture), the
 * disclosed MRL row, and the shared "Stream output:" checkbox with its
 * "Settings..." sheet. Each menu entry opens its pane directly.
 * "Open File..." keeps the plain NSOpenPanel, like 3.0. */
@interface VLCLegacyOpen : NSObject
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;
    VLCLegacyOutput *output;

    NSWindow *window;
    NSTabView *tabView;
    NSButton *okButton;
    NSButton *mrlDisclosureButton;
    NSTextField *mrlLabel;
    NSTextField *mrlField;
    NSButton *outputCheckbox;
    NSButton *outputSettingsButton;
    NSString *mrl;

    NSPanel *connectServerPanel;
    NSComboBox *connectServerAddress;

    /* --- file pane --- */
    NSImageView *fileIconWell;
    NSTextField *fileNameLabel;
    NSTextField *fileNameStubLabel;
    NSButton *fileTreatAsPipeButton;
    NSString *filePath;
    NSButton *fileSlaveCheckbox;
    NSButton *fileSelectSlaveButton;
    NSImageView *fileSlaveIconWell;
    NSTextField *fileSlaveFilenameLabel;
    NSString *fileSlavePath;
    NSButton *fileSubCheckbox;
    NSButton *fileSubSettingsButton;
    NSImageView *fileSubtitlesIconWell;
    NSTextField *fileSubtitlesFilenameLabel;
    NSButton *fileCustomTimingCheckbox;
    NSTextField *fileStartTimeLabel;
    NSTextField *fileStartTimeField;
    NSTextField *fileStopTimeLabel;
    NSTextField *fileStopTimeField;

    /* subtitle settings sheet */
    NSPanel *fileSubSheet;
    NSTextField *fileSubPathField;
    NSButton *fileSubOverrideCheckbox;
    NSTextField *fileSubDelayField;
    NSStepper *fileSubDelayStepper;
    NSTextField *fileSubFPSField;
    NSStepper *fileSubFPSStepper;
    NSPopUpButton *fileSubEncodingPopup;
    NSPopUpButton *fileSubSizePopup;
    NSPopUpButton *fileSubAlignPopup;
    NSString *subPath;

    /* --- disc pane --- */
    NSPopUpButton *discSelectorPopup;
    NSImageView *discIconView;
    NSView *discCurrentView;
    NSView *discNoDiscView;
    NSView *discAudioCDView;
    NSView *discDVDView;
    NSView *discDVDwomenusView;
    NSView *discVCDView;
    NSView *discBDView;
    NSTextField *discNoDiscLabel;
    NSTextField *discAudioCDLabel;
    NSTextField *discAudioCDTrackCountLabel;
    NSTextField *discDVDLabel;
    /* Same setting shown twice: the menu-driven pane and the title/chapter
     * pane are separate views, so each carries its own box, permanently
     * ticked and unticked respectively. */
    NSButton *discDVDMenusCheckbox;
    NSButton *discDVDwomenusMenusCheckbox;
    NSTextField *discDVDwomenusLabel;
    NSTextField *discDVDwomenusTitleField;
    NSStepper *discDVDwomenusTitleStepper;
    NSTextField *discDVDwomenusChapterField;
    NSStepper *discDVDwomenusChapterStepper;
    NSTextField *discVCDLabel;
    NSTextField *discVCDTitleField;
    NSStepper *discVCDTitleStepper;
    NSTextField *discVCDChapterField;
    NSStepper *discVCDChapterStepper;
    NSTextField *discBDLabel;
    NSButton *discBDMenusCheckbox;
    NSMutableArray *allMediaDevices;     /* dicts: path/devicePath/type/image */
    NSMutableArray *specialMediaFolders;
    BOOL b_nodvdmenus;

    /* --- network pane --- */
    NSTextField *netHTTPURLField;
    NSPanel *netUDPPanel;
    NSMatrix *netModeMatrix;
    NSMatrix *netUDPProtocolMatrix;
    NSTextField *netUDPPortField;
    NSStepper *netUDPPortStepper;
    NSTextField *netUDPMAddressField;
    NSTextField *netUDPMPortField;
    NSStepper *netUDPMPortStepper;

    /* --- capture pane --- */
    NSPopUpButton *captureModePopup;
    NSTabView *captureTabView;
    NSButton *qtkVideoCheckbox;
    NSPopUpButton *qtkVideoDevicePopup;
    NSButton *qtkAudioCheckbox;
    NSPopUpButton *qtkAudioDevicePopup;
    NSArray *videoCaptureDevices;       /* AVCaptureDevice or QTCaptureDevice */
    NSArray *audioCaptureDevices;
    NSPopUpButton *screenPopup;
    NSMutableArray *displayIDs;          /* NSNumber (CGDirectDisplayID) */
    NSTextField *screenFPSField;
    NSStepper *screenFPSStepper;
    NSTextField *screenLeftField;
    NSStepper *screenLeftStepper;
    NSTextField *screenTopField;
    NSStepper *screenTopStepper;
    NSTextField *screenWidthField;
    NSStepper *screenWidthStepper;
    NSTextField *screenHeightField;
    NSStepper *screenHeightStepper;
    NSButton *screenFollowMouseCheckbox;
    NSButton *screenqtkAudioCheckbox;
    NSPopUpButton *screenqtkAudioPopup;
}

- (void)qtkChanged:(id)sender;
- (void)qtkAudioChanged:(id)sender;
- (void)qtkToggleUIElements:(id)sender;

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;

- (void)openFile;              /* plain panel, like 3.0 "Open File..." */
- (void)connectToServer;
- (void)openSubtitleFile;

/* the tabbed window (Advanced Open File / Disc / Network / Capture) */
- (void)showTab:(int)tab;

@end
