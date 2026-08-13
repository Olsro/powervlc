/*****************************************************************************
 * VLCLegacyCustomCropAr.h: custom crop / aspect ratio panel (legacy)
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC
 *
 * Backport of VLC 4.0's custom crop / aspect ratio panel for the legacy
 * interface: manual retain/release, built in code (no nib), and nothing
 * newer than Mac OS X 10.4.
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

@interface VLCLegacyCustomCropAr : NSObject
{
    NSWindow *window;
    NSTextField *numeratorField;
    NSTextField *denominatorField;
}

/**
 * Asks for a ratio and returns it as "numerator:denominator" (autoreleased),
 * or nil when the panel was cancelled. Runs modally.
 */
+ (NSString *)runModalWithTitle:(NSString *)title
                   currentRatio:(NSString *)ratio;

@end
