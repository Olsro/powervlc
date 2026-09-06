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

# The native AppImage recipe already builds the private eMule engine. Cross
# packages must do the same with the target compiler; otherwise the extension
# is present but can only report that its bundled amuled is missing.
amule_target=linux-$arch
AMULE_BUILD_ROOT="/work/build/dependencies/amule/$amule_target" \
AMULE_DOWNLOADS=/work/contrib/tarballs \
AMULE_HOST="$triplet" AMULE_SYSROOT="$sysroot" \
AMULE_ARCH_FLAGS="--sysroot=$sysroot" \
CC="$triplet-gcc" CXX="$triplet-g++" AR="$triplet-ar" \
RANLIB="$triplet-ranlib" STRIP="$triplet-strip" \
  /work/extras/package/build-amule-engine.sh "$amule_target"
amule_private_dir="$appdir/usr/lib/vlc/powervlc-helpers"
mkdir -p "$amule_private_dir"
install -m 0755 \
  "/work/build/dependencies/amule/$amule_target/prefix/bin/amuled" \
  "$amule_private_dir/amuled"
install -m 0644 /work/extras/package/amule-engine-NOTICE.txt \
  "$amule_private_dir/aMule-engine.txt"

install -m 0755 /work/extras/package/linux/powervlc-kms3d-run \
  "$appdir/usr/bin/powervlc-kms3d-run"
install -m 0755 /work/extras/package/linux/powervlc-kms3d-input.py \
  "$appdir/usr/bin/powervlc-kms3d-input.py"
mkdir -p "$appdir/usr/share/doc/powervlc"
install -m 0644 /work/extras/package/linux/README.hdmi-3d.md \
  "$appdir/usr/share/doc/powervlc/README.hdmi-3d.md"

# Intel's native Dolby Vision transport has no upstream DRM property yet. Ship
# the restricted static helper beside PowerVLC so it remains independent of
# the distribution's IGT/libdrm versions. It still requires an explicit root
# launch and refuses every connector/register layout it does not recognise.
dovi_helper_src=/work/extras/package/linux/powervlc-intel-dovi-helper.c
if [ -f "$dovi_helper_src" ]; then
  dovi_helper_dir="$appdir/usr/lib/vlc/powervlc-helpers"
  mkdir -p "$dovi_helper_dir"
  "$triplet-gcc" -O2 -static -s -o \
    "$dovi_helper_dir/powervlc-intel-dovi-helper" "$dovi_helper_src"
  cp /work/extras/package/linux/README.dolby-vision.md \
    "$dovi_helper_dir/README.dolby-vision.md"
fi

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
if [ "${1:-}" = --direct-hdmi-3d ]; then
  shift
  app=${APPIMAGE:-$here/AppRun}
  exec "$here/usr/bin/powervlc-kms3d-run" "$app" "$@"
fi
# Modern Mesa/NVIDIA drivers may require a newer system libstdc++ than the
# portable GCC 11 copy. Prefer the host copy when it has GCC 11 symbols; old
# distributions fall back to the bundled one. powervlc-runtime contains every
# bundled dependency except libstdc++ and the host graphics ABI.
runtime="$here/usr/lib/powervlc-runtime"
for system_stdcpp in /usr/lib/*/libstdc++.so.6 /lib/*/libstdc++.so.6; do
  if [ -r "$system_stdcpp" ] && grep -aq 'GLIBCXX_3.4.29' "$system_stdcpp"; then
    libdir="$runtime"
    break
  fi
done
libdir="${libdir:-$here/usr/lib}"
export LD_LIBRARY_PATH="$libdir:$here/usr/lib/vlc${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export VLC_PLUGIN_PATH="$here/usr/lib/vlc/plugins"
export QT_PLUGIN_PATH="$here/usr/lib/qt5/plugins"
export QT_QPA_PLATFORM_PLUGIN_PATH="$QT_PLUGIN_PATH/platforms"
# libbluray's compiled-in class path points at the build host. Keep BD-J menus
# self-contained after extraction and across reboots by resolving both bundled
# jars from the AppDir at runtime.
export LIBBLURAY_CP="$here/usr/share/java/"
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

# The display driver, its dispatch libraries and its X11/Wayland client stack
# are one ABI unit supplied by the host. Bundling Ubuntu 18.04 copies made GLX
# configuration fail on Mesa 26 and can also prevent proprietary NVIDIA from
# loading. Keep codecs/Qt portable while always using the installed GPU stack.
is_host_graphics() {
  case "$1" in
    libGL*.so.*|libOpenGL.so.*|libEGL.so.*|libGLES*.so.*|libvulkan.so.*|\
    libdrm*.so.*|libgbm.so.*|libX11.so.*|libxcb.so.*|libxkbcommon*.so.*|\
    libxshmfence.so.*|libwayland*.so.*) return 0 ;;
  esac
  return 1
}

while IFS= read -r elf; do
  [ -f "$elf" ] || continue
  "$triplet-objdump" -p "$elf" 2>/dev/null |
    awk '/NEEDED/ { print $2 }' | while IFS= read -r soname; do
      is_glibc "$soname" && continue
      is_host_graphics "$soname" && continue
      target="$appdir/usr/lib/$soname"
      [ -e "$target" ] && continue
      source="$(find "$contrib/lib" "$sysroot/lib" "$sysroot/usr/lib" -name "$soname" -print -quit 2>/dev/null || true)"
      [ -n "$source" ] || continue
      mkdir -p "$appdir/usr/lib"
      cp -L "$source" "$target"
      printf '%s\n' "$target" >> "$needed"
    done
done < "$needed"

# A filtered search directory lets a modern host provide libstdc++ without
# losing the other bundled dependencies. Relative symlinks remain valid after
# the AppImage is mounted at its runtime path.
safe_runtime="$appdir/usr/lib/powervlc-runtime"
mkdir -p "$safe_runtime"
for library in "$appdir/usr/lib"/*; do
  [ -f "$library" ] || [ -L "$library" ] || continue
  name="${library##*/}"
  [ "$name" = libstdc++.so.6 ] && continue
  is_host_graphics "$name" && { rm -f "$library"; continue; }
  ln -sf "../$name" "$safe_runtime/$name"
done

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
