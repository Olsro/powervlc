/*****************************************************************************
 * VLCFSPanelDraggableView.m
 *****************************************************************************
 * Copyright (C) 2017 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: David Fuhrmann <dfuhrmann at videolan dot org>
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

#import "VLCFSPanelDraggableView.h"

#import "VLCFSPanelController.h"

@implementation VLCFSPanelDraggableView

- (BOOL)mouseDownCanMoveWindow
{
    return NO;
}

- (NSView *)hitTest:(NSPoint)point
{
    NSView *hit = [super hitTest:point];

    /* Labels and otherwise empty layout views occupy almost every pixel of
     * the panel. Treat them as draggable background while preserving buttons
     * and sliders as real controls. */
    if ([hit isKindOfClass:[NSTextField class]] ||
        (hit != self && ![hit isKindOfClass:[NSControl class]]))
        return self;
    return hit;
}

- (void)mouseDown:(NSEvent *)event
{
    VLCFSPanelController *controller =
        (VLCFSPanelController *)self.window.delegate;
    [controller dragFullscreenPanelWithEvent:event trackingWindow:self.window];
}

@end
