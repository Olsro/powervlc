/*****************************************************************************
 * speex.c : libspeex DSP resampler
 *****************************************************************************
 * Copyright © 2011-2012 Rémi Denis-Courmont
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
# include <config.h>
#endif

#include <inttypes.h>

#include <vlc_common.h>
#include <vlc_aout.h>
#include <vlc_filter.h>
#include <vlc_plugin.h>

#include <speex/speex_resampler.h>

#define QUALITY_TEXT N_("Resampling quality")
#define QUALITY_LONGTEXT N_( "Resampling quality, from worst to best" )

static int Open (vlc_object_t *);
static int OpenResampler (vlc_object_t *);
static void Close (vlc_object_t *);

vlc_module_begin ()
    set_shortname (N_("Speex resampler"))
    set_description (N_("Speex resampler") )
    set_category (CAT_AUDIO)
    set_subcategory (SUBCAT_AUDIO_RESAMPLER)
#if defined (__powerpc__) || defined (__POWERPC__)
    /* On PowerPC, libsamplerate's fastest SINC eats a large share of the
     * CPU for the permanent 48->44.1 kHz DVD conversion (these Macs'
     * codecs only run at 44.1 kHz) and it has no AltiVec path anyway.
     * Speex with a short filter costs a fraction of that. On SIMD-less
     * G3, quality 1 (16 taps) also keeps the filter-rebuild triggered by
     * aout drift adjustments cheap (update_filter was profiled at half a
     * core at quality 3); G4/G5 can afford quality 3. */
# ifdef __ALTIVEC__
    add_integer ("speex-resampler-quality", 3,
                 QUALITY_TEXT, QUALITY_LONGTEXT, true)
# else
    add_integer ("speex-resampler-quality", 1,
                 QUALITY_TEXT, QUALITY_LONGTEXT, true)
# endif
        change_integer_range (0, 10)
    set_capability ("audio converter", 60)
    set_callbacks (Open, Close)

    add_submodule ()
    set_capability ("audio resampler", 60)
#else
    add_integer ("speex-resampler-quality", 4,
                 QUALITY_TEXT, QUALITY_LONGTEXT, true)
        change_integer_range (0, 10)
    set_capability ("audio converter", 0)
    set_callbacks (Open, Close)

    add_submodule ()
    set_capability ("audio resampler", 0)
#endif
    set_callbacks (OpenResampler, Close)
    add_shortcut ("speex")
vlc_module_end ()

static block_t *Resample (filter_t *, block_t *);

#if defined (__powerpc__) || defined (__POWERPC__)
/* On PowerPC, rebuilding the speex filter tables (sin() per tap) is
 * expensive, and the aout drift loop nudges the input rate a few Hz on
 * nearly every block. Keep the last programmed rates and only reprogram
 * when one drifts past a threshold: the drift loop still converges (it
 * measures the real output) but the rebuilds become rare. */
# define PPC_RATE_HYSTERESIS 1
struct resampler_sys
{
    SpeexResamplerState *st;
    unsigned cur_irate; /* rates currently programmed into st; the aout */
    unsigned cur_orate; /* drift loop nudges the INPUT rate of the last
                         * resampler, so both sides must be watched */
    vlc_tick_t last_set; /* when the rates were last programmed */
};
#endif

static int OpenResampler (vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;

    /* Cannot convert format */
    if (filter->fmt_in.audio.i_format != filter->fmt_out.audio.i_format
    /* Cannot remix */
     || filter->fmt_in.audio.i_channels != filter->fmt_out.audio.i_channels
     || filter->fmt_in.audio.i_physical_channels == 0 )
        return VLC_EGENERIC;

    switch (filter->fmt_in.audio.i_format)
    {
        case VLC_CODEC_FL32: break;
        case VLC_CODEC_S16N: break;
        default:             return VLC_EGENERIC;
    }

    SpeexResamplerState *st;

    unsigned q = var_InheritInteger (obj, "speex-resampler-quality");
    if (unlikely(q > 10))
        q = 3;

    int err;
    st = speex_resampler_init(filter->fmt_in.audio.i_channels,
                              filter->fmt_in.audio.i_rate,
                              filter->fmt_out.audio.i_rate, q, &err);
    if (unlikely(st == NULL))
    {
        msg_Err (obj, "cannot initialize resampler: %s",
                 speex_resampler_strerror (err));
        return VLC_ENOMEM;
    }

#ifdef PPC_RATE_HYSTERESIS
    struct resampler_sys *sys = malloc (sizeof (*sys));
    if (unlikely(sys == NULL))
    {
        speex_resampler_destroy (st);
        return VLC_ENOMEM;
    }
    sys->st = st;
    sys->cur_irate = filter->fmt_in.audio.i_rate;
    sys->cur_orate = filter->fmt_out.audio.i_rate;
    sys->last_set = mdate ();
    filter->p_sys = (filter_sys_t *)sys;
#else
    filter->p_sys = (filter_sys_t *)st;
#endif
    filter->pf_audio_filter = Resample;
    return VLC_SUCCESS;
}

static int Open (vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;

    /* Will change rate */
    if (filter->fmt_in.audio.i_rate == filter->fmt_out.audio.i_rate)
        return VLC_EGENERIC;
    return OpenResampler (obj);
}

static void Close (vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;
#ifdef PPC_RATE_HYSTERESIS
    struct resampler_sys *sys = (struct resampler_sys *)filter->p_sys;
    speex_resampler_destroy (sys->st);
    free (sys);
#else
    SpeexResamplerState *st = (SpeexResamplerState *)filter->p_sys;
    speex_resampler_destroy (st);
#endif
}

static block_t *Resample (filter_t *filter, block_t *in)
{
#ifdef PPC_RATE_HYSTERESIS
    struct resampler_sys *sys = (struct resampler_sys *)filter->p_sys;
    SpeexResamplerState *st = sys->st;
#else
    SpeexResamplerState *st = (SpeexResamplerState *)filter->p_sys;
#endif

    const size_t framesize = filter->fmt_out.audio.i_bytes_per_frame;
    const unsigned irate = filter->fmt_in.audio.i_rate;
    const unsigned orate = filter->fmt_out.audio.i_rate;

    spx_uint32_t ilen = in->i_nb_samples;
    spx_uint32_t olen = ((ilen + 2) * orate * UINT64_C(11))
                      / (irate * UINT64_C(10));

    block_t *out = block_Alloc (olen * framesize);
    if (unlikely(out == NULL))
        goto error;

#ifdef PPC_RATE_HYSTERESIS
    /* Reprogram only when a requested rate drifts more than ~0.1% from
     * what is loaded (a filter rebuild otherwise happens nearly every
     * block: the aout drift loop nudges the INPUT rate of the resampler
     * a few Hz at a time). 44 Hz on 44.1 kHz is inaudible and the drift
     * loop, which measures the real output, keeps converging in coarser
     * steps. */
    unsigned idelta = irate > sys->cur_irate ? irate - sys->cur_irate
                                             : sys->cur_irate - irate;
    unsigned odelta = orate > sys->cur_orate ? orate - sys->cur_orate
                                             : sys->cur_orate - orate;
    if (idelta >= 44 || odelta >= 44)
    {
        /* The hysteresis is not enough on its own: when the machine runs
         * near saturation the aout clock jitters and the drift loop can
         * request a swing larger than the threshold on nearly every block,
         * and each reprogramming rebuilds the sinc tables (profiled at
         * ~6 ms each, a quarter of a G4 core melted into sin()). Rebuild
         * at most twice a second: in between, the loop keeps converging
         * against the real (stale-rate) output it measures. */
        vlc_tick_t now = mdate ();
        if (now - sys->last_set >= CLOCK_FREQ / 2)
        {
            speex_resampler_set_rate (st, irate, orate);
            sys->cur_irate = irate;
            sys->cur_orate = orate;
            sys->last_set = now;
        }
    }
#else
    speex_resampler_set_rate (st, irate, orate);
#endif

    /* speex may leave a tail of input unconsumed (filter phase, magic
     * samples after a rate change): loop until everything is eaten, a
     * dropped input frame is an audible glitch plus permanent A/V drift
     * that the aout then chases forever. */
    spx_uint32_t idone = 0, odone = 0;
    while (idone < in->i_nb_samples && odone < olen)
    {
        spx_uint32_t icur = in->i_nb_samples - idone;
        spx_uint32_t ocur = olen - odone;
        int err;
        if (filter->fmt_in.audio.i_format == VLC_CODEC_FL32)
            err = speex_resampler_process_interleaved_float (st,
                (float *)(in->p_buffer + (size_t)idone * framesize), &icur,
                (float *)(out->p_buffer + (size_t)odone * framesize), &ocur);
        else
            err = speex_resampler_process_interleaved_int (st,
                (int16_t *)(in->p_buffer + (size_t)idone * framesize), &icur,
                (int16_t *)(out->p_buffer + (size_t)odone * framesize), &ocur);
        if (err != 0)
        {
            msg_Err (filter, "cannot resample: %s",
                     speex_resampler_strerror (err));
            block_Release (out);
            out = NULL;
            goto error;
        }
        if (icur == 0 && ocur == 0)
            break; /* no progress, avoid spinning */
        idone += icur;
        odone += ocur;
    }
    ilen = idone;
    olen = odone;

    if (ilen < in->i_nb_samples)
        msg_Err (filter, "lost %"PRIu32" of %u input frames",
                 in->i_nb_samples - ilen, in->i_nb_samples);

    out->i_buffer = olen * framesize;
    out->i_nb_samples = olen;
    out->i_pts = in->i_pts;
    out->i_length = olen * CLOCK_FREQ / filter->fmt_out.audio.i_rate;
error:
    block_Release (in);
    return out;
}
