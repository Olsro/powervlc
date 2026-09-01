/*****************************************************************************
 * retroarch_shaders.h: RetroArch-compatible GLSL post-processing
 *****************************************************************************/
#ifndef VLC_OPENGL_RETROARCH_SHADERS_H
#define VLC_OPENGL_RETROARCH_SHADERS_H

#include "converter.h"

typedef struct vlc_ra_shader_engine vlc_ra_shader_engine_t;

vlc_ra_shader_engine_t *vlc_ra_shader_engine_Create(vlc_gl_t *gl,
                                                     const opengl_vtable_t *vt,
                                                     bool allow_long_shaders);
void vlc_ra_shader_engine_Delete(vlc_ra_shader_engine_t *engine);
void vlc_ra_shader_engine_SetViewport(vlc_ra_shader_engine_t *engine,
                                     int x, int y, unsigned width,
                                     unsigned height);
void vlc_ra_shader_engine_NewFrame(vlc_ra_shader_engine_t *engine,
                                   vlc_tick_t pts);
bool vlc_ra_shader_engine_Begin(vlc_ra_shader_engine_t *engine,
                               unsigned input_width, unsigned input_height);
void vlc_ra_shader_engine_End(vlc_ra_shader_engine_t *engine);

#endif
