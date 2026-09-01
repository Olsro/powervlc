/*****************************************************************************
 * macosx_gl1.m: fixed-pipeline OpenGL 1.1 video output for Mac OS X
 *****************************************************************************
 * Copyright (C) 2001-2026 VLC authors and VideoLAN
 *
 * Authors: derived from macosx.m (shader-based output) and from the
 *          VLC 0.9 opengl.c/voutgl.m fixed-pipeline output, for machines
 *          whose GPU has no GLSL support (PowerPC G3/G4 era: ATI Rage 128,
 *          Radeon 7000-9200, GeForce 2MX/4MX...).
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
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <CoreVideo/CoreVideo.h>
#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED >= 1060
# import <IOSurface/IOSurface.h>
# define VLC_GL1_HAVE_IOSURFACE 1
#endif
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <mach/thread_policy.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>
#include <vlc_opengl.h>
#include <vlc_picture_pool.h>
#include <sys/sysctl.h>

/* U4 — present HW piloté par le vout (contrat décodeur ↔ vout via bus libvlc). */
#include "../codec/dvddriver_piccontext.h"
#include "../codec/mvc_piccontext.h"
#include "cgl_lock_compat.h"

/* Framebuffer objects were added to the OpenGL framework after Jaguar.
 * Keeping direct references here makes dyld reject the whole GL1 module on
 * 10.2, even though the FBO presenter is only used by much newer NVIDIA
 * hardware.  Resolve the five entry points lazily so the ordinary fixed
 * pipeline remains loadable on the G3 while preserving the presenter on
 * systems that provide GL_EXT_framebuffer_object. */
typedef void (*vlc_gl1_bind_fbo_cb)(GLenum, GLuint);
typedef GLenum (*vlc_gl1_check_fbo_cb)(GLenum);
typedef void (*vlc_gl1_delete_fbo_cb)(GLsizei, const GLuint *);
typedef void (*vlc_gl1_attach_fbo_cb)(GLenum, GLenum, GLenum, GLuint, GLint);
typedef void (*vlc_gl1_gen_fbo_cb)(GLsizei, GLuint *);
typedef CGLError (*vlc_gl1_fullscreen_display_cb)(CGLContextObj,
                                                  CGOpenGLDisplayMask);

/* CGLSetFullScreenOnDisplay appeared after Jaguar.  Keeping a direct
 * reference makes dyld reject this whole output module on 10.2 even though
 * exclusive scanout is only requested on much newer NVIDIA hardware. */
static CGLError vlc_gl1_SetFullScreenOnDisplay(CGLContextObj context,
                                               CGOpenGLDisplayMask mask)
{
    static vlc_gl1_fullscreen_display_cb cb;
    static bool resolved;
    if (!resolved) {
        cb = (vlc_gl1_fullscreen_display_cb)
            dlsym(RTLD_DEFAULT, "CGLSetFullScreenOnDisplay");
        resolved = true;
    }
    if (cb != NULL)
        return cb(context, mask);

    /* Jaguar can only select the display through the pixel format, which is
     * already constrained to the active screen when this context is made. */
    return CGLSetFullScreen(context);
}

static void vlc_gl1_BindFramebufferEXT(GLenum target, GLuint framebuffer)
{
    static vlc_gl1_bind_fbo_cb cb;
    static bool resolved;
    if (!resolved) {
        cb = (vlc_gl1_bind_fbo_cb)dlsym(RTLD_DEFAULT, "glBindFramebufferEXT");
        resolved = true;
    }
    if (cb != NULL)
        cb(target, framebuffer);
}

static GLenum vlc_gl1_CheckFramebufferStatusEXT(GLenum target)
{
    static vlc_gl1_check_fbo_cb cb;
    static bool resolved;
    if (!resolved) {
        cb = (vlc_gl1_check_fbo_cb)dlsym(RTLD_DEFAULT,
                                         "glCheckFramebufferStatusEXT");
        resolved = true;
    }
    return cb != NULL ? cb(target) : 0;
}

static void vlc_gl1_DeleteFramebuffersEXT(GLsizei count,
                                          const GLuint *framebuffers)
{
    static vlc_gl1_delete_fbo_cb cb;
    static bool resolved;
    if (!resolved) {
        cb = (vlc_gl1_delete_fbo_cb)dlsym(RTLD_DEFAULT,
                                          "glDeleteFramebuffersEXT");
        resolved = true;
    }
    if (cb != NULL)
        cb(count, framebuffers);
}

static void vlc_gl1_FramebufferTexture2DEXT(GLenum target, GLenum attachment,
                                            GLenum texture_target,
                                            GLuint texture, GLint level)
{
    static vlc_gl1_attach_fbo_cb cb;
    static bool resolved;
    if (!resolved) {
        cb = (vlc_gl1_attach_fbo_cb)dlsym(RTLD_DEFAULT,
                                          "glFramebufferTexture2DEXT");
        resolved = true;
    }
    if (cb != NULL)
        cb(target, attachment, texture_target, texture, level);
}

static void vlc_gl1_GenFramebuffersEXT(GLsizei count, GLuint *framebuffers)
{
    static vlc_gl1_gen_fbo_cb cb;
    static bool resolved;
    if (!resolved) {
        cb = (vlc_gl1_gen_fbo_cb)dlsym(RTLD_DEFAULT,
                                       "glGenFramebuffersEXT");
        resolved = true;
    }
    if (cb != NULL)
        cb(count, framebuffers);
    else
        memset(framebuffers, 0, count * sizeof(*framebuffers));
}

#define glBindFramebufferEXT         vlc_gl1_BindFramebufferEXT
#define glCheckFramebufferStatusEXT  vlc_gl1_CheckFramebufferStatusEXT
#define glDeleteFramebuffersEXT      vlc_gl1_DeleteFramebuffersEXT
#define glFramebufferTexture2DEXT    vlc_gl1_FramebufferTexture2DEXT
#define glGenFramebuffersEXT         vlc_gl1_GenFramebuffersEXT

/* Per-stage timing of the display path, enabled by setting VLC_GL1_PROF in
 * the environment. Costs one gettimeofday per stage when off... nothing at
 * all: the whole thing compiles out to a load of a static bool. */
static bool gl1_prof_on;
static struct { uint64_t upload, clear, draw, swap; unsigned n; } gl1_prof;
#define GL1_PROF_START(v) \
    vlc_tick_t v = gl1_prof_on ? mdate () : 0
#define GL1_PROF_ADD(field, v) \
    do { if (gl1_prof_on) gl1_prof.field += mdate () - (v); } while (0)
#define GL1_PROF_REPORT(vd) \
    do { \
        if (gl1_prof_on && ++gl1_prof.n == 200) { \
            msg_Dbg (vd, "gl1 profile (200 frames): upload %llu us/f, " \
                     "clear %llu us/f, draw %llu us/f, swap %llu us/f", \
                     (unsigned long long) gl1_prof.upload / 200, \
                     (unsigned long long) gl1_prof.clear / 200, \
                     (unsigned long long) gl1_prof.draw / 200, \
                     (unsigned long long) gl1_prof.swap / 200); \
            memset (&gl1_prof, 0, sizeof (gl1_prof)); \
        } \
    } while (0)

/* The Apple packed-YCbCr texture extension does the YUV -> RGB conversion
 * in the texturing unit, which every Mac GPU ever shipped supports (it was
 * designed for QuickTime playback). On big-endian machines the '2vuy'
 * layout reads as YUY2, on little-endian as UYVY (see VLC 0.9 opengl.c). */
#ifndef GL_YCBCR_422_APPLE
# define GL_YCBCR_422_APPLE 0x85B9
#endif
#ifndef GL_UNSIGNED_SHORT_8_8_APPLE
# define GL_UNSIGNED_SHORT_8_8_APPLE 0x85BA
#endif
/* The reversed component order of the same extension. Which byte layout each
 * type accepts depends on the CPU endianness; VLCGL1_CHROMA below names the
 * in-memory chroma accepted by the non-REV type on this target. Having both
 * types lets a 4:2:2 source of either order be textured without conversion. */
#ifndef GL_UNSIGNED_SHORT_8_8_REV_APPLE
# define GL_UNSIGNED_SHORT_8_8_REV_APPLE 0x85BB
#endif
#ifndef GL_TEXTURE_RECTANGLE_EXT
# define GL_TEXTURE_RECTANGLE_EXT 0x84F5
#endif
#ifndef GL_MAX_RECTANGLE_TEXTURE_SIZE_EXT
# define GL_MAX_RECTANGLE_TEXTURE_SIZE_EXT 0x84F8
#endif
#ifndef GL_UNPACK_CLIENT_STORAGE_APPLE
# define GL_UNPACK_CLIENT_STORAGE_APPLE 0x85B2
#endif
#ifndef GL_TEXTURE_STORAGE_HINT_APPLE
# define GL_TEXTURE_STORAGE_HINT_APPLE 0x85BC
#endif
#ifndef GL_STORAGE_SHARED_APPLE
# define GL_STORAGE_SHARED_APPLE 0x85BF
#endif
#ifndef GL_STORAGE_CACHED_APPLE
# define GL_STORAGE_CACHED_APPLE 0x85BE
#endif

#ifdef WORDS_BIGENDIAN
# define VLCGL1_CHROMA VLC_CODEC_YUYV
#else
# define VLCGL1_CHROMA VLC_CODEC_UYVY
#endif

/* Planar path: the CPU interleave I420 -> 4:2:2 costs ~20 CPU points of a
 * G3 for DVD-sized video. When the fixed pipeline has a multiply-add
 * combiner (GL_ATI_texture_env_combine3, present on every Radeon of the
 * era), the BT.601 matrix can be computed exactly by the GPU from the
 * three planes: one pass per RGB channel through glColorMask, three MAD
 * stages per pass, every in-gamut intermediate provably within [0,1]. */
#ifndef GL_COMBINE
# define GL_COMBINE 0x8570
#endif
#ifndef GL_COMBINE_RGB
# define GL_COMBINE_RGB 0x8571
#endif
#ifndef GL_COMBINE_ALPHA
# define GL_COMBINE_ALPHA 0x8572
#endif
#ifndef GL_RGB_SCALE
# define GL_RGB_SCALE 0x8573
#endif
#ifndef GL_CONSTANT
# define GL_CONSTANT 0x8576
#endif
#ifndef GL_PREVIOUS
# define GL_PREVIOUS 0x8578
#endif
#ifndef GL_SOURCE0_RGB
# define GL_SOURCE0_RGB 0x8580
#endif
#ifndef GL_SOURCE1_RGB
# define GL_SOURCE1_RGB 0x8581
#endif
#ifndef GL_SOURCE2_RGB
# define GL_SOURCE2_RGB 0x8582
#endif
#ifndef GL_OPERAND0_RGB
# define GL_OPERAND0_RGB 0x8590
#endif
#ifndef GL_OPERAND1_RGB
# define GL_OPERAND1_RGB 0x8591
#endif
#ifndef GL_OPERAND2_RGB
# define GL_OPERAND2_RGB 0x8592
#endif
#ifndef GL_SOURCE0_ALPHA
# define GL_SOURCE0_ALPHA 0x8588
#endif
#ifndef GL_OPERAND0_ALPHA
# define GL_OPERAND0_ALPHA 0x8598
#endif
#ifndef GL_SUBTRACT
# define GL_SUBTRACT 0x84E7
#endif
#ifndef GL_MODULATE_ADD_ATI
# define GL_MODULATE_ADD_ATI 0x8744
#endif
#ifndef GL_MODULATE_SIGNED_ADD_ATI
# define GL_MODULATE_SIGNED_ADD_ATI 0x8745
#endif
#ifndef GL_MAX_TEXTURE_UNITS
# define GL_MAX_TEXTURE_UNITS 0x84E2
#endif
#ifndef GL_PRIMARY_COLOR
# define GL_PRIMARY_COLOR 0x8577
#endif
#ifndef GL_TEXTURE0
# define GL_TEXTURE0 0x84C0
#endif
#ifndef GL_TEXTURE1
# define GL_TEXTURE1 0x84C1
#endif
#ifndef GL_TEXTURE2
# define GL_TEXTURE2 0x84C2
#endif

/* BT.601 limited-range coefficients, staged so that every in-gamut
 * intermediate stays within [0,1] (see the pass comments in OpenglDraw).
 * R = 1.1644 Y + 1.5960 V - 0.8742
 * G = 1.1644 Y - 0.3918 U - 0.8130 V + 0.5318
 * B = 1.1644 Y + 2.0172 U - 1.0856  */
#define MTX_Y2   0.5822f  /* 1.1644 / 2 */
#define MTX_Y4   0.2911f  /* 1.1644 / 4 */
#define MTX_RV2  0.7980f  /* 1.5960 / 2 */
#define MTX_RK2  0.4371f  /* 0.8742 / 2 */
#define MTX_GU2  0.1959f  /* 0.3918 / 2 */
#define MTX_GV2  0.4065f  /* 0.8130 / 2 */
#define MTX_GK   0.1635f  /* chosen so 2*(Y2 Y + s1 - 0.5) lands on G */
#define MTX_BU4  0.5043f  /* 2.0172 / 4 */
#define MTX_BK4  0.2714f  /* 1.0856 / 4 */

static int  Open   (vlc_object_t *);
static void Close  (vlc_object_t *);

static picture_pool_t *Pool (vout_display_t *vd, unsigned requested_count);
static void PictureRender (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture);
static void PictureDisplay (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture);
static int Control (vout_display_t *vd, int query, va_list ap);

static int OpenglLock (vlc_gl_t *gl);
static void OpenglUnlock (vlc_gl_t *gl);
static void OpenglSwap (vlc_gl_t *gl);
static void *GL1AsyncPresenter (void *opaque);
static void *GL1FlipPresenter (void *opaque);
static void GL1PresenterDidFlip(vout_display_sys_t *display);
static CVReturn GL1DisplayLinkPresenter(CVDisplayLinkRef,
                                        const CVTimeStamp *,
                                        const CVTimeStamp *,
                                        CVOptionFlags, CVOptionFlags *, void *);

#define GL1_PLANAR_TEXT "GPU planar YUV (combiners)"
#define GL1_PLANAR_LONGTEXT "Feed the raw Y/U/V planes to the GPU and let " \
    "the fixed-function combiners apply the color matrix, instead of " \
    "interleaving 4:2:2 on the CPU. Needs GL_ATI_texture_env_combine3 and " \
    "3 texture units, so only capable GPUs take this path (others fall back " \
    "to the packed 4:2:2 upload automatically). On by default: it roughly " \
    "halves the CPU on DVD-sized video (measured ~90%->60% on a GMA 950). " \
    "The one known regression is a windowed stutter on the weakest GPU of " \
    "the era, the ATI Rage 128 in the iBook G3 (its compositor blit of the " \
    "3-pass/colormask backbuffer remaps the surface every frame); fullscreen " \
    "is unaffected everywhere. Disable it there if the window stutters."

#define GL1_FRAGPROG_TEXT "Single-pass YUV via ARB fragment program"
#define GL1_FRAGPROG_LONGTEXT "When the GPU has a programmable fragment " \
    "stage (GL_ARB_fragment_program), apply the colour matrix in one pass " \
    "instead of the three colour-masked combiner passes needed by the " \
    "fixed-function GPUs. Same picture, a third of the fill rate and of " \
    "the per-frame GL state. Turn off to force the combiner path."

#define GL1_PERBUF_TEXT "One texture set per pool buffer (planar)"
#define GL1_PERBUF_LONGTEXT "Give every picture buffer of the pool its own " \
    "Y/U/V textures instead of redefining two ping-pong sets each frame. " \
    "Under client storage a redefinition makes the driver revalidate and " \
    "remap the buffer, which a 1080p pool pays for on every frame. The " \
    "trade is that every pool buffer then stays pinned in the GPU aperture, " \
    "so turn this off on a GPU whose aperture is too small for that."

#define GL1_POOL_MAX_TEXT "Maximum number of GL1 picture buffers"
#define GL1_POOL_MAX_LONGTEXT "Limit the GL1 picture pool after normal cache " \
    "sizing. Zero keeps the automatic size. This is mainly useful on legacy " \
    "GPUs where keeping too many client-storage textures resident can exhaust " \
    "the graphics aperture and stall both video decode and presentation."

#define GL1_FULLSCREEN_CACHED_TEXT "Cache planar textures in fullscreen"
#define GL1_FULLSCREEN_CACHED_LONGTEXT "Upload planar frames to video memory " \
    "before drawing in fullscreen. Disable this on a unified GPU when video " \
    "decoding and texture DMA contend for the same graphics engine."

#define GL1_VSYNC_TEXT "Synchronize GL1 presentation to vertical retrace"
#define GL1_VSYNC_LONGTEXT "Wait for vertical retrace before swapping the " \
    "GL1 buffers. Disabling this is intended for performance diagnosis only."

#define GL1_CACHED_TEXT "VRAM-cached packed textures"
#define GL1_CACHED_LONGTEXT "Upload the packed 4:2:2 frame to VRAM once " \
    "per frame (GL_STORAGE_CACHED_APPLE, what Apple's DVD Player uses) " \
    "instead of letting the GPU fetch it from system memory during the " \
    "draw (SHARED). Costs one DMA copy, saves the AGP fetch at draw " \
    "time; which side wins depends on the GPU/presentation path, so " \
    "measure before flipping the default."

/**
 * Module declaration
 */
vlc_module_begin ()
    set_shortname ("Mac OS X GL1")
    set_description (N_("Mac OS X OpenGL 1.1 video output (no shaders)"))
    set_category (CAT_VIDEO)
    set_subcategory (SUBCAT_VIDEO_VOUT)
    /* Below the shader-based "macosx" output (250): only used when the
     * latter fails, i.e. when the GPU cannot compile GLSL. */
    set_capability ("vout display", 60)
    set_callbacks (Open, Close)
    add_shortcut ("macosx_gl1", "glfixed")
    add_bool ("gl1-planar", true, GL1_PLANAR_TEXT, GL1_PLANAR_LONGTEXT, true)
    add_bool ("gl1-fragprog", true, GL1_FRAGPROG_TEXT, GL1_FRAGPROG_LONGTEXT, true)
    add_bool ("gl1-per-buffer-tex", true, GL1_PERBUF_TEXT, GL1_PERBUF_LONGTEXT, true)
    add_integer ("gl1-pool-max", 0, GL1_POOL_MAX_TEXT, GL1_POOL_MAX_LONGTEXT, true)
    add_bool ("gl1-fullscreen-cached", true, GL1_FULLSCREEN_CACHED_TEXT,
              GL1_FULLSCREEN_CACHED_LONGTEXT, true)
    add_bool ("gl1-vsync", true, GL1_VSYNC_TEXT, GL1_VSYNC_LONGTEXT, true)
    add_bool ("gl1-packed-cached", false, GL1_CACHED_TEXT, GL1_CACHED_LONGTEXT, true)
vlc_module_end ()

#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED < 1050
/* -[NSThread isMainThread] is 10.5+; pthread_main_np() is the 10.4 way */
# include <pthread.h>
# define VLCAssertMainThread() assert(pthread_main_np() != 0)
#else
# define VLCAssertMainThread() assert([[NSThread currentThread] isMainThread])
#endif

/**
 * Obj-C protocol declaration that drawable-nsobject should follow
 * (same informal contract as the macosx module)
 */
@protocol VLCOpenGLVideoViewEmbedding <NSObject>
- (void)addVoutSubview:(NSView *)view;
- (void)removeVoutSubview:(NSView *)view;
@end

@interface VLCGL1VideoView : NSOpenGLView
{
    vout_display_t *vd;
    BOOL _hasPendingReshape;
    /* Chantier S — fenêtre enfant transparente portant sous-titres et OSD
     * au-dessus de la surface matérielle (cf. VLCGL1SubsOverlayView). */
    NSWindow *_subsOverlay;
    /* ⚠⚠ Fenêtre PARENTE de l'incrustation, suivie PAR NOUS et RETENUE
     * tant que l'incrustation lui appartient. Une référence faible devient
     * pendante quand Jaguar détruit son ancienne fenêtre plein écran avant le
     * refresh suivant : une pause qui vide alors le sous-titre plante dans
     * objc_msgSend sur removeChildWindow:. NE PAS demander
     * `-[NSWindow parentWindow]` : sur 10.2 cet
     * accesseur CRASHE (EXC_BAD_ACCESS à 0x0 dans un objc_msgSend interne,
     * relevé en direct le 2026-07-29 sur 10.2.8, pendant une pause) — la
     * machinerie de fenêtres enfants de Jaguar est celle dont nos notes disent
     * déjà qu'elle « n'affiche rien ». Nous savons à qui nous l'avons donnée :
     * il n'y a rien à demander à AppKit. */
    NSWindow *_subsOverlayParent;
    NSRect    _subsOverlayRect;   /* cadre courant (écran), 0 = jamais posé */
}
- (void)setVoutDisplay:(vout_display_t *)vd;
- (void)setVoutFlushing:(BOOL)flushing;
- (void)vlcAsyncSwap;
- (void)refreshSubsOverlay;
+ (void)vlcHideCursor;
+ (void)vlcHideCursorAgain;
- (void)vlcHwEnsureCover;
- (void)vlcHwCoverAndRefresh;
- (void)vlcHwRecomputeSurfaces;
- (void)vlcHwRestoreOpaque;
- (void)vlcTryRemedy:(NSNumber *)num;
@end

/* Packed mode binds one texture per pool picture buffer (5-ish buffers:
 * requested 3 + the 2 held ones), defined once with glTexImage2D and then
 * only dirtied with glTexSubImage2D — the Apple DVD Player recipe: with
 * client storage a full redefinition makes the driver revalidate and remap
 * the client memory every frame, a TexSubImage on the same pointer just
 * queues a new DMA. Never do this in planar/DR mode: the pool can grow to
 * 48 pictures there and pinning them all in the AGP aperture at once is
 * exactly the io_connect_map_memory thrash of round 56. */
#define GL1_MAX_PIC_TEXTURES 8

/* Planar per-buffer textures: the pool a 1080p H.264 decoder asks for is
 * ~38 pictures, so the table has to cover it -- if a buffer misses, its
 * texture set is redefined and we are back to the per-frame remap. */
#define GL1_MAX_PLANAR_SETS 48

/* GPU-composited subpictures (DVD SPU/menus, OSD): small RGBA rectangle
 * textures blended over the video by the GPU. Uploaded WITHOUT client
 * storage (the core frees the region right after display, the driver must
 * own a copy). A DVD shows 1-2 regions, OSD a couple more. */
#define GL1_MAX_REGIONS 16

typedef struct gl1_region
{
    GLuint  texture;
    GLsizei width;    /* allocated texture size */
    GLsizei height;
    unsigned used_w;  /* used texels (rect texture coords) */
    unsigned used_h;
    float   alpha;
    float   left, top, right, bottom; /* NDC quad */
} gl1_region_t;

struct vout_display_sys_t
{
    vout_display_t *owner_vd;
    VLCGL1VideoView *glView;
    id<VLCOpenGLVideoViewEmbedding> container;

    vout_window_t *embed;
    vlc_gl_t *gl;

    picture_pool_t *pool;
    bool has_first_frame;
    /* Une image HW compte comme première image pour la politique de redraw
     * AppKit, mais elle n'a créé aucune texture GL. Les confondre faisait
     * déréférencer draw_tex_set == NULL lors d'un resize. */
    bool has_gl_frame;

    /* Textures backed by client storage (GL_APPLE_client_storage):
     * the driver DMAs straight from the picture buffers instead of
     * copying them, which matters a lot on a G3 (see VLC 0.9 opengl.c).
     * The last two displayed pictures are therefore kept alive until
     * the driver cannot be reading them anymore. Packed mode uses the
     * per-picture-buffer table below; planar mode ping-pongs
     * textures[i][0..2] = Y/U/V with full redefinitions. */
    bool planar;
    /* planar, one texture set per pool picture buffer: no per-frame
     * glTexImage2D redefinition and no copy, at the price of pinning every
     * pool buffer in the GPU aperture. See GL1_MAX_PLANAR_SETS. */
    struct { const void *pixels; GLuint tex[3]; } plane_tex[GL1_MAX_PLANAR_SETS];
    unsigned plane_tex_count;
    const GLuint *draw_tex_set;
    bool     per_buffer_tex;
    bool     fullscreen_cached;
    bool     vsync_requested;
    bool     nvidia_320m;
    int      swap_interval;
    bool fragprog;        /* planar in one pass, via ARB_fragment_program */
    GLuint fp;            /* the compiled fragment program, 0 = none */
    bool packed_cached;   /* gl1-packed-cached option */
    GLenum packed_type;   /* GL type matching the source's packed byte order */
    GLuint textures[2][3];
    GLuint direct_mvc_tex[2][3];
    struct { const void *pixels; GLuint tex[3]; }
        direct_plane_tex[2][GL1_MAX_PLANAR_SETS];
    unsigned direct_plane_tex_count[2];
    GLuint direct_mvc_base_tex;
    GLuint direct_mvc_base_fbo;
    bool direct_mvc;
    bool direct_mvc_has_packed_base;
    unsigned direct_mvc_base_eye;
    unsigned direct_mvc_width;
    unsigned direct_mvc_height;
    unsigned tex_index;
    GLenum storage_hint;  /* current GL_TEXTURE_STORAGE_HINT_APPLE value */
    bool on_fullscreen_window; /* view lives in a borderless window
                                  covering its screen (set on main thread,
                                  read by the vout thread) */
    bool hdmi_framepack;
    unsigned framepack_eye_height;
    unsigned framepack_gap;
    /* Snow Leopard/NVIDIA frame-packed presentation.  Waiting for a beam
     * position on the vout thread stalls the decoder once its picture pool
     * fills.  The presenter owns that wait and only touches the GL context
     * after PictureDisplay has finished drawing the back buffer. */
    vlc_thread_t presenter_thread;
    bool presenter_thread_started;
    vlc_thread_t presenter_flip_thread;
    bool presenter_flip_thread_started;
    vlc_mutex_t presenter_lock;
    vlc_cond_t presenter_cond;
    bool presenter_started;
    bool presenter_uses_display_link;
    bool presenter_stop;
    CVDisplayLinkRef presenter_display_link;
    GLuint presenter_texture[2];
    GLuint presenter_fbo[2];
    unsigned presenter_texture_width;
    unsigned presenter_texture_height;
    int presenter_inflight;
    int presenter_queued;
    unsigned presenter_next;
    unsigned presenter_presented;
    unsigned presenter_dropped;
    picture_t *presenter_picture_queued;
    picture_t *presenter_picture_queued_next;
    picture_t *presenter_picture_inflight;
    subpicture_t *presenter_subpicture_queued;
    subpicture_t *presenter_subpicture_queued_next;
    subpicture_t *presenter_subpicture_inflight;
    bool presenter_native_ready;
    bool presenter_native_deferred;
    uint64_t presenter_native_target_host_time;
    uint64_t presenter_native_flip_serial;
    vlc_tick_t presenter_report_start;
    CGDirectDisplayID stereo_display;
    int stereo_saved_private_mode;
    bool stereo_private_mode_changed;
    CGDirectDisplayID stereo_disabled_displays[4];
    unsigned stereo_disabled_display_count;
    bool stereo_fullscreen_forced;
    bool stereo_fullscreen_display_overridden;
    bool exclusive_capture;
    int64_t stereo_saved_fullscreen_display;
    picture_t *held_pics[2];
    unsigned tex_width;   /* visible dimensions, in pixels */
    unsigned tex_height;
    unsigned x_offset;    /* crop offsets inside the picture planes */
    unsigned y_offset;
    /* Rognage DEMANDÉ PAR L'UTILISATEUR (menu « Rogner »), en texels et relatif
     * au coin haut-gauche de la texture — donc déjà débarrassé de x_offset /
     * y_offset, qui repèrent la zone visible du décodeur, elle DÉJÀ appliquée à
     * l'envoi. Vaut la texture entière tant que rien n'est rogné.
     * ⚠ Le rognage ne change QUE `vd->source` (cf. src/video_output/display.c) ;
     * `vd->fmt` garde la taille des images reçues. Un affichage qui se contente
     * de `vd->fmt` — ce que celui-ci faisait — voit donc sa FENÊTRE se remettre
     * au bon format (le placement, lui, se calcule sur `vd->source`) alors que
     * l'image, elle, reste entière et se retrouve simplement écrasée dedans.
     * Écrit par le fil du vout dans Control(), relu sans verrou par OpenglDraw()
     * comme tex_width/orient juste au-dessus — même convention. */
    unsigned crop_x, crop_y, crop_w, crop_h;
    video_orientation_t orient; /* baked into the texture coordinates:
                                 * see OrientTexCorner() */

    /* packed mode: one texture per pool picture buffer */
    struct { const void *pixels; GLuint texture; }
             pic_tex[GL1_MAX_PIC_TEXTURES];
    unsigned pic_tex_count;
    unsigned pic_tex_evict;   /* round-robin fallback, never hit with the
                                 stock 5-picture packed pool */
    GLuint   draw_tex;        /* texture of the last uploaded picture */

    gl1_region_t regions[GL1_MAX_REGIONS];
    int region_count;

    vout_display_place_t place;

    /* Rectangle vidéo en coordonnées FENÊTRE-locales, ORIGINE HAUT-GAUCHE —
     * c'est le contrat de CGSSetSurfaceBounds pour la surface du décodeur ATI.
     * ⚠ `place` ci-dessus est en coordonnées VUE : le passer tel quel décalait la
     * surface de la hauteur de la barre de titre (et de toute autre chrome), si
     * bien que la vidéo recouvrait le haut de la fenêtre et, selon la géométrie,
     * les contrôles. Calculé dans -reshape (thread principal, accès AppKit) et lu
     * par PictureDisplay (thread vout) sous @synchronized(glView), comme `place`. */
    int hw_x, hw_y, hw_w, hw_h;
    bool hw_place_valid;
    /* Fenêtre CGS où la vidéo est affichée MAINTENANT : change au passage en
     * plein écran (la vue vidéo est déplacée dans une autre fenêtre), le
     * décodeur doit y ré-attacher sa surface sinon l'écran reste noir. */
    int  hw_wid;
    /* Sous-titres/OSD en mode matériel : le chemin HW saute le rendu GL et la
     * surface du décodeur est composée AU-DESSUS du contenu de la fenêtre —
     * tout ce que la vue GL dessinerait serait recouvert. Et l'inverse ne marche
     * pas non plus : deux surfaces CGS d'une même fenêtre NE SE MÉLANGENT PAS
     * (mesuré sur G3/RV200). L'incrustation passe donc par une fenêtre enfant
     * transparente (cf. VLCGL1SubsOverlayView).
     * hw_subs_mode : décidé par le DÉCODEUR (option mpeg2-hwaccel-subs, publié
     *   sur DVDDRIVER_VAR_SUBS) et lu ici au PREMIER present matériel — pas à
     *   l'Open : la variable n'a sa valeur définitive qu'après l'ouverture du
     *   contexte HW, qui suit la création du vout. */
    bool hw_subs_mode;
    bool hw_subs_known;
    /* Image de superposition (RGBA PRÉMULTIPLIÉ) produite par le thread vout et
     * consommée par le thread principal, qui la pose dans la fenêtre de
     * superposition. ovl_x/y/w/h = rectangle en coordonnées VUE (origine
     * haut-gauche). ovl_pending : une nouvelle image (ou un effacement) attend
     * d'être publiée. ovl_sig : signature de l'incrustation courante, pour ne
     * rien recalculer tant qu'elle ne change pas — c'est ce qui préserve le
     * gain CPU du décodage matériel (cf. SubpictureSignature). */
    uint8_t *ovl_data;
    /* Le bitmap est composé à la résolution SOURCE des régions (ovl_bw×ovl_bh)
     * et affiché dans le rectangle de DESTINATION en coordonnées vue
     * (ovl_x/y/w/h) : la mise à l'échelle est faite par AppKit au moment du
     * dessin, sur le thread principal. La faire ici, sur le thread vout et
     * juste avant l'affichage, retardait l'image à chaque apparition de
     * sous-titre (mesuré : 9 ms pour une bande 1000×72 sur iBook G3). */
    int   ovl_bw, ovl_bh;
    int   ovl_x, ovl_y, ovl_w, ovl_h;
    bool  ovl_pending;
    uint64_t ovl_sig;
    /* Empreinte de l'incrustation RÉELLEMENT publiée (cadre + pixels composés).
     * Le cœur re-rend le SPU d'un DVD à chaque image en réallouant ses régions :
     * la signature d'entrée change donc en permanence alors que l'image
     * composée, elle, est identique. Republier à ce rythme repositionnait et
     * réaffichait la fenêtre de superposition 25 fois par seconde — d'où un
     * clignotement massif à l'écran (constaté sur un vrai DVD). */
    uint64_t ovl_hash;
    /* Dimensions de la VUE (points = pixels ici), publiées par -reshape :
     * l'incrustation est calculée en coordonnées vue. */
    int view_w, view_h;
    /* Effacer le framebuffer GL au prochain present matériel (marges du
     * letterbox : voir PictureDisplay). Armé à chaque changement de géométrie. */
    bool hw_need_clear;
};

struct gl_sys
{
    CGLContextObj locked_ctx;
    VLCGL1VideoView *glView;
    vout_display_sys_t *display_sys;
};

/* The Snow Leopard 320M MVC path is no longer experimental: once the output
 * has negotiated an HDMI frame-packed drawable, use the measured working
 * pipeline by default.  Environment switches remain useful for diagnostics
 * and for forcing individual stages on other legacy GPUs. */
static bool GL1UseNvidiaMvcPath(const vout_display_sys_t *sys,
                               const char *diagnostic_switch)
{
    return getenv(diagnostic_switch) != NULL ||
           (sys->nvidia_320m && sys->hdmi_framepack);
}

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
} gl1_cgs_display_mode_t;

typedef CGError (*GL1CGSGetCurrentDisplayMode)(CGDirectDisplayID, int *);
typedef void (*GL1CGSGetNumberOfDisplayModes)(CGDirectDisplayID, int *);
typedef void (*GL1CGSGetDisplayModeDescriptionOfLength)(
    CGDirectDisplayID, int, gl1_cgs_display_mode_t *, int);
typedef CGError (*GL1CGSConfigureDisplayMode)(CGDisplayConfigRef,
                                              CGDirectDisplayID, int);
typedef CGError (*GL1ConfigureDisplayEnabled)(CGDisplayConfigRef,
                                              CGDirectDisplayID, bool);

static bool GL1LoadDisplayFunctions(GL1CGSGetCurrentDisplayMode *current,
                                    GL1CGSGetNumberOfDisplayModes *count,
                                    GL1CGSGetDisplayModeDescriptionOfLength *desc,
                                    GL1CGSConfigureDisplayMode *configure)
{
    *current = (GL1CGSGetCurrentDisplayMode)
        dlsym(RTLD_DEFAULT, "CGSGetCurrentDisplayMode");
    *count = (GL1CGSGetNumberOfDisplayModes)
        dlsym(RTLD_DEFAULT, "CGSGetNumberOfDisplayModes");
    *desc = (GL1CGSGetDisplayModeDescriptionOfLength)
        dlsym(RTLD_DEFAULT, "CGSGetDisplayModeDescriptionOfLength");
    *configure = (GL1CGSConfigureDisplayMode)
        dlsym(RTLD_DEFAULT, "CGSConfigureDisplayMode");
    return *current != NULL && *count != NULL && *desc != NULL &&
           *configure != NULL;
}

static CGError GL1ConfigurePrivateMode(CGDirectDisplayID display, int mode)
{
    GL1CGSGetCurrentDisplayMode current;
    GL1CGSGetNumberOfDisplayModes count;
    GL1CGSGetDisplayModeDescriptionOfLength desc;
    GL1CGSConfigureDisplayMode configure;
    if (!GL1LoadDisplayFunctions(&current, &count, &desc, &configure))
        return kCGErrorNotImplemented;
    VLC_UNUSED(current); VLC_UNUSED(count); VLC_UNUSED(desc);

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

static int GL1FindFramepackMode(CGDirectDisplayID display, unsigned width,
                                unsigned height, double rate,
                                int *saved_mode)
{
    GL1CGSGetCurrentDisplayMode current;
    GL1CGSGetNumberOfDisplayModes count_fn;
    GL1CGSGetDisplayModeDescriptionOfLength desc;
    GL1CGSConfigureDisplayMode configure;
    if (!GL1LoadDisplayFunctions(&current, &count_fn, &desc, &configure) ||
        current(display, saved_mode) != kCGErrorSuccess)
        return -1;
    VLC_UNUSED(configure);

    gl1_cgs_display_mode_t active = { 0 };
    desc(display, *saved_mode, &active, sizeof(active));
    int count = 0;
    count_fn(display, &count);
    const bool fractional = fabs(rate - 24000.0 / 1001.0) < 0.01;
    int best = -1, depth_best = -1;
    for (int i = 0; i < count; ++i)
    {
        gl1_cgs_display_mode_t mode = { 0 };
        desc(display, i, &mode, sizeof(mode));
        if (mode.width != width || mode.height != height ||
            fabs((double)mode.frequency - rate) > 0.6)
            continue;
        if (best < 0 || !fractional)
            best = i;
        if (mode.depth == active.depth && (mode.flags & 0x80000000U) == 0 &&
            (depth_best < 0 || !fractional))
            depth_best = i;
    }
    return depth_best >= 0 ? depth_best : best;
}

static GL1ConfigureDisplayEnabled GL1DisplayEnableFunction(void)
{
    GL1ConfigureDisplayEnabled fn = (GL1ConfigureDisplayEnabled)
        dlsym(RTLD_DEFAULT, "CGConfigureDisplayEnabled");
    if (fn == NULL)
        fn = (GL1ConfigureDisplayEnabled)
            dlsym(RTLD_DEFAULT, "CGSConfigureDisplayEnabled");
    return fn;
}

static bool GL1SetBuiltinDisplays(vout_display_t *vd, bool enabled)
{
    vout_display_sys_t *sys = vd->sys;
    GL1ConfigureDisplayEnabled configure = GL1DisplayEnableFunction();
    if (configure == NULL)
        return false;

    CGDirectDisplayID displays[8];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(8, displays, &count) != kCGErrorSuccess)
        return false;

    CGDisplayConfigRef config = NULL;
    CGError error = CGBeginDisplayConfiguration(&config);
    unsigned changed = 0;
    if (enabled)
    {
        for (unsigned i = 0; error == kCGErrorSuccess &&
                             i < sys->stereo_disabled_display_count; ++i)
        {
            error = configure(config, sys->stereo_disabled_displays[i], true);
            if (error == kCGErrorSuccess)
                ++changed;
        }
    }
    else
    {
        sys->stereo_disabled_display_count = 0;
        for (uint32_t i = 0; error == kCGErrorSuccess && i < count; ++i)
        {
            if (!CGDisplayIsBuiltin(displays[i]) ||
                displays[i] == sys->stereo_display)
                continue;
            error = configure(config, displays[i], false);
            if (error == kCGErrorSuccess &&
                sys->stereo_disabled_display_count < 4)
                sys->stereo_disabled_displays[
                    sys->stereo_disabled_display_count++] = displays[i];
        }
        changed = sys->stereo_disabled_display_count;
    }
    if (error == kCGErrorSuccess && changed > 0)
        error = CGCompleteDisplayConfiguration(config,
                                                kCGConfigureForAppOnly);
    else if (config != NULL)
        CGCancelDisplayConfiguration(config);
    if (enabled || error != kCGErrorSuccess)
        sys->stereo_disabled_display_count = 0;
    return error == kCGErrorSuccess;
}

static vlc_object_t *GL1RootObject(vout_display_t *vd)
{
    vlc_object_t *root = VLC_OBJECT(vd);
    while (root->obj.parent != NULL)
        root = root->obj.parent;
    return root;
}

static bool GL1PrepareStereoDisplay(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    const bool stacked = vd->fmt.multiview_mode ==
                         MULTIVIEW_STEREO_FRAMEPACKED ||
                         (vd->fmt.i_sar_den != 0 &&
                          vd->fmt.i_sar_num == 2 * vd->fmt.i_sar_den &&
                          vd->fmt.i_visible_height == 2160);
    if (!stacked || var_InheritInteger(vd, "stereo3d-display-mode") == 2 ||
        floor(NSAppKitVersionNumber) >= 1138)
        return false;

    const unsigned eye_w = vd->fmt.i_visible_width;
    const unsigned eye_h = vd->fmt.i_visible_height / 2;
    const unsigned packed_h = eye_h == 1080 ? 2205 :
                              eye_h == 720 ? 1470 : 0;
    if (packed_h == 0)
        return false;
    double rate = vd->fmt.i_frame_rate_base != 0
                ? (double)vd->fmt.i_frame_rate / vd->fmt.i_frame_rate_base
                : 24.0;

    int configured = var_InheritInteger(vd, "macosx-vdev");
    if (configured > 0)
        sys->stereo_display = (CGDirectDisplayID)configured;
    else
    {
        CGDirectDisplayID displays[8];
        uint32_t count = 0;
        if (CGGetOnlineDisplayList(8, displays, &count) != kCGErrorSuccess)
            return false;
        for (uint32_t i = 0; i < count; ++i)
            if (!CGDisplayIsBuiltin(displays[i]))
            {
                sys->stereo_display = displays[i];
                break;
            }
    }
    if (sys->stereo_display == kCGNullDirectDisplay)
        return false;

    int saved = -1;
    int mode = GL1FindFramepackMode(sys->stereo_display, eye_w, packed_h,
                                    rate, &saved);
    if (mode < 0)
        return false;
    if (!GL1SetBuiltinDisplays(vd, false))
        return false;
    usleep(500000);
    if (GL1ConfigurePrivateMode(sys->stereo_display, mode) != kCGErrorSuccess)
    {
        GL1SetBuiltinDisplays(vd, true);
        return false;
    }
    sys->stereo_saved_private_mode = saved;
    sys->stereo_private_mode_changed = true;

    vlc_object_t *root = GL1RootObject(vd);
    var_Create(root, "stereo3d-fullscreen-display",
               VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    sys->stereo_saved_fullscreen_display =
        var_GetInteger(root, "stereo3d-fullscreen-display");
    sys->stereo_fullscreen_display_overridden = true;
    var_SetInteger(root, "stereo3d-fullscreen-display",
                   (int64_t)(uintptr_t)sys->stereo_display);
    msg_Info(vd, "GL1 switched legacy HDMI scanout to private mode %d: "
                 "%ux%u at %.3f Hz", mode, eye_w, packed_h, rate);
    return true;
}

static void GL1EnterStereoFullscreen(vout_display_t *vd)
{
    vlc_object_t *vout = vd->obj.parent;
    if (vout == NULL)
        return;
    if (!var_GetBool(vout, "fullscreen"))
    {
        vd->sys->stereo_fullscreen_forced = true;
        var_SetBool(vout, "fullscreen", true);
    }
    else
    {
        var_SetBool(vout, "fullscreen", false);
        var_SetBool(vout, "fullscreen", true);
    }
}

static void GL1RestoreStereoDisplay(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (!sys->stereo_private_mode_changed &&
        sys->stereo_disabled_display_count == 0)
        return;
    if (sys->stereo_fullscreen_display_overridden)
    {
        var_SetInteger(GL1RootObject(vd), "stereo3d-fullscreen-display",
                       sys->stereo_saved_fullscreen_display);
        sys->stereo_fullscreen_display_overridden = false;
    }
    if (sys->stereo_fullscreen_forced && vd->obj.parent != NULL)
        var_SetBool(vd->obj.parent, "fullscreen", false);
    if (sys->stereo_private_mode_changed)
    {
        GL1ConfigurePrivateMode(sys->stereo_display,
                                sys->stereo_saved_private_mode);
        sys->stereo_private_mode_changed = false;
    }
    GL1SetBuiltinDisplays(vd, true);
}

/*****************************************************************************
 * Fixed-pipeline renderer
 *****************************************************************************/

/* Context must be current. */
static bool OpenglCheckSupport (vout_display_t *vd, unsigned width, unsigned height)
{
    vout_display_sys_t *sys = vd->sys;
    const char *exts = (const char *) glGetString (GL_EXTENSIONS);
    if (exts == NULL)
        return false;

    /* "Apple Software Renderer" here means the driver could not handle
     * something in the pixel format and the whole context silently fell
     * back to the CPU — worth knowing on 1999-2003 GPUs. */
    const char *renderer = (const char *) glGetString (GL_RENDERER);
    msg_Dbg (vd, "GL renderer: %s | %s",
             renderer,
             (const char *) glGetString (GL_VERSION));
    sys->nvidia_320m = renderer != NULL &&
                       strstr(renderer, "NVIDIA GeForce 320M") != NULL;
    /* The planar (combiner) path depends on the exact fixed-function
     * feature set of these 1999-2003 GPUs: dump the facts once. */
    GLint units = 0;
    glGetIntegerv (GL_MAX_TEXTURE_UNITS, &units);
    msg_Dbg (vd, "GL texture units: %d", (int) units);
    /* Chantier S : la superposition des sous-titres sur la surface matérielle
     * exige un canal alpha DANS le framebuffer (l'effacement en alpha 0 est ce
     * qui rend la vue traversante). Sans lui, la vue reste noire opaque. */
    { GLint abits = 0;
      glGetIntegerv (GL_ALPHA_BITS, &abits);
      msg_Dbg (vd, "GL alpha bits: %d", (int) abits); }
    msg_Dbg (vd, "GL extensions: %s", exts);

    /* Planar mode requirements: MAD combiner stages + 3 texture units.
     * ARB_texture_env_combine is core since GL 1.3. */
    sys->planar = var_InheritBool (vd, "gl1-planar")
        && strstr (exts, "GL_ATI_texture_env_combine3") != NULL
        && (strstr (exts, "GL_ARB_texture_env_combine") != NULL
            || strncmp ((const char *) glGetString (GL_VERSION), "1.2", 3) > 0)
        && units >= 3;
    /* Planar used to redefine two ping-pong texture sets with glTexImage2D
     * on every frame. Under client storage that is the expensive form: each
     * redefinition makes the driver revalidate and remap the picture buffer.
     * Giving every pool buffer its own texture set instead makes the upload
     * a plain glTexSubImage2D on a mapping the driver already holds --
     * measured on the GMA 950 with 1080p: the vout thread went from 7.9 ms
     * to 5.2 ms per frame, and the draw call itself from 3.6 ms to 0.4 ms.
     * The cost is that every pool buffer stays pinned, so this is bounded
     * by the table (a bigger pool falls back to redefining slot 0). */
    sys->per_buffer_tex = sys->planar && var_InheritBool (vd, "gl1-per-buffer-tex");
    sys->fullscreen_cached = var_InheritBool (vd, "gl1-fullscreen-cached");

    /* A GPU with a programmable fragment stage does the whole colour matrix
     * in ONE pass. The combiner path needs three (one per RGB channel, with
     * glColorMask), which triples both the fill and the state changes -- and
     * the GMA 950 in a 2007 MacBook is exactly the case where that matters:
     * it cannot run GLSL (which is why this module is selected at all) but
     * ARB_fragment_program is native there. */
    sys->fragprog = sys->planar
        && var_InheritBool (vd, "gl1-fragprog")
        && strstr (exts, "GL_ARB_fragment_program") != NULL;
    if (sys->fragprog)
        msg_Dbg (vd, "using GPU planar YUV (ARB fragment program, 1 pass)");
    else if (sys->planar)
        msg_Dbg (vd, "using GPU planar YUV (combiner MAD, %d units)",
                 (int) units);
    else if (strstr (exts, "GL_APPLE_ycbcr_422") == NULL)
    {
        msg_Warn (vd, "GL_APPLE_ycbcr_422 not available");
        return false;
    }
    if (strstr (exts, "GL_EXT_texture_rectangle") == NULL
     && strstr (exts, "GL_ARB_texture_rectangle") == NULL
     && strstr (exts, "GL_NV_texture_rectangle") == NULL)
    {
        msg_Warn (vd, "rectangle textures not available");
        return false;
    }

    GLint max = 0;
    glGetIntegerv (GL_MAX_RECTANGLE_TEXTURE_SIZE_EXT, &max);
    if (max > 0 && ((GLint) width > max || (GLint) height > max))
    {
        msg_Warn (vd, "video %ux%u exceeds maximum texture size %d",
                  width, height, (int) max);
        return false;
    }
    return true;
}

/* (Re)creates the PLANAR ping-pong textures with the current storage
 * hint. Context must be current. Planar uploads fully redefine every
 * texture with glTexImage2D each frame, so freshly created textures are
 * filled again on the very next upload. (Packed mode does not use these:
 * it binds one persistent texture per pool buffer, see OpenglUpload.) */
static void SetupTextures (vout_display_sys_t *sys)
{
    for (int i = 0; i < 2; i++)
    {
        if (sys->textures[i][0] != 0)
            glDeleteTextures (3, sys->textures[i]);
        glGenTextures (3, sys->textures[i]);
        for (unsigned j = 0; j < 3; j++)
        {
            glBindTexture (GL_TEXTURE_RECTANGLE_EXT, sys->textures[i][j]);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE,
                             sys->storage_hint);
        }
    }
}

/* Packed mode: create the persistent texture for one pool buffer.
 * Context must be current; leaves the new texture bound. */
static GLuint PicTexNew (const vout_display_sys_t *sys)
{
    GLuint tex = 0;
    glGenTextures (1, &tex);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex);
    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE,
                     sys->storage_hint);
    return tex;
}

/* Planar only: pick the storage hint fitting the presentation mode and
 * recreate the textures when it flips. Windowed (composited by the
 * window server, no hard deadline) SHARED wins: zero-copy upload, the
 * AGP fetches happen at the compositor's leisure. On a fullscreen
 * borderless window the surface is page-flipped and beam-synced: with
 * SHARED the GPU misses its flip deadline waiting on AGP texture fetches
 * over the three passes and the vout thread spins in the flush (measured
 * ~93% CPU vs ~71% windowed AT THE SAME output size — the letterboxed
 * area is identical, only the presentation path differs). CACHED uploads
 * each plane once per frame by DMA and samples from VRAM: fullscreen
 * drops to ~74%, but the same hint costs ~+13 points windowed (the DMA
 * copy is a fixed price), hence the dynamic switch. */
static void UpdateStorageHint (vout_display_sys_t *sys)
{
    if (!sys->planar)
        return; /* packed: one pass, SHARED always wins */

    GLenum want = sys->on_fullscreen_window && sys->fullscreen_cached
                ? GL_STORAGE_CACHED_APPLE : GL_STORAGE_SHARED_APPLE;
    if (want == sys->storage_hint)
        return;
    sys->storage_hint = want;
    SetupTextures (sys);
    /* The per-buffer sets carry the hint they were created with: drop them
     * so they pick up the new one. */
    for (unsigned i = 0; i < sys->plane_tex_count; i++)
        glDeleteTextures (3, sys->plane_tex[i].tex);
    sys->plane_tex_count = 0;
    sys->draw_tex_set = NULL;
}

/* Context must be current. */
/* BT.601 limited-range YUV -> RGB, the very matrix the combiner passes below
 * spell out in halves and quarters (MTX_*). Written as three DP4s against
 * (Y,U,V,1) it is one pass, and it is also more faithful: the combiner path
 * has to clamp each intermediate to [0,1], this one does not.
 *
 * Context must be current. Leaves sys->fp = 0 (and sys->fragprog false) if
 * the driver rejects the program, so the caller falls back to combiners. */
static void SetupFragmentProgram (vout_display_sys_t *sys)
{
    static const char prog[] =
        "!!ARBfp1.0\n"
        "PARAM mr = { 1.1644,  0.0000,  1.5960, -0.8742 };\n"
        "PARAM mg = { 1.1644, -0.3918, -0.8130,  0.5320 };\n"
        "PARAM mb = { 1.1644,  2.0172,  0.0000, -1.0856 };\n"
        "TEMP yuv;\n"
        "TEX yuv.x, fragment.texcoord[0], texture[0], RECT;\n"
        "TEX yuv.y, fragment.texcoord[1], texture[1], RECT;\n"
        "TEX yuv.z, fragment.texcoord[2], texture[2], RECT;\n"
        "MOV yuv.w, 1.0;\n"
        "DP4 result.color.r, yuv, mr;\n"
        "DP4 result.color.g, yuv, mg;\n"
        "DP4 result.color.b, yuv, mb;\n"
        "MOV result.color.a, 1.0;\n"
        "END\n";

    glGenProgramsARB (1, &sys->fp);
    glBindProgramARB (GL_FRAGMENT_PROGRAM_ARB, sys->fp);
    glProgramStringARB (GL_FRAGMENT_PROGRAM_ARB, GL_PROGRAM_FORMAT_ASCII_ARB,
                        (GLsizei) (sizeof (prog) - 1), prog);

    GLint err = -1;
    glGetIntegerv (GL_PROGRAM_ERROR_POSITION_ARB, &err);
    if (err != -1)
    {
        glDeleteProgramsARB (1, &sys->fp);
        sys->fp = 0;
        sys->fragprog = false;
        return;
    }

}

static void OpenglInit (vout_display_sys_t *sys)
{
    glDisable (GL_BLEND);
    glDisable (GL_DEPTH_TEST);
    glDepthMask (GL_FALSE);
    glDisable (GL_CULL_FACE);
    glClearColor (0.0f, 0.0f, 0.0f, 1.0f);

    glMatrixMode (GL_PROJECTION);
    glLoadIdentity ();
    glMatrixMode (GL_MODELVIEW);
    glLoadIdentity ();

    glEnable (GL_TEXTURE_RECTANGLE_EXT);

    /* Tell the driver to source texture data straight from our buffers
     * (AGP DMA) instead of caching a copy; the copy was profiled at half
     * a G3 core for DVD-sized frames. */
    glPixelStorei (GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);

    /* Planar: SHARED until the first placement tells us the real
     * presentation mode (UpdateStorageHint may then flip to CACHED).
     * Packed: SHARED measured best on the tested GPUs; CACHED (Apple's
     * DVD Player choice) is one A/B option away. */
    if (sys->planar)
    {
        sys->storage_hint = GL_STORAGE_SHARED_APPLE;
        SetupTextures (sys);
    }
    else
        sys->storage_hint = sys->packed_cached ? GL_STORAGE_CACHED_APPLE
                                               : GL_STORAGE_SHARED_APPLE;

    glTexEnvf (GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    sys->tex_index = 0;

    if (sys->fragprog)
        SetupFragmentProgram (sys);
}

/* One MAD combiner stage on the active texture unit:
 * out = src0(op0) * k2 + { PREVIOUS | CONSTANT k1 | signed-add -0.5 },
 * then out *= scale. All args pre-clamped to [0,1] by design. */
static void CombinerStage (GLenum combine, GLenum src0, GLenum op0,
                           GLenum src1, const GLfloat k[4], GLfloat scale)
{
    glTexEnvf (GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_COMBINE);
    glTexEnvf (GL_TEXTURE_ENV, GL_COMBINE_RGB, combine);
    glTexEnvf (GL_TEXTURE_ENV, GL_SOURCE0_RGB, src0);
    glTexEnvf (GL_TEXTURE_ENV, GL_OPERAND0_RGB, op0);
    glTexEnvf (GL_TEXTURE_ENV, GL_SOURCE1_RGB, src1);
    glTexEnvf (GL_TEXTURE_ENV, GL_OPERAND1_RGB, GL_SRC_COLOR);
    glTexEnvf (GL_TEXTURE_ENV, GL_SOURCE2_RGB, GL_CONSTANT);
    glTexEnvf (GL_TEXTURE_ENV, GL_OPERAND2_RGB, GL_SRC_COLOR);
    glTexEnvfv (GL_TEXTURE_ENV, GL_TEXTURE_ENV_COLOR, k);
    glTexEnvf (GL_TEXTURE_ENV, GL_RGB_SCALE, scale);
    /* keep alpha trivial */
    glTexEnvf (GL_TEXTURE_ENV, GL_COMBINE_ALPHA, GL_REPLACE);
    glTexEnvf (GL_TEXTURE_ENV, GL_SOURCE0_ALPHA, GL_PREVIOUS);
    glTexEnvf (GL_TEXTURE_ENV, GL_OPERAND0_ALPHA, GL_SRC_ALPHA);
}

/* Upload Edge264's two reconstructed views without first copying them into a
 * 1920x2160 VLC picture.  Client storage is deliberately disabled here: the
 * DPB slots must be returned to Edge264 promptly, so the driver owns a cached
 * texture copy by the time glFinish returns.  This is one GPU read of 6.2 MB
 * instead of a CPU write followed by the same GPU read. */
static bool OpenglUploadDirectMVC (vout_display_sys_t *sys, picture_t *pic)
{
    if (!sys->fragprog ||
        !powervlc_mvc_context_is_direct(pic->context))
        return false;

    powervlc_mvc_piccontext *ctx =
        (powervlc_mvc_piccontext *)pic->context;
    if (ctx->uploaded)
    {
        /* Core redisplay (OSD/subtitle/paused refresh) of the same picture:
         * its DPB slots were already returned after the first owned upload.
         * Keep drawing the cached six textures; never fall through to the
         * deliberately incomplete stacked VLC pool buffer. */
        sys->direct_mvc = true;
        return true;
    }
    const bool persistent_upload = GL1UseNvidiaMvcPath(
        sys, "VLC_GL1_DIRECT_SUBIMAGE");
    const bool direct_per_buffer =
        getenv("VLC_GL1_DIRECT_PER_BUFFER") != NULL;
    const bool client_storage =
        getenv("VLC_GL1_DIRECT_CLIENT_STORAGE") != NULL ||
        direct_per_buffer;
    glPixelStorei (GL_UNPACK_CLIENT_STORAGE_APPLE,
                   client_storage ? GL_TRUE : GL_FALSE);
    for (unsigned eye = 0; eye < 2; ++eye)
    {
        if (ctx->packed_base && eye == ctx->base_eye)
            continue;
        bool direct_defined = false;
        if (direct_per_buffer)
        {
            unsigned i;
            for (i = 0; i < sys->direct_plane_tex_count[eye]; ++i)
                if (sys->direct_plane_tex[eye][i].pixels ==
                    ctx->planes[eye][0])
                    break;
            if (i < sys->direct_plane_tex_count[eye])
                direct_defined = true;
            else if (i < GL1_MAX_PLANAR_SETS)
            {
                glGenTextures(3, sys->direct_plane_tex[eye][i].tex);
                sys->direct_plane_tex[eye][i].pixels =
                    ctx->planes[eye][0];
                sys->direct_plane_tex_count[eye]++;
            }
            else
                i = 0;
            for (unsigned plane = 0; plane < 3; ++plane)
                sys->direct_mvc_tex[eye][plane] =
                    sys->direct_plane_tex[eye][i].tex[plane];
        }
        for (unsigned plane = 0; plane < 3; ++plane)
        {
            if (!direct_per_buffer &&
                sys->direct_mvc_tex[eye][plane] == 0)
            {
                glGenTextures (1, &sys->direct_mvc_tex[eye][plane]);
                glBindTexture (GL_TEXTURE_RECTANGLE_EXT,
                               sys->direct_mvc_tex[eye][plane]);
                glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S,
                                 GL_CLAMP_TO_EDGE);
                glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T,
                                 GL_CLAMP_TO_EDGE);
                glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER,
                                 GL_LINEAR);
                glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER,
                                 GL_LINEAR);
                glTexParameteri (GL_TEXTURE_RECTANGLE_EXT,
                                 GL_TEXTURE_STORAGE_HINT_APPLE,
                                 client_storage ? GL_STORAGE_SHARED_APPLE
                                                : GL_STORAGE_CACHED_APPLE);
                if (persistent_upload)
                    glTexImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, GL_LUMINANCE,
                                  ctx->widths[plane], ctx->heights[plane], 0,
                                  GL_LUMINANCE, GL_UNSIGNED_BYTE, NULL);
            }
            else
            {
                glBindTexture (GL_TEXTURE_RECTANGLE_EXT,
                               sys->direct_mvc_tex[eye][plane]);
                if (direct_per_buffer && !direct_defined)
                {
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT,
                                     GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT,
                                     GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT,
                                     GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT,
                                     GL_TEXTURE_MIN_FILTER, GL_LINEAR);
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT,
                                     GL_TEXTURE_STORAGE_HINT_APPLE,
                                     GL_STORAGE_SHARED_APPLE);
                }
            }
            glPixelStorei (GL_UNPACK_ROW_LENGTH,
                           ctx->strides[eye][plane]);
            /* A full definition is intentional. On the Snow Leopard 320M
             * driver, TexSubImage on a freshly allocated cached rectangle
             * remained backed by the now-returned Edge264 DPB slot and read
             * as zero. TexImage with client storage disabled makes an owned
             * driver copy before returning. */
            if (direct_per_buffer && direct_defined)
                glTexSubImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0,
                                 ctx->widths[plane], ctx->heights[plane],
                                 GL_LUMINANCE, GL_UNSIGNED_BYTE,
                                 ctx->planes[eye][plane]);
            else if (persistent_upload)
                glTexSubImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0,
                                 ctx->widths[plane], ctx->heights[plane],
                                 GL_LUMINANCE, GL_UNSIGNED_BYTE,
                                 ctx->planes[eye][plane]);
            else
                glTexImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, GL_LUMINANCE,
                              ctx->widths[plane], ctx->heights[plane], 0,
                              GL_LUMINANCE, GL_UNSIGNED_BYTE,
                              ctx->planes[eye][plane]);
        }
    }
    if (ctx->packed_base)
    {
#ifdef VLC_GL1_HAVE_IOSURFACE
        const bool iosurface_upload = GL1UseNvidiaMvcPath(
            sys, "VLC_GL1_DIRECT_IOSURFACE");
#else
        const bool iosurface_upload = false;
#endif
        if (sys->direct_mvc_base_tex == 0)
        {
            glGenTextures (1, &sys->direct_mvc_base_tex);
            glBindTexture (GL_TEXTURE_RECTANGLE_EXT,
                           sys->direct_mvc_base_tex);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S,
                             GL_CLAMP_TO_EDGE);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T,
                             GL_CLAMP_TO_EDGE);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER,
                             GL_LINEAR);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER,
                             GL_LINEAR);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT,
                             GL_TEXTURE_STORAGE_HINT_APPLE,
                             client_storage ? GL_STORAGE_SHARED_APPLE
                                            : GL_STORAGE_CACHED_APPLE);
            if (iosurface_upload) {
                /* Private RGB target for the cheap GPU-side IOSurface copy.
                 * Unlike the source binding, this texture no longer pins a
                 * VDA output surface while the drawable waits for VSync. */
                glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGB,
                             ctx->packed_base_width,
                             ctx->packed_base_height, 0, GL_RGB,
                             GL_UNSIGNED_BYTE, NULL);
                glGenFramebuffersEXT(1, &sys->direct_mvc_base_fbo);
                glBindFramebufferEXT(GL_FRAMEBUFFER_EXT,
                                     sys->direct_mvc_base_fbo);
                glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT,
                                          GL_COLOR_ATTACHMENT0_EXT,
                                          GL_TEXTURE_RECTANGLE_EXT,
                                          sys->direct_mvc_base_tex, 0);
                glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
            } else if (persistent_upload)
                glTexImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGB,
                              ctx->packed_base_width,
                              ctx->packed_base_height, 0,
                              GL_YCBCR_422_APPLE,
                              GL_UNSIGNED_SHORT_8_8_APPLE, NULL);
        }
        else
            glBindTexture (GL_TEXTURE_RECTANGLE_EXT,
                           sys->direct_mvc_base_tex);
        glPixelStorei (GL_UNPACK_ROW_LENGTH,
                       ctx->packed_base_stride / 2);
        if (persistent_upload && !iosurface_upload)
            glTexSubImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0,
                             ctx->packed_base_width,
                             ctx->packed_base_height,
                             GL_YCBCR_422_APPLE,
                             GL_UNSIGNED_SHORT_8_8_APPLE,
                             ctx->packed_base_pixels);
        else if (!iosurface_upload)
            glTexImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGB,
                          ctx->packed_base_width, ctx->packed_base_height, 0,
                          GL_YCBCR_422_APPLE, GL_UNSIGNED_SHORT_8_8_APPLE,
                          ctx->packed_base_pixels);
#ifdef VLC_GL1_HAVE_IOSURFACE
        else
        {
            IOSurfaceRef surface = CVPixelBufferGetIOSurface(
                (CVPixelBufferRef)ctx->packed_base_owner);
            GLuint source_tex = 0;
            if (surface != NULL) {
                glGenTextures(1, &source_tex);
                glBindTexture(GL_TEXTURE_RECTANGLE_EXT, source_tex);
                glTexParameteri(GL_TEXTURE_RECTANGLE_EXT,
                                GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                glTexParameteri(GL_TEXTURE_RECTANGLE_EXT,
                                GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                glTexParameteri(GL_TEXTURE_RECTANGLE_EXT,
                                GL_TEXTURE_MIN_FILTER, GL_NEAREST);
                glTexParameteri(GL_TEXTURE_RECTANGLE_EXT,
                                GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            }
            CGLError err = surface != NULL && source_tex != 0
                ? CGLTexImageIOSurface2D(CGLGetCurrentContext(),
                      GL_TEXTURE_RECTANGLE_EXT, GL_RGB,
                      ctx->packed_base_width, ctx->packed_base_height,
                      GL_YCBCR_422_APPLE, GL_UNSIGNED_SHORT_8_8_APPLE,
                      surface, 0)
                : kCGLBadDrawable;
            if (err != kCGLNoError)
            {
                static bool reported;
                if (!reported)
                {
                    fprintf(stderr, "GL1 IOSURFACE bind failed: %d\n",
                            (int)err);
                    reported = true;
                }
                if (source_tex != 0)
                    glDeleteTextures(1, &source_tex);
                glBindTexture(GL_TEXTURE_RECTANGLE_EXT,
                              sys->direct_mvc_base_tex);
                glTexSubImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0,
                                ctx->packed_base_width,
                                ctx->packed_base_height,
                                GL_YCBCR_422_APPLE,
                                GL_UNSIGNED_SHORT_8_8_APPLE,
                                ctx->packed_base_pixels);
            }
            else
            {
                glPushAttrib(GL_ALL_ATTRIB_BITS);
                glBindFramebufferEXT(GL_FRAMEBUFFER_EXT,
                                     sys->direct_mvc_base_fbo);
                glDrawBuffer(GL_COLOR_ATTACHMENT0_EXT);
                glViewport(0, 0, ctx->packed_base_width,
                           ctx->packed_base_height);
                glDisable(GL_FRAGMENT_PROGRAM_ARB);
                glDisable(GL_BLEND);
                glDisable(GL_DEPTH_TEST);
                glActiveTexture(GL_TEXTURE2);
                glDisable(GL_TEXTURE_RECTANGLE_EXT);
                glActiveTexture(GL_TEXTURE1);
                glDisable(GL_TEXTURE_RECTANGLE_EXT);
                glActiveTexture(GL_TEXTURE0);
                glEnable(GL_TEXTURE_RECTANGLE_EXT);
                glBindTexture(GL_TEXTURE_RECTANGLE_EXT, source_tex);
                glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
                glMatrixMode(GL_PROJECTION);
                glPushMatrix();
                glLoadIdentity();
                glMatrixMode(GL_MODELVIEW);
                glPushMatrix();
                glLoadIdentity();
                glColor4f(1.f, 1.f, 1.f, 1.f);
                const GLfloat width = ctx->packed_base_width;
                const GLfloat height = ctx->packed_base_height;
                glBegin(GL_QUADS);
                glTexCoord2f(0.f, 0.f);      glVertex2f(-1.f, -1.f);
                glTexCoord2f(width, 0.f);    glVertex2f( 1.f, -1.f);
                glTexCoord2f(width, height); glVertex2f( 1.f,  1.f);
                glTexCoord2f(0.f, height);   glVertex2f(-1.f,  1.f);
                glEnd();
                glPopMatrix();
                glMatrixMode(GL_PROJECTION);
                glPopMatrix();
                glMatrixMode(GL_MODELVIEW);
                glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
                glPopAttrib();
                /* Deleting the source texture retires its IOSurface storage
                 * after the already queued blit.  At that point OpenGL owns
                 * the pending use, so the client's CVPixelBuffer reference
                 * can be returned to VDA immediately. */
                glFlush();
                glDeleteTextures(1, &source_tex);
                if (ctx->packed_base_owner != NULL) {
                    ctx->release_packed_base(ctx->packed_base_owner);
                    ctx->packed_base_owner = NULL;
                    ctx->packed_base_pixels = NULL;
                }
                glBindTexture(GL_TEXTURE_RECTANGLE_EXT,
                              sys->direct_mvc_base_tex);
            }
        }
#endif
    }
    /* With the native async presenter an IOSurface must stay alive until the
     * page flip.  The copied UYVY path is different: after glFinish the
     * texture is owned by the driver, so retaining VDA's tiny surface pool
     * for the remaining VSync wait only starves the next base-view decode. */
    const bool presenter_render = GL1UseNvidiaMvcPath(
        sys, "VLC_GL1_PRESENTER_RENDER") && sys->presenter_started;
    const bool retained_iosurface = ctx->packed_base &&
        GL1UseNvidiaMvcPath(sys, "VLC_GL1_DIRECT_IOSURFACE");
    const bool deferred_presenter_release =
        presenter_render && (!ctx->packed_base || retained_iosurface);
    if (persistent_upload && !client_storage && !deferred_presenter_release)
        glFinish();
    /* The software MVC view has already been copied into driver-owned cached
     * textures (client storage is disabled).  Do not retain Edge264's DPB
     * slot merely because the same picture also carries a VDA IOSurface that
     * must survive until the page flip.  Their lifetimes are independent. */
    if (!client_storage && presenter_render && retained_iosurface &&
        !ctx->edge_returned) {
        ctx->return_frame(ctx->decoder, ctx->return_arg);
        ctx->edge_returned = true;
        ctx->return_arg = NULL;
    }
    glPixelStorei (GL_UNPACK_ROW_LENGTH, 0);
    glPixelStorei (GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);

    sys->direct_mvc_width = ctx->widths[0];
    sys->direct_mvc_height = ctx->heights[0];
    sys->direct_mvc = true;
    if (!client_storage && !deferred_presenter_release &&
        !ctx->edge_returned)
    {
        ctx->return_frame(ctx->decoder, ctx->return_arg);
        ctx->edge_returned = true;
        ctx->return_arg = NULL;
    }
    if (!client_storage && !deferred_presenter_release &&
        ctx->packed_base_owner != NULL)
    {
        ctx->release_packed_base(ctx->packed_base_owner);
        ctx->packed_base_owner = NULL;
        ctx->packed_base_pixels = NULL;
    }
    sys->direct_mvc_base_eye = ctx->base_eye;
    sys->direct_mvc_has_packed_base = ctx->packed_base;
    ctx->uploaded = true;
    return true;
}

/* Context must be current. Packed: dirty the persistent texture bound to
 * this pool buffer (glTexSubImage2D on an unchanged pointer = one queued
 * DMA; a glTexImage2D redefinition would make the driver revalidate and
 * remap the client memory every frame -- Apple's DVD Player ships the
 * TexImage-once/TexSubImage-per-frame recipe). Planar: ping-pong full
 * redefinitions as before. */
static void OpenglUpload (vout_display_sys_t *sys, picture_t *pic)
{
    if (OpenglUploadDirectMVC(sys, pic))
        return;
    sys->direct_mvc = false;
    UpdateStorageHint (sys);

    if (!sys->planar)
    {
        const plane_t *p = &pic->p[0];
        const uint8_t *data = p->p_pixels
            + sys->y_offset * (unsigned) p->i_pitch
            + sys->x_offset * (unsigned) p->i_pixel_pitch;

        unsigned i;
        for (i = 0; i < sys->pic_tex_count; i++)
            if (sys->pic_tex[i].pixels == p->p_pixels)
                break;

        glPixelStorei (GL_UNPACK_ROW_LENGTH, p->i_pitch / p->i_pixel_pitch);
        if (i < sys->pic_tex_count)
        {
            glBindTexture (GL_TEXTURE_RECTANGLE_EXT, sys->pic_tex[i].texture);
            glTexSubImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0,
                             sys->tex_width, sys->tex_height,
                             GL_YCBCR_422_APPLE, sys->packed_type,
                             data);
        }
        else
        {
            if (i == GL1_MAX_PIC_TEXTURES)
            {
                /* more distinct buffers than expected: recycle one
                 * (never happens with the stock 5-picture packed pool) */
                i = sys->pic_tex_evict;
                sys->pic_tex_evict = (sys->pic_tex_evict + 1)
                                   % GL1_MAX_PIC_TEXTURES;
                glBindTexture (GL_TEXTURE_RECTANGLE_EXT,
                               sys->pic_tex[i].texture);
            }
            else
            {
                sys->pic_tex[i].texture = PicTexNew (sys); /* leaves bound */
                sys->pic_tex_count++;
            }
            sys->pic_tex[i].pixels = p->p_pixels;
            glTexImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGB,
                          sys->tex_width, sys->tex_height, 0,
                          GL_YCBCR_422_APPLE, sys->packed_type,
                          data);
        }
        glPixelStorei (GL_UNPACK_ROW_LENGTH, 0);
        sys->draw_tex = sys->pic_tex[i].texture;
        sys->tex_index ^= 1;   /* held_pics slot, alternates as before */
        return;
    }

    unsigned next = sys->tex_index ^ 1;
    const GLuint *set = sys->textures[next];
    bool defined = false;

    if (sys->per_buffer_tex)
    {
        /* One texture set per picture buffer, keyed on the plane pointer:
         * the client-storage mapping the driver made for that buffer then
         * survives from frame to frame, and the upload is a plain
         * glTexSubImage2D that only queues a DMA. */
        unsigned i;
        for (i = 0; i < sys->plane_tex_count; i++)
            if (sys->plane_tex[i].pixels == pic->p[0].p_pixels)
                break;
        if (i < sys->plane_tex_count)
            defined = true;
        else
        {
            if (i == GL1_MAX_PLANAR_SETS)   /* pool bigger than the table */
                i = 0;
            else
            {
                glGenTextures (3, sys->plane_tex[i].tex);
                for (unsigned j = 0; j < 3; j++)
                {
                    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, sys->plane_tex[i].tex[j]);
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
                    glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_STORAGE_HINT_APPLE,
                                     sys->storage_hint);
                }
                sys->plane_tex_count++;
            }
            sys->plane_tex[i].pixels = pic->p[0].p_pixels;
        }
        set = sys->plane_tex[i].tex;
    }

    /* I420: three luminance planes, chroma at half resolution both ways */
    for (unsigned j = 0; j < 3; j++)
    {
        const plane_t *p = &pic->p[j];
        unsigned shift = j ? 1 : 0;
        const uint8_t *data = p->p_pixels
            + (sys->y_offset >> shift) * (unsigned) p->i_pitch
            + (sys->x_offset >> shift);
        unsigned w = (sys->tex_width  + shift) >> shift;
        unsigned h = (sys->tex_height + shift) >> shift;
        unsigned row_length = p->i_pitch;

        glBindTexture (GL_TEXTURE_RECTANGLE_EXT, set[j]);
        glPixelStorei (GL_UNPACK_ROW_LENGTH, row_length);
        /* Per-buffer: the pointer behind this texture never changes, so
         * define it once and only dirty it afterwards -- a redefinition
         * makes the driver revalidate and remap the client memory. */
        if (defined)
            glTexSubImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0, w, h,
                             GL_LUMINANCE, GL_UNSIGNED_BYTE, data);
        else
            glTexImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, GL_LUMINANCE,
                          w, h, 0, GL_LUMINANCE, GL_UNSIGNED_BYTE, data);
    }
    glPixelStorei (GL_UNPACK_ROW_LENGTH, 0);
    sys->tex_index = next;
    sys->draw_tex_set = set;
}

/* Context must be current. Uploads the rendered subpicture regions (RGBA)
 * into small plain textures -- WITHOUT client storage: the core frees the
 * region pictures right after display, the driver must own a copy. The
 * GPU then composites them over the video for free, replacing the core's
 * full-frame picture_Copy + CPU blend (~15% of a core when any OSD or
 * DVD subtitle is visible). */
static void UploadSubpictures (vout_display_t *vd, subpicture_t *subpic)
{
    vout_display_sys_t *sys = vd->sys;
    gl1_region_t last[GL1_MAX_REGIONS];
    int last_count = sys->region_count;

    memcpy (last, sys->regions, sizeof (last));
    sys->region_count = 0;

    if (subpic == NULL)
        goto cleanup;

    glPixelStorei (GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);

    int count = 0;
    for (subpicture_region_t *r = subpic->p_region; r != NULL; r = r->p_next)
    {
        if (count == GL1_MAX_REGIONS)
        {
            msg_Warn (vd, "more than %d subpicture regions, extra dropped",
                      GL1_MAX_REGIONS);
            break;
        }
        if (r->fmt.i_chroma != VLC_CODEC_RGBA) /* we only advertised RGBA */
            continue;

        gl1_region_t *glr = &sys->regions[count];
        glr->used_w = r->fmt.i_visible_width;
        glr->used_h = r->fmt.i_visible_height;
        glr->alpha  = (float)subpic->i_alpha * r->i_alpha / 255.0f / 255.0f;
        glr->left   =  2.0f * r->i_x / subpic->i_original_picture_width  - 1.0f;
        glr->top    = -2.0f * r->i_y / subpic->i_original_picture_height + 1.0f;
        glr->right  =  2.0f * (r->i_x + r->fmt.i_visible_width)
                            / subpic->i_original_picture_width  - 1.0f;
        glr->bottom = -2.0f * (r->i_y + r->fmt.i_visible_height)
                            / subpic->i_original_picture_height + 1.0f;

        /* recycle a texture of the exact same size from last frame */
        glr->texture = 0;
        for (int j = 0; j < last_count; j++)
            if (last[j].texture != 0
             && last[j].width  == (GLsizei) glr->used_w
             && last[j].height == (GLsizei) glr->used_h)
            {
                glr->texture = last[j].texture;
                last[j].texture = 0;
                break;
            }

        const plane_t *p = &r->p_picture->p[0];
        const uint8_t *data = p->p_pixels
            + r->fmt.i_y_offset * (unsigned) p->i_pitch
            + r->fmt.i_x_offset * (unsigned) p->i_pixel_pitch;
        glr->width  = glr->used_w;
        glr->height = glr->used_h;
        glPixelStorei (GL_UNPACK_ROW_LENGTH, p->i_pitch / p->i_pixel_pitch);
        if (glr->texture != 0)
        {
            glBindTexture (GL_TEXTURE_RECTANGLE_EXT, glr->texture);
            glTexSubImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, 0, 0,
                             glr->used_w, glr->used_h,
                             GL_RGBA, GL_UNSIGNED_BYTE, data);
        }
        else
        {
            glGenTextures (1, &glr->texture);
            glBindTexture (GL_TEXTURE_RECTANGLE_EXT, glr->texture);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
            glTexParameteri (GL_TEXTURE_RECTANGLE_EXT, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
            glTexImage2D (GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA,
                          glr->used_w, glr->used_h, 0,
                          GL_RGBA, GL_UNSIGNED_BYTE, data);
        }
        count++;
    }
    glPixelStorei (GL_UNPACK_ROW_LENGTH, 0);
    glPixelStorei (GL_UNPACK_CLIENT_STORAGE_APPLE, GL_TRUE);
    sys->region_count = count;

cleanup:
    for (int j = 0; j < last_count; j++)
        if (last[j].texture != 0)
            glDeleteTextures (1, &last[j].texture);
}

/* Draws one full quad with per-unit texture coordinates: full-resolution
 * for units sampling Y, half-resolution for units sampling chroma. */
/* Maps a corner of the DISPLAYED image, (dx, dy) in [0,1] with (0,0) at the
 * top left, onto the matching corner of the STORED texture.
 *
 * The fixed pipeline has no vertex shader to carry the orientation matrix, so
 * the rotation is baked into the texture coordinates instead. Same convention
 * as getOrientationTransformMatrix() in opengl/vout_helper.c -- that one
 * multiplies the texture coordinates by a matrix in the vertex shader, and the
 * eight cases below are that matrix worked out by hand. Keep the two in step.
 *
 * Without this every video carrying a rotation tag -- i.e. every clip filmed
 * on a phone held upright -- was drawn unrotated and simply squeezed into the
 * portrait rectangle vout_display_PlacePicture() had computed for it. */
static void OrientTexCorner (video_orientation_t orient,
                             float dx, float dy, float *tx, float *ty)
{
    switch (orient)
    {
        case ORIENT_ROTATED_90:      *tx = dy;        *ty = 1.f - dx;  break;
        case ORIENT_ROTATED_180:     *tx = 1.f - dx;  *ty = 1.f - dy;  break;
        case ORIENT_ROTATED_270:     *tx = 1.f - dy;  *ty = dx;        break;
        case ORIENT_HFLIPPED:        *tx = 1.f - dx;  *ty = dy;        break;
        case ORIENT_VFLIPPED:        *tx = dx;        *ty = 1.f - dy;  break;
        case ORIENT_TRANSPOSED:      *tx = dy;        *ty = dx;        break;
        case ORIENT_ANTI_TRANSPOSED: *tx = 1.f - dy;  *ty = 1.f - dx;  break;
        default:                     *tx = dx;        *ty = dy;        break;
    }
}

/* Recalcule le rectangle rogné à partir de `vd->source`, seul endroit que le
 * cœur met à jour quand l'utilisateur rogne (`VOUT_DISPLAY_CHANGE_SOURCE_CROP`,
 * cf. src/video_output/display.c). La texture, elle, ne porte que la zone
 * VISIBLE de l'image décodée, envoyée depuis (x_offset, y_offset) : on retire
 * donc cette origine pour retomber en coordonnées de texture.
 *
 * ⚠ Tout est arrondi au pixel PAIR : en 4:2:0 comme en 4:2:2 empaqueté, un
 * texel chroma couvre deux pixels luma, et un rectangle impair ferait échantil-
 * lonner la chroma à un demi-texel du luma — un liseré coloré sur les bords du
 * rognage. Le cœur ne garantit aucune parité (« Rogner » calcule des bandes à
 * partir d'un rapport quelconque).
 *
 * Fil du vout uniquement (Open puis Control), comme tex_width / orient. */
static void UpdateCrop (vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    const video_format_t *src = &vd->source;

    unsigned x = (src->i_x_offset > sys->x_offset)
               ? src->i_x_offset - sys->x_offset : 0;
    unsigned y = (src->i_y_offset > sys->y_offset)
               ? src->i_y_offset - sys->y_offset : 0;

    x &= ~1u;
    y &= ~1u;
    if (x >= sys->tex_width || y >= sys->tex_height)
        x = y = 0;                       /* incohérent : on montre tout */

    unsigned w = src->i_visible_width;
    unsigned h = src->i_visible_height;
    if (w == 0 || w > sys->tex_width - x)
        w = sys->tex_width - x;
    if (h == 0 || h > sys->tex_height - y)
        h = sys->tex_height - y;
    w &= ~1u;
    h &= ~1u;
    if (w == 0 || h == 0)
    {
        x = y = 0;
        w = sys->tex_width;
        h = sys->tex_height;
    }

    if (x != sys->crop_x || y != sys->crop_y
     || w != sys->crop_w || h != sys->crop_h)
        msg_Dbg (vd, "crop: %ux%u+%u+%u out of %ux%u",
                 w, h, x, y, sys->tex_width, sys->tex_height);

    sys->crop_x = x;
    sys->crop_y = y;
    sys->crop_w = w;
    sys->crop_h = h;
}

/* (x, y, w, h) = rectangle de la texture à faire tenir dans le quad, en texels
 * luma : c'est là que le rognage entre en jeu. Les unités chroma reçoivent le
 * même rectangle divisé par deux (4:2:0). */
static void PlanarQuad (float x, float y, float w, float h,
                        const bool chroma_unit[3],
                        video_orientation_t orient)
{
    float u[3], v[3];

    glBegin (GL_QUADS);
    for (int corner = 0; corner < 4; corner++)
    {
        /* picture row 0 is the top of the image */
        static const float vx[4] = { -1.0f, 1.0f, 1.0f, -1.0f };
        static const float vy[4] = {  1.0f, 1.0f, -1.0f, -1.0f };
        float dx = (corner == 1 || corner == 2) ? 1.0f : 0.0f;
        float dy = (corner >= 2) ? 1.0f : 0.0f;
        float fx, fy;

        OrientTexCorner (orient, dx, dy, &fx, &fy);

        /* La rotation s'applique DANS le rectangle rogné : `fx`/`fy` sont la
         * position normalisée du coin affiché à l'intérieur de la source
         * stockée, on la ramène ensuite dans le rectangle. Même découplage que
         * dans opengl/vout_helper.c, où la matrice d'orientation joue sur les
         * SOMMETS et les coordonnées de texture portent le seul rognage. */
        const float tx = x + fx * w;
        const float ty = y + fy * h;

        for (int t = 0; t < 3; t++)
        {
            u[t] = chroma_unit[t] ? tx * 0.5f : tx;
            v[t] = chroma_unit[t] ? ty * 0.5f : ty;
        }
        glMultiTexCoord2f (GL_TEXTURE0, u[0], v[0]);
        glMultiTexCoord2f (GL_TEXTURE1, u[1], v[1]);
        glMultiTexCoord2f (GL_TEXTURE2, u[2], v[2]);
        glVertex2f (vx[corner], vy[corner]);
    }
    glEnd ();
}

/* Draw one eye of an already stacked MVC picture into its HDMI frame-packing
 * active region. The 45-line (1080p) or 30-line (720p) blanking interval is
 * deliberately left untouched between the two calls. MVC output is
 * normalized to top/bottom, left eye first, before reaching the vout. */
static void PlanarFramepackSlice(float x, float y, float w, float h,
                                 float vertex_top, float vertex_bottom,
                                 const bool chroma_unit[3])
{
    static const float vx[4] = { -1.0f, 1.0f, 1.0f, -1.0f };
    const float vy[4] = { vertex_top, vertex_top,
                         vertex_bottom, vertex_bottom };

    glBegin(GL_QUADS);
    for (int corner = 0; corner < 4; ++corner)
    {
        const float dx = (corner == 1 || corner == 2) ? 1.0f : 0.0f;
        const float dy = corner >= 2 ? 1.0f : 0.0f;
        const float tx = x + dx * w;
        const float ty = y + dy * h;
        for (int unit = 0; unit < 3; ++unit)
        {
            const float scale = chroma_unit[unit] ? 0.5f : 1.0f;
            glMultiTexCoord2f(GL_TEXTURE0 + unit, tx * scale, ty * scale);
        }
        glVertex2f(vx[corner], vy[corner]);
    }
    glEnd();
}

static void PackedFramepackSlice(float x, float y, float w, float h,
                                 float vertex_top, float vertex_bottom)
{
    static const float vx[4] = { -1.0f, 1.0f, 1.0f, -1.0f };
    const float vy[4] = { vertex_top, vertex_top,
                         vertex_bottom, vertex_bottom };

    glBegin(GL_QUADS);
    for (int corner = 0; corner < 4; ++corner)
    {
        const float dx = (corner == 1 || corner == 2) ? 1.0f : 0.0f;
        const float dy = corner >= 2 ? 1.0f : 0.0f;
        glTexCoord2f(x + dx * w, y + dy * h);
        glVertex2f(vx[corner], vy[corner]);
    }
    glEnd();
}

static void PlanarGeometry(vout_display_sys_t *sys, float x, float y,
                           float w, float h, const bool chroma_unit[3],
                           video_orientation_t orient)
{
    if (!sys->hdmi_framepack || orient != ORIENT_NORMAL)
    {
        PlanarQuad(x, y, w, h, chroma_unit, orient);
        return;
    }

    const float raster = 2.0f * sys->framepack_eye_height +
                         sys->framepack_gap;
    const float inner = 1.0f - 2.0f * sys->framepack_eye_height / raster;
    PlanarFramepackSlice(x, y, w, h * 0.5f, 1.0f, inner, chroma_unit);
    PlanarFramepackSlice(x, y + h * 0.5f, w, h * 0.5f,
                         -inner, -1.0f, chroma_unit);
}

/* Context must be current. Composites the subpicture regions (DVD
 * SPU/menus, OSD) over the video just drawn: straight-alpha blend,
 * global alpha through GL_MODULATE on the primary color. */
static void DrawRegions (vout_display_sys_t *sys)
{
    if (sys->region_count <= 0)
        return;

    glEnable (GL_BLEND);
    glBlendFunc (GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glTexEnvf (GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_MODULATE);
    for (int i = 0; i < sys->region_count; i++)
    {
        const gl1_region_t *r = &sys->regions[i];
        if (r->texture == 0)
            continue;
        glColor4f (1.0f, 1.0f, 1.0f, r->alpha);
        glBindTexture (GL_TEXTURE_RECTANGLE_EXT, r->texture);
        glBegin (GL_QUADS);
            glTexCoord2f (0.0f, 0.0f);
            glVertex2f (r->left,  r->top);
            glTexCoord2f ((float) r->used_w, 0.0f);
            glVertex2f (r->right, r->top);
            glTexCoord2f ((float) r->used_w, (float) r->used_h);
            glVertex2f (r->right, r->bottom);
            glTexCoord2f (0.0f, (float) r->used_h);
            glVertex2f (r->left,  r->bottom);
        glEnd ();
    }
    glDisable (GL_BLEND);
    glTexEnvf (GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
    glColor4f (1.0f, 1.0f, 1.0f, 1.0f);
}

/* Context must be current. Draws the last uploaded frame. */
static void OpenglDraw (vout_display_sys_t *sys)
{
    /* Le rectangle rogné, en texels. Sans rognage il vaut la texture entière,
     * donc les coordonnées sont exactement celles d'avant. */
    const float cx = (float) sys->crop_x;
    const float cy = (float) sys->crop_y;
    const float cw = (float) sys->crop_w;
    const float ch = (float) sys->crop_h;
    const video_orientation_t orient = sys->orient;

    GL1_PROF_START (tc);
    glClear (GL_COLOR_BUFFER_BIT);
    GL1_PROF_ADD (clear, tc);

    if (!sys->planar)
    {
        if (sys->draw_tex != 0)
        {
            static const float vx[4] = { -1.0f, 1.0f, 1.0f, -1.0f };
            static const float vy[4] = {  1.0f, 1.0f, -1.0f, -1.0f };

            glBindTexture (GL_TEXTURE_RECTANGLE_EXT, sys->draw_tex);
            if (sys->hdmi_framepack && orient == ORIENT_NORMAL)
            {
                const float raster = 2.0f * sys->framepack_eye_height +
                                     sys->framepack_gap;
                const float inner = 1.0f - 2.0f *
                                    sys->framepack_eye_height / raster;
                PackedFramepackSlice(cx, cy, cw, ch * 0.5f,
                                     1.0f, inner);
                PackedFramepackSlice(cx, cy + ch * 0.5f, cw, ch * 0.5f,
                                     -inner, -1.0f);
            }
            else
            {
                glBegin (GL_QUADS);
                /* picture row 0 is the top of the image */
                for (int corner = 0; corner < 4; corner++)
                {
                    float dx = (corner == 1 || corner == 2) ? 1.0f : 0.0f;
                    float dy = (corner >= 2) ? 1.0f : 0.0f;
                    float fx, fy;

                    OrientTexCorner (orient, dx, dy, &fx, &fy);
                    glTexCoord2f (cx + fx * cw, cy + fy * ch);
                    glVertex2f (vx[corner], vy[corner]);
                }
                glEnd ();
            }
        }
        DrawRegions (sys);
        return;
    }

    if (sys->direct_mvc && sys->fragprog && sys->hdmi_framepack &&
        orient == ORIENT_NORMAL)
    {
        static const bool chromaYUV[3] = { false, true, true };
        const float raster = 2.0f * sys->framepack_eye_height +
                             sys->framepack_gap;
        const float inner = 1.0f - 2.0f *
                            sys->framepack_eye_height / raster;
        glEnable (GL_FRAGMENT_PROGRAM_ARB);
        glBindProgramARB (GL_FRAGMENT_PROGRAM_ARB, sys->fp);
        for (unsigned eye = 0; eye < 2; ++eye)
        {
            const float vertex_top = eye == 0 ? 1.0f : -inner;
            const float vertex_bottom = eye == 0 ? inner : -1.0f;
            if (sys->direct_mvc_has_packed_base &&
                eye == sys->direct_mvc_base_eye)
            {
                glDisable (GL_FRAGMENT_PROGRAM_ARB);
                glActiveTexture (GL_TEXTURE2);
                glDisable (GL_TEXTURE_RECTANGLE_EXT);
                glActiveTexture (GL_TEXTURE1);
                glDisable (GL_TEXTURE_RECTANGLE_EXT);
                glActiveTexture (GL_TEXTURE0);
                glBindTexture (GL_TEXTURE_RECTANGLE_EXT,
                               sys->direct_mvc_base_tex);
                PackedFramepackSlice (0.0f, 0.0f,
                                      (float)sys->direct_mvc_width,
                                      (float)sys->direct_mvc_height,
                                      vertex_top, vertex_bottom);
                glEnable (GL_FRAGMENT_PROGRAM_ARB);
                glBindProgramARB (GL_FRAGMENT_PROGRAM_ARB, sys->fp);
                continue;
            }
            for (unsigned plane = 0; plane < 3; ++plane)
            {
                glActiveTexture (GL_TEXTURE0 + plane);
                if (plane > 0)
                    glEnable (GL_TEXTURE_RECTANGLE_EXT);
                glBindTexture (GL_TEXTURE_RECTANGLE_EXT,
                               sys->direct_mvc_tex[eye][plane]);
            }
            PlanarFramepackSlice (0.0f, 0.0f,
                                  (float)sys->direct_mvc_width,
                                  (float)sys->direct_mvc_height,
                                  vertex_top, vertex_bottom,
                                  chromaYUV);
        }
        glDisable (GL_FRAGMENT_PROGRAM_ARB);
        glActiveTexture (GL_TEXTURE2);
        glDisable (GL_TEXTURE_RECTANGLE_EXT);
        glActiveTexture (GL_TEXTURE1);
        glDisable (GL_TEXTURE_RECTANGLE_EXT);
        glActiveTexture (GL_TEXTURE0);
        DrawRegions (sys);
        return;
    }

    const GLuint *tex = sys->per_buffer_tex ? sys->draw_tex_set
                                            : sys->textures[sys->tex_index];

    /* Une fermeture du décodeur ATI peut dépublier son contexte juste avant
     * que la dernière picture matérielle déjà ordonnancée atteigne display.
     * Cette picture n'a jamais été uploadée : en mode planar draw_tex_set est
     * donc NULL. Ne jamais déréférencer un jeu de textures qui n'existe pas ;
     * le noir déjà produit par glClear est le seul repli correct. */
    if (tex == NULL)
    {
        DrawRegions (sys);
        return;
    }

    /* One pass: the fragment program holds the whole colour matrix, so the
     * three planes are just three texture units read by a single quad. */
    if (sys->fragprog)
    {
        static const bool chromaYUV[3] = { false, true, true };

        glEnable (GL_FRAGMENT_PROGRAM_ARB);
        glBindProgramARB (GL_FRAGMENT_PROGRAM_ARB, sys->fp);
        for (int i = 0; i < 3; i++)
        {
            glActiveTexture (GL_TEXTURE0 + i);
            if (i > 0)
                glEnable (GL_TEXTURE_RECTANGLE_EXT);
            glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[i]);
        }
        PlanarGeometry (sys, cx, cy, cw, ch, chromaYUV, orient);
        glDisable (GL_FRAGMENT_PROGRAM_ARB);
        /* DrawRegions draws with the fixed pipeline on unit 0: leaving the
         * chroma units enabled would modulate the subtitles with them. */
        glActiveTexture (GL_TEXTURE2);
        glDisable (GL_TEXTURE_RECTANGLE_EXT);
        glActiveTexture (GL_TEXTURE1);
        glDisable (GL_TEXTURE_RECTANGLE_EXT);
        glActiveTexture (GL_TEXTURE0);

        DrawRegions (sys);
        return;
    }

    /* Three passes, one RGB channel each (glColorMask), three MAD
     * combiner stages per pass. Staged at half/quarter scale so every
     * in-gamut intermediate provably stays in [0,1]; the final stage
     * rescales by 2 or 4 (exact powers of two). Out-of-gamut YUV combos
     * clamp exactly like the CPU converter saturates. */
    static const GLfloat kR0[4] = { MTX_Y2,  MTX_Y2,  MTX_Y2,  1.0f };
    static const GLfloat kR1[4] = { MTX_RV2, MTX_RV2, MTX_RV2, 1.0f };
    static const GLfloat kR2[4] = { MTX_RK2, MTX_RK2, MTX_RK2, 1.0f };
    static const GLfloat kG0[4] = { MTX_GU2, MTX_GU2, MTX_GU2, 1.0f };
    static const GLfloat kG1[4] = { MTX_GV2, MTX_GV2, MTX_GV2, 1.0f };
    static const GLfloat kG2[4] = { MTX_Y2,  MTX_Y2,  MTX_Y2,  1.0f };
    static const GLfloat kB0[4] = { MTX_BU4, MTX_BU4, MTX_BU4, 1.0f };
    static const GLfloat kB1[4] = { MTX_Y4,  MTX_Y4,  MTX_Y4,  1.0f };
    static const GLfloat kB2[4] = { MTX_BK4, MTX_BK4, MTX_BK4, 1.0f };

    /* ---- R = 2 * (0.5822 Y + 0.7980 V - 0.4371) ---- */
    static const bool chromaR[3] = { false, true, false };  /* Y, V, - */
    glColorMask (GL_TRUE, GL_FALSE, GL_FALSE, GL_FALSE);
    glActiveTexture (GL_TEXTURE0);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[0]);
    CombinerStage (GL_MODULATE, GL_TEXTURE, GL_SRC_COLOR, GL_CONSTANT, kR0, 1.0f);
    glActiveTexture (GL_TEXTURE1);
    glEnable (GL_TEXTURE_RECTANGLE_EXT);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[2]);
    CombinerStage (GL_MODULATE_ADD_ATI, GL_TEXTURE, GL_SRC_COLOR, GL_PREVIOUS, kR1, 1.0f);
    glActiveTexture (GL_TEXTURE2);
    glEnable (GL_TEXTURE_RECTANGLE_EXT);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[0]);
    CombinerStage (GL_SUBTRACT, GL_PREVIOUS, GL_SRC_COLOR, GL_CONSTANT, kR2, 2.0f);
    PlanarGeometry (sys, cx, cy, cw, ch, chromaR, orient);

    /* ---- G = 2 * (0.5822 Y + [0.1959(1-U) + 0.1635 + 0.4065(1-V)] - 0.5) ---- */
    static const bool chromaG[3] = { true, true, false };   /* U, V, Y */
    glColor4f (MTX_GK, MTX_GK, MTX_GK, 1.0f);
    glColorMask (GL_FALSE, GL_TRUE, GL_FALSE, GL_FALSE);
    glActiveTexture (GL_TEXTURE0);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[1]);
    CombinerStage (GL_MODULATE_ADD_ATI, GL_TEXTURE, GL_ONE_MINUS_SRC_COLOR, GL_PRIMARY_COLOR, kG0, 1.0f);
    glActiveTexture (GL_TEXTURE1);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[2]);
    CombinerStage (GL_MODULATE_ADD_ATI, GL_TEXTURE, GL_ONE_MINUS_SRC_COLOR, GL_PREVIOUS, kG1, 1.0f);
    glActiveTexture (GL_TEXTURE2);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[0]);
    CombinerStage (GL_MODULATE_SIGNED_ADD_ATI, GL_TEXTURE, GL_SRC_COLOR, GL_PREVIOUS, kG2, 2.0f);
    PlanarGeometry (sys, cx, cy, cw, ch, chromaG, orient);

    /* ---- B = 4 * (0.2911 Y + 0.5043 U - 0.2714) ---- */
    static const bool chromaB[3] = { true, false, false };  /* U, Y, - */
    glColorMask (GL_FALSE, GL_FALSE, GL_TRUE, GL_FALSE);
    glActiveTexture (GL_TEXTURE0);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[1]);
    CombinerStage (GL_MODULATE, GL_TEXTURE, GL_SRC_COLOR, GL_CONSTANT, kB0, 1.0f);
    glActiveTexture (GL_TEXTURE1);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[0]);
    CombinerStage (GL_MODULATE_ADD_ATI, GL_TEXTURE, GL_SRC_COLOR, GL_PREVIOUS, kB1, 1.0f);
    glActiveTexture (GL_TEXTURE2);
    glBindTexture (GL_TEXTURE_RECTANGLE_EXT, tex[0]);
    CombinerStage (GL_SUBTRACT, GL_PREVIOUS, GL_SRC_COLOR, GL_CONSTANT, kB2, 4.0f);
    PlanarGeometry (sys, cx, cy, cw, ch, chromaB, orient);

    /* restore sane state for the next frame / other users of the ctx */
    glColorMask (GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
    glActiveTexture (GL_TEXTURE2);
    glDisable (GL_TEXTURE_RECTANGLE_EXT);
    glActiveTexture (GL_TEXTURE1);
    glDisable (GL_TEXTURE_RECTANGLE_EXT);
    glActiveTexture (GL_TEXTURE0);

    DrawRegions (sys);
}

/*****************************************************************************
 * Superposition sous-titres / OSD au-dessus de la surface matérielle
 *****************************************************************************
 * ⚠ MESURE (G3 Tiger / Radeon RV200) : deux surfaces CGS d'une MÊME fenêtre ne
 * se mélangent pas — la plus haute masque l'autre quelle que soit son alpha.
 * Rendre la vue GL transparente au-dessus de la surface du décodeur donne donc
 * une zone vidéo NOIRE, et la laisser dessous rend les sous-titres invisibles ;
 * une fenêtre non opaque n'y change rien. Les FENÊTRES, elles, se composent
 * avec alpha : l'incrustation passe par une fenêtre enfant transparente, cadrée
 * sur la boîte englobante des régions (donc minuscule pour un sous-titre) et
 * masquée dès qu'il n'y a plus rien à afficher.
 *****************************************************************************/

/* Signature de l'incrustation courante : sert à ne RECOMPOSER que lorsqu'elle
 * change vraiment. Deux pièges :
 *  - `subpicture->i_order` vaut 0 pour les subpictures des sub-sources (marq,
 *    OSD) : inutilisable seul, l'incrustation ne serait jamais reconstruite ;
 *  - le POINTEUR des pixels change à chaque image (le cœur re-rend le SPU d'un
 *    DVD en permanence) : l'inclure faisait recomposer 25 fois par seconde une
 *    image identique — ~288 Ko d'allocation et de mélange alpha par image, sur
 *    le thread vout, donc une saccade à chaque apparition de sous-titre.
 * On hache donc la géométrie ET un ÉCHANTILLON des pixels source (lecture
 * seule, une ligne sur 4 et un octet sur 16) : assez pour distinguer deux
 * sous-titres, sans rien allouer ni composer. 0 = aucune incrustation. */
/* 10.4 ou plus ? (Darwin 8 = 10.4). Les FENÊTRES ENFANTS n'affichent rien sous
 * 10.2 — et le même défaut se voit sur 10.3 : la superposition sous-titres/OSD
 * y restait invisible, alors que le panneau de contrôles plein écran, lui, est
 * une fenêtre INDÉPENDANTE placée par son niveau, et s'affiche parfaitement. */
static bool gl1_osx_at_least_10_4 (void)
{
    static int s_yes = -1;
    if (s_yes < 0) {
        char rel[32] = "";
        size_t len = sizeof (rel);
        s_yes = (sysctlbyname ("kern.osrelease", rel, &len, NULL, 0) == 0
                 && atoi (rel) >= 8);
    }
    return s_yes != 0;
}

static uint64_t SubpictureSignature (subpicture_t *subpic)
{
    if (subpic == NULL)
        return 0;
    uint64_t h = 1469598103934665603ull ^ (uint64_t) subpic->i_order;
    for (subpicture_region_t *r = subpic->p_region; r != NULL; r = r->p_next)
    {
        /* ⚠ L'ALPHA EST VOLONTAIREMENT ABSENT de la signature. Le cœur applique
         * un FONDU sur le dernier quart de chaque réplique
         * (vout_subpictures.c, `dst->i_alpha = fade_alpha * …`) : mesuré sur ce
         * DVD, l'alpha descend 255→249→241→…→4 à raison d'une valeur PAR IMAGE,
         * ce qui faisait recomposer et re-flusher l'incrustation trente fois de
         * suite, à 13-36 ms de thread principal la fois. Le fondu ne vaut pas
         * ce prix sur un G3 : l'incrustation garde l'alpha qu'elle avait à sa
         * composition et disparaît d'un coup, comme sur un lecteur de salon.
         * (Cela ne concerne QUE le chemin matériel : le rendu GL logiciel
         * continue de dessiner le subpicture tel que le cœur le fournit.) */
        const uint64_t v[] = {
            (uint64_t) r->i_x, (uint64_t) r->i_y,
            (uint64_t) r->fmt.i_visible_width, (uint64_t) r->fmt.i_visible_height,
        };
        unsigned i;
        for (i = 0; i < sizeof (v) / sizeof (v[0]); i++)
            h = (h ^ v[i]) * 1099511628211ull;

        if (r->p_picture == NULL)
            continue;
        const plane_t *pl = &r->p_picture->p[0];
        const uint8_t *src = pl->p_pixels
            + r->fmt.i_y_offset * (unsigned) pl->i_pitch
            + r->fmt.i_x_offset * (unsigned) pl->i_pixel_pitch;
        const unsigned w = r->fmt.i_visible_width * (unsigned) pl->i_pixel_pitch;
        /* ⚠ tourne à CHAQUE image : échantillonnage large (une ligne sur 16,
         * un octet sur 64). Un pas plus fin relit en pratique toutes les
         * lignes de cache de la région — ~288 Ko par image pour une bande de
         * sous-titres, soit du temps CPU pur perdu. La géométrie hachée
         * au-dessus discrimine déjà la plupart des changements. */
        unsigned y;
        for (y = 0; y < r->fmt.i_visible_height; y += 16) {
            const uint8_t *row = src + y * (unsigned) pl->i_pitch;
            unsigned x;
            for (x = 0; x < w; x += 64)
                h = (h ^ row[x]) * 1099511628211ull;
        }
    }
    return h ? h : 1;   /* jamais 0 : 0 signifie « rien à afficher » */
}

/* (v × a) / 255 sans division : la table de vérité est exacte sur [0,255]. */
#define MUL255(v, a) (((unsigned) (v) * (unsigned) (a) + 128u + \
                       (((unsigned) (v) * (unsigned) (a) + 128u) >> 8)) >> 8)

/* Thread VOUT. Compose les régions de sous-titres/OSD (RGBA fourni par le
 * cœur, alpha DROIT) dans une image RGBA PRÉMULTIPLIÉE cadrée sur leur boîte
 * englobante, exprimée en coordonnées VUE. Le thread principal n'a plus qu'à
 * la poser dans la fenêtre de superposition. subpic == NULL → effacement.
 * Échelle : les régions sont placées dans l'espace de l'image d'origine
 * (i_original_picture_*) ; on les projette sur le rectangle vidéo affiché
 * (`place`), au plus proche voisin — 1:1 dans le cas courant d'un DVD affiché
 * à sa taille. */
static void BuildSubsOverlay (vout_display_t *vd, subpicture_t *subpic)
{
    vout_display_sys_t *sys = vd->sys;
    /* DIAGNOSTIC : cette composition a lieu sur le THREAD VOUT, juste avant
     * l'affichage — si elle dépasse la durée d'une image (40 ms en PAL), elle
     * fait sauter une image à chaque apparition de sous-titre. */
    mtime_t t_build = mdate ();
    mtime_t t_alloc = 0, t_blit = 0;
    vout_display_place_t place;
    int vw, vh;

    @synchronized (sys->glView) {
        place = sys->place;
        vw = sys->view_w; vh = sys->view_h;
    }

    uint8_t *data = NULL;
    int ox = 0, oy = 0, ow = 0, oh = 0;   /* destination, coordonnées vue */
    int bx = 0, by = 0, bw = 0, bh = 0;   /* bitmap, coordonnées source */

    if (subpic != NULL && place.width > 0 && place.height > 0
     && subpic->i_original_picture_width > 0
     && subpic->i_original_picture_height > 0 && vw > 0 && vh > 0)
    {
        const double sx = (double) place.width  / subpic->i_original_picture_width;
        const double sy = (double) place.height / subpic->i_original_picture_height;

        /* Boîte englobante en coordonnées SOURCE (celles des régions). */
        int x0 = subpic->i_original_picture_width;
        int y0 = subpic->i_original_picture_height;
        int x1 = 0, y1 = 0;
        for (subpicture_region_t *r = subpic->p_region; r != NULL; r = r->p_next)
        {
            if (r->fmt.i_chroma != VLC_CODEC_RGBA)
                continue;
            if ((int) r->fmt.i_visible_width <= 0
             || (int) r->fmt.i_visible_height <= 0)
                continue;
            if (r->i_x < x0) x0 = r->i_x;
            if (r->i_y < y0) y0 = r->i_y;
            if (r->i_x + (int) r->fmt.i_visible_width  > x1)
                x1 = r->i_x + r->fmt.i_visible_width;
            if (r->i_y + (int) r->fmt.i_visible_height > y1)
                y1 = r->i_y + r->fmt.i_visible_height;
        }
        if (x0 < 0) x0 = 0;
        if (y0 < 0) y0 = 0;
        if (x1 > (int) subpic->i_original_picture_width)
            x1 = subpic->i_original_picture_width;
        if (y1 > (int) subpic->i_original_picture_height)
            y1 = subpic->i_original_picture_height;

        if (x1 > x0 && y1 > y0)
        {
            bx = x0; by = y0; bw = x1 - x0; bh = y1 - y0;
            data = calloc ((size_t) bw * bh, 4);
            t_alloc = mdate () - t_build;
            /* rectangle de DESTINATION (coordonnées vue), pour l'affichage */
            ox = place.x + (int) (bx * sx);
            oy = place.y + (int) (by * sy);
            ow = (int) (bw * sx + 0.5);
            oh = (int) (bh * sy + 0.5);
        }
    }

    if (data != NULL)
    {
        for (subpicture_region_t *r = subpic->p_region; r != NULL; r = r->p_next)
        {
            if (r->fmt.i_chroma != VLC_CODEC_RGBA)
                continue;
            int rx = r->i_x - bx;             /* tout est en coords SOURCE */
            int ry = r->i_y - by;
            int rw = r->fmt.i_visible_width;
            int rh = r->fmt.i_visible_height;
            if (rw <= 0 || rh <= 0)
                continue;

            const plane_t *pl = &r->p_picture->p[0];
            const uint8_t *src = pl->p_pixels
                + r->fmt.i_y_offset * (unsigned) pl->i_pitch
                + r->fmt.i_x_offset * (unsigned) pl->i_pixel_pitch;
            /* alpha global de la région, ramené sur 8 bits une fois pour toutes */
            const unsigned galpha8 =
                MUL255 ((unsigned) subpic->i_alpha, (unsigned) r->i_alpha);

            /* ⚠ CHEMIN CHAUD (thread vout, juste avant l'affichage) : le coût
             * est surtout de la BANDE PASSANTE (≈288 Ko lus + écrits pour une
             * bande 1000×72). Les pixels transparents — l'essentiel d'une bande
             * de sous-titres — sont sautés, le tampon sortant de calloc.
             * Les régions du cœur ne se recouvrent pas : une région postérieure
             * écrase simplement la précédente. */
            int y0 = (ry < 0) ? -ry : 0;
            int y1 = (ry + rh > bh) ? bh - ry : rh;
            int x0 = (rx < 0) ? -rx : 0;
            int x1 = (rx + rw > bw) ? bw - rx : rw;
            const size_t nbytes = (size_t) (x1 - x0) * 4;

            for (int y = y0; y < y1; y++)
            {
                const uint8_t *srow = src + (unsigned) y * (unsigned) pl->i_pitch
                                    + (unsigned) x0 * 4;
                uint8_t *drow = data + ((size_t) (ry + y) * bw + rx + x0) * 4;
                /* PRÉMULTIPLIÉ : c'est le seul format que CoreGraphics dessine
                 * par son chemin rapide. En lui passant de l'alpha droit, le
                 * -display de la fenêtre montait à 18–38 ms (mesuré) — un
                 * budget d'image entier, d'où la saccade. Le coût déplacé ici
                 * est sans commune mesure (~1 ms). */
                for (size_t i = 0; i < nbytes; i += 4) {
                    unsigned a = srow[i + 3];
                    if (galpha8 != 255)
                        a = MUL255 (a, galpha8);
                    if (a == 0)
                        continue;              /* déjà à zéro (calloc) */
                    /* ⚠ Sortie en ARGB PRÉMULTIPLIÉ (alpha en PREMIER), pas en
                     * RGBA : c'est le format 32 bits natif de Quartz sur PPC
                     * gros-boutiste. Lui donner du RGBA l'oblige à permuter
                     * chaque pixel à l'affichage. Réordonner ici ne coûte rien
                     * (on écrit déjà les quatre octets un par un). */
                    drow[i]     = (uint8_t) a;
                    drow[i + 1] = (uint8_t) MUL255 (srow[i],     a);
                    drow[i + 2] = (uint8_t) MUL255 (srow[i + 1], a);
                    drow[i + 3] = (uint8_t) MUL255 (srow[i + 2], a);
                }
            }
        }
    }

    t_blit = mdate () - t_build;
    /* Pas de seconde empreinte sur le RÉSULTAT : la signature d'entrée
     * (SubpictureSignature, qui échantillonne les pixels source) suffit déjà à
     * ne recomposer que sur changement réel. Repasser sur les ~288 Ko composés
     * coûtait ~1,5 ms de bande passante à chaque apparition, pour rien. */
    bool publish = true;
    @synchronized (sys->glView) {
        {
            free (sys->ovl_data);
            sys->ovl_data = data;
            sys->ovl_x = ox; sys->ovl_y = oy;
            sys->ovl_w = ow; sys->ovl_h = oh;
            sys->ovl_bw = bw; sys->ovl_bh = bh;
            sys->ovl_pending = true;
        }
    }
    if (!publish) {
        free (data);
        return;
    }
    msg_Dbg (vd, "incrustation : %dx%d à %d,%d (vue %dx%d, vidéo %dx%d+%d+%d) "
                 "composée en %d us (alloc %d, blit %d, bitmap %dx%d)",
             ow, oh, ox, oy, vw, vh,
             (int) place.width, (int) place.height, place.x, place.y,
             (int) (mdate () - t_build), (int) t_alloc,
             (int) (t_blit - t_alloc), bw, bh);
}

/* ★★ POURQUOI UN CGImageRef ET PAS UN NSBitmapImageRep :
 * CoreGraphics n'a qu'un seul chemin de composition rapide, celui de l'alpha
 * PRÉMULTIPLIÉ. Le seul initialiseur de NSBitmapImageRep capable de déclarer
 * des données prémultipliées alpha-en-tête est celui à `bitmapFormat:`, qui est
 * du 10.4 : sous 10.3 il fallait dé-prémultiplier le tampon (une boucle par
 * pixel) pour l'initialiseur d'origine, et le dessin repassait par le chemin
 * LENT — mesuré 3 à 30 ms de -drawRect: pour une bande 1023x74, à chaque
 * apparition de réplique, sur le thread principal. `CGImageCreate` accepte
 * `kCGImageAlphaPremultipliedFirst` depuis 10.0 : le chemin rapide redevient
 * accessible sur 10.3 ET 10.2, et la conversion par pixel disparaît. */
@interface VLCGL1SubsOverlayView : NSView
{
    CGImageRef        _img;
    uint8_t          *_repData;
    NSRect            _repRect;   /* où dessiner, en coordonnées de la vue */
@public
    int               _lastDrawUs; /* durée du dernier -drawRect: (diag) */
}
- (void)setImage:(CGImageRef)img data:(uint8_t *)data rect:(NSRect)rect;
@end

@implementation VLCGL1SubsOverlayView
/* ⚠ La vue devient PROPRIÉTAIRE du tampon : le CGImage ne copie pas les pixels,
 * il lit dedans à chaque affichage. Le laisser au thread vout (qui libère
 * l'ancienne image dès qu'il en compose une nouvelle) donnait un
 * use-after-free reproductible — crash dans CGSBlendRGBA8888toARGB8888 sous
 * -[NSWindow display]. Le tampon n'est libéré qu'ici, sur le thread principal,
 * quand l'image est remplacée. */
- (void)setImage:(CGImageRef)img data:(uint8_t *)data rect:(NSRect)rect
{
    if (_img != NULL)
        CGImageRelease (_img);
    free (_repData);
    _img = img;                       /* propriété transférée */
    _repData = data;
    _repRect = rect;
    [self setNeedsDisplay:YES];
}
- (void)dealloc
{
    if (_img != NULL)
        CGImageRelease (_img);
    free (_repData);
    [super dealloc];
}
- (BOOL)isOpaque      { return NO; }
- (BOOL)acceptsFirstMouse:(NSEvent *)e { VLC_UNUSED(e); return NO; }
- (void)drawRect:(NSRect)rect
{
    mtime_t t_draw = mdate ();
    VLC_UNUSED(rect);
    /* ⚠⚠ NE PAS « OPTIMISER » CE DESSIN. Trois variantes ont été essayées le
     * 2026-07-29 pour réduire la saccade — effacement conditionnel quand
     * l'incrustation recouvre la vue, composition en NSCompositeCopy au lieu du
     * mélange, et -displayIfNeeded au lieu de -display. Elles n'ont donné AUCUN
     * gain mesurable (la saccade est dans le flush au WindowServer, pas ici) et
     * l'une d'elles a FIGÉ LE GPU sur 10.4.11, quatre fois de suite, alors que
     * 10.2 et 10.3 tournaient avec le même binaire. On efface, on mélange
     * normalement, et on s'en tient là. */
    [[NSColor clearColor] set];
    NSRectFill ([self bounds]);
    if (_img != NULL) {
        CGContextRef cg = (CGContextRef) [[NSGraphicsContext currentContext]
                                             graphicsPort];
        if (cg != NULL) {
            /* Dessin 1:1 : ni rééchantillonnage ni anticrénelage à demander. */
            CGContextSetInterpolationQuality (cg, kCGInterpolationNone);
            CGContextSetShouldAntialias (cg, false);
            CGContextDrawImage (cg, CGRectMake (_repRect.origin.x,
                                                _repRect.origin.y,
                                                _repRect.size.width,
                                                _repRect.size.height), _img);
        }
    }
    _lastDrawUs = (int) (mdate () - t_draw);
}
@end

/*****************************************************************************
 * Vout display module
 *****************************************************************************/

static int Open (vlc_object_t *this)
{
    vout_display_t *vd = (vout_display_t *) this;
    vout_display_sys_t *sys = calloc (1, sizeof(*sys));

    if (!sys)
        return VLC_ENOMEM;

    vlc_mutex_init (&sys->presenter_lock);
    vlc_cond_init (&sys->presenter_cond);
    sys->presenter_inflight = -1;
    sys->presenter_queued = -1;

    gl1_prof_on = getenv ("VLC_GL1_PROF") != NULL;
    memset (&gl1_prof, 0, sizeof (gl1_prof));

    /* explicit pool: @autoreleasepool is clang-only, this file is MRC */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    {
        bool stereo_prepared = false;
        vd->sys = sys;
        sys->owner_vd = vd;
        sys->pool = NULL;
        sys->embed = NULL;
        sys->gl = NULL;

        /* U1 (décodage DVD accéléré ATI) — variables de GÉOMÉTRIE VIDÉO publiées
         * par le vout sur le bus libvlc (partagé avec le décodeur libmpeg2). Le
         * vout display est la source de vérité du placement écran (fenêtre + rect
         * letterboxé, SAR compris). wid = numéro de fenêtre CGS ; rect-x/y/w/h =
         * rectangle vidéo placé en coordonnées écran CGS (origine haut-gauche).
         * Renseignées depuis -reshape (thread principal). wid=0 = pas de fenêtre. */
        var_Create(vd->obj.libvlc, "dvddriver-vout-wid",    VLC_VAR_INTEGER);
        var_Create(vd->obj.libvlc, "dvddriver-vout-rect-x", VLC_VAR_INTEGER);
        var_Create(vd->obj.libvlc, "dvddriver-vout-rect-y", VLC_VAR_INTEGER);
        var_Create(vd->obj.libvlc, "dvddriver-vout-rect-w", VLC_VAR_INTEGER);
        var_Create(vd->obj.libvlc, "dvddriver-vout-rect-h", VLC_VAR_INTEGER);
        var_SetInteger(vd->obj.libvlc, "dvddriver-vout-wid", 0);
        /* U4 — bus de present HW (posé par le décodeur libmpeg2 ; lu ici à chaque
         * display). Créés côté vout aussi (var_Create est refcompté) pour que les
         * lectures ne préviennent pas quand le décodeur n'est pas MPEG-2 HW. */
        var_Create(vd->obj.libvlc, DVDDRIVER_VAR_CTX,     VLC_VAR_ADDRESS);
        var_Create(vd->obj.libvlc, DVDDRIVER_VAR_PRESENT, VLC_VAR_ADDRESS);
        var_Create(vd->obj.libvlc, DVDDRIVER_VAR_SP_HIDE, VLC_VAR_ADDRESS);
        var_Create(vd->obj.libvlc, DVDDRIVER_VAR_HOLD,    VLC_VAR_BOOL);
        /* Chantier S — mode sous-titres matériel : décidé par le décodeur, lu
         * ici au premier present (cf. hw_subs_mode). var_Create est refcompté :
         * la créer aussi côté vout évite un avertissement quand le décodeur
         * n'est pas MPEG-2 HW. */
        var_Create(vd->obj.libvlc, DVDDRIVER_VAR_SUBS,    VLC_VAR_BOOL);

        /* The legacy display transaction must happen before NSOpenGL creates
         * a drawable, otherwise Snow Leopard keeps both VDA and presentation
         * attached to the disappearing desktop framebuffer. */
        stereo_prepared = GL1PrepareStereoDisplay(vd);

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

        /* Get our main view */
        [VLCGL1VideoView performSelectorOnMainThread:@selector(getNewView:)
                                          withObject:[NSValue valueWithPointer:&sys->glView]
                                       waitUntilDone:YES];
        if (!sys->glView) {
            msg_Err(vd, "Initialization of open gl view failed");
            goto error;
        }

        [sys->glView setVoutDisplay:vd];


        /* We don't wait, that means that we'll have to be careful about releasing
         * container.
         * That's why we'll release on main thread in Close(). */
        if ([(id)container respondsToSelector:@selector(addVoutSubview:)])
            [(id)container performSelectorOnMainThread:@selector(addVoutSubview:)
                                            withObject:sys->glView
                                         waitUntilDone:NO];
        else if ([container isKindOfClass:[NSView class]]) {
            NSView *parentView = container;
            [parentView performSelectorOnMainThread:@selector(addSubview:)
                                         withObject:sys->glView
                                      waitUntilDone:NO];
            [sys->glView performSelectorOnMainThread:@selector(setFrameToBoundsOfView:)
                                          withObject:[NSValue valueWithPointer:parentView]
                                       waitUntilDone:NO];
        } else {
            msg_Err(vd, "Invalid drawable-nsobject object. drawable-nsobject must either be an NSView or comply to the @protocol VLCOpenGLVideoViewEmbedding.");
            goto error;
        }

        if (stereo_prepared)
        {
            GL1EnterStereoFullscreen(vd);
            usleep(500000);
        }

        /* GL context wrapper, same locking scheme as the macosx module */
        sys->gl = vlc_object_create(this, sizeof(*sys->gl));
        if (unlikely(!sys->gl))
            goto error;

        struct gl_sys *glsys = sys->gl->sys = malloc(sizeof(struct gl_sys));
        if (unlikely(!sys->gl->sys))
        {
            vlc_object_release(sys->gl);
            sys->gl = NULL;
            goto error;
        }
        glsys->locked_ctx = NULL;
        glsys->glView = sys->glView;
        glsys->display_sys = sys;
        sys->gl->makeCurrent = OpenglLock;
        sys->gl->releaseCurrent = OpenglUnlock;
        sys->gl->swap = OpenglSwap;
        sys->gl->getProcAddress = NULL;

        /* Negotiate the picture format: planar I420 rendered by the
         * combiners when the GPU can (GL_ATI_texture_env_combine3),
         * else packed 4:2:2 YCbCr textured by GL_APPLE_ycbcr_422. The
         * choice needs a current context, hence after MakeCurrent. */
        video_format_t fmt = vd->fmt;
        fmt.i_rmask = fmt.i_gmask = fmt.i_bmask = 0;

        sys->tex_width  = fmt.i_visible_width;
        sys->tex_height = fmt.i_visible_height;
        sys->x_offset   = fmt.i_x_offset;
        sys->y_offset   = fmt.i_y_offset;
        /* Un rognage peut être demandé AVANT l'ouverture (option `--crop`, ou
         * simplement mémorisé du média précédent) : le cœur l'a alors déjà
         * appliqué à `vd->source` et n'enverra aucun CHANGE_SOURCE_CROP. */
        UpdateCrop (vd);
        /* The placement rectangle is already computed post-rotation by
         * vout_display_PlacePicture(); the picture itself arrives unrotated,
         * so the display has to do the turning. */
        sys->orient     = fmt.orientation;

        if (vlc_gl_MakeCurrent(sys->gl) != VLC_SUCCESS)
        {
            msg_Err(vd, "Can't attach gl context");
            goto error;
        }
        if (!OpenglCheckSupport(vd, sys->tex_width, sys->tex_height))
        {
            vlc_gl_ReleaseCurrent(sys->gl);
            msg_Err(vd, "OpenGL 1.1 YCbCr texturing not supported here");
            goto error;
        }
        /* GL_APPLE_ycbcr_422 textures either byte order, so take whichever
         * packed 4:2:2 the decoder already produces -- the Crystal HD card
         * emits YUY2 and only YUY2. The planar path exists to spare the CPU an
         * I420 -> 4:2:2 interleave; choosing it for a 4:2:2 source would buy
         * nothing and impose the opposite conversion, one full-frame pass per
         * picture, which is enough on a GMA 950 to turn 1080p into a
         * slideshow. */
        sys->packed_type = GL_UNSIGNED_SHORT_8_8_APPLE;
        if (fmt.i_chroma == VLC_CODEC_YUYV || fmt.i_chroma == VLC_CODEC_UYVY)
        {
            if (sys->planar)
                msg_Dbg (vd, "source is already packed 4:2:2 (%4.4s): using "
                             "the packed path, no chroma conversion",
                         (const char *) &fmt.i_chroma);
            sys->planar = false;
            sys->per_buffer_tex = false;
            sys->fragprog = false;
            /* GL_UNSIGNED_SHORT_8_8_APPLE consumes YUYV bytes on big-endian
             * PowerPC and UYVY bytes on little-endian Intel. The previous
             * chroma-only test assumed little-endian and therefore displayed
             * a 2vuy webcam frame as YUYV on a G3/G4 (green/magenta image). */
            if (fmt.i_chroma != VLCGL1_CHROMA)
                sys->packed_type = GL_UNSIGNED_SHORT_8_8_REV_APPLE;
        }
        else
            fmt.i_chroma = sys->planar ? VLC_CODEC_I420 : VLCGL1_CHROMA;
        sys->packed_cached = var_InheritBool (vd, "gl1-packed-cached");
        OpenglInit(sys);

        if (sys->hdmi_framepack && GL1UseNvidiaMvcPath(
                sys, "VLC_GL1_EXCLUSIVE_FULLSCREEN")) {
            const CGError capture_error = CGDisplayCaptureWithOptions(
                sys->stereo_display, kCGCaptureNoFill);
            if (capture_error == kCGErrorSuccess) {
                CGLContextObj cgl = vlc_CGLContextOf(
                    [sys->glView openGLContext]);
                const CGOpenGLDisplayMask mask =
                    CGDisplayIDToOpenGLDisplayMask(sys->stereo_display);
                const CGLError fullscreen_error =
                    vlc_gl1_SetFullScreenOnDisplay(cgl, mask);
                if (fullscreen_error == kCGLNoError) {
                    sys->exclusive_capture = true;
                    msg_Info(vd,
                             "exclusive OpenGL scanout engaged on display %u",
                             (unsigned)sys->stereo_display);
                } else {
                    CGDisplayRelease(sys->stereo_display);
                    msg_Err(vd,
                            "exclusive OpenGL drawable failed: %s",
                            CGLErrorString(fullscreen_error));
                }
            } else {
                msg_Err(vd, "display capture failed: CoreGraphics error %d",
                        (int)capture_error);
            }
        }
        vlc_gl_ReleaseCurrent(sys->gl);

        if (sys->nvidia_320m && GL1UseNvidiaMvcPath(
                sys, "VLC_GL1_ASYNC_PRESENT")) {
            const bool native_display_link =
                GL1UseNvidiaMvcPath(sys, "VLC_GL1_DISPLAYLINK_NATIVE");
            if (native_display_link &&
                CVDisplayLinkCreateWithCGDisplay(sys->stereo_display,
                    &sys->presenter_display_link) == kCVReturnSuccess &&
                CVDisplayLinkSetOutputCallback(sys->presenter_display_link,
                    GL1DisplayLinkPresenter, sys) == kCVReturnSuccess &&
                CVDisplayLinkStart(sys->presenter_display_link) ==
                    kCVReturnSuccess) {
                sys->presenter_uses_display_link = true;
                if (getenv("VLC_GL1_SPLIT_PRESENTER") != NULL &&
                    vlc_clone(&sys->presenter_flip_thread,
                              GL1FlipPresenter, sys,
                              VLC_THREAD_PRIORITY_OUTPUT) == 0)
                    sys->presenter_flip_thread_started = true;
                if (vlc_clone(&sys->presenter_thread,
                              GL1AsyncPresenter, sys,
                              VLC_THREAD_PRIORITY_OUTPUT) == 0) {
                    sys->presenter_thread_started = true;
                    sys->presenter_started = true;
                    msg_Dbg(vd, "CoreVideo-clocked native NVIDIA presenter started");
                }
            } else if (getenv("VLC_GL1_DISPLAYLINK_PRESENT") != NULL &&
                CVDisplayLinkCreateWithCGDisplay != NULL &&
                CVDisplayLinkCreateWithCGDisplay(sys->stereo_display,
                    &sys->presenter_display_link) == kCVReturnSuccess &&
                CVDisplayLinkSetOutputCallback(sys->presenter_display_link,
                    GL1DisplayLinkPresenter, sys) == kCVReturnSuccess &&
                CVDisplayLinkStart(sys->presenter_display_link) ==
                    kCVReturnSuccess) {
                sys->presenter_started = true;
                sys->presenter_uses_display_link = true;
                msg_Dbg(vd, "CoreVideo display-link NVIDIA presenter started");
            } else if (vlc_clone (&sys->presenter_thread,
                                  GL1AsyncPresenter, sys,
                                  VLC_THREAD_PRIORITY_OUTPUT) == 0) {
                sys->presenter_thread_started = true;
                sys->presenter_started = true;
                msg_Dbg(vd, "asynchronous NVIDIA HDMI presenter started");
            }
        }

        msg_Dbg(vd, "fixed-pipeline OpenGL output: %ux%u %4.4s texture",
                sys->tex_width, sys->tex_height, (const char *) &fmt.i_chroma);

        /* OSD/SPU composited on the GPU as RGBA quads: without this the
         * core blends on the CPU into a full-frame copy of every picture
         * for as long as any subtitle/OSD is visible (~15% of a G3/G4
         * core on DVD-sized video). */
        static const vlc_fourcc_t gl1_subpicture_chromas[] = {
            VLC_CODEC_RGBA, 0
        };

        vout_display_info_t info = vd->info;
        info.has_pictures_invalid = false;
        info.subpicture_chromas = gl1_subpicture_chromas;

        const bool stacked_stereo =
            fmt.multiview_mode == MULTIVIEW_STEREO_FRAMEPACKED ||
            (fmt.i_sar_den != 0 && fmt.i_sar_num == 2 * fmt.i_sar_den &&
             fmt.i_visible_height == 2160);
        var_Create(vd, "vout-presentation-advance", VLC_VAR_INTEGER);
        var_SetInteger(vd, "vout-presentation-advance",
                       sys->nvidia_320m && stacked_stereo ? 60000 : 0);

        /* Setup vout_display_t once everything is fine */
        vd->fmt = fmt;
        vd->info = info;

        vd->pool = Pool;
        vd->prepare = PictureRender;
        vd->display = PictureDisplay;
        vd->control = Control;

        /* */
        vout_display_SendEventDisplaySize (vd, vd->fmt.i_visible_width, vd->fmt.i_visible_height);

        /* -release, not -drain: -[NSAutoreleasePool drain] only exists from
         * Mac OS X 10.4, and a missing selector is invisible to every
         * link-time check -- it raises NSInvalidArgumentException at runtime
         * instead. The two are the same thing outside a garbage-collected
         * environment, which this never is. */
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
        if (sys->presenter_started)
        {
            vlc_mutex_lock (&sys->presenter_lock);
            sys->presenter_stop = true;
            vlc_cond_broadcast (&sys->presenter_cond);
            vlc_mutex_unlock (&sys->presenter_lock);
            if (sys->presenter_uses_display_link) {
                CVDisplayLinkStop(sys->presenter_display_link);
                CVDisplayLinkRelease(sys->presenter_display_link);
                sys->presenter_display_link = NULL;
                sys->presenter_uses_display_link = false;
            }
            if (sys->presenter_thread_started) {
                vlc_join (sys->presenter_thread, NULL);
                sys->presenter_thread_started = false;
            }
            if (sys->presenter_flip_thread_started) {
                vlc_join(sys->presenter_flip_thread, NULL);
                sys->presenter_flip_thread_started = false;
            }
            sys->presenter_started = false;
        }
        if (sys->exclusive_capture) {
            NSOpenGLContext *context = [sys->glView openGLContext];
            CGLContextObj cgl = vlc_CGLContextOf(context);
            if (cgl != NULL && vlc_CGLLockContext(cgl) == kCGLNoError) {
                CGLSetCurrentContext(cgl);
                CGLClearDrawable(cgl);
                CGLSetCurrentContext(NULL);
                vlc_CGLUnlockContext(cgl);
            }
            CGDisplayRelease(sys->stereo_display);
            sys->exclusive_capture = false;
        }
        GL1RestoreStereoDisplay(vd);
        /* Rendre la fenêtre pleinement opaque AVANT de lâcher la vue : l'alpha
         * 0.99 n'est justifié que pendant le mode remplacement matériel (cf.
         * vlcHwEngagedRefresh) et la fenêtre, elle, survit au vout. */
        [sys->glView performSelectorOnMainThread:@selector(vlcHwRestoreOpaque)
                                      withObject:nil
                                   waitUntilDone:NO];

        /* Le vout ne pilote plus rien : -refreshSubsOverlay, qui lit vd->sys,
         * sort immédiatement à partir d'ici (vd == NULL sous @synchronized). */
        [sys->glView setVoutDisplay:nil];

        /* Chantier S — démonter la fenêtre de superposition (enfant de la
         * fenêtre vidéo, qui survit au vout).
         * ⚠ waitUntilDone:NO IMPÉRATIF : avec YES, une fermeture de vout pendant
         * que le thread principal est occupé attend INDÉFINIMENT — constaté sur
         * le G3, deux processus se disputant le GPU, VLC resté bloqué sur
         * « removing module macosx_gl1 ». L'ordre FIFO des messages du thread
         * principal suffit : ce démontage est mis en file AVANT le
         * -removeFromSuperview et le -release de la vue, plus bas. */
        [sys->glView performSelectorOnMainThread:@selector(tearDownSubsOverlay)
                                      withObject:nil
                                   waitUntilDone:NO];

        /* U1 : vout fermé → plus de fenêtre vidéo. Publier wid=0 (le décodeur HW
         * le lit à chaque display : 0 = ne rien présenter) puis détruire les vars. */
        var_SetInteger(vd->obj.libvlc, "dvddriver-vout-wid", 0);
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-wid");
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-rect-x");
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-rect-y");
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-rect-w");
        var_Destroy(vd->obj.libvlc, "dvddriver-vout-rect-h");
        var_Destroy(vd->obj.libvlc, DVDDRIVER_VAR_CTX);
        var_Destroy(vd->obj.libvlc, DVDDRIVER_VAR_PRESENT);
        var_Destroy(vd->obj.libvlc, DVDDRIVER_VAR_SP_HIDE);
        var_Destroy(vd->obj.libvlc, DVDDRIVER_VAR_HOLD);
        var_Destroy(vd->obj.libvlc, DVDDRIVER_VAR_SUBS);

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

        /* Incrustation non consommée : la fenêtre de superposition est déjà
         * démontée (et propriétaire de ce qu'elle affichait). */
        free (sys->ovl_data);
        sys->ovl_data = NULL;

        for (int i = 0; i < 2; i++)
            if (sys->held_pics[i])
                picture_Release (sys->held_pics[i]);

        if (sys->pool)
            picture_pool_Release (sys->pool);

        if (sys->gl != NULL)
        {
            bool have_gl_objects = sys->textures[0][0] != 0
                                || sys->direct_mvc_tex[0][0] != 0
                                || sys->direct_mvc_base_tex != 0
                                || sys->pic_tex_count > 0
                                || sys->region_count > 0
                                || sys->fp != 0;
            if (have_gl_objects
             && vlc_gl_MakeCurrent(sys->gl) == VLC_SUCCESS)
            {
                if (sys->textures[0][0] != 0)
                {
                    glDeleteTextures (3, sys->textures[0]);
                    glDeleteTextures (3, sys->textures[1]);
                }
                if (sys->direct_mvc_tex[0][0] != 0 &&
                    sys->direct_plane_tex_count[0] == 0 &&
                    sys->direct_plane_tex_count[1] == 0)
                {
                    glDeleteTextures (3, sys->direct_mvc_tex[0]);
                    glDeleteTextures (3, sys->direct_mvc_tex[1]);
                }
                if (sys->direct_mvc_base_tex != 0)
                    glDeleteTextures (1, &sys->direct_mvc_base_tex);
                if (sys->direct_mvc_base_fbo != 0)
                    glDeleteFramebuffersEXT(1,
                                            &sys->direct_mvc_base_fbo);
                if (sys->presenter_texture[0] != 0)
                    glDeleteTextures (2, sys->presenter_texture);
                if (sys->presenter_fbo[0] != 0)
                    glDeleteFramebuffersEXT(2, sys->presenter_fbo);
                for (unsigned i = 0; i < sys->pic_tex_count; i++)
                    glDeleteTextures (1, &sys->pic_tex[i].texture);
                for (int i = 0; i < sys->region_count; i++)
                    if (sys->regions[i].texture != 0)
                        glDeleteTextures (1, &sys->regions[i].texture);
                if (sys->fp != 0)
                    glDeleteProgramsARB (1, &sys->fp);
                for (unsigned i = 0; i < sys->plane_tex_count; i++)
                    glDeleteTextures (3, sys->plane_tex[i].tex);
                for (unsigned eye = 0; eye < 2; ++eye)
                    for (unsigned i = 0;
                         i < sys->direct_plane_tex_count[eye]; ++i)
                        glDeleteTextures(3,
                            sys->direct_plane_tex[eye][i].tex);
                vlc_gl_ReleaseCurrent(sys->gl);
            }
            assert(((struct gl_sys *)sys->gl->sys)->locked_ctx == NULL);
            free(sys->gl->sys);
            vlc_object_release(sys->gl);
        }

        [sys->glView release];

        if (sys->embed)
            vout_display_DeleteWindow (vd, sys->embed);
        vlc_cond_destroy (&sys->presenter_cond);
        vlc_mutex_destroy (&sys->presenter_lock);
        free (sys);
    }
    [pool release];
}

/*****************************************************************************
 * vout display callbacks
 *****************************************************************************/

/* Custom picture allocation: 64-byte aligned buffers and 32-byte multiple
 * pitches, so that the i420_yuy2 converter can use its dcbz fast path and
 * the AGP texture DMA reads aligned lines. (Stock pool pictures only
 * guarantee 16.) */
static void AlignedPicDestroy (picture_t *pic)
{
    free (pic->p_sys);
    free (pic);
}

static picture_t *AlignedPicNew (const video_format_t *fmt)
{
    /* 64-byte aligned planes and pitches: lets the PPC converter fast
     * paths use dcbz, and keeps GL client-storage DMA happy. */
    unsigned nplanes;
    unsigned pitch[3], lines[3];

    if (fmt->i_chroma == VLC_CODEC_I420)
    {
        nplanes = 3;
        pitch[0] = (fmt->i_width + 63) & ~63u;
        lines[0] = fmt->i_height;
        pitch[1] = pitch[2] = (((fmt->i_width + 1) / 2) + 63) & ~63u;
        lines[1] = lines[2] = (fmt->i_height + 1) / 2;
    }
    else
    {
        nplanes = 1;
        pitch[0] = ((fmt->i_width * 2) + 63) & ~63u;
        lines[0] = fmt->i_height;
    }

    size_t size = 63;
    for (unsigned i = 0; i < nplanes; i++)
        size += (size_t) pitch[i] * lines[i] + 63;

    /* Page-aligned, whole pages (Apple's DVD Player vm_allocates its
     * client-storage buffers the same way): the AGP DMA engine pins
     * memory per page, so buffers should not share pages with the heap. */
    size = (size + 4095) & ~(size_t) 4095;
    void *base = valloc (size);
    if (base == NULL)
        return NULL;

    picture_resource_t rsc = {
        .p_sys = base,
        .pf_destroy = AlignedPicDestroy,
    };
    uintptr_t ptr = (uintptr_t) base;
    for (unsigned i = 0; i < nplanes; i++)
    {
        ptr = (ptr + 63) & ~(uintptr_t)63;
        rsc.p[i].p_pixels = (uint8_t *) ptr;
        rsc.p[i].i_lines = lines[i];
        rsc.p[i].i_pitch = pitch[i];
        ptr += (size_t) pitch[i] * lines[i];
    }
    picture_t *pic = picture_NewFromResource (fmt, &rsc);
    if (pic == NULL)
        free (base);
    return pic;
}

static picture_pool_t *Pool (vout_display_t *vd, unsigned requested_count)
{
    vout_display_sys_t *sys = vd->sys;

    if (sys->pool)
        return sys->pool;

    /* +2: the last two displayed pictures stay referenced by the
     * client-storage textures.
     * Planar mode also shares this pool with the decoder (direct
     * rendering, no converter in between): on DVDs every cell change
     * makes es_out rebuffer, and draining the decoder fifo then needs a
     * batch of pictures at once (pts_delay, ~8 frames for dvdnav) while
     * the vout only trashes the outdated ones one by one. Without
     * headroom the decoder blocks in picture_pool_Wait, the demux
     * delivers its PCR late, and every cell change becomes a freeze
     * followed by a burst of late frames.
     * Do NOT be generous here though: every buffer cycling through the
     * client-storage textures must be mapped into the AGP aperture, and
     * past its limit gldFlush falls into io_connect_map_memory on every
     * single frame (profiled: 34 SD pictures = 44% of the vout thread
     * remapping, one late frame in three; 22 was fine). */
    unsigned count = requested_count + 2 + (sys->planar ? 4 : 0);

    /* Look-ahead decode cache (video-cache-mb). In direct rendering the
     * cache IS this pool's headroom, and decoder.c switches it off below a
     * 24-picture cushion (VIDEO_CACHE_DR_MIN_VIABLE) because a smaller one
     * only produces refill episodes. With the base +4 the headroom is 6, so
     * asking for a cache did nothing at all here -- and at 1080p it is
     * exactly what the machine needs: a Core 2 Duo decodes a 21 Mbit/s
     * Blu-ray remux at very nearly real time, so what breaks playback is
     * not the average but the variance, which is what a cushion absorbs.
     * Size the pool for the budget that was asked for, bounded by RAM.
     *
     * The sizing policy itself lives in vout_display_CacheExtraPictures();
     * pic_bytes is passed in because AlignedPicNew() pads planes to 64 bytes,
     * so the generic measurement would under-count. Only planar mode shares
     * this pool with the decoder -- in packed mode there is a converter in
     * between and the indirect path in vout_wrapper.c grows its own pool. */
    if (sys->planar)
    {
        size_t pic_bytes = 0;
        for (unsigned j = 0; j < 3; j++)
        {
            unsigned shift = j ? 1 : 0;
            pic_bytes += (size_t) ((((vd->fmt.i_width + shift) >> shift) + 63)
                                   & ~63u)
                       * (((size_t) vd->fmt.i_height + shift) >> shift);
        }

        unsigned want = vout_display_CacheExtraPictures (vd, pic_bytes);

        /* No AGP ceiling applied here on purpose. The client-storage
         * remapping cliff is real (profiled round 56: 34 buffers = 44% of the
         * vout thread remapping, one late frame in three; 22 was fine), but it
         * bites the PACKED path, which maps every buffer through
         * client-storage textures. This branch is planar, where the pool is
         * plain aligned memory uploaded per frame, and the deep cache was
         * measured to work. Capping to the AGP-safe range here would push
         * `want` under the viability floor and silently switch the cache back
         * off on exactly the machines it was written for. */
        /* A pool cannot exceed VLC_PICTURE_POOL_MAX: past it
         * picture_pool_New() returns NULL and Open() fails, i.e. NO video at
         * all. The budget above is expressed in bytes, so a small format walks
         * straight into that wall -- measured on a PowerBook G4 with a 320x180
         * clip: 281 MiB of budget over a ~98 KiB picture asked for 2999 extra,
         * 3021 in total, and the vout died with "video output creation
         * failed". The other two callers of vout_display_CacheExtraPictures()
         * clamp to VLCGL_PICTURE_MAX (128); this path deliberately goes deeper
         * (see the planar note above), so clamp it to the real ceiling
         * instead. */
        if (want > VLC_PICTURE_POOL_MAX - requested_count - 2)
            want = requested_count + 2 < VLC_PICTURE_POOL_MAX
                 ? VLC_PICTURE_POOL_MAX - requested_count - 2 : 0;

        if (want >= 26)
        {
            count = requested_count + 2 + want;
            msg_Dbg (vd, "look-ahead cache: %u extra pool pictures "
                         "(%u MiB, ~%.1f s)", want,
                     (unsigned) (((size_t) want * pic_bytes) >> 20),
                     vd->fmt.i_frame_rate_base > 0
                     ? (double) (want - 4) * vd->fmt.i_frame_rate_base
                       / vd->fmt.i_frame_rate : 0.0);
        }
    }

    int pool_max = var_InheritInteger (vd, "gl1-pool-max");
    if (pool_max == 0 && sys->nvidia_320m &&
        vd->fmt.i_visible_width == 1920 &&
        vd->fmt.i_visible_height == 2160)
    {
        /* 26 resident I420 texture sets crowd VDA's decode surfaces out of
         * the 320M's unified aperture. Eight and twelve starve the decoder
         * pool; 20 still recovers slowly. Repeated 23.976 MVC measurements
         * put 16 at the stable optimum. */
        pool_max = 16;
    }
    if (pool_max >= 3 && count > (unsigned) pool_max)
    {
        msg_Dbg (vd, "limiting picture pool from %u to %d buffers", count,
                 pool_max);
        count = pool_max;
    }


    picture_t *pics[count];
    unsigned i;
    for (i = 0; i < count; i++)
    {
        pics[i] = AlignedPicNew (&vd->fmt);
        if (pics[i] == NULL)
            break;
    }
    msg_Dbg (vd, "picture pool: %u requested, %u allocated%s", requested_count, i,
             sys->per_buffer_tex && i <= GL1_MAX_PLANAR_SETS
             ? ", one texture set each" : "");
    if (sys->per_buffer_tex && i > GL1_MAX_PLANAR_SETS)
    {
        msg_Dbg (vd, "pool larger than the %d texture sets available: "
                     "falling back to redefining one set per frame",
                 GL1_MAX_PLANAR_SETS);
        sys->per_buffer_tex = false;
    }
    if (i >= 3) /* enough to play */
        sys->pool = picture_pool_New (i, pics);
    if (!sys->pool && i > requested_count && requested_count >= 3)
    {
        /* Belt and braces behind the clamp above: losing the look-ahead cache
         * costs some smoothness, failing here costs the picture entirely. */
        msg_Warn (vd, "pool of %u pictures refused: retrying with %u, "
                      "without the look-ahead cache", i, requested_count);
        while (i > requested_count)
            picture_Release (pics[--i]);
        sys->pool = picture_pool_New (i, pics);
    }
    if (!sys->pool)
        while (i > 0)
            picture_Release (pics[--i]);
    return sys->pool;
}

static void PictureRender (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;

    /* The native-picture presenter owns upload and drawing so the vout can
     * keep decoding while the completed back buffer waits for HDMI blanking. */
    if (sys->presenter_started && sys->hdmi_framepack &&
        GL1UseNvidiaMvcPath(sys, "VLC_GL1_PRESENTER_RENDER") &&
        powervlc_mvc_context_is_direct(pic->context))
        return;

    /* U4 — picture décodée sur le GPU ATI (contexte présent + device HW actif) :
     * les plans logiciels sont vides (mode remplacement) → inutile de les uploader
     * en texture. Le present est fait par le GPU au display. On garde le chemin GL
     * pour les subpictures (sous-titres) sur le contexte GL. */
    if (pic->context != NULL
        && var_GetAddress(vd->obj.libvlc, DVDDRIVER_VAR_CTX) != NULL) {
        /* Sous-titres/OSD : composés dans une FENÊTRE de superposition (les
         * surfaces CGS d'une même fenêtre ne se mélangent pas — cf.
         * VLCGL1SubsOverlayView). On ne recompose que quand l'incrustation
         * CHANGE (i_order) : sinon le gain CPU du décodage matériel partirait
         * en recomposition à chaque image. */
        if (sys->hw_subs_mode) {
            uint64_t sig = SubpictureSignature (subpicture);
            if (sig != sys->ovl_sig) {
                sys->ovl_sig  = sig;
                BuildSubsOverlay (vd, subpicture);
            }
        }
        return;
    }

    if (vlc_gl_MakeCurrent(sys->gl) == VLC_SUCCESS)
    {
        GL1_PROF_START (t0);
        OpenglUpload (sys, pic);
        GL1_PROF_ADD (upload, t0);
        UploadSubpictures (vd, subpicture);
        vlc_gl_ReleaseCurrent(sys->gl);
    }
}

/* ★ Compteur de presents matériels pour la salve d'auto-clics réparateurs
 * (cf. vlcHwEngagedRefresh). Remis à zéro à chaque ré-engagement ET à chaque
 * changement du rect vidéo fenêtre-local : la bascule plein écran ⇄ fenêtré
 * de 10.3 REDIMENSIONNE la même fenêtre sans rouvrir le décodeur (même wid,
 * aucun ré-engagement) mais invalide l'état de composition réparé — le
 * changement de rect est le signal fiable des deux sens de bascule. */
static unsigned s_gl1_hw_pres = 0;
/* Fenêtre de recouvrement d'un pixel (cf. vlcHwEnsureCover) — thread principal
 * uniquement. Taille réglable pour l'A/B (candidats 45/46 du banc). */
static NSWindow *s_gl1_cover = nil;
static int s_gl1_cover_side = 1;

static void PictureDisplay (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;
    VLC_UNUSED(subpicture);

    /* U4 — present piloté par le VOUT : si la picture porte un contexte HW et que
     * le décodeur a publié son device + son callback de present, présenter la
     * surface GPU (au bon rect fenêtre-local, suit U1) et SAUTER le rendu GL. Le
     * pacing PTS du vout s'applique donc au present matériel → synchro A/V. */
    dvddriver_ctx *hw = var_GetAddress(vd->obj.libvlc, DVDDRIVER_VAR_CTX);
    dvddriver_present_cb present =
        (dvddriver_present_cb) var_GetAddress(vd->obj.libvlc, DVDDRIVER_VAR_PRESENT);
    /* Diagnostic. The old one-shot version fired on the very first picture,
     * which is always BEFORE the decoder has opened the hardware -- the
     * decision is taken a few pictures in, once the progressive/interlaced
     * probe has run -- so it only ever reported "not engaged" and said
     * nothing about the state that matters. Report the engagement itself,
     * and repeat the reason every 100 pictures while it does not happen. */
    {
        static bool s_engaged = false;
        static unsigned s_not_engaged = 0;
        bool now = (hw != NULL && present != NULL && pic->context != NULL);

        /* ★★ CORRECTIF DU SCINTILLEMENT 10.3 : poser l'alpha < 1 sur la
         * fenêtre hôte dès les premiers presents matériels, et le re-poser
         * après tout changement de fenêtre/géométrie (compteur remis à zéro).
         * Trois tirs suffisent et coûtent trois appels AppKit par engagement.
         * /tmp/hw_noautoclick désarme la salve (observation de l'état cassé
         * pendant les essais du banc). */
        static int s_noauto = -2;
        if (s_noauto == -2) {
            FILE *g = fopen("/tmp/hw_noautoclick", "r");
            s_noauto = (g != NULL);
            if (g) fclose(g);
        }
        if (now && !s_noauto && ++s_gl1_hw_pres <= 50) {
            if (s_gl1_hw_pres == 2 || s_gl1_hw_pres == 25)
                [sys->glView
                    performSelectorOnMainThread:@selector(vlcHwCoverAndRefresh)
                                     withObject:nil waitUntilDone:NO];
            else if (s_gl1_hw_pres == 50)
                /* re-poser (la géométrie peut avoir bougé entre-temps) */
                [sys->glView
                    performSelectorOnMainThread:@selector(vlcHwCoverAndRefresh)
                                     withObject:nil waitUntilDone:NO];
        }
        /* Fin du mode remplacement : garantir une fenêtre opaque. */
        if (!now && s_engaged)
            [sys->glView performSelectorOnMainThread:@selector(vlcHwRestoreOpaque)
                                          withObject:nil
                                       waitUntilDone:NO];

        /* ★ BANC D'ESSAI : /tmp/hw_cmd = numéro de remède à exécuter une fois
         * (cf. vlcTryRemedy:). Lu toutes les 25 images, puis effacé. */
        static unsigned s_cmd_tick = 0;
        if (now && (++s_cmd_tick % 25) == 0) {
            FILE *f = fopen("/tmp/hw_cmd", "r");
            if (f != NULL) {
                int cmd = 0;
                int got = fscanf(f, "%d", &cmd);
                fclose(f);
                unlink("/tmp/hw_cmd");
                if (got == 1)
                    [sys->glView
                        performSelectorOnMainThread:@selector(vlcTryRemedy:)
                                         withObject:[NSNumber numberWithInt:cmd]
                                      waitUntilDone:NO];
            }
        }
        if (now && !s_engaged) {
            s_engaged = true;
            msg_Dbg(vd, "present matériel engagé");
            /* ★ réarmer la salve d'auto-clics à CHAQUE ré-engagement (toute
             * réouverture du décodeur repart d'un état de composition cassé). */
            s_gl1_hw_pres = 0;
        } else if (!now) {
            if ((s_not_engaged++ % 100) == 0)
                msg_Dbg(vd, "present matériel non engagé (%u) : hw=%p "
                        "present=%p context=%p", s_not_engaged,
                        (void *)hw, (void *)present, (void *)pic->context);
            s_engaged = false;
        }
    }
    /* ★ La fenêtre qui héberge la vidéo peut être RETIRÉE par l'interface
     * (bouton « liste de lecture » : elle abrite la vue vidéo). Retirer la
     * fenêtre ne suffit PAS à cacher la surface — le WindowServer continue de
     * la composer, et la vidéo restait affichée par-dessus la liste. On
     * escamote donc la surface elle-même, et on la rend au retour. */
    if (hw != NULL) {
        static bool s_surf_hidden = false;
        /* ⚠ Tester la FENÊTRE ne suffit que de 10.4 vers le haut, où le bouton
         * retire la fenêtre hôte qui abrite la vue. En dessous, cette fenêtre
         * hôte n'existe pas (openVideoHostWindow est gaté à 10.4+) : la vue
         * vidéo reste dans la fenêtre principale, que l'interface se contente
         * de MASQUER. La fenêtre demeurait donc « visible », la surface n'était
         * jamais escamotée, et sur 10.3 le bouton « liste de lecture » n'avait
         * aucun effet visible pendant un DVD accéléré — l'image GPU recouvrait
         * la liste. (10.2 y échappait par accident : sans setHidden:, le helper
         * de l'interface DÉTACHE la vue, et [glView window] tombe à nil.)
         * On teste donc aussi la vue, ancêtres compris — le bouton masque
         * `videoView`, pas la vue GL elle-même. */
        NSView *glv = sys->glView;
        NSWindow *glwin = [glv window];
        bool view_hidden = false;
        if (glv == nil)
            view_hidden = true;
        else if ([glv respondsToSelector:@selector(isHiddenOrHasHiddenAncestor)])
            view_hidden = [glv isHiddenOrHasHiddenAncestor];
        else if ([glv respondsToSelector:@selector(isHidden)])
            view_hidden = [glv isHidden];
        bool win_visible = (glwin != nil && [glwin isVisible] && !view_hidden);
        if (win_visible == s_surf_hidden) {
            dvddriver_hide_cb hide = (dvddriver_hide_cb)
                var_GetAddress(vd->obj.libvlc, DVDDRIVER_VAR_HIDE);
            msg_Dbg(vd, "escamotage de la surface : visible=%d "
                    "vue masquée=%d", (int)win_visible, (int)view_hidden);
            if (hide != NULL) {
                hide(hw, !win_visible);
                s_surf_hidden = !win_visible;
                /* ★ CGSOrderSurface RÉUSSIT (rc=0) et ne change RIEN à l'écran
                 * tant que le serveur n'a pas recalculé la visibilité des
                 * surfaces de la fenêtre : en régime d'affichage direct, il
                 * continue d'envoyer la surface au framebuffer, et comme on
                 * vient d'arrêter les presents, les derniers pixels restent
                 * gravés — l'image se fige au lieu de disparaître. C'est le
                 * même recalcul que réclame le correctif anti-scintillement
                 * (cf. vlcHwCoverAndRefresh), et seul -[NSWindow orderWindow:]
                 * le déclenche. */
                [sys->glView
                    performSelectorOnMainThread:@selector(vlcHwRecomputeSurfaces)
                                     withObject:nil waitUntilDone:NO];
            }
        }
        if (!win_visible) {
            picture_Release(pic);
            if (subpicture)
                subpicture_Delete(subpicture);
            return;
        }
    }

    if (hw != NULL && present != NULL && pic->context != NULL) {
        /* Rectangle FENÊTRE-local (pas `place`, qui est en coords VUE : l'utiliser
         * décalait la surface vers le haut de la hauteur de la barre de titre et
         * lui faisait recouvrir la chrome de la fenêtre). */
        int hx, hy, hw_, hh, hwid;
        bool ok, need_clear;
        @synchronized (sys->glView) {
            ok = sys->hw_place_valid;
            hx = sys->hw_x; hy = sys->hw_y; hw_ = sys->hw_w; hh = sys->hw_h;
            hwid = sys->hw_wid;
            need_clear = sys->hw_need_clear;
            sys->hw_need_clear = false;
        }
        if (!ok) {
            vout_display_place_t place;
            @synchronized (sys->glView) { place = sys->place; }
            hx = place.x; hy = place.y; hw_ = place.width; hh = place.height;
        }
        /* La surface matérielle ne couvre QUE le rectangle vidéo ; les marges du
         * letterbox laissent voir le contenu périmé du framebuffer GL (le fond
         * bleu du démarrage, resté visible à gauche et à droite). En mode
         * remplacement on ne dessine plus jamais en GL, donc rien ne l'efface :
         * on le met à noir une fois, à chaque changement de géométrie. Les DEUX
         * tampons sont effacés (double buffering), d'où les deux swaps. */
        if (need_clear && vlc_gl_MakeCurrent(sys->gl) == VLC_SUCCESS) {
            for (int i = 0; i < 2; i++) {
                glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
                glClear(GL_COLOR_BUFFER_BIT);
                vlc_gl_Swap(sys->gl);
            }
            vlc_gl_ReleaseCurrent(sys->gl);
        }
        /* DIAGNOSTIC : rectangle réellement passé au present matériel, tracé à
         * chaque changement (il pilote CGSSetSurfaceBounds). */
        {
            static int lx = -12345, ly, lw, lh;
            if (hx != lx || hy != ly || hw_ != lw || hh != lh) {
                /* ★ géométrie vidéo changée (bascule plein écran ⇄ fenêtré,
                 * redimensionnement) : l'état de composition réparé ne
                 * survit pas à la reconfiguration → réarmer la salve
                 * d'auto-clics (sauf tout premier passage, lx sentinelle). */
                if (lx != -12345)
                    s_gl1_hw_pres = 0;
                lx = hx; ly = hy; lw = hw_; lh = hh;
                msg_Dbg (vd, "present matériel : rect fenêtre-local %d,%d %dx%d "
                             "(valide=%d, source %ux%u)", hx, hy, hw_, hh,
                         (int) ok, vd->source.i_visible_width,
                         vd->source.i_visible_height);
            }
        }
        if (present(hw, pic->context, hwid, hx, hy, hw_, hh)) {
            /* Le décodeur a publié sa décision (option mpeg2-hwaccel-subs + chemin
             * d'affichage retenu) au moment d'ouvrir le contexte HW, donc avant ce
             * premier present : c'est ici, et pas à l'Open du vout, qu'elle est
             * lisible. Une seule fois — le mode ne change pas en cours de flux. */
            if (!sys->hw_subs_known) {
                sys->hw_subs_known = true;
                sys->hw_subs_mode  = var_GetBool(vd->obj.libvlc, DVDDRIVER_VAR_SUBS);
                msg_Dbg(vd, "present matériel : sous-titres/OSD superposés %s",
                        sys->hw_subs_mode ? "OUI" : "non");
            }
            /* Publier l'incrustation (fenêtre de superposition) quand elle a
             * changé — le rendu lui-même a lieu sur le thread principal. */
            if (sys->hw_subs_mode && sys->ovl_pending)
                [sys->glView performSelectorOnMainThread:@selector(refreshSubsOverlay)
                                              withObject:nil
                                           waitUntilDone:NO];
            picture_Release (pic);
            sys->has_first_frame = true;
            if (subpicture)
                subpicture_Delete(subpicture);
            return;
        }
    }

    /* ★ RÉOUVERTURE EN COURS (bascule plein écran ⇄ fenêtré) : le décodeur a
     * fermé son contexte matériel et le rouvrira sur la nouvelle fenêtre à la
     * prochaine image I. Les pictures qui traversent le vout entre-temps ne sont
     * PAS affichables : en mode remplacement les plans logiciels des références
     * n'ont jamais été reconstruits, les dessiner produit l'écran vert/blanc et
     * les glitchs constatés à chaque bascule. On ne dessine rien du tout — la
     * dernière image correcte reste composée par le WindowServer. */
    if (var_GetBool(vd->obj.libvlc, DVDDRIVER_VAR_HOLD)) {
        picture_Release (pic);
        if (subpicture)
            subpicture_Delete(subpicture);
        return;
    }

    /* Fin/recréation d'un input ATI : le décodeur dépublie `hw` avant que le
     * vout ait consommé toutes les pictures déjà ordonnancées. Une picture qui
     * porte encore son contexte matériel n'a aucun plan logiciel valide et ne
     * doit surtout pas tomber dans OpenglDraw. `hw_subs_known` signifie qu'un
     * present ATI a réellement eu lieu dans ce vout ; il évite de confondre le
     * contexte opaque d'un autre décodeur matériel avec le nôtre. */
    if (sys->hw_subs_known && pic->context != NULL
     && (hw == NULL || present == NULL)) {
        picture_Release (pic);
        if (subpicture)
            subpicture_Delete(subpicture);
        return;
    }

    /* ★★ SCINTILLEMENT (Panther/Jaguar) : quand le décodeur MATÉRIEL est engagé
     * (hw non NULL), une picture SANS contexte matériel est une picture que le
     * synchro a fait sauter — en mode remplacement ses plans logiciels n'ont
     * JAMAIS été reconstruits. La dessiner en GL compose une image poubelle
     * par-dessus la surface GPU, en alternance avec elle : scintillement
     * proportionnel au taux d'images sautées (invisible sur Tiger à 2 %,
     * infernal sur Panther à 26 %) — et chaque dessin gaspille un upload
     * 720×576. On ne dessine RIEN : la dernière image correcte reste composée
     * par le WindowServer. */
    if (hw != NULL && pic->context == NULL) {
        picture_Release (pic);
        if (subpicture)
            subpicture_Delete(subpicture);
        return;
    }

    /* Le contexte HW a disparu (repli CPU, fin de lecture) : le chemin GL
     * logiciel dessine de nouveau les sous-titres lui-même, la fenêtre de
     * superposition n'a plus lieu d'être. Testé sur hw == NULL (et pas sur un
     * present refusé) : en mode additif, des pictures sans contexte matériel
     * passent aussi par ici sans que le mode change. */
    if (sys->hw_subs_mode && hw == NULL) {
        bool clear;
        @synchronized (sys->glView) {
            clear = (sys->ovl_data != NULL);
            if (clear) {
                free (sys->ovl_data);
                sys->ovl_data = NULL;
                sys->ovl_w = sys->ovl_h = 0;
                sys->ovl_pending = true;
            }
        }
        sys->ovl_sig = 0;
        if (clear)
            [sys->glView performSelectorOnMainThread:@selector(refreshSubsOverlay)
                                          withObject:nil
                                       waitUntilDone:NO];
    }

    const bool presenter_render = sys->presenter_started &&
                                  sys->hdmi_framepack &&
                                  sys->nvidia_320m &&
                                  GL1UseNvidiaMvcPath(
                                      sys, "VLC_GL1_PRESENTER_RENDER") &&
                                  powervlc_mvc_context_is_direct(pic->context);
    if (presenter_render)
    {
        picture_t *old_picture = NULL;
        subpicture_t *old_subpicture = NULL;
        vlc_mutex_lock(&sys->presenter_lock);
        if (!sys->presenter_stop)
        {
            if (sys->presenter_picture_queued == NULL) {
                sys->presenter_picture_queued = pic;
                sys->presenter_subpicture_queued = subpicture;
            } else if (sys->presenter_picture_queued_next == NULL) {
                sys->presenter_picture_queued_next = pic;
                sys->presenter_subpicture_queued_next = subpicture;
            } else {
                /* A single unusually long render/driver wake must not throw
                 * away the following film frame.  Keep a two-frame cushion;
                 * only when that cushion itself overflows do we discard the
                 * oldest queued frame and retain the two freshest ones. */
                old_picture = sys->presenter_picture_queued;
                old_subpicture = sys->presenter_subpicture_queued;
                sys->presenter_picture_queued =
                    sys->presenter_picture_queued_next;
                sys->presenter_subpicture_queued =
                    sys->presenter_subpicture_queued_next;
                sys->presenter_picture_queued_next = pic;
                sys->presenter_subpicture_queued_next = subpicture;
                sys->presenter_dropped++;
            }
            vlc_cond_signal(&sys->presenter_cond);
            pic = NULL;
            subpicture = NULL;
        }
        vlc_mutex_unlock(&sys->presenter_lock);
        if (old_picture != NULL)
            picture_Release(old_picture);
        if (old_subpicture != NULL)
            subpicture_Delete(old_subpicture);
        if (pic != NULL)
            picture_Release(pic);
        if (subpicture != NULL)
            subpicture_Delete(subpicture);
        return;
    }

    const bool async_present = sys->presenter_started &&
                               sys->hdmi_framepack &&
                               sys->nvidia_320m &&
                               getenv("VLC_GL1_FORCE_DRIVER_VSYNC") == NULL &&
                               getenv("VLC_GL1_NO_ASYNC_PRESENT") == NULL;
    /* Render straight into the drawable on the 320M.  Avoiding a full-size
     * RGBA snapshot and blit for every frame keeps this thermally constrained
     * GPU from slowing down after the first minute. */
    const bool direct_back_present = async_present &&
                                     getenv("VLC_GL1_FBO_PRESENT") == NULL;
    int snapshot_index = -1;
    if (async_present)
    {
        /* Reserve a GPU snapshot texture that the presenter is not currently
         * reading.  A queued-but-not-yet-consumed texture may be overwritten:
         * showing the newest complete film frame is preferable to building
         * latency. */
        vlc_mutex_lock (&sys->presenter_lock);
        if (direct_back_present) {
            while (!sys->presenter_stop &&
                   (sys->presenter_queued >= 0 ||
                    sys->presenter_inflight >= 0))
                vlc_cond_wait (&sys->presenter_cond,
                               &sys->presenter_lock);
            snapshot_index = 0; /* completion token, not a texture index */
        } else if (sys->presenter_queued >= 0) {
            snapshot_index = sys->presenter_queued;
            sys->presenter_queued = -1;
            sys->presenter_dropped++;
        } else {
            snapshot_index = sys->presenter_next++ & 1;
            if (snapshot_index == sys->presenter_inflight)
                snapshot_index ^= 1;
        }
        vlc_mutex_unlock (&sys->presenter_lock);
    }

    [sys->glView setVoutFlushing:YES];
    if (vlc_gl_MakeCurrent(sys->gl) == VLC_SUCCESS)
    {
        if (async_present && !direct_back_present)
        {
            const unsigned width = sys->direct_mvc_width != 0
                                 ? sys->direct_mvc_width : sys->tex_width;
            const unsigned height = 2 * sys->framepack_eye_height +
                                    sys->framepack_gap;
            glActiveTextureARB(GL_TEXTURE0_ARB);
            glPixelStorei(GL_UNPACK_CLIENT_STORAGE_APPLE, GL_FALSE);
            if (sys->presenter_texture[0] == 0 ||
                sys->presenter_texture_width != width ||
                sys->presenter_texture_height != height)
            {
                if (sys->presenter_texture[0] != 0)
                    glDeleteTextures(2, sys->presenter_texture);
                if (sys->presenter_fbo[0] != 0)
                    glDeleteFramebuffersEXT(2, sys->presenter_fbo);
                glGenTextures(2, sys->presenter_texture);
                glGenFramebuffersEXT(2, sys->presenter_fbo);
                for (unsigned i = 0; i < 2; ++i) {
                    glBindTexture(GL_TEXTURE_RECTANGLE_EXT,
                                  sys->presenter_texture[i]);
                    glTexParameteri(GL_TEXTURE_RECTANGLE_EXT,
                                    GL_TEXTURE_MIN_FILTER, GL_NEAREST);
                    glTexParameteri(GL_TEXTURE_RECTANGLE_EXT,
                                    GL_TEXTURE_MAG_FILTER, GL_NEAREST);
                    glTexParameteri(GL_TEXTURE_RECTANGLE_EXT,
                                    GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
                    glTexParameteri(GL_TEXTURE_RECTANGLE_EXT,
                                    GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
                    glTexImage2D(GL_TEXTURE_RECTANGLE_EXT, 0, GL_RGBA,
                                 width, height, 0, GL_RGBA,
                                 GL_UNSIGNED_BYTE, NULL);
                    glBindFramebufferEXT(GL_FRAMEBUFFER_EXT,
                                         sys->presenter_fbo[i]);
                    glFramebufferTexture2DEXT(GL_FRAMEBUFFER_EXT,
                                              GL_COLOR_ATTACHMENT0_EXT,
                                              GL_TEXTURE_RECTANGLE_EXT,
                                              sys->presenter_texture[i], 0);
                    const GLenum status =
                        glCheckFramebufferStatusEXT(GL_FRAMEBUFFER_EXT);
                    if (status != GL_FRAMEBUFFER_COMPLETE_EXT)
                        msg_Err(vd, "GL1 presenter FBO %u incomplete: 0x%x",
                                i, (unsigned)status);
                }
                sys->presenter_texture_width = width;
                sys->presenter_texture_height = height;
            }
            glBindFramebufferEXT(GL_FRAMEBUFFER_EXT,
                                 sys->presenter_fbo[snapshot_index]);
            glDrawBuffer(GL_COLOR_ATTACHMENT0_EXT);
            glViewport(0, 0, width, height);
        }
        GL1_PROF_START (t0);
        OpenglDraw (sys);
        GL1_PROF_ADD (draw, t0);
        if (async_present && !direct_back_present)
        {
            glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
            glDrawBuffer(GL_BACK);
        }
        else if (!async_present)
        {
            GL1_PROF_START (t1);
            vlc_gl_Swap (sys->gl);
            GL1_PROF_ADD (swap, t1);
            if (sys->hdmi_framepack && sys->nvidia_320m)
                GL1PresenterDidFlip(sys);
        }
        vlc_gl_ReleaseCurrent(sys->gl);
    }
    [sys->glView setVoutFlushing:NO];
    GL1_PROF_REPORT (vd);
    /* client storage: the driver reads from the picture buffer until the
     * texture is redefined; keep the picture alive until its texture slot
     * is reused instead of releasing it now */
    if (sys->held_pics[sys->tex_index])
        picture_Release (sys->held_pics[sys->tex_index]);
    sys->held_pics[sys->tex_index] = pic;
    sys->has_first_frame = true;
    sys->has_gl_frame = true;

    if (async_present)
    {
        vlc_mutex_lock (&sys->presenter_lock);
        sys->presenter_queued = snapshot_index;
        vlc_cond_signal (&sys->presenter_cond);
        vlc_mutex_unlock (&sys->presenter_lock);
    }

    if (subpicture)
        subpicture_Delete(subpicture);
}

static int ControlInPool (vout_display_t *vd, int query, va_list ap)
{
    vout_display_sys_t *sys = vd->sys;

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

            if (query == VOUT_DISPLAY_CHANGE_SOURCE_CROP)
                UpdateCrop (vd);

            vout_display_place_t place;
            vout_display_PlacePicture (&place, &vd->source, cfg, false);
            @synchronized (sys->glView) {
                sys->place = place;
            }

            if (vlc_gl_MakeCurrent (sys->gl) != VLC_SUCCESS)
                return VLC_EGENERIC;
            /* x / y are top left corner, but we need the lower left one */
            if (query != VOUT_DISPLAY_CHANGE_DISPLAY_SIZE)
                glViewport (place.x,
                            cfg->display.height - (place.y + place.height),
                            place.width, place.height);
            vlc_gl_ReleaseCurrent (sys->gl);

            return VLC_SUCCESS;
        }

        case VOUT_DISPLAY_RESET_PICTURES:
            vlc_assert_unreachable ();
        default:
            msg_Err (vd, "Unknown request in Mac OS X GL1 vout display");
            return VLC_EGENERIC;
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
    /* CGLUnlockContext only releases the mutex; it does not stop the
     * NSOpenGLContext from being current on this thread.  The asynchronous
     * HDMI presenter must be able to acquire that same context after the vout
     * has prepared a back buffer, so explicitly relinquish thread ownership
     * before unlocking it.  The next OpenglLock calls -makeCurrentContext as
     * usual. */
    if (sys->display_sys->presenter_started)
        [NSOpenGLContext clearCurrentContext];
    vlc_CGLUnlockContext (sys->locked_ctx);
    sys->locked_ctx = NULL;
}

static void GL1PresenterDidFlip(vout_display_sys_t *display)
{
    /* Never perform diagnostics from CoreVideo's real-time callback during
     * normal playback.  On Snow Leopard an occasional stderr flush to the
     * system disk can exceed one 41.7 ms HDMI refresh and is itself visible
     * as the isolated repeated frame the metric was meant to observe. */
    if (getenv("VLC_GL1_METRICS") == NULL)
        return;

    unsigned report_count = 0, report_dropped = 0;
    vlc_tick_t report_elapsed = 0;
    vlc_mutex_lock(&display->presenter_lock);
    if (display->presenter_report_start == 0)
        display->presenter_report_start = mdate();
    display->presenter_presented++;
    if (display->presenter_presented >= 120) {
        report_count = display->presenter_presented;
        report_dropped = display->presenter_dropped;
        report_elapsed = mdate() - display->presenter_report_start;
        display->presenter_presented = 0;
        display->presenter_dropped = 0;
        display->presenter_report_start = mdate();
    }
    vlc_mutex_unlock(&display->presenter_lock);
    if (report_count != 0 && report_elapsed > 0)
    {
        msg_Err(display->gl, "GL1 HDMI presenter: %u flips in %.3f s "
                "(%.2f fps), %u late pictures discarded",
                report_count, report_elapsed / 1000000.0,
                report_count * 1000000.0 / report_elapsed, report_dropped);
        fprintf(stderr, "GL1_METRIC flips=%u elapsed=%.3f fps=%.2f dropped=%u\n",
                report_count, report_elapsed / 1000000.0,
                report_count * 1000000.0 / report_elapsed, report_dropped);
        fflush(stderr);
    }
}

/* CoreVideo calls this on its real-time display thread just ahead of the
 * selected display's vertical retrace.  Do not commit the drawable here:
 * Snow Leopard's 320M can return from an interval-0 CGLFlushDrawable while
 * the scanout is still active.  Wake the presenter instead; it queues an
 * interval-1 swap with the driver for the following retrace. */
static CVReturn GL1DisplayLinkPresenter(CVDisplayLinkRef link,
                                        const CVTimeStamp *now,
                                        const CVTimeStamp *output,
                                        CVOptionFlags in_flags,
                                        CVOptionFlags *out_flags,
                                        void *opaque)
{
    (void)link; (void)now; (void)output; (void)in_flags; (void)out_flags;
    vout_display_sys_t *display = opaque;
    typedef uint32_t (*CallbackBeamPosition)(CGDirectDisplayID);
    static CallbackBeamPosition callback_beam_position;
    if (callback_beam_position == NULL)
        callback_beam_position = (CallbackBeamPosition)dlsym(
            RTLD_DEFAULT, "CGDisplayBeamPosition");
    const uint32_t callback_entry_beam = callback_beam_position != NULL
        ? callback_beam_position(display->stereo_display) : 0;

    vlc_mutex_lock(&display->presenter_lock);
    const bool native_mode = display->presenter_thread_started &&
                             getenv("VLC_GL1_PRESENTER_RENDER") != NULL;
    if (native_mode) {
        const bool callback_present =
            getenv("VLC_GL1_CALLBACK_PRESENT") != NULL;
        const bool ready = callback_present &&
                           display->presenter_native_ready;
        if (!display->presenter_stop) {
            display->presenter_native_target_host_time = output->hostTime;
            if (!callback_present) {
                display->presenter_native_flip_serial++;
                vlc_cond_broadcast(&display->presenter_cond);
            } else if (ready) {
                display->presenter_native_ready = false;
            }
        }
        vlc_mutex_unlock(&display->presenter_lock);

        if (!ready)
            return kCVReturnSuccess;

        /* The rendered back buffer is complete before native_ready is set.
         * Commit it from CoreVideo's own real-time callback so Snow Leopard
         * cannot delay a second worker-thread wake into active scanout. */
        /* The callback itself is emitted at the current retrace.  On 10.6,
         * output->hostTime describes the *following* refresh; waiting for it
         * here occupies CoreVideo for a whole 24 Hz period and makes it skip
         * every other callback (an exact 12 fps). */

        NSOpenGLContext *context = [display->glView openGLContext];
        CGLContextObj cgl = vlc_CGLContextOf(context);
        bool did_flip = false;
        const uint32_t callback_beam = callback_beam_position != NULL
            ? callback_beam_position(display->stereo_display) : 0;
        if (cgl != NULL && vlc_CGLLockContext(cgl) == kCGLNoError) {
            if (display->swap_interval != 0) {
                GLint interval[] = { 0 };
                CGLSetParameter(cgl, kCGLCPSwapInterval, interval);
                display->swap_interval = 0;
            }
            CGLSetCurrentContext(cgl);
            CGLFlushDrawable(cgl);
            CGLSetCurrentContext(NULL);
            vlc_CGLUnlockContext(cgl);
            did_flip = true;
            GL1PresenterDidFlip(display);
        }
        static unsigned callback_beam_samples;
        if (callback_beam_samples < 32)
            msg_Dbg(display->gl,
                    "GL1 PCM callback flush %u: entry %u, preflush %u",
                    ++callback_beam_samples, callback_entry_beam,
                    callback_beam);
        vlc_mutex_lock(&display->presenter_lock);
        if (!did_flip)
            display->presenter_dropped++;
        display->presenter_native_flip_serial++;
        vlc_cond_broadcast(&display->presenter_cond);
        vlc_mutex_unlock(&display->presenter_lock);
        return kCVReturnSuccess;
    }

    const bool native_ready = display->presenter_native_ready;
    if (display->presenter_stop ||
        (!native_ready && display->presenter_queued < 0)) {
        vlc_mutex_unlock(&display->presenter_lock);
        return kCVReturnSuccess;
    }
    if (native_ready) {
        /* output->hostTime is CoreVideo's hardware prediction of the next
         * retrace.  Let the presenter wait for that exact timestamp while
         * this real-time callback returns immediately. */
        display->presenter_native_deferred = true;
        display->presenter_native_target_host_time = output->hostTime;
        display->presenter_native_ready = false;
    } else {
        display->presenter_inflight = display->presenter_queued;
        display->presenter_queued = -1;
    }
    vlc_mutex_unlock(&display->presenter_lock);

    NSOpenGLContext *context = [display->glView openGLContext];
    CGLContextObj cgl = vlc_CGLContextOf(context);
    if (cgl != NULL && vlc_CGLLockContext(cgl) == kCGLNoError) {
        if (display->swap_interval != 0) {
            GLint interval[] = { 0 };
            CGLSetParameter(cgl, kCGLCPSwapInterval, interval);
            display->swap_interval = 0;
        }
        CGLSetCurrentContext(cgl);
        CGLFlushDrawable(cgl);
        CGLSetCurrentContext(NULL);
        vlc_CGLUnlockContext(cgl);
        GL1PresenterDidFlip(display);
    }

    vlc_mutex_lock(&display->presenter_lock);
    if (native_ready)
        display->presenter_native_flip_serial++;
    else
        display->presenter_inflight = -1;
    vlc_cond_broadcast(&display->presenter_cond);
    vlc_mutex_unlock(&display->presenter_lock);
    return kCVReturnSuccess;
}

/* Keep the display clock independent from MVC upload/rendering.  The render
 * worker publishes one immutable back buffer; this thread consumes every
 * CoreVideo target even while the next MVC picture is still being decoded. */
static void *GL1FlipPresenter(void *opaque)
{
    vout_display_sys_t *display = opaque;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    mach_timebase_info_data_t timebase;
    mach_timebase_info(&timebase);
    const uint64_t ticks_per_ms =
        1000000ULL * timebase.denom / timebase.numer;
    thread_time_constraint_policy_data_t policy = {
        .period = (uint32_t)(42 * ticks_per_ms),
        .computation = (uint32_t)(10 * ticks_per_ms),
        .constraint = (uint32_t)(15 * ticks_per_ms),
        .preemptible = FALSE,
    };
    thread_port_t thread = mach_thread_self();
    kern_return_t policy_error = thread_policy_set(thread,
        THREAD_TIME_CONSTRAINT_POLICY, (thread_policy_t)&policy,
        THREAD_TIME_CONSTRAINT_POLICY_COUNT);
    mach_port_deallocate(mach_task_self(), thread);
    msg_Dbg(display->gl, "GL1 split flip real-time policy: %s",
            policy_error == KERN_SUCCESS ? "enabled" : "unavailable");

    typedef uint32_t (*FlipBeamPosition)(CGDirectDisplayID);
    FlipBeamPosition beam_position = (FlipBeamPosition)dlsym(
        RTLD_DEFAULT, "CGDisplayBeamPosition");
    uint64_t consumed_serial = 0;

    vlc_mutex_lock(&display->presenter_lock);
    while (!display->presenter_stop) {
        while (!display->presenter_stop &&
               display->presenter_native_flip_serial == consumed_serial)
            vlc_cond_wait(&display->presenter_cond,
                          &display->presenter_lock);
        if (display->presenter_stop)
            break;
        consumed_serial = display->presenter_native_flip_serial;
        const uint64_t target =
            display->presenter_native_target_host_time;
        vlc_mutex_unlock(&display->presenter_lock);

        if (target != 0) {
            const uint64_t lead = 8000ULL * 1000ULL *
                timebase.denom / timebase.numer;
            const uint64_t wake = target > lead ? target - lead : target;
            const uint64_t phase = 100ULL * 1000ULL *
                timebase.denom / timebase.numer;
            const uint64_t phased_target = target + phase;
            if (mach_absolute_time() < wake)
                mach_wait_until(wake);
            while (mach_absolute_time() < phased_target)
                ;
        }

        uint32_t beam = beam_position != NULL
            ? beam_position(display->stereo_display) : 0;
        const uint32_t total = 2 * display->framepack_eye_height +
                               display->framepack_gap;
        const uint32_t safe_start = total > 10 ? total - 10 : total;
        const bool scan_safe = !display->exclusive_capture ||
            beam_position == NULL || beam == 0 || beam >= safe_start;

        vlc_mutex_lock(&display->presenter_lock);
        const bool ready = display->presenter_native_ready;
        vlc_mutex_unlock(&display->presenter_lock);

        bool did_flip = false;
        if (ready && scan_safe) {
            NSOpenGLContext *context = [display->glView openGLContext];
            CGLContextObj cgl = vlc_CGLContextOf(context);
            if (cgl != NULL && vlc_CGLLockContext(cgl) == kCGLNoError) {
                if (display->swap_interval != 0) {
                    GLint interval[] = { 0 };
                    CGLSetParameter(cgl, kCGLCPSwapInterval, interval);
                    display->swap_interval = 0;
                }
                CGLSetCurrentContext(cgl);
                CGLFlushDrawable(cgl);
                CGLSetCurrentContext(NULL);
                vlc_CGLUnlockContext(cgl);
                did_flip = true;
                GL1PresenterDidFlip(display);
            }
        }

        static unsigned samples;
        if (samples < 24)
            msg_Dbg(display->gl,
                    "GL1 split flip %u: target beam %u, ready %d, flip %d",
                    ++samples, beam, (int)ready, (int)did_flip);

        vlc_mutex_lock(&display->presenter_lock);
        if (did_flip) {
            display->presenter_native_ready = false;
            vlc_cond_broadcast(&display->presenter_cond);
        } else if (ready && !scan_safe) {
            display->presenter_dropped++;
        }
    }
    vlc_mutex_unlock(&display->presenter_lock);
    [pool release];
    return NULL;
}

static void *GL1AsyncPresenter (void *opaque)
{
    vout_display_sys_t *display = opaque;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    const bool presenter_render =
        getenv("VLC_GL1_PRESENTER_RENDER") != NULL;

    if (presenter_render &&
        getenv("VLC_GL1_PRESENTER_REALTIME") != NULL)
    {
        mach_timebase_info_data_t tb;
        mach_timebase_info(&tb);
        const uint64_t ticks_per_ms = 1000000ULL * tb.denom / tb.numer;
        thread_time_constraint_policy_data_t policy = {
            .period = (uint32_t)(42 * ticks_per_ms),
            .computation = (uint32_t)(10 * ticks_per_ms),
            .constraint = (uint32_t)(15 * ticks_per_ms),
            .preemptible = FALSE,
        };
        thread_port_t thread = mach_thread_self();
        kern_return_t kr = thread_policy_set(thread,
            THREAD_TIME_CONSTRAINT_POLICY, (thread_policy_t)&policy,
            THREAD_TIME_CONSTRAINT_POLICY_COUNT);
        mach_port_deallocate(mach_task_self(), thread);
        msg_Dbg(display->gl,
                "GL1 presenter real-time policy: %s",
                kr == KERN_SUCCESS ? "enabled" : "unavailable");
    }

    uint64_t consumed_display_link_serial = 0;
    vlc_mutex_lock (&display->presenter_lock);
    while (!display->presenter_stop)
    {
        while ((presenter_render
                    ? display->presenter_picture_queued == NULL
                    : display->presenter_queued < 0) &&
               !display->presenter_stop)
            vlc_cond_wait (&display->presenter_cond, &display->presenter_lock);
        if (display->presenter_stop)
            break;

        picture_t *presenter_picture = NULL;
        subpicture_t *presenter_subpicture = NULL;
        int snapshot_index = 0;
        if (presenter_render)
        {
            presenter_picture = display->presenter_picture_queued;
            presenter_subpicture = display->presenter_subpicture_queued;
            display->presenter_picture_queued =
                display->presenter_picture_queued_next;
            display->presenter_subpicture_queued =
                display->presenter_subpicture_queued_next;
            display->presenter_picture_queued_next = NULL;
            display->presenter_subpicture_queued_next = NULL;
            display->presenter_picture_inflight = presenter_picture;
            display->presenter_subpicture_inflight = presenter_subpicture;
        }
        else
        {
            snapshot_index = display->presenter_queued;
            display->presenter_queued = -1;
            display->presenter_inflight = snapshot_index;
        }
        vlc_mutex_unlock (&display->presenter_lock);

        const vlc_tick_t presenter_cycle_start = mdate();
        vlc_tick_t presenter_after_render = presenter_cycle_start;

        if (presenter_render)
        {
            if (vlc_gl_MakeCurrent(display->gl) == VLC_SUCCESS)
            {
                OpenglUpload(display, presenter_picture);
                UploadSubpictures(display->owner_vd, presenter_subpicture);
                glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
                glDrawBuffer(GL_BACK);
                OpenglDraw(display);
                if (display->presenter_uses_display_link)
                    /* Drain all frame-pack rendering before advertising the
                     * back buffer to CoreVideo.  Its callback must perform
                     * only the page flip while vertical blank is active. */
                    glFinish();
                vlc_gl_ReleaseCurrent(display->gl);
            }
            presenter_after_render = mdate();
        }

        /* CVDisplayLink supplies the cadence, while the GL driver owns the
         * tear-free commit.  Queueing the interval-1 swap from this worker
         * avoids doing a potentially blocking driver call on CoreVideo's
         * real-time callback and avoids interval-0 scanout tears on 320M. */
        if (presenter_render && display->presenter_uses_display_link)
        {
            if (display->presenter_flip_thread_started) {
                /* The dedicated clock thread owns the page flip.  Publish a
                 * completely rendered back buffer, then keep it immutable
                 * until that thread has committed it at HDMI blanking. */
                vlc_mutex_lock(&display->presenter_lock);
                display->presenter_native_ready = true;
                vlc_cond_broadcast(&display->presenter_cond);
                while (!display->presenter_stop &&
                       display->presenter_native_ready)
                    vlc_cond_wait(&display->presenter_cond,
                                  &display->presenter_lock);
                vlc_mutex_unlock(&display->presenter_lock);

                if (presenter_picture != NULL)
                    picture_Release(presenter_picture);
                if (presenter_subpicture != NULL)
                    subpicture_Delete(presenter_subpicture);
                vlc_mutex_lock(&display->presenter_lock);
                display->presenter_picture_inflight = NULL;
                display->presenter_subpicture_inflight = NULL;
                vlc_cond_broadcast(&display->presenter_cond);
                continue;
            }
            const bool callback_present =
                getenv("VLC_GL1_CALLBACK_PRESENT") != NULL;
            vlc_mutex_lock(&display->presenter_lock);
            if (callback_present)
                display->presenter_native_ready = true;
            while (!display->presenter_stop &&
                   display->presenter_native_flip_serial ==
                       consumed_display_link_serial)
                vlc_cond_wait(&display->presenter_cond,
                              &display->presenter_lock);
            consumed_display_link_serial =
                display->presenter_native_flip_serial;
            const bool deferred =
                !callback_present &&
                display->presenter_native_target_host_time != 0;
            const uint64_t target_host_time =
                display->presenter_native_target_host_time;
            vlc_mutex_unlock(&display->presenter_lock);

            if (deferred) {
                typedef uint32_t (*PreciseBeamPosition)(CGDirectDisplayID);
                typedef CGError (*WaitOutsideScanLines)(CGDirectDisplayID,
                                                        uint32_t, uint32_t);
                static PreciseBeamPosition precise_beam_position;
                static WaitOutsideScanLines wait_outside_scan_lines;
                if (precise_beam_position == NULL)
                    precise_beam_position = (PreciseBeamPosition)dlsym(
                        RTLD_DEFAULT, "CGDisplayBeamPosition");
                if (wait_outside_scan_lines == NULL)
                    wait_outside_scan_lines = (WaitOutsideScanLines)dlsym(
                        RTLD_DEFAULT,
                        "CGDisplayWaitForBeamPositionOutsideLines");
                const vlc_tick_t beam_wait_start = mdate();
                bool beam_at_boundary = false;
                uint32_t beam_after_wait = 0;
                if (display->exclusive_capture && target_host_time != 0) {
                    /* CVDisplayLink predicts the beginning of the next
                     * hardware refresh in mach absolute-time units.  On an
                     * exclusive CGL drawable this is also the complete
                     * frame-pack page-flip boundary.  Keep GL work out of
                     * CoreVideo's real-time callback, but consume its target
                     * here instead of trying to catch a sub-millisecond beam
                     * interval by polling on Snow Leopard. */
                    uint64_t wake_host_time = target_host_time;
                    if (getenv("VLC_GL1_PRESENTER_DRIVER_VSYNC") != NULL) {
                        static mach_timebase_info_data_t vsync_timebase;
                        if (vsync_timebase.denom == 0)
                            mach_timebase_info(&vsync_timebase);
                        /* Submit shortly before retrace.  Interval 1 still
                         * gives the NVIDIA driver ownership of the atomic
                         * page flip, but it can now block VDA for at most a
                         * few milliseconds instead of an entire 24 Hz
                         * period.  The 320M needs more than two milliseconds
                         * to arm a flip; keep the lead tunable so it can be
                         * measured against both missed flips and VDA cadence. */
                        unsigned lead_us = 8000;
                        const char *lead_env =
                            getenv("VLC_GL1_VSYNC_LEAD_US");
                        if (lead_env != NULL) {
                            const unsigned parsed = (unsigned)strtoul(
                                lead_env, NULL, 10);
                            if (parsed >= 1000 && parsed <= 20000)
                                lead_us = parsed;
                        }
                        const uint64_t lead_ticks =
                            (uint64_t)lead_us * 1000ULL *
                            vsync_timebase.denom / vsync_timebase.numer;
                        if (wake_host_time > lead_ticks)
                            wake_host_time -= lead_ticks;
                    } else {
                        static mach_timebase_info_data_t flip_timebase;
                        if (flip_timebase.denom == 0)
                            mach_timebase_info(&flip_timebase);
                        const uint64_t lead_ticks = 4000ULL * 1000ULL *
                            flip_timebase.denom / flip_timebase.numer;
                        if (wake_host_time > lead_ticks)
                            wake_host_time -= lead_ticks;
                    }
                    if (mach_absolute_time() < wake_host_time)
                        mach_wait_until(wake_host_time);
                    if (getenv("VLC_GL1_PRESENTER_DRIVER_VSYNC") == NULL) {
                        /* CoreVideo fires about 0.4 ms after the real wrap
                         * once AUHAL PCM is active.  Arm from its prediction
                         * for the following refresh and finish 0.4 ms early.
                         * The non-preemptible final spin prevents AUHAL from
                         * pushing this short commit into active scanout. */
                        const uint64_t final_host_time = target_host_time;
                        while (mach_absolute_time() < final_host_time)
                            ;
                        beam_at_boundary = true;
                        if (precise_beam_position != NULL)
                            beam_after_wait = precise_beam_position(
                                                  display->stereo_display);
                    }
                    if (getenv("VLC_GL1_PRESENTER_DRIVER_VSYNC") != NULL) {
                        beam_at_boundary = true;
                        if (precise_beam_position != NULL)
                            beam_after_wait = precise_beam_position(
                                                  display->stereo_display);
                    }
                } else if (precise_beam_position != NULL &&
                    display->framepack_eye_height != 0 &&
                    display->framepack_gap != 0) {
                    const uint32_t total =
                        2 * display->framepack_eye_height +
                        display->framepack_gap;
                    const uint32_t target = total > 5 ? total - 5 : total;
                    uint32_t beam = precise_beam_position(
                                        display->stereo_display);
                    if (beam >= target) {
                        beam_at_boundary = true;
                    } else {
                        static mach_timebase_info_data_t beam_timebase;
                        if (beam_timebase.denom == 0)
                            mach_timebase_info(&beam_timebase);
                        const vlc_tick_t deadline = mdate() + 50000;
                        do {
                            beam = precise_beam_position(
                                       display->stereo_display);
                            beam_at_boundary = beam >= target;
                            if (!beam_at_boundary) {
                                const uint32_t distance = target - beam;
                                const uint64_t wait_us =
                                    (uint64_t)distance * 41708 / total;
                                if (wait_us > 1200) {
                                    const uint64_t chunk_us =
                                        __MIN(wait_us - 1200, 4000);
                                    const uint64_t ticks = chunk_us * 1000ULL *
                                        beam_timebase.denom /
                                        beam_timebase.numer;
                                    mach_wait_until(mach_absolute_time() +
                                                    ticks);
                                }
                            }
                        } while (!beam_at_boundary && mdate() < deadline);
                    }
                    beam_after_wait = precise_beam_position(
                                          display->stereo_display);
                }
                static unsigned wait_samples;
                if (wait_samples < 16)
                    msg_Dbg(display->gl,
                            "GL1 precise beam wait %u: %lld us, beam %u, boundary %d",
                            ++wait_samples,
                            (long long)(mdate() - beam_wait_start),
                            beam_after_wait,
                            beam_at_boundary);
                NSOpenGLContext *context = [display->glView openGLContext];
                CGLContextObj cgl = vlc_CGLContextOf(context);
                uint32_t flush_beam_before = 0;
                uint32_t flush_beam_after = 0;
                const vlc_tick_t flush_start = mdate();
                bool did_flip = false;
                if (cgl != NULL &&
                    vlc_CGLLockContext(cgl) == kCGLNoError) {
                    const int wanted_swap =
                        getenv("VLC_GL1_PRESENTER_DRIVER_VSYNC") != NULL
                            ? 1 : 0;
                    if (display->swap_interval != wanted_swap) {
                        GLint interval[] = { wanted_swap };
                        CGLSetParameter(cgl, kCGLCPSwapInterval, interval);
                        display->swap_interval = wanted_swap;
                    }
                    if (precise_beam_position != NULL)
                        flush_beam_before = precise_beam_position(
                                                display->stereo_display);
                    const bool safe_interval0 = wanted_swap != 0 ||
                        !display->exclusive_capture ||
                        precise_beam_position == NULL ||
                        flush_beam_before == 0 ||
                        flush_beam_before >= 2195;
                    if (safe_interval0) {
                        CGLSetCurrentContext(cgl);
                        CGLFlushDrawable(cgl);
                        if (precise_beam_position != NULL)
                            flush_beam_after = precise_beam_position(
                                                   display->stereo_display);
                        CGLSetCurrentContext(NULL);
                        did_flip = true;
                    } else {
                        display->presenter_dropped++;
                        flush_beam_after = flush_beam_before;
                    }
                    vlc_CGLUnlockContext(cgl);
                    if (did_flip)
                        GL1PresenterDidFlip(display);
                }
                static unsigned flush_samples;
                if (flush_samples < 24)
                    msg_Dbg(display->gl,
                            "GL1 timed flush %u: beam %u -> %u in %lld us%s",
                            ++flush_samples, flush_beam_before,
                            flush_beam_after,
                            (long long)(mdate() - flush_start),
                            did_flip ? "" : " (unsafe, discarded)");
            }

            if (presenter_picture != NULL)
                picture_Release(presenter_picture);
            if (presenter_subpicture != NULL)
                subpicture_Delete(presenter_subpicture);

            vlc_mutex_lock(&display->presenter_lock);
            display->presenter_inflight = -1;
            display->presenter_picture_inflight = NULL;
            display->presenter_subpicture_inflight = NULL;
            vlc_cond_broadcast(&display->presenter_cond);
            continue;
        }

        typedef uint32_t (*BeamPosition)(CGDirectDisplayID);
        static BeamPosition beam_position;
        if (beam_position == NULL) {
            beam_position = (BeamPosition)
                dlsym(RTLD_DEFAULT, "CGDisplayBeamPosition");
        }
        uint32_t beam = 0;
        uint32_t initial_beam = 0;
        unsigned beam_attempts = 0;
        const vlc_tick_t beam_wait_start = mdate();
        bool safe_to_flip = true;
        if (getenv("VLC_GL1_PRESENTER_DRIVER_VSYNC") == NULL &&
            beam_position != NULL && display->framepack_eye_height != 0 &&
            display->framepack_gap != 0) {
            const uint32_t total = 2 * display->framepack_eye_height +
                                   display->framepack_gap;
            const uint32_t switch_line = display->framepack_eye_height +
                                         display->framepack_gap / 2;
            const uint32_t target_eye = switch_line > 220
                                      ? switch_line - 220 : switch_line;
            /* The beam counter was measured to reach line 2205 before it
             * wraps.  The frame boundary is therefore a second invisible
             * switching point, halfway around the scan from the inter-eye
             * gap.  Selecting the next of both cuts the worst wait in half. */
            /* The native presenter has already submitted all drawing before
             * this wait; its interval-0 flush is effectively immediate.  The
             * historical 220-line lead compensated a synchronous render in
             * OpenglSwap and visibly switched the native drawable inside the
             * bottom eye.  Aim at the last scan lines instead. */
            const uint32_t frame_lead = presenter_render ? 5 : 220;
            const uint32_t target_frame = total > frame_lead
                                        ? total - frame_lead : 0;
            const bool direct_back_present =
                getenv("VLC_GL1_FBO_PRESENT") == NULL;
            /* A drawable flip in the inter-eye gap would pair the first eye
             * of the old film frame with the second eye of the new one.  The
             * direct path therefore uses only the complete-frame boundary.
             * An immutable FBO snapshot remains safe at either blank. */
            safe_to_flip = false;
            static mach_timebase_info_data_t timebase;
            if (timebase.denom == 0)
                mach_timebase_info(&timebase);
            /* A late wake must never fall through into an interval-0 swap:
             * that is a visible tear.  Retry at the following safe boundary;
             * if both attempts miss, discard this picture and leave the
             * complete previous frame on screen. */
            for (unsigned attempt = 0; attempt < 1 && !safe_to_flip;
                 ++attempt) {
                beam = beam_position(display->stereo_display) % total;
                if (attempt == 0)
                    initial_beam = beam;
                beam_attempts = attempt + 1;
                uint32_t eye_distance =
                    (target_eye + total - beam) % total;
                uint32_t frame_distance =
                    (target_frame + total - beam) % total;
                uint32_t nearest = direct_back_present
                                 ? frame_distance
                                 : __MIN(eye_distance, frame_distance);
                /* More than half a scan away means this picture completed
                 * just after its safe boundary.  Waiting a whole refresh
                 * here blocks the direct back buffer and makes every later
                 * picture miss too.  Drop it immediately so the queued next
                 * picture can recover the 24 Hz phase. */
                if (nearest > total / 2 && !presenter_render)
                    break;
                if (nearest > 20 && nearest < total - 20) {
                    const uint64_t wait_us =
                        (uint64_t)nearest * 41708 / total;
                    const uint64_t spin_guard = presenter_render ? 3000 : 100;
                    if (wait_us > spin_guard) {
                        const uint64_t sleep_us = wait_us - spin_guard;
                        const uint64_t sleep_ticks = sleep_us * 1000ULL *
                            timebase.denom / timebase.numer;
                        mach_wait_until(mach_absolute_time() + sleep_ticks);
                    }
                }
                const vlc_tick_t deadline = mdate() +
                    (presenter_render ? 4000 : 700);
                do {
                    beam = beam_position(display->stereo_display) % total;
                    eye_distance = (target_eye + total - beam) % total;
                    frame_distance = (target_frame + total - beam) % total;
                    const uint32_t tolerance = 20;
                    const bool at_eye = eye_distance <= tolerance ||
                                        eye_distance >= total - tolerance;
                    const bool at_frame = frame_distance <= tolerance ||
                                          frame_distance >= total - tolerance;
                    safe_to_flip = at_frame ||
                                   (!direct_back_present && at_eye);
                } while (!safe_to_flip && mdate() < deadline);
            }
        }
        if (!safe_to_flip) {
            static unsigned safe_drop_count;
            if (++safe_drop_count <= 16 || safe_drop_count % 120 == 0)
                msg_Err(display->gl,
                        "GL1 presenter missed safe scan boundary (%u): initial %u final %u waited %d us",
                        safe_drop_count, initial_beam, beam,
                        (int)(mdate() - beam_wait_start));
            if (presenter_picture != NULL)
                picture_Release(presenter_picture);
            if (presenter_subpicture != NULL)
                subpicture_Delete(presenter_subpicture);
            vlc_mutex_lock(&display->presenter_lock);
            display->presenter_dropped++;
            display->presenter_inflight = -1;
            display->presenter_picture_inflight = NULL;
            display->presenter_subpicture_inflight = NULL;
            vlc_cond_broadcast(&display->presenter_cond);
            continue;
        }
        static unsigned samples;
        if (samples < 32)
            msg_Dbg(display->gl, "GL1 CGL beam swap %u initial %u "
                    "pre-flush %u waited %d us attempts %u",
                    ++samples, initial_beam, beam,
                    (int)(mdate() - beam_wait_start), beam_attempts);

        /* Use the CGL drawable directly.  Calling the Objective-C
         * -flushBuffer wrapper from a worker did not page-flip reliably on
         * the 320M, while dispatching it through AppKit only reached 13 fps.
         * CGLFlushDrawable is the thread-safe primitive used by the classic
         * CVDisplayLink recipe and keeps the driver VSync off the vout. */
        NSOpenGLContext *context = [display->glView openGLContext];
        CGLContextObj cgl = vlc_CGLContextOf(context);
        if (cgl != NULL && vlc_CGLLockContext(cgl) == kCGLNoError) {
            const int wanted_swap =
                getenv("VLC_GL1_PRESENTER_DRIVER_VSYNC") != NULL ? 1 : 0;
            if (display->swap_interval != wanted_swap) {
                GLint interval[] = { wanted_swap };
                CGLSetParameter(cgl, kCGLCPSwapInterval, interval);
                display->swap_interval = wanted_swap;
                msg_Dbg(display->gl,
                        "GL1 CGL presenter uses swap interval %d",
                        wanted_swap);
            }
            CGLSetCurrentContext(cgl);
            if (getenv("VLC_GL1_FBO_PRESENT") != NULL) {
                glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
                glDrawBuffer(GL_BACK);
                glPushAttrib(GL_ALL_ATTRIB_BITS);
                glDisable(GL_FRAGMENT_PROGRAM_ARB);
                glDisable(GL_BLEND);
                glDisable(GL_DEPTH_TEST);
                for (unsigned unit = 0; unit < 3; ++unit) {
                    glActiveTextureARB(GL_TEXTURE0_ARB + unit);
                    glDisable(GL_TEXTURE_2D);
                    glDisable(GL_TEXTURE_RECTANGLE_EXT);
                }
                glActiveTextureARB(GL_TEXTURE0_ARB);
                glEnable(GL_TEXTURE_RECTANGLE_EXT);
                glBindTexture(GL_TEXTURE_RECTANGLE_EXT,
                              display->presenter_texture[snapshot_index]);
                glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
                glViewport(0, 0, display->presenter_texture_width,
                           display->presenter_texture_height);
                glMatrixMode(GL_PROJECTION);
                glPushMatrix();
                glLoadIdentity();
                glMatrixMode(GL_MODELVIEW);
                glPushMatrix();
                glLoadIdentity();
                glColor4f(1.f, 1.f, 1.f, 1.f);
                const GLfloat width = display->presenter_texture_width;
                const GLfloat height = display->presenter_texture_height;
                glBegin(GL_QUADS);
                glTexCoord2f(0.f, 0.f);       glVertex2f(-1.f, -1.f);
                glTexCoord2f(width, 0.f);     glVertex2f( 1.f, -1.f);
                glTexCoord2f(width, height);  glVertex2f( 1.f,  1.f);
                glTexCoord2f(0.f, height);    glVertex2f(-1.f,  1.f);
                glEnd();
                glPopMatrix();
                glMatrixMode(GL_PROJECTION);
                glPopMatrix();
                glMatrixMode(GL_MODELVIEW);
                glPopAttrib();
            }
            CGLFlushDrawable(cgl);
            CGLSetCurrentContext(NULL);
            vlc_CGLUnlockContext(cgl);
            GL1PresenterDidFlip(display);
        }
        const vlc_tick_t presenter_after_flush = mdate();

        if (presenter_picture != NULL)
            picture_Release(presenter_picture);
        if (presenter_subpicture != NULL)
            subpicture_Delete(presenter_subpicture);
        const vlc_tick_t presenter_after_release = mdate();

        if (presenter_render) {
            static unsigned timing_samples;
            static vlc_tick_t timing_render, timing_wait_flush,
                              timing_release, timing_total;
            timing_render += presenter_after_render - presenter_cycle_start;
            timing_wait_flush += presenter_after_flush - presenter_after_render;
            timing_release += presenter_after_release - presenter_after_flush;
            timing_total += presenter_after_release - presenter_cycle_start;
            if (++timing_samples == 30) {
                msg_Err(display->gl,
                        "GL1 presenter timing: render %.1f ms, wait+flush %.1f ms, release %.1f ms, total %.1f ms",
                        timing_render / 30000., timing_wait_flush / 30000.,
                        timing_release / 30000., timing_total / 30000.);
                timing_samples = 0;
                timing_render = timing_wait_flush = timing_release =
                    timing_total = 0;
            }
        }

        vlc_mutex_lock (&display->presenter_lock);
        display->presenter_inflight = -1;
        display->presenter_picture_inflight = NULL;
        display->presenter_subpicture_inflight = NULL;
        vlc_cond_broadcast (&display->presenter_cond);
    }
    display->presenter_inflight = -1;
    display->presenter_queued = -1;
    picture_t *queued_picture = display->presenter_picture_queued;
    subpicture_t *queued_subpicture = display->presenter_subpicture_queued;
    picture_t *queued_picture_next =
        display->presenter_picture_queued_next;
    subpicture_t *queued_subpicture_next =
        display->presenter_subpicture_queued_next;
    display->presenter_picture_queued = NULL;
    display->presenter_subpicture_queued = NULL;
    display->presenter_picture_queued_next = NULL;
    display->presenter_subpicture_queued_next = NULL;
    vlc_mutex_unlock (&display->presenter_lock);
    if (queued_picture != NULL)
        picture_Release(queued_picture);
    if (queued_subpicture != NULL)
        subpicture_Delete(queued_subpicture);
    if (queued_picture_next != NULL)
        picture_Release(queued_picture_next);
    if (queued_subpicture_next != NULL)
        subpicture_Delete(queued_subpicture_next);
    [pool release];
    return NULL;
}

static void OpenglSwap (vlc_gl_t *gl)
{
    struct gl_sys *sys = gl->sys;
    vout_display_sys_t *display = sys->display_sys;
    if (display->hdmi_framepack && display->nvidia_320m &&
        getenv("VLC_GL1_FORCE_DRIVER_VSYNC") == NULL &&
        getenv("VLC_GL1_NO_BEAMSYNC") == NULL)
    {
        typedef uint32_t (*BeamPosition)(CGDirectDisplayID);
        static BeamPosition beam_position;
        static bool looked_up;
        if (!looked_up)
        {
            looked_up = true;
            beam_position = (BeamPosition)
                dlsym(RTLD_DEFAULT, "CGDisplayBeamPosition");
        }
        if (beam_position != NULL)
        {
            const uint32_t total = 2 * display->framepack_eye_height +
                                   display->framepack_gap;
            /* A frame-packed HDMI timing has a real vertical blanking gap
             * between the two eyes (45 lines at 1080p).  Page-flipping in
             * that gap is just as invisible as flipping after the bottom
             * eye, but reaches it roughly half a frame earlier.  That is
             * crucial on the 320M: waiting for the end of the complete 2205
             * line scan serialises VDA and the MVC enhancement decoder.
             *
             * flushBuffer drains queued GL work before switching the
             * interval-0 surface.  It takes about 4 ms, or 220 scan lines on
             * this driver, so start that much before the middle of the gap.
             * The measured surface switch then lands in HDMI blanking, not
             * in either visible eye. */
            const uint32_t switch_line = display->framepack_eye_height +
                                         display->framepack_gap / 2;
            const uint32_t target_eye = switch_line > 220
                                      ? switch_line - 220 : switch_line;
            const uint32_t target_frame = total > 220 ? total - 220 : 0;
            uint32_t beam = beam_position(display->stereo_display);
            static unsigned beam_samples;
            if (beam_samples < 24)
                msg_Dbg(gl, "GL1 dual-beam sample %u: start %u, targets %u/%u",
                        ++beam_samples, beam, target_eye, target_frame);
            /* The second safe point is the measured 2205 -> 0 frame wrap.
             * The closest target is at most half a 24 Hz frame away, so this
             * synchronous wait still returns well before the next picture.
             * Keep it active: 10.6's timed sleeps routinely miss the narrow
             * HDMI blank, whereas this output thread has fixed RR priority. */
            const vlc_tick_t deadline = mdate() + 25000;
            while (mdate() < deadline)
            {
                beam = beam_position(display->stereo_display) % total;
                const uint32_t eye_distance =
                    (target_eye + total - beam) % total;
                const uint32_t frame_distance =
                    (target_frame + total - beam) % total;
                if (eye_distance <= 20 || eye_distance >= total - 20 ||
                    frame_distance <= 20 || frame_distance >= total - 20)
                    break;
            }
        }
    }
    [[sys->glView openGLContext] flushBuffer];
}

/*****************************************************************************
 * Our NSView object
 *****************************************************************************/
@implementation VLCGL1VideoView

+ (void)getNewView:(NSValue *)value
{
    id *ret = [value pointerValue];
    *ret = [[self alloc] init];
}

/**
 * Gets called by the Open() method.
 */
- (id)init
{
    VLCAssertMainThread();

    NSOpenGLPixelFormatAttribute attribs[] =
    {
        getenv("VLC_GL1_TRIPLE_BUFFER") != NULL
            /* The attribute has always had value 3, but the 10.4 SDK does
             * not expose its modern AppKit enum name. It is only attempted
             * when the diagnostic environment switch is explicitly set. */
            ? (NSOpenGLPixelFormatAttribute)3 : NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        NSOpenGLPFANoRecovery,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize, 8,
        NSOpenGLPFADepthSize, 24,
        NSOpenGLPFAWindow,
        0
    };

    NSOpenGLPixelFormat *fmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];

    /* The GeForce 320M advertises the legacy triple-buffer token but its
     * Snow Leopard window pixel format rejects it.  Never let an optional
     * latency experiment take the whole video output down. */
    if (!fmt && getenv("VLC_GL1_TRIPLE_BUFFER") != NULL)
    {
        attribs[0] = NSOpenGLPFADoubleBuffer;
        fmt = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];
    }

    if (!fmt)
        return nil;

    self = [super initWithFrame:NSMakeRect(0,0,10,10) pixelFormat:fmt];
    [fmt release];

    if (!self)
        return nil;

    /* Swap buffers only during the vertical retrace of the monitor.
     *
     * Not made optional: turning it off was tried and measured on an
     * iBook G3 (2026-08-07). It does remove the wait -- swap fell from
     * 13.8 ms to 0.43 ms per frame -- and changes the display punctuality
     * not at all, because that wait is wall time on a BLOCKED thread and
     * the machine already had a quarter of its processor idle. What it
     * does do is break the picture: black screen, then a slideshow, since
     * the double-buffer handling here counts on a synchronised swap. */
    GLint params[] = { 1 };
    /* No CGL context to set it on below 10.3 (see vlc_CGLContextOf): the
     * output then simply swaps without waiting for the retrace. */
    CGLContextObj swapCtx = vlc_CGLContextOf([self openGLContext]);
    if (swapCtx != NULL)
        CGLSetParameter (swapCtx, kCGLCPSwapInterval, params);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(applicationDidChangeScreenParameters:)
                                                 name:NSApplicationDidChangeScreenParametersNotification
                                               object:[NSApplication sharedApplication]];

    [self setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    return self;
}

- (void)applicationDidChangeScreenParameters:(NSNotification *)notification
{
    [self performSelectorOnMainThread:@selector(reshape)
                           withObject:nil
                        waitUntilDone:NO];
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

/**
 * Gets called by the Close and Open methods.
 * (Non main thread).
 */
- (void)setVoutDisplay:(vout_display_t *)aVd
{
    @synchronized(self) {
        vd = aVd;
    }
    if (aVd != NULL) {
        aVd->sys->vsync_requested = var_InheritBool (aVd, "gl1-vsync");
        GLint interval[] = { aVd->sys->vsync_requested ? 1 : 0 };
        CGLContextObj context = vlc_CGLContextOf([self openGLContext]);
        if (context != NULL) {
            CGLSetParameter (context, kCGLCPSwapInterval, interval);
            aVd->sys->swap_interval = interval[0];
        }
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

/* Final page flip for the asynchronous Snow Leopard/GeForce 320M presenter.
 * This must run on AppKit's main thread: flushing the same NSOpenGL window
 * surface from a private pthread succeeds nominally but never becomes visible
 * on this driver. */
- (void)vlcAsyncSwap
{
    VLCAssertMainThread();
    vout_display_t *display = NULL;
    @synchronized(self) {
        display = vd;
    }
    if (display == NULL || display->sys == NULL ||
        !display->sys->presenter_started)
        return;

    /* Do not call vlc_gl_MakeCurrent here.  NSOpenGLView can enter this main
     * thread while AppKit already owns the CGL window-surface mutex; taking
     * CGLLockContext a second time deadlocks (observed on 10.6.8/320M after
     * two or three flips).  The double GPU snapshot path prevents the vout
     * thread from changing the texture selected for this presentation. */
    NSOpenGLContext *context = [self openGLContext];
    [context makeCurrentContext];
    CGLContextObj cgl = vlc_CGLContextOf(context);
    if (cgl != NULL && display->sys->swap_interval != 1) {
        GLint interval[] = { 1 };
        CGLSetParameter(cgl, kCGLCPSwapInterval, interval);
        display->sys->swap_interval = 1;
        msg_Dbg(display, "GL1 asynchronous HDMI presenter uses driver VSync");
    }
    [context flushBuffer];
    [NSOpenGLContext clearCurrentContext];

    GL1PresenterDidFlip(display->sys);
}

/**
 * Chantier S — publie l'incrustation préparée par le thread vout dans une
 * fenêtre ENFANT transparente posée au-dessus de la fenêtre vidéo.
 * ⚠ THREAD PRINCIPAL obligatoire (AppKit) : appelé via
 * performSelectorOnMainThread depuis PictureDisplay.
 * ⚠ Ne JAMAIS envoyer `setOpaque:` à une vue : c'est une méthode de NSWindow,
 * pas de NSView — l'exception « unrecognized selector » qui en résulte est
 * avalée par le perform et abandonne silencieusement la méthode.
 */
/* ★★ RÉPARATION DU SCINTILLEMENT 10.3 (images fantômes sur la surface GPU).
 *
 * Symptôme : quelques secondes après l'engagement du décodage matériel, le
 * WindowServer cesse de composer correctement notre surface accélérée et
 * mêle à l'image des restes d'images voisines. Un CLIC SOURIS de l'utilisateur
 * n'importe où sur la fenêtre répare définitivement (état collant).
 *
 * Ce qui a été établi expérimentalement (banc /tmp/hw_cmd) et par
 * DÉSASSEMBLAGE de CoreGraphics 10.3 :
 *  - le clic doit VRAIMENT traverser le WindowServer : un NSEvent posté dans
 *    notre propre file ne répare pas ; un mouvement seul, un bouton du milieu
 *    ou UpdateSystemActivity non plus ;
 *  - dans `CGXFlushSurface`, le blit accéléré `IOAccelFlushSurfaceOnFrame-
 *    buffers` exige des drapeaux + un masque de framebuffer armés par
 *    `__CGXActivateSurfaces` / `__CGXSynchronizeSurfaceVisibility` ;
 *  - MAIS aucun des appels client menant à `CGXRedrawDisplay` ne répare :
 *    ordre, niveau, tags, ombre, alpha, opacité, forme, fenêtre de devant,
 *    focus souris, synchro accélérateur, réactivation d'update, déplacement
 *    de fenêtre, redessin/flush AppKit, activation de l'application.
 *  - SEUL `-[NSWindow orderWindow:NSWindowAbove relativeTo:0]` répare —
 *    alors que `CGSOrderWindow` BRUT sur la même fenêtre ne répare PAS.
 *    AppKit fait donc plus que l'ordre CGS en remettant la fenêtre en place
 *    (ré-attache du drawable GL, très probablement), et c'est cela qui réarme
 *    la composition accélérée.
 *
 * On rejoue donc cet ordre AppKit après chaque engagement du present matériel
 * (et après tout changement de géométrie : bascule plein écran, resize).
 * Garde-fou : seulement si notre application est ACTIVE — sinon remonter la
 * fenêtre passerait devant l'app que l'utilisateur est en train d'utiliser
 * (et un film démarré en arrière-plan ne souffre pas du défaut). */
/* ★ BANC D'ESSAI « pourquoi le clic répare » (10.3).
 * Écrire un numéro dans /tmp/hw_cmd fait exécuter UNE fois le remède candidat
 * correspondant, sur le thread principal, sans rebuild ni relance — de quoi
 * essayer des dizaines de pistes sur UN SEUL état cassé. Le résultat de chaque
 * essai est jugé à l'œil par l'utilisateur.
 * Le candidat 1 est LE discriminateur : un NSEvent posté dans NOTRE file
 * d'événements ne passe PAS par le WindowServer. S'il répare, le remède est
 * dans le traitement AppKit du clic (côté app) ; s'il ne répare pas, il est
 * dans le serveur. */
- (void)vlcTryRemedy:(NSNumber *)num
{
    VLCAssertMainThread();
    const int c = [num intValue];
    NSWindow *win = [self window];
    if (win == nil) {
        fprintf(stderr, "REMEDE %d : pas de fenêtre\n", c);
        return;
    }
    int wid = (int) [win windowNumber];
    void *as = dlopen("/System/Library/Frameworks/ApplicationServices.framework"
                      "/ApplicationServices", RTLD_NOW | RTLD_GLOBAL);
    /* ⚠ chaîne de connexion : CGSMainConnectionID n'est pas toujours visible
     * par dlsym sur l'umbrella (sous-frameworks) — mêmes replis que le
     * backend, sinon cid=0 et TOUS les appels CGS sont des non-op silencieux. */
    int (*MainConn)(void)    = as ? dlsym(as, "CGSMainConnectionID") : NULL;
    int (*QDConn)(void)      = as ? dlsym(as, "GetCGSConnectionID") : NULL;
    int (*ActiveConn)(int *) = as ? dlsym(as, "CGSGetActiveConnection") : NULL;
    int cid = 0;
    if (MainConn) cid = MainConn();
    if (!cid && QDConn) cid = QDConn();
    if (!cid && ActiveConn) ActiveConn(&cid);
    const char *what = "?";

    switch (c) {
    case 1: {   /* NSEvent synthétique — n'atteint QUE notre app */
        NSPoint p = [self convertPoint:NSMakePoint(NSMidX([self bounds]),
                                                   NSMidY([self bounds]))
                                toView:nil];
        NSEvent *d = [NSEvent mouseEventWithType:NSLeftMouseDown location:p
                        modifierFlags:0 timestamp:0 windowNumber:wid
                              context:nil eventNumber:0 clickCount:1 pressure:1.0];
        NSEvent *u = [NSEvent mouseEventWithType:NSLeftMouseUp location:p
                        modifierFlags:0 timestamp:0 windowNumber:wid
                              context:nil eventNumber:0 clickCount:1 pressure:0.0];
        [NSApp postEvent:d atStart:NO];
        [NSApp postEvent:u atStart:NO];
        what = "NSEvent clic posté dans notre file (hors serveur)";
        break;
    }
    case 2:
        [win display];
        what = "[win display]";
        break;
    case 3:
        [win makeKeyAndOrderFront:nil];
        what = "makeKeyAndOrderFront";
        break;
    case 4:
        [NSApp activateIgnoringOtherApps:YES];
        what = "activateIgnoringOtherApps";
        break;
    case 5: {
        int (*FlushWin)(int, int, int) = as ? dlsym(as, "CGSFlushWindow") : NULL;
        if (FlushWin) FlushWin(cid, wid, 0);
        what = FlushWin ? "CGSFlushWindow" : "CGSFlushWindow ABSENT";
        break;
    }
    case 6: {
        int (*OrderWin)(int, int, int, int) = as ? dlsym(as, "CGSOrderWindow") : NULL;
        if (OrderWin) OrderWin(cid, wid, 1, 0);
        what = OrderWin ? "CGSOrderWindow(above)" : "CGSOrderWindow ABSENT";
        break;
    }
    case 7: {
        int (*SetLvl)(int, int, int) = as ? dlsym(as, "CGSSetWindowLevel") : NULL;
        int (*GetLvl)(int, int, int *) = as ? dlsym(as, "CGSGetWindowLevel") : NULL;
        int lvl = 0;
        if (GetLvl) GetLvl(cid, wid, &lvl);
        if (SetLvl) SetLvl(cid, wid, lvl);
        what = SetLvl ? "CGSSetWindowLevel (même niveau)" : "CGSSetWindowLevel ABSENT";
        break;
    }
    case 8: {
        int (*Dis)(int)  = as ? dlsym(as, "CGSDisableUpdate") : NULL;
        int (*Reen)(int) = as ? dlsym(as, "CGSReenableUpdate") : NULL;
        if (Dis && Reen) { Dis(cid); Reen(cid); }
        what = (Dis && Reen) ? "CGSDisable/ReenableUpdate" : "CGSDisableUpdate ABSENT";
        break;
    }
    case 9:
        [win setViewsNeedDisplay:YES];
        [win displayIfNeeded];
        [win flushWindow];
        what = "setViewsNeedDisplay + displayIfNeeded + flushWindow";
        break;
    case 10:
        [win invalidateShadow];
        what = "invalidateShadow";
        break;
    case 11:
        [win setHasShadow:NO];
        [win setHasShadow:YES];
        what = "setHasShadow NO/YES (recalcul de forme serveur)";
        break;
    case 12: {   /* re-poser la forme de fenêtre côté serveur */
        NSRect f = [win frame];
        [win setFrame:NSMakeRect(f.origin.x, f.origin.y,
                                 f.size.width, f.size.height) display:YES];
        what = "setFrame identique + display";
        break;
    }
    case 13: {   /* déplacement RÉEL de fenêtre côté serveur, puis retour */
        int (*MoveWin)(int, int, const CGPoint *) = as ? dlsym(as, "CGSMoveWindow") : NULL;
        NSRect f = [win frame];
        float scr_h = [[[NSScreen screens] objectAtIndex:0] frame].size.height;
        CGPoint o1, o0;
        o0.x = f.origin.x; o0.y = scr_h - (f.origin.y + f.size.height);
        o1.x = o0.x + 1;   o1.y = o0.y;
        if (MoveWin) { MoveWin(cid, wid, &o1); MoveWin(cid, wid, &o0); }
        what = MoveWin ? "CGSMoveWindow +1/-1" : "CGSMoveWindow ABSENT";
        break;
    }
    /* ==== candidats issus du DÉSASSEMBLAGE de CoreGraphics 10.3 ==========
     * Chemin de composition accélérée établi statiquement :
     *   CGXFlushSurface → (surf->0x1c & 0x10000000) && surf->0xc==2
     *                  && surf->0x40 && surf->0x44 && !CGXAreUpdatesDisabled
     *                  → IOAccelFlushSurfaceOnFramebuffers
     * et l'armement de surf->0x40/0x44 se fait dans __CGXActivateSurfaces /
     * __CGXSynchronizeSurfaceVisibility, atteints depuis CGXRedrawDisplay
     * (ordre, niveau, tags, ombre, alpha, forme, réactivation d'update…). */
    case 20: {   /* état vu du PROPRIÉTAIRE (les getters exigent l'ownership) */
        int (*SurfCount)(int, int, int *)  = as ? dlsym(as, "CGSGetSurfaceCount") : NULL;
        int (*Seed)(int, int, int *)       = as ? dlsym(as, "CGSGetWindowFlushSeed") : NULL;
        int (*GetTags)(int, int, int *, int) = as ? dlsym(as, "CGSGetWindowTags") : NULL;
        int sc = -1, s1 = -1, s2 = -1, tg[2] = { 0, 0 };
        if (SurfCount) SurfCount(cid, wid, &sc);
        if (Seed) Seed(cid, wid, &s1);
        if (GetTags) GetTags(cid, wid, tg, 32);
        usleep(300000);
        if (Seed) Seed(cid, wid, &s2);
        fprintf(stderr, "ETAT wid=%d surfaces=%d seed %d→%d tags=%08x/%08x\n",
                wid, sc, s1, s2, tg[0], tg[1]);
        what = "relevé d'état";
        break;
    }
    case 21: {
        int (*SetLvl)(int, int, int) = as ? dlsym(as, "CGSSetWindowLevel") : NULL;
        int (*GetLvl)(int, int, int *) = as ? dlsym(as, "CGSGetWindowLevel") : NULL;
        int lvl = 0;
        if (GetLvl) GetLvl(cid, wid, &lvl);
        if (SetLvl) SetLvl(cid, wid, lvl);
        what = SetLvl ? "CGSSetWindowLevel (identique)" : "ABSENT";
        break;
    }
    case 22: {
        int (*SetTags)(int, int, int *, int) = as ? dlsym(as, "CGSSetWindowTags") : NULL;
        int (*GetTags)(int, int, int *, int) = as ? dlsym(as, "CGSGetWindowTags") : NULL;
        int tg[2] = { 0, 0 };
        if (GetTags) GetTags(cid, wid, tg, 32);
        if (SetTags) SetTags(cid, wid, tg, 32);
        what = SetTags ? "CGSSetWindowTags (identiques)" : "ABSENT";
        break;
    }
    case 23: {
        int (*Inval)(int, int) = as ? dlsym(as, "CGSInvalidateWindowShadow") : NULL;
        if (Inval) Inval(cid, wid);
        what = Inval ? "CGSInvalidateWindowShadow" : "ABSENT";
        break;
    }
    case 24: {
        int (*SetA)(int, int, float) = as ? dlsym(as, "CGSSetWindowAlpha") : NULL;
        if (SetA) { SetA(cid, wid, 0.99f); usleep(30000); SetA(cid, wid, 1.0f); }
        what = SetA ? "CGSSetWindowAlpha 0.99→1.0" : "ABSENT";
        break;
    }
    case 25: {
        int (*SetOp)(int, int, int) = as ? dlsym(as, "CGSSetWindowOpacity") : NULL;
        if (SetOp) { SetOp(cid, wid, 0); usleep(30000); SetOp(cid, wid, 1); }
        what = SetOp ? "CGSSetWindowOpacity 0→1" : "ABSENT";
        break;
    }
    case 26: {
        int (*Front)(int, int) = as ? dlsym(as, "CGSSetFrontWindow") : NULL;
        if (Front) Front(cid, wid);
        what = Front ? "CGSSetFrontWindow" : "ABSENT";
        break;
    }
    case 27: {
        int (*MouseFoc)(int, int) = as ? dlsym(as, "CGSSetMouseFocusWindow") : NULL;
        if (MouseFoc) MouseFoc(cid, wid);
        what = MouseFoc ? "CGSSetMouseFocusWindow (ce qu'un clic établit)" : "ABSENT";
        break;
    }
    case 28: {
        int (*Sync)(int, int, int, int, int) =
            as ? dlsym(as, "CGSSynchronizeWindowAccelerator") : NULL;
        int rc = -1;
        if (Sync) rc = Sync(cid, wid, 1, 0, 0);
        fprintf(stderr, "  CGSSynchronizeWindowAccelerator rc=%d\n", rc);
        what = Sync ? "CGSSynchronizeWindowAccelerator" : "ABSENT";
        break;
    }
    case 29: {
        int (*SendExp)(int, int, int) = as ? dlsym(as, "CGSSetWindowSendExposed") : NULL;
        if (SendExp) { SendExp(cid, wid, 1); }
        what = SendExp ? "CGSSetWindowSendExposed(1)" : "ABSENT";
        break;
    }
    case 30: {   /* re-poser la FORME : passe par FinalizeGeometryChange */
        int (*GetShape)(int, int, void **) = as ? dlsym(as, "CGSGetWindowShape") : NULL;
        int (*SetShape)(int, int, int, int, void *) =
            as ? dlsym(as, "CGSSetWindowShape") : NULL;
        void *rgn = NULL;
        if (GetShape && SetShape && GetShape(cid, wid, &rgn) == 0 && rgn)
            SetShape(cid, wid, 0, 0, rgn);
        what = SetShape ? "CGSSetWindowShape (forme courante)" : "ABSENT";
        break;
    }
    /* ★ makeKeyAndOrderFront RÉPARE (validé 29/07). Or l'ordre seul
     * (CGSOrderWindow, AppKit orderWindow:) et l'activation d'app échouent :
     * c'est la partie « fenêtre CLÉ » qui porte le remède. On cherche ici la
     * forme MINIMALE — makeKeyWindow seul serait idéal (ne remonte pas la
     * fenêtre au premier plan, donc ne vole pas le focus à une autre app). */
    case 31:
        [win makeKeyWindow];
        what = "makeKeyWindow (sans remontée au premier plan)";
        break;
    case 32:
        [win orderWindow:NSWindowAbove relativeTo:0];
        what = "orderWindow:above (sans fenêtre clé)";
        break;
    case 33:
        [win resignKeyWindow];
        [win makeKeyWindow];
        what = "resignKeyWindow puis makeKeyWindow";
        break;
    /* orderWindow:above RÉPARE alors que CGSOrderWindow (brut) NON : AppKit
     * fait davantage en mettant la fenêtre en ordre. Hypothèse : la
     * ré-attache du contexte GL au drawable (CGLUpdateContext), qui réarme la
     * liste de surfaces de la fenêtre côté serveur. Ces deux candidats
     * cherchent la forme minimale, SANS toucher à l'ordre des fenêtres. */
    case 34:
        [[self openGLContext] update];
        what = "[[self openGLContext] update] (CGLUpdateContext)";
        break;
    case 35:
        [[self openGLContext] setView:self];
        what = "[[self openGLContext] setView:] (ré-attache du drawable)";
        break;
    /* ★ En PLEIN ÉCRAN, cliquer la vidéo ne répare pas, mais cliquer le
     * PANNEAU DE CONTRÔLES (une AUTRE fenêtre) répare — et ça tient même
     * après sa disparition. Le remède est donc un vrai CHANGEMENT DE LA LISTE
     * DES FENÊTRES de l'application, pas une action sur la fenêtre vidéo
     * elle-même (d'où l'échec de orderWindow:above en plein écran : la
     * fenêtre y est déjà seule et devant, l'appel ne change rien).
     * On fabrique donc ce changement avec une fenêtre auxiliaire 1×1
     * entièrement transparente : ordonnée devant, puis retirée. */
    case 36: {
        NSWindow *h = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 1, 1)
                      styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [h setLevel:[win level] + 1];
        [h setOpaque:NO];
        [h setBackgroundColor:[NSColor clearColor]];
        [h setHasShadow:NO];
        [h orderFront:nil];
        [h orderOut:nil];
        [h release];
        what = "fenêtre auxiliaire 1x1 ordonnée devant puis retirée";
        break;
    }
    case 37: {   /* variante : ordonner la fenêtre VIDÉO au-dessus de l'auxiliaire */
        NSWindow *h = [[NSWindow alloc]
            initWithContentRect:NSMakeRect(0, 0, 1, 1)
                      styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered
                          defer:NO];
        [h setLevel:[win level]];
        [h setOpaque:NO];
        [h setBackgroundColor:[NSColor clearColor]];
        [h setHasShadow:NO];
        [h orderFront:nil];
        [win orderWindow:NSWindowAbove relativeTo:[h windowNumber]];
        [h orderOut:nil];
        [h release];
        what = "vidéo ordonnée au-dessus d'une fenêtre auxiliaire";
        break;
    }
    /* En plein écran, seul le clic sur le PANNEAU DE CONTRÔLES répare. Ce
     * panneau diffère de mes auxiliaires 1×1 sur deux points : il est OPAQUE
     * et RECOUVRE la vidéo (donc il l'obscurcit puis la ré-expose), et il
     * reçoit un VRAI clic. On sépare les deux ingrédients. */
    case 38: {   /* recouvrement opaque SANS clic */
        NSRect wf = [win frame];
        NSRect hr = NSMakeRect(NSMidX(wf) - 60, NSMinY(wf) + 60, 120, 60);
        NSWindow *h = [[NSWindow alloc]
            initWithContentRect:hr styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered defer:NO];
        [h setLevel:[win level] + 1];
        [h setBackgroundColor:[NSColor blackColor]];
        [h setHasShadow:NO];
        [h orderFront:nil];
        [h display];
        usleep(120000);
        [h orderOut:nil];
        [h release];
        what = "recouvrement opaque de la vidéo, sans clic";
        break;
    }
    case 39: {   /* recouvrement opaque AVEC un vrai clic dessus (inerte) */
        NSRect wf = [win frame];
        NSRect hr = NSMakeRect(NSMidX(wf) - 60, NSMinY(wf) + 60, 120, 60);
        NSWindow *h = [[NSWindow alloc]
            initWithContentRect:hr styleMask:NSBorderlessWindowMask
                        backing:NSBackingStoreBuffered defer:NO];
        [h setLevel:[win level] + 1];
        [h setBackgroundColor:[NSColor blackColor]];
        [h setHasShadow:NO];
        [h orderFront:nil];
        [h display];
        float scr_h = [[[NSScreen screens] objectAtIndex:0] frame].size.height;
        CGPoint p;
        p.x = (float) NSMidX(hr);
        p.y = scr_h - (float) NSMidY(hr);
        CGPostMouseEvent(p, 1, 1, 1);
        usleep(40000);
        CGPostMouseEvent(p, 1, 1, 0);
        usleep(40000);
        [h orderOut:nil];
        [h release];
        what = "recouvrement opaque + vrai clic dessus";
        break;
    }
    /* ★★ THÉORIE UNIFIÉE (29/07) : l'image n'est propre que TANT QU'UNE AUTRE
     * FENÊTRE RECOUVRE la vidéo (panneau de contrôles en plein écran). Sinon
     * le serveur prend le chemin RAPIDE : il donne la surface accélérée
     * directement au framebuffer, et c'est CE chemin qui rend mal ici.
     * `__CGXActivateSurfaces` refuse le chemin direct si (entre autres)
     * l'ALPHA DE LA FENÊTRE EST < 1.0 — condition réglable par le client.
     * On la pose donc EN PERMANENCE (0.99 : invisible à l'œil). */
    case 40:
        [win setAlphaValue:0.99f];
        what = "alpha de fenêtre 0.99 PERMANENT (force la composition)";
        break;
    case 41:
        [win setOpaque:NO];
        what = "fenêtre marquée non opaque (persistant)";
        break;
    case 42:
        [win setAlphaValue:1.0f];
        [win setOpaque:YES];
        what = "retour alpha 1.0 + opaque (annule 40/41)";
        break;
    /* ★ Piste « recouvrement permanent » : une fenêtre opaque, même minuscule,
     * posée AU-DESSUS de la fenêtre vidéo interdit le chemin direct (la
     * surface n'est plus intégralement visible) et force la composition — mais
     * par simple COPIE, sans le mélange par pixel que coûte un alpha < 1.
     * C'est exactement la situation « panneau de contrôles affiché », que la
     * machine a montrée nette ET fluide. */
    /* Le recouvrement OPAQUE, même visible à l'écran, ne suffit pas en plein
     * écran alors que le PANNEAU DE CONTRÔLES, lui, suffit. Différences
     * candidates : ombre portée, translucidité, taille/position. */
    case 51:   /* ★ la recette du panneau de contrôles : NON OPAQUE + fond clair */
        [self vlcHwEnsureCover];
        [s_gl1_cover setOpaque:NO];
        [s_gl1_cover setBackgroundColor:[NSColor clearColor]];
        [s_gl1_cover setAlphaValue:1.0f];
        [s_gl1_cover orderOut:nil];
        [s_gl1_cover orderFront:nil];
        what = "recouvrement NON OPAQUE à fond transparent (invisible)";
        break;
    case 48:
        [self vlcHwEnsureCover];
        [s_gl1_cover setHasShadow:YES];
        [s_gl1_cover orderOut:nil];
        [s_gl1_cover orderFront:nil];
        what = "recouvrement AVEC ombre portée";
        break;
    case 49:
        [self vlcHwEnsureCover];
        [s_gl1_cover setAlphaValue:0.90f];
        what = "recouvrement TRANSLUCIDE (alpha 0.9)";
        break;
    case 50: {   /* même gabarit que le panneau de contrôles */
        [self vlcHwEnsureCover];
        NSRect wf = [win frame];
        NSRect fs = NSMakeRect(wf.origin.x + (wf.size.width - 315) / 2,
                               wf.origin.y + 100, 315, 31);
        [s_gl1_cover setFrame:fs display:YES];
        [s_gl1_cover setHasShadow:YES];
        [s_gl1_cover orderFront:nil];
        what = "recouvrement au gabarit du panneau de contrôles";
        break;
    }
    case 46: {   /* re-présenter le RECOUVREMENT (autre fenêtre) */
        [self vlcHwEnsureCover];
        [s_gl1_cover orderOut:nil];
        [s_gl1_cover orderFront:nil];
        what = "recouvrement retiré puis re-présenté";
        break;
    }
    case 47: {   /* vrai clic SUR le recouvrement (= clic sur une autre fenêtre) */
        [self vlcHwEnsureCover];
        [s_gl1_cover setIgnoresMouseEvents:NO];
        NSRect cf = [s_gl1_cover frame];
        float scr_h = [[[NSScreen screens] objectAtIndex:0] frame].size.height;
        CGPoint p;
        p.x = (float) NSMidX(cf);
        p.y = scr_h - (float) NSMidY(cf);
        CGPostMouseEvent(p, 1, 1, 1);
        usleep(40000);
        CGPostMouseEvent(p, 1, 1, 0);
        what = "clic synthétique sur le pixel de recouvrement";
        break;
    }
    case 43: case 44: case 45: {   /* A/B de la TAILLE du recouvrement */
        s_gl1_cover_side = (c == 43) ? 1 : (c == 44) ? 8 : 32;
        if (s_gl1_cover != nil) {
            [s_gl1_cover orderOut:nil];
            [s_gl1_cover release];
            s_gl1_cover = nil;
        }
        [self vlcHwEnsureCover];
        what = "recouvrement du coin de la SURFACE (taille A/B)";
        break;
    }
    default:
        what = "candidat inconnu";
        break;
    }
    fprintf(stderr, "REMEDE %d : %s (cid=%d wid=%d)\n", c, what, cid, wid);
}

/* ★★★ CORRECTIF DU SCINTILLEMENT (10.3, surface GPU en mode remplacement).
 *
 * Mécanisme établi par rétro-ingénierie de CoreGraphics 10.3 + essais sur
 * machine : tant que la fenêtre vidéo est intégralement visible et opaque, le
 * WindowServer donne notre surface accélérée DIRECTEMENT au framebuffer
 * (chemin refusé par `__CGXActivateSurfaces` dès que la surface est
 * partiellement masquée, la fenêtre translucide, zoomée ou transformée).
 * Ce chemin direct affiche des images mêlées avec le pilote ATI de cette
 * machine — d'où le « scintillement ». Vérifié à l'oeil : poser N'IMPORTE
 * QUELLE fenêtre par-dessus l'image l'arrête instantanément, la retirer le
 * ramène ; en plein écran, le panneau de contrôles joue ce rôle.
 *
 * Un alpha < 1 marche aussi mais coûte un mélange par pixel (saccadé sur G3).
 * On masque donc UN SEUL PIXEL de la surface, dans son coin : la composition
 * reprend, par simple copie, et le pixel est invisible à l'oeil. */
+ (void)vlcHideCursor
{
    VLCAssertMainThread();
    [NSCursor setHiddenUntilMouseMoves:YES];
    /* En PLEIN ÉCRAN le masquage ne tenait pas : le panneau de contrôles
     * s'efface peu après (fondu, retrait de fenêtre) et AppKit réaffiche le
     * pointeur au passage, alors que le coeur, lui, ne redemandera un
     * masquage qu'après une nouvelle période d'inactivité. On ré-arme donc
     * deux fois, à 1 et 2 s — sans effet si le pointeur a réellement bougé,
     * puisque -setHiddenUntilMouseMoves: se désarme de lui-même. */
    [self performSelector:@selector(vlcHideCursorAgain)
               withObject:nil afterDelay:1.0];
    [self performSelector:@selector(vlcHideCursorAgain)
               withObject:nil afterDelay:2.0];
}

+ (void)vlcHideCursorAgain
{
    VLCAssertMainThread();
    [NSCursor setHiddenUntilMouseMoves:YES];
}

- (void)vlcHwEnsureCover
{
    VLCAssertMainThread();
    NSWindow *win = [self window];
    vout_display_t *v;
    @synchronized (self) { v = vd; }
    if (win == nil || v == NULL || ![win isVisible])
        return;

    int hx, hy, hw_, hh;
    BOOL ok;
    @synchronized (self) {
        ok  = v->sys->hw_place_valid;
        hx  = v->sys->hw_x;  hy = v->sys->hw_y;
        hw_ = v->sys->hw_w;  hh = v->sys->hw_h;
    }
    if (!ok || hw_ <= 0 || hh <= 0)
        return;

    /* hx/hy sont en coordonnées FENÊTRE, origine en HAUT à gauche (ce sont
     * celles passées à CGSSetSurfaceBounds) ; NSWindow travaille en origine
     * BAS à gauche → on retourne verticalement. */
    NSRect wf = [win frame];
    NSRect cover = NSMakeRect(wf.origin.x + hx,
                              wf.origin.y + wf.size.height - (hy + hh),
                              s_gl1_cover_side, s_gl1_cover_side);

    if (s_gl1_cover != nil) {
        [s_gl1_cover setFrame:cover display:NO];
        [s_gl1_cover setLevel:[win level] + 1];
        if (![s_gl1_cover isVisible])
            [s_gl1_cover orderFront:nil];
        return;
    }
    s_gl1_cover = [[NSWindow alloc] initWithContentRect:cover
                                              styleMask:NSBorderlessWindowMask
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    [s_gl1_cover setLevel:[win level] + 1];
    /* ⚠ NON OPAQUE et fond TRANSPARENT — c'est le point décisif, et c'est
     * aussi la recette du panneau de contrôles plein écran (VLCLegacyFSPanel),
     * dont l'apparition suffisait à nettoyer l'image. Un recouvrement OPAQUE
     * ne marche PAS : le serveur se contente alors de le découper et continue
     * d'envoyer le reste de la surface directement au framebuffer (vérifié à
     * l'oeil : carré noir bien visible, scintillement intact). Une fenêtre
     * non opaque, elle, l'oblige à MÉLANGER, donc à composer la surface. */
    [s_gl1_cover setOpaque:NO];
    [s_gl1_cover setBackgroundColor:[NSColor clearColor]];
    [s_gl1_cover setHasShadow:NO];
    [s_gl1_cover setIgnoresMouseEvents:YES];
    [s_gl1_cover orderFront:nil];
}

/* Le recouvrement seul ne suffit PAS : tant que le serveur n'a pas RECALCULÉ
 * la visibilité des surfaces de la fenêtre, la surface continue d'être
 * envoyée directement au framebuffer — au point d'écraser à l'écran le pixel
 * de recouvrement lui-même (constaté : la fenêtre existe dans la liste mais
 * reste invisible). `-[NSWindow orderWindow:relativeTo:]` provoque ce
 * recalcul (l'appel CGS brut `CGSOrderWindow`, lui, ne suffit pas). Une fois
 * le recalcul fait avec le recouvrement en place, la décision « composer »
 * devient durable. */
- (void)vlcHwCoverAndRefresh
{
    VLCAssertMainThread();
    NSWindow *win = [self window];
    if (win == nil)
        return;
    /* ⚠ Ne RIEN faire si la fenêtre vidéo n'est pas à l'écran : l'interface
     * legacy la retire pour afficher la liste de lecture (elle héberge la vue
     * vidéo), et `-orderWindow:` la ramènerait aussitôt — la vidéo reprenait
     * le dessus dès le clic sur le bouton de la liste. */
    if (![win isVisible])
        return;
    [self vlcHwEnsureCover];
    [win orderWindow:NSWindowAbove relativeTo:0];
}

/* Forcer le serveur à RECALCULER la visibilité des surfaces de la fenêtre.
 * Appelé après un CGSOrderSurface d'escamotage : sans ce recalcul l'ordre est
 * accepté (rc=0) mais l'écran ne bouge pas. Contrairement à
 * -vlcHwCoverAndRefresh, on ne (re)pose PAS le pixel de recouvrement : quand la
 * vidéo est masquée il n'a plus rien à couvrir. Et pas de garde `isVisible`
 * ici — sous 10.4 c'est justement la fenêtre PRINCIPALE, toujours à l'écran,
 * qui héberge la vue vidéo masquée. */
- (void)vlcHwRecomputeSurfaces
{
    VLCAssertMainThread();
    NSWindow *win = [self window];
    if (win == nil || ![win isVisible])
        return;
    [win orderWindow:NSWindowAbove relativeTo:0];
}

/* Fin du mode remplacement (lecture logicielle, fermeture du vout) : retirer
 * le pixel de recouvrement et garantir une fenêtre pleinement opaque. */
- (void)vlcHwRestoreOpaque
{
    VLCAssertMainThread();
    if (s_gl1_cover != nil) {
        [s_gl1_cover orderOut:nil];
        [s_gl1_cover release];
        s_gl1_cover = nil;
    }
    NSWindow *win = [self window];
    if (win != nil && [win alphaValue] < 1.0f)
        [win setAlphaValue:1.0f];
}

- (void)refreshSubsOverlay
{
    VLCAssertMainThread();
    mtime_t t_refresh = mdate ();

    uint8_t *data = NULL;
    int ox = 0, oy = 0, ow = 0, oh = 0;   /* destination (coordonnées vue) */
    int bw = 0, bh = 0;                   /* taille du bitmap (source) */
    @synchronized (self) {
        if (vd == NULL)
            return;
        if (!vd->sys->ovl_pending)
            return;
        vd->sys->ovl_pending = false;
        /* Transfert de PROPRIÉTÉ du tampon au thread principal : le thread vout
         * ne doit plus le libérer sous les pieds de l'affichage. */
        data = vd->sys->ovl_data;
        vd->sys->ovl_data = NULL;
        ox = vd->sys->ovl_x; oy = vd->sys->ovl_y;
        ow = vd->sys->ovl_w; oh = vd->sys->ovl_h;
        bw = vd->sys->ovl_bw; bh = vd->sys->ovl_bh;
    }

    NSWindow *win = [self window];
    if (win == nil) {
        free (data);
        return;
    }

    /* ★★ PLEIN ÉCRAN : la vue vidéo CHANGE DE FENÊTRE. Sans fenêtre hôte
     * (le cas sous 10.3), `-setVideoFullscreenFromNumber:` crée une fenêtre
     * borderless et y déplace la vue. L'incrustation, elle, restait enfant de
     * la fenêtre PRÉCÉDENTE : toujours au-dessus d'ELLE, mais sous la fenêtre
     * plein écran — plus un seul sous-titre ni OSD à l'écran, alors que tout
     * est composé et posé normalement. On la fait adopter par la fenêtre
     * courante, et on repart d'un cadre NEUF : l'union avec l'ancien cadre,
     * exprimé dans l'autre géométrie, aurait couvert n'importe quoi. */
    if (_subsOverlay != nil && _subsOverlayParent != nil
        && _subsOverlayParent != win) {
        [_subsOverlayParent removeChildWindow:_subsOverlay];
        [_subsOverlayParent release];
        [win addChildWindow:_subsOverlay ordered:NSWindowAbove];
        _subsOverlayParent = [win retain];
        _subsOverlayRect = NSZeroRect;
        @synchronized (self) {
            if (vd) msg_Dbg (vd, "incrustation ré-adoptée par la fenêtre %d "
                                 "(bascule plein écran)", (int) [win windowNumber]);
        }
    }

    /* Cadre = BOÎTE DU SOUS-TITRE, et rien de plus : une version couvrant en
     * permanence tout le rectangle vidéo a été essayée pour éviter les
     * redimensionnements — le WindowServer compose alors une fenêtre
     * transparente pleine image À CHAQUE IMAGE et la charge explose même sans
     * sous-titre. ⚠ Et JAMAIS de `orderOut:` tant que la vidéo joue : masquer
     * puis réafficher perturbe l'empilement de nos fenêtres imbriquées
     * (principale → hôte vidéo → incrustation) et fait DISPARAÎTRE puis
     * réapparaître la fenêtre vidéo entière. Quand il n'y a rien à afficher, on
     * vide le contenu et on réduit la fenêtre à 1×1 : invisible, sans coût de
     * composition, sans toucher à l'ordre des fenêtres. */
    if (data == NULL || ow <= 0 || oh <= 0 || bw <= 0 || bh <= 0) {
        free (data);
        /* ⚠ NI -orderOut: NI redimensionnement ici. Masquer/réafficher ré-empile
         * le groupe de fenêtres, et redimensionner fait scintiller la bande
         * correspondante (le temps d'un composite, le nouveau cadre n'est pas
         * encore dessiné) — sur un DVD, avec une réplique toutes les deux
         * secondes, cela se voit beaucoup. On se contente de VIDER le contenu :
         * la fenêtre reste en place, transparente. Le sous-titre suivant occupe
         * en général exactement le même cadre (même bande de bas d'image) →
         * aucun redimensionnement du tout. Retirée au démontage seulement. */
        [(VLCGL1SubsOverlayView *)[_subsOverlay contentView] setImage:NULL
                                                                 data:NULL
                                                                 rect:NSZeroRect];
        /* On VIDE seulement : ni masquage (il fait disparaître la fenêtre
         * vidéo entière), ni changement de cadre. Chaque -setFrame: coûte un
         * aller-retour synchrone avec le WindowServer — mesuré à ~7 ms de coût
         * FIXE, indépendant de la surface — et ce blocage du thread principal
         * retarde la présentation de l'image suivante : c'est la saccade
         * constatée à chaque apparition de sous-titre. */
        [_subsOverlay display];
        return;
    }

    /* Rectangle de destination (coordonnées VUE, origine haut-gauche) → écran. */
    NSRect vrect = NSMakeRect (ox, [self bounds].size.height - (oy + oh), ow, oh);
    NSRect wrect = [self convertRect:vrect toView:nil];
    NSPoint org  = [win convertBaseToScreen:wrect.origin];
    NSRect dest  = NSMakeRect (org.x, org.y, wrect.size.width, wrect.size.height);

    /* Cadre de la fenêtre : il ne RÉTRÉCIT jamais et ne bouge que s'il ne
     * contient pas la nouvelle incrustation. Les répliques d'un film occupent
     * la même bande de bas d'image : après les premières, plus aucun
     * -setFrame:, donc plus de saccade. Le prix est la composition permanente
     * d'une bande transparente — sans commune mesure avec la fenêtre pleine
     * image essayée auparavant. */
    NSRect frame = (_subsOverlayRect.size.width < 1)
                 ? dest : NSUnionRect (_subsOverlayRect, dest);
    NSRect repRect = NSMakeRect (dest.origin.x - frame.origin.x,
                                 dest.origin.y - frame.origin.y,
                                 dest.size.width, dest.size.height);

    if (_subsOverlay == nil) {
        _subsOverlay = [[NSWindow alloc] initWithContentRect:frame
                                                   styleMask:NSBorderlessWindowMask
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
        [_subsOverlay setOpaque:NO];
        [_subsOverlay setBackgroundColor:[NSColor clearColor]];
        [_subsOverlay setHasShadow:NO];
        [_subsOverlay setIgnoresMouseEvents:YES];
        [_subsOverlay setReleasedWhenClosed:NO];
        VLCGL1SubsOverlayView *ov = [[VLCGL1SubsOverlayView alloc]
            initWithFrame:NSMakeRect (0, 0, frame.size.width, frame.size.height)];
        [ov setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
        [ov setImage:NULL data:NULL rect:NSZeroRect];
        [_subsOverlay setContentView:ov];
        [ov release];
        /* ⚠ PAS d'-addChildWindow: ICI. Ajouter une fenêtre enfant à un parent
         * visible l'ORDONNE À L'ÉCRAN sur-le-champ — donc avant que son tampon
         * ait été peint : on voyait un FLASH BLANC pleine largeur au tout
         * premier sous-titre. L'adoption a lieu à la fin, une fois le contenu
         * dessiné (elle sert alors aussi de mise à l'écran). */
    }
    /* ⚠ Deux détails qui font la différence entre 3 ms et 30 ms de dessin sur
     * un G3 : alpha PRÉMULTIPLIÉ (seul chemin rapide de CoreGraphics) et espace
     * colorimétrique PÉRIPHÉRIQUE — avec un espace calibré, ColorSync convertit
     * chaque pixel à l'affichage. `CGImageCreate` donne les deux sur TOUTES les
     * versions, là où seul l'initialiseur `bitmapFormat:` de NSBitmapImageRep
     * (10.4) savait déclarer du prémultiplié alpha-en-tête (cf. le commentaire
     * de VLCGL1SubsOverlayView).
     * ⚠ HISTORIQUE : une garde `instancesRespondToSelector:` renvoyait tout de
     * suite quand cet initialiseur 10.4 manquait — elle rendait le repli 10.3
     * INATTEIGNABLE, et c'est ce qui laissait les sous-titres invisibles sur
     * Panther alors que tout le reste de la chaîne fonctionnait. */
    CGImageRef img = NULL;
    {
        CGDataProviderRef prov =
            CGDataProviderCreateWithData (NULL, data, (size_t) bw * bh * 4, NULL);
        CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB ();
        /* ⚠⚠ PAS DE DRAPEAU D'ORDRE D'OCTETS. Le champ vaut `CGImageAlphaInfo`
         * SEUL jusqu'à 10.3 : les `kCGBitmapByteOrder*` sont du 10.4, et sur
         * Panther tout bit en trop fait échouer CGImageCreate silencieusement
         * (NULL). Le poser sur 10.4 seulement — ce que je faisais — est la SEULE
         * branche de ce chemin réservée à Tiger, et c'est elle qui a FIGÉ LE GPU
         * de l'iBook trois fois de suite sous 10.4.11 (2026-07-30) alors que
         * Panther tournait parfaitement avec le même binaire.
         * Il est de toute façon REDONDANT partout où ce code tourne : sur
         * PowerPC l'ordre natif EST ARGB big-endian, ce qui est exactement
         * pourquoi son absence sur 10.2/10.3 ne change rien. Ne pas le remettre
         * sans une raison petit-boutiste ET une validation sur 10.4. */
        CGBitmapInfo info = kCGImageAlphaPremultipliedFirst;
        if (prov != NULL && cs != NULL)
            img = CGImageCreate ((size_t) bw, (size_t) bh, 8, 32,
                                 (size_t) bw * 4, cs, info,
                                 prov, NULL, false, kCGRenderingIntentDefault);
        if (cs != NULL)   CGColorSpaceRelease (cs);
        if (prov != NULL) CGDataProviderRelease (prov);
    }
    if (img == NULL) {
        free (data);
        @synchronized (self) {
            if (vd) msg_Warn (vd, "incrustation : CGImageCreate a échoué "
                                  "(%dx%d) — sous-titres invisibles", bw, bh);
        }
        return;
    }

    BOOL wasVisible = [_subsOverlay isVisible];
    mtime_t t_frame = mdate ();
    BOOL didSetFrame = NO;
    if (!NSEqualRects (frame, [_subsOverlay frame])) {
        if ([_subsOverlay respondsToSelector:
                @selector(disableScreenUpdatesUntilFlush)])
            [_subsOverlay disableScreenUpdatesUntilFlush];
        [_subsOverlay setFrame:frame display:NO];
        didSetFrame = YES;
    }
    t_frame = mdate () - t_frame;
    _subsOverlayRect = frame;
    [(VLCGL1SubsOverlayView *)[_subsOverlay contentView] setImage:img
                                                             data:data
                                                             rect:repRect];
    [[_subsOverlay contentView] setNeedsDisplay:YES];
    /* Remonter la fenêtre SEULEMENT quand elle n'est pas déjà affichée : la
     * relation parent/enfant ne suffit pas depuis le chantier F (la vidéo vit
     * dans une fenêtre hôte elle-même enfant de la principale, et 10.4 laisse
     * ce petit-enfant sous la pile), mais le faire à chaque mise à jour
     * re-empile tout le groupe et fait clignoter l'écran.
     * ⚠ `orderWindow:relativeTo:` a été essayé : il sort la fenêtre du groupe
     * géré par AppKit et fait remonter la fenêtre principale AU-DESSUS de la
     * vidéo plein écran. -orderFront: reste dans le groupe. */
    mtime_t t_draw = mdate ();
    VLCGL1SubsOverlayView *ovv = (VLCGL1SubsOverlayView *) [_subsOverlay contentView];
    ovv->_lastDrawUs = -1;
    {
        [_subsOverlay display];      /* dessiné AVANT d'être affiché */
        /* Fenêtre ENFANT : elle suit les déplacements de la fenêtre vidéo et
         * reste juste au-dessus d'elle (y compris en plein écran). Une fenêtre
         * indépendante placée par son niveau a été mesurée : même coût.
         * L'adoption ordonne aussi la fenêtre à l'écran — d'où sa place ICI,
         * après le dessin (cf. le flash blanc du premier sous-titre). */
        if (_subsOverlayParent != win) {
            if (_subsOverlayParent != nil) {
                [_subsOverlayParent removeChildWindow:_subsOverlay];
                [_subsOverlayParent release];
            }
            [win addChildWindow:_subsOverlay ordered:NSWindowAbove];
            _subsOverlayParent = [win retain];
        } else if (!wasVisible)
            [_subsOverlay orderFront:nil];
    }
    @synchronized (self) {
        if (vd)
            msg_Dbg (vd, "incrustation posée : %d us (setFrame %d us%s, "
                         "display %d us dont drawRect %d us, bitmap %dx%d)",
                     (int) (mdate () - t_refresh), (int) t_frame,
                     didSetFrame ? "" : " sauté", (int) (mdate () - t_draw),
                     ovv->_lastDrawUs, bw, bh);
    }
}

/**
 * Démonte la fenêtre de superposition (fermeture du vout). Thread principal.
 */
- (void)tearDownSubsOverlay
{
    VLCAssertMainThread();
    _subsOverlayRect = NSZeroRect;
    if (_subsOverlay == nil)
        return;
    [_subsOverlayParent removeChildWindow:_subsOverlay];
    [_subsOverlayParent release];
    _subsOverlayParent = nil;
    [_subsOverlay orderOut:nil];
    [_subsOverlay close];
    [_subsOverlay release];
    _subsOverlay = nil;
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
 * The gl lock is held by the caller.
 */
- (void)render
{
    VLCAssertMainThread();

    if ([self canSkipRendering])
        return;

    BOOL hasGLFrame;
    vout_display_t *aVd;
    @synchronized(self) { // vd can be accessed from multiple threads
        aVd = vd;
        hasGLFrame = vd && vd->sys->has_gl_frame;
    }

    if (hasGLFrame)
        /* redraw the last uploaded frame */
        OpenglDraw (aVd->sys);
    else
        glClear (GL_COLOR_BUFFER_BIT);

    [[self openGLContext] flushBuffer];
}

/**
 * Tracks whether we render into a borderless window covering its screen
 * (page-flipped presentation): the planar renderer picks its texture
 * storage hint from this. Main thread only.
 */
- (void)updateFullscreenFlag
{
    NSWindow *w = [self window];
    BOOL fs = NO;
    if (w && [w styleMask] == NSBorderlessWindowMask) {
        NSScreen *scr = [w screen];
        if (scr && NSContainsRect ([w frame], [scr frame]))
            fs = YES;
    }
    @synchronized(self) {
        if (vd)
            vd->sys->on_fullscreen_window = fs;
    }
}

/**
 * Method called by Cocoa when the view is resized.
 */
- (void)reshape
{
    VLCAssertMainThread();
    [self updateFullscreenFlag];

    NSRect bounds = [self bounds];
    vout_display_place_t place;

    @synchronized(self) {
        if (vd) {
            vout_display_cfg_t cfg_tmp = *(vd->cfg);
            cfg_tmp.display.width  = bounds.size.width;
            cfg_tmp.display.height = bounds.size.height;

            vout_display_PlacePicture (&place, &vd->source, &cfg_tmp, false);
            vd->sys->hdmi_framepack = false;
            const bool stacked_stereo =
                vd->source.multiview_mode == MULTIVIEW_STEREO_FRAMEPACKED ||
                (vd->source.i_sar_den != 0 &&
                 vd->source.i_sar_num == 2 * vd->source.i_sar_den &&
                 vd->source.i_visible_height == 2160);
            if (stacked_stereo &&
                vd->source.i_visible_height >= 2)
            {
                const unsigned eye_h = vd->source.i_visible_height / 2;
                const unsigned gap = eye_h == 1080 ? 45 :
                                     eye_h == 720 ? 30 : 0;
                const int view_w = (int)lround(bounds.size.width);
                const int view_h = (int)lround(bounds.size.height);
                if (gap != 0 &&
                    abs(view_w - (int)vd->source.i_visible_width) <= 2 &&
                    abs(view_h - (int)(2 * eye_h + gap)) <= 2)
                {
                    /* The stacked picture is not a single 8:9 image. Each
                     * half fills one 16:9 active region and the standardized
                     * vertical blanking interval stays black between them. */
                    place.x = place.y = 0;
                    place.width = view_w;
                    place.height = view_h;
                    vd->sys->hdmi_framepack = true;
                    vd->sys->framepack_eye_height = eye_h;
                    vd->sys->framepack_gap = gap;
                    msg_Dbg(vd, "GL1 HDMI frame packing: %ux%u eyes, %u-line gap",
                            vd->source.i_visible_width, eye_h, gap);
                    if (!vd->sys->exclusive_capture &&
                        getenv("VLC_GL1_EXCLUSIVE_FULLSCREEN") != NULL) {
                        const CGError capture_error =
                            CGDisplayCaptureWithOptions(
                                vd->sys->stereo_display,
                                kCGCaptureNoFill);
                        if (capture_error == kCGErrorSuccess) {
                            CGLContextObj cgl = vlc_CGLContextOf(
                                [self openGLContext]);
                            const CGOpenGLDisplayMask mask =
                                CGDisplayIDToOpenGLDisplayMask(
                                    vd->sys->stereo_display);
                            const CGLError fullscreen_error =
                                vlc_gl1_SetFullScreenOnDisplay(cgl, mask);
                            if (fullscreen_error == kCGLNoError) {
                                vd->sys->exclusive_capture = true;
                                msg_Info(vd,
                                    "exclusive OpenGL scanout engaged on display %u",
                                    (unsigned)vd->sys->stereo_display);
                            } else {
                                CGDisplayRelease(vd->sys->stereo_display);
                                msg_Err(vd,
                                    "exclusive OpenGL drawable failed: %s",
                                    CGLErrorString(fullscreen_error));
                            }
                        } else {
                            msg_Err(vd,
                                "display capture failed: CoreGraphics error %d",
                                (int)capture_error);
                        }
                    }
                }
            }
            /* Snow Leopard's 320M driver blocks a swap for 28-33 ms at the
             * 24 Hz frame-packed timing, serializing the VDA engine behind
             * presentation. VLC already schedules pictures against their
             * PTS, so let the driver swap immediately in this one measured
             * configuration. Other GL1 hardware keeps the user setting. */
            const bool force_driver_vsync =
                getenv("VLC_GL1_FORCE_DRIVER_VSYNC") != NULL;
            const int wanted_swap = force_driver_vsync ? 1 :
                                    (vd->sys->hdmi_framepack &&
                                     vd->sys->nvidia_320m
                                      ? 0 : (vd->sys->vsync_requested ? 1 : 0));
            if (wanted_swap != vd->sys->swap_interval)
            {
                CGLContextObj context = vlc_CGLContextOf([self openGLContext]);
                if (context != NULL)
                {
                    GLint interval[] = { wanted_swap };
                    CGLSetParameter(context, kCGLCPSwapInterval, interval);
                    vd->sys->swap_interval = wanted_swap;
                    msg_Dbg(vd, "GL1 swap interval %d%s", wanted_swap,
                            wanted_swap == 0 ? " for NVIDIA MVC" : "");
                }
            }
            vd->sys->place = place;
            /* Dimensions de la vue : le fond letterbox du mode sous-titres
             * matériel se peint en coordonnées VUE (cf. DrawHWBackdrop). */
            vd->sys->view_w = (int) bounds.size.width;
            vd->sys->view_h = (int) bounds.size.height;
            vout_display_SendEventDisplaySize (vd, bounds.size.width, bounds.size.height);

            /* U1 (décodage DVD accéléré ATI) — publier la GÉOMÉTRIE VIDÉO (numéro
             * de fenêtre CGS + rectangle vidéo placé en coordonnées écran CGS
             * top-left) sur le bus libvlc, pour que la sortie HW ATI suive la
             * fenêtre/zone vidéo de VLC. Thread principal (VLCAssertMainThread) :
             * accès AppKit fenêtre/écran OK. bounds/place sont en POINTS (pas de
             * backing ici) → le G3/G4 est 1×, points == pixels. */
            NSWindow *win = [self window];
            long widNum = win ? (long)[win windowNumber] : 0;
            if (win && widNum > 0) {
                float viewH = bounds.size.height;
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
                /* Même rectangle, mais en coordonnées FENÊTRE-locales top-left :
                 * c'est ce qu'attend CGSSetSurfaceBounds. L'origine CGS de la
                 * fenêtre est le coin haut-gauche de son FRAME (barre de titre
                 * comprise), d'où le flip sur la hauteur de l'écran zéro. */
                NSRect wf = [win frame];
                long wx = lround(wf.origin.x);
                long wy = lround(screenH - (wf.origin.y + wf.size.height));
                int new_hw_x = (int)(rx - wx);
                int new_hw_y = (int)(ry - wy);
                /* Le plan SP ATI conserve son dernier bitmap aux anciennes
                 * coordonnées. L'effacer AVANT de publier le nouveau cadre
                 * évite qu'un sous-titre reste figé pendant une bascule plein
                 * écran (ou un redimensionnement) jusqu'au paquet suivant. */
                bool window_changed = vd->sys->hw_place_valid
                                   && vd->sys->hw_wid != (int)widNum;
                if (vd->sys->hw_place_valid
                 && (window_changed
                  || vd->sys->hw_x != new_hw_x || vd->sys->hw_y != new_hw_y
                  || vd->sys->hw_w != (int)rw || vd->sys->hw_h != (int)rh)) {
                    /* Sous 10.2/10.3 le chemin intégré déménage la vue dans une
                     * autre NSWindow. Jaguar invalide les mappings SP dès ce
                     * déménagement, avant que libmpeg2 n'atteigne l'image I où
                     * il détecte le nouveau wid. Suspendre immédiatement vout
                     * ET ordonnanceur SPU ferme cette fenêtre de course. */
                    if (window_changed)
                        var_SetBool(vd->obj.libvlc, DVDDRIVER_VAR_HOLD, true);
                    dvddriver_ctx *sp_hw = var_GetAddress(vd->obj.libvlc,
                                                          DVDDRIVER_VAR_CTX);
                    dvddriver_sp_hide_cb sp_hide = (dvddriver_sp_hide_cb)
                        var_GetAddress(vd->obj.libvlc, DVDDRIVER_VAR_SP_HIDE);
                    if (sp_hw != NULL && sp_hide != NULL)
                        sp_hide(sp_hw);
                }
                vd->sys->hw_x = new_hw_x;
                vd->sys->hw_y = new_hw_y;
                vd->sys->hw_w = (int)rw;
                vd->sys->hw_h = (int)rh;
                vd->sys->hw_place_valid = (rw > 0 && rh > 0);
                vd->sys->hw_wid = (int) widNum;
                vd->sys->hw_need_clear = true;   /* géométrie changée → marges à noircir */
                /* Chantier S+F — la géométrie vidéo a changé (redimensionnement,
                 * bascule plein écran) : l'incrustation courante est calculée
                 * pour l'ANCIEN cadrage. Invalider sa signature force sa
                 * reconstruction à l'échelle et à la position du nouveau
                 * rectangle vidéo dès l'image suivante (sans quoi le
                 * sous-titre resterait en place — ou disparaîtrait — après un
                 * passage en plein écran). */
                vd->sys->ovl_sig = 0;
                msg_Dbg(vd, "U1 géométrie vout : wid=%ld rect=%ld,%ld %ldx%ld "
                        "(écran H=%d) → fenêtre-local %d,%d", widNum, rx, ry, rw, rh,
                        (int)screenH, vd->sys->hw_x, vd->sys->hw_y);
            } else {
                vd->sys->hw_place_valid = false;
                var_SetInteger(vd->obj.libvlc, "dvddriver-vout-wid", 0);
                msg_Dbg(vd, "U1 géométrie vout : pas de fenêtre (wid=0)");
            }
        }
    }

    if ([self lockgl]) {
        // x / y are top left corner, but we need the lower left one
        glViewport (place.x, bounds.size.height - (place.y + place.height), place.width, place.height);

        @synchronized(self) {
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
    /* Prevent the window server from rendering non-OpenGL content in the
     * window asynchronously from OpenGL content (avoids flickering). */
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
     * menu: on Mac OS X 10.6 and older AppKit does not bubble right-clicks
     * up the responder chain by itself. */
    if ([self superview])
        [[self superview] rightMouseDown:o_event];
    else
        [super rightMouseDown:o_event];
}

- (void)scrollWheel:(NSEvent *)o_event
{
    /* NSOpenGLView consumes wheel events on Tiger instead of letting them
     * climb to the legacy video view/window, where volume + OSD are handled.
     * Forward exactly as for the contextual click so every host path keeps a
     * single volume implementation. */
    if ([self superview])
        [[self superview] scrollWheel:o_event];
    else
        [super scrollWheel:o_event];
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
    NSPoint ml = [self convertPoint: [o_event locationInWindow] fromView: nil];
    NSRect videoRect = [self bounds];
    BOOL b_inside = [self mouse: ml inRect: videoRect];

    if (b_inside) {
        @synchronized (self) {
            if (vd) {
                vout_display_SendMouseMovedDisplayCoordinates(vd, ORIENT_NORMAL,
                                                              (int)ml.x, videoRect.size.height - (int)ml.y,
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
 * menu highlighting never sees the pointer. Key presses are unaffected: we
 * implement no key handling, so they keep climbing the responder chain to
 * the hosting interface. */
- (void)viewDidMoveToWindow
{
    if ([self window])
        [[self window] makeFirstResponder:self];
    [self updateFullscreenFlag];
    [super viewDidMoveToWindow];
}

- (BOOL)mouseDownCanMoveWindow
{
    return YES;
}

@end
