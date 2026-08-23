/*****************************************************************************
 * VLCConnectToServerDialog.h: Connect to Server dialog
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by the
 * Free Software Foundation; either version 2, or (at your option) any later
 * version.
 *****************************************************************************/

#import <Cocoa/Cocoa.h>

extern NSString * const VLCConnectToServerRecentsKey;

@interface VLCConnectToServerDialog : NSObject
- (void)show;
@end
