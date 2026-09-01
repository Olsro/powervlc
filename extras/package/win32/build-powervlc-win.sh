#!/bin/sh
# PowerVLC per-target Windows build driver (NSIS .exe installers only).
#
# Usage: build-powervlc-win.sh <x86|x64|arm64> [extra build.sh args]
#
# Mirrors extras/package/macosx/build-powervlc.sh in spirit: it maps a
# friendly target name to the mingw arch triplet used by the upstream
# win32 build.sh, then drives the two upstream steps that produce the
# rebranded PowerVLC-<version>-win32/win64/winarm64.exe installer:
#
#     ./extras/package/win32/build.sh -a <arch>   (compile)
#     make package-win32                           (build the NSIS .exe)
#
# The output basename (PowerVLC-... and the win32/win64/winarm64 suffix)
# comes from vlc.win32.nsi.in via the @HAVE_WIN64_TRUE@/@HAVE_ARM64_TRUE@
# configure conditionals; this driver only selects the arch.
#
# Target -> mingw arch mapping (matching build-powervlc.sh's spirit):
#     x86   -> i686      (32-bit)
#     x64   -> x86_64    (64-bit)
#     arm64 -> aarch64   (ARM 64-bit)
#
# Toolchain prerequisites (install before running):
#  - mingw-w64 gcc (i686-w64-mingw32 / x86_64-w64-mingw32) for the x86 and
#    x64 targets;
#  - llvm-mingw (aarch64-w64-mingw32) for the arm64 target -- upstream gcc
#    has no aarch64 Windows target, so llvm-mingw is required there;
#  - the i686 mingw compiler is required EVEN FOR arm64: the NSIS installer
#    links the 32-bit nsProcess.dll plugin, which is always built for i686.
#
# We deliberately do NOT pass build.sh's -S (Windows API version): PowerVLC
# keeps VLC 3.0's minimum-OS floor (_WIN32_WINNT is left untouched), so the
# installers still target the same Windows releases as upstream VLC 3.0.
set -e

TARGET="$1"
[ -n "$TARGET" ] || { echo "usage: $0 <x86|x64|arm64> [args]"; exit 1; }
shift

case "$TARGET" in
    x86)
        ARCH="i686"
        SHORTARCH="win32"
        ;;
    x64)
        ARCH="x86_64"
        SHORTARCH="win64"
        ;;
    arm64)
        ARCH="aarch64"
        SHORTARCH="winarm64"
        ;;
    *)
        echo "unknown target: $TARGET" >&2
        echo "usage: $0 <x86|x64|arm64> [args]" >&2
        exit 1
        ;;
esac

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
VLCROOT=$(cd "$SCRIPTDIR/../.." && pwd)
BUILDDIR="$VLCROOT/build/windows/$SHORTARCH"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

# Upstream step 1: configure + compile for the selected arch.
echo "+ $SCRIPTDIR/build.sh -a $ARCH $*"
"$SCRIPTDIR/build.sh" -a "$ARCH" "$@"

# Build amuled with the same MinGW target and without aMule's legacy UPnP
# client. Its third-party inputs come from PowerVLC's cross contrib prefix.
REPO_ROOT=$(cd "$SCRIPTDIR/../../.." && pwd)
AMULE_TARGET="windows-$ARCH"
AMULE_DEPS="$REPO_ROOT/contrib/$ARCH-w64-mingw32"
AMULE_DEP_PREFIX="$AMULE_DEPS" \
AMULE_CPPFLAGS="-I$AMULE_DEPS/include" \
AMULE_LDFLAGS="-L$AMULE_DEPS/lib" \
AMULE_CMAKE_ARGS="-DZLIB_INCLUDE_DIR=$AMULE_DEPS/include -DZLIB_LIBRARY=$AMULE_DEPS/lib/libz.a" \
    "$REPO_ROOT/extras/package/build-amule-engine.sh" "$AMULE_TARGET"
export POWERVLC_AMULED="$REPO_ROOT/build/dependencies/amule/$AMULE_TARGET/prefix/bin/amuled.exe"

# Upstream step 2: build the NSIS .exe installer (no MSI).
echo "+ make package-win32"
make package-win32
