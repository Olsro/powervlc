/* Shared Apple-Silicon Dolby HDMI mode selection and restoration.
 * Moved from macosx.m so color-managed Core Animation presentation keeps
 * the same display transport. LGPL-2.1-or-later; see macosx.m.
 * Each plugin supplies distinct Objective-C class names: both modules may
 * be loaded in the same process. All mode changes run on the main thread.
 */
#ifndef VLC_MACOSX_DOVI_DISPLAY_H
#define VLC_MACOSX_DOVI_DISPLAY_H
#if defined(__arm64__)
#import <objc/message.h>
#include <math.h>
#ifndef VLCAssertMainThread
#define VLCAssertMainThread() assert([NSThread isMainThread])
#endif

/* QuartzCore's private CADisplay API is the WindowServer-owned path used by
 * display-management applications for hidden Apple-Silicon connection modes.
 * Declare only the selectors we need and look the class up at runtime: this
 * keeps the 10.4+ builds and non-Apple-Silicon machines independent of the
 * private interface. */
@interface NSObject (VLCCADisplayRuntime)
+ (NSArray *)displays;
- (NSArray *)availableModes;
- (BOOL)isExternal;
- (BOOL)isVirtual;
- (double)refreshRate;
- (id)currentMode;
- (id)hdrMode;
- (id)colorMode;
- (unsigned int)displayId;
- (unsigned long)width;
- (unsigned long)height;
- (unsigned long)bitDepth;
- (unsigned long long)internalRepresentation;
- (void)setCurrentMode:(id)mode;
- (void)update;
@end


typedef struct
{
    CGDirectDisplayID requested_display;
    CGDirectDisplayID selected_display;
    size_t scanout_width;
    size_t scanout_height;
    double scanout_refresh;
    unsigned long current_width;
    unsigned long current_height;
    double current_refresh;
    id saved_mode;
    CGDisplayModeRef saved_cg_mode;
    id termination_restorer;
    unsigned long long saved_mode_id;
    unsigned long long active_mode_id;
    bool changed;
    bool ready;
} VLCDolbyDisplayRequest;

static bool DolbyRefreshMatches(double a, double b)
{
    return fabs(a - b) < 0.02;
}

/* Cocoa contains unrelated width/height selectors with different return
 * types. Calling the private CADisplayMode scalars through explicitly typed
 * objc_msgSend casts avoids Objective-C's ambiguous-selector ABI inference. */
static unsigned long DolbyModeUnsigned(id mode, SEL selector)
{
    return ((unsigned long (*)(id, SEL))objc_msgSend)(mode, selector);
}

static double DolbyModeDouble(id mode, SEL selector)
{
    return ((double (*)(id, SEL))objc_msgSend)(mode, selector);
}

static BOOL DolbyModeBool(id mode, SEL selector)
{
    return ((BOOL (*)(id, SEL))objc_msgSend)(mode, selector);
}

static unsigned long DolbyModeWidth(id mode)
{
    return DolbyModeUnsigned(mode, @selector(width));
}

static unsigned long DolbyModeHeight(id mode)
{
    return DolbyModeUnsigned(mode, @selector(height));
}

static double DolbyModeRefresh(id mode)
{
    return DolbyModeDouble(mode, @selector(refreshRate));
}

static unsigned long long DolbyModeRepresentation(id mode)
{
    return (unsigned long long)DolbyModeUnsigned(
        mode, @selector(internalRepresentation));
}

@interface VLCDolbyTerminationRestorer : NSObject
{
    CGDirectDisplayID _displayId;
    id _savedMode;
    CGDisplayModeRef _savedCGMode;
    unsigned long long _savedModeId;
    BOOL _restored;
    BOOL _terminationSeen;
    BOOL _observing;
}
- (id)initWithDisplay:(CGDirectDisplayID)displayId
            savedMode:(id)savedMode
          savedCGMode:(CGDisplayModeRef)savedCGMode
          savedModeId:(unsigned long long)savedModeId;
- (void)restore;
- (void)invalidate;
- (BOOL)restored;
- (BOOL)terminationSeen;
@end

@implementation VLCDolbyTerminationRestorer

- (id)initWithDisplay:(CGDirectDisplayID)displayId
            savedMode:(id)savedMode
          savedCGMode:(CGDisplayModeRef)savedCGMode
          savedModeId:(unsigned long long)savedModeId
{
    self = [super init];
    if (self != nil)
    {
        _displayId = displayId;
        _savedMode = [savedMode retain];
        _savedCGMode = savedCGMode != NULL
            ? CGDisplayModeRetain(savedCGMode) : NULL;
        _savedModeId = savedModeId;
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(applicationWillTerminate:)
                   name:NSApplicationWillTerminateNotification
                 object:nil];
        _observing = YES;
    }
    return self;
}

- (void)applicationWillTerminate:(NSNotification *)notification
{
    VLC_UNUSED(notification);
    _terminationSeen = YES;
    [self restore];
}

- (void)restore
{
    if (_restored || _savedMode == nil)
        return;

    Class displayClass = NSClassFromString(@"CADisplay");
    if (displayClass == Nil ||
        ![displayClass respondsToSelector:@selector(displays)])
        return;

    for (id display in [(id)displayClass displays])
    {
        if ([display displayId] != _displayId)
            continue;

        id restoreMode = nil;
        for (id mode in [display availableModes])
            if (DolbyModeRepresentation(mode) == _savedModeId)
            {
                restoreMode = mode;
                break;
            }
        if (restoreMode == nil)
            restoreMode = _savedMode;
        if (_savedCGMode != NULL)
            CGDisplaySetDisplayMode(_displayId, _savedCGMode, NULL);
        [display setCurrentMode:restoreMode];
        [display update];
        id active = [display currentMode];
        BOOL cgRestored = _savedCGMode == NULL ||
            (CGDisplayPixelsWide(_displayId) ==
                 CGDisplayModeGetPixelWidth(_savedCGMode) &&
             CGDisplayPixelsHigh(_displayId) ==
                 CGDisplayModeGetPixelHeight(_savedCGMode));
        _restored = cgRestored && active != nil &&
                    DolbyModeRepresentation(active) == _savedModeId;
        return;
    }
}

- (void)invalidate
{
    if (_observing)
    {
        [[NSNotificationCenter defaultCenter] removeObserver:self];
        _observing = NO;
    }
}

- (BOOL)restored
{
    return _restored;
}

- (BOOL)terminationSeen
{
    return _terminationSeen;
}

- (void)dealloc
{
    [self invalidate];
    [_savedMode release];
    if (_savedCGMode != NULL)
        CGDisplayModeRelease(_savedCGMode);
    [super dealloc];
}

@end

static id DolbyModeForDisplay(id display, size_t width, size_t height,
                              double refresh)
{
    id fallback = nil;

    for (id mode in [display availableModes])
    {
        if (DolbyModeBool(mode, @selector(isVirtual)) ||
            DolbyModeWidth(mode) != width ||
            DolbyModeHeight(mode) != height ||
            !DolbyRefreshMatches(DolbyModeRefresh(mode), refresh) ||
            ![[mode hdrMode] isEqual:@"Dolby"])
            continue;

        /* LLDV is source-led: PowerVLC has already applied each frame's RPU
         * and any FEL residual, while DCP supplies the Dolby HDMI tunnel and
         * VSIF expected by the sink. Prefer it to the two sink-led modes. */
        if ([[mode colorMode] isEqual:@"DolbyVisionLowLatency"] &&
            DolbyModeUnsigned(mode, @selector(bitDepth)) >= 12)
            return mode;
        if (fallback == nil)
            fallback = mode;
    }
    return fallback;
}

@interface VLCDolbyDisplayController : NSObject
+ (void)selectDolbyDisplayMode:(NSValue *)value;
+ (void)restoreDolbyDisplayMode:(NSValue *)value;
@end

@implementation VLCDolbyDisplayController
+ (void)selectDolbyDisplayMode:(NSValue *)value
{
    VLCAssertMainThread();
    VLCDolbyDisplayRequest *request = [value pointerValue];
    Class displayClass = NSClassFromString(@"CADisplay");
    if (request == NULL || displayClass == Nil ||
        ![displayClass respondsToSelector:@selector(displays)])
        return;

    id selectedDisplay = nil;
    id selectedMode = nil;
    id selectedCurrent = nil;
    for (id display in [(id)displayClass displays])
    {
        if (![display isExternal] ||
            (request->requested_display != kCGNullDirectDisplay &&
             [display displayId] != request->requested_display))
            continue;

        id current = [display currentMode];
        if (current == nil)
            continue;
        CGDirectDisplayID displayId = [display displayId];
        size_t scanoutWidth = CGDisplayPixelsWide(displayId);
        size_t scanoutHeight = CGDisplayPixelsHigh(displayId);
        double scanoutRefresh = 0.;
        CGDisplayModeRef cgMode = CGDisplayCopyDisplayMode(displayId);
        if (cgMode != NULL)
        {
            scanoutRefresh = CGDisplayModeGetRefreshRate(cgMode);
            CGDisplayModeRelease(cgMode);
        }
        if (scanoutWidth == 0 || scanoutHeight == 0)
        {
            scanoutWidth = DolbyModeWidth(current);
            scanoutHeight = DolbyModeHeight(current);
        }
        if (scanoutRefresh <= 0.)
            scanoutRefresh = DolbyModeRefresh(current);

        request->selected_display = displayId;
        request->scanout_width = scanoutWidth;
        request->scanout_height = scanoutHeight;
        request->scanout_refresh = scanoutRefresh;
        request->current_width = DolbyModeWidth(current);
        request->current_height = DolbyModeHeight(current);
        request->current_refresh = DolbyModeRefresh(current);

        /* CADisplay's private currentMode can temporarily follow the source
         * drawable dimensions while WindowServer still scans out the desktop
         * at another size. Selecting from currentMode caused a 2160p Dolby
         * link over a 1080p framebuffer (desktop in the upper-left quarter).
         * The public CG scanout dimensions are authoritative here. */
        id candidate = DolbyModeForDisplay(display, scanoutWidth,
                                           scanoutHeight, scanoutRefresh);
        if (candidate == nil)
            continue;
        /* With no explicitly selected video device, never guess between
         * two Dolby-capable outputs. */
        if (selectedDisplay != nil &&
            request->requested_display == kCGNullDirectDisplay)
            return;
        selectedDisplay = display;
        selectedCurrent = current;
        selectedMode = candidate;
    }
    if (selectedDisplay == nil || selectedMode == nil)
        return;

    request->selected_display = [selectedDisplay displayId];
    request->active_mode_id = DolbyModeRepresentation(selectedMode);
    if (DolbyModeRepresentation(selectedMode) ==
        DolbyModeRepresentation(selectedCurrent))
    {
        request->ready = true;
        return;
    }

    request->saved_mode = [selectedCurrent retain];
    request->saved_cg_mode =
        CGDisplayCopyDisplayMode(request->selected_display);
    request->saved_mode_id = DolbyModeRepresentation(selectedCurrent);
    [selectedDisplay setCurrentMode:selectedMode];
    [selectedDisplay update];
    id active = [selectedDisplay currentMode];
    if (active != nil &&
        DolbyModeRepresentation(active) == request->active_mode_id)
    {
        request->changed = true;
        request->ready = true;
        request->termination_restorer =
            [[VLCDolbyTerminationRestorer alloc]
                initWithDisplay:request->selected_display
                      savedMode:request->saved_mode
                    savedCGMode:request->saved_cg_mode
                    savedModeId:request->saved_mode_id];
    }
    else
    {
        [request->saved_mode release];
        request->saved_mode = nil;
        if (request->saved_cg_mode != NULL)
        {
            CGDisplayModeRelease(request->saved_cg_mode);
            request->saved_cg_mode = NULL;
        }
    }
}

+ (void)restoreDolbyDisplayMode:(NSValue *)value
{
    VLCAssertMainThread();
    VLCDolbyDisplayRequest *request = [value pointerValue];
    Class displayClass = NSClassFromString(@"CADisplay");
    if (request == NULL || request->saved_mode == nil ||
        displayClass == Nil ||
        ![displayClass respondsToSelector:@selector(displays)])
        return;

    for (id display in [(id)displayClass displays])
    {
        if ([display displayId] != request->selected_display)
            continue;

        id restoreMode = nil;
        for (id mode in [display availableModes])
            if (DolbyModeRepresentation(mode) == request->saved_mode_id)
            {
                restoreMode = mode;
                break;
            }
        if (restoreMode == nil)
            restoreMode = request->saved_mode;
        if (request->saved_cg_mode != NULL)
            CGDisplaySetDisplayMode(request->selected_display,
                                    request->saved_cg_mode, NULL);
        [display setCurrentMode:restoreMode];
        [display update];
        id active = [display currentMode];
        BOOL cgRestored = request->saved_cg_mode == NULL ||
            (CGDisplayPixelsWide(request->selected_display) ==
                 CGDisplayModeGetPixelWidth(request->saved_cg_mode) &&
             CGDisplayPixelsHigh(request->selected_display) ==
                 CGDisplayModeGetPixelHeight(request->saved_cg_mode));
        request->ready = cgRestored && active != nil &&
            DolbyModeRepresentation(active) == request->saved_mode_id;
        return;
    }
}

@end
#endif
#endif
