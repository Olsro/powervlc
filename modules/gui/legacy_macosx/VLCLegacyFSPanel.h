/*****************************************************************************
 * VLCLegacyFSPanel.h: fullscreen controller panel for the legacy interface
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

#include <vlc_common.h>
#include <vlc_interface.h>

@class VLCLegacyCoreInteraction;

/* Port of VLCFSPanelController: a floating translucent transport panel shown
 * while a vout is in fullscreen. NSTrackingArea and global event monitors
 * only exist since 10.5/10.6, so visibility is driven by polling
 * +[NSEvent mouseLocation] from a timer: any mouse move reveals the panel,
 * four idle seconds hide it. */
@interface VLCLegacyFSPanel : NSObject
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;

    NSPanel *panel;
    NSButton *playButton;
    NSSlider *seekSlider;
    NSSlider *volumeSlider;
    NSTextField *timeField;
    NSTextField *durationField;
    NSTextField *mediaTitleField;   /* media title, like the 3.0 panel */
    NSTimer *pollTimer;

    NSPoint lastMouseLocation;
    double lastActivity;    /* NSTimeInterval since reference date */
    BOOL fullscreenActive;
    int dormantTicks;       /* slows the poll down outside fullscreen */
    int lastRunningState;   /* -1 initially; avoids re-tinting the play
                             * button on every poll tick */
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;

/* Starts the polling timer; call once from the main thread */
- (void)activate;
- (void)shutdown;

@end
