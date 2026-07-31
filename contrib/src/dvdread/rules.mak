# DVDREAD
LIBDVDREAD_VERSION := 7.1.1
LIBDVDREAD_URL := $(VIDEOLAN)/libdvdread/$(LIBDVDREAD_VERSION)/libdvdread-$(LIBDVDREAD_VERSION).tar.xz

ifdef BUILD_DISCS
ifdef GPL
PKGS += dvdread
endif
endif
ifeq ($(call need_pkg,"dvdread >= 6.1.0"),)
PKGS_FOUND += dvdread
endif

$(TARBALLS)/libdvdread-$(LIBDVDREAD_VERSION).tar.xz:
	$(call download,$(LIBDVDREAD_URL))

.sum-dvdread: libdvdread-$(LIBDVDREAD_VERSION).tar.xz

dvdread: libdvdread-$(LIBDVDREAD_VERSION).tar.xz .sum-dvdread
	$(UNPACK)
	# PowerVLC: realpath(path, NULL) is POSIX 2008, only supported since
	# Mac OS X 10.6 -- Tiger writes through the NULL argument and crashes
	$(APPLY) $(SRC)/dvdread/0003-dvd_reader-no-realpath-null-on-old-darwin.patch
	$(MOVE)

DEPS_dvdread = dvdcss $(DEPS_dvdcss)

DVDREAD_CONF := -Dlibdvdcss=enabled

.dvdread: dvdread .dvdcss crossfile.meson
	$(REQUIRE_GPL)
	$(MESONCLEAN)
	$(MESON) $(DVDREAD_CONF)
	+$(MESONBUILD)
	touch $@
