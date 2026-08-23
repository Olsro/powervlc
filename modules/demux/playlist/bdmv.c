/*****************************************************************************
 * bdmv.c: open Blu-ray folder structures through index.bdmv
 *****************************************************************************
 * Copyright (C) 2018 VLC authors and VideoLAN
 *
 * Authors: Shaya Potter <spotter@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *****************************************************************************
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_access.h>

#include "playlist.h"

static int ReadBDMV(stream_t *, input_item_node_t *);

static const char *StreamLocation(const stream_t *stream)
{
    return stream->psz_filepath ? stream->psz_filepath : stream->psz_url;
}

int Import_BDMV(vlc_object_t *object)
{
    stream_t *stream = (stream_t *)object;

    CHECK_FILE(stream);

    if (!stream_HasExtension(stream, ".BDMV"))
        return VLC_EGENERIC;

    const char *location = StreamLocation(stream);
    if (location == NULL)
        return VLC_EGENERIC;

    size_t length = strlen(location);
    if (length < 15)
        return VLC_EGENERIC;

    const char *filename = location + length - 10;
    if (strncasecmp(filename, "INDEX.BDMV", 10) != 0)
        return VLC_EGENERIC;

    const uint8_t *peek;
    if (vlc_stream_Peek(stream->p_source, &peek, 8) < 8 ||
        memcmp(peek, "INDX0200", 8) != 0)
        return VLC_EGENERIC;

    stream->pf_readdir = ReadBDMV;
    stream->pf_control = access_vaDirectoryControlHelper;
    return VLC_SUCCESS;
}

static int ReadBDMV(stream_t *stream, input_item_node_t *node)
{
    const char *location = StreamLocation(stream);
    size_t length = strlen(location);

    /* Remove BDMV/INDEX.BDMV (or the platform-equivalent separator). */
    char *root = strndup(location, length - 15);
    if (root == NULL)
        return VLC_ENOMEM;

    input_item_t *item = input_item_New(root, root);
    if (item == NULL)
    {
        free(root);
        return VLC_ENOMEM;
    }

    input_item_AddOption(item, "demux=bluray", VLC_INPUT_OPTION_TRUSTED);
    input_item_node_AppendItem(node, item);
    input_item_Release(item);
    free(root);
    return VLC_SUCCESS;
}
