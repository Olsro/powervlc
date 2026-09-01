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
#import "VLCLegacyCoreInteraction.h"
#import "misc.h"

#include <vlc_common.h>
#include <vlc_input.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

static BOOL b_legacy_dark = NO;

extern VLCLegacyCoreInteraction *VLCLegacyGetCore(void);

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

    /* Light gradient, top (lighter) to bottom, like VLCBottomBarView.
     *
     * Les bornes des tranches sont arrondies au pixel. 24 tranches sur une
     * barre d'environ 38 px donnent 1,58 px chacune : les bords tombaient au
     * MILIEU d'un pixel, et un NSRectFill à bord fractionnaire ne prend pas le
     * blit entier — il part dans le rastériseur anti-aliasé. Arrondies, les
     * tranches pavent exactement la barre (1 ou 2 px, plus de recouvrement
     * d'1 px à départager) et chaque remplissage retombe sur le chemin entier.
     *
     * ⚠⚠ NE PAS EN ATTENDRE PLUS QUE ÇA — mesuré, ce n'est PAS un levier de
     * performance. Le profil `sample` du thread principal sur l'iBook G3
     * (ppc750 700 MHz) pendant une lecture H.264 accusait `aa_render` à 4 522
     * échantillons sur 12 000, ce qui laissait croire au poste le plus lourd
     * de l'interface. C'était du TEMPS MURAL sur un fil préempté, pas du temps
     * CPU : l'A/B au chronomètre (2 runs par branche, 140 s de lecture, cache
     * de greffons chaud) donne 108,1 s de CPU avant et 107,5 s après, soit
     * 0,6 % — l'écart entre les deux runs de référence est déjà de 0,4 %.
     * C'est cohérent : la barre n'est redessinée qu'une fois par seconde sous
     * ≤10.3 (voir le timer dans VLCLegacyMainWindow), donc même un redessin
     * coûteux ne peut pas peser. Conservé parce que c'est gratuit et que
     * l'aspect est identique (relevé colonne par colonne : au plus 1/255
     * d'écart sur 3 rangées de 35), pas parce que ça rapporte. */
    const float topWhite = 0.965f, bottomWhite = 0.835f;
    const int steps = 24;
    const float base = floorf(NSMinY(bounds) + 0.5f);
    const float span = bounds.size.height;
    int i;
    for (i = 0; i < steps; i++) {
        /* view is not flipped: slice 0 is at the bottom */
        float y0 = floorf(span * i / steps + 0.5f);
        float y1 = floorf(span * (i + 1) / steps + 0.5f);
        if (y1 <= y0)
            continue;           /* tranche plus fine qu'un pixel */
        r = NSIntersectionRect(NSMakeRect(bounds.origin.x, base + y0,
                                          bounds.size.width, y1 - y0),
                               dirtyRect);
        if (NSIsEmptyRect(r))
            continue;
        float fraction = (float)i / (float)(steps - 1);
        [[NSColor colorWithCalibratedWhite:
            bottomWhite + (topWhite - bottomWhite) * fraction alpha:1.0] set];
        NSRectFill(r);
    }

    /* hairline separator on top */
    r = NSIntersectionRect(NSMakeRect(bounds.origin.x,
                                      floorf(NSMaxY(bounds) + 0.5f) - 1.0f,
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

- (void)dealloc
{
    [chapterFractions release];
    [chapterNames release];
    [bookmarkFractions release];
    [bookmarkNames release];
    [bookmarkTimes release];
    [super dealloc];
}

- (void)setChapterFractions:(NSArray *)fractions names:(NSArray *)names
{
    if (fractions != chapterFractions) {
        [chapterFractions release];
        chapterFractions = [fractions retain];
    }
    if (names != chapterNames) {
        [chapterNames release];
        chapterNames = [names retain];
    }
}
- (NSArray *)chapterFractions { return chapterFractions; }
- (NSArray *)chapterNames { return chapterNames; }

- (void)setBookmarkFractions:(NSArray *)fractions names:(NSArray *)names
                       times:(NSArray *)newTimes
{
    if (fractions != bookmarkFractions) {
        [bookmarkFractions release];
        bookmarkFractions = [fractions retain];
    }
    if (names != bookmarkNames) {
        [bookmarkNames release];
        bookmarkNames = [names retain];
    }
    if (newTimes != bookmarkTimes) {
        [bookmarkTimes release];
        bookmarkTimes = [newTimes retain];
    }
}
- (NSArray *)bookmarkFractions { return bookmarkFractions; }
- (NSArray *)bookmarkNames { return bookmarkNames; }
- (NSArray *)bookmarkTimes { return bookmarkTimes; }

- (void)setClipKnobsActive:(BOOL)active { clipKnobsActive = active; }
- (BOOL)clipKnobsActive { return clipKnobsActive; }
- (void)setClipEndValue:(double)value { clipEndValue = value; }
- (double)clipEndValue { return clipEndValue; }
- (void)setPlaybackMarkerValue:(double)value { playbackMarkerValue = value; }
- (double)playbackMarkerValue { return playbackMarkerValue; }
- (void)setActiveClipKnob:(int)knob { activeClipKnob = knob; }
- (int)activeClipKnob { return activeClipKnob; }

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

- (NSRect)knobRectForFraction:(float)fraction
{
    NSRect bounds = [[self controlView] bounds];
    float diameter = [self knobDiameter];
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

- (float)normalizedFraction:(double)value
{
    double range = [self maxValue] - [self minValue];
    return range > 0 ? (float)((value - [self minValue]) / range) : 0.0f;
}

- (NSRect)knobRectFlipped:(BOOL)flipped
{
    return [self knobRectForFraction:
        [self normalizedFraction:[self doubleValue]]];
}

- (NSRect)clipEndKnobRect
{
    return [self knobRectForFraction:[self normalizedFraction:clipEndValue]];
}

/* NSGradient is 10.5+; approximate the vertical track gradient with
 * clipped horizontal strips (indistinguishable at ~20 px tall) */
static void drawVerticalGradient(NSBezierPath *path, NSRect rect,
                                 float topWhite, float bottomWhite,
                                 BOOL flipped)
{
    /* ★★★ COULEURS EN ESPACE PÉRIPHÉRIQUE, ET MISES EN CACHE (2026-08-05).
     * `colorWithCalibratedWhite:` fait passer CHAQUE bande par ColorSync à
     * CHAQUE redessin : le profil `sample` d'une lecture DVD sur l'iBook G3
     * montrait `CMMProcessColors` / `CWMatchColors` sous `NSRectFill`, et la
     * descente d'affichage AppKit occupait ~20 %% du temps du fil principal —
     * pour un simple curseur de progression, qui se redessine plusieurs fois
     * par seconde pendant toute la lecture.
     * `colorWithDeviceWhite:` évite la correspondance de couleurs (un gris
     * reste un gris), et le cache évite 16 allocations d'objets par redessin.
     * Rendu visuellement identique sur ces machines. */
    static NSColor *s_cache[2][16];
    static float    s_key[2] = { -1.0f, -1.0f };
    const int steps = 16;
    int slot = (s_key[0] == topWhite) ? 0 : (s_key[1] == topWhite) ? 1 : -1;
    if (slot < 0) {
        slot = (s_key[0] < 0.0f) ? 0 : 1;
        for (int k = 0; k < steps; k++) {
            float t = (float)k / (steps - 1);
            [s_cache[slot][k] release];
            s_cache[slot][k] = [[NSColor colorWithDeviceWhite:
                topWhite + (bottomWhite - topWhite) * t alpha:1.0f] retain];
        }
        s_key[slot] = topWhite;
    }

    [NSGraphicsContext saveGraphicsState];
    [path addClip];
    float stripHeight = rect.size.height / steps;
    int i;
    for (i = 0; i < steps; i++) {
        float y = flipped
            ? rect.origin.y + i * stripHeight
            : NSMaxY(rect) - (i + 1) * stripHeight;
        [s_cache[slot][i] set];
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
    if (clipKnobsActive && !volumeStyle) {
        /* fill the clip range [start knob .. end knob] instead */
        NSRect endKnobRect = [self clipEndKnobRect];
        float startX = knobRect.origin.x + knobRect.size.width / 2.0f;
        float endX = endKnobRect.origin.x + endKnobRect.size.width / 2.0f;
        if (endX < startX)
            endX = startX;
        filled.origin.x = startX;
        filled.size.width = endX - startX;
    }
    if (filled.size.width > 3.0f) {
        [NSGraphicsContext saveGraphicsState];
        [emptyTrack addClip];
        NSBezierPath *filledTrack = VLCLegacyRoundedRectPath(filled, 2.0f);
        [(dark ? [NSColor colorWithCalibratedWhite:0.15f alpha:1.0f]
               : [NSColor colorWithCalibratedWhite:0.55f alpha:1.0f]) set];
        [filledTrack fill];
        [NSGraphicsContext restoreGraphicsState];
    }

    /* chapter separators, before the border stroke so they never sit on
     * top of it; positioned with the knob-center mapping so each mark is
     * exactly where the knob lands when seeking to that chapter */
    if (!volumeStyle && [chapterFractions count] > 1) {
        NSRect cellBounds = [[self controlView] bounds];
        float diameter = [self knobDiameter];
        [(dark
            ? [NSColor colorWithDeviceWhite:0.45f alpha:1.0f]
            : [NSColor colorWithDeviceWhite:0.42f alpha:1.0f]) set];
        [NSGraphicsContext saveGraphicsState];
        [emptyTrack addClip];
        unsigned int chapterIndex;
        for (chapterIndex = 0; chapterIndex < [chapterFractions count];
             chapterIndex++) {
            float fraction = [[chapterFractions objectAtIndex:chapterIndex]
                                 floatValue];
            if (fraction <= 0.0f || fraction >= 1.0f)
                continue;
            float x = cellBounds.origin.x
                    + fraction * (cellBounds.size.width - diameter)
                    + diameter / 2.0f;
            NSRectFill(NSMakeRect((float)floor(x), rect.origin.y + 1.0f,
                                  1.0f, rect.size.height - 2.0f));
        }
        [NSGraphicsContext restoreGraphicsState];
    }

    /* Bookmarks deliberately stand out from the neutral chapter ticks. */
    if (!volumeStyle && [bookmarkFractions count] > 0) {
        NSRect cellBounds = [[self controlView] bounds];
        float diameter = [self knobDiameter];
        [[NSColor colorWithDeviceRed:0.94f green:0.36f blue:0.10f
                               alpha:1.0f] set];
        [NSGraphicsContext saveGraphicsState];
        [emptyTrack addClip];
        unsigned int bookmarkIndex;
        for (bookmarkIndex = 0;
             bookmarkIndex < [bookmarkFractions count]; bookmarkIndex++) {
            float fraction = [[bookmarkFractions objectAtIndex:bookmarkIndex]
                                 floatValue];
            if (fraction < 0.0f || fraction > 1.0f)
                continue;
            float x = cellBounds.origin.x
                    + fraction * (cellBounds.size.width - diameter)
                    + diameter / 2.0f;
            NSRectFill(NSMakeRect((float)floor(x) - 2.0f,
                                  rect.origin.y + 1.0f,
                                  4.0f, rect.size.height - 2.0f));
        }
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
    /* in clip creation mode the start bound is drawn as the LEFT half of
     * the disc (see -drawKnobInRect:half:) */
    [self drawKnobInRect:knobRect
                    half:(clipKnobsActive && !volumeStyle) ? -1 : 0];
}

/* half < 0: only the left half of the disc, half > 0: only the right one.
 * The clip bounds use those so the flat edge sits exactly on the bound and
 * the two handles never cover each other, however close they get. */
- (void)drawKnobInRect:(NSRect)knobRect half:(int)half
{
    if (indefinite)
        return;
    BOOL dark = [self isDark];
    /* knobRectFlipped: already returns the final circle */
    NSRect discRect = NSInsetRect(knobRect, 0.5f, 0.5f);
    NSBezierPath *knob;
    if (half == 0) {
        knob = [NSBezierPath bezierPathWithOvalInRect:discRect];
    } else {
        NSPoint center = NSMakePoint(discRect.origin.x
                                         + discRect.size.width / 2.0f,
                                     discRect.origin.y
                                         + discRect.size.height / 2.0f);
        knob = [NSBezierPath bezierPath];
        /* non-flipped coordinates: 90 = top, 270 = bottom, ccw */
        [knob appendBezierPathWithArcWithCenter:center
                                         radius:discRect.size.width / 2.0f
                                     startAngle:(half < 0 ? 90.0f : 270.0f)
                                       endAngle:(half < 0 ? 270.0f : 90.0f)];
        [knob closePath];
    }

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

- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
    [super drawWithFrame:cellFrame inView:controlView];

    if (!clipKnobsActive || volumeStyle || indefinite)
        return;

    /* thin marker for the actual playback position, so the user does not
     * lose track of it while both knobs hold the clip bounds */
    NSRect bounds = [controlView bounds];
    float diameter = [self knobDiameter];
    float fraction = [self normalizedFraction:playbackMarkerValue];
    /* the playback can sit slightly outside the bounds (the end-of-clip
     * pause lands a few frames past the end knob): keep the marker cut
     * by the knob centers, where the clip logically starts and ends */
    float startFraction = [self normalizedFraction:[self doubleValue]];
    float endFraction = [self normalizedFraction:clipEndValue];
    if (fraction < startFraction)
        fraction = startFraction;
    else if (fraction > endFraction)
        fraction = endFraction;
    float x = bounds.origin.x + fraction * (bounds.size.width - diameter)
            + diameter / 2.0f;
    [[NSColor colorWithCalibratedRed:0.20f green:0.55f blue:0.91f
                               alpha:1.0f] set];
    NSRectFill(NSMakeRect((float)floor(x) - 1.0f,
                          bounds.origin.y + 3.0f,
                          2.0f, bounds.size.height - 6.0f));

    /* the clip end knob: right half only */
    [self drawKnobInRect:[self clipEndKnobRect] half:1];
}

@end

/* private hover methods, declared up front: GCC 4 warns about messages
 * to methods only defined further down the file */
@interface VLCLegacySeekSlider (HoverPrivate)
- (void)resetHoverTrackingRect;
- (void)hoverTimerFired:(NSTimer *)timer;
- (double)hoverMatchTolerance;
- (void)updateHoverTooltipForPoint:(NSPoint)local;
- (void)thumbnailDebounceFired:(NSTimer *)timer;
@end

/*****************************************************************************
 * VLCLegacySeekTooltipWindow: borderless floating panel following the
 * mouse on the seek bar, showing the hovered time, the chapter (when
 * any) and, when the provider answered, a preview thumbnail. Port of the
 * modern VLCSeekTooltipWindow with a Jaguar API floor: rounded corners
 * from arcs, -convertBaseToScreen: instead of -convertRectToScreen:
 * (10.7+), no -setHidden: (10.3+) — the image view is collapsed to a
 * zero frame instead.
 *****************************************************************************/

@interface VLCLegacySeekTooltipBackgroundView : NSView
@end

@implementation VLCLegacySeekTooltipBackgroundView
- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor colorWithCalibratedWhite:0.12f alpha:0.92f] set];
    [VLCLegacyRoundedRectPath([self bounds], 4.0f) fill];
}
@end

@interface VLCLegacySeekTooltipWindow : NSWindow
{
    NSTextField *textField;
    NSImageView *imageView;
    NSWindow *stereoMirrorWindow;
    NSImageView *stereoMirrorImageView;
}
- (void)updateWithText:(NSString *)text
                 image:(NSImage *)image
        atScreenBottom:(NSPoint)bottomCenter;
- (void)updateStereoMirror;
@end

@implementation VLCLegacySeekTooltipWindow

- (void)dealloc
{
    [stereoMirrorWindow release];
    [super dealloc];
}

- (id)init
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
        [self setReleasedWhenClosed:NO];

        NSView *content = [[[VLCLegacySeekTooltipBackgroundView alloc]
            initWithFrame:NSZeroRect] autorelease];
        [self setContentView:content];

        imageView = [[[NSImageView alloc] initWithFrame:NSZeroRect]
                        autorelease];
        [imageView setImageScaling:NSScaleProportionally];
        [imageView setEditable:NO];
        [content addSubview:imageView];

        textField = [[[NSTextField alloc] initWithFrame:NSZeroRect]
                        autorelease];
        [textField setEditable:NO];
        [textField setSelectable:NO];
        [textField setBezeled:NO];
        [textField setBordered:NO];
        [textField setDrawsBackground:NO];
        [textField setAlignment:NSCenterTextAlignment];
        [textField setTextColor:[NSColor whiteColor]];
        [textField setFont:[NSFont systemFontOfSize:11.0f]];
        [content addSubview:textField];
    }
    return self;
}

- (void)updateWithText:(NSString *)text
                 image:(NSImage *)image
        atScreenBottom:(NSPoint)bottomCenter
{
    const float padding = 5.0f;
    const float thumbWidth = 160.0f;

    [textField setStringValue:text];
    [textField sizeToFit];
    NSSize textSize = [textField frame].size;

    float width = textSize.width + 2.0f * padding;
    float height = textSize.height + 2.0f * padding;

    NSSize thumbSize = NSMakeSize(0.0f, 0.0f);
    if (image) {
        NSSize imgSize = [image size];
        float aspect = (imgSize.width > 0)
            ? imgSize.height / imgSize.width : 0.5625f;
        thumbSize = NSMakeSize(thumbWidth, thumbWidth * aspect);
        if (width < thumbWidth + 2.0f * padding)
            width = thumbWidth + 2.0f * padding;
        height += thumbSize.height + padding;
    }

    [imageView setImage:image];
    /* no -setHidden: on 10.2: a zero frame hides it just as well */
    [imageView setFrame:image
        ? NSMakeRect((width - thumbSize.width) / 2.0f,
                     textSize.height + 2.0f * padding,
                     thumbSize.width, thumbSize.height)
        : NSZeroRect];
    [textField setFrame:NSMakeRect((width - textSize.width) / 2.0f, padding,
                                   textSize.width, textSize.height)];

    NSRect frame = NSMakeRect(bottomCenter.x - width / 2.0f, bottomCenter.y,
                              width, height);
    /* A new borderless window initially belongs to the main display. Use the
     * seek panel's screen so HDMI fullscreen tooltips are not clamped back
     * onto the Mac panel before their first -setFrame:. */
    NSScreen *screen = [[self parentWindow] screen];
    if (!screen) {
        NSEnumerator *screens = [[NSScreen screens] objectEnumerator];
        NSScreen *candidate;
        while ((candidate = [screens nextObject])) {
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
    /* early Quartz caches the shadow of transparent windows: without
     * this, resized tooltips drag a stale halo around (10.2/10.3) */
    [self invalidateShadow];

    if (![self isVisible])
        [self orderFront:nil];
    [self updateStereoMirror];
}

- (void)updateStereoMirror
{
    intf_thread_t *intf = [VLCLegacyGetCore() intf];
    NSScreen *screen = [self screen];
    float height = screen ? NSHeight([screen frame]) : 0.0f;
    float gap = 0.0f;
    if (intf
     && var_InheritInteger(intf, "stereo3d-fullscreen-display") > 0) {
        if (fabs(height - 2205.0f) < 2.0f)
            gap = 45.0f;
        else if (fabs(height - 1470.0f) < 2.0f)
            gap = 30.0f;
    }

    if (gap == 0.0f) {
        [stereoMirrorWindow orderOut:nil];
        return;
    }

    if (!stereoMirrorWindow) {
        stereoMirrorWindow = [[NSWindow alloc]
            initWithContentRect:[self frame]
                      styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered defer:NO];
        [stereoMirrorWindow setOpaque:NO];
        [stereoMirrorWindow setBackgroundColor:[NSColor clearColor]];
        [stereoMirrorWindow setHasShadow:NO];
        [stereoMirrorWindow setIgnoresMouseEvents:YES];
        [stereoMirrorWindow setReleasedWhenClosed:NO];
        stereoMirrorImageView = [[[NSImageView alloc]
            initWithFrame:[[stereoMirrorWindow contentView] bounds]] autorelease];
        [stereoMirrorImageView setImageScaling:NSScaleToFit];
        [stereoMirrorImageView setAutoresizingMask:
            NSViewWidthSizable | NSViewHeightSizable];
        [[stereoMirrorWindow contentView] addSubview:stereoMirrorImageView];
    }

    NSView *content = [self contentView];
    [content displayIfNeeded];
    NSRect bounds = [content bounds];
    NSBitmapImageRep *rep =
        [content bitmapImageRepForCachingDisplayInRect:bounds];
    if (!rep)
        return;
    [content cacheDisplayInRect:bounds toBitmapImageRep:rep];
    NSImage *snapshot = [[[NSImage alloc] initWithSize:bounds.size] autorelease];
    [snapshot addRepresentation:rep];
    [stereoMirrorImageView setImage:snapshot];

    NSRect frame = [self frame];
    BOOL sourceIsLowerEye = NSMidY(frame) < NSMidY([screen frame]);
    float eyeStride = (height - gap) / 2.0f + gap;
    frame.origin.y += sourceIsLowerEye ? eyeStride : -eyeStride;
    int depth = (int)var_InheritInteger(intf, "stereo3d-overlay-depth");
    depth = MAX(-100, MIN(100, depth));
    float disparity = NSWidth([screen frame]) * .04f * depth / 100.0f;
    frame.origin.x += sourceIsLowerEye ? disparity : -disparity;

    [stereoMirrorWindow setFrame:frame display:NO];
    [stereoMirrorWindow setLevel:[self level]];
    [stereoMirrorWindow setAlphaValue:[self alphaValue]];
    [stereoMirrorWindow orderFront:nil];
}

- (void)orderOut:(id)sender
{
    [stereoMirrorWindow orderOut:sender];
    [super orderOut:sender];
}

@end

/*****************************************************************************
 * VLCLegacySeekSlider: plain NSSlider outside the clip creation mode; in
 * the mode it tracks the two bound knobs itself (on the knobs: drag that
 * bound; between them: plain seek/scrub; outside: pull the nearest
 * bound), sending the regular action for every step so the target seeks.
 *****************************************************************************/

static NSString *VLCLegacyHoverTimeString(double seconds)
{
    if (seconds < 0.0)
        seconds = 0.0;
    int total = (int)(seconds + 0.5);
    if (total >= 3600)
        return [NSString stringWithFormat:@"%d:%02d:%02d",
                total / 3600, (total / 60) % 60, total % 60];
    return [NSString stringWithFormat:@"%02d:%02d",
            total / 60, total % 60];
}

@implementation VLCLegacySeekSlider

- (void)dealloc
{
    [hoverTimer invalidate];
    [thumbnailDebounceTimer invalidate];
    [tooltipWindow release];
    [hoverThumbnail release];
    [super dealloc];
}

- (void)setMediaDuration:(double)seconds { mediaDuration = seconds; }
- (void)setHoverDelegate:(id)delegate { hoverDelegate = delegate; }

#pragma mark Hover tracking (classic tracking rect + mouse-follow timer)

- (void)resetHoverTrackingRect
{
    if (hoverTrackingTag) {
        [self removeTrackingRect:hoverTrackingTag];
        hoverTrackingTag = 0;
    }
    if ([self window]) {
        NSPoint local = [self convertPoint:
            [[self window] mouseLocationOutsideOfEventStream] fromView:nil];
        BOOL mouseInside = NSMouseInRect(local, [self bounds], [self isFlipped]);
        hoverTrackingTag = [self addTrackingRect:[self bounds]
                                           owner:self
                                        userData:NULL
                                    assumeInside:mouseInside];
        /* Après un redimensionnement ou un retour de plein écran, le nouveau
         * tracking rect peut naître sous un pointeur déjà immobile : AppKit
         * n'envoie alors aucun mouseEntered:. Amorcer nous-mêmes le suivi. */
        if (mouseInside)
            [self mouseEntered:nil];
    }
}

- (void)viewDidMoveToWindow
{
    if (![self window]) {
        /* the mouseExited that would stop the timer can never arrive */
        [hoverTimer invalidate];
        hoverTimer = nil;
        [self hideHoverTooltip];
    }
    [self resetHoverTrackingRect];
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self resetHoverTrackingRect];
}

- (void)mouseEntered:(NSEvent *)event
{
    if (hoverTimer)
        return;
    /* -mouseMoved: goes to the first responder, not to the hovered view;
     * a 10 Hz timer while inside is the 10.2-safe equivalent (it pauses
     * on its own during drags: event tracking runs another runloop mode) */
    hoverTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                  target:self
                                                selector:@selector(hoverTimerFired:)
                                                userInfo:nil
                                                 repeats:YES];
    [self hoverTimerFired:nil];
}

- (void)mouseExited:(NSEvent *)event
{
    [hoverTimer invalidate];
    hoverTimer = nil;
    [self hideHoverTooltip];
}

- (void)hoverTimerFired:(NSTimer *)timer
{
    NSWindow *win = [self window];
    if (!win) {
        [hoverTimer invalidate];
        hoverTimer = nil;
        [self hideHoverTooltip];
        return;
    }
    NSPoint local = [self convertPoint:[win mouseLocationOutsideOfEventStream]
                              fromView:nil];
    if (NSMouseInRect(local, [self bounds], [self isFlipped])) {
        /* only rebuild when the mouse actually moved: rebuilding every
         * tick would re-arm the 1 s thumbnail debounce forever */
        if (!hasLastHoverPoint
            || fabs(local.x - lastHoverPoint.x) >= 1.0
            || fabs(local.y - lastHoverPoint.y) >= 1.0) {
            lastHoverPoint = local;
            hasLastHoverPoint = YES;
            [self updateHoverTooltipForPoint:local];
        }
    } else {
        /* belt and braces: the exit event can get lost during window
         * drags or when another window slides over the bar */
        [hoverTimer invalidate];
        hoverTimer = nil;
        [self hideHoverTooltip];
    }
}

- (void)hideHoverTooltip
{
    hovering = NO;
    hasLastHoverPoint = NO;
    [tooltipWindow orderOut:nil];
    [thumbnailDebounceTimer invalidate];
    thumbnailDebounceTimer = nil;
}

- (void)refreshHoverForCurrentMouseLocation
{
    NSWindow *win = [self window];
    if (!win || ![win isVisible]) {
        [self hideHoverTooltip];
        return;
    }

    NSPoint local = [self convertPoint:[win mouseLocationOutsideOfEventStream]
                              fromView:nil];
    if (NSMouseInRect(local, [self bounds], [self isFlipped])) {
        if (!hoverTimer)
            [self mouseEntered:nil];
        else
            [self hoverTimerFired:nil];
    } else if (hovering) {
        [self hideHoverTooltip];
    }
}


/* Tolérance du « c'est bien la position demandée », en FRACTION de barre.
 *
 * ⚠⚠⚠ Elle était exprimée en SECONDES DE FILM (2 s). Sur un long média, un
 * seul pixel de barre en vaut bien davantage — mesuré : ~13 s sur un film de
 * 2 h 20 étalé sur 640 px —, si bien que le moindre frémissement de souris
 * pendant les ~2 s de décodage faisait JETER la vignette. Elle était pourtant
 * bien produite : trouvée dans le dossier temporaire de l'instance, 128 Ko,
 * horodatée pendant que l'utilisateur survolait la barre. Résultat : aperçu
 * jamais visible sur les longs films, et parfaitement visible sur les courts.
 *
 * On raisonne donc en PIXELS, avec l'ancien seuil en secondes comme plancher
 * (sur un média court, deux secondes peuvent valoir plus de trois pixels). */
- (double)hoverMatchTolerance
{
    float width = [self frame].size.width;
    if (width < 1.f)
        width = 1.f;
    double byPixels = 3.0 / (double)width;
    double bySeconds = (mediaDuration > 0.0) ? 2.0 / mediaDuration : 0.0;
    return byPixels > bySeconds ? byPixels : bySeconds;
}

- (void)updateHoverTooltipForPoint:(NSPoint)local
{
    if (![self isEnabled] || mediaDuration <= 0.0) {
        [self hideHoverTooltip];
        return;
    }

    double value = [self valueForLocationX:(float)local.x];
    double range = [self maxValue] - [self minValue];
    double fraction = range > 0 ? (value - [self minValue]) / range : 0.0;
    hovering = YES;
    hoverFraction = fraction;

    NSString *text = VLCLegacyHoverTimeString(fraction * mediaDuration);

    /* chapter (when any): last one starting at or before the position */
    VLCLegacyProgressSliderCell *cell =
        (VLCLegacyProgressSliderCell *)[self cell];
    NSArray *fractions = [cell chapterFractions];
    NSArray *names = [cell chapterNames];
    unsigned int count = [fractions count];
    if (count > 0 && [names count] == count) {
        int selected = -1;
        unsigned int i;
        for (i = 0; i < count; i++) {
            if ([[fractions objectAtIndex:i] doubleValue] <= fraction)
                selected = (int)i;
        }
        if (selected >= 0) {
            NSString *name = [names objectAtIndex:(unsigned int)selected];
            if ([name length] > 0)
                /* em dash through UTF-8 explicitly: 10.2's Foundation
                 * reads high-bit bytes of CONSTANT strings as MacRoman
                 * (@"—" renders as ",Äî" there) */
                text = [NSString stringWithFormat:@"%@%@%@", name,
                        [NSString stringWithUTF8String:" \xE2\x80\x94 "],
                        text];
        }
    }

    /* An exact marker hover takes precedence over the surrounding chapter. */
    NSArray *bookmarkFractions = [cell bookmarkFractions];
    NSArray *bookmarkNames = [cell bookmarkNames];
    unsigned int bookmarkCount = [bookmarkFractions count];
    if (bookmarkCount > 0 && [bookmarkNames count] == bookmarkCount) {
        float diameter = [cell knobDiameter];
        float usable = [self bounds].size.width - diameter;
        unsigned int i;
        for (i = 0; i < bookmarkCount; i++) {
            double mark = [[bookmarkFractions objectAtIndex:i] doubleValue];
            float markX = [self bounds].origin.x + diameter / 2.0f
                        + mark * usable;
            if (fabs(markX - local.x) <= 5.0f) {
                NSString *name = [bookmarkNames objectAtIndex:i];
                if ([name length] > 0)
                    text = [NSString stringWithFormat:@"%@%@%@", name,
                        [NSString stringWithUTF8String:" \xE2\x80\x94 "],
                        VLCLegacyHoverTimeString(mark * mediaDuration)];
                break;
            }
        }
    }

    /* in clip creation mode, hovering the clip range also shows the
     * clip's current total duration */
    if ([cell clipKnobsActive]) {
        double startFraction = ([self doubleValue] - [self minValue])
                             / (range > 0 ? range : 1.);
        double endFraction = ([cell clipEndValue] - [self minValue])
                           / (range > 0 ? range : 1.);
        if (fraction >= startFraction && fraction <= endFraction) {
            text = [NSString stringWithFormat:@"%@%@%@ %@", text,
                    [NSString stringWithUTF8String:" \xE2\x80\x94 "],
                    _NS("Clip:"),
                    VLCLegacyHoverTimeString(
                        (endFraction - startFraction) * mediaDuration)];
        }
    }

    if (!tooltipWindow)
        tooltipWindow = [[VLCLegacySeekTooltipWindow alloc] init];
    NSWindow *hostWindow = [self window];
    if ([tooltipWindow parentWindow] != hostWindow) {
        [[tooltipWindow parentWindow] removeChildWindow:tooltipWindow];
        [hostWindow addChildWindow:tooltipWindow ordered:NSWindowAbove];
    }
    /* stay above whatever hosts the slider (the fullscreen panel floats
     * at the same level as the tooltip: +1 makes the order explicit) */
    int wantedLevel = [[self window] level] + 1;
    /* Le plan ATI est une surface CGS distincte. Sur Panther, un niveau juste
     * au-dessus d'une fenêtre normale peut encore être composé derrière elle. */
    if (wantedLevel < NSFloatingWindowLevel)
        wantedLevel = NSFloatingWindowLevel;
    if ([tooltipWindow level] != wantedLevel)
        [tooltipWindow setLevel:wantedLevel];

    /* only show a cached thumbnail matching the hovered position (within
     * two seconds), else wait for the (debounced) provider */
    NSImage *thumbnail = nil;
    if (hoverThumbnail
        && fabs(hoverThumbnailFraction - fraction) <= [self hoverMatchTolerance])
        thumbnail = hoverThumbnail;

    /* anchor the tooltip 6 pt above the slider TOP edge, whatever the
     * flippedness: convert the top-edge point explicitly instead of
     * relying on NSMaxY(bounds) meaning "up" */
    NSRect sliderBounds = [self bounds];
    NSPoint topLocal = NSMakePoint(local.x, [self isFlipped]
        ? NSMinY(sliderBounds) : NSMaxY(sliderBounds));
    NSPoint base = [self convertPoint:topLocal toView:nil];
    /* -convertRectToScreen: is 10.7+; the classic conversion is fine */
    NSPoint screenPoint = [[self window] convertBaseToScreen:base];
    screenPoint.y += 6.0f;
    [tooltipWindow updateWithText:text image:thumbnail
                   atScreenBottom:screenPoint];

    /* the thumbnail request is debounced so a frantic hover does not
     * spam the thumbnailer: it fires once the mouse has settled for a
     * third of a second (measured: the rest of the chain costs ~1.6 s) (a full second at first; shortened for responsiveness --
     * a hover preview still costs a secondary decode, which is why the
     * debounce stays, and why it can be turned off entirely on slow
     * machines). No re-arm when the shown thumbnail already matches, or
     * a delivery would restart the cycle forever */
    if (hoverDelegate && !thumbnail) {
        [thumbnailDebounceTimer invalidate];
        thumbnailDebounceTimer =
            [NSTimer scheduledTimerWithTimeInterval:0.3
                                             target:self
                                           selector:@selector(thumbnailDebounceFired:)
                                           userInfo:nil
                                            repeats:NO];
    }
}

- (void)thumbnailDebounceFired:(NSTimer *)timer
{
    thumbnailDebounceTimer = nil;
    if (!hovering)
        return;
    if ([hoverDelegate respondsToSelector:
            @selector(seekSlider:hoverThumbnailWantedAtFraction:)])
        [hoverDelegate seekSlider:self
            hoverThumbnailWantedAtFraction:hoverFraction];
}

- (void)setHoverThumbnail:(NSImage *)image forFraction:(double)fraction
{
    if (image != hoverThumbnail) {
        [hoverThumbnail release];
        hoverThumbnail = [image retain];
    }
    hoverThumbnailFraction = fraction;
    if (!hovering || !image)
        return;
    /* Repaint the tooltip around the image, for the very point it was
     * built for: sampling the mouse again here would re-read a pointer
     * that has drifted by a pixel in the meantime, and the announced time
     * would visibly jump (a pixel is several seconds on a long media)
     * just because the preview landed. */
    if (mediaDuration > 0
        && fabs(fraction - hoverFraction) <= [self hoverMatchTolerance]) {
        if (hasLastHoverPoint)
            [self updateHoverTooltipForPoint:lastHoverPoint];
    }
}

- (double)valueForLocationX:(float)x
{
    VLCLegacyProgressSliderCell *cell =
        (VLCLegacyProgressSliderCell *)[self cell];
    NSRect bounds = [self bounds];
    float diameter = [cell knobDiameter];
    float usable = bounds.size.width - diameter;
    if (usable <= 0.0f)
        return [self minValue];
    double fraction = (x - bounds.origin.x - diameter / 2.0f) / usable;
    if (fraction < 0.)
        fraction = 0.;
    else if (fraction > 1.)
        fraction = 1.;
    return [self minValue] + fraction * ([self maxValue] - [self minValue]);
}

- (void)moveClipKnob:(int)knob toLocationX:(float)x
{
    VLCLegacyProgressSliderCell *cell =
        (VLCLegacyProgressSliderCell *)[self cell];
    double value = [self valueForLocationX:x];
    if (knob == 1) {
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
 * own (~11 pt measured), while the knob drawn here is 15 pt and the hover
 * tooltip converts with THAT geometry: the two disagree by a couple of
 * pixels, which on a 1.5 h media is a seek landing up to ~17 s away from
 * the time the tooltip just announced (reported by the user, reproduced:
 * tooltip 07:39, seek 07:48). Overriding -knobThickness does not help,
 * AppKit ignores it while tracking, so the conversion is done here with
 * -valueForLocationX: -- the very function the tooltip uses, and the
 * exact inverse of the knob drawing. */
- (void)trackPlainSeekFromEvent:(NSEvent *)event
{
    while (event != nil && [event type] != NSLeftMouseUp) {
        NSPoint local = [self convertPoint:[event locationInWindow]
                                  fromView:nil];
        [self setDoubleValue:[self valueForLocationX:(float)local.x]];
        [self setNeedsDisplay:YES];
        [self sendAction:[self action] to:[self target]];

        event = [[self window] nextEventMatchingMask:
                 (NSLeftMouseDraggedMask | NSLeftMouseUpMask)];
    }
}

- (void)mouseDown:(NSEvent *)event
{
    /* the tooltip in front of a drag is only in the way */
    [self hideHoverTooltip];

    VLCLegacyProgressSliderCell *cell =
        (VLCLegacyProgressSliderCell *)[self cell];
    if (![self isEnabled]) {
        [super mouseDown:event];
        return;
    }
    if (![cell clipKnobsActive]) {
        NSPoint local = [self convertPoint:[event locationInWindow]
                                  fromView:nil];
        NSArray *fractions = [cell bookmarkFractions];
        float diameter = [cell knobDiameter];
        float usable = [self bounds].size.width - diameter;
        unsigned int i;
        for (i = 0; i < [fractions count]; i++) {
            double fraction = [[fractions objectAtIndex:i] doubleValue];
            float markX = [self bounds].origin.x + diameter / 2.0f
                        + fraction * usable;
            if (fabs(markX - local.x) <= 5.0f
                && [hoverDelegate respondsToSelector:
                    @selector(seekSlider:bookmarkSelectedAtIndex:)]) {
                [self setDoubleValue:[self minValue] + fraction
                    * ([self maxValue] - [self minValue])];
                [self setNeedsDisplay:YES];
                [hoverDelegate seekSlider:self bookmarkSelectedAtIndex:(int)i];
                return;
            }
        }
        [self trackPlainSeekFromEvent:event];
        return;
    }

    /* each bound is drawn as a half disc pointing away from the clip, so
     * its grab area is that half (plus a couple of pixels of slop) and the
     * two areas can never overlap: the midpoint between both bounds always
     * splits them, however close they get */
    NSPoint local = [self convertPoint:[event locationInWindow] fromView:nil];
    NSRect startKnobRect = [cell knobRectFlipped:NO];
    NSRect endKnobRect = [cell clipEndKnobRect];
    float radius = (float)(NSWidth(startKnobRect) / 2);
    const float slop = 2.0f;
    float startX = (float)NSMidX(startKnobRect);
    float endX = (float)NSMidX(endKnobRect);
    float middleX = (startX + endX) / 2.0f;
    /* inner edges, never crossing the midpoint between the two bounds */
    float startInnerX = startX + slop;
    float endInnerX = endX - slop;
    if (startInnerX > middleX)
        startInnerX = middleX;
    if (endInnerX < middleX)
        endInnerX = middleX;
    int knob;
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

    [self moveClipKnob:knob toLocationX:(float)local.x];
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
    NSTimeInterval lastPreview = [NSDate timeIntervalSinceReferenceDate];
    BOOL pendingPreview = NO;

    for (;;) {
        NSDate *limit = pendingPreview
            ? [NSDate dateWithTimeIntervalSinceNow:0.02]
            : [NSDate distantFuture];
        event = [[self window] nextEventMatchingMask:
                     (NSLeftMouseDraggedMask | NSLeftMouseUpMask)
                                           untilDate:limit
                                              inMode:NSEventTrackingRunLoopMode
                                             dequeue:YES];
        if (event) {
            local = [self convertPoint:[event locationInWindow] fromView:nil];
            [self moveClipKnob:knob toLocationX:(float)local.x];
            if ([event type] == NSLeftMouseUp) {
                [self sendAction:[self action] to:[self target]];
                break;
            }
            pendingPreview = YES;
        }

        NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
        if (pendingPreview && now - lastPreview >= 0.1) {
            lastPreview = now;
            pendingPreview = NO;
            [self sendAction:[self action] to:[self target]];
        }
    }

    [cell setHighlighted:NO];
    [cell setActiveClipKnob:0];
    [self setNeedsDisplay:YES];
}

- (void)scrollWheel:(NSEvent *)event
{
    /* scrolling would silently move the clip start bound */
    if ([(VLCLegacyProgressSliderCell *)[self cell] clipKnobsActive])
        return;
    [super scrollWheel:event];
}

/* clicking a knob makes the slider the first responder: the bare arrow
 * keys then land here (NSSlider would nudge its own value) instead of
 * reaching the core hotkeys module. In clip mode they must behave like
 * everywhere else: one-frame nudge of the selected bound, routed
 * through the delegate (it owns the core interaction). */
- (void)keyDown:(NSEvent *)event
{
    if ([(VLCLegacyProgressSliderCell *)[self cell] clipKnobsActive]) {
        NSString *characters = [event charactersIgnoringModifiers];
        if ([characters length] == 1) {
            unichar key = [characters characterAtIndex:0];
            if (key == NSLeftArrowFunctionKey
                || key == NSRightArrowFunctionKey) {
                if ([hoverDelegate respondsToSelector:
                        @selector(seekSlider:clipStepFrames:)])
                    [hoverDelegate seekSlider:self clipStepFrames:
                        (key == NSRightArrowFunctionKey ? 1 : -1)];
                return;
            }
        }
    }
    [super keyDown:event];
}

@end

void VLCLegacyUpdateSliderBookmarks(VLCLegacySeekSlider *slider,
                                    input_thread_t *p_input,
                                    int64_t duration)
{
    VLCLegacyProgressSliderCell *cell =
        (VLCLegacyProgressSliderCell *)[slider cell];
    NSArray *fractions = nil;
    NSArray *names = nil;
    NSArray *times = nil;

    if (p_input != NULL && duration > 0) {
        seekpoint_t **pp_bookmarks = NULL;
        int i_bookmarks = 0;
        if (input_Control(p_input, INPUT_GET_BOOKMARKS, &pp_bookmarks,
                          &i_bookmarks) == VLC_SUCCESS) {
            NSMutableArray *newFractions = [NSMutableArray
                arrayWithCapacity:i_bookmarks];
            NSMutableArray *newNames = [NSMutableArray
                arrayWithCapacity:i_bookmarks];
            NSMutableArray *newTimes = [NSMutableArray
                arrayWithCapacity:i_bookmarks];
            int i;
            for (i = 0; i < i_bookmarks; i++) {
                vlc_tick_t time = pp_bookmarks[i]->i_time_offset;
                double fraction = (double)time / (double)duration;
                if (fraction < 0.0) fraction = 0.0;
                if (fraction > 1.0) fraction = 1.0;
                [newFractions addObject:[NSNumber numberWithDouble:fraction]];
                NSString *name = pp_bookmarks[i]->psz_name
                    ? [NSString stringWithUTF8String:pp_bookmarks[i]->psz_name]
                    : @"";
                [newNames addObject:name ? name : @""];
                [newTimes addObject:[NSNumber numberWithLongLong:time]];
                vlc_seekpoint_Delete(pp_bookmarks[i]);
            }
            free(pp_bookmarks);
            fractions = newFractions;
            names = newNames;
            times = newTimes;
        }
    }

    NSArray *oldFractions = [cell bookmarkFractions];
    NSArray *oldNames = [cell bookmarkNames];
    NSArray *oldTimes = [cell bookmarkTimes];
    if ((oldFractions == fractions || [oldFractions isEqualToArray:fractions])
        && (oldNames == names || [oldNames isEqualToArray:names])
        && (oldTimes == times || [oldTimes isEqualToArray:times]))
        return;
    [cell setBookmarkFractions:fractions names:names times:times];
    [slider setNeedsDisplay:YES];
}
