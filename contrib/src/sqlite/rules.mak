# SQLite

SQLITE_VERSION := 3450200
SQLITE_URL := https://www.sqlite.org/2024/sqlite-autoconf-$(SQLITE_VERSION).tar.gz

PKGS += sqlite
ifeq ($(call need_pkg,"sqlite3"),)
PKGS_FOUND += sqlite
endif

$(TARBALLS)/sqlite-autoconf-$(SQLITE_VERSION).tar.gz:
	$(call download_pkg,$(SQLITE_URL),sqlite)

.sum-sqlite: sqlite-autoconf-$(SQLITE_VERSION).tar.gz

sqlite: sqlite-autoconf-$(SQLITE_VERSION).tar.gz .sum-sqlite
	$(UNPACK)
	$(MOVE)

.sqlite: sqlite
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) --disable-readline --disable-dynamic-extensions
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@
