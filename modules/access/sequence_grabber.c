/*****************************************************************************
 * sequence_grabber.c: QuickTime Sequence Grabber capture for legacy macOS
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC authors
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_demux.h>
#include <vlc_fourcc.h>

#include <Carbon/Carbon.h>
#include <QuickTime/QuickTime.h>

#if defined(__LP64__)
# error QuickTime Sequence Grabber is only available to 32-bit processes
#endif

#define WIDTH_TEXT N_("Sequence Grabber video width")
#define HEIGHT_TEXT N_("Sequence Grabber video height")
#define FPS_TEXT N_("Sequence Grabber frame rate")

static int OpenVideo(vlc_object_t *);
static int OpenAudio(vlc_object_t *);
static void Close(vlc_object_t *);
static int Demux(demux_t *);
static int Control(demux_t *, int, va_list);

vlc_module_begin()
    set_shortname(N_("Sequence Grabber"))
    set_description(N_("QuickTime Sequence Grabber video capture"))
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_ACCESS)
    set_capability("access_demux", 5)
    add_shortcut("sgcapture")
    add_integer("sgcapture-width", 640, WIDTH_TEXT, WIDTH_TEXT, true)
        change_integer_range(80, 1920)
    add_integer("sgcapture-height", 480, HEIGHT_TEXT, HEIGHT_TEXT, true)
        change_integer_range(60, 1080)
    add_float("sgcapture-fps", 25.f, FPS_TEXT, FPS_TEXT, true)
        change_float_range(1.f, 60.f)
    set_callbacks(OpenVideo, Close)

    add_submodule()
    set_shortname(N_("Sequence Grabber Audio"))
    set_description(N_("QuickTime Sequence Grabber audio capture"))
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_ACCESS)
    set_capability("access_demux", 5)
    add_shortcut("sgsound")
    set_callbacks(OpenAudio, Close)
vlc_module_end()

struct sg_packet
{
    block_t *block;
    struct sg_packet *next;
};

struct demux_sys_t
{
    SeqGrabComponent grabber;
    SGChannel channel;
    SGDataUPP data_upp;
    bool audio;
    bool swap_audio_16;
    bool movies_entered;
    TimeScale scale;
    mtime_t pts_offset;
    bool pts_offset_set;
    mtime_t demux_time;

    vlc_mutex_t lock;
    struct sg_packet *head;
    struct sg_packet **tail;
    unsigned queued;

    es_out_id_t *es;
    es_format_t fmt;
};

static void QueueClear(demux_sys_t *sys)
{
    struct sg_packet *packet;
    vlc_mutex_lock(&sys->lock);
    packet = sys->head;
    sys->head = NULL;
    sys->tail = &sys->head;
    sys->queued = 0;
    vlc_mutex_unlock(&sys->lock);

    while (packet != NULL) {
        struct sg_packet *next = packet->next;
        block_Release(packet->block);
        free(packet);
        packet = next;
    }
}

static block_t *QueuePop(demux_sys_t *sys)
{
    vlc_mutex_lock(&sys->lock);
    struct sg_packet *packet = sys->head;
    if (packet != NULL) {
        sys->head = packet->next;
        if (sys->head == NULL)
            sys->tail = &sys->head;
        sys->queued--;
    }
    vlc_mutex_unlock(&sys->lock);
    if (packet == NULL)
        return NULL;
    block_t *block = packet->block;
    free(packet);
    return block;
}

/* The callback is entered from SGIdle() and, for some drivers, from a
 * QuickTime worker thread.  Copy the sample and hand it to VLC's demux thread;
 * never call es_out from inside the Component Manager callback. */
static pascal OSErr GrabDataProc(SGChannel channel, Ptr data, long length,
                                long *offset, long channel_refcon,
                                TimeValue time, short write_type, long refcon)
{
    VLC_UNUSED(channel);
    VLC_UNUSED(offset);
    VLC_UNUSED(channel_refcon);

    demux_sys_t *sys = (demux_sys_t *)(uintptr_t)(unsigned long)refcon;
    if (sys == NULL)
        return noErr;
    /* Sound channels reserve storage first, then provide the actual samples
     * in a seqGrabWriteFill callback on a later SGIdle().  Video channels use
     * seqGrabWriteAppend. */
    if (write_type == seqGrabWriteReserve)
        return noErr;
    if (data == NULL || length <= 0
     || (write_type != seqGrabWriteAppend
      && write_type != seqGrabWriteFill))
        return noErr;

    block_t *block = block_Alloc((size_t)length);
    struct sg_packet *packet = malloc(sizeof(*packet));
    if (block == NULL || packet == NULL) {
        if (block != NULL)
            block_Release(block);
        free(packet);
        return memFullErr;
    }
    memcpy(block->p_buffer, data, (size_t)length);
    if (sys->swap_audio_16) {
        for (long i = 0; i + 1 < length; i += 2) {
            uint8_t byte = block->p_buffer[i];
            block->p_buffer[i] = block->p_buffer[i + 1];
            block->p_buffer[i + 1] = byte;
        }
    }
    mtime_t capture_pts = (mtime_t)((int64_t)time * CLOCK_FREQ / sys->scale);
    vlc_mutex_lock(&sys->lock);
    if (!sys->pts_offset_set) {
        /* Sequence Grabber channel time starts at zero, whereas QTKit video
         * and VLC use the host monotonic clock. Anchor the first callback so
         * an sgsound input slave stays synchronized with qtcapture. */
        sys->pts_offset = mdate() - capture_pts;
        sys->pts_offset_set = true;
    }
    mtime_t pts = sys->pts_offset + capture_pts;
    vlc_mutex_unlock(&sys->lock);
    block->i_pts = block->i_dts = pts;
    if (sys->audio) {
        unsigned bytes = sys->fmt.audio.i_channels
                       * (sys->fmt.audio.i_bitspersample / 8);
        if (bytes > 0)
            block->i_nb_samples = length / bytes;
    }
    packet->block = block;
    packet->next = NULL;

    vlc_mutex_lock(&sys->lock);
    /* A stalled consumer must not let an old capture driver exhaust memory. */
    unsigned limit = sys->audio ? 128 : 32;
    if (sys->queued >= limit) {
        struct sg_packet *old = sys->head;
        sys->head = old->next;
        if (sys->head == NULL)
            sys->tail = &sys->head;
        sys->queued--;
        block_Release(old->block);
        free(old);
    }
    *sys->tail = packet;
    sys->tail = &packet->next;
    sys->queued++;
    vlc_mutex_unlock(&sys->lock);
    return noErr;
}

static int SelectDevice(demux_t *demux, SGChannel channel)
{
    demux_sys_t *sys = demux->p_sys;
    unsigned device_index = 0;
    int input_index = -1;
    if (demux->psz_location != NULL && *demux->psz_location != '\0') {
        if (sscanf(demux->psz_location, "%u:%d", &device_index,
                   &input_index) < 1)
            return VLC_EGENERIC;
    }

    SGDeviceList list = NULL;
    ComponentResult err = SGGetChannelDeviceList(channel,
        sgDeviceListIncludeInputs, &list);
    if (err != noErr || list == NULL) {
        msg_Err(demux, "SGGetChannelDeviceList failed: %ld", (long)err);
        return VLC_EGENERIC;
    }

    HLock((Handle)list);
    SGDeviceListPtr devices = *list;
    msg_Dbg(demux, "Sequence Grabber device list has %d entries; requested %u:%d",
            (int)devices->count, device_index, input_index);
    if (device_index < (unsigned)devices->count)
        msg_Dbg(demux, "Sequence Grabber device %u flags: 0x%lx",
                device_index, (unsigned long)devices->entry[device_index].flags);
    if (device_index >= (unsigned)devices->count
     || (devices->entry[device_index].flags
         & sgDeviceNameFlagDeviceUnavailable)) {
        msg_Err(demux, "Sequence Grabber device %u is absent or unavailable",
                device_index);
        HUnlock((Handle)list);
        SGDisposeDeviceList(sys->grabber, list);
        return VLC_EGENERIC;
    }

    err = SGSetChannelDevice(channel, devices->entry[device_index].name);
    if (err == noErr && input_index >= 0)
        err = SGSetChannelDeviceInput(channel, (short)input_index);
    HUnlock((Handle)list);
    SGDisposeDeviceList(sys->grabber, list);
    if (err != noErr)
        msg_Err(demux, "selecting Sequence Grabber device %u:%d failed: %ld",
                device_index, input_index, (long)err);
    return err == noErr ? VLC_SUCCESS : VLC_EGENERIC;
}

static int ConfigureFormat(demux_t *demux)
{
    demux_sys_t *sys = demux->p_sys;
    Handle description = NewHandle(0);
    if (description == NULL)
        return VLC_ENOMEM;
    ComponentResult err = SGGetChannelSampleDescription(sys->channel,
                                                         description);
    if (err != noErr) {
        msg_Err(demux, "SGGetChannelSampleDescription failed: %ld",
                (long)err);
        DisposeHandle(description);
        return VLC_EGENERIC;
    }

    HLock(description);
    if (sys->audio) {
        const SoundDescription *sound = *(SoundDescriptionHandle)description;
        vlc_fourcc_t codec = vlc_fourcc_GetCodecAudio(sound->dataFormat,
                                                       sound->sampleSize);
        if (codec == 0)
            codec = VLC_CODEC_S16N;
        /* VLC's record output supports little-endian PCM in WAV/AVI. Legacy
         * QuickTime reports 'twos' on Intel Tiger even though it supplies
         * native little-endian bytes; PowerPC supplies actual big-endian. */
        if (codec == VLC_CODEC_S16B && sound->sampleSize == 16) {
            codec = VLC_CODEC_S16L;
#ifdef WORDS_BIGENDIAN
            sys->swap_audio_16 = true;
#endif
        }
        es_format_Init(&sys->fmt, AUDIO_ES, codec);
        sys->fmt.audio.i_channels = sound->numChannels;
        sys->fmt.audio.i_rate = ((uint32_t)sound->sampleRate) >> 16;
        sys->fmt.audio.i_bitspersample = sound->sampleSize;
        sys->fmt.audio.i_blockalign = sound->numChannels
                                    * ((sound->sampleSize + 7) / 8);
        sys->fmt.i_bitrate = sys->fmt.audio.i_rate
                           * sys->fmt.audio.i_channels
                           * sys->fmt.audio.i_bitspersample;
    } else {
        const ImageDescription *image = *(ImageDescriptionHandle)description;
        vlc_fourcc_t codec = vlc_fourcc_GetCodec(VIDEO_ES, image->cType);
        if (codec == 0)
            codec = image->cType;
        es_format_Init(&sys->fmt, VIDEO_ES, codec);
        sys->fmt.video.i_width = sys->fmt.video.i_visible_width = image->width;
        sys->fmt.video.i_height = sys->fmt.video.i_visible_height = image->height;
        float fps = var_InheritFloat(demux, "sgcapture-fps");
        sys->fmt.video.i_frame_rate = (unsigned)(fps * 1000.f);
        sys->fmt.video.i_frame_rate_base = 1000;
    }
    HUnlock(description);
    DisposeHandle(description);

    sys->es = es_out_Add(demux->out, &sys->fmt);
    return sys->es != NULL ? VLC_SUCCESS : VLC_EGENERIC;
}

static int OpenCommon(vlc_object_t *object, bool audio)
{
    demux_t *demux = (demux_t *)object;
    demux_sys_t *sys = calloc(1, sizeof(*sys));
    if (sys == NULL)
        return VLC_ENOMEM;
    demux->p_sys = sys;
    sys->audio = audio;
    sys->tail = &sys->head;
    vlc_mutex_init(&sys->lock);

    ComponentResult err = EnterMovies();
    if (err != noErr) {
        msg_Err(demux, "EnterMovies failed: %ld", (long)err);
        goto error;
    }
    sys->movies_entered = true;
    sys->grabber = OpenDefaultComponent(SeqGrabComponentType, 0);
    if (sys->grabber == NULL) {
        msg_Err(demux, "no Sequence Grabber component");
        goto error;
    }
    if ((err = SGInitialize(sys->grabber)) != noErr) {
        msg_Err(demux, "SGInitialize failed: %ld", (long)err);
        goto error;
    }
    if ((err = SGSetDataRef(sys->grabber, 0, 0,
                            seqGrabDontMakeMovie)) != noErr) {
        msg_Err(demux, "SGSetDataRef failed: %ld", (long)err);
        goto error;
    }

    OSType media_type = audio ? SoundMediaType : VideoMediaType;
    if ((err = SGNewChannel(sys->grabber, media_type,
                            &sys->channel)) != noErr) {
        msg_Err(demux, "SGNewChannel failed: %ld", (long)err);
        goto error;
    }
    if (SelectDevice(demux, sys->channel) != VLC_SUCCESS)
        goto error;
    if ((err = SGSetChannelUsage(sys->channel, seqGrabRecord)) != noErr) {
        msg_Err(demux, "SGSetChannelUsage failed: %ld", (long)err);
        goto error;
    }

    if (audio) {
        if (SGSetSoundInputParameters(sys->channel, 16, 2,
                                      k16BitNativeEndianFormat) != noErr)
            msg_Warn(demux, "capture device kept its native audio format");
    } else {
        Rect bounds = { 0, 0,
            (short)var_InheritInteger(demux, "sgcapture-height"),
            (short)var_InheritInteger(demux, "sgcapture-width") };
        SGSetChannelBounds(sys->channel, &bounds);
        SGSetFrameRate(sys->channel,
            FloatToFixed(var_InheritFloat(demux, "sgcapture-fps")));
    }

    sys->data_upp = NewSGDataUPP(GrabDataProc);
    if (sys->data_upp == NULL) {
        msg_Err(demux, "NewSGDataUPP failed");
        goto error;
    }
    if ((err = SGSetDataProc(sys->grabber, sys->data_upp,
                             (long)(uintptr_t)sys)) != noErr) {
        msg_Err(demux, "SGSetDataProc failed: %ld", (long)err);
        goto error;
    }
    if ((err = SGPrepare(sys->grabber, false, true)) != noErr) {
        msg_Err(demux, "SGPrepare failed: %ld", (long)err);
        goto error;
    }
    if ((err = SGGetChannelTimeScale(sys->channel, &sys->scale)) != noErr
     || sys->scale <= 0) {
        msg_Err(demux, "SGGetChannelTimeScale failed: %ld (scale %ld)",
                (long)err, (long)sys->scale);
        goto error;
    }
    if (ConfigureFormat(demux) != VLC_SUCCESS)
        goto error;
    if ((err = SGStartRecord(sys->grabber)) != noErr) {
        msg_Err(demux, "SGStartRecord failed: %ld", (long)err);
        goto error;
    }

    demux->pf_demux = Demux;
    demux->pf_control = Control;
    msg_Dbg(demux, "Sequence Grabber %s capture started (%4.4s)",
            audio ? "audio" : "video", (const char *)&sys->fmt.i_codec);
    return VLC_SUCCESS;

error:
    Close(object);
    return VLC_EGENERIC;
}

static int OpenVideo(vlc_object_t *object)
{
    return OpenCommon(object, false);
}

static int OpenAudio(vlc_object_t *object)
{
    return OpenCommon(object, true);
}

static void Close(vlc_object_t *object)
{
    demux_t *demux = (demux_t *)object;
    demux_sys_t *sys = demux->p_sys;
    if (sys == NULL)
        return;
    if (sys->grabber != NULL) {
        SGStop(sys->grabber);
        SGSetDataProc(sys->grabber, NULL, 0);
    }
    QueueClear(sys);
    if (sys->data_upp != NULL) {
        DisposeSGDataUPP(sys->data_upp);
    }
    if (sys->channel != NULL && sys->grabber != NULL)
        SGDisposeChannel(sys->grabber, sys->channel);
    if (sys->grabber != NULL)
        CloseComponent(sys->grabber);
    es_format_Clean(&sys->fmt);
    vlc_mutex_destroy(&sys->lock);
    if (sys->movies_entered)
        ExitMovies();
    free(sys);
    demux->p_sys = NULL;
}

static int Demux(demux_t *demux)
{
    demux_sys_t *sys = demux->p_sys;
    ComponentResult err = SGIdle(sys->grabber);
    if (err != noErr) {
        msg_Err(demux, "SGIdle failed: %d", (int)err);
        return VLC_DEMUXER_EGENERIC;
    }

    block_t *block = QueuePop(sys);
    if (block == NULL) {
        msleep(10000);
        return VLC_DEMUXER_SUCCESS;
    }
    sys->demux_time = block->i_pts;
    es_out_Control(demux->out, ES_OUT_SET_PCR, block->i_pts);
    es_out_Send(demux->out, sys->es, block);
    return VLC_DEMUXER_SUCCESS;
}

static int Control(demux_t *demux, int query, va_list args)
{
    switch (query) {
        case DEMUX_CAN_PAUSE:
        case DEMUX_CAN_SEEK:
        case DEMUX_CAN_CONTROL_PACE:
        case DEMUX_SET_PAUSE_STATE:
            *va_arg(args, bool *) = false;
            return VLC_SUCCESS;
        case DEMUX_GET_PTS_DELAY:
            *va_arg(args, int64_t *) = INT64_C(1000)
                * var_InheritInteger(demux, "live-caching");
            return VLC_SUCCESS;
        case DEMUX_GET_TIME:
            /* SlaveDemux compares this value with the master's clock and
             * only calls us while we are behind. Reporting mdate() before
             * emitting data made a live audio slave look caught up forever. */
            *va_arg(args, int64_t *) = demux->p_sys->demux_time;
            return VLC_SUCCESS;
        case DEMUX_SET_NEXT_DEMUX_TIME:
            /* Live capture cannot seek to a requested timestamp. Accepting
             * the hint tells SlaveDemux to poll us once per master cycle
             * instead of spinning until the next one-second audio chunk. */
            VLC_UNUSED(va_arg(args, int64_t));
            return VLC_SUCCESS;
        default:
            return VLC_EGENERIC;
    }
}
