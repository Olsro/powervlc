/*****************************************************************************
 *MainMenu.m: MacOS X interface module
 *****************************************************************************
 *Copyright (C) 2011-2018 Felix Paul Kühne
 *$Id$
 *
 *Authors: Felix Paul Kühne <fkuehne -at- videolan -dot- org>
 *
 *This program is free software; you can redistribute it and/or modify
 *it under the terms of the GNU General Public License as published by
 *the Free Software Foundation; either version 2 of the License, or
 *(at your option) any later version.
 *
 *This program is distributed in the hope that it will be useful,
 *but WITHOUT ANY WARRANTY; without even the implied warranty of
 *MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *GNU General Public License for more details.
 *
 *You should have received a copy of the GNU General Public License
 *along with this program; if not, write to the Free Software
 *Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCMainMenu.h"
#import "VLCMain.h"

#import <vlc_common.h>
#import <vlc_playlist.h>
#import <vlc_input.h>
#import <vlc_intf_strings.h>
#import <vlc_modules.h>
#import <vlc_url.h>

#import "VLCAboutWindowController.h"
#import "VLCOpenWindowController.h"
#import "VLCAudioEffectsWindowController.h"
#import "VLCErrorWindowController.h"
#import "VLCTrackSynchronizationWindowController.h"
#import "VLCHelpWindowController.h"
#import "../macosx_crystalhd.h"
#import "../macosx_browser_addon.h"
#import "VLCVideoEffectsWindowController.h"
#import "VLCBookmarksWindowController.h"
#import "VLCSimplePrefsController.h"
#import "VLCPlaylist.h"
#import "VLCPlaylistInfo.h"
#import "VLCVoutView.h"
#import "VLCCoreDialogProvider.h"
#import "VLCCoreInteraction.h"
#import "VLCMainWindow.h"
#import "VLCSidebarDataSource.h"
#import "VLCMainWindowControlsBar.h"
#import "VLCDocumentController.h"
#import "VLCExtensionsManager.h"
#import "VLCConvertAndSaveWindowController.h"
#import "VLCConnectToServerDialog.h"
#import "VLCLogWindowController.h"
#import "VLCAddonsWindowController.h"
#import "VLCTimeSelectionPanelController.h"
#import "NSScreen+VLCAdditions.h"
#import "VLCRendererMenuController.h"
#import "VLCCustomCropArWindowController.h"

@interface VLCMainMenu() <NSMenuDelegate>
{
    VLCAboutWindowController *_aboutWindowController;
    VLCHelpWindowController  *_helpWindowController;
    VLCAddonsWindowController *_addonsController;
    VLCRendererMenuController *_rendererMenuController;
    NSTimer *_cancelRendererDiscoveryTimer;

    NSMenu *_playlistTableColumnsContextMenu;

    NSMenuItem *_recentStreamsMenuItem;
    NSMenu *_recentStreamsMenu;
    NSMenuItem *_connectToServerMenuItem;

    /* Blu-ray Pop-Up Menu, built in -awakeFromNib rather than carried by
     * MainMenu.xib. Two items, one per menu: an NSMenuItem cannot live in two
     * menus at once. */
    NSMenuItem *_discPopupMenuItem;     /* Playback menu */
    NSMenuItem *_voutDiscPopupMenuItem; /* right-click on the video */

    /* Quality of an adaptive stream, under Video Track. Also built here:
     * it only ever appears for HLS/DASH. */
    NSMenuItem *_adaptiveQualityMenuItem;
    NSMenuItem *_adaptiveMaxHeightMenuItem;

    /* Clip creation mode, right below Record. Also built here. */
    NSMenuItem *_clipModeMenuItem;

    /* Hide controls during playback, right below Float on Top. Also
     * built here. */
    NSMenuItem *_hideControlsMenuItem;

    __strong VLCTimeSelectionPanelController *_timeSelectionPanel;
}

- (void)rebuildRecentStreamsMenu;
- (void)openRecentStream:(id)sender;
- (void)clearRecentStreams:(id)sender;
- (void)openPowerVLCReleases:(id)sender;
@end

#define VLC_RECENT_STREAMS_KEY @"VLCRecentStreams"
#define VLC_RECENT_STREAMS_MAX 30

static BOOL VLCVariableMenuShowsCurrentChoice(const char *name, int type)
{
    /* Most command variables describe one-shot actions. Crop and aspect ratio
     * are commands only so their changes propagate immediately to the vout;
     * they still represent persistent selections in their menus. */
    return !(type & VLC_VAR_ISCOMMAND)
        || !strcmp(name, "crop")
        || !strcmp(name, "aspect-ratio");
}

static NSString *VLCMRLWithoutPassword(NSString *mrl)
{
    vlc_url_t url;
    if (vlc_UrlParseFixup(&url, [mrl UTF8String]) != 0)
        return mrl;
    /* Components returned by vlc_UrlParseFixup() point into psz_buffer.
     * Hiding the password only requires omitting that component while
     * composing the display URI; vlc_UrlClean() owns and frees the buffer. */
    url.psz_password = NULL;
    char *composed = vlc_uri_compose(&url);
    vlc_UrlClean(&url);
    if (!composed)
        return mrl;
    NSString *result = [NSString stringWithUTF8String:composed];
    free(composed);
    return result ?: mrl;
}

void VLCNoteRecentStream(NSString *mrl)
{
    if (![mrl length])
        return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *stored = [defaults stringArrayForKey:VLC_RECENT_STREAMS_KEY];
    NSMutableArray *streams = stored
        ? [NSMutableArray arrayWithArray:stored] : [NSMutableArray array];
    [streams removeObject:mrl];
    [streams insertObject:mrl atIndex:0];
    while ([streams count] > VLC_RECENT_STREAMS_MAX)
        [streams removeLastObject];
    [defaults setObject:streams forKey:VLC_RECENT_STREAMS_KEY];
}

@implementation VLCMainMenu

#pragma mark - Initialization

- (void)dealloc
{
    msg_Dbg(getIntf(), "Deinitializing main menu");
    [[NSNotificationCenter defaultCenter] removeObserver: self];

    [self releaseRepresentedObjects:[NSApp mainMenu]];
}

- (void)awakeFromNib
{
    _timeSelectionPanel = [[VLCTimeSelectionPanelController alloc] init];

    /* check whether the user runs OSX with a RTL language */
    NSArray* languages = [NSLocale preferredLanguages];
    NSString* preferredLanguage = [languages firstObject];

    if ([NSLocale characterDirectionForLanguage:preferredLanguage] == NSLocaleLanguageDirectionRightToLeft) {
        msg_Dbg(getIntf(), "adapting interface since '%s' is a RTL language", [preferredLanguage UTF8String]);
        [_rateTextField setAlignment: NSLeftTextAlignment];
    }

    [self setRateControlsEnabled:NO];

    [_checkForUpdate setAction:@selector(openPowerVLCReleases:)];
    [_checkForUpdate setTarget:self];
    [_checkForUpdate setEnabled:YES];

    NSString* keyString;
    vlc_value_t val;
    VLCStringUtility *stringUtility = [VLCStringUtility sharedInstance];
    char *key;

    /* Get ExtensionsManager */
    intf_thread_t *p_intf = getIntf();

    [self initStrings];

    [(VLCDocumentController *)[NSDocumentController sharedDocumentController]
        migrateRecentStreamsFromDocumentHistory];

    NSMenu *openMenu = [_open_capture menu];
    if (openMenu) {
        _connectToServerMenuItem = [[NSMenuItem alloc]
            initWithTitle:_NS("Connect to Server...")
                   action:@selector(connectToServer:)
            keyEquivalent:@"k"];
        [_connectToServerMenuItem setTarget:self];
        [openMenu insertItem:_connectToServerMenuItem
                     atIndex:[openMenu indexOfItem:_open_capture] + 1];
    }

    /* AppKit owns the local-file history. Streams need a distinct list: a
     * network MRL in NSDocumentController is presented as if it were a file
     * and cannot be opened reliably by the recent-documents machinery. */
    NSMenu *fileMenu = [_open_recent menu];
    if (fileMenu) {
        _recentStreamsMenu = [[NSMenu alloc]
            initWithTitle:_NS("Open Recent Stream")];
        [_recentStreamsMenu setDelegate:self];
        [_recentStreamsMenu setAutoenablesItems:NO];
        _recentStreamsMenuItem = [[NSMenuItem alloc]
            initWithTitle:_NS("Open Recent Stream")
                   action:nil
            keyEquivalent:@""];
        [_recentStreamsMenuItem setSubmenu:_recentStreamsMenu];
        [fileMenu insertItem:_recentStreamsMenuItem
                     atIndex:[fileMenu indexOfItem:_open_recent] + 1];
        [self rebuildRecentStreamsMenu];
    }

    /* Blu-ray pop-up menu, at the end of the Playback menu right below
     * Chapter, and in the video contextual menu -- the only menu within reach
     * in fullscreen. Added here instead of in MainMenu.xib so that the entry,
     * its wiring and its enable rule live in one place, next to the other
     * three interfaces doing exactly the same. */
    NSMenu *playbackMenu = [_chapter menu];
    if (playbackMenu) {
        _discPopupMenuItem = [[NSMenuItem alloc]
            initWithTitle:_NS(I_MENU_DISC_POPUP)
                   action:@selector(showDiscPopupMenu:)
            keyEquivalent:@""];
        [_discPopupMenuItem setTarget:self];
        [playbackMenu insertItem:_discPopupMenuItem
                         atIndex:[playbackMenu indexOfItem:_chapter] + 1];
    }
    if (_voutMenu) {
        _voutDiscPopupMenuItem = [[NSMenuItem alloc]
            initWithTitle:_NS(I_MENU_DISC_POPUP)
                   action:@selector(showDiscPopupMenu:)
            keyEquivalent:@""];
        [_voutDiscPopupMenuItem setTarget:self];
        /* set apart by a separator: it acts on the disc, not on our playback */
        NSInteger snapshotIndex = [_voutMenu indexOfItem:_voutMenusnapshot];
        if (snapshotIndex < 0) {
            [_voutMenu addItem:[NSMenuItem separatorItem]];
            [_voutMenu addItem:_voutDiscPopupMenuItem];
        } else {
            [_voutMenu insertItem:[NSMenuItem separatorItem]
                          atIndex:snapshotIndex + 1];
            [_voutMenu insertItem:_voutDiscPopupMenuItem
                          atIndex:snapshotIndex + 2];
        }
    }

    /* Clip creation mode, right below Record: a second knob appears on the
     * seek bar so both clip bounds can be set with instant preview, and
     * Record then saves exactly that range. Built here instead of in
     * MainMenu.xib, like the Blu-ray pop-up entry above. */
    NSMenu *recordMenu = [_record menu];
    if (recordMenu) {
        _clipModeMenuItem = [[NSMenuItem alloc]
            initWithTitle:_NS("Enter Clip Creation Mode")
                   action:@selector(toggleClipCreationMode:)
            keyEquivalent:@"c"];
        /* Command+Shift+C ("Clip"): Command+C is Copy and Command+Alt+C the
         * playback window. Same equivalent in the legacy interface. */
        [_clipModeMenuItem setKeyEquivalentModifierMask:
            NSCommandKeyMask | NSShiftKeyMask];
        [_clipModeMenuItem setTarget:self];
        [recordMenu insertItem:_clipModeMenuItem
                       atIndex:[recordMenu indexOfItem:_record] + 1];
    }
    /* Hide controls during playback, right below Float on Top: windowed
     * playback drops the controls bar and the title bar a few seconds
     * after the mouse leaves the window; a double click on the video
     * brings them back. Built here like the entries above. */
    if (_videoMenu && _floatontop) {
        _hideControlsMenuItem = [[NSMenuItem alloc]
            initWithTitle:_NS("Hide Controls During Playback")
                   action:@selector(toggleHideControlsPlayback:)
            keyEquivalent:@"h"];
        /* Command+Shift+H: Command+H hides the app, Command+Alt+H the
         * other apps. Same equivalent in the legacy interface. */
        [_hideControlsMenuItem setKeyEquivalentModifierMask:
            NSCommandKeyMask | NSShiftKeyMask];
        [_hideControlsMenuItem setTarget:self];
        [_videoMenu insertItem:_hideControlsMenuItem
                       atIndex:[_videoMenu indexOfItem:_floatontop] + 1];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(clipCreationModeChanged:)
                                                 name:VLCClipCreationModeChangedNotification
                                               object:nil];

    /* An adaptive stream (HLS/DASH) offers the same programme at several
     * qualities and picks one on its own, from a bandwidth estimate. When
     * it changes its mind the resolution changes with it: the picture is
     * rebuilt and the window follows. Let the user pin one instead, right
     * below Video Track since that is the same kind of choice -- which of
     * the pictures on offer to watch.
     *
     * Filled (and shown) only while an adaptive stream is playing, see
     * -setupMenus; the demuxer publishes the list on the input. */
    NSMenu *videoMenu = [_videotrack menu];
    if (videoMenu) {
        _adaptiveQualityMenuItem = [[NSMenuItem alloc] initWithTitle:_NS("Quality")
                                                             action:nil
                                                      keyEquivalent:@""];
        [_adaptiveQualityMenuItem setSubmenu:
            [[NSMenu alloc] initWithTitle:_NS("Quality")]];
        [_adaptiveQualityMenuItem setHidden:YES];
        [videoMenu insertItem:_adaptiveQualityMenuItem
                      atIndex:[videoMenu indexOfItem:_videotrack] + 1];

        /* and the standing resolution ceiling right below it: not a
         * choice about this stream but about the machine, which is why
         * it is a setting of its own rather than one more line in the
         * list above */
        _adaptiveMaxHeightMenuItem = [[NSMenuItem alloc]
            initWithTitle:_NS("Auto quality by resolution")
                   action:nil
            keyEquivalent:@""];
        [_adaptiveMaxHeightMenuItem setSubmenu:
            [[NSMenu alloc] initWithTitle:_NS("Auto quality by resolution")]];
        [_adaptiveMaxHeightMenuItem setHidden:YES];
        [videoMenu insertItem:_adaptiveMaxHeightMenuItem
                      atIndex:[videoMenu indexOfItem:_adaptiveQualityMenuItem] + 1];
    }

    /* interface switcher, below Preferences and its separator (only when
     * this build also ships the legacy interface) */
    if (module_exists("legacy_macosx")) {
        msg_Dbg(p_intf, "adding the legacy interface switcher menu item");
        NSMenu *appMenu = [_prefs menu];
        NSInteger prefsIndex = [appMenu indexOfItem:_prefs];
        NSMenuItem *switchItem = [[NSMenuItem alloc]
            initWithTitle:_NS("Switch to the legacy interface")
                   action:@selector(switchToLegacyInterface:)
            keyEquivalent:@""];
        [switchItem setTarget:self];
        [appMenu insertItem:switchItem atIndex:prefsIndex + 2];
        [appMenu insertItem:[NSMenuItem separatorItem] atIndex:prefsIndex + 3];
    }

    /* libaacs and libbdplus ship with the player but decrypt nothing until the
     * user drops their own files next to them -- in a folder inside
     * ~/Library/Preferences that nobody would ever find on their own. Offer to
     * open it, but only when this build can play Blu-ray at all. Appended to
     * the Help menu rather than declared in the nib: nothing here depends on
     * the layout of that menu.
     *
     * "libbluray", not "bluray": module_find() only ever compares
     * pp_shortcuts[0], which is the module's object name (the plugin is built
     * as liblibbluray_plugin). The "bluray" of add_shortcut() sits at index 1
     * and can never match. */
    if (module_exists("libbluray")) {
        [_helpMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:_NS("Open the libaacs folder (Blu-ray)")
                   action:@selector(openAACSFolder:)
            keyEquivalent:@""];
        [item setTarget:self];
        [_helpMenu addItem:item];

        item = [[NSMenuItem alloc]
            initWithTitle:_NS("Open the libbdplus folder (Blu-ray)")
                   action:@selector(openBDPlusFolder:)
            keyEquivalent:@""];
        [item setTarget:self];
        [_helpMenu addItem:item];
    }

    /* The browser half of PowerVLC: it hands what the browser is playing over
     * to the player, and lets the player read pages the user has opened --
     * which is the only way in on a browser older than Firefox 69, since
     * those refuse to run a bookmarklet on a page carrying a security
     * policy. Only offered when this build ships it. */
    if (VLCBrowserAddonPath() != nil) {
        [_helpMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *addonItem = [[NSMenuItem alloc]
            initWithTitle:_NS("Install the PowerVLC add-on in your browser...")
                   action:@selector(installBrowserAddon:)
            keyEquivalent:@""];
        [addonItem setTarget:self];
        [_helpMenu addItem:addonItem];
    }

    /* Crystal HD: offer to install the driver when there is a card to drive,
     * and to remove it whenever one is installed -- including on a machine
     * whose card has since been taken out, which is the only way left to get
     * rid of it. */
    VLCCrystalHDState chdState = VLCCrystalHDGetState();
    if (chdState != VLCCrystalHDAbsent) {
        BOOL install = (chdState == VLCCrystalHDCardWithoutDriver);

        [_helpMenu addItem:[NSMenuItem separatorItem]];

        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:install ? _NS("Install the Crystal HD driver...")
                                  : _NS("Remove the Crystal HD driver...")
                   action:install ? @selector(installCrystalHDDriver:)
                                  : @selector(uninstallCrystalHDDriver:)
            keyEquivalent:@""];
        [item setTarget:self];
        [_helpMenu addItem:item];

        /* Only worth offering when there is a driver to reload. */
        if (!install) {
            NSMenuItem *reload = [[NSMenuItem alloc]
                initWithTitle:_NS("Reload the Crystal HD driver...")
                       action:@selector(reloadCrystalHDDriver:)
                keyEquivalent:@""];
            [reload setTarget:self];
            [_helpMenu addItem:reload];
        }
    }

    key = config_GetPsz(p_intf, "key-quit");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_quit setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_quit setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    // do not assign play/pause key

    key = config_GetPsz(p_intf, "key-stop");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_stop setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_stop setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-prev");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_previous setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_previous setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-next");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_next setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_next setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-jump+short");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_fwd setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_fwd setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-jump-short");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_bwd setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_bwd setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-vol-up");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_vol_up setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_vol_up setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-vol-down");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_vol_down setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_vol_down setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-vol-mute");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_mute setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_mute setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-toggle-fullscreen");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_fullscreenItem setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_fullscreenItem setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-snapshot");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_snapshot setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_snapshot setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-random");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_random setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_random setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-zoom-half");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_half_window setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_half_window setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-zoom-original");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_normal_window setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_normal_window setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    key = config_GetPsz(p_intf, "key-zoom-double");
    keyString = [NSString stringWithFormat:@"%s", key];
    [_double_window setKeyEquivalent: [stringUtility VLCKeyToString: keyString]];
    [_double_window setKeyEquivalentModifierMask: [stringUtility VLCModifiersToCocoa:keyString]];
    FREENULL(key);

    [self setSubmenusEnabled: FALSE];

    /* configure playback / controls menu */
    self.controlsMenu.delegate = self;
    [_rendererNoneItem setState:NSOnState];
    _rendererMenuController = [[VLCRendererMenuController alloc] init];
    _rendererMenuController.rendererNoneItem = _rendererNoneItem;
    _rendererMenuController.rendererMenu = _rendererMenu;

    [[NSNotificationCenter defaultCenter] addObserver: self
                                             selector: @selector(refreshVoutDeviceMenu:)
                                                 name: NSApplicationDidChangeScreenParametersNotification
                                               object: nil];

    [self setupVarMenuItem:_add_intf target: (vlc_object_t *)p_intf
                             var:"intf-add" selector: @selector(toggleVar:)];

    /* setup extensions menu */
    /* Let the ExtensionsManager itself build the menu */
    VLCExtensionsManager *extMgr = [[VLCMain sharedInstance] extensionsManager];
    [extMgr buildMenu:_extensionsMenu];
    [_extensions setEnabled: ([_extensionsMenu numberOfItems] > 0)];

    // FIXME: Implement preference for autoloading extensions on mac
    if (![extMgr isLoaded] && ![extMgr cannotLoad])
        [extMgr loadExtensions];

    /* setup post-proc menu */
    NSUInteger count = (NSUInteger) [_postprocessingMenu numberOfItems];
    if (count > 0)
        [_postprocessingMenu removeAllItems];

    NSMenuItem *mitem;
    [_postprocessingMenu setAutoenablesItems: YES];
    [_postprocessingMenu addItemWithTitle: _NS("Disable") action:@selector(togglePostProcessing:) keyEquivalent:@""];
    mitem = [_postprocessingMenu itemAtIndex: 0];
    [mitem setTag: -1];
    [mitem setEnabled: YES];
    [mitem setTarget: self];
    for (NSUInteger x = 1; x < 7; x++) {
        [_postprocessingMenu addItemWithTitle:[NSString stringWithFormat:_NS("Level %i"), x]
                                               action:@selector(togglePostProcessing:)
                                        keyEquivalent:@""];
        mitem = [_postprocessingMenu itemAtIndex:x];
        [mitem setEnabled:YES];
        [mitem setTag:x];
        [mitem setTarget:self];
    }
    char *psz_config = config_GetPsz(p_intf, "video-filter");
    if (psz_config) {
        if (!strstr(psz_config, "postproc"))
            [[_postprocessingMenu itemAtIndex:0] setState:NSOnState];
        else
            [[_postprocessingMenu itemWithTag:config_GetInt(p_intf, "postproc-q")] setState:NSOnState];
        free(psz_config);
    } else
        [[_postprocessingMenu itemAtIndex:0] setState:NSOnState];
    [_postprocessing setEnabled: NO];

    [self refreshAudioDeviceList];

    /* setup subtitles menu */
    // Persist those variables on the playlist
    playlist_t *p_playlist = pl_Get(getIntf());
    var_Create(p_playlist, "freetype-color", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    var_Create(p_playlist, "freetype-background-opacity", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    var_Create(p_playlist, "freetype-background-color", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    var_Create(p_playlist, "freetype-outline-thickness", VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);

    [self setupMenu: _subtitle_textcolorMenu withIntList:"freetype-color" andSelector:@selector(switchSubtitleOption:)];
    [_subtitle_bgopacity_sld setIntValue: config_GetInt(VLC_OBJECT(p_intf), "freetype-background-opacity")];
    [self setupMenu: _subtitle_bgcolorMenu withIntList:"freetype-background-color" andSelector:@selector(switchSubtitleOption:)];
    [self setupMenu: _subtitle_outlinethicknessMenu withIntList:"freetype-outline-thickness" andSelector:@selector(switchSubtitleOption:)];

    /* Build size menu based on different scale factors */
    struct {
        const char *const name;
        int scaleValue;
    } scaleValues[] = {
        { N_("Smaller"), 50},
        { N_("Small"),   75},
        { N_("Normal"), 100},
        { N_("Large"),  125},
        { N_("Larger"), 150},
        { NULL, 0 }
    };

    for(int i = 0; scaleValues[i].name; i++) {
        NSMenuItem *menuItem = [_subtitle_sizeMenu addItemWithTitle: _NS(scaleValues[i].name) action:@selector(switchSubtitleSize:) keyEquivalent:@""];
        [menuItem setTag:scaleValues[i].scaleValue];
        [menuItem setTarget: self];
        [menuItem setState:
            var_GetInteger(p_playlist, "sub-text-scale") == scaleValues[i].scaleValue
                ? NSOnState : NSOffState];
    }
}

- (void)openPowerVLCReleases:(id)sender
{
    (void)sender;
    [[NSWorkspace sharedWorkspace]
        openURL:[NSURL URLWithString:
            [NSString stringWithUTF8String:POWERVLC_RELEASES_URL]]];
}

- (void)setupMenu: (NSMenu*)menu withIntList: (char *)psz_name andSelector:(SEL)selector
{
    module_config_t *p_item;

    [menu removeAllItems];
    p_item = config_FindConfig(psz_name);

    if (!p_item) {
        msg_Err(getIntf(), "couldn't create menu int list for item '%s' as it does not exist", psz_name);
        return;
    }

    for (int i = 0; i < p_item->list_count; i++) {
        NSMenuItem *mi;
        if (p_item->list_text != NULL)
            mi = [[NSMenuItem alloc] initWithTitle: _NS(p_item->list_text[i]) action:NULL keyEquivalent: @""];
        else if (p_item->list.i[i])
            mi = [[NSMenuItem alloc] initWithTitle: [NSString stringWithFormat: @"%d", p_item->list.i[i]] action:NULL keyEquivalent: @""];
        else {
            msg_Err(getIntf(), "item %d of pref %s failed to be created", i, psz_name);
            continue;
        }

        [mi setTarget:self];
        [mi setAction:selector];
        [mi setTag:p_item->list.i[i]];
        [mi setRepresentedObject:toNSStr(psz_name)];
        [menu addItem:mi];
        if (p_item->value.i == p_item->list.i[i])
            [mi setState:NSOnState];
    }
}

- (void)initStrings
{
    /* main menu */
    [_about setTitle: [_NS("About PowerVLC media player") \
                           stringByAppendingString: @"..."]];
    [_checkForUpdate setTitle: _NS("Check for Update...")];
    [_prefs setTitle: _NS("Preferences...")];
    [_extensions setTitle: _NS("Extensions")];
    [_extensionsMenu setTitle: _NS("Extensions")];
    [_addonManager setTitle: _NS("Addons Manager")];
    [_add_intf setTitle: _NS("Add Interface")];
    [_add_intfMenu setTitle: _NS("Add Interface")];
    [_services setTitle: _NS("Services")];
    [_hide setTitle: _NS("Hide PowerVLC")];
    [_hide_others setTitle: _NS("Hide Others")];
    [_show_all setTitle: _NS("Show All")];
    [_quit setTitle: _NS("Quit PowerVLC")];

    [_fileMenu setTitle: _ANS("1:File")];
    [_open_generic setTitle: _NS("Advanced Open File...")];
    [_open_file setTitle: _NS("Open File...")];
    [_open_disc setTitle: _NS("Open Disc...")];
    [_open_net setTitle: _NS("Open Network...")];
    [_open_capture setTitle: _NS("Open Capture Device...")];
    [_open_recent setTitle: _NS("Open Recent File")];
    [[_open_recent submenu] setTitle:_NS("Open Recent File")];
    [_close_window setTitle: _NS("Close Window")];
    [_convertandsave setTitle: _NS("Convert / Stream...")];
    [_save_playlist setTitle: _NS("Save Playlist...")];
    [_revealInFinder setTitle: _NS("Reveal in Finder")];

    [_editMenu setTitle: _NS("Edit")];
    [_cutItem setTitle: _NS("Cut")];
    [_mcopyItem setTitle: _NS("Copy")];
    [_pasteItem setTitle: _NS("Paste")];
    [_clearItem setTitle: _NS("Delete")];
    [_select_all setTitle: _NS("Select All")];
    [_findItem setTitle: _NS("Find")];

    [_viewMenu setTitle: _NS("View")];
    [_toggleJumpButtons setTitle: _NS("Show Previous & Next Buttons")];
    [_toggleJumpButtons setState: var_InheritBool(getIntf(), "macosx-show-playback-buttons")];
    [_togglePlaymodeButtons setTitle: _NS("Show Shuffle & Repeat Buttons")];
    [_togglePlaymodeButtons setState: var_InheritBool(getIntf(), "macosx-show-playmode-buttons")];
    [_toggleEffectsButton setTitle: _NS("Show Audio Effects Button")];
    [_toggleEffectsButton setState: var_InheritBool(getIntf(), "macosx-show-effects-button")];
    [_toggleSidebar setTitle: _NS("Show Sidebar")];
    [_playlistTableColumns setTitle: _NS("Playlist Table Columns")];

    [_controlsMenu setTitle: _NS("Playback")];
    [_play setTitle: _NS("Play")];
    [_stop setTitle: _NS("Stop")];
    [_record setTitle: _NS("Record")];
    [_rate_view setAutoresizingMask:NSViewWidthSizable];
    [_rate setView: _rate_view];
    [_rateLabel setStringValue: _NS("Playback Speed")];
    [_rate_slowerLabel setStringValue: _NS("Slower")];
    [_rate_normalLabel setStringValue: _NS("Normal")];
    [_rate_fasterLabel setStringValue: _NS("Faster")];
    [_trackSynchronization setTitle: _NS("Track Synchronization")];
    [_previous setTitle: _NS("Previous")];
    [_next setTitle: _NS("Next")];
    [_random setTitle: _NS("Random")];
    [_repeat setTitle: _NS("Repeat One")];
    [_loop setTitle: _NS("Repeat All")];
    [_AtoBloop setTitle: _NS("A→B Loop")];
    [_quitAfterPB setTitle: _NS("Quit after Playback")];
    [_fwd setTitle: _NS("Step Forward")];
    [_bwd setTitle: _NS("Step Backward")];
    [_jumpToTime setTitle: _NS("Jump to Time")];
    [_rendererMenuItem setTitle:_NS("Renderer")];
    [_rendererNoneItem setTitle:_NS("No renderer")];
    [_program setTitle: _NS("Program")];
    [_programMenu setTitle: _NS("Program")];
    [_title setTitle: _NS("Title")];
    [_titleMenu setTitle: _NS("Title")];
    [_chapter setTitle: _NS("Chapter")];
    [_chapterMenu setTitle: _NS("Chapter")];

    [_audioMenu setTitle: _NS("Audio")];
    [_vol_up setTitle: _NS("Increase Volume")];
    [_vol_down setTitle: _NS("Decrease Volume")];
    [_mute setTitle: _NS("Mute")];
    [_audiotrack setTitle: _NS("Audio Track")];
    [_audiotrackMenu setTitle: _NS("Audio Track")];
    [_channels setTitle: _NS("Stereo audio mode")];
    [_channelsMenu setTitle: _NS("Stereo audio mode")];
    [_audioDevice setTitle: _NS("Audio Device")];
    [_audioDeviceMenu setTitle: _NS("Audio Device")];
    [_visual setTitle: _NS("Visualizations")];
    [_visualMenu setTitle: _NS("Visualizations")];

    [_videoMenu setTitle: _NS("Video")];
    [_half_window setTitle: _NS("Half Size")];
    [_normal_window setTitle: _NS("Normal Size")];
    [_double_window setTitle: _NS("Double Size")];
    [_fittoscreen setTitle: _NS("Fit to Screen")];
    [_fullscreenItem setTitle: _NS("Fullscreen")];
    [_floatontop setTitle: _NS("Float on Top")];
    [_snapshot setTitle: _NS("Snapshot")];
    [_videotrack setTitle: _NS("Video Track")];
    [_videotrackMenu setTitle: _NS("Video Track")];
    [_aspect_ratio setTitle: _NS("Aspect ratio")];
    [_aspect_ratioMenu setTitle: _NS("Aspect ratio")];
    [_crop setTitle: _NS("Crop")];
    [_cropMenu setTitle: _NS("Crop")];
    [_screen setTitle: _NS("Fullscreen Video Device")];
    [_screenMenu setTitle: _NS("Fullscreen Video Device")];
    [_deinterlace setTitle: _NS("Deinterlace")];
    [_deinterlaceMenu setTitle: _NS("Deinterlace")];
    [_deinterlace_mode setTitle: _NS("Deinterlace mode")];
    [_deinterlace_modeMenu setTitle: _NS("Deinterlace mode")];
    [_postprocessing setTitle: _NS("Post processing")];
    [_postprocessingMenu setTitle: _NS("Post processing")];

    [_subtitlesMenu setTitle:_NS("Subtitles")];
    [_openSubtitleFile setTitle: _NS("Add Subtitle File...")];
    [_subtitle_track setTitle: _NS("Subtitles Track")];
    [_subtitle_tracksMenu setTitle: _NS("Subtitles Track")];
    [_subtitle_size setTitle: _NS("Text Size")];
    [_subtitle_textcolor setTitle: _NS("Text Color")];
    [_subtitle_outlinethickness setTitle: _NS("Outline Thickness")];

    // Autoresizing with constraints does not work on 10.7,
    // translate autoresizing mask to constriaints for now
    [_subtitle_bgopacity_view setAutoresizingMask:NSViewWidthSizable];
    [_subtitle_bgopacity setView: _subtitle_bgopacity_view];
    [_subtitle_bgopacityLabel setStringValue: _NS("Background Opacity")];
    [_subtitle_bgopacityLabel_gray setStringValue: _NS("Background Opacity")];
    [_subtitle_bgcolor setTitle: _NS("Background Color")];
    [_teletext setTitle: _NS("Teletext")];
    [_teletext_transparent setTitle: _NS("Transparent")];
    [_teletext_index setTitle: _NS("Index")];
    [_teletext_red setTitle: _NS("Red")];
    [_teletext_green setTitle: _NS("Green")];
    [_teletext_yellow setTitle: _NS("Yellow")];
    [_teletext_blue setTitle: _NS("Blue")];

    [_windowMenu setTitle: _NS("Window")];
    [_minimize setTitle: _NS("Minimize")];
    [_zoom_window setTitle: _NS("Zoom")];
    [_player setTitle: _NS("Player...")];
    [_controller setTitle: _NS("Main Window...")];
    [_audioeffects setTitle: _NS("Audio Effects...")];
    [_videoeffects setTitle: _NS("Video Effects...")];
    [_bookmarks setTitle: _NS("Bookmarks...")];
    [_playlist setTitle: _NS("Playlist...")];
    [_info setTitle: _NS("Media Information...")];
    [_messages setTitle: _NS("Messages...")];
    [_errorsAndWarnings setTitle: _NS("Errors and Warnings...")];

    [_bring_atf setTitle: _NS("Bring All to Front")];

    [_helpMenu setTitle: _NS("Help")];
    [_help setTitle: _NS("PowerVLC media player Help...")];
    [_license setTitle: _NS("License")];
    [_documentation setTitle: _NS("Online Documentation...")];
    [_website setTitle: _NS("VideoLAN Website...")];
    [_donation setTitle: _NS("Make a donation...")];
    [_forum setTitle: _NS("Online Forum...")];

    /* dock menu */
    [_dockMenuplay setTitle: _NS("Play")];
    [_dockMenustop setTitle: _NS("Stop")];
    [_dockMenunext setTitle: _NS("Next")];
    [_dockMenuprevious setTitle: _NS("Previous")];
    [_dockMenumute setTitle: _NS("Mute")];

    /* vout menu */
    [_voutMenuplay setTitle: _NS("Play")];
    [_voutMenustop setTitle: _NS("Stop")];
    [_voutMenuprev setTitle: _NS("Previous")];
    [_voutMenunext setTitle: _NS("Next")];
    [_voutMenuvolup setTitle: _NS("Volume Up")];
    [_voutMenuvoldown setTitle: _NS("Volume Down")];
    [_voutMenumute setTitle: _NS("Mute")];
    [_voutMenufullscreen setTitle: _NS("Fullscreen")];
    [_voutMenusnapshot setTitle: _NS("Snapshot")];
}

#pragma mark - Termination

- (void)releaseRepresentedObjects:(NSMenu *)the_menu
{
    NSArray *menuitems_array = [the_menu itemArray];
    NSUInteger menuItemCount = [menuitems_array count];
    for (NSUInteger i=0; i < menuItemCount; i++) {
        NSMenuItem *one_item = [menuitems_array objectAtIndex:i];
        if ([one_item hasSubmenu])
            [self releaseRepresentedObjects: [one_item submenu]];

        [one_item setRepresentedObject:NULL];
    }
}

#pragma mark - Interface update

- (void)setupMenus
{
    playlist_t *p_playlist = pl_Get(getIntf());
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (p_input != NULL) {
        [self setupVarMenuItem:_program target: (vlc_object_t *)p_input
                                 var:"program" selector: @selector(toggleVar:)];

        [self setupVarMenuItem:_title target: (vlc_object_t *)p_input
                                 var:"title" selector: @selector(toggleVar:)];

        [self setupVarMenuItem:_chapter target: (vlc_object_t *)p_input
                                 var:"chapter" selector: @selector(toggleVar:)];

        [self setupVarMenuItem:_audiotrack target: (vlc_object_t *)p_input
                                 var:"audio-es" selector: @selector(toggleVar:)];

        [self setupVarMenuItem:_videotrack target: (vlc_object_t *)p_input
                                 var:"video-es" selector: @selector(toggleVar:)];

        [self setupVarMenuItem:_subtitle_track target: (vlc_object_t *)p_input
                                 var:"spu-es" selector: @selector(toggleVar:)];

        /* Only an adaptive stream has qualities to choose from: asking
         * -setupVarMenuItem: for a variable that is not there would leave
         * the item titled and empty, and complain in the log every time a
         * menu opens. */
        if (_adaptiveQualityMenuItem != nil) {
            BOOL hasQualities = (var_Type((vlc_object_t *)p_input, "adaptive-quality")
                                 & VLC_VAR_TYPE) == VLC_VAR_INTEGER;
            [_adaptiveQualityMenuItem setHidden:!hasQualities];
            if (hasQualities)
                [self setupVarMenuItem:_adaptiveQualityMenuItem
                                target:(vlc_object_t *)p_input
                                   var:"adaptive-quality"
                              selector:@selector(toggleVar:)];
        }

        /* only offered when the playlist states its resolutions */
        if (_adaptiveMaxHeightMenuItem != nil) {
            BOOL hasHeights = (var_Type((vlc_object_t *)p_input, "adaptive-maxheight")
                               & VLC_VAR_TYPE) == VLC_VAR_INTEGER;
            [_adaptiveMaxHeightMenuItem setHidden:!hasHeights];
            if (hasHeights)
                [self setupVarMenuItem:_adaptiveMaxHeightMenuItem
                                target:(vlc_object_t *)p_input
                                   var:"adaptive-maxheight"
                              selector:@selector(toggleVar:)];
        }

        audio_output_t *p_aout = playlist_GetAout(p_playlist);
        if (p_aout != NULL) {
            [self setupVarMenuItem:_channels target: (vlc_object_t *)p_aout
                                     var:"stereo-mode" selector: @selector(toggleVar:)];

            [self setupVarMenuItem:_visual target: (vlc_object_t *)p_aout
                                     var:"visual" selector: @selector(toggleVar:)];
            vlc_object_release(p_aout);
        }

        vout_thread_t *p_vout = getVoutForActiveWindow();

        if (p_vout != NULL) {
            [self setupVarMenuItem:_aspect_ratio target: (vlc_object_t *)p_vout
                                     var:"aspect-ratio" selector: @selector(toggleVar:)];
            [self appendCustomizationItemTo:_aspect_ratio
                                     action:@selector(performCustomAspectRatio:)];

            [self setupVarMenuItem:_crop target: (vlc_object_t *) p_vout
                                     var:"crop" selector: @selector(toggleVar:)];
            [self appendCustomizationItemTo:_crop
                                     action:@selector(performCustomCrop:)];

            [self setupVarMenuItem:_deinterlace target: (vlc_object_t *)p_vout
                                     var:"deinterlace" selector: @selector(toggleVar:)];

            [self setupVarMenuItem:_deinterlace_mode target: (vlc_object_t *)p_vout
                                     var:"deinterlace-mode" selector: @selector(toggleVar:)];

            vlc_object_release(p_vout);

            [self refreshVoutDeviceMenu:nil];
        }
        [_postprocessing setEnabled:YES];
        vlc_object_release(p_input);
    } else {
        [_postprocessing setEnabled:NO];
        [_adaptiveQualityMenuItem setHidden:YES];
        [_adaptiveMaxHeightMenuItem setHidden:YES];
    }
}

- (void)refreshVoutDeviceMenu:(NSNotification *)notification
{
    NSUInteger count = (NSUInteger) [_screenMenu numberOfItems];
    NSMenu *submenu = _screenMenu;
    if (count > 0)
        [submenu removeAllItems];

    NSArray *screens = [NSScreen screens];
    NSMenuItem *mitem;
    count = [screens count];
    [_screen setEnabled: YES];
    [submenu addItemWithTitle: _NS("Default") action:@selector(toggleFullscreenDevice:) keyEquivalent:@""];
    mitem = [submenu itemAtIndex: 0];
    [mitem setTag: 0];
    [mitem setEnabled: YES];
    [mitem setTarget: self];
    NSRect s_rect;
    for (NSUInteger i = 0; i < count; i++) {
        s_rect = [[screens objectAtIndex:i] frame];
        [submenu addItemWithTitle: [NSString stringWithFormat: @"%@ %li (%ix%i)", _NS("Screen"), i+1,
                                      (int)s_rect.size.width, (int)s_rect.size.height] action:@selector(toggleFullscreenDevice:) keyEquivalent:@""];
        mitem = [submenu itemAtIndex:i+1];
        [mitem setTag: (int)[[screens objectAtIndex:i] displayID]];
        [mitem setEnabled: YES];
        [mitem setTarget: self];
    }
    [[submenu itemWithTag: var_InheritInteger(getIntf(), "macosx-vdev")] setState: NSOnState];
}

- (void)setSubmenusEnabled:(BOOL)b_enabled
{
    [_program setEnabled: b_enabled];
    [_title setEnabled: b_enabled];
    [_chapter setEnabled: b_enabled];
    [_audiotrack setEnabled: b_enabled];
    [_visual setEnabled: b_enabled];
    [_videotrack setEnabled: b_enabled];
    [_subtitle_track setEnabled: b_enabled];
    [_channels setEnabled: b_enabled];
    [_deinterlace setEnabled: b_enabled];
    [_deinterlace_mode setEnabled: b_enabled];
    [_screen setEnabled: b_enabled];
    [_aspect_ratio setEnabled: b_enabled];
    [_crop setEnabled: b_enabled];
}

- (void)setSubtitleMenuEnabled:(BOOL)b_enabled
{
    [_openSubtitleFile setEnabled: b_enabled];
    if (b_enabled) {
        [_subtitle_bgopacityLabel_gray setHidden: YES];
        [_subtitle_bgopacityLabel setHidden: NO];
    } else {
        [_subtitle_bgopacityLabel_gray setHidden: NO];
        [_subtitle_bgopacityLabel setHidden: YES];
    }
    [_subtitle_bgopacity_sld setEnabled: b_enabled];
    [_teletext setEnabled: b_enabled];
}

- (void)setRateControlsEnabled:(BOOL)b_enabled
{
    [_rate_sld setEnabled: b_enabled];
    [_rate_sld setIntValue: [[VLCCoreInteraction sharedInstance] playbackRate]];
    int i = [[VLCCoreInteraction sharedInstance] playbackRate];
    double speed =  pow(2, (double)i / 17);
    [_rateTextField setStringValue: [NSString stringWithFormat:@"%.2fx", speed]];

    NSColor *color = b_enabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor];

    [_rateLabel setTextColor:color];
    [_rate_slowerLabel setTextColor:color];
    [_rate_normalLabel setTextColor:color];
    [_rate_fasterLabel setTextColor:color];
    [_rateTextField setTextColor:color];

    [self setSubtitleMenuEnabled: b_enabled];
}

#pragma mark - View

- (IBAction)toggleEffectsButton:(id)sender
{
    BOOL b_value = !var_InheritBool(getIntf(), "macosx-show-effects-button");
    config_PutInt(getIntf(), "macosx-show-effects-button", b_value);
    [(VLCMainWindowControlsBar *)[[[VLCMain sharedInstance] mainWindow] controlsBar] setupEffectsButton:YES];
    [_toggleEffectsButton setState: b_value];
}

- (IBAction)toggleJumpButtons:(id)sender
{
    BOOL b_value = !var_InheritBool(getIntf(), "macosx-show-playback-buttons");
    config_PutInt(getIntf(), "macosx-show-playback-buttons", b_value);

    [(VLCMainWindowControlsBar *)[[[VLCMain sharedInstance] mainWindow] controlsBar] setupJumpButtons:YES];
    [[[VLCMain sharedInstance] voutController] updateWindowsUsingBlock:^(VLCVideoWindowCommon *window) {
        [[window controlsBar] toggleForwardBackwardMode: b_value];
    }];

    [_toggleJumpButtons setState: b_value];
}

- (IBAction)togglePlaymodeButtons:(id)sender
{
    BOOL b_value = !var_InheritBool(getIntf(), "macosx-show-playmode-buttons");
    config_PutInt(getIntf(), "macosx-show-playmode-buttons", b_value);
    [(VLCMainWindowControlsBar *)[[[VLCMain sharedInstance] mainWindow] controlsBar] setupPlaymodeButtons:YES];
    [_togglePlaymodeButtons setState: b_value];
}

- (IBAction)toggleSidebar:(id)sender
{
    [[[VLCMain sharedInstance] mainWindow] toggleLeftSubSplitView];
}

- (void)updateSidebarMenuItem:(BOOL)show;
{
    [_toggleSidebar setState:show];
}

#pragma mark - Playback

- (IBAction)play:(id)sender
{
    [[VLCCoreInteraction sharedInstance] playOrPause];
}

- (IBAction)stop:(id)sender
{
    [[VLCCoreInteraction sharedInstance] stop];
}

- (IBAction)prev:(id)sender
{
    [[VLCCoreInteraction sharedInstance] previous];
}

- (IBAction)next:(id)sender
{
    [[VLCCoreInteraction sharedInstance] next];
}

- (IBAction)random:(id)sender
{
    [[VLCCoreInteraction sharedInstance] shuffle];
}

- (IBAction)repeat:(id)sender
{
    vlc_value_t val;
    intf_thread_t *p_intf = getIntf();
    playlist_t *p_playlist = pl_Get(p_intf);

    var_Get(p_playlist, "repeat", &val);
    if (! val.b_bool)
        [[VLCCoreInteraction sharedInstance] repeatOne];
    else
        [[VLCCoreInteraction sharedInstance] repeatOff];
}

- (IBAction)loop:(id)sender
{
    vlc_value_t val;
    intf_thread_t *p_intf = getIntf();
    playlist_t *p_playlist = pl_Get(p_intf);

    var_Get(p_playlist, "loop", &val);
    if (! val.b_bool)
        [[VLCCoreInteraction sharedInstance] repeatAll];
    else
        [[VLCCoreInteraction sharedInstance] repeatOff];
}

- (IBAction)forward:(id)sender
{
    [[VLCCoreInteraction sharedInstance] forward];
}

- (IBAction)backward:(id)sender
{
    [[VLCCoreInteraction sharedInstance] backward];
}

- (IBAction)volumeUp:(id)sender
{
    [[VLCCoreInteraction sharedInstance] volumeUp];
}

- (IBAction)volumeDown:(id)sender
{
    [[VLCCoreInteraction sharedInstance] volumeDown];
}

- (IBAction)mute:(id)sender
{
    [[VLCCoreInteraction sharedInstance] toggleMute];
}

- (void)lockVideosAspectRatio:(id)sender
{
    [[VLCCoreInteraction sharedInstance] setAspectRatioIsLocked: ![sender state]];
    [sender setState: [[VLCCoreInteraction sharedInstance] aspectRatioIsLocked]];
}

- (IBAction)quitAfterPlayback:(id)sender
{
    playlist_t *p_playlist = pl_Get(getIntf());
    bool b_value = !var_CreateGetBool(p_playlist, "play-and-exit");
    var_SetBool(p_playlist, "play-and-exit", b_value);
    config_PutInt(getIntf(), "play-and-exit", b_value);
}

- (IBAction)toggleRecord:(id)sender
{
    [[VLCCoreInteraction sharedInstance] toggleRecord];
}

- (IBAction)showDiscPopupMenu:(id)sender
{
    [[VLCCoreInteraction sharedInstance] showDiscPopupMenu];
}

- (void)updateRecordState:(BOOL)b_value
{
    [_record setState:b_value];
}

- (IBAction)toggleClipCreationMode:(id)sender
{
    [[VLCCoreInteraction sharedInstance] toggleClipCreationMode];
}

- (void)clipCreationModeChanged:(NSNotification *)aNotification
{
    if ([[VLCCoreInteraction sharedInstance] clipCreationMode])
        [_clipModeMenuItem setTitle:_NS("Exit Clip Creation Mode")];
    else
        [_clipModeMenuItem setTitle:_NS("Enter Clip Creation Mode")];
}

- (IBAction)setPlaybackRate:(id)sender
{
    [[VLCCoreInteraction sharedInstance] setPlaybackRate: [_rate_sld intValue]];
    int i = [[VLCCoreInteraction sharedInstance] playbackRate];
    double speed =  pow(2, (double)i / 17);
    [_rateTextField setStringValue: [NSString stringWithFormat:@"%.2fx", speed]];
}

- (void)updatePlaybackRate
{
    int i = [[VLCCoreInteraction sharedInstance] playbackRate];
    double speed =  pow(2, (double)i / 17);
    [_rateTextField setStringValue: [NSString stringWithFormat:@"%.2fx", speed]];
    [_rate_sld setIntValue: i];
}

- (IBAction)toggleAtoBloop:(id)sender
{
    [[VLCCoreInteraction sharedInstance] setAtoB];
}

- (IBAction)goToSpecificTime:(id)sender
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (p_input) {
        /* we can obviously only do that if an input is available */
        int64_t length = var_GetInteger(p_input, "length");
        [_timeSelectionPanel setMaxValue:(length / CLOCK_FREQ)];
        int64_t pos = var_GetInteger(p_input, "time");
        [_timeSelectionPanel setJumpTimeValue: (pos / CLOCK_FREQ)];
        [_timeSelectionPanel runModalForWindow:[NSApp mainWindow]
                             completionHandler:^(NSInteger returnCode, int64_t returnTime) {

            if (returnCode != NSOKButton)
                return;

            input_thread_t *p_input = pl_CurrentInput(getIntf());
            if (p_input) {
                input_Control(p_input, INPUT_SET_TIME, (int64_t)(returnTime *1000000));
                vlc_object_release(p_input);
            }
        }];

        vlc_object_release(p_input);
    }
}

- (IBAction)selectRenderer:(id)sender
{
    [_rendererMenuController selectRenderer:sender];
}

#pragma mark - audio menu

- (void)refreshAudioDeviceList
{
    char **ids, **names;
    char *currentDevice;

    [_audioDeviceMenu removeAllItems];

    audio_output_t *p_aout = getAout();
    if (!p_aout)
        return;

    int n = aout_DevicesList(p_aout, &ids, &names);
    if (n == -1) {
        vlc_object_release(p_aout);
        return;
    }

    currentDevice = aout_DeviceGet(p_aout);
    NSMenuItem *_tmp;

    for (NSUInteger x = 0; x < n; x++) {
        _tmp = [_audioDeviceMenu addItemWithTitle:toNSStr(names[x]) action:@selector(toggleAudioDevice:) keyEquivalent:@""];
        [_tmp setTarget:self];
        [_tmp setTag:[[NSString stringWithFormat:@"%s", ids[x]] intValue]];
    }
    vlc_object_release(p_aout);

    [[_audioDeviceMenu itemWithTag:[[NSString stringWithFormat:@"%s", currentDevice] intValue]] setState:NSOnState];

    free(currentDevice);

    for (NSUInteger x = 0; x < n; x++) {
        free(ids[x]);
        free(names[x]);
    }
    free(ids);
    free(names);

    [_audioDeviceMenu setAutoenablesItems:YES];
    [_audioDevice setEnabled:YES];
}

- (void)toggleAudioDevice:(id)sender
{
    audio_output_t *p_aout = getAout();
    if (!p_aout)
        return;

    int returnValue = 0;

    if ([sender tag] > 0)
        returnValue = aout_DeviceSet(p_aout, [[NSString stringWithFormat:@"%li", [sender tag]] UTF8String]);
    else
        returnValue = aout_DeviceSet(p_aout, NULL);

    if (returnValue != 0)
        msg_Warn(getIntf(), "failed to set audio device %li", [sender tag]);

    vlc_object_release(p_aout);
    [self refreshAudioDeviceList];
}

#pragma mark - video menu

- (IBAction)toggleFullscreen:(id)sender
{
    [[VLCCoreInteraction sharedInstance] toggleFullscreen];
}

- (IBAction)resizeVideoWindow:(id)sender
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (p_input) {
        vout_thread_t *p_vout = getVoutForActiveWindow();
        if (p_vout) {
            if (sender == _half_window)
                var_SetFloat(p_vout, "zoom", 0.5);
            else if (sender == _normal_window)
                var_SetFloat(p_vout, "zoom", 1.0);
            else if (sender == _double_window)
                var_SetFloat(p_vout, "zoom", 2.0);
            else
            {
                [[NSApp keyWindow] performZoom:sender];
            }
            vlc_object_release(p_vout);
        }
        vlc_object_release(p_input);
    }
}

- (IBAction)floatOnTop:(id)sender
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (p_input) {
        vout_thread_t *p_vout = getVoutForActiveWindow();
        if (p_vout) {
            BOOL b_fs = var_ToggleBool(p_vout, "video-on-top");
            var_SetBool(pl_Get(getIntf()), "video-on-top", b_fs);

            vlc_object_release(p_vout);
        }
        vlc_object_release(p_input);
    }
}

- (IBAction)toggleHideControlsPlayback:(id)sender
{
    VLCCoreInteraction *coreInteraction = [VLCCoreInteraction sharedInstance];
    [coreInteraction setAutoHideControls:![coreInteraction autoHideControls]];
}

- (IBAction)createVideoSnapshot:(id)sender
{
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (p_input) {
        vout_thread_t *p_vout = getVoutForActiveWindow();
        if (p_vout) {
            var_TriggerCallback(p_vout, "video-snapshot");
            vlc_object_release(p_vout);
        }
        vlc_object_release(p_input);
    }
}

- (void)_disablePostProcessing
{
    [[VLCCoreInteraction sharedInstance] setVideoFilter:"postproc" on:false];
}

- (void)_enablePostProcessing
{
    [[VLCCoreInteraction sharedInstance] setVideoFilter:"postproc" on:true];
}

- (void)togglePostProcessing:(id)sender
{
    char *psz_name = "postproc";
    NSInteger count = [_postprocessingMenu numberOfItems];
    for (NSUInteger x = 0; x < count; x++)
        [[_postprocessingMenu itemAtIndex:x] setState:NSOffState];

    if ([sender tag] == -1) {
        [self _disablePostProcessing];
        [sender setState:NSOnState];
    } else {
        [self _enablePostProcessing];
        [sender setState:NSOnState];

        [[VLCCoreInteraction sharedInstance] setVideoFilterProperty:"postproc-q" forFilter:"postproc" withValue:(vlc_value_t){ .i_int = [sender tag] }];
    }
}

- (void)toggleFullscreenDevice:(id)sender
{
    config_PutInt(getIntf(), "macosx-vdev", [sender tag]);
    [self refreshVoutDeviceMenu: nil];
}

#pragma mark - Subtitles Menu

- (IBAction)addSubtitleFile:(id)sender
{
    NSInteger i_returnValue = 0;
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (!p_input)
        return;

    input_item_t *p_item = input_GetItem(p_input);
    if (!p_item) {
        vlc_object_release(p_input);
        return;
    }

    char *path = input_item_GetURI(p_item);

    if (!path)
        path = strdup("");

    NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setCanChooseFiles: YES];
    [openPanel setCanChooseDirectories: NO];
    [openPanel setAllowsMultipleSelection: YES];

    [openPanel setAllowedFileTypes: [NSArray arrayWithObjects:@"cdg",@"idx",@"srt",@"sub",@"utf",@"ass",@"ssa",@"aqt",@"jss",@"psb",@"rt",@"smi",@"txt",@"smil",@"stl",@"usf",@"dks",@"pjs",@"mpl2",@"mks",@"vtt",@"ttml",@"dfxp",nil]];

    NSURL *url = [NSURL URLWithString:[toNSStr(path) stringByExpandingTildeInPath]];
    url = [url URLByDeletingLastPathComponent];
    [openPanel setDirectoryURL: url];
    free(path);
    vlc_object_release(p_input);

    i_returnValue = [openPanel runModal];

    if (i_returnValue == NSOKButton)
        [[VLCCoreInteraction sharedInstance] addSubtitlesToCurrentInput:[openPanel URLs]];
}

- (void)switchSubtitleSize:(id)sender
{
    int intValue = [sender tag];
    var_SetInteger(pl_Get(getIntf()), "sub-text-scale", intValue);

    for (NSMenuItem *item in [[sender menu] itemArray])
        [item setState:item == sender ? NSOnState : NSOffState];
}


- (void)switchSubtitleOption:(id)sender
{
    int intValue = [sender tag];
    NSString *representedObject = [sender representedObject];

    var_SetInteger(pl_Get(getIntf()), [representedObject UTF8String], intValue);

    NSMenu *menu = [sender menu];
    NSUInteger count = (NSUInteger) [menu numberOfItems];
    for (NSUInteger x = 0; x < count; x++)
        [[menu itemAtIndex:x] setState:NSOffState];
    [[menu itemWithTag:intValue] setState:NSOnState];
}

- (IBAction)switchSubtitleBackgroundOpacity:(id)sender
{
    var_SetInteger(pl_Get(getIntf()), "freetype-background-opacity", [sender intValue]);
}

- (IBAction)telxTransparent:(id)sender
{
    vlc_object_t *p_vbi;
    p_vbi = (vlc_object_t *) vlc_object_find_name(pl_Get(getIntf()), "zvbi");
    if (p_vbi) {
        var_SetBool(p_vbi, "vbi-opaque", [sender state]);
        [sender setState: ![sender state]];
        vlc_object_release(p_vbi);
    }
}

- (IBAction)telxNavLink:(id)sender
{
    vlc_object_t *p_vbi;
    int i_page = 0;

    if ([[sender title] isEqualToString: _NS("Index")])
        i_page = 'i' << 16;
    else if ([[sender title] isEqualToString: _NS("Red")])
        i_page = 'r' << 16;
    else if ([[sender title] isEqualToString: _NS("Green")])
        i_page = 'g' << 16;
    else if ([[sender title] isEqualToString: _NS("Yellow")])
        i_page = 'y' << 16;
    else if ([[sender title] isEqualToString: _NS("Blue")])
        i_page = 'b' << 16;
    if (i_page == 0) return;

    p_vbi = (vlc_object_t *) vlc_object_find_name(pl_Get(getIntf()), "zvbi");
    if (p_vbi) {
        var_SetInteger(p_vbi, "vbi-page", i_page);
        vlc_object_release(p_vbi);
    }
}

#pragma mark - Panels

- (IBAction)intfOpenFile:(id)sender
{
    [[[VLCMain sharedInstance] open] openFileWithAction:^(NSArray *files) {
        [[[VLCMain sharedInstance] playlist] addPlaylistItems:files];
    }];
}

- (IBAction)intfOpenFileGeneric:(id)sender
{
    [[[VLCMain sharedInstance] open] openFileGeneric];
}

- (IBAction)intfOpenDisc:(id)sender
{
    [[[VLCMain sharedInstance] open] openDisc];
}

- (IBAction)intfOpenNet:(id)sender
{
    [[[VLCMain sharedInstance] open] openNet];
}

- (IBAction)intfOpenCapture:(id)sender
{
    [[[VLCMain sharedInstance] open] openCapture];
}

- (IBAction)savePlaylist:(id)sender
{
    playlist_t *p_playlist = pl_Get(getIntf());

    NSSavePanel *savePanel = [NSSavePanel savePanel];
    NSString * name = [NSString stringWithFormat: @"%@", _NS("Untitled")];

    [NSBundle loadNibNamed:@"PlaylistAccessoryView" owner:self];

    [_playlistSaveAccessoryText setStringValue: _NS("File Format:")];
    [[_playlistSaveAccessoryPopup itemAtIndex:0] setTitle: _NS("Extended M3U")];
    [[_playlistSaveAccessoryPopup itemAtIndex:1] setTitle: _NS("XML Shareable Playlist Format (XSPF)")];
    [[_playlistSaveAccessoryPopup itemAtIndex:2] setTitle: _NS("HTML playlist")];

    [savePanel setTitle: _NS("Save Playlist")];
    [savePanel setPrompt: _NS("Save")];
    [savePanel setAccessoryView: _playlistSaveAccessoryView];
    [savePanel setNameFieldStringValue: name];

    if ([savePanel runModal] == NSFileHandlingPanelOKButton) {
        NSString *filename = [[savePanel URL] path];

        if ([_playlistSaveAccessoryPopup indexOfSelectedItem] == 0) {
            NSString *actualFilename;
            NSRange range;
            range.location = [filename length] - [@".m3u" length];
            range.length = [@".m3u" length];

            if ([filename compare:@".m3u" options: NSCaseInsensitiveSearch range: range] != NSOrderedSame)
                actualFilename = [NSString stringWithFormat: @"%@.m3u", filename];
            else
                actualFilename = filename;

            playlist_Export(p_playlist,
                            [actualFilename fileSystemRepresentation],
                            true, "export-m3u");
        } else if ([_playlistSaveAccessoryPopup indexOfSelectedItem] == 1) {
            NSString *actualFilename;
            NSRange range;
            range.location = [filename length] - [@".xspf" length];
            range.length = [@".xspf" length];

            if ([filename compare:@".xspf" options: NSCaseInsensitiveSearch range: range] != NSOrderedSame)
                actualFilename = [NSString stringWithFormat: @"%@.xspf", filename];
            else
                actualFilename = filename;

            playlist_Export(p_playlist,
                            [actualFilename fileSystemRepresentation],
                            true, "export-xspf");
        } else {
            NSString *actualFilename;
            NSRange range;
            range.location = [filename length] - [@".html" length];
            range.length = [@".html" length];

            if ([filename compare:@".html" options: NSCaseInsensitiveSearch range: range] != NSOrderedSame)
                actualFilename = [NSString stringWithFormat: @"%@.html", filename];
            else
                actualFilename = filename;

            playlist_Export(p_playlist,
                            [actualFilename fileSystemRepresentation],
                            true, "export-html");
        }
    }
}

- (IBAction)showConvertAndSave:(id)sender
{
    [[[VLCMain sharedInstance] convertAndSaveWindow] showWindow:self];
}

- (IBAction)showVideoEffects:(id)sender
{
    [[[VLCMain sharedInstance] videoEffectsPanel] toggleWindow:sender];
}

- (IBAction)showTrackSynchronization:(id)sender
{
    [[[VLCMain sharedInstance] trackSyncPanel] toggleWindow:sender];
}

- (IBAction)showAudioEffects:(id)sender
{
    [[[VLCMain sharedInstance] audioEffectsPanel] toggleWindow:sender];
}

- (IBAction)showBookmarks:(id)sender
{
    [[[VLCMain sharedInstance] bookmarks] toggleWindow:sender];
}

- (IBAction)showPreferences:(id)sender
{
    NSInteger i_level = [[[VLCMain sharedInstance] voutController] currentStatusWindowLevel];
    [[[VLCMain sharedInstance] simplePreferences] showSimplePrefsWithLevel:i_level];
}

- (IBAction)openAddonManager:(id)sender
{
    if (!_addonsController)
        _addonsController = [[VLCAddonsWindowController alloc] init];

    [_addonsController showWindow:self];
}

- (IBAction)switchToLegacyInterface:(id)sender
{
    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:_NS("Change the interface?")];
    [alert setInformativeText:_NS("VLC needs to restart to switch interfaces. "
                                  "Do you want to continue?")];
    [alert addButtonWithTitle:_NS("Yes")];
    [alert addButtonWithTitle:_NS("No")];
    if ([alert runModal] != NSAlertFirstButtonReturn)
        return;

    intf_thread_t *p_intf = getIntf();
    config_PutPsz(p_intf, "intf", "legacy_macosx");
    config_SaveConfigFile(p_intf);

    /* detached relaunch; the bundle path travels as $0, immune to quoting */
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath:@"/bin/sh"];
    [task setArguments:@[@"-c", @"sleep 1; exec /usr/bin/open -n \"$0\"",
                         [[NSBundle mainBundle] bundlePath]]];
    @try {
        [task launch];
    } @catch (NSException *exception) {
    }
    [NSApp terminate:nil];
}

- (IBAction)showErrorsAndWarnings:(id)sender
{
    [[[[VLCMain sharedInstance] coreDialogProvider] errorPanel] showWindow:self];
}

- (IBAction)showMessagesPanel:(id)showMessagesPanel
{
    [[[VLCMain sharedInstance] debugMsgPanel] showWindow:self];
}

- (IBAction)showMainWindow:(id)sender
{
    [[[VLCMain sharedInstance] mainWindow] makeKeyAndOrderFront:sender];
}

- (IBAction)showPlaylist:(id)sender
{
    [[[VLCMain sharedInstance] mainWindow] changePlaylistState: psUserMenuEvent];
}

#pragma mark - Help and Docs

- (IBAction)showAbout:(id)sender
{
    if (!_aboutWindowController)
        _aboutWindowController = [[VLCAboutWindowController alloc] init];

    [_aboutWindowController showAbout];
}

- (IBAction)showLicense:(id)sender
{
    if (!_aboutWindowController)
        _aboutWindowController = [[VLCAboutWindowController alloc] init];

    [_aboutWindowController showGPL];
}

- (IBAction)showHelp:(id)sender
{
    if (!_helpWindowController)
        _helpWindowController = [[VLCHelpWindowController alloc] init];

    [_helpWindowController showHelp];
}

- (IBAction)openDocumentation:(id)sender
{
    NSURL *url = [NSURL URLWithString: @"https://www.videolan.org/doc/"];

    [VLCMain openURLWithVideoLANConfirmation: url];
}

- (IBAction)openWebsite:(id)sender
{
    NSURL *url = [NSURL URLWithString: @"https://www.videolan.org/"];

    [VLCMain openURLWithVideoLANConfirmation: url];
}

- (IBAction)openForum:(id)sender
{
    NSURL *url = [NSURL URLWithString: @"https://forum.videolan.org/"];

    [VLCMain openURLWithVideoLANConfirmation: url];
}

- (IBAction)openDonate:(id)sender
{
    NSURL *url = [NSURL URLWithString: @"https://www.videolan.org/contribute.html#paypal"];

    [VLCMain openURLWithVideoLANConfirmation: url];
}

/* Reveals <config home>/<lib> in the Finder, creating it first: the folder
 * does not exist until something writes there, and an "open" that silently did
 * nothing would look like a broken menu item. config_GetDiscLibDir() is what
 * the key database importer uses too, so the two can never disagree. */
- (void)openDiscLibFolder:(const char *)psz_lib
{
    char *psz_dir = config_GetDiscLibDir(psz_lib);
    NSString *path = psz_dir ? toNSStr(psz_dir) : nil;

    if (path != nil
     && [[NSFileManager defaultManager] createDirectoryAtPath:path
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil]
     && [[NSWorkspace sharedWorkspace] openFile:path]) {
        free(psz_dir);
        return;
    }

    msg_Err(getIntf(), "cannot open the %s folder", psz_lib);

    /* The "%s" is substituted by hand rather than through -stringWithFormat:,
     * whose %s decodes the bytes in the *system* encoding rather than UTF-8,
     * and this is a path. The msgid keeps VLC's "%s" so that the three
     * interfaces share a single string to translate. */
    NSMutableString *msg = [NSMutableString stringWithString:
        _NS("The folder %s could not be opened.")];
    [msg replaceOccurrencesOfString:@"%s"
                         withString:(path != nil ? path : toNSStr(psz_lib))
                            options:0
                              range:NSMakeRange(0, [msg length])];

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:_NS("Error")];
    [alert setInformativeText:msg];
    [alert addButtonWithTitle:_NS("OK")];
    [alert runModal];

    free(psz_dir);
}

- (IBAction)openAACSFolder:(id)sender
{
    [self openDiscLibFolder:"aacs"];
}

/* Handing the file to the browser is the whole of it: the browser then shows
 * its own install prompt, which is where this belongs -- the player has no
 * business installing anything inside somebody's browser. */
- (IBAction)installBrowserAddon:(id)sender
{
    if (VLCBrowserAddonInstall())
        return;

    NSAlert *alert = [[NSAlert alloc] init];
    [alert setMessageText:_NS("Error")];
    [alert setInformativeText:_NS("PowerVLC could not open the add-on with "
                                  "your browser. Drag share/powervlc.xpi "
                                  "from the application onto a browser "
                                  "window to install it.")];
    [alert addButtonWithTitle:_NS("OK")];
    [alert runModal];
}

- (IBAction)reloadCrystalHDDriver:(id)sender
{
    VLCCrystalHDRunReloadFlow();
}

/* The menu is built once at startup, so flip the item over itself rather than
 * leaving it offering to install a driver that is now installed. */
- (IBAction)installCrystalHDDriver:(id)sender
{
    if (!VLCCrystalHDRunInstallFlow(NO))
        return;

    if ([sender isKindOfClass:[NSMenuItem class]]) {
        [sender setTitle:_NS("Remove the Crystal HD driver...")];
        [sender setAction:@selector(uninstallCrystalHDDriver:)];
    }
}

- (IBAction)uninstallCrystalHDDriver:(id)sender
{
    if (!VLCCrystalHDRunUninstallFlow())
        return;

    if (![sender isKindOfClass:[NSMenuItem class]])
        return;

    /* Without a card there is nothing left to offer, so retire the item
     * instead of inviting a pointless reinstall. */
    if (VLCCrystalHDGetState() == VLCCrystalHDCardWithoutDriver) {
        [sender setTitle:_NS("Install the Crystal HD driver...")];
        [sender setAction:@selector(installCrystalHDDriver:)];
    } else {
        [sender setEnabled:NO];
    }
}

- (IBAction)openBDPlusFolder:(id)sender
{
    [self openDiscLibFolder:"bdplus"];
}

- (IBAction)showInformationPanel:(id)sender
{
    [[[VLCMain sharedInstance] currentMediaInfoPanel] toggleWindow:sender];
}

#pragma mark - convinience stuff for other objects

- (void)setPlay
{
    [_play setTitle: _NS("Play")];
    [_dockMenuplay setTitle: _NS("Play")];
    [_voutMenuplay setTitle: _NS("Play")];
}

- (void)setPause
{
    [_play setTitle: _NS("Pause")];
    [_dockMenuplay setTitle: _NS("Pause")];
    [_voutMenuplay setTitle: _NS("Pause")];
}

- (void)setRepeatOne
{
    [_repeat setState: NSOnState];
    [_loop setState: NSOffState];
}

- (void)setRepeatAll
{
    [_repeat setState: NSOffState];
    [_loop setState: NSOnState];
}

- (void)setRepeatOff
{
    [_repeat setState: NSOffState];
    [_loop setState: NSOffState];
}

- (void)setShuffle
{
    bool b_value;
    playlist_t *p_playlist = pl_Get(getIntf());
    b_value = var_GetBool(p_playlist, "random");

    [_random setState: b_value];
}

#pragma mark - Dynamic menu creation and validation

#pragma mark - custom crop and aspect ratio

/* setupVarMenu rebuilds the submenu from the variable's choices every time
 * the menu opens, so the entry has to be put back after it. Same shape as
 * VLC 4.0's -appendCustomizationItem:. */
- (void)appendCustomizationItemTo:(NSMenuItem *)menuItem action:(SEL)action
{
    NSMenu *submenu = [menuItem submenu];
    if (submenu == nil)
        return;

    if ([submenu numberOfItems] > 0)
        [submenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *customItem = [submenu addItemWithTitle:_NS("Custom")
                                                action:action
                                         keyEquivalent:@""];
    [customItem setTarget:self];
    [customItem setEnabled:YES];
    /* setupVarMenu greys the parent out when the variable offers one choice
     * or none; this entry always works, so it must not stay unreachable. */
    [menuItem setEnabled:YES];
}

/* Offers the ratio in the menu from now on, and keeps it for the next vout
 * and the next run -- "custom-crop-ratios" / "custom-aspect-ratios" is
 * exactly what vout_IntfInit reads back to fill the menu. */
- (void)rememberCustomRatio:(NSString *)ratio
                   variable:(const char *)psz_var
                     config:(const char *)psz_config
                     onVout:(vout_thread_t *)p_vout
{
    const char *psz_value = [ratio UTF8String];

    vlc_value_t val_list, text_list;
    if (var_Change(VLC_OBJECT(p_vout), psz_var, VLC_VAR_GETCHOICES,
                   &val_list, &text_list) == VLC_SUCCESS) {
        bool known = false;
        for (int i = 0; i < val_list.p_list->i_count; i++) {
            const char *psz_choice = val_list.p_list->p_values[i].psz_string;
            if (psz_choice != NULL && !strcmp(psz_choice, psz_value)) {
                known = true;
                break;
            }
        }
        var_FreeList(&val_list, &text_list);
        if (known)
            return;
    }

    vlc_value_t val, text;
    val.psz_string = (char *)psz_value;
    text.psz_string = (char *)psz_value;
    var_Change(VLC_OBJECT(p_vout), psz_var, VLC_VAR_ADDCHOICE, &val, &text);

    intf_thread_t *p_intf = getIntf();
    char *psz_list = config_GetPsz(p_intf, psz_config);
    NSMutableArray *ratios = [NSMutableArray array];
    if (psz_list != NULL) {
        for (NSString *entry in [toNSStr(psz_list) componentsSeparatedByString:@","]) {
            if ([entry length] > 0)
                [ratios addObject:entry];
        }
        free(psz_list);
    }
    if (![ratios containsObject:ratio])
        [ratios addObject:ratio];

    config_PutPsz(p_intf, psz_config,
                  [[ratios componentsJoinedByString:@","] UTF8String]);
    config_SaveConfigFile(p_intf);
}

- (void)performCustomRatioForVariable:(const char *)psz_var
                               config:(const char *)psz_config
                                title:(NSString *)title
{
    vout_thread_t *p_vout = getVoutForActiveWindow();
    if (p_vout == NULL)
        return;

    char *psz_current = var_GetString(p_vout, psz_var);
    NSString *ratio =
        [VLCCustomCropArWindowController runModalWithTitle:title
                                              currentRatio:toNSStr(psz_current)];
    free(psz_current);

    if (ratio != nil) {
        [self rememberCustomRatio:ratio variable:psz_var config:psz_config
                           onVout:p_vout];
        var_SetString(p_vout, psz_var, [ratio UTF8String]);
    }
    vlc_object_release(p_vout);
}

- (void)performCustomAspectRatio:(id)sender
{
    [self performCustomRatioForVariable:"aspect-ratio"
                                 config:"custom-aspect-ratios"
                                  title:_NS("Aspect ratio")];
}

- (void)performCustomCrop:(id)sender
{
    [self performCustomRatioForVariable:"crop"
                                 config:"custom-crop-ratios"
                                  title:_NS("Crop")];
}

- (void)setupVarMenuItem:(NSMenuItem *)mi
                  target:(vlc_object_t *)p_object
                     var:(const char *)psz_variable
                selector:(SEL)pf_callback
{
    vlc_value_t val, text;
    int i_type = var_Type(p_object, psz_variable);

    switch(i_type & VLC_VAR_TYPE) {
        case VLC_VAR_VOID:
        case VLC_VAR_BOOL:
        case VLC_VAR_STRING:
        case VLC_VAR_INTEGER:
            break;
        default:
            /* Variable doesn't exist or isn't handled */
            msg_Warn(p_object, "variable %s doesn't exist or isn't handled", psz_variable);
            return;
    }

    /* Get the descriptive name of the variable */
    var_Change(p_object, psz_variable, VLC_VAR_GETTEXT, &text, NULL);
    [mi setTitle: _NS(text.psz_string ? text.psz_string : psz_variable)];

    if (i_type & VLC_VAR_HASCHOICE) {
        NSMenu *menu = [mi submenu];

        [self setupVarMenu:menu forMenuItem:mi target:p_object
                       var:psz_variable selector:pf_callback];

        free(text.psz_string);
        return;
    }

    if (var_Get(p_object, psz_variable, &val) < 0)
        return;

    VLCAutoGeneratedMenuContent *data;
    switch(i_type & VLC_VAR_TYPE) {
        case VLC_VAR_VOID:
            data = [[VLCAutoGeneratedMenuContent alloc] initWithVariableName: psz_variable ofObject: p_object
                                                                      andValue: val ofType: i_type];
            [mi setRepresentedObject:data];
            break;

        case VLC_VAR_BOOL:
            data = [[VLCAutoGeneratedMenuContent alloc] initWithVariableName: psz_variable ofObject: p_object
                                                                      andValue: val ofType: i_type];
            [mi setRepresentedObject:data];
            if (!(i_type & VLC_VAR_ISCOMMAND))
                [mi setState: val.b_bool ? TRUE : FALSE ];
            break;

        default:
            break;
    }

    if ((i_type & VLC_VAR_TYPE) == VLC_VAR_STRING) free(val.psz_string);
    free(text.psz_string);
}


- (void)setupVarMenu:(NSMenu *)menu
         forMenuItem: (NSMenuItem *)parent
              target:(vlc_object_t *)p_object
                 var:(const char *)psz_variable
            selector:(SEL)pf_callback
{
    vlc_value_t val, val_list, text_list;
    int i_type, i;

    /* remove previous items */
    [menu removeAllItems];

    /* we disable everything here, and enable it again when needed, below */
    [parent setEnabled:NO];

    /* Aspect Ratio */
    if ([[parent title] isEqualToString: _NS("Aspect ratio")] == YES) {
        NSMenuItem *lmi_tmp2;
        lmi_tmp2 = [menu addItemWithTitle: _NS("Lock Aspect Ratio") action: @selector(lockVideosAspectRatio:) keyEquivalent: @""];
        [lmi_tmp2 setTarget: self];
        [lmi_tmp2 setEnabled: YES];
        [lmi_tmp2 setState: [[VLCCoreInteraction sharedInstance] aspectRatioIsLocked]];
        [parent setEnabled: YES];
        [menu addItem: [NSMenuItem separatorItem]];
    }

    /* Check the type of the object variable */
    i_type = var_Type(p_object, psz_variable);

    /* Make sure we want to display the variable */
    if (i_type & VLC_VAR_HASCHOICE) {
        var_Change(p_object, psz_variable, VLC_VAR_CHOICESCOUNT, &val, NULL);
        if (val.i_int == 0 || val.i_int == 1)
            return;
    }
    else
        return;

    switch(i_type & VLC_VAR_TYPE) {
        case VLC_VAR_VOID:
        case VLC_VAR_BOOL:
        case VLC_VAR_STRING:
        case VLC_VAR_INTEGER:
            break;
        default:
            /* Variable doesn't exist or isn't handled */
            return;
    }

    if (var_Get(p_object, psz_variable, &val) < 0) {
        return;
    }

    if (var_Change(p_object, psz_variable, VLC_VAR_GETCHOICES,
                   &val_list, &text_list) < 0) {
        if ((i_type & VLC_VAR_TYPE) == VLC_VAR_STRING) free(val.psz_string);
        return;
    }

    /* make (un)sensitive */
    [parent setEnabled: (val_list.p_list->i_count > 1)];

    BOOL markCurrentChoice =
        VLCVariableMenuShowsCurrentChoice(psz_variable, i_type);

    for (i = 0; i < val_list.p_list->i_count; i++) {
        NSMenuItem *lmi;
        NSString *title = @"";
        VLCAutoGeneratedMenuContent *data;

        switch(i_type & VLC_VAR_TYPE) {
            case VLC_VAR_STRING:

                title = _NS(text_list.p_list->p_values[i].psz_string ? text_list.p_list->p_values[i].psz_string : val_list.p_list->p_values[i].psz_string);

                lmi = [menu addItemWithTitle: title action: pf_callback keyEquivalent: @""];
                data = [[VLCAutoGeneratedMenuContent alloc] initWithVariableName: psz_variable ofObject: p_object
                                                                          andValue: val_list.p_list->p_values[i] ofType: i_type];
                [lmi setRepresentedObject:data];
                [lmi setTarget: self];

                if (markCurrentChoice
                 && !strcmp(val.psz_string,
                            val_list.p_list->p_values[i].psz_string))
                    [lmi setState: TRUE ];

                break;

            case VLC_VAR_INTEGER:

                title = text_list.p_list->p_values[i].psz_string ?
                _NS(text_list.p_list->p_values[i].psz_string) : [NSString stringWithFormat: @"%"PRId64, val_list.p_list->p_values[i].i_int];

                lmi = [menu addItemWithTitle: title action: pf_callback keyEquivalent: @""];
                data = [[VLCAutoGeneratedMenuContent alloc] initWithVariableName: psz_variable ofObject: p_object
                                                                          andValue: val_list.p_list->p_values[i] ofType: i_type];
                [lmi setRepresentedObject:data];
                [lmi setTarget: self];

                if (markCurrentChoice
                 && val_list.p_list->p_values[i].i_int == val.i_int)
                    [lmi setState: TRUE ];
                break;

            default:
                break;
        }
    }

    /* clean up everything */
    if ((i_type & VLC_VAR_TYPE) == VLC_VAR_STRING) free(val.psz_string);
    var_FreeList(&val_list, &text_list);
}

- (void)toggleVar:(id)sender
{
    NSMenuItem *mi = (NSMenuItem *)sender;
    VLCAutoGeneratedMenuContent *data = [mi representedObject];

    /* Rebuilding from the core value keeps every menu correct when it opens,
     * but the value is applied on a detached thread. Reflect a stateful choice
     * immediately as well, so quality, tracks, crop, aspect ratio and the
     * other selectors do not keep showing the previous check mark meanwhile. */
    if (([data type] & VLC_VAR_HASCHOICE)
     && VLCVariableMenuShowsCurrentChoice([data name], [data type])) {
        for (NSMenuItem *item in [[mi menu] itemArray]) {
            id siblingData = [item representedObject];
            if (![siblingData isKindOfClass:[VLCAutoGeneratedMenuContent class]])
                continue;
            VLCAutoGeneratedMenuContent *siblingContent = siblingData;
            if (!strcmp([siblingContent name], [data name]))
                [item setState:NSOffState];
        }
        [mi setState:NSOnState];
    }

    [NSThread detachNewThreadSelector: @selector(toggleVarThread:)
                             toTarget: self withObject: data];

    return;
}

- (int)toggleVarThread: (id)data
{
    @autoreleasepool {
        vlc_object_t *p_object;

        assert([data isKindOfClass:[VLCAutoGeneratedMenuContent class]]);
        VLCAutoGeneratedMenuContent *menuContent = (VLCAutoGeneratedMenuContent *)data;

        p_object = [menuContent vlcObject];

        if (p_object != NULL) {
            var_Set(p_object, [menuContent name], [menuContent value]);
            vlc_object_release(p_object);
            return true;
        }
        return VLC_EGENERIC;
    }
}

#pragma mark - menu delegation

- (void)rebuildRecentStreamsMenu
{
    [_recentStreamsMenu removeAllItems];
    NSArray *streams = [[NSUserDefaults standardUserDefaults]
        stringArrayForKey:VLC_RECENT_STREAMS_KEY];

    NSUInteger count = [streams count];
    for (NSUInteger i = 0; i < count; i++) {
        NSString *mrl = [streams objectAtIndex:i];
        NSString *safeMRL = VLCMRLWithoutPassword(mrl);
        char *decoded = vlc_uri_decode_duplicate([safeMRL UTF8String]);
        NSString *title = decoded ? toNSStr(decoded) : safeMRL;
        free(decoded);

        NSMenuItem *item = [[NSMenuItem alloc]
            initWithTitle:title
                   action:@selector(openRecentStream:)
            keyEquivalent:@""];
        [item setTarget:self];
        [item setRepresentedObject:mrl];
        [item setToolTip:safeMRL];
        [_recentStreamsMenu addItem:item];
    }

    if (count)
        [_recentStreamsMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *clearItem = [[NSMenuItem alloc]
        initWithTitle:_NS("Clear")
               action:@selector(clearRecentStreams:)
        keyEquivalent:@""];
    [clearItem setTarget:self];
    [clearItem setEnabled:count > 0];
    [_recentStreamsMenu addItem:clearItem];
    /* Keep the parent enabled so a stream opened after application startup
     * is immediately visible without rebuilding the whole menu bar. */
    [_recentStreamsMenuItem setEnabled:YES];
}

- (void)openRecentStream:(id)sender
{
    NSString *mrl = [sender representedObject];
    if (![mrl length])
        return;
    NSArray *serverRecents = [[NSUserDefaults standardUserDefaults]
        stringArrayForKey:VLCConnectToServerRecentsKey];
    if ([serverRecents containsObject:mrl]) {
        if ([[[[VLCMain sharedInstance] mainWindow] sidebarDataSource]
                addNetworkLocation:mrl])
            VLCNoteRecentStream(mrl);
    } else if (playlist_Add(pl_Get(getIntf()), [mrl UTF8String], true)
               == VLC_SUCCESS) {
        VLCNoteRecentStream(mrl);
    }
}

- (void)clearRecentStreams:(id)sender
{
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:VLC_RECENT_STREAMS_KEY];
    [self rebuildRecentStreamsMenu];
}

- (void)connectToServer:(id)sender
{
    VLCConnectToServerDialog *dialog = [[VLCConnectToServerDialog alloc] init];
    [dialog show];
}

- (void)menuWillOpen:(NSMenu *)menu
{
    if (menu == _recentStreamsMenu) {
        [self rebuildRecentStreamsMenu];
        return;
    }
    [_cancelRendererDiscoveryTimer invalidate];
    [_rendererMenuController startRendererDiscoveries];
}

- (void)menuDidClose:(NSMenu *)menu
{
    if (menu == _recentStreamsMenu)
        return;
    _cancelRendererDiscoveryTimer = [NSTimer scheduledTimerWithTimeInterval:20.
                                                                     target:self
                                                                   selector:@selector(cancelRendererDiscovery)
                                                                   userInfo:nil
                                                                    repeats:NO];
}

- (void)cancelRendererDiscovery
{
    [_rendererMenuController stopRendererDiscoveries];
}

@end

@implementation VLCMainMenu (NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)mi
{
    NSString *title = [mi title];
    BOOL enabled = YES;
    vlc_value_t val;
    playlist_t *p_playlist = pl_Get(getIntf());
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);

    if (mi == _stop || mi == _voutMenustop || mi == _dockMenustop) {
        if (!p_input)
            enabled = NO;
        [self setupMenus]; /* Make sure input menu is up to date */
    } else if (mi == _previous          ||
               mi == _voutMenuprev      ||
               mi == _dockMenuprevious  ||
               mi == _next              ||
               mi == _voutMenunext      ||
               mi == _dockMenunext
               ) {
        PL_LOCK;
        enabled = playlist_CurrentSize(p_playlist) > 1;
        PL_UNLOCK;
    } else if (mi == _record) {
        enabled = NO;
        if (p_input)
            enabled = var_GetBool(p_input, "can-record");
    } else if (mi == _clipModeMenuItem) {
        /* defining bounds needs seeking, saving the clip needs recording */
        enabled = NO;
        if (p_input)
            enabled = var_GetBool(p_input, "can-seek")
                   && var_GetBool(p_input, "can-record");
    } else if (mi == _random) {
        int i_state;
        var_Get(p_playlist, "random", &val);
        i_state = val.b_bool ? NSOnState : NSOffState;
        [mi setState: i_state];
    } else if (mi == _repeat) {
        int i_state;
        var_Get(p_playlist, "repeat", &val);
        i_state = val.b_bool ? NSOnState : NSOffState;
        [mi setState: i_state];
    } else if (mi == _loop) {
        int i_state;
        var_Get(p_playlist, "loop", &val);
        i_state = val.b_bool ? NSOnState : NSOffState;
        [mi setState: i_state];
    } else if (mi == _quitAfterPB) {
        int i_state;
        bool b_value = var_InheritBool(p_playlist, "play-and-exit");
        i_state = b_value ? NSOnState : NSOffState;
        [mi setState: i_state];
    } else if (mi == _fwd || mi == _bwd || mi == _jumpToTime) {
        if (p_input != NULL) {
            var_Get(p_input, "can-seek", &val);
            enabled = val.b_bool;
        } else {
            enabled = NO;
        }
    } else if (mi == _mute || mi == _dockMenumute || mi == _voutMenumute) {
        [mi setState: [[VLCCoreInteraction sharedInstance] mute] ? NSOnState : NSOffState];
        [self setupMenus]; /* Make sure audio menu is up to date */
        [self refreshAudioDeviceList];
    } else if (mi == _hideControlsMenuItem) {
        [mi setState: [[VLCCoreInteraction sharedInstance] autoHideControls]
                          ? NSOnState : NSOffState];
    } else if (mi == _half_window           ||
               mi == _normal_window         ||
               mi == _double_window         ||
               mi == _fittoscreen           ||
               mi == _snapshot              ||
               mi == _voutMenusnapshot      ||
               mi == _fullscreenItem        ||
               mi == _voutMenufullscreen    ||
               mi == _floatontop
               ) {
        enabled = NO;

        if (p_input != NULL) {
            vout_thread_t *p_vout = getVoutForActiveWindow();
            if (p_vout != NULL) {
                if (mi == _floatontop)
                    [mi setState: var_GetBool(p_vout, "video-on-top")];

                if (mi == _fullscreenItem || mi == _voutMenufullscreen)
                    [mi setState: var_GetBool(p_vout, "fullscreen")];

                enabled = YES;
                vlc_object_release(p_vout);
            }
        }

        [self setupMenus]; /* Make sure video menu is up to date */

    } else if (mi == _openSubtitleFile) {
        enabled = [mi isEnabled];
        [self setupMenus]; /* Make sure subtitles menu is up to date */
    } else if (mi == _discPopupMenuItem || mi == _voutDiscPopupMenuItem) {
        /* only the Blu-ray titles that carry a pop-up menu offer one */
        enabled = [[VLCCoreInteraction sharedInstance] hasDiscPopupMenu];
    } else if ([mi action] == @selector(switchSubtitleSize:)) {
        [mi setState:
            var_GetInteger(p_playlist, "sub-text-scale") == [mi tag]
                ? NSOnState : NSOffState];
        enabled = _openSubtitleFile.isEnabled;
    } else {
        NSMenuItem *_parent = [mi parentItem];
        if (_parent == _subtitle_size || mi == _subtitle_size           ||
            _parent == _subtitle_textcolor || mi == _subtitle_textcolor ||
            _parent == _subtitle_bgcolor || mi == _subtitle_bgcolor     ||
            _parent == _subtitle_bgopacity || mi == _subtitle_bgopacity ||
            _parent == _subtitle_outlinethickness || mi == _subtitle_outlinethickness ||
            _parent == _teletext || mi == _teletext
            ) {
            enabled = _openSubtitleFile.isEnabled;
        }
    }

    if (p_input)
        vlc_object_release(p_input);

    return enabled;
}

@end


/*****************************************************************************
 *VLCAutoGeneratedMenuContent implementation
 *****************************************************************************
 *Object connected to a playlistitem which remembers the data belonging to
 *the variable of the autogenerated menu
 *****************************************************************************/

@interface VLCAutoGeneratedMenuContent ()
{
    char *psz_name;
    vlc_object_t *vlc_object;
    vlc_value_t value;
    int i_type;
}
@end
@implementation VLCAutoGeneratedMenuContent

-(id) initWithVariableName:(const char *)name ofObject:(vlc_object_t *)object
                  andValue:(vlc_value_t)val ofType:(int)type
{
    self = [super init];

    if (self != nil) {
        vlc_object = vlc_object_hold(object);
        psz_name = strdup(name);
        i_type = type;
        value = val;
        if ((i_type & VLC_VAR_TYPE) == VLC_VAR_STRING)
            value.psz_string = strdup(val.psz_string);
    }

    return(self);
}

- (void)dealloc
{
    if (vlc_object)
        vlc_object_release(vlc_object);
    if ((i_type & VLC_VAR_TYPE) == VLC_VAR_STRING)
        free(value.psz_string);
    free(psz_name);
}

- (const char *)name
{
    return psz_name;
}

- (vlc_value_t)value
{
    return value;
}

- (vlc_object_t *)vlcObject
{
    return vlc_object_hold(vlc_object);
}

- (int)type
{
    return i_type;
}

@end
