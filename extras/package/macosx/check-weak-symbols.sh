#!/bin/sh
# List every weak-imported symbol of a built bundle.
#
# FSF GCC has no -Werror=partial-availability, so nothing warns when code
# calls an API that is newer than the deployment target. But the linker
# already knows: when the SDK declares a symbol as available only from a
# release newer than -mmacosx-version-min, AvailabilityMacros.h expands to
# __attribute__((weak_import)) and ld records it as "weak external".
#
# On the target OS those symbols resolve to NULL instead of failing the load,
# so an unguarded call jumps to address 0. This script prints exactly the set
# that has to be guarded -- it is the substitute for the missing compiler
# check, and it catches what a header grep cannot (CoreAudio's AudioObject*
# family carries no availability macro at all, yet is weak-imported below
# 10.4).
#
# Usage: check-weak-symbols.sh <path to PowerVLC.app>
#
# A clean run on a target whose minimum is the SDK's own version prints
# nothing. On the 10.3 (g3-panther) slice every line printed must correspond
# to a guarded call site -- see modules/audio_output/coreaudio_compat.h and
# modules/video_output/cgl_lock_compat.h.

set -e

APP="$1"
[ -n "$APP" ] || { echo "usage: $0 <PowerVLC.app>" >&2; exit 1; }
[ -d "$APP" ] || { echo "$0: no such bundle: $APP" >&2; exit 1; }

LT="${VLC_LEGACY_TOOLCHAIN:-$HOME/Projects/darwin-legacy-toolchain}"
NM="$LT/opt/xtools/bin/nm"
[ -x "$NM" ] || NM="$(xcrun --find nm)"

MACOS="$APP/Contents/MacOS"

for f in "$MACOS"/plugins/*.dylib "$MACOS"/lib/*.dylib "$MACOS"/PowerVLC; do
    [ -e "$f" ] || continue
    "$NM" -m "$f" 2>/dev/null | awk -v b="$(basename "$f")" \
        '/undefined.*weak external/ { print substr($4, 2), b }'
done | sort -u | awk '
    { sym = $1; $1 = ""; where[sym] = where[sym] $0 }
    END { for (s in where) print s where[s] }
' | sort
