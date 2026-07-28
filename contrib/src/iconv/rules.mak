# libiconv
LIBICONV_VERSION := 1.17
LIBICONV_URL := $(GNU)/libiconv/libiconv-$(LIBICONV_VERSION).tar.gz

PKGS += iconv
# iconv cannot be detect with pkg-config, but it is mandated by POSIX.
# Hard-code based on the operating system.
ifndef HAVE_WIN32
ifndef HAVE_ANDROID
ifdef HAVE_DARWIN_OS
# /usr/lib/libiconv.2.dylib only appears with Mac OS X 10.3 -- verified absent
# from a real 10.2.1 install, which ships no iconv at all. Below that
# deployment target the system cannot provide it, so build ours: otherwise
# every binary carries a load command dyld will not be able to satisfy.
ifeq ($(call darwin_min_os_at_least,10.3),true)
PKGS_FOUND += iconv
endif
else
PKGS_FOUND += iconv
endif
else
ifeq ($(shell expr "$(ANDROID_API)" '>=' '28'), 1)
PKGS_FOUND += iconv
endif
endif
endif

$(TARBALLS)/libiconv-$(LIBICONV_VERSION).tar.gz:
	$(call download_pkg,$(LIBICONV_URL),iconv)

.sum-iconv: libiconv-$(LIBICONV_VERSION).tar.gz

iconv: libiconv-$(LIBICONV_VERSION).tar.gz .sum-iconv
	$(UNPACK)
	$(UPDATE_AUTOCONFIG)
	$(APPLY) $(SRC)/iconv/bins.patch

	# use CreateFile2 instead of CreateFile in UWP
	$(APPLY) $(SRC)/iconv/0001-Use-CreateFile2-in-UWP-builds.patch

	# fix forbidden UWP call which can't be upstreamed as they won't
	# differentiate for winstore, only _WIN32_WINNT
	$(APPLY) $(SRC)/iconv/0001-do-not-call-GetHandleInformation-in-Winstore-apps.patch

	cd $(UNPACK_DIR) && cp config.guess config.sub build-aux \
	                 && mv config.guess config.sub libcharset/build-aux
	$(MOVE)

ICONV_CONF := --disable-nls

.iconv: iconv
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) $(ICONV_CONF)
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@
