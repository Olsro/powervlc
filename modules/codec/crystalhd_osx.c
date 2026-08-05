/*****************************************************************************
 * crystalhd_osx.c: CrystalHD platform glue for macOS
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_configuration.h>

#include <unistd.h>
#include <string.h>
#include <sys/utsname.h>

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>

#include "crystalhd_osx.h"
#undef CrystalHDOSXSetFirmwarePath

/* Kept in sync with CRYSTALHD_API_DEV_NAME in the Broadcom headers, which the
 * contrib does not install. */
#define CRYSTALHD_DEV_NODE "/dev/crystalhd"

/*****************************************************************************
 * ReadPCIWord: pull a 16-bit PCI config value out of an IOKit registry entry
 *****************************************************************************/
static bool ReadPCIWord( io_service_t service, CFStringRef key,
                         uint16_t *pi_value )
{
    CFTypeRef p_ref = IORegistryEntryCreateCFProperty( service, key,
                                                       kCFAllocatorDefault, 0 );
    if( p_ref == NULL )
        return false;

    bool b_ok = false;
    if( CFGetTypeID( p_ref ) == CFDataGetTypeID() &&
        CFDataGetLength( p_ref ) >= 2 )
    {
        /* The property carries the raw config space bytes, little endian, so
         * do not just cast: PowerPC would read them backwards. */
        const UInt8 *p_bytes = CFDataGetBytePtr( p_ref );
        *pi_value = p_bytes[0] | (p_bytes[1] << 8);
        b_ok = true;
    }

    CFRelease( p_ref );
    return b_ok;
}

bool CrystalHDOSXFindCard( uint16_t *pi_device_id )
{
    CFMutableDictionaryRef p_match = IOServiceMatching( "IOPCIDevice" );
    if( p_match == NULL )
        return false;

    /* IOServiceGetMatchingServices consumes the dictionary, including on
     * failure, so it must not be released here.
     *
     * MACH_PORT_NULL selects the default port, and is how this is spelled on
     * every target from 10.4 up: kIOMasterPortDefault was deprecated in 12.0,
     * and its replacement would only weak-link on an old deployment target. */
    io_iterator_t iterator = IO_OBJECT_NULL;
    if( IOServiceGetMatchingServices( MACH_PORT_NULL, p_match,
                                      &iterator ) != KERN_SUCCESS )
        return false;

    bool b_found = false;
    io_service_t service;

    while( !b_found &&
           (service = IOIteratorNext( iterator )) != IO_OBJECT_NULL )
    {
        uint16_t i_vendor, i_device;

        if( ReadPCIWord( service, CFSTR( "vendor-id" ), &i_vendor ) &&
            ReadPCIWord( service, CFSTR( "device-id" ), &i_device ) &&
            i_vendor == CRYSTALHD_VENDOR_BROADCOM &&
            ( i_device == CRYSTALHD_DEVICE_BCM70012 ||
              i_device == CRYSTALHD_DEVICE_BCM70015 ) )
        {
            if( pi_device_id != NULL )
                *pi_device_id = i_device;
            b_found = true;
        }

        IOObjectRelease( service );
    }

    IOObjectRelease( iterator );
    return b_found;
}

bool CrystalHDOSXDriverReady( void )
{
    /* The kext exposes a character device rather than an IOUserClient, and
     * creates it with mode 0666, so a plain access() answers both "is the
     * driver loaded" and "may this process use it". */
    return access( CRYSTALHD_DEV_NODE, R_OK | W_OK ) == 0;
}

bool CrystalHDOSXBlockedBy64BitProcess( void )
{
    /* A 32-bit build always matches a 32-bit driver. */
    if( sizeof(void *) == 4 )
        return false;

    /* 64-bit build: only a 64-bit kernel carries the call through. */
    struct utsname u;
    if( uname( &u ) != 0 )
        return false;

    return strcmp( u.machine, "x86_64" ) != 0;
}

void CrystalHDOSXSetFirmwarePath( vlc_object_t *p_obj )
{
    /* An explicit override wins, so a developer can point at a build tree. */
    if( getenv( "LIBCRYSTALHD_FW_PATH" ) != NULL )
        return;

    char *psz_datadir = config_GetDataDir();
    if( psz_datadir == NULL )
        return;

    char *psz_fwdir;
    if( asprintf( &psz_fwdir, "%s/crystalhd", psz_datadir ) != -1 )
    {
        setenv( "LIBCRYSTALHD_FW_PATH", psz_fwdir, 1 );
        msg_Dbg( p_obj, "CrystalHD firmware directory: %s", psz_fwdir );
        free( psz_fwdir );
    }

    free( psz_datadir );
}
