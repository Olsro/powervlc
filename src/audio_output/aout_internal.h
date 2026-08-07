/*****************************************************************************
 * aout_internal.h : internal defines for audio output
 *****************************************************************************
 * Copyright (C) 2002 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Christophe Massiot <massiot@via.ecp.fr>
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

#ifndef LIBVLC_AOUT_INTERNAL_H
# define LIBVLC_AOUT_INTERNAL_H 1

# include <vlc_atomic.h>
# include <vlc_viewpoint.h>

/* Max input rate factor (1/4 -> 4) */
# define AOUT_MAX_INPUT_RATE (4)

enum {
    AOUT_RESAMPLING_NONE=0,
    AOUT_RESAMPLING_UP,
    AOUT_RESAMPLING_DOWN
};

struct aout_request_vout
{
    struct vout_thread_t  *(*pf_request_vout)( void *, struct vout_thread_t *,
                                               const video_format_t *, bool );
    void *p_private;
};

typedef struct aout_volume aout_volume_t;
typedef struct aout_dev aout_dev_t;

typedef struct
{
    vlc_mutex_t lock;
    module_t *module; /**< Output plugin (or NULL if inactive) */
    aout_filters_t *filters;
    aout_volume_t *volume;

    struct
    {
        vlc_mutex_t lock;
        char *device;
        float volume;
        signed char mute;
    } req;

    struct
    {
        vlc_mutex_t lock;
        aout_dev_t *list;
        unsigned count;
    } dev;

    struct
    {
        atomic_bool update;
        vlc_mutex_t lock;
        vlc_viewpoint_t value;
    } vp;

    struct
    {
        vlc_tick_t end; /**< Last seen PTS */
        unsigned resamp_start_drift; /**< Resampler drift absolute value */
        int resamp_type; /**< Resampler mode (FIXME: redundant / resampling) */
        bool discontinuity;
        vlc_tick_t gapless_offset; /**< PTS offset of the adopted stream */
        bool b_gapless_pending; /**< Offset to be computed on the next block */

        /* Rolling window of the last drift measurements.
         *
         * When the correction finally reacts, the message it prints carries a
         * single number -- the one that crossed a threshold -- which says
         * nothing about how it got there. A drift that steps by 80 ms in four
         * blocks and one that ramps over ten seconds are entirely different
         * faults and were indistinguishable in the logs. This window is dumped
         * on the events a listener can actually hear, so the shape comes out
         * with them; recording costs three stores per block and nothing is
         * printed while nothing happens. */
#define AOUT_DRIFT_TRACE_COUNT 16
        struct
        {
            vlc_tick_t date;  /**< mdate() at the measurement */
            vlc_tick_t drift; /**< Drift, as the correction sees it */
            vlc_tick_t delay; /**< What the output reported */
        } trace[AOUT_DRIFT_TRACE_COUNT];
        unsigned trace_count; /**< Total recorded, index is modulo the size */

        /* Sample accounting across the filter chain.
         *
         * The drift the correction loop reads is a single number that folds
         * together three independent things: the output's own clock, the pace
         * the decoder is throttled at, and how much audio the filters give
         * back for what they were handed. The first log round could not tell
         * them apart -- a ramp of -28 ms per second was visible with no way to
         * say whether the sound card was running fast or the chain was simply
         * handing over less audio than the PTS timeline claimed.
         *
         * Counting samples in and out settles it on its own, without any
         * clock: the input count times the output rate over the input rate is
         * exactly what should have come out. Anything missing is the chain
         * losing audio, and it is missing whether or not the output plays at
         * the rate it says it does. */
        uint64_t samples_in;  /**< Frames handed to the filters, at input rate */
        uint64_t samples_out; /**< Frames the filters returned, at mixer rate */
        vlc_tick_t report_date; /**< mdate() of the last periodic report */
        vlc_tick_t report_drift; /**< Last drift measured, for the report */
        vlc_tick_t report_delay; /**< Last delay reported by the output */

        /* How many measurements in a row have called for the destructive
         * corrections.
         *
         * Flushing the output and padding it with silence are the two things
         * here a listener can hear, and both used to fire on a single
         * reading. Measured on a Navidrome track: fifteen consecutive
         * measurements between +99 and +116 ms, then one at +183 ms -- a
         * scheduling hiccup on one block -- and the response was to throw
         * away 1.3 s of queued audio and refill it with 1.19 s of zeroes.
         * A threshold crossed once is a sample, not a fault; crossed several
         * times running, it is real and 300 ms of extra patience costs
         * nothing next to a second of silence. */
        unsigned confirm;   /**< Readings required, from "aout-drift-confirm" */
        bool pad_silence;   /**< Correct by silence, from "aout-drift-silence" */
        bool audio_only;    /**< No video and no sout: nothing sees an offset */
        unsigned late_run;  /**< Consecutive readings above the flush bar */
        unsigned early_run; /**< Consecutive readings below the silence bar */
    } sync;

    bool b_dec_parked; /**< Stream still alive with no decoder attached */

    int initial_stereo_mode; /**< Initial stereo mode set by options */

    audio_sample_format_t input_format;
    audio_sample_format_t mixer_format;

    aout_request_vout_t request_vout;
    aout_filters_cfg_t filters_cfg;

    atomic_uint buffers_lost;
    atomic_uint buffers_played;
    atomic_uchar restart;
} aout_owner_t;

typedef struct
{
    audio_output_t output;
    aout_owner_t   owner;
} aout_instance_t;

static inline aout_owner_t *aout_owner (audio_output_t *aout)
{
    return &((aout_instance_t *)aout)->owner;
}

/****************************************************************************
 * Prototypes
 *****************************************************************************/

/* From mixer.c : */
aout_volume_t *aout_volume_New(vlc_object_t *, const audio_replay_gain_t *);
#define aout_volume_New(o, g) aout_volume_New(VLC_OBJECT(o), g)
int aout_volume_SetFormat(aout_volume_t *, vlc_fourcc_t);
void aout_volume_SetVolume(aout_volume_t *, float);
int aout_volume_Amplify(aout_volume_t *, block_t *);
void aout_volume_Delete(aout_volume_t *);


/* From output.c : */
audio_output_t *aout_New (vlc_object_t *);
#define aout_New(a) aout_New(VLC_OBJECT(a))
void aout_Destroy (audio_output_t *);

int aout_OutputNew(audio_output_t *, audio_sample_format_t *,
                   aout_filters_cfg_t *filters_cfg);
int aout_OutputTimeGet(audio_output_t *, vlc_tick_t *);
void aout_OutputPlay(audio_output_t *, block_t *);
void aout_OutputPause( audio_output_t * p_aout, bool, vlc_tick_t );
void aout_OutputFlush( audio_output_t * p_aout, bool );
void aout_OutputDelete( audio_output_t * p_aout );
void aout_OutputLock(audio_output_t *);
void aout_OutputUnlock(audio_output_t *);


/* From common.c : */
void aout_FormatsPrint(vlc_object_t *, const char *,
                       const audio_sample_format_t *,
                       const audio_sample_format_t *);
#define aout_FormatsPrint(o, t, a, b) \
        aout_FormatsPrint(VLC_OBJECT(o), t, a, b)
bool aout_ChangeFilterString( vlc_object_t *manager, vlc_object_t *aout,
                              const char *var, const char *name, bool b_add );

/* From dec.c */
#define AOUT_DEC_SUCCESS 0
#define AOUT_DEC_CHANGED 1
#define AOUT_DEC_FAILED VLC_EGENERIC

int aout_DecNew(audio_output_t *, const audio_sample_format_t *,
                const audio_replay_gain_t *, const aout_request_vout_t *,
                bool b_audio_only);
void aout_DecDelete(audio_output_t *);
void aout_DecDrainAsync(audio_output_t *);
void aout_DecPark(audio_output_t *);
void aout_DecStopParked(audio_output_t *, bool b_wait);
void aout_DecTeardownLocked(audio_output_t *);
int aout_DecPlay(audio_output_t *, block_t *, int i_input_rate);
void aout_DecChangeAudioOnly(audio_output_t *, bool b_audio_only);
void aout_DecGetResetStats(audio_output_t *, unsigned *, unsigned *);
void aout_DecChangePause(audio_output_t *, bool b_paused, vlc_tick_t i_date);
void aout_DecFlush(audio_output_t *, bool wait);
void aout_RequestRestart (audio_output_t *, unsigned);

static inline void aout_InputRequestRestart(audio_output_t *aout)
{
    aout_RequestRestart(aout, AOUT_RESTART_FILTERS);
}

static inline void aout_SetWavePhysicalChannels(audio_sample_format_t *fmt)
{
    static const uint32_t wave_channels[] = {
        AOUT_CHAN_LEFT, AOUT_CHAN_RIGHT, AOUT_CHAN_CENTER,
        AOUT_CHAN_LFE, AOUT_CHAN_REARLEFT, AOUT_CHAN_REARRIGHT,
        AOUT_CHAN_MIDDLELEFT, AOUT_CHAN_MIDDLERIGHT, AOUT_CHAN_REARCENTER };

    fmt->i_physical_channels = 0;
    for (int i = 0; i < fmt->i_channels && i < AOUT_CHAN_MAX; ++i)
        fmt->i_physical_channels |= wave_channels[i];
    aout_FormatPrepare(fmt);
}

/* From filters.c */
bool aout_FiltersCanResample (aout_filters_t *filters);

/**
 * Current resampling adjustment, in Hz applied to the resampler input rate.
 * Instrumentation only: the drift loop nudges this a couple of Hz per block
 * and the logs never showed how far it had wandered.
 */
int aout_FiltersGetResampling (aout_filters_t *filters);

void aout_ChangeViewpoint(audio_output_t *aout,
                          const vlc_viewpoint_t *p_viewpoint);

#endif /* !LIBVLC_AOUT_INTERNAL_H */
