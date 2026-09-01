/*****************************************************************************
 * VLCSlider.m
 *****************************************************************************
 * Copyright (C) 2017 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Marvin Scholz <epirat07 at gmail dot com>
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

#import "VLCSlider.h"
#import "VLCSliderCell.h"
#import "VLCStringUtility.h"
#import "VLCCoreInteraction.h"
#import "VLCMain.h"
#import "CompatibilityFixes.h"

/*****************************************************************************
 * VLCSeekTooltipWindow: borderless floating panel following the mouse on
 * the seek bar, showing the hovered time, the chapter (when any) and,
 * when a hover delegate provides one, a preview thumbnail.
 *****************************************************************************/

@interface VLCSeekTooltipBackgroundView : NSView
@end

@implementation VLCSeekTooltipBackgroundView
- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor colorWithCalibratedWhite:0.12 alpha:0.92] setFill];
    [[NSBezierPath bezierPathWithRoundedRect:[self bounds]
                                     xRadius:4.0 yRadius:4.0] fill];
}
@end

@interface VLCSeekTooltipWindow : NSWindow
{
    NSTextField *_textField;
    NSImageView *_imageView;
    NSWindow *_stereoMirrorWindow;
    NSImageView *_stereoMirrorImageView;
}
- (void)updateWithText:(NSString *)text
                 image:(NSImage *)image
        atScreenBottom:(NSPoint)bottomCenter;
- (void)updateStereoMirror;
@end

@implementation VLCSeekTooltipWindow

- (instancetype)init
{
    self = [super initWithContentRect:NSMakeRect(0, 0, 120, 24)
                            styleMask:NSBorderlessWindowMask
                              backing:NSBackingStoreBuffered
                                defer:NO];
    if (self) {
        [self setOpaque:NO];
        [self setHasShadow:YES];
        [self setBackgroundColor:[NSColor clearColor]];
        [self setLevel:NSFloatingWindowLevel];
        [self setIgnoresMouseEvents:YES];
        [self setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces
                                  | NSWindowCollectionBehaviorFullScreenAuxiliary];

        NSView *content = [[VLCSeekTooltipBackgroundView alloc] initWithFrame:NSZeroRect];
        [self setContentView:content];

        _imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
        [_imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
        [content addSubview:_imageView];

        _textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
        [_textField setEditable:NO];
        [_textField setSelectable:NO];
        [_textField setBezeled:NO];
        [_textField setBordered:NO];
        [_textField setDrawsBackground:NO];
        [_textField setAlignment:NSCenterTextAlignment];
        [_textField setTextColor:[NSColor whiteColor]];
        [_textField setFont:[NSFont systemFontOfSize:11.0]];
        [content addSubview:_textField];
    }
    return self;
}

- (void)updateWithText:(NSString *)text
                 image:(NSImage *)image
        atScreenBottom:(NSPoint)bottomCenter
{
    const CGFloat padding = 5.0;
    const CGFloat thumbWidth = 160.0;

    [_textField setStringValue:text];
    [_textField sizeToFit];
    NSSize textSize = [_textField frame].size;

    CGFloat width = textSize.width + 2 * padding;
    CGFloat height = textSize.height + 2 * padding;

    NSSize thumbSize = NSZeroSize;
    if (image) {
        NSSize imgSize = [image size];
        CGFloat aspect = (imgSize.width > 0) ? imgSize.height / imgSize.width : 0.5625;
        thumbSize = NSMakeSize(thumbWidth, thumbWidth * aspect);
        if (width < thumbWidth + 2 * padding)
            width = thumbWidth + 2 * padding;
        height += thumbSize.height + padding;
    }

    [_imageView setImage:image];
    [_imageView setHidden:image == nil];
    if (image)
        [_imageView setFrame:NSMakeRect((width - thumbSize.width) / 2,
                                        textSize.height + 2 * padding,
                                        thumbSize.width, thumbSize.height)];
    [_textField setFrame:NSMakeRect((width - textSize.width) / 2, padding,
                                    textSize.width, textSize.height)];

    NSRect frame = NSMakeRect(bottomCenter.x - width / 2, bottomCenter.y,
                              width, height);
    /* Keep the tooltip inside the slider's screen. A brand-new borderless
     * window has no useful screen yet and AppKit reports the main display;
     * in MVC fullscreen that used to clamp an HDMI tooltip to x=1342 on the
     * Mac panel while the slider itself was around x=2360 on the projector. */
    NSScreen *screen = [[self parentWindow] screen];
    if (!screen) {
        for (NSScreen *candidate in [NSScreen screens]) {
            if (NSPointInRect(bottomCenter, [candidate frame])) {
                screen = candidate;
                break;
            }
        }
    }
    if (!screen)
        screen = [self screen] ? [self screen] : [NSScreen mainScreen];
    if (screen) {
        NSRect visible = [screen visibleFrame];
        if (NSMaxX(frame) > NSMaxX(visible))
            frame.origin.x = NSMaxX(visible) - NSWidth(frame);
        if (NSMinX(frame) < NSMinX(visible))
            frame.origin.x = NSMinX(visible);
    }
    [self setFrame:frame display:YES];

    if (![self isVisible])
        [self orderFront:nil];
    [self updateStereoMirror];
}

- (void)updateStereoMirror
{
    intf_thread_t *intf = getIntf();
    NSScreen *screen = self.screen;
    CGFloat height = screen ? NSHeight(screen.frame) : 0.;
    CGFloat gap;
    if (!intf || var_InheritInteger(intf, "stereo3d-fullscreen-display") <= 0)
        gap = 0.;
    else if (fabs(height - 2205.) < 2.)
        gap = 45.;
    else if (fabs(height - 1470.) < 2.)
        gap = 30.;
    else
        gap = 0.;

    if (gap == 0.) {
        [_stereoMirrorWindow orderOut:nil];
        return;
    }

    if (!_stereoMirrorWindow) {
        _stereoMirrorWindow = [[NSWindow alloc]
            initWithContentRect:self.frame
                      styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered defer:NO];
        [_stereoMirrorWindow setOpaque:NO];
        [_stereoMirrorWindow setBackgroundColor:[NSColor clearColor]];
        [_stereoMirrorWindow setHasShadow:NO];
        [_stereoMirrorWindow setIgnoresMouseEvents:YES];
        [_stereoMirrorWindow setReleasedWhenClosed:NO];
        [_stereoMirrorWindow setCollectionBehavior:
            NSWindowCollectionBehaviorCanJoinAllSpaces |
            NSWindowCollectionBehaviorFullScreenAuxiliary];
        _stereoMirrorImageView = [[NSImageView alloc]
            initWithFrame:_stereoMirrorWindow.contentView.bounds];
        [_stereoMirrorImageView setImageScaling:NSImageScaleAxesIndependently];
        [_stereoMirrorImageView setAutoresizingMask:
            NSViewWidthSizable | NSViewHeightSizable];
        [_stereoMirrorWindow.contentView addSubview:_stereoMirrorImageView];
    }

    NSView *content = self.contentView;
    [content displayIfNeeded];
    NSRect bounds = content.bounds;
    NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect:bounds];
    if (!rep)
        return;
    [content cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSImage *snapshot = [[NSImage alloc] initWithSize:bounds.size];
    [snapshot addRepresentation:rep];
    [_stereoMirrorImageView setImage:snapshot];

    NSRect frame = self.frame;
    BOOL sourceIsLowerEye = NSMidY(frame) < NSMidY(screen.frame);
    CGFloat eyeStride = (height - gap) / 2. + gap;
    frame.origin.y += sourceIsLowerEye ? eyeStride : -eyeStride;
    int depth = (int)var_InheritInteger(intf, "stereo3d-overlay-depth");
    depth = MAX(-100, MIN(100, depth));
    CGFloat disparity = NSWidth(screen.frame) * .04 * depth / 100.;
    frame.origin.x += sourceIsLowerEye ? disparity : -disparity;

    [_stereoMirrorWindow setFrame:frame display:NO];
    [_stereoMirrorWindow setLevel:self.level];
    [_stereoMirrorWindow setAlphaValue:self.alphaValue];
    [_stereoMirrorWindow orderFront:nil];
}

- (void)orderOut:(id)sender
{
    [_stereoMirrorWindow orderOut:sender];
    [super orderOut:sender];
}

@end

@interface VLCSlider ()
{
    NSTrackingArea *_hoverTrackingArea;
    VLCSeekTooltipWindow *_tooltipWindow;
    NSTimer *_thumbnailDebounceTimer;
    double _hoverFraction;
    NSPoint _hoverPoint;          /* the point the tooltip was built for */
    NSImage *_hoverThumbnail;
    double _hoverThumbnailFraction;
    BOOL _hovering;
}
@end

@implementation VLCSlider


/* Tolérance du « c'est bien la position demandée », en FRACTION de barre.
 * ⚠⚠⚠ Elle était en SECONDES DE FILM : sur un long média un pixel de barre en
 * vaut bien plus (~13 s sur un film de 2 h 20 étalé sur 640 px), donc le
 * moindre frémissement de souris pendant le décodage faisait jeter une
 * vignette pourtant produite. Même correctif que l'interface legacy. */
- (double)hoverMatchTolerance
{
    CGFloat width = self.frame.size.width;
    if (width < 1.)
        width = 1.;
    double byPixels = 3.0 / (double)width;
    double bySeconds = (self.mediaDuration > 0.) ? 2.0 / self.mediaDuration : 0.;
    return byPixels > bySeconds ? byPixels : bySeconds;
}

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];

    if (self) {
        NSAssert([self.cell isKindOfClass:[VLCSliderCell class]],
                 @"VLCSlider cell is not VLCSliderCell");
        _isScrollable = YES;
        if (@available(macOS 10.14, *)) {
            [self viewDidChangeEffectiveAppearance];

#if (__MAC_OS_X_VERSION_MAX_ALLOWED >= 140000)
            // While this is available back to 10.9, it defaulted to
            // true in macOS 13 and earlier so setting it starting
            // in macOS 10.14+ is fine.
            [self setClipsToBounds:YES];
#endif
        } else {
            [self setSliderStyleLight];
        }
    }
    return self;
}

+ (Class)cellClass
{
    return [VLCSliderCell class];
}

- (void)scrollWheel:(NSEvent *)event
{
    // Scrolling would silently move the clip start bound; ignore it while
    // the clip creation knobs are shown.
    if ([self clipKnobsActive])
        return;
    if (!_isScrollable)
        return [super scrollWheel:event];
    double increment;
    CGFloat deltaY = [event scrollingDeltaY];
    double range = [self maxValue] - [self minValue];

    // Scroll less for high precision, else it's too fast
    if (event.hasPreciseScrollingDeltas) {
        increment = (range * 0.002) * deltaY;
    } else {
        if (deltaY == 0.0)
            return;
        increment = (range * 0.01 * deltaY);
    }

    // If scrolling is inversed, increment in other direction
    if (!event.isDirectionInvertedFromDevice)
        increment = -increment;

    [self setDoubleValue:self.doubleValue - increment];
    [self sendAction:self.action to:self.target];
}

// Workaround for 10.7
// http://stackoverflow.com/questions/3985816/custom-nsslidercell
- (void)setNeedsDisplayInRect:(NSRect)invalidRect {
    [super setNeedsDisplayInRect:[self bounds]];
}

- (BOOL)getIndefinite
{
    return [(VLCSliderCell*)[self cell] indefinite];
}

- (void)setIndefinite:(BOOL)indefinite
{
    [(VLCSliderCell*)[self cell] setIndefinite:indefinite];
}

- (BOOL)getKnobHidden
{
    return [(VLCSliderCell*)[self cell] isKnobHidden];
}

- (void)setKnobHidden:(BOOL)isKnobHidden
{
    [(VLCSliderCell*)[self cell] setKnobHidden:isKnobHidden];
}

- (BOOL)isFlipped
{
    return NO;
}

#pragma mark -
#pragma mark Clip creation mode

- (BOOL)clipKnobsActive
{
    return [(VLCSliderCell*)[self cell] clipKnobsActive];
}

- (void)setClipKnobsActive:(BOOL)active
{
    [(VLCSliderCell*)[self cell] setClipKnobsActive:active];
    [self setNeedsDisplay:YES];
}

- (double)clipEndValue
{
    return [(VLCSliderCell*)[self cell] clipEndValue];
}

- (void)setClipEndValue:(double)value
{
    [(VLCSliderCell*)[self cell] setClipEndValue:value];
    [self setNeedsDisplay:YES];
}

- (double)playbackMarkerValue
{
    return [(VLCSliderCell*)[self cell] playbackMarkerValue];
}

- (void)setPlaybackMarkerValue:(double)value
{
    [(VLCSliderCell*)[self cell] setPlaybackMarkerValue:value];
    [self setNeedsDisplay:YES];
}

- (NSInteger)activeClipKnob
{
    return [(VLCSliderCell*)[self cell] activeClipKnob];
}

#pragma mark -
#pragma mark Hover tooltip (time, chapter, preview thumbnail)

- (NSArray *)chapterFractions
{
    return [(VLCSliderCell*)[self cell] chapterFractions];
}

- (void)setChapterFractions:(NSArray *)fractions
{
    [(VLCSliderCell*)[self cell] setChapterFractions:fractions];
    [self setNeedsDisplay:YES];
}

- (NSArray *)bookmarkFractions
{
    return [(VLCSliderCell*)[self cell] bookmarkFractions];
}

- (void)setBookmarkFractions:(NSArray *)fractions
{
    [(VLCSliderCell*)[self cell] setBookmarkFractions:fractions];
    [self setNeedsDisplay:YES];
}

- (void)reloadBookmarks
{
    NSMutableArray *fractions = [NSMutableArray array];
    NSMutableArray *names = [NSMutableArray array];
    NSMutableArray *times = [NSMutableArray array];
    input_thread_t *p_input = pl_CurrentInput(getIntf());
    if (p_input) {
        vlc_tick_t duration = var_GetInteger(p_input, "length");
        seekpoint_t **pp_bookmarks = NULL;
        int i_bookmarks = 0;
        if (duration > 0 && input_Control(p_input, INPUT_GET_BOOKMARKS,
                                          &pp_bookmarks, &i_bookmarks) == VLC_SUCCESS) {
            for (int i = 0; i < i_bookmarks; i++) {
                [fractions addObject:[NSNumber numberWithDouble:
                    (double)pp_bookmarks[i]->i_time_offset / (double)duration]];
                [names addObject:pp_bookmarks[i]->psz_name
                    ? toNSStr(pp_bookmarks[i]->psz_name) : @""];
                [times addObject:[NSNumber numberWithLongLong:
                    pp_bookmarks[i]->i_time_offset]];
                vlc_seekpoint_Delete(pp_bookmarks[i]);
            }
            free(pp_bookmarks);
        }
        vlc_object_release(p_input);
    }
    self.bookmarkNames = names;
    self.bookmarkTimes = times;
    self.bookmarkFractions = fractions;
}

- (NSInteger)bookmarkIndexNearLocationX:(CGFloat)x
{
    NSArray *fractions = self.bookmarkFractions;
    VLCSliderCell *cell = (VLCSliderCell *)[self cell];
    CGFloat knobThickness = [cell knobThickness];
    CGFloat usableWidth = NSWidth([self bounds]) - knobThickness;
    if (usableWidth <= 0.0)
        return NSNotFound;
    NSInteger nearest = NSNotFound;
    CGFloat best = 6.0;
    for (NSUInteger i = 0; i < [fractions count]; i++) {
        double fraction = [[fractions objectAtIndex:i] doubleValue];
        CGFloat markerX = NSMinX([self bounds]) + usableWidth * fraction
                        + knobThickness / 2.0;
        CGFloat distance = fabs(markerX - x);
        if (distance <= 5.0 && distance < best) {
            best = distance;
            nearest = (NSInteger)i;
        }
    }
    return nearest;
}

- (void)updateTrackingAreas
{
    [super updateTrackingAreas];
    if (_hoverTrackingArea)
        [self removeTrackingArea:_hoverTrackingArea];
    /* ActiveInActiveApp, not ActiveInKeyWindow: the fullscreen controls
     * live in a borderless panel that never becomes the key window, so a
     * key-window-only tracking area never fires there */
    _hoverTrackingArea = [[NSTrackingArea alloc]
        initWithRect:[self bounds]
             options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved
                      | NSTrackingActiveInActiveApp)
               owner:self
            userInfo:nil];
    [self addTrackingArea:_hoverTrackingArea];
}

- (void)hideHoverTooltip
{
    _hovering = NO;
    [_tooltipWindow orderOut:nil];
    [_thumbnailDebounceTimer invalidate];
    _thumbnailDebounceTimer = nil;
    if ([self.hoverDelegate respondsToSelector:@selector(sliderHoverEnded:)])
        [self.hoverDelegate sliderHoverEnded:self];
}

- (void)refreshHoverForCurrentMouseLocation
{
    NSWindow *window = [self window];
    if (!window || ![window isVisible]) {
        if (_hovering)
            [self hideHoverTooltip];
        return;
    }

    NSPoint local = [self convertPoint:[window mouseLocationOutsideOfEventStream]
                              fromView:nil];
    if (NSMouseInRect(local, [self bounds], [self isFlipped])) {
        /* Do not continuously re-arm the thumbnail debounce while only the
         * stereo snapshot (rather than the pointer) is being refreshed. */
        if (!_hovering || fabs(local.x - _hoverPoint.x) >= 1.0
                       || fabs(local.y - _hoverPoint.y) >= 1.0)
            [self updateHoverTooltipForPoint:local];
    } else if (_hovering) {
        [self hideHoverTooltip];
    }
}

- (void)mouseMoved:(NSEvent *)event
{
    [self updateHoverTooltipForPoint:
        [self convertPoint:[event locationInWindow] fromView:nil]];
}

- (void)refreshHoverForHostWindowPoint:(NSPoint)point
{
    NSPoint local = [self convertPoint:point fromView:nil];
    if (NSMouseInRect(local, [self bounds], [self isFlipped]))
        [self updateHoverTooltipForPoint:local];
    else if (_hovering)
        [self hideHoverTooltip];
}

- (void)updateHoverTooltipForPoint:(NSPoint)local
{
    if (![self isEnabled] || self.mediaDuration <= 0) {
        [self hideHoverTooltip];
        return;
    }

    double value = [self valueForLocationX:local.x];
    double range = [self maxValue] - [self minValue];
    double fraction = range > 0 ? (value - [self minValue]) / range : 0.;
    _hovering = YES;
    _hoverFraction = fraction;
    _hoverPoint = local;

    long long seconds = (long long)llround(fraction * self.mediaDuration);
    NSString *text = [[VLCStringUtility sharedInstance] stringForTime:seconds];

    NSInteger bookmarkIndex = [self bookmarkIndexNearLocationX:local.x];
    if (bookmarkIndex != NSNotFound
        && (NSUInteger)bookmarkIndex < [self.bookmarkNames count]) {
        NSString *name = [self.bookmarkNames objectAtIndex:(NSUInteger)bookmarkIndex];
        if ([name length] > 0)
            text = [NSString stringWithFormat:@"%@ — %@", name, text];
    }

    /* chapter (when any): last one starting at or before the position */
    NSArray *chapterFractions = [self chapterFractions];
    NSUInteger chapterCount = [chapterFractions count];
    if (bookmarkIndex == NSNotFound && chapterCount > 0
        && [self.chapterNames count] == chapterCount) {
        NSInteger selected = -1;
        for (NSUInteger i = 0; i < chapterCount; i++) {
            if ([[chapterFractions objectAtIndex:i] doubleValue] <= fraction)
                selected = (NSInteger)i;
        }
        if (selected >= 0) {
            NSString *name = [self.chapterNames objectAtIndex:(NSUInteger)selected];
            if ([name length] > 0)
                text = [NSString stringWithFormat:@"%@ — %@", name, text];
        }
    }

    /* in clip creation mode, hovering the clip range also shows the
     * clip's current total duration */
    if (self.clipKnobsActive && range > 0) {
        double startFraction = ([self doubleValue] - [self minValue]) / range;
        double endFraction = (self.clipEndValue - [self minValue]) / range;
        if (fraction >= startFraction && fraction <= endFraction) {
            long long clipSeconds = (long long)llround(
                (endFraction - startFraction) * self.mediaDuration);
            text = [NSString stringWithFormat:@"%@ — %@ %@", text, _NS("Clip:"),
                    [[VLCStringUtility sharedInstance] stringForTime:clipSeconds]];
        }
    }

    if (!_tooltipWindow)
        _tooltipWindow = [[VLCSeekTooltipWindow alloc] init];
    NSWindow *hostWindow = self.window;
    if (_tooltipWindow.parentWindow != hostWindow) {
        [_tooltipWindow.parentWindow removeChildWindow:_tooltipWindow];
        [hostWindow addChildWindow:_tooltipWindow ordered:NSWindowAbove];
    }
    /* stay above whatever hosts the slider: the fullscreen panel sits at
     * NSModalPanelWindowLevel, higher than the tooltip's floating level */
    NSInteger wantedLevel = [[self window] level] + 1;
    if ([_tooltipWindow level] != wantedLevel)
        [_tooltipWindow setLevel:wantedLevel];

    /* only show a cached thumbnail matching the hovered position (within
     * two seconds), else wait for the (debounced) provider */
    NSImage *thumbnail = nil;
    if (_hoverThumbnail && self.mediaDuration > 0
        && fabs(_hoverThumbnailFraction - fraction) <= [self hoverMatchTolerance])
        thumbnail = _hoverThumbnail;

    NSPoint windowPoint = NSMakePoint(local.x, NSMaxY([self bounds]) + 6.0);
    NSPoint screenPoint = [[self window] convertRectToScreen:
        (NSRect){ .origin = [self convertPoint:windowPoint toView:nil],
                  .size = NSZeroSize }].origin;
    [_tooltipWindow updateWithText:text image:thumbnail atScreenBottom:screenPoint];

    /* the thumbnail request is debounced so a frantic hover does not spam
     * the thumbnailer: it fires once the mouse has settled for half a
     * second (was a full second, shortened for responsiveness) */
    if (self.hoverDelegate) {
        [_thumbnailDebounceTimer invalidate];
        _thumbnailDebounceTimer =
            [NSTimer scheduledTimerWithTimeInterval:0.5
                                             target:self
                                           selector:@selector(thumbnailDebounceFired:)
                                           userInfo:nil
                                            repeats:NO];
    }
}

- (void)thumbnailDebounceFired:(NSTimer *)timer
{
    _thumbnailDebounceTimer = nil;
    if (!_hovering)
        return;
    if ([self.hoverDelegate respondsToSelector:@selector(slider:hoverThumbnailWantedAtFraction:)])
        [self.hoverDelegate slider:self hoverThumbnailWantedAtFraction:_hoverFraction];
}

- (void)setHoverThumbnail:(NSImage *)image forFraction:(double)fraction
{
    _hoverThumbnail = image;
    _hoverThumbnailFraction = fraction;
    if (!_hovering || !image)
        return;
    /* Repaint the tooltip around the image, for the very point it was
     * built for: sampling the mouse again here would re-read a pointer
     * that has drifted by a pixel in the meantime, and the announced time
     * would visibly jump (a pixel is several seconds on a long media)
     * just because the preview landed. */
    if (self.mediaDuration > 0
        && fabs(fraction - _hoverFraction) <= [self hoverMatchTolerance])
        [self updateHoverTooltipForPoint:_hoverPoint];
}

- (void)mouseExited:(NSEvent *)event
{
    [self hideHoverTooltip];
}

/* clicking a knob makes the slider the first responder: the bare arrow
 * keys then land here (NSSlider would nudge its own value) instead of
 * reaching the core hotkeys module. In clip mode they must behave like
 * everywhere else: one-frame nudge of the selected bound. */
- (void)keyDown:(NSEvent *)event
{
    if (self.clipKnobsActive) {
        NSString *characters = [event charactersIgnoringModifiers];
        if ([characters length] == 1) {
            unichar key = [characters characterAtIndex:0];
            if (key == NSLeftArrowFunctionKey || key == NSRightArrowFunctionKey) {
                [[VLCCoreInteraction sharedInstance]
                    clipStepFrames:(key == NSRightArrowFunctionKey ? 1 : -1)];
                return;
            }
        }
    }
    [super keyDown:event];
}

- (double)valueForLocationX:(CGFloat)x
{
    // Same geometry as VLCSliderCell: the bar fills the control bounds and
    // the knob diameter equals the bar height.
    NSRect barRect = [self bounds];
    CGFloat knobThickness = barRect.size.height;
    CGFloat usableWidth = NSWidth(barRect) - knobThickness;
    if (usableWidth <= 0)
        return [self minValue];

    double fraction = (x - NSMinX(barRect) - (knobThickness / 2)) / usableWidth;
    if (fraction < 0.0)
        fraction = 0.0;
    else if (fraction > 1.0)
        fraction = 1.0;
    return [self minValue] + fraction * ([self maxValue] - [self minValue]);
}

- (void)moveClipKnob:(NSInteger)knob toLocationX:(CGFloat)x
{
    VLCSliderCell *cell = (VLCSliderCell*)[self cell];
    double value = [self valueForLocationX:x];
    if (knob == 1) {
        // Keep start <= end
        if (value > [cell clipEndValue])
            value = [cell clipEndValue];
        [self setDoubleValue:value];
    } else if (knob == 2) {
        if (value < [self doubleValue])
            value = [self doubleValue];
        [cell setClipEndValue:value];
    } else {
        /* scrub: only the playback marker moves, clamped to the clip */
        if (value < [self doubleValue])
            value = [self doubleValue];
        else if (value > [cell clipEndValue])
            value = [cell clipEndValue];
        [cell setPlaybackMarkerValue:value];
    }
    [self setNeedsDisplay:YES];
}

/* Plain (non clip mode) click and drag, tracked by hand.
 *
 * AppKit turns a click on the bar into a value with a knob width of its
 * own (~11 pt), while the knob drawn here is as tall as the bar and the
 * hover tooltip converts with THAT geometry: the two disagree by a couple
 * of pixels, which on a 1.5 h media is a seek landing up to ~17 s away
 * from the time the tooltip just announced. -knobThickness does not fix
 * it (AppKit ignores it for tracking), so the conversion is done here,
 * with -valueForLocationX: -- the very function the tooltip uses and the
 * exact inverse of the knob drawing. */
- (void)trackPlainSeekFromEvent:(NSEvent *)event
{
    while (event != nil && [event type] != NSLeftMouseUp) {
        NSPoint local = [self convertPoint:[event locationInWindow] fromView:nil];
        [self setDoubleValue:[self valueForLocationX:local.x]];
        [self setNeedsDisplay:YES];
        [self sendAction:[self action] to:[self target]];

        event = [[self window] nextEventMatchingMask:
                 (NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
    }
}

- (void)mouseDown:(NSEvent *)event
{
    [self hideHoverTooltip];

    VLCSliderCell *cell = (VLCSliderCell*)[self cell];
    if (![self isEnabled])
        return [super mouseDown:event];
    if (![cell clipKnobsActive]) {
        NSPoint local = [self convertPoint:[event locationInWindow] fromView:nil];
        NSInteger bookmarkIndex = [self bookmarkIndexNearLocationX:local.x];
        if (bookmarkIndex != NSNotFound
            && (NSUInteger)bookmarkIndex < [self.bookmarkTimes count]) {
            input_thread_t *p_input = pl_CurrentInput(getIntf());
            if (p_input) {
                input_Control(p_input, INPUT_SET_BOOKMARK, (int)bookmarkIndex);
                vlc_object_release(p_input);
            }
            return;
        }
        return [self trackPlainSeekFromEvent:event];
    }

    NSPoint local = [self convertPoint:[event locationInWindow] fromView:nil];

    // Each bound is drawn as a half disc pointing away from the clip, so
    // its grab area is that half (plus a couple of pixels of slop) and the
    // two areas can never overlap: the midpoint between both bounds always
    // splits them, however close they get. Strictly between the two bounds:
    // plain seek (scrub), leaving them alone. Outside the range: pull the
    // nearest bound.
    NSRect startKnobRect = [cell knobRectFlipped:NO];
    NSRect endKnobRect = [cell clipEndKnobRect];
    CGFloat radius = NSWidth(startKnobRect) / 2.0;
    CGFloat slop = 2.0;
    CGFloat startX = NSMidX(startKnobRect);
    CGFloat endX = NSMidX(endKnobRect);
    CGFloat middleX = (startX + endX) / 2.0;
    /* inner edges, never crossing the midpoint between the two bounds */
    CGFloat startInnerX = MIN(startX + slop, middleX);
    CGFloat endInnerX = MAX(endX - slop, middleX);
    NSInteger knob;
    if (local.x >= startX - radius - slop && local.x <= startInnerX)
        knob = 1;
    else if (local.x >= endInnerX && local.x <= endX + radius + slop)
        knob = 2;
    else if (local.x > startX && local.x < endX)
        knob = 3; /* scrub between the bounds */
    else
        knob = (local.x <= startX) ? 1 : 2;

    [cell setActiveClipKnob:knob];
    [cell setHighlighted:YES];

    // Clicking a knob (or the track) seeks right away: send the regular
    // action; the target inspects activeClipKnob to know which bound moved.
    [self moveClipKnob:knob toLocationX:local.x];
    [self sendAction:[self action] to:[self target]];

    /* The knob follows the mouse at full rate, the preview seek behind it
     * is PACED -- but never dropped. A seek is not free (an accurate one
     * decodes from the preceding key frame), so firing one per mouse
     * event just queues positions that are already stale when they are
     * served, and the picture trails the handle. One every 100 ms then,
     * with a TRAILING one: a single pixel nudge, which frame-accurate
     * trimming is made of, still gets previewed within 100 ms even though
     * no further event follows it. The release always previews too, so
     * what stays on screen is the exact bound. */
    const NSTimeInterval interval = 0.1;
    NSTimeInterval lastPreview = [NSDate timeIntervalSinceReferenceDate];
    BOOL pendingPreview = NO;

    for (;;) {
        NSDate *limit = pendingPreview
            ? [NSDate dateWithTimeIntervalSinceNow:0.02] : [NSDate distantFuture];
        event = [[self window] nextEventMatchingMask:
                     (NSLeftMouseDraggedMask | NSLeftMouseUpMask)
                                           untilDate:limit
                                              inMode:NSEventTrackingRunLoopMode
                                             dequeue:YES];
        if (event) {
            local = [self convertPoint:[event locationInWindow] fromView:nil];
            [self moveClipKnob:knob toLocationX:local.x];
            if ([event type] == NSLeftMouseUp) {
                [self sendAction:[self action] to:[self target]];
                break;
            }
            pendingPreview = YES;
        }

        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (pendingPreview && now - lastPreview >= interval) {
            lastPreview = now;
            pendingPreview = NO;
            [self sendAction:[self action] to:[self target]];
        }
    }

    [cell setHighlighted:NO];
    [cell setActiveClipKnob:0];
    [self setNeedsDisplay:YES];
}

- (void)setSliderStyleLight
{
    [(VLCSliderCell*)[self cell] setSliderStyleLight];
}

- (void)setSliderStyleDark
{
    [(VLCSliderCell*)[self cell] setSliderStyleDark];
}

- (void)viewDidChangeEffectiveAppearance
{
    if (@available(macOS 10_14, *)) {
        if ([self.effectiveAppearance.name isEqualToString:NSAppearanceNameDarkAqua])
            [self setSliderStyleDark];
        else
            [self setSliderStyleLight];
    }

    [self setNeedsDisplay:YES];
}

@end
