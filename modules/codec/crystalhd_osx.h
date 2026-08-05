/*****************************************************************************
 * crystalhd_osx.h: CrystalHD platform glue for macOS
 *****************************************************************************
 * Copyright © 2026 PowerVLC
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

#ifndef VLC_CRYSTALHD_OSX_H
#define VLC_CRYSTALHD_OSX_H

#include <stdbool.h>
#include <stdint.h>

#define CRYSTALHD_VENDOR_BROADCOM   0x14e4
#define CRYSTALHD_DEVICE_BCM70012   0x1612
#define CRYSTALHD_DEVICE_BCM70015   0x1615

/**
 * Looks for a Crystal HD card in the IOKit registry.
 *
 * This works whether or not the kext is loaded: IOPCIFamily publishes the nub
 * for every device on the bus regardless of whether a driver matched it. So a
 * card can be reported as present even when nothing can talk to it yet, which
 * is exactly what the activation UI needs to know.
 *
 * \param pi_device_id filled in with the PCI device ID on success, may be NULL
 * \return true if a card is physically present
 */
bool CrystalHDOSXFindCard( uint16_t *pi_device_id );

/**
 * Whether the kext is loaded and its BSD node can be opened.
 */
bool CrystalHDOSXDriverReady( void );

/**
 * Whether this process cannot reach the card because of its architecture.
 *
 * macOS runs the 64-bit slice of a universal binary as soon as the CPU
 * allows, whatever the kernel is; but a kext matches the KERNEL. On a Mac
 * that only ever boots a 32-bit kernel -- the GMA 950 models have no 64-bit
 * graphics driver -- a 64-bit build simply cannot talk to the driver.
 */
bool CrystalHDOSXBlockedBy64BitProcess( void );

/**
 * Points libcrystalhd at the firmware blobs shipped inside the bundle.
 *
 * Without this the library falls back to /usr/lib, which would mean asking
 * the user to install the blobs system wide. An existing LIBCRYSTALHD_FW_PATH
 * in the environment is left untouched.
 */
void CrystalHDOSXSetFirmwarePath( vlc_object_t *p_obj );
#define CrystalHDOSXSetFirmwarePath( a ) \
        CrystalHDOSXSetFirmwarePath( VLC_OBJECT( a ) )

#endif /* VLC_CRYSTALHD_OSX_H */
