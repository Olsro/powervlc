/*****************************************************************************
 * coreaudio_common.h: Common AudioUnit code for iOS and macOS
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

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import <vlc_common.h>
#import <vlc_aout.h>
#import <vlc_threads.h>

#import <AudioUnit/AudioUnit.h>
#import <AudioToolbox/AudioToolbox.h>
#if defined(__has_include) && !__has_include(<os/lock.h>)
/* Building against a pre-10.12 SDK (e.g. the 10.4u one): keep the union
 * layout compiling; the weak-symbol runtime checks in coreaudio_common.c
 * then always take the pthread mutex path (the symbol resolves to NULL
 * at build time below, and would anyway on such an old OS). */
typedef struct { uint32_t _os_unfair_lock_opaque; } os_unfair_lock;
# define OS_UNFAIR_LOCK_INIT ((os_unfair_lock){0})
# define VLC_CA_NO_UNFAIR_LOCK 1
#else
# import <os/lock.h>
#endif
#import <mach/mach_time.h>

#if !defined(MAC_OS_X_VERSION_MAX_ALLOWED) || MAC_OS_X_VERSION_MAX_ALLOWED < 1060
/* Pre-10.6 SDK: the AudioComponent API does not exist yet; map it onto the
 * Component Manager, of which it is a deliberate drop-in replacement
 * (identical struct field names and semantics). AudioDeviceIOProcID (10.5)
 * likewise degrades to the plain IOProc pointer. */
#import <CoreServices/CoreServices.h>
typedef ComponentDescription AudioComponentDescription;
typedef Component            AudioComponent;
typedef ComponentInstance    AudioComponentInstance;
typedef UInt32               AudioFormatID;
typedef AudioDeviceIOProc    AudioDeviceIOProcID;
#define AudioComponentFindNext(comp, desc) \
    FindNextComponent((comp), (ComponentDescription *)(desc))
#define AudioComponentInstanceNew(comp, outInst) \
    OpenAComponent((comp), (outInst))
#define AudioComponentInstanceDispose(inst) \
    CloseComponent(inst)
static inline OSStatus
AudioDeviceCreateIOProcID(AudioDeviceID dev, AudioDeviceIOProc proc,
                          void *data, AudioDeviceIOProcID *out)
{
    OSStatus err = AudioDeviceAddIOProc(dev, proc, data);
    if (err == noErr && out != NULL)
        *out = proc;
    return err;
}
static inline OSStatus
AudioDeviceDestroyIOProcID(AudioDeviceID dev, AudioDeviceIOProcID proc)
{
    return AudioDeviceRemoveIOProc(dev, proc);
}
#ifndef kAudioObjectPropertyScopeOutput /* 10.5+; same 'outp' FourCC */
# define kAudioObjectPropertyScopeOutput kAudioDevicePropertyScopeOutput
#endif
#ifndef kAudioFormatEnhancedAC3 /* 10.9+ header constant, FourCC 'ec-3' */
# define kAudioFormatEnhancedAC3 ((AudioFormatID)0x65632D33)
#endif
#endif /* SDK < 10.6 */

#define STREAM_FORMAT_MSG(pre, sfm) \
    pre "[%f][%4.4s][%u][%u][%u][%u][%u][%u]", \
    sfm.mSampleRate, (char *)&sfm.mFormatID, \
    (unsigned int)sfm.mFormatFlags, (unsigned int)sfm.mBytesPerPacket, \
    (unsigned int)sfm.mFramesPerPacket, (unsigned int)sfm.mBytesPerFrame, \
    (unsigned int)sfm.mChannelsPerFrame, (unsigned int)sfm.mBitsPerChannel

#define ca_LogErr(fmt) msg_Err(p_aout, fmt ", OSStatus: %d", (int) err)
#define ca_LogWarn(fmt) msg_Warn(p_aout, fmt ", OSStatus: %d", (int) err)

struct aout_sys_common
{
    /* The following is owned by common.c (initialized from ca_Open, cleaned
     * from ca_Close) */

    mach_timebase_info_data_t tinfo;

    size_t              i_underrun_size;
    bool                b_paused;
    bool                b_do_flush;
    /* Vrai dès qu'une garde anti-gel a constaté que le rappel de rendu ne
     * répond plus. Remis à faux par ca_Render : le rappel qui tire EST la
     * preuve que la sortie est revenue, donc l'état se répare tout seul. */
    bool                b_render_dead;

    size_t              i_out_max_size;
    size_t              i_out_size;
    bool                b_played;
    block_t             *p_out_chain;
    block_t             **pp_out_last;
    uint64_t            i_render_host_time;
    uint64_t            i_first_render_host_time;
    uint32_t            i_render_frames;

    /* Encoded outputs cannot use PCM zeroes while their queue is empty: that
     * breaks IEC 61937 framing and makes an HDMI receiver relock with a new
     * latency. AUHAL installs a real-time-safe pause-burst filler here for
     * passthrough; PCM users leave it NULL and keep the normal zero fill. */
    void                (*pf_fill_silence)(audio_output_t *, uint8_t *,
                                           size_t, bool);
    bool                b_silence_started;

    vlc_sem_t           flush_sem;

    union lock
    {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wpartial-availability"
        os_unfair_lock  unfair;
#pragma clang diagnostic pop
        pthread_mutex_t mutex;
    } lock;

    int                 i_rate;
    unsigned int        i_bytes_per_frame;
    unsigned int        i_frame_length;
    uint8_t             chans_to_reorder;
    uint8_t             chan_table[AOUT_CHAN_MAX];
    /* ca_TimeGet extra latency, in micro-seconds */
    vlc_tick_t          i_dev_latency_us;
};

int ca_Open(audio_output_t *p_aout);

void ca_Close(audio_output_t *p_aout);

void ca_Render(audio_output_t *p_aout, uint32_t i_nb_samples, uint64_t i_host_time,
               uint8_t *p_output, size_t i_requested);

int  ca_TimeGet(audio_output_t *p_aout, vlc_tick_t *delay);

void ca_Flush(audio_output_t *p_aout, bool wait);

void ca_Pause(audio_output_t * p_aout, bool pause, vlc_tick_t date);

void ca_Play(audio_output_t * p_aout, block_t * p_block);

int  ca_Initialize(audio_output_t *p_aout, const audio_sample_format_t *fmt,
                   vlc_tick_t i_dev_latency_us, size_t i_render_buffer_size,
                   size_t i_encoded_packet_size);

void ca_Uninitialize(audio_output_t *p_aout);

void ca_SetAliveState(audio_output_t *p_aout, bool alive);

void ca_SetDeviceLatency(audio_output_t *p_aout, vlc_tick_t i_dev_latency_us);

AudioUnit au_NewOutputInstance(audio_output_t *p_aout, OSType comp_sub_type);

void au_DisposeOutputInstance(AudioUnit au);

int  au_Initialize(audio_output_t *p_aout, AudioUnit au,
                   audio_sample_format_t *fmt,
                   const AudioChannelLayout *outlayout, vlc_tick_t i_dev_latency_us,
                   bool *warn_configuration);

void au_Uninitialize(audio_output_t *p_aout, AudioUnit au);
