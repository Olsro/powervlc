/*****************************************************************************
 * VLCLegacyMainWindow.h: main window for the legacy Mac OS X interface
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

/* NSInteger only appeared with the 10.5 SDK; the 10.4 toolchain needs the
 * historical definitions (32-bit only, which is all 10.4 GUIs ever were) */
#ifndef NSINTEGER_DEFINED
typedef int NSInteger;
typedef unsigned int NSUInteger;
#define NSINTEGER_DEFINED 1
#endif
#ifndef CGFLOAT_DEFINED
typedef float CGFloat;
#define CGFLOAT_DEFINED 1
#endif

@class VLCLegacyCoreInteraction;
@class VLCLegacyArtImageView;

/* Black view hosting the video output inside the main window. Replicates
 * the VLC 3.0 window behaviors: double-click toggles fullscreen, Space
 * pauses, Escape leaves fullscreen. */
@interface VLCLegacyVideoView : NSView
{
@public
    VLCLegacyCoreInteraction *core;   /* weak, owned by the controller */
}
@end

/* Programmatic port of the VLCMainWindow concept: transport controls, thin
 * time slider, sidebar plus flat playlist table, dropzone when empty, and
 * embedded video. Everything is built in code — nib files produced by
 * modern Xcode cannot be loaded by Mac OS X 10.4 — and uses autoresizing
 * masks only (no Auto Layout, 10.7+). */
@interface VLCLegacyMainWindow : NSObject
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;

    NSWindow *window;
    NSButton *previousButton;       /* extra prev (jump-buttons mode) */
    NSButton *backwardButton;       /* combined prev/seek (3.0 semantics) */
    NSButton *playButton;
    NSButton *forwardButton;        /* combined next/seek */
    NSButton *nextButton;           /* extra next (jump-buttons mode) */
    NSButton *stopButton;
    /* combined-button click-vs-hold state (VLCControlsBarCommon port) */
    BOOL justTriggeredNext;
    BOOL justTriggeredPrevious;
    double lastForwardEvent;
    double lastBackwardEvent;
    NSButton *viewToggleButton;
    NSButton *shuffleButton;        /* View > Show Shuffle & Repeat */
    NSButton *repeatButton;
    NSButton *effectsButton;        /* View > Show Audio Effects Button */
    NSButton *muteButton;
    NSButton *volumeMaxButton;
    NSButton *fullscreenButton;
    NSTextField *durationField;     /* single field: elapsed or remaining,
                                     * clicked to toggle (VLCTimeField) */
    BOOL showTimeRemaining;
    NSPanel *jumpPanel;             /* "Jump to Time", on double-click */
    NSTextField *jumpField;
    NSSlider *seekSlider;
    /* chapter separators cache: refetched when any of these change (an
     * input pointer alone can be reused by a fresh allocation), and
     * retried while it has yielded nothing (chaptersRetryTicks) */
    char *chaptersUri;      /* identité du média, cf. .m */
    int chaptersTitle;
    int64_t chaptersDuration;
    int chaptersRetryTicks;
    NSSlider *volumeSlider;

    NSSplitView *splitView;
    NSTableView *sidebarTable;
    NSView *sidebarPane;            /* retained: View > Show Sidebar
                                     * (scroll view + cover art) */
    NSScrollView *sidebarScroll;    /* retained */
    VLCLegacyArtImageView *sidebarArtView; /* cover art of the playing item,
                                     * bottom of the sidebar (Qt parity) */
    NSView *sidebarArtDivider;      /* draggable handle to resize the art */
    CGFloat artPanelHeight;         /* user-set art height, persisted */
    NSString *sidebarArtUrl;        /* URL currently shown, "" for none */
    NSView *rightContainer;
    NSOutlineView *playlistTable;
    NSScrollView *playlistScroll;
    NSView *dropzoneView;
    NSTextField *viewTitleLabel;
    NSTextField *searchField;   /* an NSSearchField except on 10.2 */
    /* Subscribe / Unsubscribe strip, shown at the bottom of the playlist
     * area while the Podcasts service is selected (3.0 parity) */
    NSView *podcastBar;
    NSButton *podcastRemoveButton;  /* disabled while nothing is subscribed */
    BOOL podcastBarVisible;
    NSString *searchString;
    NSString *searchStringFolded;   /* accent/case-folded, see vlc_strfold */
    NSMutableArray *visibleColumns; /* playlist column identifiers */

    /* embedded video */
    VLCLegacyVideoView *videoView;
    /* L'utilisateur a demandé la LISTE DE LECTURE pendant la lecture : à
     * respecter à chaque (re)démarrage de vout, sinon la vidéo reprend le
     * dessus toute seule (transitions de menus, engagement matériel…). */
    BOOL playlistViewWanted;
    NSWindow *fsVideoWindow;
    BOOL videoActive;
    /* Chantier F — fenêtre ENFANT hébergeant la vidéo intégrée (option
     * legacy-macosx-childvideo). Elle existe tant que la vidéo est active et
     * son numéro CGS ne change JAMAIS : le plein écran n'est plus qu'un
     * redimensionnement, donc la surface du décodeur accéléré reste valable
     * (pas de réouverture du décodeur, pas d'image noire). nil = ancien
     * comportement (la vidéo est une sous-vue de la fenêtre principale et le
     * plein écran crée fsVideoWindow). */
    NSWindow *videoHostWindow;
    BOOL videoHostFullscreen;
    NSRect videoHostWindowedFrame;
    /* Cadre RÉEL de la vue vidéo juste avant le passage en plein écran, pour le
     * restituer tel quel au retour. Le cadre du splitView, utilisé jusqu'ici,
     * avait entre-temps rétréci (mesuré : 1024x576 au démarrage de la vidéo,
     * 690x404 à la sortie du plein écran) : la vidéo revenait tassée dans un
     * coin, le reste du cadre en blanc. */
    NSRect preFullscreenVideoFrame;

    /* Snapshot of the core playlist (tree of dictionaries with keys
     * "id" (NSNumber), "title", "duration", "arturl" and, for nodes,
     * "children" (array of the same)); the outline view never touches
     * the playlist directly during drawing. */
    NSMutableArray *items;
    NSMutableSet *expandedItemIds;       /* ids kept open across reloads */
    NSMutableDictionary *artworkCache;   /* arturl -> NSImage */
    NSArray *draggedItems;               /* snapshot dicts being dragged
                                          * (VLCPLModel _draggedItems port) */

    /* sidebar model: dictionaries {kind: header|playlist|ml|sd, title,
     * sd (module name), longname} */
    NSMutableArray *sidebarItems;
    NSMutableSet *activatedServices;     /* sd names already added */
    int sidebarSelection;                /* selected row in sidebarItems */
    NSTimer *updateTimer;
    BOOL playing;
    int currentItemId;      /* playlist id of the playing item (bold row) */
    int refreshTicks;       /* safety-net counter for snapshot rebuilds */
    int lastSeenChangeCount;/* playlist change burst detection */
    int burstTicks;         /* ticks since the current burst started */
    NSMutableDictionary *browseRequestedIds; /* id -> NSDate of the last
                                        * expand-to-browse preparse; lets a
                                        * failed directory be retried once
                                        * the request is surely over */
    BOOL searchFlagsWereSet;           /* core-side search flags are up, so
                                        * an emptied search must clean them */
    NSMutableDictionary *dirCheckCache;/* path -> NSNumber(isDirectory) */

    NSMutableDictionary *fileSizeCache;  /* path -> formatted size */
    BOOL lastShuffleOn;                  /* shuffle button artwork state */
    int lastRepeatState;                 /* 0 none, 1 all, 2 one; -1 unset */

    /* "Continue playback where you left off" (VLC 3.0 parity, driven by
     * legacy-macosx-continue-playback; same NSUserDefaults keys as 3.0) */
    NSString *resumeTrackedURI;          /* input being tracked */
    int64_t resumeLastTime;              /* µs, last observed position */
    int64_t resumeLastLength;            /* µs */
    BOOL resumeHandled;                  /* offer already made for input */

    /* Pause the video playback when minimized */
    BOOL pausedByMiniaturize;

    /* "Hide controls during playback" (Video menu, driven by the
     * legacy-macosx-hide-controls option). Poll-based: the refresh tick
     * watches the mouse against the window frame — 10.2 has no better
     * primitive and the 3 s delay does not need one. While hidden the
     * window is shrunk onto the aspect-corrected picture; the title bar
     * can only go away where -setStyleMask: exists (10.6+, so on the
     * modern machines the legacy interface is tested on — the PowerPC
     * systems keep their title bar, only the controls bar goes). */
    NSView *bottomBar;                   /* weak: owned by contentView */
    BOOL controlsHiddenForPlayback;
    double mouseOutsideSince;            /* 0 = mouse inside / not armed */
    int autoHideRevealTicks;             /* video-gone streak while hidden */
    NSRect frameBeforeHidingControls;
    NSRect hiddenControlsInitialFrame;   /* to carry drags across reveal */
    NSUInteger styleMaskBeforeHidingControls;
    NSString *titleBeforeHidingControls;   /* le cadre recree revient vide */
    BOOL styleMaskChangedForHiddenControls;
    NSSize lastNativeVideoSize;          /* from setVideoViewSizeFromValue */
    NSSize lastRequestedVideoSize;       /* to spot a plain restart */
    float lastVideoZoom;                 /* to spot a zoom the user asked */
    BOOL videoDragActive;                /* a drag is under way */
    NSSize pictureBox;                   /* box a shape change fits in */
    NSTimer *hiddenCursorTimer;          /* 10 Hz, corner grip cursors */
    int hiddenCursorZone;                /* 0 none, 1 NW/SE, 2 NE/SW */
    NSPoint hiddenDragStartMouse;        /* screen coords, drag-to-move */
    NSPoint hiddenDragStartOrigin;
    /* the bare window has no grow box and its video view swallows the
     * mouse: a drag started in a CORNER resizes (picture ratio kept,
     * opposite corner anchored), anywhere else moves */
    NSRect hiddenDragStartFrame;
    BOOL hiddenDragIsResize;
    int hiddenDragResizeH;               /* -1 left edge, +1 right edge */
    int hiddenDragResizeV;               /* -1 bottom edge, +1 top edge */

    /* Black screens in fullscreen */
    NSMutableArray *fsBlackWindows;
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;

/* Must be called on the main thread */
- (void)setupWindow;
- (void)showWindow;
- (void)shutdown;

- (void)addPaths:(NSArray *)paths playFirst:(BOOL)play;

/* time field behaviors (single click / double click, like VLCTimeField) */
- (void)toggleTimeDisplay;
- (void)showJumpToTimePanel;

/* Window > Playlist...: bring the window up showing the playlist view */
- (void)showPlaylistView;

/* Edit > Find: put the caret in the playlist search field */
- (void)highlightSearchField;

/* View menu behaviors (VLC 3.0 parity) */
- (void)toggleJumpButtons;
- (void)togglePlaymodeButtons;
- (void)toggleEffectsButton;
- (void)toggleSidebar;
- (BOOL)sidebarVisible;
- (BOOL)playlistColumnShown:(NSString *)identifier;
- (void)togglePlaylistColumn:(NSString *)identifier;

/* "Hide controls during playback": all main-thread. updateAutoHideControls
 * is driven by the refresh tick; the double click on the video (directly,
 * or relayed by the core through "intf-reveal-controls") reveals. The
 * drag entry points let the video view move the whole window while it is
 * the only thing left on screen. */
- (BOOL)controlsHiddenForPlayback;
- (void)updateAutoHideControls;
- (void)hideControlsForPlayback;
- (void)revealControlsForPlayback;
- (void)beginHiddenControlsDragAtScreenPoint:(NSPoint)point;
/* dragging the picture always moves the window; the corner resize zones
 * only exist while the controls are auto-hidden (no window frame left) */
- (void)beginVideoDragAtScreenPoint:(NSPoint)point allowResize:(BOOL)allowResize;
- (void)dragHiddenControlsToScreenPoint:(NSPoint)point;
- (void)endVideoDrag;
- (BOOL)videoIsFullscreen;

/* Embedded video handling (main thread only). acquireVideoView returns nil
 * when the window already hosts a video; the caller then falls back to a
 * standalone vout window. */
- (NSView *)acquireVideoView;
/* Vue vidéo si elle est réellement affichée, sinon nil (masquage du curseur). */
- (NSView *)videoViewIfVisible;
- (void)releaseVideoView;
/* Re-applies the "Draw window shadows" preference to the live window, so
 * the checkbox takes effect without waiting for the next playback. */
- (void)applyWindowShadowSetting;
- (void)setVideoViewSizeFromValue:(NSValue *)size;
- (void)setVideoFullscreenFromNumber:(NSNumber *)fullscreen;
- (void)setVideoAboveOthersFromNumber:(NSNumber *)above;

@end
