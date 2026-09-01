/*****************************************************************************
 * VLCSlider.h
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

#import <Cocoa/Cocoa.h>

@class VLCSlider;

/* Optional provider of hover thumbnails: asked (debounced) for a preview
 * image of the hovered position; answers back through
 * -setHoverThumbnail:forFraction: whenever the image is ready. */
@protocol VLCSliderHoverDelegate <NSObject>
- (void)slider:(VLCSlider *)slider hoverThumbnailWantedAtFraction:(double)fraction;
- (void)sliderHoverEnded:(VLCSlider *)slider;
@end

@interface VLCSlider : NSSlider

@property (nonatomic, getter=getIndefinite,setter=setIndefinite:) BOOL indefinite;
@property (nonatomic, getter=getKnobHidden,setter=setKnobHidden:) BOOL isKnobHidden;

/* Indicates if the slider is scrollable with the mouse or trackpad scrollwheel. */
@property (readwrite) BOOL isScrollable;

/* Clip creation mode: the regular knob holds the clip start, a second
 * knob holds the clip end. Dragging or clicking either knob moves it and
 * is reported through the regular action; activeClipKnob tells which
 * knob (1 = start, 2 = end) is being manipulated. */
@property (nonatomic) BOOL clipKnobsActive;
@property (nonatomic) double clipEndValue;
@property (nonatomic) double playbackMarkerValue;
@property (nonatomic, readonly) NSInteger activeClipKnob;

/* Chapters (normalized fractions + names) and media duration in seconds,
 * used for the on-track separators and the hover tooltip. */
@property (nonatomic, copy) NSArray *chapterFractions;
@property (nonatomic, copy) NSArray *chapterNames;
@property (nonatomic, copy) NSArray *bookmarkFractions;
@property (nonatomic, copy) NSArray *bookmarkNames;
@property (nonatomic, copy) NSArray *bookmarkTimes;
@property (nonatomic) double mediaDuration;

/* Reload the current title's persistent bookmarks from the input. */
- (void)reloadBookmarks;

@property (nonatomic, weak) id<VLCSliderHoverDelegate> hoverDelegate;

/* Hand a ready thumbnail back to the tooltip (ignored if the mouse has
 * moved away from that position in the meantime). */
- (void)setHoverThumbnail:(NSImage *)image forFraction:(double)fraction;

/* Drop the tooltip right away (the host is going away: autohidden
 * fullscreen panel, closed window, …). */
- (void)hideHoverTooltip;

/* Re-evaluate the hover from the current pointer position. The MVC
 * fullscreen controller can move the real panel underneath a stationary
 * pointer, in which case AppKit sends no matching mouse event. */
- (void)refreshHoverForCurrentMouseLocation;

/* Show the hover tooltip for a point expressed in this slider's host-window
 * coordinates. The frame-packed fullscreen mirror receives the physical
 * mouse event in the other eye and maps its identical local coordinates
 * through this entry point. */
- (void)refreshHoverForHostWindowPoint:(NSPoint)point;

- (void)setSliderStyleLight;
- (void)setSliderStyleDark;

@end
