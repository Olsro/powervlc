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
    g4|g5)
        # PowerPC with AltiVec, Mac OS X **10.2 Jaguar** (floor lowered with
        # the G3 slice; see the `ppc` case). The contribs are
        # shared between the variants and built for the lowest
        # common ISA (7400 + AltiVec: a 7450 or a 970 runs all of it);
        # VLC itself is tuned per variant below.
        #
        # There used to be a third variant, g4e (-mcpu=7450), shipping a
        # ppc7450 slice. Dropped after measuring it on the machine it was
        # meant for -- a 1.42 GHz Mac mini G4, machine = ppc7450:
        #   MPEG-2 DVD, 60 s, x4 : 18.145 s CPU (7400) vs 18.060 s (7450)
        #   H.264 720p,  40 s, x5 : 30.9 s     (7400) vs 31.0 s     (7450)
        # 0.5 % on one workload, nothing on the other, for ~90 MB in the
        # universal bundle. The reason it buys so little: -mcpu=7450 only
        # reschedules VLC's own code (same ISA, same instruction mix -- the
        # AltiVec asm is byte-identical), while the contribs, where decoding
        # actually spends its time, are the shared -mtune=7400 build either
        # way. A 7450 now grades the ppc7400 slice highest and keeps AltiVec.
        # NEVER drop ppc7400 instead: a 7400 cannot grade a ppc7450 slice and
        # would fall back to ppc750, i.e. no AltiVec -- measured 13 % slower.
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
            # -mno-powerpc64 is NOT optional. Unlike -mcpu=7400/7450,
            # GCC's -mcpu=970 turns on -mpowerpc64, which lets it emit
            # 64-bit GPR instructions (std/ld/rldicl/sldi/srdi) inside a
            # 32-bit binary -- and Mac OS X does not preserve the upper
            # halves of the GPRs across context switches for a 32-bit
            # task, so any value living in one is corrupted at the first
            # preemption. Apple's own GCC never enabled this for -m32.
            # PowerVLC 1.1.0 shipped without it and the G5 slice died at
            # startup on a PowerMac7,2 (EXC_BAD_ACCESS at 0x0 in
            # var_Inherit, called from AllocateAllPlugins) while the G3,
            # G4 and G4e slices ran fine on the same machine -- and the
            # universal build died too, since a G5 grades the ppc970
            # subtype highest and picks exactly that slice.
            # -mtune=970 (scheduling) and -mmfcrf are unaffected.
            g5)  LEGACY_VLC_CPUFLAGS="-mcpu=970 -mtune=970 -mno-powerpc64 -maltivec -mabi=altivec" ;;
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
    x86_64)
        # ⚠ 10.6, PAS 10.5. Le défaut de ce script (10.5) faisait tomber la
        # tranche x64 sous la porte GCD de configure.ac (« targeting Mac OS X
        # < 10.6: the modern interface cannot be built (ARC), using the legacy
        # one ») : l'interface MODERNE n'y était donc jamais construite, alors
        # que BUILD-POWERVLC.md l'annonce et que les Macs 10.7+ doivent en
        # profiter. Constaté sur un bundle x64 dépourvu de
        # libmacosx_plugin.dylib. 10.6 est aussi le plancher que la tranche
        # revendique déjà côté plist, et le premier Mac Intel 64 bits (2006)
        # peut y monter ; un Intel resté en 10.5 prend la tranche x86.
        MINIMAL_OSX_VERSION="10.6"
        ;;
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

# libdvdnav for exactly the same reason, and it bit us once: the DVD virtual
# machine lives in there, and contrib/src/dvdnav/ carries PowerVLC patches that
# change what the player is told about the disc (the Tiger raw-device read
# path, and the logical subpicture number without which the first subtitle
# track is picked on some discs). Purging its stamp, its unpacked source and
# its .pc left the build linking happily against the PREVIOUS static library --
# no error, no warning, and a fix that appeared not to work.
info "Making sure the DVD contribs are current"
make .dvdnav

# libcrystalhd for the same reason, and with a sharper failure mode than the
# rest. Its patches do not merely build the library: they define the ioctl
# layout it uses to talk to the BroadcomCrystalHD kext, which is installed
# system-wide and shared with every other client on the machine. Nothing else
# rebuilds this contrib in the non -c path, so editing contrib/src/crystalhd/
# would silently relink the plugin against the previously built
# libcrystalhd.a -- leaving a player that disagrees with its own driver about
# what it is sending into the kernel.
#
# Only the Intel slices: the card is a mini-PCIe module, and the contrib is
# selected for i386/x86_64 alone (contrib/src/crystalhd/rules.mak).
case "$ARCH" in
    i686|x86_64)
        info "Making sure the Crystal HD contrib is current"
        make .crystalhd
        ;;
esac

# fontconfig and libass for the same reason, and specifically because both
# changed with the move to fontconfig 2.16.0: libbluray needs fontconfig to
# resolve BD-J menu fonts on Darwin (without it a disc that ships no font of
# its own draws its menus with no text at all), and libass was switched from
# "no font provider on this platform" to using the system fonts like it does
# everywhere else. Neither is rebuilt by anything above in the non -c path, so
# a prefix built before the change would keep a fontconfig-less libass and a
# libbluray that cannot link against the new one.
make .fontconfig
make .ass

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
    # x86_64 targets 10.5, and on a deployment target that old the current ld
    # (ld-1230) lays __LINKEDIT out in an order cctools strip will not touch:
    # every dylib comes back "function starts data out of place", so this slice
    # alone would ship its full debug map. Reproducible in three lines, and it
    # is the deployment target that decides -- 10.9 and later are fine:
    #
    #   clang -arch x86_64 -mmacosx-version-min=10.5 -g -dynamiclib t.c -o t.dylib
    #   strip -x t.dylib        # -> function starts data out of place
    #
    # Nothing can strip the result afterwards. -no_function_starts only moves
    # the complaint to the data-in-code table, then to the symbol table.
    # llvm-strip refuses outright ("shared library is not yet supported").
    # -ld_classic does produce a strippable layout -- and CRASHES on a real
    # plugin link (assertion in ld::passes::stubs::x86_64::classic::
    # StubHelperAtom::copyRawContent, reproduced relinking libgnutls_plugin
    # against the contribs), so it is not an option.
    #
    # So drop the debug info at link time instead: -Wl,-S emits no STABS at
    # all, which is the same end state strip -S reaches elsewhere. Measured on
    # that relink: 4212K -> 3446K, 38570 STABS entries -> 0, and all 5872 local
    # function names kept, so backtraces stay readable.
    #
    # The one thing lost, and only on this slice: atos can no longer add
    # file:line, because there is no debug map left to point at the .o files.
    # It still resolves the function name.
    case "$ARCH" in
        x86_64)
            case "$MINIMAL_OSX_VERSION" in
                10.*)
                    LDFLAGS="$LDFLAGS -Wl,-S"
                    STRIP_DEBUG_AT_LINK="yes"
                    ;;
            esac
            ;;
    esac
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

# VLC's configure turns AltiVec on for every host_cpu matching powerpc*, which
# is wrong for the G3 (750): it has no vector unit, and this target is built
# with -mcpu=750 and no -maltivec. The probe still succeeds -- it only asks the
# *assembler* about "vperm", and that answers yes (via -Wa,-maltivec) -- so
# CAN_COMPILE_ALTIVEC gets defined and the C intrinsics are then compiled
# without -maltivec:
#   i420_yuy2.c: implicit declaration of function 'vec_ld'
#   algo_x.c:    AltiVec argument passed to unprototyped function
# The G4/G5 slices are unaffected: they set LEGACY_PPC_ALTIVEC and do pass
# -maltivec. So gate on that rather than on the CPU family.
case "$HOST_TRIPLET" in
    powerpc-*)
        if [ "$LEGACY_PPC_ALTIVEC" != "yes" ]; then
            CONFIGFLAGS="$CONFIGFLAGS --disable-altivec"
        fi
        ;;
esac

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
#
# Settle the autotools chain FIRST. AM_MAINTAINER_MODE is enabled, so when
# configure.ac is newer than aclocal.m4 -- which is exactly what a version bump
# leaves behind -- the *make* below re-runs aclocal, autoconf and
# `config.status --recheck`, and config.status regenerates libtool. Patching
# libtool before that happens silently loses the patch, and every plugin gets
# linked MH_DYLIB again: on 10.3+ the bundle then builds and packages without a
# single error, but no plugin loads at runtime and `--list` reports core alone.
# `am--refresh` forces that regeneration now, so the patch below is the last
# word on libtool.
if [ -f Makefile ]; then
    make am--refresh > $out 2>&1 || true
fi
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
# ⚠ The install prefix is never cleaned by "make install": it only ever
# adds. A file that USED to be installed somewhere stays there for ever,
# and package.mak copies both lua trees into one directory in the bundle
# -- so a leftover silently overwrites the file that is current.
#
# Measured 2026-08-12: the extension translation catalogues moved from
# vlclibdir to vlcdatadir (they must be in the data dir, pvlc_i18n.load()
# builds the path from it), but the copies under lib/vlc/lua/i18n from
# before the move were still sitting in the prefix. Being copied second,
# they won: every bundle since had 72 catalogues -- 18 languages x 4
# extensions -- frozen at the day of the move, with no error anywhere and
# the extension code itself perfectly up to date beside them.
#
# Emptied rather than guarded against: these trees are small, they are
# reinstalled a second later by the "install" the VLC.app rule depends
# on, and this way what ends up in the bundle is exactly what the current
# install rules produce. package.mak refuses the overlap as well, so a
# future move is caught in the open instead of shipping quietly.
#
# One rm, no test: this runs under "set -e", and a [ -d ] that answers no
# on the last turn of a loop is a non-zero status that would end the build.
# rm -rf is happy with a path that is not there.
rm -rf vlc_install_dir/lib/vlc/lua vlc_install_dir/share/vlc/lua

# Same trap, on a PLUGIN this time, and with teeth: a module that stops being
# built keeps its previously installed copy for ever -- and automake does not
# remove the object either, so comparing the prefix against modules/.libs sees
# two stale files agreeing with each other.
#
# The case that bit us: keychain.m is compiled with ARC, whose runtime only
# exists from Mac OS X 10.7. configure now skips the ARC plugins below that
# (HAVE_OBJC_ARC), but an incremental tree still carried the copy built when
# it did not, and packaging shipped it. On 10.6.8 that copy is fatal -- dyld
# kills the process as it is dlopen()ed:
#   Symbol not found: _objc_retainAutoreleasedReturnValue
#   Referenced from: .../plugins/libkeychain_plugin.dylib
# which took the player down the moment anything reached the keystore.
#
# Keyed on the deployment target, the same criterion configure uses.
case "$MINIMAL_OSX_VERSION" in
    10.2|10.3|10.4|10.5|10.6)
        for _stale in modules/.libs/libkeychain_plugin.* \
                      modules/libkeychain_plugin.la \
                      vlc_install_dir/lib/vlc/plugins/keystore/libkeychain_plugin.*; do
            [ -e "$_stale" ] || continue
            echo "  dropping ARC-only plugin ${_stale##*/} (needs 10.7, target $MINIMAL_OSX_VERSION)"
            rm -f "$_stale"
        done
        ;;
esac

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

# The two loops above only ever knew about libpowervlc* and the GCC runtime,
# and they only run for the legacy slices. Everything else copied into
# Contents/MacOS/lib by package.mak kept whatever install name its build gave
# it -- which for libaacs and libbdplus (the only contribs built shared,
# because libbluray dlopen()s them instead of linking them) is the contrib
# prefix *inside this build tree*: a path that exists on no machine but this
# one. It was there on all seven slices.
#
# The bundle still worked: libbluray asks dyld for "libaacs.dylib" prefixed
# with each of its search paths in turn, and the fifth of them,
# "@executable_path/lib/", is an explicit path that resolves whatever the
# id says (verified with dlopen() on the arm64 slice). But the id is what dyld
# registers the image under, what every otool/codesign/notarisation audit
# reports, and what would be used verbatim by any future library that *links*
# one of these rather than dlopen()ing it -- which would then fail on the
# user's machine, silently, with the build machine's path in the error.
#
# So normalise generically instead of naming the two files: any bundled dylib
# whose id is still an absolute non-system path gets @executable_path/lib/,
# and every Mach-O that referenced the old id follows.
#
# Not with install_name_tool: it cannot run on the x86_64 slice at all. That
# slice deploys to 10.5, and the __LINKEDIT order ld produces for so old a
# target is the one cctools refuses -- "function starts data out of place",
# the same wall the -Wl,-S comment above hits for strip, reproduced there in
# three lines and reproducible here on the stock contrib libaacs. Doing that
# one slice differently is how this bug would come back on the slice nobody
# re-checks, so all seven go through set-dylib-name.py, which overwrites the
# name inside its load command and moves nothing.
SETNAME="python3 ${vlcroot}/extras/package/macosx/set-dylib-name.py"
OT="${XT:+$XT/}otool"

# Editing a Mach-O invalidates whatever code signature it carried, and an
# invalid signature is fatal on Apple Silicon (an absent one is not). Restore
# the state the file was in and nothing more: the PowerPC and Intel-32 slices
# are unsigned, and so are the x86_64 dylibs (the 10.5 deployment target means
# the linker adds no ad-hoc signature, and the strip that would have added one
# is skipped on that slice -- see -Wl,-S above). Signing them here would be a
# change of its own, on the slices that boot the OSes this can least be tested
# on. Never the bundle seal or Contents/MacOS/PowerVLC either: the app's
# ad-hoc identity is what Keychain binds the saved Subsonic/Jellyfin secrets
# to, and re-sealing it makes the keystore ask the user again.
resign()
{
    _rs_file="$1"; shift
    if codesign -d "$_rs_file" >/dev/null 2>&1; then _rs_was=yes; else _rs_was=no; fi
    chmod u+w "$_rs_file"
    "$@" || return 1
    if [ "$_rs_was" = "yes" ]; then
        codesign -f -s - "$_rs_file" >/dev/null 2>&1 || \
            echo "  could not re-sign ${_rs_file#VLC.app/} after renaming" >&2
    fi
}

if [ -d VLC.app/Contents/MacOS/lib ]; then
    info "Normalising the bundled libraries' install names"
    for real in VLC.app/Contents/MacOS/lib/*.dylib; do
        [ -f "$real" ] || continue
        old=`"$OT" -D "$real" | tail -1`
        # @executable_path/@rpath/@loader_path are already relocatable, and
        # /usr/lib + /System are the OS's own, which must stay absolute.
        case "$old" in
            ""|@*|/usr/lib/*|/System/*) continue ;;
        esac
        new="@executable_path/lib/`basename "$real"`"
        if [ "$old" = "$new" ]; then continue; fi
        resign "$real" $SETNAME --id "$new" "$real"
        # Follow the old id into whatever named it. Nothing does today (both
        # libraries are dlopen()ed, never linked), which is precisely why the
        # id was never noticed; a linked one would land here.
        find VLC.app/Contents/MacOS \( -name "PowerVLC" -o -name "*.dylib" \) -type f \
            -print | while read -r macho; do
            "$OT" -L "$macho" | grep -Fq "	$old (" || continue
            resign "$macho" $SETNAME --change "$old" "$new" "$macho"
        done
    done

    # And refuse to ship a bundle that still points anywhere outside the OS.
    # This is the check that would have caught libaacs/libbdplus years ago:
    # nothing here fails at build time, and on the user's machine the failure
    # is a plug-in that quietly does less than it should.
    leftover=`find VLC.app/Contents/MacOS -type f \( -name "PowerVLC" -o -name "*.dylib" \) -print0 \
        | xargs -0 -n1 "$OT" -L 2>/dev/null \
        | sed -n 's/^	\(\/[^ ]*\) (compatibility version.*/\1/p' \
        | grep -v -e '^/usr/lib/' -e '^/System/' | sort -u` || true
    if [ -n "$leftover" ]; then
        echo "ERROR: the bundle still references paths outside the OS:" >&2
        echo "$leftover" | sed 's/^/       /' >&2
        echo "       They exist on this build machine only. Bundle them into" >&2
        echo "       Contents/MacOS/lib (extras/package/macosx/package.mak)," >&2
        echo "       or drop whatever pulls them in." >&2
        exit 1
    fi
fi

# Everything is compiled with -g, which leaves a debug *map* in each Mach-O:
# ~100k STABS entries per plugin (SO/OSO/FUN -- source file names and pointers
# to the .o files of THIS build tree). None of it is usable on the target
# machine, and it is the single biggest avoidable weight in the bundle: ~15 MB
# per architecture, ~100 MB across the seven slices of the universal build.
#
# -S removes that map and nothing else. Every local function name survives
# (measured on libavcodec_plugin: 16880 before, 16880 after), so a crash log
# stays readable on the user's machine -- which matters here, because 10.2-10.6
# have no dSYM and no way to symbolicate after the fact. -x would take another
# ~50 MB but leaves only the three exported vlc_entry symbols, turning every
# PowerPC backtrace into raw offsets.
#
# Debugging here is unaffected either way: strip preserves LC_UUID and the
# unstripped originals stay in modules/.libs, so atos and symbolicatecrash
# still find them by UUID and resolve down to file:line.
#
# Two ordering constraints, each verified by the failure it causes:
#  - "$STRIP", never a plain strip: Xcode's cctools answers "unknown cputype
#    (18)" on PowerPC and leaves 23 of the fat plugins untouched. The legacy
#    toolchain's strip reads them fine.
#  - this has to run BEFORE add-dylib-toc.py below. Once that script has
#    rebuilt LC_DYSYMTAB's table of contents, strip refuses the file
#    ("table of contents out of place") -- it hit all 8 of lib/*.dylib.
#
# strip also invalidates the linker's ad-hoc signature, and an invalid
# signature is fatal on Apple Silicon (an absent one is not), so re-sign each
# file that was touched. Only those files: the bundle seal and
# Contents/MacOS/PowerVLC are deliberately left alone, because the app's ad-hoc
# code identity is what Keychain Services binds the saved Subsonic/Jellyfin
# secrets to, and re-sealing it makes the keystore ask again.
if [ "$PACKAGETYPE" = "u" ]; then
    info "Copying app with debug symbols into VLC-debug.app"
    rm -rf VLC-debug.app
    cp -Rp VLC.app VLC-debug.app

    # Workaround for breakpad symbol parsing:
    # Symbols must be uploaded for libvlc(core).dylib, not libvlc(core).x.dylib
    (cd VLC-debug.app/Contents/MacOS/lib/ && rm libpowervlccore.dylib && mv libpowervlccore.*.dylib libpowervlccore.dylib)
    (cd VLC-debug.app/Contents/MacOS/lib/ && rm libpowervlc.dylib && mv libpowervlc.*.dylib libpowervlc.dylib)
fi

# A file strip refuses just keeps its debug map: bigger bundle, still correct.
# Report it rather than aborting -- and never let it trip `set -e`.
if [ "$STRIP_DEBUG_AT_LINK" = "yes" ]; then
    info "Debug map already dropped at link time (-Wl,-S), not stripping"
else
    info "Stripping the debug map from the bundled dylibs (strip -S)"
    find VLC.app/Contents/MacOS -type f -name "*.dylib" -print | while read -r so; do
        if ! "$STRIP" -S "$so" 2>/dev/null; then
            echo "  strip -S refused ${so#VLC.app/}, debug map kept" >&2
        elif [ -z "$LEGACY_GCC" ]; then
            codesign -f -s - "$so" >/dev/null 2>&1 || \
                echo "  could not re-sign ${so#VLC.app/} after strip" >&2
        fi
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

# VLC-debug.app and the strip both moved up, ahead of add-dylib-toc.py.
if [ "$PACKAGETYPE" = "u" ]; then
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
