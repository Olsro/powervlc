# LIBAACS

AACS_VERSION := 0.11.1
AACS_URL := $(VIDEOLAN)/libaacs/$(AACS_VERSION)/libaacs-$(AACS_VERSION).tar.bz2

# libbluray never links against libaacs: it dlopen()s it at runtime under a
# plain name ("libaacs.dylib", "libaacs.dll", "libaacs.so.0" - see
# src/file/dl_posix.c and src/file/dl_win32.c in libbluray). Two consequences:
#
#  - this is the one contrib that must be built as a SHARED library, hence the
#    --enable-shared override below;
#  - it is built unconditionally, without the usual "system already has it"
#    shortcut (PKGS_FOUND). A system libaacs would satisfy the build host but
#    would not end up inside our bundle/installer, and AACS Blu-rays have to
#    play on machines that never heard of libaacs. See package.mak (macOS) and
#    extras/package/win32/package.mak, which copy the library next to the
#    player and fail the packaging step if it is missing.
#
# No key database is shipped: libaacs looks for the user's own KEYDB.cfg under
# <config dir>/aacs/ (see modules/demux/keydb.c, which offers to install one).
ifdef BUILD_DISCS
# Built for every slice, including the PowerPC and Intel-32 ones. It used not to
# be: the Darwin backend #included IOKit/storage/IOBDMediaBSDClient.h, which is
# absent from the 10.4u SDK, so the FSF GCC slices were gated out and every Mac
# that shipped with Tiger or Leopard PowerPC was left without AACS. No symbol
# from that header was ever used -- see
# libaacs-powervlc-tiger-and-external-mmc.patch, which drops the include, finds
# the drive under IODVDServices where Tiger has no Blu-ray storage family, and
# adds aacs_use_external_mmc() so the player can hand over the MMC channel it
# has to own on 10.4.
PKGS += aacs
endif

$(TARBALLS)/libaacs-$(AACS_VERSION).tar.bz2:
	$(call download_pkg,$(AACS_URL),libaacs)

.sum-aacs: libaacs-$(AACS_VERSION).tar.bz2

aacs: libaacs-$(AACS_VERSION).tar.bz2 .sum-aacs
	$(UNPACK)
ifdef HAVE_DARWIN_OS
	$(APPLY) $(SRC)/aacs/libaacs-powervlc-tiger-and-external-mmc.patch
ifneq ($(call darwin_min_os_at_least, 10.7), true)
	# The Darwin MMC backend needs libdispatch (10.6) and DASessionSetDispatchQueue
	# (10.7); rewritten on CFRunLoop + pthreads so it builds for a 10.5 target.
	# Only patched where it is actually needed: a slice deploying to 10.7 or later
	# keeps upstream's dispatch implementation untouched.
	$(APPLY) $(SRC)/aacs/libaacs-powervlc-no-libdispatch.patch
endif
endif
	$(UPDATE_AUTOCONFIG) && cd $(UNPACK_DIR) && mv config.guess config.sub build-aux
	$(MOVE)

DEPS_aacs = gcrypt $(DEPS_gcrypt)

# The keydb parser is generated at build time: libaacs' dist-hook deletes
# keydbcfg-{lexer,parser}.c, so flex and bison (or lex/yacc) are needed on the
# build machine. Both ship with Xcode's command line tools and with every
# distribution's build-essential; the generated code is host-independent, so
# cross builds use the build machine's copies.
#
# --disable-static --enable-shared comes after HOSTCONF, which asks for the
# opposite: last option wins with autoconf.
AACS_CONF := --disable-static --enable-shared

.aacs: aacs
	$(RECONF)
	cd $< && $(HOSTVARS_PIC) ./configure $(HOSTCONF) $(AACS_CONF)
	+$(MAKE) -C $< install
	touch $@
