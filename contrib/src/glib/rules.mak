# GLIB
GLIB_VERSION := 2.38
GLIB_MINOR_VERSION := 2.38.2
GLIB_URL := http://ftp.gnome.org/pub/gnome/sources/glib/$(GLIB_VERSION)/glib-$(GLIB_MINOR_VERSION).tar.xz

ifeq ($(call need_pkg,"glib-2.0 gthread-2.0"),)
PKGS_FOUND += glib
endif

DEPS_glib = ffi $(DEPS_ffi)

# GLib 2.38 otherwise tries to execute a target probe while cross-compiling.
# All PowerVLC targets supported here use a downward-growing stack.
GLIB_CONF := glib_cv_stack_grows=no glib_cv_uscore=no \
	ac_cv_func_posix_getpwuid_r=yes ac_cv_func_posix_getgrgid_r=yes

# The current macOS SDK declares the *at()/fdopendir() family even when the
# deployment target predates their macOS 10.10 implementation.  GLib's link
# probes therefore produce false positives and its sources then fail the
# availability checks (or would crash on the old OS).  Use GLib's portable
# pathname fallback on every Darwin slice.
ifdef HAVE_DARWIN_OS
GLIB_CONF += ac_cv_func_fstatat=no ac_cv_func_openat=no \
	ac_cv_func_fdopendir=no
endif

# GLib uses these generators while building its tests and resources.  The
# contrib PATH starts with $(PREFIX)/bin, which can contain generators from a
# previous target build; when cross-compiling that makes an ARM host try to
# execute a PowerPC/i386 binary.  Pin the tools found in the native make
# environment before HOSTVARS prepends the target prefix.
ifdef HAVE_CROSS_COMPILE
GLIB_NATIVE_GENMARSHAL := $(shell command -v glib-genmarshal 2>/dev/null)
GLIB_NATIVE_COMPILE_SCHEMAS := $(shell command -v glib-compile-schemas 2>/dev/null)
GLIB_NATIVE_COMPILE_RESOURCES := $(shell command -v glib-compile-resources 2>/dev/null)
ifneq ($(GLIB_NATIVE_GENMARSHAL),)
GLIB_CONF += GLIB_GENMARSHAL="$(GLIB_NATIVE_GENMARSHAL)"
endif
ifneq ($(GLIB_NATIVE_COMPILE_RESOURCES),)
GLIB_CONF += GLIB_COMPILE_RESOURCES="$(GLIB_NATIVE_COMPILE_RESOURCES)"
endif
ifneq ($(GLIB_NATIVE_COMPILE_SCHEMAS),)
GLIB_CONF += GLIB_COMPILE_SCHEMAS="$(GLIB_NATIVE_COMPILE_SCHEMAS)"
endif
endif

$(TARBALLS)/glib-$(GLIB_MINOR_VERSION).tar.xz:
	$(call download_pkg,$(GLIB_URL),glib)

.sum-glib: glib-$(GLIB_MINOR_VERSION).tar.xz

glib: glib-$(GLIB_MINOR_VERSION).tar.xz .sum-glib \
	$(wildcard $(SRC)/glib/*.patch)
	$(UNPACK)
	$(APPLY) $(SRC)/glib/clang-atomic-pointer.patch
	$(APPLY) $(SRC)/glib/llvm-mingw-arm64-breakpoint.patch
	$(APPLY) $(SRC)/glib/valgrind-mingw-architecture.patch
	$(APPLY) $(SRC)/glib/mingw-wstat-layout.patch
	$(APPLY) $(SRC)/glib/llvm-mingw-pointer-atomics.patch
	$(APPLY) $(SRC)/glib/mingw-static-init-order.patch
	$(APPLY) $(SRC)/glib/apple-parameter-macros.patch
	$(APPLY) $(SRC)/glib/darwin-pre-1010-no-at-functions.patch
	$(APPLY) $(SRC)/glib/python312-no-imp.patch
	$(MOVE)

.glib: glib
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) --disable-compile-warnings $(GLIB_CONF)
	+$(MAKEBUILD)
	+$(MAKEBUILD) install
	touch $@
