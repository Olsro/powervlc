# libxml2

LIBXML2_VERSION := 2.15.3
LIBXML2_URL := https://download.gnome.org/sources/libxml2/2.15/libxml2-$(LIBXML2_VERSION).tar.xz

PKGS += libxml2
ifeq ($(call need_pkg,"libxml-2.0"),)
PKGS_FOUND += libxml2
endif

$(TARBALLS)/libxml2-$(LIBXML2_VERSION).tar.xz:
	$(call download_pkg,$(LIBXML2_URL),libxml2)

.sum-libxml2: libxml2-$(LIBXML2_VERSION).tar.xz

LIBXML2_CONF = \
        -DLIBXML2_WITH_C14N=OFF \
        -DLIBXML2_WITH_ISO8859X=OFF \
        -DLIBXML2_WITH_SCHEMAS=OFF \
        -DLIBXML2_WITH_SCHEMATRON=OFF \
        -DLIBXML2_WITH_VALID=OFF \
        -DLIBXML2_WITH_WRITER=OFF \
        -DLIBXML2_WITH_XINCLUDE=OFF \
        -DLIBXML2_WITH_XPATH=OFF \
        -DLIBXML2_WITH_XPTR=OFF \
        -DLIBXML2_WITH_MODULES=OFF \
        -DLIBXML2_WITH_ZLIB=OFF    \
        -DLIBXML2_WITH_ICONV=OFF   \
        -DLIBXML2_WITH_REGEXPS=OFF \
        -DLIBXML2_WITH_TESTS=OFF \
        -DLIBXML2_WITH_PROGRAMS=OFF

ifdef WITH_OPTIMIZATION
LIBXML2_CONF += -DLIBXML2_WITH_DEBUG=OFF
endif

libxml2: libxml2-$(LIBXML2_VERSION).tar.xz .sum-libxml2
	$(UNPACK)
	$(APPLY) $(SRC)/libxml2/0002-globals-don-t-use-destructor-in-UWP-builds.patch
ifdef HAVE_WIN32
ifeq ($(ARCH),i386)
	# xmlInitRandom() seeds its PRNG with BCryptGenRandom(), which lives in
	# bcrypt.dll -- the CNG API, introduced with Windows Vista. On XP the
	# library loader cannot resolve it, so EVERY plugin that links libxml2
	# fails to load: xml (and with it the media library, "XML reader not
	# found"), libbluray, and libass through fontconfig.
	#
	# This seed only randomises hash table iteration order to blunt hash
	# collision attacks; it is not used for anything cryptographic. libxml2
	# itself falls back to time + object addresses on systems without
	# getentropy(), so do the same here with two calls XP has had since 2001.
	perl -0pi -e 's/status = BCryptGenRandom\(.*?GetLastError\(\)\);/(void) status;\n        globalRngState[0] = (unsigned) GetTickCount() ^ (unsigned) ((size_t) &xmlInitRandom);\n        globalRngState[1] = (unsigned) GetCurrentProcessId() ^ (unsigned) ((size_t) &xmlRngMutex);/s' \
	    $(UNPACK_DIR)/dict.c
	# xmlInitParser() uses InitOnceExecuteOnce(), a Vista API, so libxml2 also
	# fails to load on XP for that second reason -- and it takes the xml
	# plugin (hence the media library), libbluray and libass with it.
	# INIT_ONCE is a pointer-sized union starting at zero, and libxml2 resets
	# it by copying a fresh INIT_ONCE_STATIC_INIT over it, so driving it as a
	# plain interlocked state word (0 idle, 1 running, 2 done) preserves both
	# the once semantics and that reset.
	perl -pi -e 's/^    InitOnceExecuteOnce\(&onceControl, xmlInitParserWinWrapper, NULL, NULL\);$$/    { LONG volatile *o = (LONG volatile *) \&onceControl; (void) xmlInitParserWinWrapper; if (InterlockedCompareExchange((LONG *) o, 1, 0) == 0) { xmlInitParserInternal(); InterlockedExchange((LONG *) o, 2); } else while (InterlockedCompareExchange((LONG *) o, 2, 2) != 2) Sleep(0); }/' \
	    $(UNPACK_DIR)/threads.c
endif
endif
	$(call pkg_static,"libxml-2.0.pc.in")
	$(MOVE)

.libxml2: libxml2 toolchain.cmake
	$(CMAKECLEAN)
	$(HOSTVARS_CMAKE) $(CMAKE) $(LIBXML2_CONF)
	+$(CMAKEBUILD)
	$(CMAKEINSTALL)
	touch $@
