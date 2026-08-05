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

.sum-crystalhd: $(CRYSTAL_SOURCES)

libcrystalhd: $(CRYSTAL_SOURCES) .sum-crystalhd
	$(UNPACK)
	$(APPLY) $(SRC)/crystalhd/0001-relocatable-firmware-path.patch
	$(APPLY) $(SRC)/crystalhd/0002-architecture-invariant-ioctl.patch
	$(APPLY) $(SRC)/crystalhd/0003-abi-token-lock.patch
	$(MOVE)

# -D__LINUX_USER__ selects the POSIX side of the Broadcom sources; the Darwin
# specifics sit behind __APPLE__ inside those same branches.
CRYSTALHD_CXXFLAGS := -D__LINUX_USER__ -Iinclude -Iinclude/link -Iinclude/flea

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

.sum-crystalhd: $(CRYSTAL_SOURCES)

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
