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

/* Copyright (c) 2010 Spotify AB
 * 10.4-safe ObjC 1 port for the PowerVLC legacy interface, see the
 * matching header for the porting rules. */

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "VLCLegacyMediaKeys.h"

/* the 10.4 SDK only names kCGEventTapOptionListenOnly */
#ifndef kCGEventTapOptionDefault
#if __MAC_OS_X_VERSION_MAX_ALLOWED < 1050
enum { kCGEventTapOptionDefault = 0x00000000 };
#endif
#endif

@interface VLCLegacyMediaKeyTap (Private)
- (void)setShouldInterceptMediaKeyEvents:(BOOL)newSetting;
- (void)startWatchingAppSwitching;
- (void)stopWatchingAppSwitching;
- (void)handleMediaKeyEvent:(NSEvent *)event;
- (void)mediaKeyAppListChanged;
@end

static CGEventRef tapEventCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *refcon);

/* The bundle identifiers of the applications considered to be "media key
 * users": whichever of them was frontmost last owns the keys.
 * dispatch_once is unavailable: lazy init on the main thread only. */
static NSArray *mediaKeyUserBundleIdentifiers(void)
{
    static NSArray *bundleIdentifiers = nil;
    if (bundleIdentifiers == nil) {
        NSString *ourIdentifier = [[NSBundle mainBundle] bundleIdentifier];
        if (ourIdentifier == nil) {
            NSLog(@"VLCLegacyMediaKeyTap: bundle identifier unexpectedly "
                  @"nil, falling back to org.videolan.vlc");
            ourIdentifier = @"org.videolan.vlc";
        }
        bundleIdentifiers = [[NSArray alloc] initWithObjects:
            ourIdentifier, /* our app */
            @"com.spotify.client",
            @"com.apple.iTunes",
            @"com.apple.Music",
            @"com.apple.QuickTimePlayerX",
            @"com.apple.quicktimeplayer",
            @"com.apple.iWork.Keynote",
            @"com.apple.iPhoto",
            @"org.videolan.vlc",
            @"com.apple.Aperture",
            @"com.plexsquared.Plex",
            @"com.soundcloud.desktop",
            @"org.niltsh.MPlayerX",
            @"com.ilabs.PandorasHelper",
            @"com.mahasoftware.pandabar",
            @"com.bitcartel.pandorajam",
            @"org.clementine-player.clementine",
            @"fm.last.Last.fm",
            @"fm.last.Scrobbler",
            @"com.beatport.BeatportPro",
            @"com.Timenut.SongKey",
            @"com.macromedia.fireworks", /* the tap messes up their input */
            @"at.justp.Theremin",
            @"ru.ya.themblsha.YandexMusic",
            @"com.jriver.MediaCenter18",
            @"com.jriver.MediaCenter19",
            @"com.jriver.MediaCenter20",
            @"co.rackit.mate",
            @"com.ttitt.b-music",
            @"com.beardedspice.BeardedSpice",
            @"com.plug.Plug",
            @"com.netease.163music",
            nil];
    }
    return bundleIdentifiers;
}

@implementation VLCLegacyMediaKeyTap

- (id)initWithDelegate:(id)aDelegate
{
    self = [super init];
    if (self) {
        delegate = aDelegate;
        mediaKeyAppList = [[NSMutableArray alloc] init];
        [self startWatchingAppSwitching];
    }
    return self;
}

- (void)dealloc
{
    [self stopWatchingMediaKeys];
    [self stopWatchingAppSwitching];
    [mediaKeyAppList release];
    [super dealloc];
}

- (void)startWatchingAppSwitching
{
    /* Listen to "app switched" events, so that we don't intercept media
     * keys if we weren't the last "media key listening" app to be active.
     * NSRunningApplication (and the workspace notifications carrying it)
     * only exist since 10.6; the constants are spelled as literals so
     * this compiles against the 10.4 SDK. */
    if (NSClassFromString(@"NSRunningApplication") != nil) {
        [[[NSWorkspace sharedWorkspace] notificationCenter]
            addObserver:self
               selector:@selector(frontmostAppChanged:)
                   name:@"NSWorkspaceDidActivateApplicationNotification"
                 object:nil];
        [[[NSWorkspace sharedWorkspace] notificationCenter]
            addObserver:self
               selector:@selector(appTerminated:)
                   name:@"NSWorkspaceDidTerminateApplicationNotification"
                 object:nil];
    } else {
        /* 10.4/10.5 fallback: intercept only while we are active */
        usesActivationFallback = YES;
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(ownActivationChanged:)
                   name:NSApplicationDidBecomeActiveNotification
                 object:nil];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(ownActivationChanged:)
                   name:NSApplicationDidResignActiveNotification
                 object:nil];
    }
}

- (void)stopWatchingAppSwitching
{
    [[[NSWorkspace sharedWorkspace] notificationCenter]
        removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (BOOL)startWatchingMediaKeys
{
    /* [NSEvent eventWithCGEvent:] appeared with 10.5; without it the
     * events cannot be decoded, so do not install the tap at all */
    if (![NSEvent respondsToSelector:@selector(eventWithCGEvent:)])
        return NO;

    /* prevent having multiple taps */
    [self stopWatchingMediaKeys];

    /* Add an event tap to intercept the system defined media key events */
    eventPort = CGEventTapCreate(kCGSessionEventTap,
                                 kCGHeadInsertEventTap,
                                 kCGEventTapOptionDefault,
                                 CGEventMaskBit(NX_SYSDEFINED),
                                 tapEventCallback,
                                 (void *)self);

    /* can be NULL when the app has no accessibility access permission */
    if (eventPort == NULL)
        return NO;

    eventPortSource = CFMachPortCreateRunLoopSource(
        kCFAllocatorSystemDefault, eventPort, 0);
    if (eventPortSource == NULL) {
        CFMachPortInvalidate(eventPort);
        CFRelease(eventPort);
        eventPort = NULL;
        return NO;
    }

    CFRunLoopAddSource(CFRunLoopGetCurrent(), eventPortSource,
                       kCFRunLoopCommonModes);

    [self setShouldInterceptMediaKeyEvents:
        usesActivationFallback ? [NSApp isActive] : YES];

    return YES;
}

- (void)stopWatchingMediaKeys
{
    if (eventPortSource) {
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), eventPortSource,
                              kCFRunLoopCommonModes);
    }
    if (eventPort) {
        CFMachPortInvalidate(eventPort);
        CFRelease(eventPort);
        eventPort = NULL;
    }
    if (eventPortSource) {
        CFRelease(eventPortSource);
        eventPortSource = NULL;
    }
}

- (void)setShouldInterceptMediaKeyEvents:(BOOL)newSetting
{
    if (eventPort == NULL)
        return;
    CGEventTapEnable(eventPort, newSetting);
}

/*****************************************************************************
 * Event tap callback
 *****************************************************************************/

static CGEventRef tapEventCallback(CGEventTapProxy proxy, CGEventType type,
                                   CGEventRef event, void *refcon)
{
    (void)proxy;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    VLCLegacyMediaKeyTap *self = (VLCLegacyMediaKeyTap *)refcon;

    if (type == kCGEventTapDisabledByTimeout) {
        NSLog(@"VLCLegacyMediaKeyTap: media key event tap was disabled "
              @"by timeout");
        /* old GCC forbids self->ivar from a plain C function */
        [self setShouldInterceptMediaKeyEvents:YES];
        [pool release];
        return event;
    } else if (type == kCGEventTapDisabledByUserInput) {
        /* was disabled manually by -setShouldInterceptMediaKeyEvents: */
        [pool release];
        return event;
    } else if (type != NX_SYSDEFINED) {
        /* not a system defined event: do nothing */
        [pool release];
        return event;
    }

    NSEvent *nsEvent = nil;
    @try {
        nsEvent = [NSEvent eventWithCGEvent:event];
    }
    @catch (NSException *e) {
        NSLog(@"VLCLegacyMediaKeyTap: strange CGEventType: %d: %@",
              (int)type, e);
        [pool release];
        return event;
    }

    if ([nsEvent subtype] != NX_SUBTYPE_AUX_CONTROL_BUTTONS) {
        [pool release];
        return event;
    }

    int keyCode = (int)((([nsEvent data1] & 0xFFFF0000) >> 16));
    if (keyCode != NX_KEYTYPE_PLAY &&
        keyCode != NX_KEYTYPE_FAST &&
        keyCode != NX_KEYTYPE_REWIND &&
        keyCode != NX_KEYTYPE_PREVIOUS &&
        keyCode != NX_KEYTYPE_NEXT) {
        [pool release];
        return event;
    }

    [self performSelectorOnMainThread:@selector(handleMediaKeyEvent:)
                           withObject:nsEvent
                        waitUntilDone:NO];

    [pool release];
    return NULL;
}

- (void)handleMediaKeyEvent:(NSEvent *)event
{
    unsigned int eventData = (unsigned int)[event data1];

    int keyCode         = (int)((eventData & 0xFFFF0000) >> 16);
    unsigned eventFlags = (eventData & 0x0000FFFF);

    int keyState        = (int)((eventFlags & 0xFF00) >> 8);
    BOOL keyRepeat      = (eventFlags & 0x1) ? YES : NO;

    if ([delegate respondsToSelector:
            @selector(mediaKeyTap:receivedMediaKey:state:repeat:)])
        [delegate mediaKeyTap:self
             receivedMediaKey:keyCode
                        state:keyState
                       repeat:keyRepeat];
}

/*****************************************************************************
 * Task switching callbacks
 *****************************************************************************/

- (void)mediaKeyAppListChanged
{
    if ([mediaKeyAppList count] == 0)
        return;

    /* NSRunningApplication guaranteed to exist here (10.6+ path only) */
    id thisApp = [NSClassFromString(@"NSRunningApplication")
        performSelector:@selector(currentApplication)];
    id otherApp = [mediaKeyAppList objectAtIndex:0];

    BOOL isCurrent = [thisApp isEqual:otherApp];

    [self setShouldInterceptMediaKeyEvents:isCurrent];
}

- (void)frontmostAppChanged:(NSNotification *)notification
{
    /* userInfo carries an NSRunningApplication under
     * NSWorkspaceApplicationKey; typed as id to compile on 10.4 */
    id app = [[notification userInfo]
        objectForKey:@"NSWorkspaceApplicationKey"];
    NSString *bundleId = [app valueForKey:@"bundleIdentifier"];
    if (bundleId == nil)
        return;

    if (![mediaKeyUserBundleIdentifiers() containsObject:bundleId])
        return;

    [app retain];
    [mediaKeyAppList removeObject:app];
    [mediaKeyAppList insertObject:app atIndex:0];
    [app release];
    [self mediaKeyAppListChanged];
}

- (void)appTerminated:(NSNotification *)notification
{
    id app = [[notification userInfo]
        objectForKey:@"NSWorkspaceApplicationKey"];
    if (app)
        [mediaKeyAppList removeObject:app];

    [self mediaKeyAppListChanged];
}

/* ≤10.5 fallback: track only our own activation state */
- (void)ownActivationChanged:(NSNotification *)notification
{
    [self setShouldInterceptMediaKeyEvents:
        [[notification name] isEqualToString:
            NSApplicationDidBecomeActiveNotification]];
}

@end
