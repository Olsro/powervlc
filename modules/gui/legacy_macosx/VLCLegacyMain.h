/*****************************************************************************
 * VLCLegacyMain.h: central controller for the legacy Mac OS X interface
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
@class VLCLegacyMainWindow;
@class VLCLegacyExtensionsDialogProvider;
@class VLCLegacyMenu;
@class VLCLegacyOpen;
@class VLCLegacyPrefs;
@class VLCLegacyAudioEffects;
@class VLCLegacyVideoEffects;
@class VLCLegacyTrackSync;
@class VLCLegacyMessages;
@class VLCLegacyConvertAndSave;
@class VLCLegacyErrorPanel;
@class VLCLegacyMediaInfo;
@class VLCLegacyBookmarks;
@class VLCLegacyFSPanel;
@class VLCLegacyAbout;
@class VLCLegacyMainWindow;

/* Equivalent of VLCMain: owns every controller of the interface and acts as
 * the NSApplication delegate (Finder/Dock file opening, reopen). No formal
 * NSApplicationDelegate protocol conformance: the protocol only exists since
 * Mac OS X 10.6, before that the delegate methods are informal. */
@interface VLCLegacyMain : NSObject
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;
    VLCLegacyMainWindow *mainWindow;
    VLCLegacyMenu *menu;
    VLCLegacyOpen *open;
    VLCLegacyPrefs *prefs;
    VLCLegacyAudioEffects *audioEffects;
    VLCLegacyVideoEffects *videoEffects;
    VLCLegacyTrackSync *trackSync;
    VLCLegacyMessages *messages;
    VLCLegacyErrorPanel *errorPanel;
    VLCLegacyConvertAndSave *convertAndSave;
    VLCLegacyMediaInfo *mediaInfo;
    VLCLegacyBookmarks *bookmarks;
    VLCLegacyFSPanel *fsPanel;
    VLCLegacyAbout *about;
    VLCLegacyExtensionsDialogProvider *extensionDialogs;
}

- (id)initWithIntf:(intf_thread_t *)intf;

- (VLCLegacyMainWindow *)mainWindowController;
- (VLCLegacyCoreInteraction *)coreInteraction;
- (id)mediaInfoController;
- (id)menuController;
- (id)audioEffectsController;
- (id)errorPanelController;

/* dialog trampolines (main thread) for the dialog provider */
- (void)dismissDialog:(NSValue *)idValue;
- (void)displayQuestion:(NSArray *)dialogData;

/* Must run on the main thread */
- (void)setup;          /* guarded wrapper, catches and logs */
- (void)setupInterface; /* the actual work */
- (void)shutdown;

@end
