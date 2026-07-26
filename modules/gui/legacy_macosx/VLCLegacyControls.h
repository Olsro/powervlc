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
}
- (void)setKnobInset:(float)inset;
- (void)setVolumeStyle:(BOOL)volume;
- (void)setAlwaysDark:(BOOL)dark;
- (void)setIndefinite:(BOOL)flag;
- (BOOL)indefinite;
@end
