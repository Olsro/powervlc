#!/bin/sh
# Recompile the PowerVLC app icon catalog (Assets.car) from AppIcon.icon.
#
# AppIcon.icon is an Icon Composer document: layered SVGs plus icon.json, which
# holds the colours. macOS 26 and later render it with the "liquid glass"
# material; macOS 11 to 15 use the flattened renditions actool bakes into the
# same catalog. Older systems ignore the catalog entirely and keep VLC.icns.
#
# The result is committed to the tree because compiling it needs Xcode 26 or
# newer, which the PowerPC/Intel build hosts do not have. Run this only after
# editing AppIcon.icon, then commit the regenerated Assets.car.
#
# The PowerVLC red lives in the three "fill-specializations" gradients of
# icon.json (two "odd stripes" layers and the cone "base"):
#     srgb:1.00000,0.09412,0.00000  rgb(255,24,0)  cone top / lit side
#     srgb:0.84706,0.12549,0.00000  rgb(216,32,0)  cone bottom / shadow side
# They mirror the gradients of extras/package/macosx/asset_sources/vlc_app_icon.svg.

set -e

# Deployment target of the modern (arm64) bundle: renditions are baked for
# every OS from this version up.
MIN_TARGET="11.0"

srcdir="$(cd "$(dirname "$0")/../../.." && pwd)"
icondir="$srcdir/modules/gui/macosx/Resources/App-Icons"
iconset="$icondir/AppIcon.icon"

if [ ! -d "$iconset" ]; then
    echo "ERROR: $iconset not found" >&2
    exit 1
fi

if ! xcrun -f actool >/dev/null 2>&1; then
    echo "ERROR: actool not found; Xcode 26 or later is required" >&2
    exit 1
fi

actool_version=$(xcrun actool --version 2>/dev/null \
    | sed -n 's/.*<string>\([0-9][0-9]*\)\..*<\/string>.*/\1/p' | head -n 1)
if [ -n "$actool_version" ] && [ "$actool_version" -lt 26 ]; then
    echo "ERROR: actool $actool_version is too old, Xcode 26 or later is required" >&2
    exit 1
fi

# actool resolves relative --compile paths against a cached working directory
# and then silently writes somewhere else, so always hand it absolute paths.
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/out"

xcrun actool --compile "$tmpdir/out" \
    --platform macosx \
    --minimum-deployment-target "$MIN_TARGET" \
    --app-icon AppIcon \
    --output-partial-info-plist "$tmpdir/partial.plist" \
    --errors --warnings \
    "$iconset" >/dev/null

if [ ! -f "$tmpdir/out/Assets.car" ]; then
    echo "ERROR: actool did not produce Assets.car" >&2
    exit 1
fi

# Only the catalog is shipped. actool also emits an AppIcon.icns fallback, which
# we drop: pre-11.0 systems use our own hand-drawn VLC.icns instead.
cp "$tmpdir/out/Assets.car" "$icondir/Assets.car"

echo "Regenerated $icondir/Assets.car (deployment target $MIN_TARGET)"
echo "Remember to keep CFBundleIconName set to AppIcon in share/Info.plist.in"
