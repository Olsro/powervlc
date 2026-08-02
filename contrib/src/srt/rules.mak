# srt

SRT_VERSION := 1.5.6
SRT_URL := $(GITHUB)/Haivision/srt/archive/v$(SRT_VERSION).tar.gz

# gnutls (nettle/gmp) can't be used with the LGPLv2 license
ifdef GPL
SRT_PKG=1
else
ifdef GNUV3
SRT_PKG=1
endif
endif

ifdef BUILD_NETWORK
ifdef SRT_PKG
PKGS += srt
endif
endif

ifeq ($(call need_pkg,"srt >= 1.3.1"),)
PKGS_FOUND += srt
endif

DEPS_srt = gnutls $(DEPS_gnutls)
ifdef HAVE_WIN32
DEPS_srt += winpthreads $(DEPS_winpthreads)
endif

$(TARBALLS)/srt-$(SRT_VERSION).tar.gz:
	$(call download_pkg,$(SRT_URL),srt)

.sum-srt: srt-$(SRT_VERSION).tar.gz

srt: srt-$(SRT_VERSION).tar.gz .sum-srt
	$(UNPACK)
	$(APPLY) $(SRC)/srt/0001-build-fix-implicit-libraries-set-using-Wl-l-libname..patch
	$(call pkg_static,"scripts/srt.pc.in")
ifdef HAVE_MACOSX
	# The 10.4 SDK's <sys/param.h> defines a BSD isset() macro that
	# clashes with LogDispatcher::isset(); rename the method (1.5.6
	# grew a third user in logging.cpp).
	sed -i.orig -e 's/isset(/isSetFlag(/g' $(UNPACK_DIR)/srtcore/logging.h \
	    $(UNPACK_DIR)/srtcore/logging.cpp $(UNPACK_DIR)/srtcore/common.cpp
ifneq ($(call darwin_min_os_at_least, 10.6), true)
	# pthread_get/setname_np are 10.6+ and the Find module unset()s any
	# cache preset before re-probing (the probe only compiles, so the
	# availability error never fires there): short-circuit it, srt then
	# uses its dummy ThreadName implementation
	perl -pi -e 's/^function\(FindPThreadGetSetName\)$$/function(FindPThreadGetSetName)\n   return()/' \
	    $(UNPACK_DIR)/scripts/FindPThreadGetSetName.cmake
endif
endif
	$(MOVE)

SRT_CONF := -DENABLE_SHARED=OFF -DUSE_ENCLIB=gnutls -DENABLE_CXX11=OFF -DENABLE_APPS=OFF
ifdef HAVE_MACOSX
ifneq ($(call darwin_min_os_at_least, 10.6), true)
# pthread_get/setname_np are 10.6+; without them srt falls back to its
# dummy ThreadName implementation
SRT_CONF += -DHAVE_PTHREAD_GETNAME_NP:INTERNAL= -DHAVE_PTHREAD_SETNAME_NP:INTERNAL=
endif
endif

.srt: srt toolchain.cmake
	$(CMAKECLEAN)
	$(HOSTVARS_CMAKE) $(CMAKE) $(SRT_CONF)
	+$(CMAKEBUILD)
	$(CMAKEINSTALL)
	touch $@
