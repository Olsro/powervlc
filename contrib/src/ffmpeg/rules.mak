# FFmpeg

#Uncomment the one you want
#USE_LIBAV ?= 1
#USE_FFMPEG ?= 1

ifndef USE_LIBAV
FFMPEG_HASH=71fb6132637a2a430375c24afc381fff8b854fe7
FFMPEG_MAJVERSION := 8.1
FFMPEG_REVISION := 2
FFMPEG_VERSION := $(FFMPEG_MAJVERSION).$(FFMPEG_REVISION)
# FFMPEG_VERSION := $(FFMPEG_MAJVERSION)
FFMPEG_BRANCH=release/$(FFMPEG_MAJVERSION)
FFMPEG_URL := https://ffmpeg.org/releases/ffmpeg-$(FFMPEG_VERSION).tar.xz
FFMPEG_GITURL := https://code.ffmpeg.org/FFmpeg/FFmpeg.git
FFMPEG_LAVC_MIN := 57.37.100
USE_FFMPEG := 1
else
FFMPEG_HASH=e5afa1b556542fd7a52a0a9b409c80f2e6e1e9bb
FFMPEG_BRANCH=
FFMPEG_GITURL := git://git.libav.org/libav.git
FFMPEG_LAVC_MIN := 57.16.0
endif

FFMPEG_BASENAME := $(subst .,_,$(subst \,_,$(subst /,_,$(FFMPEG_HASH))))

# bsf=vp9_superframe is needed to mux VP9 inside webm/mkv
FFMPEGCONF = --prefix="$(PREFIX)" --enable-static --disable-shared \
	--extra-ldflags="$(LDFLAGS)" \
	--cc="$(CC)" \
	--pkg-config="$(PKG_CONFIG)" \
	--disable-doc \
	--disable-encoder=vorbis \
	--disable-decoder=opus \
	--enable-libgsm \
	--disable-debug \
	--disable-avdevice \
	--disable-devices \
	--disable-avfilter \
	--disable-filters \
	--disable-protocol=concat \
	--disable-bsfs \
	--disable-bzlib \
	--disable-libvpx \
	--enable-bsf=vp9_superframe

ifdef USE_FFMPEG
FFMPEGCONF += \
	--disable-swresample \
	--disable-iconv \
	--disable-avisynth \
	--disable-nvenc \
	--disable-linux-perf
ifdef HAVE_DARWIN_OS
FFMPEGCONF += \
	--disable-securetransport
endif
endif

ifdef ENABLE_PDB
FFMPEGCONF += --ln_s=false
endif

DEPS_ffmpeg = zlib $(DEPS_zlib) gsm $(DEPS_gsm)

ifndef USE_LIBAV
# VLC_FFMPEG_NO_OPENJPEG: the AppImage containers have no cmake to build
# the openjpeg contrib; ffmpeg 8's native JPEG 2000 decoder covers
# playback there.
ifndef VLC_FFMPEG_NO_OPENJPEG
FFMPEGCONF += \
	--enable-libopenjpeg
DEPS_ffmpeg += openjpeg
endif
endif

# Optional dependencies
ifndef BUILD_NETWORK
FFMPEGCONF += --disable-network
endif
ifdef BUILD_ENCODERS
FFMPEGCONF += --enable-libmp3lame
DEPS_ffmpeg += lame $(DEPS_lame)
else
FFMPEGCONF += --disable-encoders --disable-muxers
endif

ifneq ($(findstring amf,$(PKGS)),)
DEPS_ffmpeg += amf $(DEPS_amf)
endif

# Small size
ifdef WITH_OPTIMIZATION
ifdef ENABLE_SMALL
FFMPEGCONF += --enable-small
endif
ifeq ($(ARCH),arm)
ifdef HAVE_ARMV7A
FFMPEGCONF += --enable-thumb
endif
endif
else
FFMPEGCONF += --optflags=-Og
endif

ifdef HAVE_CROSS_COMPILE
FFMPEGCONF += --enable-cross-compile --disable-programs
ifndef HAVE_DARWIN_OS
FFMPEGCONF += --cross-prefix=$(HOST)-
endif
endif

# ARM stuff
ifeq ($(ARCH),arm)
FFMPEGCONF += --arch=arm
ifdef HAVE_ARMV7A
FFMPEGCONF += --cpu=cortex-a8
endif
ifdef HAVE_ARMV6
FFMPEGCONF += --cpu=armv6 --disable-neon
endif
endif

# ARM64 stuff
ifeq ($(ARCH),aarch64)
FFMPEGCONF += --arch=aarch64
endif

# MIPS stuff
ifeq ($(ARCH),mipsel)
FFMPEGCONF += --arch=mips
endif
ifeq ($(ARCH),mips64el)
FFMPEGCONF += --arch=mips64
endif

# RISC-V stuff
ifneq ($(findstring $(ARCH),riscv32 riscv64),)
FFMPEGCONF += --arch=riscv
endif

# x86 stuff
ifeq ($(ARCH),i386)
ifndef HAVE_DARWIN_OS
FFMPEGCONF += --arch=x86
endif
endif

# x86_64 stuff
ifeq ($(ARCH),x86_64)
ifndef HAVE_DARWIN_OS
FFMPEGCONF += --arch=x86_64
endif
endif

# Darwin
ifdef HAVE_DARWIN_OS
ifeq ($(ARCH),arm64_32)
# TODO remove when FFMpeg supports arm64_32
FFMPEGCONF += --arch=aarch64_32
else
FFMPEGCONF += --arch=$(ARCH)
endif
FFMPEGCONF += --target-os=darwin --extra-cflags="$(CFLAGS)"
ifneq ($(call darwin_min_os_at_least, 10.6), true)
# The AudioToolbox decoders/encoders use constants introduced after the
# 10.4/10.5 SDKs (kAudioFormatAMR, kAudioCodecBitRateControlMode_*...);
# VLC has its own audio decoders, so simply drop them for old targets.
FFMPEGCONF += --disable-audiotoolbox
endif
ifeq ($(call darwin_sdk_at_most, 10.8), true)
# assert.h in the pre-10.9 SDKs predates C11: no static_assert macro, which
# ffmpeg >= 6 uses freely. _Static_assert is a compiler keyword in GCC/clang.
FFMPEGCONF += --extra-cflags="-Dstatic_assert=_Static_assert"
endif
ifeq ($(ARCH),ppc)
ifdef VLC_PPC_ALTIVEC
# G4/G4e/G5 targets: AltiVec on (build.sh exports VLC_PPC_ALTIVEC and
# passes -maltivec in EXTRA_CFLAGS)
FFMPEGCONF += --enable-altivec
else
# G3 (ppc750) baseline: no AltiVec units on that CPU
FFMPEGCONF += --disable-altivec
endif
# ffmpeg defaults to -mdynamic-no-pic on Darwin; its static archives are
# linked into VLC plugin dylibs where ld64 rejects text relocations
FFMPEGCONF += --enable-pic
endif
ifeq ($(ARCH),i386)
ifdef HAVE_MACOSX
# Re-enable the EXTERNAL (nasm) x86 asm — IDCT, motion-comp, and the whole DSP
# for every codec — which is assembled position-independent with --enable-pic
# and links cleanly.
#
# The GCC INLINE asm is kept ON as well, for the H.264 CABAC bitstream reader
# (libavcodec/x86/cabac.h): it exists in no other form, and on a high-bitrate
# stream CABAC dominates the decode. Measured on a Core 2 Duo 2.16 GHz with a
# 21 Mbit/s 1080p Blu-ray remux: 21.7 -> 26.5 fps (+22 %), bit-exact output.
# The cost is that ffmpeg detects HAVE_INLINE_ASM_DIRECT_SYMBOL_REFS=1 (its
# probe only compiles a .o, so it never sees that ld64 later rejects the
# absolute reference to ff_h264_cabac_tables from a dylib), which leaves a
# handful of text relocations. build.sh answers that with
# -Wl,-read_only_relocs,suppress on i386. The PIC-clean alternative — ffmpeg's
# named-constraint fallback — does not build here: it needs one more operand
# than the i386 register file has once %ebx is pinned as the PIC base
# ("'asm' operand has impossible constraints" in cabac.h).
FFMPEGCONF += --enable-pic
endif
endif
ifdef USE_FFMPEG
FFMPEGCONF += --disable-lzma
endif
ifeq ($(ARCH),x86_64)
FFMPEGCONF += --cpu=core2
endif
ifdef HAVE_IOS
FFMPEGCONF += --enable-pic --extra-ldflags="$(EXTRA_CFLAGS) -isysroot $(IOS_SDK)"
endif
endif

# Linux
ifdef HAVE_LINUX
FFMPEGCONF += --target-os=linux --enable-pic

endif

ifdef HAVE_ANDROID
# broken text relocations
ifeq ($(ANDROID_ABI), x86)
FFMPEGCONF +=  --disable-mmx --disable-mmxext --disable-inline-asm
endif
endif

# Windows
ifdef HAVE_WIN32
ifndef HAVE_VISUALSTUDIO
DEPS_ffmpeg += d3d11 mingw12-fixes
endif
FFMPEGCONF += --target-os=mingw32
FFMPEGCONF += --disable-w32threads --enable-pthreads --extra-libs="-lpthread"
DEPS_ffmpeg += winpthreads $(DEPS_winpthreads)
# disable modules not compatible with XP
FFMPEGCONF += --disable-mediafoundation --disable-amf --disable-schannel
# We don't currently support D3D12 in VLC
FFMPEGCONF += --disable-d3d12va
ifndef HAVE_WINSTORE
FFMPEGCONF += --enable-dxva2
else
FFMPEGCONF += --disable-dxva2 --disable-mediafoundation
endif

ifeq ($(ARCH),x86_64)
FFMPEGCONF += --cpu=athlon64 --arch=x86_64
else
ifeq ($(ARCH),i386) # 32bits intel
FFMPEGCONF+= --cpu=i686 --arch=x86
else
ifdef HAVE_ARMV7A
FFMPEGCONF+= --arch=arm
endif
endif
endif

else # !Windows
FFMPEGCONF += --enable-pthreads
endif

# Solaris
ifdef HAVE_SOLARIS
ifeq ($(ARCH),x86_64)
FFMPEGCONF += --cpu=core2
endif
FFMPEGCONF += --target-os=sunos --enable-pic
endif

# Build
PKGS += ffmpeg
ifeq ($(call need_pkg,"libavcodec >= $(FFMPEG_LAVC_MIN) libavformat >= 53.21.0 libswscale"),)
PKGS_FOUND += ffmpeg
endif

FFMPEGCONF += --nm="$(NM)" --ar="$(AR)" --ranlib="$(RANLIB)"

$(TARBALLS)/ffmpeg-$(FFMPEG_BASENAME).tar.xz:
	$(call download_git,$(FFMPEG_GITURL),$(FFMPEG_BRANCH),$(FFMPEG_HASH))

# .sum-ffmpeg: $(TARBALLS)/ffmpeg-$(FFMPEG_BASENAME).tar.xz
# 	$(call check_githash,$(FFMPEG_HASH))
# 	touch $@

$(TARBALLS)/ffmpeg-$(FFMPEG_VERSION).tar.xz:
	$(call download_pkg,$(FFMPEG_URL),ffmpeg)

.sum-ffmpeg: ffmpeg-$(FFMPEG_VERSION).tar.xz

ffmpeg: ffmpeg-$(FFMPEG_VERSION).tar.xz .sum-ffmpeg
	$(UNPACK)
ifdef USE_FFMPEG
	$(APPLY) $(SRC)/ffmpeg/dxva_vc1_crash.patch
	$(APPLY) $(SRC)/ffmpeg/h264_early_SAR.patch
	$(APPLY) $(SRC)/ffmpeg/0001-avutil-define-WC_ERR_INVALID_CHARS-when-it-s-missing.patch
	$(APPLY) $(SRC)/ffmpeg/0001-avcodec-dxva2_hevc-add-support-for-parsing-HEVC-Rang.patch
	$(APPLY) $(SRC)/ffmpeg/0002-avcodec-hevcdec-allow-HEVC-444-8-10-12-bits-decoding.patch
	$(APPLY) $(SRC)/ffmpeg/0003-avcodec-hevcdec-allow-HEVC-422-10-12-bits-decoding-w.patch
	$(APPLY) $(SRC)/ffmpeg/0001-avcodec-mpeg12dec-don-t-call-hw-end_frame-when-start.patch
	$(APPLY) $(SRC)/ffmpeg/0002-avcodec-mpeg12dec-don-t-end-a-slice-without-first_sl.patch
	$(APPLY) $(SRC)/ffmpeg/0001-fix-mf_utils-compilation-with-mingw64.patch
	# replace Vista checks with XP SP1 checks so we don't actually change _WIN32_WINNT
	sed -i.orig 's,< 0x0600,< 0x0501,g' $(UNPACK_DIR)/configure
	$(APPLY) $(SRC)/ffmpeg/0001-bring-back-XP-support.patch
	$(APPLY) $(SRC)/ffmpeg/0011-avcodec-videotoolboxenc-disable-calls-on-unsupported.patch
	$(APPLY) $(SRC)/ffmpeg/avcodec-fix-compilation-visionos.patch
	$(APPLY) $(SRC)/ffmpeg/0001-ppc-h264-add-AltiVec-qpel8-and-clz-based-CABAC-renorm.patch
	$(APPLY) $(SRC)/ffmpeg/ffmpeg-ppc-hpeldsp-altivec.patch
	$(APPLY) $(SRC)/ffmpeg/0002-ppc-h264-inline-get_cabac-and-table-driven-chroma-mc.patch
	$(APPLY) $(SRC)/ffmpeg/0003-ppc-h264-altivec-loop-filter-strength.patch
	$(APPLY) $(SRC)/ffmpeg/0004-ppc-h264-prefetch-whole-reference-block.patch
	$(APPLY) $(SRC)/ffmpeg/0005-ppc-h264-altivec-chroma-mc4.patch
	$(APPLY) $(SRC)/ffmpeg/0006-ppc-hevc-altivec-sao-idct-and-mc.patch
	$(APPLY) $(SRC)/ffmpeg/0007-ppc-h264-chroma-mc8-element-stores.patch
	# AltiVec series from the macos-powerpc/powerpc-ports tree (Sergey
	# Fedorov, multimedia/ffmpeg8/files), same ffmpeg 8.1.2 base as ours.
	# Kept at the upstream numbering under an `mpp-` prefix so the series
	# can be re-synced patch by patch. Five are deliberately not taken:
	# 0004 (AltiVec HEVC 8-bit qpel h/v/hv) registers exactly the three
	# put_hevc_qpel slots that PowerVLC's own 0006-ppc-hevc-* overwrites a
	# few lines later, for every width class, so none of its kernels were
	# ever reachable in this tree — dead weight, and a trap: it silently
	# claimed the narrow widths that our 0009 width floor removes.
	# 0007 and 0021 collide with the PowerVLC hpeldsp/h264qpel kernels
	# above; 0014 adds AltiVec H.264 chroma loop filters that BOTH trees
	# have since measured as a loss (our 0003 kept the h and intra
	# variants in C after benching a 7447A, their 0027 disables the same
	# ones on a 970 at 0.60-0.66x), and its chroma_mc4 half duplicates our
	# 0005; 0017 only fixes a pix%16==8 bug inside 0014's own kernels (our
	# equivalents load through vec_perm/vec_lvsl and fill all eight tc0
	# lanes, so they are not affected). 0027 and 0030 are taken as
	# subsets, see the note in their commit messages.
	#
	# Some of these build nothing with our configure flags and are kept
	# only to keep the series intact and rebasable: 0003 (Opus DSP, we pass
	# --disable-decoder=opus), 0010/0013 (checkasm, tests are not built),
	# 0024/0026/0029 (libswresample, we pass --disable-swresample).
	$(APPLY) $(SRC)/ffmpeg/mpp-0001-avcodec-ppc-add-AltiVec-optimized-VP9-decoder.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0002-avutil-ppc-add-AltiVec-split-radix-FFT-backend-for-a.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0003-avcodec-ppc-add-AltiVec-optimized-Opus-DSP-postfilte.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0005-avutil-ppc-add-AltiVec-vector_fmac-fmul_scalar-butte.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0006-avcodec-ppc-add-AltiVec-H.264-intra-prediction-16x16.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0008-avcodec-ppc-add-AltiVec-vector_clip_int32-vector_cli.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0009-avcodec-ppc-add-AltiVec-ac3dsp-float_to_fixed24-sum_.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0010-tests-checkasm-add-swr_resample-resample_common-resa.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0011-avcodec-ppc-fix-vp9dsp_altivec-vertical-MC-filters-r.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0012-avcodec-ppc-fix-vp8dsp_altivec-unaligned-read-write-.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0013-tests-checkasm-call-swr-resample-dsp-under-the-real-.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0015-avcodec-ppc-VP9-horizontal-loop-filters-4-8-wide-mix.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0016-avcodec-ppc-emulated_edge_mc-AltiVec-O4.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0018-avcodec-ppc-make-emulated_edge_mc-stores-byte-precis.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0019-avutil-ppc-fix-wrong-sel_hi-permute-in-av_tx-fft4_ve.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0020-avutil-ppc-add-directly-selectable-top-level-av_tx-F.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0022-avutil-ppc-drop-top-level-av_tx-codelets-for-4-and-8.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0023-avcodec-ppc-add-AltiVec-SBR-and-AAC-PS-DSP-kernels-O.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0024-swresample-ppc-add-AltiVec-resample_common-float-ker.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0025-avcodec-ppc-add-AltiVec-VP9-4x4-inverse-transforms-O.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0026-swresample-ppc-fix-misleading-comment-on-the-x4-filt.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0027-avcodec-ppc-bench-driven-per-CPU-tuning-of-AltiVec-r-powervlc-subset.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0028-avcodec-ppc-add-AltiVec-VP9-8x8-inverse-transforms-O.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0029-swresample-ppc-add-AltiVec-resample_linear-float-S16.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0030-avcodec-ppc-tuning-pass-2-from-the-2026-07-30-G5-re--powervlc-subset.patch
	$(APPLY) $(SRC)/ffmpeg/mpp-0031-avcodec-ppc-add-AltiVec-VP9-16x16-32x32-inverse-tran.patch
	# PowerVLC tuning on top of the series: two registrations that the
	# shared g4/g5 contrib would otherwise keep, benched as losses on a
	# real 7447A.
	$(APPLY) $(SRC)/ffmpeg/0008-ppc-drop-two-altivec-registrations-slower-than-C-on-7447A.patch
	# Second tuning pass, from a full checkasm --bench of all 507 registered
	# AltiVec kernels on the 7447A: HEVC MC gains a width>=8 floor, HEVC SAO
	# 8-bit drops width 8, and three upstream kernels that lose there are
	# unregistered. See doc/ffmpeg-altivec-macos-powerpc.md.
	$(APPLY) $(SRC)/ffmpeg/0009-ppc-bench-driven-registration-tuning-on-a-7447A.patch
endif
ifdef USE_LIBAV
	$(APPLY) $(SRC)/ffmpeg/libav_gsm.patch
endif
ifdef HAVE_MACOSX
	# ffmpeg >= 6 refuses to configure with asm enabled when the target has
	# no aligned allocator (posix_memalign is 10.6+, aligned_alloc 10.15+).
	# Darwin's plain malloc has always returned 16-byte aligned blocks and
	# libavutil/mem.c still carries that fallback, so the guard is moot here
	# (the HAVE_POSIX_MEMALIGN sed below keeps the old targets on malloc).
	sed -i.orig1 's/if ! enabled_any memalign posix_memalign aligned_malloc; then/if false; then # PowerVLC: Darwin malloc is 16-byte aligned/' $(UNPACK_DIR)/configure
	# The 10.4 SDK's mach/i386/thread_status.h defines a struct xmm_reg
	# (and thread_status pulls in on every <mach/...> include); rename
	# ffmpeg's private struct TAGS to avoid the clash — the typedef
	# names stay, so no other source needs changes.
	sed -i.orig -e 's/typedef struct xmm_reg/typedef struct ff_priv_xmm_reg/' \
	            -e 's/typedef struct ymm_reg/typedef struct ff_priv_ymm_reg/' \
	    $(UNPACK_DIR)/libavutil/x86/asm.h
endif
	$(MOVE)

.ffmpeg: ffmpeg
	$(MAKEBUILDDIR)
	$(MAKECONFDIR)/configure $(FFMPEGCONF)
ifdef HAVE_MACOSX
ifneq ($(call darwin_min_os_at_least, 10.6), true)
	# posix_memalign is absent before Mac OS X 10.6; fall back to malloc,
	# which is 16-byte aligned on macOS (enough for SSE-era CPUs)
	sed -i.orig -e 's/#define HAVE_POSIX_MEMALIGN 1/#define HAVE_POSIX_MEMALIGN 0/' $(BUILD_DIR)/config.h
endif
endif
	+$(MAKEBUILD)
	+$(MAKEBUILD) install-libs install-headers
ifdef HAVE_MACOSX
ifneq ($(call darwin_min_os_at_least, 10.7), true)
	# CoreMedia does not exist before Mac OS X 10.7 (and no CM/CV symbol is
	# actually used with videotoolbox disabled); a hard link makes every
	# consumer plugin fail to dlopen on 10.5/10.6
	sed -i.orig -e 's/-framework CoreVideo//g' -e 's/-framework CoreMedia//g' \
		$(PREFIX)/lib/pkgconfig/libavutil.pc \
		$(PREFIX)/lib/pkgconfig/libavcodec.pc \
		$(PREFIX)/lib/pkgconfig/libavformat.pc
endif
endif
	touch $@
