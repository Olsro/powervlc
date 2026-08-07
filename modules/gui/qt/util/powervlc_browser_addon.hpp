/*****************************************************************************
 * powervlc_browser_addon.hpp : PowerVLC browser add-on installation
 ****************************************************************************
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

#ifndef POWERVLC_BROWSER_ADDON_HPP
#define POWERVLC_BROWSER_ADDON_HPP

#include <QString>

class QWidget;

/** Does this build ship the add-on? Empty when it does not. */
QString PowerVLCBrowserAddonPath( void );

/** Hand the add-on to the browser, or say where it is if that fails. */
void PowerVLCInstallBrowserAddon( QWidget *parent );

#endif
