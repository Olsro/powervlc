/*****************************************************************************
 * darwin_memmem.c: memmem() for Mac OS X releases older than 10.7
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

/* memmem() only exists in libSystem since Mac OS X 10.7. When built against
 * a modern SDK with an older deployment target, the symbol is weak-linked
 * and resolves to NULL at run time, so any library calling it (the gnutls
 * and srt contribs do) jumps to address zero. Providing the function in the
 * plugin itself makes the linker bind those calls locally. */

#ifdef __APPLE__
# include <AvailabilityMacros.h>
# if MAC_OS_X_VERSION_MIN_REQUIRED < 1070

#include <string.h>

void *memmem(const void *haystack, size_t haystack_len,
             const void *needle, size_t needle_len);

void *memmem(const void *haystack, size_t haystack_len,
             const void *needle, size_t needle_len)
{
    if (needle_len == 0)
        return (void *)haystack;
    if (haystack_len < needle_len)
        return NULL;

    const char *h = haystack;
    const char *last = h + haystack_len - needle_len;
    for (; h <= last; h++)
        if (h[0] == ((const char *)needle)[0]
            && !memcmp(h, needle, needle_len))
            return (void *)h;
    return NULL;
}

/* strnlen() is missing from old libSystem as well (gnutls calls it) */
size_t strnlen(const char *s, size_t maxlen);

size_t strnlen(const char *s, size_t maxlen)
{
    const char *p = memchr(s, '\0', maxlen);
    return p != NULL ? (size_t)(p - s) : maxlen;
}

# endif
#endif
