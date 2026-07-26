# speexdsp

SPEEXDSP_VERSION := 1.2.1
SPEEXDSP_URL := $(XIPH)/speex/speexdsp-$(SPEEXDSP_VERSION).tar.gz

PKGS += speexdsp
ifeq ($(call need_pkg,"speexdsp"),)
PKGS_FOUND += speexdsp
endif

$(TARBALLS)/speexdsp-$(SPEEXDSP_VERSION).tar.gz:
	$(call download_pkg,$(SPEEXDSP_URL),speexdsp)

.sum-speexdsp: speexdsp-$(SPEEXDSP_VERSION).tar.gz

speexdsp: speexdsp-$(SPEEXDSP_VERSION).tar.gz .sum-speexdsp
	$(UNPACK)
	$(MOVE)

SPEEXDSP_CONF := --enable-resample-full-sinc-table --disable-examples
ifeq ($(ARCH),ppc)
# With the full sinc table, every speex_resampler_set_rate() rebuilds a
# filt_len*den_rate table (one sin() per entry): for the arbitrary
# near-unity ratios of the aout drift loop that is 100-200 ms of sin() on
# a G4 *per adjustment*, profiled at a quarter of the core during h264
# playback. The upstream default (interpolated table, a few hundred
# entries) rebuilds in microseconds for a marginal per-sample cost.
SPEEXDSP_CONF := $(filter-out --enable-resample-full-sinc-table,$(SPEEXDSP_CONF))
endif
ifeq ($(ARCH),aarch64)
# old neon, not compatible with aarch64
SPEEXDSP_CONF += --disable-neon
endif
ifndef HAVE_NEON
SPEEXDSP_CONF += --disable-neon
endif
ifndef HAVE_FPU
SPEEXDSP_CONF += --enable-fixed-point
ifeq ($(ARCH),arm)
SPEEXDSP_CONF += --enable-arm5e-asm
endif
endif

.speexdsp: speexdsp
	$(RECONF)
	cd $< && $(HOSTVARS) ./configure $(HOSTCONF) $(SPEEXDSP_CONF)
	$(MAKE) -C $<
	$(call pkg_static,"speexdsp.pc")
	$(MAKE) -C $< install
	touch $@
