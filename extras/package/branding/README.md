# PowerVLC branding — Windows / Linux icon pipeline

This directory holds the vector master for the PowerVLC application icon and a
script that renders it into the raster formats the Windows and Linux packaging
already expect.

The macOS build gets its icon from `modules/gui/legacy_macosx/Resources`
(`.icns`, built by `extras/package/macosx/make-universal-icns.py`). This
directory is the equivalent source of truth for **Windows and Linux**.

## Files

| File                 | Purpose                                                          |
|----------------------|------------------------------------------------------------------|
| `powervlc.svg`       | Vector master (copy of the macOS app-icon source, the traffic cone). |
| `generate-icons.sh`  | Renders `powervlc.svg` into a Windows `.ico` and standalone PNGs. |
| `recolor_assets.py`  | Shifts the VLC orange to the PowerVLC red across existing assets. |
| `out/`               | Build output (git-ignored); created by the script, safe to delete. |

## The PowerVLC red

PowerVLC ships a **red** cone where VLC ships an orange one, so the rebranding
is unmistakable. The transform is a hue compression towards pure red
(`hue * 0.15`) applied only to pixels already in the orange band; saturation and
value are untouched, so gradients, shadows, the white cone bands and every
non-orange pixel survive unchanged. `#faa000` becomes `#fa1800`.

`recolor_assets.py` applies it to SVG (`rgb()` and `#rrggbb` literals), PNG,
ICO, BMP and ICNS. It is **not idempotent** — running it twice on the same file
shifts the hue again. Only ever run it on pristine assets.

Two format details it takes care of, both of which break things if got wrong:

* an `.icns` element is re-encoded in the format it already used. `ic08`/`ic09`
  as PNG instead of JPEG 2000 makes the in-process 10.4/10.5 icns reader return
  nil for the *whole* icon (see `../macosx/make-universal-icns.py`);
* a palettised BMP is recoloured through its palette, so the NSIS welcome bitmap
  keeps its bit depth instead of widening to 32-bit RGBA.

Deliberately left orange:

* the **sidebar icons** — both `macosx/Resources/sidebar-icons/` and
  `qt/pixmaps/playlist/sidebar-icons/` — kept as upstream by preference;
* the macOS titlebar traffic lights (yellow is a system semantic — red means
  close);
* the `addons/addon_*.svg` set (a per-category colour code in which red already
  means service discovery);
* the third-party service logos under
  `qt/pixmaps/playlist/sidebar-icons/sd/`, the bundled skins2 skin and its
  author's logo, and the stock jQuery UI theme under
  `share/lua/http/css/ui-lightness/`.

## What the pipeline produces

`generate-icons.sh` rasterises `powervlc.svg` and writes into `out/`:

* `out/vlc.ico` — multi-size Windows icon, frames **16 / 32 / 48 / 64 / 128 / 256**
  (the 256 frame is PNG-compressed inside the `.ico`, as Windows expects).
* `out/vlc.png` — the canonical **256×256** RGBA desktop PNG.
* `out/png/vlc-<size>.png` — the individual rasters (16/32/48/128/256/512) for
  any hicolor slots you want to refresh by hand.

The output names `vlc.ico` and `vlc.png` deliberately match the filenames the
packaging already references, so installing them is a plain copy — **no
packaging path changes**:

* Windows NSIS: `extras/package/win32/NSIS/vlc.win32.nsi.in` (`MUI_ICON`/`MUI_UNICON`)
  and `extras/package/win32/package.mak` copy `share/icons/vlc.ico`.
* Windows MSI: `extras/package/win32/msi/*.wxs` reference `vlc.ico`.
* Linux desktop / hicolor theme: `share/icons/<size>/vlc.png` (see `share/Makefile.am`).

## Regenerating and installing

```sh
# 1. render everything into ./out
./generate-icons.sh

# 2. install the two canonical assets into the packaging paths
cp out/vlc.ico ../../../share/icons/vlc.ico
cp out/vlc.png ../../../share/icons/vlc.png

# 3. (optional) refresh the hicolor theme PNGs from the rendered rasters
cp out/png/vlc-16.png  ../../../share/icons/16x16/vlc.png
cp out/png/vlc-32.png  ../../../share/icons/32x32/vlc.png
cp out/png/vlc-48.png  ../../../share/icons/48x48/vlc.png
cp out/png/vlc-128.png ../../../share/icons/128x128/vlc.png
cp out/png/vlc-256.png ../../../share/icons/256x256/vlc.png
```

`share/icons/vlc.ico` and `share/icons/vlc.png` in this tree were already
generated and installed this way.

## Toolchain

The script auto-detects an SVG rasteriser and an ICO assembler and fails with a
clear message if neither is present (it never emits a garbage/empty file):

* **SVG → PNG**: `rsvg-convert` (librsvg) preferred, else `inkscape`, else
  `cairosvg`, else ImageMagick with an SVG delegate.
* **PNG → ICO**: ImageMagick (`magick`/`convert`) preferred, else `png2ico`,
  else `icotool` (icoutils).

On macOS the easiest setup is Homebrew: `brew install librsvg imagemagick`.

Every generated file is validated with `file(1)` (Windows icon resource / PNG
image) before the script reports success.
