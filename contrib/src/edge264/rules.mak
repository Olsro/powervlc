# Edge264 -- H.264/AVC and MVC decoder used by SyLC

EDGE264_HASH := 1ac224cb566928ee55f4eacd4adc53eef502f1a1
EDGE264_GITURL := https://github.com/5ymph0en1x/SyLC.git

# Blu-ray MVC is relevant to the two desktop architectures on which Edge264
# currently has optimized backends.  Other VLC targets simply build without
# the optional decoder module.
ifeq ($(ARCH),$(filter $(ARCH),aarch64 x86_64 i386))
PKGS += edge264
endif

ifeq ($(call need_pkg,"edge264"),)
PKGS_FOUND += edge264
endif

$(TARBALLS)/edge264-$(EDGE264_HASH).tar.xz:
	$(call download_git,$(EDGE264_GITURL),,$(EDGE264_HASH))

.sum-edge264: edge264-$(EDGE264_HASH).tar.xz
	$(call check_githash,$(EDGE264_HASH))
	touch $@

edge264: edge264-$(EDGE264_HASH).tar.xz .sum-edge264 \
	$(wildcard $(SRC)/edge264/*.patch)
	$(UNPACK)
	find $(UNPACK_DIR)/edge264 -type f \( -name '*.c' -o -name '*.h' \) -exec perl -pi -e 's/\r$$//' {} +
	$(APPLY) $(SRC)/edge264/0001-pair-mvc-views-by-picture-order-count.patch
	$(APPLY) $(SRC)/edge264/0002-macos-legacy-aligned-allocation.patch
	$(APPLY) $(SRC)/edge264/0003-lock-borrowed-frame-return.patch
	$(APPLY) $(SRC)/edge264/0004-propagate-input-timestamps.patch
	$(APPLY) $(SRC)/edge264/0005-break-post-seek-self-dependencies.patch
	$(APPLY) $(SRC)/edge264/0006-darwin-legacy-cpu-count.patch
	$(APPLY) $(SRC)/edge264/0007-i386-runtime-sse41.patch
	$(APPLY) $(SRC)/edge264/0008-inject-external-mvc-base-view.patch
	$(MOVE)

EDGE264_CFLAGS = $(CFLAGS) -std=gnu17 -O3 -fno-strict-aliasing -flax-vector-conversions

DEPS_edge264 =
ifdef HAVE_WIN32
DEPS_edge264 += winpthreads $(DEPS_winpthreads)
endif

.edge264: edge264
ifeq ($(ARCH),x86_64)
	cd $< && $(HOSTVARS) $(CC) $(EDGE264_CFLAGS) -DHAS_X86_SSE41 -DHAS_X86_64_V2 -DHAS_X86_64_V3 -c edge264/src/edge264.c -o edge264/e264_base.o
	cd $< && $(HOSTVARS) $(CC) $(EDGE264_CFLAGS) -mtune=core2 -mssse3 -msse4.1 '-DADD_VARIANT(f)=f##_sse41' -include edge264/src/edge264_internal.h -c edge264/src/edge264_headers.c -o edge264/e264_sse41.o
	cd $< && $(HOSTVARS) $(CC) $(EDGE264_CFLAGS) -march=x86-64-v2 '-DADD_VARIANT(f)=f##_v2' -include edge264/src/edge264_internal.h -c edge264/src/edge264_headers.c -o edge264/e264_v2.o
	cd $< && $(HOSTVARS) $(CC) $(EDGE264_CFLAGS) -march=x86-64-v3 '-DADD_VARIANT(f)=f##_v3' -include edge264/src/edge264_internal.h -c edge264/src/edge264_headers.c -o edge264/e264_v3.o
	cd $< && $(AR) cr edge264/libedge264.a edge264/e264_base.o edge264/e264_sse41.o edge264/e264_v2.o edge264/e264_v3.o
else ifeq ($(ARCH),i386)
	# Edge264's x86 backend uses SSE2 for its baseline vector primitives; the
	# separately compiled SSE4.1 parser remains guarded by the runtime dispatch.
	cd $< && $(HOSTVARS) $(CC) $(EDGE264_CFLAGS) -fomit-frame-pointer -mtune=core2 -msse2 -DHAS_X86_SSE41 -c edge264/src/edge264.c -o edge264/e264_base.o
	cd $< && $(HOSTVARS) $(CC) $(EDGE264_CFLAGS) -fomit-frame-pointer -mtune=core2 -mssse3 -msse4.1 '-DADD_VARIANT(f)=f##_sse41' -include edge264/src/edge264_internal.h -c edge264/src/edge264_headers.c -o edge264/e264_sse41.o
	cd $< && $(AR) cr edge264/libedge264.a edge264/e264_base.o edge264/e264_sse41.o
else
	cd $< && $(HOSTVARS) $(CC) $(EDGE264_CFLAGS) -c edge264/src/edge264.c -o edge264/e264_base.o
	cd $< && $(AR) cr edge264/libedge264.a edge264/e264_base.o
endif
	cd $< && $(RANLIB) edge264/libedge264.a
	mkdir -p $(PREFIX)/include $(PREFIX)/lib/pkgconfig $(PREFIX)/lib
	cp $</edge264/edge264.h $(PREFIX)/include/edge264.h
	cp $</edge264/libedge264.a $(PREFIX)/lib/libedge264.a
	sed 's#@PREFIX@#$(PREFIX)#g' $(SRC)/edge264/edge264.pc.in > $(PREFIX)/lib/pkgconfig/edge264.pc
	touch $@
