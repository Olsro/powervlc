# GLEW
GLEW_VERSION := 2.3.1
GLEW_URL := $(GITHUB)/nigels-com/glew/releases/download/glew-$(GLEW_VERSION)/glew-$(GLEW_VERSION).tgz

ifdef HAVE_WIN32
# glwin32 and wgl are first-class Windows video outputs.  Do not rely on
# projectM to pull GLEW in indirectly: projectM is disabled by the release
# build, which otherwise silently removes both OpenGL plugins.
PKGS += glew
endif

ifeq ($(call need_pkg,"glew"),)
PKGS_FOUND += glew
endif

$(TARBALLS)/glew-$(GLEW_VERSION).tgz:
	$(call download_pkg,$(GLEW_URL),glew)

.sum-glew: glew-$(GLEW_VERSION).tgz

glew: glew-$(GLEW_VERSION).tgz .sum-glew
	$(UNPACK)
	$(APPLY) $(SRC)/glew/0001-Define-GLEW_STATIC-in-pkg-config-file-when-compiled-.patch
	$(APPLY) $(SRC)/glew/0002-Link-with-opengl32-on-Windows.patch
	$(APPLY) $(SRC)/glew/0003-Link-directly-with-glu32-on-Windows.patch
	$(APPLY) $(SRC)/glew/0004-Allow-disabling-the-CMAKE_DEBUG_POSTFIX.patch
	$(APPLY) $(SRC)/glew/0005-Do-not-force-compiler-flag.patch
	$(APPLY) $(SRC)/glew/0006-Do-not-compile-the-shared-library-with-DBUILD_SHARED.patch
	$(MOVE)

GLEW_CONF := -DBUILD_UTILS=OFF

.glew: glew toolchain.cmake
	$(CMAKECLEAN)
	$(HOSTVARS_CMAKE) $(CMAKE) -S $</build/cmake $(GLEW_CONF)
	+$(CMAKEBUILD)
	$(CMAKEINSTALL)
	touch $@
