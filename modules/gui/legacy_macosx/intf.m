/*****************************************************************************
 * intf.m: macOS legacy interface module
 *****************************************************************************
 * Copyright (C) 2002-2017 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan.org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
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

/*****************************************************************************
 * Preamble
 *****************************************************************************/
#import <stdlib.h>
#import <string.h>
#import <unistd.h>

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import <vlc_common.h>
#import <vlc_playlist.h>
#import <vlc_interface.h>
#import <vlc_vout_window.h>
/* VOUT_WINDOW_STATE_ABOVE lives here, not in vlc_vout_window.h */
#import <vlc_vout_display.h>

#import "VLCLegacyVoutWindow.h"
#import "VLCLegacyMain.h"
#import "VLCLegacyMainWindow.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyControls.h"

/* The vout window provider (a submodule sharing this plugin) needs to reach
 * the interface controller; a plain global is enough, both live and die
 * with the module. */
static VLCLegacyMain *g_legacyMain = nil;

/* Used by the standalone vout window for the VLC 3.0 pointer/keyboard
 * behaviors (double-click fullscreen, Space, Escape). */
VLCLegacyCoreInteraction *VLCLegacyGetCore(void)
{
    return [g_legacyMain coreInteraction];
}

/* Used by the core interaction when the core asks for the auto-hidden
 * controls to come back (double click on the video). */
VLCLegacyMainWindow *VLCLegacyGetMainWindow(void)
{
    return [g_legacyMain mainWindowController];
}

/*****************************************************************************
 * Local prototypes.
 *****************************************************************************/
static void Run (intf_thread_t *p_intf);

/*****************************************************************************
 * OpenIntf: initialize interface
 *****************************************************************************/
int OpenIntf (vlc_object_t *p_this)
{
    intf_thread_t *p_intf = (intf_thread_t*) p_this;
    msg_Dbg(p_intf, "Using legacy macosx interface");

    p_intf->p_sys = NULL;

    VLCLegacySetDarkMode(var_InheritBool(p_intf, "legacy-macosx-dark"));

    /* Native macOS full screen (Lion's green-button fullscreen) is a
     * modern-interface feature and must never engage under the legacy UI,
     * whose fullscreen is the custom borderless path in VLCLegacyVoutWindow
     * / -setVideoFullscreenFromNumber:. The "macosx-nativefullscreenmode"
     * bool is owned by the modern module and stored in the shared config
     * file, so a user who turned it on there would otherwise carry it into a
     * legacy session (e.g. a modern vout window loaded as --extraintf).
     * Shadow it to false on the libvlc instance — the common ancestor every
     * var_Inherit() walks before falling back to the config — for the whole
     * session, WITHOUT calling config_Put*(): the saved preference is left
     * untouched and restored the next time the modern UI runs.
     *
     * This alone is NOT enough to keep the green button from entering
     * native full screen: the variable only governs code that reads it,
     * while modern AppKit grants EVERY resizable window the native
     * fullscreen behaviour by default. Each legacy window additionally
     * refuses it through VLCLegacyDenyNativeFullscreen() (misc.m). */
    var_Create(p_intf->obj.libvlc, "macosx-nativefullscreenmode", VLC_VAR_BOOL);
    var_SetBool(p_intf->obj.libvlc, "macosx-nativefullscreenmode", false);

    Run(p_intf);

    /* Menu, main window and dialogs: built on the main thread, owned
     * through p_sys */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    VLCLegacyMain *main = [[VLCLegacyMain alloc] initWithIntf:p_intf];
    [main performSelectorOnMainThread:@selector(setup)
                           withObject:nil
                        waitUntilDone:YES];
    p_intf->p_sys = (intf_sys_t *)main;
    g_legacyMain = main;
    [pool release];

    return VLC_SUCCESS;
}

/*****************************************************************************
 * CloseIntf: destroy interface
 *****************************************************************************/
void CloseIntf (vlc_object_t *p_this)
{
    intf_thread_t *p_intf = (intf_thread_t*) p_this;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    /* This module also provides the vout windows, and those message our
     * controllers from the input thread. Stop playback and join the
     * playlist thread BEFORE tearing the interface down, so every vout
     * window is closed while its controller is still alive. Without this,
     * quitting during playback crashes in WindowClose() once libvlc
     * destroys the playlist after the interface (the Qt interface calls
     * this in its Close for the same reason). */
    playlist_Deactivate(pl_Get(p_intf));

    VLCLegacyMain *main = (VLCLegacyMain *)p_intf->p_sys;
    g_legacyMain = nil;
    /* UI teardown must happen on the main thread (AppKit aborts otherwise) */
    [main performSelectorOnMainThread:@selector(shutdown)
                           withObject:nil
                        waitUntilDone:YES];
    [main release];
    p_intf->p_sys = NULL;
    [pool release];
}

/* Dock Connection */
typedef struct CPSProcessSerNum
{
        UInt32                lo;
        UInt32                hi;
} CPSProcessSerNum;

extern OSErr    CPSGetCurrentProcess(CPSProcessSerNum *psn);
extern OSErr    CPSEnableForegroundOperation(CPSProcessSerNum *psn, UInt32 _arg2, UInt32 _arg3, UInt32 _arg4, UInt32 _arg5);
extern OSErr    CPSSetFrontProcess(CPSProcessSerNum *psn);


/*****************************************************************************
 * Run: main loop
 *****************************************************************************/
static void Run(intf_thread_t *p_intf)
{
    CPSProcessSerNum PSN;
    /* Manual autorelease pool: @autoreleasepool lowers to runtime calls
     * (objc_autoreleasePoolPush) missing before Mac OS X 10.7, and this
     * module is only built when targeting releases without them. Same
     * reasoning for the manual retain/release throughout this file: ARC
     * requires the 10.6 runtime. */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [NSApplication sharedApplication];
    if (!CPSGetCurrentProcess(&PSN))
        if (!CPSEnableForegroundOperation(&PSN,0x03,0x3C,0x2C,0x1103))
            if (!CPSSetFrontProcess(&PSN))
                [NSApplication sharedApplication];
    [pool release];
}

/*****************************************************************************
 * Vout window management
 *****************************************************************************/
static int WindowControl(vout_window_t *, int i_query, va_list);

/* AppKit windows must be created and torn down on the main thread; blocks
 * and GCD being unavailable, marshal through performSelectorOnMainThread. */
@interface VLCLegacyWindowFactory : NSObject
{
@public
    NSRect rect;
    BOOL decorated;
    VLCLegacyVoutWindow *window;
}
- (void)createWindow;
@end

@implementation VLCLegacyWindowFactory
- (void)createWindow
{
    window = [[VLCLegacyVoutWindow alloc] initWithContentRect:rect
                                                    decorated:decorated];
    [window makeKeyAndOrderFront:nil];
}
@end

static int WindowControlEmbedded(vout_window_t *, int i_query, va_list);

/* Main-thread trampoline: acquires the main window's embedded video view */
@interface VLCLegacyEmbedRequest : NSObject
{
@public
    VLCLegacyMainWindow *controller;
    NSView *view;
}
- (void)acquire;
@end

@implementation VLCLegacyEmbedRequest
- (void)acquire
{
    view = [controller acquireVideoView];
}
@end

int WindowOpen(vout_window_t *p_wnd, const vout_window_cfg_t *cfg)
{
    if (cfg->type != VOUT_WINDOW_TYPE_INVALID
     && cfg->type != VOUT_WINDOW_TYPE_NSOBJECT)
        return VLC_EGENERIC;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    /* ⚠ « Afficher la vidéo dans la fenêtre principale » (embedded-video) ET
     * « Décorations de la fenêtre » (video-deco) n'étaient lues QUE par
     * l'interface moderne : côté legacy, les deux cases se décochaient sans
     * rien changer, la vidéo étant toujours embarquée.
     * ⚠ C'est « embedded-video » qui DÉCIDE, et elle seule :
     *   - cochée (défaut) ⇒ vidéo dans la fenêtre principale, et « video-deco »
     *     n'a alors rien à décorer (pas de fenêtre vidéo à elle) ;
     *   - décochée ⇒ fenêtre séparée, décorée ou non selon « video-deco ».
     * L'interface moderne, elle, laisse « video-deco » décochée l'emporter et
     * détacher la vidéo quoi qu'il arrive : recocher « afficher dans la fenêtre
     * principale » ne produisait alors RIEN, ce qui se lit comme une panne. */
    bool b_deco = var_InheritBool(p_wnd, "video-deco");
    VLCLegacyMainWindow *controller =
        var_InheritBool(p_wnd, "embedded-video")
            ? [g_legacyMain mainWindowController] : nil;
    if (controller) {
        VLCLegacyEmbedRequest *request =
            [[VLCLegacyEmbedRequest alloc] init];
        request->controller = controller;
        [request performSelectorOnMainThread:@selector(acquire)
                                  withObject:nil
                               waitUntilDone:YES];
        NSView *view = request->view;
        [request release];

        if (view) {
            p_wnd->handle.nsobject = (void *)[view retain];
            p_wnd->type = VOUT_WINDOW_TYPE_NSOBJECT;
            /* Retained: the window can outlive the interface during
             * shutdown, and WindowControl()/WindowClose() message the
             * controller from the input thread */
            p_wnd->sys = (void *)[controller retain];
            p_wnd->control = WindowControlEmbedded;
            [pool release];
            vout_window_SetFullScreen(p_wnd, cfg->is_fullscreen);
            return VLC_SUCCESS;
        }
    }

    /* Fenêtre vidéo autonome : une des deux cases ci-dessus décochée, deuxième
     * vout simultané, ou interface en cours d'extinction. */

    VLCLegacyWindowFactory *factory = [[VLCLegacyWindowFactory alloc] init];
    factory->rect = NSMakeRect(cfg->x, cfg->y, cfg->width, cfg->height);
    factory->decorated = b_deco;
    [factory performSelectorOnMainThread:@selector(createWindow)
                              withObject:nil
                           waitUntilDone:YES];
    VLCLegacyVoutWindow *o_window = factory->window;
    [factory release];

    if (!o_window) {
        msg_Err(p_wnd, "window creation failed");
        [pool release];
        return VLC_EGENERIC;
    }

    msg_Dbg(p_wnd, "returning video window with proposed position x=%i, y=%i, width=%i, height=%i", cfg->x, cfg->y, cfg->width, cfg->height);
    /* ⚠ PAS le contentView : la fenêtre décorée lui réserve la bande du bas
     * pour sa barre de contrôles allégée, et la surface accélérée du vout,
     * qui remplit son parent, la recouvrirait. La fenêtre (créée avec un +1
     * ci-dessus, relâchée à sa fermeture) reste retrouvable depuis cette vue
     * dans WindowControl()/WindowClose(). */
    p_wnd->handle.nsobject = (void *)[[o_window videoView] retain];

    p_wnd->type = VOUT_WINDOW_TYPE_NSOBJECT;
    p_wnd->control = WindowControl;

    [pool release];

    vout_window_SetFullScreen(p_wnd, cfg->is_fullscreen);
    return VLC_SUCCESS;
}

static int WindowControl(vout_window_t *p_wnd, int i_query, va_list args)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSWindow* o_window = [(id)p_wnd->handle.nsobject window];
    if (!o_window) {
        msg_Err(p_wnd, "failed to recover cocoa window");
        [pool release];
        return VLC_EGENERIC;
    }

    int i_ret;
    switch (i_query) {
        case VOUT_WINDOW_SET_STATE:
        {
            unsigned i_state = va_arg(args, unsigned);

            /* AppKit aborts on window manipulation off the main thread */
            [(VLCLegacyVoutWindow*)o_window
                performSelectorOnMainThread:@selector(setLevelFromNumber:)
                                 withObject:[NSNumber numberWithUnsignedInt:i_state]
                              waitUntilDone:NO];

            i_ret = VLC_SUCCESS;
            break;
        }
        case VOUT_WINDOW_SET_SIZE:
        {
            unsigned int i_width  = va_arg(args, unsigned int);
            unsigned int i_height = va_arg(args, unsigned int);
            NSValue *size = [NSValue valueWithSize:NSMakeSize(i_width, i_height)];
            [(VLCLegacyVoutWindow*)o_window
                performSelectorOnMainThread:@selector(setSizeFromValue:)
                                 withObject:size
                              waitUntilDone:NO];
            i_ret = VLC_SUCCESS;
            break;
        }
        case VOUT_WINDOW_SET_FULLSCREEN:
        {
            int i_full = va_arg(args, int);
            [(VLCLegacyVoutWindow*)o_window
                performSelectorOnMainThread:(i_full ? @selector(enterFullscreen)
                                                    : @selector(leaveFullscreen))
                                 withObject:nil
                              waitUntilDone:NO];
            i_ret = VLC_SUCCESS;
            break;
        }
        case VOUT_WINDOW_HIDE_MOUSE:
        {
            /* ★ Masquage du pointeur pendant la lecture. Le coeur envoie ICI
             * les DEUX sens (masquer après inactivité, réafficher au retour de
             * la souris), ce qui permet un masquage FERME au niveau de
             * l'écran : `-[NSCursor setHiddenUntilMouseMoves:]`, essayé côté
             * vout, ne tenait pas en plein écran (annulé aussitôt par les
             * événements de souris internes, panneau de contrôles compris).
             * CGDisplayHide/ShowCursor, lui, n'est levé que par nous.
             * ⚠ Les appels s'empilent : ne jamais masquer/démasquer deux fois
             * de suite, sinon le pointeur ne revient plus. */
            (void) va_arg(args, int);   /* décidé par le sondage, cf. intf.m */
            i_ret = VLC_SUCCESS;
            break;
        }
        default:
            msg_Warn(p_wnd, "unsupported control query");
            i_ret = VLC_EGENERIC;
            break;
    }

    [pool release];
    return i_ret;
}

/* ★ MASQUAGE DU POINTEUR pendant la lecture (10.3).
 * `-[NSCursor setHiddenUntilMouseMoves:]`, essayé d'abord côté vout, ne tient
 * pas en plein écran : il est annulé aussitôt par les événements de souris
 * internes. On masque donc au niveau de l'ÉCRAN (CGDisplayHideCursor), ce que
 * rien d'autre ne lève — mais il faut alors le lever nous-mêmes. Le coeur ne
 * demande le retour du pointeur que s'il voit passer les événements souris, ce
 * qui n'est pas le cas en plein écran ; c'est le sondage du panneau de
 * contrôles (VLCLegacyFSPanel -poll:) qui détecte le mouvement et appelle
 * VLCLegacyCursorActivity(). ⚠ Les appels CGDisplayHide/ShowCursor s'empilent :
 * l'état est gardé ici pour ne jamais les déséquilibrer (sinon pointeur perdu).
 */
static bool b_vlc_cursor_hidden = false;

void VLCLegacyCursorSetHidden(bool b_hide);
void VLCLegacyCursorActivity(void);

void VLCLegacyCursorSetHidden(bool b_hide)
{
    if (b_hide == b_vlc_cursor_hidden)
        return;
    if (b_hide)
        CGDisplayHideCursor(kCGDirectMainDisplay);
    else
        CGDisplayShowCursor(kCGDirectMainDisplay);
    b_vlc_cursor_hidden = b_hide;
}

void VLCLegacyCursorActivity(void)
{
    VLCLegacyCursorSetHidden(false);
}

/* ⚠ Le coeur ne peut PAS être l'arbitre du masquage : il ne voit pas passer
 * les événements souris en plein écran, donc il croit le pointeur masqué pour
 * toujours et ne redemande plus rien — on se retrouvait avec un pointeur figé
 * dans un sens ou dans l'autre. On accuse donc réception de sa requête sans
 * rien faire, et c'est le sondage du panneau plein écran
 * (VLCLegacyFSPanel -poll:) qui décide seul, masquage ET démasquage. */

static int WindowControlEmbedded(vout_window_t *p_wnd, int i_query,
                                 va_list args)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    VLCLegacyMainWindow *controller = (VLCLegacyMainWindow *)p_wnd->sys;
    int i_ret = VLC_SUCCESS;

    switch (i_query) {
        case VOUT_WINDOW_SET_STATE:
        {
            /* Video > Float on Top. Dropping this query is what made that
             * entry do nothing: the embedded picture lives in the main
             * window, so floating above the other applications is that
             * window's LEVEL, not a property of a vout of its own. */
            unsigned i_state = va_arg(args, unsigned);
            [controller
                performSelectorOnMainThread:@selector(setVideoAboveOthersFromNumber:)
                                 withObject:[NSNumber numberWithBool:
                                     i_state == VOUT_WINDOW_STATE_ABOVE]
                              waitUntilDone:NO];
            break;
        }
        case VOUT_WINDOW_SET_SIZE:
        {
            unsigned int i_width  = va_arg(args, unsigned int);
            unsigned int i_height = va_arg(args, unsigned int);
            NSValue *size =
                [NSValue valueWithSize:NSMakeSize(i_width, i_height)];
            [controller
                performSelectorOnMainThread:@selector(setVideoViewSizeFromValue:)
                                 withObject:size
                              waitUntilDone:NO];
            break;
        }
        case VOUT_WINDOW_SET_FULLSCREEN:
        {
            int i_full = va_arg(args, int);
            [controller
                performSelectorOnMainThread:@selector(setVideoFullscreenFromNumber:)
                                 withObject:[NSNumber numberWithBool:i_full != 0]
                              waitUntilDone:NO];
            break;
        }
        case VOUT_WINDOW_HIDE_MOUSE:
        {
            /* ★ Même masquage que pour la fenêtre autonome (cf. plus haut) :
             * c'est CE chemin qu'emprunte l'interface legacy, qui embarque la
             * vidéo dans sa fenêtre principale. */
            (void) va_arg(args, int);   /* décidé par le sondage, cf. intf.m */
            break;
        }
        default:
            msg_Warn(p_wnd, "unsupported control query");
            i_ret = VLC_EGENERIC;
            break;
    }

    [pool release];
    return i_ret;
}

void WindowClose(vout_window_t *p_wnd)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    if (p_wnd->sys) {
        /* embedded in the main window */
        VLCLegacyMainWindow *controller = (VLCLegacyMainWindow *)p_wnd->sys;
        [controller performSelectorOnMainThread:@selector(releaseVideoView)
                                     withObject:nil
                                  waitUntilDone:NO];
        /* balances the retain in WindowOpen() */
        [(id)p_wnd->handle.nsobject
            performSelectorOnMainThread:@selector(release)
                             withObject:nil
                          waitUntilDone:NO];
        /* balances the controller retain in WindowOpen(); queued after
         * releaseVideoView so it executes once that call is done */
        [controller performSelectorOnMainThread:@selector(release)
                                     withObject:nil
                                  waitUntilDone:NO];
        [pool release];
        return;
    }

    NSView *o_view = (id)p_wnd->handle.nsobject;
    NSWindow *o_window = [o_view window];
    if (o_window)
        /* -close releases the window (releasedWhenClosed defaults to YES
         * for windows created programmatically). */
        [o_window performSelectorOnMainThread:@selector(close)
                                   withObject:nil
                                waitUntilDone:NO];
    /* Balances the retain in WindowOpen(); deferred to the main thread so
     * the view outlives the pending close above. */
    [o_view performSelectorOnMainThread:@selector(release)
                             withObject:nil
                          waitUntilDone:NO];
    [pool release];
}
