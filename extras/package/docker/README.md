# PowerVLC — Docker builds (Windows & Linux)

Build the PowerVLC Windows installers and Linux packages on any machine with
Docker — in particular an **Apple-Silicon Mac** — without a separate Linux box.

> PowerVLC is an unofficial fork of VLC, not affiliated with VideoLAN.

## TL;DR

```bash
# from the repo root
extras/package/docker/build-in-docker.sh win64 win32 winarm64 linux-arm64-appimage
```

Artifacts land in `extras/package/docker/out/`.

## Why Docker works well here

Windows and x86 Linux builds are **cross-compiled on Linux**. On an arm64 Mac
their compiler and packaging tools run natively; only the produced files target
x86, so no QEMU is involved.

## Target matrix

| Target | Toolchain | Runtime / floor | Speed on arm64 Mac |
|---|---|---|---|
| `win32` | mingw-w64 GCC (apt) | msvcrt — **Windows XP SP3** | native — fast |
| `win64` | mingw-w64 GCC (apt) | msvcrt — **Windows Vista** | native — fast |
| `winarm64` | llvm-mingw | ucrt — **Windows 10 (RS5)** | native — fast |
| `linux-arm64-appimage` | system Qt5 (old glibc) | glibc 2.27+ | native — fast |
| `linux-amd64-appimage` | GCC cross + Bionic sysroot | glibc 2.27+ | native — fast |
| `linux-i386-appimage` | GCC cross + Bionic sysroot | glibc 2.27+ | native — fast |

The x86 AppImages are assembled natively with `mksquashfs` and the matching
prebuilt AppImage runtime. No target-native `linuxdeploy` binary is run.

```bash
extras/package/docker/build-in-docker.sh linux-amd64-cross-check linux-i386-cross-check
```

There is no snap target: snapcraft is itself a snap and wants LXD/multipass, so
building one in a container never worked here. Linux ships as an AppImage.

Floors match VLC 3.0 and are **not** raised (`_WIN32_WINNT=0x0502` is untouched).
`gcc-mingw-w64` (msvcrt) is used for win32/win64 to keep the XP/Vista floors —
llvm-mingw only publishes a *ucrt* arm64-host toolchain, and ucrt cannot run on
XP. winarm64 is Win10-only anyway, where ucrt is correct.

## Prerequisites

- Docker Desktop (running). On Apple Silicon, QEMU emulation for `linux/amd64`
  and `linux/386` is included by default.
- Internet access on first run (pulls base images, apt packages, llvm-mingw, and
  the linuxdeploy tools).

## Usage

```bash
extras/package/docker/build-in-docker.sh <target> [more targets...]
```

Each target builds its image (cached after the first run) and then compiles in a
container from a **clean snapshot of your working tree** (tracked + new files,
minus git-ignored build artifacts), so container builds never mix with your
macOS build directories. Output is copied to `extras/package/docker/out/`.

Examples:

```bash
# all three Windows installers (fast on arm64)
extras/package/docker/build-in-docker.sh win32 win64 winarm64

# native arm64 Linux AppImage (fast)
extras/package/docker/build-in-docker.sh linux-arm64-appimage

# mainstream x86_64 Linux AppImage (slow: emulated compile)
extras/package/docker/build-in-docker.sh linux-amd64-appimage
```

## Known friction points (honest list)

These are real, and mostly inherent to cross-building VLC — expect some
iteration on your machine:

1. **Emulated Linux builds are slow.** `linux-amd64` and `linux-i386` compile all
   of VLC under QEMU; budget hours, not minutes. Prefer `linux-arm64` for a fast
   local smoke test, and consider a native amd64 machine / CI for the amd64 build.
2. **Contrib dependencies.** The Windows contrib build pulls ~100 libraries; a
   given library may want an extra host tool (e.g. `protobuf`, or `wine` for some
   Qt shader steps). Add it to `Dockerfile.windows` if a contrib stops on a
   missing tool. VLC 3.0.23's Qt5-Widgets UI generally does **not** need wine.
3. **`gcc-mingw-w64` on an arm64 host.** win32/win64 rely on the apt mingw-w64
   cross packages being available for arm64 Ubuntu/Debian (they are on
   22.04/bookworm). If your base lacks them, switch `Dockerfile.windows` to a base
   that has them, or build those two targets with the emulated x86_64 llvm-mingw
   msvcrt toolchain.
4. **AppImage + VLC plugins.** VLC's plugins are `dlopen()`ed, so the build script
   passes `--deploy-deps-only` over the plugins dir to bundle their libraries. If
   the packaged app can't find codecs at runtime, verify the plugin path
   (`usr/lib/**/vlc/plugins`) survived and, if needed, set `VLC_PLUGIN_PATH` in a
   custom `AppRun`.
5. **i386 AppImage.** `linuxdeploy-plugin-qt` may not publish an i386 build; if the
   Qt step fails, the Qt5 runtime has to be bundled by hand. i386 is legacy/niche.

## Testing the results

Docker builds the binaries but can't *run* them:

- Windows `.exe` → test on real Windows (and Windows-on-ARM hardware / a Win-ARM
  VM for `winarm64`). Verify it installs to `Program Files\PowerVLC` and coexists
  with a real VLC (separate ProgIDs).
- `.AppImage` → `chmod +x` and run on a target distro (ideally one old and one new
  to confirm the glibc floor).

## Files

- `Dockerfile.windows` — arm64-native cross env: mingw-w64 GCC + llvm-mingw + NSIS.
- `Dockerfile.linux` — old-glibc env with system Qt5 + AppImage tooling.
- `build-in-docker.sh` — orchestrator (clean-tree copy, per-target build, artifact
  extraction). Reuses `extras/package/win32/build.sh` and
  `extras/package/appimage/build-appimage.sh`.
