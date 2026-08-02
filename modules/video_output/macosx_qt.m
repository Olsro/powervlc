/*****************************************************************************
 * macosx_qt.m: QuickTime/QuickDraw video output for Mac OS X PowerPC
 *****************************************************************************
 * Copyright (C) 2001-2026 VLC authors and VideoLAN
 *
 * Authors: derived from the VLC 0.8 voutqt.m and from macosx_gl1.m.
 *
 * The Image Compression Manager takes raw planar I420 frames and hands
 * them to the QuickDraw pipeline, which on PowerPC-era hardware uses the
 * GPU blitter for colorspace conversion AND scaling (this is how DVD
 * Player and QuickTime Player achieved smooth playback on G3s). No CPU
 * chroma conversion, no texture upload: the biggest CPU consumers of the
 * GL output simply disappear.
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

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import <Cocoa/Cocoa.h>
#import <QuickTime/QuickTime.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>
#include <vlc_picture_pool.h>

static int  Open   (vlc_object_t *);
static void Close  (vlc_object_t *);

static picture_pool_t *Pool (vout_display_t *vd, unsigned requested_count);
static void PictureRender (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture);
static void PictureDisplay (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture);
static int Control (vout_display_t *vd, int query, va_list ap);

/**
 * Module declaration
 */
vlc_module_begin ()
    set_shortname ("Mac OS X QuickTime")
    set_description (N_("Mac OS X QuickDraw/QuickTime video output"))
    set_category (CAT_VIDEO)
    set_subcategory (SUBCAT_VIDEO_VOUT)
    /* Experimental, opt-in only (--vout macosx_qt), BELOW the GL1 output
     * (60). The Image Compression Manager was DVD Player's path, but here
     * it is not worth defaulting to: QuickTime re-converts YUV->2vuy in
     * software inside the decompressor (~30% of a G3 core) regardless of
     * the destination, so it matches the GL output's CPU with added
     * tearing when compositing into a Cocoa window. True zero-copy needs
     * an exclusive fullscreen CGDisplayCapture (implemented below, but
     * unreachable through the reparenting fullscreen of the legacy UI). */
    set_capability ("vout display", 50)
    set_callbacks (Open, Close)
    add_shortcut ("macosx_qt", "quicktime")
vlc_module_end ()

#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED < 1050
# include <pthread.h>
# define VLCAssertMainThread() assert(pthread_main_np() != 0)
#else
# define VLCAssertMainThread() assert([[NSThread currentThread] isMainThread])
#endif

@protocol VLCOpenGLVideoViewEmbedding <NSObject>
- (void)addVoutSubview:(NSView *)view;
- (void)removeVoutSubview:(NSView *)view;
@end

@interface VLCQTVideoView : NSQuickDrawView
{
    vout_display_t *vd;
}
- (void)setVoutDisplay:(vout_display_t *)vd;
@end

/* Per-picture payload: packed 2vuy frames are handed to the ICM as a raw
 * contiguous buffer (rowBytes must equal width * 2, so the pictures are
 * allocated without row padding). '2vuy' is the native format of the
 * QuickDraw video blitter: QuickTime's own I420 codec was profiled
 * converting to 2vuy in software first (YUV420To2VUY_W1x), work our
 * dcbz-optimized converter does for less than half the cost. */
struct qt_pic_sys
{
    PlanarPixmapInfoYUV420 header; /* ICM planar descriptor (offsets are deltas) */
    void *base;    /* backing allocation for the three planes */
    size_t size;   /* header + planes size passed to the ICM */
};

struct vout_display_sys_t
{
    VLCQTVideoView *qtView;
    id<VLCOpenGLVideoViewEmbedding> container;

    vout_window_t *embed;

    picture_pool_t *pool;

    ImageDescriptionHandle img_descr;
    ImageSequence seq;
    MatrixRecord matrix;
    CGrafPtr seq_port;    /* port the sequence was created against */
    bool seq_started;
    bool matrix_dirty;

    unsigned src_width;   /* visible source dimensions */
    unsigned src_height;

    /* The QuickDraw port covers the whole window: the blit must be offset
     * by the view's position (QD coordinates: origin top-left, y down)
     * and clipped to the view's rectangle. Maintained by the view. */
    int qd_off_x, qd_off_y;
    Rect qd_clip;

    /* Fullscreen hardware overlay: when the view fills a whole screen
     * borderlessly, we capture the display and blit into its own port.
     * With exclusive display ownership the ICM can use the GPU's YUV
     * overlay/scaler (zero desktop compositing) - the DVD Player path.
     * want_capture is set by the view (main thread); the capture itself
     * happens on the vout thread, where QuickTime is confined. */
    bool want_capture;              /* view: should we be captured? */
    CGDirectDisplayID want_display; /* which display to capture */
    bool captured;                  /* vout: currently captured? */
    CGrafPtr capture_port;

    vout_display_place_t place;
    vlc_mutex_t place_lock;
};

/*****************************************************************************
 * Geometry: map the source rectangle onto the current placement
 *****************************************************************************/
static void UpdateMatrixLocked (vout_display_sys_t *sys)
{
    SetIdentityMatrix (&sys->matrix);
    if (sys->place.width > 0 && sys->place.height > 0)
    {
        ScaleMatrix (&sys->matrix,
                     FixDiv (Long2Fix (sys->place.width),
                             Long2Fix (sys->src_width)),
                     FixDiv (Long2Fix (sys->place.height),
                             Long2Fix (sys->src_height)),
                     0, 0);
        TranslateMatrix (&sys->matrix,
                         Long2Fix (sys->qd_off_x + sys->place.x),
                         Long2Fix (sys->qd_off_y + sys->place.y));
    }
}

/* Capture / release the display for the hardware overlay path. Vout thread
 * only (QuickTime and CGDisplayCapture kept on one thread). */
static void UpdateCaptureLocked (vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    if (sys->want_capture && !sys->captured)
    {
        if (CGDisplayCapture (sys->want_display) == kCGErrorSuccess)
        {
            sys->capture_port = CreateNewPortForCGDisplayID (
                                    (UInt32) sys->want_display);
            if (sys->capture_port != NULL)
            {
                sys->captured = true;
                msg_Dbg (vd, "display captured for hardware overlay");
            }
            else
                CGDisplayRelease (sys->want_display);
        }
        else
            msg_Warn (vd, "CGDisplayCapture failed, staying windowed");
    }
    else if (!sys->want_capture && sys->captured)
    {
        if (sys->capture_port != NULL)
        {
            DisposePort (sys->capture_port);
            sys->capture_port = NULL;
        }
        CGDisplayRelease (sys->want_display);
        sys->captured = false;
        msg_Dbg (vd, "display released");
    }
}

/* Called on the vout thread only. Returns false while the view has not
 * reached a window yet (the attachment is asynchronous). */
static bool EnsureSequence (vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    vlc_mutex_lock (&sys->place_lock);
    UpdateCaptureLocked (vd);
    bool captured = sys->captured;
    vlc_mutex_unlock (&sys->place_lock);

    CGrafPtr port = captured ? sys->capture_port
                             : (CGrafPtr) [sys->qtView qdPort];
    if (port == NULL)
        return false;

    /* The view can move to another window (fullscreen): the sequence is
     * bound to a port and must follow. */
    if (sys->seq_started && port != sys->seq_port)
    {
        CDSequenceEnd (sys->seq);
        sys->seq_started = false;
    }
    if (sys->seq_started)
        return true;

    ImageDescriptionPtr descr;
    HLock ((Handle) sys->img_descr);
    descr = *sys->img_descr;

    descr->idSize = sizeof (ImageDescription);
    descr->cType = kYUV420CodecType; /* planar YUV, GPU-converted */
    descr->version = 2;
    descr->revisionLevel = 0;
    descr->vendor = 'mpla';
    descr->width = sys->src_width;
    descr->height = sys->src_height;
    descr->hRes = Long2Fix (72);
    descr->vRes = Long2Fix (72);
    descr->spatialQuality = codecLosslessQuality;
    descr->frameCount = 1;
    descr->clutID = -1;
    descr->dataSize = 0;
    descr->depth = 24;

    HUnlock ((Handle) sys->img_descr);

    vlc_mutex_lock (&sys->place_lock);
    UpdateMatrixLocked (sys);
    sys->matrix_dirty = false;
    vlc_mutex_unlock (&sys->place_lock);

    SetPort (port);
    OSErr err = DecompressSequenceBeginS (&sys->seq, sys->img_descr, NULL,
                                          (sys->src_width * sys->src_height * 16) / 8,
                                          port, NULL, NULL, &sys->matrix,
                                          srcCopy, NULL,
                                          codecFlagUseImageBuffer,
                                          codecLosslessQuality,
                                          bestSpeedCodec);
    if (err != noErr)
    {
        msg_Err (vd, "DecompressSequenceBeginS failed: %d", (int) err);
        return false;
    }

    msg_Dbg (vd, "QuickDraw sequence started (%ux%u planar YUV)",
             sys->src_width, sys->src_height);
    sys->seq_port = port;
    sys->seq_started = true;
    return true;
}

/*****************************************************************************
 * Vout display module
 *****************************************************************************/

static int Open (vlc_object_t *this)
{
    vout_display_t *vd = (vout_display_t *) this;
    vout_display_sys_t *sys = calloc (1, sizeof(*sys));

    if (!sys)
        return VLC_ENOMEM;

    /* explicit pool: @autoreleasepool is clang-only, this file is MRC */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    {
        vd->sys = sys;
        vlc_mutex_init (&sys->place_lock);

        /* The ICM packed-YUV path must exist (it does on any QuickTime 6+) */
        CodecComponent codec = 0;
        if (FindCodec (kYUV420CodecType, bestSpeedCodec, nil, &codec) != noErr
         || codec == 0)
        {
            msg_Warn (vd, "no QuickTime planar YUV codec here");
            goto error;
        }

        if (EnterMovies () != noErr)
        {
            msg_Err (vd, "EnterMovies failed");
            goto error;
        }

        sys->img_descr = (ImageDescriptionHandle)
            NewHandleClear (sizeof (ImageDescription));
        if (sys->img_descr == NULL)
            goto error;

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

        [VLCQTVideoView performSelectorOnMainThread:@selector(getNewView:)
                                         withObject:[NSValue valueWithPointer:&sys->qtView]
                                      waitUntilDone:YES];
        if (!sys->qtView) {
            msg_Err(vd, "Initialization of QuickDraw view failed");
            goto error;
        }

        [sys->qtView setVoutDisplay:vd];

        if ([(id)container respondsToSelector:@selector(addVoutSubview:)])
            [(id)container performSelectorOnMainThread:@selector(addVoutSubview:)
                                            withObject:sys->qtView
                                         waitUntilDone:NO];
        else if ([container isKindOfClass:[NSView class]]) {
            NSView *parentView = container;
            [parentView performSelectorOnMainThread:@selector(addSubview:)
                                         withObject:sys->qtView
                                      waitUntilDone:NO];
            [sys->qtView performSelectorOnMainThread:@selector(setFrameToBoundsOfView:)
                                          withObject:[NSValue valueWithPointer:parentView]
                                       waitUntilDone:NO];
        } else {
            msg_Err(vd, "Invalid drawable-nsobject object. drawable-nsobject must either be an NSView or comply to the @protocol VLCOpenGLVideoViewEmbedding.");
            goto error;
        }

        /* Planar 4:2:0 straight from the decoder; QuickDraw does the
         * YUV->RGB conversion and scaling (on the GPU when the display is
         * captured). */
        video_format_t fmt = vd->fmt;
        fmt.i_chroma = VLC_CODEC_I420;
        fmt.i_rmask = fmt.i_gmask = fmt.i_bmask = 0;

        sys->src_width  = fmt.i_width;
        sys->src_height = fmt.i_height;

        /* Initial placement (refined by Control/reshape) */
        vout_display_PlacePicture (&sys->place, &vd->source, vd->cfg, false);
        sys->matrix_dirty = true;

        msg_Dbg (vd, "QuickDraw output: %ux%u planar YUV, ICM blit",
                 sys->src_width, sys->src_height);

        vout_display_info_t info = vd->info;
        info.has_pictures_invalid = false;
        info.subpicture_chromas = NULL; /* OSD/SPU blended by the core */

        vd->fmt = fmt;
        vd->info = info;

        vd->pool = Pool;
        vd->prepare = PictureRender;
        vd->display = PictureDisplay;
        vd->control = Control;

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
        if (sys->seq_started)
            CDSequenceEnd (sys->seq);

        /* release the display capture before tearing anything down */
        if (sys->captured)
        {
            if (sys->capture_port != NULL)
                DisposePort (sys->capture_port);
            CGDisplayRelease (sys->want_display);
            sys->captured = false;
        }

        [sys->qtView setVoutDisplay:nil];

        var_Destroy (vd, "drawable-nsobject");
        if ([(id)sys->container respondsToSelector:@selector(removeVoutSubview:)])
            [(id)sys->container performSelectorOnMainThread:@selector(removeVoutSubview:)
                                                 withObject:sys->qtView
                                              waitUntilDone:NO];

        [(id)sys->container performSelectorOnMainThread:@selector(release)
                                             withObject:nil
                                          waitUntilDone:NO];
        [sys->qtView performSelectorOnMainThread:@selector(removeFromSuperview)
                                      withObject:nil
                                   waitUntilDone:NO];

        if (sys->pool)
            picture_pool_Release (sys->pool);

        if (sys->img_descr)
            DisposeHandle ((Handle) sys->img_descr);

        [sys->qtView release];

        if (sys->embed)
            vout_display_DeleteWindow (vd, sys->embed);
        vlc_mutex_destroy (&sys->place_lock);
        free (sys);
    }
    [pool release];
}

/*****************************************************************************
 * Picture pool: contiguous planar buffers with the ICM header attached
 *****************************************************************************/

static void QtPicDestroy (picture_t *pic)
{
    struct qt_pic_sys *ps = (struct qt_pic_sys *) pic->p_sys;
    free (ps->base);
    free (ps);
    free (pic);
}

static picture_t *QtPicNew (const video_format_t *fmt)
{
    struct qt_pic_sys *ps = calloc (1, sizeof (*ps));
    if (ps == NULL)
        return NULL;

    unsigned width  = fmt->i_width;
    unsigned height = fmt->i_height;
    unsigned pitch_y = (width + 15) & ~15u;
    unsigned pitch_c = ((width / 2) + 15) & ~15u;
    size_t size_y = (size_t) pitch_y * height;
    size_t size_c = (size_t) pitch_c * (height / 2);

    ps->base = malloc (size_y + 2 * size_c + 15);
    if (ps->base == NULL)
    {
        free (ps);
        return NULL;
    }

    uint8_t *y = (uint8_t *)(((uintptr_t) ps->base + 15) & ~(uintptr_t)15);
    uint8_t *u = y + size_y;
    uint8_t *v = u + size_c;

    /* the ICM planar codec reads the frame through this header; offsets
     * are deltas from the header itself, so the planes can be elsewhere */
    ps->header.componentInfoY.offset  = (long)(y - (uint8_t *) &ps->header);
    ps->header.componentInfoCb.offset = (long)(u - (uint8_t *) &ps->header);
    ps->header.componentInfoCr.offset = (long)(v - (uint8_t *) &ps->header);
    ps->header.componentInfoY.rowBytes  = pitch_y;
    ps->header.componentInfoCb.rowBytes = pitch_c;
    ps->header.componentInfoCr.rowBytes = pitch_c;
    ps->size = sizeof (ps->header);

    picture_resource_t rsc = {
        .p_sys = (picture_sys_t *) ps,
        .pf_destroy = QtPicDestroy,
        .p = {
            [0] = { .p_pixels = y, .i_lines = height,     .i_pitch = pitch_y },
            [1] = { .p_pixels = u, .i_lines = height / 2, .i_pitch = pitch_c },
            [2] = { .p_pixels = v, .i_lines = height / 2, .i_pitch = pitch_c },
        },
    };
    picture_t *pic = picture_NewFromResource (fmt, &rsc);
    if (pic == NULL)
    {
        free (ps->base);
        free (ps);
    }
    return pic;
}

static picture_pool_t *Pool (vout_display_t *vd, unsigned requested_count)
{
    vout_display_sys_t *sys = vd->sys;

    if (sys->pool)
        return sys->pool;

    picture_t *pics[requested_count];
    unsigned i;
    for (i = 0; i < requested_count; i++)
    {
        pics[i] = QtPicNew (&vd->fmt);
        if (pics[i] == NULL)
            break;
    }
    if (i >= 3)
        sys->pool = picture_pool_New (i, pics);
    if (!sys->pool)
        while (i > 0)
            picture_Release (pics[--i]);
    return sys->pool;
}

/*****************************************************************************
 * display callbacks (vout thread; QuickTime is used from this thread only,
 * like the historical 0.8 output did)
 *****************************************************************************/

static void PictureRender (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture)
{
    VLC_UNUSED(vd); VLC_UNUSED(pic); VLC_UNUSED(subpicture);
    /* nothing: the ICM reads straight from the picture planes */
}

static void PictureDisplay (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;
    VLC_UNUSED(subpicture);

    if (EnsureSequence (vd))
    {
        vlc_mutex_lock (&sys->place_lock);
        if (sys->matrix_dirty)
        {
            UpdateMatrixLocked (sys);
            sys->matrix_dirty = false;
            SetDSequenceMatrix (sys->seq, &sys->matrix);
        }
        vlc_mutex_unlock (&sys->place_lock);

        vlc_mutex_lock (&sys->place_lock);
        bool captured = sys->captured;
        Rect clip = sys->qd_clip;
        vlc_mutex_unlock (&sys->place_lock);

        CGrafPtr port = captured ? sys->capture_port
                                 : (CGrafPtr) [sys->qtView qdPort];
        if (port != NULL)
        {
            CodecFlags flags;
            SetPort (port);
            ClipRect (&clip);
            struct qt_pic_sys *ps = (struct qt_pic_sys *) pic->p_sys;
            OSErr err = DecompressSequenceFrameWhen (sys->seq,
                                                     (void *) &ps->header,
                                                     ps->size,
                                                     codecFlagUseImageBuffer,
                                                     &flags, NULL, NULL);
            if (err != noErr)
                msg_Warn (vd, "DecompressSequenceFrameWhen failed: %d", (int) err);
            else if (!captured)
                /* captured display scans out directly, no backing store */
                QDFlushPortBuffer (port, nil);
        }
    }

    picture_Release (pic);
}

static int Control (vout_display_t *vd, int query, va_list ap)
{
    vout_display_sys_t *sys = vd->sys;

    if (!sys)
        return VLC_EGENERIC;

    switch (query)
    {
        case VOUT_DISPLAY_CHANGE_DISPLAY_FILLED:
        case VOUT_DISPLAY_CHANGE_ZOOM:
        case VOUT_DISPLAY_CHANGE_SOURCE_ASPECT:
        case VOUT_DISPLAY_CHANGE_SOURCE_CROP:
        case VOUT_DISPLAY_CHANGE_DISPLAY_SIZE:
        {
            const vout_display_cfg_t *cfg;

            if (query == VOUT_DISPLAY_CHANGE_SOURCE_ASPECT
             || query == VOUT_DISPLAY_CHANGE_SOURCE_CROP) {
                cfg = vd->cfg;
            } else {
                cfg = (const vout_display_cfg_t*)va_arg (ap, const vout_display_cfg_t *);
            }

            vout_display_place_t place;
            vout_display_PlacePicture (&place, &vd->source, cfg, false);

            vlc_mutex_lock (&sys->place_lock);
            sys->place = place;
            sys->matrix_dirty = true;
            vlc_mutex_unlock (&sys->place_lock);

            return VLC_SUCCESS;
        }

        case VOUT_DISPLAY_RESET_PICTURES:
            vlc_assert_unreachable ();
        default:
            msg_Err (vd, "Unknown request in Mac OS X QT vout display");
            return VLC_EGENERIC;
    }
}

/*****************************************************************************
 * Our NSView object
 *****************************************************************************/
@implementation VLCQTVideoView

+ (void)getNewView:(NSValue *)value
{
    id *ret = [value pointerValue];
    *ret = [[self alloc] init];
}

- (id)init
{
    VLCAssertMainThread();
    self = [super initWithFrame:NSMakeRect(0, 0, 10, 10)];
    if (!self)
        return nil;
    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    return self;
}

- (void)setFrameToBoundsOfView:(NSValue *)value
{
    NSView *parentView = [value pointerValue];
    [self setFrame:[parentView bounds]];
}

- (void)setVoutDisplay:(vout_display_t *)aVd
{
    @synchronized(self) {
        vd = aVd;
    }
}

- (void)drawRect:(NSRect)rect
{
    /* Areas the video does not cover (letterbox bars) stay black; the
     * frames themselves are blitted by the ICM outside of AppKit. */
    [[NSColor blackColor] set];
    NSRectFill (rect);
}

/* Recompute the placement, the QuickDraw offset of the view inside its
 * window's port (origin top-left, y down) and the clipping rectangle. */
- (void)updateGeometry
{
    NSRect bounds = [self bounds];

    @synchronized(self) {
        if (!vd)
            return;
        vout_display_sys_t *sys = vd->sys;

        int off_x = 0, off_y = 0;
        NSWindow *win = [self window];

        /* Hardware overlay: the view fills a whole screen inside a
         * borderless window (our legacy fullscreen). Capture that display
         * and blit into it directly; otherwise blit into the window port. */
        bool want_capture = false;
        CGDirectDisplayID display = kCGDirectMainDisplay;
        if (win) {
            NSRect inWin = [self convertRect:bounds toView:nil];
            /* -contentRectForFrameRect: is 10.3; the class method that takes
             * the style mask is not, and answers the same for this window */
            NSRect content =
                [win respondsToSelector:@selector(contentRectForFrameRect:)]
                ? [win contentRectForFrameRect:[win frame]]
                : [NSWindow contentRectForFrameRect:[win frame]
                                          styleMask:[win styleMask]];
            off_x = inWin.origin.x;
            off_y = content.size.height
                  - (inWin.origin.y + inWin.size.height);

            NSScreen *screen = [win screen];
            if (screen && ([win styleMask] & NSBorderlessWindowMask)
             && NSEqualRects ([win frame], [screen frame])
             && NSEqualSizes (bounds.size, [screen frame].size)) {
                want_capture = true;
                display = (CGDirectDisplayID)[[[screen deviceDescription]
                    objectForKey:@"NSScreenNumber"] unsignedIntValue];
            }
        }

        vout_display_cfg_t cfg_tmp = *(vd->cfg);
        cfg_tmp.display.width  = bounds.size.width;
        cfg_tmp.display.height = bounds.size.height;

        vout_display_place_t place;
        vout_display_PlacePicture (&place, &vd->source, &cfg_tmp, false);

        vlc_mutex_lock (&sys->place_lock);
        sys->place = place;
        sys->want_capture = want_capture;
        sys->want_display = display;
        if (want_capture) {
            /* captured port covers the whole display at origin (0,0) */
            sys->qd_off_x = 0;
            sys->qd_off_y = 0;
            sys->qd_clip.left = 0;
            sys->qd_clip.top = 0;
            sys->qd_clip.right = bounds.size.width;
            sys->qd_clip.bottom = bounds.size.height;
        } else {
            sys->qd_off_x = off_x;
            sys->qd_off_y = off_y;
            sys->qd_clip.left = off_x;
            sys->qd_clip.top = off_y;
            sys->qd_clip.right = off_x + bounds.size.width;
            sys->qd_clip.bottom = off_y + bounds.size.height;
        }
        sys->matrix_dirty = true;
        vlc_mutex_unlock (&sys->place_lock);

        vout_display_SendEventDisplaySize (vd, bounds.size.width, bounds.size.height);
    }
}

/* Keep the placement in sync when the view is resized */
- (void)resizeWithOldSuperviewSize:(NSSize)oldBoundsSize
{
    [super resizeWithOldSuperviewSize:oldBoundsSize];
    [self updateGeometry];
}

- (void)setFrame:(NSRect)frame
{
    [super setFrame:frame];
    [self updateGeometry];
}

- (BOOL)isOpaque
{
    return YES;
}

- (BOOL)acceptsFirstResponder
{
    return YES;
}

/* Mouse-moved events go to the first responder (DVD menu highlighting);
 * a window change also invalidates the QuickDraw geometry. */
- (void)viewDidMoveToWindow
{
    if ([self window])
        [[self window] makeFirstResponder:self];
    [self updateGeometry];
    [super viewDidMoveToWindow];
}

- (BOOL)mouseDownCanMoveWindow
{
    return YES;
}

#pragma mark Mouse handling (same contract as the GL outputs)

- (void)mouseDown:(NSEvent *)o_event
{
    @synchronized (self) {
        if (vd && [o_event type] == NSLeftMouseDown
         && !([o_event modifierFlags] & NSControlKeyMask)
         && [o_event clickCount] <= 1)
            vout_display_SendEventMousePressed (vd, MOUSE_BUTTON_LEFT);
    }
    [super mouseDown:o_event];
}

- (void)rightMouseDown:(NSEvent *)o_event
{
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
        if (vd && [o_event type] == NSLeftMouseUp)
            vout_display_SendEventMouseReleased (vd, MOUSE_BUTTON_LEFT);
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
    NSPoint ml = [self convertPoint:[o_event locationInWindow] fromView:nil];
    NSRect videoRect = [self bounds];

    if ([self mouse:ml inRect:videoRect]) {
        @synchronized (self) {
            if (vd) {
                vout_display_sys_t *sys = vd->sys;
                vlc_mutex_lock (&sys->place_lock);
                vout_display_place_t place = sys->place;
                vlc_mutex_unlock (&sys->place_lock);
                vout_display_SendMouseMovedDisplayCoordinates(vd, ORIENT_NORMAL,
                    (int)ml.x, videoRect.size.height - (int)ml.y, &place);
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

@end
