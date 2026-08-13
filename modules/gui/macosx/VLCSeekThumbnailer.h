/*****************************************************************************
 * VLCSeekThumbnailer.h: seek bar hover thumbnails
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

/* Renders preview thumbnails for the seek bar hover tooltip. VLC 3.0 has
 * no core thumbnailer: a silent secondary input (no audio, dummy video
 * output) is started on the same media with the "scene" video filter
 * writing the decoded frame to a temporary png. Local files only -- a
 * network stream would open a second connection to the server. Requests
 * are serialized, only the latest one is kept, and results are cached. */
@interface VLCSeekThumbnailer : NSObject

+ (VLCSeekThumbnailer *)sharedInstance;

/* Asynchronously produce a thumbnail of the CURRENT playlist item at the
 * given position. The completion is always called on the main thread; the
 * image is nil when no thumbnail can be made (network stream, no video,
 * failure). */
- (void)thumbnailAtFraction:(double)fraction
                 completion:(void (^)(NSImage *image, double fraction))completion;

@end
