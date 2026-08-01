/*****************************************************************************
 * access.c: HTTP/TLS VLC access plug-in
 *****************************************************************************
 * Copyright © 2015 Rémi Denis-Courmont
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

#include <assert.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include <vlc_common.h>
#include <vlc_access.h>
#include <vlc_charset.h>
#include <vlc_input.h>
#include <vlc_keystore.h>
#include <vlc_meta.h>
#include <vlc_plugin.h>
#include <vlc_strings.h>
#include <vlc_url.h>

#include "connmgr.h"
#include "message.h"
#include "resource.h"
#include "file.h"
#include "live.h"

/* Largest SHOUTcast metadata block: the length byte counts 16-byte units. */
#define ICY_META_MAX (255 * 16)

struct access_sys_t
{
    struct vlc_http_mgr *manager;
    struct vlc_http_resource *resource;

    /* SHOUTcast/Icecast in-band metadata de-interleaving. The server splices
     * a metadata block into the byte stream every icy_interval bytes of real
     * payload; those bytes must be stripped before the demuxer sees them. */
    size_t   icy_interval;  /**< payload bytes between blocks, 0 if disabled */
    size_t   icy_remaining; /**< payload bytes left before the next block */
    ssize_t  icy_len;       /**< block bytes expected, -1 if length byte due */
    size_t   icy_offset;    /**< block bytes already gathered */
    char    *icy_title;     /**< last StreamTitle seen, to skip repeats */
    char    *icy_arturl;    /**< last artwork StreamUrl seen, likewise */
    char     icy_buf[ICY_META_MAX + 1];
};

/**
 * Extracts one "Field='value';" entry out of an ICY metadata block.
 *
 * @return heap-allocated UTF-8 value, or NULL if absent or unusable.
 */
static char *IcyExtract(const char *meta, const char *field)
{
    const char *p = strcasestr(meta, field);
    if (p == NULL)
        return NULL;

    p += strlen(field);

    const char *end;
    if (*p == '\'' || *p == '"')
    {   /* Quoted: the value ends at the closing quote followed by ';', with a
         * fallback on the first ';' as some servers do not escape quotes. */
        char closing[] = { p[0], ';', '\0' };

        end = strstr(p + 1, closing);
        if (end == NULL)
            end = strchr(p + 1, ';');
        p++;
    }
    else
        end = strchr(p, ';');

    char *value = (end != NULL) ? strndup(p, end - p) : strdup(p);
    if (unlikely(value == NULL))
        return NULL;

    if (EnsureUTF8(value) == NULL)
    {
        free(value);
        return NULL;
    }
    return value;
}

/** Checks that a StreamUrl actually points at an image. Plenty of stations put
 * their homepage there instead of the current cover, and that must not be
 * mistaken for artwork. */
static bool IcyUrlIsArtwork(const char *url)
{
    static const char *const exts[] = {
        ".jpg", ".jpeg", ".png", ".gif", ".webp", ".bmp",
    };
    size_t len = strlen(url);

    for (size_t i = 0; i < ARRAY_SIZE(exts); i++)
    {
        size_t elen = strlen(exts[i]);

        if (len >= elen && !vlc_ascii_strcasecmp(url + len - elen, exts[i]))
            return true;
    }
    return false;
}

/**
 * Publishes the fields of an ICY metadata block on the input item.
 */
static void IcyParse(stream_t *access, const char *meta)
{
    access_sys_t *sys = access->p_sys;
    input_item_t *item = (access->p_input != NULL)
                       ? input_GetItem(access->p_input) : NULL;

    char *title = IcyExtract(meta, "StreamTitle=");
    if (title != NULL)
    {
        if (sys->icy_title == NULL || strcmp(sys->icy_title, title))
        {   /* Changed: publish it. */
            free(sys->icy_title);
            sys->icy_title = title;
            msg_Dbg(access, "new ICY title: %s", title);

            if (item != NULL)
                input_item_SetMeta(item, vlc_meta_NowPlaying, title);
        }
        else
            free(title); /* unchanged, do not churn the playlist */
    }

    /* The cover of the track being played, when the station provides one. It
     * is the only artwork a radio stream ever carries. */
    char *url = IcyExtract(meta, "StreamUrl=");
    if (url == NULL)
        return;

    if (!IcyUrlIsArtwork(url)
     || (sys->icy_arturl != NULL && !strcmp(sys->icy_arturl, url)))
    {
        free(url);
        return;
    }

    free(sys->icy_arturl);
    sys->icy_arturl = url;
    msg_Dbg(access, "new ICY artwork: %s", url);

    if (item != NULL)
    {
        input_item_SetArtworkURL(item, url);
        /* Art is normally fetched once, when playback starts, i.e. before any
         * metadata block was received. Ask again so the new cover is actually
         * downloaded and shown. */
        libvlc_ArtRequest(access->obj.libvlc, item, META_REQUEST_OPTION_NONE);
    }
}

/**
 * Strips the interleaved ICY metadata blocks out of a freshly read block.
 *
 * Removal only ever shrinks the block, so the payload is compacted in place.
 * A metadata block may straddle two reads, hence the state kept in access_sys.
 */
static void IcyDeinterleave(stream_t *access, block_t *b)
{
    access_sys_t *sys = access->p_sys;
    const uint8_t *in = b->p_buffer;
    uint8_t *out = b->p_buffer;
    size_t left = b->i_buffer;

    while (left > 0)
    {
        if (sys->icy_remaining > 0)
        {   /* Payload */
            size_t n = (left < sys->icy_remaining) ? left : sys->icy_remaining;

            memmove(out, in, n);
            out += n;
            in += n;
            left -= n;
            sys->icy_remaining -= n;
            continue;
        }

        if (sys->icy_len < 0)
        {   /* Length byte, in 16-byte units */
            sys->icy_len = (ssize_t)(*in++) * 16;
            sys->icy_offset = 0;
            left--;

            if (sys->icy_len == 0)
            {   /* Empty block: nothing changed since the previous one */
                sys->icy_len = -1;
                sys->icy_remaining = sys->icy_interval;
            }
            continue;
        }

        /* Metadata payload */
        size_t want = (size_t)sys->icy_len - sys->icy_offset;
        size_t n = (left < want) ? left : want;

        memcpy(sys->icy_buf + sys->icy_offset, in, n);
        sys->icy_offset += n;
        in += n;
        left -= n;

        if (sys->icy_offset == (size_t)sys->icy_len)
        {
            sys->icy_buf[sys->icy_offset] = '\0';
            IcyParse(access, sys->icy_buf);
            sys->icy_len = -1;
            sys->icy_remaining = sys->icy_interval;
        }
    }

    b->i_buffer = out - b->p_buffer;
}

static block_t *FileRead(stream_t *access, bool *restrict eof)
{
    access_sys_t *sys = access->p_sys;

    for (;;)
    {
        block_t *b = vlc_http_file_read(sys->resource);
        if (b == NULL)
        {
            *eof = true;
            return NULL;
        }

        if (sys->icy_interval == 0)
            return b;

        IcyDeinterleave(access, b);
        if (b->i_buffer > 0)
            return b;

        /* The whole read was metadata; fetch actual payload. */
        block_Release(b);
    }
}

static int FileSeek(stream_t *access, uint64_t pos)
{
    access_sys_t *sys = access->p_sys;

    if (vlc_http_file_seek(sys->resource, pos))
        return VLC_EGENERIC;
    return VLC_SUCCESS;
}

static int FileControl(stream_t *access, int query, va_list args)
{
    access_sys_t *sys = access->p_sys;

    switch (query)
    {
        case STREAM_CAN_SEEK:
            /* Byte offsets carry interleaved metadata, so a range request
             * would resume at an unknown point of the ICY framing. */
            *va_arg(args, bool *) = sys->icy_interval == 0
                                 && vlc_http_file_can_seek(sys->resource);
            break;

        case STREAM_CAN_FASTSEEK:
            *va_arg(args, bool *) = false;
            break;

        case STREAM_CAN_PAUSE:
        case STREAM_CAN_CONTROL_PACE:
            *va_arg(args, bool *) = true;
            break;

        case STREAM_GET_SIZE:
        {
            if (sys->icy_interval != 0)
                return VLC_EGENERIC; /* would count the metadata blocks in */

            uintmax_t val = vlc_http_file_get_size(sys->resource);
            if (val >= UINT64_MAX)
                return VLC_EGENERIC;

            *va_arg(args, uint64_t *) = val;
            break;
        }

        case STREAM_GET_PTS_DELAY:
            *va_arg(args, int64_t *) = INT64_C(1000) *
                var_InheritInteger(access, "network-caching");
            break;

        case STREAM_GET_CONTENT_TYPE:
            *va_arg(args, char **) = vlc_http_file_get_type(sys->resource);
            break;

        case STREAM_SET_PAUSE_STATE:
            break;

        default:
            return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

static block_t *LiveRead(stream_t *access, bool *restrict eof)
{
    access_sys_t *sys = access->p_sys;

    for (;;)
    {
        block_t *b = vlc_http_live_read(sys->resource);
        if (b == NULL) /* TODO: loop instead of EOF, see vlc_http_live_read() */
        {
            *eof = true;
            return NULL;
        }

        if (sys->icy_interval == 0)
            return b;

        IcyDeinterleave(access, b);
        if (b->i_buffer > 0)
            return b;

        block_Release(b);
    }
}

static int NoSeek(stream_t *access, uint64_t pos)
{
    (void) access;
    (void) pos;
    return VLC_EGENERIC;
}

static int LiveControl(stream_t *access, int query, va_list args)
{
    access_sys_t *sys = access->p_sys;

    switch (query)
    {
        case STREAM_CAN_SEEK:
        case STREAM_CAN_FASTSEEK:
        case STREAM_CAN_PAUSE:
        case STREAM_CAN_CONTROL_PACE:
            *va_arg(args, bool *) = false;
            break;

        case STREAM_GET_PTS_DELAY:
            *va_arg(args, int64_t *) = INT64_C(1000) *
                var_InheritInteger(access, "network-caching");
            break;

        case STREAM_GET_CONTENT_TYPE:
            *va_arg(args, char **) = vlc_http_live_get_type(sys->resource);
            break;

        default:
            return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

/**
 * Picks up the ICY bits of the response: the interleaving interval, which
 * arms the de-interleaver, plus the station name and genre.
 */
static void IcySetup(stream_t *access, access_sys_t *sys)
{
    const struct vlc_http_msg *resp = sys->resource->response;
    if (resp == NULL)
        return;

    input_item_t *item = (access->p_input != NULL)
                       ? input_GetItem(access->p_input) : NULL;

    const char *str = vlc_http_msg_get_header(resp, "icy-metaint");
    if (str != NULL)
    {
        char *end;
        unsigned long interval = strtoul(str, &end, 10);

        if (end != str && interval > 0 && interval <= SIZE_MAX)
        {
            sys->icy_interval = interval;
            sys->icy_remaining = interval;
            msg_Dbg(access, "ICY metadata interval: %lu bytes", interval);
        }
    }

    if (item == NULL)
        return;

    static const struct
    {
        const char *header;
        vlc_meta_type_t meta;
    } fields[] = {
        { "icy-name",  vlc_meta_Title },
        { "icy-genre", vlc_meta_Genre },
    };

    for (size_t i = 0; i < ARRAY_SIZE(fields); i++)
    {
        str = vlc_http_msg_get_header(resp, fields[i].header);
        if (str == NULL)
            continue;

        char *value = strdup(str);
        if (unlikely(value == NULL))
            continue;

        if (EnsureUTF8(value) != NULL)
        {
            vlc_xml_decode(value);
            msg_Dbg(access, "%s: %s", fields[i].header, value);
            input_item_SetMeta(item, fields[i].meta, value);
        }
        free(value);
    }
}

static int Open(vlc_object_t *obj)
{
    stream_t *access = (stream_t *)obj;
    access_sys_t *sys = malloc(sizeof (*sys));
    int ret = VLC_ENOMEM;

    if (unlikely(sys == NULL))
        return VLC_ENOMEM;

    sys->manager = NULL;
    sys->resource = NULL;
    sys->icy_interval = 0;
    sys->icy_remaining = 0;
    sys->icy_len = -1;
    sys->icy_offset = 0;
    sys->icy_title = NULL;
    sys->icy_arturl = NULL;

    void *jar = NULL;
    if (var_InheritBool(obj, "http-forward-cookies"))
        jar = var_InheritAddress(obj, "http-cookies");

    struct vlc_credential crd;
    struct vlc_url_t crd_url;
    char *psz_realm = NULL;

    vlc_UrlParse(&crd_url, access->psz_url);
    vlc_credential_init(&crd, &crd_url);

    sys->manager = vlc_http_mgr_create(obj, jar);
    if (sys->manager == NULL)
        goto error;

    char *ua = var_InheritString(obj, "http-user-agent");
    char *referer = var_InheritString(obj, "http-referrer");
    bool live = var_InheritBool(obj, "http-continuous");

    sys->resource = (live ? vlc_http_live_create : vlc_http_file_create)(
        sys->manager, access->psz_url, ua, referer);
    free(referer);
    free(ua);

    if (sys->resource == NULL)
        goto error;

    /* Must be set before the request is actually sent, i.e. before the first
     * call querying the response status below. Servers that do not speak ICY
     * ignore the header, so this is unconditional like in the legacy access. */
    sys->resource->icy = true;

    if (vlc_credential_get(&crd, obj, NULL, NULL, NULL, NULL))
        vlc_http_res_set_login(sys->resource,
                               crd.psz_username, crd.psz_password);

    ret = VLC_EGENERIC;

    int status = vlc_http_res_get_status(sys->resource);

    while (status == 401) /* authentication */
    {
        crd.psz_authtype = "Basic";
        free(psz_realm);
        psz_realm = vlc_http_res_get_basic_realm(sys->resource);

        if (psz_realm == NULL)
            break;
        crd.psz_realm = psz_realm;
        if (!vlc_credential_get(&crd, obj, NULL, NULL, _("HTTP authentication"),
                                _("Please enter a valid login name and "
                                  "a password for realm %s."), crd.psz_realm))
            break;

        vlc_http_res_set_login(sys->resource,
                               crd.psz_username, crd.psz_password);
        status = vlc_http_res_get_status(sys->resource);
    }

    if (status < 0)
    {
        msg_Err(access, "HTTP connection failure");
        goto error;
    }

    char *redir = vlc_http_res_get_redirect(sys->resource);
    if (redir != NULL)
    {
        access->psz_url = redir;
        ret = VLC_ACCESS_REDIRECT;
        goto error;
    }

    if (status >= 300)
    {
        msg_Err(access, "HTTP %d error", status);
        goto error;
    }

    vlc_credential_store(&crd, obj);
    free(psz_realm);
    vlc_credential_clean(&crd);
    vlc_UrlClean(&crd_url);

    IcySetup(access, sys);

    access->pf_read = NULL;
    if (live)
    {
        access->pf_block = LiveRead;
        access->pf_seek = NoSeek;
        access->pf_control = LiveControl;
    }
    else
    {
        access->pf_block = FileRead;
        access->pf_seek = FileSeek;
        access->pf_control = FileControl;
    }
    access->p_sys = sys;
    return VLC_SUCCESS;

error:
    if (sys->resource != NULL)
        vlc_http_res_destroy(sys->resource);
    if (sys->manager != NULL)
        vlc_http_mgr_destroy(sys->manager);
    free(psz_realm);
    vlc_credential_clean(&crd);
    vlc_UrlClean(&crd_url);
    free(sys);
    return ret;
}

static void Close(vlc_object_t *obj)
{
    stream_t *access = (stream_t *)obj;
    access_sys_t *sys = access->p_sys;

    vlc_http_res_destroy(sys->resource);
    vlc_http_mgr_destroy(sys->manager);
    free(sys->icy_title);
    free(sys->icy_arturl);
    free(sys);
}

vlc_module_begin()
    set_description(N_("HTTPS input"))
    set_shortname(N_("HTTPS"))
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_ACCESS)
    set_capability("access", 2)
    add_shortcut("https", "http")
    set_callbacks(Open, Close)

    add_bool("http-continuous", false, N_("Continuous stream"),
             N_("Keep reading a resource that keeps being updated."), true)
        change_volatile()
    add_bool("http-forward-cookies", true, N_("Cookies forwarding"),
             N_("Forward cookies across HTTP redirections."), true)
    add_string("http-referrer", NULL, N_("Referrer"),
               N_("Provide the referral URL, i.e. HTTP \"Referer\" (sic)."),
               true)
        change_safe()
        change_volatile()
    add_string("http-user-agent", NULL, N_("User agent"),
               N_("Override the name and version of the application as "
                  "provided to the HTTP server, i.e. the HTTP \"User-Agent\". "
                  "Name and version must be separated by a forward slash, "
                  "e.g. \"FooBar/1.2.3\"."), true)
        change_safe()
        change_private()
vlc_module_end()
