/*****************************************************************************
* qtsound.m: qtkit (Mac OS X) based audio capture module
*****************************************************************************
* Copyright © 2011 VLC authors and VideoLAN
*
* Authors: Pierre d'Herbemont <pdherbemont@videolan.org>
*          Gustaf Neumann <neumann@wu.ac.at>
*          Michael S. Feurstein <michael.feurstein@wu.ac.at>
*
*****************************************************************************
* This library is free software; you can redistribute it and/or
* modify it under the terms of the GNU Lesser General Public License
* as published by the Free Software Foundation; either version 2.1
* of the License, or (at your option) any later version.
*
* This library is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
* Lesser General Public License for more details.
*
* You should have received a copy of the GNU Lesser General Public
* License along with this library; if not, write to the Free Software
* Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110, USA
*
*****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_aout.h>

#include <vlc_demux.h>
#include <vlc_dialog.h>

#define QTKIT_VERSION_MIN_REQUIRED 70200

#import <QTKit/QTKit.h>

/* This public Snow Leopard class is missing from the 10.4 SDK used to keep
 * the universal build compatible with Tiger. Declare its interface only for
 * those old SDKs; QTKit 7.6.3 and newer already declare it themselves. */
#if !defined(QTKIT_VERSION_7_6_3) \
 || QTKIT_VERSION_MAX_ALLOWED < QTKIT_VERSION_7_6_3
@interface QTCaptureDecompressedAudioOutput : QTCaptureOutput
- (void)setDelegate:(id)delegate;
@end
#endif

/*****************************************************************************
 * Local prototypes.
 *****************************************************************************/
static int Open(vlc_object_t *p_this);
static void Close(vlc_object_t *p_this);
static int Demux(demux_t *p_demux);
static int Control(demux_t *, int, va_list);

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/

vlc_module_begin()
set_shortname(N_("QTSound"))
set_description(N_("QuickTime Sound Capture"))
set_category(CAT_INPUT)
set_subcategory(SUBCAT_INPUT_ACCESS)
add_shortcut("qtsound")
set_capability("access_demux", 0)
set_callbacks(Open, Close)
vlc_module_end ()


/*****************************************************************************
 * QTKit Bridge
 *****************************************************************************/
@interface VLCDecompressedAudioDelegate : NSObject
{
    demux_t *p_qtsound;
    void *rawAudioData;
    UInt32 rawAudioDataSize;
    UInt32 numberOfSamples;
    mtime_t currentPts;
}
- (id)initWithDemux:(demux_t *)p_demux;
- (void)captureOutput:(QTCaptureOutput *)captureOutput
 didOutputAudioSampleBuffer:(QTSampleBuffer *)sampleBuffer
       fromConnection:(QTCaptureConnection *)connection;
- (block_t *)copyCurrentAudioBlock;

@end

@implementation VLCDecompressedAudioDelegate
- (id)initWithDemux:(demux_t *)p_demux
{
    if (self = [super init]) {
        p_qtsound = p_demux;
        rawAudioData = NULL;
        rawAudioDataSize = 0;
        currentPts = 0;
    }
    return self;
}
- (void)dealloc
{
    FREENULL(rawAudioData);
    [super dealloc];
}

- (void)captureOutput:(QTCaptureOutput *)captureOutput
 didOutputAudioSampleBuffer:(QTSampleBuffer *)sampleBuffer
       fromConnection:(QTCaptureConnection *)connection
{
    VLC_UNUSED(captureOutput);
    VLC_UNUSED(connection);

    UInt32 samples = [sampleBuffer numberOfSamples];
    AudioBufferList *buffers = [sampleBuffer audioBufferListWithOptions:0];
    if (samples == 0 || buffers == NULL || buffers->mNumberBuffers == 0)
        return;

    int16_t *data = malloc((size_t)samples * 2 * sizeof(*data));
    if (data == NULL) {
        msg_Err(p_qtsound, "Raw audio data could not be allocated");
        return;
    }

    const float *left = buffers->mBuffers[0].mData;
    const float *right = NULL;
    bool interleaved = buffers->mNumberBuffers == 1
                    && buffers->mBuffers[0].mNumberChannels >= 2;
    if (buffers->mNumberBuffers >= 2)
        right = buffers->mBuffers[1].mData;
    size_t leftSamples = (size_t)samples * (interleaved ? 2 : 1);
    if (left == NULL || buffers->mBuffers[0].mDataByteSize
            < leftSamples * sizeof(*left)
     || (right != NULL && buffers->mBuffers[1].mDataByteSize
            < (size_t)samples * sizeof(*right))) {
        free(data);
        msg_Err(p_qtsound, "Invalid QTKit audio buffer layout");
        return;
    }

    UInt32 i;
    for (i = 0; i < samples; i++) {
        float l = left[interleaved ? i * 2 : i];
        float r = right ? right[i] : (interleaved ? left[i * 2 + 1] : l);
        if (l > 1.f) l = 1.f;
        if (l < -1.f) l = -1.f;
        if (r > 1.f) r = 1.f;
        if (r < -1.f) r = -1.f;
        data[i * 2] = (int16_t)(l * 32767.f);
        data[i * 2 + 1] = (int16_t)(r * 32767.f);
    }

    @synchronized (self) {
        FREENULL(rawAudioData);
        rawAudioData = data;
        rawAudioDataSize = samples * 2 * sizeof(*data);
        numberOfSamples = samples;
        currentPts = mdate();
    }
}

- (block_t *)copyCurrentAudioBlock
{
    @synchronized (self) {
        if (rawAudioData == NULL || rawAudioDataSize == 0)
            return NULL;
        block_t *block = block_Alloc(rawAudioDataSize);
        if (block == NULL)
            return NULL;
        memcpy(block->p_buffer, rawAudioData, rawAudioDataSize);
        block->i_nb_samples = numberOfSamples;
        block->i_pts = block->i_dts = currentPts;
        FREENULL(rawAudioData);
        rawAudioDataSize = 0;
        return block;
    }
}

@end

/*****************************************************************************
 * Struct
 *****************************************************************************/

struct demux_sys_t {
    QTCaptureSession * session;
    QTCaptureDevice * audiodevice;
    QTCaptureDecompressedAudioOutput * audiooutput;
    VLCDecompressedAudioDelegate * audiodelegate;
    es_out_id_t *p_es_audio;
    mtime_t demux_time;
};

/*****************************************************************************
 * Open: initialize interface
 *****************************************************************************/
static int Open(vlc_object_t *p_this)
{
    demux_t *p_demux = (demux_t*)p_this;
    demux_sys_t *p_sys;
    es_format_t audiofmt;
    char *psz_uid = NULL;
    int audiocodec;
    bool success;
    NSString *qtk_curraudiodevice_uid;
    NSAutoreleasePool *pool;
    NSArray *myAudioDevices;
    QTCaptureDeviceInput *audioInput = nil;
    NSError *o_returnedAudioError;

    if(p_demux->psz_location && *p_demux->psz_location)
        psz_uid = p_demux->psz_location;

    msg_Dbg(p_demux, "qtsound uid = %s", psz_uid ? psz_uid : "");
    qtk_curraudiodevice_uid = [NSString stringWithUTF8String:
        psz_uid ? psz_uid : ""];

    pool = [[NSAutoreleasePool alloc] init];

    p_demux->p_sys = p_sys = calloc(1, sizeof(demux_sys_t));
    if(!p_sys)
        return VLC_ENOMEM;

    msg_Dbg(p_demux, "qtsound : uid = %s", [qtk_curraudiodevice_uid UTF8String]);
    myAudioDevices = [[[QTCaptureDevice inputDevicesWithMediaType:QTMediaTypeSound]
        arrayByAddingObjectsFromArray:[QTCaptureDevice inputDevicesWithMediaType:@"muxx"]] retain];
    if([myAudioDevices count] == 0) {
        vlc_dialog_display_error(p_demux, _("No Audio Input device found"), "%s",
            _("Your Mac does not seem to be equipped with a suitable audio input device. "
              "Please check your connectors and drivers."));
        msg_Err(p_demux, "Can't find any Audio device");

        goto error;
    }
    unsigned iaudio;
    for (iaudio = 0; iaudio < [myAudioDevices count]; iaudio++) {
        QTCaptureDevice *qtk_audioDevice;
        qtk_audioDevice = [myAudioDevices objectAtIndex:iaudio];
        msg_Dbg(p_demux, "qtsound audio %u/%lu localizedDisplayName: %s uniqueID: %s", iaudio, [myAudioDevices count], [[qtk_audioDevice localizedDisplayName] UTF8String], [[qtk_audioDevice uniqueID] UTF8String]);
        if ([[[qtk_audioDevice uniqueID]stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]] isEqualToString:qtk_curraudiodevice_uid]) {
            msg_Dbg(p_demux, "Device found");
            break;
        }
    }

    audioInput = nil;
    if(iaudio < [myAudioDevices count])
        p_sys->audiodevice = [myAudioDevices objectAtIndex:iaudio];
    else {
        /* cannot find designated audio device, fall back to open default audio device */
        msg_Dbg(p_demux, "Cannot find designated uid audio device as %s. Fall back to open default audio device.", [qtk_curraudiodevice_uid UTF8String]);
        p_sys->audiodevice = [QTCaptureDevice defaultInputDeviceWithMediaType: QTMediaTypeSound];
    }
    if(!p_sys->audiodevice) {
        vlc_dialog_display_error(p_demux, _("No audio input device found"), "%s",
            _("Your Mac does not seem to be equipped with a suitable audio input device. "
              "Please check your connectors and drivers."));
        msg_Err(p_demux, "Can't find any Audio device");

        goto error;
    }

    if(![p_sys->audiodevice open: &o_returnedAudioError]) {
        msg_Err(p_demux, "Unable to open the audio capture device (%ld)", [o_returnedAudioError code]);
        goto error;
    }

    if([p_sys->audiodevice isInUseByAnotherApplication] == YES) {
        msg_Err(p_demux, "default audio capture device is exclusively in use by another application");
        goto error;
    }
    audioInput = [[QTCaptureDeviceInput alloc] initWithDevice: p_sys->audiodevice];
    if(!audioInput) {
        msg_Err(p_demux, "can't create a valid audio capture input facility");
        goto error;
    } else
        msg_Dbg(p_demux, "created valid audio capture input facility");

    Class outputClass = NSClassFromString(@"QTCaptureDecompressedAudioOutput");
    if (outputClass == Nil) {
        msg_Err(p_demux, "QTCaptureDecompressedAudioOutput is unavailable");
        goto error;
    }
    p_sys->audiodelegate = [[VLCDecompressedAudioDelegate alloc]
        initWithDemux:p_demux];
    p_sys->audiooutput = [[outputClass alloc] init];
    [p_sys->audiooutput setDelegate:p_sys->audiodelegate];
    msg_Dbg (p_demux, "initialized audio output");

    /* Now we can init */
    audiocodec = VLC_CODEC_S16L;
    es_format_Init(&audiofmt, AUDIO_ES, audiocodec);

    audiofmt.audio.i_format = audiocodec;
    audiofmt.audio.i_rate = 44100;
    /*
     * i_physical_channels Describes the channels configuration of the
     * samples (ie. number of channels which are available in the
     * buffer, and positions).
     */
    audiofmt.audio.i_physical_channels = AOUT_CHAN_RIGHT | AOUT_CHAN_LEFT;
    /*
     * i_original_channels Describes from which original channels,
     * before downmixing, the buffer is derived.
     */
    /*
     * Please note that it may be completely arbitrary - buffers are not
     * obliged to contain a integral number of so-called "frames". It's
     * just here for the division:
     * buffer_size = i_nb_samples * i_bytes_per_frame / i_frame_length
     */
    audiofmt.audio.i_bitspersample = 16;
    audiofmt.audio.i_channels = 2;
    audiofmt.audio.i_blockalign = audiofmt.audio.i_channels * (audiofmt.audio.i_bitspersample / 8);
    audiofmt.i_bitrate = audiofmt.audio.i_channels * audiofmt.audio.i_rate * audiofmt.audio.i_bitspersample;

    p_sys->session = [[QTCaptureSession alloc] init];

    success = [p_sys->session addInput:audioInput error: &o_returnedAudioError];
    if(!success) {
        msg_Err(p_demux, "the audio capture device could not be added to capture session (%ld)", [o_returnedAudioError code]);
        goto error;
    }

    success = [p_sys->session addOutput:p_sys->audiooutput error: &o_returnedAudioError];
    if(!success) {
        msg_Err(p_demux, "audio output could not be added to capture session (%ld)", [o_returnedAudioError code]);
        goto error;
    }

    [p_sys->session startRunning];

    /* Set up p_demux */
    p_demux->pf_demux = Demux;
    p_demux->pf_control = Control;
    p_demux->info.i_update = 0;
    p_demux->info.i_title = 0;
    p_demux->info.i_seekpoint = 0;

    msg_Dbg(p_demux, "New audio es %d channels %dHz",
            audiofmt.audio.i_channels, audiofmt.audio.i_rate);

    p_sys->p_es_audio = es_out_Add(p_demux->out, &audiofmt);

    [audioInput release];
    [pool release];

    msg_Dbg(p_demux, "QTSound: We have an audio device ready!");

    return VLC_SUCCESS;
error:
    [audioInput release];
    [pool release];

    free(p_sys);

    return VLC_EGENERIC;
}

/*****************************************************************************
 * Close: destroy interface
 *****************************************************************************/
static void Close(vlc_object_t *p_this)
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    demux_t *p_demux = (demux_t*)p_this;
    demux_sys_t *p_sys = p_demux->p_sys;

    /* QTCaptureSession marshals graph changes to the Cocoa main thread. Do
     * not wait here: the main thread can be joining this input during CLI
     * shutdown. Clearing the delegate synchronously prevents late callbacks,
     * while performSelector retains each receiver until teardown executes. */
    [p_sys->audiooutput setDelegate:nil];
    [p_sys->session performSelectorOnMainThread:@selector(stopRunning)
                                      withObject:nil waitUntilDone:NO];
    [p_sys->audiooutput performSelectorOnMainThread:@selector(release)
                                          withObject:nil waitUntilDone:NO];
    [p_sys->session performSelectorOnMainThread:@selector(release)
                                      withObject:nil waitUntilDone:NO];
    [p_sys->audiodelegate release];

    free(p_sys);

    [pool release];
}

/*****************************************************************************
 * Demux:
 *****************************************************************************/
static int Demux(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    block_t *p_blocka = [p_sys->audiodelegate copyCurrentAudioBlock];

    if (p_blocka) {
        p_sys->demux_time = p_blocka->i_pts;
        es_out_Control(p_demux->out, ES_OUT_SET_PCR, p_blocka->i_pts);
        es_out_Send(p_demux->out, p_sys->p_es_audio, p_blocka);
    } else
        msleep(10000);

    return 1;
}

/*****************************************************************************
 * Control:
 *****************************************************************************/
static int Control(demux_t *p_demux, int i_query, va_list args)
{
    bool *pb;
    int64_t *pi64;

    switch(i_query) {
            /* Special for access_demux */
        case DEMUX_CAN_PAUSE:
        case DEMUX_CAN_SEEK:
        case DEMUX_SET_PAUSE_STATE:
        case DEMUX_CAN_CONTROL_PACE:
            pb = (bool*)va_arg(args, bool *);
            *pb = false;
            return VLC_SUCCESS;

        case DEMUX_GET_PTS_DELAY:
            pi64 = (int64_t*)va_arg(args, int64_t *);
            *pi64 = INT64_C(1000) * var_InheritInteger(p_demux, "live-caching");
            return VLC_SUCCESS;

        case DEMUX_GET_TIME:
            *va_arg(args, int64_t *) = p_demux->p_sys->demux_time;
            return VLC_SUCCESS;

        case DEMUX_SET_NEXT_DEMUX_TIME:
            VLC_UNUSED(va_arg(args, int64_t));
            return VLC_SUCCESS;

        default:
            return VLC_EGENERIC;
    }
    return VLC_EGENERIC;
}
