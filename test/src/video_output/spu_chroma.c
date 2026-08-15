/*****************************************************************************
 * spu_chroma.c: the core must only offer the blender chromas it can consume
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC
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

/*
 * When a vout_display does not composite subpictures itself (it left
 * info.subpicture_chromas empty), video_output.c passes a NULL chroma list to
 * spu_Render(), which then falls back on its own default lists. Those lists
 * are a PROMISE: "hand me a region in any of these and the blender will take
 * it". SpuRenderRegion() skips its conversion step for any chroma it finds
 * there.
 *
 * The promise was false. The lists named ARGB and BGRA, which the only
 * "video blending" module in the tree accepts as DESTINATIONS but never as
 * SOURCES -- it registers exactly YUVA, RGBA and YUVP. So an unconverted
 * region reached the blender, was refused, and the overlay was dropped,
 * once per picture, with nothing on screen to say so. Blu-ray menus are
 * rendered in exactly that chroma (bluray.c: ARGB_OVERLAY_CHROMA is
 * VLC_CODEC_ARGB on big-endian hosts and VLC_CODEC_BGRA elsewhere), so they
 * silently vanished on every such display.
 *
 * This test drives the real path end to end for a Blu-ray-shaped overlay: put
 * a region in the overlay chroma through spu_Render() with no chroma list,
 * then blend what comes out. Both halves matter -- checking only that
 * spu_Render() returns something would pass even while the overlay is being
 * thrown away downstream.
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_spu.h>
#include <vlc_filter.h>
#include <vlc_picture.h>
#include <vlc_subpicture.h>

#include "../../libvlc/test.h"
#include "../lib/libvlc_internal.h"
#include "../input/common.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

#define OVERLAY_W 64
#define OVERLAY_H 32
#define VIDEO_W   320
#define VIDEO_H   240

/* The chroma libbluray hands us for menus, per host endianness. Testing the
 * one this build will actually see is the point; testing both would pass on a
 * tree that only fixed the other. */
#ifdef WORDS_BIGENDIAN
# define OVERLAY_CHROMA VLC_CODEC_ARGB
#else
# define OVERLAY_CHROMA VLC_CODEC_BGRA
#endif

/* Destinations worth covering: the planar YUV every software decoder puts
 * out, the packed 4:2:2 a hardware decoder can put out (the Crystal HD only
 * emits YUY2), and an RGB one so the *_rgb default list is exercised too. */
static const vlc_fourcc_t dst_chromas[] = {
    VLC_CODEC_I420,
    VLC_CODEC_YUYV,
    VLC_CODEC_RGB32,
};

static void fill_overlay(picture_t *pic)
{
    /* Opaque, and deliberately not black: the check below is "the
     * destination changed", so a transparent or all-zero overlay would let a
     * broken blender pass. */
    for (int y = 0; y < pic->p[0].i_visible_lines; y++) {
        uint8_t *line = pic->p[0].p_pixels + y * pic->p[0].i_pitch;
        for (int x = 0; x < pic->p[0].i_visible_pitch; x += 4) {
            line[x + 0] = 0xC0;
            line[x + 1] = 0x40;
            line[x + 2] = 0xE0;
            line[x + 3] = 0xFF;
        }
    }
}

static subpicture_t *make_overlay_subpicture(vlc_tick_t date)
{
    /* Init first: Setup does not clear the whole struct, so a stack-garbage
     * p_palette would be handed to video_format_Clean below. */
    video_format_t fmt;
    video_format_Init(&fmt, 0);
    video_format_Setup(&fmt, OVERLAY_CHROMA, OVERLAY_W, OVERLAY_H,
                       OVERLAY_W, OVERLAY_H, 1, 1);

    subpicture_region_t *region = subpicture_region_New(&fmt);
    video_format_Clean(&fmt);
    if (region == NULL)
        return NULL;
    fill_overlay(region->p_picture);

    subpicture_t *subpic = subpicture_New(NULL);
    if (subpic == NULL) {
        subpicture_region_Delete(region);
        return NULL;
    }
    subpic->i_original_picture_width  = VIDEO_W;
    subpic->i_original_picture_height = VIDEO_H;
    subpic->b_absolute = true;
    subpic->b_ephemer  = true;
    subpic->i_start    = date;
    subpic->i_stop     = date;
    subpic->p_region   = region;
    return subpic;
}

/* Returns true if the blender actually wrote something into the destination.
 * blend.cpp reports a refusal with msg_Err and simply returns, leaving the
 * picture untouched -- there is no return code to read, so the pixels are the
 * only honest witness. */
static bool blend_touches_destination(vlc_object_t *obj,
                                      const video_format_t *fmt_dst,
                                      subpicture_region_t *region)
{
    picture_t *dst = picture_NewFromFormat(fmt_dst);
    if (dst == NULL)
        return false;

    const uint8_t witness = 0x11;
    for (int i = 0; i < dst->i_planes; i++)
        memset(dst->p[i].p_pixels, witness,
               dst->p[i].i_pitch * dst->p[i].i_lines);

    filter_t *blend = filter_NewBlend(obj, fmt_dst);
    bool touched = false;
    if (blend != NULL) {
        if (filter_ConfigureBlend(blend, fmt_dst->i_visible_width,
                                  fmt_dst->i_visible_height,
                                  &region->fmt) == VLC_SUCCESS
         && filter_Blend(blend, dst, 0, 0, region->p_picture, 255)
                == VLC_SUCCESS) {
            for (int i = 0; i < dst->i_planes && !touched; i++) {
                const plane_t *p = &dst->p[i];
                for (int y = 0; y < p->i_visible_lines && !touched; y++) {
                    const uint8_t *line = p->p_pixels + y * p->i_pitch;
                    for (int x = 0; x < p->i_visible_pitch; x++)
                        if (line[x] != witness) {
                            touched = true;
                            break;
                        }
                }
            }
        }
        filter_DeleteBlend(blend);
    }
    picture_Release(dst);
    return touched;
}

/* Returns 0 on success, 1 on failure. Deliberately NOT assert(): these builds
 * are compiled with NDEBUG, which turns assert() into nothing at all -- the
 * first version of this test printed "blend DID NOTHING" and still exited 0. */
static int test_one_destination(libvlc_int_t *vlc, vlc_fourcc_t dst_chroma)
{
    printf(" destination %4.4s: ", (const char *)&dst_chroma);

    spu_t *spu = spu_Create(vlc, NULL);
    assert(spu != NULL);

    video_format_t fmt_src, fmt_dst;
    video_format_Init(&fmt_src, 0);
    video_format_Init(&fmt_dst, 0);
    video_format_Setup(&fmt_src, VLC_CODEC_I420, VIDEO_W, VIDEO_H,
                       VIDEO_W, VIDEO_H, 1, 1);
    video_format_Setup(&fmt_dst, dst_chroma, VIDEO_W, VIDEO_H,
                       VIDEO_W, VIDEO_H, 1, 1);

    const vlc_tick_t date = VLC_TICK_0 + CLOCK_FREQ;
    subpicture_t *subpic = make_overlay_subpicture(date);
    assert(subpic != NULL);
    spu_PutSubpicture(spu, subpic);

    /* NULL chroma list: exactly what video_output.c passes when the display
     * does not composite subpictures itself. */
    subpicture_t *rendered = spu_Render(spu, NULL, &fmt_dst, &fmt_src,
                                        date, date, false);
    if (rendered == NULL) {
        printf("spu_Render returned NOTHING\n");
        assert(!"spu_Render produced no subpicture");
    }
    if (rendered->p_region == NULL) {
        printf("subpicture came back with no region\n");
        assert(!"rendered subpicture has no region");
    }

    const vlc_fourcc_t out = rendered->p_region->fmt.i_chroma;
    printf("region came out as %4.4s", (const char *)&out);

    /* The part that actually matters to the viewer: an overlay that cannot be
     * blended is an overlay nobody sees. */
    bool touched = blend_touches_destination(VLC_OBJECT(vlc), &fmt_dst,
                                             rendered->p_region);
    printf(", blend %s", touched ? "wrote pixels" : "DID NOTHING");

    /* The regression itself: the region reached the blender still in the
     * overlay chroma, because the default list claimed the blender wanted it. */
    int failures = 0;
    if (out == OVERLAY_CHROMA) {
        printf("\n  FAIL: region left unconverted in %4.4s, which no video "
               "blending module accepts as a source\n", (const char *)&out);
        failures++;
    }
    if (!touched) {
        printf("\n  FAIL: the overlay was silently dropped\n");
        failures++;
    }
    if (failures == 0)
        printf("\n");

    subpicture_Delete(rendered);
    video_format_Clean(&fmt_src);
    video_format_Clean(&fmt_dst);
    spu_Destroy(spu);
    return failures > 0;
}

int main(void)
{
    test_init();

    struct vlc_run_args args;
    vlc_run_args_init(&args);

    libvlc_instance_t *vlc = libvlc_create(&args);
    assert(vlc != NULL);

    printf("blending a %4.4s overlay (the Blu-ray menu chroma) with no "
           "display-provided chroma list:\n", (const char *)&(vlc_fourcc_t){
               OVERLAY_CHROMA });

    int failures = 0;
    for (size_t i = 0; i < ARRAY_SIZE(dst_chromas); i++)
        failures += test_one_destination(vlc->p_libvlc_int, dst_chromas[i]);

    libvlc_release(vlc);
    if (failures > 0)
        printf("%d destination(s) cannot show a Blu-ray menu overlay\n",
               failures);
    return failures > 0 ? 1 : 0;
}
