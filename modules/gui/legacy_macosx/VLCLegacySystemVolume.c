/*****************************************************************************
 * VLCLegacySystemVolume.m: system volume control for the legacy interface
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "VLCLegacySystemVolume.h"

#include <CoreAudio/CoreAudio.h>

#include "../../audio_output/coreaudio_compat.h"  // 10.3: AudioObject* is 10.4-only

/* volume of one channel of the default output device, 0.0 on failure */
static float systemVolumeForChannel(int channel)
{
    AudioDeviceID i_device;
    float f_volume;
    OSStatus err;
    UInt32 i_size;

    i_size = sizeof( i_device );
    AudioObjectPropertyAddress deviceAddress =
        { kAudioHardwarePropertyDefaultOutputDevice,
          kAudioDevicePropertyScopeOutput,
          kAudioObjectPropertyElementMaster };
    err = vlc_AudioObjectGetPropertyData( kAudioObjectSystemObject,
                                      &deviceAddress, 0, NULL,
                                      &i_size, &i_device );
    if (err != noErr)
        return .0;

    AudioObjectPropertyAddress propertyAddress =
        { kAudioDevicePropertyVolumeScalar,
          kAudioDevicePropertyScopeOutput,
          channel };
    i_size = sizeof( f_volume );
    err = vlc_AudioObjectGetPropertyData(i_device, &propertyAddress, 0, NULL,
                                     &i_size, &f_volume);
    if (err != noErr)
        return .0;

    return f_volume;
}

/* NO once a channel does not exist / is not settable (S/PDIF...) */
static int setSystemVolumeForChannel(float f_volume, int i_channel)
{
    AudioDeviceID i_device;
    OSStatus err;
    UInt32 i_size;
    Boolean b_writeable;

    i_size = sizeof( i_device );
    AudioObjectPropertyAddress deviceAddress =
        { kAudioHardwarePropertyDefaultOutputDevice,
          kAudioDevicePropertyScopeOutput,
          kAudioObjectPropertyElementMaster };
    err = vlc_AudioObjectGetPropertyData( kAudioObjectSystemObject,
                                      &deviceAddress, 0, NULL,
                                      &i_size, &i_device );
    if (err != noErr)
        return 0;

    AudioObjectPropertyAddress propertyAddress =
        { kAudioDevicePropertyVolumeScalar,
          kAudioDevicePropertyScopeOutput,
          i_channel };
    i_size = sizeof( f_volume );
    err = vlc_AudioObjectIsPropertySettable( i_device, &propertyAddress,
                                         &b_writeable );
    if (err != noErr || !b_writeable)
        return 0;
    err = vlc_AudioObjectSetPropertyData(i_device, &propertyAddress, 0, NULL,
                                     i_size, &f_volume);
    if (err != noErr)
        return 0;

    return 1;
}

static void stepSystemVolume(float f_delta)
{
    /* we trust that mono is always available and that all channels have
     * the same volume */
    float f_volume = systemVolumeForChannel(1) + f_delta;
    int b_returned = 1;
    int x;

    if (f_volume < 0.f)
        f_volume = 0.f;
    else if (f_volume > 1.f)
        f_volume = 1.f;

    /* CoreAudio gives no reasonable channel count: iterate until one
     * fails, like the modern interface does */
    for (x = 1; b_returned; x++)
        b_returned = setSystemVolumeForChannel(f_volume, x);
}

void VLCLegacySystemVolumeUp(void)
{
    stepSystemVolume(.0625f); /* 1/16 to match the OS */
}

void VLCLegacySystemVolumeDown(void)
{
    stepSystemVolume(-.0625f);
}
