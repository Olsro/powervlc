/*****************************************************************************
 * mvc.c: H.264/MVC stereoscopic decoder
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or (at
 * your option) any later version.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_codec.h>
#include <vlc_picture.h>

#include <edge264.h>
#include "mvc_piccontext.h"
#include <errno.h>

#include "hxxx_helper.h"

#if defined(__APPLE__)
# include <CoreFoundation/CoreFoundation.h>
# include <CoreVideo/CoreVideo.h>
# include <dlfcn.h>
# if defined(__arm64__) && defined(HAVE_VIDEOTOOLBOX_VIDEOTOOLBOX_H)
#  include <CoreMedia/CoreMedia.h>
#  include <VideoToolbox/VideoToolbox.h>
#  define MVC_HAVE_VT 1
# endif
# if defined(HAVE_VDA_FRAMEWORK)
#  include <VideoDecodeAcceleration/VDADecoder.h>
# else
/* The 32-bit legacy build intentionally uses the 10.4u SDK, which predates
 * the public VDA headers. VDA itself appeared in Snow Leopard and every
 * entry point/key used below is resolved with dlopen/dlsym, so preserve its
 * ABI here. On 10.4/10.5 dlopen fails and Edge264 remains the fallback. */
typedef struct OpaqueVDADecoder *VDADecoder;
typedef void VDADecoderOutputCallback(void *, CFDictionaryRef, OSStatus,
                                      uint32_t, CVImageBufferRef);
enum {
    kVDADecoderNoErr = 0,
    kVDADecoderFlush_EmitFrames = 1U << 0,
    kCVPixelFormatType_420YpCbCr8Planar = 'y420',
    kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange = '420v',
    kCVPixelFormatType_422YpCbCr8 = '2vuy',
    kCVPixelBufferLock_ReadOnly = 1U,
};
# endif
# define MVC_HAVE_VDA 1
#endif

#include "../packetizer/hxxx_nal.h"
#include "../packetizer/h264_nal.h"

#define MVC_MAX_DATES 128
#define MVC_NAL_PADDING 64
#define MVC_NAL_PREFIX_PADDING 2
#define MVC_REORDER_DEPTH 4

typedef struct
{
    picture_t *picture;
    vlc_tick_t date;
    int32_t frame_id;
    int32_t frame_id_mvc;
    int32_t poc;
    int32_t poc_mvc;
} mvc_pending_picture_t;

#if defined(MVC_HAVE_VDA)
typedef OSStatus (*mvc_vda_create_cb)(CFDictionaryRef, CFDictionaryRef,
                                      VDADecoderOutputCallback *, void *,
                                      VDADecoder *);
typedef OSStatus (*mvc_vda_decode_cb)(VDADecoder, uint32_t, CFTypeRef,
                                      CFDictionaryRef);
typedef OSStatus (*mvc_vda_flush_cb)(VDADecoder, uint32_t);
typedef OSStatus (*mvc_vda_destroy_cb)(VDADecoder);

typedef struct mvc_vda_picture
{
    CVImageBufferRef image;
    uint8_t *nv12;
    const uint8_t *nv12_y;
    const uint8_t *nv12_uv;
    int nv12_stride_y;
    int nv12_stride_uv;
    unsigned width;
    unsigned height;
    uint64_t serial;
    struct mvc_vda_picture *next;
} mvc_vda_picture_t;

typedef struct mvc_vda_owner
{
    CVImageBufferRef image;
    int32_t frame_id;
    struct mvc_vda_owner *next;
} mvc_vda_owner_t;

typedef struct mvc_vda_block
{
    block_t *block;
    uint64_t serial;
    vlc_tick_t queued_at;
    struct mvc_vda_block *next;
} mvc_vda_block_t;

typedef struct
{
    void *framework;
    VDADecoder session;
#if defined(MVC_HAVE_VT)
    VTDecompressionSessionRef vt_session;
    CMVideoFormatDescriptionRef vt_format;
    bool use_vt;
#endif
    mvc_vda_create_cb create;
    mvc_vda_decode_cb decode;
    mvc_vda_flush_cb flush;
    mvc_vda_destroy_cb destroy;
    const CFStringRef *key_height;
    const CFStringRef *key_width;
    const CFStringRef *key_source;
    const CFStringRef *key_avcc;
    const CFStringRef *key_iosurface;
    vlc_mutex_t lock;
    vlc_cond_t wait;
    mvc_vda_picture_t *pictures;
    mvc_vda_owner_t *owners;
    mvc_vda_block_t *blocks;
    mvc_vda_block_t **blocks_tail;
    uint64_t next_serial;
    bool initialized;
    bool requested;
    bool active;
    bool failed;
    bool reported_format;
    bool processing_block;
    mvc_vda_picture_t *processing_picture;
    struct hxxx_helper hh;
    bool hh_initialized;
    block_t *avcc;
    unsigned config_generation;
    unsigned timing_samples;
    FILE *dump;
    bool dumped_image;
    unsigned dump_image_count;
} mvc_vda_t;
#endif

struct decoder_sys_t
{
    Edge264Decoder *decoder;
    vlc_tick_t dates[MVC_MAX_DATES];
    unsigned date_count;
    uint8_t nal_length_size; /* zero for Annex B, 1..4 for AVC samples */
    bool warned_missing_view;
    bool reported_stereo;
    uint64_t output_count;
    vlc_tick_t cadence_wall_start;
    unsigned cadence_samples;
    unsigned poc_mismatches;
    unsigned poc_reversals;
    unsigned nonmonotonic_dates;
    unsigned irregular_dates;
    vlc_tick_t last_date;
    vlc_tick_t min_date_step;
    vlc_tick_t max_date_step;
    int32_t last_poc;
    bool have_last_poc;
    bool have_last_date;
    mvc_pending_picture_t pending[MVC_REORDER_DEPTH + 1];
    unsigned pending_count;
    unsigned reorder_depth;
    uint64_t injected_hash[3];
    bool have_injected_hash;
    bool direct_output;
    vlc_tick_t output_delay;
    uint8_t *vda_i420;
    size_t vda_i420_size;
    unsigned vda_owner_count;
    unsigned vda_owner_hits;
    unsigned vda_owner_misses;
#if defined(MVC_HAVE_VDA)
    mvc_vda_t vda;
#endif
};

static uint64_t MVCHashPlane(const uint8_t *pixels, ptrdiff_t pitch,
                             unsigned width, unsigned height)
{
    uint64_t hash = UINT64_C(1469598103934665603);
    for (unsigned y = 0; y < height; ++y)
    {
        for (unsigned x = 0; x < width; ++x)
        {
            hash ^= pixels[x];
            hash *= UINT64_C(1099511628211);
        }
        pixels += pitch;
    }
    return hash;
}

static int OpenDecoder(vlc_object_t *);
static void CloseDecoder(vlc_object_t *);
static int Decode(decoder_t *, block_t *);
#if defined(MVC_HAVE_VDA)
static void MVCVDAFlush(decoder_sys_t *);
static void MVCHardwarePictureDelete(mvc_vda_picture_t *);
#endif

#define THREADS_TEXT N_("MVC decoder threads")
#define THREADS_LONGTEXT N_("Number of Edge264 worker threads; -1 selects an optimized value automatically")

vlc_module_begin()
    set_shortname("MVC")
    set_description(N_("H.264/MVC Blu-ray 3D decoder"))
    set_capability("video decoder", 10050)
    set_callbacks(OpenDecoder, CloseDecoder)
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_VCODEC)
    add_integer_with_range("mvc-threads", -1, -1, 16,
                           THREADS_TEXT, THREADS_LONGTEXT, true)
    add_bool("mvc-direct-output", false, N_("Direct MVC planes"),
             N_("Pass Edge264's reconstructed eye planes directly to the "
                "legacy OpenGL output, avoiding a full stacked-frame copy."),
             true)
    add_integer_with_range("mvc-output-delay", 0, 0, 3000,
                           N_("MVC output latency compensation"),
                           N_("Delay completed stereo pictures by this many "
                              "milliseconds to account for hybrid decoder "
                              "latency."), true)
#if defined(MVC_HAVE_VDA)
    add_bool("mvc-vda-dump-base", false, N_("Dump MVC AVC base view"),
             N_("Write the extracted AVC-compatible base view to a temporary "
                "Annex B stream for decoder diagnostics"), true)
    add_string("mvc-vda-chroma", "auto", N_("VDA base-view output format"),
               N_("Diagnostic override: auto, uyvy, nv12 or i420"), true)
#endif
vlc_module_end()

#if defined(MVC_HAVE_VDA)
/* Experimental decoder paths are deliberately controlled by explicit /tmp
 * gates rather than persistent preferences. An empty file means enabled;
 * otherwise its integer contents are returned. */
static int dd_gate_read(const char *path)
{
    FILE *file = fopen(path, "r");
    if (file == NULL)
        return -1;
    int value = 1;
    if (fscanf(file, "%d", &value) != 1)
        value = 1;
    fclose(file);
    return value;
}
#endif

static void ReleaseNAL(int status, void *opaque)
{
    VLC_UNUSED(status);
    free(opaque);
}

static void DatesReset(decoder_sys_t *sys)
{
    sys->date_count = 0;
    sys->cadence_samples = 0;
    sys->poc_mismatches = 0;
    sys->poc_reversals = 0;
    sys->nonmonotonic_dates = 0;
    sys->irregular_dates = 0;
    sys->have_last_date = false;
    sys->have_last_poc = false;
}

static void ReportCadence(decoder_t *dec, decoder_sys_t *sys,
                          const mvc_pending_picture_t *pending,
                          vlc_tick_t date)
{
    if (sys->cadence_wall_start == 0)
        sys->cadence_wall_start = mdate();
    if (sys->output_count < 16)
        msg_Info(dec, "MVC pair #%"PRIu64": FrameId %d/%d, POC %d/%d, "
                 "PTS %"PRId64, sys->output_count,
                 pending->frame_id, pending->frame_id_mvc,
                 pending->poc, pending->poc_mvc, date);

    if (pending->poc != pending->poc_mvc)
        sys->poc_mismatches++;
    if (sys->have_last_poc && pending->poc < sys->last_poc)
        sys->poc_reversals++;
    sys->last_poc = pending->poc;
    sys->have_last_poc = true;

    if (date != VLC_TICK_INVALID)
    {
        if (sys->have_last_date)
        {
            const vlc_tick_t step = date - sys->last_date;
            if (sys->cadence_samples == 0)
                sys->min_date_step = sys->max_date_step = step;
            else
            {
                if (step < sys->min_date_step)
                    sys->min_date_step = step;
                if (step > sys->max_date_step)
                    sys->max_date_step = step;
            }
            sys->cadence_samples++;

            if (step <= 0)
                sys->nonmonotonic_dates++;
            else if (dec->fmt_out.video.i_frame_rate > 0 &&
                     dec->fmt_out.video.i_frame_rate_base > 0)
            {
                const vlc_tick_t expected =
                    ((vlc_tick_t)CLOCK_FREQ *
                     dec->fmt_out.video.i_frame_rate_base +
                     dec->fmt_out.video.i_frame_rate / 2) /
                    dec->fmt_out.video.i_frame_rate;
                /* Matroska commonly quantizes PTS to milliseconds. */
                if (llabs(step - expected) > VLC_TICK_FROM_MS(2))
                    sys->irregular_dates++;
            }
        }
        sys->last_date = date;
        sys->have_last_date = true;
    }

    sys->output_count++;
    if (sys->output_count % 120 == 0)
    {
        const vlc_tick_t wall_now = mdate();
        const vlc_tick_t wall_elapsed = wall_now - sys->cadence_wall_start;
        msg_Dbg(dec, "MVC cadence: 120 stereo pairs in %"PRId64" ms "
                 "(%.2f fps), POC mismatches %u, "
                 "POC reversals %u, "
                 "PTS step %"PRId64"..%"PRId64" us (%u non-monotonic, "
                 "%u irregular)", wall_elapsed / 1000,
                 wall_elapsed > 0 ? 120.0 * CLOCK_FREQ / wall_elapsed : 0.0,
                 sys->poc_mismatches, sys->poc_reversals,
                 sys->cadence_samples ? sys->min_date_step : 0,
                 sys->cadence_samples ? sys->max_date_step : 0,
                 sys->nonmonotonic_dates, sys->irregular_dates);
        sys->cadence_wall_start = wall_now;
        sys->cadence_samples = 0;
        sys->poc_mismatches = 0;
        sys->poc_reversals = 0;
        sys->nonmonotonic_dates = 0;
        sys->irregular_dates = 0;
    }
}

/* PTS values arrive in decoding order while Edge264 returns pictures in
 * presentation order.  Keeping the small reorder window sorted associates the
 * oldest pending presentation timestamp with the next bumped picture. */
static void DatePush(decoder_sys_t *sys, vlc_tick_t date)
{
    if (date == VLC_TICK_INVALID)
        return;

    if (sys->date_count == MVC_MAX_DATES)
        memmove(sys->dates, sys->dates + 1,
                (MVC_MAX_DATES - 1) * sizeof(sys->dates[0]));
    else
        sys->date_count++;

    unsigned pos = sys->date_count - 1;
    while (pos > 0 && sys->dates[pos - 1] > date)
    {
        sys->dates[pos] = sys->dates[pos - 1];
        pos--;
    }
    sys->dates[pos] = date;
}

static vlc_tick_t DatePop(decoder_sys_t *sys)
{
    if (sys->date_count == 0)
        return VLC_TICK_INVALID;
    vlc_tick_t date = sys->dates[0];
    sys->date_count--;
    memmove(sys->dates, sys->dates + 1,
            sys->date_count * sizeof(sys->dates[0]));
    return date;
}

static void DateDropThrough(decoder_sys_t *sys, vlc_tick_t date)
{
    unsigned count = 0;
    while (count < sys->date_count && sys->dates[count] <= date)
        count++;
    if (count == 0)
        return;
    sys->date_count -= count;
    memmove(sys->dates, sys->dates + count,
            sys->date_count * sizeof(sys->dates[0]));
}

static void EmitPendingPicture(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    if (sys->pending_count == 0)
        return;

    mvc_pending_picture_t pending = sys->pending[0];
    sys->pending_count--;
    memmove(sys->pending, sys->pending + 1,
            sys->pending_count * sizeof(sys->pending[0]));

    pending.picture->date = pending.date;
    if (pending.picture->date != VLC_TICK_INVALID)
        DateDropThrough(sys, pending.picture->date);
    else
        pending.picture->date = DatePop(sys);
    if (pending.picture->date != VLC_TICK_INVALID)
        pending.picture->date += sys->output_delay;
    ReportCadence(dec, sys, &pending, pending.picture->date);
    decoder_QueueVideo(dec, pending.picture);
}

static void InsertPendingPicture(decoder_t *dec, picture_t *picture,
                                 const Edge264Frame *frame)
{
    decoder_sys_t *sys = dec->p_sys;

    /* Edge264 worker threads complete pictures out of display order. Keep the
     * same four-picture POC look-ahead as SyLC: this covers the MVC stream's
     * B-frame reorder depth while releasing the borrowed DPB slots as soon as
     * their planes have been copied. The IDR POC floor in our Edge264 contrib
     * makes the base-view POC a monotonic key across GOP boundaries. */
    unsigned pos = sys->pending_count++;
    while (pos > 0 && sys->pending[pos - 1].poc > frame->PictureOrderCnt)
    {
        sys->pending[pos] = sys->pending[pos - 1];
        pos--;
    }
    sys->pending[pos] = (mvc_pending_picture_t) {
        .picture = picture,
        .date = frame->Timestamp,
        .frame_id = frame->FrameId,
        .frame_id_mvc = frame->FrameId_mvc,
        .poc = frame->PictureOrderCnt,
        .poc_mvc = frame->PictureOrderCnt_mvc,
    };

    if (sys->pending_count > sys->reorder_depth)
        EmitPendingPicture(dec);
}

static void DrainPendingPictures(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    while (sys->pending_count != 0)
        EmitPendingPicture(dec);
}

static void ClearPendingPictures(decoder_sys_t *sys)
{
    for (unsigned i = 0; i < sys->pending_count; ++i)
        picture_Release(sys->pending[i].picture);
    sys->pending_count = 0;
}

static void CopyPlane(uint8_t *dst, ptrdiff_t dst_pitch,
                      const uint8_t *src, ptrdiff_t src_pitch,
                      unsigned width, unsigned height)
{
    for (unsigned y = 0; y < height; ++y)
    {
        memcpy(dst, src, width);
        dst += dst_pitch;
        src += src_pitch;
    }
}

static picture_context_t *MVCDirectContextCopy(picture_context_t *opaque)
{
    powervlc_mvc_piccontext *ctx = (powervlc_mvc_piccontext *)opaque;
    __sync_add_and_fetch(&ctx->refs, 1);
    return opaque;
}

static void MVCDirectContextDestroy(picture_context_t *opaque)
{
    powervlc_mvc_piccontext *ctx = (powervlc_mvc_piccontext *)opaque;
    if (__sync_sub_and_fetch(&ctx->refs, 1) != 0)
        return;
    if (!ctx->edge_returned)
        ctx->return_frame(ctx->decoder, ctx->return_arg);
    if (ctx->packed_base_owner != NULL)
        ctx->release_packed_base(ctx->packed_base_owner);
    ctx->magic = 0;
    free(ctx);
}

static void MVCReturnEdgeFrame(void *decoder, void *return_arg)
{
    edge264_return_frame((Edge264Decoder *)decoder, return_arg);
}

#if defined(MVC_HAVE_VDA)
static void MVCReleasePackedBase(void *opaque)
{
    CVImageBufferRef image = (CVImageBufferRef)opaque;
    CVPixelBufferUnlockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
    CVPixelBufferRelease(image);
}

static void MVCVDAClearOwners(mvc_vda_t *vda)
{
    mvc_vda_owner_t *owner = vda->owners;
    vda->owners = NULL;
    while (owner != NULL)
    {
        mvc_vda_owner_t *next = owner->next;
        CVPixelBufferRelease(owner->image);
        free(owner);
        owner = next;
    }
}

static void MVCVDAStoreOwner(decoder_sys_t *sys, int32_t frame_id,
                             CVImageBufferRef image)
{
    if (!sys->direct_output || frame_id < 0 || image == NULL)
        return;
    mvc_vda_owner_t *owner = malloc(sizeof(*owner));
    if (owner == NULL)
        return;
    owner->image = CVPixelBufferRetain(image);
    owner->frame_id = frame_id;
    owner->next = sys->vda.owners;
    sys->vda.owners = owner;
    sys->vda_owner_count++;
}

static CVImageBufferRef MVCVDATakeOwner(decoder_sys_t *sys, int32_t frame_id)
{
    mvc_vda_owner_t **link = &sys->vda.owners;
    while (*link != NULL && (*link)->frame_id != frame_id)
        link = &(*link)->next;
    if (*link == NULL)
    {
        sys->vda_owner_misses++;
        if (getenv("VLC_MVC_OWNER_DIAGNOSTICS") != NULL &&
            sys->vda_owner_misses < 8)
            fprintf(stderr, "MVC_OWNER miss frame=%d queued=%u\n",
                    frame_id, sys->vda_owner_count);
        return NULL;
    }
    mvc_vda_owner_t *owner = *link;
    *link = owner->next;
    CVImageBufferRef image = owner->image;
    free(owner);
    sys->vda_owner_count--;
    sys->vda_owner_hits++;
    if (getenv("VLC_MVC_OWNER_DIAGNOSTICS") != NULL &&
        (sys->vda_owner_hits < 8 || sys->vda_owner_hits % 120 == 0))
        fprintf(stderr, "MVC_OWNER hit frame=%d queued=%u hits=%u misses=%u\n",
                frame_id, sys->vda_owner_count, sys->vda_owner_hits,
                sys->vda_owner_misses);
    return image;
}
#endif

static powervlc_mvc_piccontext *MVCDirectContextNew(
    decoder_sys_t *sys, const Edge264Frame *frame, bool base_is_right)
{
    powervlc_mvc_piccontext *ctx = calloc(1, sizeof(*ctx));
    if (ctx == NULL)
        return NULL;
    ctx->context.destroy = MVCDirectContextDestroy;
    ctx->context.copy = MVCDirectContextCopy;
    ctx->magic = POWERVLC_MVC_DIRECT_MAGIC;
    ctx->refs = 1;
    ctx->decoder = sys->decoder;
    ctx->return_arg = frame->return_arg;
    ctx->return_frame = MVCReturnEdgeFrame;
    const uint8_t *const *top = base_is_right
                              ? frame->samples_mvc : frame->samples;
    const uint8_t *const *bottom = base_is_right
                                 ? frame->samples : frame->samples_mvc;
    for (unsigned plane = 0; plane < 3; ++plane)
    {
        ctx->planes[0][plane] = top[plane];
        ctx->planes[1][plane] = bottom[plane];
        ctx->strides[0][plane] = ctx->strides[1][plane] =
            plane == 0 ? frame->stride_Y : frame->stride_C;
        ctx->widths[plane] = plane == 0 ? frame->width_Y : frame->width_C;
        ctx->heights[plane] = plane == 0 ? frame->height_Y : frame->height_C;
    }
#if defined(MVC_HAVE_VDA)
    /* The input callback can be several B-frames ahead of the picture being
     * returned here. Retrieve the VDA owner tagged with Edge264's base DPB
     * FrameId instead of accidentally pairing the current input image with
     * an older dependent view. */
    CVImageBufferRef image = MVCVDATakeOwner(sys, frame->FrameId);
    if (image != NULL && CVPixelBufferGetPixelFormatType(image) ==
                         kCVPixelFormatType_422YpCbCr8)
    {
        if (CVPixelBufferLockBaseAddress(image,
                kCVPixelBufferLock_ReadOnly) == 0)
        {
            ctx->packed_base = true;
            ctx->base_eye = base_is_right ? 1 : 0;
            ctx->packed_base_pixels = CVPixelBufferGetBaseAddress(image);
            ctx->packed_base_stride =
                (int)CVPixelBufferGetBytesPerRow(image);
            ctx->packed_base_width = (unsigned)CVPixelBufferGetWidth(image);
            ctx->packed_base_height = (unsigned)CVPixelBufferGetHeight(image);
            ctx->packed_base_owner = image;
            ctx->release_packed_base = MVCReleasePackedBase;
        }
        else
            CVPixelBufferRelease(image);
    }
    else if (image != NULL)
        CVPixelBufferRelease(image);
#endif
    return ctx;
}

static void ClearPlanePadding(plane_t *plane, unsigned width,
                              unsigned height, uint8_t value)
{
    /* The visible stereo views overwrite every useful byte below.  Clearing
     * the complete 1920x2160 allocation first doubled memory traffic on the
     * Core 2 Duo for no visual benefit. Only allocator pitch/line padding
     * needs a deterministic studio-range value. */
    if ((unsigned)plane->i_pitch > width)
        for (unsigned y = 0; y < height; ++y)
            memset(plane->p_pixels + (ptrdiff_t)y * plane->i_pitch + width,
                   value, plane->i_pitch - width);
    if ((unsigned)plane->i_lines > height)
        memset(plane->p_pixels + (ptrdiff_t)height * plane->i_pitch, value,
               (size_t)(plane->i_lines - height) * plane->i_pitch);
}

static int ConfigureOutput(decoder_t *dec, const Edge264Frame *frame)
{
    const unsigned width = frame->width_Y;
    const unsigned height = frame->height_Y;

    if (dec->fmt_out.video.i_visible_width == width &&
        dec->fmt_out.video.i_visible_height == height * 2)
        return VLC_SUCCESS;

    /* Keep the two full-resolution views adjacent in decoder memory. The
     * display backend inserts the HDMI frame-packing blanking interval at
     * presentation time, avoiding an odd-height 4:2:0 intermediate picture.
     * SAR 2:1 preserves the per-eye display aspect outside a frame-packing
     * backend. */
    video_format_Setup(&dec->fmt_out.video, VLC_CODEC_I420,
                       width, height * 2, width, height * 2, 2, 1);
    dec->fmt_out.i_codec = VLC_CODEC_I420;
    dec->fmt_out.video.multiview_mode = MULTIVIEW_STEREO_FRAMEPACKED;
    dec->fmt_out.video.primaries = dec->fmt_in.video.primaries;
    dec->fmt_out.video.transfer = dec->fmt_in.video.transfer;
    dec->fmt_out.video.space = dec->fmt_in.video.space;
    dec->fmt_out.video.b_color_range_full = dec->fmt_in.video.b_color_range_full;
    dec->fmt_out.video.i_frame_rate = dec->fmt_in.video.i_frame_rate;
    dec->fmt_out.video.i_frame_rate_base = dec->fmt_in.video.i_frame_rate_base;

    return decoder_UpdateVideoFormat(dec);
}

static bool NALIsBasePicture(const uint8_t *nal, size_t size);

#if defined(MVC_HAVE_VDA)
static int MVCFallbackAfterInjectionFailure(decoder_t *dec, block_t *block,
                                            mvc_vda_picture_t *picture)
{
    decoder_sys_t *sys = dec->p_sys;
#if defined(MVC_HAVE_VT)
    if (sys->vda.use_vt)
    {
        /* A clip boundary can leave no Edge264 base slot for an otherwise
         * valid VideoToolbox picture. Repeating the hand-off for every
         * following access unit drops a whole GOP and lets the BD-J clock run
         * away from the last queued picture. Stop using the hybrid path for
         * this decoder instance; subsequent complete access units are then
         * decoded by Edge264 exactly like the pre-VDA Apple Silicon path. */
        msg_Warn(dec, "VideoToolbox/Edge264 hand-off lost synchronization; "
                 "continuing with Edge264 for both MVC views");
        sys->vda.active = false;
        sys->vda.failed = true;
        edge264_set_external_base(sys->decoder, 0);
        sys->vda.processing_picture = NULL;
        MVCHardwarePictureDelete(picture);
        MVCVDAFlush(sys);
        block_Release(block);
        return VLCDEC_SUCCESS;
    }
#endif
    /* Preserve the established VDA/GeForce 320M failure semantics. */
    msg_Err(dec, "could not inject VDA base view into Edge264");
    sys->vda.processing_picture = NULL;
    MVCHardwarePictureDelete(picture);
    block_Release(block);
    return VLCDEC_ECRITICAL;
}
#endif

static bool NALBelongsToBaseAVC(const uint8_t *nal, size_t size)
{
    if (size == 0)
        return false;
    const unsigned type = nal[0] & 0x1f;
    /* Same AVC-compatible substream as the validated historical VDA module.
     * hxxx_helper consumes SPS/PPS, tracks both PPS IDs, strips parameter
     * sets from submitted samples and preserves the access-unit SEI/AUD. */
    return type == 1 || type == 5 || type == 6 || type == 7 || type == 8 ||
           type == 9;
}

static int QueueFrames(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    Edge264Frame frame;
    int ret;

    /* Borrow both DPB slots until their planes have been copied. With worker
     * threads, borrow=0 releases them before edge264_get_frame() returns and
     * a decoder task can overwrite a 1080p view while CopyPlane() is still
     * reading it, which is visible as whole-view flicker/tearing. */
    while ((ret = edge264_get_frame(sys->decoder, &frame, 1)) == 0)
    {
        if (frame.bit_depth_Y != 8 || frame.bit_depth_C != 8)
        {
            msg_Err(dec, "unsupported MVC bit depth %d/%d",
                    frame.bit_depth_Y, frame.bit_depth_C);
            DatePop(sys);
            edge264_return_frame(sys->decoder, frame.return_arg);
            continue;
        }
        if (frame.samples_mvc[0] == NULL)
        {
            if (!sys->warned_missing_view)
            {
                msg_Warn(dec, "MVC picture has no dependent view; waiting for stereo pairs");
                sys->warned_missing_view = true;
            }
            DatePop(sys);
            edge264_return_frame(sys->decoder, frame.return_arg);
            continue;
        }
        if (ConfigureOutput(dec, &frame) != VLC_SUCCESS)
        {
            edge264_return_frame(sys->decoder, frame.return_arg);
            return VLCDEC_ECRITICAL;
        }

        if (!sys->reported_stereo)
        {
            msg_Info(dec, "decoded first full-resolution MVC stereo frame "
                     "(%dx%d per eye, POC %d/%d)",
                     frame.width_Y, frame.height_Y,
                     frame.PictureOrderCnt, frame.PictureOrderCnt_mvc);
            sys->reported_stereo = true;
            if (sys->have_injected_hash)
                msg_Info(dec, "hybrid MVC copy check: VDA %016"PRIx64"/"
                         "%016"PRIx64"/%016"PRIx64", Edge264 %016"PRIx64
                         "/%016"PRIx64"/%016"PRIx64,
                         sys->injected_hash[0], sys->injected_hash[1],
                         sys->injected_hash[2],
                         MVCHashPlane(frame.samples[0], frame.stride_Y,
                                      frame.width_Y, frame.height_Y),
                         MVCHashPlane(frame.samples[1], frame.stride_C,
                                      frame.width_C, frame.height_C),
                         MVCHashPlane(frame.samples[2], frame.stride_C,
                                      frame.width_C, frame.height_C));
        }

        picture_t *pic = decoder_NewPicture(dec);
        if (pic == NULL)
        {
            edge264_return_frame(sys->decoder, frame.return_arg);
            return VLCDEC_ECRITICAL;
        }

        const unsigned width_y = __MIN((unsigned)frame.width_Y,
                                       (unsigned)pic->p[0].i_visible_pitch);
        const unsigned width_c = __MIN((unsigned)frame.width_C,
                                       (unsigned)pic->p[1].i_visible_pitch);
        const unsigned height_y = frame.height_Y;
        const unsigned height_c = frame.height_C;
        const bool base_is_right = dec->fmt_in.video.multiview_mode ==
                                   MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE;
        const uint8_t *const *top_view = base_is_right
                                       ? frame.samples_mvc : frame.samples;
        const uint8_t *const *bottom_view = base_is_right
                                          ? frame.samples : frame.samples_mvc;

        if (sys->direct_output)
        {
            powervlc_mvc_piccontext *ctx =
                MVCDirectContextNew(sys, &frame, base_is_right);
            if (ctx != NULL)
            {
                /* The externally injected VDA base is only guaranteed until
                 * this Decode() call returns; unlike Edge264's dependent-view
                 * DPB it cannot stay borrowed until the vout uploads it.
                 * Preserve just that one view in the VLC pool picture. This
                 * still removes half of the old 6.2 MB/frame CPU copy. */
                const unsigned base_eye = base_is_right ? 1 : 0;
                const unsigned copied_eye = ctx->packed_base
                                          ? 1 - base_eye : base_eye;
                const uint8_t *const *copied_view = ctx->packed_base
                                                  ? frame.samples_mvc
                                                  : frame.samples;
                for (unsigned plane = 0; plane < 3; ++plane)
                {
                    const unsigned ph = plane == 0 ? height_y : height_c;
                    const unsigned pw = plane == 0 ? width_y : width_c;
                    uint8_t *dst = pic->p[plane].p_pixels +
                        (ptrdiff_t)(copied_eye ? ph : 0) * pic->p[plane].i_pitch;
                    CopyPlane(dst, pic->p[plane].i_pitch,
                              copied_view[plane],
                              plane == 0 ? frame.stride_Y : frame.stride_C,
                              pw, ph);
                    ctx->planes[copied_eye][plane] = dst;
                    ctx->strides[copied_eye][plane] = pic->p[plane].i_pitch;
                }
                if (ctx->packed_base)
                {
                    edge264_return_frame(sys->decoder, frame.return_arg);
                    ctx->edge_returned = true;
                    ctx->return_arg = NULL;
                }
                pic->context = &ctx->context;
                pic->b_progressive = true;
                InsertPendingPicture(dec, pic, &frame);
                /* The context now owns Edge264's borrowed DPB slots. */
                continue;
            }
        }

        CopyPlane(pic->p[0].p_pixels, pic->p[0].i_pitch,
                  top_view[0], frame.stride_Y, width_y, height_y);
        CopyPlane(pic->p[1].p_pixels, pic->p[1].i_pitch,
                  top_view[1], frame.stride_C, width_c, height_c);
        CopyPlane(pic->p[2].p_pixels, pic->p[2].i_pitch,
                  top_view[2], frame.stride_C, width_c, height_c);

        CopyPlane(pic->p[0].p_pixels + (ptrdiff_t)height_y * pic->p[0].i_pitch,
                  pic->p[0].i_pitch, bottom_view[0], frame.stride_Y,
                  width_y, height_y);
        CopyPlane(pic->p[1].p_pixels + (ptrdiff_t)height_c * pic->p[1].i_pitch,
                  pic->p[1].i_pitch, bottom_view[1], frame.stride_C,
                  width_c, height_c);
        CopyPlane(pic->p[2].p_pixels + (ptrdiff_t)height_c * pic->p[2].i_pitch,
                  pic->p[2].i_pitch, bottom_view[2], frame.stride_C,
                  width_c, height_c);

        ClearPlanePadding(&pic->p[0], width_y, 2 * height_y, 16);
        ClearPlanePadding(&pic->p[1], width_c, 2 * height_c, 128);
        ClearPlanePadding(&pic->p[2], width_c, 2 * height_c, 128);

        pic->b_progressive = true;
        edge264_return_frame(sys->decoder, frame.return_arg);
        InsertPendingPicture(dec, pic, &frame);
    }
    return VLCDEC_SUCCESS;
}

#if defined(MVC_HAVE_VDA)
static const CFStringRef mvc_vda_serial_key =
    CFSTR("org.powervlc.mvc-vda.serial");
static const CFStringRef mvc_vda_data_key =
    CFSTR("org.powervlc.mvc-vda.compressed-data");

static void MVCQueueHardwareImage(decoder_sys_t *sys, uint64_t serial,
                                  CVImageBufferRef image)
{
    if (image == NULL || serial == 0)
        return;

    mvc_vda_picture_t *pic = malloc(sizeof(*pic));
    if (pic == NULL)
        return;
    pic->image = CVPixelBufferRetain(image);
    pic->nv12 = NULL;
    pic->nv12_y = NULL;
    pic->nv12_uv = NULL;
    pic->nv12_stride_y = 0;
    pic->nv12_stride_uv = 0;
    pic->width = (unsigned)CVPixelBufferGetWidth(image);
    pic->height = (unsigned)CVPixelBufferGetHeight(image);
    pic->serial = serial;
    pic->next = NULL;

    vlc_mutex_lock(&sys->vda.lock);
    mvc_vda_picture_t **tail = &sys->vda.pictures;
    while (*tail != NULL)
        tail = &(*tail)->next;
    *tail = pic;
    vlc_cond_broadcast(&sys->vda.wait);
    vlc_mutex_unlock(&sys->vda.lock);
}

static void MVCHardwarePictureDelete(mvc_vda_picture_t *pic)
{
    if (pic == NULL)
        return;
    if (pic->image != NULL)
        CVPixelBufferRelease(pic->image);
    free(pic->nv12);
    free(pic);
}

static void MVCVDACallback(void *opaque, CFDictionaryRef frame_info,
                           OSStatus status, uint32_t flags,
                           CVImageBufferRef image)
{
    decoder_sys_t *sys = opaque;
    VLC_UNUSED(flags);
    if (status != kVDADecoderNoErr || image == NULL || frame_info == NULL)
        return;

    CFNumberRef ref = CFDictionaryGetValue(frame_info, mvc_vda_serial_key);
    int64_t serial = -1;
    if (ref == NULL || !CFNumberGetValue(ref, kCFNumberSInt64Type, &serial))
        return;

    MVCQueueHardwareImage(sys, (uint64_t)serial, image);
}

#if defined(MVC_HAVE_VT)
static mvc_vda_picture_t *MVCVTCopyImage(CVPixelBufferRef image,
                                         uint64_t serial)
{
    if (image == NULL || serial == 0 ||
        CVPixelBufferGetPlaneCount(image) != 2 ||
        CVPixelBufferGetPixelFormatType(image) !=
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
        return NULL;
    if (CVPixelBufferLockBaseAddress(image, kCVPixelBufferLock_ReadOnly) !=
        kCVReturnSuccess)
        return NULL;

    const unsigned width = (unsigned)CVPixelBufferGetWidthOfPlane(image, 0);
    const unsigned height = (unsigned)CVPixelBufferGetHeightOfPlane(image, 0);
    const unsigned chroma_height =
        (unsigned)CVPixelBufferGetHeightOfPlane(image, 1);
    const size_t y_bytes = (size_t)width * height;
    const size_t uv_bytes = (size_t)width * chroma_height;
    mvc_vda_picture_t *pic = calloc(1, sizeof(*pic));
    if (pic != NULL)
        pic->nv12 = malloc(y_bytes + uv_bytes);
    if (pic == NULL || pic->nv12 == NULL)
    {
        free(pic);
        CVPixelBufferUnlockBaseAddress(image,
                                       kCVPixelBufferLock_ReadOnly);
        return NULL;
    }

    pic->nv12_y = pic->nv12;
    pic->nv12_uv = pic->nv12 + y_bytes;
    pic->nv12_stride_y = (int)width;
    pic->nv12_stride_uv = (int)width;
    pic->width = width;
    pic->height = height;
    pic->serial = serial;
    const uint8_t *src_y = CVPixelBufferGetBaseAddressOfPlane(image, 0);
    const uint8_t *src_uv = CVPixelBufferGetBaseAddressOfPlane(image, 1);
    const size_t src_stride_y =
        CVPixelBufferGetBytesPerRowOfPlane(image, 0);
    const size_t src_stride_uv =
        CVPixelBufferGetBytesPerRowOfPlane(image, 1);
    for (unsigned row = 0; row < height; ++row)
        memcpy(pic->nv12 + (size_t)row * width,
               src_y + (size_t)row * src_stride_y, width);
    for (unsigned row = 0; row < chroma_height; ++row)
        memcpy(pic->nv12 + y_bytes + (size_t)row * width,
               src_uv + (size_t)row * src_stride_uv, width);
    CVPixelBufferUnlockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
    return pic;
}

static void MVCVTCallback(void *opaque, void *source_frame,
                          OSStatus status, VTDecodeInfoFlags flags,
                          CVImageBufferRef image, CMTime pts, CMTime duration)
{
    VLC_UNUSED(flags);
    VLC_UNUSED(pts);
    VLC_UNUSED(duration);
    if (status != noErr)
        return;
    /* No CoreVideo object survives this callback: the MVC serial queue owns
     * ordinary NV12 memory, immune to VideoToolbox pool recycling and clip
     * teardown. */
    mvc_vda_picture_t *pic = MVCVTCopyImage(image,
        (uint64_t)(uintptr_t)source_frame);
    if (pic != NULL)
    {
        decoder_sys_t *sys = opaque;
        vlc_mutex_lock(&sys->vda.lock);
        mvc_vda_picture_t **tail = &sys->vda.pictures;
        while (*tail != NULL)
            tail = &(*tail)->next;
        *tail = pic;
        vlc_cond_broadcast(&sys->vda.wait);
        vlc_mutex_unlock(&sys->vda.lock);
    }
}
#endif

static void MVCVDAClearPictures(mvc_vda_t *vda)
{
    vlc_mutex_lock(&vda->lock);
    mvc_vda_picture_t *pic = vda->pictures;
    vda->pictures = NULL;
    vlc_mutex_unlock(&vda->lock);
    while (pic != NULL)
    {
        mvc_vda_picture_t *next = pic->next;
        MVCHardwarePictureDelete(pic);
        pic = next;
    }
}

static void MVCVDAClearBlocks(mvc_vda_t *vda)
{
    mvc_vda_block_t *entry = vda->blocks;
    vda->blocks = NULL;
    vda->blocks_tail = &vda->blocks;
    while (entry != NULL)
    {
        mvc_vda_block_t *next = entry->next;
        block_Release(entry->block);
        free(entry);
        entry = next;
    }
}

/* Return the exact standard AVCDecoderConfigurationRecord prefix. mkvmerge
 * appends mvcC after the ordinary SPS/PPS arrays; VDA must not see that MVC
 * extension. */
static size_t MVCBaseAVCCSize(const uint8_t *p, size_t size)
{
    if (size < 7 || p[0] != 1)
        return 0;
    size_t pos = 5;
    for (unsigned array = 0; array < 2; ++array)
    {
        if (pos >= size)
            return 0;
        unsigned count = p[pos++] & (array == 0 ? 0x1f : 0xff);
        for (unsigned i = 0; i < count; ++i)
        {
            if (pos + 2 > size)
                return 0;
            size_t nal_size = (size_t)p[pos] << 8 | p[pos + 1];
            pos += 2;
            if (nal_size > size - pos)
                return 0;
            pos += nal_size;
        }
    }
    /* High-profile avcC records can continue after the PPS array with
     * chroma/bit-depth/SPS-ext fields. mkvmerge then appends a sized mvcC
     * box. Preserve every standard avcC byte up to that box instead of
     * truncating at the PPS array (VDA accepts the truncated record but the
     * NVIDIA decoder subsequently produces corrupt coloured scanlines). */
    for (size_t i = pos + 4; i + 4 <= size; ++i)
        if (!memcmp(p + i, "mvcC", 4))
            return i - 4;
    return pos;
}

static void MVCVDADestroy(decoder_sys_t *sys)
{
    mvc_vda_t *vda = &sys->vda;
    if (!vda->initialized)
        return;
#if defined(MVC_HAVE_VT)
    if (vda->vt_session != NULL)
    {
        VTDecompressionSessionFinishDelayedFrames(vda->vt_session);
        VTDecompressionSessionWaitForAsynchronousFrames(vda->vt_session);
        VTDecompressionSessionInvalidate(vda->vt_session);
        CFRelease(vda->vt_session);
        vda->vt_session = NULL;
    }
    if (vda->vt_format != NULL)
    {
        CFRelease(vda->vt_format);
        vda->vt_format = NULL;
    }
#endif
    if (vda->session != NULL)
    {
        vda->flush(vda->session, 0);
        vda->destroy(vda->session);
        vda->session = NULL;
    }
    MVCVDAClearPictures(vda);
    MVCVDAClearOwners(vda);
    MVCVDAClearBlocks(vda);
    if (vda->hh_initialized)
        hxxx_helper_clean(&vda->hh);
    if (vda->avcc != NULL)
        block_Release(vda->avcc);
    if (vda->dump != NULL)
        fclose(vda->dump);
    if (vda->framework != NULL)
        dlclose(vda->framework);
    vlc_cond_destroy(&vda->wait);
    vlc_mutex_destroy(&vda->lock);
    memset(vda, 0, sizeof(*vda));
}

static void MVCVDAWriteAVCCAsAnnexB(FILE *file, const block_t *config)
{
    const uint8_t *p = config->p_buffer;
    const size_t size = config->i_buffer;
    if (file == NULL || size < 7 || p[0] != 1)
        return;

    static const uint8_t startcode[4] = { 0, 0, 0, 1 };
    size_t pos = 6;
    unsigned count = p[5] & 0x1f;
    for (unsigned arrays = 0; arrays < 2; ++arrays)
    {
        for (unsigned i = 0; i < count; ++i)
        {
            if (pos + 2 > size)
                return;
            size_t nal_size = (size_t)p[pos] << 8 | p[pos + 1];
            pos += 2;
            if (nal_size == 0 || nal_size > size - pos)
                return;
            fwrite(startcode, 1, sizeof(startcode), file);
            fwrite(p + pos, 1, nal_size, file);
            pos += nal_size;
        }
        if (pos >= size)
            return;
        count = p[pos++];
    }
}

static block_t *MVCVDAAVCCFromBlock(const decoder_sys_t *sys,
                                    const block_t *block)
{
    const uint8_t *sps = NULL, *pps = NULL;
    size_t sps_size = 0, pps_size = 0;
    if (block == NULL)
        return NULL;

    if (sys->nal_length_size != 0)
    {
        size_t offset = 0;
        while (offset + sys->nal_length_size <= block->i_buffer)
        {
            size_t nal_size = 0;
            for (unsigned i = 0; i < sys->nal_length_size; ++i)
                nal_size = (nal_size << 8) | block->p_buffer[offset++];
            if (nal_size > block->i_buffer - offset)
                break;
            unsigned type = nal_size != 0 ? block->p_buffer[offset] & 0x1f : 0;
            if (type == 7 && sps == NULL)
            {
                sps = block->p_buffer + offset;
                sps_size = nal_size;
            }
            else if (type == 8 && pps == NULL)
            {
                h264_picture_parameter_set_t *decoded = h264_decode_pps(
                    block->p_buffer + offset, nal_size, true);
                if (decoded != NULL && decoded->i_id == 0 &&
                    decoded->i_sps_id == 0)
                {
                    pps = block->p_buffer + offset;
                    pps_size = nal_size;
                }
                if (decoded != NULL)
                    h264_release_pps(decoded);
            }
            if (sps != NULL && pps != NULL)
                break;
            offset += nal_size;
        }
    }
    else
    {
        hxxx_iterator_ctx_t it;
        const uint8_t *nal;
        size_t nal_size;
        hxxx_iterator_init(&it, block->p_buffer, block->i_buffer, 0);
        while (hxxx_annexb_iterate_next(&it, &nal, &nal_size))
        {
            unsigned type = nal_size != 0 ? nal[0] & 0x1f : 0;
            if (type == 7 && sps == NULL)
            {
                sps = nal;
                sps_size = nal_size;
            }
            else if (type == 8 && pps == NULL)
            {
                h264_picture_parameter_set_t *decoded =
                    h264_decode_pps(nal, nal_size, true);
                if (decoded != NULL && decoded->i_id == 0 &&
                    decoded->i_sps_id == 0)
                {
                    pps = nal;
                    pps_size = nal_size;
                }
                if (decoded != NULL)
                    h264_release_pps(decoded);
            }
            if (sps != NULL && pps != NULL)
                break;
        }
    }
    if (sps_size < 4 || pps_size == 0 || sps_size > UINT16_MAX ||
        pps_size > UINT16_MAX)
        return NULL;

    block_t *avcc = block_Alloc(11 + sps_size + pps_size);
    if (avcc == NULL)
        return NULL;
    uint8_t *p = avcc->p_buffer;
    *p++ = 1;
    *p++ = sps[1];
    *p++ = sps[2];
    *p++ = sps[3];
    *p++ = 0xfc | ((sys->nal_length_size != 0
                   ? sys->nal_length_size : 4) - 1);
    *p++ = 0xe1;
    *p++ = sps_size >> 8;
    *p++ = sps_size;
    memcpy(p, sps, sps_size);
    p += sps_size;
    *p++ = 1;
    *p++ = pps_size >> 8;
    *p++ = pps_size;
    memcpy(p, pps, pps_size);
    return avcc;
}

#if defined(MVC_HAVE_VT)
static int MVCVTCreateSession(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    mvc_vda_t *vda = &sys->vda;
    if (vda->avcc == NULL || vda->avcc->i_buffer < 7)
        return VLC_EGENERIC;

    const uint8_t *p = vda->avcc->p_buffer;
    const size_t size = vda->avcc->i_buffer;
    size_t pos = 5;
    const unsigned sps_count = p[pos++] & 0x1f;
    const uint8_t *sets[32];
    size_t set_sizes[32];
    unsigned set_count = 0;
    for (unsigned array = 0; array < 2; ++array)
    {
        const unsigned count = array == 0 ? sps_count
                                         : (pos < size ? p[pos++] : 0);
        for (unsigned i = 0; i < count; ++i)
        {
            if (pos + 2 > size || set_count == ARRAY_SIZE(sets))
                return VLC_EGENERIC;
            const size_t nal_size = (size_t)p[pos] << 8 | p[pos + 1];
            pos += 2;
            if (nal_size == 0 || nal_size > size - pos)
                return VLC_EGENERIC;
            sets[set_count] = p + pos;
            set_sizes[set_count++] = nal_size;
            pos += nal_size;
        }
    }
    if (set_count < 2)
        return VLC_EGENERIC;

    if (vda->vt_session != NULL)
    {
        VTDecompressionSessionFinishDelayedFrames(vda->vt_session);
        VTDecompressionSessionWaitForAsynchronousFrames(vda->vt_session);
        VTDecompressionSessionInvalidate(vda->vt_session);
        CFRelease(vda->vt_session);
        vda->vt_session = NULL;
    }
    if (vda->vt_format != NULL)
    {
        CFRelease(vda->vt_format);
        vda->vt_format = NULL;
    }

    OSStatus status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
        kCFAllocatorDefault, set_count, sets, set_sizes, 4, &vda->vt_format);
    if (status != noErr)
    {
        msg_Warn(dec, "VideoToolbox format creation failed (status %d)",
                 (int)status);
        return VLC_EGENERIC;
    }

    CFMutableDictionaryRef specification = CFDictionaryCreateMutable(NULL, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef attrs = CFDictionaryCreateMutable(NULL, 3,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (specification == NULL || attrs == NULL)
        goto error;
    CFDictionarySetValue(specification,
        kVTVideoDecoderSpecification_EnableHardwareAcceleratedVideoDecoder,
        kCFBooleanTrue);
    int value = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt32Type, &value);
    if (number == NULL)
        goto error;
    CFDictionarySetValue(attrs, kCVPixelBufferPixelFormatTypeKey, number);
    CFRelease(number);
    CFDictionaryRef surface_props = CFDictionaryCreate(NULL, NULL, NULL, 0,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (surface_props != NULL)
    {
        CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey,
                             surface_props);
        CFRelease(surface_props);
    }

    VTDecompressionOutputCallbackRecord callback = {
        .decompressionOutputCallback = MVCVTCallback,
        .decompressionOutputRefCon = sys,
    };
    status = VTDecompressionSessionCreate(kCFAllocatorDefault, vda->vt_format,
        specification, attrs, &callback, &vda->vt_session);
    CFRelease(specification);
    CFRelease(attrs);
    if (status != noErr)
    {
        msg_Warn(dec, "VideoToolbox session creation failed (status %d)",
                 (int)status);
        return VLC_EGENERIC;
    }
    return VLC_SUCCESS;

error:
    if (specification != NULL) CFRelease(specification);
    if (attrs != NULL) CFRelease(attrs);
    return VLC_EGENERIC;
}
#endif

static int MVCVDACreateSession(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    mvc_vda_t *vda = &sys->vda;
    if (vda->avcc == NULL)
        return VLC_EGENERIC;

    CFMutableDictionaryRef config = CFDictionaryCreateMutable(NULL, 4,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    CFMutableDictionaryRef attrs = CFDictionaryCreateMutable(NULL, 2,
        &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    if (config == NULL || attrs == NULL)
        goto error;

    int value = dec->fmt_in.video.i_width != 0
              ? dec->fmt_in.video.i_width : 1920;
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt32Type, &value);
    CFDictionarySetValue(config, *vda->key_width, number);
    CFRelease(number);
    value = dec->fmt_in.video.i_height != 0
          ? dec->fmt_in.video.i_height : 1080;
    number = CFNumberCreate(NULL, kCFNumberSInt32Type, &value);
    CFDictionarySetValue(config, *vda->key_height, number);
    CFRelease(number);
    value = 'avc1';
    number = CFNumberCreate(NULL, kCFNumberSInt32Type, &value);
    CFDictionarySetValue(config, *vda->key_source, number);
    CFRelease(number);

    CFDataRef avcc = CFDataCreate(NULL, vda->avcc->p_buffer,
                                  vda->avcc->i_buffer);
    if (avcc == NULL)
        goto error;
    CFDictionarySetValue(config, *vda->key_avcc, avcc);
    CFRelease(avcc);

    /* GeForce 320M VDA writes packed UYVY natively. Asking it for NV12 or
     * I420 inserts a synchronous driver conversion on every output frame;
     * the standalone VDA decoder measures roughly 9% of one core with UYVY
     * versus more than 50% with either 4:2:0 layout on this exact GPU. Edge264
     * accepts the packed base directly, so retain the driver's fast path. */
    char *wanted_chroma = var_InheritString(dec, "mvc-vda-chroma");
    if (wanted_chroma != NULL && !strcmp(wanted_chroma, "nv12"))
        value = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange;
    else if (wanted_chroma != NULL && !strcmp(wanted_chroma, "i420"))
        value = kCVPixelFormatType_420YpCbCr8Planar;
    else
        value = kCVPixelFormatType_422YpCbCr8;
    free(wanted_chroma);
    number = CFNumberCreate(NULL, kCFNumberSInt32Type, &value);
    CFDictionarySetValue(attrs, kCVPixelBufferPixelFormatTypeKey, number);
    CFRelease(number);

    /* Required by TN2267 whenever destination attributes are supplied. It
     * also keeps the NVIDIA decoder on its IOSurface-backed output path. */
    CFDictionaryRef surface_props = NULL;
    if (vda->key_iosurface != NULL)
    {
        surface_props = CFDictionaryCreate(NULL, NULL, NULL, 0,
            &kCFTypeDictionaryKeyCallBacks,
            &kCFTypeDictionaryValueCallBacks);
        if (surface_props != NULL)
            CFDictionarySetValue(attrs, *vda->key_iosurface, surface_props);
    }

    OSStatus status = vda->create(config, attrs,
        (VDADecoderOutputCallback *)MVCVDACallback, sys, &vda->session);
    if (surface_props != NULL)
        CFRelease(surface_props);
    CFRelease(attrs);
    CFRelease(config);
    if (status != kVDADecoderNoErr)
    {
        vda->session = NULL;
        msg_Dbg(dec, "hybrid MVC VDA session unavailable (status %d)",
                (int)status);
        return VLC_EGENERIC;
    }
    return VLC_SUCCESS;

error:
    if (attrs != NULL) CFRelease(attrs);
    if (config != NULL) CFRelease(config);
    return VLC_EGENERIC;
}

/* Blu-ray MVC streams may redefine PPS 0 inside every GOP.  The base slices
 * remain AVC-compatible, but VDA does not consume in-band parameter sets: it
 * only reads avcC when the session is created.  Track the first SPS/PPS pair
 * of each access unit (the base pair precedes subset-SPS/PPS 1), drain the
 * old asynchronous session, then recreate it before submitting the slices. */
static int MVCVDAUpdateConfiguration(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    mvc_vda_t *vda = &sys->vda;
    block_t *avcc = h264_helper_get_avcc_config(&vda->hh);
    if (avcc == NULL)
        return VLC_SUCCESS;
    if (vda->avcc != NULL && avcc->i_buffer == vda->avcc->i_buffer &&
        !memcmp(avcc->p_buffer, vda->avcc->p_buffer, avcc->i_buffer))
    {
        block_Release(avcc);
        return VLC_SUCCESS;
    }

    if (vda->avcc != NULL)
        block_Release(vda->avcc);
    vda->avcc = avcc;
#if defined(MVC_HAVE_VT)
    if (vda->use_vt)
    {
        msg_Dbg(dec, "hybrid MVC VideoToolbox parameter-set update #%u "
                "(%zu avcC bytes)", ++vda->config_generation,
                avcc->i_buffer);
        return MVCVTCreateSession(dec);
    }
#endif
    /* The asynchronous MVC queue still owns CVPixelBuffers from this VDA
     * session. Destroying it at every Blu-ray PPS revision makes the 320M
     * reject the next VDADecoderCreate with -12473. Keep the session alive:
     * MVCBuildBaseSample places PPS 0 immediately before its slices and the
     * legacy NVIDIA parser applies that in-band revision correctly. */
    msg_Dbg(dec, "hybrid MVC VDA in-band parameter-set update #%u "
            "(%zu avcC bytes)",
            ++vda->config_generation, avcc->i_buffer);
    return VLC_SUCCESS;
}

static int MVCVDAOpen(decoder_t *dec, const block_t *first_block)
{
    decoder_sys_t *sys = dec->p_sys;
    mvc_vda_t *vda = &sys->vda;
    const uint8_t *extra = dec->fmt_in.p_extra;
    size_t avcc_size = MVCBaseAVCCSize(extra, dec->fmt_in.i_extra);
    block_t *canonical_avcc = MVCVDAAVCCFromBlock(sys, first_block);
    if (canonical_avcc == NULL && avcc_size == 0)
        return VLC_EGENERIC;

#if defined(MVC_HAVE_VT)
    vda->use_vt = true;
#else
    vda->framework = dlopen("/System/Library/Frameworks/"
        "VideoDecodeAcceleration.framework/VideoDecodeAcceleration",
        RTLD_LOCAL | RTLD_LAZY);
    if (vda->framework == NULL)
    {
        if (canonical_avcc != NULL)
            block_Release(canonical_avcc);
        return VLC_EGENERIC;
    }

# define MVC_VDA_SYM(field, name) do {                                     \
    vda->field = (void *)dlsym(vda->framework, name);                       \
    if (vda->field == NULL) goto error;                                     \
} while (0)
    MVC_VDA_SYM(create, "VDADecoderCreate");
    MVC_VDA_SYM(decode, "VDADecoderDecode");
    MVC_VDA_SYM(flush, "VDADecoderFlush");
    MVC_VDA_SYM(destroy, "VDADecoderDestroy");
    MVC_VDA_SYM(key_height, "kVDADecoderConfiguration_Height");
    MVC_VDA_SYM(key_width, "kVDADecoderConfiguration_Width");
    MVC_VDA_SYM(key_source, "kVDADecoderConfiguration_SourceFormat");
    MVC_VDA_SYM(key_avcc, "kVDADecoderConfiguration_avcCData");
# undef MVC_VDA_SYM
    vda->key_iosurface = (const CFStringRef *)
        dlsym(RTLD_DEFAULT, "kCVPixelBufferIOSurfacePropertiesKey");
#endif

    vlc_mutex_init(&vda->lock);
    vlc_cond_init(&vda->wait);
    vda->blocks_tail = &vda->blocks;
    vda->initialized = true;

    if (canonical_avcc == NULL)
    {
        struct hxxx_helper hh;
        hxxx_helper_init(&hh, VLC_OBJECT(dec), VLC_CODEC_H264, true);
        if (hxxx_helper_set_extra(&hh, extra, avcc_size) == VLC_SUCCESS)
            canonical_avcc = h264_helper_get_avcc_config(&hh);
        hxxx_helper_clean(&hh);
    }
    if (canonical_avcc == NULL)
        goto error_initialized;
    msg_Info(dec, "hybrid MVC avcC: %zu bytes (%s parameter sets)",
             canonical_avcc->i_buffer,
             first_block != NULL ? "in-band" : "CodecPrivate");
    if (var_InheritBool(dec, "mvc-vda-dump-base"))
    {
        FILE *raw = fopen("/tmp/powervlc-mvc-extra.bin", "wb");
        if (raw != NULL)
        {
            fwrite(extra, 1, dec->fmt_in.i_extra, raw);
            fclose(raw);
        }
        raw = fopen("/tmp/powervlc-mvc-base.avcc", "wb");
        if (raw != NULL)
        {
            fwrite(canonical_avcc->p_buffer, 1, canonical_avcc->i_buffer, raw);
            fclose(raw);
        }
    }
    if (var_InheritBool(dec, "mvc-vda-dump-base"))
    {
        vda->dump = fopen("/tmp/powervlc-mvc-base.h264", "wb");
        if (vda->dump != NULL)
            MVCVDAWriteAVCCAsAnnexB(vda->dump, canonical_avcc);
    }
    hxxx_helper_init(&vda->hh, VLC_OBJECT(dec), VLC_CODEC_H264, true);
    vda->hh_initialized = true;
    if (hxxx_helper_set_extra(&vda->hh, canonical_avcc->p_buffer,
                              canonical_avcc->i_buffer) != VLC_SUCCESS)
    {
        block_Release(canonical_avcc);
        goto error_initialized;
    }
    vda->avcc = canonical_avcc;
#if defined(MVC_HAVE_VT)
    int create_ret = vda->use_vt ? MVCVTCreateSession(dec)
                                 : MVCVDACreateSession(dec);
#else
    int create_ret = MVCVDACreateSession(dec);
#endif
    if (create_ret != VLC_SUCCESS)
    {
        MVCVDADestroy(sys);
        return VLC_EGENERIC;
    }
    vda->active = true;
    edge264_set_external_base(sys->decoder, 1);
#if defined(MVC_HAVE_VT)
    if (vda->use_vt)
        msg_Info(dec, "using hybrid MVC decoding: VideoToolbox H.264 base "
                 "view + Edge264 dependent view");
    else
#endif
        msg_Info(dec, "using hybrid MVC decoding: VDA H.264 base view + "
                 "Edge264 dependent view");
    return VLC_SUCCESS;

error_initialized:
    MVCVDADestroy(sys);
    return VLC_EGENERIC;
#if !defined(MVC_HAVE_VT)
error:
    dlclose(vda->framework);
    memset(vda, 0, sizeof(*vda));
    return VLC_EGENERIC;
#endif
}

static void MVCVDAFlush(decoder_sys_t *sys)
{
    mvc_vda_t *vda = &sys->vda;
#if defined(MVC_HAVE_VT)
    if (vda->use_vt && vda->vt_session != NULL)
    {
        VTDecompressionSessionFinishDelayedFrames(vda->vt_session);
        VTDecompressionSessionWaitForAsynchronousFrames(vda->vt_session);
    }
    else
#endif
    if (vda->active && vda->session != NULL)
        vda->flush(vda->session, 0);
    if (vda->initialized)
    {
        MVCVDAClearPictures(vda);
        MVCVDAClearOwners(vda);
    }
}

static block_t *MVCBuildBaseSample(const decoder_sys_t *sys,
                                   const block_t *block)
{
    block_t *out = block_Alloc(block->i_buffer + 16);
    if (out == NULL)
        return NULL;
    size_t used = 0;
    bool saw_base_slice = false;
    if (sys->nal_length_size != 0)
    {
        size_t offset = 0;
        while (offset + sys->nal_length_size <= block->i_buffer)
        {
            size_t nal_size = 0;
            size_t prefix = offset;
            for (unsigned i = 0; i < sys->nal_length_size; ++i)
                nal_size = (nal_size << 8) | block->p_buffer[offset++];
            if (nal_size > block->i_buffer - offset)
                break;
            const unsigned type = nal_size != 0
                                ? block->p_buffer[offset] & 0x1f : 0;
            /* A Matroska MVC access unit contains the base AU followed by a
             * subset SPS/PPS/SEI preamble and the dependent slices.  The raw
             * H.264 packetizer hands those portions to VDA separately; do not
             * append the dependent preamble to the base compressed sample. */
            if (type == 15 || type == 20 ||
                (saw_base_slice && type != 1 && type != 5))
                break;
            if (type == 1 || type == 5)
                saw_base_slice = true;
            if (NALBelongsToBaseAVC(block->p_buffer + offset, nal_size))
            {
                size_t bytes = sys->nal_length_size + nal_size;
                memcpy(out->p_buffer + used, block->p_buffer + prefix, bytes);
                used += bytes;
                if (sys->vda.dump != NULL)
                {
                    static const uint8_t startcode[4] = { 0, 0, 0, 1 };
                    fwrite(startcode, 1, 4, sys->vda.dump);
                    fwrite(out->p_buffer + used - nal_size, 1, nal_size,
                           sys->vda.dump);
                }
            }
            offset += nal_size;
        }
    }
    else
    {
        hxxx_iterator_ctx_t it;
        const uint8_t *nal;
        size_t nal_size;
        hxxx_iterator_init(&it, block->p_buffer, block->i_buffer, 0);
        while (hxxx_annexb_iterate_next(&it, &nal, &nal_size))
        {
            const unsigned type = nal_size != 0 ? nal[0] & 0x1f : 0;
            if (type == 15 || type == 20 ||
                (saw_base_slice && type != 1 && type != 5))
                break;
            if (type == 1 || type == 5)
                saw_base_slice = true;
            if (!NALBelongsToBaseAVC(nal, nal_size))
                continue;
            out->p_buffer[used++] = (nal_size >> 24) & 0xff;
            out->p_buffer[used++] = (nal_size >> 16) & 0xff;
            out->p_buffer[used++] = (nal_size >> 8) & 0xff;
            out->p_buffer[used++] = nal_size & 0xff;
            memcpy(out->p_buffer + used, nal, nal_size);
            used += nal_size;
            if (sys->vda.dump != NULL)
            {
                static const uint8_t startcode[4] = { 0, 0, 0, 1 };
                fwrite(startcode, 1, 4, sys->vda.dump);
                fwrite(out->p_buffer + used - nal_size, 1, nal_size,
                       sys->vda.dump);
            }
        }
    }
    out->i_buffer = used;
    if (used == 0)
    {
        block_Release(out);
        return NULL;
    }
    return out;
}

/* Collect every ordinary AVC SPS/PPS from the complete MVC access unit.
 * The dependent preamble carries PPS 1 after the base slices; it must be in
 * VDA's avcC table for later PPS 0 revisions to be accepted, but it must not
 * be appended to the compressed base-picture sample itself. */
static block_t *MVCBuildVDAParameterSets(const decoder_sys_t *sys,
                                         const block_t *block)
{
    block_t *out = block_Alloc(block->i_buffer + 16);
    if (out == NULL)
        return NULL;
    size_t used = 0;
    if (sys->nal_length_size != 0)
    {
        size_t offset = 0;
        while (offset + sys->nal_length_size <= block->i_buffer)
        {
            size_t nal_size = 0;
            size_t prefix = offset;
            for (unsigned i = 0; i < sys->nal_length_size; ++i)
                nal_size = (nal_size << 8) | block->p_buffer[offset++];
            if (nal_size > block->i_buffer - offset)
                break;
            unsigned type = nal_size != 0
                          ? block->p_buffer[offset] & 0x1f : 0;
            if (type == 7 || type == 8)
            {
                size_t bytes = sys->nal_length_size + nal_size;
                memcpy(out->p_buffer + used, block->p_buffer + prefix, bytes);
                used += bytes;
            }
            offset += nal_size;
        }
    }
    else
    {
        hxxx_iterator_ctx_t it;
        const uint8_t *nal;
        size_t nal_size;
        hxxx_iterator_init(&it, block->p_buffer, block->i_buffer, 0);
        while (hxxx_annexb_iterate_next(&it, &nal, &nal_size))
        {
            unsigned type = nal_size != 0 ? nal[0] & 0x1f : 0;
            if (type != 7 && type != 8)
                continue;
            out->p_buffer[used++] = (nal_size >> 24) & 0xff;
            out->p_buffer[used++] = (nal_size >> 16) & 0xff;
            out->p_buffer[used++] = (nal_size >> 8) & 0xff;
            out->p_buffer[used++] = nal_size & 0xff;
            memcpy(out->p_buffer + used, nal, nal_size);
            used += nal_size;
        }
    }
    out->i_buffer = used;
    if (used == 0)
    {
        block_Release(out);
        return NULL;
    }
    return out;
}

static uint64_t MVCVDASubmitBase(decoder_t *dec, const block_t *block)
{
    decoder_sys_t *sys = dec->p_sys;
    mvc_vda_t *vda = &sys->vda;
    if (!vda->active || vda->failed)
        return 0;

    block_t *sets = MVCBuildVDAParameterSets(sys, block);
    if (sets != NULL)
    {
        bool sets_changed = false;
        sets = vda->hh.pf_process_block(&vda->hh, sets, &sets_changed);
        if (sets != NULL)
            block_Release(sets);
        if (sets_changed && MVCVDAUpdateConfiguration(dec) != VLC_SUCCESS)
        {
            vda->failed = true;
            return 0;
        }
    }
    block_t *sample = MVCBuildBaseSample(sys, block);
    if (sample == NULL)
        return 0;

    bool config_changed = false;
    sample = vda->hh.pf_process_block(&vda->hh, sample, &config_changed);
    if (sample == NULL)
        return 0;
    if (config_changed && MVCVDAUpdateConfiguration(dec) != VLC_SUCCESS)
    {
        block_Release(sample);
        vda->failed = true;
        return 0;
    }

    uint64_t serial = ++vda->next_serial;
#if defined(MVC_HAVE_VT)
    if (vda->use_vt)
    {
        CMBlockBufferRef data = NULL;
        CMSampleBufferRef sample_buffer = NULL;
        OSStatus status = CMBlockBufferCreateWithMemoryBlock(
            kCFAllocatorDefault, NULL, sample->i_buffer, kCFAllocatorDefault,
            NULL, 0, sample->i_buffer, 0, &data);
        if (status == noErr)
            status = CMBlockBufferReplaceDataBytes(sample->p_buffer, data, 0,
                                                   sample->i_buffer);
        const size_t sample_size = sample->i_buffer;
        if (status == noErr)
            status = CMSampleBufferCreateReady(kCFAllocatorDefault, data,
                vda->vt_format, 1, 0, NULL, 1, &sample_size, &sample_buffer);
        block_Release(sample);
        if (data != NULL)
            CFRelease(data);
        if (status == noErr)
        {
            VTDecodeInfoFlags flags = 0;
            /* MVC keeps the matching access unit queued until its base image
             * is injected into Edge264. Do not allow the callback to outlive
             * that block (or the BD-J clip transition which destroys this
             * session): asynchronous VideoToolbox delivery otherwise leaves
             * a stale CVPixelBuffer in the serial queue. VideoToolbox still
             * performs the H.264 decode in hardware. */
            status = VTDecompressionSessionDecodeFrame(vda->vt_session,
                sample_buffer, 0,
                (void *)(uintptr_t)serial, &flags);
        }
        if (sample_buffer != NULL)
            CFRelease(sample_buffer);
        if (status != noErr)
        {
            msg_Warn(dec, "hybrid MVC VideoToolbox decode failed (status %d)",
                     (int)status);
            vda->failed = true;
            return 0;
        }
        return serial;
    }
#endif
    int64_t signed_serial = serial;
    CFDataRef data = CFDataCreate(NULL, sample->p_buffer, sample->i_buffer);
    block_Release(sample);
    CFNumberRef number = CFNumberCreate(NULL, kCFNumberSInt64Type,
                                       &signed_serial);
    CFDictionaryRef info = NULL;
    if (data != NULL && number != NULL)
    {
        const void *keys[] = { mvc_vda_serial_key, mvc_vda_data_key };
        const void *values[] = { number, data };
        info = CFDictionaryCreate(NULL, keys, values, 2,
            &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    }
    if (number != NULL) CFRelease(number);
    if (data == NULL || info == NULL)
    {
        if (data != NULL) CFRelease(data);
        if (info != NULL) CFRelease(info);
        return 0;
    }

    OSStatus status = vda->decode(vda->session, 0, data, info);
    CFRelease(data);
    CFRelease(info);
    if (status != kVDADecoderNoErr)
    {
        msg_Warn(dec, "hybrid MVC VDA decode failed (status %d)",
                 (int)status);
        vda->failed = true;
        return 0;
    }
    return serial;
}

static mvc_vda_picture_t *MVCVDATakeImage(decoder_t *dec, uint64_t serial)
{
    decoder_sys_t *sys = dec->p_sys;
    mvc_vda_t *vda = &sys->vda;
    mvc_vda_picture_t *pic = NULL;
    vlc_mutex_lock(&vda->lock);
    mvc_vda_picture_t **link = &vda->pictures;
    while (*link != NULL && (*link)->serial != serial)
        link = &(*link)->next;
    if (*link != NULL)
    {
        pic = *link;
        *link = pic->next;
        pic->next = NULL;
    }
    vlc_mutex_unlock(&vda->lock);
    if (pic != NULL && !vda->reported_format)
    {
        if (pic->nv12 != NULL)
            msg_Info(dec, "hybrid MVC hardware output: NV12 detached, "
                     "%ux%u/%d", pic->width, pic->height,
                     pic->nv12_stride_y);
        else
        {
        CVImageBufferRef image = pic->image;
        OSType format = CVPixelBufferGetPixelFormatType(image);
        size_t planes = CVPixelBufferGetPlaneCount(image);
        if (planes == 3)
            msg_Info(dec, "hybrid MVC hardware output: %4.4s, 3 planes; "
                     "Y %lux%lu/%lu, Cb %lux%lu/%lu, Cr %lux%lu/%lu",
                     (const char *)&format,
                     (unsigned long)CVPixelBufferGetWidthOfPlane(image, 0),
                     (unsigned long)CVPixelBufferGetHeightOfPlane(image, 0),
                     (unsigned long)CVPixelBufferGetBytesPerRowOfPlane(image, 0),
                     (unsigned long)CVPixelBufferGetWidthOfPlane(image, 1),
                     (unsigned long)CVPixelBufferGetHeightOfPlane(image, 1),
                     (unsigned long)CVPixelBufferGetBytesPerRowOfPlane(image, 1),
                     (unsigned long)CVPixelBufferGetWidthOfPlane(image, 2),
                     (unsigned long)CVPixelBufferGetHeightOfPlane(image, 2),
                     (unsigned long)CVPixelBufferGetBytesPerRowOfPlane(image, 2));
        else
            msg_Info(dec, "hybrid MVC hardware output: %4.4s packed, "
                     "%lux%lu/%lu",
                     (const char *)&format,
                     (unsigned long)CVPixelBufferGetWidth(image),
                     (unsigned long)CVPixelBufferGetHeight(image),
                     (unsigned long)CVPixelBufferGetBytesPerRow(image));
        }
        vda->reported_format = true;
    }
    return pic;
}

static int MVCInjectBase(decoder_t *dec, mvc_vda_picture_t *pic)
{
    decoder_sys_t *sys = dec->p_sys;
    if (pic != NULL && pic->nv12 != NULL)
        return edge264_inject_external_base_nv12(sys->decoder,
            pic->nv12_y, pic->nv12_uv, pic->nv12_stride_y,
            pic->nv12_stride_uv) == 0 ? VLC_SUCCESS : VLC_EGENERIC;
    CVImageBufferRef image = pic != NULL ? pic->image : NULL;
    if (image == NULL ||
        CVPixelBufferLockBaseAddress(image, kCVPixelBufferLock_ReadOnly) != 0)
        return VLC_EGENERIC;
    const uint8_t *planes[3];
    int strides[3];
    unsigned widths[3], heights[3];
    const size_t plane_count = CVPixelBufferGetPlaneCount(image);
    if (plane_count == 3)
    {
        for (unsigned i = 0; i < 3; ++i)
        {
            planes[i] = CVPixelBufferGetBaseAddressOfPlane(image, i);
            strides[i] = (int)CVPixelBufferGetBytesPerRowOfPlane(image, i);
            widths[i] = (unsigned)CVPixelBufferGetWidthOfPlane(image, i);
            heights[i] = (unsigned)CVPixelBufferGetHeightOfPlane(image, i);
        }
    }
    else if (plane_count == 2 &&
             CVPixelBufferGetPixelFormatType(image) ==
                 kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange)
    {
        const uint8_t *src_y = CVPixelBufferGetBaseAddressOfPlane(image, 0);
        const uint8_t *src_uv = CVPixelBufferGetBaseAddressOfPlane(image, 1);
        int ret = edge264_inject_external_base_nv12(
            sys->decoder, src_y, src_uv,
            (int)CVPixelBufferGetBytesPerRowOfPlane(image, 0),
            (int)CVPixelBufferGetBytesPerRowOfPlane(image, 1));
        if (ret == 0)
            MVCVDAStoreOwner(sys,
                edge264_get_last_external_base_frame_id(sys->decoder), image);
        CVPixelBufferUnlockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
        return ret == 0 ? VLC_SUCCESS : VLC_EGENERIC;
    }
    else if (CVPixelBufferGetPixelFormatType(image) ==
             kCVPixelFormatType_422YpCbCr8)
    {
        const unsigned width = (unsigned)CVPixelBufferGetWidth(image);
        const unsigned height = (unsigned)CVPixelBufferGetHeight(image);
        if ((width & 1) || (height & 1))
            goto conversion_error;
        const uint8_t *packed = CVPixelBufferGetBaseAddress(image);
        const size_t packed_stride = CVPixelBufferGetBytesPerRow(image);
        int ret = edge264_inject_external_base_uyvy(
            sys->decoder, packed, (int)packed_stride);
        if (ret == 0)
            MVCVDAStoreOwner(sys,
                edge264_get_last_external_base_frame_id(sys->decoder), image);
        CVPixelBufferUnlockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
        return ret == 0 ? VLC_SUCCESS : VLC_EGENERIC;
    }
    else
        goto conversion_error;
    if (sys->vda.dump != NULL && !sys->vda.dumped_image &&
        ++sys->vda.dump_image_count >= 24)
    {
        FILE *raw = fopen("/tmp/powervlc-vda-first-frame.yuv", "wb");
        if (raw != NULL)
        {
            for (unsigned plane = 0; plane < 3; ++plane)
            {
                const uint8_t *line = planes[plane];
                const size_t width = widths[plane];
                const size_t height = heights[plane];
                for (size_t y = 0; y < height; ++y)
                {
                    fwrite(line, 1, width, raw);
                    line += strides[plane];
                }
            }
            fclose(raw);
        }
        sys->vda.dumped_image = true;
    }
    if (!sys->have_injected_hash)
    {
        for (unsigned i = 0; i < 3; ++i)
            sys->injected_hash[i] = MVCHashPlane(planes[i], strides[i],
                widths[i], heights[i]);
        sys->have_injected_hash = true;
    }
    int ret = edge264_inject_external_base(sys->decoder, planes, strides);
    if (ret == 0)
        MVCVDAStoreOwner(sys,
            edge264_get_last_external_base_frame_id(sys->decoder), image);
    CVPixelBufferUnlockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
    return ret == 0 ? VLC_SUCCESS : VLC_EGENERIC;

conversion_error:
    CVPixelBufferUnlockBaseAddress(image, kCVPixelBufferLock_ReadOnly);
    return VLC_EGENERIC;
}
#endif

static bool NALIsBasePicture(const uint8_t *nal, size_t size)
{
    return size > 0 && ((nal[0] & 0x1f) == 1 || (nal[0] & 0x1f) == 5);
}

static bool NALIsDependentPicture(const uint8_t *nal, size_t size)
{
    return size > 0 && (nal[0] & 0x1f) == 20;
}

static bool BlockHasBasePicture(const decoder_sys_t *sys, const block_t *block)
{
    if (sys->nal_length_size != 0)
    {
        size_t offset = 0;
        while (offset + sys->nal_length_size <= block->i_buffer)
        {
            size_t nal_size = 0;
            for (unsigned i = 0; i < sys->nal_length_size; ++i)
                nal_size = (nal_size << 8) | block->p_buffer[offset++];
            if (nal_size > block->i_buffer - offset)
                return false;
            if (NALIsBasePicture(block->p_buffer + offset, nal_size))
                return true;
            offset += nal_size;
        }
        return false;
    }

    hxxx_iterator_ctx_t it;
    const uint8_t *nal;
    size_t size;
    hxxx_iterator_init(&it, block->p_buffer, block->i_buffer, 0);
    while (hxxx_annexb_iterate_next(&it, &nal, &size))
    {
        if (NALIsBasePicture(nal, size))
            return true;
    }
    return false;
}

static int FeedNAL(decoder_t *dec, const uint8_t *nal, size_t size)
{
    decoder_sys_t *sys = dec->p_sys;
    uint8_t *owned = malloc(MVC_NAL_PREFIX_PADDING + size + MVC_NAL_PADDING);
    if (owned == NULL)
        return VLC_ENOMEM;

    /* Edge264's vectorized bit reader may inspect the two bytes immediately
     * before the NAL while checking emulation-prevention sequences. Keep them
     * non-zero, as well as supplying its documented end padding. */
    memset(owned, 0xff, MVC_NAL_PREFIX_PADDING);
    uint8_t *payload = owned + MVC_NAL_PREFIX_PADDING;
    memcpy(payload, nal, size);
    memset(payload + size, 0, MVC_NAL_PADDING);

    int ret = edge264_decode_NAL(sys->decoder, payload, payload + size,
                                 ReleaseNAL, owned);
    if (ret != 0)
    {
        /* Edge264 only takes ownership after successfully queueing a NAL. */
        free(owned);
        if (ret != ENOBUFS && ret != ENOTSUP && ret != EBADMSG &&
            ret != ENODATA)
            msg_Warn(dec, "Edge264 rejected a NAL: %s", vlc_strerror_c(ret));
    }
    return ret;
}

static int FeedNALWithBackpressure(decoder_t *dec, const uint8_t *nal,
                                   size_t size)
{
    decoder_sys_t *sys = dec->p_sys;

    /* ENOBUFS is Edge264's flow-control result: the exact same NAL must be
     * submitted again after completed stereo pairs have returned their DPB
     * slots. In worker mode the last pair may still be deblocking, so yield
     * briefly instead of dropping the NAL and permanently desynchronizing the
     * base and dependent views. */
    for (unsigned retry = 0; retry < 10; ++retry)
    {
        int ret = FeedNAL(dec, nal, size);
        if (ret != ENOBUFS)
            return ret;

        if (QueueFrames(dec) != VLCDEC_SUCCESS)
            return ENOMEM;

        if (!edge264_is_frame_ready(sys->decoder))
            mwait(mdate() + VLC_TICK_FROM_MS(10));
    }

    /* At a Blu-ray play-item boundary the base M2TS can end a few packets
     * before its MVC extension. Edge264 then quite correctly retains an
     * incomplete access unit, but there can never be a stereo picture to
     * dequeue and release its DPB slot. Waiting a full second here made every
     * BD-J trailer/menu transition visibly freeze and ultimately forced VLC
     * to destroy the decoder as "critical".
     *
     * A genuine worker backlog clears in a few milliseconds. After 100 ms
     * with no complete pair, emit the already-copied reorder tail, discard the
     * unmatched access unit, and keep the decoder ready for the next IDR. The
     * rejected NAL is intentionally reported as EAGAIN: callers skip it but do
     * not tear down the vout or its HDMI mode. */
    msg_Warn(dec, "resetting an incomplete MVC access unit after a 100 ms "
             "buffer stall");
    DrainPendingPictures(dec);
    edge264_flush(sys->decoder);
    DatesReset(sys);
    sys->warned_missing_view = false;
    sys->reported_stereo = false;
    return EAGAIN;
}

/* Parse an AVCDecoderConfigurationRecord. MVC Matroska files append an mvcC
 * box whose payload is another record of this shape, containing subset SPS
 * and the dependent-view parameter sets. */
static int FeedConfigurationRecord(decoder_t *dec, const uint8_t *p,
                                   size_t size, bool set_length_size)
{
    decoder_sys_t *sys = dec->p_sys;
    if (size < 7 || p[0] != 1)
        return EINVAL;

    if (set_length_size)
        sys->nal_length_size = (p[4] & 0x03) + 1;

    p += 5;
    size -= 5;
    for (unsigned array = 0; array < 2; ++array)
    {
        if (size < 1)
            return EINVAL;
        const unsigned count = *p++ & (array == 0 ? 0x1f : 0xff);
        size--;
        for (unsigned i = 0; i < count; ++i)
        {
            if (size < 2)
                return EINVAL;
            const size_t nal_size = (size_t)p[0] << 8 | p[1];
            p += 2;
            size -= 2;
            if (nal_size > size)
                return EINVAL;
            if (nal_size != 0 &&
                FeedNALWithBackpressure(dec, p, nal_size) == ENOMEM)
                return ENOMEM;
            p += nal_size;
            size -= nal_size;
        }
    }
    return 0;
}

static int FeedDecoderConfiguration(decoder_t *dec)
{
    const uint8_t *extra = dec->fmt_in.p_extra;
    const size_t extra_size = dec->fmt_in.i_extra;
    if (extra == NULL || extra_size == 0)
        return 0; /* Blu-ray parameter sets arrive in-band. */

    if (extra[0] != 1)
    {
        hxxx_iterator_ctx_t it;
        const uint8_t *nal;
        size_t size;
        hxxx_iterator_init(&it, extra, extra_size, 0);
        while (hxxx_annexb_iterate_next(&it, &nal, &size))
            if (size != 0 && FeedNALWithBackpressure(dec, nal, size) == ENOMEM)
                return ENOMEM;
        return 0;
    }

    int ret = FeedConfigurationRecord(dec, extra, extra_size, true);
    if (ret != 0)
        return ret;

    bool found_mvcc = false;
    for (size_t i = 4; i + 4 <= extra_size; ++i)
    {
        if (memcmp(extra + i, "mvcC", 4))
            continue;
        const uint32_t box_size = (uint32_t)extra[i - 4] << 24 |
                                  (uint32_t)extra[i - 3] << 16 |
                                  (uint32_t)extra[i - 2] << 8  |
                                  (uint32_t)extra[i - 1];
        size_t payload_size;
        if (box_size >= 4 && box_size <= extra_size - i)
            payload_size = box_size - 4; /* Matroska/mkvmerge convention */
        else if (box_size >= 8 && box_size <= extra_size - (i - 4))
            payload_size = box_size - 8; /* regular ISO box size */
        else
            continue;
        ret = FeedConfigurationRecord(dec, extra + i + 4,
                                      payload_size, false);
        if (ret != 0)
            return ret;
        found_mvcc = true;
        break;
    }

    if (!found_mvcc)
        msg_Dbg(dec, "AVC configuration has no mvcC box; expecting in-band MVC sets");
    return 0;
}

static int Decode(decoder_t *dec, block_t *block)
{
    decoder_sys_t *sys = dec->p_sys;

#if defined(MVC_HAVE_VDA)
    mvc_vda_t *vda = &sys->vda;
    if (vda->requested && !vda->initialized && block != NULL)
    {
        if (MVCVDAOpen(dec, block) != VLC_SUCCESS)
        {
            vda->requested = false;
            msg_Dbg(dec, "hybrid MVC VDA unavailable; using Edge264 for both views");
        }
    }
    if (vda->active && !vda->processing_block)
    {
        const bool draining = block == NULL;
        if (block != NULL && (block->i_flags & BLOCK_FLAG_DISCONTINUITY))
        {
            MVCVDAClearBlocks(vda);
            MVCVDAFlush(sys);
            edge264_flush(sys->decoder);
            ClearPendingPictures(sys);
            DatesReset(sys);
            sys->warned_missing_view = false;
            sys->reported_stereo = false;
            block->i_flags &= ~BLOCK_FLAG_DISCONTINUITY;
        }

        if (draining)
        {
#if defined(MVC_HAVE_VT)
            if (vda->use_vt)
            {
                VTDecompressionSessionFinishDelayedFrames(vda->vt_session);
                VTDecompressionSessionWaitForAsynchronousFrames(
                    vda->vt_session);
            }
            else
#endif
                vda->flush(vda->session, kVDADecoderFlush_EmitFrames);
        }
        else
        {
            mvc_vda_block_t *entry = malloc(sizeof(*entry));
            uint64_t serial = BlockHasBasePicture(sys, block)
                            ? MVCVDASubmitBase(dec, block) : 0;
            if (entry == NULL || (serial == 0 &&
                                  BlockHasBasePicture(sys, block)))
            {
                free(entry);
                msg_Warn(dec, "hybrid MVC queue failed; switching to "
                         "two-view Edge264 decoding");
                vda->active = false;
                vda->failed = true;
                edge264_set_external_base(sys->decoder, 0);
                MVCVDAFlush(sys);
                MVCVDAClearBlocks(vda);
                return Decode(dec, block);
            }
            entry->block = block;
            entry->serial = serial;
            entry->queued_at = mdate();
            entry->next = NULL;
            *vda->blocks_tail = entry;
            vda->blocks_tail = &entry->next;
        }

        int result = VLCDEC_SUCCESS;
        while (vda->active && vda->blocks != NULL)
        {
            mvc_vda_block_t *entry = vda->blocks;
            mvc_vda_picture_t *picture = entry->serial != 0
                ? MVCVDATakeImage(dec, entry->serial) : NULL;
            if (entry->serial != 0 && picture == NULL)
                break;
            vda->blocks = entry->next;
            if (vda->blocks == NULL)
                vda->blocks_tail = &vda->blocks;
            block_t *queued = entry->block;
            vlc_tick_t queued_at = entry->queued_at;
            uint64_t serial = entry->serial;
            free(entry);

            vda->processing_block = true;
            vda->processing_picture = picture;
            vlc_tick_t processing_at = mdate();
            result = Decode(dec, queued);
            vlc_tick_t processed_at = mdate();
            vda->processing_picture = NULL;
            vda->processing_block = false;
            if (vda->timing_samples++ < 24)
                msg_Dbg(dec, "hybrid MVC timing #%"PRIu64": VDA/queue %"PRId64
                        " us, Edge %"PRId64" us", serial,
                        processing_at - queued_at,
                        processed_at - processing_at);
            if (result != VLCDEC_SUCCESS)
                break;
        }
        /* A failed hardware/Edge264 hand-off is recoverable. The nested
         * Decode() switches Edge264 back to ordinary two-view mode; preserve
         * input ordering by feeding every hardware-queued access unit through
         * that mode before accepting the next block from the core. */
        while (!vda->active && result == VLCDEC_SUCCESS &&
               vda->blocks != NULL)
        {
            mvc_vda_block_t *entry = vda->blocks;
            vda->blocks = entry->next;
            if (vda->blocks == NULL)
                vda->blocks_tail = &vda->blocks;
            block_t *queued = entry->block;
            free(entry);
            result = Decode(dec, queued);
        }
        if (draining && result == VLCDEC_SUCCESS && vda->blocks == NULL)
        {
            vda->processing_block = true;
            result = Decode(dec, NULL);
            vda->processing_block = false;
        }
        return result;
    }
#endif

    if (block == NULL)
    {
        edge264_bump_frames(sys->decoder);
        int ret = QueueFrames(dec);
        if (ret == VLCDEC_SUCCESS)
            DrainPendingPictures(dec);
        return ret;
    }
    if (block->i_flags & BLOCK_FLAG_CORRUPTED)
    {
        block_Release(block);
        return VLCDEC_SUCCESS;
    }
    if (block->i_flags & BLOCK_FLAG_DISCONTINUITY)
    {
        edge264_flush(sys->decoder);
        ClearPendingPictures(sys);
        DatesReset(sys);
        sys->warned_missing_view = false;
        sys->reported_stereo = false;
        /* The block carrying the marker is the first base/dependent pair
         * whose timestamps agree after a Blu-ray seek or a dropped access
         * unit. It may itself be the next IDR, so feed it after the flush
         * instead of unconditionally throwing away the recovery point. */
    }

    const vlc_tick_t block_date = block->i_pts != VLC_TICK_INVALID
                                ? block->i_pts : block->i_dts;
#if defined(MVC_HAVE_VDA)
    const bool has_base = BlockHasBasePicture(sys, block);
    mvc_vda_picture_t *vda_base = sys->vda.active && vda->processing_block
                                ? vda->processing_picture : NULL;
    bool vda_injected = false;
    if (has_base && sys->vda.active && vda_base == NULL)
    {
        /* Failure happens before Edge264 has consumed this access unit, so
         * switching it back to ordinary two-view decoding loses no picture. */
        msg_Warn(dec, "disabling hybrid MVC decode; continuing with Edge264 "
                 "for both views");
        sys->vda.active = false;
        sys->vda.failed = true;
        edge264_set_external_base(sys->decoder, 0);
        MVCVDAFlush(sys);
    }
#endif
    edge264_set_timestamp(sys->decoder, block_date);
    if (BlockHasBasePicture(sys, block))
        DatePush(sys, block_date);

    if (sys->nal_length_size != 0)
    {
        size_t offset = 0;
        while (offset + sys->nal_length_size <= block->i_buffer)
        {
            size_t size = 0;
            for (unsigned i = 0; i < sys->nal_length_size; ++i)
                size = (size << 8) | block->p_buffer[offset++];
            if (size > block->i_buffer - offset)
            {
                msg_Warn(dec, "truncated MVC AVC sample");
                break;
            }
#if defined(MVC_HAVE_VDA)
            if (vda_base != NULL && !vda_injected &&
                NALIsDependentPicture(block->p_buffer + offset, size))
            {
                if (MVCInjectBase(dec, vda_base) != VLC_SUCCESS)
                    return MVCFallbackAfterInjectionFailure(dec, block,
                                                            vda_base);
                vda_injected = true;
            }
#endif
            int ret = size != 0 ? FeedNALWithBackpressure(dec,
                                      block->p_buffer + offset, size) : 0;
            if (ret == EAGAIN)
            {
#if defined(MVC_HAVE_VDA)
                if (vda_base != NULL)
                {
                    sys->vda.processing_picture = NULL;
                    MVCHardwarePictureDelete(vda_base);
                }
#endif
                block_Release(block);
                return VLCDEC_SUCCESS;
            }
            if (ret == ENOMEM || ret == ENOBUFS ||
                QueueFrames(dec) != VLCDEC_SUCCESS)
            {
                block_Release(block);
                return VLCDEC_ECRITICAL;
            }
            offset += size;
        }
    }
    else
    {
        hxxx_iterator_ctx_t it;
        const uint8_t *nal;
        size_t size;
        hxxx_iterator_init(&it, block->p_buffer, block->i_buffer, 0);
        while (hxxx_annexb_iterate_next(&it, &nal, &size))
        {
#if defined(MVC_HAVE_VDA)
            if (vda_base != NULL && !vda_injected &&
                NALIsDependentPicture(nal, size))
            {
                if (MVCInjectBase(dec, vda_base) != VLC_SUCCESS)
                    return MVCFallbackAfterInjectionFailure(dec, block,
                                                            vda_base);
                vda_injected = true;
            }
#endif
            int ret = FeedNALWithBackpressure(dec, nal, size);
            if (ret == EAGAIN)
            {
#if defined(MVC_HAVE_VDA)
                if (vda_base != NULL)
                {
                    sys->vda.processing_picture = NULL;
                    MVCHardwarePictureDelete(vda_base);
                }
#endif
                block_Release(block);
                return VLCDEC_SUCCESS;
            }
            if (ret == ENOMEM || ret == ENOBUFS ||
                QueueFrames(dec) != VLCDEC_SUCCESS)
            {
                block_Release(block);
                return VLCDEC_ECRITICAL;
            }
        }
    }

#if defined(MVC_HAVE_VDA)
    if (vda_base != NULL)
        MVCHardwarePictureDelete(vda_base);
#endif
    block_Release(block);
    return VLCDEC_SUCCESS;
}

static void Flush(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    edge264_flush(sys->decoder);
    ClearPendingPictures(sys);
    DatesReset(sys);
    sys->warned_missing_view = false;
    sys->reported_stereo = false;
#if defined(MVC_HAVE_VDA)
    MVCVDAFlush(sys);
#endif
}

static int OpenDecoder(vlc_object_t *obj)
{
    decoder_t *dec = (decoder_t *)obj;
    if (dec->fmt_in.i_codec != VLC_CODEC_H264_MVC)
        return VLC_EGENERIC;

    decoder_sys_t *sys = vlc_obj_calloc(obj, 1, sizeof(*sys));
    if (sys == NULL)
        return VLC_ENOMEM;

#if defined(MVC_HAVE_VDA)
    const bool use_apple_base_accel =
        dd_gate_read("/tmp/vda_hybrid_3d_mvc") > 0;
#endif

    int threads = var_InheritInteger(obj, "mvc-threads");
    if (threads < 0)
    {
        /* Edge264's own -1 auto mode records -1 in the decoder before it
         * resolves the CPU count. Besides oversubscribing presentation on
         * high-core-count machines, that sentinel breaks its worker teardown.
         * Resolve it here and retain one core for demux, audio and the vout.
         * Four workers is also the measured throughput/stability optimum for
         * two 1080p MVC views on Apple Silicon. */
        unsigned cpus = vlc_GetCPUCount();
        /* On a dual-core Core 2 Duo, reserving one entire core makes two-view
         * 1080p MVC fall below real time.  Edge264's caller thread mostly
         * feeds workers and the audio/vout load is light, so use both cores
         * there.  Keep the one-core reserve on wider machines. */
        threads = (int)__MIN(cpus <= 2 ? cpus : cpus - 1, 4);
#if defined(MVC_HAVE_VDA)
        /* Once output assembly avoids clearing the complete 1920x2160 frame
         * before overwriting it, three workers gives the best measured VDA +
         * dependent-view overlap on the dual-core GeForce 320M MacBook.
         * Four oversubscribes it, while one and two leave VDA queue bubbles. */
        if (cpus <= 2 && use_apple_base_accel)
            threads = 3;
#endif
    }
    sys->reorder_depth = threads == 0 ? 0 : MVC_REORDER_DEPTH;
    sys->direct_output = var_InheritBool(obj, "mvc-direct-output");
    sys->output_delay = VLC_TICK_FROM_MS(
        var_InheritInteger(obj, "mvc-output-delay"));
    /* The optimized contrib intentionally omits Edge264's very expensive
     * per-NAL trace build; a non-NULL callback makes that build reject the
     * allocation. VLC reports decoder errors through its own messages. */
    sys->decoder = edge264_alloc(threads, NULL, NULL, 0,
                                 NULL, NULL, NULL);
    if (sys->decoder == NULL)
    {
        msg_Err(dec, "cannot initialize the Edge264 MVC decoder");
        return VLC_EGENERIC;
    }

    dec->p_sys = sys;
    int config_ret = FeedDecoderConfiguration(dec);
    if (config_ret != 0)
    {
        msg_Err(dec, "invalid MVC decoder configuration: %s",
                vlc_strerror_c(config_ret));
        edge264_free(&sys->decoder);
        return VLC_EGENERIC;
    }

#if defined(MVC_HAVE_VDA)
    sys->vda.requested = use_apple_base_accel;
    if (use_apple_base_accel)
        msg_Warn(dec, "experimental hybrid Apple MVC base-view decoder "
                 "enabled by /tmp/vda_hybrid_3d_mvc");
    else
        msg_Info(dec, "using Edge264 for both MVC views");
#endif

    dec->pf_decode = Decode;
    dec->pf_flush = Flush;
    dec->fmt_out.i_cat = VIDEO_ES;
    dec->fmt_out.i_codec = VLC_CODEC_I420;
    dec->i_extra_picture_buffers = 4;
#if defined(__APPLE__) && defined(__aarch64__)
    /* A BD-J state change can hold bd_read_ext() for roughly 2.6 seconds.
     * The ordinary disc cache is shorter, so both MVC views and the
     * interleaved passthrough audio drain together while the Java menu is
     * busy. Request the core's documented decoder lead floor once MVC is
     * actually selected; unlike DEMUX_GET_PTS_DELAY this happens after the
     * stereoscopic sub-path is known and updates the active input clock. */
    dec->i_min_pts_delay = VLC_TICK_FROM_MS(3000);
#endif

    /* The resume controller runs before the video output is necessarily
     * constructed.  Publish the pending MVC presentation here so it cannot
     * draw its choice into the ordinary window while the legacy display
     * transaction is about to begin.  The macOS vout clears the flag after
     * the HDMI fullscreen presentation is stable. */
    var_Create(dec->obj.libvlc, "stereo3d-display-transition", VLC_VAR_BOOL);
    var_SetBool(dec->obj.libvlc, "stereo3d-display-transition", true);

    /* MVC Matroska and Blu-ray signal the base-view dimensions before the
     * first access unit. Publish the stacked output now, before MVCVDAOpen()
     * creates an IOAccelerator decoder session. On Snow Leopard/NVIDIA a VDA
     * session created on the ordinary desktop and carried across the private
     * 1920x2205 Quartz transaction remains functional but is throttled to
     * roughly half real time. Creating it after the final topology avoids
     * that stale accelerator binding. */
    unsigned width = dec->fmt_in.video.i_visible_width != 0
                   ? dec->fmt_in.video.i_visible_width
                   : dec->fmt_in.video.i_width;
    unsigned height = dec->fmt_in.video.i_visible_height != 0
                    ? dec->fmt_in.video.i_visible_height
                    : dec->fmt_in.video.i_height;
    if (width != 0 && height != 0)
    {
        video_format_Setup(&dec->fmt_out.video, VLC_CODEC_I420,
                           width, height * 2, width, height * 2, 2, 1);
        dec->fmt_out.i_codec = VLC_CODEC_I420;
        dec->fmt_out.video.multiview_mode = MULTIVIEW_STEREO_FRAMEPACKED;
        dec->fmt_out.video.primaries = dec->fmt_in.video.primaries;
        dec->fmt_out.video.transfer = dec->fmt_in.video.transfer;
        dec->fmt_out.video.space = dec->fmt_in.video.space;
        dec->fmt_out.video.b_color_range_full =
            dec->fmt_in.video.b_color_range_full;
        dec->fmt_out.video.i_frame_rate = dec->fmt_in.video.i_frame_rate;
        dec->fmt_out.video.i_frame_rate_base =
            dec->fmt_in.video.i_frame_rate_base;
        if (decoder_UpdateVideoFormat(dec) != VLC_SUCCESS)
        {
            msg_Err(dec, "could not initialize the MVC video output before "
                    "the hardware decoder");
            edge264_free(&sys->decoder);
            var_SetBool(dec->obj.libvlc, "stereo3d-display-transition", false);
            return VLC_EGENERIC;
        }
    }

    msg_Info(dec, "using Edge264 MVC decoder (%d %s)", threads,
             threads == 0 ? "synchronous threads" : "worker threads");
    return VLC_SUCCESS;
}

static void CloseDecoder(vlc_object_t *obj)
{
    decoder_t *dec = (decoder_t *)obj;
    decoder_sys_t *sys = dec->p_sys;
    var_SetBool(dec->obj.libvlc, "stereo3d-display-transition", false);
    ClearPendingPictures(sys);
#if defined(MVC_HAVE_VDA)
    MVCVDADestroy(sys);
    free(sys->vda_i420);
#endif
    edge264_free(&sys->decoder);
}
