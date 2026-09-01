/*****************************************************************************
 * powervlc_medialibrary.c: lightweight PowerVLC media-library discovery
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#define VLC_MODULE_LICENSE VLC_LICENSE_GPL_2_PLUS
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_configuration.h>
#include <vlc_charset.h>
#include <vlc_fs.h>
#include <vlc_input_item.h>
#include <vlc_playlist.h>
#include <vlc_services_discovery.h>
#include <vlc_strings.h>
#include <vlc_url.h>

#include "powervlc_media_common.h"

#include <ctype.h>
#include <inttypes.h>
#include <limits.h>
#include <sys/stat.h>
#ifndef _WIN32
# include <unistd.h>
#endif

typedef struct
{
    char *psz_path;
    bool b_monitor;
    bool b_database;
} pvlc_folder_t;

typedef struct
{
    char *psz_field;
    char *psz_operator;
    char *psz_value;
} pvlc_rule_t;

typedef struct
{
    char *psz_name;
    bool b_match_all;
    size_t i_limit;
    pvlc_rule_t *p_rules;
    size_t i_rule_count;
} pvlc_smart_playlist_t;

typedef struct
{
    size_t *p_indices;
    size_t i_count;
    size_t i_capacity;
} pvlc_smart_result_t;

typedef struct
{
    char *psz_path;
    char *psz_title;
    char *psz_artist;
    char *psz_album;
    input_item_t *p_item;
} pvlc_import_request_t;

typedef struct
{
    size_t i_unsupported;
    size_t i_hidden;
    size_t i_unavailable;
    size_t i_unreadable_directories;
} pvlc_scan_report_summary_t;

/* The complete cache is needed only while the persistent lazy tree is being
 * rebuilt.  Keeping it afterwards used one allocation per metadata field and
 * quickly exhausted old 32-bit Macs.  Search keeps just the eight strings it
 * can actually expose, all packed into one arena. */
typedef struct
{
    const char *psz_search;
    const char *psz_title;
    const char *psz_artist;
    const char *psz_album;
    const char *psz_album_artist;
    const char *psz_genre;
    const char *psz_composer;
    const char *psz_year;
    uint8_t i_rating;
} pvlc_search_entry_t;

typedef struct
{
    pvlc_search_entry_t *p_entries;
    char *p_strings;
    size_t i_count;
} pvlc_search_catalog_t;

static void pvlc_search_catalog_clear( pvlc_search_catalog_t *catalog )
{
    free( catalog->p_entries );
    free( catalog->p_strings );
    memset( catalog, 0, sizeof( *catalog ) );
}

typedef struct
{
    libvlc_int_t *p_libvlc;
    uint64_t i_base;
    uint64_t i_total;
    unsigned i_last_percent;
    uint64_t i_last_done;
    vlc_tick_t i_last_publish;
    vlc_object_t *p_obj;
    const char *psz_root;
    const char *psz_checkpoint;
    pvlc_media_catalog_t *p_catalog;
    uint64_t i_checkpoint_done;
    size_t i_checkpoint_entries;
    vlc_tick_t i_last_checkpoint;
} pvlc_scan_ui_t;

static unsigned pvlc_scan_percent( uint64_t i_done, uint64_t i_total )
{
    if( i_total == 0 ) return 100;
    if( i_done >= i_total ) return 100;
    return (unsigned)((double)i_done * 100.0 / (double)i_total);
}

static void pvlc_scan_publish( libvlc_int_t *p_libvlc, bool b_active,
                               uint64_t i_done, uint64_t i_total )
{
    var_SetInteger( p_libvlc, PVLC_ML_SCAN_DONE, (int64_t)i_done );
    var_SetInteger( p_libvlc, PVLC_ML_SCAN_TOTAL, (int64_t)i_total );
    var_SetBool( p_libvlc, PVLC_ML_SCAN_ACTIVE, b_active );
    var_IncInteger( p_libvlc, PVLC_ML_SCAN_REVISION );
}

static void pvlc_scan_ui_progress( void *p_opaque, uint64_t i_done,
                                   uint64_t i_folder_total )
{
    (void)i_folder_total;
    pvlc_scan_ui_t *p = p_opaque;
    uint64_t i_global_done = p->i_base + i_done;
    vlc_tick_t now = mdate();
    if( p->psz_checkpoint && p->p_catalog
     && (i_done == 1 || i_done - p->i_checkpoint_done >= 100
      || now - p->i_last_checkpoint >= 120 * CLOCK_FREQ) )
    {
        /* Append only the last hundred records. Rewriting the whole growing
         * catalogue here made checkpoint cost quadratic and explained the
         * pronounced slowdown after the first thousand tracks. */
        if( pvlc_append_resume_cache_at( p->p_obj, p->psz_root,
                        p->psz_checkpoint, p->p_catalog,
                        p->i_checkpoint_entries ) == VLC_SUCCESS )
        {
            p->i_checkpoint_done = i_done;
            p->i_checkpoint_entries = p->p_catalog->i_count;
        }
        p->i_last_checkpoint = now;
    }
    if( p->i_total == 0 )
    {
        /* The total is deliberately unknown: counting every file first would
         * traverse a slow source twice. Publish a useful running count at a
         * bounded rate while the single real scan advances. */
        if( i_global_done == 1 || now - p->i_last_publish >= CLOCK_FREQ )
        {
            p->i_last_done = i_global_done;
            p->i_last_publish = now;
            pvlc_scan_publish( p->p_libvlc, true, i_global_done, 0 );
        }
        return;
    }
    unsigned i_percent = pvlc_scan_percent( i_global_done, p->i_total );
    /* Metadata callbacks may arrive for tens of thousands of tracks. The UI
     * only renders an integer percentage, so wake it at most 101 times. */
    if( i_percent != p->i_last_percent || i_global_done >= p->i_total )
    {
        p->i_last_percent = i_percent;
        pvlc_scan_publish( p->p_libvlc, true, i_global_done, p->i_total );
    }
}

struct services_discovery_sys_t
{
    vlc_thread_t thread;
    vlc_mutex_t lock;
    vlc_cond_t wait;
    bool b_stop;
    bool b_force_rescan;
    bool b_rating_refresh;
    bool b_smart_refresh;

    pvlc_import_request_t *p_imports;
    size_t i_import_count;

    input_item_t *pp_roots[5];
    input_item_t *p_rating_node;
    uint64_t i_visible_fingerprint;
    uint64_t i_visible_definitions;
    pvlc_scan_report_summary_t visible_scan_report;
    pvlc_search_catalog_t search_catalog;
};

static int Open( vlc_object_t * );
static void Close( vlc_object_t * );
static int Control( services_discovery_t *, int, va_list );
static void *Run( void * );
static int vlc_sd_probe_Open( vlc_object_t * );

vlc_module_begin()
    set_shortname( N_("Media Library") )
    set_description( N_("PowerVLC lightweight media library") )
    set_category( CAT_PLAYLIST )
    set_subcategory( SUBCAT_PLAYLIST_SD )
    set_capability( "services_discovery", 0 )
    set_callbacks( Open, Close )
    add_shortcut( "powervlc_library" )

    VLC_SD_PROBE_SUBMODULE
vlc_module_end()

static int vlc_sd_probe_Open( vlc_object_t *p_obj )
{
    return vlc_sd_probe_Add( (vlc_probe_t *)p_obj, "powervlc_library",
                             N_("Media Library"), SD_CAT_MYCOMPUTER );
}

static uint64_t pvlc_hash_string( uint64_t hash, const char *psz )
{
    if( psz == NULL ) return hash;
    while( *psz )
    {
        hash ^= (unsigned char)*psz++;
        hash *= UINT64_C(1099511628211);
    }
    return hash;
}

/* A folder can either carry its portable cache beside the media or keep it in
 * the managed library.  The latter is essential for removable/network roots:
 * their catalogue remains browsable while the volume is temporarily absent. */
static char *pvlc_folder_database_path( vlc_object_t *obj,
                                        const pvlc_folder_t *folder )
{
    if( folder->b_database )
    {
        char *shared = pvlc_path_join( folder->psz_path,
                                      ".powervlcmediafolder.db" );
        /* A read-only NAS mounted as guest cannot host its requested shared
         * cache. Keep using an existing shared database when readable, but
         * otherwise fall back to the managed local cache so startup never
         * depends on rescanning the network volume. */
        bool writable = true;
#ifndef _WIN32
        writable = access( folder->psz_path, W_OK ) == 0;
#endif
        if( shared && (pvlc_folder_cache_available_at( shared ) || writable) )
            return shared;
        free( shared );
    }

    char *managed = pvlc_managed_folder( obj );
    char *directory = managed ? pvlc_path_join( managed, ".powervlc-cache" )
                              : NULL;
    free( managed );
    if( directory == NULL || pvlc_mkdir_parents( directory ) != VLC_SUCCESS )
    { free( directory ); return NULL; }
    uint64_t hash = pvlc_hash_string( UINT64_C(1469598103934665603),
                                      folder->psz_path );
    char name[40];
    snprintf( name, sizeof( name ), "%016" PRIx64 ".db", hash );
    char *path = pvlc_path_join( directory, name );
    free( directory );
    return path;
}

static char *pvlc_folder_checkpoint_path( vlc_object_t *obj,
                                          const pvlc_folder_t *folder )
{
    /* Resume data always belongs to the managed local cache. A partial file
     * must never masquerade as the authoritative shared database, and saving
     * progress must not add writes to the removable/network source. */
    char *managed = pvlc_managed_folder( obj );
    char *directory = managed ? pvlc_path_join( managed, ".powervlc-cache" )
                              : NULL;
    free( managed );
    if( directory == NULL || pvlc_mkdir_parents( directory ) != VLC_SUCCESS )
    { free( directory ); return NULL; }
    uint64_t hash = pvlc_hash_string( UINT64_C(1469598103934665603),
                                      folder->psz_path );
    char name[48];
    snprintf( name, sizeof( name ), "%016" PRIx64 ".resume.db", hash );
    char *path = pvlc_path_join( directory, name );
    free( directory );
    return path;
}

static char *pvlc_folder_scan_report_path( vlc_object_t *obj,
                                           const pvlc_folder_t *folder )
{
    char *managed = pvlc_managed_folder( obj );
    char *directory = managed ? pvlc_path_join( managed, ".powervlc-cache" )
                              : NULL;
    free( managed );
    if( directory == NULL || pvlc_mkdir_parents( directory ) != VLC_SUCCESS )
    { free( directory ); return NULL; }
    uint64_t hash = pvlc_hash_string( UINT64_C(1469598103934665603),
                                      folder->psz_path );
    char name[52];
    snprintf( name, sizeof( name ), "%016" PRIx64 ".scan-report.tsv", hash );
    char *path = pvlc_path_join( directory, name );
    free( directory );
    return path;
}

static void pvlc_scan_report_load_summary(
                        const char *psz_path, pvlc_scan_report_summary_t *p )
{
    FILE *file = psz_path ? vlc_fopen( psz_path, "rb" ) : NULL;
    if( file == NULL ) return;
    char line[8192];
    while( fgets( line, sizeof( line ), file ) != NULL )
    {
        char *tab = strchr( line, '\t' );
        if( tab ) *tab = '\0';
        if( !strcmp( line, "unsupported" ) ) p->i_unsupported++;
        else if( !strcmp( line, "hidden" ) ) p->i_hidden++;
        else if( !strcmp( line, "unavailable" ) ) p->i_unavailable++;
        else if( !strcmp( line, "unreadable-directory" ) )
            p->i_unreadable_directories++;
    }
    fclose( file );
}

static char *pvlc_field( char **ppsz )
{
    if( ppsz == NULL || *ppsz == NULL ) return NULL;
    char *field = *ppsz;
    char *tab = strchr( field, '\t' );
    if( tab ) { *tab = '\0'; *ppsz = tab + 1; }
    else *ppsz = NULL;
    return field;
}

static void pvlc_folder_clear( pvlc_folder_t *p_folder )
{
    free( p_folder->psz_path );
}

static bool pvlc_same_path( const char *a, const char *b )
{
#ifdef _WIN32
    return !strcasecmp( a, b );
#else
    return !strcmp( a, b );
#endif
}

static int pvlc_folder_append( pvlc_folder_t **pp_folders, size_t *pi_count,
                               const char *psz_path, bool b_monitor,
                               bool b_database )
{
    if( psz_path == NULL || *psz_path == '\0' ) return VLC_SUCCESS;
    for( size_t i = 0; i < *pi_count; ++i )
        if( pvlc_same_path( (*pp_folders)[i].psz_path, psz_path ) )
            return VLC_SUCCESS;
    pvlc_folder_t *p = realloc( *pp_folders,
                                (*pi_count + 1) * sizeof( *p ) );
    if( p == NULL ) return VLC_ENOMEM;
    *pp_folders = p;
    p[*pi_count].psz_path = strdup( psz_path );
    p[*pi_count].b_monitor = b_monitor;
    p[*pi_count].b_database = b_database;
    if( p[*pi_count].psz_path == NULL ) return VLC_ENOMEM;
    (*pi_count)++;
    return VLC_SUCCESS;
}

static int pvlc_load_folders( vlc_object_t *p_obj, pvlc_folder_t **pp_folders,
                              size_t *pi_count )
{
    *pp_folders = NULL; *pi_count = 0;
    char *managed = pvlc_managed_folder( p_obj );
    char *managed_music = managed ? pvlc_path_join( managed, "Music" ) : NULL;
    int ret = pvlc_folder_append( pp_folders, pi_count, managed_music,
                                  true, true );
    free( managed_music );
    free( managed );
    if( ret != VLC_SUCCESS ) return ret;

    char *config = var_InheritString( p_obj, "powervlc-ml-folders" );
    if( config == NULL ) return VLC_SUCCESS;
    char *save_line = NULL;
    for( char *line = strtok_r( config, "\n", &save_line ); line != NULL;
         line = strtok_r( NULL, "\n", &save_line ) )
    {
        char *cursor = line;
        char *flags = pvlc_field( &cursor );
        char *encoded = pvlc_field( &cursor );
        char *path = pvlc_unescape( encoded ? encoded : "" );
        if( path == NULL ) { ret = VLC_ENOMEM; break; }
        ret = pvlc_folder_append( pp_folders, pi_count, path,
                                  flags && strchr( flags, 'm' ),
                                  flags && strchr( flags, 'd' ) );
        free( path );
        if( ret != VLC_SUCCESS ) break;
    }
    free( config );
    return ret;
}

static void pvlc_rule_clear( pvlc_rule_t *p_rule )
{
    free( p_rule->psz_field ); free( p_rule->psz_operator );
    free( p_rule->psz_value );
}

static void pvlc_smart_clear( pvlc_smart_playlist_t *p_smart )
{
    free( p_smart->psz_name );
    for( size_t i = 0; i < p_smart->i_rule_count; ++i )
        pvlc_rule_clear( &p_smart->p_rules[i] );
    free( p_smart->p_rules );
}

static int pvlc_smart_add_rule( pvlc_smart_playlist_t *p_smart,
                                const char *field, const char *op,
                                const char *value )
{
    pvlc_rule_t *p = realloc( p_smart->p_rules,
        (p_smart->i_rule_count + 1) * sizeof( *p ) );
    if( p == NULL ) return VLC_ENOMEM;
    p_smart->p_rules = p;
    pvlc_rule_t *r = &p[p_smart->i_rule_count];
    r->psz_field = pvlc_unescape( field );
    r->psz_operator = pvlc_unescape( op );
    r->psz_value = pvlc_unescape( value );
    if( r->psz_field == NULL || r->psz_operator == NULL || r->psz_value == NULL )
    { pvlc_rule_clear( r ); return VLC_ENOMEM; }
    p_smart->i_rule_count++;
    return VLC_SUCCESS;
}

static int pvlc_load_smart_playlists( vlc_object_t *p_obj,
                                      pvlc_smart_playlist_t **pp_smart,
                                      size_t *pi_count, uint64_t *pi_hash )
{
    *pp_smart = NULL; *pi_count = 0;
    /* Preferences can change while the discovery module is alive. Reading
     * the configuration directly avoids retaining the inherited startup
     * value in an object variable. */
    char *config = config_GetPsz( p_obj, "powervlc-ml-smart-playlists" );
    *pi_hash = pvlc_hash_string( UINT64_C(1469598103934665603), config );
    if( config == NULL || *config == '\0' ) { free( config ); return VLC_SUCCESS; }
    int ret = VLC_SUCCESS;
    char *save_line = NULL;
    for( char *line = strtok_r( config, "\n", &save_line ); line != NULL;
         line = strtok_r( NULL, "\n", &save_line ) )
    {
        char *cursor = line;
        char *name = pvlc_field( &cursor );
        char *match = pvlc_field( &cursor );
        char *limit = pvlc_field( &cursor );
        char *rules = pvlc_field( &cursor );
        if( name == NULL || match == NULL || limit == NULL || rules == NULL )
            continue;
        pvlc_smart_playlist_t *p = realloc( *pp_smart,
                                   (*pi_count + 1) * sizeof( *p ) );
        if( p == NULL ) { ret = VLC_ENOMEM; break; }
        *pp_smart = p;
        pvlc_smart_playlist_t *s = &p[*pi_count];
        memset( s, 0, sizeof( *s ) );
        s->psz_name = pvlc_unescape( name );
        s->b_match_all = strcmp( match, "any" ) != 0;
        s->i_limit = (size_t)strtoull( limit, NULL, 10 );
        if( s->psz_name == NULL ) { ret = VLC_ENOMEM; break; }
        char *save_rule = NULL;
        for( char *rule = strtok_r( rules, ";", &save_rule ); rule != NULL;
             rule = strtok_r( NULL, ";", &save_rule ) )
        {
            char *rcursor = rule;
            char *field = strsep( &rcursor, "|" );
            char *op = strsep( &rcursor, "|" );
            char *value = rcursor;
            if( field && op && value )
                ret = pvlc_smart_add_rule( s, field, op, value );
            if( ret != VLC_SUCCESS ) break;
        }
        if( ret != VLC_SUCCESS ) { pvlc_smart_clear( s ); break; }
        (*pi_count)++;
    }
    free( config );
    return ret;
}

static bool pvlc_text_match( const char *text, const char *op,
                             const char *value )
{
    text = text ? text : ""; value = value ? value : "";
    if( !strcmp( op, "contains" ) ) return strcasestr( text, value ) != NULL;
    if( !strcmp( op, "not_contains" ) ) return strcasestr( text, value ) == NULL;
    if( !strcmp( op, "is" ) ) return !strcasecmp( text, value );
    if( !strcmp( op, "is_not" ) ) return strcasecmp( text, value ) != 0;
    if( !strcmp( op, "starts_with" ) )
        return !strncasecmp( text, value, strlen( value ) );
    if( !strcmp( op, "ends_with" ) )
    {
        size_t a = strlen( text ), b = strlen( value );
        return a >= b && !strcasecmp( text + a - b, value );
    }
    return false;
}

static bool pvlc_match_rule( const pvlc_media_entry_t *e,
                             const pvlc_rule_t *r )
{
    if( !strcmp( r->psz_field, "title" ) )
        return pvlc_text_match( e->psz_title, r->psz_operator, r->psz_value );
    if( !strcmp( r->psz_field, "artist" ) )
        return pvlc_text_match( e->psz_artist, r->psz_operator, r->psz_value );
    if( !strcmp( r->psz_field, "album" ) )
        return pvlc_text_match( e->psz_album, r->psz_operator, r->psz_value );
    if( !strcmp( r->psz_field, "path" ) )
        return pvlc_text_match( e->psz_path, r->psz_operator, r->psz_value );
    if( !strcmp( r->psz_field, "type" ) )
    {
        char *show = NULL;
        bool series = e->i_type == PVLC_MEDIA_VIDEO
                   && pvlc_series_info( e->psz_path, &show, NULL, NULL );
        free( show );
        const char *type = e->i_type == PVLC_MEDIA_AUDIO ? "music"
                         : series ? "show" : "movie";
        return pvlc_text_match( type, r->psz_operator, r->psz_value );
    }
    if( !strcmp( r->psz_field, "size" ) )
    {
        uint64_t value = strtoull( r->psz_value, NULL, 10 );
        return !strcmp( r->psz_operator, "greater" ) ? e->i_size > value
             : !strcmp( r->psz_operator, "less" ) ? e->i_size < value
             : e->i_size == value;
    }
    if( !strcmp( r->psz_field, "modified" ) )
    {
        int64_t value = strtoll( r->psz_value, NULL, 10 );
        return !strcmp( r->psz_operator, "after" ) ? e->i_mtime > value
             : !strcmp( r->psz_operator, "before" ) ? e->i_mtime < value
             : e->i_mtime == value;
    }
    if( !strcmp( r->psz_field, "rating" ) )
    {
        unsigned value = (unsigned)strtoul( r->psz_value, NULL, 10 );
        return !strcmp( r->psz_operator, "greater" ) ? e->i_rating > value
             : !strcmp( r->psz_operator, "less" ) ? e->i_rating < value
             : !strcmp( r->psz_operator, "is_not" ) ? e->i_rating != value
             : e->i_rating == value;
    }
    return false;
}

static int pvlc_result_append( pvlc_smart_result_t *r, size_t index )
{
    if( r->i_count == r->i_capacity )
    {
        size_t cap = r->i_capacity ? r->i_capacity * 2 : 64;
        size_t *p = realloc( r->p_indices, cap * sizeof( *p ) );
        if( p == NULL ) return VLC_ENOMEM;
        r->p_indices = p; r->i_capacity = cap;
    }
    r->p_indices[r->i_count++] = index;
    return VLC_SUCCESS;
}

static int pvlc_compute_smart( const pvlc_media_catalog_t *catalog,
                               const pvlc_smart_playlist_t *smart,
                               size_t count, pvlc_smart_result_t **pp_results )
{
    pvlc_smart_result_t *results = calloc( count, sizeof( *results ) );
    if( count && results == NULL ) return VLC_ENOMEM;
    for( size_t s = 0; s < count; ++s )
    {
        for( size_t i = 0; i < catalog->i_count; ++i )
        {
            bool matched = smart[s].b_match_all;
            if( smart[s].i_rule_count == 0 ) matched = true;
            for( size_t r = 0; r < smart[s].i_rule_count; ++r )
            {
                bool one = pvlc_match_rule( &catalog->p_entries[i],
                                            &smart[s].p_rules[r] );
                if( smart[s].b_match_all ) { if( !one ) { matched = false; break; } }
                else if( one ) { matched = true; break; }
            }
            if( matched && pvlc_result_append( &results[s], i ) != VLC_SUCCESS )
                goto error;
            if( smart[s].i_limit && results[s].i_count >= smart[s].i_limit )
                break;
        }
    }
    *pp_results = results;
    return VLC_SUCCESS;
error:
    for( size_t i = 0; i < count; ++i ) free( results[i].p_indices );
    free( results );
    return VLC_ENOMEM;
}

static char *pvlc_smart_db_path( void )
{
    char *data = config_GetUserDir( VLC_DATA_DIR );
    if( data == NULL ) return NULL;
    pvlc_mkdir_parents( data );
    char *path = pvlc_path_join( data, "powervlc-smart-playlists.db" );
    free( data ); return path;
}

static const unsigned char pvlc_smart_magic[8] = {
    'P', 'V', 'L', 'C', 'S', 'M', 3, 0
};

static int pvlc_load_smart_cache( const pvlc_media_catalog_t *catalog,
                                  const pvlc_smart_playlist_t *smart,
                                  size_t count, uint64_t definitions,
                                  pvlc_smart_result_t **pp_results )
{
    char *path = pvlc_smart_db_path();
    FILE *f = path ? vlc_fopen( path, "rb" ) : NULL;
    free( path );
    if( f == NULL ) return VLC_EGENERIC;
    setvbuf( f, NULL, _IOFBF, 64 * 1024 );
    unsigned char magic[sizeof( pvlc_smart_magic )];
    uint64_t fp, defs;
    uint32_t stored_count;
    if( pvlc_binary_read( f, magic, sizeof( magic ) ) != VLC_SUCCESS
     || memcmp( magic, pvlc_smart_magic, sizeof( magic ) )
     || pvlc_binary_read_u64( f, &fp ) != VLC_SUCCESS
     || pvlc_binary_read_u64( f, &defs ) != VLC_SUCCESS
     || pvlc_binary_read_u32( f, &stored_count ) != VLC_SUCCESS
     || fp != catalog->i_fingerprint || defs != definitions
     || stored_count != count )
    { fclose( f ); return VLC_EGENERIC; }
    pvlc_smart_result_t *results = calloc( count, sizeof( *results ) );
    if( count && results == NULL ) { fclose( f ); return VLC_ENOMEM; }
    for( size_t s = 0; s < count; ++s )
    {
        char *name = NULL;
        uint32_t item_count;
        if( pvlc_binary_read_string( f, &name, 1024 * 1024 ) != VLC_SUCCESS
         || strcmp( name, smart[s].psz_name )
         || pvlc_binary_read_u32( f, &item_count ) != VLC_SUCCESS
         || item_count > catalog->i_count )
        {
            free( name );
            goto bad_results;
        }
        free( name );
        if( item_count )
        {
            results[s].p_indices = malloc( (size_t)item_count
                                           * sizeof( *results[s].p_indices ) );
            if( results[s].p_indices == NULL ) goto bad_results;
            results[s].i_capacity = results[s].i_count = item_count;
        }
        for( uint32_t i = 0; i < item_count; ++i )
        {
            uint32_t index;
            if( pvlc_binary_read_u32( f, &index ) != VLC_SUCCESS
             || index >= catalog->i_count ) goto bad_results;
            results[s].p_indices[i] = index;
        }
    }
    fclose( f );
    *pp_results = results;
    return VLC_SUCCESS;
bad_results:
    fclose( f );
    for( size_t i = 0; i < count; ++i ) free( results[i].p_indices );
    free( results );
    return VLC_EGENERIC;
}

static void pvlc_save_smart_cache( const pvlc_media_catalog_t *catalog,
                                   const pvlc_smart_playlist_t *smart,
                                   size_t count, uint64_t definitions,
                                   const pvlc_smart_result_t *results )
{
    if( count > UINT32_MAX || catalog->i_count > UINT32_MAX ) return;
    char *path = pvlc_smart_db_path();
    if( path == NULL ) return;
    char *tmp;
    if( asprintf( &tmp, "%s.tmp", path ) < 0 ) { free( path ); return; }
    FILE *f = vlc_fopen( tmp, "wb" );
    if( f == NULL ) { free( path ); free( tmp ); return; }
    setvbuf( f, NULL, _IOFBF, 64 * 1024 );
    int ret = pvlc_binary_write( f, pvlc_smart_magic,
                                 sizeof( pvlc_smart_magic ) );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f,
                                                   catalog->i_fingerprint );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f, definitions );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( f, (uint32_t)count );
    for( size_t s = 0; s < count; ++s )
    {
        if( results[s].i_count > UINT32_MAX ) { ret = VLC_EGENERIC; break; }
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( f,
                                                        smart[s].psz_name );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( f,
                                               (uint32_t)results[s].i_count );
        for( size_t i = 0; i < results[s].i_count; ++i )
        {
            if( results[s].p_indices[i] > UINT32_MAX )
                ret = VLC_EGENERIC;
            else if( ret == VLC_SUCCESS )
                ret = pvlc_binary_write_u32( f,
                              (uint32_t)results[s].p_indices[i] );
            if( ret != VLC_SUCCESS ) break;
        }
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
    free( path ); free( tmp );
}

static input_item_t *pvlc_add_node( services_discovery_t *sd,
                                    input_item_t *parent, const char *name )
{
    input_item_t *item = input_item_NewExt( "vlc://nop", name, -1,
                                             ITEM_TYPE_NODE, ITEM_LOCAL );
    if( item == NULL ) return NULL;
    /* This service publishes the children synchronously from its database.
     * Generic metadata preparsing of vlc://nop containers only occupies the
     * single preparser queue and can delay a real lazy-index expansion. */
    input_item_SetPreparsed( item, true );
    if( parent ) services_discovery_AddSubItem( sd, parent, item );
    else services_discovery_AddItem( sd, item );
    return item;
}

static void pvlc_add_media( services_discovery_t *sd, input_item_t *parent,
                            const pvlc_media_entry_t *entry )
{
    char *uri = vlc_path2uri( entry->psz_path, NULL );
    input_item_t *item = uri ? input_item_NewFile( uri, entry->psz_title, -1,
                                                   ITEM_LOCAL ) : NULL;
    free( uri );
    if( item == NULL ) return;
    for( size_t i = 0; i < VLC_META_TYPE_COUNT; ++i )
    {
        const char *value = pvlc_media_meta( entry, (vlc_meta_type_t)i );
        if( value && *value ) input_item_SetMeta( item, (vlc_meta_type_t)i,
                                                  value );
    }
    if( entry->i_rating > 0 )
    {
        char rating[2] = { (char)('0' + entry->i_rating), '\0' };
        input_item_SetRating( item, rating );
    }
    input_item_SetDuration( item, entry->i_duration );
    /* The catalog database is authoritative.  Avoid probing the source file
     * (especially over AFP/SMB) merely because an optional tag is empty. */
    input_item_SetPreparsed( item, true );
    for( size_t i = 0; i < entry->i_extra_count; ++i )
    {
        vlc_mutex_lock( &item->lock );
        if( item->p_meta == NULL ) item->p_meta = vlc_meta_New();
        if( item->p_meta ) vlc_meta_AddExtra( item->p_meta,
                                              entry->ppsz_extra_names[i],
                                              entry->ppsz_extra_values[i] );
        vlc_mutex_unlock( &item->lock );
    }
    services_discovery_AddSubItem( sd, parent, item );
    input_item_Release( item );
}

/* Persistent user playlists ------------------------------------------------
 *
 * They live in the fourth discovery root and are deliberately stored in a
 * small portable binary tree rather than in the source-folder catalogues.
 * This keeps playlist edits instant and available while a monitored network
 * volume is offline. */
static const unsigned char pvlc_user_playlist_magic_v1[8] = {
    'P', 'V', 'L', 'C', 'P', 'L', 1, 0
};
static const unsigned char pvlc_user_playlist_magic[8] = {
    'P', 'V', 'L', 'C', 'P', 'L', 2, 0
};

#define PVLC_USER_MANAGED_URI "powervlc-managed-relative:"

enum pvlc_user_playlist_record
{
    PVLC_USER_FOLDER = 1,
    PVLC_USER_PLAYLIST,
    PVLC_USER_TRACK,
};

static char *pvlc_user_playlist_path( void )
{
    char *data = config_GetUserDir( VLC_DATA_DIR );
    if( data == NULL ) return NULL;
    pvlc_mkdir_parents( data );
    char *path = pvlc_path_join( data, "powervlc-playlists.db" );
    free( data );
    return path;
}

static unsigned pvlc_user_record_type( input_item_t *item )
{
    if( input_item_IsPowerVLCPlaylistFolder( item ) ) return PVLC_USER_FOLDER;
    if( input_item_IsPowerVLCUserPlaylist( item ) ) return PVLC_USER_PLAYLIST;
    return PVLC_USER_TRACK;
}

/* Managed-library media must remain portable when the managed folder moves.
 * The playlist database therefore stores only the path below that folder.
 * External and network media keep their complete URI. */
static char *pvlc_user_portable_uri( vlc_object_t *obj, const char *uri )
{
    if( uri == NULL ) return strdup( "" );
    char *path = vlc_uri2path( uri );
    char *managed = pvlc_managed_folder( obj );
    char *stored = NULL;
    if( path && managed )
    {
        size_t length = strlen( managed );
        while( length > 1 && (managed[length - 1] == '/'
                           || managed[length - 1] == '\\') )
            --length;
#ifdef _WIN32
        bool inside = !strncasecmp( path, managed, length );
#else
        bool inside = !strncmp( path, managed, length );
#endif
        inside = inside && (path[length] == '/' || path[length] == '\\');
        if( inside )
            asprintf( &stored, "%s%s", PVLC_USER_MANAGED_URI,
                      path + length + 1 );
    }
    free( path );
    free( managed );
    return stored ? stored : strdup( uri );
}

static bool pvlc_user_relative_path_safe( const char *relative )
{
    if( relative == NULL || *relative == '\0' || *relative == '/'
     || *relative == '\\' ) return false;
    const char *part = relative;
    while( *part )
    {
        const char *end = strpbrk( part, "/\\" );
        size_t length = end ? (size_t)(end - part) : strlen( part );
        if( length == 0 || (length == 1 && part[0] == '.')
         || (length == 2 && part[0] == '.' && part[1] == '.') )
            return false;
        if( end == NULL ) break;
        part = end + 1;
    }
    return true;
}

static char *pvlc_user_resolve_uri( vlc_object_t *obj, const char *stored )
{
    size_t prefix = strlen( PVLC_USER_MANAGED_URI );
    if( strncmp( stored, PVLC_USER_MANAGED_URI, prefix ) )
        return strdup( stored );
    const char *relative = stored + prefix;
    if( !pvlc_user_relative_path_safe( relative ) ) return NULL;
    char *managed = pvlc_managed_folder( obj );
    char *path = managed ? pvlc_path_join( managed, relative ) : NULL;
    char *uri = path ? vlc_path2uri( path, NULL ) : NULL;
    free( path );
    free( managed );
    return uri;
}

static int pvlc_user_write_item( services_discovery_t *sd, FILE *f,
                                 playlist_item_t *item )
{
    if( item == NULL || item->p_input == NULL ) return VLC_EGENERIC;
    unsigned type = pvlc_user_record_type( item->p_input );
    char *name = input_item_GetName( item->p_input );
    char *uri = input_item_GetURI( item->p_input );
    char *stored_uri = type == PVLC_USER_TRACK
        ? pvlc_user_portable_uri( VLC_OBJECT( sd ), uri ) : strdup( uri ?: "" );
    uint32_t count = item->i_children > 0 ? (uint32_t)item->i_children : 0;
    /* i_children is an int, therefore every non-negative value is already
     * representable as uint32_t.  Casting UINT32_MAX to int would yield -1
     * on the supported targets and reject every container. */
    int ret = pvlc_binary_write_u32( f, type );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( f, name ?: "" );
    if( ret == VLC_SUCCESS && stored_uri == NULL ) ret = VLC_ENOMEM;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( f, stored_uri );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( f, count );
    for( uint32_t i = 0; ret == VLC_SUCCESS && i < count; ++i )
        ret = pvlc_user_write_item( sd, f, item->pp_children[i] );
    free( name );
    free( uri );
    free( stored_uri );
    return ret;
}

static int pvlc_user_save_locked( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    playlist_t *playlist = (playlist_t *)sd->obj.parent;
    playlist_item_t *root = sys->pp_roots[3]
                           ? playlist_ItemGetByInput( playlist,
                                                     sys->pp_roots[3] )
                           : NULL;
    if( root == NULL ) return VLC_EGENERIC;
    char *path = pvlc_user_playlist_path();
    char *tmp = NULL;
    if( path && asprintf( &tmp, "%s.tmp", path ) < 0 ) tmp = NULL;
    if( path == NULL || tmp == NULL )
    { free( path ); free( tmp ); return VLC_ENOMEM; }
    FILE *f = vlc_fopen( tmp, "wb" );
    if( f == NULL )
    { free( path ); free( tmp ); return VLC_EGENERIC; }
    setvbuf( f, NULL, _IOFBF, 64 * 1024 );
    int ret = pvlc_binary_write( f, pvlc_user_playlist_magic,
                                 sizeof( pvlc_user_playlist_magic ) );
    uint32_t count = root->i_children > 0 ? (uint32_t)root->i_children : 0;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( f, count );
    for( uint32_t i = 0; ret == VLC_SUCCESS && i < count; ++i )
        ret = pvlc_user_write_item( sd, f, root->pp_children[i] );
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
    free( path );
    free( tmp );
    return error ? VLC_EGENERIC : VLC_SUCCESS;
}

static input_item_t *pvlc_user_load_item( services_discovery_t *sd, FILE *f,
                                          input_item_t *parent,
                                          unsigned depth )
{
    if( depth > 64 ) return NULL;
    uint32_t type, count;
    char *name = NULL, *uri = NULL;
    if( pvlc_binary_read_u32( f, &type ) != VLC_SUCCESS
     || pvlc_binary_read_string( f, &name, 1024 * 1024 ) != VLC_SUCCESS
     || pvlc_binary_read_string( f, &uri, 16 * 1024 * 1024 ) != VLC_SUCCESS
     || pvlc_binary_read_u32( f, &count ) != VLC_SUCCESS
     || count > 100000
     || (type != PVLC_USER_FOLDER && type != PVLC_USER_PLAYLIST
      && type != PVLC_USER_TRACK) )
    { free( name ); free( uri ); return NULL; }
    input_item_t *item;
    if( type == PVLC_USER_TRACK )
    {
        char *resolved = pvlc_user_resolve_uri( VLC_OBJECT( sd ), uri );
        item = resolved ? input_item_New( resolved, name ) : NULL;
        free( resolved );
    }
    else
    {
        item = input_item_NewExt( "vlc://nop", name, -1,
                                  ITEM_TYPE_NODE, ITEM_LOCAL );
        if( item ) input_item_AddOption( item,
            type == PVLC_USER_FOLDER
                ? VLC_INPUT_OPTION_POWERVLC_PLAYLIST_FOLDER
                : VLC_INPUT_OPTION_POWERVLC_USER_PLAYLIST, 0 );
    }
    free( name );
    free( uri );
    if( item == NULL ) return NULL;
    services_discovery_AddSubItem( sd, parent, item );
    for( uint32_t i = 0; i < count; ++i )
    {
        input_item_t *child = pvlc_user_load_item( sd, f, item, depth + 1 );
        if( child == NULL )
        { input_item_Release( item ); return NULL; }
        input_item_Release( child );
    }
    return item;
}

static void pvlc_user_load( services_discovery_t *sd, input_item_t *root )
{
    char *path = pvlc_user_playlist_path();
    FILE *f = path ? vlc_fopen( path, "rb" ) : NULL;
    free( path );
    if( f == NULL ) return;
    setvbuf( f, NULL, _IOFBF, 64 * 1024 );
    unsigned char magic[sizeof( pvlc_user_playlist_magic )];
    uint32_t count = 0;
    bool valid = pvlc_binary_read( f, magic, sizeof( magic ) ) == VLC_SUCCESS
              && (!memcmp( magic, pvlc_user_playlist_magic, sizeof( magic ) )
               || !memcmp( magic, pvlc_user_playlist_magic_v1,
                           sizeof( magic ) ))
              && pvlc_binary_read_u32( f, &count ) == VLC_SUCCESS
              && count <= 100000;
    for( uint32_t i = 0; valid && i < count; ++i )
    {
        input_item_t *item = pvlc_user_load_item( sd, f, root, 0 );
        if( item == NULL ) valid = false;
        else input_item_Release( item );
    }
    fclose( f );
}

static int pvlc_music_compare( const void *a, const void *b )
{
    const pvlc_media_entry_t *ea = *(const pvlc_media_entry_t *const *)a;
    const pvlc_media_entry_t *eb = *(const pvlc_media_entry_t *const *)b;
    int c = strcasecmp( ea->psz_artist, eb->psz_artist );
    if( !c ) c = strcasecmp( ea->psz_album, eb->psz_album );
    const char *da = pvlc_media_meta( ea, vlc_meta_DiscNumber );
    const char *db = pvlc_media_meta( eb, vlc_meta_DiscNumber );
    const char *ta = pvlc_media_meta( ea, vlc_meta_TrackNumber );
    const char *tb = pvlc_media_meta( eb, vlc_meta_TrackNumber );
    if( !c && strtoul( da ? da : "0", NULL, 10 )
            != strtoul( db ? db : "0", NULL, 10 ) )
        c = strtoul( da ? da : "0", NULL, 10 )
          < strtoul( db ? db : "0", NULL, 10 ) ? -1 : 1;
    if( !c && strtoul( ta ? ta : "0", NULL, 10 )
            != strtoul( tb ? tb : "0", NULL, 10 ) )
        c = strtoul( ta ? ta : "0", NULL, 10 )
          < strtoul( tb ? tb : "0", NULL, 10 ) ? -1 : 1;
    if( !c ) c = strcasecmp( ea->psz_title, eb->psz_title );
    return c;
}

static bool pvlc_track_precedes( const pvlc_media_entry_t *a,
                                 const pvlc_media_entry_t *b )
{
    const char *a_disc = pvlc_media_meta( a, vlc_meta_DiscNumber );
    const char *b_disc = pvlc_media_meta( b, vlc_meta_DiscNumber );
    const char *a_track = pvlc_media_meta( a, vlc_meta_TrackNumber );
    const char *b_track = pvlc_media_meta( b, vlc_meta_TrackNumber );
    unsigned long ad = a_disc && *a_disc ? strtoul( a_disc, NULL, 10 ) : ULONG_MAX;
    unsigned long bd = b_disc && *b_disc ? strtoul( b_disc, NULL, 10 ) : ULONG_MAX;
    unsigned long at = a_track && *a_track ? strtoul( a_track, NULL, 10 ) : ULONG_MAX;
    unsigned long bt = b_track && *b_track ? strtoul( b_track, NULL, 10 ) : ULONG_MAX;
    if( ad != bd ) return ad < bd;
    if( at != bt ) return at < bt;
    return strcasecmp( a->psz_title, b->psz_title ) < 0;
}

static const char *pvlc_album_artist( const pvlc_media_entry_t *entry )
{
    const char *value = pvlc_media_meta( entry, vlc_meta_AlbumArtist );
    return value && *value ? value : entry->psz_artist;
}

static const char *pvlc_composer( const pvlc_media_entry_t *entry )
{
    static const char *const names[] = {
        "COMPOSER", "Composer", "WM/Composer", "TCOM"
    };
    for( size_t i = 0; i < ARRAY_SIZE( names ); ++i )
    {
        const char *value = pvlc_media_extra( entry, names[i] );
        if( value && *value ) return value;
    }
    const char *localized = pvlc_media_extra( entry, _( "Composer" ) );
    return localized && *localized ? localized : _( "Unknown Composer" );
}

/* Date tags are not consistently limited to a bare year.  Vorbis comments
 * in particular commonly contain YYYYMMDD or an ISO date.  Keep the media
 * library grouping stable by extracting the first plausible four-digit
 * year instead of treating the complete integer as a year. */
static unsigned pvlc_metadata_year( const char *date )
{
    if( date == NULL ) return 0;
    for( const unsigned char *p = (const unsigned char *)date; *p; ++p )
    {
        if( !isdigit( *p ) ) continue;
        if( isdigit( p[1] ) && isdigit( p[2] ) && isdigit( p[3] ) )
        {
            unsigned year = (unsigned)(p[0] - '0') * 1000
                          + (unsigned)(p[1] - '0') * 100
                          + (unsigned)(p[2] - '0') * 10
                          + (unsigned)(p[3] - '0');
            if( year >= 1000 && year <= 9999 ) return year;
        }
        while( isdigit( p[1] ) ) ++p;
    }
    return 0;
}

typedef enum
{
    PVLC_VIEW_ALBUM_ARTISTS,
    PVLC_VIEW_ARTISTS,
    PVLC_VIEW_ALBUMS,
    PVLC_VIEW_GENRES,
    PVLC_VIEW_COMPOSERS,
    PVLC_VIEW_YEARS,
    PVLC_VIEW_TRACKS,
    PVLC_VIEW_RECENT,
    PVLC_VIEW_RATINGS,
    PVLC_VIEW_COUNT,
} pvlc_music_view_t;

#define PVLC_LETTER_BUCKETS 38
#define PVLC_OTHER_BUCKET 36
#define PVLC_UNKNOWN_BUCKET 37

typedef struct
{
    const pvlc_media_entry_t *entry;
    const char *primary;
    const char *secondary;
    unsigned bucket;
    unsigned year;
    unsigned rating;
    pvlc_music_view_t view;
    char year_label[32];
    uint64_t random_primary;
    uint64_t random_secondary;
    uint64_t random_track;
} pvlc_index_ref_t;

static uint64_t pvlc_random_key( uint64_t seed, const char *value )
{
    uint64_t hash = seed ^ UINT64_C(1469598103934665603);
    for( const unsigned char *p = (const unsigned char *)(value ? value : "");
         *p; ++p )
    { hash ^= *p; hash *= UINT64_C(1099511628211); }
    /* SplitMix finalizer avoids alphabetical-looking runs for similar names. */
    hash ^= hash >> 30; hash *= UINT64_C(0xbf58476d1ce4e5b9);
    hash ^= hash >> 27; hash *= UINT64_C(0x94d049bb133111eb);
    return hash ^ (hash >> 31);
}

static unsigned pvlc_letter_bucket( const char *value )
{
    while( value && *value && isspace( (unsigned char)*value ) ) value++;
    uint32_t cp = 0;
    if( value == NULL || vlc_towc( value, &cp ) == 0 )
        return PVLC_OTHER_BUCKET;
    if( cp >= 'a' && cp <= 'z' ) cp -= 'a' - 'A';
    /* Fold the common Latin accents into their Rockbox-style A-Z bucket. */
    if( (cp >= 0x00c0 && cp <= 0x00c5) || (cp >= 0x00e0 && cp <= 0x00e5) ) cp = 'A';
    else if( cp == 0x00c7 || cp == 0x00e7 ) cp = 'C';
    else if( (cp >= 0x00c8 && cp <= 0x00cb) || (cp >= 0x00e8 && cp <= 0x00eb) ) cp = 'E';
    else if( (cp >= 0x00cc && cp <= 0x00cf) || (cp >= 0x00ec && cp <= 0x00ef) ) cp = 'I';
    else if( cp == 0x00d1 || cp == 0x00f1 ) cp = 'N';
    else if( (cp >= 0x00d2 && cp <= 0x00d6) || (cp >= 0x00f2 && cp <= 0x00f6) ) cp = 'O';
    else if( (cp >= 0x00d9 && cp <= 0x00dc) || (cp >= 0x00f9 && cp <= 0x00fc) ) cp = 'U';
    else if( cp == 0x00dd || cp == 0x00fd || cp == 0x00ff ) cp = 'Y';
    if( cp >= 'A' && cp <= 'Z' ) return (unsigned)(cp - 'A');
    if( cp >= '0' && cp <= '9' ) return 26 + (unsigned)(cp - '0');
    return PVLC_OTHER_BUCKET;
}

static const char *pvlc_bucket_label( unsigned bucket, char label[2] )
{
    label[0] = bucket < 26 ? (char)('A' + bucket)
             : bucket < 36 ? (char)('0' + bucket - 26)
             : bucket == PVLC_UNKNOWN_BUCKET ? '?' : '#';
    label[1] = '\0';
    return label;
}

static bool pvlc_unknown_label( const char *value, const char *fallback )
{
    return value == NULL || *value == '\0'
        || strcasecmp( value, fallback ) == 0
        || strcasecmp( value, _( fallback ) ) == 0;
}

/* Unknown values are real virtual groups, not ordinary words.  Keep them in
 * the dedicated '?' bucket instead of sorting their translated label under
 * C (Compositeur inconnu), U (Unknown Artist), etc. */
static bool pvlc_view_primary_is_unknown( pvlc_music_view_t view,
                                          const char *primary )
{
    switch( view )
    {
        case PVLC_VIEW_ALBUM_ARTISTS:
        case PVLC_VIEW_ARTISTS:
            return pvlc_unknown_label( primary, "Unknown Artist" );
        case PVLC_VIEW_ALBUMS:
            return pvlc_unknown_label( primary, "Unknown Album" );
        case PVLC_VIEW_GENRES:
            return pvlc_unknown_label( primary, "Unknown Genre" );
        case PVLC_VIEW_COMPOSERS:
            return pvlc_unknown_label( primary, "Unknown Composer" );
        case PVLC_VIEW_YEARS:
            return pvlc_unknown_label( primary, "Unknown Year" );
        default:
            return false;
    }
}

static unsigned pvlc_view_bucket( pvlc_music_view_t view,
                                  const char *primary, unsigned rating )
{
    if( view == PVLC_VIEW_RATINGS ) return rating;
    if( pvlc_view_primary_is_unknown( view, primary ) )
        return PVLC_UNKNOWN_BUCKET;
    return pvlc_letter_bucket( primary );
}

static const char *pvlc_view_bucket_label( pvlc_music_view_t view,
                                           unsigned bucket, char label[2] )
{
    if( view == PVLC_VIEW_RATINGS )
    {
        static const char *const ratings[] = {
            "", "★", "★★", "★★★", "★★★★", "★★★★★"
        };
        return ratings[bucket <= 5 ? bucket : 0];
    }
    return pvlc_bucket_label( bucket, label );
}

static const char *pvlc_view_primary( pvlc_index_ref_t *ref,
                                      pvlc_music_view_t view )
{
    const pvlc_media_entry_t *entry = ref->entry;
    ref->secondary = "";
    switch( view )
    {
        case PVLC_VIEW_ALBUM_ARTISTS:
            ref->secondary = entry->psz_album;
            return pvlc_album_artist( entry );
        case PVLC_VIEW_ARTISTS:
            ref->secondary = entry->psz_album;
            return entry->psz_artist;
        case PVLC_VIEW_ALBUMS:
            ref->secondary = pvlc_album_artist( entry );
            return entry->psz_album;
        case PVLC_VIEW_GENRES:
        {
            ref->secondary = entry->psz_album;
            const char *genre = pvlc_media_meta( entry, vlc_meta_Genre );
            return genre && *genre ? genre : _( "Unknown Genre" );
        }
        case PVLC_VIEW_COMPOSERS:
            ref->secondary = entry->psz_album;
            return pvlc_composer( entry );
        case PVLC_VIEW_YEARS:
        {
            ref->secondary = entry->psz_album;
            const char *date = pvlc_media_meta( entry, vlc_meta_Date );
            ref->year = pvlc_metadata_year( date );
            if( ref->year ) snprintf( ref->year_label, sizeof( ref->year_label ),
                                     "%u", ref->year );
            else snprintf( ref->year_label, sizeof( ref->year_label ), "%s",
                           _( "Unknown Year" ) );
            return ref->year_label;
        }
        case PVLC_VIEW_RATINGS:
        {
            static const char *const labels[] = {
                "", "★", "★★", "★★★", "★★★★", "★★★★★"
            };
            ref->rating = entry->i_rating;
            return labels[ref->rating <= 5 ? ref->rating : 0];
        }
        case PVLC_VIEW_TRACKS:
        case PVLC_VIEW_RECENT:
            return entry->psz_title;
        default:
            return entry->psz_title;
    }
}

static size_t pvlc_search_string_size( const char *value )
{
    return strlen( value ? value : "" ) + 1;
}

static const char *pvlc_search_string_copy( char **cursor, const char *value )
{
    if( value == NULL ) value = "";
    size_t length = strlen( value ) + 1;
    char *result = *cursor;
    memcpy( result, value, length );
    *cursor += length;
    return result;
}

static int pvlc_search_catalog_build( const pvlc_media_catalog_t *source,
                                      pvlc_search_catalog_t *target )
{
    memset( target, 0, sizeof( *target ) );
    size_t count = 0, bytes = 0;
    for( size_t i = 0; i < source->i_count; ++i )
    {
        const pvlc_media_entry_t *entry = &source->p_entries[i];
        if( entry->i_type != PVLC_MEDIA_AUDIO ) continue;
        const char *genre = pvlc_media_meta( entry, vlc_meta_Genre );
        const char *date = pvlc_media_meta( entry, vlc_meta_Date );
        char year[32]; unsigned value = pvlc_metadata_year( date );
        if( value ) snprintf( year, sizeof( year ), "%u", value );
        else snprintf( year, sizeof( year ), "%s", _( "Unknown Year" ) );
        const char *strings[] = {
            entry->psz_search_folded, entry->psz_title, entry->psz_artist,
            entry->psz_album, pvlc_album_artist( entry ),
            genre && *genre ? genre : _( "Unknown Genre" ),
            pvlc_composer( entry ), year,
        };
        for( size_t j = 0; j < ARRAY_SIZE( strings ); ++j )
        {
            size_t length = pvlc_search_string_size( strings[j] );
            if( bytes > SIZE_MAX - length ) return VLC_ENOMEM;
            bytes += length;
        }
        if( count == SIZE_MAX ) return VLC_ENOMEM;
        ++count;
    }
    if( count > SIZE_MAX / sizeof( *target->p_entries ) ) return VLC_ENOMEM;
    target->p_entries = calloc( count, sizeof( *target->p_entries ) );
    target->p_strings = malloc( bytes ? bytes : 1 );
    if( (count && target->p_entries == NULL) || target->p_strings == NULL )
    { pvlc_search_catalog_clear( target ); return VLC_ENOMEM; }

    char *cursor = target->p_strings; size_t out = 0;
    for( size_t i = 0; i < source->i_count; ++i )
    {
        const pvlc_media_entry_t *entry = &source->p_entries[i];
        if( entry->i_type != PVLC_MEDIA_AUDIO ) continue;
        pvlc_search_entry_t *search = &target->p_entries[out++];
        const char *genre = pvlc_media_meta( entry, vlc_meta_Genre );
        const char *date = pvlc_media_meta( entry, vlc_meta_Date );
        char year[32]; unsigned value = pvlc_metadata_year( date );
        if( value ) snprintf( year, sizeof( year ), "%u", value );
        else snprintf( year, sizeof( year ), "%s", _( "Unknown Year" ) );
        search->psz_search = pvlc_search_string_copy( &cursor,
                                                  entry->psz_search_folded );
        search->psz_title = pvlc_search_string_copy( &cursor,
                                                  entry->psz_title );
        search->psz_artist = pvlc_search_string_copy( &cursor,
                                                  entry->psz_artist );
        search->psz_album = pvlc_search_string_copy( &cursor,
                                                  entry->psz_album );
        search->psz_album_artist = pvlc_search_string_copy( &cursor,
                                                  pvlc_album_artist( entry ) );
        search->psz_genre = pvlc_search_string_copy( &cursor,
                         genre && *genre ? genre : _( "Unknown Genre" ) );
        search->psz_composer = pvlc_search_string_copy( &cursor,
                                                  pvlc_composer( entry ) );
        search->psz_year = pvlc_search_string_copy( &cursor, year );
        search->i_rating = entry->i_rating;
    }
    target->i_count = out;
    return VLC_SUCCESS;
}

static int pvlc_index_ref_compare( const void *a, const void *b )
{
    const pvlc_index_ref_t *ra = a, *rb = b;
    if( ra->bucket != rb->bucket ) return ra->bucket < rb->bucket ? -1 : 1;
    if( ra->view == PVLC_VIEW_RECENT
     && ra->entry->i_mtime != rb->entry->i_mtime )
        return ra->entry->i_mtime > rb->entry->i_mtime ? -1 : 1;
    if( ra->view == PVLC_VIEW_YEARS && ra->year != rb->year )
        return ra->year > rb->year ? -1 : 1;
    if( ra->view == PVLC_VIEW_RATINGS && ra->rating != rb->rating )
        return ra->rating > rb->rating ? -1 : 1;
    int c = strcasecmp( ra->primary, rb->primary );
    if( !c ) c = strcasecmp( ra->secondary, rb->secondary );
    if( !c )
    {
        const pvlc_media_entry_t *ea = ra->entry, *eb = rb->entry;
        c = pvlc_music_compare( &ea, &eb );
    }
    return c;
}

static char *pvlc_music_index_directory( void )
{
    char *data = config_GetUserDir( VLC_DATA_DIR );
    if( data == NULL ) return NULL;
    char *path = pvlc_path_join( data, "powervlc-media-index" );
    free( data );
    if( path && pvlc_mkdir_parents( path ) != VLC_SUCCESS )
    { free( path ); return NULL; }
    return path;
}

static char *pvlc_music_bucket_path( const char *directory,
                                     pvlc_music_view_t view,
                                     unsigned bucket )
{
    char name[48];
    snprintf( name, sizeof( name ), "music-%u-%02u.xspf",
              (unsigned)view, bucket );
    return pvlc_path_join( directory, name );
}

static char *pvlc_music_random_path( const char *directory,
                                     pvlc_music_view_t view )
{
    char name[48];
    snprintf( name, sizeof( name ), "music-%u-random.xspf",
              (unsigned)view );
    return pvlc_path_join( directory, name );
}

static void pvlc_xspf_text( FILE *file, const char *element,
                            const char *value )
{
    if( value == NULL || *value == '\0' ) return;
    char *xml = vlc_xml_encode( value );
    if( xml )
    {
        fprintf( file, "<%s>%s</%s>\n", element, xml, element );
        free( xml );
    }
}

static char *pvlc_music_display_title( const pvlc_media_entry_t *entry )
{
    const char *disc_value = pvlc_media_meta( entry, vlc_meta_DiscNumber );
    const char *track_value = pvlc_media_meta( entry, vlc_meta_TrackNumber );
    unsigned long disc = disc_value && *disc_value
                       ? strtoul( disc_value, NULL, 10 ) : 0;
    unsigned long track = track_value && *track_value
                        ? strtoul( track_value, NULL, 10 ) : 0;
    char *title = NULL;
    if( disc && track )
        asprintf( &title, "%lu.%lu. %s", disc, track, entry->psz_title );
    else if( track )
        asprintf( &title, "%lu. %s", track, entry->psz_title );
    return title ? title : strdup( entry->psz_title );
}

static void pvlc_xspf_track( FILE *file, const pvlc_media_entry_t *entry,
                             size_t id )
{
    char *uri = vlc_path2uri( entry->psz_path, NULL );
    char *display_title = pvlc_music_display_title( entry );
    fprintf( file, "<track>\n" );
    pvlc_xspf_text( file, "location", uri );
    pvlc_xspf_text( file, "title", display_title );
    pvlc_xspf_text( file, "creator", entry->psz_artist );
    pvlc_xspf_text( file, "album", entry->psz_album );
    pvlc_xspf_text( file, "trackNum",
                    pvlc_media_meta( entry, vlc_meta_TrackNumber ) );
    if( entry->i_rating > 0 )
        fprintf( file, "<rating>%u</rating>\n", entry->i_rating );
    if( entry->i_duration > 0 )
        fprintf( file, "<duration>%" PRId64 "</duration>\n",
                 (int64_t)(entry->i_duration / VLC_TICK_FROM_MS( 1 )) );
    fprintf( file, "<extension application=\"http://www.videolan.org/vlc/playlist/0\"><vlc:id>%zu</vlc:id></extension>\n</track>\n",
             id );
    free( display_title );
    free( uri );
}

static void pvlc_xspf_node_open( FILE *file, const char *name )
{
    char *xml = vlc_xml_encode( name ? name : "" );
    fprintf( file, "<vlc:node title=\"%s\">\n", xml ? xml : "" );
    free( xml );
}

static void pvlc_xspf_album_open( FILE *file, const char *name )
{
    pvlc_xspf_node_open( file, name );
    fprintf( file, "<vlc:option>%s</vlc:option>\n",
             VLC_INPUT_OPTION_POWERVLC_ALBUM_SCOPE );
}

static void pvlc_xspf_random_open( FILE *file, const char *label,
                                   bool album_track, bool album_scope )
{
    pvlc_xspf_node_open( file, label );
    fprintf( file, "<vlc:option>%s</vlc:option>\n",
             VLC_INPUT_OPTION_POWERVLC_RANDOM_ACTION );
    if( album_track )
        fprintf( file, "<vlc:option>%s</vlc:option>\n",
                 VLC_INPUT_OPTION_POWERVLC_RANDOM_ALBUM_TRACK );
    if( album_scope )
        fprintf( file, "<vlc:option>%s</vlc:option>\n",
                 VLC_INPUT_OPTION_POWERVLC_ALBUM_SCOPE );
}

static bool pvlc_view_has_albums( pvlc_music_view_t view )
{
    return view == PVLC_VIEW_ALBUM_ARTISTS || view == PVLC_VIEW_ARTISTS
        || view == PVLC_VIEW_COMPOSERS || view == PVLC_VIEW_GENRES
        || view == PVLC_VIEW_YEARS;
}

static bool pvlc_view_random_selects_album( pvlc_music_view_t view )
{
    return pvlc_view_has_albums( view ) || view == PVLC_VIEW_ALBUMS;
}

static bool pvlc_view_has_groups( pvlc_music_view_t view )
{
    return view != PVLC_VIEW_TRACKS && view != PVLC_VIEW_RECENT
        && view != PVLC_VIEW_RATINGS;
}

typedef enum
{
    PVLC_ALIAS_TOP,
    PVLC_ALIAS_PRIMARY,
    PVLC_ALIAS_ALBUM,
} pvlc_alias_kind_t;

typedef struct
{
    const pvlc_index_ref_t *ref;
    const pvlc_index_ref_t *owner;
    pvlc_alias_kind_t kind;
} pvlc_index_alias_t;

static int pvlc_alias_append( pvlc_index_alias_t **aliases, size_t *count,
                              const pvlc_index_ref_t *ref,
                              const pvlc_index_ref_t *owner,
                              pvlc_alias_kind_t kind )
{
    pvlc_index_alias_t *grown = realloc( *aliases,
                                         (*count + 1) * sizeof( **aliases ) );
    if( grown == NULL ) return VLC_ENOMEM;
    *aliases = grown;
    grown[*count] = (pvlc_index_alias_t){ ref, owner, kind };
    (*count)++;
    return VLC_SUCCESS;
}

static int pvlc_track_ref_compare( const void *a, const void *b )
{
    const pvlc_index_ref_t *ra = *(const pvlc_index_ref_t *const *)a;
    const pvlc_index_ref_t *rb = *(const pvlc_index_ref_t *const *)b;
    if( pvlc_track_precedes( ra->entry, rb->entry ) ) return -1;
    if( pvlc_track_precedes( rb->entry, ra->entry ) ) return 1;
    return 0;
}

static int pvlc_alias_append_album( pvlc_index_alias_t **aliases,
                                    size_t *alias_count,
                                    const pvlc_index_ref_t *refs,
                                    size_t first, size_t end,
                                    const pvlc_index_ref_t *owner,
                                    pvlc_alias_kind_t kind )
{
    size_t count = end - first;
    const pvlc_index_ref_t **ordered = malloc( count * sizeof( *ordered ) );
    if( count && ordered == NULL ) return VLC_ENOMEM;
    for( size_t i = 0; i < count; ++i ) ordered[i] = &refs[first + i];
    qsort( ordered, count, sizeof( *ordered ), pvlc_track_ref_compare );
    int ret = VLC_SUCCESS;
    for( size_t i = 0; i < count && ret == VLC_SUCCESS; ++i )
        ret = pvlc_alias_append( aliases, alias_count, ordered[i], owner,
                                 kind );
    free( ordered );
    return ret;
}

static size_t pvlc_primary_end( const pvlc_index_ref_t *refs, size_t count,
                                size_t first )
{
    size_t end = first + 1;
    while( end < count && !strcasecmp( refs[first].primary,
                                       refs[end].primary ) ) end++;
    return end;
}

static size_t pvlc_album_end( const pvlc_index_ref_t *refs, size_t end,
                              size_t first )
{
    size_t next = first + 1;
    while( next < end && !strcasecmp( refs[first].entry->psz_album,
                                      refs[next].entry->psz_album ) ) next++;
    return next;
}

static int pvlc_build_aliases( const pvlc_index_ref_t *refs, size_t count,
                               pvlc_music_view_t view,
                               pvlc_index_alias_t **aliases,
                               size_t *alias_count )
{
    *aliases = NULL; *alias_count = 0;
    if( count == 0 ) return VLC_SUCCESS;
    if( !pvlc_view_has_groups( view ) )
    {
        size_t pick = 0;
        for( size_t i = 1; i < count; ++i )
            if( refs[i].random_track < refs[pick].random_track ) pick = i;
        return pvlc_alias_append( aliases, alias_count, &refs[pick], refs,
                                  PVLC_ALIAS_TOP );
    }

    size_t top = 0;
    for( size_t first = 0; first < count; )
    {
        if( refs[first].random_primary < refs[top].random_primary ) top = first;
        first = pvlc_primary_end( refs, count, first );
    }
    size_t top_end = pvlc_primary_end( refs, count, top );
    size_t top_first = top;
    if( pvlc_view_has_albums( view ) )
    {
        for( size_t album = top; album < top_end;
             album = pvlc_album_end( refs, top_end, album ) )
            if( refs[album].random_secondary
              < refs[top_first].random_secondary ) top_first = album;
        top_end = pvlc_album_end( refs, top_end, top_first );
    }
    if( view == PVLC_VIEW_ALBUM_ARTISTS )
    {
        if( pvlc_alias_append_album( aliases, alias_count, refs,
                                    top_first, top_end, &refs[top],
                                    PVLC_ALIAS_TOP ) != VLC_SUCCESS )
            goto error;
    }
    else for( size_t i = top_first; i < top_end; ++i )
        if( pvlc_alias_append( aliases, alias_count, &refs[i], &refs[top],
                              PVLC_ALIAS_TOP ) != VLC_SUCCESS ) goto error;

    for( size_t first = 0; first < count; )
    {
        size_t end = pvlc_primary_end( refs, count, first );
        if( pvlc_view_has_albums( view ) )
        {
            size_t chosen_album = first;
            for( size_t album = first; album < end;
                 album = pvlc_album_end( refs, end, album ) )
                if( refs[album].random_secondary
                  < refs[chosen_album].random_secondary ) chosen_album = album;
            size_t chosen_end = pvlc_album_end( refs, end, chosen_album );
            if( view == PVLC_VIEW_ALBUM_ARTISTS )
            {
                if( pvlc_alias_append_album( aliases, alias_count, refs,
                                            chosen_album, chosen_end,
                                            &refs[first],
                                            PVLC_ALIAS_PRIMARY )
                    != VLC_SUCCESS ) goto error;
            }
            else for( size_t i = chosen_album; i < chosen_end; ++i )
                if( pvlc_alias_append( aliases, alias_count, &refs[i],
                                      &refs[first], PVLC_ALIAS_PRIMARY )
                    != VLC_SUCCESS ) goto error;
            for( size_t album = first; album < end; )
            {
                size_t album_end = pvlc_album_end( refs, end, album );
                /* In Album Artists an album is the playable unit.  Keep the
                 * chosen album random, but start it at disc/track one. */
                size_t pick = album;
                if( view == PVLC_VIEW_ALBUM_ARTISTS )
                {
                    for( size_t i = album + 1; i < album_end; ++i )
                        if( pvlc_track_precedes( refs[i].entry,
                                                 refs[pick].entry ) )
                            pick = i;
                }
                else
                {
                    for( size_t i = album + 1; i < album_end; ++i )
                        if( refs[i].random_track < refs[pick].random_track )
                            pick = i;
                }
                if( pvlc_alias_append( aliases, alias_count, &refs[pick],
                                      &refs[album], PVLC_ALIAS_ALBUM )
                    != VLC_SUCCESS ) goto error;
                album = album_end;
            }
        }
        else
        {
            size_t pick = first;
            for( size_t i = first + 1; i < end; ++i )
                if( refs[i].random_track < refs[pick].random_track ) pick = i;
            if( pvlc_alias_append( aliases, alias_count, &refs[pick],
                                  &refs[first], PVLC_ALIAS_PRIMARY )
                != VLC_SUCCESS ) goto error;
        }
        first = end;
    }
    return VLC_SUCCESS;
error:
    free( *aliases ); *aliases = NULL; *alias_count = 0;
    return VLC_ENOMEM;
}

static void pvlc_xspf_primary_open( FILE *file,
                                    const pvlc_index_ref_t *ref,
                                    pvlc_music_view_t view )
{
    if( view == PVLC_VIEW_ALBUMS )
    {
        char *label;
        if( asprintf( &label, "%s — %s", ref->primary,
                      ref->secondary ) < 0 ) label = NULL;
        pvlc_xspf_album_open( file, label ? label : ref->primary );
        free( label );
    }
    else pvlc_xspf_node_open( file, ref->primary );
}

static void pvlc_write_alias_items( FILE *file,
                                    const pvlc_index_alias_t *aliases,
                                    size_t alias_count, size_t base,
                                    pvlc_alias_kind_t kind,
                                    const pvlc_index_ref_t *owner,
                                    bool wrap_album )
{
    const char *last_album = NULL;
    for( size_t i = 0; i < alias_count; ++i )
        if( aliases[i].kind == kind && aliases[i].owner == owner )
        {
            const char *album = aliases[i].ref->entry->psz_album;
            if( wrap_album && (last_album == NULL
                            || strcasecmp( last_album, album )) )
            {
                if( last_album ) fputs( "</vlc:node>\n", file );
                pvlc_xspf_album_open( file, album ); last_album = album;
            }
            fprintf( file, "<vlc:item tid=\"%zu\"/>\n", base + i );
        }
    if( last_album ) fputs( "</vlc:node>\n", file );
}

static int pvlc_write_music_bucket( const char *path,
                                    const pvlc_index_ref_t *refs,
                                    size_t count, pvlc_music_view_t view )
{
    pvlc_index_alias_t *aliases = NULL; size_t alias_count = 0;
    if( pvlc_build_aliases( refs, count, view, &aliases, &alias_count )
        != VLC_SUCCESS ) return VLC_ENOMEM;
    char *temporary;
    if( asprintf( &temporary, "%s.tmp", path ) < 0 )
    { free( aliases ); return VLC_ENOMEM; }
    FILE *file = vlc_fopen( temporary, "wb" );
    if( file == NULL )
    { free( aliases ); free( temporary ); return VLC_EGENERIC; }
    setvbuf( file, NULL, _IOFBF, 64 * 1024 );
    fputs( "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
           "<playlist xmlns=\"http://xspf.org/ns/0/\" xmlns:vlc=\"http://www.videolan.org/vlc/playlist/ns/0/\" version=\"1\">\n<trackList>\n",
           file );
    for( size_t i = 0; i < count; ++i )
        pvlc_xspf_track( file, refs[i].entry, i );
    for( size_t i = 0; i < alias_count; ++i )
        pvlc_xspf_track( file, aliases[i].ref->entry, count + i );
    fputs( "</trackList>\n<extension application=\"http://www.videolan.org/vlc/playlist/0\">\n",
           file );

    pvlc_xspf_random_open( file, pvlc_view_random_selects_album( view )
                                ? _( "Random (Album)" ) : _( "Random" ),
                           false, pvlc_view_random_selects_album( view ) );
    if( pvlc_view_has_groups( view ) )
    {
        const pvlc_index_ref_t *owner = alias_count ? aliases[0].owner : NULL;
        if( owner )
        {
            pvlc_xspf_primary_open( file, owner, view );
            pvlc_write_alias_items( file, aliases, alias_count, count,
                                    PVLC_ALIAS_TOP, owner,
                                    pvlc_view_has_albums( view ) );
            fputs( "</vlc:node>\n", file );
        }
    }
    else pvlc_write_alias_items( file, aliases, alias_count, count,
                                 PVLC_ALIAS_TOP, refs, false );
    fputs( "</vlc:node>\n", file );

    const char *last_primary = NULL, *last_album = NULL;
    const pvlc_index_ref_t *primary_owner = NULL, *album_owner = NULL;
    for( size_t i = 0; i < count; ++i )
    {
        const pvlc_index_ref_t *ref = &refs[i];
        bool new_primary = last_primary == NULL
                        || strcasecmp( last_primary, ref->primary );
        bool albums = pvlc_view_has_albums( view );
        if( pvlc_view_has_groups( view ) && new_primary )
        {
            if( last_album && albums ) fputs( "</vlc:node>\n", file );
            if( last_primary ) fputs( "</vlc:node>\n", file );
            pvlc_xspf_primary_open( file, ref, view );
            last_primary = ref->primary;
            last_album = NULL;
            primary_owner = ref;
            pvlc_xspf_random_open( file, albums
                                        ? _( "Random (Album)" )
                                        : _( "Random" ), false, albums );
            pvlc_write_alias_items( file, aliases, alias_count, count,
                                    PVLC_ALIAS_PRIMARY, primary_owner, albums );
            fputs( "</vlc:node>\n", file );
        }
        if( albums && (last_album == NULL
                    || strcasecmp( last_album, ref->entry->psz_album )) )
        {
            if( last_album ) fputs( "</vlc:node>\n", file );
            pvlc_xspf_album_open( file, ref->entry->psz_album );
            last_album = ref->entry->psz_album;
            album_owner = ref;
            pvlc_xspf_random_open( file, _( "Random (Album Track)" ), true,
                                   true );
            pvlc_write_alias_items( file, aliases, alias_count, count,
                                    PVLC_ALIAS_ALBUM, album_owner, false );
            fputs( "</vlc:node>\n", file );
        }
        fprintf( file, "<vlc:item tid=\"%zu\"/>\n", i );
    }
    if( last_album && pvlc_view_has_albums( view ) )
        fputs( "</vlc:node>\n", file );
    if( last_primary && pvlc_view_has_groups( view ) )
        fputs( "</vlc:node>\n", file );
    fputs( "</extension>\n</playlist>\n", file );
    bool error = fflush( file ) != 0 || ferror( file );
    if( fclose( file ) != 0 ) error = true;
    if( !error ) error = vlc_rename( temporary, path ) != 0;
    if( error ) vlc_unlink( temporary );
    free( aliases ); free( temporary );
    return error ? VLC_EGENERIC : VLC_SUCCESS;
}

/* The top-level Random action needs only the selected path, not another full
 * copy of the whole view.  Keeping just letter -> primary -> album -> tracks
 * makes activation cheap on G3 and lets interfaces reveal/select the first
 * playing track without displaying a second Random container. */
static int pvlc_write_music_random( const char *path,
                                    const pvlc_index_ref_t *refs,
                                    size_t count, pvlc_music_view_t view )
{
    pvlc_index_alias_t *aliases = NULL; size_t alias_count = 0;
    if( pvlc_build_aliases( refs, count, view, &aliases, &alias_count )
        != VLC_SUCCESS ) return VLC_ENOMEM;
    const pvlc_index_ref_t *owner = alias_count ? aliases[0].owner : NULL;
    char *temporary;
    if( asprintf( &temporary, "%s.tmp", path ) < 0 )
    { free( aliases ); return VLC_ENOMEM; }
    FILE *file = vlc_fopen( temporary, "wb" );
    if( file == NULL )
    { free( aliases ); free( temporary ); return VLC_EGENERIC; }
    setvbuf( file, NULL, _IOFBF, 16 * 1024 );
    fputs( "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
           "<playlist xmlns=\"http://xspf.org/ns/0/\" xmlns:vlc=\"http://www.videolan.org/vlc/playlist/ns/0/\" version=\"1\">\n<trackList>\n",
           file );
    size_t selected = 0;
    for( size_t i = 0; i < alias_count; ++i )
        if( aliases[i].kind == PVLC_ALIAS_TOP && aliases[i].owner == owner )
        {
            pvlc_xspf_track( file, aliases[i].ref->entry, selected );
            selected++;
        }
    fputs( "</trackList>\n<extension application=\"http://www.videolan.org/vlc/playlist/0\">\n",
           file );
    if( owner && pvlc_view_has_groups( view ) )
    {
        char label[2];
        pvlc_xspf_node_open( file,
            pvlc_bucket_label( owner->bucket, label ) );
        pvlc_xspf_primary_open( file, owner, view );
        const char *last_album = NULL;
        size_t tid = 0;
        for( size_t i = 0; i < alias_count; ++i )
            if( aliases[i].kind == PVLC_ALIAS_TOP
             && aliases[i].owner == owner )
            {
                const char *album = aliases[i].ref->entry->psz_album;
                if( pvlc_view_has_albums( view )
                 && (last_album == NULL || strcasecmp( last_album, album )) )
                {
                    if( last_album ) fputs( "</vlc:node>\n", file );
                    pvlc_xspf_album_open( file, album );
                    last_album = album;
                }
                fprintf( file, "<vlc:item tid=\"%zu\"/>\n", tid++ );
            }
        if( last_album ) fputs( "</vlc:node>\n", file );
        fputs( "</vlc:node>\n</vlc:node>\n", file );
    }
    else
        for( size_t i = 0; i < selected; ++i )
            fprintf( file, "<vlc:item tid=\"%zu\"/>\n", i );
    fputs( "</extension>\n</playlist>\n", file );
    bool error = selected == 0 || fflush( file ) != 0 || ferror( file );
    if( fclose( file ) != 0 ) error = true;
    if( !error ) error = vlc_rename( temporary, path ) != 0;
    if( error ) vlc_unlink( temporary );
    free( aliases ); free( temporary );
    return error ? VLC_EGENERIC : VLC_SUCCESS;
}

/* Compact lazy index -----------------------------------------------------
 *
 * XSPF requires every track to be serialized once per view and parses a
 * complete letter before exposing its first row.  The compact index stores
 * media metadata once, then stores lightweight nodes addressed by file
 * offset.  The playlist importer reads only one node per expansion. */
#define PVLC_INDEX_NODE  UINT32_C(0x4e4f4445)
#define PVLC_INDEX_MEDIA UINT32_C(0x4d454449)
#define PVLC_INDEX_CHILD_NODE  1
#define PVLC_INDEX_CHILD_MEDIA 2
#define PVLC_INDEX_FLAG_RANDOM       UINT32_C(0x01)
#define PVLC_INDEX_FLAG_ALBUM_SCOPE  UINT32_C(0x02)
#define PVLC_INDEX_FLAG_RANDOM_TRACK UINT32_C(0x04)
#define PVLC_INDEX_FLAG_ALBUM_NODE   UINT32_C(0x08)
#define PVLC_INDEX_NO_VALUE UINT32_MAX

static const unsigned char pvlc_lazy_index_magic[8] = {
    'P', 'V', 'L', 'C', 'L', 'I', 5, 0
};

/* The portable-player indexes use the same stable on-disk format.  Changes
 * to media-library grouping must invalidate only this cache fingerprint,
 * never masquerade as an incompatible file format. */
#define PVLC_LIBRARY_INDEX_SCHEMA UINT64_C(2)

typedef struct
{
    uint32_t type, flags, value;
    uint64_t offset;
    char *name;
} pvlc_lazy_child_t;

typedef struct
{
    pvlc_lazy_child_t *items;
    size_t count, capacity;
} pvlc_lazy_children_t;

static void pvlc_lazy_children_clear( pvlc_lazy_children_t *children )
{
    for( size_t i = 0; i < children->count; ++i )
        free( children->items[i].name );
    free( children->items );
    memset( children, 0, sizeof( *children ) );
}

static int pvlc_lazy_child_append( pvlc_lazy_children_t *children,
                                   uint32_t type, uint32_t flags,
                                   uint32_t value, uint64_t offset,
                                   const char *name )
{
    char *copy = strdup( name ?: "" );
    if( copy == NULL ) return VLC_ENOMEM;
    if( children->count == children->capacity )
    {
        size_t capacity = children->capacity ? children->capacity * 2 : 16;
        pvlc_lazy_child_t *items = realloc( children->items,
                                            capacity * sizeof( *items ) );
        if( items == NULL )
        {
            free( copy );
            return VLC_ENOMEM;
        }
        children->items = items; children->capacity = capacity;
    }
    children->items[children->count++] = (pvlc_lazy_child_t) {
        type, flags, value, offset, copy
    };
    return VLC_SUCCESS;
}

static int pvlc_lazy_tell( FILE *file, uint64_t *offset )
{
    long position = ftell( file );
    if( position < 0 ) return VLC_EGENERIC;
    *offset = (uint64_t)position;
    return VLC_SUCCESS;
}

static int pvlc_lazy_write_node( FILE *file,
                                 const pvlc_lazy_children_t *children,
                                 uint64_t *offset )
{
    if( children->count > UINT32_MAX
     || pvlc_lazy_tell( file, offset ) != VLC_SUCCESS ) return VLC_EGENERIC;
    int ret = pvlc_binary_write_u32( file, PVLC_INDEX_NODE );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32(
                                      file, (uint32_t)children->count );
    for( size_t i = 0; i < children->count && ret == VLC_SUCCESS; ++i )
    {
        const pvlc_lazy_child_t *child = &children->items[i];
        ret = pvlc_binary_write_u32( file, child->type );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file,
                                                               child->flags );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file,
                                                               child->value );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file, 0 );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file,
                                                               child->offset );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                                                               child->name );
    }
    return ret;
}

static int pvlc_lazy_write_media( FILE *file,
                                  const pvlc_media_entry_t *entry,
                                  uint64_t *offset )
{
    char *uri = vlc_path2uri( entry->psz_path, NULL );
    char *title = pvlc_music_display_title( entry );
    if( uri == NULL || title == NULL )
    { free( uri ); free( title ); return VLC_ENOMEM; }
    int ret = pvlc_lazy_tell( file, offset );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file,
                                                          PVLC_INDEX_MEDIA );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file, uri );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file, title );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                                                       entry->psz_artist );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                                                       entry->psz_album );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                     pvlc_media_meta( entry, vlc_meta_TrackNumber ) ?: "" );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_string( file,
                     pvlc_media_meta( entry, vlc_meta_AlbumArtist ) ?: "" );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( file,
                                                       entry->i_rating );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file,
                                             (uint64_t)entry->i_duration );
    /* Reserved stable source id.  Zero identifies a regular media-library
     * entry; portable-player indexes use this slot for their in-memory DB id
     * without changing the compact reader or touching the device. */
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file, 0 );
    free( uri ); free( title );
    return ret;
}

static uint64_t pvlc_lazy_media_offset( const pvlc_media_catalog_t *catalog,
                                        const uint64_t *offsets,
                                        const pvlc_index_ref_t *ref )
{
    size_t index = (size_t)(ref->entry - catalog->p_entries);
    return index < catalog->i_count ? offsets[index] : 0;
}

typedef struct
{
    const pvlc_media_entry_t *entry;
} pvlc_album_ref_t;

static int pvlc_album_ref_compare( const void *a, const void *b )
{
    const pvlc_media_entry_t *ea = ((const pvlc_album_ref_t *)a)->entry;
    const pvlc_media_entry_t *eb = ((const pvlc_album_ref_t *)b)->entry;
    int result = strcasecmp( pvlc_album_artist( ea ), pvlc_album_artist( eb ) );
    if( !result ) result = strcasecmp( ea->psz_album, eb->psz_album );
    if( !result && pvlc_track_precedes( ea, eb ) ) result = -1;
    if( !result && pvlc_track_precedes( eb, ea ) ) result = 1;
    if( !result ) result = strcasecmp( ea->psz_path, eb->psz_path );
    return result;
}

static int pvlc_album_ref_key_compare( const pvlc_album_ref_t *ref,
                                       const pvlc_media_entry_t *entry )
{
    int result = strcasecmp( pvlc_album_artist( ref->entry ),
                             pvlc_album_artist( entry ) );
    return result ? result : strcasecmp( ref->entry->psz_album,
                                         entry->psz_album );
}

static void pvlc_album_ref_range( const pvlc_album_ref_t *refs, size_t count,
                                  const pvlc_media_entry_t *entry,
                                  size_t *first, size_t *end )
{
    size_t lo = 0, hi = count;
    while( lo < hi )
    {
        size_t mid = lo + (hi - lo) / 2;
        if( pvlc_album_ref_key_compare( &refs[mid], entry ) < 0 ) lo = mid + 1;
        else hi = mid;
    }
    *first = lo;
    hi = count;
    while( lo < hi )
    {
        size_t mid = lo + (hi - lo) / 2;
        if( pvlc_album_ref_key_compare( &refs[mid], entry ) <= 0 ) lo = mid + 1;
        else hi = mid;
    }
    *end = lo;
}

static uint64_t pvlc_lazy_album_media_offset(
    const pvlc_media_catalog_t *catalog, const uint64_t *offsets,
    const pvlc_album_ref_t *ref )
{
    size_t index = (size_t)(ref->entry - catalog->p_entries);
    return index < catalog->i_count ? offsets[index] : 0;
}

static int pvlc_lazy_write_album_ref_node(
    FILE *file, const pvlc_media_catalog_t *catalog,
    const uint64_t *media_offsets, const pvlc_album_ref_t *refs,
    size_t first, size_t end, uint64_t *offset )
{
    pvlc_lazy_children_t children = { 0 };
    int ret = VLC_SUCCESS;
    for( size_t i = first; i < end && ret == VLC_SUCCESS; ++i )
        ret = pvlc_lazy_child_append( &children, PVLC_INDEX_CHILD_MEDIA, 0,
              PVLC_INDEX_NO_VALUE,
              pvlc_lazy_album_media_offset( catalog, media_offsets, &refs[i] ),
              "" );
    if( ret == VLC_SUCCESS ) ret = pvlc_lazy_write_node( file, &children,
                                                         offset );
    pvlc_lazy_children_clear( &children );
    return ret;
}

static int pvlc_lazy_write_ref_node( FILE *file,
                                     const pvlc_media_catalog_t *catalog,
                                     const uint64_t *media_offsets,
                                     const pvlc_index_ref_t *refs,
                                     size_t first, size_t end,
                                     uint64_t *offset )
{
    pvlc_lazy_children_t children = { 0 };
    int ret = VLC_SUCCESS;
    for( size_t i = first; i < end && ret == VLC_SUCCESS; ++i )
        ret = pvlc_lazy_child_append( &children, PVLC_INDEX_CHILD_MEDIA, 0,
              PVLC_INDEX_NO_VALUE,
              pvlc_lazy_media_offset( catalog, media_offsets, &refs[i] ), "" );
    if( ret == VLC_SUCCESS ) ret = pvlc_lazy_write_node( file, &children,
                                                         offset );
    pvlc_lazy_children_clear( &children );
    return ret;
}

static int pvlc_lazy_write_one_ref_node( FILE *file,
                                     const pvlc_media_catalog_t *catalog,
                                     const uint64_t *media_offsets,
                                     const pvlc_index_ref_t *ref,
                                     uint64_t *offset )
{
    pvlc_lazy_children_t children = { 0 };
    int ret = pvlc_lazy_child_append( &children, PVLC_INDEX_CHILD_MEDIA, 0,
               PVLC_INDEX_NO_VALUE,
               pvlc_lazy_media_offset( catalog, media_offsets, ref ), "" );
    if( ret == VLC_SUCCESS ) ret = pvlc_lazy_write_node( file, &children,
                                                         offset );
    pvlc_lazy_children_clear( &children );
    return ret;
}

static size_t pvlc_lazy_random_track( const pvlc_index_ref_t *refs,
                                      size_t first, size_t end )
{
    size_t selected = first;
    for( size_t i = first + 1; i < end; ++i )
        if( refs[i].random_track < refs[selected].random_track ) selected = i;
    return selected;
}

typedef struct
{
    uint64_t node_offset, play_offset, random_key;
    const char *name;
} pvlc_lazy_group_t;

static int pvlc_lazy_write_view( FILE *file,
                                 const pvlc_media_catalog_t *catalog,
                                 const uint64_t *media_offsets,
                                 const pvlc_album_ref_t *album_refs,
                                 size_t album_ref_count,
                                 pvlc_index_ref_t *refs, size_t count,
                                 pvlc_music_view_t view, uint64_t *root_offset,
                                 uint64_t *mask )
{
    *root_offset = 0; *mask = 0;
    if( count == 0 ) return VLC_SUCCESS;
    qsort( refs, count, sizeof( *refs ), pvlc_index_ref_compare );
    if( view == PVLC_VIEW_YEARS )
        for( size_t i = 0; i < count; ++i ) refs[i].primary = refs[i].year_label;

    pvlc_lazy_children_t view_children = { 0 };
    uint64_t top_play = 0, top_key = UINT64_MAX;
    int ret = VLC_SUCCESS;
    for( size_t bucket_first = 0; bucket_first < count && ret == VLC_SUCCESS; )
    {
        size_t bucket_end = bucket_first + 1;
        while( bucket_end < count
            && refs[bucket_end].bucket == refs[bucket_first].bucket ) bucket_end++;
        pvlc_lazy_children_t letter_children = { 0 };
        uint64_t letter_play = 0, letter_key = UINT64_MAX;

        if( !pvlc_view_has_groups( view ) )
        {
            size_t pick = pvlc_lazy_random_track( refs, bucket_first,
                                                   bucket_end );
            uint64_t random_offset;
            ret = pvlc_lazy_write_one_ref_node( file, catalog, media_offsets,
                                                &refs[pick], &random_offset );
            if( ret == VLC_SUCCESS )
                ret = pvlc_lazy_child_append( &letter_children,
                    PVLC_INDEX_CHILD_NODE, PVLC_INDEX_FLAG_RANDOM,
                    PVLC_INDEX_NO_VALUE, random_offset, _( "Random" ) );
            for( size_t i = bucket_first; i < bucket_end && ret == VLC_SUCCESS; ++i )
                ret = pvlc_lazy_child_append( &letter_children,
                    PVLC_INDEX_CHILD_MEDIA, 0, PVLC_INDEX_NO_VALUE,
                    pvlc_lazy_media_offset( catalog, media_offsets, &refs[i] ), "" );
            letter_play = random_offset;
            letter_key = refs[pick].random_track;
        }
        else
        {
            size_t group_capacity = 0, group_count = 0;
            pvlc_lazy_group_t *groups = NULL;
            for( size_t primary = bucket_first; primary < bucket_end; )
            {
                size_t primary_end = pvlc_primary_end( refs, bucket_end,
                                                        primary );
                pvlc_lazy_children_t primary_children = { 0 };
                uint64_t primary_play = 0, primary_key = UINT64_MAX;
                if( pvlc_view_has_albums( view ) )
                {
                    for( size_t album = primary; album < primary_end; )
                    {
                        size_t album_end = pvlc_album_end( refs, primary_end,
                                                           album );
                        size_t complete_first, complete_end;
                        pvlc_album_ref_range( album_refs, album_ref_count,
                                              refs[album].entry,
                                              &complete_first, &complete_end );
                        uint64_t album_play, album_node, random_track_node;
                        size_t pick = complete_first;
                        for( size_t i = complete_first + 1; i < complete_end; ++i )
                            if( pvlc_random_key( catalog->i_fingerprint,
                                                album_refs[i].entry->psz_path )
                              < pvlc_random_key( catalog->i_fingerprint,
                                                album_refs[pick].entry->psz_path ) )
                                pick = i;
                        ret = pvlc_lazy_write_album_ref_node( file, catalog,
                            media_offsets, album_refs, complete_first,
                            complete_end, &album_play );
                        if( ret == VLC_SUCCESS )
                        {
                            pvlc_lazy_children_t random_children = { 0 };
                            ret = pvlc_lazy_child_append( &random_children,
                                PVLC_INDEX_CHILD_MEDIA, 0, PVLC_INDEX_NO_VALUE,
                                pvlc_lazy_album_media_offset( catalog,
                                    media_offsets, &album_refs[pick] ), "" );
                            if( ret == VLC_SUCCESS )
                                ret = pvlc_lazy_write_node( file,
                                    &random_children, &random_track_node );
                            pvlc_lazy_children_clear( &random_children );
                        }
                        pvlc_lazy_children_t album_children = { 0 };
                        if( ret == VLC_SUCCESS )
                            ret = pvlc_lazy_child_append( &album_children,
                                PVLC_INDEX_CHILD_NODE,
                                PVLC_INDEX_FLAG_RANDOM
                              | PVLC_INDEX_FLAG_RANDOM_TRACK
                              | PVLC_INDEX_FLAG_ALBUM_SCOPE,
                                PVLC_INDEX_NO_VALUE, random_track_node,
                                _( "Random (Album Track)" ) );
                        for( size_t i = complete_first;
                             i < complete_end && ret == VLC_SUCCESS; ++i )
                            ret = pvlc_lazy_child_append( &album_children,
                                PVLC_INDEX_CHILD_MEDIA, 0,
                                PVLC_INDEX_NO_VALUE,
                                pvlc_lazy_album_media_offset( catalog,
                                    media_offsets, &album_refs[i] ), "" );
                        if( ret == VLC_SUCCESS )
                            ret = pvlc_lazy_write_node( file, &album_children,
                                                        &album_node );
                        pvlc_lazy_children_clear( &album_children );
                        if( ret == VLC_SUCCESS )
                            ret = pvlc_lazy_child_append( &primary_children,
                                PVLC_INDEX_CHILD_NODE,
                                PVLC_INDEX_FLAG_ALBUM_NODE,
                                PVLC_INDEX_NO_VALUE, album_node,
                                refs[album].entry->psz_album );
                        if( refs[album].random_secondary < primary_key )
                        { primary_key = refs[album].random_secondary;
                          primary_play = album_play; }
                        album = album_end;
                    }
                }
                else
                {
                    uint64_t random_track_node;
                    if( view == PVLC_VIEW_ALBUMS )
                    {
                        size_t complete_first, complete_end;
                        pvlc_album_ref_range( album_refs, album_ref_count,
                                              refs[primary].entry,
                                              &complete_first, &complete_end );
                        size_t pick = complete_first;
                        for( size_t i = complete_first + 1;
                             i < complete_end; ++i )
                            if( pvlc_random_key( catalog->i_fingerprint,
                                                album_refs[i].entry->psz_path )
                              < pvlc_random_key( catalog->i_fingerprint,
                                                album_refs[pick].entry->psz_path ) )
                                pick = i;
                        ret = pvlc_lazy_write_album_ref_node( file, catalog,
                            media_offsets, album_refs, complete_first,
                            complete_end, &primary_play );
                        if( ret == VLC_SUCCESS )
                        {
                            pvlc_lazy_children_t random_children = { 0 };
                            ret = pvlc_lazy_child_append( &random_children,
                                PVLC_INDEX_CHILD_MEDIA, 0,
                                PVLC_INDEX_NO_VALUE,
                                pvlc_lazy_album_media_offset( catalog,
                                    media_offsets, &album_refs[pick] ), "" );
                            if( ret == VLC_SUCCESS )
                                ret = pvlc_lazy_write_node( file,
                                    &random_children, &random_track_node );
                            pvlc_lazy_children_clear( &random_children );
                        }
                        for( size_t i = complete_first;
                             i < complete_end && ret == VLC_SUCCESS; ++i )
                            ret = pvlc_lazy_child_append( &primary_children,
                                PVLC_INDEX_CHILD_MEDIA, 0,
                                PVLC_INDEX_NO_VALUE,
                                pvlc_lazy_album_media_offset( catalog,
                                    media_offsets, &album_refs[i] ), "" );
                    }
                    else
                    {
                        size_t pick = pvlc_lazy_random_track( refs, primary,
                                                              primary_end );
                        ret = pvlc_lazy_write_ref_node( file, catalog,
                            media_offsets, refs, primary, primary_end,
                            &primary_play );
                        if( ret == VLC_SUCCESS )
                            ret = pvlc_lazy_write_one_ref_node( file, catalog,
                                media_offsets, &refs[pick],
                                &random_track_node );
                        for( size_t i = primary;
                             i < primary_end && ret == VLC_SUCCESS; ++i )
                            ret = pvlc_lazy_child_append( &primary_children,
                                PVLC_INDEX_CHILD_MEDIA, 0,
                                PVLC_INDEX_NO_VALUE,
                                pvlc_lazy_media_offset( catalog, media_offsets,
                                                        &refs[i] ), "" );
                    }
                    if( ret == VLC_SUCCESS )
                        ret = pvlc_lazy_child_append( &primary_children,
                            PVLC_INDEX_CHILD_NODE,
                            PVLC_INDEX_FLAG_RANDOM
                          | PVLC_INDEX_FLAG_RANDOM_TRACK
                          | PVLC_INDEX_FLAG_ALBUM_SCOPE,
                            PVLC_INDEX_NO_VALUE, random_track_node,
                            _( "Random (Album Track)" ) );
                    primary_key = refs[primary].random_primary;
                }
                if( ret == VLC_SUCCESS && pvlc_view_has_albums( view ) )
                    ret = pvlc_lazy_child_append( &primary_children,
                        PVLC_INDEX_CHILD_NODE,
                        PVLC_INDEX_FLAG_RANDOM | PVLC_INDEX_FLAG_ALBUM_SCOPE,
                        PVLC_INDEX_NO_VALUE, primary_play,
                        _( "Random (Album)" ) );
                /* Put the action first without repeatedly shifting while the
                 * group is assembled. */
                if( primary_children.count > 1 )
                {
                    pvlc_lazy_child_t action = primary_children.items[
                                                primary_children.count - 1];
                    memmove( &primary_children.items[1],
                             &primary_children.items[0],
                             (primary_children.count - 1)
                               * sizeof( *primary_children.items ) );
                    primary_children.items[0] = action;
                }
                uint64_t primary_node = 0;
                if( ret == VLC_SUCCESS ) ret = pvlc_lazy_write_node( file,
                                         &primary_children, &primary_node );
                pvlc_lazy_children_clear( &primary_children );
                if( group_count == group_capacity && ret == VLC_SUCCESS )
                {
                    size_t capacity = group_capacity ? group_capacity * 2 : 16;
                    pvlc_lazy_group_t *grown = realloc( groups,
                                                capacity * sizeof( *grown ) );
                    if( grown == NULL ) ret = VLC_ENOMEM;
                    else { groups = grown; group_capacity = capacity; }
                }
                if( ret == VLC_SUCCESS ) groups[group_count++] =
                    (pvlc_lazy_group_t){ primary_node, primary_play,
                                         primary_key, refs[primary].primary };
                primary = primary_end;
            }
            for( size_t i = 0; i < group_count && ret == VLC_SUCCESS; ++i )
            {
                ret = pvlc_lazy_child_append( &letter_children,
                    PVLC_INDEX_CHILD_NODE,
                    view == PVLC_VIEW_ALBUMS ? PVLC_INDEX_FLAG_ALBUM_NODE : 0,
                    PVLC_INDEX_NO_VALUE, groups[i].node_offset, groups[i].name );
                if( groups[i].random_key < letter_key )
                { letter_key = groups[i].random_key;
                  letter_play = groups[i].play_offset; }
            }
            free( groups );
            if( ret == VLC_SUCCESS )
                ret = pvlc_lazy_child_append( &letter_children,
                    PVLC_INDEX_CHILD_NODE,
                    PVLC_INDEX_FLAG_RANDOM | PVLC_INDEX_FLAG_ALBUM_SCOPE,
                    PVLC_INDEX_NO_VALUE, letter_play, _( "Random (Album)" ) );
            if( letter_children.count > 1 )
            {
                pvlc_lazy_child_t action = letter_children.items[
                                                letter_children.count - 1];
                memmove( &letter_children.items[1], &letter_children.items[0],
                         (letter_children.count - 1)
                           * sizeof( *letter_children.items ) );
                letter_children.items[0] = action;
            }
        }
        uint64_t letter_offset = 0;
        if( ret == VLC_SUCCESS ) ret = pvlc_lazy_write_node( file,
                                      &letter_children, &letter_offset );
        pvlc_lazy_children_clear( &letter_children );
        if( ret == VLC_SUCCESS )
        {
            char label[2];
            ret = pvlc_lazy_child_append( &view_children,
                PVLC_INDEX_CHILD_NODE, 0, refs[bucket_first].bucket,
                letter_offset, pvlc_view_bucket_label( view,
                                      refs[bucket_first].bucket, label ) );
            *mask |= UINT64_C(1) << refs[bucket_first].bucket;
            if( letter_key < top_key )
            { top_key = letter_key; top_play = letter_play; }
        }
        bucket_first = bucket_end;
    }
    if( ret == VLC_SUCCESS )
        ret = pvlc_lazy_child_append( &view_children,
            PVLC_INDEX_CHILD_NODE, PVLC_INDEX_FLAG_RANDOM
              | (pvlc_view_random_selects_album( view )
                 ? PVLC_INDEX_FLAG_ALBUM_SCOPE : 0),
            PVLC_INDEX_NO_VALUE, top_play,
            pvlc_view_random_selects_album( view )
                ? _( "Random (Album)" ) : _( "Random" ) );
    if( view_children.count > 1 )
    {
        pvlc_lazy_child_t action = view_children.items[view_children.count - 1];
        memmove( &view_children.items[1], &view_children.items[0],
                 (view_children.count - 1) * sizeof( *view_children.items ) );
        view_children.items[0] = action;
    }
    if( ret == VLC_SUCCESS ) ret = pvlc_lazy_write_node( file, &view_children,
                                                         root_offset );
    pvlc_lazy_children_clear( &view_children );
    return ret;
}

static char *pvlc_lazy_index_path( const char *directory )
{
    return pvlc_path_join( directory, "music-index.pvli" );
}

static int pvlc_load_lazy_index( const char *directory, uint64_t fingerprint,
                                 uint64_t roots[PVLC_VIEW_COUNT],
                                 uint64_t masks[PVLC_VIEW_COUNT] )
{
    char *path = pvlc_lazy_index_path( directory );
    FILE *file = path ? vlc_fopen( path, "rb" ) : NULL;
    free( path );
    if( file == NULL ) return VLC_EGENERIC;
    unsigned char magic[8]; uint64_t stored;
    int ret = pvlc_binary_read( file, magic, sizeof( magic ) );
    if( ret == VLC_SUCCESS && memcmp( magic, pvlc_lazy_index_magic,
                                      sizeof( magic ) ) ) ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file, &stored );
    if( ret == VLC_SUCCESS && stored != fingerprint ) ret = VLC_EGENERIC;
    for( size_t i = 0; i < PVLC_VIEW_COUNT && ret == VLC_SUCCESS; ++i )
        ret = pvlc_binary_read_u64( file, &roots[i] );
    for( size_t i = 0; i < PVLC_VIEW_COUNT && ret == VLC_SUCCESS; ++i )
        ret = pvlc_binary_read_u64( file, &masks[i] );
    fclose( file );
    return ret;
}

static int pvlc_prepare_lazy_index( const pvlc_media_catalog_t *catalog,
                                    char **path_out,
                                    uint64_t roots[PVLC_VIEW_COUNT],
                                    uint64_t masks[PVLC_VIEW_COUNT] )
{
    const uint64_t index_fingerprint = catalog->i_fingerprint
                                     ^ (PVLC_LIBRARY_INDEX_SCHEMA
                                        * UINT64_C(0x9e3779b97f4a7c15));
    char *directory = pvlc_music_index_directory();
    if( directory == NULL ) return VLC_ENOMEM;
    *path_out = pvlc_lazy_index_path( directory );
    if( *path_out == NULL ) { free( directory ); return VLC_ENOMEM; }
    if( pvlc_load_lazy_index( directory, index_fingerprint,
                              roots, masks ) == VLC_SUCCESS )
    { free( directory ); return VLC_SUCCESS; }

    char *temporary = NULL;
    if( asprintf( &temporary, "%s.tmp", *path_out ) < 0 ) temporary = NULL;
    FILE *file = temporary ? vlc_fopen( temporary, "wb" ) : NULL;
    if( file == NULL )
    { free( temporary ); free( directory ); return VLC_EGENERIC; }
    setvbuf( file, NULL, _IOFBF, 64 * 1024 );
    unsigned char header[8 + 8 + PVLC_VIEW_COUNT * 16] = { 0 };
    int ret = pvlc_binary_write( file, header, sizeof( header ) );
    uint64_t *media_offsets = calloc( catalog->i_count,
                                       sizeof( *media_offsets ) );
    size_t audio_count = 0;
    for( size_t i = 0; i < catalog->i_count; ++i )
        if( catalog->p_entries[i].i_type == PVLC_MEDIA_AUDIO ) audio_count++;
    pvlc_index_ref_t *refs = malloc( audio_count * sizeof( *refs ) );
    pvlc_album_ref_t *album_refs = malloc( audio_count * sizeof( *album_refs ) );
    if( catalog->i_count && media_offsets == NULL ) ret = VLC_ENOMEM;
    if( audio_count && refs == NULL ) ret = VLC_ENOMEM;
    if( audio_count && album_refs == NULL ) ret = VLC_ENOMEM;
    size_t album_ref_count = 0;
    for( size_t i = 0; i < catalog->i_count && ret == VLC_SUCCESS; ++i )
        if( catalog->p_entries[i].i_type == PVLC_MEDIA_AUDIO )
        {
            ret = pvlc_lazy_write_media( file, &catalog->p_entries[i],
                                          &media_offsets[i] );
            album_refs[album_ref_count++].entry = &catalog->p_entries[i];
        }
    qsort( album_refs, album_ref_count, sizeof( *album_refs ),
           pvlc_album_ref_compare );
    memset( roots, 0, PVLC_VIEW_COUNT * sizeof( *roots ) );
    memset( masks, 0, PVLC_VIEW_COUNT * sizeof( *masks ) );
    for( unsigned view = 0; view < PVLC_VIEW_COUNT && ret == VLC_SUCCESS; ++view )
    {
        size_t out = 0;
        for( size_t i = 0; i < catalog->i_count; ++i )
            if( catalog->p_entries[i].i_type == PVLC_MEDIA_AUDIO )
            {
                if( view == PVLC_VIEW_RATINGS
                 && catalog->p_entries[i].i_rating == 0 ) continue;
                pvlc_index_ref_t *ref = &refs[out++];
                memset( ref, 0, sizeof( *ref ) );
                ref->entry = &catalog->p_entries[i]; ref->view = view;
                ref->primary = pvlc_view_primary( ref, view );
                ref->bucket = pvlc_view_bucket( view, ref->primary,
                                                ref->rating );
                uint64_t seed = catalog->i_fingerprint
                              ^ ((uint64_t)view << 56);
                ref->random_primary = pvlc_random_key( seed, ref->primary );
                ref->random_secondary = pvlc_random_key(
                    ref->random_primary, ref->secondary );
                ref->random_track = pvlc_random_key( ref->random_secondary,
                                                     ref->entry->psz_path );
            }
        ret = pvlc_lazy_write_view( file, catalog, media_offsets, album_refs,
                                     album_ref_count, refs, out, view,
                                     &roots[view], &masks[view] );
    }
    if( ret == VLC_SUCCESS && fseek( file, 0, SEEK_SET ) != 0 )
        ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write( file,
                         pvlc_lazy_index_magic, sizeof( pvlc_lazy_index_magic ) );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file,
                                                   index_fingerprint );
    for( size_t i = 0; i < PVLC_VIEW_COUNT && ret == VLC_SUCCESS; ++i )
        ret = pvlc_binary_write_u64( file, roots[i] );
    for( size_t i = 0; i < PVLC_VIEW_COUNT && ret == VLC_SUCCESS; ++i )
        ret = pvlc_binary_write_u64( file, masks[i] );
    bool error = ret != VLC_SUCCESS || fflush( file ) != 0 || ferror( file );
    if( fclose( file ) != 0 ) error = true;
    if( !error ) error = vlc_rename( temporary, *path_out ) != 0;
    if( error ) vlc_unlink( temporary );
    free( album_refs ); free( refs ); free( media_offsets );
    free( temporary ); free( directory );
    return error ? VLC_EGENERIC : VLC_SUCCESS;
}

static const unsigned char pvlc_index_magic[8] = {
    'P', 'V', 'L', 'C', 'I', 'X', 18, 0
};

static int pvlc_load_index_manifest( const char *directory,
                                     uint64_t fingerprint,
                                     uint64_t masks[PVLC_VIEW_COUNT] )
{
    char *path = pvlc_path_join( directory, "index.db" );
    FILE *file = path ? vlc_fopen( path, "rb" ) : NULL;
    free( path );
    if( file == NULL ) return VLC_EGENERIC;
    unsigned char magic[8]; uint64_t stored;
    int ret = pvlc_binary_read( file, magic, sizeof( magic ) );
    if( ret == VLC_SUCCESS && memcmp( magic, pvlc_index_magic,
                                      sizeof( magic ) ) ) ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file, &stored );
    if( ret == VLC_SUCCESS && stored != fingerprint ) ret = VLC_EGENERIC;
    for( size_t i = 0; i < PVLC_VIEW_COUNT && ret == VLC_SUCCESS; ++i )
        ret = pvlc_binary_read_u64( file, &masks[i] );
    fclose( file );
    return ret;
}

static int pvlc_save_index_manifest( const char *directory,
                                     uint64_t fingerprint,
                                     const uint64_t masks[PVLC_VIEW_COUNT] )
{
    char *path = pvlc_path_join( directory, "index.db" );
    char *temporary = path ? pvlc_path_join( directory, "index.db.tmp" ) : NULL;
    FILE *file = temporary ? vlc_fopen( temporary, "wb" ) : NULL;
    if( file == NULL ) { free( path ); free( temporary ); return VLC_EGENERIC; }
    int ret = pvlc_binary_write( file, pvlc_index_magic,
                                 sizeof( pvlc_index_magic ) );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file, fingerprint );
    for( size_t i = 0; i < PVLC_VIEW_COUNT && ret == VLC_SUCCESS; ++i )
        ret = pvlc_binary_write_u64( file, masks[i] );
    bool error = ret != VLC_SUCCESS || fflush( file ) != 0 || ferror( file );
    if( fclose( file ) != 0 ) error = true;
    if( !error ) error = vlc_rename( temporary, path ) != 0;
    if( error ) vlc_unlink( temporary );
    free( path ); free( temporary );
    return error ? VLC_EGENERIC : VLC_SUCCESS;
}

static int pvlc_prepare_music_index( const pvlc_media_catalog_t *catalog,
                                     char **directory_out,
                                     uint64_t masks[PVLC_VIEW_COUNT] )
{
    *directory_out = pvlc_music_index_directory();
    if( *directory_out == NULL ) return VLC_ENOMEM;
    if( pvlc_load_index_manifest( *directory_out, catalog->i_fingerprint,
                                  masks ) == VLC_SUCCESS )
        return VLC_SUCCESS;

    size_t count = 0;
    for( size_t i = 0; i < catalog->i_count; ++i )
        if( catalog->p_entries[i].i_type == PVLC_MEDIA_AUDIO ) count++;
    pvlc_index_ref_t *refs = malloc( count * sizeof( *refs ) );
    if( count && refs == NULL ) return VLC_ENOMEM;
    memset( masks, 0, PVLC_VIEW_COUNT * sizeof( *masks ) );
    int ret = VLC_SUCCESS;
    for( unsigned view = 0; view < PVLC_VIEW_COUNT && ret == VLC_SUCCESS; ++view )
    {
        size_t out = 0;
        for( size_t i = 0; i < catalog->i_count; ++i )
            if( catalog->p_entries[i].i_type == PVLC_MEDIA_AUDIO )
            {
                if( view == PVLC_VIEW_RATINGS
                 && catalog->p_entries[i].i_rating == 0 ) continue;
                pvlc_index_ref_t *ref = &refs[out++];
                memset( ref, 0, sizeof( *ref ) );
                ref->entry = &catalog->p_entries[i]; ref->view = view;
                ref->primary = pvlc_view_primary( ref, view );
                ref->bucket = pvlc_view_bucket( view, ref->primary,
                                                ref->rating );
                uint64_t seed = catalog->i_fingerprint
                              ^ ((uint64_t)view << 56);
                ref->random_primary = pvlc_random_key( seed, ref->primary );
                ref->random_secondary = pvlc_random_key(
                    ref->random_primary, ref->secondary );
                ref->random_track = pvlc_random_key( ref->random_secondary,
                                                     ref->entry->psz_path );
            }
        qsort( refs, out, sizeof( *refs ), pvlc_index_ref_compare );
        /* The year label is stored inside each sortable record. qsort moves
         * records, so pointers captured before sorting would otherwise keep
         * referring to the old slots and split one year into several
         * apparently unordered groups. Rebind them after the move. */
        if( view == PVLC_VIEW_YEARS )
            for( size_t i = 0; i < out; ++i )
                refs[i].primary = refs[i].year_label;
        for( size_t first = 0; first < out; )
        {
            size_t end = first + 1;
            while( end < out && refs[end].bucket == refs[first].bucket ) end++;
            unsigned bucket = refs[first].bucket;
            char *path = pvlc_music_bucket_path( *directory_out, view, bucket );
            if( path == NULL ) ret = VLC_ENOMEM;
            else ret = pvlc_write_music_bucket( path, &refs[first],
                                                 end - first, view );
            free( path );
            if( ret != VLC_SUCCESS ) break;
            masks[view] |= UINT64_C(1) << bucket;
            first = end;
        }
        if( ret == VLC_SUCCESS && out > 0 )
        {
            char *path = pvlc_music_random_path( *directory_out, view );
            if( path == NULL ) ret = VLC_ENOMEM;
            else ret = pvlc_write_music_random( path, refs, out, view );
            free( path );
        }
    }
    free( refs );
    if( ret == VLC_SUCCESS )
        ret = pvlc_save_index_manifest( *directory_out,
                                        catalog->i_fingerprint, masks );
    return ret;
}

static input_item_t *pvlc_add_lazy_letter( services_discovery_t *sd,
                                          input_item_t *parent,
                                          const char *directory,
                                          pvlc_music_view_t view,
                                          unsigned bucket )
{
    char *path = pvlc_music_bucket_path( directory, view, bucket );
    char *uri = path ? vlc_path2uri( path, NULL ) : NULL;
    char label[2];
    input_item_t *item = uri ? input_item_NewExt( uri,
                                pvlc_view_bucket_label( view, bucket, label ), -1,
                                ITEM_TYPE_DIRECTORY, ITEM_LOCAL ) : NULL;
    if( item )
    {
        char option[64];
        snprintf( option, sizeof( option ), "%s%u",
                  VLC_INPUT_OPTION_POWERVLC_LIBRARY_BUCKET_PREFIX, bucket );
        input_item_AddOption( item, option, 0 );
        services_discovery_AddSubItem( sd, parent, item );
    }
    free( uri ); free( path );
    return item;
}

static input_item_t *pvlc_add_lazy_random( services_discovery_t *sd,
                                          input_item_t *parent,
                                          const char *directory,
                                          pvlc_music_view_t view )
{
    char *path = pvlc_music_random_path( directory, view );
    char *uri = path ? vlc_path2uri( path, NULL ) : NULL;
    const char *label = pvlc_view_random_selects_album( view )
                      ? _( "Random (Album)" ) : _( "Random" );
    /* This is a lazy XSPF action, just like a letter bucket: it must enter
     * the directory/preparser path before the interfaces can play the
     * generated private letter -> artist -> album -> track selection.
     * Random actions are hidden as leaves by each UI, so DIRECTORY does not
     * expose a disclosure triangle to the user. */
    input_item_t *item = uri ? input_item_NewExt( uri, label, -1,
                                ITEM_TYPE_DIRECTORY, ITEM_LOCAL ) : NULL;
    if( item )
    {
        input_item_AddOption( item,
            VLC_INPUT_OPTION_POWERVLC_RANDOM_ACTION, 0 );
        if( pvlc_view_random_selects_album( view ) )
            input_item_AddOption( item,
                VLC_INPUT_OPTION_POWERVLC_ALBUM_SCOPE, 0 );
        services_discovery_AddSubItem( sd, parent, item );
    }
    free( uri ); free( path );
    return item;
}

static input_item_t *pvlc_add_music_view( services_discovery_t *sd,
                                         input_item_t *root,
                                         const char *directory,
                                         const uint64_t masks[PVLC_VIEW_COUNT],
                                         unsigned view )
{
    static const char *const labels[PVLC_VIEW_COUNT] = {
        N_( "Album Artists" ), N_( "Artists" ), N_( "Albums" ),
        N_( "Genres" ), N_( "Composers" ), N_( "Years" ),
        N_( "Tracks" ), N_( "Recently Added" ), N_( "Ratings" )
    };
    input_item_t *node = pvlc_add_node( sd, root, _( labels[view] ) );
    if( node == NULL ) return NULL;
    char option[64];
    snprintf( option, sizeof( option ), "%s%u",
              VLC_INPUT_OPTION_POWERVLC_LIBRARY_VIEW_PREFIX, view );
    input_item_AddOption( node, option, 0 );
    if( masks[view] )
    {
        input_item_t *random = pvlc_add_lazy_random( sd, node, directory,
                                                    view );
        if( random ) input_item_Release( random );
    }
    for( unsigned step = 0; step < PVLC_LETTER_BUCKETS; ++step )
    {
        /* Year buckets are digits, so their outer lazy groups also need to
         * run newest-century first. Keep the two special buckets after the
         * digits, in the same '#' then '?' order as every other view. */
        unsigned bucket = step;
        if( view == PVLC_VIEW_YEARS )
        {
            if( step < 10 ) bucket = 35 - step;
            else if( step == 10 ) bucket = PVLC_OTHER_BUCKET;
            else if( step == 11 ) bucket = PVLC_UNKNOWN_BUCKET;
            else bucket = step - 12;
        }
        if( masks[view] & (UINT64_C(1) << bucket) )
        {
            input_item_t *letter = pvlc_add_lazy_letter( sd, node,
                                  directory, view, bucket );
            if( letter ) input_item_Release( letter );
        }
    }
    return node;
}

static input_item_t *pvlc_add_compact_music_view( services_discovery_t *sd,
                                                  input_item_t *root,
                                                  const char *path,
                                                  uint64_t offset,
                                                  unsigned view )
{
    static const char *const labels[PVLC_VIEW_COUNT] = {
        N_( "Album Artists" ), N_( "Artists" ), N_( "Albums" ),
        N_( "Genres" ), N_( "Composers" ), N_( "Years" ),
        N_( "Tracks" ), N_( "Recently Added" ), N_( "Ratings" )
    };
    char *base = vlc_path2uri( path, NULL ), *uri = NULL;
    if( base && asprintf( &uri, "%s#%" PRIu64, base, offset ) < 0 ) uri = NULL;
    input_item_t *node = uri ? input_item_NewExt( uri, _( labels[view] ), -1,
                                ITEM_TYPE_DIRECTORY, ITEM_LOCAL ) : NULL;
    if( node )
    {
        input_item_AddOption( node,
            VLC_INPUT_OPTION_POWERVLC_LAZY_INDEX, 0 );
        char offset_option[64];
        snprintf( offset_option, sizeof( offset_option ), "%s%" PRIu64,
                  VLC_INPUT_OPTION_POWERVLC_INDEX_OFFSET_PREFIX, offset );
        input_item_AddOption( node, offset_option, 0 );
        char option[64];
        snprintf( option, sizeof( option ), "%s%u",
                  VLC_INPUT_OPTION_POWERVLC_LIBRARY_VIEW_PREFIX, view );
        input_item_AddOption( node, option, 0 );
        services_discovery_AddSubItem( sd, root, node );
    }
    free( uri ); free( base );
    return node;
}

static void pvlc_build_music( services_discovery_t *sd, input_item_t *root,
                              const pvlc_media_catalog_t *catalog )
{
    services_discovery_sys_t *sys = sd->p_sys;
    char *path = NULL;
    uint64_t roots[PVLC_VIEW_COUNT], masks[PVLC_VIEW_COUNT];
    if( pvlc_prepare_lazy_index( catalog, &path, roots, masks ) != VLC_SUCCESS )
    { free( path ); return; }
    for( unsigned view = 0; view < PVLC_VIEW_COUNT; ++view )
    {
        if( roots[view] == 0 ) continue;
        input_item_t *node = pvlc_add_compact_music_view( sd, root, path,
                                                          roots[view], view );
        if( node == NULL ) continue;
        if( view == PVLC_VIEW_RATINGS )
            sys->p_rating_node = input_item_Hold( node );
        input_item_Release( node );
    }
    free( path );
}

static int pvlc_video_path_compare( const void *a, const void *b )
{
    const pvlc_media_entry_t *ea = *(const pvlc_media_entry_t *const *)a;
    const pvlc_media_entry_t *eb = *(const pvlc_media_entry_t *const *)b;
    return strcasecmp( ea->psz_relative, eb->psz_relative );
}

/* Videos deliberately mirror their configured filesystem hierarchy.  This
 * keeps the index cheap and predictable for films and series alike. */
static void pvlc_build_videos( services_discovery_t *sd, input_item_t *root,
                               const pvlc_media_catalog_t *catalog )
{
    size_t count = 0;
    for( size_t i = 0; i < catalog->i_count; ++i )
        if( catalog->p_entries[i].i_type == PVLC_MEDIA_VIDEO ) count++;
    const pvlc_media_entry_t **items = malloc( count * sizeof( *items ) );
    if( count && items == NULL ) return;
    count = 0;
    for( size_t i = 0; i < catalog->i_count; ++i )
        if( catalog->p_entries[i].i_type == PVLC_MEDIA_VIDEO )
            items[count++] = &catalog->p_entries[i];
    qsort( items, count, sizeof( *items ), pvlc_video_path_compare );

    /* Video browsing stays deliberately raw. "Random" therefore opens one
     * real containing folder instead of selecting a movie or parsing tags. */
    if( count > 0 )
    {
        size_t choice = (size_t)(catalog->i_fingerprint % count);
        char *directory = strdup( items[choice]->psz_path );
        char *slash = directory ? strrchr( directory, '/' ) : NULL;
#ifdef _WIN32
        char *backslash = directory ? strrchr( directory, '\\' ) : NULL;
        if( backslash && (!slash || backslash > slash) ) slash = backslash;
#endif
        if( slash ) *slash = '\0';
        char *uri = directory && slash ? vlc_path2uri( directory, NULL ) : NULL;
        input_item_t *random = uri ? input_item_NewExt( uri, _( "Random" ), -1,
                                     ITEM_TYPE_DIRECTORY, ITEM_LOCAL ) : NULL;
        if( random )
        {
            services_discovery_AddSubItem( sd, root, random );
            input_item_Release( random );
        }
        free( uri ); free( directory );
    }

    input_item_t *nodes[65] = { NULL };
    char *previous[65] = { NULL };
    size_t previous_count = 0;
    for( size_t i = 0; i < count; ++i )
    {
        char *path = strdup( items[i]->psz_relative );
        if( path == NULL ) continue;
        for( char *p = path; *p; ++p ) if( *p == '\\' ) *p = '/';
        char *parts[66]; size_t part_count = 0; char *save = NULL;
        for( char *part = strtok_r( path, "/", &save );
             part && part_count < ARRAY_SIZE( parts );
             part = strtok_r( NULL, "/", &save ) )
            parts[part_count++] = part;
        size_t directory_count = part_count > 0 ? part_count - 1 : 0;
        if( directory_count > ARRAY_SIZE( nodes ) )
            directory_count = ARRAY_SIZE( nodes );
        size_t common = 0;
        while( common < directory_count && common < previous_count
            && !strcasecmp( previous[common], parts[common] ) ) common++;
        for( size_t d = previous_count; d > common; --d )
        {
            if( nodes[d - 1] ) input_item_Release( nodes[d - 1] );
            nodes[d - 1] = NULL;
            free( previous[d - 1] ); previous[d - 1] = NULL;
        }
        for( size_t d = common; d < directory_count; ++d )
        {
            nodes[d] = pvlc_add_node( sd, d ? nodes[d - 1] : root, parts[d] );
            previous[d] = strdup( parts[d] );
        }
        previous_count = directory_count;
        input_item_t *parent = previous_count ? nodes[previous_count - 1] : root;
        if( parent ) pvlc_add_media( sd, parent, items[i] );
        free( path );
    }
    for( size_t d = 0; d < previous_count; ++d )
    {
        if( nodes[d] ) input_item_Release( nodes[d] );
        free( previous[d] );
    }
    free( items );
}

static void pvlc_release_results( pvlc_smart_result_t *results, size_t count )
{
    if( results == NULL ) return;
    for( size_t i = 0; i < count; ++i ) free( results[i].p_indices );
    free( results );
}

static void pvlc_remove_roots( services_discovery_t *sd )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( sys->p_rating_node )
    {
        input_item_Release( sys->p_rating_node );
        sys->p_rating_node = NULL;
    }
    for( size_t i = 0; i < ARRAY_SIZE( sys->pp_roots ); ++i )
        if( sys->pp_roots[i] )
        {
            services_discovery_RemoveItem( sd, sys->pp_roots[i] );
            input_item_Release( sys->pp_roots[i] );
            sys->pp_roots[i] = NULL;
        }
}

static void pvlc_populate_smart_root( services_discovery_t *sd,
                             input_item_t *root,
                             const pvlc_media_catalog_t *catalog,
                             const pvlc_smart_playlist_t *smart,
                             size_t smart_count, uint64_t definitions )
{
    pvlc_smart_result_t *results = NULL;
    if( pvlc_load_smart_cache( catalog, smart, smart_count, definitions,
                               &results ) != VLC_SUCCESS )
    {
        if( pvlc_compute_smart( catalog, smart, smart_count, &results )
            == VLC_SUCCESS )
            pvlc_save_smart_cache( catalog, smart, smart_count, definitions,
                                   results );
    }
    if( results && root )
        for( size_t s = 0; s < smart_count; ++s )
        {
            input_item_t *node = pvlc_add_node( sd, root,
                                                smart[s].psz_name );
            if( node )
            {
                for( size_t i = 0; i < results[s].i_count; ++i )
                    pvlc_add_media( sd, node,
                        &catalog->p_entries[results[s].p_indices[i]] );
                input_item_Release( node );
            }
        }
    pvlc_release_results( results, smart_count );
}

static size_t pvlc_catalog_type_count( const pvlc_media_catalog_t *catalog,
                                       pvlc_media_type_t type )
{
    size_t count = 0;
    for( size_t i = 0; i < catalog->i_count; ++i )
        if( catalog->p_entries[i].i_type == type ) ++count;
    return count;
}

static input_item_t *pvlc_add_counted_root( services_discovery_t *sd,
                                            const char *name, size_t count )
{
    char *label = NULL;
    if( asprintf( &label, "%s (%zu)", name, count ) < 0 ) label = NULL;
    input_item_t *item = pvlc_add_node( sd, NULL, label ? label : name );
    free( label );
    return item;
}

static void pvlc_update_scan_report_root( services_discovery_t *sd,
                              const pvlc_scan_report_summary_t *report )
{
    services_discovery_sys_t *sys = sd->p_sys;
    size_t total = report->i_unsupported + report->i_hidden
                 + report->i_unavailable + report->i_unreadable_directories;
    if( !memcmp( &sys->visible_scan_report, report, sizeof( *report ) )
     && ((total == 0 && sys->pp_roots[4] == NULL)
      || (total > 0 && sys->pp_roots[4] != NULL)) )
        return;
    sys->visible_scan_report = *report;
    if( sys->pp_roots[4] )
    {
        services_discovery_RemoveItem( sd, sys->pp_roots[4] );
        input_item_Release( sys->pp_roots[4] );
        sys->pp_roots[4] = NULL;
    }
    if( total == 0 ) return;
    input_item_t *root = pvlc_add_counted_root( sd, _( "Not indexed" ),
                                                total );
    sys->pp_roots[4] = root;
    if( root == NULL ) return;
    struct { const char *name; size_t count; } reasons[] = {
        { N_( "Unsupported format" ), report->i_unsupported },
        { N_( "Hidden item" ), report->i_hidden },
        { N_( "Unavailable file" ), report->i_unavailable },
        { N_( "Unreadable folder" ), report->i_unreadable_directories },
    };
    for( size_t i = 0; i < ARRAY_SIZE( reasons ); ++i )
    {
        if( reasons[i].count == 0 ) continue;
        char *label = NULL;
        if( asprintf( &label, "%s (%zu)", _( reasons[i].name ),
                      reasons[i].count ) < 0 ) label = NULL;
        input_item_t *node = pvlc_add_node( sd, root,
                                    label ? label : _( reasons[i].name ) );
        free( label );
        if( node ) input_item_Release( node );
    }
}

static void pvlc_set_root_scan_state( services_discovery_t *sd,
                                      const char *state )
{
    services_discovery_sys_t *sys = sd->p_sys;
    static const char *const names[] = { N_( "Music" ), N_( "Videos" ) };
    for( size_t i = 0; i < ARRAY_SIZE( names ); ++i )
    {
        if( sys->pp_roots[i] == NULL ) continue;
        char *label = NULL;
        if( asprintf( &label, "%s (%s)", _( names[i] ), state ) >= 0 )
        {
            input_item_SetName( sys->pp_roots[i], label );
            free( label );
        }
    }
}

static void pvlc_set_root_counts( services_discovery_t *sd,
                                  const pvlc_media_catalog_t *catalog )
{
    services_discovery_sys_t *sys = sd->p_sys;
    static const char *const names[] = { N_( "Music" ), N_( "Videos" ) };
    const pvlc_media_type_t types[] = { PVLC_MEDIA_AUDIO, PVLC_MEDIA_VIDEO };
    for( size_t i = 0; i < ARRAY_SIZE( names ); ++i )
    {
        if( sys->pp_roots[i] == NULL ) continue;
        char *label = NULL;
        size_t count = pvlc_catalog_type_count( catalog, types[i] );
        if( asprintf( &label, "%s (%zu)", _( names[i] ), count ) >= 0 )
        {
            input_item_SetName( sys->pp_roots[i], label );
            free( label );
        }
    }
}

static void pvlc_build_tree( services_discovery_t *sd,
                             const pvlc_media_catalog_t *catalog,
                             const pvlc_smart_playlist_t *smart,
                             size_t smart_count, uint64_t definitions )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( sys->i_visible_fingerprint == catalog->i_fingerprint
     && sys->i_visible_definitions == definitions
     && sys->pp_roots[3] != NULL )
    {
        /* A scan temporarily annotates the existing roots.  Even when its
         * result has the same fingerprint, restore the authoritative counts
         * instead of leaving "scanning..." visible forever. */
        pvlc_set_root_counts( sd, catalog );
        return;
    }
    pvlc_remove_roots( sd );
    sys->pp_roots[0] = pvlc_add_counted_root( sd, _( "Music" ),
        pvlc_catalog_type_count( catalog, PVLC_MEDIA_AUDIO ) );
    sys->pp_roots[1] = pvlc_add_counted_root( sd, _( "Videos" ),
        pvlc_catalog_type_count( catalog, PVLC_MEDIA_VIDEO ) );
    sys->pp_roots[2] = pvlc_add_node( sd, NULL, _( "Smart Playlists" ) );
    sys->pp_roots[3] = pvlc_add_node( sd, NULL, _( "Playlists" ) );
    if( sys->pp_roots[3] )
    {
        input_item_AddOption( sys->pp_roots[3],
            VLC_INPUT_OPTION_POWERVLC_USER_PLAYLISTS_ROOT, 0 );
        pvlc_user_load( sd, sys->pp_roots[3] );
    }
    if( sys->pp_roots[0] ) pvlc_build_music( sd, sys->pp_roots[0], catalog );
    if( sys->pp_roots[1] )
        pvlc_build_videos( sd, sys->pp_roots[1], catalog );

    pvlc_populate_smart_root( sd, sys->pp_roots[2], catalog, smart,
                              smart_count, definitions );
    sys->i_visible_fingerprint = catalog->i_fingerprint;
    sys->i_visible_definitions = definitions;
}

/* Ratings alter only the Ratings view and smart playlists.  Replacing the
 * entire discovery tree would invalidate every UI row and collapse unrelated
 * Album Artist/album branches, so keep those nodes and their playlist ids. */
static void pvlc_rebuild_rating_views( services_discovery_t *sd,
                             const pvlc_media_catalog_t *catalog,
                             const pvlc_smart_playlist_t *smart,
                             size_t smart_count, uint64_t definitions )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( sys->pp_roots[0] == NULL || sys->pp_roots[2] == NULL )
    {
        pvlc_build_tree( sd, catalog, smart, smart_count, definitions );
        return;
    }

    char *path = NULL;
    uint64_t roots[PVLC_VIEW_COUNT], masks[PVLC_VIEW_COUNT];
    if( pvlc_prepare_lazy_index( catalog, &path, roots, masks ) == VLC_SUCCESS )
    {
        if( sys->p_rating_node )
        {
            services_discovery_RemoveItem( sd, sys->p_rating_node );
            input_item_Release( sys->p_rating_node );
            sys->p_rating_node = NULL;
        }
        input_item_t *node = roots[PVLC_VIEW_RATINGS] != 0
            ? pvlc_add_compact_music_view( sd, sys->pp_roots[0], path,
                               roots[PVLC_VIEW_RATINGS], PVLC_VIEW_RATINGS )
            : NULL;
        if( node )
        {
            sys->p_rating_node = input_item_Hold( node );
            input_item_Release( node );
        }
    }
    free( path );

    services_discovery_RemoveItem( sd, sys->pp_roots[2] );
    input_item_Release( sys->pp_roots[2] );
    sys->pp_roots[2] = pvlc_add_node( sd, NULL, _( "Smart Playlists" ) );
    pvlc_populate_smart_root( sd, sys->pp_roots[2], catalog, smart,
                              smart_count, definitions );
    sys->i_visible_fingerprint = catalog->i_fingerprint;
    sys->i_visible_definitions = definitions;
}

static void pvlc_rebuild_smart_root( services_discovery_t *sd,
                             const pvlc_media_catalog_t *catalog,
                             const pvlc_smart_playlist_t *smart,
                             size_t smart_count, uint64_t definitions )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( sys->pp_roots[2] == NULL )
    {
        pvlc_build_tree( sd, catalog, smart, smart_count, definitions );
        return;
    }
    services_discovery_RemoveItem( sd, sys->pp_roots[2] );
    input_item_Release( sys->pp_roots[2] );
    sys->pp_roots[2] = pvlc_add_node( sd, NULL, _( "Smart Playlists" ) );
    pvlc_populate_smart_root( sd, sys->pp_roots[2], catalog, smart,
                              smart_count, definitions );
    sys->i_visible_definitions = definitions;
}

static int pvlc_prefix_video_paths( pvlc_media_catalog_t *catalog,
                                    const char *folder )
{
    const char *end = folder + strlen( folder );
    while( end > folder && (end[-1] == '/' || end[-1] == '\\') ) end--;
    const char *begin = end;
    while( begin > folder && begin[-1] != '/' && begin[-1] != '\\' ) begin--;
    char *label = begin < end ? strndup( begin, (size_t)(end - begin) )
                              : strdup( folder );
    if( label == NULL ) return VLC_ENOMEM;
    for( size_t i = 0; i < catalog->i_count; ++i )
    {
        pvlc_media_entry_t *entry = &catalog->p_entries[i];
        if( entry->i_type != PVLC_MEDIA_VIDEO ) continue;
        char *relative = pvlc_path_join( label, entry->psz_relative );
        if( relative == NULL ) { free( label ); return VLC_ENOMEM; }
        free( entry->psz_relative );
        entry->psz_relative = relative;
    }
    free( label );
    return VLC_SUCCESS;
}

static int pvlc_refresh( services_discovery_t *sd, bool force,
                         bool exhaustive, bool rating_only, bool smart_only,
                         bool cache_only,
                         bool managed_only,
                         bool *changed_out )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( changed_out ) *changed_out = false;
    pvlc_folder_t *folders = NULL; size_t folder_count = 0;
    pvlc_smart_playlist_t *smart = NULL; size_t smart_count = 0;
    uint64_t definitions = 0;
    int ret = pvlc_load_folders( VLC_OBJECT( sd ), &folders, &folder_count );
    if( ret != VLC_SUCCESS ) goto out;
    ret = pvlc_load_smart_playlists( VLC_OBJECT( sd ), &smart, &smart_count,
                                     &definitions );
    if( ret != VLC_SUCCESS ) goto out;

    bool *will_scan = calloc( folder_count ? folder_count : 1,
                              sizeof( *will_scan ) );
    char **cache_paths = calloc( folder_count ? folder_count : 1,
                                 sizeof( *cache_paths ) );
    if( will_scan == NULL || cache_paths == NULL )
    {
        free( will_scan ); free( cache_paths );
        ret = VLC_ENOMEM; goto out;
    }
    uint64_t scan_done = 0;
    bool scan_started = false;
    pvlc_scan_report_summary_t scan_report = { 0 };
    libvlc_int_t *libvlc = sd->obj.libvlc;
    for( size_t i = 0; i < folder_count; ++i )
    {
        cache_paths[i] = pvlc_folder_database_path( VLC_OBJECT( sd ),
                                                    &folders[i] );
        struct stat st;
        if( vlc_stat( folders[i].psz_path, &st ) != 0 || !S_ISDIR( st.st_mode ) )
            continue;
        bool cache_available = cache_paths[i]
                    && pvlc_folder_cache_available_at( cache_paths[i] );
        /* Incremental refresh requires an existing catalogue and directory
         * snapshot. Treating a brand-new monitored folder as incremental
         * hid all progress while it silently performed a complete scan. */
        /* An explicit user rescan must rebuild the source exhaustively.  A
         * previous interrupted network enumeration may have produced both a
         * truncated catalogue and a matching truncated directory snapshot;
         * no incremental comparison can discover branches absent from both.
         * Imports still use the cheap monitored-folder refresh below. */
        bool eligible = !managed_only || i == 0;
        bool incremental = eligible && force && !exhaustive
                        && folders[i].b_monitor && cache_available;
        will_scan[i] = eligible && !incremental && !cache_only
                    && (exhaustive || (force && !cache_available));
        scan_started |= will_scan[i] || incremental;
    }
    if( scan_started )
    {
        /* Publish before the first directory access. In particular, never
         * leave a new library displayed as an authoritative "Music (0)". */
        pvlc_scan_publish( libvlc, true, 0, 0 );
        pvlc_set_root_scan_state( sd, _( "scanning…" ) );
    }

    /* Darwin 6 users need the same useful progress title as the Modern UI:
     * percentage and files remaining.  The metadata scanner deliberately
     * works in small batches, so it cannot discover the final total while it
     * is running without making the percentage regress.  Count the cheap
     * directory entries first, then keep that stable total for every folder
     * in this refresh.  If a network source changes or fails during the count,
     * fall back to the running-count display rather than publishing a lie. */
    uint64_t scan_total = 0;
    bool scan_total_known = scan_started;
    for( size_t i = 0; scan_total_known && i < folder_count; ++i )
    {
        if( !will_scan[i] ) continue;
        uint64_t folder_total = 0;
        if( pvlc_count_media_files( VLC_OBJECT( sd ), folders[i].psz_path,
                                    &folder_total ) != VLC_SUCCESS
         || UINT64_MAX - scan_total < folder_total )
        {
            scan_total_known = false;
            scan_total = 0;
            break;
        }
        scan_total += folder_total;
    }
    if( scan_started && scan_total_known && scan_total > 0 )
        pvlc_scan_publish( libvlc, true, 0, scan_total );

    pvlc_media_catalog_t combined; pvlc_catalog_init( &combined );
    for( size_t i = 0; i < folder_count; ++i )
    {
        char *scan_report_path = pvlc_folder_scan_report_path(
                                            VLC_OBJECT( sd ), &folders[i] );
        struct stat st;
        bool available = vlc_stat( folders[i].psz_path, &st ) == 0
                      && S_ISDIR( st.st_mode );
        if( !available && i == 0 )
        {
            pvlc_mkdir_parents( folders[i].psz_path );
            available = vlc_stat( folders[i].psz_path, &st ) == 0
                     && S_ISDIR( st.st_mode );
        }
        pvlc_media_catalog_t one; pvlc_catalog_init( &one );
        bool scan = available && will_scan[i];
        bool folder_changed = false;
        if( available && force && folders[i].b_monitor && cache_paths[i]
         && !will_scan[i]
         && pvlc_refresh_folder_cache_at( VLC_OBJECT( sd ),
                    folders[i].psz_path, cache_paths[i], &one,
                    &folder_changed ) == VLC_SUCCESS )
        {
            msg_Dbg( sd, "%s incremental cache with %zu media from %s",
                     folder_changed ? "refreshed" : "reused", one.i_count,
                     folders[i].psz_path );
            if( changed_out && folder_changed ) *changed_out = true;
            scan = false;
        }
        else if( !scan && cache_paths[i]
         && pvlc_load_folder_cache_at( VLC_OBJECT( sd ), folders[i].psz_path,
                                       cache_paths[i], &one ) == VLC_SUCCESS )
        {
            msg_Dbg( sd, "loaded %zu cached media from %s", one.i_count,
                     folders[i].psz_path );
        }
        else if( available && cache_only )
        {
            /* The startup cache-only pass must remain free of filesystem
             * traversal.  Report the missing cache to Run(), which will
             * schedule the one legitimate immediate scan for a new source. */
            if( changed_out ) *changed_out = true;
        }
        else if( available && !cache_only )
        {
            char *checkpoint = pvlc_folder_checkpoint_path(
                                            VLC_OBJECT( sd ), &folders[i] );
            pvlc_media_catalog_t resume;
            pvlc_catalog_init( &resume );
            bool have_resume = checkpoint
                && pvlc_load_folder_cache_at( VLC_OBJECT( sd ),
                        folders[i].psz_path, checkpoint,
                        &resume ) == VLC_SUCCESS;
            if( !have_resume && force && cache_paths[i] )
                have_resume = pvlc_load_folder_cache_at( VLC_OBJECT( sd ),
                        folders[i].psz_path, cache_paths[i],
                        &resume ) == VLC_SUCCESS;
            if( have_resume )
                msg_Dbg( sd, "resuming scan with %zu cached media from %s",
                         resume.i_count, folders[i].psz_path );

            pvlc_scan_ui_t progress = {
                .p_libvlc = libvlc,
                .i_base = scan_done,
                .i_total = scan_total_known ? scan_total : 0,
                .i_last_percent = pvlc_scan_percent( scan_done,
                                      scan_total_known ? scan_total : 0 ),
                .i_last_done = scan_done,
                .i_last_publish = mdate(),
                .p_obj = VLC_OBJECT( sd ),
                .psz_root = folders[i].psz_path,
                .psz_checkpoint = checkpoint,
                .p_catalog = &one,
                .i_checkpoint_done = 0,
                .i_checkpoint_entries = 0,
                .i_last_checkpoint = mdate(),
            };
            FILE *scan_report_file = scan_report_path
                                   ? vlc_fopen( scan_report_path, "wb" ) : NULL;
            int scan_ret = pvlc_scan_folder_resume_report_progress(
                    VLC_OBJECT( sd ), folders[i].psz_path, &one,
                    have_resume ? &resume : NULL,
                    scan_total_known ? scan_total : 0,
                    pvlc_scan_ui_progress, &progress, scan_report_file );
            if( scan_report_file ) fclose( scan_report_file );
            if( scan_ret == VLC_SUCCESS )
            {
                msg_Dbg( sd, "scanned %zu media from %s", one.i_count,
                         folders[i].psz_path );
                if( cache_paths[i] )
                    pvlc_save_folder_cache_at( VLC_OBJECT( sd ),
                                               folders[i].psz_path,
                                               cache_paths[i], &one );
                if( checkpoint ) vlc_unlink( checkpoint );
                if( changed_out ) *changed_out = true;
            }
            else
            {
                if( checkpoint && one.i_count > progress.i_checkpoint_entries )
                    pvlc_append_resume_cache_at( VLC_OBJECT( sd ),
                            folders[i].psz_path, checkpoint, &one,
                            progress.i_checkpoint_entries );
                msg_Err( sd, "media-library scan failed for %s",
                         folders[i].psz_path );
                ret = scan_ret;
            }
            pvlc_catalog_clear( &resume );
            free( checkpoint );
            scan_done += one.i_count;
            pvlc_scan_publish( libvlc, true, scan_done,
                               scan_total_known ? scan_total : 0 );
        }
        pvlc_scan_report_load_summary( scan_report_path, &scan_report );
        free( scan_report_path );
        /* The managed Music root is intentionally invisible. Each configured
         * source, however, remains a distinct top-level video folder. */
        if( i > 0 ) ret = pvlc_prefix_video_paths( &one,
                                                   folders[i].psz_path );
        if( ret == VLC_SUCCESS ) ret = pvlc_catalog_merge( &combined, &one );
        pvlc_catalog_clear( &one );
        if( ret != VLC_SUCCESS ) break;
    }
    if( scan_started )
        pvlc_scan_publish( libvlc, false, scan_done, scan_done );
    if( ret == VLC_SUCCESS )
    {
        pvlc_catalog_finalize( &combined );
        pvlc_ratings_apply( VLC_OBJECT( sd ), &combined );
        if( rating_only )
            pvlc_rebuild_rating_views( sd, &combined, smart, smart_count,
                                       definitions );
        else if( smart_only )
            pvlc_rebuild_smart_root( sd, &combined, smart, smart_count,
                                     definitions );
        else
            pvlc_build_tree( sd, &combined, smart, smart_count, definitions );
        pvlc_update_scan_report_root( sd, &scan_report );

        if( !smart_only )
        {
            pvlc_search_catalog_t search_catalog;
            int search_ret = pvlc_search_catalog_build( &combined,
                                                        &search_catalog );
            /* Search remains entirely in RAM, but only the searchable
             * projection survives. */
            vlc_mutex_lock( &sys->lock );
            pvlc_search_catalog_clear( &sys->search_catalog );
            if( search_ret == VLC_SUCCESS )
            {
                sys->search_catalog = search_catalog;
                memset( &search_catalog, 0, sizeof( search_catalog ) );
            }
            vlc_mutex_unlock( &sys->lock );
            pvlc_search_catalog_clear( &search_catalog );
        }
    }
    else if( scan_started )
        pvlc_set_root_scan_state( sd, _( "scan failed" ) );
    pvlc_catalog_clear( &combined );
    free( will_scan );
    for( size_t i = 0; i < folder_count; ++i ) free( cache_paths[i] );
    free( cache_paths );
out:
    for( size_t i = 0; i < folder_count; ++i ) pvlc_folder_clear( &folders[i] );
    free( folders );
    for( size_t i = 0; i < smart_count; ++i ) pvlc_smart_clear( &smart[i] );
    free( smart );
    return ret;
}

static void pvlc_import_one( services_discovery_t *sd,
                             const pvlc_import_request_t *request )
{
    if( request->p_item )
    {
        pvlc_import_managed_input( VLC_OBJECT( sd ), request->p_item,
            request->psz_title, request->psz_artist, request->psz_album, NULL );
        return;
    }
    struct stat st;
    if( vlc_stat( request->psz_path, &st ) != 0 ) return;
    if( S_ISREG( st.st_mode ) )
    {
        pvlc_media_entry_t entry;
        if( pvlc_scan_file( VLC_OBJECT( sd ), request->psz_path,
                            request->psz_path, &entry ) == VLC_SUCCESS )
        {
            pvlc_import_managed( VLC_OBJECT( sd ), request->psz_path,
                request->psz_title ? request->psz_title : entry.psz_title,
                request->psz_artist ? request->psz_artist : entry.psz_artist,
                request->psz_album ? request->psz_album : entry.psz_album,
                NULL );
            pvlc_media_entry_clear( &entry );
        }
    }
    else if( S_ISDIR( st.st_mode ) )
    {
        pvlc_media_catalog_t catalog; pvlc_catalog_init( &catalog );
        if( pvlc_scan_folder( VLC_OBJECT( sd ), request->psz_path, &catalog )
            == VLC_SUCCESS )
            for( size_t i = 0; i < catalog.i_count; ++i )
                if( catalog.p_entries[i].i_type == PVLC_MEDIA_AUDIO )
                    pvlc_import_managed( VLC_OBJECT( sd ),
                        catalog.p_entries[i].psz_path,
                        catalog.p_entries[i].psz_title,
                        catalog.p_entries[i].psz_artist,
                        catalog.p_entries[i].psz_album, NULL );
        pvlc_catalog_clear( &catalog );
    }
}

static void pvlc_request_clear( pvlc_import_request_t *r )
{
    free( r->psz_path ); free( r->psz_title ); free( r->psz_artist );
    free( r->psz_album );
    if( r->p_item ) input_item_Release( r->p_item );
}

static void *Run( void *data )
{
    services_discovery_t *sd = data;
    services_discovery_sys_t *sys = sd->p_sys;
    char *managed = pvlc_managed_folder( VLC_OBJECT( sd ) );
    if( managed )
    {
        static const char *const branches[] = { "Music" };
        pvlc_mkdir_parents( managed );
        for( size_t i = 0; i < ARRAY_SIZE( branches ); ++i )
        {
            char *path = pvlc_path_join( managed, branches[i] );
            if( path ) { pvlc_mkdir_parents( path ); free( path ); }
        }
        free( managed );
    }
    /* The persistent catalogue is authoritative at startup.  Missing caches
     * are deliberately left empty until the user explicitly requests a
     * rescan: merely opening PowerVLC must never walk a local or network
     * source behind the user's back. */
    pvlc_refresh( sd, false, false, false, false, true, false, NULL );

    for( ;; )
    {
        /* Close() may cancel a scan blocked on an unavailable network volume.
         * Keep cancellation disabled while the state mutex is held so the
         * worker can never disappear while owning it. */
        int cancel = vlc_savecancel();
        vlc_mutex_lock( &sys->lock );
        while( !sys->b_stop && !sys->b_force_rescan
            && !sys->b_rating_refresh && !sys->b_smart_refresh
            && sys->i_import_count == 0 )
            vlc_cond_wait( &sys->wait, &sys->lock );
        bool stop = sys->b_stop;
        bool force_rescan = sys->b_force_rescan;
        bool rating_only = sys->b_rating_refresh && !sys->b_force_rescan
                        && !sys->b_smart_refresh && sys->i_import_count == 0;
        bool smart_only = sys->b_smart_refresh && !sys->b_force_rescan
                       && !sys->b_rating_refresh && sys->i_import_count == 0;
        sys->b_force_rescan = false;
        sys->b_rating_refresh = false;
        sys->b_smart_refresh = false;
        pvlc_import_request_t *imports = sys->p_imports;
        size_t import_count = sys->i_import_count;
        sys->p_imports = NULL; sys->i_import_count = 0;
        vlc_mutex_unlock( &sys->lock );
        vlc_restorecancel( cancel );
        if( stop )
        {
            for( size_t i = 0; i < import_count; ++i ) pvlc_request_clear( &imports[i] );
            free( imports ); break;
        }
        for( size_t i = 0; i < import_count; ++i )
        {
            pvlc_import_one( sd, &imports[i] ); pvlc_request_clear( &imports[i] );
        }
        free( imports );
        /* The catalogue is authoritative between explicit changes.  A timed
         * directory walk is both unreliable (AFP/SMB can expose different
         * timestamp semantics) and catastrophically expensive on old Macs.
         * Imports refresh their managed destination; an explicit Rescan is
         * the only operation allowed to inspect configured source folders. */
        bool changed = false;
        pvlc_refresh( sd, force_rescan || import_count != 0, force_rescan,
                      rating_only, smart_only, false,
                      import_count != 0 && !force_rescan, &changed );
    }
    return NULL;
}

static bool pvlc_user_descends_from( playlist_item_t *item,
                                     playlist_item_t *ancestor )
{
    for( ; item != NULL; item = item->p_parent )
        if( item == ancestor ) return true;
    return false;
}

static playlist_item_t *pvlc_user_root_locked( services_discovery_t *sd,
                                               playlist_t *playlist )
{
    services_discovery_sys_t *sys = sd->p_sys;
    return sys->pp_roots[3]
         ? playlist_ItemGetByInput( playlist, sys->pp_roots[3] ) : NULL;
}

static bool pvlc_user_container_accepts( playlist_item_t *item, bool media )
{
    if( item == NULL || item->p_input == NULL || item->i_children < 0 )
        return false;
    if( media ) return input_item_IsPowerVLCUserPlaylist( item->p_input );
    return input_item_IsPowerVLCUserPlaylistsRoot( item->p_input )
        || input_item_IsPowerVLCPlaylistFolder( item->p_input );
}

static bool pvlc_user_lazy_location( input_item_t *input, char **path,
                                     uint64_t *offset )
{
    *path = NULL; *offset = 0;
    if( input == NULL || !input_item_IsPowerVLCLazyIndex( input ) )
        return false;
    const char prefix[] = VLC_INPUT_OPTION_POWERVLC_INDEX_OFFSET_PREFIX;
    vlc_mutex_lock( &input->lock );
    for( int i = 0; i < input->i_options && *offset == 0; ++i )
        if( !strncmp( input->ppsz_options[i], prefix, sizeof( prefix ) - 1 ) )
        {
            char *end = NULL;
            uint64_t value = strtoull(
                input->ppsz_options[i] + sizeof( prefix ) - 1, &end, 10 );
            if( value && end && *end == '\0' ) *offset = value;
        }
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

static input_item_t *pvlc_user_read_index_media( FILE *file,
                                                  uint64_t offset )
{
    if( offset > LONG_MAX || fseek( file, (long)offset, SEEK_SET ) != 0 )
        return NULL;
    uint32_t marker, rating;
    uint64_t duration, stable_id;
    char *uri = NULL, *title = NULL, *artist = NULL, *album = NULL;
    char *track = NULL, *album_artist = NULL;
    int ret = pvlc_binary_read_u32( file, &marker );
    if( ret == VLC_SUCCESS && marker != PVLC_INDEX_MEDIA ) ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &uri,
                                                            16 * 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &title,
                                                            16 * 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &artist,
                                                            16 * 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &album,
                                                            16 * 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &track,
                                                            16 * 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_string( file, &album_artist,
                                                            16 * 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &rating );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file, &duration );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file, &stable_id );
    input_item_t *item = ret == VLC_SUCCESS
        ? input_item_NewFile( uri, title, -1, ITEM_LOCAL ) : NULL;
    if( item )
    {
        if( artist && *artist ) input_item_SetMeta( item, vlc_meta_Artist,
                                                    artist );
        if( album && *album ) input_item_SetMeta( item, vlc_meta_Album,
                                                  album );
        if( track && *track ) input_item_SetMeta( item, vlc_meta_TrackNumber,
                                                  track );
        if( album_artist && *album_artist )
            input_item_SetMeta( item, vlc_meta_AlbumArtist, album_artist );
        if( rating > 0 && rating <= 5 )
        { char text[2] = { (char)('0' + rating), '\0' };
          input_item_SetRating( item, text ); }
        input_item_SetDuration( item, (vlc_tick_t)duration );
        if( stable_id )
        {
            char option[64];
            snprintf( option, sizeof( option ),
                      "powervlc-ipod-track-id=%" PRIu64, stable_id );
            input_item_AddOption( item, option, VLC_INPUT_OPTION_UNIQUE );
        }
        input_item_SetPreparsed( item, true );
    }
    free( uri ); free( title ); free( artist ); free( album );
    free( track ); free( album_artist );
    return item;
}

static int pvlc_user_copy_index_node_locked( playlist_t *playlist, FILE *file,
    uint64_t offset, playlist_item_t *target, int *position, unsigned depth )
{
    if( depth > 64 || offset > LONG_MAX
     || fseek( file, (long)offset, SEEK_SET ) != 0 ) return VLC_EGENERIC;
    uint32_t marker, count;
    if( pvlc_binary_read_u32( file, &marker ) != VLC_SUCCESS
     || marker != PVLC_INDEX_NODE
     || pvlc_binary_read_u32( file, &count ) != VLC_SUCCESS
     || count > 1000000 ) return VLC_EGENERIC;
    int ret = VLC_SUCCESS;
    for( uint32_t i = 0; i < count && ret == VLC_SUCCESS; ++i )
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
        if( ret == VLC_SUCCESS && !(flags & PVLC_INDEX_FLAG_RANDOM) )
        {
            if( type == PVLC_INDEX_CHILD_NODE )
                ret = pvlc_user_copy_index_node_locked( playlist, file,
                    child_offset, target, position, depth + 1 );
            else if( type == PVLC_INDEX_CHILD_MEDIA )
            {
                input_item_t *media = pvlc_user_read_index_media( file,
                                                                  child_offset );
                if( media == NULL ) ret = VLC_EGENERIC;
                else
                {
                    playlist_item_t *added = playlist_NodeAddInput( playlist,
                        media, target, *position < 0 ? PLAYLIST_END : *position );
                    input_item_Release( media );
                    if( added == NULL ) ret = VLC_ENOMEM;
                    else if( *position >= 0 ) ++*position;
                }
            }
            else ret = VLC_EGENERIC;
        }
        if( ret == VLC_SUCCESS && (next < 0 || fseek( file, next, SEEK_SET ) != 0) )
            ret = VLC_EGENERIC;
        free( name ); VLC_UNUSED( value ); VLC_UNUSED( reserved );
    }
    return ret;
}

static int pvlc_user_copy_lazy_index_locked( playlist_t *playlist,
    input_item_t *input, playlist_item_t *target, int *position )
{
    char *path; uint64_t offset;
    if( !pvlc_user_lazy_location( input, &path, &offset ) )
        return VLC_EGENERIC;
    FILE *file = vlc_fopen( path, "rb" );
    free( path );
    if( file == NULL ) return VLC_EGENERIC;
    setvbuf( file, NULL, _IOFBF, 64 * 1024 );
    unsigned char magic[sizeof( pvlc_lazy_index_magic )];
    int ret = pvlc_binary_read( file, magic, sizeof( magic ) );
    if( ret == VLC_SUCCESS
     && memcmp( magic, pvlc_lazy_index_magic, sizeof( magic ) ) )
        ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_user_copy_index_node_locked(
                               playlist, file, offset, target, position, 0 );
    fclose( file );
    return ret;
}

static int pvlc_user_copy_media_locked( playlist_t *playlist,
                                        playlist_item_t *source,
                                        playlist_item_t *target, int *position )
{
    if( source == NULL || source->p_input == NULL
     || input_item_IsPowerVLCRandomAction( source->p_input ) )
        return VLC_SUCCESS;
    if( source->i_children < 0 )
    {
        if( input_item_IsPowerVLCLazyIndex( source->p_input ) )
            return pvlc_user_copy_lazy_index_locked( playlist,
                                source->p_input, target, position );
        if( source->p_input->i_type != ITEM_TYPE_FILE )
            return VLC_EGENERIC;
        input_item_t *copy = input_item_Copy( source->p_input );
        if( copy == NULL ) return VLC_ENOMEM;
        playlist_item_t *added = playlist_NodeAddInput( playlist, copy, target,
            *position < 0 ? PLAYLIST_END : *position );
        input_item_Release( copy );
        if( added == NULL ) return VLC_ENOMEM;
        if( *position >= 0 ) ++*position;
        return VLC_SUCCESS;
    }
    for( int i = 0; i < source->i_children; ++i )
    {
        int ret = pvlc_user_copy_media_locked( playlist,
                       source->pp_children[i], target, position );
        if( ret != VLC_SUCCESS ) return ret;
    }
    return VLC_SUCCESS;
}

static int pvlc_user_playlist_create( services_discovery_t *sd,
                  const services_discovery_playlist_create_t *request )
{
    if( request == NULL || request->psz_name == NULL
     || !*request->psz_name ) return VLC_EGENERIC;
    playlist_t *playlist = (playlist_t *)sd->obj.parent;
    /* playlist_ServicesDiscoveryControl() invokes service controls while
     * holding the playlist lock.  All user-playlist mutations therefore run
     * in that existing critical section. */
    playlist_item_t *root = pvlc_user_root_locked( sd, playlist );
    playlist_item_t *parent = playlist_ItemGetById( playlist,
                                                    request->i_parent_id );
    int ret = VLC_EGENERIC;
    if( root && parent && pvlc_user_descends_from( parent, root )
     && pvlc_user_container_accepts( parent, false ) )
    {
        input_item_t *input = input_item_NewExt( "vlc://nop",
            request->psz_name, -1, ITEM_TYPE_NODE, ITEM_LOCAL );
        if( input )
        {
            input_item_AddOption( input, request->b_folder
                ? VLC_INPUT_OPTION_POWERVLC_PLAYLIST_FOLDER
                : VLC_INPUT_OPTION_POWERVLC_USER_PLAYLIST, 0 );
            ret = playlist_NodeAddInput( playlist, input, parent,
                                         PLAYLIST_END ) ? VLC_SUCCESS
                                                        : VLC_ENOMEM;
            input_item_Release( input );
            if( ret == VLC_SUCCESS ) ret = pvlc_user_save_locked( sd );
        }
        else ret = VLC_ENOMEM;
    }
    return ret;
}

static int pvlc_user_playlist_rename( services_discovery_t *sd,
                  const services_discovery_playlist_rename_t *request )
{
    if( request == NULL || request->psz_name == NULL
     || !*request->psz_name ) return VLC_EGENERIC;
    playlist_t *playlist = (playlist_t *)sd->obj.parent;
    playlist_item_t *root = pvlc_user_root_locked( sd, playlist );
    playlist_item_t *item = playlist_ItemGetById( playlist,
                                                  request->i_item_id );
    int ret = VLC_EGENERIC;
    if( root && item && item != root && pvlc_user_descends_from( item, root )
     && (input_item_IsPowerVLCPlaylistFolder( item->p_input )
      || input_item_IsPowerVLCUserPlaylist( item->p_input )) )
    {
        input_item_SetName( item->p_input, request->psz_name );
        ret = pvlc_user_save_locked( sd );
    }
    return ret;
}

static int pvlc_user_playlist_delete( services_discovery_t *sd,
                  const services_discovery_playlist_item_t *request )
{
    if( request == NULL ) return VLC_EGENERIC;
    playlist_t *playlist = (playlist_t *)sd->obj.parent;
    playlist_item_t *root = pvlc_user_root_locked( sd, playlist );
    playlist_item_t *item = playlist_ItemGetById( playlist,
                                                  request->i_item_id );
    int ret = VLC_EGENERIC;
    if( root && item && item != root && pvlc_user_descends_from( item, root )
     && (input_item_IsPowerVLCPlaylistFolder( item->p_input )
      || input_item_IsPowerVLCUserPlaylist( item->p_input )) )
    {
        /* The discovery tree is protected against generic UI deletion by
         * PLAYLIST_RO_FLAG. This command is the validated persistent delete
         * for playlist objects, so unlock only the exact requested node;
         * playlist_NodeDelete() force-removes its descendants recursively. */
        item->i_flags &= ~PLAYLIST_RO_FLAG;
        playlist_NodeDelete( playlist, item );
        ret = pvlc_user_save_locked( sd );
    }
    return ret;
}

static int pvlc_user_playlist_drop( services_discovery_t *sd,
                    const services_discovery_playlist_drop_t *request )
{
    if( request == NULL || request->i_count == 0
     || request->p_item_ids == NULL || request->i_count > INT_MAX )
        return VLC_EGENERIC;
    playlist_t *playlist = (playlist_t *)sd->obj.parent;
    playlist_item_t *root = pvlc_user_root_locked( sd, playlist );
    playlist_item_t *target = playlist_ItemGetById( playlist,
                                                    request->i_parent_id );
    int ret = VLC_EGENERIC;
    if( root == NULL || target == NULL
     || !pvlc_user_descends_from( target, root ) ) goto out;
    if( request->b_copy )
    {
        if( !pvlc_user_container_accepts( target, true ) ) goto out;
        int position = request->i_index;
        ret = VLC_SUCCESS;
        for( size_t i = 0; i < request->i_count && ret == VLC_SUCCESS; ++i )
        {
            playlist_item_t *source = playlist_ItemGetById(
                playlist, request->p_item_ids[i] );
            /* A container cannot be copied into itself or below itself: its
             * child count would grow while pvlc_user_copy_media_locked()
             * iterates it. Leaf tracks may still be duplicated deliberately. */
            if( source == NULL || (source->i_children >= 0
             && pvlc_user_descends_from( target, source )) )
            {
                ret = VLC_EGENERIC;
                break;
            }
            ret = pvlc_user_copy_media_locked( playlist, source, target,
                                               &position );
        }
    }
    else
    {
        playlist_item_t **items = calloc( request->i_count,
                                           sizeof( *items ) );
        if( items == NULL ) { ret = VLC_ENOMEM; goto out; }
        bool move_media = false, move_nodes = false;
        size_t count = 0;
        for( size_t i = 0; i < request->i_count; ++i )
        {
            playlist_item_t *item = playlist_ItemGetById(
                playlist, request->p_item_ids[i] );
            if( item == NULL || item == root
             || !pvlc_user_descends_from( item, root )
             || pvlc_user_descends_from( target, item ) )
            { count = 0; break; }
            bool node = input_item_IsPowerVLCPlaylistFolder( item->p_input )
                     || input_item_IsPowerVLCUserPlaylist( item->p_input );
            move_nodes |= node;
            move_media |= !node;
            items[count++] = item;
        }
        bool target_ok = count > 0 && !(move_media && move_nodes)
            && pvlc_user_container_accepts( target, move_media );
        int position = request->i_index < 0 ? target->i_children
                                             : request->i_index;
        ret = target_ok && playlist_TreeMoveMany( playlist, (int)count,
                    items, target, position ) == VLC_SUCCESS
            ? VLC_SUCCESS : VLC_EGENERIC;
        free( items );
    }
    if( ret == VLC_SUCCESS ) ret = pvlc_user_save_locked( sd );
out:
    return ret;
}

static int pvlc_user_playlist_remove( services_discovery_t *sd,
                  const services_discovery_playlist_remove_t *request )
{
    if( request == NULL || request->i_count == 0
     || request->p_item_ids == NULL || request->i_count > INT_MAX )
        return VLC_EGENERIC;
    playlist_t *playlist = (playlist_t *)sd->obj.parent;
    playlist_item_t *root = pvlc_user_root_locked( sd, playlist );
    playlist_item_t *parent = playlist_ItemGetById( playlist,
                                                    request->i_parent_id );
    if( root == NULL || parent == NULL
     || !pvlc_user_descends_from( parent, root )
     || !input_item_IsPowerVLCUserPlaylist( parent->p_input ) )
        return VLC_EGENERIC;

    /* Validate the complete request before mutating anything. IDs from a
     * stale outline reload must never delete a similarly-numbered item from
     * another playlist or the media-library catalogue. */
    playlist_item_t **items = calloc( request->i_count, sizeof( *items ) );
    if( items == NULL ) return VLC_ENOMEM;
    int ret = VLC_SUCCESS;
    for( size_t i = 0; i < request->i_count; ++i )
    {
        playlist_item_t *item = playlist_ItemGetById(
            playlist, request->p_item_ids[i] );
        if( item == NULL || item->p_parent != parent
         || input_item_IsPowerVLCUserPlaylist( item->p_input )
         || input_item_IsPowerVLCPlaylistFolder( item->p_input ) )
        {
            ret = VLC_EGENERIC;
            break;
        }
        items[i] = item;
    }
    if( ret == VLC_SUCCESS )
    {
        for( size_t i = 0; i < request->i_count; ++i )
        {
            /* Service-discovery descendants inherit PLAYLIST_RO_FLAG so a
             * generic playlist delete cannot mutate their mirrored tree.
             * This is the service's validated persistent-edit operation, so
             * clear it on the exact membership occurrence before deletion. */
            items[i]->i_flags &= ~PLAYLIST_RO_FLAG;
            playlist_NodeDelete( playlist, items[i] );
        }
        ret = pvlc_user_save_locked( sd );
    }
    free( items );
    return ret;
}

static bool pvlc_search_contains_token( const char *haystack,
                                        const char *token, size_t length )
{
    const size_t haystack_length = strlen( haystack );
    if( length > haystack_length ) return false;
    for( size_t offset = 0; offset <= haystack_length - length; ++offset )
        if( !memcmp( haystack + offset, token, length ) ) return true;
    return false;
}

static bool pvlc_search_tokens_match( const char *haystack,
                                      const char *needle )
{
    if( haystack == NULL || needle == NULL ) return false;
    if( strstr( haystack, needle ) != NULL ) return true;
    const char *p = needle;
    bool any = false;
    while( *p )
    {
        while( *p && (unsigned char)*p < 0x80
               && !isalnum( (unsigned char)*p ) ) ++p;
        const char *begin = p;
        while( *p && ((unsigned char)*p >= 0x80
                   || isalnum( (unsigned char)*p )) ) ++p;
        size_t length = (size_t)(p - begin);
        if( length == 0 ) continue;
        any = true;
        if( !pvlc_search_contains_token( haystack, begin, length ) )
            return false;
    }
    return any;
}

static int pvlc_library_match_compare( const void *a, const void *b )
{
    const services_discovery_library_match_t *left = a, *right = b;
    if( left->i_view != right->i_view )
        return left->i_view < right->i_view ? -1 : 1;
    if( left->i_bucket != right->i_bucket )
        return left->i_bucket < right->i_bucket ? -1 : 1;
    int order = strcasecmp( left->psz_primary, right->psz_primary );
    return order ? order : strcasecmp( left->psz_secondary,
                                       right->psz_secondary );
}

static int pvlc_library_match_append( services_discovery_library_search_t *r,
                                      size_t *capacity,
                                      unsigned view, unsigned bucket,
                                      const char *primary,
                                      const char *secondary )
{
    if( r->i_match_count == *capacity )
    {
        size_t grown = *capacity ? *capacity * 2 : 256;
        services_discovery_library_match_t *matches = realloc( r->p_matches,
                                             grown * sizeof( *matches ) );
        if( matches == NULL ) return VLC_ENOMEM;
        r->p_matches = matches; *capacity = grown;
    }
    services_discovery_library_match_t *match =
                                         &r->p_matches[r->i_match_count];
    match->i_view = view; match->i_bucket = bucket;
    match->psz_primary = strdup( primary ?: "" );
    match->psz_secondary = strdup( secondary ?: "" );
    if( match->psz_primary == NULL || match->psz_secondary == NULL )
    {
        free( match->psz_primary ); free( match->psz_secondary );
        return VLC_ENOMEM;
    }
    ++r->i_match_count;
    return VLC_SUCCESS;
}

static int pvlc_library_search( services_discovery_t *sd,
                                services_discovery_library_search_t *request )
{
    if( request == NULL || request->psz_query == NULL ) return VLC_EGENERIC;
    memset( request->p_bucket_masks, 0, sizeof( request->p_bucket_masks ) );
    request->i_match_count = 0;
    request->p_matches = NULL;
    char *needle = vlc_strfold( request->psz_query );
    if( needle == NULL ) return VLC_ENOMEM;

    services_discovery_sys_t *sys = sd->p_sys;
    vlc_mutex_lock( &sys->lock );
    int ret = VLC_SUCCESS; size_t match_capacity = 0;
    for( size_t i = 0; i < sys->search_catalog.i_count
                      && ret == VLC_SUCCESS; ++i )
    {
        const pvlc_search_entry_t *entry = &sys->search_catalog.p_entries[i];
        if( entry->psz_search == NULL
         || !pvlc_search_tokens_match( entry->psz_search, needle ) )
            continue;
        for( unsigned view = 0; view < PVLC_VIEW_COUNT; ++view )
        {
            if( request->i_view_mask
             && !(request->i_view_mask & (UINT64_C(1) << view)) ) continue;
            const char *primary = entry->psz_title;
            const char *secondary = "";
            unsigned rating = entry->i_rating;
            switch( (pvlc_music_view_t)view )
            {
                case PVLC_VIEW_ALBUM_ARTISTS:
                    primary = entry->psz_album_artist;
                    secondary = entry->psz_album; break;
                case PVLC_VIEW_ARTISTS:
                    primary = entry->psz_artist;
                    secondary = entry->psz_album; break;
                case PVLC_VIEW_ALBUMS:
                    primary = entry->psz_album;
                    secondary = entry->psz_album_artist; break;
                case PVLC_VIEW_GENRES:
                    primary = entry->psz_genre;
                    secondary = entry->psz_album; break;
                case PVLC_VIEW_COMPOSERS:
                    primary = entry->psz_composer;
                    secondary = entry->psz_album; break;
                case PVLC_VIEW_YEARS:
                    primary = entry->psz_year;
                    secondary = entry->psz_album; break;
                case PVLC_VIEW_RATINGS:
                {
                    static const char *const labels[] = {
                        "", "★", "★★", "★★★", "★★★★", "★★★★★"
                    };
                    if( rating == 0 ) continue;
                    primary = labels[rating <= 5 ? rating : 0]; break;
                }
                default: break;
            }
            unsigned bucket = pvlc_view_bucket( view, primary, rating );
            request->p_bucket_masks[view] |= UINT64_C(1) << bucket;
            if( pvlc_view_has_groups( (pvlc_music_view_t)view ) )
                ret = pvlc_library_match_append( request, &match_capacity,
                                                  view, bucket,
                                                  primary, secondary );
        }
    }
    vlc_mutex_unlock( &sys->lock );
    free( needle );
    msg_Dbg( sd, "memory library search '%s': view mask 0x%llx, %zu branch matches",
             request->psz_query, (unsigned long long)request->i_view_mask,
             request->i_match_count );
    if( ret != VLC_SUCCESS )
    {
        for( size_t i = 0; i < request->i_match_count; ++i )
        { free( request->p_matches[i].psz_primary );
          free( request->p_matches[i].psz_secondary ); }
        free( request->p_matches ); request->p_matches = NULL;
        request->i_match_count = 0;
        return ret;
    }
    if( request->i_match_count > 1 )
    {
        qsort( request->p_matches, request->i_match_count,
               sizeof( *request->p_matches ), pvlc_library_match_compare );
        size_t out = 1;
        for( size_t i = 1; i < request->i_match_count; ++i )
        {
            services_discovery_library_match_t *previous =
                                                   &request->p_matches[out - 1];
            services_discovery_library_match_t *match = &request->p_matches[i];
            if( pvlc_library_match_compare( previous, match ) == 0 )
            { free( match->psz_primary ); free( match->psz_secondary ); }
            else request->p_matches[out++] = *match;
        }
        request->i_match_count = out;
    }
    return VLC_SUCCESS;
}

static int Control( services_discovery_t *sd, int query, va_list args )
{
    services_discovery_sys_t *sys = sd->p_sys;
    if( query == SD_CMD_DESCRIPTOR )
    {
        services_discovery_descriptor_t *d = va_arg( args,
                                            services_discovery_descriptor_t * );
        memset( d, 0, sizeof( *d ) );
        return VLC_SUCCESS;
    }
    if( query == SD_CMD_POWERVLC_RESCAN )
    {
        vlc_mutex_lock( &sys->lock ); sys->b_force_rescan = true;
        vlc_cond_signal( &sys->wait ); vlc_mutex_unlock( &sys->lock );
        pvlc_scan_publish( sd->obj.libvlc, true, 0, 0 );
        pvlc_set_root_scan_state( sd, _( "scanning…" ) );
        return VLC_SUCCESS;
    }
    if( query == SD_CMD_POWERVLC_IMPORT )
    {
        const services_discovery_import_t *in = va_arg( args,
                                             const services_discovery_import_t * );
        if( in == NULL || (in->psz_path == NULL && in->p_item == NULL) )
            return VLC_EGENERIC;
        pvlc_import_request_t r = {
            in->psz_path ? strdup( in->psz_path ) : NULL,
            in->psz_title ? strdup( in->psz_title ) : NULL,
            in->psz_artist ? strdup( in->psz_artist ) : NULL,
            in->psz_album ? strdup( in->psz_album ) : NULL,
            in->p_item ? input_item_Hold( in->p_item ) : NULL
        };
        if( r.psz_path == NULL && r.p_item == NULL )
        { pvlc_request_clear( &r ); return VLC_ENOMEM; }
        vlc_mutex_lock( &sys->lock );
        pvlc_import_request_t *p = realloc( sys->p_imports,
                          (sys->i_import_count + 1) * sizeof( *p ) );
        if( p ) { sys->p_imports = p; p[sys->i_import_count++] = r; }
        vlc_mutex_unlock( &sys->lock );
        if( p == NULL ) { pvlc_request_clear( &r ); return VLC_ENOMEM; }
        vlc_cond_signal( &sys->wait );
        return VLC_SUCCESS;
    }
    if( query == SD_CMD_POWERVLC_SET_RATING )
    {
        const services_discovery_rating_t *rating = va_arg( args,
                                             const services_discovery_rating_t * );
        if( rating == NULL || rating->psz_path == NULL || rating->i_rating > 5 )
            return VLC_EGENERIC;
        int ret = pvlc_rating_set( VLC_OBJECT( sd ), rating->psz_path,
                                   rating->i_rating );
        if( ret == VLC_SUCCESS )
        {
            vlc_mutex_lock( &sys->lock ); sys->b_rating_refresh = true;
            vlc_cond_signal( &sys->wait ); vlc_mutex_unlock( &sys->lock );
        }
        return ret;
    }
    if( query == SD_CMD_POWERVLC_SET_RATINGS )
    {
        const services_discovery_ratings_t *ratings = va_arg( args,
                                            const services_discovery_ratings_t * );
        if( ratings == NULL || ratings->ppsz_paths == NULL
         || ratings->i_count == 0 || ratings->i_rating > 5 )
            return VLC_EGENERIC;
        int ret = pvlc_ratings_set( VLC_OBJECT( sd ), ratings->ppsz_paths,
                                    ratings->i_count, ratings->i_rating );
        if( ret == VLC_SUCCESS )
        {
            char value[2] = { ratings->i_rating
                            ? (char)('0' + ratings->i_rating) : '\0', '\0' };
            /* Service discoveries are created as children of the playlist;
             * Control is called with that playlist already locked. */
            playlist_t *playlist = (playlist_t *)sd->obj.parent;
            for( int i = 0; i < playlist->items.i_size; ++i )
            {
                input_item_t *input = playlist->items.p_elems[i]->p_input;
                char *uri = input ? input_item_GetURI( input ) : NULL;
                char *path = uri ? vlc_uri2path( uri ) : NULL;
                free( uri );
                if( path != NULL )
                    for( size_t j = 0; j < ratings->i_count; ++j )
                        if( ratings->ppsz_paths[j] != NULL
                         && !strcasecmp( path, ratings->ppsz_paths[j] ) )
                        {
                            input_item_SetRating( input, value );
                            break;
                        }
                free( path );
            }
            vlc_mutex_lock( &sys->lock ); sys->b_rating_refresh = true;
            vlc_cond_signal( &sys->wait ); vlc_mutex_unlock( &sys->lock );
        }
        return ret;
    }
    if( query == SD_CMD_POWERVLC_PLAYLIST_CREATE )
        return pvlc_user_playlist_create( sd, va_arg( args,
                    const services_discovery_playlist_create_t * ) );
    if( query == SD_CMD_POWERVLC_PLAYLIST_RENAME )
        return pvlc_user_playlist_rename( sd, va_arg( args,
                    const services_discovery_playlist_rename_t * ) );
    if( query == SD_CMD_POWERVLC_PLAYLIST_DELETE )
        return pvlc_user_playlist_delete( sd, va_arg( args,
                    const services_discovery_playlist_item_t * ) );
    if( query == SD_CMD_POWERVLC_PLAYLIST_DROP )
        return pvlc_user_playlist_drop( sd, va_arg( args,
                    const services_discovery_playlist_drop_t * ) );
    if( query == SD_CMD_POWERVLC_PLAYLIST_REMOVE )
        return pvlc_user_playlist_remove( sd, va_arg( args,
                    const services_discovery_playlist_remove_t * ) );
    if( query == SD_CMD_POWERVLC_LIBRARY_SEARCH )
        return pvlc_library_search( sd, va_arg( args,
                    services_discovery_library_search_t * ) );
    if( query == SD_CMD_POWERVLC_LIBRARY_RELOAD_SMART )
    {
        vlc_mutex_lock( &sys->lock );
        sys->b_smart_refresh = true;
        vlc_cond_signal( &sys->wait );
        vlc_mutex_unlock( &sys->lock );
        return VLC_SUCCESS;
    }
    return VLC_EGENERIC;
}

static int Open( vlc_object_t *obj )
{
    services_discovery_t *sd = (services_discovery_t *)obj;
    services_discovery_sys_t *sys = calloc( 1, sizeof( *sys ) );
    if( sys == NULL ) return VLC_ENOMEM;
    sd->p_sys = sys; sd->description = _( "PowerVLC Media Library" );
    sd->pf_control = Control;
    var_Create( sd->obj.libvlc, PVLC_ML_SCAN_ACTIVE, VLC_VAR_BOOL );
    var_Create( sd->obj.libvlc, PVLC_ML_SCAN_DONE, VLC_VAR_INTEGER );
    var_Create( sd->obj.libvlc, PVLC_ML_SCAN_TOTAL, VLC_VAR_INTEGER );
    var_Create( sd->obj.libvlc, PVLC_ML_SCAN_REVISION, VLC_VAR_INTEGER );
    vlc_mutex_init( &sys->lock ); vlc_cond_init( &sys->wait );
    if( vlc_clone( &sys->thread, Run, sd, VLC_THREAD_PRIORITY_LOW ) )
    {
        vlc_cond_destroy( &sys->wait ); vlc_mutex_destroy( &sys->lock );
        free( sys ); return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

static void Close( vlc_object_t *obj )
{
    services_discovery_t *sd = (services_discovery_t *)obj;
    services_discovery_sys_t *sys = sd->p_sys;
    vlc_mutex_lock( &sys->lock ); sys->b_stop = true;
    vlc_cond_signal( &sys->wait ); vlc_mutex_unlock( &sys->lock );
    /* Folder enumeration and metadata reads can otherwise keep the GUI's
     * termination path blocked indefinitely when a network source vanishes. */
    vlc_cancel( sys->thread );
    vlc_join( sys->thread, NULL );
    for( size_t i = 0; i < sys->i_import_count; ++i )
        pvlc_request_clear( &sys->p_imports[i] );
    free( sys->p_imports );
    pvlc_search_catalog_clear( &sys->search_catalog );
    if( sys->p_rating_node ) input_item_Release( sys->p_rating_node );
    for( size_t i = 0; i < ARRAY_SIZE( sys->pp_roots ); ++i )
        if( sys->pp_roots[i] ) input_item_Release( sys->pp_roots[i] );
    vlc_cond_destroy( &sys->wait ); vlc_mutex_destroy( &sys->lock );
    free( sys );
}
