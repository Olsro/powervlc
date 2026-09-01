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
void VLCLegacyCursorSetHiddenOnDisplay(bool, CGDirectDisplayID); /* intf.m */
#import "misc.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyMain.h"
#import "VLCLegacyMainWindow.h"
#import "VLCLegacyControls.h"
#import "VLCLegacySeekThumbnailer.h"
#import "VLCLegacyVoutWindow.h"

#include <vlc_playlist.h>
#include <vlc_input.h>
#include <vlc_vout.h>
#include <dlfcn.h>

#define FS_PANEL_HIDE_DELAY 4.0

/* declared up front: GCC 4 warns about messages to methods defined
 * further down the file */
@interface VLCLegacyFSPanel (ChaptersPrivate)
- (void)updateChaptersForInput:(input_thread_t *)p_input
                      duration:(int64_t)i_length;
- (void)updateStereoMirrorPanel;
- (void)videoMouseActivity:(NSNotification *)notification;
@end

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

/* AppKit can keep the ordinary 1080-line NSScreen geometry after DCP has
 * switched the projector to a 2205-line frame-packed raster.  NSWindow then
 * constrains a user drag against those stale bounds when the mouse is
 * released, visibly snapping the controller back to its original place.
 * The panel is deliberately user-positionable on the complete HDMI raster;
 * WindowServer, not the stale NSScreen cache, is authoritative here. */
@interface VLCLegacyFSPanelWindow : NSPanel
@end

@implementation VLCLegacyFSPanelWindow
- (NSRect)constrainFrameRect:(NSRect)frameRect toScreen:(NSScreen *)screen
{
    (void)screen;
    return frameRect;
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
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(videoMouseActivity:)
                   name:@"VLCLegacyVideoMouseActivity"
                 object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(videoMouseActivity:)
                   name:NSApplicationDidBecomeActiveNotification
                 object:nil];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [pollTimer invalidate];
    free(chaptersUri);
    [stereoMirrorPanel release];
    [panel release];
    [core release];
    [super dealloc];
}

static NSScreen *fsStereoScreen(intf_thread_t *p_intf)
{
    int display = (int)var_InheritInteger(p_intf,
                                          "stereo3d-fullscreen-display");
    if (display <= 0)
        return nil;
    NSArray *screens = [NSScreen screens];
    for (NSUInteger i = 0; i < [screens count]; ++i) {
        NSScreen *screen = [screens objectAtIndex:i];
        NSNumber *number = [[screen deviceDescription]
                            objectForKey:@"NSScreenNumber"];
        if ([number intValue] == display)
            return screen;
    }
    return nil;
}

static BOOL fsStereoEyeStride(NSScreen *screen, CGFloat *stride)
{
    /* A private CGS mode switch updates CGDisplayBounds immediately, while
     * Mavericks can keep the existing NSScreen's -frame at the previous
     * 1920x1080 size.  Using that stale height disables the second-eye copy
     * and leaves the controller apparently high in (or visible to only one
     * eye of) the projected image. */
    CGFloat height = screen ? NSHeight(VLCLegacyLiveScreenFrame(screen)) : 0.;
    CGFloat gap;
    if (fabs(height - 2205.) < 2.)
        gap = 45.;
    else if (fabs(height - 1470.) < 2.)
        gap = 30.;
    else
        return NO;
    *stride = (height - gap) / 2. + gap;
    return YES;
}

/* The polling implementation predates event monitors and sees the global
 * pointer.  In a multi-display setup that does not mean every movement is an
 * activity of the fullscreen video: moving on the Mac panel must not wake the
 * controller floating on the HDMI projector. */
static BOOL fsMouseIsOnScreen(NSPoint mouse, NSScreen *screen)
{
    return screen != nil
        && NSPointInRect(mouse, VLCLegacyLiveScreenFrame(screen));
}

static CGDirectDisplayID fsDisplayID(NSScreen *screen)
{
    NSNumber *number = screen == nil ? nil :
        [[screen deviceDescription] objectForKey:@"NSScreenNumber"];
    return number == nil ? kCGDirectMainDisplay
                         : (CGDirectDisplayID)[number unsignedIntValue];
}

static BOOL fsMoveWindowViaWindowServer(NSWindow *window,
                                        CGFloat x, CGFloat y)
{
    typedef int (*CGSMainConnectionIDFunc)(void);
    typedef int (*CGSMoveWindowFunc)(int, int, const CGPoint *);
    static CGSMainConnectionIDFunc mainConnection;
    static CGSMoveWindowFunc moveWindow;
    /* This controller is main-thread-only. Avoid dispatch_once and blocks:
     * neither is available in the 10.4 SDK used for the i386 slice. */
    static BOOL attempted = NO;
    if (!attempted) {
        attempted = YES;
        void *framework = dlopen(
            "/System/Library/Frameworks/ApplicationServices.framework/"
            "ApplicationServices", RTLD_LAZY | RTLD_LOCAL);
        if (framework) {
            mainConnection = (CGSMainConnectionIDFunc)
                dlsym(framework, "CGSMainConnectionID");
            moveWindow = (CGSMoveWindowFunc)
                dlsym(framework, "CGSMoveWindow");
        }
    }
    if (!window || !mainConnection || !moveWindow)
        return NO;
    CGPoint point = CGPointMake(x, y);
    return moveWindow(mainConnection(), (int)[window windowNumber], &point) == 0;
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
    NSScreen *targetScreen = fsStereoScreen(p_intf);
    if (!targetScreen)
        targetScreen = [NSScreen mainScreen];
    NSRect screenFrame = VLCLegacyLiveScreenFrame(targetScreen);
    CGFloat eyeStride = 0.;
    BOOL framePacked = fsStereoEyeStride(targetScreen, &eyeStride);
    NSRect rect = NSMakeRect(screenFrame.origin.x
                                 + (screenFrame.size.width - 550) / 2,
                             framePacked ? eyeStride + 90.
                                         : screenFrame.origin.y + 90.,
                             550, 84);
    panel = [[VLCLegacyFSPanelWindow alloc] initWithContentRect:rect
                                                       styleMask:NSBorderlessWindowMask
                                                         backing:NSBackingStoreBuffered
                                                           defer:NO];
    [panel setAcceptsMouseMovedEvents:YES];
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
    /* VLCLegacySeekSlider: brings the live time/chapter/preview tooltip
     * and the chapter separators, like the Qt fullscreen controller (no
     * static "Position" tooltip: it would fight with the live one) */
    seekSlider = [[[VLCLegacySeekSlider alloc]
        initWithFrame:NSMakeRect(12, 42, 526, 18)] autorelease];
    VLCLegacyProgressSliderCell *seekCell =
        [[[VLCLegacyProgressSliderCell alloc] init] autorelease];
    [seekCell setAlwaysDark:YES];
    [seekSlider setCell:seekCell];
    [(VLCLegacySeekSlider *)seekSlider setHoverDelegate:self];
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

    /* On Mavericks AppKit can retain geometry from before the private HDMI
     * mode switch. Move the owned window through WindowServer coordinates;
     * unlike AX this requires no accessibility authorization. */
    CGFloat physicalEyeHeight = framePacked
        ? (eyeStride > 1000. ? 1080. : 720.)
        : MIN(NSHeight(screenFrame), 1080.);
    CGFloat physicalX = screenFrame.origin.x
        + (NSWidth(screenFrame) - NSWidth([panel frame])) / 2.;
    /* Quartz/CGS uses top-left coordinates. Keep the same physical target as
     * the modern controller: Y=900 for a 1080-line eye, Y=540 for 720. */
    CGFloat physicalY = MAX(physicalEyeHeight - 180., 0.);
    fsMoveWindowViaWindowServer(panel, physicalX, physicalY);
}

- (void)updateStereoMirrorPanel
{
    NSScreen *screen = fsStereoScreen(p_intf);
    CGFloat eyeStride;
    if (!panel || ![panel isVisible]
        || !fsStereoEyeStride(screen, &eyeStride)) {
        [stereoMirrorPanel orderOut:nil];
        return;
    }

    NSRect screenFrame = VLCLegacyLiveScreenFrame(screen);
    NSRect panelFrame = [panel frame];
    if (!stereoMirrorPanel) {
        stereoMirrorPanel = [[NSPanel alloc]
            initWithContentRect:[panel frame]
                      styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered defer:NO];
        [stereoMirrorPanel setOpaque:NO];
        [stereoMirrorPanel setBackgroundColor:[NSColor clearColor]];
        [stereoMirrorPanel setHasShadow:NO];
        [stereoMirrorPanel setIgnoresMouseEvents:YES];
        [stereoMirrorPanel setHidesOnDeactivate:NO];
        [stereoMirrorPanel setReleasedWhenClosed:NO];
        stereoMirrorImageView = [[[NSImageView alloc]
            initWithFrame:[[stereoMirrorPanel contentView] bounds]] autorelease];
        [stereoMirrorImageView setImageScaling:NSScaleToFit];
        [stereoMirrorImageView setAutoresizingMask:
            NSViewWidthSizable | NSViewHeightSizable];
        [[stereoMirrorPanel contentView] addSubview:stereoMirrorImageView];
    }

    NSView *content = [panel contentView];
    [content displayIfNeeded];
    NSRect bounds = [content bounds];
    NSBitmapImageRep *rep =
        [content bitmapImageRepForCachingDisplayInRect:bounds];
    if (!rep)
        return;
    [content cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSImage *image = [[[NSImage alloc] initWithSize:bounds.size] autorelease];
    [image addRepresentation:rep];
    [stereoMirrorImageView setImage:image];

    NSRect frame = panelFrame;
    BOOL sourceIsLowerEye = NSMidY(frame) < NSMidY(screenFrame);
    frame.origin.y += sourceIsLowerEye ? eyeStride : -eyeStride;
    int depth = (int)var_InheritInteger(p_intf, "stereo3d-overlay-depth");
    depth = MAX(-100, MIN(100, depth));
    CGFloat fullDisparity = NSWidth(screenFrame) * .04 * depth / 100.;
    frame.origin.x += sourceIsLowerEye ? fullDisparity : -fullDisparity;

    [seekSlider refreshHoverForCurrentMouseLocation];
    if (!NSEqualRects([stereoMirrorPanel frame], frame))
        [stereoMirrorPanel setFrame:frame display:NO];
    [stereoMirrorPanel setLevel:[panel level]];
    if (![stereoMirrorPanel isVisible])
        [stereoMirrorPanel orderFront:nil];
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

- (void)videoMouseActivity:(NSNotification *)notification
{
    (void)notification;
    lastMouseLocation = [NSEvent mouseLocation];
    lastActivity = [NSDate timeIntervalSinceReferenceDate];
    VLCLegacyCursorActivity();
}

- (void)shutdown
{
    [pollTimer invalidate];
    pollTimer = nil;
    [panel orderOut:nil];
    [stereoMirrorPanel orderOut:nil];
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
    if ([core clipCreationMode]) {
        /* same routing as the windowed seek bar: both knobs define the
         * clip bounds and moving either one seeks there, so the user
         * previews what the clip will contain */
        VLCLegacyProgressSliderCell *seekCell =
            (VLCLegacyProgressSliderCell *)[seekSlider cell];
        float fraction;
        int knob = [seekCell activeClipKnob];
        if (knob == 2) {
            fraction = (float)[seekCell clipEndValue];
            [core setClipEndPosition:fraction];
            [core setClipSelectedKnob:2];
        } else if (knob == 3) {
            /* scrub between the bounds: seek only, bounds untouched */
            fraction = (float)[seekCell playbackMarkerValue];
        } else {
            fraction = [sender floatValue];
            [core setClipStartPosition:fraction];
            [core setClipSelectedKnob:1];
        }
        [core setPositionFraction:fraction];
        lastActivity = [NSDate timeIntervalSinceReferenceDate];
        return;
    }
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

    /* CGS disables and republishes displays during the Snow Leopard HDMI 3D
     * transaction.  NSEvent can report alternating coordinates in that short
     * interval; treating each as genuine activity balances Show/Hide on
     * successive displays and makes the hardware cursor flash.  Keep it
     * firmly hidden until the final topology and fullscreen window exist. */
    if (var_InheritBool(p_intf, "stereo3d-display-transition")
        && floor(NSAppKitVersionNumber) < 1343) {
        NSScreen *transitionScreen = fsStereoScreen(p_intf);
        VLCLegacyCursorSetHiddenOnDisplay(YES,
                                          fsDisplayID(transitionScreen));
        return;
    }

    /* Le suivi du pointeur tourne à CHAQUE tic, y compris hors plein écran :
     * c'est lui qui pilote le masquage du curseur dans les deux modes (le
     * coeur en est incapable, cf. intf.m). Seule la recherche d'un vout plein
     * écran, plus coûteuse, reste espacée. */
    NSPoint mouse = [NSEvent mouseLocation];
    if (!NSEqualPoints(mouse, lastMouseLocation)) {
        lastMouseLocation = mouse;
        VLCLegacyCursorActivity();   /* mouvement → pointeur rendu */

        /* While HDMI 3D is active, only movement inside that display wakes
         * its controller.  fsStereoScreen() deliberately follows the
         * transient 1920x2205/1280x1470 NSScreen, so this remains correct
         * after the display is republished during the mode switch. */
        NSScreen *stereoScreen = fsStereoScreen(p_intf);
        if (stereoScreen == nil || fsMouseIsOnScreen(mouse, stereoScreen))
            lastActivity = now;
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
        /* « Afficher la vidéo dans la fenêtre principale » décochée : l'image
         * n'est plus dans la fenêtre principale, c'est le contenu de la
         * fenêtre vidéo autonome qu'il faut survoler. */
        if (vv == nil)
            vv = [VLCLegacyCurrentVoutWindow() videoView];
        NSWindow *vw = (vv != nil) ? [vv window] : nil;
        BOOL videoVisible = vw != nil && [vw isVisible];
        /* Starting media by dropping it can create the vout without another
         * mouse-coordinate change after the drop.  Do not inherit the idle
         * time accumulated while the playlist was empty: a newly visible
         * video is cursor activity in its own right.  This also restores a
         * cursor hidden by the legacy display-transition guard as soon as the
         * final window becomes visible. */
        if (videoVisible && !windowedVideoWasVisible) {
            lastMouseLocation = mouse;
            lastActivity = now;
            VLCLegacyCursorActivity();
        }
        windowedVideoWasVisible = videoVisible;
        if (videoVisible) {
            NSRect r = [vv convertRect:[vv bounds] toView:nil];
            r.origin.x += [vw frame].origin.x;
            r.origin.y += [vw frame].origin.y;
            b_over_video = NSPointInRect(mouse, r);
        }
        VLCLegacyCursorSetHiddenOnDisplay(
            b_over_video && (now - lastActivity) >= FS_PANEL_HIDE_DELAY,
            fsDisplayID([vw screen]));

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
            VLCLegacyCursorActivity();
            [panel orderOut:nil];
            [stereoMirrorPanel orderOut:nil];
        }
        return;
    }

    if (!fullscreenActive) {
        fullscreenActive = YES;
        lastActivity = now;
    }

    NSScreen *stereoScreen = fsStereoScreen(p_intf);
    BOOL mouseOnFullscreenScreen = stereoScreen == nil
                                || fsMouseIsOnScreen(mouse, stereoScreen);
    BOOL shouldShow = mouseOnFullscreenScreen
                   && (now - lastActivity) < FS_PANEL_HIDE_DELAY;
    /* Le pointeur suit le panneau : masqué avec lui, rendu avec lui. Un seul
     * propriétaire, donc aucun risque d'état incohérent ni de curseur perdu. */
    NSScreen *cursorScreen = stereoScreen;
    if (cursorScreen == nil && panel != nil)
        cursorScreen = [panel screen];
    VLCLegacyCursorSetHiddenOnDisplay(mouseOnFullscreenScreen && !shouldShow,
                                      fsDisplayID(cursorScreen));
    if (shouldShow) {
        if (!panel)
            [self buildPanel];
        if (![panel isVisible])
            [panel orderFront:nil];
        [self refreshControls];
        [self updateStereoMirrorPanel];
    } else if (panel && [panel isVisible]) {
        [panel orderOut:nil];
        [stereoMirrorPanel orderOut:nil];
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
        VLCLegacyProgressSliderCell *clipCell =
            (VLCLegacyProgressSliderCell *)[seekSlider cell];
        if ([core clipCreationMode]) {
            /* the knobs hold the clip bounds; only the thin marker
             * follows the playback position (parity with the windowed
             * seek bar) */
            if (![clipCell clipKnobsActive])
                [clipCell setClipKnobsActive:YES];
            [seekSlider setDoubleValue:[core clipStartPosition]];
            [clipCell setClipEndValue:[core clipEndPosition]];
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
        int64_t length = var_GetInteger(p_input, "length");
        [(VLCLegacySeekSlider *)seekSlider
            setMediaDuration:(double)length / CLOCK_FREQ];
        [self updateChaptersForInput:p_input duration:length];
        VLCLegacyUpdateSliderBookmarks((VLCLegacySeekSlider *)seekSlider,
                                       p_input, length);
        vlc_object_release(p_input);
    } else {
        [(VLCLegacySeekSlider *)seekSlider setMediaDuration:0.0];
        [self updateChaptersForInput:NULL duration:0];
        VLCLegacyUpdateSliderBookmarks((VLCLegacySeekSlider *)seekSlider,
                                       NULL, 0);
        /* Stop leaves no input at all, and that is the only branch that
         * puts the clip knobs away (same fix as the windowed bar) */
        VLCLegacyProgressSliderCell *clipCell =
            (VLCLegacyProgressSliderCell *)[seekSlider cell];
        if ([clipCell clipKnobsActive]) {
            [clipCell setClipKnobsActive:NO];
            [seekSlider setNeedsDisplay:YES];
        }
    }
    [volumeSlider setFloatValue:[core volume]];
}

/* hover delegate of the seek slider (1 s debounce in the slider) */
- (void)seekSlider:(VLCLegacySeekSlider *)slider
        hoverThumbnailWantedAtFraction:(double)fraction
{
    [[VLCLegacySeekThumbnailer sharedInstance]
        requestThumbnailWithIntf:p_intf fraction:fraction forSlider:slider];
}

/* bare arrow keys while the slider is the first responder (clip mode) */
- (void)seekSlider:(VLCLegacySeekSlider *)slider
        clipStepFrames:(int)direction
{
    [core clipStepFrames:direction];
}

- (void)seekSlider:(VLCLegacySeekSlider *)slider
        bookmarkSelectedAtIndex:(int)index
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        input_Control(p_input, INPUT_SET_BOOKMARK, index);
        vlc_object_release(p_input);
    }
}

/* chapter separators, same rules and caching as the main window */
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

@end
