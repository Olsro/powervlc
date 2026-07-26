# HARFBUZZ

HARFBUZZ_VERSION := 11.5.0
HARFBUZZ_URL := $(GITHUB)/harfbuzz/harfbuzz/releases/download/$(HARFBUZZ_VERSION)/harfbuzz-$(HARFBUZZ_VERSION).tar.xz
PKGS += harfbuzz
ifeq ($(call need_pkg,"harfbuzz"),)
PKGS_FOUND += harfbuzz
endif

$(TARBALLS)/harfbuzz-$(HARFBUZZ_VERSION).tar.xz:
	$(call download_pkg,$(HARFBUZZ_URL),harfbuzz)

.sum-harfbuzz: harfbuzz-$(HARFBUZZ_VERSION).tar.xz

harfbuzz: harfbuzz-$(HARFBUZZ_VERSION).tar.xz .sum-harfbuzz
	$(UNPACK)
	$(MOVE)

DEPS_harfbuzz = freetype2 $(DEPS_freetype2)

HARFBUZZ_CONF := -Dfreetype=enabled \
	-Dglib=disabled \
	-Dgobject=disabled \
	-Ddocs=disabled \
	-Dtests=disabled

ifdef HAVE_DARWIN_OS
# CTFontManagerCreateFontDescriptorsFromURL requires Mac OS X 10.6
ifeq ($(call darwin_min_os_at_least, 10.6), true)
HARFBUZZ_CONF += -Dcoretext=enabled
else
HARFBUZZ_CONF += -Dcoretext=disabled
endif
endif

.harfbuzz: harfbuzz crossfile.meson
	$(MESONCLEAN)
	$(MESON) $(HARFBUZZ_CONF)
	+$(MESONBUILD)
	touch $@
