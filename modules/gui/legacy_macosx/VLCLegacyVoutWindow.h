/*****************************************************************************
 * VLCLegacyVoutWindow.h: macOS minimal vout window
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

#import <Cocoa/Cocoa.h>

/* NSUInteger n'est apparu qu'avec le SDK 10.5 ; la chaîne 10.4 a besoin des
 * définitions historiques (32 bits, ce que toutes les IHM 10.4 ont été). */
#ifndef NSINTEGER_DEFINED
typedef int NSInteger;
typedef unsigned int NSUInteger;
#define NSINTEGER_DEFINED 1
#endif

@interface VLCLegacyVoutWindow : NSWindow
{
    NSRect initialFrame;
    BOOL notchAdjusted;       /* image rognée sous l'encoche, plein écran */
    BOOL decorated;           /* barre de titre (option « video-deco ») */
    BOOL fullscreenActive;
    NSRect fullscreenFrame;   /* cadre visé en plein écran, à défendre */
    BOOL manualMoveActive;    /* borderless: AppKit 10.5 perd parfois son
                               * déplacement après un setFrame: animé */
    NSPoint manualMoveStartMouse;
    NSPoint manualMoveStartOrigin;

    /* La vue REMISE AU VOUT. Ce n'est pas le contentView : la fenêtre décorée
     * lui réserve la bande du bas pour sa barre de contrôles allégée, et la
     * vue accélérée du vout se pose en remplissant son parent. */
    NSView *videoView;

    /* Barre allégée, fenêtre décorée seulement (l'interface moderne fait de
     * même : sa « blank window » sans décoration n'a aucun contrôle). */
    NSView *controlsBar;
    NSButton *playButton;
    NSButton *backwardButton;
    NSButton *forwardButton;
    NSButton *fullscreenButton;
    NSSlider *seekSlider;
    NSTextField *timeField;
    NSTextField *durationField;
    NSTimer *refreshTimer;
    int lastRunningState;     /* -1 au départ : évite de re-teinter à chaque tic */

    /* Chapitres DVD : identité stable par URI et nouvelles tentatives tant que
     * dvdnav n'a pas encore publié les décalages temporels. */
    char *chaptersUri;
    int chaptersTitle;
    int64_t chaptersDuration;
    int chaptersRetryTicks;

    /* « Masquer les contrôles durant la lecture » appliqué à CETTE fenêtre */
    BOOL controlsHiddenForPlayback;
    double mouseOutsideSince;   /* NSTimeInterval, 0 = souris dans la fenêtre */
    BOOL styleMaskChangedForHiddenControls;
    NSUInteger styleMaskBeforeHidingControls;
    NSString *titleBeforeHidingControls;   /* setStyleMask: efface le titre */

    BOOL pausedByMiniaturize;   /* « Mettre en pause lors de l'iconification » */
}

- (id)initWithContentRect:(NSRect)contentRect decorated:(BOOL)b_decorated;

/* la vue à confier au vout (cf. WindowOpen) */
- (NSView *)videoView;

/* « Masquer les contrôles durant la lecture » : la révélation est aussi
 * demandée depuis le cœur, qui reçoit le double-clic des vouts d'époque
 * (cf. VLCLegacyCoreInteraction -revealControlsFromCore). */
- (void)revealControlsForPlayback;

- (void)setLevelFromNumber:(NSNumber *)value;
- (void)setSizeFromValue:(NSValue *)value;
- (void)enterFullscreen;
- (void)leaveFullscreen;
@end

/* Fenêtre vidéo AUTONOME courante, c'est-à-dire l'option « Afficher la vidéo
 * dans la fenêtre principale » décochée : nil sinon. Le panneau plein écran
 * (masquage du pointeur) et le titre de la fenêtre en ont besoin, et rien
 * d'autre ne les relie au vout. ⚠ THREAD PRINCIPAL uniquement. */
VLCLegacyVoutWindow *VLCLegacyCurrentVoutWindow(void);
