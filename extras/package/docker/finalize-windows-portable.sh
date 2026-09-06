#!/bin/sh
# Generate plugins.dat with the archive's target-native cache generator under
# Wine, then rebuild and verify the exact portable deliverable.

set -eu

usage() {
    echo "usage: $0 <win32|win64|winarm64> <input.zip> <output.zip>" >&2
    exit 2
}

[ "$#" -eq 3 ] || usage
target=$1
archive=$2
output=$3

case "$target" in
    win32)
        wine_arch=win32
        expected_pe='Intel 80386/i386'
        ;;
    win64)
        wine_arch=win64
        expected_pe='x86-64'
        ;;
    winarm64)
        wine_arch=win64
        # file(1) calls the same PE machine either ARM64 (Debian) or Aarch64
        # (macOS), depending on its magic database version.
        expected_pe='ARM64/Aarch64'
        ;;
    *) usage ;;
esac

case "$archive" in
    *.zip) ;;
    *) echo "ERROR: the portable input must be a ZIP archive: $archive" >&2; exit 1 ;;
esac
[ -f "$archive" ] || {
    echo "ERROR: portable archive not found: $archive" >&2
    exit 1
}
[ ! -e "$output" ] || {
    echo "ERROR: refusing to overwrite existing output: $output" >&2
    exit 1
}
[ "$archive" != "$output" ] || {
    echo "ERROR: input and output archives must differ" >&2
    exit 1
}
archive=$(readlink -f "$archive")
output_parent=$(dirname "$output")
[ -d "$output_parent" ] || {
    echo "ERROR: output directory not found: $output_parent" >&2
    exit 1
}
output=$(cd "$output_parent" && printf '%s/%s\n' "$PWD" "$(basename "$output")")
[ "$archive" != "$output" ] || {
    echo "ERROR: input and output archives resolve to the same path" >&2
    exit 1
}

work=$(mktemp -d /tmp/powervlc-wine-cache.XXXXXXXX)
candidate=$output.partial
cleanup() {
    rm -f -- "$candidate"
    rm -rf -- "$work"
}
trap cleanup EXIT HUP INT TERM

expanded=$work/expanded
verification=$work/verification
mkdir -p "$expanded" "$verification"
unzip -q "$archive" -d "$expanded"

# The release format has exactly one PowerVLC application directory at its
# root.  Shell globbing is safe here because every expansion remains quoted.
set -- "$expanded"/*
[ "$#" -eq 1 ] && [ -d "$1" ] || {
    echo "ERROR: expected exactly one application directory in $archive" >&2
    exit 1
}
root=$1
generator=$root/powervlc-cache-gen.exe
plugins=$root/plugins
cache=$plugins/plugins.dat

[ -f "$generator" ] || {
    echo "ERROR: cache generator missing from portable tree: $generator" >&2
    exit 1
}
[ -d "$plugins" ] || {
    echo "ERROR: plug-in directory missing from portable tree: $plugins" >&2
    exit 1
}

pe_description=$(file -b "$generator")
case "$target:$pe_description" in
    win32:*'Intel 80386'* | win32:*'Intel i386'* | win64:*x86-64* | \
    winarm64:*ARM64* | winarm64:*Aarch64*) ;;
    *)
        echo "ERROR: $target archive contains the wrong cache generator architecture" >&2
        echo "       expected $expected_pe, found: $pe_description" >&2
        exit 1
        ;;
esac

rm -f -- "$cache"
export WINEARCH=$wine_arch
export WINEPREFIX=$work/wineprefix
export WINEDEBUG=-all
export WINEDLLOVERRIDES=mscoree,mshtml=

run_wine() {
    xvfb-run -a -s '-screen 0 640x480x24' "$@"
}

echo "  CACHE    $target plugins.dat (Wine on $(uname -m))"
plugins_windows=Z:$(printf '%s' "$plugins" | sed 's|/|\\|g')
(
    cd "$root"
    # Keep Wine's helper processes on the same temporary X server until they
    # are shut down. Starting wineboot and winepath in separate xvfb-run calls
    # leaves their background clients attached to displays that have vanished.
    run_wine sh -c '
        wine ./powervlc-cache-gen.exe "$1"
        wine_status=$?
        wineserver -k >/dev/null 2>&1 || true
        wineserver -w >/dev/null 2>&1 || true
        exit "$wine_status"
    ' sh "$plugins_windows"
)

[ -f "$cache" ] || {
    echo "ERROR: powervlc-cache-gen.exe did not create plugins/plugins.dat" >&2
    exit 1
}
cache_bytes=$(wc -c < "$cache" | tr -d ' ')
[ "$cache_bytes" -ge 1024 ] || {
    echo "ERROR: generated plug-in cache is unexpectedly small: $cache_bytes bytes" >&2
    exit 1
}

# cache-gen historically returns success even if individual plug-ins could not
# be loaded. Check every packaged module path, otherwise a superficially valid
# cache can silently omit codecs whose private runtime dependency was missing.
missing_plugins=$work/missing-plugins.txt
find "$plugins" -type f -iname '*_plugin.dll' -print | while IFS= read -r plugin; do
    relative=${plugin#"$plugins"/}
    relative_windows=$(printf '%s' "$relative" | sed 's|/|\\|g')
    if ! LC_ALL=C grep -aiFq "$relative_windows" "$cache"; then
        printf '%s\n' "$relative" >> "$missing_plugins"
    fi
done
if [ -s "$missing_plugins" ]; then
    echo "ERROR: generated cache omitted these packaged plug-ins:" >&2
    sed 's/^/       /' "$missing_plugins" >&2
    exit 1
fi

# Create the archive from the directory containing the single application
# root, preserving the DLL timestamps that the cache uses for stale detection.
(cd "$expanded" && zip -q -r -9 "$candidate" .)
unzip -tqq "$candidate"
unzip -q "$candidate" -d "$verification"

verified_cache=$(find "$verification" -type f -path '*/plugins/plugins.dat' -print)
[ -n "$verified_cache" ] && [ "$(printf '%s\n' "$verified_cache" | wc -l | tr -d ' ')" -eq 1 ] || {
    echo "ERROR: finalized archive does not contain exactly one plugins.dat" >&2
    exit 1
}
verified_bytes=$(wc -c < "$verified_cache" | tr -d ' ')
[ "$verified_bytes" -eq "$cache_bytes" ] || {
    echo "ERROR: plug-in cache changed while rebuilding the archive" >&2
    exit 1
}

mv -- "$candidate" "$output"
trap - EXIT HUP INT TERM
rm -rf -- "$work"

echo "FINALIZED_ARCHIVE=$output"
echo "PLUGIN_CACHE_BYTES=$cache_bytes"
echo "SHA256=$(sha256sum "$output" | cut -d' ' -f1)"
