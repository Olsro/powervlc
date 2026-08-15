/*****************************************************************************
 * VLCLegacyVoutWindow.m: macOS minimal vout window
 *****************************************************************************
 * Copyright (C) 2007-2017 VLC authors and VideoLAN
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

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "VLCLegacyVoutWindow.h"
#import "misc.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyControls.h"
#import "VLCLegacyMainWindow.h"
#import "VLCLegacySeekThumbnailer.h"

#include <vlc_playlist.h>
#include <vlc_input.h>

/* provided by intf.m */
extern VLCLegacyCoreInteraction *VLCLegacyGetCore(void);
extern VLCLegacyMainWindow *VLCLegacyGetMainWindow(void);

#import <Cocoa/Cocoa.h>
/* SetSystemUIMode(): menu bar/Dock hiding available since Mac OS X 10.2,
 * unlike -[NSApplication setPresentationOptions:] which needs 10.6. */
#import <Carbon/Carbon.h>
/* -setStyleMask: n'existe qu'à partir de 10.6 : appelé par objc_msgSend typé,
 * sous garde -respondsToSelector: (cf. -hideControlsForPlayback).
 * ⚠ <objc/message.h> est un découpage du SDK 10.5+ ; le SDK 10.4u déclare
 * objc_msgSend dans <objc/objc-runtime.h> (même aiguillage que la fenêtre
 * principale). */
#if defined(__has_include)
# if __has_include(<objc/message.h>)
#  import <objc/message.h>
# else
#  import <objc/objc-runtime.h>
# endif
#else
# import <objc/objc-runtime.h>
#endif

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/* Hauteur de la barre allégée, celle de la barre principale (VLC 3.0). */
#define VLC_LEGACY_VOUT_BAR_HEIGHT 37

static NSString *voutThemedImage(NSString *lightName, NSString *darkName)
{
    return VLCLegacyDarkMode() ? darkName : lightName;
}

static NSString *voutTimeToString(int seconds)
{
    if (seconds < 0)
        seconds = 0;
    if (seconds >= 3600)
        return [NSString stringWithFormat:@"%d:%02d:%02d",
                seconds / 3600, (seconds / 60) % 60, seconds % 60];
    return [NSString stringWithFormat:@"%02d:%02d",
            seconds / 60, seconds % 60];
}

/* cf. VLCLegacyVoutWindow.h : la seule fenêtre vidéo autonome vivante */
static VLCLegacyVoutWindow *s_currentVoutWindow = nil;

VLCLegacyVoutWindow *VLCLegacyCurrentVoutWindow(void)
{
    return s_currentVoutWindow;
}

/* Même contrat que VLCLegacyTimeField dans la fenêtre principale : le réglage
 * écoulé/restant est commun aux deux fenêtres, tout comme le dialogue de saut. */
@interface VLCLegacyVoutTimeField : NSTextField
@end

@implementation VLCLegacyVoutTimeField
- (void)mouseDown:(NSEvent *)event
{
    VLCLegacyMainWindow *main = VLCLegacyGetMainWindow();
    if ([event clickCount] >= 2)
        [main showJumpToTimePanel];
    else
        [main toggleTimeDisplay];
}
@end

@implementation VLCLegacyVoutWindow
- (id)initWithContentRect:(NSRect)contentRect decorated:(BOOL)b_decorated
{
    /* ⚠ Sans décorations, le masque doit rester BORDERLESS PUR. L'interface
     * moderne y ajoute NSResizableWindowMask pour garder le redimensionnement,
     * mais NSBorderlessWindowMask vaut 0 : le masque se réduit alors au seul
     * bit « redimensionnable », que l'AppKit de 10.4 rend avec une BARRE DE
     * TITRE (mesuré sur l'iBook G3 : fenêtre titrée alors que la case est
     * décochée ; sur macOS moderne la même valeur donne bien une fenêtre nue).
     * Le confort de la poignée ne vaut pas de renier la case cochée. */
    unsigned int style = b_decorated
        ? (NSTitledWindowMask | NSClosableWindowMask
           | NSMiniaturizableWindowMask | NSResizableWindowMask)
        : NSBorderlessWindowMask;

    /* la taille demandée est celle de l'IMAGE : la barre s'ajoute par-dessous */
    NSRect winContent = contentRect;
    if (b_decorated)
        winContent.size.height += VLC_LEGACY_VOUT_BAR_HEIGHT;

    if( self = [super initWithContentRect:winContent
                                styleMask:style
                                  backing:NSBackingStoreBuffered
                                    defer:NO])
    {
        decorated = b_decorated;
        lastRunningState = -1;
        s_currentVoutWindow = self;
        [self setBackgroundColor:[NSColor blackColor]];
        /* le titre suit le média en cours (posé par la fenêtre principale,
         * qui compose déjà input-title-format à chaque tic) */
        if (decorated)
            [self setTitle:[NSString stringWithUTF8String:
                vlc_gettext("PowerVLC media player")]];
        /* Fermeture (cf. -windowShouldClose:) et iconification (cf.
         * -windowDidMiniaturize:) passent par le délégué — posé même sans
         * décoration, une fenêtre nue restant miniaturisable par le menu
         * Fenêtre. Cast en `id` : le protocole NSWindowDelegate n'existe pas
         * dans le SDK 10.4 avec lequel les tranches PowerPC sont bâties. */
        [self setDelegate:(id)self];
        /* Shadow per the user option (G3 default: off — measured ~16% more
         * late pictures with it there) — but NEVER when an MPEG-2 hardware
         * decoder is armed: a shadowed window at surface-commit time
         * freezes the WindowServer (iBook G3/Tiger, 2026-08-14), and any
         * later cut leaves the committed surface mis-shaped. This window is
         * created while the vout opens, i.e. after the decoder: the armed
         * flag is already readable, and the commit is still ahead. */
        {
            VLCLegacyCoreInteraction *core = VLCLegacyGetCore();
            intf_thread_t *p_vi = core ? [core intf] : NULL;
            bool hw_armed = p_vi != NULL && VLCLegacyHwDecoderArmed(p_vi);
            [self setHasShadow:(VLCLegacyWindowShadows() && !hw_armed)];
        }
        [self setMovableByWindowBackground:YES];
        /* ⚠ AppKit accorde le plein écran natif (bouton vert, menu Fenêtre,
         * ⌃⌘F) à TOUTE fenêtre redimensionnable, et cette fenêtre-ci l'est.
         * Le legacy a son propre plein écran, borderless, piloté par le
         * cœur (`fullscreen`) : les deux se marchaient dessus — la fenêtre
         * partait sur son propre bureau, la barre allégée et le panneau
         * plein écran ne suivaient pas, et en sortir laissait un cadre
         * faux. Les cinq autres fenêtres redimensionnables du legacy le
         * refusent déjà ; celle-ci avait été oubliée. */
        VLCLegacyDenyNativeFullscreen(self);
        /* DVD/BD menus need the vout's mouse-moved events */
        [self setAcceptsMouseMovedEvents:YES];
        /* modern macOS: clip the old-style GL surface (see misc.h).
         * ⚠ Sur TOUT le contentView, pas seulement sur la vue vidéo : une
         * fenêtre non calquée contenant une surface NSOpenGL d'ancien style
         * la compose PAR-DESSUS tout le reste, et la barre de contrôles
         * devenait invisible sous l'image (même piège que la fenêtre
         * principale). Mélanger calqué et non calqué ne suffit pas. */
        VLCLegacyEnableLayerBackingIfModern([self contentView]);
        [self buildContentViews];
        [self center];
        initialFrame = [self frame];
    }
    return self;
}

- (NSView *)videoView
{
    return videoView;
}

/* Zone de l'image dans le contentView : tout sauf la bande de la barre. */
- (NSRect)videoAreaRect
{
    NSRect bounds = [[self contentView] bounds];
    /* ⚠ -[NSView isHidden] est 10.3 : le plancher est 10.2, d'où l'aiguilleur
     * de misc.h (qui DÉTACHE la vue en dessous de 10.3). */
    if (controlsBar == nil || VLCLegacyViewIsHidden(controlsBar))
        return bounds;
    bounds.origin.y += VLC_LEGACY_VOUT_BAR_HEIGHT;
    bounds.size.height -= VLC_LEGACY_VOUT_BAR_HEIGHT;
    if (bounds.size.height < 0)
        bounds.size.height = 0;
    return bounds;
}

- (void)buildContentViews
{
    NSView *content = [self contentView];
    float W = [content bounds].size.width;

    if (decorated)
        [self buildControlsBar];

    /* ⚠ Le vout reçoit CETTE vue, pas le contentView : sinon sa surface
     * accélérée, qui remplit son parent, recouvrirait la barre. */
    videoView = [[[NSView alloc] initWithFrame:[self videoAreaRect]]
                    autorelease];
    [videoView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [content addSubview:videoView];
    (void)W;
}

/* Barre allégée, calquée sur celle de la fenêtre principale mais réduite à ce
 * que montre la fenêtre vidéo détachée de l'interface moderne
 * (VLCControlsBarCommon) : reculer / lecture / avancer, barre de position,
 * durée, plein écran. NI « Stop » NI « Liste de lecture » — cette dernière ne
 * bascule que la fenêtre PRINCIPALE entre image et liste. */
- (void)buildControlsBar
{
    NSView *content = [self contentView];
    float W = [content bounds].size.width;

    VLCLegacyBottomBarView *bar = [[[VLCLegacyBottomBarView alloc]
        initWithFrame:NSMakeRect(0, 0, W, VLC_LEGACY_VOUT_BAR_HEIGHT)]
            autorelease];
    [bar setAutoresizingMask:NSViewWidthSizable | NSViewMaxYMargin];
    [content addSubview:bar];
    controlsBar = bar;

    float x = 12;
    backwardButton = VLCLegacyImageButton(bar,
        voutThemedImage(@"backward-3btns", @"backward-3btns-dark"),
        voutThemedImage(@"backward-3btns-pressed",
                        @"backward-3btns-dark-pressed"),
        NSMakeRect(x, 7, 29, 23), self, @selector(backward:));
    [backwardButton setToolTip:_NS("Backward")];
    x += 29;
    playButton = VLCLegacyImageButton(bar,
        voutThemedImage(@"play", @"play_dark"),
        voutThemedImage(@"play-pressed", @"play-pressed_dark"),
        NSMakeRect(x, 7, 27, 23), self, @selector(playPause:));
    [playButton setToolTip:_NS("Play/Pause")];
    x += 27;
    forwardButton = VLCLegacyImageButton(bar,
        voutThemedImage(@"forward-3btns", @"forward-3btns-dark"),
        voutThemedImage(@"forward-3btns-pressed",
                        @"forward-3btns-dark-pressed"),
        NSMakeRect(x, 7, 29, 23), self, @selector(forward:));
    [forwardButton setToolTip:_NS("Forward")];
    x += 29 + 13;

    /* ⚠ VLCLegacySeekSlider, PAS un NSSlider nu : c'est lui qui porte les
     * séparateurs de chapitres, la tooltip vivante (temps, chapitre,
     * vignette) et les deux poignées du mode clip. La fenêtre vidéo
     * séparée s'en était tenue à un slider ordinaire, si bien que la même
     * barre montrait ses chapitres dans la fenêtre principale et rien du
     * tout ici (remonté le 14/08/2026). Parité avec VLCLegacyFSPanel. */
    seekSlider = [[[VLCLegacySeekSlider alloc]
        initWithFrame:NSMakeRect(x, 8, W - x - 108, 21)] autorelease];
    VLCLegacyProgressSliderCell *seekCell =
        [[[VLCLegacyProgressSliderCell alloc] init] autorelease];
    [seekSlider setCell:seekCell];
    [(VLCLegacySeekSlider *)seekSlider setHoverDelegate:self];
    [seekSlider setMinValue:0.0];
    [seekSlider setMaxValue:1.0];
    [seekSlider setFloatValue:0.f];
    [seekSlider setContinuous:NO];
    [seekSlider setTarget:self];
    [seekSlider setAction:@selector(seeked:)];
    [seekSlider setAutoresizingMask:NSViewWidthSizable];
    [bar addSubview:seekSlider];

    durationField = [[[VLCLegacyVoutTimeField alloc]
        initWithFrame:NSMakeRect(W - 100, 10, 56, 15)] autorelease];
    [durationField setEditable:NO];
    [durationField setSelectable:NO];
    [durationField setBordered:NO];
    [durationField setDrawsBackground:NO];
    [durationField setAlignment:NSRightTextAlignment];
    [[durationField cell] setFont:[NSFont systemFontOfSize:10.5]];
    [durationField setTextColor:VLCLegacyTextColor()];
    [durationField setStringValue:@"00:00"];
    [durationField setAutoresizingMask:NSViewMinXMargin];
    [bar addSubview:durationField];

    fullscreenButton = VLCLegacyImageButton(bar,
        voutThemedImage(@"fullscreen-one-button", @"fullscreen-one-button_dark"),
        voutThemedImage(@"fullscreen-one-button-pressed",
                        @"fullscreen-one-button-pressed_dark"),
        NSMakeRect(W - 34, 7, 29, 23), self, @selector(fullscreenClicked:));
    [fullscreenButton setToolTip:_NS("Fullscreen")];
    [fullscreenButton setAutoresizingMask:NSViewMinXMargin];

    refreshTimer = [[NSTimer scheduledTimerWithTimeInterval:0.5
                                                     target:self
                                                   selector:@selector(refreshControls:)
                                                   userInfo:nil
                                                    repeats:YES] retain];
}

- (void)playPause:(id)sender  { [VLCLegacyGetCore() togglePlayPause]; }
- (void)backward:(id)sender   { [VLCLegacyGetCore() jumpWithSeconds:-10]; }
- (void)forward:(id)sender    { [VLCLegacyGetCore() jumpWithSeconds:10]; }
- (void)fullscreenClicked:(id)sender { [VLCLegacyGetCore() toggleFullscreen]; }
- (void)seeked:(id)sender
{
    VLCLegacyCoreInteraction *core = VLCLegacyGetCore();

    if ([core clipCreationMode]) {
        /* même routage que la barre principale et le panneau plein écran :
         * les deux poignées portent les bornes du clip et bouger l'une
         * saute là, pour prévisualiser ce que le clip contiendra ; cliquer
         * ENTRE elles ne fait que scruter */
        VLCLegacyProgressSliderCell *seekCell =
            (VLCLegacyProgressSliderCell *)[seekSlider cell];
        float fraction;
        int knob = [seekCell activeClipKnob];
        if (knob == 2) {
            fraction = (float)[seekCell clipEndValue];
            [core setClipEndPosition:fraction];
            [core setClipSelectedKnob:2];
        } else if (knob == 3) {
            fraction = (float)[seekCell playbackMarkerValue];
        } else {
            fraction = [sender floatValue];
            [core setClipStartPosition:fraction];
            [core setClipSelectedKnob:1];
        }
        [core setPositionFraction:fraction];
        return;
    }

    [core setPositionFraction:[sender floatValue]];
}

/* fournisseur de vignette du survol (le débounce vit dans le slider) */
- (void)seekSlider:(VLCLegacySeekSlider *)slider
        hoverThumbnailWantedAtFraction:(double)fraction
{
    VLCLegacyCoreInteraction *core = VLCLegacyGetCore();
    intf_thread_t *p_intf = core ? [core intf] : NULL;
    if (p_intf == NULL)
        return;
    [[VLCLegacySeekThumbnailer sharedInstance]
        requestThumbnailWithIntf:p_intf fraction:fraction forSlider:slider];
}

/* flèches nues quand le slider est premier répondeur (mode clip) */
- (void)seekSlider:(VLCLegacySeekSlider *)slider
        clipStepFrames:(int)direction
{
    [VLCLegacyGetCore() clipStepFrames:direction];
}

/* Séparateurs de chapitres : mêmes règles et même cache que la fenêtre
 * principale (seulement si le dernier point de reprise a un décalage > 0,
 * sinon le média n'a pas de vrais chapitres). */
- (void)updateChaptersForInput:(input_thread_t *)p_input
                      duration:(int64_t)i_length
{
    VLCLegacyProgressSliderCell *cell =
        (VLCLegacyProgressSliderCell *)[seekSlider cell];

    int title = p_input ? (int)var_GetInteger(p_input, "title") : -1;
    char *psz_uri = NULL;
    if (p_input != NULL) {
        input_item_t *p_item = input_GetItem(p_input);
        if (p_item != NULL)
            psz_uri = input_item_GetURI(p_item);
    }
    BOOL sameMedia = ((psz_uri == NULL && chaptersUri == NULL)
                      || (psz_uri != NULL && chaptersUri != NULL
                          && strcmp(psz_uri, chaptersUri) == 0))
                     && title == chaptersTitle;
    BOOL sameSource = sameMedia && i_length == chaptersDuration;
    if (!sameMedia) {
        free(chaptersUri);
        chaptersUri = psz_uri;
        psz_uri = NULL;
    }
    free(psz_uri);
    if (sameSource && [cell chapterFractions] != nil)
        return;
    if (sameSource && ++chaptersRetryTicks < 8)
        return;
    chaptersRetryTicks = 0;
    chaptersTitle = title;
    chaptersDuration = i_length;

    NSArray *fractions = nil;
    NSArray *names = nil;
    if (p_input && i_length > 0) {
        input_title_t *p_title = NULL;
        int i_title_id = -1;
        if (input_Control(p_input, INPUT_GET_TITLE_INFO, &p_title,
                          &i_title_id) == VLC_SUCCESS && p_title) {
            if (p_title->i_seekpoint > 1
                && p_title->seekpoint[p_title->i_seekpoint - 1]->i_time_offset
                   > 0) {
                NSMutableArray *mutableFractions = [NSMutableArray
                    arrayWithCapacity:p_title->i_seekpoint];
                NSMutableArray *mutableNames = [NSMutableArray
                    arrayWithCapacity:p_title->i_seekpoint];
                int i;
                for (i = 0; i < p_title->i_seekpoint; i++) {
                    seekpoint_t *point = p_title->seekpoint[i];
                    NSString *name =
                        (point->psz_name != NULL && *point->psz_name != '\0')
                        ? [NSString stringWithUTF8String:point->psz_name]
                        : [NSString stringWithFormat:_NS("Chapter %i"), i + 1];
                    [mutableFractions addObject:
                        [NSNumber numberWithDouble:
                            (double)point->i_time_offset / (double)i_length]];
                    [mutableNames addObject:name ? name : @""];
                }
                fractions = mutableFractions;
                names = mutableNames;
            }
            vlc_input_title_Delete(p_title);
        }
    }

    if (!fractions && ![cell chapterFractions])
        return;
    if (!fractions && sameMedia)
        return;
    [cell setChapterFractions:fractions names:names];
    [seekSlider setNeedsDisplay:YES];
}

/*****************************************************************************
 * « Masquer les contrôles durant la lecture » (menu Vidéo, ⇧⌘H)
 *
 * Même moteur que la fenêtre principale : sondage du pointeur (aucune
 * primitive de suivi utilisable avant 10.5) et 3 s hors de la fenêtre. La
 * fenêtre se rétracte sur l'IMAGE — ici il n'y a QUE la barre allégée à
 * retirer, la barre de titre reste (changer le styleMask recrée le cadre de
 * fenêtre, et c'est CETTE fenêtre qui porte la surface accélérée : la
 * principale peut se le permettre parce que sa vidéo vit dans une fenêtre
 * ENFANT, pas ici). Révélation par DOUBLE-CLIC seulement, comme la
 * principale : le simple clic doit pouvoir rendre le clavier sans tout
 * ramener.
 *****************************************************************************/
#define VLC_LEGACY_VOUT_AUTOHIDE_DELAY 3.0

/* ⚠⚠⚠ Recadrer la fenêtre SANS laisser la vue vidéo s'étaler sur la bande.
 * `videoView` est en NSViewWidth|HeightSizable : à chaque -setFrame: de la
 * fenêtre, AppKit lui donne d'abord TOUTE la nouvelle hauteur — donc la
 * surface accélérée recouvre la barre — et notre recadrage ne vient qu'après.
 * Mesuré sur l'iBook G3 (Tiger) : à la révélation, la bande revenait à moitié
 * peinte (barre de position seule, boutons et durée en blanc), le
 * WindowServer ne repeignant jamais ce que la surface avait découvert. On gèle
 * donc le masque le temps du changement de cadre. */
- (void)setWindowFrameKeepingVideoArea:(NSRect)frame
{
    [videoView setAutoresizingMask:NSViewNotSizable];
    [self setFrame:frame display:NO];
    [self resizeVideoSubviewsTo:[self videoAreaRect]];
    [videoView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    if (controlsBar != nil)
        [controlsBar setNeedsDisplay:YES];
    [[self contentView] setNeedsDisplay:YES];
    [self display];
}

- (void)hideControlsForPlayback
{
    if (controlsHiddenForPlayback || controlsBar == nil)
        return;
    /* ⚠ Un masquage déclenché pendant un démontage (vue de taille ~0)
     * rétractait la fenêtre en filet — même garde-fou que la principale. */
    NSRect video = [self videoAreaRect];
    if (video.size.width < 160 || video.size.height < 90)
        return;

    controlsHiddenForPlayback = YES;
    /* ⚠ La tooltip de survol est une FENÊTRE à part : détacher la barre ne
     * l'emporte pas, elle resterait posée au-dessus de l'image. */
    [(VLCLegacySeekSlider *)seekSlider hideHoverTooltip];
    VLCLegacySetViewHidden(controlsBar, YES);

    /* Viser le CONTENU voulu, la barre de titre partant peut-être au passage :
     * le bord HAUT du contenu ne bouge pas, l'image reste là où l'utilisateur
     * la voit. */
    NSRect content = [self contentRectForFrameRect:[self frame]];
    content.origin.y += VLC_LEGACY_VOUT_BAR_HEIGHT;
    content.size.height -= VLC_LEGACY_VOUT_BAR_HEIGHT;

    /* ⚠ La barre de TITRE part aussi, comme sur la fenêtre principale — mais
     * seulement là où -setStyleMask: existe (10.6). Sur 10.2-10.5 elle reste :
     * compromis déjà documenté pour la principale, et ici le prix serait plus
     * lourd puisque c'est CETTE fenêtre qui porte la surface accélérée.
     * ⚠ BORDERLESS SEUL : le bit « redimensionnable » sans le bit « titré »
     * n'est pas une combinaison que les vieux AppKit acceptent (la barre de
     * titre RESTE), cf. le masque de -initWithContentRect:decorated:. */
    styleMaskChangedForHiddenControls = NO;
    if (decorated && [self respondsToSelector:@selector(setStyleMask:)]) {
        typedef NSUInteger (*GetMaskFn)(id, SEL);
        typedef void (*SetMaskFn)(id, SEL, NSUInteger);
        styleMaskBeforeHidingControls =
            ((GetMaskFn)objc_msgSend)(self, @selector(styleMask));
        /* ⚠ mémoriser le titre AVANT : changer le masque recrée le cadre de
         * fenêtre et le titre est perdu — le relire ensuite ne rend qu'une
         * chaîne VIDE. */
        [titleBeforeHidingControls release];
        titleBeforeHidingControls = [[self title] copy];
        ((SetMaskFn)objc_msgSend)(self, @selector(setStyleMask:),
                                  (NSUInteger)NSBorderlessWindowMask);
        styleMaskChangedForHiddenControls = YES;
    }

    [self setWindowFrameKeepingVideoArea:
        [self frameRectForContentRect:content]];
    [VLCLegacyGetCore() setControlsHiddenForPlayback:YES];
}

- (void)revealControlsForPlayback
{
    if (!controlsHiddenForPlayback)
        return;
    controlsHiddenForPlayback = NO;
    mouseOutsideSince = 0;
    VLCLegacySetViewHidden(controlsBar, NO);

    /* On repart du CONTENU courant (l'utilisateur a pu déplacer la fenêtre nue
     * entre-temps) : la bande revient sous l'image, bord haut inchangé. */
    NSRect content = [self contentRectForFrameRect:[self frame]];
    content.origin.y -= VLC_LEGACY_VOUT_BAR_HEIGHT;
    content.size.height += VLC_LEGACY_VOUT_BAR_HEIGHT;

    /* ⚠ Rétablir le masque AVANT -frameRectForContentRect: — c'est lui qui
     * décide si la barre de titre compte dans le cadre. */
    if (styleMaskChangedForHiddenControls) {
        typedef void (*SetMaskFn)(id, SEL, NSUInteger);
        ((SetMaskFn)objc_msgSend)(self, @selector(setStyleMask:),
                                  styleMaskBeforeHidingControls);
        styleMaskChangedForHiddenControls = NO;
        /* un cadre titré neuf arrive VIDE : reposer la copie prise avant */
        [self setTitle:titleBeforeHidingControls ?
                           titleBeforeHidingControls : @""];
        /* le nouveau cadre de fenêtre a perdu le délégué posé à l'init */
        [self setDelegate:(id)self];
    }

    NSRect frame = [self frameRectForContentRect:content];
    /* garder la fenêtre entière à l'écran : la barre de titre qui revient
     * pourrait la pousser sous la barre des menus */
    NSScreen *screen = [self screen];
    if (!screen)
        screen = [NSScreen mainScreen];
    if (screen != nil) {
        NSRect visible = [screen visibleFrame];
        if (NSMaxY(frame) > NSMaxY(visible))
            frame.origin.y = NSMaxY(visible) - frame.size.height;
        if (frame.origin.y < visible.origin.y)
            frame.origin.y = visible.origin.y;
    }
    [self setWindowFrameKeepingVideoArea:frame];
    [VLCLegacyGetCore() setControlsHiddenForPlayback:NO];
}

- (void)updateAutoHideControls
{
    VLCLegacyCoreInteraction *core = VLCLegacyGetCore();
    BOOL enabled = core ? [core autoHideControls] : NO;

    /* En plein écran c'est le panneau flottant qui prend le relais ; la barre
     * est déjà retirée par -enterFullscreen. */
    if (fullscreenActive) {
        mouseOutsideSince = 0;
        return;
    }
    if (controlsHiddenForPlayback) {
        if (!enabled)                  /* option décochée = retour immédiat */
            [self revealControlsForPlayback];
        return;                        /* sinon : double-clic uniquement */
    }
    if (!enabled || controlsBar == nil || ![self isVisible]) {
        mouseOutsideSince = 0;
        return;
    }
    if (NSMouseInRect([NSEvent mouseLocation], [self frame], NO)) {
        mouseOutsideSince = 0;
        return;
    }
    {
        double now = [NSDate timeIntervalSinceReferenceDate];
        if (mouseOutsideSince == 0) {
            mouseOutsideSince = now;
            return;
        }
        if (now - mouseOutsideSince >= VLC_LEGACY_VOUT_AUTOHIDE_DELAY)
            [self hideControlsForPlayback];
    }
}

- (void)stopControlsRefresh
{
    if (refreshTimer == nil)
        return;
    [refreshTimer invalidate];
    [refreshTimer release];
    refreshTimer = nil;
}

- (void)refreshControls:(NSTimer *)timer
{
    VLCLegacyCoreInteraction *core = VLCLegacyGetCore();
    intf_thread_t *p_intf = core ? [core intf] : NULL;
    if (p_intf == NULL)
        return;

    [self updateAutoHideControls];

    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    int status = playlist_Status(p_playlist);
    playlist_Unlock(p_playlist);
    BOOL running = (status == PLAYLIST_RUNNING);

    /* barre retirée : rien à rafraîchir, et un -setStringValue: sur une vue
     * détachée ferait travailler le serveur de polices pour rien */
    if (controlsHiddenForPlayback)
        return;

    if (lastRunningState != (int)running) {
        lastRunningState = (int)running;
        NSString *base = running ? voutThemedImage(@"pause", @"pause_dark")
                                 : voutThemedImage(@"play", @"play_dark");
        NSString *pressed = running
            ? voutThemedImage(@"pause-pressed", @"pause-pressed_dark")
            : voutThemedImage(@"play-pressed", @"play-pressed_dark");
        [playButton setImage:VLCLegacyImageSized(base, NSMakeSize(27, 23))];
        [playButton setAlternateImage:
            VLCLegacyImageSized(pressed, NSMakeSize(27, 23))];
    }

    /* ⚠ Ne toucher un champ QUE si son texte change : un -setStringValue:
     * identique redessine quand même, et sur 10.3 chaque redessin de glyphes
     * passe par un RPC au serveur de polices — c'est ce qui faisait scintiller
     * les autres barres (cf. VLCLegacyFSPanel -refreshControls). */
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    VLCLegacyProgressSliderCell *clipCell =
        (VLCLegacyProgressSliderCell *)[seekSlider cell];
    if (p_input) {
        int64_t length = var_GetInteger(p_input, "length");
        int64_t time = var_GetInteger(p_input, "time");
        BOOL remaining = [[NSUserDefaults standardUserDefaults]
            boolForKey:@"DisplayTimeAsTimeRemaining"];
        NSString *newTime;
        if (remaining && length > 0) {
            int64_t left = length - time;
            if (left < 0)
                left = 0;
            newTime = [NSString stringWithFormat:@"-%@",
                voutTimeToString((int)(left / CLOCK_FREQ))];
        } else
            newTime = voutTimeToString((int)(time / CLOCK_FREQ));
        if (![[durationField stringValue] isEqualToString:newTime])
            [durationField setStringValue:newTime];
        float pos = var_GetFloat(p_input, "position");
        if ([VLCLegacyGetCore() clipCreationMode]) {
            /* les poignées portent les bornes, seul le marqueur fin suit la
             * lecture (parité avec la barre principale) */
            if (![clipCell clipKnobsActive])
                [clipCell setClipKnobsActive:YES];
            [seekSlider setDoubleValue:[VLCLegacyGetCore() clipStartPosition]];
            [clipCell setClipEndValue:[VLCLegacyGetCore() clipEndPosition]];
            [clipCell setPlaybackMarkerValue:pos];
            [seekSlider setNeedsDisplay:YES];
        } else {
            if ([clipCell clipKnobsActive]) {
                [clipCell setClipKnobsActive:NO];
                [seekSlider setNeedsDisplay:YES];
            }
            if ([seekSlider floatValue] != pos)
                [seekSlider setFloatValue:pos];
        }
        /* ⚠ sans mediaDuration la tooltip de survol sort aussitôt : c'est
         * elle qui porte le temps et le nom du chapitre survolés */
        [(VLCLegacySeekSlider *)seekSlider
            setMediaDuration:(double)length / CLOCK_FREQ];
        [self updateChaptersForInput:p_input duration:length];
        vlc_object_release(p_input);
    } else {
        if (![[durationField stringValue] isEqualToString:@"00:00"])
            [durationField setStringValue:@"00:00"];
        [(VLCLegacySeekSlider *)seekSlider setMediaDuration:0.0];
        [self updateChaptersForInput:NULL duration:0];
        /* Stop ne laisse AUCUNE entrée : c'est la seule branche qui range
         * les poignées de clip (même correctif que la barre principale) */
        if ([clipCell clipKnobsActive]) {
            [clipCell setClipKnobsActive:NO];
            [seekSlider setNeedsDisplay:YES];
        }
    }
}

- (void)dealloc
{
    if (s_currentVoutWindow == self)
        s_currentVoutWindow = nil;
    [self stopControlsRefresh];
    free(chaptersUri);
    [titleBeforeHidingControls release];
    [super dealloc];
}

/* ⚠ -close est appelé par WindowClose() (intf.m) et détruit la fenêtre : le
 * pointeur global doit tomber ICI, pas seulement au -dealloc, qui peut être
 * différé par les autorelease en vol. */
- (void)close
{
    if (s_currentVoutWindow == self)
        s_currentVoutWindow = nil;
    /* ⚠ Le timer RETIENT sa cible : sans cet arrêt la fenêtre ne serait
     * jamais désallouée et continuerait d'interroger la liste de lecture. */
    [self stopControlsRefresh];
    /* fenêtre à part, elle survivrait à la nôtre */
    [(VLCLegacySeekSlider *)seekSlider hideHoverTooltip];
    /* ⚠ Le drapeau « contrôles masqués » est GLOBAL (var libvlc lue par l'OSD
     * et les raccourcis) : le laisser levé en fermant la fenêtre le rendait
     * indéboulonnable jusqu'au prochain masquage. */
    if (controlsHiddenForPlayback) {
        controlsHiddenForPlayback = NO;
        [VLCLegacyGetCore() setControlsHiddenForPlayback:NO];
    }
    /* le registre des vues masquées est indexé par ADRESSE : ne pas laisser
     * la nôtre y traîner après la fermeture (cf. misc.h) */
    if (controlsBar != nil)
        VLCLegacyForgetHiddenView(controlsBar);
    [self setDelegate:nil];
    [super close];
}

/* Le bouton de fermeture ARRÊTE la lecture : c'est le coeur qui détruit le
 * vout, et lui seul peut fermer la fenêtre proprement (WindowClose). Fermer
 * la fenêtre sous les pieds du vout laisserait une vue orpheline. */
- (BOOL)windowShouldClose:(id)sender
{
    [VLCLegacyGetCore() stop];
    return NO;
}

/* « Mettre en pause la vidéo lors de l'iconification ».
 * ⚠ La fenêtre principale a le même couple de méthodes, mais elle ne voit
 * QUE sa propre miniaturisation : ranger la fenêtre vidéo SÉPARÉE ne la
 * concerne pas, et la lecture continuait. */
- (void)windowDidMiniaturize:(NSNotification *)notification
{
    VLCLegacyCoreInteraction *core = VLCLegacyGetCore();
    intf_thread_t *p_intf = core ? [core intf] : NULL;
    if (p_intf == NULL
     || !var_InheritBool(p_intf, "legacy-macosx-pause-minimized"))
        return;

    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    int status = playlist_Status(p_playlist);
    playlist_Unlock(p_playlist);
    if (status != PLAYLIST_RUNNING)
        return;
    [core togglePlayPause];
    pausedByMiniaturize = YES;
}

- (void)windowDidDeminiaturize:(NSNotification *)notification
{
    VLCLegacyCoreInteraction *core = VLCLegacyGetCore();
    if (!pausedByMiniaturize || core == NULL)
        return;
    pausedByMiniaturize = NO;
    /* ne relancer que si l'utilisateur n'a pas repris la main entre-temps */
    intf_thread_t *p_intf = [core intf];
    if (p_intf == NULL)
        return;
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    int status = playlist_Status(p_playlist);
    playlist_Unlock(p_playlist);
    if (status != PLAYLIST_RUNNING)
        [core togglePlayPause];
}

/* Plein écran d'une fenêtre À BARRE DE TITRE : AppKit refuse par défaut de
 * laisser une fenêtre titrée sortir de l'écran, ce qui rabattait la barre de
 * titre sur l'image. On lève la contrainte le temps du plein écran et on
 * repousse la barre au-dessus du bord haut (cf. -enterFullscreen). */
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen
{
    /* ⚠⚠⚠ Rendre `frameRect` tel quel ne suffit PAS : ce n'est pas seulement
     * AppKit qui RÉDUIT un cadre ici, c'est aussi lui qui en PROPOSE un de
     * son cru, et le renvoyer intact revient à l'accepter. Masquer la barre
     * des menus (SetSystemUIMode, juste après le -setFrame:) change les
     * paramètres d'écran, et AppKit repositionne alors la fenêtre pour que
     * sa barre de titre reste dans la zone visible : tracé au banc, il
     * propose {{0,-28},…} puis {{0,25},…}, et c'est ce dernier qui restait —
     * la fenêtre remontait de 25 points (la hauteur de la barre des menus)
     * et le bas de l'écran laissait voir le BUREAU sous la vidéo (remonté le
     * 14/08/2026 sur un écran externe). Le plein écran doit donc DÉFENDRE
     * son cadre, pas se contenter de ne pas être rogné. */
    if (fullscreenActive)
        return fullscreenFrame;
    return [super constrainFrameRect:frameRect toScreen:screen];
}

/* Main-thread trampoline for VOUT_WINDOW_SET_STATE (see intf.m) */
- (void)setLevelFromNumber:(NSNumber *)value
{
    [self setLevel:[value intValue]];
}

/* Main-thread trampoline for VOUT_WINDOW_SET_SIZE (see intf.m) */
- (void)setSizeFromValue:(NSValue *)value
{
    NSSize size = [value sizeValue];
    NSRect theFrame = [self frame];
    NSRect content;

    if (fullscreenActive)
        return;             /* le plein écran fixe déjà le cadre */

    /* ⚠ La taille demandée par le coeur est celle de l'IMAGE, donc ni celle du
     * cadre ni même celle du contenu : l'appliquer au CADRE amputait la vidéo
     * de la barre de titre (mesuré : cadre 1024x768 pour une image de
     * 1024x768), et le contenu porte EN PLUS la barre de contrôles. */
    content = [self contentRectForFrameRect:theFrame];
    content.size = size;
    if (controlsBar != nil && !VLCLegacyViewIsHidden(controlsBar))
        content.size.height += VLC_LEGACY_VOUT_BAR_HEIGHT;
    content = [self frameRectForContentRect:content];

    /* ⚠⚠ BORNER À L'ÉCRAN. « Taille double » sur une vidéo 1080p demande
     * 3840x2160 : la fenêtre sortait de l'écran (mesuré : cadre de 3840 px de
     * large sur un écran de 1512). La fenêtre PRINCIPALE borne depuis
     * toujours, l'interface moderne aussi ; cette fenêtre-ci ne le faisait
     * pas. On RÉDUIT À L'ÉCHELLE, ratio conservé, plutôt que de rogner chaque
     * côté séparément comme le fait le moderne : sinon la fenêtre prend la
     * forme de l'écran et l'image y reprend des bandes noires. */
    {
        NSScreen *screen = [self screen];
        if (!screen)
            screen = [NSScreen mainScreen];
        if (screen != nil) {
            NSRect visible = [screen visibleFrame];
            float chromeW = content.size.width - size.width;
            float chromeH = content.size.height - size.height;
            float maxW = visible.size.width - chromeW;
            float maxH = visible.size.height - chromeH;
            if (maxW > 0.f && maxH > 0.f && size.width > 0.f
             && size.height > 0.f) {
                float fit = maxW / size.width;
                if (maxH / size.height < fit)
                    fit = maxH / size.height;
                if (fit < 1.f) {
                    content.size.width  = (float)(int)(size.width * fit + 0.5f)
                                        + chromeW;
                    content.size.height = (float)(int)(size.height * fit + 0.5f)
                                        + chromeH;
                }
            }
        }
    }

    /* garder le coin HAUT-gauche : en repères AppKit l'origine est en bas,
     * une fenêtre qui grandit descendrait sinon sous le bord de l'écran */
    content.origin.x = theFrame.origin.x;
    content.origin.y = NSMaxY(theFrame) - content.size.height;
    /* ... et la fenêtre entière DANS l'écran, comme la principale */
    {
        NSScreen *screen = [self screen];
        if (!screen)
            screen = [NSScreen mainScreen];
        if (screen != nil) {
            NSRect visible = [screen visibleFrame];
            if (NSMaxX(content) > NSMaxX(visible))
                content.origin.x = NSMaxX(visible) - content.size.width;
            if (content.origin.x < visible.origin.x)
                content.origin.x = visible.origin.x;
            if (NSMaxY(content) > NSMaxY(visible))
                content.origin.y = NSMaxY(visible) - content.size.height;
            if (content.origin.y < visible.origin.y)
                content.origin.y = visible.origin.y;
        }
    }
    [self setFrame:content display:YES animate:YES];
}

/* Borderless windows refuse key status by default; without this the
 * keyboard behaviors below never trigger. */
- (BOOL)canBecomeKeyWindow
{
    return YES;
}

/* VLC 3.0 behaviors: double-click toggles fullscreen, Space pauses,
 * Escape leaves fullscreen. The vout OpenGL view forwards unhandled
 * events up the responder chain. */
- (void)mouseDown:(NSEvent *)event
{
    if ([event clickCount] == 2) {
        /* contrôles masqués : le double-clic les RAMÈNE, il ne bascule pas
         * le plein écran (même règle que la fenêtre principale) */
        if (controlsHiddenForPlayback) {
            [self revealControlsForPlayback];
            return;
        }
        [VLCLegacyGetCore() toggleFullscreen];
        return;
    }
    [super mouseDown:event];
}

- (void)keyDown:(NSEvent *)event
{
    /* Full 3.0.23 behavior: every key goes to the core hotkey engine */
    if (!VLCLegacyHandleKeyEvent([VLCLegacyGetCore() intf], event))
        [super keyDown:event];
}

- (void)scrollWheel:(NSEvent *)event
{
    /* wheel = volume + native OSD bar, through the core hotkeys */
    VLCLegacyHandleScrollWheel([VLCLegacyGetCore() intf], event);
}

- (void)rightMouseDown:(NSEvent *)event
{
    id delegate = [NSApp delegate];
    if ([delegate respondsToSelector:@selector(menuController)]) {
        id menuController =
            [delegate performSelector:@selector(menuController)];
        if ([menuController respondsToSelector:@selector(voutMenu)]) {
            [NSMenu popUpContextMenu:
                [menuController performSelector:@selector(voutMenu)]
                           withEvent:event
                             forView:[self contentView]];
            return;
        }
    }
    [super rightMouseDown:event];
}

/* ⚠ BASCULE PLEIN ÉCRAN SANS ANIMATION (`animate:NO`).
 * L'animation de redimensionnement coûte cher sur un G3 — c'est la lenteur
 * ressentie à chaque bascule — et surtout elle publie une géométrie
 * INTERMÉDIAIRE : le vout calculait son rectangle sur une étape de l'animation
 * (mesuré : 690x388) et ne le recalculait plus une fois la fenêtre arrivée à sa
 * taille finale. La vidéo restait alors dans un coin d'une fenêtre plus grande,
 * le reste en blanc — le framebuffer OpenGL n'étant jamais peint quand le
 * décodage matériel est en mode remplacement. */
- (void)enterFullscreen
{
    NSScreen *screen = [self screen];
    NSRect target;

    /* le coeur peut republier l'état : sans ce garde-fou, initialFrame serait
     * écrasé par le cadre PLEIN ÉCRAN et la sortie n'aurait plus où revenir */
    if (fullscreenActive)
        return;
    /* ⚠ Révéler AVANT la transition : sinon `initialFrame` mémorise le cadre
     * RÉTRACTÉ et la sortie de plein écran rendrait une fenêtre trop courte,
     * avec une barre remise sur une hauteur qui ne l'attend pas. */
    [self revealControlsForPlayback];
    target = [screen frame];
    initialFrame = [self frame];
    /* La barre de contrôles s'efface : en plein écran c'est le panneau
     * flottant (VLCLegacyFSPanel) qui prend le relais, exactement comme pour
     * la vidéo embarquée. L'image récupère toute la hauteur. */
    if (controlsBar != nil)
        VLCLegacySetViewHidden(controlsBar, YES);
    /* fenêtre titrée : viser le CONTENU plein écran, la barre de titre sort
     * par le haut (la contrainte AppKit est levée, cf. -constrainFrameRect:) */
    if (decorated)
        target = [NSWindow frameRectForContentRect:target
                                         styleMask:[self styleMask]];
    fullscreenActive = YES;
    fullscreenFrame = target;
    [self setFrame:target display:YES animate:NO];
    [videoView setFrame:[self videoAreaRect]];

    if ([screen hasMenuBar] || [screen hasDock])
        SetSystemUIMode(kUIModeAllHidden, kUIOptionAutoShowMenuBar);

    /* Écran à encoche : la fenêtre couvre bien tout l'écran, mais l'image
     * s'arrête sous la bande de la caméra — le fond NOIR de la fenêtre la
     * remplit, comme le fait le plein écran natif. */
    NSRect safe = VLCLegacySafeContentRect(self, screen);
    notchAdjusted = !NSEqualRects(safe, [[self contentView] bounds]);
    if (notchAdjusted)
        [self resizeVideoSubviewsTo:safe];
}

- (void)leaveFullscreen
{
    /* ⚠ Le coeur envoie SET_FULLSCREEN(0) dès l'ouverture du vout (cf.
     * WindowOpen) : sans ce garde-fou, la fenêtre était aussitôt recadrée sur
     * `initialFrame` — donc renvoyée au coin bas-gauche demandé par le vout,
     * annulant le -center de l'init. */
    if (!fullscreenActive)
        return;
    SetSystemUIMode(kUIModeNormal, 0);
    fullscreenActive = NO;
    if (controlsBar != nil)
        VLCLegacySetViewHidden(controlsBar, NO);
    notchAdjusted = NO;
    /* La vue vidéo est redimensionnable. Si l'on restaure directement le
     * cadre, AppKit l'étale d'abord sur TOUT le contentView avant que nous la
     * recadrions au-dessus de la barre. La surface ATI recouvre alors la
     * barre pendant une composition et le WindowServer 10.3 ne repeint plus
     * ce qu'elle a découvert (barre blanche, seekbar seule). Le helper gèle
     * précisément l'autoresize pendant la transition puis redimensionne les
     * sous-vues du vout : leur -reshape republie également la géométrie du
     * plan subpicture matériel après la sortie du plein écran. */
    [self setWindowFrameKeepingVideoArea:initialFrame];
}

/* La vue confiée au vout est `videoView` (cf. -buildContentViews) : on la
 * recadre d'ici, comme -syncVideoSubviews côté fenêtre principale. La surface
 * accélérée, posée dedans en NSViewWidth|HeightSizable, suit toute seule. */
- (void)resizeVideoSubviewsTo:(NSRect)rect
{
    [videoView setFrame:rect];
    /* la vue accélérée du vout remplit son parent, mais son -reshape ne
     * republie la géométrie que si son propre cadre bouge */
    NSArray *subviews = [videoView subviews];
    unsigned i;
    for (i = 0; i < [subviews count]; i++)
        [[subviews objectAtIndex:i] setFrame:[videoView bounds]];
}

@end
