/*****************************************************************************
 * glwin32.c: Windows OpenGL provider
 *****************************************************************************
 * Copyright (C) 2001-2009 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Gildas Bazin <gbazin@videolan.org>
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
# include "config.h"
#endif

#include <assert.h>

#include <vlc_common.h>
#include <vlc_dialog.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>

#include <windows.h>
#include <versionhelpers.h>

#define GLEW_STATIC
#include <GL/glew.h>
#include <GL/wglew.h>
#include "../opengl/vout_helper.h"

#include "common.h"

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
static int  Open (vlc_object_t *);
static void Close(vlc_object_t *);

vlc_module_begin()
    set_category(CAT_VIDEO)
    set_subcategory(SUBCAT_VIDEO_VOUT)
    set_shortname("OpenGL")
    set_description(N_("OpenGL video output for Windows"))
    set_capability("vout display", 275)
    add_shortcut("glwin32", "opengl")
    set_callbacks(Open, Close)
    add_glopts()
vlc_module_end()

/*****************************************************************************
 * Local prototypes.
 *****************************************************************************/
struct vout_display_sys_t
{
    vout_display_sys_win32_t sys;

    vlc_gl_t              *gl;
    vout_display_opengl_t *vgl;

    bool                   stereo_mode_ready;
    bool                   stereo_mode_changed;
    bool                   stereo_fullscreen_forced;
    unsigned               stereo_eye_width;
    unsigned               stereo_eye_height;
    WCHAR                  stereo_device[CCHDEVICENAME];
    DEVMODEW               stereo_saved_mode;
};

static picture_pool_t *Pool  (vout_display_t *, unsigned);
static void           Prepare(vout_display_t *, picture_t *, subpicture_t *);
static void           Display(vout_display_t *, picture_t *, subpicture_t *);
static void           Manage (vout_display_t *);

static bool RefreshNear(double actual, double standard)
{
    double delta = actual - standard;
    return delta >= -0.2 && delta <= 0.2;
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

static void EnterStereoFullscreen(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    vlc_object_t *vout = vd->obj.parent;
    if (vout != NULL && !var_GetBool(vout, "fullscreen"))
    {
        sys->stereo_fullscreen_forced = true;
        var_SetBool(vout, "fullscreen", true);
        msg_Info(vd, "entered fullscreen automatically for HDMI 3D playback");
    }
}

static void RestoreStereoDisplayMode(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    var_SetBool(vd, "win32-framepacked-output", false);
    sys->stereo_mode_ready = false;

    if (sys->stereo_fullscreen_forced)
    {
        vlc_object_t *vout = vd->obj.parent;
        if (vout != NULL && var_GetBool(vout, "fullscreen"))
            var_SetBool(vout, "fullscreen", false);
        sys->stereo_fullscreen_forced = false;
    }

    if (sys->stereo_mode_changed)
    {
        LONG result = ChangeDisplaySettingsExW(sys->stereo_device,
                                               &sys->stereo_saved_mode,
                                               NULL, CDS_FULLSCREEN, NULL);
        if (result != DISP_CHANGE_SUCCESSFUL)
            msg_Warn(vd, "could not restore the previous Windows display "
                     "mode (%ld)", result);
        else
            msg_Info(vd, "restored the previous Windows display mode");
        sys->stereo_mode_changed = false;
    }
}

static void SelectStereoDisplayMode(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (!Win32IsFramePackableStereo(vd->fmt.multiview_mode))
        return;

    if (!CommonShouldSwitchToStereoDisplay(vd))
        return;

    unsigned eye_width, eye_height;
    if (!StereoEyeDimensions(&vd->fmt, &eye_width, &eye_height))
        return;

    DWORD packed_height;
    DWORD preferred_rate;
    DWORD alternate_rate;
    double content_rate = 24.0;
    if (vd->fmt.i_frame_rate > 0 && vd->fmt.i_frame_rate_base > 0)
        content_rate = (double)vd->fmt.i_frame_rate /
                       vd->fmt.i_frame_rate_base;

    if (eye_width == 1920 && eye_height == 1080 &&
        (RefreshNear(content_rate, 24.0) ||
         RefreshNear(content_rate, 24000.0 / 1001.0)))
    {
        packed_height = 2205;
    }
    else if (eye_width == 1280 && eye_height == 720 &&
             (RefreshNear(content_rate, 50.0) ||
              RefreshNear(content_rate, 60.0) ||
              RefreshNear(content_rate, 60000.0 / 1001.0)))
    {
        packed_height = 1470;
    }
    else
    {
        msg_Warn(vd, "unsupported HDMI frame-packing format %ux%u at %.3f Hz",
                 eye_width, eye_height, content_rate);
        vlc_dialog_display_error(vd, _("HDMI 3D frame packing unavailable"),
                                 _("PowerVLC cannot select a standardized "
                                   "HDMI frame-packed mode for %ux%u per eye "
                                   "at %.3f Hz."), eye_width, eye_height,
                                 content_rate);
        return;
    }

    /* EnumDisplaySettings represents fractional HDMI rates inconsistently:
     * drivers commonly expose 23.976/59.94 as 23/59, while others round them
     * to 24/60.  Prefer Kodi's truncation convention, but accept the rounded
     * spelling of the exact same CEA timing. */
    preferred_rate = (DWORD)content_rate;
    alternate_rate = (DWORD)(content_rate + 0.5);

    HWND window = sys->sys.hparent != NULL ? sys->sys.hparent : sys->sys.hwnd;
    HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    MONITORINFOEXW info;
    memset(&info, 0, sizeof(info));
    info.cbSize = sizeof(info);
    if (monitor == NULL || !GetMonitorInfoW(monitor, (MONITORINFO *)&info))
    {
        msg_Warn(vd, "could not identify the Windows display for HDMI 3D");
        return;
    }
    lstrcpynW(sys->stereo_device, info.szDevice,
              ARRAY_SIZE(sys->stereo_device));

    memset(&sys->stereo_saved_mode, 0, sizeof(sys->stereo_saved_mode));
    sys->stereo_saved_mode.dmSize = sizeof(sys->stereo_saved_mode);
    if (!EnumDisplaySettingsExW(sys->stereo_device, ENUM_CURRENT_SETTINGS,
                                &sys->stereo_saved_mode, 0))
    {
        msg_Warn(vd, "could not read the current Windows display mode");
        return;
    }

    DEVMODEW best;
    memset(&best, 0, sizeof(best));
    bool found = false;
    bool found_alternate = false;
    for (DWORD index = 0;; ++index)
    {
        DEVMODEW candidate;
        memset(&candidate, 0, sizeof(candidate));
        candidate.dmSize = sizeof(candidate);
        if (!EnumDisplaySettingsExW(sys->stereo_device, index, &candidate,
                                    EDS_RAWMODE))
            break;
        if (candidate.dmPelsWidth == eye_width &&
            candidate.dmPelsHeight == packed_height &&
            !(candidate.dmDisplayFlags & DM_INTERLACED))
        {
            if (candidate.dmDisplayFrequency == preferred_rate)
            {
                best = candidate;
                found = true;
                break;
            }
            if (!found_alternate &&
                candidate.dmDisplayFrequency == alternate_rate)
            {
                best = candidate;
                found_alternate = true;
            }
        }
    }
    if (!found && found_alternate)
        found = true;

    if (!found)
    {
        msg_Warn(vd, "Windows exposes no %ux%lu HDMI frame-packing mode "
                 "for %.3f Hz content", eye_width, packed_height,
                 content_rate);
        vlc_dialog_display_error(vd, _("HDMI 3D frame packing unavailable"),
                                 _("Windows does not expose the required "
                                   "%ux%lu frame-packed mode for %.3f Hz. "
                                   "PowerVLC will not substitute ordinary "
                                   "1080p because it cannot carry MVC frame "
                                   "packing."), eye_width, packed_height,
                                 content_rate);
        return;
    }

    bool already_active =
        sys->stereo_saved_mode.dmPelsWidth == eye_width &&
        sys->stereo_saved_mode.dmPelsHeight == packed_height &&
        sys->stereo_saved_mode.dmDisplayFrequency ==
            best.dmDisplayFrequency;
    if (!already_active)
    {
        LONG result = ChangeDisplaySettingsExW(sys->stereo_device, &best, NULL,
                                               CDS_TEST, NULL);
        if (result == DISP_CHANGE_SUCCESSFUL)
            result = ChangeDisplaySettingsExW(sys->stereo_device, &best, NULL,
                                              CDS_FULLSCREEN, NULL);
        if (result != DISP_CHANGE_SUCCESSFUL)
        {
            msg_Warn(vd, "Windows rejected the HDMI frame-packing mode (%ld)",
                     result);
            vlc_dialog_display_error(vd,
                                     _("HDMI 3D frame packing unavailable"),
                                     _("Windows rejected the %ux%lu "
                                       "frame-packed mode at %lu Hz "
                                       "(error %ld)."), eye_width,
                                     packed_height,
                                     best.dmDisplayFrequency, result);
            return;
        }
        sys->stereo_mode_changed = true;
    }

    DEVMODEW active;
    memset(&active, 0, sizeof(active));
    active.dmSize = sizeof(active);
    if (!EnumDisplaySettingsExW(sys->stereo_device, ENUM_CURRENT_SETTINGS,
                                &active, 0) ||
        active.dmPelsWidth != eye_width ||
        active.dmPelsHeight != packed_height)
    {
        msg_Warn(vd, "Windows did not activate the requested frame-packed "
                 "raster");
        RestoreStereoDisplayMode(vd);
        return;
    }

    sys->stereo_eye_width = eye_width;
    sys->stereo_eye_height = eye_height;
    sys->stereo_mode_ready = true;
    var_SetBool(vd, "win32-framepacked-output", true);
    UpdateRects(vd, NULL, true);
    EnterStereoFullscreen(vd);
    msg_Info(vd, "switched Windows HDMI display to %ux%lu at %lu Hz "
             "for stereoscopic playback", eye_width, packed_height,
             best.dmDisplayFrequency);
}

static int Control(vout_display_t *vd, int query, va_list args)
{
    vout_display_sys_t *sys = vd->sys;

    if (query == VOUT_DISPLAY_CHANGE_VIEWPOINT)
        return vout_display_opengl_SetViewpoint(sys->vgl,
            &va_arg (args, const vout_display_cfg_t* )->viewpoint);

    return CommonControl(vd, query, args);
}

static int EmbedVideoWindow_Control(vout_window_t *wnd, int query, va_list ap)
{
    VLC_UNUSED( ap ); VLC_UNUSED( query );
    return VLC_EGENERIC;
}

static vout_window_t *EmbedVideoWindow_Create(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    if (!sys->sys.hvideownd)
        return NULL;

    vout_window_t *wnd = vlc_object_create(vd, sizeof(vout_window_t));
    if (!wnd)
        return NULL;

    wnd->type = VOUT_WINDOW_TYPE_HWND;
    wnd->handle.hwnd = sys->sys.hvideownd;
    wnd->control = EmbedVideoWindow_Control;
    return wnd;
}

/**
 * It creates an OpenGL vout display.
 */
static int Open(vlc_object_t *object)
{
    vout_display_t *vd = (vout_display_t *)object;
    vout_display_sys_t *sys;

    /* do not use OpenGL on XP unless forced */
    if(!object->obj.force && !IsWindowsVistaOrGreater())
        return VLC_EGENERIC;

    /* Allocate structure */
    vd->sys = sys = calloc(1, sizeof(*sys));
    if (!sys)
        return VLC_ENOMEM;

    var_Create(vd, "win32-framepacked-output", VLC_VAR_BOOL);

    /* */
    if (CommonInit(vd))
        goto error;

    SelectStereoDisplayMode(vd);

    EventThreadUpdateTitle(sys->sys.event, VOUT_TITLE " (OpenGL output)");

    vout_window_t *surface = EmbedVideoWindow_Create(vd);
    if (!surface)
        goto error;

    sys->gl = vlc_gl_Create (surface, VLC_OPENGL, "$gl");
    if (!sys->gl)
    {
        vlc_object_release(surface);
        goto error;
    }

    unsigned initial_width = sys->stereo_mode_ready
                           ? sys->stereo_eye_width
                           : vd->cfg->display.width;
    unsigned initial_height = sys->stereo_mode_ready
                            ? 2 * sys->stereo_eye_height +
                              (sys->stereo_eye_height == 720 ? 30 : 45)
                            : vd->cfg->display.height;
    vlc_gl_Resize(sys->gl, initial_width, initial_height);

    video_format_t fmt = vd->fmt;
    const vlc_fourcc_t *subpicture_chromas;
    if (vlc_gl_MakeCurrent (sys->gl))
        goto error;
    sys->vgl = vout_display_opengl_New(&fmt, &subpicture_chromas, sys->gl,
                                       &vd->cfg->viewpoint);
    vlc_gl_ReleaseCurrent (sys->gl);
    if (!sys->vgl)
        goto error;

    if (sys->stereo_mode_ready)
    {
        if (vlc_gl_MakeCurrent(sys->gl) == VLC_SUCCESS)
        {
            vout_display_opengl_SetFramePackingOutput(
                sys->vgl, true, sys->stereo_eye_width,
                sys->stereo_eye_height);
            vlc_gl_ReleaseCurrent(sys->gl);
        }
    }

    vout_display_info_t info = vd->info;
    info.has_double_click = true;
    info.subpicture_chromas = subpicture_chromas;

   /* Setup vout_display now that everything is fine */
    vd->fmt  = fmt;
    vd->info = info;

    vd->pool    = Pool;
    vd->prepare = Prepare;
    vd->display = Display;
    vd->control = Control;
    vd->manage  = Manage;

    return VLC_SUCCESS;

error:
    Close(object);
    return VLC_EGENERIC;
}

/**
 * It destroys an OpenGL vout display.
 */
static void Close(vlc_object_t *object)
{
    vout_display_t *vd = (vout_display_t *)object;
    vout_display_sys_t *sys = vd->sys;
    vlc_gl_t *gl = sys->gl;

    RestoreStereoDisplayMode(vd);

    if (gl)
    {
        vout_window_t *surface = gl->surface;
        if (sys->vgl)
        {
            vlc_gl_MakeCurrent (gl);
            vout_display_opengl_Delete(sys->vgl);
            vlc_gl_ReleaseCurrent (gl);
        }
        vlc_gl_Release (gl);
        vlc_object_release(surface);
    }

    CommonClean(vd);

    free(sys);
}

/* */
static picture_pool_t *Pool(vout_display_t *vd, unsigned count)
{
    vout_display_sys_t *sys = vd->sys;

    if (!sys->sys.pool && vlc_gl_MakeCurrent (sys->gl) == VLC_SUCCESS)
    {
        sys->sys.pool = vout_display_opengl_GetPool(sys->vgl, count);
        vlc_gl_ReleaseCurrent (sys->gl);
    }
    return sys->sys.pool;
}

static void Prepare(vout_display_t *vd, picture_t *picture, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;

    if (vlc_gl_MakeCurrent (sys->gl) == VLC_SUCCESS)
    {
        vout_display_opengl_Prepare (sys->vgl, picture, subpicture);
        vlc_gl_ReleaseCurrent (sys->gl);
    }
}

static void Display(vout_display_t *vd, picture_t *picture, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;

    if (vlc_gl_MakeCurrent (sys->gl) == VLC_SUCCESS)
    {
        vout_display_opengl_Display (sys->vgl, &vd->source);
        vlc_gl_ReleaseCurrent (sys->gl);
    }

    picture_Release(picture);
    if (subpicture)
        subpicture_Delete(subpicture);

    CommonDisplay(vd);
}

static void Manage (vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    CommonManage(vd);

    const int width  = sys->sys.rect_dest.right  - sys->sys.rect_dest.left;
    const int height = sys->sys.rect_dest.bottom - sys->sys.rect_dest.top;
    vlc_gl_Resize (sys->gl, width, height);
    if (vlc_gl_MakeCurrent (sys->gl) != VLC_SUCCESS)
        return;
    vout_display_opengl_SetWindowAspectRatio(sys->vgl, (float)width / height);
    vout_display_opengl_Viewport(sys->vgl, 0, 0, width, height);
    vlc_gl_ReleaseCurrent (sys->gl);
}
