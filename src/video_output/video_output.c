/*****************************************************************************
 * video_output.c : video output thread
 *
 * This module describes the programming interface for video output threads.
 * It includes functions allowing to open a new thread, send pictures to a
 * thread, and destroy a previously oppened video output thread.
 *****************************************************************************
 * Copyright (C) 2000-2007 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Vincent Seguin <seguin@via.ecp.fr>
 *          Gildas Bazin <gbazin@videolan.org>
 *          Laurent Aimar <fenrir _AT_ videolan _DOT_ org>
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

#include <stdlib.h>                                                /* free() */
#include <stdio.h>
#include <string.h>
#include <assert.h>

#include <vlc_vout.h>

#include <vlc_filter.h>
#include <vlc_spu.h>
#include <vlc_vout_osd.h>
#include <vlc_image.h>
#include <vlc_plugin.h>

#include <libvlc.h>
#include "vout_internal.h"
#include "interlacing.h"
#include "display.h"
#include "window.h"
#include "../misc/variables.h"

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
static void *Thread(void *);
static void VoutDestructor(vlc_object_t *);
static void ThreadApplyCrop(vout_thread_t *);
static void ThreadUpdateCropAuto(vout_thread_t *, picture_t *);

/* Maximum delay between 2 displayed pictures.
 * XXX it is needed for now but should be removed in the long term.
 */
#define VOUT_REDISPLAY_DELAY (INT64_C(80000))

/**
 * Late pictures having a delay higher than this value are thrashed.
 */
#define VOUT_DISPLAY_LATE_THRESHOLD (INT64_C(20000))

/* Better be in advance when awakening than late... */
#define VOUT_MWAIT_TOLERANCE (INT64_C(4000))

/* Opt-in, allocation-free render phase telemetry.  Keep this state local to
 * the vout thread so diagnosing an expensive subtitle/menu renderer does not
 * alter vout_thread_sys_t's layout (plugins include that private header in
 * this branch). */
typedef struct
{
    unsigned count;
    vlc_tick_t filter;
    vlc_tick_t spu;
    vlc_tick_t core;
    vlc_tick_t prepare;
    vlc_tick_t total;
    vlc_tick_t predicted;
    vlc_tick_t worst;
} vout_phase_profile_t;

#ifdef thread_local
static thread_local vout_phase_profile_t vout_phase_profile;
#else
static vout_phase_profile_t vout_phase_profile;
#endif

/* */
static int VoutValidateFormat(video_format_t *dst,
                              const video_format_t *src)
{
    if (src->i_width == 0  || src->i_width  > 8192 ||
        src->i_height == 0 || src->i_height > 8192)
        return VLC_EGENERIC;
    if (src->i_sar_num <= 0 || src->i_sar_den <= 0)
        return VLC_EGENERIC;

    /* */
    video_format_Copy(dst, src);
    dst->i_chroma = vlc_fourcc_GetCodec(VIDEO_ES, src->i_chroma);
    vlc_ureduce( &dst->i_sar_num, &dst->i_sar_den,
                 src->i_sar_num,  src->i_sar_den, 50000 );
    if (dst->i_sar_num <= 0 || dst->i_sar_den <= 0) {
        dst->i_sar_num = 1;
        dst->i_sar_den = 1;
    }
    video_format_FixRgb(dst);
    return VLC_SUCCESS;
}
static void VideoFormatCopyCropAr(video_format_t *dst,
                                  const video_format_t *src)
{
    video_format_CopyCrop(dst, src);
    dst->i_sar_num = src->i_sar_num;
    dst->i_sar_den = src->i_sar_den;
}
static bool VideoFormatIsCropArEqual(video_format_t *dst,
                                     const video_format_t *src)
{
    return dst->i_sar_num * src->i_sar_den == dst->i_sar_den * src->i_sar_num &&
           dst->i_x_offset       == src->i_x_offset &&
           dst->i_y_offset       == src->i_y_offset &&
           dst->i_visible_width  == src->i_visible_width &&
           dst->i_visible_height == src->i_visible_height;
}

static void ThreadSetCropBorder(vout_thread_t *, unsigned, unsigned,
                                unsigned, unsigned);

static vout_thread_t *VoutCreate(vlc_object_t *object,
                                 const vout_configuration_t *cfg)
{
    video_format_t original;
    if (VoutValidateFormat(&original, cfg->fmt))
        return NULL;

    /* Allocate descriptor */
    vout_thread_t *vout = vlc_custom_create(object,
                                            sizeof(*vout) + sizeof(*vout->p),
                                            "video output");
    if (!vout) {
        video_format_Clean(&original);
        return NULL;
    }

    /* */
    vout->p = (vout_thread_sys_t*)&vout[1];

    vout->p->original = original;
    vout->p->dpb_size = cfg->dpb_size;

    vout_control_Init(&vout->p->control);
    vout_control_PushVoid(&vout->p->control, VOUT_CONTROL_INIT);

    vout_statistic_Init(&vout->p->statistic);

    vout_snapshot_Init(&vout->p->snapshot);

    /* Initialize locks */
    vlc_mutex_init(&vout->p->filter.lock);
    vlc_mutex_init(&vout->p->spu_lock);

    /* Take care of some "interface/control" related initialisations */
    vout_IntfInit(vout);

    /* Initialize subpicture unit */
    vout->p->spu = spu_Create(vout, vout);

    vout->p->title.show     = var_InheritBool(vout, "video-title-show");
    vout->p->title.timeout  = var_InheritInteger(vout, "video-title-timeout");
    vout->p->title.position = var_InheritInteger(vout, "video-title-position");

    /* Get splitter name if present */
    vout->p->splitter_name = var_InheritString(vout, "video-splitter");

    /* */
    vout_InitInterlacingSupport(vout, vout->p->displayed.is_interlaced);

    /* Window */
    if (vout->p->splitter_name == NULL) {
        vout_window_cfg_t wcfg = {
            .is_standalone = !var_InheritBool(vout, "embedded-video"),
            .is_fullscreen = var_GetBool(vout, "fullscreen"),
            .type = VOUT_WINDOW_TYPE_INVALID,
            // TODO: take pixel A/R, crop and zoom into account
#ifdef __APPLE__
            .x = var_InheritInteger(vout, "video-x"),
            .y = var_InheritInteger(vout, "video-y"),
#endif
            .width = cfg->fmt->i_visible_width,
            .height = cfg->fmt->i_visible_height,
        };

        vout_window_t *window = vout_display_window_New(vout, &wcfg);
        if (window != NULL)
        {
            if (var_InheritBool(vout, "video-wallpaper"))
                vout_window_SetState(window, VOUT_WINDOW_STATE_BELOW);
            else if (var_InheritBool(vout, "video-on-top"))
                vout_window_SetState(window, VOUT_WINDOW_STATE_ABOVE);
        }
        vout->p->window = window;
    } else
        vout->p->window = NULL;

    /* */
    vlc_object_set_destructor(vout, VoutDestructor);

    /* */
    if (vlc_clone(&vout->p->thread, Thread, vout,
                  VLC_THREAD_PRIORITY_OUTPUT)) {
        if (vout->p->window != NULL)
            vout_display_window_Delete(vout->p->window);
        spu_Destroy(vout->p->spu);
        vlc_object_release(vout);
        return NULL;
    }

    vout_control_WaitEmpty(&vout->p->control);

    if (vout->p->dead) {
        msg_Err(vout, "video output creation failed");
        vout_CloseAndRelease(vout);
        return NULL;
    }

    vout->p->input = cfg->input;
    if (vout->p->input)
        spu_Attach(vout->p->spu, vout->p->input, true);

    return vout;
}

#undef vout_Request
vout_thread_t *vout_Request(vlc_object_t *object,
                              const vout_configuration_t *cfg)
{
    vout_thread_t *vout = cfg->vout;
    if (cfg->change_fmt && !cfg->fmt) {
        if (vout)
            vout_CloseAndRelease(vout);
        return NULL;
    }

    /* If a vout is provided, try reusing it */
    if (vout) {
        if (vout->p->input != cfg->input) {
            if (vout->p->input)
                spu_Attach(vout->p->spu, vout->p->input, false);
            vout->p->input = cfg->input;
            if (vout->p->input)
                spu_Attach(vout->p->spu, vout->p->input, true);

            /* Another item entirely: what the automatic detection measured
             * on the previous one must not be applied to this one. */
            vout_ControlForgetCrop(vout);
        }

        if (cfg->change_fmt) {
            vout_control_cmd_t cmd;
            vout_control_cmd_Init(&cmd, VOUT_CONTROL_REINIT);
            cmd.u.cfg = cfg;

            vout_control_Push(&vout->p->control, &cmd);
            vout_control_WaitEmpty(&vout->p->control);
            vout_IntfReinit(vout);
        }

        if (!vout->p->dead) {
            msg_Dbg(object, "reusing provided vout");
            return vout;
        }
        vout_CloseAndRelease(vout);

        msg_Warn(object, "cannot reuse provided vout");
    }
    return VoutCreate(object, cfg);
}

void vout_Close(vout_thread_t *vout)
{
    assert(vout);

    if (vout->p->input)
        spu_Attach(vout->p->spu, vout->p->input, false);

    vout_snapshot_End(&vout->p->snapshot);

    vout_control_PushVoid(&vout->p->control, VOUT_CONTROL_CLEAN);
    vlc_join(vout->p->thread, NULL);

    if (vout->p->window != NULL)
        vout_display_window_Delete(vout->p->window);

    vlc_mutex_lock(&vout->p->spu_lock);
    spu_Destroy(vout->p->spu);
    vout->p->spu = NULL;
    vlc_mutex_unlock(&vout->p->spu_lock);
}

/* */
static void VoutDestructor(vlc_object_t *object)
{
    vout_thread_t *vout = (vout_thread_t *)object;

    /* Make sure the vout was stopped first */
    //assert(!vout->p_module);

    free(vout->p->splitter_name);

    /* Destroy the locks */
    vlc_mutex_destroy(&vout->p->spu_lock);
    vlc_mutex_destroy(&vout->p->filter.lock);
    vout_control_Clean(&vout->p->control);

    /* */
    vout_statistic_Clean(&vout->p->statistic);

    /* */
    vout_snapshot_Clean(&vout->p->snapshot);

    video_format_Clean(&vout->p->original);
}

/* */
void vout_Cancel(vout_thread_t *vout, bool canceled)
{
    vout_control_PushBool(&vout->p->control, VOUT_CONTROL_CANCEL, canceled);
    vout_control_WaitEmpty(&vout->p->control);
}

void vout_ChangePause(vout_thread_t *vout, bool is_paused, vlc_tick_t date)
{
    vout_control_cmd_t cmd;
    vout_control_cmd_Init(&cmd, VOUT_CONTROL_PAUSE);
    cmd.u.pause.is_on = is_paused;
    cmd.u.pause.date  = date;
    vout_control_Push(&vout->p->control, &cmd);

    vout_control_WaitEmpty(&vout->p->control);
}

void vout_GetResetStatistic(vout_thread_t *vout, unsigned *restrict displayed,
                            unsigned *restrict lost)
{
    vout_statistic_GetReset( &vout->p->statistic, displayed, lost );
}

void vout_Flush(vout_thread_t *vout, vlc_tick_t date)
{
    vout_control_PushTime(&vout->p->control, VOUT_CONTROL_FLUSH, date);
    vout_control_WaitEmpty(&vout->p->control);
}

bool vout_IsEmpty(vout_thread_t *vout)
{
    picture_t *picture = picture_fifo_Peek(vout->p->decoder_fifo);
    if (picture)
        picture_Release(picture);

    return !picture;
}

size_t vout_GetDecoderFifoCount(vout_thread_t *vout)
{
    return picture_fifo_Count(vout->p->decoder_fifo);
}

vlc_tick_t vout_GetDecoderFifoFirstDate(vout_thread_t *vout)
{
    picture_t *picture = picture_fifo_Peek(vout->p->decoder_fifo);
    if (!picture)
        return VLC_TICK_INVALID;

    vlc_tick_t date = picture->date;
    picture_Release(picture);
    return date;
}

size_t vout_GetDecoderFifoPictureBytes(vout_thread_t *vout)
{
    picture_t *picture = picture_fifo_Peek(vout->p->decoder_fifo);
    if (!picture)
        return 0;

    size_t bytes = 0;
    for (int i = 0; i < picture->i_planes; i++)
        bytes += (size_t)picture->p[i].i_pitch * picture->p[i].i_lines;

    picture_Release(picture);
    return bytes;
}

void vout_ChangeCacheHold(vout_thread_t *vout, bool hold)
{
    vout_control_PushBool(&vout->p->control, VOUT_CONTROL_CACHE_HOLD, hold);
}

void vout_ChangeStaticFrameHold(vout_thread_t *vout, bool hold)
{
    vout_control_PushBool(&vout->p->control,
                          VOUT_CONTROL_STATIC_FRAME_HOLD, hold);
}

void vout_ChangeInteractiveOverlay(vout_thread_t *vout, bool active)
{
    vout_control_PushBool(&vout->p->control,
                          VOUT_CONTROL_INTERACTIVE_OVERLAY, active);
}

bool vout_IsCacheHeld(vout_thread_t *vout)
{
    /* Racy by design (see vout_control.h): the flag belongs to the vout
     * thread, a stale value merely delays the caller's re-arm by one
     * picture. */
    return vout->p->cache_hold;
}

void vout_OffsetCacheDates(vout_thread_t *vout, vlc_tick_t duration)
{
    /* Runs in the caller's thread on purpose: the caller must be able to
     * re-base the held pictures before anything can pop them (the hold
     * release above is asynchronous). The callee carries its own lock;
     * displayed.* is left alone (vout-thread-owned, and only holds the
     * already-shown first forced picture during a hold).
     * Subtitles are deliberately NOT offset (unlike the pause path):
     * SPUs already in the heap were dated before the episode and are
     * correct as-is -- shifting them threw DVD menu highlights into the
     * future (observed: no more selection highlight, every still/cell
     * change opens an episode) -- and the SPU decoder parks in
     * DecoderWaitUnblock BEFORE DecoderFixTs, so anything it held is
     * dated against the already-shifted clock on release. */
    picture_fifo_OffsetDate(vout->p->decoder_fifo, duration);
}

unsigned vout_GetCacheHeadroom(vout_thread_t *vout)
{
    return vout->p->cache_headroom;
}

/* Direct rendering: the decoder and display share one pool, so the
 * look-ahead cache's queued pictures are the display buffers themselves.
 * The cache target reserves against this pool differently than for the
 * separate system-memory pool of indirect rendering (this pool's headroom
 * already excludes the codec DPB) -- see DecoderVideoCacheTarget. */
bool vout_CacheIsDirectRendering(vout_thread_t *vout)
{
    return vout->p->decoder_pool == vout->p->display_pool;
}

void vout_NextPicture(vout_thread_t *vout, vlc_tick_t *duration)
{
    vout_control_cmd_t cmd;
    vout_control_cmd_Init(&cmd, VOUT_CONTROL_STEP);
    cmd.u.time_ptr = duration;

    vout_control_Push(&vout->p->control, &cmd);
    vout_control_WaitEmpty(&vout->p->control);
}

void vout_DisplayTitle(vout_thread_t *vout, const char *title)
{
    assert(title);
    vout_control_PushString(&vout->p->control, VOUT_CONTROL_OSD_TITLE, title);
}

void vout_WindowMouseEvent(vout_thread_t *vout,
                           const vout_window_mouse_event_t *mouse)
{
    assert(mouse);
    vout_control_cmd_t cmd;
    vout_control_cmd_Init(&cmd, VOUT_CONTROL_WINDOW_MOUSE);
    cmd.u.window_mouse = *mouse;

    vout_control_Push(&vout->p->control, &cmd);
}

void vout_PutSubpicture( vout_thread_t *vout, subpicture_t *subpic )
{
    vout_control_cmd_t cmd;
    vout_control_cmd_Init(&cmd, VOUT_CONTROL_SUBPICTURE);
    cmd.u.subpicture = subpic;

    vout_control_Push(&vout->p->control, &cmd);
}

void vout_RefreshSubpicture(vout_thread_t *vout)
{
    vout_control_PushVoid(&vout->p->control, VOUT_CONTROL_REFRESH_SUBPICTURE);
}
int vout_RegisterSubpictureChannel( vout_thread_t *vout )
{
    int channel = VOUT_SPU_CHANNEL_AVAIL_FIRST;

    vlc_mutex_lock(&vout->p->spu_lock);
    if (vout->p->spu)
        channel = spu_RegisterChannel(vout->p->spu);
    vlc_mutex_unlock(&vout->p->spu_lock);

    return channel;
}
void vout_FlushSubpictureChannel( vout_thread_t *vout, int channel )
{
    vout_control_PushInteger(&vout->p->control, VOUT_CONTROL_FLUSH_SUBPICTURE,
                             channel);
}

/**
 * Allocates a video output picture buffer.
 *
 * Either vout_PutPicture() or picture_Release() must be used to return the
 * buffer to the video output free buffer pool.
 *
 * You may use picture_Hold() (paired with picture_Release()) to keep a
 * read-only reference.
 */
picture_t *vout_GetPicture(vout_thread_t *vout)
{
    picture_t *picture = picture_pool_Wait(vout->p->decoder_pool);
    if (likely(picture != NULL)) {
        picture_Reset(picture);
        VideoFormatCopyCropAr(&picture->format, &vout->p->original);
    }
    return picture;
}

/**
 * It gives to the vout a picture to be displayed.
 *
 * The given picture MUST comes from vout_GetPicture.
 *
 * Becareful, after vout_PutPicture is called, picture_t::p_next cannot be
 * read/used.
 */
void vout_PutPicture(vout_thread_t *vout, picture_t *picture)
{
    picture->p_next = NULL;
    if (picture_pool_OwnsPic(vout->p->decoder_pool, picture))
    {
        /* How much time is left before this picture is due? Positive means
         * the decoder is ahead and the delay that shows up at the swap was
         * introduced downstream; zero or negative means it arrived late and
         * no display path, however quick, could have saved it. */
        if (picture->date > VLC_TICK_INVALID) {
            const vlc_tick_t now = mdate();
            const vlc_tick_t lead = picture->date - now;

            vout->p->handoff.count++;
            vout->p->handoff.sum += lead;
            if (vout->p->handoff.count == 1 || lead < vout->p->handoff.worst)
                vout->p->handoff.worst = lead;
            if (lead <= 0)
                vout->p->handoff.late++;
            if (vout->p->handoff.last_report == VLC_TICK_INVALID)
                vout->p->handoff.last_report = now;
            else if (now - vout->p->handoff.last_report >= 5 * CLOCK_FREQ) {
                msg_Dbg(vout, "handoff lead: %u pictures, avg %d us ahead, "
                        "least %d us, already late: %u",
                        vout->p->handoff.count,
                        (int)(vout->p->handoff.sum
                              / __MAX(vout->p->handoff.count, 1)),
                        (int)vout->p->handoff.worst,
                        vout->p->handoff.late);
                vout->p->handoff.count = 0;
                vout->p->handoff.late = 0;
                vout->p->handoff.worst = 0;
                vout->p->handoff.sum = 0;
                vout->p->handoff.last_report = now;
            }
        }

        picture_fifo_Push(vout->p->decoder_fifo, picture);

        vout_control_Wake(&vout->p->control);
    }
    else
    {
        /* FIXME: HACK: Drop this picture because the vout changed. The old
         * picture pool need to be kept by the new vout. This requires a major
         * "vout display" API change. */
        picture_Release(picture);
    }
}

/* */
int vout_GetSnapshot(vout_thread_t *vout,
                     block_t **image_dst, picture_t **picture_dst,
                     video_format_t *fmt,
                     const char *type, vlc_tick_t timeout)
{
    picture_t *picture = vout_snapshot_Get(&vout->p->snapshot, timeout);
    if (!picture) {
        msg_Err(vout, "Failed to grab a snapshot");
        return VLC_EGENERIC;
    }

    if (image_dst) {
        vlc_fourcc_t codec = VLC_CODEC_PNG;
        if (type && image_Type2Fourcc(type))
            codec = image_Type2Fourcc(type);

        const int override_width  = var_InheritInteger(vout, "snapshot-width");
        const int override_height = var_InheritInteger(vout, "snapshot-height");

        if (picture_Export(VLC_OBJECT(vout), image_dst, fmt,
                           picture, codec, override_width, override_height)) {
            msg_Err(vout, "Failed to convert image for snapshot");
            picture_Release(picture);
            return VLC_EGENERIC;
        }
    }
    if (picture_dst)
        *picture_dst = picture;
    else
        picture_Release(picture);
    return VLC_SUCCESS;
}

void vout_ChangeAspectRatio( vout_thread_t *p_vout,
                             unsigned int i_num, unsigned int i_den )
{
    vout_ControlChangeSampleAspectRatio( p_vout, i_num, i_den );
}

/* vout_Control* are usable by anyone at anytime */
void vout_ControlChangeFullscreen(vout_thread_t *vout, bool fullscreen)
{
    vout_control_PushBool(&vout->p->control, VOUT_CONTROL_FULLSCREEN,
                          fullscreen);
}

int vout_RestartDisplay(vout_thread_t *vout)
{
    vout_control_PushVoid(&vout->p->control, VOUT_CONTROL_RESTART_DISPLAY);
    vout_control_WaitEmpty(&vout->p->control);
    return VLC_SUCCESS;
}
void vout_ControlChangeWindowState(vout_thread_t *vout, unsigned st)
{
    vout_control_PushInteger(&vout->p->control, VOUT_CONTROL_WINDOW_STATE, st);
}
void vout_ControlChangeDisplayFilled(vout_thread_t *vout, bool is_filled)
{
    vout_control_PushBool(&vout->p->control, VOUT_CONTROL_DISPLAY_FILLED,
                          is_filled);
}
void vout_ControlChangeZoom(vout_thread_t *vout, int num, int den)
{
    vout_control_PushPair(&vout->p->control, VOUT_CONTROL_ZOOM,
                          num, den);
}
void vout_ControlChangeSampleAspectRatio(vout_thread_t *vout,
                                         unsigned num, unsigned den)
{
    vout_control_PushPair(&vout->p->control, VOUT_CONTROL_ASPECT_RATIO,
                          num, den);
}
void vout_ControlChangeCropRatio(vout_thread_t *vout,
                                 unsigned num, unsigned den)
{
    vout_control_PushPair(&vout->p->control, VOUT_CONTROL_CROP_RATIO,
                          num, den);
}
void vout_ControlChangeCropWindow(vout_thread_t *vout,
                                  int x, int y, int width, int height)
{
    vout_control_cmd_t cmd;
    vout_control_cmd_Init(&cmd, VOUT_CONTROL_CROP_WINDOW);
    cmd.u.window.x      = __MAX(x, 0);
    cmd.u.window.y      = __MAX(y, 0);
    cmd.u.window.width  = __MAX(width, 0);
    cmd.u.window.height = __MAX(height, 0);

    vout_control_Push(&vout->p->control, &cmd);
}
void vout_ControlChangeCropBorder(vout_thread_t *vout,
                                  int left, int top, int right, int bottom)
{
    vout_control_cmd_t cmd;
    vout_control_cmd_Init(&cmd, VOUT_CONTROL_CROP_BORDER);
    cmd.u.border.left   = __MAX(left, 0);
    cmd.u.border.top    = __MAX(top, 0);
    cmd.u.border.right  = __MAX(right, 0);
    cmd.u.border.bottom = __MAX(bottom, 0);

    vout_control_Push(&vout->p->control, &cmd);
}
void vout_ControlChangeCropAuto(vout_thread_t *vout)
{
    vout_control_PushVoid(&vout->p->control, VOUT_CONTROL_CROP_AUTO);
}
void vout_ControlForgetCrop(vout_thread_t *vout)
{
    vout_control_PushVoid(&vout->p->control, VOUT_CONTROL_CROP_FORGET);
}
void vout_ControlChangeFilters(vout_thread_t *vout, const char *filters)
{
    vout_control_PushString(&vout->p->control, VOUT_CONTROL_CHANGE_FILTERS,
                            filters);
}
void vout_ControlChangeSubSources(vout_thread_t *vout, const char *filters)
{
    vout_control_PushString(&vout->p->control, VOUT_CONTROL_CHANGE_SUB_SOURCES,
                            filters);
}
void vout_ControlChangeSubFilters(vout_thread_t *vout, const char *filters)
{
    vout_control_PushString(&vout->p->control, VOUT_CONTROL_CHANGE_SUB_FILTERS,
                            filters);
}
void vout_ControlChangeSubMargin(vout_thread_t *vout, int margin)
{
    vout_control_PushInteger(&vout->p->control, VOUT_CONTROL_CHANGE_SUB_MARGIN,
                             margin);
}

void vout_ControlChangeViewpoint(vout_thread_t *vout,
                                 const vlc_viewpoint_t *p_viewpoint)
{
    vout_control_cmd_t cmd;
    vout_control_cmd_Init(&cmd, VOUT_CONTROL_VIEWPOINT);
    cmd.u.viewpoint = *p_viewpoint;
    vout_control_Push(&vout->p->control, &cmd);
}

/* */
static void VoutGetDisplayCfg(vout_thread_t *vout, vout_display_cfg_t *cfg, const char *title)
{
    /* Load configuration */
#if defined(_WIN32) || defined(__OS2__)
    cfg->is_fullscreen = var_GetBool(vout, "fullscreen")
                         || var_GetBool(vout, "video-wallpaper");
#endif
    cfg->viewpoint = vout->p->original.pose;

    cfg->display.title = title;
    const int display_width = var_GetInteger(vout, "width");
    const int display_height = var_GetInteger(vout, "height");
    cfg->display.width   = display_width > 0  ? display_width  : 0;
    cfg->display.height  = display_height > 0 ? display_height : 0;
    cfg->is_display_filled  = var_GetBool(vout, "autoscale");
    unsigned msar_num, msar_den;
    if (var_InheritURational(vout, &msar_num, &msar_den, "monitor-par") ||
        msar_num <= 0 || msar_den <= 0) {
        msar_num = 1;
        msar_den = 1;
    }
    cfg->display.sar.num = msar_num;
    cfg->display.sar.den = msar_den;
    unsigned zoom_den = 1000;
    unsigned zoom_num = zoom_den * var_GetFloat(vout, "zoom");
    vlc_ureduce(&zoom_num, &zoom_den, zoom_num, zoom_den, 0);
    cfg->zoom.num = zoom_num;
    cfg->zoom.den = zoom_den;
    cfg->align.vertical = VOUT_DISPLAY_ALIGN_CENTER;
    cfg->align.horizontal = VOUT_DISPLAY_ALIGN_CENTER;
    const int align_mask = var_GetInteger(vout, "align");
    if (align_mask & 0x1)
        cfg->align.horizontal = VOUT_DISPLAY_ALIGN_LEFT;
    else if (align_mask & 0x2)
        cfg->align.horizontal = VOUT_DISPLAY_ALIGN_RIGHT;
    if (align_mask & 0x4)
        cfg->align.vertical = VOUT_DISPLAY_ALIGN_TOP;
    else if (align_mask & 0x8)
        cfg->align.vertical = VOUT_DISPLAY_ALIGN_BOTTOM;
}

vout_window_t *vout_NewDisplayWindow(vout_thread_t *vout, unsigned type)
{
    vout_window_t *window = vout->p->window;

    assert(vout->p->splitter_name == NULL);

    if (window == NULL)
        return NULL;
    if (type != VOUT_WINDOW_TYPE_INVALID && type != window->type)
        return NULL;
    return window;
}

void vout_DeleteDisplayWindow(vout_thread_t *vout, vout_window_t *window)
{
    if (window == NULL && vout->p->window != NULL) {
        vout_display_window_Delete(vout->p->window);
        vout->p->window = NULL;
    }
    assert(vout->p->window == window);
}

void vout_SetDisplayWindowSize(vout_thread_t *vout,
                               unsigned width, unsigned height)
{
    vout_window_t *window = vout->p->window;

    if (window != NULL)
    /* Request a resize of the window. If it fails, there is nothing to do.
     * If it succeeds, the window will emit a resize event later. */
        vout_window_SetSize(window, width, height);
    else
    if (vout->p->display.vd != NULL)
    /* Force a resize of window-less display. This is not allowed to fail,
     * although the display is allowed to ignore the size anyway. */
        /* FIXME: remove this, fix MSW and OS/2 window providers */
        vout_display_SendEventDisplaySize(vout->p->display.vd, width, height);
}

int vout_HideWindowMouse(vout_thread_t *vout, bool hide)
{
    vout_window_t *window = vout->p->window;

    return window != NULL ? vout_window_HideMouse(window, hide) : VLC_EGENERIC;
}

/* */
static int FilterRestartCallback(vlc_object_t *p_this, char const *psz_var,
                                 vlc_value_t oldval, vlc_value_t newval,
                                 void *p_data)
{
    (void) p_this; (void) psz_var; (void) oldval; (void) newval;
    vout_ControlChangeFilters((vout_thread_t *)p_data, NULL);
    return 0;
}

static int ThreadDelFilterCallbacks(filter_t *filter, void *opaque)
{
    filter_DelProxyCallbacks((vlc_object_t *)opaque, filter,
                             FilterRestartCallback);
    return VLC_SUCCESS;
}

static void ThreadDelAllFilterCallbacks(vout_thread_t *vout)
{
    assert(vout->p->filter.chain_interactive != NULL);
    filter_chain_ForEach(vout->p->filter.chain_interactive,
                         ThreadDelFilterCallbacks, vout);
}

static picture_t *VoutVideoFilterInteractiveNewPicture(filter_t *filter)
{
    vout_thread_t *vout = filter->owner.sys;

    picture_t *picture = picture_pool_Get(vout->p->private_pool);
    if (picture) {
        picture_Reset(picture);
        VideoFormatCopyCropAr(&picture->format, &filter->fmt_out.video);
    }
    return picture;
}

static picture_t *VoutVideoFilterStaticNewPicture(filter_t *filter)
{
    vout_thread_t *vout = filter->owner.sys;

    vlc_assert_locked(&vout->p->filter.lock);
    if (filter_chain_IsEmpty(vout->p->filter.chain_interactive))
        return VoutVideoFilterInteractiveNewPicture(filter);

    return picture_NewFromFormat(&filter->fmt_out.video);
}

static void ThreadFilterFlush(vout_thread_t *vout, bool is_locked)
{
    if (vout->p->displayed.current)
        picture_Release( vout->p->displayed.current );
    vout->p->displayed.current = NULL;

    if (vout->p->displayed.next)
        picture_Release( vout->p->displayed.next );
    vout->p->displayed.next = NULL;

    if (!is_locked)
        vlc_mutex_lock(&vout->p->filter.lock);
    filter_chain_VideoFlush(vout->p->filter.chain_static);
    filter_chain_VideoFlush(vout->p->filter.chain_interactive);
    if (!is_locked)
        vlc_mutex_unlock(&vout->p->filter.lock);
}

typedef struct {
    char           *name;
    config_chain_t *cfg;
} vout_filter_t;

static void ThreadChangeFilters(vout_thread_t *vout,
                                const video_format_t *source,
                                const char *filters,
                                int deinterlace,
                                bool is_locked)
{
    ThreadFilterFlush(vout, is_locked);
    ThreadDelAllFilterCallbacks(vout);

    vlc_array_t array_static;
    vlc_array_t array_interactive;

    vlc_array_init(&array_static);
    vlc_array_init(&array_interactive);

    if ((vout->p->filter.has_deint =
         deinterlace == 1 || (deinterlace == -1 && vout->p->filter.has_deint)))
    {
        vout_filter_t *e = malloc(sizeof(*e));

        if (likely(e))
        {
            free(config_ChainCreate(&e->name, &e->cfg, "deinterlace"));
            vlc_array_append_or_abort(&array_static, e);
        }
    }

    char *current = filters ? strdup(filters) : NULL;
    while (current) {
        config_chain_t *cfg;
        char *name;
        char *next = config_ChainCreate(&name, &cfg, current);

        if (name && *name) {
            vout_filter_t *e = malloc(sizeof(*e));

            if (likely(e)) {
                e->name = name;
                e->cfg  = cfg;
                if (!strcmp(e->name, "postproc") || !strcmp(e->name, "amf_frc"))
                    vlc_array_append_or_abort(&array_static, e);
                else
                    vlc_array_append_or_abort(&array_interactive, e);
            }
            else {
                if (cfg)
                    config_ChainDestroy(cfg);
                free(name);
            }
        } else {
            if (cfg)
                config_ChainDestroy(cfg);
            free(name);
        }
        free(current);
        current = next;
    }

    if (!is_locked)
        vlc_mutex_lock(&vout->p->filter.lock);

    es_format_t fmt_target;
    es_format_InitFromVideo(&fmt_target, source ? source : &vout->p->filter.format);

    const es_format_t *p_fmt_current = &fmt_target;

    for (int a = 0; a < 2; a++) {
        vlc_array_t    *array = a == 0 ? &array_static :
                                         &array_interactive;
        filter_chain_t *chain = a == 0 ? vout->p->filter.chain_static :
                                         vout->p->filter.chain_interactive;

        filter_chain_Reset(chain, p_fmt_current, p_fmt_current);
        for (size_t i = 0; i < vlc_array_count(array); i++) {
            vout_filter_t *e = vlc_array_item_at_index(array, i);
            msg_Dbg(vout, "Adding '%s' as %s", e->name, a == 0 ? "static" : "interactive");
            filter_t *filter = filter_chain_AppendFilter(chain, e->name, e->cfg,
                               NULL, NULL);
            if (!filter)
            {
                msg_Err(vout, "Failed to add filter '%s'", e->name);
                config_ChainDestroy(e->cfg);
            }
            else if (a == 1) /* Add callbacks for interactive filters */
                filter_AddProxyCallbacks(vout, filter, FilterRestartCallback);

            free(e->name);
            free(e);
        }
        p_fmt_current = filter_chain_GetFmtOut(chain);
        vlc_array_clear(array);
    }

    if (!es_format_IsSimilar(p_fmt_current, &fmt_target)) {
        msg_Dbg(vout, "Adding a filter to compensate for format changes");
        if (filter_chain_AppendConverter(vout->p->filter.chain_interactive,
                                         p_fmt_current, &fmt_target) != 0) {
            msg_Err(vout, "Failed to compensate for the format changes, removing all filters");
            ThreadDelAllFilterCallbacks(vout);
            filter_chain_Reset(vout->p->filter.chain_static,      &fmt_target, &fmt_target);
            filter_chain_Reset(vout->p->filter.chain_interactive, &fmt_target, &fmt_target);
        }
    }

    es_format_Clean(&fmt_target);

    if (vout->p->filter.configuration != filters) {
        free(vout->p->filter.configuration);
        vout->p->filter.configuration = filters ? strdup(filters) : NULL;
    }
    if (source) {
        video_format_Clean(&vout->p->filter.format);
        video_format_Copy(&vout->p->filter.format, source);
    }

    if (!is_locked)
        vlc_mutex_unlock(&vout->p->filter.lock);
}


/* */
static int ThreadDisplayPreparePicture(vout_thread_t *vout, bool reuse, bool frame_by_frame)
{
    bool is_late_dropped = vout->p->is_late_dropped && !vout->p->pause.is_on
                        && !vout->p->cache_hold && !frame_by_frame;

    vlc_mutex_lock(&vout->p->filter.lock);

    picture_t *picture = filter_chain_VideoFilter(vout->p->filter.chain_static, NULL);
    assert(!reuse || !picture);

    while (!picture) {
        picture_t *decoded;
        if (reuse && vout->p->displayed.decoded) {
            decoded = picture_Hold(vout->p->displayed.decoded);
        } else {
            decoded = picture_fifo_Pop(vout->p->decoder_fifo);
            if (decoded) {
                if (is_late_dropped && !decoded->b_force) {
                    vlc_tick_t late_threshold;
#if defined (__powerpc__) || defined (__POWERPC__)
                    /* On PowerPC-era Macs every decoded+converted picture
                     * costs a large chunk of the frame budget: dropping one
                     * that is half a period late throws that work away and
                     * digs the deficit deeper, while displaying it merely
                     * shifts A/V sync by an imperceptible <40 ms. Tolerate a
                     * full frame period before trashing. */
                    const vlc_tick_t num = CLOCK_FREQ;
#else
                    const vlc_tick_t num = CLOCK_FREQ / 2;
#endif
                    if (decoded->format.i_frame_rate && decoded->format.i_frame_rate_base)
                        late_threshold = (num * decoded->format.i_frame_rate_base) / decoded->format.i_frame_rate;
                    else
                        late_threshold = VOUT_DISPLAY_LATE_THRESHOLD * (num / (CLOCK_FREQ/2));
                    vout_display_t *vd = vout->p->display.vd;
                    if (vd != NULL &&
                        var_Type(vd, "vout-late-threshold") != 0) {
                        const vlc_tick_t display_threshold =
                            var_GetInteger(vd, "vout-late-threshold");
                        if (late_threshold < display_threshold)
                            late_threshold = display_threshold;
                    }
                    const vlc_tick_t predicted = mdate() + 0; /* TODO improve */
                    const vlc_tick_t late = predicted - decoded->date;
                    /* A picture decoded by the GPU costs nothing to display:
                     * the work is already spent and the surface already holds
                     * the image. Dropping one that is merely a frame or two
                     * late saves no decoding and leaves a hole where its frame
                     * period should be -- measured on the ATI DVDDriver path
                     * (Mac OS X 10.2, iBook G3), that is what made the picture
                     * stutter as if frames were repeated.
                     * Be generous, but NOT infinite: dropping is also the only
                     * way the pipeline ever catches up. With no ceiling at all
                     * a deficit taken at start-up (the software probe runs
                     * before the hardware path commits) never resorbs, and the
                     * vout settles into displaying every picture 1.3 s late in
                     * bursts -- same stutter, harder to see. Above a quarter of
                     * a second the deficit is worth paying down. */
                    if (decoded->context != NULL && late_threshold < CLOCK_FREQ / 4)
                        late_threshold = CLOCK_FREQ / 4;
                    /* Hybrid MVC on the GeForce 320M has a repeatable
                     * ~240 ms base-view/dependent-view hand-off latency.
                     * The generic 250 ms hardware ceiling sits directly on
                     * that operating point: harmless scheduler jitter crosses
                     * it several times per second and turns a steady 23.976
                     * decode into an visibly uneven ~20 fps presentation.
                     * Keep a finite recovery ceiling, but move it clear of the
                     * normal MVC envelope.  This remains scoped to genuine
                     * frame-packed pictures carrying a hardware context. */
                    if (decoded->context != NULL &&
                        decoded->format.multiview_mode ==
                            MULTIVIEW_STEREO_FRAMEPACKED &&
                        late_threshold < 400 * 1000)
                        late_threshold = 400 * 1000;
                    if (late > late_threshold) {
                        msg_Warn(vout, "picture is too late to be displayed (missing %"PRId64" ms)", late/1000);
                        picture_Release(decoded);
                        vout_statistic_AddLost(&vout->p->statistic, 1);
                        continue;
                    } else if (late > 0) {
                        msg_Dbg(vout, "picture might be displayed late (missing %"PRId64" ms)", late/1000);
                    }
                }
                if (!VideoFormatIsCropArEqual(&decoded->format, &vout->p->filter.format))
                    ThreadChangeFilters(vout, &decoded->format, vout->p->filter.configuration, -1, true);
            }
        }

        if (!decoded)
            break;
        reuse = false;

        if (vout->p->displayed.decoded)
            picture_Release(vout->p->displayed.decoded);

        vout->p->displayed.decoded       = picture_Hold(decoded);
        vout->p->displayed.timestamp     = decoded->date;
        vout->p->displayed.is_interlaced = !decoded->b_progressive;

        picture = filter_chain_VideoFilter(vout->p->filter.chain_static, decoded);
    }

    vlc_mutex_unlock(&vout->p->filter.lock);

    if (!picture)
        return VLC_EGENERIC;

    ThreadUpdateCropAuto(vout, picture);

    assert(!vout->p->displayed.next);
    if (!vout->p->displayed.current)
        vout->p->displayed.current = picture;
    else
        vout->p->displayed.next    = picture;
    return VLC_SUCCESS;
}

static picture_t *ConvertRGB32AndBlendBufferNew(filter_t *filter)
{
    return picture_NewFromFormat(&filter->fmt_out.video);
}

static picture_t *ConvertRGB32AndBlend(vout_thread_t *vout, picture_t *pic,
                                     subpicture_t *subpic,
                                     const video_format_t *fmt_spu)
{
    /* This function will convert the pic to RGB32 and blend the subpic to it.
     * The returned pic can't be used to display since the chroma will be
     * different than the "vout display" one, but it can be used for snapshots.
     * fmt_spu is the format the subpicture was rendered for; it also describes
     * pic, which is left untouched.
     * */

    filter_owner_t owner = {
        .video = {
            .buffer_new = ConvertRGB32AndBlendBufferNew,
        },
    };
    filter_chain_t *filterc = filter_chain_NewVideo(vout, false, &owner);
    if (!filterc)
        return NULL;

    es_format_t src;
    es_format_Init(&src, VIDEO_ES, fmt_spu->i_chroma);
    src.video = *fmt_spu;

    es_format_t dst = src;
    dst.video.i_chroma = VLC_CODEC_RGB32;
    video_format_FixRgb(&dst.video);

    if (filter_chain_AppendConverter(filterc, &src, &dst) != 0)
    {
        filter_chain_Delete(filterc);
        return NULL;
    }

    picture_Hold(pic);
    pic = filter_chain_VideoFilter(filterc, pic);
    filter_chain_Delete(filterc);

    if (pic)
    {
        filter_t *swblend = filter_NewBlend(VLC_OBJECT(vout), &dst.video);
        if (swblend)
        {
            bool success = picture_BlendSubpicture(pic, swblend, subpic) > 0;
            filter_DeleteBlend(swblend);
            if (success)
                return pic;
        }
        picture_Release(pic);
    }
    return NULL;
}

/* Format a subpicture has to be rendered for when the "vout display" blends it
 * itself: the placed picture on the display, never smaller than the source. */
static void SpuDisplayFormat(video_format_t *fmt, vout_display_t *vd)
{
    vout_display_place_t place;
    vout_display_PlacePicture(&place, &vd->source, vd->cfg, false);

    *fmt = vd->source;
    const bool per_eye_canvas =
        var_Type(vd, "vout-spu-eye-canvas") != 0 &&
        var_GetBool(vd, "vout-spu-eye-canvas");
    if (!per_eye_canvas &&
        fmt->i_width * fmt->i_height < place.width * place.height) {
        /* "place" is expressed in display coordinates: vout_display_PlacePicture
         * has already applied the source rotation to it. This format still
         * carries that rotation and the caller applies it once more
         * (video_format_ApplyRotation) before handing it to spu_Render, so the
         * dimensions have to be stored the other way round -- otherwise a video
         * tagged 90/270 degrees (any portrait phone clip) gets its subpictures
         * rendered on a canvas whose aspect is transposed, and they reach the
         * screen squashed along one axis. */
        unsigned width  = place.width;
        unsigned height = place.height;
        if (ORIENT_IS_SWAP(fmt->orientation)) {
            unsigned store = width;
            width  = height;
            height = store;
        }
        fmt->i_sar_num = vd->cfg->display.sar.num;
        fmt->i_sar_den = vd->cfg->display.sar.den;
        fmt->i_width          =
        fmt->i_visible_width  = width;
        fmt->i_height         =
        fmt->i_visible_height = height;
    }

    /* A frame-packed MVC picture is represented internally as two vertically
     * stacked eyes (1920x2160 with SAR 2:1 for 1080p). Subpictures, menus and
     * OSDs are authored in one eye's logical 1920x1080 canvas; the display
     * module duplicates that canvas into the two HDMI views. Rendering the
     * SPU against the stacked format first scaled every BD-J ARGB canvas to
     * 1920x2160, only for OpenGL to map it back into each eye. Besides being
     * geometrically redundant, a Java menu that flushes once per video frame
     * forced this 16 MiB scale on every frame and exceeded the 23.976 fps
     * budget. Keep the SPU canvas in per-eye coordinates and remove the SAR
     * factor introduced solely by vertical stacking. */
    if (fmt->multiview_mode == MULTIVIEW_STEREO_FRAMEPACKED &&
        fmt->i_visible_height >= 2)
    {
        fmt->i_height /= 2;
        fmt->i_visible_height /= 2;
        fmt->i_y_offset /= 2;

        unsigned sar_num, sar_den;
        vlc_ureduce(&sar_num, &sar_den, fmt->i_sar_num,
                    (uint64_t)fmt->i_sar_den * 2, 50000);
        fmt->i_sar_num = sar_num;
        fmt->i_sar_den = sar_den;
    }
}

static int ThreadDisplayRenderPicture(vout_thread_t *vout, bool is_forced)
{
    vout_thread_sys_t *sys = vout->p;
    vout_display_t *vd = vout->p->display.vd;

    const bool profile_on = getenv("VLC_VOUT_PROF") != NULL;
    const vlc_tick_t profile_start = profile_on ? mdate() : 0;
    const vlc_tick_t profile_predicted = profile_on
                                       ? vout_chrono_GetHigh(&vout->p->render)
                                       : 0;

    picture_t *torender = picture_Hold(vout->p->displayed.current);

    vout_chrono_Start(&vout->p->render);

    vlc_mutex_lock(&vout->p->filter.lock);
    picture_t *filtered = filter_chain_VideoFilter(vout->p->filter.chain_interactive, torender);
    vlc_mutex_unlock(&vout->p->filter.lock);

    const vlc_tick_t profile_filter_done = profile_on ? mdate() : 0;

    if (!filtered)
        return VLC_EGENERIC;

    if (filtered->date != vout->p->displayed.current->date)
        msg_Warn(vout, "Unsupported timestamp modifications done by chain_interactive");

    /*
     * Get the subpicture to be displayed
     */
    const bool do_snapshot = vout_snapshot_IsRequested(&vout->p->snapshot);
    vlc_tick_t render_subtitle_date;
    if (vout->p->pause.is_on)
        render_subtitle_date = vout->p->pause.date;
    else
        render_subtitle_date = filtered->date > 1 ? filtered->date : mdate();
    vlc_tick_t render_osd_date = mdate(); /* FIXME wrong */

    /*
     * Get the subpicture to be displayed
     */
    const bool spu_in_display = vd->info.subpicture_chromas &&
                                *vd->info.subpicture_chromas != 0;
    const bool do_dr_spu = !do_snapshot && spu_in_display;

    //FIXME: Denying do_early_spu if vd->source.orientation != ORIENT_NORMAL
    //will have the effect that snapshots miss the subpictures. We do this
    //because there is currently no way to transform subpictures to match
    //the source format.
    const bool do_early_spu = !do_dr_spu &&
                               vd->source.orientation == ORIENT_NORMAL &&
                              (vd->info.is_slow ||
                               sys->display.use_dr ||
                               do_snapshot ||
                               vd->fmt.i_width * vd->fmt.i_height <= vd->source.i_width * vd->source.i_height);

    const vlc_fourcc_t *subpicture_chromas;
    video_format_t fmt_spu;
    /* An opaque chroma (a hardware surface: CVPX, D3D, VAAPI...) has no
     * pixels the blend module could ever write to. */
    bool opaque_spu_dst = false;
    if (do_dr_spu) {
        SpuDisplayFormat(&fmt_spu, vd);
        subpicture_chromas = vd->info.subpicture_chromas;
    } else {
        if (do_early_spu) {
            fmt_spu = vd->source;
        } else {
            fmt_spu = vd->fmt;
            fmt_spu.i_sar_num = vd->cfg->display.sar.num;
            fmt_spu.i_sar_den = vd->cfg->display.sar.den;
        }
        subpicture_chromas = NULL;
        /* A hardware surface has no plane to write into: its chroma
         * description is either missing or a FAKE_FMT() with no plane. */
        const vlc_chroma_description_t *dsc =
            vlc_fourcc_GetChromaDescription(fmt_spu.i_chroma);
        opaque_spu_dst = dsc == NULL || dsc->plane_count == 0;

        if (vout->p->spu_blend &&
            (opaque_spu_dst ||
             vout->p->spu_blend->fmt_out.video.i_chroma != fmt_spu.i_chroma)) {
            filter_DeleteBlend(vout->p->spu_blend);
            vout->p->spu_blend = NULL;
            vout->p->spu_blend_chroma = 0;
        }
        if (opaque_spu_dst) {
            /* Don't load a blender that could only fail. Snapshots are blended
             * into an RGB32 conversion below, and the picture on screen keeps
             * its overlay through the "vout display" itself when it can draw
             * subpictures. */
            if (vout->p->spu_blend_chroma != fmt_spu.i_chroma) {
                vout->p->spu_blend_chroma = fmt_spu.i_chroma;
                msg_Dbg(vout, "opaque chroma %4.4s: subpictures are %s, "
                        "snapshots are blended in RGB32",
                        (const char *)&fmt_spu.i_chroma,
                        spu_in_display ? "drawn by the display"
                                       : "not blended");
            }
        } else if (!vout->p->spu_blend &&
                   vout->p->spu_blend_chroma != fmt_spu.i_chroma) {
            vout->p->spu_blend_chroma = fmt_spu.i_chroma;
            vout->p->spu_blend = filter_NewBlend(VLC_OBJECT(vout), &fmt_spu);
            if (!vout->p->spu_blend)
                msg_Err(vout, "Failed to create blending filter, OSD/Subtitles will not work");
        }
    }

    video_format_t fmt_spu_rot;
    video_format_ApplyRotation(&fmt_spu_rot, &fmt_spu);
    subpicture_t *subpic = spu_Render(vout->p->spu,
                                      subpicture_chromas, &fmt_spu_rot,
                                      &vd->source,
                                      render_subtitle_date, render_osd_date,
                                      do_snapshot);

    /* The overlay above was rendered to be blended into the picture, which is
     * impossible on a hardware surface. Render a second one, in a chroma and a
     * size the "vout display" can draw itself, so that the frame on screen
     * does not lose its subtitles/menus while the snapshot is being made.
     * Rendered even when the first one came back empty: a snapshot ignores the
     * OSD layer (disc menus, volume bar), the screen must not. Missing it is
     * visible for good when the snapshot lands on a paused frame -- no further
     * picture is rendered to bring the menu back. */
    subpicture_t *dr_subpic = NULL;
    if (opaque_spu_dst && spu_in_display && sys->display.use_dr) {
        video_format_t fmt_dr, fmt_dr_rot;
        SpuDisplayFormat(&fmt_dr, vd);
        video_format_ApplyRotation(&fmt_dr_rot, &fmt_dr);
        dr_subpic = spu_Render(vout->p->spu, vd->info.subpicture_chromas,
                               &fmt_dr_rot, &vd->source,
                               render_subtitle_date, render_osd_date, false);
    }
    const vlc_tick_t profile_spu_done = profile_on ? mdate() : 0;
    /*
     * Perform rendering
     *
     * We have to:
     * - be sure to end up with a direct buffer.
     * - blend subtitles, and in a fast access buffer
     */
    bool is_direct = vout->p->decoder_pool == vout->p->display_pool;
    picture_t *todisplay = filtered;
    picture_t *snap_pic = todisplay;
    if (do_early_spu && subpic) {
        if (opaque_spu_dst) {
            /* Nothing to blend into: only the snapshot needs a blended copy,
             * made in RGB32 out of the hardware surface. */
            if (do_snapshot) {
                picture_t *copy = ConvertRGB32AndBlend(vout, todisplay, subpic,
                                                       &fmt_spu);
                if (copy)
                    snap_pic = copy;
            }
        } else if (vout->p->spu_blend) {
            picture_t *blent = picture_pool_Get(vout->p->private_pool);
            if (blent) {
                VideoFormatCopyCropAr(&blent->format, &filtered->format);
                picture_Copy(blent, filtered);
                if (picture_BlendSubpicture(blent, vout->p->spu_blend, subpic)) {
                    picture_Release(todisplay);
                    snap_pic = todisplay = blent;
                } else
                {
                    /* Blending failed, likely because the picture is
                     * read-only. Try to convert it to a software RGB32 one
                     * before blending it. */
                    if (do_snapshot)
                    {
                        picture_t *copy = ConvertRGB32AndBlend(vout, blent,
                                                               subpic, &fmt_spu);
                        if (copy)
                            snap_pic = copy;
                    }
                    picture_Release(blent);
                }
            }
        }
        subpicture_Delete(subpic);
        subpic = NULL;
    }

    /* Hand the display the overlay it can draw itself, in place of the one we
     * could not blend in. */
    if (dr_subpic != NULL) {
        if (subpic != NULL)
            subpicture_Delete(subpic);
        subpic = dr_subpic;
    }

    assert(vout_IsDisplayFiltered(vd) == !sys->display.use_dr);
    if (sys->display.use_dr && !is_direct) {
        picture_t *direct = NULL;
        if (likely(vout->p->display_pool != NULL))
            direct = picture_pool_Get(vout->p->display_pool);
        if (!direct) {
            picture_Release(todisplay);
            if (subpic)
                subpicture_Delete(subpic);
            return VLC_EGENERIC;
        }

        /* The display uses direct rendering (no conversion), but its pool of
         * pictures is not usable by the decoder (too few, too slow or
         * subject to invalidation...). Since there are no filters, copying
         * pictures from the decoder to the output is unavoidable. */
        VideoFormatCopyCropAr(&direct->format, &todisplay->format);
        picture_Copy(direct, todisplay);
        picture_Release(todisplay);
        snap_pic = todisplay = direct;
    }

    /*
     * Take a snapshot if requested
     */
    if (do_snapshot)
    {
        assert(snap_pic);
        vout_snapshot_Set(&vout->p->snapshot, &vd->source, snap_pic);
        if (snap_pic != todisplay)
            picture_Release(snap_pic);
    }

    /* Render the direct buffer */
    vout_UpdateDisplaySourceProperties(vd, &todisplay->format);

    todisplay = vout_FilterDisplay(vd, todisplay);
    if (todisplay == NULL) {
        if (subpic != NULL)
            subpicture_Delete(subpic);
        return VLC_EGENERIC;
    }

    const vlc_tick_t profile_prepare_start = profile_on ? mdate() : 0;

    if (sys->display.use_dr) {
        vout_display_Prepare(vd, todisplay, subpic);
    } else {
        if (!do_dr_spu && !do_early_spu && vout->p->spu_blend && subpic)
            picture_BlendSubpicture(todisplay, vout->p->spu_blend, subpic);
        vout_display_Prepare(vd, todisplay, do_dr_spu ? subpic : NULL);

        if (!do_dr_spu && subpic)
        {
            subpicture_Delete(subpic);
            subpic = NULL;
        }
    }


    if (profile_on) {
        const vlc_tick_t profile_done = mdate();
        const vlc_tick_t total = profile_done - profile_start;
        vout_phase_profile.count++;
        vout_phase_profile.filter += profile_filter_done - profile_start;
        vout_phase_profile.spu += profile_spu_done - profile_filter_done;
        vout_phase_profile.core += profile_prepare_start - profile_spu_done;
        vout_phase_profile.prepare += profile_done - profile_prepare_start;
        vout_phase_profile.total += total;
        vout_phase_profile.predicted += profile_predicted;
        if (total > vout_phase_profile.worst)
            vout_phase_profile.worst = total;

        if (vout_phase_profile.count == 120) {
            msg_Dbg(vout, "vout render profile (120 frames): filter %d, "
                    "spu %d, core %d, prepare %d, total %d us/f, "
                    "worst %d, predicted %d",
                    (int)(vout_phase_profile.filter / 120),
                    (int)(vout_phase_profile.spu / 120),
                    (int)(vout_phase_profile.core / 120),
                    (int)(vout_phase_profile.prepare / 120),
                    (int)(vout_phase_profile.total / 120),
                    (int)vout_phase_profile.worst,
                    (int)(vout_phase_profile.predicted / 120));
            memset(&vout_phase_profile, 0, sizeof(vout_phase_profile));
        }
    }

    vout_chrono_Stop(&vout->p->render);
#if 0
        {
        static int i = 0;
        if (((i++)%10) == 0)
            msg_Info(vout, "render: avg %d ms var %d ms",
                     (int)(vout->p->render.avg/1000), (int)(vout->p->render.var/1000));
        }
#endif

    /* Wait the real date (for rendering jitter) */
#if 0
    vlc_tick_t delay = todisplay->date - mdate();
    if (delay < 1000)
        msg_Warn(vout, "picture is late (%lld ms)", delay / 1000);
#endif
    const vlc_tick_t target_date = todisplay->date;
    const vlc_tick_t presentation_advance =
        var_Type(vd, "vout-presentation-advance") != 0
            ? var_GetInteger(vd, "vout-presentation-advance") : 0;
    if (!is_forced)
        mwait(target_date - presentation_advance);

    /* Display the direct buffer returned by vout_RenderPicture */
    vout->p->displayed.date = mdate();
    vout_display_Display(vd, todisplay, subpic);

    vout_statistic_AddDisplayed(&vout->p->statistic, 1);

    /* Punctuality telemetry: how late past its date the swap really ran.
     * Scheduled pictures only -- pause refreshes and forced pictures
     * have no meaningful deadline. Reported at debug verbosity every
     * five seconds; the arithmetic itself is a handful of cycles. */
    if (!is_forced) {
        vlc_tick_t lateness = vout->p->displayed.date - target_date;
        vout->p->punctuality.count++;
        vout->p->punctuality.sum += lateness;
        if (lateness > vout->p->punctuality.worst)
            vout->p->punctuality.worst = lateness;
        if (lateness > 4000)
            vout->p->punctuality.late++;
        if (vout->p->punctuality.last_report == VLC_TICK_INVALID)
            vout->p->punctuality.last_report = vout->p->displayed.date;
        else if (vout->p->displayed.date - vout->p->punctuality.last_report
                 >= 5 * CLOCK_FREQ) {
            msg_Dbg(vout, "display punctuality: %u frames, avg %d us late, "
                    "worst %d us, >4ms: %u",
                    vout->p->punctuality.count,
                    (int)(vout->p->punctuality.sum
                          / __MAX(vout->p->punctuality.count, 1)),
                    (int)vout->p->punctuality.worst,
                    vout->p->punctuality.late);
            vout->p->punctuality.count = 0;
            vout->p->punctuality.late = 0;
            vout->p->punctuality.worst = 0;
            vout->p->punctuality.sum = 0;
            vout->p->punctuality.last_report = vout->p->displayed.date;
        }
    }

    return VLC_SUCCESS;
}

static int ThreadDisplayPicture(vout_thread_t *vout, vlc_tick_t *deadline)
{
    bool frame_by_frame = !deadline;
    /* A decode-cache hold behaves like pause here: show the first (forced)
     * picture, then stop popping so the fifo can fill. */
    bool paused = vout->p->pause.is_on || vout->p->cache_hold;
    bool first = !vout->p->displayed.current;

    if (first)
        if (ThreadDisplayPreparePicture(vout, true, frame_by_frame)) /* FIXME not sure it is ok */
            return VLC_EGENERIC;

    if (!paused || frame_by_frame)
        while (!vout->p->displayed.next && !ThreadDisplayPreparePicture(vout, false, frame_by_frame))
            ;

    /* A seek while paused flushes the decoder fifo, then queues its first
     * picture with b_force set.  Do not leave that picture behind the
     * already displayed pre-seek frame: consume and present it immediately.
     * Ordinary paused pictures remain queued until an explicit frame step. */
    bool forced_next = false;
    if (paused && !frame_by_frame && vout->p->displayed.current
     && !vout->p->displayed.next)
    {
        picture_t *head = picture_fifo_Peek(vout->p->decoder_fifo);
        forced_next = head != NULL && head->b_force;
        if (head != NULL)
            picture_Release(head);

        if (forced_next
         && ThreadDisplayPreparePicture(vout, false, false) != VLC_SUCCESS)
            forced_next = false;
    }

    const vlc_tick_t date = mdate();
    vout_display_t *vd = vout->p->display.vd;
    const vlc_tick_t presentation_advance =
        var_Type(vd, "vout-presentation-advance") != 0
            ? var_GetInteger(vd, "vout-presentation-advance") : 0;
    const vlc_tick_t render_advance =
        var_Type(vd, "vout-render-advance") != 0
            ? var_GetInteger(vd, "vout-render-advance")
            : presentation_advance;
    const vlc_tick_t render_delay = vout_chrono_GetHigh(&vout->p->render) + VOUT_MWAIT_TOLERANCE;

    bool drop_next_frame = frame_by_frame || forced_next;
    vlc_tick_t date_next = VLC_TICK_INVALID;
    if (!paused && vout->p->displayed.next) {
        date_next = vout->p->displayed.next->date - render_delay
                  - render_advance;
        if (date_next /* + 0 FIXME */ <= date)
            drop_next_frame = true;
        else if (date_next - date > CLOCK_FREQ * 60) {
            /* A head picture due more than a minute from now cannot be
             * real: even the deepest look-ahead cushion keeps its head
             * near the present, and a broken decoder timestamp landing
             * here would otherwise freeze the picture for good -- the
             * head is never due, everything behind it waits, and the
             * cushion gates the decoder shut (seen live 08/08/2026 with
             * hardware-decoder timestamp echoes). Say so and step over
             * it rather than waiting for an instant that never comes. */
            msg_Warn(vout, "head picture due %"PRId64"s from now: "
                     "broken timestamp, forcing it through",
                     (date_next - date) / CLOCK_FREQ);
            drop_next_frame = true;
        }
    }

    /* FIXME/XXX we must redisplay the last decoded picture (because
     * of potential vout updated, or filters update or SPU update)
     * For now a high update period is needed but it could be removed
     * if and only if:
     * - vout module emits events from theselves.
     * - *and* SPU is modified to emit an event or a deadline when needed.
     *
     * So it will be done later.
     */
    bool refresh = false;

    vlc_tick_t date_refresh = VLC_TICK_INVALID;
    if (vout->p->displayed.date > VLC_TICK_INVALID) {
        /* A paused vout shows a static picture: redisplaying it every
         * 80 ms only serves OSD/SPU updates, and those full renders
         * cost real CPU time on the old GPUs this branch targets.
         * Slow the refresh pump down while paused. */
        vlc_tick_t redisplay_delay = vout->p->pause.is_on            ? VOUT_REDISPLAY_DELAY * 6 : VOUT_REDISPLAY_DELAY;
        date_refresh = vout->p->displayed.date + redisplay_delay - render_delay;
        refresh = date_refresh <= date;
    }
    bool force_refresh = !drop_next_frame && refresh;

    if (!frame_by_frame) {
        if (date_refresh != VLC_TICK_INVALID)
            *deadline = date_refresh;
        if (date_next != VLC_TICK_INVALID && date_next < *deadline)
            *deadline = date_next;
    }

    if (!first && !refresh && !drop_next_frame) {
        return VLC_EGENERIC;
    }

    if (drop_next_frame) {
        picture_Release(vout->p->displayed.current);
        vout->p->displayed.current = vout->p->displayed.next;
        vout->p->displayed.next    = NULL;
    }

    if (!vout->p->displayed.current)
        return VLC_EGENERIC;

    /* display the picture immediately */
    bool is_forced = frame_by_frame || force_refresh || vout->p->displayed.current->b_force;
    int ret = ThreadDisplayRenderPicture(vout, is_forced);
    return force_refresh ? VLC_EGENERIC : ret;
}

static void ThreadDisplaySubpicture(vout_thread_t *vout,
                                    subpicture_t *subpicture)
{
    spu_PutSubpicture(vout->p->spu, subpicture);
}

static void ThreadFlushSubpicture(vout_thread_t *vout, int channel)
{
    spu_ClearChannel(vout->p->spu, channel);
}

static void ThreadDisplayOsdTitle(vout_thread_t *vout, const char *string)
{
    if (!vout->p->title.show)
        return;

    vout_OSDText(vout, VOUT_SPU_CHANNEL_OSD,
                 vout->p->title.position, INT64_C(1000) * vout->p->title.timeout,
                 string);
}

static void ThreadChangeSubSources(vout_thread_t *vout, const char *filters)
{
    spu_ChangeSources(vout->p->spu, filters);
}

static void ThreadChangeSubFilters(vout_thread_t *vout, const char *filters)
{
    spu_ChangeFilters(vout->p->spu, filters);
}

static void ThreadChangeSubMargin(vout_thread_t *vout, int margin)
{
    spu_ChangeMargin(vout->p->spu, margin);
}

static void ThreadChangePause(vout_thread_t *vout, bool is_paused, vlc_tick_t date)
{
    /* De-dup same-state applications: the look-ahead cache release
     * pushes the vout pause directly (so it lands BEFORE the unhold in
     * the control queue -- an async-only pause let the unheld vout race
     * through a fifo anchored at the pause date, dropping it whole) and
     * the decoder-side application of the same pause follows a beat
     * later. Without this guard that second application trips the
     * assert below. */
    if (vout->p->pause.is_on == is_paused)
        return;
    assert(!vout->p->pause.is_on || !is_paused);

    if (vout->p->pause.is_on) {
        const vlc_tick_t duration = date - vout->p->pause.date;

        if (vout->p->step.timestamp > VLC_TICK_INVALID)
            vout->p->step.timestamp += duration;
        if (vout->p->step.last > VLC_TICK_INVALID)
            vout->p->step.last += duration;
        picture_fifo_OffsetDate(vout->p->decoder_fifo, duration);
        if (vout->p->displayed.decoded)
            vout->p->displayed.decoded->date += duration;
        spu_OffsetSubtitleDate(vout->p->spu, duration);

        ThreadFilterFlush(vout, false);
    } else {
        vout->p->step.timestamp = VLC_TICK_INVALID;
        vout->p->step.last      = VLC_TICK_INVALID;
    }
    vout->p->pause.is_on = is_paused;
    vout->p->pause.date  = date;
    msg_Dbg(vout, is_paused ? "paused: static frame redisplay throttled"
                            : "resumed: normal redisplay interval");

    vout_window_t *window = vout->p->window;
    if (window != NULL)
        vout_window_SetInhibition(window, !is_paused);
}

static void ThreadChangeCacheHold(vout_thread_t *vout, bool hold)
{
    if (vout->p->cache_hold == hold)
        return;
    vout->p->cache_hold = hold;
    msg_Dbg(vout, hold ? "decode cache fill: holding display"
                       : "decode cache fill: hold released");
}

static void ThreadChangeStaticFrameHold(vout_thread_t *vout, bool hold)
{
    if (vout->p->static_frame_hold == hold)
        return;
    vout->p->static_frame_hold = hold;
    msg_Dbg(vout, hold ? "disc menu: preserving the last video frame"
                       : "disc menu: last-frame hold released");
}

static void ThreadChangeInteractiveOverlay(vout_thread_t *vout, bool active)
{
    if (vout->p->crop.interactive_overlay == active)
        return;

    vout->p->crop.interactive_overlay = active;
    if (!vout->p->crop.automatic)
        return;

    /* The detector's border is expressed in video pixels, whereas an HDMV
     * or BD-J button keeps the coordinates authored for the complete raster.
     * Restore that raster immediately and discard menu samples so the feature
     * is measured independently when the graphics plane closes. */
    if (vout->p->crop.detector != NULL)
        vout_autocrop_Reset(vout->p->crop.detector);
    ThreadSetCropBorder(vout, 0, 0, 0, 0);
    msg_Dbg(vout, active ? "disc menu: automatic crop suspended"
                         : "disc menu: automatic crop resumed");
}

static void ThreadFlush(vout_thread_t *vout, bool below, vlc_tick_t date)
{
    vout->p->step.timestamp = VLC_TICK_INVALID;
    vout->p->step.last      = VLC_TICK_INVALID;

    /* A flush ends any decode-cache fill episode (seek, stop): the held
     * pictures are dropped right below, holding further would wedge the
     * next episode's display. */
    ThreadChangeCacheHold(vout, false);

    /* Decoder recycling normally clears displayed.current. An HDMV menu can
     * enter an infinite still at exactly that boundary: the display retains
     * its old front buffer, but without our own picture reference the vout
     * cannot blend a new button highlight into it. Keep one reference across
     * the filter flush only while the disc demux explicitly requests it. */
    picture_t *static_frame = NULL;
    if (vout->p->static_frame_hold && vout->p->displayed.current != NULL)
        static_frame = picture_Hold(vout->p->displayed.current);

    ThreadFilterFlush(vout, false); /* FIXME too much */

    /* displayed.next is outside decoder_fifo, but it is still a queued
     * pre-seek picture and may own the last direct-rendering buffer. Apply
     * the same date rule as the fifo instead of letting a paused seek expose
     * that stale image (or deadlock waiting for its buffer). */
    picture_t *next = vout->p->displayed.next;
    if (next && ((below && next->date <= date) ||
                 (!below && next->date >= date))) {
        picture_Release(next);
        vout->p->displayed.next = NULL;
    }

    picture_t *last = vout->p->displayed.decoded;
    if (last) {
        if (( below && last->date <= date) ||
            (!below && last->date >= date)) {
            picture_Release(last);

            vout->p->displayed.decoded   = NULL;
            vout->p->displayed.date      = VLC_TICK_INVALID;
            vout->p->displayed.timestamp = VLC_TICK_INVALID;
        }
    }

    if (static_frame != NULL) {
        vout->p->displayed.current = static_frame;
        /* Re-arm the periodic static-picture/SPU refresh pump. */
        vout->p->displayed.date = mdate();
        vout->p->displayed.timestamp = VLC_TICK_INVALID;
    }

    picture_fifo_Flush(vout->p->decoder_fifo, date, below);
    vout_FilterFlush(vout->p->display.vd);
}

static void ThreadStep(vout_thread_t *vout, vlc_tick_t *duration)
{
    *duration = 0;

    if (vout->p->step.last <= VLC_TICK_INVALID)
        vout->p->step.last = vout->p->displayed.timestamp;

    if (ThreadDisplayPicture(vout, NULL))
        return;

    vout->p->step.timestamp = vout->p->displayed.timestamp;

    if (vout->p->step.last > VLC_TICK_INVALID &&
        vout->p->step.timestamp > vout->p->step.last) {
        *duration = vout->p->step.timestamp - vout->p->step.last;
        vout->p->step.last = vout->p->step.timestamp;
        /* TODO advance subpicture by the duration ... */
    }
}

static void ThreadChangeFullscreen(vout_thread_t *vout, bool fullscreen)
{
    vout_window_t *window = vout->p->window;

#if !defined(_WIN32) && !defined(__OS2__)
    if (window != NULL)
        vout_window_SetFullScreen(window, fullscreen);
#else
    bool window_fullscreen = false;
    if (window != NULL
     && vout_window_SetFullScreen(window, fullscreen) == VLC_SUCCESS)
        window_fullscreen = true;
    /* FIXME: remove this event */
    if (vout->p->display.vd != NULL)
        vout_display_SendEventFullscreen(vout->p->display.vd, fullscreen, window_fullscreen);
#endif
}

static void ThreadChangeWindowState(vout_thread_t *vout, unsigned state)
{
    vout_window_t *window = vout->p->window;

    if (window != NULL)
        vout_window_SetState(window, state);
#if defined(_WIN32) || defined(__OS2__)
    else /* FIXME: remove this event */
    if (vout->p->display.vd != NULL)
        vout_display_SendWindowState(vout->p->display.vd, state);
#endif
}

static void ThreadChangeWindowMouse(vout_thread_t *vout,
                                    const vout_window_mouse_event_t *mouse)
{
    vout_display_t *vd = vout->p->display.vd;
    switch (mouse->type)
    {
        case VOUT_WINDOW_MOUSE_STATE:
        case VOUT_WINDOW_MOUSE_MOVED:
        {
            vout_display_place_t place;
            vout_display_PlacePicture(&place, &vd->source, vd->cfg, false);

            if (place.width <= 0 || place.height <= 0)
                return;

            const int x = vd->source.i_x_offset +
                (int64_t)(mouse->x - place.x) *
                vd->source.i_visible_width / place.width;
            const int y = vd->source.i_y_offset +
                (int64_t)(mouse->y - place.y) *
                vd->source.i_visible_height/ place.height;

            if (mouse->type == VOUT_WINDOW_MOUSE_STATE)
                vout_display_SendEventMouseState(vd, x, y, mouse->button_mask);
            else
                vout_display_SendEventMouseMoved(vd, x, y);
            break;
        }
        case VOUT_WINDOW_MOUSE_PRESSED:
            vout_display_SendEventMousePressed(vd, mouse->button_mask);
            break;
        case VOUT_WINDOW_MOUSE_RELEASED:
            vout_display_SendEventMouseReleased(vd, mouse->button_mask);
            break;
        case VOUT_WINDOW_MOUSE_DOUBLE_CLICK:
            if (mouse->button_mask == 0)
                vout_display_SendEventMouseDoubleClick(vd);
            else
                vout_display_SendEventMousePressed(vd, mouse->button_mask);
            break;
        default: vlc_assert_unreachable();
            break;
    }
}

static void ThreadChangeDisplayFilled(vout_thread_t *vout, bool is_filled)
{
    vout_SetDisplayFilled(vout->p->display.vd, is_filled);
}

static void ThreadChangeZoom(vout_thread_t *vout, int num, int den)
{
    if (num * 10 < den) {
        num = den;
        den *= 10;
    } else if (num > den * 10) {
        num = den * 10;
    }

    vout_SetDisplayZoom(vout->p->display.vd, num, den);
}

static void ThreadChangeAspectRatio(vout_thread_t *vout,
                                    unsigned num, unsigned den)
{
    vout_SetDisplayAspect(vout->p->display.vd, num, den);
}


/* Pushes vout->p->crop down to the display. Called both when the crop
 * changes and when a display has just been (re)created, which is the only
 * way a crop survives an input format change. */
static void ThreadApplyCrop(vout_thread_t *vout)
{
    vout_display_t *vd = vout->p->display.vd;
    if (vd == NULL)
        return;

    /* A crop counted in pixels is meaningless on a source of another size:
     * an adaptive stream that comes back at another resolution would be
     * cropped by a border measured on the previous one. Drop it -- when the
     * detection is running it will have measured the new source within the
     * second. */
    if (vout->p->crop.mode != VOUT_CROP_RATIO &&
        (vout->p->crop.src_width  != vout->p->original.i_visible_width ||
         vout->p->crop.src_height != vout->p->original.i_visible_height)) {
        vout->p->crop.mode = VOUT_CROP_RATIO;
        vout->p->crop.num  = 0;
        vout->p->crop.den  = 0;
    }

    switch (vout->p->crop.mode) {
    case VOUT_CROP_WINDOW:
        vout_SetDisplayCrop(vd, 0, 0,
                            vout->p->crop.x, vout->p->crop.y,
                            vout->p->crop.width, vout->p->crop.height);
        break;
    case VOUT_CROP_BORDER:
        vout_SetDisplayCrop(vd, 0, 0,
                            vout->p->crop.left, vout->p->crop.top,
                            -(int)vout->p->crop.right,
                            -(int)vout->p->crop.bottom);
        break;
    case VOUT_CROP_RATIO:
    default:
        vout_SetDisplayCrop(vd, vout->p->crop.num, vout->p->crop.den,
                            0, 0, 0, 0);
        break;
    }
}

/* Both crops expressed in pixels only mean something for the source they
 * were measured on. */
static void ThreadRecordCropSource(vout_thread_t *vout)
{
    vout->p->crop.src_width  = vout->p->original.i_visible_width;
    vout->p->crop.src_height = vout->p->original.i_visible_height;
}

static void ThreadSetCropBorder(vout_thread_t *vout,
                                unsigned left, unsigned top,
                                unsigned right, unsigned bottom)
{
    vout->p->crop.mode   = VOUT_CROP_BORDER;
    vout->p->crop.left   = left;
    vout->p->crop.top    = top;
    vout->p->crop.right  = right;
    vout->p->crop.bottom = bottom;
    ThreadRecordCropSource(vout);
    ThreadApplyCrop(vout);
}

/* Any explicit crop takes the automatic detection out of the picture: it is
 * one more "crop" menu entry, and picking another one leaves it. */
static void ThreadStopCropAuto(vout_thread_t *vout)
{
    vout->p->crop.automatic = false;
}

static void ThreadExecuteCropWindow(vout_thread_t *vout,
                                    unsigned x, unsigned y,
                                    unsigned width, unsigned height)
{
    ThreadStopCropAuto(vout);
    vout->p->crop.mode   = VOUT_CROP_WINDOW;
    vout->p->crop.x      = x;
    vout->p->crop.y      = y;
    vout->p->crop.width  = width;
    vout->p->crop.height = height;
    ThreadRecordCropSource(vout);
    ThreadApplyCrop(vout);
}
static void ThreadExecuteCropBorder(vout_thread_t *vout,
                                    unsigned left, unsigned top,
                                    unsigned right, unsigned bottom)
{
    msg_Dbg(vout, "ThreadExecuteCropBorder %d.%d %dx%d", left, top, right, bottom);
    ThreadStopCropAuto(vout);
    ThreadSetCropBorder(vout, left, top, right, bottom);
}

static void ThreadExecuteCropRatio(vout_thread_t *vout,
                                   unsigned num, unsigned den)
{
    ThreadStopCropAuto(vout);
    vout->p->crop.mode = VOUT_CROP_RATIO;
    vout->p->crop.num  = num;
    vout->p->crop.den  = den;
    ThreadRecordCropSource(vout);
    ThreadApplyCrop(vout);
}

static void ThreadExecuteCropAuto(vout_thread_t *vout)
{
    /* MVC is stored as two vertically adjacent eyes. Treating that buffer as
     * one photograph makes the detector crop the cinema bars once across the
     * combined 8:9 surface, cutting both eyes at their inner edge and breaking
     * HDMI frame-packing geometry. A future stereo-aware detector can analyse
     * one eye and mirror its result; until then preserve the complete views. */
    if (vout->p->original.multiview_mode == MULTIVIEW_STEREO_FRAMEPACKED ||
        vout->p->crop.interactive_overlay) {
        vout->p->crop.automatic = true;
        ThreadSetCropBorder(vout, 0, 0, 0, 0);
        return;
    }

    if (vout->p->crop.detector == NULL) {
        vout->p->crop.detector = vout_autocrop_New(VLC_OBJECT(vout));
        if (vout->p->crop.detector == NULL)
            return;
    }
    /* Only a fresh switch to automatic starts the measurement over. This
     * command is also replayed by vout_IntfReinit at every input format
     * change, i.e. at every turn of a looping stream: throwing the samples
     * away there would make the detector redo its refinement pass and move
     * the window a second time, every time round. */
    if (!vout->p->crop.automatic)
        vout_autocrop_Reset(vout->p->crop.detector);
    vout->p->crop.automatic = true;

    /* Coming back to a source already measured (a looping stream, a title
     * change) -- crop it straight away instead of showing the black bars
     * again for the second it takes to measure them anew. */
    vout_autocrop_border_t border;
    if (vout_autocrop_Restore(vout->p->crop.detector,
                              vout->p->original.i_visible_width,
                              vout->p->original.i_visible_height, &border))
        ThreadSetCropBorder(vout, border.left, border.top,
                            border.right, border.bottom);
    else
        ThreadSetCropBorder(vout, 0, 0, 0, 0);
}

/* ⚠ Everything the detection learned belongs to the item that was
 * playing. Carrying it into the next one applies its mat to an unrelated
 * source -- and it does not even need the same resolution to do so, since
 * a border measured on a frame of the same *shape* is scaled to fit (that
 * is what puts a film's 2.39 letterbox on the 4:3 programme that follows
 * it). The vout survives an item change; this memory must not. */
static void ThreadForgetCrop(vout_thread_t *vout)
{
    /* A crop the viewer set by hand is theirs, and upstream carries it
     * over as well: only what the detection decided is dropped. */
    if (!vout->p->crop.automatic)
        return;

    if (vout->p->crop.detector != NULL)
        vout_autocrop_Forget(vout->p->crop.detector);

    vout->p->crop.mode = VOUT_CROP_RATIO;
    vout->p->crop.num  = 0;
    vout->p->crop.den  = 0;
    ThreadApplyCrop(vout);
}

/* Sampled from the display loop, on the pictures on their way out. */
static void ThreadUpdateCropAuto(vout_thread_t *vout, picture_t *picture)
{
    if (!vout->p->crop.automatic || vout->p->crop.detector == NULL)
        return;
    if (vout->p->original.multiview_mode == MULTIVIEW_STEREO_FRAMEPACKED ||
        vout->p->crop.interactive_overlay)
        return;

    vout_autocrop_border_t border;
    if (vout_autocrop_Feed(vout->p->crop.detector, picture, mdate(), &border))
        ThreadSetCropBorder(vout, border.left, border.top,
                            border.right, border.bottom);
}

static void ThreadExecuteViewpoint(vout_thread_t *vout,
                                   const vlc_viewpoint_t *p_viewpoint)
{
    vout_SetDisplayViewpoint(vout->p->display.vd, p_viewpoint);
}

static int ThreadStart(vout_thread_t *vout, vout_display_state_t *state)
{
    vlc_mouse_Init(&vout->p->mouse);
    vout->p->decoder_fifo = picture_fifo_New();
    vout->p->decoder_pool = NULL;
    vout->p->display_pool = NULL;
    vout->p->private_pool = NULL;

    vout->p->filter.configuration = NULL;
    video_format_Copy(&vout->p->filter.format, &vout->p->original);

    filter_owner_t owner = {
        .sys = vout,
        .video = {
            .buffer_new = VoutVideoFilterStaticNewPicture,
        },
    };
    vout->p->filter.chain_static =
        filter_chain_NewVideo( vout, true, &owner );

    owner.video.buffer_new = VoutVideoFilterInteractiveNewPicture;
    vout->p->filter.chain_interactive =
        filter_chain_NewVideo( vout, true, &owner );

    vout_display_state_t state_default;
    if (!state) {
        VoutGetDisplayCfg(vout, &state_default.cfg, vout->p->display.title);

#if defined(_WIN32) || defined(__OS2__)
        bool below = var_InheritBool(vout, "video-wallpaper");
        bool above = var_InheritBool(vout, "video-on-top");

        state_default.wm_state = below ? VOUT_WINDOW_STATE_BELOW
                               : above ? VOUT_WINDOW_STATE_ABOVE
                               : VOUT_WINDOW_STATE_NORMAL;
#endif
        state_default.sar.num = 0;
        state_default.sar.den = 0;

        state = &state_default;
    }

    if (vout_OpenWrapper(vout, vout->p->splitter_name, state))
        goto error;
    if (vout_InitWrapper(vout))
    {
        vout_CloseWrapper(vout, state);
        goto error;
    }
    assert(vout->p->decoder_pool && vout->p->private_pool);

    vout->p->displayed.current       = NULL;
    vout->p->displayed.next          = NULL;
    vout->p->displayed.decoded       = NULL;
    vout->p->displayed.date          = VLC_TICK_INVALID;
    vout->p->displayed.timestamp     = VLC_TICK_INVALID;
    vout->p->displayed.is_interlaced = false;

    vout->p->step.last               = VLC_TICK_INVALID;
    vout->p->step.timestamp          = VLC_TICK_INVALID;

    vout->p->spu_blend_chroma        = 0;
    vout->p->spu_blend               = NULL;

    /* A brand new display crops nothing. Hand it back the crop that was in
     * force, before it has shown (and sized its window on) a single
     * picture -- otherwise every input format change, and therefore every
     * turn of a looping stream, flashes the uncropped frame and moves the
     * window twice. */
    if (vout->p->crop.automatic &&
        vout->p->original.multiview_mode == MULTIVIEW_STEREO_FRAMEPACKED) {
        vout->p->crop.mode = VOUT_CROP_RATIO;
        vout->p->crop.num = vout->p->crop.den = 0;
    }
    else if (vout->p->crop.automatic && vout->p->crop.detector != NULL) {
        vout_autocrop_border_t border;
        if (vout_autocrop_Restore(vout->p->crop.detector,
                                  vout->p->original.i_visible_width,
                                  vout->p->original.i_visible_height,
                                  &border)) {
            vout->p->crop.mode   = VOUT_CROP_BORDER;
            vout->p->crop.left   = border.left;
            vout->p->crop.top    = border.top;
            vout->p->crop.right  = border.right;
            vout->p->crop.bottom = border.bottom;
            vout->p->crop.src_width  = vout->p->original.i_visible_width;
            vout->p->crop.src_height = vout->p->original.i_visible_height;
        }
    }
    ThreadApplyCrop(vout);
    /* ...and hand it to the display right away rather than at the first
     * picture: on a stream that re-buffers after the format change (an
     * adaptive one, every time it switches variant) that is a second or
     * more during which the window has already taken the shape of the
     * uncropped frame. */
    vout_ManageWrapper(vout);

    video_format_Print(VLC_OBJECT(vout), "original format", &vout->p->original);
    return VLC_SUCCESS;
error:
    if (vout->p->filter.chain_interactive != NULL)
    {
        ThreadDelAllFilterCallbacks(vout);
        filter_chain_Delete(vout->p->filter.chain_interactive);
    }
    if (vout->p->filter.chain_static != NULL)
        filter_chain_Delete(vout->p->filter.chain_static);
    video_format_Clean(&vout->p->filter.format);
    if (vout->p->decoder_fifo != NULL)
        picture_fifo_Delete(vout->p->decoder_fifo);
    return VLC_EGENERIC;
}

static void ThreadStop(vout_thread_t *vout, vout_display_state_t *state)
{
    /* A real display teardown cannot retain a buffer owned by its pool. */
    vout->p->static_frame_hold = false;

    if (vout->p->spu_blend)
        filter_DeleteBlend(vout->p->spu_blend);

    /* Destroy translation tables */
    if (vout->p->display.vd) {
        if (vout->p->decoder_pool) {
            ThreadFlush(vout, true, INT64_MAX);
            vout_EndWrapper(vout);
        }
        vout_CloseWrapper(vout, state);
    }

    /* Destroy the video filters */
    ThreadDelAllFilterCallbacks(vout);
    filter_chain_Delete(vout->p->filter.chain_interactive);
    filter_chain_Delete(vout->p->filter.chain_static);
    video_format_Clean(&vout->p->filter.format);
    free(vout->p->filter.configuration);

    if (vout->p->decoder_fifo)
        picture_fifo_Delete(vout->p->decoder_fifo);
    assert(!vout->p->decoder_pool);
}

static void ThreadInit(vout_thread_t *vout)
{
    vout->p->dead            = false;
    vout->p->is_late_dropped = var_InheritBool(vout, "drop-late-frames");
    vout->p->pause.is_on     = false;
    vout->p->pause.date      = VLC_TICK_INVALID;
    vout->p->cache_hold      = false;
    vout->p->static_frame_hold = false;
    vout->p->crop.interactive_overlay = false;
    vout->p->cache_headroom  = 0;
    vout->p->punctuality.count = 0;
    vout->p->punctuality.late = 0;
    vout->p->punctuality.worst = 0;
    vout->p->punctuality.sum = 0;
    vout->p->punctuality.last_report = VLC_TICK_INVALID;

    vout_chrono_Init(&vout->p->render, 5, 10000); /* Arbitrary initial time */
}

static void ThreadClean(vout_thread_t *vout)
{
    if (vout->p->crop.detector != NULL) {
        vout_autocrop_Delete(vout->p->crop.detector);
        vout->p->crop.detector = NULL;
    }
    vout_chrono_Clean(&vout->p->render);
    vout->p->dead = true;
    vout_control_Dead(&vout->p->control);
}

static int ThreadReinit(vout_thread_t *vout,
                        const vout_configuration_t *cfg)
{
    video_format_t original;
    const bool force_display_restart =
        var_GetBool(vout, "powervlc-force-display-restart");

    vout->p->pause.is_on = false;
    vout->p->pause.date  = VLC_TICK_INVALID;

    if (VoutValidateFormat(&original, cfg->fmt)) {
        ThreadStop(vout, NULL);
        ThreadClean(vout);
        return VLC_EGENERIC;
    }

    /* We ignore ar changes at this point, they are dynamically supported.
     * #19268: don't ignore crop changes (fix vouts using the crop size of the
     * previous format). */
    vout->p->original.i_sar_num = original.i_sar_num;
    vout->p->original.i_sar_den = original.i_sar_den;
    if (!force_display_restart &&
        video_format_IsSimilar(&original, &vout->p->original)) {
        if (cfg->dpb_size <= vout->p->dpb_size) {
            video_format_Clean(&original);
            return VLC_SUCCESS;
        }
        msg_Warn(vout, "DPB need to be increased");
    }

    vout_display_state_t state;
    memset(&state, 0, sizeof(state));

    /* Look-ahead cache state belongs to the POOL, so it may only be
     * dropped on the path that actually tears the pool down -- the two
     * early returns above keep the existing pool and must keep its
     * headroom with it. Clearing it at the top of the function instead
     * silently killed the cache for the rest of the session on every
     * decoder restart that reuses the vout (an input format change: a
     * Blu-ray title started from a menu, a DVD domain switch), since
     * nothing re-runs vout_InitWrapper to recompute it: the target
     * clamps to a zero headroom, falls under the direct-rendering
     * viability floor and the feature turns itself off. */
    vout->p->cache_hold  = false;
    vout->p->cache_headroom = 0;

    /* A decoder/format transition reopens the display module while retaining
     * this vout object. macosx.m uses this narrow window to transfer an
     * already-active HDMI 3D session to the replacement display instead of
     * restoring the 4K desktop between an MVC clip and a 2D menu. */
    var_Create(vout, "stereo3d-vout-reinit", VLC_VAR_BOOL);
    var_SetBool(vout, "stereo3d-vout-reinit", true);
    ThreadStop(vout, &state);

#ifdef __linux__
    if (force_display_restart) {
        const char *path = getenv("POWERVLC_KMS3D_RELEASED");
        if (path != NULL && *path != '\0') {
            FILE *marker = fopen(path, "w");
            if (marker != NULL) {
                fputs("released\n", marker);
                fclose(marker);
            }
        }
    }
#endif

    vout_ReinitInterlacingSupport(vout);

#if defined(_WIN32) || defined(__OS2__)
    if (!state.cfg.is_fullscreen)
#endif
    {
        state.cfg.display.width  = 0;
        state.cfg.display.height = 0;
    }
    state.sar.num = 0;
    state.sar.den = 0;

    /* FIXME current vout "variables" are not in sync here anymore
     * and I am not sure what to do */
    if (state.cfg.display.sar.num <= 0 || state.cfg.display.sar.den <= 0) {
        state.cfg.display.sar.num = 1;
        state.cfg.display.sar.den = 1;
    }
    if (state.cfg.zoom.num <= 0 || state.cfg.zoom.den <= 0) {
        state.cfg.zoom.num = 1;
        state.cfg.zoom.den = 1;
    }

    vout->p->original = original;
    vout->p->dpb_size = cfg->dpb_size;
    if (ThreadStart(vout, &state)) {
        var_SetBool(vout, "stereo3d-vout-reinit", false);
        var_SetBool(vout, "powervlc-force-display-restart", false);
        ThreadClean(vout);
        return VLC_EGENERIC;
    }
    var_SetBool(vout, "stereo3d-vout-reinit", false);
    var_SetBool(vout, "powervlc-force-display-restart", false);
#ifdef __linux__
    if (force_display_restart) {
        const char *path = getenv("POWERVLC_KMS3D_ACTIVE");
        if (path != NULL && *path != '\0') {
            FILE *marker = fopen(path, "w");
            if (marker != NULL) {
                fputs("active\n", marker);
                fclose(marker);
            }
        }
    }
#endif
    return VLC_SUCCESS;
}

static int ThreadRestartDisplay(vout_thread_t *vout)
{
    vout_display_state_t state;
    memset(&state, 0, sizeof(state));

    /* Exchange the display backend on its owning vout thread. This works for
     * moving video and interactive stills alike while leaving the decoder,
     * input and BD-J VM untouched. */
    vout->p->cache_hold = false;
    vout->p->cache_headroom = 0;
    var_Create(vout, "stereo3d-vout-reinit", VLC_VAR_BOOL);
    var_SetBool(vout, "stereo3d-vout-reinit", true);
    ThreadStop(vout, &state);
#ifdef __linux__
    const char *released_path = getenv("POWERVLC_KMS3D_RELEASED");
    if (released_path != NULL && *released_path != '\0') {
        FILE *marker = fopen(released_path, "w");
        if (marker != NULL) {
            fputs("released\n", marker);
            fclose(marker);
        }
    }
#endif
    vout_ReinitInterlacingSupport(vout);

    state.cfg.display.width = 0;
    state.cfg.display.height = 0;
    state.sar.num = state.sar.den = 0;
    if (state.cfg.display.sar.num <= 0 || state.cfg.display.sar.den <= 0)
        state.cfg.display.sar.num = state.cfg.display.sar.den = 1;
    if (state.cfg.zoom.num <= 0 || state.cfg.zoom.den <= 0)
        state.cfg.zoom.num = state.cfg.zoom.den = 1;

    if (ThreadStart(vout, &state)) {
        var_SetBool(vout, "stereo3d-vout-reinit", false);
        var_SetBool(vout, "powervlc-force-display-restart", false);
        ThreadClean(vout);
        return VLC_EGENERIC;
    }
    var_SetBool(vout, "stereo3d-vout-reinit", false);
    var_SetBool(vout, "powervlc-force-display-restart", false);
#ifdef __linux__
    const char *active_path = getenv("POWERVLC_KMS3D_ACTIVE");
    if (active_path != NULL && *active_path != '\0') {
        FILE *marker = fopen(active_path, "w");
        if (marker != NULL) {
            fputs("active\n", marker);
            fclose(marker);
        }
    }
#endif
    return VLC_SUCCESS;
}

static void ThreadCancel(vout_thread_t *vout, bool canceled)
{
    picture_pool_Cancel(vout->p->decoder_pool, canceled);
}

static int ThreadControl(vout_thread_t *vout, vout_control_cmd_t cmd)
{
    switch(cmd.type) {
    case VOUT_CONTROL_INIT:
        ThreadInit(vout);
        if (ThreadStart(vout, NULL))
        {
            ThreadClean(vout);
            return 1;
        }
        break;
    case VOUT_CONTROL_CLEAN:
        ThreadStop(vout, NULL);
        ThreadClean(vout);
        return 1;
    case VOUT_CONTROL_REINIT:
        if (ThreadReinit(vout, cmd.u.cfg))
            return 1;
        break;
    case VOUT_CONTROL_RESTART_DISPLAY:
        if (ThreadRestartDisplay(vout))
            return 1;
        break;
    case VOUT_CONTROL_CANCEL:
        ThreadCancel(vout, cmd.u.boolean);
        break;
    case VOUT_CONTROL_SUBPICTURE:
        ThreadDisplaySubpicture(vout, cmd.u.subpicture);
        cmd.u.subpicture = NULL;
        msg_Dbg(vout, "subpicture queued, displayed current=%p",
                (void *)vout->p->displayed.current);
        if (vout->p->displayed.current != NULL &&
            (vout->p->pause.is_on || vout->p->static_frame_hold))
            ThreadDisplayRenderPicture(vout, true);
        break;
    case VOUT_CONTROL_REFRESH_SUBPICTURE:
        msg_Dbg(vout, "subpicture refresh, displayed current=%p",
                (void *)vout->p->displayed.current);
        if (vout->p->displayed.current != NULL &&
            (vout->p->pause.is_on || vout->p->static_frame_hold))
            ThreadDisplayRenderPicture(vout, true);
        break;
    case VOUT_CONTROL_FLUSH_SUBPICTURE:
        ThreadFlushSubpicture(vout, cmd.u.integer);
        break;
    case VOUT_CONTROL_OSD_TITLE:
        ThreadDisplayOsdTitle(vout, cmd.u.string);
        break;
    case VOUT_CONTROL_CHANGE_FILTERS:
        ThreadChangeFilters(vout, NULL,
                            cmd.u.string != NULL ?
                            cmd.u.string : vout->p->filter.configuration,
                            -1, false);
        break;
    case VOUT_CONTROL_CHANGE_INTERLACE:
        ThreadChangeFilters(vout, NULL, vout->p->filter.configuration,
                            cmd.u.boolean ? 1 : 0, false);
        break;
    case VOUT_CONTROL_CHANGE_SUB_SOURCES:
        ThreadChangeSubSources(vout, cmd.u.string);
        break;
    case VOUT_CONTROL_CHANGE_SUB_FILTERS:
        ThreadChangeSubFilters(vout, cmd.u.string);
        break;
    case VOUT_CONTROL_CHANGE_SUB_MARGIN:
        ThreadChangeSubMargin(vout, cmd.u.integer);
        break;
    case VOUT_CONTROL_PAUSE:
        ThreadChangePause(vout, cmd.u.pause.is_on, cmd.u.pause.date);
        break;
    case VOUT_CONTROL_CACHE_HOLD:
        ThreadChangeCacheHold(vout, cmd.u.boolean);
        break;
    case VOUT_CONTROL_STATIC_FRAME_HOLD:
        ThreadChangeStaticFrameHold(vout, cmd.u.boolean);
        break;
    case VOUT_CONTROL_INTERACTIVE_OVERLAY:
        ThreadChangeInteractiveOverlay(vout, cmd.u.boolean);
        break;
    case VOUT_CONTROL_FLUSH:
        ThreadFlush(vout, false, cmd.u.time);
        break;
    case VOUT_CONTROL_STEP:
        ThreadStep(vout, cmd.u.time_ptr);
        break;
    case VOUT_CONTROL_FULLSCREEN:
        ThreadChangeFullscreen(vout, cmd.u.boolean);
        break;
    case VOUT_CONTROL_WINDOW_STATE:
        ThreadChangeWindowState(vout, cmd.u.integer);
        break;
    case VOUT_CONTROL_WINDOW_MOUSE:
        ThreadChangeWindowMouse(vout, &cmd.u.window_mouse);
        break;
    case VOUT_CONTROL_DISPLAY_FILLED:
        ThreadChangeDisplayFilled(vout, cmd.u.boolean);
        break;
    case VOUT_CONTROL_ZOOM:
        ThreadChangeZoom(vout, cmd.u.pair.a, cmd.u.pair.b);
        break;
    case VOUT_CONTROL_ASPECT_RATIO:
        ThreadChangeAspectRatio(vout, cmd.u.pair.a, cmd.u.pair.b);
        break;
    case VOUT_CONTROL_CROP_RATIO:
        ThreadExecuteCropRatio(vout, cmd.u.pair.a, cmd.u.pair.b);
        break;
    case VOUT_CONTROL_CROP_WINDOW:
        ThreadExecuteCropWindow(vout,
                cmd.u.window.x, cmd.u.window.y,
                cmd.u.window.width, cmd.u.window.height);
        break;
    case VOUT_CONTROL_CROP_BORDER:
        ThreadExecuteCropBorder(vout,
                cmd.u.border.left,  cmd.u.border.top,
                cmd.u.border.right, cmd.u.border.bottom);
        break;
    case VOUT_CONTROL_CROP_AUTO:
        ThreadExecuteCropAuto(vout);
        break;
    case VOUT_CONTROL_CROP_FORGET:
        ThreadForgetCrop(vout);
        break;
    case VOUT_CONTROL_VIEWPOINT:
        ThreadExecuteViewpoint(vout, &cmd.u.viewpoint);
        break;
    default:
        break;
    }
    vout_control_cmd_Clean(&cmd);
    return 0;
}

/*****************************************************************************
 * Thread: video output thread
 *****************************************************************************
 * Video output thread. This function does only returns when the thread is
 * terminated. It handles the pictures arriving in the video heap and the
 * display device events.
 *****************************************************************************/
static void *Thread(void *object)
{
    vout_thread_t *vout = object;
    vout_thread_sys_t *sys = vout->p;

    vlc_tick_t deadline = VLC_TICK_INVALID;
    bool wait = false;
    for (;;) {
        vout_control_cmd_t cmd;

        if (wait)
        {
            const vlc_tick_t max_deadline = mdate() + 100000;
            deadline = deadline <= VLC_TICK_INVALID ? max_deadline : __MIN(deadline, max_deadline);
        } else {
            deadline = VLC_TICK_INVALID;
        }
        while (!vout_control_Pop(&sys->control, &cmd, deadline))
            if (ThreadControl(vout, cmd))
                return NULL;

        deadline = VLC_TICK_INVALID;
        wait = ThreadDisplayPicture(vout, &deadline) != VLC_SUCCESS;

        const bool picture_interlaced = sys->displayed.is_interlaced;

        vout_SetInterlacingState(vout, picture_interlaced);
        vout_ManageWrapper(vout);
    }
}
