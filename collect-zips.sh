#!/bin/bash
# Gather the release archives produced by the packaging scripts into a single
# zips/ folder at the repository root.
#
# Sources:
#   build*/                       macOS bundles  (package-powervlc.sh)
#   extras/package/docker/out/    Windows & Linux builds (build-in-docker.sh)
#
# Nothing else is touched: the .zip files vendored under contrib/tarballs/ and
# the ones shipped inside contrib/extras sources stay where they are.

set -u

cd "$(dirname "$0")" || exit 1
ROOT="$(pwd)"
DEST="$ROOT/zips"

mkdir -p "$DEST" || exit 1

moved=0
skipped=0

move_zip() {
    src="$1"
    name="$(basename "$src")"
    dst="$DEST/$name"

    if [ -e "$dst" ]; then
        if cmp -s "$src" "$dst"; then
            # Same archive already collected: drop the duplicate.
            rm -f "$src"
            echo "  = $name (already in zips/, source removed)"
            skipped=$((skipped + 1))
            return
        fi
        echo "  ! $name (replacing older copy in zips/)"
    fi

    if mv -f "$src" "$dst"; then
        echo "  -> $name"
        moved=$((moved + 1))
    else
        echo "  !! failed to move $src" >&2
    fi
}

echo "Collecting zips into $DEST"

# macOS bundles: build<target>/powervlc-<version>-mac-<target>.zip
for d in "$ROOT"/build*/; do
    [ -d "$d" ] || continue
    for z in "$d"*.zip; do
        [ -f "$z" ] || continue
        move_zip "$z"
    done
done

# Windows & Linux artifacts
OUT="$ROOT/extras/package/docker/out"
if [ -d "$OUT" ]; then
    for z in "$OUT"/*.zip; do
        [ -f "$z" ] || continue
        move_zip "$z"
    done
fi

echo
echo "$moved moved, $skipped duplicate(s) discarded — $(ls -1 "$DEST"/*.zip 2>/dev/null | wc -l | tr -d ' ') archive(s) in zips/"
