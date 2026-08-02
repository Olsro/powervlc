# fontconfig

FONTCONFIG_VERSION := 2.16.0
FONTCONFIG_URL := https://www.freedesktop.org/software/fontconfig/release/fontconfig-$(FONTCONFIG_VERSION).tar.xz

# Raised from 2.12.3 (2017) because BD-J menus need it and that version could
# not be switched on: on macOS 15 it aborted while building its font cache,
#   FcInitLoadConfigAndFonts -> FcConfigBuildFonts -> FcDirCacheScan
#     -> FcDirCacheBuild -> FcCacheInsert -> SIGABRT near NULL
# taking the whole player with it. 2.16.0 rewrote that path, and its fallback
# configuration (src/fcinit.c, FcInitFallbackConfig) now names a second,
# XDG-based cache directory alongside the compiled-in one, so a cache
# directory that cannot be used is no longer fatal.

PKGS += fontconfig
ifeq ($(call need_pkg,"fontconfig >= 2.11"),)
PKGS_FOUND += fontconfig
endif

$(TARBALLS)/fontconfig-$(FONTCONFIG_VERSION).tar.xz:
	$(call download_pkg,$(FONTCONFIG_URL),fontconfig)

.sum-fontconfig: fontconfig-$(FONTCONFIG_VERSION).tar.xz

# The two Windows patches this contrib used to carry are gone: both were
# fixed upstream and neither applies to 2.16.0 any more.
#   - fontconfig-win32.patch redirected the fallback cache directory to
#     %APPDATA%\vlc because FcInitFallbackConfig() hardcoded FC_CACHEDIR.
#     2.16.0 resolves the Windows local-appdata path itself (the
#     SHGetFolderPathA calls in src/fcxml.c) and the fallback config lists an
#     xdg-prefixed cachedir as well.
#   - fontconfig-noxml2.patch #if 0'd most of the includes of src/fcxml.c to
#     work around a mingw build failure that no longer occurs.
# ⚠ The Windows contribs have NOT been rebuilt against 2.16.0 -- that tree is
# separate. Revalidate there before shipping a Windows build.
fontconfig: fontconfig-$(FONTCONFIG_VERSION).tar.xz .sum-fontconfig
	$(UNPACK)
	$(UPDATE_AUTOCONFIG)
	$(call pkg_static, "fontconfig.pc.in")
	$(MOVE)

FONTCONFIG_CONF := --enable-libxml2 --disable-docs
FONTCONFIG_ENV := $(HOSTVARS)

# 2.16.0 finds freetype and libxml2 through pkg-config
# (PKG_CHECK_MODULES(FREETYPE, freetype2 >= 21.0.15) and
# PKG_CHECK_MODULES([LIBXML2], [libxml-2.0 >= 2.6])), so the old
# --with-freetype-config and the xml2-config environment overrides are gone:
# the option no longer exists and both .pc files are in the contrib prefix.

ifdef HAVE_CROSS_COMPILE
FONTCONFIG_CONF += --with-arch=$(ARCH)
endif

ifdef HAVE_WIN32
# configure turns NLS on as soon as it finds the libintl contrib, and every
# fontconfig source then pulls in <libintl.h>, which redefines fprintf and
# printf to libintl_fprintf / __printf__. fontconfig.pc carries no -lintl, so
# every static consumer -- libass, and VLC through it -- fails to link with a
# wall of undefined references to those two symbols. Nothing in VLC ever shows
# fontconfig's own messages, so the translations are pure liability here.
#
# Windows only on purpose: the macOS prefixes link fine as they are, and
# changing this globally would force a fontconfig rebuild in all seven of them
# for no gain.
FONTCONFIG_CONF += --disable-nls
endif

ifdef HAVE_MACOSX
# These are absolute paths that exist on every Mac from 10.2 on, and they are
# what makes lookups work without a fonts.conf being shipped in the bundle:
# they are compiled into the fallback configuration.
#
# --with-confdir is not passed any more -- 2.16.0 removed it (it split into
# --with-baseconfigdir and --with-configdir). It used to say
# /usr/X11/lib/X11/fonts, which was not a configuration directory at all, so
# nothing is lost by dropping it.
FONTCONFIG_CONF += \
	--with-cache-dir=~/Library/Caches/fontconfig \
	--with-default-fonts=/System/Library/Fonts \
	--with-add-fonts=/Library/Fonts,~/Library/Fonts
endif

ifdef HAVE_ANDROID
FONTCONFIG_CONF += \
	--with-cache-dir=~/.cache/fontconfig \
	--with-default-fonts=/system/fonts \
	--with-add-fonts=/product/fonts,/data/fonts
endif

DEPS_fontconfig = freetype2 $(DEPS_freetype2) libxml2 $(DEPS_libxml2)

# No RECONF anywhere any more (it used to run on win32 only, for the two
# Windows patches above): 2.16.0's shipped configure works as-is, and an
# autoreconf would regenerate the po/ infrastructure against whatever gettext
# macros happen to sit in the contrib prefix — "gettext infrastructure
# mismatch" when they differ from the one the tarball was rolled with.
.fontconfig: fontconfig
	cd $< && $(FONTCONFIG_ENV) ./configure $(HOSTCONF) $(FONTCONFIG_CONF)
	$(MAKE) -C $<
ifndef HAVE_MACOSX
	$(MAKE) -C $< install
else
# Not a plain "make install": install-data-local runs fc-cache on the build
# machine, which is meaningless here and fails outright when cross-compiling.
	$(MAKE) -C $< install-exec
	$(MAKE) -C $< -C fontconfig
	$(MAKE) -C $< -C fontconfig install-data
	sed -e 's%/usr/lib/libiconv.la%%' -i.orig $(PREFIX)/lib/libfontconfig.la
	cp $</fontconfig.pc $(PREFIX)/lib/pkgconfig/
endif
	touch $@
