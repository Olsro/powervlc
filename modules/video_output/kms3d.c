/*****************************************************************************
 * kms3d.c: direct Linux DRM/KMS output for HDMI frame-packed Blu-ray 3D
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC authors
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or (at
 * your option) any later version.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <linux/kd.h>
#include <poll.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#if defined(__SSE2__)
# include <emmintrin.h>
#endif

#include <xf86drm.h>
#include <xf86drmMode.h>

#include <vlc_common.h>
#include <vlc_aout.h>
#include <vlc_fs.h>
#include <vlc_input.h>
#include <vlc_picture_pool.h>
#include <vlc_playlist.h>
#include <vlc_plugin.h>
#include <vlc_vout.h>
#include <vlc_vout_display.h>
#include <vlc_vout_osd.h>

#define CFG_PREFIX "kms3d-"

static const vlc_fourcc_t subpicture_chromas[] = {
    VLC_CODEC_RGBA, 0
};

typedef struct
{
    uint32_t handle;
    uint32_t fb_id;
    uint32_t pitch;
    uint64_t size;
    uint8_t *map;
} kms_buffer_t;

typedef struct
{
    drmModeCrtc *crtc;
    uint32_t *connectors;
    int connector_count;
} kms_saved_crtc_t;

struct vout_display_sys_t
{
    int fd;
    int tty_fd;
    int tty_mode;
    bool tty_graphics;
    uint32_t connector_id;
    uint32_t crtc_id;
    uint32_t max_bpc_property_id;
    uint64_t saved_max_bpc;
    bool max_bpc_changed;
    kms_saved_crtc_t *saved_crtcs;
    int saved_crtc_count;
    drmModeModeInfo mode;
    unsigned eye_width;
    unsigned eye_height;
    unsigned eye_stride;
    bool stereo_source;
    kms_buffer_t buffers[3];
    unsigned front;
    unsigned queued;
    unsigned prepared;
    bool prepared_valid;
    bool flip_pending;
    unsigned overlay_debug_count;
    bool mouse_callback;
    vlc_mutex_t cursor_lock;
    int cursor_x;
    int cursor_y;
    bool cursor_visible;
    vlc_tick_t cursor_until;
    vlc_tick_t controls_until;
    float controls_position;
    int64_t controls_time;
    int64_t controls_length;
    bool controls_paused;
    picture_pool_t *pool;
};

/* A Blu-ray changes vout objects between clips even when the HDMI mode stays
 * identical. Keep one direct-KMS session across that narrow hand-off so the
 * sink never loses sync and the other CRTCs remain blank. */
static vlc_mutex_t retained_lock = VLC_STATIC_MUTEX;
static vout_display_sys_t *retained_sys;

static int Open(vlc_object_t *);
static void Close(vlc_object_t *);
static void ReleaseSystem(vout_display_sys_t *);

static void WriteTransitionMarker(const char *variable, const char *value)
{
    const char *path = getenv(variable);
    if (!path || !*path)
        return;
    FILE *marker = fopen(path, "w");
    if (!marker)
        return;
    fputs(value, marker);
    fputc('\n', marker);
    fclose(marker);
}

vlc_module_begin()
    set_shortname("KMS 3D")
    set_description(N_("Linux DRM/KMS HDMI frame-packing video output"))
    set_category(CAT_VIDEO)
    set_subcategory(SUBCAT_VIDEO_VOUT)
    set_capability("vout display", 275)
    add_loadfile(CFG_PREFIX "device", NULL,
                 N_("DRM device"),
                 N_("DRM card to use, or automatic when empty"), true)
    add_string(CFG_PREFIX "connector", NULL,
               N_("DRM connector"),
               N_("Connector such as HDMI-A-1, or automatic when empty"), true)
    set_callbacks(Open, Close)
vlc_module_end()

static const char *ConnectorTypeName(uint32_t type)
{
    switch (type) {
        case DRM_MODE_CONNECTOR_HDMIA: return "HDMI-A";
        case DRM_MODE_CONNECTOR_HDMIB: return "HDMI-B";
        case DRM_MODE_CONNECTOR_DisplayPort: return "DP";
        default: return "connector";
    }
}

static uint32_t FindCrtc(int fd, const drmModeRes *res,
                         const drmModeConnector *connector)
{
    drmModeEncoder *encoder = connector->encoder_id
                            ? drmModeGetEncoder(fd, connector->encoder_id) : NULL;
    uint32_t id = encoder ? encoder->crtc_id : 0;
    drmModeFreeEncoder(encoder);
    if (id)
        return id;

    for (int e = 0; e < connector->count_encoders; ++e) {
        encoder = drmModeGetEncoder(fd, connector->encoders[e]);
        if (!encoder)
            continue;
        for (int c = 0; c < res->count_crtcs; ++c) {
            if (encoder->possible_crtcs & (1u << c)) {
                id = res->crtcs[c];
                break;
            }
        }
        drmModeFreeEncoder(encoder);
        if (id)
            return id;
    }
    return 0;
}

static int ModeScore(const drmModeModeInfo *mode, unsigned width,
                     unsigned height, unsigned fps_num, unsigned fps_den)
{
    if ((mode->flags & DRM_MODE_FLAG_3D_MASK) !=
        DRM_MODE_FLAG_3D_FRAME_PACKING ||
        mode->hdisplay != width || mode->vdisplay != height)
        return -1;

    double wanted = fps_num && fps_den ? (double)fps_num / fps_den : 23.976;
    double actual = (double)mode->clock * 1000.0 /
                    ((double)mode->htotal * mode->vtotal);
    double error = actual > wanted ? actual - wanted : wanted - actual;
    if (error > 2.0)
        return -1;
    return 100000 - (int)(error * 10000.0);
}

static void FreeSavedCrtcs(vout_display_sys_t *sys)
{
    for (int i = 0; i < sys->saved_crtc_count; ++i) {
        drmModeFreeCrtc(sys->saved_crtcs[i].crtc);
        free(sys->saved_crtcs[i].connectors);
    }
    free(sys->saved_crtcs);
    sys->saved_crtcs = NULL;
    sys->saved_crtc_count = 0;
}

static int SaveCrtcs(vout_display_t *vd, const drmModeRes *res)
{
    vout_display_sys_t *sys = vd->sys;
    sys->saved_crtcs = calloc((size_t)res->count_crtcs,
                              sizeof(*sys->saved_crtcs));
    if (!sys->saved_crtcs)
        return VLC_ENOMEM;

    sys->saved_crtc_count = res->count_crtcs;
    for (int c = 0; c < res->count_crtcs; ++c) {
        kms_saved_crtc_t *saved = &sys->saved_crtcs[c];
        saved->crtc = drmModeGetCrtc(sys->fd, res->crtcs[c]);
        saved->connectors = calloc((size_t)res->count_connectors,
                                   sizeof(*saved->connectors));
        if (!saved->crtc || !saved->connectors) {
            FreeSavedCrtcs(sys);
            return VLC_ENOMEM;
        }

        for (int i = 0; i < res->count_connectors; ++i) {
            drmModeConnector *connector = drmModeGetConnector(
                sys->fd, res->connectors[i]);
            drmModeEncoder *encoder = connector && connector->encoder_id
                                    ? drmModeGetEncoder(sys->fd,
                                                       connector->encoder_id)
                                    : NULL;
            if (encoder && encoder->crtc_id == saved->crtc->crtc_id)
                saved->connectors[saved->connector_count++] =
                    connector->connector_id;
            drmModeFreeEncoder(encoder);
            drmModeFreeConnector(connector);
        }
    }
    return VLC_SUCCESS;
}

/* HDMI frame-packing on Blu-ray 3D is an 8-bpc transport. Some drivers keep
 * the desktop's deep-colour preference when a legacy client becomes DRM
 * master; on Intel this raises the TMDS clock from 148.5 to 222.75 MHz and
 * can leave video working while HDMI audio has no usable clock. Apply the
 * standard transport depth only when the connector exposes max bpc, and
 * restore the compositor's value when the direct-KMS session ends. */
static void ConfigureFramePackingBpc(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    drmModeObjectProperties *properties = drmModeObjectGetProperties(
        sys->fd, sys->connector_id, DRM_MODE_OBJECT_CONNECTOR);
    if (!properties)
        return;

    for (uint32_t i = 0; i < properties->count_props; ++i) {
        drmModePropertyRes *property = drmModeGetProperty(
            sys->fd, properties->props[i]);
        if (!property)
            continue;
        if (!strcmp(property->name, "max bpc") &&
            (property->flags & DRM_MODE_PROP_RANGE) &&
            property->count_values >= 2) {
            uint64_t minimum = property->values[0];
            uint64_t maximum = property->values[1];
            uint64_t bpc = VLC_CLIP(UINT64_C(8), minimum, maximum);
            sys->max_bpc_property_id = property->prop_id;
            sys->saved_max_bpc = properties->prop_values[i];
            if (sys->saved_max_bpc != bpc &&
                drmModeObjectSetProperty(sys->fd, sys->connector_id,
                                         DRM_MODE_OBJECT_CONNECTOR,
                                         property->prop_id, bpc) == 0) {
                sys->max_bpc_changed = true;
                msg_Info(vd, "set HDMI frame-packing transport to %"PRIu64
                             " bpc (was %"PRIu64")",
                         bpc, sys->saved_max_bpc);
            }
            drmModeFreeProperty(property);
            break;
        }
        drmModeFreeProperty(property);
    }
    drmModeFreeObjectProperties(properties);
}

static int CreateBuffer(vout_display_t *vd, kms_buffer_t *buffer)
{
    vout_display_sys_t *sys = vd->sys;
    struct drm_mode_create_dumb create = {
        .width = sys->eye_width,
        .height = sys->eye_height + sys->mode.vtotal,
        .bpp = 32,
    };
    if (drmIoctl(sys->fd, DRM_IOCTL_MODE_CREATE_DUMB, &create) != 0)
        return VLC_EGENERIC;

    buffer->handle = create.handle;
    buffer->pitch = create.pitch;
    buffer->size = create.size;
    if (drmModeAddFB(sys->fd, create.width, create.height, 24, 32,
                     create.pitch, create.handle, &buffer->fb_id) != 0)
        return VLC_EGENERIC;

    struct drm_mode_map_dumb map = { .handle = create.handle };
    if (drmIoctl(sys->fd, DRM_IOCTL_MODE_MAP_DUMB, &map) != 0)
        return VLC_EGENERIC;
    buffer->map = mmap(NULL, create.size, PROT_READ | PROT_WRITE, MAP_SHARED,
                       sys->fd, map.offset);
    if (buffer->map == MAP_FAILED) {
        buffer->map = NULL;
        return VLC_EGENERIC;
    }
    memset(buffer->map, 0, buffer->size);
    return VLC_SUCCESS;
}

static void DestroyBuffer(vout_display_sys_t *sys, kms_buffer_t *buffer)
{
    if (buffer->map)
        munmap(buffer->map, buffer->size);
    if (buffer->fb_id)
        drmModeRmFB(sys->fd, buffer->fb_id);
    if (buffer->handle) {
        struct drm_mode_destroy_dumb destroy = { .handle = buffer->handle };
        drmIoctl(sys->fd, DRM_IOCTL_MODE_DESTROY_DUMB, &destroy);
    }
    memset(buffer, 0, sizeof(*buffer));
}

static inline uint8_t Clip8(int value)
{
    if ((unsigned)value <= 255)
        return value;
    return value < 0 ? 0 : 255;
}

#if defined(__SSE2__)
static inline __m128i ConvertComponent2(__m128i first, int first_coefficient,
                                        __m128i second,
                                        int second_coefficient)
{
    const __m128i coefficients = _mm_set1_epi32(
        (uint16_t)first_coefficient |
        (uint32_t)(uint16_t)second_coefficient << 16);
    const __m128i rounding = _mm_set1_epi32(128);
    __m128i low = _mm_madd_epi16(_mm_unpacklo_epi16(first, second),
                                  coefficients);
    __m128i high = _mm_madd_epi16(_mm_unpackhi_epi16(first, second),
                                   coefficients);
    low = _mm_srai_epi32(_mm_add_epi32(low, rounding), 8);
    high = _mm_srai_epi32(_mm_add_epi32(high, rounding), 8);
    return _mm_packs_epi32(low, high);
}

static inline __m128i ConvertGreen(__m128i y, __m128i u, __m128i v,
                                    int u_coefficient, int v_coefficient)
{
    const __m128i y_coefficients = _mm_set1_epi32(298);
    const __m128i uv_coefficients = _mm_set1_epi32(
        (uint16_t)u_coefficient |
        (uint32_t)(uint16_t)v_coefficient << 16);
    const __m128i zero = _mm_setzero_si128();
    const __m128i rounding = _mm_set1_epi32(128);
    __m128i low = _mm_madd_epi16(_mm_unpacklo_epi16(y, zero),
                                  y_coefficients);
    __m128i high = _mm_madd_epi16(_mm_unpackhi_epi16(y, zero),
                                   y_coefficients);
    low = _mm_add_epi32(low, _mm_madd_epi16(
        _mm_unpacklo_epi16(u, v), uv_coefficients));
    high = _mm_add_epi32(high, _mm_madd_epi16(
        _mm_unpackhi_epi16(u, v), uv_coefficients));
    low = _mm_srai_epi32(_mm_add_epi32(low, rounding), 8);
    high = _mm_srai_epi32(_mm_add_epi32(high, rounding), 8);
    return _mm_packs_epi32(low, high);
}
#endif

static void ConvertEye(const picture_t *picture, uint32_t *dst,
                       unsigned dst_pitch, unsigned dst_y,
                       unsigned width, unsigned height, unsigned src_y,
                       video_color_space_t space)
{
    const plane_t *yp = &picture->p[Y_PLANE];
    const plane_t *up = &picture->p[U_PLANE];
    const plane_t *vp = &picture->p[V_PLANE];
    const bool bt709 = space != COLOR_SPACE_BT601;

    for (unsigned y = 0; y < height; ++y) {
        const uint8_t *ys = yp->p_pixels + (src_y + y) * yp->i_pitch;
        const uint8_t *us = up->p_pixels + ((src_y + y) / 2) * up->i_pitch;
        const uint8_t *vs = vp->p_pixels + ((src_y + y) / 2) * vp->i_pitch;
        uint32_t *row = dst + (dst_y + y) * dst_pitch;
        unsigned x = 0;
#if defined(__SSE2__)
        const __m128i zero = _mm_setzero_si128();
        const __m128i chroma_center = _mm_set1_epi16(128);
        const __m128i opaque = _mm_set1_epi8((char)0xff);
        const int rv = bt709 ? 459 : 409;
        const int gu = bt709 ? -55 : -100;
        const int gv = bt709 ? -136 : -208;
        const int bu = bt709 ? 541 : 516;
        for (; x + 8 <= width; x += 8) {
            uint32_t u4, v4;
            memcpy(&u4, us + x / 2, sizeof(u4));
            memcpy(&v4, vs + x / 2, sizeof(v4));

            __m128i luma = _mm_loadl_epi64((const __m128i *)(ys + x));
            luma = _mm_unpacklo_epi8(luma, zero);
            luma = _mm_subs_epu16(luma, _mm_set1_epi16(16));
            __m128i u = _mm_unpacklo_epi8(_mm_cvtsi32_si128(u4), zero);
            __m128i v = _mm_unpacklo_epi8(_mm_cvtsi32_si128(v4), zero);
            u = _mm_sub_epi16(u, chroma_center);
            v = _mm_sub_epi16(v, chroma_center);
            u = _mm_unpacklo_epi16(u, u);
            v = _mm_unpacklo_epi16(v, v);

            __m128i red = ConvertComponent2(luma, 298, v, rv);
            __m128i green = ConvertGreen(luma, u, v, gu, gv);
            __m128i blue = ConvertComponent2(luma, 298, u, bu);
            red = _mm_packus_epi16(red, zero);
            green = _mm_packus_epi16(green, zero);
            blue = _mm_packus_epi16(blue, zero);
            __m128i bg = _mm_unpacklo_epi8(blue, green);
            __m128i ra = _mm_unpacklo_epi8(red, opaque);
            _mm_storeu_si128((__m128i *)(row + x),
                             _mm_unpacklo_epi16(bg, ra));
            _mm_storeu_si128((__m128i *)(row + x + 4),
                             _mm_unpackhi_epi16(bg, ra));
        }
#endif
        for (; x < width; ++x) {
            int c = (int)ys[x] - 16;
            int d = (int)us[x / 2] - 128;
            int e = (int)vs[x / 2] - 128;
            if (c < 0) c = 0;
            int r, g, b;
            if (bt709) {
                r = (298 * c + 459 * e + 128) >> 8;
                g = (298 * c - 55 * d - 136 * e + 128) >> 8;
                b = (298 * c + 541 * d + 128) >> 8;
            } else {
                r = (298 * c + 409 * e + 128) >> 8;
                g = (298 * c - 100 * d - 208 * e + 128) >> 8;
                b = (298 * c + 516 * d + 128) >> 8;
            }
            row[x] = 0xff000000u | ((uint32_t)Clip8(r) << 16) |
                     ((uint32_t)Clip8(g) << 8) | Clip8(b);
        }
    }
}

static void BlendSubpictureEye(const subpicture_t *subpicture, uint32_t *dst,
                               unsigned dst_pitch, unsigned dst_y,
                               unsigned width, unsigned height)
{
    if (!subpicture)
        return;

    const unsigned picture_alpha = subpicture->i_alpha < 0 ? 255
                                 : (unsigned)subpicture->i_alpha;
    for (const subpicture_region_t *region = subpicture->p_region;
         region; region = region->p_next) {
        const picture_t *overlay = region->p_picture;
        if (!overlay || region->fmt.i_chroma != VLC_CODEC_RGBA)
            continue;

        const plane_t *plane = &overlay->p[0];
        const unsigned region_alpha = region->i_alpha < 0 ? 255
                                    : (unsigned)region->i_alpha;
        const int x0 = region->i_x;
        const int y0 = region->i_y;
        const unsigned rw = region->fmt.i_visible_width;
        const unsigned rh = region->fmt.i_visible_height;
        const unsigned x_offset = region->fmt.i_x_offset;
        const unsigned y_offset = region->fmt.i_y_offset;

        for (unsigned sy = 0; sy < rh; ++sy) {
            int dy = y0 + (int)sy;
            if (dy < 0 || (unsigned)dy >= height)
                continue;
            const uint8_t *src = plane->p_pixels +
                (y_offset + sy) * plane->i_pitch + x_offset * 4;
            uint32_t *out = dst + (dst_y + (unsigned)dy) * dst_pitch;

#if defined(__SSE2__)
            /* BD-J uses a full 1920x1080 RGBA surface. Most of its pixels are
             * either completely transparent or opaque; doing two alpha
             * divisions and three blends for every opaque pixel consumed more
             * than one 23.976 Hz frame by itself. Convert four opaque RGBA
             * pixels to DRM XRGB at once and skip four transparent ones. */
            if (picture_alpha == 255 && region_alpha == 255 && x0 >= 0 &&
                (unsigned)x0 + rw <= width) {
                const __m128i zero = _mm_setzero_si128();
                const __m128i alpha255 = _mm_set1_epi32(255);
                const __m128i red_mask = _mm_set1_epi32(0x000000ff);
                const __m128i green_mask = _mm_set1_epi32(0x0000ff00);
                const __m128i blue_mask = _mm_set1_epi32(0x00ff0000);
                const __m128i opaque_mask = _mm_set1_epi32(0xff000000);
                uint32_t *fast_out = out + x0;
                unsigned sx = 0;
                for (; sx + 4 <= rw; sx += 4) {
                    __m128i rgba = _mm_loadu_si128(
                        (const __m128i *)(src + sx * 4));
                    __m128i alpha = _mm_srli_epi32(rgba, 24);
                    if (_mm_movemask_epi8(_mm_cmpeq_epi32(alpha, zero)) ==
                        0xffff)
                        continue;
                    if (_mm_movemask_epi8(
                            _mm_cmpeq_epi32(alpha, alpha255)) == 0xffff) {
                        __m128i xrgb = _mm_or_si128(
                            opaque_mask,
                            _mm_or_si128(
                                _mm_slli_epi32(
                                    _mm_and_si128(rgba, red_mask), 16),
                                _mm_or_si128(
                                    _mm_and_si128(rgba, green_mask),
                                    _mm_srli_epi32(
                                        _mm_and_si128(rgba, blue_mask), 16))));
                        _mm_storeu_si128((__m128i *)(fast_out + sx), xrgb);
                        continue;
                    }
                    for (unsigned i = 0; i < 4; ++i) {
                        const uint8_t *pixel = src + (sx + i) * 4;
                        unsigned a = pixel[3];
                        if (!a)
                            continue;
                        uint32_t background = fast_out[sx + i];
                        unsigned inverse = 255 - a;
                        unsigned red = (pixel[0] * a +
                            ((background >> 16) & 0xff) * inverse + 127) / 255;
                        unsigned green = (pixel[1] * a +
                            ((background >> 8) & 0xff) * inverse + 127) / 255;
                        unsigned blue = (pixel[2] * a +
                            (background & 0xff) * inverse + 127) / 255;
                        fast_out[sx + i] = 0xff000000u | red << 16 |
                                           green << 8 | blue;
                    }
                }
                for (; sx < rw; ++sx) {
                    const uint8_t *pixel = src + sx * 4;
                    unsigned a = pixel[3];
                    if (!a)
                        continue;
                    if (a == 255) {
                        fast_out[sx] = 0xff000000u |
                                       (uint32_t)pixel[0] << 16 |
                                       (uint32_t)pixel[1] << 8 | pixel[2];
                        continue;
                    }
                    uint32_t background = fast_out[sx];
                    unsigned inverse = 255 - a;
                    unsigned red = (pixel[0] * a +
                        ((background >> 16) & 0xff) * inverse + 127) / 255;
                    unsigned green = (pixel[1] * a +
                        ((background >> 8) & 0xff) * inverse + 127) / 255;
                    unsigned blue = (pixel[2] * a +
                        (background & 0xff) * inverse + 127) / 255;
                    fast_out[sx] = 0xff000000u | red << 16 |
                                   green << 8 | blue;
                }
                continue;
            }
#endif
            for (unsigned sx = 0; sx < rw; ++sx, src += 4) {
                int dx = x0 + (int)sx;
                if (dx < 0 || (unsigned)dx >= width)
                    continue;
                unsigned alpha = src[3] * region_alpha / 255;
                alpha = alpha * picture_alpha / 255;
                if (!alpha)
                    continue;

                if (alpha == 255) {
                    out[dx] = 0xff000000u | (uint32_t)src[0] << 16 |
                              (uint32_t)src[1] << 8 | src[2];
                    continue;
                }

                uint32_t background = out[dx];
                unsigned inverse = 255 - alpha;
                unsigned red = (src[0] * alpha +
                                ((background >> 16) & 0xff) * inverse + 127) /
                               255;
                unsigned green = (src[1] * alpha +
                                  ((background >> 8) & 0xff) * inverse + 127) /
                                 255;
                unsigned blue = (src[2] * alpha +
                                 (background & 0xff) * inverse + 127) / 255;
                out[dx] = 0xff000000u | red << 16 | green << 8 | blue;
            }
        }
    }
}

static void PageFlip(int fd, unsigned frame, unsigned sec, unsigned usec,
                     void *opaque)
{
    VLC_UNUSED(fd); VLC_UNUSED(frame); VLC_UNUSED(sec); VLC_UNUSED(usec);
    vout_display_sys_t *sys = opaque;
    sys->front = sys->queued;
    sys->flip_pending = false;
}

static int WaitFlip(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    drmEventContext context = {
        .version = DRM_EVENT_CONTEXT_VERSION,
        .page_flip_handler = PageFlip,
    };
    while (sys->flip_pending) {
        struct pollfd pollfd = { .fd = sys->fd, .events = POLLIN };
        int result = poll(&pollfd, 1, 1000);
        if (result < 0 && errno == EINTR)
            continue;
        if (result <= 0 || drmHandleEvent(sys->fd, &context) != 0)
            return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

static picture_pool_t *Pool(vout_display_t *vd, unsigned count)
{
    vout_display_sys_t *sys = vd->sys;
    if (!sys->pool)
        sys->pool = picture_pool_NewFromFormat(&vd->fmt, count);
    return sys->pool;
}

static int MouseMoved(vlc_object_t *object, const char *name,
                      vlc_value_t old_value, vlc_value_t new_value,
                      void *opaque)
{
    VLC_UNUSED(object); VLC_UNUSED(name); VLC_UNUSED(old_value);
    vout_display_t *vd = opaque;
    vout_display_sys_t *sys = vd->sys;
    vlc_mutex_lock(&sys->cursor_lock);
    sys->cursor_x = VLC_CLIP(new_value.coords.x, 0,
                            (int)sys->eye_width - 1);
    sys->cursor_y = VLC_CLIP(new_value.coords.y, 0,
                            (int)sys->eye_height - 1);
    sys->cursor_visible = true;
    int64_t hide_timeout = var_InheritInteger(vd, "mouse-hide-timeout");
    sys->cursor_until = mdate() + VLC_TICK_FROM_MS(__MAX(hide_timeout, 0));
    sys->controls_until = mdate() + VLC_TICK_FROM_SEC(4);
    vlc_mutex_unlock(&sys->cursor_lock);

    playlist_t *playlist = (playlist_t *)object->obj.parent;
    input_thread_t *input = playlist_CurrentInput(playlist);
    if (input != NULL) {
        int64_t length = var_GetInteger(input, "length");
        int64_t time = var_GetInteger(input, "time");
        vlc_mutex_lock(&sys->cursor_lock);
        sys->controls_position = length > 0 ? (float)time / length : 0.f;
        sys->controls_time = time;
        sys->controls_length = length;
        sys->controls_paused = var_GetInteger(input, "state") == PAUSE_S;
        vlc_mutex_unlock(&sys->cursor_lock);
        vlc_object_release(input);
    }
    return VLC_SUCCESS;
}

static uint32_t BlendXrgb(uint32_t background, uint32_t foreground,
                          unsigned alpha)
{
    unsigned inverse = 255 - alpha;
    unsigned red = (((foreground >> 16) & 0xff) * alpha +
                    ((background >> 16) & 0xff) * inverse + 127) / 255;
    unsigned green = (((foreground >> 8) & 0xff) * alpha +
                      ((background >> 8) & 0xff) * inverse + 127) / 255;
    unsigned blue = ((foreground & 0xff) * alpha +
                     (background & 0xff) * inverse + 127) / 255;
    return 0xff000000u | red << 16 | green << 8 | blue;
}

static void FillCircle(uint32_t *dst, unsigned pitch, unsigned dst_y,
                       unsigned width, unsigned height, int cx, int cy,
                       int radius, uint32_t colour, unsigned alpha)
{
    for (int y = -radius; y <= radius; ++y) {
        int py = cy + y;
        if (py < 0 || py >= (int)height)
            continue;
        for (int x = -radius; x <= radius; ++x) {
            int px = cx + x;
            if (px < 0 || px >= (int)width || x * x + y * y > radius * radius)
                continue;
            uint32_t *pixel = &dst[(dst_y + (unsigned)py) * pitch + px];
            *pixel = BlendXrgb(*pixel, colour, alpha);
        }
    }
}

static void FillRect(uint32_t *dst, unsigned pitch, unsigned dst_y,
                     unsigned width, unsigned height, int x, int y,
                     int rect_width, int rect_height, uint32_t colour,
                     unsigned alpha)
{
    int left = __MAX(x, 0), top = __MAX(y, 0);
    int right = __MIN(x + rect_width, (int)width);
    int bottom = __MIN(y + rect_height, (int)height);
    for (int py = top; py < bottom; ++py)
        for (int px = left; px < right; ++px) {
            uint32_t *pixel = &dst[(dst_y + (unsigned)py) * pitch + px];
            *pixel = BlendXrgb(*pixel, colour, alpha);
    }
}

static const uint8_t *TimeGlyph(char character)
{
    static const uint8_t digits[10][7] = {
        { 0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e },
        { 0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e },
        { 0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f },
        { 0x1e, 0x01, 0x01, 0x0e, 0x01, 0x01, 0x1e },
        { 0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02 },
        { 0x1f, 0x10, 0x10, 0x1e, 0x01, 0x01, 0x1e },
        { 0x0e, 0x10, 0x10, 0x1e, 0x11, 0x11, 0x0e },
        { 0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 },
        { 0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e },
        { 0x0e, 0x11, 0x11, 0x0f, 0x01, 0x01, 0x0e },
    };
    static const uint8_t colon[7] =
        { 0x00, 0x04, 0x04, 0x00, 0x04, 0x04, 0x00 };
    if (character >= '0' && character <= '9')
        return digits[character - '0'];
    if (character == ':')
        return colon;
    return NULL;
}

static int TimeTextWidth(const char *text, int scale)
{
    size_t length = strlen(text);
    return length ? ((int)length * 6 - 1) * scale : 0;
}

static void DrawTimeText(uint32_t *dst, unsigned pitch, unsigned dst_y,
                         unsigned width, unsigned height, int x, int y,
                         int scale, const char *text, uint32_t colour)
{
    for (; *text != '\0'; ++text, x += 6 * scale) {
        const uint8_t *glyph = TimeGlyph(*text);
        if (!glyph)
            continue;
        for (int row = 0; row < 7; ++row)
            for (int column = 0; column < 5; ++column)
                if (glyph[row] & (1u << (4 - column)))
                    FillRect(dst, pitch, dst_y, width, height,
                             x + column * scale, y + row * scale,
                             scale, scale, colour, 255);
    }
}

static void FormatTime(char output[16], int64_t ticks)
{
    int64_t seconds = __MAX(ticks, INT64_C(0)) / CLOCK_FREQ;
    int64_t hours = seconds / 3600;
    int minutes = (int)((seconds / 60) % 60);
    int secs = (int)(seconds % 60);
    if (hours > 0)
        snprintf(output, 16, "%02"PRId64":%02d:%02d",
                 __MIN(hours, INT64_C(99)), minutes, secs);
    else
        snprintf(output, 16, "%02d:%02d", minutes, secs);
}

static void DrawControlsEye(vout_display_sys_t *sys, uint32_t *dst,
                            unsigned pitch, unsigned dst_y)
{
    vlc_mutex_lock(&sys->cursor_lock);
    bool visible = mdate() < sys->controls_until;
    int cursor_x = sys->cursor_x, cursor_y = sys->cursor_y;
    float position = sys->controls_position;
    int64_t time = sys->controls_time;
    int64_t length = sys->controls_length;
    bool paused = sys->controls_paused;
    vlc_mutex_unlock(&sys->cursor_lock);
    if (!visible)
        return;

    const int width = sys->eye_width, height = sys->eye_height;
    const int scale = __MAX(1, height / 720);
    const int radius = 25 * scale;
    const int spacing = 76 * scale;
    const int center_x = width / 2;
    const int center_y = height - 62 * scale;
    const int panel_width = 260 * scale;
    const int panel_height = 70 * scale;
    const int panel_x = center_x - panel_width / 2;
    const int panel_y = center_y - panel_height / 2;

    /* A compact translucent capsule follows the visual language of the
     * native PowerVLC controllers while remaining cheap enough for old GPUs. */
    FillRect(dst, pitch, dst_y, width, height, panel_x + radius, panel_y,
             panel_width - 2 * radius, panel_height, 0x00171a20u, 205);
    FillRect(dst, pitch, dst_y, width, height, panel_x, panel_y + radius,
             panel_width, panel_height - 2 * radius, 0x00171a20u, 205);
    FillCircle(dst, pitch, dst_y, width, height, panel_x + radius,
               center_y, radius, 0x00171a20u, 205);
    FillCircle(dst, pitch, dst_y, width, height,
               panel_x + panel_width - radius, center_y, radius,
               0x00171a20u, 205);

    int centers[3] = { center_x - spacing, center_x, center_x + spacing };
    for (int button = 0; button < 3; ++button) {
        int dx = cursor_x - centers[button], dy = cursor_y - center_y;
        bool hovered = dx * dx + dy * dy <= (radius + 7 * scale) *
                                             (radius + 7 * scale);
        FillCircle(dst, pitch, dst_y, width, height, centers[button], center_y,
                   radius, hovered ? 0x004a90e2u : 0x00343a46u,
                   hovered ? 235 : 210);
    }

    const int icon = 12 * scale;
    /* Back/forward triangles and bars. */
    for (int y = -icon; y <= icon; ++y) {
        int half = icon - abs(y);
        FillRect(dst, pitch, dst_y, width, height,
                 centers[0] - half, center_y + y, half + 1, scale,
                 0x00ffffffu, 255);
        FillRect(dst, pitch, dst_y, width, height,
                 centers[2], center_y + y, half + 1, scale,
                 0x00ffffffu, 255);
    }
    FillRect(dst, pitch, dst_y, width, height, centers[0],
             center_y - icon, 2 * scale, 2 * icon + 1,
             0x00ffffffu, 255);
    FillRect(dst, pitch, dst_y, width, height, centers[2] - 2 * scale,
             center_y - icon, 2 * scale, 2 * icon + 1,
             0x00ffffffu, 255);
    if (paused) {
        for (int y = -icon; y <= icon; ++y) {
            int half = (y + icon) / 2;
            FillRect(dst, pitch, dst_y, width, height, center_x - icon / 2,
                     center_y + y, half + 1, scale, 0x00ffffffu, 255);
        }
    } else {
        FillRect(dst, pitch, dst_y, width, height, center_x - 8 * scale,
                 center_y - icon, 5 * scale, 2 * icon,
                 0x00ffffffu, 255);
        FillRect(dst, pitch, dst_y, width, height, center_x + 3 * scale,
                 center_y - icon, 5 * scale, 2 * icon,
                 0x00ffffffu, 255);
    }

    const int progress_x = width / 20;
    const int progress_width = width - 2 * progress_x;
    const int progress_y = panel_y - 22 * scale;
    position = VLC_CLIP(position, 0.f, 1.f);
    FillRect(dst, pitch, dst_y, width, height, progress_x, progress_y,
             progress_width, 5 * scale, 0x00ffffffu, 90);
    int progress = (int)(position * progress_width);
    FillRect(dst, pitch, dst_y, width, height, progress_x, progress_y,
             progress, 5 * scale, 0x004a90e2u, 255);
    FillCircle(dst, pitch, dst_y, width, height, progress_x + progress,
               progress_y + 2 * scale, 5 * scale, 0x00ffffffu, 255);

    const int text_scale = __MAX(2, height / 540);
    char elapsed_text[16], duration_text[16];
    FormatTime(elapsed_text, time);
    FormatTime(duration_text, length);
    const int text_y = progress_y - 7 * text_scale - 8 * scale;
    DrawTimeText(dst, pitch, dst_y, width, height, progress_x, text_y,
                 text_scale, elapsed_text, 0x00ffffffu);
    DrawTimeText(dst, pitch, dst_y, width, height,
                 progress_x + progress_width -
                     TimeTextWidth(duration_text, text_scale),
                 text_y, text_scale, duration_text, 0x00ffffffu);

    bool progress_hovered = cursor_x >= progress_x &&
                            cursor_x <= progress_x + progress_width &&
                            cursor_y >= progress_y - 14 * scale &&
                            cursor_y <= progress_y + 18 * scale;
    if (progress_hovered && length > 0) {
        float target_position = (float)(cursor_x - progress_x) /
                                progress_width;
        char target_text[16];
        FormatTime(target_text, (int64_t)(target_position * length));
        int target_width = TimeTextWidth(target_text, text_scale);
        int bubble_width = target_width + 18 * scale;
        int bubble_height = 7 * text_scale + 12 * scale;
        int bubble_x = VLC_CLIP(cursor_x - bubble_width / 2, 4 * scale,
                               width - bubble_width - 4 * scale);
        int bubble_y = text_y - bubble_height - 10 * scale;
        FillRect(dst, pitch, dst_y, width, height, bubble_x, bubble_y,
                 bubble_width, bubble_height, 0x00171a20u, 235);
        DrawTimeText(dst, pitch, dst_y, width, height,
                     bubble_x + (bubble_width - target_width) / 2,
                     bubble_y + 6 * scale, text_scale, target_text,
                     0x00ffffffu);
        for (int row = 0; row < 6 * scale; ++row)
            FillRect(dst, pitch, dst_y, width, height,
                     cursor_x - (6 * scale - row),
                     bubble_y + bubble_height + row,
                     2 * (6 * scale - row) + 1, 1,
                     0x00171a20u, 235);
    }
}

static int MouseClicked(vlc_object_t *object, const char *name,
                        vlc_value_t old_value, vlc_value_t new_value,
                        void *opaque)
{
    VLC_UNUSED(name); VLC_UNUSED(old_value);
    vout_display_t *vd = opaque;
    vout_display_sys_t *sys = vd->sys;
    const int width = sys->eye_width, height = sys->eye_height;
    const int scale = __MAX(1, height / 720);
    const int center_y = height - 62 * scale;
    const int center_x = width / 2;
    const int spacing = 76 * scale;
    const int radius = 34 * scale;
    const int progress_y = center_y - 35 * scale - 22 * scale;
    bool consumed = false;

    playlist_t *playlist = (playlist_t *)object->obj.parent;
    input_thread_t *input = playlist_CurrentInput(playlist);
    if (input != NULL && new_value.coords.y >= progress_y - 10 * scale &&
        new_value.coords.y <= progress_y + 15 * scale &&
        new_value.coords.x >= width / 20 &&
        new_value.coords.x <= width - width / 20) {
        float position = (float)(new_value.coords.x - width / 20) /
                         (width - width / 10);
        position = VLC_CLIP(position, 0.f, 1.f);
        vlc_mutex_lock(&sys->cursor_lock);
        sys->controls_position = position;
        sys->controls_time = (int64_t)(position *
                             var_GetInteger(input, "length"));
        vlc_mutex_unlock(&sys->cursor_lock);
        var_SetFloat(input, "position", position);
        consumed = true;
    } else if (input != NULL) {
        for (int button = 0; button < 3; ++button) {
            int cx = center_x + (button - 1) * spacing;
            int dx = new_value.coords.x - cx;
            int dy = new_value.coords.y - center_y;
            if (dx * dx + dy * dy > radius * radius)
                continue;
            if (button == 1) {
                int state = var_GetInteger(input, "state");
                vout_OSDIcon((vout_thread_t *)object, VOUT_SPU_CHANNEL_OSD,
                             state == PAUSE_S ? OSD_PLAY_ICON : OSD_PAUSE_ICON);
                playlist_TogglePause(playlist);
                vlc_mutex_lock(&sys->cursor_lock);
                sys->controls_paused = state != PAUSE_S;
                vlc_mutex_unlock(&sys->cursor_lock);
            } else {
                int64_t time = var_GetInteger(input, "time");
                int64_t length = var_GetInteger(input, "length");
                time += button == 0 ? -10 * CLOCK_FREQ : 10 * CLOCK_FREQ;
                time = VLC_CLIP(time, 0, length);
                vlc_mutex_lock(&sys->cursor_lock);
                sys->controls_time = time;
                sys->controls_length = length;
                sys->controls_position = length > 0 ? (float)time / length
                                                     : 0.f;
                vlc_mutex_unlock(&sys->cursor_lock);
                var_SetInteger(input, "time", time);
            }
            consumed = true;
            break;
        }
    }
    if (input != NULL)
        vlc_object_release(input);
    if (consumed)
        var_SetInteger(object, "kms3d-control-click-until",
                       mdate() + VLC_TICK_FROM_MS(100));
    return VLC_SUCCESS;
}

static void DrawCursorEye(vout_display_sys_t *sys, uint32_t *dst,
                          unsigned pitch, unsigned dst_y)
{
    enum { CURSOR_WIDTH = 24, CURSOR_HEIGHT = 34 };
    vlc_mutex_lock(&sys->cursor_lock);
    int x0 = sys->cursor_x;
    int y0 = sys->cursor_y;
    bool visible = sys->cursor_visible && mdate() < sys->cursor_until;
    vlc_mutex_unlock(&sys->cursor_lock);
    if (!visible)
        return;

    for (int y = 0; y < 27 && y0 + y < (int)sys->eye_height; ++y) {
        int edge = y * 2 / 3;
        for (int x = 0; x <= edge && x < CURSOR_WIDTH &&
                        x0 + x < (int)sys->eye_width; ++x) {
            bool border = x == 0 || x >= edge - 2 || y < 2;
            dst[(dst_y + (unsigned)(y0 + y)) * pitch + x0 + x] =
                border ? 0xff000000u : 0xffffdc00u;
        }
    }
    for (int y = 21; y < CURSOR_HEIGHT &&
                         y0 + y < (int)sys->eye_height; ++y) {
        for (int x = 8; x < 13 && x0 + x < (int)sys->eye_width; ++x) {
            bool border = x == 8 || x == 12 || y == CURSOR_HEIGHT - 1;
            dst[(dst_y + (unsigned)(y0 + y)) * pitch + x0 + x] =
                border ? 0xff000000u : 0xffffdc00u;
        }
    }
}

static void RegisterMouse(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    vout_thread_t *vout = (vout_thread_t *)vd->obj.parent;
    if (vout == NULL)
        return;
    var_AddCallback(vout, "mouse-moved", MouseMoved, vd);
    var_AddCallback(vout, "mouse-clicked", MouseClicked, vd);
    var_Create(vout, "kms3d-control-click-until", VLC_VAR_INTEGER);
    var_SetInteger(vout, "kms3d-control-click-until", 0);
    sys->mouse_callback = true;
}

static void UnregisterMouse(vout_display_t *vd)
{
    vout_display_sys_t *sys = vd->sys;
    vout_thread_t *vout = (vout_thread_t *)vd->obj.parent;
    if (vout == NULL || !sys->mouse_callback)
        return;
    var_DelCallback(vout, "mouse-moved", MouseMoved, vd);
    var_DelCallback(vout, "mouse-clicked", MouseClicked, vd);
    sys->mouse_callback = false;
}

static void Prepare(vout_display_t *vd, picture_t *picture,
                    subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;

    if (subpicture && sys->overlay_debug_count < 4) {
        unsigned regions = 0;
        for (const subpicture_region_t *region = subpicture->p_region;
             region; region = region->p_next) {
            ++regions;
            msg_Info(vd, "overlay region %u: chroma %.4s at %d,%d size %ux%u "
                         "alpha %d/%d picture=%p",
                     regions, (const char *)&region->fmt.i_chroma,
                     region->i_x, region->i_y,
                     region->fmt.i_visible_width,
                     region->fmt.i_visible_height, region->i_alpha,
                     subpicture->i_alpha, (void *)region->p_picture);
        }
        msg_Info(vd, "preparing interactive overlay with %u region(s)",
                 regions);
        ++sys->overlay_debug_count;
    }

    /* Triple buffering leaves one writable buffer while the current scanout
     * and the next page flip are both owned by KMS. With only two buffers this
     * function had to wait for vblank before doing the conversion; one unlucky
     * phase then made every following picture cross VLC's late threshold. */
    unsigned back = 0;
    while (back == sys->front ||
           (sys->flip_pending && back == sys->queued))
        ++back;
    if (unlikely(back >= ARRAY_SIZE(sys->buffers))) {
        sys->prepared_valid = false;
        msg_Err(vd, "no free DRM buffer available for frame preparation");
        return;
    }
    kms_buffer_t *buffer = &sys->buffers[back];
    uint32_t *pixels = (uint32_t *)buffer->map;
    unsigned pitch = buffer->pitch / 4;
    bool right_first = vd->source.multiview_mode ==
                       MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE;
    unsigned top_src = right_first ? sys->eye_height : 0;
    unsigned bottom_src = !sys->stereo_source ? 0
                         : right_first ? 0 : sys->eye_height;

    memset(buffer->map + (uint64_t)sys->eye_height * buffer->pitch, 0,
           (uint64_t)(sys->mode.vtotal - sys->eye_height) * buffer->pitch);
    ConvertEye(picture, pixels, pitch, 0, sys->eye_width, sys->eye_height,
               top_src, vd->source.space);
    BlendSubpictureEye(subpicture, pixels, pitch, 0, sys->eye_width,
                       sys->eye_height);
    DrawControlsEye(sys, pixels, pitch, 0);
    DrawCursorEye(sys, pixels, pitch, 0);
    ConvertEye(picture, pixels, pitch, sys->mode.vtotal, sys->eye_width,
               sys->eye_height, bottom_src, vd->source.space);
    BlendSubpictureEye(subpicture, pixels, pitch, sys->mode.vtotal,
                       sys->eye_width, sys->eye_height);
    DrawControlsEye(sys, pixels, pitch, sys->mode.vtotal);
    DrawCursorEye(sys, pixels, pitch, sys->mode.vtotal);

    sys->prepared = back;
    sys->prepared_valid = true;
    VLC_UNUSED(subpicture);
}

static void Display(vout_display_t *vd, picture_t *picture,
                    subpicture_t *subpicture)
{
    vout_display_sys_t *sys = vd->sys;

    if (sys->prepared_valid) {
        /* Normally the prior event has been pending for almost a full scan by
         * now, so this only consumes the already-ready event. Keeping the wait
         * here guarantees that legacy KMS never receives two outstanding
         * page-flip requests for the same CRTC. */
        if (sys->flip_pending && WaitFlip(vd) != VLC_SUCCESS) {
            sys->flip_pending = false;
            sys->prepared_valid = false;
            msg_Warn(vd, "timed out waiting for the preceding DRM page flip");
            goto out;
        }
        sys->queued = sys->prepared;
        sys->flip_pending = true;
        if (drmModePageFlip(sys->fd, sys->crtc_id,
                            sys->buffers[sys->prepared].fb_id,
                            DRM_MODE_PAGE_FLIP_EVENT, sys) == 0) {
            sys->prepared_valid = false;
        } else {
            sys->flip_pending = false;
            msg_Warn(vd, "DRM page flip failed: %s", vlc_strerror_c(errno));
        }
    }

out:
    picture_Release(picture);
    if (subpicture)
        subpicture_Delete(subpicture);
}

static int Control(vout_display_t *vd, int query, va_list args)
{
    VLC_UNUSED(args);
    if (query == VOUT_DISPLAY_HIDE_MOUSE) {
        vout_display_sys_t *sys = vd->sys;
        vlc_mutex_lock(&sys->cursor_lock);
        sys->cursor_visible = false;
        vlc_mutex_unlock(&sys->cursor_lock);
        return VLC_SUCCESS;
    }
    return VLC_EGENERIC;
}

static int TryDevice(vout_display_t *vd, const char *path,
                     const char *requested_connector)
{
    vout_display_sys_t *sys = vd->sys;
    int fd = vlc_open(path, O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        msg_Warn(vd, "cannot open %s: %s", path, vlc_strerror_c(errno));
        return VLC_EGENERIC;
    }
    if (drmSetClientCap(fd, DRM_CLIENT_CAP_STEREO_3D, 1) != 0) {
        msg_Warn(vd, "%s does not expose the DRM stereo client capability: %s",
                 path, vlc_strerror_c(errno));
        vlc_close(fd);
        return VLC_EGENERIC;
    }
    if (drmSetMaster(fd) != 0) {
        msg_Warn(vd, "cannot become DRM master on %s: %s",
                 path, vlc_strerror_c(errno));
        vlc_close(fd);
        return VLC_EGENERIC;
    }

    drmModeRes *res = drmModeGetResources(fd);
    if (!res) {
        msg_Warn(vd, "cannot enumerate KMS resources on %s: %s",
                 path, vlc_strerror_c(errno));
        drmDropMaster(fd);
        vlc_close(fd);
        return VLC_EGENERIC;
    }
    drmModeConnector *selected = NULL;
    drmModeModeInfo selected_mode = {0};
    int best = -1;
    for (int i = 0; res && i < res->count_connectors; ++i) {
        drmModeConnector *connector = drmModeGetConnector(fd,
                                                           res->connectors[i]);
        if (!connector || connector->connection != DRM_MODE_CONNECTED) {
            drmModeFreeConnector(connector);
            continue;
        }
        char name[32];
        snprintf(name, sizeof(name), "%s-%u",
                 ConnectorTypeName(connector->connector_type),
                 connector->connector_type_id);
        if (requested_connector && *requested_connector &&
            strcmp(requested_connector, name)) {
            drmModeFreeConnector(connector);
            continue;
        }
        int local_best = -1, local_mode = -1;
        for (int m = 0; m < connector->count_modes; ++m) {
            int score = ModeScore(&connector->modes[m], sys->eye_width,
                                  sys->eye_height,
                                  vd->source.i_frame_rate,
                                  vd->source.i_frame_rate_base);
            if (score > local_best) {
                local_best = score;
                local_mode = m;
            }
        }
        msg_Dbg(vd, "%s-%u has %d modes; matching frame-packing score %d",
                ConnectorTypeName(connector->connector_type),
                connector->connector_type_id, connector->count_modes,
                local_best);
        if (local_best > best) {
            drmModeFreeConnector(selected);
            selected = connector;
            connector = NULL;
            selected_mode = selected->modes[local_mode];
            best = local_best;
        }
        drmModeFreeConnector(connector);
    }
    if (!selected) {
        msg_Warn(vd, "%s has no connected output matching %ux%u at %u/%u fps",
                 path, sys->eye_width, sys->eye_height,
                 vd->source.i_frame_rate, vd->source.i_frame_rate_base);
        drmModeFreeResources(res);
        drmDropMaster(fd);
        vlc_close(fd);
        return VLC_EGENERIC;
    }

    sys->fd = fd;
    sys->connector_id = selected->connector_id;
    sys->crtc_id = FindCrtc(fd, res, selected);
    sys->mode = selected_mode;
    drmModeFreeConnector(selected);
    if (!sys->crtc_id) {
        drmModeFreeResources(res);
        drmDropMaster(fd);
        vlc_close(fd);
        sys->fd = -1;
        return VLC_EGENERIC;
    }
    if (SaveCrtcs(vd, res) != VLC_SUCCESS) {
        drmModeFreeResources(res);
        drmDropMaster(fd);
        vlc_close(fd);
        sys->fd = -1;
        return VLC_EGENERIC;
    }
    drmModeFreeResources(res);
    msg_Info(vd, "using %s connector %u at %.3f Hz frame-packing",
             path, sys->connector_id,
             (double)sys->mode.clock * 1000.0 /
             ((double)sys->mode.htotal * sys->mode.vtotal));
    return VLC_SUCCESS;
}

static int Open(vlc_object_t *object)
{
    vout_display_t *vd = (vout_display_t *)object;
    const bool stereo_source =
        vd->source.multiview_mode == MULTIVIEW_STEREO_FRAMEPACKED ||
        vd->source.multiview_mode == MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE;
    if ((!stereo_source && vd->source.multiview_mode != MULTIVIEW_2D) ||
        vd->source.i_chroma != VLC_CODEC_I420 ||
        (stereo_source && vd->source.i_visible_height % 2))
        return VLC_EGENERIC;

    msg_Info(vd, "requesting HDMI frame-packing for %ux%u stereo source "
                  "at %u/%u fps (chroma %.4s, mode %u)",
             vd->source.i_visible_width, vd->source.i_visible_height,
             vd->source.i_frame_rate, vd->source.i_frame_rate_base,
             (const char *)&vd->source.i_chroma, vd->source.multiview_mode);

    const unsigned eye_width = vd->source.i_visible_width;
    const unsigned eye_height = stereo_source
                              ? vd->source.i_visible_height / 2
                              : vd->source.i_visible_height;

    vout_display_sys_t *sys = NULL;
    vlc_mutex_lock(&retained_lock);
    if (retained_sys != NULL && retained_sys->eye_width == eye_width &&
        retained_sys->eye_height == eye_height &&
        ModeScore(&retained_sys->mode, eye_width, eye_height,
                  vd->source.i_frame_rate,
                  vd->source.i_frame_rate_base) >= 0) {
        sys = retained_sys;
        retained_sys = NULL;
    }
    vlc_mutex_unlock(&retained_lock);

    if (sys != NULL) {
        vd->sys = sys;
        sys->stereo_source = stereo_source;
        sys->eye_stride = vd->source.i_width;
        sys->prepared_valid = false;
        sys->overlay_debug_count = 0;
        msg_Info(vd, "reusing active KMS frame-packing session across vout transition");
        goto configured;
    }

    /* A retained mode with incompatible dimensions cannot serve this vout.
     * Dispose of it before acquiring a fresh DRM master. */
    vlc_mutex_lock(&retained_lock);
    vout_display_sys_t *stale = retained_sys;
    retained_sys = NULL;
    vlc_mutex_unlock(&retained_lock);
    if (stale != NULL)
        ReleaseSystem(stale);

    sys = vd->sys = calloc(1, sizeof(*sys));
    if (!sys)
        return VLC_ENOMEM;
    sys->fd = -1;
    sys->tty_fd = -1;
    vlc_mutex_init(&sys->cursor_lock);
    sys->stereo_source = stereo_source;
    sys->eye_width = eye_width;
    sys->eye_height = eye_height;
    sys->eye_stride = vd->source.i_width;
    char *device = var_InheritString(vd, CFG_PREFIX "device");
    char *connector = var_InheritString(vd, CFG_PREFIX "connector");
    int status = VLC_EGENERIC;
    if (device && *device)
        status = TryDevice(vd, device, connector);
    else {
        char path[32];
        for (unsigned card = 0; card < 16 && status != VLC_SUCCESS; ++card) {
            snprintf(path, sizeof(path), "/dev/dri/card%u", card);
            status = TryDevice(vd, path, connector);
        }
    }
    free(device);
    free(connector);
    if (status != VLC_SUCCESS) {
        msg_Err(vd, "no available DRM master with a matching HDMI 3D mode");
        Close(object);
        return VLC_EGENERIC;
    }

    sys->tty_fd = vlc_open("/dev/tty", O_RDWR | O_CLOEXEC);
    if (sys->tty_fd < 0 && isatty(STDIN_FILENO))
        sys->tty_fd = dup(STDIN_FILENO);
    if (sys->tty_fd >= 0) {
        if (ioctl(sys->tty_fd, KDGETMODE, &sys->tty_mode) != 0)
            msg_Warn(vd, "cannot query the framebuffer console mode: %s",
                     vlc_strerror_c(errno));
        else if (sys->tty_mode != KD_GRAPHICS) {
            if (ioctl(sys->tty_fd, KDSETMODE, KD_GRAPHICS) == 0)
                sys->tty_graphics = true;
            else
                msg_Warn(vd, "cannot hide the framebuffer console: %s",
                         vlc_strerror_c(errno));
        }
    } else {
        msg_Dbg(vd, "no virtual terminal available to blank the other outputs");
    }

    if (CreateBuffer(vd, &sys->buffers[0]) != VLC_SUCCESS ||
        CreateBuffer(vd, &sys->buffers[1]) != VLC_SUCCESS ||
        CreateBuffer(vd, &sys->buffers[2]) != VLC_SUCCESS) {
        Close(object);
        return VLC_EGENERIC;
    }

    ConfigureFramePackingBpc(vd);

    /* A compositor leaves the last desktop framebuffer scanning on its other
     * CRTCs after losing DRM master. Disable those CRTCs so laptop panels stay
     * black during dedicated HDMI playback. Every original state is restored
     * below, including mirrored connector sets. */
    for (int i = 0; i < sys->saved_crtc_count; ++i) {
        drmModeCrtc *crtc = sys->saved_crtcs[i].crtc;
        if (crtc->crtc_id != sys->crtc_id && crtc->mode_valid &&
            drmModeSetCrtc(sys->fd, crtc->crtc_id, 0, 0, 0,
                           NULL, 0, NULL) != 0)
            msg_Warn(vd, "cannot blank CRTC %u: %s", crtc->crtc_id,
                     vlc_strerror_c(errno));
    }
    if (drmModeSetCrtc(sys->fd, sys->crtc_id, sys->buffers[0].fb_id,
                       0, 0, &sys->connector_id, 1, &sys->mode) != 0) {
        msg_Err(vd, "cannot enable HDMI frame-packing: %s",
                vlc_strerror_c(errno));
        Close(object);
        return VLC_EGENERIC;
    }

    /* Intel's HDMI audio component binds a running PCM stream to the current
     * transcoder. A legacy KMS modeset can move the connector to another CRTC
     * after ALSA has opened, leaving a healthy-looking stream attached to the
     * old pipe and therefore silent. Reopening only the audio output after the
     * physical modeset rebinds it without dropping DRM master or lighting the
     * laptop panel. Retained KMS-to-KMS vout replacements skip this block. */
    vout_thread_t *vout = (vout_thread_t *)vd->obj.parent;
    playlist_t *playlist = vout != NULL
                         ? (playlist_t *)vout->obj.parent : NULL;
    var_Create(vd->obj.libvlc, "powervlc-kms3d-audio-prime", VLC_VAR_BOOL);
    var_SetBool(vd->obj.libvlc, "powervlc-kms3d-audio-prime", true);
    audio_output_t *aout = playlist != NULL ? playlist_GetAout(playlist) : NULL;
    if (aout != NULL) {
        aout_RestartRequest(aout, AOUT_RESTART_OUTPUT);
        vlc_object_release(aout);
        msg_Dbg(vd, "requested HDMI audio rebind after frame-packing modeset");
    }

configured:
    vd->fmt = vd->source;
    vd->fmt.i_sar_num = 1;
    vd->fmt.i_sar_den = 1;
    /* A legacy DRM page flip is latched on the next vblank. Queue it shortly
     * before the picture PTS so it lands on the intended scan, but begin
     * rendering more than one 23.976 Hz period ahead: Prepare must first wait
     * for the preceding asynchronous flip before rewriting the back buffer. */
    var_Create(vd, "vout-presentation-advance", VLC_VAR_INTEGER);
    var_SetInteger(vd, "vout-presentation-advance", 20000);
    var_Create(vd, "vout-render-advance", VLC_VAR_INTEGER);
    var_SetInteger(vd, "vout-render-advance", 60000);
    /* A userspace legacy-KMS renderer can be briefly late while still
     * sustaining the stream indefinitely. This BD-J menu causes a measured
     * 300-320 ms timestamp discontinuity; dropping after it locks 23.976 Hz
     * playback to every other picture. Keep a finite half-second recovery
     * envelope on the direct KMS display, with six scans as the lower bound
     * for higher-refresh frame-packing modes. */
    const vlc_tick_t scan_period =
        (vlc_tick_t)sys->mode.htotal * sys->mode.vtotal * 1000 /
        sys->mode.clock;
    var_Create(vd, "vout-late-threshold", VLC_VAR_INTEGER);
    var_SetInteger(vd, "vout-late-threshold",
                   __MAX(CLOCK_FREQ / 2, 6 * scan_period + 10000));
    /* The decoded MVC picture contains two stacked eyes, but KMS consumes
     * menus and OSDs in the logical coordinates of one eye.  Prevent the
     * vout core from first enlarging that canvas to the display placement
     * derived from the stacked picture's 2:1 SAR. */
    var_Create(vd, "vout-spu-eye-canvas", VLC_VAR_BOOL);
    var_SetBool(vd, "vout-spu-eye-canvas", true);
    vd->pool = Pool;
    vd->prepare = Prepare;
    vd->display = Display;
    vd->control = Control;
    vd->info.needs_hide_mouse = true;
    vd->info.subpicture_chromas = subpicture_chromas;
    RegisterMouse(vd);
    vout_display_SendEventDisplaySize(vd, sys->eye_width, sys->eye_height);
    WriteTransitionMarker("POWERVLC_KMS3D_ACTIVE", "active");
    return VLC_SUCCESS;
}

static void Close(vlc_object_t *object)
{
    vout_display_t *vd = (vout_display_t *)object;
    vout_display_sys_t *sys = vd->sys;
    if (!sys)
        return;
    UnregisterMouse(vd);
    if (sys->flip_pending)
        WaitFlip(vd);

    vout_thread_t *vout = (vout_thread_t *)vd->obj.parent;
    char *live_module = var_GetString(vd->obj.libvlc,
                                      "powervlc-live-vout");
    if (live_module == NULL || *live_module == '\0') {
        free(live_module);
        live_module = var_InheritString(vd, "vout");
    }
    const bool retain = vout != NULL &&
                        var_GetBool(vout, "stereo3d-vout-reinit") &&
                        live_module != NULL &&
                        !strcmp(live_module, "kms3d");
    free(live_module);
    if (retain) {
        if (sys->pool != NULL) {
            picture_pool_Release(sys->pool);
            sys->pool = NULL;
        }
        sys->prepared_valid = false;
        vlc_mutex_lock(&retained_lock);
        if (retained_sys == NULL) {
            retained_sys = sys;
            vd->sys = NULL;
            vlc_mutex_unlock(&retained_lock);
            msg_Info(vd, "retaining active KMS frame-packing session for replacement vout");
            return;
        }
        vlc_mutex_unlock(&retained_lock);
    }

    ReleaseSystem(sys);
    vd->sys = NULL;
}

static void ReleaseSystem(vout_display_sys_t *sys)
{
    if (sys->fd >= 0) {
        if (sys->max_bpc_changed)
            drmModeObjectSetProperty(sys->fd, sys->connector_id,
                                     DRM_MODE_OBJECT_CONNECTOR,
                                     sys->max_bpc_property_id,
                                     sys->saved_max_bpc);
        for (int i = 0; i < sys->saved_crtc_count; ++i) {
            kms_saved_crtc_t *saved = &sys->saved_crtcs[i];
            drmModeCrtc *crtc = saved->crtc;
            if (crtc->mode_valid)
                drmModeSetCrtc(sys->fd, crtc->crtc_id, crtc->buffer_id,
                               crtc->x, crtc->y, saved->connectors,
                               saved->connector_count, &crtc->mode);
            else
                drmModeSetCrtc(sys->fd, crtc->crtc_id, 0, 0, 0,
                               NULL, 0, NULL);
        }
    }
    if (sys->pool)
        picture_pool_Release(sys->pool);
    if (sys->fd >= 0) {
        DestroyBuffer(sys, &sys->buffers[0]);
        DestroyBuffer(sys, &sys->buffers[1]);
        DestroyBuffer(sys, &sys->buffers[2]);
    }
    FreeSavedCrtcs(sys);
    if (sys->fd >= 0) {
        drmDropMaster(sys->fd);
        vlc_close(sys->fd);
    }
    WriteTransitionMarker("POWERVLC_KMS3D_RELEASED", "released");
    if (sys->tty_fd >= 0) {
        if (sys->tty_graphics)
            ioctl(sys->tty_fd, KDSETMODE, sys->tty_mode);
        vlc_close(sys->tty_fd);
    }
    vlc_mutex_destroy(&sys->cursor_lock);
    free(sys);
}
