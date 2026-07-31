# ASS
ASS_VERSION := 0.17.5
ASS_URL := $(GITHUB)/libass/libass/releases/download/$(ASS_VERSION)/libass-$(ASS_VERSION).tar.xz

PKGS += ass
ifeq ($(call need_pkg,"libass"),)
PKGS_FOUND += ass
endif

ifdef HAVE_ANDROID
WITH_FONTCONFIG = 1
else
ifdef HAVE_TIZEN
WITH_FONTCONFIG = 0
WITH_HARFBUZZ = 0
else
ifdef HAVE_DARWIN_OS
# Was 0 while the contrib was stuck on fontconfig 2.12.3, which aborts on a
# current macOS (see contrib/src/fontconfig). With 2.16.0 libass can use the
# system fonts here like it does everywhere else, instead of falling back to
# whatever the subtitle track happens to embed.
WITH_FONTCONFIG = 1
# CoreText only exists since Mac OS X 10.5 (and libass' provider uses
# 10.6-era APIs); the legacy 10.4-and-earlier slices must not compile it.
ifeq ($(call darwin_min_os_at_least, 10.6), true)
WITH_CORETEXT = 1
endif
else
ifdef HAVE_WINSTORE
WITH_FONTCONFIG = 0
WITH_DWRITE = 1
else
WITH_FONTCONFIG = 1
endif
endif
endif
endif

$(TARBALLS)/libass-$(ASS_VERSION).tar.xz:
	$(call download_pkg,$(ASS_URL),ass)

.sum-ass: libass-$(ASS_VERSION).tar.xz

libass: libass-$(ASS_VERSION).tar.xz .sum-ass
	$(UNPACK)
	$(UPDATE_AUTOCONFIG)
	$(call pkg_static,"libass.pc.in")
	$(MOVE)

DEPS_ass = freetype2 $(DEPS_freetype2) fribidi $(DEPS_fribidi) iconv $(DEPS_iconv) harfbuzz $(DEPS_harfbuzz)

ASS_CONF = --disable-test
ifneq ($(WITH_FONTCONFIG), 0)
DEPS_ass += fontconfig $(DEPS_fontconfig)
else
ASS_CONF += --disable-fontconfig --disable-require-system-font-provider
endif

ifeq ($(WITH_DWRITE), 1)
ASS_CONF += --enable-directwrite
endif

ifeq ($(WITH_CORETEXT), 1)
ASS_CONF += --enable-coretext
endif

ifeq ($(WITH_ASS_ASM), 0)
ASS_CONF += --disable-asm
endif

.ass: libass
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) $(ASS_CONF)
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@
