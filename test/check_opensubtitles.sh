#!/bin/sh
set -e
cd "$(dirname "$0")/.."
for candidate in contrib/*/bin/lua lua5.1 lua; do
    if command -v "$candidate" >/dev/null 2>&1; then
        exec "$candidate" test/check_opensubtitles.lua
    fi
done
echo 'check_opensubtitles: no Lua interpreter found' >&2
exit 77
