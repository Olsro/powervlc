/*****************************************************************************
 * misc.c
 *****************************************************************************
 * Copyright (C) 2007-2008 the VideoLAN team
 * $Id$
 *
 * Authors: Antoine Cellerier <dionoea at videolan tod org>
 *          Pierre d'Herbemont <pdherbemont # videolan.org>
 *          Rémi Duraffort <ivoire # videolan tod org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/
#ifndef  _GNU_SOURCE
#   define  _GNU_SOURCE
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <math.h>
#include <stdlib.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_meta.h>
#include <vlc_interface.h>
#include <vlc_actions.h>
#include <vlc_interrupt.h>
#include <vlc_image.h>
#include <vlc_url.h>
#include <vlc_fs.h>

#include "../vlc.h"
#include "../libs.h"
#include "misc.h"

/*****************************************************************************
 * Internal lua<->vlc utils
 *****************************************************************************/
void vlclua_set_object( lua_State *L, void *id, void *value )
{
    lua_pushlightuserdata( L, id );
    lua_pushlightuserdata( L, value );
    lua_rawset( L, LUA_REGISTRYINDEX );
}

void *vlclua_get_object( lua_State *L, void *id )
{
    lua_pushlightuserdata( L, id );
    lua_rawget( L, LUA_REGISTRYINDEX );
    const void *p = lua_topointer( L, -1 );
    lua_pop( L, 1 );
    return (void *)p;
}

#undef vlclua_set_this
void vlclua_set_this( lua_State *L, vlc_object_t *p_this )
{
    vlclua_set_object( L, vlclua_set_this, p_this );
}

vlc_object_t * vlclua_get_this( lua_State *L )
{
    return vlclua_get_object( L, vlclua_set_this );
}

/*****************************************************************************
 * VLC error code translation
 *****************************************************************************/
int vlclua_push_ret( lua_State *L, int i_error )
{
    lua_pushnumber( L, i_error );
    lua_pushstring( L, vlc_error( i_error ) );
    return 2;
}

/*****************************************************************************
 * Get the VLC version string
 *****************************************************************************/
static int vlclua_version( lua_State *L )
{
    lua_pushstring( L, VERSION_MESSAGE );
    return 1;
}

/*****************************************************************************
 * Get the PowerVLC product version
 *
 * vlc.misc.version() answers what VLC release this is derived from, which
 * is not what a script should give its name as: extensions that identify
 * themselves to a server (Jellyfin registers a device, Last.fm a client)
 * used to repeat "1.1.0" in their own source and drift from the tree.
 *****************************************************************************/
static int vlclua_product_version( lua_State *L )
{
    lua_pushliteral( L, POWERVLC_VERSION );
    return 1;
}

/*****************************************************************************
 * Get the VLC copyright
 *****************************************************************************/
static int vlclua_copyright( lua_State *L )
{
    lua_pushliteral( L, COPYRIGHT_MESSAGE );
    return 1;
}

/*****************************************************************************
 * Get the VLC license msg/disclaimer
 *****************************************************************************/
static int vlclua_license( lua_State *L )
{
    lua_pushstring( L, LICENSE_MSG );
    return 1;
}

/*****************************************************************************
 * Quit VLC
 *****************************************************************************/
static int vlclua_quit( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    /* The rc.c code also stops the playlist ... not sure if this is needed
     * though. */
    libvlc_Quit( p_this->obj.libvlc );
    return 0;
}

static int vlclua_mdate( lua_State *L )
{
    lua_pushnumber( L, mdate() );
    return 1;
}

static int vlclua_mwait( lua_State *L )
{
    double f = luaL_checknumber( L, 1 );

    vlc_interrupt_t *oint = vlclua_set_interrupt( L );
    int ret = vlc_mwait_i11e( llround(f) );

    vlc_interrupt_set( oint );
    if( ret )
        return luaL_error( L, "Interrupted." );
    return 0;
}

static int vlclua_action_id( lua_State *L )
{
    vlc_action_id_t i_key = vlc_actions_get_id( luaL_checkstring( L, 1 ) );
    if (i_key == 0)
        return 0;
    lua_pushnumber( L, i_key );
    return 1;
}

/*****************************************************************************
 *
 *****************************************************************************/
/*****************************************************************************
 * Pictures
 *****************************************************************************/
/**
 * vlc.misc.image_scale( source, destination, max_width, max_height )
 *
 * Reads a picture, and writes it out no larger than the given bounds,
 * in the format the destination file name asks for. The proportions are
 * kept, and a picture already small enough is only converted.
 *
 * This is the core's own image path, so whatever VLC can decode comes
 * in -- which matters for what servers actually send: a cover may
 * arrive as WebP, a format the machines this fork exists for cannot
 * display at all, and at whatever size the server felt like. Handing a
 * 1024x1024 picture to an interface that lays out at its natural size
 * is how a dialog ends up taller than the screen.
 *
 * Returns width, height of what was written, or nil and a message.
 **/
/* What a picture file holds, read from the file itself.
 *
 * The core guesses the format from the MIME type of the stream or from
 * the file name, and neither says anything about a file downloaded to a
 * temporary name: it answered "no suitable decoder for fourcc `    '".
 * The first bytes do say, and unlike a name they cannot lie. */
static vlc_fourcc_t vlclua_sniff_image( const char *psz_path )
{
    FILE *file = vlc_fopen( psz_path, "rb" );
    if( !file )
        return 0;

    unsigned char head[16];
    size_t i_read = fread( head, 1, sizeof( head ), file );
    fclose( file );
    if( i_read < 12 )
        return 0;

    if( head[0] == 0xFF && head[1] == 0xD8 && head[2] == 0xFF )
        return VLC_CODEC_JPEG;
    if( !memcmp( head, "\x89PNG\r\n\x1a\n", 8 ) )
        return VLC_CODEC_PNG;
    if( !memcmp( head, "GIF8", 4 ) )
        return VLC_CODEC_GIF;
    if( !memcmp( head, "RIFF", 4 ) && !memcmp( head + 8, "WEBP", 4 ) )
        return VLC_CODEC_WEBP;
    if( head[0] == 'B' && head[1] == 'M' )
        return VLC_CODEC_BMP;
    return 0;
}

/* Lay a picture that has transparency over a white sheet.
 *
 * Neither of the formats worth writing keeps an alpha channel here --
 * JPEG has none at all, and this build's PNG encoder takes plain RGB --
 * so the transparent parts arrive at the encoder as whatever sits under
 * them, which is black: a cover with a cut-out shape came out as that
 * shape on a black square, its soft edges turned to gravel. Compositing
 * first is what the transparency meant in the first place. */
static void vlclua_flatten_on_white( picture_t *p_pic,
                                     const video_format_t *p_fmt )
{
    int i_alpha;
    switch( p_fmt->i_chroma )
    {
        case VLC_CODEC_RGBA:
        case VLC_CODEC_BGRA:
            i_alpha = 3;
            break;
        case VLC_CODEC_ARGB:
            i_alpha = 0;
            break;
        default:
            return;   /* nothing to composite */
    }

    plane_t *p_plane = &p_pic->p[0];
    for( int y = 0; y < p_plane->i_visible_lines; y++ )
    {
        uint8_t *p_line = p_plane->p_pixels + y * p_plane->i_pitch;
        for( int x = 0; x + 3 < p_plane->i_visible_pitch; x += 4 )
        {
            uint8_t *p_px = p_line + x;
            unsigned i_a = p_px[i_alpha];
            if( i_a == 255 )
                continue;
            for( int i = 0; i < 4; i++ )
            {
                if( i == i_alpha )
                    continue;
                p_px[i] = ( p_px[i] * i_a + 255 * ( 255 - i_a ) ) / 255;
            }
            p_px[i_alpha] = 255;
        }
    }
}

/* Does this picture format carry transparency? */
static bool vlclua_has_alpha( vlc_fourcc_t i_chroma )
{
    switch( i_chroma )
    {
        case VLC_CODEC_RGBA:
        case VLC_CODEC_ARGB:
        case VLC_CODEC_BGRA:
        case VLC_CODEC_YUVA:
        case VLC_CODEC_YUV420A:
        case VLC_CODEC_YUV422A:
            return true;
        default:
            return false;
    }
}

static int vlclua_image_scale( lua_State *L )
{
    vlc_object_t *p_this = vlclua_get_this( L );
    const char *psz_src = luaL_checkstring( L, 1 );
    const char *psz_dst = luaL_checkstring( L, 2 );
    int i_max_width = luaL_checkint( L, 3 );
    int i_max_height = luaL_checkint( L, 4 );

    if( i_max_width < 1 || i_max_height < 1 )
        return luaL_error( L, "image_scale: bounds must be positive" );

    image_handler_t *p_image = image_HandlerCreate( p_this );
    if( !p_image )
        return vlclua_error( L );

    /* ImageReadUrl opens through the stream layer: it wants a URL */
    char *psz_url = vlc_path2uri( psz_src, NULL );
    if( !psz_url )
    {
        image_HandlerDelete( p_image );
        return vlclua_error( L );
    }

    video_format_t fmt_in, fmt_out;
    video_format_Init( &fmt_in, vlclua_sniff_image( psz_src ) );
    video_format_Init( &fmt_out, 0 );

    picture_t *p_pic = image_ReadUrl( p_image, psz_url, &fmt_in, &fmt_out );
    free( psz_url );
    if( !p_pic )
    {
        video_format_Clean( &fmt_in );
        video_format_Clean( &fmt_out );
        image_HandlerDelete( p_image );
        lua_pushnil( L );
        lua_pushstring( L, "cannot read the picture" );
        return 2;
    }

    unsigned i_width = fmt_out.i_visible_width;
    unsigned i_height = fmt_out.i_visible_height;
    if( i_width < 1 || i_height < 1 )
    {
        i_width = fmt_out.i_width;
        i_height = fmt_out.i_height;
    }

    /* A picture with transparency has to be laid over something before
     * it can be written, since neither format worth writing keeps an
     * alpha channel. A decoder hands it over in whatever it pleases --
     * a WebP arrives as planar YUV with an alpha plane, not as RGBA --
     * so the core's converter puts it in one shape first. */
    if( vlclua_has_alpha( fmt_out.i_chroma ) )
    {
        video_format_t fmt_rgba;
        video_format_Init( &fmt_rgba, VLC_CODEC_RGBA );
        fmt_rgba.i_width = fmt_rgba.i_visible_width = i_width;
        fmt_rgba.i_height = fmt_rgba.i_visible_height = i_height;
        fmt_rgba.i_sar_num = fmt_rgba.i_sar_den = 1;

        picture_t *p_rgba = image_Convert( p_image, p_pic, &fmt_out,
                                           &fmt_rgba );
        if( p_rgba )
        {
            picture_Release( p_pic );
            p_pic = p_rgba;
            video_format_Clean( &fmt_out );
            fmt_out = fmt_rgba;    /* this is the picture now */
            vlclua_flatten_on_white( p_pic, &fmt_out );
        }
        else
            video_format_Clean( &fmt_rgba );
    }

    /* Fit inside the box without distorting it, and never blow a small
     * picture up: the point is to stop one being too big, not to make
     * every one the same size. */
    unsigned i_dst_width = i_width, i_dst_height = i_height;
    if( i_width > (unsigned)i_max_width || i_height > (unsigned)i_max_height )
    {
        double f_scale_w = (double)i_max_width / i_width;
        double f_scale_h = (double)i_max_height / i_height;
        double f_scale = ( f_scale_w < f_scale_h ) ? f_scale_w : f_scale_h;
        i_dst_width = (unsigned)( i_width * f_scale );
        i_dst_height = (unsigned)( i_height * f_scale );
        if( i_dst_width < 1 )
            i_dst_width = 1;
        if( i_dst_height < 1 )
            i_dst_height = 1;
    }

    video_format_t fmt_write;
    video_format_Init( &fmt_write, 0 );   /* chroma from the file name */
    fmt_write.i_width = fmt_write.i_visible_width = i_dst_width;
    fmt_write.i_height = fmt_write.i_visible_height = i_dst_height;
    fmt_write.i_sar_num = fmt_write.i_sar_den = 1;

    int i_ret = image_WriteUrl( p_image, p_pic, &fmt_out, &fmt_write, psz_dst );

    picture_Release( p_pic );
    video_format_Clean( &fmt_in );
    video_format_Clean( &fmt_out );
    video_format_Clean( &fmt_write );
    image_HandlerDelete( p_image );

    if( i_ret != VLC_SUCCESS )
    {
        lua_pushnil( L );
        lua_pushstring( L, "cannot write the picture" );
        return 2;
    }

    lua_pushinteger( L, i_dst_width );
    lua_pushinteger( L, i_dst_height );
    return 2;
}

static const luaL_Reg vlclua_misc_reg[] = {
    { "version", vlclua_version },
    { "product_version", vlclua_product_version },
    { "copyright", vlclua_copyright },
    { "license", vlclua_license },

    { "action_id", vlclua_action_id },

    { "image_scale", vlclua_image_scale },

    { "mdate", vlclua_mdate },
    { "mwait", vlclua_mwait },

    { "quit", vlclua_quit },

    { NULL, NULL }
};

void luaopen_misc( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_misc_reg );
    lua_setfield( L, -2, "misc" );
}

/* What an extension gets: the same table without the entries that act on
 * the player. A script has no business quitting PowerVLC or sleeping the
 * thread that drives its dialog, but it does need to say which build it
 * belongs to when it introduces itself to a server. */
static const luaL_Reg vlclua_misc_info_reg[] = {
    { "version", vlclua_version },
    { "product_version", vlclua_product_version },
    { "copyright", vlclua_copyright },
    { "license", vlclua_license },

    /* A script that fetches artwork needs to be able to bring it down to
     * a sane size before handing it to a dialog. */
    { "image_scale", vlclua_image_scale },

    { NULL, NULL }
};

void luaopen_misc_info( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_misc_info_reg );
    lua_setfield( L, -2, "misc" );
}
