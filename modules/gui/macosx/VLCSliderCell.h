/*****************************************************************************
 * VLCSliderCell.h
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
#import <QuartzCore/QuartzCore.h>

@interface VLCSliderCell : NSSliderCell

// Colors
@property NSColor *gradientColor;
@property NSColor *gradientColor2;
@property NSColor *trackStrokeColor;
@property NSColor *filledTrackColor;
@property NSColor *knobFillColor;
@property NSColor *activeKnobFillColor;
@property NSColor *shadowColor;
@property NSColor *knobStrokeColor;
@property NSColor *highlightBackground;

// Gradients
@property NSGradient *trackGradient;
@property NSGradient *highlightGradient;

// Shadows
@property NSShadow *knobShadow;


@property NSInteger animationWidth;

@property (nonatomic, setter=setIndefinite:) BOOL indefinite;
@property (nonatomic, setter=setKnobHidden:) BOOL isKnobHidden;

/* Clip creation mode: a second knob marks the clip end position, the
 * regular knob marks the clip start, and a thin vertical marker keeps
 * showing the actual playback position on the track. Values use the
 * same unit as the cell value (0..10000 for the time slider). */
@property (nonatomic) BOOL clipKnobsActive;
@property (nonatomic) double clipEndValue;
@property (nonatomic) double playbackMarkerValue;
/* 0 = none, 1 = start knob, 2 = end knob */
@property (nonatomic) NSInteger activeClipKnob;

/* chapter start positions (NSNumber, normalized 0..1), drawn as thin
 * separators on the track like the Qt seek slider */
@property (nonatomic, copy) NSArray *chapterFractions;
/* persistent bookmark positions (NSNumber, normalized 0..1) */
@property (nonatomic, copy) NSArray *bookmarkFractions;

- (NSRect)clipEndKnobRect;

- (void)setSliderStyleLight;
- (void)setSliderStyleDark;

@end
