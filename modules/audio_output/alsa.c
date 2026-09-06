/*****************************************************************************
 * alsa.c : alsa plugin for vlc
 *****************************************************************************
 * Copyright (C) 2000-2010 VLC authors and VideoLAN
 * Copyright (C) 2009-2011 Rémi Denis-Courmont
 *
 * Authors: Henri Fallon <henri@videolan.org> - Original Author
 *          Jeffrey Baker <jwbaker@acm.org> - Port to ALSA 1.0 API
 *          John Paul Lorenti <jpl31@columbia.edu> - Device selection
 *          Arnaud de Bossoreille de Ribou <bozo@via.ecp.fr> - S/PDIF and aout3
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

#include <assert.h>
#include <time.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_dialog.h>
#include <vlc_aout.h>
#include <vlc_cpu.h>

#include <alsa/asoundlib.h>
#include <alsa/version.h>

/** Private data for an ALSA PCM playback stream */
struct aout_sys_t
{
    snd_pcm_t *pcm;
    unsigned rate; /**< Sample rate */
    vlc_fourcc_t format; /**< Sample format */
    uint8_t chans_table[AOUT_CHAN_MAX]; /**< Channels order table */
    uint8_t chans_to_reorder; /**< Number of channels to reorder */

    bool soft_mute;
    float soft_gain;
    char *device;

    /* A raw ALSA HDMI PCM does not update the IEC60958 channel status like
     * the optional "hdmi:" PCM plugin does. Keep enough information to put
     * the control back in PCM mode when the encoded stream stops. */
    int iec958_card;
    int iec958_index;
    bool iec958_non_audio;
    bool iec958_rearm_pending;
};

#include "audio_output/volume.h"

#define A52_FRAME_NB 1536

static int Open (vlc_object_t *);
static void Close (vlc_object_t *);
static int EnumDevices (vlc_object_t *, char const *, char ***, char ***);

static unsigned Iec958Rate(unsigned rate)
{
    switch (rate)
    {
#define FS(freq) case freq: return IEC958_AES3_CON_FS_ ## freq;
        FS( 44100) FS( 48000) FS( 32000) FS( 22050) FS( 24000)
        FS( 88200) FS(768000) FS( 96000) FS(176400) FS(192000)
#undef FS
        default: return IEC958_AES3_CON_FS_NOTID;
    }
}

/* Maps an HDMI PCM device to the matching IEC958 control index. HDA cards
 * commonly expose PCM devices 3/7/8, while SOF cards use 3/4/5. Enumerating
 * the ELD controls avoids encoding either convention in PowerVLC. */
static int FindIec958Index(snd_ctl_t *ctl, unsigned pcm_device)
{
    snd_ctl_elem_list_t *list;
    snd_ctl_elem_list_alloca(&list);
    if (snd_ctl_elem_list(ctl, list) < 0)
        return -1;

    unsigned count = snd_ctl_elem_list_get_count(list);
    if (snd_ctl_elem_list_alloc_space(list, count) < 0)
        return -1;
    if (snd_ctl_elem_list(ctl, list) < 0) {
        snd_ctl_elem_list_free_space(list);
        return -1;
    }

    unsigned lower_devices[64];
    unsigned lower_count = 0;
    unsigned iec958_controls = 0;
    bool found_device = false;
    for (unsigned i = 0; i < count; ++i) {
        const char *name = snd_ctl_elem_list_get_name(list, i);
        snd_ctl_elem_iface_t iface = snd_ctl_elem_list_get_interface(list, i);
        if (iface == SND_CTL_ELEM_IFACE_MIXER &&
            !strcmp(name, SND_CTL_NAME_IEC958("", PLAYBACK, DEFAULT)))
            ++iec958_controls;
        if (iface != SND_CTL_ELEM_IFACE_PCM || strcmp(name, "ELD"))
            continue;

        unsigned device = snd_ctl_elem_list_get_device(list, i);
        if (device == pcm_device)
            found_device = true;
        if (device >= pcm_device)
            continue;
        bool duplicate = false;
        for (unsigned d = 0; d < lower_count; ++d)
            duplicate |= lower_devices[d] == device;
        if (!duplicate && lower_count < ARRAY_SIZE(lower_devices))
            lower_devices[lower_count++] = device;
    }
    snd_ctl_elem_list_free_space(list);

    if (found_device && lower_count < iec958_controls)
        return (int)lower_count;
    return iec958_controls == 1 ? 0 : -1;
}

static int SetRawHdmiChannelStatus(audio_output_t *aout, snd_pcm_t *pcm,
                                   bool non_audio, unsigned rate)
{
    aout_sys_t *sys = aout->sys;
    snd_pcm_info_t *info;
    snd_pcm_info_alloca(&info);
    if (snd_pcm_info(pcm, info) < 0)
        return -1;

    int card = snd_pcm_info_get_card(info);
    unsigned device = snd_pcm_info_get_device(info);
    if (card < 0)
        return -1;

    char card_name[32];
    snprintf(card_name, sizeof(card_name), "hw:%d", card);
    snd_ctl_t *ctl;
    if (snd_ctl_open(&ctl, card_name, 0) < 0)
        return -1;

    int index = FindIec958Index(ctl, device);
    if (index < 0) {
        snd_ctl_close(ctl);
        return -1;
    }

    snd_ctl_elem_value_t *value;
    snd_ctl_elem_value_alloca(&value);
    snd_ctl_elem_value_set_interface(value, SND_CTL_ELEM_IFACE_MIXER);
    snd_ctl_elem_value_set_name(value,
        SND_CTL_NAME_IEC958("", PLAYBACK, DEFAULT));
    snd_ctl_elem_value_set_index(value, (unsigned)index);
    int result = snd_ctl_elem_read(ctl, value);
    if (result >= 0) {
        snd_aes_iec958_t status;
        snd_ctl_elem_value_get_iec958(value, &status);
        if (non_audio)
            status.status[0] |= IEC958_AES0_NONAUDIO;
        else
            status.status[0] &= ~IEC958_AES0_NONAUDIO;
        status.status[3] = (status.status[3] & 0xf0) | Iec958Rate(rate);
        snd_ctl_elem_value_set_iec958(value, &status);
        result = snd_ctl_elem_write(ctl, value);
    }
    snd_ctl_close(ctl);

    if (result >= 0) {
        sys->iec958_card = card;
        sys->iec958_index = index;
        sys->iec958_non_audio = non_audio;
        msg_Dbg(aout, "set IEC60958 control %d:%d to %s at %u Hz",
                card, index, non_audio ? "non-audio" : "PCM", rate);
        return 0;
    }
    return -1;
}

/* Raw hw: HDMI PCMs also bypass the ALSA hdmi plugin's playback switch.
 * Toggling that switch between encoded streams is significant on receivers
 * that keep their IEC61937 decoder locked to the previous burst layout (for
 * example AC-3 5.1 followed immediately by AC-3 stereo in a Blu-ray menu). */
static int SetRawHdmiPlaybackSwitch(audio_output_t *aout, snd_pcm_t *pcm,
                                    bool enabled)
{
    snd_pcm_info_t *info;
    snd_pcm_info_alloca(&info);
    if (snd_pcm_info(pcm, info) < 0)
        return -1;

    int card = snd_pcm_info_get_card(info);
    unsigned device = snd_pcm_info_get_device(info);
    if (card < 0)
        return -1;

    char card_name[32];
    snprintf(card_name, sizeof(card_name), "hw:%d", card);
    snd_ctl_t *ctl;
    if (snd_ctl_open(&ctl, card_name, 0) < 0)
        return -1;

    int index = FindIec958Index(ctl, device);
    if (index < 0) {
        snd_ctl_close(ctl);
        return -1;
    }

    snd_ctl_elem_value_t *value;
    snd_ctl_elem_value_alloca(&value);
    snd_ctl_elem_value_set_interface(value, SND_CTL_ELEM_IFACE_MIXER);
    snd_ctl_elem_value_set_name(value,
        SND_CTL_NAME_IEC958("", PLAYBACK, SWITCH));
    snd_ctl_elem_value_set_index(value, (unsigned)index);
    snd_ctl_elem_value_set_boolean(value, 0, enabled);
    int result = snd_ctl_elem_write(ctl, value);
    snd_ctl_close(ctl);

    if (result >= 0)
        msg_Dbg(aout, "%s IEC60958 playback switch %d:%d",
                enabled ? "enabled" : "disabled", card, index);
    return result;
}

#define AUDIO_DEV_TEXT N_("Audio output device")
#define AUDIO_DEV_LONGTEXT N_("Audio output device (using ALSA syntax).")

#define AUDIO_CHAN_TEXT N_("Audio output channels")
#define AUDIO_CHAN_LONGTEXT N_("Channels available for audio output. " \
    "If the input has more channels than the output, it will be down-mixed. " \
    "This parameter is ignored when digital pass-through is active.")
static const int channels[] = {
    AOUT_CHAN_CENTER, AOUT_CHANS_STEREO, AOUT_CHANS_4_0, AOUT_CHANS_4_1,
    AOUT_CHANS_5_0, AOUT_CHANS_5_1, AOUT_CHANS_7_1,
};
static const char *const channels_text[] = {
    N_("Mono"), N_("Stereo"), N_("Surround 4.0"), N_("Surround 4.1"),
    N_("Surround 5.0"), N_("Surround 5.1"), N_("Surround 7.1"),
};

vlc_module_begin ()
    set_shortname( "ALSA" )
    set_description( N_("ALSA audio output") )
    set_category( CAT_AUDIO )
    set_subcategory( SUBCAT_AUDIO_AOUT )
    add_string ("alsa-audio-device", "default",
                AUDIO_DEV_TEXT, AUDIO_DEV_LONGTEXT, false)
        change_string_cb (EnumDevices)
    add_integer ("alsa-audio-channels", AOUT_CHANS_FRONT,
                 AUDIO_CHAN_TEXT, AUDIO_CHAN_LONGTEXT, false)
        change_integer_list (channels, channels_text)
    add_sw_gain ()
    set_capability( "audio output", 150 )
    set_callbacks( Open, Close )
vlc_module_end ()


/** Helper for ALSA -> VLC debugging output */
static void Dump (vlc_object_t *obj, const char *msg,
                  int (*cb)(void *, snd_output_t *), void *p)
{
    snd_output_t *output;
    char *str;

    if (unlikely(snd_output_buffer_open (&output)))
        return;

    int val = cb (p, output);
    if (val)
    {
        msg_Warn (obj, "cannot get info: %s", snd_strerror (val));
        return;
    }

    size_t len = snd_output_buffer_string (output, &str);
    if (len > 0 && str[len - 1])
        len--; /* strip trailing newline */
    msg_Dbg (obj, "%s%.*s", msg, (int)len, str);
    snd_output_close (output);
}
#define Dump(o, m, cb, p) \
        Dump(VLC_OBJECT(o), m, (int (*)(void *, snd_output_t *))(cb), p)

static void DumpDevice (vlc_object_t *obj, snd_pcm_t *pcm)
{
    snd_pcm_info_t *info;

    Dump (obj, " ", snd_pcm_dump, pcm);
    snd_pcm_info_alloca (&info);
    if (snd_pcm_info (pcm, info) == 0)
    {
        msg_Dbg (obj, " device name   : %s", snd_pcm_info_get_name (info));
        msg_Dbg (obj, " device ID     : %s", snd_pcm_info_get_id (info));
        msg_Dbg (obj, " subdevice name: %s",
                snd_pcm_info_get_subdevice_name (info));
    }
}

static void DumpDeviceStatus (vlc_object_t *obj, snd_pcm_t *pcm)
{
    snd_pcm_status_t *status;

    snd_pcm_status_alloca (&status);
    snd_pcm_status (pcm, status);
    Dump (obj, "current status:\n", snd_pcm_status_dump, status);
}
#define DumpDeviceStatus(o, p) DumpDeviceStatus(VLC_OBJECT(o), p)

#if (SND_LIB_VERSION >= 0x01001B)
static const uint16_t vlc_chans[] = {
    [SND_CHMAP_MONO] = AOUT_CHAN_CENTER,
    [SND_CHMAP_FL]   = AOUT_CHAN_LEFT,
    [SND_CHMAP_FR]   = AOUT_CHAN_RIGHT,
    [SND_CHMAP_RL]   = AOUT_CHAN_REARLEFT,
    [SND_CHMAP_RR]   = AOUT_CHAN_REARRIGHT,
    [SND_CHMAP_FC]   = AOUT_CHAN_CENTER,
    [SND_CHMAP_LFE]  = AOUT_CHAN_LFE,
    [SND_CHMAP_SL]   = AOUT_CHAN_MIDDLELEFT,
    [SND_CHMAP_SR]   = AOUT_CHAN_MIDDLERIGHT,
    [SND_CHMAP_RC]   = AOUT_CHAN_REARCENTER,
};
static_assert(AOUT_CHAN_MAX == 9, "Missing channel entries");

static int Map2Mask (vlc_object_t *obj, const snd_pcm_chmap_t *restrict map)
{
    uint16_t mask = 0;

    for (unsigned i = 0; i < map->channels; i++)
    {
        const unsigned pos = map->pos[i];
        uint_fast16_t vlc_chan = 0;

        if (pos < sizeof (vlc_chans) / sizeof (vlc_chans[0]))
            vlc_chan = vlc_chans[pos];
        if (vlc_chan == 0)
        {
            msg_Dbg (obj, " %s channel %u position %u", "unsupported", i, pos);
            return -1;
        }
        if (mask & vlc_chan)
        {
            msg_Dbg (obj, " %s channel %u position %u", "duplicate", i, pos);
            return -1;
        }
        mask |= vlc_chan;
    }
    return mask;
}

/**
 * Compares a fixed ALSA channels map with the VLC channels order.
 */
static unsigned SetupChannelsFixed(const snd_pcm_chmap_t *restrict map,
                               uint16_t *restrict maskp, uint8_t *restrict tab)
{
    uint32_t chans_out[AOUT_CHAN_MAX];
    uint16_t mask = 0;

    for (unsigned i = 0; i < map->channels; i++)
    {
        uint_fast16_t vlc_chan = vlc_chans[map->pos[i]];

        chans_out[i] = vlc_chan;
        mask |= vlc_chan;
    }

    *maskp = mask;
    return aout_CheckChannelReorder(NULL, chans_out, mask, tab);
}

/**
 * Negotiate channels mapping.
 */
static unsigned SetupChannels (vlc_object_t *obj, snd_pcm_t *pcm,
                               uint16_t *restrict mask, uint8_t *restrict tab)
{
    snd_pcm_chmap_query_t **maps = snd_pcm_query_chmaps (pcm);
    if (maps == NULL)
    {   /* Fallback to default order if unknown */
        msg_Dbg(obj, "channels map not provided");
        return 0;
    }

    /* Find most appropriate available channels map */
    unsigned best_offset, best_score = 0, to_reorder = 0;

    for (snd_pcm_chmap_query_t *const *p = maps; *p != NULL; p++)
    {
        snd_pcm_chmap_query_t *map = *p;

        switch (map->type)
        {
            case SND_CHMAP_TYPE_FIXED:
            case SND_CHMAP_TYPE_PAIRED:
            case SND_CHMAP_TYPE_VAR:
                break;
            default:
                msg_Err (obj, "unknown channels map type %u", map->type);
                continue;
        }

        int chans = Map2Mask (obj, &map->map);
        if (chans == -1)
            continue;

        unsigned score = (popcount (chans & *mask) << 8)
                       | (255 - popcount (chans));
        if (score > best_score)
        {
            best_offset = p - maps;
            best_score = score;
        }
    }

    if (best_score == 0)
    {
        msg_Err (obj, "cannot find supported channels map");
        goto out;
    }

    const snd_pcm_chmap_t *map = &maps[best_offset]->map;
    msg_Dbg (obj, "using channels map %u, type %u, %u channel(s)", best_offset,
             maps[best_offset]->type, map->channels);

    /* Setup channels map */
    to_reorder = SetupChannelsFixed(map, mask, tab);

    /* TODO: avoid reordering for PAIRED and VAR types */
    //snd_pcm_set_chmap (pcm, ...)
out:
    snd_pcm_free_chmaps (maps);
    return to_reorder;
}
#else /* (SND_LIB_VERSION < 0x01001B) */
# define SetupChannels(obj, pcm, mask, tab) (0)
#endif

static int TimeGet (audio_output_t *aout, vlc_tick_t *);
static void Play (audio_output_t *, block_t *);
static void Pause (audio_output_t *, bool, mtime_t);
static void PauseDummy (audio_output_t *, bool, mtime_t);
static void Flush (audio_output_t *, bool);

static int PrimeRawHdmiCarrier(audio_output_t *aout, unsigned milliseconds)
{
    aout_sys_t *sys = aout->sys;
    snd_pcm_t *pcm = sys->pcm;
    const snd_pcm_uframes_t burst_frames = A52_FRAME_NB;
    ssize_t burst_bytes = snd_pcm_frames_to_bytes(pcm, burst_frames);
    if (burst_bytes < 8)
        return -1;

    uint8_t *burst = calloc(1, (size_t)burst_bytes);
    if (!burst)
        return -1;

    /* IEC61937 null burst: a valid, silent non-audio carrier that lets an
     * HDMI sink establish its audio clock without selecting a codec or
     * consuming programme samples. */
    SetWLE(&burst[0], 0xf872);
    SetWLE(&burst[2], 0x4e1f);
    SetWLE(&burst[4], 0x0000);
    SetWLE(&burst[6], 0x0000);

    uint64_t remaining = (uint64_t)sys->rate * milliseconds / 1000;
    int result = 0;
    while (remaining > 0) {
        snd_pcm_uframes_t frames = __MIN(remaining, burst_frames);
        snd_pcm_uframes_t offset = 0;
        while (offset < frames) {
            snd_pcm_sframes_t written = snd_pcm_writei(
                pcm, burst + snd_pcm_frames_to_bytes(pcm, offset),
                frames - offset);
            if (written < 0) {
                result = snd_pcm_recover(pcm, (int)written, 1);
                if (result < 0)
                    goto out;
                continue;
            }
            offset += (snd_pcm_uframes_t)written;
        }
        remaining -= frames;
    }
    result = snd_pcm_drain(pcm);

out:
    free(burst);
    return result;
}

/** Initializes an ALSA playback stream */
static int Start (audio_output_t *aout, audio_sample_format_t *restrict fmt)
{
    aout_sys_t *sys = aout->sys;
    snd_pcm_format_t pcm_format; /* ALSA sample format */
    bool spdif = false;
    sys->iec958_rearm_pending = false;

    if (aout_FormatNbChannels(fmt) == 0)
        return VLC_EGENERIC;

    switch (fmt->i_format)
    {
        case VLC_CODEC_FL64:
            pcm_format = SND_PCM_FORMAT_FLOAT64;
            break;
        case VLC_CODEC_FL32:
            pcm_format = SND_PCM_FORMAT_FLOAT;
            break;
        case VLC_CODEC_S32N:
            pcm_format = SND_PCM_FORMAT_S32;
            break;
        case VLC_CODEC_S16N:
            pcm_format = SND_PCM_FORMAT_S16;
            break;
        case VLC_CODEC_U8:
            pcm_format = SND_PCM_FORMAT_U8;
            break;
        default:
            if (AOUT_FMT_SPDIF(fmt))
                spdif = var_InheritBool (aout, "spdif");
            if (spdif)
            {
                fmt->i_format = VLC_CODEC_SPDIFL;
                pcm_format = SND_PCM_FORMAT_S16;
            }
            else
            if (HAVE_FPU)
            {
                fmt->i_format = VLC_CODEC_FL32;
                pcm_format = SND_PCM_FORMAT_FLOAT;
            }
            else
            {
                fmt->i_format = VLC_CODEC_S16N;
                pcm_format = SND_PCM_FORMAT_S16;
            }
    }

    const char *device = sys->device;

    /* Choose the IEC device for S/PDIF output */
    char sep = '\0';
    if (spdif)
    {
        const char *opt = NULL;

        if (!strcmp (device, "default"))
            device = "iec958"; /* TODO: hdmi */

        if (!strncmp (device, "iec958", 6))
            opt = device + 6;
        if (!strncmp (device, "hdmi", 4))
            opt = device + 4;

        if (opt != NULL)
            switch (*opt)
            {
                case ':':  sep = ','; break;
                case '\0': sep = ':'; break;
            }
    }

    char *devbuf = NULL;
    if (sep != '\0')
    {
        unsigned aes3;

        switch (fmt->i_rate)
        {
#define FS(freq) \
            case freq: aes3 = IEC958_AES3_CON_FS_ ## freq; break;
            FS( 44100) /* def. */ FS( 48000) FS( 32000)
            FS( 22050)            FS( 24000)
            FS( 88200) FS(768000) FS( 96000)
            FS(176400)            FS(192000)
#undef FS
            default:
                aes3 = IEC958_AES3_CON_FS_NOTID;
                break;
        }

        if (asprintf (&devbuf, "%s%cAES0=0x%x,AES1=0x%x,AES2=0x%x,AES3=0x%x",
                      device, sep,
                      IEC958_AES0_CON_EMPHASIS_NONE | IEC958_AES0_NONAUDIO,
                      IEC958_AES1_CON_ORIGINAL | IEC958_AES1_CON_PCM_CODER,
                      0, aes3) == -1)
            return VLC_ENOMEM;
        device = devbuf;
    }

    /* Open the device */
    snd_pcm_t *pcm;
    /* VLC always has a resampler. No need for ALSA's. */
    const int mode = SND_PCM_NO_AUTO_RESAMPLE;

    int val = snd_pcm_open (&pcm, device, SND_PCM_STREAM_PLAYBACK, mode);
    if (val != 0)
    {
        msg_Err (aout, "cannot open ALSA device \"%s\": %s", device,
                 snd_strerror (val));
        vlc_dialog_display_error (aout, _("Audio output failed"),
            _("The audio device \"%s\" could not be used:\n%s."),
            sys->device, snd_strerror (val));
        free (devbuf);
        return VLC_EGENERIC;
    }
    sys->pcm = pcm;

    /* Print some potentially useful debug */
    msg_Dbg (aout, "using ALSA device: %s", device);
    free (devbuf);
    DumpDevice (VLC_OBJECT(aout), pcm);

    /* The ALSA "hdmi:" and "iec958:" PCM aliases consume the AES options
     * appended above. Minimal distributions and some SOF UCM profiles expose
     * only raw hw: HDMI devices, however. Program their matching mixer
     * control directly so the sink can distinguish IEC61937 bursts from PCM. */
    if (spdif && SetRawHdmiPlaybackSwitch(aout, pcm, false) == 0)
        sys->iec958_rearm_pending = true;
    if (SetRawHdmiChannelStatus(aout, pcm, spdif, fmt->i_rate) != 0 && spdif)
        msg_Dbg(aout, "no writable IEC60958 channel-status control for %s",
                sys->device);
    SetRawHdmiPlaybackSwitch(aout, pcm, true);

    /* Get Initial hardware parameters */
    snd_pcm_hw_params_t *hw;
    unsigned param;

    snd_pcm_hw_params_alloca (&hw);
    snd_pcm_hw_params_any (pcm, hw);
    Dump (aout, "initial hardware setup:\n", snd_pcm_hw_params_dump, hw);

    val = snd_pcm_hw_params_set_rate_resample(pcm, hw, 0);
    if (val)
    {
        msg_Err (aout, "cannot disable resampling: %s", snd_strerror (val));
        goto error;
    }

    val = snd_pcm_hw_params_set_access (pcm, hw,
                                        SND_PCM_ACCESS_RW_INTERLEAVED);
    if (val)
    {
        msg_Err (aout, "cannot set access mode: %s", snd_strerror (val));
        goto error;
    }

    /* Set sample format */
    if (snd_pcm_hw_params_test_format (pcm, hw, pcm_format) == 0)
        ;
    else
    if (snd_pcm_hw_params_test_format (pcm, hw, SND_PCM_FORMAT_FLOAT) == 0)
    {
        fmt->i_format = VLC_CODEC_FL32;
        pcm_format = SND_PCM_FORMAT_FLOAT;
    }
    else
    if (snd_pcm_hw_params_test_format (pcm, hw, SND_PCM_FORMAT_S32) == 0)
    {
        fmt->i_format = VLC_CODEC_S32N;
        pcm_format = SND_PCM_FORMAT_S32;
    }
    else
    if (snd_pcm_hw_params_test_format (pcm, hw, SND_PCM_FORMAT_S16) == 0)
    {
        fmt->i_format = VLC_CODEC_S16N;
        pcm_format = SND_PCM_FORMAT_S16;
    }
    else
    {
        msg_Err (aout, "no supported sample format");
        goto error;
    }

    val = snd_pcm_hw_params_set_format (pcm, hw, pcm_format);
    if (val)
    {
        msg_Err (aout, "cannot set sample format: %s", snd_strerror (val));
        goto error;
    }

    /* Set channels count */
    unsigned channels;
    if (!spdif)
    {
        uint16_t map = var_InheritInteger (aout, "alsa-audio-channels");

        sys->chans_to_reorder = SetupChannels (VLC_OBJECT(aout), pcm, &map,
                                               sys->chans_table);
        fmt->i_physical_channels = map;
        channels = popcount (map);
    }
    else
    {
        sys->chans_to_reorder = 0;
        channels = 2;
    }

    /* By default, ALSA plug will pad missing channels with zeroes, which is
     * usually fine. However, it will also discard extraneous channels, which
     * is not acceptable. Thus the user must configure the physically
     * available channels, and VLC will downmix if needed. */
    val = snd_pcm_hw_params_set_channels (pcm, hw, channels);
    if (val)
    {
        msg_Err (aout, "cannot set %u channels: %s", channels,
                 snd_strerror (val));
        goto error;
    }

    /* Set sample rate */
    val = snd_pcm_hw_params_set_rate_near (pcm, hw, &fmt->i_rate, NULL);
    if (val)
    {
        msg_Err (aout, "cannot set sample rate: %s", snd_strerror (val));
        goto error;
    }
    sys->rate = fmt->i_rate;

#if 1 /* work-around for period-long latency outputs (e.g. PulseAudio): */
    param = AOUT_MIN_PREPARE_TIME;
    val = snd_pcm_hw_params_set_period_time_near (pcm, hw, &param, NULL);
    if (val)
    {
        msg_Err (aout, "cannot set period: %s", snd_strerror (val));
        goto error;
    }
#endif
    /* Set buffer size */
    param = AOUT_MAX_ADVANCE_TIME;
    val = snd_pcm_hw_params_set_buffer_time_near (pcm, hw, &param, NULL);
    if (val)
    {
        msg_Err (aout, "cannot set buffer duration: %s", snd_strerror (val));
        goto error;
    }
#if 0
    val = snd_pcm_hw_params_get_buffer_time (hw, &param, NULL);
    if (val)
    {
        msg_Warn (aout, "cannot get buffer time: %s", snd_strerror(val));
        param = AOUT_MIN_PREPARE_TIME;
    }
    else
        param /= 2;
    val = snd_pcm_hw_params_set_period_time_near (pcm, hw, &param, NULL);
    if (val)
    {
        msg_Err (aout, "cannot set period: %s", snd_strerror (val));
        goto error;
    }
#endif

    /* Commit hardware parameters */
    val = snd_pcm_hw_params (pcm, hw);
    if (val < 0)
    {
        msg_Err (aout, "cannot commit hardware parameters: %s",
                 snd_strerror (val));
        goto error;
    }
    Dump (aout, "final HW setup:\n", snd_pcm_hw_params_dump, hw);

    /* Get Initial software parameters */
    snd_pcm_sw_params_t *sw;

    snd_pcm_sw_params_alloca (&sw);
    snd_pcm_sw_params_current (pcm, sw);
    Dump (aout, "initial software parameters:\n", snd_pcm_sw_params_dump, sw);

    /* START REVISIT */
    //snd_pcm_sw_params_set_avail_min( pcm, sw, i_period_size );
    // FIXME: useful?
    val = snd_pcm_sw_params_set_start_threshold (pcm, sw, 1);
    if( val < 0 )
    {
        msg_Err( aout, "unable to set start threshold (%s)",
                 snd_strerror( val ) );
        goto error;
    }
    /* END REVISIT */

    /* Commit software parameters. */
    val = snd_pcm_sw_params (pcm, sw);
    if (val)
    {
        msg_Err (aout, "cannot commit software parameters: %s",
                 snd_strerror (val));
        goto error;
    }
    Dump (aout, "final software parameters:\n", snd_pcm_sw_params_dump, sw);

    val = snd_pcm_prepare (pcm);
    if (val)
    {
        msg_Err (aout, "cannot prepare device: %s", snd_strerror (val));
        goto error;
    }

    var_Create(aout->obj.libvlc, "powervlc-kms3d-audio-prime",
               VLC_VAR_BOOL);
    if (spdif && sys->iec958_rearm_pending) {
        bool after_modeset = var_GetBool(
            aout->obj.libvlc, "powervlc-kms3d-audio-prime");
        if (after_modeset)
            var_SetBool(aout->obj.libvlc,
                        "powervlc-kms3d-audio-prime", false);
        unsigned prime_ms = after_modeset ? 3000 : 1000;
        if (PrimeRawHdmiCarrier(aout, prime_ms) == 0) {
            snd_pcm_drop(pcm);
            SetRawHdmiPlaybackSwitch(aout, pcm, false);
            struct timespec reset_delay = { .tv_nsec = 500000000 };
            while (nanosleep(&reset_delay, &reset_delay) != 0 &&
                   errno == EINTR);
            SetRawHdmiChannelStatus(aout, pcm, true, fmt->i_rate);
            SetRawHdmiPlaybackSwitch(aout, pcm, true);
            val = snd_pcm_prepare(pcm);
            if (val < 0) {
                msg_Err(aout, "cannot prepare HDMI after carrier priming: %s",
                        snd_strerror(val));
                goto error;
            }
            sys->iec958_rearm_pending = false;
            msg_Dbg(aout, "primed raw HDMI carrier for %u ms before "
                          "IEC61937 playback", prime_ms);
        }
    }

    /* Setup audio_output_t */
    if (spdif)
    {
        fmt->i_bytes_per_frame = AOUT_SPDIF_SIZE;
        fmt->i_frame_length = A52_FRAME_NB;
    }
    fmt->channel_type = AUDIO_CHANNEL_TYPE_BITMAP;
    sys->format = fmt->i_format;

    aout->time_get = TimeGet;
    aout->play = Play;
    if (snd_pcm_hw_params_can_pause (hw))
        aout->pause = Pause;
    else
    {
        aout->pause = PauseDummy;
        msg_Warn (aout, "device cannot be paused");
    }
    aout->flush = Flush;
    aout_SoftVolumeStart (aout);
    return 0;

error:
    snd_pcm_close (pcm);
    return VLC_EGENERIC;
}

static int TimeGet (audio_output_t *aout, vlc_tick_t *restrict delay)
{
    aout_sys_t *sys = aout->sys;
    snd_pcm_sframes_t frames;

    int val = snd_pcm_delay (sys->pcm, &frames);
    if (val)
    {
        msg_Err (aout, "cannot estimate delay: %s", snd_strerror (val));
        return -1;
    }
    *delay = frames * CLOCK_FREQ / sys->rate;
    return 0;
}

/**
 * Queues one audio buffer to the hardware.
 */
static void Play (audio_output_t *aout, block_t *block)
{
    aout_sys_t *sys = aout->sys;

    if (sys->chans_to_reorder != 0)
        aout_ChannelReorder(block->p_buffer, block->i_buffer,
                           sys->chans_to_reorder, sys->chans_table, sys->format);

    snd_pcm_t *pcm = sys->pcm;

    /* On a raw HDMI PCM, changing the IEC958 switch before hw_params does not
     * necessarily reach the sink: the controller has not generated an audio
     * carrier yet.  Prime it with one valid IEC61937 burst, reset the running
     * PCM, then replay that same burst after the receiver has released the
     * preceding codec.  Doing this within VLC's normal scheduling lead keeps
     * the first programme sample and avoids an audible mid-stream re-arm. */
    if (sys->iec958_rearm_pending) {
        sys->iec958_rearm_pending = false;
        snd_pcm_sframes_t primed = snd_pcm_writei(pcm, block->p_buffer,
                                                  block->i_nb_samples);
        if (primed >= 0) {
            struct timespec carrier_delay = { .tv_nsec = 50000000 };
            while (nanosleep(&carrier_delay, &carrier_delay) != 0 &&
                   errno == EINTR);
            snd_pcm_drop(pcm);
            if (SetRawHdmiPlaybackSwitch(aout, pcm, false) == 0) {
                struct timespec reset_delay = { .tv_nsec = 500000000 };
                while (nanosleep(&reset_delay, &reset_delay) != 0 &&
                       errno == EINTR);
                SetRawHdmiChannelStatus(aout, pcm, true, sys->rate);
                SetRawHdmiPlaybackSwitch(aout, pcm, true);
            }
            if (snd_pcm_prepare(pcm) == 0)
                msg_Dbg(aout, "re-armed running raw HDMI IEC61937 stream");
        }
    }

    /* TODO: better overflow handling */
    /* TODO: no period wake ups */

    while (block->i_nb_samples > 0)
    {
        snd_pcm_sframes_t frames;

        frames = snd_pcm_writei (pcm, block->p_buffer, block->i_nb_samples);
        if (frames >= 0)
        {
            size_t bytes = snd_pcm_frames_to_bytes (pcm, frames);
            block->i_nb_samples -= frames;
            block->p_buffer += bytes;
            block->i_buffer -= bytes;
            // pts, length
        }
        else
        {
            int val = snd_pcm_recover (pcm, frames, 1);
            if (val)
            {
                msg_Err (aout, "cannot recover playback stream: %s",
                         snd_strerror (val));
                DumpDeviceStatus (aout, pcm);
                break;
            }
            msg_Warn (aout, "cannot write samples: %s", snd_strerror (frames));
        }
    }
    block_Release (block);
}

/**
 * Pauses/resumes the audio playback.
 */
static void Pause (audio_output_t *aout, bool pause, vlc_tick_t date)
{
    snd_pcm_t *pcm = aout->sys->pcm;

    int val = snd_pcm_pause (pcm, pause);
    if (unlikely(val))
        PauseDummy (aout, pause, date);
}

static void PauseDummy (audio_output_t *aout, bool pause, vlc_tick_t date)
{
    snd_pcm_t *pcm = aout->sys->pcm;

    /* Stupid device cannot pause. Discard samples. */
    if (pause)
        snd_pcm_drop (pcm);
    else
        snd_pcm_prepare (pcm);
    (void) date;
}

/**
 * Flushes/drains the audio playback buffer.
 */
static void Flush (audio_output_t *aout, bool wait)
{
    snd_pcm_t *pcm = aout->sys->pcm;

    if (wait)
        snd_pcm_drain (pcm);
    else
        snd_pcm_drop (pcm);
    snd_pcm_prepare (pcm);
}


/**
 * Releases the audio output.
 */
static void Stop (audio_output_t *aout)
{
    aout_sys_t *sys = aout->sys;
    snd_pcm_t *pcm = sys->pcm;

    snd_pcm_drop (pcm);
    if (sys->iec958_non_audio) {
        SetRawHdmiPlaybackSwitch(aout, pcm, false);
        SetRawHdmiChannelStatus(aout, pcm, false, sys->rate);
    }
    snd_pcm_close (pcm);
}

/**
 * Enumerates ALSA output devices.
 */
static int EnumDevices(vlc_object_t *obj, char const *varname,
                       char ***restrict idp, char ***restrict namep)
{
    void **hints;

    msg_Dbg (obj, "Available ALSA PCM devices:");
    if (snd_device_name_hint(-1, "pcm", &hints) < 0)
        return -1;

    char **ids = NULL, **names = NULL;
    unsigned n = 0;
    bool hinted_default = false;

    for (size_t i = 0; hints[i] != NULL; i++)
    {
        void *hint = hints[i];

        char *name = snd_device_name_get_hint(hint, "NAME");
        if (unlikely(name == NULL))
            continue;

        char *desc = snd_device_name_get_hint(hint, "DESC");
        if (desc == NULL)
            desc = xstrdup (name);
        for (char *lf = strchr(desc, '\n'); lf; lf = strchr(lf, '\n'))
            *lf = ' ';
        msg_Dbg (obj, "%s (%s)", (desc != NULL) ? desc : name, name);

        ids = xrealloc (ids, (n + 1) * sizeof (*ids));
        names = xrealloc (names, (n + 1) * sizeof (*names));
        ids[n] = name;
        names[n] = desc;
        n++;

        if (!strcmp(name, "default"))
            hinted_default = true;
    }

    snd_device_name_free_hint(hints);

    if (!hinted_default)
    {
        ids = xrealloc (ids, (n + 1) * sizeof (*ids));
        names = xrealloc (names, (n + 1) * sizeof (*names));
        ids[n] = xstrdup ("default");
        names[n] = xstrdup (_("Default"));
        n++;
    }

    *idp = ids;
    *namep = names;
    (void) varname;
    return n;
}

static int DeviceSelect (audio_output_t *aout, const char *id)
{
    aout_sys_t *sys = aout->sys;

    char *device = strdup (id ? id : "default");
    if (unlikely(device == NULL))
        return -1;

    free (sys->device);
    sys->device = device;
    aout_DeviceReport (aout, device);
    aout_RestartRequest (aout, AOUT_RESTART_OUTPUT);
    return 0;
}

static int Open(vlc_object_t *obj)
{
    audio_output_t *aout = (audio_output_t *)obj;
    aout_sys_t *sys = malloc (sizeof (*sys));

    if (unlikely(sys == NULL))
        return VLC_ENOMEM;
    sys->device = var_InheritString (aout, "alsa-audio-device");
    if (unlikely(sys->device == NULL))
        goto error;
    sys->iec958_card = -1;
    sys->iec958_index = -1;
    sys->iec958_non_audio = false;
    aout->sys = sys;
    aout->start = Start;
    aout->stop = Stop;
    aout_SoftVolumeInit (aout);
    aout->device_select = DeviceSelect;
    aout_DeviceReport (aout, sys->device);

    /* ALSA does not support hot-plug events so list devices at startup */
    char **ids, **names;
    int count = EnumDevices (VLC_OBJECT(aout), NULL, &ids, &names);
    if (count >= 0)
    {
        for (int i = 0; i < count; i++)
        {
            aout_HotplugReport (aout, ids[i], names[i]);
            free (names[i]);
            free (ids[i]);
        }
        free (names);
        free (ids);
    }

    return VLC_SUCCESS;
error:
    free (sys);
    return VLC_ENOMEM;
}

static void Close(vlc_object_t *obj)
{
    audio_output_t *aout = (audio_output_t *)obj;
    aout_sys_t *sys = aout->sys;

    free (sys->device);
    free (sys);
}
