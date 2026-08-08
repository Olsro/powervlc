/*****************************************************************************
 * VLCLegacyMenu.h: main menu for the legacy Mac OS X interface
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

#include <vlc_extensions.h>

@class VLCLegacyCoreInteraction;
@class VLCLegacyMainWindow;
@class VLCLegacyOpen;
@class VLCLegacyPrefs;
@class VLCLegacyAudioEffects;
@class VLCLegacyVideoEffects;
@class VLCLegacyTrackSync;
@class VLCLegacyMessages;
@class VLCLegacyErrorPanel;
@class VLCLegacyConvertAndSave;
@class VLCLegacyMediaInfo;
@class VLCLegacyBookmarks;
@class VLCLegacyAbout;
@class VLCLegacyAddons;

/* Programmatic port of VLCMainMenu, restricted to what the 10.4 AppKit
 * offers. Structure mirrors the modern interface: VLC / File / Edit /
 * Playback / Audio / Video / Subtitles / Window / Help. -setupMenu must run
 * on the main thread. Manual retain/release throughout: this module targets
 * Mac OS X releases without the ARC runtime. */
@interface VLCLegacyMenu : NSObject
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;
    VLCLegacyMainWindow *mainWindow;
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
    VLCLegacyAbout *about;
    VLCLegacyAddons *addons;        /* created lazily */

    NSMenuItem *playItem;
    NSMenu *playlistColumnsMenu;    /* View > Playlist Table Columns */
    /* dynamic variable-driven submenus (rebuilt on open) */
    NSMenu *audioTrackMenu;
    NSMenu *subtitleTrackMenu;
    NSMenu *videoTrackMenu;
    NSMenu *qualityMenu;            /* Video > Quality ("adaptive-quality") */
    NSMenu *titleMenu;
    NSMenu *chapterMenu;
    NSMenu *programMenu;
    NSMenu *stereoModeMenu;
    NSMenu *aspectMenu;
    NSMenu *cropMenu;
    NSMenu *visualMenu;             /* Audio > Visualizations ("visual") */
    NSMenu *audioDeviceMenu;        /* Audio > Audio Device (aout API) */
    NSMenu *addInterfaceMenu;       /* VLC > Add Interface ("intf-add") */
    NSMenu *rendererMenu;           /* Playback > Renderer */
    NSMenu *extensionsMenu;         /* VLC > Extensions (lua) */

    /* lua extensions (created on demand, released with the menu) */
    extensions_manager_t *p_extensions_manager;

    /* contextual vout menu (right-click on the video) and its own dynamic
     * submenus (an NSMenu cannot live in two menus at once) */
    NSMenu *recentMenu;             /* "Open Recent", user-defaults backed */
    NSMenu *voutMenu;
    NSMenu *voutAudioTrackMenu;
    NSMenu *voutSubtitleTrackMenu;
    NSMenu *voutVideoTrackMenu;
    NSMenu *voutAspectMenu;
    NSMenu *voutCropMenu;
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
        mainWindow:(VLCLegacyMainWindow *)mw
              open:(VLCLegacyOpen *)openDialogs
             prefs:(VLCLegacyPrefs *)prefsController
      audioEffects:(VLCLegacyAudioEffects *)audioEffectsController
      videoEffects:(VLCLegacyVideoEffects *)videoEffectsController
         trackSync:(VLCLegacyTrackSync *)trackSyncController
          messages:(VLCLegacyMessages *)messagesController
        errorPanel:(VLCLegacyErrorPanel *)errorPanelController
    convertAndSave:(VLCLegacyConvertAndSave *)convertAndSaveController
         mediaInfo:(VLCLegacyMediaInfo *)mediaInfoController
         bookmarks:(VLCLegacyBookmarks *)bookmarksController
             about:(VLCLegacyAbout *)aboutController;

- (void)setupMenu;
- (NSMenu *)voutMenu;
@end

/* Records an opened MRL in the "Open Recent" list (NSUserDefaults);
 * called from every open path. */
void VLCLegacyNoteRecentItem(NSString *mrl);
