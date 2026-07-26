/*****************************************************************************
 * VLCLegacySystemVolume.h: system volume control for the legacy interface
 *****************************************************************************
 * Copyright (C) 2003-2014 VLC authors and VideoLAN
 *
 * Authors: Jon Lech Johansen <jon-vl@nanocrew.net>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
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
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301,
 * USA.
 *****************************************************************************/

/* Plain C port of the NSSound (VLCAdditions) category of the modern
 * interface (steps the system output volume by 1/16th, like the volume
 * keys). The AudioObject* API used here already exists in the
 * MacOSX10.4u SDK, so no pre-AudioObject fallback is needed. */

#ifndef VLC_LEGACY_SYSTEM_VOLUME_H
#define VLC_LEGACY_SYSTEM_VOLUME_H

void VLCLegacySystemVolumeUp(void);
void VLCLegacySystemVolumeDown(void);

#endif
