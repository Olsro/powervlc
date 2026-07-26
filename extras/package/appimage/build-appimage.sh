#!/bin/sh
#
# build-appimage.sh - package PowerVLC as a portable Linux AppImage.
#
# PowerVLC is an unofficial fork of VLC, not affiliated with VideoLAN.
#
# This script turns an already-configured-and-built PowerVLC Linux tree into a
# single self-contained PowerVLC-<version>-<arch>.AppImage using linuxdeploy and
# its Qt plugin. The AppImage bundles PowerVLC, its VLC plugins and the Qt5
# runtime, so it runs on many distributions without installing anything and
# coexists with a system-installed real VLC (different binary name / no install).
#
# --------------------------------------------------------------------------
# IMPORTANT - build on an OLD-glibc host for broad compatibility
# --------------------------------------------------------------------------
# glibc is only forward compatible: a binary linked against glibc X runs on
# glibc >= X but NOT on older glibc. So build this AppImage on the OLDEST
# distribution you want to support - an Ubuntu 18.04-class host (glibc 2.27) is
# a good target and lets the result run on virtually every still-used desktop
# Linux. Building on a modern distro (e.g. Ubuntu 24.04) produces an AppImage
# that only runs on equally-modern systems.
#
# For an arm64 (aarch64) AppImage, run this same script on an aarch64 host with
# an equally old glibc; the ARCH is auto-detected from `uname -m`.
# --------------------------------------------------------------------------
#
# Prerequisites (see README.md):
#   * A configured PowerVLC build tree that has already been `make`-built
#     (run ./configure && make first). Point this script at it with BUILDDIR,
#     or run it from that tree.
#   * Qt5 development files (linuxdeploy-plugin-qt bundles the Qt runtime).
#   * FUSE (to run the downloaded *.AppImage tools) or set APPIMAGE_EXTRACT_AND_RUN=1.
#   * curl or wget to fetch the linuxdeploy tools (skipped if already present).
#
# This script does not need to run on this machine; it is a documented recipe.

set -e

# ---- configuration -------------------------------------------------------

# Directory of the configured+built PowerVLC tree (defaults to current dir).
BUILDDIR="${BUILDDIR:-$PWD}"

# Where the AppDir (staging root) and downloaded tools live.
WORKDIR="${WORKDIR:-$PWD}"
APPDIR="$WORKDIR/AppDir"

# Host architecture -> AppImage/linuxdeploy arch string.
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    x86_64)  ARCH="x86_64" ;;
    aarch64|arm64) ARCH="aarch64" ;;
    i386|i486|i586|i686) ARCH="i386" ;;
    *) echo "Unsupported host architecture: $HOST_ARCH" >&2; exit 1 ;;
esac
# NOTE: linuxdeploy-plugin-qt does not always publish an i386 build; if the i386
# AppImage fails at the Qt-plugin step, the Qt runtime must be bundled by hand.

# PowerVLC version: honour $VERSION, else read the top-level VERSION file, else
# fall back to `git describe`, else "unknown".
if [ -z "$VERSION" ]; then
    if [ -f "$BUILDDIR/VERSION" ]; then
        VERSION="$(cat "$BUILDDIR/VERSION")"
    elif git -C "$BUILDDIR" rev-parse --short HEAD >/dev/null 2>&1; then
        VERSION="$(git -C "$BUILDDIR" describe --always HEAD)"
    else
        VERSION="unknown"
    fi
fi

OUTFILE="PowerVLC-${VERSION}-${ARCH}.AppImage"

echo "=== PowerVLC AppImage build ==="
echo "  build tree : $BUILDDIR"
echo "  work dir   : $WORKDIR"
echo "  arch       : $ARCH"
echo "  version    : $VERSION"
echo "  output     : $OUTFILE"

# ---- 1. stage an install tree into AppDir --------------------------------

echo "--- Installing PowerVLC into $APPDIR ..."
rm -rf "$APPDIR"
make -C "$BUILDDIR" install DESTDIR="$APPDIR"

# The executable is built as "powervlc" (bin/Makefile.am), so there is nothing
# to rename here. The interface alias scripts still exec it by ABSOLUTE path
# (make-alias writes $bindir/powervlc), which does not exist inside an AppImage:
# rewrite them to the bare name, resolved through PATH by the AppRun.
VLC_BIN="$(find "$APPDIR" -type f -path '*/usr/bin/powervlc' -print -quit)"
if [ -n "$VLC_BIN" ]; then
    for _a in cpowervlc npowervlc qpowervlc rpowervlc spowervlc; do
        _f="$(dirname "$VLC_BIN")/$_a"
        [ -f "$_f" ] && sed -i 's,[^ ]*/usr/bin/powervlc,powervlc,g' "$_f"
    done
fi

# libaacs: AACS descrambling for Blu-ray. libbluray does not link against it,
# it dlopen()s "libaacs.so.0" at runtime, so linuxdeploy - which only follows
# ELF NEEDED entries - never sees it and would leave it out. Copy it in beside
# the other libraries (AppRun puts usr/lib on the library path). Without it the
# Blu-ray plugin plays homemade discs only.
BLURAY_PLUGIN="$(find "$APPDIR" -name '*bluray_plugin.so' -print -quit)"
if [ -n "$BLURAY_PLUGIN" ]; then
    LIBAACS="$(ldconfig -p 2>/dev/null | sed -n 's/.*libaacs\.so\.0 (.*) => \(.*\)/\1/p' | head -1)"
    if [ -n "$LIBAACS" ] && [ -e "$LIBAACS" ]; then
        LIBDIR="$(dirname "$(find "$APPDIR" -name 'libvlccore.so.*' -print -quit)")"
        [ -n "$LIBDIR" ] || LIBDIR="$APPDIR/usr/lib"
        mkdir -p "$LIBDIR"
        cp -L "$LIBAACS" "$LIBDIR/libaacs.so.0"
        echo "  bundled     : $LIBAACS -> $LIBDIR/libaacs.so.0"
    else
        echo "WARNING: the Blu-ray plugin is bundled but libaacs.so.0 was not" >&2
        echo "         found on this host: retail Blu-ray discs will not play." >&2
        echo "         Install it (Debian/Ubuntu: libaacs0) and re-run." >&2
    fi
fi

# The install prefix inside the tree is typically /usr or /usr/local; the
# desktop file and icon are what linuxdeploy uses to build the AppImage.
DESKTOP_FILE="$(find "$APPDIR" -name 'vlc.desktop' -print -quit)"
ICON_FILE="$(find "$APPDIR" -path '*icons/hicolor/256x256/apps/vlc.png' -print -quit)"

if [ -z "$DESKTOP_FILE" ]; then
    echo "Could not find vlc.desktop under $APPDIR - did 'make install' run?" >&2
    exit 1
fi
if [ -z "$ICON_FILE" ]; then
    # Fall back to any installed vlc icon.
    ICON_FILE="$(find "$APPDIR" -name 'vlc.png' -print -quit)"
fi

echo "  desktop file: $DESKTOP_FILE"
echo "  icon file   : $ICON_FILE"

# ---- 2. fetch linuxdeploy + the Qt plugin (if absent) --------------------

LD_BASE="https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous"
LDQT_BASE="https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous"
LINUXDEPLOY="$WORKDIR/linuxdeploy-${ARCH}.AppImage"
LINUXDEPLOY_QT="$WORKDIR/linuxdeploy-plugin-qt-${ARCH}.AppImage"

fetch() {
    # fetch <url> <dest>
    if command -v curl >/dev/null 2>&1; then
        curl -L -o "$2" "$1"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$2" "$1"
    else
        echo "Need curl or wget to download $1" >&2
        exit 1
    fi
}

# An AppImage stamps its own magic -- 'A', 'I', 0x02 -- over bytes 8..10 of the
# ELF header (EI_ABIVERSION and the padding after it). A native kernel ignores
# those bytes and runs the file regardless.
#
# An EMULATED container does not. Building the amd64 or i386 targets on an
# arm64 Docker host dispatches every x86 binary through binfmt_misc to a
# QEMU/Rosetta interpreter, and the binfmt entry matches on the ELF header
# INCLUDING those bytes. The AppImage magic makes the file miss the pattern, no
# interpreter is selected, and exec fails with a thoroughly misleading
# "Exec format error" -- on a file that `file` reports as a perfectly good
# x86-64 ELF. That is what broke linux-amd64-appimage and linux-i386-appimage
# while the native arm64 target built fine (2026-07-25).
#
# Zeroing the three bytes turns each helper back into an ordinary ELF that
# binfmt matches; the AppImage runtime does not need them to self-extract
# (APPIMAGE_EXTRACT_AND_RUN=1, set in the Docker image). Done unconditionally:
# it is harmless natively, and the persistent build volume means a helper
# downloaded by an earlier run would otherwise never get patched. The AppImage
# this script PRODUCES keeps its magic untouched -- it is the deliverable.
strip_appimage_magic() { # strip_appimage_magic <file>
    [ -f "$1" ] || return 0
    printf '\0\0\0' | dd of="$1" bs=1 seek=8 count=3 conv=notrunc 2>/dev/null
}

if [ ! -x "$LINUXDEPLOY" ]; then
    echo "--- Downloading linuxdeploy ($ARCH) ..."
    fetch "$LD_BASE/linuxdeploy-${ARCH}.AppImage" "$LINUXDEPLOY"
    chmod +x "$LINUXDEPLOY"
fi
if [ ! -x "$LINUXDEPLOY_QT" ]; then
    echo "--- Downloading linuxdeploy-plugin-qt ($ARCH) ..."
    fetch "$LDQT_BASE/linuxdeploy-plugin-qt-${ARCH}.AppImage" "$LINUXDEPLOY_QT"
    chmod +x "$LINUXDEPLOY_QT"
fi
strip_appimage_magic "$LINUXDEPLOY"
strip_appimage_magic "$LINUXDEPLOY_QT"

# The qt plugin must be found on PATH by linuxdeploy.
export PATH="$WORKDIR:$PATH"

# ---- 3. build the AppImage ----------------------------------------------

# VLC's plugins under usr/lib/.../vlc/plugins are dlopen()ed, so linuxdeploy will
# not discover them from the main binary. Point it at the main executable AND at
# the plugins directory (--deploy-deps-only) so their shared-lib dependencies
# (libav*, libx264, ...) get bundled too.
MAIN_BIN="$(find "$APPDIR" -type f -path '*/usr/bin/powervlc' -print -quit)"
[ -n "$MAIN_BIN" ] || MAIN_BIN="$(find "$APPDIR" -type f -name 'powervlc' -path '*bin*' -print -quit)"
PLUGINS_DIR="$(find "$APPDIR" -type d -name plugins -path '*vlc*' -print -quit)"

# linuxdeploy resolves each ELF's NEEDED libraries through the dynamic linker.
# VLC installs its own libraries in AppDir/usr/lib (libvlc.so.5, libvlccore.so.9)
# AND private helpers in AppDir/usr/lib/vlc (e.g. libvlc_xcb_events.so.0), none of
# which are on the default search path. Add usr/lib and all of its subdirectories
# so every inter-VLC dependency resolves (else: "Could not find dependency: ...").
LIBPATHS="$(find "$APPDIR/usr/lib" -type d 2>/dev/null | paste -sd: -)"
export LD_LIBRARY_PATH="$LIBPATHS:${LD_LIBRARY_PATH:-}"

# linuxdeploy-plugin-qt runs `qmake -query` to locate Qt. On Debian/Ubuntu, qmake
# is a qtchooser wrapper that needs QT_SELECT (or an explicit Qt5 qmake), else it
# fails with: qmake: could not find a Qt installation of ''.
export QT_SELECT=qt5
for _q in /usr/lib/qt5/bin/qmake /usr/bin/qmake-qt5 /usr/lib/*/qt5/bin/qmake; do
    [ -x "$_q" ] && { export QMAKE="$_q"; break; }
done

# The desktop file has Exec=/usr/bin/powervlc (absolute, from @bindir@/powervlc),
# which linuxdeploy cannot match to the deployed executable ("could not find
# suitable executable for Exec entry"). Reduce Exec/TryExec to the basename.
sed -i -E 's,^(Exec=)[^ ]*/powervlc,\1powervlc, ; s,^(TryExec=).*/powervlc$,\1powervlc,' "$DESKTOP_FILE"

set -- --appdir "$APPDIR" --plugin qt \
       --desktop-file "$DESKTOP_FILE" --icon-file "$ICON_FILE"
[ -n "$MAIN_BIN" ]    && set -- "$@" --executable "$MAIN_BIN"
[ -n "$PLUGINS_DIR" ] && set -- "$@" --deploy-deps-only "$PLUGINS_DIR"
set -- "$@" --output appimage

# OUTPUT controls the final AppImage filename (honoured by the appimage plugin).
# ARCH is required by linuxdeploy so it can name/label the AppImage correctly.
echo "--- Running linuxdeploy (qt plugin, appimage output) ..."
echo "  main binary : ${MAIN_BIN:-<none found>}"
echo "  plugins dir : ${PLUGINS_DIR:-<none found>}"
OUTPUT="$OUTFILE" ARCH="$ARCH" "$LINUXDEPLOY" "$@"

echo "=== Done: $WORKDIR/$OUTFILE ==="
