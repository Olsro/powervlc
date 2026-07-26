# GnuTLS

GNUTLS_MAJVERSION := 3.8
GNUTLS_VERSION := $(GNUTLS_MAJVERSION).13
GNUTLS_URL := $(GNUGPG)/gnutls/v$(GNUTLS_MAJVERSION)/gnutls-$(GNUTLS_VERSION).tar.xz

# nettle/gmp can't be used with the LGPLv2 license
ifdef GPL
GNUTLS_PKG=1
else
ifdef GNUV3
GNUTLS_PKG=1
endif
endif

ifdef BUILD_NETWORK
ifndef HAVE_DARWIN_OS
ifdef GNUTLS_PKG
PKGS += gnutls
endif
endif
endif
ifeq ($(call need_pkg,"gnutls >= 3.3.6"),)
PKGS_FOUND += gnutls
endif

$(TARBALLS)/gnutls-$(GNUTLS_VERSION).tar.xz:
	$(call download_pkg,$(GNUTLS_URL),gnutls)

.sum-gnutls: gnutls-$(GNUTLS_VERSION).tar.xz

gnutls: gnutls-$(GNUTLS_VERSION).tar.xz .sum-gnutls
	$(UNPACK)
	$(UPDATE_AUTOCONFIG) && cd $(UNPACK_DIR) && mv config.guess config.sub build-aux
	# fix forbidden UWP call which can't be upstreamed as they won't
	# differentiate for winstore, only _WIN32_WINNT
	$(APPLY) $(SRC)/gnutls/0001-fcntl-do-not-call-GetHandleInformation-in-Winstore-a.patch

	# disable the dllimport in static linking (pkg-config --static doesn't handle Cflags.private)
	sed -i.orig -e s/"_SYM_EXPORT __declspec(dllimport)"/"_SYM_EXPORT"/g $(UNPACK_DIR)/lib/includes/gnutls/gnutls.h.in

	# disable __faccessat usage on Darwin as it's not available on our minimum target
	$(APPLY) $(SRC)/gnutls/__faccessat-darwin.patch

	# emulate _Thread_local with pthread keys when targeting Mac OS X < 10.7
	$(APPLY) $(SRC)/gnutls/0001-emulate-thread-local-with-pthread-keys-on-old-macOS.patch

	# replace HANDLE_FLAG_INHERIT which may not be available in older UWP
	sed -i.orig -e s/HANDLE_FLAG_INHERIT/0x1/g $(UNPACK_DIR)/gl/fcntl.c

	$(call pkg_static,"lib/gnutls.pc.in")

	# backport build fix for some Apple targets
	$(APPLY) $(SRC)/gnutls/0001-Fix-CRAU_MAYBE_UNUSED-definition-for-old-compilers.patch
	# use CreateFile2 in Win8 as CreateFileW is forbidden in UWP
	$(APPLY) $(SRC)/gnutls/0001-Use-CreateFile2-in-UWP-builds.patch

	$(MOVE)

GNUTLS_CONF := \
	--disable-gtk-doc \
	--without-p11-kit \
	--disable-cxx \
	--disable-srp-authentication \
	--disable-anon-authentication \
	--disable-openssl-compatibility \
	--disable-guile \
	--disable-nls \
	--without-libintl-prefix \
	--disable-doc \
	--disable-tools \
	--disable-tests \
	--with-included-libtasn1 \
	--with-included-unistring

DEPS_gnutls = nettle $(DEPS_nettle)
ifdef HAVE_WINSTORE
# gnulib uses GetFileInformationByHandle / SecureZeroMemory
DEPS_gnutls += alloweduwp $(DEPS_alloweduwp)
endif

ifdef HAVE_ANDROID
GNUTLS_ENV := gl_cv_header_working_stdint_h=yes
endif
ifdef HAVE_MACOSX
# strnlen() and memmem() are only available since macOS 10.7. Force the
# gnulib replacements and demote the availability diagnostic: the SDK
# declarations keep their 10.7 availability attribute even though the linked
# implementations are gnulib's. Without this the symbols are weak-linked,
# resolve to NULL on 10.6 and crash on the first TLS handshake.
ifneq ($(call darwin_min_os_at_least, 10.7), true)
GNUTLS_CONF += ac_cv_func_strnlen=no \
	ac_cv_func_memmem=no \
	CFLAGS="$(CFLAGS) $(WNO_PARTIAL_AVAILABILITY)"
endif
endif
ifdef HAVE_WIN32
	GNUTLS_CONF += --without-idn
ifeq ($(ARCH),aarch64)
	# Gnutls' aarch64 assembly unconditionally uses ELF specific directives
	GNUTLS_CONF += --disable-hardware-acceleration
endif
endif
ifdef HAVE_MACOSX
ifeq ($(ARCH),i386)
	# The x86 "accelerated" objects (AES-NI/PCLMUL) fail to assemble with
	# the legacy cctools as targeting Tiger, and no supported 32-bit Mac
	# has those instructions anyway (Core Duo / Core 2 Duo at best).
	GNUTLS_CONF += --disable-hardware-acceleration
endif
endif

.gnutls: gnutls
	$(MAKEBUILDDIR)
	$(GNUTLS_ENV) $(MAKECONFIGURE) $(GNUTLS_CONF)
	$(call pkg_static,"$(BUILD_DIRUNPACK)/lib/gnutls.pc")
	+$(MAKEBUILD) -C gl
	+$(MAKEBUILD) -C lib
	+$(MAKEBUILD) -C gl install
	+$(MAKEBUILD) -C lib install
	touch $@
