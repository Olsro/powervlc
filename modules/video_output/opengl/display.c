/**
 * @file display.c
 * @brief OpenGL video output module
 */
/*****************************************************************************
 * Copyright © 2010-2011 Rémi Denis-Courmont
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

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include <stdlib.h>
#include <assert.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>
#include <vlc_opengl.h>
#include "vout_helper.h"

/* Plugin callbacks */
static int Open (vlc_object_t *);
static void Close (vlc_object_t *);

#define GL_TEXT N_("OpenGL extension")
#define GLES2_TEXT N_("OpenGL ES 2 extension")
#define PROVIDER_LONGTEXT N_( \
    "Extension through which to use the Open Graphics Library (OpenGL).")

#define SOFTWARE_TEXT N_("Use OpenGL even without hardware acceleration")
#define SOFTWARE_LONGTEXT N_( \
    "By default this output steps aside when OpenGL is served by a software " \
    "rasteriser such as llvmpipe, so that an output backed by the display " \
    "hardware (XVideo) can convert and scale the picture instead, which " \
    "costs far less processor time. Enable this to use OpenGL regardless.")

#if defined(__linux__) && defined(HAVE_LIBPLACEBO_NEXT) && !defined(USE_OPENGL_ES2)
# define DOVI_HDMI_TEXT N_("Use an externally activated Dolby Vision HDMI signal")
# define DOVI_HDMI_LONGTEXT N_( \
    "Render Dolby Vision as a 10-bit BT.2020/PQ signal after a platform " \
    "transport helper has switched the HDMI display to Dolby Vision. " \
    "Leave this disabled when no helper is active so PowerVLC keeps its " \
    "safe HDR-to-SDR conversion.")
# define DOVI_PEAK_TEXT N_("Dolby Vision display peak luminance")
# define DOVI_PEAK_LONGTEXT N_( \
    "Peak luminance, in nits, used for source-led Dolby Vision mapping. " \
    "Zero reads the value automatically from the display's Dolby Vision " \
    "EDID block on Linux.")
#endif

vlc_module_begin ()
#if defined (USE_OPENGL_ES2)
# define API VLC_OPENGL_ES2
# define MODULE_VARNAME "gles2"
    set_shortname (N_("OpenGL ES2"))
    set_description (N_("OpenGL for Embedded Systems 2 video output"))
    set_capability ("vout display", 265)
    set_callbacks (Open, Close)
    add_shortcut ("opengles2", "gles2")
    add_module ("gles2", "opengl es2", NULL,
                GLES2_TEXT, PROVIDER_LONGTEXT, true)

#else

# define API VLC_OPENGL
# define MODULE_VARNAME "gl"
    set_shortname (N_("OpenGL"))
    set_description (N_("OpenGL video output"))
    set_category (CAT_VIDEO)
    set_subcategory (SUBCAT_VIDEO_VOUT)
    set_capability ("vout display", 270)
    set_callbacks (Open, Close)
    add_shortcut ("opengl", "gl")
    add_module ("gl", "opengl", NULL,
                GL_TEXT, PROVIDER_LONGTEXT, true)
#endif
    /* Named after the module (gl-software / gles2-software): both plugins are
     * built from this file and may be installed side by side, so they cannot
     * share one config item name. */
    add_bool (MODULE_VARNAME "-software", false,
              SOFTWARE_TEXT, SOFTWARE_LONGTEXT, true)
#if defined(__linux__) && defined(HAVE_LIBPLACEBO_NEXT) && !defined(USE_OPENGL_ES2)
    add_bool ("gl-dovi-hdmi", false, DOVI_HDMI_TEXT,
              DOVI_HDMI_LONGTEXT, true)
    add_integer_with_range ("gl-dovi-peak", 0, 0, 10000,
                            DOVI_PEAK_TEXT, DOVI_PEAK_LONGTEXT, true)
#endif
    add_glopts ()
vlc_module_end ()

struct vout_display_sys_t
{
    vout_display_opengl_t *vgl;
    vlc_gl_t *gl;
    picture_pool_t *pool;
};

#ifdef __linux__
static void SetPlacement(vout_display_sys_t *sys,
                         const vout_display_cfg_t *cfg,
                         const vout_display_place_t *place)
{
    unsigned drawable_width = cfg->display.width;
    unsigned drawable_height = cfg->display.height;
    int viewport_x = place->x;
    int viewport_y = place->y;

    /* An X11 EGL surface keeps the size of its native window: Resize() is a
     * no-op there, so the framebuffer spans the complete display and the
     * picture offset belongs in the viewport. A native Wayland EGL window is
     * actually resized to the placed picture and the wl_egl_window offset
     * performs the centring, leaving a local 0,0 viewport. Telling libplacebo
     * that the X11 framebuffer has only the picture width made portrait video
     * disappear whenever its centred x offset lay beyond that false width. */
    if (sys->gl->surface->type == VOUT_WINDOW_TYPE_WAYLAND)
    {
        drawable_width = place->width;
        drawable_height = place->height;
        viewport_x = 0;
        viewport_y = 0;
    }

    vout_display_opengl_SetDrawableSize(sys->vgl, drawable_width,
                                        drawable_height);
    vout_display_opengl_SetWindowAspectRatio(sys->vgl,
                                              (float)place->width / place->height);
    vout_display_opengl_Viewport(sys->vgl, viewport_x, viewport_y,
                                 place->width, place->height);
}
#endif

/**
 * Is this picture format a hardware surface?
 *
 * Such a picture never reaches system memory: it is a handle to a buffer owned
 * by the decoder's GPU stack, and this module -- through its glconv_* helpers
 * -- is the only output able to take one. Any other output forces the core to
 * insert a readback-and-convert chain first.
 */
static bool IsHardwareSurface (vlc_fourcc_t chroma)
{
    switch (chroma)
    {
        case VLC_CODEC_VAAPI_420:
        case VLC_CODEC_VAAPI_420_10BPP:
        case VLC_CODEC_VDPAU_VIDEO_420:
        case VLC_CODEC_VDPAU_VIDEO_422:
        case VLC_CODEC_VDPAU_VIDEO_444:
        case VLC_CODEC_VDPAU_OUTPUT:
        case VLC_CODEC_ANDROID_OPAQUE:
        case VLC_CODEC_MMAL_OPAQUE:
            return true;
        default:
            return false;
    }
}

/* Display callbacks */
static picture_pool_t *Pool (vout_display_t *, unsigned);
static void PictureRender (vout_display_t *, picture_t *, subpicture_t *);
static void PictureDisplay (vout_display_t *, picture_t *, subpicture_t *);
static int Control (vout_display_t *, int, va_list);

/**
 * Allocates a surface and an OpenGL context for video output.
 */
static int Open (vlc_object_t *obj)
{
    vout_display_t *vd = (vout_display_t *)obj;
    vout_display_sys_t *sys = malloc (sizeof (*sys));
    if (unlikely(sys == NULL))
        return VLC_ENOMEM;

    sys->gl = NULL;
    sys->pool = NULL;

    vout_window_t *surface = vout_display_NewWindow (vd, VOUT_WINDOW_TYPE_INVALID);
    if (surface == NULL)
    {
        msg_Err (vd, "parent window not available");
        goto error;
    }

    const char *gl_name = "$" MODULE_VARNAME;

    /* VDPAU GL interop works only with GLX. Override the "gl" option to force
     * it. */
#ifndef USE_OPENGL_ES2
    if (surface->type == VOUT_WINDOW_TYPE_XID)
    {
        switch (vd->fmt.i_chroma)
        {
            case VLC_CODEC_VDPAU_VIDEO_444:
            case VLC_CODEC_VDPAU_VIDEO_422:
            case VLC_CODEC_VDPAU_VIDEO_420:
            {
                /* Force the option only if it was not previously set */
                char *str = var_InheritString(surface, MODULE_VARNAME);
                if (str == NULL || str[0] == 0 || strcmp(str, "any") == 0)
                    gl_name = "glx";
                free(str);
                break;
            }
            default:
                break;
        }
    }
#endif

    sys->gl = vlc_gl_Create (surface, API, gl_name);
    if (sys->gl == NULL)
        goto error;

    vlc_gl_Resize (sys->gl, vd->cfg->display.width, vd->cfg->display.height);

    /* Initialize video display */
    const vlc_fourcc_t *spu_chromas;

    if (vlc_gl_MakeCurrent (sys->gl))
        goto error;

    /* Decline a software rasteriser unless asked to take it.
     *
     * This module outranks every other X11/Wayland output (270/265 against 200
     * for xcb_xv and 100 for xcb_x11), so it wins even when Mesa has fallen
     * back to llvmpipe and every pixel is converted and scaled on the CPU.
     * That is not hypothetical: Mesa 25 dropped the DRI2 path, and
     * xf86-video-intel only offers DRI2 on gen3, so an ordinary Debian 13 on
     * a 945GME lands on llvmpipe. Measured there on 52 s of 854x480 H.264
     * (Atom N270): 91.3 s of CPU through this module against 39.9 s through
     * xcb_xv -- 2.3x, on the kind of machine that can least afford it.
     * Declining lets the module system fall through to an output that hands
     * the conversion to the display hardware.
     *
     * Only this module is affected: the check lives here and not in
     * vout_display_opengl_New(), which macOS and Windows also call and where
     * bailing out would leave them with no video output at all.
     *
     * A hardware surface is the one case where stepping aside costs more than
     * it saves: no other output can take one, so the core answers by inserting
     * a readback-and-convert chain. Observed while VLC was probing VDPAU on the
     * netbook -- declining a VAOP picture handed the job to xcb_x11 behind a
     * software VAOP -> I420 -> RV32 bicubic swscale, which is worse than the
     * software OpenGL it was avoiding. The saving only exists when a cheaper
     * non-GL path genuinely exists, i.e. for pictures already in memory. */
    if (!var_InheritBool (vd, MODULE_VARNAME "-software")
     && !IsHardwareSurface (vd->fmt.i_chroma)
     && vout_display_opengl_IsSoftware (sys->gl))
    {
        msg_Dbg (vd, "declining: OpenGL is software-rasterised here, and a "
                     "hardware output is likely cheaper (use --"
                     MODULE_VARNAME "-software to force OpenGL anyway)");
        vlc_gl_ReleaseCurrent (sys->gl);
        goto error;
    }

    sys->vgl = vout_display_opengl_New (&vd->fmt, &spu_chromas, sys->gl,
                                        &vd->cfg->viewpoint);
    if (sys->vgl != NULL)
        vout_display_opengl_SetDrawableSize(sys->vgl,
                                            vd->cfg->display.width,
                                            vd->cfg->display.height);
    vlc_gl_ReleaseCurrent (sys->gl);

    if (sys->vgl == NULL)
        goto error;

    vd->sys = sys;
    vd->info.has_pictures_invalid = false;
    vd->info.subpicture_chromas = spu_chromas;
    vd->pool = Pool;
    vd->prepare = PictureRender;
    vd->display = PictureDisplay;
    vd->control = Control;
    return VLC_SUCCESS;

error:
    if (sys->gl != NULL)
        vlc_gl_Release (sys->gl);
    if (surface != NULL)
        vout_display_DeleteWindow (vd, surface);
    free (sys);
    return VLC_EGENERIC;
}

/**
 * Destroys the OpenGL context.
 */
static void Close (vlc_object_t *obj)
{
    vout_display_t *vd = (vout_display_t *)obj;
    vout_display_sys_t *sys = vd->sys;
    vlc_gl_t *gl = sys->gl;
    vout_window_t *surface = gl->surface;

    vlc_gl_MakeCurrent (gl);
    vout_display_opengl_Delete (sys->vgl);
    vlc_gl_ReleaseCurrent (gl);

    vlc_gl_Release (gl);
    vout_display_DeleteWindow (vd, surface);
    free (sys);
}

/**
 * Returns picture buffers
 */
static picture_pool_t *Pool (vout_display_t *vd, unsigned count)
{
    vout_display_sys_t *sys = vd->sys;

    /* Look-ahead decode cache (video-cache-mb): this pool is handed to the
     * decoder (direct rendering), so the cache lives in whatever headroom it
     * has beyond the DPB -- and the core asks for a fixed count, so only this
     * module can make room for it. These pictures come from
     * picture_NewFromFormat(), i.e. plain system memory, and
     * vout_display_opengl_GetPool() caps the total at VLCGL_PICTURE_MAX
     * anyway; clamp here so the figure logged is the one really requested. */
    unsigned extra = vout_display_CacheExtraPictures (vd, 0);
    if (extra > 0)
    {
        if (count + extra > VLCGL_PICTURE_MAX)
            extra = count < VLCGL_PICTURE_MAX ? VLCGL_PICTURE_MAX - count : 0;
        /* Under the floor decoder.c switches the cache off, so the extra
         * pictures would be paid for and never used. */
        if (extra < 26)
            extra = 0;
        else
        {
            msg_Dbg (vd, "look-ahead cache: %u extra pool pictures", extra);
            count += extra;
        }
    }

    if (!sys->pool && vlc_gl_MakeCurrent (sys->gl) == VLC_SUCCESS)
    {
        sys->pool = vout_display_opengl_GetPool (sys->vgl, count);
        vlc_gl_ReleaseCurrent (sys->gl);
    }
    return sys->pool;
}

static void PictureRender (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;

    if (vlc_gl_MakeCurrent (sys->gl) == VLC_SUCCESS)
    {
        vout_display_opengl_Prepare (sys->vgl, pic, subpicture);
        vlc_gl_ReleaseCurrent (sys->gl);
    }
}

static void PictureDisplay (vout_display_t *vd, picture_t *pic, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;

    if (vlc_gl_MakeCurrent (sys->gl) == VLC_SUCCESS)
    {
        vout_display_opengl_Display (sys->vgl, &vd->source);
        vlc_gl_ReleaseCurrent (sys->gl);
    }

    picture_Release (pic);
    if (subpicture != NULL)
        subpicture_Delete(subpicture);
}

static int Control (vout_display_t *vd, int query, va_list ap)
{
    vout_display_sys_t *sys = vd->sys;

    switch (query)
    {
#ifndef NDEBUG
      case VOUT_DISPLAY_RESET_PICTURES: // not needed
        vlc_assert_unreachable();
#endif

      case VOUT_DISPLAY_CHANGE_DISPLAY_SIZE:
      case VOUT_DISPLAY_CHANGE_DISPLAY_FILLED:
      case VOUT_DISPLAY_CHANGE_ZOOM:
      {
        vout_display_cfg_t c = *va_arg (ap, const vout_display_cfg_t *);
        const video_format_t *src = &vd->source;
        vout_display_place_t place;

        /* Reverse vertical alignment as the GL tex are Y inverted */
        if (c.align.vertical == VOUT_DISPLAY_ALIGN_TOP)
            c.align.vertical = VOUT_DISPLAY_ALIGN_BOTTOM;
        else if (c.align.vertical == VOUT_DISPLAY_ALIGN_BOTTOM)
            c.align.vertical = VOUT_DISPLAY_ALIGN_TOP;

        vout_display_PlacePicture (&place, src, &c, false);
        vlc_gl_Resize (sys->gl, place.width, place.height);
        if (vlc_gl_MakeCurrent (sys->gl) != VLC_SUCCESS)
            return VLC_EGENERIC;
#ifdef __linux__
        SetPlacement(sys, &c, &place);
#else
        vout_display_opengl_SetDrawableSize(sys->vgl, place.width,
                                            place.height);
        vout_display_opengl_SetWindowAspectRatio(sys->vgl,
                                                  (float)place.width / place.height);
        vout_display_opengl_Viewport(sys->vgl, place.x, place.y,
                                     place.width, place.height);
#endif
        vlc_gl_ReleaseCurrent (sys->gl);
        return VLC_SUCCESS;
      }

      case VOUT_DISPLAY_CHANGE_SOURCE_ASPECT:
      case VOUT_DISPLAY_CHANGE_SOURCE_CROP:
      {
        const vout_display_cfg_t *cfg = vd->cfg;
        vout_display_place_t place;

        vout_display_PlacePicture (&place, &vd->source, cfg, false);
#ifdef __linux__
        vlc_gl_Resize (sys->gl, place.width, place.height);
        if (vlc_gl_MakeCurrent (sys->gl) != VLC_SUCCESS)
            return VLC_EGENERIC;
        SetPlacement(sys, cfg, &place);
#else
        if (vlc_gl_MakeCurrent (sys->gl) != VLC_SUCCESS)
            return VLC_EGENERIC;
        vout_display_opengl_SetDrawableSize(sys->vgl, cfg->display.width,
                                            cfg->display.height);
        vout_display_opengl_SetWindowAspectRatio(sys->vgl,
                                                  (float)place.width / place.height);
        vout_display_opengl_Viewport(sys->vgl, place.x, place.y,
                                     place.width, place.height);
#endif
        vlc_gl_ReleaseCurrent (sys->gl);
        return VLC_SUCCESS;
      }
      case VOUT_DISPLAY_CHANGE_VIEWPOINT:
        return vout_display_opengl_SetViewpoint (sys->vgl,
            &va_arg (ap, const vout_display_cfg_t* )->viewpoint);
      default:
        msg_Err (vd, "Unknown request %d", query);
    }
    return VLC_EGENERIC;
}
