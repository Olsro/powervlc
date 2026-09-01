# RetroArch GLSL shaders in PowerVLC

This directory is a source snapshot of `libretro/glsl-shaders`, commit
`4f4eb801b2dbcaed0a9669a9deec1a098f3623d8` (2026-08-23).

PowerVLC executes the original `.glslp` pass descriptions and `.glsl` source
programs; it does not translate their visual algorithms into approximations.
Copyright and licence terms vary by shader and remain in the original files or
their adjacent README/licence files.  The PowerVLC preset parser and renderer
are an independent implementation and contain no RetroArch parser code.

At runtime a preset is listed only if every required shader compiles and links,
its render-target formats are supported, and the backend implements every
resource/state feature requested by that preset.  The CPU CRT filter remains
the fallback for outputs without a compatible programmable GPU.
