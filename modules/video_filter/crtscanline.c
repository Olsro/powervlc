/*****************************************************************************
 * crtscanline.c : resolution-aware CRT video filter
 *****************************************************************************
 * Copyright (C) 2026 Authors
 * Copyright (C) 2026 PowerVLC contributors
 * Authors: Jules Lazaro and PowerVLC contributors
 *
 * Based on VLC-CRT-Filter-Effect by Jules Lazaro:
 * https://github.com/julescools/VLC-CRT-Filter-Effect
 * Imported from upstream commit b7d3ad419b1324321e7306faab5807ca11355efe.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser
 * General Public License for more details.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <math.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_filter.h>
#include <vlc_picture.h>
#include <vlc_configuration.h>

#include "filter_picture.h"

#define FILTER_PREFIX "crtscanline-"
#define PARAMETER_REFRESH_FRAMES 8
#define HALATION_THRESHOLD 180

enum phosphor_mask_e
{
    PHOSPHOR_NONE = 0,
    PHOSPHOR_APERTURE_GRILLE,
    PHOSPHOR_SLOT_MASK,
    PHOSPHOR_SHADOW_MASK,
};

static const int phosphor_values[] = {
    PHOSPHOR_NONE,
    PHOSPHOR_APERTURE_GRILLE,
    PHOSPHOR_SLOT_MASK,
    PHOSPHOR_SHADOW_MASK,
};

static const char *const phosphor_texts[] = {
    N_("None (fastest)"),
    N_("Aperture grille"),
    N_("Slot mask"),
    N_("Shadow mask"),
};

#define DARKNESS_TEXT N_("Scanline darkness")
#define DARKNESS_LONGTEXT N_("Scanline intensity at a 1080p reference. " \
    "The effect is reduced automatically for lower-resolution sources.")
#define SPACING_TEXT N_("Scanline spacing")
#define SPACING_LONGTEXT N_("Scanline period in pixels at a 480p reference. " \
    "The period follows the source resolution.")
#define BLEND_TEXT N_("Smooth scanlines")
#define BLEND_LONGTEXT N_("Use a smooth beam profile instead of hard bands.")
#define PHOSPHOR_TEXT N_("Phosphor mask type")
#define PHOSPHOR_LONGTEXT N_("Simulate the luminance structure of an aperture " \
    "grille, slot mask, or shadow mask without tinting subtitles.")
#define MASK_STRENGTH_TEXT N_("Phosphor mask strength")
#define MASK_STRENGTH_LONGTEXT N_("Visibility of the selected phosphor mask.")
#define HALATION_TEXT N_("Halation")
#define HALATION_LONGTEXT N_("Add a small glow around bright picture detail.")
#define DIFFUSION_TEXT N_("Diffusion")
#define DIFFUSION_LONGTEXT N_("Blend adjacent picture samples to reproduce " \
    "the gentle optical softness of a CRT.")
#define RETROARCH_PRESET_TEXT N_("Last RetroArch preset")
#define RETROARCH_PRESET_LONGTEXT N_("Remember the preset selected by the " \
    "CRT Display Controller.")

static int Create(vlc_object_t *);
static void Destroy(vlc_object_t *);
static picture_t *Filter(filter_t *, picture_t *);

vlc_module_begin()
    set_description(N_("CRT display simulation video filter"))
    set_shortname(N_("CRT display"))
    set_help(N_("Resolution-aware scanlines, phosphor masks, halation, and diffusion"))
    set_category(CAT_VIDEO)
    set_subcategory(SUBCAT_VIDEO_VFILTER)
    set_capability("video filter", 0)

    add_integer_with_range(FILTER_PREFIX "darkness", 35, 0, 100,
                           DARKNESS_TEXT, DARKNESS_LONGTEXT, false)
        change_safe()
    add_integer_with_range(FILTER_PREFIX "spacing", 2, 1, 20,
                           SPACING_TEXT, SPACING_LONGTEXT, false)
        change_safe()
    add_bool(FILTER_PREFIX "blend", true, BLEND_TEXT, BLEND_LONGTEXT, false)
        change_safe()
    add_integer(FILTER_PREFIX "phosphor", PHOSPHOR_NONE,
                PHOSPHOR_TEXT, PHOSPHOR_LONGTEXT, false)
        change_integer_list(phosphor_values, phosphor_texts)
        change_safe()
    add_integer_with_range(FILTER_PREFIX "mask-strength", 20, 0, 100,
                           MASK_STRENGTH_TEXT, MASK_STRENGTH_LONGTEXT, false)
        change_safe()
    add_integer_with_range(FILTER_PREFIX "halation", 0, 0, 100,
                           HALATION_TEXT, HALATION_LONGTEXT, false)
        change_safe()
    add_integer_with_range(FILTER_PREFIX "diffusion", 0, 0, 100,
                           DIFFUSION_TEXT, DIFFUSION_LONGTEXT, false)
        change_safe()
    add_string(FILTER_PREFIX "retroarch-preset", "crt-easymode",
               RETROARCH_PRESET_TEXT, RETROARCH_PRESET_LONGTEXT, true)
        change_safe()

    add_shortcut("crtscanline")
    set_callbacks(Create, Destroy)
vlc_module_end()

static const char *const filter_options[] = {
    "darkness", "spacing", "blend", "phosphor", "mask-strength",
    "halation", "diffusion", NULL
};

typedef struct
{
    int darkness;
    int spacing;
    bool blend;
    int phosphor;
    int mask_strength;
    int halation;
    int diffusion;
} crt_parameters_t;

struct filter_sys_t
{
    crt_parameters_t params;
    unsigned refresh_countdown;
    bool gpu_passthrough_only;

    uint16_t *scanline_scale;
    int scanline_height;
    int scanline_darkness;
    int scanline_spacing;
    bool scanline_blend;

    uint16_t *mask_scale;
    int mask_width;
    int mask_height;
    int mask_type;
    int mask_strength;
    int mask_phases;
    int mask_cell;

};

static int ReadInteger(filter_t *filter, const char *name, int minimum,
                       int maximum)
{
    int value = (int)config_GetInt(filter, name);
    return VLC_CLIP(value, minimum, maximum);
}

static void RefreshParameters(filter_t *filter, bool force)
{
    filter_sys_t *sys = filter->p_sys;

    if (!force && sys->refresh_countdown > 0)
    {
        sys->refresh_countdown--;
        return;
    }

    sys->refresh_countdown = PARAMETER_REFRESH_FRAMES - 1;
    sys->params.darkness = ReadInteger(filter, FILTER_PREFIX "darkness", 0, 100);
    sys->params.spacing = ReadInteger(filter, FILTER_PREFIX "spacing", 1, 20);
    sys->params.blend = config_GetInt(filter, FILTER_PREFIX "blend") != 0;
    sys->params.phosphor = ReadInteger(filter, FILTER_PREFIX "phosphor",
                                       PHOSPHOR_NONE, PHOSPHOR_SHADOW_MASK);
    sys->params.mask_strength = ReadInteger(filter,
                                            FILTER_PREFIX "mask-strength", 0, 100);
    sys->params.halation = ReadInteger(filter, FILTER_PREFIX "halation", 0, 100);
    sys->params.diffusion = ReadInteger(filter, FILTER_PREFIX "diffusion", 0, 100);
}

static bool RebuildScanlineTable(filter_sys_t *sys, int height)
{
    const crt_parameters_t *params = &sys->params;

    if (sys->scanline_scale != NULL && sys->scanline_height == height &&
        sys->scanline_darkness == params->darkness &&
        sys->scanline_spacing == params->spacing &&
        sys->scanline_blend == params->blend)
        return true;

    if (height <= 0 || (size_t)height > SIZE_MAX / sizeof(*sys->scanline_scale))
        return false;

    uint16_t *table = realloc(sys->scanline_scale,
                              (size_t)height * sizeof(*table));
    if (table == NULL)
        return false;
    sys->scanline_scale = table;

    double spacing = (double)params->spacing * (double)height / 480.0;
    if (spacing < 1.5)
        spacing = 1.5;

    double height_ratio = (double)height / 1080.0;
    if (height_ratio < 0.15)
        height_ratio = 0.15;
    else if (height_ratio > 1.0)
        height_ratio = 1.0;

    const int effective_darkness =
        (int)((double)params->darkness * height_ratio + 0.5);
    const int dark_scale = 256 - effective_darkness * 256 / 100;

    if (params->blend)
    {
        const double two_pi = 6.28318530717958647692;
        const int middle = (256 + dark_scale) / 2;
        const int range = (256 - dark_scale) / 2;
        int y;
        for (y = 0; y < height; ++y)
            table[y] = (uint16_t)(middle +
                (int)(cos((double)y * two_pi / spacing) * (double)range));
    }
    else
    {
        int period = (int)(spacing + 0.5);
        int y;
        if (period < 2)
            period = 2;
        for (y = 0; y < height; ++y)
            table[y] = (uint16_t)(((y % period) < (period / 2))
                                  ? 256 : dark_scale);
    }

    sys->scanline_height = height;
    sys->scanline_darkness = params->darkness;
    sys->scanline_spacing = params->spacing;
    sys->scanline_blend = params->blend;
    return true;
}

static bool RebuildMaskTable(filter_sys_t *sys, int width, int height)
{
    const crt_parameters_t *params = &sys->params;
    const int phases = params->phosphor == PHOSPHOR_APERTURE_GRILLE ? 1 : 3;

    if (params->phosphor == PHOSPHOR_NONE || params->mask_strength == 0)
        return true;

    if (sys->mask_scale != NULL && sys->mask_width == width &&
        sys->mask_height == height && sys->mask_type == params->phosphor &&
        sys->mask_strength == params->mask_strength)
        return true;

    if (width <= 0 || (size_t)width > SIZE_MAX / (sizeof(*sys->mask_scale) * phases))
        return false;

    uint16_t *table = realloc(sys->mask_scale,
                              (size_t)width * phases * sizeof(*table));
    if (table == NULL)
        return false;
    sys->mask_scale = table;

    int cell = (height + 240) / 480;
    if (cell < 1)
        cell = 1;
    const int dim = 256 - params->mask_strength * 128 / 100;
    const int soft = 256 - params->mask_strength * 48 / 100;
    int phase;

    for (phase = 0; phase < phases; ++phase)
    {
        int x;
        for (x = 0; x < width; ++x)
        {
            const int column = x / cell;
            int scale = 256;

            if (params->phosphor == PHOSPHOR_APERTURE_GRILLE)
                scale = column % 3 == 2 ? dim : 256;
            else if (params->phosphor == PHOSPHOR_SLOT_MASK)
            {
                if ((column + (phase == 2 ? 2 : 0)) % 4 == 3)
                    scale = dim;
                else if (phase == 2)
                    scale = soft;
            }
            else if ((column + phase) % 3 == 2)
                scale = dim;
            else if ((column + phase) % 3 == 1)
                scale = soft;

            table[(size_t)phase * width + x] = (uint16_t)scale;
        }
    }

    sys->mask_width = width;
    sys->mask_height = height;
    sys->mask_type = params->phosphor;
    sys->mask_strength = params->mask_strength;
    sys->mask_phases = phases;
    sys->mask_cell = cell;
    return true;
}

static bool ApplySpatialEffects(filter_t *filter, plane_t *dst,
                                const plane_t *src)
{
    filter_sys_t *sys = filter->p_sys;
    const int width = src->i_visible_pitch;
    const int height = src->i_visible_lines;
    int y;

    if (width <= 0 || height <= 0 || dst->i_visible_pitch != width ||
        dst->i_visible_lines != height)
        return false;

    for (y = 0; y < height; ++y)
    {
        const uint8_t *row = src->p_pixels + (size_t)y * src->i_pitch;
        const uint8_t *above = y > 0 ? row - src->i_pitch : row;
        const uint8_t *below = y + 1 < height ? row + src->i_pitch : row;
        uint8_t *out = dst->p_pixels + (size_t)y * dst->i_pitch;
        int x;

        for (x = 0; x < width; ++x)
        {
            const int centre = row[x];
            const int left = row[x > 0 ? x - 1 : x];
            const int right = row[x + 1 < width ? x + 1 : x];
            const int up = above[x];
            const int down = below[x];
            int value = centre;

            if (sys->params.diffusion > 0)
            {
                const int blurred = (centre * 4 + left + right + up + down + 4) >> 3;
                value = (centre * (100 - sys->params.diffusion) +
                         blurred * sys->params.diffusion + 50) / 100;
            }

            if (sys->params.halation > 0)
            {
                int glow = __MAX(left - HALATION_THRESHOLD, 0) +
                           __MAX(right - HALATION_THRESHOLD, 0) +
                           __MAX(up - HALATION_THRESHOLD, 0) +
                           __MAX(down - HALATION_THRESHOLD, 0);
                value += (glow * sys->params.halation + 200) / 400;
                if (value > 255)
                    value = 255;
            }
            out[x] = (uint8_t)value;
        }
    }
    return true;
}

static void ApplyScanlinesAndMask(filter_sys_t *sys, plane_t *plane)
{
    const int width = plane->i_visible_pitch;
    const int height = plane->i_visible_lines;
    const bool use_mask = sys->params.phosphor != PHOSPHOR_NONE &&
                          sys->params.mask_strength > 0 &&
                          sys->mask_scale != NULL;
    int y;

    for (y = 0; y < height; ++y)
    {
        uint8_t *pixels = plane->p_pixels + (size_t)y * plane->i_pitch;
        const int row_scale = sys->params.darkness > 0
                            ? sys->scanline_scale[y] : 256;
        int x;

        if (!use_mask)
        {
            if (row_scale == 256)
                continue;
            for (x = 0; x < width; ++x)
                pixels[x] = (uint8_t)(((unsigned)pixels[x] * row_scale + 128) >> 8);
            continue;
        }

        const int logical_row = y / sys->mask_cell;
        const int phase = logical_row % sys->mask_phases;
        const uint16_t *mask = sys->mask_scale + (size_t)phase * width;
        for (x = 0; x < width; ++x)
        {
            const int scale = (row_scale * mask[x] + 128) >> 8;
            if (scale != 256)
                pixels[x] = (uint8_t)(((unsigned)pixels[x] * scale + 128) >> 8);
        }
    }
}

static int Create(vlc_object_t *object)
{
    filter_t *filter = (filter_t *)object;

    /* Old configurations may still name this CPU filter while the exact GPU
     * renderer is enabled. Rejecting it makes the filter chain recursively
     * search for a hardware-to-I420 converter before the controller gets a
     * chance to clean the saved chain. Accept a format-neutral passthrough for
     * that one migration case; choosing a CPU preset removes and recreates the
     * filter with its normal planar-YUV requirements. */
    if (var_InheritBool(filter, "crt-retroarch-enabled")) {
        filter_sys_t *sys = calloc(1, sizeof(*sys));
        if (sys == NULL)
            return VLC_ENOMEM;
        sys->gpu_passthrough_only = true;
        filter->p_sys = sys;
        filter->pf_video_filter = Filter;
        msg_Dbg(filter, "CRT CPU filter bypassed while RetroArch GPU is active");
        return VLC_SUCCESS;
    }

    if (filter->fmt_in.video.i_chroma != filter->fmt_out.video.i_chroma)
    {
        msg_Err(filter, "input and output chromas do not match");
        return VLC_EGENERIC;
    }

    switch (filter->fmt_in.video.i_chroma)
    {
        CASE_PLANAR_YUV
            break;
        default:
            msg_Dbg(filter, "unsupported chroma (%4.4s), need 8-bit planar YUV",
                    (char *)&filter->fmt_in.video.i_chroma);
            return VLC_EGENERIC;
    }

    filter_sys_t *sys = calloc(1, sizeof(*sys));
    if (sys == NULL)
        return VLC_ENOMEM;
    filter->p_sys = sys;

    config_ChainParse(filter, FILTER_PREFIX, filter_options, filter->p_cfg);
    RefreshParameters(filter, true);
    filter->pf_video_filter = Filter;
    msg_Info(filter, "CRT display filter initialized");
    return VLC_SUCCESS;
}

static void Destroy(vlc_object_t *object)
{
    filter_t *filter = (filter_t *)object;
    filter_sys_t *sys = filter->p_sys;
    free(sys->scanline_scale);
    free(sys->mask_scale);
    free(sys);
}

static picture_t *Filter(filter_t *filter, picture_t *picture)
{
    filter_sys_t *sys = filter->p_sys;
    picture_t *output;
    plane_t *luma;

    if (picture == NULL)
        return NULL;

    if (sys->gpu_passthrough_only ||
        var_InheritBool(filter, "crt-retroarch-enabled"))
        return picture;

    RefreshParameters(filter, false);
    if (sys->params.darkness == 0 &&
        (sys->params.phosphor == PHOSPHOR_NONE || sys->params.mask_strength == 0) &&
        sys->params.halation == 0 && sys->params.diffusion == 0)
        return picture;

    /* Decoder pictures can remain reference frames or be presented again
     * while paused.  Never modify them in place: doing so feeds the CRT mask
     * back into predictive decoding and reapplies darkness on redisplay. */
    output = filter_NewPicture(filter);
    if (output == NULL)
    {
        picture_Release(picture);
        return NULL;
    }
    picture_CopyProperties(output, picture);
    for (int plane = 0; plane < picture->i_planes; ++plane)
        if (plane != Y_PLANE)
            plane_CopyPixels(&output->p[plane], &picture->p[plane]);

    luma = &output->p[Y_PLANE];
    if ((sys->params.halation == 0 && sys->params.diffusion == 0) ||
        !ApplySpatialEffects(filter, luma, &picture->p[Y_PLANE]))
        plane_CopyPixels(luma, &picture->p[Y_PLANE]);

    if ((sys->params.darkness == 0 ||
         RebuildScanlineTable(sys, luma->i_visible_lines)) &&
        RebuildMaskTable(sys, luma->i_visible_pitch, luma->i_visible_lines))
        ApplyScanlinesAndMask(sys, luma);

    picture_Release(picture);
    return output;
}
