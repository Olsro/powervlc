/*****************************************************************************
 * dovi_display.c: native Windows Dolby Vision display transport
 *
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

/* DisplayConfig was added in Windows 7. Expose its declarations to this
 * translation unit without raising PowerVLC's Vista runtime floor: every
 * entry point is still looked up dynamically below. */
#if _WIN32_WINNT < 0x0601
# undef _WIN32_WINNT
# define _WIN32_WINNT 0x0601
#endif
#if WINVER < 0x0601
# undef WINVER
# define WINVER 0x0601
#endif

#include <vlc_common.h>

#include <windows.h>
#include <wingdi.h>

#include "dovi_display.h"

/* Windows' own display settings handler uses these packets to select between
 * the HDR10 and Dolby Vision scan-out modes. They deliberately remain local:
 * older Windows builds and drivers reject unknown packets without changing
 * the display, which gives us a capability probe and a safe fallback. */
#define DISPLAYCONFIG_GET_DOLBY_VISION_STATE ((DISPLAYCONFIG_DEVICE_INFO_TYPE)-44)
#define DISPLAYCONFIG_SET_DOLBY_VISION_STATE ((DISPLAYCONFIG_DEVICE_INFO_TYPE)-43)
#define DISPLAYCONFIG_GET_ADVANCED_COLOR     ((DISPLAYCONFIG_DEVICE_INFO_TYPE)9)
#define DISPLAYCONFIG_SET_ADVANCED_COLOR     ((DISPLAYCONFIG_DEVICE_INFO_TYPE)10)

#define WIN32_ADVANCED_COLOR_SUPPORTED 0x1u
#define WIN32_ADVANCED_COLOR_ENABLED   0x2u
#define WIN32_ADVANCED_COLOR_HDR10     1u
#define WIN32_ADVANCED_COLOR_DOLBY     2u

typedef LONG (WINAPI *pfn_GetDisplayConfigBufferSizes)(UINT32, UINT32 *, UINT32 *);
typedef LONG (WINAPI *pfn_QueryDisplayConfig)(UINT32, UINT32 *, DISPLAYCONFIG_PATH_INFO *,
                                              UINT32 *, DISPLAYCONFIG_MODE_INFO *,
                                              DISPLAYCONFIG_TOPOLOGY_ID *);
typedef LONG (WINAPI *pfn_DisplayConfigGetDeviceInfo)(DISPLAYCONFIG_DEVICE_INFO_HEADER *);
typedef LONG (WINAPI *pfn_DisplayConfigSetDeviceInfo)(DISPLAYCONFIG_DEVICE_INFO_HEADER *);

typedef struct
{
    DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    UINT32 mode;
    UINT32 reserved;
} win32_dovi_state_query_t;

typedef struct
{
    DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    UINT32 mode;
} win32_dovi_state_set_t;

typedef struct
{
    DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    UINT32 flags;
    UINT32 color_encoding;
    UINT32 bits_per_channel;
} win32_advanced_color_info_t;

typedef struct
{
    DISPLAYCONFIG_DEVICE_INFO_HEADER header;
    UINT32 enable;
} win32_advanced_color_set_t;

_Static_assert(sizeof(win32_dovi_state_query_t) == 28,
               "unexpected private Dolby Vision query packet layout");
_Static_assert(sizeof(win32_dovi_state_set_t) == 24,
               "unexpected private Dolby Vision set packet layout");

struct win32_dovi_display
{
    pfn_DisplayConfigGetDeviceInfo get_info;
    pfn_DisplayConfigSetDeviceInfo set_info;
    DISPLAYCONFIG_DEVICE_INFO_HEADER target;
    UINT32 saved_mode;
    bool mode_changed;
    bool advanced_color_enabled;
};

static void InitHeader(DISPLAYCONFIG_DEVICE_INFO_HEADER *header,
                       DISPLAYCONFIG_DEVICE_INFO_TYPE type, UINT32 size,
                       const DISPLAYCONFIG_PATH_TARGET_INFO *target)
{
    memset(header, 0, sizeof(*header));
    header->type = type;
    header->size = size;
    header->adapterId = target->adapterId;
    header->id = target->id;
}

static bool SameDeviceName(const WCHAR *left, const WCHAR *right)
{
    return left != NULL && right != NULL && _wcsicmp(left, right) == 0;
}

static bool FindWindowTarget(vlc_object_t *obj, HWND hwnd,
                             pfn_GetDisplayConfigBufferSizes get_sizes,
                             pfn_QueryDisplayConfig query,
                             pfn_DisplayConfigGetDeviceInfo get_info,
                             DISPLAYCONFIG_PATH_TARGET_INFO *selected)
{
    HMONITOR monitor = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
    MONITORINFOEXW monitor_info = { .cbSize = sizeof(monitor_info) };
    if (monitor == NULL || !GetMonitorInfoW(monitor, (MONITORINFO *)&monitor_info))
        return false;

    for (unsigned attempt = 0; attempt < 3; ++attempt)
    {
        UINT32 path_count = 0, mode_count = 0;
        LONG result = get_sizes(QDC_ONLY_ACTIVE_PATHS, &path_count, &mode_count);
        if (result != ERROR_SUCCESS)
            return false;

        DISPLAYCONFIG_PATH_INFO *paths = vlc_alloc(path_count, sizeof(*paths));
        DISPLAYCONFIG_MODE_INFO *modes = vlc_alloc(mode_count, sizeof(*modes));
        if (paths == NULL || modes == NULL)
        {
            free(paths);
            free(modes);
            return false;
        }

        result = query(QDC_ONLY_ACTIVE_PATHS, &path_count, paths, &mode_count,
                       modes, NULL);
        if (result == ERROR_INSUFFICIENT_BUFFER)
        {
            free(paths);
            free(modes);
            continue;
        }
        if (result != ERROR_SUCCESS)
        {
            free(paths);
            free(modes);
            return false;
        }

        bool found = false;
        for (UINT32 i = 0; i < path_count && !found; ++i)
        {
            DISPLAYCONFIG_SOURCE_DEVICE_NAME source;
            memset(&source, 0, sizeof(source));
            source.header.type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            source.header.size = sizeof(source);
            source.header.adapterId = paths[i].sourceInfo.adapterId;
            source.header.id = paths[i].sourceInfo.id;
            if (get_info(&source.header) == ERROR_SUCCESS &&
                SameDeviceName(source.viewGdiDeviceName, monitor_info.szDevice))
            {
                *selected = paths[i].targetInfo;
                found = true;
            }
        }
        free(paths);
        free(modes);

        if (found)
        {
            msg_Dbg(obj, "Dolby Vision display target is %ls (id %lu)",
                    monitor_info.szDevice, (unsigned long)selected->id);
            return true;
        }
        return false;
    }
    return false;
}

static LONG GetDoviMode(win32_dovi_display_t *state, UINT32 *mode)
{
    win32_dovi_state_query_t query;
    memset(&query, 0, sizeof(query));
    query.header = state->target;
    query.header.type = DISPLAYCONFIG_GET_DOLBY_VISION_STATE;
    query.header.size = sizeof(query);
    LONG result = state->get_info(&query.header);
    if (result == ERROR_SUCCESS)
        *mode = query.mode;
    return result;
}

static LONG SetDoviMode(win32_dovi_display_t *state, UINT32 mode)
{
    win32_dovi_state_set_t set;
    memset(&set, 0, sizeof(set));
    set.header = state->target;
    set.header.type = DISPLAYCONFIG_SET_DOLBY_VISION_STATE;
    set.header.size = sizeof(set);
    set.mode = mode;
    return state->set_info(&set.header);
}

static LONG GetAdvancedColor(win32_dovi_display_t *state, UINT32 *flags)
{
    win32_advanced_color_info_t query;
    memset(&query, 0, sizeof(query));
    query.header = state->target;
    query.header.type = DISPLAYCONFIG_GET_ADVANCED_COLOR;
    query.header.size = sizeof(query);
    LONG result = state->get_info(&query.header);
    if (result == ERROR_SUCCESS)
        *flags = query.flags;
    return result;
}

static LONG SetAdvancedColor(win32_dovi_display_t *state, bool enable)
{
    win32_advanced_color_set_t set;
    memset(&set, 0, sizeof(set));
    set.header = state->target;
    set.header.type = DISPLAYCONFIG_SET_ADVANCED_COLOR;
    set.header.size = sizeof(set);
    set.enable = enable;
    return state->set_info(&set.header);
}

win32_dovi_display_t *Win32DoviDisplay_Enable(vlc_object_t *obj, HWND hwnd)
{
    if (hwnd == NULL)
        return NULL;

    HMODULE user32 = GetModuleHandleW(L"user32.dll");
    if (user32 == NULL)
        return NULL;

    pfn_GetDisplayConfigBufferSizes get_sizes =
        (pfn_GetDisplayConfigBufferSizes)(void *)GetProcAddress(
            user32, "GetDisplayConfigBufferSizes");
    pfn_QueryDisplayConfig query =
        (pfn_QueryDisplayConfig)(void *)GetProcAddress(user32,
                                                        "QueryDisplayConfig");
    pfn_DisplayConfigGetDeviceInfo get_info =
        (pfn_DisplayConfigGetDeviceInfo)(void *)GetProcAddress(
            user32, "DisplayConfigGetDeviceInfo");
    pfn_DisplayConfigSetDeviceInfo set_info =
        (pfn_DisplayConfigSetDeviceInfo)(void *)GetProcAddress(
            user32, "DisplayConfigSetDeviceInfo");
    if (get_sizes == NULL || query == NULL || get_info == NULL ||
        set_info == NULL)
        return NULL;

    win32_dovi_display_t *state = calloc(1, sizeof(*state));
    if (state == NULL)
        return NULL;
    state->get_info = get_info;
    state->set_info = set_info;

    DISPLAYCONFIG_PATH_TARGET_INFO target;
    if (!FindWindowTarget(obj, hwnd, get_sizes, query, get_info, &target))
        goto error;
    InitHeader(&state->target, DISPLAYCONFIG_GET_DOLBY_VISION_STATE,
               sizeof(win32_dovi_state_query_t), &target);

    UINT32 flags = 0;
    LONG result = GetAdvancedColor(state, &flags);
    if (result != ERROR_SUCCESS ||
        (flags & WIN32_ADVANCED_COLOR_SUPPORTED) == 0)
    {
        msg_Dbg(obj, "Dolby Vision display probe: HDR unavailable (%ld)",
                result);
        goto error;
    }

    state->advanced_color_enabled =
        (flags & WIN32_ADVANCED_COLOR_ENABLED) != 0;
    if (!state->advanced_color_enabled)
    {
        result = SetAdvancedColor(state, true);
        if (result != ERROR_SUCCESS)
        {
            msg_Dbg(obj, "cannot enable Windows advanced color for Dolby "
                         "Vision (%ld)", result);
            goto error;
        }
    }

    result = GetDoviMode(state, &state->saved_mode);
    if (result != ERROR_SUCCESS)
    {
        msg_Dbg(obj, "native Dolby Vision mode is unavailable (%ld)", result);
        goto restore_advanced_color;
    }
    if (state->saved_mode == WIN32_ADVANCED_COLOR_DOLBY)
    {
        msg_Info(obj, "native Windows Dolby Vision HDMI transport already active");
        return state;
    }

    result = SetDoviMode(state, WIN32_ADVANCED_COLOR_DOLBY);
    UINT32 active_mode = 0;
    if (result != ERROR_SUCCESS ||
        GetDoviMode(state, &active_mode) != ERROR_SUCCESS ||
        active_mode != WIN32_ADVANCED_COLOR_DOLBY)
    {
        msg_Dbg(obj, "native Dolby Vision mode rejected by Windows or the "
                     "display driver (%ld)", result);
        goto restore_advanced_color;
    }

    state->mode_changed = true;
    msg_Info(obj, "native Windows Dolby Vision HDMI transport active "
                  "(DisplayConfig target %lu; no Store extension required)",
             (unsigned long)state->target.id);
    return state;

restore_advanced_color:
    if (!state->advanced_color_enabled)
        SetAdvancedColor(state, false);
error:
    free(state);
    return NULL;
}

void Win32DoviDisplay_Restore(vlc_object_t *obj,
                              win32_dovi_display_t *state)
{
    if (state == NULL)
        return;

    if (state->mode_changed)
    {
        UINT32 restore_mode = state->saved_mode == WIN32_ADVANCED_COLOR_DOLBY
                            ? WIN32_ADVANCED_COLOR_DOLBY
                            : WIN32_ADVANCED_COLOR_HDR10;
        LONG result = SetDoviMode(state, restore_mode);
        if (result == ERROR_SUCCESS)
            msg_Info(obj, "restored Windows display after Dolby Vision playback");
        else
            msg_Warn(obj, "could not restore the Windows Dolby Vision display "
                          "state (%ld)", result);
    }
    if (!state->advanced_color_enabled)
        SetAdvancedColor(state, false);
    free(state);
}
