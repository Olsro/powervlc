/*****************************************************************************
 * VLCLegacyMediaInfo.h: media information window for the legacy interface
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
#include <vlc_input_item.h>

@class VLCLegacyCoreInteraction;

/* number of editable metadata rows of the General pane (2.2 layout) */
#define MEDIA_INFO_META_COUNT 12

/* Port of the 2.2/3.0 "Media Information" HUD panel: dark rounded
 * borderless window with General (editable metadata + artwork +
 * Save Metadata), Codec Details, and Statistics panes, refreshed while
 * visible. The HUD look is drawn manually: NSHUDWindowMask is 10.6+ and
 * 2.2 itself used the bundled BGHUDAppKit for the same purpose. */
@interface VLCLegacyMediaInfo : NSObject
{
    intf_thread_t *p_intf;
    VLCLegacyCoreInteraction *core;

    NSPanel *window;
    NSView *paneContainer;
    NSView *panes[3];               /* retained; swapped manually (a
                                     * tabless NSTabView paints a plain
                                     * grey area on old AppKit) */
    NSButton *tabButtons[3];
    NSView *tabHighlight;           /* marks the selected pane button */
    NSTimer *refreshTimer;
    void *lastItem;                 /* input_item_t last filled in */
    input_item_t *inspectedItem;    /* held item selected in the browser;
                                     * NULL means follow current playback */

    /* general pane */
    NSImageView *artworkView;
    NSTextField *metaFields[MEDIA_INFO_META_COUNT];
    NSTextField *uriField;

    /* codec details pane: the per-stream tree published by the demuxers
     * and decoders (input_item_t categories), same source as the modern
     * interface, shown with disclosure triangles */
    NSOutlineView *streamsOutline;
    NSMutableArray *streamNodes;    /* top level VLCLegacyInfoNode's */
    NSString *streamsSignature;     /* rebuild only when contents change */

    /* statistics pane */
    NSTextField *readBytesField;
    NSTextField *inputBitrateField;
    NSTextField *demuxBytesField;
    NSTextField *demuxBitrateField;
    NSTextField *videoDecodedField;
    NSTextField *displayedField;
    NSTextField *lostFramesField;
    NSTextField *videoCacheField;
    NSTextField *videoCacheMemField;
    NSTextField *audioDecodedField;
    NSTextField *playedABuffersField;
    NSTextField *lostABuffersField;
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction;
- (void)showWindow;
- (void)showWindowForInputItem:(input_item_t *)item;
- (void)refresh:(NSTimer *)timer;

@end
