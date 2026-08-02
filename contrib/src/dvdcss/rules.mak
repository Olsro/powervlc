# DVDCSS
DVDCSS_VERSION := 1.6.0
DVDCSS_URL := $(VIDEOLAN)/libdvdcss/$(DVDCSS_VERSION)/libdvdcss-$(DVDCSS_VERSION).tar.xz

ifeq ($(call need_pkg,"libdvdcss"),)
PKGS_FOUND += dvdcss
endif

$(TARBALLS)/libdvdcss-$(DVDCSS_VERSION).tar.xz:
	$(call download,$(DVDCSS_URL))

.sum-dvdcss: libdvdcss-$(DVDCSS_VERSION).tar.xz

dvdcss: libdvdcss-$(DVDCSS_VERSION).tar.xz .sum-dvdcss
	$(UNPACK)
	$(MOVE)

.dvdcss: dvdcss crossfile.meson
	$(REQUIRE_GPL)
	$(MESONCLEAN)
	$(MESON)
	+$(MESONBUILD)
	touch $@
