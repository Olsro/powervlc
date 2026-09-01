# UPNP
UPNP_VERSION := 1.14.31
UPNP_URL := $(GITHUB)/pupnp/pupnp/archive/refs/tags/release-$(UPNP_VERSION).tar.gz

# PowerVLC's extension-facing UPnP support is implemented in the core. pupnp
# remains an explicit contrib target for upstream compatibility, but is not a
# default network dependency and therefore cannot leak libupnp/libixml into
# normal macOS, Linux or Windows packages.

$(TARBALLS)/pupnp-release-$(UPNP_VERSION).tar.gz:
	$(call download_pkg,$(UPNP_URL),upnp)

.sum-upnp: pupnp-release-$(UPNP_VERSION).tar.gz

ifdef HAVE_WIN32
DEPS_upnp += winpthreads $(DEPS_winpthreads)
endif

UPNP_CONF := -DUPNP_BUILD_SHARED=OFF \
	-DBUILD_TESTING=OFF \
	-DUPNP_BUILD_SAMPLES=OFF

ifdef HAVE_IOS
UPNP_CONF += -DUPNP_ENABLE_IPV6=OFF -DUPNP_ENABLE_UNSPECIFIED_SERVER=ON \
 -DUPNP_MINISERVER_REUSEADDR=OFF
else
UPNP_CONF += -DUPNP_ENABLE_IPV6=ON
endif

ifdef HAVE_MACOSX
# strndup()/strnlen() are only available since macOS 10.7; preset the CMake
# cache so the checks report them missing and the built-in fallbacks are used
# (see the UpnpString compat patch)
ifneq ($(call darwin_min_os_at_least, 10.7), true)
UPNP_CONF += -DHAVE_STRNDUP:INTERNAL= -DHAVE_STRNLEN:INTERNAL=
endif
endif

upnp: pupnp-release-$(UPNP_VERSION).tar.gz .sum-upnp
	$(UNPACK)
ifdef HAVE_ANDROID
	$(APPLY) $(SRC)/upnp/revert-ifaddrs.patch
else
	# Avoid forcing `-lpthread` on android as it does not provide it and
	# identifies as 'Linux' in CMake.
	$(APPLY) $(SRC)/upnp/libtool-nostdlib-workaround.patch
endif
	$(APPLY) $(SRC)/upnp/miniserver.patch
ifdef HAVE_IOS
	$(APPLY) $(SRC)/upnp/fix-reuseaddr-option.patch
endif
	$(APPLY) $(SRC)/upnp/0001-Don-t-assume-strndup-to-be-missing-on-Windows.patch
	$(APPLY) $(SRC)/upnp/0001-Do-not-use-missing-OnLinkPrefixLength-when-compiling.patch
	$(APPLY) $(SRC)/upnp/0001-UpnpString-compat-strndup-strnlen-for-old-macOS.patch
ifdef HAVE_WIN32
ifeq ($(ARCH),i386)
	# pupnp takes the "secure CRT" spelling of a handful of calls whenever
	# _WIN32 is defined, but those entry points only reached msvcrt.dll with
	# Windows Vista: on XP SP3 -- the floor of the win32 slice -- the plugin
	# fails to load outright. Every one of these has a plain equivalent right
	# next to it in the #else branch, and none of the sscanf() formats uses
	# %s or %c, so the size arguments the _s forms carry are not needed.
	cd $(UNPACK_DIR) && sed -i.orig \
	    -e 's/sscanf_s(/sscanf(/g' \
	    -e 's/fopen_s(&\([A-Za-z_][A-Za-z0-9_]*\), \(.*\));/\1 = fopen(\2);/' \
	    upnp/src/genlib/net/http/webserver.c \
	    upnp/src/genlib/net/http/httpparser.c \
	    upnp/src/genlib/net/http/httpreadwrite.c \
	    upnp/src/genlib/net/uri/uri.c \
	    upnp/src/api/upnpapi.c \
	    upnp/src/api/upnpdebug.c \
	    ixml/src/ixmlparser.c
	# wcstombs_s() spans several lines; its first argument only receives the
	# converted length, which pupnp discards anyway (it frees a NULL pointer).
	cd $(UNPACK_DIR) && perl -0pi -e \
	    's/wcstombs_s\(\s*s\s*,\s*([^,]+),\s*sizeof\([^)]*\),\s*([^,]+),\s*(sizeof\([^)]*\))\);/wcstombs($$1, $$2, $$3);/gs' \
	    upnp/src/api/upnpapi.c
endif
endif
	$(MOVE)

.upnp: upnp toolchain.cmake
	$(CMAKECLEAN)
	$(HOSTVARS_CMAKE) $(CMAKE) $(UPNP_CONF)
	+$(CMAKEBUILD)
	+$(CMAKEINSTALL)
	touch $@
