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
- **`patchelf`**, to repair the plugin `RUNPATH`s that linuxdeploy leaves
  unusable (see below). The build aborts without it.
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
3. Runs `linuxdeploy --appdir AppDir --plugin qt` to deploy the dependencies.
4. Repairs the plugin `RUNPATH`s with `patchelf` (see below).
5. Runs `linuxdeploy --appdir AppDir --output appimage` to package.
6. Produces `PowerVLC-<version>-<arch>.AppImage`.

### Why the `RUNPATH` repair is not optional

linuxdeploy sets a usable RUNPATH on the main executable, but every file it
only *scans* with `--deploy-deps-only` — which is how VLC's `dlopen()`ed plugins
are handled — keeps a RUNPATH of plain `$ORIGIN`, pointing at
`usr/lib/vlc/plugins/<category>/` instead of `usr/lib`. Nothing fails at build
time; the AppImage even passes a `--version` smoke test, because that path never
loads a plugin's own dependencies. At run time, two things break:

- Plugins whose dependencies are not already loaded are dropped, including
  VLC's private helpers in `usr/lib/vlc` — which takes out `xcb_x11`, `xcb_xv`
  and `gl`, i.e. **every X11 video output**.
- `libqt_plugin.so` falls back to the **host's** Qt5 via `ld.so.cache` while the
  platform plugin and `libQt5XcbQpa` still come from the bundle. The two Qt
  builds mix and the process **segfaults at startup** inside
  `xkb_x11_keymap_new_from_device()` (observed on Debian 13 i386, 2026-08-10).

Step 4 rewrites those RUNPATHs to reach `usr/lib` and `usr/lib/vlc`, so it needs
**`patchelf`** on the build host. Measured on the i386 AppImage: 472 → 511
modules loaded, zero load failures.

Exporting `LD_LIBRARY_PATH` from the `AppRun` looks simpler and was tried first,
but it is **inherited by child processes**: system helpers the app spawns —
`dbus-launch` above all — then load our older bundled libraries and die
(``dbus-launch: .../libdbus-1.so.3: version `LIBDBUS_PRIVATE_1.16.2' not
found``), taking the D-Bus/MPRIS interface with them. `DT_RUNPATH` is a property
of the file and never leaks.

The host graphics stack is untouched either way — linuxdeploy's blacklist keeps
`libGL`/`libEGL`/`libX11`/`libxcb.so.1`/`libdrm` out of the bundle. The script
hard-fails after packaging if the repair did not take, so this cannot regress
silently.

### Architectures

The target architecture is auto-detected from `uname -m`:

- Run on an **x86_64** host → `PowerVLC-<version>-x86_64.AppImage`.
- Run on an **aarch64 / arm64** host (again with old glibc) →
  `PowerVLC-<version>-aarch64.AppImage`.
- Run on an **i386/i686** host → `PowerVLC-<version>-i386.AppImage`.
  Note that `linuxdeploy-plugin-qt` does not always publish an i386 build; if
  the Qt-plugin step fails, the Qt runtime has to be bundled by hand.

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
