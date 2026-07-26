/*****************************************************************************
 * aligned_alloc.c: C11 aligned_alloc() replacement
 *****************************************************************************
 * Copyright © 2012, 2017 Rémi Denis-Courmont
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

#include <assert.h>
#include <stdlib.h>
#include <errno.h>
#include <stdint.h>
#if !defined (HAVE_POSIX_MEMALIGN) && defined (HAVE_MEMALIGN)
# include <malloc.h>
#endif

#if !defined (HAVE_POSIX_MEMALIGN) && !defined (HAVE_MEMALIGN) \
 && !(defined (_WIN32) && (defined (__MINGW32__) || defined (_MSC_VER)))
/* No native aligned allocator at all (e.g. Mac OS X before 10.6):
 * over-allocate and align manually, stashing the real malloc()'d
 * pointer just before the block returned to the caller so that
 * vlc_aligned_free() can recover and release it. */
# define VLC_ALIGNED_ALLOC_FALLBACK 1
#endif

/* Same rename as vlc_fixups.h applies to the CALLERS: on Apple targets the
 * SDK always declares aligned_alloc() with __OSX_AVAILABLE(10.15), so a
 * deployment target below that cannot name it -- the header points callers
 * at vlc_aligned_alloc() instead. The definition has to follow, or every
 * pre-10.15 build links against a symbol nothing provides. Placed after the
 * system headers on purpose, so the SDK's own declaration is left alone. */
#if defined (__APPLE__) && defined (__clang__)
# define aligned_alloc vlc_aligned_alloc
#endif

void *aligned_alloc(size_t align, size_t size)
{
    /* align must be a power of 2 */
    /* size must be a multiple of align */
    if ((align & (align - 1)) || (size & (align - 1)))
    {
        errno = EINVAL;
        return NULL;
    }

#ifdef HAVE_POSIX_MEMALIGN
    if (align < sizeof (void *)) /* POSIX does not allow small alignment */
        align = sizeof (void *);

    void *ptr;
    int err = posix_memalign(&ptr, align, size);
    if (err)
    {
        errno = err;
        ptr = NULL;
    }
    return ptr;

#elif defined(HAVE_MEMALIGN)
    return memalign(align, size);
#elif defined (_WIN32) && defined(__MINGW32__)
    return __mingw_aligned_malloc(size, align);
#elif defined (_WIN32) && defined(_MSC_VER)
    return _aligned_malloc(size, align);
#elif defined (VLC_ALIGNED_ALLOC_FALLBACK)
    if (align < sizeof (void *))
        align = sizeof (void *);

    void *base = malloc(size + align - 1 + sizeof (void *));
    if (base == NULL)
        return NULL;

    uintptr_t aligned = ((uintptr_t)base + sizeof (void *) + align - 1)
                       & ~(uintptr_t)(align - 1);
    ((void **)aligned)[-1] = base;
    return (void *)aligned;
#else
#warning unsupported aligned allocation!
    if (size > 0)
        errno = ENOMEM;
    return NULL;
#endif
}

#ifdef VLC_ALIGNED_ALLOC_FALLBACK
void vlc_aligned_free(void *ptr)
{
    if (ptr != NULL)
        free(((void **)ptr)[-1]);
}
#endif
