#!/bin/sh
# Build Qt 5.6's host tools on arm64 and its libraries for the requested x86
# target. Qt's configure separates host tools from target libraries, so this
# never executes an x86 program.
set -eu

case "${1:-}" in
  amd64) target=x86_64-linux-gnu ;;
  i386) target=i686-linux-gnu ;;
  *) echo "Usage: $0 amd64|i386" >&2; exit 64 ;;
esac

version=5.6.3
root=/work/.qt-cross/$target
src=/work/.qt-cross/src/qtbase-opensource-src-$version
build=$root/build
prefix=/work/contrib-$target-glibc227
hostprefix=$root/host-tools
sysroot=/opt/sysroots/$target-glibc-2.27
driver=/work/.toolchains/prefix/$target/driver-bin/$target-

mkdir -p /work/.qt-cross/src "$root"
if [ ! -d "$src" ]; then
  archive=/work/.qt-cross/src/qtbase-opensource-src-$version.tar.xz
  [ -f "$archive" ] || curl -fL --retry 3 -o "$archive" \
    "https://download.qt.io/archive/qt/5.6/$version/submodules/qtbase-opensource-src-$version.tar.xz"
  tar -C /work/.qt-cross/src -xf "$archive"
fi

if [ ! -f "$build/Makefile" ]; then
  mkdir -p "$build"
  cd "$build"
  "$src/configure" -opensource -confirm-license -release \
    -xplatform linux-g++ -device-option "CROSS_COMPILE=$driver" \
    -sysroot "$sysroot" -prefix "$prefix" -hostprefix "$hostprefix" \
    -no-pch -nomake examples -nomake tests -no-qml-debug \
    -no-sql-sqlite -no-sql-odbc -no-openssl -no-dbus -no-audio-backend \
    -system-zlib -qt-libjpeg -qt-libpng
fi
make -C "$build" -j"$(nproc)" sub-src
make -C "$build" install

for pc in Qt5Core Qt5Gui Qt5Widgets; do
  test -f "$prefix/lib/pkgconfig/$pc.pc"
done
echo "OK: Qt $version cross-built for $target."
