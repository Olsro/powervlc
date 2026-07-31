# librist

LIBRIST_VERSION := v0.2.18
LIBRIST_URL := $(VIDEOLAN_GIT)/rist/librist/-/archive/$(LIBRIST_VERSION)/librist-$(LIBRIST_VERSION).tar.gz

ifdef BUILD_NETWORK
ifdef HAVE_MACOSX
# librist uses strnlen()/clock APIs that only exist since Mac OS X 10.7;
# the legacy targets simply lose the (niche) RIST protocol
ifeq ($(call darwin_min_os_at_least, 10.7), true)
PKGS += librist
endif
else
PKGS += librist
endif
endif

DEPS_librist =
ifdef HAVE_WIN32
DEPS_librist += winpthreads $(DEPS_winpthreads)
endif

ifeq ($(call need_pkg,"librist >= 0.2"),)
PKGS_FOUND += librist
endif

LIBRIST_CONF = -Dbuilt_tools=false -Dtest=false
ifdef HAVE_WIN32
LIBRIST_CONF += -Dhave_mingw_pthreads=true
endif

$(TARBALLS)/librist-$(LIBRIST_VERSION).tar.gz:
	$(call download_pkg,$(LIBRIST_URL),librist)

.sum-librist: librist-$(LIBRIST_VERSION).tar.gz

librist: librist-$(LIBRIST_VERSION).tar.gz .sum-librist
	$(UNPACK)
	$(MOVE)

.librist: librist crossfile.meson
	$(MESONCLEAN)
	$(MESON) $(LIBRIST_CONF)
	+$(MESONBUILD)
	touch $@
