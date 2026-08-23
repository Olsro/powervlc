/*****************************************************************************
 * gopher.c: Gopher input module
 *****************************************************************************
 * Copyright (C) 2019-2020 VLC authors
 *
 * Authors: Vincenzo "KatolaZ" Nicosia <katolaz@freaknet.org>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_access.h>
#include <vlc_url.h>
#include <vlc_tls.h>

static ssize_t Read(stream_t *access, void *buffer, size_t length)
{
    return vlc_tls_Read(access->p_sys, buffer, length, false);
}

static int Control(stream_t *access, int query, va_list args)
{
    switch (query)
    {
        case STREAM_CAN_SEEK:
        case STREAM_CAN_FASTSEEK:
            *va_arg(args, bool *) = false;
            return VLC_SUCCESS;

        case STREAM_CAN_PAUSE:
        case STREAM_CAN_CONTROL_PACE:
            *va_arg(args, bool *) = true;
            return VLC_SUCCESS;

        case STREAM_GET_PTS_DELAY:
            *va_arg(args, vlc_tick_t *) = VLC_TICK_FROM_MS(
                var_InheritInteger(access, "network-caching"));
            return VLC_SUCCESS;

        case STREAM_SET_PAUSE_STATE:
            return VLC_SUCCESS;

        default:
            return VLC_EGENERIC;
    }
}

static int Open(vlc_object_t *object)
{
    stream_t *access = (stream_t *)object;
    vlc_url_t url;

    if (vlc_UrlParse(&url, access->psz_url) || url.psz_host == NULL)
    {
        msg_Err(access, "invalid Gopher location: %s", access->psz_location);
        vlc_UrlClean(&url);
        return VLC_EGENERIC;
    }

    unsigned port = url.i_port != 0 ? url.i_port : 70;
    vlc_tls_t *socket = vlc_tls_SocketOpenTCP(object, url.psz_host, port);
    if (socket == NULL)
    {
        msg_Err(access, "cannot connect to %s:%u", url.psz_host, port);
        vlc_UrlClean(&url);
        return VLC_EGENERIC;
    }

    /* RFC 4266: the first path character after '/' is the item type and is
     * not part of the selector sent to the server. */
    const char *selector = "";
    if (url.psz_path != NULL && url.psz_path[0] == '/' &&
        url.psz_path[1] != '\0')
        selector = url.psz_path + 2;

    char *request;
    if (asprintf(&request, "%s\r\n", selector) < 0)
    {
        vlc_UrlClean(&url);
        vlc_tls_SessionDelete(socket);
        return VLC_ENOMEM;
    }
    vlc_UrlClean(&url);

    size_t remaining = strlen(request);
    const char *cursor = request;
    while (remaining > 0)
    {
        ssize_t written = vlc_tls_Write(socket, cursor, remaining);
        if (written <= 0)
        {
            free(request);
            vlc_tls_SessionDelete(socket);
            return VLC_EGENERIC;
        }
        cursor += written;
        remaining -= written;
    }
    free(request);

    access->p_sys = socket;
    access->pf_read = Read;
    access->pf_block = NULL;
    access->pf_control = Control;
    access->pf_seek = NULL;
    return VLC_SUCCESS;
}

static void Close(vlc_object_t *object)
{
    stream_t *access = (stream_t *)object;
    vlc_tls_SessionDelete(access->p_sys);
}

vlc_module_begin()
    set_shortname("Gopher")
    set_description(N_("Gopher input"))
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_ACCESS)
    set_capability("access", 0)
    set_callbacks(Open, Close)
    add_shortcut("gopher")
vlc_module_end()
