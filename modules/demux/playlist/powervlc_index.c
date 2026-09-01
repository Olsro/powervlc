/*****************************************************************************
 * powervlc_index.c: compact, random-access PowerVLC library index reader
 *****************************************************************************
 * One local file stores media metadata once and lightweight view nodes by
 * offset. Expanding a row reads only that node and its direct children.
 * This deliberately avoids parsing a multi-megabyte XSPF bucket and creating
 * every descendant on memory-constrained PowerPC Macs.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_access.h>
#include <vlc_fs.h>
#include <vlc_input_item.h>
#include <vlc_stream.h>
#include <vlc_url.h>

#include "playlist.h"

#include <inttypes.h>

#define PVLC_INDEX_NODE  UINT32_C(0x4e4f4445)
#define PVLC_INDEX_MEDIA UINT32_C(0x4d454449)
#define PVLC_INDEX_CHILD_NODE  1
#define PVLC_INDEX_CHILD_MEDIA 2
#define PVLC_INDEX_FLAG_RANDOM       UINT32_C(0x01)
#define PVLC_INDEX_FLAG_ALBUM_SCOPE  UINT32_C(0x02)
#define PVLC_INDEX_FLAG_RANDOM_TRACK UINT32_C(0x04)
#define PVLC_INDEX_FLAG_ALBUM_NODE   UINT32_C(0x08)
#define PVLC_INDEX_FLAG_DEVICE_STRUCTURE UINT32_C(0x10)
#define PVLC_INDEX_NO_VALUE UINT32_MAX

static const unsigned char pvlc_index_magic[8] = {
    'P', 'V', 'L', 'C', 'L', 'I', 5, 0
};

/* Revision 6 was briefly emitted by the media-library indexer even though
 * its binary layout remained revision 5. Accept it while existing caches are
 * migrated back to the shared stable format used by portable players. */
static const unsigned char pvlc_index_magic_transitional[8] = {
    'P', 'V', 'L', 'C', 'L', 'I', 6, 0
};

typedef struct
{
    char **uris;
    size_t count;
} pvlc_deleted_set_t;

static char *pvlc_base_url( stream_t * );

static int pvlc_string_pointer_compare( const void *left, const void *right )
{
    const char *const *a = left, *const *b = right;
    return strcmp( *a, *b );
}

static uint32_t pvlc_file_read_u32( FILE *file, bool *valid )
{
    unsigned char data[4];
    if( fread( data, 1, sizeof( data ), file ) != sizeof( data ) )
    { *valid = false; return 0; }
    return (uint32_t)data[0] | (uint32_t)data[1] << 8
         | (uint32_t)data[2] << 16 | (uint32_t)data[3] << 24;
}

static char *pvlc_file_read_string( FILE *file, bool *valid )
{
    uint32_t length = pvlc_file_read_u32( file, valid );
    if( !*valid || length > 16 * 1024 * 1024 )
    { *valid = false; return NULL; }
    char *text = malloc( (size_t)length + 1 );
    if( text == NULL ) { *valid = false; return NULL; }
    if( length && fread( text, 1, length, file ) != length )
    { free( text ); *valid = false; return NULL; }
    text[length] = '\0';
    return text;
}

static void pvlc_deleted_clear( pvlc_deleted_set_t *set )
{
    for( size_t i = 0; i < set->count; ++i ) free( set->uris[i] );
    free( set->uris );
    memset( set, 0, sizeof( *set ) );
}

static pvlc_deleted_set_t pvlc_deleted_load( stream_t *stream )
{
    pvlc_deleted_set_t set = { 0 };
    char *base = pvlc_base_url( stream );
    char *path = base ? vlc_uri2path( base ) : NULL;
    free( base );
    char *overlay = NULL;
    if( path && asprintf( &overlay, "%s.deleted", path ) < 0 ) overlay = NULL;
    free( path );
    FILE *file = overlay ? vlc_fopen( overlay, "rb" ) : NULL;
    free( overlay );
    if( file == NULL ) return set;
    static const unsigned char magic[8] = {
        'P', 'V', 'L', 'C', 'D', 'E', 'L', 1
    };
    unsigned char actual[sizeof( magic )];
    bool valid = fread( actual, 1, sizeof( actual ), file ) == sizeof( actual )
              && !memcmp( actual, magic, sizeof( magic ) );
    uint32_t count = valid ? pvlc_file_read_u32( file, &valid ) : 0;
    if( count > 1000000 ) valid = false;
    if( valid && count )
    {
        set.uris = vlc_alloc( count, sizeof( *set.uris ) );
        if( set.uris == NULL ) valid = false;
    }
    for( uint32_t i = 0; valid && i < count; ++i )
    {
        set.uris[i] = pvlc_file_read_string( file, &valid );
        if( valid ) set.count++;
    }
    fclose( file );
    if( !valid ) pvlc_deleted_clear( &set );
    else if( set.count > 1 ) qsort( set.uris, set.count, sizeof( *set.uris ),
                                    pvlc_string_pointer_compare );
    return set;
}

static bool pvlc_deleted_contains( const pvlc_deleted_set_t *set,
                                   const char *uri )
{
    return uri && set->count && bsearch( &uri, set->uris, set->count,
                       sizeof( *set->uris ), pvlc_string_pointer_compare );
}

static int pvlc_read( stream_t *stream, void *data, size_t size )
{
    return size == 0 || vlc_stream_Read( stream, data, size ) == (ssize_t)size
         ? VLC_SUCCESS : VLC_EGENERIC;
}

static int pvlc_read_u32( stream_t *stream, uint32_t *value )
{
    unsigned char data[4];
    if( pvlc_read( stream, data, sizeof( data ) ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    *value = (uint32_t)data[0] | (uint32_t)data[1] << 8
           | (uint32_t)data[2] << 16 | (uint32_t)data[3] << 24;
    return VLC_SUCCESS;
}

static int pvlc_read_u64( stream_t *stream, uint64_t *value )
{
    unsigned char data[8];
    if( pvlc_read( stream, data, sizeof( data ) ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    *value = 0;
    for( unsigned i = 0; i < 8; ++i )
        *value |= (uint64_t)data[i] << (i * 8);
    return VLC_SUCCESS;
}

static int pvlc_read_string( stream_t *stream, char **value )
{
    uint32_t length;
    *value = NULL;
    if( pvlc_read_u32( stream, &length ) != VLC_SUCCESS
     || length > 16 * 1024 * 1024 ) return VLC_EGENERIC;
    char *text = malloc( (size_t)length + 1 );
    if( text == NULL ) return VLC_ENOMEM;
    if( pvlc_read( stream, text, length ) != VLC_SUCCESS )
    { free( text ); return VLC_EGENERIC; }
    text[length] = '\0';
    *value = text;
    return VLC_SUCCESS;
}

static void pvlc_apply_flags( input_item_t *item, uint32_t flags,
                              uint32_t value )
{
    if( flags & PVLC_INDEX_FLAG_RANDOM )
        input_item_AddOption( item, VLC_INPUT_OPTION_POWERVLC_RANDOM_ACTION, 0 );
    if( flags & PVLC_INDEX_FLAG_ALBUM_SCOPE )
        input_item_AddOption( item, VLC_INPUT_OPTION_POWERVLC_ALBUM_SCOPE, 0 );
    if( flags & PVLC_INDEX_FLAG_RANDOM_TRACK )
        input_item_AddOption( item,
            VLC_INPUT_OPTION_POWERVLC_RANDOM_ALBUM_TRACK, 0 );
    if( flags & PVLC_INDEX_FLAG_ALBUM_NODE )
        input_item_AddOption( item, VLC_INPUT_OPTION_POWERVLC_ALBUM_SCOPE, 0 );
    if( flags & PVLC_INDEX_FLAG_DEVICE_STRUCTURE )
        input_item_AddOption( item,
            VLC_INPUT_OPTION_POWERVLC_DEVICE_STRUCTURE,
            VLC_INPUT_OPTION_UNIQUE );
    if( value != PVLC_INDEX_NO_VALUE )
    {
        char option[64];
        snprintf( option, sizeof( option ), "%s%u",
                  VLC_INPUT_OPTION_POWERVLC_LIBRARY_BUCKET_PREFIX, value );
        input_item_AddOption( item, option, 0 );
    }
}

static char *pvlc_base_url( stream_t *stream )
{
    char *base = strdup( stream->psz_url );
    char *fragment = base ? strchr( base, '#' ) : NULL;
    if( fragment ) *fragment = '\0';
    return base;
}

static uint64_t pvlc_item_offset( stream_t *stream )
{
    input_item_t *item = GetCurrentItem( stream );
    if( item == NULL ) return 0;
    const char prefix[] = VLC_INPUT_OPTION_POWERVLC_INDEX_OFFSET_PREFIX;
    uint64_t offset = 0;
    vlc_mutex_lock( &item->lock );
    /* A portable-player index is append-only during an editing session.
     * Rebinding a stable UI row therefore adds a newer offset option instead
     * of replacing the input item (which would lose expansion state).  The
     * last matching option is authoritative. */
    for( int i = 0; i < item->i_options; ++i )
        if( !strncmp( item->ppsz_options[i], prefix, sizeof( prefix ) - 1 ) )
        {
            char *end = NULL;
            uint64_t value = strtoull(
                item->ppsz_options[i] + sizeof( prefix ) - 1, &end, 10 );
            if( value && end && *end == '\0' ) offset = value;
        }
    vlc_mutex_unlock( &item->lock );
    return offset;
}

static input_item_t *pvlc_read_media( stream_t *stream, uint64_t offset,
                                      const pvlc_deleted_set_t *deleted )
{
    if( vlc_stream_Seek( stream, offset ) != VLC_SUCCESS ) return NULL;
    uint32_t marker, rating;
    uint64_t duration, stable_id;
    char *uri = NULL, *title = NULL, *artist = NULL, *album = NULL;
    char *track = NULL, *album_artist = NULL;
    int ret = pvlc_read_u32( stream, &marker );
    if( ret == VLC_SUCCESS && marker != PVLC_INDEX_MEDIA ) ret = VLC_EGENERIC;
    if( ret == VLC_SUCCESS ) ret = pvlc_read_string( stream, &uri );
    if( ret == VLC_SUCCESS ) ret = pvlc_read_string( stream, &title );
    if( ret == VLC_SUCCESS ) ret = pvlc_read_string( stream, &artist );
    if( ret == VLC_SUCCESS ) ret = pvlc_read_string( stream, &album );
    if( ret == VLC_SUCCESS ) ret = pvlc_read_string( stream, &track );
    if( ret == VLC_SUCCESS ) ret = pvlc_read_string( stream, &album_artist );
    if( ret == VLC_SUCCESS ) ret = pvlc_read_u32( stream, &rating );
    if( ret == VLC_SUCCESS ) ret = pvlc_read_u64( stream, &duration );
    if( ret == VLC_SUCCESS ) ret = pvlc_read_u64( stream, &stable_id );
    input_item_t *item = ret == VLC_SUCCESS
                          && !pvlc_deleted_contains( deleted, uri )
        ? input_item_NewFile( uri, title, -1, ITEM_LOCAL ) : NULL;
    if( item )
    {
        if( artist && *artist ) input_item_SetMeta( item, vlc_meta_Artist, artist );
        if( album && *album ) input_item_SetMeta( item, vlc_meta_Album, album );
        if( track && *track ) input_item_SetMeta( item, vlc_meta_TrackNumber, track );
        if( album_artist && *album_artist )
            input_item_SetMeta( item, vlc_meta_AlbumArtist, album_artist );
        if( rating > 0 && rating <= 5 )
        {
            char text[2] = { (char)('0' + rating), '\0' };
            input_item_SetMeta( item, vlc_meta_Rating, text );
        }
        input_item_SetDuration( item, (vlc_tick_t)duration );
        if( stable_id != 0 )
        {
            char option[64];
            snprintf( option, sizeof( option ), "powervlc-ipod-track-id=%" PRIu64,
                      stable_id );
            input_item_AddOption( item, option, VLC_INPUT_OPTION_UNIQUE );
        }
        input_item_SetPreparsed( item, true );
    }
    free( uri ); free( title ); free( artist ); free( album );
    free( track ); free( album_artist );
    return item;
}

/* Determine whether a virtual child still contains at least one visible
 * medium after staged iPod deletions. This walks only the local compact index
 * and stops at the first live URI, so collapsed views remain cheap. */
static int pvlc_node_has_visible_media( stream_t *source, uint64_t offset,
                                       const pvlc_deleted_set_t *deleted,
                                       bool *visible, unsigned depth )
{
    *visible = false;
    if( depth > 64 || vlc_stream_Seek( source, offset ) != VLC_SUCCESS )
        return VLC_EGENERIC;
    uint32_t marker, child_count;
    if( pvlc_read_u32( source, &marker ) != VLC_SUCCESS
     || marker != PVLC_INDEX_NODE
     || pvlc_read_u32( source, &child_count ) != VLC_SUCCESS
     || child_count > 1000000 ) return VLC_EGENERIC;
    int ret = VLC_SUCCESS;
    for( uint32_t i = 0; i < child_count && ret == VLC_SUCCESS; ++i )
    {
        uint32_t type, flags, value, reserved;
        uint64_t child_offset;
        char *name = NULL;
        ret = pvlc_read_u32( source, &type );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_u32( source, &flags );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_u32( source, &value );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_u32( source, &reserved );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_u64( source, &child_offset );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_string( source, &name );
        uint64_t next = vlc_stream_Tell( source );
        if( ret == VLC_SUCCESS && type == PVLC_INDEX_CHILD_NODE )
            ret = pvlc_node_has_visible_media( source, child_offset, deleted,
                                                visible, depth + 1 );
        else if( ret == VLC_SUCCESS && type == PVLC_INDEX_CHILD_MEDIA )
        {
            if( vlc_stream_Seek( source, child_offset ) != VLC_SUCCESS )
                ret = VLC_EGENERIC;
            uint32_t media_marker;
            char *uri = NULL;
            if( ret == VLC_SUCCESS ) ret = pvlc_read_u32( source,
                                                          &media_marker );
            if( ret == VLC_SUCCESS && media_marker != PVLC_INDEX_MEDIA )
                ret = VLC_EGENERIC;
            if( ret == VLC_SUCCESS ) ret = pvlc_read_string( source, &uri );
            if( ret == VLC_SUCCESS )
                *visible = !pvlc_deleted_contains( deleted, uri );
            free( uri );
        }
        else if( ret == VLC_SUCCESS ) ret = VLC_EGENERIC;
        free( name ); VLC_UNUSED( flags ); VLC_UNUSED( value );
        VLC_UNUSED( reserved );
        if( ret == VLC_SUCCESS && *visible ) return VLC_SUCCESS;
        if( ret == VLC_SUCCESS
         && vlc_stream_Seek( source, next ) != VLC_SUCCESS )
            ret = VLC_EGENERIC;
    }
    return ret;
}

static int pvlc_read_directory( stream_t *stream, input_item_node_t *root )
{
    /* URL fragments are deliberately stripped by VLC's input layer before
     * stream filters run.  The publishing item therefore carries the
     * random-access offset as an internal option. */
    uint64_t offset = pvlc_item_offset( stream );
    /* A playlist importer is a stream filter: its own read callbacks are not
     * byte-stream callbacks.  All random-access I/O must go through the
     * wrapped source, exactly as the XSPF importer gives its source to the XML
     * reader. */
    stream_t *source = stream->p_source;
    msg_Dbg( stream, "reading compact index node at offset %" PRIu64,
             offset );
    uint64_t size = 0;
    if( source == NULL || offset == 0
     || vlc_stream_GetSize( source, &size ) != VLC_SUCCESS
     || offset >= size ) return VLC_EGENERIC;
    if( vlc_stream_Seek( source, offset ) != VLC_SUCCESS ) return VLC_EGENERIC;
    uint32_t marker, child_count;
    if( pvlc_read_u32( source, &marker ) != VLC_SUCCESS
     || marker != PVLC_INDEX_NODE
     || pvlc_read_u32( source, &child_count ) != VLC_SUCCESS
     || child_count > 1000000 ) return VLC_EGENERIC;
    char *base = pvlc_base_url( stream );
    if( base == NULL ) return VLC_ENOMEM;
    pvlc_deleted_set_t deleted = pvlc_deleted_load( stream );
    int ret = VLC_SUCCESS;
    for( uint32_t i = 0; i < child_count && ret == VLC_SUCCESS; ++i )
    {
        uint32_t type, flags, value, reserved;
        uint64_t child_offset;
        char *name = NULL;
        ret = pvlc_read_u32( source, &type );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_u32( source, &flags );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_u32( source, &value );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_u32( source, &reserved );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_u64( source, &child_offset );
        if( ret == VLC_SUCCESS ) ret = pvlc_read_string( source, &name );
        uint64_t next = vlc_stream_Tell( source );
        input_item_t *item = NULL;
        if( ret == VLC_SUCCESS && type == PVLC_INDEX_CHILD_NODE )
        {
            bool visible = true;
            if( deleted.count )
            {
                visible = false;
                int check = pvlc_node_has_visible_media( source,
                                 child_offset, &deleted, &visible, 0 );
                /* A damaged overlay/index must not hide valid content. */
                if( check != VLC_SUCCESS ) visible = true;
            }
            char *uri = NULL;
            if( visible
             && asprintf( &uri, "%s#%" PRIu64, base, child_offset ) >= 0 )
                item = input_item_NewExt( uri, name, -1,
                                          ITEM_TYPE_DIRECTORY, ITEM_LOCAL );
            free( uri );
            if( item )
            {
                input_item_AddOption( item,
                    VLC_INPUT_OPTION_POWERVLC_LAZY_INDEX, 0 );
                char option[64];
                snprintf( option, sizeof( option ), "%s%" PRIu64,
                          VLC_INPUT_OPTION_POWERVLC_INDEX_OFFSET_PREFIX,
                          child_offset );
                input_item_AddOption( item, option, 0 );
                pvlc_apply_flags( item, flags, value );
            }
        }
        else if( ret == VLC_SUCCESS && type == PVLC_INDEX_CHILD_MEDIA )
            item = pvlc_read_media( source, child_offset, &deleted );
        else if( ret == VLC_SUCCESS )
            ret = VLC_EGENERIC;
        if( item )
        {
            input_item_node_AppendItem( root, item );
            input_item_Release( item );
        }
        if( ret == VLC_SUCCESS && vlc_stream_Seek( source, next ) != VLC_SUCCESS )
            ret = VLC_EGENERIC;
        free( name );
        VLC_UNUSED( reserved );
    }
    pvlc_deleted_clear( &deleted );
    free( base );
    return ret;
}

int Import_PowerVLCIndex( vlc_object_t *object )
{
    stream_t *stream = (stream_t *)object;
    msg_Dbg( stream, "probing compact index %s",
             stream->psz_url ? stream->psz_url : "" );
    if( vlc_stream_Control( GetSource( stream ),
                            STREAM_IS_DIRECTORY ) == VLC_SUCCESS )
    {
        msg_Dbg( stream, "compact index rejected as a directory" );
        return VLC_EGENERIC;
    }
    const char *name = stream->psz_filepath ? stream->psz_filepath
                                            : stream->psz_url;
    const char *end = name ? strchr( name, '#' ) : NULL;
    size_t length = name ? (end ? (size_t)(end - name) : strlen( name )) : 0;
    if( length < 5 || strncasecmp( name + length - 5, ".pvli", 5 ) )
    {
        msg_Dbg( stream, "compact index extension mismatch: '%s'",
                 name ? name : "" );
        return VLC_EGENERIC;
    }
    unsigned char magic[sizeof( pvlc_index_magic )];
    stream_t *source = stream->p_source;
    int seek_start = source ? vlc_stream_Seek( source, 0 ) : VLC_EGENERIC;
    int read_magic = seek_start == VLC_SUCCESS
                   ? pvlc_read( source, magic, sizeof( magic ) )
                   : VLC_EGENERIC;
    int magic_match = read_magic == VLC_SUCCESS
                    && (memcmp( magic, pvlc_index_magic, sizeof( magic ) ) == 0
                     || memcmp( magic, pvlc_index_magic_transitional,
                                sizeof( magic ) ) == 0) ? 0 : -1;
    int seek_reset = magic_match == 0 ? vlc_stream_Seek( source, 0 )
                                      : VLC_EGENERIC;
    if( seek_start != VLC_SUCCESS || read_magic != VLC_SUCCESS
     || magic_match || seek_reset != VLC_SUCCESS )
    {
        msg_Dbg( stream,
                 "compact index header rejected (seek=%d read=%d magic=%d reset=%d)",
                 seek_start, read_magic, magic_match, seek_reset );
        return VLC_EGENERIC;
    }
    msg_Dbg( stream, "compact index accepted" );
    stream->pf_readdir = pvlc_read_directory;
    stream->pf_control = access_vaDirectoryControlHelper;
    return VLC_SUCCESS;
}
