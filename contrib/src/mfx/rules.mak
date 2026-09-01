# Legacy Intel Media SDK 1.x dispatcher. oneVPL deliberately removed MVC;
# Ivy Bridge/Haswell Windows drivers still expose it through this API.

MFX_VERSION := 1.35.1
MFX_URL := $(GITHUB)/lu-zero/mfx_dispatch/archive/refs/tags/$(MFX_VERSION).tar.gz

ifeq ($(call need_pkg,"mfx"),)
PKGS_FOUND += mfx
endif

ifdef HAVE_WIN32
ifeq ($(filter arm aarch64, $(ARCH)),)
PKGS += mfx
endif
endif

DEPS_mfx :=

$(TARBALLS)/mfx_dispatch-$(MFX_VERSION).tar.gz:
	$(call download_pkg,$(MFX_URL),mfx)

.sum-mfx: mfx_dispatch-$(MFX_VERSION).tar.gz

mfx: mfx_dispatch-$(MFX_VERSION).tar.gz .sum-mfx
	$(UNPACK)
	$(UPDATE_AUTOCONFIG)
	$(MOVE)

.mfx: mfx
	$(RECONF)
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE)
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@
