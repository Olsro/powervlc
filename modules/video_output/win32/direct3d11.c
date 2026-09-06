/*****************************************************************************
 * direct3d11.c: Windows Direct3D11 video output module
 *****************************************************************************
 * Copyright (C) 2014-2015 VLC authors and VideoLAN
 *
 * Authors: Martell Malone <martellmalone@gmail.com>
 *          Steve Lhomme <robux4@gmail.com>
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

#if _WIN32_WINNT < 0x0601 // _WIN32_WINNT_WIN7
# undef _WIN32_WINNT
# define _WIN32_WINNT 0x0601
#endif
#if WINVER < 0x0601
# undef WINVER
# define WINVER 0x0601
#endif

#include <vlc_common.h>
#include <vlc_dialog.h>
#include <vlc_plugin.h>
#include <vlc_vout_display.h>
#include <vlc_vout_osd.h>
#include <vlc_actions.h>
#include <vlc_input.h>
#include <vlc_playlist.h>

#include <assert.h>
#include <math.h>

#define COBJMACROS
#include <initguid.h>
#include <d3d11_1.h>
#ifdef HAVE_DXGI1_6_H
# include <dxgi1_6.h>
#else
# include <dxgi1_5.h>
#endif
#ifdef HAVE_D3D11_4_H
#include <d3d11_4.h>
#endif

/* avoided until we can pass ISwapchainPanel without c++/cx mode
# include <windows.ui.xaml.media.dxinterop.h> */

#include "../../video_chroma/d3d11_fmt.h"
#include "d3d11_quad.h"
#include "d3d11_shaders.h"
#include "d3d11_ra_shaders.h"
#include "d3d11_scaler.h"
#include "d3d11_tonemap.h"
#if !VLC_WINSTORE_APP
# include "dovi_display.h"
#endif

#include "common.h"

DEFINE_GUID(GUID_SWAPCHAIN_WIDTH,  0xf1b59347, 0x1643, 0x411a, 0xad, 0x6b, 0xc7, 0x80, 0x17, 0x7a, 0x06, 0xb6);
DEFINE_GUID(GUID_SWAPCHAIN_HEIGHT, 0x6ea976a0, 0x9d60, 0x4bb7, 0xa5, 0xa9, 0x7d, 0xd1, 0x18, 0x7f, 0xc9, 0xbd);

static int  Open(vlc_object_t *);
static void Close(vlc_object_t *);

#define D3D11_HELP N_("Recommended video output for Windows 8 and later versions")
#define HW_BLENDING_TEXT N_("Use hardware blending support")
#define HW_BLENDING_LONGTEXT N_(\
    "Try to use hardware acceleration for subtitle/OSD blending.")

#define UPSCALE_MODE_TEXT N_("Video Upscaling Mode")
#define UPSCALE_MODE_LONGTEXT N_("Select the upscaling mode for video.")

static const char *const ppsz_upscale_mode[] = {
    "linear", "point", "processor", "super" };
static const char *const ppsz_upscale_mode_text[] = {
    N_("Linear Sampler"), N_("Point Sampler"), N_("Video Processor"), N_("Super Resolution") };

#define HDR_MODE_TEXT N_("HDR Output Mode")
#define HDR_MODE_LONGTEXT N_("Use HDR output even if the source is SDR.")

#define DOVI_HDMI_TEXT N_("Use the native Dolby Vision HDMI signal")
#define DOVI_HDMI_LONGTEXT N_( \
    "Switch a compatible Windows display to its native Dolby Vision mode " \
    "while Dolby Vision video is playing, then restore its previous HDR " \
    "state. This does not require the Dolby Vision Store extension.")

static const char *const ppsz_hdr_mode[] = {
    "auto", "never", "always", "generate" };
static const char *const ppsz_hdr_mode_text[] = {
    N_("Auto"), N_("Never out HDR"), N_("Always output HDR"), N_("Generate HDR from SDR") };

vlc_module_begin ()
    set_shortname("Direct3D11")
    set_description(N_("Direct3D11 video output"))
    set_help(D3D11_HELP)
    set_category(CAT_VIDEO)
    set_subcategory(SUBCAT_VIDEO_VOUT)

    add_bool("direct3d11-hw-blending", true, HW_BLENDING_TEXT, HW_BLENDING_LONGTEXT, true)

    add_integer("winrt-d3dcontext",    0x0, NULL, NULL, true) /* ID3D11DeviceContext* */
        change_volatile()
    add_integer("winrt-swapchain",     0x0, NULL, NULL, true) /* IDXGISwapChain1*     */
        change_volatile()

    add_string("d3d11-upscale-mode", "linear", UPSCALE_MODE_TEXT, UPSCALE_MODE_LONGTEXT, false)
        change_string_list(ppsz_upscale_mode, ppsz_upscale_mode_text)

    add_string("d3d11-hdr-mode", "auto", HDR_MODE_TEXT, HDR_MODE_LONGTEXT, false)
        change_string_list(ppsz_hdr_mode, ppsz_hdr_mode_text)

#if !VLC_WINSTORE_APP
    add_bool("d3d11-dovi-hdmi", true, DOVI_HDMI_TEXT,
             DOVI_HDMI_LONGTEXT, true)
#endif

    set_capability("vout display", 300)
    add_shortcut("direct3d11")
    set_callbacks(Open, Close)
vlc_module_end ()

enum d3d11_upscale
{
    upscale_LinearSampler,
    upscale_PointSampler,
    upscale_VideoProcessor,
    upscale_SuperResolution,
};

enum d3d11_hdr
{
    hdr_Auto,
    hdr_Never,
    hdr_Always,
    hdr_Fake,
};

struct vout_display_sys_t
{
    vout_display_sys_win32_t sys;
    video_format_t           pool_fmt;
    const d3d_format_t       *pool_d3dfmt;

    int                      log_level;

    display_info_t           display;

    HINSTANCE                hdxgi_dll;        /* handle of the opened dxgi dll */
    d3d11_handle_t           hd3d;
    IDXGISwapChain1          *dxgiswapChain;   /* DXGI 1.2 swap chain */
    IDXGISwapChain4          *dxgiswapChain4;  /* DXGI 1.5 for HDR */
    IDXGIOutput              *stereo_present_output;
    DXGI_HDR_METADATA_HDR10  hdr10;
    d3d11_device_t           d3d_dev;
    d3d_quad_t               picQuad;
    video_format_t           quad_fmt;

#ifdef HAVE_D3D11_4_H
    ID3D11Fence              *d3dRenderFence;
    ID3D11DeviceContext4     *d3dcontext4;
    UINT64                   renderFence;
    HANDLE                   renderFinished;
#endif

    picture_sys_t            stagingSys;
    HANDLE                   sharedHandle;

    ID3D11RenderTargetView   *d3drenderTargetView;
    ID3D11RenderTargetView   *d3drenderTargetViewRight;
    ID3D11DepthStencilView   *d3ddepthStencilView;
    struct d3d11_ra_shader_engine *crtShaders;

    bool                     stereo_requested;
    bool                     stereo_active;
    bool                     stereo_adopted;
    vlc_tick_t               stereo_adopted_fullscreen_guard_until;
    bool                     stereo_windowed;
    bool                     stereo_mode_changed;
    bool                     stereo_fullscreen_forced;
    bool                     stereo_display_was_enabled;
    unsigned                 stereo_eye_width;
    unsigned                 stereo_eye_height;
    WCHAR                    stereo_device[CCHDEVICENAME];
    DEVMODEW                 stereo_saved_mode;
    IDXGIDisplayControl      *stereo_display_control;
    DISPLAYCONFIG_PATH_INFO  *stereo_saved_paths;
    DISPLAYCONFIG_MODE_INFO  *stereo_saved_modes;
    UINT32                   stereo_saved_path_count;
    UINT32                   stereo_saved_mode_count;
    bool                     stereo_topology_changed;
    bool                     stereo_mouse_callbacks;
    vlc_tick_t               stereo_controls_until;
    vlc_tick_t               stereo_controls_last_draw;
    vlc_tick_t               stereo_controls_osd_until;
    bool                     stereo_controls_hovered;
    vlc_tick_t               stereo_cursor_last_draw;
    int                      stereo_cursor_channel;
    int                      stereo_feedback_channel;
    int                      stereo_back_channel;
    int                      stereo_pause_channel;
    int                      stereo_forward_channel;
    volatile LONG            stereo_cursor_x;
    volatile LONG            stereo_cursor_y;
    POINT                    stereo_cursor_screen;
    bool                     stereo_cursor_screen_valid;
    vlc_tick_t               stereo_mouse_accept_after;

    ID3D11InputLayout         *pVertexLayout;
    ID3D11VertexShader        *flatVSShader;
    ID3D11VertexShader        *projectionVSShader;

    /* copy from the decoder pool into picSquad before display
     * Uses a Texture2D with slices rather than a Texture2DArray for the decoder */
    bool                     legacy_shader;
    bool                     dovi_metadata_reported;
    bool                     dovi_missing_reported;
    bool                     dovi_fel_reported;
    bool                     dovi_sdr_reported;
    bool                     dovi_hdr10_reported;
#if !VLC_WINSTORE_APP
    win32_dovi_display_t     *dovi_display;
    bool                     dovi_display_attempted;
#endif

    // SPU
    vlc_fourcc_t             pSubpictureChromas[2];
    ID3D11PixelShader        *pSPUPixelShader;
    const d3d_format_t       *d3dregion_format;
    int                      d3dregion_count;
    picture_t                **d3dregions;
    int64_t                  d3dregion_order;
    int                      d3dregion_original_width;
    int                      d3dregion_original_height;
    bool                     d3dregion_order_valid;
    bool                     stereo_geometry_reported;
    int64_t                  stereo_spu_reported_order;
    unsigned                 stereo_spu_report_count;

    // upscaling
    enum d3d11_upscale       upscaleMode;
    struct d3d11_scaler      *scaleProc;

    // HDR mode
    enum d3d11_hdr           hdrMode;
    struct d3d11_tonemapper  *tonemapProc;
};

/* The vout core retains its vout_thread_t while reopening the display module
 * for a decoder format change. A Blu-ray can therefore go from an MVC logo
 * to an authored 2D language menu without ending the disc session. Keep the
 * Windows display transaction on that persistent vout: restoring the saved
 * topology from Close() would re-enable the laptop panel before the new D3D11
 * swapchain exists, and Qt would consequently recreate the video there. */
typedef struct
{
    bool mode_changed;
    bool fullscreen_forced;
    bool display_was_enabled;
    bool topology_changed;
    unsigned eye_width;
    unsigned eye_height;
    WCHAR device[CCHDEVICENAME];
    DEVMODEW saved_mode;
    DISPLAYCONFIG_PATH_INFO *saved_paths;
    DISPLAYCONFIG_MODE_INFO *saved_modes;
    UINT32 saved_path_count;
    UINT32 saved_mode_count;
} win32_stereo_handoff_t;

#define RECTWidth(r)   (int)((r).right - (r).left)
#define RECTHeight(r)  (int)((r).bottom - (r).top)

static picture_pool_t *Pool(vout_display_t *, unsigned);

static void Prepare(vout_display_t *, picture_t *, subpicture_t *subpicture);
static void Display(vout_display_t *, picture_t *, subpicture_t *subpicture);

static void Direct3D11Destroy(vout_display_t *);

static int  Direct3D11Open (vout_display_t *, bool external_device);
static void Direct3D11Close(vout_display_t *);

static int SetupOutputFormat(vout_display_t *, video_format_t *decoder, video_format_t *quad);
static int  Direct3D11CreateFormatResources (vout_display_t *, const video_format_t *);
static int  Direct3D11CreateGenericResources(vout_display_t *);
static void Direct3D11DestroyResources(vout_display_t *);

static void DestroyDisplayPoolPicture(picture_t *);
static void Direct3D11DeleteRegions(int, picture_t **);
static int Direct3D11MapSubpicture(vout_display_t *, int *, picture_t ***, subpicture_t *);

static void SetQuadVSProjection(vout_display_t *, d3d_quad_t *, const vlc_viewpoint_t *);
static void UpdatePicQuadPosition(vout_display_t *);
static void CallUpdateRects(vout_display_t *);

static int Control(vout_display_t *, int, va_list);
static void Manage(vout_display_t *vd);

static int Direct3D11MapPoolTexture(picture_t *picture)
{
    picture_sys_t *p_sys = picture->p_sys;
    D3D11_MAPPED_SUBRESOURCE mappedResource;
    HRESULT hr;

    ID3D11Device *dev;
    ID3D11DeviceContext_GetDevice(p_sys->context, &dev);
    ID3D11Device_Release(dev);

#ifndef NDEBUG
    D3D11_TEXTURE2D_DESC dsc;
    ID3D11Texture2D_GetDesc(p_sys->texture[KNOWN_DXGI_INDEX], &dsc);
    assert(dsc.CPUAccessFlags & D3D11_CPU_ACCESS_WRITE);
    assert(dsc.Usage & D3D11_USAGE_DYNAMIC);
#endif

    hr = ID3D11DeviceContext_Map(p_sys->context, p_sys->resource[KNOWN_DXGI_INDEX], p_sys->slice_index, D3D11_MAP_WRITE_DISCARD, 0, &mappedResource);
    if( FAILED(hr) )
    {
        return VLC_EGENERIC;
    }
    return CommonUpdatePicture(picture, NULL, mappedResource.pData, mappedResource.RowPitch);
}

static void Direct3D11UnmapPoolTexture(picture_t *picture)
{
    picture_sys_t *p_sys = picture->p_sys;
    ID3D11DeviceContext_Unmap(p_sys->context, p_sys->resource[KNOWN_DXGI_INDEX], 0);
}

static void StereoEyeTextureRect(video_multiview_mode_t mode,
                                 const video_format_t *fmt,
                                 unsigned output_eye, float *left, float *top,
                                 float *right, float *bottom)
{
    bool right_first = mode == MULTIVIEW_STEREO_SBS_RIGHT_FIRST ||
                       mode == MULTIVIEW_STEREO_TB_RIGHT_FIRST ||
                       mode == MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE;
    unsigned source_eye = output_eye ^ right_first;

    float coded_width = fmt->i_width > 0 ? fmt->i_width : 1;
    float coded_height = fmt->i_height > 0 ? fmt->i_height : 1;
    *left = fmt->i_x_offset / coded_width;
    *top = fmt->i_y_offset / coded_height;
    *right = (fmt->i_x_offset + fmt->i_visible_width) / coded_width;
    *bottom = (fmt->i_y_offset + fmt->i_visible_height) / coded_height;
    switch (mode)
    {
        case MULTIVIEW_STEREO_SBS:
        case MULTIVIEW_STEREO_SBS_RIGHT_FIRST:
        {
            float middle = (*left + *right) * .5f;
            if (source_eye)
                *left = middle;
            else
                *right = middle;
            break;
        }
        case MULTIVIEW_STEREO_TB:
        case MULTIVIEW_STEREO_TB_RIGHT_FIRST:
        case MULTIVIEW_STEREO_FRAMEPACKED:
        case MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE:
        {
            float middle = (*top + *bottom) * .5f;
            if (source_eye)
                *top = middle;
            else
                *bottom = middle;
            break;
        }
        default:
            break;
    }
}

static bool GetWinRTSize(const vout_display_sys_win32_t *p_sys, UINT *w, UINT *h)
{
    const vout_display_sys_t *sys = (const vout_display_sys_t *)p_sys;
    uint32_t i_width;
    uint32_t i_height;
    UINT dataSize = sizeof(i_width);
    HRESULT hr = IDXGISwapChain_GetPrivateData(sys->dxgiswapChain, &GUID_SWAPCHAIN_WIDTH, &dataSize, &i_width);
    if (FAILED(hr)) {
        return false;
    }
    dataSize = sizeof(i_height);
    hr = IDXGISwapChain_GetPrivateData(sys->dxgiswapChain, &GUID_SWAPCHAIN_HEIGHT, &dataSize, &i_height);
    if (FAILED(hr)) {
        return false;
    }
    *w = i_width;
    *h = i_height;
    return true;
}

static int OpenCoreW(vout_display_t *vd)
{
    IDXGISwapChain1* dxgiswapChain  = (void*)var_InheritInteger(vd, "winrt-swapchain");
    if (!dxgiswapChain)
        return VLC_EGENERIC;
    ID3D11DeviceContext* d3dcontext = (void*)var_InheritInteger(vd, "winrt-d3dcontext");
    if (!d3dcontext)
        return VLC_EGENERIC;
    ID3D11Device* d3ddevice = NULL;
    ID3D11DeviceContext_GetDevice(d3dcontext, &d3ddevice);
    if (!d3ddevice)
        return VLC_EGENERIC;

    vout_display_sys_t *sys = vd->sys;
    sys->dxgiswapChain = dxgiswapChain;
    sys->d3d_dev.d3ddevice     = d3ddevice;
    sys->d3d_dev.d3dcontext    = d3dcontext;
    sys->d3d_dev.feature_level = ID3D11Device_GetFeatureLevel(sys->d3d_dev.d3ddevice );
    IDXGISwapChain_AddRef     (sys->dxgiswapChain);
    ID3D11DeviceContext_AddRef(sys->d3d_dev.d3dcontext);

    sys->sys.pf_GetWindowSize = GetWinRTSize;

    return VLC_SUCCESS;
}

static unsigned int GetPictureWidth(const vout_display_t *vd)
{
    return vd->sys->picQuad.i_width;
}

static unsigned int GetPictureHeight(const vout_display_t *vd)
{
    return vd->sys->picQuad.i_height;
}

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
        case MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE:
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

static bool IsInternalDisplayPath(const DISPLAYCONFIG_PATH_INFO *path)
{
    switch (path->targetInfo.outputTechnology)
    {
        case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL:
        case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_DISPLAYPORT_EMBEDDED:
        case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_UDI_EMBEDDED:
        case DISPLAYCONFIG_OUTPUT_TECHNOLOGY_LVDS:
            return true;
        default:
            return false;
    }
}

static LONG QueryActiveDisplayTopology(DISPLAYCONFIG_PATH_INFO **paths,
                                       UINT32 *path_count,
                                       DISPLAYCONFIG_MODE_INFO **modes,
                                       UINT32 *mode_count)
{
    *paths = NULL;
    *modes = NULL;
    for (unsigned attempt = 0; attempt < 4; ++attempt)
    {
        LONG result = GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS,
                                                  path_count, mode_count);
        if (result != ERROR_SUCCESS)
            return result;
        *paths = calloc(*path_count, sizeof(**paths));
        *modes = calloc(*mode_count, sizeof(**modes));
        if ((*path_count != 0 && *paths == NULL) ||
            (*mode_count != 0 && *modes == NULL))
        {
            free(*paths);
            free(*modes);
            *paths = NULL;
            *modes = NULL;
            return ERROR_NOT_ENOUGH_MEMORY;
        }
        result = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, path_count,
                                    *paths, mode_count, *modes, NULL);
        if (result != ERROR_INSUFFICIENT_BUFFER)
            return result;
        free(*paths);
        free(*modes);
        *paths = NULL;
        *modes = NULL;
    }
    return ERROR_INSUFFICIENT_BUFFER;
}

static bool UseExternalDisplayOnly(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    DISPLAYCONFIG_PATH_INFO *paths;
    DISPLAYCONFIG_MODE_INFO *modes;
    UINT32 path_count = 0, mode_count = 0;
    LONG result = QueryActiveDisplayTopology(&paths, &path_count, &modes,
                                             &mode_count);
    if (result != ERROR_SUCCESS)
    {
        msg_Warn(vd, "cannot read the active Windows display topology (%ld)",
                 result);
        return false;
    }

    bool needs_external_only = path_count != 1;
    for (UINT32 i = 0; i < path_count; ++i)
        needs_external_only |= IsInternalDisplayPath(&paths[i]);
    if (!needs_external_only)
    {
        free(paths);
        free(modes);
        return true;
    }

    result = SetDisplayConfig(0, NULL, 0, NULL,
                              SDC_APPLY | SDC_TOPOLOGY_EXTERNAL);
    if (result != ERROR_SUCCESS)
    {
        msg_Warn(vd, "Windows rejected temporary external-display-only "
                 "topology (%ld)", result);
        free(paths);
        free(modes);
        return false;
    }

    sys->stereo_saved_paths = paths;
    sys->stereo_saved_modes = modes;
    sys->stereo_saved_path_count = path_count;
    sys->stereo_saved_mode_count = mode_count;
    sys->stereo_topology_changed = true;

    /* SetDisplayConfig is synchronous for the topology database, but the
     * graphics stack needs a short time to publish the projector's 3D modes.
     * Poll the active paths instead of guessing a fixed multi-second delay. */
    for (unsigned attempt = 0; attempt < 50; ++attempt)
    {
        DISPLAYCONFIG_PATH_INFO *current_paths;
        DISPLAYCONFIG_MODE_INFO *current_modes;
        UINT32 current_path_count = 0, current_mode_count = 0;
        result = QueryActiveDisplayTopology(&current_paths,
                                            &current_path_count,
                                            &current_modes,
                                            &current_mode_count);
        bool ready = result == ERROR_SUCCESS && current_path_count > 0;
        for (UINT32 i = 0; ready && i < current_path_count; ++i)
            ready = !IsInternalDisplayPath(&current_paths[i]);
        free(current_paths);
        free(current_modes);
        if (ready)
        {
            msg_Info(vd, "temporarily selected the external Windows display "
                     "for HDMI 3D");
            Sleep(250);
            return true;
        }
        Sleep(100);
    }
    msg_Warn(vd, "external-display-only topology did not become active");
    return false;
}

static unsigned StereoMouseLogicalWidth(const vout_display_t *vd)
{
    unsigned width = vd->fmt.i_visible_width;
    if (vd->fmt.i_sar_num > 0 && vd->fmt.i_sar_den > 0)
        width = (uint64_t)width * vd->fmt.i_sar_num /
                vd->fmt.i_sar_den;
    return width;
}

static LONG StereoMouseLogicalX(const vout_display_t *vd, LONG x)
{
    int64_t logical_x = x;
    if (vd->fmt.i_sar_num > 0 && vd->fmt.i_sar_den > 0)
        logical_x = logical_x * vd->fmt.i_sar_num / vd->fmt.i_sar_den;
    return (LONG)VLC_CLIP(logical_x, 0,
                          (int64_t)StereoMouseLogicalWidth(vd));
}

static int StereoMouseMoved(vlc_object_t *object, const char *name,
                            vlc_value_t old_value, vlc_value_t new_value,
                            void *opaque)
{
    VLC_UNUSED(old_value);
    VLC_UNUSED(new_value);
    vout_display_t *vd = opaque;
    vout_display_sys_t *sys = vd->sys;
    if (!sys->stereo_active)
        return VLC_SUCCESS;

    vlc_tick_t now = mdate();
    bool periodic_refresh = name != NULL &&
                            !strcmp(name, "stereo-periodic-refresh");
    bool hover_changed = false;
    vlc_tick_t visibility_duration;
    if (!periodic_refresh)
    {
        /* The exclusive swapchain and the fullscreen child are both moved
         * while Windows commits the external-only topology.  That produces
         * one or more WM_MOUSEMOVE notifications with coordinates from the
         * previous desktop.  They are not user input and, if accepted, can
         * create the bottom-right "+10 seconds" SPU in only one DXGI eye. */
        if (now < sys->stereo_mouse_accept_after)
            return VLC_SUCCESS;

        /* Resizing/repositioning the exclusive HDMI window generates a
         * relative mouse-moved event although the physical pointer did not
         * move. Blu-ray page transitions can therefore resurrect the
         * fullscreen controller (and its bottom-right forward control) while
         * the user navigates exclusively with the keyboard. Apart from being
         * distracting, that stale quad may only be visible in one DXGI eye.
         * Gate activation on the desktop cursor position, which changes only
         * for genuine pointer motion. */
        POINT screen_cursor;
        if (GetCursorPos(&screen_cursor))
        {
            if (sys->stereo_cursor_screen_valid &&
                screen_cursor.x == sys->stereo_cursor_screen.x &&
                screen_cursor.y == sys->stereo_cursor_screen.y)
                return VLC_SUCCESS;
            sys->stereo_cursor_screen = screen_cursor;
            sys->stereo_cursor_screen_valid = true;

            /* A display-topology or fullscreen-window move can clamp the
             * desktop cursor and post WM_MOUSEMOVE with stale client
             * coordinates.  The screen position then really changes, so the
             * equality guard above is insufficient: the stale Y coordinate
             * can falsely place the pointer in the bottom controller and
             * keep its right-hand OSD quad alive for a full day.  Validate
             * the reported video coordinate against the physical pointer in
             * the current child window before creating any SPU. */
            POINT client_cursor = screen_cursor;
            RECT client_rect;
            if (sys->sys.hvideownd != NULL &&
                ScreenToClient(sys->sys.hvideownd, &client_cursor) &&
                GetClientRect(sys->sys.hvideownd, &client_rect))
            {
                int client_height = RECTHeight(client_rect);
                int client_width = RECTWidth(client_rect);
                if (client_width <= 0 || client_height <= 0 ||
                    client_cursor.x < 0 || client_cursor.x >= client_width ||
                    client_cursor.y < 0 || client_cursor.y >= client_height)
                    return VLC_SUCCESS;
                else
                {
                    int64_t expected_y = vd->source.i_y_offset +
                        (int64_t)client_cursor.y * vd->source.i_height /
                        client_height;
                    int64_t delta_y = expected_y - new_value.coords.y;
                    if (delta_y < 0)
                        delta_y = -delta_y;
                    if (delta_y > 4)
                        return VLC_SUCCESS;
                }
            }
        }

        unsigned control_height = vd->fmt.i_visible_height;
        bool controls_hovered = control_height > 0 &&
            new_value.coords.y >= (int)(control_height * 3 / 4);
        hover_changed = controls_hovered != sys->stereo_controls_hovered;
        /* Hovering changes which row receives clicks, but it must not pin an
         * OSD indefinitely.  A stationary pointer gets the same four-second
         * inactivity timeout as the rest of the fullscreen UI. */
        visibility_duration = 4 * CLOCK_FREQ;
        sys->stereo_controls_hovered = controls_hovered;
        sys->stereo_controls_until = now + visibility_duration;
        InterlockedExchange(&sys->stereo_cursor_x,
                            StereoMouseLogicalX(vd, new_value.coords.x));
        InterlockedExchange(&sys->stereo_cursor_y, new_value.coords.y);
    }
    else
    {
        visibility_duration = sys->stereo_controls_until - now;
        if (visibility_duration <= 0)
            return VLC_SUCCESS;
    }
    bool refresh_osd = hover_changed ||
                       now - sys->stereo_controls_last_draw >= CLOCK_FREQ ||
                       now + CLOCK_FREQ / 4 >=
                           sys->stereo_controls_osd_until;

    /* DXGI exclusive mode cannot composite the Windows hardware pointer.
     * Upload its tiny texture only when the controller is refreshed. Its
     * position is changed directly on the cached D3D quad every frame. */
    if (sys->stereo_cursor_channel >= VOUT_SPU_CHANNEL_AVAIL_FIRST &&
        refresh_osd)
    {
        enum { CURSOR_WIDTH = 24, CURSOR_HEIGHT = 34 };
        video_format_t fmt;
        video_format_Init(&fmt, VLC_CODEC_RGBA);
        fmt.i_width = fmt.i_visible_width = CURSOR_WIDTH;
        fmt.i_height = fmt.i_visible_height = CURSOR_HEIGHT;
        fmt.i_sar_num = fmt.i_sar_den = 1;
        subpicture_region_t *region = subpicture_region_New(&fmt);
        video_format_Clean(&fmt);
        if (region != NULL)
        {
            picture_t *pic = region->p_picture;
            for (int y = 0; y < CURSOR_HEIGHT; ++y)
                memset(pic->p[0].p_pixels + y * pic->p[0].i_pitch, 0,
                       CURSOR_WIDTH * 4);
            for (int y = 0; y < 27; ++y)
            {
                int edge = y * 2 / 3;
                for (int x = 0; x <= edge && x < CURSOR_WIDTH; ++x)
                {
                    uint8_t *pixel = pic->p[0].p_pixels +
                                     y * pic->p[0].i_pitch + x * 4;
                    bool border = x == 0 || x >= edge - 2 || y < 2;
                    pixel[0] = border ? 0 : 255;
                    pixel[1] = border ? 0 : 220;
                    pixel[2] = 0;
                    pixel[3] = 255;
                }
            }
            /* Cursor stem. */
            for (int y = 21; y < CURSOR_HEIGHT; ++y)
                for (int x = 8; x < 13; ++x)
                {
                    uint8_t *pixel = pic->p[0].p_pixels +
                                     y * pic->p[0].i_pitch + x * 4;
                    bool border = x == 8 || x == 12 ||
                                  y == CURSOR_HEIGHT - 1;
                    pixel[0] = border ? 0 : 255;
                    pixel[1] = border ? 0 : 220;
                    pixel[2] = 0;
                    pixel[3] = 255;
            }
            unsigned logical_width = StereoMouseLogicalWidth(vd);
            region->i_x = VLC_CLIP(
                StereoMouseLogicalX(vd, new_value.coords.x), 0,
                (int)logical_width - CURSOR_WIDTH);
            region->i_y = VLC_CLIP(new_value.coords.y, 0,
                                   (int)vd->fmt.i_visible_height -
                                   CURSOR_HEIGHT);
            region->i_stereo_offset = INT16_MAX;

            subpicture_t *cursor = subpicture_New(NULL);
            if (cursor != NULL)
            {
                cursor->p_region = region;
                cursor->i_original_picture_width = logical_width;
                cursor->i_original_picture_height = vd->fmt.i_visible_height;
                cursor->i_channel = sys->stereo_cursor_channel;
                cursor->i_start = now;
                cursor->i_stop = now + visibility_duration;
                cursor->b_ephemer = true;
                cursor->b_absolute = true;
                cursor->b_fade = false;
                vout_PutSubpicture((vout_thread_t *)object, cursor);
            }
            else
                subpicture_region_Delete(region);
        }
        sys->stereo_cursor_last_draw = now;
    }
    /* Text rasterization and upload are expensive enough to disturb 23.976-Hz
     * MVC on Ivy Bridge. Refresh shortly before the existing OSD expires,
     * instead of rebuilding it for every mouse event. */
    if (refresh_osd)
    {
        vlc_tick_t osd_duration = visibility_duration;
        sys->stereo_controls_last_draw = now;
        sys->stereo_controls_osd_until = now + osd_duration;
        playlist_t *playlist = (playlist_t *)object->obj.parent;
        input_thread_t *input = playlist != NULL
                              ? playlist_CurrentInput(playlist) : NULL;
        int64_t time = input != NULL ? var_GetInteger(input, "time") : 0;
        int64_t length = input != NULL ? var_GetInteger(input, "length") : 0;
        int state = input != NULL ? var_GetInteger(input, "state") : 0;
        float position = length > 0 ? (float)time / length : 0.f;
        if (position < 0.f)
            position = 0.f;
        else if (position > 1.f)
            position = 1.f;

        enum { PROGRESS_WIDTH = 36 };
        char progress[PROGRESS_WIDTH + 1];
        int cursor = (int)(position * (PROGRESS_WIDTH - 1) + .5f);
        for (int i = 0; i < PROGRESS_WIDTH; ++i)
            progress[i] = i == cursor ? '|' : (i < cursor ? '=' : '-');
        progress[PROGRESS_WIDTH] = '\0';

        char time_text[MSTRTIME_MAX_SIZE];
        char length_text[MSTRTIME_MAX_SIZE];
        secstotimestr(time_text, time / CLOCK_FREQ);
        secstotimestr(length_text, length / CLOCK_FREQ);
        char timeline[384];
        /* A plain trailing space is discarded by the text renderer, which
         * collapses the reserved second row and makes the buttons overwrite
         * the timeline.  NBSP keeps that row's line box without drawing a
         * visible marker. */
        snprintf(timeline, sizeof(timeline),
                 "%s  [%s]  %s\n\xC2\xA0",
                 time_text, progress, length_text);
        if (input != NULL)
            vlc_object_release(input);
        vout_OSDText((vout_thread_t *)object, VOUT_SPU_CHANNEL_OSD,
                     SUBPICTURE_ALIGN_BOTTOM,
                     osd_duration,
                     timeline);
        vout_OSDText((vout_thread_t *)object, sys->stereo_back_channel,
                     SUBPICTURE_ALIGN_LEFT | SUBPICTURE_ALIGN_BOTTOM,
                     osd_duration, "[ -10 seconds ]");
        vout_OSDText((vout_thread_t *)object, sys->stereo_pause_channel,
                     SUBPICTURE_ALIGN_BOTTOM, osd_duration,
                     state == PAUSE_S ? "[ Play ]" : "[ Pause ]");
        vout_OSDText((vout_thread_t *)object, sys->stereo_forward_channel,
                     SUBPICTURE_ALIGN_RIGHT | SUBPICTURE_ALIGN_BOTTOM,
                     osd_duration, "[ +10 seconds ]");
    }
    return VLC_SUCCESS;
}

static int StereoMouseClicked(vlc_object_t *object, const char *name,
                              vlc_value_t old_value, vlc_value_t new_value,
                              void *opaque)
{
    VLC_UNUSED(name);
    VLC_UNUSED(old_value);
    vout_display_t *vd = opaque;
    vout_display_sys_t *sys = vd->sys;
    if (!sys->stereo_active || mdate() > sys->stereo_controls_until)
        return VLC_SUCCESS;

    /* Contrary to the software-pointer quad, Win32 click coordinates arrive
     * in the anamorphic source space for stacked MVC (3840 logical pixels
     * for a 1920-wide surface with SAR 2:1).  Keep hit testing in that space;
     * using the pointer texture's 1920-pixel width shifts Pause onto +10 s. */
    unsigned width = StereoMouseLogicalWidth(vd);
    LONG click_x = StereoMouseLogicalX(vd, new_value.coords.x);
    unsigned height = vd->fmt.i_visible_height;
    if (width == 0 || height == 0 ||
        new_value.coords.y < (int)(height * 3 / 4))
        return VLC_SUCCESS;

    /* Repeated clicks are intentional on the seek buttons.  The Win32
     * window will also synthesize a double-click after the second press;
     * mark this OSD hit so the core does not interpret it as a fullscreen
     * toggle. */
    var_SetInteger(object, "stereo-controls-double-click-until",
                   mdate() + VLC_TICK_FROM_MS(500));

    playlist_t *playlist = (playlist_t *)object->obj.parent;
    input_thread_t *input = playlist != NULL
                          ? playlist_CurrentInput(playlist) : NULL;
    if (new_value.coords.y < (int)(height * 7 / 8))
    {
        /* The progress row spans the middle 90% of the image. */
        float position = ((float)click_x / width - .05f) / .90f;
        if (position < 0.f)
            position = 0.f;
        else if (position > 1.f)
            position = 1.f;
        if (input != NULL)
            var_SetFloat(input, "position", position);
        if (sys->stereo_feedback_channel >=
            VOUT_SPU_CHANNEL_AVAIL_FIRST)
            vout_OSDText((vout_thread_t *)object,
                         sys->stereo_feedback_channel,
                         0,
                         VLC_TICK_FROM_MS(1200), "Seek");
        sys->stereo_controls_osd_until = 0;
        StereoMouseMoved(object, "mouse-moved", old_value, new_value,
                         opaque);
        if (input != NULL)
            vlc_object_release(input);
        return VLC_SUCCESS;
    }

    int zone = (int)((int64_t)click_x * 3 / width);
    int action = zone <= 0 ? ACTIONID_JUMP_BACKWARD_SHORT
               : zone == 1 ? ACTIONID_PLAY_PAUSE
                           : ACTIONID_JUMP_FORWARD_SHORT;
    var_SetInteger(object->obj.libvlc, "key-action", action);
    if (sys->stereo_feedback_channel >= VOUT_SPU_CHANNEL_AVAIL_FIRST)
        vout_OSDText((vout_thread_t *)object,
                     sys->stereo_feedback_channel,
                     0,
                     VLC_TICK_FROM_MS(1200),
                     zone <= 0 ? "-10 s"
                               : zone == 1 ? "Play / Pause" : "+10 s");
    sys->stereo_controls_osd_until = 0;
    StereoMouseMoved(object, "mouse-moved", old_value, new_value, opaque);
    if (input != NULL)
        vlc_object_release(input);
    return VLC_SUCCESS;
}

static void RegisterStereoMouseControls(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    vout_thread_t *vout = (vout_thread_t *)vd->obj.parent;
    if (!sys->stereo_active || vout == NULL)
        return;
    var_AddCallback(vout, "mouse-moved", StereoMouseMoved, vd);
    var_AddCallback(vout, "mouse-clicked", StereoMouseClicked, vd);
    var_Create(vout, "stereo-controls-double-click-until", VLC_VAR_INTEGER);
    var_SetInteger(vout, "stereo-controls-double-click-until", 0);
    sys->stereo_cursor_channel = vout_RegisterSubpictureChannel(vout);
    sys->stereo_feedback_channel = vout_RegisterSubpictureChannel(vout);
    sys->stereo_back_channel = vout_RegisterSubpictureChannel(vout);
    sys->stereo_pause_channel = vout_RegisterSubpictureChannel(vout);
    sys->stereo_forward_channel = vout_RegisterSubpictureChannel(vout);
    sys->stereo_cursor_screen_valid =
        GetCursorPos(&sys->stereo_cursor_screen) != FALSE;
    sys->stereo_mouse_accept_after = mdate() + VLC_TICK_FROM_SEC(1);
    /* During an MVC -> 2D-menu vout handoff Qt briefly reports the new video
     * child as non-fullscreen while it reparents it, even though the adopted
     * Blu-ray HDMI session is still intentionally fullscreen.  Do not let
     * that transient notification tear down and immediately recreate the
     * exclusive stereo swapchain: on Ivy Bridge the round trip can leave a
     * stale black tile in one eye.  This guard begins only once the new vout
     * is operational, and expires quickly so a real user request remains
     * responsive. */
    if (sys->stereo_adopted && sys->stereo_fullscreen_forced)
        sys->stereo_adopted_fullscreen_guard_until =
            mdate() + VLC_TICK_FROM_SEC(2);
    sys->stereo_mouse_callbacks = true;
}

static void UnregisterStereoMouseControls(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    vout_thread_t *vout = (vout_thread_t *)vd->obj.parent;
    if (!sys->stereo_mouse_callbacks || vout == NULL)
        return;
    var_DelCallback(vout, "mouse-moved", StereoMouseMoved, vd);
    var_DelCallback(vout, "mouse-clicked", StereoMouseClicked, vd);
    var_SetInteger(vout, "stereo-controls-double-click-until", 0);
    if (sys->stereo_cursor_channel >= VOUT_SPU_CHANNEL_AVAIL_FIRST)
        vout_FlushSubpictureChannel(vout, sys->stereo_cursor_channel);
    if (sys->stereo_feedback_channel >= VOUT_SPU_CHANNEL_AVAIL_FIRST)
        vout_FlushSubpictureChannel(vout, sys->stereo_feedback_channel);
    if (sys->stereo_back_channel >= VOUT_SPU_CHANNEL_AVAIL_FIRST)
        vout_FlushSubpictureChannel(vout, sys->stereo_back_channel);
    if (sys->stereo_pause_channel >= VOUT_SPU_CHANNEL_AVAIL_FIRST)
        vout_FlushSubpictureChannel(vout, sys->stereo_pause_channel);
    if (sys->stereo_forward_channel >= VOUT_SPU_CHANNEL_AVAIL_FIRST)
        vout_FlushSubpictureChannel(vout, sys->stereo_forward_channel);
    sys->stereo_cursor_channel = VOUT_SPU_CHANNEL_INVALID;
    sys->stereo_feedback_channel = VOUT_SPU_CHANNEL_INVALID;
    sys->stereo_back_channel = VOUT_SPU_CHANNEL_INVALID;
    sys->stereo_pause_channel = VOUT_SPU_CHANNEL_INVALID;
    sys->stereo_forward_channel = VOUT_SPU_CHANNEL_INVALID;
    sys->stereo_cursor_screen_valid = false;
    sys->stereo_mouse_accept_after = VLC_TICK_INVALID;
    sys->stereo_mouse_callbacks = false;
}

static void RestoreStereoOutput(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    if (sys->stereo_display_control != NULL)
    {
        IDXGIDisplayControl_SetStereoEnabled(
            sys->stereo_display_control,
            sys->stereo_display_was_enabled ? TRUE : FALSE);
        IDXGIDisplayControl_Release(sys->stereo_display_control);
        sys->stereo_display_control = NULL;
    }
    sys->stereo_active = false;

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
                                               &sys->stereo_saved_mode, NULL,
                                               CDS_FULLSCREEN, NULL);
        if (result != DISP_CHANGE_SUCCESSFUL)
            msg_Warn(vd, "could not restore the previous Windows display "
                     "mode (%ld)", result);
        else
            msg_Info(vd, "restored the previous Windows display mode");
        sys->stereo_mode_changed = false;
    }

    if (sys->stereo_topology_changed)
    {
        LONG result = SetDisplayConfig(
            sys->stereo_saved_path_count, sys->stereo_saved_paths,
            sys->stereo_saved_mode_count, sys->stereo_saved_modes,
            SDC_APPLY | SDC_USE_SUPPLIED_DISPLAY_CONFIG |
            SDC_ALLOW_CHANGES);
        if (result == ERROR_SUCCESS)
            msg_Info(vd, "restored the previous Windows display topology");
        else
            msg_Warn(vd, "could not restore the previous Windows display "
                     "topology (%ld)", result);
        sys->stereo_topology_changed = false;
    }
    free(sys->stereo_saved_paths);
    free(sys->stereo_saved_modes);
    sys->stereo_saved_paths = NULL;
    sys->stereo_saved_modes = NULL;
    sys->stereo_saved_path_count = 0;
    sys->stereo_saved_mode_count = 0;
}

static bool AdoptStereoOutputHandoff(vout_display_t *vd)
{
    vlc_object_t *vout = vd->obj.parent;
    if (vout == NULL)
        return false;

    win32_stereo_handoff_t *state =
        var_GetAddress(vout, "win32-stereo-display-state");
    if (state == NULL)
        return false;

    vout_display_sys_t *sys = vd->sys;
    sys->stereo_requested = true;
    sys->stereo_adopted = true;
    sys->stereo_windowed = false;
    sys->stereo_mode_changed = state->mode_changed;
    sys->stereo_fullscreen_forced = state->fullscreen_forced;
    sys->stereo_display_was_enabled = state->display_was_enabled;
    sys->stereo_topology_changed = state->topology_changed;
    sys->stereo_eye_width = state->eye_width;
    sys->stereo_eye_height = state->eye_height;
    memcpy(sys->stereo_device, state->device, sizeof(sys->stereo_device));
    sys->stereo_saved_mode = state->saved_mode;
    sys->stereo_saved_paths = state->saved_paths;
    sys->stereo_saved_modes = state->saved_modes;
    sys->stereo_saved_path_count = state->saved_path_count;
    sys->stereo_saved_mode_count = state->saved_mode_count;

    state->saved_paths = NULL;
    state->saved_modes = NULL;
    free(state);
    var_SetAddress(vout, "win32-stereo-display-state", NULL);
    /* If this Open later fails, its Close must restore the adopted topology
     * instead of parking it again for a different display fallback. */
    var_SetBool(vout, "stereo3d-vout-reinit", false);
    msg_Info(vd, "adopted active Windows HDMI 3D session for the new video "
                 "format");
    return true;
}

static bool ParkStereoOutputHandoff(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    vlc_object_t *vout = vd->obj.parent;
    if (!sys->stereo_requested || vout == NULL ||
        !var_GetBool(vout, "stereo3d-vout-reinit"))
        return false;

    win32_stereo_handoff_t *state = calloc(1, sizeof(*state));
    if (state == NULL)
        return false;

    state->mode_changed = sys->stereo_mode_changed;
    state->fullscreen_forced = sys->stereo_fullscreen_forced;
    state->display_was_enabled = sys->stereo_display_was_enabled;
    state->topology_changed = sys->stereo_topology_changed;
    state->eye_width = sys->stereo_eye_width;
    state->eye_height = sys->stereo_eye_height;
    memcpy(state->device, sys->stereo_device, sizeof(state->device));
    state->saved_mode = sys->stereo_saved_mode;
    state->saved_paths = sys->stereo_saved_paths;
    state->saved_modes = sys->stereo_saved_modes;
    state->saved_path_count = sys->stereo_saved_path_count;
    state->saved_mode_count = sys->stereo_saved_mode_count;

    sys->stereo_mode_changed = false;
    sys->stereo_fullscreen_forced = false;
    sys->stereo_topology_changed = false;
    sys->stereo_saved_paths = NULL;
    sys->stereo_saved_modes = NULL;
    sys->stereo_saved_path_count = 0;
    sys->stereo_saved_mode_count = 0;
    if (sys->stereo_display_control != NULL)
    {
        /* Releasing the interface does not disable stereo. The replacement
         * swapchain obtains its own interface while retaining the original
         * pre-session enabled state stored above. */
        IDXGIDisplayControl_Release(sys->stereo_display_control);
        sys->stereo_display_control = NULL;
    }

    var_Create(vout, "win32-stereo-display-state", VLC_VAR_ADDRESS);
    win32_stereo_handoff_t *stale =
        var_GetAddress(vout, "win32-stereo-display-state");
    if (stale != NULL)
    {
        free(stale->saved_paths);
        free(stale->saved_modes);
        free(stale);
    }
    var_SetAddress(vout, "win32-stereo-display-state", state);
    msg_Info(vd, "keeping Windows HDMI 3D active across the video format "
                 "change");
    return true;
}

static bool PrepareStereoOutput(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    msg_Info(vd, "stereo probe: source mode %d, display mode %d, "
             "source %ux%u visible %ux%u at %u/%u fps",
             vd->source.multiview_mode, vd->fmt.multiview_mode,
             vd->source.i_width, vd->source.i_height,
             vd->source.i_visible_width, vd->source.i_visible_height,
             vd->source.i_frame_rate, vd->source.i_frame_rate_base);
    if (!Win32IsFramePackableStereo(vd->fmt.multiview_mode))
    {
        msg_Warn(vd, "stereo probe rejected multiview mode %d",
                 vd->fmt.multiview_mode);
        return false;
    }

    if (!CommonShouldSwitchToStereoDisplay(vd))
        return false;

    unsigned eye_width, eye_height;
    if (!StereoEyeDimensions(&vd->fmt, &eye_width, &eye_height))
        return false;

    double content_rate = 24.0;
    if (vd->fmt.i_frame_rate > 0 && vd->fmt.i_frame_rate_base > 0)
        content_rate = (double)vd->fmt.i_frame_rate /
                       vd->fmt.i_frame_rate_base;

    if (!((eye_width == 1920 && eye_height == 1080 &&
           (RefreshNear(content_rate, 24.0) ||
            RefreshNear(content_rate, 24000.0 / 1001.0))) ||
          (eye_width == 1280 && eye_height == 720 &&
           (RefreshNear(content_rate, 50.0) ||
            RefreshNear(content_rate, 60.0) ||
            RefreshNear(content_rate, 60000.0 / 1001.0)))))
    {
        vlc_dialog_display_error(vd, _("HDMI 3D frame packing unavailable"),
                                 _("PowerVLC cannot select a standardized "
                                   "HDMI frame-packed mode for %ux%u per eye "
                                   "at %.3f Hz."), eye_width, eye_height,
                                 content_rate);
        return false;
    }

    if (!UseExternalDisplayOnly(vd))
    {
        vlc_dialog_display_error(vd, _("HDMI 3D frame packing unavailable"),
                                 _("Windows could not activate the external "
                                   "display by itself."));
        return false;
    }

    HWND window = sys->sys.hparent != NULL ? sys->sys.hparent : sys->sys.hwnd;
    HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
    MONITORINFOEXW info;
    memset(&info, 0, sizeof(info));
    info.cbSize = sizeof(info);
    if (monitor == NULL || !GetMonitorInfoW(monitor, (MONITORINFO *)&info))
    {
        msg_Warn(vd, "cannot identify the monitor hosting the video window");
        return false;
    }
    lstrcpynW(sys->stereo_device, info.szDevice,
              ARRAY_SIZE(sys->stereo_device));
    msg_Info(vd, "stereo target is %ls, eye raster %ux%u at %.3f Hz",
             sys->stereo_device, eye_width, eye_height, content_rate);

    memset(&sys->stereo_saved_mode, 0, sizeof(sys->stereo_saved_mode));
    sys->stereo_saved_mode.dmSize = sizeof(sys->stereo_saved_mode);
    if (!EnumDisplaySettingsExW(sys->stereo_device, ENUM_CURRENT_SETTINGS,
                                &sys->stereo_saved_mode, 0))
    {
        msg_Warn(vd, "cannot read the current mode for %ls",
                 sys->stereo_device);
        return false;
    }

    DWORD preferred_rate = (DWORD)content_rate;
    DWORD alternate_rate = (DWORD)(content_rate + 0.5);
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
            candidate.dmPelsHeight == eye_height &&
            !(candidate.dmDisplayFlags & DM_INTERLACED))
        {
            msg_Dbg(vd, "stereo candidate %lux%lu at %lu Hz flags 0x%lx",
                    candidate.dmPelsWidth, candidate.dmPelsHeight,
                    candidate.dmDisplayFrequency, candidate.dmDisplayFlags);
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
        msg_Warn(vd, "no %ux%u display mode near %.3f Hz is exposed by %ls",
                 eye_width, eye_height, content_rate, sys->stereo_device);
        /* Ivy Bridge's Windows 10 driver hides the HDMI 1.4 frame-packed
         * timings from EnumDisplaySettings.  DXGI still exposes them after
         * SetStereoEnabled(), and Kodi consequently creates the stereo swap
         * chain first instead of rejecting the stream here.  Let DXGI make
         * that authoritative capability check below. */
        goto stereo_ready;
    }
    msg_Info(vd, "selected Windows stereo mode %lux%lu at %lu Hz",
             best.dmPelsWidth, best.dmPelsHeight,
             best.dmDisplayFrequency);

    bool already_active =
        sys->stereo_saved_mode.dmPelsWidth == eye_width &&
        sys->stereo_saved_mode.dmPelsHeight == eye_height &&
        sys->stereo_saved_mode.dmDisplayFrequency == best.dmDisplayFrequency;
    if (!already_active)
    {
        LONG result = ChangeDisplaySettingsExW(sys->stereo_device, &best, NULL,
                                               CDS_TEST, NULL);
        if (result == DISP_CHANGE_SUCCESSFUL)
            result = ChangeDisplaySettingsExW(sys->stereo_device, &best, NULL,
                                              CDS_FULLSCREEN, NULL);
        if (result != DISP_CHANGE_SUCCESSFUL)
        {
            vlc_dialog_display_error(
                vd, _("HDMI 3D frame packing unavailable"),
                _("Windows rejected the %ux%u stereoscopic mode at %lu Hz "
                  "(error %ld)."), eye_width, eye_height,
                best.dmDisplayFrequency, result);
            return false;
        }
        sys->stereo_mode_changed = true;
    }

stereo_ready:
    sys->stereo_eye_width = eye_width;
    sys->stereo_eye_height = eye_height;
    sys->stereo_requested = true;

    vlc_object_t *vout = vd->obj.parent;
    if (vout != NULL && !var_GetBool(vout, "fullscreen"))
    {
        sys->stereo_fullscreen_forced = true;
        var_SetBool(vout, "fullscreen", true);
    }
    UpdateRects(vd, NULL, true);
    return true;
}

static int Open(vlc_object_t *object)
{
    vout_display_t *vd = (vout_display_t *)object;

#if !VLC_WINSTORE_APP
    /* Allow using D3D11 automatically starting from Windows 8.1 */
    if (!vd->obj.force)
    {
        bool isWin81OrGreater = false;
        HMODULE hKernel32 = GetModuleHandle(TEXT("kernel32.dll"));
        if (likely(hKernel32 != NULL))
            isWin81OrGreater = GetProcAddress(hKernel32, "IsProcessCritical") != NULL;
        if (!isWin81OrGreater)
            return VLC_EGENERIC;
    }
#endif

    vout_display_sys_t *sys = vd->sys = calloc(1, sizeof(vout_display_sys_t));
    if (unlikely(sys == NULL))
        return VLC_ENOMEM;
    sys->stereo_spu_reported_order = INT64_MIN;
    int ret = D3D11_Create(vd, &sys->hd3d, true);
    if (unlikely(ret != VLC_SUCCESS))
        goto error;

    ret = OpenCoreW(vd);
    bool external_device = ret == VLC_SUCCESS;
#if VLC_WINSTORE_APP
    if (!external_device)
        return ret;
#endif

    if (external_device)
        sys->sys.src_fmt = &vd->source;
    else if (CommonInit(vd) != VLC_SUCCESS)
        goto error;

#if !VLC_WINSTORE_APP
    if (!external_device && vd->source.dovi.rpu_present &&
        var_InheritBool(vd, "d3d11-dovi-hdmi"))
    {
        sys->dovi_display_attempted = true;
        sys->dovi_display = Win32DoviDisplay_Enable(
            VLC_OBJECT(vd), sys->sys.hvideownd);
    }
#endif

#if !VLC_WINSTORE_APP
    bool adopted_stereo = !external_device &&
                          AdoptStereoOutputHandoff(vd);
    if (!external_device && !adopted_stereo)
        PrepareStereoOutput(vd);
#endif

    vd->sys->sys.pf_GetPictureWidth  = GetPictureWidth;
    vd->sys->sys.pf_GetPictureHeight = GetPictureHeight;

    if (Direct3D11Open(vd, external_device)) {
        msg_Err(vd, "Direct3D11 could not be opened");
        goto error;
    }

#if !VLC_WINSTORE_APP
    if (!external_device)
        RegisterStereoMouseControls(vd);
#endif

#if !VLC_WINSTORE_APP
    if (!external_device)
        EventThreadUpdateTitle(vd->sys->sys.event, VOUT_TITLE " (Direct3D11 output)");
#endif
    msg_Dbg(vd, "Direct3D11 device adapter successfully initialized");

    vd->info.has_double_click     = true;
    vd->info.has_pictures_invalid = vd->info.is_slow;

    if (var_InheritBool(vd, "direct3d11-hw-blending") &&
        vd->sys->d3dregion_format != NULL)
    {
        vd->sys->pSubpictureChromas[0] = vd->sys->d3dregion_format->fourcc;
        vd->sys->pSubpictureChromas[1] = 0;
        vd->info.subpicture_chromas = vd->sys->pSubpictureChromas;
    }
    else
        vd->info.subpicture_chromas = NULL;
    sys->sharedHandle = INVALID_HANDLE_VALUE;

    vd->pool    = Pool;
    vd->prepare = Prepare;
    vd->display = Display;
    vd->control = Control;
    vd->manage  = Manage;

    msg_Dbg(vd, "Direct3D11 Open Succeeded");

    return VLC_SUCCESS;

error:
    Close(object);
    return VLC_EGENERIC;
}

static void Close(vlc_object_t *object)
{
    vout_display_t * vd = (vout_display_t *)object;

    UnregisterStereoMouseControls(vd);
    Direct3D11Close(vd);
#if !VLC_WINSTORE_APP
    Win32DoviDisplay_Restore(VLC_OBJECT(vd), vd->sys->dovi_display);
    vd->sys->dovi_display = NULL;
#endif
#if !VLC_WINSTORE_APP
    if (!ParkStereoOutputHandoff(vd))
#endif
        RestoreStereoOutput(vd);
    CommonClean(vd);
    Direct3D11Destroy(vd);
    free(vd->sys);
}

static picture_pool_t *Pool(vout_display_t *vd, unsigned pool_size)
{
    /* compensate for extra hardware decoding pulling extra pictures from our pool */
    pool_size += 2;

    vout_display_sys_t *sys = vd->sys;
    picture_t **pictures = NULL;
    picture_t *picture;
    unsigned  picture_count = 0;

    if (sys->sys.pool)
        return sys->sys.pool;

    if (vd->info.is_slow)
        pool_size = 1;

    if (D3D11_SetupQuad( vd, &sys->d3d_dev, &sys->quad_fmt, &sys->picQuad, &sys->display, &sys->sys.rect_src_clipped,
                   vd->fmt.projection_mode == PROJECTION_MODE_RECTANGULAR ? sys->flatVSShader : sys->projectionVSShader,
                   sys->pVertexLayout,
                   sys->quad_fmt.projection_mode, vd->fmt.orientation ) != VLC_SUCCESS) {
        msg_Err(vd, "Could not Create the main quad picture.");
        return NULL;
    }

    if ( vd->fmt.projection_mode == PROJECTION_MODE_EQUIRECTANGULAR ||
         vd->fmt.projection_mode == PROJECTION_MODE_CUBEMAP_LAYOUT_STANDARD )
        SetQuadVSProjection( vd, &sys->picQuad, &vd->cfg->viewpoint );

    if (!vd->info.is_slow) {
        HRESULT           hr;
        ID3D10Multithread *pMultithread;
        hr = ID3D11Device_QueryInterface( sys->d3d_dev.d3ddevice, &IID_ID3D10Multithread, (void **)&pMultithread);
        if (SUCCEEDED(hr)) {
            ID3D10Multithread_SetMultithreadProtected(pMultithread, TRUE);
            ID3D10Multithread_Release(pMultithread);
        }
    }

    if (sys->pool_d3dfmt->formatTexture == DXGI_FORMAT_UNKNOWN)
        sys->sys.pool = picture_pool_NewFromFormat( &sys->pool_fmt, pool_size );
    else
    {
        ID3D11Texture2D  *textures[pool_size * D3D11_MAX_SHADER_VIEW];
        memset(textures, 0, sizeof(textures));
        unsigned slices = pool_size;
        if (!CanUseVoutPool(&sys->d3d_dev, pool_size))
            /* only provide enough for the filters, we can still do direct rendering */
            slices = __MIN(slices, 6);

        if (AllocateTextures(vd, &sys->d3d_dev, sys->pool_d3dfmt, &sys->pool_fmt, true, false, slices, textures))
            goto error;

        pictures = calloc(pool_size, sizeof(*pictures));
        if (!pictures)
            goto error;

        for (picture_count = 0; picture_count < pool_size; picture_count++) {
            picture_sys_t *picsys = calloc(1, sizeof(*picsys));
            if (unlikely(picsys == NULL))
                goto error;

            for (unsigned plane = 0; plane < D3D11_MAX_SHADER_VIEW; plane++)
            {
                if (picture_count < slices)
                    picsys->texture[plane] =textures[picture_count * D3D11_MAX_SHADER_VIEW + plane];
                else if (textures[plane])
                {
                    picsys->texture[plane] = textures[plane];
                    ID3D11Texture2D_AddRef(picsys->texture[plane]);
                }
            }

            picsys->slice_index = picture_count < slices ? picture_count : 0;
            picsys->formatTexture = sys->pool_d3dfmt->formatTexture;
            picsys->context = sys->d3d_dev.d3dcontext;

            picture_resource_t resource = {
                .p_sys = picsys,
                .pf_destroy = DestroyDisplayPoolPicture,
            };

            picture = picture_NewFromResource(&sys->pool_fmt, &resource);
            if (unlikely(picture == NULL)) {
                free(picsys);
                msg_Err( vd, "Failed to create picture %d in the pool.", picture_count );
                goto error;
            }

            pictures[picture_count] = picture;
            /* each picture_t holds a ref to the context and release it on Destroy */
            ID3D11DeviceContext_AddRef(picsys->context);
        }

#ifdef HAVE_ID3D11VIDEODECODER
        if (is_d3d11_opaque(sys->pool_fmt.i_chroma) && !sys->legacy_shader)
#endif
        {
            sys->picQuad.resourceCount = DxgiResourceCount(sys->pool_d3dfmt);
            for (picture_count = 0; picture_count < slices; picture_count++) {
                if (!pictures[picture_count]->p_sys->texture[0])
                    continue;
                if (D3D11_AllocateShaderView(vd, sys->d3d_dev.d3ddevice, sys->pool_d3dfmt,
                                       pictures[picture_count]->p_sys->texture, picture_count,
                                       pictures[picture_count]->p_sys->resourceView))
                    goto error;
            }
        }

        picture_pool_configuration_t pool_cfg = {
            .picture       = pictures,
            .picture_count = pool_size,
        };
        if (vd->info.is_slow && !is_d3d11_opaque(sys->pool_fmt.i_chroma)) {
            pool_cfg.lock          = Direct3D11MapPoolTexture;
            //pool_cfg.unlock        = Direct3D11UnmapPoolTexture;
        }
        sys->sys.pool = picture_pool_NewExtended( &pool_cfg );
    }

error:
    if (sys->sys.pool == NULL) {
        picture_pool_configuration_t pool_cfg = {
            .picture_count = 0,
        };
        if (pictures) {
            msg_Dbg(vd, "Failed to create the picture d3d11 pool");
            for (unsigned i=0;i<picture_count; ++i)
                picture_Release(pictures[i]);
            free(pictures);
        }

        /* create an empty pool to avoid crashing */
        sys->sys.pool = picture_pool_NewExtended( &pool_cfg );
    } else {
        msg_Dbg(vd, "D3D11 pool succeed with %d surfaces (%dx%d) context 0x%p",
                pool_size, sys->pool_fmt.i_width, sys->pool_fmt.i_height, sys->d3d_dev.d3dcontext);
    }
    return sys->sys.pool;
}

static void DestroyDisplayPoolPicture(picture_t *picture)
{
    picture_sys_t *p_sys = picture->p_sys;
    ReleasePictureSys( p_sys );
    free(p_sys);
    free(picture);
}

#if !VLC_WINSTORE_APP
static void FillSwapChainDesc(vout_display_t *vd, DXGI_SWAP_CHAIN_DESC1 *out)
{
    vout_display_sys_t *sys = vd->sys;
    ZeroMemory(out, sizeof(*out));
    out->BufferCount = 3;
    out->BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
    out->SampleDesc.Count = 1;
    out->SampleDesc.Quality = 0;
    out->Width = sys->stereo_requested ? sys->stereo_eye_width
                                       : vd->source.i_visible_width;
    out->Height = sys->stereo_requested ? sys->stereo_eye_height
                                        : vd->source.i_visible_height;
    out->Format = DXGI_FORMAT_R8G8B8A8_UNORM; /* TODO: use DXGI_FORMAT_NV12 */
    out->Stereo = sys->stereo_requested ? TRUE : FALSE;
    if (sys->stereo_requested)
        out->Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    else if (sys->hdrMode == hdr_Always || sys->hdrMode == hdr_Fake)
        out->Format = DXGI_FORMAT_R10G10B10A2_UNORM;
    else if (sys->hdrMode == hdr_Auto)
    {
        if ( vd->source.i_chroma == VLC_CODEC_D3D11_OPAQUE_10B ||
             vd->source.transfer == TRANSFER_FUNC_SMPTE_ST2084 ||
             vd->source.transfer == TRANSFER_FUNC_HLG)
            out->Format = DXGI_FORMAT_R10G10B10A2_UNORM;
    }
    //out->Flags = 512; // DXGI_SWAP_CHAIN_FLAG_YUV_VIDEO;

    bool isWin10OrGreater = false;
    HMODULE hKernelBase = GetModuleHandle(TEXT("kernelbase.dll"));
    if (likely(hKernelBase != NULL))
    {
        isWin10OrGreater = GetProcAddress(hKernelBase, "VirtualAllocFromApp") != NULL;
        FreeLibrary(hKernelBase);
    }
    if (sys->stereo_requested)
        out->SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
    else if (isWin10OrGreater)
        out->SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    else
    {
        bool isWin81OrGreater = false;
        HMODULE hKernel32 = GetModuleHandle(TEXT("kernel32.dll"));
        if (likely(hKernel32 != NULL))
            isWin81OrGreater = GetProcAddress(hKernel32, "IsProcessCritical") != NULL;
        if (isWin81OrGreater)
            out->SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
        else
        {
            out->SwapEffect = DXGI_SWAP_EFFECT_DISCARD;
            out->BufferCount = 1;
        }
    }
}

static DXGI_RATIONAL StereoRefreshRate(const video_format_t *fmt)
{
    double rate = 24.0;
    if (fmt->i_frame_rate > 0 && fmt->i_frame_rate_base > 0)
        rate = (double)fmt->i_frame_rate / fmt->i_frame_rate_base;

    DXGI_RATIONAL refresh;
    if (RefreshNear(rate, 24000.0 / 1001.0))
    {
        refresh.Numerator = 24000;
        refresh.Denominator = 1001;
    }
    else if (RefreshNear(rate, 60000.0 / 1001.0))
    {
        refresh.Numerator = 60000;
        refresh.Denominator = 1001;
    }
    else
    {
        refresh.Numerator = (UINT)(rate + 0.5) * 1000;
        refresh.Denominator = 1000;
    }
    return refresh;
}

static HWND StereoSwapChainWindow(const vout_display_sys_t *sys)
{
    HWND root = GetAncestor(sys->sys.hvideownd, GA_ROOT);
    return root != NULL ? root : sys->sys.hvideownd;
}

/* Intel's Ivy Bridge driver does not advertise the HDMI 1.4 3D timings to
 * EnumDisplaySettings.  The MVC Kodi fork primes the driver with an ordinary
 * swap chain in exclusive mode, calls ResizeTarget with the desired per-eye
 * timing, tears it down, and only then enables DXGI stereo. */
static HRESULT PrimeStereoDisplay(vout_display_t *vd,
                                  IDXGIFactory2 *factory,
                                  IDXGIOutput **output)
{
    vout_display_sys_t *sys = vd->sys;
    DXGI_SWAP_CHAIN_DESC1 desc;
    FillSwapChainDesc(vd, &desc);
    desc.Stereo = FALSE;
    desc.Flags = DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;

    DXGI_SWAP_CHAIN_FULLSCREEN_DESC fs_desc;
    ZeroMemory(&fs_desc, sizeof(fs_desc));
    fs_desc.RefreshRate = StereoRefreshRate(&vd->fmt);
    fs_desc.ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_PROGRESSIVE;
    fs_desc.Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
    fs_desc.Windowed = TRUE;

    IDXGISwapChain1 *bootstrap = NULL;
    HWND swapchain_window = StereoSwapChainWindow(sys);
    msg_Info(vd, "stereo window video=%p parent=%p fullscreen=%p root=%p",
             sys->sys.hvideownd, sys->sys.hparent, sys->sys.hfswnd,
             swapchain_window);
    HRESULT hr = IDXGIFactory2_CreateSwapChainForHwnd(
        factory, (IUnknown *)sys->d3d_dev.d3ddevice,
        swapchain_window, &desc, &fs_desc, NULL, &bootstrap);
    msg_Info(vd, "stereo bootstrap mono swapchain: hr=0x%lX", hr);
    if (FAILED(hr))
        return hr;

    hr = IDXGISwapChain_GetContainingOutput(bootstrap, output);
    msg_Info(vd, "stereo bootstrap containing output: hr=0x%lX", hr);
    if (SUCCEEDED(hr))
    {
        hr = IDXGISwapChain_SetFullscreenState(bootstrap, TRUE, *output);
        msg_Info(vd, "stereo bootstrap exclusive fullscreen: hr=0x%lX", hr);
    }

    if (SUCCEEDED(hr))
    {
        DXGI_MODE_DESC target;
        ZeroMemory(&target, sizeof(target));
        target.Width = sys->stereo_eye_width;
        target.Height = sys->stereo_eye_height;
        target.RefreshRate = fs_desc.RefreshRate;
        target.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        target.ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_PROGRESSIVE;
        target.Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
        hr = IDXGISwapChain_ResizeTarget(bootstrap, &target);
        msg_Info(vd, "stereo bootstrap ResizeTarget %ux%u at %u/%u: "
                 "hr=0x%lX", target.Width, target.Height,
                 target.RefreshRate.Numerator,
                 target.RefreshRate.Denominator, hr);
    }

    BOOL fullscreen = FALSE;
    if (SUCCEEDED(IDXGISwapChain_GetFullscreenState(bootstrap, &fullscreen,
                                                    NULL)) && fullscreen)
    {
        HRESULT leave_hr = IDXGISwapChain_SetFullscreenState(bootstrap,
                                                              FALSE, NULL);
        msg_Info(vd, "stereo bootstrap leave exclusive fullscreen: "
                 "hr=0x%lX", leave_hr);
    }
    IDXGISwapChain1_Release(bootstrap);
    return hr;
}

static HRESULT EnterStereoFullscreen(vout_display_t *vd, const char *phase,
                                     IDXGIOutput *known_output)
{
    vout_display_sys_t *sys = vd->sys;
    IDXGIOutput *output = known_output;
    HRESULT hr = S_OK;
    if (output != NULL)
        IDXGIOutput_AddRef(output);
    else
        hr = IDXGISwapChain_GetContainingOutput(sys->dxgiswapChain, &output);
    if (SUCCEEDED(hr))
        hr = IDXGISwapChain_SetFullscreenState(sys->dxgiswapChain, TRUE,
                                               output);
    if (SUCCEEDED(hr))
    {
        DXGI_MODE_DESC target;
        ZeroMemory(&target, sizeof(target));
        target.Width = sys->stereo_eye_width;
        target.Height = sys->stereo_eye_height;
        target.RefreshRate = StereoRefreshRate(&vd->fmt);
        target.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
        target.ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_PROGRESSIVE;
        target.Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
        hr = IDXGISwapChain_ResizeTarget(sys->dxgiswapChain, &target);
    }
    BOOL fullscreen = FALSE;
    HRESULT state_hr = IDXGISwapChain_GetFullscreenState(sys->dxgiswapChain,
                                                         &fullscreen, NULL);
    msg_Info(vd, "DXGI stereo exclusive %s: fullscreen=%d, hr=0x%lX, "
             "state_hr=0x%lX", phase, fullscreen != FALSE, hr, state_hr);
    if (output != NULL)
        IDXGIOutput_Release(output);
    return FAILED(hr) ? hr : (fullscreen ? S_OK : E_FAIL);
}

static void LogStereoModes(vout_display_t *vd, IDXGIOutput *output,
                           DXGI_FORMAT format)
{
    IDXGIOutput1 *output1 = NULL;
    HRESULT hr = IDXGIOutput_QueryInterface(output, &IID_IDXGIOutput1,
                                             (void **)&output1);
    if (FAILED(hr))
        return;
    UINT count = 0;
    hr = IDXGIOutput1_GetDisplayModeList1(output1, format,
                                          DXGI_ENUM_MODES_STEREO,
                                          &count, NULL);
    msg_Info(vd, "DXGI stereo mode list format %d: count=%u hr=0x%lX",
             format, count, hr);
    if (SUCCEEDED(hr) && count > 0)
    {
        DXGI_MODE_DESC1 *modes = malloc(count * sizeof(*modes));
        if (modes != NULL && SUCCEEDED(IDXGIOutput1_GetDisplayModeList1(
                output1, format, DXGI_ENUM_MODES_STEREO, &count, modes)))
        {
            for (UINT i = 0; i < count; ++i)
                if (modes[i].Stereo ||
                    (modes[i].Width == vd->sys->stereo_eye_width &&
                     modes[i].Height == vd->sys->stereo_eye_height))
                    msg_Info(vd, "DXGI stereo candidate %ux%u %u/%u "
                             "stereo=%d scan=%d scaling=%d", modes[i].Width,
                             modes[i].Height, modes[i].RefreshRate.Numerator,
                             modes[i].RefreshRate.Denominator,
                             modes[i].Stereo != FALSE,
                             modes[i].ScanlineOrdering, modes[i].Scaling);
        }
        free(modes);
    }
    IDXGIOutput1_Release(output1);
}
#endif

static int UpdateSamplers(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    HRESULT hr;

    D3D11_SAMPLER_DESC sampDesc;
    memset(&sampDesc, 0, sizeof(sampDesc));
    sampDesc.AddressU = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampDesc.AddressV = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampDesc.AddressW = D3D11_TEXTURE_ADDRESS_CLAMP;
    sampDesc.ComparisonFunc = D3D11_COMPARISON_ALWAYS;
    sampDesc.MinLOD = 0;
    sampDesc.MaxLOD = D3D11_FLOAT32_MAX;

    d3d11_device_lock(&sys->d3d_dev);

    ID3D11SamplerState *d3dsampState[2];
    if (sys->upscaleMode == upscale_PointSampler)
        sampDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
    else
        sampDesc.Filter = D3D11_FILTER_MIN_MAG_LINEAR_MIP_POINT;
    hr = ID3D11Device_CreateSamplerState(sys->d3d_dev.d3ddevice, &sampDesc, &d3dsampState[0]);
    if (FAILED(hr)) {
        msg_Err(vd, "Could not Create the D3d11 Sampler State. (hr=0x%lX)", hr);
        d3d11_device_unlock(&sys->d3d_dev);
        return VLC_EGENERIC;
    }

    sampDesc.Filter = D3D11_FILTER_MIN_MAG_MIP_POINT;
    hr = ID3D11Device_CreateSamplerState(sys->d3d_dev.d3ddevice, &sampDesc, &d3dsampState[1]);
    if (FAILED(hr)) {
        msg_Err(vd, "Could not Create the D3d11 Sampler State. (hr=0x%lX)", hr);
        ID3D11SamplerState_Release(d3dsampState[0]);
        d3d11_device_unlock(&sys->d3d_dev);
        return VLC_EGENERIC;
    }

    ID3D11DeviceContext_PSSetSamplers(sys->d3d_dev.d3dcontext, 0, 2, d3dsampState);
    ID3D11SamplerState_Release(d3dsampState[0]);
    ID3D11SamplerState_Release(d3dsampState[1]);

    d3d11_device_unlock(&sys->d3d_dev);
    return VLC_SUCCESS;
}

static HRESULT UpdateBackBuffer(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    HRESULT hr;
    ID3D11Texture2D* pDepthStencil;
    ID3D11Texture2D* pBackBuffer;
    UINT window_width, window_height;
    bool proc_upscale = sys->upscaleMode == upscale_VideoProcessor || sys->upscaleMode == upscale_SuperResolution;
    if ((sys->sys.pf_GetWindowSize != GetWinRTSize && !proc_upscale)
    || !sys->sys.pf_GetWindowSize(&sys->sys, &window_width, &window_height))
    {
        window_width  = RECTWidth(sys->sys.rect_dest_clipped);
        window_height = RECTHeight(sys->sys.rect_dest_clipped);
    }
    if (sys->stereo_active)
    {
        window_width = sys->stereo_eye_width;
        window_height = sys->stereo_eye_height;
    }

    if (proc_upscale)
    {
        vout_display_cfg_t cfg = *vd->cfg;
        cfg.display.width = window_width;
        cfg.display.height = window_height;
        D3D11_UpscalerUpdate(VLC_OBJECT(vd), sys->scaleProc, &sys->d3d_dev,
                             &sys->pool_fmt, &sys->quad_fmt, &cfg);

        if (sys->tonemapProc)
            D3D11_TonemapperUpdate(VLC_OBJECT(vd), sys->tonemapProc, &sys->d3d_dev,
                                   &sys->quad_fmt);
    }

    D3D11_TEXTURE2D_DESC dsc = { 0 };

    if (sys->d3drenderTargetView) {
        ID3D11Resource *res = NULL;
        ID3D11RenderTargetView_GetResource(sys->d3drenderTargetView, &res);
        if (res)
        {
            ID3D11Texture2D_GetDesc((ID3D11Texture2D*) res, &dsc);
            ID3D11Resource_Release(res);
        }
    }

    if (dsc.Width == window_width && dsc.Height == window_height &&
        (!sys->stereo_active || sys->d3drenderTargetViewRight != NULL))
        return S_OK; /* nothing changed */

    if (sys->d3drenderTargetView) {
        ID3D11RenderTargetView_Release(sys->d3drenderTargetView);
        sys->d3drenderTargetView = NULL;
    }
    if (sys->d3drenderTargetViewRight) {
        ID3D11RenderTargetView_Release(sys->d3drenderTargetViewRight);
        sys->d3drenderTargetViewRight = NULL;
    }
    if (sys->d3ddepthStencilView) {
        ID3D11DepthStencilView_Release(sys->d3ddepthStencilView);
        sys->d3ddepthStencilView = NULL;
    }

    /* TODO detect is the size is the same as the output and switch to fullscreen mode */
    hr = IDXGISwapChain_ResizeBuffers(sys->dxgiswapChain, 0, window_width, window_height,
        DXGI_FORMAT_UNKNOWN, 0);
    if (FAILED(hr)) {
       msg_Err(vd, "Failed to resize the backbuffer. (hr=0x%lX)", hr);
       return hr;
    }

    hr = IDXGISwapChain_GetBuffer(sys->dxgiswapChain, 0, &IID_ID3D11Texture2D, (LPVOID *)&pBackBuffer);
    if (FAILED(hr)) {
       msg_Err(vd, "Could not get the backbuffer for the Swapchain. (hr=0x%lX)", hr);
       return hr;
    }

    if (sys->stereo_active)
    {
        D3D11_TEXTURE2D_DESC backDesc;
        ID3D11Texture2D_GetDesc(pBackBuffer, &backDesc);
        if (backDesc.ArraySize < 2)
        {
            ID3D11Texture2D_Release(pBackBuffer);
            msg_Err(vd, "DXGI stereo back buffer has only %u array slice",
                    backDesc.ArraySize);
            return E_FAIL;
        }
        D3D11_RENDER_TARGET_VIEW_DESC viewDesc;
        memset(&viewDesc, 0, sizeof(viewDesc));
        viewDesc.Format = backDesc.Format;
        viewDesc.ViewDimension = D3D11_RTV_DIMENSION_TEXTURE2DARRAY;
        viewDesc.Texture2DArray.MipSlice = 0;
        viewDesc.Texture2DArray.ArraySize = 1;
        viewDesc.Texture2DArray.FirstArraySlice = 0;
        hr = ID3D11Device_CreateRenderTargetView(
            sys->d3d_dev.d3ddevice, (ID3D11Resource *)pBackBuffer,
            &viewDesc, &sys->d3drenderTargetView);
        if (SUCCEEDED(hr))
        {
            viewDesc.Texture2DArray.FirstArraySlice = 1;
            hr = ID3D11Device_CreateRenderTargetView(
                sys->d3d_dev.d3ddevice, (ID3D11Resource *)pBackBuffer,
                &viewDesc, &sys->d3drenderTargetViewRight);
        }
    }
    else
        hr = ID3D11Device_CreateRenderTargetView(
            sys->d3d_dev.d3ddevice, (ID3D11Resource *)pBackBuffer, NULL,
            &sys->d3drenderTargetView);
    ID3D11Texture2D_Release(pBackBuffer);
    if (FAILED(hr)) {
        msg_Err(vd, "Failed to create the target view. (hr=0x%lX)", hr);
        if (sys->d3drenderTargetView) {
            ID3D11RenderTargetView_Release(sys->d3drenderTargetView);
            sys->d3drenderTargetView = NULL;
        }
        return hr;
    }

    D3D11_TEXTURE2D_DESC deptTexDesc;
    memset(&deptTexDesc, 0,sizeof(deptTexDesc));
    deptTexDesc.ArraySize = 1;
    deptTexDesc.BindFlags = D3D11_BIND_DEPTH_STENCIL;
    deptTexDesc.CPUAccessFlags = 0;
    deptTexDesc.Format = DXGI_FORMAT_D24_UNORM_S8_UINT;
    deptTexDesc.Width = window_width;
    deptTexDesc.Height = window_height;
    deptTexDesc.MipLevels = 1;
    deptTexDesc.MiscFlags = 0;
    deptTexDesc.SampleDesc.Count = 1;
    deptTexDesc.SampleDesc.Quality = 0;
    deptTexDesc.Usage = D3D11_USAGE_DEFAULT;

    hr = ID3D11Device_CreateTexture2D(sys->d3d_dev.d3ddevice, &deptTexDesc, NULL, &pDepthStencil);
    if (FAILED(hr)) {
       msg_Err(vd, "Could not create the depth stencil texture. (hr=0x%lX)", hr);
       return hr;
    }

    D3D11_DEPTH_STENCIL_VIEW_DESC depthViewDesc;
    memset(&depthViewDesc, 0, sizeof(depthViewDesc));

    depthViewDesc.Format = deptTexDesc.Format;
    depthViewDesc.ViewDimension = D3D11_DSV_DIMENSION_TEXTURE2D;
    depthViewDesc.Texture2D.MipSlice = 0;

    hr = ID3D11Device_CreateDepthStencilView(sys->d3d_dev.d3ddevice, (ID3D11Resource *)pDepthStencil, &depthViewDesc, &sys->d3ddepthStencilView);
    ID3D11Texture2D_Release(pDepthStencil);

    if (FAILED(hr)) {
       msg_Err(vd, "Could not create the depth stencil view. (hr=0x%lX)", hr);
       return hr;
    }

    return S_OK;
}

#if !VLC_WINSTORE_APP
static void ReleaseSwapChainForStereoTransition(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    ID3D11DeviceContext_OMSetRenderTargets(sys->d3d_dev.d3dcontext,
                                           0, NULL, NULL);
    if (sys->stereo_present_output != NULL)
    {
        IDXGIOutput_Release(sys->stereo_present_output);
        sys->stereo_present_output = NULL;
    }
    if (sys->d3drenderTargetView != NULL)
    {
        ID3D11RenderTargetView_Release(sys->d3drenderTargetView);
        sys->d3drenderTargetView = NULL;
    }
    if (sys->d3drenderTargetViewRight != NULL)
    {
        ID3D11RenderTargetView_Release(sys->d3drenderTargetViewRight);
        sys->d3drenderTargetViewRight = NULL;
    }
    if (sys->d3ddepthStencilView != NULL)
    {
        ID3D11DepthStencilView_Release(sys->d3ddepthStencilView);
        sys->d3ddepthStencilView = NULL;
    }
    if (sys->dxgiswapChain4 != NULL)
    {
        IDXGISwapChain_Release(sys->dxgiswapChain4);
        sys->dxgiswapChain4 = NULL;
    }
    if (sys->dxgiswapChain != NULL)
    {
        BOOL fullscreen = FALSE;
        if (SUCCEEDED(IDXGISwapChain_GetFullscreenState(
                          sys->dxgiswapChain, &fullscreen, NULL)) &&
            fullscreen)
            IDXGISwapChain_SetFullscreenState(sys->dxgiswapChain,
                                              FALSE, NULL);
        IDXGISwapChain1_Release(sys->dxgiswapChain);
        sys->dxgiswapChain = NULL;
    }
    ID3D11DeviceContext_Flush(sys->d3d_dev.d3dcontext);
}

static HRESULT GetSwapChainFactory(vout_display_t *vd,
                                   IDXGIFactory2 **factory)
{
    vout_display_sys_t *sys = vd->sys;
    IDXGIAdapter *adapter = D3D11DeviceAdapter(sys->d3d_dev.d3ddevice);
    if (adapter == NULL)
        return E_FAIL;
    HRESULT hr = IDXGIAdapter_GetParent(adapter, &IID_IDXGIFactory2,
                                        (void **)factory);
    IDXGIAdapter_Release(adapter);
    return hr;
}

static HRESULT SwitchStereoStreamToWindowedMono(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    IDXGIFactory2 *factory = NULL;
    HRESULT hr = GetSwapChainFactory(vd, &factory);
    if (FAILED(hr))
        return hr;

    ReleaseSwapChainForStereoTransition(vd);
    sys->stereo_active = false;

    /* Keep stereo_requested as the stream capability flag, but build this
     * replacement exactly like VLC's ordinary composited swapchain. */
    bool requested = sys->stereo_requested;
    sys->stereo_requested = false;
    DXGI_SWAP_CHAIN_DESC1 desc;
    FillSwapChainDesc(vd, &desc);
    sys->stereo_requested = requested;

    hr = IDXGIFactory2_CreateSwapChainForHwnd(
        factory, (IUnknown *)sys->d3d_dev.d3ddevice,
        sys->sys.hvideownd, &desc, NULL, NULL, &sys->dxgiswapChain);
    IDXGIFactory2_Release(factory);
    if (FAILED(hr))
    {
        msg_Err(vd, "could not create the mono windowed swapchain "
                "(hr=0x%lX)", hr);
        return hr;
    }

    IDXGISwapChain_QueryInterface(sys->dxgiswapChain,
                                  &IID_IDXGISwapChain4,
                                  (void **)&sys->dxgiswapChain4);
    hr = UpdateBackBuffer(vd);
    if (SUCCEEDED(hr))
    {
        CallUpdateRects(vd);
        msg_Info(vd, "MVC playback switched to a composited mono window");
    }
    return hr;
}

static HRESULT SwitchStereoStreamToExclusive(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    IDXGIFactory2 *factory = NULL;
    HRESULT hr = GetSwapChainFactory(vd, &factory);
    if (FAILED(hr))
        return hr;

    ReleaseSwapChainForStereoTransition(vd);

    IDXGIOutput *output = NULL;
    hr = PrimeStereoDisplay(vd, factory, &output);
    if (FAILED(hr))
        goto done;

    if (sys->stereo_display_control != NULL &&
        !IDXGIDisplayControl_IsStereoEnabled(sys->stereo_display_control))
        IDXGIDisplayControl_SetStereoEnabled(sys->stereo_display_control,
                                             TRUE);

    DXGI_SWAP_CHAIN_DESC1 desc;
    FillSwapChainDesc(vd, &desc);
    desc.Flags |= DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
    DXGI_SWAP_CHAIN_FULLSCREEN_DESC fs_desc;
    ZeroMemory(&fs_desc, sizeof(fs_desc));
    fs_desc.RefreshRate = StereoRefreshRate(&vd->fmt);
    fs_desc.ScanlineOrdering = DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
    fs_desc.Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
    fs_desc.Windowed = FALSE;

    hr = IDXGIFactory2_CreateSwapChainForHwnd(
        factory, (IUnknown *)sys->d3d_dev.d3ddevice,
        StereoSwapChainWindow(sys), &desc, &fs_desc, NULL,
        &sys->dxgiswapChain);
    if (FAILED(hr))
        goto done;

    DXGI_SWAP_CHAIN_DESC1 created;
    hr = IDXGISwapChain1_GetDesc1(sys->dxgiswapChain, &created);
    if (FAILED(hr) || !created.Stereo)
    {
        hr = E_FAIL;
        goto done;
    }
    hr = EnterStereoFullscreen(vd, "after windowed playback", output);
    if (FAILED(hr))
        goto done;

    sys->stereo_active = true;
    IDXGISwapChain_QueryInterface(sys->dxgiswapChain,
                                  &IID_IDXGISwapChain4,
                                  (void **)&sys->dxgiswapChain4);
    hr = UpdateBackBuffer(vd);
    if (SUCCEEDED(hr))
    {
        sys->stereo_present_output = output;
        IDXGIOutput_AddRef(sys->stereo_present_output);
        CallUpdateRects(vd);
        msg_Info(vd, "MVC playback switched back to HDMI frame packing");
    }

done:
    if (output != NULL)
        IDXGIOutput_Release(output);
    IDXGIFactory2_Release(factory);
    return hr;
}
#endif

/* rotation around the Z axis */
static void getZRotMatrix(float theta, FLOAT matrix[static 16])
{
    float st, ct;

    sincosf(theta, &st, &ct);

    const FLOAT m[] = {
    /*  x    y    z    w */
        ct,  -st, 0.f, 0.f,
        st,  ct,  0.f, 0.f,
        0.f, 0.f, 1.f, 0.f,
        0.f, 0.f, 0.f, 1.f
    };

    memcpy(matrix, m, sizeof(m));
}

/* rotation around the Y axis */
static void getYRotMatrix(float theta, FLOAT matrix[static 16])
{
    float st, ct;

    sincosf(theta, &st, &ct);

    const FLOAT m[] = {
    /*  x    y    z    w */
        ct,  0.f, -st, 0.f,
        0.f, 1.f, 0.f, 0.f,
        st,  0.f, ct,  0.f,
        0.f, 0.f, 0.f, 1.f
    };

    memcpy(matrix, m, sizeof(m));
}

/* rotation around the X axis */
static void getXRotMatrix(float phi, FLOAT matrix[static 16])
{
    float sp, cp;

    sincosf(phi, &sp, &cp);

    const FLOAT m[] = {
    /*  x    y    z    w */
        1.f, 0.f, 0.f, 0.f,
        0.f, cp,  sp,  0.f,
        0.f, -sp, cp,  0.f,
        0.f, 0.f, 0.f, 1.f
    };

    memcpy(matrix, m, sizeof(m));
}

static void getZoomMatrix(float zoom, FLOAT matrix[static 16]) {

    const FLOAT m[] = {
        /* x   y     z     w */
        1.0f, 0.0f, 0.0f, 0.0f,
        0.0f, 1.0f, 0.0f, 0.0f,
        0.0f, 0.0f, 1.0f, 0.0f,
        0.0f, 0.0f, zoom, 1.0f
    };

    memcpy(matrix, m, sizeof(m));
}

/* perspective matrix see https://www.opengl.org/sdk/docs/man2/xhtml/gluPerspective.xml */
static void getProjectionMatrix(float sar, float fovy, FLOAT matrix[static 16]) {

    float zFar  = 1000;
    float zNear = 0.01;

    float f = 1.f / tanf(fovy / 2.f);

    const FLOAT m[] = {
        f / sar, 0.f,                   0.f,                0.f,
        0.f,     f,                     0.f,                0.f,
        0.f,     0.f,     (zNear + zFar) / (zNear - zFar), -1.f,
        0.f,     0.f, (2 * zNear * zFar) / (zNear - zFar),  0.f};

     memcpy(matrix, m, sizeof(m));
}

static float UpdateFOVy(float f_fovx, float f_sar)
{
    return 2 * atanf(tanf(f_fovx / 2) / f_sar);
}

static float UpdateZ(float f_fovx, float f_fovy)
{
    /* Do trigonometry to calculate the minimal z value
     * that will allow us to zoom out without seeing the outside of the
     * sphere (black borders). */
    float tan_fovx_2 = tanf(f_fovx / 2);
    float tan_fovy_2 = tanf(f_fovy / 2);
    float z_min = - SPHERE_RADIUS / sinf(atanf(sqrtf(
                    tan_fovx_2 * tan_fovx_2 + tan_fovy_2 * tan_fovy_2)));

    /* The FOV value above which z is dynamically calculated. */
    const float z_thresh = 90.f;

    float f_z;
    if (f_fovx <= z_thresh * M_PI / 180)
        f_z = 0;
    else
    {
        float f = z_min / ((FIELD_OF_VIEW_DEGREES_MAX - z_thresh) * M_PI / 180);
        f_z = f * f_fovx - f * z_thresh * M_PI / 180;
        if (f_z < z_min)
            f_z = z_min;
    }
    return f_z;
}

static void SetQuadVSProjection(vout_display_t *vd, d3d_quad_t *quad, const vlc_viewpoint_t *p_vp)
{
    if (!quad->pVertexShaderConstants)
        return;

#define RAD(d) ((float) ((d) * M_PI / 180.f))
    float f_fovx = RAD(p_vp->fov);
    if ( f_fovx > FIELD_OF_VIEW_DEGREES_MAX * M_PI / 180 + 0.001f ||
         f_fovx < -0.001f )
        return;

    float f_sar = (float) vd->cfg->display.width / vd->cfg->display.height;
    float f_teta = RAD(p_vp->yaw) - (float) M_PI_2;
    float f_phi  = RAD(p_vp->pitch);
    float f_roll = RAD(p_vp->roll);
    float f_fovy = UpdateFOVy(f_fovx, f_sar);
    float f_z = UpdateZ(f_fovx, f_fovy);

    vout_display_sys_t *sys = vd->sys;
    HRESULT hr;
    D3D11_MAPPED_SUBRESOURCE mapped;
    hr = ID3D11DeviceContext_Map(sys->d3d_dev.d3dcontext, (ID3D11Resource *)quad->pVertexShaderConstants, 0, D3D11_MAP_WRITE_DISCARD, 0, &mapped);
    if (SUCCEEDED(hr)) {
        VS_PROJECTION_CONST *dst_data = mapped.pData;
        getXRotMatrix(f_phi, dst_data->RotX);
        getYRotMatrix(f_teta,   dst_data->RotY);
        getZRotMatrix(f_roll,  dst_data->RotZ);
        getZoomMatrix(SPHERE_RADIUS * f_z, dst_data->View);
        getProjectionMatrix(f_sar, f_fovy, dst_data->Projection);
    }
    ID3D11DeviceContext_Unmap(sys->d3d_dev.d3dcontext, (ID3D11Resource *)quad->pVertexShaderConstants, 0);
#undef RAD
}

static void UpdateSize(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    sys->d3dregion_order_valid = false;
    msg_Dbg(vd, "Detected size change %dx%d", RECTWidth(sys->sys.rect_dest_clipped),
            RECTHeight(sys->sys.rect_dest_clipped));

    UpdateBackBuffer(vd);

    d3d11_device_lock( &sys->d3d_dev );

    UpdatePicQuadPosition(vd);

    D3D11_UpdateQuadPosition(vd, &sys->d3d_dev, &sys->picQuad, &sys->sys.rect_src_clipped,
                             vd->fmt.orientation);

    d3d11_device_unlock( &sys->d3d_dev );
}

static inline bool RectEquals(const RECT *r1, const RECT *r2)
{
    return r1->bottom == r2->bottom && r1->top == r2->top &&
           r1->left == r2->left && r1->right == r2->right;
}

static int Control(vout_display_t *vd, int query, va_list args)
{
    vout_display_sys_t *sys = vd->sys;
    RECT before_src_clipped  = sys->sys.rect_src_clipped;
    RECT before_dest_clipped = sys->sys.rect_dest_clipped;
    RECT before_dest         = sys->sys.rect_dest;
#if !VLC_WINSTORE_APP
    bool stereo_fullscreen_change = false;
    bool stereo_wants_fullscreen = false;
    if (query == VOUT_DISPLAY_CHANGE_FULLSCREEN &&
        sys->stereo_active && !sys->stereo_windowed)
    {
        va_list peek;
        va_copy(peek, args);
        stereo_wants_fullscreen = va_arg(peek, int) != 0;
        va_end(peek);
        stereo_fullscreen_change = true;

        if (!stereo_wants_fullscreen && sys->stereo_adopted &&
            mdate() < sys->stereo_adopted_fullscreen_guard_until)
        {
            msg_Info(vd, "ignored transient fullscreen exit while adopting "
                         "the Blu-ray HDMI 3D session");
            return VLC_SUCCESS;
        }

        /* CommonControl only changes the Win32/Qt window.  DXGI exclusive
         * state is independent, so explicitly release it before Qt reparents
         * the video back into the normal application window. */
        if (!stereo_wants_fullscreen)
        {
            HRESULT hr = IDXGISwapChain_SetFullscreenState(
                sys->dxgiswapChain, FALSE, NULL);
            msg_Info(vd, "left DXGI stereo exclusive mode for windowed "
                     "playback (hr=0x%lX)", hr);
            sys->stereo_fullscreen_forced = false;
        }
    }
#endif

    if (sys->upscaleMode == upscale_VideoProcessor || sys->upscaleMode == upscale_SuperResolution)
        switch (query) {
        case VOUT_DISPLAY_CHANGE_DISPLAY_FILLED:
        case VOUT_DISPLAY_CHANGE_ZOOM:
        case VOUT_DISPLAY_CHANGE_SOURCE_ASPECT:
        case VOUT_DISPLAY_CHANGE_SOURCE_CROP:
            {
                // update the source cropping
                UINT window_width, window_height;
                if (!sys->sys.pf_GetWindowSize(&sys->sys, &window_width, &window_height))
                {
                    window_width  = RECTWidth(sys->sys.rect_dest_clipped);
                    window_height = RECTHeight(sys->sys.rect_dest_clipped);
                }
                vout_display_cfg_t cfg = *vd->cfg;
                cfg.display.width = window_width;
                cfg.display.height = window_height;
                D3D11_UpscalerUpdate(VLC_OBJECT(vd), sys->scaleProc, &sys->d3d_dev, &vd->source,
                                     &sys->quad_fmt, &cfg);

                if (sys->tonemapProc)
                    D3D11_TonemapperUpdate(VLC_OBJECT(vd), sys->tonemapProc, &sys->d3d_dev,
                                           &sys->quad_fmt);
            }
            break;
        }

    int res = CommonControl( vd, query, args );

#if !VLC_WINSTORE_APP
    if (res == VLC_SUCCESS && stereo_fullscreen_change &&
        stereo_wants_fullscreen)
        res = SUCCEEDED(EnterStereoFullscreen(
                            vd, "after VLC fullscreen request", NULL))
                  ? VLC_SUCCESS : VLC_EGENERIC;
#endif

    if (query == VOUT_DISPLAY_CHANGE_VIEWPOINT)
    {
        const vout_display_cfg_t *cfg = va_arg(args, const vout_display_cfg_t*);
        if ( sys->picQuad.pVertexShaderConstants )
        {
            SetQuadVSProjection( vd, &sys->picQuad, &cfg->viewpoint );
            res = VLC_SUCCESS;
        }
    }

    if (!RectEquals(&before_src_clipped,  &sys->sys.rect_src_clipped) ||
        !RectEquals(&before_dest_clipped, &sys->sys.rect_dest_clipped) ||
        !RectEquals(&before_dest,         &sys->sys.rect_dest) )
    {
        UpdateSize(vd);
    }

    return res;
}

static void Manage(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    RECT before_src_clipped  = sys->sys.rect_src_clipped;
    RECT before_dest_clipped = sys->sys.rect_dest_clipped;
    RECT before_dest         = sys->sys.rect_dest;

    CommonManage(vd);

#if !VLC_WINSTORE_APP
    if (sys->stereo_requested && !sys->stereo_windowed)
    {
        vout_thread_t *vout = (vout_thread_t *)vd->obj.parent;
        bool wants_fullscreen = vout != NULL &&
                                var_GetBool(vout, "fullscreen");
        if (!wants_fullscreen && sys->stereo_active)
        {
            HRESULT hr = SwitchStereoStreamToWindowedMono(vd);
            if (FAILED(hr))
                msg_Err(vd, "could not switch MVC playback to a window "
                        "(hr=0x%lX)", hr);
            sys->stereo_fullscreen_forced = false;
        }
        else if (wants_fullscreen && !sys->stereo_active)
        {
            HRESULT hr = SwitchStereoStreamToExclusive(vd);
            if (FAILED(hr))
                msg_Err(vd, "could not restore HDMI frame packing "
                        "(hr=0x%lX)", hr);
        }
        else if (wants_fullscreen && sys->stereo_active)
        {
            BOOL fullscreen = FALSE;
            if (FAILED(IDXGISwapChain_GetFullscreenState(
                           sys->dxgiswapChain, &fullscreen, NULL)) ||
                !fullscreen)
                EnterStereoFullscreen(vd, "recovery after window event",
                                      NULL);
        }
    }
#endif

    if (!RectEquals(&before_src_clipped, &sys->sys.rect_src_clipped) ||
        !RectEquals(&before_dest_clipped, &sys->sys.rect_dest_clipped) ||
        !RectEquals(&before_dest, &sys->sys.rect_dest))
    {
        UpdateSize(vd);
    }
}

static void CallUpdateRects(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys->scaleProc && D3D11_UpscalerUsed(sys->scaleProc))
    {
        D3D11_UpscalerGetSize(sys->scaleProc, &sys->quad_fmt.i_width, &sys->quad_fmt.i_height);

        sys->quad_fmt.i_x_offset       = 0;
        sys->quad_fmt.i_y_offset       = 0;
        sys->quad_fmt.i_visible_width  = sys->quad_fmt.i_width;
        sys->quad_fmt.i_visible_height = sys->quad_fmt.i_height;

        sys->picQuad.i_width = sys->quad_fmt.i_width;
        sys->picQuad.i_height = sys->quad_fmt.i_height;

        UpdateRects(vd, NULL, true);
        UpdateSize(vd);
    }
    else
    {
        UpdateRects(vd, NULL, true);
    }
}

static int CreateStaging(vout_display_t *vd, ID3D11DeviceContext *shared_context)
{
    vout_display_sys_t *sys = vd->sys;
    ID3D11Texture2D *textures[D3D11_MAX_SHADER_VIEW] = {0};
    video_format_t surface_fmt = sys->pool_fmt;
    surface_fmt.i_width  = sys->picQuad.i_width;
    surface_fmt.i_height = sys->picQuad.i_height;

    if (AllocateTextures(vd, &sys->d3d_dev, sys->picQuad.formatInfo, &surface_fmt,
                         false, shared_context != NULL, 1, textures))
    {
        msg_Err(vd, "Failed to allocate the staging texture");
        return VLC_EGENERIC;
    }

    sys->picQuad.resourceCount = DxgiResourceCount(sys->picQuad.formatInfo);
    if (D3D11_AllocateShaderView(vd, sys->d3d_dev.d3ddevice, sys->picQuad.formatInfo,
                                 textures, 0, sys->stagingSys.resourceView))
    {
        msg_Err(vd, "Failed to allocate the staging shader view");
        return VLC_EGENERIC;
    }

    for (unsigned plane = 0; plane < D3D11_MAX_SHADER_VIEW; plane++)
        sys->stagingSys.texture[plane] = textures[plane];


    if (shared_context)
    {
        assert(sys->sharedHandle == INVALID_HANDLE_VALUE);
        HRESULT hr;
        IDXGIResource1* sharedResource = NULL;
        ID3D11Resource_QueryInterface(sys->stagingSys.resource[0], &IID_IDXGIResource1, (void**)&sharedResource);
        hr = IDXGIResource1_CreateSharedHandle(sharedResource, NULL, DXGI_SHARED_RESOURCE_READ|DXGI_SHARED_RESOURCE_WRITE, NULL, &sys->sharedHandle);
        IDXGIResource1_Release(sharedResource);
        if (FAILED(hr))
        {
            msg_Err(vd, "Failed to get the shared handle");
            return VLC_EGENERIC;
        }
    }

    return VLC_SUCCESS;
}

static double DoviPqCodeToNits(uint16_t code)
{
    const double m1 = 2610.0 / (4096.0 * 4.0);
    const double m2 = (2523.0 / 4096.0) * 128.0;
    const double c1 = 3424.0 / 4096.0;
    const double c2 = (2413.0 / 4096.0) * 32.0;
    const double c3 = (2392.0 / 4096.0) * 32.0;
    const double pq = fmin(code, 4095.0) / 4095.0;
    const double e = pow(pq, 1.0 / m2);
    return 10000.0 * pow(fmax(e - c1, 0.0) / (c2 - c3 * e),
                           1.0 / m1);
}

static float DoviSourcePeakNits(const vlc_video_dovi_metadata_t *dovi)
{
    const uint16_t peak_pq = dovi->has_level1 && dovi->level1_max_pq
                           ? dovi->level1_max_pq : dovi->source_max_pq;
    return fmax(DoviPqCodeToNits(peak_pq), (double)DEFAULT_BRIGHTNESS);
}

static void DoviFillHdr10Metadata(DXGI_HDR_METADATA_HDR10 *hdr10,
                                  const vlc_video_dovi_metadata_t *dovi,
                                  float source_peak)
{
    memset(hdr10, 0, sizeof(*hdr10));
    /* Rec. ITU-R BT.2020 and D65, in CTA/DXGI units of 0.00002. */
    hdr10->RedPrimary[0] = 35400; hdr10->RedPrimary[1] = 14600;
    hdr10->GreenPrimary[0] = 8500; hdr10->GreenPrimary[1] = 39850;
    hdr10->BluePrimary[0] = 6550; hdr10->BluePrimary[1] = 2300;
    hdr10->WhitePoint[0] = 15635; hdr10->WhitePoint[1] = 16450;
    const double mastering_peak = fmax(
        DoviPqCodeToNits(dovi->source_max_pq), DEFAULT_BRIGHTNESS);
    const double mastering_luminance =
        fmin(mastering_peak, (double)UINT32_MAX);
    const double minimum_luminance =
        fmin(10000.0 * DoviPqCodeToNits(dovi->source_min_pq),
             (double)UINT32_MAX);
    const double content_light_level =
        fmin(source_peak, (double)UINT16_MAX);
    hdr10->MaxMasteringLuminance = (UINT32)mastering_luminance;
    hdr10->MinMasteringLuminance = (UINT32)minimum_luminance;
    hdr10->MaxContentLightLevel = (UINT16)content_light_level;
    if (dovi->has_level1 && dovi->level1_avg_pq)
    {
        const double average_light_level = fmin(
            DoviPqCodeToNits(dovi->level1_avg_pq), (double)UINT16_MAX);
        hdr10->MaxFrameAverageLightLevel = (UINT16)average_light_level;
    }
}

static void Prepare(vout_display_t *vd, picture_t *picture, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;

    /* Mouse events stop when the pointer is stationary.  Keep the visible
     * controller's time and progress current once per second without
     * extending its non-hover timeout.  The resulting SPU is consumed by a
     * following video frame and therefore never adds an extra Present(). */
    vlc_tick_t controls_now = mdate();
    if (sys->stereo_active &&
        controls_now < sys->stereo_controls_until &&
        controls_now - sys->stereo_controls_last_draw >= CLOCK_FREQ)
    {
        vlc_value_t old_value = { 0 };
        vlc_value_t mouse;
        mouse.coords.x = InterlockedCompareExchange(&sys->stereo_cursor_x,
                                                     0, 0);
        mouse.coords.y = InterlockedCompareExchange(&sys->stereo_cursor_y,
                                                     0, 0);
        StereoMouseMoved((vlc_object_t *)vd->obj.parent,
                         "stereo-periodic-refresh", old_value, mouse, vd);
    }

    if (sys->picQuad.formatInfo->formatTexture == DXGI_FORMAT_UNKNOWN)
    {
        D3D11_MAPPED_SUBRESOURCE mappedResource;
        D3D11_TEXTURE2D_DESC texDesc;
        int i;
        HRESULT hr;
        plane_t planes[PICTURE_PLANE_MAX];

        bool b_mapped = true;
        for (i = 0; i < picture->i_planes; i++) {
            hr = ID3D11DeviceContext_Map(sys->d3d_dev.d3dcontext, sys->stagingSys.resource[i],
                                         0, D3D11_MAP_WRITE_DISCARD, 0, &mappedResource);
            if( unlikely(FAILED(hr)) )
            {
                while (i-- > 0)
                    ID3D11DeviceContext_Unmap(sys->d3d_dev.d3dcontext, sys->stagingSys.resource[i], 0);
                b_mapped = false;
                break;
            }
            ID3D11Texture2D_GetDesc(sys->stagingSys.texture[i], &texDesc);
            planes[i].i_lines = texDesc.Height;
            planes[i].i_pitch = mappedResource.RowPitch;
            planes[i].p_pixels = mappedResource.pData;

            planes[i].i_visible_lines = picture->p[i].i_visible_lines;
            planes[i].i_visible_pitch = picture->p[i].i_visible_pitch;
        }

        if (b_mapped)
        {
            for (i = 0; i < picture->i_planes; i++)
                plane_CopyPixels(&planes[i], &picture->p[i]);

            for (i = 0; i < picture->i_planes; i++)
                ID3D11DeviceContext_Unmap(sys->d3d_dev.d3dcontext, sys->stagingSys.resource[i], 0);
        }
    }
    else
    {
        picture_sys_t *p_sys = ActivePictureSys(picture);

        if (is_d3d11_opaque(picture->format.i_chroma))
            d3d11_device_lock( &sys->d3d_dev );

        if (sys->scaleProc && D3D11_UpscalerUsed(sys->scaleProc))
        {
            if (D3D11_UpscalerScale(VLC_OBJECT(vd), sys->scaleProc, p_sys) != VLC_SUCCESS)
                return;
            p_sys = D3D11_UpscalerGetOutput(sys->scaleProc);
        }
        if (sys->tonemapProc)
        {
            if (FAILED(D3D11_TonemapperProcess(VLC_OBJECT(vd), sys->tonemapProc, p_sys)))
                return;
            p_sys = D3D11_TonemapperGetOutput(sys->tonemapProc);
        }

        D3D11_TEXTURE2D_DESC srcDesc;
        ID3D11Texture2D_GetDesc(p_sys->texture[KNOWN_DXGI_INDEX], &srcDesc);

        ID3D11DeviceContext* copyContext = sys->d3d_dev.d3dcontext;
        ID3D11Resource* copyResource = sys->stagingSys.resource[KNOWN_DXGI_INDEX];
        ID3D11Resource* newResource = NULL;

        if (is_d3d11_opaque(picture->format.i_chroma) && sys->d3d_dev.d3dcontext != p_sys->context)
        {
            if (sys->stagingSys.texture[0] == NULL)
            {
                sys->legacy_shader = true; // force using staging
                int ret = CreateStaging(vd, p_sys->context);
                if (unlikely(ret != VLC_SUCCESS))
                {
                    if (is_d3d11_opaque(picture->format.i_chroma))
                        d3d11_device_unlock( &sys->d3d_dev );
                    return;
                }
            }

            HRESULT hr;

            ID3D11Device *psysDev;
            ID3D11Device1 *d3d11VLC1;
            ID3D11DeviceContext_GetDevice(p_sys->context, &psysDev);
            hr = ID3D11Device_QueryInterface(psysDev, &IID_ID3D11Device1, (void**)&d3d11VLC1);
            if (SUCCEEDED(hr))
            {
                hr = ID3D11Device1_OpenSharedResource1(d3d11VLC1, sys->sharedHandle, &IID_ID3D11Resource, (void**)&newResource);
                ID3D11Device1_Release(d3d11VLC1);
            }
            ID3D11Device_Release(psysDev);
            if (FAILED(hr))
            {
                if (is_d3d11_opaque(picture->format.i_chroma))
                    d3d11_device_unlock( &sys->d3d_dev );
                return;
            }

            copyResource = newResource;
            copyContext = p_sys->context;
        }

        if (!is_d3d11_opaque(picture->format.i_chroma) || sys->legacy_shader) {
            D3D11_TEXTURE2D_DESC texDesc;
            if (!is_d3d11_opaque(picture->format.i_chroma))
                Direct3D11UnmapPoolTexture(picture);
            ID3D11Texture2D_GetDesc(sys->stagingSys.texture[0], &texDesc);
            D3D11_BOX box = {
                .top = 0,
                .bottom = __MIN(srcDesc.Height, texDesc.Height),
                .left = 0,
                .right = __MIN(srcDesc.Width, texDesc.Width),
                .back = 1,
            };
            ID3D11DeviceContext_CopySubresourceRegion(copyContext,
                                                      copyResource,
                                                      0, 0, 0, 0,
                                                      p_sys->resource[KNOWN_DXGI_INDEX],
                                                      p_sys->slice_index, &box);
        }
        else
        {
            if (srcDesc.BindFlags & D3D11_BIND_SHADER_RESOURCE)
            {
                /* for performance reason we don't want to allocate this during
                 * display, do it preferrably when creating the texture */
                assert(p_sys->resourceView[0]!=NULL);
            }
            if ( sys->picQuad.i_height != srcDesc.Height ||
                 sys->picQuad.i_width != srcDesc.Width )
            {
                /* the decoder produced different sizes than the vout, we need to
                 * adjust the vertex */
                sys->quad_fmt.i_width = srcDesc.Width;
                sys->quad_fmt.i_height = srcDesc.Height;
                sys->picQuad.i_width = sys->quad_fmt.i_width;
                sys->picQuad.i_height = sys->quad_fmt.i_height;

                CallUpdateRects(vd);
                UpdateSize(vd);
            }
        }

        if (newResource != NULL)
            // shared resource
            ID3D11Resource_Release(newResource);
    }

    if (subpicture &&
        (!sys->d3dregion_order_valid ||
         sys->d3dregion_order != subpicture->i_order ||
         sys->d3dregion_original_width !=
             subpicture->i_original_picture_width ||
         sys->d3dregion_original_height !=
             subpicture->i_original_picture_height)) {
        int subpicture_region_count    = 0;
        picture_t **subpicture_regions = NULL;
        Direct3D11MapSubpicture(vd, &subpicture_region_count, &subpicture_regions, subpicture);
        Direct3D11DeleteRegions(sys->d3dregion_count, sys->d3dregions);
        sys->d3dregion_count = subpicture_region_count;
        sys->d3dregions      = subpicture_regions;
        sys->d3dregion_order = subpicture->i_order;
        sys->d3dregion_original_width =
            subpicture->i_original_picture_width;
        sys->d3dregion_original_height =
            subpicture->i_original_picture_height;
        sys->d3dregion_order_valid = true;

        /* The software pointer must be the last blended quad so subtitle
         * glyphs and the controller cannot cover it. */
        for (int i = 0; i + 1 < sys->d3dregion_count; ++i)
        {
            d3d_quad_t *quad = sys->d3dregions[i] != NULL
                             ? (d3d_quad_t *)sys->d3dregions[i]->p_sys
                             : NULL;
            if (quad != NULL && quad->stereoOffset == INT16_MAX)
            {
                picture_t *cursor = sys->d3dregions[i];
                memmove(&sys->d3dregions[i], &sys->d3dregions[i + 1],
                        (sys->d3dregion_count - i - 1) *
                        sizeof(*sys->d3dregions));
                sys->d3dregions[sys->d3dregion_count - 1] = cursor;
                break;
            }
        }
    }

    if (sys->quad_fmt.dovi.rpu_present)
    {
#if !VLC_WINSTORE_APP
        /* Some demuxer/decoder combinations expose the RPU flag only after
         * the vout has opened. Switch the HDMI transport at the first Dolby
         * Vision frame in that case, before rendering it. */
        if (!sys->dovi_display_attempted &&
            var_InheritBool(vd, "d3d11-dovi-hdmi"))
        {
            sys->dovi_display_attempted = true;
            sys->dovi_display = Win32DoviDisplay_Enable(
                VLC_OBJECT(vd), sys->sys.hvideownd);
        }
#endif
        if (!D3D11_UpdateQuadDolbyVision(vd, &sys->d3d_dev, &sys->picQuad,
                                         picture->p_dovi) &&
            !sys->dovi_missing_reported)
        {
            msg_Err(vd, "could not update Dolby Vision D3D11 metadata");
            sys->dovi_missing_reported = true;
        }
        if (picture->p_dovi != NULL && !sys->dovi_metadata_reported)
        {
            msg_Info(vd, "Dolby Vision dynamic metadata active in D3D11 "
                         "(%u-bit BL, residual %s)",
                     picture->p_dovi->bl_bit_depth,
                     picture->p_dovi->residual_disabled ? "disabled" : "available");
            sys->dovi_metadata_reported = true;
        }
        if (picture->p_enhancement_layer != NULL && !sys->dovi_fel_reported)
        {
            msg_Warn(vd, "Dolby Vision Profile 7 enhancement residual is not "
                         "composed by D3D11; rendering the compatible base layer");
            sys->dovi_fel_reported = true;
        }
    }

    if (picture->p_dovi != NULL)
    {
        /* RPU reshaping yields BT.2020/PQ even when the compatible base layer
         * is HLG. Preserve its scene peak for diagnostics and provide an
         * HDR10-only sink with metadata derived from the RPU. */
        const float source_peak = DoviSourcePeakNits(picture->p_dovi);
        /* VLC's Hable shader operates on absolute PQ luminance and expects
         * the nominal 10,000-nit PQ range here. Scaling by the scene peak
         * instead would amplify a 699-nit title about fourteen times and
         * clip most of an SDR frame to white. */
        D3D11_UpdateQuadLuminanceScale(vd, &sys->d3d_dev, &sys->picQuad,
            (float)sys->display.luminance_peak / MAX_PQ_BRIGHTNESS);

        bool native_dovi_transport = false;
#if !VLC_WINSTORE_APP
        native_dovi_transport = sys->dovi_display != NULL;
#endif
        if (sys->dxgiswapChain4 && !native_dovi_transport &&
            sys->display.colorspace->transfer == TRANSFER_FUNC_SMPTE_ST2084)
        {
            DXGI_HDR_METADATA_HDR10 hdr10;
            DoviFillHdr10Metadata(&hdr10, picture->p_dovi, source_peak);
            if (memcmp(&sys->hdr10, &hdr10, sizeof(hdr10)))
            {
                memcpy(&sys->hdr10, &hdr10, sizeof(hdr10));
                IDXGISwapChain4_SetHDRMetaData(sys->dxgiswapChain4,
                    DXGI_HDR_METADATA_TYPE_HDR10, sizeof(hdr10), &hdr10);
            }
            if (!sys->dovi_hdr10_reported)
            {
                msg_Info(vd, "Dolby Vision HDR10 fallback active "
                             "(BT.2020/PQ, RPU scene peak %.0f nits)",
                         source_peak);
                sys->dovi_hdr10_reported = true;
            }
        }
        else if (sys->display.colorspace->transfer == TRANSFER_FUNC_SRGB &&
                 !sys->dovi_sdr_reported)
        {
            msg_Info(vd, "Dolby Vision SDR tone mapping active "
                         "(BT.2020/PQ to Rec.709, RPU scene peak %.0f nits)",
                     source_peak);
            sys->dovi_sdr_reported = true;
        }
    }
    else if (picture->format.mastering.max_luminance)
    {
        D3D11_UpdateQuadLuminanceScale(vd, &sys->d3d_dev, &sys->picQuad, (float)sys->display.luminance_peak / GetFormatLuminance(VLC_OBJECT(vd), &picture->format));

        if (sys->dxgiswapChain4)
        {
            DXGI_HDR_METADATA_HDR10 hdr10 = {0};
            hdr10.GreenPrimary[0] = picture->format.mastering.primaries[0];
            hdr10.GreenPrimary[1] = picture->format.mastering.primaries[1];
            hdr10.BluePrimary[0]  = picture->format.mastering.primaries[2];
            hdr10.BluePrimary[1]  = picture->format.mastering.primaries[3];
            hdr10.RedPrimary[0]   = picture->format.mastering.primaries[4];
            hdr10.RedPrimary[1]   = picture->format.mastering.primaries[5];
            hdr10.WhitePoint[0] = picture->format.mastering.white_point[0];
            hdr10.WhitePoint[1] = picture->format.mastering.white_point[1];
            hdr10.MaxMasteringLuminance = picture->format.mastering.max_luminance / 10000;
            hdr10.MinMasteringLuminance = picture->format.mastering.min_luminance;
            hdr10.MaxContentLightLevel = picture->format.lighting.MaxCLL;
            hdr10.MaxFrameAverageLightLevel = picture->format.lighting.MaxFALL;
            if (memcmp(&sys->hdr10, &hdr10, sizeof(hdr10)))
            {
                memcpy(&sys->hdr10, &hdr10, sizeof(hdr10));
                IDXGISwapChain4_SetHDRMetaData(sys->dxgiswapChain4, DXGI_HDR_METADATA_TYPE_HDR10, sizeof(hdr10), &hdr10);
            }
        }
    }

    ID3D11ShaderResourceView *SRV[D3D11_MAX_SHADER_VIEW];
    /* Render the quad using the last stage of processing */
    if (!is_d3d11_opaque(picture->format.i_chroma) || sys->legacy_shader)
    {
        memcpy(SRV, sys->stagingSys.resourceView, sizeof(SRV));
    }
    else if (sys->tonemapProc)
    {
        picture_sys_t *p_sys = D3D11_TonemapperGetOutput(sys->tonemapProc);
        memcpy(SRV, p_sys->resourceView, sizeof(SRV));
    }
    else if (sys->scaleProc && D3D11_UpscalerUsed(sys->scaleProc))
    {
        D3D11_UpscalerGetSRV(sys->scaleProc, SRV);
    }
    else
    {
        picture_sys_t *p_sys;
        p_sys = ActivePictureSys(picture);
        memcpy(SRV, p_sys->resourceView, sizeof(SRV));
    }

    /* Convert the decoder's native YUV/RGB texture through VLC's regular
     * colour-managed picture shader first. The RetroArch graph therefore
     * always receives a conventional RGB source and remains independent of
     * NV12/P010/opaque decoder layouts. Subtitles are drawn afterwards and
     * deliberately stay sharp. */
    bool use_crt = false;
    ID3D11RenderTargetView *crt_input = NULL;
    unsigned crt_width = 0, crt_height = 0;
    unsigned crt_view_width = RECTWidth(sys->sys.rect_dest_clipped);
    unsigned crt_view_height = RECTHeight(sys->sys.rect_dest_clipped);
    if (sys->crtShaders && !sys->stereo_requested &&
        vd->fmt.projection_mode == PROJECTION_MODE_RECTANGULAR &&
        D3D11_RA_Begin(sys->crtShaders,
                       sys->quad_fmt.i_visible_width,
                       sys->quad_fmt.i_visible_height,
                       crt_view_width, crt_view_height, picture->date,
                       &crt_input, &crt_width, &crt_height))
    {
        D3D11_VIEWPORT saved = sys->picQuad.cropViewport;
        sys->picQuad.cropViewport.TopLeftX = 0;
        sys->picQuad.cropViewport.TopLeftY = 0;
        sys->picQuad.cropViewport.Width = crt_width;
        sys->picQuad.cropViewport.Height = crt_height;
        D3D11_RenderQuad(&sys->d3d_dev, &sys->picQuad, SRV, crt_input);
        sys->picQuad.cropViewport = saved;
        use_crt = true;
    }

    /* A DXGI stereo swapchain exposes the back buffer as a two-slice texture
     * array. Render each packed source eye into its corresponding slice. The
     * SPU pass is deliberately repeated for both eyes so menus, subtitles and
     * fullscreen controls remain readable in hardware 3D mode. */
    FLOAT blackRGBA[4] = {0.0f, 0.0f, 0.0f, 1.0f};
    unsigned view_count = sys->stereo_active ? 2 : 1;
    for (unsigned eye = 0; eye < view_count; ++eye)
    {
        ID3D11RenderTargetView *target = eye == 0
                                       ? sys->d3drenderTargetView
                                       : sys->d3drenderTargetViewRight;
        if (target == NULL)
            continue;

        if (sys->stereo_requested)
        {
            float left, top, right, bottom;
            unsigned source_eye = sys->stereo_active ? eye : 0;
            StereoEyeTextureRect(vd->fmt.multiview_mode, &sys->quad_fmt,
                                 source_eye,
                                 &left, &top, &right, &bottom);
            if (!sys->stereo_geometry_reported)
            {
                msg_Info(vd, "stereo render geometry: source mode %d, "
                         "quad coded %ux%u visible %ux%u offset %u,%u, "
                         "eye target %ux%u, eye %u texture %.6f,%.6f-%.6f,%.6f",
                         vd->fmt.multiview_mode,
                         sys->quad_fmt.i_width, sys->quad_fmt.i_height,
                         sys->quad_fmt.i_visible_width,
                         sys->quad_fmt.i_visible_height,
                         sys->quad_fmt.i_x_offset, sys->quad_fmt.i_y_offset,
                         sys->stereo_eye_width, sys->stereo_eye_height,
                         source_eye, left, top, right, bottom);
                if (eye + 1 == view_count)
                    sys->stereo_geometry_reported = true;
            }
            D3D11_UpdateQuadTextureCoords(vd, &sys->d3d_dev, &sys->picQuad,
                                          left, top, right, bottom);
        }

        ID3D11DeviceContext_ClearRenderTargetView(sys->d3d_dev.d3dcontext,
                                                  target, blackRGBA);
        ID3D11DeviceContext_ClearDepthStencilView(
            sys->d3d_dev.d3dcontext, sys->d3ddepthStencilView,
            D3D11_CLEAR_DEPTH | D3D11_CLEAR_STENCIL, 1.0f, 0);
        bool crt_rendered = false;
        if (use_crt)
        {
            D3D11_VIEWPORT viewport = sys->picQuad.cropViewport;
            crt_rendered = D3D11_RA_Render(sys->crtShaders, target, &viewport);
            if (!crt_rendered)
                msg_Warn(vd, "Direct3D11 RetroArch rendering failed; using the normal picture shader");
        }
        if (!crt_rendered)
            D3D11_RenderQuad(&sys->d3d_dev, &sys->picQuad, SRV, target);

        if (subpicture)
        {
            if (sys->stereo_active &&
                sys->stereo_spu_report_count < 48 &&
                sys->stereo_spu_reported_order != sys->d3dregion_order)
            {
                msg_Info(vd, "stereo SPU order %"PRId64": %d regions, "
                         "original %dx%d",
                         sys->d3dregion_order, sys->d3dregion_count,
                         sys->d3dregion_original_width,
                         sys->d3dregion_original_height);
                for (int region = 0; region < sys->d3dregion_count; ++region)
                {
                    if (sys->d3dregions[region] == NULL)
                        continue;
                    d3d_quad_t *reported =
                        (d3d_quad_t *)sys->d3dregions[region]->p_sys;
                    msg_Info(vd, "stereo SPU region %d: viewport "
                             "%.2f,%.2f %.2fx%.2f offset %d, texture %ux%u",
                             region,
                             reported->cropViewport.TopLeftX,
                             reported->cropViewport.TopLeftY,
                             reported->cropViewport.Width,
                             reported->cropViewport.Height,
                             reported->stereoOffset,
                             sys->d3dregions[region]->format.i_visible_width,
                             sys->d3dregions[region]->format.i_visible_height);
                }
                sys->stereo_spu_reported_order = sys->d3dregion_order;
                sys->stereo_spu_report_count++;
            }
            int overlay_depth = var_InheritInteger(
                vd, "stereo3d-overlay-depth");
            if (overlay_depth < -100)
                overlay_depth = -100;
            else if (overlay_depth > 100)
                overlay_depth = 100;
            for (int i = 0; i < sys->d3dregion_count; ++i)
            {
                if (sys->d3dregions[i])
                {
                    d3d_quad_t *quad =
                        (d3d_quad_t *)sys->d3dregions[i]->p_sys;
                    D3D11_VIEWPORT base_viewport = quad->cropViewport;
                    bool software_cursor =
                        quad->stereoOffset == INT16_MAX;
                    if (sys->stereo_active && software_cursor)
                    {
                        unsigned logical_width = vd->fmt.i_visible_width;
                        if (vd->fmt.i_sar_num > 0 &&
                            vd->fmt.i_sar_den > 0)
                            logical_width = (uint64_t)logical_width *
                                            vd->fmt.i_sar_num /
                                            vd->fmt.i_sar_den;
                        LONG cursor_x = InterlockedCompareExchange(
                            &sys->stereo_cursor_x, 0, 0);
                        LONG cursor_y = InterlockedCompareExchange(
                            &sys->stereo_cursor_y, 0, 0);
                        quad->cropViewport.TopLeftX =
                            (float)cursor_x * sys->stereo_eye_width /
                            logical_width;
                        quad->cropViewport.TopLeftY =
                            (float)cursor_y * sys->stereo_eye_height /
                            vd->fmt.i_visible_height;
                        quad->cropViewport.Width = 24.f;
                        quad->cropViewport.Height = 34.f;
                    }
                    else if (sys->stereo_active)
                    {
                        float shift = (float)overlay_depth / 100.f *
                                      .02f * sys->stereo_eye_width;
                        shift += (float)quad->stereoOffset * .5f;
                        if (eye != 0)
                            shift = -shift;

                        bool full_eye =
                            base_viewport.Width >=
                            (float)sys->stereo_eye_width - 1.f;
                        if (full_eye && shift > 0.f)
                            quad->cropViewport.Width += 2.f * shift;
                        else if (full_eye && shift < 0.f)
                        {
                            quad->cropViewport.TopLeftX += 2.f * shift;
                            quad->cropViewport.Width -= 2.f * shift;
                        }
                        else
                            quad->cropViewport.TopLeftX += shift;
                    }
                    D3D11_RenderQuad(&sys->d3d_dev, quad,
                                     quad->picSys.resourceView, target);
                    quad->cropViewport = base_viewport;
                }
            }
        }
    }

#ifdef HAVE_D3D11_4_H
    if (sys->d3dcontext4)
    {
        vlc_tick_t render_start;
        if (sys->log_level >= 4)
            render_start = mdate();
        if (sys->renderFence == UINT64_MAX)
            sys->renderFence = 0;
        else
            sys->renderFence++;

        ResetEvent(sys->renderFinished);
        ID3D11Fence_SetEventOnCompletion(sys->d3dRenderFence, sys->renderFence, sys->renderFinished);
        ID3D11DeviceContext4_Signal(sys->d3dcontext4, sys->d3dRenderFence, sys->renderFence);

        WaitForSingleObject(sys->renderFinished, INFINITE);
        if (sys->log_level >= 4)
            msg_Dbg(vd, "waited %" PRId64 " ms for the render fence",
                    (mdate() - render_start) * 1000 / CLOCK_FREQ);
    }
#endif

    if (is_d3d11_opaque(picture->format.i_chroma))
        d3d11_device_unlock( &sys->d3d_dev );

}

static void Display(vout_display_t *vd, picture_t *picture, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;

    DXGI_PRESENT_PARAMETERS presentParams;
    memset(&presentParams, 0, sizeof(presentParams));
    d3d11_device_lock( &sys->d3d_dev );
    /* The Intel HDMI 3D path needs an atomic VBlank present; interval zero
     * tears even when preceded by IDXGIOutput::WaitForVBlank(). */
    UINT sync_interval = sys->stereo_active ? 1 : 0;
    HRESULT hr = IDXGISwapChain1_Present1(sys->dxgiswapChain, sync_interval,
                                          0, &presentParams);
    if (hr == DXGI_ERROR_DEVICE_REMOVED || hr == DXGI_ERROR_DEVICE_RESET)
    {
        /* TODO device lost */
        msg_Err(vd, "SwapChain Present failed. (hr=0x%lX)", hr);
    }

    d3d11_device_unlock( &sys->d3d_dev );

    picture_Release(picture);
    if (subpicture)
        subpicture_Delete(subpicture);

    CommonDisplay(vd);
}

static void Direct3D11Destroy(vout_display_t *vd)
{
#if !VLC_WINSTORE_APP
    vout_display_sys_t *sys = vd->sys;
    sys->hdxgi_dll = NULL;
    D3D11_Destroy( &vd->sys->hd3d );
#endif
}

#define COLOR_RANGE_FULL   1 /* 0-255 */
#define COLOR_RANGE_STUDIO 0 /* 16-235 */

#define TRANSFER_FUNC_10    TRANSFER_FUNC_LINEAR
#define TRANSFER_FUNC_22    TRANSFER_FUNC_SRGB
#define TRANSFER_FUNC_2084  TRANSFER_FUNC_SMPTE_ST2084

#define COLOR_PRIMARIES_BT601  COLOR_PRIMARIES_BT601_525

static const dxgi_color_space color_spaces[] = {
#define DXGIMAP(AXIS, RANGE, GAMMA, SITTING, PRIMARIES) \
    { DXGI_COLOR_SPACE_##AXIS##_##RANGE##_G##GAMMA##_##SITTING##_P##PRIMARIES, \
      #AXIS " Rec." #PRIMARIES " gamma:" #GAMMA " range:" #RANGE, \
      COLOR_AXIS_##AXIS, COLOR_PRIMARIES_BT##PRIMARIES, TRANSFER_FUNC_##GAMMA, \
      COLOR_SPACE_BT##PRIMARIES, COLOR_RANGE_##RANGE},

    DXGIMAP(RGB,   FULL,     22,    NONE,   709)
    DXGIMAP(YCBCR, STUDIO,   22,    LEFT,   601)
    DXGIMAP(YCBCR, FULL,     22,    LEFT,   601)
    DXGIMAP(RGB,   FULL,     10,    NONE,   709)
    DXGIMAP(RGB,   STUDIO,   22,    NONE,   709)
    DXGIMAP(YCBCR, STUDIO,   22,    LEFT,   709)
    DXGIMAP(YCBCR, FULL,     22,    LEFT,   709)
    DXGIMAP(RGB,   STUDIO,   22,    NONE,  2020)
    DXGIMAP(YCBCR, STUDIO,   22,    LEFT,  2020)
    DXGIMAP(YCBCR, FULL,     22,    LEFT,  2020)
    DXGIMAP(YCBCR, STUDIO,   22, TOPLEFT,  2020)
    DXGIMAP(RGB,   FULL,     22,    NONE,  2020)
    DXGIMAP(RGB,   FULL,   2084,    NONE,  2020)
    DXGIMAP(YCBCR, STUDIO, 2084,    LEFT,  2020)
    DXGIMAP(RGB,   STUDIO, 2084,    NONE,  2020)
    DXGIMAP(YCBCR, STUDIO, 2084, TOPLEFT,  2020)
    /*DXGIMAP(YCBCR, FULL,     22,    NONE,  2020, 601)*/
    {DXGI_COLOR_SPACE_RESERVED, NULL, 0, 0, 0, 0, 0},
#undef DXGIMAP
};

#ifdef HAVE_DXGI1_6_H
static bool canHandleConversion(const dxgi_color_space *src, const dxgi_color_space *dst)
{
    if (src == dst)
        return true;
    if (src->primaries == COLOR_PRIMARIES_BT2020)
        return true; /* we can convert BT2020 to 2020 or 709 */
    if (dst->transfer == TRANSFER_FUNC_BT709)
        return true; /* we can handle anything to 709 */
    return false; /* let Windows do the rest */
}
#endif

static IDXGIOutput *GetDXGIOutput(IDXGISwapChain1 *dxgiswapChain, d3d11_device_t *d3d_dev)
{
    IDXGIOutput *dxgiOutput = NULL;
    if (FAILED(IDXGISwapChain_GetContainingOutput( dxgiswapChain, &dxgiOutput )))
    {
        // GetContainingOutput fails in UWP
        IDXGIAdapter *dxgiadapter = D3D11DeviceAdapter(d3d_dev->d3ddevice);
        if (likely(dxgiadapter!=NULL)) {
            // Get the first usable output (monitor)
            for (UINT adapter=0;;adapter++)
            {
                HRESULT hr = IDXGIAdapter_EnumOutputs(dxgiadapter, adapter, &dxgiOutput);
                if (SUCCEEDED(hr))
                    break;
                if (hr == DXGI_ERROR_NOT_FOUND) // no more adapters
                    break;
            }
            IDXGIAdapter_Release(dxgiadapter);
        }
    }
    return dxgiOutput;
}

static void D3D11SetColorSpace(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    HRESULT hr;
    int best = -1;
    int score, best_score = 0;
    UINT support;
    IDXGIOutput *dxgiOutput = NULL;
    IDXGISwapChain3 *dxgiswapChain3 = NULL;
    sys->display.colorspace = &color_spaces[0];

    hr = IDXGISwapChain_QueryInterface( sys->dxgiswapChain, &IID_IDXGISwapChain3, (void **)&dxgiswapChain3);
    if (FAILED(hr)) {
        msg_Warn(vd, "could not get a IDXGISwapChain3");
        goto done;
    }

    video_format_t match_source = vd->source;
    if (sys->hdrMode == hdr_Never)
    {
        match_source.primaries = COLOR_PRIMARIES_BT709;
        match_source.transfer  = TRANSFER_FUNC_BT709;
        match_source.space     = COLOR_SPACE_BT709;
    }
    else if (sys->hdrMode == hdr_Always || sys->hdrMode == hdr_Fake)
    {
        match_source.primaries = COLOR_PRIMARIES_BT2020;
        match_source.transfer  = TRANSFER_FUNC_SMPTE_ST2084;
        match_source.space     = COLOR_SPACE_BT2020;
        if (sys->hdrMode == hdr_Fake) // the video processor keeps the source range
            match_source.i_chroma  = VLC_CODEC_RGBA10;
    }

    bool src_full_range = match_source.b_color_range_full ||
                          /* the YUV->RGB conversion already output full range */
                          is_d3d11_opaque(match_source.i_chroma) ||
                          vlc_fourcc_IsYUV(match_source.i_chroma);

    /* pick the best output based on color support and transfer */
    /* TODO support YUV output later */
    for (int i=0; color_spaces[i].name; ++i)
    {
        hr = IDXGISwapChain3_CheckColorSpaceSupport(dxgiswapChain3, color_spaces[i].dxgi, &support);
        if (SUCCEEDED(hr) && support) {
            msg_Dbg(vd, "supports colorspace %s", color_spaces[i].name);
            score = 0;
            if (color_spaces[i].primaries == match_source.primaries)
                score++;
            if (color_spaces[i].color == match_source.space)
                score += 2; /* we don't want to translate color spaces */
            if (color_spaces[i].transfer == match_source.transfer ||
                /* favor 2084 output for HLG source */
                (color_spaces[i].transfer == TRANSFER_FUNC_SMPTE_ST2084 && match_source.transfer == TRANSFER_FUNC_HLG))
                score++;
            if (color_spaces[i].b_full_range == src_full_range)
                score++;
            if (score > best_score || (score && best == -1)) {
                best = i;
                best_score = score;
            }
        }
    }

    if (best == -1)
    {
        best = 0;
        msg_Warn(vd, "no matching colorspace found force %s", color_spaces[best].name);
    }

#ifdef HAVE_DXGI1_6_H
    if (sys->hdrMode == hdr_Auto || sys->hdrMode == hdr_Fake) // match the screen
    if ((dxgiOutput = GetDXGIOutput( sys->dxgiswapChain, &sys->d3d_dev )) != NULL)
    {
        IDXGIOutput6 *dxgiOutput6 = NULL;
        if (SUCCEEDED(IDXGIOutput_QueryInterface( dxgiOutput, &IID_IDXGIOutput6, (void **)&dxgiOutput6 )))
        {
            DXGI_OUTPUT_DESC1 desc1;
            if (SUCCEEDED(IDXGIOutput6_GetDesc1( dxgiOutput6, &desc1 )))
            {
                const dxgi_color_space *csp = NULL;
                for (int i=0; color_spaces[i].name; ++i)
                {
                    if (color_spaces[i].dxgi == desc1.ColorSpace)
                    {
                        if (!canHandleConversion(&color_spaces[best], &color_spaces[i]))
                            msg_Warn(vd, "Can't handle conversion to screen format %s", color_spaces[i].name);
                        else
                        {
                            best = i;
                            csp = &color_spaces[i];
                        }
                        break;
                    }
                }

                msg_Dbg(vd, "Output max luminance: %.1f, colorspace %s, bits per pixel %d", desc1.MaxFullFrameLuminance, csp?csp->name:"unknown", desc1.BitsPerColor);
                //sys->display.luminance_peak = desc1.MaxFullFrameLuminance;
            }
            IDXGIOutput6_Release( dxgiOutput6 );
        }
        IDXGIOutput_Release( dxgiOutput );
    }
#endif

    hr = IDXGISwapChain3_SetColorSpace1(dxgiswapChain3, color_spaces[best].dxgi);
    if (SUCCEEDED(hr))
    {
        sys->display.colorspace = &color_spaces[best];
        msg_Dbg(vd, "using colorspace %s", sys->display.colorspace->name);
    }
    else
        msg_Err(vd, "Failed to set colorspace %s. (hr=0x%lX)", sys->display.colorspace->name, hr);
done:
    /* guestimate the display peak luminance */
    switch (sys->display.colorspace->transfer)
    {
    case TRANSFER_FUNC_LINEAR:
    case TRANSFER_FUNC_SRGB:
        sys->display.luminance_peak = DEFAULT_SRGB_BRIGHTNESS;
        break;
    case TRANSFER_FUNC_SMPTE_ST2084:
        sys->display.luminance_peak = MAX_PQ_BRIGHTNESS;
        break;
    /* there is no other output transfer on Windows */
    default:
        vlc_assert_unreachable();
    }

    if (dxgiswapChain3)
        IDXGISwapChain3_Release(dxgiswapChain3);
}

static const d3d_format_t *GetDirectRenderingFormat(vout_display_t *vd, vlc_fourcc_t i_src_chroma)
{
    UINT supportFlags = D3D11_FORMAT_SUPPORT_SHADER_LOAD;
    if (is_d3d11_opaque(i_src_chroma))
        supportFlags |= D3D11_FORMAT_SUPPORT_DECODER_OUTPUT;
    return FindD3D11Format( vd, &vd->sys->d3d_dev, i_src_chroma, false, 0, 0, 0, is_d3d11_opaque(i_src_chroma), supportFlags );
}

static const d3d_format_t *GetDirectDecoderFormat(vout_display_t *vd, vlc_fourcc_t i_src_chroma)
{
    UINT supportFlags = D3D11_FORMAT_SUPPORT_DECODER_OUTPUT;
    return FindD3D11Format( vd, &vd->sys->d3d_dev, i_src_chroma, false, 0, 0, 0, is_d3d11_opaque(i_src_chroma), supportFlags );
}

static const d3d_format_t *GetDisplayFormatByDepth(vout_display_t *vd, uint8_t bit_depth,
                                                   uint8_t widthDenominator,
                                                   uint8_t heightDenominator,
                                                   bool from_processor,
                                                   bool rgb_only)
{
    UINT supportFlags = D3D11_FORMAT_SUPPORT_SHADER_LOAD;
    if (from_processor)
        supportFlags |= D3D11_FORMAT_SUPPORT_VIDEO_PROCESSOR_OUTPUT;
    return FindD3D11Format( vd, &vd->sys->d3d_dev, 0, rgb_only,
                            bit_depth, widthDenominator, heightDenominator,
                            false, supportFlags );
}

static const d3d_format_t *GetBlendableFormat(vout_display_t *vd, vlc_fourcc_t i_src_chroma)
{
    UINT supportFlags = D3D11_FORMAT_SUPPORT_SHADER_LOAD | D3D11_FORMAT_SUPPORT_BLENDABLE;
    return FindD3D11Format( vd, &vd->sys->d3d_dev, i_src_chroma, false, 0, 0, 0, false, supportFlags );
}

static bool CanUseTextureArray(vout_display_t *vd)
{
#ifndef HAVE_ID3D11VIDEODECODER
    (void) vd;
    return false;
#else
    // 15.200.1062.1004 is wrong - 2015/08/03 - 15.7.1 WHQL
    // 21.19.144.1281 is wrong   -
    // 22.19.165.3 is good       - 2017/05/04 - ReLive Edition 17.5.1
    struct wddm_version WDDM_os = {
        .wddm         = 21,  // starting with drivers designed for W10 Anniversary Update
    };
    if (D3D11CheckDriverVersion(&vd->sys->d3d_dev, GPU_MANUFACTURER_AMD, &WDDM_os) != VLC_SUCCESS)
    {
        msg_Dbg(vd, "AMD driver too old, fallback to legacy shader mode");
        return false;
    }

    // xx.xx.1000.xxx drivers can't happen here for WDDM > 2.0
    struct wddm_version WDDM_build = {
        .revision     = 162,
    };
    if (D3D11CheckDriverVersion(&vd->sys->d3d_dev, GPU_MANUFACTURER_AMD, &WDDM_build) != VLC_SUCCESS)
    {
        msg_Dbg(vd, "Bogus AMD driver detected, fallback to legacy shader mode");
        return false;
    }

    return true;
#endif
}

static bool BogusZeroCopy(const vout_display_t *vd)
{
    if (vd->sys->d3d_dev.adapterDesc.VendorId != GPU_MANUFACTURER_AMD)
        return false;

    switch (vd->sys->d3d_dev.adapterDesc.DeviceId)
    {
    case 0x687F: // RX Vega 56/64
    case 0x6863: // RX Vega Frontier Edition
    case 0x15DD: // RX Vega 8/11 (Ryzen iGPU)
    {
        struct wddm_version WDDM = {
            .revision     = 14011, // 18.10.2 - 2018/06/11
        };
        return D3D11CheckDriverVersion(&vd->sys->d3d_dev, GPU_MANUFACTURER_AMD, &WDDM) != VLC_SUCCESS;
    }
    default:
        return false;
    }
}

static enum d3d11_hdr HdrModeFromString(vlc_object_t *logger, const char *psz_hdr)
{
    if (strcmp("auto", psz_hdr) == 0)
        return hdr_Auto;
    if (strcmp("never", psz_hdr) == 0)
        return hdr_Never;
    if (strcmp("always", psz_hdr) == 0)
        return hdr_Always;
    if (strcmp("generate", psz_hdr) == 0)
        return hdr_Fake;

    msg_Warn(logger, "unknown HDR mode %s, using auto mode", psz_hdr);
    return hdr_Auto;
}

static void InitTonemapProcessor(vout_display_t *vd, const video_format_t *fmt_in)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys->hdrMode != hdr_Fake)
        return;

    sys->tonemapProc = D3D11_TonemapperCreate(VLC_OBJECT(vd), &sys->d3d_dev, fmt_in);
    if (sys->tonemapProc == NULL)
    {
        sys->hdrMode = hdr_Auto;
        msg_Dbg(vd, "failed to create the tone mapper, using default HDR mode");
        return;
    }

    msg_Dbg(vd, "Using tonemapper");
}

static void InitScaleProcessor(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    if (sys->upscaleMode != upscale_VideoProcessor && sys->upscaleMode != upscale_SuperResolution)
        return;

    sys->scaleProc = D3D11_UpscalerCreate(VLC_OBJECT(vd), &sys->d3d_dev, sys->quad_fmt.i_chroma,
                                          sys->upscaleMode == upscale_SuperResolution,
                                          &sys->picQuad.formatInfo);
    if (sys->scaleProc == NULL)
        sys->upscaleMode = upscale_LinearSampler;

    msg_Dbg(vd, "Using %s scaler with %s output", ppsz_upscale_mode_text[sys->upscaleMode],
        sys->picQuad.formatInfo->name);
}

static int Direct3D11Open(vout_display_t *vd, bool external_device)
{
    vout_display_sys_t *sys = vd->sys;
    IDXGIFactory2 *dxgifactory;

    char *psz_hdr = var_InheritString(vd, "d3d11-hdr-mode");
    sys->hdrMode = HdrModeFromString(VLC_OBJECT(vd), psz_hdr);
    free(psz_hdr);
    /* HDMI 1.4 frame-packed timings and the Windows stereo swapchain path
     * are SDR. Do not let an automatic HDR choice replace the required
     * BGRA8 stereo back buffer with a 10-bit monoscopic one. */
    if (sys->stereo_requested)
        sys->hdrMode = hdr_Never;

    if (!external_device)
    {
#if !VLC_WINSTORE_APP
        HRESULT hr = S_OK;

        DXGI_SWAP_CHAIN_DESC1 scd;
        DXGI_SWAP_CHAIN_FULLSCREEN_DESC stereo_fs_desc;
        IDXGIOutput *stereo_output = NULL;
        ZeroMemory(&stereo_fs_desc, sizeof(stereo_fs_desc));

        hr = D3D11_CreateDevice(vd, &sys->hd3d,
                                is_d3d11_opaque(vd->source.i_chroma),
                                &sys->d3d_dev);
        if (FAILED(hr)) {
        msg_Err(vd, "Could not Create the D3D11 device. (hr=0x%lX)", hr);
        return VLC_EGENERIC;
        }

        IDXGIAdapter *dxgiadapter = D3D11DeviceAdapter(sys->d3d_dev.d3ddevice);
        if (unlikely(dxgiadapter==NULL)) {
        msg_Err(vd, "Could not get the DXGI Adapter");
        return VLC_EGENERIC;
        }

        for (UINT output_index = 0;; ++output_index)
        {
            IDXGIOutput *probe_output = NULL;
            if (IDXGIAdapter_EnumOutputs(dxgiadapter, output_index,
                                         &probe_output) == DXGI_ERROR_NOT_FOUND)
                break;
            if (probe_output == NULL)
                continue;
            DXGI_OUTPUT_DESC output_desc;
            if (SUCCEEDED(IDXGIOutput_GetDesc(probe_output, &output_desc)))
            {
                DISPLAY_DEVICEW monitor_desc;
                ZeroMemory(&monitor_desc, sizeof(monitor_desc));
                monitor_desc.cb = sizeof(monitor_desc);
                EnumDisplayDevicesW(output_desc.DeviceName, 0,
                                    &monitor_desc, 0);
                msg_Info(vd, "DXGI output %u: %ls, monitor '%ls', "
                         "attached=%d, desktop=%ld,%ld-%ld,%ld",
                         output_index, output_desc.DeviceName,
                         monitor_desc.DeviceString,
                         output_desc.AttachedToDesktop != FALSE,
                         output_desc.DesktopCoordinates.left,
                         output_desc.DesktopCoordinates.top,
                         output_desc.DesktopCoordinates.right,
                         output_desc.DesktopCoordinates.bottom);
            }
            IDXGIOutput_Release(probe_output);
        }

        hr = IDXGIAdapter_GetParent(dxgiadapter, &IID_IDXGIFactory2, (void **)&dxgifactory);
        IDXGIAdapter_Release(dxgiadapter);
        if (FAILED(hr)) {
        msg_Err(vd, "Could not get the DXGI Factory. (hr=0x%lX)", hr);
        return VLC_EGENERIC;
        }

        if (sys->stereo_requested)
        {
            hr = PrimeStereoDisplay(vd, dxgifactory, &stereo_output);
            if (FAILED(hr))
            {
                msg_Warn(vd, "could not prime the HDMI stereo mode "
                         "(hr=0x%lX)", hr);
                if (stereo_output != NULL)
                    IDXGIOutput_Release(stereo_output);
                IDXGIFactory2_Release(dxgifactory);
                return VLC_EGENERIC;
            }

            hr = IDXGIFactory2_QueryInterface(
                dxgifactory, &IID_IDXGIDisplayControl,
                (void **)&sys->stereo_display_control);
            if (FAILED(hr) || sys->stereo_display_control == NULL)
            {
                msg_Warn(vd, "DXGI display control is unavailable "
                         "(hr=0x%lX)", hr);
                IDXGIOutput_Release(stereo_output);
                IDXGIFactory2_Release(dxgifactory);
                return VLC_EGENERIC;
            }

            bool display_is_enabled =
                IDXGIDisplayControl_IsStereoEnabled(
                    sys->stereo_display_control) != FALSE;
            /* An adopted session must ultimately restore the state from
             * before the first MVC vout, not the enabled state observed
             * halfway through the same Blu-ray. */
            if (!sys->stereo_adopted)
                sys->stereo_display_was_enabled = display_is_enabled;
            if (!display_is_enabled)
                IDXGIDisplayControl_SetStereoEnabled(
                    sys->stereo_display_control, TRUE);

            bool windowed_stereo_available =
                IDXGIFactory2_IsWindowedStereoEnabled(dxgifactory) != FALSE;
            /* Ivy Bridge reports windowed stereo support, yet DWM presents a
             * black image on this HDMI path.  Keep the proven exclusive path;
             * in-video controls are composed into its two back-buffer eyes. */
            sys->stereo_windowed = false;
            msg_Info(vd, "DXGI stereo after exclusive mode priming: "
                     "display=%d, windowed=%d",
                     IDXGIDisplayControl_IsStereoEnabled(
                         sys->stereo_display_control) != FALSE,
                     windowed_stereo_available);
            LogStereoModes(vd, stereo_output,
                           DXGI_FORMAT_B8G8R8A8_UNORM);
            LogStereoModes(vd, stereo_output,
                           DXGI_FORMAT_R8G8B8A8_UNORM);

            if (!sys->stereo_windowed)
            {
                /* This query is specifically about *windowed* stereo.  Old
                 * Intel drivers can keep returning false while accepting an
                 * exclusive stereo swap chain, which is the path required
                 * for HDMI frame packing anyway.  Let creation be the
                 * authoritative test. */
                msg_Warn(vd, "DXGI windowed stereo is unavailable; trying "
                         "the exclusive stereo swapchain");
            }

            stereo_fs_desc.ScanlineOrdering =
                DXGI_MODE_SCANLINE_ORDER_UNSPECIFIED;
            stereo_fs_desc.Scaling = DXGI_MODE_SCALING_UNSPECIFIED;
            /* Prefer the DWM stereo compositor when Windows exposes it.  A
             * borderless Qt fullscreen window still fills the projector, but
             * its controller/tool windows remain compositable and Windows
             * duplicates ordinary 2D UI into both eyes.  Exclusive mode is
             * retained as the fallback for older drivers. */
            stereo_fs_desc.Windowed = sys->stereo_windowed ? TRUE : FALSE;
        }

        FillSwapChainDesc(vd, &scd);

        if (sys->stereo_requested && !sys->stereo_windowed)
            scd.Flags |= DXGI_SWAP_CHAIN_FLAG_ALLOW_MODE_SWITCH;
        hr = IDXGIFactory2_CreateSwapChainForHwnd(dxgifactory,
                                                (IUnknown *)sys->d3d_dev.d3ddevice,
                                                sys->stereo_requested
                                                    ? StereoSwapChainWindow(sys)
                                                    : sys->sys.hvideownd,
                                                &scd,
                                                sys->stereo_requested ? &stereo_fs_desc : NULL,
                                                NULL,
                                                &sys->dxgiswapChain);
        if (hr == DXGI_ERROR_INVALID_CALL && scd.Format == DXGI_FORMAT_R10G10B10A2_UNORM)
        {
            msg_Warn(vd, "10 bits swapchain failed, try 8 bits");
            scd.Format = DXGI_FORMAT_R8G8B8A8_UNORM;
            hr = IDXGIFactory2_CreateSwapChainForHwnd(dxgifactory, (IUnknown *)sys->d3d_dev.d3ddevice,
                                                    sys->sys.hvideownd, &scd, NULL, NULL, &sys->dxgiswapChain);
        }
        IDXGIFactory2_Release(dxgifactory);
        if (FAILED(hr)) {
        if (stereo_output != NULL)
            IDXGIOutput_Release(stereo_output);
        msg_Err(vd, "Could not create the SwapChain. (hr=0x%lX)", hr);
        return VLC_EGENERIC;
        }
        if (sys->stereo_requested)
        {
            DXGI_SWAP_CHAIN_DESC1 created_desc;
            hr = IDXGISwapChain1_GetDesc1(sys->dxgiswapChain,
                                          &created_desc);
            if (FAILED(hr) || !created_desc.Stereo)
            {
                IDXGIOutput_Release(stereo_output);
                msg_Warn(vd, "DXGI created a monoscopic swapchain instead "
                         "of the requested stereoscopic one");
                return VLC_EGENERIC;
            }
            BOOL fullscreen = FALSE;
            IDXGIOutput *created_output = NULL;
            HRESULT state_hr = IDXGISwapChain_GetFullscreenState(
                sys->dxgiswapChain, &fullscreen, &created_output);
            msg_Info(vd, "DXGI stereo swapchain active: stereo=%d, "
                     "size=%ux%u, fullscreen=%d (hr=0x%lX)",
                     created_desc.Stereo != FALSE, created_desc.Width,
                     created_desc.Height, fullscreen != FALSE, state_hr);
            if (created_output != NULL)
                IDXGIOutput_Release(created_output);
            if (!sys->stereo_windowed)
            {
                hr = EnterStereoFullscreen(vd, "after creation",
                                           stereo_output);
                if (FAILED(hr))
                {
                    IDXGIOutput_Release(stereo_output);
                    msg_Warn(vd, "could not enter exclusive stereo mode "
                             "(hr=0x%lX)", hr);
                    return VLC_EGENERIC;
                }
            }
            else
                msg_Info(vd, "DXGI windowed stereo compositor active");
            sys->stereo_active = true;
            sys->stereo_present_output = stereo_output;
            IDXGIOutput_AddRef(sys->stereo_present_output);
        }
        if (stereo_output != NULL)
            IDXGIOutput_Release(stereo_output);
#endif
    }
    else
    {
        HRESULT hr = S_OK;
        IDXGIAdapter *adap = D3D11DeviceAdapter(sys->d3d_dev.d3ddevice);
        if (adap == NULL)
            hr = E_FAIL;
        else
        {
            hr = IDXGIAdapter_GetDesc(adap, &sys->d3d_dev.adapterDesc);
            IDXGIAdapter_Release(adap);
        }
        if (hr)
            msg_Warn(vd, "can't get adapter description");

        D3D11_GetDriverVersion(vd, &sys->d3d_dev);
    }

    IDXGISwapChain_QueryInterface( sys->dxgiswapChain, &IID_IDXGISwapChain4, (void **)&sys->dxgiswapChain4);

    D3D11SetColorSpace(vd);

    char *psz_upscale = var_InheritString(vd, "d3d11-upscale-mode");
    if (strcmp("linear", psz_upscale) == 0)
        sys->upscaleMode = upscale_LinearSampler;
    else if (strcmp("point", psz_upscale) == 0)
        sys->upscaleMode = upscale_PointSampler;
    else if (strcmp("processor", psz_upscale) == 0)
        sys->upscaleMode = upscale_VideoProcessor;
    else if (strcmp("super", psz_upscale) == 0)
        sys->upscaleMode = upscale_SuperResolution;
    else
    {
        msg_Warn(vd, "unknown upscale mode %s, using linear sampler", psz_upscale);
        sys->upscaleMode = upscale_LinearSampler;
    }
    free(psz_upscale);

    video_format_Copy(&sys->pool_fmt, &vd->source);
    video_format_Copy(&sys->quad_fmt, &vd->source);
    int err = SetupOutputFormat(vd, &sys->pool_fmt, &sys->quad_fmt);
    if (err != VLC_SUCCESS)
    {
        if (!is_d3d11_opaque(vd->source.i_chroma)
#if !VLC_WINSTORE_APP
            && vd->obj.force
#endif
                )
        {
            const vlc_fourcc_t *list = vlc_fourcc_IsYUV(vd->source.i_chroma) ?
                        vlc_fourcc_GetYUVFallback(vd->source.i_chroma) :
                        vlc_fourcc_GetRGBFallback(vd->source.i_chroma);
            for (unsigned i = 0; list[i] != 0; i++) {
                sys->pool_fmt.i_chroma = list[i];
                if (sys->pool_fmt.i_chroma == vd->source.i_chroma)
                    continue;
                err = SetupOutputFormat(vd, &sys->pool_fmt, &sys->quad_fmt);
                if (err == VLC_SUCCESS)
                    break;
            }
        }
        if (err != VLC_SUCCESS)
            return err;
    }

    if (sys->upscaleMode == upscale_VideoProcessor || sys->upscaleMode == upscale_SuperResolution)
        sys->sys.src_fmt = &sys->quad_fmt;

    if ( sys->picQuad.formatInfo->formatTexture != DXGI_FORMAT_R8G8B8A8_UNORM &&
         sys->picQuad.formatInfo->formatTexture != DXGI_FORMAT_B5G6R5_UNORM )
    {
        sys->pool_fmt.i_width  = (sys->pool_fmt.i_width  + 0x01) & ~0x01;
        sys->pool_fmt.i_height = (sys->pool_fmt.i_height + 0x01) & ~0x01;
    }

    if (Direct3D11CreateGenericResources(vd)) {
        msg_Err(vd, "Failed to allocate resources");
        return VLC_EGENERIC;
    }

    /* The CRT runner consumes the RGB result of VLC's normal D3D11 colour
     * conversion, then executes the build-time compiled Slang/HLSL graph.
     * Failure leaves the regular Direct3D output fully operational. */
    sys->crtShaders = D3D11_RA_Create(vd, &sys->hd3d, &sys->d3d_dev);
    if (!sys->crtShaders)
        msg_Warn(vd, "Direct3D11 RetroArch shader pipeline unavailable");

    video_format_Clean(&vd->fmt);
    video_format_Copy(&vd->fmt, &sys->pool_fmt);

    sys->log_level = var_InheritInteger(vd, "verbose");

    return VLC_SUCCESS;
}

static const d3d_format_t *SelectClosestOutput(vout_display_t *vd, vlc_fourcc_t i_chroma,
                                               bool from_processor)
{
    const d3d_format_t *res = NULL;

    // look for any pixel format that we can handle with enough pixels per channel
    uint8_t bits_per_channel;
    uint8_t widthDenominator, heightDenominator;
    switch (i_chroma)
    {
    case VLC_CODEC_D3D11_OPAQUE:
        bits_per_channel = 8;
        widthDenominator = heightDenominator = 2;
        break;
    case VLC_CODEC_D3D11_OPAQUE_10B:
        bits_per_channel = 10;
        widthDenominator = heightDenominator = 2;
        break;
    default:
        {
            const vlc_chroma_description_t *p_format = vlc_fourcc_GetChromaDescription(i_chroma);
            if (p_format == NULL)
            {
                bits_per_channel = 8;
                widthDenominator = heightDenominator = 2;
            }
            else
            {
                bits_per_channel = p_format->pixel_bits == 0 ? 8 : p_format->pixel_bits /
                                                                (p_format->plane_count==1 ? p_format->pixel_size : 1);
                widthDenominator = heightDenominator = 1;
                for (size_t i=0; i<p_format->plane_count; i++)
                {
                    if (widthDenominator < p_format->p[i].w.den)
                        widthDenominator = p_format->p[i].w.den;
                    if (heightDenominator < p_format->p[i].h.den)
                        heightDenominator = p_format->p[1].h.den;
                }
            }
        }
        break;
    }

    bool is_rgb = !vlc_fourcc_IsYUV(i_chroma);
    res = GetDisplayFormatByDepth(vd, bits_per_channel,
                                  widthDenominator,
                                  heightDenominator,
                                  from_processor, is_rgb);
    if (res != NULL)
        return res;
    if (is_rgb)
        res = GetDisplayFormatByDepth(vd, bits_per_channel,
                                      widthDenominator,
                                      heightDenominator,
                                      from_processor, false);
    if (res != NULL)
        return res;

    // look for any pixel format that we can handle
    res = GetDisplayFormatByDepth(vd, 0, 0, 0, false, false);
    return res;
}

static const d3d_format_t *SelectOutputFormat(vout_display_t *vd, const video_format_t *fmt,
                                              const d3d_format_t ** decoder_format)
{
    const d3d_format_t *res = NULL;
    // look for the requested pixel format first
    res = GetDirectRenderingFormat(vd, fmt->i_chroma);
    if (res != NULL)
        return res;

    /* look for a decoder format that can be decoded but not used in shaders */
    if ( is_d3d11_opaque(fmt->i_chroma) )
        *decoder_format = GetDirectDecoderFormat(vd, fmt->i_chroma);

    res = SelectClosestOutput(vd, fmt->i_chroma, *decoder_format!=NULL);

    return res;
}

static int SetupOutputFormat(vout_display_t *vd, video_format_t *fmt, video_format_t *quad_fmt)
{
    vout_display_sys_t *sys = vd->sys;

    // look for the requested pixel format first
    const d3d_format_t *decoder_format = NULL;
    sys->picQuad.formatInfo = SelectOutputFormat(vd, quad_fmt, &decoder_format);

    if ( !sys->picQuad.formatInfo )
    {
       msg_Err(vd, "Could not get a suitable texture pixel format");
       return VLC_EGENERIC;
    }
    sys->pool_d3dfmt = decoder_format ? decoder_format : sys->picQuad.formatInfo;

    InitScaleProcessor(vd);

    msg_Dbg( vd, "Using pixel format %s for chroma %4.4s", sys->pool_d3dfmt->name,
                 (char *)&fmt->i_chroma );
    fmt->i_chroma = sys->pool_d3dfmt->fourcc;
    DxgiFormatMask( sys->picQuad.formatInfo->formatTexture, fmt );

    InitTonemapProcessor(vd, quad_fmt);

    if (sys->hdrMode == hdr_Fake)
    {
        quad_fmt->i_chroma           = VLC_CODEC_RGBA10;
        quad_fmt->primaries          = sys->display.colorspace->primaries;
        quad_fmt->transfer           = sys->display.colorspace->transfer;
        quad_fmt->space              = sys->display.colorspace->color;
        quad_fmt->b_color_range_full = sys->display.colorspace->b_full_range;
        sys->picQuad.formatInfo = SelectOutputFormat(vd, quad_fmt, &decoder_format);
    }

    /* check the region pixel format */
    sys->d3dregion_format = GetBlendableFormat(vd, VLC_CODEC_RGBA);
    if (!sys->d3dregion_format)
        sys->d3dregion_format = GetBlendableFormat(vd, VLC_CODEC_BGRA);

    sys->legacy_shader = sys->d3d_dev.feature_level < D3D_FEATURE_LEVEL_10_0 ||
            (sys->scaleProc == NULL && !CanUseTextureArray(vd)) ||
            BogusZeroCopy(vd);

    if (Direct3D11CreateFormatResources(vd, quad_fmt)) {
        msg_Err(vd, "Failed to allocate format resources");
        return VLC_EGENERIC;
    }
    vd->info.is_slow = !is_d3d11_opaque(fmt->i_chroma) && sys->picQuad.formatInfo->formatTexture != DXGI_FORMAT_UNKNOWN;

    return VLC_SUCCESS;
}

static void Direct3D11Close(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    Direct3D11DestroyResources(vd);
    if (sys->stereo_present_output != NULL)
    {
        IDXGIOutput_Release(sys->stereo_present_output);
        sys->stereo_present_output = NULL;
    }
    if (sys->dxgiswapChain4)
    {
        IDXGISwapChain_Release(sys->dxgiswapChain4);
        sys->dxgiswapChain4 = NULL;
    }
    if (sys->dxgiswapChain)
    {
        BOOL fullscreen = FALSE;
        if (SUCCEEDED(IDXGISwapChain_GetFullscreenState(
                          sys->dxgiswapChain, &fullscreen, NULL)) &&
            fullscreen)
            IDXGISwapChain_SetFullscreenState(sys->dxgiswapChain,
                                              FALSE, NULL);
        IDXGISwapChain_Release(sys->dxgiswapChain);
        sys->dxgiswapChain = NULL;
    }

    D3D11_ReleaseDevice( &sys->d3d_dev );

    msg_Dbg(vd, "Direct3D11 device adapter closed");
}

static void UpdatePicQuadPosition(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    sys->picQuad.cropViewport.Width    = RECTWidth(sys->sys.rect_dest_clipped);
    sys->picQuad.cropViewport.Height   = RECTHeight(sys->sys.rect_dest_clipped);
    sys->picQuad.cropViewport.TopLeftX = sys->sys.rect_dest_clipped.left;
    sys->picQuad.cropViewport.TopLeftY = sys->sys.rect_dest_clipped.top;

    sys->picQuad.cropViewport.MinDepth = 0.0f;
    sys->picQuad.cropViewport.MaxDepth = 1.0f;

    SetQuadVSProjection(vd, &sys->picQuad, &vd->cfg->viewpoint);

#ifndef NDEBUG
    msg_Dbg(vd, "picQuad position (%.02f,%.02f) %.02fx%.02f", sys->picQuad.cropViewport.TopLeftX, sys->picQuad.cropViewport.TopLeftY, sys->picQuad.cropViewport.Width, sys->picQuad.cropViewport.Height );
#endif
}

/* TODO : handle errors better
   TODO : seperate out into smaller functions like createshaders */
static int Direct3D11CreateFormatResources(vout_display_t *vd, const video_format_t *fmt)
{
    vout_display_sys_t *sys = vd->sys;
    HRESULT hr;

    const video_transfer_func_t source_transfer = fmt->dovi.rpu_present
                                                ? TRANSFER_FUNC_SMPTE_ST2084
                                                : fmt->transfer;
    const video_color_primaries_t source_primaries = fmt->dovi.rpu_present
                                                   ? COLOR_PRIMARIES_BT2020
                                                   : fmt->primaries;
    hr = D3D11_CompilePixelShader(vd, &sys->hd3d, sys->legacy_shader, &sys->d3d_dev,
                                  sys->picQuad.formatInfo, &sys->display,
                                  source_transfer, source_primaries,
                                  fmt->b_color_range_full, fmt->dovi.rpu_present,
                                  &sys->picQuad.d3dpixelShader);
    if (FAILED(hr))
    {
        msg_Err(vd, "Failed to create the pixel shader. (hr=0x%lX)", hr);
        return VLC_EGENERIC;
    }

    sys->picQuad.i_width  = fmt->i_width;
    sys->picQuad.i_height = fmt->i_height;

    CallUpdateRects(vd);

#ifdef HAVE_ID3D11VIDEODECODER
    if (!is_d3d11_opaque(fmt->i_chroma) || sys->legacy_shader)
    {
        /* we need a staging texture */
        int ret = CreateStaging(vd, NULL);
        if (ret != VLC_SUCCESS)
            return ret;
    }
#endif

    return VLC_SUCCESS;
}

#ifdef HAVE_D3D11_4_H
static HRESULT InitRenderFence(vout_display_sys_t *sys)
{
    HRESULT hr;
    sys->renderFinished = CreateEvent(NULL, TRUE, FALSE, NULL);
    if (unlikely(sys->renderFinished == NULL))
        return S_FALSE;
    ID3D11Device5 *d3ddev5 = NULL;
    hr = ID3D11DeviceContext_QueryInterface(sys->d3d_dev.d3dcontext, &IID_ID3D11DeviceContext4, (void**)&sys->d3dcontext4);
    if (FAILED(hr))
        goto error;
    hr = ID3D11Device_QueryInterface(sys->d3d_dev.d3ddevice, &IID_ID3D11Device5, (void**)&d3ddev5);
    if (FAILED(hr))
        goto error;
    hr = ID3D11Device5_CreateFence(d3ddev5, sys->renderFence, D3D11_FENCE_FLAG_NONE, &IID_ID3D11Fence, (void**)&sys->d3dRenderFence);
    if (FAILED(hr))
        goto error;
    ID3D11Device5_Release(d3ddev5);
    return hr;
error:
    if (d3ddev5)
        ID3D11Device5_Release(d3ddev5);
    if (sys->d3dRenderFence)
    {
        ID3D11Fence_Release(sys->d3dRenderFence);
        sys->d3dRenderFence = NULL;
    }
    if (sys->d3dcontext4)
    {
        ID3D11DeviceContext4_Release(sys->d3dcontext4);
        sys->d3dcontext4 = NULL;
    }
    CloseHandle(sys->renderFinished);
    return hr;
}
#endif // HAVE_D3D11_4_H

static int Direct3D11CreateGenericResources(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    HRESULT hr;

#ifdef HAVE_D3D11_4_H
    hr = InitRenderFence(sys);
    if (SUCCEEDED(hr))
    {
        msg_Dbg(vd, "using GPU render fence");
    }
#endif

    ID3D11BlendState *pSpuBlendState;
    D3D11_BLEND_DESC spuBlendDesc = { 0 };
    spuBlendDesc.RenderTarget[0].BlendEnable = TRUE;
    spuBlendDesc.RenderTarget[0].SrcBlend = D3D11_BLEND_SRC_ALPHA;
    spuBlendDesc.RenderTarget[0].DestBlend = D3D11_BLEND_INV_SRC_ALPHA;
    spuBlendDesc.RenderTarget[0].BlendOp = D3D11_BLEND_OP_ADD;

    spuBlendDesc.RenderTarget[0].SrcBlendAlpha = D3D11_BLEND_ONE;
    spuBlendDesc.RenderTarget[0].DestBlendAlpha = D3D11_BLEND_ZERO;
    spuBlendDesc.RenderTarget[0].BlendOpAlpha = D3D11_BLEND_OP_ADD;

    spuBlendDesc.RenderTarget[0].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;

    spuBlendDesc.RenderTarget[1].BlendEnable = TRUE;
    spuBlendDesc.RenderTarget[1].SrcBlend = D3D11_BLEND_ONE;
    spuBlendDesc.RenderTarget[1].DestBlend = D3D11_BLEND_ZERO;
    spuBlendDesc.RenderTarget[1].BlendOp = D3D11_BLEND_OP_ADD;

    spuBlendDesc.RenderTarget[1].SrcBlendAlpha = D3D11_BLEND_ONE;
    spuBlendDesc.RenderTarget[1].DestBlendAlpha = D3D11_BLEND_ZERO;
    spuBlendDesc.RenderTarget[1].BlendOpAlpha = D3D11_BLEND_OP_ADD;

    spuBlendDesc.RenderTarget[1].RenderTargetWriteMask = D3D11_COLOR_WRITE_ENABLE_ALL;
    hr = ID3D11Device_CreateBlendState(sys->d3d_dev.d3ddevice, &spuBlendDesc, &pSpuBlendState);
    if (FAILED(hr)) {
       msg_Err(vd, "Could not create SPU blend state. (hr=0x%lX)", hr);
       return VLC_EGENERIC;
    }
    ID3D11DeviceContext_OMSetBlendState(sys->d3d_dev.d3dcontext, pSpuBlendState, NULL, 0xFFFFFFFF);
    ID3D11BlendState_Release(pSpuBlendState);

    /* disable depth testing as we're only doing 2D
     * see https://msdn.microsoft.com/en-us/library/windows/desktop/bb205074%28v=vs.85%29.aspx
     * see http://rastertek.com/dx11tut11.html
    */
    D3D11_DEPTH_STENCIL_DESC stencilDesc;
    ZeroMemory(&stencilDesc, sizeof(stencilDesc));

    ID3D11DepthStencilState *pDepthStencilState;
    hr = ID3D11Device_CreateDepthStencilState(sys->d3d_dev.d3ddevice, &stencilDesc, &pDepthStencilState );
    if (SUCCEEDED(hr)) {
        ID3D11DeviceContext_OMSetDepthStencilState(sys->d3d_dev.d3dcontext, pDepthStencilState, 0);
        ID3D11DepthStencilState_Release(pDepthStencilState);
    }

    hr = UpdateBackBuffer(vd);
    if (FAILED(hr)) {
       msg_Err(vd, "Could not update the backbuffer. (hr=0x%lX)", hr);
       return VLC_EGENERIC;
    }

    CallUpdateRects(vd);

    if (sys->d3dregion_format != NULL)
    {
        hr = D3D11_CompilePixelShader(vd, &sys->hd3d, sys->legacy_shader, &sys->d3d_dev,
                                      sys->d3dregion_format, &sys->display, TRANSFER_FUNC_SRGB, COLOR_PRIMARIES_SRGB, true, false, &sys->pSPUPixelShader);
        if (FAILED(hr))
        {
            if (sys->picQuad.d3dpixelShader)
            {
                ID3D11PixelShader_Release(sys->picQuad.d3dpixelShader);
                sys->picQuad.d3dpixelShader = NULL;
            }
            msg_Err(vd, "Failed to create the SPU pixel shader. (hr=0x%lX)", hr);
            return VLC_EGENERIC;
        }
    }

    ID3DBlob *pVSBlob = D3D11_CompileShader(vd, &sys->hd3d, &sys->d3d_dev, globVertexShaderFlat, false);
    if (!pVSBlob)
        return VLC_EGENERIC;

    hr = ID3D11Device_CreateVertexShader(sys->d3d_dev.d3ddevice, (void *)ID3D10Blob_GetBufferPointer(pVSBlob),
                                        ID3D10Blob_GetBufferSize(pVSBlob), NULL, &sys->flatVSShader);

    if(FAILED(hr)) {
      ID3D10Blob_Release(pVSBlob);
      msg_Err(vd, "Failed to create the flat vertex shader. (hr=0x%lX)", hr);
      return VLC_EGENERIC;
    }

    D3D11_INPUT_ELEMENT_DESC layout[] = {
    { "POSITION", 0, DXGI_FORMAT_R32G32B32_FLOAT, 0, D3D11_APPEND_ALIGNED_ELEMENT, D3D11_INPUT_PER_VERTEX_DATA, 0},
    { "TEXCOORD", 0, DXGI_FORMAT_R32G32_FLOAT,    0, D3D11_APPEND_ALIGNED_ELEMENT, D3D11_INPUT_PER_VERTEX_DATA, 0},
    };

    hr = ID3D11Device_CreateInputLayout(sys->d3d_dev.d3ddevice, layout, 2, (void *)ID3D10Blob_GetBufferPointer(pVSBlob),
                                        ID3D10Blob_GetBufferSize(pVSBlob), &sys->pVertexLayout);

    ID3D10Blob_Release(pVSBlob);

    if(FAILED(hr)) {
      msg_Err(vd, "Failed to create the vertex input layout. (hr=0x%lX)", hr);
      return VLC_EGENERIC;
    }

    pVSBlob = D3D11_CompileShader(vd, &sys->hd3d, &sys->d3d_dev, globVertexShaderProjection, false);
    if (!pVSBlob)
        return VLC_EGENERIC;

    hr = ID3D11Device_CreateVertexShader(sys->d3d_dev.d3ddevice, (void *)ID3D10Blob_GetBufferPointer(pVSBlob),
                                        ID3D10Blob_GetBufferSize(pVSBlob), NULL, &sys->projectionVSShader);

    if(FAILED(hr)) {
      ID3D10Blob_Release(pVSBlob);
      msg_Err(vd, "Failed to create the projection vertex shader. (hr=0x%lX)", hr);
      return VLC_EGENERIC;
    }
    ID3D10Blob_Release(pVSBlob);

    UpdatePicQuadPosition(vd);

    UpdateSamplers(vd);

    msg_Dbg(vd, "Direct3D11 resources created");
    return VLC_SUCCESS;
}

static void Direct3D11DestroyPool(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    if (sys->sys.pool)
        picture_pool_Release(sys->sys.pool);
    sys->sys.pool = NULL;
    video_format_Clean(&sys->pool_fmt);
}

static void Direct3D11DestroyResources(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;

    Direct3D11DestroyPool(vd);

    if (sys->crtShaders)
    {
        D3D11_RA_Destroy(sys->crtShaders);
        sys->crtShaders = NULL;
    }

    D3D11_ReleaseQuad(&sys->picQuad);
    Direct3D11DeleteRegions(sys->d3dregion_count, sys->d3dregions);
    sys->d3dregion_count = 0;
    sys->d3dregion_order_valid = false;

    ReleasePictureSys(&sys->stagingSys);
    CloseHandle(sys->sharedHandle);
    sys->sharedHandle = INVALID_HANDLE_VALUE;

    if (sys->tonemapProc != NULL)
    {
        D3D11_TonemapperDestroy(sys->tonemapProc);
        sys->tonemapProc = NULL;
    }
    if (sys->scaleProc != NULL)
    {
        D3D11_UpscalerDestroy(sys->scaleProc);
        sys->scaleProc = NULL;
    }
    video_format_Clean(&sys->quad_fmt);

    if (sys->pVertexLayout)
    {
        ID3D11InputLayout_Release(sys->pVertexLayout);
        sys->pVertexLayout = NULL;
    }
    if (sys->flatVSShader)
    {
        ID3D11VertexShader_Release(sys->flatVSShader);
        sys->flatVSShader = NULL;
    }
    if (sys->projectionVSShader)
    {
        ID3D11VertexShader_Release(sys->projectionVSShader);
        sys->projectionVSShader = NULL;
    }
    if (sys->d3drenderTargetView)
    {
        ID3D11RenderTargetView_Release(sys->d3drenderTargetView);
        sys->d3drenderTargetView = NULL;
    }
    if (sys->d3drenderTargetViewRight)
    {
        ID3D11RenderTargetView_Release(sys->d3drenderTargetViewRight);
        sys->d3drenderTargetViewRight = NULL;
    }
    if (sys->d3ddepthStencilView)
    {
        ID3D11DepthStencilView_Release(sys->d3ddepthStencilView);
        sys->d3ddepthStencilView = NULL;
    }
    if (sys->pSPUPixelShader)
    {
        ID3D11PixelShader_Release(sys->pSPUPixelShader);
        sys->pSPUPixelShader = NULL;
    }
    if (sys->picQuad.d3dpixelShader)
    {
        ID3D11PixelShader_Release(sys->picQuad.d3dpixelShader);
        sys->picQuad.d3dpixelShader = NULL;
    }
#ifdef HAVE_D3D11_4_H
    if (sys->d3dcontext4)
    {
        ID3D11Fence_Release(sys->d3dRenderFence);
        sys->d3dRenderFence = NULL;
        ID3D11DeviceContext4_Release(sys->d3dcontext4);
        sys->d3dcontext4 = NULL;
        CloseHandle(sys->renderFinished);
        sys->renderFinished = NULL;
    }
#endif

    msg_Dbg(vd, "Direct3D11 resources destroyed");
}

static void Direct3D11DeleteRegions(int count, picture_t **region)
{
    for (int i = 0; i < count; ++i) {
        if (region[i]) {
            picture_Release(region[i]);
        }
    }
    free(region);
}

static void DestroyPictureQuad(picture_t *p_picture)
{
    D3D11_ReleaseQuad( (d3d_quad_t *) p_picture->p_sys );
    free( p_picture );
}

static int Direct3D11MapSubpicture(vout_display_t *vd, int *subpicture_region_count,
                                   picture_t ***region, subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;
    D3D11_MAPPED_SUBRESOURCE mappedResource;
    D3D11_TEXTURE2D_DESC texDesc;
    HRESULT hr;
    int err;

    if (sys->d3dregion_format == NULL)
        return VLC_EGENERIC;

    int count = 0;
    for (subpicture_region_t *r = subpicture->p_region; r; r = r->p_next)
        count++;

    *region = calloc(count, sizeof(picture_t *));
    if (unlikely(*region==NULL))
        return VLC_ENOMEM;
    *subpicture_region_count = count;

    int i = 0;
    for (subpicture_region_t *r = subpicture->p_region; r; r = r->p_next, i++) {
        if (!r->fmt.i_visible_width || !r->fmt.i_visible_height)
            continue; // won't render anything, keep the cache for later

        for (int j = 0; j < sys->d3dregion_count; j++) {
            picture_t *cache = sys->d3dregions[j];
            if (cache != NULL && ((d3d_quad_t *) cache->p_sys)->picSys.texture[KNOWN_DXGI_INDEX]) {
                ID3D11Texture2D_GetDesc( ((d3d_quad_t *) cache->p_sys)->picSys.texture[KNOWN_DXGI_INDEX], &texDesc );
                if (texDesc.Format == sys->d3dregion_format->formatTexture &&
                    texDesc.Width  == r->p_picture->format.i_width &&
                    texDesc.Height == r->p_picture->format.i_height) {
                    (*region)[i] = cache;
                    memset(&sys->d3dregions[j], 0, sizeof(cache)); // do not reuse this cached value
                    break;
                }
            }
        }

        RECT output;
        output.left   = r->fmt.i_x_offset;
        output.right  = r->fmt.i_x_offset + r->fmt.i_visible_width;
        output.top    = r->fmt.i_y_offset;
        output.bottom = r->fmt.i_y_offset + r->fmt.i_visible_height;

        picture_t *quad_picture = (*region)[i];
        if (quad_picture == NULL) {
            d3d_quad_t *d3dquad = calloc(1, sizeof(*d3dquad));
            if (unlikely(d3dquad==NULL)) {
                continue;
            }
            if (AllocateTextures(vd, &sys->d3d_dev, sys->d3dregion_format,
                                 &r->p_picture->format, false, false, 1,
                                 d3dquad->picSys.texture)) {
                msg_Err(vd, "Failed to allocate %dx%d texture for OSD",
                        r->fmt.i_visible_width, r->fmt.i_visible_height);
                for (int j=0; j<D3D11_MAX_SHADER_VIEW; j++)
                    if (d3dquad->picSys.texture[j])
                        ID3D11Texture2D_Release(d3dquad->picSys.texture[j]);
                free(d3dquad);
                continue;
            }

            if (D3D11_AllocateShaderView(vd, sys->d3d_dev.d3ddevice, sys->d3dregion_format,
                                         d3dquad->picSys.texture, 0,
                                         d3dquad->picSys.resourceView)) {
                msg_Err(vd, "Failed to create %dx%d shader view for OSD",
                        r->fmt.i_visible_width, r->fmt.i_visible_height);
                free(d3dquad);
                continue;
            }
            d3dquad->i_width    = r->fmt.i_width;
            d3dquad->i_height   = r->fmt.i_height;

            d3dquad->formatInfo = sys->d3dregion_format;
            err = D3D11_SetupQuad( vd, &sys->d3d_dev, &r->fmt, d3dquad, &sys->display, &output,
                             sys->flatVSShader, sys->pVertexLayout, PROJECTION_MODE_RECTANGULAR, ORIENT_NORMAL );
            if (err != VLC_SUCCESS) {
                msg_Err(vd, "Failed to create %dx%d quad for OSD",
                        r->fmt.i_visible_width, r->fmt.i_visible_height);
                free(d3dquad);
                continue;
            }
            d3dquad->d3dpixelShader = sys->pSPUPixelShader;
            picture_resource_t picres = {
                .p_sys      = (picture_sys_t *) d3dquad,
                .pf_destroy = DestroyPictureQuad,
            };
            (*region)[i] = picture_NewFromResource(&r->p_picture->format, &picres);
            if ((*region)[i] == NULL) {
                msg_Err(vd, "Failed to create %dx%d picture for OSD",
                        r->fmt.i_width, r->fmt.i_height);
                D3D11_ReleaseQuad(d3dquad);
                continue;
            }
            quad_picture = (*region)[i];
        } else {
            D3D11_UpdateQuadPosition(vd, &sys->d3d_dev, (d3d_quad_t *) quad_picture->p_sys, &output, ORIENT_NORMAL);
        }

        hr = ID3D11DeviceContext_Map(sys->d3d_dev.d3dcontext, ((d3d_quad_t *) quad_picture->p_sys)->picSys.resource[KNOWN_DXGI_INDEX], 0, D3D11_MAP_WRITE_DISCARD, 0, &mappedResource);
        if( SUCCEEDED(hr) ) {
            err = CommonUpdatePicture(quad_picture, NULL, mappedResource.pData, mappedResource.RowPitch);
            if (err != VLC_SUCCESS) {
                msg_Err(vd, "Failed to set the buffer on the SPU picture" );
                ID3D11DeviceContext_Unmap(sys->d3d_dev.d3dcontext, ((d3d_quad_t *) quad_picture->p_sys)->picSys.resource[KNOWN_DXGI_INDEX], 0);
                picture_Release(quad_picture);
                if ((*region)[i] == quad_picture)
                    (*region)[i] = NULL;
                continue;
            }

            picture_CopyPixels(quad_picture, r->p_picture);

            ID3D11DeviceContext_Unmap(sys->d3d_dev.d3dcontext, ((d3d_quad_t *) quad_picture->p_sys)->picSys.resource[KNOWN_DXGI_INDEX], 0);
        } else {
            msg_Err(vd, "Failed to map the SPU texture (hr=0x%lX)", hr );
            picture_Release(quad_picture);
            if ((*region)[i] == quad_picture)
                (*region)[i] = NULL;
            continue;
        }

        d3d_quad_t *quad = (d3d_quad_t *) quad_picture->p_sys;

        vout_display_cfg_t place_cfg = *vd->cfg;
        if (sys->sys.rect_display.right && sys->sys.rect_display.bottom)
        {
            place_cfg.display.width  = sys->sys.rect_display.right;
            place_cfg.display.height = sys->sys.rect_display.bottom;
        } else {
            place_cfg.display.width  = RECTWidth(sys->sys.rect_dest_clipped);
            place_cfg.display.height = RECTHeight(sys->sys.rect_dest_clipped);
        }

        vout_display_place_t place;
        vout_display_PlacePicture(&place, &vd->source, &place_cfg, false);

        quad->cropViewport.Width =  (FLOAT) r->fmt.i_visible_width  * place.width  / subpicture->i_original_picture_width;
        quad->cropViewport.Height = (FLOAT) r->fmt.i_visible_height * place.height / subpicture->i_original_picture_height;
        quad->cropViewport.MinDepth = 0.0f;
        quad->cropViewport.MaxDepth = 1.0f;
        quad->cropViewport.TopLeftX = place.x + (FLOAT) r->i_x * place.width  / subpicture->i_original_picture_width;
        quad->cropViewport.TopLeftY = place.y + (FLOAT) r->i_y * place.height / subpicture->i_original_picture_height;
        quad->stereoOffset = r->i_stereo_offset;

        D3D11_UpdateQuadOpacity(vd, &sys->d3d_dev, quad, r->i_alpha / 255.0f );
    }
    return VLC_SUCCESS;
}
