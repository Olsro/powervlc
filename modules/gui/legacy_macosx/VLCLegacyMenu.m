/*****************************************************************************
 * VLCLegacyMenu.m: main menu for the legacy Mac OS X interface
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

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "VLCLegacyMenu.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyMainWindow.h"
#import "VLCLegacyOpen.h"
#import "VLCLegacyPrefs.h"
#import "VLCLegacyAudioEffects.h"
#import "VLCLegacyVideoEffects.h"
#import "VLCLegacyTrackSync.h"
#import "VLCLegacyMessages.h"
#import "VLCLegacyConvertAndSave.h"
#import "VLCLegacyMediaInfo.h"
#import "VLCLegacyBookmarks.h"
#import "VLCLegacyAbout.h"
#import "VLCLegacyAddons.h"
#import "VLCLegacyCustomCropAr.h"
#import "../macosx_crystalhd.h"
#import "../macosx_browser_addon.h"
#import "misc.h"

#include <vlc_playlist.h>
#include <vlc_modules.h>
#include <vlc_input.h>
#include <vlc_intf_strings.h>
#include <vlc_vout.h>
#include <vlc_aout.h>
#include <vlc_actions.h>
#include <vlc_configuration.h>
#include <vlc_url.h>
#include <math.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

static NSString *keyString(unichar c)
{
    return [NSString stringWithFormat:@"%C", c];
}

/* target object of a dynamic variable menu */
enum {
    OBJ_INPUT,
    OBJ_VOUT,
    OBJ_AOUT,
    OBJ_INTF
};

/* lua extensions: menu tags pack (action << 16) | extension index,
 * exactly like VLCExtensionsManager */
#define EXT_MENU_MAP(action, index) ((((int)(action)) << 16) | (int)(index))
#define EXT_MENU_ACTION(tag) ((int)(((tag) >> 16) & 0xFFFF))
#define EXT_MENU_INDEX(tag)  ((int)((tag) & 0xFFFF))

/* "Open Recent": a small user-defaults backed list, like the 3.0 one */
#define VLC_RECENT_ITEMS_KEY @"VLCLegacyRecentItems"
#define VLC_RECENT_ITEMS_MAX 10

void VLCLegacyNoteRecentItem(NSString *mrl)
{
    if (![mrl length])
        return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *stored = [defaults stringArrayForKey:VLC_RECENT_ITEMS_KEY];
    NSMutableArray *list = stored
        ? [NSMutableArray arrayWithArray:stored] : [NSMutableArray array];
    [list removeObject:mrl];
    [list insertObject:mrl atIndex:0];
    while ([list count] > VLC_RECENT_ITEMS_MAX)
        [list removeLastObject];
    [defaults setObject:list forKey:VLC_RECENT_ITEMS_KEY];

    /* feed the system recent-documents list too: the modern interface's
     * File > Open Recent reads it, so items opened in the legacy
     * interface survive a switch of interfaces */
    NSURL *url = [NSURL URLWithString:mrl];
    if (url)
        [[NSDocumentController sharedDocumentController]
            noteNewRecentDocumentURL:url];
}

@implementation VLCLegacyMenu

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
             about:(VLCLegacyAbout *)aboutController
{
    if (self = [super init]) {
        core = [interaction retain];
        mainWindow = [mw retain];
        open = [openDialogs retain];
        prefs = [prefsController retain];
        audioEffects = [audioEffectsController retain];
        videoEffects = [videoEffectsController retain];
        trackSync = [trackSyncController retain];
        messages = [messagesController retain];
        errorPanel = [errorPanelController retain];
        convertAndSave = [convertAndSaveController retain];
        mediaInfo = [mediaInfoController retain];
        bookmarks = [bookmarksController retain];
        about = [aboutController retain];
        p_intf = [interaction intf];
    }
    return self;
}

- (void)dealloc
{
    if (p_extensions_manager) {
        if (p_extensions_manager->p_module)
            module_unneed(p_extensions_manager,
                          p_extensions_manager->p_module);
        vlc_object_release(p_extensions_manager);
    }
    [voutMenu release];
    [core release];
    [mainWindow release];
    [open release];
    [prefs release];
    [audioEffects release];
    [videoEffects release];
    [trackSync release];
    [messages release];
    [errorPanel release];
    [convertAndSave release];
    [mediaInfo release];
    [bookmarks release];
    [about release];
    [addons release];
    [super dealloc];
}

- (NSMenuItem *)addItemTo:(NSMenu *)menu title:(NSString *)title
                   action:(SEL)action key:(NSString *)key
{
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title
                                                   action:action
                                            keyEquivalent:key] autorelease];
    [item setTarget:self];
    [menu addItem:item];
    return item;
}

- (NSMenu *)addMenuTo:(NSMenu *)menubar title:(NSString *)title
{
    NSMenuItem *item = [menubar addItemWithTitle:@"" action:nil
                                   keyEquivalent:@""];
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:title] autorelease];
    [item setSubmenu:menu];
    return menu;
}

/* Submenu whose content is rebuilt from a VLC object variable each time it
 * opens: this is how the 3.0.23 track/title/chapter menus behave. */
- (NSMenu *)addDynamicMenuTo:(NSMenu *)parent title:(NSString *)title
{
    /* The action is never fired (items with submenus open the submenu
     * instead) but lets validateMenuItem: gray the entry when no media
     * is playing, as the modern interface does */
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:title
                                                   action:@selector(inputDependentParent:)
                                            keyEquivalent:@""] autorelease];
    [item setTarget:self];
    NSMenu *menu = VLCLegacyMakeDynamicMenu(title, self);
    [item setSubmenu:menu];
    [parent addItem:item];
    return menu;
}

/* Static submenu filled with the choices of an integer core option
 * (freetype-color & co), like -[VLCMainMenu setupMenu:withIntList:] */
- (NSMenu *)addConfigChoicesMenuTo:(NSMenu *)parent title:(NSString *)title
                            option:(const char *)name
{
    NSMenuItem *parentItem = [[[NSMenuItem alloc]
        initWithTitle:title
               action:@selector(inputDependentParent:)
        keyEquivalent:@""] autorelease];
    [parentItem setTarget:self];
    NSMenu *menu = [[[NSMenu alloc] initWithTitle:title] autorelease];
    [parentItem setSubmenu:menu];
    [parent addItem:parentItem];

    module_config_t *p_item = config_FindConfig(name);
    if (!p_item)
        return menu;
    int i;
    for (i = 0; i < (int)p_item->list_count; i++) {
        NSString *choiceTitle;
        if (p_item->list_text && p_item->list_text[i])
            choiceTitle = _NS(p_item->list_text[i]);
        else
            choiceTitle = [NSString stringWithFormat:@"%d",
                           (int)p_item->list.i[i]];
        NSMenuItem *choice = [self addItemTo:menu title:choiceTitle
                                      action:@selector(switchSubtitleOption:)
                                         key:@""];
        [choice setTag:p_item->list.i[i]];
        [choice setRepresentedObject:[NSString stringWithUTF8String:name]];
    }
    return menu;
}

/* Apple-DVD-Player-style deinterlacing selector: friendly quality presets
 * (shortcuts over the core "deinterlace" / "deinterlace-mode" variables) plus a
 * "Custom" submenu that still exposes every deinterlace method, so no power is
 * lost versus the raw menus these replaced. "Best quality" is greyed out on
 * Macs that cannot sustain it (see VLCLegacyBestDeinterlaceAvailable), exactly
 * as Apple's DVD Player does. The whole item greys with the rest of the Video
 * menu when nothing is playing. */
- (void)addDeinterlaceQualityMenuTo:(NSMenu *)parent
{
    NSMenuItem *parentItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Deinterlacing")
               action:@selector(inputDependentParent:) keyEquivalent:@""]
        autorelease];
    [parentItem setTarget:self];
    NSMenu *menu = [[[NSMenu alloc]
        initWithTitle:_NS("Deinterlacing")] autorelease];
    [parentItem setSubmenu:menu];
    [parent addItem:parentItem];

    const struct { const char *title; int tier; } tiers[] = {
        { N_("Disabled"),        0 },
        { N_("Good quality"),    1 },
        { N_("Optimal quality"), 2 },
        { N_("Best quality"),    3 },
    };
    unsigned i;
    for (i = 0; i < sizeof(tiers) / sizeof(tiers[0]); i++) {
        NSMenuItem *item = [self addItemTo:menu title:_NS(tiers[i].title)
                                    action:@selector(setDeinterlaceQuality:)
                                       key:@""];
        [item setTag:tiers[i].tier];
    }

    /* "Custom": every deinterlace method the core exposes (translated labels). */
    [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *customItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Custom") action:NULL keyEquivalent:@""] autorelease];
    NSMenu *customMenu = [[[NSMenu alloc]
        initWithTitle:_NS("Custom")] autorelease];
    [customItem setSubmenu:customMenu];
    [menu addItem:customItem];

    char **values = NULL, **texts = NULL;
    ssize_t n = config_GetPszChoices(VLC_OBJECT(p_intf), "deinterlace-mode",
                                     &values, &texts);
    ssize_t c;
    for (c = 0; c < n; c++) {
        if (values[c]) {
            NSString *title = [NSString stringWithUTF8String:
                (texts[c] && *texts[c]) ? texts[c] : values[c]];
            NSMenuItem *m = [self addItemTo:customMenu title:title
                                     action:@selector(setDeinterlaceCustomMode:)
                                        key:@""];
            [m setRepresentedObject:[NSString stringWithUTF8String:values[c]]];
        }
        free(values[c]);
        free(texts[c]);
    }
    free(values);
    free(texts);
}

/* Push a deinterlace state to the core config (so future vouts and the next
 * launch inherit it) and live to the running vout. Set the mode before the
 * on/off toggle so the first deinterlaced frame already uses it. */
- (void)applyDeinterlace:(int)deint mode:(const char *)mode
{
    config_PutInt(p_intf, "deinterlace", deint);
    config_PutPsz(p_intf, "deinterlace-mode", mode);
    vlc_object_t *p_vout = [self objectOfType:OBJ_VOUT];
    if (p_vout) {
        var_SetString(p_vout, "deinterlace-mode", mode);
        var_SetInteger(p_vout, "deinterlace", deint);
        vlc_object_release(p_vout);
    }
}

/* Apply a preset tier (0-3). Tier 4 = "custom": leave the persisted
 * deinterlace-mode untouched (the user picked a raw method from the submenu). */
- (void)applyDeinterlaceTier:(int)tier
{
    if (tier == 4)
        return;
    if (tier == 3 && !VLCLegacyBestDeinterlaceAvailable())
        tier = 2;                       /* clamp "Best" where it is unavailable */

    int deint;                          /* "deinterlace": 0 off, -1 auto-detect */
    const char *mode;                   /* "deinterlace-mode" filter method     */
    switch (tier) {
        case 0: deint =  0; mode = "auto";    break;  /* Disabled            */
        case 1: deint = -1; mode = "linear";  break;  /* Good: light         */
        case 3: deint = -1; mode = "yadif2x"; break;  /* Best: MA @ 50 flds/s */
        case 2:
        default: deint = -1; mode = "auto";   break;  /* Optimal: MA default */
    }
    [self applyDeinterlace:deint mode:mode];
}

- (void)setDeinterlaceQuality:(id)sender
{
    int tier = (int)[sender tag];
    config_PutInt(p_intf, "legacy-macosx-deinterlace", tier);
    [self applyDeinterlaceTier:tier];
    config_SaveConfigFile(p_intf);      /* remember it across launches */
}

- (void)setDeinterlaceCustomMode:(id)sender
{
    const char *mode = [[sender representedObject] UTF8String];
    if (!mode)
        return;
    config_PutInt(p_intf, "legacy-macosx-deinterlace", 4);   /* 4 = custom */
    [self applyDeinterlace:-1 mode:mode];
    config_SaveConfigFile(p_intf);
}

- (void)setupMenu
{
    NSMenu *menubar = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    NSMenuItem *item;

    /* --- VLC --- */
    NSMenu *appMenu = [self addMenuTo:menubar title:@"PowerVLC"];
    [self addItemTo:appMenu title:_NS("About PowerVLC media player")
             action:@selector(showAbout:) key:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:appMenu title:_NS("Preferences...")
             action:@selector(showPrefs:) key:@","];
    [appMenu addItem:[NSMenuItem separatorItem]];
    /* Interface switcher: only when the modern interface can actually run
     * here (module present in this build AND Mac OS X 10.7.5 or newer) */
    if (module_exists("macosx") && VLCLegacyOSVersionAtLeast(10, 7, 5)) {
        [self addItemTo:appMenu title:_NS("Switch to the modern interface")
                 action:@selector(switchInterface:) key:@""];
        [appMenu addItem:[NSMenuItem separatorItem]];
    }
    /* Extensions / Addons Manager / Add Interface, like the 3.0 app menu */
    NSMenuItem *extensionsItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Extensions")
               action:@selector(extensionsParent:)
        keyEquivalent:@""] autorelease];
    [extensionsItem setTarget:self];
    extensionsMenu = VLCLegacyMakeDynamicMenu(_NS("Extensions"), self);
    [extensionsItem setSubmenu:extensionsMenu];
    [appMenu addItem:extensionsItem];
    [self addItemTo:appMenu title:_NS("Addons Manager")
             action:@selector(showAddonsManager:) key:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *addIntfItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Add Interface")
               action:@selector(dynamicSubmenuParent:)
        keyEquivalent:@""] autorelease];
    [addIntfItem setTarget:self];
    addInterfaceMenu = VLCLegacyMakeDynamicMenu(_NS("Add Interface"), self);
    [addIntfItem setSubmenu:addInterfaceMenu];
    [appMenu addItem:addIntfItem];
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *servicesItem = [appMenu addItemWithTitle:_NS("Services")
                                                  action:nil
                                           keyEquivalent:@""];
    NSMenu *servicesMenu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    [servicesItem setSubmenu:servicesMenu];
    [NSApp setServicesMenu:servicesMenu];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:_NS("Hide PowerVLC")
                       action:@selector(hide:) keyEquivalent:@"h"];
    item = [appMenu addItemWithTitle:_NS("Hide Others")
                              action:@selector(hideOtherApplications:)
                       keyEquivalent:@"h"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    [appMenu addItemWithTitle:_NS("Show All")
                       action:@selector(unhideAllApplications:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    /* the items whose action has a core hotkey show the CONFIGURED key, as
     * -[VLCMainMenu setupMenus] does: the literal below is only the fallback
     * should the option be missing */
    item = [self addItemTo:appMenu title:_NS("Quit PowerVLC")
                    action:@selector(quit:) key:@"q"];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-quit");

    /* --- File --- */
    NSMenu *fileMenu = [self addMenuTo:menubar title:_NS("File")];
    [self addItemTo:fileMenu title:_NS("Open File...")
             action:@selector(openFile:) key:@"o"];
    item = [self addItemTo:fileMenu title:_NS("Advanced Open File...")
                    action:@selector(openAdvanced:) key:@"o"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [self addItemTo:fileMenu title:_NS("Open Disc...")
             action:@selector(openDisc:) key:@"d"];
    [self addItemTo:fileMenu title:_NS("Open Network...")
             action:@selector(openNetwork:) key:@"n"];
    [self addItemTo:fileMenu title:_NS("Open Capture Device...")
             action:@selector(openCapture:) key:@"r"];
    /* separators and ordering cloned from the 3.0 MainMenu.xib */
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *recentItem = [fileMenu
        addItemWithTitle:_NS("Open Recent")
                  action:@selector(dynamicSubmenuParent:)
           keyEquivalent:@""];
    [recentItem setTarget:self];
    recentMenu = VLCLegacyMakeDynamicMenu(_NS("Open Recent"), self);
    [recentItem setSubmenu:recentMenu];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:_NS("Close Window")
                        action:@selector(performClose:) keyEquivalent:@"w"];
    item = [self addItemTo:fileMenu title:_NS("Reveal in Finder")
                    action:@selector(revealInFinder:) key:@"r"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    item = [self addItemTo:fileMenu title:_NS("Convert / Stream...")
                    action:@selector(showConvertAndSave:) key:@"s"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:fileMenu title:_NS("Save Playlist...")
             action:@selector(savePlaylist:) key:@"s"];

    /* --- Edit --- */
    NSMenu *editMenu = [self addMenuTo:menubar title:_NS("Edit")];
    [editMenu addItemWithTitle:_NS("Cut")
                        action:@selector(cut:) keyEquivalent:@"x"];
    [editMenu addItemWithTitle:_NS("Copy")
                        action:@selector(copy:) keyEquivalent:@"c"];
    [editMenu addItemWithTitle:_NS("Paste")
                        action:@selector(paste:) keyEquivalent:@"v"];
    item = [editMenu addItemWithTitle:_NS("Delete")
                               action:@selector(deleteSelectedItems:)
                        keyEquivalent:[NSString stringWithFormat:@"%c", 0x08]];
    [item setKeyEquivalentModifierMask:0];
    [item setTarget:mainWindow];
    [editMenu addItemWithTitle:_NS("Select All")
                        action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    item = [self addItemTo:editMenu title:_NS("Find")
                    action:@selector(highlightSearchField:) key:@"f"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];

    /* --- View (order and behaviors of the 3.0.23 View menu) --- */
    NSMenu *viewMenu = [self addMenuTo:menubar title:_NS("View")];
    [self addItemTo:viewMenu title:_NS("Show Previous & Next Buttons")
             action:@selector(toggleJumpButtons:) key:@""];
    [self addItemTo:viewMenu title:_NS("Show Shuffle & Repeat Buttons")
             action:@selector(togglePlaymodeButtons:) key:@""];
    [self addItemTo:viewMenu title:_NS("Show Audio Effects Button")
             action:@selector(toggleEffectsButton:) key:@""];
    [self addItemTo:viewMenu title:_NS("Show Sidebar")
             action:@selector(toggleSidebar:) key:@""];
    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *columnsItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Playlist Table Columns")
               action:nil keyEquivalent:@""] autorelease];
    playlistColumnsMenu = [[[NSMenu alloc]
        initWithTitle:_NS("Playlist Table Columns")] autorelease];
    static const struct { const char *title; const char *identifier; }
        playlist_columns[11] = {
        { N_("Track Number"), "tracknumber" },
        { N_("Title"),        "title" },
        { N_("Author"),       "author" },
        { N_("Duration"),     "duration" },
        { N_("Genre"),        "genre" },
        { N_("Album"),        "album" },
        { N_("Description"),  "description" },
        { N_("Date"),         "date" },
        { N_("Language"),     "language" },
        { N_("URI"),          "uri" },
        { N_("File Size"),    "filesize" },
    };
    int col;
    for (col = 0; col < 11; col++) {
        item = [self addItemTo:playlistColumnsMenu
                         title:_NS(playlist_columns[col].title)
                        action:@selector(togglePlaylistColumnTable:)
                           key:@""];
        [item setRepresentedObject:[NSString stringWithUTF8String:
            playlist_columns[col].identifier]];
    }
    [columnsItem setSubmenu:playlistColumnsMenu];
    [viewMenu addItem:columnsItem];

    /* --- Playback (items and order of the 3.0.23 menu) --- */
    NSMenu *playMenu = [self addMenuTo:menubar title:_NS("Playback")];
    /* Command+P like VLCMainMenu, NOT Space: a menu key equivalent is
     * consumed app-wide before the key window sees it, which would keep the
     * core from ever handling key-play-pause. Space still pauses everywhere
     * -- the vout windows send every key to the hotkey engine, and
     * -[VLCLegacyHostWindow performKeyEquivalent:] hands it the keys that
     * match a configured hotkey. */
    playItem = [self addItemTo:playMenu title:_NS("Play")
                        action:@selector(togglePlayPause:) key:@"p"];
    item = [self addItemTo:playMenu title:_NS("Stop")
                    action:@selector(stop:) key:@"."];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-stop");
    item = [self addItemTo:playMenu title:_NS("Record")
                    action:@selector(toggleRecord:) key:@"r"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    /* clip creation mode, right below Record like the modern interface;
     * the title is refreshed by the validation. Command+Shift+C ("Clip"):
     * Command+C is Copy and Command+Alt+C the playback window, and it sits
     * next to Record's Command+Alt+R. */
    item = [self addItemTo:playMenu title:_NS("Enter Clip Creation Mode")
                    action:@selector(toggleClipCreationMode:) key:@"c"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    /* 3.0 embeds a rate slider in the menu; menu item views only exist
     * from Mac OS X 10.5 on, so the same control becomes a submenu of
     * fixed rates (the slider maps 2^(-2..2) anyway) */
    NSMenuItem *speedItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Playback Speed")
               action:@selector(inputDependentParent:)
        keyEquivalent:@""] autorelease];
    [speedItem setTarget:self];
    NSMenu *speedMenu = [[[NSMenu alloc]
        initWithTitle:_NS("Playback Speed")] autorelease];
    static const struct { const char *title; int pct; } speeds[9] = {
        { "0.25x", 25 },  { "0.50x", 50 },   { "0.75x", 75 },
        { N_("Normal"), 100 },
        { "1.25x", 125 }, { "1.50x", 150 },  { "1.75x", 175 },
        { "2.00x", 200 }, { "4.00x", 400 },
    };
    int spd;
    for (spd = 0; spd < 9; spd++) {
        item = [self addItemTo:speedMenu
                         title:speeds[spd].pct == 100
                             ? _NS(speeds[spd].title)
                             : [NSString stringWithUTF8String:
                                   speeds[spd].title]
                        action:@selector(setPlaybackSpeed:) key:@""];
        [item setTag:speeds[spd].pct];
    }
    [speedItem setSubmenu:speedMenu];
    [playMenu addItem:speedItem];
    [playMenu addItem:[NSMenuItem separatorItem]];
    item = [self addItemTo:playMenu title:_NS("Step Forward")
                    action:@selector(jump:)
                       key:keyString(NSRightArrowFunctionKey)];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    [item setTag:10];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-jump+short");
    item = [self addItemTo:playMenu title:_NS("Step Backward")
                    action:@selector(jump:)
                       key:keyString(NSLeftArrowFunctionKey)];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    [item setTag:-10];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-jump-short");
    [self addItemTo:playMenu title:_NS("Jump to Time")
             action:@selector(jumpToTime:) key:@"j"];
    [playMenu addItem:[NSMenuItem separatorItem]];
    item = [self addItemTo:playMenu title:_NS("Previous")
                    action:@selector(previous:)
                       key:keyString(NSLeftArrowFunctionKey)];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-prev");
    item = [self addItemTo:playMenu title:_NS("Next")
                    action:@selector(next:)
                       key:keyString(NSRightArrowFunctionKey)];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-next");
    item = [self addItemTo:playMenu title:_NS("Random")
                    action:@selector(toggleRandom:) key:@"z"];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-random");
    /* No Command+R on Repeat One although VLCMainMenu carries one: File >
     * Open Capture Device... owns that equivalent in both interfaces, and
     * being earlier in the menu bar it always wins -- the modern entry is
     * decorative. */
    [self addItemTo:playMenu title:_NS("Repeat One")
             action:@selector(toggleRepeat:) key:@""];
    [self addItemTo:playMenu title:_NS("Repeat All")
             action:@selector(toggleLoop:) key:@"l"];
    item = [self addItemTo:playMenu title:_NS("A→B Loop")
                    action:@selector(toggleAtoBLoop:) key:@"l"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [playMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:playMenu title:_NS("Quit after Playback")
             action:@selector(toggleQuitAfterPlayback:) key:@""];
    [playMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *rendererItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Renderer")
               action:@selector(dynamicSubmenuParent:)
        keyEquivalent:@""] autorelease];
    [rendererItem setTarget:self];
    rendererMenu = VLCLegacyMakeDynamicMenu(_NS("Renderer"), self);
    [rendererItem setSubmenu:rendererMenu];
    [playMenu addItem:rendererItem];
    programMenu = [self addDynamicMenuTo:playMenu title:_NS("Program")];
    titleMenu = [self addDynamicMenuTo:playMenu title:_NS("Title")];
    chapterMenu = [self addDynamicMenuTo:playMenu title:_NS("Chapter")];
    /* Blu-ray pop-up menu: drawn by the disc over the running movie, so it is
     * a plain item next to Title/Chapter rather than a submenu. Greyed out
     * unless the title being played carries one (see -validateMenuItem:). */
    [self addItemTo:playMenu title:_NS(I_MENU_DISC_POPUP)
             action:@selector(showDiscPopupMenu:) key:@""];

    /* --- Audio --- */
    NSMenu *audioMenu = [self addMenuTo:menubar title:_NS("Audio")];
    item = [self addItemTo:audioMenu title:_NS("Increase Volume")
                    action:@selector(volumeUp:)
                       key:keyString(NSUpArrowFunctionKey)];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-vol-up");
    item = [self addItemTo:audioMenu title:_NS("Decrease Volume")
                    action:@selector(volumeDown:)
                       key:keyString(NSDownArrowFunctionKey)];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-vol-down");
    item = [self addItemTo:audioMenu title:_NS("Mute")
                    action:@selector(mute:)
                       key:keyString(NSDownArrowFunctionKey)];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-vol-mute");
    [audioMenu addItem:[NSMenuItem separatorItem]];
    audioTrackMenu = [self addDynamicMenuTo:audioMenu
                                      title:_NS("Audio Track")];
    stereoModeMenu = [self addDynamicMenuTo:audioMenu
                                      title:_NS("Stereo audio mode")];
    [audioMenu addItem:[NSMenuItem separatorItem]];
    visualMenu = [self addDynamicMenuTo:audioMenu
                                  title:_NS("Visualizations")];
    [audioMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *audioDeviceItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Audio Device")
               action:@selector(dynamicSubmenuParent:)
        keyEquivalent:@""] autorelease];
    [audioDeviceItem setTarget:self];
    audioDeviceMenu = VLCLegacyMakeDynamicMenu(_NS("Audio Device"), self);
    [audioDeviceItem setSubmenu:audioDeviceMenu];
    [audioMenu addItem:audioDeviceItem];

    /* --- Video --- */
    NSMenu *videoMenu = [self addMenuTo:menubar title:_NS("Video")];
    /* Window sizing through the vout "zoom" variable; the factor times 100
     * is carried by the tag (menu tags are integers) */
    item = [self addItemTo:videoMenu title:_NS("Half Size")
                    action:@selector(setZoom:) key:@"0"];
    [item setTag:50];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-zoom-half");
    item = [self addItemTo:videoMenu title:_NS("Normal Size")
                    action:@selector(setZoom:) key:@"1"];
    [item setTag:100];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-zoom-original");
    item = [self addItemTo:videoMenu title:_NS("Double Size")
                    action:@selector(setZoom:) key:@"2"];
    [item setTag:200];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-zoom-double");
    /* Not a "zoom" factor: like VLCMainMenu this is the AppKit zoom of the
     * window hosting the video, i.e. what the green button does. No core
     * hotkey backs it, so Command+3 is fixed in both interfaces. */
    [self addItemTo:videoMenu title:_NS("Fit to Screen")
             action:@selector(fitToScreen:) key:@"3"];
    [videoMenu addItem:[NSMenuItem separatorItem]];
    item = [self addItemTo:videoMenu title:_NS("Fullscreen")
                    action:@selector(toggleFullscreen:) key:@"f"];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-toggle-fullscreen");
    /* Command+T ("on Top"): free in both interfaces and not a core hotkey
     * (key-position is a bare "t") */
    [self addItemTo:videoMenu title:_NS("Float on Top")
             action:@selector(toggleFloatOnTop:) key:@"t"];
    /* windowed playback drops the controls bar and the title bar a few
     * seconds after the mouse leaves the window; double-click the video
     * to bring them back. Command+Shift+H, like the modern interface
     * (Command+H hides the app, Command+Alt+H the other apps). */
    item = [self addItemTo:videoMenu
                     title:_NS("Hide Controls During Playback")
                    action:@selector(toggleHideControlsPlayback:)
                       key:@"h"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [videoMenu addItem:[NSMenuItem separatorItem]];
    item = [self addItemTo:videoMenu title:_NS("Snapshot")
                    action:@selector(snapshot:) key:@"s"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    VLCLegacyApplyHotkeyToMenuItem(p_intf, item, "key-snapshot");
    [videoMenu addItem:[NSMenuItem separatorItem]];
    videoTrackMenu = [self addDynamicMenuTo:videoMenu
                                      title:_NS("Video Track")];
    /* Which quality of an adaptive stream (HLS/DASH) to watch. Greyed out
     * unless the stream playing offers a choice -- which, on the machines
     * this interface runs on, is the difference between a picture that
     * plays and one that does not. */
    qualityMenu = [self addDynamicMenuTo:videoMenu title:_NS("Quality")];
    maxHeightMenu = [self addDynamicMenuTo:videoMenu
                                     title:_NS("Auto quality by resolution")];
    aspectMenu = [self addDynamicMenuTo:videoMenu title:_NS("Aspect ratio")];
    cropMenu = [self addDynamicMenuTo:videoMenu title:_NS("Crop")];
    [self addDeinterlaceQualityMenuTo:videoMenu];

    /* --- Subtitles --- */
    /* Persist the style variables on the playlist, so every new vout
     * inherits them (exactly what VLCMainMenu does) */
    playlist_t *p_playlist = pl_Get(p_intf);
    var_Create(p_playlist, "freetype-color",
               VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    var_Create(p_playlist, "freetype-background-color",
               VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    var_Create(p_playlist, "freetype-outline-thickness",
               VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);

    NSMenu *subtitlesMenu = [self addMenuTo:menubar title:_NS("Subtitles")];
    [self addItemTo:subtitlesMenu title:_NS("Add Subtitle File...")
             action:@selector(addSubtitleFile:) key:@""];
    subtitleTrackMenu = [self addDynamicMenuTo:subtitlesMenu
                                         title:_NS("Subtitles Track")];
    [subtitlesMenu addItem:[NSMenuItem separatorItem]];

    /* text size: scale factors on "sub-text-scale", like the 3.0 menu */
    NSMenuItem *sizeItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Text Size")
               action:@selector(inputDependentParent:)
        keyEquivalent:@""] autorelease];
    [sizeItem setTarget:self];
    NSMenu *sizeMenu = [[[NSMenu alloc] initWithTitle:_NS("Text Size")]
        autorelease];
    struct { const char *title; int value; } sizes[5] = {
        { N_("Smaller"), 50 }, { N_("Small"), 75 }, { N_("Normal"), 100 },
        { N_("Large"), 125 },  { N_("Larger"), 150 },
    };
    int i;
    for (i = 0; i < 5; i++) {
        item = [self addItemTo:sizeMenu title:_NS(sizes[i].title)
                        action:@selector(setTextSize:) key:@""];
        [item setTag:sizes[i].value];
    }
    [sizeItem setSubmenu:sizeMenu];
    [subtitlesMenu addItem:sizeItem];

    [self addConfigChoicesMenuTo:subtitlesMenu title:_NS("Text Color")
                          option:"freetype-color"];
    [self addConfigChoicesMenuTo:subtitlesMenu
                           title:_NS("Outline Thickness")
                          option:"freetype-outline-thickness"];
    [subtitlesMenu addItem:[NSMenuItem separatorItem]];

    /* 3.0 embeds an opacity slider; menu item views need 10.5, so the
     * same variable becomes a 0-100% submenu in 10% steps */
    var_Create(p_playlist, "freetype-background-opacity",
               VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    NSMenuItem *bgOpacityItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Background Opacity")
               action:@selector(inputDependentParent:)
        keyEquivalent:@""] autorelease];
    [bgOpacityItem setTarget:self];
    NSMenu *bgOpacityMenu = [[[NSMenu alloc]
        initWithTitle:_NS("Background Opacity")] autorelease];
    int pct;
    for (pct = 0; pct <= 100; pct += 10) {
        item = [self addItemTo:bgOpacityMenu
                         title:[NSString stringWithFormat:@"%d %%", pct]
                        action:@selector(setBackgroundOpacity:) key:@""];
        /* the freetype option is 0-255 */
        [item setTag:(pct * 255 + 50) / 100];
    }
    [bgOpacityItem setSubmenu:bgOpacityMenu];
    [subtitlesMenu addItem:bgOpacityItem];

    [self addConfigChoicesMenuTo:subtitlesMenu
                           title:_NS("Background Color")
                          option:"freetype-background-color"];
    [subtitlesMenu addItem:[NSMenuItem separatorItem]];

    /* Teletext, driving the zvbi decoder variables like 3.0 */
    NSMenuItem *teletextItem = [[[NSMenuItem alloc]
        initWithTitle:_NS("Teletext")
               action:@selector(inputDependentParent:)
        keyEquivalent:@""] autorelease];
    [teletextItem setTarget:self];
    NSMenu *teletextMenu = [[[NSMenu alloc] initWithTitle:_NS("Teletext")]
        autorelease];
    [self addItemTo:teletextMenu title:_NS("Transparent")
             action:@selector(telxTransparent:) key:@""];
    [teletextMenu addItem:[NSMenuItem separatorItem]];
    static const struct { const char *title; int page; } telx_links[5] = {
        { N_("Index"),  'i' << 16 }, { N_("Red"),   'r' << 16 },
        { N_("Green"),  'g' << 16 }, { N_("Yellow"), 'y' << 16 },
        { N_("Blue"),   'b' << 16 },
    };
    int tlx;
    for (tlx = 0; tlx < 5; tlx++) {
        item = [self addItemTo:teletextMenu title:_NS(telx_links[tlx].title)
                        action:@selector(telxNavLink:) key:@""];
        [item setTag:telx_links[tlx].page];
    }
    [teletextItem setSubmenu:teletextMenu];
    [subtitlesMenu addItem:teletextItem];

    /* --- Window (items, order and separators of the 3.0.23 menu) --- */
    NSMenu *windowMenu = [self addMenuTo:menubar title:_NS("Window")];
    [windowMenu addItemWithTitle:_NS("Minimize")
                          action:@selector(performMiniaturize:)
                   keyEquivalent:@"m"];
    item = [windowMenu addItemWithTitle:_NS("Zoom")
                                 action:@selector(performZoom:)
                          keyEquivalent:@"z"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    item = [self addItemTo:windowMenu title:_NS("Main Window...")
                    action:@selector(showMainWindow:) key:@"c"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    item = [self addItemTo:windowMenu title:_NS("Playlist...")
                    action:@selector(showPlaylist:) key:@"p"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    [self addItemTo:windowMenu title:_NS("Media Information...")
             action:@selector(showMediaInfo:) key:@"i"];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:windowMenu title:_NS("Video Effects...")
             action:@selector(showVideoEffects:) key:@"e"];
    item = [self addItemTo:windowMenu title:_NS("Audio Effects...")
                    action:@selector(showAudioEffects:) key:@"e"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [self addItemTo:windowMenu title:_NS("Track Synchronization")
             action:@selector(showTrackSynchronization:) key:@""];
    [self addItemTo:windowMenu title:_NS("Bookmarks...")
             action:@selector(showBookmarks:) key:@"b"];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    item = [self addItemTo:windowMenu title:_NS("Errors and Warnings...")
                    action:@selector(showErrorsAndWarnings:) key:@"m"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSAlternateKeyMask];
    item = [self addItemTo:windowMenu title:_NS("Messages...")
                    action:@selector(showMessagesPanel:) key:@"m"];
    [item setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:_NS("Bring All to Front")
                          action:@selector(arrangeInFront:) keyEquivalent:@""];
    [NSApp setWindowsMenu:windowMenu];

    /* --- Help --- */
    NSMenu *helpMenu = [self addMenuTo:menubar title:_NS("Help")];
    [self addItemTo:helpMenu title:_NS("PowerVLC media player Help...")
             action:@selector(openDocumentation:) key:@"?"];
    [helpMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:helpMenu title:_NS("VideoLAN Website...")
             action:@selector(openWebsite:) key:@""];
    [self addItemTo:helpMenu title:_NS("Make a donation...")
             action:@selector(openDonation:) key:@""];
    [self addItemTo:helpMenu title:_NS("Online Forum...")
             action:@selector(openForum:) key:@""];

    /* libaacs and libbdplus ship with the player but decrypt nothing until
     * the user drops their own files next to them -- in a folder inside
     * ~/Library/Preferences that nobody would ever find on their own. Offer to
     * open it, but only where Blu-ray playback works at all: the plugin has to
     * be in this build, and the disc access needs Mac OS X 10.4 (Tiger is the
     * floor for IOKit's optical-drive and DiskArbitration APIs libaacs uses;
     * this interface itself runs as far down as 10.2).
     *
     * "libbluray", not "bluray": module_find() only ever compares
     * pp_shortcuts[0], which is the module's object name (the plugin is built
     * as liblibbluray_plugin). The "bluray" of add_shortcut() sits at index 1
     * and can never match. */
    if (module_exists("libbluray") && VLCLegacyOSVersionAtLeast(10, 4, 0)) {
        [helpMenu addItem:[NSMenuItem separatorItem]];
        [self addItemTo:helpMenu title:_NS("Open the libaacs folder (Blu-ray)")
                 action:@selector(openAACSFolder:) key:@""];
        [self addItemTo:helpMenu title:_NS("Open the libbdplus folder (Blu-ray)")
                 action:@selector(openBDPlusFolder:) key:@""];
    }

    /* The browser half of PowerVLC: it hands what the browser is playing
     * over to the player, and lets the player read pages the user has
     * opened. On these machines it is not a nicety -- every browser that
     * still runs here is older than Firefox 69, and those refuse to run a
     * bookmarklet on any page carrying a security policy, which every
     * guarded site sends. Only offered when this build ships it. */
    if (VLCBrowserAddonPath() != nil) {
        [helpMenu addItem:[NSMenuItem separatorItem]];
        [self addItemTo:helpMenu title:_NS("Install the PowerVLC add-on in "
                                           "your browser...")
                 action:@selector(installBrowserAddon:) key:@""];
    }

    /* Crystal HD: offer to install the driver when there is a card to drive,
     * and to remove it whenever one is installed -- including on a machine
     * whose card has since been taken out, which is the only way left to get
     * rid of it. */
    switch (VLCCrystalHDGetState()) {
        case VLCCrystalHDCardWithoutDriver:
            [helpMenu addItem:[NSMenuItem separatorItem]];
            [self addItemTo:helpMenu
                      title:_NS("Install the Crystal HD driver...")
                     action:@selector(installCrystalHDDriver:) key:@""];
            break;

        case VLCCrystalHDReady:
        case VLCCrystalHDDriverWithoutCard:
            [helpMenu addItem:[NSMenuItem separatorItem]];
            [self addItemTo:helpMenu
                      title:_NS("Reload the Crystal HD driver...")
                     action:@selector(reloadCrystalHDDriver:) key:@""];
            [self addItemTo:helpMenu
                      title:_NS("Remove the Crystal HD driver...")
                     action:@selector(uninstallCrystalHDDriver:) key:@""];
            break;

        case VLCCrystalHDAbsent:
            break;
    }

    [NSApp setMainMenu:menubar];

    /* On Mac OS X 10.4, the application menu must be declared explicitly
     * with the (long deprecated, removed from headers) -setAppleMenu:,
     * otherwise AppKit shows its own bold "VLC" menu next to ours and
     * ours becomes a duplicate. From 10.5 on, the first submenu of the
     * main menu is picked up automatically and this call is unneeded. */
    if ([NSApp respondsToSelector:@selector(setAppleMenu:)])
        [NSApp performSelector:@selector(setAppleMenu:)
                    withObject:[[menubar itemAtIndex:0] submenu]];

    /* --- contextual vout menu (3.0 right-click on the video) --- */
    voutMenu = [[NSMenu alloc] initWithTitle:@""];
    item = [self addItemTo:voutMenu title:_NS("Play")
                    action:@selector(togglePlayPause:) key:@""];
    [self addItemTo:voutMenu title:_NS("Stop")
             action:@selector(stop:) key:@""];
    [self addItemTo:voutMenu title:_NS("Previous")
             action:@selector(previous:) key:@""];
    [self addItemTo:voutMenu title:_NS("Next")
             action:@selector(next:) key:@""];
    [voutMenu addItem:[NSMenuItem separatorItem]];
    voutAudioTrackMenu = [self addDynamicMenuTo:voutMenu
                                          title:_NS("Audio Track")];
    voutVideoTrackMenu = [self addDynamicMenuTo:voutMenu
                                          title:_NS("Video Track")];
    voutSubtitleTrackMenu = [self addDynamicMenuTo:voutMenu
                                             title:_NS("Subtitles Track")];
    /* the only way to reach the Blu-ray pop-up menu in fullscreen, where the
     * menu bar is out of reach (besides the key-disc-popup-menu hotkey); set
     * apart by a separator, it acts on the disc and not on our playback */
    [voutMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:voutMenu title:_NS(I_MENU_DISC_POPUP)
             action:@selector(showDiscPopupMenu:) key:@""];
    [voutMenu addItem:[NSMenuItem separatorItem]];
    [self addItemTo:voutMenu title:_NS("Fullscreen")
             action:@selector(toggleFullscreen:) key:@""];
    [self addItemTo:voutMenu title:_NS("Float on Top")
             action:@selector(toggleFloatOnTop:) key:@""];
    [self addItemTo:voutMenu title:_NS("Snapshot")
             action:@selector(snapshot:) key:@""];
    [voutMenu addItem:[NSMenuItem separatorItem]];
    voutAspectMenu = [self addDynamicMenuTo:voutMenu
                                      title:_NS("Aspect ratio")];
    voutCropMenu = [self addDynamicMenuTo:voutMenu title:_NS("Crop")];
    [self addDeinterlaceQualityMenuTo:voutMenu];

    /* Apply the saved deinterlacing tier once at startup, before the first
     * vout is created, so a choice made last session (or in Preferences)
     * takes effect on the very first frame. */
    [self applyDeinterlaceTier:
        (int)var_InheritInteger(p_intf, "legacy-macosx-deinterlace")];
}

- (NSMenu *)voutMenu
{
    return voutMenu;
}

/*****************************************************************************
 * dynamic variable menus (3.0.23 behavior: rebuilt each time they open)
 *****************************************************************************/

- (vlc_object_t *)objectOfType:(int)type
{
    playlist_t *p_playlist = pl_Get(p_intf);
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (type == OBJ_INPUT)
        return (vlc_object_t *)p_input;   /* held; released by callers */

    if (type == OBJ_VOUT) {
        vout_thread_t *p_vout = NULL;
        if (p_input) {
            p_vout = input_GetVout(p_input);
            vlc_object_release(p_input);
        }
        return (vlc_object_t *)p_vout;
    }

    if (type == OBJ_INTF) {
        if (p_input)
            vlc_object_release(p_input);
        return (vlc_object_t *)vlc_object_hold(p_intf);
    }

    if (p_input)
        vlc_object_release(p_input);
    return (vlc_object_t *)playlist_GetAout(p_playlist);
}

- (void)variableForMenu:(NSMenu *)menu name:(const char **)name
                 object:(int *)objectType isString:(BOOL *)isString
{
    *name = NULL;
    *objectType = OBJ_INPUT;
    *isString = NO;
    if (menu == audioTrackMenu || menu == voutAudioTrackMenu)
        *name = "audio-es";
    else if (menu == subtitleTrackMenu || menu == voutSubtitleTrackMenu)
        *name = "spu-es";
    else if (menu == videoTrackMenu || menu == voutVideoTrackMenu)
        *name = "video-es";
    else if (menu == qualityMenu)
        *name = "adaptive-quality";
    else if (menu == maxHeightMenu)
        *name = "adaptive-maxheight";
    else if (menu == titleMenu)
        *name = "title";
    else if (menu == chapterMenu)
        *name = "chapter";
    else if (menu == programMenu)
        *name = "program";
    else if (menu == stereoModeMenu) {
        *name = "stereo-mode";
        *objectType = OBJ_AOUT;
    } else if (menu == aspectMenu || menu == voutAspectMenu) {
        *name = "aspect-ratio";
        *objectType = OBJ_VOUT;
        *isString = YES;
    } else if (menu == cropMenu || menu == voutCropMenu) {
        *name = "crop";
        *objectType = OBJ_VOUT;
        *isString = YES;
    } else if (menu == visualMenu) {
        *name = "visual";
        *objectType = OBJ_AOUT;
        *isString = YES;
    } else if (menu == addInterfaceMenu) {
        *name = "intf-add";
        *objectType = OBJ_INTF;
        *isString = YES;
    }
}

- (void)menuNeedsUpdate:(NSMenu *)menu
{
    if (menu == recentMenu) {
        while ([menu numberOfItems])
            [menu removeItemAtIndex:0];
        NSArray *recents = [[NSUserDefaults standardUserDefaults]
            stringArrayForKey:VLC_RECENT_ITEMS_KEY];
        unsigned i;
        for (i = 0; i < [recents count]; i++) {
            NSString *mrl = [recents objectAtIndex:i];
            NSString *title = mrl;
            char *psz_path = vlc_uri2path([mrl UTF8String]);
            if (psz_path) {
                title = [[NSFileManager defaultManager] displayNameAtPath:
                    [NSString stringWithUTF8String:psz_path]];
                free(psz_path);
            } else {
                char *psz_mrl = strdup([mrl UTF8String]);
                if (psz_mrl) {
                    vlc_uri_decode(psz_mrl);
                    title = [NSString stringWithUTF8String:psz_mrl];
                    free(psz_mrl);
                }
            }
            NSMenuItem *item = [self addItemTo:menu title:title
                                        action:@selector(openRecentItem:)
                                           key:@""];
            [item setRepresentedObject:mrl];
        }
        if ([recents count])
            [menu addItem:[NSMenuItem separatorItem]];
        [self addItemTo:menu title:_NS("Clear")
                 action:@selector(clearRecentItems:) key:@""];
        return;
    }

    if (menu == audioDeviceMenu) {
        [self rebuildAudioDeviceMenu];
        return;
    }
    if (menu == extensionsMenu) {
        [self rebuildExtensionsMenu];
        return;
    }
    if (menu == rendererMenu) {
        [self rebuildRendererMenu];
        return;
    }

    const char *name;
    int objectType;
    BOOL isString;
    [self variableForMenu:menu name:&name object:&objectType
                 isString:&isString];
    if (!name)
        return;

    while ([menu numberOfItems])
        [menu removeItemAtIndex:0];

    vlc_object_t *p_object = [self objectOfType:objectType];
    if (!p_object)
        return;

    vlc_value_t current;
    if (var_Get(p_object, name, &current) != VLC_SUCCESS) {
        vlc_object_release(p_object);
        return;
    }

    vlc_value_t val, text;
    if (var_Change(p_object, name, VLC_VAR_GETCHOICES, &val, &text)
            != VLC_SUCCESS) {
        if (isString)
            free(current.psz_string);
        vlc_object_release(p_object);
        return;
    }

    int i;
    for (i = 0; i < val.p_list->i_count; i++) {
        NSString *title;
        if (text.p_list->p_values[i].psz_string)
            title = [NSString stringWithUTF8String:
                text.p_list->p_values[i].psz_string];
        else if (isString)
            title = [NSString stringWithUTF8String:
                val.p_list->p_values[i].psz_string
                    ? val.p_list->p_values[i].psz_string : ""];
        else
            title = [NSString stringWithFormat:@"%d",
                (int)val.p_list->p_values[i].i_int];

        NSMenuItem *item = [[[NSMenuItem alloc]
            initWithTitle:title
                   action:@selector(selectDynamicItem:)
            keyEquivalent:@""] autorelease];
        [item setTarget:self];

        NSDictionary *info;
        BOOL selected;
        if (isString) {
            const char *choice = val.p_list->p_values[i].psz_string
                ? val.p_list->p_values[i].psz_string : "";
            info = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSString stringWithUTF8String:name], @"var",
                [NSString stringWithUTF8String:choice], @"value",
                [NSNumber numberWithInt:objectType], @"object",
                nil];
            selected = current.psz_string
                && !strcmp(current.psz_string, choice);
        } else {
            info = [NSDictionary dictionaryWithObjectsAndKeys:
                [NSString stringWithUTF8String:name], @"var",
                [NSNumber numberWithLongLong:
                    val.p_list->p_values[i].i_int], @"value",
                [NSNumber numberWithInt:objectType], @"object",
                nil];
            selected = current.i_int == val.p_list->p_values[i].i_int;
        }
        [item setRepresentedObject:info];
        [item setState:selected ? NSOnState : NSOffState];
        [menu addItem:item];
    }

    var_FreeList(&val, &text);
    if (isString)
        free(current.psz_string);
    vlc_object_release(p_object);

    /* The two ratio menus get a "Custom..." entry of their own, appended
     * after the choices the variable offers (VLC 4.0 backport). It has to
     * be put back here: this method empties the menu each time it opens. */
    if (menu == aspectMenu || menu == voutAspectMenu)
        [self appendCustomItemTo:menu action:@selector(customAspectRatio:)];
    else if (menu == cropMenu || menu == voutCropMenu)
        [self appendCustomItemTo:menu action:@selector(customCrop:)];
}

/*****************************************************************************
 * Custom crop / aspect ratio (VLC 4.0 backport)
 *****************************************************************************/

- (void)appendCustomItemTo:(NSMenu *)menu action:(SEL)action
{
    if ([menu numberOfItems] > 0)
        [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle:_NS("Custom")
                                                  action:action
                                           keyEquivalent:@""] autorelease];
    [item setTarget:self];
    [menu addItem:item];
}

/* Offers the ratio in the menu from now on, and keeps it for the next vout
 * and the next run -- "custom-crop-ratios" / "custom-aspect-ratios" is
 * exactly what vout_IntfInit reads back to fill the menu. */
- (void)rememberCustomRatio:(NSString *)ratio
                   variable:(const char *)name
                     config:(const char *)configName
                     onVout:(vlc_object_t *)p_vout
{
    const char *value = [ratio UTF8String];

    vlc_value_t val_list, text_list;
    if (var_Change(p_vout, name, VLC_VAR_GETCHOICES, &val_list, &text_list)
            == VLC_SUCCESS) {
        BOOL known = NO;
        int i;
        for (i = 0; i < val_list.p_list->i_count; i++) {
            const char *choice = val_list.p_list->p_values[i].psz_string;
            if (choice && !strcmp(choice, value)) {
                known = YES;
                break;
            }
        }
        var_FreeList(&val_list, &text_list);
        if (known)
            return;
    }

    vlc_value_t val, text;
    val.psz_string = (char *)value;
    text.psz_string = (char *)value;
    var_Change(p_vout, name, VLC_VAR_ADDCHOICE, &val, &text);

    char *psz_list = config_GetPsz(p_intf, configName);
    NSMutableArray *ratios = [NSMutableArray array];
    if (psz_list) {
        NSArray *known = [[NSString stringWithUTF8String:psz_list]
            componentsSeparatedByString:@","];
        NSEnumerator *e = [known objectEnumerator];
        NSString *entry;
        while ((entry = [e nextObject]) != nil) {
            if ([entry length] > 0)
                [ratios addObject:entry];
        }
        free(psz_list);
    }
    if (![ratios containsObject:ratio])
        [ratios addObject:ratio];

    config_PutPsz(p_intf, configName,
                  [[ratios componentsJoinedByString:@","] UTF8String]);
    config_SaveConfigFile(p_intf);
}

- (void)customRatioForVariable:(const char *)name
                        config:(const char *)configName
                         title:(NSString *)title
{
    vlc_object_t *p_vout = [self objectOfType:OBJ_VOUT];
    if (!p_vout)
        return;

    char *psz_current = var_GetString(p_vout, name);
    NSString *current = psz_current
        ? [NSString stringWithUTF8String:psz_current] : nil;
    NSString *ratio = [VLCLegacyCustomCropAr runModalWithTitle:title
                                                  currentRatio:current];
    free(psz_current);

    if (ratio) {
        [self rememberCustomRatio:ratio variable:name config:configName
                           onVout:p_vout];
        var_SetString(p_vout, name, [ratio UTF8String]);
    }
    vlc_object_release(p_vout);
}

- (void)customAspectRatio:(id)sender
{
    [self customRatioForVariable:"aspect-ratio"
                          config:"custom-aspect-ratios"
                           title:_NS("Aspect ratio")];
}

- (void)customCrop:(id)sender
{
    [self customRatioForVariable:"crop"
                          config:"custom-crop-ratios"
                           title:_NS("Crop")];
}

/*****************************************************************************
 * Audio Device (aout devices API, port of refreshAudioDeviceList)
 *****************************************************************************/

- (void)rebuildAudioDeviceMenu
{
    while ([audioDeviceMenu numberOfItems])
        [audioDeviceMenu removeItemAtIndex:0];

    audio_output_t *p_aout = playlist_GetAout(pl_Get(p_intf));
    if (!p_aout)
        return;

    char **ids, **names;
    int count = aout_DevicesList(p_aout, &ids, &names);
    if (count < 0) {
        vlc_object_release(p_aout);
        return;
    }
    char *psz_current = aout_DeviceGet(p_aout);

    int i;
    for (i = 0; i < count; i++) {
        NSMenuItem *item = [self addItemTo:audioDeviceMenu
            title:[NSString stringWithUTF8String:names[i] ? names[i] : ""]
           action:@selector(toggleAudioDevice:) key:@""];
        [item setRepresentedObject:
            [NSString stringWithUTF8String:ids[i] ? ids[i] : ""]];
        if (psz_current && ids[i] && !strcmp(psz_current, ids[i]))
            [item setState:NSOnState];
        else if (!psz_current && ids[i] && !*ids[i])
            [item setState:NSOnState];
        free(ids[i]);
        free(names[i]);
    }
    free(ids);
    free(names);
    free(psz_current);
    vlc_object_release(p_aout);
}

- (void)toggleAudioDevice:(id)sender
{
    audio_output_t *p_aout = playlist_GetAout(pl_Get(p_intf));
    if (!p_aout)
        return;
    NSString *deviceId = [sender representedObject];
    if (aout_DeviceSet(p_aout, [deviceId length]
                       ? [deviceId UTF8String] : NULL))
        msg_Warn(p_intf, "failed to set audio device");
    vlc_object_release(p_aout);
}

/*****************************************************************************
 * Renderer (Playback menu). Without any renderer discovery module (none
 * ships in these builds) the 3.0 menu shows a single checked "No renderer"
 * entry; keep exactly that behavior.
 *****************************************************************************/

- (void)rebuildRendererMenu
{
    while ([rendererMenu numberOfItems])
        [rendererMenu removeItemAtIndex:0];
    NSMenuItem *item = [self addItemTo:rendererMenu
                                 title:_NS("No renderer")
                                action:@selector(selectRenderer:) key:@""];
    [item setState:NSOnState];
}

- (void)selectRenderer:(id)sender
{
    playlist_SetRenderer(pl_Get(p_intf), NULL);
}

/*****************************************************************************
 * lua extensions (port of VLCExtensionsManager buildMenu:/triggerMenu:)
 *****************************************************************************/

- (BOOL)loadExtensions
{
    if (p_extensions_manager)
        return p_extensions_manager->p_module != NULL;

    p_extensions_manager = (extensions_manager_t *)
        vlc_object_create(p_intf, sizeof(extensions_manager_t));
    if (!p_extensions_manager)
        return NO;
    p_extensions_manager->p_module =
        module_need(p_extensions_manager, "extension", NULL, false);
    return p_extensions_manager->p_module != NULL;
}

- (int)extensionsCount
{
    if (![self loadExtensions])
        return 0;
    vlc_mutex_lock(&p_extensions_manager->lock);
    int count = p_extensions_manager->extensions.i_size;
    vlc_mutex_unlock(&p_extensions_manager->lock);
    return count;
}

- (void)rebuildExtensionsMenu
{
    while ([extensionsMenu numberOfItems])
        [extensionsMenu removeItemAtIndex:0];
    if (![self loadExtensions])
        return;

    vlc_mutex_lock(&p_extensions_manager->lock);
    extension_t *p_ext = NULL;
    int i_ext = 0;
    FOREACH_ARRAY(p_ext, p_extensions_manager->extensions) {
        bool b_active = extension_IsActivated(p_extensions_manager, p_ext);
        NSString *title = [NSString stringWithUTF8String:
            p_ext->psz_title ? p_ext->psz_title : "?"];

        if (b_active && extension_HasMenu(p_extensions_manager, p_ext)) {
            NSMenu *submenu = [[[NSMenu alloc] initWithTitle:title]
                autorelease];
            NSMenuItem *parent = [extensionsMenu addItemWithTitle:title
                                                           action:nil
                                                    keyEquivalent:@""];
            [parent setSubmenu:submenu];

            char **ppsz_titles = NULL;
            uint16_t *pi_ids = NULL;
            if (extension_GetMenu(p_extensions_manager, p_ext,
                                  &ppsz_titles, &pi_ids) == VLC_SUCCESS) {
                int i;
                for (i = 0; ppsz_titles[i] != NULL; i++) {
                    NSMenuItem *entry = [self addItemTo:submenu
                        title:[NSString stringWithUTF8String:
                            ppsz_titles[i]]
                       action:@selector(triggerExtensionMenu:) key:@""];
                    [entry setTag:EXT_MENU_MAP(pi_ids[i], i_ext)];
                    free(ppsz_titles[i]);
                }
                free(ppsz_titles);
                free(pi_ids);
            }
            [submenu addItem:[NSMenuItem separatorItem]];
            NSMenuItem *deactivate = [self addItemTo:submenu
                title:_NS("Deactivate")
               action:@selector(triggerExtensionMenu:) key:@""];
            [deactivate setTag:EXT_MENU_MAP(0, i_ext)];
        } else {
            NSMenuItem *entry = [self addItemTo:extensionsMenu title:title
                action:@selector(triggerExtensionMenu:) key:@""];
            [entry setTag:EXT_MENU_MAP(0, i_ext)];
            if (!extension_TriggerOnly(p_extensions_manager, p_ext)
             && b_active)
                [entry setState:NSOnState];
        }
        i_ext++;
    }
    FOREACH_END()
    vlc_mutex_unlock(&p_extensions_manager->lock);
}

- (void)triggerExtensionMenu:(id)sender
{
    if (!p_extensions_manager)
        return;
    int i_action = EXT_MENU_ACTION([sender tag]);
    int i_ext = EXT_MENU_INDEX([sender tag]);

    vlc_mutex_lock(&p_extensions_manager->lock);
    if (i_ext < 0 || i_ext >= p_extensions_manager->extensions.i_size) {
        vlc_mutex_unlock(&p_extensions_manager->lock);
        return;
    }
    extension_t *p_ext =
        ARRAY_VAL(p_extensions_manager->extensions, i_ext);
    vlc_mutex_unlock(&p_extensions_manager->lock);

    if (i_action == 0) {
        /* toggle activation, or plain trigger for trigger-only ones. Dialogs
         * raised by the extension are rendered by
         * VLCLegacyExtensionsDialogProvider. */
        if (extension_TriggerOnly(p_extensions_manager, p_ext))
            extension_Trigger(p_extensions_manager, p_ext);
        else if (extension_IsActivated(p_extensions_manager, p_ext))
            extension_Deactivate(p_extensions_manager, p_ext);
        else
            extension_Activate(p_extensions_manager, p_ext);
    } else
        extension_TriggerMenu(p_extensions_manager, p_ext,
                              (uint16_t)i_action);
}

- (void)selectDynamicItem:(id)sender
{
    NSDictionary *info = [sender representedObject];
    if (!info)
        return;
    vlc_object_t *p_object =
        [self objectOfType:[[info objectForKey:@"object"] intValue]];
    if (!p_object)
        return;
    const char *name = [[info objectForKey:@"var"] UTF8String];
    id value = [info objectForKey:@"value"];
    if ([value isKindOfClass:[NSString class]])
        var_SetString(p_object, name, [value UTF8String]);
    else {
        int64_t selected = [value longLongValue];
        var_SetInteger(p_object, name, selected);

        /* These are machine preferences, not merely properties of the
         * current item.  Saving them only when the adaptive demuxer closed
         * meant that a long-running TV stream, a crash or a forced quit lost
         * the user's choice.  Persist standing quality modes (Automatic,
         * Lowest, Highest are non-positive; a positive value is a bitrate
         * belonging only to this playlist) and every resolution ceiling as
         * soon as the menu item is selected. */
        if ((!strcmp(name, "adaptive-quality") && selected <= 0)
         || !strcmp(name, "adaptive-maxheight")) {
            config_PutInt(p_intf, name, selected);
            config_SaveConfigFile(p_intf);
        }
    }
    vlc_object_release(p_object);
}

/*****************************************************************************
 * Menu actions. All run on the main thread (menu dispatch); the playlist
 * functions used here are thread-safe core primitives.
 *****************************************************************************/

- (void)quit:(id)sender               { libvlc_Quit(p_intf->obj.libvlc); }

- (void)switchInterface:(id)sender
{
    NSInteger answer = NSRunAlertPanel(
        _NS("Change the interface?"),
        @"%@",
        _NS("Yes"), _NS("No"), nil,
        _NS("VLC needs to restart to switch interfaces. "
            "Do you want to continue?"));
    if (answer != NSAlertDefaultReturn)
        return;
    /* an empty "intf" restores the default module scoring, which picks
     * the modern interface back on 10.7.5+ */
    config_PutPsz(p_intf, "intf", "");
    config_SaveConfigFile(p_intf);
    VLCLegacyRelaunchApplication();
    libvlc_Quit(p_intf->obj.libvlc);
}

- (void)openFile:(id)sender           { [open openFile]; }

- (void)openRecentItem:(id)sender
{
    NSString *mrl = [sender representedObject];
    if (![mrl length])
        return;
    playlist_Add(pl_Get(p_intf), [mrl UTF8String], true);
    VLCLegacyNoteRecentItem(mrl);
}

- (void)clearRecentItems:(id)sender
{
    [[NSUserDefaults standardUserDefaults]
        removeObjectForKey:VLC_RECENT_ITEMS_KEY];
}

/* the currently playing item, revealed in the Finder like 3.0 */
- (NSString *)currentInputFilePath
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return nil;
    char *psz_uri = input_item_GetURI(input_GetItem(p_input));
    vlc_object_release(p_input);
    if (!psz_uri)
        return nil;
    char *psz_path = vlc_uri2path(psz_uri);
    free(psz_uri);
    if (!psz_path)
        return nil;
    NSString *path = [NSString stringWithUTF8String:psz_path];
    free(psz_path);
    return path;
}

- (void)revealInFinder:(id)sender
{
    NSString *path = [self currentInputFilePath];
    if (path)
        [[NSWorkspace sharedWorkspace] selectFile:path
                         inFileViewerRootedAtPath:@""];
}
- (void)openAdvanced:(id)sender       { [open showTab:OPEN_TAB_FILE]; }
- (void)openNetwork:(id)sender        { [open showTab:OPEN_TAB_NETWORK]; }
- (void)openDisc:(id)sender           { [open showTab:OPEN_TAB_DISC]; }
- (void)openCapture:(id)sender        { [open showTab:OPEN_TAB_CAPTURE]; }
- (void)addSubtitleFile:(id)sender    { [open openSubtitleFile]; }

- (void)togglePlayPause:(id)sender    { [core togglePlayPause]; }
- (void)stop:(id)sender               { [core stop]; }
- (void)next:(id)sender               { [core next]; }
- (void)previous:(id)sender           { [core previous]; }
- (void)jump:(id)sender               { [core jumpWithSeconds:(int)[sender tag]]; }
- (void)jumpToTime:(id)sender         { [mainWindow showJumpToTimePanel]; }
- (void)toggleRecord:(id)sender
{
    /* while creating a clip, Record saves exactly the [start..end] range */
    if ([core clipCreationMode])
        [core recordClipToggle];
    else
        [core toggleRecord];
}
- (void)toggleClipCreationMode:(id)sender { [core toggleClipCreationMode]; }

/* Blu-ray pop-up menu (INPUT_NAV_POPUP), not the disc root menu */
- (void)showDiscPopupMenu:(id)sender
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    input_ShowPopupMenu(p_input);
    vlc_object_release(p_input);
}

- (void)toggleAtoBLoop:(id)sender     { [core setAtoB]; }
- (void)showConvertAndSave:(id)sender { [convertAndSave showWindow]; }

- (void)setPlaybackSpeed:(id)sender
{
    [core setPlaybackRate:(float)[sender tag] / 100.f];
}

- (void)toggleQuitAfterPlayback:(id)sender
{
    playlist_t *p_playlist = pl_Get(p_intf);
    bool b_value = !var_CreateGetBool(p_playlist, "play-and-exit");
    var_SetBool(p_playlist, "play-and-exit", b_value);
    config_PutInt(p_intf, "play-and-exit", b_value);
}

- (void)setBackgroundOpacity:(id)sender
{
    var_SetInteger(pl_Get(p_intf), "freetype-background-opacity",
                   [sender tag]);
}

/* Teletext: drives the running zvbi decoder, like 3.0 (no-op without) */
- (vlc_object_t *)vbiObject
{
    return (vlc_object_t *)vlc_object_find_name(pl_Get(p_intf), "zvbi");
}

- (void)telxTransparent:(id)sender
{
    vlc_object_t *p_vbi = [self vbiObject];
    if (!p_vbi)
        return;
    var_SetBool(p_vbi, "vbi-opaque", [sender state] == NSOnState);
    vlc_object_release(p_vbi);
}

- (void)telxNavLink:(id)sender
{
    vlc_object_t *p_vbi = [self vbiObject];
    if (!p_vbi)
        return;
    var_SetInteger(p_vbi, "vbi-page", [sender tag]);
    vlc_object_release(p_vbi);
}

/* never fired: enables/disables the Extensions submenu parent */
- (void)extensionsParent:(id)sender
{
}

- (void)showAddonsManager:(id)sender
{
    if (!addons)
        addons = [[VLCLegacyAddons alloc] initWithIntf:p_intf];
    [addons showWindow];
}

- (void)toggleRandom:(id)sender       { [core togglePlaylistBool:"random"]; }
- (void)toggleLoop:(id)sender         { [core togglePlaylistBool:"loop"]; }
- (void)toggleRepeat:(id)sender       { [core togglePlaylistBool:"repeat"]; }
/* Port of -[VLCMainMenu floatOnTop:]. Toggling only the PLAYLIST variable
 * (what this did) seeds the next vout and never reaches the window that is
 * on screen: the state has to be set on the running vout, which is what the
 * core turns into VOUT_WINDOW_SET_STATE. The playlist copy is kept in sync
 * because the check mark reads it. */
- (void)toggleFloatOnTop:(id)sender
{
    playlist_t *p_playlist = pl_Get(p_intf);
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (!p_input) {
        var_ToggleBool(p_playlist, "video-on-top");
        return;
    }
    vout_thread_t *p_vout = input_GetVout(p_input);
    if (p_vout) {
        bool b_on = var_ToggleBool(p_vout, "video-on-top");
        var_SetBool(p_playlist, "video-on-top", b_on);
        vlc_object_release(p_vout);
    }
    vlc_object_release(p_input);
}

- (void)toggleHideControlsPlayback:(id)sender
{
    [core setAutoHideControls:![core autoHideControls]];
}

- (void)volumeUp:(id)sender           { [core volumeUp]; }
- (void)volumeDown:(id)sender         { [core volumeDown]; }
- (void)mute:(id)sender               { [core toggleMute]; }

- (void)toggleFullscreen:(id)sender   { [core toggleFullscreen]; }
- (void)snapshot:(id)sender           { [core snapshot]; }
- (void)setZoom:(id)sender            { [core setZoom:(float)[sender tag] / 100.f]; }

/* Video > Fit to Screen, ported from -[VLCMainMenu resizeVideoWindow:]:
 * zoom the window the video lives in. Windowed playback embeds the video in
 * the main window, which is zoomable; the standalone vout window (second
 * vout, or shutdown) is borderless and AppKit ignores -performZoom: there,
 * exactly as in the modern interface. */
- (void)fitToScreen:(id)sender        { [[NSApp keyWindow] performZoom:sender]; }

- (void)highlightSearchField:(id)sender { [mainWindow highlightSearchField]; }

- (void)setTextSize:(id)sender
{
    var_SetInteger(pl_Get(p_intf), "sub-text-scale", [sender tag]);
}

- (void)switchSubtitleOption:(id)sender
{
    var_SetInteger(pl_Get(p_intf),
                   [[sender representedObject] UTF8String], [sender tag]);
}

/* debug: exercise the very call AppKit makes before showing a menu, and
 * report what each dynamic submenu ends up containing. VLC_LEGACY_SHOW /
 * legacy-macosx-show = "menucheck". */
- (void)debugDumpDynamicMenus
{
    struct { const char *name; NSMenu *menu; } dyn[8] = {
        { "audioDevice",  audioDeviceMenu },
        { "renderer",     rendererMenu },
        { "extensions",   extensionsMenu },
        { "addInterface", addInterfaceMenu },
        { "recent",       recentMenu },
        { "crop",         cropMenu },
        { "title",        titleMenu },
        { "chapter",      chapterMenu },
    };
    int i;

    for (i = 0; i < 8; i++) {
        if (dyn[i].menu == nil)
            continue;
        [dyn[i].menu update];
        msg_Info(p_intf, "menucheck: %s -> %d entrée(s)", dyn[i].name,
                 (int)[dyn[i].menu numberOfItems]);
    }
}

/* Never fired (the items carry submenus); exists so validateMenuItem:
 * can gray those entries without a playing input */
- (void)inputDependentParent:(id)sender
{
}

/* Never fired either. It marks the items whose submenu is rebuilt on the
 * fly, and it exists because AppKit only validates items that HAVE an
 * action -- which is how those submenus get refreshed where NSMenu has no
 * delegate (see -validateMenuItem:). Always enabled. */
- (void)dynamicSubmenuParent:(id)sender
{
}

- (void)savePlaylist:(id)sender
{
    NSSavePanel *savePanel = [NSSavePanel savePanel];

    /* accessory view with the export format, like VLCMainMenu */
    NSView *accessory = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 342, 32)] autorelease];
    NSTextField *label = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(0, 9, 99, 14)] autorelease];
    [label setEditable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setAlignment:NSRightTextAlignment];
    [[label cell] setFont:[NSFont systemFontOfSize:11]];
    [label setStringValue:_NS("File Format:")];
    [accessory addSubview:label];
    NSPopUpButton *formatPopup = [[[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(104, 2, 230, 26) pullsDown:NO] autorelease];
    [formatPopup addItemWithTitle:_NS("Extended M3U")];
    [formatPopup addItemWithTitle:
        _NS("XML Shareable Playlist Format (XSPF)")];
    [formatPopup addItemWithTitle:_NS("HTML playlist")];
    [accessory addSubview:formatPopup];

    [savePanel setTitle:_NS("Save Playlist")];
    [savePanel setPrompt:_NS("Save")];
    [savePanel setAccessoryView:accessory];

    /* runModalForDirectory:file: rather than setNameFieldStringValue:
     * (10.6) and runModal (URL-based, 10.6) */
    if ([savePanel runModalForDirectory:nil file:_NS("Untitled")]
            != NSFileHandlingPanelOKButton)
        return;

    static const char *const modules[3] =
        { "export-m3u", "export-xspf", "export-html" };
    static NSString *const extensions[3] = { @".m3u", @".xspf", @".html" };
    int format = (int)[formatPopup indexOfSelectedItem];
    if (format < 0 || format > 2)
        format = 0;

    NSString *filename = [savePanel filename];
    if (![[filename lowercaseString] hasSuffix:extensions[format]])
        filename = [filename stringByAppendingString:extensions[format]];

    playlist_Export(pl_Get(p_intf), [filename fileSystemRepresentation],
                    true, modules[format]);
}

- (void)showAbout:(id)sender          { [about showAbout]; }
- (void)showMainWindow:(id)sender     { [mainWindow showWindow]; }
- (void)showPlaylist:(id)sender       { [mainWindow showPlaylistView]; }
- (void)showPrefs:(id)sender          { [prefs showWindow]; }
- (void)showAudioEffects:(id)sender   { [audioEffects showWindow]; }
- (void)showVideoEffects:(id)sender   { [videoEffects showWindow]; }
- (void)showTrackSynchronization:(id)sender { [trackSync showWindow]; }
- (void)showMessagesPanel:(id)sender  { [messages showWindow]; }
- (void)showErrorsAndWarnings:(id)sender { [errorPanel showWindow]; }
- (void)showMediaInfo:(id)sender      { [mediaInfo showWindow]; }
- (void)showBookmarks:(id)sender      { [bookmarks showWindow]; }

/* --- View menu (VLC 3.0 behaviors, delegated to the main window) --- */
- (void)toggleJumpButtons:(id)sender     { [mainWindow toggleJumpButtons]; }
- (void)togglePlaymodeButtons:(id)sender
{
    [mainWindow togglePlaymodeButtons];
}
- (void)toggleEffectsButton:(id)sender   { [mainWindow toggleEffectsButton]; }
- (void)toggleSidebar:(id)sender         { [mainWindow toggleSidebar]; }

- (void)togglePlaylistColumnTable:(id)sender
{
    [mainWindow togglePlaylistColumn:[sender representedObject]];
}

- (void)openWebsite:(id)sender
{
    VLCLegacyConfirmAndOpenVideoLANURL(
        [NSURL URLWithString:@"https://www.videolan.org/"]);
}

- (void)openDocumentation:(id)sender
{
    VLCLegacyConfirmAndOpenVideoLANURL(
        [NSURL URLWithString:@"https://www.videolan.org/doc/"]);
}

- (void)openDonation:(id)sender
{
    VLCLegacyConfirmAndOpenVideoLANURL(
        [NSURL URLWithString:@"https://www.videolan.org/contribute.html#money"]);
}

- (void)openForum:(id)sender
{
    VLCLegacyConfirmAndOpenVideoLANURL(
        [NSURL URLWithString:@"https://forum.videolan.org/"]);
}

/* Reveals <config home>/<lib> in the Finder, creating it first: the folder
 * does not exist until something writes there, and an "open" that silently did
 * nothing would look like a broken menu item. config_GetDiscLibDir() is what
 * the key database importer uses too, so the two can never disagree.
 *
 * -createDirectoryAtPath:attributes: creates one level only, which is all that
 * is needed: its parent is ~/Library/Preferences, which every account has.
 * (The recursive -createDirectoryAtPath:withIntermediateDirectories:... is
 * 10.5 and would take this interface's Tiger builds down with it.) */
- (void)openDiscLibFolder:(const char *)psz_lib
{
    char *psz_dir = config_GetDiscLibDir(psz_lib);
    NSString *path = psz_dir ? [NSString stringWithUTF8String:psz_dir] : nil;

    NSFileManager *fm = [NSFileManager defaultManager];

    if (path != nil
     && ([fm fileExistsAtPath:path]
      || [fm createDirectoryAtPath:path attributes:nil])
     && [[NSWorkspace sharedWorkspace] openFile:path]) {
        free(psz_dir);
        return;
    }

    msg_Err(p_intf, "cannot open the %s folder", psz_lib);

    /* The "%s" is substituted by hand rather than through -stringWithFormat:,
     * whose %s decodes the bytes in the *system* encoding -- which is not
     * necessarily UTF-8 here, and this is a path. The msgid keeps VLC's "%s"
     * so that the three interfaces share a single string to translate. */
    NSMutableString *msg = [NSMutableString stringWithString:
        _NS("The folder %s could not be opened.")];
    [msg replaceOccurrencesOfString:@"%s"
                         withString:(path != nil ? path
                                     : [NSString stringWithUTF8String:psz_lib])
                            options:0
                              range:NSMakeRange(0, [msg length])];
    NSRunAlertPanel(_NS("Error"), @"%@", _NS("OK"), nil, nil, msg);
    free(psz_dir);
}

- (void)openAACSFolder:(id)sender
{
    [self openDiscLibFolder:"aacs"];
}

- (void)openBDPlusFolder:(id)sender
{
    [self openDiscLibFolder:"bdplus"];
}

/* Handing the file to the browser is the whole of it: the browser then
 * shows its own install prompt, which is where this belongs -- the player
 * has no business installing anything inside somebody's browser. */
- (void)installBrowserAddon:(id)sender
{
    if (VLCBrowserAddonInstall())
        return;

    NSRunAlertPanel(_NS("Error"), @"%@", _NS("OK"), nil, nil,
                    _NS("PowerVLC could not open the add-on with your "
                        "browser. Drag share/powervlc.xpi from the "
                        "application onto a browser window to install it."));
}

- (void)reloadCrystalHDDriver:(id)sender
{
    VLCCrystalHDRunReloadFlow();
}

/* The menu is built once at startup, so flip the item over itself rather than
 * leaving it offering to install a driver that is now installed. */
- (void)installCrystalHDDriver:(id)sender
{
    if (!VLCCrystalHDRunInstallFlow(NO))
        return;

    if ([sender isKindOfClass:[NSMenuItem class]]) {
        [sender setTitle:_NS("Remove the Crystal HD driver...")];
        [sender setAction:@selector(uninstallCrystalHDDriver:)];
    }
}

- (void)uninstallCrystalHDDriver:(id)sender
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

/* An input must be playing for these to make sense */
- (BOOL)hasInput
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return NO;
    vlc_object_release(p_input);
    return YES;
}

/* Only the Blu-ray titles carrying a pop-up menu offer one; the demuxer
 * publishes it on the input (see INPUT_POPUP_MENU_VAR). */
- (BOOL)hasDiscPopupMenu
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return NO;
    BOOL b_available = input_HasPopupMenu(p_input) ? YES : NO;
    vlc_object_release(p_input);
    return b_available;
}

- (BOOL)hasVout
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return NO;
    vout_thread_t *p_vout = input_GetVout(p_input);
    if (p_vout)
        vlc_object_release(p_vout);
    vlc_object_release(p_input);
    return p_vout != NULL;
}

/* Check marks, dynamic titles and the context-sensitive graying of
 * -[VLCMainMenu validateMenuItem:] */
- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    SEL action = [item action];
    playlist_t *p_playlist = pl_Get(p_intf);

    if (action == @selector(dynamicSubmenuParent:))
        return YES;
    const char *name = NULL;
    if (action == @selector(toggleRandom:))
        name = "random";
    else if (action == @selector(toggleLoop:))
        name = "loop";
    else if (action == @selector(toggleRepeat:))
        name = "repeat";
    else if (action == @selector(toggleFloatOnTop:)) {
        [item setState:[core playlistBool:"video-on-top"]
            ? NSOnState : NSOffState];
        return [self hasVout];
    } else if (action == @selector(toggleHideControlsPlayback:)) {
        [item setState:[core autoHideControls] ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(mute:)) {
        [item setState:[core muted] ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(togglePlayPause:)) {
        /* "Play" becomes "Pause" while playing, like 3.0.23 */
        playlist_Lock(p_playlist);
        int status = playlist_Status(p_playlist);
        playlist_Unlock(p_playlist);
        [item setTitle:status == PLAYLIST_RUNNING
            ? _NS("Pause") : _NS("Play")];
        return YES;
    } else if (action == @selector(stop:)) {
        return [self hasInput];
    } else if (action == @selector(previous:) || action == @selector(next:)) {
        playlist_Lock(p_playlist);
        BOOL several = playlist_CurrentSize(p_playlist) > 1;
        playlist_Unlock(p_playlist);
        return several;
    } else if (action == @selector(jump:)
            || action == @selector(jumpToTime:)) {
        BOOL canSeek = NO;
        input_thread_t *p_input = playlist_CurrentInput(p_playlist);
        if (p_input) {
            canSeek = var_GetBool(p_input, "can-seek") ? YES : NO;
            vlc_object_release(p_input);
        }
        return canSeek;
    } else if (action == @selector(toggleRecord:)) {
        [item setState:[core recording] ? NSOnState : NSOffState];
        return [core canRecord];
    } else if (action == @selector(toggleClipCreationMode:)) {
        [item setTitle:[core clipCreationMode]
            ? _NS("Exit Clip Creation Mode")
            : _NS("Enter Clip Creation Mode")];
        /* defining bounds needs seeking, saving the clip needs recording */
        BOOL canSeek = NO;
        input_thread_t *p_input = playlist_CurrentInput(p_playlist);
        if (p_input) {
            canSeek = var_GetBool(p_input, "can-seek") ? YES : NO;
            vlc_object_release(p_input);
        }
        return canSeek && [core canRecord];
    } else if (action == @selector(setPlaybackSpeed:)) {
        int current = (int)lroundf([core playbackRate] * 100.f);
        [item setState:current == [item tag] ? NSOnState : NSOffState];
        return [self hasInput];
    } else if (action == @selector(toggleAtoBLoop:)) {
        return [self hasInput];
    } else if (action == @selector(toggleQuitAfterPlayback:)) {
        [item setState:var_InheritBool(p_playlist, "play-and-exit")
            ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(setBackgroundOpacity:)) {
        [item setState:
            var_GetInteger(p_playlist, "freetype-background-opacity")
                == [item tag] ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(telxTransparent:)
            || action == @selector(telxNavLink:)) {
        vlc_object_t *p_vbi = [self vbiObject];
        if (!p_vbi)
            return NO;
        if (action == @selector(telxTransparent:))
            [item setState:var_GetBool(p_vbi, "vbi-opaque")
                ? NSOffState : NSOnState];
        vlc_object_release(p_vbi);
        return YES;
    } else if (action == @selector(extensionsParent:)) {
        return [self extensionsCount] > 0;
    } else if (action == @selector(setZoom:)
            || action == @selector(fitToScreen:)
            || action == @selector(snapshot:)
            || action == @selector(toggleFullscreen:)) {
        return [self hasVout];
    } else if (action == @selector(showDiscPopupMenu:)) {
        return [self hasDiscPopupMenu];
    } else if (action == @selector(addSubtitleFile:)
            || action == @selector(inputDependentParent:)) {
        /* Quality only means something for an adaptive stream: the demuxer
         * publishes the list on the input, and there is none otherwise */
        if ([item submenu] == qualityMenu || [item submenu] == maxHeightMenu) {
            const char *psz_var = ([item submenu] == qualityMenu)
                                ? "adaptive-quality" : "adaptive-maxheight";
            input_thread_t *p_input =
                playlist_CurrentInput(pl_Get(p_intf));
            BOOL b_has = NO;
            if (p_input) {
                b_has = (var_Type((vlc_object_t *)p_input, psz_var)
                         & VLC_VAR_TYPE) == VLC_VAR_INTEGER;
                vlc_object_release(p_input);
            }
            return b_has;
        }
        return [self hasInput];
    } else if (action == @selector(revealInFinder:)) {
        /* only local files can be shown in the Finder */
        return [self currentInputFilePath] != nil;
    } else if (action == @selector(clearRecentItems:)) {
        return [[[NSUserDefaults standardUserDefaults]
            stringArrayForKey:VLC_RECENT_ITEMS_KEY] count] > 0;
    } else if (action == @selector(toggleJumpButtons:)) {
        [item setState:var_InheritBool(p_intf,
            "legacy-macosx-show-playback-buttons")
                ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(togglePlaymodeButtons:)) {
        [item setState:var_InheritBool(p_intf,
            "legacy-macosx-show-playmode-buttons")
                ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(toggleEffectsButton:)) {
        [item setState:var_InheritBool(p_intf,
            "legacy-macosx-show-effects-button")
                ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(toggleSidebar:)) {
        [item setState:[mainWindow sidebarVisible]
            ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(togglePlaylistColumnTable:)) {
        [item setState:[mainWindow playlistColumnShown:
            [item representedObject]] ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(setTextSize:)) {
        [item setState:
            var_GetInteger(p_playlist, "sub-text-scale") == [item tag]
                ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(setDeinterlaceQuality:)) {
        /* "Best quality" is unavailable (greyed) on Macs that cannot run it */
        if ([item tag] == 3 && !VLCLegacyBestDeinterlaceAvailable()) {
            [item setState:NSOffState];
            return NO;
        }
        int tier = (int)var_InheritInteger(p_intf, "legacy-macosx-deinterlace");
        if (tier == 3 && !VLCLegacyBestDeinterlaceAvailable())
            tier = 2;               /* stored Best but unavailable → Optimal */
        [item setState:([item tag] == tier) ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(setDeinterlaceCustomMode:)) {
        /* checked when this raw method is the active one (tier 4 = custom) */
        BOOL on = NO;
        if (var_InheritInteger(p_intf, "legacy-macosx-deinterlace") == 4) {
            char *cur = config_GetPsz(p_intf, "deinterlace-mode");
            on = cur && [[item representedObject] isEqualToString:
                            [NSString stringWithUTF8String:cur]];
            free(cur);
        }
        [item setState:on ? NSOnState : NSOffState];
        return YES;
    } else if (action == @selector(switchSubtitleOption:)) {
        [item setState:
            var_GetInteger(p_playlist,
                           [[item representedObject] UTF8String])
                == [item tag] ? NSOnState : NSOffState];
        return YES;
    }
    if (name)
        [item setState:[core playlistBool:name] ? NSOnState : NSOffState];
    return YES;
}

@end
