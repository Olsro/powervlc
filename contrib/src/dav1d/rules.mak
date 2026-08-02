# libdav1d

DAV1D_VERSION := 1.5.4
DAV1D_URL := $(VIDEOLAN)/dav1d/$(DAV1D_VERSION)/dav1d-$(DAV1D_VERSION).tar.xz

# aligned-allocation functions absent before Mac OS X 10.6: dav1d >= 1.5.4
# carries the manual malloc fallback upstream (former PowerVLC patch 0001)
PKGS += dav1d
ifeq ($(call need_pkg,"dav1d"),)
PKGS_FOUND += dav1d
endif

DAV1D_CONF = -D enable_tests=false -D enable_tools=false

# dav1d's hand-written x86-32 assembly (SSSE3 angular intra predictors and
# likely other Mach-O/PIC code paths) is broken on Mac OS X i386: it computes
# wild pointers and crashes AV1 decode (SIGBUS/SIGSEGV, e.g. inside
# dav1d_ipred_z1_8bpc_ssse3). Fall back to the C DSP on the 32-bit Intel slice
# — slower but correct. The ppc/x86_64/arm64 slices keep their asm.
ifeq ($(ARCH),i386)
DAV1D_CONF += -D enable_asm=false
endif

# PowerPC: upstream dav1d only builds its PPC backend for ppc64le, so a G4 or a
# G5 decoded AV1 entirely in C. 0002..0007 below are Sergey Fedorov's plain
# AltiVec port (see the patch list under `dav1d`), which turns that backend on
# for big-endian 32/64-bit PowerPC and adds the VSX-less kernels the G4/G5 can
# actually run.
#
# They are applied on every slice -- patching only the PowerPC contribs would
# leave the others unable to build once anything else in the tree expects the
# patched tree (the mistake made once with libmpeg2). What is conditional is
# whether the backend is *compiled*: the G3 (750/750FX) has no vector unit at
# all, and dav1d's meson would hand -maltivec to the AltiVec sub-target
# regardless of the CPU flags this contrib was configured with. build.sh
# exports VLC_PPC_ALTIVEC for the g4/g4e/g5 targets only, so the G3 slice keeps
# the C DSP -- as it already does for ffmpeg (contrib/src/ffmpeg/rules.mak).
#
# 0008 is the second half of that safety net, at runtime: Darwin has no
# auxiliary vector, and the upstream port assumes every Apple PowerPC has
# AltiVec. It asks the kernel (hw.vectorunit) instead.
ifeq ($(ARCH),ppc)
ifndef VLC_PPC_ALTIVEC
DAV1D_CONF += -D enable_asm=false
endif
endif

$(TARBALLS)/dav1d-$(DAV1D_VERSION).tar.xz:
	$(call download_pkg,$(DAV1D_URL),dav1d)
#	$(call download_git,$(DAV1D_GITURL),,$(DAV1D_HASH))

.sum-dav1d: dav1d-$(DAV1D_VERSION).tar.xz

# 0002..0007 are the PowerPC AltiVec backend, taken verbatim from
# https://github.com/macos-powerpc/powerpc-ports/tree/main/multimedia/dav1d/files
# (0001-Support-altivec.patch and the five 000{2..6}-PPC-* that follow it,
# renumbered here to keep the local patch order). They apply to 1.5.1 as they do
# to the 1.5.4 that port carries. 0008 is ours; see the note above.
dav1d: dav1d-$(DAV1D_VERSION).tar.xz .sum-dav1d
	$(UNPACK)
	$(APPLY) $(SRC)/dav1d/0002-ppc-support-altivec.patch
	$(APPLY) $(SRC)/dav1d/0003-ppc-altivec-inverse-transform.patch
	$(APPLY) $(SRC)/dav1d/0004-ppc-altivec-mc-blend.patch
	$(APPLY) $(SRC)/dav1d/0005-ppc-altivec-loop-filter.patch
	$(APPLY) $(SRC)/dav1d/0006-ppc-altivec-compound-prediction.patch
	$(APPLY) $(SRC)/dav1d/0007-ppc-altivec-subpel-mc.patch
	$(APPLY) $(SRC)/dav1d/0008-ppc-darwin-runtime-altivec-check.patch
	$(MOVE)

.dav1d: dav1d crossfile.meson
	$(MESONCLEAN)
	$(MESON) $(DAV1D_CONF)
	+$(MESONBUILD)
	touch $@
