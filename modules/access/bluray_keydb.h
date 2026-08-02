/*****************************************************************************
 * bluray_keydb.h: find a disc's main playlist in the user's AACS key database
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifndef VLC_BLURAY_KEYDB_H
#define VLC_BLURAY_KEYDB_H

#include <vlc_common.h>
#include <stdint.h>

/*
 * "Playlist obfuscation": some discs hide the real feature among hundreds of
 * decoy .mpls playlists, all of them plausible and several of them the same
 * length as the real one. Picking the longest title -- which is what
 * bd_get_main_title() does, and what this player has always followed when
 * playing without menus -- then lands on a decoy, and the viewer has no way to
 * tell: the title list is a bare "Title 1..N" with nothing tying an entry to a
 * file on the disc.
 *
 * The information needed to resolve this is usually already on the user's
 * machine. FindVUK's KEYDB.cfg records the feature playlist for a large share
 * of the discs it covers, in the trailing comment of the disc's entry:
 *
 *   0xE1DD...5965 = BACCANO DISC 1 | D | ... | V | 0x... ; MKBv40/FindVUK 1.10
 *                                  - MainPlaylist: 00005.mpls - VolumeSize: ...
 *
 * libaacs never sees it: its lexer drops everything after the ';', and no
 * token for a playlist exists in its grammar. So this reads the file directly.
 * Nothing here parses or needs any key material -- only the disc id at the
 * start of the line and the playlist number in the comment are looked at.
 */

#define BLURAY_KEYDB_NO_PLAYLIST (-1)

/**
 * Look up the main playlist recorded for a disc in the user's key database.
 *
 * @param obj       object to log through
 * @param p_disc_id the 20-byte AACS disc id (BLURAY_DISC_INFO.disc_id)
 * @return the playlist number (the NNNNN of NNNNN.mpls), or
 *         BLURAY_KEYDB_NO_PLAYLIST when there is no key database, no entry for
 *         this disc, or no playlist recorded in the entry.
 */
int bluray_KeydbFindMainPlaylist(vlc_object_t *obj, const uint8_t *p_disc_id);

#endif /* VLC_BLURAY_KEYDB_H */
