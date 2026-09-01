/*****************************************************************************
 * powervlc_devices.c: portable-player browsing and drag-and-drop transfers
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#define VLC_MODULE_LICENSE VLC_LICENSE_GPL_2_PLUS
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_configuration.h>
#include <vlc_fs.h>
#include <vlc_input.h>
#include <vlc_input_item.h>
#include <vlc_image.h>
#include <vlc_meta.h>
#include <vlc_playlist.h>
#include <vlc_services_discovery.h>
#include <vlc_url.h>

#include "powervlc_media_common.h"

#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <sys/stat.h>
#ifndef _WIN32
# include <sys/statvfs.h>
#endif
#include <time.h>

#ifdef HAVE_LIBGPOD
# include <gpod/itdb.h>
#endif

#define DEVICE_DB ".powervlcdevice.db"
#define TRANSFER_HISTORY_LIMIT 200
#define IPOD_TRACK_ID_OPTION "powervlc-ipod-track-id="
#define IPOD_PLAYLIST_ID_OPTION "powervlc-ipod-playlist-id="

static char device_mode_copy[] = "copy";
static char device_mode_transcode[] = "transcode";

typedef struct
{
    char *name, *path, *kind, *codec, *backup;
    bool transcode;
    bool album_artist_as_composer;
    unsigned bitrate;
} device_config_t;

typedef struct
{
    char *source, *destination, *mode;
    uint64_t size;
    int64_t mtime;
} sync_entry_t;

typedef struct
{
    sync_entry_t *entries;
    size_t count, capacity;
} sync_state_t;

struct services_discovery_sys_t
{
    vlc_thread_t thread;
    vlc_mutex_t lock;
    vlc_cond_t wait;
    bool stop, refresh;
    char *backup_request;
    char **drop_paths;
    uint64_t *drop_transfers;
    size_t drop_count;
    char **delete_paths;
    size_t delete_count;
    int *delete_item_ids;
    size_t delete_item_count;
    char **pending_ipod_additions;
    size_t pending_ipod_addition_count;
    char **pending_ipod_deletions;
    size_t pending_ipod_deletion_count;
    bool pending_changes;
    bool commit_failed;
    bool commit_request;
    bool discard_request;
    services_discovery_transfer_item_t *transfers;
    size_t transfer_count;
    uint64_t next_transfer_id;
    bool transferring;
    unsigned transcode_parallelism;
    device_config_t device;
    input_item_t *visible_roots[8];
    size_t visible_root_count;
    unsigned activity;
    uint64_t total_bytes, free_bytes;
#ifdef HAVE_LIBGPOD
    Itdb_iTunesDB *ipod_database;
    GTree *ipod_track_ids;
    char *ipod_index_path;
    GHashTable *ipod_playlist_offsets;
    uint64_t ipod_music_offset, ipod_podcast_offset;
    uint64_t ipod_music_view_offsets[7];
    size_t ipod_music_view_count;
    size_t ipod_music_count, ipod_podcast_count, ipod_playlist_count;
    input_item_t *ipod_music_root;
    input_item_t *ipod_podcast_root;
    input_item_t *ipod_session_additions;
    size_t ipod_session_addition_count;
#endif
};

static unsigned portable_transcode_task_limit( void )
{
    unsigned cpus = vlc_GetCPUCount();
    if( cpus == 0 ) cpus = 1;

    /* Transcoding and feeding a slow portable player overlap well.  Keep at
     * least two jobs in flight even on a single-core system, use two jobs per
     * logical processor, and cap the resulting pressure at ten jobs. */
    return cpus >= 5 ? 10 : cpus * 2;
}

static void update_device_space( services_discovery_sys_t *sys )
{
#ifndef _WIN32
    struct statvfs st;
    if( statvfs( sys->device.path, &st ) == 0 )
    {
        uint64_t unit = st.f_frsize ? st.f_frsize : st.f_bsize;
        vlc_mutex_lock( &sys->lock );
        sys->total_bytes = (uint64_t)st.f_blocks * unit;
        sys->free_bytes = (uint64_t)st.f_bavail * unit;
        vlc_mutex_unlock( &sys->lock );
    }
#else
    (void)sys;
#endif
}

static void remember_visible_root( services_discovery_sys_t *sys,
                                   input_item_t *item )
{
    if( item && sys->visible_root_count < ARRAY_SIZE( sys->visible_roots ) )
        sys->visible_roots[sys->visible_root_count++] = item;
    else if( item )
        input_item_Release( item );
}

static void remove_visible_roots( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    for( size_t i = 0; i < sys->visible_root_count; ++i )
    {
        services_discovery_RemoveItem( sd, sys->visible_roots[i] );
        input_item_Release( sys->visible_roots[i] );
        sys->visible_roots[i] = NULL;
    }
    sys->visible_root_count = 0;
#ifdef HAVE_LIBGPOD
    if( sys->ipod_session_additions )
        input_item_Release( sys->ipod_session_additions );
    sys->ipod_session_additions = NULL;
    sys->ipod_session_addition_count = 0;
    sys->ipod_music_root = NULL;
    sys->ipod_podcast_root = NULL;
#endif
}

static void set_device_activity( services_discovery_sys_t *sys,
                                 unsigned activity )
{
    vlc_mutex_lock( &sys->lock );
    sys->activity = activity;
    vlc_mutex_unlock( &sys->lock );
}

static int Open( vlc_object_t * );
static void Close( vlc_object_t * );
static void *Run( void * );
static int Control( services_discovery_t *, int, va_list );
static int vlc_sd_probe_Open( vlc_object_t * );
static bool path_is_inside( const char *, const char * );

static bool path_has_device_prefix( const char *device, const char *path )
{
    size_t length = strlen( device );
    while( length > 1 && (device[length - 1] == '/'
                       || device[length - 1] == '\\') ) length--;
    return !strncasecmp( device, path, length )
        && (path[length] == '/' || path[length] == '\\');
}

static bool device_managed_root_name( const char *name )
{
    static const char *const roots[] = {
        "Music", "Movies", "Shows", "Podcasts", "Playlists"
    };
    for( size_t i = 0; i < ARRAY_SIZE( roots ); ++i )
        if( !strcasecmp( name, roots[i] ) ) return true;
    return false;
}

static bool device_path_is_managed( const device_config_t *device,
                                    const char *path )
{
    if( device == NULL || path == NULL ) return false;
    static const char *const roots[] = {
        "Music", "Movies", "Shows", "Podcasts", "Playlists"
    };
    for( size_t i = 0; i < ARRAY_SIZE( roots ); ++i )
    {
        char *root = pvlc_path_join( device->path, roots[i] );
        bool managed = root && path_has_device_prefix( root, path );
        free( root );
        if( managed ) return true;
    }
    return false;
}

static void transfer_item_clear( services_discovery_transfer_item_t *item )
{
    free( item->psz_source );
    free( item->psz_destination );
    memset( item, 0, sizeof( *item ) );
}

static uint64_t transfer_begin_locked( services_discovery_sys_t *sys,
                                       const char *source,
                                       const char *destination,
                                       services_discovery_transfer_stage_e stage )
{
    if( sys->transfer_count == TRANSFER_HISTORY_LIMIT )
    {
        transfer_item_clear( &sys->transfers[0] );
        memmove( &sys->transfers[0], &sys->transfers[1],
                 (sys->transfer_count - 1) * sizeof( *sys->transfers ) );
        sys->transfer_count--;
    }
    services_discovery_transfer_item_t *grown = realloc( sys->transfers,
                    (sys->transfer_count + 1) * sizeof( *grown ) );
    uint64_t id = 0;
    if( grown )
    {
        sys->transfers = grown;
        size_t index = sys->transfer_count++;
        services_discovery_transfer_item_t *item = &grown[index];
        memset( item, 0, sizeof( *item ) );
        item->psz_source = strdup( source ? source : "" );
        item->psz_destination = strdup( destination ? destination : "" );
        id = ++sys->next_transfer_id;
        if( id == 0 ) id = ++sys->next_transfer_id;
        item->i_id = id;
        item->i_stage = stage;
        item->i_progress = 0;
        if( item->psz_source == NULL || item->psz_destination == NULL )
        {
            transfer_item_clear( item );
            sys->transfer_count--;
            id = 0;
        }
    }
    return id;
}

static uint64_t transfer_begin( services_discovery_sys_t *sys,
                                const char *source, const char *destination,
                                services_discovery_transfer_stage_e stage )
{
    vlc_mutex_lock( &sys->lock );
    uint64_t id = transfer_begin_locked( sys, source, destination, stage );
    vlc_mutex_unlock( &sys->lock );
    return id;
}

static void transfer_update( services_discovery_sys_t *sys, uint64_t id,
                             services_discovery_transfer_stage_e stage,
                             unsigned progress )
{
    if( id == 0 ) return;
    vlc_mutex_lock( &sys->lock );
    for( size_t i = 0; i < sys->transfer_count; ++i )
        if( sys->transfers[i].i_id == id )
        {
            sys->transfers[i].i_stage = stage;
            sys->transfers[i].i_progress = progress > 100 ? 100 : progress;
            break;
        }
    vlc_mutex_unlock( &sys->lock );
}

static bool transfer_cancelled( services_discovery_sys_t *sys, uint64_t id )
{
    bool cancelled = false;
    vlc_mutex_lock( &sys->lock );
    for( size_t i = 0; i < sys->transfer_count; ++i )
        if( sys->transfers[i].i_id == id )
        { cancelled = sys->transfers[i].b_cancel_requested; break; }
    vlc_mutex_unlock( &sys->lock );
    return cancelled;
}

static void transfer_set_destination( services_discovery_sys_t *sys,
                                      uint64_t id, const char *destination )
{
    char *copy = strdup( destination ? destination : "" );
    if( copy == NULL ) return;
    vlc_mutex_lock( &sys->lock );
    for( size_t i = 0; i < sys->transfer_count; ++i )
        if( sys->transfers[i].i_id == id )
        {
            free( sys->transfers[i].psz_destination );
            sys->transfers[i].psz_destination = copy;
            copy = NULL;
            break;
        }
    vlc_mutex_unlock( &sys->lock );
    free( copy );
}

static void transfer_set_activity( services_discovery_sys_t *sys, bool active )
{
    vlc_mutex_lock( &sys->lock );
    sys->transferring = active || sys->drop_count > 0;
    vlc_mutex_unlock( &sys->lock );
}

static const char *const options[] = { "index", NULL };
#define CFG_PREFIX "powervlc-device-"

vlc_module_begin()
    set_shortname( N_("Portable player") )
    set_description( N_("PowerVLC portable-player transfers") )
    set_category( CAT_PLAYLIST )
    set_subcategory( SUBCAT_PLAYLIST_SD )
    set_capability( "services_discovery", 0 )
    set_callbacks( Open, Close )
    add_shortcut( "powervlc_device" )
    add_integer( CFG_PREFIX "index", -1, NULL, NULL, true )

    VLC_SD_PROBE_SUBMODULE
vlc_module_end()

static char *field( char **cursor )
{
    if( cursor == NULL || *cursor == NULL ) return NULL;
    char *out = *cursor, *tab = strchr( out, '\t' );
    if( tab ) { *tab = '\0'; *cursor = tab + 1; } else *cursor = NULL;
    return out;
}

static void device_clear( device_config_t *d )
{
    free( d->name ); free( d->path ); free( d->kind ); free( d->codec );
    free( d->backup ); memset( d, 0, sizeof( *d ) );
}

static int device_parse_line( char *line, device_config_t *d )
{
    memset( d, 0, sizeof( *d ) );
    char *cursor = line;
    char *v[10];
    for( size_t i = 0; i < ARRAY_SIZE( v ); ++i ) v[i] = field( &cursor );
    if( v[0] == NULL || v[1] == NULL ) return VLC_EGENERIC;
    d->name = pvlc_unescape( v[0] ); d->path = pvlc_unescape( v[1] );
    d->kind = pvlc_unescape( v[2] ? v[2] : "storage" );
    d->transcode = v[3] && atoi( v[3] );
    d->codec = pvlc_unescape( v[4] && *v[4] ? v[4] : "aac" );
    d->bitrate = v[5] && *v[5]
               ? (unsigned)strtoul( v[5], NULL, 10 ) : 256;
    if( d->bitrate == 0 ) d->bitrate = 256;
    d->album_artist_as_composer = v[6] && atoi( v[6] );
    d->backup = pvlc_unescape( v[9] ? v[9] : "" );
    if( d->name && d->path && d->kind && d->codec && d->backup )
        return VLC_SUCCESS;
    device_clear( d ); return VLC_ENOMEM;
}

static int device_at_index( vlc_object_t *obj, size_t wanted,
                            device_config_t *device )
{
    char *config = var_InheritString( obj, "powervlc-devices" );
    if( config == NULL ) return VLC_EGENERIC;
    size_t index = 0; int ret = VLC_EGENERIC; char *save = NULL;
    /* VLC's text configuration format cannot persist literal newlines inside
     * a string value.  Accept the legacy in-memory newline form and the
     * persistent pipe-separated form written by the preference UIs.  Device
     * text fields percent-escape pipes, so the separator is unambiguous. */
    for( char *line = strtok_r( config, "\n|", &save ); line;
         line = strtok_r( NULL, "\n|", &save ), ++index )
        if( index == wanted ) { ret = device_parse_line( line, device ); break; }
    free( config ); return ret;
}

static int vlc_sd_probe_Open( vlc_object_t *obj )
{
    char *config = var_InheritString( obj, "powervlc-devices" );
    if( config == NULL ) return VLC_PROBE_CONTINUE;
    size_t index = 0; char *save = NULL;
    for( char *line = strtok_r( config, "\n|", &save ); line;
         line = strtok_r( NULL, "\n|", &save ), ++index )
    {
        device_config_t device;
        if( device_parse_line( line, &device ) == VLC_SUCCESS )
        {
            char *chain;
            if( asprintf( &chain, "powervlc_device{index=%zu}", index ) >= 0 )
            {
                vlc_sd_probe_Add( (vlc_probe_t *)obj, chain, device.name,
                                  SD_CAT_DEVICES );
                free( chain );
            }
            device_clear( &device );
        }
    }
    free( config ); return VLC_PROBE_CONTINUE;
}

static int state_append( sync_state_t *state, const sync_entry_t *entry )
{
    if( state->count == state->capacity )
    {
        size_t cap = state->capacity ? state->capacity * 2 : 128;
        sync_entry_t *p = realloc( state->entries, cap * sizeof( *p ) );
        if( p == NULL ) return VLC_ENOMEM;
        state->entries = p; state->capacity = cap;
    }
    sync_entry_t *dst = &state->entries[state->count++];
    *dst = *entry;
    dst->source = strdup( entry->source );
    dst->destination = strdup( entry->destination );
    dst->mode = strdup( entry->mode );
    if( dst->source && dst->destination && dst->mode ) return VLC_SUCCESS;
    free( dst->source ); free( dst->destination ); free( dst->mode );
    state->count--; return VLC_ENOMEM;
}

static void state_clear( sync_state_t *state )
{
    for( size_t i = 0; i < state->count; ++i )
    { free( state->entries[i].source ); free( state->entries[i].destination );
      free( state->entries[i].mode ); }
    free( state->entries ); memset( state, 0, sizeof( *state ) );
}

static int state_compare( const void *a, const void *b )
{
    const sync_entry_t *left = a, *right = b;
    return strcasecmp( left->source, right->source );
}

static void state_sort( sync_state_t *state )
{
    if( state->count > 1 )
        qsort( state->entries, state->count, sizeof( *state->entries ),
               state_compare );
}

static sync_entry_t *state_find_linear( sync_state_t *state,
                                        const char *source )
{
    for( size_t i = 0; i < state->count; ++i )
        if( !strcasecmp( state->entries[i].source, source ) )
            return &state->entries[i];
    return NULL;
}

static const unsigned char device_db_magic[8] = {
    'P', 'V', 'L', 'C', 'D', 'V', 2, 0
};

static int state_load( const device_config_t *device, sync_state_t *state )
{
    memset( state, 0, sizeof( *state ) );
    char *path = pvlc_path_join( device->path, DEVICE_DB );
    FILE *f = path ? vlc_fopen( path, "rb" ) : NULL; free( path );
    if( f == NULL ) return VLC_EGENERIC;
    setvbuf( f, NULL, _IOFBF, 64 * 1024 );
    unsigned char magic[sizeof( device_db_magic )];
    uint64_t fingerprint, timestamp, count;
    uint32_t bitrate;
    char *name = NULL, *kind = NULL, *codec = NULL;
    int ret = pvlc_binary_read( f, magic, sizeof( magic ) );
    if( ret == VLC_SUCCESS && memcmp( magic, device_db_magic, sizeof( magic ) ) )
        ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( f, &fingerprint );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( f, &timestamp );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( f, &name, 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( f, &kind, 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( f, &codec, 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( f, &bitrate );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( f, &count );
    VLC_UNUSED( fingerprint ); VLC_UNUSED( timestamp ); VLC_UNUSED( bitrate );
    free( name ); free( kind ); free( codec );
    if( ret != VLC_SUCCESS || count > UINT64_C(10000000)
     || count > SIZE_MAX / sizeof( *state->entries ) )
    {
        fclose( f ); return VLC_EGENERIC;
    }
    if( count )
    {
        state->entries = calloc( (size_t)count, sizeof( *state->entries ) );
        if( state->entries == NULL ) { fclose( f ); return VLC_ENOMEM; }
        state->capacity = (size_t)count;
    }
    for( uint64_t i = 0; i < count; ++i )
    {
        sync_entry_t *entry = &state->entries[state->count];
        uint64_t mtime;
        ret = pvlc_binary_read_string( f, &entry->source, 16 * 1024 * 1024 );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( f, &entry->size );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( f, &mtime );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( f,
                                         &entry->destination, 16 * 1024 * 1024 );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( f,
                                         &entry->mode, 1024 * 1024 );
        if( ret != VLC_SUCCESS )
        {
            free( entry->source ); free( entry->destination ); free( entry->mode );
            fclose( f ); state_clear( state ); return ret;
        }
        entry->mtime = (int64_t)mtime;
        state->count++;
    }
    fclose( f ); state_sort( state ); return VLC_SUCCESS;
}

static int state_save( const device_config_t *device, const sync_state_t *state,
                       uint64_t fingerprint )
{
    char *path = pvlc_path_join( device->path, DEVICE_DB );
    char *tmp = pvlc_path_join( device->path, ".powervlcdevice.db.tmp" );
    FILE *f = tmp ? vlc_fopen( tmp, "wb" ) : NULL;
    if( !path || !tmp || !f ) { free( path ); free( tmp ); return VLC_EGENERIC; }
    setvbuf( f, NULL, _IOFBF, 64 * 1024 );
    int ret = pvlc_binary_write( f, device_db_magic,
                                 sizeof( device_db_magic ) );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f, fingerprint );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f,
                                                   (uint64_t)time( NULL ) );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( f, device->name );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( f, device->kind );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( f, device->codec );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( f, device->bitrate );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f, state->count );
    for( size_t i = 0; i < state->count; ++i )
    {
        const sync_entry_t *e = &state->entries[i];
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( f, e->source );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f, e->size );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f,
                                                    (uint64_t)e->mtime );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( f,
                                                    e->destination );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( f, e->mode );
        if( ret != VLC_SUCCESS ) break;
    }
    bool error = ret != VLC_SUCCESS || fflush( f ) != 0 || ferror( f );
    if( fclose( f ) != 0 ) error = true;
    if( !error )
    {
#ifdef _WIN32
        vlc_unlink( path );
#endif
        error = vlc_rename( tmp, path ) != 0;
    }
    if( error ) vlc_unlink( tmp );
    free( path ); free( tmp ); return error ? VLC_EGENERIC : VLC_SUCCESS;
}

static const char *filename_of( const char *path )
{
    const char *base = path;
    for( const char *p = path; *p; ++p ) if( *p == '/' || *p == '\\' ) base = p + 1;
    return base;
}

static bool has_extension( const char *path, const char *extension )
{
    const char *dot = strrchr( path, '.' );
    return dot && !strcasecmp( dot + 1, extension );
}

typedef struct
{
    services_discovery_sys_t *sys;
    uint64_t transfer;
    vlc_mutex_t lock;
    vlc_cond_t wait;
    bool finished;
} transcode_monitor_t;

static int transcode_event( vlc_object_t *object, const char *name,
                            vlc_value_t old_value, vlc_value_t new_value,
                            void *opaque )
{
    VLC_UNUSED( name ); VLC_UNUSED( old_value );
    transcode_monitor_t *monitor = opaque;
    if( new_value.i_int == INPUT_EVENT_POSITION )
    {
        double position = var_GetFloat( object, "position" );
        unsigned percent = position <= 0. ? 0
                         : position >= 1. ? 99 : (unsigned)(position * 100.);
        transfer_update( monitor->sys, monitor->transfer,
                         SD_TRANSFER_TRANSCODING, percent );
    }
    else if( new_value.i_int == INPUT_EVENT_DEAD )
    {
        vlc_mutex_lock( &monitor->lock );
        monitor->finished = true;
        vlc_cond_signal( &monitor->wait );
        vlc_mutex_unlock( &monitor->lock );
    }
    return VLC_SUCCESS;
}

static void transcode_cancel_cleanup( void *opaque )
{
    input_thread_t *input = opaque;
    input_Stop( input );
    input_Close( input );
}

static char *portable_artwork_url( const pvlc_media_entry_t *entry )
{
    if( entry == NULL ) return NULL;
    const char *stored = pvlc_media_meta( entry, vlc_meta_ArtworkURL );
    if( stored && *stored )
    {
        char *path = vlc_uri2path( stored );
        struct stat st;
        if( path && vlc_stat( path, &st ) == 0 && st.st_size > 0 )
        {
            free( path );
            return strdup( stored );
        }
        free( path );
    }

    /* attachment:// belongs to the scanner input that discovered embedded
     * art. Prefer a conventional image beside the source when available. */
    char *directory = entry->psz_path ? strdup( entry->psz_path ) : NULL;
    char *slash = directory ? strrchr( directory, '/' ) : NULL;
#ifdef _WIN32
    char *backslash = directory ? strrchr( directory, '\\' ) : NULL;
    if( backslash && (!slash || backslash > slash) ) slash = backslash;
#endif
    if( slash == NULL ) { free( directory ); return NULL; }
    *slash = '\0';
    static const char *const names[] = {
        "cover.jpg", "Cover.jpg", "folder.jpg", "Folder.jpg",
        "front.jpg", "Front.jpg", "cover.jpeg", "Cover.jpeg",
        "cover.png", "Cover.png", "folder.png", "Folder.png",
    };
    char *url = NULL;
    for( size_t i = 0; i < ARRAY_SIZE( names ); ++i )
    {
        char *candidate = pvlc_path_join( directory, names[i] );
        struct stat st;
        if( candidate && vlc_stat( candidate, &st ) == 0 && st.st_size > 0 )
        {
            url = vlc_path2uri( candidate, NULL );
            free( candidate );
            break;
        }
        free( candidate );
    }
    free( directory );
    return url;
}

static void transcode_set_metadata( input_item_t *item,
                                    const pvlc_media_entry_t *entry )
{
    if( entry == NULL ) return;
    for( size_t i = 0; i < VLC_META_TYPE_COUNT; ++i )
    {
        /* Artwork is resolved below because attachment:// URLs belong to the
         * scanner input and may need a neighbouring album image fallback. */
        if( i == vlc_meta_ArtworkURL ) continue;
        const char *value = pvlc_media_meta( entry, (vlc_meta_type_t)i );
        if( value && *value )
            input_item_SetMeta( item, (vlc_meta_type_t)i, value );
    }
    for( size_t i = 0; i < entry->i_extra_count; ++i )
    {
        vlc_mutex_lock( &item->lock );
        if( item->p_meta == NULL ) item->p_meta = vlc_meta_New();
        if( item->p_meta )
            vlc_meta_AddExtra( item->p_meta, entry->ppsz_extra_names[i],
                              entry->ppsz_extra_values[i] );
        vlc_mutex_unlock( &item->lock );
    }
    char *artwork = portable_artwork_url( entry );
    if( artwork )
    {
        input_item_SetMeta( item, vlc_meta_ArtworkURL, artwork );
        free( artwork );
    }
}

static void transcode_write_metadata( vlc_object_t *obj,
                                      const char *destination,
                                      const pvlc_media_entry_t *cached )
{
    /* The indexed catalog is authoritative. Reopening the source here caused
     * one extra network round-trip per transfer after the encoder had already
     * consumed the complete file. */
    const pvlc_media_entry_t *metadata = cached;
    char *output_uri = vlc_path2uri( destination, NULL );
    input_item_t *output = output_uri
        ? input_item_NewFile( output_uri, metadata ? metadata->psz_title : NULL,
                              -1, ITEM_LOCAL ) : NULL;
    free( output_uri );
    if( output )
    {
        transcode_set_metadata( output, metadata );
        if( input_item_WriteMeta( obj, output ) != VLC_SUCCESS )
            msg_Warn( obj, "could not write all portable-player metadata to %s",
                      destination );
        input_item_Release( output );
    }
}

static int transcode_file( vlc_object_t *obj, const char *source,
                           const char *destination, const device_config_t *d,
                           const pvlc_media_entry_t *entry,
                           services_discovery_sys_t *status_sys,
                           uint64_t transfer )
{
    const char *acodec = !strcasecmp( d->codec, "aac" ) ? "mp4a"
                       : !strcasecmp( d->codec, "flac" ) ? "flac" : "mp3";
    const char *mux = !strcasecmp( d->codec, "aac" ) ? "mp4" : "raw";
    unsigned encoder_threads = vlc_GetCPUCount();
    if( encoder_threads == 0 ) encoder_threads = 1;
    if( status_sys && status_sys->transcode_parallelism > 1 )
    {
        encoder_threads /= status_sys->transcode_parallelism;
        if( encoder_threads == 0 ) encoder_threads = 1;
    }
    char *escaped = config_StringEscape( destination );
    if( escaped == NULL ) return VLC_ENOMEM;
    char *sout;
    if( asprintf( &sout, "sout=#transcode{acodec=%s,ab=%u,channels=2,"
                  "samplerate=44100,threads=%u}:"
                  "std{access=file,mux=%s,dst='%s'}",
                  acodec, d->bitrate, encoder_threads, mux, escaped ) < 0 )
    { free( escaped ); return VLC_ENOMEM; }
    free( escaped );
    char *uri = vlc_path2uri( source, NULL );
    input_item_t *item = uri ? input_item_New( uri, NULL ) : NULL; free( uri );
    if( item == NULL ) { free( sout ); return VLC_ENOMEM; }
    /* The stream-output chain does not reliably copy source tags (and a raw
     * MP3 stream has nowhere to carry them).  Seed the input with the catalog
     * metadata, then write those tags explicitly to the completed file. */
    transcode_set_metadata( item, entry );
    if( encoder_threads > 1 )
        msg_Dbg( obj, "portable-player transcode using %u encoder threads",
                 encoder_threads );
    input_item_AddOption( item, sout, VLC_INPUT_OPTION_TRUSTED ); free( sout );
    static const char *const opts[] = { "no-video", "no-spu", "no-osd",
                                        "no-sout-video", "sout-audio" };
    for( size_t i = 0; i < ARRAY_SIZE( opts ); ++i )
        input_item_AddOption( item, opts[i], VLC_INPUT_OPTION_TRUSTED );
    /* Apple's older AAC decoders reject Perceptual Noise Substitution even
     * though it is valid AAC.  Pass the native FFmpeg encoder option only for
     * AAC iPod outputs, leaving every other transcode profile untouched. */
    if( !strcasecmp( d->kind, "ipod" ) && !strcasecmp( d->codec, "aac" ) )
        input_item_AddOption( item, "sout-avcodec-options=aac_pns=0",
                              VLC_INPUT_OPTION_TRUSTED );
    if( status_sys == NULL )
    {
        int ret = input_Read( obj, item );
        struct stat st;
        if( ret != VLC_SUCCESS || vlc_stat( destination, &st ) != 0
         || st.st_size == 0 )
        { input_item_Release( item ); vlc_unlink( destination );
          return VLC_EGENERIC; }
        transcode_write_metadata( obj, destination, entry );
        input_item_Release( item );
        return VLC_SUCCESS;
    }

    int ret = VLC_EGENERIC;
    input_thread_t *input = input_Create( obj, item, "device-transcode",
                                          NULL, NULL );
    if( input )
    {
        bool cancelled = false;
        transcode_monitor_t monitor = {
            .sys = status_sys,
            .transfer = transfer,
        };
        vlc_mutex_init( &monitor.lock );
        vlc_cond_init( &monitor.wait );
        var_AddCallback( input, "intf-event", transcode_event, &monitor );
        if( input_Start( input ) == VLC_SUCCESS )
        {
            vlc_cleanup_push( transcode_cancel_cleanup, input );
            vlc_mutex_lock( &monitor.lock );
            while( !monitor.finished
                && !transfer_cancelled( status_sys, transfer ) )
                vlc_cond_timedwait( &monitor.wait, &monitor.lock,
                                    mdate() + CLOCK_FREQ / 10 );
            cancelled = transfer_cancelled( status_sys, transfer );
            vlc_mutex_unlock( &monitor.lock );
            if( cancelled ) input_Stop( input );
            vlc_cleanup_pop();
            ret = cancelled ? VLC_EGENERIC : VLC_SUCCESS;
        }
        var_DelCallback( input, "intf-event", transcode_event, &monitor );
        input_Close( input );
        vlc_cond_destroy( &monitor.wait );
        vlc_mutex_destroy( &monitor.lock );
    }
    struct stat st;
    if( ret != VLC_SUCCESS || vlc_stat( destination, &st ) != 0 || st.st_size == 0 )
    { input_item_Release( item ); vlc_unlink( destination ); return VLC_EGENERIC; }
    transcode_write_metadata( obj, destination, entry );
    input_item_Release( item );
    return VLC_SUCCESS;
}

static int copy_file_tracked( services_discovery_sys_t *sys, uint64_t transfer,
                              const char *source, const char *destination )
{
    FILE *input = vlc_fopen( source, "rb" );
    if( input == NULL ) return VLC_EGENERIC;
    FILE *output = vlc_fopen( destination, "wb" );
    if( output == NULL ) { fclose( input ); return VLC_EGENERIC; }
    struct stat st;
    uint64_t total = vlc_stat( source, &st ) == 0 ? (uint64_t)st.st_size : 0;
    uint64_t done = 0;
    char buffer[64 * 1024];
    int ret = VLC_SUCCESS;
    size_t count;
    while( (count = fread( buffer, 1, sizeof( buffer ), input )) > 0 )
    {
        vlc_testcancel();
        if( transfer_cancelled( sys, transfer ) )
        { ret = VLC_EGENERIC; break; }
        if( fwrite( buffer, 1, count, output ) != count )
        { ret = VLC_EGENERIC; break; }
        done += count;
        transfer_update( sys, transfer, SD_TRANSFER_COPYING,
                         total ? (unsigned)((done * 100) / total) : 0 );
    }
    if( ferror( input ) || fflush( output ) != 0 || ferror( output ) )
        ret = VLC_EGENERIC;
    fclose( input );
    if( fclose( output ) != 0 ) ret = VLC_EGENERIC;
    if( ret != VLC_SUCCESS ) vlc_unlink( destination );
    return ret;
}

static int copy_memory_tracked( services_discovery_sys_t *sys,
                                uint64_t transfer, const unsigned char *data,
                                size_t size, const char *destination )
{
    FILE *output = vlc_fopen( destination, "wb" );
    if( output == NULL ) return VLC_EGENERIC;
    size_t done = 0;
    int ret = VLC_SUCCESS;
    while( done < size )
    {
        vlc_testcancel();
        if( transfer_cancelled( sys, transfer ) )
        { ret = VLC_EGENERIC; break; }
        size_t chunk = size - done;
        if( chunk > 1024 * 1024 ) chunk = 1024 * 1024;
        if( fwrite( data + done, 1, chunk, output ) != chunk )
        { ret = VLC_EGENERIC; break; }
        done += chunk;
        transfer_update( sys, transfer, SD_TRANSFER_COPYING,
                         size ? (unsigned)((done * 100) / size) : 100 );
    }
    if( fflush( output ) != 0 || ferror( output ) ) ret = VLC_EGENERIC;
    if( fclose( output ) != 0 ) ret = VLC_EGENERIC;
    if( ret != VLC_SUCCESS ) vlc_unlink( destination );
    return ret;
}

static char *transcode_staging_file( void )
{
    char *cache = config_GetUserDir( VLC_CACHE_DIR );
    if( cache == NULL ) return NULL;
    char *directory = pvlc_path_join( cache, "portable-transcodes" );
    free( cache );
    if( directory == NULL ) return NULL;
    if( pvlc_mkdir_parents( directory ) != VLC_SUCCESS )
    { free( directory ); return NULL; }
    char *path = NULL;
    if( asprintf( &path, "%s/pvlc-XXXXXX", directory ) < 0 ) path = NULL;
    free( directory );
    if( path == NULL ) return NULL;
    int fd = vlc_mkstemp( path );
    if( fd < 0 ) { free( path ); return NULL; }
    vlc_close( fd );
    return path;
}

static int read_staging_file( const char *path, unsigned char **data,
                              size_t *size )
{
    *data = NULL; *size = 0;
    struct stat st;
    if( vlc_stat( path, &st ) != 0 || st.st_size <= 0
     || (uintmax_t)st.st_size > SIZE_MAX ) return VLC_EGENERIC;
    FILE *input = vlc_fopen( path, "rb" );
    if( input == NULL ) return VLC_EGENERIC;
    unsigned char *buffer = malloc( (size_t)st.st_size );
    if( buffer == NULL ) { fclose( input ); return VLC_ENOMEM; }
    size_t read = fread( buffer, 1, (size_t)st.st_size, input );
    int ret = read == (size_t)st.st_size && !ferror( input )
            ? VLC_SUCCESS : VLC_EGENERIC;
    fclose( input );
    if( ret != VLC_SUCCESS ) { free( buffer ); return ret; }
    *data = buffer; *size = read;
    return VLC_SUCCESS;
}

/* Rockbox reliably understands a baseline JPEG beside the album.  Artwork
 * discovered from PNG/WebP/progressive-JPEG sources is therefore decoded and
 * re-encoded instead of being copied byte-for-byte. */
static void rockbox_write_cover( vlc_object_t *obj,
                                 const pvlc_media_entry_t *entry,
                                 const char *media_destination )
{
    char *art = portable_artwork_url( entry );
    if( art == NULL ) return;
    char *directory = strdup( media_destination );
    char *slash = directory ? strrchr( directory, '/' ) : NULL;
#ifdef _WIN32
    char *backslash = directory ? strrchr( directory, '\\' ) : NULL;
    if( backslash && (!slash || backslash > slash) ) slash = backslash;
#endif
    if( slash == NULL ) { free( directory ); free( art ); return; }
    *slash = '\0';
    char *destination = pvlc_path_join( directory, "cover.jpg" );
    free( directory );
    struct stat st;
    if( destination == NULL || (vlc_stat( destination, &st ) == 0
                             && st.st_size > 0) )
    { free( destination ); free( art ); return; }

    image_handler_t *handler = image_HandlerCreate( obj );
    if( handler == NULL ) { free( destination ); free( art ); return; }
    video_format_t input, decoded, output;
    video_format_Init( &input, 0 );
    video_format_Init( &decoded, 0 );
    picture_t *picture = image_ReadUrl( handler, art, &input, &decoded );
    if( picture )
    {
        unsigned width = decoded.i_visible_width ? decoded.i_visible_width
                                                  : decoded.i_width;
        unsigned height = decoded.i_visible_height ? decoded.i_visible_height
                                                     : decoded.i_height;
        if( width > 600 || height > 600 )
        {
            double scale = (double)600 / (width > height ? width : height);
            width = (unsigned)(width * scale); height = (unsigned)(height * scale);
        }
        video_format_Init( &output, VLC_CODEC_JPEG );
        output.i_width = output.i_visible_width = width ? width : 1;
        output.i_height = output.i_visible_height = height ? height : 1;
        output.i_sar_num = output.i_sar_den = 1;
        if( image_WriteUrl( handler, picture, &decoded, &output,
                            destination ) != VLC_SUCCESS )
            vlc_unlink( destination );
        video_format_Clean( &output );
        picture_Release( picture );
    }
    video_format_Clean( &input ); video_format_Clean( &decoded );
    image_HandlerDelete( handler ); free( destination ); free( art );
}

static char *sync_destination( vlc_object_t *obj, const device_config_t *d,
                               const pvlc_media_entry_t *e, bool transcoded,
                               bool podcast )
{
    int64_t mc = var_InheritInteger( obj, "powervlc-device-max-component" );
    int64_t mp = var_InheritInteger( obj, "powervlc-device-max-path" );
    size_t max_component = mc >= 32 && mc <= 240 ? (size_t)mc : 96;
    size_t max_path = mp >= 96 && mp <= 1024 ? (size_t)mp : 240;
    size_t root_len = strlen( d->path );
    unsigned components = podcast ? 2
                        : e->i_type == PVLC_MEDIA_AUDIO ? 3 : 2;
    size_t fair = max_path > root_len + 16
                ? (max_path - root_len - 16) / components : 16;
    if( fair < max_component ) max_component = fair < 16 ? 16 : fair;

    char *base = pvlc_sanitize_filename( filename_of( e->psz_path ), max_component );
    if( transcoded && base )
    {
        char *dot = strrchr( base, '.' ); if( dot ) *dot = '\0';
        const char *ext = !strcasecmp( d->codec, "aac" ) ? ".m4a"
                        : !strcasecmp( d->codec, "flac" ) ? ".flac" : ".mp3";
        char *renamed; if( asprintf( &renamed, "%s%s", base, ext ) >= 0 )
        { free( base ); base = renamed; }
    }
    char *dir = NULL;
    if( podcast )
        dir = pvlc_path_join( d->path, "Podcasts" );
    else if( e->i_type == PVLC_MEDIA_AUDIO )
    {
        char *music = pvlc_path_join( d->path, "Music" );
        char *artist = pvlc_sanitize_component( e->psz_artist, "Unknown Artist",
                                                max_component );
        char *album = pvlc_sanitize_component( e->psz_album, "Unknown Album",
                                               max_component );
        char *artist_dir = music && artist ? pvlc_path_join( music, artist ) : NULL;
        dir = artist_dir && album ? pvlc_path_join( artist_dir, album ) : NULL;
        free( music ); free( artist ); free( album ); free( artist_dir );
    }
    else
    {
        char *show = NULL; unsigned season = 0;
        if( pvlc_series_info( e->psz_path, &show, &season, NULL ) )
        {
            char *shows = pvlc_path_join( d->path, "Shows" );
            char *safe = pvlc_sanitize_component( show, "Unknown Show",
                                                  max_component );
            char *show_dir = shows && safe ? pvlc_path_join( shows, safe ) : NULL;
            char season_name[32]; snprintf( season_name, sizeof( season_name ),
                                            "Season %02u", season );
            dir = show_dir ? pvlc_path_join( show_dir, season_name ) : NULL;
            free( show ); free( shows ); free( safe ); free( show_dir );
        }
        else dir = pvlc_path_join( d->path, "Movies" );
    }
    char *destination = dir && base ? pvlc_path_join( dir, base ) : NULL;
    free( dir ); free( base );
    if( destination && strlen( destination ) > max_path )
    { free( destination ); return NULL; }
    return destination;
}

static uint64_t device_path_hash( const char *value )
{
    uint64_t hash = UINT64_C(1469598103934665603);
    while( *value ) { hash ^= (unsigned char)*value++; hash *= UINT64_C(1099511628211); }
    return hash;
}

static bool destination_used( const sync_state_t *state, const char *path )
{
    for( size_t i = 0; i < state->count; ++i )
        if( !strcasecmp( state->entries[i].destination, path ) ) return true;
    return false;
}

/* A deterministic hash suffix resolves same-name media without ever growing
 * beyond the configured component or full-path limits. */
static char *unique_device_destination( vlc_object_t *obj,
                                        const device_config_t *device,
                                        const pvlc_media_entry_t *entry,
                                        char *suggested,
                                        const sync_entry_t *previous,
                                        bool transcoded,
                                        const sync_state_t *next )
{
    int64_t mc = var_InheritInteger( obj, "powervlc-device-max-component" );
    int64_t mp = var_InheritInteger( obj, "powervlc-device-max-path" );
    size_t max_component = mc >= 32 && mc <= 240 ? (size_t)mc : 96;
    size_t max_path = mp >= 96 && mp <= 1024 ? (size_t)mp : 240;
    const char *mode = transcoded ? "transcode" : "copy";
    if( previous && !strcmp( previous->mode, mode )
     && strlen( previous->destination ) <= max_path )
    {
        free( suggested );
        return strdup( previous->destination );
    }
    struct stat st;
    if( !destination_used( next, suggested )
     && (vlc_stat( suggested, &st ) != 0
      || (!transcoded && pvlc_files_equal( entry->psz_path, suggested,
                                           entry->i_size ))) )
        return suggested;

    char *slash = strrchr( suggested, '/' );
#ifdef _WIN32
    char *backslash = strrchr( suggested, '\\' );
    if( backslash && (!slash || backslash > slash) ) slash = backslash;
#endif
    if( slash == NULL ) { free( suggested ); return NULL; }
    size_t directory_length = (size_t)(slash - suggested);
    const char *filename = slash + 1;
    const char *dot = strrchr( filename, '.' );
    size_t stem_length = dot ? (size_t)(dot - filename) : strlen( filename );
    size_t extension_length = dot ? strlen( dot ) : 0;
    size_t available = max_path > directory_length + 1
                     ? max_path - directory_length - 1 : 0;
    if( available > max_component ) available = max_component;
    uint64_t hash = device_path_hash( entry->psz_path );
    for( unsigned attempt = 0; attempt < 10000; ++attempt )
    {
        char suffix[40];
        int suffix_length = attempt == 0
            ? snprintf( suffix, sizeof( suffix ), "-%016" PRIx64, hash )
            : snprintf( suffix, sizeof( suffix ), "-%016" PRIx64 "-%u",
                        hash, attempt + 1 );
        if( suffix_length < 0
         || (size_t)suffix_length + extension_length >= available ) break;
        size_t stem_limit = available - extension_length
                          - (size_t)suffix_length;
        size_t shortened = stem_length < stem_limit ? stem_length : stem_limit;
        while( shortened > 0
            && ((unsigned char)filename[shortened] & 0xc0) == 0x80 ) shortened--;
        char *candidate = malloc( directory_length + 1 + shortened
                                  + (size_t)suffix_length
                                  + extension_length + 1 );
        if( candidate == NULL ) break;
        memcpy( candidate, suggested, directory_length + 1 );
        memcpy( candidate + directory_length + 1, filename, shortened );
        memcpy( candidate + directory_length + 1 + shortened, suffix,
                (size_t)suffix_length );
        if( extension_length )
            memcpy( candidate + directory_length + 1 + shortened
                    + (size_t)suffix_length, dot, extension_length );
        candidate[directory_length + 1 + shortened + (size_t)suffix_length
                  + extension_length] = '\0';
        if( !destination_used( next, candidate )
         && (vlc_stat( candidate, &st ) != 0
          || (!transcoded && pvlc_files_equal( entry->psz_path, candidate,
                                               entry->i_size ))) )
        { free( suggested ); return candidate; }
        free( candidate );
    }
    free( suggested );
    VLC_UNUSED( device );
    return NULL;
}

static int sync_dropped_entry( services_discovery_t *sd,
                               pvlc_media_entry_t *entry,
                               sync_state_t *state, uint64_t transfer )
{
    device_config_t *device = &sd->p_sys->device;
    bool transcode = device->transcode
                  && entry->i_type == PVLC_MEDIA_AUDIO
                  && !has_extension( entry->psz_path, device->codec )
                  && !( !strcasecmp( device->codec, "aac" )
                     && has_extension( entry->psz_path, "m4a" ) );
    sync_entry_t *previous = state_find_linear( state, entry->psz_path );
    char *destination = sync_destination( VLC_OBJECT( sd ), device, entry,
                                          transcode, false );
    if( destination )
        destination = unique_device_destination( VLC_OBJECT( sd ), device,
                              entry, destination, previous, transcode, state );
    if( destination == NULL ) return VLC_EGENERIC;
    transfer_set_destination( sd->p_sys, transfer, destination );
    if( transfer_cancelled( sd->p_sys, transfer ) )
    {
        transfer_update( sd->p_sys, transfer, SD_TRANSFER_CANCELLED, 0 );
        free( destination );
        return VLC_EGENERIC;
    }
    char *directory = strdup( destination );
    char *slash = directory ? strrchr( directory, '/' ) : NULL;
#ifdef _WIN32
    char *backslash = directory ? strrchr( directory, '\\' ) : NULL;
    if( backslash && (!slash || backslash > slash) ) slash = backslash;
#endif
    if( slash ) { *slash = '\0'; pvlc_mkdir_parents( directory ); }
    free( directory );
    transfer_update( sd->p_sys, transfer,
                     transcode ? SD_TRANSFER_TRANSCODING : SD_TRANSFER_COPYING,
                     0 );
    int ret = transcode ? transcode_file( VLC_OBJECT( sd ), entry->psz_path,
                                          destination, device, entry, sd->p_sys,
                                          transfer )
                        : copy_file_tracked( sd->p_sys, transfer,
                                             entry->psz_path, destination );
    bool cancelled = transfer_cancelled( sd->p_sys, transfer );
    transfer_update( sd->p_sys, transfer,
                     ret == VLC_SUCCESS ? SD_TRANSFER_COMPLETED
                     : cancelled ? SD_TRANSFER_CANCELLED : SD_TRANSFER_FAILED,
                     ret == VLC_SUCCESS ? 100 : 0 );
    if( ret == VLC_SUCCESS && transcode
     && !strcasecmp( device->kind, "rockbox" ) )
        rockbox_write_cover( VLC_OBJECT( sd ), entry, destination );
    if( ret == VLC_SUCCESS )
    {
        const char *mode = transcode ? device_mode_transcode
                                     : device_mode_copy;
        if( previous )
        {
            char *new_destination = strdup( destination );
            char *new_mode = strdup( mode );
            if( new_destination == NULL || new_mode == NULL )
            {
                free( new_destination ); free( new_mode );
                ret = VLC_ENOMEM;
            }
            else
            {
                free( previous->destination ); free( previous->mode );
                previous->destination = new_destination;
                previous->mode = new_mode;
                previous->size = entry->i_size;
                previous->mtime = entry->i_mtime;
            }
        }
        else
        {
            sync_entry_t added = { entry->psz_path, destination, (char *)mode,
                                   entry->i_size, entry->i_mtime };
            ret = state_append( state, &added );
        }
    }
    free( destination );
    return ret;
}

typedef struct
{
    pvlc_media_entry_t entry;
    char *destination;
    uint64_t transfer;
    bool transcode;
    int result;
} dropped_job_t;

typedef struct
{
    services_discovery_t *sd;
    dropped_job_t *jobs;
    size_t count;
    size_t next;
    vlc_mutex_t lock;
} dropped_workers_t;

typedef struct
{
    vlc_thread_t *threads;
    size_t count;
} dropped_threads_cleanup_t;

static void cleanup_dropped_threads( void *opaque )
{
    dropped_threads_cleanup_t *cleanup = opaque;
    for( size_t i = 0; i < cleanup->count; ++i )
        vlc_cancel( cleanup->threads[i] );
    for( size_t i = 0; i < cleanup->count; ++i )
        vlc_join( cleanup->threads[i], NULL );
    free( cleanup->threads );
}

static void *run_dropped_transcodes( void *opaque )
{
    dropped_workers_t *workers = opaque;
    for( ;; )
    {
        vlc_mutex_lock( &workers->lock );
        size_t index = workers->next;
        while( index < workers->count && !workers->jobs[index].transcode )
            index++;
        workers->next = index < workers->count ? index + 1 : index;
        vlc_mutex_unlock( &workers->lock );
        if( index >= workers->count ) break;

        dropped_job_t *job = &workers->jobs[index];
        if( transfer_cancelled( workers->sd->p_sys, job->transfer ) )
            job->result = VLC_EGENERIC;
        else
        {
            transfer_update( workers->sd->p_sys, job->transfer,
                             SD_TRANSFER_TRANSCODING, 0 );
            job->result = transcode_file( VLC_OBJECT( workers->sd ),
                              job->entry.psz_path, job->destination,
                              &workers->sd->p_sys->device, &job->entry,
                              workers->sd->p_sys, job->transfer );
        }
        bool cancelled = transfer_cancelled( workers->sd->p_sys,
                                              job->transfer );
        transfer_update( workers->sd->p_sys, job->transfer,
                         job->result == VLC_SUCCESS ? SD_TRANSFER_COMPLETED
                         : cancelled ? SD_TRANSFER_CANCELLED
                                     : SD_TRANSFER_FAILED,
                         job->result == VLC_SUCCESS ? 100 : 0 );
    }
    return NULL;
}

static void state_store_completed_job( sync_state_t *state,
                                       const dropped_job_t *job )
{
    const char *mode = job->transcode ? device_mode_transcode
                                      : device_mode_copy;
    sync_entry_t *previous = state_find_linear( state, job->entry.psz_path );
    if( previous )
    {
        char *destination = strdup( job->destination );
        char *new_mode = strdup( mode );
        if( destination && new_mode )
        {
            free( previous->destination ); free( previous->mode );
            previous->destination = destination; previous->mode = new_mode;
            previous->size = job->entry.i_size;
            previous->mtime = job->entry.i_mtime;
            return;
        }
        free( destination ); free( new_mode );
        return;
    }
    sync_entry_t added = { job->entry.psz_path, job->destination, (char *)mode,
                           job->entry.i_size, job->entry.i_mtime };
    state_append( state, &added );
}

static playlist_item_t *regular_loaded_item_for_path( playlist_item_t *parent,
                                                       const char *path,
                                                       unsigned depth )
{
    if( parent == NULL || depth > 64 || parent->i_children < 0 ) return NULL;
    for( int i = 0; i < parent->i_children; ++i )
    {
        playlist_item_t *child = parent->pp_children[i];
        char *uri = child->p_input ? input_item_GetURI( child->p_input ) : NULL;
        char *child_path = uri ? vlc_uri2path( uri ) : NULL;
        free( uri );
        bool exact = child_path && !strcmp( child_path, path );
        bool ancestor = child_path && path_has_device_prefix( child_path, path );
        free( child_path );
        if( exact ) return child;
        if( ancestor )
        {
            playlist_item_t *found = regular_loaded_item_for_path(
                                                child, path, depth + 1 );
            if( found ) return found;
        }
    }
    return NULL;
}

/* A completed regular/Rockbox file copy should appear immediately, but a
 * complete service refresh would collapse every open directory. Add the leaf
 * only when its destination directory is already materialised; otherwise its
 * normal lazy enumeration will discover the file when first expanded. */
static void regular_publish_completed_jobs( services_discovery_t *sd,
                                             dropped_job_t *jobs,
                                             size_t count )
{
    playlist_t *core = (playlist_t *)sd->obj.parent;
    playlist_Lock( core );
    for( size_t i = 0; i < count; ++i )
    {
        dropped_job_t *job = &jobs[i];
        if( job->result != VLC_SUCCESS || job->destination == NULL ) continue;
        char *directory = strdup( job->destination );
        char *slash = directory ? strrchr( directory, '/' ) : NULL;
        if( slash == NULL ) { free( directory ); continue; }
        *slash = '\0';
        playlist_item_t *parent = NULL;
        char *managed_path = NULL;
        for( size_t root = 0; root < sd->p_sys->visible_root_count; ++root )
        {
            input_item_t *visible = sd->p_sys->visible_roots[root];
            char *uri = input_item_GetURI( visible );
            char *path = uri ? vlc_uri2path( uri ) : NULL;
            free( uri );
            bool contains = path && (!strcmp( path, directory )
                          || path_has_device_prefix( path, directory ));
            if( contains )
            {
                parent = playlist_ItemGetByInput( core, visible );
                managed_path = path;
                break;
            }
            free( path );
        }
        if( parent == NULL || managed_path == NULL )
        { free( managed_path ); free( directory ); continue; }
        size_t root_length = strlen( managed_path );
        char *relative = strlen( directory ) > root_length
                       ? strdup( directory + root_length ) : strdup( "" );
        while( relative && (*relative == '/' || *relative == '\\') )
            memmove( relative, relative + 1, strlen( relative ) );
        char *built = strdup( managed_path );
        free( managed_path );
        char *save = NULL;
        for( char *component = relative
                    ? strtok_r( relative, "/\\", &save ) : NULL;
             component && parent; component = strtok_r( NULL, "/\\", &save ) )
        {
            char *next = built ? pvlc_path_join( built, component ) : NULL;
            if( next == NULL ) { parent = NULL; break; }
            playlist_item_t *child = regular_loaded_item_for_path( parent,
                                                                    next, 0 );
            if( child == NULL )
            {
                /* Publish the first newly-created directory. Its children
                 * remain lazy and will be read from disk when it is opened. */
                char *uri = vlc_path2uri( next, NULL );
                input_item_t *input = uri ? input_item_NewExt( uri, component,
                                      -1, ITEM_TYPE_DIRECTORY, ITEM_LOCAL ) : NULL;
                free( uri );
                if( input )
                {
                    playlist_NodeAddInput( core, input, parent, PLAYLIST_END );
                    input_item_Release( input );
                }
                parent = NULL;
            }
            else
            {
                parent = child;
                if( parent->i_children < 0 ) parent = NULL;
            }
            free( built ); built = next;
        }
        free( built ); free( relative ); free( directory );
        if( parent == NULL || parent->i_children < 0 ) continue;
        if( regular_loaded_item_for_path( parent, job->destination, 0 ) )
            continue;
        char *uri = vlc_path2uri( job->destination, NULL );
        const char *name = strrchr( job->destination, '/' );
        input_item_t *input = uri ? input_item_NewFile( uri,
                                name ? name + 1 : job->destination,
                                -1, ITEM_LOCAL ) : NULL;
        free( uri );
        if( input )
        {
            if( job->entry.psz_artist ) input_item_SetMeta( input,
                                   vlc_meta_Artist, job->entry.psz_artist );
            if( job->entry.psz_album ) input_item_SetMeta( input,
                                   vlc_meta_Album, job->entry.psz_album );
            input_item_SetPreparsed( input, true );
            playlist_NodeAddInput( core, input, parent, PLAYLIST_END );
            input_item_Release( input );
        }
    }
    playlist_Unlock( core );
}

static bool sync_dropped_regular_files( services_discovery_t *sd, char **paths,
                                        uint64_t *transfers, size_t count )
{
    for( size_t i = 0; i < count; ++i )
    {
        struct stat st;
        if( path_is_inside( sd->p_sys->device.path, paths[i] )
         || vlc_stat( paths[i], &st ) != 0 || !S_ISREG( st.st_mode ) )
            return false;
    }

    sync_state_t reservations;
    if( state_load( &sd->p_sys->device, &reservations ) != VLC_SUCCESS )
        memset( &reservations, 0, sizeof( reservations ) );
    dropped_job_t *jobs = calloc( count, sizeof( *jobs ) );
    if( jobs == NULL ) { state_clear( &reservations ); return true; }

    size_t prepared = 0;
    for( size_t i = 0; i < count; ++i )
    {
        dropped_job_t *job = &jobs[prepared];
        job->transfer = transfers[i]; job->result = VLC_EGENERIC;
        if( transfer_cancelled( sd->p_sys, job->transfer ) )
        { transfer_update( sd->p_sys, job->transfer, SD_TRANSFER_CANCELLED, 0 );
          continue; }
        if( pvlc_scan_file( VLC_OBJECT( sd ), paths[i], paths[i], &job->entry )
            != VLC_SUCCESS )
        { transfer_update( sd->p_sys, job->transfer, SD_TRANSFER_FAILED, 0 );
          continue; }
        job->transcode = sd->p_sys->device.transcode
                      && job->entry.i_type == PVLC_MEDIA_AUDIO
                      && !has_extension( job->entry.psz_path,
                                         sd->p_sys->device.codec )
                      && !( !strcasecmp( sd->p_sys->device.codec, "aac" )
                         && has_extension( job->entry.psz_path, "m4a" ) );
        sync_entry_t *previous = state_find_linear( &reservations,
                                                    job->entry.psz_path );
        job->destination = sync_destination( VLC_OBJECT( sd ),
                            &sd->p_sys->device, &job->entry,
                            job->transcode, false );
        if( job->destination )
            job->destination = unique_device_destination( VLC_OBJECT( sd ),
                &sd->p_sys->device, &job->entry, job->destination, previous,
                job->transcode, &reservations );
        if( job->destination == NULL )
        { pvlc_media_entry_clear( &job->entry );
          transfer_update( sd->p_sys, job->transfer, SD_TRANSFER_FAILED, 0 );
          continue; }
        char *directory = strdup( job->destination );
        char *slash = directory ? strrchr( directory, '/' ) : NULL;
#ifdef _WIN32
        char *backslash = directory ? strrchr( directory, '\\' ) : NULL;
        if( backslash && (!slash || backslash > slash) ) slash = backslash;
#endif
        if( slash ) { *slash = '\0'; pvlc_mkdir_parents( directory ); }
        free( directory );
        transfer_set_destination( sd->p_sys, job->transfer, job->destination );
        sync_entry_t reservation = { job->entry.psz_path, job->destination,
            job->transcode ? device_mode_transcode : device_mode_copy,
            job->entry.i_size, job->entry.i_mtime };
        if( previous )
        {
            free( previous->destination ); free( previous->mode );
            previous->destination = strdup( reservation.destination );
            previous->mode = strdup( reservation.mode );
            previous->size = reservation.size; previous->mtime = reservation.mtime;
        }
        else state_append( &reservations, &reservation );
        prepared++;
    }
    state_clear( &reservations );

    dropped_workers_t workers = { .sd = sd, .jobs = jobs, .count = prepared };
    vlc_mutex_init( &workers.lock );
    unsigned task_limit = portable_transcode_task_limit();
    size_t transcodes = 0;
    for( size_t i = 0; i < prepared; ++i ) if( jobs[i].transcode ) transcodes++;
    size_t worker_count = transcodes < task_limit ? transcodes : task_limit;
    sd->p_sys->transcode_parallelism = worker_count ? (unsigned)worker_count : 1;
    size_t background_count = worker_count > 0 ? worker_count - 1 : 0;
    vlc_thread_t *threads = background_count ? calloc( background_count,
                                                   sizeof( *threads ) ) : NULL;
    size_t started = 0;
    for( ; threads && started < background_count; ++started )
        if( vlc_clone( &threads[started], run_dropped_transcodes, &workers,
                       VLC_THREAD_PRIORITY_LOW ) ) break;
    dropped_threads_cleanup_t cleanup = { threads, started };
    vlc_cleanup_push( cleanup_dropped_threads, &cleanup );

    /* Copies deliberately stay on this one lane even while the independent
     * transcoding workers use the available processor cores. */
    for( size_t i = 0; i < prepared; ++i ) if( !jobs[i].transcode )
    {
        dropped_job_t *job = &jobs[i];
        if( transfer_cancelled( sd->p_sys, job->transfer ) )
            job->result = VLC_EGENERIC;
        else
        {
            char *dir = strdup( job->destination );
            char *slash = dir ? strrchr( dir, '/' ) : NULL;
            if( slash ) { *slash = '\0'; pvlc_mkdir_parents( dir ); }
            free( dir );
            transfer_update( sd->p_sys, job->transfer, SD_TRANSFER_COPYING, 0 );
            job->result = copy_file_tracked( sd->p_sys, job->transfer,
                                  job->entry.psz_path, job->destination );
        }
        bool cancelled = transfer_cancelled( sd->p_sys, job->transfer );
        transfer_update( sd->p_sys, job->transfer,
                         job->result == VLC_SUCCESS ? SD_TRANSFER_COMPLETED
                         : cancelled ? SD_TRANSFER_CANCELLED
                                     : SD_TRANSFER_FAILED,
                         job->result == VLC_SUCCESS ? 100 : 0 );
    }
    if( transcodes ) run_dropped_transcodes( &workers );
    for( size_t i = 0; i < started; ++i ) vlc_join( threads[i], NULL );
    cleanup.count = 0;
    sd->p_sys->transcode_parallelism = 1;
    free( threads );
    vlc_cleanup_pop();
    vlc_mutex_destroy( &workers.lock );

    sync_state_t final_state;
    if( state_load( &sd->p_sys->device, &final_state ) != VLC_SUCCESS )
        memset( &final_state, 0, sizeof( final_state ) );
    for( size_t i = 0; i < prepared; ++i )
    {
        if( jobs[i].result == VLC_SUCCESS )
        {
            state_store_completed_job( &final_state, &jobs[i] );
            if( jobs[i].transcode
             && !strcasecmp( sd->p_sys->device.kind, "rockbox" ) )
                rockbox_write_cover( VLC_OBJECT( sd ), &jobs[i].entry,
                                     jobs[i].destination );
        }
    }
    state_sort( &final_state );
    state_save( &sd->p_sys->device, &final_state, 0 );
    regular_publish_completed_jobs( sd, jobs, prepared );
    for( size_t i = 0; i < prepared; ++i )
    {
        pvlc_media_entry_clear( &jobs[i].entry );
        free( jobs[i].destination );
    }
    state_clear( &final_state ); free( jobs );
    return true;
}

#ifdef HAVE_LIBGPOD
static guint32 ipod_uint_meta( const pvlc_media_entry_t *entry,
                               vlc_meta_type_t type )
{
    const char *value = pvlc_media_meta( entry, type );
    return value && *value ? (guint32)strtoul( value, NULL, 10 ) : 0;
}

static Itdb_Track *ipod_track_from_entry( Itdb_iTunesDB *database,
                                          const pvlc_media_entry_t *entry,
                                          bool album_artist_as_composer )
{
    Itdb_Track *track = itdb_track_new();
    if( track == NULL ) return NULL;
    track->title = g_strdup( entry->psz_title ? entry->psz_title : "" );
    track->artist = g_strdup( entry->psz_artist ? entry->psz_artist : "" );
    track->album = g_strdup( entry->psz_album ? entry->psz_album : "" );
    const char *album_artist = pvlc_media_meta( entry, vlc_meta_AlbumArtist );
    track->albumartist = g_strdup( album_artist );
    track->genre = g_strdup( pvlc_media_meta( entry, vlc_meta_Genre ) );
    track->composer = g_strdup( album_artist_as_composer && album_artist
                             && *album_artist ? album_artist
                              : pvlc_media_extra( entry, "Composer" ) );
    track->comment = g_strdup( pvlc_media_meta( entry, vlc_meta_Description ) );
    track->track_nr = ipod_uint_meta( entry, vlc_meta_TrackNumber );
    track->tracks = ipod_uint_meta( entry, vlc_meta_TrackTotal );
    track->cd_nr = ipod_uint_meta( entry, vlc_meta_DiscNumber );
    track->cds = ipod_uint_meta( entry, vlc_meta_DiscTotal );
    const char *date = pvlc_media_meta( entry, vlc_meta_Date );
    if( date && isdigit( (unsigned char)date[0] ) )
    {
        char year[5] = { 0 };
        strncpy( year, date, 4 );
        track->year = (guint32)strtoul( year, NULL, 10 );
    }
    track->tracklen = entry->i_duration > 0
                    ? (guint32)(entry->i_duration / 1000) : 0;
    track->size = entry->i_size;
    track->rating = entry->i_rating * ITDB_RATING_STEP;
    track->mediatype = entry->i_type == PVLC_MEDIA_VIDEO
                     ? ITDB_MEDIATYPE_MOVIE : ITDB_MEDIATYPE_AUDIO;
    track->time_added = time( NULL );
    track->time_modified = entry->i_mtime;
    itdb_track_add( database, track, -1 );
    Itdb_Playlist *master = itdb_playlist_mpl( database );
    if( master ) itdb_playlist_add_track( master, track, -1 );
    return track;
}

/* itdb_track_remove() only unlinks the database's track list. libgpod leaves
 * every playlist member untouched, so freeing the track first creates stale
 * pointers that crash the next itdb_write() while sort keys are generated. */
static void ipod_remove_track_completely( Itdb_iTunesDB *database,
                                          Itdb_Track *track )
{
    if( database == NULL || track == NULL ) return;
    for( GList *entry = database->playlists; entry; entry = entry->next )
    {
        Itdb_Playlist *playlist = entry->data;
        while( g_list_find( playlist->members, track ) )
            itdb_playlist_remove_track( playlist, track );
    }
    itdb_track_remove( track );
}

static bool ipod_stage_added_path( services_discovery_sys_t *sys,
                                   const char *path )
{
    char *copy = strdup( path );
    char **grown = copy ? realloc( sys->pending_ipod_additions,
        (sys->pending_ipod_addition_count + 1) * sizeof( *grown ) ) : NULL;
    if( grown == NULL ) { free( copy ); return false; }
    sys->pending_ipod_additions = grown;
    sys->pending_ipod_additions[sys->pending_ipod_addition_count++] = copy;
    vlc_mutex_lock( &sys->lock ); sys->pending_changes = true;
    vlc_mutex_unlock( &sys->lock );
    return true;
}

/* The compact session index is intentionally immutable while branches are
 * open. Publish staged deletions in a tiny local companion file so every
 * later expansion can filter the same paths without rebuilding the tree or
 * touching the iPod. */
static int ipod_write_deletion_overlay( services_discovery_sys_t *sys )
{
    if( sys->ipod_index_path == NULL ) return VLC_EGENERIC;
    char *path = NULL, *tmp = NULL;
    if( asprintf( &path, "%s.deleted", sys->ipod_index_path ) < 0 ) path = NULL;
    if( path && asprintf( &tmp, "%s.tmp", path ) < 0 ) tmp = NULL;
    if( path == NULL || tmp == NULL )
    { free( path ); free( tmp ); return VLC_ENOMEM; }
    if( sys->pending_ipod_deletion_count == 0 )
    {
        vlc_unlink( path ); free( path ); free( tmp ); return VLC_SUCCESS;
    }
    if( sys->pending_ipod_deletion_count > UINT32_MAX )
    { free( path ); free( tmp ); return VLC_EGENERIC; }
    FILE *file = vlc_fopen( tmp, "wb" );
    if( file == NULL ) { free( path ); free( tmp ); return VLC_EGENERIC; }
    static const unsigned char magic[8] = {
        'P', 'V', 'L', 'C', 'D', 'E', 'L', 1
    };
    int ret = pvlc_binary_write( file, magic, sizeof( magic ) );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file,
                         (uint32_t)sys->pending_ipod_deletion_count );
    for( size_t i = 0; i < sys->pending_ipod_deletion_count
                             && ret == VLC_SUCCESS; ++i )
    {
        char *uri = vlc_path2uri( sys->pending_ipod_deletions[i], NULL );
        ret = uri ? pvlc_binary_write_string( file, uri ) : VLC_ENOMEM;
        free( uri );
    }
    bool failed = ret != VLC_SUCCESS || fflush( file ) != 0 || ferror( file );
    if( fclose( file ) != 0 ) failed = true;
    if( !failed ) failed = vlc_rename( tmp, path ) != 0;
    if( failed ) vlc_unlink( tmp );
    free( path ); free( tmp );
    return failed ? VLC_EGENERIC : VLC_SUCCESS;
}

static void ipod_publish_added_track( services_discovery_t *, Itdb_Track * );
static int ipod_build_local_index( services_discovery_t * );
static void ipod_rebind_music_views( services_discovery_t * );

/* iTunes uses four-character names inside the Fxx directories. Besides
 * matching Apple's convention, this avoids repeating libgpod's long prefix
 * in every mhit path stored in iTunesDB. The base-36 namespace is probed on
 * the case-insensitive iPod filesystem, so existing media are never reused. */
static gchar *ipod_short_destination( const gchar *allocated,
                                      const char *source,
                                      const char *const *reserved,
                                      size_t reserved_count )
{
    if( allocated == NULL ) return NULL;
    const char *slash = strrchr( allocated, '/' );
    if( slash == NULL ) return g_strdup( allocated );
    const char *dot = strrchr( slash + 1, '.' );
    const char *extension = dot ? dot : "";
    if( strlen( extension ) > 16 ) extension = "";
    size_t directory_length = (size_t)(slash - allocated + 1);
    uint64_t hash = UINT64_C(1469598103934665603);
    for( const unsigned char *p = (const unsigned char *)(source ?: ""); *p; ++p )
    { hash ^= *p; hash *= UINT64_C(1099511628211); }
    static const char alphabet[] = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    const uint32_t namespace_size = 36u * 36u * 36u * 36u;
    for( uint32_t attempt = 0; attempt < namespace_size; ++attempt )
    {
        uint32_t value = (uint32_t)((hash + attempt) % namespace_size);
        char name[5];
        for( int i = 3; i >= 0; --i )
        { name[i] = alphabet[value % 36]; value /= 36; }
        name[4] = '\0';
        gchar *candidate = g_strdup_printf( "%.*s%s%s",
                            (int)directory_length, allocated, name, extension );
        if( candidate == NULL ) return NULL;
        bool already_reserved = false;
        for( size_t i = 0; i < reserved_count; ++i )
            if( reserved[i] && !strcmp( reserved[i], candidate ) )
            { already_reserved = true; break; }
        struct stat st;
        if( !already_reserved && vlc_lstat( candidate, &st ) != 0
         && errno == ENOENT )
            return candidate;
        g_free( candidate );
    }
    return NULL;
}

static int ipod_stage_entry( services_discovery_t *sd,
                             pvlc_media_entry_t *entry, uint64_t transfer )
{
    services_discovery_sys_t *sys = sd->p_sys;
    Itdb_Track *track = ipod_track_from_entry( sys->ipod_database, entry,
                                  sys->device.album_artist_as_composer );
    if( track == NULL ) return VLC_ENOMEM;
    bool transcode = sys->device.transcode && entry->i_type == PVLC_MEDIA_AUDIO
                  && !has_extension( entry->psz_path, sys->device.codec )
                  && !( !strcasecmp( sys->device.codec, "aac" )
                     && has_extension( entry->psz_path, "m4a" ) );
    char *hint = NULL;
    if( transcode )
    {
        const char *extension = !strcasecmp( sys->device.codec, "aac" )
                              ? "m4a" : sys->device.codec;
        if( asprintf( &hint, "%s.%s", entry->psz_path, extension ) < 0 )
            hint = NULL;
    }
    GError *error = NULL;
    gchar *allocated = itdb_cp_get_dest_filename( track, NULL,
                                hint ? hint : entry->psz_path, &error );
    free( hint );
    gchar *destination = ipod_short_destination( allocated, entry->psz_path,
                                                  NULL, 0 );
    g_free( allocated );
    if( destination == NULL )
    {
        msg_Err( sd, "cannot allocate an iPod destination: %s",
                 error ? error->message : "unknown error" );
        if( error ) g_error_free( error );
        ipod_remove_track_completely( sys->ipod_database, track );
        transfer_update( sys, transfer, SD_TRANSFER_FAILED, 0 );
        return VLC_EGENERIC;
    }
    transfer_set_destination( sys, transfer, destination );
    transfer_update( sys, transfer, transcode ? SD_TRANSFER_TRANSCODING
                                               : SD_TRANSFER_COPYING, 0 );
    int result = transcode
        ? transcode_file( VLC_OBJECT( sd ), entry->psz_path, destination,
                          &sys->device, entry, sys, transfer )
        : copy_file_tracked( sys, transfer, entry->psz_path, destination );
    if( result == VLC_SUCCESS
     && itdb_cp_finalize( track, NULL, destination, &error ) == NULL )
        result = VLC_EGENERIC;
    if( result == VLC_SUCCESS && !ipod_stage_added_path( sys, destination ) )
        result = VLC_ENOMEM;
    if( result == VLC_SUCCESS ) ipod_publish_added_track( sd, track );
    if( result != VLC_SUCCESS )
    {
        vlc_unlink( destination );
        ipod_remove_track_completely( sys->ipod_database, track );
        if( error )
        {
            msg_Err( sd, "cannot finalize an iPod track: %s", error->message );
            g_error_free( error );
        }
    }
    bool cancelled = transfer_cancelled( sys, transfer );
    transfer_update( sys, transfer,
                     result == VLC_SUCCESS ? SD_TRANSFER_COMPLETED
                     : cancelled ? SD_TRANSFER_CANCELLED : SD_TRANSFER_FAILED,
                     result == VLC_SUCCESS ? 100 : 0 );
    g_free( destination );
    return result;
}

typedef struct
{
    pvlc_media_entry_t *entry;
    uint64_t transfer;
    Itdb_Track *track;
    char *destination;
    char *staging;
    unsigned char *memory;
    size_t memory_size;
    int result;
    bool ready;
} ipod_transcode_job_t;

typedef struct
{
    services_discovery_t *sd;
    ipod_transcode_job_t *jobs;
    size_t count;
    size_t next;
    size_t outstanding;
    size_t parallelism;
    vlc_mutex_t lock;
    vlc_cond_t wait;
} ipod_transcode_workers_t;

static void *run_ipod_transcodes( void *opaque )
{
    ipod_transcode_workers_t *workers = opaque;
    for( ;; )
    {
        vlc_mutex_lock( &workers->lock );
        /* A completed output stays in RAM until the single iPod writer has
         * consumed it.  Bound the sum of running and cached jobs to the
         * machine's logical CPU count, but release one slot immediately
         * after each copy: this is a sliding window, not a sequence of
         * fixed-size barriers. */
        while( workers->next < workers->count
            && workers->outstanding >= workers->parallelism )
            vlc_cond_wait( &workers->wait, &workers->lock );
        if( workers->next >= workers->count )
        {
            vlc_mutex_unlock( &workers->lock );
            break;
        }
        size_t index = workers->next++;
        workers->outstanding++;
        vlc_mutex_unlock( &workers->lock );
        ipod_transcode_job_t *job = &workers->jobs[index];
        if( !transfer_cancelled( workers->sd->p_sys, job->transfer ) )
        {
            transfer_update( workers->sd->p_sys, job->transfer,
                             SD_TRANSFER_TRANSCODING, 0 );
            job->result = transcode_file( VLC_OBJECT( workers->sd ),
                job->entry->psz_path, job->staging,
                &workers->sd->p_sys->device, job->entry,
                workers->sd->p_sys, job->transfer );
            if( job->result == VLC_SUCCESS )
            {
                job->result = read_staging_file( job->staging, &job->memory,
                                                  &job->memory_size );
                if( job->result == VLC_SUCCESS ) vlc_unlink( job->staging );
            }
        }
        vlc_mutex_lock( &workers->lock );
        job->ready = true;
        vlc_cond_signal( &workers->wait );
        vlc_mutex_unlock( &workers->lock );
    }
    return NULL;
}

static bool ipod_prepare_transcode( services_discovery_t *sd,
                                    pvlc_media_entry_t *entry,
                                    uint64_t transfer,
                                    ipod_transcode_job_t *previous,
                                    size_t previous_count,
                                    ipod_transcode_job_t *job )
{
    services_discovery_sys_t *sys = sd->p_sys;
    memset( job, 0, sizeof( *job ) );
    job->entry = entry; job->transfer = transfer; job->result = VLC_EGENERIC;
    job->track = ipod_track_from_entry( sys->ipod_database, entry,
                                       sys->device.album_artist_as_composer );
    if( job->track == NULL ) return false;
    const char *extension = !strcasecmp( sys->device.codec, "aac" )
                          ? "m4a" : sys->device.codec;
    char *hint = NULL;
    if( asprintf( &hint, "%s.%s", entry->psz_path, extension ) < 0 )
        hint = NULL;
    GError *error = NULL;
    gchar *allocated = itdb_cp_get_dest_filename( job->track, NULL,
                                      hint ? hint : entry->psz_path, &error );
    free( hint );
    const char **reserved = previous_count
                          ? calloc( previous_count, sizeof( *reserved ) ) : NULL;
    for( size_t i = 0; reserved && i < previous_count; ++i )
        reserved[i] = previous[i].destination;
    job->destination = previous_count && reserved == NULL ? NULL
        : ipod_short_destination( allocated, entry->psz_path,
                                  reserved, previous_count );
    free( reserved );
    g_free( allocated );
    if( error ) g_error_free( error );
    job->staging = transcode_staging_file();
    if( job->destination && job->staging )
    {
        transfer_set_destination( sys, transfer, job->destination );
        return true;
    }
    g_free( job->destination ); free( job->staging );
    job->destination = job->staging = NULL;
    ipod_remove_track_completely( sys->ipod_database, job->track );
    job->track = NULL;
    transfer_update( sys, transfer, SD_TRANSFER_FAILED, 0 );
    return false;
}

static void ipod_finish_transcode( services_discovery_t *sd,
                                   ipod_transcode_job_t *job )
{
    services_discovery_sys_t *sys = sd->p_sys;
    bool cancelled = transfer_cancelled( sys, job->transfer );
    if( job->result == VLC_SUCCESS && !cancelled )
    {
        transfer_update( sys, job->transfer, SD_TRANSFER_COPYING, 0 );
        job->result = job->memory
            ? copy_memory_tracked( sys, job->transfer, job->memory,
                                   job->memory_size, job->destination )
            : copy_file_tracked( sys, job->transfer, job->staging,
                                 job->destination );
    }
    GError *error = NULL;
    if( job->result == VLC_SUCCESS )
    {
        Itdb_Track *finalized = itdb_cp_finalize( job->track, NULL,
                                                  job->destination, &error );
        if( finalized == NULL ) job->result = VLC_EGENERIC;
    }
    if( job->result == VLC_SUCCESS
     && !ipod_stage_added_path( sys, job->destination ) )
        job->result = VLC_ENOMEM;
    if( job->result == VLC_SUCCESS )
        ipod_publish_added_track( sd, job->track );
    if( job->result != VLC_SUCCESS )
    {
        vlc_unlink( job->destination );
        ipod_remove_track_completely( sys->ipod_database, job->track );
        if( error )
            msg_Err( sd, "cannot finalize an iPod track: %s", error->message );
    }
    if( error ) g_error_free( error );
    cancelled = transfer_cancelled( sys, job->transfer );
    transfer_update( sys, job->transfer,
                     job->result == VLC_SUCCESS ? SD_TRANSFER_COMPLETED
                     : cancelled ? SD_TRANSFER_CANCELLED : SD_TRANSFER_FAILED,
                     job->result == VLC_SUCCESS ? 100 : 0 );
    if( job->staging ) vlc_unlink( job->staging );
    free( job->memory ); free( job->staging ); g_free( job->destination );
}

static void ipod_stage_transcode_pipeline( services_discovery_t *sd,
                                           pvlc_media_entry_t *entries,
                                           uint64_t *transfers, size_t count )
{
    ipod_transcode_job_t *jobs = calloc( count, sizeof( *jobs ) );
    if( jobs == NULL ) return;
    size_t prepared = 0;
    for( size_t i = 0; i < count; ++i )
        if( ipod_prepare_transcode( sd, &entries[i], transfers[i], jobs,
                                    prepared,
                                    &jobs[prepared] ) ) prepared++;
    if( prepared == 0 ) { free( jobs ); return; }

    unsigned task_limit = portable_transcode_task_limit();
    size_t worker_count = prepared < task_limit ? prepared : task_limit;
    ipod_transcode_workers_t workers = {
        .sd = sd, .jobs = jobs, .count = prepared,
        .parallelism = worker_count,
    };
    vlc_mutex_init( &workers.lock );
    vlc_cond_init( &workers.wait );
    vlc_thread_t *threads = calloc( worker_count, sizeof( *threads ) );
    size_t started = 0;
    for( ; threads && started < worker_count; ++started )
        if( vlc_clone( &threads[started], run_ipod_transcodes, &workers,
                       VLC_THREAD_PRIORITY_LOW ) ) break;
    sd->p_sys->transcode_parallelism = started ? (unsigned)started : 1;
    dropped_threads_cleanup_t cleanup = { threads, started };
    vlc_cleanup_push( cleanup_dropped_threads, &cleanup );

    if( started == 0 )
    {
        /* Thread creation can fail on a very constrained legacy system. */
        for( size_t i = 0; i < prepared; ++i )
        {
            transfer_update( sd->p_sys, jobs[i].transfer,
                             SD_TRANSFER_TRANSCODING, 0 );
            jobs[i].result = transcode_file( VLC_OBJECT( sd ),
                jobs[i].entry->psz_path, jobs[i].staging, &sd->p_sys->device,
                jobs[i].entry, sd->p_sys, jobs[i].transfer );
            if( jobs[i].result == VLC_SUCCESS )
                jobs[i].result = read_staging_file( jobs[i].staging,
                                     &jobs[i].memory, &jobs[i].memory_size );
            ipod_finish_transcode( sd, &jobs[i] );
        }
    }
    else
    {
        size_t consumed = 0;
        while( consumed < prepared )
        {
            vlc_mutex_lock( &workers.lock );
            size_t ready = prepared;
            while( ready == prepared )
            {
                for( size_t i = 0; i < prepared; ++i )
                    if( jobs[i].ready ) { ready = i; break; }
                if( ready == prepared )
                    vlc_cond_wait( &workers.wait, &workers.lock );
            }
            jobs[ready].ready = false;
            vlc_mutex_unlock( &workers.lock );

            /* Only this lane writes to the slow iPod filesystem.  Encoder
             * workers continue filling the remaining slots concurrently. */
            ipod_finish_transcode( sd, &jobs[ready] );
            consumed++;
            vlc_mutex_lock( &workers.lock );
            workers.outstanding--;
            vlc_cond_broadcast( &workers.wait );
            vlc_mutex_unlock( &workers.lock );
        }
    }
    for( size_t i = 0; i < started; ++i ) vlc_join( threads[i], NULL );
    cleanup.count = 0;
    free( threads );
    vlc_cleanup_pop();
    sd->p_sys->transcode_parallelism = 1;
    vlc_cond_destroy( &workers.wait );
    vlc_mutex_destroy( &workers.lock );
    free( jobs );
}

static bool ipod_entry_needs_transcode( const device_config_t *device,
                                        const pvlc_media_entry_t *entry )
{
    return device->transcode && entry->i_type == PVLC_MEDIA_AUDIO
        && !has_extension( entry->psz_path, device->codec )
        && !( !strcasecmp( device->codec, "aac" )
           && has_extension( entry->psz_path, "m4a" ) );
}

static void ipod_stage_dropped_paths( services_discovery_t *sd, char **paths,
                                      uint64_t *transfers, size_t count )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( sys->ipod_database == NULL ) return;
    pvlc_media_catalog_t catalog; pvlc_catalog_init( &catalog );
    uint64_t *entry_transfers = NULL;
    for( size_t i = 0; i < count; ++i )
    {
        struct stat st;
        if( vlc_stat( paths[i], &st ) != 0 ) continue;
        if( S_ISREG( st.st_mode ) )
        {
            pvlc_media_entry_t entry;
            if( pvlc_scan_file( VLC_OBJECT( sd ), paths[i], paths[i], &entry )
                == VLC_SUCCESS )
            {
                uint64_t *grown = realloc( entry_transfers,
                                  (catalog.i_count + 1) * sizeof( *grown ) );
                if( grown ) entry_transfers = grown;
                if( grown && pvlc_catalog_append( &catalog, &entry )
                          == VLC_SUCCESS )
                {
                    grown[catalog.i_count - 1] = transfers[i];
                }
                pvlc_media_entry_clear( &entry );
            }
            continue;
        }
        if( !S_ISDIR( st.st_mode ) ) continue;
        pvlc_media_catalog_t folder; pvlc_catalog_init( &folder );
        if( pvlc_scan_folder( VLC_OBJECT( sd ), paths[i], &folder )
            == VLC_SUCCESS )
            for( size_t j = 0; j < folder.i_count; ++j )
            {
                uint64_t transfer = j == 0 ? transfers[i]
                    : transfer_begin( sys, folder.p_entries[j].psz_path, "",
                                      SD_TRANSFER_QUEUED );
                size_t old_count = catalog.i_count;
                uint64_t *grown = realloc( entry_transfers,
                                    (old_count + 1) * sizeof( *grown ) );
                if( grown ) entry_transfers = grown;
                if( grown && pvlc_catalog_append( &catalog,
                                  &folder.p_entries[j] ) == VLC_SUCCESS )
                {
                    grown[old_count] = transfer;
                }
            }
        pvlc_catalog_clear( &folder );
    }

    for( size_t i = 0; i < catalog.i_count; )
    {
        if( !ipod_entry_needs_transcode( &sys->device,
                                         &catalog.p_entries[i] ) )
        { ipod_stage_entry( sd, &catalog.p_entries[i], entry_transfers[i] );
          ++i; continue; }
        size_t first = i;
        while( i < catalog.i_count
            && ipod_entry_needs_transcode( &sys->device,
                                            &catalog.p_entries[i] ) )
            ++i;
        ipod_stage_transcode_pipeline( sd, &catalog.p_entries[first],
                                       &entry_transfers[first], i - first );
    }
    free( entry_transfers );
    pvlc_catalog_clear( &catalog );
}
#endif

static bool sync_dropped_paths( services_discovery_t *sd, char **paths,
                                uint64_t *transfers, size_t count )
{
#ifdef HAVE_LIBGPOD
    if( !strcasecmp( sd->p_sys->device.kind, "ipod" ) )
    {
        ipod_stage_dropped_paths( sd, paths, transfers, count );
        /* Publish one new compact-index generation for the whole coalesced
         * batch, then rebind the stable virtual rows in place.  Never rebuild
         * once per copied medium and never replace the service root. */
        if( sd->p_sys->ipod_session_addition_count > 0 )
        {
            if( ipod_build_local_index( sd ) == VLC_SUCCESS )
                ipod_rebind_music_views( sd );
            else
                msg_Err( sd, "cannot refresh iPod views after transfers" );
        }
        return false;
    }
#endif
    if( pvlc_mkdir_parents( sd->p_sys->device.path ) != VLC_SUCCESS )
        return false;
    if( sync_dropped_regular_files( sd, paths, transfers, count ) )
        return false;
    sync_state_t state;
    if( state_load( &sd->p_sys->device, &state ) != VLC_SUCCESS )
        memset( &state, 0, sizeof( state ) );
    for( size_t i = 0; i < count; ++i )
    {
        if( path_is_inside( sd->p_sys->device.path, paths[i] ) ) continue;
        struct stat st;
        if( vlc_stat( paths[i], &st ) != 0 ) continue;
        if( S_ISDIR( st.st_mode ) )
        {
            pvlc_media_catalog_t catalog; pvlc_catalog_init( &catalog );
            if( pvlc_scan_folder( VLC_OBJECT( sd ), paths[i], &catalog )
                == VLC_SUCCESS )
                for( size_t j = 0; j < catalog.i_count; ++j )
                {
                    uint64_t id = j == 0 ? transfers[i]
                        : transfer_begin( sd->p_sys,
                                          catalog.p_entries[j].psz_path, "",
                                          SD_TRANSFER_QUEUED );
                    sync_dropped_entry( sd, &catalog.p_entries[j], &state, id );
                }
            pvlc_catalog_clear( &catalog );
        }
        else if( S_ISREG( st.st_mode ) )
        {
            pvlc_media_entry_t entry;
            if( pvlc_scan_file( VLC_OBJECT( sd ), paths[i], paths[i], &entry )
                == VLC_SUCCESS )
            {
                sync_dropped_entry( sd, &entry, &state, transfers[i] );
                pvlc_media_entry_clear( &entry );
            }
        }
    }
    state_sort( &state );
    state_save( &sd->p_sys->device, &state, 0 );
    state_clear( &state );
    return true;
}

#ifdef HAVE_LIBGPOD
static uint64_t ipod_cache_key( const char *path )
{
    uint64_t hash = UINT64_C( 1469598103934665603 );
    for( const unsigned char *p = (const unsigned char *)path; *p; ++p )
    {
        hash ^= *p;
        hash *= UINT64_C( 1099511628211 );
    }
    return hash;
}

static void ipod_remove_old_snapshots( const char *directory,
                                       const char *current,
                                       uint64_t key )
{
    DIR *dir = vlc_opendir( directory );
    if( dir == NULL ) return;
    char prefix[24];
    snprintf( prefix, sizeof( prefix ), "%016" PRIx64 "-", key );
    const char *name;
    while( (name = vlc_readdir( dir )) != NULL )
    {
        if( strncmp( name, prefix, strlen( prefix ) ) ) continue;
        char *path = pvlc_path_join( directory, name );
        if( path && strcmp( path, current ) ) vlc_unlink( path );
        free( path );
    }
    closedir( dir );
}

/* libgpod's mount-point parser performs its work against the iPod itself.
 * Even after avoiding per-track probes, parsing a 14 MB database through a
 * slow FAT USB device takes seconds and creates avoidable random I/O.  Keep a
 * versioned local snapshot, fault the complete snapshot into RAM, then let
 * libgpod parse only that warm local copy.  On an unchanged iPod the sole
 * device access is the stat() used to validate the snapshot. */
static Itdb_iTunesDB *ipod_parse_cached( services_discovery_t *sd,
                                        GError **error )
{
    services_discovery_sys_t *sys = sd->p_sys;
    vlc_tick_t started = mdate();
    char *source = NULL;
    if( asprintf( &source, "%s/iPod_Control/iTunes/iTunesDB",
                  sys->device.path ) < 0 )
        source = NULL;
    struct stat source_stat;
    if( source == NULL || vlc_stat( source, &source_stat ) != 0 )
    {
        free( source );
        source = itdb_get_itunesdb_path( sys->device.path );
    }
    if( source == NULL || vlc_stat( source, &source_stat ) != 0 )
    {
        g_set_error( error, ITDB_FILE_ERROR, ITDB_FILE_ERROR_NOTFOUND,
                     "iTunesDB not found on %s", sys->device.path );
        g_free( source );
        return NULL;
    }

    char *base = config_GetUserDir( VLC_CACHE_DIR );
    char *directory = base ? pvlc_path_join( base, "powervlc/ipod" ) : NULL;
    free( base );
    char *snapshot = NULL;
    uint64_t key = ipod_cache_key( sys->device.path );
    if( directory && pvlc_mkdir_parents( directory ) == VLC_SUCCESS )
        asprintf( &snapshot, "%s/%016" PRIx64 "-%" PRIu64 "-%" PRId64
                  ".itdb", directory, key, (uint64_t)source_stat.st_size,
                  (int64_t)source_stat.st_mtime );

    gchar *contents = NULL;
    gsize length = 0;
    bool ready = snapshot && g_file_get_contents( snapshot, &contents,
                                                   &length, NULL )
              && length == (gsize)source_stat.st_size;
    if( !ready )
    {
        g_free( contents ); contents = NULL; length = 0;
        if( !g_file_get_contents( source, &contents, &length, error ) )
        {
            free( snapshot ); free( directory ); g_free( source );
            return NULL;
        }
        if( snapshot )
        {
            GError *cache_error = NULL;
            if( !g_file_set_contents( snapshot, contents, length, &cache_error ) )
            {
                msg_Warn( sd, "cannot cache iTunesDB locally: %s",
                          cache_error ? cache_error->message : "unknown error" );
                if( cache_error ) g_error_free( cache_error );
                free( snapshot ); snapshot = NULL;
            }
            else ipod_remove_old_snapshots( directory, snapshot, key );
        }
    }

    /* contents intentionally remains alive while libgpod parses the local
     * file: its pages have just been read/written and are resident in RAM. */
    Itdb_iTunesDB *database = snapshot
                           ? itdb_parse_file( snapshot, error ) : NULL;
    if( database == NULL && snapshot == NULL )
        database = itdb_parse_file( source, error );
    g_free( contents );
    if( database )
    {
        itdb_set_mountpoint( database, sys->device.path );
        g_free( database->filename );
        database->filename = g_strdup( source );
    }
    msg_Dbg( sd, "iTunesDB %s snapshot loaded and parsed in %.3f s",
             ready ? "cached" : "fresh",
             (double)(mdate() - started) / CLOCK_FREQ );
    free( snapshot ); free( directory ); g_free( source );
    return database;
}

static gchar *ipod_track_path( Itdb_Track *track )
{
    /* itdb_filename_on_ipod() calls g_file_test() for every track and then
     * performs a case-insensitive directory walk on failure.  On a large,
     * nearly-full FAT iPod those thousands of synchronous metadata requests
     * can take tens of minutes.  iTunesDB already contains the canonical
     * iPod-relative path, so construct the path without touching the disk.
     * An unavailable file will still fail normally when the user plays it. */
    gchar *relative = track && track->ipod_path
                    ? g_strdup( track->ipod_path ) : NULL;
    if( relative ) itdb_filename_ipod2fs( relative );
    const gchar *mountpoint = track && track->itdb
                            ? itdb_get_mountpoint( track->itdb ) : NULL;
    gchar *filename = relative && mountpoint
                    ? g_build_filename( mountpoint, relative, NULL ) : NULL;
    g_free( relative );
    return filename;
}

static bool ipod_track_is_staged_for_deletion( services_discovery_sys_t *sys,
                                               Itdb_Track *track )
{
    gchar *path = ipod_track_path( track );
    bool found = false;
    for( size_t i = 0; path && i < sys->pending_ipod_deletion_count; ++i )
        if( !strcmp( path, sys->pending_ipod_deletions[i] ) )
        { found = true; break; }
    g_free( path );
    return found;
}

static input_item_t *ipod_track_item( Itdb_Track *track )
{
    gchar *filename = ipod_track_path( track );
    char *uri = filename ? vlc_path2uri( filename, NULL ) : NULL;
    input_item_t *item = uri
        ? input_item_NewFile( uri, track->title ? track->title : filename,
                              -1, ITEM_LOCAL ) : NULL;
    if( item != NULL )
    {
        char option[64];
        snprintf( option, sizeof( option ), IPOD_TRACK_ID_OPTION "%u",
                  track->id );
        input_item_AddOption( item, option, VLC_INPUT_OPTION_UNIQUE );
        if( track->artist ) input_item_SetMeta( item, vlc_meta_Artist,
                                                track->artist );
        if( track->album ) input_item_SetMeta( item, vlc_meta_Album,
                                               track->album );
        /* iTunesDB is the metadata authority for this item.  Do not enqueue
         * another per-file metadata probe merely because an optional tag is
         * empty: that would reintroduce thousands of accesses to the iPod. */
        input_item_SetPreparsed( item, true );
    }
    free( uri ); g_free( filename );
    return item;
}

/* Keep the current tree stable while transfers are running. Rebuilding the
 * compact index after every completed track would replace every lazy node
 * and collapse the user's open branches. Instead, expose successful copies
 * immediately in a small session node. The next normal device refresh builds
 * all virtual views from the authoritative in-memory iTunesDB. */
static void ipod_publish_added_track( services_discovery_t *sd,
                                      Itdb_Track *track )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( track == NULL || sys->ipod_music_root == NULL ) return;
    if( sys->ipod_session_additions == NULL )
    {
        char *uri = NULL;
        uint64_t key = ipod_cache_key( sys->device.path );
        if( asprintf( &uri, "powervlc-ipod-session://%016" PRIx64, key ) < 0 )
            uri = NULL;
        input_item_t *node = uri ? input_item_NewExt( uri,
            _( "Added this session" ), -1, ITEM_TYPE_NODE, ITEM_LOCAL ) : NULL;
        free( uri );
        if( node == NULL ) return;
        input_item_SetPreparsed( node, true );
        services_discovery_AddSubItem( sd, sys->ipod_music_root, node );
        /* Keep the creator reference for subsequent AddSubItem calls. The
         * core owns its separate reference until the visible root is gone. */
        sys->ipod_session_additions = node;
    }

    input_item_t *item = ipod_track_item( track );
    if( item == NULL ) return;
    services_discovery_AddSubItem( sd, sys->ipod_session_additions, item );
    input_item_Release( item );
    sys->ipod_session_addition_count++;
    sys->ipod_music_count++;

    char *label = NULL;
    if( asprintf( &label, "%s (%zu)", _( "Added this session" ),
                  sys->ipod_session_addition_count ) >= 0 )
    {
        input_item_SetName( sys->ipod_session_additions, label );
        free( label );
    }
    label = NULL;
    if( asprintf( &label, "%s (%zu)", _( "Music" ),
                  sys->ipod_music_count ) >= 0 )
    {
        input_item_SetName( sys->ipod_music_root, label );
        free( label );
    }
}

static void ipod_set_counted_name( input_item_t *item, size_t count )
{
    if( item == NULL ) return;
    char *name = input_item_GetName( item );
    if( name == NULL ) return;
    size_t base_length = strlen( name );
    char *suffix = strrchr( name, '(' );
    if( suffix && suffix > name && suffix[-1] == ' ' )
    {
        char *end = NULL;
        strtoull( suffix + 1, &end, 10 );
        if( end && !strcmp( end, ")" ) ) base_length = (size_t)(suffix - name - 1);
    }
    char *label = NULL;
    if( asprintf( &label, "%.*s (%zu)", (int)base_length, name, count ) >= 0 )
    { input_item_SetName( item, label ); free( label ); }
    free( name );
}

static void ipod_update_visible_counts( services_discovery_t *sd,
                                        playlist_t *core )
{
    services_discovery_sys_t *sys = sd->p_sys;
    GHashTable *deleted = g_hash_table_new( g_str_hash, g_str_equal );
    if( deleted == NULL ) return;
    for( size_t i = 0; i < sys->pending_ipod_deletion_count; ++i )
        g_hash_table_add( deleted, sys->pending_ipod_deletions[i] );
    size_t music = 0, podcasts = 0;
    for( GList *entry = sys->ipod_database->tracks; entry; entry = entry->next )
    {
        Itdb_Track *track = entry->data;
        gchar *path = ipod_track_path( track );
        bool removed = path && g_hash_table_contains( deleted, path );
        g_free( path );
        if( removed ) continue;
        if( track->mediatype & ITDB_MEDIATYPE_PODCAST ) podcasts++;
        else music++;
    }
    g_hash_table_destroy( deleted );
    sys->ipod_music_count = music;
    sys->ipod_podcast_count = podcasts;
    ipod_set_counted_name( sys->ipod_music_root, music );
    ipod_set_counted_name( sys->ipod_podcast_root, podcasts );

    playlist_item_t *music_root = sys->ipod_music_root
        ? playlist_ItemGetByInput( core, sys->ipod_music_root ) : NULL;
    if( music_root && music_root->i_children >= 0 )
        for( int i = 0; i < music_root->i_children; ++i )
        {
            input_item_t *input = music_root->pp_children[i]->p_input;
            if( input && input_item_IsPowerVLCLazyIndex( input ) )
                ipod_set_counted_name( input, music );
        }
}

/* The device view uses the same random-access container as the media
 * library.  iTunesDB is parsed once from its local snapshot, then each UI
 * expansion reads a few bytes from this local index instead of walking the
 * iPod or materialising all tracks and playlist occurrences. */
#define PVLC_IPOD_INDEX_NODE UINT32_C(0x4e4f4445)
#define PVLC_IPOD_INDEX_MEDIA UINT32_C(0x4d454449)
#define PVLC_IPOD_CHILD_NODE 1
#define PVLC_IPOD_CHILD_MEDIA 2
#define PVLC_IPOD_NO_VALUE UINT32_MAX
#define PVLC_IPOD_FLAG_DEVICE_STRUCTURE UINT32_C(0x10)

typedef struct
{
    uint32_t type;
    uint64_t offset;
    const char *name;
    uint32_t flags;
} ipod_index_child_t;

static int ipod_index_tell( FILE *file, uint64_t *offset )
{
    long position = ftell( file );
    if( position < 0 ) return VLC_EGENERIC;
    *offset = (uint64_t)position;
    return VLC_SUCCESS;
}

static int ipod_index_write_node( FILE *file,
                                  const ipod_index_child_t *children,
                                  size_t count, uint64_t *offset )
{
    if( count > UINT32_MAX || ipod_index_tell( file, offset ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    int ret = pvlc_binary_write_u32( file, PVLC_IPOD_INDEX_NODE );
    if( ret == VLC_SUCCESS )
        ret = pvlc_binary_write_u32( file, (uint32_t)count );
    for( size_t i = 0; i < count && ret == VLC_SUCCESS; ++i )
    {
        ret = pvlc_binary_write_u32( file, children[i].type );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file,
                                                       children[i].flags );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file,
                                                       PVLC_IPOD_NO_VALUE );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file, 0 );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file,
                                                       children[i].offset );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                                                  children[i].name ?: "" );
    }
    return ret;
}

static int ipod_index_write_media( FILE *file, Itdb_Track *track,
                                   uint64_t *offset )
{
    gchar *filename = ipod_track_path( track );
    char *uri = filename ? vlc_path2uri( filename, NULL ) : NULL;
    if( uri == NULL ) { g_free( filename ); return VLC_EGENERIC; }
    char track_number[24] = "";
    if( track->track_nr ) snprintf( track_number, sizeof( track_number ), "%u",
                                   track->track_nr );
    int ret = ipod_index_tell( file, offset );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file,
                                                    PVLC_IPOD_INDEX_MEDIA );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file, uri );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                                  track->title ?: filename ?: "" );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                                                    track->artist ?: "" );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                                                     track->album ?: "" );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                                                            track_number );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                                               track->albumartist ?: "" );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file,
                                               track->rating / 20 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file,
                              (uint64_t)VLC_TICK_FROM_MS( track->tracklen ) );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file, track->id );
    free( uri ); g_free( filename );
    return ret;
}

static unsigned ipod_title_bucket( const char *title )
{
    const unsigned char *p = (const unsigned char *)(title ?: "");
    while( *p && !isalnum( *p ) ) ++p;
    int c = toupper( *p );
    if( c >= 'A' && c <= 'Z' ) return (unsigned)(c - 'A');
    if( c >= '0' && c <= '9' ) return 26 + (unsigned)(c - '0');
    return 36;
}

static const char *ipod_bucket_name( unsigned bucket, char text[2] )
{
    text[0] = bucket < 26 ? (char)('A' + bucket)
            : bucket < 36 ? (char)('0' + bucket - 26) : '#';
    text[1] = '\0';
    return text;
}

static int ipod_index_write_bucket_root( FILE *file, GPtrArray *buckets[37],
                                         GHashTable *offsets,
                                         uint64_t *root_offset )
{
    ipod_index_child_t roots[37];
    char labels[37][2];
    size_t root_count = 0;
    int ret = VLC_SUCCESS;
    for( unsigned b = 0; b < 37 && ret == VLC_SUCCESS; ++b )
    {
        if( buckets[b] == NULL || buckets[b]->len == 0 ) continue;
        ipod_index_child_t *children = vlc_alloc( buckets[b]->len,
                                                  sizeof( *children ) );
        if( children == NULL ) { ret = VLC_ENOMEM; break; }
        size_t count = 0;
        for( guint i = 0; i < buckets[b]->len; ++i )
        {
            Itdb_Track *track = g_ptr_array_index( buckets[b], i );
            uint64_t *offset = g_hash_table_lookup( offsets, track );
            if( offset ) children[count++] = (ipod_index_child_t) {
                PVLC_IPOD_CHILD_MEDIA, *offset, ""
            };
        }
        uint64_t node_offset = 0;
        ret = ipod_index_write_node( file, children, count, &node_offset );
        free( children );
        if( ret == VLC_SUCCESS )
        {
            size_t index = root_count++;
            roots[index] = (ipod_index_child_t) {
                PVLC_IPOD_CHILD_NODE, node_offset,
                ipod_bucket_name( b, labels[index] )
            };
        }
    }
    if( ret == VLC_SUCCESS )
        ret = ipod_index_write_node( file, roots, root_count, root_offset );
    return ret;
}

typedef enum
{
    IPOD_VIEW_ALBUM_ARTIST,
    IPOD_VIEW_ARTIST,
    IPOD_VIEW_ALBUM,
    IPOD_VIEW_GENRE,
    IPOD_VIEW_COMPOSER,
    IPOD_VIEW_YEAR,
} ipod_grouped_view_t;

static const char *ipod_view_value( Itdb_Track *track,
                                    ipod_grouped_view_t view,
                                    char year[16] )
{
    const char *value = NULL;
    switch( view )
    {
        case IPOD_VIEW_ALBUM_ARTIST:
            value = track->albumartist && *track->albumartist
                  ? track->albumartist : track->artist; break;
        case IPOD_VIEW_ARTIST: value = track->artist; break;
        case IPOD_VIEW_ALBUM: value = track->album; break;
        case IPOD_VIEW_GENRE: value = track->genre; break;
        case IPOD_VIEW_COMPOSER: value = track->composer; break;
        case IPOD_VIEW_YEAR:
            if( track->year > 0 )
            {
                int normalized = track->year;
                while( normalized > 9999 ) normalized /= 10;
                snprintf( year, 16, "%d", normalized ); value = year;
            }
            break;
    }
    return value && *value ? value : _( "Unknown" );
}

static gint ipod_group_name_compare( gconstpointer a, gconstpointer b )
{
    return g_utf8_collate( a, b );
}

static gint ipod_year_name_compare( gconstpointer a, gconstpointer b )
{
    long left = strtol( a, NULL, 10 ), right = strtol( b, NULL, 10 );
    if( left != right ) return left < right ? 1 : -1;
    return g_utf8_collate( a, b );
}

static GHashTable *ipod_group_tracks( GPtrArray *tracks,
                                     ipod_grouped_view_t view )
{
    GHashTable *groups = g_hash_table_new_full( g_str_hash, g_str_equal,
                                                g_free,
                                                (GDestroyNotify)g_ptr_array_unref );
    if( groups == NULL ) return NULL;
    for( guint i = 0; i < tracks->len; ++i )
    {
        Itdb_Track *track = g_ptr_array_index( tracks, i ); char year[16] = "";
        const char *name = ipod_view_value( track, view, year );
        GPtrArray *members = g_hash_table_lookup( groups, name );
        if( members == NULL )
        {
            members = g_ptr_array_new();
            if( members == NULL ) { g_hash_table_destroy( groups ); return NULL; }
            g_hash_table_insert( groups, g_strdup( name ), members );
        }
        g_ptr_array_add( members, track );
    }
    return groups;
}

static int ipod_index_write_track_node( FILE *file, GPtrArray *tracks,
                                        GHashTable *media_offsets,
                                        uint64_t *offset )
{
    ipod_index_child_t *children = vlc_alloc( tracks->len,
                                              sizeof( *children ) );
    if( tracks->len && children == NULL ) return VLC_ENOMEM;
    size_t count = 0;
    for( guint i = 0; i < tracks->len; ++i )
    {
        uint64_t *media = g_hash_table_lookup( media_offsets,
                                               g_ptr_array_index( tracks, i ) );
        if( media ) children[count++] = (ipod_index_child_t) {
            PVLC_IPOD_CHILD_MEDIA, *media, ""
        };
    }
    int ret = ipod_index_write_node( file, children, count, offset );
    free( children ); return ret;
}

static int ipod_index_write_album_children( FILE *file, GPtrArray *tracks,
                                            GHashTable *media_offsets,
                                            uint64_t *offset )
{
    GHashTable *albums = ipod_group_tracks( tracks, IPOD_VIEW_ALBUM );
    if( albums == NULL ) return VLC_ENOMEM;
    GList *names = g_hash_table_get_keys( albums );
    names = g_list_sort( names, ipod_group_name_compare );
    size_t count = g_list_length( names );
    ipod_index_child_t *children = vlc_alloc( count, sizeof( *children ) );
    if( count && children == NULL )
    { g_list_free( names ); g_hash_table_destroy( albums ); return VLC_ENOMEM; }
    size_t used = 0; int ret = VLC_SUCCESS;
    for( GList *entry = names; entry && ret == VLC_SUCCESS; entry = entry->next )
    {
        uint64_t node = 0; const char *name = entry->data;
        ret = ipod_index_write_track_node( file,
                        g_hash_table_lookup( albums, name ), media_offsets, &node );
        if( ret == VLC_SUCCESS ) children[used++] = (ipod_index_child_t) {
            PVLC_IPOD_CHILD_NODE, node, name
        };
    }
    if( ret == VLC_SUCCESS ) ret = ipod_index_write_node( file, children,
                                                           used, offset );
    free( children ); g_list_free( names ); g_hash_table_destroy( albums );
    return ret;
}

static int ipod_index_write_grouped_view( FILE *file, GPtrArray *tracks,
                                          GHashTable *media_offsets,
                                          ipod_grouped_view_t view,
                                          uint64_t *root_offset )
{
    GHashTable *groups = ipod_group_tracks( tracks, view );
    if( groups == NULL ) return VLC_ENOMEM;
    GList *names = g_hash_table_get_keys( groups );
    names = g_list_sort( names, view == IPOD_VIEW_YEAR
                              ? ipod_year_name_compare : ipod_group_name_compare );
    GHashTable *nodes = g_hash_table_new_full( g_str_hash, g_str_equal,
                                               NULL, g_free );
    int ret = nodes ? VLC_SUCCESS : VLC_ENOMEM;
    for( GList *entry = names; entry && ret == VLC_SUCCESS; entry = entry->next )
    {
        uint64_t *node = g_new( uint64_t, 1 ); const char *name = entry->data;
        if( node == NULL ) { ret = VLC_ENOMEM; break; }
        GPtrArray *members = g_hash_table_lookup( groups, name );
        ret = view == IPOD_VIEW_ALBUM
            ? ipod_index_write_track_node( file, members, media_offsets, node )
            : ipod_index_write_album_children( file, members, media_offsets, node );
        if( ret == VLC_SUCCESS ) g_hash_table_insert( nodes, (void *)name, node );
        else g_free( node );
    }
    if( ret == VLC_SUCCESS && view == IPOD_VIEW_YEAR )
    {
        size_t count = g_list_length( names ), used = 0;
        ipod_index_child_t *children = vlc_alloc( count, sizeof( *children ) );
        if( count && children == NULL ) ret = VLC_ENOMEM;
        for( GList *entry = names; entry && ret == VLC_SUCCESS;
             entry = entry->next )
        {
            uint64_t *node = g_hash_table_lookup( nodes, entry->data );
            if( node ) children[used++] = (ipod_index_child_t) {
                PVLC_IPOD_CHILD_NODE, *node, entry->data
            };
        }
        if( ret == VLC_SUCCESS ) ret = ipod_index_write_node( file, children,
                                                       used, root_offset );
        free( children );
    }
    else if( ret == VLC_SUCCESS )
    {
        GPtrArray *buckets[37] = { 0 };
        for( unsigned i = 0; i < 37; ++i ) buckets[i] = g_ptr_array_new();
        for( GList *entry = names; entry; entry = entry->next )
            g_ptr_array_add( buckets[ipod_title_bucket( entry->data )],
                             entry->data );
        ipod_index_child_t roots[37]; char labels[37][2]; size_t root_count = 0;
        for( unsigned bucket = 0; bucket < 37 && ret == VLC_SUCCESS; ++bucket )
        {
            size_t count = buckets[bucket]->len;
            if( count == 0 ) continue;
            ipod_index_child_t *children = vlc_alloc( count,
                                                       sizeof( *children ) );
            if( children == NULL ) { ret = VLC_ENOMEM; break; }
            size_t used = 0;
            for( guint i = 0; i < buckets[bucket]->len; ++i )
            {
                const char *name = g_ptr_array_index( buckets[bucket], i );
                uint64_t *node = g_hash_table_lookup( nodes, name );
                if( node ) children[used++] = (ipod_index_child_t) {
                    PVLC_IPOD_CHILD_NODE, *node, name
                };
            }
            uint64_t node = 0;
            ret = ipod_index_write_node( file, children, used, &node );
            free( children );
            if( ret == VLC_SUCCESS )
            {
                size_t index = root_count++;
                roots[index] = (ipod_index_child_t) {
                    PVLC_IPOD_CHILD_NODE, node,
                    ipod_bucket_name( bucket, labels[index] )
                };
            }
        }
        if( ret == VLC_SUCCESS ) ret = ipod_index_write_node( file, roots,
                                                    root_count, root_offset );
        for( unsigned i = 0; i < 37; ++i ) g_ptr_array_free( buckets[i], TRUE );
    }
    g_hash_table_destroy( nodes ); g_list_free( names );
    g_hash_table_destroy( groups ); return ret;
}

static int ipod_build_local_index( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    bool append = sys->ipod_index_path != NULL;
    char *base = config_GetUserDir( VLC_CACHE_DIR );
    char *directory = base ? pvlc_path_join( base, "powervlc/ipod" ) : NULL;
    free( base );
    char *path = NULL, *tmp = NULL;
    uint64_t key = ipod_cache_key( sys->device.path );
    if( append )
        path = strdup( sys->ipod_index_path );
    else if( directory && pvlc_mkdir_parents( directory ) == VLC_SUCCESS )
    {
        asprintf( &path, "%s/%016" PRIx64 ".pvli", directory, key );
        if( path ) asprintf( &tmp, "%s.tmp", path );
    }
    free( directory );
    /* Do not use stdio "ab" here.  On macOS its O_APPEND writes land at EOF
     * but ftell() may keep reporting a generation-relative position, which
     * makes every child descriptor point into the previous generation. */
    FILE *file = append && path ? vlc_fopen( path, "r+b" )
                                : tmp ? vlc_fopen( tmp, "wb" ) : NULL;
    if( append && file && fseek( file, 0, SEEK_END ) != 0 )
    { fclose( file ); file = NULL; }
    if( file == NULL ) { free( path ); free( tmp ); return VLC_EGENERIC; }
    static const unsigned char magic[8] = {
        /* Keep this in lockstep with the shared compact-index reader.  The
         * iPod writer already emits the complete v5 child descriptors and
         * media records; advertising the obsolete v3 version made every
         * lazy Music/Podcasts expansion reject the freshly-built cache. */
        'P', 'V', 'L', 'C', 'L', 'I', 5, 0
    };
    int ret = pvlc_binary_write( file, magic, sizeof( magic ) );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file, 0 );

    GHashTable *offsets = g_hash_table_new_full( g_direct_hash, g_direct_equal,
                                                 NULL, g_free );
    GPtrArray *music[37] = { 0 }, *podcasts[37] = { 0 };
    GPtrArray *all_music = g_ptr_array_new();
    for( unsigned i = 0; i < 37; ++i )
    {
        music[i] = g_ptr_array_new(); podcasts[i] = g_ptr_array_new();
    }
    for( GList *entry = sys->ipod_database->tracks;
         entry && ret == VLC_SUCCESS; entry = entry->next )
    {
        Itdb_Track *track = entry->data;
        if( ipod_track_is_staged_for_deletion( sys, track ) ) continue;
        uint64_t *offset = g_new( uint64_t, 1 );
        if( offset == NULL ) { ret = VLC_ENOMEM; break; }
        ret = ipod_index_write_media( file, track, offset );
        if( ret != VLC_SUCCESS ) { g_free( offset ); break; }
        g_hash_table_insert( offsets, track, offset );
        unsigned bucket = ipod_title_bucket( track->title );
        if( track->mediatype & ITDB_MEDIATYPE_PODCAST )
            g_ptr_array_add( podcasts[bucket], track );
        else
        {
            g_ptr_array_add( music[bucket], track );
            g_ptr_array_add( all_music, track );
        }
    }
    uint64_t track_offset = 0, podcast_offset = 0;
    if( ret == VLC_SUCCESS ) ret = ipod_index_write_bucket_root( file, music,
                                                   offsets, &track_offset );
    if( ret == VLC_SUCCESS ) ret = ipod_index_write_bucket_root( file, podcasts,
                                                offsets, &podcast_offset );
    static const struct { ipod_grouped_view_t view; const char *name; } views[] = {
        { IPOD_VIEW_ALBUM_ARTIST, N_( "Album Artists" ) },
        { IPOD_VIEW_ARTIST, N_( "Artists" ) },
        { IPOD_VIEW_ALBUM, N_( "Albums" ) },
        { IPOD_VIEW_GENRE, N_( "Genres" ) },
        { IPOD_VIEW_COMPOSER, N_( "Composers" ) },
        { IPOD_VIEW_YEAR, N_( "Years" ) },
    };
    ipod_index_child_t music_views[ARRAY_SIZE( views ) + 1];
    char *music_view_names[ARRAY_SIZE( views ) + 1] = { 0 };
    size_t music_view_count = 0;
    for( size_t i = 0; i < ARRAY_SIZE( views ) && ret == VLC_SUCCESS; ++i )
    {
        uint64_t offset = 0;
        ret = ipod_index_write_grouped_view( file, all_music, offsets,
                                              views[i].view, &offset );
        char *label = ret == VLC_SUCCESS ? g_strdup_printf( "%s (%u)",
                              _( views[i].name ), all_music->len ) : NULL;
        if( ret == VLC_SUCCESS && label == NULL ) ret = VLC_ENOMEM;
        if( ret == VLC_SUCCESS )
        {
            music_view_names[music_view_count] = label;
            music_views[music_view_count++] = (ipod_index_child_t) {
                PVLC_IPOD_CHILD_NODE, offset, label,
                PVLC_IPOD_FLAG_DEVICE_STRUCTURE
            };
        }
    }
    if( ret == VLC_SUCCESS )
    {
        char *label = g_strdup_printf( "%s (%u)", _( "Tracks" ),
                                       all_music->len );
        if( label == NULL ) ret = VLC_ENOMEM;
        else
        {
            music_view_names[music_view_count] = label;
            music_views[music_view_count++] = (ipod_index_child_t) {
                PVLC_IPOD_CHILD_NODE, track_offset, label,
                PVLC_IPOD_FLAG_DEVICE_STRUCTURE
            };
        }
    }
    uint64_t music_offset = 0;
    if( ret == VLC_SUCCESS ) ret = ipod_index_write_node( file, music_views,
                                               music_view_count, &music_offset );
    for( size_t i = 0; i < ARRAY_SIZE( music_view_names ); ++i )
        g_free( music_view_names[i] );
    GHashTable *playlist_offsets = g_hash_table_new_full( g_int64_hash,
                                     g_int64_equal, g_free, g_free );
    size_t playlist_count = 0;
    for( GList *entry = sys->ipod_database->playlists;
         entry && ret == VLC_SUCCESS; entry = entry->next )
    {
        Itdb_Playlist *playlist = entry->data;
        if( itdb_playlist_is_mpl( playlist )
         || itdb_playlist_is_podcasts( playlist ) ) continue;
        playlist_count++;
        size_t capacity = g_list_length( playlist->members );
        ipod_index_child_t *children = vlc_alloc( capacity,
                                                  sizeof( *children ) );
        if( capacity && children == NULL ) { ret = VLC_ENOMEM; break; }
        size_t count = 0;
        for( GList *member = playlist->members; member; member = member->next )
        {
            uint64_t *offset = g_hash_table_lookup( offsets, member->data );
            if( offset ) children[count++] = (ipod_index_child_t) {
                PVLC_IPOD_CHILD_MEDIA, *offset, ""
            };
        }
        uint64_t *id = g_new( uint64_t, 1 ), *node = g_new( uint64_t, 1 );
        if( id == NULL || node == NULL )
        { g_free( id ); g_free( node ); ret = VLC_ENOMEM; free( children ); break; }
        *id = playlist->id;
        ret = ipod_index_write_node( file, children, count, node );
        free( children );
        if( ret == VLC_SUCCESS ) g_hash_table_insert( playlist_offsets, id, node );
        else { g_free( id ); g_free( node ); }
    }
    size_t music_count = all_music->len, podcast_count = 0;
    for( unsigned i = 0; i < 37; ++i )
        podcast_count += podcasts[i]->len;
    for( unsigned i = 0; i < 37; ++i )
    { g_ptr_array_free( music[i], TRUE ); g_ptr_array_free( podcasts[i], TRUE ); }
    g_ptr_array_free( all_music, TRUE );
    g_hash_table_destroy( offsets );
    bool failed = ret != VLC_SUCCESS || fflush( file ) != 0 || ferror( file );
    if( fclose( file ) != 0 ) failed = true;
    if( !append && !failed ) failed = vlc_rename( tmp, path ) != 0;
    if( !append && failed ) vlc_unlink( tmp );
    free( tmp );
    if( failed )
    { free( path ); g_hash_table_destroy( playlist_offsets ); return VLC_EGENERIC; }
    free( sys->ipod_index_path );
    if( sys->ipod_playlist_offsets )
        g_hash_table_destroy( sys->ipod_playlist_offsets );
    sys->ipod_index_path = path;
    sys->ipod_playlist_offsets = playlist_offsets;
    sys->ipod_music_offset = music_offset;
    sys->ipod_podcast_offset = podcast_offset;
    sys->ipod_music_view_count = music_view_count;
    for( size_t i = 0; i < ARRAY_SIZE( sys->ipod_music_view_offsets ); ++i )
        sys->ipod_music_view_offsets[i] = i < music_view_count
                                       ? music_views[i].offset : 0;
    sys->ipod_music_count = music_count;
    sys->ipod_podcast_count = podcast_count;
    sys->ipod_playlist_count = playlist_count;
    /* This freshly generated index already excludes every staged deletion;
     * an overlay belonging to the previous generation is no longer needed. */
    if( !append )
    {
        char *overlay = NULL;
        if( asprintf( &overlay, "%s.deleted", sys->ipod_index_path ) >= 0 )
        { vlc_unlink( overlay ); free( overlay ); }
    }
    return VLC_SUCCESS;
}

/* Refresh the contents of the seven stable virtual Music views after a
 * transfer batch.  Their playlist/input objects are deliberately retained,
 * so the UI keeps the Music row, selection and disclosure state.  The local
 * compact index is append-only for the duration of the session: already
 * materialised descendants can safely finish reading their old offsets while
 * these roots are rebound to the latest generation. */
static void ipod_rebind_music_views( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    playlist_t *core = (playlist_t *)sd->obj.parent;
    input_item_t *requests[7] = { 0 };
    playlist_item_t *request_items[7] = { 0 };
    size_t request_count = 0, view = 0;
    char *base = vlc_path2uri( sys->ipod_index_path, NULL );
    if( base == NULL ) return;

    playlist_Lock( core );
    playlist_item_t *music = playlist_ItemGetByInput( core,
                                                       sys->ipod_music_root );
    if( music && sys->ipod_music_offset )
    {
        char *uri = NULL;
        if( asprintf( &uri, "%s#%" PRIu64, base,
                      sys->ipod_music_offset ) >= 0 )
        {
            input_item_SetURI( music->p_input, uri );
            free( uri );
            char option[64];
            snprintf( option, sizeof( option ), "%s%" PRIu64,
                      VLC_INPUT_OPTION_POWERVLC_INDEX_OFFSET_PREFIX,
                      sys->ipod_music_offset );
            input_item_AddOption( music->p_input, option, 0 );
            input_item_SetPreparsed( music->p_input, false );
        }
    }
    if( music && music->i_children >= 0 )
        for( int i = 0; i < music->i_children
                     && view < sys->ipod_music_view_count; ++i )
        {
            playlist_item_t *row = music->pp_children[i];
            input_item_t *input = row ? row->p_input : NULL;
            if( input == NULL || !input_item_IsPowerVLCDeviceStructure( input )
             || !input_item_IsPowerVLCLazyIndex( input ) )
                continue;
            uint64_t offset = sys->ipod_music_view_offsets[view++];
            char *uri = NULL;
            if( offset == 0
             || asprintf( &uri, "%s#%" PRIu64, base, offset ) < 0 )
                continue;
            input_item_SetURI( input, uri );
            free( uri );
            char option[64];
            snprintf( option, sizeof( option ), "%s%" PRIu64,
                      VLC_INPUT_OPTION_POWERVLC_INDEX_OFFSET_PREFIX, offset );
            input_item_AddOption( input, option, 0 );
            input_item_SetPreparsed( input, false );
            /* An empty first expansion turns the input into ITEM_TYPE_NODE.
             * Restore its browsable type before requesting the new index
             * generation, otherwise every UI correctly sees a childless
             * terminal row and removes its disclosure chevron. */
            vlc_mutex_lock( &input->lock );
            input->i_type = ITEM_TYPE_DIRECTORY;
            vlc_mutex_unlock( &input->lock );
            ipod_set_counted_name( input, sys->ipod_music_count );

            while( row->i_children > 0 )
            {
                playlist_item_t *child = row->pp_children[row->i_children - 1];
                child->i_flags &= ~PLAYLIST_RO_FLAG;
                playlist_NodeDeleteBatch( core, child );
            }
            input_item_Hold( input );
            requests[request_count] = input;
            request_items[request_count++] = row;
        }

    if( sys->ipod_session_additions )
    {
        playlist_item_t *session = playlist_ItemGetByInput(
                                      core, sys->ipod_session_additions );
        if( session )
        {
            session->i_flags &= ~PLAYLIST_RO_FLAG;
            playlist_NodeDeleteBatch( core, session );
        }
        input_item_Release( sys->ipod_session_additions );
        sys->ipod_session_additions = NULL;
        sys->ipod_session_addition_count = 0;
    }
    playlist_Unlock( core );
    free( base );

    for( size_t i = 0; i < request_count; ++i )
    {
        libvlc_MetadataRequest( sd->obj.libvlc, requests[i],
            META_REQUEST_OPTION_SCOPE_LOCAL | META_REQUEST_OPTION_NO_ART,
            120000, request_items[i] );
        input_item_Release( requests[i] );
    }
}

static input_item_t *ipod_lazy_node( const char *path, uint64_t offset,
                                     const char *name )
{
    if( path == NULL || offset == 0 ) return NULL;
    char *base = vlc_path2uri( path, NULL ), *uri = NULL;
    if( base && asprintf( &uri, "%s#%" PRIu64, base, offset ) < 0 ) uri = NULL;
    input_item_t *item = uri ? input_item_NewExt( uri, name, -1,
                                  ITEM_TYPE_DIRECTORY, ITEM_LOCAL ) : NULL;
    if( item )
    {
        input_item_AddOption( item, VLC_INPUT_OPTION_POWERVLC_LAZY_INDEX, 0 );
        char option[64];
        snprintf( option, sizeof( option ), "%s%" PRIu64,
                  VLC_INPUT_OPTION_POWERVLC_INDEX_OFFSET_PREFIX, offset );
        input_item_AddOption( item, option, 0 );
    }
    free( uri ); free( base );
    return item;
}

static void browse_ipod_database( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    vlc_tick_t started = mdate();
    GError *error = NULL;
    set_device_activity( sys, SD_DEVICE_LOADING_ITUNESDB );
    if( sys->ipod_database == NULL )
        sys->ipod_database = ipod_parse_cached( sd, &error );
    Itdb_iTunesDB *database = sys->ipod_database;
    if( database == NULL )
    {
        msg_Err( sd, "libgpod cannot browse the iPod: %s",
                 error ? error->message : "unknown error" );
        if( error ) g_error_free( error );
        set_device_activity( sys, SD_DEVICE_IDLE );
        return;
    }
    if( sys->ipod_track_ids )
        itdb_track_id_tree_destroy( sys->ipod_track_ids );
    sys->ipod_track_ids = itdb_track_id_tree_create( database );
    if( ipod_build_local_index( sd ) != VLC_SUCCESS )
    {
        msg_Err( sd, "cannot build local lazy iPod index" );
        set_device_activity( sys, SD_DEVICE_IDLE );
        return;
    }
    char *music_name = NULL, *podcast_name = NULL, *playlists_name = NULL;
    if( asprintf( &music_name, "%s (%zu)", _( "Music" ),
                  sys->ipod_music_count ) < 0 ) music_name = NULL;
    if( asprintf( &podcast_name, "%s (%zu)", _( "Podcasts" ),
                  sys->ipod_podcast_count ) < 0 ) podcast_name = NULL;
    if( asprintf( &playlists_name, "%s (%zu)", _( "Playlists" ),
                  sys->ipod_playlist_count ) < 0 ) playlists_name = NULL;
    input_item_t *music = ipod_lazy_node( sys->ipod_index_path,
                                          sys->ipod_music_offset,
                                          music_name ? music_name : _( "Music" ) );
    input_item_t *podcasts = ipod_lazy_node( sys->ipod_index_path,
                                             sys->ipod_podcast_offset,
                                             podcast_name ? podcast_name
                                                          : _( "Podcasts" ) );
    if( music ) input_item_AddOption( music,
        VLC_INPUT_OPTION_POWERVLC_DEVICE_STRUCTURE,
        VLC_INPUT_OPTION_UNIQUE );
    if( podcasts ) input_item_AddOption( podcasts,
        VLC_INPUT_OPTION_POWERVLC_DEVICE_STRUCTURE,
        VLC_INPUT_OPTION_UNIQUE );
    if( music )
    {
        services_discovery_AddItem( sd, music );
        remember_visible_root( sys, music );
        sys->ipod_music_root = music;
    }
    if( podcasts )
    {
        services_discovery_AddItem( sd, podcasts );
        remember_visible_root( sys, podcasts );
        sys->ipod_podcast_root = podcasts;
    }
    input_item_t *playlists = input_item_NewExt( "powervlc-ipod-playlists://root",
                                  playlists_name ? playlists_name : _( "Playlists" ),
                                  -1, ITEM_TYPE_NODE, ITEM_LOCAL );
    free( music_name ); free( podcast_name ); free( playlists_name );
    if( playlists )
    {
        input_item_SetPreparsed( playlists, true );
        input_item_AddOption( playlists,
            VLC_INPUT_OPTION_POWERVLC_DEVICE_STRUCTURE,
            VLC_INPUT_OPTION_UNIQUE );
        input_item_AddOption( playlists,
            VLC_INPUT_OPTION_POWERVLC_USER_PLAYLISTS_ROOT,
            VLC_INPUT_OPTION_UNIQUE );
    }
    if( playlists != NULL )
    {
        services_discovery_AddItem( sd, playlists );
        remember_visible_root( sys, playlists );
        for( GList *entry = database->playlists; entry != NULL;
             entry = entry->next )
        {
            Itdb_Playlist *playlist = entry->data;
            if( itdb_playlist_is_mpl( playlist )
             || itdb_playlist_is_podcasts( playlist ) ) continue;
            guint64 lookup = playlist->id;
            uint64_t *offset = sys->ipod_playlist_offsets
                             ? g_hash_table_lookup( sys->ipod_playlist_offsets,
                                                    &lookup ) : NULL;
            input_item_t *node = offset ? ipod_lazy_node(
                                sys->ipod_index_path, *offset,
                                playlist->name ? playlist->name : _( "Playlist" ) )
                                             : NULL;
            if( node )
            {
                input_item_AddOption( node,
                    VLC_INPUT_OPTION_POWERVLC_USER_PLAYLIST,
                    VLC_INPUT_OPTION_UNIQUE );
                char option[64];
                snprintf( option, sizeof( option ), IPOD_PLAYLIST_ID_OPTION
                          "%" PRIu64, (uint64_t)playlist->id );
                input_item_AddOption( node, option, VLC_INPUT_OPTION_UNIQUE );
            }
            if( node ) services_discovery_AddSubItem( sd, playlists, node );
            if( node ) input_item_Release( node );
        }
    }
    msg_Dbg( sd, "lazy iPod roots for %u tracks built in %.3f s",
             itdb_tracks_number( database ),
             (double)(mdate() - started) / CLOCK_FREQ );
    set_device_activity( sys, SD_DEVICE_IDLE );
}
#endif

static input_item_t *add_directory_node( services_discovery_t *sd,
                                         input_item_t *parent,
                                         const char *path, const char *name )
{
    char *uri = vlc_path2uri( path, NULL );
    input_item_t *item = uri ? input_item_NewExt( uri, name, -1,
                              ITEM_TYPE_DIRECTORY, ITEM_LOCAL ) : NULL;
    free( uri );
    if( item == NULL ) return NULL;
    /* Do not mark filesystem directories as preparsed.  Their native
     * directory access will enumerate one level only when the user opens the
     * chevron, keeping slow USB/flash/network readers completely lazy. */
    if( parent ) services_discovery_AddSubItem( sd, parent, item );
    else services_discovery_AddItem( sd, item );
    return item;
}

static void browse_one_level( services_discovery_t *sd, input_item_t *parent,
                              const char *path )
{
    DIR *dir = vlc_opendir( path ); if( !dir ) return;
    const char *name;
    while( (name = vlc_readdir( dir )) != NULL )
    {
        if( name[0] == '.' ) continue;
        /* USB and Rockbox views deliberately expose only the portable-media
         * layout owned by PowerVLC. System files, firmware and arbitrary
         * user folders must remain invisible and therefore immutable here. */
        if( !device_managed_root_name( name ) ) continue;
        char *full = pvlc_path_join( path, name ); if( !full ) continue;
        struct stat st;
        if( vlc_stat( full, &st ) == 0 && S_ISDIR( st.st_mode ) )
        {
            input_item_t *node = add_directory_node( sd, parent, full, name );
            if( node )
            {
                if( parent ) input_item_Release( node );
                else remember_visible_root( sd->p_sys, node );
            }
        }
        else if( vlc_stat( full, &st ) == 0 && S_ISREG( st.st_mode ) )
        {
            pvlc_media_type_t type;
            const char *dot = strrchr( name, '.' );
            bool playlist = dot && (!strcasecmp( dot, ".m3u" )
                         || !strcasecmp( dot, ".m3u8" )
                         || !strcasecmp( dot, ".xspf" ));
            if( playlist || pvlc_media_type( full, &type ) == VLC_SUCCESS )
            {
                char *uri = vlc_path2uri( full, NULL );
                input_item_t *item = uri ? input_item_NewFile( uri, name, -1,
                                                               ITEM_LOCAL ) : NULL;
                free( uri );
                if( item )
                {
                    if( parent ) services_discovery_AddSubItem( sd, parent, item );
                    else services_discovery_AddItem( sd, item );
                    if( parent ) input_item_Release( item );
                    else remember_visible_root( sd->p_sys, item );
                }
            }
        }
        free( full );
    }
    closedir( dir );
}

static void refresh_tree( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    set_device_activity( sys, SD_DEVICE_LOADING_CONTENTS );
    remove_visible_roots( sd );
#ifdef HAVE_LIBGPOD
    if( !strcasecmp( sys->device.kind, "ipod" ) )
        browse_ipod_database( sd );
    else
#endif
        browse_one_level( sd, NULL, sys->device.path );
    update_device_space( sys );
    set_device_activity( sys, SD_DEVICE_IDLE );
}

static int copy_tree( const char *source, const char *destination,
                      unsigned depth )
{
    if( depth > 32 ) return VLC_EGENERIC;
    struct stat st; if( vlc_stat( source, &st ) != 0 ) return VLC_EGENERIC;
    if( S_ISREG( st.st_mode ) ) return pvlc_copy_file( source, destination );
    if( !S_ISDIR( st.st_mode ) || pvlc_mkdir_parents( destination ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    DIR *dir = vlc_opendir( source ); if( !dir ) return VLC_EGENERIC;
    int ret = VLC_SUCCESS; const char *name;
    while( (name = vlc_readdir( dir )) != NULL )
    {
        if( !strcmp( name, "." ) || !strcmp( name, ".." ) ) continue;
        char *src = pvlc_path_join( source, name );
        char *dst = pvlc_path_join( destination, name );
        if( !src || !dst || copy_tree( src, dst, depth + 1 ) != VLC_SUCCESS )
            ret = VLC_EGENERIC;
        free( src ); free( dst ); if( ret != VLC_SUCCESS ) break;
    }
    closedir( dir ); return ret;
}

static bool path_is_inside( const char *parent, const char *child )
{
    char *canonical_parent = realpath( parent, NULL );
    char *canonical_child = realpath( child, NULL );
    char *ancestor = canonical_child ? NULL : strdup( child );
    while( canonical_child == NULL && ancestor != NULL )
    {
        char *slash = strrchr( ancestor, '/' );
#ifdef _WIN32
        char *backslash = strrchr( ancestor, '\\' );
        if( backslash && (!slash || backslash > slash) ) slash = backslash;
#endif
        if( slash == NULL ) break;
        if( slash == ancestor ) slash[1] = '\0'; else *slash = '\0';
        canonical_child = realpath( ancestor, NULL );
        if( slash == ancestor ) break;
    }
    free( ancestor );
    const char *p = canonical_parent ? canonical_parent : parent;
    const char *c = canonical_child ? canonical_child : child;
    size_t length = strlen( p );
    while( length > 1 && (p[length - 1] == '/' || p[length - 1] == '\\') )
        length--;
    bool inside = !strncasecmp( p, c, length )
               && (c[length] == '\0' || c[length] == '/' || c[length] == '\\');
    free( canonical_parent ); free( canonical_child ); return inside;
}

static bool delete_regular_path_tree( services_discovery_t *sd,
                                      const char *path, unsigned depth )
{
    if( depth > 64 ) return false;
    struct stat st;
    if( vlc_lstat( path, &st ) != 0 ) return errno == ENOENT;
    if( !S_ISDIR( st.st_mode ) )
    {
        if( vlc_unlink( path ) == 0 ) return true;
        msg_Warn( sd, "cannot delete %s: %s", path, vlc_strerror_c( errno ) );
        return false;
    }
    DIR *dir = vlc_opendir( path );
    if( dir == NULL ) return false;
    bool success = true; const char *name;
    while( success && (name = vlc_readdir( dir )) != NULL )
    {
        if( !strcmp( name, "." ) || !strcmp( name, ".." ) ) continue;
        char *child = pvlc_path_join( path, name );
        success = child && delete_regular_path_tree( sd, child, depth + 1 );
        free( child );
    }
    closedir( dir );
    if( success && remove( path ) != 0 )
    {
        msg_Warn( sd, "cannot remove directory %s: %s", path,
                  vlc_strerror_c( errno ) );
        success = false;
    }
    return success;
}

static bool delete_device_paths( services_discovery_t *sd, char **paths,
                                 size_t count )
{
    services_discovery_sys_t *sys = sd->p_sys;
    bool success = true;
    set_device_activity( sys, SD_DEVICE_DELETING );
#ifdef HAVE_LIBGPOD
    if( !strcasecmp( sys->device.kind, "ipod" ) && sys->ipod_database )
    {
        /* Deletions are only reflected in the view.  The database and media
         * files stay untouched until the user explicitly commits the whole
         * session, so several edits still cost a single iTunesDB write. */
        for( size_t i = 0; i < count; ++i )
        {
            bool duplicate = false;
            for( size_t j = 0; j < sys->pending_ipod_deletion_count; ++j )
                if( !strcmp( paths[i], sys->pending_ipod_deletions[j] ) )
                { duplicate = true; break; }
            if( duplicate ) continue;
            char *copy = strdup( paths[i] );
            char **grown = copy ? realloc( sys->pending_ipod_deletions,
                (sys->pending_ipod_deletion_count + 1) * sizeof( *grown ) )
                               : NULL;
            if( grown == NULL ) { free( copy ); success = false; continue; }
            sys->pending_ipod_deletions = grown;
            sys->pending_ipod_deletions[sys->pending_ipod_deletion_count++] = copy;
        }
        vlc_mutex_lock( &sys->lock );
        sys->pending_changes = sys->pending_ipod_deletion_count > 0
                            || sys->pending_ipod_addition_count > 0;
        vlc_mutex_unlock( &sys->lock );
        if( ipod_write_deletion_overlay( sys ) != VLC_SUCCESS )
        {
            msg_Err( sd, "cannot update the local iPod deletion overlay" );
            success = false;
        }
    }
    else
#endif
        for( size_t i = 0; i < count; ++i )
            if( !device_path_is_managed( &sys->device, paths[i] )
             || !delete_regular_path_tree( sd, paths[i], 0 ) ) success = false;
    update_device_space( sys );
    set_device_activity( sys, SD_DEVICE_IDLE );
    return success;
}

/* A regular/Rockbox player mirrors its filesystem one-to-one.  Once a
 * recursive deletion succeeded, remove only the selected root rows from the
 * core playlist.  Rebuilding the whole service tree would needlessly close
 * every outline branch (and is very expensive for a large Rockbox volume). */
static void remove_regular_device_items( services_discovery_t *sd,
                                         const int *item_ids, size_t count )
{
    if( item_ids == NULL || count == 0 ) return;
    playlist_t *core = (playlist_t *)sd->obj.parent;
    playlist_Lock( core );
    for( size_t i = 0; i < count; ++i )
    {
        playlist_item_t *item = playlist_ItemGetById( core, item_ids[i] );
        if( item == NULL ) continue; /* an earlier selected parent removed it */
        item->i_flags &= ~PLAYLIST_RO_FLAG;
        playlist_NodeDeleteBatch( core, item );
    }
    playlist_Unlock( core );
}

#ifdef HAVE_LIBGPOD
static int ipod_collect_fully_deleted_nodes(
    services_discovery_sys_t *, playlist_item_t *, GHashTable *,
    playlist_item_t ***, size_t * );

static bool ipod_path_is_selected( input_item_t *input, char **paths,
                                   size_t count )
{
    if( input == NULL ) return false;
    char *uri = input_item_GetURI( input );
    char *path = uri ? vlc_uri2path( uri ) : NULL;
    free( uri );
    bool selected = false;
    for( size_t i = 0; path && i < count && !selected; ++i )
        selected = !strcmp( path, paths[i] );
    free( path );
    return selected;
}

static int ipod_collect_path_items( playlist_item_t *parent, char **paths,
                                    size_t count, playlist_item_t ***items,
                                    size_t *item_count )
{
    if( parent == NULL || parent->i_children < 0 ) return VLC_SUCCESS;
    for( int i = 0; i < parent->i_children; ++i )
    {
        playlist_item_t *child = parent->pp_children[i];
        if( child->i_children >= 0 )
        {
            int ret = ipod_collect_path_items( child, paths, count, items,
                                               item_count );
            if( ret != VLC_SUCCESS ) return ret;
        }
        else if( ipod_path_is_selected( child->p_input, paths, count ) )
        {
            playlist_item_t **grown = realloc( *items,
                (*item_count + 1) * sizeof( *grown ) );
            if( grown == NULL ) return VLC_ENOMEM;
            *items = grown;
            (*items)[(*item_count)++] = child;
        }
    }
    return VLC_SUCCESS;
}

/* A track can be visible simultaneously in several virtual iPod views and
 * playlists. Remove only those materialised leaf occurrences. This keeps all
 * unrelated branches expanded and avoids rebuilding tens of thousands of
 * lazy rows after a staged deletion. */
static void remove_ipod_device_paths( services_discovery_t *sd, char **paths,
                                      size_t count )
{
    if( paths == NULL || count == 0 ) return;
    services_discovery_sys_t *sys = sd->p_sys;
    playlist_t *core = (playlist_t *)sd->obj.parent;
    playlist_item_t **items = NULL;
    size_t item_count = 0;
    playlist_item_t **stale_nodes = NULL;
    size_t stale_node_count = 0;
    GHashTable *selected = g_hash_table_new( g_str_hash, g_str_equal );
    if( selected )
        for( size_t i = 0; i < count; ++i )
            g_hash_table_add( selected, paths[i] );
    playlist_Lock( core );
    ipod_update_visible_counts( sd, core );
    for( size_t i = 0; i < sys->visible_root_count; ++i )
    {
        playlist_item_t *root = playlist_ItemGetByInput( core,
                                                        sys->visible_roots[i] );
        if( ipod_collect_path_items( root, paths, count, &items,
                                    &item_count ) != VLC_SUCCESS )
            break;
        /* Music and Podcasts are virtual views backed by the local compact
         * index. Playlists are user objects and must remain even when all
         * their members were physically removed. */
        if( selected && i < 2 && root && root->i_children >= 0 )
        {
            /* The direct children of Music are permanent structural views
             * (Album Artists, Artists, Albums...). Never remove those rows,
             * even when the player becomes empty; only prune below them. */
            for( int child = 0; child < root->i_children; ++child )
                if( ipod_collect_fully_deleted_nodes( sys,
                        root->pp_children[child], selected, &stale_nodes,
                        &stale_node_count ) != VLC_SUCCESS )
                    break;
        }
    }
    for( size_t i = 0; i < item_count; ++i )
    {
        /* Every collected entry is a leaf, so removing an earlier occurrence
         * cannot invalidate another pointer in this array. */
        items[i]->i_flags &= ~PLAYLIST_RO_FLAG;
        playlist_NodeDeleteBatch( core, items[i] );
    }
    for( size_t i = 0; i < stale_node_count; ++i )
    {
        /* A fully-selected lazy album/artist/bucket otherwise keeps showing
         * the pre-deletion contents from the immutable session index. */
        stale_nodes[i]->i_flags &= ~PLAYLIST_RO_FLAG;
        playlist_NodeDeleteBatch( core, stale_nodes[i] );
    }
    playlist_Unlock( core );
    if( selected ) g_hash_table_destroy( selected );
    free( stale_nodes ); free( items );
}

static void ipod_clear_path_list( char ***paths, size_t *count,
                                  bool remove_files )
{
    for( size_t i = 0; i < *count; ++i )
    {
        if( remove_files ) vlc_unlink( (*paths)[i] );
        free( (*paths)[i] );
    }
    free( *paths ); *paths = NULL; *count = 0;
}

static bool ipod_delete_staged_files( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    size_t failed = 0;
    for( size_t i = 0; i < sys->pending_ipod_deletion_count; ++i )
    {
        char *path = sys->pending_ipod_deletions[i];
        if( vlc_unlink( path ) == 0 || errno == ENOENT )
        { free( path ); continue; }
        msg_Err( sd, "cannot remove finalized iPod media %s: %s", path,
                 vlc_strerror_c( errno ) );
        sys->pending_ipod_deletions[failed++] = path;
    }
    sys->pending_ipod_deletion_count = failed;
    if( failed == 0 )
    { free( sys->pending_ipod_deletions ); sys->pending_ipod_deletions = NULL; }
    else
    {
        char **shrunk = realloc( sys->pending_ipod_deletions,
                                 failed * sizeof( *shrunk ) );
        if( shrunk ) sys->pending_ipod_deletions = shrunk;
    }
    return failed == 0;
}

static bool ipod_commit_changes( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( sys->ipod_database == NULL ) return false;
    set_device_activity( sys, SD_DEVICE_UPDATING_ITUNESDB );
    for( GList *entry = sys->ipod_database->tracks, *next; entry; entry = next )
    {
        next = entry->next;
        Itdb_Track *track = entry->data;
        if( ipod_track_is_staged_for_deletion( sys, track ) )
        {
            ipod_remove_track_completely( sys->ipod_database, track );
        }
    }
    GError *error = NULL;
    bool written = itdb_write( sys->ipod_database, &error );
    if( !written )
    {
        msg_Err( sd, "cannot commit pending iTunesDB changes: %s",
                 error ? error->message : "unknown error" );
        if( error ) g_error_free( error );
        vlc_mutex_lock( &sys->lock ); sys->commit_failed = true;
        vlc_mutex_unlock( &sys->lock );
    }
    else
    {
        /* iTunesDB no longer references these tracks. Remove the physical
         * media now and retain failures as pending work so Finalize can be
         * retried instead of silently leaking files on the iPod. */
        bool files_deleted = ipod_delete_staged_files( sd );
        ipod_clear_path_list( &sys->pending_ipod_additions,
                              &sys->pending_ipod_addition_count, false );
        bool overlay_written = ipod_write_deletion_overlay( sys ) == VLC_SUCCESS;
        vlc_mutex_lock( &sys->lock );
        sys->pending_changes = !files_deleted;
        sys->commit_failed = !files_deleted || !overlay_written;
        vlc_mutex_unlock( &sys->lock );
        /* itdb_write() reassigns track ids. Rebuild the lookup immediately;
         * otherwise later playlist actions could resolve an old id to a
         * deleted track. */
        if( sys->ipod_track_ids )
            itdb_track_id_tree_destroy( sys->ipod_track_ids );
        sys->ipod_track_ids = itdb_track_id_tree_create(
                                                sys->ipod_database );
        update_device_space( sys );
        written = files_deleted && overlay_written;
    }
    set_device_activity( sys, SD_DEVICE_IDLE );
    return written;
}

static void ipod_discard_changes( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    ipod_clear_path_list( &sys->pending_ipod_additions,
                          &sys->pending_ipod_addition_count, true );
    ipod_clear_path_list( &sys->pending_ipod_deletions,
                          &sys->pending_ipod_deletion_count, false );
    if( sys->ipod_track_ids )
    { itdb_track_id_tree_destroy( sys->ipod_track_ids );
      sys->ipod_track_ids = NULL; }
    if( sys->ipod_database ) itdb_free( sys->ipod_database );
    sys->ipod_database = NULL;
    vlc_mutex_lock( &sys->lock );
    sys->pending_changes = false;
    sys->commit_failed = false;
    vlc_mutex_unlock( &sys->lock );
    update_device_space( sys );
}
#endif

static void *Run( void *data )
{
    services_discovery_t *sd = data; services_discovery_sys_t *sys = sd->p_sys;
    refresh_tree( sd );
    for( ;; )
    {
        /* Cancellation is used by Close() to abort a blocked copy/transcode.
         * Never allow it while this mutex is owned. */
        int cancel = vlc_savecancel();
        vlc_mutex_lock( &sys->lock );
        while( !sys->stop && !sys->refresh
            && !sys->backup_request && sys->drop_count == 0
            && sys->delete_count == 0 && !sys->commit_request
            && !sys->discard_request )
            vlc_cond_wait( &sys->wait, &sys->lock );
        /* Some interfaces send one control call per selected path.  Coalesce
         * the short burst for both additions and deletions: a large batch
         * must produce one transfer/update and at most one lazy-index/tree
         * rebuild, never one rebuild per media item. */
        if( !sys->stop && (sys->drop_count > 0 || sys->delete_count > 0) )
        {
            vlc_tick_t deadline = mdate() + CLOCK_FREQ / 10;
            while( !sys->stop
                && vlc_cond_timedwait( &sys->wait, &sys->lock, deadline ) == 0 )
                ;
        }
        bool stop = sys->stop, refresh = sys->refresh;
        char *backup = sys->backup_request;
        char **drop_paths = sys->drop_paths; size_t drop_count = sys->drop_count;
        uint64_t *drop_transfers = sys->drop_transfers;
        char **delete_paths = sys->delete_paths;
        size_t delete_count = sys->delete_count;
        int *delete_item_ids = sys->delete_item_ids;
        size_t delete_item_count = sys->delete_item_count;
        bool commit = sys->commit_request, discard = sys->discard_request;
        sys->refresh = false; sys->backup_request = NULL;
        sys->drop_paths = NULL; sys->drop_transfers = NULL; sys->drop_count = 0;
        sys->delete_paths = NULL; sys->delete_count = 0;
        sys->delete_item_ids = NULL; sys->delete_item_count = 0;
        sys->commit_request = false; sys->discard_request = false;
        vlc_mutex_unlock( &sys->lock );
        vlc_restorecancel( cancel );
        if( stop )
        {
            free( backup );
            for( size_t i = 0; i < drop_count; ++i ) free( drop_paths[i] );
            free( drop_paths ); free( drop_transfers );
            for( size_t i = 0; i < delete_count; ++i ) free( delete_paths[i] );
            free( delete_paths ); free( delete_item_ids ); break;
        }
        bool transfer_work = drop_count > 0;
        if( transfer_work ) transfer_set_activity( sys, true );
        if( drop_count )
        {
            refresh |= sync_dropped_paths( sd, drop_paths, drop_transfers,
                                            drop_count );
        }
        if( transfer_work ) transfer_set_activity( sys, false );
        for( size_t i = 0; i < drop_count; ++i ) free( drop_paths[i] );
        free( drop_paths ); free( drop_transfers );
        if( delete_count )
        {
            bool deleted = delete_device_paths( sd, delete_paths,
                                                delete_count );
#ifdef HAVE_LIBGPOD
            bool ipod = !strcasecmp( sys->device.kind, "ipod" );
#else
            bool ipod = false;
#endif
#ifdef HAVE_LIBGPOD
            if( ipod && deleted )
                remove_ipod_device_paths( sd, delete_paths, delete_count );
#endif
            if( deleted )
                remove_regular_device_items( sd, delete_item_ids,
                                              delete_item_count );
        }
        for( size_t i = 0; i < delete_count; ++i ) free( delete_paths[i] );
        free( delete_paths );
        free( delete_item_ids );
#ifdef HAVE_LIBGPOD
        if( commit && !strcasecmp( sys->device.kind, "ipod" ) )
        {
            bool defer;
            vlc_mutex_lock( &sys->lock );
            defer = sys->transferring || sys->drop_count > 0;
            if( defer )
                /* More transfers arrived while the preceding batch was
                 * running. Keep the user's request queued behind them. */
                sys->commit_request = true;
            else
                sys->activity = SD_DEVICE_UPDATING_ITUNESDB;
            vlc_mutex_unlock( &sys->lock );
            if( !defer )
                /* This only serializes the in-memory state already
                 * represented by the tree. Rebuilding it would collapse all
                 * open branches. */
                ipod_commit_changes( sd );
        }
        if( discard && !strcasecmp( sys->device.kind, "ipod" ) )
        {
            ipod_discard_changes( sd ); refresh = true;
        }
#else
        VLC_UNUSED( commit ); VLC_UNUSED( discard );
#endif
        if( backup )
        {
            if( path_is_inside( sys->device.path, backup ) )
                msg_Err( sd, "refusing a backup destination inside the device" );
            else
            {
                char *target = pvlc_path_join( backup, sys->device.name );
                if( target )
                { copy_tree( sys->device.path, target, 0 ); free( target ); }
            }
            free( backup );
        }
        if( refresh ) refresh_tree( sd );
    }
    return NULL;
}

#ifdef HAVE_LIBGPOD
/* playlist_ServicesDiscoveryControl() calls service controls with the core
 * playlist lock held. iPod playlist nodes carry the stable libgpod id in
 * their URI, so transient UI item ids never become database identities. */
static bool ipod_playlist_id_from_item( playlist_t *core, int item_id,
                                        guint64 *playlist_id )
{
    playlist_item_t *item = playlist_ItemGetById( core, item_id );
    input_item_t *input = item ? item->p_input : NULL;
    const size_t option_length = strlen( IPOD_PLAYLIST_ID_OPTION );
    bool valid = false;
    if( input )
    {
        vlc_mutex_lock( &input->lock );
        for( int i = 0; i < input->i_options && !valid; ++i )
            if( !strncmp( input->ppsz_options[i], IPOD_PLAYLIST_ID_OPTION,
                          option_length ) )
            {
                char *end = NULL;
                uint64_t value = strtoull( input->ppsz_options[i]
                                           + option_length, &end, 10 );
                valid = value != 0 && end && *end == '\0';
                if( valid ) *playlist_id = value;
            }
        vlc_mutex_unlock( &input->lock );
    }
    if( valid ) return true;
    char *uri = input ? input_item_GetURI( input ) : NULL;
    const char prefix[] = "powervlc-ipod-playlist://";
    valid = uri && !strncmp( uri, prefix, sizeof( prefix ) - 1 );
    if( valid )
    {
        char *end = NULL;
        uint64_t value = strtoull( uri + sizeof( prefix ) - 1, &end, 10 );
        valid = value != 0 && end && *end == '\0';
        if( valid ) *playlist_id = value;
    }
    free( uri );
    return valid;
}

static Itdb_Track *ipod_track_from_core_item( services_discovery_sys_t *sys,
                                               playlist_item_t *item )
{
    if( item == NULL || item->p_input == NULL || item->i_children >= 0 )
        return NULL;
    guint32 track_id = 0;
    size_t prefix_length = strlen( IPOD_TRACK_ID_OPTION );
    vlc_mutex_lock( &item->p_input->lock );
    for( int i = 0; i < item->p_input->i_options && track_id == 0; ++i )
        if( !strncmp( item->p_input->ppsz_options[i], IPOD_TRACK_ID_OPTION,
                      prefix_length ) )
            track_id = strtoul( item->p_input->ppsz_options[i] + prefix_length,
                                NULL, 10 );
    vlc_mutex_unlock( &item->p_input->lock );
    Itdb_Track *by_id = track_id && sys->ipod_track_ids
                      ? itdb_track_id_tree_by_id( sys->ipod_track_ids,
                                                  track_id ) : NULL;
    if( by_id ) return by_id;

    /* Compatibility fallback for items imported from another tree: compare
     * in-memory path strings only. ipod_track_path() never stats the iPod. */
    char *uri = input_item_GetURI( item->p_input );
    char *path = uri ? vlc_uri2path( uri ) : NULL;
    free( uri );
    if( path == NULL ) return NULL;
    Itdb_Track *found = NULL;
    for( GList *entry = sys->ipod_database->tracks; entry; entry = entry->next )
    {
        Itdb_Track *track = entry->data;
        gchar *candidate = ipod_track_path( track );
        bool match = candidate && !strcmp( candidate, path );
        g_free( candidate );
        if( match ) { found = track; break; }
    }
    free( path );
    return found;
}

static void ipod_mark_playlist_change_locked( services_discovery_sys_t *sys,
                                               bool refresh )
{
    sys->pending_changes = true;
    if( refresh )
    {
        sys->refresh = true;
        vlc_cond_signal( &sys->wait );
    }
}

static int ipod_playlist_control( services_discovery_t *sd, int query,
                                  va_list args )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( strcasecmp( sys->device.kind, "ipod" ) || sys->ipod_database == NULL )
        return VLC_EGENERIC;
    playlist_t *core = (playlist_t *)sd->obj.parent;
    int ret = VLC_EGENERIC;

    if( query == SD_CMD_POWERVLC_PLAYLIST_CREATE )
    {
        const services_discovery_playlist_create_t *request = va_arg( args,
                                  const services_discovery_playlist_create_t * );
        playlist_item_t *parent = request
                                ? playlist_ItemGetById( core, request->i_parent_id )
                                : NULL;
        char *uri = parent && parent->p_input
                  ? input_item_GetURI( parent->p_input ) : NULL;
        bool root = uri && !strcmp( uri, "powervlc-ipod-playlists://root" );
        free( uri );
        if( request == NULL || request->b_folder || !request->psz_name
         || !*request->psz_name || !root ) return VLC_EGENERIC;
        vlc_mutex_lock( &sys->lock );
        Itdb_Playlist *created = itdb_playlist_new( request->psz_name, false );
        if( created )
        {
            itdb_playlist_add( sys->ipod_database, created, -1 );
            ipod_mark_playlist_change_locked( sys, false );
            char playlist_uri[96];
            snprintf( playlist_uri, sizeof( playlist_uri ),
                      "powervlc-ipod-playlist://%"
                      PRIu64, (uint64_t)created->id );
            input_item_t *input = input_item_NewExt( playlist_uri,
                                      request->psz_name,
                                      -1, ITEM_TYPE_NODE, ITEM_LOCAL );
            if( input )
            {
                input_item_SetPreparsed( input, true );
                input_item_AddOption( input,
                    VLC_INPUT_OPTION_POWERVLC_USER_PLAYLIST,
                    VLC_INPUT_OPTION_UNIQUE );
                char option[64];
                snprintf( option, sizeof( option ), IPOD_PLAYLIST_ID_OPTION
                          "%" PRIu64, (uint64_t)created->id );
                input_item_AddOption( input, option, VLC_INPUT_OPTION_UNIQUE );
                ret = playlist_NodeAddInput( core, input, parent,
                                             PLAYLIST_END )
                    ? VLC_SUCCESS : VLC_ENOMEM;
                input_item_Release( input );
            }
            if( ret == VLC_SUCCESS )
            {
                ++sys->ipod_playlist_count;
                char *label = NULL;
                if( asprintf( &label, "%s (%zu)", _( "Playlists" ),
                              sys->ipod_playlist_count ) >= 0 )
                { input_item_SetName( parent->p_input, label ); free( label ); }
            }
        }
        vlc_mutex_unlock( &sys->lock );
        return ret;
    }

    if( query == SD_CMD_POWERVLC_PLAYLIST_RENAME
     || query == SD_CMD_POWERVLC_PLAYLIST_DELETE )
    {
        int item_id; const char *name = NULL;
        if( query == SD_CMD_POWERVLC_PLAYLIST_RENAME )
        {
            const services_discovery_playlist_rename_t *request = va_arg( args,
                                  const services_discovery_playlist_rename_t * );
            if( request == NULL || !request->psz_name || !*request->psz_name )
                return VLC_EGENERIC;
            item_id = request->i_item_id; name = request->psz_name;
        }
        else
        {
            const services_discovery_playlist_item_t *request = va_arg( args,
                                      const services_discovery_playlist_item_t * );
            if( request == NULL ) return VLC_EGENERIC;
            item_id = request->i_item_id;
        }
        guint64 id;
        if( !ipod_playlist_id_from_item( core, item_id, &id ) )
            return VLC_EGENERIC;
        playlist_item_t *core_item = playlist_ItemGetById( core, item_id );
        if( core_item == NULL || core_item->p_input == NULL )
            return VLC_EGENERIC;
        vlc_mutex_lock( &sys->lock );
        Itdb_Playlist *playlist = itdb_playlist_by_id( sys->ipod_database, id );
        if( playlist && !itdb_playlist_is_mpl( playlist )
                     && !itdb_playlist_is_podcasts( playlist ) )
        {
            if( name )
            {
                gchar *copy = g_strdup( name );
                if( copy ) { g_free( playlist->name ); playlist->name = copy;
                             ret = VLC_SUCCESS; }
            }
            else { itdb_playlist_remove( playlist ); ret = VLC_SUCCESS; }
            if( ret == VLC_SUCCESS )
                ipod_mark_playlist_change_locked( sys, false );
        }
        vlc_mutex_unlock( &sys->lock );
        if( ret == VLC_SUCCESS )
        {
            if( name )
                input_item_SetName( core_item->p_input, name );
            else
            {
                /* The libgpod object has already been removed from the
                 * in-memory database.  Mirror that one operation in the core
                 * tree instead of rebuilding all tracks, virtual views and
                 * playlist occurrences. */
                core_item->i_flags &= ~PLAYLIST_RO_FLAG;
                playlist_NodeDeleteBatch( core, core_item );
            }
        }
        return ret;
    }

    const services_discovery_playlist_drop_t *drop = NULL;
    const services_discovery_playlist_remove_t *remove = NULL;
    int parent_id, insert_at = -1; size_t count; const int *ids;
    bool copy = false;
    if( query == SD_CMD_POWERVLC_PLAYLIST_DROP )
    {
        drop = va_arg( args, const services_discovery_playlist_drop_t * );
        if( drop == NULL ) return VLC_EGENERIC;
        parent_id = drop->i_parent_id; count = drop->i_count;
        ids = drop->p_item_ids; insert_at = drop->i_index; copy = drop->b_copy;
    }
    else
    {
        remove = va_arg( args, const services_discovery_playlist_remove_t * );
        if( remove == NULL ) return VLC_EGENERIC;
        parent_id = remove->i_parent_id; count = remove->i_count;
        ids = remove->p_item_ids;
    }
    if( count == 0 || count > INT_MAX || ids == NULL ) return VLC_EGENERIC;
    guint64 target_id;
    if( !ipod_playlist_id_from_item( core, parent_id, &target_id ) )
        return VLC_EGENERIC;
    playlist_item_t *target_core = playlist_ItemGetById( core, parent_id );
    Itdb_Track **tracks = calloc( count, sizeof( *tracks ) );
    playlist_item_t **core_items = calloc( count, sizeof( *core_items ) );
    int *positions = malloc( count * sizeof( *positions ) );
    if( tracks == NULL || core_items == NULL || positions == NULL )
    {
        free( tracks ); free( core_items ); free( positions );
        return VLC_ENOMEM;
    }
    for( size_t i = 0; i < count; ++i )
    {
        playlist_item_t *item = playlist_ItemGetById( core, ids[i] );
        core_items[i] = item;
        tracks[i] = ipod_track_from_core_item( sys, item );
        positions[i] = -1;
        if( item && target_core && item->p_parent == target_core )
            for( int child = 0; child < target_core->i_children; ++child )
                if( target_core->pp_children[child] == item )
                { positions[i] = child; break; }
        if( tracks[i] == NULL )
        {
            free( tracks ); free( core_items ); free( positions );
            return VLC_EGENERIC;
        }
    }
    int core_insert_at = insert_at;
    if( query == SD_CMD_POWERVLC_PLAYLIST_DROP && !copy && insert_at >= 0
     && target_core )
        for( size_t i = 0; i < count; ++i )
        {
            if( positions[i] >= 0 && positions[i] < insert_at ) --insert_at;
        }
    bool moved_in_place = query == SD_CMD_POWERVLC_PLAYLIST_DROP && !copy
                       && target_core != NULL;
    for( size_t i = 0; moved_in_place && i < count; ++i )
        moved_in_place = positions[i] >= 0 && core_items[i] != NULL;

    vlc_mutex_lock( &sys->lock );
    Itdb_Playlist *target = itdb_playlist_by_id( sys->ipod_database, target_id );
    if( target )
    {
        if( query == SD_CMD_POWERVLC_PLAYLIST_REMOVE || !copy )
        {
            /* Delete membership links from the end so duplicate tracks and
             * multiple selections retain exact occurrence semantics. */
            for( size_t removed = 0; removed < count; ++removed )
            {
                int highest = -1; size_t selected = count;
                for( size_t i = 0; i < count; ++i )
                    if( positions[i] > highest )
                    { highest = positions[i]; selected = i; }
                if( selected == count ) break;
                GList *link = g_list_nth( target->members, highest );
                if( link ) target->members = g_list_delete_link(
                                                target->members, link );
                positions[selected] = -1;
            }
        }
        if( query == SD_CMD_POWERVLC_PLAYLIST_DROP )
        {
            int length = g_list_length( target->members );
            int position = insert_at < 0 ? length : insert_at;
            if( position > length ) position = length;
            for( size_t i = 0; i < count; ++i )
                itdb_playlist_add_track( target, tracks[i], position++ );
        }
        /* Reordering an existing playlist is already fully represented by
         * the in-memory libgpod list.  Mirror that same move directly in the
         * core tree while playlist_ServicesDiscoveryControl() still owns the
         * playlist lock.  Rebuilding the complete iPod tree here used to
         * allocate and publish every track and every playlist occurrence,
         * blocking the UI for several seconds despite doing no useful disk
         * work. */
        if( moved_in_place )
        {
            int position = core_insert_at < 0 ? target_core->i_children
                                              : core_insert_at;
            if( position > target_core->i_children )
                position = target_core->i_children;
            moved_in_place = playlist_TreeMoveMany( core, (int)count,
                                  core_items, target_core, position )
                          == VLC_SUCCESS;
        }
        bool inserted_in_place = query == SD_CMD_POWERVLC_PLAYLIST_DROP
                              && copy && target_core != NULL
                              && target_core->i_children >= 0;
        if( inserted_in_place )
        {
            int position = core_insert_at < 0 ? target_core->i_children
                                              : core_insert_at;
            if( position > target_core->i_children )
                position = target_core->i_children;
            for( size_t i = 0; i < count; ++i )
            {
                input_item_t *input = ipod_track_item( tracks[i] );
                playlist_item_t *added = input
                    ? playlist_NodeAddInput( core, input, target_core,
                                             position++ ) : NULL;
                if( input ) input_item_Release( input );
                if( added == NULL ) { inserted_in_place = false; break; }
            }
        }
        bool removed_in_place = query == SD_CMD_POWERVLC_PLAYLIST_REMOVE;
        if( removed_in_place )
        {
            /* The control is called with the core playlist lock held.  The
             * selected rows are exact occurrences in this playlist, so
             * remove them directly instead of rebuilding every iPod view and
             * every playlist occurrence from the compact index. */
            for( size_t i = 0; i < count; ++i )
            {
                core_items[i]->i_flags &= ~PLAYLIST_RO_FLAG;
                playlist_NodeDelete( core, core_items[i] );
            }
        }
        /* Never rebuild the complete device tree for a playlist edit. The
         * database change is already staged in RAM; when the destination is
         * materialised the matching core rows were updated above. */
        ipod_mark_playlist_change_locked( sys, false );
        ret = VLC_SUCCESS;
    }
    vlc_mutex_unlock( &sys->lock );
    free( tracks ); free( core_items ); free( positions );
    return ret;
}

static int ipod_delete_path_append( services_discovery_sys_t *sys,
                                    char ***paths, size_t *count,
                                    const char *path, GHashTable *seen )
{
    if( path == NULL || !path_has_device_prefix( sys->device.path, path ) )
        return VLC_EGENERIC;
    if( g_hash_table_contains( seen, path ) ) return VLC_SUCCESS;
    char *copy = strdup( path );
    char **grown = copy ? realloc( *paths, (*count + 1) * sizeof( *grown ) )
                        : NULL;
    if( grown == NULL ) { free( copy ); return VLC_ENOMEM; }
    *paths = grown;
    (*paths)[(*count)++] = copy;
    g_hash_table_add( seen, copy );
    return VLC_SUCCESS;
}

static bool ipod_lazy_index_location( input_item_t *input, char **path,
                                      uint64_t *offset )
{
    *path = NULL; *offset = 0;
    if( input == NULL || !input_item_IsPowerVLCLazyIndex( input ) )
        return false;
    const char prefix[] = VLC_INPUT_OPTION_POWERVLC_INDEX_OFFSET_PREFIX;
    vlc_mutex_lock( &input->lock );
    for( int i = 0; i < input->i_options && *offset == 0; ++i )
        if( !strncmp( input->ppsz_options[i], prefix, sizeof( prefix ) - 1 ) )
            *offset = strtoull( input->ppsz_options[i]
                                      + sizeof( prefix ) - 1, NULL, 10 );
    vlc_mutex_unlock( &input->lock );
    char *uri = input_item_GetURI( input );
    if( uri )
    {
        char *fragment = strchr( uri, '#' );
        if( fragment ) *fragment = '\0';
        *path = vlc_uri2path( uri );
    }
    free( uri );
    return *path != NULL && *offset != 0;
}

static int ipod_resolve_index_node( services_discovery_sys_t *sys, FILE *file,
                                    uint64_t offset, char ***paths,
                                    size_t *count, GHashTable *seen,
                                    unsigned depth )
{
    if( depth > 64 || offset > LONG_MAX
     || fseek( file, (long)offset, SEEK_SET ) != 0 ) return VLC_EGENERIC;
    uint32_t marker = 0, children = 0;
    int ret = pvlc_binary_read_u32( file, &marker );
    if( ret == VLC_SUCCESS && marker != PVLC_IPOD_INDEX_NODE )
        ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &children );
    if( ret == VLC_SUCCESS && children > 1000000 ) ret = VLC_EGENERIC;
    for( uint32_t i = 0; i < children && ret == VLC_SUCCESS; ++i )
    {
        uint32_t type, flags, value, reserved; uint64_t child_offset;
        char *name = NULL;
        ret = pvlc_binary_read_u32( file, &type );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &flags );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &value );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &reserved );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file,
                                                              &child_offset );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &name,
                                                                 1024 * 1024 );
        long next = ftell( file );
        if( ret == VLC_SUCCESS && type == PVLC_IPOD_CHILD_NODE )
            ret = ipod_resolve_index_node( sys, file, child_offset, paths,
                                            count, seen, depth + 1 );
        else if( ret == VLC_SUCCESS && type == PVLC_IPOD_CHILD_MEDIA )
        {
            if( child_offset > LONG_MAX
             || fseek( file, (long)child_offset, SEEK_SET ) != 0 )
                ret = VLC_EGENERIC;
            uint32_t media_marker; char *uri = NULL;
            if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file,
                                                               &media_marker );
            if( ret == VLC_SUCCESS && media_marker != PVLC_IPOD_INDEX_MEDIA )
                ret = VLC_EGENERIC;
            if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &uri,
                                                               16 * 1024 * 1024 );
            char *path = uri ? vlc_uri2path( uri ) : NULL;
            if( ret == VLC_SUCCESS ) ret = ipod_delete_path_append( sys,
                                                  paths, count, path, seen );
            free( path ); free( uri );
        }
        else if( ret == VLC_SUCCESS ) ret = VLC_EGENERIC;
        if( ret == VLC_SUCCESS && (next < 0 || fseek( file, next, SEEK_SET ) != 0) )
            ret = VLC_EGENERIC;
        free( name ); VLC_UNUSED( flags ); VLC_UNUSED( value );
        VLC_UNUSED( reserved );
    }
    return ret;
}

/* Test a lazy subtree against a deletion set without materialising all its
 * paths. Large top-level views normally fail on their first unselected media
 * record, so deleting one album stays effectively constant-time. */
static int ipod_index_node_all_selected( FILE *file, uint64_t offset,
                                        GHashTable *selected, bool *has_media,
                                        bool *all_selected, unsigned depth )
{
    if( depth > 64 || offset > LONG_MAX
     || fseek( file, (long)offset, SEEK_SET ) != 0 ) return VLC_EGENERIC;
    uint32_t marker = 0, children = 0;
    int ret = pvlc_binary_read_u32( file, &marker );
    if( ret == VLC_SUCCESS && marker != PVLC_IPOD_INDEX_NODE )
        ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &children );
    if( ret == VLC_SUCCESS && children > 1000000 ) ret = VLC_EGENERIC;
    for( uint32_t i = 0; i < children && ret == VLC_SUCCESS; ++i )
    {
        uint32_t type, flags, value, reserved;
        uint64_t child_offset;
        char *name = NULL;
        ret = pvlc_binary_read_u32( file, &type );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &flags );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &value );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &reserved );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file,
                                                              &child_offset );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &name,
                                                                 1024 * 1024 );
        long next = ftell( file );
        if( ret == VLC_SUCCESS && type == PVLC_IPOD_CHILD_NODE )
        {
            bool child_has_media = false, child_all_selected = true;
            ret = ipod_index_node_all_selected( file, child_offset, selected,
                           &child_has_media, &child_all_selected, depth + 1 );
            *has_media |= child_has_media;
            if( !child_all_selected ) *all_selected = false;
        }
        else if( ret == VLC_SUCCESS && type == PVLC_IPOD_CHILD_MEDIA )
        {
            if( child_offset > LONG_MAX
             || fseek( file, (long)child_offset, SEEK_SET ) != 0 )
                ret = VLC_EGENERIC;
            uint32_t media_marker = 0;
            char *uri = NULL;
            if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32(
                                                    file, &media_marker );
            if( ret == VLC_SUCCESS
             && media_marker != PVLC_IPOD_INDEX_MEDIA ) ret = VLC_EGENERIC;
            if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file,
                                                    &uri, 16 * 1024 * 1024 );
            char *path = uri ? vlc_uri2path( uri ) : NULL;
            if( ret == VLC_SUCCESS )
            {
                *has_media = true;
                if( path == NULL || !g_hash_table_contains( selected, path ) )
                    *all_selected = false;
            }
            free( path ); free( uri );
        }
        else if( ret == VLC_SUCCESS ) ret = VLC_EGENERIC;
        free( name ); VLC_UNUSED( flags ); VLC_UNUSED( value );
        VLC_UNUSED( reserved );
        if( ret == VLC_SUCCESS && !*all_selected ) return VLC_SUCCESS;
        if( ret == VLC_SUCCESS
         && (next < 0 || fseek( file, next, SEEK_SET ) != 0) )
            ret = VLC_EGENERIC;
    }
    return ret;
}

static bool ipod_lazy_node_fully_selected( input_item_t *input,
                                           GHashTable *selected )
{
    char *path = NULL;
    uint64_t offset = 0;
    if( !ipod_lazy_index_location( input, &path, &offset ) ) return false;
    FILE *file = vlc_fopen( path, "rb" );
    free( path );
    if( file == NULL ) return false;
    setvbuf( file, NULL, _IOFBF, 64 * 1024 );
    static const unsigned char magic[8] = {
        'P', 'V', 'L', 'C', 'L', 'I', 5, 0
    };
    unsigned char actual[sizeof( magic )];
    int ret = pvlc_binary_read( file, actual, sizeof( actual ) );
    if( ret == VLC_SUCCESS && memcmp( actual, magic, sizeof( magic ) ) )
        ret = VLC_EGENERIC;
    bool has_media = false, all_selected = true;
    if( ret == VLC_SUCCESS ) ret = ipod_index_node_all_selected( file, offset,
                         selected, &has_media, &all_selected, 0 );
    fclose( file );
    return ret == VLC_SUCCESS && has_media && all_selected;
}

static int ipod_collect_fully_deleted_nodes(
    services_discovery_sys_t *sys, playlist_item_t *parent,
    GHashTable *selected, playlist_item_t ***items, size_t *count )
{
    VLC_UNUSED( sys );
    if( parent == NULL || parent->i_children < 0 ) return VLC_SUCCESS;
    for( int i = 0; i < parent->i_children; ++i )
    {
        playlist_item_t *child = parent->pp_children[i];
        if( child == NULL ) continue;
        /* An unopened lazy directory still has i_children < 0 in the core,
         * although the interfaces correctly draw a disclosure triangle from
         * its input type. It must be tested before the ordinary leaf check. */
        if( ipod_lazy_node_fully_selected( child->p_input, selected ) )
        {
            playlist_item_t **grown = realloc( *items,
                                      (*count + 1) * sizeof( *grown ) );
            if( grown == NULL ) return VLC_ENOMEM;
            *items = grown;
            (*items)[(*count)++] = child;
            continue;
        }
        if( child->i_children < 0 ) continue;
        int ret = ipod_collect_fully_deleted_nodes( sys, child, selected,
                                                     items, count );
        if( ret != VLC_SUCCESS ) return ret;
    }
    return VLC_SUCCESS;
}

static int ipod_resolve_core_item( services_discovery_sys_t *sys,
                                   playlist_item_t *item, char ***paths,
                                   size_t *count, GHashTable *seen )
{
    if( item == NULL || item->p_input == NULL ) return VLC_EGENERIC;
    char *index_path = NULL; uint64_t offset = 0;
    if( ipod_lazy_index_location( item->p_input, &index_path, &offset ) )
    {
        FILE *file = vlc_fopen( index_path, "rb" );
        free( index_path );
        if( file == NULL ) return VLC_EGENERIC;
        setvbuf( file, NULL, _IOFBF, 64 * 1024 );
        static const unsigned char magic[8] = {
            'P', 'V', 'L', 'C', 'L', 'I', 5, 0
        };
        unsigned char actual[sizeof( magic )];
        int ret = pvlc_binary_read( file, actual, sizeof( actual ) );
        if( ret == VLC_SUCCESS && memcmp( actual, magic, sizeof( magic ) ) )
            ret = VLC_EGENERIC;
        if( ret == VLC_SUCCESS ) ret = ipod_resolve_index_node( sys, file,
                                            offset, paths, count, seen, 0 );
        fclose( file );
        return ret;
    }
    free( index_path );
    if( item->i_children >= 0 )
    {
        for( int i = 0; i < item->i_children; ++i )
        {
            int ret = ipod_resolve_core_item( sys, item->pp_children[i],
                                               paths, count, seen );
            if( ret != VLC_SUCCESS ) return ret;
        }
        return VLC_SUCCESS;
    }
    char *uri = input_item_GetURI( item->p_input );
    char *path = uri ? vlc_uri2path( uri ) : NULL;
    free( uri );
    int ret = ipod_delete_path_append( sys, paths, count, path, seen );
    free( path );
    return ret;
}

static int ipod_resolve_delete_request( services_discovery_t *sd,
                       services_discovery_device_delete_resolve_t *request )
{
    if( request == NULL || request->p_item_ids == NULL
     || request->i_item_count == 0 ) return VLC_EGENERIC;
    request->ppsz_paths = NULL; request->i_count = 0;
    services_discovery_sys_t *sys = sd->p_sys;
    playlist_t *core = (playlist_t *)sd->obj.parent;
    GHashTable *seen = g_hash_table_new( g_str_hash, g_str_equal );
    int ret = seen ? VLC_SUCCESS : VLC_ENOMEM;
    playlist_item_t *music_root = sys->ipod_music_root
        ? playlist_ItemGetByInput( core, sys->ipod_music_root ) : NULL;
    for( size_t i = 0; i < request->i_item_count && ret == VLC_SUCCESS; ++i )
    {
        playlist_item_t *item = playlist_ItemGetById( core,
                                            request->p_item_ids[i] );
        /* Music and its direct children are containers/views, never media
         * ownership scopes. Deleting Album Artists would otherwise resolve
         * every track and erase the entire player through one redundant
         * virtual representation. */
        if( item == NULL || item == music_root || item->p_parent == music_root
         || input_item_IsPowerVLCDeviceStructure( item->p_input ) )
        { ret = VLC_EGENERIC; break; }
        ret = ipod_resolve_core_item( sys, item, &request->ppsz_paths,
                                      &request->i_count, seen );
    }
    if( seen ) g_hash_table_destroy( seen );
    if( ret != VLC_SUCCESS )
    {
        for( size_t i = 0; i < request->i_count; ++i )
            free( request->ppsz_paths[i] );
        free( request->ppsz_paths );
        request->ppsz_paths = NULL; request->i_count = 0;
    }
    return ret;
}
#endif

static int regular_resolve_delete_request( services_discovery_t *sd,
                       services_discovery_device_delete_resolve_t *request )
{
    if( request == NULL || request->p_item_ids == NULL
     || request->i_item_count == 0 ) return VLC_EGENERIC;
    request->ppsz_paths = NULL; request->i_count = 0;
    services_discovery_sys_t *sys = sd->p_sys;
    playlist_t *core = (playlist_t *)sd->obj.parent;
    int ret = VLC_SUCCESS;
    for( size_t i = 0; i < request->i_item_count && ret == VLC_SUCCESS; ++i )
    {
        playlist_item_t *item = playlist_ItemGetById( core,
                                               request->p_item_ids[i] );
        char *uri = item && item->p_input
                  ? input_item_GetURI( item->p_input ) : NULL;
        char *path = uri ? vlc_uri2path( uri ) : NULL; free( uri );
        if( path == NULL || !device_path_is_managed( &sys->device, path ) )
            ret = VLC_EGENERIC;
        else
        {
            bool duplicate = false;
            for( size_t j = 0; j < request->i_count; ++j )
                if( !strcmp( request->ppsz_paths[j], path ) )
                { duplicate = true; break; }
            if( !duplicate )
            {
                char **grown = realloc( request->ppsz_paths,
                         (request->i_count + 1) * sizeof( *grown ) );
                if( grown == NULL ) ret = VLC_ENOMEM;
                else
                {
                    request->ppsz_paths = grown;
                    request->ppsz_paths[request->i_count++] = path;
                    path = NULL;
                }
            }
        }
        free( path );
    }
    if( ret != VLC_SUCCESS )
    {
        for( size_t i = 0; i < request->i_count; ++i )
            free( request->ppsz_paths[i] );
        free( request->ppsz_paths );
        request->ppsz_paths = NULL; request->i_count = 0;
    }
    return ret;
}

/* Resolve a virtual Media Library/iPod node to the real media paths stored in
 * PowerVLC's compact local index.  Dragging the node's file:// URI directly
 * would otherwise enqueue music-index.pvli itself as if it were audio. */
#define PVLC_DEVICE_INDEX_NODE UINT32_C(0x4e4f4445)
#define PVLC_DEVICE_INDEX_MEDIA UINT32_C(0x4d454449)
#define PVLC_DEVICE_INDEX_CHILD_NODE 1
#define PVLC_DEVICE_INDEX_CHILD_MEDIA 2
#define PVLC_DEVICE_INDEX_FLAG_RANDOM UINT32_C(0x01)

static int device_source_path_append( char ***paths, size_t *count,
                                      const char *path )
{
    if( path == NULL || !*path ) return VLC_EGENERIC;
    for( size_t i = 0; i < *count; ++i )
        if( !strcmp( (*paths)[i], path ) ) return VLC_SUCCESS;
    char *copy = strdup( path );
    char **grown = copy ? realloc( *paths, (*count + 1) * sizeof( *grown ) )
                        : NULL;
    if( grown == NULL ) { free( copy ); return VLC_ENOMEM; }
    *paths = grown; (*paths)[(*count)++] = copy;
    return VLC_SUCCESS;
}

static bool device_lazy_index_location( input_item_t *input, char **path,
                                        uint64_t *offset )
{
    *path = NULL; *offset = 0;
    if( input == NULL || !input_item_IsPowerVLCLazyIndex( input ) )
        return false;
    const char prefix[] = VLC_INPUT_OPTION_POWERVLC_INDEX_OFFSET_PREFIX;
    vlc_mutex_lock( &input->lock );
    for( int i = 0; i < input->i_options && *offset == 0; ++i )
        if( !strncmp( input->ppsz_options[i], prefix, sizeof( prefix ) - 1 ) )
            *offset = strtoull( input->ppsz_options[i]
                                + sizeof( prefix ) - 1, NULL, 10 );
    vlc_mutex_unlock( &input->lock );
    char *uri = input_item_GetURI( input );
    char *fragment = uri ? strchr( uri, '#' ) : NULL;
    if( fragment ) *fragment = '\0';
    *path = uri ? vlc_uri2path( uri ) : NULL;
    free( uri );
    if( *path == NULL || *offset == 0 )
    { free( *path ); *path = NULL; *offset = 0; return false; }
    return true;
}

static int device_resolve_index_node( FILE *file, uint64_t offset,
                                      char ***paths, size_t *count,
                                      unsigned depth )
{
    if( depth > 64 || offset > LONG_MAX
     || fseek( file, (long)offset, SEEK_SET ) != 0 ) return VLC_EGENERIC;
    uint32_t marker = 0, children = 0;
    int ret = pvlc_binary_read_u32( file, &marker );
    if( ret == VLC_SUCCESS && marker != PVLC_DEVICE_INDEX_NODE )
        ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &children );
    if( ret == VLC_SUCCESS && children > 1000000 ) ret = VLC_EGENERIC;
    for( uint32_t i = 0; i < children && ret == VLC_SUCCESS; ++i )
    {
        uint32_t type, flags, value, reserved; uint64_t child_offset;
        char *name = NULL;
        ret = pvlc_binary_read_u32( file, &type );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &flags );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &value );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &reserved );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file,
                                                              &child_offset );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &name,
                                                                 1024 * 1024 );
        long next = ftell( file );
        if( ret == VLC_SUCCESS && !(flags & PVLC_DEVICE_INDEX_FLAG_RANDOM) )
        {
            if( type == PVLC_DEVICE_INDEX_CHILD_NODE )
                ret = device_resolve_index_node( file, child_offset, paths,
                                                  count, depth + 1 );
            else if( type == PVLC_DEVICE_INDEX_CHILD_MEDIA )
            {
                if( child_offset > LONG_MAX
                 || fseek( file, (long)child_offset, SEEK_SET ) != 0 )
                    ret = VLC_EGENERIC;
                uint32_t media_marker = 0; char *uri = NULL;
                if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32(
                                                      file, &media_marker );
                if( ret == VLC_SUCCESS
                 && media_marker != PVLC_DEVICE_INDEX_MEDIA )
                    ret = VLC_EGENERIC;
                if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file,
                                            &uri, 16 * 1024 * 1024 );
                char *path = uri ? vlc_uri2path( uri ) : NULL;
                if( ret == VLC_SUCCESS ) ret = device_source_path_append(
                                                        paths, count, path );
                free( path ); free( uri );
            }
            else ret = VLC_EGENERIC;
        }
        if( ret == VLC_SUCCESS
         && (next < 0 || fseek( file, next, SEEK_SET ) != 0) )
            ret = VLC_EGENERIC;
        free( name ); VLC_UNUSED( value ); VLC_UNUSED( reserved );
    }
    return ret;
}

static int device_resolve_import( const services_discovery_import_t *request,
                                  char ***paths, size_t *count )
{
    *paths = NULL; *count = 0;
    if( request == NULL ) return VLC_EGENERIC;
    char *index_path = NULL; uint64_t offset = 0;
    if( request->p_item
     && input_item_IsPowerVLCRandomAction( request->p_item ) )
        return VLC_SUCCESS;
    if( request->p_item && device_lazy_index_location( request->p_item,
                                                &index_path, &offset ) )
    {
        FILE *file = vlc_fopen( index_path, "rb" ); free( index_path );
        if( file == NULL ) return VLC_EGENERIC;
        setvbuf( file, NULL, _IOFBF, 64 * 1024 );
        static const unsigned char magic[8] = {
            'P', 'V', 'L', 'C', 'L', 'I', 5, 0
        };
        unsigned char actual[sizeof( magic )];
        int ret = pvlc_binary_read( file, actual, sizeof( actual ) );
        if( ret == VLC_SUCCESS && memcmp( actual, magic, sizeof( magic ) ) )
            ret = VLC_EGENERIC;
        if( ret == VLC_SUCCESS ) ret = device_resolve_index_node( file,
                                             offset, paths, count, 0 );
        fclose( file ); return ret;
    }
    free( index_path );
    /* Never enqueue a compact index as media merely because an older UI did
     * not pass its input_item_t. It is safer to reject that drag visibly. */
    const char *extension = request->psz_path
                          ? strrchr( request->psz_path, '.' ) : NULL;
    if( extension && !strcasecmp( extension, ".pvli" ) ) return VLC_EGENERIC;
    return device_source_path_append( paths, count, request->psz_path );
}

static int device_queue_drop_locked( services_discovery_sys_t *sys,
                                     const char *path )
{
    for( size_t i = 0; i < sys->drop_count; ++i )
        if( !strcmp( sys->drop_paths[i], path ) ) return VLC_SUCCESS;
    char *copy = strdup( path );
    if( copy == NULL ) return VLC_ENOMEM;
    char **paths = realloc( sys->drop_paths,
                            (sys->drop_count + 1) * sizeof( *paths ) );
    if( paths == NULL ) { free( copy ); return VLC_ENOMEM; }
    sys->drop_paths = paths;
    uint64_t *transfers = realloc( sys->drop_transfers,
                         (sys->drop_count + 1) * sizeof( *transfers ) );
    if( transfers == NULL ) { free( copy ); return VLC_ENOMEM; }
    sys->drop_transfers = transfers;
    uint64_t id = transfer_begin_locked( sys, path, "", SD_TRANSFER_QUEUED );
    if( id == 0 ) { free( copy ); return VLC_ENOMEM; }
    sys->drop_paths[sys->drop_count] = copy;
    sys->drop_transfers[sys->drop_count++] = id;
    sys->transferring = true;
    return VLC_SUCCESS;
}

static int Control( services_discovery_t *sd, int query, va_list args )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( query == SD_CMD_DESCRIPTOR )
    {
        services_discovery_descriptor_t *d = va_arg( args,
                                            services_discovery_descriptor_t * );
        memset( d, 0, sizeof( *d ) ); return VLC_SUCCESS;
    }
    /* The UI lock is a safety affordance, not the consistency boundary.
     * Refuse every other device action at the service layer while a regular
     * filesystem deletion is walking the tree. Status polling remains
     * available so interfaces can observe completion and unlock themselves. */
    vlc_mutex_lock( &sys->lock );
    bool deleting = sys->activity == SD_DEVICE_DELETING;
    vlc_mutex_unlock( &sys->lock );
    if( deleting && query != SD_CMD_POWERVLC_DEVICE_TRANSFERS )
        return VLC_EGENERIC;
    if( query == SD_CMD_POWERVLC_DEVICE_ADD )
    {
        const services_discovery_import_t *request = va_arg( args,
                                             const services_discovery_import_t * );
        char **paths = NULL; size_t count = 0;
        int ret = device_resolve_import( request, &paths, &count );
        if( ret == VLC_SUCCESS && count == 0 ) ret = VLC_EGENERIC;
        vlc_mutex_lock( &sys->lock );
        size_t old_count = sys->drop_count;
        for( size_t i = 0; i < count && ret == VLC_SUCCESS; ++i )
            ret = device_queue_drop_locked( sys, paths[i] );
        /* A later allocation failure must not strand paths already accepted
         * by this batch in the queue. */
        if( sys->drop_count > old_count ) vlc_cond_signal( &sys->wait );
        vlc_mutex_unlock( &sys->lock );
        for( size_t i = 0; i < count; ++i ) free( paths[i] );
        free( paths ); return ret;
    }
#ifdef HAVE_LIBGPOD
    if( query == SD_CMD_POWERVLC_DEVICE_RESOLVE_DELETE )
    {
        services_discovery_device_delete_resolve_t *request = va_arg( args,
                         services_discovery_device_delete_resolve_t * );
        return !strcasecmp( sys->device.kind, "ipod" )
             ? ipod_resolve_delete_request( sd, request )
             : regular_resolve_delete_request( sd, request );
    }
    if( query == SD_CMD_POWERVLC_PLAYLIST_CREATE
     || query == SD_CMD_POWERVLC_PLAYLIST_RENAME
     || query == SD_CMD_POWERVLC_PLAYLIST_DELETE
     || query == SD_CMD_POWERVLC_PLAYLIST_DROP
     || query == SD_CMD_POWERVLC_PLAYLIST_REMOVE )
        return ipod_playlist_control( sd, query, args );
#endif
#ifndef HAVE_LIBGPOD
    if( query == SD_CMD_POWERVLC_DEVICE_RESOLVE_DELETE )
        return regular_resolve_delete_request( sd, va_arg( args,
                         services_discovery_device_delete_resolve_t * ) );
#endif
    vlc_mutex_lock( &sys->lock ); int ret = VLC_SUCCESS;
    if( query == SD_CMD_POWERVLC_RESCAN ) sys->refresh = true;
    else if( query == SD_CMD_POWERVLC_DEVICE_TRANSFERS )
    {
        services_discovery_transfer_status_t *status = va_arg( args,
                                   services_discovery_transfer_status_t * );
        if( status == NULL ) ret = VLC_EGENERIC;
        else
        {
            memset( status, 0, sizeof( *status ) );
            status->b_synchronizing = sys->transferring;
            status->b_pending_changes = sys->pending_changes;
            status->b_commit_failed = sys->commit_failed;
            status->i_activity = sys->activity;
            status->i_total_bytes = sys->total_bytes;
            status->i_free_bytes = sys->free_bytes;
            if( sys->transfer_count )
                status->p_items = calloc( sys->transfer_count,
                                           sizeof( *status->p_items ) );
            if( sys->transfer_count && status->p_items == NULL )
                ret = VLC_ENOMEM;
            else
            {
                status->i_count = sys->transfer_count;
                for( size_t i = 0; i < status->i_count; ++i )
                {
                    status->p_items[i] = sys->transfers[i];
                    status->p_items[i].psz_source =
                        strdup( sys->transfers[i].psz_source );
                    status->p_items[i].psz_destination =
                        strdup( sys->transfers[i].psz_destination );
                    if( status->p_items[i].psz_source == NULL
                     || status->p_items[i].psz_destination == NULL )
                    {
                        for( size_t j = 0; j <= i; ++j )
                        { free( status->p_items[j].psz_source );
                          free( status->p_items[j].psz_destination ); }
                        free( status->p_items );
                        memset( status, 0, sizeof( *status ) );
                        ret = VLC_ENOMEM; break;
                    }
                }
            }
        }
    }
    else if( query == SD_CMD_POWERVLC_DEVICE_CANCEL_TRANSFER )
    {
        const services_discovery_transfer_cancel_t *request = va_arg( args,
                                  const services_discovery_transfer_cancel_t * );
        ret = VLC_EGENERIC;
        for( size_t i = 0; request && i < sys->transfer_count; ++i )
            if( sys->transfers[i].i_id == request->i_id
             && sys->transfers[i].i_stage != SD_TRANSFER_COMPLETED
             && sys->transfers[i].i_stage != SD_TRANSFER_FAILED
             && sys->transfers[i].i_stage != SD_TRANSFER_CANCELLED )
            {
                sys->transfers[i].b_cancel_requested = true;
                if( sys->transfers[i].i_stage == SD_TRANSFER_QUEUED )
                    sys->transfers[i].i_stage = SD_TRANSFER_CANCELLED;
                ret = VLC_SUCCESS;
                break;
            }
    }
    else if( query == SD_CMD_POWERVLC_DEVICE_CANCEL_ALL )
    {
        for( size_t i = 0; i < sys->transfer_count; ++i )
            if( sys->transfers[i].i_stage != SD_TRANSFER_COMPLETED
             && sys->transfers[i].i_stage != SD_TRANSFER_FAILED
             && sys->transfers[i].i_stage != SD_TRANSFER_CANCELLED )
            {
                sys->transfers[i].b_cancel_requested = true;
                if( sys->transfers[i].i_stage == SD_TRANSFER_QUEUED )
                    sys->transfers[i].i_stage = SD_TRANSFER_CANCELLED;
            }
    }
    else if( query == SD_CMD_POWERVLC_DEVICE_COMMIT )
    {
#ifdef HAVE_LIBGPOD
        if( strcasecmp( sys->device.kind, "ipod" )
         || (!sys->pending_changes && !sys->transferring
                                  && sys->drop_count == 0) )
            ret = VLC_EGENERIC;
        else
        {
            const bool transfer_active = sys->transferring
                                      || sys->drop_count > 0;
            struct stat st;
            /* A click from a context menu opened just before the transfer
             * started can still arrive while the menu item is visually
             * disabled. In that case this control call must be a pure queue
             * operation: do not probe the slow device or touch iTunesDB/UI
             * state from the caller's thread. The worker validates and writes
             * the device only after the complete transfer batch has drained. */
            if( !transfer_active
             && (vlc_stat( sys->device.path, &st ) != 0
              || !S_ISDIR( st.st_mode )) )
            {
                /* Do not pretend that an asynchronous validation was queued
                 * after the player disappeared. Keep all edits retryable and
                 * expose the failure through the regular status polling. */
                sys->commit_failed = true;
                ret = VLC_EGENERIC;
            }
            else
            {
                sys->commit_failed = false;
                sys->commit_request = true;
                /* While copies are active, retain their progress label and
                 * queue finalization behind every current transfer. */
                if( !transfer_active )
                    sys->activity = SD_DEVICE_UPDATING_ITUNESDB;
            }
        }
#else
        ret = VLC_EGENERIC;
#endif
    }
    else if( query == SD_CMD_POWERVLC_DEVICE_DISCARD )
    {
#ifdef HAVE_LIBGPOD
        if( strcasecmp( sys->device.kind, "ipod" ) || !sys->pending_changes )
            ret = VLC_EGENERIC;
        else sys->discard_request = true;
#else
        ret = VLC_EGENERIC;
#endif
    }
    else if( query == SD_CMD_POWERVLC_DEVICE_DELETE )
    {
        const services_discovery_device_delete_t *request = va_arg( args,
                                  const services_discovery_device_delete_t * );
        size_t old_count = sys->delete_count;
        size_t old_item_count = sys->delete_item_count;
        if( request == NULL || request->i_count == 0 ) ret = VLC_EGENERIC;
        if( ret == VLC_SUCCESS && request->i_item_count > 0
         && request->p_item_ids == NULL ) ret = VLC_EGENERIC;
        if( ret == VLC_SUCCESS && request->i_item_count > 0 )
        {
            int *grown = realloc( sys->delete_item_ids,
                (old_item_count + request->i_item_count) * sizeof( *grown ) );
            if( grown == NULL ) ret = VLC_ENOMEM;
            else sys->delete_item_ids = grown;
        }
        for( size_t i = 0; ret == VLC_SUCCESS && i < request->i_count; ++i )
        {
            const char *path = request->ppsz_paths[i];
            if( path == NULL || !path_has_device_prefix( sys->device.path, path ) )
            { ret = VLC_EGENERIC; break; }
            char *copy = strdup( path );
            char **grown = copy ? realloc( sys->delete_paths,
                    (sys->delete_count + 1) * sizeof( *grown ) ) : NULL;
            if( grown == NULL ) { free( copy ); ret = VLC_ENOMEM; break; }
            sys->delete_paths = grown;
            sys->delete_paths[sys->delete_count++] = copy;
        }
        if( ret != VLC_SUCCESS )
        {
            while( sys->delete_count > old_count )
                free( sys->delete_paths[--sys->delete_count] );
        }
        else if( request->i_item_count > 0 )
        {
            memcpy( sys->delete_item_ids + old_item_count,
                    request->p_item_ids,
                    request->i_item_count * sizeof( *request->p_item_ids ) );
            sys->delete_item_count += request->i_item_count;
        }
        if( ret == VLC_SUCCESS )
            /* Publish the busy state before the worker wakes up. Interfaces
             * can therefore lock the device view immediately after the
             * confirmation dialog, including during the short batch window. */
            sys->activity = SD_DEVICE_DELETING;
    }
    else if( query == SD_CMD_POWERVLC_DEVICE_BACKUP )
    {
        const char *path = va_arg( args, const char * );
        if( !path ) ret = VLC_EGENERIC;
        else { free( sys->backup_request ); sys->backup_request = strdup( path );
               if( !sys->backup_request ) ret = VLC_ENOMEM; }
    }
    else ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS && query != SD_CMD_POWERVLC_DEVICE_TRANSFERS )
        vlc_cond_signal( &sys->wait );
    vlc_mutex_unlock( &sys->lock ); return ret;
}

static int Open( vlc_object_t *obj )
{
    services_discovery_t *sd = (services_discovery_t *)obj;
    config_ChainParse( sd, CFG_PREFIX, options, sd->p_cfg );
    int64_t index = var_InheritInteger( sd, CFG_PREFIX "index" );
    if( index < 0 ) return VLC_EGENERIC;
    services_discovery_sys_t *sys = calloc( 1, sizeof( *sys ) );
    if( !sys ) return VLC_ENOMEM;
    if( device_at_index( obj, (size_t)index, &sys->device ) != VLC_SUCCESS )
    { free( sys ); return VLC_EGENERIC; }
#ifndef HAVE_LIBGPOD
    if( !strcasecmp( sys->device.kind, "ipod" ) )
    {
        msg_Err( sd, "this build has no libgpod Apple iPod support" );
        device_clear( &sys->device ); free( sys ); return VLC_EGENERIC;
    }
#endif
    sd->p_sys = sys; sd->description = sys->device.name; sd->pf_control = Control;
    vlc_mutex_init( &sys->lock ); vlc_cond_init( &sys->wait );
    if( vlc_clone( &sys->thread, Run, sd, VLC_THREAD_PRIORITY_LOW ) )
    { vlc_cond_destroy( &sys->wait ); vlc_mutex_destroy( &sys->lock );
      device_clear( &sys->device ); free( sys ); return VLC_EGENERIC; }
    return VLC_SUCCESS;
}

static void Close( vlc_object_t *obj )
{
    services_discovery_t *sd = (services_discovery_t *)obj;
    services_discovery_sys_t *sys = sd->p_sys;
    vlc_mutex_lock( &sys->lock ); sys->stop = true; vlc_cond_signal( &sys->wait );
    vlc_mutex_unlock( &sys->lock );
    /* Do not make application termination wait for a disconnected target,
     * an in-progress large copy, or a transcoder that cannot make progress. */
    vlc_cancel( sys->thread );
    vlc_join( sys->thread, NULL );
#ifdef HAVE_LIBGPOD
    if( sys->ipod_session_additions )
        input_item_Release( sys->ipod_session_additions );
#endif
    for( size_t i = 0; i < sys->visible_root_count; ++i )
        input_item_Release( sys->visible_roots[i] );
    for( size_t i = 0; i < sys->drop_count; ++i ) free( sys->drop_paths[i] );
    free( sys->drop_paths );
    free( sys->drop_transfers );
    for( size_t i = 0; i < sys->delete_count; ++i ) free( sys->delete_paths[i] );
    free( sys->delete_paths );
    free( sys->delete_item_ids );
    for( size_t i = 0; i < sys->transfer_count; ++i )
        transfer_item_clear( &sys->transfers[i] );
    free( sys->transfers );
#ifdef HAVE_LIBGPOD
    ipod_clear_path_list( &sys->pending_ipod_additions,
                          &sys->pending_ipod_addition_count, true );
    ipod_clear_path_list( &sys->pending_ipod_deletions,
                          &sys->pending_ipod_deletion_count, false );
    if( sys->ipod_track_ids )
        itdb_track_id_tree_destroy( sys->ipod_track_ids );
    if( sys->ipod_database ) itdb_free( sys->ipod_database );
    if( sys->ipod_playlist_offsets )
        g_hash_table_destroy( sys->ipod_playlist_offsets );
    free( sys->ipod_index_path );
#endif
    free( sys->backup_request ); device_clear( &sys->device );
    vlc_cond_destroy( &sys->wait ); vlc_mutex_destroy( &sys->lock ); free( sys );
}
