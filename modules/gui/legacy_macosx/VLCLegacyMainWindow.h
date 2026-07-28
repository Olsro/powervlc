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
    NSString *searchString;
    NSMutableArray *visibleColumns; /* playlist column identifiers */

    /* embedded video */
    VLCLegacyVideoView *videoView;
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
    NSMutableSet *browseRequestedIds;  /* directories already sent to the
                                        * preparser (expand-to-browse) */
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

/* View menu behaviors (VLC 3.0 parity) */
- (void)toggleJumpButtons;
- (void)togglePlaymodeButtons;
- (void)toggleEffectsButton;
- (void)toggleSidebar;
- (BOOL)sidebarVisible;
- (BOOL)playlistColumnShown:(NSString *)identifier;
- (void)togglePlaylistColumn:(NSString *)identifier;

/* Embedded video handling (main thread only). acquireVideoView returns nil
 * when the window already hosts a video; the caller then falls back to a
 * standalone vout window. */
- (NSView *)acquireVideoView;
- (void)releaseVideoView;
- (void)setVideoViewSizeFromValue:(NSValue *)size;
- (void)setVideoFullscreenFromNumber:(NSNumber *)fullscreen;

@end
