# Netatalk Client / libafpclient
AFPCLIENT_VERSION := 0.9.5
AFPCLIENT_URL := $(GITHUB)/Netatalk/netatalk-client/archive/refs/tags/$(AFPCLIENT_VERSION).tar.gz

ifdef BUILD_NETWORK
PKGS += afpclient
endif

ifeq ($(call need_pkg,"libafpclient >= 1.0.0"),)
PKGS_FOUND += afpclient
endif

DEPS_afpclient = gcrypt $(DEPS_gcrypt) iconv $(DEPS_iconv)
ifdef HAVE_WIN32
DEPS_afpclient += winpthreads
endif

AFPCLIENT_PATCHES := \
	$(SRC)/afpclient/0001-build-library-only.patch \
	$(SRC)/afpclient/0002-windows-compat.patch \
	$(SRC)/afpclient/0003-signal-loop-startup.patch \
	$(SRC)/afpclient/0004-jaguar-compat.patch \
	$(SRC)/afpclient/0005-meson-045-compat.patch \
	$(SRC)/afpclient/0006-short-reads-are-not-eof.patch \
	$(SRC)/afpclient/win32_compat.h

$(TARBALLS)/netatalk-client-$(AFPCLIENT_VERSION).tar.gz:
	$(call download_pkg,$(AFPCLIENT_URL),afpclient)

.sum-afpclient: netatalk-client-$(AFPCLIENT_VERSION).tar.gz

afpclient: netatalk-client-$(AFPCLIENT_VERSION).tar.gz .sum-afpclient \
	$(AFPCLIENT_PATCHES)
	$(UNPACK)
	$(APPLY) $(SRC)/afpclient/0001-build-library-only.patch
	$(APPLY) $(SRC)/afpclient/0002-windows-compat.patch
	$(APPLY) $(SRC)/afpclient/0003-signal-loop-startup.patch
	$(APPLY) $(SRC)/afpclient/0004-jaguar-compat.patch
	$(APPLY) $(SRC)/afpclient/0005-meson-045-compat.patch
	$(APPLY) $(SRC)/afpclient/0006-short-reads-are-not-eof.patch
	cp $(SRC)/afpclient/win32_compat.h $(UNPACK_DIR)/include/
	$(MOVE)

.afpclient: afpclient crossfile.meson $(AFPCLIENT_PATCHES) \
	$(SRC)/afpclient/rules.mak $(SRC)/main.mak
	$(REQUIRE_GPL)
	$(RM) -R afpclient
	+$(MAKE) afpclient
	$(MESONCLEAN)
	$(MESON) -Denable-tools=false -Denable-fuse=false -Denable-docs=false
	+# Ubuntu 18.04 ships Meson 0.45, whose CLI has neither
	+# `meson compile` nor `meson install`.  The generated Ninja targets are
	+# stable across both old and current Meson releases.
	+ninja -C $</build $(MESONCOMPILEFLAGS)
	+ninja -C $</build install
	touch $@
