# FFI
FFI_VERSION := 3.0.13
FFI_URL := https://www.sourceware.org/pub/libffi/libffi-$(FFI_VERSION).tar.gz

# 3.0.13 predates Windows on ARM and selects AArch64 ELF assembly, which the
# COFF llvm-mingw assembler rightly rejects. Keep the proven legacy version
# for old systems, but use the current pinned release for this new ABI.
ifeq ($(ARCH)-$(HAVE_WIN32),aarch64-1)
FFI_VERSION := 3.7.1
FFI_URL := https://github.com/libffi/libffi/releases/download/v$(FFI_VERSION)/libffi-$(FFI_VERSION).tar.gz
FFI_MODERN_WINDOWS_ARM := 1
endif

ifeq ($(call need_pkg,"libffi"),)
PKGS_FOUND += ffi
endif

$(TARBALLS)/libffi-$(FFI_VERSION).tar.gz:
	$(call download_pkg,$(FFI_URL),ffi)

.sum-ffi: libffi-$(FFI_VERSION).tar.gz

ffi: libffi-$(FFI_VERSION).tar.gz .sum-ffi
	$(UNPACK)
ifndef FFI_MODERN_WINDOWS_ARM
	$(APPLY) $(SRC)/ffi/powerpc-g3-machine.patch
	$(APPLY) $(SRC)/ffi/win64-pcrel-closure.patch
endif
	$(MOVE)

ifeq ($(ARCH)-$(HAVE_DARWIN_OS),aarch64-1)
# libffi 3.0.13 predates Darwin/arm64 and selects its ELF assembler there.
# The macOS SDK supplies libffi for native Apple Silicon builds; GLib's
# configure check links that system library directly, so no contrib archive
# is needed (or buildable) for this target.
.ffi: $(SRC)/ffi/libffi-darwin.pc.in
	mkdir -p $(PREFIX)/lib/pkgconfig
	sed -e 's|@PREFIX@|$(PREFIX)|g' -e 's|@SDK@|$(MACOSX_SDK)|g' \
		$< > $(PREFIX)/lib/pkgconfig/libffi.pc
	touch $@
else
.ffi: ffi
	$(RECONF)
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE)
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@
endif
