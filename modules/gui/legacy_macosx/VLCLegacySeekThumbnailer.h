/*****************************************************************************
 * VLCLegacySeekThumbnailer.h: seek bar hover thumbnails (legacy interface)
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC authors
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

#include <vlc_common.h>
#include <vlc_interface.h>

@class VLCLegacySeekSlider;

/* Mac OS X 10.2-safe port of VLCSeekThumbnailer: no GCD (10.6+), no
 * blocks, no NSCache (10.6+) — one detached worker NSThread at a time,
 * latest-request-wins, results delivered back on the main thread to
 * -[VLCLegacySeekSlider setHoverThumbnail:forFraction:]. */
@interface VLCLegacySeekThumbnailer : NSObject
{
    NSMutableDictionary *cache;      /* "uri#second" -> NSImage */
    NSMutableArray *cacheOrder;      /* keys, oldest first (FIFO cap) */
    NSString *sceneDirectory;

    BOOL busy;                       /* a worker thread is running */
    /* latest pending request (replaced on every new hover) */
    BOOL hasPending;
    NSString *pendingURI;
    double pendingSeconds;
    double pendingFraction;
    NSString *pendingCacheKey;
    VLCLegacySeekSlider *pendingSlider; /* assign: outlives requests */
}

+ (VLCLegacySeekThumbnailer *)sharedInstance;

/* Main thread only. Answers immediately from the cache, else queues a
 * render; only local files (a network stream would open a second
 * connection). */
- (void)requestThumbnailWithIntf:(intf_thread_t *)intf
                        fraction:(double)fraction
                       forSlider:(VLCLegacySeekSlider *)slider;
@end
