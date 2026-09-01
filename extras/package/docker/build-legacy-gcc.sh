#!/bin/sh
# Build a native-arm64 GCC cross toolchain whose target C/C++ runtime is the
# Bionic (glibc 2.27) sysroot.  Unlike Ubuntu's packaged cross GCC, this never
# mixes target headers or libstdc++ from a newer glibc release.
set -eu

case "${1:-}" in
  amd64) target=x86_64-linux-gnu; sysarch=x86_64-linux-gnu ;;
  i386)  target=i686-linux-gnu; sysarch=i386-linux-gnu ;;
  *) echo "Usage: $0 amd64|i386" >&2; exit 64 ;;
esac

version=11.5.0
root=/work/.toolchains
src="$root/src/gcc-$version"
build="$root/build/$target"
prefix="$root/prefix/$target"
sysroot="/opt/sysroots/$target-glibc-2.27"

[ -f "$sysroot/.powervlc-sysroot" ] || { echo "Missing $sysroot" >&2; exit 1; }
mkdir -p "$root/src" "$root/build" "$root/prefix"

if [ ! -d "$src" ]; then
  archive="$root/src/gcc-$version.tar.xz"
  curl -fL --retry 3 -o "$archive" \
    "https://ftp.gnu.org/gnu/gcc/gcc-$version/gcc-$version.tar.xz"
  tar -C "$root/src" -xf "$archive"
  ( cd "$src" && contrib/download_prerequisites )
fi

if [ ! -f "$build/Makefile" ]; then
  mkdir -p "$build"
  ( cd "$build" && "$src/configure" \
      --target="$target" --prefix="$prefix" --with-sysroot="$sysroot" \
      --with-native-system-header-dir=/usr/include \
      --enable-languages=c,c++ --disable-bootstrap --disable-multilib \
      --disable-nls --disable-libsanitizer --disable-libquadmath )
fi

make -C "$build" -j"$(nproc)" all-gcc all-target-libgcc all-target-libstdc++-v3
make -C "$build" install-gcc install-target-libgcc install-target-libstdc++-v3

# This GCC was built without binutils of its own.  Its driver invokes the
# generic names (as, ld, …), so place target-binutils links beside the driver.
# COMPILER_PATH lets the target compiler find them without polluting PATH for
# native helper programs (FFmpeg's HOSTCC must still assemble arm64 objects).
for tool in ar as ld nm objcopy objdump ranlib readelf strip; do
  ln -sfn "/usr/bin/$target-$tool" "$prefix/bin/$tool"
done
mkdir -p "$prefix/driver-bin"
for driver in c++ cpp g++ gcc; do
  driver_path="$prefix/driver-bin/$target-$driver"
  rm -f "$driver_path"
  printf '%s\n' '#!/bin/sh' \
    "COMPILER_PATH='$prefix/bin' exec '$prefix/bin/$target-$driver' \"\$@\"" \
    > "$driver_path"
  chmod +x "$driver_path"
done

cat >"$root/test-$target.cc" <<'EOF'
#include <string>
int main() { return std::string("powervlc").empty(); }
EOF
"$prefix/driver-bin/$target-g++" "$root/test-$target.cc" -o "$root/test-$target"
max_glibc="$(objdump -T "$root/test-$target" | sed -n 's/.*\(GLIBC_[0-9.]*\).*/\1/p' | sort -Vu | tail -1)"
[ -z "$max_glibc" ] || [ "$(printf '%s\n' "$max_glibc" GLIBC_2.27 | sort -V | head -1)" = "$max_glibc" ] || {
  echo "ERROR: toolchain emitted $max_glibc, expected glibc <= 2.27" >&2
  exit 1
}
echo "OK: $target GCC $version targets $max_glibc (Bionic sysroot)."
