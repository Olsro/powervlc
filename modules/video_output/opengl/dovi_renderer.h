/*****************************************************************************
 * dovi_renderer.h: libplacebo Dolby Vision renderer for VLC 3 OpenGL outputs
 *****************************************************************************/

#ifndef VLC_OPENGL_DOVI_RENDERER_H
#define VLC_OPENGL_DOVI_RENDERER_H 1

#include <vlc_opengl.h>
#include <vlc_picture_pool.h>
#include <vlc_subpicture.h>

typedef struct vlc_dovi_renderer vlc_dovi_renderer_t;

vlc_dovi_renderer_t *vlc_dovi_renderer_Create(vlc_gl_t *,
                                               const video_format_t *);
void vlc_dovi_renderer_Delete(vlc_dovi_renderer_t *);
picture_pool_t *vlc_dovi_renderer_GetPool(vlc_dovi_renderer_t *, unsigned);
int vlc_dovi_renderer_Prepare(vlc_dovi_renderer_t *, picture_t *,
                              subpicture_t *);
int vlc_dovi_renderer_Display(vlc_dovi_renderer_t *);
void vlc_dovi_renderer_SetDrawableSize(vlc_dovi_renderer_t *, unsigned,
                                       unsigned);
void vlc_dovi_renderer_SetDisplayHeadroom(vlc_dovi_renderer_t *, float);
void vlc_dovi_renderer_SetViewport(vlc_dovi_renderer_t *, int, int,
                                   unsigned, unsigned);

#endif
