/*****************************************************************************
 * powervlc_media_common.h: lightweight media-library filesystem helpers
 *****************************************************************************/

#ifndef VLC_POWERVLC_MEDIA_COMMON_H
#define VLC_POWERVLC_MEDIA_COMMON_H 1

#include <vlc_common.h>
#include <vlc_meta.h>
#include <stdio.h>

#define PVLC_ML_SCAN_ACTIVE    "powervlc-ml-scan-active"
#define PVLC_ML_SCAN_DONE      "powervlc-ml-scan-done"
#define PVLC_ML_SCAN_TOTAL     "powervlc-ml-scan-total"
#define PVLC_ML_SCAN_REVISION  "powervlc-ml-scan-revision"

typedef enum
{
    PVLC_MEDIA_AUDIO = 1,
    PVLC_MEDIA_VIDEO = 2,
} pvlc_media_type_t;

typedef struct
{
    char *psz_path;
    char *psz_relative;
    char *psz_title;
    char *psz_artist;
    char *psz_album;
    /* Runtime-only folded Title/Artist/Album/Album Artist search corpus.
     * It is rebuilt from cached metadata and is never serialized. */
    char *psz_search_folded;
    /* Title, artist and album keep their historical named fields above.
     * Every other VLC metadata field is retained here so a library view never
     * has to open the media again after the initial scan. */
    char *ppsz_meta[VLC_META_TYPE_COUNT];
    char **ppsz_extra_names;
    char **ppsz_extra_values;
    size_t i_extra_count;
    vlc_tick_t i_duration;
    uint64_t i_size;
    int64_t i_mtime;
    pvlc_media_type_t i_type;
    uint8_t i_rating;
} pvlc_media_entry_t;

typedef struct
{
    pvlc_media_entry_t *p_entries;
    size_t i_count;
    size_t i_capacity;
    uint64_t i_fingerprint;
} pvlc_media_catalog_t;

void pvlc_catalog_init( pvlc_media_catalog_t * );
void pvlc_media_entry_clear( pvlc_media_entry_t * );
void pvlc_catalog_clear( pvlc_media_catalog_t * );
/* Moves one entry into the catalog and clears the source on success. */
int pvlc_catalog_append( pvlc_media_catalog_t *, pvlc_media_entry_t * );
/* Moves all entries from the source into the destination without duplicating
 * their metadata strings. The source is empty on success. */
int pvlc_catalog_merge( pvlc_media_catalog_t *, pvlc_media_catalog_t * );
void pvlc_catalog_finalize( pvlc_media_catalog_t * );

int pvlc_media_type( const char *, pvlc_media_type_t * );
const char *pvlc_media_meta( const pvlc_media_entry_t *, vlc_meta_type_t );
const char *pvlc_media_extra( const pvlc_media_entry_t *, const char * );
int pvlc_scan_file( vlc_object_t *, const char *, const char *,
                    pvlc_media_entry_t * );
typedef void (*pvlc_scan_progress_cb)( void *, uint64_t, uint64_t );
int pvlc_count_media_files( vlc_object_t *, const char *, uint64_t * );
int pvlc_scan_folder_progress( vlc_object_t *, const char *,
                              pvlc_media_catalog_t *, uint64_t,
                              pvlc_scan_progress_cb, void * );
int pvlc_scan_folder_resume_progress( vlc_object_t *, const char *,
                              pvlc_media_catalog_t *,
                              const pvlc_media_catalog_t *, uint64_t,
                              pvlc_scan_progress_cb, void * );
/* Optional tab-separated diagnostic stream. Each line contains a stable
 * reason key followed by the path that was deliberately or accidentally not
 * indexed. The caller owns and serializes the FILE. */
int pvlc_scan_folder_resume_report_progress( vlc_object_t *, const char *,
                              pvlc_media_catalog_t *,
                              const pvlc_media_catalog_t *, uint64_t,
                              pvlc_scan_progress_cb, void *, FILE * );
int pvlc_scan_folder( vlc_object_t *, const char *, pvlc_media_catalog_t * );
bool pvlc_folder_cache_available( const char * );
bool pvlc_folder_cache_available_at( const char * );
int pvlc_load_folder_cache( vlc_object_t *, const char *,
                            pvlc_media_catalog_t * );
int pvlc_load_folder_cache_at( vlc_object_t *, const char *, const char *,
                               pvlc_media_catalog_t * );
int pvlc_save_folder_cache( vlc_object_t *, const char *,
                            const pvlc_media_catalog_t * );
int pvlc_save_folder_cache_at( vlc_object_t *, const char *, const char *,
                               const pvlc_media_catalog_t * );
int pvlc_append_resume_cache_at( vlc_object_t *, const char *, const char *,
                                const pvlc_media_catalog_t *, size_t );
/* Refreshes a folder cache from a persistent directory snapshot. Unchanged
 * directories are never opened and unchanged media reuse their cached
 * metadata, so monitor passes remain cheap even on old machines. */
int pvlc_refresh_folder_cache_at( vlc_object_t *, const char *, const char *,
                                  pvlc_media_catalog_t *, bool * );

/* Ratings deliberately live outside the source-file tag cache: changing a
 * star is instant, does not rewrite music, and survives index rebuilds. */
int pvlc_ratings_apply( vlc_object_t *, pvlc_media_catalog_t * );
int pvlc_rating_set( vlc_object_t *, const char *, unsigned );
int pvlc_ratings_set( vlc_object_t *, const char *const *, size_t, unsigned );

char *pvlc_managed_folder( vlc_object_t * );
int pvlc_import_managed( vlc_object_t *, const char *, const char *,
                         const char *, const char *, char ** );
int pvlc_import_managed_input( vlc_object_t *, input_item_t *, const char *,
                               const char *, const char *, char ** );

int pvlc_mkdir_parents( const char * );
int pvlc_copy_file( const char *, const char * );
bool pvlc_files_equal( const char *, const char *, uint64_t );
char *pvlc_path_join( const char *, const char * );
char *pvlc_escape( const char * );
char *pvlc_unescape( const char * );
char *pvlc_sanitize_component( const char *, const char *, size_t );
char *pvlc_sanitize_filename( const char *, size_t );
bool pvlc_series_info( const char *, char **, unsigned *, unsigned * );

/* Compact, little-endian primitives shared by all PowerVLC cache formats.
 * They make the on-disk snapshots portable between PowerPC and Intel/ARM. */
int pvlc_binary_write( FILE *, const void *, size_t );
int pvlc_binary_read( FILE *, void *, size_t );
int pvlc_binary_write_u32( FILE *, uint32_t );
int pvlc_binary_write_u64( FILE *, uint64_t );
int pvlc_binary_read_u32( FILE *, uint32_t * );
int pvlc_binary_read_u64( FILE *, uint64_t * );
int pvlc_binary_write_string( FILE *, const char * );
int pvlc_binary_read_string( FILE *, char **, uint32_t );

#endif
