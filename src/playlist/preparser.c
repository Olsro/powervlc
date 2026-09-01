/*****************************************************************************
 * preparser.c
 *****************************************************************************
 * Copyright © 2017-2017 VLC authors and VideoLAN
 * $Id$
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>

#include "misc/background_worker.h"
#include "input/input_interface.h"
#include "input/input_internal.h"
#include "preparser.h"
#include "fetcher.h"

struct playlist_preparser_t
{
    vlc_object_t* owner;
    playlist_fetcher_t* fetcher;
    struct background_worker** workers;
    unsigned worker_count;
    atomic_uint next_worker;
    atomic_bool deactivated;
};

static int InputEvent( vlc_object_t* obj, const char* varname,
    vlc_value_t old, vlc_value_t cur, void* opaque )
{
    VLC_UNUSED( obj ); VLC_UNUSED( varname ); VLC_UNUSED( old );

    if( cur.i_int == INPUT_EVENT_DEAD )
    {
        playlist_preparser_t *preparser = opaque;
        for( unsigned i = 0; i < preparser->worker_count; ++i )
            background_worker_RequestProbe( preparser->workers[i] );
    }

    return VLC_SUCCESS;
}

static int PreparserOpenInput( void* preparser_, void* item_, void** out )
{
    playlist_preparser_t* preparser = preparser_;
    input_item_t *item = item_;
    char *name = input_item_GetName( item );
    if( input_item_IsPowerVLCLazyIndex( item ) )
    {
        char *uri = input_item_GetURI( item );
        vlc_mutex_lock( &item->lock );
        msg_Dbg( preparser->owner,
                 "opening lazy index node '%s' (%s) with %d options",
                 name ? name : "", uri ? uri : "", item->i_options );
        for( int i = 0; i < item->i_options; ++i )
            msg_Dbg( preparser->owner, "lazy option: %s (0x%x)",
                     item->ppsz_options[i], item->optflagv[i] );
        vlc_mutex_unlock( &item->lock );
        free( uri );
    }

    input_thread_t* input = input_CreatePreparser( preparser->owner, item_ );
    if( !input )
    {
        if( input_item_IsPowerVLCLazyIndex( item ) )
            msg_Err( preparser->owner, "cannot create lazy index input '%s'",
                     name ? name : "" );
        free( name );
        input_item_SignalPreparseEnded( item_, ITEM_PREPARSE_FAILED );
        return VLC_EGENERIC;
    }

    var_AddCallback( input, "intf-event", InputEvent, preparser );
    if( input_Start( input ) )
    {
        if( input_item_IsPowerVLCLazyIndex( item ) )
            msg_Err( preparser->owner, "cannot start lazy index input '%s'",
                     name ? name : "" );
        free( name );
        var_DelCallback( input, "intf-event", InputEvent, preparser );
        input_Close( input );
        input_item_SignalPreparseEnded( item_, ITEM_PREPARSE_FAILED );
        return VLC_EGENERIC;
    }

    free( name );
    *out = input;
    return VLC_SUCCESS;
}

static int PreparserProbeInput( void* preparser_, void* input_ )
{
    int state = input_GetState( input_ );
    return state == END_S || state == ERROR_S;
    VLC_UNUSED( preparser_ );
}

static void PreparserCloseInput( void* preparser_, void* input_ )
{
    playlist_preparser_t* preparser = preparser_;
    input_thread_t* input = input_;
    input_item_t* item = input_priv(input)->p_item;

    var_DelCallback( input, "intf-event", InputEvent, preparser );

    int status;
    switch( input_GetState( input ) )
    {
        case END_S:
            status = ITEM_PREPARSE_DONE;
            break;
        case ERROR_S:
            status = ITEM_PREPARSE_FAILED;
            break;
        default:
            status = ITEM_PREPARSE_TIMEOUT;
    }

    if( input_item_IsPowerVLCLazyIndex( item ) )
    {
        char *name = input_item_GetName( item );
        msg_Dbg( preparser->owner, "lazy index node '%s' finished with status %d",
                 name ? name : "", status );
        free( name );
    }

    input_Stop( input );
    input_Close( input );

    vlc_mutex_lock( &item->lock );
    bool skip_art = item->b_preparse_skip_art;
    vlc_mutex_unlock( &item->lock );
    if( preparser->fetcher && !skip_art )
    {
        if( !playlist_fetcher_Push( preparser->fetcher, item, 0, status ) )
            return;
    }

    input_item_SetPreparsed( item, true );
    input_item_SignalPreparseEnded( item, status );
}

static void InputItemRelease( void* item ) { input_item_Release( item ); }
static void InputItemHold( void* item ) { input_item_Hold( item ); }

playlist_preparser_t* playlist_preparser_New( vlc_object_t *parent )
{
    playlist_preparser_t* preparser = calloc( 1, sizeof *preparser );

    struct background_worker_config conf = {
        .default_timeout = var_InheritInteger( parent, "preparse-timeout" ),
        .pf_start = PreparserOpenInput,
        .pf_probe = PreparserProbeInput,
        .pf_stop = PreparserCloseInput,
        .pf_release = InputItemRelease,
        .pf_hold = InputItemHold };


    if( unlikely( !preparser ) )
        return NULL;

    /* Metadata requests used to share one strictly serial background worker.
     * That made a high-latency media library advance roughly one file per
     * round trip regardless of the host CPU. Keep the pool deliberately
     * bounded: enough lanes to hide NAS latency, without turning a rotating
     * disk or an old PowerPC machine into an I/O storm. */
    unsigned cpus = vlc_GetCPUCount();
    if( cpus == 0 ) cpus = 1;
    /* Metadata scanning is latency-bound on removable and network media.
     * Give modern machines a few more in-flight requests than CPU cores,
     * while a one- or two-core legacy Mac keeps exactly its CPU count. */
    preparser->worker_count = cpus >= 4 ? cpus + 4 : cpus;
    if( preparser->worker_count > 16 ) preparser->worker_count = 16;
    preparser->workers = calloc( preparser->worker_count,
                                 sizeof( *preparser->workers ) );
    if( preparser->workers )
        for( unsigned i = 0; i < preparser->worker_count; ++i )
        {
            preparser->workers[i] = background_worker_New( preparser, &conf );
            if( preparser->workers[i] == NULL )
            {
                preparser->worker_count = i;
                break;
            }
        }
    else
        preparser->worker_count = 0;

    if( unlikely( preparser->worker_count == 0 ) )
    {
        free( preparser->workers );
        free( preparser );
        return NULL;
    }

    preparser->owner = parent;
    preparser->fetcher = playlist_fetcher_New( parent );
    atomic_init( &preparser->next_worker, 0 );
    atomic_init( &preparser->deactivated, false );

    if( unlikely( !preparser->fetcher ) )
        msg_Warn( parent, "unable to create art fetcher" );

    return preparser;
}

void playlist_preparser_Push( playlist_preparser_t *preparser,
    input_item_t *item, input_item_meta_request_option_t i_options,
    int timeout, void *id )
{
    if( atomic_load( &preparser->deactivated ) )
        return;

    vlc_mutex_lock( &item->lock );
    int i_type = item->i_type;
    int b_net = item->b_net;
    vlc_mutex_unlock( &item->lock );

    switch( i_type )
    {
        case ITEM_TYPE_NODE:
        case ITEM_TYPE_FILE:
        case ITEM_TYPE_DIRECTORY:
        case ITEM_TYPE_PLAYLIST:
            if( !b_net || i_options & META_REQUEST_OPTION_SCOPE_NETWORK )
                break;
        default:
            input_item_SignalPreparseEnded( item, ITEM_PREPARSE_SKIPPED );
            return;
    }

    unsigned worker = atomic_fetch_add( &preparser->next_worker, 1 )
                    % preparser->worker_count;
    if( background_worker_Push( preparser->workers[worker], item, id,
                                timeout ) )
        input_item_SignalPreparseEnded( item, ITEM_PREPARSE_FAILED );
}

void playlist_preparser_fetcher_Push( playlist_preparser_t *preparser,
    input_item_t *item, input_item_meta_request_option_t options )
{
    if( preparser->fetcher )
        playlist_fetcher_Push( preparser->fetcher, item, options, -1 );
}

void playlist_preparser_Cancel( playlist_preparser_t *preparser, void *id )
{
    for( unsigned i = 0; i < preparser->worker_count; ++i )
        background_worker_Cancel( preparser->workers[i], id );
}

void playlist_preparser_Deactivate( playlist_preparser_t* preparser )
{
    atomic_store( &preparser->deactivated, true );
    for( unsigned i = 0; i < preparser->worker_count; ++i )
        background_worker_Cancel( preparser->workers[i], NULL );
}

void playlist_preparser_Delete( playlist_preparser_t *preparser )
{
    for( unsigned i = 0; i < preparser->worker_count; ++i )
        background_worker_Delete( preparser->workers[i] );
    free( preparser->workers );

    if( preparser->fetcher )
        playlist_fetcher_Delete( preparser->fetcher );

    free( preparser );
}
