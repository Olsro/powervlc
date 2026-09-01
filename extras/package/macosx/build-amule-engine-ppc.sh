#!/bin/sh
# Build the minimal aMule 3.0.1 engine for one PowerVLC PowerPC target.
set -eu

TARGET=${1:-g3}
case "$TARGET" in
    g3) CPU_FLAGS="-mcpu=750 -mtune=750"; CONTRIB_NAME=powerpc-apple-darwin8-jaguar ;;
    g4) CPU_FLAGS="-mcpu=7400 -mtune=7400 -maltivec"; CONTRIB_NAME=powerpc-apple-darwin8-av ;;
    g5) CPU_FLAGS="-mcpu=970 -mtune=970 -maltivec"; CONTRIB_NAME=powerpc-apple-darwin8-av ;;
    *) echo "usage: $0 <g3|g4|g5>" >&2; exit 1 ;;
esac

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../../.." && pwd)
PATCH_DIR="$SCRIPT_DIR/amule-ppc"
TOOLS=${VLC_LEGACY_TOOLCHAIN:-"$HOME/Projects/darwin-legacy-toolchain"}
SDK="$TOOLS/sdks/MacOSX10.4u.sdk"
CONTRIB="$ROOT/contrib/$CONTRIB_NAME"
BUILD_ROOT=${AMULE_PPC_BUILD_ROOT:-"$ROOT/build/dependencies/amule/$TARGET"}
PREFIX="$BUILD_ROOT/prefix"
SOURCES="$BUILD_ROOT/sources"
DOWNLOADS="$BUILD_ROOT/downloads"

AMULE_COMMIT=02db0d7faecfc377694ff6242bc23346185990ed
WX_COMMIT=896e4f587615b832ce27b8325357cb504997e1d3
CRYPTOPP_COMMIT=843d74c7c97f9e19a615b8ff3c0ca06599ca501b
BOOST_ARCHIVE=boost_1_88_0.tar.bz2
BOOST_SHA256=46d9d2c06637b219270877c9e16155cbd015b6dc84349af064c088e9b5b12f7b

CC="$TOOLS/opt/gcc-ppc-tiger/bin/tiger-cc"
CXX="$TOOLS/opt/gcc-ppc-tiger/bin/tiger-c++"
AR="$TOOLS/opt/gcc-ppc-tiger/bin/powerpc-apple-darwin8-gcc-ar"
RANLIB="$TOOLS/opt/gcc-ppc-tiger/bin/powerpc-apple-darwin8-gcc-ranlib"
STRIP="$TOOLS/opt/xtools/bin/strip"

for tool in git curl cmake ninja shasum tar; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
for file in "$CC" "$CXX" "$AR" "$RANLIB" "$STRIP" "$SDK/usr/include/stdio.h" \
            "$CONTRIB/lib/libz.a"; do
    [ -e "$file" ] || { echo "missing PowerVLC build prerequisite: $file" >&2; exit 1; }
done

mkdir -p "$BUILD_ROOT" "$PREFIX/include" "$PREFIX/lib" "$PREFIX/bin" \
         "$SOURCES" "$DOWNLOADS"
JOBS=$(sysctl -n hw.ncpu 2>/dev/null || echo 2)

checkout_exact()
{
    url=$1 commit=$2 destination=$3
    if [ ! -d "$destination/.git" ]; then
        mkdir -p "$destination"
        git -C "$destination" init -q
        git -C "$destination" remote add origin "$url"
        git -C "$destination" fetch -q --depth 1 origin "$commit"
        git -C "$destination" checkout -q --detach FETCH_HEAD
    fi
    actual=$(git -C "$destination" rev-parse HEAD)
    [ "$actual" = "$commit" ] || {
        echo "$destination is at $actual, expected $commit" >&2
        exit 1
    }
}

apply_once()
{
    source_dir=$1 patch_file=$2
    if git -C "$source_dir" apply --reverse --check --unidiff-zero "$patch_file" 2>/dev/null; then
        return
    fi
    git -C "$source_dir" apply --check --unidiff-zero "$patch_file"
    git -C "$source_dir" apply --unidiff-zero "$patch_file"
}

echo "[amuled-$TARGET] fetching pinned sources"
checkout_exact https://github.com/amule-org/amule.git "$AMULE_COMMIT" "$SOURCES/amule"
checkout_exact https://github.com/wxWidgets/wxWidgets.git "$WX_COMMIT" "$SOURCES/wxwidgets"
checkout_exact https://github.com/weidai11/cryptopp.git "$CRYPTOPP_COMMIT" "$SOURCES/cryptopp"
# The depth-one commit fetch does not carry the annotated release tag. CMake
# uses that tag to select release EC compatibility rather than snapshot mode.
git -C "$SOURCES/amule" tag -f 3.0.1 "$AMULE_COMMIT" >/dev/null
git -C "$SOURCES/wxwidgets" submodule update -q --init --depth 1 \
    3rdparty/pcre src/expat
apply_once "$SOURCES/amule" "$PATCH_DIR/amule-download-only-jaguar.patch"
apply_once "$SOURCES/wxwidgets" "$PATCH_DIR/wxwidgets-jaguar.patch"

if [ ! -f "$DOWNLOADS/$BOOST_ARCHIVE" ]; then
    curl -fL --retry 3 -o "$DOWNLOADS/$BOOST_ARCHIVE" \
        "https://archives.boost.io/release/1.88.0/source/$BOOST_ARCHIVE"
fi
actual=$(shasum -a 256 "$DOWNLOADS/$BOOST_ARCHIVE" | awk '{print $1}')
[ "$actual" = "$BOOST_SHA256" ] || { echo "Boost checksum mismatch" >&2; exit 1; }
if [ ! -d "$SOURCES/boost_1_88_0/boost" ]; then
    tar -xjf "$DOWNLOADS/$BOOST_ARCHIVE" -C "$SOURCES"
fi

echo "[amuled-ppc] rebuilding the shared Jaguar compatibility archive"
COMPAT_OBJECTS="$BUILD_ROOT/jaguar-compat"
mkdir -p "$COMPAT_OBJECTS"
for source in "$ROOT"/extras/package/macosx/jaguar-compat/*.c; do
    object="$COMPAT_OBJECTS/$(basename "$source" .c).o"
        "$CC" -c "$source" -o "$object" -O2 -fno-builtin -isysroot "$SDK" \
        -mmacosx-version-min=10.2 $CPU_FLAGS
done
"$AR" crs "$PREFIX/lib/libjaguarcompat.a" "$COMPAT_OBJECTS"/*.o
"$RANLIB" "$PREFIX/lib/libjaguarcompat.a"

echo "[amuled-ppc] building static wxBase (no GUI, web request or watcher)"
WX_BUILD="$BUILD_ROOT/wxwidgets"
mkdir -p "$WX_BUILD"
if [ ! -f "$WX_BUILD/Makefile" ]; then
    (cd "$WX_BUILD" && \
        CC="$CC" CXX="$CXX" \
        CFLAGS="-O2 $CPU_FLAGS -fno-stack-check" \
        CXXFLAGS="-O2 $CPU_FLAGS -fno-stack-check -std=gnu++17" \
        CPPFLAGS="-isysroot $SDK -mmacosx-version-min=10.2 -D_INTL_REDIRECT_MACROS -DPOWERVLC_WXBASE_JAGUAR=1 -I$CONTRIB/include" \
        LDFLAGS="-Wl,-syslibroot,$SDK -mmacosx-version-min=10.2 -Wl,-no_uuid -L$CONTRIB/lib -lSystemStubs -Wl,$PREFIX/lib/libjaguarcompat.a" \
        "$SOURCES/wxwidgets/configure" \
          --host=powerpc-unknown-freebsd6 --prefix="$PREFIX" \
          --disable-shared --disable-gui --disable-debug --disable-tests \
          --disable-precomp-headers --disable-webrequest --disable-fswatcher \
          --disable-mimetype --disable-secretstore --with-zlib=sys \
          --with-libiconv-prefix="$CONTRIB")
fi
make -C "$WX_BUILD" -j"$JOBS"
make -C "$WX_BUILD" install

echo "[amuled-ppc] building static Crypto++ without assembly"
make -C "$SOURCES/cryptopp" -j"$JOBS" static \
    CXX="$CXX" AR="$AR" RANLIB="$RANLIB" ARFLAGS=cr \
    CXXFLAGS="-O2 $CPU_FLAGS -fno-stack-check -isysroot $SDK -mmacosx-version-min=10.2 -DCRYPTOPP_DISABLE_ASM=1"
mkdir -p "$PREFIX/include/cryptopp" "$PREFIX/lib"
cp "$SOURCES/cryptopp"/*.h "$PREFIX/include/cryptopp/"
cp "$SOURCES/cryptopp/libcryptopp.a" "$PREFIX/lib/"

echo "[amuled-ppc] building daemon-only aMule 3.0.1"
export POWERVLC_ROOT="$ROOT"
export POWERVLC_LEGACY_TOOLCHAIN="$TOOLS"
export POWERVLC_AMULE_PREFIX="$PREFIX"
export POWERVLC_AMULE_CONTRIB="$CONTRIB"
export POWERVLC_AMULE_CPU_FLAGS="$CPU_FLAGS"
AMULE_BUILD="$BUILD_ROOT/amule"
cmake -S "$SOURCES/amule" -B "$AMULE_BUILD" -G Ninja \
    -DCMAKE_TOOLCHAIN_FILE="$PATCH_DIR/toolchain-powerpc-jaguar.cmake" \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_FLAGS_RELEASE='-O3 -DNDEBUG' \
    -DCMAKE_CXX_FLAGS_RELEASE='-O3 -DNDEBUG' \
    -DBUILD_DAEMON=ON -DBUILD_MONOLITHIC=OFF -DBUILD_ED2K=OFF \
    -DBUILD_ALC=OFF -DBUILD_ALCC=OFF -DBUILD_AMULECMD=OFF \
    -DBUILD_CAS=OFF -DBUILD_FILEVIEW=OFF -DBUILD_REMOTEGUI=OFF \
    -DBUILD_WEBSERVER=OFF -DBUILD_WXCAS=OFF -DBUILD_TESTING=OFF \
    -DENABLE_NLS=OFF -DENABLE_IP2COUNTRY=OFF -DENABLE_BFD=OFF \
    -DENABLE_MMAP=OFF -DENABLE_UPNP=OFF -DDEFAULT_VERSION_CHECK=OFF \
    -DPOWERVLC_EXTERNAL_HTTP=ON \
    -DBoost_INCLUDE_DIR="$SOURCES/boost_1_88_0" \
    -DBOOST_ROOT="$SOURCES/boost_1_88_0" -DBoost_NO_SYSTEM_PATHS=ON \
    -DHAVE_FALLOCATE=FALSE -DHAVE_POSIX_FALLOCATE=FALSE \
    -DHAVE_SYS_STATVFS_H=FALSE -DHAVE_GETOPT_LONG=FALSE
ninja -C "$AMULE_BUILD" amuled

cp "$AMULE_BUILD/src/amuled" "$PREFIX/bin/amuled"
"$STRIP" -x "$PREFIX/bin/amuled"
chmod 755 "$PREFIX/bin/amuled"

if otool -L "$PREFIX/bin/amuled" | awk 'NR > 1 { print $1 }' |
   grep -Ev '^(/usr/lib/libSystem\.B\.dylib|/System/Library/Frameworks/)' >/dev/null; then
    echo "amuled has an unexpected dynamic dependency" >&2
    exit 1
fi

echo "[amuled-$TARGET] installed $PREFIX/bin/amuled"
