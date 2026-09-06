#!/bin/sh
# Build PowerVLC's minimal, daemon-only amuled from pinned sources.
# Supported targets: macos-i686, macos-arm64, macos-x86_64, linux-<native arch>,
# windows-i686, windows-x86_64 and windows-aarch64.
set -eu

TARGET=${1:-}
[ -n "$TARGET" ] || {
    echo "usage: $0 <macos-i686|macos-arm64|macos-x86_64|linux-ARCH|windows-ARCH>" >&2
    exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
PATCH_DIR="$SCRIPT_DIR/macosx/amule-ppc"
BUILD_ROOT=${AMULE_BUILD_ROOT:-"$ROOT/build/dependencies/amule/$TARGET"}
PREFIX="$BUILD_ROOT/prefix"
SOURCES="$BUILD_ROOT/sources"
DOWNLOADS=${AMULE_DOWNLOADS:-"$ROOT/contrib/tarballs"}

AMULE_COMMIT=02db0d7faecfc377694ff6242bc23346185990ed
WX_COMMIT=896e4f587615b832ce27b8325357cb504997e1d3
CRYPTOPP_COMMIT=843d74c7c97f9e19a615b8ff3c0ca06599ca501b
BOOST_ARCHIVE=boost_1_88_0.tar.bz2
BOOST_SHA256=46d9d2c06637b219270877c9e16155cbd015b6dc84349af064c088e9b5b12f7b

PLATFORM=${TARGET%%-*}
ARCH=${TARGET#*-}
EXE=
WX_HOST=
WX_COMPAT_CPPFLAGS=
AMULE_CXXFLAGS=
WX_LIB_SUFFIX=
CMAKE_PLATFORM_ARGS=
CRYPTOPP_CPPFLAGS=
case "$PLATFORM-$ARCH" in
    macos-i686)
        TOOLS=${VLC_LEGACY_TOOLCHAIN:-"$HOME/Projects/darwin-legacy-toolchain"}
        SDK="$TOOLS/sdks/MacOSX10.4u.sdk"
        DEP_PREFIX=${AMULE_DEP_PREFIX:-"$ROOT/contrib/i686-apple-darwin8"}
        CC=${CC:-"$TOOLS/opt/gcc-i686-tiger/bin/tiger-cc"}
        CXX=${CXX:-"$TOOLS/opt/gcc-i686-tiger/bin/tiger-c++"}
        AR=${AR:-"$TOOLS/opt/gcc-i686-tiger/bin/i686-apple-darwin8-gcc-ar"}
        RANLIB=${RANLIB:-"$TOOLS/opt/gcc-i686-tiger/bin/i686-apple-darwin8-gcc-ranlib"}
        STRIP=${STRIP:-"$TOOLS/opt/xtools/bin/strip"}
        # wxBase is GUI-free, so use the neutral Unix backend just like the
        # PowerPC build. A Darwin host triplet selects modern Cocoa sources
        # even with --disable-gui, which cannot compile against the 10.4 SDK.
        WX_HOST="--host=i686-unknown-freebsd6"
        COMMON_FLAGS="-march=i686 -mtune=generic -fno-stack-check -isysroot $SDK -mmacosx-version-min=10.4 -static-libstdc++ -static-libgcc"
        WX_COMPAT_CPPFLAGS="-DPOWERVLC_WXBASE_JAGUAR=1"
        AMULE_CPPFLAGS="-D_INTL_REDIRECT_MACROS -I$DEP_PREFIX/include"
        # Tiger has no posix_memalign(). Force Boost.Align's portable
        # allocation backend for both configure probes and the daemon.
        AMULE_CXXFLAGS="-DPOWERVLC_WXBASE_JAGUAR=1 -DBOOST_ASIO_DISABLE_KQUEUE=1 -DBOOST_ERROR_CODE_HEADER_ONLY=1 -DBOOST_ALIGN_USE_NEW"
        AMULE_LDFLAGS="-Wl,-syslibroot,$SDK -mmacosx-version-min=10.4 -Wl,-no_uuid -static-libstdc++ -static-libgcc -L$DEP_PREFIX/lib"
        AMULE_CMAKE_ARGS="-DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_OSX_SYSROOT=$SDK -DCMAKE_OSX_DEPLOYMENT_TARGET=10.4 -DZLIB_INCLUDE_DIR=$DEP_PREFIX/include -DZLIB_LIBRARY=$DEP_PREFIX/lib/libz.a -DLIBATOMIC_LIBRARY=$TOOLS/opt/gcc-i686-tiger/i686-apple-darwin8/lib/libatomic.a -DHAVE_FALLOCATE=FALSE -DHAVE_POSIX_FALLOCATE=FALSE"
        CMAKE_PLATFORM_ARGS="-DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY"
        ;;
    macos-arm64)
        CC=${CC:-clang}; CXX=${CXX:-clang++}
        AR=${AR:-ar}; RANLIB=${RANLIB:-ranlib}; STRIP=${STRIP:-strip}
        WX_HOST="--host=aarch64-unknown-freebsd13"
        WX_LIB_SUFFIX="aarch64-unknown-freebsd13"
        WX_COMPAT_CPPFLAGS="-DPOWERVLC_WXBASE_JAGUAR=1"
        AMULE_CXXFLAGS="-DPOWERVLC_WXBASE_JAGUAR=1"
        COMMON_FLAGS="-arch arm64 -mmacosx-version-min=11.0"
        CMAKE_PLATFORM_ARGS="-DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=11.0"
        ;;
    macos-x86_64)
        CC=${CC:-clang}; CXX=${CXX:-clang++}
        AR=${AR:-ar}; RANLIB=${RANLIB:-ranlib}; STRIP=${STRIP:-strip}
        WX_HOST="--host=x86_64-unknown-freebsd13"
        WX_LIB_SUFFIX="x86_64-unknown-freebsd13"
        WX_COMPAT_CPPFLAGS="-DPOWERVLC_WXBASE_JAGUAR=1"
        AMULE_CXXFLAGS="-DPOWERVLC_WXBASE_JAGUAR=1"
        COMMON_FLAGS="-arch x86_64 -mmacosx-version-min=10.7"
        CMAKE_PLATFORM_ARGS="-DCMAKE_OSX_ARCHITECTURES=x86_64 -DCMAKE_OSX_DEPLOYMENT_TARGET=10.7"
        ;;
    linux-*)
        HOST=${AMULE_HOST:-}
        if [ -n "$HOST" ]; then
            CC=${CC:-"$HOST-gcc"}; CXX=${CXX:-"$HOST-g++"}
            AR=${AR:-"$HOST-ar"}; RANLIB=${RANLIB:-"$HOST-ranlib"}
            STRIP=${STRIP:-"$HOST-strip"}; WX_HOST="--host=$HOST"
            CMAKE_PLATFORM_ARGS="-DCMAKE_SYSTEM_NAME=Linux -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON"
            if [ -n "${AMULE_SYSROOT:-}" ]; then
                CMAKE_PLATFORM_ARGS="$CMAKE_PLATFORM_ARGS -DCMAKE_SYSROOT=$AMULE_SYSROOT"
            fi
        else
            CC=${CC:-cc}; CXX=${CXX:-c++}
            AR=${AR:-ar}; RANLIB=${RANLIB:-ranlib}; STRIP=${STRIP:-strip}
        fi
        COMMON_FLAGS=${AMULE_ARCH_FLAGS:-}
        # Boost.Asio's header probe links a tiny executable.  Unlike newer
        # glibc releases, Ubuntu 18.04 still requires an explicit libpthread
        # for the thread symbols instantiated by those headers.  Carry it to
        # both the probe and the daemon link through Boost_LIBRARIES.
        AMULE_CMAKE_ARGS="-DCMAKE_REQUIRED_LIBRARIES=pthread"
        ;;
    windows-i686|windows-x86_64|windows-aarch64)
        HOST=${AMULE_HOST:-"$ARCH-w64-mingw32"}
        CC=${CC:-"$HOST-gcc"}; CXX=${CXX:-"$HOST-g++"}
        AR=${AR:-"$HOST-ar"}; RANLIB=${RANLIB:-"$HOST-ranlib"}
        STRIP=${STRIP:-"$HOST-strip"}; WX_HOST="--host=$HOST"; EXE=.exe
        COMMON_FLAGS="${AMULE_ARCH_FLAGS:-} -static -static-libgcc -static-libstdc++"
        CRYPTOPP_CPPFLAGS="-I$PATCH_DIR/mingw-compat"
        if [ -d "/usr/$HOST/lib" ]; then
            MINGW_ROOT="/usr/$HOST"
        elif [ -d "/opt/llvm-mingw/$HOST/lib" ]; then
            MINGW_ROOT="/opt/llvm-mingw/$HOST"
        else
            echo "cannot locate the $HOST runtime libraries" >&2; exit 1
        fi
        AMULE_DEP_LIB="${AMULE_DEP_PREFIX:-$PREFIX}/lib"
        # CMake validates every -l emitted by wx-config itself.  Tell it where
        # both the private static wx libraries and the target SDK import libs
        # live; host Linux library paths are intentionally irrelevant here.
        CMAKE_PLATFORM_ARGS="-DCMAKE_SYSTEM_NAME=Windows -DCMAKE_C_COMPILER=$CC -DCMAKE_CXX_COMPILER=$CXX -DCMAKE_RC_COMPILER=${WINDRES:-$HOST-windres} -DCMAKE_LIBRARY_PATH=$PREFIX/lib;$MINGW_ROOT/lib;$AMULE_DEP_LIB -DwxWidgets_USE_STATIC=ON"
        if [ "$ARCH" = "i686" ]; then
            LIBATOMIC=$($CXX -print-file-name=libatomic.a)
            [ -f "$LIBATOMIC" ] || { echo "libatomic.a is required for windows-i686" >&2; exit 1; }
            CMAKE_PLATFORM_ARGS="$CMAKE_PLATFORM_ARGS -DLIBATOMIC_LIBRARY=$LIBATOMIC"
        fi
        ;;
    *) echo "unsupported amuled target: $TARGET" >&2; exit 1 ;;
esac

for tool in git curl cmake ninja tar make "$CC" "$CXX" "$AR" "$RANLIB"; do
    command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
# CMake searches bare compiler names again after applying CMAKE_SYSROOT and can
# accidentally select a target-side compiler from <sysroot>/usr/bin. Resolve
# the build container's cross drivers before CMake sees the sysroot.
CMAKE_CC=$(command -v "$CC")
CMAKE_CXX=$(command -v "$CXX")
CMAKE_AR=$(command -v "$AR")
CMAKE_RANLIB=$(command -v "$RANLIB")
if command -v shasum >/dev/null 2>&1; then
    checksum() { shasum -a 256 "$1" | awk '{print $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
    checksum() { sha256sum "$1" | awk '{print $1}'; }
else
    echo "shasum or sha256sum is required" >&2; exit 1
fi
mkdir -p "$BUILD_ROOT" "$PREFIX/include" "$PREFIX/lib" "$SOURCES" "$DOWNLOADS"
JOBS=${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}

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
    [ "$(git -C "$destination" rev-parse HEAD)" = "$commit" ] || {
        echo "$destination is not at pinned commit $commit" >&2; exit 1;
    }
    # The patch set is applied below on every invocation.  The amuled build
    # also performs a few in-place CMake/source normalisations after patching;
    # those edits make `git apply --reverse --check` unable to recognise an
    # otherwise already-applied patch on the next retry.  Reset only this
    # disposable, pinned source checkout so every invocation reapplies the
    # exact patch set from a clean tree.  Out-of-tree build products live in
    # $BUILD_ROOT/{wxwidgets,amule} and are deliberately untouched.
    git -C "$destination" reset --hard -q "$commit"
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

echo "[amuled:$TARGET] fetching pinned sources"
checkout_exact https://github.com/amule-org/amule.git "$AMULE_COMMIT" "$SOURCES/amule"
checkout_exact https://github.com/wxWidgets/wxWidgets.git "$WX_COMMIT" "$SOURCES/wxwidgets"
checkout_exact https://github.com/weidai11/cryptopp.git "$CRYPTOPP_COMMIT" "$SOURCES/cryptopp"
git -C "$SOURCES/amule" tag -f 3.0.1 "$AMULE_COMMIT" >/dev/null
git -C "$SOURCES/wxwidgets" submodule update -q --init --depth 1 3rdparty/pcre src/expat
apply_once "$SOURCES/amule" "$PATCH_DIR/amule-download-only-jaguar.patch"
apply_once "$SOURCES/amule" "$PATCH_DIR/amule-pinned-boost.patch"
apply_once "$SOURCES/amule" "$PATCH_DIR/amule-explicit-cryptopp.patch"
apply_once "$SOURCES/amule" "$PATCH_DIR/amule-static-wx.patch"
apply_once "$SOURCES/wxwidgets" "$PATCH_DIR/wxwidgets-jaguar.patch"
# This opcode spelling exists solely for the old Tiger assembler.  Applying it
# to MinGW checkouts is both unnecessary and unreliable because Git preserves
# Crypto++'s CRLF source there.
if [ "$PLATFORM-$ARCH" = "macos-i686" ]; then
    apply_once "$SOURCES/cryptopp" "$PATCH_DIR/cryptopp-old-assembler.patch"
fi

if [ ! -f "$DOWNLOADS/$BOOST_ARCHIVE" ]; then
    curl -fL --retry 3 -o "$DOWNLOADS/$BOOST_ARCHIVE" \
        "https://archives.boost.io/release/1.88.0/source/$BOOST_ARCHIVE"
fi
[ "$(checksum "$DOWNLOADS/$BOOST_ARCHIVE")" = "$BOOST_SHA256" ] || {
    echo "Boost checksum mismatch" >&2; exit 1;
}
if [ ! -d "$SOURCES/boost_1_88_0/boost" ]; then
    tar -xjf "$DOWNLOADS/$BOOST_ARCHIVE" -C "$SOURCES"
fi

echo "[amuled:$TARGET] building static wxBase"
WX_BUILD="$BUILD_ROOT/wxwidgets"
mkdir -p "$WX_BUILD"
if [ ! -f "$WX_BUILD/Makefile" ]; then
    (cd "$WX_BUILD" && CC="$CC" CXX="$CXX" \
      CFLAGS="-O2 $COMMON_FLAGS" CXXFLAGS="-O2 -std=gnu++17 $COMMON_FLAGS" \
      CPPFLAGS="$WX_COMPAT_CPPFLAGS ${AMULE_CPPFLAGS:-}" \
      LDFLAGS="$COMMON_FLAGS ${AMULE_LDFLAGS:-}" \
      "$SOURCES/wxwidgets/configure" $WX_HOST --prefix="$PREFIX" \
        --disable-shared --disable-gui --disable-debug --disable-tests \
        --disable-precomp-headers --disable-webrequest --disable-fswatcher \
        --disable-mimetype --disable-secretstore --with-zlib=sys)
fi
make -C "$WX_BUILD" -j"$JOBS"
make -C "$WX_BUILD" install
if [ "$PLATFORM" = "windows" ]; then
    # wxBase's install list omits several MSW headers that its own public base
    # headers include (wx/msw/init.h first).  They are headers only; copying the
    # complete platform directory does not pull any GUI library into amuled.
    cp -R "$SOURCES/wxwidgets/include/wx/msw" "$PREFIX/include/wx-3.2/wx/"
fi
if [ -n "$WX_LIB_SUFFIX" ]; then
    # Rosetta can execute the x86_64 configure probe, so wx-config reports a
    # native build even though the neutral host suffix is present on archives.
    # Provide the unsuffixed static archive names wx-config consequently emits.
    for component in baseu baseu_net baseu_xml; do
        ln -sf "libwx_${component}-3.2-${WX_LIB_SUFFIX}.a" \
            "$PREFIX/lib/libwx_${component}-3.2.a"
    done
fi

echo "[amuled:$TARGET] building static Crypto++"
make -C "$SOURCES/cryptopp" -j"$JOBS" static CXX="$CXX" AR="$AR" \
    RANLIB="$RANLIB" ARFLAGS=cr \
    CXXFLAGS="-O2 $CRYPTOPP_CPPFLAGS $COMMON_FLAGS -DCRYPTOPP_DISABLE_ASM=1"
mkdir -p "$PREFIX/include/cryptopp" "$PREFIX/lib"
cp "$SOURCES/cryptopp"/*.h "$PREFIX/include/cryptopp/"
cp "$SOURCES/cryptopp/libcryptopp.a" "$PREFIX/lib/"

echo "[amuled:$TARGET] building daemon without legacy UPnP"
AMULE_BUILD="$BUILD_ROOT/amule"
# Ubuntu 18.04 ships CMake 3.10, before add_compile_definitions() was
# introduced.  The older add_definitions() accepts the same generator
# expressions and keeps the pinned aMule source compatible with that image.
perl -0pi -e 's/add_compile_definitions/add_definitions/g; \
    s/add_definitions \(POWERVLC_EXTERNAL_HTTP=1\)/add_definitions (-DPOWERVLC_EXTERNAL_HTTP=1)/g; \
    s{add_definitions \(\$<\$<CONFIG:DEBUG>:__DEBUG__>\)}{if (CMAKE_BUILD_TYPE STREQUAL "Debug")\n\tadd_definitions(-D__DEBUG__)\nendif()}g; \
    s{add_definitions \(\$<\$<CONFIG:DEBUG>:wxDEBUG_LEVEL=0>\)}{if (CMAKE_BUILD_TYPE STREQUAL "Debug")\n\tadd_definitions(-DwxDEBUG_LEVEL=0)\nendif()}g; \
    s/include \(CheckIncludeFiles\)/include (CheckCXXSourceCompiles)/; \
    s{\t(?:check_include_files|add_definitions) \("boost/system/error_code\.hpp;boost/asio\.hpp" ASIO_SOCKETS LANGUAGE CXX\)}{\tcheck_cxx_source_compiles ([=[\n#include <boost/system/error_code.hpp>\n#include <boost/asio.hpp>\nint main(void) { return 0; }\n]=] ASIO_SOCKETS)}' \
    "$SOURCES/amule/cmake/options.cmake" \
    "$SOURCES/amule/cmake/boost.cmake"
perl -0pi -e 's{add_library \(wxWidgets::\$\{_target\} INTERFACE IMPORTED\)}{add_library (POWERVLC_wxWidgets_\${_target} INTERFACE)\n\t\t\tadd_library (wxWidgets::\${_target} ALIAS POWERVLC_wxWidgets_\${_target})}; \
    s{(target_(?:link_libraries|include_directories|compile_definitions) \()wxWidgets::\$\{_target\}}{$1POWERVLC_wxWidgets_\${_target}}g' \
    "$SOURCES/amule/cmake/wx.cmake"
# CMAKE_PLATFORM_ARGS is intentionally split into individual -D arguments.
# shellcheck disable=SC2086
mkdir -p "$AMULE_BUILD"
( cd "$AMULE_BUILD" && cmake "$SOURCES/amule" -G Ninja $CMAKE_PLATFORM_ARGS \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_C_COMPILER="$CMAKE_CC" \
    -DCMAKE_CXX_COMPILER="$CMAKE_CXX" \
    -DCMAKE_AR="$CMAKE_AR" -DCMAKE_RANLIB="$CMAKE_RANLIB" \
    -DCMAKE_C_FLAGS="${AMULE_CPPFLAGS:-}" \
    -DCMAKE_CXX_FLAGS="$AMULE_CXXFLAGS ${AMULE_CPPFLAGS:-} -I$PREFIX/include -DCRYPTOPP_DISABLE_ASM=1" \
    -DCMAKE_EXE_LINKER_FLAGS="$COMMON_FLAGS ${AMULE_LDFLAGS:-}" \
    -DCMAKE_C_FLAGS_RELEASE="-O3 -DNDEBUG $COMMON_FLAGS" \
    -DCMAKE_CXX_FLAGS_RELEASE="-O3 -DNDEBUG $COMMON_FLAGS" \
    -DBUILD_DAEMON=ON -DBUILD_MONOLITHIC=OFF -DBUILD_ED2K=OFF \
    -DBUILD_ALC=OFF -DBUILD_ALCC=OFF -DBUILD_AMULECMD=OFF -DBUILD_CAS=OFF \
    -DBUILD_FILEVIEW=OFF -DBUILD_REMOTEGUI=OFF -DBUILD_WEBSERVER=OFF \
    -DBUILD_WXCAS=OFF -DBUILD_TESTING=OFF -DENABLE_NLS=OFF \
    -DENABLE_IP2COUNTRY=OFF -DENABLE_BFD=OFF -DENABLE_UPNP=OFF \
    -DDEFAULT_VERSION_CHECK=OFF -DPOWERVLC_EXTERNAL_HTTP=ON \
    -DwxWidgets_CONFIG_EXECUTABLE="$PREFIX/bin/wx-config" \
    -DCRYPTOPP_INCLUDE_DIR="$PREFIX/include" -DCRYPTOPP_LIBRARY="$PREFIX/lib/libcryptopp.a" \
    -DCRYPTOPP_VERSION=890 \
    -DPOWERVLC_BOOST_INCLUDE_DIR="$SOURCES/boost_1_88_0" ${AMULE_CMAKE_ARGS:-} )
ninja -C "$AMULE_BUILD" amuled

mkdir -p "$PREFIX/bin"
cp "$AMULE_BUILD/src/amuled$EXE" "$PREFIX/bin/amuled$EXE"
"$STRIP" "$PREFIX/bin/amuled$EXE" 2>/dev/null || true
chmod 755 "$PREFIX/bin/amuled$EXE"

case "$PLATFORM" in
    macos) deps=$(otool -L "$PREFIX/bin/amuled" | grep -Ei '(libupnp|libixml)' || true) ;;
    linux)
        if [ -n "${AMULE_HOST:-}" ]; then
            deps=$("${OBJDUMP:-$HOST-objdump}" -p "$PREFIX/bin/amuled" |
                   grep -Ei '(libupnp|libixml)' || true)
        else
            deps=$(ldd "$PREFIX/bin/amuled" | grep -Ei '(libupnp|libixml)' || true)
        fi
        ;;
    windows) deps=$("${OBJDUMP:-$HOST-objdump}" -p "$PREFIX/bin/amuled.exe" | grep -Ei '(libupnp|libixml)' || true) ;;
esac
[ -z "$deps" ] || { echo "legacy UPnP dependency leaked into amuled" >&2; echo "$deps" >&2; exit 1; }

echo "$PREFIX/bin/amuled$EXE"
