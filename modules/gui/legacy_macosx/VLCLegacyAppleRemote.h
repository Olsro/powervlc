/*****************************************************************************
 * VLCLegacyAppleRemote.h
 *****************************************************************************
 * Created by Martin Kahr on 11.03.06 under a MIT-style license.
 * Copyright (c) 2006 martinkahr.com. All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included
 * in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
 * THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 *
 *****************************************************************************
 *
 * Note that changes made by any members or contributors of the VideoLAN team
 * (i.e. changes that were checked in exclusively into one of VideoLAN's
 * source code repositories) are licensed under the GNU General Public
 * License version 2, or (at your option) any later version.
 * Thus, the following statements apply to our changes:
 *
 * Copyright (C) 2006-2007 VLC authors and VideoLAN
 * Authors: Eric Petit <titer@m0k.org>
 *          Felix Kühne <fkuehne at videolan dot org>
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301,
 * USA.
 *****************************************************************************/

/* Mac OS X 10.4-safe port of AppleRemote.h/m (modern interface): plain
 * ObjC 1 syntax, no properties, manual retain/release. The class is
 * renamed so its runtime name cannot collide with the modern module's
 * AppleRemote when both plugins live in the same process. Not a
 * singleton; the owner keeps one instance and is its (unretained)
 * delegate, responding to appleRemoteButton:pressedDown:clickCount:. */

#import <Cocoa/Cocoa.h>
#import <mach/mach.h>
#import <mach/mach_error.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOCFPlugIn.h>
#import <IOKit/hid/IOHIDLib.h>
#import <IOKit/hid/IOHIDKeys.h>

enum AppleRemoteEventIdentifier
{
    kRemoteButtonVolume_Plus        =1<<1,
    kRemoteButtonVolume_Minus       =1<<2,
    kRemoteButtonMenu               =1<<3,
    kRemoteButtonPlay               =1<<4,
    kRemoteButtonRight              =1<<5,
    kRemoteButtonLeft               =1<<6,
    kRemoteButtonRight_Hold         =1<<7,
    kRemoteButtonLeft_Hold          =1<<8,
    kRemoteButtonMenu_Hold          =1<<9,
    kRemoteButtonPlay_Sleep         =1<<10,
    kRemoteControl_Switched         =1<<11,
    kRemoteButtonVolume_Plus_Hold   =1<<12,
    kRemoteButtonVolume_Minus_Hold  =1<<13,
    k2009RemoteButtonPlay           =1<<14,
    k2009RemoteButtonFullscreen     =1<<15
};
typedef enum AppleRemoteEventIdentifier AppleRemoteEventIdentifier;

@interface VLCLegacyAppleRemote : NSObject
{
    IOHIDDeviceInterface** hidDeviceInterface;
    IOHIDQueueInterface**  queue;
    NSArray*        allCookies;
    NSDictionary*   cookieToButtonMapping;
    CFRunLoopSourceRef eventSource;

    BOOL openInExclusiveMode;
    BOOL simulatesPlusMinusHold;
    BOOL processesBacklog;
    unsigned int clickCountEnabledButtons;
    NSTimeInterval maximumClickCountTimeDifference;

    /* state for simulating plus/minus hold */
    BOOL lastEventSimulatedHold;
    AppleRemoteEventIdentifier lastPlusMinusEvent;
    NSTimeInterval lastPlusMinusEventTime;

    int remoteId;
    NSTimeInterval lastClickCountEventTime;
    AppleRemoteEventIdentifier lastClickCountEvent;
    unsigned int eventClickCount;

    id delegate;
}

- (int)remoteId;
- (BOOL)remoteAvailable;
- (BOOL)listeningToRemote;
- (void)setListeningToRemote:(BOOL)value;

/* Delegates are not retained; must respond to
 * appleRemoteButton:pressedDown:clickCount: */
- (void)setDelegate:(id)aDelegate;
- (id)delegate;

- (BOOL)clickCountingEnabled;
- (void)setClickCountingEnabled:(BOOL)value;
- (unsigned int)clickCountEnabledButtons;
- (void)setClickCountEnabledButtons:(unsigned int)value;
- (NSTimeInterval)maximumClickCountTimeDifference;
- (void)setMaximumClickCountTimeDifference:(NSTimeInterval)value;
- (BOOL)processesBacklog;
- (void)setProcessesBacklog:(BOOL)value;
- (BOOL)openInExclusiveMode;
- (void)setOpenInExclusiveMode:(BOOL)value;
- (BOOL)simulatesPlusMinusHold;
- (void)setSimulatesPlusMinusHold:(BOOL)value;

- (IBAction)startListening:(id)sender;
- (IBAction)stopListening:(id)sender;
@end

/* Method definitions for the delegate of VLCLegacyAppleRemote */
@interface NSObject(VLCLegacyAppleRemoteDelegate)
- (void)appleRemoteButton:(AppleRemoteEventIdentifier)buttonIdentifier
              pressedDown:(BOOL)pressedDown
               clickCount:(unsigned int)count;
@end
