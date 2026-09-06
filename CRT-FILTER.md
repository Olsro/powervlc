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

The menu is capability-driven. Known language-incompatible presets and heavy
presets on constrained drivers are excluded immediately. Compilation/linking,
LUT decoding, framebuffer formats and texture-unit counts are validated on
first selection; rejected presets are then withdrawn. This lazy validation
avoids compiling the entire catalogue while a video is opening, but means an
entry can initially appear and subsequently be rejected by a particular driver.
Direct3D 11 on Windows exposes the accepted Slang catalogue through a native
HLSL multipass renderer. Direct3D 9, DirectDraw, GDI and outputs without a
suitable programmable GPU path continue to use the CPU presets above; on
Windows the controller can also restart the current item with OpenGL.
PowerVLC composites subtitles
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

## Slang presets

The same menu distinguishes **GLSL · name** and **Slang · name**. The Slang
entries are compiled from the official
[libretro/slang-shaders](https://github.com/libretro/slang-shaders) CRT catalogue,
pinned to revision `4812a82f6c9a11cc8b5a7447040a98c9fc80c00e`.
They are additional programs, not aliases for the similarly named GLSL presets.

The build-time importer uses **glslang → SPIR-V → SPIRV-Cross** and emits both
HLSL 5.0 and the lowest validated GLSL level among 120, 130, 330 and 430.
Reflection maps Slang's
uniform blocks, push constants, location-based stage interfaces, texture
semantics, four-component size/inverse-size values and parameters to the
renderer. Preset references/includes, aliases, LUTs, supported framebuffer
formats and a single feedback target are retained. Source algorithms are not
replaced with approximations. Subtitles, raster normalization and pause/frame
timing use the existing renderer.

No Slang, glslang or SPIR-V compiler is shipped or run on the playback machine.
OpenGL consumes the generated GLSL directly; Direct3D 11 compiles the generated
HLSL with the standard Direct3D compiler when a preset is selected for the first
time. The generated assets are included automatically in Mac Legacy, Mac
Modern, Linux Qt and Windows Qt packages through the existing shader-data
packaging rules. Detailed preset structures are allocated only when selected,
rather than for the whole catalogue. The original CPU filter remains available
without a programmable GPU output.

Windows packages combine the 1,567 runtime shader, preset and LUT resources in
a single seekable `retroarch-shaders.pak`. Shader text and lookup images are
read directly from the indexed payload; nothing is expanded into a temporary
directory. This substantially reduces installer and antivirus file-system work
without changing the renderer or the shader contents. Unix packages and source
trees retain loose resources, which the same runtime continues to support.

The generated HLSL is executed directly by a new Direct3D 11 backend; it is not
an OpenGL window hidden behind the Direct3D preference. There is no equivalent
Metal, Vulkan, Direct3D 9 or DirectDraw GPU backend, nor an arbitrary runtime
`.slangp` loader. Slang improves source portability, not a GPU's actual
hardware capabilities. In particular, the current macOS compatibility context
reports GLSL 120 even on Apple Silicon: Slang presets requiring a newer level
are hidden there, while the existing GLSL catalogue remains available.

The D3D11 graph follows RetroArch's resource transition order: all shader
resource views and the previous output-merger target are detached before a
pass generates mipmaps or binds that texture as its input. D3D11 otherwise
permits the conflicting input slot to become `NULL` without failing the draw,
which is especially destructive in long Royale graphs. Declared sRGB and FP16
intermediate formats are preserved rather than used as a synchronization
workaround.

The importer fails closed on features not represented faithfully by this
backend: more than 15 authored passes (one slot is reserved for presentation),
more than 64 global parameters, multiple feedback targets, frame-history
semantics not yet exposed by the Slang adapter, unsupported target formats, and
unsupported uniforms such as subframe timing. The complete accepted/rejected
list and reasons are recorded in
`share/retroarch-shaders/crt/slang/import-report.json`. Original source files,
includes, assets and licence notices accompany the generated programs.

To regenerate, install the build-host tools `glslangValidator` and
`spirv-cross`, check out the pinned upstream revision, and generate into an
empty staging directory:

```sh
python3 extras/tools/import-slang-shaders.py /path/to/slang-shaders /path/to/staging/crt
python3 test/check_slang_import.py
```

Review the report before replacing `share/retroarch-shaders/crt/slang` with
the staged directory. `test/check_slang_gpu.c` additionally compiles and links
the generated programs on native macOS OpenGL, Linux EGL/Mesa, or Windows WGL
without opening a visible application window; build/run instructions are in
that file. Windows tests must run in the logged-in interactive desktop session,
not the SSH service session, to exercise the VM/GPU driver.

The importer disables optional GLSL 4.2 sampler-binding qualifiers on older
targets: sampler units are assigned by the renderer, so these qualifiers add
no functionality and would unnecessarily reject OpenGL 4.1 drivers such as
Parallels. This does not reduce shader quality.

On Windows, both the normal Direct3D 11 output and OpenGL can run GPU presets.
The Direct3D 11 path consumes the generated HLSL programs and is the relevant
isolated playback test for the default Windows configuration:

```text
powervlc.exe --no-one-instance --vout=direct3d11 --crt-retroarch-enabled --crt-retroarch-preset=slang/crt-royale video.mkv
```

OpenGL continues to accept the same command with `--vout=glwin32`. The CPU
presets remain available on Direct3D 9, DirectDraw and legacy outputs.
On the validated Intel Iris Xe path, the generic and Slang Royale menu names
select the upstream Royale-fast graph with display-safe contrast. The two
Intel-labelled graphs that returned a black frame on that driver are not
advertised; explicit failure is preferable to a selectable no-op or black
picture.

## Older hardware

The default settings run only the scanline pass. Its cosine beam profile is
precomputed when a setting or source size changes, then reused for subsequent
frames. Decoder input pictures remain immutable: the filter writes a separate
output picture so paused redraws cannot darken it repeatedly and predicted
frames cannot inherit a CRT mask. Setting darkness to 0 with all advanced
effects off is a direct pass-through.

Phosphor masks add one integer multiply per luma sample. Halation and diffusion
share a single source-to-output spatial pass without a scratch copy, but remain the most
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
