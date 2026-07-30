# LIBAACS

AACS_VERSION := 0.12.0
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

# The keydb lexer and parser no longer have to be generated here: up to 0.11.1
# libaacs' dist-hook deleted keydbcfg-{lexer,parser}.c from the tarball, which
# made flex and bison (or lex/yacc) a build requirement; 0.12.0 dropped that
# hook and ships them pre-generated, newer than the .l/.y they come from, so
# make leaves them alone. configure still probes for lex and yacc
# (AM_PROG_LEX / AC_PROG_YACC), it just no longer needs to find them -- and
# both ship with Xcode's command line tools anyway.
#
# $(RECONF) does gain a requirement in exchange: 0.12.0 prefers pkg-config over
# the bundled m4 macros for libgcrypt and gpg-error, and libaacs does not ship
# pkg.m4, so aclocal has to find the build machine's copy. It is there whenever
# pkg-config is, which every other contrib already needs.
#
# --disable-static --enable-shared comes after HOSTCONF, which asks for the
# opposite: last option wins with autoconf.
AACS_CONF := --disable-static --enable-shared

.aacs: aacs
	$(RECONF)
	cd $< && $(HOSTVARS_PIC) ./configure $(HOSTCONF) $(AACS_CONF)
	+$(MAKE) -C $< install
	touch $@
