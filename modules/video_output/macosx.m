/*****************************************************************************
 * macosx.m: MacOS X OpenGL provider
 *****************************************************************************
 * Copyright (C) 2001-2013 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Derk-Jan Hartman <hartman at videolan dot org>
 *          Eric Petit <titer@m0k.org>
 *          Benjamin Pracht <bigben at videolan dot org>
 *          Damien Fouilleul <damienf at videolan dot org>
 *          Pierre d'Herbemont <pdherbemont at videolan dot org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
 *          Rémi Denis-Courmont
 *          Juho Vähä-Herttua <juhovh at iki dot fi>
 *          Laurent Aimar <fenrir _AT_ videolan _DOT_ org>
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

/*****************************************************************************
 * Preamble
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#import <OpenGL/OpenGL.h>
#import <dlfcn.h>
#import <IOKit/IOKitLib.h>
#import <Security/Authorization.h>
#import <Security/AuthorizationTags.h>
/* <objc/message.h> is a 10.5+ SDK split; the 10.4u SDK declares
 * objc_msgSend in <objc/objc-runtime.h>. */
#if defined(__has_include)
# if __has_include(<objc/message.h>)
#  import <objc/message.h>
# else
#  import <objc/objc-runtime.h>
# endif
#else
# import <objc/objc-runtime.h>
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>
#include <vlc_opengl.h>
#include <vlc_dialog.h>
#include <unistd.h>
#include "opengl/vout_helper.h"
#include "cgl_lock_compat.h"

#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED < 1050
/* -[NSThread isMainThread] is 10.5+; pthread_main_np() is the 10.4 way */
# include <pthread.h>
# define VLCAssertMainThread() assert(pthread_main_np() != 0)
#else
# define VLCAssertMainThread() assert([[NSThread currentThread] isMainThread])
#endif

/**
 * Forward declarations
 */
static int Open (vlc_object_t *);
static void Close (vlc_object_t *);

static picture_pool_t *Pool (vout_display_t *vd, unsigned requested_count);
static void PictureRender (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture);
static void PictureDisplay (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture);
static int Control (vout_display_t *vd, int query, va_list ap);

static void *OurGetProcAddress(vlc_gl_t *, const char *);

static int OpenglLock (vlc_gl_t *gl);
static void OpenglUnlock (vlc_gl_t *gl);
static void OpenglSwap (vlc_gl_t *gl);

#define DOVI_HDMI_TEXT N_("Use the native Dolby Vision HDMI signal")
#define DOVI_HDMI_LONGTEXT N_( \
    "On Apple Silicon, switch a compatible external display to its hidden " \
    "Dolby Vision connection mode while Dolby Vision video is playing. " \
    "PowerVLC restores the exact previous connection mode when playback " \
    "stops.")

/**
 * Module declaration
 */
vlc_module_begin ()
    /* Will be loaded even without interface module. see voutgl.m */
    set_shortname ("Mac OS X")
    set_description (N_("Mac OS X OpenGL video output"))
    set_category (CAT_VIDEO)
    set_subcategory (SUBCAT_VIDEO_VOUT)
    set_capability ("vout display", 250)
    set_callbacks (Open, Close)
    add_shortcut ("macosx", "vout_macosx")
    add_bool ("macosx-dovi-hdmi", true, DOVI_HDMI_TEXT,
              DOVI_HDMI_LONGTEXT, true)
    add_glopts ()
vlc_module_end ()

/* Backing-store coordinate helpers: no-op fallback on Mac OS X 10.6,
 * which has no HiDPI displays (points always equal pixels there). */
static inline NSRect vlcConvertRectToBacking(NSView *view, NSRect rect)
{
/* convertRectToBacking: is 10.7+, unknown to older SDKs (no HiDPI there) */
#if !defined(MAC_OS_X_VERSION_MAX_ALLOWED) || MAC_OS_X_VERSION_MAX_ALLOWED >= 1070
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
    if ([view respondsToSelector:@selector(convertRectToBacking:)])
        return [view convertRectToBacking:rect];
#pragma clang diagnostic pop
#else
    (void)view;
#endif
    return rect;
}

static inline NSPoint vlcConvertPointToBacking(NSView *view, NSPoint point)
{
#if !defined(MAC_OS_X_VERSION_MAX_ALLOWED) || MAC_OS_X_VERSION_MAX_ALLOWED >= 1070
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
    if ([view respondsToSelector:@selector(convertPointToBacking:)])
        return [view convertPointToBacking:point];
#pragma clang diagnostic pop
#else
    (void)view;
#endif
    return point;
}

/**
 * Obj-C protocol declaration that drawable-nsobject should follow
 */
@protocol VLCOpenGLVideoViewEmbedding <NSObject>
- (void)addVoutSubview:(NSView *)view;
- (void)removeVoutSubview:(NSView *)view;
@end

typedef struct
{
    id *view;
    BOOL wantsExtendedDynamicRange;
} VLCOpenGLVideoViewCreationRequest;

@interface VLCOpenGLVideoView : NSOpenGLView
{
    vout_display_t *vd;
    BOOL _hasPendingReshape;
}
- (void)setVoutDisplay:(vout_display_t *)vd;
- (id)initWithExtendedDynamicRange:(BOOL)wantsExtendedDynamicRange;
- (void)setVoutFlushing:(BOOL)flushing;
- (void)copyWindowDisplayID:(NSValue *)value;
- (void)fitWindowToStereoDisplay:(NSNumber *)displayNumber;
+ (void)activateForStereoFullscreen:(id)unused;
@end

/* MonitorPanel is a private macOS framework used by System Settings itself.
 * Keep every reference late-bound so old macOS releases remain supported and
 * the plugin has no private-framework load dependency. */
@interface NSObject (VLCMonitorPanelRuntime)
+ (id)sharedMgr;
- (BOOL)tryLockAccess;
- (void)unlockAccess;
- (void)notifyWillReconfigure;
- (void)notifyReconfigure;
- (id)displayWithID:(int)displayID;
- (void)stopMirroringForDisplay:(id)display;
@end

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


#define STEREO_MAX_MIRRORS 16

typedef CFTypeRef VLCIOAVServiceRef;
typedef VLCIOAVServiceRef (*VLCIOAVServiceCreateWithService)(CFAllocatorRef,
                                                             io_service_t);
typedef IOReturn (*VLCIOAVServiceCopyEDID)(VLCIOAVServiceRef, CFDataRef *);
typedef IOReturn (*VLCIOAVServiceSetVirtualEDIDMode)(VLCIOAVServiceRef,
                                                     Boolean, CFDataRef);

typedef struct
{
    uint32_t mode_number;
    uint32_t flags;
    uint32_t width;
    uint32_t height;
    uint32_t depth;
    uint8_t unknown[170];
    uint16_t frequency;
    uint8_t more_unknown[16];
    float density;
} vlc_cgs_display_mode_t;

typedef CGError (*VLCCGSGetCurrentDisplayMode)(CGDirectDisplayID, int *);
typedef void (*VLCCGSGetNumberOfDisplayModes)(CGDirectDisplayID, int *);
typedef void (*VLCCGSGetDisplayModeDescriptionOfLength)(
    CGDirectDisplayID, int, vlc_cgs_display_mode_t *, int);
typedef CGError (*VLCCGSConfigureDisplayMode)(CGDisplayConfigRef,
                                              CGDirectDisplayID, int);
typedef CGError (*VLCConfigureDisplayEnabled)(CGDisplayConfigRef,
                                              CGDirectDisplayID, bool);

/* CGDisplayModeRef arrived in 10.6, while PowerVLC's Intel floor is 10.4.
 * Keep one opaque retained CoreFoundation object in the vout and bridge the
 * modern mode API dynamically. On Tiger/Leopard the object is the historical
 * mode dictionary returned by CGDisplayCurrentMode/AvailableModes. */
typedef CFTypeRef VLCDisplayModeRef;

struct vout_display_sys_t
{
    VLCOpenGLVideoView *glView;
    id<VLCOpenGLVideoViewEmbedding> container;

    vout_window_t *embed;
    vlc_gl_t *gl;
    vout_display_opengl_t *vgl;

    picture_pool_t *pool;
    picture_t *current;
    bool has_first_frame;

    /* Opt-in timing probe for the frame-packed path.  Keep this local to the
     * vout: macosx_gl1 has its own profiler, but current macOS selects this
     * vout_display_opengl-backed module instead. */
    bool profile_on;
    uint64_t profile_prepare;
    uint64_t profile_display;
    uint64_t profile_swap;
    unsigned profile_frames;

    CGDirectDisplayID dovi_display;
    id dovi_saved_mode;
    VLCDisplayModeRef dovi_saved_cg_mode;
    unsigned long long dovi_saved_mode_id;
    unsigned long long dovi_active_mode_id;
    id dovi_termination_restorer;
    bool dovi_mode_changed;
    bool dovi_mode_ready;
    bool dovi_fullscreen_display_overridden;
    int64_t dovi_saved_fullscreen_display;

    CGDirectDisplayID stereo_display;
    VLCDisplayModeRef stereo_saved_mode;
    bool stereo_mode_changed;
    bool stereo_operation_changed;
    bool stereo_private_mode_changed;
    int stereo_saved_private_mode;
    bool stereo_virtual_edid_enabled;
    uint16_t stereo_vendor;
    uint16_t stereo_product;
    uint32_t stereo_serial;
    bool stereo_mode_ready;
    id stereo_saved_dynamic_range_mode;
    unsigned long long stereo_saved_dynamic_range_mode_id;
    unsigned stereo_eye_width;
    unsigned stereo_eye_height;
    bool stereo_fullscreen_forced;
    bool stereo_fullscreen_display_overridden;
    int64_t stereo_saved_fullscreen_display;
    CGDirectDisplayID stereo_mirror_displays[STEREO_MAX_MIRRORS];
    CGDirectDisplayID stereo_mirror_masters[STEREO_MAX_MIRRORS];
    uint32_t stereo_mirror_count;
    CGDirectDisplayID stereo_disabled_displays[STEREO_MAX_MIRRORS];
    uint32_t stereo_disabled_display_count;
    AuthorizationRef stereo_clamshell_authorization;
    FILE *stereo_clamshell_pipe;
    bool stereo_synthetic_clamshell;
    vout_display_place_t place;
};

/* The vout core keeps its vout_thread_t while reopening this display module
 * for a decoder format change. Everything from stereo_display up to place is
 * display-session ownership, whereas the OpenGL/view members before it belong
 * to one module incarnation. Move exactly that contiguous state through a
 * private variable on the persistent vout object. */
#define VLC_STEREO_HANDOFF_SIZE \
    (offsetof(vout_display_sys_t, place) - \
     offsetof(vout_display_sys_t, stereo_display))

static bool AdoptStereoDisplayHandoff(vout_display_t *vd)
{
    void *state = var_GetAddress(vd->obj.parent, "stereo3d-display-state");
    if (state == NULL)
        return false;

    memcpy(&vd->sys->stereo_display, state, VLC_STEREO_HANDOFF_SIZE);
    free(state);
    var_SetAddress(vd->obj.parent, "stereo3d-display-state", NULL);
    /* A failed Open must restore the adopted mode rather than parking it a
     * second time. The core clears this too after a successful ThreadStart. */
    var_SetBool(vd->obj.parent, "stereo3d-vout-reinit", false);
    msg_Info(vd, "adopted active HDMI 3D session for the new video format");
    return vd->sys->stereo_mode_ready;
}

static bool ParkStereoDisplayHandoff(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (!sys->stereo_mode_ready ||
        !var_GetBool(vd->obj.parent, "stereo3d-vout-reinit"))
        return false;

    void *state = malloc(VLC_STEREO_HANDOFF_SIZE);
    if (state == NULL)
        return false;
    memcpy(state, &sys->stereo_display, VLC_STEREO_HANDOFF_SIZE);
    memset(&sys->stereo_display, 0, VLC_STEREO_HANDOFF_SIZE);
    var_Create(vd->obj.parent, "stereo3d-display-state", VLC_VAR_ADDRESS);
    void *stale = var_GetAddress(vd->obj.parent, "stereo3d-display-state");
    if (stale != NULL)
        free(stale);
    var_SetAddress(vd->obj.parent, "stereo3d-display-state", state);
    msg_Info(vd, "keeping HDMI 3D active across the video format change");
    return true;
}

static bool IsFramePackableStereo(video_multiview_mode_t mode);

/* Keep the automatic HDMI 3D choice for the lifetime of the parent vout.
 * Seeking an MVC title can reopen this display module while the same vout is
 * still alive.  Asking synchronously from every Open() both repeats a choice
 * the user has already made and leaves playback without a video output until
 * the replacement dialog is dismissed. */
static bool ShouldSwitchToStereoDisplay(vout_display_t *vd)
{
    const int policy = var_InheritInteger(vd, "stereo3d-display-mode");
    if (policy != 1)
        return policy == 0;

    vlc_object_t *vout = vd->obj.parent;
    static const char decision_var[] = "stereo3d-display-prompt-result";
    if (vout != NULL &&
        (var_Type(vout, decision_var) & VLC_VAR_CLASS) == VLC_VAR_INTEGER)
    {
        const bool switch_display =
            var_GetInteger(vout, decision_var) == 1;
        msg_Dbg(vd, "reusing the HDMI 3D display choice for this playback: %s",
                switch_display ? "change mode" : "keep current mode");
        return switch_display;
    }

    const int answer = vlc_dialog_wait_question(
        vd, VLC_DIALOG_QUESTION_NORMAL,
        _("Keep current mode"), _("Change mode"), NULL,
        _("Blu-ray 3D video detected"), "%s",
        _("Switch the HDMI display to the standardized frame-packed 3D "
          "raster and enter full screen? The current mode will be restored "
          "after playback."));

    if (vout != NULL)
    {
        var_Create(vout, decision_var, VLC_VAR_INTEGER);
        var_SetInteger(vout, decision_var, answer == 1 ? 1 : 0);
    }
    return answer == 1;
}

#if defined(__arm64__)

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

typedef struct
{
    CGDirectDisplayID display;
    id saved_mode;
    unsigned long long saved_mode_id;
    bool changed;
    bool ready;
} VLCStereoSDRDisplayRequest;

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

@interface VLCOpenGLVideoView (VLCDolbyDisplayMode)
+ (void)selectDolbyDisplayMode:(NSValue *)value;
+ (void)restoreDolbyDisplayMode:(NSValue *)value;
+ (void)selectStereoSDRDisplayMode:(NSValue *)value;
+ (void)restoreStereoDynamicRangeMode:(NSValue *)value;
+ (void)restoreStereoDynamicRangeModeAndRelease:(NSValue *)value;
@end

@implementation VLCOpenGLVideoView (VLCDolbyDisplayMode)

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

+ (void)selectStereoSDRDisplayMode:(NSValue *)value
{
    VLCAssertMainThread();
    VLCStereoSDRDisplayRequest *request = [value pointerValue];
    Class displayClass = NSClassFromString(@"CADisplay");
    if (request == NULL || displayClass == Nil ||
        ![displayClass respondsToSelector:@selector(displays)])
        return;

    for (id display in [(id)displayClass displays])
    {
        if ([display displayId] != request->display)
            continue;

        id current = [display currentMode];
        if (current == nil)
            return;
        id hdr = [current hdrMode];
        if (hdr == nil || [hdr isEqual:@"SDR"])
        {
            request->ready = true;
            return;
        }

        id candidate = nil;
        for (id mode in [display availableModes])
        {
            id modeHDR = [mode hdrMode];
            if (DolbyModeWidth(mode) == DolbyModeWidth(current) &&
                DolbyModeHeight(mode) == DolbyModeHeight(current) &&
                DolbyRefreshMatches(DolbyModeRefresh(mode),
                                    DolbyModeRefresh(current)) &&
                (modeHDR == nil || [modeHDR isEqual:@"SDR"]))
            {
                candidate = mode;
                break;
            }
        }
        if (candidate == nil)
            return;

        request->saved_mode = [current retain];
        request->saved_mode_id = DolbyModeRepresentation(current);
        [display setCurrentMode:candidate];
        [display update];
        id active = [display currentMode];
        id activeHDR = [active hdrMode];
        request->ready = active != nil &&
            (activeHDR == nil || [activeHDR isEqual:@"SDR"]);
        request->changed = request->ready;
        if (!request->ready)
        {
            [request->saved_mode release];
            request->saved_mode = nil;
        }
        return;
    }
}

+ (void)restoreStereoDynamicRangeMode:(NSValue *)value
{
    VLCAssertMainThread();
    VLCStereoSDRDisplayRequest *request = [value pointerValue];
    Class displayClass = NSClassFromString(@"CADisplay");
    if (request == NULL || request->saved_mode == nil ||
        displayClass == Nil ||
        ![displayClass respondsToSelector:@selector(displays)])
        return;

    for (id display in [(id)displayClass displays])
    {
        if ([display displayId] != request->display)
            continue;
        id restore = nil;
        for (id mode in [display availableModes])
            if (DolbyModeRepresentation(mode) == request->saved_mode_id)
            {
                restore = mode;
                break;
            }
        [display setCurrentMode:restore != nil ? restore : request->saved_mode];
        [display update];
        id active = [display currentMode];
        request->ready = active != nil &&
            DolbyModeRepresentation(active) == request->saved_mode_id;
        return;
    }
}

+ (void)restoreStereoDynamicRangeModeAndRelease:(NSValue *)value
{
    VLCStereoSDRDisplayRequest *request = [value pointerValue];
    [self restoreStereoDynamicRangeMode:value];
    [request->saved_mode release];
    free(request);
}

@end

#endif /* __arm64__ */

static void SelectStereoSDRDisplayMode(vout_display_t *vd,
                                       bool preserve_for_restore)
{
#if defined(__arm64__)
    vout_display_sys_t *sys = vd->sys;
    VLCStereoSDRDisplayRequest request = {
        .display = sys->stereo_display,
    };
    [VLCOpenGLVideoView
        performSelectorOnMainThread:@selector(selectStereoSDRDisplayMode:)
                         withObject:[NSValue valueWithPointer:&request]
                      waitUntilDone:YES];
    if (request.changed)
    {
        if (preserve_for_restore &&
            sys->stereo_saved_dynamic_range_mode == nil)
        {
            sys->stereo_saved_dynamic_range_mode = request.saved_mode;
            sys->stereo_saved_dynamic_range_mode_id = request.saved_mode_id;
            msg_Info(vd, "disabled HDR on display %u before HDMI 3D mode "
                     "switch", sys->stereo_display);
        }
        else
        {
            /* The private frame-packed timing can inherit/re-enable HDR.
             * Never retain that temporary mode as the desktop restoration
             * target: it would put the display back into the 3D timing when
             * MVC playback closes. */
            [request.saved_mode release];
            msg_Info(vd, "reasserted SDR on display %u after HDMI 3D mode "
                     "switch", sys->stereo_display);
        }
    }
    else if (!request.ready)
        msg_Warn(vd, "could not select an SDR variant of the current HDMI "
                     "display mode for MVC playback");
#else
    VLC_UNUSED(vd);
    VLC_UNUSED(preserve_for_restore);
#endif
}

static void RestoreStereoDynamicRangeMode(vout_display_t *vd)
{
#if defined(__arm64__)
    vout_display_sys_t *sys = vd->sys;
    if (sys->stereo_saved_dynamic_range_mode == nil)
        return;

    /* Close normally runs on the vout thread while the AppKit thread may be
     * blocked in playlist_Destroy() waiting for that same thread. A
     * synchronous main-thread selector here therefore deadlocks shutdown.
     * Transfer the retained CADisplay mode to a heap request and let AppKit
     * restore and release it once its event loop is available again. */
    VLCStereoSDRDisplayRequest *request =
        calloc(1, sizeof(*request));
    if (request == NULL)
    {
        [sys->stereo_saved_dynamic_range_mode release];
        sys->stereo_saved_dynamic_range_mode = nil;
        return;
    }
    request->display = sys->stereo_display;
    request->saved_mode = sys->stereo_saved_dynamic_range_mode;
    request->saved_mode_id = sys->stereo_saved_dynamic_range_mode_id;
    sys->stereo_saved_dynamic_range_mode = nil;

    NSValue *value = [NSValue valueWithPointer:request];
    if ([NSThread isMainThread])
        [VLCOpenGLVideoView
            restoreStereoDynamicRangeModeAndRelease:value];
    else
        [VLCOpenGLVideoView
            performSelectorOnMainThread:
                @selector(restoreStereoDynamicRangeModeAndRelease:)
                             withObject:value
                          waitUntilDone:NO];
#else
    VLC_UNUSED(vd);
#endif
}

static void SelectDolbyDisplayMode(vout_display_t *vd)
{
#if defined(__arm64__)
    vout_display_sys_t *sys = vd->sys;
    if (!vd->fmt.dovi.rpu_present ||
        IsFramePackableStereo(vd->fmt.multiview_mode) ||
        !var_InheritBool(vd, "macosx-dovi-hdmi"))
        return;

    int configured = var_InheritInteger(vd, "macosx-vdev");
    VLCDolbyDisplayRequest request = {
        .requested_display = configured > 0
            ? (CGDirectDisplayID)configured : kCGNullDirectDisplay,
    };
    [VLCOpenGLVideoView
        performSelectorOnMainThread:@selector(selectDolbyDisplayMode:)
                         withObject:[NSValue valueWithPointer:&request]
                      waitUntilDone:YES];
    if (!request.ready)
    {
        msg_Warn(vd, "Dolby Vision video detected, but no matching managed "
                     "Dolby HDMI mode was accepted for display %u "
                     "(CG scanout %zux%zu %.3f Hz; CADisplay %lux%lu "
                     "%.3f Hz; configured display %d)",
                     request.selected_display,
                     request.scanout_width, request.scanout_height,
                     request.scanout_refresh,
                     (unsigned long)request.current_width,
                     (unsigned long)request.current_height,
                     request.current_refresh, configured);
        return;
    }

    sys->dovi_display = request.selected_display;
    sys->dovi_saved_mode = request.saved_mode;
    sys->dovi_saved_cg_mode = request.saved_cg_mode;
    sys->dovi_saved_mode_id = request.saved_mode_id;
    sys->dovi_active_mode_id = request.active_mode_id;
    sys->dovi_termination_restorer = request.termination_restorer;
    sys->dovi_mode_changed = request.changed;
    sys->dovi_mode_ready = true;
    msg_Info(vd, "Dolby Vision HDMI transport active on display %u "
                 "at %zux%zu %.3f Hz (mode %llu; CADisplay was %lux%lu "
                 "%.3f Hz%s)", sys->dovi_display,
                 request.scanout_width, request.scanout_height,
                 request.scanout_refresh,
                 sys->dovi_active_mode_id,
                 (unsigned long)request.current_width,
                 (unsigned long)request.current_height,
                 request.current_refresh,
                 sys->dovi_mode_changed ? "; previous mode saved" : "");
#else
    VLC_UNUSED(vd);
#endif
}

static void SetDolbyFullscreenDisplay(vout_display_t *vd, bool enable)
{
#if defined(__arm64__)
    vout_display_sys_t *sys = vd->sys;
    vlc_object_t *root = VLC_OBJECT(vd);
    while (root->obj.parent != NULL)
        root = root->obj.parent;

    if (enable)
    {
        if (!sys->dovi_fullscreen_display_overridden)
        {
            if (var_Create(root, "dovi-fullscreen-display",
                           VLC_VAR_INTEGER | VLC_VAR_DOINHERIT) != VLC_SUCCESS)
            {
                msg_Warn(vd, "could not publish the Dolby Vision fullscreen "
                             "display target");
                return;
            }
            sys->dovi_saved_fullscreen_display =
                var_GetInteger(root, "dovi-fullscreen-display");
            sys->dovi_fullscreen_display_overridden = true;
        }
        var_SetInteger(root, "dovi-fullscreen-display",
                       (int64_t)(uintptr_t)sys->dovi_display);
    }
    else if (sys->dovi_fullscreen_display_overridden)
    {
        var_SetInteger(root, "dovi-fullscreen-display",
                       sys->dovi_saved_fullscreen_display);
        sys->dovi_fullscreen_display_overridden = false;
    }
#else
    VLC_UNUSED(vd);
    VLC_UNUSED(enable);
#endif
}

static void RestoreDolbyDisplayMode(vout_display_t *vd)
{
#if defined(__arm64__)
    vout_display_sys_t *sys = vd->sys;
    if (!sys->dovi_mode_ready)
        return;

    /* The GUI consumes this transient target independently of whether the
     * HDMI connection mode itself had to change (the projector may already
     * have been in LLDV). Never leave it behind for the next video. */
    SetDolbyFullscreenDisplay(vd, false);
    if (!sys->dovi_mode_changed || sys->dovi_saved_mode == nil)
    {
        sys->dovi_mode_ready = false;
        return;
    }

    VLCDolbyTerminationRestorer *terminationRestorer =
        sys->dovi_termination_restorer;
    if ([terminationRestorer terminationSeen])
    {
        /* NSApplicationWillTerminateNotification is delivered while the main
         * run loop still exists. It is too late to synchronously dispatch to
         * that loop from the later vout teardown. */
        if (![terminationRestorer restored])
            [terminationRestorer restore];
        if ([terminationRestorer restored])
            msg_Info(vd, "restored display %u during application termination "
                         "(mode %llu)", sys->dovi_display,
                         sys->dovi_saved_mode_id);
        else
            msg_Warn(vd, "could not restore display %u during application "
                         "termination", sys->dovi_display);
        [terminationRestorer invalidate];
        [terminationRestorer release];
        sys->dovi_termination_restorer = nil;
        [sys->dovi_saved_mode release];
        sys->dovi_saved_mode = nil;
        if (sys->dovi_saved_cg_mode != NULL)
        {
            CGDisplayModeRelease((CGDisplayModeRef)sys->dovi_saved_cg_mode);
            sys->dovi_saved_cg_mode = NULL;
        }
        sys->dovi_mode_changed = false;
        sys->dovi_mode_ready = false;
        return;
    }

    VLCDolbyDisplayRequest request = {
        .selected_display = sys->dovi_display,
        .saved_mode = sys->dovi_saved_mode,
        .saved_cg_mode = (CGDisplayModeRef)sys->dovi_saved_cg_mode,
        .saved_mode_id = sys->dovi_saved_mode_id,
    };
    [VLCOpenGLVideoView
        performSelectorOnMainThread:@selector(restoreDolbyDisplayMode:)
                         withObject:[NSValue valueWithPointer:&request]
                      waitUntilDone:YES];
    if (request.ready)
        msg_Info(vd, "restored display %u after Dolby Vision playback "
                     "(mode %llu)", sys->dovi_display,
                     sys->dovi_saved_mode_id);
    else
        msg_Warn(vd, "could not verify restoration of display %u after "
                     "Dolby Vision playback", sys->dovi_display);
    [terminationRestorer invalidate];
    [terminationRestorer release];
    sys->dovi_termination_restorer = nil;
    [sys->dovi_saved_mode release];
    sys->dovi_saved_mode = nil;
    if (sys->dovi_saved_cg_mode != NULL)
    {
        CGDisplayModeRelease((CGDisplayModeRef)sys->dovi_saved_cg_mode);
        sys->dovi_saved_cg_mode = NULL;
    }
    sys->dovi_mode_changed = false;
    sys->dovi_mode_ready = false;
#else
    VLC_UNUSED(vd);
#endif
}

static bool DisplayModeIsDictionary(VLCDisplayModeRef mode)
{
    return mode != NULL && CFGetTypeID(mode) == CFDictionaryGetTypeID();
}

static double DisplayModeDictionaryNumber(VLCDisplayModeRef mode,
                                          CFStringRef key)
{
    CFNumberRef value = (CFNumberRef)CFDictionaryGetValue(
        (CFDictionaryRef)mode, key);
    double result = 0.;
    if (value != NULL)
        CFNumberGetValue(value, kCFNumberDoubleType, &result);
    return result;
}

static VLCDisplayModeRef CopyDisplayModeCompat(CGDirectDisplayID display)
{
    typedef CFTypeRef (*CopyModeFunc)(CGDirectDisplayID);
    static CopyModeFunc copy_mode;
    static bool attempted;
    if (!attempted) {
        attempted = true;
        copy_mode = (CopyModeFunc)dlsym(RTLD_DEFAULT,
                                        "CGDisplayCopyDisplayMode");
    }
    if (copy_mode != NULL)
        return copy_mode(display);
    CFDictionaryRef mode = CGDisplayCurrentMode(display);
    return mode != NULL ? CFRetain(mode) : NULL;
}

static CFArrayRef CopyAllDisplayModesCompat(CGDirectDisplayID display)
{
    typedef CFArrayRef (*CopyModesFunc)(CGDirectDisplayID, CFDictionaryRef);
    static CopyModesFunc copy_modes;
    static bool attempted;
    if (!attempted) {
        attempted = true;
        copy_modes = (CopyModesFunc)dlsym(RTLD_DEFAULT,
                                          "CGDisplayCopyAllDisplayModes");
    }
    if (copy_modes != NULL)
        return copy_modes(display, NULL);
    CFArrayRef modes = CGDisplayAvailableModes(display);
    return modes != NULL ? CFRetain(modes) : NULL;
}

static double DisplayModeRawRefresh(VLCDisplayModeRef mode)
{
    if (DisplayModeIsDictionary(mode))
        return DisplayModeDictionaryNumber(mode, kCGDisplayRefreshRate);
    typedef double (*GetRefreshFunc)(CFTypeRef);
    static GetRefreshFunc get_refresh;
    static bool attempted;
    if (!attempted) {
        attempted = true;
        get_refresh = (GetRefreshFunc)dlsym(RTLD_DEFAULT,
                                            "CGDisplayModeGetRefreshRate");
    }
    return get_refresh != NULL ? get_refresh(mode) : 0.;
}

static double DisplayModeRefresh(VLCDisplayModeRef mode)
{
    double refresh = DisplayModeRawRefresh(mode);
    return refresh > 1.0 ? refresh : 60.0;
}

static size_t DisplayModeDimension(VLCDisplayModeRef mode, bool width)
{
    if (DisplayModeIsDictionary(mode))
        return (size_t)DisplayModeDictionaryNumber(
            mode, width ? kCGDisplayWidth : kCGDisplayHeight);
    typedef size_t (*GetDimensionFunc)(CFTypeRef);
    static GetDimensionFunc get_pixel_width, get_pixel_height;
    static GetDimensionFunc get_width, get_height;
    static bool attempted;
    if (!attempted) {
        attempted = true;
        get_pixel_width = (GetDimensionFunc)dlsym(
            RTLD_DEFAULT, "CGDisplayModeGetPixelWidth");
        get_pixel_height = (GetDimensionFunc)dlsym(
            RTLD_DEFAULT, "CGDisplayModeGetPixelHeight");
        get_width = (GetDimensionFunc)dlsym(RTLD_DEFAULT,
                                            "CGDisplayModeGetWidth");
        get_height = (GetDimensionFunc)dlsym(RTLD_DEFAULT,
                                             "CGDisplayModeGetHeight");
    }
    GetDimensionFunc function = width
        ? (get_pixel_width != NULL ? get_pixel_width : get_width)
        : (get_pixel_height != NULL ? get_pixel_height : get_height);
    return function != NULL ? function(mode) : 0;
}

static size_t DisplayModePixelWidth(VLCDisplayModeRef mode)
{
    return DisplayModeDimension(mode, true);
}

static size_t DisplayModePixelHeight(VLCDisplayModeRef mode)
{
    return DisplayModeDimension(mode, false);
}

static uint32_t DisplayModeIdentifier(VLCDisplayModeRef mode)
{
    if (DisplayModeIsDictionary(mode))
        return (uint32_t)DisplayModeDictionaryNumber(mode, kCGDisplayMode);
    typedef uint32_t (*GetModeIDFunc)(CFTypeRef);
    static GetModeIDFunc get_mode_id;
    static bool attempted;
    if (!attempted) {
        attempted = true;
        get_mode_id = (GetModeIDFunc)dlsym(
            RTLD_DEFAULT, "CGDisplayModeGetIODisplayModeID");
    }
    return get_mode_id != NULL ? get_mode_id(mode) : 0;
}

static CGError SetDisplayModeCompat(CGDirectDisplayID display,
                                    VLCDisplayModeRef mode)
{
    if (DisplayModeIsDictionary(mode))
        return CGDisplaySwitchToMode(display, (CFDictionaryRef)mode);
    typedef CGError (*SetModeFunc)(CGDirectDisplayID, CFTypeRef,
                                   CFDictionaryRef);
    static SetModeFunc set_mode;
    static bool attempted;
    if (!attempted) {
        attempted = true;
        set_mode = (SetModeFunc)dlsym(RTLD_DEFAULT,
                                      "CGDisplaySetDisplayMode");
    }
    return set_mode != NULL ? set_mode(display, mode, NULL)
                            : kCGErrorFailure;
}

static bool RefreshNear(double actual, double standard)
{
    return fabs(actual - standard) <= 0.2;
}

static bool IsFramePackableStereo(video_multiview_mode_t mode)
{
    return mode == MULTIVIEW_STEREO_FRAMEPACKED ||
           mode == MULTIVIEW_STEREO_SBS ||
           mode == MULTIVIEW_STEREO_TB ||
           mode == MULTIVIEW_STEREO_SBS_RIGHT_FIRST ||
           mode == MULTIVIEW_STEREO_TB_RIGHT_FIRST;
}

static bool StereoEyeDimensions(const video_format_t *fmt,
                                unsigned *width, unsigned *height)
{
    switch (fmt->multiview_mode)
    {
        case MULTIVIEW_STEREO_FRAMEPACKED:
            *width = fmt->i_visible_width;
            *height = fmt->i_visible_height / 2;
            return true;
        case MULTIVIEW_STEREO_SBS:
        case MULTIVIEW_STEREO_SBS_RIGHT_FIRST:
            /* Half-SBS uses a normal 16:9 coded frame; full-SBS is twice as
             * wide. Both become one standard-sized eye at scanout. */
            *width = fmt->i_visible_width >= 2560
                   ? fmt->i_visible_width / 2 : fmt->i_visible_width;
            *height = fmt->i_visible_height;
            return true;
        case MULTIVIEW_STEREO_TB:
        case MULTIVIEW_STEREO_TB_RIGHT_FIRST:
            *width = fmt->i_visible_width;
            *height = fmt->i_visible_height > fmt->i_visible_width
                    ? fmt->i_visible_height / 2 : fmt->i_visible_height;
            return true;
        default:
            return false;
    }
}

static uint16_t EDIDReadLE16(const uint8_t *p)
{
    return (uint16_t)p[0] | (uint16_t)p[1] << 8;
}

static uint32_t EDIDReadLE32(const uint8_t *p)
{
    return (uint32_t)p[0] | (uint32_t)p[1] << 8 |
           (uint32_t)p[2] << 16 | (uint32_t)p[3] << 24;
}

static void EDIDWriteLE16(uint8_t *p, uint16_t value)
{
    p[0] = value;
    p[1] = value >> 8;
}

static bool EDIDIsValid(CFDataRef data)
{
    static const uint8_t header[8] = {
        0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00
    };
    CFIndex length = data != NULL ? CFDataGetLength(data) : 0;
    if (length < 128 || length > 512 || length % 128 != 0)
        return false;
    const uint8_t *bytes = CFDataGetBytePtr(data);
    if (memcmp(bytes, header, sizeof(header)) != 0 ||
        bytes[126] + 1 != (unsigned)length / 128)
        return false;
    for (CFIndex block = 0; block < length; block += 128)
    {
        unsigned checksum = 0;
        for (unsigned i = 0; i < 128; ++i)
            checksum += bytes[block + i];
        if ((checksum & 0xff) != 0)
            return false;
    }
    return true;
}

static bool EDIDAdvertisesHDMI3D(CFDataRef data)
{
    if (!EDIDIsValid(data))
        return false;
    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);
    for (CFIndex offset = 128; offset + 128 <= length; offset += 128)
    {
        const uint8_t *extension = bytes + offset;
        if (extension[0] != 0x02 || extension[2] < 4 ||
            extension[2] > 127)
            continue;
        unsigned pos = 4;
        while (pos < extension[2])
        {
            unsigned tag = extension[pos] >> 5;
            unsigned size = extension[pos] & 0x1f;
            if (pos + 1 + size > extension[2])
                break;
            const uint8_t *block = extension + pos + 1;
            /* HDMI Licensing VSDB: HDMI video present, 3D present. */
            if (tag == 3 && size >= 9 && block[0] == 0x03 &&
                block[1] == 0x0c && block[2] == 0x00 &&
                (block[7] & 0x20) != 0 && (block[8] & 0x80) != 0)
                return true;
            pos += 1 + size;
        }
    }
    return false;
}

static bool FillFramePackingTiming(uint8_t detailed[20],
                                   size_t eye_width, size_t eye_height,
                                   double rate)
{
    uint32_t pixel_clock;
    uint16_t hblank, hfront, hsync;
    uint16_t packed_height, vblank, vfront, vsync;
    if (eye_width == 1920 && eye_height == 1080 &&
        (RefreshNear(rate, 24.0) ||
         RefreshNear(rate, 24000.0 / 1001.0)))
    {
        pixel_clock = RefreshNear(rate, 24000.0 / 1001.0) ?
                      148351648 : 148500000;
        hblank = 830;
        hfront = 638;
        hsync = 44;
        packed_height = 2205;
        vblank = 45;
        vfront = 4;
        vsync = 5;
    }
    else if (eye_width == 1280 && eye_height == 720 &&
             (RefreshNear(rate, 50.0) || RefreshNear(rate, 60.0) ||
              RefreshNear(rate, 60000.0 / 1001.0)))
    {
        pixel_clock = RefreshNear(rate, 60000.0 / 1001.0) ?
                      148351648 : 148500000;
        bool rate50 = RefreshNear(rate, 50.0);
        hblank = rate50 ? 700 : 370;
        hfront = rate50 ? 440 : 110;
        hsync = 40;
        packed_height = 1470;
        vblank = 30;
        vfront = 5;
        vsync = 5;
    }
    else
        return false;

    memset(detailed, 0, 20);
    uint32_t clock_10khz = (uint32_t)llround(pixel_clock / 10000.0) - 1;
    detailed[0] = clock_10khz;
    detailed[1] = clock_10khz >> 8;
    detailed[2] = clock_10khz >> 16;
    /* DisplayID Type-I detailed timing: stereo, left view first. */
    detailed[3] = 0x20;
    EDIDWriteLE16(detailed + 4, eye_width - 1);
    EDIDWriteLE16(detailed + 6, hblank - 1);
    EDIDWriteLE16(detailed + 8, (hfront - 1) | 0x8000);
    EDIDWriteLE16(detailed + 10, hsync - 1);
    EDIDWriteLE16(detailed + 12, packed_height - 1);
    EDIDWriteLE16(detailed + 14, vblank - 1);
    EDIDWriteLE16(detailed + 16, (vfront - 1) | 0x8000);
    EDIDWriteLE16(detailed + 18, vsync - 1);
    return true;
}

static CFDataRef CopyFramePackingEDID(CFDataRef physical,
                                      size_t eye_width, size_t eye_height,
                                      double rate)
{
    if (!EDIDAdvertisesHDMI3D(physical))
        return NULL;

    uint8_t detailed[40];
    if (!FillFramePackingTiming(detailed, eye_width, eye_height, rate))
        return NULL;

    unsigned detailed_size = 20;
    /* A disc can interleave 23.976 MVC with 25 fps 2D trailers. Publish the
     * standardized 720p50 frame-packed timing alongside 1080p24 from the
     * outset.  The vout can then retune between two already-advertised stereo
     * modes without tearing down the virtual EDID (which would make the
     * projector leave 3D and flash the internal display). */
    if (eye_width == 1920 && eye_height == 1080 &&
        FillFramePackingTiming(detailed + 20, 1280, 720, 50.0))
        detailed_size += 20;

    uint8_t display_id[128] = { 0 };
    display_id[0] = 0x70; /* DisplayID extension */
    display_id[1] = 0x11; /* DisplayID 1.1 */
    display_id[3] = 0x03; /* standalone display device */
    unsigned pos = 5;
    display_id[pos++] = 0x03; /* Type-I detailed timing block */
    display_id[pos++] = 0x00;
    display_id[pos++] = detailed_size;
    memcpy(display_id + pos, detailed, detailed_size);
    pos += detailed_size;
    /* Explicit stacked-frame transport, top half is the left-eye view. */
    static const uint8_t stereo_interface[] = {
        0x10, 0x00, 0x03, 0x00, 0x05, 0x00
    };
    memcpy(display_id + pos, stereo_interface, sizeof(stereo_interface));
    pos += sizeof(stereo_interface);
    static const uint8_t name_block[] = {
        0x0b, 0x00, 0x08, 'P', 'o', 'w', 'e', 'r', 'V', 'L', 'C'
    };
    memcpy(display_id + pos, name_block, sizeof(name_block));
    pos += sizeof(name_block);
    display_id[2] = pos - 5;
    unsigned section_sum = 0;
    for (unsigned i = 1; i < pos; ++i)
        section_sum += display_id[i];
    display_id[pos] = (uint8_t)(-section_sum);
    unsigned extension_sum = 0;
    for (unsigned i = 0; i < 127; ++i)
        extension_sum += display_id[i];
    display_id[127] = (uint8_t)(-extension_sum);

    CFIndex physical_length = CFDataGetLength(physical);
    if (physical_length + 128 > 512)
        return NULL;
    CFMutableDataRef result = CFDataCreateMutable(kCFAllocatorDefault,
                                                   physical_length + 128);
    if (result == NULL)
        return NULL;
    CFDataSetLength(result, physical_length + 128);
    uint8_t *bytes = CFDataGetMutableBytePtr(result);
    memcpy(bytes, CFDataGetBytePtr(physical), physical_length);

    /* Blu-ray 3D frame packing is always SDR.  Apple Silicon otherwise keeps
     * the desktop's HDR transport when entering the private 1920x2205 mode,
     * even after CADisplay has selected an SDR desktop variant.  Remove the
     * sink's HDR signalling from the temporary EDID so DCP cannot emit a PQ
     * or Dolby HDMI infoframe for the private stereo timing. */
    for (CFIndex offset = 128; offset + 128 <= physical_length;
         offset += 128)
    {
        uint8_t *extension = bytes + offset;
        if (extension[0] != 0x02 || extension[2] < 4 ||
            extension[2] > 127)
            continue;
        unsigned data_end = extension[2];
        for (unsigned block_pos = 4; block_pos < data_end;)
        {
            unsigned tag = extension[block_pos] >> 5;
            unsigned size = extension[block_pos] & 0x1f;
            if (block_pos + 1 + size > data_end)
                break;
            uint8_t *block = extension + block_pos + 1;
            /* CTA-861 HDR Static Metadata block (extended tag 0x06). */
            if (tag == 7 && size >= 2 && block[0] == 0x06)
                memset(block + 1, 0, size - 1);
            /* Dolby Vision and HDR10+ vendor-specific blocks. Older CTA
             * revisions use a regular VSDB; this XGIMI (and many modern
             * projectors) puts both OUIs in an Extended Vendor-Specific
             * Video Data Block instead. Preserve its extended tag while
             * clearing the capability payload. */
            if (tag == 3 && size >= 3 &&
                ((block[0] == 0x46 && block[1] == 0xd0 &&
                  block[2] == 0x00) ||
                 (block[0] == 0x8b && block[1] == 0x84 &&
                  block[2] == 0x90)))
                memset(block, 0, size);
            if (tag == 7 && size >= 4 && block[0] == 0x01 &&
                ((block[1] == 0x46 && block[2] == 0xd0 &&
                  block[3] == 0x00) ||
                 (block[1] == 0x8b && block[2] == 0x84 &&
                  block[3] == 0x90)))
                memset(block + 1, 0, size - 1);
            block_pos += 1 + size;
        }
        extension[127] = 0;
        unsigned extension_checksum = 0;
        for (unsigned i = 0; i < 127; ++i)
            extension_checksum += extension[i];
        extension[127] = (uint8_t)(-extension_checksum);
    }
    memcpy(bytes + physical_length, display_id, sizeof(display_id));
    bytes[126] = physical_length / 128;
    bytes[127] = 0;
    unsigned base_sum = 0;
    for (unsigned i = 0; i < 127; ++i)
        base_sum += bytes[i];
    bytes[127] = (uint8_t)(-base_sum);
    if (!EDIDIsValid(result))
    {
        CFRelease(result);
        return NULL;
    }
    return result;
}

static bool LoadIOAVFunctions(VLCIOAVServiceCreateWithService *create,
                              VLCIOAVServiceCopyEDID *copy_edid,
                              VLCIOAVServiceSetVirtualEDIDMode *set_virtual)
{
    *create = (VLCIOAVServiceCreateWithService)
        dlsym(RTLD_DEFAULT, "IOAVServiceCreateWithService");
    *copy_edid = (VLCIOAVServiceCopyEDID)
        dlsym(RTLD_DEFAULT, "IOAVServiceCopyEDID");
    *set_virtual = (VLCIOAVServiceSetVirtualEDIDMode)
        dlsym(RTLD_DEFAULT, "IOAVServiceSetVirtualEDIDMode");
    return *create != NULL && *copy_edid != NULL && *set_virtual != NULL;
}

static bool IOAVServiceIsExternal(io_service_t service)
{
    CFTypeRef value = IORegistryEntryCreateCFProperty(
        service, CFSTR("Location"), kCFAllocatorDefault, 0);
    bool external = value != NULL &&
        CFGetTypeID(value) == CFStringGetTypeID() &&
        CFStringCompare((CFStringRef)value, CFSTR("External"), 0) ==
            kCFCompareEqualTo;
    if (value != NULL)
        CFRelease(value);
    return external;
}

static VLCIOAVServiceRef CopyIOAVServiceForDisplay(
    uint16_t vendor, uint16_t product, uint32_t serial,
    VLCIOAVServiceCreateWithService create,
    VLCIOAVServiceCopyEDID copy_edid, CFDataRef *edid_out)
{
    *edid_out = NULL;
    CFMutableDictionaryRef matching = IOServiceMatching("DCPAVServiceProxy");
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (matching == NULL ||
        IOServiceGetMatchingServices(kIOMasterPortDefault, matching,
                                     &iterator) != kIOReturnSuccess)
        return NULL;

    VLCIOAVServiceRef result = NULL;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL)
    {
        if (IOAVServiceIsExternal(service))
        {
            VLCIOAVServiceRef candidate =
                create(kCFAllocatorDefault, service);
            CFDataRef edid = NULL;
            if (candidate != NULL &&
                copy_edid(candidate, &edid) == kIOReturnSuccess &&
                EDIDIsValid(edid))
            {
                const uint8_t *bytes = CFDataGetBytePtr(edid);
                uint16_t edid_vendor = (uint16_t)bytes[8] << 8 | bytes[9];
                uint16_t edid_product = EDIDReadLE16(bytes + 10);
                uint32_t edid_serial = EDIDReadLE32(bytes + 12);
                if (edid_vendor == vendor && edid_product == product &&
                    (serial == 0 || edid_serial == 0 || edid_serial == serial))
                {
                    result = candidate;
                    *edid_out = edid;
                    candidate = NULL;
                    edid = NULL;
                }
            }
            if (edid != NULL)
                CFRelease(edid);
            if (candidate != NULL)
                CFRelease(candidate);
        }
        IOObjectRelease(service);
        if (result != NULL)
            break;
    }
    IOObjectRelease(iterator);
    return result;
}

static CGDirectDisplayID FindOnlineStereoDisplay(vout_display_sys_t *sys)
{
    CGDirectDisplayID displays[STEREO_MAX_MIRRORS];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(STEREO_MAX_MIRRORS, displays, &count) !=
        kCGErrorSuccess)
        return kCGNullDirectDisplay;
    for (uint32_t i = 0; i < count; ++i)
    {
        uint32_t serial = CGDisplaySerialNumber(displays[i]);
        if (!CGDisplayIsBuiltin(displays[i]) &&
            CGDisplayVendorNumber(displays[i]) == sys->stereo_vendor &&
            CGDisplayModelNumber(displays[i]) == sys->stereo_product &&
            (sys->stereo_serial == 0 || serial == 0 ||
             serial == sys->stereo_serial))
            return displays[i];
    }
    return kCGNullDirectDisplay;
}

static bool DisplayPublishesFramePackingMode(CGDirectDisplayID display,
                                             size_t width, size_t height,
                                             double rate)
{
    CFArrayRef modes = CopyAllDisplayModesCompat(display);
    if (modes == NULL)
        return false;
    bool found = false;
    for (CFIndex i = 0; i < CFArrayGetCount(modes); ++i)
    {
        VLCDisplayModeRef mode =
            (VLCDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
        if (DisplayModePixelWidth(mode) == width &&
            DisplayModePixelHeight(mode) == height &&
            RefreshNear(DisplayModeRawRefresh(mode), rate))
        {
            found = true;
            break;
        }
    }
    CFRelease(modes);
    return found;
}

static CGDirectDisplayID FindAutomaticStereoDisplay(size_t width,
                                                    size_t height,
                                                    double rate)
{
    CGDirectDisplayID displays[STEREO_MAX_MIRRORS];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(STEREO_MAX_MIRRORS, displays, &count) !=
        kCGErrorSuccess)
        return CGMainDisplayID();

    CGDirectDisplayID fallback = kCGNullDirectDisplay;
    for (uint32_t i = 0; i < count; ++i)
    {
        if (CGDisplayIsBuiltin(displays[i]) ||
            !CGDisplayIsOnline(displays[i]))
            continue;
        if (fallback == kCGNullDirectDisplay)
            fallback = displays[i];
        if (DisplayPublishesFramePackingMode(displays[i], width, height, rate))
            return displays[i];
    }
    return fallback != kCGNullDirectDisplay ? fallback : CGMainDisplayID();
}

static bool RunAuthorizedInstaller(AuthorizationRef authorization,
                                   const char *const arguments[])
{
    FILE *communication = NULL;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    OSStatus status = AuthorizationExecuteWithPrivileges(
        authorization, "/usr/bin/install", kAuthorizationFlagDefaults,
        (char *const *)arguments, &communication);
#pragma clang diagnostic pop
    if (status != errAuthorizationSuccess)
        return false;

    /* AuthorizationExecuteWithPrivileges returns after spawning the tool.
     * Waiting for EOF prevents the file install racing the mode check or the
     * next privileged command. */
    if (communication != NULL)
    {
        char discarded[128];
        while (fread(discarded, 1, sizeof(discarded), communication) > 0)
            ;
        fclose(communication);
    }
    return true;
}

static NSData *CopyLegacy1080pFramePackingDTD(double rate)
{
    const unsigned h_active = 1920, h_blank = 830;
    const unsigned h_front = 638, h_sync = 44;
    const unsigned v_active = 2205, v_blank = 45;
    const unsigned v_front = 4, v_sync = 5;
    const unsigned clock_10khz = RefreshNear(rate, 24000.0 / 1001.0)
        ? 14835 : 14850;
    uint8_t dtd[18] = { 0 };
    dtd[0] = clock_10khz & 0xff;
    dtd[1] = clock_10khz >> 8;
    dtd[2] = h_active & 0xff;
    dtd[3] = h_blank & 0xff;
    dtd[4] = ((h_active >> 8) << 4) | (h_blank >> 8);
    dtd[5] = v_active & 0xff;
    dtd[6] = v_blank & 0xff;
    dtd[7] = ((v_active >> 8) << 4) | (v_blank >> 8);
    dtd[8] = h_front & 0xff;
    dtd[9] = h_sync & 0xff;
    dtd[10] = (v_front << 4) | v_sync;
    dtd[11] = ((h_front >> 8) << 6) | ((h_sync >> 8) << 4) |
              ((v_front >> 4) << 2) | (v_sync >> 4);
    dtd[17] = 0x1e; /* digital separate sync, positive H and V */
    return [[NSData alloc] initWithBytes:dtd length:sizeof(dtd)];
}

static NSString *LegacyFramePackingOverridePath(vout_display_sys_t *sys)
{
    return [NSString stringWithFormat:
        @"/System/Library/Displays/Overrides/DisplayVendorID-%x/"
         "DisplayProductID-%x", sys->stereo_vendor, sys->stereo_product];
}

static bool LegacyFramePackingOverrideHasRate(vout_display_sys_t *sys,
                                              double rate)
{
    NSDictionary *contents = [NSDictionary dictionaryWithContentsOfFile:
        LegacyFramePackingOverridePath(sys)];
    NSArray *timings = [contents objectForKey:@"dspc"];
    if (![timings isKindOfClass:[NSArray class]])
        return false;

    NSData *dtd = CopyLegacy1080pFramePackingDTD(rate);
    bool present = [timings containsObject:dtd];
    [dtd release];
    return present;
}

static bool InstallLegacyFramePackingOverride(vout_display_t *vd,
                                              size_t eye_width,
                                              size_t eye_height,
                                              double rate)
{
    vout_display_sys_t *sys = vd->sys;
    if (eye_width != 1920 || eye_height != 1080)
        return false;

    if (vlc_dialog_wait_question(
            vd, VLC_DIALOG_QUESTION_NORMAL, _("Keep current mode"),
            _("Install display timing"), NULL,
            _("One-time HDMI 3D setup"), "%s",
            _("This version of macOS does not yet expose the required "
              "1920x2205 HDMI "
              "timing for this projector. PowerVLC can install it directly. "
              "macOS will request an administrator password and a restart "
              "will be required.")) != 1)
        return false;

    NSString *directory = [NSString stringWithFormat:
        @"/System/Library/Displays/Overrides/DisplayVendorID-%x",
        sys->stereo_vendor];
    NSString *destination = LegacyFramePackingOverridePath(sys);
    NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:
        destination];
    NSMutableDictionary *contents = existing != nil
        ? [[existing mutableCopy] autorelease]
        : [NSMutableDictionary dictionary];
    [contents setObject:[NSNumber numberWithUnsignedInt:sys->stereo_vendor]
                 forKey:@"DisplayVendorID"];
    [contents setObject:[NSNumber numberWithUnsignedInt:sys->stereo_product]
                 forKey:@"DisplayProductID"];

    NSMutableArray *timings = nil;
    id old_timings = [contents objectForKey:@"dspc"];
    if ([old_timings isKindOfClass:[NSArray class]])
        timings = [[old_timings mutableCopy] autorelease];
    else
        timings = [NSMutableArray array];
    NSData *dtd = CopyLegacy1080pFramePackingDTD(rate);
    [timings removeObject:dtd];
    /* CGS rounds both rates to 24. Keep the fractional DTD first so
     * FindPrivateFramePackingMode can distinguish it from true 24.000 Hz by
     * override order on the Mavericks Intel driver. */
    if (RefreshNear(rate, 24000.0 / 1001.0))
        [timings insertObject:dtd atIndex:0];
    else
        [timings addObject:dtd];
    [dtd release];
    [contents setObject:timings forKey:@"dspc"];

    NSString *temporary = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[NSString stringWithFormat:
            @"powervlc-display-%x-%x.plist", sys->stereo_vendor,
            sys->stereo_product]];
    if (![contents writeToFile:temporary atomically:YES])
    {
        msg_Err(vd, "could not create the temporary HDMI display override");
        return false;
    }

    AuthorizationRef authorization = NULL;
    AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed |
                               kAuthorizationFlagExtendRights;
    OSStatus status = AuthorizationCreate(NULL, kAuthorizationEmptyEnvironment,
                                           flags, &authorization);
    bool installed = false;
    if (status == errAuthorizationSuccess)
    {
        const char *mkdir_arguments[] = {
            "-d", "-o", "root", "-g", "wheel", "-m", "755",
            [directory fileSystemRepresentation], NULL
        };
        const char *file_arguments[] = {
            "-o", "root", "-g", "wheel", "-m", "644",
            [temporary fileSystemRepresentation],
            [destination fileSystemRepresentation], NULL
        };
        installed = RunAuthorizedInstaller(authorization, mkdir_arguments) &&
                    RunAuthorizedInstaller(authorization, file_arguments);
        AuthorizationFree(authorization, kAuthorizationFlagDefaults);
    }
    unlink([temporary fileSystemRepresentation]);

    installed = installed && LegacyFramePackingOverrideHasRate(sys, rate);
    if (installed)
    {
        msg_Info(vd, "installed autonomous HDMI frame-packing display "
                     "override for vendor %x product %x",
                 sys->stereo_vendor, sys->stereo_product);
        vlc_dialog_display_error(
            vd, _("Restart required"),
            _("The HDMI 3D timing was installed successfully. Restart macOS "
              "once; PowerVLC will then switch the projector automatically "
              "without SwitchResX."));
    }
    else
    {
        msg_Err(vd, "could not install the HDMI display override");
        vlc_dialog_display_error(
            vd, _("HDMI 3D setup failed"),
            _("PowerVLC could not install the display timing. No display "
              "setting was changed."));
    }
    return installed;
}

static bool WaitForStereoDisplay(vout_display_sys_t *sys, unsigned attempts)
{
    for (unsigned i = 0; i < attempts; ++i)
    {
        CGDirectDisplayID display = FindOnlineStereoDisplay(sys);
        if (display != kCGNullDirectDisplay)
        {
            sys->stereo_display = display;
            return true;
        }
        usleep(100000);
    }
    return false;
}

static bool HasActiveBuiltinDisplay(void)
{
    CGDirectDisplayID displays[STEREO_MAX_MIRRORS];
    uint32_t count = 0;
    if (CGGetActiveDisplayList(STEREO_MAX_MIRRORS, displays, &count) !=
        kCGErrorSuccess)
        return true;
    for (uint32_t i = 0; i < count; ++i)
        if (CGDisplayIsBuiltin(displays[i]))
            return true;
    return false;
}

static bool IsClamshellStateClosed(void)
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    io_service_t resources = IOServiceGetMatchingService(
        kIOMasterPortDefault, IOServiceMatching("IOResources"));
#pragma clang diagnostic pop
    if (resources == IO_OBJECT_NULL)
        return false;

    CFTypeRef state = IORegistryEntryCreateCFProperty(
        resources, CFSTR("AppleClamshellState"),
        kCFAllocatorDefault, 0);
    IOObjectRelease(resources);
    bool closed = state != NULL && CFGetTypeID(state) == CFBooleanGetTypeID() &&
                  CFBooleanGetValue((CFBooleanRef)state);
    if (state != NULL)
        CFRelease(state);
    return closed;
}

static void BeginHDMIAudioReconfiguration(vout_display_t *vd)
{
    var_SetBool(vd->obj.libvlc, "macosx-hdmi-audio-reconfiguring", true);
}

static void EndHDMIAudioReconfiguration(vout_display_t *vd)
{
    var_SetBool(vd->obj.libvlc, "macosx-hdmi-audio-reconfiguring", false);
    var_IncInteger(vd->obj.libvlc, "macosx-hdmi-audio-generation");
}

/* Mavericks' Ivy Bridge framebuffer cannot scan the internal LVDS pipe and
 * the 148.5 MHz 1920x2205 HDMI pipe reliably at the same time.  IOGraphics'
 * own clamshell event is the only tested transition which really tears down
 * LVDS; merely disabling the CG display or powering down its panel leaves the
 * scanout active.  A tiny privileged helper publishes that event and remains
 * attached to this FILE stream.  EOF (including an application crash) makes
 * it publish the inverse event, unless the physical lid is actually closed. */
static bool StartSyntheticClamshell(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys->stereo_synthetic_clamshell)
        return true;

    /* CoreGraphics can omit the built-in display from its active list while
     * Ivy Bridge still drives it as a hardware-mirror pipe. That false
     * inactive state was accepted as a completed clamshell transition and
     * made the 1920x2205 projector scanout visibly oscillate. Only the
     * IOGraphics clamshell resource itself proves that another owner (or the
     * physical lid) has already requested the required pipe teardown. */
    if (!HasActiveBuiltinDisplay() && IsClamshellStateClosed()) {
        sys->stereo_synthetic_clamshell = true;
        msg_Info(vd, "internal display pipe already has a clamshell guard");
        return true;
    }

    NSString *directory = [[[NSBundle mainBundle] executablePath]
        stringByDeletingLastPathComponent];
    NSString *helper = [directory
        stringByAppendingPathComponent:@"powervlc-clamshell-helper"];
    if (![[NSFileManager defaultManager] isExecutableFileAtPath:helper])
    {
        msg_Err(vd, "legacy HDMI 3D helper is missing at %s",
                [helper fileSystemRepresentation]);
        return false;
    }

    AuthorizationItem execute_item = {
        kAuthorizationRightExecute, 0, NULL, 0
    };
    AuthorizationRights execute_rights = { 1, &execute_item };
    AuthorizationFlags flags = kAuthorizationFlagInteractionAllowed |
                               kAuthorizationFlagExtendRights |
                               kAuthorizationFlagPreAuthorize;
    OSStatus status = AuthorizationCreate(&execute_rights,
                                           kAuthorizationEmptyEnvironment,
                                           flags,
                                           &sys->stereo_clamshell_authorization);
    if (status != errAuthorizationSuccess)
    {
        msg_Err(vd, "could not acquire the legacy HDMI 3D helper right (%d)",
                (int)status);
        return false;
    }

    char *arguments[] = { "hold", NULL };
    BeginHDMIAudioReconfiguration(vd);
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    status = AuthorizationExecuteWithPrivileges(
        sys->stereo_clamshell_authorization,
        [helper fileSystemRepresentation], kAuthorizationFlagDefaults,
        arguments, &sys->stereo_clamshell_pipe);
#pragma clang diagnostic pop
    if (status != errAuthorizationSuccess ||
        sys->stereo_clamshell_pipe == NULL)
    {
        msg_Err(vd, "could not start legacy HDMI 3D helper (%d)",
                (int)status);
        AuthorizationFree(sys->stereo_clamshell_authorization,
                          kAuthorizationFlagDefaults);
        sys->stereo_clamshell_authorization = NULL;
        sys->stereo_clamshell_pipe = NULL;
        EndHDMIAudioReconfiguration(vd);
        return false;
    }

    /* IOGraphics consumes the resource asynchronously and then WindowServer
     * republishes the remaining HDMI display. */
    for (unsigned i = 0; i < 150 && HasActiveBuiltinDisplay(); ++i)
        usleep(100000);
    if (HasActiveBuiltinDisplay())
    {
        msg_Err(vd, "the internal display pipe stayed active after the "
                "synthetic clamshell transition");
        fclose(sys->stereo_clamshell_pipe);
        sys->stereo_clamshell_pipe = NULL;
        AuthorizationFree(sys->stereo_clamshell_authorization,
                          kAuthorizationFlagDefaults);
        sys->stereo_clamshell_authorization = NULL;
        EndHDMIAudioReconfiguration(vd);
        return false;
    }

    sys->stereo_synthetic_clamshell = true;
    /* When Quartz had already marked the mirror slave inactive, the loop
     * above completes immediately although the LVDS pipe is still draining.
     * Give IOGraphics one full topology-settle interval before configuring
     * the high-clock HDMI frame-packing mode. */
    usleep(1500000);
    msg_Info(vd, "stopped the internal display pipe for stable legacy "
             "HDMI 3D scanout");
    return true;
}

static void StopSyntheticClamshell(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys->stereo_clamshell_pipe != NULL)
    {
        /* Closing the bidirectional authorization pipe gives the helper EOF;
         * it restores the open state before exiting. */
        fclose(sys->stereo_clamshell_pipe);
        sys->stereo_clamshell_pipe = NULL;
    }
    if (sys->stereo_clamshell_authorization != NULL)
    {
        AuthorizationFree(sys->stereo_clamshell_authorization,
                          kAuthorizationFlagDefaults);
        sys->stereo_clamshell_authorization = NULL;
    }
    if (sys->stereo_synthetic_clamshell)
        msg_Info(vd, "released the legacy HDMI 3D clamshell guard");
    sys->stereo_synthetic_clamshell = false;
}

static bool SetVirtualFramePackingEDID(vout_display_t *vd, bool enable,
                                       size_t eye_width, size_t eye_height,
                                       double rate)
{
    vout_display_sys_t *sys = vd->sys;
    VLCIOAVServiceCreateWithService create;
    VLCIOAVServiceCopyEDID copy_edid;
    VLCIOAVServiceSetVirtualEDIDMode set_virtual;
    if (!LoadIOAVFunctions(&create, &copy_edid, &set_virtual))
        return false;

    CFDataRef service_edid = NULL;
    VLCIOAVServiceRef service = CopyIOAVServiceForDisplay(
        sys->stereo_vendor, sys->stereo_product, sys->stereo_serial,
        create, copy_edid, &service_edid);
    if (service == NULL)
        return false;

    CFDataRef virtual_edid = NULL;
    if (enable)
    {
        virtual_edid = CopyFramePackingEDID(service_edid, eye_width,
                                             eye_height, rate);
        if (virtual_edid == NULL)
        {
            msg_Warn(vd, "the HDMI display EDID has no usable 3D capability");
            CFRelease(service_edid);
            CFRelease(service);
            return false;
        }
    }
    IOReturn error = set_virtual(service, enable, virtual_edid);
    if (virtual_edid != NULL)
        CFRelease(virtual_edid);
    CFRelease(service_edid);
    CFRelease(service);
    if (error != kIOReturnSuccess)
    {
        msg_Warn(vd, "IOAV virtual EDID %s failed (0x%x)",
                 enable ? "enable" : "disable", error);
        return false;
    }
    sys->stereo_virtual_edid_enabled = enable;
    /* DCP publishes the same CGDirectDisplayID briefly while rebuilding the
     * mode table.  Do not mistake that stale display for the reconnected one. */
    usleep(500000);
    /* Creating a mode may legitimately take longer. Shutdown must remain
     * responsive: after disabling the virtual EDID, continue cleanup after
     * five seconds and let WindowServer finish the physical reconnect. */
    if (!WaitForStereoDisplay(sys, enable ? 300 : 50))
    {
        msg_Warn(vd, "HDMI display did not return after virtual EDID %s",
                 enable ? "enable" : "disable");
        return false;
    }
    msg_Info(vd, "%s temporary HDMI frame-packing EDID",
             enable ? "enabled" : "disabled");
    return true;
}

static bool LoadCGSFunctions(VLCCGSGetCurrentDisplayMode *get_current,
                             VLCCGSGetNumberOfDisplayModes *get_count,
                             VLCCGSGetDisplayModeDescriptionOfLength *describe,
                             VLCCGSConfigureDisplayMode *configure)
{
    *get_current = (VLCCGSGetCurrentDisplayMode)
        dlsym(RTLD_DEFAULT, "CGSGetCurrentDisplayMode");
    *get_count = (VLCCGSGetNumberOfDisplayModes)
        dlsym(RTLD_DEFAULT, "CGSGetNumberOfDisplayModes");
    *describe = (VLCCGSGetDisplayModeDescriptionOfLength)
        dlsym(RTLD_DEFAULT, "CGSGetDisplayModeDescriptionOfLength");
    *configure = (VLCCGSConfigureDisplayMode)
        dlsym(RTLD_DEFAULT, "CGSConfigureDisplayMode");
    return *get_current != NULL && *get_count != NULL &&
           *describe != NULL && *configure != NULL;
}

static int FindPrivateFramePackingMode(CGDirectDisplayID display,
                                       size_t width, size_t height,
                                       double rate)
{
    VLCCGSGetCurrentDisplayMode get_current;
    VLCCGSGetNumberOfDisplayModes get_count;
    VLCCGSGetDisplayModeDescriptionOfLength describe;
    VLCCGSConfigureDisplayMode configure;
    if (!LoadCGSFunctions(&get_current, &get_count, &describe, &configure))
        return -1;
    VLC_UNUSED(get_current);
    VLC_UNUSED(configure);

    int count = 0;
    get_count(display, &count);
    /* Mavericks rounds both 23.976 and 24.000 to the integer frequency 24
     * in CGS descriptions (and to 24.000 in public CGDisplayMode objects).
     * Display overrides preserve DTD order, however: PowerVLC installs the
     * fractional timing first and the integer timing second.  Select the
     * first matching duplicate for 24000/1001 content and the last for true
     * 24 Hz content. */
    const bool mavericks = floor(NSAppKitVersionNumber) == 1265;
    /* Keep the DTD ordering when Quartz rounds both clocks to 24 Hz: the
     * first entry is the 148.35 MHz 24000/1001 timing and the second the
     * exact 148.50 MHz timing. Even with LVDS verifiably stopped, Ivy Bridge
     * on Mavericks emits intermittent white lines at the bottom of the
     * fractional scanout. Use its stable exact-24 timing and compensate the
     * 24000/1001 cadence in presentation scheduling on that stack only. */
    const bool fractional_24 =
        fabs(rate - 24000.0 / 1001.0) < 0.01 && !mavericks;
    int current_index = -1;
    vlc_cgs_display_mode_t current_mode = { 0 };
    if (get_current(display, &current_index) == kCGErrorSuccess &&
        current_index >= 0)
        describe(display, current_index, &current_mode, sizeof(current_mode));

    int best = -1;
    int best_matching_depth = -1;
    for (int i = 0; i < count; ++i)
    {
        vlc_cgs_display_mode_t mode = { 0 };
        describe(display, i, &mode, sizeof(mode));
        if (mode.width == width && mode.height == height &&
            fabs((double)mode.frequency - rate) <= 0.6)
        {
            if (best < 0 || !fractional_24)
                best = i;
            /* Each DTD appears once per pixel depth plus a disabled sentinel.
             * Switching from the desktop's 32-bit mode to the first duplicate
             * selected a 16-bit scanout on Snow Leopard. Preserve the active
             * depth and reject the 0x80000000 sentinel while retaining DTD
             * order to distinguish 23.976 from true 24 Hz. */
            if (mode.depth == current_mode.depth &&
                (mode.flags & 0x80000000U) == 0 &&
                (best_matching_depth < 0 || !fractional_24))
                best_matching_depth = i;
        }
    }
    return best_matching_depth >= 0 ? best_matching_depth : best;
}

static CGError ConfigurePrivateDisplayMode(CGDirectDisplayID display,
                                           int mode)
{
    VLCCGSGetCurrentDisplayMode get_current;
    VLCCGSGetNumberOfDisplayModes get_count;
    VLCCGSGetDisplayModeDescriptionOfLength describe;
    VLCCGSConfigureDisplayMode configure;
    if (!LoadCGSFunctions(&get_current, &get_count, &describe, &configure))
        return kCGErrorNotImplemented;
    VLC_UNUSED(get_current);
    VLC_UNUSED(get_count);
    VLC_UNUSED(describe);

    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error == kCGErrorSuccess)
    {
        error = configure(config, display, mode);
        if (error == kCGErrorSuccess)
            error = CGCompleteDisplayConfiguration(config,
                                                    kCGConfigureForAppOnly);
        else
            CGCancelDisplayConfiguration(config);
    }
    return error;
}

static bool DescribePrivateDisplayMode(CGDirectDisplayID display, int mode,
                                       vlc_cgs_display_mode_t *description)
{
    VLCCGSGetCurrentDisplayMode get_current;
    VLCCGSGetNumberOfDisplayModes get_count;
    VLCCGSGetDisplayModeDescriptionOfLength describe;
    VLCCGSConfigureDisplayMode configure;
    if (mode < 0 || description == NULL ||
        !LoadCGSFunctions(&get_current, &get_count, &describe, &configure))
        return false;
    VLC_UNUSED(get_current);
    VLC_UNUSED(get_count);
    VLC_UNUSED(configure);

    memset(description, 0, sizeof(*description));
    describe(display, mode, description, sizeof(*description));
    return description->width > 0 && description->height > 0;
}

static bool DetachMirrorWithMonitorPanel(vout_display_t *vd,
                                         CGDirectDisplayID display_id)
{
    static void *monitor_panel;
    if (monitor_panel == NULL)
        monitor_panel = dlopen("/System/Library/PrivateFrameworks/"
                              "MonitorPanel.framework/MonitorPanel",
                              RTLD_LAZY | RTLD_LOCAL);
    if (monitor_panel == NULL)
        return false;

    Class manager_class = NSClassFromString(@"MPDisplayMgr");
    SEL shared_selector = NSSelectorFromString(@"sharedMgr");
    if (manager_class == Nil ||
        ![manager_class respondsToSelector:shared_selector])
        return false;

    id manager = [manager_class sharedMgr];
    SEL stop_selector = NSSelectorFromString(@"stopMirroringForDisplay:");
    SEL display_selector = NSSelectorFromString(@"displayWithID:");
    if (manager == nil || ![manager respondsToSelector:stop_selector] ||
        ![manager respondsToSelector:display_selector] ||
        ![manager respondsToSelector:@selector(tryLockAccess)] ||
        ![manager respondsToSelector:@selector(unlockAccess)] ||
        ![manager respondsToSelector:@selector(notifyWillReconfigure)] ||
        ![manager respondsToSelector:@selector(notifyReconfigure)])
        return false;

    bool locked = false;
    bool requested = false;
    @try
    {
        for (unsigned attempt = 0; attempt < 10 && !locked; ++attempt)
        {
            locked = [manager tryLockAccess];
            if (!locked)
                usleep(50000);
        }
        id display = [manager displayWithID:(int)display_id];
        if (locked && display != nil)
        {
            [manager notifyWillReconfigure];
            [manager stopMirroringForDisplay:display];
            [manager notifyReconfigure];
            requested = true;
        }
        if (locked)
        {
            [manager unlockAccess];
            locked = false;
        }
    }
    @catch (NSException *exception)
    {
        msg_Warn(vd, "MonitorPanel could not separate the mirrored display: "
                 "%s", [[exception reason] UTF8String]);
        if (locked)
        {
            @try { [manager unlockAccess]; }
            @catch (NSException *unlock_exception)
            {
                VLC_UNUSED(unlock_exception);
            }
        }
        return false;
    }

    if (!requested)
        return false;
    for (unsigned attempt = 0; attempt < 50; ++attempt)
    {
        if (!CGDisplayIsInMirrorSet(display_id))
        {
            msg_Info(vd, "separated the HDMI display with the modern macOS "
                     "display service");
            return true;
        }
        usleep(100000);
    }
    return false;
}

static void PutStereoDisplayBesideBuiltin(vout_display_t *vd,
                                          CGDirectDisplayID *displays,
                                          uint32_t display_count)
{
    vout_display_sys_t *sys = vd->sys;
    CGDirectDisplayID builtin = kCGNullDirectDisplay;
    for (uint32_t i = 0; i < display_count; ++i)
    {
        if (displays[i] != sys->stereo_display &&
            CGDisplayIsBuiltin(displays[i]) &&
            CGDisplayIsOnline(displays[i]))
        {
            builtin = displays[i];
            break;
        }
    }
    if (builtin == kCGNullDirectDisplay)
        return;

    CGRect builtin_bounds = CGDisplayBounds(builtin);
    if (CGRectGetWidth(builtin_bounds) < 1.0)
        return;

    /* A projector that was the mirror master keeps the global (0,0) origin
     * after Quartz separates the group.  That makes it the desktop's main
     * display and leaves unrelated application windows above the 3D vout.
     * Temporarily make the built-in panel the desktop origin and put the HDMI
     * raster directly to its right.  Recreating the saved mirror relation at
     * shutdown restores the projector's original master/main status. */
    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error == kCGErrorSuccess)
        error = CGConfigureDisplayOrigin(config, builtin, 0, 0);
    if (error == kCGErrorSuccess)
        error = CGConfigureDisplayOrigin(
            config, sys->stereo_display,
            (int32_t)lround(CGRectGetWidth(builtin_bounds)), 0);
    if (error == kCGErrorSuccess)
        error = CGCompleteDisplayConfiguration(config,
                                                kCGConfigureForAppOnly);
    else if (config != NULL)
        CGCancelDisplayConfiguration(config);

    if (error == kCGErrorSuccess)
        msg_Info(vd, "temporarily made the built-in display primary and "
                 "placed HDMI 3D beside it");
    else
        msg_Warn(vd, "could not keep the built-in display primary while "
                 "using HDMI 3D (%d)", error);
}

static VLCConfigureDisplayEnabled LoadConfigureDisplayEnabled(void)
{
    /* SwitchResX 4.3.6 uses the public spelling through Mountain Lion and
     * the CGS spelling on Mavericks.  They have the same transaction-based
     * ABI.  Late binding keeps the vout loadable back to PowerVLC's 10.4
     * floor and avoids a private-symbol link dependency. */
    const bool mavericks_or_later = floor(NSAppKitVersionNumber) >= 1265;
    const char *primary = mavericks_or_later
        ? "CGSConfigureDisplayEnabled" : "CGConfigureDisplayEnabled";
    const char *fallback = mavericks_or_later
        ? "CGConfigureDisplayEnabled" : "CGSConfigureDisplayEnabled";
    VLCConfigureDisplayEnabled configure =
        (VLCConfigureDisplayEnabled)dlsym(RTLD_DEFAULT, primary);
    if (configure == NULL)
        configure = (VLCConfigureDisplayEnabled)dlsym(RTLD_DEFAULT, fallback);
    return configure;
}

static bool DisableBuiltinDisplaysForStereo(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    VLCConfigureDisplayEnabled configure = LoadConfigureDisplayEnabled();
    if (configure == NULL)
    {
        msg_Warn(vd, "macOS has no display-enable transaction function");
        return false;
    }

    CGDirectDisplayID displays[STEREO_MAX_MIRRORS];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(STEREO_MAX_MIRRORS, displays, &count) !=
        kCGErrorSuccess)
        return false;

    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    sys->stereo_disabled_display_count = 0;
    bool found_active_builtin = false;
    for (uint32_t i = 0; error == kCGErrorSuccess && i < count; ++i)
    {
        /* Mavericks reports the internal panel as online but sometimes not
         * "active" while it is still scanning out (and visibly flickering).
         * CGSConfigureDisplayEnabled operates on the online display object,
         * so do not use CGDisplayIsActive() as a proxy for whether the panel
         * needs to be disabled. */
        if (displays[i] == sys->stereo_display ||
            !CGDisplayIsBuiltin(displays[i]))
            continue;
        found_active_builtin = true;
        error = configure(config, displays[i], false);
        if (error == kCGErrorSuccess)
            sys->stereo_disabled_displays[
                sys->stereo_disabled_display_count++] = displays[i];
    }
    if (error == kCGErrorSuccess && !found_active_builtin)
    {
        CGCancelDisplayConfiguration(config);
        msg_Info(vd, "no active built-in display needs disabling for HDMI 3D");
        return true;
    }
    if (error == kCGErrorSuccess && sys->stereo_disabled_display_count > 0)
        error = CGCompleteDisplayConfiguration(config,
                                                kCGConfigureForAppOnly);
    else if (config != NULL)
        CGCancelDisplayConfiguration(config);

    if (error != kCGErrorSuccess ||
        sys->stereo_disabled_display_count == 0)
    {
        msg_Warn(vd, "could not disable the built-in display for legacy "
                     "HDMI 3D (%d)", error);
        sys->stereo_disabled_display_count = 0;
        return false;
    }
    msg_Info(vd, "temporarily disabled %u built-in display(s) for stable "
                 "legacy HDMI 3D scanout", sys->stereo_disabled_display_count);
    return true;
}

static void RestoreBuiltinDisplays(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys->stereo_disabled_display_count == 0)
        return;
    VLCConfigureDisplayEnabled configure = LoadConfigureDisplayEnabled();
    CGDisplayConfigRef config = NULL;
    CGError error = configure != NULL
        ? CGBeginDisplayConfiguration(&config) : kCGErrorNotImplemented;
    for (uint32_t i = 0; error == kCGErrorSuccess &&
                         i < sys->stereo_disabled_display_count; ++i)
        error = configure(config, sys->stereo_disabled_displays[i], true);
    if (error == kCGErrorSuccess)
        error = CGCompleteDisplayConfiguration(config,
                                                kCGConfigureForAppOnly);
    else if (config != NULL)
        CGCancelDisplayConfiguration(config);
    if (error == kCGErrorSuccess)
        msg_Info(vd, "restored %u built-in display(s)",
                 sys->stereo_disabled_display_count);
    else
        msg_Warn(vd, "could not restore the built-in display (%d)", error);
    sys->stereo_disabled_display_count = 0;
}

static bool DetachStereoDisplayMirrors(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    CGDirectDisplayID displays[STEREO_MAX_MIRRORS];
    uint32_t display_count = 0;
    if (CGGetOnlineDisplayList(STEREO_MAX_MIRRORS, displays,
                               &display_count) != kCGErrorSuccess)
        return false;

    sys->stereo_mirror_count = 0;
    for (uint32_t i = 0; i < display_count; ++i)
    {
        CGDirectDisplayID master = CGDisplayMirrorsDisplay(displays[i]);
        if (master != kCGNullDirectDisplay &&
            (displays[i] == sys->stereo_display ||
             master == sys->stereo_display))
        {
            uint32_t slot = sys->stereo_mirror_count++;
            sys->stereo_mirror_displays[slot] = displays[i];
            sys->stereo_mirror_masters[slot] = master;
        }
    }

    /* Recent macOS releases can report every display in a mirror set with a
     * null CGDisplayMirrorsDisplay(), including the slave.  Fall back to the
     * mirror-set bit and common desktop bounds in that representation.  The
     * main display is the implicit master; recording that relation lets the
     * exact mirrored arrangement be recreated after playback. */
    if (sys->stereo_mirror_count == 0 &&
        CGDisplayIsInMirrorSet(sys->stereo_display))
    {
        CGRect stereo_bounds = CGDisplayBounds(sys->stereo_display);
        CGDirectDisplayID master = CGMainDisplayID();
        if (!CGDisplayIsInMirrorSet(master) ||
            !CGRectEqualToRect(CGDisplayBounds(master), stereo_bounds))
            master = sys->stereo_display;

        for (uint32_t i = 0; i < display_count; ++i)
        {
            if (displays[i] == master ||
                !CGDisplayIsInMirrorSet(displays[i]) ||
                !CGRectEqualToRect(CGDisplayBounds(displays[i]),
                                   stereo_bounds))
                continue;
            uint32_t slot = sys->stereo_mirror_count++;
            sys->stereo_mirror_displays[slot] = displays[i];
            sys->stereo_mirror_masters[slot] = master;
        }
    }
    if (sys->stereo_mirror_count == 0)
        return true;

    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error == kCGErrorSuccess)
    {
        for (uint32_t i = 0; i < sys->stereo_mirror_count; ++i)
        {
            error = CGConfigureDisplayMirrorOfDisplay(
                                  config,
                                  sys->stereo_mirror_displays[i],
                                  kCGNullDirectDisplay);
            if (error != kCGErrorSuccess)
                break;
        }
        if (error == kCGErrorSuccess)
            error = CGCompleteDisplayConfiguration(config,
                                                    kCGConfigureForAppOnly);
        else
            CGCancelDisplayConfiguration(config);
    }
    if (error != kCGErrorSuccess)
    {
        msg_Warn(vd, "Quartz could not separate the HDMI display from its "
                 "mirror group (%d); trying the modern macOS display "
                 "service", error);
        if (!DetachMirrorWithMonitorPanel(vd, sys->stereo_display))
        {
            sys->stereo_mirror_count = 0;
            return false;
        }
    }

    PutStereoDisplayBesideBuiltin(vd, displays, display_count);

    msg_Info(vd, "temporarily separated the HDMI display from %u mirror(s)",
             sys->stereo_mirror_count);
    return true;
}

static void RestoreStereoDisplayMirrors(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    RestoreBuiltinDisplays(vd);
    if (sys->stereo_mirror_count == 0)
        return;

    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    if (error == kCGErrorSuccess)
    {
        for (uint32_t i = 0; i < sys->stereo_mirror_count; ++i)
        {
            error = CGConfigureDisplayMirrorOfDisplay(
                                  config,
                                  sys->stereo_mirror_displays[i],
                                  sys->stereo_mirror_masters[i]);
            if (error != kCGErrorSuccess)
                break;
        }
        if (error == kCGErrorSuccess)
            error = CGCompleteDisplayConfiguration(config,
                                                    kCGConfigureForAppOnly);
        else
            CGCancelDisplayConfiguration(config);
    }
    if (error != kCGErrorSuccess)
        msg_Warn(vd, "could not restore the previous display mirroring (%d)",
                 error);
    else
        msg_Info(vd, "restored the previous display mirroring");
    sys->stereo_mirror_count = 0;
}

static void EnterStereoFullscreen(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    vlc_object_t *vout = vd->obj.parent;
    if (vout == NULL)
        return;

    if (!var_GetBool(vout, "fullscreen"))
    {
        sys->stereo_fullscreen_forced = true;
        var_SetBool(vout, "fullscreen", true);
        msg_Info(vd, "entered fullscreen automatically for MVC playback");
    }
    else
    {
        /* --fullscreen (or a saved fullscreen state) can be applied before
         * the legacy video view exists.  Its window callback then discards
         * the request, and merely setting true again after the private HDMI
         * mode switch is a no-op.  Replay the transition now that the view
         * and final stereo target both exist.  The false/true pair is queued
         * in order by the vout control path and does not claim ownership of
         * a fullscreen state the user requested. */
        var_SetBool(vout, "fullscreen", false);
        var_SetBool(vout, "fullscreen", true);
        msg_Info(vd, "reapplied pre-existing fullscreen state after HDMI "
                     "display transition");
    }
}

static void SetStereoFullscreenDisplay(vout_display_t *vd, bool enable)
{
    vout_display_sys_t *sys = vd->sys;
    vlc_object_t *root = VLC_OBJECT(vd);
    while (root->obj.parent != NULL)
        root = root->obj.parent;

    if (enable)
    {
        if (!sys->stereo_fullscreen_display_overridden)
        {
            if (var_Create(root, "stereo3d-fullscreen-display",
                           VLC_VAR_INTEGER | VLC_VAR_DOINHERIT) != VLC_SUCCESS)
            {
                msg_Warn(vd, "could not create the transient 3D fullscreen "
                         "display target");
                return;
            }
            sys->stereo_saved_fullscreen_display =
                var_GetInteger(root, "stereo3d-fullscreen-display");
            sys->stereo_fullscreen_display_overridden = true;
        }
        var_SetInteger(root, "stereo3d-fullscreen-display",
                       (int64_t)(uintptr_t)sys->stereo_display);
    }
    else if (sys->stereo_fullscreen_display_overridden)
    {
        var_SetInteger(root, "stereo3d-fullscreen-display",
                       sys->stereo_saved_fullscreen_display);
        sys->stereo_fullscreen_display_overridden = false;
    }
}

/* The legacy display transaction temporarily tears down and republishes the
 * screen topology.  The GUI must not draw transient UI (notably the resume
 * choice) or repeatedly show the hardware cursor while WindowServer is in
 * that state: on Snow Leopard/NVIDIA both can end up on the disappearing
 * desktop and the cursor visibly flashes on the HDMI raster. */
static void SetStereoDisplayTransition(vout_display_t *vd, bool active)
{
    vlc_object_t *root = VLC_OBJECT(vd);
    while (root->obj.parent != NULL)
        root = root->obj.parent;

    if (var_Create(root, "stereo3d-display-transition",
                   VLC_VAR_BOOL) == VLC_SUCCESS ||
        var_Type(root, "stereo3d-display-transition") != 0)
        var_SetBool(root, "stereo3d-display-transition", active);
}

static bool RetuneAdoptedStereoDisplay(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (!sys->stereo_mode_ready || !sys->stereo_private_mode_changed)
        return false;

    double source_rate = 0.0;
    if (vd->fmt.i_frame_rate > 0 && vd->fmt.i_frame_rate_base > 0)
        source_rate = (double)vd->fmt.i_frame_rate /
                      vd->fmt.i_frame_rate_base;

    unsigned eye_width = sys->stereo_eye_width;
    unsigned eye_height = sys->stereo_eye_height;
    size_t packed_height = 2 * eye_height +
                           (eye_height == 720 ? 30 : 45);
    double scanout_rate = source_rate;

    if (vd->fmt.multiview_mode == MULTIVIEW_2D &&
        source_rate > 24.5 && source_rate < 25.5)
    {
        /* 25 fps cannot be presented evenly by the retained 1080p24 stereo
         * timing: VLC must discard one picture every second, which is the
         * regular judder visible in Albator's Trailer 3. HDMI defines 720p50
         * frame packing for this cadence; each duplicated 2D picture then
         * occupies exactly two scanouts and the projector remains in 3D. */
        eye_width = 1280;
        eye_height = 720;
        packed_height = 1470;
        scanout_rate = 50.0;
    }
    else if (IsFramePackableStereo(vd->fmt.multiview_mode) &&
             vd->fmt.i_visible_width >= 1920 &&
             vd->fmt.i_visible_height >= 1080)
    {
        eye_width = 1920;
        eye_height = 1080;
        packed_height = 2205;
        if (scanout_rate < 1.0)
            scanout_rate = 24.0;
    }
    else
        return false;

    if (eye_width == sys->stereo_eye_width &&
        eye_height == sys->stereo_eye_height)
        return false;

    int mode = FindPrivateFramePackingMode(sys->stereo_display, eye_width,
                                            packed_height, scanout_rate);
    if (mode < 0)
    {
        msg_Warn(vd, "no retained HDMI frame-packing mode for %ux%zu at "
                     "%.3f Hz; keeping %ux%u", eye_width, packed_height,
                     scanout_rate, sys->stereo_eye_width,
                     sys->stereo_eye_height);
        return false;
    }

    CGError error = ConfigurePrivateDisplayMode(sys->stereo_display, mode);
    if (error != kCGErrorSuccess)
    {
        msg_Warn(vd, "could not retune retained HDMI 3D mode %d (%d)",
                 mode, error);
        return false;
    }
    usleep(200000);
    sys->stereo_eye_width = eye_width;
    sys->stereo_eye_height = eye_height;
    msg_Info(vd, "retuned retained HDMI 3D scanout to private mode %d: "
             "%ux%zu at %.3f Hz", mode, eye_width, packed_height,
             scanout_rate);
    return true;
}

static void SelectStereoDisplayMode(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys->stereo_mode_ready)
        return;
    if (!IsFramePackableStereo(vd->fmt.multiview_mode))
        return;

    if (!ShouldSwitchToStereoDisplay(vd))
        return;

    /* NSAppKitVersionNumber 1343 is Yosemite.  Mavericks' Ivy Bridge driver
     * kernel-panics if CGDisplaySetStereoOperation() is called, even when that
     * API returns kCGErrorRangeCheck.  SwitchResX confirms that the reliable
     * legacy path is instead an ordinary CoreGraphics switch to a DTD-published
     * 1920x2205 timing, performed before any NSOpenGL context exists. */
    const bool legacy_display_stack = floor(NSAppKitVersionNumber) < 1343;
    /* Establish foreground ownership before touching display topology.
     * Promoting the process after CGSConfigureDisplayEnabled() makes
     * Mavericks rebuild the application desktop and silently re-enables the
     * internal LCD, producing scanout contention and bottom-edge flashes. */
    [VLCOpenGLVideoView
        performSelectorOnMainThread:@selector(activateForStereoFullscreen:)
                         withObject:nil waitUntilDone:YES];

    double content_rate = 24.0;
    if (vd->fmt.i_frame_rate > 0 && vd->fmt.i_frame_rate_base > 0)
        content_rate = (double)vd->fmt.i_frame_rate /
                       vd->fmt.i_frame_rate_base;

    unsigned eye_width_u, eye_height_u;
    if (!StereoEyeDimensions(&vd->fmt, &eye_width_u, &eye_height_u))
        return;
    const size_t eye_width = eye_width_u;
    const size_t eye_height = eye_height_u;
    sys->stereo_eye_width = eye_width_u;
    sys->stereo_eye_height = eye_height_u;
    size_t packed_height;
    bool standard_rate;
    if (eye_width == 1920 && eye_height == 1080)
    {
        packed_height = 2205;
        standard_rate = RefreshNear(content_rate, 24.0) ||
                        RefreshNear(content_rate, 24000.0 / 1001.0);
    }
    else if (eye_width == 1280 && eye_height == 720)
    {
        packed_height = 1470;
        standard_rate = RefreshNear(content_rate, 50.0) ||
                        RefreshNear(content_rate, 60.0) ||
                        RefreshNear(content_rate, 60000.0 / 1001.0);
    }
    else
    {
        msg_Warn(vd, "unsupported HDMI frame-packing eye size %zux%zu",
                 eye_width, eye_height);
        vlc_dialog_display_error(vd, _("HDMI 3D frame packing unavailable"),
                                 _("PowerVLC cannot create a standardized "
                                   "frame-packed raster for %zux%zu per eye."),
                                 eye_width, eye_height);
        return;
    }
    if (!standard_rate)
    {
        msg_Warn(vd, "unsupported HDMI frame-packing rate %.3f Hz for "
                 "%zux%zu per eye", content_rate, eye_width, eye_height);
        vlc_dialog_display_error(vd, _("HDMI 3D frame packing unavailable"),
                                 _("%.3f Hz is not a standardized HDMI "
                                   "frame-packing rate for %zux%zu per eye."),
                                 content_rate, eye_width, eye_height);
        return;
    }

    int configured = var_InheritInteger(vd, "macosx-vdev");
    sys->stereo_display = configured > 0
        ? (CGDirectDisplayID)configured
        : FindAutomaticStereoDisplay(eye_width, packed_height, content_rate);
    VLCDisplayModeRef current = CopyDisplayModeCompat(sys->stereo_display);
    if (current == NULL)
        return;

    /* A 3D Blu-ray is SDR by specification. If the 4K desktop currently uses
     * HDR, DCP otherwise carries that dynamic-range state into the private
     * 1920x2205 timing even though the OpenGL surface itself is 8-bit SDR. */
    SelectStereoSDRDisplayMode(vd, true);

    /* Apple Silicon's DCP accepts HDMI 3D timings but hides them from the
     * public CGDisplayMode list.  If the exact private mode is absent, expose
     * one temporarily through the external IOAV service, then switch it with
     * the same private CGS API used by the macOS display stack. */
    sys->stereo_vendor = CGDisplayVendorNumber(sys->stereo_display);
    sys->stereo_product = CGDisplayModelNumber(sys->stereo_display);
    sys->stereo_serial = CGDisplaySerialNumber(sys->stereo_display);

    /* A public exact-24 mode is within the old 0.6-Hz search tolerance and
     * used to suppress installation of the separate 23.976 DTD. Verify the
     * actual 18-byte timing in the legacy override before searching CGS: its
     * integer mode descriptions cannot tell the two clocks apart. */
    if (legacy_display_stack && eye_width == 1920 && eye_height == 1080 &&
        !LegacyFramePackingOverrideHasRate(sys, content_rate))
    {
        InstallLegacyFramePackingOverride(vd, eye_width, eye_height,
                                           content_rate);
        CFRelease(current);
        return;
    }
    int private_mode = FindPrivateFramePackingMode(sys->stereo_display,
                                                    eye_width, packed_height,
                                                    content_rate);
    if (legacy_display_stack)
    {
        /* Legacy Quartz only rebuilds its mode table at login/boot after a
         * display override is installed.  Do this before publishing the
         * synthetic clamshell event: without an existing private mode the
         * topology transition can never succeed and merely blanks the
         * internal panel for several seconds. */
        if (private_mode < 0)
        {
            InstallLegacyFramePackingOverride(vd, eye_width, eye_height,
                                               content_rate);
            CFRelease(current);
            return;
        }

        /* The successful Mavericks sequence is deliberately atomic from the
         * vout's point of view: remove LVDS first, reacquire HDMI after the
         * topology event, then use the private mode index.  The public mode
         * setter silently substitutes 1920x1080 in clamshell mode. */
        /* Snow Leopard's NVIDIA 320M stack consumes the historical
         * AppleClamshellState resource but does not remove the built-in
         * framebuffer from Quartz's active topology.  SwitchResX's legacy
         * transaction API does, and was verified on 10.6 to leave only HDMI
         * active.  Mavericks still needs the synthetic IOGraphics event to
         * stop the Intel LVDS scanout electrically, so retain that path from
         * 10.9 onward. */
        const bool pre_mavericks = floor(NSAppKitVersionNumber) < 1265;
        bool ready = pre_mavericks
            ? DisableBuiltinDisplaysForStereo(vd)
            : StartSyntheticClamshell(vd);
        if (ready)
            ready = WaitForStereoDisplay(sys, 100);
        if (ready)
            private_mode = FindPrivateFramePackingMode(
                sys->stereo_display, eye_width, packed_height, content_rate);

        VLCCGSGetCurrentDisplayMode get_current;
        VLCCGSGetNumberOfDisplayModes get_count;
        VLCCGSGetDisplayModeDescriptionOfLength describe;
        VLCCGSConfigureDisplayMode configure;
        int saved_private = -1;
        ready = ready && private_mode >= 0 &&
            LoadCGSFunctions(&get_current, &get_count, &describe, &configure) &&
            get_current(sys->stereo_display, &saved_private) ==
                kCGErrorSuccess;
        VLC_UNUSED(get_count);
        VLC_UNUSED(describe);
        VLC_UNUSED(configure);

        CGError error = ready
            ? ConfigurePrivateDisplayMode(sys->stereo_display, private_mode)
            : kCGErrorFailure;
        int active_private = -1;
        size_t logical_width = 0, logical_height = 0;
        vlc_cgs_display_mode_t active_description = { 0 };
        bool active_description_valid = false;
        if (ready && error == kCGErrorSuccess)
        {
            /* A newly installed fractional DTD makes WindowServer republish
             * the HDMI display once more after CGS accepts the mode. The old
             * CGDirectDisplayID can transiently report a scaled 1920x1600
             * framebuffer even though mode 0 is active. Reacquire the XGIMI
             * display and wait for its physical raster instead of restoring
             * the previous mode on that intermediate snapshot. */
            for (unsigned i = 0; i < 50; ++i)
            {
                WaitForStereoDisplay(sys, 1);
                active_private = -1;
                get_current(sys->stereo_display, &active_private);
                logical_width = CGDisplayPixelsWide(sys->stereo_display);
                logical_height = CGDisplayPixelsHigh(sys->stereo_display);
                active_description_valid = DescribePrivateDisplayMode(
                    sys->stereo_display, active_private,
                    &active_description);
                if (active_private == private_mode &&
                    active_description_valid &&
                    active_description.width == eye_width &&
                    active_description.height == packed_height &&
                    (active_description.flags & 0x80000000U) == 0)
                    break;
                usleep(100000);
            }
        }
        ready = ready && error == kCGErrorSuccess &&
            active_private == private_mode &&
            active_description_valid &&
            active_description.width == eye_width &&
            active_description.height == packed_height &&
            (active_description.flags & 0x80000000U) == 0;
        if (ready)
        {
            sys->stereo_saved_private_mode = saved_private;
            sys->stereo_private_mode_changed = true;
            sys->stereo_saved_mode = current;
            sys->stereo_mode_changed = true;
            sys->stereo_mode_ready = true;
            current = NULL;
            msg_Info(vd, "switched legacy HDMI scanout to private mode %d: "
                     "%zux%zu at %.3f Hz", private_mode, eye_width,
                     packed_height, content_rate);
            SelectStereoSDRDisplayMode(vd, false);
            EndHDMIAudioReconfiguration(vd);
        }
        else
        {
            msg_Err(vd, "legacy private HDMI mode failed (mode=%d "
                    "configure=%d active=%d description=%ux%u/0x%08x "
                    "logical=%zux%zu)", private_mode, error, active_private,
                    active_description.width, active_description.height,
                    active_description.flags, logical_width, logical_height);
            if (error == kCGErrorSuccess && saved_private >= 0)
                ConfigurePrivateDisplayMode(sys->stereo_display,
                                            saved_private);
            if (pre_mavericks)
                RestoreBuiltinDisplays(vd);
            StopSyntheticClamshell(vd);
            EndHDMIAudioReconfiguration(vd);
            vlc_dialog_display_error(
                vd, _("HDMI 3D frame packing unavailable"),
                _("PowerVLC could not establish the stable legacy HDMI 3D "
                  "display topology. The previous display state was "
                  "restored."));
        }
        if (current != NULL)
            CFRelease(current);
        return;
    }

    if (!legacy_display_stack && !CGDisplayIsBuiltin(sys->stereo_display))
    {
        const int physical_private_mode = private_mode;
        if (SetVirtualFramePackingEDID(vd, true, eye_width, eye_height,
                                       content_rate))
        {
            private_mode = -1;
            for (unsigned i = 0; i < 300 && private_mode < 0; ++i)
            {
                private_mode = FindPrivateFramePackingMode(
                    sys->stereo_display, eye_width, packed_height,
                    content_rate);
                if (private_mode < 0)
                    usleep(100000);
            }
        }
        else if (sys->stereo_virtual_edid_enabled)
            SetVirtualFramePackingEDID(vd, false, 0, 0, 0.0);
        else
            private_mode = physical_private_mode;
    }

    if (!legacy_display_stack && private_mode >= 0)
    {
        VLCCGSGetCurrentDisplayMode get_current;
        VLCCGSGetNumberOfDisplayModes get_count;
        VLCCGSGetDisplayModeDescriptionOfLength describe;
        VLCCGSConfigureDisplayMode configure;
        int saved_private = -1;
        if (LoadCGSFunctions(&get_current, &get_count, &describe, &configure) &&
            get_current(sys->stereo_display, &saved_private) ==
                kCGErrorSuccess &&
            DetachStereoDisplayMirrors(vd))
        {
            VLC_UNUSED(get_count);
            VLC_UNUSED(describe);
            VLC_UNUSED(configure);
            /* Completing the unmirror transaction can republish the HDMI
             * display under another CGDirectDisplayID and reorder its private
             * mode list.  Reacquire both before configuring; using the mode
             * index found while mirrored fails with
             * kCGErrorConfigurationHasChanged on Apple Silicon. */
            if (!WaitForStereoDisplay(sys, 50))
                private_mode = -1;
            else
                private_mode = FindPrivateFramePackingMode(
                    sys->stereo_display, eye_width, packed_height,
                    content_rate);

            if (private_mode >= 0 &&
                get_current(sys->stereo_display, &saved_private) !=
                    kCGErrorSuccess)
                private_mode = -1;
            CGError error = private_mode >= 0
                ? ConfigurePrivateDisplayMode(sys->stereo_display,
                                              private_mode)
                : kCGErrorFailure;
            usleep(200000);
            int active_private = -1;
            get_current(sys->stereo_display, &active_private);
            if (error == kCGErrorSuccess && active_private == private_mode &&
                CGDisplayPixelsWide(sys->stereo_display) == eye_width &&
                CGDisplayPixelsHigh(sys->stereo_display) == packed_height)
            {
                sys->stereo_saved_private_mode = saved_private;
                sys->stereo_private_mode_changed = true;
                sys->stereo_saved_mode = current;
                sys->stereo_mode_changed = true;
                sys->stereo_mode_ready = true;
                current = NULL;
                msg_Info(vd, "switched HDMI scanout to private mode %d: "
                         "%zux%zu at %.3f Hz", private_mode, eye_width,
                         packed_height, content_rate);
                return;
            }
            msg_Warn(vd, "private HDMI frame-packing mode %d failed "
                     "(configure=%d active=%d pixels=%zux%zu)", private_mode,
                     error, active_private,
                     CGDisplayPixelsWide(sys->stereo_display),
                     CGDisplayPixelsHigh(sys->stereo_display));
            RestoreStereoDisplayMirrors(vd);
        }
        else
            msg_Warn(vd, "could not prepare private HDMI frame-packing mode");

        if (sys->stereo_virtual_edid_enabled)
            SetVirtualFramePackingEDID(vd, false, 0, 0, 0.0);
    }

    if (!DetachStereoDisplayMirrors(vd))
    {
        vlc_dialog_display_error(vd, _("HDMI 3D frame packing unavailable"),
                                 _("PowerVLC could not temporarily separate "
                                   "the HDMI display from its mirrored "
                                   "display before entering 3D mode."));
        CFRelease(current);
        return;
    }

    /* On recent macOS, ask CoreGraphics to put the link in stereo operation
     * link in stereo operation as well; on a display whose EDID marks the
     * timing as stacked-frame stereo this is the public API that lets the
     * driver emit the corresponding stereo signalling.  Never call it on the
     * Mavericks/Ivy Bridge stack: the exact DTD is sufficient there and the
     * stereo API itself is the reproduced kernel-panic trigger. */
    if (!legacy_display_stack && !CGDisplayIsStereo(sys->stereo_display))
    {
        CGError error = CGDisplaySetStereoOperation(sys->stereo_display, true,
                                                    false,
                                                    kCGConfigureForAppOnly);
        if (error != kCGErrorSuccess ||
            !CGDisplayIsStereo(sys->stereo_display))
        {
            msg_Warn(vd, "macOS rejected HDMI stereo operation (%d); "
                     "refusing a timing-only 3D mode", error);
            vlc_dialog_display_error(vd,
                         _("HDMI 3D frame packing unavailable"),
                         _("macOS did not enable stereo operation for this "
                           "display (error %d). PowerVLC will not use a "
                           "1920x2205 timing without HDMI 3D signalling."),
                         error);
            if (CGDisplayIsStereo(sys->stereo_display))
                CGDisplaySetStereoOperation(sys->stereo_display, false, false,
                                            kCGConfigureForAppOnly);
            RestoreStereoDisplayMirrors(vd);
            CFRelease(current);
            return;
        }
        sys->stereo_operation_changed = true;
        msg_Info(vd, "enabled CoreGraphics stereo operation for HDMI 3D");
    }

    CFArrayRef modes = CopyAllDisplayModesCompat(sys->stereo_display);
    VLCDisplayModeRef best = NULL;
    double best_score = 1e9;
    bool stereo_mode_ready = false;
    if (modes != NULL)
    {
        CFIndex count = CFArrayGetCount(modes);
        for (CFIndex i = 0; i < count; ++i)
        {
            VLCDisplayModeRef candidate =
                (VLCDisplayModeRef)CFArrayGetValueAtIndex(modes, i);
            size_t width = DisplayModePixelWidth(candidate);
            size_t height = DisplayModePixelHeight(candidate);
            if (width != eye_width || height != packed_height)
                continue;

            double refresh = DisplayModeRawRefresh(candidate);
            if (refresh < 1.0 || fabs(refresh - content_rate) > 0.2)
                continue;
            double score = fabs(refresh - content_rate);
            if (score < best_score)
            {
                best = candidate;
                best_score = score;
            }
        }
    }

    VLCDisplayModeRef active = CopyDisplayModeCompat(sys->stereo_display);
    if (best != NULL && (active == NULL ||
        DisplayModeIdentifier(best) != DisplayModeIdentifier(active)))
    {
        CFRetain(best);
        CGError error = SetDisplayModeCompat(sys->stereo_display, best);
        if (error == kCGErrorSuccess)
        {
            sys->stereo_saved_mode = current;
            sys->stereo_mode_changed = true;
            current = NULL;
            msg_Info(vd, "switched HDMI display to %zux%zu at %.3f Hz for MVC",
                     DisplayModePixelWidth(best),
                     DisplayModePixelHeight(best),
                     DisplayModeRefresh(best));
            stereo_mode_ready = true;
        }
        else
        {
            msg_Warn(vd, "could not select the HDMI frame-packing mode (%d)",
                     error);
            vlc_dialog_display_error(vd,
                         _("HDMI 3D frame packing unavailable"),
                         _("macOS rejected the %zux%zu frame-packed mode "
                           "at %.3f Hz (error %d)."),
                         eye_width, packed_height, content_rate, error);
        }
        CFRelease(best);
    }
    else if (best != NULL)
        stereo_mode_ready = true;
    else if (best == NULL)
    {
        msg_Warn(vd, "macOS exposes no true %zux%zu at %.3f Hz HDMI "
                 "frame-packing mode; refusing to substitute ordinary 1080p",
                 eye_width, packed_height, content_rate);
        vlc_dialog_display_error(vd, _("HDMI 3D frame packing unavailable"),
                                 _("macOS does not expose the required %zux%zu "
                                   "frame-packed mode at %.3f Hz for this "
                                   "display. PowerVLC will not substitute "
                                   "ordinary 1080p because it cannot carry "
                                   "MVC frame packing."),
                                 eye_width, packed_height, content_rate);
    }

    if (active != NULL)
        CFRelease(active);

    /* Some drivers leave stereo operation when changing timing.  Reassert it
     * and require CoreGraphics to confirm it before rendering frame packing. */
    if (!legacy_display_stack && stereo_mode_ready &&
        !CGDisplayIsStereo(sys->stereo_display))
    {
        CGError error = CGDisplaySetStereoOperation(sys->stereo_display, true,
                                                    false,
                                                    kCGConfigureForAppOnly);
        if (error != kCGErrorSuccess ||
            !CGDisplayIsStereo(sys->stereo_display))
        {
            msg_Warn(vd, "HDMI stereo operation was lost after mode switch (%d)",
                     error);
            vlc_dialog_display_error(vd,
                         _("HDMI 3D frame packing unavailable"),
                         _("macOS left stereo operation after selecting the "
                           "frame-packed timing (error %d)."), error);
            stereo_mode_ready = false;
        }
    }

    if (stereo_mode_ready)
    {
        if (sys->stereo_saved_mode == NULL &&
            sys->stereo_operation_changed)
        {
            sys->stereo_saved_mode = current;
            current = NULL;
        }
        sys->stereo_mode_ready = true;
    }
    else
    {
        if (sys->stereo_operation_changed)
        {
            CGDisplaySetStereoOperation(sys->stereo_display, false, false,
                                        kCGConfigureForAppOnly);
            sys->stereo_operation_changed = false;
        }
        if (sys->stereo_mode_changed && sys->stereo_saved_mode != NULL)
        {
            SetDisplayModeCompat(sys->stereo_display,
                                 sys->stereo_saved_mode);
            CFRelease(sys->stereo_saved_mode);
            sys->stereo_saved_mode = NULL;
            sys->stereo_mode_changed = false;
        }
        RestoreStereoDisplayMirrors(vd);
    }

    if (modes != NULL)
        CFRelease(modes);
    if (current != NULL)
        CFRelease(current);
}

static void ActivateStereoPresentation(vout_display_t *vd,
                                       bool enter_fullscreen)
{
    if (!vd->sys->stereo_mode_ready)
        return;
    /* A test build is commonly started through SSH.  In that case Finder
     * remains frontmost and Mavericks keeps its menu bar above VLC's native
     * fullscreen window.  Apart from being visible, the 2D bar is repeated
     * in both eyes.  Activate on AppKit's main thread before toggling
     * fullscreen so the GUI's normal fullscreen presentation options can
     * hide the menu bar and Dock. */
    [VLCOpenGLVideoView
        performSelectorOnMainThread:@selector(activateForStereoFullscreen:)
                         withObject:nil waitUntilDone:YES];
    SetStereoFullscreenDisplay(vd, true);
    /* A decoder/format handoff inherits an already-fullscreen HDMI session.
     * Replaying EnterStereoFullscreen() here used to enqueue fullscreen=false
     * followed by fullscreen=true on every BD-J clip transition.  AppKit then
     * briefly restored the desktop presentation options, producing a white
     * flash on the internal Mac display.  Only the first stereo display needs
     * to enter fullscreen; an adopted session must leave that state alone. */
    if (enter_fullscreen)
        EnterStereoFullscreen(vd);
}

static void ActivateDolbyPresentation(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (!sys->dovi_mode_ready)
        return;

    /* The HDMI transport and the AppKit window must name the same display.
     * The legacy interface has its own saved fullscreen preference and would
     * otherwise keep the view on the built-in panel while CADisplay sends an
     * LLDV link to the projector. */
    SetDolbyFullscreenDisplay(vd, true);

    vlc_object_t *vout = vd->obj.parent;
    if (vout != NULL && var_GetBool(vout, "fullscreen"))
    {
        /* The original fullscreen request is queued before the vout can
         * discover the Dolby-capable sink. Replay it now that the transient
         * destination is published and the video view exists. */
        var_SetBool(vout, "fullscreen", false);
        var_SetBool(vout, "fullscreen", true);
        msg_Info(vd, "reapplied fullscreen on Dolby Vision display %u",
                 sys->dovi_display);
    }
}

typedef struct
{
    CGDirectDisplayID display;
    bool attached;
} VLCVideoViewDisplayProbe;

/* Native fullscreen is asynchronous even on the legacy AppKit stack.  Do not
 * initialize the GL renderer while the video view still belongs to the old
 * desktop: Snow Leopard's NVIDIA driver then keeps the window drawable on
 * that framebuffer after Quartz publishes the private 1920x2205 scanout. */
static bool WaitForVideoViewOnStereoDisplay(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (!sys->stereo_mode_ready || sys->glView == nil)
        return true;

    for (unsigned i = 0; i < 150; ++i)
    {
        VLCVideoViewDisplayProbe probe = { sys->stereo_display, false };
        [sys->glView
            performSelectorOnMainThread:@selector(copyWindowDisplayID:)
                             withObject:[NSValue valueWithPointer:&probe]
                          waitUntilDone:YES];
        if (probe.attached)
        {
            [sys->glView
                performSelectorOnMainThread:
                    @selector(retargetDrawableForChangedDisplay)
                                 withObject:nil waitUntilDone:YES];
            msg_Info(vd, "OpenGL video view attached to HDMI display %u "
                     "before renderer initialization", sys->stereo_display);
            return true;
        }
        usleep(20000);
    }

    msg_Warn(vd, "OpenGL video view did not reach HDMI display %u before "
             "renderer initialization", sys->stereo_display);
    return false;
}

static void RestoreStereoDisplayMode(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    SetStereoDisplayTransition(vd, false);
    if (sys->stereo_synthetic_clamshell)
        BeginHDMIAudioReconfiguration(vd);
    sys->stereo_mode_ready = false;
    /* Release the fullscreen guard before asking the GUI to leave it. */
    SetStereoFullscreenDisplay(vd, false);
    if (sys->stereo_fullscreen_forced)
    {
        vlc_object_t *vout = vd->obj.parent;
        if (vout != NULL && var_GetBool(vout, "fullscreen"))
            var_SetBool(vout, "fullscreen", false);
        sys->stereo_fullscreen_forced = false;
    }

    bool operation_changed = sys->stereo_operation_changed;
    if (operation_changed)
    {
        CGError error = CGDisplaySetStereoOperation(sys->stereo_display, false,
                                                    false,
                                                    kCGConfigureForAppOnly);
        if (error != kCGErrorSuccess)
            msg_Warn(vd, "could not disable HDMI stereo operation (%d)", error);
        sys->stereo_operation_changed = false;
    }
    bool private_mode_restored = false;
    if (sys->stereo_private_mode_changed)
    {
        CGError error = ConfigurePrivateDisplayMode(
            sys->stereo_display, sys->stereo_saved_private_mode);
        if (error != kCGErrorSuccess)
            msg_Warn(vd, "could not restore the previous private HDMI "
                     "display mode (%d)", error);
        else
            private_mode_restored = true;
        sys->stereo_private_mode_changed = false;
    }

    /* First return to the physical EDID while the external display is still
     * independent. Restoring mirroring beforehand made DCP repeatedly resize
     * the fullscreen drawable and sometimes kept the display offline until
     * our 30-second wait expired. */
    if (sys->stereo_virtual_edid_enabled &&
        !SetVirtualFramePackingEDID(vd, false, 0, 0, 0.0))
        msg_Warn(vd, "could not restore the physical HDMI EDID");

    if (sys->stereo_saved_mode != NULL && !private_mode_restored)
    {
        CGError error = SetDisplayModeCompat(sys->stereo_display,
                                             sys->stereo_saved_mode);
        if (error != kCGErrorSuccess)
            msg_Warn(vd, "could not restore the previous HDMI display mode (%d)",
                     error);
    }
    if (sys->stereo_saved_mode != NULL)
        CFRelease(sys->stereo_saved_mode);
    sys->stereo_saved_mode = NULL;
    sys->stereo_mode_changed = false;

    RestoreStereoDisplayMirrors(vd);
    StopSyntheticClamshell(vd);
    /* Restore the exact CADisplay mode (including the user's previous HDR
     * choice) only after the desktop resolution/topology is back in place. */
    RestoreStereoDynamicRangeMode(vd);
    if (var_GetBool(vd->obj.libvlc, "macosx-hdmi-audio-reconfiguring"))
    {
        usleep(500000);
        EndHDMIAudioReconfiguration(vd);
    }
}

struct gl_sys
{
    CGLContextObj locked_ctx;
    VLCOpenGLVideoView *glView;
    vout_display_sys_t *display_sys;
};

static void *OurGetProcAddress(vlc_gl_t *gl, const char *name)
{
    VLC_UNUSED(gl);

    return dlsym(RTLD_DEFAULT, name);
}

static int Open (vlc_object_t *this)
{
    vout_display_t *vd = (vout_display_t *)this;
    vout_display_sys_t *sys = calloc (1, sizeof(*sys));

    if (!sys)
        return VLC_ENOMEM;

    /* explicit pool: @autoreleasepool is clang-only, this file is MRC */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    {
        if (!CGDisplayUsesOpenGLAcceleration (kCGDirectMainDisplay))
            msg_Err (this, "no OpenGL hardware acceleration found. this can lead to slow output and unexpected results");

        vd->sys = sys;
        sys->pool = NULL;
        sys->embed = NULL;
        sys->vgl = NULL;
        sys->gl = NULL;
        sys->profile_on = getenv("VLC_GL1_PROF") != NULL ||
                          getenv("VLC_MACOSX_PROF") != NULL;
        var_Create(vd->obj.parent, "macosx-glcontext", VLC_VAR_ADDRESS);
        var_Create(vd->obj.libvlc, "macosx-hdmi-audio-reconfiguring",
                   VLC_VAR_BOOL);
        var_Create(vd->obj.libvlc, "macosx-hdmi-audio-generation",
                   VLC_VAR_INTEGER);

        /* U1 (décodage DVD accéléré ATI) — GÉOMÉTRIE VIDÉO publiée par le vout.
         * Le vout display est la SOURCE DE VÉRITÉ du placement à l'écran : il
         * connaît la vue, sa fenêtre et le rectangle vidéo letterboxé exact (SAR
         * 4:3/16:9 compris, via vout_display_PlacePicture). On publie sur le bus
         * libvlc (partagé avec le décodeur libmpeg2) pour que la sortie HW ATI
         * puisse suivre la fenêtre/zone vidéo de VLC au lieu d'une fenêtre Carbon
         * séparée. wid = numéro de fenêtre CGS ; rect-x/y/w/h = rectangle vidéo
         * PLACÉ en coordonnées écran CGS (origine EN HAUT à gauche). wid=0 = pas
         * de fenêtre (vout fermé / vue hors hiérarchie). Publié depuis -reshape
         * (thread principal : initial, resize, plein écran, retour fenêtré). */
        var_Create(vd->obj.libvlc, "dvddriver-vout-wid",    VLC_VAR_INTEGER);
        var_Create(vd->obj.libvlc, "dvddriver-vout-rect-x", VLC_VAR_INTEGER);
        var_Create(vd->obj.libvlc, "dvddriver-vout-rect-y", VLC_VAR_INTEGER);
        var_Create(vd->obj.libvlc, "dvddriver-vout-rect-w", VLC_VAR_INTEGER);
        var_Create(vd->obj.libvlc, "dvddriver-vout-rect-h", VLC_VAR_INTEGER);
        var_SetInteger(vd->obj.libvlc, "dvddriver-vout-wid", 0);

        const bool adoptedStereo = AdoptStereoDisplayHandoff(vd);
        if (adoptedStereo)
            RetuneAdoptedStereoDisplay(vd);

        /* Get the drawable object */
        id container = var_CreateGetAddress (vd, "drawable-nsobject");
        if (container)
            vout_display_DeleteWindow (vd, NULL);
        else {
            sys->embed = vout_display_NewWindow (vd, VOUT_WINDOW_TYPE_NSOBJECT);
            if (sys->embed)
                container = sys->embed->handle.nsobject;

            if (!container) {
                msg_Err(vd, "No drawable-nsobject nor vout_window_t found, passing over.");
                goto error;
            }
        }

        /* This will be released in Close(), on
         * main thread, after we are done using it. */
        sys->container = [container retain];

        /* Display reconfiguration must precede NSOpenGLView construction.
         * On Mavericks, changing the HDMI timing after IOAccelerator has a
         * drawable is what made WindowServer enter the kernel-panic path. */
        if (adoptedStereo || IsFramePackableStereo(vd->fmt.multiview_mode))
            SetStereoDisplayTransition(vd, true);
        SelectStereoDisplayMode(vd);
        SelectDolbyDisplayMode(vd);

        /* Get our main view*/
        VLCOpenGLVideoViewCreationRequest viewRequest = {
            (id *)&sys->glView,
            vout_display_opengl_RequiresHDRRenderer(&vd->fmt) &&
                !sys->stereo_mode_ready &&
                !IsFramePackableStereo(vd->fmt.multiview_mode)
        };
        [VLCOpenGLVideoView performSelectorOnMainThread:@selector(getNewView:)
                                             withObject:[NSValue valueWithPointer:&viewRequest]
                                          waitUntilDone:YES];
        if (!sys->glView) {
            msg_Err(vd, "Initialization of open gl view failed");
            goto error;
        }

        [sys->glView setVoutDisplay:vd];

        /* The view must be in the window hierarchy before requesting the
         * automatic stereo fullscreen transition. */
        if ([(id)container respondsToSelector:@selector(addVoutSubview:)])
            [(id)container performSelectorOnMainThread:@selector(addVoutSubview:)
                                            withObject:sys->glView
                                         waitUntilDone:YES];
        else if ([container isKindOfClass:[NSView class]]) {
            NSView *parentView = container;
            [parentView performSelectorOnMainThread:@selector(addSubview:)
                                         withObject:sys->glView
                                      waitUntilDone:YES];
            [sys->glView performSelectorOnMainThread:@selector(setFrameToBoundsOfView:)
                                          withObject:[NSValue valueWithPointer:parentView]
                                       waitUntilDone:YES];
        } else {
            msg_Err(vd, "Invalid drawable-nsobject object. drawable-nsobject must either be an NSView or comply to the @protocol VLCOpenGLVideoViewEmbedding.");
            goto error;
        }

        /* Opening the file chooser while the projector is in 3D deliberately
         * leaves fullscreen so AppKit can show the panel.  The replacement
         * disc still adopts the retained HDMI timing, but that does not mean
         * its Cocoa window is fullscreen.  Re-enter only when the live vout
         * flag confirms that fullscreen was lost; ordinary BD-J clip changes
         * keep the flag set and therefore remain flash-free. */
        vlc_object_t *vout = vd->obj.parent;
        const bool needsStereoFullscreen = !adoptedStereo ||
            vout == NULL || !var_GetBool(vout, "fullscreen");

        /* The Cocoa fullscreen window survives vout and disc handoffs.  Its
         * frame belongs to the old NSScreen raster until AppKit is explicitly
         * told otherwise, so refit an adopted window which is still truly
         * fullscreen.  When the file chooser already left fullscreen, do not
         * move the ordinary window to HDMI: EnterStereoFullscreen() below
         * will create the projector window while preserving the ordinary
         * window's position on the internal display for the next double-click
         * exit. */
        if (adoptedStereo && !needsStereoFullscreen)
            [sys->glView
                performSelectorOnMainThread:
                    @selector(fitWindowToStereoDisplay:)
                                 withObject:[NSNumber numberWithUnsignedInt:
                                                sys->stereo_display]
                              waitUntilDone:YES];

        ActivateStereoPresentation(vd, needsStereoFullscreen);
        ActivateDolbyPresentation(vd);
        /* On Snow Leopard the GeForce 320M really needs the drawable attached
         * before renderer creation.  On modern macOS, however, fullscreen is
         * a vout control queued behind this very Open(): waiting here can
         * never make progress.  It merely lets a local Blu-ray demux tens of
         * seconds ahead before the renderer exists, producing the long black
         * start and late-picture purge seen on Apple Silicon. */
        if (floor(NSAppKitVersionNumber) < 1343)
            WaitForVideoViewOnStereoDisplay(vd);
        if (sys->stereo_mode_ready &&
            !sys->stereo_private_mode_changed)
            SelectStereoSDRDisplayMode(vd, false);
        SetStereoDisplayTransition(vd, false);

        /* Initialize common OpenGL video display */
        sys->gl = vlc_object_create(this, sizeof(*sys->gl));

        if( unlikely( !sys->gl ) )
            goto error;

        struct gl_sys *glsys = sys->gl->sys = malloc(sizeof(struct gl_sys));
        if( unlikely( !sys->gl->sys ) )
        {
            vlc_object_release(sys->gl);
            goto error;
        }
        glsys->locked_ctx = NULL;
        glsys->glView = sys->glView;
        glsys->display_sys = sys;
        sys->gl->makeCurrent = OpenglLock;
        sys->gl->releaseCurrent = OpenglUnlock;
        sys->gl->swap = OpenglSwap;
        sys->gl->getProcAddress = OurGetProcAddress;

        var_SetAddress(vd->obj.parent, "macosx-glcontext",
                       vlc_CGLContextOf([sys->glView openGLContext]));

        const vlc_fourcc_t *subpicture_chromas;

        if (vlc_gl_MakeCurrent(sys->gl) != VLC_SUCCESS)
        {
            msg_Err(vd, "Can't attach gl context");
            goto error;
        }
        sys->vgl = vout_display_opengl_New (&vd->fmt, &subpicture_chromas, sys->gl,
                                            &vd->cfg->viewpoint);
        if (sys->vgl != NULL)
            vout_display_opengl_SetDrawableSize(sys->vgl,
                                                vd->cfg->display.width,
                                                vd->cfg->display.height);
        if (sys->vgl && sys->stereo_mode_ready)
        {
            vout_display_opengl_SetFramePackingOutput(
                sys->vgl, true, sys->stereo_eye_width,
                sys->stereo_eye_height);

            /* CGLFlushDrawable with swap interval 1 waits for the next HDMI
             * vblank. Starting it at the picture PTS therefore presents one
             * complete scanout late on Mavericks (about 42 ms at 1080p24),
             * and small scheduling variations occasionally miss another
             * vblank. Let the core enter presentation just before the target
             * vblank. 720-line frame packing scans at 50/60 Hz, while the
             * Blu-ray 1080-line mode scans at 24 Hz. */
            var_Create(vd, "vout-presentation-advance", VLC_VAR_INTEGER);
            var_SetInteger(vd, "vout-presentation-advance",
                           sys->stereo_eye_height == 720 ? 18000 : 38000);
            msg_Info(vd, "expanding packed stereo source to HDMI frame packing "
                     "on the GPU (%ux%u per eye)", sys->stereo_eye_width,
                     sys->stereo_eye_height);
        }
        vlc_gl_ReleaseCurrent(sys->gl);
        if (!sys->vgl) {
            msg_Err(vd, "Error while initializing opengl display.");
            goto error;
        }

        /* The fullscreen window reached the private HDMI display before the
         * renderer was created, so any earlier AppKit reshape necessarily ran
         * while sys->vgl was NULL.  Replay it synchronously now: vd->cfg can
         * still contain the former 1080-line desktop size, whereas the actual
         * drawable is the complete 2205-line frame-packing raster. */
        if (sys->stereo_mode_ready)
            [sys->glView performSelectorOnMainThread:@selector(reshape)
                                           withObject:nil waitUntilDone:YES];

        /* */
        vout_display_info_t info = vd->info;
        info.has_pictures_invalid = false;
        info.subpicture_chromas = subpicture_chromas;

        /* Setup vout_display_t once everything is fine */
        vd->info = info;

        vd->pool = Pool;
        vd->prepare = PictureRender;
        vd->display = PictureDisplay;
        vd->control = Control;

        /* */
        vout_display_SendEventDisplaySize (vd, vd->fmt.i_visible_width, vd->fmt.i_visible_height);

        [pool release];
        return VLC_SUCCESS;

    error:
        Close(this);
        [pool release];
        return VLC_EGENERIC;
    }
}

void Close (vlc_object_t *this)
{
    vout_display_t *vd = (vout_display_t *)this;
    vout_display_sys_t *sys = vd->sys;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    {
        RestoreDolbyDisplayMode(vd);
        if (!ParkStereoDisplayHandoff(vd))
            RestoreStereoDisplayMode(vd);
        [sys->glView setVoutDisplay:nil];

        var_Destroy (vd, "drawable-nsobject");
        if ([(id)sys->container respondsToSelector:@selector(removeVoutSubview:)])
        /* This will retain sys->glView */
            [(id)sys->container performSelectorOnMainThread:@selector(removeVoutSubview:)
                                                 withObject:sys->glView
                                              waitUntilDone:NO];

        /* release on main thread as explained in Open() */
        [(id)sys->container performSelectorOnMainThread:@selector(release)
                                             withObject:nil
                                          waitUntilDone:NO];
        [sys->glView performSelectorOnMainThread:@selector(removeFromSuperview)
                                      withObject:nil
                                   waitUntilDone:NO];

        var_Destroy(vd->obj.parent, "macosx-glcontext");

        /* U1 : le vout se ferme → plus de fenêtre vidéo. Publier wid=0 (que le
         * décodeur HW lit à chaque display : 0 = ne rien présenter dans la
         * fenêtre VLC) AVANT de détruire les variables. */
        var_SetInteger(vd->obj.libvlc, "dvddriver-vout-wid", 0);
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-wid");
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-rect-x");
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-rect-y");
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-rect-w");
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-rect-h");

        if (sys->vgl != NULL)
        {
            vlc_gl_MakeCurrent(sys->gl);
            vout_display_opengl_Delete (sys->vgl);
            vlc_gl_ReleaseCurrent(sys->gl);
        }

        if (sys->gl != NULL)
        {
            assert(((struct gl_sys *)sys->gl->sys)->locked_ctx == NULL);
            free(sys->gl->sys);
            vlc_object_release(sys->gl);
        }

        [sys->glView release];

        if (sys->embed)
            vout_display_DeleteWindow (vd, sys->embed);
        free (sys);
    }
    [pool release];
}

/*****************************************************************************
 * vout display callbacks
 *****************************************************************************/

static picture_pool_t *Pool (vout_display_t *vd, unsigned requested_count)
{
    vout_display_sys_t *sys = vd->sys;

    if (sys->stereo_mode_ready && floor(NSAppKitVersionNumber) < 1138 &&
        requested_count > 16)
    {
        msg_Dbg(vd, "limiting Snow Leopard MVC display pool from %u to 16",
                requested_count);
        requested_count = 16;
    }

    /* Look-ahead decode cache (video-cache-mb): the decoder renders straight
     * into this pool, so the cache is whatever headroom it has past the DPB.
     * The core requests a fixed count, so without this the headroom is 0 and
     * decoder.c switches the cache off -- measured on 10.6: budget 1 GiB,
     * target 331 pictures before clamping, headroom 0, cache dead. This is the
     * same thing macosx_gl1.m does for the legacy GL path. The pictures are
     * plain system memory and vout_display_opengl_GetPool() caps the total at
     * VLCGL_PICTURE_MAX. */
    unsigned extra = vout_display_CacheExtraPictures (vd, 0);
    if (extra > 0)
    {
        if (requested_count + extra > VLCGL_PICTURE_MAX)
            extra = requested_count < VLCGL_PICTURE_MAX
                  ? VLCGL_PICTURE_MAX - requested_count : 0;
        /* Under the floor the cache is off anyway: do not pay for them. */
        if (extra < 26)
            extra = 0;
        else
        {
            msg_Dbg (vd, "look-ahead cache: %u extra pool pictures", extra);
            requested_count += extra;
        }
    }

    if (!sys->pool && vlc_gl_MakeCurrent(sys->gl) == VLC_SUCCESS)
    {
        sys->pool = vout_display_opengl_GetPool (sys->vgl, requested_count);
        vlc_gl_ReleaseCurrent(sys->gl);
    }
    return sys->pool;
}

static void PictureRender (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture)
{

    vout_display_sys_t *sys = vd->sys;
    vlc_tick_t started = sys->profile_on ? mdate() : 0;

    if (vlc_gl_MakeCurrent(sys->gl) == VLC_SUCCESS)
    {
        vout_display_opengl_Prepare (sys->vgl, pic, subpicture);
        vlc_gl_ReleaseCurrent(sys->gl);
    }
    if (sys->profile_on)
        sys->profile_prepare += mdate() - started;
}

static void PictureDisplay (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;
    vlc_tick_t started = sys->profile_on ? mdate() : 0;
    [sys->glView setVoutFlushing:YES];
    if (vlc_gl_MakeCurrent(sys->gl) == VLC_SUCCESS)
    {
        /* Runtime AppKit version check instead of @available: the latter
         * compiles into compiler-rt's __isOSVersionAtLeast, which relies on
         * Grand Central Dispatch (dispatch_once_f), absent on Mac OS X 10.5.
         * 1671 is NSAppKitVersionNumber10_14 (not spelled with the named
         * constant, which older SDK headers lack). */
        if (floor(NSAppKitVersionNumber) >= 1671) {
            vout_display_opengl_SetDrawableSize(vd->sys->vgl,
                                                vd->cfg->display.width,
                                                vd->cfg->display.height);
            if (sys->stereo_mode_ready)
                vout_display_opengl_Viewport(vd->sys->vgl, 0, 0,
                                             vd->cfg->display.width,
                                             vd->cfg->display.height);
            else {
                vout_display_place_t place;
                vout_display_PlacePicture(&place, &vd->source, vd->cfg, false);
                vout_display_opengl_Viewport(vd->sys->vgl, place.x,
                                             vd->cfg->display.height -
                                             (place.y + place.height),
                                             place.width, place.height);
            }
        }

        vout_display_opengl_Display (sys->vgl, &vd->source);
        vlc_gl_ReleaseCurrent(sys->gl);
    }
    [sys->glView setVoutFlushing:NO];
    picture_Release (pic);
    sys->has_first_frame = true;

    if (subpicture)
        subpicture_Delete(subpicture);

    if (sys->profile_on)
    {
        sys->profile_display += mdate() - started;
        if (++sys->profile_frames == 120)
        {
            msg_Dbg(vd, "macosx profile (120 frames): prepare %llu us/f, "
                         "display %llu us/f, swap %llu us/f, other %llu us/f",
                    (unsigned long long)sys->profile_prepare / 120,
                    (unsigned long long)sys->profile_display / 120,
                    (unsigned long long)sys->profile_swap / 120,
                    (unsigned long long)(sys->profile_display -
                                         sys->profile_swap) / 120);
            sys->profile_prepare = 0;
            sys->profile_display = 0;
            sys->profile_swap = 0;
            sys->profile_frames = 0;
        }
    }
}

static int ControlInPool (vout_display_t *vd, int query, va_list ap)
{
    vout_display_sys_t *sys = vd->sys;

    {
        switch (query)
        {
            case VOUT_DISPLAY_CHANGE_DISPLAY_FILLED:
            case VOUT_DISPLAY_CHANGE_ZOOM:
            case VOUT_DISPLAY_CHANGE_SOURCE_ASPECT:
            case VOUT_DISPLAY_CHANGE_SOURCE_CROP:
            case VOUT_DISPLAY_CHANGE_DISPLAY_SIZE:
            {
                const vout_display_cfg_t *cfg;

                if (query == VOUT_DISPLAY_CHANGE_SOURCE_ASPECT || query == VOUT_DISPLAY_CHANGE_SOURCE_CROP) {
                    cfg = vd->cfg;
                } else {
                    cfg = (const vout_display_cfg_t*)va_arg (ap, const vout_display_cfg_t *);
                }

                /* we always use our current frame here, because we have some size constraints
                 in the ui vout provider */
                vout_display_cfg_t cfg_tmp = *cfg;

                /* Reverse vertical alignment as the GL tex are Y inverted */
                if (cfg_tmp.align.vertical == VOUT_DISPLAY_ALIGN_TOP)
                    cfg_tmp.align.vertical = VOUT_DISPLAY_ALIGN_BOTTOM;
                else if (cfg_tmp.align.vertical == VOUT_DISPLAY_ALIGN_BOTTOM)
                    cfg_tmp.align.vertical = VOUT_DISPLAY_ALIGN_TOP;

                vout_display_place_t place;
                if (sys->stereo_mode_ready)
                {
                    /* The private HDMI raster includes the mandatory
                     * frame-packing blanking interval. A source crop/aspect
                     * notification at a BD-J menu loop must not replace the
                     * full-raster viewport with a normal 16:9 placement. */
                    place.x = 0;
                    place.y = 0;
                    place.width = cfg_tmp.display.width;
                    place.height = cfg_tmp.display.height;
                }
                else
                    vout_display_PlacePicture(&place, &vd->source, &cfg_tmp,
                                              false);
                @synchronized (sys->glView) {
                    sys->place = place;
                }

                if (vlc_gl_MakeCurrent (sys->gl) != VLC_SUCCESS)
                    return VLC_EGENERIC;
                vout_display_opengl_SetDrawableSize(sys->vgl,
                                                    cfg_tmp.display.width,
                                                    cfg_tmp.display.height);
                vout_display_opengl_SetWindowAspectRatio(sys->vgl, (float)place.width / place.height);

                /* For resize, we call glViewport in reshape and not here.
                 This has the positive side effect that we avoid erratic sizing as we animate every resize. */
                if (query != VOUT_DISPLAY_CHANGE_DISPLAY_SIZE)
                    // x / y are top left corner, but we need the lower left one
                    vout_display_opengl_Viewport(sys->vgl, place.x,
                                                 cfg_tmp.display.height - (place.y + place.height),
                                                 place.width, place.height);
                vlc_gl_ReleaseCurrent (sys->gl);

                return VLC_SUCCESS;
            }

            case VOUT_DISPLAY_CHANGE_VIEWPOINT:
                return vout_display_opengl_SetViewpoint (sys->vgl,
                    &va_arg (ap, const vout_display_cfg_t* )->viewpoint);

            case VOUT_DISPLAY_RESET_PICTURES:
                vlc_assert_unreachable ();
            default:
                msg_Err (vd, "Unknown request in Mac OS X vout display");
                return VLC_EGENERIC;
        }
    }
}

static int Control (vout_display_t *vd, int query, va_list ap)
{
    if (!vd->sys)
        return VLC_EGENERIC;

    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    int ret = ControlInPool (vd, query, ap);
    [pool release];
    return ret;
}

/*****************************************************************************
 * vout opengl callbacks
 *****************************************************************************/
static int OpenglLock (vlc_gl_t *gl)
{
    struct gl_sys *sys = gl->sys;
    if (![sys->glView respondsToSelector:@selector(openGLContext)])
        return 1;

    assert(sys->locked_ctx == NULL);

    NSOpenGLContext *context = [sys->glView openGLContext];
    CGLContextObj cglcntx = vlc_CGLContextOf(context);
    if (context == nil || cglcntx == NULL)
        return 1;

    CGLError err = vlc_CGLLockContext (cglcntx);
    if (kCGLNoError == err) {
        sys->locked_ctx = cglcntx;
        [context makeCurrentContext];
        return 0;
    }
    return 1;
}

static void OpenglUnlock (vlc_gl_t *gl)
{
    struct gl_sys *sys = gl->sys;
    vlc_CGLUnlockContext (sys->locked_ctx);
    sys->locked_ctx = NULL;
}

static void OpenglSwap (vlc_gl_t *gl)
{
    struct gl_sys *sys = gl->sys;
    vout_display_sys_t *display_sys = sys->display_sys;
    vlc_tick_t started = display_sys->profile_on ? mdate() : 0;
    [[sys->glView openGLContext] flushBuffer];
    if (display_sys->profile_on)
        display_sys->profile_swap += mdate() - started;
}

/*****************************************************************************
 * Our NSView object
 *****************************************************************************/
@implementation VLCOpenGLVideoView

+ (void)getNewView:(NSValue *)value
{
    VLCOpenGLVideoViewCreationRequest *request = [value pointerValue];
    *request->view = [[self alloc]
        initWithExtendedDynamicRange:request->wantsExtendedDynamicRange];
}

+ (void)activateForStereoFullscreen:(id)unused
{
    VLC_UNUSED(unused);
    VLCAssertMainThread();

    /* A bundle started with `open --args` on older macOS can still inherit a
     * prohibited/accessory activation policy from its command-line startup.
     * In that state -activateIgnoringOtherApps: is a no-op: Finder remains
     * frontmost and its Dock is composited over the lower MVC eye.  Promote
     * the already-running NSApplication (this does not launch another app).
     * The selector check keeps the module loadable on the 10.4 floor. */
    BOOL regular = NO;
    if ([NSApp respondsToSelector:@selector(setActivationPolicy:)]) {
        typedef BOOL (*VLCSetActivationPolicy)(id, SEL, long);
        VLCSetActivationPolicy set_policy = (VLCSetActivationPolicy)
            [NSApp methodForSelector:@selector(setActivationPolicy:)];
        /* NSApplicationActivationPolicyRegular has always been zero; using
         * the numeric ABI value keeps the 10.4 SDK buildable. */
        regular = set_policy(NSApp, @selector(setActivationPolicy:), 0);
    }
    /* Mavericks can return YES above without assigning an application serial
     * number when the bundle was opened with command-line arguments.  The
     * Process Manager promotion is the authoritative path on the legacy
     * stack and is available on PowerVLC's full 10.4+ range. */
    if (!regular || floor(NSAppKitVersionNumber) < 1343)
    {
        typedef struct {
            uint32_t highLongOfPSN;
            uint32_t lowLongOfPSN;
        } VLCProcessSerialNumber;
        typedef int32_t (*VLCGetCurrentProcess)(VLCProcessSerialNumber *);
        typedef int32_t (*VLCTransformProcessType)(
            const VLCProcessSerialNumber *, uint32_t);
        typedef int32_t (*VLCSetFrontProcess)(
            const VLCProcessSerialNumber *);
        VLCGetCurrentProcess get_current =
            (VLCGetCurrentProcess)dlsym(RTLD_DEFAULT, "GetCurrentProcess");
        VLCTransformProcessType transform = (VLCTransformProcessType)
            dlsym(RTLD_DEFAULT, "TransformProcessType");
        VLCSetFrontProcess set_front =
            (VLCSetFrontProcess)dlsym(RTLD_DEFAULT, "SetFrontProcess");
        VLCProcessSerialNumber psn;
        if (get_current != NULL && transform != NULL &&
            get_current(&psn) == 0)
        {
            /* kProcessTransformToForegroundApplication (10.3+). */
            transform(&psn, 1);
            if (set_front != NULL)
                set_front(&psn);
        }
    }
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)copyWindowDisplayID:(NSValue *)value
{
    VLCAssertMainThread();
    VLCVideoViewDisplayProbe *probe = [value pointerValue];
    NSScreen *screen = [[self window] screen];
    NSNumber *number = [[screen deviceDescription]
        objectForKey:@"NSScreenNumber"];
    probe->attached = number != nil &&
        [number unsignedIntValue] == probe->display;
}


/**
 * Gets called by the Open() method.
 */
- (id)initWithExtendedDynamicRange:(BOOL)wantsExtendedDynamicRange
{
    VLCAssertMainThread();

    /* Warning - this may be called on non main thread */

    NSOpenGLPixelFormatAttribute attribs[] =
    {
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        NSOpenGLPFANoRecovery,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize, 8,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFAWindow,
#if !defined(MAC_OS_X_VERSION_MAX_ALLOWED) || MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
        /* 10.5+; Tiger has no offline renderers to allow anyway */
        NSOpenGLPFAAllowOfflineRenderers,
#endif
        0
    };

    NSOpenGLPixelFormat *fmt = nil;

#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED >= 101100
    /* AppKit's EDR OpenGL path preserves values above SDR white only with a
     * floating-point drawable. Prefer RGBA16F on 10.11+ and retain the
     * ordinary 8-bit format as a compatibility fallback for GPUs/drivers
     * which cannot expose such a window surface. */
    if (wantsExtendedDynamicRange && floor(NSAppKitVersionNumber) >= 1404)
    {
        NSOpenGLPixelFormatAttribute edrAttribs[] =
        {
            NSOpenGLPFADoubleBuffer,
            NSOpenGLPFAAccelerated,
            NSOpenGLPFANoRecovery,
            /* libplacebo 7, which performs Dolby Vision reshaping and FEL
             * reconstruction, requires desktop OpenGL 3 or newer. The
             * floating EDR drawable is only attempted on 10.11+, where
             * Apple's 4.1 Core profile is available. */
            /* Numeric ABI values avoid a hard 10.7/10.10 availability
             * annotation while the surrounding runtime gate keeps this
             * path at 10.11+.  PowerVLC itself must still deploy to 10.6. */
            (NSOpenGLPixelFormatAttribute)99,
            (NSOpenGLPixelFormatAttribute)0x4100,
            NSOpenGLPFAColorFloat,
            NSOpenGLPFAColorSize, 64,
            NSOpenGLPFADepthSize, 24,
            /* Core-profile floating formats are rejected by AppKit when
             * NSOpenGLPFAWindow is specified explicitly. NSOpenGLView adds
             * the drawable attachment itself. */
            NSOpenGLPFAAllowOfflineRenderers,
            0
        };
        fmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:edrAttribs];
        if (!fmt)
        {
            /* The HDR renderer still needs OpenGL >= 3 when AppKit cannot
             * create a floating EDR drawable and SDR tone mapping is used. */
            NSOpenGLPixelFormatAttribute sdrCoreAttribs[] =
            {
                NSOpenGLPFADoubleBuffer,
                NSOpenGLPFAAccelerated,
                NSOpenGLPFANoRecovery,
                (NSOpenGLPixelFormatAttribute)99,
                (NSOpenGLPixelFormatAttribute)0x4100,
                NSOpenGLPFAColorSize, 24,
                NSOpenGLPFAAlphaSize, 8,
                NSOpenGLPFAAllowOfflineRenderers,
                0
            };
            fmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:sdrCoreAttribs];
        }
    }
#endif

    if (!fmt)
        fmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];

    if (!fmt)
        return nil;

    self = [super initWithFrame:NSMakeRect(0,0,10,10) pixelFormat:fmt];
    [fmt release];

    if (!self)
        return nil;

    /* enable HiDPI support (10.7+) */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
    if ([self respondsToSelector:@selector(setWantsBestResolutionOpenGLSurface:)]) {
        [self setWantsBestResolutionOpenGLSurface:YES];
    }
#pragma clang diagnostic pop

    /* request our screen's HDR mode (introduced in OS X 10.11) */
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
    if (wantsExtendedDynamicRange &&
        [self respondsToSelector:@selector(setWantsExtendedDynamicRangeOpenGLSurface:)]) {
        [self setWantsExtendedDynamicRangeOpenGLSurface:YES];
    }
#pragma clang diagnostic pop

    /* Swap buffers only during the vertical retrace of the monitor.
     http://developer.apple.com/documentation/GraphicsImaging/
     Conceptual/OpenGL/chap5/chapter_5_section_44.html */
    GLint params[] = { 1 };
    /* No CGL context to set it on below 10.3 (see vlc_CGLContextOf): the
     * output then simply swaps without waiting for the retrace. */
    CGLContextObj swapCtx = vlc_CGLContextOf([self openGLContext]);
    if (swapCtx != NULL)
        CGLSetParameter (swapCtx, kCGLCPSwapInterval, params);

    /* Use the classic observer API: the block-based variant requires
     * Mac OS X 10.6 and the blocks runtime. */
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidChangeScreenParameters:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:[NSApplication sharedApplication]];

    /* A frame-packing mode switch moves the same NSOpenGLView from the
     * Retina panel (2x backing) to an HDMI scanout (1x backing). AppKit can
     * deliver the global display notification before the fullscreen window
     * has reached its destination, leaving the GL viewport at the old 2x
     * size. String notification names keep this source buildable with the
     * pre-10.7 SDKs where backing-store notifications were not declared. */
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(windowGeometryDidChange:)
                                                 name:@"NSWindowDidChangeScreenNotification"
                                               object:nil];
    /* Do not observe NSWindowDidChangeBackingPropertiesNotification here.
     * Updating an NSOpenGLContext can itself emit that notification on recent
     * AppKit, which fed back into updateForChangedDisplay and generated an
     * endless stream of reshape events after a seek.  The window-screen event
     * plus the delayed global-display pass cover the Retina-to-HDMI move. */

    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    return self;
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification
{
    [self performSelectorOnMainThread:@selector(updateForChangedDisplay)
                           withObject:nil
                        waitUntilDone:NO];
    /* Fullscreen uses an AppKit animation; its last frame can occur after the
     * display notification. Re-evaluate once that transition has settled. */
    [self performSelector:@selector(updateForChangedDisplay)
               withObject:nil afterDelay:0.6];
}

- (void)windowGeometryDidChange:(NSNotification *)notification
{
    if ([notification object] != [self window])
        return;
    [self performSelectorOnMainThread:@selector(retargetDrawableForChangedDisplay)
                           withObject:nil
                        waitUntilDone:NO];
    [self performSelector:@selector(retargetDrawableForChangedDisplay)
               withObject:nil afterDelay:0.1];
}

- (GLint)desiredSwapInterval
{
    @synchronized(self) {
        /* On Snow Leopard's GeForce 320M the 24 Hz frame-packed swap blocks
         * for 28-33 ms and serializes VDA behind the presentation engine.
         * VLC already performs PTS pacing; an immediate driver swap measured
         * 2-6 ms and sustained 23.976 fps with no late frames after warm-up.
         * Keep ordinary vblank synchronization everywhere else. */
        if (vd != NULL && vd->sys->stereo_mode_ready &&
            floor(NSAppKitVersionNumber) < 1138)
            return 0;
    }
    return 1;
}

/* On the Snow Leopard NVIDIA stack, -[NSOpenGLContext update] refreshes the
 * drawable geometry but does not necessarily move the drawable off the old
 * framebuffer.  This is observable after the legacy HDMI transaction: the
 * host window has the external 1920x2205 frame, yet swaps still reach the
 * physically scanning built-in panel and HDMI remains black.  Reattaching the
 * existing context preserves all GL objects while making AppKit choose the
 * framebuffer of the window's new screen. */
- (void)retargetDrawableForChangedDisplay
{
    NSOpenGLContext *context = [self openGLContext];
    CGLContextObj cgl = vlc_CGLContextOf(context);
    if (context == nil || cgl == NULL)
        return;

    if (vlc_CGLLockContext(cgl) == kCGLNoError)
    {
        [context clearDrawable];
        [context setView:self];
        [context update];
        GLint interval = [self desiredSwapInterval];
        CGLSetParameter(cgl, kCGLCPSwapInterval, &interval);
        vlc_CGLUnlockContext(cgl);
    }
    [self reshape];
}

- (void)updateForChangedDisplay
{
    /* The drawable can move from the built-in 60 Hz panel to an external
     * 23.976/24 Hz frame-packing scanout while the same NSOpenGLContext stays
     * alive. Explicitly retarget it, then reassert swap-to-vblank so buffer
     * swaps cannot remain paced by the old display. */
    [self update];
    CGLContextObj context = vlc_CGLContextOf([self openGLContext]);
    if (context != NULL)
    {
        GLint interval = [self desiredSwapInterval];
        CGLSetParameter(context, kCGLCPSwapInterval, &interval);
    }
    [self reshape];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

/**
 * Gets called by the Open() method.
 */
- (void)setFrameToBoundsOfView:(NSValue *)value
{
    NSView *parentView = [value pointerValue];
    [self setFrame:[parentView bounds]];
}

- (void)fitWindowToStereoDisplay:(NSNumber *)displayNumber
{
    VLCAssertMainThread();

    NSScreen *target = nil;
    NSEnumerator *screenEnumerator = [[NSScreen screens] objectEnumerator];
    NSScreen *screen;
    while ((screen = [screenEnumerator nextObject]) != nil)
    {
        NSNumber *number = [[screen deviceDescription]
                            objectForKey:@"NSScreenNumber"];
        if ([number unsignedIntValue] == [displayNumber unsignedIntValue])
        {
            target = screen;
            break;
        }
    }

    NSWindow *window = [self window];
    if (target == nil || window == nil)
        return;

    /* The fullscreen window survives vout handoffs. After changing from the
     * 1920x2205 timing to 1280x1470 AppKit otherwise keeps its old frame,
     * making the new drawable 1920x2205 with its top 735 lines off-screen.
     * Resize that existing window in place; do not toggle fullscreen, which
     * would flash the internal display and briefly make the projector leave
     * 3D. */
    [window setFrame:[target frame] display:YES animate:NO];
    NSView *parent = [self superview];
    if (parent != nil)
        [self setFrame:[parent bounds]];
    /* A private timing republishes the NSScreen and WindowServer can put
     * Finder in front even though VLC's logical fullscreen flag never
     * changed.  Re-front the existing borderless window without replaying a
     * fullscreen false/true edge (which exposes the desktop and ultimately
     * leaves some BD-J menus windowed). */
    [NSApp activateIgnoringOtherApps:YES];
    [window orderFrontRegardless];
    [window makeKeyWindow];
    [window displayIfNeeded];
}

/**
 * Gets called by the Close and Open methods.
 * (Non main thread).
 */
- (void)setVoutDisplay:(vout_display_t *)aVd
{
    @synchronized(self) {
        vd = aVd;
    }
}

/**
 * Gets called when the vout will acquire the lock and flush.
 * (Non main thread).
 */
- (void)setVoutFlushing:(BOOL)flushing
{
    if (!flushing)
        return;
    @synchronized(self) {
        _hasPendingReshape = NO;
    }
}

/**
 * Can -drawRect skip rendering?.
 */
- (BOOL)canSkipRendering
{
    VLCAssertMainThread();

    @synchronized(self) {
        BOOL hasFirstFrame = vd && vd->sys->has_first_frame;
        return !_hasPendingReshape && hasFirstFrame;
    }
}


/**
 * Local method that locks the gl context.
 */
- (BOOL)lockgl
{
    VLCAssertMainThread();
    NSOpenGLContext *context = [self openGLContext];
    CGLError err = vlc_CGLLockContext (vlc_CGLContextOf(context));
    if (err == kCGLNoError)
        [context makeCurrentContext];
    return err == kCGLNoError;
}

/**
 * Local method that unlocks the gl context.
 */
- (void)unlockgl
{
    VLCAssertMainThread();
    vlc_CGLUnlockContext (vlc_CGLContextOf([self openGLContext]));
}

/**
 * Local method that force a rendering of a frame.
 * This will get called if Cocoa forces us to redraw (via -drawRect).
 */
- (void)render
{
    VLCAssertMainThread();

    // We may have taken some times to take the opengl Lock.
    // Check here to see if we can just skip the frame as well.
    if ([self canSkipRendering])
        return;

    BOOL hasFirstFrame;
    @synchronized(self) { // vd can be accessed from multiple threads
        hasFirstFrame = vd && vd->sys->has_first_frame;
    }

    if (hasFirstFrame)
        // This will lock gl.
        vout_display_opengl_Display (vd->sys->vgl, &vd->source);
    else
        glClear (GL_COLOR_BUFFER_BIT);
}

/**
 * Method called by Cocoa when the view is resized.
 */
- (void)reshape
{
    VLCAssertMainThread();

    /* on HiDPI displays, the point bounds don't equal the actual pixel based bounds */
    NSRect bounds = vlcConvertRectToBacking(self, [self bounds]);
    vout_display_place_t place;

    @synchronized(self) {
        if (vd) {
            vout_display_cfg_t cfg_tmp = *(vd->cfg);
            cfg_tmp.display.width  = bounds.size.width;
            cfg_tmp.display.height = bounds.size.height;

            /* A frame-packed HDMI timing is not an ordinary video canvas.
             * Its 45-line active-space separator has to land at the exact
             * CEA scanlines (1080 + 45 + 1080).  PlacePicture sees the
             * compact 1920x2160 source aspect and would otherwise center it
             * inside 1920x2205, adding 22/23-line outer margins and shifting
             * both eyes out of the positions expected by the sink. */
            if (vd->sys->stereo_mode_ready)
            {
                place.x = 0;
                place.y = 0;
                place.width = bounds.size.width;
                place.height = bounds.size.height;
                msg_Info(vd, "HDMI frame-packing drawable is %dx%d "
                         "(configured display was %ux%u)",
                         (int)bounds.size.width, (int)bounds.size.height,
                         vd->cfg->display.width, vd->cfg->display.height);
            }
            else
                vout_display_PlacePicture(&place, &vd->source, &cfg_tmp,
                                          false);
            vd->sys->place = place;
            vout_display_SendEventDisplaySize (vd, bounds.size.width, bounds.size.height);

            /* U1 — publier la géométrie vidéo (numéro de fenêtre CGS + rectangle
             * vidéo placé en coordonnées écran CGS top-left) sur le bus libvlc.
             * Thread principal (VLCAssertMainThread) : accès AppKit fenêtre/écran OK.
             * NB : place et bounds sont en pixels BACKING ; on suppose 1× (cible
             * G3/G4 non-HiDPI) → backing == points, donc pas de reconversion. */
            NSWindow *win = [self window];
            long widNum = win ? (long)[win windowNumber] : 0;
            if (win && widNum > 0) {
                float viewH = bounds.size.height;      /* même espace que place */
                /* place : origine EN HAUT à gauche dans la vue → rect AppKit vue
                 * (origine en bas à gauche). */
                NSRect vrect = NSMakeRect(place.x, viewH - (place.y + place.height),
                                          place.width, place.height);
                NSRect wrect = [self convertRect:vrect toView:nil];   /* → fenêtre */
                NSPoint sOrg = [win convertBaseToScreen:wrect.origin]; /* → écran (10.5-safe) */
                /* Écran « zéro » (barre de menus) = origine des coordonnées CGS
                 * globales ; sa hauteur sert au flip vers l'origine haut-gauche. */
                NSArray *screens = [NSScreen screens];
                NSScreen *zero = [screens count] ? [screens objectAtIndex:0]
                                                 : [NSScreen mainScreen];
                float screenH = [zero frame].size.height;
                long rx = lround(sOrg.x);
                long ry = lround(screenH - (sOrg.y + wrect.size.height));
                long rw = lround(wrect.size.width);
                long rh = lround(wrect.size.height);
                var_SetInteger(vd->obj.libvlc, "dvddriver-vout-rect-x", rx);
                var_SetInteger(vd->obj.libvlc, "dvddriver-vout-rect-y", ry);
                var_SetInteger(vd->obj.libvlc, "dvddriver-vout-rect-w", rw);
                var_SetInteger(vd->obj.libvlc, "dvddriver-vout-rect-h", rh);
                var_SetInteger(vd->obj.libvlc, "dvddriver-vout-wid", widNum);
                msg_Dbg(vd, "U1 géométrie vout : wid=%ld rect=%ld,%ld %ldx%ld (écran H=%d)",
                        widNum, rx, ry, rw, rh, (int)screenH);
            } else {
                var_SetInteger(vd->obj.libvlc, "dvddriver-vout-wid", 0);
                msg_Dbg(vd, "U1 géométrie vout : pas de fenêtre (wid=0)");
            }
        }
    }

    if ([self lockgl]) {
        /* NSOpenGLView does not always retarget its context when a fullscreen
         * window changes screen during the same display reconfiguration. */
        [[self openGLContext] update];
        GLint interval = [self desiredSwapInterval];
        CGLContextObj context = vlc_CGLContextOf([self openGLContext]);
        if (context != NULL)
            CGLSetParameter(context, kCGLCPSwapInterval, &interval);

        /* CGFloat is not exposed by the 10.4 SDK headers used by the i386
         * legacy build.  The OpenGL helper consumes a float anyway. */
        float edrHeadroom = 1.0f;
#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED >= 101100
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        NSScreen *screen = [[self window] screen];
        if ([screen respondsToSelector:
                     @selector(maximumExtendedDynamicRangeColorComponentValue)])
            edrHeadroom = [screen maximumExtendedDynamicRangeColorComponentValue];
#pragma clang diagnostic pop
#endif
        if (vd != NULL && vd->sys->vgl != NULL)
        {
            vout_display_opengl_SetDrawableSize(vd->sys->vgl,
                                                bounds.size.width,
                                                bounds.size.height);
            vout_display_opengl_SetDisplayHeadroom(vd->sys->vgl,
                                                   edrHeadroom);
        }

        // x / y are top left corner, but we need the lower left one
        glViewport (place.x, bounds.size.height - (place.y + place.height), place.width, place.height);

        @synchronized(self) {
            // This may be cleared before -drawRect is being called,
            // in this case we'll skip the rendering.
            // This will save us for rendering two frames (or more) for nothing
            // (one by the vout, one (or more) by drawRect)
            _hasPendingReshape = YES;
        }

        [self unlockgl];

        [super reshape];
    }
}

/**
 * Method called by Cocoa when the view is resized or the location has changed.
 * We just need to make sure we are locking here.
 */
- (void)update
{
    VLCAssertMainThread();
    BOOL success = [self lockgl];
    if (!success)
        return;

    [super update];

    [self unlockgl];
}

/**
 * Method called by Cocoa to force redraw.
 */
- (void)drawRect:(NSRect) rect
{
    VLCAssertMainThread();

    if ([self canSkipRendering])
        return;

    BOOL success = [self lockgl];
    if (!success)
        return;

    [self render];

    [self unlockgl];
}

- (void)renewGState
{
    // Comment take from Apple GLEssentials sample code:
    // https://developer.apple.com/library/content/samplecode/GLEssentials
    //
    // OpenGL rendering is not synchronous with other rendering on the OSX.
    // Therefore, call disableScreenUpdatesUntilFlush so the window server
    // doesn't render non-OpenGL content in the window asynchronously from
    // OpenGL content, which could cause flickering.  (non-OpenGL content
    // includes the title bar and drawing done by the app with other APIs)

    // In macOS 10.13 and later, window updates are automatically batched
    // together and this no longer needs to be called (effectively a no-op)
    /* -disableScreenUpdatesUntilFlush is 10.4; without it the window
     * server may show a resized window before it is redrawn, which costs a
     * flicker and nothing else. */
    if ([[self window] respondsToSelector:
            @selector(disableScreenUpdatesUntilFlush)])
        [[self window] disableScreenUpdatesUntilFlush];

    [super renewGState];
}

- (BOOL)isOpaque
{
    return YES;
}

#pragma mark -
#pragma mark Mouse handling

- (void)mouseDown:(NSEvent *)o_event
{
    /* A stationary click (notably the click that gives VLC focus again) is
     * invisible to the legacy cursor poller, which normally detects only a
     * coordinate change.  Publish the real event so it can restart its idle
     * timer before deciding to hide the hardware cursor.  The notification
     * is harmless when another macOS interface is active. */
    [[NSNotificationCenter defaultCenter]
        postNotificationName:@"VLCLegacyVideoMouseActivity" object:self];

    @synchronized (self) {
        if (vd) {
            if ([o_event type] == NSLeftMouseDown && !([o_event modifierFlags] &  NSControlKeyMask)) {
                if ([o_event clickCount] <= 1)
                    vout_display_SendEventMousePressed (vd, MOUSE_BUTTON_LEFT);
            }
        }
    }

    [super mouseDown:o_event];
}

- (void)rightMouseDown:(NSEvent *)o_event
{
    /* Forward to the hosting interface view so it can pop its contextual
     * menu: on Mac OS X 10.6 AppKit does not bubble right-clicks up the
     * responder chain by itself. */
    if ([self superview])
        [[self superview] rightMouseDown:o_event];
    else
        [super rightMouseDown:o_event];
}

- (void)otherMouseDown:(NSEvent *)o_event
{
    @synchronized (self) {
        if (vd)
            vout_display_SendEventMousePressed (vd, MOUSE_BUTTON_CENTER);
    }

    [super otherMouseDown: o_event];
}

- (void)mouseUp:(NSEvent *)o_event
{
    @synchronized (self) {
        if (vd) {
            if ([o_event type] == NSLeftMouseUp)
                vout_display_SendEventMouseReleased (vd, MOUSE_BUTTON_LEFT);
        }
    }

    [super mouseUp: o_event];
}

- (void)otherMouseUp:(NSEvent *)o_event
{
    @synchronized (self) {
        if (vd)
            vout_display_SendEventMouseReleased (vd, MOUSE_BUTTON_CENTER);
    }

    [super otherMouseUp: o_event];
}

- (void)mouseMoved:(NSEvent *)o_event
{
    /* on HiDPI displays, the point bounds don't equal the actual pixel based bounds */
    NSPoint ml = [self convertPoint: [o_event locationInWindow] fromView: nil];
    NSRect videoRect = [self bounds];
    BOOL b_inside = [self mouse: ml inRect: videoRect];

    ml = vlcConvertPointToBacking(self, ml);
    videoRect = vlcConvertRectToBacking(self, videoRect);

    if (b_inside) {
        @synchronized (self) {
            if (vd) {
                int mouseY = videoRect.size.height - (int)ml.y;
                /* The active HDMI 3D session exposes the complete packed
                 * scanout to AppKit. Map either physical eye back onto the
                 * single 1920x1080 Blu-ray interaction plane. */
                if (vd->sys->stereo_mode_ready &&
                    vd->sys->stereo_eye_width > 0 &&
                    vd->sys->stereo_eye_height > 0)
                {
                    const unsigned source_eye_height =
                        vd->source.multiview_mode ==
                            MULTIVIEW_STEREO_FRAMEPACKED ||
                        vd->source.multiview_mode ==
                            MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE
                        ? vd->source.i_visible_height / 2
                        : vd->source.i_visible_height;
                    const int packed_y = mouseY;
                    const int blanking = (int)videoRect.size.height -
                        2 * (int)vd->sys->stereo_eye_height;
                    int eye_y = packed_y;
                    if (packed_y >= (int)vd->sys->stereo_eye_height +
                                      blanking)
                        eye_y -= (int)vd->sys->stereo_eye_height + blanking;

                    if (ml.x >= 0 &&
                        ml.x < (float)vd->sys->stereo_eye_width &&
                        eye_y >= 0 &&
                        eye_y < (int)vd->sys->stereo_eye_height)
                    {
                        int x = (int)(vd->source.i_x_offset +
                            (int64_t)ml.x *
                            vd->source.i_visible_width /
                            vd->sys->stereo_eye_width);
                        int y = (int)(vd->source.i_y_offset / 2 +
                            (int64_t)eye_y * source_eye_height /
                            vd->sys->stereo_eye_height);
                        vout_display_SendEventMouseMoved(vd, x, y);
                    }
                }
                /* The windowed MVC preview draws only the first eye over the
                 * complete viewport.  The generic mapper still sees the
                 * internal two-eye (1920x2160) source and would therefore
                 * double Y, making BD-J buttons react in the wrong place.
                 * Map directly into the one-eye canvas in preview mode.  A
                 * real HDMI frame-packed scanout was handled above. */
                else if (!vd->sys->stereo_mode_ready &&
                    (vd->source.multiview_mode ==
                         MULTIVIEW_STEREO_FRAMEPACKED ||
                     vd->source.multiview_mode ==
                         MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE) &&
                    vd->sys->place.width > 0 && vd->sys->place.height > 0)
                {
                    int x = (int)(vd->source.i_x_offset +
                        (int64_t)((int)ml.x - vd->sys->place.x) *
                        vd->source.i_visible_width / vd->sys->place.width);
                    int y = (int)(vd->source.i_y_offset / 2 +
                        (int64_t)(mouseY - vd->sys->place.y) *
                        (vd->source.i_visible_height / 2) /
                        vd->sys->place.height);
                    vout_display_SendEventMouseMoved(vd, x, y);
                }
                else
                    vout_display_SendMouseMovedDisplayCoordinates(
                        vd, ORIENT_NORMAL, (int)ml.x, mouseY,
                        &vd->sys->place);
            }
        }
    }

    [super mouseMoved: o_event];
}

- (void)mouseDragged:(NSEvent *)o_event
{
    [self mouseMoved: o_event];
    [super mouseDragged: o_event];
}

- (void)otherMouseDragged:(NSEvent *)o_event
{
    [self mouseMoved: o_event];
    [super otherMouseDragged: o_event];
}

- (void)rightMouseDragged:(NSEvent *)o_event
{
    [self mouseMoved: o_event];
    [super rightMouseDragged: o_event];
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

/* AppKit routes mouse-moved events to the first responder, not to the view
 * under the cursor: claim it whenever we enter a window, otherwise DVD/BD
 * menu highlighting never sees the pointer. Same contract as the other two
 * Mac outputs (macosx_gl1.m, macosx_qt.m). Key presses are unaffected: we
 * implement no key handling, so they keep climbing the responder chain to
 * the hosting interface. */
- (void)viewDidMoveToWindow
{
    if ([self window])
    {
        [[self window] makeFirstResponder:self];
        /* The newly-created fullscreen window may still carry the source
         * screen's backing scale at this instant. The delayed pass observes
         * its final HDMI screen and corrects the viewport accordingly. */
        [self performSelector:@selector(updateForChangedDisplay)
                   withObject:nil afterDelay:0.1];
        [self performSelector:@selector(updateForChangedDisplay)
                   withObject:nil afterDelay:0.6];
    }
    [super viewDidMoveToWindow];
}

- (BOOL)mouseDownCanMoveWindow
{
    return YES;
}

@end
