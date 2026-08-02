# winpthreads, dxvahd

MINGW64_VERSION := 14.0.0
MINGW64_URL := $(SF)/mingw-w64/mingw-w64/mingw-w64-release/mingw-w64-v$(MINGW64_VERSION).tar.bz2
# MINGW64_HASH=2c35e8ff0d33916bd490e8932cba2049cd1af3d0
# MINGW64_GITURL := https://git.code.sf.net/p/mingw-w64/mingw-w64

ifdef HAVE_WIN32
PKGS += winpthreads

ifndef HAVE_VISUALSTUDIO
ifdef HAVE_WINSTORE
PKGS += alloweduwp
endif
PKGS += dxva dxvahd mingw11-fixes mingw12-fixes mft10
ifeq ($(ARCH),i386)
PKGS += dxva_x86
endif

ifeq ($(call mingw_at_least, 10), true)
PKGS_FOUND += dxva mft10
endif # MINGW 10
ifeq ($(call mingw_at_least, 11), true)
PKGS_FOUND +=
endif # MINGW 11
ifeq ($(call mingw_at_least, 12), true)
PKGS_FOUND += mingw11-fixes
endif # MINGW 12
ifeq ($(call mingw_at_least, 13), true)
PKGS_FOUND += mingw12-fixes dxvahd alloweduwp
ifeq ($(ARCH),i386)
PKGS_FOUND += dxva_x86
endif
endif # MINGW 13
endif # !HAVE_VISUALSTUDIO

ifdef HAVE_WINSTORE
# force rebuild of winpthread as pthread_setname_np may be broken, it's OK to use when targeting UWP (Win10)
HAVE_WINPTHREAD := $(shell $(CC) $(CFLAGS) -E -dM -include pthread.h - < /dev/null >/dev/null 2>&1 || echo FAIL)
ifeq ($(HAVE_WINPTHREAD),)
PKGS_FOUND += winpthreads
endif
endif

endif # HAVE_WIN32

PKGS_ALL += winpthreads dxva dxvahd dxva_x86 mingw11-fixes mingw12-fixes alloweduwp mft10

# $(TARBALLS)/mingw-w64-$(MINGW64_HASH).tar.xz:
# 	$(call download_git,$(MINGW64_GITURL),,$(MINGW64_HASH))

$(TARBALLS)/mingw-w64-v$(MINGW64_VERSION).tar.bz2:
	$(call download_pkg,$(MINGW64_URL),winpthreads)

.sum-mingw64: mingw-w64-v$(MINGW64_VERSION).tar.bz2
# .sum-mingw64: mingw-w64-$(MINGW64_HASH).tar.xz
# 	$(call check_githash,$(MINGW64_HASH))
# 	touch $@

mingw64: mingw-w64-v$(MINGW64_VERSION).tar.bz2 .sum-mingw64
# mingw64: mingw-w64-$(MINGW64_HASH).tar.xz .sum-mingw64
	$(UNPACK)
	$(APPLY) $(SRC)/mingw64/0001-disable-pthread_-g-s-etname_np-when-targetting-Windo.patch
	$(MOVE)

.mingw64: mingw64
	touch $@

.sum-winpthreads: .sum-mingw64
	touch $@

.winpthreads: mingw64
	# The toolchain may carry older mingw-w64 headers than these winpthreads
	# sources (Debian bullseye ships v8, which lacks struct _timespec64):
	# configure the matching headers into a private prefix and compile
	# winpthreads against them. The resulting library only depends on
	# msvcrt/kernel32, so it links fine with the older toolchain.
	cd $< && rm -rf vlc_build_headers vlc_private_headers && \
	    mkdir vlc_build_headers && cd vlc_build_headers && \
	    ../mingw-w64-headers/configure --host=$(HOST) \
	        --prefix=$(abspath $<)/vlc_private_headers && \
	    $(MAKE) install
	# The v14 headers declare _set_errno() as a msvcrt dllimport, but the
	# import library of an older toolchain does not carry it: shadow it
	# with the equivalent errno assignment after <errno.h> is in.
	printf '#ifndef __ASSEMBLER__\n#include <errno.h>\n#undef _set_errno\n#define _set_errno(e) ((errno = (e)), 0)\n#endif\n' \
	    > $(abspath $<)/vlc_set_errno_compat.h
	$(MAKEBUILDDIR)
	$(MAKECONFDIR)/mingw-w64-libraries/winpthreads/configure $(HOSTCONF) \
	    CPPFLAGS="$(CPPFLAGS) -isystem $(abspath $<)/vlc_private_headers/include -include $(abspath $<)/vlc_set_errno_compat.h"
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@

.sum-dxvahd: .sum-mingw64
	touch $@

.dxvahd: mingw64
	install -d "$(PREFIX)/include"
	install $</mingw-w64-headers/include/dxvahd.h "$(PREFIX)/include"
	touch $@

.sum-mingw11-fixes: .sum-mingw64
	touch $@

.mingw11-fixes: mingw64
	install -d "$(PREFIX)/include"
	install $</mingw-w64-headers/crt/process.h "$(PREFIX)/include"
	touch $@

.sum-mingw12-fixes: .sum-mingw64
	touch $@

.mingw12-fixes: mingw64
	install -d "$(PREFIX)/include"
	install $</mingw-w64-headers/include/strmif.h "$(PREFIX)/include"
	touch $@

.sum-mft10: .sum-mingw64
	touch $@

MINGW_HEADERS_MFT := mfidl.h mfapi.h mftransform.h mferror.h mfobjects.h mmreg.h

.mft10: mingw64
	install -d "$(PREFIX)/include"
	install $(addprefix $</mingw-w64-headers/include/,$(MINGW_HEADERS_MFT)) "$(PREFIX)/include"
	touch $@

.sum-dxva: .sum-mingw64
	touch $@

.dxva: mingw64
	install -d "$(PREFIX)/include"
	install $</mingw-w64-headers/include/dxva.h "$(PREFIX)/include"
	touch $@


MINGW64_UWP_CONF := --without-headers --with-crt --without-libraries --without-tools
ifeq ($(ARCH),x86_64)
MINGW64_UWP_CONF +=--disable-lib32 --enable-lib64
MINGW64_BUILDDIR := lib64
else ifeq ($(ARCH),i386)
MINGW64_UWP_CONF +=--enable-lib32 --disable-lib64
MINGW64_BUILDDIR := lib32
else ifeq ($(ARCH),aarch64)
MINGW64_UWP_CONF +=--disable-lib32 --disable-lib64 --enable-libarm64
MINGW64_BUILDDIR := libarm64
else ifeq ($(ARCH),arm)
MINGW64_UWP_CONF +=--disable-lib32 --disable-lib64 --enable-libarm32
MINGW64_BUILDDIR := libarm32
endif

.sum-alloweduwp: .sum-mingw64
	touch $@

.alloweduwp: BUILD_DIR=$</vlc_build_alloweduwp
.alloweduwp: mingw64
	install -d "$(PREFIX)/include"
	install $</mingw-w64-headers/include/fileapi.h "$(PREFIX)/include"
	install $</mingw-w64-headers/include/memoryapi.h "$(PREFIX)/include"
	install $</mingw-w64-headers/include/winbase.h "$(PREFIX)/include"
	install $</mingw-w64-headers/include/libloaderapi.h "$(PREFIX)/include"
	install $</mingw-w64-headers/include/winreg.h "$(PREFIX)/include"
	install $</mingw-w64-headers/include/heapapi.h      "$(PREFIX)/include"
	install $</mingw-w64-headers/include/minwinbase.h   "$(PREFIX)/include"

	# Trick mingw-w64 into just building libwindowsapp.a
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) $(MINGW64_UWP_CONF)
	mkdir -p $(BUILD_DIR)/mingw-w64-crt/$(MINGW64_BUILDDIR)
	+$(MAKEBUILD) -C mingw-w64-crt LIBRARIES=$(MINGW64_BUILDDIR)/libwindowsapp.a DATA= HEADERS=
	+$(MAKEBUILD) -C mingw-w64-crt $(MINGW64_BUILDDIR)_LIBRARIES=$(MINGW64_BUILDDIR)/libwindowsapp.a install-$(MINGW64_BUILDDIR)LIBRARIES
	touch $@

.sum-dxva_x86: .sum-mingw64
	touch $@

.dxva_x86: BUILD_DIR=$</vlc_build_dxva_x86
.dxva_x86: mingw64
ifeq ($(ARCH),i386)
	install -d "$(PREFIX)/include"

	# Trick mingw-w64 into just building libdxva2.a
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) $(MINGW64_MINIMALCRT_CONF)
	mkdir -p $(BUILD_DIR)/mingw-w64-crt/$(MINGW64_BUILDDIR)
	+$(MAKEBUILD) -C mingw-w64-crt LIBRARIES=$(MINGW64_BUILDDIR)/libdxva2.a DATA= HEADERS=
	+$(MAKEBUILD) -C mingw-w64-crt $(MINGW64_BUILDDIR)_LIBRARIES=$(MINGW64_BUILDDIR)/libdxva2.a install-$(MINGW64_BUILDDIR)LIBRARIES
endif
	touch $@
