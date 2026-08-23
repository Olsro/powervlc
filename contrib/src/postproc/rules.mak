# libpostproc

POSTPROC_GITURL:=$(GITHUB)/michaelni/libpostproc
POSTPROC_GITVERSION:=e4982b227779f24f7c54d699d2e247652f69c475

POSTPROC_CONF = --prefix="$(PREFIX)" --enable-static --disable-shared \
	--extra-ldflags="$(LDFLAGS)" \
	--cc="$(CC)" \
	--pkg-config="$(PKG_CONFIG)" \
	--disable-doc \
	--disable-debug \
	--disable-devices \
	--disable-bsfs \
	--disable-nvenc \
	--disable-linux-perf

ifdef ENABLE_PDB
POSTPROC_CONF += --ln_s=false
endif

DEPS_postproc = ffmpeg $(DEPS_ffmpeg)

POSTPROC_CONF += --disable-network
POSTPROC_CONF += --disable-encoders --disable-muxers

# Small size
ifdef WITH_OPTIMIZATION
ifdef ENABLE_SMALL
POSTPROC_CONF += --enable-small
endif
ifeq ($(ARCH),arm)
ifdef HAVE_ARMV7A
POSTPROC_CONF += --enable-thumb
endif
endif
else
POSTPROC_CONF += --optflags=-Og
endif

ifdef HAVE_CROSS_COMPILE
POSTPROC_CONF += --enable-cross-compile --disable-programs
ifndef HAVE_DARWIN_OS
POSTPROC_CONF += --cross-prefix=$(HOST)-
endif
endif

# ARM stuff
ifeq ($(ARCH),arm)
POSTPROC_CONF += --arch=arm
ifdef HAVE_ARMV7A
POSTPROC_CONF += --cpu=cortex-a8
endif
ifdef HAVE_ARMV6
POSTPROC_CONF += --cpu=armv6 --disable-neon
endif
endif

# ARM64 stuff
ifeq ($(ARCH),aarch64)
POSTPROC_CONF += --arch=aarch64
endif

# MIPS stuff
ifeq ($(ARCH),mipsel)
POSTPROC_CONF += --arch=mips
endif
ifeq ($(ARCH),mips64el)
POSTPROC_CONF += --arch=mips64
endif

# RISC-V stuff
ifneq ($(findstring $(ARCH),riscv32 riscv64),)
POSTPROC_CONF += --arch=riscv
endif

# x86 stuff
ifeq ($(ARCH),i386)
ifndef HAVE_DARWIN_OS
POSTPROC_CONF += --arch=x86
endif
endif

# x86_64 stuff
ifeq ($(ARCH),x86_64)
ifndef HAVE_DARWIN_OS
POSTPROC_CONF += --arch=x86_64
endif
endif

# Darwin
ifdef HAVE_DARWIN_OS
ifeq ($(ARCH),arm64_32)
# TODO remove when FFMpeg supports arm64_32
POSTPROC_CONF += --arch=aarch64_32
else
POSTPROC_CONF += --arch=$(ARCH)
endif
POSTPROC_CONF += --target-os=darwin --extra-cflags="$(CFLAGS)"
ifeq ($(call darwin_sdk_at_most, 10.8), true)
# assert.h in the pre-10.9 SDKs predates C11: no static_assert macro
# (same workaround as the ffmpeg contrib)
POSTPROC_CONF += --extra-cflags="-Dstatic_assert=_Static_assert"
endif
ifeq ($(ARCH),ppc)
POSTPROC_CONF += --enable-pic
# The configure probe accepts -maltivec even when the target flags say
# -mcpu=750, then silently promotes every object to the ppc7400 subtype.  Such
# a library is rejected by dyld on a real G3.  PowerVLC's G4/G5 builds export
# VLC_PPC_ALTIVEC explicitly; all other PowerPC builds must stay scalar.
ifndef VLC_PPC_ALTIVEC
POSTPROC_CONF += --disable-altivec
endif
endif
ifeq ($(ARCH),x86_64)
POSTPROC_CONF += --cpu=core2
endif
ifdef HAVE_IOS
POSTPROC_CONF += --enable-pic --extra-ldflags="$(EXTRA_CFLAGS) -isysroot $(IOS_SDK)"
endif
endif

# Linux
ifdef HAVE_LINUX
POSTPROC_CONF += --target-os=linux --enable-pic

endif

ifdef HAVE_ANDROID
# broken text relocations
ifeq ($(ANDROID_ABI), x86)
POSTPROC_CONF +=  --disable-mmx --disable-mmxext --disable-inline-asm
endif
endif

POSTPROC_CONF += --disable-autodetect
# use the real maintained libavutil, only headers should be used
# DO NOT install this libavutil in place of the FFmpeg one
POSTPROC_CONF += --disable-avutil
POSTPROC_CONF += --enable-postproc

# Windows
ifdef HAVE_WIN32
POSTPROC_CONF += --target-os=mingw32
POSTPROC_CONF += --disable-w32threads --enable-pthreads --extra-libs="-lpthread"
DEPS_postproc += winpthreads $(DEPS_winpthreads)

ifeq ($(ARCH),x86_64)
POSTPROC_CONF += --cpu=athlon64 --arch=x86_64
else
ifeq ($(ARCH),i386) # 32bits intel
POSTPROC_CONF+= --cpu=i686 --arch=x86
else
ifdef HAVE_ARMV7A
POSTPROC_CONF+= --arch=arm
endif
endif
endif

else # !Windows
POSTPROC_CONF += --enable-pthreads
endif

# Solaris
ifdef HAVE_SOLARIS
ifeq ($(ARCH),x86_64)
POSTPROC_CONF += --cpu=core2
endif
POSTPROC_CONF += --target-os=sunos --enable-pic
endif

# Build
ifdef GPL
PKGS += postproc
endif
ifeq ($(call need_pkg,"libpostproc"),)
PKGS_FOUND += postproc
endif

POSTPROC_CONF += --nm="$(NM)" --ar="$(AR)" --ranlib="$(RANLIB)"

$(TARBALLS)/postproc-$(POSTPROC_GITVERSION).tar.xz:
	$(call download_git,$(POSTPROC_GITURL),,$(POSTPROC_GITVERSION))

.sum-postproc: $(TARBALLS)/postproc-$(POSTPROC_GITVERSION).tar.xz
	$(call check_githash,$(POSTPROC_GITVERSION))
	touch $@

postproc: postproc-$(POSTPROC_GITVERSION).tar.xz .sum-postproc
	$(UNPACK)
	$(APPLY) $(SRC)/postproc/0001-force-using-external-libavutil.patch
	$(APPLY) $(SRC)/postproc/0002-add-missing-libavcodec-headers.patch
ifdef HAVE_MACOSX
	# same as the ffmpeg contrib: Darwin malloc is 16-byte aligned and
	# mem.c keeps the fallback, the configure guard is moot here
	sed -i.orig1 's/if ! enabled_any memalign posix_memalign aligned_malloc; then/if false; then # PowerVLC: Darwin malloc is 16-byte aligned/' $(UNPACK_DIR)/configure
endif
	$(MOVE)

.postproc: postproc
	$(REQUIRE_GPL)
	$(MAKEBUILDDIR)
	$(MAKECONFDIR)/configure $(POSTPROC_CONF)
ifdef HAVE_MACOSX
ifneq ($(call darwin_min_os_at_least, 10.6), true)
	# posix_memalign is absent before Mac OS X 10.6 (see ffmpeg contrib)
	sed -i.orig -e 's/#define HAVE_POSIX_MEMALIGN 1/#define HAVE_POSIX_MEMALIGN 0/' $(BUILD_DIR)/config.h
endif
endif
	+$(MAKEBUILD)
	+$(MAKEBUILD) install-libs install-headers
	touch $@
