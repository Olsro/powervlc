#! /bin/sh
set -e

SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
cd "${SCRIPT_PATH}/.."

LUA=""
for candidate in contrib/*/bin/lua lua5.1 lua; do
    if [ -x "$candidate" ]; then LUA="$candidate"; break; fi
    if command -v "$candidate" >/dev/null 2>&1; then LUA="$candidate"; break; fi
done
if [ -z "$LUA" ]; then
    echo "check_twitch_extension: no Lua interpreter found, skipping" >&2
    exit 0
fi

"$LUA" test/check_twitch_extension.lua \
    share/lua/extensions/Twitch.lua share/lua/modules
