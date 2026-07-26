# FLAC

FLAC_VERSION := 1.3.4
FLAC_URL := http://downloads.xiph.org/releases/flac/flac-$(FLAC_VERSION).tar.xz

PKGS += flac
ifeq ($(call need_pkg,"flac"),)
PKGS_FOUND += flac
endif

$(TARBALLS)/flac-$(FLAC_VERSION).tar.xz:
	$(call download_pkg,$(FLAC_URL),flac)

.sum-flac: flac-$(FLAC_VERSION).tar.xz

flac: flac-$(FLAC_VERSION).tar.xz .sum-flac
	$(UNPACK)
ifdef HAVE_WINSTORE
	$(APPLY) $(SRC)/flac/console_write.patch
	$(APPLY) $(SRC)/flac/remove_blocking_code_useless_flaclib.patch
	$(APPLY) $(SRC)/flac/no-createfilea.patch
endif
ifdef HAVE_DARWIN_OS
	cd $(UNPACK_DIR) && sed -e 's,-dynamiclib,-dynamiclib -arch $(ARCH),' -i.orig configure
ifeq ($(ARCH),ppc)
	# libFLAC's Makefile.am hardcodes -faltivec on Darwin/ppc regardless of
	# --disable-altivec (upstream FIXME); it stamps every object ppc7400,
	# unloadable on a G3 (the .flac rule autoreconfs, propagating this)
	cd $(UNPACK_DIR) && sed -i.orig -e 's/-faltivec//g' src/libFLAC/Makefile.am
endif
endif
ifdef HAVE_ANDROID
ifeq ($(ANDROID_ABI), x86)
	# cpu.c:130:29: error: sys/ucontext.h: No such file or directory
	# defining USE_OBSOLETE_SIGCONTEXT_FLAVOR allows us to bypass that
	cd $(UNPACK_DIR) && sed -i.orig -e s/"#  undef USE_OBSOLETE_SIGCONTEXT_FLAVOR"/"#define USE_OBSOLETE_SIGCONTEXT_FLAVOR"/g src/libFLAC/cpu.c
endif
endif
	$(APPLY) $(SRC)/flac/dont-force-msvcrt-version.patch
	$(call pkg_static,"src/libFLAC/flac.pc.in")
	$(UPDATE_AUTOCONFIG)
	$(MOVE)

FLACCONF := \
	--disable-examples \
	--disable-thorough-tests \
	--disable-doxygen-docs \
	--disable-xmms-plugin \
	--disable-cpplibs \
	--disable-oggtest
# TODO? --enable-sse
ifdef HAVE_DARWIN_OS
ifneq ($(findstring $(ARCH),i386 x86_64),)
FLACCONF += --disable-asm-optimizations
endif
ifeq ($(ARCH),ppc)
# G3 baseline: the AltiVec code paths would stamp every object ppc7400,
# which dyld then refuses to load on a ppc750 machine
FLACCONF += --disable-altivec --disable-asm-optimizations
endif
ifneq ($(call darwin_min_os_at_least, 10.5), true)
# libSystem before 10.5 has no __stack_chk_fail/__stack_chk_guard
FLACCONF += --disable-stack-smash-protection
endif
endif

FLAC_CFLAGS := $(CFLAGS)
ifdef HAVE_WIN32
FLAC_CFLAGS += -mstackrealign
FLAC_CFLAGS +="-DFLAC__NO_DLL"
endif

DEPS_flac = ogg $(DEPS_ogg)

.flac: flac
	cd $< && $(AUTORECONF)
	cd $< && $(HOSTVARS) ./configure $(HOSTCONF) CFLAGS="$(FLAC_CFLAGS)" $(FLACCONF)
	$(MAKE) -C $< -C include install
	$(MAKE) -C $< -C src/libFLAC install
	$(MAKE) -C $< -C src/share install
	touch $@
