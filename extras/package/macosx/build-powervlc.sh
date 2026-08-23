#!/bin/sh
# PowerVLC per-target build driver.
#
# Usage: build-powervlc.sh <x64|x86|g3|g4|g5|arm64> [extra build.sh args]
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
[ -n "$TARGET" ] || { echo "usage: $0 <x64|x86|g3|g4|g5|arm64> [args]"; exit 1; }
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
        # --enable-a52 : liba52 est fourni par les contribs mais le support est
        # DÉSACTIVÉ par défaut dans configure.ac, donc le greffon n'était jamais
        # construit. Sur PowerPC sans SIMD il bat libavcodec de ~3,5 points en
        # lecture DVD (68,9 %% contre 72,3 %% sur iBook G3 600 MHz) ET décode en
        # virgule flottante, là où libavcodec retombe sur `ac3_fixed`. Le choix
        # reste débrayable par l'option `audio-liba52` (onglet Audio).
        ARGS="--disable-sparkle --disable-macosx --disable-altivec \
--enable-run-as-root --enable-libmpeg2 --enable-a52"
        ;;
    g4|g5)
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

# Keep an explicit floor stamp as a guard against accidentally pointing an
# architecture label at the wrong build directory. build.sh now reconfigures
# every invocation, but changing a directory's deployment floor in place can
# still leave third-party or manually produced objects behind.
case "$TARGET" in
    g3|g4|g5)    WANT_MIN="10.2" ;;
    x86)          WANT_MIN="10.4" ;;
    x64)          WANT_MIN="10.5" ;;
    arm64)        WANT_MIN="11.0" ;;
    *)            WANT_MIN="" ;;
esac
STAMP="$BUILDDIR/.powervlc-osx-min"
if [ -n "$WANT_MIN" ] && [ -f "$STAMP" ] && [ "$(cat "$STAMP")" != "$WANT_MIN" ]; then
    echo "ERROR: $BUILDDIR was configured for macOS $(cat "$STAMP")," >&2
    echo "       this target now needs $WANT_MIN. Use a fresh build directory." >&2
    exit 1
fi
mkdir -p "$BUILDDIR"
cd "$BUILDDIR"

VLC_CONFIGURE_ARGS="$ARGS $VLC_CONFIGURE_ARGS" \
    "$SCRIPTDIR/build.sh" -a "$ARCH" "$@"

[ -n "$WANT_MIN" ] && [ -d "$BUILDDIR" ] && echo "$WANT_MIN" > "$STAMP"

# Lua bytecode is architecture-specific; ship portable source so the PowerPC
# and 32-bit slices stop failing with "bad header in precompiled chunk".
if [ -d "$BUILDDIR/PowerVLC.app" ]; then
    "$SCRIPTDIR/lua-portable.sh" "$BUILDDIR/PowerVLC.app"

    # package.mak initially creates the cache before build.sh normalises and
    # strips the bundled Mach-O plugins.  Those operations change every
    # plugin's mtime, so the cache is already stale when the finished app is
    # launched (and was especially harmful on the native Apple Silicon
    # bundle).  Regenerate it only when this host can execute the target cache
    # generator; cross-built legacy slices deliberately ship without one.
    CACHEGEN="$BUILDDIR/bin/powervlc-cache-gen"
    PLUGINDIR="$BUILDDIR/PowerVLC.app/Contents/MacOS/plugins"
    if [ -x "$CACHEGEN" ] && "$CACHEGEN" --help >/dev/null 2>&1; then
        "$CACHEGEN" "$PLUGINDIR"
    else
        rm -f "$PLUGINDIR/plugins.dat"
    fi
fi
