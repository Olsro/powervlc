# LIBBDPLUS

BDPLUS_VERSION := 0.2.0
BDPLUS_URL := $(VIDEOLAN)/libbdplus/$(BDPLUS_VERSION)/libbdplus-$(BDPLUS_VERSION).tar.bz2

# BD+ is the second copy-protection layer of Blu-ray, on top of AACS: the disc
# ships a small virtual machine program that unscrambles the video stream, and
# without it a BD+ title decrypts to garbage even when AACS succeeded.
#
# Everything said about libaacs in contrib/src/aacs applies here word for word.
# libbluray never links against libbdplus either: it dlopen()s it under a plain
# name ("libbdplus.dylib", "libbdplus.dll", "libbdplus.so.0" - see
# src/libbluray/disc/bdplus.c and src/file/dl_*.c in libbluray). So:
#
#  - this is the second contrib that must be built as a SHARED library, hence
#    the --enable-shared override below;
#  - it is built unconditionally, without the usual "system already has it"
#    shortcut (PKGS_FOUND): a system libbdplus satisfies the build host but
#    never ends up inside our bundle/installer.
#
# Unlike libaacs, a missing libbdplus is NOT a packaging error: AACS is what
# every retail disc uses, BD+ only some of them, and the player is perfectly
# usable without it. The packaging steps warn instead of failing.
#
# No VM is shipped: libbdplus looks for <config dir>/bdplus/vm0/ (see
# src/file/configfile.c, BDPLUS_DIR), which is $HOME/Library/Preferences on
# macOS, %APPDATA% on Windows and $XDG_CONFIG_HOME elsewhere -- the same parent
# directory libaacs reads KEYDB.cfg from. The Help menu of every interface
# opens that folder so the user can drop their own files in it.
ifdef BUILD_DISCS
PKGS += bdplus
endif

$(TARBALLS)/libbdplus-$(BDPLUS_VERSION).tar.bz2:
	$(call download_pkg,$(BDPLUS_URL),libbdplus)

.sum-bdplus: libbdplus-$(BDPLUS_VERSION).tar.bz2

bdplus: libbdplus-$(BDPLUS_VERSION).tar.bz2 .sum-bdplus
	$(UNPACK)
ifdef HAVE_DARWIN_OS
	$(APPLY) $(SRC)/bdplus/libbdplus-powervlc-darwin-feature-macros.patch
endif
	$(UPDATE_AUTOCONFIG) && cd $(UNPACK_DIR) && mv config.guess config.sub build-aux
	$(MOVE)

DEPS_bdplus = gcrypt $(DEPS_gcrypt)

# --without-libaacs: only the bdplus_test example uses libaacs, and it is a
# noinst_PROGRAM that `make install` still has to build and link. Asking for it
# would make this contrib depend on the build order of another one for a tool
# nothing ships.
#
# --disable-static --enable-shared comes after HOSTCONF, which asks for the
# opposite: last option wins with autoconf.
BDPLUS_CONF := --disable-static --enable-shared --without-libaacs

# noinst_PROGRAMS= drops the two examples (bdplus_test, convtab_dump). They are
# installed nowhere, yet `make install` still has to build them, and
# convtab_dump does not compile on Darwin: it names a local variable "index",
# which _DARWIN_C_SOURCE (see the patch above) turns into a redeclaration of
# index() from <strings.h>. The library itself is all we ship.
.bdplus: bdplus
	$(RECONF)
	cd $< && $(HOSTVARS_PIC) ./configure $(HOSTCONF) $(BDPLUS_CONF)
	+$(MAKE) -C $< install noinst_PROGRAMS=
	touch $@
