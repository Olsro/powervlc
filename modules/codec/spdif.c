/*****************************************************************************
 * spdif.c: S/PDIF pass-though decoder
 *****************************************************************************
 * Copyright (C) 2016 VLC authors and VideoLAN
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

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_aout.h>
#include <vlc_codec.h>
#include <vlc_modules.h>

static int OpenDecoder(vlc_object_t *);

vlc_module_begin()
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_ACODEC)
    set_description(N_("S/PDIF pass-through decoder"))
    set_capability("audio decoder", 120)
    set_callbacks(OpenDecoder, NULL)
vlc_module_end()

static int
DecodeBlock(decoder_t *p_dec, block_t *p_block)
{
    if (p_block != NULL)
        decoder_QueueAudio( p_dec, p_block );
    return VLCDEC_SUCCESS;
}

static int
OpenDecoder(vlc_object_t *p_this)
{
    decoder_t *p_dec = (decoder_t*)p_this;

    /* Passthrough must always be an explicit user choice.  Output modules
     * can discover that a link supports encoded audio, but discovery alone
     * must never make this decoder outrank the normal PCM decoder.  Keep the
     * policy here, in the common decoder, so every platform and every UI gets
     * the same master switch and receiver-capability checks. */
    if (!var_InheritBool(p_dec, "spdif"))
        return VLC_EGENERIC;

    switch (p_dec->fmt_in.i_codec)
    {
    case VLC_CODEC_MPGA:
    case VLC_CODEC_MP3:
        /* Disabled by default */
        if (!p_dec->obj.force)
            return VLC_EGENERIC;
        break;
    case VLC_CODEC_A52:
        if (!var_InheritBool(p_dec, "spdif-ac3"))
            return VLC_EGENERIC;
        break;
    case VLC_CODEC_EAC3:
        if (!var_InheritBool(p_dec, "spdif-eac3"))
            return VLC_EGENERIC;
        break;
    case VLC_CODEC_MLP:
    case VLC_CODEC_TRUEHD:
        if (!var_InheritBool(p_dec, "spdif-truehd"))
            return VLC_EGENERIC;
        break;
    case VLC_CODEC_DTS:
    {
        /* VLC 3 carries the DTS-HD indication in i_profile.  A DTS-HD
         * access unit also contains a backward-compatible DTS core.  Keep
         * the passthrough packetizer available when only core DTS is
         * enabled so outputs without a native DTS-HD carrier (notably
         * CoreAudio on macOS) can strip the extension and send that core. */
        const bool b_dts_core = var_InheritBool(p_dec, "spdif-dts");
        const bool b_dts_hd = p_dec->fmt_in.i_profile > 0
                           && var_InheritBool(p_dec, "spdif-dtshd");
        if (!b_dts_core && !b_dts_hd)
            return VLC_EGENERIC;
        break;
    }
    case VLC_CODEC_SPDIFL:
    case VLC_CODEC_SPDIFB:
        /* Already encapsulated: the master switch is still mandatory, but
         * the original family is no longer available here. */
        break;
    default:
        return VLC_EGENERIC;
    }

    /* Set output properties */
    p_dec->fmt_out.i_codec = p_dec->fmt_in.i_codec;
    p_dec->fmt_out.audio = p_dec->fmt_in.audio;
    p_dec->fmt_out.i_profile = p_dec->fmt_in.i_profile;
    p_dec->fmt_out.audio.i_format = p_dec->fmt_out.i_codec;

    if (decoder_UpdateAudioFormat(p_dec))
        return VLC_EGENERIC;

    p_dec->pf_decode = DecodeBlock;
    p_dec->pf_flush  = NULL;

    return VLC_SUCCESS;
}
