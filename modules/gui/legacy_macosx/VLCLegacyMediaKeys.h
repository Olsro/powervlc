/*
 Copyright (c) 2011, Joachim Bengtsson
 All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 * Neither the name of the organization nor the names of its contributors may
   be used to endorse or promote products derived from this software without
   specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
 LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 */

/* Mac OS X 10.4-safe port of SPMediaKeyTap (modern interface): plain
 * ObjC 1 syntax, manual retain/release, no blocks/dispatch. The class is
 * renamed so its runtime name cannot collide with the modern module's
 * SPMediaKeyTap when both plugins live in the same process. The delegate
 * protocol is informal (formal @protocol adoption lists are avoided for
 * old-GCC friendliness); the delegate must implement
 * mediaKeyTap:receivedMediaKey:state:repeat:. */

#import <Cocoa/Cocoa.h>
#import <IOKit/hidsystem/ev_keymap.h>
#import <IOKit/hidsystem/IOLLEvent.h>

/* NS_ENUM is unavailable with old toolchains: plain typedef enums */
typedef enum {
    VLCLegacyMediaKeyPlay        = NX_KEYTYPE_PLAY,
    VLCLegacyMediaKeyNext        = NX_KEYTYPE_NEXT,
    VLCLegacyMediaKeyPrevious    = NX_KEYTYPE_PREVIOUS,
    VLCLegacyMediaKeyFastForward = NX_KEYTYPE_FAST,
    VLCLegacyMediaKeyRewind      = NX_KEYTYPE_REWIND
} VLCLegacyMediaKeyCode;

typedef enum {
    VLCLegacyMediaKeyStateDown = NX_KEYDOWN,
    VLCLegacyMediaKeyStateUp   = NX_KEYUP
} VLCLegacyMediaKeyState;

@interface VLCLegacyMediaKeyTap : NSObject
{
    CFMachPortRef eventPort;
    CFRunLoopSourceRef eventPortSource;
    id delegate;                    /* not retained */
    /* the app that is frontmost in this list owns the media keys
     * (entries are NSRunningApplication instances, 10.6+ only) */
    NSMutableArray *mediaKeyAppList;
    /* ≤10.5 fallback: no NSRunningApplication, intercept only while
     * this application is active */
    BOOL usesActivationFallback;
}

- (id)initWithDelegate:(id)aDelegate;

/* Returns NO when the event tap cannot be installed (no accessibility
 * permission, or [NSEvent eventWithCGEvent:] missing on 10.4). */
- (BOOL)startWatchingMediaKeys;
- (void)stopWatchingMediaKeys;
@end

/* Method definitions for the delegate of VLCLegacyMediaKeyTap */
@interface NSObject(VLCLegacyMediaKeyTapDelegate)
- (void)mediaKeyTap:(VLCLegacyMediaKeyTap *)keyTap
   receivedMediaKey:(int)keyCode
              state:(int)keyState
             repeat:(BOOL)isRepeat;
@end
