/*****************************************************************************
 * afp.c: Apple Filing Protocol access plug-in
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 ******************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#include <vlc_common.h>
#include <vlc_access.h>
#include <vlc_dialog.h>
#include <vlc_input_item.h>
#include <vlc_keystore.h>
#include <vlc_plugin.h>
#include <vlc_url.h>

#include <afp.h>
#include <libafpclient.h>
#include <midlevel.h>

static int Open(vlc_object_t *);
static void Close(vlc_object_t *);

vlc_module_begin()
    set_shortname("AFP")
    set_description(N_("Apple Filing Protocol input"))
    set_help(N_("Browse and play files on AFP servers with Netatalk Client"))
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_ACCESS)
    set_capability("access", 20)
    add_shortcut("afp")
    set_callbacks(Open, Close)
vlc_module_end()

struct access_sys_t
{
    struct afp_url url;
    struct afp_server *server;
    struct afp_volume *volume;
    struct afp_file_info *file;
    struct afp_file_info *entries;
    vlc_url_t encoded_url;
    uint64_t offset;
    uint64_t size;
    bool eof;
    bool server_root;
};

static vlc_mutex_t afp_init_lock = VLC_STATIC_MUTEX;
static bool afp_initialized;
static int afp_init_result = VLC_EGENERIC;

static void AFPLog(void *opaque, enum logtypes type, int level,
                   const char *message)
{
    VLC_UNUSED(opaque);
    VLC_UNUSED(type);
    VLC_UNUSED(level);
    VLC_UNUSED(message);
}

static struct libafpclient afp_client = {
    .unmount_volume = NULL,
    .log_for_client = AFPLog,
    .forced_ending_hook = NULL,
    .scan_extra_fds = NULL,
    .loop_started = NULL,
};

static int AFPInit(void)
{
    vlc_mutex_lock(&afp_init_lock);
    if (!afp_initialized)
    {
#ifndef _WIN32
        struct sigaction old_int, old_term;
        sigaction(SIGINT, NULL, &old_int);
        sigaction(SIGTERM, NULL, &old_term);
#endif

        libafpclient_register(&afp_client);
        if (afp_main_quick_startup(NULL) == 0)
        {
            afp_wait_for_started_loop();
            if (init_uams() == 0)
                afp_init_result = VLC_SUCCESS;
        }

        /* libafpclient's loop installs process-wide shutdown handlers. VLC
         * owns those signals, so restore the handlers after the loop starts. */
#ifndef _WIN32
        sigaction(SIGINT, &old_int, NULL);
        sigaction(SIGTERM, &old_term, NULL);
#endif
        afp_initialized = true;
    }
    int ret = afp_init_result;
    vlc_mutex_unlock(&afp_init_lock);
    return ret;
}

static int AFPControl(stream_t *access, int query, va_list args)
{
    access_sys_t *sys = access->p_sys;

    switch (query)
    {
        case STREAM_CAN_SEEK:
            *va_arg(args, bool *) = true;
            break;
        case STREAM_CAN_FASTSEEK:
            *va_arg(args, bool *) = false;
            break;
        case STREAM_CAN_PAUSE:
        case STREAM_CAN_CONTROL_PACE:
            *va_arg(args, bool *) = true;
            break;
        case STREAM_GET_SIZE:
            *va_arg(args, uint64_t *) = sys->size;
            break;
        case STREAM_GET_PTS_DELAY:
            *va_arg(args, int64_t *) =
                var_InheritInteger(access, "network-caching") * 1000;
            break;
        case STREAM_SET_PAUSE_STATE:
            break;
        default:
            return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

static ssize_t AFPRead(stream_t *access, void *buffer, size_t length)
{
    access_sys_t *sys = access->p_sys;
    if (sys->eof)
        return 0;

    if (length > INT_MAX)
        length = INT_MAX;

    int eof = 0;
    int ret = ml_read(sys->volume, sys->url.path, buffer, length,
                      (off_t)sys->offset, sys->file, &eof);
    if (ret < 0)
    {
        msg_Err(access, "AFP read failed: %s", vlc_strerror_c(-ret));
        return -1;
    }

    sys->offset += (uint64_t)ret;
    sys->eof = eof != 0 || ret == 0;
    return ret;
}

static int AFPSeek(stream_t *access, uint64_t position)
{
    access_sys_t *sys = access->p_sys;
    sys->offset = position;
    sys->eof = false;
    return VLC_SUCCESS;
}

static char *AFPChildURL(access_sys_t *sys, const char *name,
                         bool directory)
{
    char *encoded = vlc_uri_encode(name);
    if (encoded == NULL)
        return NULL;

    const char *base = sys->encoded_url.psz_path;
    size_t base_len = base != NULL ? strlen(base) : 0;
    bool slash = base_len > 0 && base[base_len - 1] != '/';
    char *path;
    if (asprintf(&path, "%s%s%s%s", base_len ? base : "/",
                 slash ? "/" : "", encoded, directory ? "/" : "") < 0)
        path = NULL;
    free(encoded);
    if (path == NULL)
        return NULL;

    vlc_url_t child = sys->encoded_url;
    child.psz_path = path;
    /* Credentials are kept in VLC's in-memory keystore after a successful
     * connection.  Do not copy URL userinfo to children: apart from leaking
     * secrets into every playlist item, stale credentials (after a successful
     * retry) would otherwise be tried again for each directory level. */
    child.psz_username = NULL;
    child.psz_password = NULL;
    char *url = vlc_uri_compose(&child);
    free(path);
    return url;
}

static int AFPDirRead(stream_t *access, input_item_node_t *node)
{
    access_sys_t *sys = access->p_sys;
    struct vlc_readdir_helper rdh;
    vlc_readdir_helper_init(&rdh, access, node);
    int ret = VLC_SUCCESS;

    if (sys->server_root)
    {
        for (unsigned int i = 0; i < sys->server->num_volumes
             && ret == VLC_SUCCESS; ++i)
        {
            const char *name = sys->server->volumes[i].volume_name_printable;
            char *url = AFPChildURL(sys, name, true);
            if (url == NULL)
            {
                ret = VLC_ENOMEM;
                break;
            }
            ret = vlc_readdir_helper_additem(&rdh, url, NULL, name,
                                              ITEM_TYPE_DIRECTORY, ITEM_NET);
            free(url);
        }
    }
    else
    {
        for (struct afp_file_info *entry = sys->entries;
             entry != NULL && ret == VLC_SUCCESS; entry = entry->next)
        {
            if (!strcmp(entry->name, ".") || !strcmp(entry->name, ".."))
                continue;
            char *url = AFPChildURL(sys, entry->name, entry->isdir != 0);
            if (url == NULL)
            {
                ret = VLC_ENOMEM;
                break;
            }
            ret = vlc_readdir_helper_additem(&rdh, url, NULL, entry->name,
                entry->isdir ? ITEM_TYPE_DIRECTORY : ITEM_TYPE_FILE, ITEM_NET);
            free(url);
        }
    }

    vlc_readdir_helper_finish(&rdh, ret == VLC_SUCCESS);
    return ret;
}

static int AFPConnect(stream_t *access)
{
    access_sys_t *sys = access->p_sys;
    struct afp_connection_request request;
    memset(&request, 0, sizeof(request));
    request.url = sys->url;
    request.uam_mask = sys->url.uamname[0] != '\0'
        ? find_uam_by_name(sys->url.uamname) : default_uams_mask();

    errno = 0;
    sys->server = afp_server_full_connect(access, &request);
    if (sys->server == NULL)
    {
        int error = errno != 0 ? errno : EIO;
        msg_Err(access, "could not connect or authenticate to AFP server %s: %s",
                sys->url.servername, vlc_strerror_c(error));
        return -error;
    }
    return VLC_SUCCESS;
}

static int AFPSetCredentials(stream_t *access,
                             const vlc_credential *credential)
{
    access_sys_t *sys = access->p_sys;
    const char *username = credential->psz_username;
    const char *password = credential->psz_password;

    if (username == NULL || password == NULL)
        return VLC_EGENERIC;
    if (strlen(username) >= sizeof(sys->url.username)
     || strlen(password) >= sizeof(sys->url.password))
    {
        msg_Err(access, "AFP username or password is too long");
        return VLC_EGENERIC;
    }

    strcpy(sys->url.username, username);
    strcpy(sys->url.password, password);
    return VLC_SUCCESS;
}

static int Open(vlc_object_t *obj)
{
    stream_t *access = (stream_t *)obj;
    access_sys_t *sys = vlc_obj_calloc(obj, 1, sizeof(*sys));
    if (unlikely(sys == NULL))
        return VLC_ENOMEM;
    access->p_sys = sys;

    if (AFPInit() != VLC_SUCCESS)
    {
        msg_Err(access, "could not initialize Netatalk Client");
        return VLC_EGENERIC;
    }

    afp_default_url(&sys->url);
    if (afp_parse_url(&sys->url, access->psz_url) != 0
     || vlc_UrlParseFixup(&sys->encoded_url, access->psz_url) != 0)
        goto error;

    /* libafpclient parses the URI structure but deliberately keeps percent
     * escapes intact.  VLC directory items use standard URI escaping, so
     * decode the fields that are sent to the AFP server. */
    if (vlc_uri_decode(sys->url.username) == NULL
     || vlc_uri_decode(sys->url.password) == NULL
     || vlc_uri_decode(sys->url.volumename) == NULL
     || vlc_uri_decode(sys->url.path) == NULL)
        goto error;

    vlc_credential credential;
    vlc_credential_init(&credential, &sys->encoded_url);

    bool connected = false;
    bool have_credentials = vlc_credential_get(&credential, access, NULL,
                                                NULL, NULL, NULL);
    while (!connected)
    {
        if (!have_credentials)
            have_credentials = vlc_credential_get(&credential, access, NULL,
                NULL, _("AFP authentication"),
                _("Please enter a valid login and password for the AFP "
                  "connection to %s."), sys->encoded_url.psz_host);
        if (!have_credentials)
            break;

        if (AFPSetCredentials(access, &credential) != VLC_SUCCESS)
            break;

        int connect_result = AFPConnect(access);
        if (connect_result == VLC_SUCCESS)
        {
            connected = true;
            vlc_credential_store(&credential, access);
            break;
        }
        if (connect_result != -EACCES)
            break;
        have_credentials = false;
    }
    vlc_credential_clean(&credential);

    if (!connected)
    {
        vlc_dialog_display_error(access, _("AFP connection failed"),
            _("PowerVLC could not connect to the AFP server. Check the "
              "server address and credentials."));
        goto error;
    }

    if (sys->url.volumename[0] == '\0')
    {
        sys->server_root = true;
        access->pf_readdir = AFPDirRead;
        access->pf_control = access_vaDirectoryControlHelper;
        return VLC_SUCCESS;
    }

    sys->volume = find_volume_by_name(sys->server, sys->url.volumename);
    if (sys->volume == NULL)
    {
        msg_Err(access, "AFP volume '%s' was not found", sys->url.volumename);
        goto error;
    }

    sys->volume->extra_flags |= VOLUME_EXTRA_FLAGS_NO_LOCKING
                              | VOLUME_EXTRA_FLAGS_IGNORE_UNIXPRIVS;
    afp_detect_mapping(sys->volume);
    char message[MAX_ERROR_LEN] = "";
    unsigned int message_len = 0;
    if (afp_connect_volume(sys->volume, sys->server, message, &message_len,
                           sizeof(message)) != 0)
    {
        msg_Err(access, "could not open AFP volume '%s': %s",
                sys->url.volumename, message);
        goto error;
    }

    const char *path = sys->url.path[0] != '\0' ? sys->url.path : "/";

    /* A volume root is known to be a directory.  Some AFP servers reject
     * FPGetFileDirParms for the root while accepting FPEnumerate, so do not
     * make successful browsing depend on a redundant root stat. */
    if (!strcmp(path, "/"))
    {
        int ret = ml_readdir(sys->volume, path, &sys->entries);
        if (ret < 0)
        {
            msg_Err(access, "could not list AFP volume root: %s",
                    vlc_strerror_c(-ret));
            goto error;
        }
        access->pf_readdir = AFPDirRead;
        access->pf_control = access_vaDirectoryControlHelper;
        return VLC_SUCCESS;
    }

    struct stat st;
    int ret = ml_getattr(sys->volume, path, &st);
    if (ret < 0)
    {
        msg_Err(access, "could not stat AFP path '%s': %s", path,
                vlc_strerror_c(-ret));
        goto error;
    }

    if (S_ISDIR(st.st_mode))
    {
        ret = ml_readdir(sys->volume, path, &sys->entries);
        if (ret < 0)
        {
            msg_Err(access, "could not list AFP directory '%s': %s", path,
                    vlc_strerror_c(-ret));
            goto error;
        }
        access->pf_readdir = AFPDirRead;
        access->pf_control = access_vaDirectoryControlHelper;
    }
    else if (S_ISREG(st.st_mode))
    {
        ret = ml_open(sys->volume, path, O_RDONLY, &sys->file);
        if (ret < 0)
        {
            msg_Err(access, "could not open AFP file '%s': %s", path,
                    vlc_strerror_c(-ret));
            goto error;
        }
        sys->size = st.st_size;
        access->pf_read = AFPRead;
        access->pf_seek = AFPSeek;
        access->pf_control = AFPControl;
    }
    else
        goto error;

    return VLC_SUCCESS;

error:
    Close(obj);
    return VLC_EGENERIC;
}

static void Close(vlc_object_t *obj)
{
    stream_t *access = (stream_t *)obj;
    access_sys_t *sys = access->p_sys;
    if (sys == NULL)
        return;

    if (sys->file != NULL)
    {
        ml_close(sys->volume, sys->url.path, sys->file);
        free(sys->file);
    }
    if (sys->entries != NULL)
        afp_ml_filebase_free(&sys->entries);

    if (sys->volume != NULL && sys->volume->attached == AFP_VOLUME_ATTACHED)
    {
        afp_detach_volume(sys->volume);
        sys->server = NULL; /* detach removes the final server connection */
    }
    if (sys->server != NULL)
        afp_server_remove(sys->server);

    vlc_UrlClean(&sys->encoded_url);
}
