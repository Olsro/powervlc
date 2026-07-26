# FFmpeg

#Uncomment the one you want
#USE_LIBAV ?= 1
#USE_FFMPEG ?= 1

ifndef USE_LIBAV
FFMPEG_HASH=71fb6132637a2a430375c24afc381fff8b854fe7
FFMPEG_MAJVERSION := 4.4
FFMPEG_REVISION := 5
FFMPEG_VERSION := $(FFMPEG_MAJVERSION).$(FFMPEG_REVISION)
FFMPEG_BRANCH=release/$(FFMPEG_MAJVERSION)
FFMPEG_URL := https://ffmpeg.org/releases/ffmpeg-$(FFMPEG_VERSION).tar.xz
FFMPEG_SNAPURL := http://git.videolan.org/?p=ffmpeg.git;a=snapshot;h=$(FFMPEG_HASH);sf=tgz
FFMPEG_GITURL := http://git.videolan.org/git/ffmpeg.git
FFMPEG_LAVC_MIN := 57.37.100
USE_FFMPEG := 1
else
FFMPEG_HASH=e5afa1b556542fd7a52a0a9b409c80f2e6e1e9bb
FFMPEG_BRANCH=
FFMPEG_SNAPURL := http://git.libav.org/?p=libav.git;a=snapshot;h=$(FFMPEG_HASH);sf=tgz
FFMPEG_GITURL := git://git.libav.org/libav.git
FFMPEG_LAVC_MIN := 57.16.0
endif

FFMPEG_BASENAME := $(subst .,_,$(subst \,_,$(subst /,_,$(FFMPEG_HASH))))

# bsf=vp9_superframe is needed to mux VP9 inside webm/mkv
FFMPEGCONF = \
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
	--disable-avresample \
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
	--disable-videotoolbox \
	--disable-securetransport
endif
endif

DEPS_ffmpeg = zlib gsm

ifndef USE_LIBAV
FFMPEGCONF += \
	--enable-libopenjpeg
DEPS_ffmpeg += openjpeg
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

# Postproc
MAYBE_POSTPROC =
ifdef GPL
FFMPEGCONF += --enable-gpl --enable-postproc
MAYBE_POSTPROC = libpostproc
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
ifdef HAVE_NEON
FFMPEGCONF += --enable-neon
endif
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
FFMPEGCONF += --arch=$(ARCH) --target-os=darwin --extra-cflags="$(CFLAGS)"
ifneq ($(call darwin_min_os_at_least, 10.6), true)
# The AudioToolbox decoders/encoders use constants introduced after the
# 10.4/10.5 SDKs (kAudioFormatAMR, kAudioCodecBitRateControlMode_*...);
# VLC has its own audio decoders, so simply drop them for old targets.
FFMPEGCONF += --disable-audiotoolbox
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
ifdef HAVE_NEON
FFMPEGCONF += --as="$(AS)"
endif
endif
endif

# Linux
ifdef HAVE_LINUX
FFMPEGCONF += --target-os=linux --enable-pic --extra-libs="-lm"

endif

ifdef HAVE_ANDROID
# broken text relocations
ifeq ($(ANDROID_ABI), x86)
FFMPEGCONF +=  --disable-mmx --disable-mmxext --disable-inline-asm
endif
ifeq ($(ANDROID_ABI), x86_64)
FFMPEGCONF +=  --disable-mmx --disable-mmxext --disable-inline-asm
endif
endif

# Windows
ifdef HAVE_WIN32
ifndef HAVE_VISUALSTUDIO
DEPS_ffmpeg += d3d11
endif
FFMPEGCONF += --target-os=mingw32
FFMPEGCONF += --disable-w32threads --enable-pthreads --extra-libs="-lpthread"
DEPS_ffmpeg += pthreads $(DEPS_pthreads)
# disable modules not compatible with XP
FFMPEGCONF += --disable-mediafoundation --disable-amf --disable-schannel
ifndef HAVE_WINSTORE
FFMPEGCONF += --enable-dxva2
else
FFMPEGCONF += --disable-dxva2
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
ifeq ($(call need_pkg,"libavcodec >= $(FFMPEG_LAVC_MIN) libavformat >= 53.21.0 libswscale $(MAYBE_POSTPROC)"),)
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
	$(APPLY) $(SRC)/ffmpeg/armv7_fixup.patch
	$(APPLY) $(SRC)/ffmpeg/dxva_vc1_crash.patch
	$(APPLY) $(SRC)/ffmpeg/h264_early_SAR.patch
	$(APPLY) $(SRC)/ffmpeg/0001-avcodec-dxva2_hevc-add-support-for-parsing-HEVC-Rang.patch
	$(APPLY) $(SRC)/ffmpeg/0002-avcodec-hevcdec-allow-HEVC-444-8-10-12-bits-decoding.patch
	$(APPLY) $(SRC)/ffmpeg/0003-avcodec-hevcdec-allow-HEVC-422-10-12-bits-decoding-w.patch
	$(APPLY) $(SRC)/ffmpeg/0001-avcodec-mpeg12dec-don-t-call-hw-end_frame-when-start.patch
	$(APPLY) $(SRC)/ffmpeg/0002-avcodec-mpeg12dec-don-t-end-a-slice-without-first_sl.patch
	$(APPLY) $(SRC)/ffmpeg/0001-fix-MediaFoundation-compilation-if-WINVER-was-forced.patch
	$(APPLY) $(SRC)/ffmpeg/0001-bring-back-XP-support.patch
	$(APPLY) $(SRC)/ffmpeg/0001-avcodec-vp9-Do-not-destroy-uninitialized-mutexes-con.patch
	$(APPLY) $(SRC)/ffmpeg/0001-dxva2_hevc-don-t-use-frames-as-reference-if-they-are.patch
	$(APPLY) $(SRC)/ffmpeg/0001-Replace-all-occurences-of-av_mallocz_array-by-av_cal.patch
	$(APPLY) $(SRC)/ffmpeg/0002-compat-w32dlfcn.h-Remove-MAX_PATH-limit-and-replace-.patch
	$(APPLY) $(SRC)/ffmpeg/0001-ppc-h264-add-AltiVec-qpel8-and-clz-based-CABAC-renorm.patch
	$(APPLY) $(SRC)/ffmpeg/ffmpeg-ppc-hpeldsp-altivec.patch
endif
ifdef USE_LIBAV
	$(APPLY) $(SRC)/ffmpeg/libav_gsm.patch
endif
ifdef HAVE_MACOSX
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
	cd $< && $(HOSTVARS) ./configure \
		--extra-ldflags="$(LDFLAGS)" $(FFMPEGCONF) \
		--prefix="$(PREFIX)" --enable-static --disable-shared
ifdef HAVE_MACOSX
ifneq ($(call darwin_min_os_at_least, 10.6), true)
	# posix_memalign is absent before Mac OS X 10.6; fall back to malloc,
	# which is 16-byte aligned on macOS (enough for SSE-era CPUs)
	cd $< && sed -i.orig -e 's/#define HAVE_POSIX_MEMALIGN 1/#define HAVE_POSIX_MEMALIGN 0/' config.h
endif
endif
	$(MAKE) -C $< install-libs install-headers
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
