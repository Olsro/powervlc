/*****************************************************************************
 * VLCMainWindow.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2002-2018 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne -at- videolan -dot- org>
 *          Jon Lech Johansen <jon-vl@nanocrew.net>
 *          Christophe Massiot <massiot@via.ecp.fr>
 *          Derk-Jan Hartman <hartman at videolan.org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "VLCMainWindow.h"

#import "VLCMain.h"
#import "CompatibilityFixes.h"
#import "VLCCoreInteraction.h"
#import "VLCAudioEffectsWindowController.h"
#import "VLCMainMenu.h"
#import "VLCOpenWindowController.h"
#import "VLCPlaylist.h"
#import "VLCSidebarDataSource.h"
#import "VLCSourceListItem.h"

#import <math.h>
#import <vlc_playlist.h>
#import <vlc_rand.h>
#import <vlc_url.h>
#import <vlc_strings.h>
#import "VLCPLModel.h"

#import "PXSourceList/PXSourceList.h"

#import "VLCMainWindowControlsBar.h"
#import "VLCVoutView.h"
#import "VLCVoutWindowController.h"


/* The Qt main window keeps a black, image-centred surface behind playback:
 * it shows the cone while idle and the current artwork for audio.  Keep the
 * Cocoa implementation self-contained here so the 10.7 deployment floor is
 * unchanged and the same view can sit beside the existing split/video views. */
@interface VLCMainBackgroundView : NSView
{
    NSImage *defaultImage;
    NSImage *displayedImage;
    NSImage *colouredCone;
    NSArray *colouredCones;
    NSTimer *motionTimer;
    NSRect imageRect;
    NSPoint conePosition;
    NSPoint coneVelocity;
    NSTimeInterval lastMotionTime;
    NSUInteger coneColourIndex;
    BOOL showingCone;
    BOOL coneBouncing;
    BOOL trackingIdleClick;
    BOOL idleSurfaceDragged;
    BOOL idlePressWasOnCone;
    BOOL idlePressActivatesWindow;
    NSPoint idlePressLocation;
}
- (void)setArtwork:(NSImage *)artwork;
- (void)setBackgroundActive:(BOOL)active;
@end

static NSImage *VLCMainBackgroundTintedCone(NSImage *source, NSUInteger sector)
{
    static const NSUInteger coneHues[] = { 0, 30, 105, 165, 210, 285 };
    NSUInteger hue = coneHues[sector % (sizeof(coneHues) / sizeof(coneHues[0]))];
    NSUInteger hueSector = hue / 60;
    NSUInteger hueRemainder = hue % 60;
    NSSize sourceSize = [source size];
    if (sourceSize.width <= 0.0 || sourceSize.height <= 0.0)
        return source;
    CGFloat imageScale = MIN(1.0, MIN(128.0 / sourceSize.width,
                                      128.0 / sourceSize.height));
    NSInteger width = (NSInteger)ceil(sourceSize.width * imageScale);
    NSInteger height = (NSInteger)ceil(sourceSize.height * imageScale);
    size_t sourceRowBytes = (size_t)width * 4;
    unsigned char *pixels = calloc((size_t)height, sourceRowBytes);
    if (!pixels)
        return source;
    CGColorSpaceRef colourSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmapContext = CGBitmapContextCreate(pixels, width, height,
        8, sourceRowBytes, colourSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colourSpace);
    if (!bitmapContext) {
        free(pixels);
        return source;
    }
    CGContextSetRGBFillColor(bitmapContext, 0.0, 0.0, 0.0, 1.0);
    CGContextFillRect(bitmapContext, CGRectMake(0, 0, width, height));
    NSGraphicsContext *context = [NSGraphicsContext
        graphicsContextWithGraphicsPort:bitmapContext flipped:NO];
    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext:context];
    if ([context respondsToSelector:@selector(setImageInterpolation:)])
        [context setImageInterpolation:NSImageInterpolationHigh];
    [source drawInRect:NSMakeRect(0.0, 0.0, width, height)
              fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    [NSGraphicsContext restoreGraphicsState];
    CGContextRelease(bitmapContext);

    NSBitmapImageRep *tinted = [[NSBitmapImageRep alloc]
        initWithBitmapDataPlanes:NULL pixelsWide:width pixelsHigh:height
        bitsPerSample:8 samplesPerPixel:3 hasAlpha:NO isPlanar:NO
        colorSpaceName:NSCalibratedRGBColorSpace bytesPerRow:width * 3
        bitsPerPixel:24];
    if (!tinted) {
        free(pixels);
        return source;
    }
    unsigned char *destination = [tinted bitmapData];
    NSInteger destinationRowBytes = [tinted bytesPerRow];
    for (NSInteger y = 0; y < height; ++y) {
        unsigned char *sourceRow = pixels + (size_t)y * sourceRowBytes;
        unsigned char *destinationRow = destination + y * destinationRowBytes;
        for (NSInteger x = 0; x < width; ++x) {
            unsigned char *input = sourceRow + x * 4;
            unsigned char *output = destinationRow + x * 3;
            unsigned char maximum = MAX(input[0], MAX(input[1], input[2]));
            unsigned char minimum = MIN(input[0], MIN(input[1], input[2]));
            output[0] = input[0];
            output[1] = input[1];
            output[2] = input[2];
            if (maximum - minimum < 4)
                continue; /* retain the cone's white and grey bands */
            unsigned char rising = minimum +
                ((maximum - minimum) * hueRemainder + 30) / 60;
            unsigned char falling = maximum -
                ((maximum - minimum) * hueRemainder + 30) / 60;
            switch (hueSector) {
                case 0: output[0] = maximum; output[1] = rising; output[2] = minimum; break;
                case 1: output[0] = falling; output[1] = maximum; output[2] = minimum; break;
                case 2: output[0] = minimum; output[1] = maximum; output[2] = rising; break;
                case 3: output[0] = minimum; output[1] = falling; output[2] = maximum; break;
                case 4: output[0] = rising; output[1] = minimum; output[2] = maximum; break;
                default:output[0] = maximum; output[1] = minimum; output[2] = falling; break;
            }
        }
    }
    free(pixels);

    NSImage *result = [[NSImage alloc] initWithSize:NSMakeSize(width, height)];
    [result addRepresentation:tinted];
    return result;
}

@implementation VLCMainBackgroundView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        /* This surface deliberately uses the classic bare cone. The app icon
         * can be the Tahoe rounded-square variant on newer macOS releases,
         * which does not belong on the black playback background. */
        defaultImage = [NSImage imageNamed:@"VLC"];
        if (var_InheritBool(getIntf(), "macosx-icon-change")) {
            NSCalendar *calendar = [[NSCalendar alloc]
                initWithCalendarIdentifier:NSGregorianCalendar];
            NSUInteger day = [calendar ordinalityOfUnit:NSDayCalendarUnit
                                                  inUnit:NSYearCalendarUnit
                                                 forDate:[NSDate date]];
            if (day >= 354)
                defaultImage = [NSImage imageNamed:@"VLC-Xmas"];
        }
        displayedImage = defaultImage;
        showingCone = YES;
        coneVelocity = NSMakePoint(140.0, 105.0);
        [self registerForDraggedTypes:@[NSFilenamesPboardType]];
    }
    return self;
}

- (BOOL)isOpaque { return YES; }
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)acceptsFirstMouse:(NSEvent *)event
{
    /* Preserve one-gesture window dragging while making an ordinary first
     * click behave like a native activation click, with no idle action. */
    /* AppKit calls this only for the first click in a non-key window; its
     * key/active state may already have changed by this point. */
    idlePressActivatesWindow = YES;
    return YES;
}

- (void)prepareConeColours
{
    if (colouredCones)
        return;

    /* Build the tiny palette before motion begins. Recolouring a bitmap at
     * the exact collision instant is visible as a pause on older machines. */
    NSMutableArray *cones = [NSMutableArray arrayWithCapacity:6];
    for (NSUInteger i = 0; i < 6; ++i)
        [cones addObject:VLCMainBackgroundTintedCone(defaultImage, i)];
    colouredCones = [cones copy];
}

- (void)startCone
{
    [self prepareConeColours];
    coneBouncing = YES;
    colouredCone = nil;
    uint32_t randomValue;
    vlc_rand_bytes(&randomValue, sizeof(randomValue));
    coneColourIndex = randomValue % [colouredCones count];
    conePosition = imageRect.origin;
    coneVelocity = NSMakePoint(140.0, 105.0);
    lastMotionTime = [NSDate timeIntervalSinceReferenceDate];
    motionTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 60.0
        target:self selector:@selector(advanceCone:) userInfo:nil
        repeats:YES];
    [self setNeedsDisplay:YES];
}

- (void)setArtwork:(NSImage *)artwork
{
    displayedImage = artwork ?: defaultImage;
    showingCone = artwork == nil;
    [self stopCone];
    [self setNeedsDisplay:YES];
}

- (void)setBackgroundActive:(BOOL)active
{
    [self setHidden:!active];
    if (!active)
        [self stopCone];
}

- (void)stopCone
{
    trackingIdleClick = NO;
    [motionTimer invalidate];
    motionTimer = nil;
    coneBouncing = NO;
    colouredCone = nil;
    [self setNeedsDisplay:YES];
}

- (void)mouseDown:(NSEvent *)event
{
    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    /* Resolve this gesture on mouse-up: the complete playback surface stays
     * a window handle whether it currently shows the cone or audio artwork. */
    trackingIdleClick = YES;
    idleSurfaceDragged = NO;
    idlePressWasOnCone = showingCone && NSPointInRect(point, imageRect);
    idlePressLocation = [NSEvent mouseLocation];
}

- (void)mouseDragged:(NSEvent *)event
{
    if (trackingIdleClick) {
        if (!idleSurfaceDragged) {
            NSPoint current = [NSEvent mouseLocation];
            if (fabs(current.x - idlePressLocation.x) +
                fabs(current.y - idlePressLocation.y) < 4.0)
                return;
            idleSurfaceDragged = YES;
        }
        NSWindow *window = [self window];
        NSPoint origin = [window frame].origin;
        origin.x += [event deltaX];
        origin.y -= [event deltaY];
        [window setFrameOrigin:origin];
        return;
    }
    [super mouseDragged:event];
}

- (void)mouseUp:(NSEvent *)event
{
    if (!trackingIdleClick) {
        [super mouseUp:event];
        return;
    }

    trackingIdleClick = NO;
    BOOL activatesWindow = idlePressActivatesWindow;
    idlePressActivatesWindow = NO;
    if (idleSurfaceDragged)
        return;
    if (activatesWindow)
        return;
    /* Artwork is presentation content: clicking it or its black margins must
     * not unexpectedly replace it with the playlist. */
    if (!showingCone)
        return;
    if (coneBouncing) {
        [self stopCone];
        return;
    }
    if (idlePressWasOnCone) {
        [self startCone];
        return;
    }
    [(VLCMainWindow *)[self window] changePlaylistState:psUserEvent];
}

- (void)advanceCone:(NSTimer *)timer
{
    if (!coneBouncing || [self isHidden] || [self window] == nil) {
        [self stopCone];
        return;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    NSTimeInterval elapsed = MIN(now - lastMotionTime, 0.1);
    lastMotionTime = now;
    NSRect bounds = NSInsetRect([self bounds], 12.0, 12.0);
    CGFloat maxX = MAX(NSMinX(bounds), NSMaxX(bounds) - imageRect.size.width);
    CGFloat maxY = MAX(NSMinY(bounds), NSMaxY(bounds) - imageRect.size.height);
    NSPoint next = NSMakePoint(conePosition.x + coneVelocity.x * elapsed,
                               conePosition.y + coneVelocity.y * elapsed);
    BOOL bounced = NO;
    if (next.x <= NSMinX(bounds) || next.x >= maxX) {
        next.x = MIN(MAX(next.x, NSMinX(bounds)), maxX);
        coneVelocity.x = -coneVelocity.x;
        bounced = YES;
    }
    if (next.y <= NSMinY(bounds) || next.y >= maxY) {
        next.y = MIN(MAX(next.y, NSMinY(bounds)), maxY);
        coneVelocity.y = -coneVelocity.y;
        bounced = YES;
    }
    conePosition = next;
    if (bounced) {
        uint32_t randomValue;
        vlc_rand_bytes(&randomValue, sizeof(randomValue));
        coneColourIndex = (coneColourIndex + 1 +
            randomValue % ([colouredCones count] - 1)) % [colouredCones count];
        colouredCone = [colouredCones objectAtIndex:coneColourIndex];
    }
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor blackColor] set];
    NSRectFill(dirtyRect);
    NSImage *image = coneBouncing && colouredCone ? colouredCone : displayedImage;
    NSSize source = [image size];
    if (source.width <= 0.0 || source.height <= 0.0)
        return;

    NSRect available = NSInsetRect([self bounds], 12.0, 12.0);
    CGFloat scale;
    if (showingCone) {
        scale = MIN(1.0, MIN(128.0 / source.width,
                    MIN(128.0 / source.height,
                    MIN(available.size.width / source.width,
                        available.size.height / source.height))));
    } else {
        /* Unlike the narrow sidebar preview, this is the presentation view:
         * use all available room, just as the expandable Qt background does. */
        scale = MIN(available.size.width / source.width,
                    available.size.height / source.height);
    }
    NSSize size = NSMakeSize(source.width * scale, source.height * scale);
    NSPoint origin = coneBouncing ? conePosition : NSMakePoint(
        NSMidX(available) - size.width / 2.0,
        NSMidY(available) - size.height / 2.0);
    imageRect = NSMakeRect(origin.x, origin.y, size.width, size.height);
    [[NSGraphicsContext currentContext] setImageInterpolation:NSImageInterpolationHigh];
    [image drawInRect:imageRect fromRect:NSZeroRect
            operation:NSCompositeSourceOver fraction:1.0];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    return NSDragOperationCopy;
}

- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender { return YES; }

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    return [[VLCCoreInteraction sharedInstance] performDragOperation:sender];
}

@end


@interface VLCMainWindow() <NSWindowDelegate, NSAnimationDelegate, NSSplitViewDelegate>
{
    BOOL videoPlaybackEnabled;
    BOOL dropzoneActive;
    BOOL splitViewRemoved;
    BOOL minimizedView;

    BOOL b_video_playback_enabled;
    BOOL b_dropzone_active;
    BOOL b_splitview_removed;
    BOOL b_minimized_view;

    CGFloat f_lastSplitViewHeight;
    CGFloat f_lastLeftSplitViewWidth;

    /* this is only true, when we have NO video playing inside the main window */

    BOOL b_podcastView_displayed;

    NSRect frameBeforePlayback;

    /* cover art of the playing item, at the bottom of the sidebar like
     * the Qt interface shows it; the panel is user-resizable in height
     * and the height is remembered across sessions */
    NSImageView *sidebarArtView;
    NSString *sidebarArtUrl;
    NSView *sidebarArtDivider;
    CGFloat artPanelHeight;

    VLCMainBackgroundView *backgroundView;
    BOOL playlistViewWanted;
}
- (void)makeSplitViewVisible;
- (void)makeSplitViewHidden;
- (void)showPodcastControls;
- (void)hidePodcastControls;
- (void)showBackgroundView;
@end

static const float f_min_window_height = 307.;

/* NSUserDefaults key for the persisted cover-art panel height */
static NSString *const VLCMainArtHeightKey = @"VLCMainWindowSidebarArtHeight";
#define VLC_ART_DIVIDER_THICKNESS 6.0
#define VLC_ART_MIN_HEIGHT        40.0
#define VLC_ART_MIN_LIST_HEIGHT   80.0

#define PVLC_ML_SCAN_ACTIVE   "powervlc-ml-scan-active"
#define PVLC_ML_SCAN_DONE     "powervlc-ml-scan-done"
#define PVLC_ML_SCAN_TOTAL    "powervlc-ml-scan-total"
#define PVLC_ML_SCAN_REVISION "powervlc-ml-scan-revision"

static int PowerVLCMediaLibraryScanChanged(vlc_object_t *object,
                                            const char *name,
                                            vlc_value_t oldValue,
                                            vlc_value_t newValue,
                                            void *opaque)
{
    (void)object; (void)name; (void)oldValue; (void)newValue;
    [(__bridge id)opaque performSelectorOnMainThread:
        @selector(_updatePlaylistTitle) withObject:nil waitUntilDone:NO];
    return VLC_SUCCESS;
}

/* A thin draggable handle between the sidebar list and the cover art at
 * the bottom of it; dragging it resizes the art panel, and the height is
 * remembered across sessions (see the controller's persistence). */
@protocol VLCArtDividerDelegate <NSObject>
- (void)artDividerDraggedToPaneY:(CGFloat)y;
@end

@interface VLCArtDivider : NSView
{
    __unsafe_unretained id<VLCArtDividerDelegate> dragDelegate;
}
- (void)setDragDelegate:(id<VLCArtDividerDelegate>)delegate;
@end

@implementation VLCArtDivider
- (void)setDragDelegate:(id<VLCArtDividerDelegate>)delegate
{
    dragDelegate = delegate;
}
- (BOOL)isFlipped { return NO; }
- (void)drawRect:(NSRect)dirtyRect
{
    NSRect b = [self bounds];
    /* a subtle separator line along the top edge of the handle */
    [[NSColor colorWithCalibratedWhite:0.5 alpha:0.35] set];
    NSRectFill(NSMakeRect(0, b.size.height - 1, b.size.width, 1));
}
- (void)resetCursorRects
{
    [self addCursorRect:[self bounds] cursor:[NSCursor resizeUpDownCursor]];
}
- (void)mouseDown:(NSEvent *)event    { [self relayDrag:event]; }
- (void)mouseDragged:(NSEvent *)event { [self relayDrag:event]; }
- (void)relayDrag:(NSEvent *)event
{
    NSView *pane = [self superview];
    NSPoint p = [pane convertPoint:[event locationInWindow] fromView:nil];
    [dragDelegate artDividerDraggedToPaneY:p.y];
}
@end

/* The small playlist-sidebar artwork is an export surface as well as a
 * preview.  Its art already lives in VLC's cache, so publishing that path as
 * NSFilenamesPboardType gives Finder and other applications a real file on
 * every macOS version supported by the Modern interface. */
@interface VLCMainArtworkView : NSImageView
{
    NSString *artPath;
    NSPoint dragStartPoint;
    BOOL dragCandidate;
}
- (void)setArtworkImage:(NSImage *)image path:(NSString *)path;
@end

@implementation VLCMainArtworkView
- (void)setArtworkImage:(NSImage *)image path:(NSString *)path
{
    [self setImage:image];
    artPath = [path copy];
}

- (NSMenu *)menuForEvent:(NSEvent *)event
{
    (void)event;
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
    NSMenuItem *download = [menu addItemWithTitle:_NS("Download cover art")
        action:@selector(downloadCoverArt:) keyEquivalent:@""];
    [download setTarget:self];
    NSMenuItem *copy = [menu addItemWithTitle:_NS("Copy")
        action:@selector(copyCoverArt:) keyEquivalent:@""];
    [copy setTarget:self];
    [copy setEnabled:artPath != nil && [self image] != nil];
    return menu;
}

- (void)downloadCoverArt:(id)sender
{
    (void)sender;
    input_thread_t *input = pl_CurrentInput(getIntf());
    if (!input)
        return;
    input_item_t *item = input_GetItem(input);
    if (item)
        libvlc_ArtRequest(getIntf()->obj.libvlc, item,
                         META_REQUEST_OPTION_SCOPE_ANY);
    vlc_object_release(input);
}

- (void)copyCoverArt:(id)sender
{
    (void)sender;
    NSData *data = [[self image] TIFFRepresentation];
    if (!data || !artPath)
        return;
    NSPasteboard *pasteboard = [NSPasteboard generalPasteboard];
    [pasteboard declareTypes:@[NSTIFFPboardType] owner:nil];
    [pasteboard setData:data forType:NSTIFFPboardType];
}

- (void)mouseDown:(NSEvent *)event
{
    dragStartPoint = [self convertPoint:[event locationInWindow] fromView:nil];
    dragCandidate = artPath != nil;
    [super mouseDown:event];
}

- (void)mouseDragged:(NSEvent *)event
{
    if (!dragCandidate || !artPath ||
        ![[NSFileManager defaultManager] fileExistsAtPath:artPath]) {
        [super mouseDragged:event];
        return;
    }

    NSPoint point = [self convertPoint:[event locationInWindow] fromView:nil];
    if (hypot(point.x - dragStartPoint.x,
              point.y - dragStartPoint.y) < 3.0)
        return;
    dragCandidate = NO;

    NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    [pasteboard declareTypes:@[NSFilenamesPboardType] owner:nil];
    [pasteboard setPropertyList:@[artPath] forType:NSFilenamesPboardType];

    NSImage *source = [self image];
    NSSize sourceSize = [source size];
    CGFloat scale = MIN(1.0, MIN(96.0 / sourceSize.width,
                                 96.0 / sourceSize.height));
    NSSize size = NSMakeSize(sourceSize.width * scale,
                             sourceSize.height * scale);
    NSImage *preview = [[NSImage alloc] initWithSize:size];
    [preview lockFocus];
    [source drawInRect:NSMakeRect(0.0, 0.0, size.width, size.height)
              fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
    [preview unlockFocus];
    [self dragImage:preview at:dragStartPoint offset:NSZeroSize event:event
          pasteboard:pasteboard source:self slideBack:YES];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)local
{
    (void)local;
    return NSDragOperationCopy;
}
@end

/* default window title ("Lecteur multimedia PowerVLC" in French) */
static NSString *defaultWindowTitle(void)
{
    return _NS("PowerVLC media player");
}

@implementation VLCMainWindow

#pragma mark -
#pragma mark Initialization

- (BOOL)isEvent:(NSEvent *)o_event forKey:(const char *)keyString
{
    char *key;
    NSString *o_key;

    key = config_GetPsz(getIntf(), keyString);
    o_key = [NSString stringWithFormat:@"%s", key];
    FREENULL(key);

    unsigned int i_keyModifiers = [[VLCStringUtility sharedInstance] VLCModifiersToCocoa:o_key];

    NSString * characters = [o_event charactersIgnoringModifiers];
    if ([characters length] > 0) {
        return [[characters lowercaseString] isEqualToString: [[VLCStringUtility sharedInstance] VLCKeyToString: o_key]] &&
                (i_keyModifiers & NSShiftKeyMask)     == ([o_event modifierFlags] & NSShiftKeyMask) &&
                (i_keyModifiers & NSControlKeyMask)   == ([o_event modifierFlags] & NSControlKeyMask) &&
                (i_keyModifiers & NSAlternateKeyMask) == ([o_event modifierFlags] & NSAlternateKeyMask) &&
                (i_keyModifiers & NSCommandKeyMask)   == ([o_event modifierFlags] & NSCommandKeyMask);
    }
    return NO;
}

/* ⚠ Command + a digit was dead on every keyboard whose digit row needs Shift
 * -- AZERTY, QWERTZ and the rest. The event then carries the UNSHIFTED
 * character of the key ('"' for the "3" of a French layout), which matches no
 * menu equivalent. AppKit works around this by falling back on an
 * ASCII-capable layout, but only inside ITS OWN dispatch: -performKeyEquivalent:
 * below consults the main menu by hand, with the event exactly as it came, and
 * never calls super, so that fallback never gets its turn. Measured on a French
 * layout, Video > Half Size: Command + the "0" key did nothing at all, Command
 * + Shift + "0" halved the window as it should.
 *
 * VIRTUAL key codes are positional and layout independent: those below are the
 * digit row of every Mac keyboard (the order is the historical one, 5 and 6 are
 * swapped and 7 to 0 are not consecutive). Same fix as the legacy interface's
 * VLCLegacyEventWithDigitRowFallback, which is why the legacy menus already
 * answer these shortcuts. */
static NSEvent *VLCEventWithDigitRowFallback(NSEvent *o_event)
{
    if (!([o_event modifierFlags] & NSCommandKeyMask))
        return o_event;             /* only command equivalents suffer this */

    unichar digit;
    switch ([o_event keyCode]) {
        case 18: digit = '1'; break;
        case 19: digit = '2'; break;
        case 20: digit = '3'; break;
        case 21: digit = '4'; break;
        case 23: digit = '5'; break;
        case 22: digit = '6'; break;
        case 26: digit = '7'; break;
        case 28: digit = '8'; break;
        case 25: digit = '9'; break;
        case 29: digit = '0'; break;
        default: return o_event;
    }

    NSString *characters = [o_event charactersIgnoringModifiers];
    if (!([o_event modifierFlags] & NSShiftKeyMask)
        && [characters length] == 1
        && [characters characterAtIndex:0] == digit)
        return o_event;             /* the layout already gives the digit */

    /* Shift is dropped: on such a keyboard it is how the digit is typed in the
     * first place, and no menu item here is bound to Command+Shift+<digit>. */
    NSString *replacement = [NSString stringWithCharacters:&digit length:1];
    return [NSEvent keyEventWithType:[o_event type]
                            location:[o_event locationInWindow]
                       modifierFlags:[o_event modifierFlags] & ~NSShiftKeyMask
                           timestamp:[o_event timestamp]
                        windowNumber:[o_event windowNumber]
                             context:nil
                          characters:replacement
         charactersIgnoringModifiers:replacement
                           isARepeat:[o_event isARepeat]
                             keyCode:[o_event keyCode]];
}

- (BOOL)performKeyEquivalent:(NSEvent *)o_event
{
    /* when a list (playlist outline, sidebar) has keyboard focus, the
     * plain Left/Right arrows belong to it (fold/unfold), not to the
     * core hotkeys (key-nav-*).  DVD menu navigation still gets them
     * whenever the video view has focus.  Up/Down, Delete and Return
     * are already let through by hasDefinedShortcutKey:force:.
     * ⚠ Clip creation trims the selected bound by one frame with those
     * arrows, and on an AUDIO item the playlist is the only thing on
     * screen, so the list always holds the focus: the mode wins there,
     * otherwise the arrows would be dead exactly where trimming by hand
     * matters most. */
    if (!([o_event modifierFlags] & (NSControlKeyMask | NSAlternateKeyMask
                                   | NSShiftKeyMask | NSCommandKeyMask))
     && ![[VLCCoreInteraction sharedInstance] clipCreationMode]
     && [[self firstResponder] isKindOfClass:[NSTableView class]]) {
        NSString *characters = [o_event charactersIgnoringModifiers];
        if ([characters length] > 0) {
            unichar key = [characters characterAtIndex:0];
            if (key == NSLeftArrowFunctionKey || key == NSRightArrowFunctionKey)
                return NO; /* regular dispatch: the focused list handles it */
        }
    }

    /* substitute the digit before either path below sees the event, so the
     * menu and the core agree on what was pressed (see above) */
    o_event = VLCEventWithDigitRowFallback(o_event);

    BOOL b_force = NO;
    // these are key events which should be handled by vlc core, but are attached to a main menu item
    if (![self isEvent: o_event forKey: "key-vol-up"] &&
        ![self isEvent: o_event forKey: "key-vol-down"] &&
        ![self isEvent: o_event forKey: "key-vol-mute"] &&
        ![self isEvent: o_event forKey: "key-prev"] &&
        ![self isEvent: o_event forKey: "key-next"] &&
        ![self isEvent: o_event forKey: "key-jump+short"] &&
        ![self isEvent: o_event forKey: "key-jump-short"]) {
        /* We indeed want to prioritize some Cocoa key equivalent against libvlc,
         so we perform the menu equivalent now. */
        if ([[NSApp mainMenu] performKeyEquivalent:o_event])
            return TRUE;
    }
    else
        b_force = YES;

    VLCCoreInteraction *coreInteraction = [VLCCoreInteraction sharedInstance];
    return [coreInteraction hasDefinedShortcutKey:o_event force:b_force] ||
           [coreInteraction keyEvent:o_event];
}

- (void)dealloc
{
    msg_Dbg(getIntf(), "Deinitializing VLCMainWindow object");

    [[NSNotificationCenter defaultCenter] removeObserver: self];
    var_DelCallback(getIntf()->obj.libvlc, PVLC_ML_SCAN_REVISION,
                    PowerVLCMediaLibraryScanChanged, (__bridge void *)self);
    if (@available(macOS 10_14, *)) {
        [[NSApplication sharedApplication] removeObserver:self forKeyPath:@"effectiveAppearance"];
    }
}

- (void)awakeFromNib
{
    [super awakeFromNib];

    /*
     * General setup
     */

    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    BOOL splitViewShouldBeHidden = NO;

    [self setDelegate:self];
    [self setRestorable:NO];
    // TODO: useOptimizedDrawing deprecated since 10.10, but no
    // documentation provided what do use instead.
    // see radar://23047516
    [self useOptimizedDrawing:YES];
    [self setExcludedFromWindowsMenu:YES];
    [self setAcceptsMouseMovedEvents:YES];
    [self setFrameAutosaveName:@"mainwindow"];

    _nativeFullscreenMode = var_InheritBool(getIntf(), "macosx-nativefullscreenmode");
    b_dropzone_active = YES;
    playlistViewWanted = NO;

    /* The background occupies the same middle-content rectangle as the
     * split and video views. It is autoresized rather than constrained so it
     * remains compatible with the 10.7 AppKit used by this interface. */
    NSView *middleContent = [self.videoView superview];
    backgroundView = [[VLCMainBackgroundView alloc]
        initWithFrame:[middleContent bounds]];
    [backgroundView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [middleContent addSubview:backgroundView
                    positioned:NSWindowBelow
                    relativeTo:_splitView];

    // Playlist setup
    var_Create(getIntf()->obj.libvlc, PVLC_ML_SCAN_ACTIVE, VLC_VAR_BOOL);
    var_Create(getIntf()->obj.libvlc, PVLC_ML_SCAN_DONE, VLC_VAR_INTEGER);
    var_Create(getIntf()->obj.libvlc, PVLC_ML_SCAN_TOTAL, VLC_VAR_INTEGER);
    var_Create(getIntf()->obj.libvlc, PVLC_ML_SCAN_REVISION, VLC_VAR_INTEGER);
    var_AddCallback(getIntf()->obj.libvlc, PVLC_ML_SCAN_REVISION,
                    PowerVLCMediaLibraryScanChanged, (__bridge void *)self);
    VLCPlaylist *playlist = [[VLCMain sharedInstance] playlist];
    [playlist setOutlineView:(VLCPlaylistView *)_outlineView];
    [playlist setPlaylistHeaderView:_outlineView.headerView];
    [self setNextResponder:playlist];

    // (Re)load sidebar for the first time and select first item
    self.sidebarDataSource = [[VLCSidebarDataSource alloc] init];
    self.sidebarDataSource.sidebarView = self.sidebarView;

    [self.sidebarDataSource reloadSidebar];
    [_sidebarView setAutosaveName:@"mainwindow-sidebar"];
    [_sidebarView setAutosaveExpandedItems:YES];

    [_sidebarView selectRowIndexes:[NSIndexSet indexSetWithIndex:1] byExtendingSelection:NO];

    // Cover art of the current item at the bottom of the sidebar, the
    // same presentation as the Qt interface on Windows/Linux
    {
        NSView *leftPane = self.splitViewLeft;
        NSScrollView *sidebarScroll = self.sidebarScrollView;
        NSNumber *savedArtHeight = [defaults objectForKey:VLCMainArtHeightKey];
        artPanelHeight = savedArtHeight ? [savedArtHeight doubleValue] : 120.;
        [sidebarScroll setTranslatesAutoresizingMaskIntoConstraints:YES];
        /* vertical placement is driven by -layoutSidebarArtStack, not the
         * autoresizing machinery, so keep only the width follow-through */
        [sidebarScroll setAutoresizingMask:NSViewWidthSizable];
        sidebarArtView = [[VLCMainArtworkView alloc]
            initWithFrame:NSMakeRect(0., 0., [leftPane bounds].size.width, 10.)];
        [sidebarArtView setAutoresizingMask:NSViewWidthSizable];
        [sidebarArtView setImageScaling:NSImageScaleProportionallyDown];
        [sidebarArtView setImage:[NSImage imageNamed:@"noart"]];
        [sidebarArtView setEditable:NO];
        [sidebarArtView unregisterDraggedTypes];
        [leftPane addSubview:sidebarArtView];

        VLCArtDivider *divider = [[VLCArtDivider alloc]
            initWithFrame:NSMakeRect(0., 0., [leftPane bounds].size.width,
                                     VLC_ART_DIVIDER_THICKNESS)];
        [divider setAutoresizingMask:NSViewWidthSizable];
        [divider setDragDelegate:(id)self];
        sidebarArtDivider = divider;
        [leftPane addSubview:sidebarArtDivider];

        /* relayout the art stack whenever the left pane changes size
         * (window resize, sidebar divider drag) */
        [leftPane setPostsFrameChangedNotifications:YES];
        [defaultCenter addObserver:self
                          selector:@selector(sidebarPaneFrameChanged:)
                              name:NSViewFrameDidChangeNotification
                            object:leftPane];
        [self layoutSidebarArtStack];
    }

    /*
     * Set up translatable strings for the UI elements
     */

    // Window title
    [self setTitle:defaultWindowTitle()];

    // Search Field
    [_searchField setToolTip:_NS("Search in Playlist")];
    [_searchField.cell setPlaceholderString:_NS("Search")];
    [_searchField.cell accessibilitySetOverrideValue:_NS("Search the playlist. Results will be selected in the table.")
                                        forAttribute:NSAccessibilityDescriptionAttribute];

    // Dropzone
    [_dropzoneLabel setStringValue:_NS("Drop media here")];
    if (@available(macOS 10.14, *)) {
        NSApplication *app = [NSApplication sharedApplication];
        if ([app.effectiveAppearance.name isEqualToString:NSAppearanceNameDarkAqua]) {
            [_dropzoneImageView setImage:[NSImage imageNamed:@"mj-dropzone-dark"]];
        } else {
            [_dropzoneImageView setImage:imageFromRes(@"dropzone")];
        }
        [app addObserver:self
              forKeyPath:@"effectiveAppearance"
                 options:0
                 context:nil];
        self.dropzoneBackgroundImageView.hidden = YES;
    } else {
        [_dropzoneImageView setImage:imageFromRes(@"dropzone")];
    }
    [_dropzoneButton setTitle:_NS("Open media...")];
    [_dropzoneButton.cell accessibilitySetOverrideValue:_NS("Open a dialog to select the media to play")
                                           forAttribute:NSAccessibilityDescriptionAttribute];

    // Podcast view
    /* the strip is a fixed dark image in either appearance, so the round
     * rect buttons, which draw their title in the control text colour,
     * come out unreadable: spell the colour out */
    NSDictionary *podcastButtonAttributes = @{
        NSForegroundColorAttributeName: [NSColor whiteColor],
        NSFontAttributeName: [NSFont systemFontOfSize:[NSFont smallSystemFontSize]],
        NSParagraphStyleAttributeName: ({
            NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
            [style setAlignment:NSTextAlignmentCenter];
            style;
        })
    };
    [_podcastAddButton setAttributedTitle:
        [[NSAttributedString alloc] initWithString:_NS("Subscribe")
                                        attributes:podcastButtonAttributes]];
    [_podcastRemoveButton setAttributedTitle:
        [[NSAttributedString alloc] initWithString:_NS("Unsubscribe")
                                        attributes:podcastButtonAttributes]];

    // Podcast subscribe window
    [_podcastSubscribeTitle setStringValue:_NS("Subscribe to a podcast")];
    [_podcastSubscribeSubtitle setStringValue:_NS("Enter URL of the podcast to subscribe to:")];
    [_podcastSubscribeOkButton setTitle:_NS("Subscribe")];
    [_podcastSubscribeCancelButton setTitle:_NS("Cancel")];

    // Podcast unsubscribe window
    [_podcastUnsubscirbeTitle setStringValue:_NS("Unsubscribe from a podcast")];
    [_podcastUnsubscribeSubtitle setStringValue:_NS("Select the podcast you would like to unsubscribe from:")];
    [_podcastUnsubscribeOkButton setTitle:_NS("Unsubscribe")];
    [_podcastUnsubscribeCancelButton setTitle:_NS("Cancel")];

    /* interface builder action */
    CGFloat f_threshold_height = f_min_video_height + [self.controlsBar height];
    if (self.darkInterface)
        f_threshold_height += [self.titlebarView frame].size.height;
    if ([[self contentView] frame].size.height < f_threshold_height)
        splitViewShouldBeHidden = YES;

    // Set that here as IB seems to be buggy
    if (self.darkInterface)
        [self setContentMinSize:NSMakeSize(604., f_min_window_height + [self.titlebarView frame].size.height)];
    else
        [self setContentMinSize:NSMakeSize(604., f_min_window_height)];

    _fspanel = [[VLCFSPanelController alloc] init];
    [_fspanel showWindow:self];

    /* make sure we display the desired default appearance when VLC launches for the first time */
    if (![defaults objectForKey:@"VLCFirstRun"]) {
        [defaults setObject:[NSDate date] forKey:@"VLCFirstRun"];

        [_sidebarView expandItem:nil expandChildren:YES];

        NSAlert *albumArtAlert = [NSAlert alertWithMessageText:_NS("Check for album art and metadata?") defaultButton:_NS("Enable Metadata Retrieval") alternateButton:_NS("No, Thanks") otherButton:nil informativeTextWithFormat:@"%@",_NS("VLC can check online for album art and metadata to enrich your playback experience, e.g. by providing track information when playing Audio CDs. To provide this functionality, VLC will send information about your contents to trusted services in an anonymized form.")];
        NSInteger returnValue = [albumArtAlert runModal];
        config_PutInt(getIntf(), "metadata-network-access", returnValue == NSAlertDefaultReturn);
    }

    if (self.darkInterface) {
        [defaultCenter addObserver: self selector: @selector(windowResizedOrMoved:) name: NSWindowDidResizeNotification object: nil];
        [defaultCenter addObserver: self selector: @selector(windowResizedOrMoved:) name: NSWindowDidMoveNotification object: nil];

        [self setBackgroundColor: [NSColor clearColor]];
        [self setOpaque: NO];
        [self display];
        [self setHasShadow:NO];
        [self setHasShadow:YES];

        self.previousSavedFrame = [self frame];
    } else {
        [_playlistScrollView setBorderType:NSNoBorder];
        [_sidebarScrollView setBorderType:NSNoBorder];
    }

    [defaultCenter addObserver: self selector: @selector(someWindowWillClose:) name: NSWindowWillCloseNotification object: nil];
    [defaultCenter addObserver: self selector: @selector(someWindowWillMiniaturize:) name: NSWindowWillMiniaturizeNotification object:nil];
    [defaultCenter addObserver: self selector: @selector(applicationWillTerminate:) name: NSApplicationWillTerminateNotification object: nil];
    [defaultCenter addObserver: self selector: @selector(mainSplitViewDidResizeSubviews:) name: NSSplitViewDidResizeSubviewsNotification object:_splitView];

    if (splitViewShouldBeHidden) {
        [self hideSplitView:YES];
        f_lastSplitViewHeight = 300;
    }

    /* sanity check for the window size */
    NSRect frame = [self frame];
    NSSize screenSize = [[self screen] frame].size;
    if (screenSize.width <= frame.size.width || screenSize.height <= frame.size.height) {
        self.nativeVideoSize = screenSize;
        [self resizeWindow];
    }

    /* update fs button to reflect state for next startup */
    if (var_InheritBool(pl_Get(getIntf()), "fullscreen"))
        [self.controlsBar setFullscreenState:YES];

    /* restore split view */
    f_lastLeftSplitViewWidth = 200;
    [[[VLCMain sharedInstance] mainMenu] updateSidebarMenuItem: ![_splitView isSubviewCollapsed:_splitViewLeft]];

    /* Qt starts on its cone/art surface rather than opening the playlist.
     * Match that default on macOS; the playlist button still exposes the
     * complete split view. */
    [self showBackgroundView];
}

#pragma mark -
#pragma mark cover-art panel resizing

/* Position the sidebar list, the divider and the cover art inside the
 * left split pane. The art keeps its user-set height (clamped to the
 * available space); the list takes whatever is left above it. */
- (void)layoutSidebarArtStack
{
    NSView *pane = self.splitViewLeft;
    NSScrollView *sidebarScroll = self.sidebarScrollView;
    if (!pane || !sidebarScroll || !sidebarArtView)
        return;
    CGFloat W = [pane bounds].size.width;
    CGFloat H = [pane bounds].size.height;
    CGFloat div = VLC_ART_DIVIDER_THICKNESS;

    CGFloat h = artPanelHeight;
    CGFloat maxH = H - VLC_ART_MIN_LIST_HEIGHT - div;
    if (h > maxH) h = maxH;
    if (h < VLC_ART_MIN_HEIGHT) h = VLC_ART_MIN_HEIGHT;
    if (h + div > H) h = (H > div) ? H - div : 0;

    [sidebarArtView setFrame:NSMakeRect(0, 0, W, h)];
    [sidebarArtDivider setFrame:NSMakeRect(0, h, W, div)];
    [sidebarScroll setFrame:NSMakeRect(0, h + div, W,
                                       (H > h + div) ? H - h - div : 0)];
}

- (void)sidebarPaneFrameChanged:(NSNotification *)notification
{
    [self layoutSidebarArtStack];
}

/* VLCArtDividerDelegate: the user dragged the handle. Convert the
 * pane-space y into an art height, clamp it, relayout and persist. */
- (void)artDividerDraggedToPaneY:(CGFloat)y
{
    CGFloat H = [self.splitViewLeft bounds].size.height;
    CGFloat div = VLC_ART_DIVIDER_THICKNESS;
    CGFloat h = y - div / 2.0;
    CGFloat maxH = H - VLC_ART_MIN_LIST_HEIGHT - div;
    if (h > maxH) h = maxH;
    if (h < VLC_ART_MIN_HEIGHT) h = VLC_ART_MIN_HEIGHT;
    artPanelHeight = h;
    [self layoutSidebarArtStack];
    [[NSUserDefaults standardUserDefaults]
        setObject:[NSNumber numberWithDouble:artPanelHeight]
           forKey:VLCMainArtHeightKey];
}

#pragma mark -
#pragma mark appearance management

// Show split view and hide the video view
- (void)makeSplitViewVisible
{
    [self setContentMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    if (self.darkInterface)
        [self setContentMinSize: NSMakeSize(604., f_min_window_height + [self.titlebarView frame].size.height)];
    else
        [self setContentMinSize: NSMakeSize(604., f_min_window_height)];

    NSRect old_frame = [self frame];
    CGFloat newHeight = [self minSize].height;
    if (old_frame.size.height < newHeight) {
        NSRect new_frame = old_frame;
        new_frame.origin.y = old_frame.origin.y + old_frame.size.height - newHeight;
        new_frame.size.height = newHeight;

        [[self animator] setFrame:new_frame display:YES animate:YES];
    }

    [backgroundView setBackgroundActive:NO];
    [self.videoView setHidden:YES];
    [_splitView setHidden:NO];
    if (self.nativeFullscreenMode && [self fullscreen]) {
        [self showControlsBar];
        [self.fspanel setNonActive];
    }

    [self makeFirstResponder:_playlistScrollView];
}

// Hides the split view and makes the vout view in foreground
- (void)makeSplitViewHidden
{
    [self setContentMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    if (self.darkInterface)
        [self setContentMinSize: NSMakeSize(604., f_min_video_height + [self.titlebarView frame].size.height)];
    else
        [self setContentMinSize: NSMakeSize(604., f_min_video_height)];

    [backgroundView setBackgroundActive:NO];
    [_splitView setHidden:YES];
    [self.videoView setHidden:NO];
    if (self.nativeFullscreenMode && [self fullscreen]) {
        [self hideControlsBar];
        [self.fspanel setActive];
    }

    if ([[self.videoView subviews] count] > 0)
        [self makeFirstResponder: [[self.videoView subviews] firstObject]];
}

- (void)showBackgroundView
{
    [self setContentMaxSize:NSMakeSize(FLT_MAX, FLT_MAX)];
    if (self.darkInterface)
        [self setContentMinSize:NSMakeSize(604., f_min_window_height
                                                + [self.titlebarView frame].size.height)];
    else
        [self setContentMinSize:NSMakeSize(604., f_min_window_height)];

    NSRect oldFrame = [self frame];
    CGFloat requiredHeight = [self minSize].height;
    if (oldFrame.size.height < requiredHeight) {
        oldFrame.origin.y += oldFrame.size.height - requiredHeight;
        oldFrame.size.height = requiredHeight;
        [self setFrame:oldFrame display:YES];
    }
    b_splitview_removed = NO;
    b_minimized_view = NO;

    [self.videoView setHidden:YES];
    [_splitView setHidden:YES];
    [backgroundView setBackgroundActive:YES];
    [self makeFirstResponder:backgroundView];
    if (self.nativeFullscreenMode && [self fullscreen]) {
        [self showControlsBar];
        [self.fspanel setNonActive];
    }
}


- (void)changePlaylistState:(VLCPlaylistStateEvent)event
{
    msg_Dbg(getIntf(), "change main view: playlist requested %i, event %i",
            playlistViewWanted, event);
    if (![self isVisible] && event == psUserMenuEvent) {
        [self makeKeyAndOrderFront: nil];
        return;
    }

    BOOL b_activeVideo = [[VLCMain sharedInstance] activeVideoPlayback];
    if (event == psUserMenuEvent)
        event = psUserEvent;

    /* With a detached vout, video never replaces the main-window surface;
     * its button simply alternates the same background and playlist views. */
    if (self.nonembedded) {
        if (event == psUserEvent) {
            playlistViewWanted = !playlistViewWanted;
            if (playlistViewWanted)
                [self makeSplitViewVisible];
            else
                [self showBackgroundView];
        }
        return;
    }

    if (event == psUserEvent) {
        if (b_activeVideo) {
            if ([self.videoView isHidden]) {
                playlistViewWanted = NO;
                [self makeSplitViewHidden];
            } else {
                playlistViewWanted = YES;
                [self makeSplitViewVisible];
            }
        } else {
            playlistViewWanted = !playlistViewWanted;
            if (playlistViewWanted)
                [self makeSplitViewVisible];
            else
                [self showBackgroundView];
        }
        return;
    }

    /* Input/vout events never override an explicit playlist choice. The
     * normal path otherwise follows Qt: video, then art/cone when it ends. */
    if (b_activeVideo && !playlistViewWanted)
        [self makeSplitViewHidden];
    else if (playlistViewWanted)
        [self makeSplitViewVisible];
    else
        [self showBackgroundView];
}

- (IBAction)dropzoneButtonAction:(id)sender
{
    [[[VLCMain sharedInstance] open] openFileGeneric];
}

#pragma mark -
#pragma mark overwritten default functionality

- (void)windowResizedOrMoved:(NSNotification *)notification
{
    [self saveFrameUsingName:[self frameAutosaveName]];
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    [self saveFrameUsingName:[self frameAutosaveName]];
}


- (void)someWindowWillClose:(NSNotification *)notification
{
    id obj = [notification object];

    // hasActiveVideo is defined for VLCVideoWindowCommon and subclasses
    if ([obj respondsToSelector:@selector(hasActiveVideo)] && [obj hasActiveVideo]) {
        if ([[VLCMain sharedInstance] activeVideoPlayback])
            [[VLCCoreInteraction sharedInstance] stop];
    }
}

- (void)someWindowWillMiniaturize:(NSNotification *)notification
{
    if (config_GetInt(getIntf(), "macosx-pause-minimized")) {
        id obj = [notification object];

        if ([obj class] == [VLCVideoWindowCommon class] || [obj class] == [VLCDetachedVideoWindow class] || ([obj class] == [VLCMainWindow class] && !self.nonembedded)) {
            if ([[VLCMain sharedInstance] activeVideoPlayback])
                [[VLCCoreInteraction sharedInstance] pause];
        }
    }
}

#pragma mark -
#pragma mark Update interface and respond to foreign events
- (void)showDropZone
{
    b_dropzone_active = YES;
    [_dropzoneView setHidden:NO];
    [_playlistScrollView setHidden:YES];
}

- (void)hideDropZone
{
    b_dropzone_active = NO;
    [_dropzoneView setHidden:YES];
    [_playlistScrollView setHidden:NO];
}

- (void)hideSplitView:(BOOL)resize
{
    if (resize) {
        NSRect winrect = [self frame];
        f_lastSplitViewHeight = [_splitView frame].size.height;
        winrect.size.height = winrect.size.height - f_lastSplitViewHeight;
        winrect.origin.y = winrect.origin.y + f_lastSplitViewHeight;
        [self setFrame:winrect display:YES animate:YES];
    }

    if (self.darkInterface) {
        [self setContentMinSize: NSMakeSize(604., [self.controlsBar height] + [self.titlebarView frame].size.height)];
        [self setContentMaxSize: NSMakeSize(FLT_MAX, [self.controlsBar height] + [self.titlebarView frame].size.height)];
    } else {
        [self setContentMinSize: NSMakeSize(604., [self.controlsBar height])];
        [self setContentMaxSize: NSMakeSize(FLT_MAX, [self.controlsBar height])];
    }

    b_splitview_removed = YES;
}

- (void)showSplitView:(BOOL)resize
{
    [self updateWindow];
    if (self.darkInterface)
        [self setContentMinSize:NSMakeSize(604., f_min_window_height + [self.titlebarView frame].size.height)];
    else
        [self setContentMinSize:NSMakeSize(604., f_min_window_height)];
    [self setContentMaxSize: NSMakeSize(FLT_MAX, FLT_MAX)];

    if (resize) {
        NSRect winrect;
        winrect = [self frame];
        winrect.size.height = winrect.size.height + f_lastSplitViewHeight;
        winrect.origin.y = winrect.origin.y - f_lastSplitViewHeight;
        [self setFrame:winrect display:YES animate:YES];
    }

    b_splitview_removed = NO;
}

- (void)updateTimeSlider
{
    [self.controlsBar updateTimeSlider];
    [self.fspanel updatePositionAndTime];

    [[[VLCMain sharedInstance] voutController] updateControlsBarsUsingBlock:^(VLCControlsBarCommon *controlsBar) {
        [controlsBar updateTimeSlider];
    }];

    [[VLCCoreInteraction sharedInstance] updateAtoB];
    [[VLCCoreInteraction sharedInstance] updateClipRecording];
}

- (void)updateName
{
    /* the art may only appear once the meta fetcher is done: updateName
     * runs on those events too */
    [self updateSidebarCoverArt];

    input_thread_t *p_input;
    p_input = pl_CurrentInput(getIntf());
    if (p_input) {
        NSString *aString = @"";

        if (!config_GetPsz(getIntf(), "video-title")) {
            char *format = var_InheritString(getIntf(), "input-title-format");
            if (format) {
                char *formated = vlc_strfinput(p_input, format);
                free(format);
                aString = toNSStr(formated);
                free(formated);
            }
        } else
            aString = toNSStr(config_GetPsz(getIntf(), "video-title"));

        char *uri = input_item_GetURI(input_GetItem(p_input));

        NSURL * o_url = [NSURL URLWithString:toNSStr(uri)];
        NSString *filePath = [o_url isFileURL] ? [o_url path] : nil;
        /* setRepresentedURL: asks LaunchServices for the localized file name
         * and its ancestor chain.  On an iPod or another slow/removable
         * volume that turns a harmless title update into synchronous disk
         * I/O on AppKit's main thread, freezing the whole interface while the
         * device retries.  A represented URL is only a Finder convenience;
         * playback must never depend on resolving it. */
        BOOL slowExternalFile = filePath != nil
                             && [filePath hasPrefix:@"/Volumes/"];
        if ([o_url isFileURL] && !slowExternalFile) {
            [self setRepresentedURL: o_url];
            [[[VLCMain sharedInstance] voutController] updateWindowsUsingBlock:^(VLCVideoWindowCommon *o_window) {
                [o_window setRepresentedURL:o_url];
            }];
        } else {
            [self setRepresentedURL: nil];
            [[[VLCMain sharedInstance] voutController] updateWindowsUsingBlock:^(VLCVideoWindowCommon *o_window) {
                [o_window setRepresentedURL:nil];
            }];
        }
        free(uri);

        if ([aString isEqualToString:@""]) {
            if ([o_url isFileURL])
                /* lastPathComponent is purely lexical.  displayNameAtPath:
                 * performs filesystem/LaunchServices queries and can block
                 * for minutes when a portable player responds poorly. */
                aString = [filePath lastPathComponent];
            else
                aString = [o_url absoluteString];
        }

        if ([aString length] > 0) {
            [self setTitle: aString];
            [[[VLCMain sharedInstance] voutController] updateWindowsUsingBlock:^(VLCVideoWindowCommon *o_window) {
                [o_window setTitle:aString];
            }];

            [self.fspanel setStreamTitle: aString];
        } else {
            [self setTitle: defaultWindowTitle()];
            [self setRepresentedURL: nil];
        }

        vlc_object_release(p_input);
    } else {
        [self setTitle: defaultWindowTitle()];
        [self setRepresentedURL: nil];
    }
}

/* cover art of the playing item in the sidebar (Qt interface parity);
 * also called when the meta/art of the input are fetched late */
- (void)updateSidebarCoverArt
{
    NSString *artUrl = nil;
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (p_input) {
        input_item_t *p_item = input_GetItem(p_input);
        char *psz_url = p_item ? input_item_GetArtworkURL(p_item) : NULL;
        if (psz_url) {
            artUrl = toNSStr(psz_url);
            free(psz_url);
        }
        vlc_object_release(p_input);
    }
    if (!artUrl)
        artUrl = @"";
    if ([artUrl isEqualToString:sidebarArtUrl])
        return;
    sidebarArtUrl = artUrl;

    NSImage *art = nil;
    NSString *artPath = nil;
    if ([artUrl length]) {
        char *psz_path = vlc_uri2path([artUrl UTF8String]);
        if (psz_path) {
            artPath = toNSStr(psz_path);
            art = [[NSImage alloc] initWithContentsOfFile:artPath];
            free(psz_path);
        }
    }
    [(VLCMainArtworkView *)sidebarArtView
        setArtworkImage:art ? art : [NSImage imageNamed:@"noart"]
                         path:art ? artPath : nil];
    [backgroundView setArtwork:art];
}

- (void)updateWindow
{
    [self updateSidebarCoverArt];
    [self.controlsBar updateControls];
    [[[VLCMain sharedInstance] voutController] updateControlsBarsUsingBlock:^(VLCControlsBarCommon *controlsBar) {
        [controlsBar updateControls];
    }];

    bool b_seekable = false;

    playlist_t *p_playlist = pl_Get(getIntf());
    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (p_input) {
        /* seekable streams */
        b_seekable = var_GetBool(p_input, "can-seek");

        vlc_object_release(p_input);
    }

    [self updateTimeSlider];
    if ([self.fspanel respondsToSelector:@selector(setSeekable:)])
        [self.fspanel setSeekable: b_seekable];

    PL_LOCK;
    if ([[[[VLCMain sharedInstance] playlist] model] currentRootType] != ROOT_TYPE_PLAYLIST ||
        [[[[VLCMain sharedInstance] playlist] model] hasChildren])
        [self hideDropZone];
    else
        [self showDropZone];
    PL_UNLOCK;
    [_sidebarView setNeedsDisplay:YES];

    // Update badge in the sidebar for the first two items (Playlist and Media library)
    [_sidebarView reloadDataForRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1,2)]
                            columnIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [[_sidebarView tableColumns] count])]];

    [self _updatePlaylistTitle];
}

- (void)setPause
{
    [self.controlsBar setPause];
    [self.fspanel setPause];

    [[[VLCMain sharedInstance] voutController] updateControlsBarsUsingBlock:^(VLCControlsBarCommon *controlsBar) {
        [controlsBar setPause];
    }];
}

- (void)setPlay
{
    [self.controlsBar setPlay];
    [self.fspanel setPlay];

    [[[VLCMain sharedInstance] voutController] updateControlsBarsUsingBlock:^(VLCControlsBarCommon *controlsBar) {
        [controlsBar setPlay];
    }];
}

- (void)updateVolumeSlider
{
    [(VLCMainWindowControlsBar *)[self controlsBar] updateVolumeSlider];
    [self.fspanel setVolumeLevel:[[VLCCoreInteraction sharedInstance] volume]];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context
{
    if (@available(macOS 10_14, *)) {
        if ([[[NSApplication sharedApplication] effectiveAppearance].name isEqualToString:NSAppearanceNameDarkAqua]) {
            [_dropzoneImageView setImage:[NSImage imageNamed:@"mj-dropzone-dark"]];
        } else {
            [_dropzoneImageView setImage:imageFromRes(@"dropzone")];
        }
        [self.sidebarDataSource reloadSidebar];
    }
}

#pragma mark -
#pragma mark Video Output handling

- (void)videoplayWillBeStarted
{
    if (!self.fullscreen)
        frameBeforePlayback = [self frame];
}

- (void)setVideoplayEnabled
{
    BOOL b_videoPlayback = [[VLCMain sharedInstance] activeVideoPlayback];

    if (!b_videoPlayback) {
        if (!self.nonembedded && (!self.nativeFullscreenMode || (self.nativeFullscreenMode && !self.fullscreen)) && frameBeforePlayback.size.width > 0 && frameBeforePlayback.size.height > 0) {

            // only resize back to minimum view of this is still desired final state
            CGFloat f_threshold_height = f_min_video_height + [self.controlsBar height];
            if(frameBeforePlayback.size.height > f_threshold_height || b_minimized_view) {

                if ([[VLCMain sharedInstance] isTerminating])
                    [self setFrame:frameBeforePlayback display:YES];
                else
                    [[self animator] setFrame:frameBeforePlayback display:YES];

            }
        }

        frameBeforePlayback = NSMakeRect(0, 0, 0, 0);

        // update fs button to reflect state for next startup
        if (var_InheritBool(getIntf(), "fullscreen") || var_GetBool(pl_Get(getIntf()), "fullscreen")) {
            [self.controlsBar setFullscreenState:YES];
        }

        [self makeFirstResponder: _playlistScrollView];
        [[[VLCMain sharedInstance] voutController] updateWindowLevelForHelperWindows: NSNormalWindowLevel];

        // restore alpha value to 1 for the case that macosx-opaqueness is set to < 1
        [self setAlphaValue:1.0];
    }

    if (self.nativeFullscreenMode) {
        if ([self hasActiveVideo] && [self fullscreen] && b_videoPlayback) {
            [self hideControlsBar];
            [self.fspanel setActive];
        } else {
            [self showControlsBar];
            [self.fspanel setNonActive];
        }
    }
}

#pragma mark -
#pragma mark Fullscreen support

- (void)showFullscreenController
{
    id currentWindow = [NSApp keyWindow];
    if ([currentWindow respondsToSelector:@selector(hasActiveVideo)] && [currentWindow hasActiveVideo]) {
        if ([currentWindow respondsToSelector:@selector(fullscreen)] && [currentWindow fullscreen] && ![[currentWindow videoView] isHidden]) {

            if ([[VLCMain sharedInstance] activeVideoPlayback])
                [self.fspanel fadeIn];
        }
    }

}

#pragma mark -
#pragma mark split view delegate
- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)dividerIndex
{
    if (dividerIndex == 0)
        return 300.;
    else
        return proposedMax;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)dividerIndex
{
    if (dividerIndex == 0)
        return 100.;
    else
        return proposedMin;
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview
{
    return ([subview isEqual:_splitViewLeft]);
}

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)subview
{
    return (![subview isEqual:_splitViewLeft]);
}

- (void)mainSplitViewDidResizeSubviews:(id)object
{
    f_lastLeftSplitViewWidth = [_splitViewLeft frame].size.width;
    [[[VLCMain sharedInstance] mainMenu] updateSidebarMenuItem: ![_splitView isSubviewCollapsed:_splitViewLeft]];
}

- (void)toggleLeftSubSplitView
{
    [_splitView adjustSubviews];
    if ([_splitView isSubviewCollapsed:_splitViewLeft])
        [_splitView setPosition:f_lastLeftSplitViewWidth ofDividerAtIndex:0];
    else
        [_splitView setPosition:[_splitView minPossiblePositionOfDividerAtIndex:0] ofDividerAtIndex:0];

    [[[VLCMain sharedInstance] mainMenu] updateSidebarMenuItem: ![_splitView isSubviewCollapsed:_splitViewLeft]];
}

#pragma mark -
#pragma mark private playlist magic
- (void)_updatePlaylistTitle
{
    VLCPLModel *model = [[[VLCMain sharedInstance] playlist] model];
    PLRootType root = [model currentRootType];
    BOOL powerLibrary = [model isPowerVLCLibraryRoot];
    playlist_t *p_playlist = pl_Get(getIntf());

    BOOL scanActive = var_GetBool(getIntf()->obj.libvlc,
                                  PVLC_ML_SCAN_ACTIVE);
    uint64_t done = (uint64_t)var_GetInteger(getIntf()->obj.libvlc,
                                             PVLC_ML_SCAN_DONE);
    uint64_t total = (uint64_t)var_GetInteger(getIntf()->obj.libvlc,
                                              PVLC_ML_SCAN_TOTAL);
    if ((root == ROOT_TYPE_MEDIALIBRARY || powerLibrary) && scanActive) {
        if (total == 0) {
            NSString *format = done == 1
                ? _NS("Media Library — scanning… · %llu file indexed")
                : _NS("Media Library — scanning… · %llu files indexed");
            [_categoryLabel setStringValue:
                [NSString stringWithFormat:format,
                                           (unsigned long long)done]];
            return;
        }
        unsigned percent = done >= total ? 100 : (unsigned)
            ((double)done * 100.0 / (double)total);
        unsigned long long remaining = done < total ? total - done : 0;
        NSString *format = remaining == 1
            ? _NS("Media Library — scanning %u%% · %llu file remaining")
            : _NS("Media Library — scanning %u%% · %llu files remaining");
        [_categoryLabel setStringValue:
            [NSString stringWithFormat:format, percent, remaining]];
        return;
    }

    PL_LOCK;
    if (root == ROOT_TYPE_PLAYLIST)
        [_categoryLabel setStringValue: [_NS("Playlist") stringByAppendingString:[self _playbackDurationOfNode:p_playlist->p_playing]]];
    else if (root == ROOT_TYPE_MEDIALIBRARY)
        [_categoryLabel setStringValue: [_NS("Media Library") stringByAppendingString:[self _playbackDurationOfNode:p_playlist->p_media_library]]];
    else if (powerLibrary)
        [_categoryLabel setStringValue:_NS("Media Library")];

    PL_UNLOCK;
}

- (NSString *)_playbackDurationOfNode:(playlist_item_t*)node
{
    if (!node)
        return @"";

    playlist_t * p_playlist = pl_Get(getIntf());
    PL_ASSERT_LOCKED;

    vlc_tick_t mt_duration = playlist_GetNodeDuration( node );

    if (mt_duration < 1)
        return @"";

    mt_duration = mt_duration / 1000000;

    int sec = (mt_duration % 60);
    int min = (mt_duration % 3600) / 60;
    int hours = (mt_duration % 86400) / 3600;
    int days = (int)(mt_duration / 86400);

    NSString *result;
    if (days > 0) {
        result = [NSString stringWithFormat:@"%i:%i:%02i:%02i", days, hours, min, sec];
    } else {
        result = [NSString stringWithFormat:@"%i:%02i:%02i", hours, min, sec];
    }

    return [NSString stringWithFormat:@" — %@", result];
}

- (IBAction)searchItem:(id)sender
{
    [[[VLCMain sharedInstance] playlist] searchUpdate:[_searchField stringValue]];
}

- (IBAction)highlightSearchField:(id)sender
{
    [_searchField selectText:sender];
}

#pragma mark -
#pragma mark Sidebar handling

- (IBAction)sdmenuhandler:(id)sender
{
    NSString * identifier = [sender representedObject];
    msg_Dbg(getIntf(), "Change state for service discovery item '%s'", [identifier UTF8String]);

    if ([identifier length] > 0 && ![identifier isEqualToString:@"lua{sd='freebox',longname='Freebox TV'}"]) {
        playlist_t * p_playlist = pl_Get(getIntf());
        BOOL sd_loaded = playlist_IsServicesDiscoveryLoaded(p_playlist, [identifier UTF8String]);

        if (!sd_loaded)
            playlist_ServicesDiscoveryAdd(p_playlist, [identifier UTF8String]);
        else
            playlist_ServicesDiscoveryRemove(p_playlist, [identifier UTF8String]);
    }
}

- (void)sourceListSelectionDidChange:(NSNotification *)notification
{
    playlist_t * p_playlist = pl_Get(getIntf());

    NSIndexSet *selectedIndexes = [_sidebarView selectedRowIndexes];
    if (selectedIndexes.count == 0)
        return;

    id item = [_sidebarView itemAtRow:[selectedIndexes firstIndex]];

    if ([item playlistItemId] >= 0) {
        [_categoryLabel setStringValue:[item title]];
        PL_LOCK;
        playlist_item_t *networkItem = playlist_ItemGetById(p_playlist,
                                                             (int)[item playlistItemId]);
        if (networkItem)
            [[[[VLCMain sharedInstance] playlist] model] changeRootItem:networkItem];
        PL_UNLOCK;
        [self hidePodcastControls];
        [self hideDropZone];
        return;
    }

    //Set the label text to represent the new selection
    if ([item sdtype] > -1 && [[item identifier] length] > 0) {
        BOOL sd_loaded = playlist_IsServicesDiscoveryLoaded(p_playlist, [[item identifier] UTF8String]);
        if (!sd_loaded) {
            playlist_ServicesDiscoveryAdd(p_playlist, [[item identifier] UTF8String]);
        } else {
            /* an on-line service left empty (network hiccup during its
             * one-shot discovery) has no other way to retry: selecting
             * it again restarts the module, in the background (removing
             * a service joins its thread, which may sit in a network
             * fetch — doing that here would freeze the UI) */
            static BOOL s_sdReloadInFlight = NO;
            BOOL b_empty = NO;
            PL_LOCK;
            playlist_item_t *pl_node = playlist_ChildSearchName(&p_playlist->root,
                                                                [[item title] UTF8String]);
            if (pl_node) {
                if (pl_node->i_children <= 0)
                    b_empty = YES;
                else if (pl_node->i_children == 1) {
                    /* only the error placeholder a service script adds
                     * after a failed discovery */
                    playlist_item_t *pl_child = pl_node->pp_children[0];
                    b_empty = pl_child->i_children < 0 && pl_child->p_input
                           && pl_child->p_input->psz_uri
                           && !strcmp(pl_child->p_input->psz_uri, "vlc://nop");
                }
            }
            PL_UNLOCK;
            if (b_empty
             && ![[item identifier] isEqualToString:@"powervlc_library"]
             && ![[item identifier] hasPrefix:@"powervlc_device{"]
             && !s_sdReloadInFlight) {
                s_sdReloadInFlight = YES;
                NSString *sdName = [item identifier];
                NSString *sdTitle = [item title];
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    playlist_ServicesDiscoveryRemove(p_playlist, [sdName UTF8String]);
                    playlist_ServicesDiscoveryAdd(p_playlist, [sdName UTF8String]);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        /* root the view on the recreated node */
                        PL_LOCK;
                        playlist_item_t *pl_new = playlist_ChildSearchName(&p_playlist->root,
                                                                           [sdTitle UTF8String]);
                        if (pl_new)
                            [[[[VLCMain sharedInstance] playlist] model] changeRootItem:pl_new];
                        PL_UNLOCK;
                        s_sdReloadInFlight = NO;
                    });
                });
            }
        }
    }

    [_categoryLabel setStringValue:[item title]];

    if ([[item identifier] isEqualToString:@"playlist"]) {
        PL_LOCK;
        [[[[VLCMain sharedInstance] playlist] model] changeRootItem:p_playlist->p_playing];
        PL_UNLOCK;

        [self _updatePlaylistTitle];

    } else if ([[item identifier] isEqualToString:@"medialibrary"]) {
        if (p_playlist->p_media_library) {

            PL_LOCK;
            [[[[VLCMain sharedInstance] playlist] model] changeRootItem:p_playlist->p_media_library];

            PL_UNLOCK;

            [self _updatePlaylistTitle];
        }
    } else {
        PL_LOCK;
        NSString *rootTitle = [item serviceRootTitle] ?: [item title];
        const char *title = [[item identifier] isEqualToString:@"powervlc_library"]
                          ? _("PowerVLC Media Library")
                          : [rootTitle UTF8String];
        playlist_item_t *pl_item = playlist_ChildSearchName(&p_playlist->root, title);
        if (pl_item)
            [[[[VLCMain sharedInstance] playlist] model] changeRootItem:pl_item];
        else
            msg_Err(getIntf(), "Could not find playlist entry with name %s", title);

        PL_UNLOCK;
    }

    // Note the order: first hide the podcast controls, then show the drop zone
    if ([[item identifier] isEqualToString:@"podcast"])
        [self showPodcastControls];
    else
        [self hidePodcastControls];

    PL_LOCK;
    if ([[[[VLCMain sharedInstance] playlist] model] currentRootType] != ROOT_TYPE_PLAYLIST ||
        [[[[VLCMain sharedInstance] playlist] model] hasChildren])
        [self hideDropZone];
    else
        [self showDropZone];
    PL_UNLOCK;

    [[NSNotificationCenter defaultCenter] postNotificationName: VLCMediaKeySupportSettingChangedNotification
                                                        object: nil
                                                      userInfo: nil];
}

#pragma mark -
#pragma mark Podcast

- (IBAction)addPodcast:(id)sender
{
    [NSApp beginSheet:_podcastSubscribeWindow modalForWindow:self modalDelegate:self didEndSelector:NULL contextInfo:nil];
}

- (IBAction)addPodcastWindowAction:(id)sender
{
    [_podcastSubscribeWindow orderOut:sender];
    [NSApp endSheet:_podcastSubscribeWindow];

    if (sender == _podcastSubscribeOkButton && [[_podcastSubscribeUrlField stringValue] length] > 0) {
        NSMutableString *podcastConf = [[NSMutableString alloc] init];
        if (config_GetPsz(getIntf(), "podcast-urls") != NULL)
            [podcastConf appendFormat:@"%s|", config_GetPsz(getIntf(), "podcast-urls")];

        [podcastConf appendString: [_podcastSubscribeUrlField stringValue]];
        config_PutPsz(getIntf(), "podcast-urls", [podcastConf UTF8String]);
        var_SetString(pl_Get(getIntf()), "podcast-urls", [podcastConf UTF8String]);
    }
}

/* The feeds to drop are the ones selected in the list, which is
 * unambiguous: no confirmation sheet, and re-subscribing is one URL
 * away. Only the top level holds the feeds, below it are the episodes. */
- (IBAction)removePodcast:(id)sender
{
    char *psz_urls = config_GetPsz(getIntf(), "podcast-urls");
    if (psz_urls == NULL)
        return;
    NSMutableArray *urls = [NSMutableArray arrayWithArray:[toNSStr(psz_urls) componentsSeparatedByString:@"|"]];
    free(psz_urls);

    VLCPlaylist *playlist = [[VLCMain sharedInstance] playlist];
    NSOutlineView *outlineView = [playlist outlineView];
    NSMutableArray *selectedUrls = [[NSMutableArray alloc] init];
    NSIndexSet *selectedRows = [outlineView selectedRowIndexes];
    NSUInteger row = [selectedRows firstIndex];
    while (row != NSNotFound) {
        if ([outlineView levelForRow:row] == 0) {
            VLCPLItem *item = [outlineView itemAtRow:row];
            char *psz_uri = [item input] ? input_item_GetURI([item input]) : NULL;
            if (psz_uri) {
                [selectedUrls addObject:toNSStr(psz_uri)];
                free(psz_uri);
            }
        }
        row = [selectedRows indexGreaterThanIndex:row];
    }

    NSUInteger countBefore = [urls count];
    [urls removeObjectsInArray:selectedUrls];
    if ([urls count] == countBefore)
        return;

    NSString *joinedUrls = [urls componentsJoinedByString:@"|"];
    config_PutPsz(getIntf(), "podcast-urls", [joinedUrls UTF8String]);
    var_SetString(pl_Get(getIntf()), "podcast-urls", [joinedUrls UTF8String]);

    if (playlist_IsServicesDiscoveryLoaded(pl_Get(getIntf()), "podcast"))
        [playlist playlistUpdated];
}

- (IBAction)removePodcastWindowAction:(id)sender
{
    [_podcastUnsubscribeWindow orderOut:sender];
    [NSApp endSheet:_podcastUnsubscribeWindow];

    if (sender == _podcastUnsubscribeOkButton) {
        playlist_t * p_playlist = pl_Get(getIntf());
        char *psz_urls = var_InheritString(p_playlist, "podcast-urls");

        NSMutableArray * urls = [[NSMutableArray alloc] initWithArray:[toNSStr(config_GetPsz(getIntf(), "podcast-urls")) componentsSeparatedByString:@"|"]];
        [urls removeObjectAtIndex: [_podcastUnsubscribePopUpButton indexOfSelectedItem]];
        const char *psz_new_urls = [[urls componentsJoinedByString:@"|"] UTF8String];
        var_SetString(pl_Get(getIntf()), "podcast-urls", psz_new_urls);
        config_PutPsz(getIntf(), "podcast-urls", psz_new_urls);

        free(psz_urls);

        /* update playlist table */
        if (playlist_IsServicesDiscoveryLoaded(p_playlist, "podcast")) {
            [[[VLCMain sharedInstance] playlist] playlistUpdated];
        }
    }
}

- (void)showPodcastControls
{
    _tableViewToPodcastConstraint.priority = 999;
    _podcastView.hidden = NO;

    b_podcastView_displayed = YES;
}

- (void)hidePodcastControls
{
    if (b_podcastView_displayed) {
        _tableViewToPodcastConstraint.priority = 1;
        _podcastView.hidden = YES;

        b_podcastView_displayed = NO;
    }
}

@end

@interface VLCDetachedVideoWindow ()
@end

@implementation VLCDetachedVideoWindow

- (void)awakeFromNib
{
    // sets lion fullscreen behaviour
    [super awakeFromNib];
    [self setAcceptsMouseMovedEvents: YES];

    /* ⚠ La barre de contrôles passe AU-DESSUS de la vue vidéo dans la pile.
     * Mesuré : la barre est bien là, visible, posée à 0,0 1024x36 sous une
     * vue vidéo qui commence à y=36 — et pourtant la bande sortait tout
     * NOIRE. Une sonde (remplissage rouge du -drawRect: de VLCVoutView) l'a
     * montrée peinte par la VUE VIDÉO, dont le rendu déborde sous son propre
     * cadre. Remonter la barre en dernier la met hors d'atteinte, quel que
     * soit ce débordement. Le nib la place en premier, donc dessous. */
    {
        NSView *bar = [[self controlsBar] bottomBarView];
        if (bar != nil && [bar superview] == [self contentView])
            [[self contentView] addSubview:bar
                                positioned:NSWindowAbove
                                relativeTo:nil];
    }

    if (@available(macOS 10.14, *)) {
        [self setContentMinSize: NSMakeSize(363., f_min_video_height + [[self controlsBar] height])];
    } else {
        BOOL darkInterface = config_GetInt(getIntf(), "macosx-interfacestyle");

        if (darkInterface) {
            [self setBackgroundColor: [NSColor clearColor]];

            [self setOpaque: NO];
            [self display];
            [self setHasShadow:NO];
            [self setHasShadow:YES];

            [self setTitle: defaultWindowTitle()];

            [self setContentMinSize: NSMakeSize(363., f_min_video_height + [[self controlsBar] height] + [self.titlebarView frame].size.height)];
        } else {
            [self setContentMinSize: NSMakeSize(363., f_min_video_height + [[self controlsBar] height])];
        }
    }
}

@end
