/*****************************************************************************
 * powervlc_media_common.c: lightweight media-library filesystem helpers
 *****************************************************************************
 * Cache snapshots are compact binary streams.  Fixed-width little-endian
 * integers and length-prefixed UTF-8 strings keep them fast on G3 hardware,
 * dependency-free, and portable between PowerPC and Intel/ARM machines.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "powervlc_media_common.h"

#include <vlc_configuration.h>
#include <vlc_charset.h>
#include <vlc_input.h>
#include <vlc_fs.h>
#include <vlc_url.h>

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <stdatomic.h>
#include <sys/stat.h>
#ifdef __APPLE__
# include <sys/mount.h>
#endif

#ifdef _WIN32
# define PVLC_SEP '\\'
#else
# define PVLC_SEP '/'
#endif

#define PVLC_FOLDER_DB ".powervlcmediafolder.db"
#define PVLC_RATINGS_DB "powervlc-ratings.db"
#define PVLC_DB_HEADER "PowerVLC-Media-Folder-DB\t1"
static const unsigned char pvlc_folder_magic[8] = {
    'P', 'V', 'L', 'C', 'M', 'L', 5, 0
};
static const unsigned char pvlc_resume_magic[8] = {
    'P', 'V', 'L', 'C', 'R', 'S', 1, 0
};
#define PVLC_RESUME_ENTRY_BEGIN UINT32_C(0x52534d42)
#define PVLC_RESUME_ENTRY_END   UINT32_C(0x52534d45)

int pvlc_binary_write( FILE *f, const void *data, size_t size )
{
    return size == 0 || fwrite( data, 1, size, f ) == size
         ? VLC_SUCCESS : VLC_EGENERIC;
}

int pvlc_binary_read( FILE *f, void *data, size_t size )
{
    return size == 0 || fread( data, 1, size, f ) == size
         ? VLC_SUCCESS : VLC_EGENERIC;
}

int pvlc_binary_write_u32( FILE *f, uint32_t value )
{
    unsigned char data[4];
    for( unsigned i = 0; i < 4; ++i ) data[i] = (value >> (i * 8)) & 0xff;
    return pvlc_binary_write( f, data, sizeof( data ) );
}

int pvlc_binary_write_u64( FILE *f, uint64_t value )
{
    unsigned char data[8];
    for( unsigned i = 0; i < 8; ++i ) data[i] = (value >> (i * 8)) & 0xff;
    return pvlc_binary_write( f, data, sizeof( data ) );
}

int pvlc_binary_read_u32( FILE *f, uint32_t *value )
{
    unsigned char data[4];
    if( pvlc_binary_read( f, data, sizeof( data ) ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    *value = 0;
    for( unsigned i = 0; i < 4; ++i ) *value |= (uint32_t)data[i] << (i * 8);
    return VLC_SUCCESS;
}

int pvlc_binary_read_u64( FILE *f, uint64_t *value )
{
    unsigned char data[8];
    if( pvlc_binary_read( f, data, sizeof( data ) ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    *value = 0;
    for( unsigned i = 0; i < 8; ++i ) *value |= (uint64_t)data[i] << (i * 8);
    return VLC_SUCCESS;
}

int pvlc_binary_write_string( FILE *f, const char *value )
{
    size_t size = value ? strlen( value ) : 0;
    if( size > UINT32_MAX ) return VLC_EGENERIC;
    if( pvlc_binary_write_u32( f, (uint32_t)size ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    return pvlc_binary_write( f, value, size );
}

int pvlc_binary_read_string( FILE *f, char **value, uint32_t maximum )
{
    uint32_t size;
    *value = NULL;
    if( pvlc_binary_read_u32( f, &size ) != VLC_SUCCESS || size > maximum )
        return VLC_EGENERIC;
    char *result = malloc( (size_t)size + 1 );
    if( result == NULL ) return VLC_ENOMEM;
    if( pvlc_binary_read( f, result, size ) != VLC_SUCCESS )
    {
        free( result );
        return VLC_EGENERIC;
    }
    result[size] = '\0';
    *value = result;
    return VLC_SUCCESS;
}

/* Metadata caches contain a large fixed set of fields, most of which are
 * empty for most tracks.  Allocating a one-byte string for every empty field
 * turns 70,000 tracks into millions of malloc nodes (over 100 MB on modern
 * malloc implementations and much worse pressure on a G3). */
static int pvlc_binary_read_optional_string( FILE *f, char **value,
                                             uint32_t maximum )
{
    uint32_t size;
    *value = NULL;
    if( pvlc_binary_read_u32( f, &size ) != VLC_SUCCESS || size > maximum )
        return VLC_EGENERIC;
    if( size == 0 ) return VLC_SUCCESS;
    char *result = malloc( (size_t)size + 1 );
    if( result == NULL ) return VLC_ENOMEM;
    if( pvlc_binary_read( f, result, size ) != VLC_SUCCESS )
    { free( result ); return VLC_EGENERIC; }
    result[size] = '\0';
    *value = result;
    return VLC_SUCCESS;
}

static bool pvlc_is_separator( char c )
{
    return c == '/' || c == '\\';
}

char *pvlc_path_join( const char *psz_left, const char *psz_right )
{
    if( psz_left == NULL || psz_right == NULL )
        return NULL;
    size_t i_left = strlen( psz_left );
    while( *psz_right != '\0' && pvlc_is_separator( *psz_right ) )
        psz_right++;
    bool b_sep = i_left > 0 && !pvlc_is_separator( psz_left[i_left - 1] );
    char *psz_result;
    int ret = b_sep ? asprintf( &psz_result, "%s%c%s", psz_left,
                                PVLC_SEP, psz_right )
                    : asprintf( &psz_result, "%s%s", psz_left, psz_right );
    if( ret < 0 ) return NULL;
    return psz_result;
}

static int pvlc_mkdir_one( const char *psz_path )
{
    struct stat st;
    if( vlc_stat( psz_path, &st ) == 0 )
        return S_ISDIR( st.st_mode ) ? VLC_SUCCESS : VLC_EGENERIC;
    if( vlc_mkdir( psz_path, 0755 ) == 0 || errno == EEXIST )
        return VLC_SUCCESS;
    return VLC_EGENERIC;
}

int pvlc_mkdir_parents( const char *psz_path )
{
    if( psz_path == NULL || *psz_path == '\0' )
        return VLC_EGENERIC;
    char *psz_copy = strdup( psz_path );
    if( psz_copy == NULL )
        return VLC_ENOMEM;

    char *p = psz_copy;
#ifdef _WIN32
    if( isalpha( (unsigned char)p[0] ) && p[1] == ':' )
        p += 2;
#endif
    for( ; *p != '\0'; ++p )
    {
        if( !pvlc_is_separator( *p ) )
            continue;
        if( p == psz_copy )
            continue;
        char c = *p;
        *p = '\0';
        if( pvlc_mkdir_one( psz_copy ) != VLC_SUCCESS )
        {
            free( psz_copy );
            return VLC_EGENERIC;
        }
        *p = c;
    }
    int i_ret = pvlc_mkdir_one( psz_copy );
    free( psz_copy );
    return i_ret;
}

void pvlc_catalog_init( pvlc_media_catalog_t *p_catalog )
{
    memset( p_catalog, 0, sizeof( *p_catalog ) );
}

void pvlc_media_entry_clear( pvlc_media_entry_t *p_entry )
{
    free( p_entry->psz_path );
    free( p_entry->psz_relative );
    free( p_entry->psz_title );
    free( p_entry->psz_artist );
    free( p_entry->psz_album );
    free( p_entry->psz_search_folded );
    for( size_t i = 0; i < VLC_META_TYPE_COUNT; ++i )
        free( p_entry->ppsz_meta[i] );
    for( size_t i = 0; i < p_entry->i_extra_count; ++i )
    {
        free( p_entry->ppsz_extra_names[i] );
        free( p_entry->ppsz_extra_values[i] );
    }
    free( p_entry->ppsz_extra_names );
    free( p_entry->ppsz_extra_values );
    memset( p_entry, 0, sizeof( *p_entry ) );
}

void pvlc_catalog_clear( pvlc_media_catalog_t *p_catalog )
{
    for( size_t i = 0; i < p_catalog->i_count; ++i )
        pvlc_media_entry_clear( &p_catalog->p_entries[i] );
    free( p_catalog->p_entries );
    pvlc_catalog_init( p_catalog );
}

static uint64_t pvlc_hash_bytes( uint64_t i_hash, const void *p_data,
                                 size_t i_size )
{
    const unsigned char *p = p_data;
    for( size_t i = 0; i < i_size; ++i )
    {
        i_hash ^= p[i];
        i_hash *= UINT64_C(1099511628211);
    }
    return i_hash;
}

static uint64_t pvlc_entry_hash( uint64_t i_hash,
                                 const pvlc_media_entry_t *p_entry )
{
    i_hash = pvlc_hash_bytes( i_hash, p_entry->psz_path,
                             strlen( p_entry->psz_path ) );
    if( p_entry->psz_relative )
        i_hash = pvlc_hash_bytes( i_hash, p_entry->psz_relative,
                                  strlen( p_entry->psz_relative ) );
    i_hash = pvlc_hash_bytes( i_hash, &p_entry->i_size,
                             sizeof( p_entry->i_size ) );
    i_hash = pvlc_hash_bytes( i_hash, &p_entry->i_mtime,
                             sizeof( p_entry->i_mtime ) );
    i_hash = pvlc_hash_bytes( i_hash, &p_entry->i_duration,
                             sizeof( p_entry->i_duration ) );
    i_hash = pvlc_hash_bytes( i_hash, &p_entry->i_rating,
                             sizeof( p_entry->i_rating ) );
    for( size_t i = 0; i < VLC_META_TYPE_COUNT; ++i )
    {
        const char *value = pvlc_media_meta( p_entry, (vlc_meta_type_t)i );
        if( value ) i_hash = pvlc_hash_bytes( i_hash, value, strlen( value ) );
    }
    for( size_t i = 0; i < p_entry->i_extra_count; ++i )
    {
        i_hash = pvlc_hash_bytes( i_hash, p_entry->ppsz_extra_names[i],
                                 strlen( p_entry->ppsz_extra_names[i] ) );
        i_hash = pvlc_hash_bytes( i_hash, p_entry->ppsz_extra_values[i],
                                 strlen( p_entry->ppsz_extra_values[i] ) );
    }
    return i_hash;
}

static int pvlc_catalog_add_owned( pvlc_media_catalog_t *p_catalog,
                                   pvlc_media_entry_t *p_entry )
{
    if( p_catalog->i_count == p_catalog->i_capacity )
    {
        size_t i_new = p_catalog->i_capacity == 0 ? 128
                                                   : p_catalog->i_capacity * 2;
        pvlc_media_entry_t *p = realloc( p_catalog->p_entries,
                                         i_new * sizeof( *p ) );
        if( p == NULL )
            return VLC_ENOMEM;
        p_catalog->p_entries = p;
        p_catalog->i_capacity = i_new;
    }
    p_catalog->p_entries[p_catalog->i_count++] = *p_entry;
    memset( p_entry, 0, sizeof( *p_entry ) );
    return VLC_SUCCESS;
}

int pvlc_catalog_append( pvlc_media_catalog_t *p_catalog,
                         pvlc_media_entry_t *p_entry )
{
    return pvlc_catalog_add_owned( p_catalog, p_entry );
}

static int pvlc_entry_dup( pvlc_media_entry_t *p_dst,
                           const pvlc_media_entry_t *p_src )
{
    memset( p_dst, 0, sizeof( *p_dst ) );
    p_dst->psz_path = strdup( p_src->psz_path );
    p_dst->psz_relative = strdup( p_src->psz_relative
                                  ? p_src->psz_relative : p_src->psz_path );
    p_dst->psz_title = strdup( p_src->psz_title );
    p_dst->psz_artist = strdup( p_src->psz_artist );
    p_dst->psz_album = strdup( p_src->psz_album );
    p_dst->psz_search_folded = p_src->psz_search_folded
                             ? strdup( p_src->psz_search_folded ) : NULL;
    for( size_t i = 0; i < VLC_META_TYPE_COUNT; ++i )
        if( p_src->ppsz_meta[i] )
            p_dst->ppsz_meta[i] = strdup( p_src->ppsz_meta[i] );
    if( p_src->i_extra_count )
    {
        p_dst->ppsz_extra_names = calloc( p_src->i_extra_count,
                                          sizeof( *p_dst->ppsz_extra_names ) );
        p_dst->ppsz_extra_values = calloc( p_src->i_extra_count,
                                           sizeof( *p_dst->ppsz_extra_values ) );
        if( p_dst->ppsz_extra_names && p_dst->ppsz_extra_values )
            for( size_t i = 0; i < p_src->i_extra_count; ++i )
            {
                p_dst->ppsz_extra_names[i] = strdup( p_src->ppsz_extra_names[i] );
                p_dst->ppsz_extra_values[i] = strdup( p_src->ppsz_extra_values[i] );
                if( !p_dst->ppsz_extra_names[i] || !p_dst->ppsz_extra_values[i] )
                    break;
                p_dst->i_extra_count++;
            }
    }
    p_dst->i_duration = p_src->i_duration;
    p_dst->i_size = p_src->i_size;
    p_dst->i_mtime = p_src->i_mtime;
    p_dst->i_type = p_src->i_type;
    p_dst->i_rating = p_src->i_rating;
    bool metadata_ok = true;
    for( size_t i = 0; i < VLC_META_TYPE_COUNT; ++i )
        if( p_src->ppsz_meta[i] && !p_dst->ppsz_meta[i] ) metadata_ok = false;
    if( p_src->i_extra_count != p_dst->i_extra_count ) metadata_ok = false;
    if( p_dst->psz_path && p_dst->psz_relative && p_dst->psz_title
     && p_dst->psz_artist && p_dst->psz_album
     && (!p_src->psz_search_folded || p_dst->psz_search_folded)
     && metadata_ok )
        return VLC_SUCCESS;
    pvlc_media_entry_clear( p_dst );
    return VLC_ENOMEM;
}

int pvlc_catalog_merge( pvlc_media_catalog_t *p_dst,
                        pvlc_media_catalog_t *p_src )
{
    if( p_src->i_count == 0 ) return VLC_SUCCESS;
    if( p_dst->i_count > SIZE_MAX - p_src->i_count ) return VLC_ENOMEM;
    size_t needed = p_dst->i_count + p_src->i_count;
    if( needed > p_dst->i_capacity )
    {
        pvlc_media_entry_t *entries = realloc( p_dst->p_entries,
                                               needed * sizeof( *entries ) );
        if( entries == NULL ) return VLC_ENOMEM;
        p_dst->p_entries = entries;
        p_dst->i_capacity = needed;
    }
    memcpy( &p_dst->p_entries[p_dst->i_count], p_src->p_entries,
            p_src->i_count * sizeof( *p_src->p_entries ) );
    p_dst->i_count = needed;
    free( p_src->p_entries );
    pvlc_catalog_init( p_src );
    return VLC_SUCCESS;
}

static int pvlc_entry_compare( const void *a, const void *b )
{
    const pvlc_media_entry_t *ea = a;
    const pvlc_media_entry_t *eb = b;
    return strcasecmp( ea->psz_path, eb->psz_path );
}

static void pvlc_catalog_sort_deduplicate( pvlc_media_catalog_t *p_catalog )
{
    if( p_catalog->i_count > 1 )
        qsort( p_catalog->p_entries, p_catalog->i_count,
               sizeof( *p_catalog->p_entries ), pvlc_entry_compare );

    size_t out = 0;
    for( size_t i = 0; i < p_catalog->i_count; ++i )
    {
        if( out > 0 && !strcmp( p_catalog->p_entries[out - 1].psz_path,
                               p_catalog->p_entries[i].psz_path ) )
        {
            pvlc_media_entry_clear( &p_catalog->p_entries[i] );
            continue;
        }
        if( out != i )
            p_catalog->p_entries[out] = p_catalog->p_entries[i];
        out++;
    }
    p_catalog->i_count = out;

}

static void pvlc_catalog_prepare_search( pvlc_media_catalog_t *p_catalog )
{
    /* Search is an in-memory database operation.  Fold the four indexed
     * text fields once when the catalogue is published; a query over tens
     * of thousands of tracks then performs no metadata reads and no
     * per-field allocations. */
    for( size_t i = 0; i < p_catalog->i_count; ++i )
    {
        pvlc_media_entry_t *entry = &p_catalog->p_entries[i];
        if( entry->psz_search_folded != NULL )
            continue;
        const char *album_artist = pvlc_media_meta( entry,
                                                    vlc_meta_AlbumArtist );
        char *text = NULL;
        if( asprintf( &text, "%s\n%s\n%s\n%s",
                      entry->psz_title ?: "", entry->psz_artist ?: "",
                      entry->psz_album ?: "", album_artist ?: "" ) >= 0 )
        {
            entry->psz_search_folded = vlc_strfold( text );
            free( text );
        }
    }

}

static void pvlc_catalog_rehash( pvlc_media_catalog_t *p_catalog )
{
    uint64_t hash = UINT64_C(1469598103934665603);
    for( size_t i = 0; i < p_catalog->i_count; ++i )
        hash = pvlc_entry_hash( hash, &p_catalog->p_entries[i] );
    p_catalog->i_fingerprint = hash;
}

void pvlc_catalog_finalize( pvlc_media_catalog_t *p_catalog )
{
    pvlc_catalog_sort_deduplicate( p_catalog );
    pvlc_catalog_prepare_search( p_catalog );
    pvlc_catalog_rehash( p_catalog );
}

typedef struct
{
    char *path;
    uint8_t rating;
} pvlc_rating_entry_t;

static const unsigned char pvlc_ratings_magic[8] = {
    'P', 'V', 'L', 'C', 'R', 'T', 1, 0
};

static char *pvlc_ratings_path( void )
{
    char *data = config_GetUserDir( VLC_DATA_DIR );
    if( data == NULL ) return NULL;
    if( pvlc_mkdir_parents( data ) != VLC_SUCCESS )
    { free( data ); return NULL; }
    char *path = pvlc_path_join( data, PVLC_RATINGS_DB );
    free( data );
    return path;
}

static int pvlc_rating_compare( const void *a, const void *b )
{
    const pvlc_rating_entry_t *ra = a, *rb = b;
    return strcasecmp( ra->path, rb->path );
}

static void pvlc_ratings_clear( pvlc_rating_entry_t *entries, size_t count )
{
    for( size_t i = 0; i < count; ++i ) free( entries[i].path );
    free( entries );
}

static int pvlc_ratings_load( pvlc_rating_entry_t **out, size_t *count )
{
    *out = NULL; *count = 0;
    char *path = pvlc_ratings_path();
    FILE *file = path ? vlc_fopen( path, "rb" ) : NULL;
    free( path );
    if( file == NULL ) return VLC_SUCCESS;
    unsigned char magic[8]; uint64_t total = 0;
    int ret = pvlc_binary_read( file, magic, sizeof( magic ) );
    if( ret == VLC_SUCCESS && memcmp( magic, pvlc_ratings_magic,
                                      sizeof( magic ) ) ) ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file, &total );
    if( ret == VLC_SUCCESS && (total > UINT64_C(10000000)
                           || total > SIZE_MAX / sizeof( **out )) )
        ret = VLC_EGENERIC;
    pvlc_rating_entry_t *entries = ret == VLC_SUCCESS
                                ? calloc( (size_t)total, sizeof( *entries ) )
                                : NULL;
    if( ret == VLC_SUCCESS && total && entries == NULL ) ret = VLC_ENOMEM;
    for( size_t i = 0; i < (size_t)total && ret == VLC_SUCCESS; ++i )
    {
        uint32_t rating;
        ret = pvlc_binary_read_string( file, &entries[i].path,
                                       16 * 1024 * 1024 );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( file, &rating );
        if( ret == VLC_SUCCESS && rating <= 5 ) entries[i].rating = rating;
        else if( ret == VLC_SUCCESS ) ret = VLC_EGENERIC;
    }
    fclose( file );
    if( ret != VLC_SUCCESS )
    { pvlc_ratings_clear( entries, (size_t)total ); return ret; }
    if( total > 1 ) qsort( entries, (size_t)total, sizeof( *entries ),
                           pvlc_rating_compare );
    *out = entries; *count = (size_t)total;
    return VLC_SUCCESS;
}

static int pvlc_ratings_save( pvlc_rating_entry_t *entries, size_t count )
{
    char *path = pvlc_ratings_path(), *temporary = NULL;
    if( path == NULL || asprintf( &temporary, "%s.tmp", path ) < 0 )
    { free( path ); return VLC_ENOMEM; }
    FILE *file = vlc_fopen( temporary, "wb" );
    int ret = file ? pvlc_binary_write( file, pvlc_ratings_magic,
                                        sizeof( pvlc_ratings_magic ) )
                   : VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file, count );
    for( size_t i = 0; i < count && ret == VLC_SUCCESS; ++i )
    {
        ret = pvlc_binary_write_string( file, entries[i].path );
        if( ret == VLC_SUCCESS )
            ret = pvlc_binary_write_u32( file, entries[i].rating );
    }
    bool error = ret != VLC_SUCCESS;
    if( file && (fflush( file ) != 0 || ferror( file )) ) error = true;
    if( file && fclose( file ) != 0 ) error = true;
    if( !error )
    {
#ifdef _WIN32
        vlc_unlink( path );
#endif
        error = vlc_rename( temporary, path ) != 0;
    }
    if( error ) vlc_unlink( temporary );
    free( temporary ); free( path );
    return error ? VLC_EGENERIC : VLC_SUCCESS;
}

int pvlc_ratings_apply( vlc_object_t *obj, pvlc_media_catalog_t *catalog )
{
    pvlc_rating_entry_t *ratings; size_t count;
    int ret = pvlc_ratings_load( &ratings, &count );
    if( ret != VLC_SUCCESS )
    { msg_Warn( obj, "cannot read the PowerVLC ratings database" ); return ret; }
    /* The sidecar database is authoritative. Folder caches can still contain
     * an older non-zero value after the user clears a rating, so reset every
     * catalog entry before applying the current sidecar contents. */
    for( size_t ci = 0; ci < catalog->i_count; ++ci )
        catalog->p_entries[ci].i_rating = 0;
    size_t ri = 0;
    for( size_t ci = 0; ci < catalog->i_count && ri < count; )
    {
        int comparison = strcasecmp( catalog->p_entries[ci].psz_path,
                                     ratings[ri].path );
        if( comparison < 0 ) ci++;
        else if( comparison > 0 ) ri++;
        else { catalog->p_entries[ci++].i_rating = ratings[ri++].rating; }
    }
    pvlc_ratings_clear( ratings, count );
    /* Ratings change neither path order nor searchable text. */
    pvlc_catalog_rehash( catalog );
    return VLC_SUCCESS;
}

int pvlc_ratings_set( vlc_object_t *obj, const char *const *paths,
                      size_t path_count, unsigned rating )
{
    if( paths == NULL || path_count == 0 || rating > 5 ) return VLC_EGENERIC;
    pvlc_rating_entry_t *entries; size_t count;
    int ret = pvlc_ratings_load( &entries, &count );
    if( ret != VLC_SUCCESS ) return ret;
    for( size_t path_index = 0; path_index < path_count; ++path_index )
    {
        const char *path = paths[path_index];
        if( path == NULL || *path == '\0' ) continue;
        size_t pos = 0;
        while( pos < count && strcasecmp( entries[pos].path, path ) < 0 ) pos++;
        bool found = pos < count && !strcasecmp( entries[pos].path, path );
        if( rating == 0 && found )
        {
            free( entries[pos].path );
            memmove( &entries[pos], &entries[pos + 1],
                     (count - pos - 1) * sizeof( *entries ) );
            count--;
        }
        else if( rating != 0 && found ) entries[pos].rating = rating;
        else if( rating != 0 )
        {
            char *copy = strdup( path );
            if( copy == NULL )
            { pvlc_ratings_clear( entries, count ); return VLC_ENOMEM; }
            pvlc_rating_entry_t *grown = realloc( entries,
                                      (count + 1) * sizeof( *entries ) );
            if( grown == NULL )
            { free( copy ); pvlc_ratings_clear( entries, count ); return VLC_ENOMEM; }
            entries = grown;
            memmove( &entries[pos + 1], &entries[pos],
                     (count - pos) * sizeof( *entries ) );
            entries[pos].path = copy; entries[pos].rating = rating;
            count++;
        }
    }
    ret = pvlc_ratings_save( entries, count );
    if( ret != VLC_SUCCESS ) msg_Warn( obj, "cannot save media rating" );
    pvlc_ratings_clear( entries, count );
    return ret;
}

int pvlc_rating_set( vlc_object_t *obj, const char *path, unsigned rating )
{
    if( path == NULL ) return VLC_EGENERIC;
    return pvlc_ratings_set( obj, &path, 1, rating );
}

static bool pvlc_extension_in( const char *psz_ext, const char *const *ppsz,
                               size_t i_count )
{
    for( size_t i = 0; i < i_count; ++i )
        if( !strcasecmp( psz_ext, ppsz[i] ) )
            return true;
    return false;
}

int pvlc_media_type( const char *psz_path, pvlc_media_type_t *p_type )
{
    static const char *const audio[] = {
        "669", "aac", "ac3", "aiff", "ape", "au", "dts", "flac",
        "it", "m4a", "mka", "mod", "mp2", "mp3", "mpc", "mtm",
        "oga", "ogg", "opus", "ra", "s3m", "spx", "tta", "wav",
        "wma", "wv", "xm"
    };
    static const char *const video[] = {
        "3g2", "3gp", "asf", "avi", "divx", "dv", "f4v", "flv",
        "m2ts", "m4v", "mkv", "mov", "mp4", "mpeg", "mpg", "mts",
        "ogm", "ogv", "rm", "rmvb", "ts", "vob", "webm", "wmv"
    };
    const char *psz_dot = strrchr( psz_path, '.' );
    if( psz_dot == NULL || psz_dot[1] == '\0' )
        return VLC_EGENERIC;
    psz_dot++;
    if( pvlc_extension_in( psz_dot, audio, ARRAY_SIZE( audio ) ) )
        *p_type = PVLC_MEDIA_AUDIO;
    else if( pvlc_extension_in( psz_dot, video, ARRAY_SIZE( video ) ) )
        *p_type = PVLC_MEDIA_VIDEO;
    else
        return VLC_EGENERIC;
    return VLC_SUCCESS;
}

static char *pvlc_title_from_filename( const char *psz_filename )
{
    const char *psz_name = psz_filename;
    while( isdigit( (unsigned char)*psz_name ) )
        psz_name++;
    if( psz_name != psz_filename )
    {
        while( *psz_name == ' ' || *psz_name == '-' || *psz_name == '_' )
            psz_name++;
        if( *psz_name == '\0' )
            psz_name = psz_filename;
    }
    char *psz_title = strdup( psz_name );
    if( psz_title == NULL )
        return NULL;
    char *psz_dot = strrchr( psz_title, '.' );
    if( psz_dot != NULL )
        *psz_dot = '\0';
    return psz_title;
}

static char *pvlc_component_dup( const char *p_begin, const char *p_end,
                                 const char *psz_fallback )
{
    if( p_begin == NULL || p_end == NULL || p_end <= p_begin )
        return strdup( psz_fallback );
    return strndup( p_begin, (size_t)(p_end - p_begin) );
}

static int pvlc_infer_metadata( const char *psz_relative,
                                pvlc_media_entry_t *p_entry )
{
    char *psz_normal = strdup( psz_relative );
    if( psz_normal == NULL )
        return VLC_ENOMEM;
    for( char *p = psz_normal; *p != '\0'; ++p )
        if( *p == '\\' )
            *p = '/';

    const char *filename = strrchr( psz_normal, '/' );
    filename = filename ? filename + 1 : psz_normal;
    p_entry->psz_title = pvlc_title_from_filename( filename );

    const char *album_end = filename > psz_normal ? filename - 1 : NULL;
    const char *album_begin = NULL;
    if( album_end != NULL )
    {
        album_begin = album_end;
        while( album_begin > psz_normal && album_begin[-1] != '/' )
            album_begin--;
    }
    const char *artist_end = album_begin && album_begin > psz_normal
                           ? album_begin - 1 : NULL;
    const char *artist_begin = NULL;
    if( artist_end != NULL )
    {
        artist_begin = artist_end;
        while( artist_begin > psz_normal && artist_begin[-1] != '/' )
            artist_begin--;
    }
    p_entry->psz_album = pvlc_component_dup( album_begin, album_end,
                                             "Unknown Album" );
    p_entry->psz_artist = pvlc_component_dup( artist_begin, artist_end,
                                              "Unknown Artist" );
    free( psz_normal );
    if( p_entry->psz_title && p_entry->psz_album && p_entry->psz_artist )
        return VLC_SUCCESS;
    return VLC_ENOMEM;
}

const char *pvlc_media_meta( const pvlc_media_entry_t *entry,
                             vlc_meta_type_t type )
{
    if( type == vlc_meta_Title ) return entry->psz_title;
    if( type == vlc_meta_Artist ) return entry->psz_artist;
    if( type == vlc_meta_Album ) return entry->psz_album;
    return type >= 0 && type < VLC_META_TYPE_COUNT ? entry->ppsz_meta[type]
                                                   : NULL;
}

const char *pvlc_media_extra( const pvlc_media_entry_t *entry,
                              const char *name )
{
    for( size_t i = 0; i < entry->i_extra_count; ++i )
        if( !strcasecmp( entry->ppsz_extra_names[i], name ) )
            return entry->ppsz_extra_values[i];
    return NULL;
}

static void pvlc_replace_nonempty( char **destination, char *value )
{
    if( value && *value )
    {
        free( *destination );
        *destination = value;
    }
    else
        free( value );
}

typedef struct
{
    atomic_bool done;
    int status;
} pvlc_preparse_wait_t;

typedef struct
{
    libvlc_int_t *p_libvlc;
    input_item_t *p_item;
    pvlc_preparse_wait_t *p_wait;
    bool b_attached;
    bool b_pending;
} pvlc_preparse_cleanup_t;

static void pvlc_preparse_ended( const vlc_event_t *event, void *opaque )
{
    pvlc_preparse_wait_t *wait = opaque;
    wait->status = event->u.input_item_preparse_ended.new_status;
    atomic_store_explicit( &wait->done, true, memory_order_release );
}

static void pvlc_preparse_cancel_cleanup( void *p_opaque )
{
    pvlc_preparse_cleanup_t *p = p_opaque;
    if( p->b_pending )
        libvlc_MetadataCancel( p->p_libvlc, p->p_wait );
    if( p->b_attached )
        vlc_event_detach( &p->p_item->event_manager,
                          vlc_InputItemPreparseEnded,
                          pvlc_preparse_ended, p->p_wait );
    input_item_Release( p->p_item );
}

/* Read tags once, during the deliberately thorough initial scan.  The
 * services-discovery thread waits for the local preparser so every later UI
 * rebuild can use only the compact cache. */
static int pvlc_read_metadata( vlc_object_t *obj, pvlc_media_entry_t *entry,
                               bool b_fetch_external_art )
{
    char *uri = vlc_path2uri( entry->psz_path, NULL );
    /* Do not seed the preparser item with the path-derived fallback title.
     * input_item's curated-title protection would otherwise prefer a fallback
     * such as "03 Silence" over the real embedded TITLE tag "Silence".  The
     * entry already retains its fallback, so a missing/corrupt tag still has a
     * useful name after the metadata request. */
    input_item_t *item = uri ? input_item_NewFile( uri, NULL, -1, ITEM_LOCAL )
                             : NULL;
    free( uri );
    if( item == NULL ) return VLC_ENOMEM;

    pvlc_preparse_wait_t wait;
    atomic_init( &wait.done, false );
    wait.status = ITEM_PREPARSE_FAILED;
    pvlc_preparse_cleanup_t cleanup = {
        .p_libvlc = obj->obj.libvlc,
        .p_item = item,
        .p_wait = &wait,
    };
    int ret;
    vlc_cleanup_push( pvlc_preparse_cancel_cleanup, &cleanup );
    ret = vlc_event_attach( &item->event_manager,
                                vlc_InputItemPreparseEnded,
                                pvlc_preparse_ended, &wait );
    if( ret == VLC_SUCCESS )
    {
        cleanup.b_attached = true;
        ret = libvlc_MetadataRequest( obj->obj.libvlc, item,
                                      META_REQUEST_OPTION_SCOPE_LOCAL
                                    | (b_fetch_external_art ? 0
                                          : META_REQUEST_OPTION_NO_ART),
                                      30000, &wait );
        if( ret == VLC_SUCCESS )
        {
            cleanup.b_pending = true;
            /* Mach semaphore_wait() is not a pthread cancellation point.
             * Waiting on it directly left every scanner worker asleep when
             * PowerVLC was closed, and the GUI then froze joining them.  A
             * short polling sleep bounds shutdown latency while consuming no
             * meaningful CPU during normal scans. */
            while( !atomic_load_explicit( &wait.done,
                                           memory_order_acquire ) )
            {
                vlc_testcancel();
                msleep( VLC_TICK_FROM_MS( 50 ) );
            }
            cleanup.b_pending = false;
        }
        vlc_event_detach( &item->event_manager, vlc_InputItemPreparseEnded,
                          pvlc_preparse_ended, &wait );
        cleanup.b_attached = false;
    }

    if( ret == VLC_SUCCESS && wait.status == ITEM_PREPARSE_DONE )
    {
        pvlc_replace_nonempty( &entry->psz_title,
                               input_item_GetMeta( item, vlc_meta_Title ) );
        pvlc_replace_nonempty( &entry->psz_artist,
                               input_item_GetMeta( item, vlc_meta_Artist ) );
        pvlc_replace_nonempty( &entry->psz_album,
                               input_item_GetMeta( item, vlc_meta_Album ) );
        for( size_t i = 0; i < VLC_META_TYPE_COUNT; ++i )
        {
            if( i == vlc_meta_Title || i == vlc_meta_Artist
             || i == vlc_meta_Album ) continue;
            entry->ppsz_meta[i] = input_item_GetMeta( item,
                                                       (vlc_meta_type_t)i );
        }
        entry->i_duration = input_item_GetDuration( item );

        vlc_mutex_lock( &item->lock );
        char **names = item->p_meta ? vlc_meta_CopyExtraNames( item->p_meta )
                                    : NULL;
        size_t count = 0;
        while( names && names[count] ) count++;
        if( count )
        {
            entry->ppsz_extra_names = calloc( count,
                                      sizeof( *entry->ppsz_extra_names ) );
            entry->ppsz_extra_values = calloc( count,
                                       sizeof( *entry->ppsz_extra_values ) );
            if( entry->ppsz_extra_names && entry->ppsz_extra_values )
                for( size_t i = 0; i < count; ++i )
                {
                    const char *value = vlc_meta_GetExtra( item->p_meta,
                                                           names[i] );
                    entry->ppsz_extra_names[i] = strdup( names[i] );
                    entry->ppsz_extra_values[i] = strdup( value ? value : "" );
                    if( !entry->ppsz_extra_names[i]
                     || !entry->ppsz_extra_values[i] ) break;
                    entry->i_extra_count++;
                }
        }
        vlc_mutex_unlock( &item->lock );
        for( size_t i = 0; names && names[i]; ++i ) free( names[i] );
        free( names );
    }
    else
        msg_Warn( obj, "metadata preparse failed for %s", entry->psz_path );

    vlc_cleanup_pop();
    input_item_Release( item );
    /* A corrupt media file must not make the entire library disappear: its
     * path-derived fallback metadata is still valid and remains cached. */
    return VLC_SUCCESS;
}

static int pvlc_scan_file_known( vlc_object_t *obj, const char *path,
                                 const char *relative, const struct stat *st,
                                 bool b_fetch_external_art,
                                 pvlc_media_entry_t *entry )
{
    memset( entry, 0, sizeof( *entry ) );
    if( path == NULL || st == NULL || !S_ISREG( st->st_mode )
     || pvlc_media_type( path, &entry->i_type ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    entry->psz_path = strdup( path );
    entry->psz_relative = strdup( relative ? relative : path );
    entry->i_size = (uint64_t)st->st_size;
    entry->i_mtime = (int64_t)st->st_mtime;
    if( entry->psz_path == NULL || entry->psz_relative == NULL
     || pvlc_infer_metadata( relative ? relative : path, entry ) != VLC_SUCCESS )
    {
        pvlc_media_entry_clear( entry );
        return VLC_ENOMEM;
    }
    /* Music is the managed, metadata-driven library. Videos deliberately keep
     * a cheap path-only index and are browsed through their folder tree. */
    return entry->i_type == PVLC_MEDIA_AUDIO
         ? pvlc_read_metadata( obj, entry, b_fetch_external_art )
         : VLC_SUCCESS;
}

int pvlc_scan_file( vlc_object_t *obj, const char *path,
                    const char *relative, pvlc_media_entry_t *entry )
{
    struct stat st;
    if( path == NULL || vlc_stat( path, &st ) != 0 )
        return VLC_EGENERIC;
    return pvlc_scan_file_known( obj, path, relative, &st, true, entry );
}

static int pvlc_count_recursive( vlc_object_t *p_obj, const char *psz_root,
                                 const char *psz_relative, unsigned i_depth,
                                 uint64_t *pi_count )
{
    if( i_depth > 64 ) return VLC_SUCCESS;
    char *psz_dir = *psz_relative ? pvlc_path_join( psz_root, psz_relative )
                                  : strdup( psz_root );
    if( psz_dir == NULL ) return VLC_ENOMEM;
    DIR *p_dir = vlc_opendir( psz_dir );
    if( p_dir == NULL ) { free( psz_dir ); return VLC_EGENERIC; }

    int i_ret = VLC_SUCCESS;
    const char *psz_name;
    for( ;; )
    {
        /* readdir() uses NULL for both end-of-directory and an I/O error.
         * Network filesystems can fail halfway through a large directory;
         * accepting that as EOF makes the resulting count look complete. */
        errno = 0;
        psz_name = vlc_readdir( p_dir );
        if( psz_name == NULL )
        {
            if( errno != 0 )
            {
                msg_Warn( p_obj, "cannot finish counting media folder %s: %s",
                          psz_dir, vlc_strerror_c( errno ) );
                i_ret = VLC_EGENERIC;
            }
            break;
        }
        vlc_testcancel();
        if( psz_name[0] == '.' ) continue;
        char *psz_rel = *psz_relative ? pvlc_path_join( psz_relative, psz_name )
                                      : strdup( psz_name );
        char *psz_full = psz_rel ? pvlc_path_join( psz_root, psz_rel ) : NULL;
        if( psz_rel == NULL || psz_full == NULL )
            i_ret = VLC_ENOMEM;
        else
        {
            struct stat st;
            if( vlc_lstat( psz_full, &st ) == 0 && S_ISDIR( st.st_mode ) )
                i_ret = pvlc_count_recursive( p_obj, psz_root, psz_rel,
                                              i_depth + 1, pi_count );
            else if( vlc_stat( psz_full, &st ) == 0 && S_ISREG( st.st_mode ) )
            {
                pvlc_media_type_t i_type;
                if( pvlc_media_type( psz_full, &i_type ) == VLC_SUCCESS )
                    (*pi_count)++;
            }
        }
        free( psz_full ); free( psz_rel );
        if( i_ret != VLC_SUCCESS ) break;
    }
    closedir( p_dir ); free( psz_dir );
    return i_ret;
}

int pvlc_count_media_files( vlc_object_t *p_obj, const char *psz_root,
                            uint64_t *pi_count )
{
    if( pi_count == NULL ) return VLC_EGENERIC;
    *pi_count = 0;
    struct stat st;
    if( psz_root == NULL || vlc_stat( psz_root, &st ) != 0
     || !S_ISDIR( st.st_mode ) ) return VLC_EGENERIC;
    return pvlc_count_recursive( p_obj, psz_root, "", 0, pi_count );
}

static const pvlc_media_entry_t *pvlc_cached_entry_find(
    const pvlc_media_catalog_t *, const char * );

typedef struct
{
    char *psz_path;
    char *psz_relative;
    uint64_t i_size;
    int64_t i_mtime;
    bool b_have_stat;
} pvlc_scan_task_t;

typedef struct
{
    pvlc_scan_task_t *p_tasks;
    size_t i_count;
    size_t i_capacity;
} pvlc_scan_tasks_t;

typedef struct
{
    vlc_object_t *p_obj;
    pvlc_scan_tasks_t *p_tasks;
    pvlc_media_catalog_t *p_catalog;
    const pvlc_media_catalog_t *p_cached;
    uint64_t i_done;
    uint64_t i_total;
    int i_result;
    pvlc_scan_progress_cb pf_progress;
    void *p_opaque;
    bool b_remote;
    FILE *p_report;
} pvlc_scan_batch_context_t;

static int pvlc_process_scan_batch( pvlc_scan_batch_context_t * );

static void pvlc_scan_report_issue( FILE *p_report, const char *psz_reason,
                                    const char *psz_path )
{
    if( p_report == NULL || psz_reason == NULL || psz_path == NULL ) return;
    fprintf( p_report, "%s\t", psz_reason );
    for( const char *p = psz_path; *p; ++p )
        fputc( *p == '\t' || *p == '\r' || *p == '\n' ? ' ' : *p,
               p_report );
    fputc( '\n', p_report );
}

static void pvlc_scan_tasks_clear( pvlc_scan_tasks_t *p_tasks )
{
    for( size_t i = 0; i < p_tasks->i_count; ++i )
    {
        free( p_tasks->p_tasks[i].psz_path );
        free( p_tasks->p_tasks[i].psz_relative );
    }
    free( p_tasks->p_tasks );
    memset( p_tasks, 0, sizeof( *p_tasks ) );
}

static int pvlc_scan_tasks_append( pvlc_scan_tasks_t *p_tasks,
                                   char *psz_path, char *psz_relative,
                                   const struct stat *p_stat )
{
    if( p_tasks->i_count == p_tasks->i_capacity )
    {
        size_t i_capacity = p_tasks->i_capacity
                          ? p_tasks->i_capacity * 2 : 256;
        pvlc_scan_task_t *p = realloc( p_tasks->p_tasks,
                                      i_capacity * sizeof( *p ) );
        if( p == NULL ) return VLC_ENOMEM;
        p_tasks->p_tasks = p;
        p_tasks->i_capacity = i_capacity;
    }
    p_tasks->p_tasks[p_tasks->i_count++] = (pvlc_scan_task_t) {
        .psz_path = psz_path,
        .psz_relative = psz_relative,
        .i_size = p_stat ? (uint64_t)p_stat->st_size : 0,
        .i_mtime = p_stat ? (int64_t)p_stat->st_mtime : 0,
        .b_have_stat = p_stat != NULL,
    };
    return VLC_SUCCESS;
}

/* Enumerate once, without opening media payloads. The resulting compact task
 * array lets the metadata phase keep several high-latency reads in flight. */
static int pvlc_collect_scan_tasks( vlc_object_t *p_obj,
                                    const char *psz_root,
                                    const char *psz_relative,
                                    unsigned i_depth,
                                    pvlc_scan_batch_context_t *p_batch )
{
    if( i_depth > 64 )
        return VLC_SUCCESS;
    char *psz_dir = *psz_relative ? pvlc_path_join( psz_root, psz_relative )
                                  : strdup( psz_root );
    if( psz_dir == NULL )
        return VLC_ENOMEM;
    DIR *p_dir = vlc_opendir( psz_dir );
    if( p_dir == NULL )
    {
        msg_Warn( p_obj, "cannot scan media folder %s: %s", psz_dir,
                  vlc_strerror_c( errno ) );
        pvlc_scan_report_issue( p_batch->p_report,
                                "unreadable-directory", psz_dir );
        free( psz_dir );
        /* A NAS can retain directory entries whose names the current client
         * can enumerate but no longer open (for example legacy AFP names
         * containing characters forbidden by SMB).  Skip that isolated
         * subtree; only failure to open the configured root invalidates the
         * scan. */
        return i_depth == 0 ? VLC_EGENERIC : VLC_SUCCESS;
    }

    int i_ret = VLC_SUCCESS;
    struct dirent *p_entry;
    for( ;; )
    {
        /* A transient SMB/AFP error must not be mistaken for a clean EOF.
         * Otherwise the caller commits a valid-looking but truncated cache. */
        errno = 0;
        p_entry = readdir( p_dir );
        if( p_entry == NULL )
        {
            if( errno != 0 )
            {
                msg_Warn( p_obj, "cannot finish scanning media folder %s: %s",
                          psz_dir, vlc_strerror_c( errno ) );
                pvlc_scan_report_issue( p_batch->p_report,
                                        "unreadable-directory", psz_dir );
                i_ret = VLC_EGENERIC;
            }
            break;
        }
        vlc_testcancel();
        const char *psz_name = p_entry->d_name;
        if( !strcmp( psz_name, "." ) || !strcmp( psz_name, ".." ) )
            continue;
        char *psz_rel = *psz_relative ? pvlc_path_join( psz_relative, psz_name )
                                      : strdup( psz_name );
        char *psz_full = psz_rel ? pvlc_path_join( psz_root, psz_rel ) : NULL;
        if( psz_rel == NULL || psz_full == NULL )
        {
            free( psz_rel );
            free( psz_full );
            i_ret = VLC_ENOMEM;
            break;
        }
        if( psz_name[0] == '.' )
        {
            pvlc_scan_report_issue( p_batch->p_report, "hidden", psz_full );
            free( psz_full );
            free( psz_rel );
            continue;
        }
        struct stat st;
        bool b_have_stat = false;
        bool b_directory = false;
        bool b_regular = false;
#if defined(DT_DIR) && defined(DT_REG) && defined(DT_LNK) && defined(DT_UNKNOWN)
        /* SMB already supplies the object type in its directory reply on
         * modern macOS.  Trust that cheap hint for directories and ordinary
         * files so their attributes can be fetched concurrently by the
         * metadata workers instead of issuing one serial lstat round trip per
         * entry.  Unknown types and links retain the fully portable fallback. */
        if( p_entry->d_type == DT_DIR )
            b_directory = true;
        else if( p_entry->d_type == DT_REG )
            b_regular = true;
        else if( p_entry->d_type == DT_LNK )
        {
            b_have_stat = vlc_stat( psz_full, &st ) == 0;
            b_regular = b_have_stat && S_ISREG( st.st_mode );
        }
        else if( p_entry->d_type == DT_UNKNOWN )
#endif
        {
            b_have_stat = vlc_lstat( psz_full, &st ) == 0;
            b_directory = b_have_stat && S_ISDIR( st.st_mode );
            b_regular = b_have_stat && S_ISREG( st.st_mode );
#ifndef _WIN32
            if( b_have_stat && S_ISLNK( st.st_mode ) )
            {
                b_have_stat = vlc_stat( psz_full, &st ) == 0;
                b_regular = b_have_stat && S_ISREG( st.st_mode );
            }
#endif
            if( !b_have_stat )
                pvlc_scan_report_issue( p_batch->p_report,
                                        "unavailable", psz_full );
        }

        if( b_directory )
            i_ret = pvlc_collect_scan_tasks( p_obj, psz_root, psz_rel,
                                             i_depth + 1, p_batch );
        else if( b_regular )
        {
            pvlc_media_type_t i_type;
            if( pvlc_media_type( psz_full, &i_type ) == VLC_SUCCESS )
            {
                i_ret = pvlc_scan_tasks_append( p_batch->p_tasks,
                                                psz_full, psz_rel,
                                                b_have_stat ? &st : NULL );
                if( i_ret == VLC_SUCCESS )
                {
                    psz_full = NULL;
                    psz_rel = NULL;
                    /* Prime all worker lanes as soon as the first eight
                     * files exist, so the UI leaves zero promptly. Later
                     * batches amortize traversal/dispatch overhead over
                     * two hundred files. */
                    size_t i_batch_size = p_batch->i_done == 0 ? 8 : 200;
                    if( p_batch->p_tasks->i_count >= i_batch_size )
                        i_ret = pvlc_process_scan_batch( p_batch );
                }
            }
            else
                pvlc_scan_report_issue( p_batch->p_report,
                                        "unsupported", psz_full );
        }
        free( psz_full );
        free( psz_rel );
        if( i_ret != VLC_SUCCESS )
            break;
    }
    closedir( p_dir );
    free( psz_dir );
    return i_ret;
}

typedef struct
{
    vlc_object_t *p_obj;
    pvlc_scan_tasks_t *p_tasks;
    pvlc_media_catalog_t *p_catalog;
    const pvlc_media_catalog_t *p_cached;
    size_t i_next;
    uint64_t i_done;
    uint64_t i_total;
    int i_result;
    pvlc_scan_progress_cb pf_progress;
    void *p_opaque;
    FILE *p_report;
    vlc_mutex_t lock;
} pvlc_scan_workers_t;

static void *pvlc_run_scan_worker( void *p_opaque )
{
    pvlc_scan_workers_t *p = p_opaque;
    for( ;; )
    {
        vlc_mutex_lock( &p->lock );
        size_t i = p->i_next++;
        vlc_mutex_unlock( &p->lock );
        if( i >= p->p_tasks->i_count ) break;

        pvlc_scan_task_t *p_task = &p->p_tasks->p_tasks[i];
        pvlc_media_entry_t entry;
        memset( &entry, 0, sizeof( entry ) );
        struct stat st;
        int i_ret = VLC_SUCCESS;
        if( !p_task->b_have_stat )
        {
            if( vlc_stat( p_task->psz_path, &st ) != 0
             || !S_ISREG( st.st_mode ) )
                i_ret = VLC_EGENERIC;
            else
            {
                p_task->i_size = (uint64_t)st.st_size;
                p_task->i_mtime = (int64_t)st.st_mtime;
                p_task->b_have_stat = true;
            }
        }
        const pvlc_media_entry_t *p_known = p->p_cached
            ? pvlc_cached_entry_find( p->p_cached, p_task->psz_path ) : NULL;
        if( i_ret == VLC_SUCCESS && p_known
         && p_known->i_size == p_task->i_size
         && p_known->i_mtime == p_task->i_mtime )
            i_ret = pvlc_entry_dup( &entry, p_known );
        else if( i_ret == VLC_SUCCESS )
        {
            struct stat st = {
                .st_mode = S_IFREG,
                .st_size = (off_t)p_task->i_size,
                .st_mtime = (time_t)p_task->i_mtime,
            };
            i_ret = pvlc_scan_file_known( p->p_obj, p_task->psz_path,
                                          p_task->psz_relative, &st, false,
                                          &entry );
        }

        /* A file can disappear, be locked, or time out independently while a
         * network folder is being scanned.  Do not discard the whole library
         * for that transient failure: leave it out of this checkpoint and let
         * the next incremental pass retry it.  Allocation failures remain
         * fatal because continuing could silently create a partial catalog. */
        if( i_ret != VLC_SUCCESS && i_ret != VLC_ENOMEM )
        {
            msg_Warn( p->p_obj, "skipping unavailable media %s",
                      p_task->psz_path );
            vlc_mutex_lock( &p->lock );
            pvlc_scan_report_issue( p->p_report, "unavailable",
                                    p_task->psz_path );
            vlc_mutex_unlock( &p->lock );
            i_ret = VLC_SUCCESS;
        }

        /* Catalog mutation, checkpoint serialization and UI callbacks remain
         * one ordered lane. Only slow, independent metadata reads overlap. */
        vlc_mutex_lock( &p->lock );
        if( i_ret == VLC_SUCCESS && entry.psz_path != NULL )
            i_ret = pvlc_catalog_add_owned( p->p_catalog, &entry );
        if( i_ret != VLC_SUCCESS && p->i_result == VLC_SUCCESS )
            p->i_result = i_ret;
        pvlc_media_entry_clear( &entry );
        p->i_done++;
        if( p->pf_progress )
            p->pf_progress( p->p_opaque, p->i_done, p->i_total );
        vlc_mutex_unlock( &p->lock );
    }
    return NULL;
}

typedef struct
{
    vlc_thread_t *p_threads;
    size_t i_first;
    size_t i_count;
} pvlc_scan_threads_cleanup_t;

static void pvlc_cleanup_scan_threads( void *p_opaque )
{
    pvlc_scan_threads_cleanup_t *p = p_opaque;
    for( size_t i = p->i_first; i < p->i_count; ++i )
        vlc_cancel( p->p_threads[i] );
    for( size_t i = p->i_first; i < p->i_count; ++i )
        vlc_join( p->p_threads[i], NULL );
}

static int pvlc_process_scan_batch( pvlc_scan_batch_context_t *p_batch )
{
    pvlc_scan_tasks_t *p_tasks = p_batch->p_tasks;
    if( p_tasks->i_count == 0 ) return VLC_SUCCESS;

    unsigned cpus = vlc_GetCPUCount();
    if( cpus == 0 ) cpus = 1;
    /* Network metadata reads are latency-bound. A one-core G3 still needs a
     * few requests in flight instead of serializing every SMB/AFP round trip. */
    size_t i_worker_count = p_batch->b_remote ? cpus + 3 : cpus;
    if( i_worker_count > 16 ) i_worker_count = 16;
    if( i_worker_count > p_tasks->i_count )
        i_worker_count = p_tasks->i_count;
    msg_Dbg( p_batch->p_obj,
             "scanning metadata batch of %zu media with %zu worker%s",
             p_tasks->i_count, i_worker_count,
             i_worker_count == 1 ? "" : "s" );

    pvlc_scan_workers_t workers = {
        .p_obj = p_batch->p_obj,
        .p_tasks = p_tasks,
        .p_catalog = p_batch->p_catalog,
        .p_cached = p_batch->p_cached,
        .i_done = p_batch->i_done,
        .i_total = p_batch->i_total,
        .i_result = VLC_SUCCESS,
        .pf_progress = p_batch->pf_progress,
        .p_opaque = p_batch->p_opaque,
        .p_report = p_batch->p_report,
    };
    vlc_mutex_init( &workers.lock );

    vlc_thread_t *p_threads = calloc( i_worker_count, sizeof( *p_threads ) );
    size_t i_started = 0;
    while( p_threads && i_started < i_worker_count )
    {
        if( vlc_clone( &p_threads[i_started], pvlc_run_scan_worker, &workers,
                       VLC_THREAD_PRIORITY_LOW ) )
            break;
        i_started++;
    }
    if( i_started == 0 )
        pvlc_run_scan_worker( &workers );
    else
    {
        pvlc_scan_threads_cleanup_t cleanup = {
            .p_threads = p_threads, .i_count = i_started,
        };
        vlc_cleanup_push( pvlc_cleanup_scan_threads, &cleanup );
        for( size_t i = 0; i < i_started; ++i )
        {
            vlc_join( p_threads[i], NULL );
            cleanup.i_first = i + 1;
        }
        vlc_cleanup_pop();
    }
    p_batch->i_done = workers.i_done;
    if( workers.i_result != VLC_SUCCESS )
        p_batch->i_result = workers.i_result;
    free( p_threads );
    vlc_mutex_destroy( &workers.lock );
    pvlc_scan_tasks_clear( p_tasks );
    return workers.i_result;
}

int pvlc_scan_folder_progress( vlc_object_t *p_obj, const char *psz_root,
                               pvlc_media_catalog_t *p_catalog,
                               uint64_t i_total,
                               pvlc_scan_progress_cb pf_progress,
                               void *p_opaque )
{
    return pvlc_scan_folder_resume_progress( p_obj, psz_root, p_catalog, NULL,
                                             i_total, pf_progress, p_opaque );
}

int pvlc_scan_folder_resume_progress( vlc_object_t *p_obj,
                               const char *psz_root,
                               pvlc_media_catalog_t *p_catalog,
                               const pvlc_media_catalog_t *p_cached,
                               uint64_t i_total,
                               pvlc_scan_progress_cb pf_progress,
                               void *p_opaque )
{
    return pvlc_scan_folder_resume_report_progress( p_obj, psz_root,
                    p_catalog, p_cached, i_total, pf_progress, p_opaque,
                    NULL );
}

int pvlc_scan_folder_resume_report_progress( vlc_object_t *p_obj,
                               const char *psz_root,
                               pvlc_media_catalog_t *p_catalog,
                               const pvlc_media_catalog_t *p_cached,
                               uint64_t i_total,
                               pvlc_scan_progress_cb pf_progress,
                               void *p_opaque, FILE *p_report )
{
    struct stat st;
    if( psz_root == NULL || vlc_stat( psz_root, &st ) != 0
     || !S_ISDIR( st.st_mode ) )
        return VLC_EGENERIC;

    pvlc_scan_tasks_t tasks = { 0 };
#ifdef __APPLE__
    struct statfs fs;
    bool remote = statfs( psz_root, &fs ) == 0 && !(fs.f_flags & MNT_LOCAL);
#else
    bool remote = false;
#endif
    pvlc_scan_batch_context_t batch = {
        .p_obj = p_obj,
        .p_tasks = &tasks,
        .p_catalog = p_catalog,
        .p_cached = p_cached,
        .i_total = i_total,
        .i_result = VLC_SUCCESS,
        .pf_progress = pf_progress,
        .p_opaque = p_opaque,
        .b_remote = remote,
        .p_report = p_report,
    };
    int i_ret = pvlc_collect_scan_tasks( p_obj, psz_root, "", 0, &batch );
    if( i_ret == VLC_SUCCESS )
        i_ret = pvlc_process_scan_batch( &batch );
    if( i_ret == VLC_SUCCESS ) i_ret = batch.i_result;
    pvlc_scan_tasks_clear( &tasks );
    if( i_ret == VLC_SUCCESS )
        pvlc_catalog_finalize( p_catalog );
    return i_ret;
}

int pvlc_scan_folder( vlc_object_t *p_obj, const char *psz_root,
                      pvlc_media_catalog_t *p_catalog )
{
    return pvlc_scan_folder_progress( p_obj, psz_root, p_catalog, 0,
                                      NULL, NULL );
}

typedef struct
{
    char *psz_relative;
    int64_t i_mtime;
    bool b_dirty;
} pvlc_directory_state_t;

typedef struct
{
    pvlc_directory_state_t *p_dirs;
    size_t i_count;
    size_t i_capacity;
} pvlc_directory_snapshot_t;

static const unsigned char pvlc_directory_magic[8] = {
    'P', 'V', 'L', 'C', 'D', 'R', 1, 0
};

static void pvlc_directory_snapshot_clear( pvlc_directory_snapshot_t *snapshot )
{
    for( size_t i = 0; i < snapshot->i_count; ++i )
        free( snapshot->p_dirs[i].psz_relative );
    free( snapshot->p_dirs );
    memset( snapshot, 0, sizeof( *snapshot ) );
}

static pvlc_directory_state_t *pvlc_directory_find(
    pvlc_directory_snapshot_t *snapshot, const char *relative )
{
    size_t low = 0, high = snapshot->i_count;
    while( low < high )
    {
        size_t middle = low + (high - low) / 2;
        int order = strcmp( snapshot->p_dirs[middle].psz_relative, relative );
        if( order < 0 ) low = middle + 1;
        else if( order > 0 ) high = middle;
        else return &snapshot->p_dirs[middle];
    }
    return NULL;
}

static int pvlc_directory_compare( const void *a, const void *b )
{
    const pvlc_directory_state_t *da = a, *db = b;
    return strcmp( da->psz_relative, db->psz_relative );
}

static void pvlc_directory_snapshot_sort( pvlc_directory_snapshot_t *snapshot )
{
    if( snapshot->i_count > 1 )
        qsort( snapshot->p_dirs, snapshot->i_count,
               sizeof( *snapshot->p_dirs ), pvlc_directory_compare );
}

static int pvlc_directory_append( pvlc_directory_snapshot_t *snapshot,
                                  const char *relative, int64_t mtime )
{
    if( snapshot->i_count == snapshot->i_capacity )
    {
        size_t capacity = snapshot->i_capacity ? snapshot->i_capacity * 2 : 64;
        pvlc_directory_state_t *dirs = realloc( snapshot->p_dirs,
                                                capacity * sizeof( *dirs ) );
        if( dirs == NULL ) return VLC_ENOMEM;
        snapshot->p_dirs = dirs;
        snapshot->i_capacity = capacity;
    }
    pvlc_directory_state_t *dir = &snapshot->p_dirs[snapshot->i_count++];
    dir->psz_relative = strdup( relative );
    dir->i_mtime = mtime;
    dir->b_dirty = false;
    return dir->psz_relative ? VLC_SUCCESS : VLC_ENOMEM;
}

static char *pvlc_directory_snapshot_path( const char *db )
{
    char *path = NULL;
    if( db && asprintf( &path, "%s.dirs", db ) < 0 ) path = NULL;
    return path;
}

static int pvlc_directory_snapshot_load( const char *db,
                                         pvlc_directory_snapshot_t *snapshot )
{
    char *path = pvlc_directory_snapshot_path( db );
    FILE *file = path ? vlc_fopen( path, "rb" ) : NULL;
    free( path );
    if( file == NULL ) return VLC_EGENERIC;
    unsigned char magic[sizeof( pvlc_directory_magic )];
    uint64_t count = 0;
    int ret = pvlc_binary_read( file, magic, sizeof( magic ) );
    if( ret == VLC_SUCCESS
     && memcmp( magic, pvlc_directory_magic, sizeof( magic ) ) )
        ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file, &count );
    if( ret == VLC_SUCCESS && (count > UINT32_MAX
                            || count > SIZE_MAX / sizeof( *snapshot->p_dirs )) )
        ret = VLC_EGENERIC;
    for( uint64_t i = 0; i < count && ret == VLC_SUCCESS; ++i )
    {
        char *relative = NULL; uint64_t mtime = 0;
        ret = pvlc_binary_read_string( file, &relative, 16 * 1024 * 1024 );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( file, &mtime );
        if( ret == VLC_SUCCESS )
            ret = pvlc_directory_append( snapshot, relative, (int64_t)mtime );
        free( relative );
    }
    fclose( file );
    if( ret == VLC_SUCCESS ) pvlc_directory_snapshot_sort( snapshot );
    if( ret != VLC_SUCCESS ) pvlc_directory_snapshot_clear( snapshot );
    return ret;
}

static int pvlc_directory_snapshot_save( vlc_object_t *obj, const char *db,
                                  const pvlc_directory_snapshot_t *snapshot )
{
    char *path = pvlc_directory_snapshot_path( db );
    char *tmp = NULL;
    if( path == NULL || asprintf( &tmp, "%s.tmp", path ) < 0 )
    { free( path ); free( tmp ); return VLC_ENOMEM; }
    FILE *file = vlc_fopen( tmp, "wb" );
    int ret = file ? VLC_SUCCESS : VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write( file,
                                    pvlc_directory_magic,
                                    sizeof( pvlc_directory_magic ) );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file,
                                                          snapshot->i_count );
    for( size_t i = 0; i < snapshot->i_count && ret == VLC_SUCCESS; ++i )
    {
        ret = pvlc_binary_write_string( file,
                                        snapshot->p_dirs[i].psz_relative );
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( file,
                                    (uint64_t)snapshot->p_dirs[i].i_mtime );
    }
    bool error = ret != VLC_SUCCESS || !file;
    if( file )
    {
        if( fflush( file ) != 0 || ferror( file ) ) error = true;
        if( fclose( file ) != 0 ) error = true;
    }
    if( !error )
    {
#ifdef _WIN32
        vlc_unlink( path );
#endif
        error = vlc_rename( tmp, path ) != 0;
    }
    if( error )
    {
        msg_Warn( obj, "cannot commit directory snapshot %s", path );
        vlc_unlink( tmp );
    }
    free( tmp ); free( path );
    return error ? VLC_EGENERIC : VLC_SUCCESS;
}

static bool pvlc_relative_belongs_to( const char *path, const char *directory )
{
    size_t length = strlen( directory );
    return length == 0 || (!strncmp( path, directory, length )
        && (path[length] == '\0' || pvlc_is_separator( path[length] )));
}

static void pvlc_mark_directory_dirty( pvlc_directory_snapshot_t *snapshot,
                                       const char *relative )
{
    for( size_t i = 0; i < snapshot->i_count; ++i )
        if( pvlc_relative_belongs_to( relative,
                                      snapshot->p_dirs[i].psz_relative ) )
            snapshot->p_dirs[i].b_dirty = true;
}

static const pvlc_media_entry_t *pvlc_cached_entry_find(
    const pvlc_media_catalog_t *catalog, const char *path )
{
    size_t low = 0, high = catalog->i_count;
    while( low < high )
    {
        size_t middle = low + (high - low) / 2;
        int order = strcasecmp( catalog->p_entries[middle].psz_path, path );
        if( order < 0 ) low = middle + 1;
        else if( order > 0 ) high = middle;
        else return &catalog->p_entries[middle];
    }
    return NULL;
}

static int pvlc_copy_cached_subtree( const pvlc_media_catalog_t *cached,
                                     const char *relative,
                                     pvlc_media_catalog_t *fresh )
{
    size_t low = 0, high = cached->i_count;
    while( low < high )
    {
        size_t middle = low + (high - low) / 2;
        int order = strcmp( cached->p_entries[middle].psz_relative, relative );
        if( order < 0 ) low = middle + 1; else high = middle;
    }
    for( size_t i = low; i < cached->i_count; ++i )
    {
        const pvlc_media_entry_t *source = &cached->p_entries[i];
        if( !pvlc_relative_belongs_to( source->psz_relative, relative ) )
            break;
        pvlc_media_entry_t copy;
        int ret = pvlc_entry_dup( &copy, source );
        if( ret == VLC_SUCCESS ) ret = pvlc_catalog_add_owned( fresh, &copy );
        if( ret != VLC_SUCCESS )
        { pvlc_media_entry_clear( &copy ); return ret; }
    }
    return VLC_SUCCESS;
}

static int pvlc_copy_directory_subtree(
    const pvlc_directory_snapshot_t *old, const char *relative,
    pvlc_directory_snapshot_t *fresh )
{
    size_t low = 0, high = old->i_count;
    while( low < high )
    {
        size_t middle = low + (high - low) / 2;
        int order = strcmp( old->p_dirs[middle].psz_relative, relative );
        if( order < 0 ) low = middle + 1; else high = middle;
    }
    for( size_t i = low; i < old->i_count; ++i )
        if( pvlc_relative_belongs_to( old->p_dirs[i].psz_relative, relative ) )
        {
            int ret = pvlc_directory_append( fresh,
                       old->p_dirs[i].psz_relative, old->p_dirs[i].i_mtime );
            if( ret != VLC_SUCCESS ) return ret;
        }
        else break;
    return VLC_SUCCESS;
}

static int pvlc_incremental_directory( vlc_object_t *obj, const char *root,
    const char *relative, const pvlc_media_catalog_t *cached,
    pvlc_directory_snapshot_t *old, pvlc_media_catalog_t *fresh,
    pvlc_directory_snapshot_t *snapshot, unsigned depth )
{
    if( depth > 64 ) return VLC_SUCCESS;
    char *path = *relative ? pvlc_path_join( root, relative ) : strdup( root );
    if( path == NULL ) return VLC_ENOMEM;
    struct stat dir_stat;
    if( vlc_stat( path, &dir_stat ) != 0 || !S_ISDIR( dir_stat.st_mode ) )
    { free( path ); return VLC_SUCCESS; }
    pvlc_directory_state_t *previous = pvlc_directory_find( old, relative );
    if( previous && !previous->b_dirty
     && previous->i_mtime == (int64_t)dir_stat.st_mtime )
    {
        int ret = pvlc_copy_cached_subtree( cached, relative, fresh );
        if( ret == VLC_SUCCESS )
            ret = pvlc_copy_directory_subtree( old, relative, snapshot );
        free( path );
        return ret;
    }
    int ret = pvlc_directory_append( snapshot, relative,
                                      (int64_t)dir_stat.st_mtime );
    DIR *dir = ret == VLC_SUCCESS ? vlc_opendir( path ) : NULL;
    if( dir == NULL )
    { free( path ); return ret == VLC_SUCCESS ? VLC_EGENERIC : ret; }
    const char *name;
    while( ret == VLC_SUCCESS )
    {
        /* Do not replace a complete cache with a partial incremental view if
         * a remote directory stops yielding entries partway through. */
        errno = 0;
        name = vlc_readdir( dir );
        if( name == NULL )
        {
            if( errno != 0 )
            {
                msg_Warn( obj,
                          "cannot finish refreshing media folder %s: %s",
                          path, vlc_strerror_c( errno ) );
                ret = VLC_EGENERIC;
            }
            break;
        }
        vlc_testcancel();
        if( name[0] == '.' ) continue;
        char *child_rel = *relative ? pvlc_path_join( relative, name )
                                    : strdup( name );
        char *child = child_rel ? pvlc_path_join( root, child_rel ) : NULL;
        if( child_rel == NULL || child == NULL ) ret = VLC_ENOMEM;
        else
        {
            struct stat st;
            if( vlc_lstat( child, &st ) == 0 && S_ISDIR( st.st_mode ) )
                ret = pvlc_incremental_directory( obj, root, child_rel,
                      cached, old, fresh, snapshot, depth + 1 );
            else if( vlc_stat( child, &st ) == 0 && S_ISREG( st.st_mode ) )
            {
                pvlc_media_type_t type;
                if( pvlc_media_type( child, &type ) == VLC_SUCCESS )
                {
                    const pvlc_media_entry_t *known =
                        pvlc_cached_entry_find( cached, child );
                    pvlc_media_entry_t entry;
                    if( known && known->i_size == (uint64_t)st.st_size
                     && known->i_mtime == (int64_t)st.st_mtime )
                        ret = pvlc_entry_dup( &entry, known );
                    else
                        ret = pvlc_scan_file( obj, child, child_rel, &entry );
                    if( ret == VLC_SUCCESS )
                        ret = pvlc_catalog_add_owned( fresh, &entry );
                    pvlc_media_entry_clear( &entry );
                }
            }
        }
        free( child ); free( child_rel );
    }
    closedir( dir ); free( path );
    return ret;
}

bool pvlc_folder_cache_available( const char *psz_root )
{
    char *psz_path = pvlc_path_join( psz_root, PVLC_FOLDER_DB );
    bool b_available = pvlc_folder_cache_available_at( psz_path );
    free( psz_path );
    return b_available;
}

bool pvlc_folder_cache_available_at( const char *psz_path )
{
    struct stat st;
    return psz_path && vlc_stat( psz_path, &st ) == 0
         && S_ISREG( st.st_mode );
}

static bool pvlc_escape_safe( unsigned char c )
{
    return c >= 0x20 && c != '%' && c != '\t' && c != '\r' && c != '\n';
}

char *pvlc_escape( const char *psz_value )
{
    if( psz_value == NULL )
        return strdup( "" );
    size_t n = strlen( psz_value );
    char *psz_out = malloc( n * 3 + 1 );
    if( psz_out == NULL )
        return NULL;
    static const char hex[] = "0123456789ABCDEF";
    char *p = psz_out;
    for( size_t i = 0; i < n; ++i )
    {
        unsigned char c = (unsigned char)psz_value[i];
        if( pvlc_escape_safe( c ) )
            *p++ = (char)c;
        else
        {
            *p++ = '%';
            *p++ = hex[c >> 4];
            *p++ = hex[c & 15];
        }
    }
    *p = '\0';
    return psz_out;
}

static int pvlc_hex( char c )
{
    if( c >= '0' && c <= '9' ) return c - '0';
    if( c >= 'a' && c <= 'f' ) return c - 'a' + 10;
    if( c >= 'A' && c <= 'F' ) return c - 'A' + 10;
    return -1;
}

char *pvlc_unescape( const char *psz_value )
{
    char *psz_out = strdup( psz_value ? psz_value : "" );
    if( psz_out == NULL )
        return NULL;
    char *dst = psz_out;
    const char *src = psz_value ? psz_value : "";
    while( *src )
    {
        if( src[0] == '%' && src[1] != '\0' && src[2] != '\0'
         && pvlc_hex( src[1] ) >= 0 && pvlc_hex( src[2] ) >= 0 )
        {
            *dst++ = (char)((pvlc_hex( src[1] ) << 4) | pvlc_hex( src[2] ));
            src += 3;
        }
        else
            *dst++ = *src++;
    }
    *dst = '\0';
    return psz_out;
}

static char *pvlc_relative_to( const char *psz_root, const char *psz_path )
{
    size_t n = strlen( psz_root );
    if( strncmp( psz_root, psz_path, n ) != 0 )
        return NULL;
    const char *p = psz_path + n;
    while( pvlc_is_separator( *p ) )
        p++;
    return strdup( p );
}

static int pvlc_write_cache_entry( FILE *f, const char *psz_root,
                                   const pvlc_media_entry_t *e )
{
    char *rel_raw = pvlc_relative_to( psz_root, e->psz_path );
    int ret = rel_raw ? pvlc_binary_write_string( f, rel_raw ) : VLC_ENOMEM;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f, e->i_size );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f,
                                                    (uint64_t)e->i_mtime );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( f,
                                                    (uint32_t)e->i_type );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u64( f,
                                                    (uint64_t)e->i_duration );
    for( size_t m = 0; m < VLC_META_TYPE_COUNT && ret == VLC_SUCCESS; ++m )
        ret = pvlc_binary_write_string( f,
                         pvlc_media_meta( e, (vlc_meta_type_t)m ) );
    if( e->i_extra_count > UINT32_MAX ) ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_write_u32( f,
                                               (uint32_t)e->i_extra_count );
    for( size_t m = 0; m < e->i_extra_count && ret == VLC_SUCCESS; ++m )
    {
        ret = pvlc_binary_write_string( f, e->ppsz_extra_names[m] );
        if( ret == VLC_SUCCESS )
            ret = pvlc_binary_write_string( f, e->ppsz_extra_values[m] );
    }
    free( rel_raw );
    return ret;
}

int pvlc_save_folder_cache_at( vlc_object_t *p_obj, const char *psz_root,
                               const char *psz_db,
                               const pvlc_media_catalog_t *p_catalog )
{
    char *psz_tmp = NULL;
    if( psz_db == NULL || asprintf( &psz_tmp, "%s.tmp", psz_db ) < 0 )
    {
        free( psz_tmp );
        return VLC_ENOMEM;
    }
    FILE *f = vlc_fopen( psz_tmp, "wb" );
    if( f == NULL )
    {
        msg_Warn( p_obj, "cannot write media cache %s: %s", psz_tmp,
                  vlc_strerror_c( errno ) );
        free( psz_tmp );
        return VLC_EGENERIC;
    }
    setvbuf( f, NULL, _IOFBF, 64 * 1024 );
    int i_ret = pvlc_binary_write( f, pvlc_folder_magic,
                                   sizeof( pvlc_folder_magic ) );
    if( i_ret == VLC_SUCCESS )
        i_ret = pvlc_binary_write_u64( f, p_catalog->i_fingerprint );
    if( i_ret == VLC_SUCCESS )
        i_ret = pvlc_binary_write_u64( f, p_catalog->i_count );
    for( size_t i = 0; i < p_catalog->i_count; ++i )
    {
        const pvlc_media_entry_t *e = &p_catalog->p_entries[i];
        if( i_ret == VLC_SUCCESS )
            i_ret = pvlc_write_cache_entry( f, psz_root, e );
        if( i_ret != VLC_SUCCESS ) break;
    }
    bool b_error = i_ret != VLC_SUCCESS || fflush( f ) != 0 || ferror( f );
    if( fclose( f ) != 0 )
        b_error = true;
    if( !b_error )
    {
#ifdef _WIN32
        vlc_unlink( psz_db );
#endif
        b_error = vlc_rename( psz_tmp, psz_db ) != 0;
    }
    if( b_error )
    {
        msg_Warn( p_obj, "cannot commit media cache %s: %s", psz_db,
                  vlc_strerror_c( errno ) );
        vlc_unlink( psz_tmp );
    }
    free( psz_tmp );
    return b_error ? VLC_EGENERIC : VLC_SUCCESS;
}

int pvlc_append_resume_cache_at( vlc_object_t *p_obj, const char *psz_root,
                                 const char *psz_db,
                                 const pvlc_media_catalog_t *p_catalog,
                                 size_t i_first )
{
    if( psz_db == NULL || i_first > p_catalog->i_count ) return VLC_EGENERIC;
    FILE *f = vlc_fopen( psz_db, i_first == 0 ? "wb" : "ab" );
    if( f == NULL ) return VLC_EGENERIC;
    setvbuf( f, NULL, _IOFBF, 64 * 1024 );
    int ret = i_first == 0
            ? pvlc_binary_write( f, pvlc_resume_magic,
                                 sizeof( pvlc_resume_magic ) ) : VLC_SUCCESS;
    for( size_t i = i_first; i < p_catalog->i_count && ret == VLC_SUCCESS; ++i )
    {
        ret = pvlc_binary_write_u32( f, PVLC_RESUME_ENTRY_BEGIN );
        if( ret == VLC_SUCCESS )
            ret = pvlc_write_cache_entry( f, psz_root,
                                          &p_catalog->p_entries[i] );
        if( ret == VLC_SUCCESS )
            ret = pvlc_binary_write_u32( f, PVLC_RESUME_ENTRY_END );
    }
    bool error = ret != VLC_SUCCESS || fflush( f ) != 0 || ferror( f );
    if( fclose( f ) != 0 ) error = true;
    if( error )
        msg_Warn( p_obj, "cannot append media scan checkpoint %s", psz_db );
    return error ? VLC_EGENERIC : VLC_SUCCESS;
}

int pvlc_save_folder_cache( vlc_object_t *p_obj, const char *psz_root,
                            const pvlc_media_catalog_t *p_catalog )
{
    char *psz_db = pvlc_path_join( psz_root, PVLC_FOLDER_DB );
    int ret = psz_db ? pvlc_save_folder_cache_at( p_obj, psz_root, psz_db,
                                                   p_catalog ) : VLC_ENOMEM;
    free( psz_db );
    return ret;
}

static char *pvlc_next_field( char **ppsz_cursor )
{
    if( *ppsz_cursor == NULL )
        return NULL;
    char *field = *ppsz_cursor;
    char *tab = strchr( field, '\t' );
    if( tab )
    {
        *tab = '\0';
        *ppsz_cursor = tab + 1;
    }
    else
        *ppsz_cursor = NULL;
    return field;
}

static int pvlc_load_folder_cache_text( FILE *f, const char *psz_root,
                                        pvlc_media_catalog_t *p_catalog )
{
    char *line = NULL;
    size_t cap = 0;
    ssize_t len = getline( &line, &cap, f );
    if( len < 0 || strncmp( line, PVLC_DB_HEADER, strlen( PVLC_DB_HEADER ) ) )
    {
        free( line );
        return VLC_EGENERIC;
    }
    int i_ret = VLC_SUCCESS;
    while( (len = getline( &line, &cap, f )) >= 0 )
    {
        while( len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r') )
            line[--len] = '\0';
        if( strncmp( line, "MEDIA\t", 6 ) )
            continue;
        char *cursor = line + 6;
        char *fields[7];
        for( size_t i = 0; i < ARRAY_SIZE( fields ); ++i )
            fields[i] = pvlc_next_field( &cursor );
        if( fields[0] == NULL || fields[1] == NULL || fields[2] == NULL
         || fields[3] == NULL || fields[4] == NULL || fields[5] == NULL
         || fields[6] == NULL )
            continue;
        char *rel = pvlc_unescape( fields[0] );
        pvlc_media_entry_t entry;
        memset( &entry, 0, sizeof( entry ) );
        entry.psz_path = rel ? pvlc_path_join( psz_root, rel ) : NULL;
        entry.psz_relative = rel ? strdup( rel ) : NULL;
        entry.i_size = strtoull( fields[1], NULL, 10 );
        entry.i_mtime = strtoll( fields[2], NULL, 10 );
        entry.i_type = atoi( fields[3] ) == PVLC_MEDIA_VIDEO
                     ? PVLC_MEDIA_VIDEO : PVLC_MEDIA_AUDIO;
        entry.psz_title = pvlc_unescape( fields[4] );
        entry.psz_artist = pvlc_unescape( fields[5] );
        entry.psz_album = pvlc_unescape( fields[6] );
        free( rel );
        if( entry.psz_path && entry.psz_relative && entry.psz_title
         && entry.psz_artist
         && entry.psz_album )
            i_ret = pvlc_catalog_add_owned( p_catalog, &entry );
        else
            i_ret = VLC_ENOMEM;
        pvlc_media_entry_clear( &entry );
        if( i_ret != VLC_SUCCESS )
            break;
    }
    free( line );
    if( i_ret == VLC_SUCCESS )
        pvlc_catalog_finalize( p_catalog );
    return i_ret;
}

static int pvlc_read_cache_entry( FILE *f, const char *psz_root,
                                  pvlc_media_entry_t *p_entry )
{
    pvlc_media_entry_t entry;
    memset( &entry, 0, sizeof( entry ) );
    char *relative = NULL;
    uint64_t mtime = 0, duration = 0;
    uint32_t type = 0;
    int ret = pvlc_binary_read_string( f, &relative, 16 * 1024 * 1024 );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( f, &entry.i_size );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( f, &mtime );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( f, &type );
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u64( f, &duration );
    for( size_t m = 0; m < VLC_META_TYPE_COUNT && ret == VLC_SUCCESS; ++m )
    {
        char **slot = m == vlc_meta_Title ? &entry.psz_title
                    : m == vlc_meta_Artist ? &entry.psz_artist
                    : m == vlc_meta_Album ? &entry.psz_album
                                         : &entry.ppsz_meta[m];
        ret = pvlc_binary_read_optional_string( f, slot, 16 * 1024 * 1024 );
    }
    uint32_t extra_count = 0;
    if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( f, &extra_count );
    if( ret == VLC_SUCCESS && extra_count > 100000 ) ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS && extra_count )
    {
        entry.ppsz_extra_names = calloc( extra_count,
                                  sizeof( *entry.ppsz_extra_names ) );
        entry.ppsz_extra_values = calloc( extra_count,
                                   sizeof( *entry.ppsz_extra_values ) );
        if( !entry.ppsz_extra_names || !entry.ppsz_extra_values )
            ret = VLC_ENOMEM;
    }
    for( uint32_t m = 0; m < extra_count && ret == VLC_SUCCESS; ++m )
    {
        ret = pvlc_binary_read_string( f, &entry.ppsz_extra_names[m],
                                        16 * 1024 * 1024 );
        if( ret == VLC_SUCCESS )
            ret = pvlc_binary_read_string( f, &entry.ppsz_extra_values[m],
                                            16 * 1024 * 1024 );
        if( ret == VLC_SUCCESS ) entry.i_extra_count++;
    }
    if( ret == VLC_SUCCESS )
    {
        entry.psz_path = pvlc_path_join( psz_root, relative );
        entry.psz_relative = strdup( relative );
        entry.i_mtime = (int64_t)mtime;
        entry.i_duration = (vlc_tick_t)duration;
        entry.i_type = type == PVLC_MEDIA_VIDEO ? PVLC_MEDIA_VIDEO
                                                : PVLC_MEDIA_AUDIO;
        if( entry.psz_path == NULL || entry.psz_relative == NULL )
            ret = VLC_ENOMEM;
    }
    free( relative );
    if( ret == VLC_SUCCESS )
        *p_entry = entry;
    else
        pvlc_media_entry_clear( &entry );
    return ret;
}

static int pvlc_load_folder_cache_binary( FILE *f, const char *psz_root,
                                          pvlc_media_catalog_t *p_catalog )
{
    uint64_t stored_fingerprint, count;
    if( pvlc_binary_read_u64( f, &stored_fingerprint ) != VLC_SUCCESS
     || pvlc_binary_read_u64( f, &count ) != VLC_SUCCESS
     || count > UINT64_C(10000000) || count > SIZE_MAX / sizeof( *p_catalog->p_entries ) )
        return VLC_EGENERIC;
    if( count )
    {
        p_catalog->p_entries = malloc( (size_t)count * sizeof( *p_catalog->p_entries ) );
        if( p_catalog->p_entries == NULL ) return VLC_ENOMEM;
        p_catalog->i_capacity = (size_t)count;
    }
    for( uint64_t i = 0; i < count; ++i )
    {
        pvlc_media_entry_t entry;
        memset( &entry, 0, sizeof( entry ) );
        int ret = pvlc_read_cache_entry( f, psz_root, &entry );
        if( ret == VLC_SUCCESS ) ret = pvlc_catalog_add_owned( p_catalog, &entry );
        pvlc_media_entry_clear( &entry );
        if( ret != VLC_SUCCESS ) return ret;
    }
    bool sorted = true;
    for( size_t i = 1; i < p_catalog->i_count; ++i )
        if( strcasecmp( p_catalog->p_entries[i - 1].psz_path,
                        p_catalog->p_entries[i].psz_path ) >= 0 )
        { sorted = false; break; }
    if( sorted )
    {
        pvlc_catalog_prepare_search( p_catalog );
        p_catalog->i_fingerprint = stored_fingerprint;
    }
    else
        pvlc_catalog_finalize( p_catalog );
    return VLC_SUCCESS;
}

static int pvlc_load_resume_cache( FILE *f, const char *psz_root,
                                   pvlc_media_catalog_t *p_catalog )
{
    for( ;; )
    {
        uint32_t marker;
        if( pvlc_binary_read_u32( f, &marker ) != VLC_SUCCESS )
            break;
        if( marker != PVLC_RESUME_ENTRY_BEGIN )
            break;
        pvlc_media_entry_t entry;
        int ret = pvlc_read_cache_entry( f, psz_root, &entry );
        uint32_t end = 0;
        if( ret == VLC_SUCCESS ) ret = pvlc_binary_read_u32( f, &end );
        if( ret != VLC_SUCCESS || end != PVLC_RESUME_ENTRY_END )
        {
            if( ret == VLC_SUCCESS ) pvlc_media_entry_clear( &entry );
            break; /* Ignore only a possibly interrupted trailing record. */
        }
        ret = pvlc_catalog_add_owned( p_catalog, &entry );
        pvlc_media_entry_clear( &entry );
        if( ret != VLC_SUCCESS ) return ret;
    }
    pvlc_catalog_finalize( p_catalog );
    return p_catalog->i_count > 0 ? VLC_SUCCESS : VLC_EGENERIC;
}

int pvlc_load_folder_cache_at( vlc_object_t *p_obj, const char *psz_root,
                               const char *psz_db,
                               pvlc_media_catalog_t *p_catalog )
{
    FILE *f = vlc_fopen( psz_db, "rb" );
    if( f == NULL ) return VLC_EGENERIC;
    setvbuf( f, NULL, _IOFBF, 64 * 1024 );
    unsigned char magic[sizeof( pvlc_folder_magic )];
    int ret = pvlc_binary_read( f, magic, sizeof( magic ) );
    bool resume = ret == VLC_SUCCESS
               && !memcmp( magic, pvlc_resume_magic, sizeof( magic ) );
    bool legacy = ret == VLC_SUCCESS && !resume
               && memcmp( magic, pvlc_folder_magic, sizeof( magic ) ) != 0;
    if( resume )
        ret = pvlc_load_resume_cache( f, psz_root, p_catalog );
    else if( ret == VLC_SUCCESS && !legacy )
        ret = pvlc_load_folder_cache_binary( f, psz_root, p_catalog );
    else if( legacy && fseek( f, 0, SEEK_SET ) == 0 )
        ret = pvlc_load_folder_cache_text( f, psz_root, p_catalog );
    else
        ret = VLC_EGENERIC;
    fclose( f );
    if( ret != VLC_SUCCESS )
    {
        msg_Warn( p_obj, "unsupported or damaged media cache %s", psz_db );
        pvlc_catalog_clear( p_catalog );
    }
    else if( legacy )
    {
        msg_Dbg( p_obj, "migrating text media cache %s to current binary format",
                 psz_db );
        pvlc_save_folder_cache_at( p_obj, psz_root, psz_db, p_catalog );
    }
    return ret;
}

int pvlc_load_folder_cache( vlc_object_t *p_obj, const char *psz_root,
                            pvlc_media_catalog_t *p_catalog )
{
    char *psz_db = pvlc_path_join( psz_root, PVLC_FOLDER_DB );
    int ret = psz_db ? pvlc_load_folder_cache_at( p_obj, psz_root, psz_db,
                                                   p_catalog ) : VLC_ENOMEM;
    free( psz_db );
    return ret;
}

int pvlc_refresh_folder_cache_at( vlc_object_t *obj, const char *root,
                                  const char *db,
                                  pvlc_media_catalog_t *catalog,
                                  bool *changed )
{
    if( changed ) *changed = false;
    pvlc_media_catalog_t cached;
    pvlc_catalog_init( &cached );
    bool cache_available = pvlc_load_folder_cache_at( obj, root, db,
                                                       &cached ) == VLC_SUCCESS;
    pvlc_directory_snapshot_t old = { 0 }, fresh_snapshot = { 0 };
    bool snapshot_available = cache_available
        && pvlc_directory_snapshot_load( db, &old ) == VLC_SUCCESS;
    bool dirty = !cache_available || !snapshot_available;

    if( snapshot_available )
    {
        for( size_t i = 0; i < old.i_count; ++i )
        {
            char *path = *old.p_dirs[i].psz_relative
                       ? pvlc_path_join( root, old.p_dirs[i].psz_relative )
                       : strdup( root );
            struct stat st;
            bool differs = path == NULL || vlc_stat( path, &st ) != 0
                        || !S_ISDIR( st.st_mode )
                        || old.p_dirs[i].i_mtime != (int64_t)st.st_mtime;
            free( path );
            if( differs )
            {
                dirty = true;
                pvlc_mark_directory_dirty( &old,
                                            old.p_dirs[i].psz_relative );
            }
        }
        /* Do not stat every cached file during periodic monitoring. On SMB
         * and AFP this was tens of thousands of synchronous round trips per
         * pass. Explicit Rescan verifies in-place tag edits on filesystems
         * which do not propagate them to their parent directory. */
    }

    if( !dirty )
    {
        *catalog = cached;
        memset( &cached, 0, sizeof( cached ) );
        pvlc_directory_snapshot_clear( &old );
        return VLC_SUCCESS;
    }

    pvlc_media_catalog_t fresh;
    pvlc_catalog_init( &fresh );
    int ret = pvlc_incremental_directory( obj, root, "", &cached, &old,
                                           &fresh, &fresh_snapshot, 0 );
    if( ret == VLC_SUCCESS )
    {
        pvlc_directory_snapshot_sort( &fresh_snapshot );
        pvlc_catalog_finalize( &fresh );
        ret = pvlc_save_folder_cache_at( obj, root, db, &fresh );
        if( ret == VLC_SUCCESS )
            ret = pvlc_directory_snapshot_save( obj, db, &fresh_snapshot );
    }
    if( ret == VLC_SUCCESS )
    {
        *catalog = fresh;
        memset( &fresh, 0, sizeof( fresh ) );
        if( changed ) *changed = true;
    }
    pvlc_catalog_clear( &fresh );
    pvlc_catalog_clear( &cached );
    pvlc_directory_snapshot_clear( &old );
    pvlc_directory_snapshot_clear( &fresh_snapshot );
    return ret;
}

char *pvlc_managed_folder( vlc_object_t *p_obj )
{
    char *psz_path = var_InheritString( p_obj, "powervlc-ml-managed-folder" );
    if( psz_path != NULL && *psz_path != '\0' )
        return psz_path;
    free( psz_path );
    char *psz_music = config_GetUserDir( VLC_MUSIC_DIR );
    if( psz_music == NULL )
        return NULL;
    psz_path = pvlc_path_join( psz_music, "PowerVLC media library" );
    free( psz_music );
    return psz_path;
}

int pvlc_copy_file( const char *psz_src, const char *psz_dst )
{
    FILE *in = vlc_fopen( psz_src, "rb" );
    if( in == NULL )
        return VLC_EGENERIC;
    FILE *out = vlc_fopen( psz_dst, "wb" );
    if( out == NULL )
    {
        fclose( in );
        return VLC_EGENERIC;
    }
    char buffer[64 * 1024];
    int i_ret = VLC_SUCCESS;
    size_t n;
    while( (n = fread( buffer, 1, sizeof( buffer ), in )) > 0 )
    {
        vlc_testcancel();
        if( fwrite( buffer, 1, n, out ) != n )
        {
            i_ret = VLC_EGENERIC;
            break;
        }
    }
    if( ferror( in ) || fflush( out ) != 0 || ferror( out ) )
        i_ret = VLC_EGENERIC;
    fclose( in );
    if( fclose( out ) != 0 )
        i_ret = VLC_EGENERIC;
    if( i_ret != VLC_SUCCESS )
        vlc_unlink( psz_dst );
    return i_ret;
}

static size_t pvlc_utf8_prefix( const char *psz, size_t i_limit )
{
    size_t n = strlen( psz );
    if( n <= i_limit )
        return n;
    n = i_limit;
    while( n > 0 && ((unsigned char)psz[n] & 0xc0) == 0x80 )
        --n;
    return n;
}

char *pvlc_sanitize_component( const char *psz_value,
                               const char *psz_fallback, size_t i_max_bytes )
{
    if( psz_value == NULL || *psz_value == '\0' )
        psz_value = psz_fallback;
    char *out = strdup( psz_value );
    if( out == NULL )
        return NULL;
    for( char *p = out; *p; ++p )
        if( (unsigned char)*p < 0x20 || strchr( "<>:\"/\\|?*", *p ) )
            *p = '_';
    size_t n = strlen( out );
    while( n > 0 && (out[n - 1] == ' ' || out[n - 1] == '.') )
        out[--n] = '\0';
    if( i_max_bytes > 0 && n > i_max_bytes )
    {
        n = pvlc_utf8_prefix( out, i_max_bytes );
        out[n] = '\0';
        while( n > 0 && (out[n - 1] == ' ' || out[n - 1] == '.') )
            out[--n] = '\0';
    }
    return n > 0 ? out : (free( out ), strdup( psz_fallback ));
}

char *pvlc_sanitize_filename( const char *psz_value, size_t i_max_bytes )
{
    char *clean = pvlc_sanitize_component( psz_value, "media", 0 );
    if( clean == NULL || i_max_bytes == 0 || strlen( clean ) <= i_max_bytes )
        return clean;
    const char *dot = strrchr( clean, '.' );
    size_t ext = dot && dot != clean && strlen( dot ) < i_max_bytes / 2
               ? strlen( dot ) : 0;
    size_t stem_limit = i_max_bytes - ext;
    size_t stem = pvlc_utf8_prefix( clean, stem_limit );
    char *out = malloc( stem + ext + 1 );
    if( out != NULL )
    {
        memcpy( out, clean, stem );
        if( ext )
            memcpy( out + stem, dot, ext );
        out[stem + ext] = '\0';
    }
    free( clean );
    return out;
}

static const char *pvlc_filename( const char *psz_path )
{
    const char *base = psz_path;
    for( const char *p = psz_path; *p; ++p )
        if( pvlc_is_separator( *p ) ) base = p + 1;
    return base;
}

bool pvlc_series_info( const char *psz_path, char **ppsz_show,
                       unsigned *pi_season, unsigned *pi_episode )
{
    if( ppsz_show ) *ppsz_show = NULL;
    if( pi_season ) *pi_season = 0;
    if( pi_episode ) *pi_episode = 0;
    const char *base = pvlc_filename( psz_path );
    const char *marker = NULL;
    unsigned season = 0, episode = 0;
    for( const char *p = base; *p; ++p )
    {
        if( (p[0] == 's' || p[0] == 'S') && isdigit( (unsigned char)p[1] ) )
        {
            char *end;
            unsigned s = (unsigned)strtoul( p + 1, &end, 10 );
            if( (*end == 'e' || *end == 'E')
             && isdigit( (unsigned char)end[1] ) )
            {
                season = s;
                episode = (unsigned)strtoul( end + 1, NULL, 10 );
                marker = p;
                break;
            }
        }
        if( isdigit( (unsigned char)p[0] ) )
        {
            char *end;
            unsigned s = (unsigned)strtoul( p, &end, 10 );
            if( (*end == 'x' || *end == 'X')
             && isdigit( (unsigned char)end[1] ) )
            {
                season = s;
                episode = (unsigned)strtoul( end + 1, NULL, 10 );
                marker = p;
                break;
            }
        }
    }
    if( marker == NULL )
    {
        /* Jellyfin's alternative layout puts episodes below Season XX. */
        const char *season_dir = strcasestr( psz_path, "season " );
        if( season_dir != NULL && isdigit( (unsigned char)season_dir[7] ) )
        {
            season = (unsigned)strtoul( season_dir + 7, NULL, 10 );
            const char *show_end = season_dir;
            while( show_end > psz_path && pvlc_is_separator( show_end[-1] ) )
                --show_end;
            const char *show_begin = show_end;
            while( show_begin > psz_path && !pvlc_is_separator( show_begin[-1] ) )
                --show_begin;
            if( ppsz_show )
                *ppsz_show = pvlc_component_dup( show_begin, show_end,
                                                  "Unknown Show" );
            if( pi_season ) *pi_season = season;
            return true;
        }
        return false;
    }
    const char *end = marker;
    while( end > base && (end[-1] == ' ' || end[-1] == '-' || end[-1] == '_'
                           || end[-1] == '.') )
        --end;
    char *show = pvlc_component_dup( base, end, "Unknown Show" );
    if( show != NULL )
    {
        char *dot;
        for( dot = show; *dot; ++dot )
            if( *dot == '.' || *dot == '_' ) *dot = ' ';
    }
    if( ppsz_show ) *ppsz_show = show; else free( show );
    if( pi_season ) *pi_season = season;
    if( pi_episode ) *pi_episode = episode;
    return true;
}

bool pvlc_files_equal( const char *a, const char *b,
                       uint64_t expected_size )
{
    struct stat sa, sb;
    if( vlc_stat( a, &sa ) != 0 || vlc_stat( b, &sb ) != 0
     || !S_ISREG( sa.st_mode ) || !S_ISREG( sb.st_mode )
     || (uint64_t)sa.st_size != expected_size || sa.st_size != sb.st_size )
        return false;
    FILE *fa = vlc_fopen( a, "rb" ), *fb = vlc_fopen( b, "rb" );
    if( fa == NULL || fb == NULL )
    { if( fa ) fclose( fa ); if( fb ) fclose( fb ); return false; }
    unsigned char ba[64 * 1024], bb[64 * 1024];
    bool same = true;
    size_t na, nb;
    do
    {
        na = fread( ba, 1, sizeof( ba ), fa );
        nb = fread( bb, 1, sizeof( bb ), fb );
        if( na != nb || memcmp( ba, bb, na ) ) { same = false; break; }
    } while( na != 0 );
    if( ferror( fa ) || ferror( fb ) ) same = false;
    fclose( fa ); fclose( fb );
    return same;
}

static char *pvlc_unique_destination( const char *psz_dir,
                                      const char *psz_filename,
                                      const char *psz_source,
                                      uint64_t i_source_size,
                                      size_t i_max_component,
                                      size_t i_max_path )
{
    size_t dir_length = strlen( psz_dir );
    if( dir_length + 2 >= i_max_path ) return NULL;
    size_t available = i_max_path - dir_length - 1;
    if( available > i_max_component ) available = i_max_component;
    char *limited = pvlc_sanitize_filename( psz_filename, available );
    char *dst = limited ? pvlc_path_join( psz_dir, limited ) : NULL;
    if( dst == NULL )
    { free( limited ); return NULL; }
    struct stat st;
    if( vlc_stat( dst, &st ) != 0 )
    { free( limited ); return dst; }
    if( pvlc_files_equal( psz_source, dst, i_source_size ) )
    { free( limited ); return dst; }

    uint64_t hash = pvlc_hash_bytes( UINT64_C(1469598103934665603),
                                     psz_source, strlen( psz_source ) );
    const char *dot = strrchr( limited, '.' );
    size_t stem_len = dot ? (size_t)(dot - limited) : strlen( limited );
    size_t extension_len = dot ? strlen( dot ) : 0;
    for( unsigned i = 0; i < 10000; ++i )
    {
        char suffix[32];
        int suffix_len = i == 0
            ? snprintf( suffix, sizeof( suffix ), "-%08" PRIx32,
                        (uint32_t)hash )
            : snprintf( suffix, sizeof( suffix ), "-%08" PRIx32 "-%u",
                        (uint32_t)hash, i + 1 );
        if( suffix_len < 0 || (size_t)suffix_len + extension_len >= available )
            break;
        size_t stem_limit = available - extension_len - (size_t)suffix_len;
        size_t shortened = pvlc_utf8_prefix( limited,
                                             stem_len < stem_limit
                                                ? stem_len : stem_limit );
        char *candidate = malloc( shortened + (size_t)suffix_len
                                  + extension_len + 1 );
        if( candidate == NULL ) { free( dst ); free( limited ); return NULL; }
        memcpy( candidate, limited, shortened );
        memcpy( candidate + shortened, suffix, (size_t)suffix_len );
        if( extension_len )
            memcpy( candidate + shortened + (size_t)suffix_len, dot,
                    extension_len );
        candidate[shortened + (size_t)suffix_len + extension_len] = '\0';
        free( dst );
        dst = pvlc_path_join( psz_dir, candidate );
        free( candidate );
        if( dst == NULL ) break;
        if( vlc_stat( dst, &st ) != 0
         || pvlc_files_equal( psz_source, dst, i_source_size ) )
        { free( limited ); return dst; }
    }
    free( dst ); free( limited );
    return NULL;
}

int pvlc_import_managed( vlc_object_t *p_obj, const char *psz_source,
                         const char *psz_title, const char *psz_artist,
                         const char *psz_album, char **ppsz_destination )
{
    if( ppsz_destination )
        *ppsz_destination = NULL;
    struct stat st;
    pvlc_media_type_t type;
    if( psz_source == NULL || vlc_stat( psz_source, &st ) != 0
     || !S_ISREG( st.st_mode )
     || pvlc_media_type( psz_source, &type ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    if( type != PVLC_MEDIA_AUDIO )
    {
        msg_Warn( p_obj, "managed-library import rejected for non-audio file %s",
                  psz_source );
        return VLC_EGENERIC;
    }

    char *managed = pvlc_managed_folder( p_obj );
    int64_t configured = var_InheritInteger( p_obj,
                                             "powervlc-ml-max-component" );
    int64_t configured_path = var_InheritInteger( p_obj,
                                                  "powervlc-ml-max-path" );
    size_t max_component = configured >= 48 && configured <= 240
                         ? (size_t)configured : 180;
    size_t max_path = configured_path >= 96 && configured_path <= 1024
                    ? (size_t)configured_path : 240;
    if( managed )
    {
        size_t root_length = strlen( managed );
        size_t fair = max_path > root_length + 32
                    ? (max_path - root_length - 32) / 3 : 16;
        if( fair < max_component ) max_component = fair < 16 ? 16 : fair;
    }
    char *artist = pvlc_sanitize_component( psz_artist, "Unknown Artist",
                                            max_component );
    char *album = pvlc_sanitize_component( psz_album, "Unknown Album",
                                           max_component );
    const char *base = pvlc_filename( psz_source );
    char *filename = pvlc_sanitize_filename( base, max_component );
    char *type_dir = managed ? pvlc_path_join( managed, "Music" ) : NULL;
    char *artist_dir = NULL;
    char *dest_dir = NULL;
    if( type_dir )
    {
        artist_dir = pvlc_path_join( type_dir, artist );
        dest_dir = artist_dir ? pvlc_path_join( artist_dir, album ) : NULL;
    }

    int i_ret = VLC_ENOMEM;
    if( managed && artist && album && filename && type_dir && dest_dir )
    {
        if( strlen( dest_dir ) + 2 >= max_path )
            i_ret = VLC_EGENERIC;
        else
            i_ret = pvlc_mkdir_parents( dest_dir );
        if( i_ret == VLC_SUCCESS )
        {
            char *dst = pvlc_unique_destination( dest_dir, filename,
                                                 psz_source,
                                                 (uint64_t)st.st_size,
                                                 max_component, max_path );
            if( dst == NULL )
                i_ret = VLC_EGENERIC;
            else
            {
                if( pvlc_files_equal( psz_source, dst,
                                      (uint64_t)st.st_size ) )
                    i_ret = VLC_SUCCESS;
                else
                    i_ret = pvlc_copy_file( psz_source, dst );
                if( i_ret == VLC_SUCCESS && ppsz_destination )
                    *ppsz_destination = strdup( dst );
                free( dst );
            }
        }
    }
    if( i_ret != VLC_SUCCESS )
        msg_Err( p_obj, "cannot import %s into managed media folder",
                 psz_source );
    VLC_UNUSED( psz_title ); /* title is retained by the scan cache/UI */
    free( managed ); free( artist ); free( album ); free( filename );
    free( type_dir ); free( artist_dir ); free( dest_dir );
    return i_ret;
}

/* Import a non-file input (primarily one Audio-CD track). The item's trusted
 * options are copied so cdda-first-sector/cdda-last-sector survive the handoff
 * to the background library thread. FLAC keeps the extraction lossless while
 * remaining inexpensive to decode on the oldest supported machines. */
int pvlc_import_managed_input( vlc_object_t *p_obj, input_item_t *p_source,
                               const char *psz_title, const char *psz_artist,
                               const char *psz_album, char **ppsz_destination )
{
    if( ppsz_destination ) *ppsz_destination = NULL;
    if( p_source == NULL ) return VLC_EGENERIC;
    char *item_title = psz_title ? strdup( psz_title )
                                 : input_item_GetTitleFbName( p_source );
    char *item_artist = psz_artist ? strdup( psz_artist )
                                   : input_item_GetMeta( p_source,
                                                        vlc_meta_Artist );
    char *item_album = psz_album ? strdup( psz_album )
                                 : input_item_GetMeta( p_source,
                                                      vlc_meta_Album );
    if( item_title == NULL ) item_title = strdup( "Audio CD Track" );
    if( item_artist == NULL ) item_artist = strdup( "Unknown Artist" );
    if( item_album == NULL ) item_album = strdup( "Audio CD" );
    char *managed = pvlc_managed_folder( p_obj );
    int64_t mc = var_InheritInteger( p_obj, "powervlc-ml-max-component" );
    int64_t mp = var_InheritInteger( p_obj, "powervlc-ml-max-path" );
    size_t max_component = mc >= 48 && mc <= 240 ? (size_t)mc : 180;
    size_t max_path = mp >= 96 && mp <= 1024 ? (size_t)mp : 240;
    if( managed )
    {
        size_t fair = max_path > strlen( managed ) + 32
                    ? (max_path - strlen( managed ) - 32) / 3 : 16;
        if( fair < max_component ) max_component = fair < 16 ? 16 : fair;
    }
    char *artist = pvlc_sanitize_component( item_artist, "Unknown Artist",
                                            max_component );
    char *album = pvlc_sanitize_component( item_album, "Audio CD",
                                           max_component );
    char *title = pvlc_sanitize_component( item_title, "Audio CD Track",
                                           max_component > 5
                                             ? max_component - 5 : 16 );
    char *filename = NULL;
    if( title && asprintf( &filename, "%s.flac", title ) < 0 ) filename = NULL;
    char *music = managed ? pvlc_path_join( managed, "Music" ) : NULL;
    char *artist_dir = music && artist ? pvlc_path_join( music, artist ) : NULL;
    char *dest_dir = artist_dir && album ? pvlc_path_join( artist_dir, album )
                                         : NULL;
    int ret = VLC_ENOMEM;
    char *destination = NULL;
    char *uri = input_item_GetURI( p_source );
    if( filename && dest_dir && uri && strlen( dest_dir ) + 2 < max_path
     && pvlc_mkdir_parents( dest_dir ) == VLC_SUCCESS )
    {
        char *plain = pvlc_path_join( dest_dir, filename );
        struct stat st;
        if( plain && vlc_stat( plain, &st ) == 0 && st.st_size > 0 )
        {
            destination = plain;
            ret = VLC_SUCCESS;
        }
        else
        {
            free( plain );
            destination = pvlc_unique_destination( dest_dir, filename, uri, 0,
                                                   max_component, max_path );
        }
        if( ret != VLC_SUCCESS && destination )
        {
            char *escaped = config_StringEscape( destination );
            char *sout = NULL;
            if( escaped && asprintf( &sout,
                "sout=#transcode{acodec=flac,channels=2,samplerate=44100}:"
                "std{access=file,mux=raw,dst='%s'}", escaped ) >= 0 )
            {
                input_item_t *item = input_item_New( uri, item_title );
                if( item )
                {
                    input_item_CopyOptions( item, p_source );
                    input_item_AddOption( item, sout, VLC_INPUT_OPTION_TRUSTED );
                    static const char *const options[] = { "no-video", "no-spu",
                        "no-osd", "no-sout-video", "sout-audio" };
                    for( size_t i = 0; i < ARRAY_SIZE( options ); ++i )
                        input_item_AddOption( item, options[i],
                                              VLC_INPUT_OPTION_TRUSTED );
                    ret = input_Read( p_obj, item );
                    input_item_Release( item );
                    if( ret == VLC_SUCCESS
                     && (vlc_stat( destination, &st ) != 0 || st.st_size == 0) )
                        ret = VLC_EGENERIC;
                }
            }
            free( escaped ); free( sout );
            if( ret != VLC_SUCCESS ) vlc_unlink( destination );
        }
    }
    if( ret == VLC_SUCCESS && ppsz_destination )
        *ppsz_destination = strdup( destination );
    if( ret != VLC_SUCCESS )
        msg_Err( p_obj, "cannot import input %s into managed media folder",
                 uri ? uri : "(null)" );
    free( item_title ); free( item_artist ); free( item_album ); free( managed );
    free( artist ); free( album ); free( title ); free( filename ); free( music );
    free( artist_dir ); free( dest_dir ); free( destination ); free( uri );
    return ret;
}
