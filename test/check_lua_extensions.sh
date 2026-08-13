#! /bin/sh
# Every Lua extension must survive being loaded by the SCANNER, which is
# not the same thing as being valid Lua.
#
# The scanner reads descriptor() -- the function that names the menu
# entry -- in a bare Lua state: no libraries at all, `require` replaced by
# a stub that returns nothing (modules/lua/extension.c, ScanExtensions).
# Only `string` and vlc.config.language() are put back, because they
# compute and read and nothing else. So ANY library call at file level --
# `package.config`, `io.open`, `os.time`, a `require` whose result is
# indexed -- raises while the file is being loaded, and the extension is
# then simply absent from the menu. Nothing anywhere says why: there is no
# error in the log, no warning, no half-loaded extension. Just a menu
# entry that is not there.
#
# It has happened twice. This makes it a build failure instead.
set -e

SCRIPT_PATH="$( cd "$(dirname "$0")" ; pwd -P )"
cd "${SCRIPT_PATH}/.."

# A 5.1 interpreter: the contribs build one, and it is the same one the
# player embeds. Anything else on the machine will do as well.
LUA=""
for candidate in contrib/*/bin/lua lua5.1 lua; do
    if [ -x "$candidate" ]; then LUA="$candidate"; break; fi
    if command -v "$candidate" >/dev/null 2>&1; then LUA="$candidate"; break; fi
done
if [ -z "$LUA" ]; then
    echo "check_lua_extensions: no Lua interpreter found, skipping" >&2
    exit 0
fi

harness=$(mktemp -t luascan)
cat > "$harness" <<'LUA'
local file = arg[1]
-- exactly what ScanExtensions() leaves in the state
local env = {
  require = function() return nil end,
  string  = string,
  vlc     = { config = { language = function() return "en" end } },
}
local chunk, err = loadfile(file)
if not chunk then
  print("does not compile: " .. tostring(err))
  os.exit(1)
end
setfenv(chunk, env)
local ok, err2 = pcall(chunk)
if not ok then
  print("dies while loading, so it will NOT appear in the menu:")
  print("  " .. tostring(err2))
  os.exit(1)
end
if type(env.descriptor) ~= "function" then
  print("no descriptor() -- nothing would name the menu entry")
  os.exit(1)
end
local ok2, d = pcall(env.descriptor)
if not ok2 or type(d) ~= "table" or not d.title then
  print("descriptor() does not return a title: " .. tostring(d))
  os.exit(1)
end
LUA

status=0
for ext in share/lua/extensions/*.lua; do
    test -f "$ext" || continue
    if out=$("$LUA" "$harness" "$ext" 2>&1); then
        echo "  ok      ${ext##*/}"
    else
        echo "  FAILED  ${ext##*/}: $out" >&2
        status=1
    fi
done
rm -f "$harness"

if [ "$status" -ne 0 ]; then
    echo "" >&2
    echo "An extension that dies in the scanner is invisible in the menu," >&2
    echo "with nothing in the log to say so. Move whatever it does at file" >&2
    echo "level into activate(), which runs in a complete Lua state." >&2
fi
exit "$status"
