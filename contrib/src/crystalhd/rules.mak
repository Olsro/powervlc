# CrystalHD: Broadcom BCM70012/BCM70015 hardware video decoder
#
# Win32 only needs the LGPL headers, since the module dlopens the Broadcom DLL
# shipped with the vendor driver.
#
# macOS has no vendor driver, so we build the whole userspace library from the
# crystalhd-for-osx sources and link it statically into the plugin. That keeps
# libcrystalhd.dylib out of /usr/lib: the only piece left to install is the
# kext, which cannot be avoided (no userspace PCIe access before macOS 10.15).

CRYSTAL_HEADERS_URL := http://www.broadcom.com/docs/support/crystalhd/crystalhd_lgpl_includes_v1.zip

CRYSTALHD_OSX_VERSION := a7b5062
CRYSTALHD_OSX_URL := $(CONTRIB_VIDEOLAN)/crystalhd/crystalhd-osx-$(CRYSTALHD_OSX_VERSION).tar.xz

ifdef HAVE_WIN32
PKGS += crystalhd
endif
ifdef HAVE_MACOSX
# The card is a mini-PCIe module: it only ever turns up in Intel Macs.
ifeq ($(ARCH),i386)
PKGS += crystalhd
endif
ifeq ($(ARCH),x86_64)
PKGS += crystalhd
endif
endif

ifdef HAVE_MACOSX

$(TARBALLS)/crystalhd-osx-$(CRYSTALHD_OSX_VERSION).tar.xz:
	$(call download_pkg,$(CRYSTALHD_OSX_URL),crystalhd)

CRYSTAL_SOURCES := crystalhd-osx-$(CRYSTALHD_OSX_VERSION).tar.xz

libcrystalhd: $(CRYSTAL_SOURCES) .sum-crystalhd
	$(UNPACK)
	$(APPLY) $(SRC)/crystalhd/0001-relocatable-firmware-path.patch
	$(APPLY) $(SRC)/crystalhd/0002-architecture-invariant-ioctl.patch
	$(APPLY) $(SRC)/crystalhd/0003-abi-token-lock.patch
	$(MOVE)

# -D__LINUX_USER__ selects the POSIX side of the Broadcom sources; the Darwin
# specifics sit behind __APPLE__ inside those same branches.
CRYSTALHD_CXXFLAGS := -D__LINUX_USER__ -Iinclude -Iinclude/link -Iinclude/flea
# bc_dts_glob_osx.h defines its own `inline int posix_memalign(...)` (malloc,
# Darwin already aligns on 16 bytes) right after including <stdlib.h>. In C++
# that is a redefinition of the SDK's declaration, so it inherits its
# API_AVAILABLE(macos(10.6)) and every call site trips
# -Werror=partial-availability on the 10.5 target -- even though the function
# being called is the shim, which is available everywhere. The i386 slice never
# showed it: the legacy GCC has no availability diagnostics at all, which is
# why libcrystalhd.a exists for i686-apple-darwin8 and has never once built for
# x86_64. The warning is about a declaration, not about the code that runs.
CRYSTALHD_CXXFLAGS += -Wno-error=unguarded-availability -Wno-unguarded-availability

.crystalhd: libcrystalhd
	cd $< && for f in darwin_lib/libcrystalhd/*.cpp; do \
		$(CXX) $(CXXFLAGS) $(CRYSTALHD_CXXFLAGS) -c "$$f" -o "$${f%.cpp}.o" || exit 1; \
	done
	cd $< && $(AR) rcs libcrystalhd.a darwin_lib/libcrystalhd/*.o && $(RANLIB) libcrystalhd.a
	mkdir -p "$(PREFIX)/lib" "$(PREFIX)/include/libcrystalhd" "$(PREFIX)/share/crystalhd"
	cp $</libcrystalhd.a "$(PREFIX)/lib/"
	cp $</darwin_lib/libcrystalhd/libcrystalhd_if.h "$(PREFIX)/include/libcrystalhd/"
	cp $</include/bc_dts_defs.h $</include/bc_dts_types.h \
	   $</include/libcrystalhd_version.h "$(PREFIX)/include/libcrystalhd/"
	# The blobs are pushed by the userspace library, not by the kext, so the
	# app can ship them in its own bundle and point at them at runtime.
	cp $</firmware/fwbin/70012/bcm70012fw.bin \
	   $</firmware/fwbin/70015/bcm70015fw.bin "$(PREFIX)/share/crystalhd/"
	# Kext sources travel with the library so both sides always agree on the
	# ioctl layout; they are built separately, against an SDK that modern
	# clang can no longer target.
	rm -Rf "$(PREFIX)/share/crystalhd/driver"
	cp -R $</driver "$(PREFIX)/share/crystalhd/driver"
	touch $@

else

$(TARBALLS)/crystalhd_lgpl_includes_v1.zip:
	$(call download_pkg,$(CRYSTAL_HEADERS_URL),crystalhd)

CRYSTAL_SOURCES := crystalhd_lgpl_includes_v1.zip

libcrystalhd: $(CRYSTAL_SOURCES) .sum-crystalhd
	$(RM) -R $(UNPACK_DIR) && unzip -o $< -d $(UNPACK_DIR)
	chmod -R u+w $(UNPACK_DIR)
	$(APPLY) $(SRC)/crystalhd/callback_proto.patch
ifdef HAVE_WIN32 # we want dlopening on win32
	rm -rf $(UNPACK_DIR)/bc_drv_if.h
endif
	$(MOVE)

.crystalhd: libcrystalhd
	rm -Rf "$(PREFIX)/include/libcrystalhd"
	cp -R $< "$(PREFIX)/include"
	touch $@

endif

# This package is the one contrib whose SHA512SUMS lists two MUTUALLY
# EXCLUSIVE tarballs: the Windows LGPL header zip and the macOS sources. The
# stock .sum-% recipe in main.mak checks the tarball it was asked for and then
# runs the checksummer over the WHOLE SUMS file, so a Windows build -- which
# has no reason to ever download the macOS tarball, its download rule being
# inside the HAVE_MACOSX branch -- died on "crystalhd-osx-*.tar.xz: FAILED
# open or read". Same the other way round on macOS. So check exactly the
# tarballs this platform pulled in, by feeding the checksummer only their
# lines. (The other multi-entry SUMS -- d3d11, d3d9, libcxx-legacy -- list
# files that are all fetched together, and stay on the stock recipe.)
.sum-crystalhd: $(CRYSTAL_SOURCES)
	$(foreach f,$(filter $(TARBALLS)/%,$^), \
		grep -- " $(f:$(TARBALLS)/%=%)$$" "$(SRC)/crystalhd/SHA512SUMS" \
		| (cd $(TARBALLS) && $(SHA512SUM) /dev/stdin) &&) \
	touch $@
