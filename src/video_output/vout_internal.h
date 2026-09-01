/*****************************************************************************
 * vout_internal.h : Internal vout definitions
 *****************************************************************************
 * Copyright (C) 2008 VLC authors and VideoLAN
 * Copyright (C) 2008 Laurent Aimar
 * $Id$
 *
 * Authors: Laurent Aimar < fenrir _AT_ videolan _DOT_ org >
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

#ifndef LIBVLC_VOUT_INTERNAL_H
#define LIBVLC_VOUT_INTERNAL_H 1

#include <vlc_picture_fifo.h>
#include <vlc_picture_pool.h>
#include <vlc_vout_display.h>
#include <vlc_vout_wrapper.h>
#include "vout_control.h"
#include "control.h"
#include "snapshot.h"
#include "statistic.h"
#include "chrono.h"
#include "vout_autocrop.h"

/* It should be high enough to absorbe jitter due to difficult picture(s)
 * to decode but not too high as memory is not that cheap.
 *
 * It can be made lower at compilation time if needed, but performance
 * may be degraded.
 */
#define VOUT_MAX_PICTURES (20)

/* */
struct vout_thread_sys_t
{
    /* Splitter module if used */
    char            *splitter_name;

    /* Input thread for dvd menu interactions */
    vlc_object_t    *input;

    /* */
    video_format_t  original;   /* Original format ie coming from the decoder */
    unsigned        dpb_size;

    /* Snapshot interface */
    vout_snapshot_t snapshot;

    /* Statistics */
    vout_statistic_t statistic;

    /* Subpicture unit */
    vlc_mutex_t     spu_lock;
    spu_t           *spu;
    vlc_fourcc_t    spu_blend_chroma;
    filter_t        *spu_blend;

    /* Video output window */
    vout_window_t   *window;

    /* Thread & synchronization */
    vlc_thread_t    thread;
    bool            dead;
    vout_control_t  control;

    /* */
    struct {
        char           *title;
        vout_display_t *vd;
        bool           use_dr;
    } display;

    struct {
        vlc_tick_t  date;
        vlc_tick_t  timestamp;
        bool        is_interlaced;
        picture_t   *decoded;
        picture_t   *current;
        picture_t   *next;
    } displayed;

    struct {
        vlc_tick_t  last;
        vlc_tick_t  timestamp;
    } step;

    struct {
        bool        is_on;
        vlc_tick_t  date;
    } pause;

    /* Look-ahead decode cache (video-cache-mb): while the fill gate in
     * es_out holds playback, the vout must neither display nor trash the
     * pictures accumulating in decoder_fifo (their dates are only
     * re-based when the gate opens). Behaves like pause for the display
     * loop, but kept separate so it never collides with the real pause
     * state machine (ThreadChangePause asserts on double pause). */
    bool            cache_hold;
    /* A still-image disc menu needs the last filtered picture to survive
     * decoder recycling so its changing interactive plane can be recomposed
     * without another video frame. */
    bool            static_frame_hold;
    /* How many pictures the decoder may pile up in decoder_fifo without
     * starving the pool (would deadlock in picture_pool_Wait otherwise).
     * Computed by vout_InitWrapper from the actual pool size, 0 when
     * unknown/no room. */
    unsigned        cache_headroom;

    /* Display punctuality telemetry (debug verbosity only): how far past
     * its date every scheduled picture actually hit the display, sampled
     * at the swap. Answers "is the playback micro-stuttering?" without a
     * human staring at the screen -- late-but-under-the-drop-threshold
     * frames are invisible in the logs otherwise. */
    struct {
        unsigned    count;
        unsigned    late;       /* > 4 ms past their date */
        vlc_tick_t  worst;
        vlc_tick_t  sum;
        vlc_tick_t  last_report;
    } punctuality;

    /* The other end of the same question (debug verbosity only): how much
     * time a picture still had in front of it when the decoder handed it
     * over. Punctuality alone cannot tell "the display is slow" from "the
     * picture was already late when it arrived": measured on an iBook G3,
     * pictures reached the swap 85 to 129 ms past their date while the
     * processor kept a quarter of itself idle and the display path cost
     * two milliseconds a frame -- so the delay had to come from upstream,
     * and nothing was measuring upstream.
     *
     * Written from the decoder thread, which is the only caller of
     * vout_PutPicture(), and read nowhere else: telemetry, not state. */
    struct {
        unsigned    count;
        unsigned    late;       /* already past their date on arrival */
        vlc_tick_t  worst;      /* least lead seen (may be negative) */
        vlc_tick_t  sum;
        vlc_tick_t  last_report;
    } handoff;

    /* OSD title configuration */
    struct {
        bool        show;
        vlc_tick_t  timeout;
        int         position;
    } title;

    struct {
        bool        is_interlaced;
        vlc_tick_t  date;
    } interlacing;

    /* */
    bool            is_late_dropped;

    /* The crop that was last asked for, remembered on the *vout* and not
     * only on the display. A display is torn down and rebuilt on every
     * input format change -- which a looping stream does at every turn --
     * and comes back uncropped; re-applying this at ThreadStart is what
     * keeps the picture (and the window) from jumping back to the full
     * frame for a moment. */
    struct {
        enum {
            VOUT_CROP_RATIO,
            VOUT_CROP_WINDOW,
            VOUT_CROP_BORDER,
        } mode;
        unsigned num, den;                  /* RATIO */
        unsigned x, y, width, height;       /* WINDOW */
        unsigned left, top, right, bottom;  /* BORDER */
        /* Source the WINDOW/BORDER values were computed against: they are
         * pixel counts, so they mean nothing on a source of another size. */
        unsigned src_width, src_height;
        /* crop=auto: the border above is then decided by the detector. */
        bool             automatic;
        /* Disc-menu graphics use uncropped source coordinates. */
        bool             interactive_overlay;
        vout_autocrop_t *detector;
    } crop;

    /* Video filter2 chain */
    struct {
        vlc_mutex_t     lock;
        char            *configuration;
        video_format_t  format;
        struct filter_chain_t *chain_static;
        struct filter_chain_t *chain_interactive;
        bool            has_deint;
    } filter;

    /* */
    vlc_mouse_t     mouse;

    /* */
    picture_pool_t  *private_pool;
    picture_pool_t  *display_pool;
    picture_pool_t  *decoder_pool;
    picture_fifo_t  *decoder_fifo;
    vout_chrono_t   render;           /**< picture render time estimator */
};

/* TODO to move them to vlc_vout.h */
void vout_ControlChangeFullscreen(vout_thread_t *, bool fullscreen);
void vout_ControlChangeWindowState(vout_thread_t *, unsigned state);
void vout_ControlChangeDisplayFilled(vout_thread_t *, bool is_filled);
void vout_ControlChangeZoom(vout_thread_t *, int num, int den);
void vout_ControlChangeSampleAspectRatio(vout_thread_t *, unsigned num, unsigned den);
void vout_ControlChangeCropRatio(vout_thread_t *, unsigned num, unsigned den);
void vout_ControlChangeCropWindow(vout_thread_t *, int x, int y, int width, int height);
void vout_ControlChangeCropBorder(vout_thread_t *, int left, int top, int right, int bottom);
void vout_ControlChangeCropAuto(vout_thread_t *);
void vout_ControlForgetCrop(vout_thread_t *);
void vout_ControlChangeFilters(vout_thread_t *, const char *);
void vout_ControlChangeSubSources(vout_thread_t *, const char *);
void vout_ControlChangeSubFilters(vout_thread_t *, const char *);
void vout_ControlChangeSubMargin(vout_thread_t *, int);
void vout_ControlChangeViewpoint( vout_thread_t *, const vlc_viewpoint_t *);

/* */
void vout_IntfInit( vout_thread_t * );
void vout_IntfReinit( vout_thread_t * );

/* */
int  vout_OpenWrapper (vout_thread_t *, const char *, const vout_display_state_t *);
void vout_CloseWrapper(vout_thread_t *, vout_display_state_t *);
int  vout_InitWrapper(vout_thread_t *);
void vout_EndWrapper(vout_thread_t *);
void vout_ManageWrapper(vout_thread_t *);

/* */
int spu_ProcessMouse(spu_t *, const vlc_mouse_t *, const video_format_t *);
void spu_Attach( spu_t *, vlc_object_t *input, bool );
void spu_ChangeMargin(spu_t *, int);

#endif
