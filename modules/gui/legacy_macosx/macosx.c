/*****************************************************************************
 * macosx.c: legacy Mac OS X module for vlc
 *****************************************************************************
 * Copyright (C) 2001-2012 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Colin Delacroix <colin@zoy.org>
 *          Eugenio Jarosiewicz <ej0@cise.ufl.edu>
 *          Pierre d'Herbemont <pdherbemont # videolan.org>
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
#include <stdlib.h>                                      /* malloc(), free() */
#include <string.h>

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_window.h>

/*****************************************************************************
 * External prototypes
 *****************************************************************************/
int  OpenIntf     ( vlc_object_t * );
void CloseIntf    ( vlc_object_t * );

int  WindowOpen   ( vout_window_t *, const vout_window_cfg_t * );
void WindowClose  ( vout_window_t * );

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/

static const int legacy_continue_playback_list[] = { 0, 1, 2 };
static const char *const legacy_continue_playback_list_text[] = {
    N_("Ask"), N_("Always"), N_("Never")
};

static const int legacy_itunes_list[] = { 0, 1, 2 };
static const char *const legacy_itunes_list_text[] = {
    N_("Do nothing"), N_("Pause iTunes / Spotify"),
    N_("Pause and resume iTunes / Spotify")
};

/* Apple-DVD-Player-style deinterlacing quality selector. The value maps to a
 * software deinterlacer (VLC's are AltiVec-accelerated on PowerPC, exactly like
 * Apple's own DVDAltivecMADeInterlacer): 0 off, 1 "linear", 2 "auto" (the motion
 * adaptive default), 3 "yadif2x" (double rate). See VLCLegacyMenu.m. */
static const int legacy_deint_list[] = { 0, 1, 2, 3, 4 };
static const char *const legacy_deint_list_text[] = {
    N_("Disabled"), N_("Good quality"),
    N_("Optimal quality"), N_("Best quality"), N_("Custom")
};

vlc_module_begin ()
    /* Minimal interface. see intf.m */
    set_shortname( "Legacy Macosx" )
    add_shortcut( "legacy_macosx", "losx" )
    set_description( N_("Legacy Mac OS X interface") )
    set_capability( "interface", 50 )
    set_callbacks( OpenIntf, CloseIntf )
    set_category( CAT_INTERFACE )
    set_subcategory( SUBCAT_INTERFACE_MAIN )
    add_bool( "legacy-macosx-dark", false,
              N_("Run VLC with dark interface style"),
              N_("If this option is enabled, VLC will use the dark interface "
                 "style. Otherwise, the grey interface style is used."),
              false )
    /* Dropping the drop shadow while video plays was measured to help on
     * 10.4: one windowed frame in three was late with it, and the flushes
     * showed up as a storm of window-surface remaps.
     * ⚠ The explanation long written next to that measurement -- the window
     * server recomputing the shadow on every frame -- does not survive
     * inspection: that recomputation is a property of NON-OPAQUE windows,
     * whose shadow is derived from the content alpha, and neither the main
     * window nor the vout window is ever made non-opaque here (only the
     * HUD/tooltip panels are). Nor is the machine it was measured on
     * recorded anywhere. So: real symptom, unexplained cause.
     * The shadow is what detaches a window from the desktop, and a video
     * window without one looks pasted onto it, so only the PowerPC slice
     * built without AltiVec -- the G3 one -- defaults to off; the checkbox
     * in the interface preferences flips it either way. */
#if (defined(__ppc__) || defined(__ppc64__) || defined(__POWERPC__)) \
 && !defined(HAVE_ALTIVEC_H)
# define LEGACY_SHADOWS_DEFAULT false
#else
# define LEGACY_SHADOWS_DEFAULT true
#endif
    add_bool( "legacy-macosx-window-shadows", LEGACY_SHADOWS_DEFAULT,
              N_("Draw window shadows"),
              N_("Keep the drop shadow under the video windows, which is "
                 "what visually detaches them from the desktop. The window "
                 "server recomputes that shadow on every video frame: on "
                 "the slowest Macs this costs enough displayed frames to be "
                 "worth turning off, which is why it is off by default "
                 "there."),
              false )
    /* View menu toggles, mirroring the modern interface options (their
     * own names: a config option may only be declared by one module) */
    add_bool( "legacy-macosx-show-playback-buttons", false,
              N_("Show Previous & Next Buttons"),
              N_("Shows the previous and next buttons in the main window."),
              false )
    add_bool( "legacy-macosx-show-playmode-buttons", false,
              N_("Show Shuffle & Repeat Buttons"),
              N_("Shows the shuffle and repeat buttons in the main window."),
              false )
    add_bool( "legacy-macosx-show-effects-button", false,
              N_("Show Audio Effects Button"),
              N_("Shows the audio effects button in the main window."),
              false )
    /* VLC 3.0 simple-preferences parity; the modern module owns the
     * macosx-* names, so these carry the legacy- prefix (same texts,
     * translations already exist) */
    add_integer( "legacy-macosx-continue-playback", 0,
              N_("Continue playback where you left off"),
              N_("VLC will store playback positions of the last 30 items "
                 "you played. If you re-open one of those, playback will "
                 "continue."),
              false )
        change_integer_list( legacy_continue_playback_list,
                             legacy_continue_playback_list_text )
    add_bool( "legacy-macosx-pause-minimized", false,
              N_("Pause the video playback when minimized"),
              N_("With this option enabled, the playback will be "
                 "automatically paused when minimizing the window."),
              false )
    add_bool( "legacy-macosx-hide-controls", false,
              N_("Hide controls during playback"),
              N_("In windowed playback, hide the controls bar and the "
                 "window title bar after a few seconds once the mouse has "
                 "left the window, leaving only the video. Double-click "
                 "the video to bring them back; keyboard shortcuts keep "
                 "working and show the fullscreen-style OSD meanwhile."),
              false )
    /* The preview costs a full secondary decode. Measured on the iBook
     * G3 600 MHz: ~3-4 s alone and ~10 s during playback, with the
     * playback visibly stuttering meanwhile — every PowerPC build
     * therefore ships with it off; the checkbox in the interface
     * preferences turns it back on. */
#if defined(__ppc__) || defined(__ppc64__) || defined(__POWERPC__)
# define HOVER_THUMBNAILS_DEFAULT false
#else
# define HOVER_THUMBNAILS_DEFAULT true
#endif
    add_bool( "legacy-macosx-hover-thumbnails", HOVER_THUMBNAILS_DEFAULT,
              N_("Show a preview image when hovering the seek bar"),
              N_("Render a small preview of the hovered position in the "
                 "seek bar tooltip. The preview is decoded by a second, "
                 "silent input: on slow machines it can take several "
                 "seconds to appear and steal cycles from the playback; "
                 "disable it there."),
              false )
    add_integer( "legacy-macosx-vdev", 0,
              N_("Video device"),
              N_("Number of the screen to use by default to display videos "
                 "in 'fullscreen'. The screen number correspondance can be "
                 "found in the video device selection menu."),
              false )
    /* Chantier F — la vidéo intégrée vit dans une FENÊTRE ENFANT sans bordure
     * plutôt que directement dans la fenêtre principale. Le plein écran devient
     * un simple redimensionnement de cette fenêtre : son numéro CGS ne change
     * jamais, donc la sortie vidéo accélérée (surface liée à ce numéro) n'a pas
     * à être réouverte — bascule instantanée, sans image noire. Repli prévu au
     * cas où le comportement des fenêtres enfants de 10.4 poserait problème. */
    add_bool( "legacy-macosx-childvideo", true,
              N_("Embedded video in a child window"),
              N_("Host the embedded video in a borderless child window: "
                 "switching to fullscreen is instant and does not interrupt "
                 "accelerated decoding. Turning this off restores the former "
                 "behaviour (a separate fullscreen window). No effect under "
                 "Mac OS X 10.4, where a child window displays nothing."),
              true )
    /* Debug affordance, mirroring VLC_LEGACY_SHOW: names a window to open at
     * startup (prefs, prefsadv, mediainfo, errors, about, bookmarks...). An
     * application started by the Finder inherits loginwindow's environment,
     * so the variable never reaches it -- this is the way in. */
    add_string( "legacy-macosx-show", "",
                N_("Open a window at startup (debugging)"),
                N_("Name of the window to open at startup, like the "
                   "VLC_LEGACY_SHOW environment variable: prefs, "
                   "prefsadv, mediainfo, errors, about, bookmarks, "
                   "messages, tracksync, effects, videoeffects, convert, "
                   "fspanel, open0..3."),
                true )
    add_bool( "legacy-macosx-black", false,
              N_("Black screens in fullscreen"),
              N_("In fullscreen mode, keep screen where there is no video "
                 "displayed black"),
              false )
    /* Apple Remote / media keys / external players, same texts as the
     * modern module (translations already exist) but legacy- prefixed
     * names, as a config option may only be declared by one module */
    add_bool( "legacy-macosx-appleremote", true,
              N_("Control playback with the Apple Remote"),
              N_("By default, VLC can be remotely controlled with the "
                 "Apple Remote."),
              false )
    add_bool( "legacy-macosx-appleremote-sysvol", false,
              N_("Control system volume with the Apple Remote"),
              N_("By default, VLC will control its own volume with the "
                 "Apple Remote. However, you can choose to control the "
                 "global system volume instead."),
              false )
    add_bool( "legacy-macosx-mediakeys", true,
              N_("Control playback with media keys"),
              N_("By default, VLC can be controlled using the media keys "
                 "on modern Apple keyboards."),
              false )
    add_integer( "legacy-macosx-control-itunes", 1,
              N_("Control external music players"),
              N_("VLC will pause and resume supported music players on "
                 "playback."),
              false )
        change_integer_list( legacy_itunes_list, legacy_itunes_list_text )
/* Deinterlacing costs a full software filter pass per picture, and VLC's are
 * AltiVec-accelerated -- exactly like Apple's own DVDAltivecMADeInterlacer.
 * A slice built without AltiVec runs them scalar, and a G3 cannot sustain
 * that at DVD resolution: the picture stutters instead of being merely
 * combed. So those machines default to Off, the way Apple's DVD Player
 * greys out what a given model cannot do. Everything else keeps "Optimal";
 * the setting stays fully user-changeable either way. */
#if (defined(__ppc__) || defined(__ppc64__) || defined(__POWERPC__)) \
 && !defined(HAVE_ALTIVEC_H)
# define LEGACY_DEINT_DEFAULT 0
#else
# define LEGACY_DEINT_DEFAULT 2
#endif

    add_integer( "legacy-macosx-deinterlace", LEGACY_DEINT_DEFAULT,
              N_("Deinterlacing"),
              N_("Removes the interlacing combing from interlaced video such "
                 "as most PAL DVDs. Higher settings look better but use more "
                 "CPU. \"Best quality\" is offered only on Macs fast enough "
                 "for it (G5, Intel, Apple Silicon), exactly as Apple's DVD "
                 "Player greys it out on slower models."),
              false )
        change_integer_list( legacy_deint_list, legacy_deint_list_text )

    add_submodule ()
    /* Will be loaded even without interface module. see voutgl.m */
        set_description( "Legacy Mac OS X Video Output Provider" )
        set_capability( "vout window", 50 )
        set_callbacks( WindowOpen, WindowClose )
vlc_module_end ()

