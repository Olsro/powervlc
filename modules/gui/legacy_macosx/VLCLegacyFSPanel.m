/*****************************************************************************
 * VLCLegacyFSPanel.m: fullscreen controller panel for the legacy interface
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

#import "VLCLegacyFSPanel.h"

void VLCLegacyCursorActivity(void);      /* intf.m */
void VLCLegacyCursorSetHidden(bool);     /* intf.m */
#import "misc.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyMain.h"
#import "VLCLegacyMainWindow.h"
#import "VLCLegacyControls.h"

#include <vlc_playlist.h>
#include <vlc_input.h>
#include <vlc_vout.h>

#define FS_PANEL_HIDE_DELAY 4.0

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/* the 3.0 fullscreen controller background: rounded dark rectangle
 * (the NSVisualEffectView blur needs 10.10; 3.0 itself falls back to a
 * plain dark layer on older releases) */
@interface VLCLegacyFSBackgroundView : NSView
@end

@implementation VLCLegacyFSBackgroundView
- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor colorWithCalibratedWhite:0.0f alpha:0.8f] set];
    [VLCLegacyRoundedRectPath([self bounds], 8.0f) fill];
}
@end

/* The lockFocus + NSCompositeSourceAtop tinting of the PDF templates
 * renders solid filled rectangles on the Mac OS X 10.4 AppKit; fall back
 * to the VLC 2.x fullscreen artwork there (white glyphs shipped with
 * dedicated highlight variants). */
static BOOL fsUseLegacyArtwork(void)
{
    return floor(NSAppKitVersionNumber) < 949; /* 949 = first 10.5 AppKit */
}

static NSString *fsLegacyArtworkName(NSString *templateName)
{
    static NSDictionary *map = nil;
    if (!map)
        map = [[NSDictionary dictionaryWithObjectsAndKeys:
            @"fs_volume_mute",     @"VLCVolumeOffTemplate",
            @"fs_volume_max",      @"VLCVolumeOnTemplate",
            @"fs_skip_previous",   @"VLCPreviousTemplate",
            @"fs_rewind",          @"VLCBackwardTemplate",
            @"fs_play",            @"VLCPlayTemplate",
            @"fs_pause",           @"VLCPauseTemplate",
            @"fs_forward",         @"VLCForwardTemplate",
            @"fs_skip_next",       @"VLCNextTemplate",
            @"fs_exit_fullscreen", @"VLCFullscreenOnTemplate",
            nil] retain];
    return [map objectForKey:templateName];
}

static NSImage *fsPanelImage(NSString *name, NSSize size, BOOL highlighted)
{
    if (fsUseLegacyArtwork()) {
        NSString *base = fsLegacyArtworkName(name);
        if (base) {
            NSImage *img = VLCLegacyImage(highlighted
                ? [base stringByAppendingString:@"_highlight"] : base);
            if (img)
                return img;
        }
    }
    return VLCLegacyTintedImage(name, size,
        highlighted ? [NSColor colorWithCalibratedWhite:0.6f alpha:1.0f]
                    : [NSColor whiteColor]);
}

/* white-rendered template artwork, like the 3.0 panel buttons */
static NSButton *fsTemplateButton(NSView *parent, NSString *name,
                                  NSRect frame, id target, SEL action)
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setButtonType:NSMomentaryChangeButton];
    [button setBordered:NO];
    [button setImage:fsPanelImage(name, frame.size, NO)];
    [button setAlternateImage:fsPanelImage(name, frame.size, YES)];
    [button setTarget:target];
    [button setAction:action];
    [parent addSubview:button];
    return button;
}

@implementation VLCLegacyFSPanel

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
{
    if (self = [super init]) {
        core = [interaction retain];
        p_intf = [interaction intf];
        lastRunningState = -1;
    }
    return self;
}

- (void)dealloc
{
    [pollTimer invalidate];
    [panel release];
    [core release];
    [super dealloc];
}

static NSString *fsTimeToString(int seconds)
{
    if (seconds < 0)
        seconds = 0;
    if (seconds >= 3600)
        return [NSString stringWithFormat:@"%d:%02d:%02d",
                seconds / 3600, (seconds / 60) % 60, seconds % 60];
    return [NSString stringWithFormat:@"%02d:%02d",
            seconds / 60, seconds % 60];
}

- (void)buildPanel
{
    /* Geometry of the 3.0 fullscreen controller: time and title on top,
     * the seek bar across, transport centered at the bottom with the
     * volume on the left and the exit button on the right. */
    NSRect screenFrame = [[NSScreen mainScreen] frame];
    NSRect rect = NSMakeRect(screenFrame.origin.x
                                 + (screenFrame.size.width - 550) / 2,
                             screenFrame.origin.y + 90, 550, 84);
    panel = [[NSPanel alloc] initWithContentRect:rect
                                       styleMask:NSBorderlessWindowMask
                                         backing:NSBackingStoreBuffered
                                           defer:NO];
    [panel setLevel:NSFloatingWindowLevel];
    [panel setOpaque:NO];
    [panel setBackgroundColor:[NSColor clearColor]];
    [panel setMovableByWindowBackground:YES];
    [panel setHidesOnDeactivate:NO];
    [panel setBecomesKeyOnlyIfNeeded:YES];
    [panel setReleasedWhenClosed:NO];
    NSView *content = [panel contentView];

    VLCLegacyFSBackgroundView *background =
        [[[VLCLegacyFSBackgroundView alloc]
            initWithFrame:NSMakeRect(0, 0, 550, 84)] autorelease];
    [background setAutoresizingMask:NSViewWidthSizable
                                   | NSViewHeightSizable];
    [content addSubview:background];

    /* --- top row: elapsed, media title, total --- */
    timeField = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(12, 63, 60, 14)] autorelease];
    [timeField setEditable:NO];
    [timeField setBordered:NO];
    [timeField setDrawsBackground:NO];
    [timeField setTextColor:[NSColor whiteColor]];
    [[timeField cell] setFont:[NSFont systemFontOfSize:10]];
    [timeField setAlignment:NSLeftTextAlignment];
    [timeField setStringValue:@"00:00"];
    [content addSubview:timeField];

    mediaTitleField = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(80, 62, 390, 15)] autorelease];
    [mediaTitleField setEditable:NO];
    [mediaTitleField setBordered:NO];
    [mediaTitleField setDrawsBackground:NO];
    [mediaTitleField setTextColor:[NSColor whiteColor]];
    [mediaTitleField setAlignment:NSCenterTextAlignment];
    [[mediaTitleField cell] setFont:[NSFont boldSystemFontOfSize:11]];
    VLCLegacySetCellLineBreakMode([mediaTitleField cell], NSLineBreakByTruncatingTail);
    [mediaTitleField setStringValue:@""];
    [content addSubview:mediaTitleField];

    durationField = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(478, 63, 60, 14)] autorelease];
    [durationField setEditable:NO];
    [durationField setBordered:NO];
    [durationField setDrawsBackground:NO];
    [durationField setTextColor:[NSColor whiteColor]];
    [[durationField cell] setFont:[NSFont systemFontOfSize:10]];
    [durationField setAlignment:NSRightTextAlignment];
    [durationField setStringValue:@"00:00"];
    [content addSubview:durationField];

    /* --- seek bar across --- */
    seekSlider = [[[NSSlider alloc]
        initWithFrame:NSMakeRect(12, 42, 526, 18)] autorelease];
    VLCLegacyProgressSliderCell *seekCell =
        [[[VLCLegacyProgressSliderCell alloc] init] autorelease];
    [seekCell setAlwaysDark:YES];
    [seekSlider setCell:seekCell];
    [seekSlider setToolTip:_NS("Position")];
    [seekSlider setMinValue:0.0];
    [seekSlider setMaxValue:1.0];
    [seekSlider setContinuous:NO];
    [seekSlider setTarget:self];
    [seekSlider setAction:@selector(seeked:)];
    [content addSubview:seekSlider];

    /* --- bottom row --- */
    /* volume on the left, thin slider with the 100% mark */
    [fsTemplateButton(content, @"VLCVolumeOffTemplate",
        NSMakeRect(14, 15, 8, 13), self, @selector(muteVolume:))
        setToolTip:_NS("Mute")];
    volumeSlider = [[[NSSlider alloc]
        initWithFrame:NSMakeRect(28, 13, 100, 17)] autorelease];
    VLCLegacyProgressSliderCell *volumeCell =
        [[[VLCLegacyProgressSliderCell alloc] init] autorelease];
    [volumeCell setAlwaysDark:YES];
    [volumeCell setVolumeStyle:YES];
    [volumeCell setKnobInset:1.0f];
    [volumeSlider setCell:volumeCell];
    [volumeSlider setToolTip:_NS("Volume")];
    [volumeSlider setMinValue:0.0];
    [volumeSlider setMaxValue:1.25];
    [volumeSlider setContinuous:YES];
    [volumeSlider setTarget:self];
    [volumeSlider setAction:@selector(volumeChanged:)];
    [content addSubview:volumeSlider];
    [fsTemplateButton(content, @"VLCVolumeOnTemplate",
        NSMakeRect(134, 15, 15, 13), self, @selector(maxVolume:))
        setToolTip:_NS("Full Volume")];

    /* Transport, centré sur la largeur du panneau (550).
     * ⚠ Sous 10.3/10.4 les illustrations sont utilisées à leur TAILLE
     * NATURELLE (fsPanelImage renvoie l'image telle quelle, sans mise à
     * l'échelle) : un bouton plus étroit que son image la ROGNE — c'est ce qui
     * amputait les triangles de rembobinage et d'avance (image 42 px de large
     * dans un bouton de 28). Les cadres ci-dessous reprennent donc exactement
     * les dimensions des images : 30x19 précédent/suivant, 42x20
     * rembobinage/avance, 34x28 lecture. */
    [fsTemplateButton(content, @"VLCPreviousTemplate",
        NSMakeRect(174, 12, 30, 19), self, @selector(prev:))
        setToolTip:_NS("Previous")];
    [fsTemplateButton(content, @"VLCBackwardTemplate",
        NSMakeRect(210, 11, 42, 20), self, @selector(backward:))
        setToolTip:_NS("Backward")];
    playButton = fsTemplateButton(content, @"VLCPlayTemplate",
        NSMakeRect(258, 7, 34, 28), self, @selector(playPause:));
    [playButton setToolTip:_NS("Play/Pause")];
    [fsTemplateButton(content, @"VLCForwardTemplate",
        NSMakeRect(298, 11, 42, 20), self, @selector(forward:))
        setToolTip:_NS("Forward")];
    [fsTemplateButton(content, @"VLCNextTemplate",
        NSMakeRect(346, 12, 30, 19), self, @selector(next:))
        setToolTip:_NS("Next")];

    /* exit fullscreen, far right */
    [fsTemplateButton(content, @"VLCFullscreenOnTemplate",
        NSMakeRect(512, 11, 21, 21), self, @selector(leaveFullscreen:))
        setToolTip:_NS("Leave fullscreen")];
}

/* debug hook (VLC_LEGACY_SHOW=fspanel): shows the panel without a
 * fullscreen vout, for headless snapshots */
- (void)debugShow
{
    if (!panel)
        [self buildPanel];
    [self refreshControls];
    [panel orderFront:nil];
}

- (void)activate
{
    lastMouseLocation = [NSEvent mouseLocation];
    lastActivity = [NSDate timeIntervalSinceReferenceDate];
    /* Cadence réduite sous 10.4 : cf. le tic de la fenêtre principale. */
    pollTimer = [NSTimer scheduledTimerWithTimeInterval:
                     (VLCLegacyOSVersionAtLeast(10, 4, 0) ? 0.3 : 1.0)
                                                 target:self
                                               selector:@selector(poll:)
                                               userInfo:nil
                                                repeats:YES];
}

- (void)shutdown
{
    [pollTimer invalidate];
    pollTimer = nil;
    [panel orderOut:nil];
}

/*****************************************************************************
 * actions
 *****************************************************************************/

- (void)playPause:(id)sender       { [core togglePlayPause]; }
- (void)prev:(id)sender            { [core previous]; }
- (void)next:(id)sender            { [core next]; }
- (void)backward:(id)sender        { [core jumpWithSeconds:-10]; }
- (void)forward:(id)sender         { [core jumpWithSeconds:10]; }
- (void)muteVolume:(id)sender      { [core toggleMute]; }
- (void)maxVolume:(id)sender       { [core setVolume:1.25f];
                                     [volumeSlider setFloatValue:1.25f]; }
- (void)volumeChanged:(id)sender   { [core setVolume:[sender floatValue]]; }
- (void)leaveFullscreen:(id)sender { [core toggleFullscreen]; }

- (void)seeked:(id)sender
{
    [core setPositionFraction:[sender floatValue]];
    lastActivity = [NSDate timeIntervalSinceReferenceDate];
}

/*****************************************************************************
 * visibility engine
 *****************************************************************************/

- (BOOL)voutIsFullscreen
{
    BOOL result = NO;
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return NO;
    vout_thread_t *p_vout = input_GetVout(p_input);
    if (p_vout) {
        result = var_GetBool(p_vout, "fullscreen");
        vlc_object_release(p_vout);
    }
    vlc_object_release(p_input);
    return result;
}

- (void)poll:(NSTimer *)timer
{
    double now = [NSDate timeIntervalSinceReferenceDate];

    /* Le suivi du pointeur tourne à CHAQUE tic, y compris hors plein écran :
     * c'est lui qui pilote le masquage du curseur dans les deux modes (le
     * coeur en est incapable, cf. intf.m). Seule la recherche d'un vout plein
     * écran, plus coûteuse, reste espacée. */
    NSPoint mouse = [NSEvent mouseLocation];
    if (!NSEqualPoints(mouse, lastMouseLocation)) {
        lastMouseLocation = mouse;
        lastActivity = now;
        VLCLegacyCursorActivity();   /* mouvement → pointeur rendu */
    }

    if (!fullscreenActive) {
        /* FENÊTRÉ : masquer seulement si le pointeur est immobile AU-DESSUS
         * DE L'IMAGE (ailleurs — contrôles, barre de titre, autre app — il
         * doit rester visible). */
        BOOL b_over_video = NO;
        /* ⚠ +sharedInstance N'EXISTE PAS sur VLCLegacyMain : l'appeler levait
         * une exception qui interrompait TOUT le sondage en silence (ni
         * masquage, ni trace). L'objet principal est le délégué de NSApp. */
        NSView *vv = nil;
        id appDelegate = [NSApp delegate];
        if ([appDelegate respondsToSelector:@selector(mainWindowController)])
            vv = [[(VLCLegacyMain *)appDelegate mainWindowController]
                      videoViewIfVisible];
        NSWindow *vw = (vv != nil) ? [vv window] : nil;
        if (vw != nil && [vw isVisible]) {
            NSRect r = [vv convertRect:[vv bounds] toView:nil];
            r.origin.x += [vw frame].origin.x;
            r.origin.y += [vw frame].origin.y;
            b_over_video = NSPointInRect(mouse, r);
        }
        VLCLegacyCursorSetHidden(b_over_video
                                 && (now - lastActivity) >= FS_PANEL_HIDE_DELAY);

        if (++dormantTicks < 3)
            return;
        dormantTicks = 0;
    }

    BOOL fullscreen = [self voutIsFullscreen];
    /* so does hovering the panel itself */
    if (panel && [panel isVisible]
        && NSPointInRect(mouse, [panel frame]))
        lastActivity = now;

    if (!fullscreen) {
        if (fullscreenActive) {
            fullscreenActive = NO;
            [panel orderOut:nil];
        }
        return;
    }

    if (!fullscreenActive) {
        fullscreenActive = YES;
        lastActivity = now;
    }

    BOOL shouldShow = (now - lastActivity) < FS_PANEL_HIDE_DELAY;
    /* Le pointeur suit le panneau : masqué avec lui, rendu avec lui. Un seul
     * propriétaire, donc aucun risque d'état incohérent ni de curseur perdu. */
    VLCLegacyCursorSetHidden(!shouldShow);
    if (shouldShow) {
        if (!panel)
            [self buildPanel];
        if (![panel isVisible])
            [panel orderFront:nil];
        [self refreshControls];
    } else if (panel && [panel isVisible]) {
        [panel orderOut:nil];
    }
}

- (void)refreshControls
{
    playlist_t *p_playlist = pl_Get(p_intf);
    playlist_Lock(p_playlist);
    int status = playlist_Status(p_playlist);
    playlist_Unlock(p_playlist);
    BOOL running = status == PLAYLIST_RUNNING;
    /* re-tinting on every poll tick would be wasteful */
    if (lastRunningState != (int)running) {
        lastRunningState = (int)running;
        NSString *playImage = running ? @"VLCPauseTemplate"
                                      : @"VLCPlayTemplate";
        [playButton setImage:fsPanelImage(playImage, NSMakeSize(30, 30), NO)];
        [playButton setAlternateImage:fsPanelImage(playImage,
                                                   NSMakeSize(30, 30), YES)];
    }

    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (p_input) {
        char *psz_title = input_item_GetTitleFbName(input_GetItem(p_input));
        if (psz_title) {
            NSString *title = [NSString stringWithUTF8String:psz_title];
            free(psz_title);
            if (![[mediaTitleField stringValue] isEqualToString:title])
                [mediaTitleField setStringValue:title];
        }
        int seconds = (int)(var_GetInteger(p_input, "time") / CLOCK_FREQ);
        int total = (int)(var_GetInteger(p_input, "length") / CLOCK_FREQ);
        /* Ne toucher les champs QUE si le texte change : un setStringValue:
         * identique redessine quand même, et sur Mac OS X 10.3 chaque redessin
         * de glyphes passe par un RPC au serveur de polices (~140 ms la barre)
         * — c'est ce qui rendait le PLEIN ÉCRAN scintillant alors que le mode
         * fenêtré venait d'être corrigé (même classe de bug que le tic de la
         * barre principale). Idem pour le slider, dont chaque setFloatValue
         * salit tout le panneau. */
        NSString *newTime = fsTimeToString(seconds);
        if (![[timeField stringValue] isEqualToString:newTime])
            [timeField setStringValue:newTime];
        NSString *newTotal = fsTimeToString(total);
        if (![[durationField stringValue] isEqualToString:newTotal])
            [durationField setStringValue:newTotal];
        float pos = var_GetFloat(p_input, "position");
        if ([seekSlider floatValue] != pos)
            [seekSlider setFloatValue:pos];
        vlc_object_release(p_input);
    }
    [volumeSlider setFloatValue:[core volume]];
}

@end
