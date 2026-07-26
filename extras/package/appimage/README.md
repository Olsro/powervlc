# PowerVLC AppImage

Packaging recipe for building a portable **PowerVLC** AppImage for Linux.

PowerVLC is an unofficial fork of VLC, not affiliated with VideoLAN.

An AppImage is a single executable file that bundles PowerVLC together with its
VLC plugins and the Qt5 runtime. It runs on most Linux distributions without
installing anything, and coexists with a system-installed real VLC (it is a
separate file with its own name, and installs nothing system-wide).

## Prerequisites

- **An old-glibc build host.** glibc is only *forward* compatible, so build on
  the oldest system you want to support. An **Ubuntu 18.04-class host
  (glibc 2.27)** is the recommended target and yields an AppImage that runs on
  virtually every still-used desktop Linux. Building on a modern distro produces
  an AppImage that only runs on equally-modern systems.
- **A configured and built PowerVLC tree.** Run `./configure && make` first;
  the script calls `make install DESTDIR=.../AppDir` on that tree.
- **Qt5 development files** on the build host (the Qt runtime is bundled by
  `linuxdeploy-plugin-qt`).
- **FUSE** to run the AppImage tools (or export `APPIMAGE_EXTRACT_AND_RUN=1`).
- **curl or wget** to fetch `linuxdeploy` and `linuxdeploy-plugin-qt`
  (downloaded automatically on first run if not already present).

## Building

From a configured + built PowerVLC tree:

```sh
# from the build tree (defaults BUILDDIR/WORKDIR to $PWD):
sh extras/package/appimage/build-appimage.sh

# or point it at a build tree explicitly:
BUILDDIR=/path/to/powervlc-build \
WORKDIR=/path/to/output-dir \
VERSION=3.0.23-powervlc \
sh extras/package/appimage/build-appimage.sh
```

The script:

1. `make install DESTDIR="$WORKDIR/AppDir"` to stage an install tree.
2. Downloads `linuxdeploy` + `linuxdeploy-plugin-qt` for the host arch if absent.
3. Runs `linuxdeploy --appdir AppDir --plugin qt --output appimage` with the
   installed `vlc.desktop` and 256×256 icon.
4. Produces `PowerVLC-<version>-<arch>.AppImage`.

### Architectures

The target architecture is auto-detected from `uname -m`:

- Run on an **x86_64** host → `PowerVLC-<version>-x86_64.AppImage`.
- Run on an **aarch64 / arm64** host (again with old glibc) →
  `PowerVLC-<version>-aarch64.AppImage`.

There is no cross-compilation here: build each architecture on a native host.

## Compatibility rationale

- **Broad reach via old glibc.** Linking against an old glibc makes the binary
  run on that glibc and all newer ones, covering the widest range of distros
  from one build.
- **Self-contained.** Qt5 and the VLC/PowerVLC plugins are bundled, so there are
  no distro package dependencies to satisfy at run time.
- **Coexists with real VLC.** The AppImage is a standalone file and installs
  nothing into system paths, so it never conflicts with an official `vlc`
  package.
