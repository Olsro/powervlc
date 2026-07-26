/*****************************************************************************
 * algo_x.c : "X" algorithm for vlc deinterlacer
 *****************************************************************************
 * Copyright (C) 2000-2011 VLC authors and VideoLAN
 * $Id$
 *
 * Author: Laurent Aimar <fenrir@videolan.org>
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
#   include "config.h"
#endif

#ifdef CAN_COMPILE_MMXEXT
#   include "mmx.h"
#endif

#include <stdint.h>

#include <vlc_common.h>
#include <vlc_cpu.h>
#include <vlc_picture.h>

#include "deinterlace.h" /* filter_sys_t */

#include "algo_x.h"

#ifdef CAN_COMPILE_C_ALTIVEC
#   ifdef HAVE_ALTIVEC_H
#       include <altivec.h>
#   endif
/* altivec.h (FSF GCC) redefines 'vector', 'pixel' and 'bool' as macros;
 * undo that so the plain C parts of this file keep the C99 meaning of
 * 'bool'.  The AltiVec code below spells the types __vector/__bool. */
#   undef vector
#   undef pixel
#   undef bool
#   define bool _Bool
#endif

/*****************************************************************************
 * Internal functions
 *****************************************************************************/

/* XDeint8x8Detect: detect if a 8x8 block is interlaced.
 * XXX: It need to access to 8x10
 * We use more than 8 lines to help with scrolling (text)
 * (and because XDeint8x8Frame use line 9)
 * XXX: smooth/uniform area with noise detection doesn't works well
 * but it's not really a problem because they don't have much details anyway
 */
static inline int ssd( int a ) { return a*a; }
static inline int XDeint8x8DetectC( uint8_t *src, int i_src )
{
    int y, x;
    int ff, fr;
    int fc;

    /* Detect interlacing */
    fc = 0;
    for( y = 0; y < 7; y += 2 )
    {
        ff = fr = 0;
        for( x = 0; x < 8; x++ )
        {
            fr += ssd(src[      x] - src[1*i_src+x]) +
                  ssd(src[i_src+x] - src[2*i_src+x]);
            ff += ssd(src[      x] - src[2*i_src+x]) +
                  ssd(src[i_src+x] - src[3*i_src+x]);
        }
        if( ff < 6*fr/8 && fr > 32 )
            fc++;

        src += 2*i_src;
    }

    return fc < 1 ? false : true;
}
#ifdef CAN_COMPILE_MMXEXT
VLC_MMX
static inline int XDeint8x8DetectMMXEXT( uint8_t *src, int i_src )
{

    int y, x;
    int32_t ff, fr;
    int fc;

    /* Detect interlacing */
    fc = 0;
    pxor_r2r( mm7, mm7 );
    for( y = 0; y < 9; y += 2 )
    {
        ff = fr = 0;
        pxor_r2r( mm5, mm5 );
        pxor_r2r( mm6, mm6 );
        for( x = 0; x < 8; x+=4 )
        {
            movd_m2r( src[        x], mm0 );
            movd_m2r( src[1*i_src+x], mm1 );
            movd_m2r( src[2*i_src+x], mm2 );
            movd_m2r( src[3*i_src+x], mm3 );

            punpcklbw_r2r( mm7, mm0 );
            punpcklbw_r2r( mm7, mm1 );
            punpcklbw_r2r( mm7, mm2 );
            punpcklbw_r2r( mm7, mm3 );

            movq_r2r( mm0, mm4 );

            psubw_r2r( mm1, mm0 );
            psubw_r2r( mm2, mm4 );

            psubw_r2r( mm1, mm2 );
            psubw_r2r( mm1, mm3 );

            pmaddwd_r2r( mm0, mm0 );
            pmaddwd_r2r( mm4, mm4 );
            pmaddwd_r2r( mm2, mm2 );
            pmaddwd_r2r( mm3, mm3 );
            paddd_r2r( mm0, mm2 );
            paddd_r2r( mm4, mm3 );
            paddd_r2r( mm2, mm5 );
            paddd_r2r( mm3, mm6 );
        }

        movq_r2r( mm5, mm0 );
        psrlq_i2r( 32, mm0 );
        paddd_r2r( mm0, mm5 );
        movd_r2m( mm5, fr );

        movq_r2r( mm6, mm0 );
        psrlq_i2r( 32, mm0 );
        paddd_r2r( mm0, mm6 );
        movd_r2m( mm6, ff );

        if( ff < 6*fr/8 && fr > 32 )
            fc++;

        src += 2*i_src;
    }
    return fc;
}
#endif

static inline void XDeint8x8MergeC( uint8_t *dst,  int i_dst,
                                    uint8_t *src1, int i_src1,
                                    uint8_t *src2, int i_src2 )
{
    int y, x;

    /* Progressive */
    for( y = 0; y < 8; y += 2 )
    {
        memcpy( dst, src1, 8 );
        dst  += i_dst;

        for( x = 0; x < 8; x++ )
            dst[x] = (src1[x] + 6*src2[x] + src1[i_src1+x] + 4 ) >> 3;
        dst += i_dst;

        src1 += i_src1;
        src2 += i_src2;
    }
}

#ifdef CAN_COMPILE_MMXEXT
VLC_MMX
static inline void XDeint8x8MergeMMXEXT( uint8_t *dst,  int i_dst,
                                         uint8_t *src1, int i_src1,
                                         uint8_t *src2, int i_src2 )
{
    static const uint64_t m_4 = INT64_C(0x0004000400040004);
    int y, x;

    /* Progressive */
    pxor_r2r( mm7, mm7 );
    for( y = 0; y < 8; y += 2 )
    {
        for( x = 0; x < 8; x +=4 )
        {
            movd_m2r( src1[x], mm0 );
            movd_r2m( mm0, dst[x] );

            movd_m2r( src2[x], mm1 );
            movd_m2r( src1[i_src1+x], mm2 );

            punpcklbw_r2r( mm7, mm0 );
            punpcklbw_r2r( mm7, mm1 );
            punpcklbw_r2r( mm7, mm2 );
            paddw_r2r( mm1, mm1 );
            movq_r2r( mm1, mm3 );
            paddw_r2r( mm3, mm3 );
            paddw_r2r( mm2, mm0 );
            paddw_r2r( mm3, mm1 );
            paddw_m2r( m_4, mm1 );
            paddw_r2r( mm1, mm0 );
            psraw_i2r( 3, mm0 );
            packuswb_r2r( mm7, mm0 );
            movd_r2m( mm0, dst[i_dst+x] );
        }
        dst += 2*i_dst;
        src1 += i_src1;
        src2 += i_src2;
    }
}

#endif

/* XDeint8x8FieldE: Stupid deinterlacing (1,0,1) for block that miss a
 * neighbour
 * (Use 8x9 pixels)
 * TODO: a better one for the inner part.
 */
static inline void XDeint8x8FieldEC( uint8_t *dst, int i_dst,
                                     uint8_t *src, int i_src )
{
    int y, x;

    /* Interlaced */
    for( y = 0; y < 8; y += 2 )
    {
        memcpy( dst, src, 8 );
        dst += i_dst;

        for( x = 0; x < 8; x++ )
            dst[x] = (src[x] + src[2*i_src+x] ) >> 1;
        dst += 1*i_dst;
        src += 2*i_src;
    }
}

#ifdef CAN_COMPILE_MMXEXT
VLC_MMX
static inline void XDeint8x8FieldEMMXEXT( uint8_t *dst, int i_dst,
                                          uint8_t *src, int i_src )
{
    int y;

    /* Interlaced */
    for( y = 0; y < 8; y += 2 )
    {
        movq_m2r( src[0], mm0 );
        movq_r2m( mm0, dst[0] );
        dst += i_dst;

        movq_m2r( src[2*i_src], mm1 );
        pavgb_r2r( mm1, mm0 );

        movq_r2m( mm0, dst[0] );

        dst += 1*i_dst;
        src += 2*i_src;
    }
}
#endif

/* XDeint8x8Field: Edge oriented interpolation
 * (Need -4 and +5 pixels H, +1 line)
 */
static inline void XDeint8x8FieldC( uint8_t *dst, int i_dst,
                                    uint8_t *src, int i_src )
{
    int y, x;

    /* Interlaced */
    for( y = 0; y < 8; y += 2 )
    {
        memcpy( dst, src, 8 );
        dst += i_dst;

        for( x = 0; x < 8; x++ )
        {
            uint8_t *src2 = &src[2*i_src];
            /* I use 8 pixels just to match the MMX version, but it's overkill
             * 5 would be enough (less isn't good) */
            const int c0 = abs(src[x-4]-src2[x-2]) + abs(src[x-3]-src2[x-1]) +
                           abs(src[x-2]-src2[x+0]) + abs(src[x-1]-src2[x+1]) +
                           abs(src[x+0]-src2[x+2]) + abs(src[x+1]-src2[x+3]) +
                           abs(src[x+2]-src2[x+4]) + abs(src[x+3]-src2[x+5]);

            const int c1 = abs(src[x-3]-src2[x-3]) + abs(src[x-2]-src2[x-2]) +
                           abs(src[x-1]-src2[x-1]) + abs(src[x+0]-src2[x+0]) +
                           abs(src[x+1]-src2[x+1]) + abs(src[x+2]-src2[x+2]) +
                           abs(src[x+3]-src2[x+3]) + abs(src[x+4]-src2[x+4]);

            const int c2 = abs(src[x-2]-src2[x-4]) + abs(src[x-1]-src2[x-3]) +
                           abs(src[x+0]-src2[x-2]) + abs(src[x+1]-src2[x-1]) +
                           abs(src[x+2]-src2[x+0]) + abs(src[x+3]-src2[x+1]) +
                           abs(src[x+4]-src2[x+2]) + abs(src[x+5]-src2[x+3]);

            if( c0 < c1 && c1 <= c2 )
                dst[x] = (src[x-1] + src2[x+1]) >> 1;
            else if( c2 < c1 && c1 <= c0 )
                dst[x] = (src[x+1] + src2[x-1]) >> 1;
            else
                dst[x] = (src[x+0] + src2[x+0]) >> 1;
        }

        dst += 1*i_dst;
        src += 2*i_src;
    }
}

#ifdef CAN_COMPILE_MMXEXT
VLC_MMX
static inline void XDeint8x8FieldMMXEXT( uint8_t *dst, int i_dst,
                                         uint8_t *src, int i_src )
{
    int y, x;

    /* Interlaced */
    for( y = 0; y < 8; y += 2 )
    {
        memcpy( dst, src, 8 );
        dst += i_dst;

        for( x = 0; x < 8; x++ )
        {
            uint8_t *src2 = &src[2*i_src];
            int32_t c0, c1, c2;

            movq_m2r( src[x-2], mm0 );
            movq_m2r( src[x-3], mm1 );
            movq_m2r( src[x-4], mm2 );

            psadbw_m2r( src2[x-4], mm0 );
            psadbw_m2r( src2[x-3], mm1 );
            psadbw_m2r( src2[x-2], mm2 );

            movd_r2m( mm0, c2 );
            movd_r2m( mm1, c1 );
            movd_r2m( mm2, c0 );

            if( c0 < c1 && c1 <= c2 )
                dst[x] = (src[x-1] + src2[x+1]) >> 1;
            else if( c2 < c1 && c1 <= c0 )
                dst[x] = (src[x+1] + src2[x-1]) >> 1;
            else
                dst[x] = (src[x+0] + src2[x+0]) >> 1;
        }

        dst += 1*i_dst;
        src += 2*i_src;
    }
}
#endif

#ifdef CAN_COMPILE_C_ALTIVEC
/*****************************************************************************
 * AltiVec versions of the 8x8 kernels.  They are bit-exact with the C
 * versions above (NOT with the MMXEXT ones, which use different rounding
 * and detection: the C versions are what runs on PowerPC otherwise).
 *
 * Safety of the vector memory accesses: the callers (see RenderX) only
 * select this path when, for both pictures, the plane base is 16-byte
 * aligned and the plane pitch is a multiple of 16 (always true for
 * pictures from VLC's allocator: 64-byte base alignment, pitch multiple
 * of 64).  Every 8x8 block therefore starts on an 8-byte boundary, the
 * plane allocation starts and ends on 16-byte boundaries, and any 16-byte
 * vec_ld container that overlaps a byte the C code reads lies entirely
 * inside the plane allocation, so no vector load can run past the buffer,
 * not even for the rightmost block of a row.  Stores write exactly the
 * 8 bytes the C code writes, using two 4-byte vec_ste stores (no
 * read-modify-write of neighbouring bytes).
 *****************************************************************************/

/* Load the 8 bytes at p (p must be 8-byte aligned) into lanes 0..7. */
VLC_ALTIVEC
static inline __vector unsigned char XDeintLoad8Altivec( const uint8_t *p )
{
    /* p being 8-byte aligned, the 8 bytes live in a single 16-byte
     * container; rotate them to the front. */
    const __vector unsigned char v = vec_ld( 0, p );
    return vec_perm( v, v, vec_lvsl( 0, p ) );
}

/* Store lanes 0..7 of v to the 8 bytes at dst (must be 8-byte aligned). */
VLC_ALTIVEC
static inline void XDeintStore8Altivec( uint8_t *dst, __vector unsigned char v )
{
    /* Rotate the 8 payload bytes to the position they occupy inside
     * dst's 16-byte container, then store the two 32-bit words. */
    v = vec_perm( v, v, vec_lvsr( 0, dst ) );
    vec_ste( (__vector unsigned int)v, 0, (unsigned int *)dst );
    vec_ste( (__vector unsigned int)v, 4, (unsigned int *)dst );
}

/* Truncating byte average (a+b)>>1.
 * vec_avg() rounds up and would NOT match the C code. */
VLC_ALTIVEC
static inline __vector unsigned char XDeintAvg8Altivec( __vector unsigned char a,
                                                        __vector unsigned char b )
{
    return vec_add( vec_and( a, b ),
                    vec_sr( vec_xor( a, b ), vec_splat_u8( 1 ) ) );
}

/* c[x] = sum(k=0..7) e[x+k] for x = 0..7, over the 16 16-bit lanes of
 * lo:hi.  Lane 15 is never read. */
VLC_ALTIVEC
static inline __vector unsigned short XDeintSlide8Altivec( __vector unsigned short lo,
                                                           __vector unsigned short hi )
{
    __vector unsigned short c;
    c = vec_add( lo, vec_sld( lo, hi,  2 ) );
    c = vec_add( c,  vec_sld( lo, hi,  4 ) );
    c = vec_add( c,  vec_sld( lo, hi,  6 ) );
    c = vec_add( c,  vec_sld( lo, hi,  8 ) );
    c = vec_add( c,  vec_sld( lo, hi, 10 ) );
    c = vec_add( c,  vec_sld( lo, hi, 12 ) );
    c = vec_add( c,  vec_sld( lo, hi, 14 ) );
    return c;
}

VLC_ALTIVEC
static inline int XDeint8x8DetectAltivec( uint8_t *src, int i_src )
{
    const __vector unsigned char zero8 = vec_splat_u8( 0 );
    const __vector signed int zero32 = vec_splat_s32( 0 );
    union { __vector signed int v; int32_t i[4]; } fru, ffu;
    __vector signed short r0, r1, r2, r3;
    int y;
    int fc;

/* One 8-pixel row, zero-extended to 16-bit lanes */
#define XDEINT_ROW16( p ) \
    ((__vector signed short)vec_mergeh( zero8, XDeintLoad8Altivec( p ) ))

    /* Detect interlacing */
    fc = 0;
    r0 = XDEINT_ROW16( &src[0*i_src] );
    r1 = XDEINT_ROW16( &src[1*i_src] );
    for( y = 0; y < 7; y += 2 )
    {
        __vector signed short d01, d12, d02, d13;

        r2 = XDEINT_ROW16( &src[2*i_src] );
        r3 = XDEINT_ROW16( &src[3*i_src] );

        d01 = vec_sub( r0, r1 );
        d12 = vec_sub( r1, r2 );
        d02 = vec_sub( r0, r2 );
        d13 = vec_sub( r1, r3 );

        /* Exact integer sums of squared differences: 8 * 2 * 255^2 fits
         * comfortably in 32 bits, so neither vec_msum nor the saturating
         * vec_sums can overflow. */
        fru.v = vec_sums( vec_msum( d12, d12, vec_msum( d01, d01, zero32 ) ),
                          zero32 );
        ffu.v = vec_sums( vec_msum( d13, d13, vec_msum( d02, d02, zero32 ) ),
                          zero32 );

        if( ffu.i[3] < 6*fru.i[3]/8 && fru.i[3] > 32 )
            fc++;

        r0 = r2;
        r1 = r3;
        src += 2*i_src;
    }
#undef XDEINT_ROW16

    return fc < 1 ? false : true;
}

VLC_ALTIVEC
static inline void XDeint8x8MergeAltivec( uint8_t *dst,  int i_dst,
                                          uint8_t *src1, int i_src1,
                                          uint8_t *src2, int i_src2 )
{
    const __vector unsigned char zero8 = vec_splat_u8( 0 );
    const __vector unsigned short six   = vec_splat_u16( 6 );
    const __vector unsigned short four  = vec_splat_u16( 4 );
    const __vector unsigned short three = vec_splat_u16( 3 );
    int y;

    /* Progressive */
    for( y = 0; y < 8; y += 2 )
    {
        __vector unsigned short a, b, c, t;

        memcpy( dst, src1, 8 );
        dst += i_dst;

        a = (__vector unsigned short)vec_mergeh( zero8,
                                                 XDeintLoad8Altivec( src1 ) );
        b = (__vector unsigned short)vec_mergeh( zero8,
                                                 XDeintLoad8Altivec( src2 ) );
        c = (__vector unsigned short)vec_mergeh( zero8,
                                          XDeintLoad8Altivec( &src1[i_src1] ) );

        /* (a + 6*b + c + 4) >> 3, max 2044 so exact in 16-bit lanes */
        t = vec_mladd( b, six, vec_add( vec_add( a, c ), four ) );
        t = vec_sr( t, three );
        XDeintStore8Altivec( dst, vec_pack( t, t ) );
        dst += i_dst;

        src1 += i_src1;
        src2 += i_src2;
    }
}

VLC_ALTIVEC
static inline void XDeint8x8FieldEAltivec( uint8_t *dst, int i_dst,
                                           uint8_t *src, int i_src )
{
    int y;

    /* Interlaced */
    for( y = 0; y < 8; y += 2 )
    {
        memcpy( dst, src, 8 );
        dst += i_dst;

        XDeintStore8Altivec( dst,
            XDeintAvg8Altivec( XDeintLoad8Altivec( src ),
                               XDeintLoad8Altivec( &src[2*i_src] ) ) );
        dst += 1*i_dst;
        src += 2*i_src;
    }
}

VLC_ALTIVEC
static inline void XDeint8x8FieldAltivec( uint8_t *dst, int i_dst,
                                          uint8_t *src, int i_src )
{
    const __vector unsigned char zero8 = vec_splat_u8( 0 );
    int y;

    /* Interlaced */
    for( y = 0; y < 8; y += 2 )
    {
        /* This function is only used on interior blocks (like the C
         * version), so src[-4..+13] of both lines stays inside the row's
         * pixels plus its neighbouring blocks. */
        const uint8_t *q1 = src - 4;
        const uint8_t *q2 = &src[2*i_src] - 4;
        __vector unsigned char s0, s2, t0, t2;
        __vector unsigned char e0, e1, e2;
        __vector unsigned short c0, c1, c2;
        __vector unsigned short m0, m2;
        __vector unsigned char b0, b2, res;

        memcpy( dst, src, 8 );
        dst += i_dst;

        {
            /* q1 and q2 have the same 16-byte misalignment (4 or 12,
             * the pitch being a multiple of 16), so lvsl cannot wrap and
             * two containers cover all 18 bytes of each line. */
            const __vector unsigned char perm0 = vec_lvsl( 0, q1 );
            const __vector unsigned char perm2 = vec_lvsl( 2, q1 );
            const __vector unsigned char l1a = vec_ld(  0, q1 );
            const __vector unsigned char l1b = vec_ld( 16, q1 );
            const __vector unsigned char l2a = vec_ld(  0, q2 );
            const __vector unsigned char l2b = vec_ld( 16, q2 );
            s0 = vec_perm( l1a, l1b, perm0 );  /* src [x-4 .. x+11] */
            s2 = vec_perm( l1a, l1b, perm2 );  /* src [x-2 .. x+13] */
            t0 = vec_perm( l2a, l2b, perm0 );  /* src2[x-4 .. x+11] */
            t2 = vec_perm( l2a, l2b, perm2 );  /* src2[x-2 .. x+13] */
        }

        /* Absolute differences along the three directions */
        e0 = vec_sub( vec_max( s0, t2 ), vec_min( s0, t2 ) );
        e1 = vec_sub( vec_max( s0, t0 ), vec_min( s0, t0 ) );
        e2 = vec_sub( vec_max( s2, t0 ), vec_min( s2, t0 ) );

        /* 8-tap sliding sums in 16-bit lanes (max 8*255, no overflow):
         * c0[x] = sum |src[x-4+k] - src2[x-2+k]|, k = 0..7
         * c1[x] = sum |src[x-3+k] - src2[x-3+k]|, k = 0..7
         * c2[x] = sum |src[x-2+k] - src2[x-4+k]|, k = 0..7 */
        c0 = XDeintSlide8Altivec(
                (__vector unsigned short)vec_mergeh( zero8, e0 ),
                (__vector unsigned short)vec_mergel( zero8, e0 ) );
        {
            const __vector unsigned short e1l =
                (__vector unsigned short)vec_mergeh( zero8, e1 );
            const __vector unsigned short e1h =
                (__vector unsigned short)vec_mergel( zero8, e1 );
            c1 = XDeintSlide8Altivec( vec_sld( e1l, e1h, 2 ),
                                      vec_sld( e1h, e1h, 2 ) );
        }
        c2 = XDeintSlide8Altivec(
                (__vector unsigned short)vec_mergeh( zero8, e2 ),
                (__vector unsigned short)vec_mergel( zero8, e2 ) );

        /* m0 = (c0 < c1) && (c1 <= c2);  m2 = (c2 < c1) && (c1 <= c0).
         * The two can never be true at once. */
        m0 = vec_andc( (__vector unsigned short)
                           vec_cmplt( (__vector signed short)c0,
                                      (__vector signed short)c1 ),
                       (__vector unsigned short)
                           vec_cmpgt( (__vector signed short)c1,
                                      (__vector signed short)c2 ) );
        m2 = vec_andc( (__vector unsigned short)
                           vec_cmplt( (__vector signed short)c2,
                                      (__vector signed short)c1 ),
                       (__vector unsigned short)
                           vec_cmpgt( (__vector signed short)c1,
                                      (__vector signed short)c0 ) );
        b0 = (__vector unsigned char)vec_pack( m0, m0 );
        b2 = (__vector unsigned char)vec_pack( m2, m2 );

        /* Candidates: center (src[x]+src2[x])>>1, then override with
         * right (src[x+1]+src2[x-1])>>1 where m2, and with left
         * (src[x-1]+src2[x+1])>>1 where m0. */
        res = XDeintAvg8Altivec( vec_sld( s0, s0, 4 ),
                                 vec_sld( t0, t0, 4 ) );
        res = vec_sel( res, XDeintAvg8Altivec( vec_sld( s0, s0, 5 ),
                                               vec_sld( t0, t0, 3 ) ), b2 );
        res = vec_sel( res, XDeintAvg8Altivec( vec_sld( s0, s0, 3 ),
                                               vec_sld( t0, t0, 5 ) ), b0 );

        XDeintStore8Altivec( dst, res );

        dst += 1*i_dst;
        src += 2*i_src;
    }
}
#endif

/* NxN arbitrary size (and then only use pixel in the NxN block)
 */
static inline int XDeintNxNDetect( uint8_t *src, int i_src,
                                   int i_height, int i_width )
{
    int y, x;
    int ff, fr;
    int fc;


    /* Detect interlacing */
    /* FIXME way too simple, need to be more like XDeint8x8Detect */
    ff = fr = 0;
    fc = 0;
    for( y = 0; y < i_height - 2; y += 2 )
    {
        const uint8_t *s = &src[y*i_src];
        for( x = 0; x < i_width; x++ )
        {
            fr += ssd(s[      x] - s[1*i_src+x]);
            ff += ssd(s[      x] - s[2*i_src+x]);
        }
        if( ff < fr && fr > i_width / 2 )
            fc++;
    }

    return fc < 2 ? false : true;
}

static inline void XDeintNxNFrame( uint8_t *dst, int i_dst,
                                   uint8_t *src, int i_src,
                                   int i_width, int i_height )
{
    int y, x;

    /* Progressive */
    for( y = 0; y < i_height; y += 2 )
    {
        memcpy( dst, src, i_width );
        dst += i_dst;

        if( y < i_height - 2 )
        {
            for( x = 0; x < i_width; x++ )
                dst[x] = (src[x] + 2*src[1*i_src+x] + src[2*i_src+x] + 2 ) >> 2;
        }
        else
        {
            /* Blend last line */
            for( x = 0; x < i_width; x++ )
                dst[x] = (src[x] + src[1*i_src+x] ) >> 1;
        }
        dst += 1*i_dst;
        src += 2*i_src;
    }
}

static inline void XDeintNxNField( uint8_t *dst, int i_dst,
                                   uint8_t *src, int i_src,
                                   int i_width, int i_height )
{
    int y, x;

    /* Interlaced */
    for( y = 0; y < i_height; y += 2 )
    {
        memcpy( dst, src, i_width );
        dst += i_dst;

        if( y < i_height - 2 )
        {
            for( x = 0; x < i_width; x++ )
                dst[x] = (src[x] + src[2*i_src+x] ) >> 1;
        }
        else
        {
            /* Blend last line */
            for( x = 0; x < i_width; x++ )
                dst[x] = (src[x] + src[i_src+x]) >> 1;
        }
        dst += 1*i_dst;
        src += 2*i_src;
    }
}

static inline void XDeintNxN( uint8_t *dst, int i_dst, uint8_t *src, int i_src,
                              int i_width, int i_height )
{
    if( XDeintNxNDetect( src, i_src, i_width, i_height ) )
        XDeintNxNField( dst, i_dst, src, i_src, i_width, i_height );
    else
        XDeintNxNFrame( dst, i_dst, src, i_src, i_width, i_height );
}

/* XDeintBand8x8:
 */
static inline void XDeintBand8x8C( uint8_t *dst, int i_dst,
                                   uint8_t *src, int i_src,
                                   const int i_mbx, int i_modx )
{
    int x;

    for( x = 0; x < i_mbx; x++ )
    {
        int s;
        if( ( s = XDeint8x8DetectC( src, i_src ) ) )
        {
            if( x == 0 || x == i_mbx - 1 )
                XDeint8x8FieldEC( dst, i_dst, src, i_src );
            else
                XDeint8x8FieldC( dst, i_dst, src, i_src );
        }
        else
        {
            XDeint8x8MergeC( dst, i_dst,
                             &src[0*i_src], 2*i_src,
                             &src[1*i_src], 2*i_src );
        }

        dst += 8;
        src += 8;
    }

    if( i_modx )
        XDeintNxN( dst, i_dst, src, i_src, i_modx, 8 );
}

#ifdef CAN_COMPILE_MMXEXT
VLC_MMX
static inline void XDeintBand8x8MMXEXT( uint8_t *dst, int i_dst,
                                        uint8_t *src, int i_src,
                                        const int i_mbx, int i_modx )
{
    int x;

    /* Reset current line */
    for( x = 0; x < i_mbx; x++ )
    {
        int s;
        if( ( s = XDeint8x8DetectMMXEXT( src, i_src ) ) )
        {
            if( x == 0 || x == i_mbx - 1 )
                XDeint8x8FieldEMMXEXT( dst, i_dst, src, i_src );
            else
                XDeint8x8FieldMMXEXT( dst, i_dst, src, i_src );
        }
        else
        {
            XDeint8x8MergeMMXEXT( dst, i_dst,
                                  &src[0*i_src], 2*i_src,
                                  &src[1*i_src], 2*i_src );
        }

        dst += 8;
        src += 8;
    }

    if( i_modx )
        XDeintNxN( dst, i_dst, src, i_src, i_modx, 8 );
}
#endif

#ifdef CAN_COMPILE_C_ALTIVEC
VLC_ALTIVEC
static inline void XDeintBand8x8Altivec( uint8_t *dst, int i_dst,
                                         uint8_t *src, int i_src,
                                         const int i_mbx, int i_modx )
{
    int x;

    for( x = 0; x < i_mbx; x++ )
    {
        if( XDeint8x8DetectAltivec( src, i_src ) )
        {
            if( x == 0 || x == i_mbx - 1 )
                XDeint8x8FieldEAltivec( dst, i_dst, src, i_src );
            else
                XDeint8x8FieldAltivec( dst, i_dst, src, i_src );
        }
        else
        {
            XDeint8x8MergeAltivec( dst, i_dst,
                                   &src[0*i_src], 2*i_src,
                                   &src[1*i_src], 2*i_src );
        }

        dst += 8;
        src += 8;
    }

    if( i_modx )
        XDeintNxN( dst, i_dst, src, i_src, i_modx, 8 );
}
#endif

/*****************************************************************************
 * Public functions
 *****************************************************************************/

int RenderX( filter_t *p_filter, picture_t *p_outpic, picture_t *p_pic )
{
    int i_plane;
#if defined (CAN_COMPILE_MMXEXT)
    const bool mmxext = vlc_CPU_MMXEXT();
#endif
#if defined (CAN_COMPILE_C_ALTIVEC)
    const bool altivec = vlc_CPU_ALTIVEC();
#endif

    /* Copy image and skip lines */
    for( i_plane = 0 ; i_plane < p_pic->i_planes ; i_plane++ )
    {
        const int i_mby = ( p_outpic->p[i_plane].i_visible_lines + 7 )/8 - 1;
        const int i_mbx = p_outpic->p[i_plane].i_visible_pitch/8;

        const int i_mody = p_outpic->p[i_plane].i_visible_lines - 8*i_mby;
        const int i_modx = p_outpic->p[i_plane].i_visible_pitch - 8*i_mbx;

        const int i_dst = p_outpic->p[i_plane].i_pitch;
        const int i_src = p_pic->p[i_plane].i_pitch;

        int y, x;

#if defined (CAN_COMPILE_C_ALTIVEC)
        /* The AltiVec code needs 16-byte aligned plane bases and pitches
         * that are multiples of 16.  VLC's picture allocator guarantees
         * both (64/64), but check so externally allocated pictures safely
         * fall back to the C code. */
        const bool altivec_plane = altivec &&
            !( (uintptr_t)p_outpic->p[i_plane].p_pixels & 15 ) &&
            !( (uintptr_t)p_pic->p[i_plane].p_pixels & 15 ) &&
            !( ( i_dst | i_src ) & 15 );
        /* one-shot path telemetry: which branch actually serves playback */
        static bool logged = false;
        if( !logged && i_plane == 0 )
        {
            logged = true;
            msg_Dbg( p_filter, "xdeint path: %s (cpu %d dst %p/%d src %p/%d)",
                     altivec_plane ? "ALTIVEC" : "C-fallback", (int)altivec,
                     (void *)p_outpic->p[i_plane].p_pixels, i_dst,
                     (void *)p_pic->p[i_plane].p_pixels, i_src );
        }
#endif

        for( y = 0; y < i_mby; y++ )
        {
            uint8_t *dst = &p_outpic->p[i_plane].p_pixels[8*y*i_dst];
            uint8_t *src = &p_pic->p[i_plane].p_pixels[8*y*i_src];

#ifdef CAN_COMPILE_MMXEXT
            if( mmxext )
                XDeintBand8x8MMXEXT( dst, i_dst, src, i_src, i_mbx, i_modx );
            else
#endif
#ifdef CAN_COMPILE_C_ALTIVEC
            if( altivec_plane )
                XDeintBand8x8Altivec( dst, i_dst, src, i_src, i_mbx, i_modx );
            else
#endif
                XDeintBand8x8C( dst, i_dst, src, i_src, i_mbx, i_modx );
        }

        /* Last line (C only)*/
        if( i_mody )
        {
            uint8_t *dst = &p_outpic->p[i_plane].p_pixels[8*y*i_dst];
            uint8_t *src = &p_pic->p[i_plane].p_pixels[8*y*i_src];

            for( x = 0; x < i_mbx; x++ )
            {
                XDeintNxN( dst, i_dst, src, i_src, 8, i_mody );

                dst += 8;
                src += 8;
            }

            if( i_modx )
                XDeintNxN( dst, i_dst, src, i_src, i_modx, i_mody );
        }
    }

#ifdef CAN_COMPILE_MMXEXT
    if( mmxext )
        emms();
#endif
    return VLC_SUCCESS;
}
