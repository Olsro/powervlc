/*****************************************************************************
 * VLCLegacyMain.m: central controller for the legacy Mac OS X interface
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

#import "VLCLegacyMain.h"
#import "misc.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyMainWindow.h"
#import "VLCLegacyMenu.h"
#import "../macosx_crystalhd.h"
#import "VLCLegacyOpen.h"
#import "VLCLegacyPrefs.h"
#import "VLCLegacyAudioEffects.h"
#import "VLCLegacyVideoEffects.h"
#import "VLCLegacyTrackSync.h"
#import "VLCLegacyMessages.h"
#import "VLCLegacyConvertAndSave.h"
#import "VLCLegacyMediaInfo.h"
#import "VLCLegacyBookmarks.h"
#import "VLCLegacyFSPanel.h"
#import "VLCLegacyAbout.h"
#import "VLCLegacyExtensionsDialogProvider.h"

#include <vlc_dialog.h>
#include <vlc_configuration.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])


/*****************************************************************************
 * Core dialog provider: errors are collected in the Errors and Warnings
 * panel; questions are asked with a modal alert; the remaining interactive
 * dialogs are dismissed (the same net behavior as having no provider, which
 * rejects them, but errors become visible).
 * The callbacks run on core threads: marshal everything.
 *****************************************************************************/

/* NSArray cannot hold nil, and the core passes NULL for the buttons it does
 * not use. */
static NSString *legacyStr(const char *psz)
{
    return psz != NULL ? [NSString stringWithUTF8String:psz] : @"";
}

static void dialogDisplayError(void *p_data, const char *psz_title,
                               const char *psz_text)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *line = [NSString stringWithFormat:@"%@: %@",
        [NSString stringWithUTF8String:psz_title ? psz_title : ""],
        [NSString stringWithUTF8String:psz_text ? psz_text : ""]];
    [[(VLCLegacyMain *)p_data errorPanelController]
        performSelectorOnMainThread:@selector(addError:)
                         withObject:line
                      waitUntilDone:NO];
    [pool release];
}

static void dialogDismissId(void *p_data, vlc_dialog_id *p_id)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [(VLCLegacyMain *)p_data
        performSelectorOnMainThread:@selector(dismissDialog:)
                         withObject:[NSValue valueWithPointer:p_id]
                      waitUntilDone:NO];
    [pool release];
}

static void dialogDisplayLogin(void *p_data, vlc_dialog_id *p_id,
                               const char *psz_title, const char *psz_text,
                               const char *psz_default_username,
                               bool b_ask_store)
{
    (void)psz_title; (void)psz_text; (void)psz_default_username;
    (void)b_ask_store;
    dialogDismissId(p_data, p_id);
}

static void dialogDisplayQuestion(void *p_data, vlc_dialog_id *p_id,
                                  const char *psz_title,
                                  const char *psz_text,
                                  vlc_dialog_question_type i_type,
                                  const char *psz_cancel,
                                  const char *psz_action1,
                                  const char *psz_action2)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    /* performSelectorOnMainThread: retains its argument until it runs, so the
     * array outlives this pool. Never waitUntilDone: the caller is a core
     * thread blocked on the answer, and the panel needs the main thread. */
    NSArray *data = [NSArray arrayWithObjects:
        [NSValue valueWithPointer:p_id],
        legacyStr(psz_title),
        legacyStr(psz_text),
        [NSNumber numberWithInt:(int)i_type],
        legacyStr(psz_cancel),
        legacyStr(psz_action1),
        legacyStr(psz_action2),
        nil];
    [(VLCLegacyMain *)p_data
        performSelectorOnMainThread:@selector(displayQuestion:)
                         withObject:data
                      waitUntilDone:NO];
    [pool release];
}

static void dialogDisplayProgress(void *p_data, vlc_dialog_id *p_id,
                                  const char *psz_title,
                                  const char *psz_text,
                                  bool b_indeterminate, float f_position,
                                  const char *psz_cancel)
{
    /* progress reports are not surfaced by this interface */
    (void)p_data; (void)p_id; (void)psz_title; (void)psz_text;
    (void)b_indeterminate; (void)f_position; (void)psz_cancel;
}

static void dialogCancel(void *p_data, vlc_dialog_id *p_id)
{
    (void)p_data; (void)p_id;
}

static void dialogUpdateProgress(void *p_data, vlc_dialog_id *p_id,
                                 float f_position, const char *psz_text)
{
    (void)p_data; (void)p_id; (void)f_position; (void)psz_text;
}

static const vlc_dialog_cbs dialog_callbacks = {
    dialogDisplayError,
    dialogDisplayLogin,
    dialogDisplayQuestion,
    dialogDisplayProgress,
    dialogCancel,
    dialogUpdateProgress,
};

@implementation VLCLegacyMain

- (id)initWithIntf:(intf_thread_t *)intf
{
    if (self = [super init]) {
        p_intf = intf;
        core = [[VLCLegacyCoreInteraction alloc] initWithIntf:intf];
        mainWindow = [[VLCLegacyMainWindow alloc] initWithCore:core];
        open = [[VLCLegacyOpen alloc] initWithCore:core];
        prefs = [[VLCLegacyPrefs alloc] initWithCore:core];
        audioEffects = [[VLCLegacyAudioEffects alloc] initWithCore:core];
        videoEffects = [[VLCLegacyVideoEffects alloc] initWithCore:core];
        trackSync = [[VLCLegacyTrackSync alloc] initWithCore:core];
        messages = [[VLCLegacyMessages alloc] initWithIntf:intf];
        errorPanel = [[VLCLegacyErrorPanel alloc] initWithIntf:intf];
        convertAndSave = [[VLCLegacyConvertAndSave alloc] initWithCore:core];
        mediaInfo = [[VLCLegacyMediaInfo alloc] initWithCore:core];
        bookmarks = [[VLCLegacyBookmarks alloc] initWithCore:core];
        fsPanel = [[VLCLegacyFSPanel alloc] initWithCore:core];
        about = [[VLCLegacyAbout alloc] initWithIntf:intf];
        /* without this, an extension builds its dialog and nothing
         * ever shows it: clicking VLSub simply did nothing */
        extensionDialogs =
            [[VLCLegacyExtensionsDialogProvider alloc] initWithIntf:intf];
        menu = [[VLCLegacyMenu alloc] initWithCore:core
                                        mainWindow:mainWindow
                                              open:open
                                             prefs:prefs
                                      audioEffects:audioEffects
                                      videoEffects:videoEffects
                                         trackSync:trackSync
                                          messages:messages
                                        errorPanel:errorPanel
                                    convertAndSave:convertAndSave
                                         mediaInfo:mediaInfo
                                         bookmarks:bookmarks
                                             about:about];
    }
    return self;
}

- (void)dealloc
{
    if ([NSApp delegate] == self)
        [NSApp setDelegate:nil];
    [menu release];
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
    [fsPanel release];
    [extensionDialogs stop];
    [extensionDialogs release];
    [about release];
    [mainWindow release];
    [core release];
    [super dealloc];
}

- (VLCLegacyMainWindow *)mainWindowController
{
    return mainWindow;
}

- (VLCLegacyCoreInteraction *)coreInteraction
{
    return core;
}

- (id)mediaInfoController
{
    return mediaInfo;
}

- (id)menuController
{
    return menu;
}

- (id)audioEffectsController
{
    return audioEffects;
}

- (id)errorPanelController
{
    return errorPanel;
}

- (void)dismissDialog:(NSValue *)idValue
{
    vlc_dialog_id_dismiss((vlc_dialog_id *)[idValue pointerValue]);
}

- (void)displayQuestion:(NSArray *)dialogData
{
    vlc_dialog_id *p_id = (vlc_dialog_id *)[[dialogData objectAtIndex:0] pointerValue];
    NSString *title = [dialogData objectAtIndex:1];
    NSString *text = [dialogData objectAtIndex:2];
    int i_type = [[dialogData objectAtIndex:3] intValue];
    NSString *cancel = [dialogData objectAtIndex:4];
    NSString *action1 = [dialogData objectAtIndex:5];
    NSString *action2 = [dialogData objectAtIndex:6];

    /* The first button of NSRunAlertPanel is the default one. A question with
     * no action is a plain notification: the cancel button is then the only
     * button, so it takes that place. */
    BOOL isNotification = [action1 length] == 0 && [action2 length] == 0;
    NSString *defaultButton = isNotification ? cancel : action1;
    NSString *alternateButton = ([action2 length] > 0) ? action2 : nil;
    NSString *otherButton = isNotification ? nil : cancel;

    if ([defaultButton length] == 0)
        defaultButton = _NS("OK");

    /* NSAlert exists on 10.4 but only its modal-session API can set a style,
     * and NSRunCriticalAlertPanel is exactly the caution variant. */
    NSInteger answer;
    if (i_type == VLC_DIALOG_QUESTION_CRITICAL)
        answer = NSRunCriticalAlertPanel(title, @"%@", defaultButton,
                                         alternateButton, otherButton, text);
    else
        answer = NSRunAlertPanel(title, @"%@", defaultButton,
                                 alternateButton, otherButton, text);

    if (isNotification) {
        vlc_dialog_id_dismiss(p_id);
        return;
    }

    switch (answer) {
        case NSAlertDefaultReturn:
            vlc_dialog_id_post_action(p_id, 1);
            break;
        case NSAlertAlternateReturn:
            vlc_dialog_id_post_action(p_id, 2);
            break;
        case NSAlertOtherReturn:
        default:
            vlc_dialog_id_dismiss(p_id);
            break;
    }
}

/* -setup runs on the main thread, inside AppKit's run loop. AppKit catches
 * whatever escapes from there and reports it somewhere we cannot read when
 * the application was started by the Finder -- the failure looks exactly
 * like an application that launched and drew nothing: no window, no menu
 * bar, no log line. That already cost a debugging session on Tiger, where
 * one 10.5-only call in this path silently cost the entire interface. So
 * catch it here, name it in VLC's own log, and let the caller see that the
 * interface is only half-built rather than guess. */
- (void)setup
{
    @try {
        [self setupInterface];
    }
    @catch (NSException *e) {
        msg_Err(p_intf, "interface setup failed: %s: %s",
                [[e name] UTF8String] ?: "?",
                [[e reason] UTF8String] ?: "?");
    }
}

- (void)setupInterface
{
    /* AppKit turns unknown command-line arguments into open-file events,
     * which would add every item twice (libvlc already parses argv) */
    [[NSUserDefaults standardUserDefaults] registerDefaults:
        [NSDictionary dictionaryWithObject:@"NO"
                                    forKey:@"NSTreatUnknownArgumentsAsOpen"]];

    msg_Dbg(p_intf, "setup: menu");
    [menu setupMenu];
    msg_Dbg(p_intf, "setup: main window");
    [mainWindow setupWindow];
    msg_Dbg(p_intf, "setup: fullscreen panel");
    [fsPanel activate];
    msg_Dbg(p_intf, "setup: application delegate");
    [NSApp setDelegate:(id)self];

    /* Apple Remote, media keys and external player control; the remote
     * is grabbed exclusively, so listen only while VLC is the active
     * application (like the modern interface does) */
    [core setupRemoteAndMediaKeys];
    if ([NSApp isActive])
        [core startListeningWithAppleRemote];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationBecameActive:)
               name:NSApplicationDidBecomeActiveNotification
             object:nil];
    [[NSNotificationCenter defaultCenter]
        addObserver:self
           selector:@selector(applicationResignedActive:)
               name:NSApplicationDidResignActiveNotification
             object:nil];

    /* first launch: ask for the metadata network access permission, the
     * same question (and NSUserDefaults key) as the modern interface */
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults objectForKey:@"VLCFirstRun"]) {
        [defaults setObject:[NSDate date] forKey:@"VLCFirstRun"];
        NSInteger answer = NSRunAlertPanel(
            _NS("Check for album art and metadata?"),
            @"%@",
            _NS("Enable Metadata Retrieval"),
            _NS("No, Thanks"),
            nil,
            _NS("VLC can check online for album art and metadata to "
                "enrich your playback experience, e.g. by providing track "
                "information when playing Audio CDs. To provide this "
                "functionality, VLC will send information about your "
                "contents to trusted services in an anonymized form."));
        config_PutInt(p_intf, "metadata-network-access",
                      answer == NSAlertDefaultReturn);
        config_SaveConfigFile(p_intf);
    }
    /* error dialogs land in the Errors and Warnings panel */
    vlc_dialog_provider_set_callbacks(p_intf, &dialog_callbacks, self);
    /* debug helper: open a window at startup, e.g. VLC_LEGACY_SHOW=prefs.
     * The "legacy-macosx-show" option does the same through vlcrc, which is
     * the only way in when the application is started by the Finder: an app
     * launched by LaunchServices inherits loginwindow's environment, not the
     * one of whoever asked for it. That is the whole difference between
     * being able to look at a window on an old machine over SSH and not. */
    char *psz_show_conf = var_InheritString(p_intf, "legacy-macosx-show");
    const char *psz_show = getenv("VLC_LEGACY_SHOW");

    if (psz_show == NULL && psz_show_conf != NULL && *psz_show_conf != '\0')
        psz_show = psz_show_conf;
    if (psz_show && !strncmp(psz_show, "prefs", 5)
     && psz_show[5] >= '0' && psz_show[5] <= '5') {
        [prefs showWindow];
        [prefs performSelector:@selector(debugSelectPane:)
                    withObject:[NSNumber numberWithInt:psz_show[5] - '0']];
    }
    else if (psz_show && !strcmp(psz_show, "prefs"))
        [prefs showWindow];
    else if (psz_show && !strcmp(psz_show, "prefsadv")) {
        [prefs showWindow];
        [prefs performSelector:@selector(toggleAdvanced:) withObject:nil];
    }
    else if (psz_show && !strcmp(psz_show, "prefsadvback")) {
        /* there and back again: the round trip is what used to lose the
         * toolbar buttons, hidden by tag and then unfindable */
        [prefs showWindow];
        [prefs performSelector:@selector(toggleAdvanced:) withObject:nil];
        [prefs performSelector:@selector(toggleAdvanced:) withObject:nil];
    }
    else if (psz_show && !strcmp(psz_show, "fspanel"))
        [fsPanel performSelector:@selector(debugShow)];
    else if (psz_show && !strncmp(psz_show, "prefssub", 8)) {
        /* e.g. VLC_LEGACY_SHOW=prefssub701 renders the core options of
         * subcategory 701 (SUBCAT_PLAYLIST_GENERAL) */
        [prefs showWindow];
        [prefs performSelector:@selector(toggleAdvanced:) withObject:nil];
        [prefs performSelector:@selector(debugShowSubcat:)
                    withObject:[NSNumber numberWithInt:atoi(psz_show + 8)]];
    }
    else if (psz_show && !strcmp(psz_show, "about"))
        [about showAbout];
    else if (psz_show && !strncmp(psz_show, "mediainfo", 9)) {
        [mediaInfo showWindow];
        if (psz_show[9] >= '0' && psz_show[9] <= '2')
            [mediaInfo performSelector:@selector(debugSelectPane:)
                            withObject:[NSNumber numberWithInt:
                                            psz_show[9] - '0']];
    }
    else if (psz_show && !strcmp(psz_show, "bookmarks"))
        [bookmarks showWindow];
    else if (psz_show && !strncmp(psz_show, "effects", 7)) {
        [audioEffects showWindow];
        if (psz_show[7] >= '0' && psz_show[7] <= '7')
            [audioEffects selectPaneAtIndex:psz_show[7] - '0'];
    }
    else if (psz_show && !strncmp(psz_show, "videoeffects", 12)) {
        [videoEffects showWindow];
        if (psz_show[12] >= '0' && psz_show[12] <= '7')
            [videoEffects selectPaneAtIndex:psz_show[12] - '0'];
    }
    else if (psz_show && !strcmp(psz_show, "tracksync"))
        [trackSync showWindow];
    else if (psz_show && !strncmp(psz_show, "convert", 7)) {
        [convertAndSave showWindow];
        if (psz_show[7] == '1')
            [convertAndSave performSelector:@selector(iWantAFile:)
                                 withObject:nil];
        else if (psz_show[7] == '2')
            [convertAndSave performSelector:@selector(iWantAStream:)
                                 withObject:nil];
        else if (psz_show[7] == '3')
            /* opens the app-modal Customize panel (blocks startup) */
            [convertAndSave performSelector:@selector(customizeProfile:)
                                 withObject:nil];
    }
    else if (psz_show && !strcmp(psz_show, "menucheck"))
        [menu performSelector:@selector(debugDumpDynamicMenus)
                   withObject:nil
                   afterDelay:8.0];
    else if (psz_show && !strcmp(psz_show, "messages"))
        [messages showWindow];
    else if (psz_show && !strcmp(psz_show, "errors"))
        [errorPanel showWindow];
    else if (psz_show && !strncmp(psz_show, "open", 4)
          && psz_show[4] >= '0' && psz_show[4] <= '3')
        [open showTab:psz_show[4] - '0'];

    free(psz_show_conf);

    /* debug: VLC_LEGACY_PAUSE_AFTER=<s> pauses playback after a delay,
     * to measure the paused CPU consumption without UI scripting */
    const char *psz_pause = getenv("VLC_LEGACY_PAUSE_AFTER");
    if (psz_pause)
        [core performSelector:@selector(togglePlayPause)
                   withObject:nil
                   afterDelay:atof(psz_pause)];

    /* Debug: render every window into PNG files (works even with the
     * screen locked, unlike screencapture) */
    if (getenv("VLC_LEGACY_SNAPSHOT"))
        [NSTimer scheduledTimerWithTimeInterval:3.0
                                         target:self
                                       selector:@selector(snapshotWindows:)
                                       userInfo:nil
                                        repeats:NO];

    /* Offer to install the Crystal HD driver when the machine has a card but
     * no driver. Deferred rather than run inline: this puts a modal panel on
     * screen, and it should appear over a window that already exists instead
     * of stalling the rest of the setup behind it. */
    [self performSelector:@selector(promptForCrystalHDDriver)
               withObject:nil
               afterDelay:0.5];

    msg_Dbg(p_intf, "setup: done");
}

- (void)promptForCrystalHDDriver
{
    VLCCrystalHDMaybePromptAtStartup();
}



- (void)applicationBecameActive:(NSNotification *)notification
{
    [core startListeningWithAppleRemote];
}

- (void)applicationResignedActive:(NSNotification *)notification
{
    [core stopListeningWithAppleRemote];
}

- (void)shutdown
{
    if ([NSApp delegate] == self)
        [NSApp setDelegate:nil];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [core shutdownAutoHide];
    [core shutdownClipExport];
    [core shutdownRemoteAndMediaKeys];
    vlc_dialog_provider_set_callbacks(p_intf, NULL, NULL);
    [messages shutdown];
    /* 3.0 persists the effect profiles on quit */
    [audioEffects saveCurrentProfileAtTerminate];
    [videoEffects saveCurrentProfileAtTerminate];
    [fsPanel shutdown];
    [mainWindow shutdown];
}

/* debug: recursive menu dump (snapshots cannot capture the menu bar) */
static void dumpMenu(NSMenu *menu, int depth, NSMutableString *tree)
{
    int i;
    for (i = 0; i < [menu numberOfItems]; i++) {
        NSMenuItem *item = [menu itemAtIndex:i];
        int k;
        for (k = 0; k < depth; k++)
            [tree appendString:@"  "];
        if ([item isSeparatorItem]) {
            [tree appendString:@"---\n"];
            continue;
        }
        [tree appendFormat:@"%@%@%@\n", [item title],
            [[item keyEquivalent] length]
                ? [NSString stringWithFormat:@" [key=%@ mask=0x%x]",
                    [item keyEquivalent],
                    (unsigned)[item keyEquivalentModifierMask]]
                : @"",
            [item submenu] ? @" >" : @""];
        if ([item submenu])
            dumpMenu([item submenu], depth + 1, tree);
    }
}

- (void)snapshotWindows:(NSTimer *)timer
{
    const char *psz_dir = getenv("VLC_LEGACY_SNAPSHOT");
    if (!psz_dir)
        return;
    NSString *dir = [NSString stringWithUTF8String:psz_dir];

    NSMutableString *menuTree = [NSMutableString string];
    dumpMenu([NSApp mainMenu], 0, menuTree);
    [menuTree writeToFile:[dir stringByAppendingString:@"/menus.txt"]
               atomically:YES];

    NSArray *windows = [NSApp windows];
    unsigned i;
    for (i = 0; i < [windows count]; i++) {
        NSWindow *w = [windows objectAtIndex:i];
        if (![w isVisible])
            continue;
        NSView *view = [w contentView];
        NSRect bounds = [view bounds];
        if (![view respondsToSelector:
                @selector(bitmapImageRepForCachingDisplayInRect:)])
            continue;   /* 10.4+; the snapshot helper is debug-only */
        NSBitmapImageRep *rep =
            [view bitmapImageRepForCachingDisplayInRect:bounds];
        if (!rep)
            continue;
        [view cacheDisplayInRect:bounds toBitmapImageRep:rep];
        NSData *png = [rep representationUsingType:NSPNGFileType
                                        properties:[NSDictionary dictionary]];
        [png writeToFile:[dir stringByAppendingFormat:@"/win%u.png", i]
              atomically:YES];
        /* dump the view hierarchy with frames for debugging */
        NSMutableString *tree = [NSMutableString string];
        NSMutableArray *stack = [NSMutableArray arrayWithObject:view];
        NSMutableArray *depth = [NSMutableArray arrayWithObject:
            [NSNumber numberWithInt:0]];
        while ([stack count]) {
            NSView *v = [stack objectAtIndex:0];
            int d = [[depth objectAtIndex:0] intValue];
            [stack removeObjectAtIndex:0];
            [depth removeObjectAtIndex:0];
            NSMutableString *pad = [NSMutableString string];
            int k;
            for (k = 0; k < d; k++)
                [pad appendString:@"  "];
            id layer = [v respondsToSelector:@selector(layer)]
                ? [v performSelector:@selector(layer)] : nil;
            [tree appendFormat:@"%@%@ frame=%@ hidden=%d layer=%@\n",
                pad, NSStringFromClass([v class]),
                NSStringFromRect([v frame]), VLCLegacyViewIsHidden(v),
                layer ? [[layer valueForKey:@"frame"] description] : @"none"];
            NSArray *subs = [v subviews];
            unsigned si;
            for (si = 0; si < [subs count]; si++) {
                [stack insertObject:[subs objectAtIndex:si] atIndex:si];
                [depth insertObject:[NSNumber numberWithInt:d + 1]
                            atIndex:si];
            }
        }
        [tree writeToFile:[dir stringByAppendingFormat:@"/win%u.txt", i]
               atomically:YES];
    }
}

/*****************************************************************************
 * NSApplication delegate (informal protocol on 10.4)
 *****************************************************************************/

/* Files opened from the Finder or dropped on the Dock icon */
- (void)application:(NSApplication *)application openFiles:(NSArray *)files
{
    [mainWindow addPaths:files playFirst:YES];
    if ([application respondsToSelector:@selector(replyToOpenOrPrint:)])
        [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)application:(NSApplication *)application openFile:(NSString *)file
{
    [mainWindow addPaths:[NSArray arrayWithObject:file] playFirst:YES];
    return YES;
}

/* Click on the Dock icon with no visible window: bring the playlist back */
- (BOOL)applicationShouldHandleReopen:(NSApplication *)application
                    hasVisibleWindows:(BOOL)hasWindows
{
    if (!hasWindows)
        [mainWindow showWindow];
    return YES;
}

@end
