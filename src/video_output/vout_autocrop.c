/*****************************************************************************
 * vout_autocrop.c : automatic black border detection
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC
 *
 * The per-picture detection below is a transcription of the one HandBrake
 * uses in libhb/scan.c (row_all_dark / column_all_dark and the crop record
 * around them), which is the reference implementation in the open source
 * world for getting this right on real material.
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

#include <limits.h>
#include <stdlib.h>

#include <vlc_common.h>
#include <vlc_picture.h>
#include <vlc_image.h>

#include "vout_autocrop.h"

/* Luma above which a row/column cannot be part of a black bar. Same value as
 * HandBrake: high enough to survive the quantization noise that any encoder
 * leaves in a flat black mat, low enough to stay under any real picture. */
#define AUTOCROP_DARK       32
/* A border must also be *flat*: no sample further than this from the row
 * average. Dark picture content (a night scene, a fade) is never flat. */
#define AUTOCROP_FLATNESS   16

/* How often a picture is actually looked at. Fast until something has been
 * decided -- that delay is dead time during which the viewer stares at the
 * black bars -- then slow, since from then on we are only watching for the
 * aspect ratio to change mid-programme. */
#define AUTOCROP_PERIOD_SEARCH  (CLOCK_FREQ / 6)
#define AUTOCROP_PERIOD_SETTLED (CLOCK_FREQ / 2)

/* Rolling window of accepted samples the decision is taken from: half a
 * minute of playback. It has to be that long because of what makes the
 * measurement move -- a scene that is dark right up to the mat reads as a
 * wider mat, and a scene can be dark for a good many seconds. */
#define AUTOCROP_SAMPLES    61
/* ... and how many of them are needed before deciding anything at all. */
#define AUTOCROP_SAMPLES_MIN 5
/* ... and before the one correction pass below (about five seconds in). */
#define AUTOCROP_SAMPLES_REFINE 11

/* A sample this far below the median means the window holds frames of
 * different aspect ratios (a scope film with 16:9 credits, an advert
 * break): the median would then crop into the wider ones, so the loosest
 * crop is taken instead. HandBrake's margin; its count scales with the
 * number of samples (it uses 4 out of 10 previews, 8 out of 40), which
 * here is a fifth of the window. */
#define AUTOCROP_MIXED_MARGIN 9
#define AUTOCROP_MIXED_MIN_COUNT 3

/* Hysteresis: a decision this close to what is already applied is not worth
 * moving the window for (and every change costs a resize, which the user
 * sees). Below the ~1% of frame height HandBrake ignores as edge noise. */
#define AUTOCROP_HYSTERESIS 8
/* The first decision is taken from five samples covering less than a second
 * -- fast, but that second is often a fade-in or a title card, and the mat
 * it measures there can be a couple of lines off. Once the window is full,
 * and once only, allow one correction down to the exact border. */
#define AUTOCROP_REFINE_HYSTERESIS 2

/* How many source geometries the last decision is remembered for. */
#define AUTOCROP_GEOMETRIES 4
/* ... and how many distinct mats are remembered for each of them, so that
 * one already worn is recognised at once when it comes back. */
#define AUTOCROP_KNOWN 3
/* How many samples in a row must say exactly the same thing for that to
 * count as "the mat is back", when it is one this source already wore.
 * Two seconds of an unchanging measurement: a mat is pixel-identical from
 * frame to frame, a dark scene taken for one is not. */
#define AUTOCROP_RETURN_RUN 5

struct vout_autocrop_t
{
    vlc_object_t *obj;

    /* Lazily created, and only ever used for the chromas whose luma cannot
     * be read directly -- in practice the hardware surfaces (CVPX on macOS,
     * D3D, VAAPI) and the 10-bit and RGB layouts. */
    image_handler_t *image;
    bool image_failed;

    /* Geometry every sample below refers to; a change wipes them. */
    unsigned width;
    unsigned height;

    /* Rolling window of accepted samples */
    unsigned t[AUTOCROP_SAMPLES];
    unsigned b[AUTOCROP_SAMPLES];
    unsigned l[AUTOCROP_SAMPLES];
    unsigned r[AUTOCROP_SAMPLES];
    unsigned count;     /* valid samples, up to AUTOCROP_SAMPLES */
    unsigned next;      /* where the next one goes */
    bool     refined;   /* the one correction pass has been taken */
    /* Last border the window pointed at, waiting for the next sample to
     * say the same thing before it is acted on. */
    vout_autocrop_border_t proposal;
    bool     has_proposal;

    vlc_tick_t next_sample;

    /* The mats worn by each source geometry, most recent first -- an
     * adaptive stream that loops can come back at another resolution and
     * then at the first one again, and a television channel alternates
     * between the programme's mat and the full frame of its adverts.
     * known[0] is what is applied; the ones behind it are what this
     * source is known to go back to (see MatchesKnownMat). */
    struct {
        unsigned width;
        unsigned height;
        vout_autocrop_border_t known[AUTOCROP_KNOWN];
        unsigned known_count;
    } applied[AUTOCROP_GEOMETRIES];
    unsigned applied_count;
};

static bool BorderIsClose(const vout_autocrop_border_t *a,
                          const vout_autocrop_border_t *b, unsigned tolerance);

static unsigned FindGeometry(const vout_autocrop_t *ac,
                             unsigned width, unsigned height)
{
    for (unsigned i = 0; i < ac->applied_count; i++)
        if (ac->applied[i].width == width && ac->applied[i].height == height)
            return i;
    return AUTOCROP_GEOMETRIES;
}

/* Most recently applied first. */
static vout_autocrop_border_t *FindApplied(vout_autocrop_t *ac,
                                           unsigned width, unsigned height)
{
    const unsigned i = FindGeometry(ac, width, height);
    return i < AUTOCROP_GEOMETRIES ? &ac->applied[i].known[0] : NULL;
}

/* Has this source worn that mat before? */
static bool MatchesKnownMat(const vout_autocrop_t *ac,
                            unsigned width, unsigned height,
                            const vout_autocrop_border_t *border)
{
    const unsigned g = FindGeometry(ac, width, height);
    if (g >= AUTOCROP_GEOMETRIES)
        return false;

    for (unsigned i = 0; i < ac->applied[g].known_count; i++)
        if (BorderIsClose(&ac->applied[g].known[i], border,
                          AUTOCROP_HYSTERESIS / 2))
            return true;
    return false;
}

static void RecordApplied(vout_autocrop_t *ac, unsigned width, unsigned height,
                          const vout_autocrop_border_t *border)
{
    unsigned g = FindGeometry(ac, width, height);

    if (g >= AUTOCROP_GEOMETRIES) {
        if (ac->applied_count < AUTOCROP_GEOMETRIES)
            ac->applied_count++;
        /* Push everything down one slot; when the table is full that drops
         * the oldest geometry off the end. */
        memmove(&ac->applied[1], &ac->applied[0],
                (ac->applied_count - 1) * sizeof(ac->applied[0]));
        ac->applied[0].width  = width;
        ac->applied[0].height = height;
        ac->applied[0].known_count = 0;
        g = 0;
    }

    /* Same mat as the one in force: nothing to remember. */
    if (ac->applied[g].known_count > 0
     && BorderIsClose(&ac->applied[g].known[0], border, 0))
        return;

    if (ac->applied[g].known_count < AUTOCROP_KNOWN)
        ac->applied[g].known_count++;
    memmove(&ac->applied[g].known[1], &ac->applied[g].known[0],
            (ac->applied[g].known_count - 1) * sizeof(ac->applied[g].known[0]));
    ac->applied[g].known[0] = *border;
}

/*****************************************************************************
 * Per-picture detection (HandBrake's, on VLC plane_t)
 *****************************************************************************/
static inline unsigned AbsDiff(unsigned x, unsigned y)
{
    return x < y ? y - x : x - y;
}

static inline unsigned ClampBlack(unsigned x)
{
    /* luma 'black' is 16 and anything less should be clamped at 16 */
    return x < 16 ? 16 : x;
}

static bool RowAllDark(const uint8_t *luma, int pitch, unsigned width,
                       unsigned row)
{
    const uint8_t *line = luma + (size_t)pitch * row;

    unsigned avg = 0;
    for (unsigned i = 0; i < width; i++)
        avg += ClampBlack(line[i]);
    avg /= width;
    if (avg >= AUTOCROP_DARK)
        return false;

    for (unsigned i = 0; i < width; i++)
        if (AbsDiff(avg, ClampBlack(line[i])) > AUTOCROP_FLATNESS)
            return false;
    return true;
}

static bool ColumnAllDark(const uint8_t *luma, int pitch, unsigned height,
                          unsigned top, unsigned bottom, unsigned col)
{
    const uint8_t *column = luma + (size_t)pitch * top + col;
    const unsigned lines = height - top - bottom;

    unsigned avg = 0;
    for (unsigned i = 0; i < lines; i++)
        avg += ClampBlack(column[(size_t)pitch * i]);
    avg /= lines;
    if (avg >= AUTOCROP_DARK)
        return false;

    for (unsigned i = 0; i < lines; i++)
        if (AbsDiff(avg, ClampBlack(column[(size_t)pitch * i])) > AUTOCROP_FLATNESS)
            return false;
    return true;
}

/**
 * Runs the detection over one 8-bit luma plane.
 *
 * \return false when the frame must not be counted at all (all black, or a
 * border reaching a quarter of the frame: a fade, a title card, credits).
 */
static bool DetectBorder(const uint8_t *luma, int pitch,
                         unsigned width, unsigned height,
                         vout_autocrop_border_t *border)
{
    const unsigned h4 = height / 4;
    const unsigned w4 = width / 4;

    if (h4 < 1 || w4 < 1)
        return false;

    /* When widescreen content is matted to 16:9 or 4:3 there is sometimes a
     * thin border on the outer edge of the matte (line 21 VBI data on TV
     * content, a production diagnostic on HD). Ignore it so the matte itself
     * can be found -- but do not crop it on its own, cropping a dozen lines
     * only shifts the picture about. Scales with the frame: 12 pixels on
     * 1080i look like 4 on 480i. */
    const unsigned edge = height / 100;

    unsigned top, bottom, left, right;

    for (top = edge; top < h4; top++)
        if (!RowAllDark(luma, pitch, width, top))
            break;
    if (top <= edge) {
        for (top = 0; top < edge; top++)
            if (!RowAllDark(luma, pitch, width, top))
                break;
        if (top >= edge)
            top = 0;
    }

    for (bottom = edge; bottom < h4; bottom++)
        if (!RowAllDark(luma, pitch, width, height - 1 - bottom))
            break;
    if (bottom <= edge) {
        for (bottom = 0; bottom < edge; bottom++)
            if (!RowAllDark(luma, pitch, width, height - 1 - bottom))
                break;
        if (bottom >= edge)
            bottom = 0;
    }

    for (left = 0; left < w4; left++)
        if (!ColumnAllDark(luma, pitch, height, top, bottom, left))
            break;

    for (right = 0; right < w4; right++)
        if (!ColumnAllDark(luma, pitch, height, top, bottom, width - 1 - right))
            break;

    /* Only keep the result if none of the borders reached a quarter of the
     * frame, otherwise frames with a lot of black -- titles, credits, a fade
     * through black -- would drag the decision with them. */
    if (top >= h4 || bottom >= h4 || left >= w4 || right >= w4)
        return false;

    border->top    = top;
    border->bottom = bottom;
    border->left   = left;
    border->right  = right;
    return true;
}

/*****************************************************************************
 * Getting at the luma
 *****************************************************************************/
/* Anything with a byte-per-sample luma plane first: I420, YV12, I422, I444,
 * NV12, NV21, GREY and their JPEG-range twins. Everything else (hardware
 * surfaces, 10-bit, packed YUV, RGB) goes through a conversion. */
static bool LumaIsReadable(const picture_t *pic)
{
    const vlc_chroma_description_t *desc =
        vlc_fourcc_GetChromaDescription(pic->format.i_chroma);

    return desc != NULL && desc->plane_count > 0 && desc->pixel_size == 1
        && vlc_fourcc_IsYUV(pic->format.i_chroma)
        && pic->p[0].p_pixels != NULL;
}

static picture_t *ConvertToI420(vout_autocrop_t *ac, picture_t *pic)
{
    if (ac->image_failed)
        return NULL;
    if (ac->image == NULL) {
        ac->image = image_HandlerCreate(ac->obj);
        if (ac->image == NULL) {
            ac->image_failed = true;
            return NULL;
        }
    }

    /* Same geometry, only the layout changes: the CVPX converter (and most
     * others) refuse anything that would also resize. */
    video_format_t fmt_out = pic->format;
    fmt_out.i_chroma  = VLC_CODEC_I420;
    fmt_out.p_palette = NULL;

    picture_t *converted = image_Convert(ac->image, pic, &pic->format, &fmt_out);
    if (converted == NULL) {
        msg_Dbg(ac->obj, "autocrop: cannot read %4.4s pictures, giving up",
                (const char *)&pic->format.i_chroma);
        /* One failure is enough: it is the chroma that cannot be read, and
         * it will not change. Retrying would convert nothing several times
         * a second for the rest of the playback. */
        ac->image_failed = true;
    }
    return converted;
}

/*****************************************************************************
 * Deciding
 *****************************************************************************/
static int CompareUnsigned(const void *a, const void *b)
{
    const unsigned x = *(const unsigned *)a;
    const unsigned y = *(const unsigned *)b;
    return x < y ? -1 : (x > y ? 1 : 0);
}

static inline unsigned Even(unsigned x)
{
    /* A cropped rectangle whose origin or size is odd puts the chroma
     * planes half a sample off in 4:2:0 and 4:2:2, which some displays
     * cannot express at all. Always round the border down, i.e. keep the
     * extra line rather than eat into the picture. */
    return x & ~1u;
}

/**
 * Turns the window of samples into one border, the way HandBrake picks one
 * out of its previews: the median, unless enough samples sit well below it,
 * which means the window holds several aspect ratios -- then the loosest
 * (smallest) crop, so nothing that is picture in any of them is cut.
 *
 * The median is what makes this hold still. A single scene that happens to
 * be dark right up to the mat measures a wider mat, but it is a minority
 * of half a minute of samples and the median ignores it.
 */
static void SelectBorder(const vout_autocrop_t *ac,
                         vout_autocrop_border_t *border)
{
    unsigned t[AUTOCROP_SAMPLES], b[AUTOCROP_SAMPLES];
    unsigned l[AUTOCROP_SAMPLES], r[AUTOCROP_SAMPLES];
    const unsigned n = ac->count;

    memcpy(t, ac->t, n * sizeof(*t));
    memcpy(b, ac->b, n * sizeof(*b));
    memcpy(l, ac->l, n * sizeof(*l));
    memcpy(r, ac->r, n * sizeof(*r));

    qsort(t, n, sizeof(*t), CompareUnsigned);
    qsort(b, n, sizeof(*b), CompareUnsigned);
    qsort(l, n, sizeof(*l), CompareUnsigned);
    qsort(r, n, sizeof(*r), CompareUnsigned);

    unsigned i = n >> 1;

    const unsigned switch_count = (n / 5) > AUTOCROP_MIXED_MIN_COUNT
                                ? (n / 5) : AUTOCROP_MIXED_MIN_COUNT;
    unsigned below = 0;
    for (unsigned k = 0; k < n; k++) {
        if ((t[k] + AUTOCROP_MIXED_MARGIN < t[i]) ||
            (b[k] + AUTOCROP_MIXED_MARGIN < b[i]) ||
            (l[k] + AUTOCROP_MIXED_MARGIN < l[i]) ||
            (r[k] + AUTOCROP_MIXED_MARGIN < r[i]))
            below++;
    }
    if (below >= switch_count)
        i = 0;

    border->top    = Even(t[i]);
    border->bottom = Even(b[i]);
    border->left   = Even(l[i]);
    border->right  = Even(r[i]);
}

static bool BorderIsClose(const vout_autocrop_border_t *a,
                          const vout_autocrop_border_t *b, unsigned tolerance)
{
    return AbsDiff(a->top,    b->top)    <= tolerance
        && AbsDiff(a->bottom, b->bottom) <= tolerance
        && AbsDiff(a->left,   b->left)   <= tolerance
        && AbsDiff(a->right,  b->right)  <= tolerance;
}

/**
 * The last AUTOCROP_RETURN_RUN samples, when they all say exactly the same
 * thing, and that thing is a mat this source has worn before.
 *
 * This is the way back from an advert break. Going the other way is quick
 * -- the moment the picture reaches the edge of the frame the selection
 * drops to the loosest crop of the window -- but coming back the mat has
 * to win a median taken over half a minute, which is half a minute of
 * black bars on a programme that had them cropped a moment earlier. A mat
 * is identical from frame to frame and this source is known to wear it, so
 * a couple of seconds of it saying so is proof enough.
 */
static bool ReturnedToKnownMat(const vout_autocrop_t *ac,
                               unsigned width, unsigned height,
                               vout_autocrop_border_t *border)
{
    if (ac->count < AUTOCROP_RETURN_RUN)
        return false;

    vout_autocrop_border_t run;
    for (unsigned i = 0; i < AUTOCROP_RETURN_RUN; i++) {
        /* ac->next is where the *next* sample goes, so step back from it. */
        const unsigned k = (ac->next + AUTOCROP_SAMPLES - 1 - i)
                         % AUTOCROP_SAMPLES;
        const vout_autocrop_border_t sample = {
            .left = Even(ac->l[k]), .top = Even(ac->t[k]),
            .right = Even(ac->r[k]), .bottom = Even(ac->b[k]),
        };

        if (i == 0)
            run = sample;
        else if (!BorderIsClose(&run, &sample, AUTOCROP_REFINE_HYSTERESIS))
            return false;
    }

    if (!MatchesKnownMat(ac, width, height, &run))
        return false;

    *border = run;
    return true;
}

/* The loosest crop the window holds, side by side: the mat every single
 * sample agrees is there. */
static void WindowFloor(const vout_autocrop_t *ac,
                        vout_autocrop_border_t *floor)
{
    unsigned t = UINT_MAX, b = UINT_MAX, l = UINT_MAX, r = UINT_MAX;

    for (unsigned i = 0; i < ac->count; i++) {
        if (ac->t[i] < t) t = ac->t[i];
        if (ac->b[i] < b) b = ac->b[i];
        if (ac->l[i] < l) l = ac->l[i];
        if (ac->r[i] < r) r = ac->r[i];
    }

    floor->top    = Even(t == UINT_MAX ? 0 : t);
    floor->bottom = Even(b == UINT_MAX ? 0 : b);
    floor->left   = Even(l == UINT_MAX ? 0 : l);
    floor->right  = Even(r == UINT_MAX ? 0 : r);
}

static bool BorderIsWorthApplying(const vout_autocrop_border_t *applied,
                                  const vout_autocrop_border_t *border,
                                  unsigned hysteresis)
{
    if (applied == NULL)
        return border->top || border->bottom || border->left || border->right;

    return AbsDiff(border->top,    applied->top)    >= hysteresis
        || AbsDiff(border->bottom, applied->bottom) >= hysteresis
        || AbsDiff(border->left,   applied->left)   >= hysteresis
        || AbsDiff(border->right,  applied->right)  >= hysteresis;
}

/*****************************************************************************
 * Public
 *****************************************************************************/
vout_autocrop_t *vout_autocrop_New(vlc_object_t *obj)
{
    vout_autocrop_t *ac = calloc(1, sizeof(*ac));
    if (unlikely(ac == NULL))
        return NULL;

    ac->obj = obj;
    ac->next_sample = VLC_TICK_INVALID;
    return ac;
}

void vout_autocrop_Delete(vout_autocrop_t *ac)
{
    if (ac->image != NULL)
        image_HandlerDelete(ac->image);
    free(ac);
}

void vout_autocrop_Reset(vout_autocrop_t *ac)
{
    ac->count   = 0;
    ac->next    = 0;
    ac->refined = false;
    ac->has_proposal = false;
    ac->next_sample = VLC_TICK_INVALID;
}

void vout_autocrop_Forget(vout_autocrop_t *ac)
{
    vout_autocrop_Reset(ac);
    ac->applied_count = 0;
    ac->width  = 0;
    ac->height = 0;
}

bool vout_autocrop_Restore(const vout_autocrop_t *ac,
                           unsigned width, unsigned height,
                           vout_autocrop_border_t *border)
{
    const vout_autocrop_border_t *applied =
        FindApplied((vout_autocrop_t *)ac, width, height);
    if (applied != NULL) {
        *border = *applied;
        return true;
    }

    /* A resolution never seen before -- but an adaptive stream changing
     * variant keeps the same picture inside the same frame shape, only
     * bigger or smaller. Scale the border measured on another resolution
     * of the same shape and use it until the measurement confirms it:
     * without this, every variant change shows the black bars again for
     * the second it takes to measure them, and moves the window twice.
     * Deliberately not recorded as a decision -- it is a guess. */
    for (unsigned i = 0; i < ac->applied_count; i++) {
        const unsigned w = ac->applied[i].width;
        const unsigned h = ac->applied[i].height;

        if (w == 0 || h == 0 || ac->applied[i].known_count == 0)
            continue;
        /* Same frame shape, within a percent: the rungs of a real ladder
         * are not exactly proportional (854x480 is not exactly 16:9 while
         * 1280x720 is). */
        const uint64_t a = (uint64_t)w * height, b = (uint64_t)h * width;
        const uint64_t diff = a > b ? a - b : b - a;
        if (diff * 100 > a)
            continue;

        const vout_autocrop_border_t *known = &ac->applied[i].known[0];
        border->left   = Even((unsigned)((uint64_t)known->left   * width / w));
        border->right  = Even((unsigned)((uint64_t)known->right  * width / w));
        border->top    = Even((unsigned)((uint64_t)known->top    * height / h));
        border->bottom = Even((unsigned)((uint64_t)known->bottom * height / h));
        return true;
    }
    return false;
}

bool vout_autocrop_Feed(vout_autocrop_t *ac, picture_t *pic, vlc_tick_t now,
                        vout_autocrop_border_t *border)
{
    if (ac->next_sample != VLC_TICK_INVALID && now < ac->next_sample)
        return false;
    /* Sample fast only while the window is still filling up, whatever it
     * ends up deciding -- including "this picture has no black bars", which
     * is a decision too and must not keep the detector spinning. */
    ac->next_sample = now + (ac->count >= AUTOCROP_SAMPLES_MIN
                             ? AUTOCROP_PERIOD_SETTLED
                             : AUTOCROP_PERIOD_SEARCH);


    const video_format_t *fmt = &pic->format;
    const unsigned width  = fmt->i_visible_width;
    const unsigned height = fmt->i_visible_height;

    if (width < 32 || height < 32)
        return false;

    if (ac->width != width || ac->height != height) {
        ac->width  = width;
        ac->height = height;
        ac->count = 0;
        ac->next  = 0;
        ac->has_proposal = false;
        /* A geometry already decided once has had its refinement pass; a
         * stream that alternates between two resolutions would otherwise
         * be allowed a fresh two-pixel correction on every switch, and
         * spend its life nudging the window back and forth. */
        ac->refined = FindApplied(ac, width, height) != NULL;
    }

    picture_t *converted = NULL;
    const picture_t *readable = pic;
    if (!LumaIsReadable(pic)) {
        converted = ConvertToI420(ac, pic);
        if (converted == NULL)
            return false;
        readable = converted;
    }

    const plane_t *plane = &readable->p[0];
    const uint8_t *luma = plane->p_pixels
                        + (size_t)plane->i_pitch * readable->format.i_y_offset
                        + readable->format.i_x_offset;

    vout_autocrop_border_t sample;
    const bool usable = DetectBorder(luma, plane->i_pitch, width, height,
                                     &sample);
    if (converted != NULL)
        picture_Release(converted);
    if (!usable)
        return false;

    ac->t[ac->next] = sample.top;
    ac->b[ac->next] = sample.bottom;
    ac->l[ac->next] = sample.left;
    ac->r[ac->next] = sample.right;
    ac->next = (ac->next + 1) % AUTOCROP_SAMPLES;
    if (ac->count < AUTOCROP_SAMPLES)
        ac->count++;

    /* The mat this source is known to wear, back after an interruption:
     * acted on at once, and the window is emptied because everything in it
     * describes what was on screen before. Without that, the median of the
     * old samples would immediately undo it. */
    vout_autocrop_border_t returned;
    if (ReturnedToKnownMat(ac, width, height, &returned)
     && BorderIsWorthApplying(FindApplied(ac, width, height), &returned,
                              AUTOCROP_HYSTERESIS)) {
        msg_Dbg(ac->obj, "autocrop: %ux%u -> %ux%u+%u+%u (known mat back)",
                width, height,
                width - returned.left - returned.right,
                height - returned.top - returned.bottom,
                returned.left, returned.top);
        RecordApplied(ac, width, height, &returned);
        ac->count = 0;
        ac->next  = 0;
        ac->has_proposal = false;
        *border = returned;
        return true;
    }

    if (ac->count < AUTOCROP_SAMPLES_MIN)
        return false;

    vout_autocrop_border_t decided;
    SelectBorder(ac, &decided);

    const bool settled = ac->count >= AUTOCROP_SAMPLES_REFINE;
    const unsigned hysteresis = (settled && !ac->refined)
                              ? AUTOCROP_REFINE_HYSTERESIS
                              : AUTOCROP_HYSTERESIS;
    if (settled)
        ac->refined = true;

    const vout_autocrop_border_t *applied = FindApplied(ac, width, height);
    if (!BorderIsWorthApplying(applied, &decided, hysteresis))
        return false;

    /* ⚠ Cropping MORE than what is already in force, on a source whose mat
     * is established, is almost always a scene that happens to be dark up
     * to the mat -- a night sky over a 4:3 programme reads as a wider mat
     * and takes the picture with it, then gives it back when the daylight
     * returns. Widening is therefore only allowed when *every* sample of
     * the window says so; that a majority does is not enough, however long
     * the scene lasts. Cropping LESS goes through at once: that direction
     * means picture is being cut, which is the damage worth undoing.
     * A mat this source already wore comes back through
     * ReturnedToKnownMat() above, which does not need this proof. */
    if (applied != NULL
     && (decided.top    > applied->top    + AUTOCROP_REFINE_HYSTERESIS
      || decided.bottom > applied->bottom + AUTOCROP_REFINE_HYSTERESIS
      || decided.left   > applied->left   + AUTOCROP_REFINE_HYSTERESIS
      || decided.right  > applied->right  + AUTOCROP_REFINE_HYSTERESIS)) {
        vout_autocrop_border_t floor;
        WindowFloor(ac, &floor);

        if (floor.top    + AUTOCROP_REFINE_HYSTERESIS < decided.top
         || floor.bottom + AUTOCROP_REFINE_HYSTERESIS < decided.bottom
         || floor.left   + AUTOCROP_REFINE_HYSTERESIS < decided.left
         || floor.right  + AUTOCROP_REFINE_HYSTERESIS < decided.right)
            return false;
    }

    /* Never act on a decision the next sample does not confirm. What this
     * catches is the fade from black that opens most sources (and every
     * advert break): during it the picture *is* a growing black border, so
     * each sample measures a different one, and acting on them walks the
     * window down in steps instead of settling once at the end. Two
     * agreeing decisions in a row cost one sampling period. */
    const bool confirmed = ac->has_proposal
        && AbsDiff(decided.top,    ac->proposal.top)    <= AUTOCROP_REFINE_HYSTERESIS
        && AbsDiff(decided.bottom, ac->proposal.bottom) <= AUTOCROP_REFINE_HYSTERESIS
        && AbsDiff(decided.left,   ac->proposal.left)   <= AUTOCROP_REFINE_HYSTERESIS
        && AbsDiff(decided.right,  ac->proposal.right)  <= AUTOCROP_REFINE_HYSTERESIS;
    ac->proposal = decided;
    ac->has_proposal = true;
    if (!confirmed)
        return false;

    msg_Dbg(ac->obj, "autocrop: %ux%u -> %ux%u+%u+%u", width, height,
            width - decided.left - decided.right,
            height - decided.top - decided.bottom,
            decided.left, decided.top);

    RecordApplied(ac, width, height, &decided);
    *border = decided;
    return true;
}
