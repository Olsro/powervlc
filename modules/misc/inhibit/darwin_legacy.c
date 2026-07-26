/*****************************************************************************
 * darwin_legacy.c: screen saver inhibition for Mac OS X 10.4/10.5
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
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

/* The modern interface inhibits sleep with IOPMAssertion, which only
 * exists since Mac OS X 10.6 (and lives in the disabled macosx UI module
 * anyway). On Tiger the display would blank one minute into a movie.
 * UpdateSystemActivity() is the historical API: poking it periodically
 * keeps the display and the system awake. */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_inhibit.h>

#include <CoreServices/CoreServices.h>

struct vlc_inhibit_sys
{
    vlc_timer_t timer;
};

static void Timer (void *data)
{
    VLC_UNUSED(data);
    UpdateSystemActivity (UsrActivity);
}

static void Inhibit (vlc_inhibit_t *ih, unsigned flags)
{
    vlc_inhibit_sys_t *sys = ih->p_sys;

    if (flags & VLC_INHIBIT_DISPLAY)
    {
        /* fire now, then every 30 seconds (the display sleep timeout
         * granularity is one minute) */
        UpdateSystemActivity (UsrActivity);
        vlc_timer_schedule (sys->timer, false, 1, 30 * CLOCK_FREQ);
    }
    else
        vlc_timer_schedule (sys->timer, false, 0, 0);
}

static int Open (vlc_object_t *obj)
{
    vlc_inhibit_t *ih = (vlc_inhibit_t *)obj;
    vlc_inhibit_sys_t *sys = malloc (sizeof (*sys));
    if (unlikely(sys == NULL))
        return VLC_ENOMEM;

    if (vlc_timer_create (&sys->timer, Timer, NULL))
    {
        free (sys);
        return VLC_EGENERIC;
    }

    ih->p_sys = sys;
    ih->inhibit = Inhibit;
    return VLC_SUCCESS;
}

static void Close (vlc_object_t *obj)
{
    vlc_inhibit_t *ih = (vlc_inhibit_t *)obj;
    vlc_inhibit_sys_t *sys = ih->p_sys;

    vlc_timer_destroy (sys->timer);
    free (sys);
}

vlc_module_begin ()
    set_shortname (N_("Darwin legacy inhibit"))
    set_description (N_("Screen saver inhibition for Mac OS X 10.4/10.5"))
    set_category (CAT_ADVANCED)
    set_subcategory (SUBCAT_ADVANCED_MISC)
    set_capability ("inhibit", 10)
    set_callbacks (Open, Close)
vlc_module_end ()
