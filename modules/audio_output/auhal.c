/*****************************************************************************
 * auhal.c: AUHAL and Coreaudio output plugin
 *****************************************************************************
 * Copyright (C) 2005 - 2017 VLC authors and VideoLAN
 *
 * Authors: Derk-Jan Hartman <hartman at videolan dot org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
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

#pragma mark includes

#import "coreaudio_common.h"

#import <vlc_plugin.h>
#import <vlc_dialog.h>                      // vlc_dialog_display_error
#import <vlc_charset.h>                     // FromCFString

#import <CoreAudio/CoreAudio.h>             // AudioDeviceID
#import <CoreServices/CoreServices.h>
#import <IOKit/IOKitLib.h>

#include <dlfcn.h>

#import "coreaudio_compat.h"          // 10.3: AudioObject* is 10.4-only

#pragma mark -
#pragma mark local prototypes & module descriptor


#define AOUT_VOLUME_DEFAULT             256
#define AOUT_VOLUME_MAX                 512

#define VOLUME_TEXT N_("Audio volume")
#define VOLUME_LONGTEXT VOLUME_TEXT

#define DEVICE_TEXT N_("Last audio device")
#define DEVICE_LONGTEXT DEVICE_TEXT

static int      Open                    (vlc_object_t *);
static void     Close                   (vlc_object_t *);

vlc_module_begin ()
    set_shortname("auhal")
    set_description(N_("HAL AudioUnit output"))
    set_capability("audio output", 101)
    set_category(CAT_AUDIO)
    set_subcategory(SUBCAT_AUDIO_AOUT)
    set_callbacks(Open, Close)
    add_integer("auhal-volume", AOUT_VOLUME_DEFAULT,
                VOLUME_TEXT, VOLUME_LONGTEXT, true)
    change_integer_range(0, AOUT_VOLUME_MAX)
    add_string("auhal-audio-device", "", DEVICE_TEXT, DEVICE_LONGTEXT, true)
    add_string("auhal-warned-devices", "", NULL, NULL, true)
    add_obsolete_integer("macosx-audio-device") /* since 2.1.0 */
vlc_module_end ()

#pragma mark -
#pragma mark private declarations

#define AOUT_VAR_SPDIF_FLAG 0xf00000

/* Apple HDMI drivers expose these IEC 60958 carrier formats even though the
 * identifiers are not part of the public CoreAudio SDK.  They can already be
 * observed on systems whose deployment target predates them, so use literal
 * AudioFormatIDs rather than availability-gated SDK names. */
#define kAudioFormat60958EAC3Compat ((AudioFormatID)'cec3')
#define kAudioFormat60958MATCompat  ((AudioFormatID)'mtat')

/* Largest IEC 61937 pause repetition period used here: four HBR carrier
 * frames of sixteen bytes each (TrueHD/MAT and E-AC-3). */
#define HDMI_PAUSE_MAX_PERIOD 64
#define VLC_CA_TRANSPORT_HDMI ((UInt32)'hdmi')
#define VLC_CA_TRANSPORT_DISPLAYPORT ((UInt32)'dprt')

/*****************************************************************************
 * aout_sys_t: private audio output method descriptor
 *****************************************************************************
 * This structure is part of the audio output thread descriptor.
 * It describes the CoreAudio specific properties of an output thread.
 *****************************************************************************/
struct aout_sys_t
{
    struct aout_sys_common c;

    /* DeviceID of the selected device */
    AudioObjectID               i_selected_dev;
    /* DeviceID of device which will be selected on start */
    AudioObjectID               i_new_selected_dev;
    /* true if the user selected the default audio device (id 0) */
    bool                        b_selected_dev_is_default;
    /* CoreAudio IDs are ephemeral: an HDMI mode/topology change removes the
     * endpoint and republishes the same sink under another numeric ID. */
    CFStringRef                 selected_device_uid;
    CFStringRef                 selected_device_name;
    UInt32                      selected_device_transport;

    /* DeviceID of current device */
    AudioDeviceIOProcID         i_procID;
    /* Are we running in digital mode? */
    bool                        b_digital;
    /* IEC 61937 type-3 pause burst repeated while a digital queue is empty.
     * It keeps the receiver locked across seek preroll without scheduling any
     * programme audio or changing the physical stream format. */
    uint8_t                     p_pause_burst[HDMI_PAUSE_MAX_PERIOD];
    size_t                      i_pause_burst_size;
    size_t                      i_pause_burst_offset;

    /* AUHAL specific */
    AudioUnit                   au_unit;

    /* CoreAudio SPDIF mode specific */
    /* Keep the pid of our hog status */
    pid_t                       i_hog_pid;
    /* The StreamID that has a cac3 streamformat */
    AudioStreamID               i_stream_id;
    /* The index of i_stream_id in an AudioBufferList */
    int                         i_stream_index;
    /* The original format of the stream */
    AudioStreamBasicDescription sfmt_revert;
    /* Whether we need to revert the stream format */
    bool                        b_revert;
    /* Whether we need to set the mixing mode back */
    bool                        b_changed_mixing;

    /* Original device nominal sample rate to restore on Stop (0 = none).
     * Switching the device to the stream rate (like Apple's DVD Player
     * does) removes every resampling stage, which a G3 cannot afford. */
    Float64                     f_revert_rate;

    CFArrayRef                  device_list;
    /* protects access to device_list */
    vlc_mutex_t                 device_list_lock;

    /* Synchronizes access to i_selected_dev. This is only needed between VLCs
     * audio thread and the core audio callback thread. The value is only
     * changed in Start, further access to this variable within the audio
     * thread (start, stop, close) needs no protection. */
    vlc_mutex_t                 selected_device_lock;

    float                       f_volume;
    bool                        b_mute;

    bool                        b_ignore_streams_changed_callback;
};

#pragma mark -
#pragma mark helpers

static int
AoGetProperty(audio_output_t *p_aout, AudioObjectID id,
              const AudioObjectPropertyAddress *p_address, size_t i_elm_size,
              ssize_t i_nb_expected_elms, size_t *p_nb_elms, void **pp_out_data,
              void *p_allocated_out_data)
{
    assert(i_elm_size > 0);

    /* Get data size */
    UInt32 i_out_size;
    OSStatus err = vlc_AudioObjectGetPropertyDataSize(id, p_address, 0, NULL,
                                                  &i_out_size);
    if (err != noErr)
    {
        /* ⚠ Une propriété INCONNUE n'est pas une panne : les systèmes anciens
         * n'ont pas toutes celles des SDK récents. Sur Mac OS X 10.2,
         * `kAudioStreamPropertyAvailablePhysicalFormats` ('pfta') n'existe pas
         * et rend 'who?' — la sonde de sortie numérique échoue donc à chaque
         * lancement, mais la sortie ANALOGIQUE s'ouvre ensuite normalement.
         * Journalisé en erreur, ce message fait croire à une panne audio : il
         * m'a fait conclure à tort que l'audio ne marchait pas sur Jaguar
         * (2026-08-05), alors que la lecture sortait bien en 5.1. */
        if (err == kAudioHardwareUnknownPropertyError)
            msg_Dbg(p_aout, "propriété [%4.4s] absente sur ce système "
                    "(périphérique %i) — sonde ignorée",
                    (const char *) &p_address[0], id);
        else
            msg_Err(p_aout, "AudioObjectGetPropertyDataSize failed, device id: "
                    "%i, prop: [%4.4s], OSStatus: %d", id,
                    (const char *) &p_address[0], (int)err);
        return VLC_EGENERIC;
    }

    size_t i_nb_elms = i_out_size / i_elm_size;
    if (p_nb_elms != NULL)
        *p_nb_elms = i_nb_elms;
    /* Check if we get the expected number of elements */
    if (i_nb_expected_elms != -1 && (size_t)i_nb_expected_elms != i_nb_elms)
    {
        msg_Err(p_aout, "AoGetProperty error: expected elements don't match");
        return VLC_EGENERIC;
    }

    if (pp_out_data == NULL && p_allocated_out_data == NULL)
        return VLC_SUCCESS;

    if (i_out_size == 0)
    {
        if (pp_out_data != NULL)
            *pp_out_data = NULL;
        return VLC_SUCCESS;
    }

    /* Alloc data or use pre-allocated one */
    void *p_out_data;
    if (pp_out_data != NULL)
    {
        assert(p_allocated_out_data == NULL);

        *pp_out_data = malloc(i_out_size);
        if (*pp_out_data == NULL)
            return VLC_ENOMEM;
        p_out_data = *pp_out_data;
    }
    else
    {
        assert(p_allocated_out_data != NULL);
        p_out_data = p_allocated_out_data;
    }

    /* Fill data */
    err = vlc_AudioObjectGetPropertyData(id, p_address, 0, NULL, &i_out_size,
                                     p_out_data);
    if (err != noErr)
    {
        msg_Err(p_aout, "AudioObjectGetPropertyData failed, device id: %i, "
                "prop: [%4.4s], OSStatus: %d", id, (const char *) &p_address[0],
                (int) err);

        if (pp_out_data != NULL)
            free(*pp_out_data);
        return VLC_EGENERIC;
    }
    assert(p_nb_elms == NULL || *p_nb_elms == (i_out_size / i_elm_size));
    return VLC_SUCCESS;
}

/* Get Audio Object Property data: pp_out_data will be allocated by this MACRO
 * and need to be freed in case of success. */
#define AO_GETPROP(id, type, p_out_nb_elms, pp_out_data, a1, a2) \
    AoGetProperty(p_aout, (id), \
                  &(AudioObjectPropertyAddress) {(a1), (a2), 0}, sizeof(type), \
                  -1, (p_out_nb_elms), (void **)(pp_out_data), NULL)

/* Get 1 Audio Object Property data: pre-allocated by the caller */
#define AO_GET1PROP(id, type, p_out_data, a1, a2) \
    AoGetProperty(p_aout, (id), \
                  &(AudioObjectPropertyAddress) {(a1), (a2), 0}, sizeof(type), \
                  1, NULL, NULL, (p_out_data))

static bool
AoIsPropertySettable(audio_output_t *p_aout, AudioObjectID id,
                     const AudioObjectPropertyAddress *p_address)
{
    Boolean b_settable;
    OSStatus err = vlc_AudioObjectIsPropertySettable(id, p_address, &b_settable);
    if (err != noErr)
    {
        msg_Warn(p_aout, "AudioObjectIsPropertySettable failed, device id: %i, "
                 "prop: [%4.4s], OSStatus: %d", id, (const char *)&p_address[0],
                 (int)err);
        return false;
    }
    return b_settable;
}

#define AO_ISPROPSETTABLE(id, a1, a2) \
    AoIsPropertySettable(p_aout, (id), \
                         &(AudioObjectPropertyAddress) { (a1), (a2), 0})

#define AO_HASPROP(id, a1, a2) \
    vlc_AudioObjectHasProperty((id), &(AudioObjectPropertyAddress) { (a1), (a2), 0})

static int
AoSetProperty(audio_output_t *p_aout, AudioObjectID id,
              const AudioObjectPropertyAddress *p_address, size_t i_data,
              const void *p_data)
{
    OSStatus err =
        vlc_AudioObjectSetPropertyData(id, p_address, 0, NULL, i_data, p_data);

    if (err != noErr)
    {
        msg_Err(p_aout, "AudioObjectSetPropertyData failed, device id: %i, "
                 "prop: [%4.4s], OSStatus: %d", id, (const char *)&p_address[0],
                 (int)err);
        return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

#define AO_SETPROP(id, i_data, p_data, a1, a2) \
    AoSetProperty(p_aout, (id), \
                  &(AudioObjectPropertyAddress) { (a1), (a2), 0}, \
                  (i_data), (p_data));

static int
AoUpdateListener(audio_output_t *p_aout, bool add, AudioObjectID id,
                 const AudioObjectPropertyAddress *p_address,
                 AudioObjectPropertyListenerProc listener, void *data)
{
    OSStatus err = add ?
        vlc_AudioObjectAddPropertyListener(id, p_address, listener, data) :
        vlc_AudioObjectRemovePropertyListener(id, p_address, listener, data);

    if (err != noErr)
    {
        msg_Err(p_aout, "AudioObject%sPropertyListener failed, device id %i, "
                "prop: [%4.4s], OSStatus: %d", add ? "Add" : "Remove", id,
                (const char *)&p_address[0], (int)err);
        return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

#define AO_UPDATELISTENER(id, add, listener, data, a1, a2) \
    AoUpdateListener(p_aout, add, (id), \
                  &(AudioObjectPropertyAddress) { (a1), (a2), 0}, \
                  (listener), (data))

#pragma mark -
#pragma mark Stream / Hardware Listeners

static bool
IsAudioFormatDigital(AudioFormatID id)
{
    switch (id)
    {
        case 'IAC3':
        case 'iac3':
        case kAudioFormat60958AC3:
        case kAudioFormatAC3:
        case kAudioFormatEnhancedAC3:
        case kAudioFormat60958EAC3Compat:
        case kAudioFormat60958MATCompat:
            return true;
        default:
            return false;
    }
}

static OSStatus
StreamsChangedListener(AudioObjectID, UInt32,
                       const AudioObjectPropertyAddress [], void *);

static int
ManageAudioStreamsCallback(audio_output_t *p_aout, AudioDeviceID i_dev_id,
                           bool b_register)
{
    /* Retrieve all the output streams */
    size_t i_streams;
    AudioStreamID *p_streams;
    int ret = AO_GETPROP(i_dev_id, AudioStreamID, &i_streams, &p_streams,
                          kAudioDevicePropertyStreams,
                          kAudioObjectPropertyScopeOutput);
    if (ret != VLC_SUCCESS)
        return ret;

    for (size_t i = 0; i < i_streams; i++)
    {
        /* get notified when physical formats change */
        AO_UPDATELISTENER(p_streams[i], b_register, StreamsChangedListener,
                          p_aout, kAudioStreamPropertyAvailablePhysicalFormats,
                          kAudioObjectPropertyScopeGlobal);
    }

    free(p_streams);
    return VLC_SUCCESS;
}

/*
 * AudioStreamSupportsDigital: Checks if audio stream is compatible with raw
 * bitstreams
 */
static bool
AudioStreamSupportsDigital(audio_output_t *p_aout, AudioStreamID i_stream_id)
{
    bool b_return = false;

    /* Retrieve all the stream formats supported by each output stream */
    size_t i_formats;
    AudioStreamRangedDescription *p_format_list;
    int ret = AO_GETPROP(i_stream_id, AudioStreamRangedDescription, &i_formats,
                          &p_format_list,
                          kAudioStreamPropertyAvailablePhysicalFormats,
                          kAudioObjectPropertyScopeGlobal);
    if (ret != VLC_SUCCESS)
        return false;

    for (size_t i = 0; i < i_formats; i++)
    {
        /* Kept at debug level: HDMI HBR troubleshooting depends on knowing
         * whether CoreAudio actually exposes a 192 kHz encoded physical
         * format. Release builds still need to be diagnosable with -vv. */
        msg_Dbg(p_aout, STREAM_FORMAT_MSG("supported format: ",
                p_format_list[i].mFormat));

        if (IsAudioFormatDigital(p_format_list[i].mFormat.mFormatID))
            b_return = true;
    }

    free(p_format_list);
    return b_return;
}

/*
 * AudioDeviceSupportsDigital: Checks if device supports raw bitstreams
 */
static bool
AudioDeviceSupportsDigital(audio_output_t *p_aout, AudioDeviceID i_dev_id)
{
    size_t i_streams;
    AudioStreamID * p_streams;
    int ret = AO_GETPROP(i_dev_id, AudioStreamID, &i_streams, &p_streams,
                          kAudioDevicePropertyStreams,
                          kAudioObjectPropertyScopeOutput);
    if (ret != VLC_SUCCESS)
        return false;

    for (size_t i = 0; i < i_streams; i++)
    {
        if (AudioStreamSupportsDigital(p_aout, p_streams[i]))
        {
            free(p_streams);
            return true;
        }
    }

    free(p_streams);
    return false;
}

/* CoreAudio's list of physical formats describes what the Mac-side HDMI
 * engine can put on the wire, not necessarily what the connected sink can
 * decode. In particular, Apple exposes an HBR/MAT carrier even when a
 * projector's EDID has no TrueHD SAD. Opening that carrier succeeds but the
 * sink quite correctly produces silence. Read the sink EDID as a second,
 * codec-level capability check before selecting passthrough.
 *
 * The public IODisplayConnect registry path covers classic PowerPC/Intel
 * macOS. Apple Silicon moved external displays behind DCPAVServiceProxy, so
 * use the same late-bound IOAV EDID accessor as the 3D video output. Keeping
 * that path late-bound preserves the Mac OS X 10.4 deployment target. */
typedef CFTypeRef (*AUHALIOAVServiceCreateWithService)(CFAllocatorRef,
                                                       io_service_t);
typedef IOReturn (*AUHALIOAVServiceCopyEDID)(CFTypeRef, CFDataRef *);

static bool EDIDIsValid(CFDataRef data)
{
    static const uint8_t header[8] = {
        0x00, 0xff, 0xff, 0xff, 0xff, 0xff, 0xff, 0x00
    };
    CFIndex length = data != NULL ? CFDataGetLength(data) : 0;
    if (length < 128 || length > 512 || length % 128 != 0)
        return false;

    const uint8_t *bytes = CFDataGetBytePtr(data);
    if (memcmp(bytes, header, sizeof(header)) != 0 ||
        bytes[126] + 1 != (unsigned)length / 128)
        return false;

    for (CFIndex block = 0; block < length; block += 128)
    {
        unsigned checksum = 0;
        for (unsigned i = 0; i < 128; ++i)
            checksum += bytes[block + i];
        if ((checksum & 0xff) != 0)
            return false;
    }
    return true;
}

static bool EDIDMatchesDisplayName(CFDataRef data, CFStringRef device_name)
{
    if (!EDIDIsValid(data) || device_name == NULL)
        return false;

    const uint8_t *bytes = CFDataGetBytePtr(data);
    for (unsigned offset = 54; offset + 18 <= 126; offset += 18)
    {
        const uint8_t *descriptor = bytes + offset;
        if (descriptor[0] != 0 || descriptor[1] != 0 ||
            descriptor[2] != 0 || descriptor[3] != 0xfc)
            continue;

        char monitor_name[14];
        size_t length = 13;
        memcpy(monitor_name, descriptor + 5, length);
        while (length > 0 && (monitor_name[length - 1] == ' ' ||
                              monitor_name[length - 1] == '\n' ||
                              monitor_name[length - 1] == '\r' ||
                              monitor_name[length - 1] == '\0'))
            --length;
        monitor_name[length] = '\0';

        CFStringRef edid_name = CFStringCreateWithCString(
            kCFAllocatorDefault, monitor_name, kCFStringEncodingASCII);
        if (edid_name == NULL)
            return false;
        bool matches = CFStringCompare(device_name, edid_name,
                         kCFCompareCaseInsensitive) == kCFCompareEqualTo;
        CFRelease(edid_name);
        return matches;
    }
    return false;
}

static void ConsiderEDIDCandidate(CFDataRef data, CFStringRef device_name,
                                  CFDataRef *match, CFDataRef *only,
                                  unsigned *count)
{
    if (!EDIDIsValid(data))
        return;
    ++*count;
    if (*only == NULL)
        *only = CFRetain(data);
    if (*match == NULL && EDIDMatchesDisplayName(data, device_name))
        *match = CFRetain(data);
}

static CFDataRef CopyPublicDisplayEDID(CFStringRef device_name)
{
    CFMutableDictionaryRef matching = IOServiceMatching("IODisplayConnect");
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (matching == NULL ||
        IOServiceGetMatchingServices(kIOMasterPortDefault, matching,
                                     &iterator) != kIOReturnSuccess)
        return NULL;

    CFDataRef match = NULL;
    CFDataRef only = NULL;
    unsigned count = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL)
    {
        CFTypeRef value = IORegistryEntryCreateCFProperty(
            service, CFSTR("IODisplayEDID"), kCFAllocatorDefault, 0);
        if (value != NULL && CFGetTypeID(value) == CFDataGetTypeID())
            ConsiderEDIDCandidate((CFDataRef)value, device_name,
                                  &match, &only, &count);
        if (value != NULL)
            CFRelease(value);
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);

    if (match != NULL)
    {
        if (only != NULL)
            CFRelease(only);
        return match;
    }
    if (count == 1)
        return only;
    if (only != NULL)
        CFRelease(only);
    return NULL;
}

static bool IOAVServiceIsExternal(io_service_t service)
{
    CFTypeRef value = IORegistryEntryCreateCFProperty(
        service, CFSTR("Location"), kCFAllocatorDefault, 0);
    bool external = value != NULL &&
        CFGetTypeID(value) == CFStringGetTypeID() &&
        CFStringCompare((CFStringRef)value, CFSTR("External"), 0) ==
            kCFCompareEqualTo;
    if (value != NULL)
        CFRelease(value);
    return external;
}

static CFDataRef CopyDCPDisplayEDID(CFStringRef device_name)
{
    AUHALIOAVServiceCreateWithService create =
        (AUHALIOAVServiceCreateWithService)
        dlsym(RTLD_DEFAULT, "IOAVServiceCreateWithService");
    AUHALIOAVServiceCopyEDID copy_edid = (AUHALIOAVServiceCopyEDID)
        dlsym(RTLD_DEFAULT, "IOAVServiceCopyEDID");
    if (create == NULL || copy_edid == NULL)
        return NULL;

    CFMutableDictionaryRef matching = IOServiceMatching("DCPAVServiceProxy");
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (matching == NULL ||
        IOServiceGetMatchingServices(kIOMasterPortDefault, matching,
                                     &iterator) != kIOReturnSuccess)
        return NULL;

    CFDataRef match = NULL;
    CFDataRef only = NULL;
    unsigned count = 0;
    io_service_t service;
    while ((service = IOIteratorNext(iterator)) != IO_OBJECT_NULL)
    {
        if (IOAVServiceIsExternal(service))
        {
            CFTypeRef av_service = create(kCFAllocatorDefault, service);
            CFDataRef edid = NULL;
            if (av_service != NULL &&
                copy_edid(av_service, &edid) == kIOReturnSuccess &&
                edid != NULL)
                ConsiderEDIDCandidate(edid, device_name,
                                      &match, &only, &count);
            if (edid != NULL)
                CFRelease(edid);
            if (av_service != NULL)
                CFRelease(av_service);
        }
        IOObjectRelease(service);
    }
    IOObjectRelease(iterator);

    if (match != NULL)
    {
        if (only != NULL)
            CFRelease(only);
        return match;
    }
    if (count == 1)
        return only;
    if (only != NULL)
        CFRelease(only);
    return NULL;
}

static CFDataRef CopyAudioDeviceEDID(audio_output_t *p_aout,
                                     AudioDeviceID device)
{
    CFStringRef device_name = NULL;
    if (AO_GET1PROP(device, CFStringRef, &device_name,
                    kAudioObjectPropertyName,
                    kAudioObjectPropertyScopeGlobal) != VLC_SUCCESS)
        return NULL;

    CFDataRef edid = CopyPublicDisplayEDID(device_name);
    if (edid == NULL)
        edid = CopyDCPDisplayEDID(device_name);
    CFRelease(device_name);
    return edid;
}

static bool EDIDHasAudioFormat(CFDataRef data, unsigned format_code)
{
    if (!EDIDIsValid(data))
        return false;

    const uint8_t *bytes = CFDataGetBytePtr(data);
    CFIndex length = CFDataGetLength(data);
    for (CFIndex offset = 128; offset + 128 <= length; offset += 128)
    {
        const uint8_t *extension = bytes + offset;
        if (extension[0] != 0x02 || extension[2] < 4 ||
            extension[2] > 127)
            continue;

        unsigned pos = 4;
        while (pos < extension[2])
        {
            unsigned tag = extension[pos] >> 5;
            unsigned size = extension[pos] & 0x1f;
            if (pos + 1 + size > extension[2])
                break;
            if (tag == 1)
            {
                const uint8_t *block = extension + pos + 1;
                for (unsigned sad = 0; sad + 3 <= size; sad += 3)
                    if (((block[sad] >> 3) & 0x0f) == format_code)
                        return true;
            }
            pos += 1 + size;
        }
    }
    return false;
}

static bool AudioDeviceEDIDSupportsCodec(audio_output_t *p_aout,
                                         AudioDeviceID device,
                                         vlc_fourcc_t codec)
{
    unsigned edid_format;
    switch (codec)
    {
        case VLC_CODEC_A52:    edid_format = 2;  break; /* AC-3 */
        case VLC_CODEC_DTS:    edid_format = 7;  break; /* DTS core */
        case VLC_CODEC_EAC3:   edid_format = 10; break; /* DD+ */
        case VLC_CODEC_TRUEHD:
        case VLC_CODEC_MLP:    edid_format = 12; break; /* MAT/MLP */
        default:
            return true;
    }

    CFDataRef edid = CopyAudioDeviceEDID(p_aout, device);
    if (edid == NULL)
    {
        msg_Dbg(p_aout, "HDMI sink EDID unavailable; keeping the explicit "
                        "passthrough selection");
        return true;
    }

    bool supported = EDIDHasAudioFormat(edid, edid_format);
    CFRelease(edid);
    if (!supported)
        msg_Warn(p_aout, "HDMI sink EDID does not advertise codec %.4s; "
                         "falling back to decoded PCM", (const char *)&codec);
    else
        msg_Dbg(p_aout, "HDMI sink EDID advertises codec %.4s",
                        (const char *)&codec);
    return supported;
}

static void
ReportDevice(audio_output_t *p_aout, UInt32 i_id, char *name)
{
    char deviceid[10];
    sprintf(deviceid, "%i", i_id);

    aout_HotplugReport(p_aout, deviceid, name);
}

/*
 * AudioDeviceIsAHeadphone: Checks if device is a headphone
 */

static bool
AudioDeviceIsAHeadphone(audio_output_t *p_aout, AudioDeviceID i_dev_id)
{
    UInt32 defaultSize = sizeof(AudioDeviceID);

    const AudioObjectPropertyAddress defaultAddr = {
        kAudioHardwarePropertyDefaultOutputDevice,
        kAudioObjectPropertyScopeGlobal,
        kAudioObjectPropertyElementMaster
    };

    vlc_AudioObjectGetPropertyData(kAudioObjectSystemObject, &defaultAddr, 0, NULL, &defaultSize, &i_dev_id);

    AudioObjectPropertyAddress property;
    property.mSelector = kAudioDevicePropertyDataSource;
    property.mScope = kAudioDevicePropertyScopeOutput;
    property.mElement = kAudioObjectPropertyElementMaster;

    UInt32 data;
    UInt32 size = sizeof(UInt32);
    vlc_AudioObjectGetPropertyData(i_dev_id, &property, 0, NULL, &size, &data);

    /*
     'hdpn' == headphone
     'ispk' == internal speaker
     '61pd' == HDMI
     '    ' == Bluetooth accessory or AirPlay
    */

    return data == 'hdpn';
}

/*
 * AudioDeviceHasOutput: Checks if the device is actually an output device
 */
static int
AudioDeviceHasOutput(audio_output_t *p_aout, AudioDeviceID i_dev_id)
{
    size_t i_streams;
    int ret = AO_GETPROP(i_dev_id, AudioStreamID, &i_streams, NULL,
                          kAudioDevicePropertyStreams,
                          kAudioObjectPropertyScopeOutput);
    if (ret != VLC_SUCCESS || i_streams == 0)
        return FALSE;

    return TRUE;
}

static CFStringRef
CopyAudioDeviceUID(audio_output_t *p_aout, AudioDeviceID i_dev_id)
{
    if (i_dev_id == 0)
        return NULL;
    CFStringRef uid = NULL;
    if (AO_GET1PROP(i_dev_id, CFStringRef, &uid,
                    kAudioDevicePropertyDeviceUID,
                    kAudioObjectPropertyScopeGlobal) != VLC_SUCCESS)
        return NULL;
    return uid;
}

static AudioDeviceID
FindAudioDeviceByIdentity(audio_output_t *p_aout, CFStringRef wanted_uid,
                          CFStringRef wanted_name, UInt32 wanted_transport)
{
    if (wanted_uid == NULL && wanted_name == NULL)
        return 0;
    size_t count = 0;
    AudioDeviceID *devices = NULL;
    if (AO_GETPROP(kAudioObjectSystemObject, AudioDeviceID, &count, &devices,
                   kAudioHardwarePropertyDevices,
                   kAudioObjectPropertyScopeGlobal) != VLC_SUCCESS)
        return 0;

    AudioDeviceID found = 0;
    for (size_t i = 0; i < count && found == 0; ++i)
    {
        if (!AudioDeviceHasOutput(p_aout, devices[i]))
            continue;
        CFStringRef uid = CopyAudioDeviceUID(p_aout, devices[i]);
        CFStringRef name = NULL;
        UInt32 transport = 0;
        AO_GET1PROP(devices[i], CFStringRef, &name,
                    kAudioObjectPropertyName,
                    kAudioObjectPropertyScopeGlobal);
        AO_GET1PROP(devices[i], UInt32, &transport,
                    kAudioDevicePropertyTransportType,
                    kAudioObjectPropertyScopeGlobal);
        if (uid != NULL)
        {
            if (wanted_uid != NULL && CFEqual(uid, wanted_uid))
                found = devices[i];
            CFRelease(uid);
        }
        if (found == 0 && name != NULL && wanted_name != NULL &&
            transport == wanted_transport && CFEqual(name, wanted_name))
            found = devices[i];
        if (name != NULL)
            CFRelease(name);
    }
    free(devices);
    return found;
}

static void
RememberSelectedDeviceUID(audio_output_t *p_aout, AudioDeviceID i_dev_id)
{
    aout_sys_t *p_sys = p_aout->sys;
    AudioDeviceID physical = i_dev_id & ~AOUT_VAR_SPDIF_FLAG;
    CFStringRef uid = CopyAudioDeviceUID(p_aout, physical);
    CFStringRef name = NULL;
    UInt32 transport = 0;
    AO_GET1PROP(physical, CFStringRef, &name, kAudioObjectPropertyName,
                kAudioObjectPropertyScopeGlobal);
    AO_GET1PROP(physical, UInt32, &transport,
                kAudioDevicePropertyTransportType,
                kAudioObjectPropertyScopeGlobal);
    if (uid == NULL && name == NULL)
        return;
    if (p_sys->selected_device_uid != NULL)
        CFRelease(p_sys->selected_device_uid);
    if (p_sys->selected_device_name != NULL)
        CFRelease(p_sys->selected_device_name);
    p_sys->selected_device_uid = uid;
    p_sys->selected_device_name = name;
    p_sys->selected_device_transport = transport;
}

static bool
RemapSelectedHDMIDevice(audio_output_t *p_aout)
{
    aout_sys_t *p_sys = p_aout->sys;
    AudioDeviceID replacement = 0;
    if (p_sys->selected_device_transport == VLC_CA_TRANSPORT_HDMI ||
        p_sys->selected_device_transport == VLC_CA_TRANSPORT_DISPLAYPORT)
        replacement = FindAudioDeviceByIdentity(
            p_aout, p_sys->selected_device_uid, p_sys->selected_device_name,
            p_sys->selected_device_transport);

    /* An earlier transient restart may already have fallen back to the
     * built-in speakers and overwritten the selected runtime identity.  A
     * frame-packed HDMI presentation has an unambiguous destination: recover
     * the newly published HDMI/DisplayPort endpoint directly. */
    if (replacement == 0)
    {
        size_t count = 0;
        AudioDeviceID *devices = NULL;
        if (AO_GETPROP(kAudioObjectSystemObject, AudioDeviceID, &count,
                       &devices, kAudioHardwarePropertyDevices,
                       kAudioObjectPropertyScopeGlobal) == VLC_SUCCESS)
        {
            for (size_t i = 0; i < count && replacement == 0; ++i)
            {
                UInt32 transport = 0;
                if (AudioDeviceHasOutput(p_aout, devices[i]) &&
                    AO_GET1PROP(devices[i], UInt32, &transport,
                                kAudioDevicePropertyTransportType,
                                kAudioObjectPropertyScopeGlobal) == VLC_SUCCESS &&
                    (transport == VLC_CA_TRANSPORT_HDMI ||
                     transport == VLC_CA_TRANSPORT_DISPLAYPORT))
                    replacement = devices[i];
            }
            free(devices);
        }
    }
    if (replacement == 0)
        return false;
    AudioDeviceID old = p_sys->i_new_selected_dev & ~AOUT_VAR_SPDIF_FLAG;
    bool digital = (p_sys->i_new_selected_dev & AOUT_VAR_SPDIF_FLAG) != 0;
    p_sys->i_new_selected_dev = replacement |
        (digital ? AOUT_VAR_SPDIF_FLAG : 0);
    RememberSelectedDeviceUID(p_aout, p_sys->i_new_selected_dev);
    msg_Info(p_aout, "remapped republished HDMI audio device %u to %u",
             old, replacement);
    return true;
}

static void
RebuildDeviceList(audio_output_t * p_aout, UInt32 *p_id_exists)
{
    struct aout_sys_t   *p_sys = p_aout->sys;

    msg_Dbg(p_aout, "Rebuild device list");

    ReportDevice(p_aout, 0, _("System Sound Output Device"));

    /* Get number of devices */
    size_t i_devices;
    AudioDeviceID *p_devices;
    int ret = AO_GETPROP(kAudioObjectSystemObject, AudioDeviceID, &i_devices,
                         &p_devices, kAudioHardwarePropertyDevices,
                         kAudioObjectPropertyScopeGlobal);

    if (ret != VLC_SUCCESS || i_devices == 0)
    {
        msg_Err(p_aout, "No audio output devices found.");
        return;
    }
    msg_Dbg(p_aout, "found %zu audio device(s)", i_devices);

    /* setup local array */
    CFMutableArrayRef currentListOfDevices =
        CFArrayCreateMutable(kCFAllocatorDefault, 0, &kCFTypeArrayCallBacks);

    UInt32 i_id_exists;
    if (p_id_exists)
    {
        i_id_exists = *p_id_exists;
        *p_id_exists = 0;
    }
    else
        i_id_exists = 0;

    for (size_t i = 0; i < i_devices; i++)
    {
        CFStringRef device_name_ref;
        char *psz_name;
        CFIndex length;
        UInt32 i_id = p_devices[i];

        int ret = AO_GET1PROP(i_id, CFStringRef, &device_name_ref,
                              kAudioObjectPropertyName,
                              kAudioObjectPropertyScopeGlobal);
        if (ret != VLC_SUCCESS)
        {
            msg_Dbg(p_aout, "failed to get name for device %i", i_id);
            continue;
        }

        psz_name = FromCFString(device_name_ref, kCFStringEncodingUTF8);
        CFRelease(device_name_ref);

        msg_Dbg(p_aout, "DevID: %i DevName: %s", i_id, psz_name);

        if (!AudioDeviceHasOutput(p_aout, i_id))
        {
            msg_Dbg(p_aout, "this '%s' is INPUT only. skipping...", psz_name);
            free(psz_name);
            continue;
        }

        // Report back audio device in analog mode
        if (p_id_exists && i_id == i_id_exists)
            *p_id_exists = i_id;

        ReportDevice(p_aout, i_id, psz_name);
        CFNumberRef deviceNumber = CFNumberCreate(kCFAllocatorDefault,
                                                  kCFNumberSInt32Type, &i_id);
        CFArrayAppendValue(currentListOfDevices, deviceNumber);
        CFRelease(deviceNumber);

        if (AudioDeviceSupportsDigital(p_aout, i_id))
        {
            msg_Dbg(p_aout, "'%s' supports digital output", psz_name);
            char *psz_encoded_name = nil;
            asprintf(&psz_encoded_name, _("%s (Encoded Output)"), psz_name);
            i_id = i_id | AOUT_VAR_SPDIF_FLAG;
            ReportDevice(p_aout, i_id, psz_encoded_name);
            deviceNumber = CFNumberCreate(kCFAllocatorDefault,
                                          kCFNumberSInt32Type, &i_id);
            CFArrayAppendValue(currentListOfDevices, deviceNumber);
            CFRelease(deviceNumber);
            free(psz_encoded_name);

            // Report back audio device in digital mode
            if (p_id_exists && i_id == i_id_exists)
                *p_id_exists = i_id;
        }

        // TODO: only register once for each device
        ManageAudioStreamsCallback(p_aout, p_devices[i], true);

        free(psz_name);
    }

    vlc_mutex_lock(&p_sys->device_list_lock);
    CFIndex count = 0;
    if (p_sys->device_list)
        count = CFArrayGetCount(p_sys->device_list);
    CFRange newListSearchRange =
        CFRangeMake(0, CFArrayGetCount(currentListOfDevices));

    if (count > 0)
    {
        msg_Dbg(p_aout, "Looking for removed devices");
        CFNumberRef cfn_device_id;
        int i_device_id = 0;
        for (CFIndex x = 0; x < count; x++)
        {
            if (!CFArrayContainsValue(currentListOfDevices, newListSearchRange,
                                      CFArrayGetValueAtIndex(p_sys->device_list,
                                      x)))
            {
                cfn_device_id = CFArrayGetValueAtIndex(p_sys->device_list, x);
                if (cfn_device_id)
                {
                    CFNumberGetValue(cfn_device_id, kCFNumberSInt32Type,
                                     &i_device_id);
                    msg_Dbg(p_aout, "Device ID %i is not found in new array, "
                            "deleting.", i_device_id);

                    ReportDevice(p_aout, i_device_id, NULL);
                }
            }
        }
    }
    if (p_sys->device_list)
        CFRelease(p_sys->device_list);
    p_sys->device_list = CFArrayCreateCopy(kCFAllocatorDefault,
                                           currentListOfDevices);
    CFRelease(currentListOfDevices);
    vlc_mutex_unlock(&p_sys->device_list_lock);

    free(p_devices);
}

/*
 * Callback when current device is not alive anymore
 */
static OSStatus
DeviceAliveListener(AudioObjectID inObjectID,  UInt32 inNumberAddresses,
                    const AudioObjectPropertyAddress inAddresses[],
                    void *inClientData)
{
    VLC_UNUSED(inObjectID);
    VLC_UNUSED(inNumberAddresses);
    VLC_UNUSED(inAddresses);

    audio_output_t *p_aout = (audio_output_t *)inClientData;
    if (!p_aout)
        return -1;

    if (var_GetBool(p_aout->obj.libvlc,
                    "macosx-hdmi-audio-reconfiguring"))
    {
        msg_Dbg(p_aout, "HDMI display transition in progress; deferring "
                        "audio restart");
        return noErr;
    }

    msg_Warn(p_aout, "audio device died, resetting aout");
    aout_RestartRequest(p_aout, AOUT_RESTART_OUTPUT);

    return noErr;
}

/*
 * Callback when default audio device changed
 */
static OSStatus
DefaultDeviceChangedListener(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                             const AudioObjectPropertyAddress inAddresses[],
                             void *inClientData)
{
    VLC_UNUSED(inObjectID);
    VLC_UNUSED(inNumberAddresses);
    VLC_UNUSED(inAddresses);

    audio_output_t *p_aout = (audio_output_t *)inClientData;
    if (!p_aout)
        return -1;

    aout_sys_t *p_sys = p_aout->sys;

    if (!p_aout->sys->b_selected_dev_is_default)
        return noErr;

    AudioObjectID defaultDeviceID;
    int ret = AO_GET1PROP(kAudioObjectSystemObject, AudioObjectID,
                          &defaultDeviceID,
                          kAudioHardwarePropertyDefaultOutputDevice,
                          kAudioObjectPropertyScopeOutput);
    if (ret != VLC_SUCCESS)
        return -1;

    msg_Dbg(p_aout, "default device changed to %i", defaultDeviceID);

    /* Default device is changed by the os to allow other apps to play sound
     * while in digital mode. But this should not affect ourself. */
    if (p_aout->sys->b_digital)
    {
        msg_Dbg(p_aout, "ignore, as digital mode is active");
        return noErr;
    }

    vlc_mutex_lock(&p_sys->selected_device_lock);
    /* Also ignore events which announce the same device id */
    if (defaultDeviceID != p_aout->sys->i_selected_dev)
    {
        msg_Dbg(p_aout, "default device actually changed, resetting aout");
        aout_RestartRequest(p_aout, AOUT_RESTART_OUTPUT);
    }
    vlc_mutex_unlock(&p_sys->selected_device_lock);

    return noErr;
}

/*
 * Callback when physical formats for device change
 */
static OSStatus
StreamsChangedListener(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                       const AudioObjectPropertyAddress inAddresses[],
                       void *inClientData)
{
    VLC_UNUSED(inNumberAddresses);
    VLC_UNUSED(inAddresses);

    audio_output_t *p_aout = (audio_output_t *)inClientData;
    if (!p_aout)
        return -1;

    aout_sys_t *p_sys = p_aout->sys;
    if(unlikely(p_sys->b_ignore_streams_changed_callback == true))
        return 0;

    msg_Dbg(p_aout, "available physical formats for audio device changed");
    RebuildDeviceList(p_aout, NULL);

    vlc_mutex_lock(&p_sys->selected_device_lock);
    /* In this case audio has not yet started. Below code will not work and is
     * not needed here. */
    if (p_sys->i_selected_dev == 0)
    {
        vlc_mutex_unlock(&p_sys->selected_device_lock);
        return 0;
    }

    /*
     * check if changed stream id belongs to current device
     */
    size_t i_streams;
    AudioStreamID *p_streams;
    int ret = AO_GETPROP(p_sys->i_selected_dev, AudioStreamID, &i_streams,
                         &p_streams, kAudioDevicePropertyStreams,
                         kAudioObjectPropertyScopeOutput);
    if (ret != VLC_SUCCESS)
    {
        vlc_mutex_unlock(&p_sys->selected_device_lock);
        return ret;
    }
    vlc_mutex_unlock(&p_sys->selected_device_lock);

    for (size_t i = 0; i < i_streams; i++)
    {
        if (p_streams[i] == inObjectID)
        {
            /* Changing HDMI display modes can make CoreAudio announce a new
             * list of available physical formats even though the active
             * encoded stream remains valid. Restarting in that situation
             * tears down IEC 61937 and can make the decoder fall back to PCM
             * after a seek. Keep the live bitstream when CoreAudio confirms
             * that this very stream is still in a digital physical format. */
            AudioStreamBasicDescription active_format;
            int format_ret = AO_GET1PROP(inObjectID,
                                         AudioStreamBasicDescription,
                                         &active_format,
                                         kAudioStreamPropertyPhysicalFormat,
                                         kAudioObjectPropertyScopeGlobal);
            if (p_sys->b_digital && p_sys->i_stream_id == inObjectID
             && format_ret == VLC_SUCCESS
             && IsAudioFormatDigital(active_format.mFormatID))
            {
                msg_Dbg(p_aout, "digital stream is still valid; keeping "
                         "the active passthrough output");
            }
            else
            {
                msg_Dbg(p_aout, "Restart aout as this affects current device");
                aout_RestartRequest(p_aout, AOUT_RESTART_OUTPUT);
            }
            break;
        }
    }
    free(p_streams);

    return noErr;
}

/*
 * Callback when device list changed
 */
static OSStatus
DevicesListener(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                const AudioObjectPropertyAddress inAddresses[],
                void *inClientData)
{
    VLC_UNUSED(inObjectID);
    VLC_UNUSED(inNumberAddresses);
    VLC_UNUSED(inAddresses);

    audio_output_t *p_aout = (audio_output_t *)inClientData;
    if (!p_aout)
        return -1;
    aout_sys_t *p_sys = p_aout->sys;

    msg_Dbg(p_aout, "audio device configuration changed, resetting cache");
    RebuildDeviceList(p_aout, NULL);

    vlc_mutex_lock(&p_sys->selected_device_lock);
    vlc_mutex_lock(&p_sys->device_list_lock);
    CFNumberRef selectedDevice =
        CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type,
                       &p_sys->i_selected_dev);
    CFRange range = CFRangeMake(0, CFArrayGetCount(p_sys->device_list));
    if (!CFArrayContainsValue(p_sys->device_list, range, selectedDevice) &&
        !var_GetBool(p_aout->obj.libvlc,
                     "macosx-hdmi-audio-reconfiguring"))
        aout_RestartRequest(p_aout, AOUT_RESTART_OUTPUT);
    CFRelease(selectedDevice);
    vlc_mutex_unlock(&p_sys->device_list_lock);
    vlc_mutex_unlock(&p_sys->selected_device_lock);

    return noErr;
}

static int
HDMIDisplayAudioGenerationChanged(vlc_object_t *object, const char *name,
                                  vlc_value_t old_value,
                                  vlc_value_t new_value, void *opaque)
{
    VLC_UNUSED(object);
    VLC_UNUSED(name);
    VLC_UNUSED(old_value);
    VLC_UNUSED(new_value);
    audio_output_t *p_aout = opaque;

    /* The display endpoint can lag WindowServer's final mode transaction.
     * Match its stable CoreAudio UID rather than the disposable object ID. */
    for (unsigned i = 0; i < 30; ++i)
    {
        if (RemapSelectedHDMIDevice(p_aout))
            break;
        usleep(100000);
    }
    aout_RestartRequest(p_aout, AOUT_RESTART_OUTPUT);
    return VLC_SUCCESS;
}

/*
 * StreamListener: check whether the device's physical format change is complete
 */
static OSStatus
StreamListener(AudioObjectID inObjectID, UInt32 inNumberAddresses,
               const AudioObjectPropertyAddress inAddresses[],
               void *inClientData)
{
    OSStatus err = noErr;
    struct { vlc_mutex_t lock; vlc_cond_t cond; } * w = inClientData;

    VLC_UNUSED(inObjectID);

    for (unsigned int i = 0; i < inNumberAddresses; i++)
    {
        if (inAddresses[i].mSelector == kAudioStreamPropertyPhysicalFormat)
        {
            int canc = vlc_savecancel();
            vlc_mutex_lock(&w->lock);
            vlc_cond_signal(&w->cond);
            vlc_mutex_unlock(&w->lock);
            vlc_restorecancel(canc);
            break;
        }
    }
    return err;
}

/*
 * AudioStreamChangeFormat: switch stream format based on the provided
 * description
 */
static int
AudioStreamChangeFormat(audio_output_t *p_aout, AudioStreamID i_stream_id,
                        AudioStreamBasicDescription change_format)
{
    int retValue = false;

    struct { vlc_mutex_t lock; vlc_cond_t cond; } w;

    msg_Dbg(p_aout, STREAM_FORMAT_MSG("setting stream format: ", change_format));

    /* Condition because SetProperty is asynchronous */
    vlc_cond_init(&w.cond);
    vlc_mutex_init(&w.lock);
    vlc_mutex_lock(&w.lock);

    /* Install the callback */
    int ret = AO_UPDATELISTENER(i_stream_id, true, StreamListener, &w,
                                kAudioStreamPropertyPhysicalFormat,
                                kAudioObjectPropertyScopeGlobal);

    if (ret != VLC_SUCCESS)
    {
        retValue = false;
        goto out;
    }

    /* change the format */
    ret = AO_SETPROP(i_stream_id, sizeof(AudioStreamBasicDescription),
                     &change_format, kAudioStreamPropertyPhysicalFormat,
                     kAudioObjectPropertyScopeGlobal);
    if (ret != VLC_SUCCESS)
    {
        retValue = false;
        goto out;
    }

    /* The AudioStreamSetProperty is not only asynchronous (requiring the
     * locks) it is also not atomic in its behaviour.  Therefore we check 9
     * times before we really give up.
     */
    for (int i = 0; i < 9; i++)
    {
        /* Callback is not always invoked. So first check if format is already
         * set. */
        if (i > 0)
        {
            vlc_tick_t timeout = mdate() + 500000;
            if (vlc_cond_timedwait(&w.cond, &w.lock, timeout))
                msg_Dbg(p_aout, "reached timeout");
        }

        AudioStreamBasicDescription actual_format;
        int ret = AO_GET1PROP(i_stream_id, AudioStreamBasicDescription,
                              &actual_format,
                              kAudioStreamPropertyPhysicalFormat,
                              kAudioObjectPropertyScopeGlobal);

        if (ret != VLC_SUCCESS)
            continue;

        msg_Dbg(p_aout, STREAM_FORMAT_MSG("actual format in use: ",
                actual_format));
        if (actual_format.mSampleRate == change_format.mSampleRate &&
            actual_format.mFormatID == change_format.mFormatID &&
            actual_format.mFramesPerPacket == change_format.mFramesPerPacket)
        {
            /* The right format is now active */
            retValue = true;
            break;
        }

        /* We need to check again */
    }

out:
    vlc_mutex_unlock(&w.lock);

    /* Removing the property listener */
    ret = AO_UPDATELISTENER(i_stream_id, false, StreamListener, &w,
                            kAudioStreamPropertyPhysicalFormat,
                            kAudioObjectPropertyScopeGlobal);
    if (ret != VLC_SUCCESS)
        retValue = false;

    vlc_mutex_destroy(&w.lock);
    vlc_cond_destroy(&w.cond);

    return retValue;
}

#pragma mark -
#pragma mark core interaction

static int
SwitchAudioDevice(audio_output_t *p_aout, const char *name)
{
    struct aout_sys_t *p_sys = p_aout->sys;

    if (name)
        p_sys->i_new_selected_dev = atoi(name);
    else
        p_sys->i_new_selected_dev = 0;

    p_sys->i_new_selected_dev = p_sys->i_new_selected_dev;
    RememberSelectedDeviceUID(p_aout, p_sys->i_new_selected_dev);

    aout_DeviceReport(p_aout, name);
    aout_RestartRequest(p_aout, AOUT_RESTART_OUTPUT);

    return 0;
}

static int
VolumeSet(audio_output_t * p_aout, float volume)
{
    struct aout_sys_t *p_sys = p_aout->sys;
    OSStatus ostatus = 0;

    if (p_sys->b_digital)
        return VLC_EGENERIC;

    p_sys->f_volume = volume;
    aout_VolumeReport(p_aout, volume);

    /* Set volume for output unit */
    if (!p_sys->b_mute)
    {
        ostatus = AudioUnitSetParameter(p_sys->au_unit,
                                        kHALOutputParam_Volume,
                                        kAudioUnitScope_Global,
                                        0,
                                        volume * volume * volume,
                                        0);
    }

    if (var_InheritBool(p_aout, "volume-save"))
        config_PutInt(p_aout, "auhal-volume",
                      lroundf(volume * AOUT_VOLUME_DEFAULT));

    return ostatus;
}

static int
MuteSet(audio_output_t * p_aout, bool mute)
{
    struct aout_sys_t *p_sys = p_aout->sys;

    if(p_sys->b_digital)
        return VLC_EGENERIC;

    p_sys->b_mute = mute;
    aout_MuteReport(p_aout, mute);

    float volume = .0;
    if (!mute)
        volume = p_sys->f_volume;

    OSStatus err =
        AudioUnitSetParameter(p_sys->au_unit, kHALOutputParam_Volume,
                              kAudioUnitScope_Global, 0,
                              volume * volume * volume, 0);

    return err == noErr ? VLC_SUCCESS : VLC_EGENERIC;
}

#pragma mark -
#pragma mark actual playback

static inline void
DigitalPauseSet16(aout_sys_t *p_sys, size_t i_offset, uint16_t i_value,
                  bool b_big_endian)
{
    if (b_big_endian)
        SetWBE(&p_sys->p_pause_burst[i_offset], i_value);
    else
        SetWLE(&p_sys->p_pause_burst[i_offset], i_value);
}

/* Called under the CoreAudio render lock: no allocation, logging or system
 * call is allowed here. The prebuilt IEC 61937 pause period is simply carried
 * over between callbacks, including callbacks shorter than one period. */
static void
FillDigitalPause(audio_output_t *p_aout, uint8_t *p_output, size_t i_size,
                 bool b_new_gap)
{
    aout_sys_t *p_sys = p_aout->sys;

    if (unlikely(p_sys->i_pause_burst_size == 0))
    {
        memset(p_output, 0, i_size);
        return;
    }

    if (b_new_gap)
        p_sys->i_pause_burst_offset = 0;

    while (i_size > 0)
    {
        size_t i_copy = __MIN(i_size, p_sys->i_pause_burst_size
                                    - p_sys->i_pause_burst_offset);
        memcpy(p_output,
               &p_sys->p_pause_burst[p_sys->i_pause_burst_offset], i_copy);
        p_output += i_copy;
        i_size -= i_copy;
        p_sys->i_pause_burst_offset += i_copy;
        if (p_sys->i_pause_burst_offset == p_sys->i_pause_burst_size)
            p_sys->i_pause_burst_offset = 0;
    }
}

/* IEC 61937-2 pause burst (data type 3). Kodi's AudioEngine uses a repetition
 * period of four carrier frames for TrueHD/E-AC-3 and three for the classic
 * formats. Keeping the period in AUHAL lets the common renderer remain
 * format-agnostic while replacing its otherwise-invalid PCM zero padding. */
static void
ConfigureDigitalPause(audio_output_t *p_aout, const audio_sample_format_t *fmt,
                      vlc_fourcc_t i_source_format, unsigned i_source_rate,
                      unsigned i_source_frame_length)
{
    aout_sys_t *p_sys = p_aout->sys;
    unsigned i_repetition = 3;
    unsigned i_duration_ms;

    switch (i_source_format)
    {
        case VLC_CODEC_TRUEHD:
        case VLC_CODEC_MLP:
            i_repetition = 4;
            i_duration_ms = 20; /* one 61440-byte MAT frame at 192 kHz HBR */
            break;
        case VLC_CODEC_EAC3:
            i_repetition = 4;
            i_duration_ms = i_source_rate != 0
                          ? 6144 * 1000 / i_source_rate / 4 : 32;
            break;
        case VLC_CODEC_A52:
            i_duration_ms = 32;
            break;
        default:
            i_duration_ms = i_source_rate != 0 && i_source_frame_length != 0
                          ? i_source_frame_length * 1000 / i_source_rate : 11;
            break;
    }
    if (i_duration_ms == 0)
        i_duration_ms = 1;

    const size_t i_carrier_frame = fmt->i_frame_length != 0
                                 ? fmt->i_bytes_per_frame / fmt->i_frame_length
                                 : 0;
    const size_t i_period = i_repetition * i_carrier_frame;
    if (i_period < 10 || i_period > sizeof(p_sys->p_pause_burst))
    {
        p_sys->i_pause_burst_size = 0;
        p_sys->c.pf_fill_silence = NULL;
        msg_Warn(p_aout, "unsupported IEC 61937 pause period %zu", i_period);
        return;
    }

    const bool b_big_endian = fmt->i_format == VLC_CODEC_SPDIFB;
    memset(p_sys->p_pause_burst, 0, i_period);
    DigitalPauseSet16(p_sys, 0, 0xf872, b_big_endian);
    DigitalPauseSet16(p_sys, 2, 0x4e1f, b_big_endian);
    DigitalPauseSet16(p_sys, 4, 0x0003, b_big_endian);
    DigitalPauseSet16(p_sys, 6, 32, b_big_endian);
    uint64_t i_gap = (uint64_t)i_source_rate * i_duration_ms / 1000;
    DigitalPauseSet16(p_sys, 8, i_gap > UINT16_MAX ? UINT16_MAX : i_gap,
                      b_big_endian);

    p_sys->i_pause_burst_size = i_period;
    p_sys->i_pause_burst_offset = 0;
    p_sys->c.pf_fill_silence = FillDigitalPause;
    msg_Dbg(p_aout, "IEC 61937 pause carrier: %zu-byte period, %u ms gap",
            i_period, i_duration_ms);
}

/*
 * RenderCallbackSPDIF: callback for SPDIF audio output
 */
static OSStatus
RenderCallbackSPDIF(AudioDeviceID inDevice, const AudioTimeStamp * inNow,
                    const AudioBufferList * inInputData,
                    const AudioTimeStamp * inInputTime,
                    AudioBufferList * outOutputData,
                    const AudioTimeStamp * inOutputTime, void *p_data)
{
    VLC_UNUSED(inNow);
    VLC_UNUSED(inDevice);
    VLC_UNUSED(inInputData);
    VLC_UNUSED(inInputTime);

    audio_output_t * p_aout = p_data;
    aout_sys_t *p_sys = p_aout->sys;
    uint8_t *p_output = outOutputData->mBuffers[p_sys->i_stream_index].mData;
    size_t i_size = outOutputData->mBuffers[p_sys->i_stream_index].mDataByteSize;

    /* AudioDeviceIOProc gives both the callback time and the predicted time
     * at which the first frame of this output buffer reaches the device.
     * Scheduling compressed HDMI from inNow hides the HAL/transport queue;
     * that queue can be rebuilt with a different depth after a seek while
     * VLC continues to report a perfect clock.  Use the actual output time
     * when the driver provides it, falling back for legacy CoreAudio drivers
     * which only implement inNow.  The separate device/stream latency passed
     * to ca_Initialize() is the same additional frame count used by Kodi's
     * Darwin sink; CoreAudio does not include it in this timestamp delta. */
    uint64_t i_host_time;
    if (inOutputTime != NULL
     && (inOutputTime->mFlags & kAudioTimeStampHostTimeValid))
        i_host_time = inOutputTime->mHostTime;
    else if (inNow != NULL && (inNow->mFlags & kAudioTimeStampHostTimeValid))
        i_host_time = inNow->mHostTime;
    else
        i_host_time = mach_absolute_time();

    ca_Render(p_aout, 0, i_host_time, p_output, i_size);

    return noErr;
}

#pragma mark -
#pragma mark initialization

static void
WarnConfiguration(audio_output_t *p_aout)
{
    struct aout_sys_t *p_sys = p_aout->sys;
    char *warned_devices = var_CreateGetNonEmptyString(p_aout, "auhal-warned-devices");
    bool dev_is_warned = false;
    unsigned dev_count = 0;

    /* Check if the actual device was already warned */
    if (warned_devices)
    {
        char *dup = strdup(warned_devices);
        if (dup)
        {
            char *savetpr;
            for (const char *dev = strtok_r(dup, ";", &savetpr);
                 dev != NULL && !dev_is_warned;
                 dev = strtok_r(NULL, ";", &savetpr))
            {
                dev_count++;
                int devid = atoi(dev);
                if (devid >= 0 && (unsigned) devid == p_sys->i_selected_dev)
                {
                    dev_is_warned = true;
                    break;
                }
            }
            free(dup);
        }
    }

    /* Warn only one time per device */
    if (!dev_is_warned)
    {
        msg_Warn(p_aout, "You should configure your speaker layout with "
                "Audio Midi Setup in /Applications/Utilities. VLC will "
                "output Stereo only.");
        vlc_dialog_display_error(p_aout,
            _("Audio device is not configured"), "%s",
            _("You should configure your speaker layout with "
            "\"Audio Midi Setup\" in /Applications/"
            "Utilities. VLC will output Stereo only."));

        /* Don't save too many devices */
        if (dev_count >= 10)
        {
            char *end = strrchr(warned_devices, ';');
            if (end)
                *end = 0;
        }

        /* Add the actual device to the list of warned devices */
        char *new_warned_devices;
        if (asprintf(&new_warned_devices, "%u%s%s", p_sys->i_selected_dev,
                     warned_devices ? ";" : "",
                     warned_devices ? warned_devices : "") != -1)
        {
            config_PutPsz(p_aout, "auhal-warned-devices", new_warned_devices);
            var_SetString(p_aout, "auhal-warned-devices", new_warned_devices);
            free(new_warned_devices);
        }
    }
    free(warned_devices);
}

/*
 * StartAnalog: open and setup a HAL AudioUnit to do PCM audio output
 */
/* Switch the device nominal sample rate to the stream rate when the
 * hardware supports it: this removes both VLC's resampler and the AUHAL
 * internal converter from the pipeline. Returns the rate to restore on
 * Stop, or 0 when nothing was changed. */
static Float64
SetDeviceRate(audio_output_t *p_aout, AudioObjectID i_dev, unsigned i_rate)
{
    Float64 f_current = 0;
    if (AO_GET1PROP(i_dev, Float64, &f_current,
                    kAudioDevicePropertyNominalSampleRate,
                    kAudioObjectPropertyScopeGlobal) != VLC_SUCCESS)
        return 0;

    if ((unsigned)(f_current + 0.5) == i_rate)
        return 0;

    UInt32 i_ranges = 0;
    AudioValueRange *p_ranges = NULL;
    if (AO_GETPROP(i_dev, AudioValueRange, &i_ranges, &p_ranges,
                   kAudioDevicePropertyAvailableNominalSampleRates,
                   kAudioObjectPropertyScopeGlobal) != VLC_SUCCESS)
        return 0;

    bool b_supported = false;
    for (UInt32 i = 0; i < i_ranges && !b_supported; i++)
        b_supported = i_rate >= (unsigned)p_ranges[i].mMinimum
                   && i_rate <= (unsigned)p_ranges[i].mMaximum;
    free(p_ranges);

    if (!b_supported)
    {
        msg_Dbg(p_aout, "device cannot run at %u Hz, will resample", i_rate);
        return 0;
    }

    Float64 f_rate = i_rate;
    int ret = AO_SETPROP(i_dev, sizeof(f_rate), &f_rate,
                         kAudioDevicePropertyNominalSampleRate,
                         kAudioObjectPropertyScopeGlobal)
    if (ret != VLC_SUCCESS)
        return 0;

    /* The switch is asynchronous on some HALs: give it a moment */
    for (int i = 0; i < 20; i++)
    {
        Float64 f_check = 0;
        if (AO_GET1PROP(i_dev, Float64, &f_check,
                        kAudioDevicePropertyNominalSampleRate,
                        kAudioObjectPropertyScopeGlobal) == VLC_SUCCESS
         && (unsigned)(f_check + 0.5) == i_rate)
            break;
        msleep(10000);
    }

    msg_Dbg(p_aout, "switched device from %u Hz to %u Hz",
            (unsigned)(f_current + 0.5), i_rate);
    return f_current;
}

static int
StartAnalog(audio_output_t *p_aout, audio_sample_format_t *fmt)
{
    struct aout_sys_t           *p_sys = p_aout->sys;
    OSStatus                    err = noErr;
    UInt32                      i_param_size;
    AudioChannelLayout          *layout = NULL;

    if (aout_FormatNbChannels(fmt) == 0)
        return VLC_EGENERIC;

    p_sys->c.pf_fill_silence = NULL;
    p_sys->c.b_silence_started = false;
    p_sys->i_pause_burst_size = 0;

    p_sys->f_revert_rate =
        SetDeviceRate(p_aout, p_sys->i_selected_dev, fmt->i_rate);

    p_sys->au_unit = au_NewOutputInstance(p_aout, kAudioUnitSubType_HALOutput);
    if (p_sys->au_unit == NULL)
        return VLC_EGENERIC;

    p_aout->current_sink_info.headphones = AudioDeviceIsAHeadphone(p_aout, p_sys->i_selected_dev);

    /* Set the device we will use for this output unit */
    err = AudioUnitSetProperty(p_sys->au_unit,
                               kAudioOutputUnitProperty_CurrentDevice,
                               kAudioUnitScope_Global, 0,
                               &p_sys->i_selected_dev, sizeof(AudioObjectID));

    if (err != noErr)
    {
        ca_LogErr("cannot select audio output device, PCM output failed");
        goto error;
    }

    /* Get the channel layout of the device side of the unit (vlc -> unit ->
     * device) */
    err = AudioUnitGetPropertyInfo(p_sys->au_unit,
                                   kAudioDevicePropertyPreferredChannelLayout,
                                   kAudioUnitScope_Output, 0, &i_param_size,
                                   NULL);
    if (err == noErr)
    {
        layout = (AudioChannelLayout *)malloc(i_param_size);
        if (layout == NULL)
            goto error;

        OSStatus err =
            AudioUnitGetProperty(p_sys->au_unit,
                                 kAudioDevicePropertyPreferredChannelLayout,
                                 kAudioUnitScope_Output, 0, layout,
                                 &i_param_size);
        if (err != noErr)
            goto error;
    }
    else
    {
        ca_LogWarn("device driver does not support "
                   "kAudioDevicePropertyPreferredChannelLayout - using stereo");

        /* ★★★★ Tenir la promesse du message ci-dessus — elle n'était écrite
         * NULLE PART. Sans disposition de périphérique, au_Initialize prend sa
         * branche `else` : elle garde la disposition d'ENTRÉE (« VLC keeping
         * the same input layout ») et ouvre une unité audio à SIX canaux sur
         * une sortie qui n'en reproduit que deux. La voie CENTRALE part alors
         * dans le vide — et sur un DVD c'est là que vivent les dialogues.
         *
         * Constaté sur iBook G3 / Panther, piste anglaise AC-3 5.1 : musique
         * et bruits de fond parfaitement audibles, dialogues absents, dès la
         * première seconde et sans aucun déplacement. Le pilote de ces
         * machines ne connaît pas la propriété (OSStatus -10879) et leur
         * sortie intégrée est stéréo.
         *
         * On force donc le format en stéréo et on laisse le cœur faire le
         * mixage descendant, qui lui sait replier la voie centrale sur les
         * deux voies avant. Même parti pris que le repli pré-10.3 de
         * MapOutputLayout(), quelques lignes plus loin dans
         * coreaudio_common.c. */
        fmt->i_physical_channels = AOUT_CHANS_STEREO;
        aout_FormatPrepare(fmt);
    }

    /* Do the last VLC aout setups */
    bool warn_configuration;
    int ret = au_Initialize(p_aout, p_sys->au_unit, fmt, layout, 0,
                            &warn_configuration);
    if (ret != VLC_SUCCESS)
        goto error;

    err = AudioOutputUnitStart(p_sys->au_unit);
    if (err != noErr)
    {
        ca_LogErr("AudioUnitStart failed");
        au_Uninitialize(p_aout, p_sys->au_unit);
        goto error;
    }

    /* Set volume for output unit */
    VolumeSet(p_aout, p_sys->f_volume);
    MuteSet(p_aout, p_sys->b_mute);

    free(layout);

    if (warn_configuration)
        WarnConfiguration(p_aout);

    return VLC_SUCCESS;
error:
    au_DisposeOutputInstance(p_sys->au_unit);
    free(layout);
    return VLC_EGENERIC;
}

/*
 * StartSPDIF: Setup an encoded digital stream (SPDIF) output
 */
static int
StartSPDIF(audio_output_t * p_aout, audio_sample_format_t *fmt)
{
    struct aout_sys_t *p_sys = p_aout->sys;
    int ret;

    const vlc_fourcc_t source_format = fmt->i_format;
    const unsigned source_rate = fmt->i_rate;
    const unsigned source_frame_length = fmt->i_frame_length;
    const bool b_dtshd_requested = source_format == VLC_CODEC_DTS
                                && var_GetBool(p_aout, "dtshd");
    bool b_dtshd = b_dtshd_requested;

    /* CoreAudio exposes AC-3/IEC 60958 and, on recent HDMI devices, E-AC-3
     * and MAT physical formats.  MAT is a TrueHD transport; its HBR-sized
     * ASBD is not evidence of a DTS-HD IEC 61937 carrier.  Feeding DTS-HD
     * type-IV bursts to that format succeeds locally but produces silence at
     * the receiver (unlike AC-3 on the same link).  Kodi's Darwin sink makes
     * the same distinction and advertises DTSHD_CORE, not DTSHD, for its
     * CoreAudio encoded stream.
     *
     * A DTS-HD frame contains a standard DTS core.  When the user enabled
     * core DTS passthrough, select the regular 48 kHz IEC 60958 carrier; the
     * tospdif converter will then discard the HD extension and transmit the
     * core without decoding it.  Keep native DTS-HD enabled on outputs such
     * as WASAPI, where the OS exposes an explicit DTS-HD carrier. */
    if (b_dtshd_requested)
    {
        if (!var_InheritBool(p_aout, "spdif-dts"))
        {
            msg_Warn(p_aout, "CoreAudio has no native DTS-HD carrier and DTS "
                             "core passthrough is disabled; falling back to "
                             "decoded audio");
            return VLC_EGENERIC;
        }

        msg_Warn(p_aout, "CoreAudio has no native DTS-HD carrier; passing the "
                         "embedded DTS core through HDMI instead");
        b_dtshd = false;
    }

    /* Legacy DVD-Audio MLP and Dolby TrueHD share CTA audio format code 12,
     * but current CoreAudio HDMI sinks expose only the Dolby MAT carrier in
     * practice. The connected sink advertises that SAD and decodes TrueHD,
     * yet produces silence for a structurally valid MLP stream carried by the
     * same MAT writer. Prefer the normal PCM decoder for standalone MLP on
     * macOS; native platforms remain free to pass it through. */
    if (source_format == VLC_CODEC_MLP)
    {
        msg_Warn(p_aout, "CoreAudio MAT passthrough is limited to Dolby "
                         "TrueHD; decoding legacy MLP to PCM");
        return VLC_EGENERIC;
    }

    /* A CoreAudio carrier alone is not proof that the HDMI sink accepts the
     * encoded codec. Reject unsupported families before hogging/changing the
     * device; decoder module selection will then continue with the normal PCM
     * decoder. DTS-HD deliberately checks DTS here because macOS transmits
     * its embedded core. */
    if (!AudioDeviceEDIDSupportsCodec(p_aout, p_sys->i_selected_dev,
                                      source_format))
        return VLC_EGENERIC;

    size_t i_encoded_packet_size = AOUT_SPDIF_SIZE;
    uint64_t i_required_bytes_per_second;
    switch (source_format)
    {
        case VLC_CODEC_EAC3:
            /* IEC 61937-3: four times the classic 48 kHz stereo carrier. */
            i_required_bytes_per_second = 192000 * 4;
            i_encoded_packet_size = AOUT_SPDIF_SIZE * 4;
            break;
        case VLC_CODEC_TRUEHD:
        case VLC_CODEC_MLP:
            /* MAT and DTS-HD use the eight-channel 192 kHz HBR payload
             * bandwidth (CoreAudio may describe the same wire rate as a
             * 768 kHz, two-channel carrier). */
            i_required_bytes_per_second = 192000 * 8 * 2;
            i_encoded_packet_size = 61440;
            break;
        case VLC_CODEC_DTS:
            i_required_bytes_per_second = b_dtshd
                                        ? 192000 * 8 * 2 : 48000 * 2 * 2;
            if (source_frame_length != 0)
            {
                uint64_t i_packet = (uint64_t)source_frame_length * 4;
                if (b_dtshd && source_rate != 0)
                    /* DTS-HD type IV periods are counted as 768 kHz stereo
                     * IEC 60958 frames (four bytes each), even when the HDMI
                     * sink describes the equivalent wire as 192 kHz/8ch. */
                    i_packet = 768000 * (uint64_t)source_frame_length
                             / source_rate * 4;
                if (i_packet > 0 && i_packet <= SIZE_MAX)
                    i_encoded_packet_size = i_packet;
            }
            break;
        default:
            i_required_bytes_per_second = 48000 * 2 * 2;
            break;
    }

    /* Check if device supports digital */
    if (!AudioDeviceSupportsDigital(p_aout, p_sys->i_selected_dev))
    {
        msg_Dbg(p_aout, "Audio device supports PCM mode only");
        return VLC_EGENERIC;
    }

    ret = AO_GET1PROP(p_sys->i_selected_dev, pid_t, &p_sys->i_hog_pid,
                      kAudioDevicePropertyHogMode,
                      kAudioObjectPropertyScopeOutput);
    if (ret != VLC_SUCCESS)
    {
        /* This is not a fatal error. Some drivers simply don't support this
         * property */
        p_sys->i_hog_pid = -1;
    }

    if (p_sys->i_hog_pid != -1 && p_sys->i_hog_pid != getpid())
    {
        msg_Err(p_aout, "Selected audio device is exclusively in use by another"
                " program.");
        vlc_dialog_display_error(p_aout, _("Audio output failed"), "%s",
            _("The selected audio output device is exclusively in "
            "use by another program."));
        return VLC_EGENERIC;
    }

    AudioStreamBasicDescription desired_stream_format;
    memset(&desired_stream_format, 0, sizeof(desired_stream_format));

    /* Start doing the SPDIF setup process */
    p_sys->b_digital = true;

    /* Hog the device */
    p_sys->i_hog_pid = getpid();

    /*
     * HACK: On 10.6, auhal will trigger the streams changed callback when
     * calling below line, directly in the same thread. This call needs to be
     * ignored to avoid endless restarting.
     */
    p_sys->b_ignore_streams_changed_callback = true;
    ret = AO_SETPROP(p_sys->i_selected_dev, sizeof(p_sys->i_hog_pid),
                     &p_sys->i_hog_pid, kAudioDevicePropertyHogMode,
                     kAudioObjectPropertyScopeOutput);
    p_sys->b_ignore_streams_changed_callback = false;

    if (ret != VLC_SUCCESS)
        return ret;

    if (AO_HASPROP(p_sys->i_selected_dev, kAudioDevicePropertySupportsMixing,
                   kAudioObjectPropertyScopeGlobal))
    {
        /* Set mixable to false if we are allowed to */
        UInt32 b_mix;
        bool b_writeable = AO_ISPROPSETTABLE(p_sys->i_selected_dev,
                                             kAudioDevicePropertySupportsMixing,
                                             kAudioObjectPropertyScopeGlobal);

        ret = AO_GET1PROP(p_sys->i_selected_dev, UInt32, &b_mix,
                          kAudioDevicePropertySupportsMixing,
                          kAudioObjectPropertyScopeGlobal);
        if (ret == VLC_SUCCESS && b_writeable)
        {
            b_mix = 0;
            ret = AO_SETPROP(p_sys->i_selected_dev, sizeof(UInt32), &b_mix,
                             kAudioDevicePropertySupportsMixing,
                             kAudioObjectPropertyScopeGlobal);
            p_sys->b_changed_mixing = true;
        }

        if (ret != VLC_SUCCESS)
        {
            msg_Err(p_aout, "failed to set mixmode");
            return ret;
        }
    }

    /* Get a list of all the streams on this device */
    size_t i_streams;
    AudioStreamID *p_streams;
    ret = AO_GETPROP(p_sys->i_selected_dev, AudioStreamID, &i_streams,
                     &p_streams, kAudioDevicePropertyStreams,
                     kAudioObjectPropertyScopeOutput);
    if (ret != VLC_SUCCESS)
        return ret;

    for (unsigned i = 0; i < i_streams && p_sys->i_stream_index < 0 ; i++)
    {
        /* Find a stream with a cac3 stream */
        bool b_digital = false;

        /* Retrieve all the stream formats supported by each output stream */
        size_t i_formats;
        AudioStreamRangedDescription *p_format_list;
        int ret = AO_GETPROP(p_streams[i], AudioStreamRangedDescription,
                             &i_formats, &p_format_list,
                             kAudioStreamPropertyAvailablePhysicalFormats,
                             kAudioObjectPropertyScopeGlobal);
        if (ret != VLC_SUCCESS)
            continue;

        /* Check if one of the supported formats is a digital format */
        for (size_t j = 0; j < i_formats; j++)
        {
            if (IsAudioFormatDigital(p_format_list[j].mFormat.mFormatID))
            {
                b_digital = true;
                break;
            }
        }

        if (b_digital)
        {
            /* if this stream supports a digital (cac3) format, then go set it.
             * */
            int i_requested_rate_format = -1;
            int i_current_rate_format = -1;
            int i_backup_rate_format = -1;
            uint64_t i_backup_bytes_per_second = UINT64_MAX;

            if (!p_sys->b_revert)
            {
                /* Retrieve the original format of this stream first if not
                 * done so already */
                AudioStreamBasicDescription current_streamformat;
                int ret = AO_GET1PROP(p_streams[i], AudioStreamBasicDescription,
                                      &current_streamformat,
                                      kAudioStreamPropertyPhysicalFormat,
                                      kAudioObjectPropertyScopeGlobal);
                if (ret != VLC_SUCCESS)
                    continue;

                /*
                 * Only the first found format id is accepted. In case of
                 * another id later on, we still use the already saved one.
                 * This can happen if the user plugs in a spdif cable while a
                 * stream is already playing. Then, auhal already misleadingly
                 * reports an ac3 format here whereas the original format
                 * should be still pcm.
                 */
                if (p_sys->sfmt_revert.mFormatID > 0
                 && p_sys->sfmt_revert.mFormatID != current_streamformat.mFormatID
                 && p_streams[i] == p_sys->i_stream_id)
                {
                    msg_Warn(p_aout, STREAM_FORMAT_MSG("Detected current stream"
                             " format: ", current_streamformat));
                    msg_Warn(p_aout, "... there is another stream format "
                             "already stored, the current one is ignored");
                }
                else
                    p_sys->sfmt_revert = current_streamformat;

                p_sys->b_revert = true;
            }

            p_sys->i_stream_id = p_streams[i];
            p_sys->i_stream_index = i;

            for (size_t j = 0; j < i_formats; j++)
            {
                if (IsAudioFormatDigital(p_format_list[j].mFormat.mFormatID))
                {
                    const AudioStreamBasicDescription *candidate =
                        &p_format_list[j].mFormat;
                    uint64_t i_bytes_per_second =
                        candidate->mBytesPerFrame * candidate->mSampleRate;
                    if (i_bytes_per_second == 0
                     && candidate->mFramesPerPacket != 0)
                        i_bytes_per_second = candidate->mBytesPerPacket
                                           * candidate->mSampleRate
                                           / candidate->mFramesPerPacket;

                    /* A 48 kHz AC-3 carrier is a valid encoded format but it
                     * physically cannot carry E-AC-3, MAT or DTS-HD. */
                    if (i_bytes_per_second < i_required_bytes_per_second)
                        continue;

                    if (p_format_list[j].mFormat.mSampleRate == fmt->i_rate)
                    {
                        i_requested_rate_format = j;
                        break;
                    }
                    else if (p_format_list[j].mFormat.mSampleRate ==
                             p_sys->sfmt_revert.mSampleRate)
                        i_current_rate_format = j;
                    else
                    {
                        if (i_backup_rate_format < 0
                         || i_bytes_per_second < i_backup_bytes_per_second)
                        {
                            i_backup_rate_format = j;
                            i_backup_bytes_per_second = i_bytes_per_second;
                        }
                    }
                }

            }

            if (i_requested_rate_format >= 0)
            {
                /* We prefer to output at the samplerate of the original audio */
                desired_stream_format =
                    p_format_list[i_requested_rate_format].mFormat;
            }
            else if (i_current_rate_format >= 0)
            {
                /* If not possible, we will try to use the current samplerate
                 * of the device */
                desired_stream_format =
                    p_format_list[i_current_rate_format].mFormat;
            }
            else
            {
                /* Pick the narrowest carrier that can represent the payload:
                 * 192 kHz for E-AC-3, HBR for TrueHD/DTS-HD. */
                if (i_backup_rate_format < 0)
                    continue;
                desired_stream_format =
                    p_format_list[i_backup_rate_format].mFormat;
            }
        }
        free(p_format_list);
    }
    free(p_streams);

    msg_Dbg(p_aout, STREAM_FORMAT_MSG("original stream format: ",
            p_sys->sfmt_revert));

    p_sys->b_ignore_streams_changed_callback = true;
    bool b_format_changed = AudioStreamChangeFormat(p_aout,
                                                     p_sys->i_stream_id,
                                                     desired_stream_format);
    p_sys->b_ignore_streams_changed_callback = false;
    if (!b_format_changed)
    {
        msg_Err(p_aout, "failed to change stream format for SPDIF output");
        return VLC_EGENERIC;
    }

    /* Set the format flags. CoreAudio commonly describes an HDMI HBR wire as
     * 768 kHz stereo (4 bytes per frame), equivalent to 192 kHz/8ch
     * (16 bytes per frame). TrueHD's MAT writer counts its fixed 61440-byte
     * burst in the latter representation. VLC's DTS-HD type-IV writer instead
     * defines its repetition period in 768 kHz stereo IEC 60958 frames, so it
     * must retain that representation. Treating DTS-HD as 192 kHz/16-byte
     * frames made every burst four times too short after a DTS-HD track was
     * selected (most visibly after a Blu-ray seek), and the core then filled
     * the three missing quarters with silence. */
    if (desired_stream_format.mFormatFlags & kAudioFormatFlagIsBigEndian)
        fmt->i_format = VLC_CODEC_SPDIFB;
    else
        fmt->i_format = VLC_CODEC_SPDIFL;
    if (source_format == VLC_CODEC_DTS && b_dtshd)
    {
        fmt->i_bytes_per_frame = 4;
        fmt->i_frame_length = 1;
        fmt->i_rate = 768000;
    }
    else if (i_required_bytes_per_second >= 192000 * 8 * 2)
    {
        fmt->i_bytes_per_frame = 16;
        fmt->i_frame_length = 1;
        fmt->i_rate = 192000;
    }
    else
    {
        fmt->i_bytes_per_frame = AOUT_SPDIF_SIZE;
        fmt->i_frame_length = A52_FRAME_NB;
        fmt->i_rate = (unsigned int)desired_stream_format.mSampleRate;
    }
    aout_FormatPrepare(fmt);
    ConfigureDigitalPause(p_aout, fmt, source_format, source_rate,
                          source_frame_length);

    /* Kodi sizes its Darwin ring from four CoreAudio device buffers. Query the
     * same hardware quantum after selecting the encoded physical format. The
     * AudioDevice IOProc exposes bytes in that physical format, hence use the
     * selected ASBD rather than VLC's normalized HBR representation. */
    size_t i_render_buffer_size = 0;
    UInt32 i_render_frames = 0;
    if (AO_GET1PROP(p_sys->i_selected_dev, UInt32, &i_render_frames,
                    kAudioDevicePropertyBufferFrameSize,
                    kAudioObjectPropertyScopeOutput) == VLC_SUCCESS
     && i_render_frames > 0)
    {
        uint64_t i_device_bytes_per_frame =
            desired_stream_format.mBytesPerFrame;
        if (i_device_bytes_per_frame == 0
         && desired_stream_format.mFramesPerPacket != 0)
            i_device_bytes_per_frame =
                (desired_stream_format.mBytesPerPacket
                 + desired_stream_format.mFramesPerPacket - 1)
                / desired_stream_format.mFramesPerPacket;
        if (i_device_bytes_per_frame == 0
         && desired_stream_format.mSampleRate > 0)
            i_device_bytes_per_frame =
                (uint64_t)(i_required_bytes_per_second
                         / desired_stream_format.mSampleRate);

        uint64_t i_render_bytes = (uint64_t)i_render_frames
                                * i_device_bytes_per_frame;
        if (i_render_bytes > 0 && i_render_bytes <= SIZE_MAX)
            i_render_buffer_size = i_render_bytes;
    }

    /* Mirror CoreAudio's complete, runtime-provided latency model used by
     * Kodi: callback output-time delta + software ring (handled by
     * coreaudio_common) + device latency + one hardware buffer + safety
     * offset + stream latency.  Passing zero here made compressed HDMI audio
     * physically arrive later than the video even though VLC's own queue
     * clock looked synchronized.  No receiver-specific or fixed A/V offset is
     * involved; every term is queried from the active CoreAudio objects after
     * selecting the encoded physical format. */
    UInt32 i_device_latency_frames = 0;
    UInt32 i_safety_frames = 0;
    UInt32 i_stream_latency_frames = 0;
    AO_GET1PROP(p_sys->i_selected_dev, UInt32, &i_device_latency_frames,
                kAudioDevicePropertyLatency,
                kAudioObjectPropertyScopeOutput);
    AO_GET1PROP(p_sys->i_selected_dev, UInt32, &i_safety_frames,
                kAudioDevicePropertySafetyOffset,
                kAudioObjectPropertyScopeOutput);
    AO_GET1PROP(p_sys->i_stream_id, UInt32, &i_stream_latency_frames,
                kAudioStreamPropertyLatency,
                kAudioObjectPropertyScopeGlobal);

    const uint64_t i_coreaudio_latency_frames =
        (uint64_t)i_device_latency_frames + i_render_frames + i_safety_frames
      + i_stream_latency_frames;
    const double f_physical_rate = desired_stream_format.mSampleRate > 0.0
                                 ? desired_stream_format.mSampleRate
                                 : fmt->i_rate;
    vlc_tick_t i_coreaudio_latency_us = f_physical_rate > 0.0
        ? (vlc_tick_t)(i_coreaudio_latency_frames * CLOCK_FREQ
                       / f_physical_rate + 0.5)
        : 0;
    msg_Dbg(p_aout, "encoded CoreAudio latency: device %u + buffer %u + "
            "safety %u + stream %u = %"PRIu64" frames / %"PRId64" us",
            i_device_latency_frames, i_render_frames, i_safety_frames,
            i_stream_latency_frames, i_coreaudio_latency_frames,
            i_coreaudio_latency_us);

    /* Add IOProc callback */
    OSStatus err =
        AudioDeviceCreateIOProcID(p_sys->i_selected_dev,
                                  RenderCallbackSPDIF,
                                  p_aout, &p_sys->i_procID);
    if (err != noErr)
    {
        ca_LogErr("Failed to create Process ID");
        return VLC_EGENERIC;
    }

    ret = ca_Initialize(p_aout, fmt, i_coreaudio_latency_us,
                        i_render_buffer_size,
                        i_encoded_packet_size);
    if (ret != VLC_SUCCESS)
    {
        AudioDeviceDestroyIOProcID(p_sys->i_selected_dev, p_sys->i_procID);
        return VLC_EGENERIC;
    }

    /* Start device */
    err = AudioDeviceStart(p_sys->i_selected_dev, p_sys->i_procID);
    if (err != noErr)
    {
        ca_LogErr("Failed to start audio device");

        err = AudioDeviceDestroyIOProcID(p_sys->i_selected_dev, p_sys->i_procID);
        if (err != noErr)
            ca_LogErr("Failed to destroy process ID");

        return VLC_EGENERIC;
    }

    msg_Dbg(p_aout, "Using audio device for digital output");
    return VLC_SUCCESS;
}

static void
Stop(audio_output_t *p_aout)
{
    struct aout_sys_t   *p_sys = p_aout->sys;
    OSStatus            err = noErr;

    msg_Dbg(p_aout, "Stopping the auhal module");

    if (p_sys->au_unit)
    {
        AudioOutputUnitStop(p_sys->au_unit);
        au_Uninitialize(p_aout, p_sys->au_unit);
        au_DisposeOutputInstance(p_sys->au_unit);
    }
    else
    {
        assert(p_sys->b_digital);

        /* Stop device */
        err = AudioDeviceStop(p_sys->i_selected_dev,
                               p_sys->i_procID);
        if (err != noErr)
            ca_LogErr("AudioDeviceStop failed");

        /* Remove IOProc callback */
        err = AudioDeviceDestroyIOProcID(p_sys->i_selected_dev,
                                          p_sys->i_procID);
        if (err != noErr)
            ca_LogErr("Failed to destroy Process ID");

        if (p_sys->b_revert
         && !AudioStreamChangeFormat(p_aout, p_sys->i_stream_id, p_sys->sfmt_revert))
            msg_Err(p_aout, "failed to revert stream format in close");

        if (p_sys->b_changed_mixing
         && p_sys->sfmt_revert.mFormatID != kAudioFormat60958AC3)
        {
            UInt32 b_mix;
            /* Revert mixable to true if we are allowed to */
            bool b_writeable =
                AO_ISPROPSETTABLE(p_sys->i_selected_dev,
                                  kAudioDevicePropertySupportsMixing,
                                  kAudioObjectPropertyScopeGlobal);
            int ret = AO_GET1PROP(p_sys->i_selected_dev, UInt32, &b_mix,
                                  kAudioDevicePropertySupportsMixing,
                                  kAudioObjectPropertyScopeOutput);
            if (ret == VLC_SUCCESS && b_writeable)
            {
                msg_Dbg(p_aout, "mixable is: %d", b_mix);
                b_mix = 1;
                ret = AO_SETPROP(p_sys->i_selected_dev,
                                 sizeof(UInt32), &b_mix,
                                 kAudioDevicePropertySupportsMixing,
                                 kAudioObjectPropertyScopeOutput);
            }

            if (ret != VLC_SUCCESS)
                msg_Err(p_aout, "failed to re-set mixmode");
        }
        ca_Uninitialize(p_aout);

        if (p_sys->i_hog_pid == getpid())
        {
            p_sys->i_hog_pid = -1;

            /*
             * HACK: On 10.6, auhal will trigger the streams changed callback
             * when calling below line, directly in the same thread. This call
             * needs to be ignored to avoid endless restarting.
             */
            p_sys->b_ignore_streams_changed_callback = true;
            AO_SETPROP(p_sys->i_selected_dev, sizeof(p_sys->i_hog_pid),
                       &p_sys->i_hog_pid, kAudioDevicePropertyHogMode,
                       kAudioObjectPropertyScopeOutput);
            p_sys->b_ignore_streams_changed_callback = false;
        }

        p_sys->b_digital = false;
    }

    /* Restore the device rate we changed in StartAnalog(), if any. This must
     * stay OUTSIDE the analog/digital branching above: SetDeviceRate() returns
     * 0 whenever the device already ran at the wanted rate, so making the
     * S/PDIF teardown the "else" of this test used to run it on every analog
     * stop — calling AudioDeviceStop(dev, NULL), which stops the device
     * itself, once per track. */
    if (p_sys->f_revert_rate != 0)
    {
        AO_SETPROP(p_sys->i_selected_dev, sizeof(p_sys->f_revert_rate),
                   &p_sys->f_revert_rate, kAudioDevicePropertyNominalSampleRate,
                   kAudioObjectPropertyScopeGlobal);
        p_sys->f_revert_rate = 0;
    }

    /* remove audio device alive callback */
    AO_UPDATELISTENER(p_sys->i_selected_dev, false, DeviceAliveListener, p_aout,
                      kAudioDevicePropertyDeviceIsAlive,
                      kAudioObjectPropertyScopeGlobal);
}

static int
Start(audio_output_t *p_aout, audio_sample_format_t *restrict fmt)
{
    UInt32                  i_param_size = 0;
    struct aout_sys_t       *p_sys = NULL;

    /* Use int here, to match kAudioDevicePropertyDeviceIsAlive
     * property size */
    int                     b_alive = false;

    if ((AOUT_FMT_SPDIF(fmt) || AOUT_FMT_HDMI(fmt))
     && !var_InheritBool(p_aout, "spdif"))
        return VLC_EGENERIC;

    p_sys = p_aout->sys;
    p_sys->b_digital = false;
    p_sys->au_unit = NULL;
    p_sys->i_stream_index = -1;
    p_sys->b_revert = false;
    p_sys->b_changed_mixing = false;

    vlc_mutex_lock(&p_sys->selected_device_lock);
    bool do_spdif;
    if (AOUT_FMT_SPDIF(fmt) || AOUT_FMT_HDMI(fmt))
        do_spdif = true;
    else
        do_spdif = false;

    /* A display mode transaction republishes an HDMI endpoint with a new
     * AudioDeviceID (for example XGIMI 117 -> 163). The restart can arrive
     * after the new endpoint is visible but before the display-generation
     * callback has remapped i_new_selected_dev. Resolve the persistent
     * UID/name here as the final authority, before deciding that the stored
     * numeric ID vanished and falling back to the Mac speakers. */
    if ((p_sys->i_new_selected_dev & ~AOUT_VAR_SPDIF_FLAG) != 0 &&
        (p_sys->selected_device_transport == VLC_CA_TRANSPORT_HDMI ||
         p_sys->selected_device_transport == VLC_CA_TRANSPORT_DISPLAYPORT))
        RemapSelectedHDMIDevice(p_aout);

    p_sys->i_selected_dev = p_sys->i_new_selected_dev & ~AOUT_VAR_SPDIF_FLAG;

    aout_FormatPrint(p_aout, "VLC is looking for:", fmt);

    msg_Dbg(p_aout, "attempting to use device %i", p_sys->i_selected_dev);

    if (p_sys->i_selected_dev > 0)
    {
        /* Check if device is in devices list. Only checking for
         * kAudioDevicePropertyDeviceIsAlive is not sufficient, as a former
         * airplay device might be already gone, but the device number might be
         * still valid. Core Audio even says that this device would be alive.
         * Don't ask why, its Core Audio. */
        CFIndex count = CFArrayGetCount(p_sys->device_list);
        CFNumberRef deviceNumber =
            CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type,
                           &p_sys->i_selected_dev);
        if (CFArrayContainsValue(p_sys->device_list,
                                 CFRangeMake(0, count), deviceNumber))
        {
            /* Check if the desired device is alive and usable */
            i_param_size = sizeof(b_alive);
            int ret = AO_GET1PROP(p_sys->i_selected_dev, int, &b_alive,
                                  kAudioDevicePropertyDeviceIsAlive,
                                  kAudioObjectPropertyScopeGlobal);
            if (ret != VLC_SUCCESS)
                b_alive = false; /* Be tolerant */

            if (!b_alive)
                msg_Warn(p_aout, "selected audio device is not alive, switching"
                         " to default device");

        }
        else
        {
            msg_Warn(p_aout, "device id %i not found in the current devices "
                     "list, fallback to default device", p_sys->i_selected_dev);
        }
        CFRelease(deviceNumber);
    }

    p_sys->b_selected_dev_is_default = false;
    if (!b_alive || p_sys->i_selected_dev == 0)
    {
        p_sys->b_selected_dev_is_default = true;

        AudioObjectID defaultDeviceID = 0;
        int ret = AO_GET1PROP(kAudioObjectSystemObject, AudioObjectID,
                              &defaultDeviceID,
                              kAudioHardwarePropertyDefaultOutputDevice,
                              kAudioObjectPropertyScopeOutput);
        if (ret != VLC_SUCCESS)
        {
            vlc_mutex_unlock(&p_sys->selected_device_lock);
            return VLC_EGENERIC;
        }
        else
            msg_Dbg(p_aout, "using default audio device %i", defaultDeviceID);

        p_sys->i_selected_dev = defaultDeviceID;
    }
    vlc_mutex_unlock(&p_sys->selected_device_lock);

    /* add a callback to see if the device dies later on */
    AO_UPDATELISTENER(p_sys->i_selected_dev, true, DeviceAliveListener, p_aout,
                      kAudioDevicePropertyDeviceIsAlive,
                      kAudioObjectPropertyScopeGlobal);

    /* get device latency */
    UInt32 i_latency_samples;
    vlc_tick_t i_latency_us = 0;
    int ret = AO_GET1PROP(p_sys->i_selected_dev, UInt32, &i_latency_samples,
                          kAudioDevicePropertyLatency,
                          kAudioObjectPropertyScopeOutput);
    if (ret == VLC_SUCCESS)
        i_latency_us += i_latency_samples * CLOCK_FREQ / fmt->i_rate;

    msg_Dbg(p_aout, "Current device has a latency of %lld us", i_latency_us);

    /* Check for Digital mode or Analog output mode */
    if (do_spdif)
    {
        if (StartSPDIF(p_aout, fmt) == VLC_SUCCESS)
        {
            msg_Dbg(p_aout, "digital output successfully opened");
            return VLC_SUCCESS;
        }
    }
    else
    {
        if (StartAnalog(p_aout, fmt) == VLC_SUCCESS)
        {
            msg_Dbg(p_aout, "analog output successfully opened");
            fmt->channel_type = AUDIO_CHANNEL_TYPE_BITMAP;
            return VLC_SUCCESS;
        }
    }

    msg_Err(p_aout, "opening auhal output failed");
    AO_UPDATELISTENER(p_sys->i_selected_dev, false, DeviceAliveListener, p_aout,
                      kAudioDevicePropertyDeviceIsAlive,
                      kAudioObjectPropertyScopeGlobal);
    return VLC_EGENERIC;
}

static void Close(vlc_object_t *obj)
{
    audio_output_t *p_aout = (audio_output_t *)obj;
    aout_sys_t *p_sys = p_aout->sys;

    var_DelCallback(p_aout->obj.libvlc, "macosx-hdmi-audio-generation",
                    HDMIDisplayAudioGenerationChanged, p_aout);

    /* remove audio devices callback */
    AO_UPDATELISTENER(kAudioObjectSystemObject, false, DevicesListener, p_aout,
                      kAudioHardwarePropertyDevices,
                      kAudioObjectPropertyScopeGlobal);

    /* remove listener to be notified about changes in default audio device */
    AO_UPDATELISTENER(kAudioObjectSystemObject, false,
                      DefaultDeviceChangedListener, p_aout,
                      kAudioHardwarePropertyDefaultOutputDevice,
                      kAudioObjectPropertyScopeGlobal);

    /*
     * StreamsChangedListener can rebuild the device list and thus held the
     * device_list_lock.  To avoid a possible deadlock, an array copy is
     * created here.  In rare cases, this can lead to missing
     * StreamsChangedListener callback deregistration (TODO).
     */
    vlc_mutex_lock(&p_sys->device_list_lock);
    CFArrayRef device_list_cpy = CFArrayCreateCopy(NULL, p_sys->device_list);
    vlc_mutex_unlock(&p_sys->device_list_lock);

    /* remove streams callbacks */
    CFIndex count = CFArrayGetCount(device_list_cpy);
    if (count > 0)
    {
        for (CFIndex x = 0; x < count; x++)
        {
            AudioDeviceID deviceId = 0;
            CFNumberRef cfn_device_id =
                CFArrayGetValueAtIndex(device_list_cpy, x);
            if (!cfn_device_id)
                continue;

            CFNumberGetValue(cfn_device_id, kCFNumberSInt32Type, &deviceId);
            if (!(deviceId & AOUT_VAR_SPDIF_FLAG))
                ManageAudioStreamsCallback(p_aout, deviceId, false);
        }
    }

    CFRelease(device_list_cpy);
    CFRelease(p_sys->device_list);

    char *psz_device = aout_DeviceGet(p_aout);
    config_PutPsz(p_aout, "auhal-audio-device", psz_device);
    free(psz_device);

    vlc_mutex_destroy(&p_sys->selected_device_lock);
    vlc_mutex_destroy(&p_sys->device_list_lock);

    ca_Close(p_aout);
    if (p_sys->selected_device_uid != NULL)
        CFRelease(p_sys->selected_device_uid);
    if (p_sys->selected_device_name != NULL)
        CFRelease(p_sys->selected_device_name);
    free(p_sys);
}

static int Open(vlc_object_t *obj)
{
    audio_output_t *p_aout = (audio_output_t *)obj;

    aout_sys_t *p_sys = p_aout->sys = calloc(1, sizeof (*p_sys));
    if (unlikely(p_sys == NULL))
        return VLC_ENOMEM;

    if (ca_Open(p_aout) != VLC_SUCCESS)
    {
        free(p_sys);
        return VLC_EGENERIC;
    }

    vlc_mutex_init(&p_sys->device_list_lock);
    vlc_mutex_init(&p_sys->selected_device_lock);
    p_sys->b_digital = false;
    p_sys->b_ignore_streams_changed_callback = false;
    p_sys->b_selected_dev_is_default = false;
    memset(&p_sys->sfmt_revert, 0, sizeof(p_sys->sfmt_revert));
    p_sys->i_stream_id = 0;

    p_aout->start = Start;
    p_aout->stop = Stop;
    p_aout->volume_set = VolumeSet;
    p_aout->mute_set = MuteSet;
    p_aout->device_select = SwitchAudioDevice;
    p_sys->device_list = CFArrayCreate(kCFAllocatorDefault, NULL, 0, NULL);

    /*
     * Force an own run loop for callbacks.
     *
     * According to rtaudio, this is absolutely necessary since 10.6 to get
     * correct notifications.  It might fix issues when using the module as a
     * library where a proper loop is not setup already.
     */
    CFRunLoopRef theRunLoop = NULL;
    AO_SETPROP(kAudioObjectSystemObject, sizeof(CFRunLoopRef),
               &theRunLoop, kAudioHardwarePropertyRunLoop,
               kAudioObjectPropertyScopeGlobal);

    /* Attach a listener so that we are notified of a change in the device
     * setup */
    AO_UPDATELISTENER(kAudioObjectSystemObject, true, DevicesListener, p_aout,
                      kAudioHardwarePropertyDevices,
                      kAudioObjectPropertyScopeGlobal);

    /* Attach a listener to be notified about changes in default audio device */
    AO_UPDATELISTENER(kAudioObjectSystemObject, true,
                      DefaultDeviceChangedListener, p_aout,
                      kAudioHardwarePropertyDefaultOutputDevice,
                      kAudioObjectPropertyScopeGlobal);

    char *psz_audio_device = var_InheritString(p_aout, "auhal-audio-device");
    if (psz_audio_device != NULL)
    {
        int dev_id_int = atoi(psz_audio_device);
        UInt32 dev_id = dev_id_int < 0 ? 0 : dev_id_int;

        bool isDigital = (dev_id & AOUT_VAR_SPDIF_FLAG) != 0;
        msg_Dbg(obj, "Trying to use stored audio device %d (%s)",
                (dev_id & ~AOUT_VAR_SPDIF_FLAG), isDigital ? "digital" : "analog");

        /* Keep the encoded-output intent while RebuildDeviceList checks the
         * disposable CoreAudio object ID. This lets the identity remapper
         * recover the currently published HDMI endpoint when PowerVLC was
         * launched with an ID saved before the latest display mode switch. */
        p_sys->i_new_selected_dev = dev_id;
        RebuildDeviceList(p_aout, &dev_id);
        if (dev_id == 0 && isDigital && RemapSelectedHDMIDevice(p_aout))
            dev_id = p_sys->i_new_selected_dev;
        p_sys->i_new_selected_dev = dev_id;
        RememberSelectedDeviceUID(p_aout, dev_id);
        free(psz_audio_device);
    }
    else
    {
        RebuildDeviceList(p_aout, NULL);
        p_sys->i_new_selected_dev = 0;
    }

    var_Create(p_aout->obj.libvlc, "macosx-hdmi-audio-reconfiguring",
               VLC_VAR_BOOL);
    var_Create(p_aout->obj.libvlc, "macosx-hdmi-audio-generation",
               VLC_VAR_INTEGER);
    var_AddCallback(p_aout->obj.libvlc, "macosx-hdmi-audio-generation",
                    HDMIDisplayAudioGenerationChanged, p_aout);

    char deviceid[10];
    sprintf(deviceid, "%i", p_sys->i_new_selected_dev);
    aout_DeviceReport(p_aout, deviceid);

    /* remember the volume */
    p_sys->f_volume = var_InheritInteger(p_aout, "auhal-volume")
                    / (float)AOUT_VOLUME_DEFAULT;
    aout_VolumeReport(p_aout, p_sys->f_volume);
    p_sys->b_mute = var_InheritBool(p_aout, "mute");
    aout_MuteReport(p_aout, p_sys->b_mute);

    return VLC_SUCCESS;
}
