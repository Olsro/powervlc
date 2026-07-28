/*****************************************************************************
 * powervlc_disclibs.hpp : PowerVLC Blu-ray helper-library folders
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

#ifndef VLC_QT_POWERVLC_DISCLIBS_HPP_
#define VLC_QT_POWERVLC_DISCLIBS_HPP_

class QWidget;

/* True when this build can play Blu-ray discs at all, i.e. when the menu
 * entries below have something to be useful for. */
bool PowerVLCHasBluray( void );

/* Creates <config home>/<psz_lib> if needed and shows it in the file manager.
 * psz_lib is "aacs" or "bdplus". */
void PowerVLCOpenDiscLibFolder( QWidget *parent, const char *psz_lib );

#endif
