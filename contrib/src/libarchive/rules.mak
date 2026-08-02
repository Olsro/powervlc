# LIBARCHIVE
LIBARCHIVE_VERSION := 3.8.8
LIBARCHIVE_URL := $(GITHUB)/libarchive/libarchive/releases/download/v$(LIBARCHIVE_VERSION)/libarchive-$(LIBARCHIVE_VERSION).tar.xz

PKGS += libarchive
ifeq ($(call need_pkg,"libarchive >= 3.2.0"),)
PKGS_FOUND += libarchive
endif

DEPS_libarchive = zlib $(DEPS_zlib)

LIBARCHIVE_CONF := \
		-DENABLE_CPIO=OFF -DENABLE_TAR=OFF -DENABLE_CAT=OFF \
		-DENABLE_LIBXML2=OFF -DENABLE_LZMA=OFF -DENABLE_ICONV=OFF -DENABLE_EXPAT=OFF \
		-DENABLE_TEST=OFF -DENABLE_WERROR=OFF \
		-DENABLE_LIBB2=OFF -DENABLE_LZ4=OFF -DENABLE_LZO=OFF -DENABLE_ZSTD=OFF
# ^ find_library() is not confined to the contrib prefix, so a host (Homebrew)
# libb2/lz4/lzo/zstd would be picked up and recorded in libarchive.pc (-lb2 and
# -lzstd leaked into every consumer on macOS); none is needed for VLC's use.

# CNG enables bcrypt on Windows and useless otherwise, it's not used when building for XP
# ... except that nothing actually made that true: ENABLE_CNG was set
# unconditionally, libarchive imported thirteen BCrypt* entry points, and
# bcrypt.dll only exists from Windows Vista on -- so the stream_extractor
# plugin failed to load outright on XP, which is precisely the target the
# comment above says it is not used for. Honour it for the win32 slice.
LIBARCHIVE_CNG = ON
ifdef HAVE_WIN32
ifeq ($(ARCH),i386)
LIBARCHIVE_CNG = OFF
# _mkgmtime() resolves to _mkgmtime32() or _mkgmtime64() through mingw's
# time.h, and BOTH suffixed spellings only exist in the msvcrt.dll of Windows
# Vista -- XP has just the unsuffixed _mkgmtime, which the header will never
# emit. Unset the probe so libarchive uses the timegm() it computes from first
# principles right below, which needs nothing from the CRT.
LIBARCHIVE_CONF +=-DHAVE__MKGMTIME:INTERNAL=
endif
endif
LIBARCHIVE_CONF +=-DENABLE_CNG=$(LIBARCHIVE_CNG)

# bsdunzip doesn't build on macos, android and emscripten and it's disabled on Windows
LIBARCHIVE_CONF +=-DENABLE_UNZIP=OFF

ifdef HAVE_MACOSX
# these functions are detected as present but there are not until macOS 10.10
# the minimum supported value is 10.7, in each case missing the functions falls
# back to an alternative
LIBARCHIVE_CONF += -DHAVE_FDOPENDIR:INTERNAL= -DHAVE_OPENAT:INTERNAL= -DHAVE_FSTATAT:INTERNAL= -DHAVE_LINKAT:INTERNAL=

# these are only available since macOS 10.7; missing them falls back to an
# alternative as well
ifneq ($(call darwin_min_os_at_least, 10.7), true)
LIBARCHIVE_CONF += -DHAVE_STRNLEN:INTERNAL= -DHAVE_ARC4RANDOM_BUF:INTERNAL=
endif
endif

$(TARBALLS)/libarchive-$(LIBARCHIVE_VERSION).tar.xz:
	$(call download_pkg,$(LIBARCHIVE_URL),libarchive)

.sum-libarchive: libarchive-$(LIBARCHIVE_VERSION).tar.xz

libarchive: libarchive-$(LIBARCHIVE_VERSION).tar.xz .sum-libarchive
	$(UNPACK)
	$(APPLY) $(SRC)/libarchive/0001-zstd-use-GetNativeSystemInfo-to-get-the-number-of-th.patch
	# Do not use WINAPI_PARTITION_SYSTEM, It's not handled properly by the mingw64 macro
	sed -i.orig 's, | WINAPI_PARTITION_SYSTEM,,' $(UNPACK_DIR)/libarchive/archive_write_disk_windows.c
	# don't use CreateHardLinkW on old UWP
	$(APPLY) $(SRC)/libarchive/0001-Disable-CreateHardLinkW-usage-on-old-UWP-targets.patch
	$(APPLY) $(SRC)/libarchive/0003-Use-VirtualAllocFromApp-for-old-UWP-targets.patch
	$(APPLY) $(SRC)/libarchive/0001-cryptor-require-deployment-target-10.7-for-CommonCrypto.patch
ifdef HAVE_WIN32
ifeq ($(ARCH),i386)
	# _wsopen_s() is a "secure CRT" function: it only reached msvcrt.dll with
	# Windows Vista, and the win32 slice targets XP SP3, where a DLL importing
	# it cannot be loaded at all. _wsopen() is the pre-Vista spelling and
	# already defaults to the _SH_DENYNO sharing mode asked for here.
	sed -i.orig -e 's/_wsopen_s(&r, ws, flags, _SH_DENYNO, pmode);/r = _wsopen(ws, flags, pmode);/' \
	    -e 's/_wsopen_s(&r, path, flags, _SH_DENYNO, pmode);/r = _wsopen(path, flags, pmode);/' \
	    $(UNPACK_DIR)/libarchive/archive_windows.c
	# ENABLE_CNG=OFF is not enough: _archive_mktempx() calls BCrypt with no
	# guard at all, so libarchive pulls in bcrypt.dll (Vista and later) on
	# any Windows build. The bytes only pick the characters of a temporary
	# file name, and the surrounding loop already retries until CreateFile
	# succeeds, so a seeded rand() is adequate here -- this is not a
	# security boundary, unlike the CNG code paths that ENABLE_CNG=OFF drops.
	cd $(UNPACK_DIR) && perl -0pi \
	    -e 's/if \(!BCRYPT_SUCCESS\(BCryptOpenAlgorithmProvider.*?\}\n/srand((unsigned) GetTickCount() ^ (unsigned) GetCurrentProcessId());\n/s;' \
	    -e 's/if \(!BCRYPT_SUCCESS\(BCryptGenRandom.*?\}\n/{ wchar_t *q; for (q = p; q < ep; q++) *q = (wchar_t) rand(); }\n/s;' \
	    -e 's/if \(hAlg != NULL\)\s*\n\s*BCryptCloseAlgorithmProvider\(hAlg, 0\);\n//s;' \
	    libarchive/archive_util.c
	# mingw-w64 makes time_t 64-bit by default, which routes localtime(),
	# mktime() and _mkgmtime() to their _*64 spellings. Those three are
	# missing from the msvcrt.dll of Windows XP -- unlike _fstat64/_stat64,
	# which is why avcodec, flac and mkv load there and libarchive does not.
	# archive_platform.h is included first by every libarchive source, so
	# asking for a 32-bit time_t here covers the whole library. VLC's
	# stream_extractor/archive.c uses no libarchive time API, so the narrower
	# time_t never crosses the plugin boundary.
	perl -pi -e 's/^(#define\s+ARCHIVE_PLATFORM_H_INCLUDED)$$/$$1\n\n\/* PowerVLC: XP msvcrt has no _localtime64\/_mktime64\/_mkgmtime64 *\/\n#define _USE_32BIT_TIME_T 1/' \
	    $(UNPACK_DIR)/libarchive/archive_platform.h
endif
endif
	$(call pkg_static,"build/pkgconfig/libarchive.pc.in")
	$(MOVE)

.libarchive: libarchive toolchain.cmake
	$(CMAKECLEAN)
	$(HOSTVARS_CMAKE) $(CMAKE) $(LIBARCHIVE_CONF)
	+$(CMAKEBUILD)
	$(CMAKEINSTALL)
	touch $@
