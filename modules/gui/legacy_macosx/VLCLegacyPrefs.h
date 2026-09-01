/*****************************************************************************
 * VLCLegacyPrefs.h: simple preferences for the legacy Mac OS X interface
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

#ifndef NSINTEGER_DEFINED
typedef int NSInteger;
typedef unsigned int NSUInteger;
#define NSINTEGER_DEFINED 1
#endif

@class VLCLegacyCoreInteraction;

/* Full port of the VLC 3.0.23 simple preferences, plus dedicated Media
 * Library and Portable Players panes
 * with the same options and behaviors, plus the hotkey table with the
 * 3.0 capture panel. */
@interface VLCLegacyPrefs : NSObject
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;

    NSWindow *window;
    NSTabView *tabView;
    NSMutableArray *entries;      /* VLCLegacyPrefEntry: config <-> control */
    NSMutableArray *retainedPaneViews; /* Jaguar may release inactive tabs */

    /* controls with behaviors beyond a plain config binding */
    NSComboBox *languagePopup;              /* NSUserDefaults "language" */
    NSTextField *languageLabel;
    NSMatrix *styleMatrix;                  /* legacy-macosx-dark radios */
    NSButton *notificationsCheckbox;        /* growl in "control" */
    NSButton *luaHTTPCheckbox;              /* http in "extraintf" */
    NSTextField *luaHTTPPasswordField;      /* http-password */
    NSMatrix *volumeMatrix;                 /* volume-save radios */
    NSSlider *volumeSlider;                 /* auhal-volume */
    NSTextField *volumeField;
    NSButton *passthroughCheckbox;
    NSButton *passthroughAC3Checkbox;
    NSButton *passthroughEAC3Checkbox;
    NSButton *passthroughTrueHDCheckbox;
    NSButton *passthroughDTSCheckbox;
    NSButton *passthroughDTSHDCheckbox;
    NSButton *lastfmCheckbox;               /* audioscrobbler intf */
    NSTextField *lastfmUserField;
    NSTextField *lastfmPasswordField;
    NSTextField *snapshotPathField;
    NSTextField *recordPathField;
    NSPopUpButton *cacheLevelPopup;         /* composite *-caching */
    NSTextField *cacheCustomLabel;
    /* PowerVLC lightweight media library */
    NSTextField *managedMediaFolderField;
    NSTableView *mediaFoldersTable;
    NSMutableArray *mediaFolders;
    NSTableView *smartPlaylistsTable;
    NSMutableArray *smartPlaylists;
    NSInteger smartPlaylistModalResult;
    /* Portable-player profiles. */
    NSTableView *portablePlayersTable;
    NSMutableArray *portablePlayers;
    NSInteger activePortablePlayerRow;
    NSTextField *portablePlayerNameField;
    NSTextField *portablePlayerPathField;
    NSTextField *portablePlayerBackupField;
    NSPopUpButton *portablePlayerKindPopup;
    NSButton *portablePlayerTranscodeCheckbox;
    NSPopUpButton *portablePlayerCodecPopup;
    NSTextField *portablePlayerBitrateField;
    NSButton *portablePlayerAlbumArtistComposerCheckbox;
    /* deinterlacing: the quality presets, plus the raw method picker that is
     * only revealed when the "Custom" preset is selected */
    NSPopUpButton *deintQualityPopup;
    NSPopUpButton *deintMethodPopup;
    NSTextField *deintMethodLabel;
    NSTextField *fontField;                 /* freetype-font + font panel */
    NSSlider *opacitySlider;                /* freetype-opacity (0-100 %) */
    NSTextField *opacityField;

    /* advanced ("Show All") mode */
    BOOL advancedMode;
    NSButton *toggleButton;
    NSView *advancedContainer;
    NSOutlineView *categoryOutline;
    NSScrollView *optionsScroll;
    NSMutableArray *categoryTree;     /* nodes {title, kind, children, ...} */
    NSMutableArray *advancedEntries;  /* VLCLegacyPrefEntry, current pane */

    /* hotkeys pane */
    NSTableView *hotkeysTable;
    NSMutableArray *hotkeyNames;  /* NSString, config item name */
    NSMutableArray *hotkeyTexts;  /* NSString, human description */
    NSMutableArray *hotkeyValues; /* NSString, current raw value */
    NSMutableArray *hotkeyDirty;  /* NSNumber BOOL per row */

    /* hotkey capture panel (3.0 "Press new keys for..." sheet) */
    NSPanel *capturePanel;
    NSTextField *captureActionLabel;
    NSTextField *captureKeysLabel;
    NSTextField *captureTakenLabel;
    NSButton *captureOKButton;
    NSString *captureKeyInTransition;
    int captureRow;
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;
- (void)showWindow;

/* called by the capture panel with a "Command-Shift-x" style string */
- (BOOL)changeHotkeyTo:(NSString *)key;

/* deinterlacing: reveal the raw method picker only for the "Custom" preset */
- (void)deinterlaceQualityChanged:(id)sender;
- (void)syncDeinterlaceMethodVisibility;

/* Jaguar-compatible replacement for NSAlert's 10.5 accessory view. */
- (void)finishSmartPlaylistEditor:(id)sender;
- (void)finishAddingPortablePlayer:(id)rowNumber;

@end
