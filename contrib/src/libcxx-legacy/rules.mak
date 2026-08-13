# LIBCXX-LEGACY
#
# The macOS SDK only ships libc++.dylib starting with Mac OS X 10.9;
# targeting an older release with the default -stdlib=libc++ means every
# C++ plugin (libmatroska, live555, TagLib, x265...) fails to load at
# runtime there. This package builds a self-contained libc++/libc++abi
# from source and bundles it into VLC.app instead of relying on the OS.
#
# LLVM 8.0.0 is deliberately used instead of a newer release: libc++'s
# std::ios_base::Init (constructed as soon as any consumer links
# <iostream>) crashes on startup when libc++ itself is built with a
# very old -mmacosx-version-min, for every LLVM release from 9.0.0
# onwards that was tested (through at least 19.1.0); this is an
# upstream libc++ bug that as of this writing has no fix (see
# llvm/llvm-project issues #111570 and #109782 for reports of the same
# crash signature). LLVM 8.0.0 is the newest release confirmed not to
# regress; this was found by bisecting LLVM releases 5.0.0 through
# 18.1.8 directly against this deployment target. Do not "helpfully"
# bump this version without re-validating that the resulting libc++
# actually runs (compiling cleanly is not sufficient: the crash above
# only manifests at runtime, in std::ios_base::Init's constructor).
#
# libunwind is intentionally not part of this package: libc++abi is
# built against the system's own unwinder (already relied upon by
# libstdc++ for C++ exceptions since long before Mac OS X 10.5), which
# avoids a separate dylib to bundle and sidesteps linker issues where
# -isysroot causes -lunwind to resolve against the SDK's own (link-only)
# stub instead of a custom-built library.
#
# Anything linking against this libc++ must be compiled against ITS
# headers (see LIBCXX_LEGACY_CXXFLAGS below), not the SDK's libc++
# headers: the two are different enough (this is an old release) that
# mixing compile-time layout from one with the runtime implementation
# of the other risks ABI mismatches. Likewise, always link
# -lc++abi before -lc++ explicitly: libc++'s automatic re-export of
# libc++abi's symbols has proven unreliable across several LLVM
# releases when the ABI library isn't the SDK's own.

LIBCXX_LEGACY_VERSION := 8.0.0
LIBCXX_LEGACY_URL_BASE := https://releases.llvm.org/$(LIBCXX_LEGACY_VERSION)

ifdef HAVE_DARWIN_OS
ifneq ($(call darwin_min_os_at_least, 10.9), true)
# Only needed for clang builds (-stdlib=libc++); the legacy ppc/i386
# cross builds use FSF g++, whose (static) libstdc++ replaces this.
ifdef HAVE_CLANG
PKGS += libcxx-legacy
endif
endif
endif

$(TARBALLS)/llvm-$(LIBCXX_LEGACY_VERSION).src.tar.xz:
	$(call download_pkg,$(LIBCXX_LEGACY_URL_BASE)/llvm-$(LIBCXX_LEGACY_VERSION).src.tar.xz,libcxx-legacy)

$(TARBALLS)/libcxx-$(LIBCXX_LEGACY_VERSION).src.tar.xz:
	$(call download_pkg,$(LIBCXX_LEGACY_URL_BASE)/libcxx-$(LIBCXX_LEGACY_VERSION).src.tar.xz,libcxx-legacy)

$(TARBALLS)/libcxxabi-$(LIBCXX_LEGACY_VERSION).src.tar.xz:
	$(call download_pkg,$(LIBCXX_LEGACY_URL_BASE)/libcxxabi-$(LIBCXX_LEGACY_VERSION).src.tar.xz,libcxx-legacy)

.sum-libcxx-legacy: llvm-$(LIBCXX_LEGACY_VERSION).src.tar.xz \
                    libcxx-$(LIBCXX_LEGACY_VERSION).src.tar.xz \
                    libcxxabi-$(LIBCXX_LEGACY_VERSION).src.tar.xz
	$(CHECK_SHA512)

libcxx-legacy: llvm-$(LIBCXX_LEGACY_VERSION).src.tar.xz \
               libcxx-$(LIBCXX_LEGACY_VERSION).src.tar.xz \
               libcxxabi-$(LIBCXX_LEGACY_VERSION).src.tar.xz \
               .sum-libcxx-legacy
	$(RM) -Rf $@ $@.tmp
	mkdir -p $@.tmp
	tar xJf $(TARBALLS)/llvm-$(LIBCXX_LEGACY_VERSION).src.tar.xz -C $@.tmp
	tar xJf $(TARBALLS)/libcxx-$(LIBCXX_LEGACY_VERSION).src.tar.xz -C $@.tmp
	tar xJf $(TARBALLS)/libcxxabi-$(LIBCXX_LEGACY_VERSION).src.tar.xz -C $@.tmp
	mv $@.tmp/llvm-$(LIBCXX_LEGACY_VERSION).src $@.tmp/llvm
	mv $@.tmp/libcxx-$(LIBCXX_LEGACY_VERSION).src $@.tmp/libcxx
	mv $@.tmp/libcxxabi-$(LIBCXX_LEGACY_VERSION).src $@.tmp/libcxxabi
	# ⚠ libc++abi links against a HARDCODED /usr/lib/libSystem.B.dylib
	# (src/CMakeLists.txt), a path that no longer exists on disk since the
	# system dylibs moved into the dyld shared cache: the link dies with
	# "no such file or directory". The SDK ships the stub the linker really
	# wants, usr/lib/libSystem.B.tbd, so point at that one -- through
	# CMAKE_OSX_SYSROOT, which the shared toolchain.cmake does set, so this
	# keeps working whatever SDK is in use.
	sed -i.orig 's|"/usr/lib/libSystem.B.dylib"|"$${CMAKE_OSX_SYSROOT}/usr/lib/libSystem.B.tbd"|' \
		$@.tmp/libcxxabi/src/CMakeLists.txt
	# ⚠ libc++ refuse la cible 10.6 par un FATAL_ERROR, sur une comparaison
	# LITTÉRALE à la chaîne « 10.6 » -- d'où le fait que 10.5 passait très
	# bien. Le refus vise le libc++ DU SYSTÈME (la liste de ré-export de
	# l'époque) ; nous embarquons le nôtre, et la branche else prend la même
	# liste que pour 10.5 comme pour 10.7. On neutralise donc la condition
	# plutôt que la cible, qui doit rester celle de la tranche.
	sed -i.orig 's|if ( CMAKE_OSX_DEPLOYMENT_TARGET STREQUAL "10.6" )|if ( FALSE )|' \
		$@.tmp/libcxx/lib/CMakeLists.txt
	# Tarball mtimes are ancient (2018-vintage LLVM release) and clustered
	# to the second; normalize to now so nothing downstream (CMake's own
	# try_compile machinery included) makes a wrong same-second/stale-file
	# call against them.
	find $@.tmp -exec touch {} +
	mv $@.tmp $@
	touch $@

# Exposed for configure.ac/the main build to compile and link any C++
# code against this libc++ instead of the SDK's.
LIBCXX_LEGACY_CXXFLAGS = -nostdinc++ -D_LIBCPP_DISABLE_AVAILABILITY \
	-isystem $(PREFIX)/include/c++/v1
LIBCXX_LEGACY_LIBS = -L$(PREFIX)/lib -Wl,-rpath,$(PREFIX)/lib -lc++abi -lc++

# The shared toolchain.cmake sets CMAKE_C_FLAGS/CMAKE_CXX_FLAGS with a
# plain set() call, which (being a toolchain file, processed before
# project()) shadows any -DCMAKE_CXX_FLAGS=... passed on the cmake
# command line for the rest of configuration. Layer our own defines on
# top in a package-specific toolchain file instead of fighting that.
#
# -D_LIBCPP_HAS_NO_ALIGNED_ALLOCATION: libc++ builds itself in a newer
# C++ mode than the -std=c++11 VLC's own code uses, purely to expose
# every symbol (e.g. the C++17 aligned new/delete overloads) to any
# consumer regardless of the -std it happens to compile with. Those
# aligned overloads unconditionally call posix_memalign(), which is
# only available from Mac OS X 10.6, so they must not be built at all
# for this deployment target -- VLC's own code targets C++11 and never
# calls them anyway.
#
# -Wno-partial-availability: belt-and-suspenders alongside the above.
# The shared CFLAGS/CXXFLAGS carry VLC's own -Werror=partial-availability
# (added to catch VLC's own code calling APIs newer than its deployment
# target). libc++/libc++abi are third-party code we are not going to
# comb through function-by-function for every other such call site, so
# silence it for this package specifically rather than pretend to
# audit upstream's.
#
# CMAKE_SYSTEM_VERSION: VLC's contrib build uses its own bundled CMake
# (extras/tools/build/bin/cmake, currently 3.17.0) rather than whatever
# cmake happens to be first on PATH interactively -- this matters here
# because that old CMake's Modules/Platform/Darwin.cmake only enables
# rpath support ("Enable rpath support for 10.5 and greater where it is
# known to work") when CMAKE_SYSTEM_VERSION's major component is
# greater than 8. The shared toolchain.cmake sets CMAKE_SYSTEM_NAME
# explicitly (this is a cross-compile: Apple Silicon BUILD, x86_64
# HOST) but never sets CMAKE_SYSTEM_VERSION, so it defaults to empty,
# DARWIN_MAJOR_VERSION parses as empty too, and that rpath-enabling
# branch is silently skipped -- CMAKE_SHARED_LIBRARY_RUNTIME_C_FLAG
# never gets a value, and libcxx's shared library target (the only
# contrib CMake target that is actually a .dylib; every other
# CMake-based contrib package only builds static libraries, which is
# why this has gone unnoticed until now) fails with "Attempting to use
# @rpath without CMAKE_SHARED_LIBRARY_RUNTIME_C_FLAG being set". Note
# this DARWIN_MAJOR_VERSION only gates whether the *build host*
# supports rpath at all (true for any host new enough to run this
# build in the first place) -- it has nothing to do with our 10.5
# deployment *target*, so any value greater than 8 is correct here.
libcxx-legacy-toolchain.cmake: toolchain.cmake
	cp toolchain.cmake $@
	echo "set(CMAKE_SYSTEM_VERSION \"$$(uname -r)\")" >> $@
	echo 'set(CMAKE_C_FLAGS "$${CMAKE_C_FLAGS} -D_LIBCPP_DISABLE_AVAILABILITY -D_LIBCPP_HAS_NO_ALIGNED_ALLOCATION -Wno-partial-availability")' >> $@
	echo 'set(CMAKE_CXX_FLAGS "$${CMAKE_CXX_FLAGS} -D_LIBCPP_DISABLE_AVAILABILITY -D_LIBCPP_HAS_NO_ALIGNED_ALLOCATION -Wno-partial-availability")' >> $@

.libcxx-legacy: libcxx-legacy libcxx-legacy-toolchain.cmake
	# Stage 1/2: libc++abi, against the system unwinder (see comment above)
	$(RM) -Rf $</build-cxxabi
	cmake -S $</libcxxabi -B $</build-cxxabi \
		-DCMAKE_TOOLCHAIN_FILE=$(abspath libcxx-legacy-toolchain.cmake) \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=$(VLC_DEPLOYMENT_TARGET) \
		-DLLVM_PATH=$(abspath $</llvm) \
		-DLIBCXXABI_LIBCXX_PATH=$(abspath $</libcxx) \
		-DLIBCXXABI_LIBCXX_INCLUDES=$(abspath $</libcxx/include) \
		-DLIBCXXABI_USE_LLVM_UNWINDER=OFF \
		-DLIBCXXABI_ENABLE_SHARED=ON \
		-DLIBCXXABI_ENABLE_STATIC=OFF \
		-DCMAKE_MACOSX_RPATH=OFF \
		-DCMAKE_INSTALL_PREFIX:STRING=$(PREFIX) \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build $</build-cxxabi
	cmake --install $</build-cxxabi

	# Stage 2/2: libc++, linked against the libc++abi just installed
	$(RM) -Rf $</build-cxx
	cmake -S $</libcxx -B $</build-cxx \
		-DCMAKE_TOOLCHAIN_FILE=$(abspath libcxx-legacy-toolchain.cmake) \
		-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
		-DCMAKE_OSX_DEPLOYMENT_TARGET=$(VLC_DEPLOYMENT_TARGET) \
		-DLLVM_PATH=$(abspath $</llvm) \
		-DLIBCXX_CXX_ABI=libcxxabi \
		-DLIBCXX_CXX_ABI_INCLUDE_PATHS=$(abspath $</libcxxabi/include) \
		-DLIBCXX_CXX_ABI_LIBRARY_PATH=$(PREFIX)/lib \
		-DLIBCXX_ENABLE_SHARED=ON \
		-DLIBCXX_ENABLE_STATIC=OFF \
		-DLIBCXX_INCLUDE_TESTS=OFF \
		-DLIBCXX_INCLUDE_BENCHMARKS=OFF \
		-DLIBCXX_ENABLE_FILESYSTEM=OFF \
		-DLIBCXX_OSX_REEXPORT_LIBCXXABI_SYMBOLS=OFF \
		-DCMAKE_EXE_LINKER_FLAGS=-Wl,-rpath,$(PREFIX)/lib \
		-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-rpath,$(PREFIX)/lib \
		-DCMAKE_MACOSX_RPATH=OFF \
		-DCMAKE_INSTALL_PREFIX:STRING=$(PREFIX) \
		-DCMAKE_BUILD_TYPE=Release
	cmake --build $</build-cxx
	cmake --install $</build-cxx
	touch $@
