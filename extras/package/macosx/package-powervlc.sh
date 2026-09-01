#!/bin/sh
# Zip a PowerVLC bundle as powervlc-<version>-mac-<architecture>.zip.
#
# Usage: package-powervlc.sh <x64|x86|g3|g4|g5|arm64|universal>
# The version is read from the bundle's Info.plist
# (CFBundleShortVersionString); the architecture label is the build
# target name. The "mac" tag keeps these archives distinguishable from
# the Windows/Linux ones, whose target names already carry the platform
# (win64, linux-x86_64...). The zip is written next to the bundle.
set -e

TARGET="$1"
[ -n "$TARGET" ] || { echo "usage: $0 <target>" >&2; exit 1; }

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
VLCROOT=$(cd "$SCRIPTDIR/../../.." && pwd)
BUILDDIR="$VLCROOT/build/macos/$TARGET"
APP="$BUILDDIR/PowerVLC.app"
[ -d "$APP" ] || { echo "missing bundle: $APP" >&2; exit 1; }

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" \
    "$APP/Contents/Info.plist" 2>/dev/null)
[ -n "$VERSION" ] || { echo "cannot read bundle version" >&2; exit 1; }

ZIP="$BUILDDIR/powervlc-$VERSION-mac-$TARGET.zip"
rm -f "$ZIP"
(cd "$BUILDDIR" && zip -qry "$(basename "$ZIP")" PowerVLC.app)
echo "$ZIP"
