/*****************************************************************************
 * aiff.c: Audio Interchange File Format demuxer
 *****************************************************************************
 * Copyright (C) 2004-2007 VLC authors and VideoLAN
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

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_demux.h>
#include <vlc_meta.h>
#include <limits.h>

/* TODO:
 *  - ...
 */

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
static int  Open    ( vlc_object_t * );
static void Close  ( vlc_object_t * );

vlc_module_begin ()
    set_category( CAT_INPUT )
    set_subcategory( SUBCAT_INPUT_DEMUX )
    set_description( N_("AIFF demuxer" ) )
    set_capability( "demux", 10 )
    set_callbacks( Open, Close )
    add_shortcut( "aiff" )
vlc_module_end ()

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/

struct demux_sys_t
{
    es_format_t  fmt;
    es_out_id_t *es;

    int64_t     i_ssnd_pos;
    int64_t     i_ssnd_size;
    uint32_t    i_ssnd_offset;
    uint32_t    i_ssnd_blocksize;

    /* real data start */
    int64_t     i_ssnd_start;
    int64_t     i_ssnd_end;

    int         i_ssnd_fsize;

    int64_t     i_time;

    vlc_meta_t *p_meta;
};

static int Demux  ( demux_t *p_demux );
static int Control( demux_t *p_demux, int i_query, va_list args );

/* GetF80BE: read a 80 bits float in big endian */
static unsigned int GetF80BE( const uint8_t p[10] )
{
    unsigned int i_mantissa = GetDWBE( &p[2] );
    int          i_exp = 30 - p[1];
    unsigned int i_last = 0;

    while( i_exp-- > 0 )
    {
        i_last = i_mantissa;
        i_mantissa >>= 1;
    }
    if( i_last&0x01 )
    {
        i_mantissa++;
    }
    return i_mantissa;
}

static int ReadTextChunk( demux_t *p_demux, uint64_t i_chunk_size,
                          uint32_t i_data_size )
{
    static const struct
    {
        char chunk_id[4];
        vlc_meta_type_t meta_type;
    } text_chunks[] = {
        { { 'N', 'A', 'M', 'E' }, vlc_meta_Title },
        { { 'A', 'U', 'T', 'H' }, vlc_meta_Artist },
        { { '(', 'c', ')', ' ' }, vlc_meta_Copyright },
        { { 'A', 'N', 'N', 'O' }, vlc_meta_Description },
    };

    const uint8_t *p_peek;
    if( vlc_stream_Peek( p_demux->s, &p_peek, 8 ) < 8 )
        return VLC_EGENERIC;

    size_t i_text_chunk = ARRAY_SIZE( text_chunks );
    for( size_t i = 0; i < ARRAY_SIZE( text_chunks ); ++i )
    {
        if( !memcmp( p_peek, text_chunks[i].chunk_id, 4 ) )
        {
            i_text_chunk = i;
            break;
        }
    }
    if( i_text_chunk == ARRAY_SIZE( text_chunks ) )
        return VLC_EGENERIC;

    /* Text metadata is expected to be tiny. Avoid asking the stream cache to
     * materialize a maliciously large chunk just to read a tag. */
    if( i_data_size > 16 * 1024 * 1024 )
        return VLC_EGENERIC;
    ssize_t i_peek = vlc_stream_Peek( p_demux->s, &p_peek, i_chunk_size );
    if( i_peek < 0 || (uint64_t)i_peek != i_chunk_size )
        return VLC_EGENERIC;

    char *psz_value = malloc( (size_t)i_data_size + 1 );
    if( psz_value == NULL )
        return VLC_ENOMEM;

    memcpy( psz_value, p_peek + 8, i_data_size );
    psz_value[i_data_size] = '\0';

    demux_sys_t *p_sys = p_demux->p_sys;
    if( p_sys->p_meta == NULL )
        p_sys->p_meta = vlc_meta_New();
    if( p_sys->p_meta == NULL )
    {
        free( psz_value );
        return VLC_ENOMEM;
    }

    vlc_meta_Set( p_sys->p_meta, text_chunks[i_text_chunk].meta_type,
                  psz_value );
    free( psz_value );
    return VLC_SUCCESS;
}

/*****************************************************************************
 * Open
 *****************************************************************************/
static int Open( vlc_object_t *p_this )
{
    demux_t     *p_demux = (demux_t*)p_this;
    demux_sys_t *p_sys;

    const uint8_t *p_peek;

    bool b_can_seek = false;
    if( vlc_stream_Control( p_demux->s, STREAM_CAN_SEEK, &b_can_seek ) ||
        !b_can_seek )
        return VLC_EGENERIC;

    if( vlc_stream_Peek( p_demux->s, &p_peek, 12 ) < 12 )
        return VLC_EGENERIC;
    if( memcmp( p_peek, "FORM", 4 ) || memcmp( &p_peek[8], "AIFF", 4 ) )
        return VLC_EGENERIC;

    uint64_t i_form_end = UINT64_C(8) + GetDWBE( &p_peek[4] );
    if( i_form_end < 12 )
        return VLC_EGENERIC;

    /* skip aiff header */
    if( vlc_stream_Read( p_demux->s, NULL, 12 ) < 12 )
        return VLC_EGENERIC;

    /* Fill p_demux field */
    DEMUX_INIT_COMMON(); p_sys = p_demux->p_sys;
    es_format_Init( &p_sys->fmt, AUDIO_ES, VLC_FOURCC( 't', 'w', 'o', 's' ) );
    p_sys->i_time = 0;
    p_sys->i_ssnd_pos = -1;

    for( ;; )
    {
        int64_t i_chunk_pos = vlc_stream_Tell( p_demux->s );
        if( i_chunk_pos < 0 || (uint64_t)i_chunk_pos + 8 > i_form_end )
            break;

        if( vlc_stream_Peek( p_demux->s, &p_peek, 8 ) < 8 )
            break;

        uint32_t i_data_size = GetDWBE( &p_peek[4] );
        uint64_t i_chunk_size = UINT64_C( 8 ) + i_data_size + ( i_data_size & 1 );

        msg_Dbg( p_demux, "chunk fcc=%4.4s size=%" PRIu64 " data_size=%" PRIu32,
            p_peek, i_chunk_size, i_data_size );

        if( !memcmp( p_peek, "COMM", 4 ) )
        {
            if( i_data_size < 18 )
                goto error;
            if( vlc_stream_Peek( p_demux->s, &p_peek, 18+8 ) < 18+8 )
                goto error;

            p_sys->fmt.audio.i_channels = GetWBE( &p_peek[8] );
            p_sys->fmt.audio.i_bitspersample = GetWBE( &p_peek[14] );
            p_sys->fmt.audio.i_rate     = GetF80BE( &p_peek[16] );

            msg_Dbg( p_demux, "COMM: channels=%d samples_frames=%d bits=%d rate=%d",
                     GetWBE( &p_peek[8] ), GetDWBE( &p_peek[10] ), GetWBE( &p_peek[14] ),
                     GetF80BE( &p_peek[16] ) );
        }
        else if( !memcmp( p_peek, "SSND", 4 ) )
        {
            if( i_data_size < 8 )
                goto error;
            if( vlc_stream_Peek( p_demux->s, &p_peek, 8+8 ) < 8+8 )
                goto error;

            p_sys->i_ssnd_pos = vlc_stream_Tell( p_demux->s );
            p_sys->i_ssnd_size = i_data_size;
            p_sys->i_ssnd_offset = GetDWBE( &p_peek[8] );
            p_sys->i_ssnd_blocksize = GetDWBE( &p_peek[12] );

            if( p_sys->i_ssnd_offset > i_data_size - 8 )
                goto error;

            msg_Dbg( p_demux, "SSND: (offset=%" PRIu32 " blocksize=%" PRIu32 ")",
                     p_sys->i_ssnd_offset, p_sys->i_ssnd_blocksize );
        }
        else
        {
            int i_ret = ReadTextChunk( p_demux, i_chunk_size, i_data_size );
            if( i_ret == VLC_ENOMEM )
                goto error;
        }

        uint64_t i_next_chunk = (uint64_t)i_chunk_pos + i_chunk_size;
        if( i_next_chunk > i_form_end ||
            vlc_stream_Seek( p_demux->s, i_next_chunk ) != VLC_SUCCESS )
        {
            msg_Warn( p_demux, "incomplete file" );
            goto error;
        }
    }

    p_sys->i_ssnd_start = p_sys->i_ssnd_pos + 16 + p_sys->i_ssnd_offset;
    p_sys->i_ssnd_end = p_sys->i_ssnd_start + p_sys->i_ssnd_size
                      - 8 - p_sys->i_ssnd_offset;

    p_sys->i_ssnd_fsize = p_sys->fmt.audio.i_channels *
                          ((p_sys->fmt.audio.i_bitspersample + 7) / 8);

    if( p_sys->i_ssnd_pos < 12 || p_sys->i_ssnd_fsize <= 0 ||
        p_sys->fmt.audio.i_rate == 0 )
    {
        msg_Err( p_demux, "invalid audio parameters" );
        goto error;
    }

    /* seek into SSND chunk */
    if( vlc_stream_Seek( p_demux->s, p_sys->i_ssnd_start ) )
    {
        msg_Err( p_demux, "cannot seek to data chunk" );
        goto error;
    }

    /* */
    p_sys->es = es_out_Add( p_demux->out, &p_sys->fmt );

    return VLC_SUCCESS;

error:
    if( p_sys->p_meta )
        vlc_meta_Delete( p_sys->p_meta );
    free( p_sys );
    return VLC_EGENERIC;
}

/*****************************************************************************
 * Close
 *****************************************************************************/
static void Close( vlc_object_t *p_this )
{
    demux_t     *p_demux = (demux_t*)p_this;
    demux_sys_t *p_sys = p_demux->p_sys;

    if( p_sys->p_meta )
        vlc_meta_Delete( p_sys->p_meta );
    free( p_sys );
}


/*****************************************************************************
 * Demux:
 *****************************************************************************/
static int Demux( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    int64_t     i_tell = vlc_stream_Tell( p_demux->s );

    block_t     *p_block;
    int         i_read;

    if( p_sys->i_ssnd_end > 0 && i_tell >= p_sys->i_ssnd_end )
    {
        /* EOF */
        return 0;
    }

    /* Set PCR */
    es_out_SetPCR( p_demux->out, VLC_TICK_0 + p_sys->i_time);

    /* we will read 100ms at once */
    i_read = p_sys->i_ssnd_fsize * ( p_sys->fmt.audio.i_rate / 10 );
    if( p_sys->i_ssnd_end > 0 && p_sys->i_ssnd_end - i_tell < i_read )
    {
        i_read = p_sys->i_ssnd_end - i_tell;
    }
    if( ( p_block = vlc_stream_Block( p_demux->s, i_read ) ) == NULL )
    {
        return 0;
    }

    p_block->i_dts =
    p_block->i_pts = VLC_TICK_0 + p_sys->i_time;

    p_sys->i_time += (int64_t)1000000 *
                     p_block->i_buffer /
                     p_sys->i_ssnd_fsize /
                     p_sys->fmt.audio.i_rate;

    /* */
    es_out_Send( p_demux->out, p_sys->es, p_block );
    return 1;
}

/*****************************************************************************
 * Control:
 *****************************************************************************/
static int Control( demux_t *p_demux, int i_query, va_list args )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    double f, *pf;
    int64_t *pi64;

    switch( i_query )
    {
        case DEMUX_CAN_SEEK:
            return vlc_stream_vaControl( p_demux->s, i_query, args );

        case DEMUX_GET_POSITION:
        {
            int64_t i_start = p_sys->i_ssnd_start;
            int64_t i_end   = p_sys->i_ssnd_end > 0 ? p_sys->i_ssnd_end : stream_Size( p_demux->s );
            int64_t i_tell  = vlc_stream_Tell( p_demux->s );

            pf = va_arg( args, double * );

            if( i_start < i_end )
            {
                *pf = (double)(i_tell - i_start)/(double)(i_end - i_start);
                return VLC_SUCCESS;
            }
            return VLC_EGENERIC;
        }

        case DEMUX_SET_POSITION:
        {
            int64_t i_start = p_sys->i_ssnd_start;
            int64_t i_end  = p_sys->i_ssnd_end > 0 ? p_sys->i_ssnd_end : stream_Size( p_demux->s );

            f = va_arg( args, double );

            if( i_start < i_end )
            {
                int     i_frame = (f * ( i_end - i_start )) / p_sys->i_ssnd_fsize;
                int64_t i_new   = i_start + i_frame * p_sys->i_ssnd_fsize;

                if( vlc_stream_Seek( p_demux->s, i_new ) )
                {
                    return VLC_EGENERIC;
                }
                p_sys->i_time = (int64_t)1000000 * i_frame / p_sys->fmt.audio.i_rate;
                return VLC_SUCCESS;
            }
            return VLC_EGENERIC;
        }

        case DEMUX_GET_TIME:
            pi64 = va_arg( args, int64_t * );
            *pi64 = p_sys->i_time;
            return VLC_SUCCESS;

        case DEMUX_GET_LENGTH:
        {
            int64_t i_end  = p_sys->i_ssnd_end > 0 ? p_sys->i_ssnd_end : stream_Size( p_demux->s );

            pi64 = va_arg( args, int64_t * );
            if( p_sys->i_ssnd_start < i_end )
            {
                *pi64 = (int64_t)1000000 * ( i_end - p_sys->i_ssnd_start ) / p_sys->i_ssnd_fsize / p_sys->fmt.audio.i_rate;
                return VLC_SUCCESS;
            }
            return VLC_EGENERIC;
        }
        case DEMUX_GET_META:
            if( p_sys->p_meta == NULL )
                return VLC_EGENERIC;
            vlc_meta_Merge( va_arg( args, vlc_meta_t * ), p_sys->p_meta );
            return VLC_SUCCESS;

        case DEMUX_SET_TIME:
        case DEMUX_GET_FPS:
        default:
            return VLC_EGENERIC;
    }
}
