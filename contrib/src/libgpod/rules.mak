# libgpod — Apple iPod iTunesDB access

LIBGPOD_VERSION := 0.8.3
LIBGPOD_URL := https://downloads.sourceforge.net/project/gtkpod/libgpod/libgpod-0.8/libgpod-$(LIBGPOD_VERSION).tar.bz2
HASHAB_HASH := f80d46432204c6238cad7d8ca3b3dd52ea66836b
HASHAB_GITURL := https://github.com/dstaley/hashab.git

PKGS += libgpod
ifeq ($(call need_pkg,"libgpod-1.0 >= 0.8.3"),)
PKGS_FOUND += libgpod
endif

DEPS_libgpod = glib sqlite libplist libxml2 \
	$(DEPS_glib) $(DEPS_sqlite) $(DEPS_libplist) $(DEPS_libxml2)

# These APIs are provided by the bundled GLib. libgpod's old configure script
# probes them without the GLib link flags when cross-compiling.
LIBGPOD_CONF := ac_cv_func_g_int64_hash=yes ac_cv_func_g_int64_equal=yes \
	ac_cv_func_g_checksum_reset=yes ac_cv_func_g_mapped_file_unref=yes

$(TARBALLS)/libgpod-$(LIBGPOD_VERSION).tar.bz2:
	$(call download_pkg,$(LIBGPOD_URL),libgpod)

$(TARBALLS)/hashab-$(HASHAB_HASH).tar.xz:
	$(call download_git,$(HASHAB_GITURL),,$(HASHAB_HASH))

.sum-hashab: hashab-$(HASHAB_HASH).tar.xz
	$(call check_githash,$(HASHAB_HASH))
	touch $@

.sum-libgpod: libgpod-$(LIBGPOD_VERSION).tar.bz2 .sum-hashab
	$(CHECK_SHA512)
	touch $@

libgpod: libgpod-$(LIBGPOD_VERSION).tar.bz2 hashab-$(HASHAB_HASH).tar.xz .sum-libgpod
	$(UNPACK)
	mkdir -p $(UNPACK_DIR)/src/hashab
	cp hashab-$(HASHAB_HASH)/src/*.c hashab-$(HASHAB_HASH)/src/*.h \
		$(UNPACK_DIR)/src/hashab/
	cp hashab-$(HASHAB_HASH)/LICENSE $(UNPACK_DIR)/src/hashab/LICENSE
	$(RM) -R hashab-$(HASHAB_HASH)
	$(APPLY) $(SRC)/libgpod/disable-intltool-without-nls.patch
	$(APPLY) $(SRC)/libgpod/library-only.patch
	$(APPLY) $(SRC)/libgpod/embed-native-hashab.patch
	$(MOVE)

.libgpod: libgpod .glib .sqlite .libplist .libxml2
	$(MAKEBUILDDIR)
	CFLAGS="$(CFLAGS) -fwrapv" $(MAKECONFIGURE) \
		--disable-udev --without-libimobiledevice \
		--disable-gdk-pixbuf --disable-libxml --disable-gtk-doc \
		--without-python --without-mono --disable-more-warnings \
		--disable-nls $(LIBGPOD_CONF)
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@
