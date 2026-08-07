/*****************************************************************************
 * decoder.c: Functions for the management of decoders
 *****************************************************************************
 * Copyright (C) 1999-2004 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Christophe Massiot <massiot@via.ecp.fr>
 *          Gildas Bazin <gbazin@videolan.org>
 *          Laurent Aimar <fenrir@via.ecp.fr>
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
#include <assert.h>

#include <vlc_common.h>

#include <vlc_atomic.h>
#include <vlc_block.h>
#include <vlc_vout.h>
#include <vlc_aout.h>
#include <vlc_sout.h>
#include <vlc_codec.h>
#include <vlc_spu.h>
#include <vlc_meta.h>
#include <vlc_dialog.h>
#include <vlc_modules.h>

#include "audio_output/aout_internal.h"
#include "stream_output/stream_output.h"
#include "input_internal.h"
#include "clock.h"
#include "decoder.h"
#include "event.h"
#include "resource.h"

#include "../video_output/vout_control.h"

/*
 * Possibles values set in p_owner->reload atomic
 */
enum reload
{
    RELOAD_NO_REQUEST,
    RELOAD_DECODER,     /* Reload the decoder module */
    RELOAD_DECODER_AOUT /* Stop the aout and reload the decoder module */
};

struct decoder_owner_sys_t
{
    input_thread_t  *p_input;
    input_resource_t*p_resource;
    input_clock_t   *p_clock;
    int             i_last_rate;

    vout_thread_t   *p_spu_vout;
    int              i_spu_channel;
    int64_t          i_spu_order;

    sout_instance_t         *p_sout;
    sout_packetizer_input_t *p_sout_input;

    vlc_thread_t     thread;

    void (*pf_update_stat)( decoder_owner_sys_t *, unsigned decoded, unsigned lost );

    /* Some decoders require already packetized data (ie. not truncated) */
    decoder_t *p_packetizer;
    bool b_packetizer;

    /* Current format in use by the output */
    es_format_t    fmt;

    /* */
    bool           b_fmt_description;
    vlc_meta_t     *p_description;
    atomic_int     reload;

    /* fifo */
    block_fifo_t *p_fifo;

    /* Lock for communication with decoder thread */
    vlc_mutex_t lock;
    vlc_cond_t  wait_request;
    vlc_cond_t  wait_acknowledge;
    vlc_cond_t  wait_fifo; /* TODO: merge with wait_acknowledge */
    vlc_cond_t  wait_timed;

    /* -- These variables need locking on write(only) -- */
    audio_output_t *p_aout;

    vout_thread_t   *p_vout;

    /* -- Theses variables need locking on read *and* write -- */
    /* Preroll */
    int64_t i_preroll_end;
    /* Pause */
    vlc_tick_t pause_date;
    unsigned frames_countdown;
    bool paused;

    bool error;

    /* Waiting */
    bool b_waiting;
    bool b_first;
    bool b_has_data;

    /* Look-ahead decode cache (video-cache-* options, video ES only).
     * While b_waiting and the vout fifo holds fewer than the target
     * number of pictures, the decoder keeps decoding instead of parking
     * after its first picture (which is what makes es_out's fill gate
     * reachable at all -- see EsOutVideoCacheFillRatio). */
    size_t i_cache_bytes;        /* MB budget in bytes, 0 = feature off */
    unsigned i_cache_max_seconds;
    size_t i_cache_pic_bytes;    /* measured on the first queued picture */
    bool b_cache_hold;           /* this episode's vout hold was requested */
    /* Adaptive refill pacing (round 87b): controller state, decoder
     * thread only -- no locking. */
    vlc_tick_t i_cache_pace_yield; /* current base yield between pictures */
    vlc_tick_t i_cache_pace_mark;  /* date of last controller update, 0 = reset */
    size_t i_cache_pace_count;     /* cushion count at last update */

    /* Flushing */
    bool flushing;
    bool b_draining;
    atomic_bool drained;
    bool b_idle;

    /* Gapless (PowerVLC) */
    bool b_gapless_eos;     /* end of stream: drain without waiting */
    bool b_gapless_drained; /* async drain done, output queue still playing */

    /* Gapless (PowerVLC): encoder priming/padding trimming */
    uint64_t i_gl_count;    /* decoded samples seen so far */
    uint64_t i_gl_end;      /* index of the first padding sample */
    uint32_t i_gl_priming;  /* samples to drop at the start */
    bool     b_gl_active;   /* trimming enabled for this track */
    bool     b_gl_init;     /* parameters already read from the format */

    /* CC */
#define MAX_CC_DECODERS 64 /* The es_out only creates one type of es */
    struct
    {
        bool b_supported;
        decoder_cc_desc_t desc;
        decoder_t *pp_decoder[MAX_CC_DECODERS];
    } cc;

    /* Delay */
    vlc_tick_t i_ts_delay;
};

/* Pictures which are DECODER_BOGUS_VIDEO_DELAY or more in advance probably have
 * a bogus PTS and won't be displayed */
#define DECODER_BOGUS_VIDEO_DELAY                ((vlc_tick_t)(DEFAULT_PTS_DELAY * 30))

/* */
#define DECODER_SPU_VOUT_WAIT_DURATION ((int)(0.200*CLOCK_FREQ))
#define BLOCK_FLAG_CORE_PRIVATE_RELOADED (1 << BLOCK_FLAG_CORE_PRIVATE_SHIFT)

/**
 * Load a decoder module
 */
static int LoadDecoder( decoder_t *p_dec, bool b_packetizer,
                        const es_format_t *restrict p_fmt )
{
    p_dec->b_frame_drop_allowed = true;
    p_dec->i_extra_picture_buffers = 0;
    p_dec->i_dpb_size = 0;

    p_dec->pf_decode = NULL;
    p_dec->pf_get_cc = NULL;
    p_dec->pf_packetize = NULL;
    p_dec->pf_flush = NULL;

    es_format_Copy( &p_dec->fmt_in, p_fmt );
    es_format_Init( &p_dec->fmt_out, p_fmt->i_cat, 0 );

    /* Find a suitable decoder/packetizer module */
    if( !b_packetizer )
    {
        static const char caps[ES_CATEGORY_COUNT][16] = {
            [VIDEO_ES] = "video decoder",
            [AUDIO_ES] = "audio decoder",
            [SPU_ES] = "spu decoder",
        };
        p_dec->p_module = module_need( p_dec, caps[p_dec->fmt_in.i_cat],
                                       "$codec", false );
    }
    else
        p_dec->p_module = module_need( p_dec, "packetizer", "$packetizer", false );

    if( !p_dec->p_module )
    {
        es_format_Clean( &p_dec->fmt_in );
        return -1;
    }
    else
        return 0;
}

/**
 * Unload a decoder module
 */
static void UnloadDecoder( decoder_t *p_dec )
{
    if( p_dec->p_module )
    {
        module_unneed( p_dec, p_dec->p_module );
        p_dec->p_module = NULL;
    }

    if( p_dec->p_description )
    {
        vlc_meta_Delete( p_dec->p_description );
        p_dec->p_description = NULL;
    }

    es_format_Clean( &p_dec->fmt_in );
    es_format_Clean( &p_dec->fmt_out );
}

static int ReloadDecoder( decoder_t *p_dec, bool b_packetizer,
                          const es_format_t *restrict p_fmt, enum reload reload )
{
    /* Copy p_fmt since it can be destroyed by UnloadDecoder */
    es_format_t fmt_in;
    if( es_format_Copy( &fmt_in, p_fmt ) != VLC_SUCCESS )
    {
        p_dec->p_owner->error = true;
        return VLC_EGENERIC;
    }

    /* Restart the decoder module */
    UnloadDecoder( p_dec );
    p_dec->p_owner->error = false;

    if( reload == RELOAD_DECODER_AOUT )
    {
        decoder_owner_sys_t *p_owner = p_dec->p_owner;
        assert( p_owner->fmt.i_cat == AUDIO_ES );
        audio_output_t *p_aout = p_owner->p_aout;

        vlc_mutex_lock( &p_owner->lock );
        p_owner->p_aout = NULL;
        vlc_mutex_unlock( &p_owner->lock );
        if( p_aout )
        {
            aout_DecDelete( p_aout );
            input_resource_PutAout( p_owner->p_resource, p_aout );
        }
    }

    if( LoadDecoder( p_dec, b_packetizer, &fmt_in ) )
    {
        p_dec->p_owner->error = true;
        es_format_Clean( &fmt_in );
        return VLC_EGENERIC;
    }
    es_format_Clean( &fmt_in );
    return VLC_SUCCESS;
}

static void DecoderUpdateFormatLocked( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_assert_locked( &p_owner->lock );

    es_format_Clean( &p_owner->fmt );
    es_format_Copy( &p_owner->fmt, &p_dec->fmt_out );

    /* Move p_description */
    if( p_dec->p_description != NULL )
    {
        if( p_owner->p_description != NULL )
            vlc_meta_Delete( p_owner->p_description );
        p_owner->p_description = p_dec->p_description;
        p_dec->p_description = NULL;
    }

    p_owner->b_fmt_description = true;
}

/*****************************************************************************
 * Buffers allocation callbacks for the decoders
 *****************************************************************************/
static vout_thread_t *aout_request_vout( void *p_private,
                                         vout_thread_t *p_vout,
                                         const video_format_t *p_fmt, bool b_recyle )
{
    decoder_t *p_dec = p_private;
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    input_thread_t *p_input = p_owner->p_input;
    video_format_t fmt;

    if (p_fmt != NULL)
    {
        fmt = *p_fmt;
        p_fmt = &fmt;
        video_format_AdjustColorSpace( &fmt );
    }

    p_vout = input_resource_RequestVout( p_owner->p_resource, p_vout, p_fmt, 1,
                                         b_recyle );
    if( p_input != NULL )
        input_SendEventVout( p_input );

    return p_vout;
}

static bool aout_replaygain_changed( const audio_replay_gain_t *a,
                                     const audio_replay_gain_t *b )
{
    for( size_t i=0; i<AUDIO_REPLAY_GAIN_MAX; i++ )
    {
        if( a->pb_gain[i] != b->pb_gain[i] ||
            a->pb_peak[i] != b->pb_peak[i] ||
            a->pb_gain[i] != b->pb_gain[i] ||
            a->pb_peak[i] != b->pb_peak[i] )
            return true;
    }
    return false;
}

static int aout_update_format( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    if( p_owner->p_aout &&
       ( !AOUT_FMTS_IDENTICAL(&p_dec->fmt_out.audio, &p_owner->fmt.audio) ||
         p_dec->fmt_out.i_codec != p_dec->fmt_out.audio.i_format ||
         p_dec->fmt_out.i_profile != p_owner->fmt.i_profile ) )
    {
        audio_output_t *p_aout = p_owner->p_aout;

        /* Parameters changed, restart the aout */
        vlc_mutex_lock( &p_owner->lock );
        p_owner->p_aout = NULL;
        vlc_mutex_unlock( &p_owner->lock );
        aout_DecDelete( p_aout );

        input_resource_PutAout( p_owner->p_resource, p_aout );
    }

    /* Check if only replay gain has changed */
    if( aout_replaygain_changed( &p_dec->fmt_in.audio_replay_gain,
                                 &p_owner->fmt.audio_replay_gain ) )
    {
        p_dec->fmt_out.audio_replay_gain = p_dec->fmt_in.audio_replay_gain;
        if( p_owner->p_aout )
        {
            p_owner->fmt.audio_replay_gain = p_dec->fmt_in.audio_replay_gain;
            var_TriggerCallback( p_owner->p_aout, "audio-replay-gain-mode" );
        }
    }

    if( p_owner->p_aout == NULL )
    {
        p_dec->fmt_out.audio.i_format = p_dec->fmt_out.i_codec;

        audio_sample_format_t format = p_dec->fmt_out.audio;
        aout_FormatPrepare( &format );

        const int i_force_dolby = var_InheritInteger( p_dec, "force-dolby-surround" );
        if( i_force_dolby &&
            format.i_physical_channels == (AOUT_CHAN_LEFT|AOUT_CHAN_RIGHT) )
        {
            if( i_force_dolby == 1 )
                format.i_chan_mode |= AOUT_CHANMODE_DOLBYSTEREO;
            else /* i_force_dolby == 2 */
                format.i_chan_mode &= ~AOUT_CHANMODE_DOLBYSTEREO;
        }

        aout_request_vout_t request_vout = {
            .pf_request_vout = aout_request_vout,
            .p_private = p_dec,
        };
        audio_output_t *p_aout;

        p_aout = input_resource_GetAout( p_owner->p_resource );
        if( p_aout )
        {
            /* TODO: 3.0 HACK: we need to put i_profile inside audio_format_t
             * for 4.0 */
            if( p_dec->fmt_out.i_codec == VLC_CODEC_DTS )
                var_SetBool( p_aout, "dtshd", p_dec->fmt_out.i_profile > 0 );

            /* "gapless-eligible" is only ever cleared when a video ES is
             * added to the input, so it really means "no video anywhere".
             * With no video and no stream output, nothing is slaved to the
             * audio clock and an offset in it cannot be seen by anyone --
             * which is what lets the output correct drift inaudibly instead
             * of punching a hole in the sound. Both uses want the same three
             * conditions, hence the one flag.
             *
             * Read once, when the output is created: an input that only
             * grows a video ES later (MPEG-TS) would keep the audio-only
             * verdict. Rare, and "aout-drift-silence=always" overrides it. */
            bool b_audio_only = p_owner->p_input != NULL
                             && p_owner->p_sout == NULL
                             && var_GetBool( p_owner->p_input,
                                             "gapless-eligible" );

            if( aout_DecNew( p_aout, &format,
                             &p_dec->fmt_out.audio_replay_gain,
                             &request_vout, b_audio_only ) )
            {
                input_resource_PutAout( p_owner->p_resource, p_aout );
                p_aout = NULL;
            }
        }

        vlc_mutex_lock( &p_owner->lock );
        p_owner->p_aout = p_aout;

        DecoderUpdateFormatLocked( p_dec );
        aout_FormatPrepare( &p_owner->fmt.audio );
        vlc_mutex_unlock( &p_owner->lock );

        if( p_owner->p_input != NULL )
            input_SendEventAout( p_owner->p_input );

        if( p_aout == NULL )
        {
            msg_Err( p_dec, "failed to create audio output" );
            return -1;
        }

        p_dec->fmt_out.audio.i_bytes_per_frame =
            p_owner->fmt.audio.i_bytes_per_frame;
        p_dec->fmt_out.audio.i_bitspersample =
            p_owner->fmt.audio.i_bitspersample;
        p_dec->fmt_out.audio.i_frame_length =
            p_owner->fmt.audio.i_frame_length;
    }
    return 0;
}

static int vout_update_format( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    if( p_owner->p_vout == NULL
     || p_dec->fmt_out.video.i_width != p_owner->fmt.video.i_width
     || p_dec->fmt_out.video.i_height != p_owner->fmt.video.i_height
     || p_dec->fmt_out.video.i_visible_width != p_owner->fmt.video.i_visible_width
     || p_dec->fmt_out.video.i_visible_height != p_owner->fmt.video.i_visible_height
     || p_dec->fmt_out.video.i_x_offset != p_owner->fmt.video.i_x_offset
     || p_dec->fmt_out.video.i_y_offset != p_owner->fmt.video.i_y_offset
     || p_dec->fmt_out.i_codec != p_owner->fmt.video.i_chroma
     || (int64_t)p_dec->fmt_out.video.i_sar_num * p_owner->fmt.video.i_sar_den !=
        (int64_t)p_dec->fmt_out.video.i_sar_den * p_owner->fmt.video.i_sar_num ||
        p_dec->fmt_out.video.orientation != p_owner->fmt.video.orientation ||
        p_dec->fmt_out.video.multiview_mode != p_owner->fmt.video.multiview_mode )
    {
        vout_thread_t *p_vout;

        if( !p_dec->fmt_out.video.i_width ||
            !p_dec->fmt_out.video.i_height ||
            p_dec->fmt_out.video.i_width < p_dec->fmt_out.video.i_visible_width ||
            p_dec->fmt_out.video.i_height < p_dec->fmt_out.video.i_visible_height )
        {
            /* Can't create a new vout without display size */
            return -1;
        }

        video_format_t fmt = p_dec->fmt_out.video;
        fmt.i_chroma = p_dec->fmt_out.i_codec;

        if( vlc_fourcc_IsYUV( fmt.i_chroma ) )
        {
            const vlc_chroma_description_t *dsc = vlc_fourcc_GetChromaDescription( fmt.i_chroma );
            for( unsigned int i = 0; dsc && i < dsc->plane_count; i++ )
            {
                while( fmt.i_width % dsc->p[i].w.den )
                    fmt.i_width++;
                while( fmt.i_height % dsc->p[i].h.den )
                    fmt.i_height++;
            }
        }

        if( !fmt.i_visible_width || !fmt.i_visible_height )
        {
            if( p_dec->fmt_in.video.i_visible_width &&
                p_dec->fmt_in.video.i_visible_height )
            {
                fmt.i_visible_width  = p_dec->fmt_in.video.i_visible_width;
                fmt.i_visible_height = p_dec->fmt_in.video.i_visible_height;
                fmt.i_x_offset       = p_dec->fmt_in.video.i_x_offset;
                fmt.i_y_offset       = p_dec->fmt_in.video.i_y_offset;
            }
            else
            {
                fmt.i_visible_width  = fmt.i_width;
                fmt.i_visible_height = fmt.i_height;
                fmt.i_x_offset       = 0;
                fmt.i_y_offset       = 0;
            }
        }

        if( fmt.i_visible_height == 1088 &&
            var_CreateGetBool( p_dec, "hdtv-fix" ) )
        {
            fmt.i_visible_height = 1080;
            if( !(fmt.i_sar_num % 136))
            {
                fmt.i_sar_num *= 135;
                fmt.i_sar_den *= 136;
            }
            msg_Warn( p_dec, "Fixing broken HDTV stream (display_height=1088)");
        }

        if( !fmt.i_sar_num || !fmt.i_sar_den )
        {
            fmt.i_sar_num = 1;
            fmt.i_sar_den = 1;
        }

        vlc_ureduce( &fmt.i_sar_num, &fmt.i_sar_den,
                     fmt.i_sar_num, fmt.i_sar_den, 50000 );

        video_format_AdjustColorSpace( &fmt );

        vlc_mutex_lock( &p_owner->lock );

        p_vout = p_owner->p_vout;
        p_owner->p_vout = NULL;
        vlc_mutex_unlock( &p_owner->lock );

        unsigned dpb_size;
        switch( p_dec->fmt_in.i_codec )
        {
        case VLC_CODEC_HEVC:
        case VLC_CODEC_H264:
        case VLC_CODEC_DIRAC: /* FIXME valid ? */
            /* 18 is the worst case the codec allows -- 16 reference frames
             * plus reordering -- and almost no real stream comes near it. At
             * 1080p it asks the vout for 26 pictures, 81 MB, on machines that
             * may have 1 GB in total; four reference frames need half that.
             * Prefer what the decoder read out of the sequence header, capped
             * at the worst case so a stream that really does use 16 references
             * behaves exactly as before. */
            dpb_size = 18;
            if( p_dec->i_dpb_size > 0 && (unsigned)p_dec->i_dpb_size < dpb_size )
                dpb_size = p_dec->i_dpb_size;
            break;
        case VLC_CODEC_AV1:
            dpb_size = 8; /* NUM_REF_FRAMES from the AV1 spec */
            break;
        case VLC_CODEC_VP5:
        case VLC_CODEC_VP6:
        case VLC_CODEC_VP6F:
        case VLC_CODEC_VP8:
            dpb_size = 3;
            break;
        default:
            dpb_size = 2;
            break;
        }
        msg_Dbg( p_dec, "picture pool: dpb %u + %d extra + 1 (%s)", dpb_size,
                 p_dec->i_extra_picture_buffers,
                 p_dec->i_dpb_size > 0 ? "from the stream" : "codec worst case" );
        p_vout = input_resource_RequestVout( p_owner->p_resource,
                                             p_vout, &fmt,
                                             dpb_size +
                                             p_dec->i_extra_picture_buffers + 1,
                                             true );
        vlc_mutex_lock( &p_owner->lock );
        p_owner->p_vout = p_vout;

        DecoderUpdateFormatLocked( p_dec );
        p_owner->fmt.video.i_chroma = p_dec->fmt_out.i_codec;
        vlc_mutex_unlock( &p_owner->lock );

        if( p_owner->p_input != NULL )
            input_SendEventVout( p_owner->p_input );
        if( p_vout == NULL )
        {
            msg_Err( p_dec, "failed to create video output" );
            return -1;
        }
    }

    if ( memcmp( &p_dec->fmt_out.video.mastering,
                 &p_owner->fmt.video.mastering,
                 sizeof(p_owner->fmt.video.mastering)) ||
         p_dec->fmt_out.video.lighting.MaxCLL !=
         p_owner->fmt.video.lighting.MaxCLL ||
         p_dec->fmt_out.video.lighting.MaxFALL !=
         p_owner->fmt.video.lighting.MaxFALL)
    {
        /* the format has changed but we don't need a new vout */
        vlc_mutex_lock( &p_owner->lock );
        DecoderUpdateFormatLocked( p_dec );
        vlc_mutex_unlock( &p_owner->lock );
    }
    return 0;
}

static picture_t *vout_new_buffer( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    assert( p_owner->p_vout );

    return vout_GetPicture( p_owner->p_vout );
}

static subpicture_t *spu_new_buffer( decoder_t *p_dec,
                                     const subpicture_updater_t *p_updater )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    vout_thread_t *p_vout = NULL;
    subpicture_t *p_subpic;
    int i_attempts = 30;

    while( i_attempts-- )
    {
        if( p_owner->error )
            break;

        p_vout = input_resource_HoldVout( p_owner->p_resource );
        if( p_vout )
            break;

        msleep( DECODER_SPU_VOUT_WAIT_DURATION );
    }

    if( !p_vout )
    {
        msg_Warn( p_dec, "no vout found, dropping subpicture" );
        return NULL;
    }

    if( p_owner->p_spu_vout != p_vout )
    {
        p_owner->i_spu_channel = vout_RegisterSubpictureChannel( p_vout );
        p_owner->i_spu_order = 0;
        p_owner->p_spu_vout = p_vout;
    }

    p_subpic = subpicture_New( p_updater );
    if( p_subpic )
    {
        p_subpic->i_channel = p_owner->i_spu_channel;
        p_subpic->i_order = p_owner->i_spu_order++;
        p_subpic->b_subtitle = true;
    }

    vlc_object_release( p_vout );

    return p_subpic;
}

static int DecoderGetInputAttachments( decoder_t *p_dec,
                                       input_attachment_t ***ppp_attachment,
                                       int *pi_attachment )
{
    input_thread_t *p_input = p_dec->p_owner->p_input;

    if( unlikely(p_input == NULL) )
        return VLC_ENOOBJ;
    return input_Control( p_input, INPUT_GET_ATTACHMENTS,
                          ppp_attachment, pi_attachment );
}

static vlc_tick_t DecoderGetDisplayDate( decoder_t *p_dec, vlc_tick_t i_ts )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_mutex_lock( &p_owner->lock );
    if( p_owner->b_waiting || p_owner->paused )
        i_ts = VLC_TICK_INVALID;
    vlc_mutex_unlock( &p_owner->lock );

    if( !p_owner->p_clock || i_ts <= VLC_TICK_INVALID )
        return i_ts;

    if( input_clock_ConvertTS( VLC_OBJECT(p_dec), p_owner->p_clock, NULL, &i_ts, NULL, INT64_MAX ) ) {
        msg_Err(p_dec, "Could not get display date for timestamp %"PRId64"", i_ts);
        return VLC_TICK_INVALID;
    }

    return i_ts;
}

static int DecoderGetDisplayRate( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    if( !p_owner->p_clock )
        return INPUT_RATE_DEFAULT;
    return input_clock_GetRate( p_owner->p_clock );
}

/*****************************************************************************
 * Public functions
 *****************************************************************************/
block_t *decoder_NewAudioBuffer( decoder_t *dec, int samples )
{
    assert( dec->fmt_out.audio.i_frame_length > 0
         && dec->fmt_out.audio.i_bytes_per_frame  > 0 );

    size_t length = samples * dec->fmt_out.audio.i_bytes_per_frame
                            / dec->fmt_out.audio.i_frame_length;
    block_t *block = block_Alloc( length );
    if( likely(block != NULL) )
    {
        block->i_nb_samples = samples;
        block->i_pts = block->i_length = 0;
    }
    return block;
}

subpicture_t *decoder_NewSubpicture( decoder_t *p_decoder,
                                     const subpicture_updater_t *p_dyn )
{
    subpicture_t *p_subpicture = p_decoder->pf_spu_buffer_new( p_decoder, p_dyn );
    if( !p_subpicture )
        msg_Warn( p_decoder, "can't get output subpicture" );
    return p_subpicture;
}

static void RequestReload( decoder_t * p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    /* Don't override reload if it's RELOAD_DECODER_AOUT */
    int expected = RELOAD_NO_REQUEST;
    atomic_compare_exchange_strong( &p_owner->reload, &expected, RELOAD_DECODER );
}

/* decoder_GetInputAttachments:
 */
int decoder_GetInputAttachments( decoder_t *p_dec,
                                 input_attachment_t ***ppp_attachment,
                                 int *pi_attachment )
{
    if( !p_dec->pf_get_attachments )
        return VLC_EGENERIC;

    return p_dec->pf_get_attachments( p_dec, ppp_attachment, pi_attachment );
}
/* decoder_GetDisplayDate:
 */
vlc_tick_t decoder_GetDisplayDate( decoder_t *p_dec, vlc_tick_t i_ts )
{
    if( !p_dec->pf_get_display_date )
        return VLC_TICK_INVALID;

    return p_dec->pf_get_display_date( p_dec, i_ts );
}
/* decoder_GetDisplayRate:
 */
int decoder_GetDisplayRate( decoder_t *p_dec )
{
    if( !p_dec->pf_get_display_rate )
        return INPUT_RATE_DEFAULT;

    return p_dec->pf_get_display_rate( p_dec );
}

void decoder_AbortPictures( decoder_t *p_dec, bool b_abort )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_mutex_lock( &p_owner->lock );
    if( p_owner->p_vout != NULL )
        vout_Cancel( p_owner->p_vout, b_abort );
    vlc_mutex_unlock( &p_owner->lock );
}

/* Look-ahead decode cache: pool reserve kept free for the DECODE side
 * (reference frames + the frame being decoded + reorder in flight). The
 * cache target is capped this many pictures below the pool headroom (see
 * DecoderVideoCacheTarget) so the fill loop always stops with at least
 * this many buffers free -- the decode never sinks into picture_pool_Wait
 * with the vout idle (paused and/or held by a fill episode), where a
 * B-pyramid could grab several decode buffers between two outputs and
 * block INSIDE avcodec with nobody left to free the pool (the full app
 * freeze once seen after a pause/play storm on the Mini G4). 720p H.264
 * tops out at a DPB of 5, plus in-flight and reorder slack -- 10 covers
 * the worst legal reorder depth; 6 was NOT enough.
 *
 * This used to be the STAGING threshold: past it every further decoded
 * picture was copied into plain memory (releasing its pool buffer) so the
 * cache could grow to the whole MB budget instead of stopping at the
 * pool. That copy cost one full-frame memcpy per picture -- and on the
 * single-core software-decode machines this cache exists for, those were
 * exactly the cycles the decoder needed, trading smooth-with-the-odd
 * -dropout playback for a steady stutter. Dropped: the cache is now
 * simply bounded by the pool. */
#define VIDEO_CACHE_POOL_MARGIN 10

/* Round 87: pace the look-ahead REFILL so decoding-ahead never saturates
 * the single-core PPC targets. Flat-out decode-ahead was measured to peg
 * the core (0% idle / 57% sys) during every mid-play top-up, starving the
 * audio chain into a "playback too late" flush that resets the clock and
 * forces the very re-buffer the cache exists to prevent (see HANDOFF
 * round 87).
 *
 * A FIXED yield proved insufficient (round 87b): on heavy scenes the
 * per-picture decode time grows past (frame period - yield), the paced
 * refill silently drops below 1x, the cushion drains over a minute, and
 * the old low-water flat-out cliff then re-created the saturation hiccup
 * it was meant to avoid. Instead, an adaptive CONTROLLER: every
 * PACE_INTERVAL the decoder compares the cushion count to the previous
 * mark. Cushion not growing => the yield shrinks (more core to decode);
 * growing faster than needed => the yield grows (hand the core back to
 * the 1x consumers). The yield is further scaled by cushion fullness
 * (near-empty decodes almost flat-out, near-full coasts), so a sudden
 * heavy burst is countered faster than the controller interval. Flat-out
 * is reserved for b_waiting episodes (initial fill and es_out re-buffer:
 * display frozen, nothing to starve, shortest freeze wins). */
#define VIDEO_CACHE_PACE_INTERVAL   (CLOCK_FREQ / 2)  /* controller period */
#define VIDEO_CACHE_PACE_INIT       (12 * 1000)       /* starting yield */
#define VIDEO_CACHE_PACE_MAX        (30 * 1000)       /* yield ceiling */
#define VIDEO_CACHE_PACE_STEP       (2 * 1000)        /* adjust step */
#define VIDEO_CACHE_PACE_SLOPE_MIN  1   /* min cushion growth / interval */
#define VIDEO_CACHE_PACE_SLOPE_MAX  4   /* growth beyond which we relax */

/* Effective look-ahead cache target in pictures for the current stream:
 * the smaller of the MB budget, the seconds cap and the pool headroom.
 * This is the single source of truth for both the decoder's own fill loop
 * and es_out's fill gate (through input_DecoderGetCacheState): if they
 * diverged, the decoder could park short of what es_out waits for and
 * buffering would only end at EOF. Returns 0 when unknown yet (no picture
 * measured / no vout). Owner lock held. */
static size_t DecoderVideoCacheTarget( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    if( p_owner->i_cache_bytes == 0 || p_owner->i_cache_pic_bytes == 0
     || p_owner->p_vout == NULL )
        return 0;

    size_t i_target = p_owner->i_cache_bytes / p_owner->i_cache_pic_bytes;

    const video_format_t *fmt = &p_dec->fmt_out.video;
    if( p_owner->i_cache_max_seconds > 0
     && fmt->i_frame_rate > 0 && fmt->i_frame_rate_base > 0 )
    {
        size_t i_cap = (size_t)( (double)fmt->i_frame_rate
                     / fmt->i_frame_rate_base * p_owner->i_cache_max_seconds );
        if( i_cap < i_target )
            i_target = i_cap;
    }

    /* The cache lives in the vout fifo as pool buffers, so it can never
     * grow past the pool headroom minus the decode-side reserve (there is
     * no staging fallback: see VIDEO_CACHE_POOL_MARGIN). Clamp the target
     * to that bound -- otherwise the fill gate would wait on a count the
     * fill can never reach, top out after a second and loop episodes
     * forever. */
    size_t i_headroom = vout_GetCacheHeadroom( p_owner->p_vout );
    if( vout_CacheIsDirectRendering( p_owner->p_vout ) )
    {
        /* Direct rendering: the decoder's pictures ARE the display pool's.
         * MEASURED on the Mini G4 (Radeon 9200, 720p): a micro-cushion is
         * WORSE than no cache at all -- the whole machinery (100 ms
         * decoder-throttle quantum, refill hold/release cycles) is tuned
         * for cushions of dozens of pictures, and a ~8-picture target
         * produced a refill every second with 300+ late pictures where the
         * plain path plays clean. Below a viability floor, turn the cache
         * OFF entirely for this stream. This pool's headroom already
         * excludes the codec DPB, so a small extra margin suffices.
         *
         * The display is expected to have sized its pool for the requested
         * budget (macosx_gl1.m's Pool() does, bounded by RAM); a display
         * that hands out a fixed cushion simply lands under the floor and
         * runs without a cache, as before. */
        enum { VIDEO_CACHE_DR_POOL_MARGIN = 4,
               VIDEO_CACHE_DR_MIN_VIABLE  = 24 };
        size_t i_bound = i_headroom > VIDEO_CACHE_DR_POOL_MARGIN
                       ? i_headroom - VIDEO_CACHE_DR_POOL_MARGIN : 1;
        if( i_bound < VIDEO_CACHE_DR_MIN_VIABLE )
            i_bound = 0;
        if( i_bound < i_target )
            i_target = i_bound;
    }
    else
    {
        /* Indirect rendering: the decoder pool is separate system memory,
         * eagerly sized to hold the whole budget (see vout_wrapper.c), so
         * this clamp normally leaves the requested target untouched and
         * only bites when the budget exceeds the pool's up-front RAM cap.
         * The headroom here still counts the codec DPB, so the reserve is
         * the full VIDEO_CACHE_POOL_MARGIN. No viability floor: the eager
         * pool is always large, and a small explicit budget is the user's
         * to make. */
        size_t i_bound = i_headroom > VIDEO_CACHE_POOL_MARGIN
                       ? i_headroom - VIDEO_CACHE_POOL_MARGIN : 1;
        if( i_bound < i_target )
            i_target = i_bound;
    }

    return i_target;
}

static void DecoderWaitUnblock( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_assert_locked( &p_owner->lock );

    for( ;; )
    {
        if( !p_owner->b_waiting || !p_owner->b_has_data )
            break;
        vlc_cond_wait( &p_owner->wait_request, &p_owner->lock );
    }
}

/* DecoderTimedWait: Interruptible wait
 * Returns VLC_SUCCESS if wait was not interrupted, and VLC_EGENERIC otherwise */
static int DecoderTimedWait( decoder_t *p_dec, vlc_tick_t deadline )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    if (deadline - mdate() <= 0)
        return VLC_SUCCESS;

    vlc_fifo_Lock( p_owner->p_fifo );
    while( !p_owner->flushing
        && vlc_fifo_TimedWaitCond( p_owner->p_fifo, &p_owner->wait_timed,
                                   deadline ) == 0 );
    int ret = p_owner->flushing ? VLC_EGENERIC : VLC_SUCCESS;
    vlc_fifo_Unlock( p_owner->p_fifo );
    return ret;
}

static inline void DecoderUpdatePreroll( int64_t *pi_preroll, const block_t *p )
{
    if( p->i_flags & BLOCK_FLAG_PREROLL )
        *pi_preroll = INT64_MAX;
    /* Check if we can use the packet for end of preroll */
    else if( (p->i_flags & BLOCK_FLAG_DISCONTINUITY) &&
             (p->i_buffer == 0 || (p->i_flags & BLOCK_FLAG_CORRUPTED)) )
        *pi_preroll = INT64_MAX;
    else if( p->i_dts > VLC_TICK_INVALID )
        *pi_preroll = __MIN( *pi_preroll, p->i_dts );
    else if( p->i_pts > VLC_TICK_INVALID )
        *pi_preroll = __MIN( *pi_preroll, p->i_pts );
}

static void DecoderFixTs( decoder_t *p_dec, vlc_tick_t *pi_ts0, vlc_tick_t *pi_ts1,
                          vlc_tick_t *pi_duration, int *pi_rate, vlc_tick_t i_ts_bound )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    input_clock_t   *p_clock = p_owner->p_clock;

    vlc_assert_locked( &p_owner->lock );

    const vlc_tick_t i_es_delay = p_owner->i_ts_delay;

    if( !p_clock )
        return;

    const bool b_ephemere = pi_ts1 && *pi_ts0 == *pi_ts1;
    int i_rate;

    if( *pi_ts0 > VLC_TICK_INVALID )
    {
        *pi_ts0 += i_es_delay;
        if( pi_ts1 && *pi_ts1 > VLC_TICK_INVALID )
            *pi_ts1 += i_es_delay;
        if( i_ts_bound != INT64_MAX )
            i_ts_bound += i_es_delay;
        if( input_clock_ConvertTS( VLC_OBJECT(p_dec), p_clock, &i_rate, pi_ts0, pi_ts1, i_ts_bound ) ) {
            const char *psz_name = module_get_name( p_dec->p_module, false );
            if( pi_ts1 != NULL )
                msg_Err(p_dec, "Could not convert timestamps %"PRId64
                        ", %"PRId64" for %s", *pi_ts0, *pi_ts1, psz_name );
            else
                msg_Err(p_dec, "Could not convert timestamp %"PRId64" for %s", *pi_ts0, psz_name );
            *pi_ts0 = VLC_TICK_INVALID;
        }
    }
    else
    {
        i_rate = input_clock_GetRate( p_clock );
    }

    /* Do not create ephemere data because of rounding errors */
    if( !b_ephemere && pi_ts1 && *pi_ts0 == *pi_ts1 )
        *pi_ts1 += 1;

    if( pi_duration )
        *pi_duration = ( *pi_duration * i_rate + INPUT_RATE_DEFAULT-1 )
            / INPUT_RATE_DEFAULT;

    if( pi_rate )
        *pi_rate = i_rate;
}

#ifdef ENABLE_SOUT
static int DecoderPlaySout( decoder_t *p_dec, block_t *p_sout_block )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    assert( p_owner->p_clock );
    assert( !p_sout_block->p_next );

    vlc_mutex_lock( &p_owner->lock );

    if( p_owner->b_waiting )
    {
        p_owner->b_has_data = true;
        vlc_cond_signal( &p_owner->wait_acknowledge );
    }

    DecoderWaitUnblock( p_dec );
    DecoderFixTs( p_dec, &p_sout_block->i_dts, &p_sout_block->i_pts,
                  &p_sout_block->i_length, NULL, INT64_MAX );

    vlc_mutex_unlock( &p_owner->lock );

    /* FIXME --VLC_TICK_INVALID inspect stream_output*/
    return sout_InputSendBuffer( p_owner->p_sout_input, p_sout_block );
}

/* This function process a block for sout
 */
static void DecoderProcessSout( decoder_t *p_dec, block_t *p_block )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    block_t *p_sout_block;
    block_t **pp_block = p_block ? &p_block : NULL;

    while( ( p_sout_block =
                 p_dec->pf_packetize( p_dec, pp_block ) ) )
    {
        if( p_owner->p_sout_input == NULL )
        {
            vlc_mutex_lock( &p_owner->lock );
            DecoderUpdateFormatLocked( p_dec );

            p_owner->fmt.i_group = p_dec->fmt_in.i_group;
            p_owner->fmt.i_id = p_dec->fmt_in.i_id;
            if( p_dec->fmt_in.psz_language )
            {
                free( p_owner->fmt.psz_language );
                p_owner->fmt.psz_language =
                    strdup( p_dec->fmt_in.psz_language );
            }
            vlc_mutex_unlock( &p_owner->lock );

            p_owner->p_sout_input =
                sout_InputNew( p_owner->p_sout, &p_owner->fmt );

            if( p_owner->p_sout_input == NULL )
            {
                msg_Err( p_dec, "cannot create packetizer output (%4.4s)",
                         (char *)&p_owner->fmt.i_codec );
                p_owner->error = true;

                if(p_block)
                    block_Release(p_block);

                block_ChainRelease(p_sout_block);
                break;
            }
        }

        while( p_sout_block )
        {
            block_t *p_next = p_sout_block->p_next;

            p_sout_block->p_next = NULL;

            if( DecoderPlaySout( p_dec, p_sout_block ) == VLC_EGENERIC )
            {
                msg_Err( p_dec, "cannot continue streaming due to errors with codec %4.4s",
                                (char *)&p_owner->fmt.i_codec );

                p_owner->error = true;

                /* Cleanup */

                if( p_block )
                    block_Release( p_block );

                block_ChainRelease( p_next );
                return;
            }

            p_sout_block = p_next;
        }
    }
}
#endif

static void DecoderPlayCc( decoder_t *p_dec, block_t *p_cc,
                           const decoder_cc_desc_t *p_desc )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_mutex_lock( &p_owner->lock );

    p_owner->cc.desc = *p_desc;

    /* Fanout data to all decoders. We do not know if es_out
       selected 608 or 708. */
    uint64_t i_bitmap = p_owner->cc.desc.i_608_channels |
                        p_owner->cc.desc.i_708_channels;

    for( int i=0; i_bitmap > 0; i_bitmap >>= 1, i++ )
    {
        decoder_t *p_ccdec = p_owner->cc.pp_decoder[i];
        if( !p_ccdec )
            continue;

        if( i_bitmap > 1 )
        {
            block_FifoPut( p_ccdec->p_owner->p_fifo, block_Duplicate(p_cc) );
        }
        else
        {
            block_FifoPut( p_ccdec->p_owner->p_fifo, p_cc );
            p_cc = NULL; /* was last dec */
        }
    }

    vlc_mutex_unlock( &p_owner->lock );

    if( p_cc ) /* can have bitmap set but no created decs */
        block_Release( p_cc );
}

static void PacketizerGetCc( decoder_t *p_dec, decoder_t *p_dec_cc )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    block_t *p_cc;
    decoder_cc_desc_t desc;

    /* Do not try retreiving CC if not wanted (sout) or cannot be retreived */
    if( !p_owner->cc.b_supported )
        return;

    assert( p_dec_cc->pf_get_cc != NULL );

    p_cc = p_dec_cc->pf_get_cc( p_dec_cc, &desc );
    if( !p_cc )
        return;
    DecoderPlayCc( p_dec, p_cc, &desc );
}

static int DecoderQueueCc( decoder_t *p_videodec, block_t *p_cc,
                           const decoder_cc_desc_t *p_desc )
{
    decoder_owner_sys_t *p_owner = p_videodec->p_owner;

    if( unlikely( p_cc != NULL ) )
    {
        if( p_owner->cc.b_supported &&
           ( !p_owner->p_packetizer || !p_owner->p_packetizer->pf_get_cc ) )
            DecoderPlayCc( p_videodec, p_cc, p_desc );
        else
            block_Release( p_cc );
    }
    return 0;
}

static int DecoderPlayVideo( decoder_t *p_dec, picture_t *p_picture,
                             unsigned *restrict pi_lost_sum )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    vout_thread_t  *p_vout = p_owner->p_vout;
    bool prerolled;

    vlc_mutex_lock( &p_owner->lock );
    if( p_owner->i_preroll_end > p_picture->date )
    {
        vlc_mutex_unlock( &p_owner->lock );
        picture_Release( p_picture );
        return -1;
    }

    prerolled = p_owner->i_preroll_end > INT64_MIN;
    p_owner->i_preroll_end = INT64_MIN;
    vlc_mutex_unlock( &p_owner->lock );

    if( unlikely(prerolled) )
    {
        msg_Dbg( p_dec, "end of video preroll" );

        if( p_vout )
            vout_Flush( p_vout, VLC_TICK_INVALID+1 );
    }

    if( p_picture->date <= VLC_TICK_INVALID )
    {
        msg_Warn( p_dec, "non-dated video buffer received" );
        goto discard;
    }

    /* */
    vlc_mutex_lock( &p_owner->lock );

    if( p_owner->b_waiting && !p_owner->b_first )
    {
        p_owner->b_has_data = true;
        vlc_cond_signal( &p_owner->wait_acknowledge );
    }

    /* Look-ahead decode cache: while es_out's fill gate holds playback
     * (b_waiting), keep decoding into the vout fifo instead of parking
     * on the second picture, until the fill target is reached. The vout
     * is put on hold first so it neither displays nor trashes those
     * pictures (their dates, converted against the still-frozen clock
     * origin, are re-based by es_out when the gate opens). */
    bool b_cache_fill = false;
    if( p_owner->i_cache_bytes > 0 && p_vout != NULL )
    {
        /* (Re-)measured on every picture: a mid-stream format change
         * would otherwise leave the byte-budget target computed against
         * a stale picture size. Opaque hardware pictures measure 0 and
         * keep the previous (or unknown) size. */
        size_t i_bytes = 0;
        for( int i = 0; i < p_picture->i_planes; i++ )
            i_bytes += (size_t)p_picture->p[i].i_pitch
                     * p_picture->p[i].i_lines;
        if( i_bytes > 0 )
            p_owner->i_cache_pic_bytes = i_bytes;
    }
    /* Computed once under the owner lock for the fill-mode check below. */
    size_t i_cache_target = 0;
    if( p_owner->i_cache_bytes > 0 && p_vout != NULL )
        i_cache_target = DecoderVideoCacheTarget( p_dec );

    if( p_owner->b_waiting && !p_owner->b_first
     && p_owner->i_cache_bytes > 0 && p_vout != NULL
     && vout_GetDecoderFifoCount( p_vout ) < i_cache_target )
    {
        b_cache_fill = true;
        /* Not a pure latch anymore: a seek can interleave the decoder
         * flush's vout-flush command AFTER the hold this fill just
         * queued (both traverse the vout control queue) -- the vout
         * ends up unheld while b_cache_hold still says held, the
         * unheld vout eats every picture as it lands and the fill
         * crawls at ~1% until the wall timeout (observed on seek: 276
         * pictures lost, ~10 s stall, recovery only via the next
         * refill). Cross-checking the vout's own state self-heals that
         * desync at the very next picture; the release race this could
         * reopen is closed by input_DecoderStopWait being the one to
         * queue the final unhold, under this same owner lock. */
        if( !p_owner->b_cache_hold || !vout_IsCacheHeld( p_vout ) )
        {
            p_owner->b_cache_hold = true;
            vout_ChangeCacheHold( p_vout, true );
        }
    }

    bool b_first_after_wait = p_owner->b_waiting && p_owner->b_has_data
                           && !b_cache_fill;

    if( !b_cache_fill )
        DecoderWaitUnblock( p_dec );

    if( p_owner->b_waiting && p_owner->b_first )
    {
        /* Not an assert on b_first anymore: in cache-fill mode the
         * decoder passes here for every accumulated picture, and only
         * the very first one must be forced on screen. */
        msg_Dbg( p_dec, "Received first picture" );
        p_owner->b_first = false;
        p_picture->b_force = true;
    }

    const bool b_dated = p_picture->date > VLC_TICK_INVALID;
    int i_rate = INPUT_RATE_DEFAULT;
    vlc_tick_t i_ts_bound = DECODER_BOGUS_VIDEO_DELAY;
    if( p_owner->i_cache_bytes > 0 )
    {
        /* The look-ahead cache legitimately decodes up to its whole
         * time-depth ahead of the clock, so pictures near the far edge
         * of the cushion carry dates that far in the future -- the
         * stock bogus-date guard (~9 s) skips them as broken stream
         * timestamps. Observed at video-cache-mb=512 (353-picture
         * target, ~15 s of 24 fps video): every picture decoded past
         * ~10 s ahead was dropped "early picture skipped", silently
         * capping the cache and burning the core decoding into the
         * same wall forever. Widen the guard by the current target's
         * time-depth; truly insane dates (minutes off) stay caught. */
        const video_format_t *fmt = &p_dec->fmt_out.video;
        size_t i_target = DecoderVideoCacheTarget( p_dec );
        if( i_target > 0
         && fmt->i_frame_rate > 0 && fmt->i_frame_rate_base > 0 )
            i_ts_bound += (vlc_tick_t)i_target * CLOCK_FREQ
                        * fmt->i_frame_rate_base / fmt->i_frame_rate;
        else if( p_owner->i_cache_max_seconds > 0 )
            i_ts_bound += (vlc_tick_t)p_owner->i_cache_max_seconds
                        * CLOCK_FREQ;
        else
            /* No target measured yet and no seconds cap: cover the
             * worst case rather than skipping legitimate pictures. */
            i_ts_bound += (vlc_tick_t)60 * CLOCK_FREQ;
    }
    DecoderFixTs( p_dec, &p_picture->date, NULL, NULL,
                  &i_rate, i_ts_bound );

    vlc_mutex_unlock( &p_owner->lock );

    /* FIXME: The *input* FIFO should not be locked here. This will not work
     * properly if/when pictures are queued asynchronously. */
    vlc_fifo_Lock( p_owner->p_fifo );
    if( unlikely(p_owner->paused) && likely(p_owner->frames_countdown > 0) )
        p_owner->frames_countdown--;
    vlc_fifo_Unlock( p_owner->p_fifo );

    /* */
    if( p_vout == NULL )
        goto discard;

    if( p_picture->b_force || p_picture->date > VLC_TICK_INVALID )
        /* FIXME: VLC_TICK_INVALID -- verify video_output */
    {
        if( i_rate != p_owner->i_last_rate || b_first_after_wait )
        {
            /* Be sure to not display old picture after our own */
            vout_Flush( p_vout, p_picture->date );
            p_owner->i_last_rate = i_rate;
        }

        /* The look-ahead cache is bounded by the pool: the decoder's fill
         * loop stops at a target kept VIDEO_CACHE_POOL_MARGIN below the
         * headroom (see DecoderVideoCacheTarget), so the queued pool
         * pictures never exhaust it and the decode side never wedges in
         * picture_pool_Wait. Queue the pool picture as-is. */
        vout_PutPicture( p_vout, p_picture );

        /* NO es_out_Control() from this thread, ever: the input thread
         * deletes decoders (EsUnselect at stop and on every dvdnav
         * ES churn) while HOLDING the es_out lock and pthread_join()s
         * this very thread -- a synchronous call back into es_out here
         * deadlocks the whole player the moment those two cross
         * (observed on DVD seek storms: decoder blocked on the es_out
         * lock, input blocked in the join, UI blocked behind both).
         * The fill gate is instead re-evaluated on the INPUT thread:
         * by ES_OUT_SET_PCR while the demux is active, and by the EOF
         * wait's ES_OUT_GET_EMPTY poll (EsOutDecodersIsEmpty calls
         * EsOutDecodersStopBuffering) once a local file is fully
         * demuxed -- worst-case ~100 ms of extra gate latency. */
    }
    else
    {
        if( b_dated )
            msg_Warn( p_dec, "early picture skipped" );
        else
            msg_Warn( p_dec, "non-dated video buffer received" );
        goto discard;
    }

    return 0;
discard:
    *pi_lost_sum += 1;
    picture_Release( p_picture );
    return 0;
}

static void DecoderUpdateStatVideo( decoder_owner_sys_t *p_owner,
                                    unsigned decoded, unsigned lost )
{
    input_thread_t *p_input = p_owner->p_input;
    unsigned displayed = 0;

    /* Update ugly stat */
    if( p_input == NULL )
        return;

    if( p_owner->p_vout != NULL )
    {
        unsigned vout_lost = 0;

        vout_GetResetStatistic( p_owner->p_vout, &displayed, &vout_lost );
        lost += vout_lost;
    }

    vlc_mutex_lock( &input_priv(p_input)->counters.counters_lock );
    stats_Update( input_priv(p_input)->counters.p_decoded_video, decoded, NULL );
    stats_Update( input_priv(p_input)->counters.p_lost_pictures, lost , NULL);
    stats_Update( input_priv(p_input)->counters.p_displayed_pictures, displayed, NULL);
    vlc_mutex_unlock( &input_priv(p_input)->counters.counters_lock );
}

static int DecoderQueueVideo( decoder_t *p_dec, picture_t *p_pic )
{
    assert( p_pic );
    unsigned i_lost = 0;
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    int ret = DecoderPlayVideo( p_dec, p_pic, &i_lost );

    p_owner->pf_update_stat( p_owner, 1, i_lost );
    return ret;
}

/**
 * Gapless (PowerVLC): drops the encoder priming/padding samples advertised by
 * the demuxer in the input format. Generic: works with any audio decoder.
 *
 * \return the block to play, possibly shortened, or NULL if it was entirely
 * made of encoder samples (this is not an error).
 */
static block_t *DecoderGaplessTrim( decoder_t *p_dec, block_t *p_audio )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    if( !p_owner->b_gl_init )
    {
        p_owner->b_gl_init = true;

        uint64_t i_priming = p_dec->fmt_in.audio.i_gapless_priming;
        uint64_t i_length  = p_dec->fmt_in.audio.i_gapless_length;
        unsigned i_in_rate  = p_dec->fmt_in.audio.i_rate;
        unsigned i_out_rate = p_dec->fmt_out.audio.i_rate;

        if( ( i_priming != 0 || i_length != 0 )
         && AOUT_FMT_LINEAR( &p_dec->fmt_out.audio ) && i_out_rate != 0 )
        {
            bool b_ok = true;

            if( i_in_rate != 0 && i_out_rate != i_in_rate )
            {
                /* SBR (HE-AAC): the decoder doubles the sample rate, the
                 * counts given by the demuxer are at the media rate. Only an
                 * integral ratio can be handled safely. */
                if( i_out_rate % i_in_rate == 0 )
                {
                    unsigned i_mul = i_out_rate / i_in_rate;
                    i_priming *= i_mul;
                    i_length  *= i_mul;
                }
                else
                    b_ok = false;
            }

            if( b_ok )
            {
                p_owner->i_gl_priming = i_priming;
                p_owner->i_gl_end = i_length ? i_priming + i_length
                                             : UINT64_MAX;
                p_owner->b_gl_active = true;
                msg_Dbg( p_dec, "gapless trim: priming %"PRIu64", "
                         "valid samples %"PRIu64, i_priming, i_length );
            }
        }
    }

    if( p_audio->i_nb_samples == 0 || p_audio->i_buffer == 0 )
        return p_audio;

    const size_t i_bpf = p_audio->i_buffer / p_audio->i_nb_samples;
    const unsigned i_rate = p_dec->fmt_out.audio.i_rate;
    const uint64_t i_pos = p_owner->i_gl_count;

    /* Always counted: the total is logged when the decoder dies, which is
     * how the priming/padding formulas are checked empirically. */
    p_owner->i_gl_count += p_audio->i_nb_samples;

    if( !p_owner->b_gl_active )
        return p_audio;

    /* Tail: everything past the last valid sample is encoder padding. */
    if( i_pos >= p_owner->i_gl_end )
    {
        block_Release( p_audio );
        return NULL;
    }
    if( p_owner->i_gl_count > p_owner->i_gl_end )
    {
        unsigned i_keep = p_owner->i_gl_end - i_pos;
        p_audio->i_nb_samples = i_keep;
        p_audio->i_buffer = i_keep * i_bpf;
        p_audio->i_length = CLOCK_FREQ * i_keep / i_rate;
    }

    /* Head: encoder delay. */
    if( i_pos < p_owner->i_gl_priming )
    {
        uint64_t i_skip = p_owner->i_gl_priming - i_pos;

        if( i_skip >= p_audio->i_nb_samples )
        {
            block_Release( p_audio );
            return NULL;
        }
        p_audio->p_buffer += i_skip * i_bpf;
        p_audio->i_buffer -= i_skip * i_bpf;
        p_audio->i_nb_samples -= i_skip;
        p_audio->i_pts += CLOCK_FREQ * i_skip / i_rate;
        p_audio->i_length = CLOCK_FREQ * p_audio->i_nb_samples / i_rate;
    }

    return p_audio;
}

static int DecoderPlayAudio( decoder_t *p_dec, block_t *p_audio,
                             unsigned *restrict pi_lost_sum )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    bool prerolled;

    assert( p_audio != NULL );

    p_audio = DecoderGaplessTrim( p_dec, p_audio );
    if( p_audio == NULL )
        return 0; /* fully consumed encoder samples, not a loss */

    vlc_mutex_lock( &p_owner->lock );
    if( p_owner->i_preroll_end > p_audio->i_pts )
    {
        vlc_mutex_unlock( &p_owner->lock );
        block_Release( p_audio );
        return -1;
    }

    prerolled = p_owner->i_preroll_end > INT64_MIN;
    p_owner->i_preroll_end = INT64_MIN;
    vlc_mutex_unlock( &p_owner->lock );

    if( unlikely(prerolled) )
    {
        msg_Dbg( p_dec, "end of audio preroll" );

        if( p_owner->p_aout )
            aout_DecFlush( p_owner->p_aout, false );
    }

    /* */
    if( p_audio->i_pts <= VLC_TICK_INVALID ) // FIXME --VLC_TICK_INVALID verify audio_output/*
    {
        msg_Warn( p_dec, "non-dated audio buffer received" );
        *pi_lost_sum += 1;
        block_Release( p_audio );
        return 0;
    }

    /* */
    vlc_mutex_lock( &p_owner->lock );
    if( p_owner->b_waiting )
    {
        p_owner->b_has_data = true;
        vlc_cond_signal( &p_owner->wait_acknowledge );
    }

    /* */
    int i_rate = INPUT_RATE_DEFAULT;

    DecoderWaitUnblock( p_dec );
    DecoderFixTs( p_dec, &p_audio->i_pts, NULL, &p_audio->i_length,
                  &i_rate, AOUT_MAX_ADVANCE_TIME );
    vlc_mutex_unlock( &p_owner->lock );

    audio_output_t *p_aout = p_owner->p_aout;

    if( p_aout != NULL && p_audio->i_pts > VLC_TICK_INVALID
     && i_rate >= INPUT_RATE_DEFAULT/AOUT_MAX_INPUT_RATE
     && i_rate <= INPUT_RATE_DEFAULT*AOUT_MAX_INPUT_RATE
     && !DecoderTimedWait( p_dec, p_audio->i_pts - AOUT_MAX_PREPARE_TIME ) )
    {
        int status = aout_DecPlay( p_aout, p_audio, i_rate );
        if( status == AOUT_DEC_CHANGED )
        {
            /* Only reload the decoder */
            RequestReload( p_dec );
        }
        else if( status == AOUT_DEC_FAILED )
        {
            /* If we reload because the aout failed, we should release it. That
             * way, a next call to aout_update_format() won't re-use the
             * previous (failing) aout but will try to create a new one. */
            atomic_store( &p_owner->reload, RELOAD_DECODER_AOUT );
        }
    }
    else
    {
        msg_Dbg( p_dec, "discarded audio buffer" );
        *pi_lost_sum += 1;
        block_Release( p_audio );
    }
    return 0;
}

static void DecoderUpdateStatAudio( decoder_owner_sys_t *p_owner,
                                    unsigned decoded, unsigned lost )
{
    input_thread_t *p_input = p_owner->p_input;
    unsigned played = 0;

    /* Update ugly stat */
    if( p_input == NULL )
        return;

    if( p_owner->p_aout != NULL )
    {
        unsigned aout_lost;

        aout_DecGetResetStats( p_owner->p_aout, &aout_lost, &played );
        lost += aout_lost;
    }

    vlc_mutex_lock( &input_priv(p_input)->counters.counters_lock);
    stats_Update( input_priv(p_input)->counters.p_lost_abuffers, lost, NULL );
    stats_Update( input_priv(p_input)->counters.p_played_abuffers, played, NULL );
    stats_Update( input_priv(p_input)->counters.p_decoded_audio, decoded, NULL );
    vlc_mutex_unlock( &input_priv(p_input)->counters.counters_lock);
}

static int DecoderQueueAudio( decoder_t *p_dec, block_t *p_aout_buf )
{
    unsigned lost = 0;
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    int ret = DecoderPlayAudio( p_dec, p_aout_buf, &lost );

    p_owner->pf_update_stat( p_owner, 1, lost );

    return ret;
}

static void DecoderPlaySpu( decoder_t *p_dec, subpicture_t *p_subpic )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    vout_thread_t *p_vout = p_owner->p_spu_vout;

    /* */
    if( p_subpic->i_start <= VLC_TICK_INVALID )
    {
        msg_Warn( p_dec, "non-dated spu buffer received" );
        subpicture_Delete( p_subpic );
        return;
    }

    /* */
    vlc_mutex_lock( &p_owner->lock );

    if( p_owner->b_waiting )
    {
        p_owner->b_has_data = true;
        vlc_cond_signal( &p_owner->wait_acknowledge );
    }

    DecoderWaitUnblock( p_dec );
    DecoderFixTs( p_dec, &p_subpic->i_start, &p_subpic->i_stop, NULL,
                  NULL, INT64_MAX );
    vlc_mutex_unlock( &p_owner->lock );

    if( p_subpic->i_start <= VLC_TICK_INVALID
     || DecoderTimedWait( p_dec, p_subpic->i_start - SPU_MAX_PREPARE_TIME ) )
    {
        subpicture_Delete( p_subpic );
        return;
    }

    vout_PutSubpicture( p_vout, p_subpic );
}

static void DecoderUpdateStatSpu( decoder_owner_sys_t *p_owner,
                                  unsigned decoded, unsigned lost )
{
    (void) p_owner; (void) decoded; (void) lost;
}

static int DecoderQueueSpu( decoder_t *p_dec, subpicture_t *p_spu )
{
    assert( p_spu );
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    input_thread_t *p_input = p_owner->p_input;

    if( p_input != NULL )
    {
        vlc_mutex_lock( &input_priv(p_input)->counters.counters_lock );
        stats_Update( input_priv(p_input)->counters.p_decoded_sub, 1, NULL );
        vlc_mutex_unlock( &input_priv(p_input)->counters.counters_lock );
    }

    int i_ret = -1;
    vout_thread_t *p_vout = input_resource_HoldVout( p_owner->p_resource );
    if( p_vout && p_owner->p_spu_vout == p_vout )
    {
        /* Preroll does not work very well with subtitle */
        vlc_mutex_lock( &p_owner->lock );
        if( p_spu->i_start > VLC_TICK_INVALID &&
            p_spu->i_start < p_owner->i_preroll_end &&
            ( p_spu->i_stop <= VLC_TICK_INVALID || p_spu->i_stop < p_owner->i_preroll_end ) )
        {
            vlc_mutex_unlock( &p_owner->lock );
            subpicture_Delete( p_spu );
        }
        else
        {
            vlc_mutex_unlock( &p_owner->lock );
            DecoderPlaySpu( p_dec, p_spu );
            i_ret = 0;
        }
    }
    else
    {
        subpicture_Delete( p_spu );
    }
    if( p_vout )
        vlc_object_release( p_vout );
    return i_ret;
}

static void DecoderProcess( decoder_t *p_dec, block_t *p_block );
static void DecoderDecode( decoder_t *p_dec, block_t *p_block )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    int ret = p_dec->pf_decode( p_dec, p_block );
    switch( ret )
    {
        case VLCDEC_SUCCESS:
            p_owner->pf_update_stat( p_owner, 1, 0 );
            break;
        case VLCDEC_ECRITICAL:
            p_owner->error = true;
            break;
        case VLCDEC_RELOAD:
            RequestReload( p_dec );
            if( unlikely( p_block == NULL ) )
                break;
            if( !( p_block->i_flags & BLOCK_FLAG_CORE_PRIVATE_RELOADED ) )
            {
                p_block->i_flags |= BLOCK_FLAG_CORE_PRIVATE_RELOADED;
                DecoderProcess( p_dec, p_block );
            }
            else /* We prefer loosing this block than an infinite recursion */
                block_Release( p_block );
            break;
        default:
            vlc_assert_unreachable();
    }
}

/**
 * Decode a block
 *
 * \param p_dec the decoder object
 * \param p_block the block to decode
 */
static void DecoderProcess( decoder_t *p_dec, block_t *p_block )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    if( p_owner->error )
        goto error;

    /* Here, the atomic doesn't prevent to miss a reload request.
     * DecoderProcess() can still be called after the decoder module or the
     * audio output requested a reload. This will only result in a drop of an
     * input block or an output buffer. */
    enum reload reload;
    if( ( reload = atomic_exchange( &p_owner->reload, RELOAD_NO_REQUEST ) ) )
    {
        msg_Warn( p_dec, "Reloading the decoder module%s",
                  reload == RELOAD_DECODER_AOUT ? " and the audio output" : "" );

        if( ReloadDecoder( p_dec, false, &p_dec->fmt_in, reload ) != VLC_SUCCESS )
            goto error;
    }

    bool packetize = p_owner->p_packetizer != NULL;
    if( p_block )
    {
        if( p_block->i_buffer <= 0 )
            goto error;

        vlc_mutex_lock( &p_owner->lock );
        DecoderUpdatePreroll( &p_owner->i_preroll_end, p_block );
        vlc_mutex_unlock( &p_owner->lock );
        if( unlikely( p_block->i_flags & BLOCK_FLAG_CORE_PRIVATE_RELOADED ) )
        {
            /* This block has already been packetized */
            packetize = false;
        }
    }

#ifdef ENABLE_SOUT
    if( p_owner->p_sout != NULL )
    {
        DecoderProcessSout( p_dec, p_block );
        return;
    }
#endif
    if( packetize )
    {
        block_t *p_packetized_block;
        block_t **pp_block = p_block ? &p_block : NULL;
        decoder_t *p_packetizer = p_owner->p_packetizer;

        while( (p_packetized_block =
                p_packetizer->pf_packetize( p_packetizer, pp_block ) ) )
        {
            if( !es_format_IsSimilar( &p_dec->fmt_in, &p_packetizer->fmt_out ) )
            {
                msg_Dbg( p_dec, "restarting module due to input format change");

                /* Drain the decoder module */
                DecoderDecode( p_dec, NULL );

                if( ReloadDecoder( p_dec, false, &p_packetizer->fmt_out,
                                   RELOAD_DECODER ) != VLC_SUCCESS )
                {
                    block_ChainRelease( p_packetized_block );
                    return;
                }
            }

            if( p_packetizer->pf_get_cc )
                PacketizerGetCc( p_dec, p_packetizer );

            while( p_packetized_block )
            {
                block_t *p_next = p_packetized_block->p_next;
                p_packetized_block->p_next = NULL;

                DecoderDecode( p_dec, p_packetized_block );
                if( p_owner->error )
                {
                    block_ChainRelease( p_next );
                    return;
                }

                p_packetized_block = p_next;
            }
        }
        /* Drain the decoder after the packetizer is drained */
        if( !pp_block )
            DecoderDecode( p_dec, NULL );
    }
    else
        DecoderDecode( p_dec, p_block );
    return;

error:
    if( p_block )
        block_Release( p_block );
}

static void DecoderProcessFlush( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    decoder_t *p_packetizer = p_owner->p_packetizer;

    if( p_owner->error )
        return;

    if( p_packetizer != NULL && p_packetizer->pf_flush != NULL )
        p_packetizer->pf_flush( p_packetizer );

    if ( p_dec->pf_flush != NULL )
        p_dec->pf_flush( p_dec );

    /* flush CC sub decoders */
    if( p_owner->cc.b_supported )
    {
        for( int i=0; i<MAX_CC_DECODERS; i++ )
        {
            decoder_t *p_subdec = p_owner->cc.pp_decoder[i];
            if( p_subdec && p_subdec->pf_flush )
                p_subdec->pf_flush( p_subdec );
        }
    }

#ifdef ENABLE_SOUT
    if ( p_owner->p_sout_input != NULL )
    {
        sout_InputFlush( p_owner->p_sout_input );
    }
#endif
    if( p_dec->fmt_out.i_cat == AUDIO_ES )
    {
        /* Gapless: once the end of stream has been drained, the only flush
         * that can still arrive is the teardown one — input_DecoderDelete
         * raises "flushing" to unblock DecoderTimedWait before joining the
         * thread. Flushing the output there would throw away the very
         * audio the next track is meant to adopt (it did: the transition
         * was gapless on a fast machine, which usually cancelled the
         * thread before it ran this, and never on a slow one). */
        if( p_owner->b_gapless_drained )
        {
            msg_Dbg( p_dec, "gapless: teardown flush, keeping the queued "
                     "audio for the next track" );
        }
        else
        {
            if( p_owner->p_aout )
                aout_DecFlush( p_owner->p_aout, false );
            /* A seek/stop before the end of stream cancels the parking:
             * the output buffer has just been thrown away. */
            p_owner->b_gapless_eos = false;
            /* Sample counting is impossible after a seek: give up trimming
             * (degrades to the plain, untrimmed behaviour). */
            p_owner->b_gl_active = false;
        }
    }
    else if( p_dec->fmt_out.i_cat == VIDEO_ES )
    {
        if( p_owner->p_vout )
            vout_Flush( p_owner->p_vout, VLC_TICK_INVALID+1 );
    }
    else if( p_dec->fmt_out.i_cat == SPU_ES )
    {
        if( p_owner->p_spu_vout )
        {
            vout_thread_t *p_vout = input_resource_HoldVout( p_owner->p_resource );

            if( p_vout && p_owner->p_spu_vout == p_vout )
                vout_FlushSubpictureChannel( p_vout, p_owner->i_spu_channel );

            if( p_vout )
                vlc_object_release( p_vout );
        }
    }

    vlc_mutex_lock( &p_owner->lock );
    p_owner->i_preroll_end = INT64_MIN;
    /* The vout flush above dropped any held cache pictures and cleared
     * the hold on the vout side (see ThreadFlush); a new fill episode
     * must request it again. */
    p_owner->b_cache_hold = false;
    vlc_mutex_unlock( &p_owner->lock );
}

/**
 * The decoding main loop
 *
 * \param p_dec the decoder
 */
static void *DecoderThread( void *p_data )
{
    decoder_t *p_dec = (decoder_t *)p_data;
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    bool paused = false;

    /* The decoder's main loop */
    vlc_fifo_Lock( p_owner->p_fifo );
    vlc_fifo_CleanupPush( p_owner->p_fifo );

    for( ;; )
    {
        if( p_owner->flushing )
        {   /* Flush before/regardless of pause. We do not want to resume just
             * for the sake of flushing (glitches could otherwise happen). */
            int canc = vlc_savecancel();

            vlc_fifo_Unlock( p_owner->p_fifo );

            /* Flush the decoder (and the output) */
            DecoderProcessFlush( p_dec );

            vlc_fifo_Lock( p_owner->p_fifo );
            vlc_restorecancel( canc );

            /* Reset flushing after DecoderProcess in case input_DecoderFlush
             * is called again. This will avoid a second useless flush (but
             * harmless). */
            p_owner->flushing = false;

            continue;
        }

        if( paused != p_owner->paused )
        {   /* Update playing/paused status of the output */
            int canc = vlc_savecancel();
            vlc_tick_t date = p_owner->pause_date;

            paused = p_owner->paused;
            vlc_fifo_Unlock( p_owner->p_fifo );

            /* NOTE: Only the audio and video outputs care about pause. */
            msg_Dbg( p_dec, "toggling %s", paused ? "resume" : "pause" );
            if( p_owner->p_vout != NULL )
                vout_ChangePause( p_owner->p_vout, paused, date );
            if( p_owner->p_aout != NULL )
                aout_DecChangePause( p_owner->p_aout, paused, date );

            vlc_restorecancel( canc );
            vlc_fifo_Lock( p_owner->p_fifo );
            continue;
        }

        if( p_owner->paused && p_owner->frames_countdown == 0 )
        {
            /* Look-ahead decode cache: a pause is a free opportunity to
             * decode ahead -- keep filling the cache up to its full
             * target instead of idling. The pictures decoded here carry
             * frozen-clock dates, like any picture decoded just before
             * the pause: the vout already re-bases the whole decoder
             * fifo by the pause duration on resume (ThreadChangePause),
             * so they come out correctly timed. */
            bool b_pause_fill = false;
            if( p_owner->i_cache_bytes > 0
             && !vlc_fifo_IsEmpty( p_owner->p_fifo ) )
            {
                /* DecoderVideoCacheTarget needs the owner lock, which
                 * nests OUTSIDE the fifo lock everywhere else: drop and
                 * re-take. */
                vlc_fifo_Unlock( p_owner->p_fifo );
                vlc_mutex_lock( &p_owner->lock );
                vout_thread_t *p_vout = p_owner->p_vout;
                b_pause_fill = p_vout != NULL
                    && vout_GetDecoderFifoCount( p_vout )
                       < DecoderVideoCacheTarget( p_dec );
                vlc_mutex_unlock( &p_owner->lock );
                vlc_fifo_Lock( p_owner->p_fifo );
                /* State may have moved while unlocked (flush, resume):
                 * re-run the loop checks instead of trusting it. */
                if( p_owner->flushing || !p_owner->paused )
                    continue;
            }
            if( !b_pause_fill )
            {   /* Wait for resumption from pause */
                p_owner->b_idle = true;
                vlc_cond_signal( &p_owner->wait_acknowledge );
                vlc_fifo_Wait( p_owner->p_fifo );
                p_owner->b_idle = false;
                continue;
            }
            /* else fall through: dequeue and decode one block while
             * paused, then come back here for the next re-check */
        }

        /* Look-ahead cache: cushion at target -- throttle HERE, in the
         * decoder loop where flushing/paused/kill are re-checked every
         * wakeup, NEVER by letting the decode sink into
         * picture_pool_Wait inside the codec. A decoder faster than
         * the display (MPEG-2 DVD on a G4) used to top the target then
         * pile pool-backed pictures until picture_pool_Wait blocked it
         * INSIDE avcodec for as long as the vout took to drain back to
         * a pool picture -- minutes behind a deep cushion, deaf
         * to everything. A dvdnav WAIT/STILL reset arriving meanwhile
         * could never be flushed: the fifo kept its stale-epoch
         * pictures, the unheld vout dribble-dropped them and the fill
         * gate hung on a descending percentage for the whole drain
         * (observed live: 90%..0% over minutes on the Chihiro title,
         * RAM ballooning from the unpaced demux all along). */
        if( p_owner->i_cache_bytes > 0 && !p_owner->flushing
         && p_owner->frames_countdown == 0
         && !vlc_fifo_IsEmpty( p_owner->p_fifo ) )
        {
            size_t i_target = 0, i_count = 0;
            bool b_waiting = false;
            vlc_fifo_Unlock( p_owner->p_fifo );
            vlc_mutex_lock( &p_owner->lock );
            vout_thread_t *p_vout_full = p_owner->p_vout;
            if( p_vout_full != NULL )
            {
                i_target = DecoderVideoCacheTarget( p_dec );
                i_count  = vout_GetDecoderFifoCount( p_vout_full );
            }
            b_waiting = p_owner->b_waiting;
            vlc_mutex_unlock( &p_owner->lock );
            vlc_fifo_Lock( p_owner->p_fifo );
            if( p_owner->flushing )
                continue;
            if( i_target > 0 && i_count >= i_target )
            {
                /* Cushion full. Poll every 100 ms: nothing signals the
                 * fifo when the vout drains a picture, and flush/delete
                 * signal wait_timed (same pattern as DecoderTimedWait). */
                p_owner->i_cache_pace_mark = 0; /* controller restart */
                p_owner->b_idle = true;
                vlc_cond_signal( &p_owner->wait_acknowledge );
                vlc_fifo_TimedWaitCond( p_owner->p_fifo,
                                        &p_owner->wait_timed,
                                        mdate() + CLOCK_FREQ / 10 );
                p_owner->b_idle = false;
                continue;
            }
            if( i_target > 0 && !b_waiting )
            {
                /* Adaptive paced refill (round 87b, see the PACE defines
                 * above): steady playback with the cushion below target.
                 * Yield between decoded pictures, with the yield servoed
                 * on the measured cushion slope, then fall through to
                 * decode exactly ONE picture and re-pace. Safe to raise
                 * b_idle here: the fifo is non-empty (guarded above and
                 * only drained by this thread), so the empty+idle
                 * starve/drain checks never trip. */
                const vlc_tick_t now = mdate();
                if( p_owner->i_cache_pace_mark == 0 )
                {
                    p_owner->i_cache_pace_mark = now;
                    p_owner->i_cache_pace_count = i_count;
                }
                else if( now - p_owner->i_cache_pace_mark
                         >= VIDEO_CACHE_PACE_INTERVAL )
                {
                    /* Cushion growth since the previous mark (negative
                     * = draining). */
                    ssize_t i_slope = (ssize_t)i_count
                                    - (ssize_t)p_owner->i_cache_pace_count;
                    if( i_slope < VIDEO_CACHE_PACE_SLOPE_MIN )
                    {
                        if( p_owner->i_cache_pace_yield
                            > VIDEO_CACHE_PACE_STEP )
                            p_owner->i_cache_pace_yield
                                -= VIDEO_CACHE_PACE_STEP;
                        else
                            p_owner->i_cache_pace_yield = 0;
                    }
                    else if( i_slope > VIDEO_CACHE_PACE_SLOPE_MAX
                          && p_owner->i_cache_pace_yield
                             < VIDEO_CACHE_PACE_MAX )
                        p_owner->i_cache_pace_yield
                            += VIDEO_CACHE_PACE_STEP / 2;
                    p_owner->i_cache_pace_mark = now;
                    p_owner->i_cache_pace_count = i_count;
                }
                /* Proportional term: scale the yield by cushion fullness
                 * so a sudden drain is countered faster than the
                 * controller interval (near-empty => near flat-out). */
                vlc_tick_t i_yield = p_owner->i_cache_pace_yield
                                   * (vlc_tick_t)i_count
                                   / (vlc_tick_t)i_target;
                if( i_yield > 0 )
                {
                    p_owner->b_idle = true;
                    vlc_cond_signal( &p_owner->wait_acknowledge );
                    vlc_fifo_TimedWaitCond( p_owner->p_fifo,
                                            &p_owner->wait_timed,
                                            now + i_yield );
                    p_owner->b_idle = false;
                    if( p_owner->flushing )
                        continue;
                }
                /* fall through: decode one picture, then re-check */
            }
            else if( i_target > 0 )
                p_owner->i_cache_pace_mark = 0; /* b_waiting: flat-out */
        }

        vlc_cond_signal( &p_owner->wait_fifo );
        vlc_testcancel(); /* forced expedited cancellation in case of stop */

        block_t *p_block = vlc_fifo_DequeueUnlocked( p_owner->p_fifo );
        if( p_block == NULL )
        {
            if( likely(!p_owner->b_draining) )
            {   /* Wait for a block to decode (or a request to drain) */
                p_owner->b_idle = true;
                vlc_cond_signal( &p_owner->wait_acknowledge );
                vlc_fifo_Wait( p_owner->p_fifo );
                p_owner->b_idle = false;
                continue;
            }
            /* We have emptied the FIFO and there is a pending request to
             * drain. Pass p_block = NULL to decoder just once. */
        }

        vlc_fifo_Unlock( p_owner->p_fifo );

        int canc = vlc_savecancel();
        DecoderProcess( p_dec, p_block );

        if( p_block == NULL )
        {   /* Draining: the decoder is drained and all decoded buffers are
             * queued to the output at this point. Now drain the output. */
            if( p_owner->p_aout != NULL )
            {
                if( p_owner->b_gapless_eos )
                {   /* Gapless: do not wait for playback, the queued audio
                     * keeps playing while the next input is being set up. */
                    aout_DecDrainAsync( p_owner->p_aout );
                    p_owner->b_gapless_drained = true;
                }
                else
                    aout_DecFlush( p_owner->p_aout, true );
            }
        }
        vlc_restorecancel( canc );

        /* TODO? Wait for draining instead of polling. */
        vlc_mutex_lock( &p_owner->lock );
        if( p_owner->b_draining && (p_block == NULL) )
        {
            p_owner->b_draining = false;
            p_owner->drained = true;
        }
        vlc_fifo_Lock( p_owner->p_fifo );
        vlc_cond_signal( &p_owner->wait_acknowledge );
        vlc_mutex_unlock( &p_owner->lock );
    }
    vlc_cleanup_pop();
    vlc_assert_unreachable();
}

/**
 * Create a decoder object
 *
 * \param p_input the input thread
 * \param p_es the es descriptor
 * \param b_packetizer instead of a decoder
 * \return the decoder object
 */
static decoder_t * CreateDecoder( vlc_object_t *p_parent,
                                  input_thread_t *p_input,
                                  const es_format_t *fmt,
                                  input_resource_t *p_resource,
                                  sout_instance_t *p_sout )
{
    decoder_t *p_dec;
    decoder_owner_sys_t *p_owner;

    p_dec = vlc_custom_create( p_parent, sizeof( *p_dec ), "decoder" );
    if( p_dec == NULL )
        return NULL;

    /* Allocate our private structure for the decoder */
    p_dec->p_owner = p_owner = malloc( sizeof( decoder_owner_sys_t ) );
    if( unlikely(p_owner == NULL) )
    {
        vlc_object_release( p_dec );
        return NULL;
    }
    p_owner->i_preroll_end = INT64_MIN;
    p_owner->i_last_rate = INPUT_RATE_DEFAULT;
    p_owner->p_input = p_input;
    p_owner->p_resource = p_resource;
    p_owner->p_aout = NULL;
    p_owner->p_vout = NULL;
    p_owner->p_spu_vout = NULL;
    p_owner->i_spu_channel = 0;
    p_owner->i_spu_order = 0;
    p_owner->p_sout = p_sout;
    p_owner->p_sout_input = NULL;
    p_owner->p_packetizer = NULL;

    p_owner->b_fmt_description = false;
    p_owner->p_description = NULL;

    p_owner->paused = false;
    p_owner->pause_date = VLC_TICK_INVALID;
    p_owner->frames_countdown = 0;

    p_owner->b_waiting = false;
    p_owner->b_first = true;
    p_owner->b_has_data = false;

    p_owner->error = false;

    p_owner->flushing = false;
    p_owner->b_draining = false;
    p_owner->drained = false;
    p_owner->b_gapless_eos = false;
    p_owner->b_gapless_drained = false;
    p_owner->i_gl_count = 0;
    p_owner->i_gl_end = 0;
    p_owner->i_gl_priming = 0;
    p_owner->b_gl_active = false;
    p_owner->b_gl_init = false;
    atomic_init( &p_owner->reload, RELOAD_NO_REQUEST );
    p_owner->b_idle = false;

    p_owner->i_cache_bytes = 0;
    p_owner->i_cache_max_seconds = 0;
    p_owner->i_cache_pic_bytes = 0;
    p_owner->b_cache_hold = false;
    p_owner->i_cache_pace_yield = VIDEO_CACHE_PACE_INIT;
    p_owner->i_cache_pace_mark = 0;
    p_owner->i_cache_pace_count = 0;
    if( fmt->i_cat == VIDEO_ES && p_sout == NULL && p_input != NULL )
    {
        /* No per-URI disc blacklist here anymore: menu-capable disc
         * demuxers now declare their menu domains themselves through
         * ES_OUT_SET_VIDEO_CACHE_INHIBIT (dvdnav per domain, bluray for
         * the whole session), so TITLE playback gets the cache -- slow
         * machines genuinely need it for MPEG-2 (iBook G3) -- while
         * menus never open fill episodes. */
        int64_t i_cache_mb = var_InheritInteger( p_dec, "video-cache-mb" );
        if( i_cache_mb > 0 )
            p_owner->i_cache_bytes = (size_t)i_cache_mb * 1024 * 1024;
        int64_t i_max_s =
            var_InheritInteger( p_dec, "video-cache-max-seconds" );
        if( i_max_s > 0 )
            p_owner->i_cache_max_seconds = (unsigned)i_max_s;
    }

    es_format_Init( &p_owner->fmt, fmt->i_cat, 0 );

    /* decoder fifo */
    p_owner->p_fifo = block_FifoNew();
    if( unlikely(p_owner->p_fifo == NULL) )
    {
        free( p_owner );
        vlc_object_release( p_dec );
        return NULL;
    }

    vlc_mutex_init( &p_owner->lock );
    vlc_cond_init( &p_owner->wait_request );
    vlc_cond_init( &p_owner->wait_acknowledge );
    vlc_cond_init( &p_owner->wait_fifo );
    vlc_cond_init( &p_owner->wait_timed );

    /* Set buffers allocation callbacks for the decoders */
    p_dec->pf_aout_format_update = aout_update_format;
    p_dec->pf_vout_format_update = vout_update_format;
    p_dec->pf_vout_buffer_new = vout_new_buffer;
    p_dec->pf_spu_buffer_new  = spu_new_buffer;
    /* */
    p_dec->pf_get_attachments  = DecoderGetInputAttachments;
    p_dec->pf_get_display_date = DecoderGetDisplayDate;
    p_dec->pf_get_display_rate = DecoderGetDisplayRate;

    /* Load a packetizer module if the input is not already packetized */
    if( p_sout == NULL && !fmt->b_packetized )
    {
        p_owner->p_packetizer =
            vlc_custom_create( p_parent, sizeof( decoder_t ), "packetizer" );
        if( p_owner->p_packetizer )
        {
            if( LoadDecoder( p_owner->p_packetizer, true, fmt ) )
            {
                vlc_object_release( p_owner->p_packetizer );
                p_owner->p_packetizer = NULL;
            }
            else
            {
                p_owner->p_packetizer->fmt_out.b_packetized = true;
                fmt = &p_owner->p_packetizer->fmt_out;
            }
        }
    }

    /* Find a suitable decoder/packetizer module */
    if( LoadDecoder( p_dec, p_sout != NULL, fmt ) )
        return p_dec;

    switch( p_dec->fmt_out.i_cat )
    {
        case VIDEO_ES:
            p_dec->pf_queue_video = DecoderQueueVideo;
            p_dec->pf_queue_cc = DecoderQueueCc;
            p_owner->pf_update_stat = DecoderUpdateStatVideo;
            break;
        case AUDIO_ES:
            p_dec->pf_queue_audio = DecoderQueueAudio;
            p_owner->pf_update_stat = DecoderUpdateStatAudio;
            break;
        case SPU_ES:
            p_dec->pf_queue_sub = DecoderQueueSpu;
            p_owner->pf_update_stat = DecoderUpdateStatSpu;
            break;
        default:
            msg_Err( p_dec, "unknown ES format" );
            UnloadDecoder( p_dec );
            return p_dec;
    }
    /* Copy ourself the input replay gain */
    if( fmt->i_cat == AUDIO_ES )
    {
        for( unsigned i = 0; i < AUDIO_REPLAY_GAIN_MAX; i++ )
        {
            if( !p_dec->fmt_out.audio_replay_gain.pb_peak[i] )
            {
                p_dec->fmt_out.audio_replay_gain.pb_peak[i] = fmt->audio_replay_gain.pb_peak[i];
                p_dec->fmt_out.audio_replay_gain.pf_peak[i] = fmt->audio_replay_gain.pf_peak[i];
            }
            if( !p_dec->fmt_out.audio_replay_gain.pb_gain[i] )
            {
                p_dec->fmt_out.audio_replay_gain.pb_gain[i] = fmt->audio_replay_gain.pb_gain[i];
                p_dec->fmt_out.audio_replay_gain.pf_gain[i] = fmt->audio_replay_gain.pf_gain[i];
            }
        }
    }

    /* */
    p_owner->cc.b_supported = ( p_sout == NULL );

    p_owner->cc.desc.i_608_channels = 0;
    p_owner->cc.desc.i_708_channels = 0;
    for( unsigned i = 0; i < MAX_CC_DECODERS; i++ )
        p_owner->cc.pp_decoder[i] = NULL;
    p_owner->i_ts_delay = 0;
    return p_dec;
}

/**
 * Destroys a decoder object
 *
 * \param p_dec the decoder object
 * \return nothing
 */
static void DeleteDecoder( decoder_t * p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    msg_Dbg( p_dec, "killing decoder fourcc `%4.4s'",
             (char*)&p_dec->fmt_in.i_codec );

    if( p_owner->i_gl_count != 0 )
        msg_Dbg( p_dec, "gapless trim: %"PRIu64" samples seen",
                 p_owner->i_gl_count );

    const bool b_flush_spu = p_dec->fmt_out.i_cat == SPU_ES;
    UnloadDecoder( p_dec );

    /* Free all packets still in the decoder fifo. */
    block_FifoRelease( p_owner->p_fifo );

    /* Cleanup */
    if( p_owner->p_aout )
    {
        if( p_owner->b_gapless_drained )
        {   /* Gapless: keep the output stream alive with its queued audio,
             * the next track will adopt it. No flush, no teardown. */
            aout_DecPark( p_owner->p_aout );
        }
        else
        {
            aout_DecFlush( p_owner->p_aout, false );
            aout_DecDelete( p_owner->p_aout );
        }
        input_resource_PutAout( p_owner->p_resource, p_owner->p_aout );
        if( p_owner->p_input != NULL )
            input_SendEventAout( p_owner->p_input );
    }
    if( p_owner->p_vout )
    {
        /* Reset the cancel state that was set before joining the decoder
         * thread */
        vout_Cancel( p_owner->p_vout, false );

        input_resource_RequestVout( p_owner->p_resource, p_owner->p_vout, NULL,
                                    0, true );
        if( p_owner->p_input != NULL )
            input_SendEventVout( p_owner->p_input );
    }

#ifdef ENABLE_SOUT
    if( p_owner->p_sout_input )
    {
        sout_InputDelete( p_owner->p_sout_input );
    }
#endif
    es_format_Clean( &p_owner->fmt );

    if( b_flush_spu )
    {
        vout_thread_t *p_vout = input_resource_HoldVout( p_owner->p_resource );
        if( p_vout )
        {
            if( p_owner->p_spu_vout == p_vout )
                vout_FlushSubpictureChannel( p_vout, p_owner->i_spu_channel );
            vlc_object_release( p_vout );
        }
    }

    if( p_owner->p_description )
        vlc_meta_Delete( p_owner->p_description );

    if( p_owner->p_packetizer )
    {
        UnloadDecoder( p_owner->p_packetizer );
        vlc_object_release( p_owner->p_packetizer );
    }

    vlc_cond_destroy( &p_owner->wait_timed );
    vlc_cond_destroy( &p_owner->wait_fifo );
    vlc_cond_destroy( &p_owner->wait_acknowledge );
    vlc_cond_destroy( &p_owner->wait_request );
    vlc_mutex_destroy( &p_owner->lock );

    vlc_object_release( p_dec );

    free( p_owner );
}

/* */
static void DecoderUnsupportedCodec( decoder_t *p_dec, const es_format_t *fmt, bool b_decoding )
{
    if (fmt->i_codec != VLC_CODEC_UNKNOWN && fmt->i_codec) {
        const char *desc = vlc_fourcc_GetDescription(fmt->i_cat, fmt->i_codec);
        if (!desc || !*desc)
            desc = N_("No description for this codec");
        msg_Err( p_dec, "Codec `%4.4s' (%s) is not supported.", (char*)&fmt->i_codec, desc );
        vlc_dialog_display_error( p_dec, _("Codec not supported"),
            _("VLC could not decode the format \"%4.4s\" (%s)"),
            (char*)&fmt->i_codec, desc );
    } else if( b_decoding ){
        msg_Err( p_dec, "could not identify codec" );
        vlc_dialog_display_error( p_dec, _("Unidentified codec"),
            _("VLC could not identify the audio or video codec" ) );
    }
}

/* TODO: pass p_sout through p_resource? -- Courmisch */
static decoder_t *decoder_New( vlc_object_t *p_parent, input_thread_t *p_input,
                               const es_format_t *fmt, input_clock_t *p_clock,
                               input_resource_t *p_resource,
                               sout_instance_t *p_sout  )
{
    decoder_t *p_dec = NULL;
    const char *psz_type = p_sout ? N_("packetizer") : N_("decoder");
    int i_priority;

    /* Create the decoder configuration structure */
    p_dec = CreateDecoder( p_parent, p_input, fmt, p_resource, p_sout );
    if( p_dec == NULL )
    {
        msg_Err( p_parent, "could not create %s", psz_type );
        vlc_dialog_display_error( p_parent, _("Streaming / Transcoding failed"),
            _("VLC could not open the %s module."), vlc_gettext( psz_type ) );
        return NULL;
    }

    if( !p_dec->p_module )
    {
        DecoderUnsupportedCodec( p_dec, fmt, !p_sout );

        DeleteDecoder( p_dec );
        return NULL;
    }

    p_dec->p_owner->p_clock = p_clock;
    assert( p_dec->fmt_out.i_cat != UNKNOWN_ES );

    if( p_dec->fmt_out.i_cat == AUDIO_ES )
        i_priority = VLC_THREAD_PRIORITY_AUDIO;
    else
        i_priority = VLC_THREAD_PRIORITY_VIDEO;

    /* Spawn the decoder thread */
    if( vlc_clone( &p_dec->p_owner->thread, DecoderThread, p_dec, i_priority ) )
    {
        msg_Err( p_dec, "cannot spawn decoder thread" );
        DeleteDecoder( p_dec );
        return NULL;
    }

    return p_dec;
}


/**
 * Spawns a new decoder thread from the input thread
 *
 * \param p_input the input thread
 * \param p_es the es descriptor
 * \return the spawned decoder object
 */
decoder_t *input_DecoderNew( input_thread_t *p_input,
                             es_format_t *fmt, input_clock_t *p_clock,
                             sout_instance_t *p_sout  )
{
    return decoder_New( VLC_OBJECT(p_input), p_input, fmt, p_clock,
                        input_priv(p_input)->p_resource, p_sout );
}

/**
 * Spawn a decoder thread outside of the input thread.
 */
decoder_t *input_DecoderCreate( vlc_object_t *p_parent, const es_format_t *fmt,
                                input_resource_t *p_resource )
{
    return decoder_New( p_parent, NULL, fmt, NULL, p_resource, NULL );
}


/**
 * Kills a decoder thread and waits until it's finished
 *
 * \param p_input the input thread
 * \param p_es the es descriptor
 * \return nothing
 */
void input_DecoderDelete( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_cancel( p_owner->thread );

    vlc_fifo_Lock( p_owner->p_fifo );
    /* Signal DecoderTimedWait */
    p_owner->flushing = true;
    vlc_cond_signal( &p_owner->wait_timed );
    vlc_fifo_Unlock( p_owner->p_fifo );

    /* Make sure we aren't waiting/decoding anymore */
    vlc_mutex_lock( &p_owner->lock );
    p_owner->b_waiting = false;
    vlc_cond_signal( &p_owner->wait_request );

    /* If the video output is paused or slow, or if the picture pool size was
     * under-estimated (e.g. greedy video filter, buggy decoder...), the
     * the picture pool may be empty, and the decoder thread or any decoder
     * module worker threads may be stuck waiting for free picture buffers.
     *
     * This unblocks the thread, allowing the decoder module to join all its
     * worker threads (if any) and the decoder thread to terminate. */
    if( p_owner->p_vout != NULL )
        vout_Cancel( p_owner->p_vout, true );
    vlc_mutex_unlock( &p_owner->lock );

    vlc_join( p_owner->thread, NULL );

    /* */
    if( p_dec->p_owner->cc.b_supported )
    {
        for( int i = 0; i < MAX_CC_DECODERS; i++ )
            input_DecoderSetCcState( p_dec, VLC_CODEC_CEA608, i, false );
    }

    /* Delete decoder */
    DeleteDecoder( p_dec );
}

/**
 * Put a block_t in the decoder's fifo.
 * Thread-safe w.r.t. the decoder. May be a cancellation point.
 *
 * \param p_dec the decoder object
 * \param p_block the data block
 */
void input_DecoderDecode( decoder_t *p_dec, block_t *p_block, bool b_do_pace )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_fifo_Lock( p_owner->p_fifo );
    if( !b_do_pace )
    {
        /* FIXME: ideally we would check the time amount of data
         * in the FIFO instead of its size. */
        /* 400 MiB, i.e. ~ 50mb/s for 60s */
        if( vlc_fifo_GetBytes( p_owner->p_fifo ) > 400*1024*1024 )
        {
            msg_Warn( p_dec, "decoder/packetizer fifo full (data not "
                      "consumed quickly enough), resetting fifo!" );
            block_ChainRelease( vlc_fifo_DequeueAllUnlocked( p_owner->p_fifo ) );
            p_block->i_flags |= BLOCK_FLAG_DISCONTINUITY;
        }
    }
    else
    if( !p_owner->b_waiting )
    {   /* The FIFO is not consumed when waiting, so pacing would deadlock VLC.
         * Locking is not necessary as b_waiting is only read, not written by
         * the decoder thread. */
        while( vlc_fifo_GetCount( p_owner->p_fifo ) >= 10 )
            vlc_fifo_WaitCond( p_owner->p_fifo, &p_owner->wait_fifo );
    }

    vlc_fifo_QueueUnlocked( p_owner->p_fifo, p_block );
    vlc_fifo_Unlock( p_owner->p_fifo );
}

bool input_DecoderIsEmpty( decoder_t * p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    assert( !p_owner->b_waiting );

    vlc_fifo_Lock( p_owner->p_fifo );
    if( !vlc_fifo_IsEmpty( p_dec->p_owner->p_fifo ) || p_owner->b_draining )
    {
        vlc_fifo_Unlock( p_owner->p_fifo );
        return false;
    }
    vlc_fifo_Unlock( p_owner->p_fifo );

    bool b_empty;

    vlc_mutex_lock( &p_owner->lock );
#ifdef ENABLE_SOUT
    if( p_owner->p_sout_input != NULL )
        b_empty = sout_InputIsEmpty( p_owner->p_sout_input );
    else
#endif
    if( p_owner->fmt.i_cat == VIDEO_ES && p_owner->p_vout != NULL )
        b_empty = vout_IsEmpty( p_owner->p_vout );
    else if( p_owner->fmt.i_cat == AUDIO_ES )
        b_empty = !p_owner->b_draining || p_owner->drained;
    else
        b_empty = true; /* TODO subtitles support */
    vlc_mutex_unlock( &p_owner->lock );

    return b_empty;
}

/**
 * Signals that there are no further blocks to decode, and requests that the
 * decoder drain all pending buffers. This is used to ensure that all
 * intermediate buffers empty and no samples get lost at the end of the stream.
 *
 * @note The function does not actually wait for draining. It just signals that
 * draining should be performed once the decoder has emptied FIFO.
 */
void input_DecoderDrain( decoder_t *p_dec, bool b_gapless )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_fifo_Lock( p_owner->p_fifo );
    /* Only the first drain request decides whether the output stream may be
     * parked: the later call from EsOutDel (which always passes false) must
     * not clear the flag set at end of stream. */
    if( !p_owner->b_draining && !atomic_load( &p_owner->drained ) )
        p_owner->b_gapless_eos = b_gapless
                              && p_dec->fmt_out.i_cat == AUDIO_ES;
    p_owner->b_draining = true;
    vlc_fifo_Signal( p_owner->p_fifo );
    vlc_fifo_Unlock( p_owner->p_fifo );
}

/**
 * Requests that the decoder immediately discard all pending buffers.
 * This is useful when seeking or when deselecting a stream.
 */
void input_DecoderFlush( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_fifo_Lock( p_owner->p_fifo );

    /* Empty the fifo */
    block_ChainRelease( vlc_fifo_DequeueAllUnlocked( p_owner->p_fifo ) );

    /* Don't need to wait for the DecoderThread to flush. Indeed, if called a
     * second time, this function will clear the FIFO again before anything was
     * dequeued by DecoderThread and there is no need to flush a second time in
     * a row. */
    p_owner->flushing = true;

    /* Flush video/spu decoder when paused: increment frames_countdown in order
     * to display one frame/subtitle */
    if( p_owner->paused
     && ( p_owner->fmt.i_cat == VIDEO_ES || p_owner->fmt.i_cat == SPU_ES )
     && p_owner->frames_countdown == 0 )
        p_owner->frames_countdown++;

    vlc_fifo_Signal( p_owner->p_fifo );
    vlc_cond_signal( &p_owner->wait_timed );

    vlc_fifo_Unlock( p_owner->p_fifo );
}

void input_DecoderGetCcDesc( decoder_t *p_dec, decoder_cc_desc_t *p_desc )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_mutex_lock( &p_owner->lock );
    *p_desc = p_owner->cc.desc;
    vlc_mutex_unlock( &p_owner->lock );
}

static bool input_DecoderHasCCChanFlag( decoder_t *p_dec,
                                        vlc_fourcc_t codec, int i_channel )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    int i_max_channels;
    uint64_t i_bitmap;
    if( codec == VLC_CODEC_CEA608 )
    {
        i_max_channels = 4;
        i_bitmap = p_owner->cc.desc.i_608_channels;
    }
    else if( codec == VLC_CODEC_CEA708 )
    {
        i_max_channels = 64;
        i_bitmap = p_owner->cc.desc.i_708_channels;
    }
    else return false;

    return ( i_channel >= 0 && i_channel < i_max_channels &&
             ( i_bitmap & ((uint64_t)1 << i_channel) ) );
}

int input_DecoderSetCcState( decoder_t *p_dec, vlc_fourcc_t codec,
                             int i_channel, bool b_decode )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    //msg_Warn( p_dec, "input_DecoderSetCcState: %d @%x", b_decode, i_channel );

    if( !input_DecoderHasCCChanFlag( p_dec, codec, i_channel ) )
        return VLC_EGENERIC;

    if( b_decode )
    {
        decoder_t *p_cc;
        es_format_t fmt;

        es_format_Init( &fmt, SPU_ES, codec );
        fmt.subs.cc.i_channel = i_channel;
        fmt.subs.cc.i_reorder_depth = p_owner->cc.desc.i_reorder_depth;
        p_cc = input_DecoderNew( p_owner->p_input, &fmt,
                              p_dec->p_owner->p_clock, p_owner->p_sout );
        if( !p_cc )
        {
            msg_Err( p_dec, "could not create decoder" );
            vlc_dialog_display_error( p_dec,
                _("Streaming / Transcoding failed"), "%s",
                _("VLC could not open the decoder module.") );
            return VLC_EGENERIC;
        }
        else if( !p_cc->p_module )
        {
            DecoderUnsupportedCodec( p_dec, &fmt, true );
            input_DecoderDelete(p_cc);
            return VLC_EGENERIC;
        }
        p_cc->p_owner->p_clock = p_owner->p_clock;

        vlc_mutex_lock( &p_owner->lock );
        p_owner->cc.pp_decoder[i_channel] = p_cc;
        vlc_mutex_unlock( &p_owner->lock );
    }
    else
    {
        decoder_t *p_cc;

        vlc_mutex_lock( &p_owner->lock );
        p_cc = p_owner->cc.pp_decoder[i_channel];
        p_owner->cc.pp_decoder[i_channel] = NULL;
        vlc_mutex_unlock( &p_owner->lock );

        if( p_cc )
            input_DecoderDelete(p_cc);
    }
    return VLC_SUCCESS;
}

int input_DecoderGetCcState( decoder_t *p_dec, vlc_fourcc_t codec,
                             int i_channel, bool *pb_decode )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    if( !input_DecoderHasCCChanFlag( p_dec, codec, i_channel ) )
        return VLC_EGENERIC;

    vlc_mutex_lock( &p_owner->lock );
    *pb_decode = p_owner->cc.pp_decoder[i_channel] != NULL;
    vlc_mutex_unlock( &p_owner->lock );
    return VLC_SUCCESS;
}

void input_DecoderChangePause( decoder_t *p_dec, bool b_paused, vlc_tick_t i_date )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    /* Normally, p_owner->b_paused != b_paused here. But if a track is added
     * while the input is paused (e.g. add sub file), then b_paused is
     * (incorrectly) false. FIXME: This is a bug in the decoder owner. */
    vlc_fifo_Lock( p_owner->p_fifo );
    p_owner->paused = b_paused;
    p_owner->pause_date = i_date;
    p_owner->frames_countdown = 0;
    vlc_fifo_Signal( p_owner->p_fifo );
    vlc_fifo_Unlock( p_owner->p_fifo );
}

void input_DecoderChangeDelay( decoder_t *p_dec, vlc_tick_t i_delay )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_mutex_lock( &p_owner->lock );
    p_owner->i_ts_delay = i_delay;
    vlc_mutex_unlock( &p_owner->lock );
}

void input_DecoderStartWait( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    assert( !p_owner->b_waiting );

    vlc_mutex_lock( &p_owner->lock );
    p_owner->b_first = true;
    p_owner->b_has_data = false;
    p_owner->b_waiting = true;
    vlc_cond_signal( &p_owner->wait_request );
    vlc_mutex_unlock( &p_owner->lock );
}

void input_DecoderStopWait( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    assert( p_owner->b_waiting );

    vlc_mutex_lock( &p_owner->lock );
    p_owner->b_waiting = false;
    if( p_owner->b_cache_hold && p_owner->p_vout != NULL )
        /* Authoritative end-of-episode unhold. Queued AFTER b_waiting
         * went false under this lock: any in-flight fill picture either
         * ran before us (its hold(true) precedes this false in the vout
         * control queue) or after (b_waiting false, no hold at all), so
         * the unhold always lands last and the vout can never stay
         * wedged held with the gate open. es_out's release only
         * re-bases dates/flushes the OSD; the unhold lives here. */
        vout_ChangeCacheHold( p_owner->p_vout, false );
    p_owner->b_cache_hold = false;
    vlc_cond_signal( &p_owner->wait_request );
    vlc_mutex_unlock( &p_owner->lock );
}

/* Look-ahead decode cache: reports how full this (video) decoder's vout
 * fifo is against the effective target, so es_out's fill gate and the
 * decoder's own fill loop share one truth (see DecoderVideoCacheTarget).
 * *pb_starved is true when the decoder cannot make further progress (its
 * input fifo is empty and it is idle) -- at demux EOF that is the signal
 * to stop waiting for the cache. Returns false when the feature is off
 * for this decoder. */
bool input_DecoderGetCacheState( decoder_t *p_dec, size_t *pi_count,
                                 size_t *pi_target, size_t *pi_bytes,
                                 bool *pb_starved )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    if( p_owner->i_cache_bytes == 0 )
        return false;

    vlc_mutex_lock( &p_owner->lock );
    *pi_target = DecoderVideoCacheTarget( p_dec );
    *pi_count = p_owner->p_vout != NULL
              ? vout_GetDecoderFifoCount( p_owner->p_vout ) : 0;
    if( pi_bytes != NULL )
        /* Every cached picture has the format the first measured picture
         * had. */
        *pi_bytes = *pi_count * p_owner->i_cache_pic_bytes;
    vlc_mutex_unlock( &p_owner->lock );

    if( pb_starved != NULL )
    {
        vlc_fifo_Lock( p_owner->p_fifo );
        *pb_starved = vlc_fifo_IsEmpty( p_owner->p_fifo )
                   && p_owner->b_idle;
        vlc_fifo_Unlock( p_owner->p_fifo );
    }

    return true;
}

/* Whether the decoder has produced a picture and is parked on the
 * buffering gate (b_has_data): with an unmeasurable picture size
 * (opaque hardware pictures, target stuck at 0) this is the signal
 * that nothing will ever accumulate -- the parked decoder holds its
 * next picture in hand -- so the fill gate must open right away. */
bool input_DecoderIsReadyWaiting( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    bool b_ready;

    vlc_mutex_lock( &p_owner->lock );
    b_ready = p_owner->b_waiting && p_owner->b_has_data;
    vlc_mutex_unlock( &p_owner->lock );
    return b_ready;
}

void input_DecoderWait( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    assert( p_owner->b_waiting );

    /* Hard bound on the whole wait: this runs on the INPUT thread with
     * the es_out lock held -- if the decoder cannot acknowledge (e.g.
     * wedged inside its codec on some resource), waiting forever here
     * freezes every input control (stop, pause, quit, the time display)
     * with it. A decoder that has anything to give signals within
     * milliseconds; five seconds means something is already wrong, and
     * a degraded start beats a dead player. */
    const vlc_tick_t i_deadline = mdate() + 5 * CLOCK_FREQ;

    vlc_mutex_lock( &p_owner->lock );
    while( !p_owner->b_has_data )
    {
        /* Don't need to lock p_owner->paused since it's only modified by the
         * owner */
        if( p_owner->paused )
            break;
        vlc_fifo_Lock( p_owner->p_fifo );
        if( p_owner->b_idle && vlc_fifo_IsEmpty( p_owner->p_fifo ) )
        {
            msg_Err( p_dec, "buffer deadlock prevented" );
            vlc_fifo_Unlock( p_owner->p_fifo );
            break;
        }
        vlc_fifo_Unlock( p_owner->p_fifo );
        if( vlc_cond_timedwait( &p_owner->wait_acknowledge, &p_owner->lock,
                                i_deadline ) )
        {
            msg_Warn( p_dec, "decoder wait timed out, proceeding without "
                      "its acknowledgement" );
            break;
        }
    }
    vlc_mutex_unlock( &p_owner->lock );
}

void input_DecoderFrameNext( decoder_t *p_dec, vlc_tick_t *pi_duration )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    assert( p_owner->paused );
    *pi_duration = 0;

    vlc_fifo_Lock( p_owner->p_fifo );
    p_owner->frames_countdown++;
    vlc_fifo_Signal( p_owner->p_fifo );
    vlc_fifo_Unlock( p_owner->p_fifo );

    vlc_mutex_lock( &p_owner->lock );
    if( p_owner->fmt.i_cat == VIDEO_ES )
    {
        if( p_owner->p_vout )
            vout_NextPicture( p_owner->p_vout, pi_duration );
    }
    vlc_mutex_unlock( &p_owner->lock );
}

bool input_DecoderHasFormatChanged( decoder_t *p_dec, es_format_t *p_fmt, vlc_meta_t **pp_meta )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;
    bool b_changed;

    vlc_mutex_lock( &p_owner->lock );
    b_changed = p_owner->b_fmt_description;
    if( b_changed )
    {
        if( p_fmt != NULL )
            es_format_Copy( p_fmt, &p_owner->fmt );

        if( pp_meta )
        {
            *pp_meta = NULL;
            if( p_owner->p_description )
            {
                *pp_meta = vlc_meta_New();
                if( *pp_meta )
                    vlc_meta_Merge( *pp_meta, p_owner->p_description );
            }
        }
        p_owner->b_fmt_description = false;
    }
    vlc_mutex_unlock( &p_owner->lock );
    return b_changed;
}

size_t input_DecoderGetFifoSize( decoder_t *p_dec )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    return block_FifoSize( p_owner->p_fifo );
}

void input_DecoderGetObjects( decoder_t *p_dec,
                              vout_thread_t **pp_vout, audio_output_t **pp_aout )
{
    decoder_owner_sys_t *p_owner = p_dec->p_owner;

    vlc_mutex_lock( &p_owner->lock );
    if( pp_vout )
        *pp_vout = p_owner->p_vout ? vlc_object_hold( p_owner->p_vout ) : NULL;
    if( pp_aout )
        *pp_aout = p_owner->p_aout ? vlc_object_hold( p_owner->p_aout ) : NULL;
    vlc_mutex_unlock( &p_owner->lock );
}
