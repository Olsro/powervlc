# x264

X264_HASH := e067ab0b530395f90b578f6d05ab0a225e2efdf9
X264_VERSION := $(X264_HASH)
X264_GITURL := $(VIDEOLAN_GIT)/videolan/x264.git

ifdef BUILD_ENCODERS
ifdef GPL
PKGS += x264
endif
endif

ifeq ($(call need_pkg,"x264 >= 0.148"),)
PKGS_FOUND += x264
endif

ifeq ($(call need_pkg,"x264 >= 0.153"),)
PKGS_FOUND += x26410b
endif

PKGS_ALL += x26410b

X264CONF = \
	--disable-avs \
	--disable-lavf \
	--disable-cli \
	--disable-ffms \
	--disable-opencl
ifndef HAVE_WIN32
X264CONF += --enable-pic
ifeq ($(ARCH),ppc)
# The G3 target has no vector unit. G4/G5 builds export VLC_PPC_ALTIVEC and
# use the restored big-endian AltiVec backend below.
X264CONF += --disable-vsx
ifndef VLC_PPC_ALTIVEC
X264CONF += --disable-asm
endif
endif
ifeq ($(ARCH),i386)
ifdef HAVE_MACOSX
# The i386 nasm objects carry text relocations that ld64 rejects inside
# plugin dylibs (encoder only: C is fine)
X264CONF += --disable-asm
endif
endif
else
ifdef HAVE_WINSTORE
X264CONF += --enable-win32thread
else
X264CONF += --disable-win32thread
endif
endif
ifdef HAVE_CROSS_COMPILE
ifndef HAVE_DARWIN_OS
ifdef HAVE_ANDROID
X264CONF += --cross-prefix="$(subst ld,,$(LD))"
else
X264CONF += --cross-prefix="$(HOST)-"
endif
endif
ifdef HAVE_ANDROID
# broken text relocations
ifeq ($(ANDROID_ABI), x86)
X264CONF += --disable-asm
endif
endif
endif

ifneq ($(filter arm aarch64, $(ARCH)),)
ifndef HAVE_WIN32
X264_ASM_USES_CC:=1
endif
endif

ifdef X264_ASM_USES_CC
X264CONF += --extra-asflags="$(EXTRA_CFLAGS)"
endif

$(TARBALLS)/x264-$(X264_VERSION).tar.xz:
	$(call download_git,$(X264_GITURL),,$(X264_HASH))

.sum-x26410b: .sum-x264
	touch $@

.sum-x264: x264-$(X264_VERSION).tar.xz
	$(call check_githash,$(X264_VERSION))
	touch $@

x264 x26410b: %: x264-$(X264_VERSION).tar.xz .sum-%
	$(UNPACK)
	$(UPDATE_AUTOCONFIG)
	$(APPLY) $(SRC)/x264/x264-winstore.patch
	$(APPLY) $(SRC)/x264/0001-osdep-use-direct-path-to-internal-x264.h.patch
	$(APPLY) $(SRC)/x264/0001-configure-set-_FILE_OFFSET_BITS-to-detect-fseeko.patch
	# Restore/fix the big-endian AltiVec backend from powerpc-ports commit
	# d693f73b (2026-06-26). The first patch supplies VSX-less helpers, the
	# second fixes chroma MC endianness and uninitialized lanes. 0002 makes
	# x264's Darwin probe accept our FSF GCC; 0003 keeps the four tiny kernels
	# that lose on a 7447A in C.
	$(APPLY) $(SRC)/x264/altivec-x264.patch
	$(APPLY) $(SRC)/x264/altivec-x264-2.patch
	$(APPLY) $(SRC)/x264/0002-ppc-darwin-use-fsf-gcc-altivec-flags.patch
	$(APPLY) $(SRC)/x264/0003-ppc-g4-keep-four-slower-tiny-kernels-in-c.patch
	$(MOVE)

.x264: x264
	$(REQUIRE_GPL)
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) $(X264CONF)
	# make dummy dependency file
	touch $(BUILD_DIR)/.depend
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@

.x26410b: .x264
	touch $@
