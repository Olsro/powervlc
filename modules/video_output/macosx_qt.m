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

#include <unistd.h>            /* access() — interrupteur /tmp/qt_capture */
#include <fcntl.h>             /* open() — témoin de bascule synchrone */
#include <stdlib.h>            /* getenv() */
#include <stdio.h>             /* snprintf() */


#import <Cocoa/Cocoa.h>
#import <QuickTime/QuickTime.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>
#include <vlc_picture_pool.h>

#include <math.h>                            /* lround */
#include "../codec/dvddriver_piccontext.h"   /* present matériel piloté par le vout */

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
    /* ★★★ VERROU DE DESSIN (2026-08-05) — sépare le dessin QuickTime du
     * DÉMÉNAGEMENT DE LA VUE d'une fenêtre à l'autre.
     *
     * En plein écran, l'interface legacy retire la vue vidéo de sa fenêtre et
     * l'insère dans une fenêtre sans bordure (chemin obligatoire sous 10.4,
     * cf. `openVideoHostWindow`). La vue étant une `NSQuickDrawView`, AppKit
     * DÉTRUIT et recrée son port QuickDraw au passage — pendant que le fil du
     * vout peut être en train d'y dessiner via `DecompressSequenceFrameWhen`.
     * Résultat mesuré au témoin synchrone : le gel se produit exactement dans
     * `addSubview:`, et il emporte la MACHINE ENTIÈRE (SSH compris).
     * Ce verrou est pris autour de tout le dessin ; `viewWillMoveToWindow:`
     * le prend aussi, ce qui garantit qu'aucun dessin n'est en cours au moment
     * du déménagement, et en profite pour clore la séquence sur l'ancien port
     * AVANT que celui-ci disparaisse. */
    vlc_mutex_t draw_lock;
    bool        suspended;          /* vue en cours de déménagement */

    vlc_mutex_t place_lock;

    /* ==== Décodage DVD accéléré ATI (U1/U4) ==============================
     * Ce vout est celui que retiennent les cartes sans textures RECTANGLE —
     * la Rage Mobility M3 de l'iBook G3, où macosx_gl1 décline (« OpenGL 1.1
     * YCbCr texturing not supported here »). Sans le protocole ci-dessous le
     * décodeur matériel tourne mais AUCUNE image n'est présentée : le present
     * est piloté par le vout, et lui seul connaît le pacing PTS.
     * Rectangle vidéo en coordonnées FENÊTRE-locales (ce qu'attend
     * CGSSetSurfaceBounds), publié par updateGeometry sur le thread principal
     * et lu au display sous place_lock. */
    int  hw_x, hw_y, hw_w, hw_h;
    int  hw_wid;              /* numéro CGS de la fenêtre hôte, 0 = aucune */
    bool hw_place_valid;
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
        vlc_mutex_init (&sys->draw_lock);
        sys->suspended = false;

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

        /* ⚠ Les dimensions VISIBLES, jamais celles du tampon : `i_width` et
         * `i_height` portent l'alignement que réclame le décodeur, et les
         * lignes de remplissage ne sont JAMAIS écrites. Décrire l'image à la
         * taille du tampon les donne à blitter à l'ICM, qui les étire dans le
         * rectangle calculé pour l'image visible : image tassée à la verticale
         * et BANDE VERTE en bas (du YUV à zéro), largeur pleine. Mesuré sur
         * une vidéo Invidious 640x360 en H.264 — avcodec_align_dimensions2()
         * arrondit la hauteur à 32 et ajoute 2 lignes pour la sur-lecture de
         * la MC chroma, soit un tampon de 640x386 dont le décodeur ne remplit
         * que 368 lignes : 18 lignes vertes. Invisible sur DVD, où MPEG-2 ne
         * réclame ni l'arrondi à 32 ni les 2 lignes en trop. */
        sys->src_width  = fmt.i_visible_width;
        sys->src_height = fmt.i_visible_height;

        /* Initial placement (refined by Control/reshape) */
        vout_display_PlacePicture (&sys->place, &vd->source, vd->cfg, false);
        sys->matrix_dirty = true;

        /* U1 — géométrie publiée sur le bus libvlc à l'intention du décodeur
         * matériel ATI. wid=0 tant qu'updateGeometry n'a pas vu de fenêtre :
         * le décodeur ouvre alors sa propre fenêtre Carbon. */
        var_Create (vd->obj.libvlc, DVDDRIVER_VAR_WID,    VLC_VAR_INTEGER);
        var_Create (vd->obj.libvlc, DVDDRIVER_VAR_RECT_X, VLC_VAR_INTEGER);
        var_Create (vd->obj.libvlc, DVDDRIVER_VAR_RECT_Y, VLC_VAR_INTEGER);
        var_Create (vd->obj.libvlc, DVDDRIVER_VAR_RECT_W, VLC_VAR_INTEGER);
        var_Create (vd->obj.libvlc, DVDDRIVER_VAR_RECT_H, VLC_VAR_INTEGER);
        var_SetInteger (vd->obj.libvlc, DVDDRIVER_VAR_WID, 0);

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

        /* U1 — retirer la géométrie du bus : wid=0 d'abord, pour qu'un décodeur
         * encore vivant cesse de viser une fenêtre qui va disparaître. */
        var_SetInteger (vd->obj.libvlc, DVDDRIVER_VAR_WID, 0);
        var_Destroy (vd->obj.libvlc, DVDDRIVER_VAR_WID);
        var_Destroy (vd->obj.libvlc, DVDDRIVER_VAR_RECT_X);
        var_Destroy (vd->obj.libvlc, DVDDRIVER_VAR_RECT_Y);
        var_Destroy (vd->obj.libvlc, DVDDRIVER_VAR_RECT_W);
        var_Destroy (vd->obj.libvlc, DVDDRIVER_VAR_RECT_H);

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
        vlc_mutex_destroy (&sys->draw_lock);
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
    /* ⚠ Le pas de ligne CHROMA vaut exactement la MOITIÉ du pas luma en 4:2:0 —
     * il ne s'aligne PAS pour son propre compte. L'aligner séparément
     * (`((width/2)+15) & ~15`) donnait 368 au lieu de 360 pour une largeur de
     * 720 : le luma tombait juste (720 est déjà multiple de 16) tandis que la
     * chroma glissait de 8 octets par ligne, d'où une image lisible BARRÉE DE
     * BANDES DIAGONALES rouge/bleu et une ligne verte en bas. Visible sur tout
     * DVD PAL/NTSC (720 de large) — donc sur les menus, rendus en logiciel, et
     * sur toute lecture non accélérée. */
    unsigned pitch_c = pitch_y / 2;
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
     * are deltas from the header itself, so the planes can be elsewhere.
     * L'image décrite à l'ICM est la partie VISIBLE (voir Open) : les offsets
     * pointent donc son coin haut-gauche, pas l'origine du plan. */
    unsigned crop_x = fmt->i_x_offset & ~1u;   /* 4:2:0 : un pixel chroma
                                                * couvre 2x2 pixels luma */
    unsigned crop_y = fmt->i_y_offset & ~1u;
    const uint8_t *vy = y + (size_t) crop_y * pitch_y + crop_x;
    const uint8_t *vu = u + (size_t) (crop_y / 2) * pitch_c + crop_x / 2;
    const uint8_t *vv = v + (size_t) (crop_y / 2) * pitch_c + crop_x / 2;

    ps->header.componentInfoY.offset  = (long)(vy - (uint8_t *) &ps->header);
    ps->header.componentInfoCb.offset = (long)(vu - (uint8_t *) &ps->header);
    ps->header.componentInfoCr.offset = (long)(vv - (uint8_t *) &ps->header);
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

    /* ==== U4 — present matériel piloté par le vout =========================
     * Si la picture porte un contexte HW et que le décodeur a publié son device
     * et son callback, présenter la surface GPU et NE PAS blitter : en mode
     * remplacement les plans logiciels ne sont jamais reconstruits, les blitter
     * afficherait du vide. Le pacing PTS du vout s'applique donc au present
     * matériel, ce qui donne la synchro A/V.
     *
     * Les deux adresses sont relues à CHAQUE image, jamais mises en cache : le
     * décodeur peut fermer puis rouvrir son contexte en cours de flux (bascule
     * plein écran, changement de séquence). */
    dvddriver_ctx *hw = var_GetAddress (vd->obj.libvlc, DVDDRIVER_VAR_CTX);
    dvddriver_present_cb present =
        (dvddriver_present_cb) var_GetAddress (vd->obj.libvlc, DVDDRIVER_VAR_PRESENT);

    if (hw != NULL && present != NULL && pic->context != NULL)
    {
        int hx, hy, hw_, hh, hwid;
        bool ok;
        vlc_mutex_lock (&sys->place_lock);
        ok = sys->hw_place_valid;
        hx = sys->hw_x; hy = sys->hw_y; hw_ = sys->hw_w; hh = sys->hw_h;
        hwid = sys->hw_wid;
        if (!ok)
        {
            /* Pas encore de géométrie fenêtre-locale : le rectangle en coords
             * VUE est le meilleur repli, et le décodeur l'ignore de toute façon
             * quand il affiche dans sa propre fenêtre Carbon (wid=0). */
            hx = sys->place.x; hy = sys->place.y;
            hw_ = sys->place.width; hh = sys->place.height;
            hwid = 0;
        }
        vlc_mutex_unlock (&sys->place_lock);

        {
            static bool s_engaged = false;
            if (!s_engaged)
            {
                s_engaged = true;
                msg_Dbg (vd, "present matériel engagé (rect fenêtre-local "
                         "%d,%d %dx%d, wid=%d)", hx, hy, hw_, hh, hwid);
            }
        }

        if (present (hw, pic->context, hwid, hx, hy, hw_, hh))
        {
            picture_Release (pic);
            return;
        }
    }
    else if (hw != NULL && present != NULL)
    {
        /* ★★ IMAGE SANS CONTEXTE MATÉRIEL alors que le chemin HW est ACTIF —
         * ne PAS la blitter. En mode remplacement les plans logiciels ne sont
         * pas reconstruits (cf. le commentaire ci-dessus), et surtout ce blit
         * dessine dans la FENÊTRE, sous la surface CGS du décodeur : on fait
         * alors coexister deux contenus différents au même endroit, que le
         * WindowServer peut composer l'un puis l'autre — d'où des flashs et des
         * « retours en arrière » résiduels. Garder la dernière image matérielle
         * est strictement meilleur : l'image sautée est de toute façon
         * invisible sous la surface.
         * ⚠ Ce cas n'est PAS marginal sur du contenu entrelacé : les images à
         * prédiction `field` ne sont pas soumises au GPU. Mesuré sur ce DVD
         * (Rage 128, 55 s) : 1465 images, 1351 décodées en matériel ⇒ **114
         * images, 8 %, passaient par ce blit**. Il coûte en plus une conversion
         * ICM logicielle (~30 %% d'un cœur de G3 pendant sa durée). */
        picture_Release (pic);
        return;
    }

    /* ★★ Tout le dessin QuickTime sous `draw_lock` : c'est ce qui permet à
     * `viewWillMoveToWindow:` de garantir qu'aucune image n'est en cours de
     * blit quand AppKit détruit le port QuickDraw. */
    vlc_mutex_lock (&sys->draw_lock);
    if (sys->suspended)
    {
        /* Déménagement de la vue en cours : le port de destination est en train
         * de disparaître. Sauter cette image est sans conséquence (au pire une
         * image perdue pendant la bascule) ; dessiner serait fatal. */
        vlc_mutex_unlock (&sys->draw_lock);
        picture_Release (pic);
        return;
    }

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
    vlc_mutex_unlock (&sys->draw_lock);

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

            /* ★★★ CAPTURE EXCLUSIVE DE L'ÉCRAN — DÉSARMÉE PAR DÉFAUT (2026-08-05).
             *
             * `CGDisplayCapture` prend l'écran en EXCLUSIVITÉ pour obtenir un
             * chemin sans copie. C'est la SEULE chose que le plein écran fasse
             * de particulier ici, et la bascule plein écran gèle la machine
             * ENTIÈRE sur ce banc (SSH lui-même ne répond plus, donc ce n'est
             * pas un blocage applicatif). Le commentaire d'en-tête du module
             * affirmait ce chemin « inatteignable avec le plein écran par
             * reparentage de l'interface legacy » — c'est FAUX, la condition
             * ci-dessous est bien remplie, et c'est probablement pourquoi le
             * défaut n'avait jamais été rapproché de la capture.
             * ⚠ On ne perd presque rien à la désarmer : d'après ce même
             * en-tête, QuickTime reconvertit de toute façon YUV→2vuy en
             * logiciel dans le décompresseur (~30 % d'un cœur de G3) quelle que
             * soit la destination — le « zéro copie » n'était donc pas atteint.
             * Interrupteur pour l'A/B, et pour reprendre le chantier plus tard :
             * `/tmp/qt_capture`. */
            static int s_cap = -1;
            if (s_cap < 0)
                s_cap = (access ("/tmp/qt_capture", F_OK) == 0) ? 1 : 0;

            NSScreen *screen = [win screen];
            if (s_cap > 0
             && screen && ([win styleMask] & NSBorderlessWindowMask)
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

        /* ==== U1 — publier la géométrie vidéo pour le décodeur matériel ATI ==
         * Thread principal (updateGeometry n'est appelé que là) : les accès
         * AppKit fenêtre/écran sont légitimes. Le G3 est 1×, points == pixels.
         *
         * ⚠ Le mode CAPTURE D'ÉCRAN est exclu : la surface du décodeur est liée
         * à une FENÊTRE, et un écran capturé ne compose plus les fenêtres — la
         * publier ferait viser une fenêtre que le WindowServer n'affiche plus.
         * On y publie donc wid=0, ce qui fait retomber le décodeur sur sa propre
         * fenêtre Carbon. */
        long widNum = (win != nil && !want_capture) ? (long)[win windowNumber] : 0;
        if (widNum > 0 && place.width > 0 && place.height > 0)
        {
            /* `place` a son origine EN HAUT à gauche dans la vue ; le repère
             * AppKit de la vue est en BAS à gauche, d'où le flip. */
            NSRect vrect = NSMakeRect (place.x,
                                       bounds.size.height - (place.y + place.height),
                                       place.width, place.height);
            NSRect wrect = [self convertRect:vrect toView:nil];       /* → fenêtre */
            NSPoint sOrg = [win convertBaseToScreen:wrect.origin];    /* → écran (10.5-safe) */

            /* L'écran « zéro » (celui de la barre de menus) est l'origine des
             * coordonnées CGS globales ; sa hauteur sert au flip vers une
             * origine haut-gauche. */
            NSArray *screens = [NSScreen screens];
            NSScreen *zero = [screens count] ? [screens objectAtIndex:0]
                                             : [NSScreen mainScreen];
            float screenH = [zero frame].size.height;

            long rx = lround (sOrg.x);
            long ry = lround (screenH - (sOrg.y + wrect.size.height));
            long rw = lround (wrect.size.width);
            long rh = lround (wrect.size.height);
            var_SetInteger (vd->obj.libvlc, DVDDRIVER_VAR_RECT_X, rx);
            var_SetInteger (vd->obj.libvlc, DVDDRIVER_VAR_RECT_Y, ry);
            var_SetInteger (vd->obj.libvlc, DVDDRIVER_VAR_RECT_W, rw);
            var_SetInteger (vd->obj.libvlc, DVDDRIVER_VAR_RECT_H, rh);
            var_SetInteger (vd->obj.libvlc, DVDDRIVER_VAR_WID, widNum);

            /* Même rectangle en coordonnées FENÊTRE-locales top-left : c'est ce
             * qu'attend CGSSetSurfaceBounds. L'origine CGS d'une fenêtre est le
             * coin haut-gauche de son FRAME, barre de titre comprise. */
            NSRect wf = [win frame];
            long wx = lround (wf.origin.x);
            long wy = lround (screenH - (wf.origin.y + wf.size.height));

            vlc_mutex_lock (&sys->place_lock);
            sys->hw_x = (int)(rx - wx);
            sys->hw_y = (int)(ry - wy);
            sys->hw_w = (int)rw;
            sys->hw_h = (int)rh;
            sys->hw_wid = (int)widNum;
            sys->hw_place_valid = true;
            vlc_mutex_unlock (&sys->place_lock);

            msg_Dbg (vd, "U1 géométrie vout : wid=%ld rect=%ld,%ld %ldx%ld "
                     "→ fenêtre-local %d,%d", widNum, rx, ry, rw, rh,
                     (int)(rx - wx), (int)(ry - wy));
        }
        else
        {
            vlc_mutex_lock (&sys->place_lock);
            sys->hw_place_valid = false;
            sys->hw_wid = 0;
            vlc_mutex_unlock (&sys->place_lock);
            var_SetInteger (vd->obj.libvlc, DVDDRIVER_VAR_WID, 0);
        }

        /* ⚠ Suspect n°1 : cet appel réveille le thread du vout, qui va
         * reconstruire sa séquence QuickTime — depuis le THREAD PRINCIPAL, qui
         * détient encore @synchronized(self) et place_lock. */
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

/* ★★★ LE POINT CRITIQUE — cf. `draw_lock`.
 *
 * AppKit appelle ceci JUSTE AVANT de sortir la vue de sa fenêtre (et avant de
 * l'insérer dans la nouvelle). C'est notre seule fenêtre de tir pour arrêter le
 * dessin : au retour de cette méthode, le port QuickDraw de la vue va être
 * détruit. Sans cela, `addSubview:` gèle la MACHINE ENTIÈRE — localisé au
 * témoin synchrone (dernière étape atteinte : « L5 insertion dans la nouvelle
 * fenetre »), parce que le fil du vout est encore dans
 * `DecompressSequenceFrameWhen` sur un port en train de disparaître.
 *
 * Prendre `draw_lock` ATTEND la fin de l'image en cours — quelques
 * millisecondes — puis interdit les suivantes. On clôt aussi la séquence de
 * décompression tant que l'ancien port est encore valide : la laisser vivre
 * sur un port mort est précisément ce qu'on veut éviter. `EnsureSequence` la
 * recréera sur le nouveau port au premier affichage qui suit. */
- (void)viewWillMoveToWindow:(NSWindow *)newWindow
{
    /* Une reprise programmée par un déménagement précédent ne doit pas tomber
     * au milieu de celui-ci. */
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                        selector:@selector(resumeDrawingAfterMove) object:nil];
    @synchronized (self) {
        if (vd) {
            vout_display_sys_t *sys = vd->sys;
            vlc_mutex_lock (&sys->draw_lock);
            sys->suspended = true;
            if (sys->seq_started) {
                CDSequenceEnd (sys->seq);
                sys->seq_started = false;
            }
            vlc_mutex_unlock (&sys->draw_lock);
        }
    }
    [super viewWillMoveToWindow:newWindow];
}

/* ★★★ REPRISE DIFFÉRÉE — la deuxième moitié du correctif.
 *
 * Reprendre le dessin dès `viewDidMoveToWindow` ne suffit PAS : cette méthode
 * est appelée AU MILIEU de la bascule, alors que le fil principal a encore à
 * masquer la barre de menus (`SetSystemUIMode`), ordonner et activer la
 * nouvelle fenêtre. Mesuré au témoin : le fil du vout repartait aussitôt
 * recréer sa séquence QuickTime sur le nouveau port **pendant** que le fil
 * principal était dans `SetSystemUIMode` — deux sollicitations simultanées du
 * serveur graphique, et la machine entière se fige (dernière étape atteinte :
 * « L6 SetSystemUIMode(masque) »).
 * `afterDelay:0` ne temporise pas : il place la reprise au TOUR SUIVANT de la
 * boucle d'événements, donc APRÈS que toute la bascule (L1…L9) soit revenue.
 * C'est exactement la garantie qu'il faut, sans délai arbitraire à calibrer.
 * ⚠ Si la boucle d'événements ne tournait pas, la vidéo resterait figée mais
 * la machine, elle, resterait vivante : le mode dégradé est acceptable. */
- (void)resumeDrawingAfterMove
{
    @synchronized (self) {
        if (vd) {
            vout_display_sys_t *sys = vd->sys;
            vlc_mutex_lock (&sys->draw_lock);
            sys->suspended = false;
            vlc_mutex_unlock (&sys->draw_lock);
        }
    }
}

/* Mouse-moved events go to the first responder (DVD menu highlighting);
 * a window change also invalidates the QuickDraw geometry. */
- (void)viewDidMoveToWindow
{
    if ([self window])
        [[self window] makeFirstResponder:self];
    [self updateGeometry];
    [super viewDidMoveToWindow];
    /* Ne PAS reprendre ici : la bascule n'est pas terminée (cf. ci-dessus). */
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                        selector:@selector(resumeDrawingAfterMove) object:nil];
    [self performSelector:@selector(resumeDrawingAfterMove)
               withObject:nil afterDelay:0.0];
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
                /* ★★ REPÈRE VERTICAL — le piège de cette sortie.
                 * `vout_display_SendMouseMovedDisplayCoordinates` attend un y
                 * mesuré depuis le HAUT. Les sorties OpenGL écrivent donc
                 * `hauteur - y`, parce que `NSOpenGLView` n'est PAS retournée
                 * (origine en bas à gauche, convention Cocoa).
                 * ⚠⚠ ICI la vue dérive de **`NSQuickDrawView`, qui retourne
                 * déjà son repère** (`isFlipped` = OUI) pour coller à QuickDraw :
                 * `ml.y` est DÉJÀ mesuré depuis le haut. Recopier la ligne des
                 * sorties GL appliquait donc un SECOND retournement — d'où des
                 * menus DVD où survoler « Play » sélectionnait « Set Up »,
                 * c'est-à-dire l'entrée symétrique par rapport au centre.
                 * Diagnostiqué à la mesure (2026-08-05) : `place y=0 h=576`,
                 * `orientation=0`, tout le reste de la chaîne étant neutre, le
                 * signe ne pouvait s'inverser qu'ici.
                 * Le test porte sur `isFlipped` plutôt que sur la classe : la
                 * ligne reste juste si la vue change de parent un jour. */
                const int i_disp_y = [self isFlipped]
                    ? (int) ml.y
                    : (int) videoRect.size.height - (int) ml.y;
                vout_display_SendMouseMovedDisplayCoordinates(vd, ORIENT_NORMAL,
                    (int)ml.x, i_disp_y, &place);
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
