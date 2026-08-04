/*****************************************************************************
 * unicode.c: Unicode <-> locale functions
 *****************************************************************************
 * Copyright (C) 2005-2006 VLC authors and VideoLAN
 * Copyright © 2005-2010 Rémi Denis-Courmont
 *
 * Authors: Rémi Denis-Courmont
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

/*****************************************************************************
 * Preamble
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>

#include "libvlc.h"
#include <vlc_charset.h>

#include <assert.h>

#include <stdio.h>
#include <stdarg.h>
#include <stdlib.h>
#include <sys/types.h>
#if defined(_WIN32)
#  include <io.h>
#endif
#include <errno.h>
#include <wctype.h>

/**
 * Formats an UTF-8 string as vfprintf(), then print it, with
 * appropriate conversion to local encoding.
 */
int utf8_vfprintf( FILE *stream, const char *fmt, va_list ap )
{
#ifndef _WIN32
    return vfprintf (stream, fmt, ap);
#else
    char *str;
    int res = vasprintf (&str, fmt, ap);
    if (unlikely(res == -1))
        return -1;

#if !VLC_WINSTORE_APP
    /* Writing to the console is a lot of fun on Microsoft Windows.
     * If you use the standard I/O functions, you must use the OEM code page,
     * which is different from the usual ANSI code page. Or maybe not, if the
     * user called "chcp". Anyway, we prefer Unicode. */
    int fd = _fileno (stream);
    if (likely(fd != -1) && _isatty (fd))
    {
        wchar_t *wide = ToWide (str);
        if (likely(wide != NULL))
        {
            HANDLE h = (HANDLE)((uintptr_t)_get_osfhandle (fd));
            DWORD out;
            /* XXX: It is not clear whether WriteConsole() wants the number of
             * Unicode characters or the size of the wchar_t array. */
            BOOL ok = WriteConsoleW (h, wide, wcslen (wide), &out, NULL);
            free (wide);
            if (ok)
                goto out;
        }
    }
#endif
    wchar_t *wide = ToWide(str);
    if (likely(wide != NULL))
    {
        res = fputws(wide, stream);
        free(wide);
    }
    else
        res = -1;
out:
    free (str);
    return res;
#endif
}

/**
 * Formats an UTF-8 string as fprintf(), then print it, with
 * appropriate conversion to local encoding.
 */
int utf8_fprintf( FILE *stream, const char *fmt, ... )
{
    va_list ap;
    int res;

    va_start( ap, fmt );
    res = utf8_vfprintf( stream, fmt, ap );
    va_end( ap );
    return res;
}

size_t vlc_towc (const char *str, uint32_t *restrict pwc)
{
    uint8_t *ptr = (uint8_t *)str, c;
    uint32_t cp;

    assert (str != NULL);

    c = *ptr;
    if (unlikely(c > 0xF4))
        return -1;

    int charlen = clz8 (c ^ 0xFF);
    switch (charlen)
    {
        case 0: // 7-bit ASCII character -> short cut
            *pwc = c;
            return c != '\0';

        case 1: // continuation byte -> error
            return -1;

        case 2:
            if (unlikely(c < 0xC2)) // ASCII overlong
                return -1;
            cp = (c & 0x1F) << 6;
            break;

        case 3:
            cp = (c & 0x0F) << 12;
            break;

        case 4:
            cp = (c & 0x07) << 18;
            break;

        default:
            vlc_assert_unreachable ();
    }

    /* Unrolled continuation bytes decoding */
    switch (charlen)
    {
        case 4:
            c = *++ptr;
            if (unlikely((c & 0xC0) != 0x80)) // not a continuation byte
                return -1;
            cp |= (c & 0x3F) << 12;

            if (unlikely(cp >= 0x110000)) // beyond Unicode range
                return -1;
            /* fall through */
        case 3:
            c = *++ptr;
            if (unlikely((c & 0xC0) != 0x80)) // not a continuation byte
                return -1;
            cp |= (c & 0x3F) << 6;

            if (unlikely(cp >= 0xD800 && cp < 0xE000)) // UTF-16 surrogate
                return -1;
            if (unlikely(cp < (1u << (5 * charlen - 4)))) // non-ASCII overlong
                return -1;
            /* fall through */
        case 2:
            c = *++ptr;
            if (unlikely((c & 0xC0) != 0x80)) // not a continuation byte
                return -1;
            cp |= (c & 0x3F);
            break;
    }

    *pwc = cp;
    return charlen;
}

/**
 * Look for an UTF-8 string within another one in a case-insensitive fashion.
 * Beware that this is quite slow. Contrary to strcasestr(), this function
 * works regardless of the system character encoding, and handles multibyte
 * code points correctly.

 * @param haystack string to look into
 * @param needle string to look for
 * @return a pointer to the first occurrence of the needle within the haystack,
 * or NULL if no occurrence were found.
 */
char *vlc_strcasestr (const char *haystack, const char *needle)
{
    ssize_t s;

    do
    {
        const char *h = haystack, *n = needle;

        for (;;)
        {
            uint32_t cph, cpn;

            s = vlc_towc (n, &cpn);
            if (s == 0)
                return (char *)haystack;
            if (unlikely(s < 0))
                return NULL;
            n += s;

            s = vlc_towc (h, &cph);
            if (s <= 0 || towlower (cph) != towlower (cpn))
                break;
            h += s;
        }

        s = vlc_towc (haystack, &(uint32_t) { 0 });
        haystack += s;
    }
    while (s > 0);

    return NULL;
}

/* ASCII stand-in for the Latin-1 supplement, U+00C0 to U+00FF.
 * NULL where the code point is not a letter (multiplication and division
 * signs), so that it goes through the general path. */
static const char *const latin1_fold[0x40] = {
    "a", "a", "a", "a", "a", "a", "ae", "c",    /* U+00C0 */
    "e", "e", "e", "e", "i", "i", "i", "i",     /* U+00C8 */
    "d", "n", "o", "o", "o", "o", "o", NULL,    /* U+00D0 */
    "o", "u", "u", "u", "u", "y", "th", "ss",   /* U+00D8 */
    "a", "a", "a", "a", "a", "a", "ae", "c",    /* U+00E0 */
    "e", "e", "e", "e", "i", "i", "i", "i",     /* U+00E8 */
    "d", "n", "o", "o", "o", "o", "o", NULL,    /* U+00F0 */
    "o", "u", "u", "u", "u", "y", "th", "y",    /* U+00F8 */
};

/* Latin Extended-A, U+0100 to U+017F: one base letter each. The two
 * ligatures of the block (U+0132 IJ and U+0152 OE) expand to two letters
 * and are handled apart; their slots here are never read. */
static const char latinA_fold[] =
    "aaaaaa"        /* U+0100 A with macron..A with ogonek */
    "cccccccc"      /* U+0106 C with acute..C with caron */
    "dddd"          /* U+010E D with caron..D with stroke */
    "eeeeeeeeee"    /* U+0112 E with macron..E with caron */
    "gggggggg"      /* U+011C G with circumflex..G with cedilla */
    "hhhh"          /* U+0124 H with circumflex..H with stroke */
    "iiiiiiiiii"    /* U+0128 I with tilde..dotless i */
    "ij"            /* U+0132 IJ ligature (see above) */
    "jj"            /* U+0134 J with circumflex */
    "kkk"           /* U+0136 K with cedilla..kra */
    "llllllllll"    /* U+0139 L with acute..l with stroke */
    "nnnnnnnnn"     /* U+0143 N with acute..eng */
    "oooooo"        /* U+014C O with macron..o with double acute */
    "oe"            /* U+0152 OE ligature (see above) */
    "rrrrrr"        /* U+0154 R with acute..r with caron */
    "ssssssss"      /* U+015A S with acute..s with caron */
    "tttttt"        /* U+0162 T with cedilla..t with stroke */
    "uuuuuuuuuuuu"  /* U+0168 U with tilde..u with ogonek */
    "ww"            /* U+0174 W with circumflex */
    "yyy"           /* U+0176 Y with circumflex..Y with diaeresis */
    "zzzzzz"        /* U+0179 Z with acute..z with caron */
    "s";            /* U+017F long s */

/* The ASCII equivalent of a code point, or NULL when there is none and
 * the code point must be kept as it is. An empty string drops it. */
static const char *FoldCodePoint (uint32_t cp, char *scratch)
{
    if (cp < 0x80)
    {   /* plain ASCII, only the case has to go */
        scratch[0] = (cp >= 'A' && cp <= 'Z') ? (char)(cp + ('a' - 'A'))
                                              : (char)cp;
        scratch[1] = '\0';
        return scratch;
    }

    /* combining marks: a decomposed "e" + acute accent must fold to the
     * same thing as the precomposed "é" */
    if (cp >= 0x0300 && cp <= 0x036F)
        return "";

    if (cp >= 0x00C0 && cp <= 0x00FF)
        return latin1_fold[cp - 0x00C0];

    if (cp >= 0x0100 && cp <= 0x017F)
    {
        if (cp == 0x0132 || cp == 0x0133)
            return "ij";
        if (cp == 0x0152 || cp == 0x0153)
            return "oe";
        scratch[0] = latinA_fold[cp - 0x0100];
        scratch[1] = '\0';
        return scratch;
    }

    switch (cp)
    {   /* typographic punctuation, as typed on a keyboard */
        case 0x00AB: case 0x00BB:                       /* angle quotes */
        case 0x201C: case 0x201D: case 0x201E: case 0x201F:
            return "\"";
        case 0x2018: case 0x2019: case 0x201A: case 0x201B:
            return "'";
        case 0x2010: case 0x2011: case 0x2012: case 0x2013:
        case 0x2014: case 0x2015:                       /* dashes */
            return "-";
        case 0x2026:                                    /* ellipsis */
            return "...";
        case 0x00A0: case 0x202F: case 0x205F:          /* fixed spaces */
            return " ";
    }
    if (cp >= 0x2000 && cp <= 0x200A)                   /* en/em spaces */
        return " ";

    return NULL;
}

/**
 * Folds an UTF-8 string down to a form fit for searching: case, accents,
 * Latin ligatures and typographic punctuation are all reduced to plain
 * lower-case ASCII wherever an equivalent exists, so that a search for
 * "au coeur de l'histoire" finds "Au Cœur de l’Histoire".
 *
 * Only the Latin blocks are covered; anything else is passed through
 * unchanged, so a search in a script this does not know still behaves as
 * an exact substring search.
 *
 * @param str string to fold
 * @return a nul-terminated folded UTF-8 string, to be freed with free(),
 * or NULL on allocation failure.
 */
char *vlc_strfold (const char *str)
{
    /* no folding lengthens a code point, but the reserve costs nothing
     * next to being wrong about it */
    size_t size = strlen (str) * 3 + 1;
    char *out = malloc (size);
    if (unlikely(out == NULL))
        return NULL;

    char *dst = out;
    for (;;)
    {
        uint32_t cp;
        ssize_t s = vlc_towc (str, &cp);

        if (s == 0)
            break;
        if (unlikely(s < 0))
        {   /* not valid UTF-8: copy the byte over and carry on, the
             * caller is searching, not validating */
            *(dst++) = *(str++);
            continue;
        }

        char scratch[2];
        const char *fold = FoldCodePoint (cp, scratch);

        if (fold != NULL)
            while (*fold != '\0')
                *(dst++) = *(fold++);
        else
        {
            memcpy (dst, str, s);
            dst += s;
        }
        str += s;
    }
    *dst = '\0';
    return out;
}

/**
 * Converts a string from the given character encoding to utf-8.
 *
 * @return a nul-terminated utf-8 string, or null in case of error.
 * The result must be freed using free().
 */
char *FromCharset(const char *charset, const void *data, size_t data_size)
{
    vlc_iconv_t handle = vlc_iconv_open ("UTF-8", charset);
    if (handle == (vlc_iconv_t)(-1))
        return NULL;

    char *out = NULL;
    for(unsigned mul = 4; mul < 8; mul++ )
    {
        size_t in_size = data_size;
        const char *in = data;
        size_t out_max = mul * data_size;
        char *tmp = out = malloc (1 + out_max);
        if (!out)
            break;

        if (vlc_iconv (handle, &in, &in_size, &tmp, &out_max) != (size_t)(-1)) {
            *tmp = '\0';
            break;
        }
        free(out);
        out = NULL;

        if (errno != E2BIG)
            break;
    }
    vlc_iconv_close(handle);
    return out;
}

/**
 * Converts a nul-terminated UTF-8 string to a given character encoding.
 * @param charset iconv name of the character set
 * @param in nul-terminated UTF-8 string
 * @param outsize pointer to hold the byte size of result
 *
 * @return A pointer to the result, which must be released using free().
 * The UTF-8 nul terminator is included in the conversion if the target
 * character encoding supports it. However it is not included in the returned
 * byte size.
 * In case of error, NULL is returned and the byte size is undefined.
 */
void *ToCharset(const char *charset, const char *in, size_t *outsize)
{
    vlc_iconv_t hd = vlc_iconv_open (charset, "UTF-8");
    if (hd == (vlc_iconv_t)(-1))
        return NULL;

    const size_t inlen = strlen (in);
    void *res;

    for (unsigned mul = 4; mul < 16; mul++)
    {
        size_t outlen = mul * (inlen + 1);
        res = malloc (outlen);
        if (unlikely(res == NULL))
            break;

        const char *inp = in;
        char *outp = res;
        size_t inb = inlen;
        size_t outb = outlen - mul;

        if (vlc_iconv (hd, &inp, &inb, &outp, &outb) != (size_t)(-1))
        {
            *outsize = outlen - mul - outb;
            outb += mul;
            inb = 1; /* append nul terminator if possible */
            if (vlc_iconv (hd, &inp, &inb, &outp, &outb) != (size_t)(-1))
                break;
            if (errno == EILSEQ) /* cannot translate nul terminator!? */
                break;
        }

        free (res);
        res = NULL;
        if (errno != E2BIG) /* conversion failure */
            break;
    }
    vlc_iconv_close (hd);
    return res;
}

