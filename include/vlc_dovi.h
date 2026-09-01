/*****************************************************************************
 * vlc_dovi.h: Dolby Vision metadata definitions
 *****************************************************************************
 * Copyright (C) 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 ******************************************************************************/

#ifndef VLC_DOVI_H
#define VLC_DOVI_H 1

#include <stdbool.h>
#include <stdint.h>

/** Static Dolby Vision decoder configuration (dvcC/dvvC). */
typedef struct vlc_dovi_config_t
{
    uint8_t version_major;
    uint8_t version_minor;
    uint8_t profile;
    uint8_t level;
    bool rpu_present;
    bool el_present;
    bool bl_present;
    uint8_t bl_signal_compatibility_id;
    uint8_t metadata_compression;
} vlc_dovi_config_t;

enum vlc_dovi_reshape_method_t
{
    VLC_DOVI_RESHAPE_POLYNOMIAL = 0,
    VLC_DOVI_RESHAPE_MMR = 1,
};

enum vlc_dovi_nlq_method_t
{
    VLC_DOVI_NLQ_NONE = -1,
    VLC_DOVI_NLQ_LINEAR_DZ = 0,
};

/** Parsed, per-picture Dolby Vision RPU metadata. */
typedef struct vlc_video_dovi_metadata_t
{
    uint8_t coef_log2_denom;
    uint8_t bl_bit_depth;
    uint8_t el_bit_depth;
    uint8_t vdr_bit_depth;
    bool bl_video_full_range;
    bool residual_disabled;
    enum vlc_dovi_nlq_method_t nlq_method;

    float nonlinear_offset[3];
    float nonlinear_matrix[9];
    float linear_matrix[9];
    uint16_t source_min_pq;
    uint16_t source_max_pq;

    struct vlc_dovi_reshape_t
    {
        uint8_t num_pivots;
        uint16_t pivots[9];
        enum vlc_dovi_reshape_method_t mapping[8];
        uint8_t polynomial_order[8];
        int64_t polynomial_coefficients[8][3];
        uint8_t mmr_order[8];
        int64_t mmr_constant[8];
        int64_t mmr_coefficients[8][3][7];
    } curves[3];

    struct vlc_dovi_nlq_t
    {
        uint16_t offset;
        uint64_t vdr_in_max;
        uint64_t deadzone_slope;
        uint64_t deadzone_threshold;
    } nlq[3];

    bool has_level1;
    uint16_t level1_min_pq;
    uint16_t level1_max_pq;
    uint16_t level1_avg_pq;
} vlc_video_dovi_metadata_t;

#endif /* VLC_DOVI_H */
