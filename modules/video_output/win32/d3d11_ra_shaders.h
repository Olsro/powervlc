/*****************************************************************************
 * d3d11_ra_shaders.h: RetroArch Slang CRT execution for Direct3D 11
 *****************************************************************************/
#ifndef VLC_D3D11_RA_SHADERS_H
#define VLC_D3D11_RA_SHADERS_H

#include <vlc_common.h>
#include <vlc_vout_display.h>
#include <d3d11.h>

#include "../../video_chroma/d3d11_fmt.h"

struct d3d11_ra_shader_engine;

struct d3d11_ra_shader_engine *D3D11_RA_Create(vout_display_t *,
                                                d3d11_handle_t *,
                                                d3d11_device_t *);
void D3D11_RA_Destroy(struct d3d11_ra_shader_engine *);

/* Begin one decoded frame. The caller renders VLC's normal colour-converted
 * picture quad into the returned RGB target; Render then runs the exact Slang
 * pass graph and writes it into the normal D3D11 back buffer. */
bool D3D11_RA_Begin(struct d3d11_ra_shader_engine *, unsigned, unsigned,
                    unsigned, unsigned, vlc_tick_t,
                    ID3D11RenderTargetView **, unsigned *, unsigned *);
bool D3D11_RA_Render(struct d3d11_ra_shader_engine *,
                     ID3D11RenderTargetView *, const D3D11_VIEWPORT *);

#endif
