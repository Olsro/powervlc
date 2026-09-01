#!/bin/sh
# Install PowerVLC's own UPnP-free amuled build in its background helper app.
set -eu

APP=${1:-}
[ -d "$APP/Contents/MacOS" ] || {
    echo "usage: AMULED_BINARY=/path/to/amuled $0 /path/to/PowerVLC.app" >&2
    exit 1
}

SOURCE=${AMULED_BINARY:-}
[ -n "$SOURCE" ] && [ -x "$SOURCE" ] || {
    echo "AMULED_BINARY must name PowerVLC's compiled amuled engine" >&2
    exit 1
}

TARGET_ARCHS=$(lipo -archs "$APP/Contents/MacOS/PowerVLC" 2>/dev/null || true)
SOURCE_ARCHS=$(lipo -archs "$SOURCE" 2>/dev/null || true)
for arch in $TARGET_ARCHS; do
    case " $SOURCE_ARCHS " in
        *" $arch "*) ;;
        *) echo "amuled has [$SOURCE_ARCHS], PowerVLC needs [$TARGET_ARCHS]" >&2; exit 1 ;;
    esac
done

if otool -L "$SOURCE" | grep -Eiq '(libupnp|libixml)'; then
    echo "refusing amuled linked to the legacy UPnP stack" >&2
    exit 1
fi

# All third-party dependencies are static. Only OS libraries/frameworks may
# remain dynamic, so the official aMule dependency closure cannot return.
if otool -L "$SOURCE" | awk 'NR > 1 { print $1 }' |
   grep -Ev '^(/usr/lib/|/System/Library/Frameworks/)' >/dev/null; then
    echo "amuled has a non-system dynamic dependency" >&2
    otool -L "$SOURCE" >&2
    exit 1
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
HELPER_APP="$APP/Contents/Helpers/PowerVLC eMule Engine.app"
HELPER_CONTENTS="$HELPER_APP/Contents"
HELPER_BIN="$HELPER_CONTENTS/MacOS/amuled"

mkdir -p "$HELPER_CONTENTS/MacOS" "$APP/Contents/Resources/licenses"
cp "$SCRIPT_DIR/amule-helper-Info.plist" "$HELPER_CONTENTS/Info.plist"
cp -p "$SOURCE" "$HELPER_BIN"
chmod 755 "$HELPER_BIN"
cp "$SCRIPT_DIR/../amule-engine-NOTICE.txt" \
   "$APP/Contents/Resources/licenses/aMule-engine.txt"
rm -f "$APP/Contents/MacOS/amuled"
codesign --force --sign - "$HELPER_APP" >/dev/null 2>&1 || true

echo "embed-amule-engine: installed PowerVLC amuled [$SOURCE_ARCHS]"
