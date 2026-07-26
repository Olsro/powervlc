# libdav1d

DAV1D_VERSION := 1.5.4
DAV1D_URL := $(VIDEOLAN)/dav1d/$(DAV1D_VERSION)/dav1d-$(DAV1D_VERSION).tar.xz

# aligned-allocation functions absent before Mac OS X 10.6 are worked
# around by 0001-mem-manual-aligned-alloc-fallback.patch
PKGS += dav1d
ifeq ($(call need_pkg,"dav1d"),)
PKGS_FOUND += dav1d
endif

DAV1D_CONF = -D enable_tests=false -D enable_tools=false

# dav1d's hand-written x86-32 assembly (SSSE3 angular intra predictors and
# likely other Mach-O/PIC code paths) is broken on Mac OS X i386: it computes
# wild pointers and crashes AV1 decode (SIGBUS/SIGSEGV, e.g. inside
# dav1d_ipred_z1_8bpc_ssse3). Fall back to the C DSP on the 32-bit Intel slice
# — slower but correct. The ppc/x86_64/arm64 slices keep their asm.
ifeq ($(ARCH),i386)
DAV1D_CONF += -D enable_asm=false
endif

$(TARBALLS)/dav1d-$(DAV1D_VERSION).tar.xz:
	$(call download_pkg,$(DAV1D_URL),dav1d)
#	$(call download_git,$(DAV1D_GITURL),,$(DAV1D_HASH))

.sum-dav1d: dav1d-$(DAV1D_VERSION).tar.xz

dav1d: dav1d-$(DAV1D_VERSION).tar.xz .sum-dav1d
	$(UNPACK)
	$(APPLY) $(SRC)/dav1d/0001-mem-manual-aligned-alloc-fallback.patch
	$(MOVE)

.dav1d: dav1d crossfile.meson
	$(MESONCLEAN)
	$(MESON) $(DAV1D_CONF)
	+$(MESONBUILD)
	touch $@
