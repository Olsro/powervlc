#ifndef POWERVLC_MVC_PICCONTEXT_H
#define POWERVLC_MVC_PICCONTEXT_H

#include <vlc_picture.h>
#include <stdint.h>
#include <stdlib.h>

#define POWERVLC_MVC_DIRECT_MAGIC UINT32_C(0x4d564344) /* MVCD */

typedef struct powervlc_mvc_piccontext
{
    picture_context_t context;
    uint32_t magic;
    volatile int refs;
    bool uploaded;
    bool edge_returned;
    void *decoder;
    void *return_arg;
    void (*return_frame)(void *decoder, void *return_arg);
    const uint8_t *planes[2][3]; /* left/top, right/bottom; Y, Cb, Cr */
    int strides[2][3];
    unsigned widths[3];
    unsigned heights[3];
    bool packed_base;
    unsigned base_eye;
    const uint8_t *packed_base_pixels;
    int packed_base_stride;
    unsigned packed_base_width;
    unsigned packed_base_height;
    void *packed_base_owner;
    void (*release_packed_base)(void *owner);
} powervlc_mvc_piccontext;

static inline bool powervlc_mvc_context_is_direct(const picture_context_t *ctx)
{
    return ctx != NULL &&
           ((const powervlc_mvc_piccontext *)ctx)->magic ==
               POWERVLC_MVC_DIRECT_MAGIC;
}

#endif
