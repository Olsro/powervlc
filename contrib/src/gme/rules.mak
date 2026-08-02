# Game Music Emu

GME_VERSION := 0.6.5
GME_URL := $(GITHUB)/libgme/game-music-emu/archive/refs/tags/$(GME_VERSION).tar.gz

PKGS += gme

$(TARBALLS)/game-music-emu-$(GME_VERSION).tar.gz:
	$(call download_pkg,$(GME_URL),gme)

DEPS_gme = zlib $(DEPS_zlib)

.sum-gme: game-music-emu-$(GME_VERSION).tar.gz

game-music-emu: game-music-emu-$(GME_VERSION).tar.gz .sum-gme
	$(UNPACK)
	$(call pkg_static,"gme/libgme.pc.in")
	$(MOVE)

GME_CONF := -DENABLE_UBSAN=OFF
# player/CMakeLists.txt does an optional find_package(SDL2) purely to build a
# demo player we do not ship. On a machine with Homebrew SDL2 installed CMake
# picks up /opt/homebrew/lib/cmake/SDL2 and dies on its imported target, so the
# build depended on which brew formulae were present. Tell CMake the package is
# unavailable; the CMakeLists already handles that ("disabling player demo").
GME_CONF += -DCMAKE_DISABLE_FIND_PACKAGE_SDL2=ON

.gme: game-music-emu toolchain.cmake
	$(CMAKECLEAN)
	$(HOSTVARS_CMAKE) $(CMAKE) $(GME_CONF)
	+$(CMAKEBUILD)
	$(CMAKEINSTALL)
	touch $@
