/*****************************************************************************
 * vout_wrapper.c: "vout display" -> "video output" wrapper
 *****************************************************************************
 * Copyright (C) 2009 Laurent Aimar
 * $Id$
 *
 * Authors: Laurent Aimar <fenrir _AT_ videolan _DOT_ org>
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
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_vout_wrapper.h>
#include <vlc_vout.h>
#include <assert.h>
#ifdef __APPLE__
# include <sys/sysctl.h>   /* hw.memsize, for the RAM-scaled cache pool cap */
#endif
#include "vout_internal.h"
#include "display.h"

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
#ifdef _WIN32
static int  Forward(vlc_object_t *, char const *,
                    vlc_value_t, vlc_value_t, void *);
#endif

/*****************************************************************************
 *
 *****************************************************************************/
int vout_OpenWrapper(vout_thread_t *vout,
                     const char *splitter_name, const vout_display_state_t *state)
{
    vout_thread_sys_t *sys = vout->p;
    msg_Dbg(vout, "Opening vout display wrapper");

    /* The Linux KMS 3D launcher changes display backends without replacing
     * the input (and therefore without resetting a BD-J virtual machine).
     * Use its process-wide live selection when present. The private variable
     * is never created during ordinary playback, so all other platforms and
     * launch paths retain the normal $vout inheritance rules. */
    char *live_module = var_GetString(vout->obj.libvlc,
                                      "powervlc-live-vout");
    const char *display_module = live_module != NULL && *live_module != '\0'
                               ? live_module : "$vout";

    /* */
    sys->display.title = var_InheritString(vout, "video-title");

    /* */
    const vlc_tick_t double_click_timeout = 300000;
    const vlc_tick_t hide_timeout = var_CreateGetInteger(vout, "mouse-hide-timeout") * 1000;

    if (splitter_name) {
        sys->display.vd = vout_NewSplitter(vout, &vout->p->original, state,
                                           display_module, splitter_name,
                                           double_click_timeout, hide_timeout);
    } else {
        sys->display.vd = vout_NewDisplay(vout, &vout->p->original, state,
                                          display_module,
                                          double_click_timeout, hide_timeout);
    }
    free(live_module);
    if (!sys->display.vd) {
        free(sys->display.title);
        return VLC_EGENERIC;
    }

    /* */
#ifdef _WIN32
    var_Create(vout, "video-wallpaper", VLC_VAR_BOOL|VLC_VAR_DOINHERIT);
    var_AddCallback(vout, "video-wallpaper", Forward, NULL);
#endif

    /* */
    sys->decoder_pool = NULL;

    return VLC_SUCCESS;
}

/*****************************************************************************
 *
 *****************************************************************************/
void vout_CloseWrapper(vout_thread_t *vout, vout_display_state_t *state)
{
    vout_thread_sys_t *sys = vout->p;

#ifdef _WIN32
    var_DelCallback(vout, "video-wallpaper", Forward, NULL);
#endif
    sys->decoder_pool = NULL; /* FIXME remove */

    vout_DeleteDisplay(sys->display.vd, state);
    free(sys->display.title);
}

/*****************************************************************************
 *
 *****************************************************************************/
/* Minimum number of display picture */
#define DISPLAY_PICTURE_COUNT (1)

/* Look-ahead decode cache (video-cache-mb): how many extra pictures the
 * MB/seconds budget asks for, sized against the decoder's output format.
 * Only used for the indirect-rendering pool below, which lives in plain
 * system memory (picture_pool_NewFromFormat) -- unlike the direct-rendering
 * display pool, growing it costs RAM only, no AGP-aperture pressure, so no
 * hard picture ceiling here beyond the budget itself. (The DR/planar case
 * is grown by the display module instead, see Pool() in macosx_gl1.m and
 * its 48-picture AGP ceiling.) *pi_pic_bytes returns the measured picture
 * size (0 when unknown) for the caller's own byte accounting. */
static unsigned VoutCacheExtraPictures(vout_display_t *vd,
                                       size_t *pi_pic_bytes)
{
    *pi_pic_bytes = 0;

    int64_t mb = var_InheritInteger(vd, "video-cache-mb");
    if (mb <= 0)
        return 0;

    /* Real byte size of one pool picture (all planes, alignment padding
     * ignored -- fine for sizing a budget). */
    picture_t *probe = picture_NewFromFormat(&vd->source);
    if (probe == NULL)
        return 0;
    size_t pic_bytes = 0;
    for (int i = 0; i < probe->i_planes; i++)
        pic_bytes += (size_t)probe->p[i].i_pitch * probe->p[i].i_lines;
    picture_Release(probe);
    if (pic_bytes == 0)
        return 0;
    *pi_pic_bytes = pic_bytes;

    size_t target = (size_t)mb * 1024 * 1024 / pic_bytes;

    int64_t max_s = var_InheritInteger(vd, "video-cache-max-seconds");
    if (max_s > 0 && vd->source.i_frame_rate > 0
     && vd->source.i_frame_rate_base > 0)
    {
        size_t seconds_target = (size_t)((double)vd->source.i_frame_rate
                              / vd->source.i_frame_rate_base * max_s);
        if (seconds_target < target)
            target = seconds_target;
    }
    return target > 4096 ? 4096 : (unsigned)target;
}

static void NoDrInit(vout_thread_t *vout)
{
    vout_thread_sys_t *sys = vout->p;

    if (sys->display.use_dr)
        sys->display_pool = vout_display_Pool(sys->display.vd, 3);
    else
        sys->display_pool = NULL;
}

int vout_InitWrapper(vout_thread_t *vout)
{
    vout_thread_sys_t *sys = vout->p;
    vout_display_t *vd = sys->display.vd;

    sys->display.use_dr = !vout_IsDisplayFiltered(vd);
    const bool allow_dr = !vd->info.has_pictures_invalid && !vd->info.is_slow && sys->display.use_dr;
    const unsigned private_picture  = 4; /* XXX 3 for filter, 1 for SPU */
    const unsigned decoder_picture  = 1 + sys->dpb_size;
    const unsigned kept_picture     = 1; /* last displayed picture */
    const unsigned reserved_picture = DISPLAY_PICTURE_COUNT +
                                      private_picture +
                                      kept_picture;
    const unsigned display_pool_size = allow_dr ? __MAX(VOUT_MAX_PICTURES,
                                                        reserved_picture + decoder_picture) : 3;
    picture_pool_t *display_pool = vout_display_Pool(vd, display_pool_size);
    if (display_pool == NULL)
        return VLC_EGENERIC;

#ifndef NDEBUG
    if ( picture_pool_GetSize(display_pool) < display_pool_size )
        msg_Warn(vout, "Not enough display buffers in the pool, requested %d got %d",
                 display_pool_size, picture_pool_GetSize(display_pool));
#endif
    /* Worth a line in a normal build: on the old Macs this port targets the
     * pool is the single largest allocation in the process (a 1080p picture is
     * 3.1 MB), and how many it holds follows from the decoder's DPB request in
     * a way that is otherwise invisible. */
    if (allow_dr)
        msg_Dbg(vout, "display pool: %d pictures (dpb %u + reserved %u, floor %u)",
                picture_pool_GetSize(display_pool), decoder_picture,
                reserved_picture, (unsigned)VOUT_MAX_PICTURES);

    if (allow_dr &&
        picture_pool_GetSize(display_pool) >= reserved_picture + decoder_picture) {
        /* Look-ahead decode cache headroom: whatever the (possibly
         * display-grown, see macosx_gl1.m) pool holds beyond the DPB and
         * the reserved pictures may safely pile up in the decoder fifo.
         * decoder_picture (what the codec actually asked for) is the
         * right reserve, NOT the inflated dpb_size below. */
        unsigned pool_size = picture_pool_GetSize(display_pool);
        if (pool_size > reserved_picture + decoder_picture)
            vout->p->cache_headroom =
                pool_size - reserved_picture - decoder_picture;
        sys->dpb_size     = picture_pool_GetSize(display_pool) - reserved_picture;
        sys->decoder_pool = display_pool;
        sys->display_pool = display_pool;
    } else if (!sys->decoder_pool) {
        /* Indirect rendering: this pool is plain system memory, grow it by
         * the video-cache-mb budget so decoded pictures can accumulate. */
        const unsigned base_count = __MAX(VOUT_MAX_PICTURES,
                                          reserved_picture + decoder_picture
                                          - DISPLAY_PICTURE_COUNT);
        size_t pic_bytes;
        unsigned extra = VoutCacheExtraPictures(vd, &pic_bytes);
        unsigned total_count = base_count + extra;
        if (extra > 0)
            /* Size the pool so its headroom holds the WHOLE cache target
             * plus the decode-side reserve: the cache is bounded by this
             * pool (there is no staging fallback anymore), and the target
             * is clamped to headroom - VIDEO_CACHE_POOL_MARGIN (see
             * DecoderVideoCacheTarget), with headroom = pool - reserved -
             * 2. So the requested budget is reached without the clamp
             * biting: margin = reserved + 2 + the pool margin (10,
             * duplicated from decoder.c's VIDEO_CACHE_POOL_MARGIN) + slack
             * for the decoder's own per-picture size re-measurements. */
            total_count += reserved_picture + 2 + 10 + 6;
        /* Bound the EAGER allocation (the pool allocates its pictures up
         * front, and it is now the hard ceiling on cache depth -- there is
         * no staging fallback to grow past it). The pool becomes resident
         * as the cache fills, so bound it to a fraction of installed RAM:
         * ~1/3 keeps the 1 GB Minis near their tested-safe ~320 MB (round
         * 61) while letting a bigger-memory PPC machine (a 2 GB G5, say)
         * cache proportionally deeper for free. Clamp the top end too --
         * these builds run 32-bit even on the G5, so a huge machine's 1/3
         * would strain the address space, and a cache that deep buys
         * nothing (the decoder cannot fill it and the demux pacing is
         * tuned for moderate depths). Fall back to the fixed 320 MB when
         * the RAM size cannot be read. Past this the cache simply caps
         * here; the trade is deliberate -- a shallower cache with the odd
         * dropout beats the per-frame memcpy staging used to pay to grow
         * it (see VIDEO_CACHE_POOL_MARGIN). */
        size_t EAGER_BYTES_CAP = (size_t)320 << 20;
#ifdef __APPLE__
        {
            uint64_t physmem = 0;
            size_t len = sizeof(physmem);
            if (sysctlbyname("hw.memsize", &physmem, &len, NULL, 0) == 0
             && physmem > 0)
            {
                uint64_t cap = physmem / 3;
                if (cap > ((uint64_t)768 << 20))
                    cap = (uint64_t)768 << 20;
                EAGER_BYTES_CAP = (size_t)cap;
            }
        }
#endif
        if (pic_bytes > 0
         && (size_t)total_count * pic_bytes > EAGER_BYTES_CAP)
            total_count = (unsigned)(EAGER_BYTES_CAP / pic_bytes);
        /* picture_pool bitmap ceiling (POOL_MAX = 1024, see picture_pool.c)
         * -- a bigger pool fails to create; stay just under it. */
        if (total_count > 1000)
            total_count = 1000;
        if (total_count < base_count)
            total_count = base_count;
        sys->decoder_pool =
            picture_pool_NewFromFormat(&vd->source, total_count);
        if (!sys->decoder_pool)
            return VLC_EGENERIC;
        unsigned pool_size = picture_pool_GetSize(sys->decoder_pool);
        /* +2: one picture in flight in the decoder, one safety */
        if (pool_size > reserved_picture + 2)
            vout->p->cache_headroom = pool_size - reserved_picture - 2;
        if (allow_dr) {
            msg_Warn(vout, "Not enough direct buffers, using system memory");
            sys->dpb_size = 0;
        } else {
            sys->dpb_size = picture_pool_GetSize(sys->decoder_pool) - reserved_picture;
        }
        NoDrInit(vout);
    }
    sys->private_pool = picture_pool_Reserve(sys->decoder_pool, private_picture);
    if (!sys->private_pool)
    {
        if (sys->decoder_pool != sys->display_pool)
            picture_pool_Release(sys->decoder_pool);
        sys->display_pool = sys->decoder_pool = NULL;
        return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

/*****************************************************************************
 *
 *****************************************************************************/
void vout_EndWrapper(vout_thread_t *vout)
{
    vout_thread_sys_t *sys = vout->p;

    assert(vout->p->decoder_pool && vout->p->private_pool);

    picture_pool_Release(sys->private_pool);

    if (sys->decoder_pool != sys->display_pool)
        picture_pool_Release(sys->decoder_pool);
}

/*****************************************************************************
 *
 *****************************************************************************/
void vout_ManageWrapper(vout_thread_t *vout)
{
    vout_thread_sys_t *sys = vout->p;
    vout_display_t *vd = sys->display.vd;

    bool reset_display_pool = vout_AreDisplayPicturesInvalid(vd);
    reset_display_pool |= vout_ManageDisplay(vd, !sys->display.use_dr || reset_display_pool);

    if (reset_display_pool) {
        sys->display.use_dr = !vout_IsDisplayFiltered(vd);
        NoDrInit(vout);
    }
}

#ifdef _WIN32
static int Forward(vlc_object_t *object, char const *var,
                   vlc_value_t oldval, vlc_value_t newval, void *data)
{
    vout_thread_t *vout = (vout_thread_t*)object;

    VLC_UNUSED(oldval);
    VLC_UNUSED(data);
    return var_Set(vout->p->display.vd, var, newval);
}
#endif
