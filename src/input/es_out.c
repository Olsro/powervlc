/*****************************************************************************
 * es_out.c: Es Out handler for input.
 *****************************************************************************
 * Copyright (C) 2003-2004 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Laurent Aimar <fenrir@via.ecp.fr>
 *          Jean-Paul Saman <jpsaman #_at_# m2x dot nl>
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

#include <stdio.h>
#include <assert.h>
#include <vlc_common.h>

#include <vlc_input.h>
#include <vlc_es_out.h>
#include <vlc_block.h>
#include <vlc_aout.h>
#include <vlc_vout.h>
#include <vlc_vout_osd.h>
#include <vlc_fourcc.h>
#include <vlc_meta.h>
#include <vlc_charset.h>
#include <vlc_url.h>

#include "input_internal.h"
#include "clock.h"
#include "decoder.h"
#include "es_out.h"
#include "event.h"
#include "info.h"
#include "item.h"

#include "../stream_output/stream_output.h"
#include "../audio_output/aout_internal.h"
#include "resource.h"
#include "../video_output/vout_control.h"

#include <vlc_iso_lang.h>
/* FIXME we should find a better way than including that */
#include "../text/iso-639_def.h"

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
typedef struct
{
    /* Program ID */
    int i_id;

    /* Number of es for this pgrm */
    int i_es;

    bool b_selected;
    bool b_scrambled;

    /* Clock for this program */
    input_clock_t *p_clock;

    vlc_tick_t i_last_pcr;

    vlc_meta_t *p_meta;
} es_out_pgrm_t;

struct es_out_id_t
{
    /* ES ID */
    int       i_id;
    es_out_pgrm_t *p_pgrm;

    /* */
    bool b_scrambled;
    /* Selection was forced (user or demux request): the automatic
     * default-selection must not steal it for a higher-priority track */
    bool b_forced_selection;

    /* Channel in the track type */
    int         i_channel;
    es_format_t fmt;
    char        *psz_language;
    char        *psz_language_code;

    decoder_t   *p_dec;
    decoder_t   *p_dec_record;

    vlc_tick_t  i_pts_level;

    /* Fields for Video with CC */
    struct
    {
        vlc_fourcc_t type;
        uint64_t     i_bitmap;    /* channels bitmap */
        es_out_id_t  *pp_es[64]; /* a max of 64 chans for CEA708 */
    } cc;

    /* Field for CC track from a master video */
    es_out_id_t *p_master;

    /* ID for the meta data */
    int         i_meta_id;
};

typedef struct
{
    int         i_count;    /* es count */
    es_out_id_t *p_main_es; /* current main es */
    enum es_out_policy_e e_policy;

    /* Parameters used for es selection */
    bool        b_autoselect; /* if we want to select an es when no user prefs */
    int         i_id;       /* es id as set by es fmt.id */
    int         i_demux_id; /* same as previous, demuxer set default value */
    int         i_channel;  /* es number in creation order */
    char        **ppsz_language;
} es_out_es_props_t;

struct es_out_sys_t
{
    input_thread_t *p_input;

    /* */
    vlc_mutex_t   lock;

    /* all programs */
    int           i_pgrm;
    es_out_pgrm_t **pgrm;
    es_out_pgrm_t *p_pgrm;  /* Master program */

    /* all es */
    int         i_id;
    int         i_es;
    es_out_id_t **es;

    /* mode gestion */
    bool  b_active;
    int         i_mode;

    es_out_es_props_t video, audio, sub;

    /* es/group to select */
    int         i_group_id;

    /* delay */
    int64_t i_audio_delay;
    int64_t i_spu_delay;

    /* Clock configuration */
    vlc_tick_t  i_pts_delay;
    vlc_tick_t  i_pts_jitter;
    int         i_cr_average;
    int         i_rate;
    bool        b_next_pcr_seamless;

    /* */
    bool        b_paused;
    es_out_id_t *p_next_frame_es;
    vlc_tick_t  i_pause_date;

    /* Current preroll */
    vlc_tick_t  i_preroll_end;

    /* Used for buffering */
    bool        b_buffering;
    vlc_tick_t  i_buffering_extra_initial;
    vlc_tick_t  i_buffering_extra_stream;
    vlc_tick_t  i_buffering_extra_system;

    /* Look-ahead decoded-picture cache (video-cache-* options); see
     * EsOutVideoCacheFillRatio(). 0 MB disables the whole feature.
     * (The seconds cap is enforced decoder-side, in
     * DecoderVideoCacheTarget; es_out only needs the byte budget.) */
    size_t      i_video_cache_bytes;
    unsigned    i_video_cache_fill_percent;

    /* Record */
    sout_instance_t *p_sout_record;
    /* Bounded recording (clip creation): the stop bound only starts
     * counting once the demuxer has actually reached the clip, see
     * ES_OUT_SET_TIMES */
    vlc_tick_t  i_record_stop_armed_for;
    bool        b_record_stop_armed;

    /* Used only to limit debugging output */
    int         i_prev_stream_level;

    /* Throttles the buffering OSD (see EsOutVideoCacheFillRatio) */
    vlc_tick_t  i_video_cache_osd_last;

    /* Watchdog against a wedged fill (decoder stuck before its first
     * picture, pool famine...): if the fifo count makes no progress for
     * VIDEO_CACHE_STALL_TIMEOUT, give the wait up (as if skipped). */
    size_t      i_video_cache_last_count;
    vlc_tick_t  i_video_cache_progress_date;
    /* Wall-clock start of the current fill episode: a fill that IS
     * progressing but too slowly (DVD stills produce ~1 picture/s, so
     * the no-progress watchdog never fires) must not gate playback for
     * minutes either. */
    vlc_tick_t  i_video_cache_episode_start;

    /* Set by the Play/Pause hotkey while buffering to skip the wait
     * (see input_EsOutSkipVideoCacheFill) */
    bool        b_video_cache_skip;
    /* Demux-driven: menu-capable disc demuxers inhibit the cache in
     * menu domains (see ES_OUT_SET_VIDEO_CACHE_INHIBIT). */
    bool        b_video_cache_inhibit;
    /* A user pause that BEGAN during a cache fill episode is kept
     * virtual (b_paused/i_pause_date only, nothing propagated to the
     * clock, the decoders or the vout) and materialized in one go when
     * the gate opens. Propagating it live is what corrupted the held
     * pictures: the clock reference shifts on the input thread at
     * resume, but the vout's matching fifo shift is applied by the
     * decoder thread only after it finishes its current decode run --
     * every picture decoded in that lag converts against the shifted
     * clock AND THEN gets the vout shift again (dated one pause-span in
     * the future), so on release the display freezes a span on the
     * first doubled picture then drops a span's worth of correct ones
     * as "late" (observed: 99-152 drops per pause cycle). During the
     * episode a pause has nothing real to do anyway: the vout is held,
     * the clock origin frozen, the audio parked. */
    bool        b_video_cache_pause_virtual;

    /* Mid-play refill (see EsOutVideoCacheMaybeRefill): a buffering
     * episode opened because the cache drained to zero during playback.
     * Released with a plain clock shift of the episode's duration -- the
     * absolute re-anchoring of EsOutDecodersStopBuffering assumes a
     * freshly referenced clock (start/seek) and would otherwise park
     * playback as far in the future as the reference is in the past. */
    bool        b_video_cache_refill;
    vlc_tick_t  i_video_cache_refill_start;
    vlc_tick_t  i_video_cache_refill_last_end;
    /* Consecutive refill episodes that ended nearly empty (source too
     * slow, decoder wedged...): each one doubles the refill cooldown, so
     * a stream that cannot actually be cached degrades to rare, long
     * pauses instead of a permanent 2-3 s freeze/buffering loop. Reset
     * by any effective episode and by seeks. */
    unsigned    i_video_cache_bad_refills;
    /* When the decoder was first seen starved in the current fill
     * episode (see the grace period in EsOutVideoCacheFillRatio).
     * VLC_TICK_INVALID whenever it is feeding normally. */
    vlc_tick_t  i_video_cache_starved_since;
};

static es_out_id_t *EsOutAdd    ( es_out_t *, const es_format_t * );
static int          EsOutSend   ( es_out_t *, es_out_id_t *, block_t * );
static void         EsOutDel    ( es_out_t *, es_out_id_t * );
static int          EsOutControl( es_out_t *, int i_query, va_list );
static void         EsOutDelete ( es_out_t * );

static void         EsOutTerminate( es_out_t * );
static void         EsOutSelect( es_out_t *, es_out_id_t *es, bool b_force );
static void         EsOutUpdateInfo( es_out_t *, es_out_id_t *es, const es_format_t *, const vlc_meta_t * );
static int          EsOutSetRecord(  es_out_t *, bool b_record );

static bool EsIsSelected( es_out_id_t *es );
static void EsSelect( es_out_t *out, es_out_id_t *es );

static bool EsOutKeepDiscVout( const es_out_sys_t *p_sys )
{
    return var_GetBool( p_sys->p_input, "bluray-disc-session" );
}
static void EsDeleteInfo( es_out_t *, es_out_id_t *es );
static void EsUnselect( es_out_t *out, es_out_id_t *es, bool b_update );
static void EsOutDecoderChangeDelay( es_out_t *out, es_out_id_t *p_es );
static void EsOutDecodersChangePause( es_out_t *out, bool b_paused, vlc_tick_t i_date );
static void EsOutChangePosition( es_out_t *out );
static bool EsOutIsExtraBufferingAllowed( es_out_t *out );
static void EsOutProgramChangePause( es_out_t *out, bool b_paused, vlc_tick_t i_date );
static void EsOutProgramsChangeRate( es_out_t *out );
static void EsOutDecodersStopBuffering( es_out_t *out, bool b_forced );
static void EsOutVideoCacheMaybeRefill( es_out_t *out );
static bool EsOutVideoCacheHasCushion( es_out_t *out );
static void EsOutGlobalMeta( es_out_t *p_out, const vlc_meta_t *p_meta );
static void EsOutMeta( es_out_t *p_out, const vlc_meta_t *p_meta, const vlc_meta_t *p_progmeta );

static char *LanguageGetName( const char *psz_code );
static char *LanguageGetCode( const char *psz_lang );
static char **LanguageSplit( const char *psz_langs );
static int LanguageArrayIndex( char **ppsz_langs, const char *psz_lang );

static char *EsOutProgramGetMetaName( es_out_pgrm_t *p_pgrm );
static char *EsInfoCategoryName( es_out_id_t* es );

static inline int EsOutGetClosedCaptionsChannel( const es_format_t *p_fmt )
{
    int i_channel;
    if( p_fmt->i_codec == VLC_CODEC_CEA608 && p_fmt->subs.cc.i_channel < 4 )
        i_channel = p_fmt->subs.cc.i_channel;
    else if( p_fmt->i_codec == VLC_CODEC_CEA708 && p_fmt->subs.cc.i_channel < 64 )
        i_channel = p_fmt->subs.cc.i_channel;
    else
        i_channel = -1;
    return i_channel;
}
static inline bool EsFmtIsTeletext( const es_format_t *p_fmt )
{
    return p_fmt->i_cat == SPU_ES && p_fmt->i_codec == VLC_CODEC_TELETEXT;
}

/*****************************************************************************
 * Es category specific structs
 *****************************************************************************/
static es_out_es_props_t * GetPropsByCat( es_out_sys_t *p_sys, int i_cat )
{
    switch( i_cat )
    {
    case AUDIO_ES:
        return &p_sys->audio;
    case SPU_ES:
        return &p_sys->sub;
    case VIDEO_ES:
        return &p_sys->video;
    }
    return NULL;
}

static void EsOutPropsCleanup( es_out_es_props_t *p_props )
{
    if( p_props->ppsz_language )
    {
        for( int i = 0; p_props->ppsz_language[i]; i++ )
            free( p_props->ppsz_language[i] );
        free( p_props->ppsz_language );
    }
}

static void EsOutPropsInit( es_out_es_props_t *p_props,
                            bool autoselect,
                            input_thread_t *p_input,
                            enum es_out_policy_e e_default_policy,
                            const char *psz_trackidvar,
                            const char *psz_trackvar,
                            const char *psz_langvar,
                            const char *psz_debug )
{
    p_props->e_policy = e_default_policy;
    p_props->i_count = 0;
    p_props->b_autoselect = autoselect;
    p_props->i_id = (psz_trackidvar) ? var_GetInteger( p_input, psz_trackidvar ): -1;
    p_props->i_channel = (psz_trackvar) ? var_GetInteger( p_input, psz_trackvar ): -1;
    p_props->i_demux_id = -1;
    p_props->p_main_es = NULL;

    if( !input_priv(p_input)->b_preparsing && psz_langvar )
    {
        char *psz_string = var_GetString( p_input, psz_langvar );
        p_props->ppsz_language = LanguageSplit( psz_string );
        if( p_props->ppsz_language )
        {
            for( int i = 0; p_props->ppsz_language[i]; i++ )
                msg_Dbg( p_input, "selected %s language[%d] %s",
                         psz_debug, i, p_props->ppsz_language[i] );
        }
        free( psz_string );
    }
}

/*****************************************************************************
 * input_EsOutNew:
 *****************************************************************************/
es_out_t *input_EsOutNew( input_thread_t *p_input, int i_rate )
{
    es_out_t     *out = malloc( sizeof( *out ) );
    if( !out )
        return NULL;

    es_out_sys_t *p_sys = calloc( 1, sizeof( *p_sys ) );
    if( !p_sys )
    {
        free( out );
        return NULL;
    }

    out->pf_add     = EsOutAdd;
    out->pf_send    = EsOutSend;
    out->pf_del     = EsOutDel;
    out->pf_control = EsOutControl;
    out->pf_destroy = EsOutDelete;
    out->p_sys      = p_sys;

    vlc_mutex_init_recursive( &p_sys->lock );
    p_sys->p_input = p_input;

    p_sys->b_active = false;
    p_sys->p_next_frame_es = NULL;
    p_sys->i_mode   = ES_OUT_MODE_NONE;

    TAB_INIT( p_sys->i_pgrm, p_sys->pgrm );

    TAB_INIT( p_sys->i_es, p_sys->es );

    /* */
    EsOutPropsInit( &p_sys->video, true, p_input, ES_OUT_ES_POLICY_SIMULTANEOUS,
                    NULL, NULL, NULL, NULL );
    EsOutPropsInit( &p_sys->audio, true, p_input, ES_OUT_ES_POLICY_EXCLUSIVE,
                    "audio-track-id", "audio-track", "audio-language", "audio" );
    EsOutPropsInit( &p_sys->sub,  false, p_input, ES_OUT_ES_POLICY_EXCLUSIVE,
                    "sub-track-id", "sub-track", "sub-language", "sub" );

    p_sys->i_group_id = var_GetInteger( p_input, "program" );

    /* Gapless (PowerVLC): audio-only inputs may park/adopt the audio output
     * stream across tracks. Cleared for good as soon as a video ES shows up. */
    var_Create( p_input, "gapless-eligible", VLC_VAR_BOOL );
    var_SetBool( p_input, "gapless-eligible", true );

    p_sys->i_pause_date = -1;
    p_sys->b_paused = false;

    p_sys->i_rate = i_rate;
    p_sys->b_next_pcr_seamless = false;

    int64_t i_cache_mb = var_InheritInteger( p_input, "video-cache-mb" );
    p_sys->i_video_cache_bytes =
        i_cache_mb > 0 ? (size_t)i_cache_mb * 1024 * 1024 : 0;
    int i_fill = var_InheritInteger( p_input, "video-cache-fill-percent" );
    p_sys->i_video_cache_fill_percent =
        i_fill < 0 ? 0 : (i_fill > 100 ? 100 : (unsigned)i_fill);
    p_sys->i_video_cache_last_count = 0;
    p_sys->i_video_cache_progress_date = VLC_TICK_INVALID;
    p_sys->i_video_cache_episode_start = VLC_TICK_INVALID;
    p_sys->b_video_cache_refill = false;
    p_sys->i_video_cache_refill_start = VLC_TICK_INVALID;
    p_sys->i_video_cache_refill_last_end = VLC_TICK_INVALID;
    p_sys->i_video_cache_bad_refills = 0;
    p_sys->i_video_cache_osd_last = VLC_TICK_INVALID;
    p_sys->i_video_cache_starved_since = VLC_TICK_INVALID;
    p_sys->b_video_cache_inhibit = false;
    p_sys->b_video_cache_pause_virtual = false;

    p_sys->b_buffering = true;
    p_sys->i_preroll_end = -1;
    p_sys->i_prev_stream_level = -1;

    return out;
}

/*****************************************************************************
 *
 *****************************************************************************/
static void EsOutDelete( es_out_t *out )
{
    es_out_sys_t *p_sys = out->p_sys;

    assert( !p_sys->i_es && !p_sys->i_pgrm && !p_sys->p_pgrm );
    EsOutPropsCleanup( &p_sys->audio );
    EsOutPropsCleanup( &p_sys->sub );

    vlc_mutex_destroy( &p_sys->lock );

    free( p_sys );
    free( out );
}

static void EsOutTerminate( es_out_t *out )
{
    es_out_sys_t *p_sys = out->p_sys;

    if( p_sys->p_sout_record )
        EsOutSetRecord( out, false );

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        if( p_sys->es[i]->p_dec )
            input_DecoderDelete( p_sys->es[i]->p_dec );

        free( p_sys->es[i]->psz_language );
        free( p_sys->es[i]->psz_language_code );
        es_format_Clean( &p_sys->es[i]->fmt );

        free( p_sys->es[i] );
    }
    TAB_CLEAN( p_sys->i_es, p_sys->es );

    /* FIXME duplicate work EsOutProgramDel (but we cannot use it) add a EsOutProgramClean ? */
    for( int i = 0; i < p_sys->i_pgrm; i++ )
    {
        es_out_pgrm_t *p_pgrm = p_sys->pgrm[i];
        input_clock_Delete( p_pgrm->p_clock );
        if( p_pgrm->p_meta )
            vlc_meta_Delete( p_pgrm->p_meta );

        free( p_pgrm );
    }
    TAB_CLEAN( p_sys->i_pgrm, p_sys->pgrm );

    p_sys->p_pgrm = NULL;

    input_item_SetEpgOffline( input_priv(p_sys->p_input)->p_item );
    input_SendEventMetaEpg( p_sys->p_input );
}

static vlc_tick_t EsOutGetWakeup( es_out_t *out )
{
    es_out_sys_t   *p_sys = out->p_sys;
    input_thread_t *p_input = p_sys->p_input;

    if( !p_sys->p_pgrm )
        return 0;

    /* We do not have a wake up date if the input cannot have its speed
     * controlled or sout is imposing its own or while buffering
     *
     * FIXME for !input_priv(p_input)->b_can_pace_control a wake-up time is still needed
     * to avoid too heavy buffering */
    if( !input_priv(p_input)->b_can_pace_control ||
        input_priv(p_input)->b_out_pace_control ||
        p_sys->b_buffering ||
        p_sys->p_next_frame_es != NULL )
    {
        /* Video-cache fill episode with a healthy compressed backlog
         * already queued: nap instead of spinning the demux flat-out.
         * On the single-core PPC targets the input thread runs at
         * SCHED_RR (round 63) and a zero wakeup lets it starve the
         * plain-priority DECODER outright -- observed on DVD title
         * fills as 2-3 decoded pictures per 5 s (the too-slow valve
         * then fired, so video-cache-fill-percent was never honoured)
         * while the demux pulled the disc into RAM at 16x realtime.
         * With 40 ms naps past the extra-buffering cap (~10 MB) the
         * decoder owns the core and a DVD fill completes at full
         * decode speed; the demux keeps topping the backlog up in
         * bursts between naps. */
        if( p_sys->b_buffering && p_sys->i_video_cache_bytes > 0
         && !p_sys->b_video_cache_inhibit
         && !EsOutIsExtraBufferingAllowed( out ) )
            return mdate() + 40000;
        return 0;
    }

    /* STEADY PLAYBACK with the look-ahead cache under its target: stock
     * pace control feeds the demux at 1x (pts-delay of backlog), which
     * can never REBUILD a cushion -- on sources that are not fully
     * demuxed up front (DVD: 60+ min of stream, unlike a local file
     * swallowed whole during the initial episode) the reservoir could
     * only ever drain: every hiccup walked it monotonically to zero,
     * then a refill episode re-bought it, in a loop (user report). Run
     * the demux AHEAD while the cushion is short -- but NEVER by spinning
     * the input flat-out (the round-86 correction below).
     *
     * The input thread is SCHED_RR (VLC_THREAD_PRIORITY_INPUT=22 ->
     * sched_get_priority_min+RR, round 63) and the video decoder is
     * plain SCHED_OTHER. On the single-core PPC targets a zero wakeup
     * here (the old "fifo demonstrably fat -> return 0" fast-burst) does
     * not help the cushion: it PREEMPTS the decoder, which then can
     * neither drain this compressed fifo nor produce the decoded
     * pictures the cushion is made of. Measured on the Chihiro DVD title
     * (round 86): the demux delivers ~10x realtime while BUFFERING (the
     * display is off, only demux+decoder contend) but collapses to
     * ~0.25x during PLAYBACK (demux+decoder+vout contend and the RT
     * input wins the core), so the cushion drained to a re-buffer every
     * ~28 s no matter how deep the cache. The disc I/O is NOT the
     * bottleneck; the decoder starving for the core is.
     *
     * Fix (round 87b, superseding the first r87 attempt): burst-and-nap
     * around a HIGH-WATER mark. The first attempt napped 40 ms as soon
     * as the video fifo held 512 KiB; with the demux pulling ONE 2 KiB
     * disc block per wakeup that caps delivery at ~1 MB/s -- the AVERAGE
     * DVD mux rate with zero margin -- so every bitrate peak
     * under-delivered BOTH elementary streams (they are interleaved in
     * the same program stream) and the ~0.5 s audio backlog behind a
     * 512 KiB video fifo drained first: "buffer too late: dropped" ->
     * aout flush -> clock hiccup -> the very re-buffer we fight, every
     * ~27 s. Burst-and-nap instead: below the high-water mark the input
     * runs unthrottled (the disc feeds at 10x, so topping the backlog up
     * costs short RT bursts the decoded-picture cushion absorbs; the
     * adaptive refill pacing in decoder.c re-buys the few pictures
     * lost); above it the input naps 40 ms and the core belongs to the
     * decoder. 4 MiB of program stream is ~4 s of BOTH audio and video
     * backlog -- peaks are ridden out without any stream running late.
     * The 2 ms probe under 1 MiB is the round-75 live-stream guard: a
     * source slower than its consumer must not let the RT input spin on
     * empty reads. */
    if( p_sys->i_video_cache_bytes > 0 && !p_sys->b_video_cache_inhibit )
    {
        for( int i = 0; i < p_sys->i_es; i++ )
        {
            es_out_id_t *p_es = p_sys->es[i];
            if( p_es->fmt.i_cat != VIDEO_ES || !p_es->p_dec )
                continue;
            size_t i_count, i_target;
            if( input_DecoderGetCacheState( p_es->p_dec, &i_count,
                                            &i_target, NULL, NULL )
             && i_target > 0 )
            {
                if( i_count < i_target )
                {
                    const size_t i_fifo =
                        input_DecoderGetFifoSize( p_es->p_dec );
                    if( !EsOutIsExtraBufferingAllowed( out )
                     || i_fifo > 4 * 1024 * 1024 )
                        return mdate() + 40000;
                    if( i_fifo > 1 * 1024 * 1024 )
                        return 0;
                    return mdate() + 2000;
                }
                /* Cushion FULL: re-check at frame cadence. NEVER fall
                 * through to the stock clock wakeup here -- the demux
                 * runs cushion-depth AHEAD of the master clock, so the
                 * stock deadline is ~cushion-depth in the future: the
                 * input slept the whole 21 s, the compressed fifo ran
                 * dry, the decoder idled, and the cushion drained END TO
                 * END into a re-buffer, in a loop. THIS single faraway
                 * sleep -- not decoder CPU, not disc delivery -- was the
                 * root cause of the periodic mid-play refill (rounds
                 * 84-87 chased it in the wrong layers). 40 ms matches
                 * the display drain rate: the vout frees a slot, the
                 * next wakeup sees count < target and tops it up. */
                return mdate() + 40000;
            }
            break;
        }
    }

    return input_clock_GetWakeup( p_sys->p_pgrm->p_clock );
}

static es_out_id_t es_cat[DATA_ES];

static es_out_id_t *EsOutGetFromID( es_out_t *out, int i_id )
{
    if( i_id < 0 )
    {
        /* Special HACK, -i_id is the cat of the stream */
        return es_cat - i_id;
    }

    for( int i = 0; i < out->p_sys->i_es; i++ )
    {
        if( out->p_sys->es[i]->i_id == i_id )
            return out->p_sys->es[i];
    }
    return NULL;
}

static bool EsOutDecodersIsEmpty( es_out_t *out )
{
    es_out_sys_t      *p_sys = out->p_sys;

    /* For a fully demuxed local file no PCR will ever fire again; the
     * input's EOF wait polling us is then the only recurring hook where
     * a drained look-ahead cache can start a refill episode. */
    if( !p_sys->b_buffering )
        EsOutVideoCacheMaybeRefill( out );

    if( p_sys->b_buffering && p_sys->p_pgrm )
    {
        /* Demux EOF normally force-ends buffering (no more data will
         * ever complete the stream-time criterion). But the look-ahead
         * cache criterion completes from data already sitting in the
         * decoder fifo -- a small local file is fully demuxed within
         * milliseconds, long before the cache fills. Keep the gate as
         * long as the video decoder can still make progress; force once
         * it is starved (everything decoded, target simply unreachable). */
        bool b_forced = true;
        if( p_sys->i_video_cache_bytes > 0 && !p_sys->b_video_cache_skip )
        {
            for( int i = 0; i < p_sys->i_es; i++ )
            {
                es_out_id_t *es = p_sys->es[i];
                if( es->fmt.i_cat != VIDEO_ES || !es->p_dec )
                    continue;
                size_t i_count, i_target;
                bool b_starved;
                if( input_DecoderGetCacheState( es->p_dec, &i_count,
                                                &i_target, NULL, &b_starved )
                 && !b_starved )
                    b_forced = false;
                break;
            }
        }
        EsOutDecodersStopBuffering( out, b_forced );
        if( p_sys->b_buffering )
            /* Still buffering after a FORCED stop = pathological, claim
             * emptiness so the input bails out instead of hanging (stock
             * behavior). Still buffering after a non-forced stop = the
             * cache fill is deliberately holding the gate while the
             * decoder chews its queued data: NOT empty, the input must
             * keep waiting (it re-polls us every INPUT_IDLE_SLEEP, which
             * conveniently doubles as the fill's EOF-side recheck). */
            return b_forced;
    }

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *es = p_sys->es[i];

        if( es->p_dec && !input_DecoderIsEmpty( es->p_dec ) )
            return false;
        if( es->p_dec_record && !input_DecoderIsEmpty( es->p_dec_record ) )
            return false;
    }
    return true;
}

static void EsOutSetDelay( es_out_t *out, int i_cat, int64_t i_delay )
{
    es_out_sys_t *p_sys = out->p_sys;

    if( i_cat == AUDIO_ES )
        p_sys->i_audio_delay = i_delay;
    else if( i_cat == SPU_ES )
        p_sys->i_spu_delay = i_delay;

    for( int i = 0; i < p_sys->i_es; i++ )
        EsOutDecoderChangeDelay( out, p_sys->es[i] );
}

static int EsOutSetRecord(  es_out_t *out, bool b_record )
{
    es_out_sys_t   *p_sys = out->p_sys;
    input_thread_t *p_input = p_sys->p_input;

    assert( ( b_record && !p_sys->p_sout_record ) || ( !b_record && p_sys->p_sout_record ) );

    if( b_record )
    {
        char *psz_path = input_RecordDirectory( p_input );

        char *psz_sout = NULL;  // TODO conf

        if( !psz_sout && psz_path )
        {
            char *psz_file = input_CreateFilename( p_input, psz_path, INPUT_RECORD_PREFIX, NULL );
            if( psz_file )
            {
                char* psz_file_esc = config_StringEscape( psz_file );
                if ( psz_file_esc )
                {
                    /* PowerVLC clip creation: pass the preferred start
                     * bound so the capture starts at the last key frame
                     * at or before it (see modules/stream_out/record.c) */
                    vlc_tick_t i_record_start =
                        var_GetInteger( p_input, "record-start-time" );
                    /* How many streams the recording chain must wait for
                     * before it settles on a container: it picks one from
                     * the streams that have delivered a block, and a
                     * subtitle track can stay silent long enough to miss
                     * the choice and be dropped (see record.c). These are
                     * exactly the ES that get a recording decoder below. */
                    int i_expect = 0;
                    for( int i = 0; i < p_sys->i_es; i++ )
                        if( p_sys->es[i]->p_dec && !p_sys->es[i]->p_master )
                            i_expect++;
                    if( asprintf( &psz_sout, "#record{dst-prefix='%s',"
                                  "start-time=%"PRId64",expect-streams=%d}",
                                  psz_file_esc,
                                  i_record_start > 0 ? i_record_start : 0,
                                  i_expect ) < 0 )
                        psz_sout = NULL;
                    free( psz_file_esc );
                }
                free( psz_file );
            }
        }
        free( psz_path );

        if( !psz_sout )
            return VLC_EGENERIC;

#ifdef ENABLE_SOUT
        p_sys->p_sout_record = sout_NewInstance( p_input, psz_sout );
#endif
        free( psz_sout );

        if( !p_sys->p_sout_record )
            return VLC_EGENERIC;

        for( int i = 0; i < p_sys->i_es; i++ )
        {
            es_out_id_t *p_es = p_sys->es[i];

            if( !p_es->p_dec || p_es->p_master )
                continue;

            p_es->p_dec_record = input_DecoderNew( p_input, &p_es->fmt, p_es->p_pgrm->p_clock, p_sys->p_sout_record );
            if( p_es->p_dec_record && p_sys->b_buffering )
                input_DecoderStartWait( p_es->p_dec_record );
        }
    }
    else
    {
        for( int i = 0; i < p_sys->i_es; i++ )
        {
            es_out_id_t *p_es = p_sys->es[i];

            if( !p_es->p_dec_record )
                continue;

            input_DecoderDelete( p_es->p_dec_record );
            p_es->p_dec_record = NULL;
        }
#ifdef ENABLE_SOUT
        sout_DeleteInstance( p_sys->p_sout_record );
#endif
        p_sys->p_sout_record = NULL;
    }

    return VLC_SUCCESS;
}

static void EsOutStopNextFrame( es_out_t *out )
{
    es_out_sys_t *p_sys = out->p_sys;
    assert( p_sys->p_next_frame_es != NULL );
    /* Flush every ES except the video one */
    EsOutChangePosition( out );
    p_sys->p_next_frame_es = NULL;
}

/* Pushes the pause state to the video decoder's vout synchronously from
 * this (the input) thread, so it lands in the vout control queue BEFORE
 * anything else this pause transition triggers. The decoder thread
 * re-applies the same state a beat later when it notices the toggle and
 * the vout de-dups it. Without this, every picture decoded between the
 * input-thread clock shift and the decoder-thread vout shift at RESUME
 * converts against the already-shifted clock and then gets the vout's
 * fifo shift on top -- dated one pause-span ahead, a span-long freeze
 * then a span of "too late" drops with a deep look-ahead fifo. */
static void EsOutVideoVoutChangePause( es_out_t *out, bool b_paused,
                                       vlc_tick_t i_date )
{
    es_out_sys_t *p_sys = out->p_sys;

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];
        if( p_es->fmt.i_cat != VIDEO_ES || !p_es->p_dec )
            continue;
        vout_thread_t *p_vout = NULL;
        input_DecoderGetObjects( p_es->p_dec, &p_vout, NULL );
        if( p_vout )
        {
            vout_ChangePause( p_vout, b_paused, i_date );
            vlc_object_release( p_vout );
        }
        break;
    }
}

static void EsOutChangePause( es_out_t *out, bool b_paused, vlc_tick_t i_date )
{
    es_out_sys_t *p_sys = out->p_sys;

    /* See b_video_cache_pause_virtual: pauses born inside a cache fill
     * episode stay virtual until the gate opens. A pause that PRE-dates
     * the episode keeps the stock symmetric propagation (clock and vout
     * shift by the same span at resume: homogeneous, the release offset
     * absorbs it). */
    if( p_sys->i_video_cache_bytes > 0 && p_sys->b_buffering )
    {
        if( b_paused && !p_sys->b_paused )
        {
            msg_Dbg( p_sys->p_input, "video cache: pause kept virtual "
                     "during the fill episode" );
            p_sys->b_video_cache_pause_virtual = true;
            p_sys->b_paused = true;
            p_sys->i_pause_date = i_date;
            return;
        }
        if( !b_paused && p_sys->b_video_cache_pause_virtual )
        {
            msg_Dbg( p_sys->p_input, "video cache: virtual pause "
                     "cancelled during the fill episode" );
            p_sys->b_video_cache_pause_virtual = false;
            p_sys->b_paused = false;
            p_sys->i_pause_date = i_date;
            return;
        }
    }

    /* XXX the order is important */
    if( b_paused )
    {
        EsOutVideoVoutChangePause( out, true, i_date );
        EsOutDecodersChangePause( out, true, i_date );
        EsOutProgramChangePause( out, true, i_date );
    }
    else
    {
        if( p_sys->p_next_frame_es != NULL )
            EsOutStopNextFrame( out );

        if( p_sys->i_buffering_extra_initial > 0 )
        {
            vlc_tick_t i_stream_start;
            vlc_tick_t i_system_start;
            vlc_tick_t i_stream_duration;
            vlc_tick_t i_system_duration;
            int i_ret;
            i_ret = input_clock_GetState( p_sys->p_pgrm->p_clock,
                                          &i_stream_start, &i_system_start,
                                          &i_stream_duration, &i_system_duration );
            if( !i_ret )
            {
                /* FIXME pcr != exactly what wanted */
                const vlc_tick_t i_used = /*(i_stream_duration - input_priv(p_sys->p_input)->i_pts_delay)*/ p_sys->i_buffering_extra_system - p_sys->i_buffering_extra_initial;
                i_date -= i_used;
            }
            p_sys->i_buffering_extra_initial = 0;
            p_sys->i_buffering_extra_stream = 0;
            p_sys->i_buffering_extra_system = 0;
        }
        EsOutProgramChangePause( out, false, i_date );
        EsOutVideoVoutChangePause( out, false, i_date );
        EsOutDecodersChangePause( out, false, i_date );

        EsOutProgramsChangeRate( out );
    }
    p_sys->b_paused = b_paused;
    p_sys->i_pause_date = i_date;
}

static void EsOutChangeRate( es_out_t *out, int i_rate )
{
    es_out_sys_t      *p_sys = out->p_sys;

    p_sys->i_rate = i_rate;
    EsOutProgramsChangeRate( out );
}

static void EsOutChangePosition( es_out_t *out )
{
    es_out_sys_t      *p_sys = out->p_sys;


    input_SendEventCache( p_sys->p_input, 0.0 );

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];

        if( p_es->p_dec != NULL )
        {
            input_DecoderFlush( p_es->p_dec );
            if( !p_sys->b_buffering )
            {
                input_DecoderStartWait( p_es->p_dec );
                if( p_es->p_dec_record != NULL )
                    input_DecoderStartWait( p_es->p_dec_record );
            }
        }
        p_es->i_pts_level = VLC_TICK_INVALID;
    }

    for( int i = 0; i < p_sys->i_pgrm; i++ ) {
        input_clock_Reset( p_sys->pgrm[i]->p_clock );
        p_sys->pgrm[i]->i_last_pcr = VLC_TICK_INVALID;
    }

    p_sys->b_buffering = true;
    p_sys->i_buffering_extra_initial = 0;
    p_sys->i_buffering_extra_stream = 0;
    p_sys->i_buffering_extra_system = 0;
    p_sys->i_preroll_end = -1;
    p_sys->i_prev_stream_level = -1;
    /* Every seek re-buffers the video cache too: a fluid resume is worth
     * more than shaving a few seconds off the wait. A user-initiated
     * skip of the wait only ever applies to the buffering episode it was
     * pressed during. */
    p_sys->b_video_cache_skip = false;
    p_sys->i_video_cache_last_count = 0;
    p_sys->i_video_cache_progress_date = VLC_TICK_INVALID;
    p_sys->i_video_cache_episode_start = VLC_TICK_INVALID;
    p_sys->i_video_cache_starved_since = VLC_TICK_INVALID;
    /* A refill episode in flight is superseded by the seek's own one */
    p_sys->b_video_cache_refill = false;
    p_sys->i_video_cache_refill_last_end = VLC_TICK_INVALID;
    p_sys->i_video_cache_osd_last = VLC_TICK_INVALID;
    /* i_video_cache_bad_refills deliberately survives: this runs for
     * PCR discontinuities too (every underrun of a stalling stream),
     * which would defeat the backoff exactly where it matters. The
     * counter is cleared by any effective fill episode instead. */
}



/**
 * Computes how full the look-ahead decode cache is, as a 0.0-1.0 ratio
 * against the effective target (see DecoderVideoCacheTarget in decoder.c,
 * the single source of truth: the smaller of the MB budget, the seconds
 * cap and the vout pool headroom). Returns 1.0 (never blocks) when the
 * feature is disabled, no video decoder exists to buffer against, or the
 * user skipped the wait via the Play/Pause hotkey.
 */
/* Last-resort valve when the fill produced NO picture at all: bail as
 * if skipped. 6 s (was 15 s, from the round-60 wedge era): every known
 * wedge now has a root fix, and the remaining zero-picture waits are
 * slow STARTS -- a Jellyfin transcode spinning up its ffmpeg held the
 * first picture ~15 s and the gate turned that into 15 s of black
 * (observed on the mp4-over-https test); a DVD title entry can idle a
 * few seconds in the reset churn too. 6 s keeps the safety margin over
 * codec init while making a dead start bearable. */
#define VIDEO_CACHE_STALL_TIMEOUT (6 * CLOCK_FREQ)

/* Wall-clock bound on one fill episode, but ONLY for sources producing
 * pictures slower than VIDEO_CACHE_FILL_MIN_RATE: it catches stills and
 * near-stills that the no-progress watchdog can never see (DVD logo
 * stills at ~1 pic/s were observed gating a title start for minutes). A
 * fill that produces at a healthy rate is allowed to run to its target
 * however long that takes -- that is the point of the feature: a 50%
 * fill of a deep (hundreds of pictures) cache legitimately needs more
 * than any fixed timeout, and cutting it there was observed starting
 * playback at ~30% whatever video-cache-fill-percent said. */
#define VIDEO_CACHE_FILL_WALL_TIMEOUT (5 * CLOCK_FREQ)
#define VIDEO_CACHE_FILL_MIN_RATE 2 /* pictures per second */

/* How long a fill episode keeps waiting through an apparently starved
 * decoder before believing it (see the starvation guard below). Long
 * enough to ride out a disc seek or a slow drive's inter-burst gap,
 * short enough that a true EOF costs half a second. */
#define VIDEO_CACHE_STARVE_GRACE (CLOCK_FREQ / 2)

static double EsOutVideoCacheFillRatio( es_out_t *out )
{
    es_out_sys_t *p_sys = out->p_sys;

    if( p_sys->i_video_cache_bytes == 0 || p_sys->b_video_cache_skip
     || p_sys->b_video_cache_inhibit )
        return 1.0;

    /* Distinguishes "no video ES at all" (nothing to ever buffer against,
     * return 1.0/never blocks -- e.g. an audio-only file) from "the video
     * ES exists but hasn't got a vout yet" (the decoder hasn't produced
     * its first frame/negotiated a picture format yet: still keep
     * waiting, return 0.0, not 1.0 -- this was the bug that made the
     * whole feature a no-op: SET_PCR fires before the first frame is
     * decoded far more often than not, so the pre-vout window is where
     * EsOutDecodersStopBuffering usually makes its first check). */
    bool b_found_video = false;

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];
        if( p_es->fmt.i_cat != VIDEO_ES || !p_es->p_dec )
            continue;
        b_found_video = true;

        /* Both the fill count and the target come from the decoder
         * itself (see DecoderVideoCacheTarget): the decoder is what
         * stops decoding ahead once the target is reached, so the gate
         * must wait on the exact same number or it would never see
         * 100% and only ever end at EOF. */
        size_t i_pic_count, i_target_count;
        bool b_starved;
        if( !input_DecoderGetCacheState( p_es->p_dec, &i_pic_count,
                                         &i_target_count, NULL,
                                         &b_starved ) )
            return 1.0; /* not a caching decoder (should not happen) */

        /* Watchdog: a fill that makes no progress (decoder wedged before
         * its first picture, pool famine...) must not hold playback
         * hostage forever -- give up as if the user skipped. Progress is
         * measured on the fifo count, not on time spent: a slow fill
         * that IS progressing may legitimately take longer than any
         * fixed timeout (that is the point of the feature). */
        /* A starved decoder (ES fifo empty, decoder idle) will not
         * produce anything more however long the gate stays shut:
         * stills hit this permanently (one picture per cell), plain
         * EOF does too. Start with whatever there is. Two guards:
         * target > 0 (a picture was measured once -- an idle decoder
         * before the first data arrives is just a young stream), AND
         * at least one picture produced IN THIS EPISODE. The second
         * one is the dvdnav seek fix: a seek flushes the decoder NOW
         * but dvdnav only fires its HOP/RESET_PCR a beat later on the
         * demux thread -- in that interregnum the decoder is starved
         * (flushed empty) while the target survives from before the
         * seek, and this bail-out was opening the gate at ~1% against
         * a stale clock (stream_duration in the hundreds of seconds):
         * ~120-220 pictures dropped "too late" after every DVD seek.
         * With the guard the gate simply keeps waiting the few ms
         * until the real reset re-arms everything. */
        /* Third guard, added on Blu-ray: starvation must PERSIST. A disc
         * that jumps to a playlist (title picked from a menu) leaves the
         * decoder momentarily dry while libbluray seeks, and an optical
         * drive delivering barely above 1x runs the ES fifo empty between
         * bursts -- both looked "starved" for a few tens of ms and cut
         * fills that were climbing steadily (measured: an episode killed
         * at 13 pictures after 402 ms, having gone 1% -> 12% without
         * stalling). Real starvation -- EOF, a still, a source that has
         * genuinely stopped -- lasts, so it still opens the gate one
         * grace period later. Progress in the meantime rearms it. */
        if( b_starved && i_target_count > 0 && i_pic_count > 0 )
        {
            vlc_tick_t i_starve_now = mdate();
            if( p_sys->i_video_cache_starved_since == VLC_TICK_INVALID )
                p_sys->i_video_cache_starved_since = i_starve_now;
            else if( i_starve_now - p_sys->i_video_cache_starved_since
                     >= VIDEO_CACHE_STARVE_GRACE )
            {
                msg_Dbg( p_sys->p_input, "video cache fill: decoder starved "
                         "(%zu pictures), starting", i_pic_count );
                return 1.0;
            }
        }
        else
            p_sys->i_video_cache_starved_since = VLC_TICK_INVALID;

        vlc_tick_t now = mdate();
        if( p_sys->i_video_cache_episode_start == VLC_TICK_INVALID )
            p_sys->i_video_cache_episode_start = now;

        /* A decoder whose picture size cannot be measured (opaque
         * hardware pictures: no planes to sum) never gets a target; once
         * it has produced a picture it parks on the buffering gate like
         * a stock decoder, holding the next one in hand -- the fifo
         * count will never move. Waiting for it is waiting for nothing:
         * start right away (the look-ahead cache effectively cannot
         * apply to such decoders). */
        if( i_target_count == 0 && i_pic_count == 0
         && input_DecoderIsReadyWaiting( p_es->p_dec )
         && now - p_sys->i_video_cache_episode_start >= 100000 )
        {
            msg_Dbg( p_sys->p_input, "video cache fill: picture size "
                     "unmeasurable and decoder ready, starting" );
            return 1.0;
        }

        if( i_pic_count > 0
              && now - p_sys->i_video_cache_episode_start
                 > VIDEO_CACHE_FILL_WALL_TIMEOUT
                 /* The healthy-rate exemption needs a sizeable target:
                  * pictures piling up with target still 0 means their
                  * size cannot be measured (opaque hardware pictures) --
                  * the gate would never complete, keep the hard wall. */
              && ( i_target_count == 0
                || (int64_t)i_pic_count * CLOCK_FREQ
                   < (int64_t)VIDEO_CACHE_FILL_MIN_RATE
                     * ( now - p_sys->i_video_cache_episode_start ) ) )
        {
            msg_Dbg( p_sys->p_input, "video cache fill too slow (%zu "
                     "pictures after %d ms), starting with what there is",
                     i_pic_count,
                     (int)(( now - p_sys->i_video_cache_episode_start )
                           / 1000) );
            return 1.0;
        }
        if( p_sys->i_video_cache_progress_date == VLC_TICK_INVALID
         || i_pic_count != p_sys->i_video_cache_last_count )
        {
            p_sys->i_video_cache_last_count = i_pic_count;
            p_sys->i_video_cache_progress_date = now;
        }
        else if( i_pic_count > 0
              && now - p_sys->i_video_cache_progress_date > CLOCK_FREQ )
        {
            /* Pictures accumulated but the count stopped growing for a
             * whole second while the vout is on hold (nothing consumes
             * them): the decoder is blocked on pool exhaustion (its
             * in-flight/reference pictures eat into the headroom in
             * codec-specific ways) or starved by a slow input. Either
             * way the cache is as full as it will ever get: start. */
            msg_Dbg( p_sys->p_input, "video cache fill topped out at %zu "
                     "pictures (target %zu), starting", i_pic_count,
                     i_target_count );
            return 1.0;
        }
        else if( now - p_sys->i_video_cache_progress_date
                 > ( p_sys->b_video_cache_refill
                     ? 3 * CLOCK_FREQ / 2 : VIDEO_CACHE_STALL_TIMEOUT ) )
        {
            /* Refill episodes get a much shorter zero-picture patience
             * (1.5 s vs the initial fill's codec-init margin): the
             * decoder was producing an instant ago, so nothing showing
             * up means the DRAIN was source-bound (live HLS, starved
             * transcoder) and holding longer buys nothing. The
             * ineffective-episode strike then backs the next attempt
             * off exponentially, so a persistently source-bound stream
             * degrades to a rare short hiccup -- empirically measured,
             * no fragile liveness heuristics (b_can_pace_control is
             * true even for live adaptive streams). */
            msg_Warn( p_sys->p_input, "video cache fill stalled with no "
                      "picture at all, giving the wait up" );
            p_sys->b_video_cache_skip = true;
            return 1.0;
        }

        double f_ratio;
        if( i_target_count == 0 )
        {
            /* Nothing decoded into the vout yet: no picture size to
             * size a target against, keep waiting (EOF is handled by
             * the starved check in EsOutDecodersIsEmpty, wedges by the
             * watchdog above). */
            f_ratio = 0.0;
        }
        else
        {
            f_ratio = (double)i_pic_count / (double)i_target_count;
            if( f_ratio > 1.0 )
                f_ratio = 1.0;
        }

        if( f_ratio < 1.0 && p_sys->i_video_cache_fill_percent > 0 )
        {
            /* Throttled OSD: rechecks fire on every decoded picture,
             * far more often than a human needs a percentage refresh. */
            if( now - p_sys->i_video_cache_osd_last >= CLOCK_FREQ / 4 )
            {
                vout_thread_t *p_vout = NULL;
                input_DecoderGetObjects( p_es->p_dec, &p_vout, NULL );
                if( p_vout )
                {
                    p_sys->i_video_cache_osd_last = now;
                    /* Scale the displayed percentage to the resume
                     * threshold (fill-percent), not to the full target:
                     * "Buffering... 100%" is then exactly the moment
                     * playback resumes, whatever the threshold. */
                    int i_pct = (int)( 100.0 * f_ratio * 100.0
                                       / p_sys->i_video_cache_fill_percent );
                    if( i_pct > 100 )
                        i_pct = 100;
                    vout_OSDMessage( p_vout, VOUT_SPU_CHANNEL_OSD,
                        _("Buffering... %d%%"), i_pct );
                    vlc_object_release( p_vout );
                }
            }
        }

        return f_ratio;
    }

    /* A video ES with no vout yet still means "keep waiting"; only the
     * true absence of any video ES means there is nothing to buffer
     * against. */
    return b_found_video ? 0.0 : 1.0;
}

/**
 * Ends a look-ahead cache fill episode: re-bases the dates of the held
 * pictures by i_offset then releases the vout hold. The pictures were
 * dated while the clock still had its pre-episode origin; i_offset is
 * whatever shift the caller just applied to that origin (the conversion
 * is otherwise stable during buffering: with pace control the drift term
 * is never updated and the reference point only moves on discontinuities,
 * which reset the whole episode anyway). Must be called AFTER the clock
 * origin change and BEFORE input_DecoderStopWait, so the parked decoder
 * only resumes against an unheld, re-based vout.
 */
static void EsOutVideoCacheRelease( es_out_t *out, vlc_tick_t i_offset )
{
    es_out_sys_t *p_sys = out->p_sys;

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];
        if( p_es->fmt.i_cat != VIDEO_ES || !p_es->p_dec )
            continue;

        vout_thread_t *p_vout = NULL;
        input_DecoderGetObjects( p_es->p_dec, &p_vout, NULL );
        if( p_vout )
        {
            if( i_offset != 0 )
                vout_OffsetCacheDates( p_vout, i_offset );
            /* Drop the "Buffering %" OSD right away on SOFTWARE outputs: a
             * still-fading OSD forces them into the picture_Copy+blend path on
             * every frame of the resumed playback -- measured at ~15% of the
             * core on the Mini G4, enough to re-drain the fresh cache and loop
             * the refill forever.
             *
             * Do NOT flush it on the ATI DVD path. Its display composites OSD
             * regions in a small overlay window, so there is no full-picture
             * blend cost. More importantly, a keyboard seek posts its position
             * OSD just before the refill: flushing the shared OSD channel here
             * erased that user feedback. The failure looked intermittent
             * because it depended on whether the seek opened a cache episode.
             * The display unhold itself is NOT queued here anymore: it
             * moved into input_DecoderStopWait (which every caller of
             * this function runs right after), where the decoder owner
             * lock orders it after any in-flight fill picture's
             * hold(true) -- queuing it from here could be overtaken by
             * such a straggler and wedge the vout held. */
            if( !var_GetBool( p_vout->obj.libvlc, "dvddriver-subs" ) )
                vout_FlushSubpictureChannel( p_vout,
                                             VOUT_SPU_CHANNEL_OSD );
            /* A virtual pause about to be materialized (see
             * EsOutDecodersStopBuffering) must reach the vout BEFORE
             * the unhold that input_DecoderStopWait queues right after
             * this function: both traverse the vout control queue, so
             * pushing the pause here guarantees the vout wakes up
             * unheld-but-paused and leaves the (pause-date-anchored)
             * pictures alone. The decoder-side application that follows
             * de-dups on the vout side. */
            if( p_sys->b_video_cache_pause_virtual )
                vout_ChangePause( p_vout, true, p_sys->i_pause_date );
            vlc_object_release( p_vout );
        }
        break;
    }

    p_sys->i_video_cache_last_count = 0;
    p_sys->i_video_cache_progress_date = VLC_TICK_INVALID;
    p_sys->i_video_cache_episode_start = VLC_TICK_INVALID;
    p_sys->i_video_cache_starved_since = VLC_TICK_INVALID;
}

/* Cool-down between two mid-play refill episodes -- only a backstop
 * against degenerate re-trigger loops: the fill itself already spaces
 * episodes naturally, and on over-budget content an immediate refill
 * (hold, then fluid stretch) beats dribbling late pictures, which is the
 * whole point of the option. */
#define VIDEO_CACHE_REFILL_COOLDOWN (1 * CLOCK_FREQ)

/**
 * True when the look-ahead cache is active, not inhibited, and currently
 * holds a cushion of decoded pictures ahead of the display. Side-effect
 * free (unlike EsOutVideoCacheFillRatio, which is the startup gate).
 *
 * In that state a "late" PCR from the demuxer is expected and benign: the
 * demuxer is throttled by the cache's back-pressure (its fifo fills once
 * the cache reaches target), not by a genuine clock problem, and the
 * display keeps drawing from the cushion. Resetting the clock / inflating
 * pts_delay there (see ES_OUT_SET_PCR) just throws the buffered data away
 * and forces a needless re-buffer episode -- observed on DVD as one stall
 * every ~cache-depth seconds with video-cache-mb enabled. A true drain
 * (fifo hits 0) is NOT masked here: it still reaches
 * EsOutVideoCacheMaybeRefill, which refills properly.
 */
static bool EsOutVideoCacheHasCushion( es_out_t *out )
{
    es_out_sys_t *p_sys = out->p_sys;

    if( p_sys->i_video_cache_bytes == 0 || p_sys->b_video_cache_inhibit
     || p_sys->b_video_cache_skip )
        return false;

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];
        if( p_es->fmt.i_cat != VIDEO_ES || !p_es->p_dec )
            continue;

        size_t i_count, i_target;
        bool b_starved;
        if( !input_DecoderGetCacheState( p_es->p_dec, &i_count, &i_target,
                                         NULL, &b_starved ) )
            return false;
        /* A measured target (a picture was sized) and ANY picture decoded
         * ahead: the display has something to draw while the demuxer
         * catches up, so absorb the late PCR. The threshold is deliberately
         * just >0, not a comfortable margin: a full drain to 0 is caught
         * one step earlier by EsOutVideoCacheMaybeRefill (a proper refill),
         * so the 1-2 picture window between "comfortable" and "empty" must
         * be absorbed here too -- otherwise a late PCR landing in that
         * window still triggers the disruptive clock reset (throwing away
         * ~20 s of cache), which is exactly the stall we are removing. */
        if( i_target > 0 && i_count > 0 )
            return true;
    }
    return false;
}

/**
 * Mid-play counterpart of the startup/seek fill gate: when the look-ahead
 * cache has fully drained during playback (the decoder fell behind the
 * display), open a fresh buffering episode to refill it -- blocking a few
 * seconds buys a fluid stretch, instead of a long dribble of late
 * pictures. Called from ES_OUT_SET_PCR (demux still active) and from
 * EsOutDecodersIsEmpty (fully demuxed local file: the input's EOF wait
 * polls it every INPUT_IDLE_SLEEP, and no PCR will ever come again).
 */
static void EsOutVideoCacheMaybeRefill( es_out_t *out )
{
    es_out_sys_t *p_sys = out->p_sys;

    if( p_sys->i_video_cache_bytes == 0 || p_sys->b_buffering
     || p_sys->b_video_cache_inhibit
     || p_sys->b_paused || p_sys->p_pgrm == NULL
     || p_sys->p_next_frame_es != NULL )
        return;

    /* Ineffective episodes double the cooldown (up to 32x): see the
     * accounting in EsOutDecodersStopBuffering. */
    const vlc_tick_t i_cooldown = VIDEO_CACHE_REFILL_COOLDOWN
                                << p_sys->i_video_cache_bad_refills;
    const vlc_tick_t now = mdate();
    if( p_sys->i_video_cache_refill_last_end > VLC_TICK_INVALID
     && now - p_sys->i_video_cache_refill_last_end < i_cooldown )
        return;

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];
        if( p_es->fmt.i_cat != VIDEO_ES || !p_es->p_dec )
            continue;

        size_t i_count, i_target;
        bool b_starved;
        if( !input_DecoderGetCacheState( p_es->p_dec, &i_count, &i_target,
                                         NULL, &b_starved ) )
            return;
        /* Only a true mid-play drain qualifies: the decoder has shown
         * everything it produced (fifo empty) but still has compressed
         * data queued (not starved/EOF). i_target == 0 means no picture
         * was ever measured -- the startup gate's business, not ours. */
        if( i_target == 0 || i_count > 0 || b_starved )
            return;

        msg_Dbg( p_sys->p_input, "video cache drained mid-play, "
                 "re-buffering to refill it" );

        /* Post the "Buffering" OSD right at the trigger: on over-budget
         * content the first fresh picture (hence the first FillRatio
         * recheck, which owns the periodic OSD refresh) can take a
         * second or more -- the picture must not just freeze mutely. */
        {
            vout_thread_t *p_vout = NULL;
            input_DecoderGetObjects( p_es->p_dec, &p_vout, NULL );
            if( p_vout )
            {
                p_sys->i_video_cache_osd_last = now;
                vout_OSDMessage( p_vout, VOUT_SPU_CHANNEL_OSD,
                                 _("Buffering... %d%%"), 0 );
                vlc_object_release( p_vout );
            }
        }

        for( int j = 0; j < p_sys->i_es; j++ )
        {
            es_out_id_t *p_wait = p_sys->es[j];
            if( !p_wait->p_dec )
                continue;
            /* Pause the audio path outright: the aout typically holds
             * 0.5-1 s of already-decoded samples which would keep
             * playing over the frozen picture -- A/V desync for the
             * whole episode. Paused, they resume shifted by the same
             * offset as everything else when the gate opens. (A user
             * pause during the episode is absorbed by the decoder's
             * pause state being level-triggered; the pause-then-resume-
             * during-episode corner case merely lets the audio restart
             * a second early.) */
            if( p_wait->fmt.i_cat == AUDIO_ES )
                input_DecoderChangePause( p_wait->p_dec, true, now );
            input_DecoderStartWait( p_wait->p_dec );
            if( p_wait->p_dec_record )
                input_DecoderStartWait( p_wait->p_dec_record );
        }

        p_sys->b_buffering = true;
        p_sys->i_buffering_extra_initial = 0;
        p_sys->i_buffering_extra_stream = 0;
        p_sys->i_buffering_extra_system = 0;
        p_sys->i_preroll_end = -1;
        p_sys->i_prev_stream_level = -1;
        p_sys->b_video_cache_skip = false;
        p_sys->i_video_cache_last_count = 0;
        p_sys->i_video_cache_progress_date = VLC_TICK_INVALID;
        p_sys->i_video_cache_episode_start = VLC_TICK_INVALID;
        p_sys->i_video_cache_starved_since = VLC_TICK_INVALID;
        p_sys->b_video_cache_refill = true;
        p_sys->i_video_cache_refill_start = now;
        return;
    }
}

static void EsOutDecodersStopBuffering( es_out_t *out, bool b_forced )
{
    es_out_sys_t *p_sys = out->p_sys;

    vlc_tick_t i_stream_start;
    vlc_tick_t i_system_start;
    vlc_tick_t i_stream_duration;
    vlc_tick_t i_system_duration;
    if (input_clock_GetState( p_sys->p_pgrm->p_clock,
                                  &i_stream_start, &i_system_start,
                                  &i_stream_duration, &i_system_duration ))
        return;

    vlc_tick_t i_preroll_duration = 0;
    if( p_sys->i_preroll_end >= 0 )
        i_preroll_duration = __MAX( p_sys->i_preroll_end - i_stream_start, 0 );

    const vlc_tick_t i_buffering_duration = p_sys->i_pts_delay +
                                         i_preroll_duration +
                                         p_sys->i_buffering_extra_stream - p_sys->i_buffering_extra_initial;

    if( i_stream_duration <= i_buffering_duration && !b_forced )
    {
        double f_level;
        if (i_buffering_duration == 0)
            f_level = 0;
        else
            f_level = __MAX( (double)i_stream_duration / i_buffering_duration, 0 );
        input_SendEventCache( p_sys->p_input, f_level );

        int i_level = (int)(100 * f_level);
        if( p_sys->i_prev_stream_level != i_level )
        {
            msg_Dbg( p_sys->p_input, "Buffering %d%%", i_level );
            p_sys->i_prev_stream_level = i_level;
        }

        return;
    }

    if( !b_forced )
    {
        double f_cache_ratio = EsOutVideoCacheFillRatio( out );
        if( f_cache_ratio < (double)p_sys->i_video_cache_fill_percent / 100.0 )
        {
            /* Report whichever of the two buffering criteria (the
             * existing compressed-stream-time one above, or our
             * decoded-picture-cache one) is furthest from done. */
            double f_stream_level = i_buffering_duration > 0
                ? __MAX( (double)i_stream_duration / i_buffering_duration, 0 )
                : 1.0;
            double f_level = __MIN( f_stream_level, f_cache_ratio );
            input_SendEventCache( p_sys->p_input, f_level );

            int i_level = (int)(100 * f_level);
            if( p_sys->i_prev_stream_level != i_level )
            {
                msg_Dbg( p_sys->p_input, "Buffering %d%%", i_level );
                p_sys->i_prev_stream_level = i_level;
            }
            return;
        }
    }

    /* An MVC picture is assembled from two independently demuxed Blu-ray
     * views.  The normal compressed-stream threshold can be reached after
     * only one primary block, before the paired decoder has a complete
     * picture.  Do not enter input_DecoderWait() in that state: it holds the
     * es_out lock and prevents the demuxer from supplying the missing blocks,
     * turning every 3D clip boundary into the five-second safety timeout.
     * Staying in buffering lets both chained demuxers continue.  Pace that
     * continuation: on a fast local ISO, running flat-out can enqueue and
     * finish a 22-second play item while macOS is still spending four seconds
     * switching the HDMI scanout to frame packing.  The PLAYITEM event then
     * tears down the decoder before its first decoded picture is presented.
     * One 60-KiB demux block every 10 ms is still over 6 MB/s (well above the
     * Blu-ray maximum) while preventing that destructive look-ahead. Keep a
     * two-second wall-clock escape for damaged streams that never form a pair. */
    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];
        if( p_es->p_dec && p_es->fmt.i_cat == VIDEO_ES &&
            p_es->fmt.i_codec == VLC_CODEC_H264_MVC &&
            !input_DecoderIsReadyWaiting( p_es->p_dec ) &&
            i_system_duration < 2 * CLOCK_FREQ )
        {
            msleep( VLC_TICK_FROM_MS(10) );
            return;
        }
    }

    input_SendEventCache( p_sys->p_input, 1.0 );

    msg_Dbg( p_sys->p_input, "Stream buffering done (%d ms in %d ms)",
              (int)(i_stream_duration/1000), (int)(i_system_duration/1000) );
    p_sys->b_buffering = false;
    p_sys->i_preroll_end = -1;
    p_sys->i_prev_stream_level = -1;

    if( p_sys->i_buffering_extra_initial > 0 )
    {
        /* FIXME wrong ? */
        return;
    }

    const vlc_tick_t i_decoder_buffering_start = mdate();
    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];

        if( !p_es->p_dec || p_es->fmt.i_cat == SPU_ES )
            continue;

        input_DecoderWait( p_es->p_dec );
        if( p_es->p_dec_record )
            input_DecoderWait( p_es->p_dec_record );
    }

    msg_Dbg( p_sys->p_input, "Decoder wait done in %d ms",
              (int)(mdate() - i_decoder_buffering_start)/1000 );

    /* Here is a good place to destroy unused vout with every demuxer --
     * unless a selected video track is between two decoders and has not
     * asked for its own yet, in which case the "unused" one is the very
     * one it is about to ask for.
     *
     * That happens on every resolution change of an adaptive stream (HLS
     * variant switch, an advertisement encoded differently): the demuxer
     * restarts, the video ES is removed and re-added, and its decoder is
     * reloaded. If the re-buffering that follows completes before the new
     * decoder has seen its first picture -- a hundred milliseconds, and
     * routine when the switch itself triggered the re-buffering -- the
     * free vout is destroyed here and the decoder creates a brand new one
     * a moment later. Reusing it only restarts the "vout display"; a new
     * vout also means a new video *window*, and on macOS the interface
     * reacts to that: the video view is torn down, the window falls back
     * to the playlist (sometimes collapsing to its toolbar) and pops back
     * to video a fraction of a second later, on every quality change. */
    bool b_video_pending = false;
    for( int i = 0; i < p_sys->i_es && !b_video_pending; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];

        if( p_es->fmt.i_cat != VIDEO_ES || p_es->p_dec == NULL )
            continue;

        vout_thread_t *p_vout;
        input_DecoderGetObjects( p_es->p_dec, &p_vout, NULL );
        if( p_vout != NULL )
            vlc_object_release( p_vout );
        else
            b_video_pending = true;
    }

    if( !b_video_pending && !EsOutKeepDiscVout( p_sys ) )
        input_resource_TerminateVout( input_priv(p_sys->p_input)->p_resource );
    else
        msg_Dbg( p_sys->p_input, "keeping the free vout: a selected video "
                 "track has not requested one yet or a Blu-ray session is "
                 "between clips" );

    /* */
    const vlc_tick_t i_wakeup_delay = 10*1000; /* FIXME CLEANUP thread wake up time*/
    const vlc_tick_t i_current_date = p_sys->b_paused ? p_sys->i_pause_date : mdate();

    if( p_sys->b_video_cache_refill )
    {
        /* Mid-play refill episode: the clock reference dates back to the
         * last start/seek, far behind the play position (and for a fully
         * demuxed local file it will never move again), so the absolute
         * re-anchoring below would park playback that far in the future.
         * What the episode really was is a pause of its own duration:
         * shift the origin (and the held pictures) by exactly that. */
        vlc_tick_t i_offset = i_current_date + i_wakeup_delay
                            - p_sys->i_video_cache_refill_start;
        /* The drain that opened the episode means the decoder was
         * already running LATE: the held pictures carry that lateness
         * on top of the episode's duration. When the oldest held
         * picture is visible, anchor IT at "now" instead, so the
         * refilled cushion is a full look-ahead, not late from birth. */
        for( int i = 0; i < p_sys->i_es; i++ )
        {
            es_out_id_t *p_es = p_sys->es[i];
            if( p_es->fmt.i_cat != VIDEO_ES || !p_es->p_dec )
                continue;
            vout_thread_t *p_vout = NULL;
            input_DecoderGetObjects( p_es->p_dec, &p_vout, NULL );
            if( p_vout )
            {
                vlc_tick_t i_first = vout_GetDecoderFifoFirstDate( p_vout );
                if( i_first > VLC_TICK_INVALID
                 && i_current_date + i_wakeup_delay - i_first > i_offset )
                    i_offset = i_current_date + i_wakeup_delay - i_first;
                vlc_object_release( p_vout );
            }

            /* Effectiveness accounting: an episode that ends nearly
             * empty (a starved decoder released it right away, the
             * source cannot feed the cache) bought no fluid stretch at
             * all -- each one doubles the refill cooldown so a stream
             * that cannot actually be cached degrades to rare pauses
             * instead of a permanent freeze/0%-buffering loop. Any
             * effective episode resets the penalty. */
            size_t i_count, i_target;
            if( input_DecoderGetCacheState( p_es->p_dec, &i_count,
                                            &i_target, NULL, NULL ) )
            {
                if( i_target > 0 && i_count * 10 < i_target )
                {
                    if( p_sys->i_video_cache_bad_refills < 5 )
                        p_sys->i_video_cache_bad_refills++;
                    msg_Dbg( p_sys->p_input, "video cache refill "
                             "ineffective (%zu/%zu pictures, strike %u), "
                             "backing off", i_count, i_target,
                             p_sys->i_video_cache_bad_refills );
                }
                else
                    p_sys->i_video_cache_bad_refills = 0;
            }
            break;
        }
        input_clock_OffsetSystemOrigin( p_sys->p_pgrm->p_clock, i_offset );
        EsOutVideoCacheRelease( out, i_offset );
        /* Resume the audio path paused at the trigger, shifted by the
         * exact same offset as the clock and the held pictures so A/V
         * stays in sync (unless the user paused meanwhile: their resume
         * will unpause it). */
        if( !p_sys->b_paused )
            for( int i = 0; i < p_sys->i_es; i++ )
            {
                es_out_id_t *p_es = p_sys->es[i];
                if( p_es->fmt.i_cat == AUDIO_ES && p_es->p_dec )
                    input_DecoderChangePause( p_es->p_dec, false,
                        p_sys->i_video_cache_refill_start + i_offset );
            }
        p_sys->b_video_cache_refill = false;
        p_sys->i_video_cache_refill_last_end = i_current_date;
    }
    else
    {
        /* A live IEC 61937 carrier can retain a driver-reported HDMI output
         * horizon after its software queue was flushed. The first post-seek
         * programme block cannot reach the wire before that date. Rebase the
         * common clock by this measured value; cold starts and ordinary PCM
         * flushes report no usable horizon and keep the historical path. */
        vlc_tick_t i_audio_output_delay = 0;
        for( int i = 0; i < p_sys->i_es; i++ )
        {
            es_out_id_t *p_es = p_sys->es[i];
            vlc_tick_t i_delay;
            if( p_es->fmt.i_cat == AUDIO_ES && p_es->p_dec != NULL
             && input_DecoderGetAudioOutputDelay( p_es->p_dec, &i_delay )
             && i_delay > i_audio_output_delay
             && i_delay < 5 * CLOCK_FREQ )
                i_audio_output_delay = i_delay;
        }
        if( i_audio_output_delay > 0 )
            msg_Dbg( p_sys->p_input, "delaying seek A/V gate by measured "
                     "audio output horizon: %"PRId64" us",
                     i_audio_output_delay );

        msg_Warn( p_sys->p_input,
                  "clock release anchor: paused=%d pause_date=%"PRId64
                  " now=%"PRId64" buffering=%"PRId64
                  " wakeup=%"PRId64" audio_horizon=%"PRId64,
                  p_sys->b_paused, p_sys->i_pause_date, i_current_date,
                  i_buffering_duration, i_wakeup_delay,
                  i_audio_output_delay );

        const vlc_tick_t i_release_origin = i_current_date + i_wakeup_delay
                                          + i_audio_output_delay
                                          - i_buffering_duration;
        /* MVC Blu-ray can expose the base and dependent views through
         * distinct ES programs.  Releasing only the currently selected
         * program leaves the sibling clock on its pre-buffering system grid;
         * when that PCR becomes active at the menu junction it overwrites the
         * good mapping and stalls both views.  Anchor every initialized
         * program clock to the same presentation origin. */
        for( int i = 0; i < p_sys->i_pgrm; i++ )
        {
            vlc_tick_t rs, rsy, ds, dsy;
            if( input_clock_GetState( p_sys->pgrm[i]->p_clock,
                                      &rs, &rsy, &ds, &dsy ) == VLC_SUCCESS )
                input_clock_ChangeSystemOrigin( p_sys->pgrm[i]->p_clock,
                                                true, i_release_origin );
        }
        {
            vlc_tick_t rs, rsy, ds, dsy;
            if( input_clock_GetState( p_sys->p_pgrm->p_clock,
                                      &rs, &rsy, &ds, &dsy ) == VLC_SUCCESS )
                msg_Warn( p_sys->p_input,
                          "clock release result: rate=%d ref_stream=%"PRId64
                          " ref_system=%"PRId64" stream_duration=%"PRId64
                          " system_duration=%"PRId64,
                          input_clock_GetRate(p_sys->p_pgrm->p_clock),
                          rs, rsy, ds, dsy );
        }

        /* Look-ahead cache: re-base the held pictures onto the fresh
         * origin and let the vout consume them. The shift is measured as
         * the reference's system-side move across the origin change
         * (i_system_start still holds the pre-change reference from the
         * input_clock_GetState call at the top of this function; nothing
         * in between touches the clock, the es_out lock is held
         * throughout). The release itself is unconditional: even if the
         * clock state could not be re-read (it cannot fail right after
         * ChangeSystemOrigin, but never leave that unchecked), the vout
         * hold and the buffering OSD must not stay stuck forever. */
        if( p_sys->i_video_cache_bytes > 0 )
        {
            vlc_tick_t i_offset = 0;
            vlc_tick_t i_stream_start2, i_system_after;
            vlc_tick_t i_stream_duration2, i_system_duration2;
            if( !input_clock_GetState( p_sys->p_pgrm->p_clock,
                                       &i_stream_start2, &i_system_after,
                                       &i_stream_duration2,
                                       &i_system_duration2 ) )
                i_offset = i_system_after - i_system_start;

            /* An effective start/seek fill clears the refill-backoff
             * strikes: whatever starved the earlier refills (a slow
             * stretch of the source) is over. */
            for( int i = 0; i < p_sys->i_es; i++ )
            {
                es_out_id_t *p_es = p_sys->es[i];
                if( p_es->fmt.i_cat != VIDEO_ES || !p_es->p_dec )
                    continue;
                size_t i_count, i_target;
                if( input_DecoderGetCacheState( p_es->p_dec, &i_count,
                                                &i_target, NULL, NULL )
                 && i_target > 0 && i_count * 2 >= i_target )
                    p_sys->i_video_cache_bad_refills = 0;
                break;
            }

            EsOutVideoCacheRelease( out, i_offset );
        }
    }

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];

        if( !p_es->p_dec )
            continue;

        input_DecoderStopWait( p_es->p_dec );
        if( p_es->p_dec_record )
            input_DecoderStopWait( p_es->p_dec_record );
    }

    /* A user pause kept virtual during the episode materializes now, in
     * one clean transition dated at the ORIGINAL pause instant (the
     * clock origin above was anchored at that same date, so playback
     * freezes exactly where the user left it). From here on the stock
     * pause bookkeeping applies: the eventual resume shifts the clock
     * and the vout by the same span, symmetrically. */
    if( p_sys->b_video_cache_pause_virtual )
    {
        p_sys->b_video_cache_pause_virtual = false;
        msg_Dbg( p_sys->p_input, "video cache: materializing the virtual "
                 "pause at the gate release" );
        EsOutProgramChangePause( out, true, p_sys->i_pause_date );
        EsOutDecodersChangePause( out, true, p_sys->i_pause_date );
    }
}
static void EsOutDecodersChangePause( es_out_t *out, bool b_paused, vlc_tick_t i_date )
{
    es_out_sys_t *p_sys = out->p_sys;

    /* Pause decoders first */
    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *es = p_sys->es[i];

        if( es->p_dec )
        {
            input_DecoderChangePause( es->p_dec, b_paused, i_date );
            if( es->p_dec_record )
                input_DecoderChangePause( es->p_dec_record, b_paused, i_date );
        }
    }
}

static bool EsOutIsExtraBufferingAllowed( es_out_t *out )
{
    es_out_sys_t *p_sys = out->p_sys;

    size_t i_size = 0;
    for( int i = 0; i < p_sys->i_es; i++ )
    {
        es_out_id_t *p_es = p_sys->es[i];

        if( p_es->p_dec )
            i_size += input_DecoderGetFifoSize( p_es->p_dec );
        if( p_es->p_dec_record )
            i_size += input_DecoderGetFifoSize( p_es->p_dec_record );
    }
    //msg_Info( out, "----- EsOutIsExtraBufferingAllowed =% 5d KiB -- ", i_size / 1024 );

    /* TODO maybe we want to be able to tune it ? */
#if defined(OPTIMIZE_MEMORY)
    const size_t i_level_high = 512*1024;  /* 0.5 MiB */
#else
    const size_t i_level_high = 10*1024*1024; /* 10 MiB */
#endif
    return i_size < i_level_high;
}

static void EsOutProgramChangePause( es_out_t *out, bool b_paused, vlc_tick_t i_date )
{
    es_out_sys_t *p_sys = out->p_sys;

    for( int i = 0; i < p_sys->i_pgrm; i++ )
        input_clock_ChangePause( p_sys->pgrm[i]->p_clock, b_paused, i_date );
}

static void EsOutDecoderChangeDelay( es_out_t *out, es_out_id_t *p_es )
{
    es_out_sys_t *p_sys = out->p_sys;

    /* Decoder timestamps must not be moved before the clock origin.  Apart
     * from being needlessly fragile at startup, a negative audio timestamp
     * cannot survive a seek: the decoder gate opens only once video preroll
     * is complete, at which point the audio output correctly rejects the
     * leading samples as late.
     *
     * Translate every ES by the opposite of the earliest requested delay.
     * This preserves all relative A/V/subtitle timing exactly.  In the HDMI
     * projector case, audio=-D becomes audio=0 and video/subtitles=+D, so the
     * audio queue never receives a timestamp in the past and the same
     * compensation remains valid across start, seek and resume. */
    vlc_tick_t i_earliest = __MIN( p_sys->i_audio_delay,
                                  p_sys->i_spu_delay );
    vlc_tick_t i_offset = i_earliest < 0 ? -i_earliest : 0;
    vlc_tick_t i_delay;

    if( p_es->fmt.i_cat == AUDIO_ES )
        i_delay = p_sys->i_audio_delay + i_offset;
    else if( p_es->fmt.i_cat == SPU_ES )
        i_delay = p_sys->i_spu_delay + i_offset;
    else if( p_es->fmt.i_cat == VIDEO_ES )
        i_delay = i_offset;
    else
        return;

    if( p_es->p_dec )
        input_DecoderChangeDelay( p_es->p_dec, i_delay );
    if( p_es->p_dec_record )
        input_DecoderChangeDelay( p_es->p_dec_record, i_delay );
}
static void EsOutProgramsChangeRate( es_out_t *out )
{
    es_out_sys_t      *p_sys = out->p_sys;

    for( int i = 0; i < p_sys->i_pgrm; i++ )
        input_clock_ChangeRate( p_sys->pgrm[i]->p_clock, p_sys->i_rate );
}

static void EsOutFrameNext( es_out_t *out )
{
    es_out_sys_t *p_sys = out->p_sys;

    assert( p_sys->b_paused );

    if( p_sys->p_next_frame_es == NULL )
    {
        /* Don't use 'foreach_es_then_es_slaves': next-frame is not implemented
         * on ES slaves */
        for( int i = 0; i < p_sys->i_es; i++ )
        {
            es_out_id_t *p_es = p_sys->es[i];

            if( p_es->p_master == NULL && p_es->fmt.i_cat == VIDEO_ES && p_es->p_dec )
            {
                p_sys->p_next_frame_es = p_es;
                break;
            }
        }

        if( p_sys->p_next_frame_es == NULL )
        {
            msg_Warn( p_sys->p_input, "No video track selected, ignoring 'frame next'" );
            return;
        }
    }

    vlc_tick_t i_duration;
    input_DecoderFrameNext( p_sys->p_next_frame_es->p_dec, &i_duration );

    msg_Dbg( out->p_sys->p_input, "EsOutFrameNext consummed %d ms", (int)(i_duration/1000) );
}
static vlc_tick_t EsOutGetBuffering( es_out_t *out )
{
    es_out_sys_t *p_sys = out->p_sys;
    vlc_tick_t i_stream_duration, i_system_start;

    if( !p_sys->p_pgrm )
        return 0;
    else
    {
        vlc_tick_t i_stream_start, i_system_duration;

        if( input_clock_GetState( p_sys->p_pgrm->p_clock,
                                  &i_stream_start, &i_system_start,
                                  &i_stream_duration, &i_system_duration ) )
            return 0;
    }

    vlc_tick_t i_delay;

    if( p_sys->b_buffering && p_sys->i_buffering_extra_initial <= 0 )
    {
        i_delay = i_stream_duration;
    }
    else
    {
        vlc_tick_t i_system_duration;

        if( p_sys->b_paused )
        {
            i_system_duration = p_sys->i_pause_date  - i_system_start;
            if( p_sys->i_buffering_extra_initial > 0 )
                i_system_duration += p_sys->i_buffering_extra_system - p_sys->i_buffering_extra_initial;
        }
        else
        {
            i_system_duration = mdate() - i_system_start;
        }

        const vlc_tick_t i_consumed = i_system_duration * INPUT_RATE_DEFAULT / p_sys->i_rate - i_stream_duration;
        i_delay = p_sys->i_pts_delay - i_consumed;
    }
    /* ★★★ Volontairement SIGNÉ — ne PAS plafonner à zéro ici.
     *
     * Cette valeur n'a qu'un seul appelant, ES_OUT_SET_TIMES, qui s'en sert
     * pour ramener le temps du DÉMULTIPLEXEUR au temps de LECTURE. En
     * développant, `temps_demux - i_delay` vaut exactement
     * `ref.stream + (maintenant - ref.system) - pts_delay` : c'est déjà la
     * position dérivée de l'horloge, et elle est juste tant qu'on la laisse
     * s'exprimer.
     *
     * Le plafonnement à zéro la cassait dès que le démultiplexeur prenait de
     * l'avance PUIS s'arrêtait — le cas d'un flux court entièrement
     * téléchargé. `i_stream_duration` reste alors figé sur le dernier PCR
     * pendant que le temps réel avance, donc `i_consumed` finit par dépasser
     * `i_pts_delay`, le délai devient négatif, et le plafonnement faisait
     * rapporter le temps du démultiplexeur lui-même, immobile. Mesuré sur
     * iBook G3 avec une vidéo Invidious de 19 s : image et son allaient au
     * bout, mais la barre de progression restait clouée à 00:09.
     *
     * En le laissant négatif, le temps rapporté continue d'avancer au rythme
     * réel une fois le démultiplexeur à sec — ce qui est précisément ce que
     * fait la lecture. L'appelant borne le résultat à [0, durée]. */
    return i_delay;
}

static void EsOutESVarUpdateGeneric( es_out_t *out, int i_id,
                                     const es_format_t *fmt, const char *psz_language,
                                     bool b_delete )
{
    es_out_sys_t      *p_sys = out->p_sys;
    input_thread_t    *p_input = p_sys->p_input;
    vlc_value_t       val, text;

    if( b_delete )
    {
        if( EsFmtIsTeletext( fmt ) )
            input_SendEventTeletextDel( p_sys->p_input, i_id );

        input_SendEventEsDel( p_input, fmt->i_cat, i_id );
        return;
    }

    /* Get the number of ES already added */
    const char *psz_var;
    if( fmt->i_cat == AUDIO_ES )
        psz_var = "audio-es";
    else if( fmt->i_cat == VIDEO_ES )
        psz_var = "video-es";
    else
        psz_var = "spu-es";

    var_Change( p_input, psz_var, VLC_VAR_CHOICESCOUNT, &val, NULL );
    if( val.i_int == 0 )
    {
        vlc_value_t val2;

        /* First one, we need to add the "Disable" choice */
        val2.i_int = -1; text.psz_string = _("Disable");
        var_Change( p_input, psz_var, VLC_VAR_ADDCHOICE, &val2, &text );
        val.i_int++;
    }

    /* Take care of the ES description */
    if( fmt->psz_description && *fmt->psz_description )
    {
        if( psz_language && *psz_language )
        {
            if( asprintf( &text.psz_string, "%s - [%s]", fmt->psz_description,
                          psz_language ) == -1 )
                text.psz_string = NULL;
        }
        else text.psz_string = strdup( fmt->psz_description );
    }
    else
    {
        if( psz_language && *psz_language )
        {
            if( asprintf( &text.psz_string, "%s %"PRId64" - [%s]", _( "Track" ), val.i_int, psz_language ) == -1 )
                text.psz_string = NULL;
        }
        else
        {
            if( asprintf( &text.psz_string, "%s %"PRId64, _( "Track" ), val.i_int ) == -1 )
                text.psz_string = NULL;
        }
    }

    input_SendEventEsAdd( p_input, fmt->i_cat, i_id, text.psz_string );
    if( EsFmtIsTeletext( fmt ) )
    {
        char psz_page[3+1];
        snprintf( psz_page, sizeof(psz_page), "%d%2.2x",
                  fmt->subs.teletext.i_magazine,
                  fmt->subs.teletext.i_page );
        input_SendEventTeletextAdd( p_sys->p_input,
                                    i_id, fmt->subs.teletext.i_magazine >= 0 ? psz_page : NULL );
    }

    free( text.psz_string );
}

static void EsOutESVarUpdate( es_out_t *out, es_out_id_t *es,
                              bool b_delete )
{
    EsOutESVarUpdateGeneric( out, es->i_id, &es->fmt, es->psz_language, b_delete );
}

static bool EsOutIsProgramVisible( es_out_t *out, int i_group )
{
    return out->p_sys->i_group_id == 0 || out->p_sys->i_group_id == i_group;
}

/* EsOutProgramSelect:
 *  Select a program and update the object variable
 */
static void EsOutProgramSelect( es_out_t *out, es_out_pgrm_t *p_pgrm )
{
    es_out_sys_t      *p_sys = out->p_sys;
    input_thread_t    *p_input = p_sys->p_input;
    int               i;

    if( p_sys->p_pgrm == p_pgrm )
        return; /* Nothing to do */

    if( p_sys->p_pgrm )
    {
        es_out_pgrm_t *old = p_sys->p_pgrm;
        msg_Dbg( p_input, "unselecting program id=%d", old->i_id );

        for( i = 0; i < p_sys->i_es; i++ )
        {
            if( p_sys->es[i]->p_pgrm == old && EsIsSelected( p_sys->es[i] ) &&
                p_sys->i_mode != ES_OUT_MODE_ALL )
                EsUnselect( out, p_sys->es[i], true );
        }

        p_sys->audio.p_main_es = NULL;
        p_sys->video.p_main_es = NULL;
        p_sys->sub.p_main_es = NULL;
    }

    msg_Dbg( p_input, "selecting program id=%d", p_pgrm->i_id );

    /* Mark it selected */
    p_pgrm->b_selected = true;

    /* Switch master stream */
    p_sys->p_pgrm = p_pgrm;

    /* Update "program" */
    input_SendEventProgramSelect( p_input, p_pgrm->i_id );

    /* Update "es-*" */
    input_SendEventEsDel( p_input, AUDIO_ES, -1 );
    input_SendEventEsDel( p_input, VIDEO_ES, -1 );
    input_SendEventEsDel( p_input, SPU_ES, -1 );
    input_SendEventTeletextDel( p_input, -1 );
    input_SendEventProgramScrambled( p_input, p_pgrm->i_id, p_pgrm->b_scrambled );

    /* TODO event */
    var_SetInteger( p_input, "teletext-es", -1 );

    for( i = 0; i < p_sys->i_es; i++ )
    {
        if( p_sys->es[i]->p_pgrm == p_sys->p_pgrm )
        {
            EsOutESVarUpdate( out, p_sys->es[i], false );
            EsOutUpdateInfo( out, p_sys->es[i], &p_sys->es[i]->fmt, NULL );
        }

        EsOutSelect( out, p_sys->es[i], false );
    }

    /* Ensure the correct running EPG table is selected */
    input_item_ChangeEPGSource( input_priv(p_input)->p_item, p_pgrm->i_id );

    /* Update now playing */
    if( p_pgrm->p_meta )
    {
        input_item_SetESNowPlaying( input_priv(p_input)->p_item,
                                    vlc_meta_Get( p_pgrm->p_meta, vlc_meta_ESNowPlaying ) );
        input_item_SetPublisher( input_priv(p_input)->p_item,
                                 vlc_meta_Get( p_pgrm->p_meta, vlc_meta_Publisher ) );
        input_item_SetTitle( input_priv(p_input)->p_item,
                             vlc_meta_Get( p_pgrm->p_meta, vlc_meta_Title ) );
        input_SendEventMeta( p_input );
        /* FIXME: we probably want to replace every input meta */
    }
}

/* EsOutAddProgram:
 *  Add a program
 */
static es_out_pgrm_t *EsOutProgramAdd( es_out_t *out, int i_group )
{
    es_out_sys_t      *p_sys = out->p_sys;
    input_thread_t    *p_input = p_sys->p_input;

    es_out_pgrm_t *p_pgrm = malloc( sizeof( es_out_pgrm_t ) );
    if( !p_pgrm )
        return NULL;

    /* Init */
    p_pgrm->i_id = i_group;
    p_pgrm->i_es = 0;
    p_pgrm->b_selected = false;
    p_pgrm->b_scrambled = false;
    p_pgrm->i_last_pcr = VLC_TICK_INVALID;
    p_pgrm->p_meta = NULL;
    p_pgrm->p_clock = input_clock_New( VLC_OBJECT(p_sys->p_input),
                                      p_sys->i_rate );
    if( !p_pgrm->p_clock )
    {
        free( p_pgrm );
        return NULL;
    }
    if( p_sys->b_paused )
        input_clock_ChangePause( p_pgrm->p_clock, p_sys->b_paused, p_sys->i_pause_date );
    input_clock_SetJitter( p_pgrm->p_clock, p_sys->i_pts_delay, p_sys->i_cr_average );

    /* Append it */
    TAB_APPEND( p_sys->i_pgrm, p_sys->pgrm, p_pgrm );

    /* Update "program" variable */
    if( EsOutIsProgramVisible( out, i_group ) )
        input_SendEventProgramAdd( p_input, i_group, NULL );

    if( i_group == p_sys->i_group_id || ( !p_sys->p_pgrm && p_sys->i_group_id == 0 ) )
        EsOutProgramSelect( out, p_pgrm );

    return p_pgrm;
}

/* EsOutDelProgram:
 *  Delete a program
 */
static int EsOutProgramDel( es_out_t *out, int i_group )
{
    es_out_sys_t      *p_sys = out->p_sys;
    input_thread_t    *p_input = p_sys->p_input;
    es_out_pgrm_t     *p_pgrm = NULL;
    int               i;

    for( i = 0; i < p_sys->i_pgrm; i++ )
    {
        if( p_sys->pgrm[i]->i_id == i_group )
        {
            p_pgrm = p_sys->pgrm[i];
            break;
        }
    }

    if( p_pgrm == NULL )
        return VLC_EGENERIC;

    if( p_pgrm->i_es )
    {
        msg_Dbg( p_input, "can't delete program %d which still has %i ES",
                 i_group, p_pgrm->i_es );
        return VLC_EGENERIC;
    }

    TAB_REMOVE( p_sys->i_pgrm, p_sys->pgrm, p_pgrm );

    /* If program is selected we need to unselect it */
    if( p_sys->p_pgrm == p_pgrm )
        p_sys->p_pgrm = NULL;

    input_clock_Delete( p_pgrm->p_clock );

    if( p_pgrm->p_meta )
        vlc_meta_Delete( p_pgrm->p_meta );
    free( p_pgrm );

    /* Update "program" variable */
    input_SendEventProgramDel( p_input, i_group );

    return VLC_SUCCESS;
}

/* EsOutProgramFind
 */
static es_out_pgrm_t *EsOutProgramFind( es_out_t *p_out, int i_group )
{
    es_out_sys_t *p_sys = p_out->p_sys;

    for( int i = 0; i < p_sys->i_pgrm; i++ )
    {
        if( p_sys->pgrm[i]->i_id == i_group )
            return p_sys->pgrm[i];
    }
    return EsOutProgramAdd( p_out, i_group );
}

/* EsOutProgramMeta:
 */
static char *EsOutProgramGetMetaName( es_out_pgrm_t *p_pgrm )
{
    char *psz = NULL;
    if( p_pgrm->p_meta && vlc_meta_Get( p_pgrm->p_meta, vlc_meta_Title ) )
    {
        if( asprintf( &psz, _("%s [%s %d]"), vlc_meta_Get( p_pgrm->p_meta, vlc_meta_Title ),
                      _("Program"), p_pgrm->i_id ) == -1 )
            return NULL;
    }
    else
    {
        if( asprintf( &psz, "%s %d", _("Program"), p_pgrm->i_id ) == -1 )
            return NULL;
    }
    return psz;
}

static char *EsOutProgramGetProgramName( es_out_pgrm_t *p_pgrm )
{
    char *psz = NULL;
    if( p_pgrm->p_meta && vlc_meta_Get( p_pgrm->p_meta, vlc_meta_Title ) )
    {
        return strdup( vlc_meta_Get( p_pgrm->p_meta, vlc_meta_Title ) );
    }
    else
    {
        if( asprintf( &psz, "%s %d", _("Program"), p_pgrm->i_id ) == -1 )
            return NULL;
    }
    return psz;
}

static char *EsInfoCategoryName( es_out_id_t* es )
{
    char *psz_category;

    if( asprintf( &psz_category, _("Stream %d"), es->i_meta_id ) == -1 )
        return NULL;

    return psz_category;
}

static void EsOutProgramMeta( es_out_t *out, int i_group, const vlc_meta_t *p_meta )
{
    es_out_sys_t      *p_sys = out->p_sys;
    es_out_pgrm_t     *p_pgrm;
    input_thread_t    *p_input = p_sys->p_input;
    const char        *psz_title = NULL;
    const char        *psz_provider = NULL;
    int i;

    msg_Dbg( p_input, "EsOutProgramMeta: number=%d", i_group );

    /* Check against empty meta data (empty for what we handle) */
    if( !vlc_meta_Get( p_meta, vlc_meta_Title) &&
        !vlc_meta_Get( p_meta, vlc_meta_ESNowPlaying) &&
        !vlc_meta_Get( p_meta, vlc_meta_Publisher) )
    {
        return;
    }

    if( i_group < 0 )
    {
        EsOutGlobalMeta( out, p_meta );
        return;
    }

    /* Find program */
    if( !EsOutIsProgramVisible( out, i_group ) )
        return;
    p_pgrm = EsOutProgramFind( out, i_group );
    if( !p_pgrm )
        return;

    if( p_pgrm->p_meta )
    {
        const char *psz_current_title = vlc_meta_Get( p_pgrm->p_meta, vlc_meta_Title );
        const char *psz_new_title = vlc_meta_Get( p_meta, vlc_meta_Title );
        if( (psz_current_title != NULL && psz_new_title != NULL)
            ? strcmp(psz_new_title, psz_current_title)
            : (psz_current_title != psz_new_title) )
        {
            /* Remove old entries */
            char *psz_oldinfokey = EsOutProgramGetMetaName( p_pgrm );
            input_Control( p_input, INPUT_DEL_INFO, psz_oldinfokey, NULL );
            /* TODO update epg name ?
             * TODO update scrambled info name ? */
            free( psz_oldinfokey );
        }
        vlc_meta_Delete( p_pgrm->p_meta );
    }
    p_pgrm->p_meta = vlc_meta_New();
    if( p_pgrm->p_meta )
        vlc_meta_Merge( p_pgrm->p_meta, p_meta );

    if( p_sys->p_pgrm == p_pgrm )
    {
        EsOutMeta( out, NULL, p_meta );
    }
    /* */
    psz_title = vlc_meta_Get( p_meta, vlc_meta_Title);
    psz_provider = vlc_meta_Get( p_meta, vlc_meta_Publisher);

    /* Update the description text of the program */
    if( psz_title && *psz_title )
    {
        char *psz_text;
        if( psz_provider && *psz_provider )
        {
            if( asprintf( &psz_text, "%s [%s]", psz_title, psz_provider ) < 0 )
                psz_text = NULL;
        }
        else
        {
            psz_text = strdup( psz_title );
        }

        /* ugly but it works */
        if( psz_text )
        {
            input_SendEventProgramDel( p_input, i_group );
            input_SendEventProgramAdd( p_input, i_group, psz_text );
            if( p_sys->p_pgrm == p_pgrm )
                input_SendEventProgramSelect( p_input, i_group );
            free( psz_text );
        }
    }

    /* */
    char **ppsz_all_keys = vlc_meta_CopyExtraNames(p_meta );

    info_category_t *p_cat = NULL;
    if( psz_provider || ( ppsz_all_keys[0] && *ppsz_all_keys[0] ) )
    {
        char *psz_cat = EsOutProgramGetMetaName( p_pgrm );
        if( psz_cat )
            p_cat = info_category_New( psz_cat );
        free( psz_cat );
    }

    for( i = 0; ppsz_all_keys[i]; i++ )
    {
        if( p_cat )
            info_category_AddInfo( p_cat, vlc_gettext(ppsz_all_keys[i]), "%s",
                                   vlc_meta_GetExtra( p_meta, ppsz_all_keys[i] ) );
        free( ppsz_all_keys[i] );
    }
    free( ppsz_all_keys );

    if( psz_provider )
    {
        if( p_sys->p_pgrm == p_pgrm )
        {
            input_item_SetPublisher( input_priv(p_input)->p_item, psz_provider );
            input_SendEventMeta( p_input );
        }
        if( p_cat )
            info_category_AddInfo( p_cat, vlc_meta_TypeToLocalizedString(vlc_meta_Publisher),
                                   "%s",psz_provider );
    }
    if( p_cat )
        input_Control( p_input, INPUT_MERGE_INFOS, p_cat );
}

static void EsOutProgramEpgEvent( es_out_t *out, int i_group, const vlc_epg_event_t *p_event )
{
    es_out_sys_t      *p_sys = out->p_sys;
    input_thread_t    *p_input = p_sys->p_input;
    input_item_t      *p_item = input_priv(p_input)->p_item;
    es_out_pgrm_t     *p_pgrm;

    /* Find program */
    if( !EsOutIsProgramVisible( out, i_group ) )
        return;
    p_pgrm = EsOutProgramFind( out, i_group );
    if( !p_pgrm )
        return;

    input_item_SetEpgEvent( p_item, p_event );
}

static void EsOutProgramEpg( es_out_t *out, int i_group, const vlc_epg_t *p_epg )
{
    es_out_sys_t      *p_sys = out->p_sys;
    input_thread_t    *p_input = p_sys->p_input;
    input_item_t      *p_item = input_priv(p_input)->p_item;
    es_out_pgrm_t     *p_pgrm;
    char *psz_cat;

    /* Find program */
    if( !EsOutIsProgramVisible( out, i_group ) )
        return;
    p_pgrm = EsOutProgramFind( out, i_group );
    if( !p_pgrm )
        return;

    /* Update info */
    psz_cat = EsOutProgramGetMetaName( p_pgrm );
    msg_Dbg( p_input, "EsOutProgramEpg: number=%d name=%s", i_group, psz_cat );

    /* Merge EPG */
    vlc_epg_t epg;

    epg = *p_epg;
    epg.psz_name = EsOutProgramGetProgramName( p_pgrm );

    input_item_SetEpg( p_item, &epg, p_sys->p_pgrm && (p_epg->i_source_id == p_sys->p_pgrm->i_id) );
    input_SendEventMetaEpg( p_sys->p_input );

    free( epg.psz_name );

    /* Update now playing */
    if( p_epg->b_present && p_pgrm->p_meta &&
       ( p_epg->p_current || p_epg->i_event == 0 ) )
    {
        vlc_meta_SetNowPlaying( p_pgrm->p_meta, NULL );
    }

    vlc_mutex_lock( &p_item->lock );
    for( int i = 0; i < p_item->i_epg; i++ )
    {
        const vlc_epg_t *p_tmp = p_item->pp_epg[i];

        if( p_tmp->b_present && p_tmp->i_source_id == p_pgrm->i_id )
        {
            const char *psz_name = ( p_tmp->p_current ) ? p_tmp->p_current->psz_name : NULL;
            if( !p_pgrm->p_meta )
                p_pgrm->p_meta = vlc_meta_New();
            if( p_pgrm->p_meta )
                vlc_meta_Set( p_pgrm->p_meta, vlc_meta_ESNowPlaying, psz_name );
            break;
        }
    }
    vlc_mutex_unlock( &p_item->lock );

    /* Update selected program input info */
    if( p_pgrm == p_sys->p_pgrm )
    {
        const char *psz_nowplaying = p_pgrm->p_meta ?
                                     vlc_meta_Get( p_pgrm->p_meta, vlc_meta_ESNowPlaying ) : NULL;

        input_item_SetESNowPlaying( input_priv(p_input)->p_item, psz_nowplaying );
        input_SendEventMeta( p_input );

        if( psz_nowplaying )
        {
            input_Control( p_input, INPUT_ADD_INFO, psz_cat,
                vlc_meta_TypeToLocalizedString(vlc_meta_ESNowPlaying), "%s", psz_nowplaying );
        }
        else
        {
            input_Control( p_input, INPUT_DEL_INFO, psz_cat,
                vlc_meta_TypeToLocalizedString(vlc_meta_ESNowPlaying) );
        }
    }

    free( psz_cat );
}

static void EsOutEpgTime( es_out_t *out, int64_t time )
{
    es_out_sys_t      *p_sys = out->p_sys;
    input_thread_t    *p_input = p_sys->p_input;
    input_item_t      *p_item = input_priv(p_input)->p_item;

    input_item_SetEpgTime( p_item, time );
}

static void EsOutProgramUpdateScrambled( es_out_t *p_out, es_out_pgrm_t *p_pgrm )
{
    es_out_sys_t    *p_sys = p_out->p_sys;
    input_thread_t  *p_input = p_sys->p_input;
    bool b_scrambled = false;

    for( int i = 0; i < p_sys->i_es; i++ )
    {
        if( p_sys->es[i]->p_pgrm == p_pgrm && p_sys->es[i]->b_scrambled )
        {
            b_scrambled = true;
            break;
        }
    }
    if( !p_pgrm->b_scrambled == !b_scrambled )
        return;

    p_pgrm->b_scrambled = b_scrambled;
    char *psz_cat = EsOutProgramGetMetaName( p_pgrm );

    if( b_scrambled )
        input_Control( p_input, INPUT_ADD_INFO, psz_cat, _("Scrambled"), _("Yes") );
    else
        input_Control( p_input, INPUT_DEL_INFO, psz_cat, _("Scrambled") );
    free( psz_cat );

    input_SendEventProgramScrambled( p_input, p_pgrm->i_id, b_scrambled );
}

static void EsOutMeta( es_out_t *p_out, const vlc_meta_t *p_meta, const vlc_meta_t *p_program_meta )
{
    es_out_sys_t    *p_sys = p_out->p_sys;
    input_thread_t  *p_input = p_sys->p_input;
    input_item_t *p_item = input_GetItem( p_input );

    char *psz_combined = NULL;
    vlc_mutex_lock( &p_item->lock );
    if( p_meta )
    {
        const char *psz_new_title = vlc_meta_Get( p_meta, vlc_meta_Title );
        if( psz_new_title )
            psz_combined = input_item_CombineCuratedTitle( p_item, psz_new_title );
        vlc_meta_Merge( p_item->p_meta, p_meta );
        if( psz_combined )
            vlc_meta_Set( p_item->p_meta, vlc_meta_Title, psz_combined );
    }
    vlc_mutex_unlock( &p_item->lock );

    /* Check program meta to not override GROUP_META values */
    if( p_meta && (!p_program_meta || vlc_meta_Get( p_program_meta, vlc_meta_Title ) == NULL) &&
         vlc_meta_Get( p_meta, vlc_meta_Title ) != NULL &&
         psz_combined == NULL /* keep a curated item name */ )
        input_item_SetName( p_item, vlc_meta_Get( p_meta, vlc_meta_Title ) );
    free( psz_combined );

    const char *psz_arturl = NULL;
    char *psz_alloc = NULL;

    if( p_program_meta )
        psz_arturl = vlc_meta_Get( p_program_meta, vlc_meta_ArtworkURL );
    if( psz_arturl == NULL && p_meta )
        psz_arturl = vlc_meta_Get( p_meta, vlc_meta_ArtworkURL );

    if( psz_arturl == NULL ) /* restore/favor previously set item art URL */
        psz_arturl = psz_alloc = input_item_GetArtURL( p_item );

    if( psz_arturl != NULL )
        input_item_SetArtURL( p_item, psz_arturl );

    if( psz_arturl != NULL && !strncmp( psz_arturl, "attachment://", 13 ) )
    {   /* Clear art cover if streaming out.
         * FIXME: Why? Remove this when sout gets meta data support. */
        if( input_priv(p_input)->p_sout != NULL )
            input_item_SetArtURL( p_item, NULL );
        else
            input_ExtractAttachmentAndCacheArt( p_input, psz_arturl + 13 );
    }
    free( psz_alloc );

    input_item_SetPreparsed( p_item, true );

    input_SendEventMeta( p_input );
    /* TODO handle sout meta ? */
}

static void EsOutGlobalMeta( es_out_t *p_out, const vlc_meta_t *p_meta )
{
    es_out_sys_t    *p_sys = p_out->p_sys;
    EsOutMeta( p_out, p_meta,
               (p_sys->p_pgrm && p_sys->p_pgrm->p_meta) ? p_sys->p_pgrm->p_meta : NULL );
}

static es_out_id_t *EsOutAddSlave( es_out_t *out, const es_format_t *fmt, es_out_id_t *p_master )
{
    es_out_sys_t      *p_sys = out->p_sys;
    input_thread_t    *p_input = p_sys->p_input;

    if( fmt->i_group < 0 )
    {
        msg_Err( p_input, "invalid group number" );
        return NULL;
    }

    /* Gapless (PowerVLC): as soon as this input carries video, it may neither
     * park nor adopt an audio output stream (2 s of A/V desync otherwise).
     *
     * The same verdict decides how the audio output corrects drift, and an
     * audio output may already exist and be playing by the time a programme
     * declares its video (MPEG-TS). Tell it, rather than leaving it with the
     * answer it read when it was created. */
    if( fmt->i_cat == VIDEO_ES
     && var_GetBool( p_input, "gapless-eligible" ) )
    {
        var_SetBool( p_input, "gapless-eligible", false );

        audio_output_t *p_aout =
            input_resource_HoldAout( input_priv(p_input)->p_resource );
        if( p_aout != NULL )
        {
            aout_DecChangeAudioOnly( p_aout, false );
            vlc_object_release( p_aout );
        }
    }

    es_out_id_t   *es = malloc( sizeof( *es ) );
    es_out_pgrm_t *p_pgrm;
    int i;

    if( !es )
        return NULL;

    vlc_mutex_lock( &p_sys->lock );

    /* Search the program */
    p_pgrm = EsOutProgramFind( out, fmt->i_group );
    if( !p_pgrm )
    {
        vlc_mutex_unlock( &p_sys->lock );
        free( es );
        return NULL;
    }

    /* Increase ref count for program */
    p_pgrm->i_es++;

    /* Set up ES */
    es->p_pgrm = p_pgrm;
    es_format_Copy( &es->fmt, fmt );
    if( es->fmt.i_id < 0 )
        es->fmt.i_id = p_sys->i_id;
    if( !es->fmt.i_original_fourcc )
        es->fmt.i_original_fourcc = es->fmt.i_codec;

    es->i_id = es->fmt.i_id;
    es->i_meta_id = p_sys->i_id++; /* always incremented */
    es->b_scrambled = false;
    es->b_forced_selection = false;

    switch( es->fmt.i_cat )
    {
    case AUDIO_ES:
    {
        es->fmt.i_codec = vlc_fourcc_GetCodecAudio( es->fmt.i_codec,
                                                    es->fmt.audio.i_bitspersample );
        es->i_channel = p_sys->audio.i_count++;

        audio_replay_gain_t rg;
        memset( &rg, 0, sizeof(rg) );
        vlc_mutex_lock( &input_priv(p_input)->p_item->lock );
        vlc_audio_replay_gain_MergeFromMeta( &rg, input_priv(p_input)->p_item->p_meta );
        vlc_mutex_unlock( &input_priv(p_input)->p_item->lock );

        for( i = 0; i < AUDIO_REPLAY_GAIN_MAX; i++ )
        {
            if( !es->fmt.audio_replay_gain.pb_peak[i] )
            {
                es->fmt.audio_replay_gain.pb_peak[i] = rg.pb_peak[i];
                es->fmt.audio_replay_gain.pf_peak[i] = rg.pf_peak[i];
            }
            if( !es->fmt.audio_replay_gain.pb_gain[i] )
            {
                es->fmt.audio_replay_gain.pb_gain[i] = rg.pb_gain[i];
                es->fmt.audio_replay_gain.pf_gain[i] = rg.pf_gain[i];
            }
        }
        break;
    }

    case VIDEO_ES:
        es->fmt.i_codec = vlc_fourcc_GetCodec( es->fmt.i_cat, es->fmt.i_codec );
        es->i_channel = p_sys->video.i_count++;

        if( !es->fmt.video.i_visible_width || !es->fmt.video.i_visible_height )
        {
            es->fmt.video.i_visible_width = es->fmt.video.i_width;
            es->fmt.video.i_visible_height = es->fmt.video.i_height;
        }

        if( es->fmt.video.i_frame_rate && es->fmt.video.i_frame_rate_base )
            vlc_ureduce( &es->fmt.video.i_frame_rate,
                         &es->fmt.video.i_frame_rate_base,
                         es->fmt.video.i_frame_rate,
                         es->fmt.video.i_frame_rate_base, 0 );
        break;

    case SPU_ES:
        es->fmt.i_codec = vlc_fourcc_GetCodec( es->fmt.i_cat, es->fmt.i_codec );
        es->i_channel = p_sys->sub.i_count++;
        break;

    default:
        es->i_channel = 0;
        break;
    }
    es->psz_language = LanguageGetName( es->fmt.psz_language ); /* remember so we only need to do it once */
    es->psz_language_code = LanguageGetCode( es->fmt.psz_language );
    es->p_dec = NULL;
    es->p_dec_record = NULL;
    es->cc.type = 0;
    es->cc.i_bitmap = 0;
    es->p_master = p_master;
    es->i_pts_level = VLC_TICK_INVALID;

    TAB_APPEND( p_sys->i_es, p_sys->es, es );

    if( es->p_pgrm == p_sys->p_pgrm )
        EsOutESVarUpdate( out, es, false );

    EsOutUpdateInfo( out, es, &es->fmt, NULL );
    EsOutSelect( out, es, false );

    if( es->b_scrambled )
        EsOutProgramUpdateScrambled( out, es->p_pgrm );

    vlc_mutex_unlock( &p_sys->lock );

    return es;
}

/* EsOutAdd:
 *  Add an es_out
 */
static es_out_id_t *EsOutAdd( es_out_t *out, const es_format_t *fmt )
{
    return EsOutAddSlave( out, fmt, NULL );
}

static bool EsIsSelected( es_out_id_t *es )
{
    if( es->p_master )
    {
        bool b_decode = false;
        if( es->p_master->p_dec )
        {
            int i_channel = EsOutGetClosedCaptionsChannel( &es->fmt );
            input_DecoderGetCcState( es->p_master->p_dec, es->fmt.i_codec,
                                     i_channel, &b_decode );
        }
        return b_decode;
    }
    else
    {
        return es->p_dec != NULL;
    }
}
static void EsCreateDecoder( es_out_t *out, es_out_id_t *p_es )
{
    es_out_sys_t   *p_sys = out->p_sys;
    input_thread_t *p_input = p_sys->p_input;

    p_es->p_dec = input_DecoderNew( p_input, &p_es->fmt, p_es->p_pgrm->p_clock, input_priv(p_input)->p_sout );
    if( p_es->p_dec )
    {
        if( p_sys->b_buffering )
            input_DecoderStartWait( p_es->p_dec );

        if( !p_es->p_master && p_sys->p_sout_record )
        {
            p_es->p_dec_record = input_DecoderNew( p_input, &p_es->fmt, p_es->p_pgrm->p_clock, p_sys->p_sout_record );
            if( p_es->p_dec_record && p_sys->b_buffering )
                input_DecoderStartWait( p_es->p_dec_record );
        }
    }

    EsOutDecoderChangeDelay( out, p_es );
}
static void EsDestroyDecoder( es_out_t *out, es_out_id_t *p_es )
{
    VLC_UNUSED(out);

    if( !p_es->p_dec )
        return;

    input_DecoderDelete( p_es->p_dec );
    p_es->p_dec = NULL;

    if( p_es->p_dec_record )
    {
        input_DecoderDelete( p_es->p_dec_record );
        p_es->p_dec_record = NULL;
    }
}

static void EsSelect( es_out_t *out, es_out_id_t *es )
{
    es_out_sys_t   *p_sys = out->p_sys;
    input_thread_t *p_input = p_sys->p_input;

    if( EsIsSelected( es ) )
    {
        msg_Warn( p_input, "ES 0x%x is already selected", es->i_id );
        return;
    }

    if( es->p_master )
    {
        int i_channel;
        if( !es->p_master->p_dec )
            return;

        i_channel = EsOutGetClosedCaptionsChannel( &es->fmt );

        if( i_channel == -1 ||
            input_DecoderSetCcState( es->p_master->p_dec, es->fmt.i_codec,
                                     i_channel, true ) )
            return;
    }
    else
    {
        const bool b_sout = input_priv(p_input)->p_sout != NULL;
        if( es->fmt.i_cat == VIDEO_ES || es->fmt.i_cat == SPU_ES )
        {
            if( !var_GetBool( p_input, b_sout ? "sout-video" : "video" ) )
            {
                msg_Dbg( p_input, "video is disabled, not selecting ES 0x%x",
                         es->i_id );
                return;
            }
        }
        else if( es->fmt.i_cat == AUDIO_ES )
        {
            if( !var_GetBool( p_input, b_sout ? "sout-audio" : "audio" ) )
            {
                msg_Dbg( p_input, "audio is disabled, not selecting ES 0x%x",
                         es->i_id );
                return;
            }
        }
        if( es->fmt.i_cat == SPU_ES )
        {
            if( !var_GetBool( p_input, b_sout ? "sout-spu" : "spu" ) )
            {
                msg_Dbg( p_input, "spu is disabled, not selecting ES 0x%x",
                         es->i_id );
                return;
            }
        }

        EsCreateDecoder( out, es );

        if( es->p_dec == NULL || es->p_pgrm != p_sys->p_pgrm )
            return;
    }

    /* Mark it as selected */
    input_SendEventEsSelect( p_input, es->fmt.i_cat, es->i_id );
    input_SendEventTeletextSelect( p_input, EsFmtIsTeletext( &es->fmt ) ? es->i_id : -1 );
}

static void EsDeleteCCChannels( es_out_t *out, es_out_id_t *parent )
{
    es_out_sys_t   *p_sys = out->p_sys;
    input_thread_t *p_input = p_sys->p_input;

    if( parent->cc.type == 0 )
        return;

    const int i_spu_id = var_GetInteger( p_input, "spu-es");

    uint64_t i_bitmap = parent->cc.i_bitmap;
    for( int i = 0; i_bitmap > 0; i++, i_bitmap >>= 1 )
    {
        if( (i_bitmap & 1) == 0 || !parent->cc.pp_es[i] )
            continue;

        if( i_spu_id == parent->cc.pp_es[i]->i_id )
        {
            /* Force unselection of the CC */
            input_SendEventEsSelect( p_input, SPU_ES, -1 );
        }
        EsOutDel( out, parent->cc.pp_es[i] );
    }

    parent->cc.i_bitmap = 0;
    parent->cc.type = 0;
}

static void EsUnselect( es_out_t *out, es_out_id_t *es, bool b_update )
{
    es_out_sys_t   *p_sys = out->p_sys;
    input_thread_t *p_input = p_sys->p_input;

    if( !EsIsSelected( es ) )
    {
        msg_Warn( p_input, "ES 0x%x is already unselected", es->i_id );
        return;
    }

    if( p_sys->p_next_frame_es == es )
        EsOutStopNextFrame( out );

    if( es->p_master )
    {
        if( es->p_master->p_dec )
        {
            int i_channel = EsOutGetClosedCaptionsChannel( &es->fmt );
            if( i_channel != -1 )
                input_DecoderSetCcState( es->p_master->p_dec, es->fmt.i_codec,
                                         i_channel, false );
        }
    }
    else
    {
        EsDeleteCCChannels( out, es );
        EsDestroyDecoder( out, es );
    }

    es->b_forced_selection = false;

    if( !b_update )
        return;

    /* Mark it as unselected */
    input_SendEventEsSelect( p_input, es->fmt.i_cat, -1 );
    if( EsFmtIsTeletext( &es->fmt ) )
        input_SendEventTeletextSelect( p_input, -1 );
}

/**
 * Select an ES given the current mode
 * XXX: you need to take a the lock before (stream.stream_lock)
 *
 * \param out The es_out structure
 * \param es es_out_id structure
 * \param b_force ...
 * \return nothing
 */
static void EsOutSelect( es_out_t *out, es_out_id_t *es, bool b_force )
{
    es_out_sys_t      *p_sys = out->p_sys;
    es_out_es_props_t *p_esprops = GetPropsByCat( p_sys, es->fmt.i_cat );

    if( !p_sys->b_active ||
        ( !b_force && es->fmt.i_priority < ES_PRIORITY_SELECTABLE_MIN ) )
    {
        return;
    }

    bool b_auto_unselect = p_esprops && p_sys->i_mode == ES_OUT_MODE_AUTO &&
                           p_esprops->e_policy == ES_OUT_ES_POLICY_EXCLUSIVE &&
                           p_esprops->p_main_es && p_esprops->p_main_es != es;

    if( p_sys->i_mode == ES_OUT_MODE_ALL || b_force )
    {
        if( !EsIsSelected( es ) )
        {
            if( b_auto_unselect )
                EsUnselect( out, p_esprops->p_main_es, false );

            EsSelect( out, es );
        }
    }
    else if( p_sys->i_mode == ES_OUT_MODE_PARTIAL )
    {
        char *prgms = var_GetNonEmptyString( p_sys->p_input, "programs" );
        if( prgms != NULL )
        {
            char *buf;

            for ( const char *prgm = strtok_r( prgms, ",", &buf );
                  prgm != NULL;
                  prgm = strtok_r( NULL, ",", &buf ) )
            {
                if( atoi( prgm ) == es->p_pgrm->i_id || b_force )
                {
                    if( !EsIsSelected( es ) )
                        EsSelect( out, es );
                    break;
                }
            }
            free( prgms );
        }
    }
    else if( p_sys->i_mode == ES_OUT_MODE_AUTO )
    {
        const es_out_id_t *wanted_es = NULL;

        if( es->p_pgrm != p_sys->p_pgrm || !p_esprops )
            return;

        /* user designated by ID ES have higher prio than everything */
        if ( p_esprops->i_id >= 0 )
        {
            if( es->i_id == p_esprops->i_id )
                wanted_es = es;
        }
        /* then per pos */
        else if( p_esprops->i_channel >= 0 )
        {
            if( p_esprops->i_channel == es->i_channel )
                wanted_es = es;
        }
        else if( p_esprops->ppsz_language )
        {
            /* If not deactivated */
            const int i_stop_idx = LanguageArrayIndex( p_esprops->ppsz_language, "none" );
            {
                int current_es_idx = ( p_esprops->p_main_es == NULL ) ? -1 :
                        LanguageArrayIndex( p_esprops->ppsz_language,
                                            p_esprops->p_main_es->psz_language_code );
                int es_idx = LanguageArrayIndex( p_esprops->ppsz_language,
                                                 es->psz_language_code );
                if( es_idx >= 0 && (i_stop_idx < 0 || i_stop_idx > es_idx) )
                {
                    /* Only select the language if it's in the list */
                    if( p_esprops->p_main_es == NULL ||
                        current_es_idx < 0 || /* current es was not selected by lang prefs */
                        es_idx < current_es_idx || /* current es has lower lang prio */
                        (  es_idx == current_es_idx && /* lang is same, but es has higher prio */
                           p_esprops->p_main_es->fmt.i_priority < es->fmt.i_priority ) )
                    {
                        wanted_es = es;
                    }
                }
                /* We did not find a language matching our prefs */
                else if( i_stop_idx < 0 ) /* If not fallback disabled by 'none' */
                {
                    /* Select if asked by demuxer */
                    if( current_es_idx < 0 ) /* No es is currently selected by lang pref */
                    {
                        /* If demux has specified a track */
                        if( p_esprops->i_demux_id >= 0 && es->i_id == p_esprops->i_demux_id )
                        {
                            wanted_es = es;
                        }
                        /* Otherwise, fallback by priority (never stealing a
                         * forced selection, see #24815) */
                        else if( p_esprops->p_main_es == NULL ||
                                 ( !p_esprops->p_main_es->b_forced_selection &&
                                   es->fmt.i_priority > p_esprops->p_main_es->fmt.i_priority ) )
                        {
                            if( p_esprops->b_autoselect )
                                wanted_es = es;
                        }
                    }
                }
            }

        }
        /* If there is no user preference, select the default subtitle
         * or adapt by ES priority */
        else if( p_esprops->i_demux_id >= 0 && es->i_id == p_esprops->i_demux_id )
        {
            wanted_es = es;
        }
        else if( p_esprops->p_main_es == NULL ||
                 ( !p_esprops->p_main_es->b_forced_selection &&
                   es->fmt.i_priority > p_esprops->p_main_es->fmt.i_priority ) )
        {
            if( p_esprops->b_autoselect )
                wanted_es = es;
        }

        if( wanted_es == es && !EsIsSelected( es ) )
        {
            if( b_auto_unselect )
                EsUnselect( out, p_esprops->p_main_es, false );

            EsSelect( out, es );
        }
    }

    if( b_force )
        es->b_forced_selection = true;

    /* FIXME TODO handle priority here */
    if( p_esprops && p_sys->i_mode == ES_OUT_MODE_AUTO && EsIsSelected( es ) )
        p_esprops->p_main_es = es;
}

static void EsOutCreateCCChannels( es_out_t *out, vlc_fourcc_t codec, uint64_t i_bitmap,
                                   const char *psz_descfmt, es_out_id_t *parent )
{
    es_out_sys_t   *p_sys = out->p_sys;
    input_thread_t *p_input = p_sys->p_input;

    /* Only one type of captions is allowed ! */
    if( parent->cc.type && parent->cc.type != codec )
        return;

    uint64_t i_existingbitmap = parent->cc.i_bitmap;
    for( int i = 0; i_bitmap > 0; i++, i_bitmap >>= 1, i_existingbitmap >>= 1 )
    {
        es_format_t fmt;

        if( (i_bitmap & 1) == 0 || (i_existingbitmap & 1) )
            continue;

        msg_Dbg( p_input, "Adding CC track %d for es[%d]", 1+i, parent->i_id );

        /* Traduire ICI et pas chez l'appelant : EsOutSend passe par ce chemin À
         * CHAQUE BLOC, et sur Mac OS X 10.3 chaque résolution gettext refait un
         * getcwd() qui MARCHE LE DISQUE en readdir — mesuré au PC-sampling sur
         * l'iBook G3 : ~50 %% d'un cœur pendant une lecture DVD, pour une
         * chaîne qui ne sert qu'à la création (rare, jamais sur un DVD) d'un
         * canal de sous-titres CC. */
        psz_descfmt = vlc_gettext( psz_descfmt );

        es_format_Init( &fmt, SPU_ES, codec );
        fmt.subs.cc.i_channel = i;
        fmt.i_group = parent->fmt.i_group;
        if( asprintf( &fmt.psz_description, psz_descfmt, 1 + i ) == -1 )
            fmt.psz_description = NULL;

        es_out_id_t **pp_es = &parent->cc.pp_es[i];
        *pp_es = EsOutAddSlave( out, &fmt, parent );
        es_format_Clean( &fmt );

        /* */
        parent->cc.i_bitmap |= (1ULL << i);
        parent->cc.type = codec;

        /* Enable if user specified on command line */
        if (p_sys->sub.i_channel == i)
            EsOutSelect(out, *pp_es, true);
    }
}

/**
 * Send a block for the given es_out
 *
 * \param out the es_out to send from
 * \param es the es_out_id
 * \param p_block the data block to send
 */
static int EsOutSend( es_out_t *out, es_out_id_t *es, block_t *p_block )
{
    es_out_sys_t   *p_sys = out->p_sys;
    input_thread_t *p_input = p_sys->p_input;

    assert( p_block->p_next == NULL );

    if( libvlc_stats( p_input ) )
    {
        uint64_t i_total;

        vlc_mutex_lock( &input_priv(p_input)->counters.counters_lock );
        stats_Update( input_priv(p_input)->counters.p_demux_read,
                      p_block->i_buffer, &i_total );
        stats_Update( input_priv(p_input)->counters.p_demux_bitrate, i_total, NULL );

        /* Update number of corrupted data packats */
        if( p_block->i_flags & BLOCK_FLAG_CORRUPTED )
        {
            stats_Update( input_priv(p_input)->counters.p_demux_corrupted, 1, NULL );
        }
        /* Update number of discontinuities */
        if( p_block->i_flags & BLOCK_FLAG_DISCONTINUITY )
        {
            stats_Update( input_priv(p_input)->counters.p_demux_discontinuity, 1, NULL );
        }
        vlc_mutex_unlock( &input_priv(p_input)->counters.counters_lock );
    }

    vlc_mutex_lock( &p_sys->lock );

    /* Drop all ESes except the video one in case of next-frame */
    if( p_sys->p_next_frame_es != NULL && p_sys->p_next_frame_es != es )
    {
        block_Release( p_block );
        vlc_mutex_unlock( &p_sys->lock );
        return VLC_SUCCESS;
    }

    /* Mark preroll blocks */
    if( p_sys->i_preroll_end >= 0 )
    {
        int64_t i_date = p_block->i_pts;
        if( p_block->i_pts <= VLC_TICK_INVALID )
            i_date = p_block->i_dts;

        /* In some cases, the demuxer sends non dated packets.
           We use interpolation, previous, or pcr value to compare with
           preroll target timestamp */
        if( i_date == VLC_TICK_INVALID )
        {
            if( es->i_pts_level != VLC_TICK_INVALID )
                i_date = es->i_pts_level;
            else if( es->p_pgrm->i_last_pcr != VLC_TICK_INVALID )
                i_date = es->p_pgrm->i_last_pcr;
        }

        if( i_date != VLC_TICK_INVALID )
            es->i_pts_level = i_date + p_block->i_length;

        /* If i_date is still invalid (first/all non dated), expect to be in preroll */

        if( i_date == VLC_TICK_INVALID ||
            es->i_pts_level < p_sys->i_preroll_end )
            p_block->i_flags |= BLOCK_FLAG_PREROLL;
    }

    if( !es->p_dec )
    {
        block_Release( p_block );
        vlc_mutex_unlock( &p_sys->lock );
        return VLC_SUCCESS;
    }

    /* Check for sout mode */
    if( input_priv(p_input)->p_sout )
    {
        /* FIXME review this, proper lock may be missing */
        if( input_priv(p_input)->p_sout->i_out_pace_nocontrol > 0 &&
            input_priv(p_input)->b_out_pace_control )
        {
            msg_Dbg( p_input, "switching to sync mode" );
            input_priv(p_input)->b_out_pace_control = false;
        }
        else if( input_priv(p_input)->p_sout->i_out_pace_nocontrol <= 0 &&
                 !input_priv(p_input)->b_out_pace_control )
        {
            msg_Dbg( p_input, "switching to async mode" );
            input_priv(p_input)->b_out_pace_control = true;
        }
    }

    /* Decode */
    if( es->p_dec_record )
    {
        block_t *p_dup = block_Duplicate( p_block );
        if( p_dup )
            input_DecoderDecode( es->p_dec_record, p_dup,
                                 input_priv(p_input)->b_out_pace_control );
    }
    input_DecoderDecode( es->p_dec, p_block,
                         input_priv(p_input)->b_out_pace_control );

    es_format_t fmt_dsc;
    vlc_meta_t  *p_meta_dsc;
    if( input_DecoderHasFormatChanged( es->p_dec, &fmt_dsc, &p_meta_dsc ) )
    {
        EsOutUpdateInfo( out, es, &fmt_dsc, p_meta_dsc );

        es_format_Clean( &fmt_dsc );
        if( p_meta_dsc )
            vlc_meta_Delete( p_meta_dsc );
    }

    /* Check CC status */
    decoder_cc_desc_t desc;

    input_DecoderGetCcDesc( es->p_dec, &desc );
    if( var_InheritInteger( p_input, "captions" ) == 708 )
        EsOutCreateCCChannels( out, VLC_CODEC_CEA708, desc.i_708_channels,
                               N_("DTVCC Closed captions %u"), es );
    EsOutCreateCCChannels( out, VLC_CODEC_CEA608, desc.i_608_channels,
                           N_("Closed captions %u"), es );

    vlc_mutex_unlock( &p_sys->lock );

    return VLC_SUCCESS;
}

/*****************************************************************************
 * EsOutDel:
 *****************************************************************************/
static void EsOutDel( es_out_t *out, es_out_id_t *es )
{
    es_out_sys_t *p_sys = out->p_sys;
    bool b_reselect = false;
    int i;

    vlc_mutex_lock( &p_sys->lock );

    es_out_es_props_t *p_esprops = GetPropsByCat( p_sys, es->fmt.i_cat );

    /* We don't try to reselect */
    if( es->p_dec )
    {   /* FIXME: This might hold the ES output caller (i.e. the demux), and
         * the corresponding thread (typically the input thread), for a little
         * bit too long if the ES is deleted in the middle of a stream. */
        input_DecoderDrain( es->p_dec, false );
        while( !input_Stopped(p_sys->p_input) && !p_sys->b_buffering )
        {
            if( input_DecoderIsEmpty( es->p_dec ) &&
                ( !es->p_dec_record || input_DecoderIsEmpty( es->p_dec_record ) ))
                break;
            /* FIXME there should be a way to have auto deleted es, but there will be
             * a problem when another codec of the same type is created (mainly video) */
            msleep( 20*1000 );
        }
        EsUnselect( out, es, es->p_pgrm == p_sys->p_pgrm );
    }

    if( es->p_pgrm == p_sys->p_pgrm )
        EsOutESVarUpdate( out, es, true );

    EsDeleteInfo( out, es );

    TAB_REMOVE( p_sys->i_es, p_sys->es, es );

    /* Update program */
    es->p_pgrm->i_es--;
    if( es->p_pgrm->i_es == 0 )
        msg_Dbg( p_sys->p_input, "Program doesn't contain anymore ES" );

    if( es->b_scrambled )
        EsOutProgramUpdateScrambled( out, es->p_pgrm );

    /* */
    if( p_esprops )
    {
        if( p_esprops->p_main_es == es )
        {
            b_reselect = true;
            p_esprops->p_main_es = NULL;
        }
        p_esprops->i_count--;
    }

    /* Re-select another track when needed */
    if( b_reselect )
    {
        for( i = 0; i < p_sys->i_es; i++ )
        {
            if( es->fmt.i_cat == p_sys->es[i]->fmt.i_cat )
            {
                if( EsIsSelected(p_sys->es[i]) )
                {
                    input_SendEventEsSelect( p_sys->p_input, es->fmt.i_cat, p_sys->es[i]->i_id );
                    if( p_esprops->p_main_es == NULL )
                        p_esprops->p_main_es = p_sys->es[i];
                }
                else
                    EsOutSelect( out, p_sys->es[i], false );
            }
        }
    }

    free( es->psz_language );
    free( es->psz_language_code );

    es_format_Clean( &es->fmt );

    vlc_mutex_unlock( &p_sys->lock );

    free( es );
}

/**
 * Control query handler
 *
 * \param out the es_out to control
 * \param i_query A es_out query as defined in include/ninput.h
 * \param args a variable list of arguments for the query
 * \return VLC_SUCCESS or an error code
 */
static int EsOutControlLocked( es_out_t *out, int i_query, va_list args )
{
    es_out_sys_t *p_sys = out->p_sys;

    switch( i_query )
    {
    case ES_OUT_SET_ES_STATE:
    {
        es_out_id_t *es = va_arg( args, es_out_id_t * );
        bool b = va_arg( args, int );
        if( b && !EsIsSelected( es ) )
        {
            EsSelect( out, es );
            return EsIsSelected( es ) ? VLC_SUCCESS : VLC_EGENERIC;
        }
        else if( !b && EsIsSelected( es ) )
        {
            EsUnselect( out, es, es->p_pgrm == p_sys->p_pgrm );
            return VLC_SUCCESS;
        }
        return VLC_SUCCESS;
    }

    case ES_OUT_GET_ES_STATE:
    {
        es_out_id_t *es = va_arg( args, es_out_id_t * );
        bool *pb = va_arg( args, bool * );

        *pb = EsIsSelected( es );
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_ES_CAT_POLICY:
    {
        enum es_format_category_e i_cat = va_arg( args, enum es_format_category_e );
        enum es_out_policy_e i_pol = va_arg( args, enum es_out_policy_e );
        es_out_es_props_t *p_esprops = GetPropsByCat( p_sys, i_cat );
        if( p_esprops == NULL )
            return VLC_EGENERIC;
        p_esprops->e_policy = i_pol;
        return VLC_SUCCESS;
    }

    case ES_OUT_GET_GROUP_FORCED:
    {
        int *pi_group = va_arg( args, int * );
        *pi_group = p_sys->i_group_id;
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_MODE:
    {
        const int i_mode = va_arg( args, int );
        assert( i_mode == ES_OUT_MODE_NONE || i_mode == ES_OUT_MODE_ALL ||
                i_mode == ES_OUT_MODE_AUTO || i_mode == ES_OUT_MODE_PARTIAL ||
                i_mode == ES_OUT_MODE_END );

        if( i_mode != ES_OUT_MODE_NONE && !p_sys->b_active && p_sys->i_es > 0 )
        {
            /* XXX Terminate vout if there are tracks but no video one.
             * This one is not mandatory but is he earliest place where it
             * can be done */
            int i;
            for( i = 0; i < p_sys->i_es; i++ )
            {
                es_out_id_t *p_es = p_sys->es[i];
                if( p_es->fmt.i_cat == VIDEO_ES )
                    break;
            }
            if( i >= p_sys->i_es && !EsOutKeepDiscVout( p_sys ) )
                input_resource_TerminateVout( input_priv(p_sys->p_input)->p_resource );
        }
        p_sys->b_active = i_mode != ES_OUT_MODE_NONE;
        p_sys->i_mode = i_mode;

        /* Reapply policy mode */
        for( int i = 0; i < p_sys->i_es; i++ )
        {
            if( EsIsSelected( p_sys->es[i] ) )
                EsUnselect( out, p_sys->es[i],
                            p_sys->es[i]->p_pgrm == p_sys->p_pgrm );
        }
        for( int i = 0; i < p_sys->i_es; i++ )
            EsOutSelect( out, p_sys->es[i], false );
        if( i_mode == ES_OUT_MODE_END )
            EsOutTerminate( out );
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_ES:
    case ES_OUT_RESTART_ES:
    {
#define IGNORE_ES DATA_ES
        es_out_id_t *es = va_arg( args, es_out_id_t * );

        enum es_format_category_e i_cat;
        if( es == NULL )
            i_cat = UNKNOWN_ES;
        else if( es == es_cat + AUDIO_ES )
            i_cat = AUDIO_ES;
        else if( es == es_cat + VIDEO_ES )
            i_cat = VIDEO_ES;
        else if( es == es_cat + SPU_ES )
            i_cat = SPU_ES;
        else
            i_cat = IGNORE_ES;

        for( int i = 0; i < p_sys->i_es; i++ )
        {
            if( i_cat == IGNORE_ES )
            {
                if( es == p_sys->es[i] )
                {
                    if( i_query == ES_OUT_RESTART_ES && p_sys->es[i]->p_dec )
                    {
                        EsDestroyDecoder( out, p_sys->es[i] );
                        EsCreateDecoder( out, p_sys->es[i] );
                    }
                    else if( i_query == ES_OUT_SET_ES )
                    {
                        EsOutSelect( out, es, true );
                    }
                    break;
                }
            }
            else
            {
                if( i_cat == UNKNOWN_ES || p_sys->es[i]->fmt.i_cat == i_cat )
                {
                    if( EsIsSelected( p_sys->es[i] ) )
                    {
                        if( i_query == ES_OUT_RESTART_ES )
                        {
                            if( p_sys->es[i]->p_dec )
                            {
                                EsDestroyDecoder( out, p_sys->es[i] );
                                EsCreateDecoder( out, p_sys->es[i] );
                            }
                        }
                        else
                        {
                            EsUnselect( out, p_sys->es[i],
                                        p_sys->es[i]->p_pgrm == p_sys->p_pgrm );
                        }
                    }
                }
            }
        }
        return VLC_SUCCESS;
    }
    case ES_OUT_STOP_ALL_ES:
    {
        int *selected_es = vlc_alloc(p_sys->i_es + 1, sizeof(int));
        if (!selected_es)
            return VLC_ENOMEM;
        selected_es[0] = p_sys->i_es;
        for( int i = 0; i < p_sys->i_es; i++ )
        {
            if( EsIsSelected( p_sys->es[i] ) )
            {
                EsDestroyDecoder( out, p_sys->es[i] );
                selected_es[i + 1] = p_sys->es[i]->i_id;
            }
            else
                selected_es[i + 1] = -1;
        }
        *va_arg( args, void **) = selected_es;
        return VLC_SUCCESS;
    }
    case ES_OUT_START_ALL_ES:
    {
        int *selected_es = va_arg( args, void * );
        int count = selected_es[0];
        for( int i = 0; i < count; ++i )
        {
            int i_id = selected_es[i + 1];
            if( i_id != -1 )
            {
                es_out_id_t *p_es = EsOutGetFromID( out, i_id );
                EsCreateDecoder( out, p_es );
            }
        }
        free(selected_es);
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_ES_DEFAULT:
    {
        es_out_id_t *es = va_arg( args, es_out_id_t * );

        if( es == NULL )
        {
            /*p_sys->i_default_video_id = -1;*/
            /*p_sys->i_default_audio_id = -1;*/
            p_sys->sub.i_demux_id = -1;
        }
        else if( es == es_cat + AUDIO_ES )
        {
            /*p_sys->i_default_video_id = -1;*/
        }
        else if( es == es_cat + VIDEO_ES )
        {
            /*p_sys->i_default_audio_id = -1;*/
        }
        else if( es == es_cat + SPU_ES )
        {
            p_sys->sub.i_demux_id = -1;
        }
        else
        {
            /*if( es->fmt.i_cat == VIDEO_ES )
                p_sys->i_default_video_id = es->i_id;
            else
            if( es->fmt.i_cat == AUDIO_ES )
                p_sys->i_default_audio_id = es->i_id;
            else*/
            if( es->fmt.i_cat == SPU_ES )
                p_sys->sub.i_demux_id = es->i_id;
        }
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_PCR:
    case ES_OUT_SET_GROUP_PCR:
    {
        es_out_pgrm_t *p_pgrm = NULL;
        int            i_group = 0;
        int64_t        i_pcr;

        /* Search program */
        if( i_query == ES_OUT_SET_PCR )
        {
            p_pgrm = p_sys->p_pgrm;
            if( !p_pgrm )
                p_pgrm = EsOutProgramAdd( out, i_group );   /* Create it */
        }
        else
        {
            i_group = va_arg( args, int );
            p_pgrm = EsOutProgramFind( out, i_group );
        }
        if( !p_pgrm )
            return VLC_EGENERIC;

        i_pcr = va_arg( args, int64_t );
        if( i_pcr <= VLC_TICK_INVALID )
        {
            msg_Err( p_sys->p_input, "Invalid PCR value in ES_OUT_SET_(GROUP_)PCR !" );
            return VLC_EGENERIC;
        }

        const vlc_tick_t i_previous_pcr = p_pgrm->i_last_pcr;
        if( i_previous_pcr > VLC_TICK_INVALID &&
            llabs( i_pcr - i_previous_pcr ) > VLC_TICK_FROM_SEC(10) )
            msg_Warn( p_sys->p_input,
                      "large PCR step: previous=%"PRId64" incoming=%"PRId64
                      " delta=%"PRId64" ms",
                      i_previous_pcr, i_pcr,
                      MS_FROM_VLC_TICK(i_pcr - i_previous_pcr) );
        p_pgrm->i_last_pcr = i_pcr;

        /* TODO do not use mdate() but proper stream acquisition date */
        bool b_late;
        input_clock_Update( p_pgrm->p_clock, VLC_OBJECT(p_sys->p_input),
                            &b_late,
                            input_priv(p_sys->p_input)->b_can_pace_control || p_sys->b_buffering,
                            EsOutIsExtraBufferingAllowed( out ),
                            i_pcr, mdate() );

        if( b_late )
        {
            vlc_tick_t stream_start, system_start;
            vlc_tick_t stream_duration, system_duration;
            if( input_clock_GetState( p_pgrm->p_clock, &stream_start,
                                      &system_start, &stream_duration,
                                      &system_duration ) == VLC_SUCCESS )
                msg_Warn( p_sys->p_input,
                          "late PCR state: PCR=%"PRId64" previous=%"PRId64
                          " ref_stream=%"PRId64" ref_system=%"PRId64
                          " stream_duration=%"PRId64" system_duration=%"PRId64,
                          i_pcr, i_previous_pcr, stream_start, system_start,
                          stream_duration, system_duration );
        }

        /* A continuity filter has already rebased this PCR onto the current
         * stream timeline.  input_clock_Update() must still consume it, but
         * treating the resulting one-shot lateness as starvation would flush
         * decoders and visibly stall a seamless Blu-ray clip/menu junction. */
        if( p_sys->b_next_pcr_seamless )
        {
            msg_Dbg( p_sys->p_input,
                     "late-PCR recovery inhibited for rebased seamless PCR" );
            b_late = false;
            p_sys->b_next_pcr_seamless = false;
        }

        if( !p_sys->p_pgrm )
            return VLC_SUCCESS;

        if( p_sys->b_buffering )
        {
            /* Check buffering state on master clock update */
            EsOutDecodersStopBuffering( out, false );
        }
        else if( p_pgrm == p_sys->p_pgrm )
        {
            if( p_sys->p_next_frame_es != NULL )
                return VLC_SUCCESS;

            EsOutVideoCacheMaybeRefill( out );
            if( p_sys->b_buffering )
                /* A refill episode just opened: the late/jitter handling
                 * below is startup-time logic, skip it for this PCR. */
                return VLC_SUCCESS;

            if( b_late && EsOutVideoCacheHasCushion( out ) )
            {
                /* The demuxer is only "late" because the look-ahead cache
                 * throttled it; the display rides its cushion. Absorbing
                 * this here avoids the re-buffer storm (~1 stall / cache
                 * depth) seen on DVD with video-cache-mb on. */
                msg_Dbg( p_sys->p_input, "late PCR absorbed by look-ahead "
                         "cache cushion (no re-buffer)" );
                b_late = false;
            }

            if( b_late && ( !input_priv(p_sys->p_input)->p_sout ||
                            !input_priv(p_sys->p_input)->b_out_pace_control ) )
            {
                const vlc_tick_t i_pts_delay_base = p_sys->i_pts_delay - p_sys->i_pts_jitter;
                vlc_tick_t i_pts_delay = input_clock_GetJitter( p_pgrm->p_clock );

                /* Avoid dangerously high value */
                const vlc_tick_t i_jitter_max = INT64_C(1000) * var_InheritInteger( p_sys->p_input, "clock-jitter" );
                if( i_pts_delay > __MIN( i_pts_delay_base + i_jitter_max, INPUT_PTS_DELAY_MAX ) )
                {
                    msg_Err( p_sys->p_input,
                             "ES_OUT_SET_(GROUP_)PCR  is called too late (jitter of %d ms ignored)",
                             (int)(i_pts_delay - i_pts_delay_base) / 1000 );
                    i_pts_delay = p_sys->i_pts_delay;

                    /* reset clock */
                    for( int i = 0; i < p_sys->i_pgrm; i++ )
                      input_clock_Reset( p_sys->pgrm[i]->p_clock );
                }
                else
                {
                    msg_Err( p_sys->p_input,
                             "ES_OUT_SET_(GROUP_)PCR  is called too late (pts_delay increased to %d ms)",
                             (int)(i_pts_delay/1000) );

                    /* Force a rebufferization when we are too late */

                    /* It is not really good, as we throw away already buffered data
                     * TODO have a mean to correctly reenter bufferization */
                    es_out_Control( out, ES_OUT_RESET_PCR );
                }

                es_out_SetJitter( out, i_pts_delay_base, i_pts_delay - i_pts_delay_base, p_sys->i_cr_average );
            }
        }
        return VLC_SUCCESS;
    }

    case ES_OUT_RESET_PCR:
        p_sys->b_next_pcr_seamless = false;
        msg_Dbg( p_sys->p_input, "ES_OUT_RESET_PCR called" );
        EsOutChangePosition( out );
        return VLC_SUCCESS;

    case ES_OUT_SET_VIDEO_CACHE_SKIP:
        /* The fill wait is deliberately NOT user-skippable: playback
         * must never start before the look-ahead cache reached its
         * threshold (it used to be skippable from the Play/Pause key).
         * The control is kept (and refused) so any stale caller keeps
         * falling through to its normal handling; the internal
         * b_video_cache_skip flag remains as the stall-timeout safety
         * valve only (see VIDEO_CACHE_STALL_TIMEOUT). */
        return VLC_EGENERIC;

    case ES_OUT_RECHECK_VIDEO_CACHE:
        /* No caller left inside the tree: the decoder-side per-picture
         * recheck this served was removed (it deadlocked against
         * EsUnselect's decoder join, see DecoderPlayVideo). Kept for
         * ABI; harmless if something external still fires it, since it
         * runs under the es_out lock on the caller's thread. */
        if( p_sys->b_buffering && p_sys->p_pgrm )
            EsOutDecodersStopBuffering( out, false );
        return VLC_SUCCESS;

    case ES_OUT_SET_VIDEO_CACHE_INHIBIT:
    {
        bool b = va_arg( args, int );
        if( b != p_sys->b_video_cache_inhibit )
        {
            msg_Dbg( p_sys->p_input, "video cache %s by the demuxer",
                     b ? "inhibited" : "re-allowed" );
            p_sys->b_video_cache_inhibit = b;
            /* Turning the inhibition ON while a fill episode is holding
             * playback (e.g. a title->menu hop whose RESET_PCR opened an
             * episode just before the demuxer could tell us): re-evaluate
             * right away so the gate opens on the spot instead of at the
             * next PCR/decoded picture. */
            if( b && p_sys->b_buffering && p_sys->p_pgrm )
                EsOutDecodersStopBuffering( out, false );
        }
        return VLC_SUCCESS;
    }

    case ES_OUT_GET_VIDEO_CACHE_STATE:
    {
        size_t *pi_count = va_arg( args, size_t * );
        size_t *pi_target = va_arg( args, size_t * );
        size_t *pi_bytes = va_arg( args, size_t * );
        *pi_count = *pi_target = 0;
        if( pi_bytes != NULL )
            *pi_bytes = 0;
        if( p_sys->i_video_cache_bytes > 0 )
            for( int i = 0; i < p_sys->i_es; i++ )
            {
                es_out_id_t *p_es = p_sys->es[i];
                if( p_es->fmt.i_cat != VIDEO_ES || !p_es->p_dec )
                    continue;
                bool b_starved;
                input_DecoderGetCacheState( p_es->p_dec, pi_count,
                                            pi_target, pi_bytes,
                                            &b_starved );
                break;
            }
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_GROUP:
    {
        int i = va_arg( args, int );
        for( int j = 0; j < p_sys->i_pgrm; j++ )
        {
            es_out_pgrm_t *p_pgrm = p_sys->pgrm[j];
            if( p_pgrm->i_id == i )
            {
                EsOutProgramSelect( out, p_pgrm );
                return VLC_SUCCESS;
            }
        }
        return VLC_EGENERIC;
    }

    case ES_OUT_SET_ES_FMT:
    {
        /* This ain't pretty but is need by some demuxers (eg. Ogg )
         * to update the p_extra data */
        es_out_id_t *es = va_arg( args, es_out_id_t * );
        es_format_t *p_fmt = va_arg( args, es_format_t * );
        if( es == NULL )
            return VLC_EGENERIC;

        es_format_Clean( &es->fmt );
        es_format_Copy( &es->fmt, p_fmt );

        if( es->p_dec )
        {
            EsDestroyDecoder( out, es );
            EsCreateDecoder( out, es );
        }

        return VLC_SUCCESS;
    }

    case ES_OUT_SET_ES_SCRAMBLED_STATE:
    {
        es_out_id_t *es = va_arg( args, es_out_id_t * );
        bool b_scrambled = (bool)va_arg( args, int );

        if( !es->b_scrambled != !b_scrambled )
        {
            es->b_scrambled = b_scrambled;
            EsOutProgramUpdateScrambled( out, es->p_pgrm );
        }
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_NEXT_DISPLAY_TIME:
    {
        const int64_t i_date = va_arg( args, int64_t );

        if( i_date < 0 )
            return VLC_EGENERIC;

        p_sys->i_preroll_end = i_date;

        return VLC_SUCCESS;
    }
    case ES_OUT_SET_GROUP_META:
    {
        int i_group = va_arg( args, int );
        const vlc_meta_t *p_meta = va_arg( args, const vlc_meta_t * );

        EsOutProgramMeta( out, i_group, p_meta );
        return VLC_SUCCESS;
    }
    case ES_OUT_SET_GROUP_EPG:
    {
        int i_group = va_arg( args, int );
        const vlc_epg_t *p_epg = va_arg( args, const vlc_epg_t * );

        EsOutProgramEpg( out, i_group, p_epg );
        return VLC_SUCCESS;
    }
    case ES_OUT_SET_GROUP_EPG_EVENT:
    {
        int i_group = va_arg( args, int );
        const vlc_epg_event_t *p_evt = va_arg( args, const vlc_epg_event_t * );

        EsOutProgramEpgEvent( out, i_group, p_evt );
        return VLC_SUCCESS;
    }
    case ES_OUT_SET_EPG_TIME:
    {
        int64_t i64 = va_arg( args, int64_t );

        EsOutEpgTime( out, i64 );
        return VLC_SUCCESS;
    }

    case ES_OUT_DEL_GROUP:
    {
        int i_group = va_arg( args, int );

        return EsOutProgramDel( out, i_group );
    }

    case ES_OUT_SET_META:
    {
        const vlc_meta_t *p_meta = va_arg( args, const vlc_meta_t * );

        EsOutGlobalMeta( out, p_meta );
        return VLC_SUCCESS;
    }

    case ES_OUT_GET_WAKE_UP:
    {
        vlc_tick_t *pi_wakeup = va_arg( args, vlc_tick_t* );
        *pi_wakeup = EsOutGetWakeup( out );
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_ES_BY_ID:
    case ES_OUT_RESTART_ES_BY_ID:
    case ES_OUT_SET_ES_DEFAULT_BY_ID:
    {
        const int i_id = va_arg( args, int );
        es_out_id_t *p_es = EsOutGetFromID( out, i_id );
        int i_new_query = 0;

        switch( i_query )
        {
        case ES_OUT_SET_ES_BY_ID:         i_new_query = ES_OUT_SET_ES; break;
        case ES_OUT_RESTART_ES_BY_ID:     i_new_query = ES_OUT_RESTART_ES; break;
        case ES_OUT_SET_ES_DEFAULT_BY_ID: i_new_query = ES_OUT_SET_ES_DEFAULT; break;
        default:
          vlc_assert_unreachable();
        }
        /* TODO if the lock is made non recursive it should be changed */
        int i_ret = es_out_Control( out, i_new_query, p_es );

        /* Clean up vout after user action (in active mode only).
         * FIXME it does not work well with multiple video windows */
        if( p_sys->b_active && !EsOutKeepDiscVout( p_sys ) )
            input_resource_TerminateVout( input_priv(p_sys->p_input)->p_resource );
        return i_ret;
    }

    case ES_OUT_GET_ES_OBJECTS_BY_ID:
    {
        const int i_id = va_arg( args, int );
        es_out_id_t *p_es = EsOutGetFromID( out, i_id );
        if( !p_es )
            return VLC_EGENERIC;

        vlc_object_t    **pp_decoder = va_arg( args, vlc_object_t ** );
        vout_thread_t   **pp_vout    = va_arg( args, vout_thread_t ** );
        audio_output_t **pp_aout    = va_arg( args, audio_output_t ** );
        if( p_es->p_dec )
        {
            if( pp_decoder )
                *pp_decoder = vlc_object_hold( p_es->p_dec );
            input_DecoderGetObjects( p_es->p_dec, pp_vout, pp_aout );
        }
        else
        {
            if( pp_decoder )
                *pp_decoder = NULL;
            if( pp_vout )
                *pp_vout = NULL;
            if( pp_aout )
                *pp_aout = NULL;
        }
        return VLC_SUCCESS;
    }

    case ES_OUT_GET_BUFFERING:
    {
        bool *pb = va_arg( args, bool* );
        *pb = p_sys->b_buffering;
        if( p_sys->b_buffering )
            *pb = true;
        else if( p_sys->p_next_frame_es != NULL )
        {
            /* The input thread will continue to call demux() if this control
             * returns true. In case of next-frame, ask the input thread to
             * continue to demux() until the vout has a picture to display. */
            assert( p_sys->b_paused );
            *pb = p_sys->p_next_frame_es->p_dec != NULL
                && input_DecoderIsEmpty( p_sys->p_next_frame_es->p_dec );
        }
        else
            *pb = false;
        return VLC_SUCCESS;
    }

    case ES_OUT_GET_EMPTY:
    {
        bool *pb = va_arg( args, bool* );
        *pb = EsOutDecodersIsEmpty( out );
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_DELAY:
    {
        const int i_cat = va_arg( args, int );
        const vlc_tick_t i_delay = va_arg( args, vlc_tick_t );
        EsOutSetDelay( out, i_cat, i_delay );
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_RECORD_STATE:
    {
        bool b = va_arg( args, int );
        return EsOutSetRecord( out, b );
    }

    case ES_OUT_SET_PAUSE_STATE:
    {
        const bool b_source_paused = (bool)va_arg( args, int );
        const bool b_paused = (bool)va_arg( args, int );
        const vlc_tick_t i_date = va_arg( args, vlc_tick_t );

        assert( !b_source_paused == !b_paused );
        EsOutChangePause( out, b_paused, i_date );

        return VLC_SUCCESS;
    }

    case ES_OUT_SET_RATE:
    {
        const int i_src_rate = va_arg( args, int );
        const int i_rate = va_arg( args, int );

        assert( i_src_rate == i_rate );
        EsOutChangeRate( out, i_rate );

        return VLC_SUCCESS;
    }

    case ES_OUT_SET_TIME:
    {
        const vlc_tick_t i_date = va_arg( args, vlc_tick_t );

        assert( i_date == -1 );
        EsOutChangePosition( out );

        return VLC_SUCCESS;
    }

    case ES_OUT_SET_FRAME_NEXT:
        EsOutFrameNext( out );
        return VLC_SUCCESS;

    case ES_OUT_SET_TIMES:
    {
        double f_position = va_arg( args, double );
        vlc_tick_t i_time = va_arg( args, vlc_tick_t );
        vlc_tick_t i_length = va_arg( args, vlc_tick_t );

        input_SendEventLength( p_sys->p_input, i_length );

        /* Bounded recording (clip creation): the UI arms an absolute stop
         * time (µs, same base as the "time" variable) in the
         * "record-stop-time" input variable. The raw i_time received here
         * is demux-paced, so recording ends when the DEMUXER crosses the
         * bound -- stopping from the interface on the playback time would
         * overshoot by the whole buffering lead. The var write goes through
         * the regular "record" callback and control queue, which both
         * updates the recording state and notifies the interfaces. */
        if( input_priv(p_sys->p_input)->b_recording )
        {
            vlc_tick_t i_record_stop = var_GetInteger( p_sys->p_input,
                                                       "record-stop-time" );
            if( i_record_stop != p_sys->i_record_stop_armed_for )
            {
                p_sys->i_record_stop_armed_for = i_record_stop;
                p_sys->b_record_stop_armed = false;
            }
            if( i_record_stop > 0 )
            {
                /* ⚠ The bound is meaningless until the demuxer has
                 * reached the clip: arming a clip whose start lies
                 * BEHIND the current position (the end knob was just
                 * previewed, or the end-bound pause is holding there)
                 * seeks backwards, and the first times reported after
                 * that still carry the position the demuxer was at --
                 * already past the bound, so the recording used to stop
                 * on the spot, leaving a header-only file or none at
                 * all. Wait for a time below the bound before letting it
                 * fire. */
                if( !p_sys->b_record_stop_armed )
                {
                    if( i_time < i_record_stop )
                        p_sys->b_record_stop_armed = true;
                }
                else if( i_time >= i_record_stop )
                    var_SetBool( p_sys->p_input, "record", false );
            }
        }
        else if( p_sys->b_record_stop_armed
              || p_sys->i_record_stop_armed_for != 0 )
        {
            p_sys->b_record_stop_armed = false;
            p_sys->i_record_stop_armed_for = 0;
        }

        if( !p_sys->b_buffering || p_sys->p_next_frame_es != NULL )
        {
            /* Also report times in next-frame mode without taking into
             * account the buffering. */

            vlc_tick_t i_delay;

            /* Fix for buffering delay */
            if( p_sys->p_next_frame_es == NULL
             && (!input_priv(p_sys->p_input)->p_sout ||
                 !input_priv(p_sys->p_input)->b_out_pace_control ) )
                i_delay = EsOutGetBuffering( out );
            else
                i_delay = 0;

            /* `i_delay` est SIGNÉ (cf. EsOutGetBuffering) : négatif, il fait
             * AVANCER le temps rapporté au-delà de celui du démultiplexeur,
             * ce qui est correct quand celui-ci a fini de lire et que la
             * lecture se poursuit sur ce qui est en file. D'où le bornage
             * haut, qui n'était pas nécessaire tant que le délai ne pouvait
             * que retarder. */
            i_time -= i_delay;
            if( i_time < 0 )
                i_time = 0;
            if( i_length > 0 && i_time > i_length )
                i_time = i_length;

            if( i_length > 0 )
                f_position -= (double)i_delay / i_length;
            if( f_position < 0 )
                f_position = 0;
            if( f_position > 1.0 )
                f_position = 1.0;

            input_SendEventPosition( p_sys->p_input, f_position, i_time );
        }
        return VLC_SUCCESS;
    }
    case ES_OUT_SET_JITTER:
    {
        vlc_tick_t i_pts_delay  = va_arg( args, vlc_tick_t );
        vlc_tick_t i_pts_jitter = va_arg( args, vlc_tick_t );
        int     i_cr_average = va_arg( args, int );

        bool b_change_clock =
            i_pts_delay + i_pts_jitter != p_sys->i_pts_delay ||
            i_cr_average != p_sys->i_cr_average;

        assert( i_pts_jitter >= 0 );
        p_sys->i_pts_delay  = i_pts_delay + i_pts_jitter;
        p_sys->i_pts_jitter = i_pts_jitter;
        p_sys->i_cr_average = i_cr_average;

        for( int i = 0; i < p_sys->i_pgrm && b_change_clock; i++ )
            input_clock_SetJitter( p_sys->pgrm[i]->p_clock,
                                   i_pts_delay + i_pts_jitter, i_cr_average );
        return VLC_SUCCESS;
    }

    case ES_OUT_GET_PCR_SYSTEM:
    {
        if( p_sys->b_buffering )
            return VLC_EGENERIC;

        es_out_pgrm_t *p_pgrm = p_sys->p_pgrm;
        if( !p_pgrm )
            return VLC_EGENERIC;

        vlc_tick_t *pi_system = va_arg( args, vlc_tick_t *);
        vlc_tick_t *pi_delay  = va_arg( args, vlc_tick_t *);
        input_clock_GetSystemOrigin( p_pgrm->p_clock, pi_system, pi_delay );
        return VLC_SUCCESS;
    }

    case ES_OUT_GET_CURRENT_PCR:
    {
        if( p_sys->b_buffering )
            return VLC_EGENERIC;

        es_out_pgrm_t *p_pgrm = p_sys->p_pgrm;
        if( !p_pgrm )
            return VLC_EGENERIC;

        vlc_tick_t current = input_clock_GetCurrentStream( p_pgrm->p_clock,
                                                           mdate() );
        if( current == VLC_TICK_INVALID )
            return VLC_EGENERIC;
        *va_arg( args, vlc_tick_t * ) = current;
        return VLC_SUCCESS;
    }

    case ES_OUT_SET_NEXT_PCR_SEAMLESS:
        p_sys->b_next_pcr_seamless = true;
        return VLC_SUCCESS;

    case ES_OUT_MODIFY_PCR_SYSTEM:
    {
        if( p_sys->b_buffering )
            return VLC_EGENERIC;

        es_out_pgrm_t *p_pgrm = p_sys->p_pgrm;
        if( !p_pgrm )
            return VLC_EGENERIC;

        const bool    b_absolute = va_arg( args, int );
        const vlc_tick_t i_system   = va_arg( args, vlc_tick_t );
        input_clock_ChangeSystemOrigin( p_pgrm->p_clock, b_absolute, i_system );
        return VLC_SUCCESS;
    }
    case ES_OUT_SET_EOS:
    {
        /* Gapless (PowerVLC): the audio output stream may only be parked
         * if this input carries no video at all. */
        bool b_gapless = var_GetBool( p_sys->p_input, "gapless-eligible" );
        for (int i = 0; i < p_sys->i_es && b_gapless; i++) {
            es_out_id_t *id = p_sys->es[i];
            if (id->p_dec != NULL && id->fmt.i_cat == VIDEO_ES)
            {
                b_gapless = false;
                break;
            }
        }
        for (int i = 0; i < p_sys->i_es; i++) {
            es_out_id_t *id = p_sys->es[i];
            if (id->p_dec != NULL)
                input_DecoderDrain(id->p_dec, b_gapless);
        }
        return VLC_SUCCESS;
    }

    case ES_OUT_POST_SUBNODE:
    {
        input_item_node_t *node = va_arg(args, input_item_node_t *);
        input_item_node_PostAndDelete(node);
        return VLC_SUCCESS;
    }

    default:
        msg_Err( p_sys->p_input, "unknown query 0x%x in %s", i_query,
                 __func__  );
        return VLC_EGENERIC;
    }
}
static int EsOutControl( es_out_t *out, int i_query, va_list args )
{
    es_out_sys_t *p_sys = out->p_sys;
    int i_ret;

    vlc_mutex_lock( &p_sys->lock );
    i_ret = EsOutControlLocked( out, i_query, args );
    vlc_mutex_unlock( &p_sys->lock );

    return i_ret;
}

/****************************************************************************
 * LanguageGetName: try to expend iso639 into plain name
 ****************************************************************************/
static char *LanguageGetName( const char *psz_code )
{
    const iso639_lang_t *pl;

    if( psz_code == NULL || !strcmp( psz_code, "und" ) )
    {
        return strdup( "" );
    }

    if( strlen( psz_code ) == 2 )
    {
        pl = GetLang_1( psz_code );
    }
    else if( strlen( psz_code ) == 3 )
    {
        pl = GetLang_2B( psz_code );
        if( !strcmp( pl->psz_iso639_1, "??" ) )
        {
            pl = GetLang_2T( psz_code );
        }
    }
    else
    {
        char *lang = LanguageGetCode( psz_code );
        pl = GetLang_1( lang );
        free( lang );
    }

    if( !strcmp( pl->psz_iso639_1, "??" ) )
    {
       return strdup( psz_code );
    }
    else
    {
        return strdup( vlc_gettext(pl->psz_eng_name) );
    }
}

/* Get a 2 char code */
static char *LanguageGetCode( const char *psz_lang )
{
    const iso639_lang_t *pl;

    if( psz_lang == NULL || *psz_lang == '\0' )
        return strdup("??");

    for( pl = p_languages; pl->psz_eng_name != NULL; pl++ )
    {
        if( !strcasecmp( pl->psz_eng_name, psz_lang ) ||
            !strcasecmp( pl->psz_iso639_1, psz_lang ) ||
            !strcasecmp( pl->psz_iso639_2T, psz_lang ) ||
            !strcasecmp( pl->psz_iso639_2B, psz_lang ) )
            return strdup( pl->psz_iso639_1 );
    }

    return strdup("??");
}

static char **LanguageSplit( const char *psz_langs )
{
    char *psz_dup;
    char *psz_parser;
    char **ppsz = NULL;
    int i_psz = 0;

    if( psz_langs == NULL ) return NULL;

    psz_parser = psz_dup = strdup(psz_langs);

    while( psz_parser && *psz_parser )
    {
        char *psz;
        char *psz_code;

        psz = strchr(psz_parser, ',' );
        if( psz ) *psz++ = '\0';

        if( !strcmp( psz_parser, "any" ) )
        {
            TAB_APPEND( i_psz, ppsz, strdup("any") );
        }
        else if( !strcmp( psz_parser, "none" ) )
        {
            TAB_APPEND( i_psz, ppsz, strdup("none") );
        }
        else
        {
            psz_code = LanguageGetCode( psz_parser );
            if( strcmp( psz_code, "??" ) )
            {
                TAB_APPEND( i_psz, ppsz, psz_code );
            }
            else
            {
                free( psz_code );
            }
        }

        psz_parser = psz;
    }

    if( i_psz )
    {
        TAB_APPEND( i_psz, ppsz, NULL );
    }

    free( psz_dup );
    return ppsz;
}

static int LanguageArrayIndex( char **ppsz_langs, const char *psz_lang )
{
    if( !ppsz_langs || !psz_lang )
        return -1;

    for( int i = 0; ppsz_langs[i]; i++ )
    {
        if( !strcasecmp( ppsz_langs[i], psz_lang ) ||
            ( !strcasecmp( ppsz_langs[i], "any" ) && strcasecmp( psz_lang, "none") ) )
            return i;
        if( !strcasecmp( ppsz_langs[i], "none" ) )
            break;
    }

    return -1;
}

static void info_category_AddCodecInfo( info_category_t* p_cat,
                                        const char *psz_info,
                                        vlc_fourcc_t i_fourcc,
                                        const char *psz_description )
{
    const char *ps_fcc = (const char*)&i_fourcc;
    if( psz_description && *psz_description )
        info_category_AddInfo( p_cat, psz_info, "%s (%.4s)",
                               psz_description, ps_fcc );
    else if ( i_fourcc != VLC_FOURCC(0,0,0,0) )
        info_category_AddInfo( p_cat, psz_info, "%.4s", ps_fcc );
}

/****************************************************************************
 * EsOutUpdateInfo:
 * - add meta info to the playlist item
 ****************************************************************************/
static void EsOutUpdateInfo( es_out_t *out, es_out_id_t *es, const es_format_t *fmt, const vlc_meta_t *p_meta )
{
    es_out_sys_t   *p_sys = out->p_sys;
    input_thread_t *p_input = p_sys->p_input;
    const es_format_t *p_fmt_es = &es->fmt;
    lldiv_t         div;

    if( es->fmt.i_cat == fmt->i_cat )
    {
        es_format_t update = *fmt;
        update.i_id = es->i_meta_id;
        update.i_codec = es->fmt.i_codec;
        update.i_original_fourcc = es->fmt.i_original_fourcc;

        /* Update infos that could have been lost by the decoder (no need to
         * dup them since input_item_UpdateTracksInfo() will do it). */
        if (update.psz_language == NULL)
            update.psz_language = es->fmt.psz_language;
        if (update.psz_description == NULL)
            update.psz_description = es->fmt.psz_description;
        if (update.i_cat == SPU_ES)
        {
            if (update.subs.psz_encoding == NULL)
                update.subs.psz_encoding = es->fmt.subs.psz_encoding;
            if (update.subs.p_style == NULL)
                update.subs.p_style = es->fmt.subs.p_style;
        }
        if (update.i_extra_languages == 0)
        {
            assert(update.p_extra_languages == NULL);
            update.i_extra_languages = es->fmt.i_extra_languages;
            update.p_extra_languages = es->fmt.p_extra_languages;
        }

        /* No need to update codec specific data */
        update.i_extra = 0;
        update.p_extra = NULL;

        input_item_UpdateTracksInfo(input_GetItem(p_input), &update);
    }

    /* Create category */
    char* psz_cat = EsInfoCategoryName( es );

    if( unlikely( !psz_cat ) )
        return;

    info_category_t* p_cat = info_category_New( psz_cat );

    free( psz_cat );

    if( unlikely( !p_cat ) )
        return;

    /* Add information */
    if( es->i_meta_id != es->i_id )
        info_category_AddInfo( p_cat, _("Original ID"),
                       "%d", es->i_id );

    const vlc_fourcc_t i_codec_fourcc = ( p_fmt_es->i_original_fourcc )?
                               p_fmt_es->i_original_fourcc : p_fmt_es->i_codec;
    const char *psz_codec_description =
        vlc_fourcc_GetDescription( p_fmt_es->i_cat, i_codec_fourcc );
    info_category_AddCodecInfo( p_cat, _("Codec"),
                                i_codec_fourcc, psz_codec_description );

    if( !EMPTY_STR(es->psz_language) )
        info_category_AddInfo( p_cat, _("Language"), "%s",
                               es->psz_language );
    if( !EMPTY_STR(fmt->psz_description) || !EMPTY_STR(p_fmt_es->psz_description) )
        info_category_AddInfo( p_cat, _("Description"), "%s",
                               EMPTY_STR(fmt->psz_description) ? p_fmt_es->psz_description
                                                               : fmt->psz_description );

    if( p_fmt_es->i_bitrate > 0 )
        info_category_AddInfo( p_cat, _("Bitrate"), _("%u kb/s"),
                               p_fmt_es->i_bitrate / 1000 );

    switch( fmt->i_cat )
    {
    case AUDIO_ES:
        info_category_AddInfo( p_cat, _("Type"), _("Audio") );

        if( p_fmt_es->audio.i_physical_channels )
            info_category_AddInfo( p_cat, _("Channels"), "%s",
                vlc_gettext( aout_FormatPrintChannels( &p_fmt_es->audio ) ) );

        if( p_fmt_es->audio.i_rate )
        {
            info_category_AddInfo( p_cat, _("Sample rate"), _("%u Hz"),
                                   p_fmt_es->audio.i_rate );
            /* FIXME that should be removed or improved ! (used by text/strings.c) */
            var_SetInteger( p_input, "sample-rate", p_fmt_es->audio.i_rate );
        }

        unsigned int i_orgbps = p_fmt_es->audio.i_bitspersample;
        if( i_orgbps == 0 )
            i_orgbps = aout_BitsPerSample( p_fmt_es->i_codec );
        if( i_orgbps != 0 )
            info_category_AddInfo( p_cat, _("Bits per sample"), "%u",
                                   i_orgbps );

        if( fmt->audio.i_format &&
            fmt->audio.i_format != p_fmt_es->i_codec )
        {
            psz_codec_description = vlc_fourcc_GetDescription( AUDIO_ES,
                                                               fmt->audio.i_format );
            info_category_AddCodecInfo( p_cat, _("Decoded format"),
                                        fmt->audio.i_format,
                                        psz_codec_description );
        }

        if( fmt->audio.i_physical_channels &&
            fmt->audio.i_physical_channels != p_fmt_es->audio.i_physical_channels )
            info_category_AddInfo( p_cat, _("Decoded channels"), "%s",
                vlc_gettext( aout_FormatPrintChannels( &fmt->audio ) ) );

        if( fmt->audio.i_rate &&
            fmt->audio.i_rate != p_fmt_es->audio.i_rate )
            info_category_AddInfo( p_cat, _("Decoded sample rate"), _("%u Hz"),
                                   fmt->audio.i_rate );

        unsigned i_outbps = fmt->audio.i_bitspersample;
        if( i_outbps == 0 )
            i_outbps = aout_BitsPerSample( fmt->i_codec );
        if( i_outbps != 0 && i_outbps != i_orgbps )
            info_category_AddInfo( p_cat, _("Decoded bits per sample"), "%u",
                                   i_outbps );

        if( fmt->i_bitrate > 0 )
        {
            info_category_AddInfo( p_cat, _("Decoded Bitrate"), _("%u kb/s"),
                                   fmt->i_bitrate / 1000 );
            /* FIXME that should be removed or improved ! (used by text/strings.c) */
            var_SetInteger( p_input, "bit-rate", fmt->i_bitrate );
        }

        for( int i = 0; i < AUDIO_REPLAY_GAIN_MAX; i++ )
        {
            const audio_replay_gain_t *p_rg = &fmt->audio_replay_gain;
            if( !p_rg->pb_gain[i] )
                continue;
            const char *psz_name;
            if( i == AUDIO_REPLAY_GAIN_TRACK )
                psz_name = _("Track replay gain");
            else
                psz_name = _("Album replay gain");
            info_category_AddInfo( p_cat, psz_name, _("%.2f dB"),
                                   p_rg->pf_gain[i] );
        }
        break;

    case VIDEO_ES:
        info_category_AddInfo( p_cat, _("Type"), _("Video") );

        if( fmt->video.i_visible_width > 0 &&
            fmt->video.i_visible_height > 0 )
            info_category_AddInfo( p_cat, _("Video resolution"), "%ux%u",
                                   fmt->video.i_visible_width,
                                   fmt->video.i_visible_height);

        if( fmt->video.i_width > 0 && fmt->video.i_height > 0 )
            info_category_AddInfo( p_cat, _("Buffer dimensions"), "%ux%u",
                                   fmt->video.i_width, fmt->video.i_height );

       if( fmt->video.i_frame_rate > 0 &&
           fmt->video.i_frame_rate_base > 0 )
       {
           div = lldiv( (float)fmt->video.i_frame_rate /
                               fmt->video.i_frame_rate_base * 1000000,
                               1000000 );
           if( div.rem > 0 )
               info_category_AddInfo( p_cat, _("Frame rate"), "%"PRId64".%06u",
                                      div.quot, (unsigned int )div.rem );
           else
               info_category_AddInfo( p_cat, _("Frame rate"), "%"PRId64,
                                      div.quot );
       }
       if( fmt->i_codec != p_fmt_es->i_codec )
       {
           psz_codec_description = vlc_fourcc_GetDescription( VIDEO_ES,
                                                              fmt->i_codec );
           info_category_AddCodecInfo( p_cat, _("Decoded format"),
                                       fmt->i_codec,
                                       psz_codec_description );
       }
       {
           static const char orient_names[][13] = {
               N_("Top left"), N_("Left top"),
               N_("Right bottom"), N_("Top right"),
               N_("Bottom left"), N_("Bottom right"),
               N_("Left bottom"), N_("Right top"),
           };
           info_category_AddInfo( p_cat, _("Orientation"), "%s",
                                  _(orient_names[fmt->video.orientation]) );
       }
       if( fmt->video.primaries != COLOR_PRIMARIES_UNDEF )
       {
           static const char primaries_names[][32] = {
               [COLOR_PRIMARIES_UNDEF] = N_("Undefined"),
               [COLOR_PRIMARIES_BT601_525] =
                   N_("ITU-R BT.601 (525 lines, 60 Hz)"),
               [COLOR_PRIMARIES_BT601_625] =
                   N_("ITU-R BT.601 (625 lines, 50 Hz)"),
               [COLOR_PRIMARIES_BT709] = "ITU-R BT.709",
               [COLOR_PRIMARIES_BT2020] = "ITU-R BT.2020",
               [COLOR_PRIMARIES_DCI_P3] = "DCI/P3 D65",
               [COLOR_PRIMARIES_BT470_M] = "ITU-R BT.470 M",
           };
           static_assert(ARRAY_SIZE(primaries_names) == COLOR_PRIMARIES_MAX+1,
                         "Color primiaries table mismatch");
           info_category_AddInfo( p_cat, _("Color primaries"), "%s",
                                  _(primaries_names[fmt->video.primaries]) );
       }
       if( fmt->video.transfer != TRANSFER_FUNC_UNDEF )
       {
           static const char func_names[][20] = {
               [TRANSFER_FUNC_UNDEF] = N_("Undefined"),
               [TRANSFER_FUNC_LINEAR] = N_("Linear"),
               [TRANSFER_FUNC_SRGB] = "sRGB",
               [TRANSFER_FUNC_BT470_BG] = "ITU-R BT.470 BG",
               [TRANSFER_FUNC_BT470_M] = "ITU-R BT.470 M",
               [TRANSFER_FUNC_BT709] = "ITU-R BT.709",
               [TRANSFER_FUNC_SMPTE_ST2084] = "SMPTE ST2084 (PQ)",
               [TRANSFER_FUNC_SMPTE_240] = "SMPTE 240M",
               [TRANSFER_FUNC_HLG] = N_("Hybrid Log-Gamma"),
           };
           static_assert(ARRAY_SIZE(func_names) == TRANSFER_FUNC_MAX+1,
                         "Transfer functions table mismatch");
           info_category_AddInfo( p_cat, _("Color transfer function"), "%s",
                                  _(func_names[fmt->video.transfer]) );
       }
       if( fmt->video.space != COLOR_SPACE_UNDEF )
       {
           static const char space_names[][16] = {
               [COLOR_SPACE_UNDEF] = N_("Undefined"),
               [COLOR_SPACE_BT601] = "ITU-R BT.601",
               [COLOR_SPACE_BT709] = "ITU-R BT.709",
               [COLOR_SPACE_BT2020] = "ITU-R BT.2020",
           };
           static_assert(ARRAY_SIZE(space_names) == COLOR_SPACE_MAX+1,
                         "Color space table mismatch");
           info_category_AddInfo( p_cat, _("Color space"), _("%s Range"),
                                  _(space_names[fmt->video.space]),
                       _(fmt->video.b_color_range_full ? "Full" : "Limited") );
       }
       if( fmt->video.chroma_location != CHROMA_LOCATION_UNDEF )
       {
           static const char c_loc_names[][16] = {
               [CHROMA_LOCATION_UNDEF] = N_("Undefined"),
               [CHROMA_LOCATION_LEFT] = N_("Left"),
               [CHROMA_LOCATION_CENTER] = N_("Center"),
               [CHROMA_LOCATION_TOP_LEFT] = N_("Top Left"),
               [CHROMA_LOCATION_TOP_CENTER] = N_("Top Center"),
               [CHROMA_LOCATION_BOTTOM_LEFT] =N_("Bottom Left"),
               [CHROMA_LOCATION_BOTTOM_CENTER] = N_("Bottom Center"),
           };
           static_assert(ARRAY_SIZE(c_loc_names) == CHROMA_LOCATION_MAX+1,
                         "Chroma location table mismatch");
           info_category_AddInfo( p_cat, _("Chroma location"), "%s",
                   _(c_loc_names[fmt->video.chroma_location]) );
       }
       if( fmt->video.projection_mode != PROJECTION_MODE_RECTANGULAR )
       {
           const char *psz_loc_name = NULL;
           switch (fmt->video.projection_mode)
           {
           case PROJECTION_MODE_RECTANGULAR:
               psz_loc_name = N_("Rectangular");
               break;
           case PROJECTION_MODE_EQUIRECTANGULAR:
               psz_loc_name = N_("Equirectangular");
               break;
           case PROJECTION_MODE_CUBEMAP_LAYOUT_STANDARD:
               psz_loc_name = N_("Cubemap");
               break;
           default:
               vlc_assert_unreachable();
               break;
           }
           info_category_AddInfo( p_cat, _("Projection"), "%s", _(psz_loc_name) );

           info_category_AddInfo( p_cat, vlc_pgettext("ViewPoint", "Yaw"),
                                  "%.2f", fmt->video.pose.yaw );
           info_category_AddInfo( p_cat, vlc_pgettext("ViewPoint", "Pitch"),
                                  "%.2f", fmt->video.pose.pitch );
           info_category_AddInfo( p_cat, vlc_pgettext("ViewPoint", "Roll"),
                                  "%.2f", fmt->video.pose.roll );
           info_category_AddInfo( p_cat,
                                  vlc_pgettext("ViewPoint", "Field of view"),
                                  "%.2f", fmt->video.pose.fov );
       }
       if ( fmt->video.mastering.max_luminance )
       {
           info_category_AddInfo( p_cat, _("Max. luminance"), "%.4f cd/m²",
               fmt->video.mastering.max_luminance / 10000.f );
       }
       if ( fmt->video.mastering.min_luminance )
       {
           info_category_AddInfo( p_cat, _("Min. luminance"), "%.4f cd/m²",
               fmt->video.mastering.min_luminance / 10000.f );
       }
       if ( fmt->video.mastering.primaries[4] &&
            fmt->video.mastering.primaries[5] )
       {
           float x = (float)fmt->video.mastering.primaries[4] / 50000.f;
           float y = (float)fmt->video.mastering.primaries[5] / 50000.f;
           info_category_AddInfo( p_cat, _("Primary R"), "x=%.4f y=%.4f", x, y );
       }
       if ( fmt->video.mastering.primaries[0] &&
            fmt->video.mastering.primaries[1] )
       {
           float x = (float)fmt->video.mastering.primaries[0] / 50000.f;
           float y = (float)fmt->video.mastering.primaries[1] / 50000.f;
           info_category_AddInfo( p_cat, _("Primary G"), "x=%.4f y=%.4f", x, y );
       }
       if ( fmt->video.mastering.primaries[2] &&
            fmt->video.mastering.primaries[3] )
       {
           float x = (float)fmt->video.mastering.primaries[2] / 50000.f;
           float y = (float)fmt->video.mastering.primaries[3] / 50000.f;
           info_category_AddInfo( p_cat, _("Primary B"), "x=%.4f y=%.4f", x, y );
       }
       if ( fmt->video.mastering.white_point[0] &&
            fmt->video.mastering.white_point[1] )
       {
           float x = (float)fmt->video.mastering.white_point[0] / 50000.f;
           float y = (float)fmt->video.mastering.white_point[1] / 50000.f;
           info_category_AddInfo( p_cat, _("White point"), "x=%.4f y=%.4f", x, y );
       }
       if ( fmt->video.lighting.MaxCLL )
       {
           info_category_AddInfo( p_cat, "MaxCLL", "%d cd/m²",
                                  fmt->video.lighting.MaxCLL );
       }
       if ( fmt->video.lighting.MaxFALL )
       {
           info_category_AddInfo( p_cat, "MaxFALL", "%d cd/m²",
                                  fmt->video.lighting.MaxFALL );
       }
       break;

    case SPU_ES:
        info_category_AddInfo( p_cat, _("Type"), _("Subtitle") );
        break;

    default:
        break;
    }

    /* Append generic meta */
    if( p_meta )
    {
        char **ppsz_all_keys = vlc_meta_CopyExtraNames( p_meta );
        for( int i = 0; ppsz_all_keys && ppsz_all_keys[i]; i++ )
        {
            char *psz_key = ppsz_all_keys[i];
            const char *psz_value = vlc_meta_GetExtra( p_meta, psz_key );

            if( psz_value )
                info_category_AddInfo( p_cat, vlc_gettext(psz_key), "%s",
                                       vlc_gettext(psz_value) );
            free( psz_key );
        }
        free( ppsz_all_keys );
    }
    /* */
    input_Control( p_input, INPUT_REPLACE_INFOS, p_cat );
}

static void EsDeleteInfo( es_out_t *out, es_out_id_t *es )
{
    char* psz_info_category;

    if( likely( psz_info_category = EsInfoCategoryName( es ) ) )
    {
        input_Control( out->p_sys->p_input, INPUT_DEL_INFO,
          psz_info_category, NULL );

        free( psz_info_category );
    }
}
