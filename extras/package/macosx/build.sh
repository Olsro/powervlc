#!/bin/sh
set -e

info()
{
    local green="\033[1;32m"
    local normal="\033[0m"
    echo "[${green}build${normal}] $1"
}

ARCH="x86_64"
MINIMAL_OSX_VERSION="10.5"
OSX_KERNELVERSION=`uname -r | cut -d. -f1`
BUILD_ARCH=`uname -m | cut -d. -f1`
SDKROOT=$(xcrun --show-sdk-path)
VLCBUILDDIR=""

CORE_COUNT=`getconf NPROCESSORS_ONLN 2>&1`
let JOBS=$CORE_COUNT+1

if [ ! -z "$VLC_FORCE_KERNELVERSION" ]; then
    OSX_KERNELVERSION="$VLC_FORCE_KERNELVERSION"
fi

usage()
{
cat << EOF
usage: $0 [options]

Build vlc in the current directory

OPTIONS:
   -h            Show some help
   -q            Be quiet
   -j            Force number of cores to be used
   -r            Rebuild everything (tools, contribs, vlc)
   -c            Recompile contribs from sources
   -p            Build packages for all artifacts
   -i <n|u>      Create an installable package (n: nightly, u: unsigned stripped release archive)
   -k <sdk>      Use the specified sdk (default: $SDKROOT)
   -a <arch>     Use the specified arch (default: $ARCH)
   -C            Use the specified VLC build dir
   -b <url>      Enable breakpad support and send crash reports to this URL
EOF

}

spushd()
{
    pushd "$1" > /dev/null
}

spopd()
{
    popd > /dev/null
}

get_actual_arch() {
    if [ "$1" = "aarch64" ]; then
        echo "arm64"
    else
        echo "$1"
    fi
}

get_buildsystem_arch() {
    if [ "$1" = "arm64" ]; then
        echo "aarch64"
    else
        echo "$1"
    fi
}

while getopts "hvrcpi:k:a:j:C:b:" OPTION
do
     case $OPTION in
         h)
             usage
             exit 1
             ;;
         q)
             set +x
             QUIET="yes"
         ;;
         r)
             REBUILD="yes"
         ;;
         c)
             CONTRIBFROMSOURCE="yes"
         ;;
         p)
             PACKAGE="yes"
         ;;
         i)
             PACKAGETYPE=$OPTARG
         ;;
         a)
             ARCH=$OPTARG
         ;;
         k)
             SDKROOT=$OPTARG
         ;;
         j)
             JOBS=$OPTARG
         ;;
         C)
             VLCBUILDDIR=$OPTARG
         ;;
         b)
             BREAKPAD=$OPTARG
         ;;
         *)
             usage
             exit 1
         ;;
     esac
done
shift $(($OPTIND - 1))

if [ "x$1" != "x" ]; then
    usage
    exit 1
fi

#
# Various initialization
#

out="/dev/stdout"
if [ "$QUIET" = "yes" ]; then
    out="/dev/null"
fi

ACTUAL_ARCH=`get_actual_arch $ARCH`
BUILD_ARCH=`get_buildsystem_arch $BUILD_ARCH`
BUILD_TRIPLET=$BUILD_ARCH-apple-darwin$OSX_KERNELVERSION
HOST_TRIPLET=$ARCH-apple-darwin$OSX_KERNELVERSION

# Legacy PowerPC/i386 cross build using the homemade GCC toolchain
# (FSF GCC + darwin-xtools; no -arch, no clang-only flags).
LEGACY_TOOLCHAIN_ROOT="${VLC_LEGACY_TOOLCHAIN:-$HOME/Projects/darwin-legacy-toolchain}"
LEGACY_GCC=""
LEGACY_CONTRIB_SUFFIX=""      # distinct contrib prefix per CPU family
LEGACY_CONTRIB_CPUFLAGS=""    # CPU flags for the (shared) contribs
LEGACY_VLC_CPUFLAGS=""        # CPU flags for VLC itself (per variant)
LEGACY_PPC_ALTIVEC=""         # set to yes on AltiVec-capable PowerPC
case $ARCH in
    ppc)
        # PowerPC G3 (750), Mac OS X **10.2 Jaguar**. No SIMD.
        # The floor dropped from 10.4 to 10.2: old Macs usually still run the
        # release they shipped with rather than the newest one they could take.
        # Validated on a real iBook G3 (PowerBook4,3) -- interface, audio,
        # video, DVD and the ATI hardware decoder. See MACOS_INCOMPATIBILITIES
        # §1.3 for everything Jaguar lacks and how it is worked around.
        LEGACY_TRIPLE="powerpc-apple-darwin8"
        LEGACY_GCC="$LEGACY_TOOLCHAIN_ROOT/opt/gcc-ppc-tiger"
        MINIMAL_OSX_VERSION="10.2"
        SDKROOT="$LEGACY_TOOLCHAIN_ROOT/sdks/MacOSX10.4u.sdk"
        HOST_TRIPLET="$LEGACY_TRIPLE"
        # Reuse the contribs proven at 10.2 by the former `ppc-jaguar` staging
        # target: same triple, same -mcpu=750, same no-AltiVec, same deployment
        # target -- rebuilding them under another name would only burn hours.
        LEGACY_CONTRIB_SUFFIX="-jaguar"
        # The G3 slice is tagged ppc750: schedule for the 750 pipeline
        # (short 4-stage, single load/store unit). Without these flags
        # GCC schedules for a generic PowerPC model.
        LEGACY_CONTRIB_CPUFLAGS="-mcpu=750 -mtune=750"
        LEGACY_VLC_CPUFLAGS="-mcpu=750 -mtune=750"
        ;;
    g4|g4e|g5)
        # PowerPC with AltiVec, Mac OS X **10.2 Jaguar** (floor lowered with
        # the G3 slice; see the `ppc` case). The contribs are
        # shared between the three variants and built for the lowest
        # common ISA (7400 + AltiVec: a 7450 or a 970 runs all of it);
        # VLC itself is tuned per variant below.
        LEGACY_TRIPLE="powerpc-apple-darwin8"
        LEGACY_GCC="$LEGACY_TOOLCHAIN_ROOT/opt/gcc-ppc-tiger"
        MINIMAL_OSX_VERSION="10.2"
        SDKROOT="$LEGACY_TOOLCHAIN_ROOT/sdks/MacOSX10.4u.sdk"
        HOST_TRIPLET="$LEGACY_TRIPLE"
        LEGACY_CONTRIB_SUFFIX="-av"
        LEGACY_CONTRIB_CPUFLAGS="-mcpu=7400 -mtune=7400 -maltivec -mabi=altivec"
        LEGACY_PPC_ALTIVEC="yes"
        case $ARCH in
            g4)  LEGACY_VLC_CPUFLAGS="-mcpu=7400 -mtune=7400 -maltivec -mabi=altivec" ;;
            g4e) LEGACY_VLC_CPUFLAGS="-mcpu=7450 -mtune=7450 -maltivec -mabi=altivec" ;;
            g5)  LEGACY_VLC_CPUFLAGS="-mcpu=970 -mtune=970 -maltivec -mabi=altivec" ;;
        esac
        ;;
    i686)
        # Intel 32-bit, Mac OS X 10.4 Tiger (10.4.4 was the first x86
        # release). Needs the i686-apple-darwin8 cross GCC; modern clang
        # no longer ships i386 runtime libraries.
        LEGACY_TRIPLE="i686-apple-darwin8"
        LEGACY_GCC="$LEGACY_TOOLCHAIN_ROOT/opt/gcc-i686-tiger"
        MINIMAL_OSX_VERSION="10.4"
        SDKROOT="$LEGACY_TOOLCHAIN_ROOT/sdks/MacOSX10.4u.sdk"
        HOST_TRIPLET="$LEGACY_TRIPLE"
        ;;
    i686-leopard)
        # Previous Intel 32-bit target (10.5), kept for reference.
        LEGACY_TRIPLE="i686-apple-darwin9"
        LEGACY_GCC="$LEGACY_TOOLCHAIN_ROOT/opt/gcc-i686"
        MINIMAL_OSX_VERSION="10.5"
        SDKROOT="$LEGACY_TOOLCHAIN_ROOT/sdks/MacOSX10.5.sdk"
        HOST_TRIPLET="$LEGACY_TRIPLE"
        ;;
    # x86_64 (10.5.8+) stays on the modern clang path below: 64-bit
    # apps require 10.5 anyway and the clang build already targets it.
    aarch64|arm64)
        # Apple Silicon: macOS 11.0 is the first arm64 release.
        MINIMAL_OSX_VERSION="11.0"
        ;;
esac

info "Building VLC for macOS for architecture ${ACTUAL_ARCH} on a ${BUILD_ARCH} device"

spushd `dirname $0`/../../..
vlcroot=`pwd`
spopd

builddir=`pwd`

info "Building in \"$builddir\""

python3Path=$(echo /Library/Frameworks/Python.framework/Versions/3.*/bin | awk '{print $1;}')
if [ ! -d "$python3Path" ]; then
	python3Path=""
fi

if [ -n "$LEGACY_GCC" ]; then
    XT="$LEGACY_TOOLCHAIN_ROOT/opt/xtools/bin"
    export AR="$XT/ar"
    # Prefer the argv-filtering wrappers (drop -no-cpp-precomp & other
    # Apple-only flags hardcoded by old configure scripts) when present.
    if [ -x "$LEGACY_GCC/bin/tiger-cc" ]; then
        export CC="$LEGACY_GCC/bin/tiger-cc"
        export CXX="$LEGACY_GCC/bin/tiger-c++"
    else
        export CC="$LEGACY_GCC/bin/$LEGACY_TRIPLE-gcc"
        export CXX="$LEGACY_GCC/bin/$LEGACY_TRIPLE-g++"
    fi
    export NM="$XT/nm"
    export OBJC="$CC"
    export RANLIB="$XT/ranlib"
    export STRINGS="$XT/strings"
    export STRIP="$XT/strip"
    export LD="$XT/ld"
    export OTOOL="$XT/otool"
    export INSTALL_NAME_TOOL="$XT/install_name_tool"
    export LIPO="$XT/lipo"
    # Native compiler for build-time helper programs of cross-compiled
    # contribs (gmp, nettle...): must not inherit the target sysroot.
    export CC_FOR_BUILD="/usr/bin/clang"
    export CPP_FOR_BUILD="/usr/bin/clang -E"
    export BUILD_CC="/usr/bin/clang"
    # Lua bytecode is not portable to the target's byte order/word size;
    # ship the .lua sources under the .luac names instead (the target's Lua
    # compiles them at load time). legacy-luac copies source -> output.
    if [ -x "$LEGACY_GCC/bin/legacy-luac" ]; then
        export LUAC="$LEGACY_GCC/bin/legacy-luac"
        export LUAC_ANY_ARCH="yes"
    fi
else
export AR="`xcrun --find ar`"
export CC="`xcrun --find clang`"
export CXX="`xcrun --find clang++`"
export NM="`xcrun --find nm`"
export OBJC="`xcrun --find clang`"
export OBJCXX="`xcrun --find clang++`"
export RANLIB="`xcrun --find ranlib`"
export STRINGS="`xcrun --find strings`"
export STRIP="`xcrun --find strip`"
fi
export SDKROOT
# /opt/homebrew/bin (Apple Silicon) and /usr/local/bin (Intel) are appended so
# the contrib ffmpeg build finds nasm/yasm (`brew install nasm`) — required to
# assemble the i386 x86 asm; without an assembler ffmpeg silently drops it.
export PATH="${vlcroot}/extras/tools/build/bin:${vlcroot}/contrib/${BUILD_TRIPLET}/bin:$python3Path:${VLC_PATH}:/bin:/sbin:/usr/bin:/usr/sbin:/opt/homebrew/bin:/usr/local/bin"

# Select avcodec flavor to compile contribs with
export USE_FFMPEG=1

# The following symbols do not exist on the minimal macOS version (10.7), so they are disabled
# here. This allows compilation also with newer macOS SDKs.

# Added symbols in macOS 10.15 / iOS 13 / tvOS 13
export ac_cv_func_aligned_alloc=no
export ac_cv_func_timespec_get=no

# Added symbol in macOS 10.14 / iOS 12 / tvOS 9
export ac_cv_func_thread_get_register_pointer_values=no

# Added symbols in macOS 10.13 / iOS 11 / tvOS 11
export ac_cv_func_utimensat=no
export ac_cv_func_futimens=no

# Added symbols in 10.13
export ac_cv_func_open_wmemstream=no
export ac_cv_func_fmemopen=no
export ac_cv_func_open_memstream=no
export ac_cv_func_futimens=no
export ac_cv_func_utimensat=no

# Added symbols between 10.11 and 10.12
export ac_cv_func_basename_r=no
export ac_cv_func_clock_getres=no
export ac_cv_func_clock_gettime=no
export ac_cv_func_clock_settime=no
export ac_cv_func_dirname_r=no
export ac_cv_func_getentropy=no
export ac_cv_func_mkostemp=no
export ac_cv_func_mkostemps=no
export ac_cv_func_timingsafe_bcmp=no

# Added symbols between 10.7 and 10.11
export ac_cv_func_ffsll=no
export ac_cv_func_flsll=no
export ac_cv_func_fdopendir=no
export ac_cv_func_openat=no
export ac_cv_func_fstatat=no
export ac_cv_func_readlinkat=no
export ac_cv_func_linkat=no
export ac_cv_func_unlinkat=no

# Added symbols between 10.7 and 10.9
export ac_cv_func_memset_s=no

# Added symbols in 10.7 (this branch targets 10.5/10.6, where the weak-linked
# symbols resolve to NULL and crash on the first call)
export ac_cv_func_memmem=no
export ac_cv_func_strnlen=no

# libnetwork does not exist yet on 10.7 (used by libcddb)
export ac_cv_lib_network_connect=no

# poll() arrived with Mac OS X 10.3. The 10.4u SDK declares it either way and
# <poll.h> carries no availability annotation, so configure would happily
# detect it and the link would emit a HARD reference that 10.2 cannot resolve
# -- nothing weak-imported, so check-weak-symbols.sh would stay silent about
# it. Force the select()-based replacement instead (compat/poll.c, listed in
# configure.ac's AC_REPLACE_FUNCS).
case "$MINIMAL_OSX_VERSION" in
    10.0|10.1|10.2)
        export ac_cv_func_poll=no
        ;;
esac

#
# vlc/extras/tools
#

info "Building building tools"
spushd "${vlcroot}/extras/tools"
# extras/tools are HOST tools: always build them with the native compiler,
# never with the legacy cross gcc.
(
    if [ -n "$LEGACY_GCC" ]; then
        export CC="`xcrun --find clang`"
        export CXX="`xcrun --find clang++`"
        export OBJC="$CC"
        export AR="`xcrun --find ar`"
        export RANLIB="`xcrun --find ranlib`"
        export NM="`xcrun --find nm`"
        export STRIP="`xcrun --find strip`"
        unset LD SDKROOT CFLAGS CXXFLAGS OBJCFLAGS LDFLAGS
    fi
    ./bootstrap > $out
    if [ "$REBUILD" = "yes" ]; then
        make clean
        ./bootstrap > $out
    fi
    make -j$JOBS > $out
)
spopd

#
# vlc/contribs
#

# Usually, VLCs contrib libraries do not support partial availability at runtime.
# Forcing those errors has two reasons:
# - Some custom configure scripts include the right header for testing availability.
#   Those configure checks fail (correctly) with those errors, and replacements are
#   enabled. (e.g. ffmpeg)
# - This will fail the build if a partially available symbol is added later on
#   in contribs and not mentioned in the list of symbols above.
if [ -n "$LEGACY_GCC" ]; then
    # FSF GCC: no -Werror=partial-availability (clang-only); the old SDK
    # itself is the availability gate. No -arch either: the cross compiler
    # produces exactly one architecture.
    ARCH_CFLAG=""
    export CFLAGS=""
    export CXXFLAGS=""
    export OBJCFLAGS=""
else
    ARCH_CFLAG="-arch $ACTUAL_ARCH"
    export CFLAGS="-Werror=partial-availability"
    export CXXFLAGS="-Werror=partial-availability"
    export OBJCFLAGS="-Werror=partial-availability"
fi

# Used by contrib/src/main.mak's darwin_min_os_at_least (gates contrib
# features/packages that require a newer minimum OS than $MINIMAL_OSX_VERSION).
export VLC_DEPLOYMENT_TARGET="$MINIMAL_OSX_VERSION"

# PowerPC long-double ABI: 10.4 widened `long double` from 64 to 128 bits, so
# when the deployment target is older the 10.4u SDK headers redirect the whole
# printf family to _<fn>$LDBLStub (sys/cdefs.h, gated on < 1040). Those stubs
# are NOT in libSystem -- Apple ships them in the SDK's static
# libSystemStubs.a, and GCC's darwin driver links it automatically... but only
# from 10.3 on: at 10.2 its spec assumes the redirect cannot happen, which is
# wrong when a 10.4u SDK is used. Without this, every contrib that calls
# snprintf() fails to link (zlib, lua, nettle, vorbis...).
LEGACY_LDBL_STUBS=""
case "$MINIMAL_OSX_VERSION" in
    10.0|10.1|10.2)
        # -ljaguarcompat is the libc 10.2 lacks (dlopen, C99 float math,
        # tsearch, the $LDBL128/$UNIX2003 aliases...). It is built into the
        # contrib prefix a few dozen lines below, before anything links.
        # The compat archive is passed as -Wl,<absolute path> rather than
        # -L<dir> -ljaguarcompat, because neither of the other two forms
        # survives every build system here: CMake never sees EXTRA_LDFLAGS
        # (contrib's toolchain.cmake sets CMAKE_LD_FLAGS, not a CMake
        # variable) and meson drops the -L when it splits the flags it takes
        # from the environment. A -Wl, argument is opaque to both, is passed
        # straight to ld, and is silently ignored when only compiling --
        # unlike a bare archive path, which warns "linker input file unused"
        # on every compile and would eventually break a configure probe.
        # -lSystemStubs needs no path: it lives in the SDK, under -isysroot.
        # -no_uuid: LC_UUID (0x1b) only appeared in Mac OS X 10.4, and the
        # 2002 tools do not know it -- gdb prints "unable to read unknown load
        # command 0x1b" for every image, and 10.2's own ld refuses a dylib
        # carrying one ("unknown cmd field"). dyld walks the same load command
        # list, so leave it out rather than trust it to skip what it cannot
        # parse.
        LEGACY_LDBL_STUBS="-lSystemStubs -Wl,-no_uuid -Wl,${vlcroot}/contrib/${HOST_TRIPLET}${LEGACY_CONTRIB_SUFFIX}/lib/libjaguarcompat.a"

        # NOTE: resist the temptation to switch VLC's own replacements on with
        # ac_cv_func_<fn>=no for the rest of what 10.2 lacks. That tells VLC
        # the function is not DECLARED, when the 10.4u SDK declares all of
        # them -- only the runtime symbol is missing. compat/lldiv.c then
        # redefines lldiv_t against <stdlib.h>, and vlc_fixups.h redefines
        # getc_unlocked against <stdio.h>: both fail to compile. Everything
        # else is provided by libjaguarcompat.a instead, where the SDK
        # declarations are simply implemented rather than contradicted.
        #
        # That includes the xlocale family: <xlocale.h> is in the SDK, so
        # ac_cv_func_newlocale=no makes vlc_fixups.h redeclare locale_t
        # against it. libjaguarcompat.a implements those too.
        #
        # poll is the one exception and is handled further up: <poll.h>
        # exists, so vlc_fixups.h includes it instead of redeclaring, and
        # compat/poll.c builds cleanly.
        ;;
esac

# ...and it has to go in the CFLAGS too, not just the LDFLAGS: contrib's
# generated toolchain.cmake sets CMAKE_LD_FLAGS, which is not a CMake variable
# at all (the real ones are CMAKE_{EXE,SHARED,MODULE}_LINKER_FLAGS), so
# EXTRA_LDFLAGS never reaches a CMake link line -- libpng's shared target fails
# on _fprintf$LDBLStub otherwise. CMAKE_C_FLAGS *is* passed when linking, and
# GCC ignores a -l silently when it is only compiling.
export EXTRA_CFLAGS="-isysroot $SDKROOT -mmacosx-version-min=$MINIMAL_OSX_VERSION -DMACOSX_DEPLOYMENT_TARGET=$MINIMAL_OSX_VERSION $ARCH_CFLAG $LEGACY_CONTRIB_CPUFLAGS $LEGACY_LDBL_STUBS"
export EXTRA_LDFLAGS="-Wl,-syslibroot,$SDKROOT -mmacosx-version-min=$MINIMAL_OSX_VERSION -isysroot $SDKROOT -DMACOSX_DEPLOYMENT_TARGET=$MINIMAL_OSX_VERSION $ARCH_CFLAG $LEGACY_CONTRIB_CPUFLAGS $LEGACY_LDBL_STUBS"
# Lets contrib rules.mak files (ffmpeg...) keep AltiVec enabled on G4/G5
# while the G3 build still disables it.
if [ "$LEGACY_PPC_ALTIVEC" = "yes" ]; then
    export VLC_PPC_ALTIVEC=yes
fi
# xcodebuild only allows to set a build-in sdk, not a custom one. Therefore use the default included SDK here
export XCODE_FLAGS="MACOSX_DEPLOYMENT_TARGET=$MINIMAL_OSX_VERSION -sdk macosx WARNING_CFLAGS=-Werror=partial-availability"

CONTRIBFLAGS=
if [ "$PACKAGETYPE" = "u" ]; then
    # release package should have sparkle, breakpad, growl
    CONTRIBFLAGS="$CONTRIBFLAGS --enable-sparkle --enable-breakpad --enable-growl"
elif [ "$PACKAGETYPE" = "n" ]; then
    # nightly package should have growl
    CONTRIBFLAGS="$CONTRIBFLAGS --enable-growl"
fi

# The libc that Mac OS X 10.2 does not have. Built here rather than as a
# contrib package because everything else -- contribs included -- links it:
# it has to exist in the prefix before the first of them is configured.
# See extras/package/macosx/jaguar-compat/ for what it provides and why.
if [ -n "$LEGACY_LDBL_STUBS" ]; then
    JAGUAR_SRC="${vlcroot}/extras/package/macosx/jaguar-compat"
    JAGUAR_PREFIX="${vlcroot}/contrib/${HOST_TRIPLET}${LEGACY_CONTRIB_SUFFIX}"

    info "Building the 10.2 compatibility library"
    mkdir -p "$JAGUAR_PREFIX/lib" "$builddir/jaguar-compat"
    for src in "$JAGUAR_SRC"/*.c; do
        obj="$builddir/jaguar-compat/$(basename "$src" .c).o"
        # -fno-builtin is not optional here. Every function in libc102.c is a
        # libc function implemented in terms of other libc functions, and GCC
        # recognises those shapes: it folds (float)sin((double)x) back into
        # sinf(), and exp(a)*cos(b) + exp(a)*sin(b)*i back into cexp(). Each
        # definition then calls itself. Measured: MPEG-1 decoding died in a
        # runaway cexp() recursion on the 10.2 machine.
        $CC -c "$src" -o "$obj" -O2 -fno-builtin -isysroot "$SDKROOT" \
            -mmacosx-version-min="$MINIMAL_OSX_VERSION" \
            $LEGACY_CONTRIB_CPUFLAGS || exit 1
    done
    "$XT/ar" crs "$JAGUAR_PREFIX/lib/libjaguarcompat.a" \
        "$builddir"/jaguar-compat/*.o || exit 1
    "$XT/ranlib" "$JAGUAR_PREFIX/lib/libjaguarcompat.a" || exit 1
fi

info "Building contribs"
spushd "${vlcroot}/contrib"

# ⚠ A contrib prefix is reused as-is when it already exists -- nothing in it
# records WHICH deployment target it was built for. Lowering the PowerPC floor
# from 10.4 to 10.2 would therefore have linked 10.4-era static libraries into
# a 10.2 binary, silently: no build error, no warning, and a hard reference to
# a symbol Jaguar does not have only shows up as a dyld failure on the machine.
# Stamp the target in the prefix and refuse to reuse a mismatched set.
CONTRIB_STAMP="${vlcroot}/contrib/${HOST_TRIPLET}${LEGACY_CONTRIB_SUFFIX}/.powervlc-osx-min"
if [ -f "$CONTRIB_STAMP" ]; then
    stamped=$(cat "$CONTRIB_STAMP")
    if [ "$stamped" != "$MINIMAL_OSX_VERSION" ]; then
        echo "ERROR: contribs in contrib/${HOST_TRIPLET}${LEGACY_CONTRIB_SUFFIX}" >&2
        echo "       were built for macOS $stamped, this target needs $MINIMAL_OSX_VERSION." >&2
        echo "       Remove that prefix (and contrib/contrib-${HOST_TRIPLET}${LEGACY_CONTRIB_SUFFIX})" >&2
        echo "       so they are rebuilt, then run this build again." >&2
        exit 1
    fi
fi

CONTRIB_PREFIX_FLAG=""
if [ -n "$LEGACY_CONTRIB_SUFFIX" ]; then
    # CPU-variant contribs live in their own prefix so different -mcpu
    # families of the same triple never mix objects.
    CONTRIB_PREFIX_FLAG="--prefix=${vlcroot}/contrib/${HOST_TRIPLET}${LEGACY_CONTRIB_SUFFIX}"
fi
mkdir -p contrib-$HOST_TRIPLET$LEGACY_CONTRIB_SUFFIX && cd contrib-$HOST_TRIPLET$LEGACY_CONTRIB_SUFFIX
../bootstrap --build=$BUILD_TRIPLET --host=$HOST_TRIPLET $CONTRIB_PREFIX_FLAG $CONTRIBFLAGS > $out
if [ -n "$LEGACY_GCC" ]; then
    # The Apple clang driver honours $SDKROOT, so a legacy SDK exported in
    # the environment poisons every native build-helper (gmp's
    # CC_FOR_BUILD test, ncurses' make_hash, meson native targets...).
    # The contrib config.mak has captured MACOSX_SDK above; keep SDKROOT
    # as a plain (non-exported) shell variable from here on.
    SDKROOT_SAVED="$SDKROOT"
    unset SDKROOT
    SDKROOT="$SDKROOT_SAVED"
fi
if [ "$REBUILD" = "yes" ]; then
    make clean
fi
make list
if [ "$CONTRIBFROMSOURCE" = "yes" ]; then
    make fetch
    make -j$JOBS -k || make -j1

    if [ "$PACKAGE" = "yes" ]; then
        make package
    fi

else
if [ ! -e "../$HOST_TRIPLET" ]; then
    if [ -n "$VLC_PREBUILT_CONTRIBS_URL" ]; then
        make prebuilt PREBUILT_URL="$VLC_PREBUILT_CONTRIBS_URL"
        make .luac
    else
        make prebuilt
        make .luac
    fi
fi
fi

# Without -c, an existing contrib prefix is taken as complete and nothing above
# rebuilds anything -- which silently ships a stale libbluray/libaacs when their
# rules or patches have changed. These two carry the Blu-ray support and are
# cheap no-ops once their stamps are current, so ask for them by name. Deleting
# a stamp (and the unpacked source, so the patches re-apply) is what forces a
# rebuild after touching contrib/src/{bluray,aacs,bdplus}.
#
# libaacs additionally has to exist at all: libbluray dlopen()s it, it is
# bundled with the player (see contrib/src/aacs), and packaging refuses to ship
# a Blu-ray plugin without it. It used to be unbuildable for the PowerPC and
# Intel-32 slices, whose 10.4u SDK has no IOKit/storage/IOBDMediaBSDClient.h --
# but no symbol from that header was ever used, and
# libaacs-powervlc-tiger-and-external-mmc.patch drops the include, so every
# slice gets AACS now and AACS_OPTIONAL is no longer set for any of them.
#
# libbdplus is the BD+ layer, dlopen()ed and bundled the same way; it is only a
# warning when missing, but it is just as cheap to keep current.
info "Making sure the Blu-ray contribs are current"
make .bluray
make .aacs
make .bdplus

# Same reasoning for ffmpeg, which carries the PowerPC H.264 patches in
# contrib/src/ffmpeg/000*-ppc-*: without this the prefix built before those
# patches existed is reused for ever, and the build still reports success --
# there is no message at all, because `make list` decides ffmpeg is "to be
# built" while nothing in the non -c path ever runs it. Worse, deleting the
# stamp and the unpacked source is NOT enough on its own: need_pkg finds the
# already-installed libav*.pc in the prefix and marks the package found. To
# force a rebuild, delete the stamp, the unpacked source *and*
# contrib/<triple>/lib/pkgconfig/{libav*,libswscale,libpostproc}.pc.
# A no-op (one stat) once the stamp is current.
make .ffmpeg

# Record the deployment target this prefix was built for (see the guard above).
mkdir -p "${vlcroot}/contrib/${HOST_TRIPLET}${LEGACY_CONTRIB_SUFFIX}"
echo "$MINIMAL_OSX_VERSION" \
    > "${vlcroot}/contrib/${HOST_TRIPLET}${LEGACY_CONTRIB_SUFFIX}/.powervlc-osx-min"
spopd

unset CFLAGS
unset CXXFLAGS
unset OBJCFLAGS

unset EXTRA_CFLAGS
unset EXTRA_LDFLAGS
unset XCODE_FLAGS

# Enable debug symbols by default
export CFLAGS="-g $ARCH_CFLAG $LEGACY_VLC_CPUFLAGS"
export CXXFLAGS="-g $ARCH_CFLAG $LEGACY_VLC_CPUFLAGS"
export OBJCFLAGS="-g $ARCH_CFLAG $LEGACY_VLC_CPUFLAGS"
if [ -n "$LEGACY_GCC" ]; then
    # The 10.4/10.5 SDKs' <inttypes.h> hides the PRI* macros from C++
    # unless __STDC_FORMAT_MACROS is defined (pre-C++11 C99 rule).
    export CXXFLAGS="$CXXFLAGS -D__STDC_FORMAT_MACROS"
fi
if [ -n "$LEGACY_GCC" ]; then
    # Static GCC runtimes: the target OS does not ship libstdc++/libgcc
    # matching our FSF GCC, and shipping them as dylibs needs install_name
    # surgery. gcc silently ignores these when linking plain C.
    export LDFLAGS="-static-libgcc -static-libstdc++ $LEGACY_LDBL_STUBS"
    case "$MINIMAL_OSX_VERSION" in
        10.0|10.1|10.2)
            # Mac OS X 10.2's dyld crashes in __dyld_map_image when it has to
            # pull OpenGL.framework in as a dependency of a bundle being
            # linked -- every plugin that touches GL (screen, vout_macosx,
            # macosx_gl1) takes the process down on its own. Loading the same
            # framework at startup is fine: verified with
            # DYLD_INSERT_LIBRARIES, where all 326 plugins then load. So link
            # it into everything here and let it be there before any bundle
            # asks. Costs one load command; the framework is on every Mac.
            LDFLAGS="$LDFLAGS -framework OpenGL"
            ;;
    esac
    # i386: ffmpeg's re-enabled x86 asm (SSE2+ IDCT / motion-comp / DSP, a big
    # decode speedup for every codec) emits a few text relocations that the
    # legacy ld64 rejects by default. Allow them (the affected text pages
    # become writable -- a minor, well-understood cost) so the asm links into
    # the plugin dylibs. Needs nasm/yasm at build time (contrib/src/ffmpeg).
    case "$ARCH" in
        i386|i686) LDFLAGS="$LDFLAGS -Wl,-read_only_relocs,suppress" ;;
    esac
else
    export LDFLAGS="$ARCH_CFLAG"
fi

#
# vlc/bootstrap
#

info "Bootstrap-ing configure"
spushd "${vlcroot}"
if ! [ -e "${vlcroot}/configure" ]; then
    ${vlcroot}/bootstrap > $out
fi
spopd


if [ ! -z "$VLCBUILDDIR" ];then
    mkdir -p $VLCBUILDDIR
    pushd $VLCBUILDDIR
fi
#
# vlc/configure
#

CONFIGFLAGS=""
if [ ! -z "$BREAKPAD" ]; then
     CONFIGFLAGS="$CONFIGFLAGS --with-breakpad=$BREAKPAD"
fi
if [ "$PACKAGETYPE" = "u" ]; then
    # release package should have sparkle, breakpad, growl
    CONFIGFLAGS="$CONFIGFLAGS --enable-sparkle --enable-breakpad --enable-growl"
elif [ "$PACKAGETYPE" = "n" ]; then
    # nightly package should have growl
    CONFIGFLAGS="$CONFIGFLAGS --enable-growl --disable-sparkle"
else
    # configure.ac turns Sparkle on by default on Mac OS X and then *errors out*
    # if the framework is missing from the contribs -- and the contribs only
    # build it for a release package (see CONTRIBFLAGS above). So every plain
    # build.sh run would die in configure with
    #   "Sparkle framework is required and was not found in <contrib>"
    # unless it is switched off explicitly here.
    CONFIGFLAGS="$CONFIGFLAGS --disable-sparkle"
fi

if [ "${vlcroot}/configure" -nt Makefile ]; then

  WITH_CONTRIB_FLAG=""
  if [ -n "$LEGACY_CONTRIB_SUFFIX" ]; then
      WITH_CONTRIB_FLAG="--with-contrib=${vlcroot}/contrib/${HOST_TRIPLET}${LEGACY_CONTRIB_SUFFIX}"
  fi
  ${vlcroot}/extras/package/macosx/configure.sh \
      --build=$BUILD_TRIPLET \
      --host=$HOST_TRIPLET \
      --with-macosx-version-min=$MINIMAL_OSX_VERSION \
      --with-macosx-sdk=$SDKROOT \
      $WITH_CONTRIB_FLAG \
      $CONFIGFLAGS \
      $VLC_CONFIGURE_ARGS > $out
fi

# Mac OS X 10.2 cannot load an Objective-C plugin that is a dylib. VLC's
# plugins are MH_DYLIB here because libtool's Darwin module_cmds link them
# with -dynamiclib; on 10.3 and later that is fine, since dlopen() takes a
# dylib. On 10.2 there is no dlopen() at all, so our dlcompat has to reach for
# NSAddImage() -- and dyld then runs the ObjC runtime's add-image hook, which
# dies in _objcInit for every image carrying an __OBJC segment (measured: the
# legacy interface, then nsspeechsynthesizer, then the next one...).
#
# Bundles are the format that era expects for loadable code:
# NSCreateObjectFileImageFromFile()/NSLinkModule() handle them, ObjC included,
# and that path is verified on the machine. So link modules with -bundle here.
# Everything else about them is unchanged -- same name, same exported symbol
# list, and no table of contents needed, since NSLinkModule() resolves through
# the symbol table rather than the TOC.
case "$MINIMAL_OSX_VERSION" in
    10.0|10.1|10.2)
        if [ -f libtool ] && grep -q 'module_cmds=.*-dynamiclib' libtool; then
            info "Linking plugins as bundles (10.2 cannot NSAddImage ObjC)"
            sed -i.orig-dynamiclib \
                -e '/^module_cmds=/s/-dynamiclib/-bundle/' \
                -e '/^module_expsym_cmds=/s/-dynamiclib/-bundle/' libtool
        fi
        ;;
esac

#
# make
#

if [ "$REBUILD" = "yes" ]; then
    info "Running make clean"
    make clean
fi

info "Running make -j$JOBS"
make -j$JOBS

info "Preparing VLC.app"
make VLC.app

# Workaround for macOS 10.7: CFNetwork only exists as part of CoreServices framework
# Skipped: libpowervlccore.dylib already links CoreServices directly, so this rename creates a
# duplicate LC_LOAD_DYLIB entry that modern dyld (macOS 12+) refuses to load.
if [ "$ARCH" = "x86_64" ] && [ "$MINIMAL_OSX_VERSION_WORKAROUND" = "yes" ]; then
    install_name_tool -change /System/Library/Frameworks/CFNetwork.framework/Versions/A/CFNetwork /System/Library/Frameworks/CoreServices.framework/Versions/A/CoreServices VLC.app/Contents/MacOS/lib/libpowervlccore.dylib
fi

# dyld before Mac OS X 10.5 has no @rpath: the freshly built libvlc/libvlccore
# keep their absolute build-tree install names, unusable on the target machine.
# Rewrite everything to @executable_path (supported since 10.0), in the bundled
# libraries' ids and in every Mach-O referencing them.
case "$MINIMAL_OSX_VERSION" in
    10.2|10.3|10.4) NEEDS_EXECUTABLE_PATH=yes ;;
    *)              NEEDS_EXECUTABLE_PATH=no  ;;
esac
if [ "$NEEDS_EXECUTABLE_PATH" = "yes" ] && [ -n "$LEGACY_GCC" ] && [ -d VLC.app/Contents/MacOS/lib ]; then
    # Tiger's Finder only understands the legacy icns elements (is32/il32/
    # ih32/it32); the stock VLC.icns is PNG-based (10.7+) and shows as a
    # generic icon there (and blurry in NSImage). VLC-tiger.icns carries
    # both families (generated with libicns png2icns).
    #
    # 10.2 needs more than that: it shows a generic icon even for the Tiger
    # file. Its Icon Services predate ic08/ic09 (10.5 and 10.7), and an
    # element it does not know appears to cost it the whole file rather than
    # just that size. VLC-jaguar.icns is the same artwork with only the
    # classic elements left.
    ICNS_SRC="$vlcroot/modules/gui/legacy_macosx/Resources/VLC-tiger.icns"
    case "$MINIMAL_OSX_VERSION" in
        10.0|10.1|10.2)
            if [ -f "$vlcroot/modules/gui/legacy_macosx/Resources/VLC-jaguar.icns" ]; then
                ICNS_SRC="$vlcroot/modules/gui/legacy_macosx/Resources/VLC-jaguar.icns"
            fi
            ;;
    esac
    if [ -f "$ICNS_SRC" ]; then
        info "Installing legacy application icon ($(basename "$ICNS_SRC"))"
        cp "$ICNS_SRC" VLC.app/Contents/Resources/VLC.icns
    fi
    # The Icecast directory SD (a ~20MB XML parsed in Lua, minutes at 100%
    # CPU on a G4) ships again: the legacy interface now asks the user for
    # confirmation before activating any Lua-based directory service.
    info "Rewriting install names to @executable_path (no @rpath before 10.5)"
    for real in VLC.app/Contents/MacOS/lib/libpowervlc*.*.dylib; do
        [ -f "$real" ] || continue
        old=$("$XT/otool" -D "$real" | tail -1)
        new="@executable_path/lib/$(basename "$real")"
        "$XT/install_name_tool" -id "$new" "$real"
        find VLC.app/Contents/MacOS \( -name "PowerVLC" -o -name "*.dylib" \) -type f \
            -exec "$XT/install_name_tool" -change "$old" "$new" {} \;
    done
    # The C++ plugins link the GCC runtime dynamically (libtool drops
    # -static-libstdc++/-static-libgcc when creating modules): bundle the
    # toolchain's ppc750 runtime dylibs and point everything at them.
    GCC_RT_LIB="$LEGACY_GCC/$LEGACY_TRIPLE/lib"
    for rt in libstdc++.6.dylib libgcc_s.1.1.dylib libatomic.1.dylib; do
        [ -f "$GCC_RT_LIB/$rt" ] || continue
        info "Bundling GCC runtime $rt"
        cp "$GCC_RT_LIB/$rt" VLC.app/Contents/MacOS/lib/
        chmod u+w "VLC.app/Contents/MacOS/lib/$rt"
        "$XT/install_name_tool" -id "@executable_path/lib/$rt" "VLC.app/Contents/MacOS/lib/$rt"
        find VLC.app/Contents/MacOS \( -name "PowerVLC" -o -name "*.dylib" \) -type f \
            -exec "$XT/install_name_tool" -change "$GCC_RT_LIB/$rt" "@executable_path/lib/$rt" {} \;
    done
fi

# Mac OS X 10.2's dyld finds a dylib's exported symbols only through the
# LC_DYSYMTAB table of contents, which modern ld64 no longer emits (it builds
# single-module dylibs, and -multi_module is accepted then ignored). Without
# it the library loads and every one of its symbols reads as undefined --
# measured on a 10.2.1 iBook, down to a five-line test dylib. Rebuild the
# table afterwards; 10.3 and later ignore it, so this is inert everywhere
# else. It has to run LAST: install_name_tool relays out what it edits.
case "$MINIMAL_OSX_VERSION" in
    10.0|10.1|10.2)
        if [ -d VLC.app/Contents/MacOS/lib ]; then
            info "Adding the dylib table of contents (10.2 dyld)"
            python3 "${vlcroot}/extras/package/macosx/add-dylib-toc.py" \
                VLC.app/Contents/MacOS/lib/*.dylib || exit 1
        fi

        # An Objective-C file that defines no class leaves module->symtab
        # NULL, and 10.2's _objcInit() dereferences it: the process dies on
        # dlopen() of the plug-in, silently, before any log line. Cheap to
        # check, invisible if it is not checked.
        info "Checking for Objective-C modules with a NULL symtab (10.2)"
        sh "${vlcroot}/extras/package/macosx/check-objc-modules.sh" \
            VLC.app || exit 1
        ;;
esac

if [ "$PACKAGETYPE" = "u" ]; then
    info "Copying app with debug symbols into VLC-debug.app and stripping"
    rm -rf VLC-debug.app
    cp -Rp VLC.app VLC-debug.app

    # Workaround for breakpad symbol parsing:
    # Symbols must be uploaded for libvlc(core).dylib, not libvlc(core).x.dylib
    (cd VLC-debug.app/Contents/MacOS/lib/ && rm libpowervlccore.dylib && mv libpowervlccore.*.dylib libpowervlccore.dylib)
    (cd VLC-debug.app/Contents/MacOS/lib/ && rm libpowervlc.dylib && mv libpowervlc.*.dylib libpowervlc.dylib)


    find VLC.app/ -name "*.dylib" -exec strip -x {} \;
    find VLC.app/ -type f -name "PowerVLC" -exec strip -x {} \;
    find VLC.app/ -type f -name "Sparkle" -exec strip -x {} \;
    find VLC.app/ -type f -name "Growl" -exec strip -x {} \;
    find VLC.app/ -type f -name "Breakpad" -exec strip -x {} \;

if [ "$BUILD_TRIPLET" = "$HOST_TRIPLET" ]; then
    bin/powervlc-cache-gen VLC.app/Contents/MacOS/plugins
fi

    info "Building VLC release archive"
    make package-macosx-release
    shasum -a 512 vlc-*-release.zip
elif [ "$PACKAGETYPE" = "n" -o "$PACKAGE" = "yes" ]; then
    info "Building VLC dmg package"
    make package-macosx
fi

# PowerVLC branding: ship the bundle under its own name so Finder shows
# "PowerVLC" and the port can live next to the official VLC.app without
# sharing its preferences (the Info.plist identifier already differs).
if [ -d VLC.app ]; then
    info "Renaming bundle to PowerVLC.app"
    rm -rf PowerVLC.app
    mv VLC.app PowerVLC.app
fi

if [ ! -z "$VLCBUILDDIR" ];then
    popd
fi
