/*****************************************************************************
 * bluray_darwin_disc.h: read a Blu-ray disc over MMC on Mac OS X 10.4
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

#ifndef VLC_BLURAY_DARWIN_DISC_H
#define VLC_BLURAY_DARWIN_DISC_H

#include <vlc_common.h>

/*
 * Mac OS X 10.4 has no Blu-ray storage family at all. A BD-ROM is misdetected
 * as a CD -- the media is published as IOCDMedia with a 2352 byte block size,
 * so it never mounts and every read on /dev/[r]diskN returns EOF at any offset
 * (measured; the kernel logs "SAM Multimedia: READ or WRITE failed, ASC = 0x64"
 * = ILLEGAL MODE FOR THIS TRACK, because the CD media class asks the drive for
 * CD-mode reads). Sending READ(10) over SCSITaskLib is the only way to get the
 * bytes, so the player does that itself and hands libbluray the blocks.
 *
 * SCSITaskLib refuses commands unless the caller holds exclusive access, and
 * that has a single owner -- which is why the same channel is handed to libaacs
 * through aacs_use_external_mmc() rather than letting it open its own.
 */

typedef struct bluray_disc_t bluray_disc_t;

/**
 * Claim a drive and its disc.
 *
 * @param obj    parent object, for logging
 * @param psz_bsd_name  BSD name of the media ("disk1"), or NULL to take the
 *                      first optical drive that has readable media
 * @return NULL when no drive could be claimed
 */
bluray_disc_t *bluray_disc_OpenMMC(vlc_object_t *obj, const char *psz_bsd_name);

/**
 * Read a disc the OS can reach, through /dev/rdiskN, with the same read-ahead.
 *
 * @param psz_device  raw device node
 * @return NULL when the device cannot be read
 */
bluray_disc_t *bluray_disc_OpenRaw(vlc_object_t *obj, const char *psz_device);

/**
 * Release the drive.
 *
 * Exclusive access is held for the whole session and only dropped here: on 10.4
 * releasing it makes the OS re-probe media it cannot identify, and it responds
 * by ejecting the disc.
 */
void bluray_disc_Close(bluray_disc_t *);

/**
 * libbluray block reader (bd_open_stream_dev signature).
 *
 * @return number of 2048 byte blocks read, or a negative value on error
 */
int bluray_disc_ReadBlocks(void *handle, void *buf, int lba, int num_blocks);

/**
 * The SCSITaskDeviceInterface** backing this reader, to hand to libaacs.
 */
void *bluray_disc_TaskInterface(bluray_disc_t *);

#endif /* VLC_BLURAY_DARWIN_DISC_H */
