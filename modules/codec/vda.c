/*****************************************************************************
 * vda.c: Video Decode Acceleration H.264 decoder (Mac OS X 10.6.3+)
 *****************************************************************************
 * Copyright © 2026 VLC authors and VideoLAN
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

/* Hardware H.264 decoding through the public Video Decode Acceleration
 * framework, which Apple shipped with Mac OS X 10.6.3 for the GPUs of that
 * era (GeForce 9400M, 320M, GT 330M...). This is the ancestor of
 * VideoToolbox, which only became public with 10.8 — on 10.6/10.7 this
 * module is the only hardware path. The plugin links the framework
 * directly: on releases without it, dlopen() of the plugin simply fails
 * and VLC falls back to the software avcodec decoder. */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_codec.h>

#include "hxxx_helper.h"
#include "vt_utils.h"

#include <VideoDecodeAcceleration/VDADecoder.h>
#include <CoreVideo/CoreVideo.h>

static int  OpenDecoder(vlc_object_t *);
static void CloseDecoder(vlc_object_t *);

#define VDA_TEXT N_("Video Decode Acceleration (VDA)")
#define VDA_LONGTEXT N_("Use the hardware H.264 decoder of Mac OS X " \
    "10.6.3 and later. If the graphics chipset does not support it, " \
    "VLC automatically falls back to software decoding.")

#define CHROMA_TEXT N_("VDA output format")
#define CHROMA_LONGTEXT N_("Pixel format the graphics chipset decodes into. " \
    "\"Auto\" picks the first one the driver accepts, which is normally the " \
    "one it produces natively; the others are for troubleshooting.")

static const char *const chroma_values[] = {
    "auto", "uyvy", "nv12", "i420"
};
static const char *const chroma_names[] = {
    N_("Auto"), "UYVY (4:2:2)", "NV12 (4:2:0)", "I420 (4:2:0)"
};

vlc_module_begin()
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_VCODEC)
    set_description(N_("VDA hardware decoder"))
    set_capability("video decoder", 100)
    set_callbacks(OpenDecoder, CloseDecoder)
    /* On by default: with zero-copy output the hardware decoder costs about a
     * ninth of the CPU that software decoding does on the GPUs VDA supports
     * (measured on a GeForce 320M, see CreateSession).
     *
     * Enabling it cannot displace the modern path: videotoolbox declares
     * capability 800 against our 100, so from 10.8 on it is always tried
     * first and wins. VDA only gets a turn where it is the sole hardware
     * decoder — 10.6 and 10.7 — and when the chipset or the stream turns out
     * to be unsupported we hand back VLCDEC_RELOAD and VLC restarts the chain
     * on avcodec (capability 70). */
    add_bool("vda", true, VDA_TEXT, VDA_LONGTEXT, false)
    add_string("vda-chroma", "auto", CHROMA_TEXT, CHROMA_LONGTEXT, true)
        change_string_list(chroma_values, chroma_names)
vlc_module_end()

/*****************************************************************************
 * decoder_sys_t
 *****************************************************************************/

/* held output frame, ordered by pts (the VDA callback delivers frames in
 * decode order, not display order) */
struct vda_pic
{
    picture_t *p_pic;
    struct vda_pic *p_next;
};

struct decoder_sys_t
{
    VDADecoder session;
    struct hxxx_helper hh;
    OSType cv_format;           /* negotiated CVPixelBuffer format */
    vlc_fourcc_t i_chroma;      /* matching VLC chroma */

    vlc_mutex_t lock;
    struct vda_pic *p_queue;    /* sorted by pts, smallest first */
    unsigned i_queued;
    unsigned i_depth;           /* frames held back for reordering */
    bool b_format_valid;
    bool b_abort;               /* hardware unusable: reload on next block */
};

static const CFStringRef kVLCVDAPts = CFSTR("org.videolan.vda.pts");

/*****************************************************************************
 * output queue helpers (lock held)
 *****************************************************************************/

static void QueueInsert(decoder_sys_t *p_sys, picture_t *p_pic)
{
    struct vda_pic *p_entry = malloc(sizeof (*p_entry));
    if (unlikely(p_entry == NULL)) {
        picture_Release(p_pic);
        return;
    }
    p_entry->p_pic = p_pic;

    struct vda_pic **pp = &p_sys->p_queue;
    while (*pp != NULL && (*pp)->p_pic->date <= p_pic->date)
        pp = &(*pp)->p_next;
    p_entry->p_next = *pp;
    *pp = p_entry;
    p_sys->i_queued++;
}

static picture_t *QueuePop(decoder_sys_t *p_sys)
{
    struct vda_pic *p_entry = p_sys->p_queue;
    if (p_entry == NULL)
        return NULL;
    p_sys->p_queue = p_entry->p_next;
    p_sys->i_queued--;
    picture_t *p_pic = p_entry->p_pic;
    free(p_entry);
    return p_pic;
}

static void QueueEmpty(decoder_t *p_dec, bool b_emit)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    picture_t *p_pic;
    vlc_mutex_lock(&p_sys->lock);
    while ((p_pic = QueuePop(p_sys)) != NULL) {
        if (b_emit)
            decoder_QueueVideo(p_dec, p_pic);
        else
            picture_Release(p_pic);
    }
    vlc_mutex_unlock(&p_sys->lock);
}

/*****************************************************************************
 * VDA output callback (arbitrary thread)
 *****************************************************************************/

static void DecoderCallback(void *refcon, CFDictionaryRef frameInfo,
                            OSStatus status, uint32_t infoFlags,
                            CVImageBufferRef imageBuffer)
{
    decoder_t *p_dec = refcon;
    decoder_sys_t *p_sys = p_dec->p_sys;
    VLC_UNUSED(infoFlags);

    if (status != kVDADecoderNoErr || imageBuffer == NULL)
        return;
    if (CVPixelBufferGetPixelFormatType(imageBuffer) != p_sys->cv_format)
        return;

    vlc_mutex_lock(&p_sys->lock);
    bool b_ok = p_sys->b_format_valid;
    vlc_mutex_unlock(&p_sys->lock);
    if (!b_ok)
        return;

    picture_t *p_pic = decoder_NewPicture(p_dec);
    if (p_pic == NULL)
        return;

    /* timestamp travels through the frameInfo dictionary */
    p_pic->date = VLC_TS_INVALID;
    if (frameInfo != NULL) {
        CFNumberRef ptsRef = CFDictionaryGetValue(frameInfo, kVLCVDAPts);
        int64_t i_pts;
        if (ptsRef != NULL
         && CFNumberGetValue(ptsRef, kCFNumberSInt64Type, &i_pts))
            p_pic->date = i_pts;
    }

    /* VDA is fed progressive H.264 only; it never emits fields. */
    p_pic->b_progressive = true;

    /* Zero copy. The decoded frame already lives in GPU memory, backed by an
     * IOSurface, so hand that buffer straight down the chain instead of
     * reading it back: the glconv_cvpx converter binds it as a texture with
     * CGLTexImageIOSurface2D and it never leaves the GPU.
     *
     * Do NOT reintroduce a CVPixelBufferLockBaseAddress()+memcpy() here. That
     * lock forces a readback across the bus, the vout then uploads the very
     * same frame back as a texture, and the round trip costs more than
     * decoding the stream on the CPU in the first place — measured on a
     * GeForce 320M, 1080p: 25.0 s of CPU per 30 s of video with the copy
     * versus 18.5 s for pure software decoding.
     *
     * On failure cvpxpic_attach() has already released the picture. */
    if (cvpxpic_attach(p_pic, imageBuffer) != VLC_SUCCESS)
        return;

    /* reorder: hold i_depth frames, emit by increasing pts */
    vlc_mutex_lock(&p_sys->lock);
    QueueInsert(p_sys, p_pic);
    picture_t *p_out = p_sys->i_queued > p_sys->i_depth
        ? QueuePop(p_sys) : NULL;
    vlc_mutex_unlock(&p_sys->lock);

    if (p_out != NULL)
        decoder_QueueVideo(p_dec, p_out);
}

/*****************************************************************************
 * session management
 *****************************************************************************/

static void DestroySession(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    if (p_sys->session == NULL)
        return;
    VDADecoderFlush(p_sys->session, 0);
    VDADecoderDestroy(p_sys->session);
    p_sys->session = NULL;
    QueueEmpty(p_dec, false);
}

static int CreateSession(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    unsigned i_width, i_height, i_vis_width, i_vis_height;
    if (hxxx_helper_get_current_picture_size(&p_sys->hh,
            &i_width, &i_height, &i_vis_width, &i_vis_height)
            != VLC_SUCCESS)
        return VLC_EGENERIC;

    block_t *p_avcc = h264_helper_get_avcc_config(&p_sys->hh);
    if (p_avcc == NULL)
        return VLC_EGENERIC;

    /* decoder configuration */
    CFMutableDictionaryRef config = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    int i_number;
    CFNumberRef numberRef;
    i_number = i_width;
    numberRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &i_number);
    CFDictionarySetValue(config, kVDADecoderConfiguration_Width, numberRef);
    CFRelease(numberRef);
    i_number = i_height;
    numberRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &i_number);
    CFDictionarySetValue(config, kVDADecoderConfiguration_Height, numberRef);
    CFRelease(numberRef);
    i_number = 'avc1';
    numberRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &i_number);
    CFDictionarySetValue(config, kVDADecoderConfiguration_SourceFormat,
                         numberRef);
    CFRelease(numberRef);
    CFDataRef avccRef = CFDataCreate(kCFAllocatorDefault,
                                     p_avcc->p_buffer, p_avcc->i_buffer);
    CFDictionarySetValue(config, kVDADecoderConfiguration_avcCData, avccRef);
    CFRelease(avccRef);
    block_Release(p_avcc);

    /* Output formats, in the order we ask the driver for them. The chromas
     * are the opaque CVPX_* ones: the frames stay in GPU memory and are only
     * ever touched again by the texture converter.
     *
     * Packed 4:2:2 comes FIRST because it is what these video engines write
     * natively. Ask for a 4:2:0 layout instead and VDA still says yes, but it
     * quietly converts every frame on the CPU on the way out — which costs
     * far more than the decode it saves. Measured on a GeForce 320M, 1080p
     * H.264, fullscreen, share of one core:
     *
     *     software (avcodec)  79.7 %
     *     VDA asking NV12     51.9 %
     *     VDA asking I420     51.5 %
     *     VDA asking UYVY      9.0 %   <- no conversion
     *
     * 4:2:2 carries a third more samples than the 4:2:0 source, but that
     * costs GPU bandwidth we have to spare, not CPU time we do not. The
     * chroma upsampling is the driver's own and is not lossy. */
    static const struct {
        const char *psz_name;
        OSType cv;
        vlc_fourcc_t chroma;
    } formats[] = {
        { "uyvy", kCVPixelFormatType_422YpCbCr8,       VLC_CODEC_CVPX_UYVY },
        { "nv12", kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
          VLC_CODEC_CVPX_NV12 },
        { "i420", kCVPixelFormatType_420YpCbCr8Planar, VLC_CODEC_CVPX_I420 },
    };
    char *psz_want = var_InheritString(p_dec, "vda-chroma");

    /* Every buffer must be IOSurface-backed, otherwise CGLTexImageIOSurface2D
     * in the converter has nothing to bind and the frame cannot be shown
     * without a readback. */
    CFDictionaryRef ioSurfaceProps = CFDictionaryCreateMutable(
        kCFAllocatorDefault, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

    OSStatus status = kVDADecoderConfigurationError;
    unsigned fmt;
    for (fmt = 0; fmt < sizeof (formats) / sizeof (formats[0]); fmt++) {
        if (psz_want != NULL && strcmp(psz_want, "auto") != 0
         && strcmp(psz_want, formats[fmt].psz_name) != 0)
            continue;

        CFMutableDictionaryRef imageAttributes = CFDictionaryCreateMutable(
            kCFAllocatorDefault, 2,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
        i_number = formats[fmt].cv;
        numberRef = CFNumberCreate(NULL, kCFNumberSInt32Type, &i_number);
        CFDictionarySetValue(imageAttributes,
                             kCVPixelBufferPixelFormatTypeKey, numberRef);
        CFRelease(numberRef);
        if (ioSurfaceProps != NULL)
            CFDictionarySetValue(imageAttributes,
                                 kCVPixelBufferIOSurfacePropertiesKey,
                                 ioSurfaceProps);

        status = VDADecoderCreate(config, imageAttributes,
                                  (VDADecoderOutputCallback *)
                                      DecoderCallback,
                                  p_dec, &p_sys->session);
        CFRelease(imageAttributes);
        if (status == kVDADecoderNoErr) {
            p_sys->cv_format = formats[fmt].cv;
            p_sys->i_chroma = formats[fmt].chroma;
            break;
        }
        p_sys->session = NULL;
    }
    free(psz_want);
    if (ioSurfaceProps != NULL)
        CFRelease(ioSurfaceProps);
    CFRelease(config);

    if (status != kVDADecoderNoErr) {
        msg_Warn(p_dec, "VDADecoderCreate failed: %d (hardware decoding "
                 "unavailable, falling back to software)", (int)status);
        p_sys->session = NULL;
        return VLC_EGENERIC;
    }

    /* how many frames must be held back for display-order output */
    uint8_t i_reorder = 0;
    unsigned i_delay = 0;
    if (h264_helper_get_current_dpb_values(&p_sys->hh, &i_reorder, &i_delay)
            != VLC_SUCCESS || i_reorder == 0)
        i_reorder = 4;
    if (i_reorder > 8)
        i_reorder = 8;

    /* propagate the output format */
    p_dec->fmt_out.i_codec = p_sys->i_chroma;
    p_dec->fmt_out.video.i_chroma = p_sys->i_chroma;
    p_dec->fmt_out.video.i_width = i_width;
    p_dec->fmt_out.video.i_height = i_height;
    p_dec->fmt_out.video.i_visible_width = i_vis_width;
    p_dec->fmt_out.video.i_visible_height = i_vis_height;
    int i_sar_num, i_sar_den;
    if (hxxx_helper_get_current_sar(&p_sys->hh, &i_sar_num, &i_sar_den)
            == VLC_SUCCESS && i_sar_num > 0 && i_sar_den > 0) {
        p_dec->fmt_out.video.i_sar_num = i_sar_num;
        p_dec->fmt_out.video.i_sar_den = i_sar_den;
    }
    if (decoder_UpdateVideoFormat(p_dec) != 0) {
        DestroySession(p_dec);
        return VLC_EGENERIC;
    }

    vlc_mutex_lock(&p_sys->lock);
    p_sys->i_depth = i_reorder;
    p_sys->b_format_valid = true;
    vlc_mutex_unlock(&p_sys->lock);

    msg_Dbg(p_dec, "VDA hardware decoding session started (%ux%u, %4.4s, "
            "reorder depth %u)", i_width, i_height,
            (const char *)&p_sys->i_chroma, i_reorder);
    return VLC_SUCCESS;
}

/*****************************************************************************
 * decoding
 *****************************************************************************/

static void Flush(decoder_t *p_dec)
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    if (p_sys->session != NULL)
        VDADecoderFlush(p_sys->session, 0);
    QueueEmpty(p_dec, false);
}

static int DecodeBlock(decoder_t *p_dec, block_t *p_block)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* A previous call found the hardware unusable for this stream. Ask for
     * the reload here, at the very top, while p_block is still exactly the
     * block the core owns: VLCDEC_RELOAD means "do not release or modify it,
     * it will be fed to my replacement". Mark the ES too so OpenDecoder
     * skips this module when the chain restarts. */
    if (p_sys->b_abort) {
        var_Create(p_dec, "vda-failed", VLC_VAR_VOID);
        return VLCDEC_RELOAD;
    }

    if (p_block == NULL) {
        /* drain */
        if (p_sys->session != NULL)
            VDADecoderFlush(p_sys->session, kVDADecoderFlush_EmitFrames);
        QueueEmpty(p_dec, true);
        return VLCDEC_SUCCESS;
    }

    if (p_block->i_flags & (BLOCK_FLAG_DISCONTINUITY | BLOCK_FLAG_CORRUPTED)) {
        Flush(p_dec);
        if (p_block->i_flags & BLOCK_FLAG_CORRUPTED) {
            block_Release(p_block);
            return VLCDEC_SUCCESS;
        }
    }

    /* AnnexB -> length-prefixed conversion, SPS/PPS tracking */
    bool b_config_changed = false;
    p_block = p_sys->hh.pf_process_block(&p_sys->hh, p_block,
                                         &b_config_changed);
    if (p_block == NULL)
        return VLCDEC_SUCCESS;

    if (b_config_changed && p_sys->session != NULL) {
        VDADecoderFlush(p_sys->session, kVDADecoderFlush_EmitFrames);
        QueueEmpty(p_dec, true);
        DestroySession(p_dec);
    }

    if (p_sys->session == NULL) {
        if (CreateSession(p_dec) != VLC_SUCCESS) {
            /* No hardware for this stream. We cannot ask for the reload from
             * here: pf_process_block() above already consumed the block the
             * core handed us and replaced it with a converted one, and on
             * VLCDEC_RELOAD the core re-feeds *its* pointer to the module
             * that replaces us (see decoder.c, DecoderDecodeVideo). Asking
             * now hands avcodec freed memory and it segfaults inside
             * av_packet_ref().
             *
             * So drop this block, and reload at the top of the next call,
             * before that block has been touched. Losing one block is
             * expected on a reload and the next keyframe recovers. */
            p_sys->b_abort = true;
            block_Release(p_block);
            return VLCDEC_SUCCESS;
        }
    }

    CFDataRef frameData = CFDataCreate(kCFAllocatorDefault,
                                       p_block->p_buffer, p_block->i_buffer);
    int64_t i_pts = p_block->i_pts != VLC_TS_INVALID
        ? p_block->i_pts : p_block->i_dts;
    CFNumberRef ptsRef = CFNumberCreate(NULL, kCFNumberSInt64Type, &i_pts);
    CFDictionaryRef frameInfo = NULL;
    if (ptsRef != NULL) {
        frameInfo = CFDictionaryCreate(kCFAllocatorDefault,
            (const void **)&kVLCVDAPts, (const void **)&ptsRef, 1,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
        CFRelease(ptsRef);
    }
    block_Release(p_block);
    if (frameData == NULL || frameInfo == NULL) {
        if (frameData)
            CFRelease(frameData);
        if (frameInfo)
            CFRelease(frameInfo);
        return VLCDEC_SUCCESS;
    }

    OSStatus status = VDADecoderDecode(p_sys->session, 0, frameData,
                                       frameInfo);
    CFRelease(frameData);
    CFRelease(frameInfo);
    if (status != kVDADecoderNoErr)
        msg_Warn(p_dec, "VDADecoderDecode failed: %d", (int)status);

    return VLCDEC_SUCCESS;
}

/*****************************************************************************
 * Open / Close
 *****************************************************************************/

static int OpenDecoder(vlc_object_t *p_this)
{
    decoder_t *p_dec = (decoder_t *)p_this;

    if (p_dec->fmt_in.i_cat != VIDEO_ES
     || p_dec->fmt_in.i_codec != VLC_CODEC_H264)
        return VLC_EGENERIC;

    if (!var_InheritBool(p_this, "vda"))
        return VLC_EGENERIC;

    /* hardware already proved unusable for this ES (see DecodeBlock) */
    if (var_Type(p_dec, "vda-failed") != 0)
        return VLC_EGENERIC;

    /* No runtime symbol check needed: the framework is linked directly,
     * so on releases without it (10.5, 10.6.0-10.6.2) the plugin fails to
     * dlopen and this code never runs. */

    decoder_sys_t *p_sys = calloc(1, sizeof (*p_sys));
    if (unlikely(p_sys == NULL))
        return VLC_ENOMEM;
    p_dec->p_sys = p_sys;

    vlc_mutex_init(&p_sys->lock);
    hxxx_helper_init(&p_sys->hh, VLC_OBJECT(p_dec),
                     p_dec->fmt_in.i_codec, true);
    if (hxxx_helper_set_extra(&p_sys->hh, p_dec->fmt_in.p_extra,
                              p_dec->fmt_in.i_extra) != VLC_SUCCESS) {
        hxxx_helper_clean(&p_sys->hh);
        vlc_mutex_destroy(&p_sys->lock);
        free(p_sys);
        return VLC_EGENERIC;
    }

    p_dec->pf_decode = DecodeBlock;
    p_dec->pf_flush = Flush;
    p_dec->fmt_out.i_codec = VLC_CODEC_I420;

    msg_Dbg(p_dec, "trying VDA hardware decoding");
    return VLC_SUCCESS;
}

static void CloseDecoder(vlc_object_t *p_this)
{
    decoder_t *p_dec = (decoder_t *)p_this;
    decoder_sys_t *p_sys = p_dec->p_sys;

    DestroySession(p_dec);
    hxxx_helper_clean(&p_sys->hh);
    vlc_mutex_destroy(&p_sys->lock);
    free(p_sys);
}
