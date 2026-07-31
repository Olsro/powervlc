# FLAC

FLAC_VERSION := 1.4.2
FLAC_URL := $(GITHUB)/xiph/flac/releases/download/$(FLAC_VERSION)/flac-$(FLAC_VERSION).tar.xz

PKGS += flac
ifeq ($(call need_pkg,"flac"),)
PKGS_FOUND += flac
endif

$(TARBALLS)/flac-$(FLAC_VERSION).tar.xz:
	$(call download_pkg,$(FLAC_URL),flac)

.sum-flac: flac-$(FLAC_VERSION).tar.xz

flac: flac-$(FLAC_VERSION).tar.xz .sum-flac
	$(UNPACK)
	# disable building a tool we don't use
	sed -e 's,add_subdirectory("microbench"),#add_subdirectory("microbench"),' -i.orig $(UNPACK_DIR)/CMakeLists.txt
	$(call pkg_static,"src/libFLAC/flac.pc.in")
	$(MOVE)

FLAC_CONF = \
	-DBUILD_TESTING=OFF \
	-DINSTALL_MANPAGES=OFF \
	-DBUILD_CXXLIBS=OFF \
	-DBUILD_EXAMPLES=OFF \
	-DBUILD_PROGRAMS=OFF

ifeq ($(ARCH),i386)
# nasm doesn't like the -fstack-protector-strong that's added to its flags
# let's prioritize the use of nasm over stack protection
FLAC_CONF += -DWITH_STACK_PROTECTOR=OFF
endif

ifdef HAVE_DARWIN_OS
# libSystem before 10.5 has no __stack_chk_fail/__stack_chk_guard
ifneq ($(call darwin_min_os_at_least, 10.5), true)
FLAC_CONF += -DWITH_STACK_PROTECTOR=OFF
endif
ifeq ($(ARCH),i386)
# the legacy cctools as cannot assemble the AVX2 intrinsics objects
FLAC_CONF += -DWITH_AVX=OFF
endif
endif

DEPS_flac = ogg $(DEPS_ogg)

.flac: flac toolchain.cmake
	$(CMAKECLEAN)
	$(HOSTVARS_CMAKE) $(CMAKE) $(FLAC_CONF)
	+$(CMAKEBUILD)
	$(CMAKEINSTALL)
	touch $@
