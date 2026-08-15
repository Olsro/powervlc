/*****************************************************************************
 * dvdread.c : DvdRead input module for vlc
 *****************************************************************************
 * Copyright (C) 2001-2006 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Stéphane Borel <stef@via.ecp.fr>
 *          Gildas Bazin <gbazin@videolan.org>
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
 * NOTA BENE: this module requires the linking against a library which is
 * known to require licensing under the GNU General Public License version 2
 * (or later). Therefore, the result of compiling this module will normally
 * be subject to the terms of that later license.
 *****************************************************************************/


/*****************************************************************************
 * Preamble
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_input.h>
#include <vlc_access.h>
#include <vlc_charset.h>
#include <vlc_interface.h>
#include <vlc_dialog.h>
#include "dvd_description.h"

#include <vlc_iso_lang.h>

#include "../demux/mpeg/pes.h"
#include "../demux/mpeg/ps.h"

#include <sys/types.h>
#include <unistd.h>

#include <dvdread/dvd_reader.h>
#include <dvdread/ifo_types.h>
#include <dvdread/ifo_read.h>
#include <dvdread/nav_read.h>
#include <dvdread/nav_print.h>

#ifndef DVDREAD_VERSION_CODE
# define DVDREAD_VERSION_CODE(major, minor, micro) (((major) * 10000) + ((minor) * 100) +  ((micro) * 1))
# define DVDREAD_VERSION DVDREAD_VERSION_CODE(5,0,3)
#endif

/* DVD-Audio (AUDIO_TS zone) needs the audio IFO API of libdvdread 7 */
#if DVDREAD_VERSION >= DVDREAD_VERSION_CODE(7, 0, 0)
# define DVDREAD_HAS_DVDAUDIO 1
#endif

#include <assert.h>
#include <limits.h>

#include "disc_helper.h"

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
#define ANGLE_TEXT N_("DVD angle")
#define ANGLE_LONGTEXT N_( \
    "Default DVD angle." )

static int  Open ( vlc_object_t * );
static void Close( vlc_object_t * );

vlc_module_begin ()
    set_shortname( N_("DVD without menus") )
    set_description( N_("DVDRead Input (no menu support)") )
    set_category( CAT_INPUT )
    set_subcategory( SUBCAT_INPUT_ACCESS )
    add_integer( "dvdread-angle", 1, ANGLE_TEXT,
        ANGLE_LONGTEXT, false )
    add_obsolete_string( "dvdread-css-method" ) /* obsolete since 1.1.0 */
    set_capability( "access_demux", 0 )
    add_shortcut( "dvd", "dvdread", "dvdsimple", "dvda" )
    set_callbacks( Open, Close )
vlc_module_end ()

/* how many blocks DVDRead will read in each loop */
#define DVD_BLOCK_READ_ONCE 4

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/

struct demux_sys_t
{
    /* DVDRead state */
    dvd_reader_t *p_dvdread;
    dvd_file_t   *p_title;

    ifo_handle_t *p_vmg_file;
    ifo_handle_t *p_vts_file;

    int i_title;
    int i_chapter, i_chapters;
    int i_angle, i_angles;

    tt_srpt_t    *p_tt_srpt;
    pgc_t        *p_cur_pgc;
    dsi_t        dsi_pack;
    int          i_ttn;

    int i_pack_len;
    int i_cur_block;
    int i_next_vobu;

    int i_mux_rate;

    /* Current title start/end blocks */
    int i_title_start_block;
    int i_title_end_block;
    int i_title_blocks;
    int i_title_offset;
    vlc_tick_t i_title_cur_time;

    int i_title_start_cell;
    int i_title_end_cell;
    int i_cur_cell;
    int i_next_cell;
    vlc_tick_t i_cell_cur_time;
    vlc_tick_t i_cell_duration;

    /* Time axis. Everything the user sees or clicks -- the clock, the slider,
     * the chapter marks and seeking -- is expressed in TIME and derived from
     * this one table, so they cannot disagree. The old axis was the sector
     * count, with time extrapolated from it as if the bitrate were constant;
     * on a variable-bitrate title the two rulers drift apart and the cursor
     * never lands on its own chapter marks.
     * p_cell_start_time[c] is the title-relative start time of cell c along
     * the played angle. Cells of an angle block all carry the same start
     * time, and only the selected angle is counted once into the total --
     * counting them all is what made i_title_blocks overstate the length of
     * an angle title. */
    int64_t   *p_cell_start_time;
    int        i_cell_count;
    vlc_tick_t i_title_time;

    /* Track */
    ps_track_t    tk[PS_TK_COUNT];

    int           i_titles;
    input_title_t **titles;

    /* Video */
    int i_sar_num;
    int i_sar_den;

    /* SPU */
    uint32_t clut[16];

    /* DVD-Audio (AUDIO_TS) mode */
    bool b_audio;
#ifdef DVDREAD_HAS_DVDAUDIO
    /* Current ATS title record (points into p_vts_file, reused as ATS ifo) */
    atsi_title_record_t *p_title_table;
#endif
};

static int Control   ( demux_t *, int, va_list );
static int Demux     ( demux_t * );
static int DemuxBlock( demux_t *, const uint8_t *, int );

static void DemuxTitles( demux_t *, int * );
static void ESNew( demux_t *, int, int, int );

static int  DvdReadSetArea  ( demux_t *, int, int, int );
static int  DvdReadSeek     ( demux_t *, int );
static void DvdReadHandleDSI( demux_t *, uint8_t * );
static void DvdReadFindCell ( demux_t * );

/* time axis */
static vlc_tick_t DvdReadCurrentTime( demux_sys_t * );
static int        DvdReadTimeToBlock( demux_sys_t *, vlc_tick_t );

#ifdef DVDREAD_HAS_DVDAUDIO
/* ATS lengths are 90 kHz MPEG PTS ticks, not BCD dvd_time_t */
# define DVDA_PTS_TO_TIME( pts ) ( (int64_t)(pts) * CLOCK_FREQ / 90000 )
static int  DvdReadSetAreaAudio( demux_t *, int, int );
static int  DvdReadSeekAudio   ( demux_t *, int );
static void DemuxTitlesAudio   ( demux_t * );
static int  DemuxAudio         ( demux_t * );
#endif

#if DVDREAD_VERSION >= DVDREAD_VERSION_CODE(6, 1, 0)
static void DvdReadLog( void *foo, dvd_logger_level_t i, const char *p, va_list z )
{
    demux_t *p_demux = (demux_t*)foo;
    msg_GenericVa( p_demux, i, p, z );
}
#endif
/*****************************************************************************
 * Open:
 *****************************************************************************/
static int Open( vlc_object_t *p_this )
{
    demux_t      *p_demux = (demux_t*)p_this;
    demux_sys_t  *p_sys;
    char         *psz_file;
    ifo_handle_t *p_vmg_file;

    if( !p_demux->psz_file || !*p_demux->psz_file )
    {
        /* Only when selected */
        if( !*p_demux->psz_access )
            return VLC_EGENERIC;

        psz_file = var_InheritString( p_this, "dvd" );
    }
    else
        psz_file = strdup( p_demux->psz_file );

#if defined( _WIN32 ) || defined( __OS2__ )
    if( psz_file != NULL )
    {
        size_t flen = strlen( psz_file );
        if( flen > 0 && psz_file[flen - 1] == '\\' )
            psz_file[flen - 1] = '\0';
    }
    else
        psz_file = strdup("");
#endif
    if( unlikely(psz_file == NULL) )
        return VLC_EGENERIC;

    if( DiscProbeMacOSPermission( p_this, psz_file ) != VLC_SUCCESS )
    {
        free( psz_file );
        return VLC_EGENERIC;
    }

    /* Open dvdread */
#if DVDREAD_VERSION < DVDREAD_VERSION_CODE(6, 1, 2)
    /* In libdvdread prior to 6.1.2, UTF8 is not supported for windows and
     * requires a prior conversion.
     * For non win32/os2 platforms, this is just a no-op */
    const char *psz_path = ToLocale( psz_file );
#else
    const char *psz_path = psz_file;
#endif
#if DVDREAD_VERSION >= DVDREAD_VERSION_CODE(6, 1, 0)
    dvd_logger_cb cbs;
    cbs.pf_log = DvdReadLog;
#ifdef DVDREAD_HAS_DVDAUDIO
    /* dvda:// forces the AUDIO_TS zone; a plain dvd:// still reaches it,
     * DVDOpen2 probes the disc type on its own since 7.1.0 */
    dvd_reader_t *p_dvdread;
    if( p_demux->psz_access != NULL && !strcmp( p_demux->psz_access, "dvda" ) )
        p_dvdread = DVDOpenAudio( p_demux, &cbs, psz_path );
    else
        p_dvdread = DVDOpen2( p_demux, &cbs, psz_path );
#else
    dvd_reader_t *p_dvdread = DVDOpen2( p_demux, &cbs, psz_path );
#endif
#else
    dvd_reader_t *p_dvdread = DVDOpen( psz_path );
#endif
#if DVDREAD_VERSION < DVDREAD_VERSION_CODE(6, 1, 2)
    LocaleFree( psz_path );
#endif
    if( p_dvdread == NULL )
    {
        msg_Err( p_demux, "DVDRead cannot open source: %s", psz_file );
        vlc_dialog_display_error( p_demux, _("Playback failure"),
                      _("DVDRead could not open the disc \"%s\"."), psz_file );

        free( psz_file );
        return VLC_EGENERIC;
    }
    free( psz_file );

    /* Ifo allocation & initialisation */
    if( !( p_vmg_file = ifoOpen( p_dvdread, 0 ) ) )
    {
        char rgsz_volid[32];
        if( DVDUDFVolumeInfo( p_dvdread, rgsz_volid, 32, NULL, 0 ) )
        {
            if( DVDISOVolumeInfo( p_dvdread, rgsz_volid, 32, NULL, 0 ) == 0 )
            {
                vlc_dialog_display_error( p_demux, _("Playback failure"),
                              _("Cannot play a non-UDF mastered DVD." ) );
                msg_Err( p_demux, "Invalid UDF DVD. (Found ISO9660 '%s')", rgsz_volid );
            }
        }
        msg_Warn( p_demux, "cannot open VMG info" );
        DVDClose( p_dvdread );
        return VLC_EGENERIC;
    }
    msg_Dbg( p_demux, "VMG opened" );

    /* Fill p_demux field */
    DEMUX_INIT_COMMON(); p_sys = p_demux->p_sys;

    ps_track_init( p_sys->tk );
    p_sys->i_sar_num = 0;
    p_sys->i_sar_den = 0;
    p_sys->i_title_cur_time = (vlc_tick_t) 0;
    p_sys->i_cell_cur_time = (vlc_tick_t) 0;
    p_sys->i_cell_duration = (vlc_tick_t) 0;

    p_sys->p_dvdread = p_dvdread;
    p_sys->p_vmg_file = p_vmg_file;
    p_sys->p_title = NULL;
    p_sys->p_vts_file = NULL;

    p_sys->i_title = p_sys->i_chapter = -1;
    p_sys->i_mux_rate = 0;

    p_sys->b_audio = false;
#ifdef DVDREAD_HAS_DVDAUDIO
    p_sys->p_title_table = NULL;
    if( p_vmg_file->ifo_format == IFO_AUDIO )
    {
        p_sys->b_audio = true;
        msg_Dbg( p_demux, "DVD-Audio disc detected" );
    }
#endif

    p_sys->i_angle = var_CreateGetInteger( p_demux, "dvdread-angle" );
    if( p_sys->i_angle <= 0 ) p_sys->i_angle = 1;

#ifdef DVDREAD_HAS_DVDAUDIO
    if( p_sys->b_audio )
    {
        DemuxTitlesAudio( p_demux );
        if( DvdReadSetAreaAudio( p_demux, 0, 0 ) != VLC_SUCCESS )
        {
            msg_Err( p_demux, "DvdReadSetAreaAudio(0,0) failed" );
            Close( p_this );
            return VLC_EGENERIC;
        }
        return VLC_SUCCESS;
    }
#endif

    DemuxTitles( p_demux, &p_sys->i_angle );
    if( DvdReadSetArea( p_demux, 0, 0, p_sys->i_angle ) != VLC_SUCCESS )
    {
        msg_Err( p_demux, "DvdReadSetArea(0,0,%i) failed (can't decrypt DVD?)",
                 p_sys->i_angle );
        Close( p_this );
        return VLC_EGENERIC;
    }

    return VLC_SUCCESS;
}

/*****************************************************************************
 * Close:
 *****************************************************************************/
static void Close( vlc_object_t *p_this )
{
    demux_t     *p_demux = (demux_t*)p_this;
    demux_sys_t *p_sys = p_demux->p_sys;

    for( int i = 0; i < PS_TK_COUNT; i++ )
    {
        ps_track_t *tk = &p_sys->tk[i];
        if( tk->b_configured )
        {
            es_format_Clean( &tk->fmt );
            if( tk->es ) es_out_Del( p_demux->out, tk->es );
        }
    }

    /* Free the array of titles */
    for( int i = 0; i < p_sys->i_titles; i++ )
        vlc_input_title_Delete( p_sys->titles[i] );
    TAB_CLEAN( p_sys->i_titles, p_sys->titles );

    /* Close libdvdread */
    if( p_sys->p_title ) DVDCloseFile( p_sys->p_title );
    if( p_sys->p_vts_file ) ifoClose( p_sys->p_vts_file );
    if( p_sys->p_vmg_file ) ifoClose( p_sys->p_vmg_file );
    DVDClose( p_sys->p_dvdread );

    free( p_sys->p_cell_start_time );
    free( p_sys );
}

static int64_t dvdtime_to_time( dvd_time_t *dtime, uint8_t still_time )
{
/* Macro to convert Binary Coded Decimal to Decimal */
#define BCD2D(__x__) (((__x__ & 0xf0) >> 4) * 10 + (__x__ & 0x0f))

    double f_fps, f_ms;
    int64_t i_micro_second = 0;

    if (still_time == 0 || still_time == 0xFF)
    {
        i_micro_second += (int64_t)(BCD2D(dtime->hour)) * 60 * 60 * 1000000;
        i_micro_second += (int64_t)(BCD2D(dtime->minute)) * 60 * 1000000;
        i_micro_second += (int64_t)(BCD2D(dtime->second)) * 1000000;

        switch((dtime->frame_u & 0xc0) >> 6)
        {
        case 1:
            f_fps = 25.0;
            break;
        case 3:
            f_fps = 29.97;
            break;
        default:
            f_fps = 2500.0;
            break;
        }
        f_ms = BCD2D(dtime->frame_u&0x3f) * 1000.0 / f_fps;
        i_micro_second += (int64_t)(f_ms * 1000.0);
    }
    else
    {
        i_micro_second = still_time;
        i_micro_second = (int64_t)((double)i_micro_second * 1000000.0);
    }

    return i_micro_second;
}

/*****************************************************************************
 * Control:
 *****************************************************************************/
static int Control( demux_t *p_demux, int i_query, va_list args )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    double f, *pf;
    bool *pb;
    int64_t *pi64;
    input_title_t ***ppp_title;
    int *pi_int;
    int i;

    if(unlikely(!p_sys->p_vts_file))
        return VLC_EGENERIC;

    switch( i_query )
    {
        case DEMUX_GET_POSITION:
        {
            pf = va_arg( args, double * );

#ifdef DVDREAD_HAS_DVDAUDIO
            if( p_sys->b_audio )
            {
                *pf = p_sys->i_title_blocks > 0
                    ? (double)p_sys->i_title_offset / p_sys->i_title_blocks
                    : 0.0;
                return VLC_SUCCESS;
            }
#endif
            /* Position is time, like the clock and the chapter marks. */
            if( p_sys->i_title_time > 0 )
            {
                const vlc_tick_t i_now = DvdReadCurrentTime( p_sys );
                *pf = (double)i_now / (double)p_sys->i_title_time;
            }
            else if( p_sys->i_title_blocks > 0 )
                *pf = (double)p_sys->i_title_offset / p_sys->i_title_blocks;
            else
                *pf = 0.0;

            return VLC_SUCCESS;
        }
        case DEMUX_SET_POSITION:
        {
            f = va_arg( args, double );

#ifdef DVDREAD_HAS_DVDAUDIO
            if( p_sys->b_audio )
                return DvdReadSeekAudio( p_demux, f * p_sys->i_title_blocks );
#endif
            if( p_sys->i_title_time > 0 )
                return DvdReadSeek( p_demux, DvdReadTimeToBlock( p_sys,
                                    (vlc_tick_t)( f * p_sys->i_title_time ) ) );
            return DvdReadSeek( p_demux, f * p_sys->i_title_blocks );
        }
        case DEMUX_SET_TIME:
        {
            const int64_t i_target = va_arg( args, int64_t );

#ifdef DVDREAD_HAS_DVDAUDIO
            if( p_sys->b_audio )
                return VLC_EGENERIC;    /* AUDIO_TS has no time axis: the
                                         * core falls back on the position */
#endif
            if( p_sys->i_title_time <= 0 )
                return VLC_EGENERIC;
            return DvdReadSeek( p_demux,
                                DvdReadTimeToBlock( p_sys, i_target ) );
        }
        case DEMUX_GET_TIME:
            pi64 = va_arg( args, int64_t * );
            if( p_demux->info.i_title >= 0 && p_demux->info.i_title < p_sys->i_titles )
            {
#ifdef DVDREAD_HAS_DVDAUDIO
                if( p_sys->b_audio )
                {
                    if( p_sys->p_title_table == NULL || p_sys->i_title_blocks <= 0 )
                    {
                        *pi64 = 0;
                        return VLC_EGENERIC;
                    }
                    *pi64 = DVDA_PTS_TO_TIME( p_sys->p_title_table->length_pts ) /
                            p_sys->i_title_blocks * p_sys->i_title_offset;
                    return VLC_SUCCESS;
                }
#endif
                *pi64 = DvdReadCurrentTime( p_sys );
                return VLC_SUCCESS;
            }
            *pi64 = 0;
            return VLC_EGENERIC;

        case DEMUX_GET_LENGTH:
            pi64 = va_arg( args, int64_t * );
            if( p_demux->info.i_title >= 0 && p_demux->info.i_title < p_sys->i_titles )
            {
#ifdef DVDREAD_HAS_DVDAUDIO
                if( p_sys->b_audio )
                {
                    if( p_sys->p_title_table == NULL )
                    {
                        *pi64 = 0;
                        return VLC_EGENERIC;
                    }
                    *pi64 = DVDA_PTS_TO_TIME( p_sys->p_title_table->length_pts );
                    return VLC_SUCCESS;
                }
#endif
                /* The sum over the played path, not the PGC's own figure:
                 * they differ on an angle title, and the clock, the slider
                 * and the chapter marks all count the played path. */
                *pi64 = p_sys->i_title_time > 0
                    ? p_sys->i_title_time
                    : (int64_t)dvdtime_to_time(
                          &p_sys->p_cur_pgc->playback_time, 0 );
                return VLC_SUCCESS;
            }
            *pi64 = 0;
            return VLC_EGENERIC;

        /* Special for access_demux */
        case DEMUX_CAN_PAUSE:
        case DEMUX_CAN_SEEK:
        case DEMUX_CAN_CONTROL_PACE:
            /* TODO */
            pb = va_arg( args, bool * );
            *pb = true;
            return VLC_SUCCESS;

        case DEMUX_SET_PAUSE_STATE:
            return VLC_SUCCESS;

        case DEMUX_GET_TITLE_INFO:
            ppp_title = va_arg( args, input_title_t *** );
            pi_int    = va_arg( args, int * );
            *va_arg( args, int * ) = 1; /* Title offset */
            *va_arg( args, int * ) = 1; /* Chapter offset */

            /* Duplicate title infos */
            *pi_int = p_sys->i_titles;
            *ppp_title = vlc_alloc( p_sys->i_titles, sizeof(input_title_t *) );
            for( i = 0; i < p_sys->i_titles; i++ )
            {
                (*ppp_title)[i] = vlc_input_title_Duplicate(p_sys->titles[i]);
            }
            return VLC_SUCCESS;

        case DEMUX_SET_TITLE:
            i = va_arg( args, int );
#ifdef DVDREAD_HAS_DVDAUDIO
            if( p_sys->b_audio
              ? DvdReadSetAreaAudio( p_demux, i, 0 ) != VLC_SUCCESS
              : DvdReadSetArea( p_demux, i, 0, -1 ) != VLC_SUCCESS )
#else
            if( DvdReadSetArea( p_demux, i, 0, -1 ) != VLC_SUCCESS )
#endif
            {
                msg_Warn( p_demux, "cannot set title/chapter" );
                return VLC_EGENERIC;
            }
            p_demux->info.i_update |=
                INPUT_UPDATE_TITLE | INPUT_UPDATE_SEEKPOINT;
            p_demux->info.i_title = i;
            p_demux->info.i_seekpoint = 0;
            return VLC_SUCCESS;

        case DEMUX_SET_SEEKPOINT:
            i = va_arg( args, int );
#ifdef DVDREAD_HAS_DVDAUDIO
            if( p_sys->b_audio
              ? DvdReadSetAreaAudio( p_demux, -1, i ) != VLC_SUCCESS
              : DvdReadSetArea( p_demux, -1, i, -1 ) != VLC_SUCCESS )
#else
            if( DvdReadSetArea( p_demux, -1, i, -1 ) != VLC_SUCCESS )
#endif
            {
                msg_Warn( p_demux, "cannot set title/chapter" );
                return VLC_EGENERIC;
            }
            p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;
            p_demux->info.i_seekpoint = i;
            return VLC_SUCCESS;

        case DEMUX_GET_PTS_DELAY:
            pi64 = va_arg( args, int64_t * );
            *pi64 =
                INT64_C(1000) * var_InheritInteger( p_demux, "disc-caching" );
            return VLC_SUCCESS;

        /* TODO implement others */
        default:
            return VLC_EGENERIC;
    }
}

/*****************************************************************************
 * Demux:
 *****************************************************************************/
static int Demux( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if(unlikely(!p_sys->p_vts_file))
        return VLC_DEMUXER_EOF;

#ifdef DVDREAD_HAS_DVDAUDIO
    if( p_sys->b_audio )
        return DemuxAudio( p_demux );
#endif

    uint8_t p_buffer[DVD_VIDEO_LB_LEN * DVD_BLOCK_READ_ONCE];
    int i_blocks_once, i_read;

    /*
     * Playback by cell in this pgc, starting at the cell for our chapter.
     */

    /*
     * Check end of pack, and select the following one
     */
    if( !p_sys->i_pack_len )
    {
        /* Read NAV packet */
        if( DVDReadBlocks( p_sys->p_title, p_sys->i_next_vobu,
                           1, p_buffer ) != 1 )
        {
            msg_Err( p_demux, "read failed for block %d", p_sys->i_next_vobu );
            vlc_dialog_display_error( p_demux, _("Playback failure"),
                          _("DVDRead could not read block %d."),
                          p_sys->i_next_vobu );
            return -1;
        }

        /* Basic check to be sure we don't have a empty title
         * go to next title if so */
        //assert( p_buffer[41] == 0xbf && p_buffer[1027] == 0xbf );
        DemuxBlock( p_demux, p_buffer, DVD_VIDEO_LB_LEN );

        /* Parse the contained dsi packet */
        DvdReadHandleDSI( p_demux, p_buffer );

        /* End of title */
        if( p_sys->i_cur_cell >= p_sys->p_cur_pgc->nr_of_cells )
        {
            int k = p_sys->i_title;

            /* Looking for a not broken title */
            while( k < p_sys->i_titles && DvdReadSetArea( p_demux, ++k, 0, -1 ) != VLC_SUCCESS )
            {
                msg_Err(p_demux, "Failed next title, trying another: %i", k );
                if( k >= p_sys->i_titles )
                    return 0; // EOF
            }
        }

        if( p_sys->i_pack_len >= 1024 )
        {
            msg_Err( p_demux, "i_pack_len >= 1024 (%i). "
                     "This shouldn't happen!", p_sys->i_pack_len );
            return 0; /* EOF */
        }

        p_sys->i_cur_block++;
        p_sys->i_title_offset++;
    }

    if( p_sys->i_cur_cell >= p_sys->p_cur_pgc->nr_of_cells )
    {
        int k = p_sys->i_title;

        /* Looking for a not broken title */
        while( k < p_sys->i_titles && DvdReadSetArea( p_demux, ++k, 0, -1 ) != VLC_SUCCESS )
        {
            msg_Err(p_demux, "Failed next title, trying another: %i", k );
            if( k >= p_sys->i_titles )
                return 0; // EOF
        }
    }

    /*
     * Read actual data
     */
    i_blocks_once = __MIN( p_sys->i_pack_len, DVD_BLOCK_READ_ONCE );
    p_sys->i_pack_len -= i_blocks_once;

    /* Reads from DVD */
    i_read = DVDReadBlocks( p_sys->p_title, p_sys->i_cur_block,
                            i_blocks_once, p_buffer );
    if( i_read != i_blocks_once )
    {
        msg_Err( p_demux, "read failed for %d/%d blocks at 0x%02x",
                 i_read, i_blocks_once, p_sys->i_cur_block );
        vlc_dialog_display_error( p_demux, _("Playback failure"),
                        _("DVDRead could not read %d/%d blocks at 0x%02x."),
                        i_read, i_blocks_once, p_sys->i_cur_block );
        return -1;
    }

    p_sys->i_cur_block += i_read;
    p_sys->i_title_offset += i_read;

#if 0
    msg_Dbg( p_demux, "i_blocks: %d len: %d current: 0x%02x",
             i_read, p_sys->i_pack_len, p_sys->i_cur_block );
#endif

    for( int i = 0; i < i_read; i++ )
    {
        DemuxBlock( p_demux, p_buffer + i * DVD_VIDEO_LB_LEN,
                    DVD_VIDEO_LB_LEN );
    }

#undef p_pgc

    return 1;
}

/*****************************************************************************
 * DemuxBlock: demux a given block
 *****************************************************************************/
static int DemuxBlock( demux_t *p_demux, const uint8_t *p, int len )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    while( len > 0 )
    {
        int i_size = ps_pkt_size( p, len );
        if( i_size <= 0 || i_size > len )
        {
            break;
        }

        /* Create a block */
        block_t *p_pkt = block_Alloc( i_size );
        memcpy( p_pkt->p_buffer, p, i_size);

        /* Parse it and send it */
        switch( 0x100 | p[3] )
        {
        case 0x1b9:
        case 0x1bb:
        case 0x1bc:

#ifdef DVDREAD_DEBUG
            if( p[3] == 0xbc )
            {
                msg_Warn( p_demux, "received a PSM packet" );
            }
            else if( p[3] == 0xbb )
            {
                msg_Warn( p_demux, "received a SYSTEM packet" );
            }
#endif
            block_Release( p_pkt );
            break;

        case 0x1ba:
        {
            int64_t i_scr;
            int i_mux_rate;
            if( !ps_pkt_parse_pack( p_pkt, &i_scr, &i_mux_rate ) )
            {
                es_out_SetPCR( p_demux->out, VLC_TICK_0 + i_scr );
                if( i_mux_rate > 0 ) p_sys->i_mux_rate = i_mux_rate;
            }
            block_Release( p_pkt );
            break;
        }
        default:
        {
            int i_id = ps_pkt_id( p_pkt, p_sys->b_audio ? PS_SOURCE_AOB
                                                        : PS_SOURCE_VOB );
            if( i_id >= 0xc0 )
            {
                ps_track_t *tk = &p_sys->tk[ps_id_to_tk(i_id)];

                if( !tk->b_configured )
                {
                    ESNew( p_demux, i_id, 0, 0 );
                }
                if( tk->es &&
                    !ps_pkt_parse_pes( VLC_OBJECT(p_demux), p_pkt, tk->i_skip ) )
                {
                    es_out_Send( p_demux->out, tk->es, p_pkt );
                }
                else
                {
                    block_Release( p_pkt );
                }
            }
            else
            {
                block_Release( p_pkt );
            }
            break;
        }
        }

        p += i_size;
        len -= i_size;
    }

    return VLC_SUCCESS;
}

/*****************************************************************************
 * ESNew: register a new elementary stream
 *****************************************************************************/
static void ESNew( demux_t *p_demux, int i_id, int i_lang, int i_code_ext )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    ps_track_t  *tk = &p_sys->tk[ps_id_to_tk(i_id)];
    char psz_language[3];

    if( tk->b_configured ) return;

    if( ps_track_fill( tk, NULL, i_id, NULL, true ) )
    {
        msg_Warn( p_demux, "unknown codec for id=0x%x", i_id );
        return;
    }

    psz_language[0] = psz_language[1] = psz_language[2] = 0;
    if( i_lang && i_lang != 0xffff )
    {
        psz_language[0] = (i_lang >> 8)&0xff;
        psz_language[1] = (i_lang     )&0xff;
    }

    /* Add a new ES */
    if( tk->fmt.i_cat == VIDEO_ES )
    {
        tk->fmt.video.i_sar_num = p_sys->i_sar_num;
        tk->fmt.video.i_sar_den = p_sys->i_sar_den;
    }
    else if( tk->fmt.i_cat == AUDIO_ES )
    {
#if 0
        int i_audio = -1;
        /* find the audio number PLEASE find another way */
        if( (i_id&0xbdf8) == 0xbd88 )       /* dts */
        {
            i_audio = i_id&0x07;
        }
        else if( (i_id&0xbdf0) == 0xbd80 )  /* a52 */
        {
            i_audio = i_id&0xf;
        }
        else if( (i_id&0xbdf0) == 0xbda0 )  /* lpcm */
        {
            i_audio = i_id&0x1f;
        }
        else if( ( i_id&0xe0 ) == 0xc0 )    /* mpga */
        {
            i_audio = i_id&0x1f;
        }
#endif

        if( psz_language[0] ) tk->fmt.psz_language = strdup( psz_language );

        if( (size_t) i_code_ext < ARRAY_SIZE(dvd_audio_code_ext)
            && dvd_audio_code_ext[i_code_ext] )
            tk->fmt.psz_description =
                strdup( vlc_gettext( dvd_audio_code_ext[i_code_ext] ) );
    }
    else if( tk->fmt.i_cat == SPU_ES )
    {
        /* Palette */
        tk->fmt.subs.spu.palette[0] = SPU_PALETTE_DEFINED;
        memcpy( &tk->fmt.subs.spu.palette[1], p_sys->clut,
                16 * sizeof( uint32_t ) );

        if( psz_language[0] ) tk->fmt.psz_language = strdup( psz_language );

        if( (size_t) i_code_ext < ARRAY_SIZE(dvd_spu_code_ext)
            && dvd_spu_code_ext[i_code_ext] )
            tk->fmt.psz_description =
                strdup( vlc_gettext( dvd_spu_code_ext[i_code_ext] ) );

        if( i_code_ext == DVD_SUBP_CODE_EXT_FORCED )
            tk->fmt.subs.b_forced = true;
    }

    tk->es = es_out_Add( p_demux->out, &tk->fmt );
    tk->b_configured = true;
}

/*****************************************************************************
 * DvdReadSetArea: initialize input data for title x, chapter y.
 * It should be called for each user navigation request.
 *****************************************************************************
 * Take care that i_title and i_chapter start from 0.
 *****************************************************************************/
/*****************************************************************************
 * Time axis
 *****************************************************************************/

/* Returns the cell actually played at i_cell -- the selected angle when
 * i_cell opens an angle block -- and, through pi_next, the first cell after
 * the whole block. Mirrors DvdReadFindCell so that the time table, the seek
 * and the reader all walk the same path. */
static int DvdReadPlayedCellIn( pgc_t *p_pgc, int i_angle, int i_cell,
                                int *pi_next )
{
    int i_played = i_cell;

    if( p_pgc->cell_playback[i_cell].block_type == BLOCK_TYPE_ANGLE_BLOCK )
    {
        int i = 0;
        while( i_cell + i < p_pgc->nr_of_cells - 1 &&
               p_pgc->cell_playback[i_cell + i].block_mode !=
                   BLOCK_MODE_LAST_CELL )
            i++;
        *pi_next = i_cell + i + 1;

        i_played = i_cell + i_angle - 1;
        if( i_played > i_cell + i )
            i_played = i_cell;      /* angle beyond the block: play the first */
    }
    else
        *pi_next = i_cell + 1;

    return i_played;
}

static int DvdReadPlayedCell( demux_sys_t *p_sys, int i_cell, int *pi_next )
{
    return DvdReadPlayedCellIn( p_sys->p_cur_pgc, p_sys->i_angle, i_cell,
                                pi_next );
}

/* Number of blocks of the played path, and the start time of every cell. */
static void DvdReadBuildTimeTable( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    pgc_t *p_pgc = p_sys->p_cur_pgc;

    free( p_sys->p_cell_start_time );
    p_sys->p_cell_start_time = NULL;
    p_sys->i_cell_count = 0;
    p_sys->i_title_time = 0;

    if( p_pgc == NULL || p_pgc->cell_playback == NULL ||
        p_pgc->nr_of_cells <= 0 )
        return;

    int64_t *p_time = calloc( p_pgc->nr_of_cells, sizeof(*p_time) );
    if( unlikely( p_time == NULL ) )
        return;

    vlc_tick_t i_acc = 0;
    int i_cell = p_sys->i_title_start_cell;
    while( i_cell >= 0 && i_cell <= p_sys->i_title_end_cell )
    {
        int i_next;
        const int i_played = DvdReadPlayedCell( p_sys, i_cell, &i_next );

        /* every angle of the block starts at the same point of the title */
        for( int i = i_cell; i < i_next && i <= p_sys->i_title_end_cell; i++ )
            p_time[i] = i_acc;

        i_acc += dvdtime_to_time(
            &p_pgc->cell_playback[i_played].playback_time, 0 );

        if( i_next <= i_cell )      /* never trust the disc to move forward */
            break;
        i_cell = i_next;
    }

    p_sys->p_cell_start_time = p_time;
    p_sys->i_cell_count = p_pgc->nr_of_cells;
    p_sys->i_title_time = i_acc;
}

/* Where the read head is, in title time. The start of the current cell plus
 * the elapsed time the disc itself publishes in the navigation pack of the
 * current VOBU (c_eltm) -- which the demuxer already decodes and, until now,
 * threw away. Nothing is interpolated, so this cannot drift. */
static vlc_tick_t DvdReadCurrentTime( demux_sys_t *p_sys )
{
    if( p_sys->p_cell_start_time == NULL || p_sys->i_cur_cell < 0 ||
        p_sys->i_cur_cell >= p_sys->i_cell_count )
        return 0;

    vlc_tick_t i_time = p_sys->p_cell_start_time[p_sys->i_cur_cell] +
                        p_sys->i_cell_cur_time;
    if( i_time < 0 )
        i_time = 0;
    if( p_sys->i_title_time > 0 && i_time > p_sys->i_title_time )
        i_time = p_sys->i_title_time;
    return i_time;
}

/* Title time -> title-relative block offset, walking the played path so the
 * result feeds DvdReadSeek unchanged. Inside the target cell the only ruler
 * available is that cell's own duration; DvdReadSeek then snaps to a real
 * VOBU and the next navigation pack re-syncs the clock exactly, so the
 * approximation never accumulates. */
static int DvdReadTimeToBlock( demux_sys_t *p_sys, vlc_tick_t i_time )
{
    pgc_t *p_pgc = p_sys->p_cur_pgc;
    int i_block_offset = 0;
    int i_cell = p_sys->i_title_start_cell;

    if( p_sys->p_cell_start_time == NULL )
        return 0;

    while( i_cell >= 0 && i_cell <= p_sys->i_title_end_cell )
    {
        int i_next;
        const int i_played = DvdReadPlayedCell( p_sys, i_cell, &i_next );
        const vlc_tick_t i_start = p_sys->p_cell_start_time[i_cell];
        const vlc_tick_t i_duration = dvdtime_to_time(
            &p_pgc->cell_playback[i_played].playback_time, 0 );
        const uint32_t i_blocks =
            p_pgc->cell_playback[i_played].last_sector -
            p_pgc->cell_playback[i_played].first_sector + 1;

        if( i_time < i_start + i_duration ||
            i_next > p_sys->i_title_end_cell || i_next <= i_cell )
        {
            if( i_duration > 0 && i_time > i_start )
            {
                double f = (double)( i_time - i_start ) / (double)i_duration;
                if( f > 1.0 )
                    f = 1.0;
                i_block_offset += (int)( f * i_blocks );
            }
            return i_block_offset;
        }

        i_block_offset += i_blocks;
        i_cell = i_next;
    }

    return i_block_offset;
}

static int DvdReadSetArea( demux_t *p_demux, int i_title, int i_chapter,
                           int i_angle )
{
    VLC_UNUSED( i_angle );

    demux_sys_t *p_sys = p_demux->p_sys;
    int pgc_id = 0, pgn = 0;

#define p_pgc p_sys->p_cur_pgc
#define p_vmg p_sys->p_vmg_file
#define p_vts p_sys->p_vts_file

    if( i_title >= 0 && i_title < p_sys->i_titles &&
        i_title != p_sys->i_title )
    {
        int i_start_cell, i_end_cell;

        if( p_sys->p_title != NULL )
        {
            DVDCloseFile( p_sys->p_title );
            p_sys->p_title = NULL;
        }
        if( p_vts != NULL ) ifoClose( p_vts );
        p_sys->i_title = i_title;

        /*
         *  We have to load all title information
         */
        msg_Dbg( p_demux, "open VTS %d, for title %d",
                 p_vmg->tt_srpt->title[i_title].title_set_nr, i_title + 1 );

        /* Ifo vts */
        if( !( p_vts = ifoOpen( p_sys->p_dvdread,
               p_vmg->tt_srpt->title[i_title].title_set_nr ) ) )
        {
            msg_Err( p_demux, "fatal error in vts ifo" );
            return VLC_EGENERIC;
        }

        /* Title position inside the selected vts */
        p_sys->i_ttn = p_vmg->tt_srpt->title[i_title].vts_ttn;

        /* Find title start/end */
        pgc_id = p_vts->vts_ptt_srpt->title[p_sys->i_ttn - 1].ptt[0].pgcn;
        pgn = p_vts->vts_ptt_srpt->title[p_sys->i_ttn - 1].ptt[0].pgn;
        p_pgc = p_vts->vts_pgcit->pgci_srp[pgc_id - 1].pgc;

        if( p_pgc->cell_playback == NULL )
        {
            msg_Err( p_demux, "Invalid PGC (cell_playback_offset)" );
            return VLC_EGENERIC;
        }

        p_sys->i_title_start_cell =
            i_start_cell = p_pgc->program_map[pgn - 1] - 1;
        p_sys->i_title_start_block =
            p_pgc->cell_playback[i_start_cell].first_sector;

        p_sys->i_title_end_cell =
            i_end_cell = p_pgc->nr_of_cells - 1;
        p_sys->i_title_end_block =
            p_pgc->cell_playback[i_end_cell].last_sector;

        p_sys->i_title_offset = 0;

        /* Count the played path only. Summing every cell of an angle block
         * counted the same seconds two or three times over, so the title came
         * out longer than it is and the read head never reached the end of
         * its own scale. */
        p_sys->i_title_blocks = 0;
        for( int i = i_start_cell; i >= 0 && i <= i_end_cell; )
        {
            int i_next;
            const int i_played = DvdReadPlayedCell( p_sys, i, &i_next );
            const uint32_t cell_blocks =
                p_pgc->cell_playback[i_played].last_sector -
                p_pgc->cell_playback[i_played].first_sector + 1;
            if(unlikely( cell_blocks == 0 || cell_blocks > INT_MAX ||
                 INT_MAX - p_sys->i_title_blocks < (int)cell_blocks ))
                return VLC_EGENERIC;
            p_sys->i_title_blocks += cell_blocks;
            if( i_next <= i )
                break;
            i = i_next;
        }

        DvdReadBuildTimeTable( p_demux );

        msg_Dbg( p_demux, "title %d vts_title %d pgc %d pgn %d "
                 "start %d end %d blocks: %d",
                 i_title + 1, p_sys->i_ttn, pgc_id, pgn,
                 p_sys->i_title_start_block, p_sys->i_title_end_block,
                 p_sys->i_title_blocks );

        /*
         * Set properties for current chapter
         */
        p_sys->i_chapter = 0;
        p_sys->i_chapters =
            p_vts->vts_ptt_srpt->title[p_sys->i_ttn - 1].nr_of_ptts;

        pgc_id = p_vts->vts_ptt_srpt->title[
                    p_sys->i_ttn - 1].ptt[p_sys->i_chapter].pgcn;
        pgn = p_vts->vts_ptt_srpt->title[
                    p_sys->i_ttn - 1].ptt[p_sys->i_chapter].pgn;

        p_pgc = p_vts->vts_pgcit->pgci_srp[pgc_id - 1].pgc;
        p_sys->i_pack_len = 0;
        p_sys->i_next_cell =
            p_sys->i_cur_cell = p_pgc->program_map[pgn - 1] - 1;
        DvdReadFindCell( p_demux );

        p_sys->i_next_vobu = p_sys->i_cur_block =
            p_pgc->cell_playback[p_sys->i_cur_cell].first_sector;

        /*
         * Angle management
         */
        p_sys->i_angles = p_vmg->tt_srpt->title[i_title].nr_of_angles;
        if( p_sys->i_angle > p_sys->i_angles ) p_sys->i_angle = 1;

        /*
         * We've got enough info, time to open the title set data.
         */
        if( !( p_sys->p_title = DVDOpenFile( p_sys->p_dvdread,
            p_vmg->tt_srpt->title[i_title].title_set_nr,
            DVD_READ_TITLE_VOBS ) ) )
        {
            msg_Err( p_demux, "cannot open title (VTS_%02d_1.VOB)",
                     p_vmg->tt_srpt->title[i_title].title_set_nr );
            return VLC_EGENERIC;
        }

        //IfoPrintTitle( p_demux );

        /*
         * Destroy obsolete ES by reinitializing program 0
         * and find all ES in title with ifo data
         */
        es_out_Control( p_demux->out, ES_OUT_RESET_PCR );

        for( int i = 0; i < PS_TK_COUNT; i++ )
        {
            ps_track_t *tk = &p_sys->tk[i];
            if( tk->b_configured )
            {
                es_format_Clean( &tk->fmt );
                if( tk->es ) es_out_Del( p_demux->out, tk->es );
            }
            tk->b_configured = false;
        }

        if( p_demux->info.i_title != i_title )
        {
            p_demux->info.i_update |=
                INPUT_UPDATE_TITLE | INPUT_UPDATE_SEEKPOINT;
            p_demux->info.i_title = i_title;
            p_demux->info.i_seekpoint = 0;
        }

        /* TODO: re-add angles */


        ESNew( p_demux, 0xe0, 0, 0 ); /* Video, FIXME ? */
        const video_attr_t *p_attr = &p_vts->vtsi_mat->vts_video_attr;
        int i_video_height = p_attr->video_format != 0 ? 576 : 480;
        int i_video_width;
        switch( p_attr->picture_size )
        {
        case 0:
            i_video_width = 720;
            break;
        case 1:
            i_video_width = 704;
            break;
        case 2:
            i_video_width = 352;
            break;
        default:
        case 3:
            i_video_width = 352;
            i_video_height /= 2;
            break;
        }
        switch( p_attr->display_aspect_ratio )
        {
        case 0:
            p_sys->i_sar_num = 4 * i_video_height;
            p_sys->i_sar_den = 3 * i_video_width;
            break;
        case 3:
            p_sys->i_sar_num = 16 * i_video_height;
            p_sys->i_sar_den =  9 * i_video_width;
            break;
        default:
            p_sys->i_sar_num = 0;
            p_sys->i_sar_den = 0;
            break;
        }

#define audio_control \
    p_sys->p_vts_file->vts_pgcit->pgci_srp[pgc_id-1].pgc->audio_control[i-1]

        /* Audio ES, in the order they appear in the .ifo */
        for( int i = 1; i <= p_vts->vtsi_mat->nr_of_vts_audio_streams; i++ )
        {
            int i_position = 0;
            uint16_t i_id;

            //IfoPrintAudio( p_demux, i );

            /* Audio channel is active if first byte is 0x80 */
            if( audio_control & 0x8000 )
            {
                i_position = ( audio_control & 0x7F00 ) >> 8;

                msg_Dbg( p_demux, "audio position  %d", i_position );
                switch( p_vts->vtsi_mat->vts_audio_attr[i - 1].audio_format )
                {
                case 0x00: /* A52 */
                    i_id = (0x80 + i_position) | PS_PACKET_ID_MASK_VOB;
                    break;
                case 0x02:
                case 0x03: /* MPEG audio */
                    i_id = 0xc000 + i_position;
                    break;
                case 0x04: /* LPCM */
                    i_id = (0xa0 + i_position) | PS_PACKET_ID_MASK_VOB;
                    break;
                case 0x06: /* DTS */
                    i_id = (0x88 + i_position) | PS_PACKET_ID_MASK_VOB;
                    break;
                default:
                    i_id = 0;
                    msg_Err( p_demux, "unknown audio type %.2x",
                        p_vts->vtsi_mat->vts_audio_attr[i - 1].audio_format );
                }

                ESNew( p_demux, i_id, p_sys->p_vts_file->vtsi_mat->
                       vts_audio_attr[i - 1].lang_code,
                       p_sys->p_vts_file->vtsi_mat->
                       vts_audio_attr[i - 1].code_extension );
            }
        }
#undef audio_control

#define spu_palette \
    p_sys->p_vts_file->vts_pgcit->pgci_srp[pgc_id-1].pgc->palette

        memcpy( p_sys->clut, spu_palette, 16 * sizeof( uint32_t ) );

#define spu_control \
    p_sys->p_vts_file->vts_pgcit->pgci_srp[pgc_id-1].pgc->subp_control[i-1]

        /* Sub Picture ES */
        for( int i = 1; i <= p_vts->vtsi_mat->nr_of_vts_subp_streams; i++ )
        {
            int i_position = 0;
            uint16_t i_id;

            //IfoPrintSpu( p_sys, i );
            msg_Dbg( p_demux, "spu %d 0x%02x", i, spu_control );

            if( spu_control & 0x80000000 )
            {
                /*  there are several streams for one spu */
                if( p_vts->vtsi_mat->vts_video_attr.display_aspect_ratio )
                {
                    /* 16:9 */
                    switch( p_vts->vtsi_mat->vts_video_attr.permitted_df )
                    {
                    case 1: /* letterbox */
                        i_position = spu_control & 0xff;
                        break;
                    case 2: /* pan&scan */
                        i_position = ( spu_control >> 8 ) & 0xff;
                        break;
                    default: /* widescreen */
                        i_position = ( spu_control >> 16 ) & 0xff;
                        break;
                    }
                }
                else
                {
                    /* 4:3 */
                    i_position = ( spu_control >> 24 ) & 0x7F;
                }

                i_id = (0x20 + i_position) | PS_PACKET_ID_MASK_VOB;

                ESNew( p_demux, i_id, p_sys->p_vts_file->vtsi_mat->
                       vts_subp_attr[i - 1].lang_code,
                       p_sys->p_vts_file->vtsi_mat->
                       vts_subp_attr[i - 1].code_extension );
            }
        }
#undef spu_control

    }
    else if( i_title != -1 && i_title != p_sys->i_title )

    {
        return VLC_EGENERIC; /* Couldn't set title */
    }

    /*
     * Chapter selection
     */

    if( i_chapter >= 0 && i_chapter < p_sys->i_chapters )
    {
        pgc_id = p_vts->vts_ptt_srpt->title[
                     p_sys->i_ttn - 1].ptt[i_chapter].pgcn;
        pgn = p_vts->vts_ptt_srpt->title[
                  p_sys->i_ttn - 1].ptt[i_chapter].pgn;

        p_pgc = p_vts->vts_pgcit->pgci_srp[pgc_id - 1].pgc;
        if( p_pgc->cell_playback == NULL )
            return VLC_EGENERIC; /* Couldn't set chapter */

        p_sys->i_cur_cell = p_pgc->program_map[pgn - 1] - 1;
        p_sys->i_chapter = i_chapter;
        DvdReadFindCell( p_demux );

        p_sys->i_title_offset = 0;
        for( int i = p_sys->i_title_start_cell; i < p_sys->i_cur_cell; i++ )
        {
            p_sys->i_title_offset += p_pgc->cell_playback[i].last_sector -
                p_pgc->cell_playback[i].first_sector + 1;
        }

        p_sys->i_pack_len = 0;
        p_sys->i_next_vobu = p_sys->i_cur_block =
            p_pgc->cell_playback[p_sys->i_cur_cell].first_sector;

        if( p_demux->info.i_seekpoint != i_chapter )
        {
            p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;
            p_demux->info.i_seekpoint = i_chapter;
        }
    }
    else if( i_chapter != -1 )

    {
        return VLC_EGENERIC; /* Couldn't set chapter */
    }

#undef p_pgc
#undef p_vts
#undef p_vmg

    return VLC_SUCCESS;
}

/*****************************************************************************
 * DvdReadSeek : Goes to a given position on the stream.
 *****************************************************************************
 * This one is used by the input and translate chronological position from
 * input to logical position on the device.
 *****************************************************************************/
static int DvdReadSeek( demux_t *p_demux, int i_block_offset )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    int i_chapter = 0;
    int i_cell = 0;
    int i_block;

#define p_pgc p_sys->p_cur_pgc
#define p_vts p_sys->p_vts_file

    /* Find cell, along the played path: an offset in blocks has to mean the
     * same thing here as in the time table and in i_title_blocks, otherwise a
     * click lands somewhere else than where it was aimed on an angle title.
     * i_cell stays the cell that OPENS the block -- DvdReadFindCell below
     * applies the angle to it -- while the arithmetic uses the played one. */
    i_block = i_block_offset;
    int i_played_cell = -1;
    for( i_cell = p_sys->i_title_start_cell;
         i_cell >= 0 && i_cell <= p_sys->i_title_end_cell; )
    {
        int i_next;
        const int i_played = DvdReadPlayedCell( p_sys, i_cell, &i_next );
        const int i_cell_blocks =
            (int)p_pgc->cell_playback[i_played].last_sector -
            (int)p_pgc->cell_playback[i_played].first_sector + 1;

        if( i_block < i_cell_blocks )
        {
            i_played_cell = i_played;
            break;
        }
        i_block -= i_cell_blocks;

        if( i_next <= i_cell )
            break;
        i_cell = i_next;
    }
    if( i_played_cell < 0 )
    {
        msg_Err( p_demux, "couldn't find cell for block %i", i_block_offset );
        return VLC_EGENERIC;
    }
    i_block += p_pgc->cell_playback[i_played_cell].first_sector;
    p_sys->i_title_offset = i_block_offset;

    /* Find chapter */
    for( i_chapter = 0; i_chapter < p_sys->i_chapters; i_chapter++ )
    {
        int pgc_id, pgn, i_tmp;

        pgc_id = p_vts->vts_ptt_srpt->title[
                    p_sys->i_ttn - 1].ptt[i_chapter].pgcn;
        pgn = p_vts->vts_ptt_srpt->title[
                    p_sys->i_ttn - 1].ptt[i_chapter].pgn;

        i_tmp = p_vts->vts_pgcit->pgci_srp[pgc_id - 1].pgc->program_map[pgn-1];

        if( i_tmp > i_cell ) break;
    }

    if( i_chapter < p_sys->i_chapters &&
        p_demux->info.i_seekpoint != i_chapter )
    {
        p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;
        p_demux->info.i_seekpoint = i_chapter;
    }

    /* Find vobu */
    /* see ifo_read.c / ifoRead_VOBU_ADMAP_internal for index count */
    int i_vobu = 1;
    const size_t i_vobu_sect_index_count =
            (p_vts->vts_vobu_admap->last_byte + 1 - VOBU_ADMAP_SIZE) / sizeof(uint32_t);
    for( size_t i=0; i<i_vobu_sect_index_count; i++ )
    {
        if( p_vts->vts_vobu_admap->vobu_start_sectors[i] > (uint32_t) i_block )
            break;
        i_vobu = i + 1;
    }

#if 1
    int i_sub_cell = 1;
    /* Find sub_cell */
    /* need to check cell # <= vob count as cell table alloc only ensures:
     * info_length / sizeof(cell_adr_t) < c_adt->nr_of_vobs, see ifo_read.c */
    const uint32_t vobu_start_sector = p_vts->vts_vobu_admap->vobu_start_sectors[i_vobu-1];
    for( int i = 0; i + 1<p_vts->vts_c_adt->nr_of_vobs; i++ )
    {
        const cell_adr_t *p_cell = &p_vts->vts_c_adt->cell_adr_table[i];
        if(p_cell->start_sector <= vobu_start_sector)
           i_sub_cell = i + 1;
    }

    msg_Dbg( p_demux, "cell %d i_sub_cell %d chapter %d vobu %d "
             "cell_sector %d vobu_sector %d sub_cell_sector %d",
             i_cell, i_sub_cell, i_chapter, i_vobu,
             p_sys->p_cur_pgc->cell_playback[i_cell].first_sector,
             p_vts->vts_vobu_admap->vobu_start_sectors[i_vobu],
             p_vts->vts_c_adt->cell_adr_table[i_sub_cell - 1].start_sector);
#endif

    p_sys->i_cur_block = i_block;
    if(likely( (size_t)i_vobu < i_vobu_sect_index_count ))
        p_sys->i_next_vobu = p_vts->vts_vobu_admap->vobu_start_sectors[i_vobu];
    else
        p_sys->i_next_vobu = i_block;
    p_sys->i_pack_len = p_sys->i_next_vobu - i_block;
    p_sys->i_cur_cell = i_cell;
    p_sys->i_chapter = i_chapter;
    DvdReadFindCell( p_demux );

#undef p_vts
#undef p_pgc

    return VLC_SUCCESS;
}

#ifdef DVDREAD_HAS_DVDAUDIO
/*****************************************************************************
 * DVD-Audio (AUDIO_TS zone): an ATS is a "group", its titles hold tracks
 * ("trackpoints") laid out linearly in ATS_XX_[1-9].AOB -- plain MPEG-PS
 * with LPCM/MLP substreams, no cells and no NAV/DSI packets.
 * Ported from VLC 4.0's dvdread_audio.c (monolithic 3.0 layout).
 *****************************************************************************/

/*****************************************************************************
 * DvdReadSetAreaAudio: initialize input data for title x, track y.
 *****************************************************************************/
static int DvdReadSetAreaAudio( demux_t *p_demux, int i_title, int i_track )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    const ifo_handle_t *p_amg = p_sys->p_vmg_file;

    if( i_title >= 0 && i_title < p_sys->i_titles &&
        i_title != p_sys->i_title )
    {
        const track_info_t *p_track_info =
            &p_amg->info_table_second_sector->tracks_info[i_title];

        if( p_sys->p_title != NULL )
        {
            DVDCloseFile( p_sys->p_title );
            p_sys->p_title = NULL;
        }
        p_sys->i_title = i_title;

        /* Open the ATS ifo of this group (reusing the p_vts_file slot) */
        msg_Dbg( p_demux, "open ATS %d, for group %d",
                 p_track_info->group_property, i_title + 1 );
        if( p_sys->p_vts_file != NULL )
            ifoClose( p_sys->p_vts_file );
        if( !( p_sys->p_vts_file = ifoOpen( p_sys->p_dvdread,
                                            p_track_info->group_property ) ) )
        {
            msg_Err( p_demux, "fatal error in ats ifo" );
            return VLC_EGENERIC;
        }

        const ifo_handle_t *p_ats = p_sys->p_vts_file;

        /* Title position inside the selected ats,
         * i_title is the overall title number */
        p_sys->i_ttn = p_track_info->title_property;

        if( p_ats->atsi_title_table == NULL || p_sys->i_ttn == 0
         || p_sys->i_ttn > p_ats->atsi_title_table->nr_titles )
        {
            msg_Err( p_demux, "invalid ats title %d", i_title );
            return VLC_EGENERIC;
        }

        atsi_title_record_t *p_title_rec = p_sys->p_title_table =
            &p_ats->atsi_title_table->atsi_title_row_tables[p_sys->i_ttn - 1];

        p_sys->i_chapter = 0;
        p_sys->i_chapters = p_title_rec->nr_pointer_records;
        if( p_sys->i_chapters <= 0 )
        {
            msg_Err( p_demux, "invalid track count for title %d", i_title );
            return VLC_EGENERIC;
        }

        /* No cells in dvd audio, only the start and end sectors of the title */
        p_sys->i_title_start_block =
            p_title_rec->atsi_track_pointer_rows[0].start_sector;
        p_sys->i_title_end_block =
            p_title_rec->atsi_track_pointer_rows[p_sys->i_chapters - 1].end_sector;
        p_sys->i_title_blocks =
            p_sys->i_title_end_block - p_sys->i_title_start_block + 1;
        p_sys->i_title_offset = 0;
        p_sys->i_pack_len = 0;
        msg_Dbg( p_demux, "title %d ttn %d start %d end %d blocks: %d",
                 i_title, p_sys->i_ttn,
                 p_sys->i_title_start_block, p_sys->i_title_end_block,
                 p_sys->i_title_blocks );

        /* Time to open the AOB set of this group */
        if( !( p_sys->p_title = DVDOpenFile( p_sys->p_dvdread,
               p_track_info->group_property, DVD_READ_TITLE_VOBS ) ) )
        {
            msg_Err( p_demux, "cannot open title (ATS_%02d_1.AOB)",
                     p_track_info->group_property );
            return VLC_EGENERIC;
        }

        /*
         * Destroy obsolete ES by reinitializing program 0
         * and find all ES in title with ifo data
         */
        es_out_Control( p_demux->out, ES_OUT_RESET_PCR );

        for( int i = 0; i < PS_TK_COUNT; i++ )
        {
            ps_track_t *tk = &p_sys->tk[i];
            if( tk->b_configured )
            {
                es_format_Clean( &tk->fmt );
                if( tk->es ) es_out_Del( p_demux->out, tk->es );
            }
            tk->b_configured = false;
        }

        if( p_demux->info.i_title != i_title )
        {
            p_demux->info.i_update |=
                INPUT_UPDATE_TITLE | INPUT_UPDATE_SEEKPOINT;
            p_demux->info.i_title = i_title;
            p_demux->info.i_seekpoint = 0;
        }
    }
    else if( i_title != -1 && i_title != p_sys->i_title )
    {
        return VLC_EGENERIC; /* Couldn't set title */
    }

    /*
     * Track (chapter) selection
     */
    if( i_track >= 0 && i_track < p_sys->i_chapters )
    {
        const atsi_track_pointer_t *rows =
            p_sys->p_title_table->atsi_track_pointer_rows;

        p_sys->i_chapter = i_track;
        p_sys->i_title_offset =
            rows[i_track].start_sector - rows[0].start_sector;
        p_sys->i_pack_len = 0;
        /* current block relative to start of the AOB set */
        p_sys->i_cur_block = rows[i_track].start_sector;

        if( p_demux->info.i_seekpoint != i_track )
        {
            p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;
            p_demux->info.i_seekpoint = i_track;
        }
    }
    else if( i_track != -1 )
    {
        msg_Dbg( p_demux, "Couldn't set track" );
        return VLC_EGENERIC;
    }

    return VLC_SUCCESS;
}

/*****************************************************************************
 * DvdReadSeekAudio: seek to a title-relative block offset
 *****************************************************************************/
static int DvdReadSeekAudio( demux_t *p_demux, int i_block_offset )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    const atsi_track_pointer_t *rows =
        p_sys->p_title_table->atsi_track_pointer_rows;
    int i_chapter;
    int i_seek_blocks = 0;

    if( i_block_offset < 0 )
        i_block_offset = 0;

    /* Find the track containing the offset */
    for( i_chapter = 0; i_chapter < p_sys->i_chapters; i_chapter++ )
    {
        const int i_chapter_len = rows[i_chapter].end_sector -
                                  rows[i_chapter].start_sector + 1;

        if( i_block_offset < i_seek_blocks + i_chapter_len )
            break;

        i_seek_blocks += i_chapter_len;
    }

    if( i_chapter >= p_sys->i_chapters )
        return VLC_EGENERIC;

    if( p_demux->info.i_seekpoint != i_chapter )
    {
        p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;
        p_demux->info.i_seekpoint = i_chapter;
    }

    /* i_block_offset is title-relative, i_seek_blocks is the track start */
    p_sys->i_cur_block = rows[i_chapter].start_sector +
                         ( i_block_offset - i_seek_blocks );
    if( p_sys->i_cur_block <= p_sys->i_title_end_block )
        p_sys->i_pack_len = p_sys->i_title_end_block - p_sys->i_cur_block + 1;
    else
        p_sys->i_pack_len = 0;
    p_sys->i_title_offset = i_block_offset;
    p_sys->i_chapter = i_chapter;

    return VLC_SUCCESS;
}

/*****************************************************************************
 * DemuxTitlesAudio: build the title/track table from the AMG
 *****************************************************************************/
static void DemuxTitlesAudio( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    input_title_t *t = NULL;
    seekpoint_t *s;
    ifo_handle_t *p_ats_ifo = NULL;

    /* Find out number of titles/tracks */
    const int i_titles =
        p_sys->p_vmg_file->info_table_second_sector->nr_of_titles;
    msg_Dbg( p_demux, "number of titles: %d", i_titles );

    for( int i = 0; i < i_titles; i++ )
    {
        const track_info_t * const p_track_info =
            &p_sys->p_vmg_file->info_table_second_sector->tracks_info[i];
        int i_chapters = p_track_info->nr_chapters_in_title;
        msg_Dbg( p_demux, "title %d has %d tracks", i, i_chapters );

        t = vlc_input_title_New();
        if( unlikely( !t ) )
            return;

        const atsi_title_record_t *p_title_rec = NULL;
        t->i_length = DVDA_PTS_TO_TIME( p_track_info->len_audio_zone_pts );

        p_ats_ifo = ifoOpen( p_sys->p_dvdread, p_track_info->group_property );
        if( p_ats_ifo != NULL && p_ats_ifo->atsi_title_table != NULL
         && p_track_info->title_property > 0
         && p_track_info->title_property <= p_ats_ifo->atsi_title_table->nr_titles )
        {
            p_title_rec = &p_ats_ifo->atsi_title_table->
                atsi_title_row_tables[p_track_info->title_property - 1];
            i_chapters = p_title_rec->nr_pointer_records;
            t->i_length = DVDA_PTS_TO_TIME( p_title_rec->length_pts );
        }

        const atsi_track_pointer_t *rows =
            p_title_rec ? p_title_rec->atsi_track_pointer_rows : NULL;
        uint32_t first_sector = 0, blocks = 0;
        if( rows != NULL && p_title_rec->nr_pointer_records > 0 )
        {
            first_sector = rows[0].start_sector;
            const uint32_t end_sector =
                rows[p_title_rec->nr_pointer_records - 1].end_sector;
            if( end_sector >= first_sector )
                blocks = end_sector - first_sector + 1;
        }

        for( int j = 0; j < __MAX( i_chapters, 1 ); j++ )
        {
            s = vlc_seekpoint_New();
            if( unlikely( !s ) )
                goto fail;
            if( blocks > 0 && j < p_title_rec->nr_pointer_records )
            {
                const uint32_t offset = rows[j].start_sector - first_sector;
                s->i_time_offset = offset * t->i_length / blocks;
            }
            TAB_APPEND( t->i_seekpoint, t->seekpoint, s );
        }

        if( p_ats_ifo != NULL )
        {
            ifoClose( p_ats_ifo );
            p_ats_ifo = NULL;
        }

        TAB_APPEND( p_sys->i_titles, p_sys->titles, t );
        t = NULL;
    }
    return;

fail:
    if( p_ats_ifo != NULL )
        ifoClose( p_ats_ifo );
    if( t != NULL )
        vlc_input_title_Delete( t );
}

/*****************************************************************************
 * DemuxAudio: linear AOB playback, no cells and no NAV packets
 *****************************************************************************/
static int DemuxAudio( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    uint8_t p_buffer[DVD_VIDEO_LB_LEN * DVD_BLOCK_READ_ONCE];
    int i_blocks_once, i_read;

    if( !p_sys->i_pack_len )
    {
        if( p_sys->i_cur_block <= p_sys->i_title_end_block )
        {
            p_sys->i_pack_len =
                p_sys->i_title_end_block - p_sys->i_cur_block + 1;
        }
        else
        {
            /* End of title: look for the next playable one */
            int k = p_sys->i_title;

            while( k < p_sys->i_titles &&
                   DvdReadSetAreaAudio( p_demux, ++k, 0 ) != VLC_SUCCESS )
            {
                msg_Err( p_demux, "Failed next title, trying another: %i", k );
                if( k >= p_sys->i_titles )
                    return 0; // EOF
            }
            if( k >= p_sys->i_titles )
                return 0; // EOF
            p_sys->i_pack_len =
                p_sys->i_title_end_block - p_sys->i_cur_block + 1;
        }
    }

    /*
     * Read actual data
     */
    i_blocks_once = __MIN( p_sys->i_pack_len, DVD_BLOCK_READ_ONCE );
    p_sys->i_pack_len -= i_blocks_once;

    i_read = DVDReadBlocks( p_sys->p_title, p_sys->i_cur_block,
                            i_blocks_once, p_buffer );
    if( i_read != i_blocks_once )
    {
        msg_Err( p_demux, "read failed for %d/%d blocks at 0x%02x",
                 i_read, i_blocks_once, p_sys->i_cur_block );
        vlc_dialog_display_error( p_demux, _("Playback failure"),
                        _("DVDRead could not read %d/%d blocks at 0x%02x."),
                        i_read, i_blocks_once, p_sys->i_cur_block );
        return -1;
    }

    p_sys->i_cur_block += i_read;
    p_sys->i_title_offset += i_read;

    for( int i = 0; i < i_read; i++ )
    {
        DemuxBlock( p_demux, p_buffer + i * DVD_VIDEO_LB_LEN,
                    DVD_VIDEO_LB_LEN );
    }

    return 1;
}
#endif /* DVDREAD_HAS_DVDAUDIO */

/*****************************************************************************
 * DvdReadHandleDSI
 *****************************************************************************/
static void DvdReadHandleDSI( demux_t *p_demux, uint8_t *p_data )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    /* Check we are really on a DSI packet
     * http://www.mpucoder.com/DVD/dsi_pkt.html
     * Some think it's funny to fill with 0x42 */
    const uint8_t dsiheader[7] = { 0x00, 0x00, 0x01, 0xbf, 0x03, 0xfa, 0x01 };
    if(!memcmp(&p_data[DSI_START_BYTE-7], dsiheader, 7))
    {
        navRead_DSI( &p_sys->dsi_pack, &p_data[DSI_START_BYTE] );

        /*
         * Store the timecodes so we can get the current time
         */
        p_sys->i_title_cur_time = (vlc_tick_t) p_sys->dsi_pack.dsi_gi.nv_pck_scr / 90 * 1000;
        p_sys->i_cell_cur_time = (vlc_tick_t) dvdtime_to_time( &p_sys->dsi_pack.dsi_gi.c_eltm, 0 );

        /*
         * Determine where we go next.  These values are the ones we mostly
        * care about.
        */
        p_sys->i_cur_block = p_sys->dsi_pack.dsi_gi.nv_pck_lbn;
        p_sys->i_pack_len = p_sys->dsi_pack.dsi_gi.vobu_ea;

        /*
        * If we're not at the end of this cell, we can determine the next
        * VOBU to display using the VOBU_SRI information section of the
        * DSI.  Using this value correctly follows the current angle,
        * avoiding the doubled scenes in The Matrix, and makes our life
        * really happy.
        */

        p_sys->i_next_vobu = p_sys->i_cur_block +
            ( p_sys->dsi_pack.vobu_sri.next_vobu & 0x7fffffff );
    }
    else
    {
        /* resync after decoy/corrupted titles */
        msg_Warn(p_demux, "Invalid DSI packet in VOBU %d found, skipping Cell %d / %d",
                 p_sys->i_next_vobu, p_sys->i_cur_cell, p_sys->i_title_end_cell);
        p_sys->dsi_pack.vobu_sri.next_vobu = SRI_END_OF_CELL;
    }

    if( p_sys->dsi_pack.vobu_sri.next_vobu != SRI_END_OF_CELL
        && p_sys->i_angle > 1 )
    {
        switch( ( p_sys->dsi_pack.sml_pbi.category & 0xf000 ) >> 12 )
        {
        case 0x4:
            /* Interleaved unit with no angle */
            if( p_sys->dsi_pack.sml_pbi.ilvu_sa != 0 )
            {
                p_sys->i_next_vobu = p_sys->i_cur_block +
                    p_sys->dsi_pack.sml_pbi.ilvu_sa;
                p_sys->i_pack_len = p_sys->dsi_pack.sml_pbi.ilvu_ea;
            }
            else
            {
                p_sys->i_next_vobu = p_sys->i_cur_block +
                    p_sys->dsi_pack.dsi_gi.vobu_ea + 1;
            }
            break;
        case 0x5:
            /* vobu is end of ilvu */
            if( p_sys->dsi_pack.sml_agli.data[p_sys->i_angle-1].address )
            {
                p_sys->i_next_vobu = p_sys->i_cur_block +
                    p_sys->dsi_pack.sml_agli.data[p_sys->i_angle-1].address;
                p_sys->i_pack_len = p_sys->dsi_pack.sml_pbi.ilvu_ea;

                break;
            }
            /* fall through */
        case 0x6:
            /* vobu is beginning of ilvu */
        case 0x9:
            /* next scr is 0 */
        case 0xa:
            /* entering interleaved section */
        case 0x8:
            /* non interleaved cells in interleaved section */
        default:
            p_sys->i_next_vobu = p_sys->i_cur_block +
                ( p_sys->dsi_pack.vobu_sri.next_vobu & 0x7fffffff );
            break;
        }
    }
    else if( p_sys->dsi_pack.vobu_sri.next_vobu == SRI_END_OF_CELL )
    {
        p_sys->i_cur_cell = p_sys->i_next_cell;

        /* End of title */
        if( p_sys->i_cur_cell >= p_sys->p_cur_pgc->nr_of_cells ) return;

        DvdReadFindCell( p_demux );

        p_sys->i_next_vobu =
            p_sys->p_cur_pgc->cell_playback[p_sys->i_cur_cell].first_sector;

        p_sys->i_cell_duration = (vlc_tick_t)dvdtime_to_time( &p_sys->p_cur_pgc->cell_playback[p_sys->i_cur_cell].playback_time, 0 );
    }


#if 0
    msg_Dbg( p_demux, "scr %d lbn 0x%02x vobu_ea %d vob_id %d c_id %d c_time %lld",
             p_sys->dsi_pack.dsi_gi.nv_pck_scr,
             p_sys->dsi_pack.dsi_gi.nv_pck_lbn,
             p_sys->dsi_pack.dsi_gi.vobu_ea,
             p_sys->dsi_pack.dsi_gi.vobu_vob_idn,
             p_sys->dsi_pack.dsi_gi.vobu_c_idn,
             dvdtime_to_time( &p_sys->dsi_pack.dsi_gi.c_eltm, 0 ) );

    msg_Dbg( p_demux, "cell duration: %lld",
             (vlc_tick_t)dvdtime_to_time( &p_sys->p_cur_pgc->cell_playback[p_sys->i_cur_cell].playback_time, 0 ) );

    msg_Dbg( p_demux, "cat 0x%02x ilvu_ea %d ilvu_sa %d size %d",
             p_sys->dsi_pack.sml_pbi.category,
             p_sys->dsi_pack.sml_pbi.ilvu_ea,
             p_sys->dsi_pack.sml_pbi.ilvu_sa,
             p_sys->dsi_pack.sml_pbi.size );

    msg_Dbg( p_demux, "next_vobu %d next_ilvu1 %d next_ilvu2 %d",
             p_sys->dsi_pack.vobu_sri.next_vobu & 0x7fffffff,
             p_sys->dsi_pack.sml_agli.data[ p_sys->i_angle - 1 ].address,
             p_sys->dsi_pack.sml_agli.data[ p_sys->i_angle ].address);
#endif
}

/*****************************************************************************
 * DvdReadFindCell
 *****************************************************************************/
static void DvdReadFindCell( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    pgc_t *p_pgc;
    int   pgc_id, pgn;
    int   i = 0;

#define cell p_sys->p_cur_pgc->cell_playback

    if( cell[p_sys->i_cur_cell].block_type == BLOCK_TYPE_ANGLE_BLOCK )
    {
        p_sys->i_cur_cell += p_sys->i_angle - 1;

        while( cell[p_sys->i_cur_cell+i].block_mode != BLOCK_MODE_LAST_CELL )
        {
            i++;
        }
        p_sys->i_next_cell = p_sys->i_cur_cell + i + 1;
    }
    else
    {
        p_sys->i_next_cell = p_sys->i_cur_cell + 1;
    }

#undef cell

    if( p_sys->i_chapter + 1 >= p_sys->i_chapters ) return;

    pgc_id = p_sys->p_vts_file->vts_ptt_srpt->title[
                p_sys->i_ttn - 1].ptt[p_sys->i_chapter + 1].pgcn;
    pgn = p_sys->p_vts_file->vts_ptt_srpt->title[
              p_sys->i_ttn - 1].ptt[p_sys->i_chapter + 1].pgn;
    p_pgc = p_sys->p_vts_file->vts_pgcit->pgci_srp[pgc_id - 1].pgc;

    if( p_sys->i_cur_cell >= p_pgc->program_map[pgn - 1] - 1 )
    {
        p_sys->i_chapter++;

        if( p_sys->i_chapter < p_sys->i_chapters &&
            p_demux->info.i_seekpoint != p_sys->i_chapter )
        {
            p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;
            p_demux->info.i_seekpoint = p_sys->i_chapter;
        }
    }
}

/*****************************************************************************
 * DemuxTitles: get the titles/chapters structure
 *****************************************************************************/
/* Start time of every chapter of a title, and the title length, read from the
 * IFO. This is what the seek bar draws its chapter marks from: without it the
 * marks were all at zero and the interface -- rightly -- refused to draw any.
 * Publishing none is better than publishing wrong ones, so anything that does
 * not fit the simple case gives up quietly and leaves the times at zero. */
static void DvdReadTitleTimes( ifo_handle_t *p_vts, int i_vts_ttn,
                               int i_angle, input_title_t *t )
{
    if( p_vts == NULL || p_vts->vts_ptt_srpt == NULL ||
        p_vts->vts_ptt_srpt->title == NULL || p_vts->vts_pgcit == NULL ||
        i_vts_ttn < 1 || i_vts_ttn > p_vts->vts_ptt_srpt->nr_of_srpts )
        return;

    const ttu_t *p_ttu = &p_vts->vts_ptt_srpt->title[i_vts_ttn - 1];
    const int i_ptts = p_ttu->nr_of_ptts;
    if( p_ttu->ptt == NULL || i_ptts < 1 || i_ptts > t->i_seekpoint )
        return;

    /* Chapters spread over several program chains have no single time line
     * to be placed on. */
    const int i_pgcn = p_ttu->ptt[0].pgcn;
    if( i_pgcn < 1 || i_pgcn > p_vts->vts_pgcit->nr_of_pgci_srp )
        return;
    for( int i = 1; i < i_ptts; i++ )
        if( p_ttu->ptt[i].pgcn != i_pgcn )
            return;

    pgc_t *p_pgc = p_vts->vts_pgcit->pgci_srp[i_pgcn - 1].pgc;
    if( p_pgc == NULL || p_pgc->cell_playback == NULL ||
        p_pgc->program_map == NULL || p_pgc->nr_of_cells < 1 )
        return;

    const int i_first_pgn = p_ttu->ptt[0].pgn;
    if( i_first_pgn < 1 || i_first_pgn > p_pgc->nr_of_programs )
        return;
    const int i_start_cell = p_pgc->program_map[i_first_pgn - 1] - 1;
    if( i_start_cell < 0 || i_start_cell >= p_pgc->nr_of_cells )
        return;

    int64_t *p_cell_time = calloc( p_pgc->nr_of_cells, sizeof(*p_cell_time) );
    int64_t *p_ptt_time = calloc( i_ptts, sizeof(*p_ptt_time) );
    if( unlikely( p_cell_time == NULL || p_ptt_time == NULL ) )
        goto end;

    /* one walk of the played path; every angle of a block starts together */
    vlc_tick_t i_acc = 0;
    for( int i_cell = i_start_cell;
         i_cell >= 0 && i_cell < p_pgc->nr_of_cells; )
    {
        int i_next;
        const int i_played =
            DvdReadPlayedCellIn( p_pgc, i_angle, i_cell, &i_next );

        for( int i = i_cell; i < i_next && i < p_pgc->nr_of_cells; i++ )
            p_cell_time[i] = i_acc;

        i_acc += dvdtime_to_time(
            &p_pgc->cell_playback[i_played].playback_time, 0 );

        if( i_next <= i_cell )
            break;
        i_cell = i_next;
    }

    /* Collect first, commit second: a title half-stamped with times would
     * leave the last chapter at zero, which reads as "no times at all". */
    for( int i = 0; i < i_ptts; i++ )
    {
        const int i_pgn = p_ttu->ptt[i].pgn;
        if( i_pgn < 1 || i_pgn > p_pgc->nr_of_programs )
            goto end;
        const int i_cell = p_pgc->program_map[i_pgn - 1] - 1;
        if( i_cell < 0 || i_cell >= p_pgc->nr_of_cells )
            goto end;
        p_ptt_time[i] = p_cell_time[i_cell];
    }

    for( int i = 0; i < i_ptts; i++ )
        t->seekpoint[i]->i_time_offset = p_ptt_time[i];
    t->i_length = i_acc;

end:
    free( p_cell_time );
    free( p_ptt_time );
}

static void DemuxTitles( demux_t *p_demux, int *pi_angle )
{
    VLC_UNUSED( pi_angle );

    demux_sys_t *p_sys = p_demux->p_sys;
    input_title_t *t;
    seekpoint_t *s;
    ifo_handle_t *p_vts = NULL;
    int i_vts_open = -1;

    /* Find out number of titles/chapters */
#define tt_srpt p_sys->p_vmg_file->tt_srpt

    int32_t i_titles = tt_srpt->nr_of_srpts;
    msg_Dbg( p_demux, "number of titles: %d", i_titles );

    for( int i = 0; i < i_titles; i++ )
    {
        int32_t i_chapters = 0;
        int j;

        i_chapters = tt_srpt->title[i].nr_of_ptts;
        msg_Dbg( p_demux, "title %d has %d chapters", i, i_chapters );

        t = vlc_input_title_New();

        for( j = 0; j < __MAX( i_chapters, 1 ); j++ )
        {
            s = vlc_seekpoint_New();
            TAB_APPEND( t->i_seekpoint, t->seekpoint, s );
        }

        /* Stamp the chapters with their start time. The IFO of a title set
         * serves every title it holds, and tt_srpt groups them, so keep the
         * last one open rather than reopening it for each title. */
        const int i_vts = tt_srpt->title[i].title_set_nr;
        if( i_vts != i_vts_open )
        {
            if( p_vts != NULL )
                ifoClose( p_vts );
            p_vts = ifoOpen( p_sys->p_dvdread, i_vts );
            i_vts_open = p_vts != NULL ? i_vts : -1;
        }
        if( p_vts != NULL )
            DvdReadTitleTimes( p_vts, tt_srpt->title[i].vts_ttn,
                               p_sys->i_angle, t );

        TAB_APPEND( p_sys->i_titles, p_sys->titles, t );
    }

    if( p_vts != NULL )
        ifoClose( p_vts );

#undef tt_srpt
}
