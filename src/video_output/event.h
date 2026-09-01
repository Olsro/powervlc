/*****************************************************************************
 * event.h: vout event
 *****************************************************************************
 * Copyright (C) 2009 Laurent Aimar
 * $Id$
 *
 * Authors: Laurent Aimar <fenrir _AT_ videolan _DOT_ org>
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

#include <vlc_common.h>
#include <math.h>

#include "vout_control.h"

/* TODO/FIXME
 *
 * It should be converted to something like input_thread_t:
 * one intf-event can be grabbed by a callback, all others
 * variable only var_Change
 *
 * Maybe a intf-mouse can be used too (don't like it).
 *
 * (Some case may infinite loop otherwise here)
 */

static inline void vout_SendEventClose(vout_thread_t *vout)
{
#warning FIXME: implement video close event
    /* FIXME: this code is disabled as it breaks the non-playlist cases */
    //playlist_Stop(pl_Get(vout));
    (void) vout;
}
static inline void vout_SendEventKey(vout_thread_t *vout, int key)
{
    var_SetInteger(vout->obj.libvlc, "key-pressed", key);
}
/* PowerVLC. Dragging the picture moves the window -- the gesture the two
 * macOS interfaces offer, and the only way to move the window at all once
 * "Hide controls during playback" has stripped its frame. An interface whose
 * own widget sees the mouse does it by itself; the Win32 vout creates a
 * child window of its own INSIDE the one the interface hands it and answers
 * every mouse message in its own thread, so no toolkit event is ever born
 * there and the core has to relay the gesture.
 *
 * The relay only exists for interfaces that ask for it, by creating the
 * libvlc "intf-video-drag" integer: 1 = pressed, 2 = moved, 3 = released.
 * No coordinates travel with it -- what moving a window needs is the
 * pointer in SCREEN space, which the interface reads for itself, while the
 * vout only ever knows picture coordinates. */
enum {
    VOUT_VIDEO_DRAG_PRESSED  = 1,
    VOUT_VIDEO_DRAG_MOVED    = 2,
    VOUT_VIDEO_DRAG_RELEASED = 3,
};
static inline void vout_RelayVideoDrag(vout_thread_t *vout, int phase)
{
    vlc_object_t *libvlc = VLC_OBJECT(vout->obj.libvlc);
    if (var_Type(libvlc, "intf-video-drag") != 0)
        var_SetInteger(libvlc, "intf-video-drag", phase);
}
static inline void vout_SendEventMouseMoved(vout_thread_t *vout, int x, int y)
{
    var_SetCoords(vout, "mouse-moved", x, y);
}
static inline void vout_SendEventViewpointMoved(vout_thread_t *vout,
                                                const vlc_viewpoint_t *p_viewpoint)
{
    var_SetAddress(vout, "viewpoint-moved", (void *) p_viewpoint);
    /* This variable can only be read from callbacks */
    var_Change(vout, "viewpoint-moved", VLC_VAR_SETVALUE,
               &(vlc_value_t) { .p_address = NULL }, NULL);
}
static inline void vout_SendEventMousePressed(vout_thread_t *vout, int button)
{
    int key = KEY_UNSET;
    var_OrInteger(vout, "mouse-button-down", 1 << button);

    switch (button)
    {
    case MOUSE_BUTTON_LEFT:
    {
        /* FIXME? */
        int x, y;
        var_GetCoords(vout, "mouse-moved", &x, &y);
        var_SetCoords(vout, "mouse-clicked", x, y);
        var_SetBool(vout->obj.libvlc, "intf-popupmenu", false);
        vout_RelayVideoDrag(vout, VOUT_VIDEO_DRAG_PRESSED);
        return;
    }
    case MOUSE_BUTTON_CENTER:
        var_ToggleBool(vout->obj.libvlc, "intf-toggle-fscontrol");
        return;
    case MOUSE_BUTTON_RIGHT:
#if !defined(_WIN32)
        var_SetBool(vout->obj.libvlc, "intf-popupmenu", true);
#endif
        return;
    case MOUSE_BUTTON_WHEEL_UP:    key = KEY_MOUSEWHEELUP;    break;
    case MOUSE_BUTTON_WHEEL_DOWN:  key = KEY_MOUSEWHEELDOWN;  break;
    case MOUSE_BUTTON_WHEEL_LEFT:  key = KEY_MOUSEWHEELLEFT;  break;
    case MOUSE_BUTTON_WHEEL_RIGHT: key = KEY_MOUSEWHEELRIGHT; break;
    }
    vout_SendEventKey(vout, key);
}
static inline void vout_SendEventMouseReleased(vout_thread_t *vout, int button)
{
    var_NAndInteger(vout, "mouse-button-down", 1 << button);
    if (button == MOUSE_BUTTON_LEFT)
        vout_RelayVideoDrag(vout, VOUT_VIDEO_DRAG_RELEASED);
#if defined(_WIN32)
    switch (button)
    {
    case MOUSE_BUTTON_RIGHT:
        var_SetBool(vout->obj.libvlc, "intf-popupmenu", true);
        return;
    }
#endif
}
static inline void vout_SendEventMouseDoubleClick(vout_thread_t *vout)
{
    /* Exclusive HDMI stereo has an in-picture controller.  Two quick presses
     * on one of its seek buttons are two commands, not a request to leave
     * fullscreen.  The display marks only hits inside that controller. */
    if (var_Type(vout, "stereo-controls-double-click-until") != 0 &&
        mdate() < var_GetInteger(vout,
                                "stereo-controls-double-click-until"))
        return;

    /* While an interface auto-hides its windowed controls (it then holds
     * the libvlc "intf-controls-hidden" bool up), a double click means
     * "bring the controls back", not "toggle fullscreen". */
    vlc_object_t *libvlc = VLC_OBJECT(vout->obj.libvlc);
    if (var_Type(libvlc, "intf-controls-hidden") != 0
     && var_GetBool(libvlc, "intf-controls-hidden"))
    {
        if (var_Type(libvlc, "intf-reveal-controls") != 0)
            var_TriggerCallback(libvlc, "intf-reveal-controls");
        return;
    }
    //vout_ControlSetFullscreen(vout, !var_GetBool(vout, "fullscreen"));
    var_ToggleBool(vout, "fullscreen");
}
static inline void vout_SendEventViewpointChangeable(vout_thread_t *vout,
                                                     bool b_can_change)
{
    var_SetBool(vout, "viewpoint-changeable", b_can_change);
}

#if 0
static inline void vout_SendEventSnapshot(vout_thread_t *vout, const char *filename)
{
    /* signal creation of a new snapshot file */
    var_SetString(vout->obj.libvlc, "snapshot-file", filename);
}

#warning "FIXME clean up postproc event"

extern void vout_InstallDeprecatedPostProcessing(vout_thread_t *);
extern void vout_UninstallDeprecatedPostProcessing(vout_thread_t *);

static inline void vout_SendEventPostProcessing(vout_thread_t *vout, bool is_available)
{
    if (is_available)
        vout_InstallDeprecatedPostProcessing(vout);
    else
        vout_UninstallDeprecatedPostProcessing(vout);
}

static inline void vout_SendEventFilters(vout_thread_t *vout)
{
    vout_filter_t **filter;
    int           filter_count;

    vout_ControlGetFilters(vout, &filter, &filter_count);

    char *list = strdup("");
    for (int i = 0; i < filter_count; i++) {
        char *psz;

        if (asprintf(&psz, "%s%s%s",
                     list, i > 0 ? ":" : "", filter[i]->name) < 0) {
            free(list);
            list = NULL;
            break;
        }
        free(list);
        list = psz;
    }

    if (list) {
        vlc_value_t val;
        val.psz_string = list;
        var_Change(vout, "video-filter", VLC_VAR_SETVALUE, &val, NULL);
        free(list);
    }

    for (int i = 0; i < filter_count; i++)
        vout_filter_Delete(filter[i]);
    free(filter);
}
#endif
