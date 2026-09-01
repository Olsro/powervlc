/*****************************************************************************
 * mfx_mvc.c: Intel Media SDK hardware H.264/MVC decoder for Windows
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#define COBJMACROS

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_codec.h>
#include <vlc_picture.h>

#include <windows.h>
#include <d3d11.h>
#include <mfx/mfxvideo.h>
#include <mfx/mfxmvc.h>

#define MVC_API_MAX_MINOR 35
#define MVC_MAX_SURFACES 64
#define MVC_MAX_PENDING_VIEWS 24

typedef struct
{
    mfxFrameSurface1 surface;
    uint8_t *allocation;
} mvc_surface_t;

typedef struct mvc_view_t
{
    struct mvc_view_t *next;
    uint8_t *y;
    uint8_t *uv;
    unsigned width;
    unsigned height;
    mfxU32 frame_order;
    vlc_tick_t date;
} mvc_view_t;

struct decoder_sys_t
{
    mfxSession session;
    mfxIMPL impl;
    mfxVersion version;
    ID3D11Device *device;
    ID3D11DeviceContext *context;
    mfxVideoParam params;
    mfxExtMVCSeqDesc mvc;
    mfxExtBuffer *ext[1];
    bool decoder_ready;
    mvc_surface_t surfaces[MVC_MAX_SURFACES];
    unsigned surface_count;
    uint8_t *stream;
    size_t stream_len;
    size_t stream_capacity;
    vlc_tick_t stream_date;
    uint8_t nal_length_size;
    mvc_view_t *base_head;
    mvc_view_t *base_tail;
    mvc_view_t *dependent_head;
    mvc_view_t *dependent_tail;
    unsigned base_count;
    unsigned dependent_count;
    bool base_is_right;
    bool abort_to_software;
    uint64_t pair_count;
};

static int OpenDecoder(vlc_object_t *);
static void CloseDecoder(vlc_object_t *);

vlc_module_begin()
    set_shortname("Intel MVC")
    set_description(N_("Intel Media SDK hardware MVC decoder"))
    set_capability("video decoder", 10060)
    set_callbacks(OpenDecoder, CloseDecoder)
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_VCODEC)
vlc_module_end()

static bool IsHardwareImplementation(mfxIMPL impl)
{
    const mfxIMPL base = impl & 0x0f;
    return base >= MFX_IMPL_HARDWARE && base <= MFX_IMPL_HARDWARE4;
}

static int OpenHardwareSession(decoder_t *dec, decoder_sys_t *sys)
{
    const D3D_FEATURE_LEVEL levels[] = {
        D3D_FEATURE_LEVEL_11_0, D3D_FEATURE_LEVEL_10_1,
        D3D_FEATURE_LEVEL_10_0,
    };
    D3D_FEATURE_LEVEL selected;
    HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL,
                                   D3D11_CREATE_DEVICE_BGRA_SUPPORT,
                                   levels, ARRAY_SIZE(levels),
                                   D3D11_SDK_VERSION, &sys->device, &selected,
                                   &sys->context);
    if (FAILED(hr))
    {
        msg_Warn(dec, "cannot create the Intel D3D11 decode device (0x%lx)",
                 hr);
        return VLC_EGENERIC;
    }

    /* Kodi's old manual "MFX level" is the requested API minor version.
     * Probe from the newest 1.x ABI downwards and accept hardware only. */
    for (int minor = MVC_API_MAX_MINOR; minor >= 0; --minor)
    {
        mfxVersion requested = { 0 };
        requested.Minor = minor;
        requested.Major = 1;
        mfxSession session = NULL;
        mfxStatus status = MFXInit(MFX_IMPL_HARDWARE | MFX_IMPL_VIA_D3D11,
                                   &requested, &session);
        if (status < MFX_ERR_NONE || session == NULL)
            continue;
        mfxIMPL impl = 0;
        mfxVersion actual = { 0 };
        if (MFXQueryIMPL(session, &impl) < MFX_ERR_NONE ||
            MFXQueryVersion(session, &actual) < MFX_ERR_NONE ||
            !IsHardwareImplementation(impl))
        {
            MFXClose(session);
            continue;
        }
        /* The Ivy Bridge 1.11 runtime creates its own D3D11 device and returns
         * MFX_ERR_UNDEFINED_BEHAVIOR when an application tries to replace it.
         * System-memory output does not require an external handle. Newer
         * runtimes that accept the handle can still use it. */
        status = MFXVideoCORE_SetHandle(session, MFX_HANDLE_D3D11_DEVICE,
                                        (mfxHDL)sys->device);
        sys->session = session;
        sys->impl = impl;
        sys->version = actual;
        msg_Info(dec, "Intel Media SDK hardware session: requested 1.%d, "
                 "runtime %u.%u, implementation 0x%x, D3D feature level "
                 "0x%x, SetHandle %d", minor, actual.Major, actual.Minor,
                 impl, selected, status);
        return VLC_SUCCESS;
    }
    msg_Warn(dec, "Intel Media SDK exposes no usable D3D11 hardware session");
    return VLC_EGENERIC;
}

static int StreamReserve(decoder_sys_t *sys, size_t extra)
{
    if (extra > SIZE_MAX - sys->stream_len)
        return VLC_ENOMEM;
    const size_t needed = sys->stream_len + extra;
    if (needed <= sys->stream_capacity)
        return VLC_SUCCESS;
    size_t capacity = sys->stream_capacity ? sys->stream_capacity : 65536;
    while (capacity < needed)
        capacity = capacity > SIZE_MAX / 2 ? needed : capacity * 2;
    uint8_t *stream = realloc(sys->stream, capacity);
    if (stream == NULL)
        return VLC_ENOMEM;
    sys->stream = stream;
    sys->stream_capacity = capacity;
    return VLC_SUCCESS;
}

static int StreamAppend(decoder_sys_t *sys, const void *data, size_t size)
{
    if (StreamReserve(sys, size) != VLC_SUCCESS)
        return VLC_ENOMEM;
    memcpy(sys->stream + sys->stream_len, data, size);
    sys->stream_len += size;
    return VLC_SUCCESS;
}

static int AppendNAL(decoder_sys_t *sys, const uint8_t *nal, size_t size)
{
    static const uint8_t start_code[4] = { 0, 0, 0, 1 };
    if (StreamAppend(sys, start_code, sizeof(start_code)) != VLC_SUCCESS ||
        StreamAppend(sys, nal, size) != VLC_SUCCESS)
        return VLC_ENOMEM;
    return VLC_SUCCESS;
}

static int AppendConfigurationRecord(decoder_sys_t *sys, const uint8_t *p,
                                     size_t size, bool set_length_size)
{
    if (size < 7 || p[0] != 1)
        return VLC_EGENERIC;
    if (set_length_size)
        sys->nal_length_size = (p[4] & 3) + 1;
    p += 5;
    size -= 5;
    for (unsigned array = 0; array < 2; ++array)
    {
        if (size < 1)
            return VLC_EGENERIC;
        unsigned count = *p++ & (array == 0 ? 0x1f : 0xff);
        size--;
        while (count-- != 0)
        {
            if (size < 2)
                return VLC_EGENERIC;
            size_t nal_size = (size_t)p[0] << 8 | p[1];
            p += 2;
            size -= 2;
            if (nal_size > size || AppendNAL(sys, p, nal_size) != VLC_SUCCESS)
                return VLC_EGENERIC;
            p += nal_size;
            size -= nal_size;
        }
    }
    return VLC_SUCCESS;
}

static int AppendDecoderConfiguration(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    const uint8_t *extra = dec->fmt_in.p_extra;
    size_t extra_size = dec->fmt_in.i_extra;
    if (extra == NULL || extra_size == 0)
        return VLC_SUCCESS;
    if (extra[0] != 1)
        return StreamAppend(sys, extra, extra_size);
    if (AppendConfigurationRecord(sys, extra, extra_size, true) != VLC_SUCCESS)
        return VLC_EGENERIC;
    for (size_t i = 4; i + 4 <= extra_size; ++i)
    {
        if (memcmp(extra + i, "mvcC", 4) != 0)
            continue;
        uint32_t box_size = (uint32_t)extra[i - 4] << 24 |
                            (uint32_t)extra[i - 3] << 16 |
                            (uint32_t)extra[i - 2] << 8 | extra[i - 1];
        size_t payload_size;
        if (box_size >= 4 && box_size <= extra_size - i)
            payload_size = box_size - 4;
        else if (box_size >= 8 && box_size <= extra_size - (i - 4))
            payload_size = box_size - 8;
        else
            continue;
        return AppendConfigurationRecord(sys, extra + i + 4,
                                         payload_size, false);
    }
    return VLC_SUCCESS;
}

static int AppendBlock(decoder_sys_t *sys, const block_t *block)
{
    if (sys->nal_length_size == 0)
        return StreamAppend(sys, block->p_buffer, block->i_buffer);
    size_t offset = 0;
    while (offset + sys->nal_length_size <= block->i_buffer)
    {
        size_t size = 0;
        for (unsigned i = 0; i < sys->nal_length_size; ++i)
            size = (size << 8) | block->p_buffer[offset++];
        if (size > block->i_buffer - offset)
            return VLC_EGENERIC;
        if (AppendNAL(sys, block->p_buffer + offset, size) != VLC_SUCCESS)
            return VLC_ENOMEM;
        offset += size;
    }
    return VLC_SUCCESS;
}

static void FreeMVCDescription(mfxExtMVCSeqDesc *mvc)
{
    free(mvc->View);
    free(mvc->ViewId);
    free(mvc->OP);
    mvc->View = NULL;
    mvc->ViewId = NULL;
    mvc->OP = NULL;
    mvc->NumViewAlloc = mvc->NumViewIdAlloc = mvc->NumOPAlloc = 0;
}

static int AllocateMVCDescription(mfxExtMVCSeqDesc *mvc)
{
    free(mvc->View);
    free(mvc->ViewId);
    free(mvc->OP);
    mvc->View = calloc(mvc->NumView, sizeof(*mvc->View));
    mvc->ViewId = calloc(mvc->NumViewId, sizeof(*mvc->ViewId));
    mvc->OP = calloc(mvc->NumOP, sizeof(*mvc->OP));
    if ((mvc->NumView && !mvc->View) ||
        (mvc->NumViewId && !mvc->ViewId) || (mvc->NumOP && !mvc->OP))
        return VLC_ENOMEM;
    mvc->NumViewAlloc = mvc->NumView;
    mvc->NumViewIdAlloc = mvc->NumViewId;
    mvc->NumOPAlloc = mvc->NumOP;
    return VLC_SUCCESS;
}

static void FreeSurfaces(decoder_sys_t *sys)
{
    for (unsigned i = 0; i < sys->surface_count; ++i)
        free(sys->surfaces[i].allocation);
    memset(sys->surfaces, 0, sizeof(sys->surfaces));
    sys->surface_count = 0;
}

static int AllocateSurfaces(decoder_t *dec, mfxFrameAllocRequest *request)
{
    decoder_sys_t *sys = dec->p_sys;
    unsigned count = request->NumFrameSuggested + sys->params.AsyncDepth + 4;
    if (count > MVC_MAX_SURFACES)
        count = MVC_MAX_SURFACES;
    if (count < request->NumFrameMin)
        return VLC_EGENERIC;
    unsigned width = (sys->params.mfx.FrameInfo.Width + 31) & ~31u;
    unsigned height = (sys->params.mfx.FrameInfo.Height + 31) & ~31u;
    size_t bytes = (size_t)width * height * 3 / 2;
    for (unsigned i = 0; i < count; ++i)
    {
        uint8_t *raw = malloc(bytes + 31);
        if (raw == NULL)
        {
            FreeSurfaces(sys);
            return VLC_ENOMEM;
        }
        uint8_t *aligned = (uint8_t *)(((uintptr_t)raw + 31) & ~(uintptr_t)31);
        sys->surfaces[i].allocation = raw;
        sys->surfaces[i].surface.Info = sys->params.mfx.FrameInfo;
        sys->surfaces[i].surface.Data.Y = aligned;
        sys->surfaces[i].surface.Data.U = aligned + (size_t)width * height;
        sys->surfaces[i].surface.Data.V = sys->surfaces[i].surface.Data.U + 1;
        sys->surfaces[i].surface.Data.Pitch = width;
    }
    sys->surface_count = count;
    msg_Info(dec, "allocated %u Intel MVC system-memory surfaces", count);
    return VLC_SUCCESS;
}

static int InitializeDecoder(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    if (sys->stream_len == 0)
        return VLC_EGENERIC;
    mfxBitstream bitstream = { 0 };
    bitstream.Data = sys->stream;
    bitstream.DataLength = bitstream.MaxLength = sys->stream_len;
    bitstream.TimeStamp = sys->stream_date == VLC_TICK_INVALID
                        ? MFX_TIMESTAMP_UNKNOWN : (mfxU64)sys->stream_date;
    mfxStatus status = MFXVideoDECODE_DecodeHeader(sys->session, &bitstream,
                                                   &sys->params);
    if (status == MFX_ERR_NOT_ENOUGH_BUFFER)
    {
        if (AllocateMVCDescription(&sys->mvc) != VLC_SUCCESS)
            return VLC_ENOMEM;
        bitstream.DataOffset = 0;
        bitstream.DataLength = sys->stream_len;
        status = MFXVideoDECODE_DecodeHeader(sys->session, &bitstream,
                                             &sys->params);
    }
    if (status == MFX_ERR_MORE_DATA)
        return VLC_EGENERIC;
    if (status < MFX_ERR_NONE)
    {
        msg_Warn(dec, "Intel MVC DecodeHeader failed (%d)", status);
        sys->abort_to_software = true;
        return VLC_EGENERIC;
    }
    if (sys->mvc.NumView != 2)
    {
        msg_Warn(dec, "Intel decoder reported %u MVC views", sys->mvc.NumView);
        sys->abort_to_software = true;
        return VLC_EGENERIC;
    }
    sys->params.IOPattern = MFX_IOPATTERN_OUT_SYSTEM_MEMORY;
    sys->params.AsyncDepth = 6;
    status = MFXVideoDECODE_Query(sys->session, &sys->params, &sys->params);
    if (status == MFX_WRN_PARTIAL_ACCELERATION)
    {
        msg_Warn(dec, "Intel MVC would use partial/software acceleration");
        sys->abort_to_software = true;
        return VLC_EGENERIC;
    }
    if (status < MFX_ERR_NONE)
    {
        msg_Warn(dec, "Intel MVC Query failed (%d)", status);
        sys->abort_to_software = true;
        return VLC_EGENERIC;
    }
    mfxFrameAllocRequest request = { 0 };
    status = MFXVideoDECODE_QueryIOSurf(sys->session, &sys->params, &request);
    if (status < MFX_ERR_NONE || AllocateSurfaces(dec, &request) != VLC_SUCCESS)
    {
        msg_Warn(dec, "Intel MVC QueryIOSurf failed (%d)", status);
        sys->abort_to_software = true;
        return VLC_EGENERIC;
    }
    status = MFXVideoDECODE_Init(sys->session, &sys->params);
    if (status == MFX_WRN_PARTIAL_ACCELERATION || status < MFX_ERR_NONE)
    {
        msg_Warn(dec, "Intel hardware MVC initialization failed (%d)", status);
        FreeSurfaces(sys);
        sys->abort_to_software = true;
        return VLC_EGENERIC;
    }
    sys->decoder_ready = true;
    msg_Info(dec, "initialized hardware MVC: %ux%u, views %u/%u",
             sys->params.mfx.FrameInfo.CropW,
             sys->params.mfx.FrameInfo.CropH,
             sys->mvc.View[0].ViewId, sys->mvc.View[1].ViewId);
    return VLC_SUCCESS;
}

static mfxFrameSurface1 *GetFreeSurface(decoder_sys_t *sys)
{
    for (unsigned i = 0; i < sys->surface_count; ++i)
        if (sys->surfaces[i].surface.Data.Locked == 0)
            return &sys->surfaces[i].surface;
    return NULL;
}

static void FreeView(mvc_view_t *view)
{
    if (view != NULL)
    {
        free(view->y);
        free(view);
    }
}

static void ClearViews(decoder_sys_t *sys)
{
    mvc_view_t *view;
    while ((view = sys->base_head) != NULL)
    {
        sys->base_head = view->next;
        FreeView(view);
    }
    while ((view = sys->dependent_head) != NULL)
    {
        sys->dependent_head = view->next;
        FreeView(view);
    }
    sys->base_tail = sys->dependent_tail = NULL;
    sys->base_count = sys->dependent_count = 0;
}

static mvc_view_t *CopyView(const mfxFrameSurface1 *surface)
{
    unsigned width = surface->Info.CropW ? surface->Info.CropW
                                         : surface->Info.Width;
    unsigned height = surface->Info.CropH ? surface->Info.CropH
                                          : surface->Info.Height;
    mvc_view_t *view = calloc(1, sizeof(*view));
    if (view == NULL)
        return NULL;
    size_t y_size = (size_t)width * height;
    view->y = malloc(y_size + y_size / 2);
    if (view->y == NULL)
    {
        free(view);
        return NULL;
    }
    view->uv = view->y + y_size;
    const uint8_t *src_y = surface->Data.Y +
        (size_t)surface->Info.CropY * surface->Data.Pitch +
        surface->Info.CropX;
    const uint8_t *src_uv = surface->Data.U +
        (size_t)(surface->Info.CropY / 2) * surface->Data.Pitch +
        surface->Info.CropX;
    for (unsigned y = 0; y < height; ++y)
        memcpy(view->y + (size_t)y * width,
               src_y + (size_t)y * surface->Data.Pitch, width);
    for (unsigned y = 0; y < height / 2; ++y)
        memcpy(view->uv + (size_t)y * width,
               src_uv + (size_t)y * surface->Data.Pitch, width);
    view->width = width;
    view->height = height;
    view->frame_order = surface->Data.FrameOrder;
    view->date = surface->Data.TimeStamp == MFX_TIMESTAMP_UNKNOWN
               ? VLC_TICK_INVALID : (vlc_tick_t)surface->Data.TimeStamp;
    return view;
}

static void QueueView(decoder_sys_t *sys, mvc_view_t *view, bool dependent)
{
    mvc_view_t **head = dependent ? &sys->dependent_head : &sys->base_head;
    mvc_view_t **tail = dependent ? &sys->dependent_tail : &sys->base_tail;
    unsigned *count = dependent ? &sys->dependent_count : &sys->base_count;
    if (*tail != NULL)
        (*tail)->next = view;
    else
        *head = view;
    *tail = view;
    (*count)++;
    if (*count > MVC_MAX_PENDING_VIEWS)
    {
        mvc_view_t *old = *head;
        *head = old->next;
        if (*head == NULL)
            *tail = NULL;
        (*count)--;
        FreeView(old);
    }
}

static int ConfigureOutput(decoder_t *dec, unsigned width, unsigned height)
{
    if (dec->fmt_out.video.i_visible_width == width &&
        dec->fmt_out.video.i_visible_height == height * 2)
        return VLC_SUCCESS;
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
    msg_Info(dec, "publishing frame-packed MVC output %ux%u, mode %d, "
             "rate %u/%u", width, height * 2,
             dec->fmt_out.video.multiview_mode,
             dec->fmt_out.video.i_frame_rate,
             dec->fmt_out.video.i_frame_rate_base);
    return decoder_UpdateVideoFormat(dec);
}

static void CopyNV12View(picture_t *picture, unsigned eye,
                         const mvc_view_t *view)
{
    unsigned y_offset = eye * view->height;
    unsigned c_offset = eye * (view->height / 2);
    for (unsigned y = 0; y < view->height; ++y)
        memcpy(picture->p[0].p_pixels +
                   (ptrdiff_t)(y_offset + y) * picture->p[0].i_pitch,
               view->y + (size_t)y * view->width, view->width);
    for (unsigned y = 0; y < view->height / 2; ++y)
    {
        uint8_t *u = picture->p[1].p_pixels +
                     (ptrdiff_t)(c_offset + y) * picture->p[1].i_pitch;
        uint8_t *v = picture->p[2].p_pixels +
                     (ptrdiff_t)(c_offset + y) * picture->p[2].i_pitch;
        const uint8_t *uv = view->uv + (size_t)y * view->width;
        for (unsigned x = 0; x < view->width / 2; ++x)
        {
            u[x] = uv[2 * x];
            v[x] = uv[2 * x + 1];
        }
    }
}

static int EmitPairs(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    while (sys->base_head != NULL && sys->dependent_head != NULL)
    {
        mvc_view_t *base = sys->base_head;
        mvc_view_t *dependent = sys->dependent_head;

        /* Media SDK normally emits both views with the same FrameOrder.  Do
         * not pair merely by queue position: after a damaged access unit or
         * a seek, one missing view would otherwise leave the eyes one frame
         * apart indefinitely. */
        if (base->frame_order != dependent->frame_order)
        {
            bool drop_base;
            if (base->date != VLC_TICK_INVALID &&
                dependent->date != VLC_TICK_INVALID &&
                base->date != dependent->date)
                drop_base = base->date < dependent->date;
            else
                drop_base = (int32_t)(base->frame_order -
                                      dependent->frame_order) < 0;
            msg_Warn(dec, "dropping unmatched Intel MVC %s view order "
                     "%u/%u", drop_base ? "base" : "dependent",
                     base->frame_order, dependent->frame_order);
            if (drop_base)
            {
                sys->base_head = base->next;
                if (sys->base_head == NULL)
                    sys->base_tail = NULL;
                sys->base_count--;
                FreeView(base);
            }
            else
            {
                sys->dependent_head = dependent->next;
                if (sys->dependent_head == NULL)
                    sys->dependent_tail = NULL;
                sys->dependent_count--;
                FreeView(dependent);
            }
            continue;
        }
        sys->base_head = base->next;
        sys->dependent_head = dependent->next;
        if (sys->base_head == NULL) sys->base_tail = NULL;
        if (sys->dependent_head == NULL) sys->dependent_tail = NULL;
        sys->base_count--;
        sys->dependent_count--;
        if (base->width != dependent->width || base->height != dependent->height ||
            ConfigureOutput(dec, base->width, base->height) != VLC_SUCCESS)
        {
            FreeView(base);
            FreeView(dependent);
            return VLCDEC_ECRITICAL;
        }
        picture_t *picture = decoder_NewPicture(dec);
        if (picture == NULL)
        {
            FreeView(base);
            FreeView(dependent);
            return VLCDEC_ECRITICAL;
        }
        const mvc_view_t *left = sys->base_is_right ? dependent : base;
        const mvc_view_t *right = sys->base_is_right ? base : dependent;
        CopyNV12View(picture, 0, left);
        CopyNV12View(picture, 1, right);
        picture->date = base->date != VLC_TICK_INVALID ? base->date
                                                       : dependent->date;
        picture->b_progressive = true;
        if (sys->pair_count < 12)
            msg_Info(dec, "Intel MVC pair #%"PRIu64" order %u/%u PTS %"PRId64,
                     sys->pair_count, base->frame_order,
                     dependent->frame_order, picture->date);
        sys->pair_count++;
        decoder_QueueVideo(dec, picture);
        FreeView(base);
        FreeView(dependent);
    }
    return VLCDEC_SUCCESS;
}

static int HandleSurface(decoder_t *dec, mfxFrameSurface1 *surface,
                         mfxSyncPoint sync)
{
    decoder_sys_t *sys = dec->p_sys;
    mfxStatus status = MFXVideoCORE_SyncOperation(sys->session, sync, 1000);
    if (status < MFX_ERR_NONE)
    {
        msg_Warn(dec, "Intel MVC surface synchronization failed (%d)", status);
        return VLCDEC_ECRITICAL;
    }
    mvc_view_t *view = CopyView(surface);
    if (view == NULL)
        return VLCDEC_ECRITICAL;
    QueueView(sys, view, surface->Info.FrameId.ViewId != 0);
    return EmitPairs(dec);
}

static int DecodeStream(decoder_t *dec, bool drain)
{
    decoder_sys_t *sys = dec->p_sys;
    mfxBitstream bitstream = { 0 };
    if (!drain)
    {
        bitstream.Data = sys->stream;
        bitstream.DataLength = bitstream.MaxLength = sys->stream_len;
        bitstream.TimeStamp = sys->stream_date == VLC_TICK_INVALID
                            ? MFX_TIMESTAMP_UNKNOWN : (mfxU64)sys->stream_date;
    }
    mfxStatus status = MFX_ERR_NONE;
    unsigned busy_retries = 0;
    for (unsigned iteration = 0; iteration < 256; ++iteration)
    {
        mfxFrameSurface1 *work = GetFreeSurface(sys);
        if (work == NULL)
        {
            msg_Warn(dec, "Intel MVC has no free decode surface");
            return VLCDEC_ECRITICAL;
        }
        mfxFrameSurface1 *output = NULL;
        mfxSyncPoint sync = NULL;
        status = MFXVideoDECODE_DecodeFrameAsync(
            sys->session, drain ? NULL : &bitstream, work, &output, &sync);
        if (status == MFX_WRN_DEVICE_BUSY)
        {
            if (++busy_retries > 100)
                return VLCDEC_ECRITICAL;
            Sleep(1);
            continue;
        }
        busy_retries = 0;
        if (sync != NULL && output != NULL &&
            HandleSurface(dec, output, sync) != VLCDEC_SUCCESS)
            return VLCDEC_ECRITICAL;
        if (status == MFX_ERR_MORE_SURFACE ||
            (status >= MFX_ERR_NONE && sync != NULL))
            continue;
        if (status == MFX_ERR_MORE_DATA)
            break;
        if (status < MFX_ERR_NONE)
        {
            msg_Warn(dec, "Intel MVC decode failed (%d)", status);
            return VLCDEC_ECRITICAL;
        }
    }
    if (!drain)
    {
        size_t consumed = bitstream.DataOffset;
        if (consumed > sys->stream_len)
            consumed = sys->stream_len;
        if (consumed != 0)
        {
            sys->stream_len -= consumed;
            memmove(sys->stream, sys->stream + consumed, sys->stream_len);
        }
        if (sys->stream_len == 0)
            sys->stream_date = VLC_TICK_INVALID;
    }
    return VLCDEC_SUCCESS;
}

static int Decode(decoder_t *dec, block_t *block)
{
    decoder_sys_t *sys = dec->p_sys;
    if (unlikely(sys->abort_to_software))
    {
        /* VLCDEC_RELOAD transfers ownership of this untouched block to the
         * replacement decoder. The marker survives module unload/reload on
         * the decoder object, so mfx_mvc declines and Edge264 gets selected
         * instead of reopening the same unusable hardware path forever. */
        var_Create(dec, "mfx-mvc-failed", VLC_VAR_VOID);
        return VLCDEC_RELOAD;
    }
    if (block == NULL)
        return sys->decoder_ready ? DecodeStream(dec, true) : VLCDEC_SUCCESS;
    if (block->i_flags & BLOCK_FLAG_CORRUPTED)
    {
        block_Release(block);
        return VLCDEC_SUCCESS;
    }
    if (block->i_flags & BLOCK_FLAG_DISCONTINUITY)
    {
        if (sys->decoder_ready)
            MFXVideoDECODE_Reset(sys->session, &sys->params);
        sys->stream_len = 0;
        sys->stream_date = VLC_TICK_INVALID;
        ClearViews(sys);
    }
    vlc_tick_t date = block->i_pts != VLC_TICK_INVALID
                    ? block->i_pts : block->i_dts;
    if (sys->stream_len == 0 || sys->stream_date == VLC_TICK_INVALID)
        sys->stream_date = date;
    int ret = AppendBlock(sys, block);
    if (ret != VLC_SUCCESS)
    {
        block_Release(block);
        return VLCDEC_ECRITICAL;
    }
    if (!sys->decoder_ready)
    {
        ret = InitializeDecoder(dec);
        if (ret != VLC_SUCCESS)
        {
            if (sys->abort_to_software)
            {
                var_Create(dec, "mfx-mvc-failed", VLC_VAR_VOID);
                return VLCDEC_RELOAD;
            }
            block_Release(block);
            return sys->stream_len < 8 * 1024 * 1024
                 ? VLCDEC_SUCCESS : VLCDEC_ECRITICAL;
        }
    }
    block_Release(block);
    return DecodeStream(dec, false);
}

static void Flush(decoder_t *dec)
{
    decoder_sys_t *sys = dec->p_sys;
    if (sys->decoder_ready)
        MFXVideoDECODE_Reset(sys->session, &sys->params);
    sys->stream_len = 0;
    sys->stream_date = VLC_TICK_INVALID;
    ClearViews(sys);
    sys->pair_count = 0;
}

static int OpenDecoder(vlc_object_t *obj)
{
    decoder_t *dec = (decoder_t *)obj;
    if (dec->fmt_in.i_codec != VLC_CODEC_H264_MVC)
        return VLC_EGENERIC;
    if (var_Type(dec, "mfx-mvc-failed") != 0)
    {
        msg_Info(dec, "Intel MVC declined after a runtime capability failure");
        return VLC_EGENERIC;
    }

    /* The regular VLC hardware-decoding preference also governs MVC.  The
     * Intel plugin has a higher capability score than Edge264, so declining
     * here is what turns the software decoder into the normal fallback when
     * the user selects "Disable" in the video preferences. */
    char *hw = var_InheritString(obj, "avcodec-hw");
    const bool hardware_disabled = hw != NULL && !strcmp(hw, "none");
    free(hw);
    if (hardware_disabled)
    {
        msg_Info(dec, "Intel MVC disabled by the hardware-decoding preference");
        return VLC_EGENERIC;
    }

    decoder_sys_t *sys = vlc_obj_calloc(obj, 1, sizeof(*sys));
    if (sys == NULL)
        return VLC_ENOMEM;
    dec->p_sys = sys;
    sys->stream_date = VLC_TICK_INVALID;
    sys->base_is_right = dec->fmt_in.video.multiview_mode ==
                         MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE;
    if (OpenHardwareSession(dec, sys) != VLC_SUCCESS)
        goto error;
    memset(&sys->params, 0, sizeof(sys->params));
    sys->params.mfx.CodecId = MFX_CODEC_AVC;
    sys->params.mfx.FrameInfo.FourCC = MFX_FOURCC_NV12;
    sys->mvc.Header.BufferId = MFX_EXTBUFF_MVC_SEQ_DESC;
    sys->mvc.Header.BufferSz = sizeof(sys->mvc);
    sys->ext[0] = (mfxExtBuffer *)&sys->mvc;
    sys->params.ExtParam = sys->ext;
    sys->params.NumExtParam = 1;
    if (AppendDecoderConfiguration(dec) != VLC_SUCCESS)
        goto error;
    dec->pf_decode = Decode;
    dec->pf_flush = Flush;
    dec->fmt_out.i_cat = VIDEO_ES;
    dec->fmt_out.i_codec = VLC_CODEC_I420;
    dec->i_extra_picture_buffers = 6;
    return VLC_SUCCESS;
error:
    if (sys->session != NULL) MFXClose(sys->session);
    if (sys->context != NULL) ID3D11DeviceContext_Release(sys->context);
    if (sys->device != NULL) ID3D11Device_Release(sys->device);
    free(sys->stream);
    return VLC_EGENERIC;
}

static void CloseDecoder(vlc_object_t *obj)
{
    decoder_t *dec = (decoder_t *)obj;
    decoder_sys_t *sys = dec->p_sys;
    ClearViews(sys);
    if (sys->decoder_ready)
        MFXVideoDECODE_Close(sys->session);
    FreeSurfaces(sys);
    FreeMVCDescription(&sys->mvc);
    if (sys->session != NULL) MFXClose(sys->session);
    if (sys->context != NULL) ID3D11DeviceContext_Release(sys->context);
    if (sys->device != NULL) ID3D11Device_Release(sys->device);
    free(sys->stream);
}
