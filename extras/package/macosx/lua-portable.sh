#!/bin/sh
# Make a bundle's Lua scripts architecture-portable.
#
# Usage: lua-portable.sh <PowerVLC.app>
#
# VLC installs precompiled Lua chunks (*.luac). Lua bytecode is NOT
# portable: its header encodes endianness and the width of int/size_t/
# lua_Number, so a chunk compiled by the build host's luac (little-endian
# 64-bit here) is rejected on a PowerPC (big-endian) or 32-bit target with
# "bad header in precompiled chunk" — every Lua service discovery (Jamendo,
# Icecast, …) then fails to load. A single universal bundle spans PPC, i386,
# x86_64 and arm64, so no one bytecode format can satisfy all of them.
#
# VLC's Lua loader detects source vs bytecode from the first byte (\033Lua),
# not the extension, so we overwrite each installed *.luac with its *.lua
# SOURCE (keeping the .luac name the loader looks for). The interpreter then
# compiles it at runtime on whatever architecture is actually running.
set -e

APP="$1"
[ -n "$APP" ] || { echo "usage: $0 <bundle.app>" >&2; exit 1; }

SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
VLCROOT=$(cd "$SCRIPTDIR/../../.." && pwd)
SRC="$VLCROOT/share/lua"
LUADIR="$APP/Contents/MacOS/share/lua"
[ -d "$LUADIR" ] || exit 0

count=0
find "$LUADIR" -name '*.luac' | while IFS= read -r f; do
    rel=${f#"$LUADIR"/}                  # e.g. sd/jamendo.luac
    src="$SRC/${rel%.luac}.lua"          # share/lua/sd/jamendo.lua
    if [ -f "$src" ]; then
        cp "$src" "$f"                   # .luac name, portable source body
        count=$((count + 1))
    else
        echo "  lua-portable: no source for $rel (left as bytecode)" >&2
    fi
done
echo "lua-portable: sourced Lua scripts in $(basename "$APP")"
