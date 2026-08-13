/*****************************************************************************
 * vout_autocrop.h : automatic black border detection
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC
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

#ifndef LIBVLC_VOUT_AUTOCROP_H
#define LIBVLC_VOUT_AUTOCROP_H 1

/**
 * Automatic detection of the black bars (letterbox/pillarbox) a picture is
 * padded with, so the vout can crop them away on its own.
 *
 * The per-picture detection is the one HandBrake uses (libhb/scan.c): a row
 * or column counts as a border only if its average luma is below DARK *and*
 * every one of its samples sits within +-16 of that average, which is what
 * separates a flat mat from genuinely dark picture content. Unlike
 * HandBrake, which scans a fixed set of previews once before encoding, this
 * runs on the pictures as they are displayed, so the decision is taken from
 * a rolling window of samples and is allowed to change while playing.
 */
typedef struct vout_autocrop_t vout_autocrop_t;

typedef struct {
    unsigned left;
    unsigned top;
    unsigned right;
    unsigned bottom;
} vout_autocrop_border_t;

vout_autocrop_t *vout_autocrop_New(vlc_object_t *);
void vout_autocrop_Delete(vout_autocrop_t *);

/**
 * Drops every sample taken so far (but not the border currently applied,
 * which vout_autocrop_Restore still hands back).
 */
void vout_autocrop_Reset(vout_autocrop_t *);

/**
 * Drops everything, the mats learned included: what was measured on one
 * item says nothing about the next one.
 */
void vout_autocrop_Forget(vout_autocrop_t *);

/**
 * Feeds one picture to the detector. Most calls do nothing: pictures are
 * only ever sampled a few times a second.
 *
 * \return true when a new border has been decided and must be applied, in
 * which case it is stored in *border.
 */
bool vout_autocrop_Feed(vout_autocrop_t *, picture_t *, vlc_tick_t now,
                        vout_autocrop_border_t *border);

/**
 * Hands back the border last decided for a source of that size, so a
 * display that has just been recreated can be cropped before it shows its
 * first picture rather than a second later.
 *
 * \return false when nothing has been decided yet for that geometry.
 */
bool vout_autocrop_Restore(const vout_autocrop_t *,
                           unsigned width, unsigned height,
                           vout_autocrop_border_t *border);

#endif /* LIBVLC_VOUT_AUTOCROP_H */
