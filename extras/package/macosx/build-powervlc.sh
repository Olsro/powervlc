#!/bin/sh
# PowerVLC per-target build driver.
#
# Usage: build-powervlc.sh <x64|x86|g3|g4|g4e|g5|arm64> [extra build.sh args]
#
# Runs extras/package/macosx/build.sh inside the matching build<name>
# directory at the repository root with the PowerVLC configure policy:
#  - macosx-avfoundation, chromecast and osx-notifications are NEVER
#    force-disabled: configure drops what its dependencies cannot
#    provide, and what an old OS release cannot run degrades cleanly at
#    launch (weak frameworks / runtime class checks / plugin cache skip);
#  - the PowerPC and Intel 32-bit targets build without the modern
#    interface (--disable-macosx): Mac OS X 10.7+ never ran on them, so
#    only the legacy interface is reachable there anyway.
set -e

TARGET="$1"
[ -n "$TARGET" ] || { echo "usage: $0 <x64|x86|g3|g4|g4e|g5|arm64> [args]"; exit 1; }
shift

case "$TARGET" in
    x64)
        # legacy interface included: the in-app interface switcher must
        # work on every target (it is only auto-enabled below 10.6)
        ARCH="x86_64"
        ARGS="--disable-sparkle --enable-legacy-macosx"
        ;;
    arm64)
        ARCH="aarch64"
        ARGS="--disable-sparkle --enable-legacy-macosx"
        ;;
    x86)
        ARCH="i686"
        ARGS="--disable-sparkle --disable-macosx --enable-run-as-root \
--enable-libmpeg2 --disable-mmx --disable-sse"
        ;;
    g3)
        ARCH="ppc"
        ARGS="--disable-sparkle --disable-macosx --disable-altivec \
--enable-run-as-root --enable-libmpeg2"
        ;;
    g4|g4e|g5)
        ARCH="$TARGET"
        ARGS="--disable-sparkle --disable-macosx --enable-run-as-root \
--enable-libmpeg2"
        ;;
    *)
        echo "unknown target: $TARGET" >&2
        exit 1
        ;;
esac

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
VLCROOT=$(cd "$SCRIPTDIR/../../.." && pwd)
BUILDDIR="$VLCROOT/build$TARGET"
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

VLC_CONFIGURE_ARGS="$ARGS $VLC_CONFIGURE_ARGS" \
    "$SCRIPTDIR/build.sh" -a "$ARCH" "$@"

# Lua bytecode is architecture-specific; ship portable source so the PowerPC
# and 32-bit slices stop failing with "bad header in precompiled chunk".
if [ -d "$BUILDDIR/PowerVLC.app" ]; then
    "$SCRIPTDIR/lua-portable.sh" "$BUILDDIR/PowerVLC.app"
fi
