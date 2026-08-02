/*****************************************************************************
 * VLCLegacyControls.m: shared custom controls for the legacy interface
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

#import "VLCLegacyControls.h"
#import "misc.h"

static BOOL b_legacy_dark = NO;

BOOL VLCLegacyDarkMode(void)
{
    return b_legacy_dark;
}

void VLCLegacySetDarkMode(BOOL dark)
{
    b_legacy_dark = dark;
}

NSColor *VLCLegacyTextColor(void)
{
    return b_legacy_dark
        ? [NSColor colorWithCalibratedWhite:0.90 alpha:1.0]
        : [NSColor colorWithCalibratedWhite:0.22 alpha:1.0];
}

NSColor *VLCLegacySecondaryTextColor(void)
{
    return b_legacy_dark
        ? [NSColor colorWithCalibratedWhite:0.60 alpha:1.0]
        : [NSColor colorWithCalibratedWhite:0.45 alpha:1.0];
}

NSColor *VLCLegacyTableBackgroundColor(void)
{
    return b_legacy_dark
        ? [NSColor colorWithCalibratedWhite:0.16 alpha:1.0]
        : [NSColor whiteColor];
}

NSColor *VLCLegacySidebarBackgroundColor(void)
{
    return b_legacy_dark
        ? [NSColor colorWithCalibratedWhite:0.12 alpha:1.0]
        : [NSColor colorWithCalibratedRed:0.836 green:0.858 blue:0.886
                                    alpha:1.0];
}

NSImage *VLCLegacyImage(NSString *name)
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *path = [bundle pathForResource:name ofType:@"png"];
    if (!path)
        path = [bundle pathForResource:name ofType:@"pdf"];
    if (!path)
        return nil;
    return [[[NSImage alloc] initWithContentsOfFile:path] autorelease];
}

NSImage *VLCLegacyImageSized(NSString *name, NSSize size)
{
    NSImage *image = VLCLegacyImage(name);
    [image setSize:size];
    return image;
}

NSColor *VLCLegacyGlyphColor(void)
{
    return [NSColor colorWithCalibratedWhite:0.36 alpha:1.0];
}

NSImage *VLCLegacyTintedImage(NSString *name, NSSize size, NSColor *color)
{
    NSImage *source = VLCLegacyImage(name);
    if (!source)
        return nil;
    [source setSize:size];
    NSImage *result = [[[NSImage alloc] initWithSize:size] autorelease];
    [result lockFocus];
    [source drawInRect:NSMakeRect(0, 0, size.width, size.height)
              fromRect:NSZeroRect
             operation:NSCompositeSourceOver
              fraction:1.0f];
    [color set];
    NSRectFillUsingOperation(NSMakeRect(0, 0, size.width, size.height),
                             NSCompositeSourceAtop);
    [result unlockFocus];
    return result;
}

NSBezierPath *VLCLegacyRoundedRectPath(NSRect rect, float radius)
{
    NSBezierPath *path = [NSBezierPath bezierPath];
    float maxRadius = (rect.size.width < rect.size.height
                       ? rect.size.width : rect.size.height) / 2.0f;
    if (radius > maxRadius)
        radius = maxRadius;
    if (radius <= 0.0f) {
        [path appendBezierPathWithRect:rect];
        return path;
    }
    NSRect inner = NSInsetRect(rect, radius, radius);
    [path appendBezierPathWithArcWithCenter:
        NSMakePoint(NSMinX(inner), NSMinY(inner))
        radius:radius startAngle:180 endAngle:270];
    [path appendBezierPathWithArcWithCenter:
        NSMakePoint(NSMaxX(inner), NSMinY(inner))
        radius:radius startAngle:270 endAngle:360];
    [path appendBezierPathWithArcWithCenter:
        NSMakePoint(NSMaxX(inner), NSMaxY(inner))
        radius:radius startAngle:0 endAngle:90];
    [path appendBezierPathWithArcWithCenter:
        NSMakePoint(NSMinX(inner), NSMaxY(inner))
        radius:radius startAngle:90 endAngle:180];
    [path closePath];
    return path;
}

NSImage *VLCLegacyStopGlyph(NSSize size, NSColor *color)
{
    NSImage *result = [[[NSImage alloc] initWithSize:size] autorelease];
    [result lockFocus];
    [color set];
    [VLCLegacyRoundedRectPath(
        NSMakeRect(size.width * 0.15f, size.height * 0.15f,
                   size.width * 0.7f, size.height * 0.7f), 1.5f) fill];
    [result unlockFocus];
    return result;
}

NSImage *VLCLegacyListGlyph(NSSize size, NSColor *color)
{
    NSImage *result = [[[NSImage alloc] initWithSize:size] autorelease];
    [result lockFocus];
    [color set];
    int i;
    for (i = 0; i < 3; i++)
        NSRectFill(NSMakeRect(size.width * 0.1f,
                              size.height * (0.2f + 0.25f * i),
                              size.width * 0.8f,
                              size.height * 0.12f));
    [result unlockFocus];
    return result;
}

NSButton *VLCLegacyImageButton(NSView *parent, NSString *imageName,
                               NSString *alternateImageName, NSRect frame,
                               id target, SEL action)
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setButtonType:NSMomentaryChangeButton];
    [button setBordered:NO];
    NSImage *image = VLCLegacyImage(imageName);
    if (image) {
        [image setSize:frame.size];
        [button setImage:image];
    }
    if (alternateImageName) {
        NSImage *alternate = VLCLegacyImage(alternateImageName);
        if (alternate) {
            [alternate setSize:frame.size];
            [button setAlternateImage:alternate];
        }
    }
    if ([[button cell] respondsToSelector:@selector(setImageDimsWhenDisabled:)])
        [[button cell] setImageDimsWhenDisabled:YES];
    [button setTarget:target];
    [button setAction:action];
    [parent addSubview:button];
    return button;
}

/*****************************************************************************
 * VLCLegacyBottomBarView
 *****************************************************************************/

@implementation VLCLegacyBottomBarView

- (BOOL)isOpaque
{
    return YES;
}

/* Every fill below is intersected with dirtyRect before painting.  The
 * output is pixel-identical (AppKit clips drawRect: to the dirty region
 * anyway), but a partial repaint — the once-a-second time label tick or
 * a slider knob move dirties only a small strip of the bar — no longer
 * allocates 24 NSColors and pushes 24 full-width fills through the
 * clipper on a G4. */
- (void)drawRect:(NSRect)dirtyRect
{
    NSRect bounds = [self bounds];
    NSRect r;

    if (VLCLegacyDarkMode()) {
        /* Tile the 2.x/3.0 dark bottom bar artwork */
        NSImage *tile = VLCLegacyImage(@"bottom-background_dark");
        if (tile) {
            NSSize size = [tile size];
            float x;
            for (x = 0; x < bounds.size.width; x += size.width) {
                NSRect dest = NSMakeRect(bounds.origin.x + x,
                                         bounds.origin.y,
                                         size.width, bounds.size.height);
                if (!NSIntersectsRect(dest, dirtyRect))
                    continue;
                [tile drawInRect:dest
                        fromRect:NSZeroRect
                       operation:NSCompositeSourceOver
                        fraction:1.0f];
            }
        } else {
            r = NSIntersectionRect(bounds, dirtyRect);
            if (!NSIsEmptyRect(r)) {
                [[NSColor colorWithCalibratedWhite:0.15 alpha:1.0] set];
                NSRectFill(r);
            }
        }
        r = NSIntersectionRect(NSMakeRect(bounds.origin.x,
                                          NSMaxY(bounds) - 1.0f,
                                          bounds.size.width, 1.0f),
                               dirtyRect);
        if (!NSIsEmptyRect(r)) {
            [[NSColor blackColor] set];
            NSRectFill(r);
        }
        return;
    }

    /* Light gradient, top (lighter) to bottom, like VLCBottomBarView */
    const float topWhite = 0.965f, bottomWhite = 0.835f;
    const int steps = 24;
    int i;
    for (i = 0; i < steps; i++) {
        /* view is not flipped: slice 0 is at the bottom; slices overlap
         * by 1 px and later slices win, an order the intersection keeps */
        r = NSIntersectionRect(NSMakeRect(bounds.origin.x,
                                          bounds.origin.y
                                              + bounds.size.height * i / steps,
                                          bounds.size.width,
                                          bounds.size.height / steps + 1.0f),
                               dirtyRect);
        if (NSIsEmptyRect(r))
            continue;
        float fraction = (float)i / (float)(steps - 1);
        [[NSColor colorWithCalibratedWhite:
            bottomWhite + (topWhite - bottomWhite) * fraction alpha:1.0] set];
        NSRectFill(r);
    }

    /* hairline separator on top */
    r = NSIntersectionRect(NSMakeRect(bounds.origin.x, NSMaxY(bounds) - 1.0f,
                                      bounds.size.width, 1.0f),
                           dirtyRect);
    if (!NSIsEmptyRect(r)) {
        [[NSColor colorWithCalibratedWhite:0.62f alpha:1.0] set];
        NSRectFill(r);
    }
}

@end

/*****************************************************************************
 * VLCLegacyImageSliderCell
 *****************************************************************************/

@implementation VLCLegacyImageSliderCell

- (void)setBarImage:(NSImage *)bar knobImage:(NSImage *)knob
{
    [bar retain];
    [barImage release];
    barImage = bar;
    [knob retain];
    [knobImage release];
    knobImage = knob;
}

- (void)dealloc
{
    [barImage release];
    [knobImage release];
    [super dealloc];
}

- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped
{
    if (!barImage)
        return;
    NSSize size = [barImage size];
    [barImage drawInRect:NSMakeRect(rect.origin.x,
                                    rect.origin.y
                                        + (rect.size.height
                                           - size.height) / 2,
                                    rect.size.width, size.height)
                fromRect:NSZeroRect
               operation:NSCompositeSourceOver
                fraction:1.0f];
}

- (void)drawKnob:(NSRect)knobRect
{
    if (!knobImage)
        return;
    NSSize size = [knobImage size];
    [knobImage drawInRect:NSMakeRect(knobRect.origin.x
                                         + (knobRect.size.width
                                            - size.width) / 2,
                                     knobRect.origin.y
                                         + (knobRect.size.height
                                            - size.height) / 2,
                                     size.width, size.height)
                 fromRect:NSZeroRect
                operation:NSCompositeSourceOver
                 fraction:1.0f];
}

@end

/*****************************************************************************
 * VLCLegacyProgressSliderCell
 *****************************************************************************/

@implementation VLCLegacyProgressSliderCell

- (id)init
{
    if (self = [super init])
        knobInset = 2.0f;
    return self;
}

- (void)setKnobInset:(float)inset { knobInset = inset; }
- (void)setVolumeStyle:(BOOL)volume { volumeStyle = volume; }
- (void)setAlwaysDark:(BOOL)dark { alwaysDark = dark; }
- (void)setIndefinite:(BOOL)flag { indefinite = flag; }
- (BOOL)indefinite { return indefinite; }

- (BOOL)isDark
{
    return alwaysDark || VLCLegacyDarkMode();
}

/* The time slider track fills the whole control, like VLCSliderCell;
 * the volume slider keeps the default thin track, like
 * VLCVolumeSliderCell (that is what makes it look like a line). */
- (NSRect)barRectFlipped:(BOOL)flipped
{
    if (volumeStyle) {
        /* -[NSSliderCell barRectFlipped:] does NOT exist before 10.7 (modern
         * SDKs declare it 10.9+). An #if on MAC_OS_X_VERSION_MAX_ALLOWED is
         * NOT enough, because that tests the SDK, not the running system: the
         * x86_64 slice is built against a current SDK yet has to run on
         * 10.5/10.6, where calling super raises "unrecognized selector" and
         * aborts the app at launch (crash seen on 10.6.8, MacBook2,1 — the
         * i386 slice escaped it only because it is built against the 10.4 SDK).
         * Ask the RUNTIME instead. Testing NSSliderCell (not self) is what
         * makes this correct: it looks at AppKit's own method list, not at
         * this subclass's override. */
#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
        if ([NSSliderCell instancesRespondToSelector:@selector(barRectFlipped:)]) {
# ifdef __clang__
#  pragma clang diagnostic push
#  pragma clang diagnostic ignored "-Wunguarded-availability"
# endif
            return [super barRectFlipped:flipped];
# ifdef __clang__
#  pragma clang diagnostic pop
# endif
        }
#endif
        /* 10.4-10.6 (or an SDK that does not declare it): approximate the
         * default thin track — a centered 5px lane. */
        NSRect bounds = [[self controlView] bounds];
        return NSMakeRect(bounds.origin.x + 2.0f,
                          bounds.origin.y
                              + (float)floor((bounds.size.height - 5.0f) / 2.0f),
                          bounds.size.width - 4.0f, 5.0f);
    }
    return [[self controlView] bounds];
}

/* The knob is computed from the control bounds so the circle is exactly
 * centered vertically (the default NSSliderCell rect is not, with our
 * custom bars). The volume knob is deliberately smaller than the 100%
 * tick so the mark stays visible above and below it. */
- (float)knobDiameter
{
    NSRect bounds = [[self controlView] bounds];
    if (volumeStyle)
        return 11.0f;
    float diameter = bounds.size.height - 6.0f;
    if (diameter < 9.0f)
        diameter = 9.0f;
    return diameter;
}

- (NSRect)knobRectFlipped:(BOOL)flipped
{
    NSRect bounds = [[self controlView] bounds];
    float diameter = [self knobDiameter];
    double range = [self maxValue] - [self minValue];
    float fraction = range > 0
        ? (float)(([self doubleValue] - [self minValue]) / range) : 0.0f;
    if (fraction < 0.0f)
        fraction = 0.0f;
    else if (fraction > 1.0f)
        fraction = 1.0f;
    return NSMakeRect(bounds.origin.x
                          + fraction * (bounds.size.width - diameter),
                      bounds.origin.y
                          + (float)floor((bounds.size.height - diameter)
                                         / 2.0f),
                      diameter, diameter);
}

/* NSGradient is 10.5+; approximate the vertical track gradient with
 * clipped horizontal strips (indistinguishable at ~20 px tall) */
static void drawVerticalGradient(NSBezierPath *path, NSRect rect,
                                 float topWhite, float bottomWhite,
                                 BOOL flipped)
{
    [NSGraphicsContext saveGraphicsState];
    [path addClip];
    const int steps = 16;
    float stripHeight = rect.size.height / steps;
    int i;
    for (i = 0; i < steps; i++) {
        float t = (float)i / (steps - 1);   /* 0 = visual top */
        float y = flipped
            ? rect.origin.y + i * stripHeight
            : NSMaxY(rect) - (i + 1) * stripHeight;
        [[NSColor colorWithCalibratedWhite:
            topWhite + (bottomWhite - topWhite) * t alpha:1.0f] set];
        NSRectFill(NSMakeRect(rect.origin.x, y,
                              rect.size.width, stripHeight + 1.0f));
    }
    [NSGraphicsContext restoreGraphicsState];
}

/* exact palette of VLCSliderCell / VLCVolumeSliderCell (3.0, aqua+dark) */
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped
{
    /* 10.4's AppKit computes the incoming rect internally without asking
     * -barRectFlipped:; recompute it so the geometry matches everywhere.
     * This calls our OWN override (see above), which falls back to a computed
     * rect when AppKit has no barRectFlipped: — so it is safe on 10.4-10.6. */
#ifdef __clang__
# pragma clang diagnostic push
# pragma clang diagnostic ignored "-Wunguarded-availability"
#endif
    rect = [self barRectFlipped:flipped];
#ifdef __clang__
# pragma clang diagnostic pop
#endif
    BOOL dark = [self isDark];
    rect = NSInsetRect(rect, 1.0f, 1.0f);
    float radius = volumeStyle ? 1.0f : 3.0f;

    NSBezierPath *emptyTrack = VLCLegacyRoundedRectPath(rect, radius);

    if (indefinite) {
        /* buffering: the animated blue band of VLCSliderCell */
        [[NSColor colorWithCalibratedRed:0.20f green:0.55f blue:0.91f
                                   alpha:1.0f] set];
        [emptyTrack fill];

        [NSGraphicsContext saveGraphicsState];
        [emptyTrack addClip];
        const float bandWidth = 60.0f;
        if (animationPosition < rect.size.width + bandWidth)
            animationPosition += (rect.size.width + bandWidth) / 12.0f;
        else
            animationPosition = -bandWidth;
        [[NSColor colorWithCalibratedRed:0.459f green:0.725f blue:0.988f
                                   alpha:1.0f] set];
        [VLCLegacyRoundedRectPath(
            NSMakeRect(rect.origin.x + animationPosition, rect.origin.y,
                       bandWidth, rect.size.height), radius) fill];
        [NSGraphicsContext restoreGraphicsState];
        return;
    }

    if (dark)
        drawVerticalGradient(emptyTrack, rect, 0.24f, 0.15f, flipped);
    else
        drawVerticalGradient(emptyTrack, rect, 0.663f, 0.749f, flipped);

    /* Filled portion, up to the middle of the knob. Clipped to the
     * track: its smaller corner radius otherwise pokes a few pixels
     * outside the track's rounded left corner. */
    NSRect knobRect = [self knobRectFlipped:flipped];
    NSRect filled = rect;
    filled.size.width = knobRect.origin.x + knobRect.size.width / 2
                      - rect.origin.x;
    if (filled.size.width > 3.0f) {
        [NSGraphicsContext saveGraphicsState];
        [emptyTrack addClip];
        NSBezierPath *filledTrack = VLCLegacyRoundedRectPath(filled, 2.0f);
        [(dark ? [NSColor colorWithCalibratedWhite:0.15f alpha:1.0f]
               : [NSColor colorWithCalibratedWhite:0.55f alpha:1.0f]) set];
        [filledTrack fill];
        [NSGraphicsContext restoreGraphicsState];
    }

    [(dark
        ? [NSColor colorWithCalibratedWhite:0.23f alpha:1.0f]
        : [NSColor colorWithCalibratedRed:0.619f green:0.624f blue:0.623f
                                    alpha:1.0f]) set];
    [emptyTrack setLineWidth:1.0f];
    [emptyTrack stroke];

    if (volumeStyle) {
        /* the 100% mark warning against saturation (the slider itself
         * goes up to 125%, like macosx-max-volume) */
        double range = [self maxValue] - [self minValue];
        if (range > 0 && [self maxValue] > 1.0) {
            float fraction = (float)((1.0 - [self minValue]) / range);
            /* same mapping as knobRectFlipped:, so at exactly 100% the
             * circle is CROSSED by the mark, not next to it */
            NSRect cell = [[self controlView] bounds];
            float diameter = [self knobDiameter];
            float x = (float)floor(cell.origin.x
                    + fraction * (cell.size.width - diameter)
                    + diameter / 2.0f) + 0.5f;
            /* taller than the 11 px knob, so the mark peeks out above
             * and below the circle sitting on it */
            float tickHeight = 13.0f;
            [(dark
                ? [NSColor colorWithCalibratedWhite:0.55f alpha:1.0f]
                : [NSColor colorWithCalibratedWhite:0.45f alpha:1.0f]) set];
            [NSBezierPath strokeLineFromPoint:
                    NSMakePoint(x, NSMidY(cell) - tickHeight / 2)
                                      toPoint:
                    NSMakePoint(x, NSMidY(cell) + tickHeight / 2)];
        }
    }
}

/* NSSliderCell only invalidates the knob area while tracking: without a
 * full redraw the filled portion and the tick lag until mouse-up */
- (void)snapVolume
{
    if (!volumeStyle)
        return;
    double value = [self doubleValue];
    if (value > 0.93 && value < 1.07 && value != 1.0)
        [self setDoubleValue:1.0];
}

- (BOOL)startTrackingAt:(NSPoint)startPoint inView:(NSView *)controlView
{
    BOOL result = [super startTrackingAt:startPoint inView:controlView];
    [self snapVolume];
    [controlView setNeedsDisplay:YES];
    return result;
}

- (BOOL)continueTracking:(NSPoint)lastPoint at:(NSPoint)currentPoint
                  inView:(NSView *)controlView
{
    BOOL result = [super continueTracking:lastPoint at:currentPoint
                                   inView:controlView];
    [self snapVolume];
    [controlView setNeedsDisplay:YES];
    return result;
}

- (void)stopTracking:(NSPoint)lastPoint at:(NSPoint)stopPoint
              inView:(NSView *)controlView mouseIsUp:(BOOL)flag
{
    [super stopTracking:lastPoint at:stopPoint inView:controlView
              mouseIsUp:flag];
    [self snapVolume];
    [controlView setNeedsDisplay:YES];
}

- (void)drawKnob:(NSRect)knobRect
{
    if (indefinite)
        return;
    BOOL dark = [self isDark];
    /* knobRectFlipped: already returns the final circle */
    NSBezierPath *knob = [NSBezierPath bezierPathWithOvalInRect:
        NSInsetRect(knobRect, 0.5f, 0.5f)];

    NSColor *fill;
    NSColor *stroke;
    if (dark && volumeStyle) {
        fill = [self isHighlighted]
            ? [NSColor colorWithCalibratedWhite:0.95f alpha:1.0f]
            : [NSColor colorWithCalibratedWhite:0.70f alpha:1.0f];
        stroke = [NSColor blackColor];
    } else {
        fill = [self isHighlighted]
            ? [NSColor colorWithCalibratedWhite:0.95f alpha:1.0f]
            : [NSColor whiteColor];
        stroke = [NSColor colorWithCalibratedRed:0.592f green:0.596f
                                            blue:0.596f alpha:1.0f];
    }
    [fill set];
    [knob fill];
    [stroke set];
    [knob setLineWidth:0.5f];
    [knob stroke];
}

@end
