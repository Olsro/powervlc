/*****************************************************************************
 * record.c: record stream output module
 *****************************************************************************
 * Copyright (C) 2008-2009 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Laurent Aimar <fenrir@via.ecp.fr>
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

#include <limits.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_block.h>
#include <vlc_sout.h>
#include <vlc_fs.h>
#include <assert.h>

/*****************************************************************************
 * Exported prototypes
 *****************************************************************************/
static int      Open    ( vlc_object_t * );
static void     Close   ( vlc_object_t * );

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
#define DST_PREFIX_TEXT N_("Destination prefix")
#define DST_PREFIX_LONGTEXT N_( \
    "Prefix of the destination file automatically generated" )
#define START_TIME_TEXT N_("Preferred start bound of the capture (µs)")
#define EXPECT_STREAMS_TEXT N_("Number of elementary streams to wait for")
#define DEFAULT_SPU_TEXT N_("Mark the subtitle track as default")

#define SOUT_CFG_PREFIX "sout-record-"

vlc_module_begin ()
    set_description( N_("Record stream output") )
    set_capability( "sout stream", 0 )
    add_shortcut( "record" )
    set_shortname( N_("Record") )

    set_category( CAT_SOUT )
    set_subcategory( SUBCAT_SOUT_STREAM )

    add_string( SOUT_CFG_PREFIX "dst-prefix", "", DST_PREFIX_TEXT,
                DST_PREFIX_LONGTEXT, true )
    /* PowerVLC clip creation: preferred start bound (µs, stream time).
     * When the demuxer delivered data from before that time, the capture
     * starts at the LAST key frame at or before it instead of the first
     * key frame received -- the closest possible clip start without
     * re-encoding. 0 keeps the historic behavior. */
    add_integer( SOUT_CFG_PREFIX "start-time", 0, START_TIME_TEXT,
                 START_TIME_TEXT, true )
    /* PowerVLC: how many elementary streams the caller knows it selected.
     * See the note in Send(): the container is chosen from the streams
     * present at that instant, and a sparse one -- a subtitle -- can turn
     * up long after. 0 keeps the historic behaviour. */
    add_integer( SOUT_CFG_PREFIX "expect-streams", 0, EXPECT_STREAMS_TEXT,
                 EXPECT_STREAMS_TEXT, true )
    /* Used by clip export only: an extracted subtitle must still be enabled
     * when the resulting file is opened in another player. */
    add_bool( SOUT_CFG_PREFIX "default-spu", false, DEFAULT_SPU_TEXT,
              DEFAULT_SPU_TEXT, true )

    set_callbacks( Open, Close )
vlc_module_end ()

/* */
static const char *const ppsz_sout_options[] = {
    "dst-prefix",
    "start-time",
    "expect-streams",
    "default-spu",
    NULL
};

/* */
static sout_stream_id_sys_t *Add( sout_stream_t *, const es_format_t * );
static void              Del ( sout_stream_t *, sout_stream_id_sys_t * );
static int               Send( sout_stream_t *, sout_stream_id_sys_t *, block_t* );

/* */
struct sout_stream_id_sys_t
{
    es_format_t fmt;

    block_t *p_first;
    block_t **pp_last;

    sout_stream_id_sys_t *id;

    bool b_wait_key;
    bool b_wait_start;

    /* last tick seen on THIS stream while probing, to detect a seek */
    vlc_tick_t i_probe_last_dts;
    /* the buffer was already cut at its start frame: the start-time
     * threshold must not be applied to it a second time */
    bool b_trimmed;
};

struct sout_stream_sys_t
{
    char *psz_prefix;

    sout_stream_t *p_out;

    vlc_tick_t  i_date_start;
    size_t      i_size;

    vlc_tick_t  i_max_wait;
    size_t      i_max_size;

    bool        b_drop;

    int              i_id;
    sout_stream_id_sys_t **id;
    vlc_tick_t  i_dts_start;
    /* preferred start bound (µs, stream time base), 0 = none */
    vlc_tick_t  i_start_bound;
    /* how many streams the caller selected, 0 = it did not say */
    int         i_expect_streams;
    /* ask a capable muxer to make the sole exported subtitle selected */
    bool        b_default_spu;
};

static void OutputStart( sout_stream_t *p_stream );
static void OutputSend( sout_stream_t *p_stream, sout_stream_id_sys_t *id, block_t * );
static vlc_tick_t BlockTick( const block_t *p_block );

/*****************************************************************************
 * Open:
 *****************************************************************************/
static int Open( vlc_object_t *p_this )
{
    sout_stream_t *p_stream = (sout_stream_t*)p_this;
    sout_stream_sys_t *p_sys;

    p_stream->pf_add    = Add;
    p_stream->pf_del    = Del;
    p_stream->pf_send   = Send;

    p_stream->p_sys = p_sys = malloc( sizeof(*p_sys) );
    if( !p_sys )
        return VLC_ENOMEM;

    config_ChainParse( p_stream, SOUT_CFG_PREFIX, ppsz_sout_options, p_stream->p_cfg );

    p_sys->p_out = NULL;
    p_sys->psz_prefix = var_GetNonEmptyString( p_stream, SOUT_CFG_PREFIX "dst-prefix" );
    if( !p_sys->psz_prefix  )
    {
        p_sys->psz_prefix = strdup( "sout-record-" );
        if( !p_sys->psz_prefix )
        {
            free( p_sys );
            return VLC_ENOMEM;
        }
    }

    p_sys->i_date_start = -1;
    p_sys->i_size = 0;
#ifdef OPTIMIZE_MEMORY
    p_sys->i_max_wait = 5*CLOCK_FREQ; /* 5s */
    p_sys->i_max_size = 1*1024*1024; /* 1 MiB */
#else
    p_sys->i_max_wait = 30*CLOCK_FREQ; /* 30s */
    p_sys->i_max_size = 20*1024*1024; /* 20 MiB */
#endif
    p_sys->b_drop = false;
    p_sys->i_dts_start = 0;
    p_sys->b_default_spu = var_GetBool( p_stream,
                                        SOUT_CFG_PREFIX "default-spu" );
    p_sys->i_start_bound = var_GetInteger( p_stream,
                                           SOUT_CFG_PREFIX "start-time" );
    p_sys->i_expect_streams = var_GetInteger( p_stream,
                                          SOUT_CFG_PREFIX "expect-streams" );
    TAB_INIT( p_sys->i_id, p_sys->id );

    return VLC_SUCCESS;
}


/*****************************************************************************
 * Close:
 *****************************************************************************/
static void Close( vlc_object_t * p_this )
{
    sout_stream_t *p_stream = (sout_stream_t*)p_this;
    sout_stream_sys_t *p_sys = p_stream->p_sys;

    if( p_sys->p_out )
        sout_StreamChainDelete( p_sys->p_out, p_sys->p_out );

    TAB_CLEAN( p_sys->i_id, p_sys->id );
    free( p_sys->psz_prefix );
    free( p_sys );
}

/*****************************************************************************
 *
 *****************************************************************************/
static sout_stream_id_sys_t *Add( sout_stream_t *p_stream, const es_format_t *p_fmt )
{
    sout_stream_sys_t *p_sys = p_stream->p_sys;
    sout_stream_id_sys_t *id;

    id = malloc( sizeof(*id) );
    if( !id )
        return NULL;

    es_format_Copy( &id->fmt, p_fmt );
    id->p_first = NULL;
    id->pp_last = &id->p_first;
    id->id = NULL;
    id->b_wait_key = true;
    id->b_wait_start = true;
    id->i_probe_last_dts = 0;
    id->b_trimmed = false;

    /* Nothing can be done for it here -- the muxer has its header written
     * and takes no new stream -- but it used to vanish without a word. */
    if( p_sys->p_out != NULL )
        msg_Warn( p_stream, "stream %4.4s only appeared after the output was "
                  "opened: it cannot be recorded",
                  (char *)&p_fmt->i_codec );

    TAB_APPEND( p_sys->i_id, p_sys->id, id );

    return id;
}

static void Del( sout_stream_t *p_stream, sout_stream_id_sys_t *id )
{
    sout_stream_sys_t *p_sys = p_stream->p_sys;

    if( !p_sys->p_out )
        OutputStart( p_stream );

    if( id->p_first )
        block_ChainRelease( id->p_first );

    assert( !id->id || p_sys->p_out );
    if( id->id )
        sout_StreamIdDel( p_sys->p_out, id->id );

    es_format_Clean( &id->fmt );

    TAB_REMOVE( p_sys->i_id, p_sys->id, id );

    if( p_sys->i_id <= 0 )
    {
        if( !p_sys->p_out )
            p_sys->b_drop = false;
    }

    free( id );
}

static int Send( sout_stream_t *p_stream, sout_stream_id_sys_t *id,
                 block_t *p_buffer )
{
    sout_stream_sys_t *p_sys = p_stream->p_sys;

    /* A seek right after arming the record (clip creation jumps to the
     * clip start bound) makes the timestamps jump while we are still
     * probing: the buffered pre-seek blocks would end up muxed next to
     * post-seek ones, producing a broken file. Drop everything buffered
     * so far and re-arm the key frame waits: the post-seek stream begins
     * at the key frame the demuxer resumed from, which is exactly what
     * the clip should start with. Audio/video only: subtitle ticks are
     * legitimately sparse.
     *
     * ⚠ The reference tick is kept PER STREAM. A single shared one compares
     * the video clock against the audio clock, and an interleave offset of
     * more than the tolerance then reads as a seek on every single block:
     * measured on an MKV export, the capture restarted ~40 times in a row
     * and the clip lost its whole first GOP (2,7 s), a BluRay remux with
     * PCM 5.1 lost more. Each elementary stream is only ever compared with
     * itself now; a real seek moves them all, so seeing it on one is enough
     * to flush everything. */
    if( !p_sys->p_out &&
        ( id->fmt.i_cat == AUDIO_ES || id->fmt.i_cat == VIDEO_ES ) )
    {
        vlc_tick_t i_tick = BlockTick( p_buffer );
        if( i_tick != 0 )
        {
            if( id->i_probe_last_dts != 0 &&
                ( i_tick < id->i_probe_last_dts - 2*CLOCK_FREQ ||
                  i_tick > id->i_probe_last_dts + 2*CLOCK_FREQ ) )
            {
                msg_Dbg( p_stream, "timestamp discontinuity while probing "
                         "(%"PRId64" -> %"PRId64"): restarting capture",
                         id->i_probe_last_dts, i_tick );
                for( int i = 0; i < p_sys->i_id; i++ )
                {
                    sout_stream_id_sys_t *p_id = p_sys->id[i];
                    if( p_id->p_first )
                        block_ChainRelease( p_id->p_first );
                    p_id->p_first = NULL;
                    p_id->pp_last = &p_id->p_first;
                    p_id->b_wait_key = true;
                    p_id->b_wait_start = true;
                    /* their buffers are gone: nothing to compare against
                     * until each of them delivers again */
                    if( p_id != id )
                        p_id->i_probe_last_dts = 0;
                }
                p_sys->i_size = 0;
                p_sys->i_dts_start = 0;
                id->i_probe_last_dts = i_tick;
            }
            else if( i_tick > id->i_probe_last_dts )
                id->i_probe_last_dts = i_tick;
        }
    }

    if( p_sys->i_date_start < 0 )
        p_sys->i_date_start = mdate();

    /* ⚠⚠⚠ The container is chosen from the streams present AT THAT
     * INSTANT, and a stream that turns up afterwards is never added to it:
     * its blocks are dropped, in silence (see Add()). Subtitles are the
     * victims, being sparse by nature -- on a 26 Mbit/s BluRay remux the
     * 20 MiB probe fills in SIX SECONDS of film, long before the first
     * cue. Measured 14/08/2026 on such a remux: the ASS track announced
     * itself 37 log lines after the muxer had been settled, and simply
     * was not in the clip.
     *
     * So when the caller has told us how many streams it selected, hold
     * the SIZE trigger until they have all shown themselves. Never the
     * clock one: a live recording has to start within i_max_wait whatever
     * happens, and a subtitle track can stay silent for minutes. The wait
     * is bounded by memory too -- four probe buffers and no more. */
    const bool b_wait_streams = p_sys->i_expect_streams > p_sys->i_id
                             && p_sys->i_size < 4 * p_sys->i_max_size;

    if( !p_sys->p_out &&
        ( mdate() - p_sys->i_date_start > p_sys->i_max_wait ||
          ( p_sys->i_size > p_sys->i_max_size && !b_wait_streams ) ) )
    {
        msg_Dbg( p_stream, "Starting recording, waited %ds and %dbyte",
                 (int)((mdate() - p_sys->i_date_start)/1000000), (int)p_sys->i_size );
        OutputStart( p_stream );
    }

    OutputSend( p_stream, id, p_buffer );

    return VLC_SUCCESS;
}

/*****************************************************************************
 *
 *****************************************************************************/
typedef struct
{
    /* ⚠ These were `char [4]`, which fits "asf" and "mp4" and nothing else:
     * a longer name silently ran over into the extension field beside it
     * ("avformat{mux=matroska}" came out as "avfomkv"). That is why the
     * avformat entries below the table were commented out rather than used.
     * Pointers to literals instead -- no length to get wrong. */
    const char *psz_muxer;
    const char *psz_extension;
    int         i_es_max;
    vlc_fourcc_t codec[128];
} muxer_properties_t;

#define M(muxer, ext, count, ... ) { .psz_muxer = muxer, .psz_extension = ext, .i_es_max = count, .codec = { __VA_ARGS__, 0 } }
/* Table of native codec support,
 * Do not do non native and non standard association !
 * Muxer will be probe if no entry found */
static const muxer_properties_t p_muxers[] = {
    M( "raw", "mp3", 1,         VLC_CODEC_MPGA ),
    M( "raw", "a52", 1,         VLC_CODEC_A52 ),
    M( "raw", "dts", 1,         VLC_CODEC_DTS ),
    M( "raw", "mpc", 1,         VLC_CODEC_MUSEPACK7, VLC_CODEC_MUSEPACK8 ),
    M( "raw", "ape", 1,         VLC_CODEC_APE ),

    M( "wav", "wav", 1,         VLC_CODEC_U8,   VLC_CODEC_S16L,
                                VLC_CODEC_S24L, VLC_CODEC_S32L, VLC_CODEC_FL32 ),

    //M( "avformat{mux=flac}", "flac", 1, VLC_CODEC_FLAC ), BROKEN

    M( "ogg", "ogg", INT_MAX,   VLC_CODEC_VORBIS, VLC_CODEC_SPEEX,  VLC_CODEC_FLAC,
                                VLC_CODEC_SUBT,   VLC_CODEC_THEORA, VLC_CODEC_DIRAC,
                                VLC_CODEC_OPUS ),

    M( "asf", "asf", 127,       VLC_CODEC_WMA1, VLC_CODEC_WMA2, VLC_CODEC_WMAP, VLC_CODEC_WMAL, VLC_CODEC_WMAS,
                                VLC_CODEC_WMV1, VLC_CODEC_WMV2, VLC_CODEC_WMV3, VLC_CODEC_VC1 ),

    M( "mp4", "mp4", INT_MAX,   VLC_CODEC_MP4A, VLC_CODEC_H264, VLC_CODEC_MP4V, VLC_CODEC_HEVC,
                                VLC_CODEC_SUBT ),

    M( "ps", "mpg", 16/* FIXME*/,VLC_CODEC_MPGV,
                                VLC_CODEC_MPGA, VLC_CODEC_DVD_LPCM, VLC_CODEC_A52,
                                VLC_CODEC_DTS,
                                VLC_CODEC_SPU ),

    M( "avi", "avi", 100,       VLC_CODEC_A52, VLC_CODEC_MPGA,
                                VLC_CODEC_WMA1, VLC_CODEC_WMA2, VLC_CODEC_WMAP, VLC_CODEC_WMAL,
                                VLC_CODEC_U8, VLC_CODEC_S16L, VLC_CODEC_S24L,
                                VLC_CODEC_MP4V ),

    M( "ts", "ts", 8000,        VLC_CODEC_MPGV,
                                VLC_CODEC_H264, VLC_CODEC_HEVC,
                                VLC_CODEC_MPGA, VLC_CODEC_DVD_LPCM, VLC_CODEC_A52,
                                VLC_CODEC_DTS,  VLC_CODEC_MP4A,
                                VLC_CODEC_DVBS, VLC_CODEC_TELETEXT ),

    /* ⚠ There is NO native "mkv" muxer in VLC (modules/mux/ has asf, avi,
     * mp4, ps, ts, ogg, wav and nothing else), so the entry that used to sit
     * here could never load: it silently fell through to the brute-force
     * probe below. Matroska comes from libavformat instead -- see the
     * comment on the entry below, and contrib/src/ffmpeg/rules.mak, which
     * has to enable that one muxer.
     *
     * Last on purpose: every earlier entry is a container the rest of the
     * world expects for that particular set of streams (a recorded TV
     * channel stays .ts, an H.264/AAC film stays .mp4). Matroska is what
     * catches everything those cannot express -- which is most of what a
     * modern film actually contains.
     *
     * It is the ONLY container here that can carry the two subtitle formats
     * a stream copy otherwise has to drop on the floor: ASS/SSA styling and
     * Blu-ray PGS bitmaps. Both were silently lost from every exported clip
     * before this (measured 14/08/2026: "mp4 mux error: unsupported codec
     * ssa in mp4", then avi, ogg and asf refusing in turn). It also rescues
     * the raw PCM tracks of a BluRay remux, which used to drag the whole
     * recording down to ASF or AVI.
     *
     * ⚠ Only codecs libavformat's Matroska muxer is known to accept are
     * listed. A codec left out of this list is not lost: no entry matches,
     * and the brute-force probe below runs exactly as it did before. Adding
     * one it would REFUSE is the harmful direction -- an exact table match
     * opens the muxer once and any stream it turns down is then dropped in
     * silence. */
    M( "avformat{mux=matroska}", "mkv", 32,
                                /* video */
                                VLC_CODEC_H264, VLC_CODEC_HEVC, VLC_CODEC_MPGV,
                                VLC_CODEC_MP4V, VLC_CODEC_VP8,  VLC_CODEC_VP9,
                                VLC_CODEC_AV1,  VLC_CODEC_THEORA,
                                VLC_CODEC_MJPG, VLC_CODEC_DIRAC, VLC_CODEC_VC1,
                                VLC_CODEC_WMV1, VLC_CODEC_WMV2, VLC_CODEC_WMV3,
                                /* audio */
                                VLC_CODEC_A52,  VLC_CODEC_EAC3, VLC_CODEC_DTS,
                                VLC_CODEC_TRUEHD, VLC_CODEC_MLP,
                                VLC_CODEC_MP4A, VLC_CODEC_MPGA, VLC_CODEC_MP3,
                                VLC_CODEC_FLAC, VLC_CODEC_ALAC,
                                VLC_CODEC_VORBIS, VLC_CODEC_OPUS, VLC_CODEC_SPEEX,
                                VLC_CODEC_WAVPACK, VLC_CODEC_TTA,
                                VLC_CODEC_WMA1, VLC_CODEC_WMA2,
                                VLC_CODEC_WMAP, VLC_CODEC_WMAL,
                                VLC_CODEC_AMR_NB, VLC_CODEC_AMR_WB,
                                VLC_CODEC_U8,   VLC_CODEC_S16L, VLC_CODEC_S24L,
                                VLC_CODEC_S32L, VLC_CODEC_F32L,
                                /* subtitles -- the whole point */
                                VLC_CODEC_SUBT, VLC_CODEC_SSA, VLC_CODEC_BD_PG,
                                VLC_CODEC_SPU,  VLC_CODEC_DVBS ),
};
#undef M

static int OutputNew( sout_stream_t *p_stream,
                      const char *psz_muxer, const char *psz_prefix, const char *psz_extension  )
{
    sout_stream_sys_t *p_sys = p_stream->p_sys;
    char *psz_file = NULL, *psz_tmp = NULL;
    char *psz_output = NULL;
    char *psz_muxer_default_spu = NULL;
    int i_count;

    /* Native muxers do not expose a portable default-subtitle flag. The
     * Matroska path uses avformat, which does; add its private option only
     * for a clip export that actually contains the selected subtitle. */
    const char *psz_output_muxer = psz_muxer;
    size_t i_muxer_len = strlen( psz_muxer );
    if( p_sys->b_default_spu && i_muxer_len > 1
     && !strncmp( psz_muxer, "avformat{", 9 )
     && psz_muxer[i_muxer_len - 1] == '}' )
    {
        if( asprintf( &psz_muxer_default_spu, "%.*s,default-spu=1}",
                      (int)( i_muxer_len - 1 ), psz_muxer ) < 0 )
            goto error;
        psz_output_muxer = psz_muxer_default_spu;
    }

    if( asprintf( &psz_tmp, "%s%s%s",
                  psz_prefix, psz_extension ? "." : "", psz_extension ? psz_extension : "" ) < 0 )
    {
        psz_tmp = NULL;
        goto error;
    }

    psz_file = config_StringEscape( psz_tmp );
    if( !psz_file )
        goto error;

    if( asprintf( &psz_output,
                  "std{access=file{no-append,no-format,no-overwrite},"
                  "mux='%s',dst='%s'}", psz_output_muxer, psz_file ) < 0 )
    {
        psz_output = NULL;
        goto error;
    }

    /* Create the output */
    msg_Dbg( p_stream, "Using record output `%s'", psz_output );

    p_sys->p_out = sout_StreamChainNew( p_stream->p_sout, psz_output, NULL, NULL );

    if( !p_sys->p_out )
        goto error;

    /* Add es */
    i_count = 0;
    for( int i = 0; i < p_sys->i_id; i++ )
    {
        sout_stream_id_sys_t *id = p_sys->id[i];

        id->id = sout_StreamIdAdd( p_sys->p_out, &id->fmt );
        if( id->id )
            i_count++;
    }

    /* ⚠ What listens to "record-file" wants the PATH of the file just
     * written -- the media library adds it, the clip export matches it
     * against the prefix it asked for -- not the piece of sout syntax that
     * went into the chain. The two are the same string on Unix, which is
     * how publishing the escaped copy went unnoticed; on Windows every
     * backslash of the path comes back DOUBLED and no listener recognises
     * its own file. The clip export then announced "export failed" over a
     * clip it had just written perfectly (Windows XP, 13/08/2026). */
    if( psz_file && psz_extension )
        var_SetString( p_stream->obj.libvlc, "record-file", psz_tmp );

    free( psz_tmp );
    free( psz_file );
    free( psz_output );
    free( psz_muxer_default_spu );

    return i_count;

error:

    free( psz_tmp );
    free( psz_file );
    free( psz_output );
    free( psz_muxer_default_spu );
    return -1;

}

static vlc_tick_t BlockTick( const block_t *p_block )
{
    if( unlikely(!p_block) )
        return 0;
    else if( likely(p_block->i_dts != 0) )
        return p_block->i_dts;
    else
        return p_block->i_pts;
}

/* Does this access unit RESET the reference chain -- an H.264 IDR, an HEVC
 * IDR -- rather than merely being an I picture?
 *
 * ⚠ The distinction is the whole difference between a clean cut and two
 * wrong pictures. A plain I picture only means "coded without reference";
 * the pictures around it may still be predicted from before it, and the
 * ones that follow it commonly use TEMPORAL DIRECT mode, whose motion
 * comes from the co-located picture's OWN references. Cut in front of
 * those and the decoder has nothing to derive them from -- it says "co
 * located POCs unavailable" and guesses. Measured on an H.264 BluRay remux
 * cut at an I picture: the two B pictures right after it differ from the
 * source, every time (14/08/2026). An IDR forbids all of that by
 * definition: nothing after it may look back.
 *
 * The packetizers hand us Annex B, so the NAL type is the low five bits of
 * the byte after each start code (H.264), or bits 6-1 of the first of two
 * (HEVC). */
static bool BlockIsIDR( vlc_fourcc_t i_codec, const block_t *p_block )
{
    if( i_codec != VLC_CODEC_H264 && i_codec != VLC_CODEC_HEVC )
        return false;

    const uint8_t *p = p_block->p_buffer;
    size_t i_size = p_block->i_buffer;

    for( size_t i = 0; i + 4 < i_size; i++ )
    {
        if( p[i] != 0 || p[i+1] != 0 || p[i+2] != 1 )
            continue;

        const uint8_t *nal = &p[i+3];
        if( i_codec == VLC_CODEC_H264 )
        {
            if( (nal[0] & 0x1f) == 5 )     /* coded slice of an IDR picture */
                return true;
        }
        else
        {
            const uint8_t i_type = (nal[0] & 0x7e) >> 1;
            if( i_type == 19 || i_type == 20 )   /* IDR_W_RADL, IDR_N_LP */
                return true;
        }
    }
    return false;
}

/* when the picture is DISPLAYED, as opposed to when it is decoded */
static vlc_tick_t BlockDisplayTick( const block_t *p_block )
{
    if( unlikely(!p_block) )
        return 0;
    else if( likely(p_block->i_pts != 0) )
        return p_block->i_pts;
    else
        return p_block->i_dts;
}

/* Cut a buffered video chain at the frame the capture must begin with.
 *
 * ⚠⚠⚠ This CANNOT be done with a timestamp threshold, which is what the
 * generic path below does for the other streams. Decode order is not
 * display order: an open-GOP key frame (an HEVC CRA, an H.264 recovery
 * point) is followed in decode order by its LEADING pictures, which are
 * displayed before it -- so their timestamps are lower than the key
 * frame's, and so is the timestamp of nothing else. Cutting on "tick >=
 * key frame tick" threw those leading pictures away, which is right, but
 * it threw away with them the first P frame of the new GOP, whose dts
 * sits in the same range and whose PTS does not: everything that
 * referenced it then decoded to garbage until the next key frame.
 * Measured on an MKV clip cut at a CRA: 175 of 403 frames unusable, i.e.
 * seven seconds of visibly broken picture (12/08/2026 -- user report
 * "the export gives a degraded picture, but not always": only cuts that
 * land on an open-GOP key frame are hit).
 *
 * So: everything BEFORE the key frame in the chain goes, the leading
 * pictures right after it go (they are undecodable once their references
 * are outside the clip), and everything else stays whatever its dts. */
static void OutputTrimToKeyFrame( sout_stream_t *p_stream,
                                  sout_stream_id_sys_t *id, block_t *p_key )
{
    int i_dropped = 0;

    while( id->p_first != NULL && id->p_first != p_key )
    {
        block_t *p_block = id->p_first;
        id->p_first = p_block->p_next;
        block_Release( p_block );
        i_dropped++;
    }

    const vlc_tick_t i_key_display = BlockDisplayTick( p_key );
    block_t **pp_next = &p_key->p_next;
    while( *pp_next != NULL )
    {
        block_t *p_block = *pp_next;
        const vlc_tick_t i_display = BlockDisplayTick( p_block );

        /* leading pictures come as one run right after their key frame:
         * the first picture displayed after it ends them */
        if( i_display == 0 || i_display >= i_key_display )
            break;

        *pp_next = p_block->p_next;
        block_Release( p_block );
        i_dropped++;
    }

    /* the chain lost its tail marker along the way */
    id->pp_last = &id->p_first;
    for( block_t *p_block = id->p_first; p_block != NULL;
         p_block = p_block->p_next )
        id->pp_last = &p_block->p_next;

    id->b_trimmed = true;

    if( i_dropped > 0 )
        msg_Dbg( p_stream, "capture starts on the key frame, %d earlier or "
                 "leading picture(s) dropped", i_dropped );
}

static void OutputStart( sout_stream_t *p_stream )
{
    sout_stream_sys_t *p_sys = p_stream->p_sys;

    /* */
    if( p_sys->b_drop )
        return;

    /* From now on drop packet that cannot be handled */
    p_sys->b_drop = true;

    /* Detect streams to smart select muxer */
    const char *psz_muxer = NULL;
    const char *psz_extension = NULL;

    /* Look for preferred muxer
     * TODO we could insert transcode in a few cases like
     * s16l <-> s16b
     */
    for( unsigned i = 0; i < sizeof(p_muxers) / sizeof(*p_muxers); i++ )
    {
        bool b_ok;
        if( p_sys->i_id > p_muxers[i].i_es_max )
            continue;

        b_ok = true;
        for( int j = 0; j < p_sys->i_id; j++ )
        {
            es_format_t *p_fmt = &p_sys->id[j]->fmt;

            b_ok = false;
            for( int k = 0; p_muxers[i].codec[k] != 0; k++ )
            {
                if( p_fmt->i_codec == p_muxers[i].codec[k] )
                {
                    b_ok = true;
                    break;
                }
            }
            if( !b_ok )
                break;
        }
        if( !b_ok )
            continue;

        psz_muxer = p_muxers[i].psz_muxer;
        psz_extension = p_muxers[i].psz_extension;
        break;
    }

    /* If failed, brute force our demuxers and select the one that
     * keeps most of our stream */
    if( !psz_muxer || !psz_extension )
    {
        static const char ppsz_muxers[][2][4] = {
            { "avi", "avi" }, { "mp4", "mp4" }, { "ogg", "ogg" },
            { "asf", "asf" }, {  "ts",  "ts" }, {  "ps", "mpg" },
            /* ⚠ no "mkv" here: there is no native Matroska muxer to probe.
             * The table above routes Matroska to libavformat by name, which
             * is safe because it only ever happens on an exact codec match --
             * probing avformat blind is what the disabled block below warns
             * about. */
#if 0
            // XXX ffmpeg sefault really easily if you try an unsupported codec
            // mov and avi at least segfault
            { "avformat{mux=avi}", "avi" },
            { "avformat{mux=mov}", "mov" },
            { "avformat{mux=mp4}", "mp4" },
            { "avformat{mux=nsv}", "nsv" },
            { "avformat{mux=flv}", "flv" },
#endif
        };
        int i_best = 0;
        int i_best_es = 0;

        msg_Warn( p_stream, "failed to find an adequate muxer, probing muxers" );
        for( unsigned i = 0; i < sizeof(ppsz_muxers) / sizeof(*ppsz_muxers); i++ )
        {
            char *psz_file;
            int i_es;

            psz_file = tempnam( NULL, "vlc" );
            if( !psz_file )
                continue;

            msg_Dbg( p_stream, "probing muxer %s", ppsz_muxers[i][0] );
            i_es = OutputNew( p_stream, ppsz_muxers[i][0], psz_file, NULL );

            if( i_es < 0 )
            {
                vlc_unlink( psz_file );
                free( psz_file );
                continue;
            }

            /* */
            for( int j = 0; j < p_sys->i_id; j++ )
            {
                sout_stream_id_sys_t *id = p_sys->id[j];

                if( id->id )
                    sout_StreamIdDel( p_sys->p_out, id->id );
                id->id = NULL;
            }
            if( p_sys->p_out )
                sout_StreamChainDelete( p_sys->p_out, p_sys->p_out );
            p_sys->p_out = NULL;

            if( i_es > i_best_es )
            {
                i_best_es = i_es;
                i_best = i;

                if( i_best_es >= p_sys->i_id )
                    break;
            }
            vlc_unlink( psz_file );
            free( psz_file );
        }

        /* */
        psz_muxer = ppsz_muxers[i_best][0];
        psz_extension = ppsz_muxers[i_best][1];
        msg_Dbg( p_stream, "using muxer %s with extension %s (%d/%d streams accepted)",
                 psz_muxer, psz_extension, i_best_es, p_sys->i_id );
    }

    /* Create the output */
    if( OutputNew( p_stream, psz_muxer, p_sys->psz_prefix, psz_extension ) < 0 )
    {
        msg_Err( p_stream, "failed to open output");
        return;
    }

    /* Compute highest timestamp of first I over all streams */
    p_sys->i_dts_start = 0;
    vlc_tick_t i_highest_head_dts = 0;
    vlc_tick_t i_video_key = 0;
    for( int i = 0; i < p_sys->i_id; i++ )
    {
        sout_stream_id_sys_t *id = p_sys->id[i];

        if( !id->id || !id->p_first )
            continue;

        block_t *p_block = id->p_first;
        vlc_tick_t i_dts = BlockTick( p_block );

        if( i_dts > i_highest_head_dts &&
           ( id->fmt.i_cat == AUDIO_ES || id->fmt.i_cat == VIDEO_ES ) )
        {
            i_highest_head_dts = i_dts;
        }

        /* PowerVLC clip creation: when a start bound is set and the
         * buffer reaches back before it, prefer the LAST key frame at or
         * before the bound over the first key frame received -- the
         * capture then starts as close to the bound as decodability
         * allows. VIDEO only: audio samples are all flagged as key
         * frames, so a bounded pick there would slide i_dts_start up to
         * the bound itself and cut the chosen video key frame off.
         * Without a bound (or when the buffer starts after it) this
         * degrades to the historic first-key-frame behavior. */
        const bool b_bounded = p_sys->i_start_bound > 0
                            && id->fmt.i_cat == VIDEO_ES;
        bool b_found_key = false;
        block_t *p_key_block = NULL;
        for( ; p_block != NULL; p_block = p_block->p_next )
        {
            if( !( p_block->i_flags & BLOCK_FLAG_TYPE_I ) )
                continue;
            vlc_tick_t i_key_dts = BlockTick( p_block );
            if( !b_found_key )
            {
                i_dts = i_key_dts;
                p_key_block = p_block;
                b_found_key = true;
                if( !b_bounded )
                    break;
            }
            else if( i_key_dts <= p_sys->i_start_bound + VLC_TS_0 )
            {
                i_dts = i_key_dts;
                p_key_block = p_block;
            }
            else
                break;
        }

        /* Prefer a picture that resets the reference chain (see BlockIsIDR):
         * starting on a plain I picture leaves the two that follow it
         * mis-predicted. The swap is only worth it while it is CHEAP --
         * an IDR a long way further in would cost the user seconds of the
         * clip they asked for, which is far worse than two frames. One
         * second is the bound. */
        if( b_found_key && id->fmt.i_cat == VIDEO_ES && p_key_block != NULL
         && !BlockIsIDR( id->fmt.i_codec, p_key_block ) )
        {
            for( block_t *p_idr = p_key_block; p_idr != NULL;
                 p_idr = p_idr->p_next )
            {
                if( !( p_idr->i_flags & BLOCK_FLAG_TYPE_I )
                 || !BlockIsIDR( id->fmt.i_codec, p_idr ) )
                    continue;
                vlc_tick_t i_idr_dts = BlockTick( p_idr );
                if( i_idr_dts - i_dts > CLOCK_FREQ )
                    break;
                msg_Dbg( p_stream, "starting on the IDR %"PRId64" µs in "
                         "rather than on a plain I picture",
                         i_idr_dts - i_dts );
                p_key_block = p_idr;
                i_dts = i_idr_dts;
                break;
            }
        }

        if( b_found_key && id->fmt.i_cat == VIDEO_ES && i_dts > i_video_key )
            i_video_key = i_dts;

        msg_Dbg( p_stream, "stream %d cat %d: head %"PRId64" chosen key "
                 "%"PRId64" (bound %"PRId64") found_key=%d", i, id->fmt.i_cat,
                 BlockTick( id->p_first ), i_dts, p_sys->i_start_bound,
                 (int)b_found_key );

        if( i_dts > p_sys->i_dts_start )
            p_sys->i_dts_start = i_dts;

        /* cut the video buffer here, where decode order is still known */
        if( id->fmt.i_cat == VIDEO_ES && p_key_block != NULL )
            OutputTrimToKeyFrame( p_stream, id, p_key_block );
    }

    /* The chosen video key frame has the last word, bound or not: the
     * usual highest-first-I alignment lets an audio stream whose first
     * block sits a few ms later push the start PAST that key frame, which
     * is then dropped -- and the video, still waiting for a key frame,
     * only resumes at the next one, one whole GOP later. Measured on a
     * clip cut right on a key frame (what the clip creation mode always
     * does): audio from 0, video from 0.996 s, i.e. a black second at the
     * head of the file. Audio missing those few milliseconds instead is
     * harmless. */
    if( i_video_key > 0 && i_video_key < p_sys->i_dts_start )
        p_sys->i_dts_start = i_video_key;

    if( p_sys->i_dts_start == 0 )
        p_sys->i_dts_start = i_highest_head_dts;

    sout_stream_id_sys_t *p_cand;
    vlc_tick_t canddts;
    do
    {
        /* dequeue candidate */
        p_cand = NULL;
        canddts = 0;

        /* Send buffered data in dts order */
        for( int i = 0; i < p_sys->i_id; i++ )
        {
            sout_stream_id_sys_t *id = p_sys->id[i];

            if( !id->id || id->p_first == NULL )
                continue;

            block_t *p_id_block;
            vlc_tick_t id_dts = 0;
            for( p_id_block = id->p_first; p_id_block; p_id_block = p_id_block->p_next )
            {
                id_dts = BlockTick( p_id_block );
                if( id_dts != 0 )
                    break;
            }

            if( id_dts == 0 )
            {
                p_cand = id;
                canddts = 0;
                break;
            }

            if( p_cand == NULL || canddts > id_dts )
            {
                p_cand = id;
                canddts = id_dts;
            }
        }

        if( p_cand != NULL )
        {
            block_t *p_block = p_cand->p_first;
            p_cand->p_first = p_block->p_next;
            if( p_cand->p_first == NULL )
                p_cand->pp_last = &p_cand->p_first;
            p_block->p_next = NULL;

            /* a trimmed chain already begins exactly where it should, and
             * its own timestamps do not run in the order it holds */
            if( p_cand->b_trimmed
             || BlockTick( p_block ) >= p_sys->i_dts_start )
                OutputSend( p_stream, p_cand, p_block );
            else
                block_Release( p_block );
        }

    } while( p_cand != NULL );
}

static void OutputSend( sout_stream_t *p_stream, sout_stream_id_sys_t *id, block_t *p_block )
{
    sout_stream_sys_t *p_sys = p_stream->p_sys;

    if( id->id )
    {
        /* We wait until the first key frame (if needed) and
         * to be beyond i_dts_start (for stream without key frame) */
        if( unlikely( id->b_wait_key ) )
        {
            if( p_block->i_flags & BLOCK_FLAG_TYPE_I )
            {
                id->b_wait_key = false;
                id->b_wait_start = false;
            }

            if( ( p_block->i_flags & BLOCK_FLAG_TYPE_MASK ) == 0 )
                id->b_wait_key = false;
        }
        if( unlikely( id->b_wait_start ) )
        {
            if( p_block->i_dts >=p_sys->i_dts_start )
                id->b_wait_start = false;
        }
        if( unlikely( id->b_wait_key || id->b_wait_start ) )
            block_ChainRelease( p_block );
        else
            sout_StreamIdSend( p_sys->p_out, id->id, p_block );
    }
    else if( p_sys->b_drop )
    {
        block_ChainRelease( p_block );
    }
    else
    {
        size_t i_size;

        block_ChainProperties( p_block, NULL, &i_size, NULL );
        p_sys->i_size += i_size;
        block_ChainLastAppend( &id->pp_last, p_block );
    }
}
