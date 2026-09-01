# CRT display filter

PowerVLC builds the native `crtscanline` video filter by default on Mac Legacy,
Mac Modern, Linux Qt, and Windows Qt. It is based on Jules Lazaro's
[VLC-CRT-Filter-Effect](https://github.com/julescools/VLC-CRT-Filter-Effect),
imported from commit `b7d3ad419b1324321e7306faab5807ca11355efe` and extended
under the same LGPL 2.1-or-later license.

The filter is available in the advanced video-filter preferences as **CRT
display**, but it does not need to be enabled there first. The bundled **View
→ CRT Display Controller** extension adds it to the current video as soon as
**On**, a setting, or a preset is selected. **Off** removes the filter without
discarding the chosen settings. It may also be started from a terminal:

```text
powervlc --video-filter=crtscanline video.mkv
```

## Controls

| Option | Range | Default | Cost and purpose |
| --- | ---: | ---: | --- |
| `crtscanline-darkness` | 0–100 | 35 | Resolution-aware scanline depth |
| `crtscanline-spacing` | 1–20 | 2 | Line period at a 480p reference |
| `crtscanline-blend` | on/off | on | Smooth beam profile or hard bands |
| `crtscanline-phosphor` | 0–3 | 0 | Off, aperture grille, slot mask, or shadow mask |
| `crtscanline-mask-strength` | 0–100 | 20 | Visibility of the phosphor structure |
| `crtscanline-halation` | 0–100 | 0 | Glow around bright picture detail |
| `crtscanline-diffusion` | 0–100 | 0 | Gentle optical softening |

**Vintage anime** is tuned as a restrained CPU-filter starting point for 480p
masters: smooth scanlines, a light aperture grille, and low halation and
diffusion.

On programmable OpenGL outputs, **Presets RetroArch** executes the original
`.glslp` descriptions and `.glsl` programs from all 77 top-level presets in
RetroArch's
[`crt` shader directory](https://github.com/libretro/glsl-shaders/tree/master/crt).
This is not a visual approximation: the renderer implements ordered multipass
targets, source/viewport/absolute scaling, the stock presentation pass, shader
parameters and aliases, sRGB and floating-point buffers, wrap/filter/mipmap
state, external lookup textures, previous-frame history, and feedback passes.
Preset parameters are global across every pass, matching RetroArch even when
their `#pragma` declarations occur only in a preset's final shader, as they do
for CRT-Royale.
The files keep their upstream names and licences; PowerVLC's preset parser is
an independent implementation.

RetroArch cores normally provide shaders with a native 240p/480p raster, while
many video releases store the same master already enlarged to 720p or 1080p.
Treating every row of such a file as a CRT scanline creates severe moire. The
controller's **Source raster** choice therefore defaults to **Auto (source
SD)**: inputs above 576 lines are reduced on the GPU to 480 lines before the
original preset runs. **Native**, **240p**, and **480p** are available for
material whose mastering resolution is known. The presentation and phosphor
mask still use the full output viewport, and subtitles remain full-resolution.

The menu is capability-driven. A preset is exposed only when every program
compiles and links on the active driver, every LUT decodes, every target format
is framebuffer-complete, and the maximum texture-unit requirement fits the
GPU. Thus an older machine sees only the exact shaders it can execute; an
output without a suitable programmable OpenGL path sees no RetroArch menu at
all and continues to use the CPU presets above. PowerVLC composites subtitles
after this GPU stage, so subtitle edges stay clean instead of passing through
the CRT mask. While a RetroArch preset is active, movie subtitles also receive
a subtle black safety halo behind their original pixels. This preserves the
authored colour, alpha, and antialiasing of text and bitmap subtitles (including
PGS) while keeping them readable over high-frequency scanlines and phosphor
masks. OSD, logos, and interactive disc menus are left unchanged.

Temporal presets follow decoded video frames rather than display refreshes.
Pausing therefore freezes shader animation, feedback, and frame history; a
window redraw or resize does not make the CRT continue evolving on its own.

VLC's existing grain, motion blur, gamma, and contrast controls still compose
with this filter. Apply them lightly after choosing a CRT preset; the filter
does not silently change unrelated VLC preferences.

## Older hardware

The default settings run only the scanline pass. Its cosine beam profile is
precomputed when a setting or source size changes, then reused for subsequent
frames. Frames are modified in place, so the filter does not allocate and copy
a second video picture. Setting darkness to 0 with all advanced effects off is
a direct pass-through.

Phosphor masks add one integer multiply per luma sample. Halation and diffusion
share one cached luma buffer and a single spatial pass, but remain the most
expensive options. Set both to 0 first when tuning for a G3, early Intel Mac,
or similarly constrained PC.

The GPU renderer allocates intermediate targets only for the passes that need
them, shares identical LUT textures between presets, and allocates temporal
history only when the selected shader references it. Lightweight presets are
the only ones probed on drivers classified as constrained. The CPU and exact
GPU engines are mutually exclusive, avoiding an unnecessary hardware-to-CPU
pixel conversion when an exact shader is active.

On Apple's GLSL 1.20 compatibility context, the renderer backports GLSL 1.30
intrinsics through the corresponding OpenGL extensions and removes only dead
shader-interface values. This keeps CRT-Royale within the eight-varying limit
of that context. Pass and alias `InputSize` uniforms describe the valid image
stored in each intermediate target, exactly as in RetroArch; this is distinct
from the input consumed while producing that target and is essential to
Royale's scanline, bloom, and manual Lanczos mask coordinates. Presets are
still published only after the backported programs compile and link
successfully.
