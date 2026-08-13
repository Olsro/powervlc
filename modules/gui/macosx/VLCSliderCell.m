/*****************************************************************************
 * VLCSliderCell.m
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

#import "VLCSliderCell.h"
#import "CompatibilityFixes.h"
#import "NSGradient+VLCAdditions.h"

@interface VLCSliderCell () {
    NSInteger _animationPosition;
    double _lastTime;
    double _deltaToLastFrame;
    CVDisplayLinkRef _displayLink;
}
@end

@implementation VLCSliderCell

- (instancetype)initWithCoder:(NSCoder *)coder
{
    self = [super initWithCoder:coder];
    if (self) {
        [self setSliderStyleLight];
        _animationWidth = [[self controlView] bounds].size.width;

        [self initDisplayLink];
    }
    return self;
}

- (void)setSliderStyleLight
{
    // Color Declarations
    _gradientColor = [NSColor colorWithCalibratedRed: 0.663 green: 0.663 blue: 0.663 alpha: 1];
    _gradientColor2 = [NSColor colorWithCalibratedRed: 0.749 green: 0.749 blue: 0.753 alpha: 1];
    _trackStrokeColor = [NSColor colorWithCalibratedRed: 0.619 green: 0.624 blue: 0.623 alpha: 1];
    _filledTrackColor = [NSColor colorWithCalibratedRed: 0.55 green: 0.55 blue: 0.55 alpha: 1];
    _knobFillColor = [NSColor colorWithCalibratedRed: 1 green: 1 blue: 1 alpha: 1];
    _activeKnobFillColor = [NSColor colorWithCalibratedRed: 0.95 green: 0.95 blue: 0.95 alpha: 1];
    _shadowColor = [NSColor colorWithCalibratedRed: 0.32 green: 0.32 blue: 0.32 alpha: 1];
    _knobStrokeColor = [NSColor colorWithCalibratedRed: 0.592 green: 0.596 blue: 0.596 alpha: 1];

    // Gradient Declarations
    _trackGradient = [[NSGradient alloc] initWithColorsAndLocations:
                      _gradientColor, 0.0,
                      [_gradientColor blendedColorWithFraction:0.5 ofColor:_gradientColor2], 0.60,
                      _gradientColor2, 1.0, nil];

    // Shadow Declarations
    _knobShadow = [[NSShadow alloc] init];
    _knobShadow.shadowColor = _shadowColor;
    _knobShadow.shadowOffset = NSMakeSize(0, 0);
    _knobShadow.shadowBlurRadius = 2;

    _highlightBackground = [NSColor colorWithCalibratedRed:0.20 green:0.55 blue:0.91 alpha:1.0];
    NSColor *highlightAccent = [NSColor colorWithCalibratedRed:0.4588235294 green:0.7254901961 blue:0.9882352941 alpha:1.0];
    _highlightGradient = [[NSGradient alloc] initWithColors:@[
                                                              _highlightBackground,
                                                              highlightAccent,
                                                              _highlightBackground
                                                              ]];
}

- (void)setSliderStyleDark
{
    // Color Declarations
    if (OSX_MOJAVE_AND_HIGHER) {
        _gradientColor = [NSColor colorWithCalibratedRed: 0.20 green: 0.20 blue: 0.20 alpha: 1];
        _knobFillColor = [NSColor colorWithCalibratedRed: 0.81 green: 0.81 blue: 0.81 alpha: 1];
        _activeKnobFillColor = [NSColor colorWithCalibratedRed: 0.76 green: 0.76 blue: 0.76 alpha: 1];
    } else {
        _gradientColor = [NSColor colorWithCalibratedRed: 0.24 green: 0.24 blue: 0.24 alpha: 1];
        _knobFillColor = [NSColor colorWithCalibratedRed: 1 green: 1 blue: 1 alpha: 1];
        _activeKnobFillColor = [NSColor colorWithCalibratedRed: 0.95 green: 0.95 blue: 0.95 alpha: 1];
    }
    _gradientColor2 = [NSColor colorWithCalibratedRed: 0.15 green: 0.15 blue: 0.15 alpha: 1];
    _trackStrokeColor = [NSColor colorWithCalibratedRed: 0.23 green: 0.23 blue: 0.23 alpha: 1];
    _filledTrackColor = [NSColor colorWithCalibratedRed: 0.15 green: 0.15 blue: 0.15 alpha: 1];
    _shadowColor = [NSColor colorWithCalibratedRed: 0.32 green: 0.32 blue: 0.32 alpha: 1];
    _knobStrokeColor = [NSColor colorWithCalibratedRed: 0.592 green: 0.596 blue: 0.596 alpha: 1];

    // Gradient Declarations
    _trackGradient = [[NSGradient alloc] initWithColorsAndLocations:
                      _gradientColor, 0.0,
                      [_gradientColor blendedColorWithFraction:0.5 ofColor:_gradientColor2], 0.60,
                      _gradientColor2, 1.0, nil];

    // Shadow Declarations
    _knobShadow = [[NSShadow alloc] init];
    _knobShadow.shadowColor = _shadowColor;
    _knobShadow.shadowOffset = NSMakeSize(0, 0);
    _knobShadow.shadowBlurRadius = 2;

    _highlightBackground = [NSColor colorWithCalibratedRed:0.20 green:0.55 blue:0.91 alpha:1.0];
    NSColor *highlightAccent = [NSColor colorWithCalibratedRed:0.4588235294 green:0.7254901961 blue:0.9882352941 alpha:1.0];
    _highlightGradient = [[NSGradient alloc] initWithColors:@[
                                                              _highlightBackground,
                                                              highlightAccent,
                                                              _highlightBackground
                                                              ]];
}

- (void)dealloc
{
    CVDisplayLinkRelease(_displayLink);
}

static CVReturn DisplayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp *inNow, const CVTimeStamp *inOutputTime, CVOptionFlags flagsIn, CVOptionFlags *flagsOut, void *displayLinkContext)
{
    CVTimeStamp inNowCopy = *inNow;
    dispatch_async(dispatch_get_main_queue(), ^{
        VLCSliderCell *sliderCell = (__bridge VLCSliderCell*)displayLinkContext;
        [sliderCell displayLink:displayLink tickWithTime:&inNowCopy];
    });
    return kCVReturnSuccess;
}

- (void)displayLink:(CVDisplayLinkRef)displayLink tickWithTime:(const CVTimeStamp*)inNow
{
    if (_lastTime == 0) {
        _deltaToLastFrame = 0;
    } else {
        _deltaToLastFrame = (double)(inNow->videoTime - _lastTime) / inNow->videoTimeScale;
    }
    _lastTime = inNow->videoTime;

    [self.controlView setNeedsDisplay:YES];
}

- (void)initDisplayLink
{
    CVReturn ret = CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    if (ret != kCVReturnSuccess) {
        // TODO: Handle error
        return;
    }
    CVDisplayLinkSetOutputCallback(_displayLink, DisplayLinkCallback, (__bridge void*) self);
}

- (double)normalizedValue:(double)value
{
    double min = [self minValue];
    double max = [self maxValue];

    max -= min;
    value -= min;

    double normalized = value / max;
    if (normalized < 0.0)
        normalized = 0.0;
    else if (normalized > 1.0)
        normalized = 1.0;
    return normalized;
}

- (double)myNormalizedDouble
{
    return [self normalizedValue:[self doubleValue]];
}

/* The knob we draw is as wide as the bar is tall. AppKit's own idea of the
 * knob width (~11 pt) is NOT this one and cannot be overridden through
 * -knobThickness (tried: it changes nothing on the tracking), which is why
 * the seek sliders convert clicks themselves -- see -[VLCSlider mouseDown:].
 * Reported here as well so the filled track and the chapter marks are
 * drawn against the knob that actually exists. */
- (CGFloat)knobThickness
{
    return [[self controlView] bounds].size.height;
}

- (NSRect)knobRectForNormalizedValue:(double)val
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
    // This is our own implementation, so no need to guard it on < 10.9
    NSRect barRect = [self barRectFlipped:NO];
#pragma clang diagnostic pop
    CGFloat knobThickness = barRect.size.height;

    NSRect rect = NSMakeRect((NSWidth(barRect) - knobThickness) * val, 0, knobThickness, knobThickness);
    return [[self controlView] backingAlignedRect:rect options:NSAlignAllEdgesNearest];
}

- (NSRect)knobRectFlipped:(BOOL)flipped
{
    return [self knobRectForNormalizedValue:[self myNormalizedDouble]];
}

- (NSRect)clipEndKnobRect
{
    return [self knobRectForNormalizedValue:[self normalizedValue:_clipEndValue]];
}

#pragma mark -
#pragma mark Normal slider drawing

/* half < 0: only the left half of the disc, half > 0: only the right one.
 * The clip bounds use those so the flat edge sits exactly on the bound and
 * the two handles never cover each other, however close they get. */
+ (NSBezierPath *)knobPathInRect:(NSRect)rect half:(NSInteger)half
{
    if (half == 0)
        return [NSBezierPath bezierPathWithOvalInRect:rect];

    NSPoint center = NSMakePoint(NSMidX(rect), NSMidY(rect));
    CGFloat radius = NSWidth(rect) / 2.0;
    NSBezierPath *path = [NSBezierPath bezierPath];
    /* non-flipped coordinates: 90 = top, 270 = bottom, counterclockwise */
    [path appendBezierPathWithArcWithCenter:center
                                     radius:radius
                                 startAngle:(half < 0 ? 90.0 : 270.0)
                                   endAngle:(half < 0 ? 270.0 : 90.0)];
    [path closePath];
    return path;
}

- (void)drawKnobInRect:(NSRect)knobRect active:(BOOL)active
{
    [self drawKnobInRect:knobRect active:active half:0];
}

- (void)drawKnobInRect:(NSRect)knobRect active:(BOOL)active half:(NSInteger)half
{
    // Draw knob
    NSBezierPath* knobPath = [VLCSliderCell knobPathInRect:NSInsetRect(knobRect, 2.0, 2.0)
                                                      half:half];
    if (active) {
        [_activeKnobFillColor setFill];
    } else {
        [_knobFillColor setFill];
    }

    [knobPath fill];

    [_knobStrokeColor setStroke];
    knobPath.lineWidth = 0.5;

    [NSGraphicsContext saveGraphicsState];
    if (active)
        [_knobShadow set];
    [knobPath stroke];
    [NSGraphicsContext restoreGraphicsState];
}

- (void)drawKnob:(NSRect)knobRect
{
    if (_isKnobHidden)
        return;

    BOOL active = self.isHighlighted
        && (!_clipKnobsActive || _activeClipKnob != 2);
    /* clip start: left half only, so the flat edge marks the bound */
    [self drawKnobInRect:knobRect active:active half:(_clipKnobsActive ? -1 : 0)];
}

- (NSRect)barRectFlipped:(BOOL)flipped
{
    return [[self controlView] bounds];
}

- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped
{
    // Inset rect
    rect = NSInsetRect(rect, 1.0, 1.0);

    rect = [[self controlView] backingAlignedRect:rect options:NSAlignAllEdgesNearest];

    // Empty Track Drawing
    NSBezierPath* emptyTrackPath = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:3 yRadius:3];

    [_trackGradient vlc_safeDrawInBezierPath:emptyTrackPath angle:-90];

    if (_isKnobHidden) {
        [_trackStrokeColor setStroke];
        emptyTrackPath.lineWidth = 1;
        [emptyTrackPath stroke];
        return;
    }

    // Calculate filled track
    NSRect filledTrackRect = rect;
    NSRect knobRect = [self knobRectFlipped:NO];
    filledTrackRect.size.width = knobRect.origin.x + (self.knobThickness / 2);

    if (_clipKnobsActive) {
        // Fill the clip range [start knob .. end knob] instead of [0 .. knob]
        NSRect endKnobRect = [self clipEndKnobRect];
        CGFloat startX = knobRect.origin.x + (self.knobThickness / 2);
        CGFloat endX = endKnobRect.origin.x + (self.knobThickness / 2);
        if (endX < startX)
            endX = startX;
        filledTrackRect.origin.x = startX;
        filledTrackRect.size.width = endX - startX;
    }

    // Filled Track Drawing
    CGFloat filledTrackCornerRadius = 2;
    NSBezierPath* filledTrackPath = [NSBezierPath bezierPathWithRoundedRect:filledTrackRect
                                                                    xRadius:filledTrackCornerRadius
                                                                    yRadius:filledTrackCornerRadius];

    [_filledTrackColor setFill];
    [filledTrackPath fill];

    /* chapter separators, like the Qt seek slider */
    NSUInteger chapterCount = [_chapterFractions count];
    if (chapterCount > 1) {
        CGFloat knobThickness = self.knobThickness;
        [_trackStrokeColor setFill];
        for (NSUInteger i = 1; i < chapterCount; i++) {
            double fraction = [[_chapterFractions objectAtIndex:i] doubleValue];
            if (fraction <= 0. || fraction > 1.)
                continue;
            CGFloat x = NSMinX(rect) + (NSWidth(rect) - knobThickness) * fraction
                + (knobThickness / 2);
            NSRectFill(NSMakeRect(x, NSMinY(rect) + 1.0, 1.0, NSHeight(rect) - 2.0));
        }
    }

    [_trackStrokeColor setStroke];
    emptyTrackPath.lineWidth = 1;
    [emptyTrackPath stroke];
}

#pragma mark -
#pragma mark Clip creation mode drawing

- (void)drawClipExtrasInFrame:(NSRect)cellFrame
{
    if (_isKnobHidden)
        return;

    // Thin marker for the actual playback position, so the user does not
    // lose track of it while both knobs hold the clip bounds.
    NSRect barRect = [[self controlView] bounds];
    CGFloat knobThickness = barRect.size.height;
    double markerVal = [self normalizedValue:_playbackMarkerValue];
    /* the playback can sit slightly outside the bounds (the end-of-clip
     * pause lands a few frames past the end knob): keep the marker cut
     * by the knob centers, where the clip logically starts and ends */
    double startVal = [self normalizedValue:[self doubleValue]];
    double endVal = [self normalizedValue:_clipEndValue];
    if (markerVal < startVal)
        markerVal = startVal;
    else if (markerVal > endVal)
        markerVal = endVal;
    CGFloat markerX = (NSWidth(barRect) - knobThickness) * markerVal
        + (knobThickness / 2);
    NSRect markerRect = NSMakeRect(markerX - 1.0, NSMinY(barRect) + 2.0,
                                   2.0, NSHeight(barRect) - 4.0);
    [_highlightBackground setFill];
    [[NSBezierPath bezierPathWithRoundedRect:markerRect xRadius:1.0 yRadius:1.0] fill];

    BOOL endActive = self.isHighlighted && _activeClipKnob == 2;
    /* clip end: right half only (see -drawKnob:) */
    [self drawKnobInRect:[self clipEndKnobRect] active:endActive half:1];
}

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    if (_indefinite)
        return [self drawAnimationInRect:cellFrame];

    [super drawWithFrame:cellFrame inView:controlView];

    if (_clipKnobsActive)
        [self drawClipExtrasInFrame:cellFrame];
}

#pragma mark -
#pragma mark Indefinite slider drawing


- (void)drawHighlightInRect:(NSRect)rect
{
    [_highlightGradient drawInRect:rect angle:0];
}


- (void)drawHighlightBackgroundInRect:(NSRect)rect
{
    rect = NSInsetRect(rect, 1.0, 1.0);
    NSBezierPath *fullPath = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2.0 yRadius:2.0];
    [_highlightBackground setFill];
    [fullPath fill];
}

- (void)drawAnimationInRect:(NSRect)rect
{
    [self drawHighlightBackgroundInRect:rect];

    [NSGraphicsContext saveGraphicsState];
    rect = NSInsetRect(rect, 1.0, 1.0);
    NSBezierPath *fullPath = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:2.0 yRadius:2.0];
    [fullPath setClip];

    // Use previously calculated position
    rect.origin.x = _animationPosition;

    // Calculate new position for next Frame
    if (_animationPosition < (rect.size.width + _animationWidth)) {
        _animationPosition += (rect.size.width + _animationWidth) * _deltaToLastFrame;
    } else {
        _animationPosition = -(_animationWidth);
    }

    rect.size.width = _animationWidth;


    [self drawHighlightInRect:rect];
    [NSGraphicsContext restoreGraphicsState];
    _deltaToLastFrame = 0;
}


#pragma mark -
#pragma mark Animation handling

- (void)beginAnimating
{
    CVReturn err = CVDisplayLinkStart(_displayLink);
    if (err != kCVReturnSuccess) {
        // TODO: Handle error
    }
    _animationPosition = -(_animationWidth);
    [self setEnabled:NO];
}

- (void)endAnimating
{
    CVDisplayLinkStop(_displayLink);
    [self setEnabled:YES];

}

- (void)setIndefinite:(BOOL)indefinite
{
    if (_indefinite == indefinite)
        return;

    if (indefinite)
        [self beginAnimating];
    else
        [self endAnimating];
    _indefinite = indefinite;
}

- (void)setKnobHidden:(BOOL)isKnobHidden
{
    _isKnobHidden = isKnobHidden;
    [self.controlView setNeedsDisplay:YES];
}


@end
