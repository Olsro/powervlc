#!/bin/sh
# Assemble a Type-2 AppImage without running any target executable.  The
# squashfs tool runs on arm64; the x86 runtime is only concatenated as data.
set -eu

case "${1:-}" in
  amd64) arch=x86_64; runtime_arch=x86_64; triplet=x86_64-linux-gnu; sysarch=x86_64-linux-gnu ;;
  i386)  arch=i386; runtime_arch=i686; triplet=i686-linux-gnu; sysarch=i386-linux-gnu ;;
  *) echo "Usage: $0 amd64|i386" >&2; exit 64 ;;
esac

build=/work/cross-$1
appdir=/work/AppDir-$1
runtime=/work/.appimage-runtime-$arch
outfile=/work/PowerVLC-${PVLC_VER}-$arch.AppImage
toolchain=/work/.toolchains/prefix/$triplet
sysroot=/opt/sysroots/${triplet}-glibc-2.27
contrib=/work/contrib-${triplet}-glibc227

rm -rf "$appdir" "$outfile"
make -C "$build" install DESTDIR="$appdir"

# Lua bytecode is architecture-dependent. Cross builds generate .luac with the
# native arm64 host tool, which i386/x86_64 Lua cannot load. Ship the matching
# source scripts instead; VLC compiles them on the target at runtime.
lua_dest="$appdir/usr/lib/vlc/lua"
if [ -d "$lua_dest" ] && [ -d /work/share/lua ]; then
  find "$lua_dest" -type f -name '*.luac' -delete
  find /work/share/lua -type f -name '*.lua' -print | while IFS= read -r source; do
    relative="${source#/work/share/lua/}"
    destination="$lua_dest/$relative"
    mkdir -p "$(dirname "$destination")"
    cp "$source" "$destination"
  done
fi

# AppImage's launcher must be a script because this package is assembled by an
# arm64 host but launches the target binary only on the target machine.
cat >"$appdir/AppRun" <<'EOF'
#!/bin/sh
here="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
export LD_LIBRARY_PATH="$here/usr/lib:$here/usr/lib/vlc${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export VLC_PLUGIN_PATH="$here/usr/lib/vlc/plugins"
export QT_PLUGIN_PATH="$here/usr/lib/qt5/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$QT_PLUGIN_PATH/platforms"
exec "$here/usr/bin/powervlc" "$@"
EOF
chmod 0755 "$appdir/AppRun"

desktop="$(find "$appdir" -name vlc.desktop -print -quit)"
[ -n "$desktop" ] && ln -s "${desktop#"$appdir"/}" "$appdir/powervlc.desktop"
icon="$(find "$appdir" -name powervlc.png -print -quit)"
[ -n "$icon" ] && ln -s "${icon#"$appdir"/}" "$appdir/.DirIcon"

# libstdc++ is part of the self-contained C++ toolchain; glibc deliberately
# stays external so the binary continues to honour the documented 2.27 floor.
stdcpp="$(find -L "$toolchain" -name libstdc++.so.6 -type f -print -quit)"
if [ -n "$stdcpp" ]; then
  mkdir -p "$appdir/usr/lib"
  cp -L "$stdcpp" "$appdir/usr/lib/libstdc++.so.6"
fi

# Qt is a target library just like FFmpeg: copy its plugins and resolve every
# target ELF dependency without executing it.  This is the cross equivalent of
# linuxdeploy's bundling pass in the native arm64 recipe.
qtplugins="$sysroot/usr/lib/$sysarch/qt5/plugins"
if [ -d "$qtplugins" ]; then
  mkdir -p "$appdir/usr/lib/qt5"
  cp -a "$qtplugins" "$appdir/usr/lib/qt5/"
fi

needed=/tmp/powervlc-needed-$arch
: > "$needed"
find "$appdir/usr" -type f -print > "$needed"

is_glibc() {
  case "$1" in
    ld-linux*.so*|libc.so.*|libm.so.*|libdl.so.*|libpthread.so.*|librt.so.*|libresolv.so.*|libutil.so.*|libnsl.so.*) return 0 ;;
  esac
  return 1
}

while IFS= read -r elf; do
  [ -f "$elf" ] || continue
  "$triplet-objdump" -p "$elf" 2>/dev/null |
    awk '/NEEDED/ { print $2 }' | while IFS= read -r soname; do
      is_glibc "$soname" && continue
      target="$appdir/usr/lib/$soname"
      [ -e "$target" ] && continue
      source="$(find "$contrib/lib" "$sysroot/lib" "$sysroot/usr/lib" -name "$soname" -print -quit 2>/dev/null || true)"
      [ -n "$source" ] || continue
      mkdir -p "$appdir/usr/lib"
      cp -L "$source" "$target"
      printf '%s\n' "$target" >> "$needed"
    done
done < "$needed"

if [ ! -f "$runtime" ]; then
  curl -fL --retry 3 -o "$runtime" \
    "https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-$runtime_arch"
  chmod 0755 "$runtime"
fi
mksquashfs "$appdir" "$outfile.squashfs" -noappend -comp zstd >/dev/null
cat "$runtime" "$outfile.squashfs" > "$outfile"
chmod 0755 "$outfile"
rm -f "$outfile.squashfs"

file "$outfile"
echo "OK: native-arm64 packaging produced $outfile"
