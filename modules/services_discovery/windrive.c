/**
 * @file win_disc.c
 * @brief List of disc drives for VLC media player for Windows
 */
/*****************************************************************************
 * Copyright © 2010 Rémi Denis-Courmont
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

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include <vlc_common.h>
#include <vlc_services_discovery.h>
#include <vlc_plugin.h>

#include <windows.h>
#include <winioctl.h>

/* Keep this probe independent from the CDDA access module: service discovery
 * only needs the control nibble from the standard READ TOC response. */
#define DISC_MAX_TRACKS 100
typedef struct
{
    UCHAR reserved;
    UCHAR control_and_adr;
    UCHAR track_number;
    UCHAR reserved1;
    UCHAR address[4];
} disc_track_data_t;

typedef struct
{
    UCHAR length[2];
    UCHAR first_track;
    UCHAR last_track;
    disc_track_data_t tracks[DISC_MAX_TRACKS];
} disc_toc_t;

#ifndef IOCTL_CDROM_BASE
# define IOCTL_CDROM_BASE FILE_DEVICE_CD_ROM
#endif
#ifndef IOCTL_CDROM_READ_TOC
# define IOCTL_CDROM_READ_TOC CTL_CODE(IOCTL_CDROM_BASE, 0x0000, \
                                       METHOD_BUFFERED, FILE_READ_ACCESS)
#endif

static bool IsAudioCD( char letter )
{
    char device[] = "\\\\.\\A:";
    device[4] = letter;

    HANDLE handle = CreateFileA( device, GENERIC_READ,
                                 FILE_SHARE_READ | FILE_SHARE_WRITE, NULL,
                                 OPEN_EXISTING, 0, NULL );
    if( handle == INVALID_HANDLE_VALUE )
        return false;

    disc_toc_t toc;
    DWORD read;
    const BOOL ok = DeviceIoControl( handle, IOCTL_CDROM_READ_TOC, NULL, 0,
                                     &toc, sizeof(toc), &read, NULL );
    CloseHandle( handle );
    if( !ok || read < offsetof(disc_toc_t, tracks) )
        return false;

    const unsigned tracks = toc.last_track - toc.first_track + 1;
    if( tracks == 0 || tracks > DISC_MAX_TRACKS
     || read < offsetof(disc_toc_t, tracks) + tracks * sizeof(toc.tracks[0]) )
        return false;

    for( unsigned i = 0; i < tracks; ++i )
        if( (toc.tracks[i].control_and_adr & 0x04) == 0 )
            return true;
    return false;
}

static int Open (vlc_object_t *);

VLC_SD_PROBE_HELPER("disc", N_("Discs"), SD_CAT_DEVICES)

/*
 * Module descriptor
 */
vlc_module_begin ()
    add_submodule ()
    set_shortname (N_("Discs"))
    set_description (N_("Discs"))
    set_category (CAT_PLAYLIST)
    set_subcategory (SUBCAT_PLAYLIST_SD)
    set_capability ("services_discovery", 0)
    set_callbacks (Open, NULL)
    add_shortcut ("disc")

    VLC_SD_PROBE_SUBMODULE

vlc_module_end ()

/**
 * Probes and initializes.
 */
static int Open (vlc_object_t *obj)
{
    services_discovery_t *sd = (services_discovery_t *)obj;

    sd->description = _("Discs");

    LONG drives = GetLogicalDrives ();
    char mrl[12] = "file:///A:/", name[3] = "A:";
    CHAR path[4] = "A:\\";

    for (char d = 0; d < 26; d++)
    {
        input_item_t *item;
        CHAR letter = 'A' + d;

        /* Does this drive actually exist? */
        if (!(drives & (1 << d)))
            continue;
        /* Is it a disc drive? */
        path[0] = letter;
        if (GetDriveTypeA (path) != DRIVE_CDROM)
            continue;

        name[0] = letter;
        if( IsAudioCD( letter ) )
            snprintf( mrl, sizeof(mrl), "cdda:///%c:", letter );
        else
        {
            strcpy( mrl, "file:///A:/" );
            mrl[8] = letter;
        }
        item = input_item_NewDisc (mrl, name, -1);
        msg_Dbg (sd, "adding %s (%s)", mrl, name);
        if (item == NULL)
            break;

        services_discovery_AddItem(sd, item);
    }
    return VLC_SUCCESS;
}
