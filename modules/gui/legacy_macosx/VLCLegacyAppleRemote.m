/*****************************************************************************
 * VLCLegacyAppleRemote.m
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
 * (i.e. changes that were exclusively checked in to one of VideoLAN's source
 * code repositories) are licensed under the GNU General Public License
 * version 2, or (at your option) any later version.
 * Thus, the following statements apply to our changes:
 *
 * Copyright (C) 2006-2009 VLC authors and VideoLAN
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

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "VLCLegacyAppleRemote.h"
#import "misc.h"

static const char* AppleRemoteDeviceName = "AppleIRController";
static const int REMOTE_SWITCH_COOKIE = 19;
static const NSTimeInterval DEFAULT_MAXIMUM_CLICK_TIME_DIFFERENCE = 0.35;
static const NSTimeInterval HOLD_RECOGNITION_TIME_INTERVAL = 0.4;

/* private/IOKit categories (informal, ObjC 1) */
@interface VLCLegacyAppleRemote (PrivateMethods)
- (NSDictionary *)cookieToButtonMapping;
- (void)setRemoteId:(int)aValue;
- (IOHIDQueueInterface **)queue;
- (void)handleEventWithCookieString:(NSString *)cookieString
                        sumOfValues:(SInt32)sumOfValues;
@end

@interface VLCLegacyAppleRemote (IOKitMethods)
- (io_object_t)findAppleRemoteDevice;
- (IOHIDDeviceInterface **)createInterfaceForDevice:(io_object_t)hidDevice;
- (BOOL)initializeCookies;
- (BOOL)openDevice;
@end

@implementation VLCLegacyAppleRemote

- (id)init
{
    self = [super init];
    if (self) {
        openInExclusiveMode = YES;
        queue = NULL;
        hidDeviceInterface = NULL;
        NSMutableDictionary *mapping = [[NSMutableDictionary alloc] init];

        /* the HID cookies changed with macOS 10.15 and 10.13 */
        if (VLCLegacyOSVersionAtLeast(10, 15, 0)) {
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Plus]    forKey:@"35_23_22_17_14_4_3_35_23_22_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Minus]   forKey:@"35_23_22_18_14_4_3_35_23_22_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonMenu]           forKey:@"35_24_23_22_4_3_35_24_23_22_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonPlay]           forKey:@"35_25_23_22_4_3_35_25_23_22_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonRight]          forKey:@"35_26_23_22_4_3_35_26_23_22_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonLeft]           forKey:@"35_27_23_22_4_3_35_27_23_22_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonRight_Hold]     forKey:@"35_23_22_16_14_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonLeft_Hold]      forKey:@"35_23_22_15_14_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonMenu_Hold]      forKey:@"35_23_22_4_3_35_23_22_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonPlay_Sleep]     forKey:@"39_35_23_22_4_3_39_35_23_22_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:k2009RemoteButtonPlay]       forKey:@"35_23_22_10_4_3_35_23_22_10_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:k2009RemoteButtonFullscreen] forKey:@"35_23_22_4_3_35_23_22_4_3_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteControl_Switched]     forKey:@"44_35_23_22_4_3_35_23_22_4_3_"];
        } else if (VLCLegacyOSVersionAtLeast(10, 6, 0)) {
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Plus]    forKey:@"33_31_30_21_20_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Minus]   forKey:@"33_32_30_21_20_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonMenu]           forKey:@"33_22_21_20_2_33_22_21_20_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonPlay]           forKey:@"33_23_21_20_2_33_23_21_20_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonRight]          forKey:@"33_24_21_20_2_33_24_21_20_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonLeft]           forKey:@"33_25_21_20_2_33_25_21_20_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonRight_Hold]     forKey:@"33_21_20_14_12_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonLeft_Hold]      forKey:@"33_21_20_13_12_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonMenu_Hold]      forKey:@"33_21_20_2_33_21_20_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonPlay_Sleep]     forKey:@"37_33_21_20_2_37_33_21_20_2_"];
            [mapping setObject:[NSNumber numberWithInt:k2009RemoteButtonPlay]       forKey:@"33_21_20_8_2_33_21_20_8_2_"];
            [mapping setObject:[NSNumber numberWithInt:k2009RemoteButtonFullscreen] forKey:@"33_21_20_3_2_33_21_20_3_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteControl_Switched]     forKey:@"42_33_23_21_20_2_33_23_21_20_2_"];

            if (VLCLegacyOSVersionAtLeast(10, 13, 0)) {
                [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Plus]  forKey:@"33_21_20_15_12_2_"];
                [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Minus] forKey:@"33_21_20_16_12_2_"];
            }
        } else if (VLCLegacyOSVersionAtLeast(10, 5, 0)) {
            /* Leopard (10.5.x). The HID element cookies sit at a lower base
             * offset than on Snow Leopard, and — unlike 10.6+ — every button
             * string embeds cookie 19 (see the switch-cookie handling in
             * QueueCallbackFunction, which is disabled below 10.6). Hold
             * values are best-effort; if a button is silent, read the cookie
             * string the callback logs and correct the key here. */
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Plus]    forKey:@"31_29_28_19_18_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Minus]   forKey:@"31_30_28_19_18_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonMenu]           forKey:@"31_20_19_18_31_20_19_18_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonPlay]           forKey:@"31_21_19_18_31_21_19_18_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonRight]          forKey:@"31_22_19_18_31_22_19_18_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonLeft]           forKey:@"31_23_19_18_31_23_19_18_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonRight_Hold]     forKey:@"31_19_18_4_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonLeft_Hold]      forKey:@"31_19_18_3_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonMenu_Hold]      forKey:@"31_19_18_31_19_18_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonPlay_Sleep]     forKey:@"35_31_19_18_35_31_19_18_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteControl_Switched]     forKey:@"19_"];
        } else {
            /* Tiger (10.4.x). Base offset lower still; switch cookie 19 is
             * delivered on its own here, so it is not embedded in the button
             * strings (contrast 10.5 above). */
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Plus]    forKey:@"14_12_11_6_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonVolume_Minus]   forKey:@"14_13_11_6_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonMenu]           forKey:@"14_7_6_14_7_6_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonPlay]           forKey:@"14_8_6_14_8_6_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonRight]          forKey:@"14_9_6_14_9_6_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonLeft]           forKey:@"14_10_6_14_10_6_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonRight_Hold]     forKey:@"14_6_4_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonLeft_Hold]      forKey:@"14_6_3_2_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonMenu_Hold]      forKey:@"14_6_14_6_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteButtonPlay_Sleep]     forKey:@"18_14_6_18_14_6_"];
            [mapping setObject:[NSNumber numberWithInt:kRemoteControl_Switched]     forKey:@"19_"];
        }

        cookieToButtonMapping = [[NSDictionary alloc]
            initWithDictionary:mapping];
        [mapping release];

        /* defaults */
        simulatesPlusMinusHold = YES;
        maximumClickCountTimeDifference =
            DEFAULT_MAXIMUM_CLICK_TIME_DIFFERENCE;
    }
    return self;
}

- (void)dealloc
{
    [self stopListening:self];
    [cookieToButtonMapping release];
    cookieToButtonMapping = nil;
    [super dealloc];
}

- (int)remoteId
{
    return remoteId;
}

- (BOOL)remoteAvailable
{
    io_object_t hidDevice = [self findAppleRemoteDevice];
    if (hidDevice != 0) {
        IOObjectRelease(hidDevice);
        return YES;
    }
    return NO;
}

- (BOOL)listeningToRemote
{
    return (hidDeviceInterface != NULL && allCookies != NULL
            && queue != NULL);
}

- (void)setListeningToRemote:(BOOL)value
{
    if (value == NO)
        [self stopListening:self];
    else
        [self startListening:self];
}

/* Delegates are not retained (standard Cocoa delegate ownership) */
- (void)setDelegate:(id)aDelegate
{
    if (aDelegate && [aDelegate respondsToSelector:
            @selector(appleRemoteButton:pressedDown:clickCount:)] == NO)
        return;
    delegate = aDelegate;
}

- (id)delegate
{
    return delegate;
}

- (BOOL)clickCountingEnabled
{
    return clickCountEnabledButtons != 0;
}

- (void)setClickCountingEnabled:(BOOL)value
{
    if (value)
        [self setClickCountEnabledButtons:
            kRemoteButtonVolume_Plus | kRemoteButtonVolume_Minus
          | kRemoteButtonPlay | kRemoteButtonLeft | kRemoteButtonRight
          | kRemoteButtonMenu | k2009RemoteButtonPlay
          | k2009RemoteButtonFullscreen];
    else
        [self setClickCountEnabledButtons:0];
}

- (unsigned int)clickCountEnabledButtons
{
    return clickCountEnabledButtons;
}

- (void)setClickCountEnabledButtons:(unsigned int)value
{
    clickCountEnabledButtons = value;
}

- (NSTimeInterval)maximumClickCountTimeDifference
{
    return maximumClickCountTimeDifference;
}

- (void)setMaximumClickCountTimeDifference:(NSTimeInterval)value
{
    maximumClickCountTimeDifference = value;
}

- (BOOL)processesBacklog
{
    return processesBacklog;
}

- (void)setProcessesBacklog:(BOOL)value
{
    processesBacklog = value;
}

- (BOOL)openInExclusiveMode
{
    return openInExclusiveMode;
}

- (void)setOpenInExclusiveMode:(BOOL)value
{
    openInExclusiveMode = value;
}

- (BOOL)simulatesPlusMinusHold
{
    return simulatesPlusMinusHold;
}

- (void)setSimulatesPlusMinusHold:(BOOL)value
{
    simulatesPlusMinusHold = value;
}

- (IBAction)startListening:(id)sender
{
    (void)sender;
    if ([self listeningToRemote])
        return;

    io_object_t hidDevice = [self findAppleRemoteDevice];
    if (hidDevice == 0)
        return;

    if ([self createInterfaceForDevice:hidDevice] == NULL)
        goto error;

    if ([self initializeCookies] == NO)
        goto error;

    if ([self openDevice] == NO)
        goto error;
    goto cleanup;

error:
    [self stopListening:self];

cleanup:
    IOObjectRelease(hidDevice);
}

- (IBAction)stopListening:(id)sender
{
    (void)sender;
    if (eventSource != NULL) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), eventSource,
                              kCFRunLoopDefaultMode);
        CFRelease(eventSource);
        eventSource = NULL;
    }
    if (queue != NULL) {
        (*queue)->stop(queue);
        (*queue)->dispose(queue);
        (*queue)->Release(queue);
        queue = NULL;
    }

    if (allCookies != nil) {
        [allCookies release];
        allCookies = nil;
    }

    if (hidDeviceInterface != NULL) {
        (*hidDeviceInterface)->close(hidDeviceInterface);
        (*hidDeviceInterface)->Release(hidDeviceInterface);
        hidDeviceInterface = NULL;
    }
}

@end

@implementation VLCLegacyAppleRemote (PrivateMethods)

- (void)setRemoteId:(int)value
{
    remoteId = value;
}

- (IOHIDQueueInterface **)queue
{
    return queue;
}

- (NSDictionary *)cookieToButtonMapping
{
    return cookieToButtonMapping;
}

- (NSString *)validCookieSubstring:(NSString *)cookieString
{
    if (cookieString == nil || [cookieString length] == 0)
        return nil;
    NSEnumerator *keyEnum = [[self cookieToButtonMapping] keyEnumerator];
    NSString *key;
    while ((key = [keyEnum nextObject])) {
        NSRange range = [cookieString rangeOfString:key];
        if (range.location == 0)
            return key;
    }
    return nil;
}

- (void)sendSimulatedPlusMinusEvent:(id)time
{
    BOOL startSimulateHold = NO;
    AppleRemoteEventIdentifier event = lastPlusMinusEvent;
    @synchronized(self) {
        startSimulateHold = (lastPlusMinusEvent > 0
            && lastPlusMinusEventTime == [time doubleValue]);
    }
    if (startSimulateHold) {
        lastEventSimulatedHold = YES;
        event = (event == kRemoteButtonVolume_Plus)
            ? kRemoteButtonVolume_Plus_Hold
            : kRemoteButtonVolume_Minus_Hold;
        [delegate appleRemoteButton:event pressedDown:YES clickCount:1];
    }
}

- (void)sendRemoteButtonEvent:(AppleRemoteEventIdentifier)event
                  pressedDown:(BOOL)pressedDown
{
    if (!delegate)
        return;

    if (simulatesPlusMinusHold) {
        if (event == kRemoteButtonVolume_Plus
         || event == kRemoteButtonVolume_Minus) {
            if (pressedDown) {
                lastPlusMinusEvent = event;
                lastPlusMinusEventTime =
                    [NSDate timeIntervalSinceReferenceDate];
                [self performSelector:@selector(sendSimulatedPlusMinusEvent:)
                           withObject:[NSNumber numberWithDouble:
                               lastPlusMinusEventTime]
                           afterDelay:HOLD_RECOGNITION_TIME_INTERVAL];
                return;
            } else {
                if (lastEventSimulatedHold) {
                    event = (event == kRemoteButtonVolume_Plus)
                        ? kRemoteButtonVolume_Plus_Hold
                        : kRemoteButtonVolume_Minus_Hold;
                    lastPlusMinusEvent = 0;
                    lastEventSimulatedHold = NO;
                } else {
                    @synchronized(self) {
                        lastPlusMinusEvent = 0;
                    }
                    pressedDown = YES;
                }
            }
        }
    }

    if ((clickCountEnabledButtons & event) == (unsigned int)event) {
        if (pressedDown == NO && (event == kRemoteButtonVolume_Minus
                               || event == kRemoteButtonVolume_Plus))
            return; /* this one is triggered automatically by the handler */
        NSNumber *eventNumber;
        NSNumber *timeNumber;
        @synchronized(self) {
            lastClickCountEventTime =
                [NSDate timeIntervalSinceReferenceDate];
            if (lastClickCountEvent == event)
                eventClickCount = eventClickCount + 1;
            else
                eventClickCount = 1;
            lastClickCountEvent = event;
            timeNumber = [NSNumber numberWithDouble:
                lastClickCountEventTime];
            eventNumber = [NSNumber numberWithUnsignedInt:event];
        }
        [self performSelector:@selector(executeClickCountEvent:)
                   withObject:[NSArray arrayWithObjects:
                       eventNumber, timeNumber, nil]
                   afterDelay:maximumClickCountTimeDifference];
    } else {
        [delegate appleRemoteButton:event pressedDown:pressedDown
                         clickCount:1];
    }
}

- (void)executeClickCountEvent:(NSArray *)values
{
    AppleRemoteEventIdentifier event =
        [[values objectAtIndex:0] unsignedIntValue];
    NSTimeInterval eventTimePoint =
        [[values objectAtIndex:1] doubleValue];

    BOOL finishedClicking = NO;
    int finalClickCount = eventClickCount;

    @synchronized(self) {
        finishedClicking = (event != lastClickCountEvent
            || eventTimePoint == lastClickCountEventTime);
        if (finishedClicking)
            eventClickCount = 0;
    }

    if (finishedClicking) {
        [delegate appleRemoteButton:event pressedDown:YES
                         clickCount:finalClickCount];
        if (simulatesPlusMinusHold == NO
         && (event == kRemoteButtonVolume_Minus
          || event == kRemoteButtonVolume_Plus)) {
            /* trigger a button release event, too */
            [NSThread sleepUntilDate:
                [NSDate dateWithTimeIntervalSinceNow:0.1]];
            [delegate appleRemoteButton:event pressedDown:NO
                             clickCount:finalClickCount];
        }
    }
}

- (void)handleEventWithCookieString:(NSString *)cookieString
                        sumOfValues:(SInt32)sumOfValues
{
    if (cookieString == nil || [cookieString length] == 0)
        return;
    NSNumber *buttonId =
        [[self cookieToButtonMapping] objectForKey:cookieString];
    if (buttonId != nil) {
        [self sendRemoteButtonEvent:(AppleRemoteEventIdentifier)
                [buttonId intValue]
                        pressedDown:(sumOfValues > 0)];
    } else {
        /* a number of events may be stored in the cookie string when the
         * main thread was too busy to handle them in time */
        NSString *subCookieString;
        NSString *lastSubCookieString = nil;
        while ((subCookieString =
                    [self validCookieSubstring:cookieString])) {
            cookieString = [cookieString substringFromIndex:
                [subCookieString length]];
            lastSubCookieString = subCookieString;
            if (processesBacklog)
                [self handleEventWithCookieString:subCookieString
                                      sumOfValues:sumOfValues];
        }
        if (processesBacklog == NO && lastSubCookieString != nil) {
            /* process the last event of the backlog and assume that the
             * button is not pressed down any longer */
            [self handleEventWithCookieString:lastSubCookieString
                                  sumOfValues:0];
        }
        if ([cookieString length] > 0)
            NSLog(@"VLCLegacyAppleRemote: unknown AR button for "
                  @"cookiestring %@", cookieString);
    }
}

@end

/* Callback method for the device queue: called for any event of any type
 * (cookie) to which we subscribe */
static void QueueCallbackFunction(void *target, IOReturn result,
                                  void *refcon, void *sender)
{
    (void)refcon; (void)sender;
    VLCLegacyAppleRemote *remote = (VLCLegacyAppleRemote *)target;

    IOHIDEventStruct event;
    AbsoluteTime     zeroTime = {0,0};
    NSMutableString *cookieString = [NSMutableString string];
    SInt32           sumOfValues = 0;

    /* On 10.6+, cookie 19 is a dedicated "remote switched" element delivered
     * on its own, so we intercept it. On 10.4/10.5 the value 19 is part of
     * every button's cookie string (e.g. "31_..._19_18_"), so intercepting it
     * would corrupt the string and spuriously fire kRemoteControl_Switched on
     * every press — there it must flow into the string like any other element.*/
    BOOL interceptSwitchCookie = VLCLegacyOSVersionAtLeast(10, 6, 0);

    while (result == kIOReturnSuccess) {
        result = (*[remote queue])->getNextEvent([remote queue], &event,
                                                 zeroTime, 0);
        if (result != kIOReturnSuccess)
            continue;

        if (interceptSwitchCookie
         && REMOTE_SWITCH_COOKIE == (int)(long)event.elementCookie) {
            [remote setRemoteId:event.value];
            [remote handleEventWithCookieString:@"19_" sumOfValues:0];
        } else {
            if (((int)(long)event.elementCookie) != 5) {
                sumOfValues += event.value;
                [cookieString appendString:[NSString stringWithFormat:
                    @"%d_", (int)(long)event.elementCookie]];
            }
        }
    }

    [remote handleEventWithCookieString:cookieString
                            sumOfValues:sumOfValues];
}

@implementation VLCLegacyAppleRemote (IOKitMethods)

- (IOHIDDeviceInterface **)createInterfaceForDevice:(io_object_t)hidDevice
{
    io_name_t             className;
    IOCFPlugInInterface **plugInInterface = NULL;
    HRESULT               plugInResult = S_OK;
    SInt32                score = 0;
    IOReturn              ioReturnValue = kIOReturnSuccess;

    hidDeviceInterface = NULL;

    ioReturnValue = IOObjectGetClass(hidDevice, className);
    if (ioReturnValue != kIOReturnSuccess) {
        NSLog(@"VLCLegacyAppleRemote: failed to get IOKit class name.");
        return NULL;
    }

    ioReturnValue = IOCreatePlugInInterfaceForService(hidDevice,
                        kIOHIDDeviceUserClientTypeID,
                        kIOCFPlugInInterfaceID,
                        &plugInInterface,
                        &score);
    if (ioReturnValue == kIOReturnSuccess) {
        plugInResult = (*plugInInterface)->QueryInterface(plugInInterface,
            CFUUIDGetUUIDBytes(kIOHIDDeviceInterfaceID),
            (LPVOID)&hidDeviceInterface);
        if (plugInResult != S_OK)
            NSLog(@"VLCLegacyAppleRemote: couldn't create HID class "
                  @"device interface");
        if (plugInInterface)
            (*plugInInterface)->Release(plugInInterface);
    }
    return hidDeviceInterface;
}

- (io_object_t)findAppleRemoteDevice
{
    CFMutableDictionaryRef hidMatchDictionary = NULL;
    IOReturn ioReturnValue = kIOReturnSuccess;
    io_iterator_t hidObjectIterator = 0;
    io_object_t hidDevice = 0;

    /* Set up a matching dictionary to search the I/O Registry by class
     * name for all HID class devices */
    hidMatchDictionary = IOServiceMatching(AppleRemoteDeviceName);

    /* Now search I/O Registry for matching devices */
    ioReturnValue = IOServiceGetMatchingServices(kIOMasterPortDefault,
        hidMatchDictionary, &hidObjectIterator);

    if ((ioReturnValue == kIOReturnSuccess) && (hidObjectIterator != 0))
        hidDevice = IOIteratorNext(hidObjectIterator);

    IOObjectRelease(hidObjectIterator);

    return hidDevice;
}

- (BOOL)initializeCookies
{
    IOHIDDeviceInterface122 **handle =
        (IOHIDDeviceInterface122 **)hidDeviceInterface;
    IOHIDElementCookie cookie;
    id                 object;
    NSDictionary      *element;
    CFArrayRef         elementsRef;
    IOReturn           success;

    if (!handle || !(*handle))
        return NO;

    /* Copy all elements: we're grabbing most of the elements for this
     * device anyway, so iterating them ourselves is faster than passing
     * a matching dictionary here. */
    success = (*handle)->copyMatchingElements(handle, NULL, &elementsRef);

    if (success == kIOReturnSuccess) {
        NSArray *elements = (NSArray *)elementsRef;
        NSMutableArray *mutableAllCookies =
            [[NSMutableArray alloc] init];
        NSUInteger elementCount = [elements count];
        NSUInteger i;
        for (i = 0; i < elementCount; i++) {
            element = [elements objectAtIndex:i];

            /* get cookie */
            object = [element valueForKey:
                (NSString *)CFSTR(kIOHIDElementCookieKey)];
            if (object == nil || ![object isKindOfClass:[NSNumber class]])
                continue;
            cookie = (IOHIDElementCookie)(long)[object longValue];

            [mutableAllCookies addObject:
                [NSNumber numberWithInt:(int)(long)cookie]];
        }
        [allCookies release];
        allCookies = [[NSArray alloc] initWithArray:mutableAllCookies];
        [mutableAllCookies release];
    } else {
        if (elementsRef)
            CFRelease(elementsRef);
        return NO;
    }

    if (elementsRef)
        CFRelease(elementsRef);
    return YES;
}

- (BOOL)openDevice
{
    HRESULT result;

    IOHIDOptionsType openMode = kIOHIDOptionsTypeNone;
    if (openInExclusiveMode)
        openMode = kIOHIDOptionsTypeSeizeDevice;
    IOReturn ioReturnValue =
        (*hidDeviceInterface)->open(hidDeviceInterface, openMode);

    if (ioReturnValue == KERN_SUCCESS) {
        queue = (*hidDeviceInterface)->allocQueue(hidDeviceInterface);
        if (queue) {
            /* depth: maximum number of elements in queue before the
             * oldest elements start to be lost */
            result = (*queue)->create(queue, 0, 12);
            (void)result;

            NSUInteger cookieCount = [allCookies count];
            NSUInteger i;
            for (i = 0; i < cookieCount; i++) {
                IOHIDElementCookie cookie = (IOHIDElementCookie)(long)
                    [[allCookies objectAtIndex:i] intValue];
                (*queue)->addElement(queue, cookie, 0);
            }

            /* add callback for async events */
            ioReturnValue = (*queue)->createAsyncEventSource(queue,
                                                             &eventSource);
            if (ioReturnValue == KERN_SUCCESS) {
                ioReturnValue = (*queue)->setEventCallout(queue,
                    QueueCallbackFunction, (void *)self, NULL);
                if (ioReturnValue == KERN_SUCCESS) {
                    CFRunLoopAddSource(CFRunLoopGetCurrent(), eventSource,
                                       kCFRunLoopDefaultMode);
                    /* start data delivery to the queue */
                    (*queue)->start(queue);
                    return YES;
                } else {
                    NSLog(@"VLCLegacyAppleRemote: error when setting "
                          @"event callout");
                }
            } else {
                NSLog(@"VLCLegacyAppleRemote: error when creating async "
                      @"event source");
            }
        } else {
            NSLog(@"VLCLegacyAppleRemote: error when opening HID device");
        }
    }
    return NO;
}

@end
