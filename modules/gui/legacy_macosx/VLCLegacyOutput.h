/*****************************************************************************
 * VLCLegacyOutput.h: stream output settings sheet (legacy Mac OS X intf)
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

/* Programmatic port of VLCOutput (the "Streaming and Transcoding Options"
 * sheet opened by the "Settings..." button of the Open window). Produces
 * the same ":sout=#..." option strings as the 3.0 implementation. */
@interface VLCLegacyOutput : NSObject
{
    intf_thread_t *p_intf;

    NSPanel *sheet;

    NSButton *displayCheckbox;
    NSMatrix *methodMatrix;

    NSTextField *fileField;
    NSButton *browseButton;
    NSButton *dumpCheckbox;

    NSPopUpButton *streamTypePopup;
    NSTextField *streamAddressField;
    NSTextField *streamPortField;
    NSStepper *streamPortStepper;
    NSTextField *streamTTLField;
    NSStepper *streamTTLStepper;

    NSPopUpButton *muxPopup;

    NSButton *videoCheckbox;
    NSPopUpButton *videoCodecPopup;
    NSComboBox *videoBitrateCombo;
    NSComboBox *videoScaleCombo;
    NSButton *audioCheckbox;
    NSPopUpButton *audioCodecPopup;
    NSComboBox *audioBitrateCombo;
    NSComboBox *audioChannelsCombo;

    NSButton *sapCheckbox;
    NSButton *rtspCheckbox;
    NSButton *httpCheckbox;
    NSButton *sdpFileCheckbox;
    NSTextField *channelNameField;
    NSTextField *sdpURLField;

    NSString *transcodeString;
    NSArray *soutMRL;
}

- (id)initWithIntf:(intf_thread_t *)intf;

/* Opens the sheet attached to the given window */
- (void)beginSheetForWindow:(NSWindow *)parent;

/* ":sout=..." option strings reflecting the current settings */
- (NSArray *)soutMRL;

@end
