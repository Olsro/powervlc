/*****************************************************************************
 * bookmarks.c: persistent, shareable per-content bookmarks
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC authors
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <ctype.h>
#include <dirent.h>
#include <errno.h>
#include <inttypes.h>
#include <limits.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

#include <vlc_common.h>
#include <vlc_configuration.h>
#include <vlc_fs.h>
#include <vlc_input.h>
#include <vlc_input_item.h>
#include <vlc_md5.h>

#include "input_internal.h"
#include "config/configuration.h"

#define BOOKMARKS_DIRECTORY "bookmarks"
#define BOOKMARKS_FORMAT "powervlc-bookmarks"
#define BOOKMARKS_COLLECTION_FORMAT "powervlc-bookmarks-collection"
#define BOOKMARKS_VERSION 1
#define BOOKMARKS_MAX_FILE (16u * 1024u * 1024u)

typedef struct
{
    char *psz_id;
    char *psz_uri;
    char *psz_name;
    int i_title;
    vlc_tick_t i_duration;
    size_t i_bookmarks;
    seekpoint_t **pp_bookmarks;
} bookmark_set_t;

typedef struct
{
    bookmark_set_t *p_sets;
    size_t i_sets;
    bool b_is_collection;
} bookmark_collection_t;

static void BookmarkSetClean( bookmark_set_t *p_set )
{
    free( p_set->psz_id );
    free( p_set->psz_uri );
    free( p_set->psz_name );
    for( size_t i = 0; i < p_set->i_bookmarks; i++ )
        vlc_seekpoint_Delete( p_set->pp_bookmarks[i] );
    free( p_set->pp_bookmarks );
    memset( p_set, 0, sizeof(*p_set) );
}

static void BookmarkCollectionClean( bookmark_collection_t *p_collection )
{
    for( size_t i = 0; i < p_collection->i_sets; i++ )
        BookmarkSetClean( &p_collection->p_sets[i] );
    free( p_collection->p_sets );
    memset( p_collection, 0, sizeof(*p_collection) );
}

static bool BookmarkDiscUri( const char *psz_uri )
{
    static const char *const ppsz_schemes[] = {
        "dvd:", "dvdsimple:", "bluray:", "bd:"
    };
    for( size_t i = 0; i < ARRAY_SIZE(ppsz_schemes); i++ )
        if( !strncasecmp(psz_uri, ppsz_schemes[i],
                         strlen(ppsz_schemes[i])) )
            return true;
    return false;
}

static char *BookmarkContentId( const char *psz_uri, const char *psz_name,
                                int i_title )
{
    struct md5_s md5;
    char psz_title[32];

    snprintf( psz_title, sizeof(psz_title), "\n%d", i_title );
    InitMD5( &md5 );
    AddMD5( &md5, psz_uri, strlen(psz_uri) );
    /* Optical drives normally keep the same device MRL after a disc swap.
     * Include the published volume/title name so two discs in /dev/diskN do
     * not inherit one another's bookmarks. Individual titles remain split by
     * the numeric title suffix below. */
    if( BookmarkDiscUri(psz_uri) && psz_name != NULL )
    {
        AddMD5( &md5, "\n", 1 );
        AddMD5( &md5, psz_name, strlen(psz_name) );
    }
    AddMD5( &md5, psz_title, strlen(psz_title) );
    EndMD5( &md5 );
    return psz_md5_hash( &md5 );
}

static bool BookmarkIdValid( const char *psz_id )
{
    if( psz_id == NULL || strlen(psz_id) != 32 )
        return false;
    for( unsigned i = 0; i < 32; i++ )
        if( !isxdigit((unsigned char)psz_id[i]) )
            return false;
    return true;
}

static char *BookmarksDirectory( vlc_object_t *p_obj, bool b_create )
{
    char *psz_data = config_GetUserDir( VLC_DATA_DIR );
    if( psz_data == NULL )
        return NULL;

    char *psz_dir;
    if( asprintf( &psz_dir, "%s" DIR_SEP BOOKMARKS_DIRECTORY, psz_data ) < 0 )
        psz_dir = NULL;
    free( psz_data );

    if( psz_dir != NULL && b_create && config_CreateDir( p_obj, psz_dir ) )
    {
        free( psz_dir );
        psz_dir = NULL;
    }
    return psz_dir;
}

static char *BookmarksPath( vlc_object_t *p_obj, const char *psz_id,
                            bool b_create_directory )
{
    if( !BookmarkIdValid(psz_id) )
        return NULL;

    char *psz_dir = BookmarksDirectory( p_obj, b_create_directory );
    if( psz_dir == NULL )
        return NULL;

    char *psz_path;
    if( asprintf( &psz_path, "%s" DIR_SEP "%s.json", psz_dir, psz_id ) < 0 )
        psz_path = NULL;
    free( psz_dir );
    return psz_path;
}

static int JsonPutString( FILE *p_file, const char *psz_value )
{
    if( fputc('"', p_file) == EOF )
        return VLC_EGENERIC;

    const unsigned char *p = (const unsigned char *)(psz_value ? psz_value : "");
    for( ; *p; p++ )
    {
        switch( *p )
        {
            case '"': if( fputs("\\\"", p_file) == EOF ) return VLC_EGENERIC; break;
            case '\\': if( fputs("\\\\", p_file) == EOF ) return VLC_EGENERIC; break;
            case '\b': if( fputs("\\b", p_file) == EOF ) return VLC_EGENERIC; break;
            case '\f': if( fputs("\\f", p_file) == EOF ) return VLC_EGENERIC; break;
            case '\n': if( fputs("\\n", p_file) == EOF ) return VLC_EGENERIC; break;
            case '\r': if( fputs("\\r", p_file) == EOF ) return VLC_EGENERIC; break;
            case '\t': if( fputs("\\t", p_file) == EOF ) return VLC_EGENERIC; break;
            default:
                if( *p < 0x20 )
                {
                    if( fprintf(p_file, "\\u%04x", *p) < 0 )
                        return VLC_EGENERIC;
                }
                else if( fputc(*p, p_file) == EOF )
                    return VLC_EGENERIC;
        }
    }
    return fputc('"', p_file) == EOF ? VLC_EGENERIC : VLC_SUCCESS;
}

static int BookmarkSetWrite( FILE *p_file, const bookmark_set_t *p_set,
                             unsigned i_indent )
{
    const char *psz_pad = i_indent ? "    " : "";
    const char *psz_pad2 = i_indent ? "        " : "    ";
    const char *psz_pad3 = i_indent ? "            " : "        ";

    if( fprintf(p_file, "%s{\n%s\"format\": \"%s\",\n"
                        "%s\"version\": %d,\n%s\"content\": {\n"
                        "%s\"id\": ",
                psz_pad, psz_pad2, BOOKMARKS_FORMAT, psz_pad2,
                BOOKMARKS_VERSION, psz_pad2, psz_pad3) < 0
     || JsonPutString(p_file, p_set->psz_id) != VLC_SUCCESS
     || fprintf(p_file, ",\n%s\"uri\": ", psz_pad3) < 0
     || JsonPutString(p_file, p_set->psz_uri) != VLC_SUCCESS
     || fprintf(p_file, ",\n%s\"name\": ", psz_pad3) < 0
     || JsonPutString(p_file, p_set->psz_name) != VLC_SUCCESS
     || fprintf(p_file, ",\n%s\"title\": %d,\n"
                        "%s\"duration_us\": %"PRId64"\n%s},\n"
                        "%s\"bookmarks\": [",
                psz_pad3, p_set->i_title, psz_pad3,
                p_set->i_duration, psz_pad2, psz_pad2) < 0 )
        return VLC_EGENERIC;

    for( size_t i = 0; i < p_set->i_bookmarks; i++ )
    {
        const seekpoint_t *p_bookmark = p_set->pp_bookmarks[i];
        if( fprintf(p_file, "%s\n%s{ \"name\": ", i ? "," : "", psz_pad3) < 0
         || JsonPutString(p_file, p_bookmark->psz_name) != VLC_SUCCESS
         || fprintf(p_file, ", \"time_us\": %"PRId64
                            ", \"time_seconds\": %.6f }",
                    p_bookmark->i_time_offset,
                    (double)p_bookmark->i_time_offset / CLOCK_FREQ) < 0 )
            return VLC_EGENERIC;
    }

    return fprintf(p_file, "%s\n%s]\n%s}",
                   p_set->i_bookmarks ? "" : "", psz_pad2, psz_pad) < 0
         ? VLC_EGENERIC : VLC_SUCCESS;
}

static int BookmarkSetWritePath( vlc_object_t *p_obj,
                                 const bookmark_set_t *p_set,
                                 const char *psz_path, bool b_atomic )
{
    char *psz_temporary = NULL;
    const char *psz_output = psz_path;
    if( b_atomic )
    {
        if( asprintf(&psz_temporary, "%s.tmp%"PRIu32, psz_path,
                     (uint32_t)getpid()) < 0 )
            return VLC_ENOMEM;
        psz_output = psz_temporary;
    }

    FILE *p_file = vlc_fopen( psz_output, "wt" );
    if( p_file == NULL )
    {
        msg_Err( p_obj, "cannot write bookmarks file %s: %s",
                 psz_output, vlc_strerror_c(errno) );
        free( psz_temporary );
        return VLC_EGENERIC;
    }

    int i_ret = BookmarkSetWrite( p_file, p_set, 0 );
    if( fputc('\n', p_file) == EOF || fclose(p_file) )
        i_ret = VLC_EGENERIC;

    if( i_ret == VLC_SUCCESS && b_atomic
     && vlc_rename(psz_temporary, psz_path) )
        i_ret = VLC_EGENERIC;
    if( i_ret != VLC_SUCCESS && psz_temporary )
        vlc_unlink( psz_temporary );
    free( psz_temporary );
    return i_ret;
}

static int BookmarkSetCapture( input_thread_t *p_input, bookmark_set_t *p_set )
{
    input_thread_private_t *p_priv = input_priv(p_input);
    input_item_t *p_item = input_GetItem( p_input );
    memset( p_set, 0, sizeof(*p_set) );

    p_set->psz_uri = input_item_GetURI( p_item );
    p_set->psz_name = input_item_GetTitleFbName( p_item );
    p_set->i_title = p_priv->i_bookmark_title;
    p_set->i_duration = var_GetInteger( p_input, "length" );
    if( p_set->psz_uri == NULL )
        goto error;
    if( p_set->psz_name == NULL )
        p_set->psz_name = strdup( "" );
    p_set->psz_id = BookmarkContentId( p_set->psz_uri, p_set->psz_name,
                                       p_set->i_title );
    if( p_set->psz_id == NULL || p_set->psz_name == NULL )
        goto error;

    vlc_mutex_lock( &p_item->lock );
    if( p_priv->i_bookmark > 0 )
    {
        p_set->pp_bookmarks = vlc_alloc( p_priv->i_bookmark,
                                        sizeof(*p_set->pp_bookmarks) );
        if( p_set->pp_bookmarks == NULL )
        {
            vlc_mutex_unlock( &p_item->lock );
            goto error;
        }
        for( int i = 0; i < p_priv->i_bookmark; i++ )
        {
            seekpoint_t *p_copy = vlc_seekpoint_Duplicate(p_priv->pp_bookmark[i]);
            if( p_copy == NULL )
            {
                vlc_mutex_unlock( &p_item->lock );
                goto error;
            }
            p_set->pp_bookmarks[p_set->i_bookmarks++] = p_copy;
        }
    }
    vlc_mutex_unlock( &p_item->lock );
    return VLC_SUCCESS;

error:
    BookmarkSetClean( p_set );
    return VLC_ENOMEM;
}

/* Minimal strict JSON reader for the deliberately small public schema. It
 * accepts unknown properties so users can annotate files by adding fields. */
typedef struct
{
    const char *p;
    const char *p_end;
} json_cursor_t;

static void JsonSkipSpace( json_cursor_t *p_cursor )
{
    while( p_cursor->p < p_cursor->p_end
        && isspace((unsigned char)*p_cursor->p) )
        p_cursor->p++;
}

static bool JsonTake( json_cursor_t *p_cursor, char c )
{
    JsonSkipSpace( p_cursor );
    if( p_cursor->p >= p_cursor->p_end || *p_cursor->p != c )
        return false;
    p_cursor->p++;
    return true;
}

static bool JsonAppendByte( char **ppsz, size_t *pi_length, size_t *pi_alloc,
                            unsigned char c )
{
    if( *pi_length + 1 >= *pi_alloc )
    {
        size_t i_new = *pi_alloc ? *pi_alloc * 2 : 32;
        char *psz_new = realloc( *ppsz, i_new );
        if( psz_new == NULL )
            return false;
        *ppsz = psz_new;
        *pi_alloc = i_new;
    }
    (*ppsz)[(*pi_length)++] = (char)c;
    return true;
}

static bool JsonAppendCodepoint( char **ppsz, size_t *pi_length,
                                 size_t *pi_alloc, unsigned i_codepoint )
{
    if( i_codepoint <= 0x7f )
        return JsonAppendByte(ppsz, pi_length, pi_alloc, i_codepoint);
    if( i_codepoint <= 0x7ff )
        return JsonAppendByte(ppsz, pi_length, pi_alloc, 0xc0 | (i_codepoint >> 6))
            && JsonAppendByte(ppsz, pi_length, pi_alloc, 0x80 | (i_codepoint & 0x3f));
    if( i_codepoint <= 0xffff )
        return JsonAppendByte(ppsz, pi_length, pi_alloc, 0xe0 | (i_codepoint >> 12))
            && JsonAppendByte(ppsz, pi_length, pi_alloc, 0x80 | ((i_codepoint >> 6) & 0x3f))
            && JsonAppendByte(ppsz, pi_length, pi_alloc, 0x80 | (i_codepoint & 0x3f));
    if( i_codepoint <= 0x10ffff )
        return JsonAppendByte(ppsz, pi_length, pi_alloc, 0xf0 | (i_codepoint >> 18))
            && JsonAppendByte(ppsz, pi_length, pi_alloc, 0x80 | ((i_codepoint >> 12) & 0x3f))
            && JsonAppendByte(ppsz, pi_length, pi_alloc, 0x80 | ((i_codepoint >> 6) & 0x3f))
            && JsonAppendByte(ppsz, pi_length, pi_alloc, 0x80 | (i_codepoint & 0x3f));
    return false;
}

static int JsonHex( char c )
{
    if( c >= '0' && c <= '9' ) return c - '0';
    if( c >= 'a' && c <= 'f' ) return c - 'a' + 10;
    if( c >= 'A' && c <= 'F' ) return c - 'A' + 10;
    return -1;
}

static bool JsonReadHex4( json_cursor_t *p_cursor, unsigned *pi_value )
{
    if( p_cursor->p_end - p_cursor->p < 4 )
        return false;
    unsigned i_value = 0;
    for( unsigned i = 0; i < 4; i++ )
    {
        int i_hex = JsonHex( *p_cursor->p++ );
        if( i_hex < 0 )
            return false;
        i_value = (i_value << 4) | (unsigned)i_hex;
    }
    *pi_value = i_value;
    return true;
}

static char *JsonString( json_cursor_t *p_cursor )
{
    JsonSkipSpace( p_cursor );
    if( p_cursor->p >= p_cursor->p_end || *p_cursor->p++ != '"' )
        return NULL;

    char *psz_value = NULL;
    size_t i_length = 0, i_alloc = 0;
    while( p_cursor->p < p_cursor->p_end )
    {
        unsigned char c = (unsigned char)*p_cursor->p++;
        if( c == '"' )
        {
            if( !JsonAppendByte(&psz_value, &i_length, &i_alloc, '\0') )
                break;
            return psz_value;
        }
        if( c < 0x20 )
            break;
        if( c != '\\' )
        {
            if( !JsonAppendByte(&psz_value, &i_length, &i_alloc, c) )
                break;
            continue;
        }
        if( p_cursor->p >= p_cursor->p_end )
            break;
        c = (unsigned char)*p_cursor->p++;
        switch( c )
        {
            case '"': case '\\': case '/': break;
            case 'b': c = '\b'; break;
            case 'f': c = '\f'; break;
            case 'n': c = '\n'; break;
            case 'r': c = '\r'; break;
            case 't': c = '\t'; break;
            case 'u':
            {
                unsigned i_codepoint;
                if( !JsonReadHex4(p_cursor, &i_codepoint) )
                    goto error;
                if( i_codepoint >= 0xd800 && i_codepoint <= 0xdbff )
                {
                    unsigned i_low;
                    if( p_cursor->p_end - p_cursor->p < 6
                     || p_cursor->p[0] != '\\' || p_cursor->p[1] != 'u' )
                        goto error;
                    p_cursor->p += 2;
                    if( !JsonReadHex4(p_cursor, &i_low)
                     || i_low < 0xdc00 || i_low > 0xdfff )
                        goto error;
                    i_codepoint = 0x10000 + ((i_codepoint - 0xd800) << 10)
                                              + (i_low - 0xdc00);
                }
                else if( i_codepoint >= 0xdc00 && i_codepoint <= 0xdfff )
                    goto error;
                if( !JsonAppendCodepoint(&psz_value, &i_length, &i_alloc,
                                         i_codepoint) )
                    goto error;
                continue;
            }
            default: goto error;
        }
        if( !JsonAppendByte(&psz_value, &i_length, &i_alloc, c) )
            break;
    }
error:
    free( psz_value );
    return NULL;
}

static bool JsonNumber( json_cursor_t *p_cursor, double *pf_value )
{
    JsonSkipSpace( p_cursor );
    if( p_cursor->p >= p_cursor->p_end )
        return false;

    /* strtod() also accepts implementation extensions such as nan, inf and
     * hexadecimal floats. Scan the JSON number grammar first. */
    const char *p_end = p_cursor->p;
    if( *p_end == '-' )
        p_end++;
    if( p_end >= p_cursor->p_end )
        return false;
    if( *p_end == '0' )
        p_end++;
    else if( *p_end >= '1' && *p_end <= '9' )
        while( p_end < p_cursor->p_end && isdigit((unsigned char)*p_end) )
            p_end++;
    else
        return false;
    if( p_end < p_cursor->p_end && *p_end == '.' )
    {
        p_end++;
        const char *p_digits = p_end;
        while( p_end < p_cursor->p_end && isdigit((unsigned char)*p_end) )
            p_end++;
        if( p_end == p_digits )
            return false;
    }
    if( p_end < p_cursor->p_end && (*p_end == 'e' || *p_end == 'E') )
    {
        p_end++;
        if( p_end < p_cursor->p_end && (*p_end == '+' || *p_end == '-') )
            p_end++;
        const char *p_digits = p_end;
        while( p_end < p_cursor->p_end && isdigit((unsigned char)*p_end) )
            p_end++;
        if( p_end == p_digits )
            return false;
    }

    char *psz_end;
    errno = 0;
    double f_value = strtod( p_cursor->p, &psz_end );
    if( psz_end != p_end || errno == ERANGE || !isfinite(f_value) )
        return false;
    p_cursor->p = p_end;
    *pf_value = f_value;
    return true;
}

static bool JsonSkipValue( json_cursor_t *p_cursor );

static bool JsonSkipArray( json_cursor_t *p_cursor )
{
    if( !JsonTake(p_cursor, '[') ) return false;
    JsonSkipSpace( p_cursor );
    if( JsonTake(p_cursor, ']') ) return true;
    do {
        if( !JsonSkipValue(p_cursor) ) return false;
    } while( JsonTake(p_cursor, ',') );
    return JsonTake( p_cursor, ']' );
}

static bool JsonSkipObject( json_cursor_t *p_cursor )
{
    if( !JsonTake(p_cursor, '{') ) return false;
    JsonSkipSpace( p_cursor );
    if( JsonTake(p_cursor, '}') ) return true;
    do {
        char *psz_key = JsonString( p_cursor );
        free( psz_key );
        if( psz_key == NULL || !JsonTake(p_cursor, ':')
         || !JsonSkipValue(p_cursor) )
            return false;
    } while( JsonTake(p_cursor, ',') );
    return JsonTake( p_cursor, '}' );
}

static bool JsonSkipValue( json_cursor_t *p_cursor )
{
    JsonSkipSpace( p_cursor );
    if( p_cursor->p >= p_cursor->p_end ) return false;
    if( *p_cursor->p == '{' ) return JsonSkipObject( p_cursor );
    if( *p_cursor->p == '[' ) return JsonSkipArray( p_cursor );
    if( *p_cursor->p == '"' )
    {
        char *psz = JsonString( p_cursor );
        free( psz );
        return psz != NULL;
    }
    static const char *const ppsz_literals[] = { "true", "false", "null" };
    for( size_t i = 0; i < ARRAY_SIZE(ppsz_literals); i++ )
    {
        size_t i_length = strlen(ppsz_literals[i]);
        if( (size_t)(p_cursor->p_end - p_cursor->p) >= i_length
         && !memcmp(p_cursor->p, ppsz_literals[i], i_length) )
        {
            p_cursor->p += i_length;
            return true;
        }
    }
    double f;
    return JsonNumber( p_cursor, &f );
}

static bool JsonBookmark( json_cursor_t *p_cursor, seekpoint_t **pp_bookmark )
{
    if( !JsonTake(p_cursor, '{') ) return false;
    seekpoint_t *p_bookmark = vlc_seekpoint_New();
    if( p_bookmark == NULL ) return false;
    bool b_has_time_us = false;
    bool b_has_time = false;

    JsonSkipSpace( p_cursor );
    while( !JsonTake(p_cursor, '}') )
    {
        char *psz_key = JsonString( p_cursor );
        if( psz_key == NULL || !JsonTake(p_cursor, ':') )
        {
            free( psz_key );
            goto error;
        }
        if( !strcmp(psz_key, "name") )
        {
            char *psz_name = JsonString( p_cursor );
            if( psz_name == NULL ) { free(psz_key); goto error; }
            free( p_bookmark->psz_name );
            p_bookmark->psz_name = psz_name;
        }
        else if( !strcmp(psz_key, "time_us") )
        {
            double f;
            if( !JsonNumber(p_cursor, &f) || f < 0.0
             || f >= (double)INT64_MAX )
            { free(psz_key); goto error; }
            p_bookmark->i_time_offset = (vlc_tick_t)llround(f);
            b_has_time_us = true;
            b_has_time = true;
        }
        else if( !strcmp(psz_key, "time_seconds") )
        {
            double f;
            if( !JsonNumber(p_cursor, &f) || f < 0.0
             || f >= (double)INT64_MAX / CLOCK_FREQ )
            { free(psz_key); goto error; }
            if( !b_has_time_us )
                p_bookmark->i_time_offset = (vlc_tick_t)llround(f * CLOCK_FREQ);
            b_has_time = true;
        }
        else if( !JsonSkipValue(p_cursor) )
        {
            free( psz_key );
            goto error;
        }
        free( psz_key );
        if( JsonTake(p_cursor, '}') )
            break;
        if( !JsonTake(p_cursor, ',') )
            goto error;
    }

    if( !b_has_time )
        goto error;
    if( p_bookmark->psz_name == NULL )
        p_bookmark->psz_name = strdup( "Bookmark" );
    if( p_bookmark->psz_name == NULL )
        goto error;
    *pp_bookmark = p_bookmark;
    return true;
error:
    vlc_seekpoint_Delete( p_bookmark );
    return false;
}

static bool JsonBookmarks( json_cursor_t *p_cursor, bookmark_set_t *p_set )
{
    if( !JsonTake(p_cursor, '[') ) return false;
    JsonSkipSpace( p_cursor );
    if( JsonTake(p_cursor, ']') ) return true;
    for( ;; )
    {
        seekpoint_t *p_bookmark;
        if( !JsonBookmark(p_cursor, &p_bookmark) ) return false;
        seekpoint_t **pp_new = realloc( p_set->pp_bookmarks,
            (p_set->i_bookmarks + 1) * sizeof(*p_set->pp_bookmarks) );
        if( pp_new == NULL )
        {
            vlc_seekpoint_Delete( p_bookmark );
            return false;
        }
        p_set->pp_bookmarks = pp_new;
        p_set->pp_bookmarks[p_set->i_bookmarks++] = p_bookmark;
        if( JsonTake(p_cursor, ']') ) return true;
        if( !JsonTake(p_cursor, ',') ) return false;
    }
}

static bool JsonContent( json_cursor_t *p_cursor, bookmark_set_t *p_set )
{
    if( !JsonTake(p_cursor, '{') ) return false;
    JsonSkipSpace( p_cursor );
    while( !JsonTake(p_cursor, '}') )
    {
        char *psz_key = JsonString( p_cursor );
        if( psz_key == NULL || !JsonTake(p_cursor, ':') )
        {
            free( psz_key );
            return false;
        }
        if( !strcmp(psz_key, "id") || !strcmp(psz_key, "uri")
         || !strcmp(psz_key, "name") )
        {
            char *psz_value = JsonString( p_cursor );
            if( psz_value == NULL ) { free(psz_key); return false; }
            char **ppsz_target = !strcmp(psz_key, "id") ? &p_set->psz_id
                               : !strcmp(psz_key, "uri") ? &p_set->psz_uri
                                                         : &p_set->psz_name;
            free( *ppsz_target );
            *ppsz_target = psz_value;
        }
        else if( !strcmp(psz_key, "title") || !strcmp(psz_key, "duration_us") )
        {
            double f;
            if( !JsonNumber(p_cursor, &f) ) { free(psz_key); return false; }
            if( !strcmp(psz_key, "title") )
            {
                if( f < INT_MIN || f > INT_MAX || f != llround(f) )
                { free(psz_key); return false; }
                p_set->i_title = (int)f;
            }
            else
            {
                if( f < 0.0 || f >= (double)INT64_MAX )
                { free(psz_key); return false; }
                p_set->i_duration = (vlc_tick_t)llround(f);
            }
        }
        else if( !JsonSkipValue(p_cursor) )
        {
            free( psz_key );
            return false;
        }
        free( psz_key );
        if( JsonTake(p_cursor, '}') ) break;
        if( !JsonTake(p_cursor, ',') ) return false;
    }
    return p_set->psz_uri != NULL && p_set->psz_name != NULL;
}

static bool JsonBookmarkSet( json_cursor_t *p_cursor, bookmark_set_t *p_set )
{
    if( !JsonTake(p_cursor, '{') ) return false;
    bool b_format = false;
    bool b_version = false;
    bool b_content = false;
    bool b_bookmarks = false;
    JsonSkipSpace( p_cursor );
    while( !JsonTake(p_cursor, '}') )
    {
        char *psz_key = JsonString( p_cursor );
        if( psz_key == NULL || !JsonTake(p_cursor, ':') )
        {
            free( psz_key );
            return false;
        }
        bool b_ok;
        if( !strcmp(psz_key, "format") )
        {
            char *psz_format = JsonString( p_cursor );
            b_ok = psz_format != NULL
                && !strcmp(psz_format, BOOKMARKS_FORMAT);
            b_format = b_ok;
            free( psz_format );
        }
        else if( !strcmp(psz_key, "version") )
        {
            double f_version;
            b_ok = JsonNumber( p_cursor, &f_version )
                && f_version == BOOKMARKS_VERSION;
            b_version = b_ok;
        }
        else if( !strcmp(psz_key, "content") )
        {
            b_ok = JsonContent( p_cursor, p_set );
            b_content = b_ok;
        }
        else if( !strcmp(psz_key, "bookmarks") )
        {
            b_ok = JsonBookmarks( p_cursor, p_set );
            b_bookmarks = b_ok;
        }
        else
            b_ok = JsonSkipValue( p_cursor );
        free( psz_key );
        if( !b_ok ) return false;
        if( JsonTake(p_cursor, '}') ) break;
        if( !JsonTake(p_cursor, ',') ) return false;
    }
    return b_format && b_version && b_content && b_bookmarks;
}

static bool BookmarkCollectionAppend( bookmark_collection_t *p_collection,
                                      bookmark_set_t *p_set )
{
    bookmark_set_t *p_new = realloc( p_collection->p_sets,
        (p_collection->i_sets + 1) * sizeof(*p_collection->p_sets) );
    if( p_new == NULL ) return false;
    p_collection->p_sets = p_new;
    p_collection->p_sets[p_collection->i_sets++] = *p_set;
    memset( p_set, 0, sizeof(*p_set) );
    return true;
}

static bool JsonCollectionArray( json_cursor_t *p_cursor,
                                 bookmark_collection_t *p_collection )
{
    if( !JsonTake(p_cursor, '[') ) return false;
    JsonSkipSpace( p_cursor );
    if( JsonTake(p_cursor, ']') ) return true;
    for( ;; )
    {
        bookmark_set_t set = { 0 };
        if( !JsonBookmarkSet(p_cursor, &set)
         || !BookmarkCollectionAppend(p_collection, &set) )
        {
            BookmarkSetClean( &set );
            return false;
        }
        if( JsonTake(p_cursor, ']') ) return true;
        if( !JsonTake(p_cursor, ',') ) return false;
    }
}

static bool JsonDocument( const char *psz_json, size_t i_length,
                          bookmark_collection_t *p_collection )
{
    json_cursor_t cursor = { psz_json, psz_json + i_length };
    if( !JsonTake(&cursor, '{') ) return false;

    bookmark_set_t single = { 0 };
    bool b_collection = false;
    bool b_ok = true;
    char *psz_format = NULL;
    bool b_version = false;
    bool b_content = false;
    bool b_bookmarks = false;
    bool b_contents = false;
    JsonSkipSpace( &cursor );
    while( !JsonTake(&cursor, '}') )
    {
        char *psz_key = JsonString( &cursor );
        if( psz_key == NULL || !JsonTake(&cursor, ':') )
        {
            free( psz_key );
            b_ok = false;
            break;
        }
        if( !strcmp(psz_key, "format") )
        {
            free( psz_format );
            psz_format = JsonString( &cursor );
            b_ok = psz_format != NULL;
        }
        else if( !strcmp(psz_key, "version") )
        {
            double f_version;
            b_ok = JsonNumber( &cursor, &f_version )
                && f_version == BOOKMARKS_VERSION;
            b_version = b_ok;
        }
        else if( !strcmp(psz_key, "content") )
        {
            b_ok = JsonContent( &cursor, &single );
            b_content = b_ok;
        }
        else if( !strcmp(psz_key, "bookmarks") )
        {
            b_ok = JsonBookmarks( &cursor, &single );
            b_bookmarks = b_ok;
        }
        else if( !strcmp(psz_key, "contents") )
        {
            b_collection = true;
            b_ok = JsonCollectionArray( &cursor, p_collection );
            b_contents = b_ok;
        }
        else
            b_ok = JsonSkipValue( &cursor );
        free( psz_key );
        if( !b_ok ) break;
        if( JsonTake(&cursor, '}') ) break;
        if( !JsonTake(&cursor, ',') ) { b_ok = false; break; }
    }
    JsonSkipSpace( &cursor );
    if( cursor.p != cursor.p_end ) b_ok = false;
    const char *psz_expected = b_collection
        ? BOOKMARKS_COLLECTION_FORMAT : BOOKMARKS_FORMAT;
    if( psz_format == NULL || strcmp(psz_format, psz_expected) || !b_version )
        b_ok = false;
    if( b_collection ? (!b_contents || b_content || b_bookmarks)
                     : (!b_content || !b_bookmarks || b_contents) )
        b_ok = false;

    if( b_ok && !b_collection )
        b_ok = BookmarkCollectionAppend( p_collection, &single );
    if( b_ok )
        p_collection->b_is_collection = b_collection;
    free( psz_format );
    BookmarkSetClean( &single );
    return b_ok;
}

static char *BookmarkReadFile( const char *psz_path, size_t *pi_length )
{
    FILE *p_file = vlc_fopen( psz_path, "rb" );
    if( p_file == NULL ) return NULL;
    if( fseek(p_file, 0, SEEK_END) || ftell(p_file) < 0 )
    {
        fclose( p_file );
        return NULL;
    }
    long i_size = ftell( p_file );
    if( i_size < 0 || (unsigned long)i_size > BOOKMARKS_MAX_FILE
     || fseek(p_file, 0, SEEK_SET) )
    {
        fclose( p_file );
        return NULL;
    }
    char *psz_json = malloc( (size_t)i_size + 1 );
    if( psz_json == NULL ) { fclose(p_file); return NULL; }
    if( fread(psz_json, 1, (size_t)i_size, p_file) != (size_t)i_size )
    {
        free( psz_json );
        fclose( p_file );
        return NULL;
    }
    fclose( p_file );
    psz_json[i_size] = '\0';
    *pi_length = (size_t)i_size;
    return psz_json;
}

static int BookmarkParsePath( const char *psz_path,
                              bookmark_collection_t *p_collection )
{
    size_t i_length;
    char *psz_json = BookmarkReadFile( psz_path, &i_length );
    if( psz_json == NULL ) return VLC_EGENERIC;
    bool b_ok = JsonDocument( psz_json, i_length, p_collection );
    free( psz_json );
    if( !b_ok ) BookmarkCollectionClean( p_collection );
    return b_ok ? VLC_SUCCESS : VLC_EGENERIC;
}

static void BookmarkSetApply( input_thread_t *p_input,
                              const bookmark_set_t *p_set )
{
    input_thread_private_t *p_priv = input_priv(p_input);
    input_item_t *p_item = input_GetItem( p_input );
    p_priv->b_bookmarks_loading = true;

    vlc_mutex_lock( &p_item->lock );
    for( int i = 0; i < p_priv->i_bookmark; i++ )
        vlc_seekpoint_Delete( p_priv->pp_bookmark[i] );
    TAB_CLEAN( p_priv->i_bookmark, p_priv->pp_bookmark );
    for( size_t i = 0; i < p_set->i_bookmarks; i++ )
    {
        seekpoint_t *p_copy = vlc_seekpoint_Duplicate(p_set->pp_bookmarks[i]);
        if( p_copy != NULL )
            TAB_APPEND( p_priv->i_bookmark, p_priv->pp_bookmark, p_copy );
    }
    vlc_mutex_unlock( &p_item->lock );

    input_UpdateBookmarksOption( p_input );
    p_priv->b_bookmarks_loading = false;
}

static int BookmarkLoadCurrent( input_thread_t *p_input, bool b_clear_missing )
{
    input_thread_private_t *p_priv = input_priv(p_input);
    input_item_t *p_item = input_GetItem( p_input );
    char *psz_uri = input_item_GetURI( p_item );
    if( psz_uri == NULL ) return VLC_EGENERIC;
    char *psz_name = input_item_GetTitleFbName( p_item );
    char *psz_id = BookmarkContentId( psz_uri, psz_name,
                                      p_priv->i_bookmark_title );
    free( psz_name );
    free( psz_uri );
    if( psz_id == NULL ) return VLC_ENOMEM;
    char *psz_path = BookmarksPath( VLC_OBJECT(p_input), psz_id, false );
    free( psz_id );

    bookmark_collection_t collection = { 0 };
    int i_ret = psz_path ? BookmarkParsePath(psz_path, &collection) : VLC_EGENERIC;
    free( psz_path );
    if( i_ret == VLC_SUCCESS && !collection.b_is_collection
     && collection.i_sets == 1 )
        BookmarkSetApply( p_input, &collection.p_sets[0] );
    else if( b_clear_missing )
    {
        bookmark_set_t empty = { 0 };
        BookmarkSetApply( p_input, &empty );
        i_ret = VLC_SUCCESS;
    }
    BookmarkCollectionClean( &collection );
    return i_ret;
}

void input_BookmarksInitialize( input_thread_t *p_input )
{
    input_thread_private_t *p_priv = input_priv(p_input);
    p_priv->i_bookmark_title = var_GetInteger( p_input, "title" );
    p_priv->b_bookmarks_ready = true;
    BookmarkLoadCurrent( p_input, false );
}

void input_BookmarksPersist( input_thread_t *p_input )
{
    input_thread_private_t *p_priv = input_priv(p_input);
    if( !p_priv->b_bookmarks_ready || p_priv->b_bookmarks_loading )
        return;

    bookmark_set_t set;
    if( BookmarkSetCapture(p_input, &set) != VLC_SUCCESS )
        return;
    char *psz_path = BookmarksPath( VLC_OBJECT(p_input), set.psz_id,
                                    set.i_bookmarks > 0 );
    if( psz_path != NULL )
    {
        if( set.i_bookmarks == 0 )
            vlc_unlink( psz_path );
        else if( BookmarkSetWritePath(VLC_OBJECT(p_input), &set,
                                      psz_path, true) != VLC_SUCCESS )
            msg_Err( p_input, "could not persist bookmarks" );
    }
    free( psz_path );
    BookmarkSetClean( &set );
}

void input_BookmarksSwitchTitle( input_thread_t *p_input, int i_title )
{
    input_thread_private_t *p_priv = input_priv(p_input);
    if( !p_priv->b_bookmarks_ready || p_priv->i_bookmark_title == i_title )
        return;
    input_BookmarksPersist( p_input );
    p_priv->i_bookmark_title = i_title;
    BookmarkLoadCurrent( p_input, true );
}

int input_BookmarksExport( input_thread_t *p_input, const char *psz_path )
{
    if( psz_path == NULL || *psz_path == '\0' ) return VLC_EGENERIC;
    bookmark_set_t set;
    int i_ret = BookmarkSetCapture( p_input, &set );
    if( i_ret == VLC_SUCCESS )
        i_ret = BookmarkSetWritePath( VLC_OBJECT(p_input), &set,
                                      psz_path, false );
    BookmarkSetClean( &set );
    return i_ret;
}

static int BookmarkSetStoreImported( vlc_object_t *p_obj, bookmark_set_t *p_set )
{
    if( p_set->psz_uri != NULL )
    {
        char *psz_id = BookmarkContentId(p_set->psz_uri, p_set->psz_name,
                                         p_set->i_title);
        free( p_set->psz_id );
        p_set->psz_id = psz_id;
    }
    if( !BookmarkIdValid(p_set->psz_id) ) return VLC_EGENERIC;
    char *psz_path = BookmarksPath( p_obj, p_set->psz_id, true );
    if( psz_path == NULL ) return VLC_EGENERIC;
    int i_ret = BookmarkSetWritePath( p_obj, p_set, psz_path, true );
    free( psz_path );
    return i_ret;
}

static int BookmarkCollectionStore( vlc_object_t *p_obj,
                                    input_thread_t *p_current,
                                    bookmark_collection_t *p_collection )
{
    char *psz_current_id = NULL;
    if( p_current != NULL )
    {
        input_thread_private_t *p_priv = input_priv(p_current);
        input_item_t *p_item = input_GetItem( p_current );
        char *psz_uri = input_item_GetURI( p_item );
        char *psz_name = input_item_GetTitleFbName( p_item );
        if( psz_uri != NULL )
            psz_current_id = BookmarkContentId(psz_uri, psz_name,
                                                p_priv->i_bookmark_title);
        free( psz_name );
        free( psz_uri );
    }

    int i_ret = VLC_SUCCESS;
    for( size_t i = 0; i < p_collection->i_sets; i++ )
    {
        bookmark_set_t *p_set = &p_collection->p_sets[i];
        if( BookmarkSetStoreImported(p_obj, p_set) != VLC_SUCCESS )
            i_ret = VLC_EGENERIC;
        if( p_current != NULL && psz_current_id != NULL
         && p_set->psz_id != NULL
         && !strcasecmp(psz_current_id, p_set->psz_id) )
            BookmarkSetApply( p_current, p_set );
    }
    free( psz_current_id );
    return i_ret;
}

int input_BookmarksImport( input_thread_t *p_input, const char *psz_path )
{
    bookmark_collection_t collection = { 0 };
    if( psz_path == NULL
     || BookmarkParsePath(psz_path, &collection) != VLC_SUCCESS
     || collection.i_sets == 0 )
    {
        BookmarkCollectionClean( &collection );
        return VLC_EGENERIC;
    }

    int i_ret = VLC_SUCCESS;
    if( !collection.b_is_collection )
    {
        /* A shared single-content file is intentionally portable: applying
         * it to the media currently open also works when that media lives at
         * a different path on the receiving computer. */
        BookmarkSetApply( p_input, &collection.p_sets[0] );
        input_BookmarksPersist( p_input );
    }
    else
        i_ret = BookmarkCollectionStore( VLC_OBJECT(p_input), p_input,
                                         &collection );
    BookmarkCollectionClean( &collection );
    return i_ret;
}

#undef input_BookmarksImportAll
int input_BookmarksImportAll( vlc_object_t *p_obj, const char *psz_path )
{
    bookmark_collection_t collection = { 0 };
    if( psz_path == NULL
     || BookmarkParsePath(psz_path, &collection) != VLC_SUCCESS
     || !collection.b_is_collection )
    {
        BookmarkCollectionClean( &collection );
        return VLC_EGENERIC;
    }
    int i_ret = BookmarkCollectionStore( p_obj, NULL, &collection );
    BookmarkCollectionClean( &collection );
    return i_ret;
}

static bool BookmarkFilename( const char *psz_name )
{
    if( strlen(psz_name) != 37 || strcmp(psz_name + 32, ".json") )
        return false;
    char psz_id[33];
    memcpy( psz_id, psz_name, 32 );
    psz_id[32] = '\0';
    return BookmarkIdValid( psz_id );
}

#undef input_BookmarksExportAll
int input_BookmarksExportAll( vlc_object_t *p_obj, const char *psz_path )
{
    if( psz_path == NULL || *psz_path == '\0' )
        return VLC_EGENERIC;
    char *psz_dir = BookmarksDirectory( p_obj, false );
    if( psz_dir == NULL ) return VLC_EGENERIC;
    DIR *p_directory = vlc_opendir( psz_dir );

    bookmark_collection_t all = { 0 };
    if( p_directory != NULL )
    {
        const char *psz_name;
        while( (psz_name = vlc_readdir(p_directory)) != NULL )
        {
            if( !BookmarkFilename(psz_name) ) continue;
            char *psz_file;
            if( asprintf(&psz_file, "%s" DIR_SEP "%s", psz_dir, psz_name) < 0 )
                continue;
            bookmark_collection_t one = { 0 };
            if( BookmarkParsePath(psz_file, &one) == VLC_SUCCESS
             && !one.b_is_collection && one.i_sets == 1 )
                BookmarkCollectionAppend( &all, &one.p_sets[0] );
            BookmarkCollectionClean( &one );
            free( psz_file );
        }
        closedir( p_directory );
    }
    else if( errno != ENOENT )
    {
        free( psz_dir );
        return VLC_EGENERIC;
    }
    free( psz_dir );

    FILE *p_file = vlc_fopen( psz_path, "wt" );
    if( p_file == NULL )
    {
        BookmarkCollectionClean( &all );
        return VLC_EGENERIC;
    }
    int i_ret = fprintf(p_file,
        "{\n    \"format\": \"%s\",\n    \"version\": %d,\n"
        "    \"contents\": [",
        BOOKMARKS_COLLECTION_FORMAT, BOOKMARKS_VERSION) < 0
        ? VLC_EGENERIC : VLC_SUCCESS;
    for( size_t i = 0; i < all.i_sets && i_ret == VLC_SUCCESS; i++ )
    {
        if( fprintf(p_file, "%s\n", i ? "," : "") < 0
         || BookmarkSetWrite(p_file, &all.p_sets[i], 1) != VLC_SUCCESS )
            i_ret = VLC_EGENERIC;
    }
    if( fprintf(p_file, "%s\n    ]\n}\n", all.i_sets ? "" : "") < 0
     || fclose(p_file) )
        i_ret = VLC_EGENERIC;
    BookmarkCollectionClean( &all );
    return i_ret;
}

#undef input_BookmarksClearAll
int input_BookmarksClearAll( vlc_object_t *p_obj )
{
    char *psz_dir = BookmarksDirectory( p_obj, false );
    if( psz_dir != NULL )
    {
        DIR *p_directory = vlc_opendir( psz_dir );
        if( p_directory != NULL )
        {
            const char *psz_name;
            while( (psz_name = vlc_readdir(p_directory)) != NULL )
            {
                if( !BookmarkFilename(psz_name) ) continue;
                char *psz_file;
                if( asprintf(&psz_file, "%s" DIR_SEP "%s", psz_dir,
                             psz_name) >= 0 )
                {
                    vlc_unlink( psz_file );
                    free( psz_file );
                }
            }
            closedir( p_directory );
        }
        free( psz_dir );
    }

    return VLC_SUCCESS;
}
