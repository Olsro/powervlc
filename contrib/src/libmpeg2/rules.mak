# libmpeg2

LIBMPEG2_VERSION := 0.5.1
LIBMPEG2_URL := $(CONTRIB_VIDEOLAN)/libmpeg2/libmpeg2-$(LIBMPEG2_VERSION).tar.gz

ifdef GPL
PKGS += libmpeg2
endif
ifeq ($(call need_pkg,"libmpeg2"),)
PKGS_FOUND += libmpeg2
endif

$(TARBALLS)/libmpeg2-$(LIBMPEG2_VERSION).tar.gz:
	$(call download_pkg,$(LIBMPEG2_URL),libmpeg2)

.sum-libmpeg2: libmpeg2-$(LIBMPEG2_VERSION).tar.gz

libmpeg2: libmpeg2-$(LIBMPEG2_VERSION).tar.gz .sum-libmpeg2
	$(UNPACK)
	$(APPLY) $(SRC)/libmpeg2/libmpeg2-arm-pld.patch
	$(APPLY) $(SRC)/libmpeg2/libmpeg2-inline.patch
	$(APPLY) $(SRC)/libmpeg2/libmpeg2-mc-neon.patch
	$(APPLY) $(SRC)/libmpeg2/libmpeg2-ppc-word-mc.patch
	# Macroblock capture hooks for the hardware MPEG-2 decoder: without them
	# modules/codec/libmpeg2.c cannot compile (mpeg2_hwaccel_t).
	$(APPLY) $(SRC)/libmpeg2/libmpeg2-powervlc-hwaccel.patch
	sed -i.orig -e 's,libvo src test vc++,,' $(UNPACK_DIR)/Makefile.am
	sed -i.orig -e 's,SUBDIRS,# SUBDIRS,' $(UNPACK_DIR)/libmpeg2/Makefile.am
ifeq ($(ARCH),ppc)
	# G3 target: skip AltiVec detection entirely (the 750 has none, and
	# this pre-C99 AltiVec code no longer compiles with modern GCC)
	sed -i.orig2 -e 's/for TRY_CFLAGS in "-mpim-altivec -force_cpusubtype_ALL" -faltivec -maltivec -fvec; do/for TRY_CFLAGS in ; do/' $(UNPACK_DIR)/configure.ac
endif
	$(MOVE)

LIBMPEG2_CONF := --without-x --disable-sdl
ifeq ($(ARCH),ppc)
# The decoder is the single largest CPU consumer of DVD playback on a G3;
# the stock contrib -g -O2 leaves measurable performance on the table.
LIBMPEG2_CONF += CFLAGS="$(CFLAGS) -O3 -fomit-frame-pointer -mtune=750"
endif

.libmpeg2: libmpeg2
	$(REQUIRE_GPL)
	$(RECONF)
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) $(LIBMPEG2_CONF)
	+$(MAKEBUILD) -C libmpeg2
	+$(MAKEBUILD) -C include
	+$(MAKEBUILD) -C libmpeg2 install
	+$(MAKEBUILD) -C include install
	touch $@
