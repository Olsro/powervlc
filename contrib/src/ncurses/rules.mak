# ncurses

NCURSES_VERSION := 6.3
NCURSES_URL := $(GNU)/ncurses/ncurses-$(NCURSES_VERSION).tar.gz

ifdef HAVE_MACOSX
PKGS += ncurses
endif

ifeq ($(call need_pkg,"ncursesw"),)
PKGS_FOUND += ncurses
endif

$(TARBALLS)/ncurses-$(NCURSES_VERSION).tar.gz:
	$(call download_pkg,$(NCURSES_URL),ncurses)

.sum-ncurses: ncurses-$(NCURSES_VERSION).tar.gz

ncurses: ncurses-$(NCURSES_VERSION).tar.gz .sum-ncurses
	$(UNPACK)
	$(UPDATE_AUTOCONFIG)
	$(MOVE)

.ncurses: ncurses
	cd $< && mkdir -p "$(PREFIX)/lib/pkgconfig" && $(HOSTVARS) PKG_CONFIG_LIBDIR="$(PREFIX)/lib/pkgconfig" ./configure $(patsubst --datarootdir=%,,$(HOSTCONF)) --without-debug --enable-widec --without-develop --without-shared --with-terminfo-dirs=/usr/share/terminfo --with-pkg-config=yes --enable-pc-files --with-build-cc="$${CC_FOR_BUILD:-cc}" --with-build-cflags= --with-build-cppflags= --with-build-ldflags=
	cd $< && make -C ncurses -j1 && make -C ncurses install
	cd $< && make -C include -j1 && make -C include install
	cd $< && make -C misc pc-files && cp misc/ncursesw.pc "$(PREFIX)/lib/pkgconfig"
	touch $@
