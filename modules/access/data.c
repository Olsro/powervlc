/*****************************************************************************
 * data.c: data URI access module
 *****************************************************************************
 * Copyright (C) 2021 VLC authors and VideoLAN
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

#include <assert.h>
#include <errno.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_access.h>
#include <vlc_strings.h>
#include <vlc_url.h>

/* Keep malformed or hostile playlist entries from allocating unbounded RAM. */
#define DATA_URI_MAX_SIZE (64u * 1024u * 1024u)

struct access_sys_t
{
    size_t type_offset;
    size_t type_length;
    size_t length;
    size_t offset;
    uint8_t *data;
};

static ssize_t Read(stream_t *access, void *buffer, size_t length)
{
    access_sys_t *sys = access->p_sys;
    size_t available = sys->length - sys->offset;

    assert(sys->offset <= sys->length);
    if (length > available)
        length = available;

    memcpy(buffer, sys->data + sys->offset, length);
    sys->offset += length;
    return length;
}

static int Seek(stream_t *access, uint64_t position)
{
    access_sys_t *sys = access->p_sys;
    sys->offset = position <= sys->length ? position : sys->length;
    return VLC_SUCCESS;
}

static int Control(stream_t *access, int query, va_list args)
{
    access_sys_t *sys = access->p_sys;

    switch (query)
    {
        case STREAM_CAN_SEEK:
        case STREAM_CAN_FASTSEEK:
        case STREAM_CAN_PAUSE:
        case STREAM_CAN_CONTROL_PACE:
            *va_arg(args, bool *) = true;
            return VLC_SUCCESS;

        case STREAM_GET_SIZE:
            *va_arg(args, uint64_t *) = sys->length;
            return VLC_SUCCESS;

        case STREAM_GET_PTS_DELAY:
            *va_arg(args, vlc_tick_t *) = DEFAULT_PTS_DELAY;
            return VLC_SUCCESS;

        case STREAM_GET_CONTENT_TYPE:
        {
            const char *type = access->psz_url + 5 + sys->type_offset;
            char *copy = sys->type_length > 0
                       ? strndup(type, sys->type_length)
                       : strdup("text/plain;charset=US-ASCII");
            *va_arg(args, char **) = copy;
            return copy != NULL ? VLC_SUCCESS : VLC_ENOMEM;
        }

        case STREAM_SET_PAUSE_STATE:
            return VLC_SUCCESS;

        default:
            return VLC_EGENERIC;
    }
}

static int Open(vlc_object_t *object)
{
    stream_t *access = (stream_t *)object;
    const char *url = access->psz_url;

    if (url == NULL || strncmp(url, "data:", 5) != 0)
        return VLC_EGENERIC;
    url += 5;

    /* VLC 3's command-line MRL normalizer recognizes schemes through ://.
     * Accept that spelling too, while keeping RFC 2397 data: URIs intact. */
    size_t type_offset = 0;
    if (url[0] == '/' && url[1] == '/')
    {
        url += 2;
        type_offset = 2;
    }

    const char *separator = strchr(url, ',');
    if (separator == NULL)
    {
        msg_Err(access, "invalid data URI: missing comma");
        return VLC_EGENERIC;
    }

    bool base64 = separator - url >= 7 &&
                  memcmp(separator - 7, ";base64", 7) == 0;
    size_t encoded_length = strlen(separator + 1);
    size_t encoded_limit = base64 ? (DATA_URI_MAX_SIZE * 4u / 3u + 4u)
                                  : (DATA_URI_MAX_SIZE * 3u);
    if (encoded_length > encoded_limit)
    {
        msg_Err(access, "data URI exceeds the %u MiB limit",
                DATA_URI_MAX_SIZE / 1024u / 1024u);
        return VLC_EGENERIC;
    }

    access_sys_t *sys = vlc_obj_malloc(object, sizeof(*sys));
    if (unlikely(sys == NULL))
        return VLC_ENOMEM;

    char *decoded = vlc_uri_decode_duplicate(separator + 1);
    if (decoded == NULL)
        return errno == ENOMEM ? VLC_ENOMEM : VLC_EGENERIC;

    sys->type_length = separator - url - (base64 ? 7 : 0);
    sys->type_offset = type_offset;
    sys->offset = 0;

    if (base64)
    {
        size_t input_length = strlen(decoded);
        size_t capacity = input_length - input_length / 4u + 1u;
        uint8_t *binary = malloc(capacity);
        if (unlikely(binary == NULL))
        {
            free(decoded);
            return VLC_ENOMEM;
        }

        sys->length = vlc_b64_decode_binary_to_buffer(binary, capacity,
                                                       decoded);
        free(decoded);
        sys->data = binary;
    }
    else
    {
        sys->length = strlen(decoded);
        sys->data = (uint8_t *)decoded;
    }

    if (sys->length > DATA_URI_MAX_SIZE)
    {
        free(sys->data);
        return VLC_EGENERIC;
    }

    access->p_sys = sys;
    access->pf_read = Read;
    access->pf_block = NULL;
    access->pf_seek = Seek;
    access->pf_control = Control;
    return VLC_SUCCESS;
}

static void Close(vlc_object_t *object)
{
    stream_t *access = (stream_t *)object;
    access_sys_t *sys = access->p_sys;
    free(sys->data);
}

vlc_module_begin()
    set_shortname(N_("data"))
    set_description(N_("data URI scheme"))
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_ACCESS)
    set_capability("access", 0)
    set_callbacks(Open, Close)
    add_shortcut("data")
vlc_module_end()
