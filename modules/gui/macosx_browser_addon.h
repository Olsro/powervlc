/*****************************************************************************
 * macosx_browser_addon.h: hand the browser add-on to the user's browser
 *****************************************************************************
 * Copyright (C) 2026 the PowerVLC team
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

#ifndef VLC_MACOSX_BROWSER_ADDON_H
#define VLC_MACOSX_BROWSER_ADDON_H

#import <Foundation/Foundation.h>

/* Both Mac interfaces offer this, so it lives here rather than twice over. */

/* The add-on shipped in the bundle, or nil when this build has none. */
NSString *VLCBrowserAddonPath(void);

/* Opens it with the browser the user has set as their default, which is
 * what makes the browser offer to install it. Returns NO if there is
 * nothing to install or no browser would take it. */
BOOL VLCBrowserAddonInstall(void);

#endif
