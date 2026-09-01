/*****************************************************************************
 * search.c : Search functions
 *****************************************************************************
 * Copyright (C) 1999-2009 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
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
#include <ctype.h>
#include <assert.h>
#include <string.h>

#include <vlc_common.h>
#include <vlc_playlist.h>
#include <vlc_charset.h>
#include "playlist_internal.h"

/***************************************************************************
 * Item search functions
 ***************************************************************************/

/***************************************************************************
 * Live search handling
 ***************************************************************************/

/**
 * Enable all items in the playlist
 * @param p_root: the current root item
 */
static void playlist_LiveSearchClean( playlist_item_t *p_root )
{
    for( int i = 0; i < p_root->i_children; i++ )
    {
        playlist_item_t *p_item = p_root->pp_children[i];
        if( p_item->i_children >= 0 )
            playlist_LiveSearchClean( p_item );
        p_item->i_flags &= ~PLAYLIST_DBL_FLAG;
    }
}


/**
 * Enable/Disable items in the playlist according to the search argument
 * @param p_root: the current root item
 * @param psz_string: the string to search
 * @return true if an item match
 */
/* Both sides are folded (case, accents, Latin ligatures and typographic
 * punctuation), so that "au coeur de l'histoire" finds a feed titled
 * "Au Cœur de l’Histoire". The needle is folded once by the caller. */
static bool SearchContainsToken( const char *haystack, const char *token,
                                 size_t length )
{
    const size_t haystack_length = strlen( haystack );
    if( length > haystack_length ) return false;
    for( size_t offset = 0; offset <= haystack_length - length; ++offset )
        if( !memcmp( haystack + offset, token, length ) ) return true;
    return false;
}

static bool SearchMatches( const char *psz_haystack, const char *psz_folded_needle )
{
    if( !psz_haystack )
        return false;

    char *psz_folded = vlc_strfold( psz_haystack );
    if( unlikely(psz_folded == NULL) ) /* out of memory: plain search */
        return vlc_strcasestr( psz_haystack, psz_folded_needle ) != NULL;

    bool b_match = strstr( psz_folded, psz_folded_needle ) != NULL;
    if( !b_match )
    {
        const char *p = psz_folded_needle;
        bool any = false;
        b_match = true;
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
            if( !SearchContainsToken( psz_folded, begin, length ) )
                b_match = false;
            if( !b_match ) break;
        }
        b_match = b_match && any;
    }
    free( psz_folded );
    return b_match;
}

static bool playlist_LiveSearchUpdateInternal( playlist_item_t *p_root,
                                               const char *psz_string, bool b_recursive )
{
    int i;
    bool b_match = false;
    for( i = 0 ; i < p_root->i_children ; i ++ )
    {
        bool b_enable = false;
        playlist_item_t *p_item = p_root->pp_children[i];
        /* Random entries are commands backed by a private XSPF subtree, not
         * media-library content.  Matching their translated label (or one of
         * their private descendants) makes a query such as "random" unfold
         * one synthetic row per album and duplicates the visible library. */
        if( p_item->p_input != NULL
         && input_item_IsPowerVLCRandomAction( p_item->p_input ) )
        {
            p_item->i_flags |= PLAYLIST_DBL_FLAG;
            continue;
        }
        // Go recurssively if their is some children
        if( b_recursive && p_item->i_children >= 0 &&
            playlist_LiveSearchUpdateInternal( p_item, psz_string, true ) )
        {
            b_enable = true;
        }

        if( !b_enable )
        {
            vlc_mutex_lock( &p_item->p_input->lock );
            // Do we have some meta ?
            if( p_item->p_input->p_meta )
            {
                // Use Title or fall back to psz_name
                const char *psz_title = vlc_meta_Get( p_item->p_input->p_meta, vlc_meta_Title );
                if( !psz_title )
                    psz_title = p_item->p_input->psz_name;
                const char *psz_album = vlc_meta_Get( p_item->p_input->p_meta, vlc_meta_Album );
                const char *psz_artist = vlc_meta_Get( p_item->p_input->p_meta, vlc_meta_Artist );
                const char *psz_album_artist = vlc_meta_Get( p_item->p_input->p_meta,
                                                             vlc_meta_AlbumArtist );
                /* Virtual media-library folders carry inherited metadata;
                 * their meta title can therefore differ from the visible
                 * node name (notably artist and album branches). Always
                 * search the displayed name as well. */
                b_enable = SearchMatches( p_item->p_input->psz_name,
                                          psz_string ) ||
                           SearchMatches( psz_title, psz_string ) ||
                           SearchMatches( psz_album, psz_string ) ||
                           SearchMatches( psz_artist, psz_string ) ||
                           SearchMatches( psz_album_artist, psz_string );
            }
            else
                b_enable = SearchMatches( p_item->p_input->psz_name, psz_string );
            vlc_mutex_unlock( &p_item->p_input->lock );
        }

        if( b_enable )
            p_item->i_flags &= ~PLAYLIST_DBL_FLAG;
        else
            p_item->i_flags |= PLAYLIST_DBL_FLAG;

        b_match |= b_enable;
   }
   return b_match;
}



/**
 * Launch the recursive search in the playlist
 * @param p_playlist: the playlist
 * @param p_root: the current root item
 * @param psz_string: the string to find
 * @return VLC_SUCCESS
 */
int playlist_LiveSearchUpdate( playlist_t *p_playlist, playlist_item_t *p_root,
                               const char *psz_string, bool b_recursive )
{
    PL_ASSERT_LOCKED;
    pl_priv(p_playlist)->b_reset_currently_playing = true;
    /* Search fields commonly leave a trailing space while the user types.
     * It must not become part of the needle ("Fei " still finds
     * "Fei Lian"). Keep inner spaces intact, since they are meaningful. */
    const char *psz_begin = psz_string;
    while( *psz_begin == ' ' || *psz_begin == '\t'
        || *psz_begin == '\r' || *psz_begin == '\n' )
        ++psz_begin;
    size_t i_length = strlen( psz_begin );
    while( i_length > 0 )
    {
        const char c = psz_begin[i_length - 1];
        if( c != ' ' && c != '\t' && c != '\r' && c != '\n' )
            break;
        --i_length;
    }

    if( i_length > 0 )
    {
        char *psz_needle = malloc( i_length + 1 );
        if( unlikely(psz_needle == NULL) )
            return VLC_ENOMEM;
        memcpy( psz_needle, psz_begin, i_length );
        psz_needle[i_length] = '\0';
        /* fold the needle once for the whole walk */
        char *psz_folded = vlc_strfold( psz_needle );
        playlist_LiveSearchUpdateInternal( p_root,
                                           psz_folded ? psz_folded : psz_needle,
                                           b_recursive );
        free( psz_folded );
        free( psz_needle );
    }
    else
        playlist_LiveSearchClean( p_root );
    vlc_cond_signal( &pl_priv(p_playlist)->signal );
    return VLC_SUCCESS;
}
