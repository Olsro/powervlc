# libplist (the stable API expected by libgpod 0.8.x)

LIBPLIST_VERSION := 1.12
LIBPLIST_URL := https://github.com/libimobiledevice/libplist/archive/refs/tags/$(LIBPLIST_VERSION).tar.gz

PKGS += libplist
ifeq ($(call need_pkg,"libplist >= 1.0"),)
PKGS_FOUND += libplist
endif

DEPS_libplist = libxml2 $(DEPS_libxml2)

$(TARBALLS)/libplist-$(LIBPLIST_VERSION).tar.gz:
	$(call download_pkg,$(LIBPLIST_URL),libplist)

.sum-libplist: libplist-$(LIBPLIST_VERSION).tar.gz

libplist: libplist-$(LIBPLIST_VERSION).tar.gz .sum-libplist \
	$(wildcard $(SRC)/libplist/*.patch)
	$(UNPACK)
	$(APPLY) $(SRC)/libplist/static-windows.patch
	$(MOVE)

.libplist: libplist .libxml2
	$(RECONF)
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) --without-cython
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@
