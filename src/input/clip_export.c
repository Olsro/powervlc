/*****************************************************************************
 * clip_export.c: fast clip extraction for the clip creation mode
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC authors
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/* Recording a clip by playing it back takes exactly as long as the clip
 * lasts. This runs the very same recording chain (#record, so the same
 * muxer choice and the same file naming) on a SECOND, headless input
 * instead: no audio output, no video output, hence no clock — the demuxer
 * is only limited by the disk, and a minute of video is written in a
 * fraction of a second. The playback the user is watching is left
 * completely alone, which is the other half of the point.
 *
 * The caller polls: the interfaces already refresh at 10 Hz. */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <assert.h>
#include <stdarg.h>

#include <vlc_common.h>
#include <vlc_arrays.h>
#include <vlc_input.h>
#include <vlc_input_item.h>
#include <vlc_configuration.h>

#include "input_internal.h"

struct input_clip_export_t
{
    input_thread_t *p_input;
    input_item_t   *p_item;
    char           *psz_prefix;   /* path prefix handed to #record */
    char           *psz_file;     /* the file it produced, once known */
    vlc_tick_t      i_start;
    vlc_tick_t      i_stop;
    vlc_tick_t      i_duration;
    vlc_tick_t      i_deadline;   /* wall clock: give up rather than hang */
    bool            b_failed;
};

/* Discs are driven by titles and menus: which title is playing is INPUT
 * state, not something the item carries, so a second input on the same
 * MRL restarts in the DVD menu -- where the seek to the clip start is
 * refused outright ("can't set time", dvdnav) and the stop bound is never
 * reached because a menu loops forever. Measured on a DVD ISO: the whole
 * export wrote the menu instead of the clip and never ended. Those are
 * recorded live instead. */
static bool ClipExportIsDiscInput( input_thread_t *p_source,
                                   input_item_t *p_item )
{
    static const char *const ppsz_disc_schemes[] = {
        "dvd", "dvdnav", "dvdsimple", "dvdread", "bluray", "vcd", "svcd",
        "vcdx", "cdda",
    };

    char *psz_uri = input_item_GetURI( p_item );
    if( psz_uri )
    {
        size_t i_len = strcspn( psz_uri, ":" );
        for( size_t i = 0; i < ARRAY_SIZE(ppsz_disc_schemes); i++ )
            if( strlen( ppsz_disc_schemes[i] ) == i_len
             && !strncasecmp( psz_uri, ppsz_disc_schemes[i], i_len ) )
            {
                free( psz_uri );
                return true;
            }
        free( psz_uri );
    }

    /* anything else exposing several titles falls in the same trap */
    return var_CountChoices( p_source, "title" ) > 1;
}

static void ClipExportAddOption( input_item_t *p_item, const char *psz_format, ... )
{
    char *psz_option;
    va_list args;

    va_start( args, psz_format );
    if( vasprintf( &psz_option, psz_format, args ) != -1 )
    {
        input_item_AddOption( p_item, psz_option, VLC_INPUT_OPTION_TRUSTED );
        free( psz_option );
    }
    va_end( args );
}

#undef input_ClipExportNew
input_clip_export_t *input_ClipExportNew( vlc_object_t *p_parent,
                                          input_thread_t *p_source,
                                          vlc_tick_t i_start, vlc_tick_t i_stop )
{
    assert( p_parent && p_source );

    if( i_start < 0 )
        i_start = 0;
    if( i_stop <= i_start )
        return NULL;

    /* the extraction seeks and reads on its own: a stream that cannot be
     * seeked, or whose length is unknown, has to be recorded live */
    if( !var_GetBool( p_source, "can-seek" ) )
        return NULL;

    input_item_t *p_source_item = input_GetItem( p_source );
    if( !p_source_item )
        return NULL;

    vlc_tick_t i_duration = input_item_GetDuration( p_source_item );
    if( i_duration <= 0 )
        return NULL;

    if( ClipExportIsDiscInput( p_source, p_source_item ) )
    {
        msg_Dbg( p_parent, "clip export: disc input, recording it live instead" );
        return NULL;
    }

    input_clip_export_t *p_export = calloc( 1, sizeof(*p_export) );
    if( !p_export )
        return NULL;

    p_export->i_start = i_start;
    p_export->i_stop = i_stop > i_duration ? i_duration : i_stop;
    p_export->i_duration = i_duration;
    /* The whole point is to be FASTER than the playback, so anything that
     * takes several times the length of the clip is not going to finish:
     * give up and say so rather than poll a stuck input forever (the
     * caller only ever learns about the end through -IsRunning). */
    p_export->i_deadline = mdate()
        + 4 * ( p_export->i_stop - i_start ) + 60 * CLOCK_FREQ;

    p_export->p_item = input_item_Copy( p_source_item );
    if( !p_export->p_item )
        goto error;

    /* the very same directory a live recording would use */
    char *psz_dir = input_RecordDirectory( p_source );
    if( !psz_dir )
        goto error;
    p_export->psz_prefix = input_CreateFilename( p_source, psz_dir,
                                                 INPUT_RECORD_PREFIX, NULL );
    free( psz_dir );
    if( !p_export->psz_prefix )
        goto error;

    char *psz_prefix_esc = config_StringEscape( p_export->psz_prefix );
    if( !psz_prefix_esc )
        goto error;

    /* The recording chain is the regular one, so the produced file is named
     * and muxed exactly like a live recording. No start-time bound is given
     * to #record: here the seek does the trimming (the extraction starts at
     * the key frame at or before the bound, like a live recording does), and
     * the block timestamps of a sout run are not on the media time base
     * anyway. */
    ClipExportAddOption( p_export->p_item, "sout=#record{dst-prefix='%s'}",
                         psz_prefix_esc );
    free( psz_prefix_esc );

    ClipExportAddOption( p_export->p_item, "start-time=%.3f",
                         (double)p_export->i_start / (double)CLOCK_FREQ );
    ClipExportAddOption( p_export->p_item, "stop-time=%.3f",
                         (double)p_export->i_stop / (double)CLOCK_FREQ );

    static const char *const ppsz_options[] = {
        /* the bounds must be exact: no key-frame-only seeking */
        "no-input-fast-seek",
        /* headless: nothing of this second input reaches the user */
        "no-osd", "no-video-title-show", "no-sub-autodetect-file",
    };
    for( size_t i = 0; i < ARRAY_SIZE(ppsz_options); i++ )
        input_item_AddOption( p_export->p_item, ppsz_options[i],
                              VLC_INPUT_OPTION_TRUSTED );

    /* #record announces the file it settled on through this variable */
    var_SetString( p_parent->obj.libvlc, "record-file", "" );

    p_export->p_input = input_Create( p_parent, p_export->p_item,
                                      "clip export", NULL, NULL );
    if( !p_export->p_input )
        goto error;

    if( input_Start( p_export->p_input ) != VLC_SUCCESS )
    {
        input_Close( p_export->p_input );
        p_export->p_input = NULL;
        goto error;
    }

    return p_export;

error:
    if( p_export->p_item )
        input_item_Release( p_export->p_item );
    free( p_export->psz_prefix );
    free( p_export );
    return NULL;
}

bool input_ClipExportIsRunning( input_clip_export_t *p_export )
{
    if( !p_export->p_input || p_export->b_failed )
        return false;

    input_state_e state = input_GetState( p_export->p_input );
    if( state == END_S || state == ERROR_S )
        return false;

    if( mdate() > p_export->i_deadline )
    {
        msg_Warn( p_export->p_input, "clip export gave up: still running "
                  "after %"PRId64" s",
                  ( 4 * ( p_export->i_stop - p_export->i_start )
                    + 60 * CLOCK_FREQ ) / CLOCK_FREQ );
        p_export->b_failed = true;
        return false;
    }
    return true;
}

float input_ClipExportProgress( input_clip_export_t *p_export )
{
    if( !p_export->p_input )
        return 1.f;

    /* the position is that of the whole item; the clip is a window in it */
    float f_pos = var_GetFloat( p_export->p_input, "position" );
    vlc_tick_t i_now = (vlc_tick_t)( (double)f_pos * (double)p_export->i_duration );
    if( i_now <= p_export->i_start )
        return 0.f;
    if( i_now >= p_export->i_stop )
        return 1.f;
    return (float)( i_now - p_export->i_start )
         / (float)( p_export->i_stop - p_export->i_start );
}

char *input_ClipExportFinish( input_clip_export_t *p_export )
{
    if( p_export->p_input )
    {
        libvlc_int_t *p_libvlc = p_export->p_input->obj.libvlc;

        input_Stop( p_export->p_input );
        input_Close( p_export->p_input );
        p_export->p_input = NULL;

        /* only ours: a recording started elsewhere in the meantime would
         * have overwritten the variable with a name of its own. A timed
         * out export reports no file at all: what it wrote, if anything,
         * is not the clip that was asked for. */
        char *psz_file = p_export->b_failed
            ? NULL : var_GetNonEmptyString( p_libvlc, "record-file" );
        if( psz_file )
        {
            if( !strncmp( psz_file, p_export->psz_prefix,
                          strlen( p_export->psz_prefix ) ) )
                p_export->psz_file = psz_file;
            else
                free( psz_file );
        }
    }

    char *psz_file = p_export->psz_file;
    if( p_export->p_item )
        input_item_Release( p_export->p_item );
    free( p_export->psz_prefix );
    free( p_export );
    return psz_file;
}
