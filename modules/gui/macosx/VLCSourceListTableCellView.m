/*****************************************************************************
 * VLCSourceListTableCellView.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2018 VLC authors and VideoLAN
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

#import "VLCSourceListTableCellView.h"

@implementation VLCSourceListTableCellView

- (void)awakeFromNib
{
    [super awakeFromNib];

    // Set larger margin for Big Sur sidebar to reduce icon size
    // 10.16 == 11.0, but the latter is not known in older SDKs
    if(@available(macOS 10.16, *)) {
        self.imageBottomConstraint.constant = 6.0;
        self.imageTopConstraint.constant = 6.0;
    }
}

- (void)layout
{
    [super layout];

    /* PXSourceList adjusts row indentation after Auto Layout has positioned
     * the prototype cell.  On dynamically-added network rows this can leave
     * the label at the icon's origin, most visibly with an IP address.  Keep
     * a deterministic gap even after the source-list indentation pass. */
    if (self.imageView.image && self.textField) {
        NSRect imageFrame = self.imageView.frame;
        NSRect textFrame = self.textField.frame;
        CGFloat minimumTextX = NSMaxX(imageFrame) + 7.0;
        if (NSMinX(textFrame) < minimumTextX) {
            CGFloat rightEdge = NSMaxX(textFrame);
            textFrame.origin.x = minimumTextX;
            textFrame.size.width = MAX(0.0, rightEdge - minimumTextX);
            self.textField.frame = textFrame;
        }
    }
}

@end
