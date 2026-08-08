/*****************************************************************************
 * picture_pool.c : picture pool functions
 *****************************************************************************
 * Copyright (C) 2009 VLC authors and VideoLAN
 * Copyright (C) 2009 Laurent Aimar <fenrir _AT_ videolan _DOT_ org>
 * Copyright (C) 2013-2015 Rémi Denis-Courmont
 *
 * Authors: Laurent Aimar <fenrir _AT_ videolan _DOT_ org>
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
#include <assert.h>
#include <limits.h>
#include <stdlib.h>

#include <vlc_common.h>
#include <vlc_picture_pool.h>
#include <vlc_atomic.h>
#include "picture.h"

/* The pool used to be limited to the 64 bits of one unsigned long long.
 * The look-ahead video cache (video-cache-mb) sizes the indirect-rendering
 * decoder pool from a RAM budget, and a DVD-sized budget wants hundreds of
 * pictures. This bitmap is now the HARD ceiling on how deep that cache can
 * grow: the plain-memory staging that used to spill decoded pictures past
 * the pool was dropped (one full-frame memcpy per picture, ~11% of the Mini
 * G4 during DVD playback -- see DecoderPlayVideo), so the pool must be sized
 * to the whole budget. A multi-word bitmap (16 * 64 = 1024) covers the
 * RAM-scaled pool the larger-memory PPC machines can afford (see
 * vout_wrapper.c). The array cost is trivial (one pointer word per slot);
 * the picture BUFFERS are allocated separately, so this width is not itself
 * a RAM commitment. The pool address is aligned on POOL_MAX so a clone can
 * pack pool+offset into one uintptr_t (see picture_pool_ClonePicture) --
 * POOL_MAX must stay a power of two, so POOL_WORDS must too. */
#define POOL_WORD_BITS (CHAR_BIT * sizeof (unsigned long long))
#define POOL_WORDS 16
#define POOL_MAX (POOL_WORD_BITS * POOL_WORDS)

static_assert ((POOL_MAX & (POOL_MAX - 1)) == 0, "Not a power of two");
/* Modules clamp their pool against the public constant; the two must not
 * drift apart, or a "vout display" sizing its pool from a memory budget would
 * clamp to a ceiling this allocator does not honour. */
static_assert (POOL_MAX == VLC_PICTURE_POOL_MAX, "Public ceiling out of sync");

struct picture_pool_t {
    int       (*pic_lock)(picture_t *);
    void      (*pic_unlock)(picture_t *);
    vlc_mutex_t lock;
    vlc_cond_t  wait;

    bool               canceled;
    unsigned long long available[POOL_WORDS];
    atomic_ushort      refs;
    unsigned short     picture_count;
    picture_t  *picture[];
};

static inline void pool_avail_set(picture_pool_t *pool, unsigned offset)
{
    pool->available[offset / POOL_WORD_BITS] |=
        1ULL << (offset % POOL_WORD_BITS);
}

static inline void pool_avail_clear(picture_pool_t *pool, unsigned offset)
{
    pool->available[offset / POOL_WORD_BITS] &=
        ~(1ULL << (offset % POOL_WORD_BITS));
}

static inline bool pool_avail_test(const picture_pool_t *pool, unsigned offset)
{
    return (pool->available[offset / POOL_WORD_BITS]
            >> (offset % POOL_WORD_BITS)) & 1;
}

static bool pool_avail_empty(const picture_pool_t *pool)
{
    for (unsigned w = 0; w < POOL_WORDS; w++)
        if (pool->available[w] != 0)
            return false;
    return true;
}

/* First available offset at or above `from` (0-based), as 1-based index;
 * 0 when none — the multi-word generalization of ffsll/fnsll. */
static unsigned pool_avail_next(const picture_pool_t *pool, unsigned from)
{
    unsigned w = from / POOL_WORD_BITS;
    if (w >= POOL_WORDS)
        return 0;

    unsigned long long x = pool->available[w]
        & ~((1ULL << (from % POOL_WORD_BITS)) - 1);
    for (;;) {
        if (x != 0)
            return w * POOL_WORD_BITS + ffsll(x);
        if (++w >= POOL_WORDS)
            return 0;
        x = pool->available[w];
    }
}

static void picture_pool_Destroy(picture_pool_t *pool)
{
    if (atomic_fetch_sub(&pool->refs, 1) != 1)
        return;

    vlc_cond_destroy(&pool->wait);
    vlc_mutex_destroy(&pool->lock);
    aligned_free(pool);
}

void picture_pool_Release(picture_pool_t *pool)
{
    for (unsigned i = 0; i < pool->picture_count; i++)
        picture_Release(pool->picture[i]);
    picture_pool_Destroy(pool);
}

static void picture_pool_ReleasePicture(picture_t *clone)
{
    picture_priv_t *priv = (picture_priv_t *)clone;
    uintptr_t sys = (uintptr_t)priv->gc.opaque;
    picture_pool_t *pool = (void *)(sys & ~(POOL_MAX - 1));
    unsigned offset = sys & (POOL_MAX - 1);
    picture_t *picture = pool->picture[offset];

    free(clone);

    if (pool->pic_unlock != NULL)
        pool->pic_unlock(picture);
    picture_Release(picture);

    vlc_mutex_lock(&pool->lock);
    assert(!pool_avail_test(pool, offset));
    pool_avail_set(pool, offset);
    vlc_cond_signal(&pool->wait);
    vlc_mutex_unlock(&pool->lock);

    picture_pool_Destroy(pool);
}

static picture_t *picture_pool_ClonePicture(picture_pool_t *pool,
                                            unsigned offset)
{
    picture_t *picture = pool->picture[offset];
    uintptr_t sys = ((uintptr_t)pool) + offset;
    picture_resource_t res = {
        .p_sys = picture->p_sys,
        .pf_destroy = picture_pool_ReleasePicture,
    };

    for (int i = 0; i < picture->i_planes; i++) {
        res.p[i].p_pixels = picture->p[i].p_pixels;
        res.p[i].i_lines = picture->p[i].i_lines;
        res.p[i].i_pitch = picture->p[i].i_pitch;
    }

    picture_t *clone = picture_NewFromResource(&picture->format, &res);
    if (likely(clone != NULL)) {
        ((picture_priv_t *)clone)->gc.opaque = (void *)sys;
        picture_Hold(picture);
    }
    return clone;
}

picture_pool_t *picture_pool_NewExtended(const picture_pool_configuration_t *cfg)
{
    if (unlikely(cfg->picture_count > POOL_MAX))
        return NULL;

    picture_pool_t *pool;
    size_t size = sizeof (*pool) + cfg->picture_count * sizeof (picture_t *);

    size += (-size) & (POOL_MAX - 1);
    pool = aligned_alloc(POOL_MAX, size);
    if (unlikely(pool == NULL))
        return NULL;

    pool->pic_lock   = cfg->lock;
    pool->pic_unlock = cfg->unlock;
    vlc_mutex_init(&pool->lock);
    vlc_cond_init(&pool->wait);
    for (unsigned w = 0, n = cfg->picture_count; w < POOL_WORDS; w++) {
        if (n >= POOL_WORD_BITS) {
            pool->available[w] = ~0ULL;
            n -= POOL_WORD_BITS;
        } else {
            pool->available[w] = n ? (1ULL << n) - 1 : 0;
            n = 0;
        }
    }
    atomic_init(&pool->refs,  1);
    pool->picture_count = cfg->picture_count;
    memcpy(pool->picture, cfg->picture,
           cfg->picture_count * sizeof (picture_t *));
    pool->canceled = false;
    return pool;
}

picture_pool_t *picture_pool_New(unsigned count, picture_t *const *tab)
{
    picture_pool_configuration_t cfg = {
        .picture_count = count,
        .picture = tab,
    };

    return picture_pool_NewExtended(&cfg);
}

picture_pool_t *picture_pool_NewFromFormat(const video_format_t *fmt,
                                           unsigned count)
{
    picture_t *picture[count ? count : 1];
    unsigned i;

    for (i = 0; i < count; i++) {
        picture[i] = picture_NewFromFormat(fmt);
        if (picture[i] == NULL)
            goto error;
    }

    picture_pool_t *pool = picture_pool_New(count, picture);
    if (!pool)
        goto error;

    return pool;

error:
    while (i > 0)
        picture_Release(picture[--i]);
    return NULL;
}

picture_pool_t *picture_pool_Reserve(picture_pool_t *master, unsigned count)
{
    picture_t *picture[count ? count : 1];
    unsigned i;

    for (i = 0; i < count; i++) {
        picture[i] = picture_pool_Get(master);
        if (picture[i] == NULL)
            goto error;
    }

    picture_pool_t *pool = picture_pool_New(count, picture);
    if (!pool)
        goto error;

    return pool;

error:
    while (i > 0)
        picture_Release(picture[--i]);
    return NULL;
}

picture_t *picture_pool_Get(picture_pool_t *pool)
{
    vlc_mutex_lock(&pool->lock);
    assert(pool->refs > 0);

    if (pool->canceled)
    {
        vlc_mutex_unlock(&pool->lock);
        return NULL;
    }

    for (unsigned i = pool_avail_next(pool, 0); i;
         i = pool_avail_next(pool, i))
    {
        pool_avail_clear(pool, i - 1);
        vlc_mutex_unlock(&pool->lock);

        picture_t *picture = pool->picture[i - 1];

        if (pool->pic_lock != NULL && pool->pic_lock(picture) != VLC_SUCCESS) {
            vlc_mutex_lock(&pool->lock);
            pool_avail_set(pool, i - 1);
            continue;
        }

        picture_t *clone = picture_pool_ClonePicture(pool, i - 1);
        if (clone != NULL) {
            assert(clone->p_next == NULL);
            atomic_fetch_add(&pool->refs, 1);
        }
        return clone;
    }

    vlc_mutex_unlock(&pool->lock);
    return NULL;
}

picture_t *picture_pool_Wait(picture_pool_t *pool)
{
    unsigned i;

    vlc_mutex_lock(&pool->lock);
    assert(pool->refs > 0);

    while (pool_avail_empty(pool))
    {
        if (pool->canceled)
        {
            vlc_mutex_unlock(&pool->lock);
            return NULL;
        }
        vlc_cond_wait(&pool->wait, &pool->lock);
    }

    i = pool_avail_next(pool, 0);
    assert(i > 0);
    pool_avail_clear(pool, i - 1);
    vlc_mutex_unlock(&pool->lock);

    picture_t *picture = pool->picture[i - 1];

    if (pool->pic_lock != NULL && pool->pic_lock(picture) != VLC_SUCCESS) {
        vlc_mutex_lock(&pool->lock);
        pool_avail_set(pool, i - 1);
        vlc_cond_signal(&pool->wait);
        vlc_mutex_unlock(&pool->lock);
        return NULL;
    }

    picture_t *clone = picture_pool_ClonePicture(pool, i - 1);
    if (clone != NULL) {
        assert(clone->p_next == NULL);
        atomic_fetch_add(&pool->refs, 1);
    }
    return clone;
}

void picture_pool_Cancel(picture_pool_t *pool, bool canceled)
{
    vlc_mutex_lock(&pool->lock);
    assert(pool->refs > 0);

    pool->canceled = canceled;
    if (canceled)
        vlc_cond_broadcast(&pool->wait);
    vlc_mutex_unlock(&pool->lock);
}

bool picture_pool_OwnsPic(picture_pool_t *pool, picture_t *pic)
{
    picture_priv_t *priv = (picture_priv_t *)pic;

    while (priv->gc.destroy != picture_pool_ReleasePicture) {
        pic = priv->gc.opaque;
        priv = (picture_priv_t *)pic;
    }

    uintptr_t sys = (uintptr_t)priv->gc.opaque;
    picture_pool_t *picpool = (void *)(sys & ~(POOL_MAX - 1));
    return pool == picpool;
}

unsigned picture_pool_GetSize(const picture_pool_t *pool)
{
    return pool->picture_count;
}

void picture_pool_Enum(picture_pool_t *pool, void (*cb)(void *, picture_t *),
                       void *opaque)
{
    /* NOTE: So far, the pictures table cannot change after the pool is created
     * so there is no need to lock the pool mutex here. */
    for (unsigned i = 0; i < pool->picture_count; i++)
        cb(opaque, pool->picture[i]);
}
