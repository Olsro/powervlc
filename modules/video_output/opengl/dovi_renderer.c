/*****************************************************************************
 * dovi_renderer.c: libplacebo Dolby Vision renderer for VLC 3 OpenGL outputs
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include <math.h>
#include <stdlib.h>
#include <string.h>

#ifdef __linux__
# include <dirent.h>
# include <stdio.h>
#endif

#include <vlc_common.h>
#include <vlc_fourcc.h>

#include <libplacebo/config.h>
#include <libplacebo/log.h>
#include <libplacebo/opengl.h>
#include <libplacebo/renderer.h>
#include <libplacebo/utils/upload.h>

#include "dovi_renderer.h"

struct vlc_dovi_renderer
{
    vlc_gl_t *gl;
    video_format_t format;
    picture_pool_t *pool;

    pl_log log;
    pl_opengl opengl;
    pl_swapchain swapchain;
    pl_renderer renderer;

    pl_tex base_tex[4];
    pl_tex enhancement_tex[4];
    struct pl_frame image;
    struct pl_frame enhancement;
    struct pl_dovi_metadata dovi;

    struct pl_overlay *overlays;
    struct pl_overlay_part *overlay_parts;
    pl_tex *overlay_tex;
    unsigned overlay_capacity;
#ifdef __linux__
    unsigned overlay_count;
#endif

    unsigned drawable_width;
    unsigned drawable_height;
    unsigned framebuffer;
    int viewport_x;
    int viewport_y;
    unsigned viewport_width;
    unsigned viewport_height;
    bool prepared;
    bool reported_fel;
    bool reported_metadata;
    bool reported_output;
#ifdef __linux__
    bool native_dovi;
#endif
    float target_peak;
};

#define DOVI_PICTURE_MAX 128

#ifdef __linux__
#define DOVI_DEFAULT_PEAK 1000.f

static float PqCodeToNits(float pq)
{
    const double m1 = 2610.0 / 16384.0;
    const double m2 = 2523.0 / 32.0;
    const double c1 = 3424.0 / 4096.0;
    const double c2 = 2413.0 / 128.0;
    const double c3 = 2392.0 / 128.0;
    const double p = pow(pq, 1.0 / m2);
    const double numerator = fmax(p - c1, 0.0);
    const double denominator = c2 - c3 * p;
    return denominator > 0.0
         ? (float)(10000.0 * pow(numerator / denominator, 1.0 / m1)) : 0.f;
}

/* CTA-861 encodes Dolby's VSVDB as extended data block 0x01 followed by
 * Dolby's little-endian OUI (00-D0-46). Version 2 stores MaxL in the upper
 * five bits of its third payload byte. */
static float DoviV2PeakFromEdid(const unsigned char *edid, size_t size)
{
    if (size < 128 || memcmp(edid, "\x00\xff\xff\xff\xff\xff\xff\x00", 8))
        return 0.f;

    const unsigned blocks = __MIN((unsigned)edid[126],
                                  (unsigned)(size / 128 - 1));
    for (unsigned b = 1; b <= blocks; ++b)
    {
        const unsigned char *cta = edid + b * 128;
        if (cta[0] != 0x02)
            continue;
        const unsigned end = cta[2] >= 4 && cta[2] <= 127 ? cta[2] : 127;
        for (unsigned pos = 4; pos < end;)
        {
            const unsigned length = cta[pos] & 0x1f;
            if (!length || pos + 1 + length > end)
                break;
            if ((cta[pos] >> 5) == 7 && length >= 7 &&
                cta[pos + 1] == 0x01 && cta[pos + 2] == 0x46 &&
                cta[pos + 3] == 0xd0 && cta[pos + 4] == 0x00)
            {
                const unsigned char *payload = &cta[pos + 5];
                const unsigned payload_length = length - 4;
                if (payload_length >= 3 && (payload[0] >> 5) == 2)
                {
                    const unsigned max_luminance_code = payload[2] >> 3;
                    const float pq = (2055.f + 65.f * max_luminance_code) /
                                     (2055.f + 31.f * 65.f);
                    return PqCodeToNits(pq);
                }
            }
            pos += 1 + length;
        }
    }
    return 0.f;
}

static float LinuxDoviPeakFromEdid(void)
{
    DIR *dir = opendir("/sys/class/drm");
    if (!dir)
        return 0.f;

    float peak = 0.f;
    struct dirent *entry;
    while (!peak && (entry = readdir(dir)))
    {
        if (strncmp(entry->d_name, "card", 4) ||
            !strstr(entry->d_name, "-HDMI-A-"))
            continue;

        char path[512];
        if (snprintf(path, sizeof(path), "/sys/class/drm/%s/status",
                     entry->d_name) >= (int)sizeof(path))
            continue;
        FILE *file = fopen(path, "rb");
        char status[16] = {0};
        if (!file)
            continue;
        const size_t status_size = fread(status, 1, sizeof(status) - 1, file);
        fclose(file);
        if (status_size < 9 || strncmp(status, "connected", 9))
            continue;

        if (snprintf(path, sizeof(path), "/sys/class/drm/%s/edid",
                     entry->d_name) >= (int)sizeof(path))
            continue;
        file = fopen(path, "rb");
        if (!file)
            continue;
        unsigned char edid[2048];
        const size_t edid_size = fread(edid, 1, sizeof(edid), file);
        fclose(file);
        peak = DoviV2PeakFromEdid(edid, edid_size);
    }
    closedir(dir);
    return peak;
}
#endif

static void Log(void *opaque, enum pl_log_level level, const char *message)
{
    vlc_gl_t *gl = opaque;
    switch (level)
    {
        case PL_LOG_FATAL:
        case PL_LOG_ERR:  msg_Err(gl, "%s", message); break;
        case PL_LOG_WARN: msg_Warn(gl, "%s", message); break;
        case PL_LOG_INFO: msg_Info(gl, "%s", message); break;
        default:          msg_Dbg(gl, "%s", message); break;
    }
}

static pl_voidfunc_t DoviGetProcAddress(void *opaque, const char *name)
{
    return (pl_voidfunc_t)vlc_gl_GetProcAddress(opaque, name);
}

static void DoviSwapBuffers(void *opaque)
{
    vlc_gl_Swap(opaque);
}

static struct pl_color_space ColorSpace(const video_format_t *fmt)
{
    static const enum pl_color_primaries primaries[COLOR_PRIMARIES_MAX + 1] = {
        [COLOR_PRIMARIES_UNDEF]     = PL_COLOR_PRIM_UNKNOWN,
        [COLOR_PRIMARIES_BT601_525] = PL_COLOR_PRIM_BT_601_525,
        [COLOR_PRIMARIES_BT601_625] = PL_COLOR_PRIM_BT_601_625,
        [COLOR_PRIMARIES_BT709]     = PL_COLOR_PRIM_BT_709,
        [COLOR_PRIMARIES_BT2020]    = PL_COLOR_PRIM_BT_2020,
        [COLOR_PRIMARIES_DCI_P3]    = PL_COLOR_PRIM_DCI_P3,
        [COLOR_PRIMARIES_FCC1953]   = PL_COLOR_PRIM_BT_470M,
    };
    static const enum pl_color_transfer transfers[TRANSFER_FUNC_MAX + 1] = {
        [TRANSFER_FUNC_UNDEF]        = PL_COLOR_TRC_UNKNOWN,
        [TRANSFER_FUNC_LINEAR]       = PL_COLOR_TRC_LINEAR,
        [TRANSFER_FUNC_SRGB]         = PL_COLOR_TRC_SRGB,
        [TRANSFER_FUNC_BT470_BG]     = PL_COLOR_TRC_BT_1886,
        [TRANSFER_FUNC_BT470_M]      = PL_COLOR_TRC_BT_1886,
        [TRANSFER_FUNC_BT709]        = PL_COLOR_TRC_BT_1886,
        [TRANSFER_FUNC_SMPTE_ST2084] = PL_COLOR_TRC_PQ,
        [TRANSFER_FUNC_SMPTE_240]    = PL_COLOR_TRC_BT_1886,
        [TRANSFER_FUNC_HLG]          = PL_COLOR_TRC_HLG,
    };

    struct pl_color_space color = {
        .primaries = primaries[fmt->primaries],
        .transfer = transfers[fmt->transfer],
        .hdr = {
            .prim = {
                .green = { fmt->mastering.primaries[0] / 50000.f,
                           fmt->mastering.primaries[1] / 50000.f },
                .blue  = { fmt->mastering.primaries[2] / 50000.f,
                           fmt->mastering.primaries[3] / 50000.f },
                .red   = { fmt->mastering.primaries[4] / 50000.f,
                           fmt->mastering.primaries[5] / 50000.f },
                .white = { fmt->mastering.white_point[0] / 50000.f,
                           fmt->mastering.white_point[1] / 50000.f },
            },
            .max_luma = fmt->mastering.max_luminance / 10000.f,
            .min_luma = fmt->mastering.min_luminance / 10000.f,
            .max_cll = fmt->lighting.MaxCLL,
            .max_fall = fmt->lighting.MaxFALL,
        },
    };
    return color;
}

static enum pl_color_system ColorSystem(const video_format_t *fmt)
{
    if (!vlc_fourcc_IsYUV(fmt->i_chroma))
        return PL_COLOR_SYSTEM_RGB;
    switch (fmt->space)
    {
        case COLOR_SPACE_BT601:  return PL_COLOR_SYSTEM_BT_601;
        case COLOR_SPACE_BT2020: return PL_COLOR_SYSTEM_BT_2020_NC;
        default:                 return PL_COLOR_SYSTEM_BT_709;
    }
}

static struct pl_color_repr ColorRepr(const video_format_t *fmt,
                                      const vlc_chroma_description_t *desc)
{
    const int sample_depth = desc ? desc->pixel_size * 8 : 8;
    const int color_depth = desc && desc->pixel_bits
                          ? (int)desc->pixel_bits : sample_depth;
    return (struct pl_color_repr) {
        .sys = ColorSystem(fmt),
        .levels = fmt->b_color_range_full ? PL_COLOR_LEVELS_PC
                                           : PL_COLOR_LEVELS_TV,
        .alpha = PL_ALPHA_NONE,
        .bits = {
            .sample_depth = sample_depth,
            .color_depth = color_depth,
            .bit_shift = 0,
        },
    };
}

static enum pl_chroma_location ChromaLocation(video_chroma_location_t loc)
{
    switch (loc)
    {
        case CHROMA_LOCATION_LEFT:          return PL_CHROMA_LEFT;
        case CHROMA_LOCATION_CENTER:        return PL_CHROMA_CENTER;
        case CHROMA_LOCATION_TOP_LEFT:      return PL_CHROMA_TOP_LEFT;
        case CHROMA_LOCATION_TOP_CENTER:    return PL_CHROMA_TOP_CENTER;
        case CHROMA_LOCATION_BOTTOM_LEFT:   return PL_CHROMA_BOTTOM_LEFT;
        case CHROMA_LOCATION_BOTTOM_CENTER: return PL_CHROMA_BOTTOM_CENTER;
        default:                            return PL_CHROMA_UNKNOWN;
    }
}

static void MapOrientation(struct pl_frame *frame, video_orientation_t orientation)
{
#define SWAP_FLOAT(a, b) do { float temporary = (a); (a) = (b); (b) = temporary; } while (0)
    switch (orientation)
    {
        case ORIENT_HFLIPPED:
            SWAP_FLOAT(frame->crop.x0, frame->crop.x1);
            break;
        case ORIENT_VFLIPPED:
            SWAP_FLOAT(frame->crop.y0, frame->crop.y1);
            break;
        case ORIENT_ROTATED_90:
            frame->rotation = PL_ROTATION_90;
            break;
        case ORIENT_ROTATED_180:
            frame->rotation = PL_ROTATION_180;
            break;
        case ORIENT_ROTATED_270:
            frame->rotation = PL_ROTATION_270;
            break;
        case ORIENT_TRANSPOSED:
            frame->rotation = PL_ROTATION_90;
            SWAP_FLOAT(frame->crop.y0, frame->crop.y1);
            break;
        case ORIENT_ANTI_TRANSPOSED:
            frame->rotation = PL_ROTATION_90;
            SWAP_FLOAT(frame->crop.x0, frame->crop.x1);
            break;
        default:
            break;
    }
#undef SWAP_FLOAT
}

static bool PackedRGBA(vlc_fourcc_t chroma, struct pl_plane_data *data,
                       const picture_t *pic)
{
    if (chroma != VLC_CODEC_RGBA && chroma != VLC_CODEC_BGRA)
        return false;
    *data = (struct pl_plane_data) {
        .type = PL_FMT_UNORM,
        .width = pic->format.i_visible_width,
        .height = pic->format.i_visible_height,
        .component_size = { 8, 8, 8, 8 },
        .component_map = { chroma == VLC_CODEC_BGRA ? 2 : 0, 1,
                           chroma == VLC_CODEC_BGRA ? 0 : 2, 3 },
        .pixel_stride = 4,
        .row_stride = pic->p[0].i_pitch,
        .pixels = pic->p[0].p_pixels +
                  pic->format.i_y_offset * pic->p[0].i_pitch +
                  pic->format.i_x_offset * 4,
    };
    return true;
}

/* Map the software formats produced by FFmpeg's HEVC decoder. Dolby Vision
 * Profile 7 BL and EL are planar 4:2:0 10-bit in all currently authored UHD
 * discs, but accepting the other planar depths keeps profile 8 and converted
 * samples on the same path. */
static int PlaneData(const picture_t *pic, struct pl_plane_data data[4])
{
    const vlc_chroma_description_t *desc =
        vlc_fourcc_GetChromaDescription(pic->format.i_chroma);
    if (!desc || desc->plane_count == 0 || desc->plane_count != (unsigned)pic->i_planes)
        return 0;

    if (desc->plane_count == 1 && PackedRGBA(pic->format.i_chroma, &data[0], pic))
        return 1;

    if (desc->plane_count != 3 || !vlc_fourcc_IsYUV(pic->format.i_chroma))
        return 0;

    for (unsigned i = 0; i < desc->plane_count; ++i)
    {
        const unsigned w_num = desc->p[i].w.num;
        const unsigned w_den = desc->p[i].w.den;
        const unsigned h_num = desc->p[i].h.num;
        const unsigned h_den = desc->p[i].h.den;
        const unsigned x = pic->format.i_x_offset * w_num / w_den;
        const unsigned y = pic->format.i_y_offset * h_num / h_den;
        data[i] = (struct pl_plane_data) {
            .type = PL_FMT_UNORM,
            .width = (pic->format.i_visible_width * w_num + w_den - 1) / w_den,
            .height = (pic->format.i_visible_height * h_num + h_den - 1) / h_den,
            .component_size = { (int)desc->pixel_size * 8 },
            .component_map = { (int)i },
            .pixel_stride = desc->pixel_size,
            .row_stride = pic->p[i].i_pitch,
            .pixels = pic->p[i].p_pixels + y * pic->p[i].i_pitch +
                      x * desc->pixel_size,
        };
    }

    if (pic->format.i_chroma == VLC_CODEC_YV12)
    {
        data[1].component_map[0] = 2;
        data[2].component_map[0] = 1;
    }
    return desc->plane_count;
}

static bool UploadFrame(vlc_dovi_renderer_t *sys, const picture_t *pic,
                        struct pl_frame *frame, pl_tex textures[4])
{
    struct pl_plane_data data[4] = {{0}};
    const int planes = PlaneData(pic, data);
    if (!planes)
        return false;

    const vlc_chroma_description_t *desc =
        vlc_fourcc_GetChromaDescription(pic->format.i_chroma);
    *frame = (struct pl_frame) {
        .num_planes = planes,
        .color = ColorSpace(&pic->format),
        .repr = ColorRepr(&pic->format, desc),
        .crop = { 0, 0, pic->format.i_visible_width,
                         pic->format.i_visible_height },
        .pixel_aspect_ratio = pic->format.i_sar_den
            ? (float)pic->format.i_sar_num / pic->format.i_sar_den : 1.f,
    };

    for (int i = 0; i < planes; ++i)
    {
        if (!pl_upload_plane(sys->opengl->gpu, &frame->planes[i],
                             &textures[i], &data[i]))
            return false;
    }
    pl_frame_set_chroma_location(frame, ChromaLocation(pic->format.chroma_location));
    return true;
}

static bool NLQIsTrivial(const vlc_video_dovi_metadata_t *src)
{
    const uint64_t unity = 1ULL << src->coef_log2_denom;
    for (unsigned c = 0; c < 3; ++c)
        if (src->nlq[c].offset != 0 || src->nlq[c].vdr_in_max != unity ||
            src->nlq[c].deadzone_slope != 0 ||
            src->nlq[c].deadzone_threshold != 0)
            return false;
    return true;
}

static void MapDovi(struct pl_frame *frame, struct pl_dovi_metadata *dst,
                    const vlc_video_dovi_metadata_t *src)
{
    memset(dst, 0, sizeof(*dst));
    memcpy(dst->nonlinear_offset, src->nonlinear_offset,
           sizeof(dst->nonlinear_offset));
    memcpy(dst->nonlinear.m, src->nonlinear_matrix, sizeof(dst->nonlinear.m));
    memcpy(dst->linear.m, src->linear_matrix, sizeof(dst->linear.m));

    const double coefficient_scale = 1.0 / (1ULL << src->coef_log2_denom);
    for (unsigned c = 0; c < 3; ++c)
    {
        const struct vlc_dovi_reshape_t *in = &src->curves[c];
        struct pl_reshape_data *out = &dst->comp[c];
        out->num_pivots = in->num_pivots;
        const float pivot_scale = 1.f / ((1U << src->bl_bit_depth) - 1U);
        for (unsigned i = 0; i < in->num_pivots; ++i)
            out->pivots[i] = in->pivots[i] * pivot_scale;
        for (unsigned i = 0; i + 1 < in->num_pivots; ++i)
        {
            out->method[i] = in->mapping[i];
            if (in->mapping[i] == VLC_DOVI_RESHAPE_POLYNOMIAL)
            {
                for (unsigned k = 0; k < 3; ++k)
                    out->poly_coeffs[i][k] = k <= in->polynomial_order[i]
                        ? in->polynomial_coefficients[i][k] * coefficient_scale
                        : 0.f;
            }
            else
            {
                out->mmr_order[i] = in->mmr_order[i];
                out->mmr_constant[i] = in->mmr_constant[i] * coefficient_scale;
                for (unsigned j = 0; j < in->mmr_order[i]; ++j)
                    for (unsigned k = 0; k < 7; ++k)
                        out->mmr_coeffs[i][j][k] =
                            in->mmr_coefficients[i][j][k] * coefficient_scale;
            }
        }
    }

    dst->nlq_active = !src->residual_disabled &&
                      src->nlq_method == VLC_DOVI_NLQ_LINEAR_DZ &&
                      !NLQIsTrivial(src);
    if (dst->nlq_active)
    {
        const double el_max = (1ULL << src->el_bit_depth) - 1ULL;
        for (unsigned c = 0; c < 3; ++c)
        {
            const double slope = src->nlq[c].deadzone_slope;
            const double threshold = src->nlq[c].deadzone_threshold;
            dst->nlq[c].offset = src->nlq[c].offset / el_max;
            dst->nlq[c].deadzone_slope =
                el_max * coefficient_scale * slope;
            dst->nlq[c].deadzone_threshold =
                coefficient_scale * (threshold - 0.5 * slope);
        }
    }

    frame->repr.sys = PL_COLOR_SYSTEM_DOLBYVISION;
    frame->repr.levels = src->bl_video_full_range ? PL_COLOR_LEVELS_PC
                                                   : PL_COLOR_LEVELS_TV;
    frame->repr.bits.color_depth = src->bl_bit_depth;
    frame->repr.dovi = dst;
    frame->color.primaries = PL_COLOR_PRIM_BT_2020;
    frame->color.transfer = PL_COLOR_TRC_PQ;
    const float pq_scale = 1.f / 4095.f;
    frame->color.hdr.min_luma = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS,
                                               src->source_min_pq * pq_scale);
    frame->color.hdr.max_luma = pl_hdr_rescale(PL_HDR_PQ, PL_HDR_NITS,
                                               src->source_max_pq * pq_scale);
    if (src->has_level1)
    {
        /* Dolby Vision level 1 carries PQ-domain CIE-Y statistics. Keep them
         * in that domain: libplacebo uses these dynamic values directly for
         * peak detection and tone mapping. */
        frame->color.hdr.max_pq_y = src->level1_max_pq * pq_scale;
        frame->color.hdr.avg_pq_y = src->level1_avg_pq * pq_scale;
    }
}

static bool EnsureOverlayCapacity(vlc_dovi_renderer_t *sys, unsigned count)
{
    if (count <= sys->overlay_capacity)
        return true;
    struct pl_overlay *overlays = calloc(count, sizeof(*overlays));
    struct pl_overlay_part *parts = calloc(count, sizeof(*parts));
    pl_tex *textures = calloc(count, sizeof(*textures));
    if (!overlays || !parts || !textures)
    {
        free(overlays);
        free(parts);
        free(textures);
        return false;
    }

    if (sys->overlay_capacity)
    {
        memcpy(overlays, sys->overlays,
               sys->overlay_capacity * sizeof(*overlays));
        memcpy(parts, sys->overlay_parts,
               sys->overlay_capacity * sizeof(*parts));
        memcpy(textures, sys->overlay_tex,
               sys->overlay_capacity * sizeof(*textures));
    }
    free(sys->overlays);
    free(sys->overlay_parts);
    free(sys->overlay_tex);
    sys->overlays = overlays;
    sys->overlay_parts = parts;
    sys->overlay_tex = textures;
    sys->overlay_capacity = count;
    return true;
}

static void PrepareOverlays(vlc_dovi_renderer_t *sys, subpicture_t *subpicture)
{
    sys->image.num_overlays = 0;
    sys->image.overlays = NULL;
#ifdef __linux__
    sys->overlay_count = 0;
#endif
    if (!subpicture)
        return;

    unsigned count = 0;
    for (subpicture_region_t *r = subpicture->p_region; r; r = r->p_next)
        ++count;
    if (!EnsureOverlayCapacity(sys, count))
        return;

#ifdef __linux__
    const unsigned canvas_width = subpicture->i_original_picture_width;
    const unsigned canvas_height = subpicture->i_original_picture_height;
    const float scale_x = canvas_width
                        ? (float)sys->viewport_width / canvas_width : 1.f;
    const float scale_y = canvas_height
                        ? (float)sys->viewport_height / canvas_height : 1.f;
#endif

    unsigned i = 0;
    for (subpicture_region_t *r = subpicture->p_region; r; r = r->p_next)
    {
        struct pl_plane_data data;
        if (!r->p_picture || !PackedRGBA(r->p_picture->format.i_chroma,
                                         &data, r->p_picture) ||
            !pl_upload_plane(sys->opengl->gpu, NULL, &sys->overlay_tex[i], &data))
            continue;

        sys->overlay_parts[i] = (struct pl_overlay_part) {
            .src = { 0, 0, r->fmt.i_visible_width, r->fmt.i_visible_height },
#ifdef __linux__
            .dst = { r->i_x * scale_x, r->i_y * scale_y,
                     (r->i_x + r->fmt.i_visible_width) * scale_x,
                     (r->i_y + r->fmt.i_visible_height) * scale_y },
#else
            .dst = { r->i_x, r->i_y,
                     r->i_x + r->fmt.i_visible_width,
                     r->i_y + r->fmt.i_visible_height },
#endif
        };
        sys->overlays[i] = (struct pl_overlay) {
            .tex = sys->overlay_tex[i],
            .mode = PL_OVERLAY_NORMAL,
#ifdef __linux__
            .coords = PL_OVERLAY_COORDS_DST_CROP,
#else
            .coords = PL_OVERLAY_COORDS_SRC_FRAME,
#endif
            .repr = {
                .sys = PL_COLOR_SYSTEM_RGB,
                .levels = PL_COLOR_LEVELS_PC,
                .alpha = PL_ALPHA_INDEPENDENT,
            },
            .color = {
                .primaries = PL_COLOR_PRIM_BT_709,
                .transfer = PL_COLOR_TRC_SRGB,
            },
            .parts = &sys->overlay_parts[i],
            .num_parts = 1,
        };
        ++i;
    }
#ifdef __linux__
    sys->overlay_count = i;
#else
    sys->image.overlays = sys->overlays;
    sys->image.num_overlays = i;
#endif
}

vlc_dovi_renderer_t *vlc_dovi_renderer_Create(vlc_gl_t *gl,
                                               const video_format_t *format)
{
    vlc_dovi_renderer_t *sys = calloc(1, sizeof(*sys));
    if (!sys)
        return NULL;
    sys->gl = gl;
    sys->format = *format;
    sys->viewport_width = format->i_visible_width;
    sys->viewport_height = format->i_visible_height;
    sys->target_peak = PL_COLOR_SDR_WHITE;
#ifdef __linux__
    sys->native_dovi = var_InheritBool(gl, "gl-dovi-hdmi");
    const int configured_peak = var_InheritInteger(gl, "gl-dovi-peak");
    if (sys->native_dovi)
    {
        sys->target_peak = configured_peak > 0
                         ? configured_peak : DOVI_DEFAULT_PEAK;
        if (configured_peak == 0)
        {
            const float edid_peak = LinuxDoviPeakFromEdid();
            if (isfinite(edid_peak) && edid_peak >= 80.f && edid_peak <= 10000.f)
                sys->target_peak = edid_peak;
        }
    }
#endif

    sys->log = pl_log_create(PL_API_VER, pl_log_params(
        .log_cb = Log,
        .log_priv = gl,
        .log_level = var_InheritInteger(gl, "verbose") >= 3
                   ? PL_LOG_DEBUG : PL_LOG_INFO
    ));
    sys->opengl = pl_opengl_create(sys->log, pl_opengl_params(
        .get_proc_addr_ex = DoviGetProcAddress,
        .proc_ctx = gl,
        .allow_software = false,
        .debug = var_InheritInteger(gl, "verbose") >= 4
    ));
    if (!sys->opengl)
        goto error;

    sys->swapchain = pl_opengl_create_swapchain(sys->opengl,
        pl_opengl_swapchain_params(
            .swap_buffers = DoviSwapBuffers,
            .priv = gl,
            .max_swapchain_depth = 2
        ));
    if (!sys->swapchain)
        goto error;
    sys->renderer = pl_renderer_create(sys->log, sys->opengl->gpu);
    if (!sys->renderer)
        goto error;

    msg_Info(gl, "Dolby Vision/HDR renderer: libplacebo %s (profile %u%s)",
             PL_VERSION, format->dovi.profile,
             format->dovi.el_present ? ", enhancement layer" : "");
    return sys;

error:
    vlc_dovi_renderer_Delete(sys);
    return NULL;
}

void vlc_dovi_renderer_Delete(vlc_dovi_renderer_t *sys)
{
    if (!sys)
        return;
    if (sys->pool)
        picture_pool_Release(sys->pool);
    if (sys->opengl)
    {
        pl_gpu gpu = sys->opengl->gpu;
        for (unsigned i = 0; i < 4; ++i)
        {
            pl_tex_destroy(gpu, &sys->base_tex[i]);
            pl_tex_destroy(gpu, &sys->enhancement_tex[i]);
        }
        for (unsigned i = 0; i < sys->overlay_capacity; ++i)
            pl_tex_destroy(gpu, &sys->overlay_tex[i]);
    }
    free(sys->overlays);
    free(sys->overlay_parts);
    free(sys->overlay_tex);
    pl_renderer_destroy(&sys->renderer);
    pl_swapchain_destroy(&sys->swapchain);
    pl_opengl_destroy(&sys->opengl);
    pl_log_destroy(&sys->log);
    free(sys);
}

picture_pool_t *vlc_dovi_renderer_GetPool(vlc_dovi_renderer_t *sys,
                                           unsigned count)
{
    if (!sys->pool)
        sys->pool = picture_pool_NewFromFormat(&sys->format,
                    __MIN(count, DOVI_PICTURE_MAX));
    return sys->pool;
}

int vlc_dovi_renderer_Prepare(vlc_dovi_renderer_t *sys, picture_t *picture,
                              subpicture_t *subpicture)
{
    if (!UploadFrame(sys, picture, &sys->image, sys->base_tex))
    {
        msg_Err(sys->gl, "cannot upload Dolby Vision base layer (%4.4s)",
                (const char *)&picture->format.i_chroma);
        sys->prepared = false;
        return VLC_EGENERIC;
    }
    MapOrientation(&sys->image, picture->format.orientation);

    if (picture->p_dovi)
    {
        MapDovi(&sys->image, &sys->dovi, picture->p_dovi);
        if (!sys->reported_metadata)
        {
            msg_Info(sys->gl, "Dolby Vision dynamic metadata active (BL %u-bit, residual %s)",
                     picture->p_dovi->bl_bit_depth,
                     picture->p_dovi->residual_disabled ? "disabled" : "enabled");
            sys->reported_metadata = true;
        }
    }

    sys->image.enhancement_layer = NULL;
    if (picture->p_enhancement_layer && picture->p_dovi &&
        !picture->p_dovi->residual_disabled &&
        UploadFrame(sys, picture->p_enhancement_layer, &sys->enhancement,
                    sys->enhancement_tex))
    {
        sys->enhancement.repr.bits.color_depth = picture->p_dovi->el_bit_depth;
        sys->image.enhancement_layer = &sys->enhancement;
        if (!sys->reported_fel)
        {
            msg_Info(sys->gl, "Dolby Vision FEL: composing decoded enhancement-layer residual");
            sys->reported_fel = true;
        }
    }

    PrepareOverlays(sys, subpicture);
    sys->prepared = true;
    return VLC_SUCCESS;
}

int vlc_dovi_renderer_Display(vlc_dovi_renderer_t *sys)
{
    if (!sys->prepared || !sys->drawable_width || !sys->drawable_height)
        return VLC_EGENERIC;

    struct pl_swapchain_frame swapframe;
    if (!pl_swapchain_start_frame(sys->swapchain, &swapframe))
        return VLC_EGENERIC;

    struct pl_frame target;
    pl_frame_from_swapchain(&target, &swapframe);
    /* Match the sRGB tag of color-managed SDR surfaces, rather than the
     * swapchain's generic monitor gamma. Float surfaces are tagged linear. */
    target.color = pl_color_space_srgb;
    const int target_y = (int)sys->drawable_height -
                         (sys->viewport_y + (int)sys->viewport_height);
    target.crop = (pl_rect2df) {
        sys->viewport_x,
        target_y,
        sys->viewport_x + (int)sys->viewport_width,
        target_y + (int)sys->viewport_height,
    };

#ifdef __linux__
    target.overlays = sys->overlays;
    target.num_overlays = sys->overlay_count;
    pl_tex_clear(sys->opengl->gpu, swapframe.fbo,
                 (float[4]) { 0.f, 0.f, 0.f, 1.f });

    if (sys->native_dovi)
    {
        target.color.primaries = PL_COLOR_PRIM_BT_2020;
        target.color.transfer = PL_COLOR_TRC_PQ;
        target.color.hdr.min_luma = 0.f;
        target.color.hdr.max_luma = sys->target_peak;
        if (!sys->reported_output)
        {
            msg_Info(sys->gl, "Dolby Vision output: native BT.2020/PQ, %.0f-nit target",
                     sys->target_peak);
            sys->reported_output = true;
        }
    }
    else
#endif
    /* A floating-point AppKit OpenGL surface represents linear EDR values.
     * Preserve HDR highlights there; an ordinary UNORM surface retains the
     * swapchain's SDR colorspace and libplacebo tone-maps safely. */
    if (swapframe.fbo->params.format->type == PL_FMT_FLOAT)
    {
        target.color.primaries = PL_COLOR_PRIM_BT_709;
        target.color.transfer = PL_COLOR_TRC_LINEAR;
        target.color.hdr.min_luma = 0.f;
        target.color.hdr.max_luma = sys->target_peak;
        if (!sys->reported_output)
        {
            msg_Info(sys->gl, "Dolby Vision/HDR output: floating-point EDR, %.0f-nit target",
                     sys->target_peak);
            sys->reported_output = true;
        }
    }
    else if (!sys->reported_output)
    {
        msg_Info(sys->gl, "Dolby Vision/HDR output: integer SDR framebuffer; tone mapping is active");
        sys->reported_output = true;
    }

    bool ok = pl_render_image(sys->renderer, &sys->image, &target,
                              &pl_render_default_params);
    if (!ok)
        msg_Err(sys->gl, "libplacebo failed to render Dolby Vision frame");
    if (!pl_swapchain_submit_frame(sys->swapchain))
        ok = false;
    if (ok)
        pl_swapchain_swap_buffers(sys->swapchain);
    return ok ? VLC_SUCCESS : VLC_EGENERIC;
}

void vlc_dovi_renderer_SetDrawableSize(vlc_dovi_renderer_t *sys,
                                       unsigned width, unsigned height)
{
    if (!width || !height ||
        (sys->drawable_width == width && sys->drawable_height == height))
        return;
    int w = width, h = height;
    if (pl_swapchain_resize(sys->swapchain, &w, &h))
    {
        sys->drawable_width = w;
        sys->drawable_height = h;
        if (!sys->viewport_width || !sys->viewport_height)
        {
            sys->viewport_width = w;
            sys->viewport_height = h;
        }
    }
}

void vlc_dovi_renderer_SetFramebuffer(vlc_dovi_renderer_t *sys, unsigned fbo)
{
    if (sys->framebuffer == fbo)
        return;
    sys->framebuffer = fbo;
    const struct pl_opengl_framebuffer fb = { .id = fbo };
    pl_opengl_swapchain_update_fb(sys->swapchain, &fb);
    sys->drawable_width = sys->drawable_height = 0;
}

void vlc_dovi_renderer_SetDisplayHeadroom(vlc_dovi_renderer_t *sys,
                                          float headroom)
{
    if (!isfinite(headroom) || headroom < 1.f)
        headroom = 1.f;
    const float target_peak = headroom * PL_COLOR_SDR_WHITE;
    if (fabsf(sys->target_peak - target_peak) < 0.5f)
        return;
    sys->target_peak = target_peak;
    sys->reported_output = false;
}

void vlc_dovi_renderer_SetViewport(vlc_dovi_renderer_t *sys, int x, int y,
                                   unsigned width, unsigned height)
{
    sys->viewport_x = x;
    sys->viewport_y = y;
    sys->viewport_width = width;
    sys->viewport_height = height;
}
