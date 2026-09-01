# libplacebo

# Dolby Vision FEL composition was added after the v7 releases (API 366-369).
# Keep the exact revision reproducible: apart from the main tree, the OpenGL
# loader generator needs the submodule commits recorded by this revision.
PLACEBO_NEXT_HASH := 22ee762e8e0890fc54068beb670310f0edce7263
PLACEBO_NEXT_VERSION := 7.371.0
PLACEBO_NEXT_ARCHIVE := libplacebo-$(PLACEBO_NEXT_HASH).tar.xz
PLACEBO_NEXT_URL := https://code.videolan.org/videolan/libplacebo.git

# VLC 3's old shader adapter is tied to libplacebo < 6. Preserve it for the
# legacy 32-bit/PowerPC targets; modern 64-bit targets use the renderer API
# which can combine Dolby Vision BL, FEL and RPU.
PLACEBO_LEGACY_VERSION := 0.2.1
PLACEBO_LEGACY_ARCHIVE := libplacebo-$(PLACEBO_LEGACY_VERSION).tar.gz
PLACEBO_LEGACY_URL := https://github.com/haasn/libplacebo/archive/v$(PLACEBO_LEGACY_VERSION).tar.gz

PKGS += libplacebo

ifneq ($(filter aarch64 x86_64,$(ARCH)),)

ifeq ($(call need_pkg,"libplacebo >= $(PLACEBO_NEXT_VERSION)"),)
PKGS_FOUND += libplacebo
endif

PLACEBO_NEXT_CONF := \
	-Dvulkan=disabled \
	-Dd3d11=disabled \
	-Dopengl=enabled \
	-Dgl-proc-addr=disabled \
	-Ddovi=enabled \
	-Dlibdovi=disabled \
	-Dglslang=disabled \
	-Dshaderc=disabled \
	-Dlcms=disabled \
	-Ddemos=false \
	-Dtests=false \
	-Dbench=false \
	-Dfuzz=false \
	-Dunwind=disabled \
	-Dxxhash=disabled

# The only C++ code in this otherwise C library is fast_float, which does not
# throw.  MinGW nevertheless emits an exception personality reference by
# default; consumers of libplacebo are C plug-ins and consequently do not pull
# the C++ runtime in at link time.  Avoid the unused runtime dependency instead
# of making every OpenGL plug-in link libstdc++ (which would also be wrong for
# the llvm-mingw/ARM64 libc++ toolchain).
ifdef HAVE_WIN32
PLACEBO_NEXT_CONF += -Dcpp_args=-fno-exceptions
endif

$(TARBALLS)/$(PLACEBO_NEXT_ARCHIVE):
	rm -Rf -- "$(TARBALLS)/libplacebo-$(PLACEBO_NEXT_HASH)"
	$(GIT) clone --no-checkout "$(PLACEBO_NEXT_URL)" "$(TARBALLS)/libplacebo-$(PLACEBO_NEXT_HASH)"
	$(GIT) -C "$(TARBALLS)/libplacebo-$(PLACEBO_NEXT_HASH)" checkout --detach "$(PLACEBO_NEXT_HASH)"
	$(GIT) -C "$(TARBALLS)/libplacebo-$(PLACEBO_NEXT_HASH)" submodule update --init --depth 1 \
		3rdparty/glad 3rdparty/jinja 3rdparty/markupsafe 3rdparty/fast_float \
		3rdparty/Vulkan-Headers
	find "$(TARBALLS)/libplacebo-$(PLACEBO_NEXT_HASH)" -name .git -prune -exec rm -Rf -- {} \;
	cd "$(TARBALLS)" && tar cJf "$(PLACEBO_NEXT_ARCHIVE).tmp" "libplacebo-$(PLACEBO_NEXT_HASH)"
	mv -f -- "$(TARBALLS)/$(PLACEBO_NEXT_ARCHIVE).tmp" "$@"
	echo "$(PLACEBO_NEXT_HASH) $@" > "$(@:.tar.xz=.githash)"
	rm -Rf -- "$(TARBALLS)/libplacebo-$(PLACEBO_NEXT_HASH)"

.sum-libplacebo: $(PLACEBO_NEXT_ARCHIVE)
	$(call check_githash,$(PLACEBO_NEXT_HASH))
	touch $@

libplacebo: $(PLACEBO_NEXT_ARCHIVE) .sum-libplacebo \
	$(wildcard $(SRC)/libplacebo/*.patch)
	$(UNPACK)
	$(APPLY) $(SRC)/libplacebo/mingw-charconv-fallback.patch
	$(MOVE)

.libplacebo: libplacebo crossfile.meson
	$(MESONCLEAN)
	$(MESON) $(PLACEBO_NEXT_CONF)
	+$(MESONBUILD)
	touch $@

else

ifeq ($(call need_pkg,"libplacebo"),)
PKGS_FOUND += libplacebo
endif

LIBPLACEBO_CFLAGS   := $(CFLAGS)
LIBPLACEBO_CXXFLAGS := $(CXXFLAGS)
ifdef HAVE_WIN32
LIBPLACEBO_WIN32 = HAVE_WIN32=1
endif

$(TARBALLS)/$(PLACEBO_LEGACY_ARCHIVE):
	$(call download_pkg,$(PLACEBO_LEGACY_URL),libplacebo)

.sum-libplacebo: $(PLACEBO_LEGACY_ARCHIVE)

libplacebo: $(PLACEBO_LEGACY_ARCHIVE) .sum-libplacebo
	$(UNPACK)
	$(APPLY) $(SRC)/libplacebo/0001-build-use-a-Makefile.patch
	$(APPLY) $(SRC)/libplacebo/0001-ta_utils-avoid-strnlen-for-old-macOS.patch
	$(MOVE)

.libplacebo: libplacebo
	cd $< && rm -rf ./build
	cd $< && $(HOSTVARS_PIC) PREFIX=$(PREFIX) $(LIBPLACEBO_WIN32) CFLAGS="$(LIBPLACEBO_CFLAGS)" CXXFLAGS="$(LIBPLACEBO_CXXFLAGS)" make install
	touch $@

endif
