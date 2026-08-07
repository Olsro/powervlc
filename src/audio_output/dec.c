/*****************************************************************************
 * dec.c : audio output API towards decoders
 *****************************************************************************
 * Copyright (C) 2002-2007 VLC authors and VideoLAN
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

/*****************************************************************************
 * Preamble
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <assert.h>

#include <vlc_common.h>
#include <vlc_aout.h>
#include <vlc_input.h>

#include "aout_internal.h"
#include "libvlc.h"

/**
 * Creates an audio output
 */
int aout_DecNew( audio_output_t *p_aout,
                 const audio_sample_format_t *p_format,
                 const audio_replay_gain_t *p_replay_gain,
                 const aout_request_vout_t *p_request_vout,
                 bool b_audio_only )
{
    if( p_format->i_bitspersample > 0 )
    {
        /* Sanitize audio format, input need to have a valid physical channels
         * layout or a valid number of channels. */
        int i_map_channels = aout_FormatNbChannels( p_format );
        if( ( i_map_channels == 0 && p_format->i_channels == 0 )
           || i_map_channels > AOUT_CHAN_MAX || p_format->i_channels > INPUT_CHAN_MAX )
        {
            msg_Err( p_aout, "invalid audio channels count" );
            return -1;
        }
    }

    if( p_format->i_rate > 384000 )
    {
        msg_Err( p_aout, "excessive audio sample frequency (%u)",
                 p_format->i_rate );
        return -1;
    }
    if( p_format->i_rate < 4000 )
    {
        msg_Err( p_aout, "too low audio sample frequency (%u)",
                 p_format->i_rate );
        return -1;
    }

    aout_owner_t *owner = aout_owner(p_aout);

    /* TODO: reduce lock scope depending on decoder's real need */
    aout_OutputLock (p_aout);

    if (owner->b_dec_parked)
    {
        if (b_audio_only && owner->mixer_format.i_format
         && AOUT_FMTS_IDENTICAL(&owner->input_format, p_format)
         && atomic_load(&owner->restart) == 0)
        {
            /* ADOPTION: leave the output module and the filters alone */
            owner->b_dec_parked = false;
            aout_volume_Delete (owner->volume);
            owner->volume = aout_volume_New (p_aout, p_replay_gain);
            aout_volume_SetFormat (owner->volume, owner->mixer_format.i_format);
            /* The filters keep a pointer to owner->request_vout: only its
             * contents may be rewritten, never its address. */
            owner->request_vout = *p_request_vout;
            owner->sync.b_gapless_pending = true; /* offset set on 1st block */
            owner->sync.gapless_offset = 0;
            owner->sync.discontinuity = false; /* no resync, no flush */
            /* Do NOT touch: sync.end, resamp_type, filters_cfg, stereo-mode */
            msg_Dbg (p_aout, "gapless: adopted parked stream");
            aout_OutputUnlock (p_aout);

            atomic_init (&owner->buffers_lost, 0);
            atomic_init (&owner->buffers_played, 0);
            atomic_store (&owner->vp.update, true);
            return 0;
        }

        msg_Dbg (p_aout, "gapless: parked stream not compatible, "
                 "restarting output");
        if (owner->mixer_format.i_format)
            /* Play out what is still queued (bounded by ~2 s) before tearing
             * the stream down, otherwise the tail of the previous track would
             * be lost. This is the blocking drain that used to happen at the
             * end of that track, just deferred to here. */
            aout_OutputFlush (p_aout, true);
        aout_DecTeardownLocked (p_aout);
        owner->b_dec_parked = false;
        owner->sync.gapless_offset = 0;
        owner->sync.b_gapless_pending = false;
    }

    /* Create the audio output stream */
    owner->volume = aout_volume_New (p_aout, p_replay_gain);

    atomic_store (&owner->restart, 0);
    owner->input_format = *p_format;
    owner->mixer_format = owner->input_format;
    owner->request_vout = *p_request_vout;

    var_Change (p_aout, "stereo-mode", VLC_VAR_SETVALUE,
                &(vlc_value_t) { .i_int = owner->initial_stereo_mode }, NULL);

    owner->filters_cfg = AOUT_FILTERS_CFG_INIT;
    if (aout_OutputNew (p_aout, &owner->mixer_format, &owner->filters_cfg))
        goto error;
    aout_volume_SetFormat (owner->volume, owner->mixer_format.i_format);

    /* Create the audio filtering "input" pipeline */
    owner->filters = aout_FiltersNew (p_aout, p_format, &owner->mixer_format,
                                      &owner->request_vout,
                                      &owner->filters_cfg);
    if (owner->filters == NULL)
    {
        aout_OutputDelete (p_aout);
error:
        aout_volume_Delete (owner->volume);
        owner->volume = NULL;
        aout_OutputUnlock (p_aout);
        return -1;
    }


    owner->sync.end = VLC_TICK_INVALID;
    owner->sync.resamp_type = AOUT_RESAMPLING_NONE;
    owner->sync.discontinuity = true;
    /* A fresh stream: measurements from the previous one would only make the
     * trace lie about how the new one got where it is. */
    owner->sync.trace_count = 0;
    owner->sync.samples_in = 0;
    owner->sync.samples_out = 0;
    owner->sync.report_date = VLC_TICK_INVALID;
    owner->sync.report_drift = 0;
    owner->sync.report_delay = 0;
    owner->sync.late_run = 0;
    owner->sync.early_run = 0;
    owner->sync.confirm = var_InheritInteger (p_aout, "aout-drift-confirm");
    owner->sync.audio_only = b_audio_only;
    switch (var_InheritInteger (p_aout, "aout-drift-silence"))
    {
        case 0:  owner->sync.pad_silence = false; break;  /* never */
        case 2:  owner->sync.pad_silence = true;  break;  /* always */
        default: owner->sync.pad_silence = !b_audio_only; /* auto */
    }
    msg_Dbg (p_aout, "drift policy: %s stream, correcting by %s, "
             "%u reading(s) to confirm", b_audio_only ? "audio-only" : "a/v",
             owner->sync.pad_silence ? "silence" : "resampling",
             owner->sync.confirm);
    if (owner->sync.confirm < 1)
        owner->sync.confirm = 1;
    aout_OutputUnlock (p_aout);

    atomic_init (&owner->buffers_lost, 0);
    atomic_init (&owner->buffers_played, 0);
    atomic_store (&owner->vp.update, true);
    return 0;
}

/**
 * Tells the output that its stream has (or no longer has) video alongside it.
 *
 * The predicate is a property of the input, not of the output, and it can
 * turn from true to false part-way through a stream: an MPEG-TS programme
 * may only declare its video ES after audio has been playing for a while.
 * Reading it once when the output is created would leave such a stream
 * correcting drift the audio-only way -- inaudibly, but by letting the audio
 * run ahead, which is exactly what one must not do once there are pictures
 * to stay in step with.
 *
 * So the input pushes the change instead. It is a latch in practice (an
 * input never loses its video), and it costs nothing per block.
 */
void aout_DecChangeAudioOnly (audio_output_t *aout, bool b_audio_only)
{
    aout_owner_t *owner = aout_owner (aout);

    aout_OutputLock (aout);
    if (owner->sync.audio_only != b_audio_only)
    {
        owner->sync.audio_only = b_audio_only;
        if (var_InheritInteger (aout, "aout-drift-silence") == 1) /* auto */
        {
            owner->sync.pad_silence = !b_audio_only;
            msg_Dbg (aout, "drift policy: now %s stream, correcting by %s",
                     b_audio_only ? "audio-only" : "a/v",
                     owner->sync.pad_silence ? "silence" : "resampling");
        }
    }
    aout_OutputUnlock (aout);
}

/**
 * Stops all plugins involved in the audio output.
 */
void aout_DecTeardownLocked (audio_output_t *aout)
{
    aout_owner_t *owner = aout_owner (aout);

    if (owner->mixer_format.i_format)
    {
        aout_FiltersDelete (aout, owner->filters);
        aout_OutputDelete (aout);
    }
    aout_volume_Delete (owner->volume);
    owner->volume = NULL;
}

void aout_DecDelete (audio_output_t *aout)
{
    aout_owner_t *owner = aout_owner (aout);

    aout_OutputLock (aout);
    aout_DecTeardownLocked (aout);
    owner->b_dec_parked = false;
    owner->sync.gapless_offset = 0;
    owner->sync.b_gapless_pending = false;
    aout_OutputUnlock (aout);
}

/**
 * Drains the filters into the output without waiting for playback to finish.
 * Used at the end of a track when the output stream is about to be parked.
 */
void aout_DecDrainAsync (audio_output_t *aout)
{
    aout_owner_t *owner = aout_owner (aout);

    aout_OutputLock (aout);
    if (owner->mixer_format.i_format)
    {
        block_t *block = aout_FiltersDrain (owner->filters);
        if (block)
        {
            /* Keep sync.end in step: it is what the next track's PTS offset
             * is computed from. */
            if (block->i_pts > VLC_TICK_INVALID)
                owner->sync.end = block->i_pts + block->i_length + 1;
            aout_OutputPlay (aout, block);
        }
    }
    aout_OutputUnlock (aout);
}

/**
 * Keeps the output stream alive (module started, filters and queued audio
 * still playing) while no decoder is attached to it.
 */
void aout_DecPark (audio_output_t *aout)
{
    aout_owner_t *owner = aout_owner (aout);

    aout_OutputLock (aout);
    owner->b_dec_parked = true;
    msg_Dbg (aout, "gapless: parking output stream (buffered until %"PRId64")",
             owner->sync.end);
    aout_OutputUnlock (aout);
}

/**
 * Tears down a parked stream. If b_wait, the queued audio is played out first
 * (bounded by AOUT_MAX_PREPARE_TIME, i.e. ~2 seconds).
 */
void aout_DecStopParked (audio_output_t *aout, bool b_wait)
{
    aout_owner_t *owner = aout_owner (aout);

    aout_OutputLock (aout);
    if (owner->b_dec_parked)
    {
        msg_Dbg (aout, "gapless: stopping parked stream (wait=%d)", b_wait);
        if (owner->mixer_format.i_format)
        {
            if (!b_wait)
                aout_FiltersFlush (owner->filters);
            aout_OutputFlush (aout, b_wait);
        }
        aout_DecTeardownLocked (aout);
        owner->b_dec_parked = false;
        owner->sync.end = VLC_TICK_INVALID;
        owner->sync.gapless_offset = 0;
        owner->sync.b_gapless_pending = false;
    }
    aout_OutputUnlock (aout);
}

static int aout_CheckReady (audio_output_t *aout)
{
    aout_owner_t *owner = aout_owner (aout);

    int status = AOUT_DEC_SUCCESS;
    int restart = atomic_exchange (&owner->restart, 0);
    if (unlikely(restart))
    {
        if (owner->mixer_format.i_format)
            aout_FiltersDelete (aout, owner->filters);

        if (restart & AOUT_RESTART_OUTPUT)
        {   /* Reinitializes the output */
            msg_Dbg (aout, "restarting output...");
            if (owner->mixer_format.i_format)
                aout_OutputDelete (aout);
            owner->mixer_format = owner->input_format;
            owner->filters_cfg = AOUT_FILTERS_CFG_INIT;
            if (aout_OutputNew (aout, &owner->mixer_format, &owner->filters_cfg))
                owner->mixer_format.i_format = 0;
            aout_volume_SetFormat (owner->volume,
                                   owner->mixer_format.i_format);

            /* Notify the decoder that the aout changed in order to try a new
             * suitable codec (like an HDMI audio format). However, keep the
             * same codec if the aout was restarted because of a stereo-mode
             * change from the user. */
            if (restart == AOUT_RESTART_OUTPUT)
                status = AOUT_DEC_CHANGED;
        }

        msg_Dbg (aout, "restarting filters...");
        owner->sync.end = VLC_TICK_INVALID;
        owner->sync.resamp_type = AOUT_RESAMPLING_NONE;

        if (owner->mixer_format.i_format)
        {
            owner->filters = aout_FiltersNew (aout, &owner->input_format,
                                              &owner->mixer_format,
                                              &owner->request_vout,
                                              &owner->filters_cfg);
            if (owner->filters == NULL)
            {
                aout_OutputDelete (aout);
                owner->mixer_format.i_format = 0;
            }
        }
        /* TODO: This would be a good time to call clean up any video output
         * left over by an audio visualization:
        input_resource_TerminatVout(MAGIC HERE); */
    }
    return (owner->mixer_format.i_format) ? status : AOUT_DEC_FAILED;
}

/**
 * Marks the audio output for restart, to update any parameter of the output
 * plug-in (e.g. output device or channel mapping).
 */
void aout_RequestRestart (audio_output_t *aout, unsigned mode)
{
    aout_owner_t *owner = aout_owner (aout);
    atomic_fetch_or (&owner->restart, mode);
    msg_Dbg (aout, "restart requested (%u)", mode);
}

/*
 * Buffer management
 */

static void aout_StopResampling (audio_output_t *aout)
{
    aout_owner_t *owner = aout_owner (aout);

    owner->sync.resamp_type = AOUT_RESAMPLING_NONE;
    aout_FiltersAdjustResampling (owner->filters, 0);
}

static void aout_DecSilence (audio_output_t *aout, vlc_tick_t length, vlc_tick_t pts)
{
    aout_owner_t *owner = aout_owner (aout);
    const audio_sample_format_t *fmt = &owner->mixer_format;
    size_t frames = (fmt->i_rate * length) / CLOCK_FREQ;

    block_t *block = block_Alloc (frames * fmt->i_bytes_per_frame
                                  / fmt->i_frame_length);
    if (unlikely(block == NULL))
        return; /* uho! */

    msg_Dbg (aout, "inserting %zu zeroes", frames);
    memset (block->p_buffer, 0, block->i_buffer);
    block->i_nb_samples = frames;
    block->i_pts = pts;
    block->i_dts = pts;
    block->i_length = length;
    aout_OutputPlay (aout, block);
}

/**
 * Records one drift measurement in the rolling window.
 *
 * Called for every block, so it does nothing but store: the reading of it is
 * in aout_DriftTraceDump(), which only runs when something went wrong.
 */
static void aout_DriftTraceRecord (aout_owner_t *owner, vlc_tick_t now,
                                   vlc_tick_t drift, vlc_tick_t delay)
{
    unsigned i = owner->sync.trace_count % AOUT_DRIFT_TRACE_COUNT;

    owner->sync.trace[i].date = now;
    owner->sync.trace[i].drift = drift;
    owner->sync.trace[i].delay = delay;
    owner->sync.trace_count++;
}

/**
 * Prints the rolling window, oldest measurement first, as one line.
 *
 * Ages are relative to the newest measurement, so the line reads as a
 * history: "-412ms" is what the drift was 412 ms before the event. A drift
 * that steps and a drift that ramps are then obvious at a glance, which is
 * the whole point -- the warning on its own only ever showed the value that
 * crossed the threshold.
 */
static void aout_DriftTraceDump (audio_output_t *aout, const char *psz_why)
{
    aout_owner_t *owner = aout_owner (aout);
    const unsigned i_count = owner->sync.trace_count < AOUT_DRIFT_TRACE_COUNT
                           ? owner->sync.trace_count : AOUT_DRIFT_TRACE_COUNT;

    if (i_count == 0)
        return;

    /* newest first, so ages can be worked out against it */
    const unsigned i_newest =
        (owner->sync.trace_count - 1) % AOUT_DRIFT_TRACE_COUNT;
    const vlc_tick_t t_ref = owner->sync.trace[i_newest].date;

    /* 32 characters per entry is ample for "-1234ms:-123456/-123456 " */
    char psz_buf[AOUT_DRIFT_TRACE_COUNT * 32];
    size_t i_pos = 0;

    for (unsigned n = 0; n < i_count; n++)
    {
        /* walk from the oldest still held to the newest */
        const unsigned i = (owner->sync.trace_count - i_count + n)
                           % AOUT_DRIFT_TRACE_COUNT;
        int i_len = snprintf (psz_buf + i_pos, sizeof (psz_buf) - i_pos,
                              "%s%lldms:%lld/%lld", n ? " " : "",
                              (long long)((owner->sync.trace[i].date - t_ref)
                                          / 1000),
                              (long long)owner->sync.trace[i].drift,
                              (long long)owner->sync.trace[i].delay);
        if (i_len < 0 || (size_t)i_len >= sizeof (psz_buf) - i_pos)
            break;
        i_pos += i_len;
    }

    msg_Dbg (aout, "drift trace (%s), age:drift/delay in us -- %s",
             psz_why, psz_buf);
}

/**
 * Prints one line per second on how the stream is doing, whether or not
 * anything is wrong.
 *
 * The event dumps say what the drift was over the second and a half before a
 * glitch, and that turned out to be too short a window: the first Windows
 * round showed a steady ramp with no visible beginning, so the ramp could not
 * be tied to anything. This runs on every block and speaks once a second, so
 * a whole track fits in a dozen lines.
 *
 * The number to watch is "balance": how much audio the filter chain has
 * returned, against how much it was given, both in milliseconds of playing
 * time. It needs no clock and no output cooperation, so it separates "the
 * chain is losing audio" from "the sound card does not run at the rate it
 * claims" -- which the drift alone can never do.
 */
static void aout_SyncReport (audio_output_t *aout, vlc_tick_t now)
{
    aout_owner_t *owner = aout_owner (aout);

    if (owner->sync.report_date == VLC_TICK_INVALID)
    {
        owner->sync.report_date = now;
        return;
    }
    if (now - owner->sync.report_date < CLOCK_FREQ)
        return;

    const unsigned i_rate_in = owner->input_format.i_rate;
    const unsigned i_rate_out = owner->mixer_format.i_rate;

    if (i_rate_in == 0 || i_rate_out == 0)
        return;

    /* Playing time of what went in, and of what came back out. */
    const vlc_tick_t i_in = owner->sync.samples_in * CLOCK_FREQ / i_rate_in;
    const vlc_tick_t i_out = owner->sync.samples_out * CLOCK_FREQ / i_rate_out;

    msg_Dbg (aout, "sync report: in %"PRIu64" smp / %"PRId64" ms, "
             "out %"PRIu64" smp / %"PRId64" ms, balance %"PRId64" ms "
             "(%.3f %%), resampling %+d Hz, delay %"PRId64" us, "
             "drift %"PRId64" us, wall %"PRId64" ms",
             owner->sync.samples_in, i_in / 1000,
             owner->sync.samples_out, i_out / 1000,
             (i_out - i_in) / 1000,
             i_in ? (100.0 * (double)(i_out - i_in) / (double)i_in) : 0.0,
             aout_FiltersGetResampling (owner->filters),
             owner->sync.report_delay, owner->sync.report_drift,
             (now - owner->sync.report_date) / 1000);

    owner->sync.report_date = now;
}

static void aout_DecSynchronize (audio_output_t *aout, vlc_tick_t dec_pts,
                                 int input_rate)
{
    aout_owner_t *owner = aout_owner (aout);
    vlc_tick_t drift;

    /**
     * Depending on the drift between the actual and intended playback times,
     * the audio core may ignore the drift, trigger upsampling or downsampling,
     * insert silence or even discard samples.
     * Future VLC versions may instead adjust the input rate.
     *
     * The audio output plugin is responsible for estimating its actual
     * playback time, or rather the estimated time when the next sample will
     * be played. (The actual playback time is always the current time, that is
     * to say mdate(). It is not an useful statistic.)
     *
     * Most audio output plugins can estimate the delay until playback of
     * the next sample to be written to the buffer, or equally the time until
     * all samples in the buffer will have been played. Then:
     *    pts = mdate() + delay
     */
    if (aout_OutputTimeGet (aout, &drift) != 0)
        return; /* nothing can be done if timing is unknown */

    const vlc_tick_t delay = drift; /* what the output reported, on its own */
    const vlc_tick_t now = mdate ();

    drift += now - dec_pts;
    aout_DriftTraceRecord (owner, now, drift, delay);
    owner->sync.report_drift = drift;
    owner->sync.report_delay = delay;

    /* Late audio output.
     * This can happen due to insufficient caching, scheduling jitter
     * or bug in the decoder. Ideally, the output would seek backward. But that
     * is not portable, not supported by some hardware and often unsafe/buggy
     * where supported. The other alternative is to flush the buffers
     * completely. */
    const vlc_tick_t i_late_bar = owner->sync.discontinuity ? 0
                  : +3 * input_rate * AOUT_MAX_PTS_DELAY / INPUT_RATE_DEFAULT;

    owner->sync.late_run = (drift > i_late_bar) ? owner->sync.late_run + 1 : 0;

    /* On a discontinuity the queue is known to be wrong, so act at once;
     * otherwise wait for the reading to be confirmed. */
    if (drift > i_late_bar
     && (owner->sync.discontinuity
      || owner->sync.late_run >= owner->sync.confirm))
    {
        owner->sync.late_run = 0;
        if (!owner->sync.discontinuity)
            msg_Warn (aout, "playback way too late (%"PRId64"): "
                      "flushing buffers", drift);
        else
            msg_Dbg (aout, "playback too late (%"PRId64"): "
                     "flushing buffers", drift);
        aout_DriftTraceDump (aout, "late, flushing");
        aout_OutputFlush (aout, false);

        aout_StopResampling (aout);
        owner->sync.end = VLC_TICK_INVALID;
        owner->sync.discontinuity = true;

        /* Now the output might be too early... Recheck. */
        if (aout_OutputTimeGet (aout, &drift) != 0)
            return; /* nothing can be done if timing is unknown */
        drift += mdate () - dec_pts;
    }

    /* Early audio output.
     * This is rare except at startup when the buffers are still empty. */
    const vlc_tick_t i_early_bar = owner->sync.discontinuity ? 0
                : -3 * input_rate * AOUT_MAX_PTS_ADVANCE / INPUT_RATE_DEFAULT;

    owner->sync.early_run = (drift < i_early_bar) ? owner->sync.early_run + 1 : 0;

    /* Padding never prevents an underrun -- that is worth stating, because
     * the branch reads as if it did. The queue holds `delay` of audio and the
     * block is due `|drift|` after it runs out; writing the block straight
     * away plays it that much early, but plays it CONTINUOUSLY. The zeroes
     * buy alignment with the input clock and pay for it with the very gap
     * they appear to be preventing.
     *
     * That trade is right when there is video to stay in step with, and wrong
     * on a music player, where nothing shows the offset and everything shows
     * the hole. Where the resampler is available it can absorb the same
     * offset inaudibly -- measured doing exactly that on this machine, taking
     * a -100 ms drift back through zero. So when padding is turned off, leave
     * the drift alone and let the resampler have it; the give-up bar below
     * has to stand aside too, or it would cut off the only correction left. */
    const bool b_may_pad = owner->sync.discontinuity || owner->sync.pad_silence
                        || !aout_FiltersCanResample (owner->filters);

    if (drift < i_early_bar && b_may_pad
     && (owner->sync.discontinuity
      || owner->sync.early_run >= owner->sync.confirm))
    {
        owner->sync.early_run = 0;
        if (!owner->sync.discontinuity)
        {
            msg_Warn (aout, "playback way too early (%"PRId64"): "
                      "playing silence", drift);
            /* This one the listener hears: it is the gap in the sound. */
            aout_DriftTraceDump (aout, "early, inserting silence");
        }
        aout_DecSilence (aout, -drift, dec_pts);

        aout_StopResampling (aout);
        owner->sync.discontinuity = true;
        drift = 0;
    }

    if (!aout_FiltersCanResample(owner->filters))
        return;

    /* Resampling */
    if (drift > +AOUT_MAX_PTS_DELAY
     && owner->sync.resamp_type != AOUT_RESAMPLING_UP)
    {
        msg_Warn (aout, "playback too late (%"PRId64"): up-sampling",
                  drift);
        owner->sync.resamp_type = AOUT_RESAMPLING_UP;
        owner->sync.resamp_start_drift = +drift;
    }
    if (drift < -AOUT_MAX_PTS_ADVANCE
     && owner->sync.resamp_type != AOUT_RESAMPLING_DOWN)
    {
        msg_Warn (aout, "playback too early (%"PRId64"): down-sampling",
                  drift);
        owner->sync.resamp_type = AOUT_RESAMPLING_DOWN;
        owner->sync.resamp_start_drift = -drift;
    }

    if (owner->sync.resamp_type == AOUT_RESAMPLING_NONE)
        return; /* Everything is fine. Nothing to do. */

    /* Give up only once the correction is genuinely losing ground -- and
     * never while there is still room before the drift becomes audible.
     *
     * Scaling the bar purely on the drift at which correction started meant
     * that the earlier it kicked in, the sooner it quit: measured on a
     * Navidrome track, correction began at -41 ms and was abandoned at
     * -83 ms, a mere 37 ms short of the -120 ms where silence is injected.
     * Resampling then restarted from scratch while the drift ran the rest of
     * the way into that limit, and the listener heard the gap. Stopping the
     * only thing working, just before the point where it matters, cannot be
     * right: floor the bar at the threshold that actually hurts.
     *
     * The safety valve is kept -- a drift that keeps growing past that still
     * stops resampling rather than pitch-shifting for ever. */
    vlc_tick_t i_give_up = 2 * owner->sync.resamp_start_drift;
    const vlc_tick_t i_audible = 3 * input_rate * AOUT_MAX_PTS_ADVANCE
                               / INPUT_RATE_DEFAULT;

    if (i_give_up < i_audible)
        i_give_up = i_audible;

    if (llabs (drift) > i_give_up && b_may_pad)
    {   /* If the drift is ever increasing, then something is seriously wrong.
         * Cease resampling and hope for the best. (Not when resampling is the
         * only correction allowed: giving up would leave nothing at all.) */
        msg_Warn (aout, "timing screwed (drift: %"PRId64" us): "
                  "stopping resampling", drift);
        aout_DriftTraceDump (aout, "correction giving up");
        aout_StopResampling (aout);
        return;
    }

    /* Resampling has been triggered earlier. This checks if it needs to be
     * increased or decreased. Resampling rate changes must be kept slow for
     * the comfort of listeners. */
    int adj = (owner->sync.resamp_type == AOUT_RESAMPLING_UP) ? +2 : -2;

    if (2 * llabs (drift) <= owner->sync.resamp_start_drift)
        /* If the drift has been reduced from more than half its initial
         * value, then it is time to switch back the resampling direction. */
        adj *= -1;

    if (!aout_FiltersAdjustResampling (owner->filters, adj))
    {   /* Everything is back to normal: stop resampling. */
        owner->sync.resamp_type = AOUT_RESAMPLING_NONE;
        msg_Dbg (aout, "resampling stopped (drift: %"PRId64" us)", drift);
    }
}

/*****************************************************************************
 * aout_DecPlay : filter & mix the decoded buffer
 *****************************************************************************/
int aout_DecPlay (audio_output_t *aout, block_t *block, int input_rate)
{
    aout_owner_t *owner = aout_owner (aout);

    assert (input_rate >= INPUT_RATE_DEFAULT / AOUT_MAX_INPUT_RATE);
    assert (input_rate <= INPUT_RATE_DEFAULT * AOUT_MAX_INPUT_RATE);
    assert (block->i_pts >= VLC_TICK_0);

    block->i_length = CLOCK_FREQ * block->i_nb_samples
                                 / owner->input_format.i_rate;

    aout_OutputLock (aout);
    int ret = aout_CheckReady (aout);
    if (unlikely(ret == AOUT_DEC_FAILED))
        goto drop; /* Pipeline is unrecoverably broken :-( */

    const vlc_tick_t now = mdate ();

    /* Gapless: the offset has to be settled BEFORE the buffer can be judged.
     *
     * A joined track arrives on its own input clock, which runs
     * gapless_offset ahead of the moment its audio is really due -- the
     * parked queue of the previous track has to drain first. Judging the RAW
     * PTS therefore made every block of that track look gapless_offset late.
     * Measured on a Navidrome album: an offset of 1.26 s against an
     * AOUT_MAX_PTS_DELAY of 60 ms, so blocks were dropped one after another
     * and the output filled the holes with silence -- chopping every second
     * on a track that had already been downloaded in full.
     *
     * It fed on itself: dropping a buffer keeps the queue below the very
     * depth whose absence caused the drop. Only a manual replay cleared it,
     * because that starts a fresh stream with the offset back at zero --
     * exactly what the bug report described.
     *
     * It also explains why macOS never showed it: the margin is the output
     * queue depth against the offset, and WASAPI's ~2 s buffer sits close
     * enough to a 1.2 s offset to fall the wrong side of it. */
    if (owner->sync.b_gapless_pending)
    {
        owner->sync.b_gapless_pending = false;
        if (owner->sync.end != VLC_TICK_INVALID && owner->sync.end > now)
        {
            owner->sync.gapless_offset = owner->sync.end - block->i_pts;
            msg_Dbg (aout, "gapless: joining streams, offset %"PRId64" us",
                     owner->sync.gapless_offset);
        }
        else
        {   /* Queue already drained (transition too long, pause...) */
            owner->sync.gapless_offset = 0;
            owner->sync.discontinuity = true;
            msg_Dbg (aout, "gapless: parked buffer underran, normal resync");
        }
    }
    block->i_pts += owner->sync.gapless_offset;

    /* Judged on the time it will ACTUALLY be played at. */
    const vlc_tick_t advance = block->i_pts - now;
    if (advance < -AOUT_MAX_PTS_DELAY)
    {   /* Late buffer can be caused by bugs in the decoder, by scheduling
         * latency spikes (excessive load, SIGSTOP, etc.) or if buffering is
         * insufficient. We assume the PTS is wrong and play the buffer anyway:
         * Hopefully video has encountered a similar PTS problem as audio. */
        msg_Warn (aout, "buffer too late (%"PRId64" us): dropped", advance);
        goto drop;
    }
    /* The early bound carries the offset with it: a joined track legitimately
     * sits that much further in the future, and this check exists to catch a
     * decoder handing out nonsense, not that. (This is what the code used to
     * guard against by testing the raw PTS -- at the cost of the late test
     * above, which needs the real one.) */
    if (advance > AOUT_MAX_ADVANCE_TIME + owner->sync.gapless_offset)
    {   /* Early buffers can only be caused by bugs in the decoder. */
        msg_Err (aout, "buffer too early (%"PRId64" us): dropped", advance);
        goto drop;
    }

    if (block->i_flags & BLOCK_FLAG_DISCONTINUITY)
        owner->sync.discontinuity = true;

    if (atomic_exchange(&owner->vp.update, false))
    {
        vlc_mutex_lock (&owner->vp.lock);
        aout_FiltersChangeViewpoint (owner->filters, &owner->vp.value);
        vlc_mutex_unlock (&owner->vp.lock);
    }

    const unsigned i_samples_in = block->i_nb_samples;

    block = aout_FiltersPlay (owner->filters, block, input_rate);
    if (block == NULL)
        goto lost;

    owner->sync.samples_in += i_samples_in;
    owner->sync.samples_out += block->i_nb_samples;

    /* Software volume */
    aout_volume_Amplify (owner->volume, block);

    /* Drift correction */
    aout_DecSynchronize (aout, block->i_pts, input_rate);
    aout_SyncReport (aout, now);

    /* Output */
    owner->sync.end = block->i_pts + block->i_length + 1;
    owner->sync.discontinuity = false;
    aout_OutputPlay (aout, block);
    atomic_fetch_add(&owner->buffers_played, 1);
out:
    aout_OutputUnlock (aout);
    return ret;
drop:
    owner->sync.discontinuity = true;
    block_Release (block);
lost:
    atomic_fetch_add(&owner->buffers_lost, 1);
    goto out;
}

void aout_DecGetResetStats(audio_output_t *aout, unsigned *restrict lost,
                           unsigned *restrict played)
{
    aout_owner_t *owner = aout_owner (aout);

    *lost = atomic_exchange(&owner->buffers_lost, 0);
    *played = atomic_exchange(&owner->buffers_played, 0);
}

void aout_DecChangePause (audio_output_t *aout, bool paused, vlc_tick_t date)
{
    aout_owner_t *owner = aout_owner (aout);

    aout_OutputLock (aout);
    if (owner->sync.end != VLC_TICK_INVALID)
    {
        if (paused)
            owner->sync.end -= date;
        else
            owner->sync.end += date;
    }
    if (owner->mixer_format.i_format)
        aout_OutputPause (aout, paused, date);
    aout_OutputUnlock (aout);
}

void aout_DecFlush (audio_output_t *aout, bool wait)
{
    aout_owner_t *owner = aout_owner (aout);

    aout_OutputLock (aout);
    owner->sync.end = VLC_TICK_INVALID;
    owner->sync.gapless_offset = 0;
    owner->sync.b_gapless_pending = false;
    if (owner->mixer_format.i_format)
    {
        if (wait)
        {
            block_t *block = aout_FiltersDrain (owner->filters);
            if (block)
                aout_OutputPlay (aout, block);
        }
        else
            aout_FiltersFlush (owner->filters);
        aout_OutputFlush (aout, wait);
    }
    aout_OutputUnlock (aout);
}

void aout_ChangeViewpoint(audio_output_t *aout,
                          const vlc_viewpoint_t *p_viewpoint)
{
    aout_owner_t *owner = aout_owner (aout);

    vlc_mutex_lock (&owner->vp.lock);
    owner->vp.value = *p_viewpoint;
    atomic_store(&owner->vp.update, true);
    vlc_mutex_unlock (&owner->vp.lock);
}
