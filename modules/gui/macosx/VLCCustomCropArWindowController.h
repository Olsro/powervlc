/*****************************************************************************
 * VLCCustomCropArWindowController.h: custom crop / aspect ratio panel
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC
 *
 * Backported from VLC 4.0 (modules/gui/macosx/panels/dialogs), whose panel
 * is loaded from a nib. This one builds itself, so that it can be added to
 * an interface whose menus and windows come from a frozen xib.
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

NS_ASSUME_NONNULL_BEGIN

@interface VLCCustomCropArWindowController : NSWindowController

/**
 * Asks for a ratio and returns it as "numerator:denominator", or nil when
 * the panel was cancelled. Runs modally.
 *
 * \param title what is being set ("Aspect ratio", "Crop")
 * \param ratio the ratio to start from, or nil
 */
+ (nullable NSString *)runModalWithTitle:(NSString *)title
                            currentRatio:(nullable NSString *)ratio;

@end

NS_ASSUME_NONNULL_END
