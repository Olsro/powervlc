/*****************************************************************************
 * VLCLegacyControls.h: shared custom controls for the legacy interface
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

/* Interface theme (mirrors the 3.0 grey/dark styles). Set once at
 * interface startup from the "legacy-macosx-dark" option; switching
 * requires a restart, exactly like the official 3.0 interface. */
BOOL VLCLegacyDarkMode(void);
void VLCLegacySetDarkMode(BOOL dark);

/* Theme-dependent colors */
NSColor *VLCLegacyTextColor(void);          /* time labels, table text */
NSColor *VLCLegacySecondaryTextColor(void); /* dropzone label, headers */
NSColor *VLCLegacyTableBackgroundColor(void);
NSColor *VLCLegacySidebarBackgroundColor(void);

/* Loads an image from the application bundle Resources (flattened at
 * packaging time); tries .png first, then .pdf (the VLC 3.0 template
 * icons are PDF vectors, which NSImage handles since Mac OS X 10.0). */
NSImage *VLCLegacyImage(NSString *name);

/* Same, resized (PDF vectors rescale cleanly through -setSize:) */
NSImage *VLCLegacyImageSized(NSString *name, NSSize size);

/* Template glyph tinted like the 3.0 bright interface (grey glyphs) */
NSImage *VLCLegacyTintedImage(NSString *name, NSSize size, NSColor *color);

/* Programmatic glyphs for buttons 3.0 has no template asset for */
NSImage *VLCLegacyStopGlyph(NSSize size, NSColor *color);
NSImage *VLCLegacyListGlyph(NSSize size, NSColor *color);

/* The 3.0 bright glyph color */
NSColor *VLCLegacyGlyphColor(void);

/* Borderless icon button in the VLC 3.0 style */
NSButton *VLCLegacyImageButton(NSView *parent, NSString *imageName,
                               NSString *alternateImageName, NSRect frame,
                               id target, SEL action);

/* Replica of VLCBottomBarView: the light gradient bar at the bottom of the
 * 3.0 main window. NSGradient needs 10.5, so the gradient is drawn as
 * interpolated horizontal slices. */
@interface VLCLegacyBottomBarView : NSView
@end

/* Slider cell drawing a bar image and a knob image (used by the fullscreen
 * panel with the fs_* artwork). */
@interface VLCLegacyImageSliderCell : NSSliderCell
{
    NSImage *barImage;
    NSImage *knobImage;
}
- (void)setBarImage:(NSImage *)bar knobImage:(NSImage *)knob;
@end

/* Thin progress-style seek slider replicating the VLC 3.0 time slider:
 * a rounded light track with the elapsed portion filled, and a small
 * round knob. */
/* -bezierPathWithRoundedRect:xRadius:yRadius: only exists since 10.5;
 * same geometry built from arcs, available since 10.0 */
NSBezierPath *VLCLegacyRoundedRectPath(NSRect rect, float radius);

/* Port of VLCSliderCell / VLCVolumeSliderCell (3.0): rectangular track
 * filling the control, vertical gradient, rounded 3 px, filled portion up
 * to the knob, round white knob. */
@interface VLCLegacyProgressSliderCell : NSSliderCell
{
    float knobInset;     /* 2.0 like VLCSliderCell; 1.0 for volume */
    BOOL volumeStyle;    /* thin track + 100% tick, like the 3.0 volume */
    BOOL alwaysDark;     /* fullscreen panel: dark regardless of theme */
    BOOL indefinite;     /* buffering: animated blue band, hidden knob */
    float animationPosition;

    /* clip creation mode: a second knob holds the clip end, the regular
     * knob holds the clip start, a thin marker follows the playback.
     * Values in the cell unit (0..1 for the time slider). */
    BOOL clipKnobsActive;
    double clipEndValue;
    double playbackMarkerValue;
    int activeClipKnob;  /* 0 none, 1 start, 2 end, 3 scrub */

    /* chapter separators on the track (normalized 0..1 fractions) and
     * their names for the hover tooltip; nil when the media has none */
    NSArray *chapterFractions;
    NSArray *chapterNames;
}
- (void)setKnobInset:(float)inset;
- (void)setVolumeStyle:(BOOL)volume;
- (void)setAlwaysDark:(BOOL)dark;
- (void)setIndefinite:(BOOL)flag;
- (BOOL)indefinite;

- (float)knobDiameter;
- (void)setChapterFractions:(NSArray *)fractions names:(NSArray *)names;
- (NSArray *)chapterFractions;
- (NSArray *)chapterNames;
- (void)setClipKnobsActive:(BOOL)active;
- (BOOL)clipKnobsActive;
- (void)setClipEndValue:(double)value;
- (double)clipEndValue;
- (void)setPlaybackMarkerValue:(double)value;
- (double)playbackMarkerValue;
- (void)setActiveClipKnob:(int)knob;
- (int)activeClipKnob;
- (NSRect)clipEndKnobRect;
/* half < 0 left half disc, 0 full disc, > 0 right half (clip bounds) */
- (void)drawKnobInRect:(NSRect)knobRect half:(int)half;
@end

@class VLCLegacySeekTooltipWindow;

/* Seek slider handling the two clip bounds knobs: outside the clip mode
 * it is a plain NSSlider. Also owns the hover tooltip (hovered time,
 * chapter name, optional preview thumbnail).
 *
 * Jaguar floor: no NSTrackingArea (10.5+) — a classic tracking rect
 * detects enter/exit and a 10 Hz timer follows the mouse while inside
 * (-mouseMoved: is delivered to the first responder, not to the view
 * under the cursor, so it cannot be relied upon here). */
@interface VLCLegacySeekSlider : NSSlider
{
    NSTrackingRectTag hoverTrackingTag;
    NSTimer *hoverTimer;             /* follows the mouse while inside */
    NSPoint lastHoverPoint;          /* last point the tooltip was built
                                      * for: the 10 Hz follow timer must
                                      * not re-arm the debounce while the
                                      * mouse sits still */
    BOOL hasLastHoverPoint;
    NSTimer *thumbnailDebounceTimer; /* 1 s of quiet before a request */
    VLCLegacySeekTooltipWindow *tooltipWindow;
    BOOL hovering;
    double hoverFraction;
    double mediaDuration;            /* seconds; 0 = no tooltip */
    NSImage *hoverThumbnail;
    double hoverThumbnailFraction;
    id hoverDelegate;                /* assign; informal protocol below */
}
- (double)valueForLocationX:(float)x;

- (void)setMediaDuration:(double)seconds;
/* the delegate is NOT retained (it owns the slider) */
- (void)setHoverDelegate:(id)delegate;
- (void)hideHoverTooltip;
/* thumbnail provider answer; ignored when the mouse moved elsewhere */
- (void)setHoverThumbnail:(NSImage *)image forFraction:(double)fraction;
@end

/* Informal hover delegate protocol:
 * - (void)seekSlider:(VLCLegacySeekSlider *)slider
 *       hoverThumbnailWantedAtFraction:(double)fraction;
 * fired once the mouse has settled for a second; reply (possibly later,
 * possibly never) with -setHoverThumbnail:forFraction:.
 * - (void)seekSlider:(VLCLegacySeekSlider *)slider
 *       clipStepFrames:(int)direction;
 * bare arrow key pressed while the slider is the first responder in
 * clip mode: nudge the selected bound by one frame. */
