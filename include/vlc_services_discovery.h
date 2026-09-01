/*****************************************************************************
 * vlc_services_discovery.h : Services Discover functions
 *****************************************************************************
 * Copyright (C) 1999-2004 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan.org>
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

#ifndef VLC_SERVICES_DISCOVERY_H_
#define VLC_SERVICES_DISCOVERY_H_

#include <vlc_input.h>
#include <vlc_probe.h>

/**
 * \file
 * This file lists functions and structures for service discovery (SD) in vlc
 */

# ifdef __cplusplus
extern "C" {
# endif

/**
 * @{
 */

struct services_discovery_owner_t
{
    void *sys; /**< Private data for the owner callbacks */
    void (*item_added)(struct services_discovery_t *sd, input_item_t *parent,
                       input_item_t *item, const char *category);
    void (*item_removed)(struct services_discovery_t *sd, input_item_t *item);
    void (*item_tree_added)(struct services_discovery_t *sd,
                            input_item_t *parent, input_item_node_t *tree);
};

/**
 * Main service discovery structure to build a SD module
 */
struct services_discovery_t
{
    VLC_COMMON_MEMBERS
    module_t *          p_module;             /**< Loaded module */

    char *psz_name;                           /**< Main name of the SD */
    config_chain_t *p_cfg;                    /**< Configuration for the SD */

    const char *description; /**< Human-readable name */

    /** Control function
     * \see services_discovery_command_e
     */
    int ( *pf_control ) ( services_discovery_t *, int, va_list );

    services_discovery_sys_t *p_sys;          /**< Custom private data */

    struct services_discovery_owner_t owner; /**< Owner callbacks */
};

/**
 * Service discovery categories
 * \see vlc_sd_probe_Add
 */
enum services_discovery_category_e
{
    SD_CAT_DEVICES = 1,           /**< Devices, like portable music players */
    SD_CAT_LAN,                   /**< LAN/WAN services, like Upnp or SAP */
    SD_CAT_INTERNET,              /**< Internet or Website channels services */
    SD_CAT_MYCOMPUTER             /**< Computer services, like Discs or Apps */
};

/**
 * Service discovery control commands
 */
enum services_discovery_command_e
{
    SD_CMD_SEARCH = 1,          /**< arg1 = query */
    SD_CMD_DESCRIPTOR,          /**< arg1 = services_discovery_descriptor_t* */

    /* PowerVLC lightweight media-library extensions.  Kept on the service
     * discovery API so every interface (Qt and both Cocoa interfaces) can
     * drive the same background engine without depending on a GUI toolkit. */
    SD_CMD_POWERVLC_RESCAN,     /**< no argument */
    SD_CMD_POWERVLC_IMPORT,     /**< arg1 = services_discovery_import_t* */
    SD_CMD_POWERVLC_SET_RATING, /**< arg1 = services_discovery_rating_t* */
    SD_CMD_POWERVLC_SET_RATINGS,/**< arg1 = services_discovery_ratings_t* */
    SD_CMD_POWERVLC_DEVICE_RESERVED, /**< unused; preserves command ABI */
    SD_CMD_POWERVLC_DEVICE_ADD, /**< arg1 = services_discovery_import_t* */
    SD_CMD_POWERVLC_DEVICE_BACKUP, /**< arg1 = destination directory */
    SD_CMD_POWERVLC_DEVICE_TRANSFERS, /**< arg1 = services_discovery_transfer_status_t* */
    SD_CMD_POWERVLC_DEVICE_CANCEL_TRANSFER, /**< arg1 = services_discovery_transfer_cancel_t* */
    SD_CMD_POWERVLC_DEVICE_CANCEL_ALL, /**< no argument */
    SD_CMD_POWERVLC_DEVICE_RESOLVE_DELETE, /**< arg1 = services_discovery_device_delete_resolve_t* */
    SD_CMD_POWERVLC_DEVICE_DELETE, /**< arg1 = services_discovery_device_delete_t* */
    SD_CMD_POWERVLC_DEVICE_COMMIT, /**< commit pending portable-player changes */
    SD_CMD_POWERVLC_DEVICE_DISCARD, /**< discard pending portable-player changes */
    SD_CMD_POWERVLC_PLAYLIST_CREATE, /**< arg1 = services_discovery_playlist_create_t* */
    SD_CMD_POWERVLC_PLAYLIST_RENAME, /**< arg1 = services_discovery_playlist_rename_t* */
    SD_CMD_POWERVLC_PLAYLIST_DELETE, /**< arg1 = services_discovery_playlist_item_t* */
    SD_CMD_POWERVLC_PLAYLIST_DROP, /**< arg1 = services_discovery_playlist_drop_t* */
    SD_CMD_POWERVLC_PLAYLIST_REMOVE, /**< arg1 = services_discovery_playlist_remove_t* */
    SD_CMD_POWERVLC_LIBRARY_SEARCH, /**< arg1 = services_discovery_library_search_t* */
    SD_CMD_POWERVLC_LIBRARY_RELOAD_SMART /**< reload smart playlists; no scan */
};

/** Metadata supplied when an interface imports media into the PowerVLC
 * auto-managed library. All values are borrowed for the duration of the
 * control call. p_item is optional and preserves input options (notably an
 * Audio-CD track's sector range) when the source is not a regular file. */
typedef struct services_discovery_import_t
{
    const char *psz_path;
    const char *psz_title;
    const char *psz_artist;
    const char *psz_album;
    input_item_t *p_item;
} services_discovery_import_t;

/** User rating stored by the PowerVLC media library. A zero rating clears it. */
typedef struct services_discovery_rating_t
{
    const char *psz_path;
    unsigned i_rating;          /**< 0 (unrated) through 5 stars */
} services_discovery_rating_t;

/** Batch rating update. Paths are borrowed for the duration of the call. */
typedef struct services_discovery_ratings_t
{
    const char *const *ppsz_paths;
    size_t i_count;
    unsigned i_rating;          /**< 0 (unrated) through 5 stars */
} services_discovery_ratings_t;

/** Persistent playlists shown inside the PowerVLC media library. Playlist
 * item ids are valid for the duration of a control call only. */
typedef struct services_discovery_playlist_create_t
{
    int i_parent_id;             /**< Playlists root or playlist-folder id */
    const char *psz_name;
    bool b_folder;               /**< false creates a playlist */
} services_discovery_playlist_create_t;

typedef struct services_discovery_playlist_rename_t
{
    int i_item_id;
    const char *psz_name;
} services_discovery_playlist_rename_t;

typedef struct services_discovery_playlist_item_t
{
    int i_item_id;
} services_discovery_playlist_item_t;

typedef struct services_discovery_playlist_drop_t
{
    int i_parent_id;             /**< target folder or playlist */
    int i_index;                 /**< insertion position, -1 appends */
    size_t i_count;
    const int *p_item_ids;
    bool b_copy;                 /**< copy media; move playlist objects */
} services_discovery_playlist_drop_t;

typedef struct services_discovery_playlist_remove_t
{
    int i_parent_id;
    size_t i_count;
    const int *p_item_ids;
} services_discovery_playlist_remove_t;

/* The order mirrors the nine music categories exposed by the PowerVLC
 * library service.  A search returns the lazy index buckets which can
 * contain matches, allowing interfaces to load only those local XSPF files
 * instead of recursively opening the complete library. */
#define SD_POWERVLC_LIBRARY_VIEW_COUNT 9
typedef struct services_discovery_library_match_t
{
    unsigned i_view;
    unsigned i_bucket;
    char *psz_primary;
    char *psz_secondary;
} services_discovery_library_match_t;

typedef struct services_discovery_library_search_t
{
    const char *psz_query;
    uint64_t i_view_mask;
    uint64_t p_bucket_masks[SD_POWERVLC_LIBRARY_VIEW_COUNT];
    /* Exact lazy branches containing matches. The caller owns the array and
     * both strings in every entry. This prevents interfaces from opening an
     * entire letter (potentially thousands of rows) merely to find one
     * matching album. */
    size_t i_match_count;
    services_discovery_library_match_t *p_matches;
} services_discovery_library_search_t;

/** Current step of a portable-player transfer. */
typedef enum services_discovery_transfer_stage_e
{
    SD_TRANSFER_QUEUED = 0,
    SD_TRANSFER_COPYING,
    SD_TRANSFER_TRANSCODING,
    SD_TRANSFER_COMPLETED,
    SD_TRANSFER_FAILED,
    SD_TRANSFER_CANCELLED,
} services_discovery_transfer_stage_e;

/** One entry in the session transfer history. Strings are allocated by the
 * service and must be freed by the caller together with the item array. */
typedef struct services_discovery_transfer_item_t
{
    char *psz_source;
    char *psz_destination;
    uint64_t i_id; /**< stable session identifier used for cancellation */
    services_discovery_transfer_stage_e i_stage;
    unsigned i_progress; /**< exact integer percentage, 0 through 100 */
    bool b_cancel_requested; /**< internal state, also useful to interfaces */
} services_discovery_transfer_item_t;

/** Snapshot returned by SD_CMD_POWERVLC_DEVICE_TRANSFERS. The caller owns
 * p_items and both strings in every item. */
typedef struct services_discovery_transfer_status_t
{
    bool b_synchronizing;
    bool b_pending_changes;
    /** The last requested database validation failed. Pending edits are kept
     * in memory so that the user can reconnect the player and retry. */
    bool b_commit_failed;
    size_t i_count;
    services_discovery_transfer_item_t *p_items;
    unsigned i_activity;
    uint64_t i_total_bytes;
    uint64_t i_free_bytes;
} services_discovery_transfer_status_t;

enum
{
    SD_DEVICE_IDLE = 0,
    SD_DEVICE_LOADING_CONTENTS,
    SD_DEVICE_LOADING_ITUNESDB,
    SD_DEVICE_UPDATING_ITUNESDB,
    SD_DEVICE_DELETING,
};

typedef struct services_discovery_device_delete_t
{
    const char *const *ppsz_paths;
    size_t i_count;
    const int *p_item_ids;       /**< selected tree nodes, optional */
    size_t i_item_count;
} services_discovery_device_delete_t;

/** Resolve selected device-tree rows to physical media paths.  This expands
 * PowerVLC's local lazy index without materialising thousands of outline
 * rows or touching the portable player.  The caller owns every returned
 * string and the array. */
typedef struct services_discovery_device_delete_resolve_t
{
    const int *p_item_ids;
    size_t i_item_count;
    char **ppsz_paths;
    size_t i_count;
} services_discovery_device_delete_resolve_t;

typedef struct services_discovery_transfer_cancel_t
{
    uint64_t i_id;
} services_discovery_transfer_cancel_t;

/**
 * Service discovery capabilities
 */
enum services_discovery_capability_e
{
    SD_CAP_SEARCH = 1           /**< One can search in the SD */
};

/**
 * Service discovery descriptor
 * \see services_discovery_command_e
 */
typedef struct
{
    char *psz_short_desc;       /**< The short description, human-readable */
    char *psz_icon_url;         /**< URL to the icon that represents it */
    char *psz_url;              /**< URL for the service */
    int   i_capabilities;       /**< \see services_discovery_capability_e */
} services_discovery_descriptor_t;


/***********************************************************************
 * Service Discovery
 ***********************************************************************/

/**
 * Ask for a research in the SD
 * @param p_sd: the Service Discovery
 * @param i_control: the command to issue
 * @param args: the argument list
 * @return VLC_SUCCESS in case of success, the error code overwise
 */
static inline int vlc_sd_control( services_discovery_t *p_sd, int i_control, va_list args )
{
    if( p_sd->pf_control )
        return p_sd->pf_control( p_sd, i_control, args );
    else
        return VLC_EGENERIC;
}

/* Get the services discovery modules names to use in Create(), in a null
 * terminated string array. Array and string must be freed after use. */
VLC_API char ** vlc_sd_GetNames( vlc_object_t *, char ***, int ** ) VLC_USED;
#define vlc_sd_GetNames(obj, pln, pcat ) \
        vlc_sd_GetNames(VLC_OBJECT(obj), pln, pcat)

/**
 * Creates a services discoverer.
 */
VLC_API services_discovery_t *vlc_sd_Create(vlc_object_t *parent,
    const char *chain, const struct services_discovery_owner_t *owner)
VLC_USED;

VLC_API void vlc_sd_Destroy( services_discovery_t * );

/**
 * Added top-level service callback.
 *
 * This is a convenience wrapper for services_discovery_AddSubItem().
 * It covers the most comomn case wherby the added item is a top-level service,
 * i.e. it has no parent node.
 */
static inline void services_discovery_AddItem(services_discovery_t *sd,
                                              input_item_t *item)
{
    sd->owner.item_added(sd, NULL, item, NULL);
}

/**
 * Added service callback.
 *
 * A services discovery module invokes this function when it "discovers" a new
 * service, i.e. a new input item.
 *
 * @note This callback does not take ownership of the input item; it might
 * however (and most probably will) add one of more references to the item.
 *
 * The caller is responsible for releasing its own reference(s) eventually.
 * Keeping a reference is necessary to call services_discovery_RemoveItem() or
 * to alter the item later. However, if the caller will never remove nor alter
 * the item, it can drop its reference(s) immediately.
 *
 * @param sd services discoverer / services discovery module instance
 * @param item input item to add
 */
static inline void services_discovery_AddSubItem(services_discovery_t *sd,
                                                 input_item_t *parent,
                                                 input_item_t *item)
{
    sd->owner.item_added(sd, parent, item, NULL);
}

static inline void services_discovery_AddItemTreeFallback(
    services_discovery_t *sd, input_item_t *parent, input_item_node_t *tree)
{
    for (int i = 0; i < tree->i_children; ++i)
    {
        input_item_node_t *child = tree->pp_children[i];
        sd->owner.item_added(sd, parent, child->p_item, NULL);
        services_discovery_AddItemTreeFallback(sd, child->p_item, child);
    }
}

/** Adds a complete input tree in one owner transaction. */
static inline void services_discovery_AddItemTree(services_discovery_t *sd,
                                                  input_item_t *parent,
                                                  input_item_node_t *tree)
{
    if (sd->owner.item_tree_added != NULL)
        sd->owner.item_tree_added(sd, parent, tree);
    else
        services_discovery_AddItemTreeFallback(sd, parent, tree);
}

/**
 * Added service backward compatibility callback.
 *
 * @param category Optional name of a group that the item belongs in
 *                 (for backward compatibility with legacy modules)
 */
VLC_DEPRECATED
static inline void services_discovery_AddItemCat(services_discovery_t *sd,
                                                 input_item_t *item,
                                                 const char *category)
{
    sd->owner.item_added(sd, NULL, item, category);
}

/**
 * Removed service callback.
 *
 * A services discovery module invokes this function when it senses that a
 * service is no longer available.
 */
static inline void services_discovery_RemoveItem(services_discovery_t *sd,
                                                 input_item_t *item)
{
    sd->owner.item_removed(sd, item);
}

/* SD probing */

VLC_API int vlc_sd_probe_Add(vlc_probe_t *, const char *, const char *, int category);

#define VLC_SD_PROBE_SUBMODULE \
    add_submodule() \
        set_capability( "services probe", 100 ) \
        set_callbacks( vlc_sd_probe_Open, NULL )

#define VLC_SD_PROBE_HELPER(name, longname, cat) \
static int vlc_sd_probe_Open (vlc_object_t *obj) \
{ \
    return vlc_sd_probe_Add ((struct vlc_probe_t *)obj, name, \
                             longname, cat); \
}

/** @} */
# ifdef __cplusplus
}
# endif

#endif
