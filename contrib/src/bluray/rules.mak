# LIBBLURAY

BLURAY_VERSION := 1.4.0
BLURAY_URL := $(VIDEOLAN)/libbluray/$(BLURAY_VERSION)/libbluray-$(BLURAY_VERSION).tar.xz

ifdef BUILD_DISCS
PKGS += bluray
endif
ifeq ($(call need_pkg,"libbluray >= 1.0.0"),)
PKGS_FOUND += bluray
endif

ifdef HAVE_ANDROID
WITH_FONTCONFIG = 0
else
ifdef HAVE_DARWIN_OS
WITH_FONTCONFIG = 0
else
ifdef HAVE_WIN32
WITH_FONTCONFIG = 0
else
WITH_FONTCONFIG = 1
endif
endif
endif

DEPS_bluray = libxml2 $(DEPS_libxml2) freetype2 $(DEPS_freetype2)

# --- BD-J (Blu-ray Java menus) ---------------------------------------------
# The BD-J .jar must stay loadable by a Java 5 JRE: Mac OS X 10.4 and 10.5 on
# PowerPC top out at Apple's Java 1.5.0_19 (Java 6 on Mac was Intel-only, and
# the community PowerPC port of it is not something a release should depend
# on). Java 5 bytecode (class file v49) still loads fine on Java 8+ everywhere
# else, so targeting it costs nothing on Windows/Linux/modern macOS.
#
# Two independent things have to line up for that.
#
# 1. The bytecode version. libbluray defaults java_src_version to 1.5 and only
#    raises it when the java9 option is on, in which case it derives it from
#    whichever javac it finds:
#      javac 9..11 -> 1.6   javac 12..17 -> 1.7   javac >= 18 -> 1.8
#    (see src/libbluray/bdj/meson.build). So java9 is turned off below, and the
#    JDK is pinned here rather than taken from the ambient PATH -- otherwise
#    the runtime requirement of a release would depend on the build host.
#    javac 9 dropped -source/-target 1.5, so this needs a JDK 8; without one
#    (and ant) BD-J is switched off explicitly rather than silently producing a
#    jar the old machines cannot load.
#
# 2. The JDK internals the BD-J code replaces. java.io.FileSystem,
#    java.awt.peer.ComponentPeer and FramePeer changed shape between Java 5 and
#    Java 6, and java.awt.Container.{get,set}ComponentZOrder are final in Java 5
#    -- so a -target 1.5 jar built from upstream sources would load and then die.
#    0004-bdj-run-on-java-5.patch closes that; read its header for the details.
#
# Override BLURAY_JDK_HOME to skip the probe or to use another JDK.
#
# Pinning the bytecode version does not stop javac from linking against APIs
# added later, which would only fail at runtime on the old machines. Two
# complementary answers to that:
#   - check-bdj-java6.py runs after the build and fails it if the jars reference
#     any documented API newer than Java 6 (resolved against the JDK's ct.sym).
#     Java 6 and not 5 because ct.sym only goes back to release 6 -- no JDK ever
#     shipped Java 5 API data. What the patch above adds is deliberately allowed
#     to reference Java 6 members, since those methods are unreachable on a
#     Java 5 VM; the check therefore stays at 6 by design, and the Java 5
#     guarantee comes from the patch plus BLURAY_JAVA5_API below;
#   - BLURAY_BDJ_BOOTCLASSPATH, pointing at a real Java 6 rt.jar, additionally
#     covers the JDK internals (sun.*) that ct.sym does not describe. It stays a
#     Java 6 rt.jar on purpose: the compatibility methods must see the Java 6
#     shapes to compile, and reach the Java 5 ones through reflection.
#   - check-bdj-java5.py resolves the jars against BLURAY_JAVA5_API, an index of
#     what a real Java 5 JRE declares, and proves nothing outside that known set
#     needs Java 6. That index is committed; see contrib/java5-api/README for
#     why it is an index and not a class library.
BLURAY_JDK_HOME ?= $(shell \
	for d in "$$(/usr/libexec/java_home -v 1.8 2>/dev/null)" \
	         "$(HOME)"/.sdkman/candidates/java/8* \
	         /Library/Java/JavaVirtualMachines/*1.8*/Contents/Home \
	         /usr/lib/jvm/java-8-*; do \
		test -x "$$d/bin/javac" || continue; \
		"$$d/bin/javac" -version 2>&1 | grep -qE '^javac 1\.8\.' || continue; \
		echo "$$d"; break; \
	done)
# Flatten, so the probe above does not run again on every expansion.
BLURAY_JDK_HOME := $(BLURAY_JDK_HOME)
BLURAY_ANT := $(shell command -v ant 2>/dev/null)
BLURAY_PYTHON := $(shell command -v python3 2>/dev/null)
# Every .jar in BLURAY_JAVA6_DIR becomes the compile-time boot class path. It
# holds the OpenJDK 6 rt.jar (GPLv2+CE, so it can live in the tree), archived
# so the build depends on neither the network nor an old machine being up.
# See java6-bootclasspath/README for provenance and licensing.
BLURAY_JAVA6_DIR ?= $(SRC)/../java6-bootclasspath
BLURAY_BDJ_BOOTCLASSPATH ?= $(shell ls $(BLURAY_JAVA6_DIR)/*.jar 2>/dev/null \
	| tr '\n' ':' | sed 's/:$$//')
BLURAY_BDJ_BOOTCLASSPATH := $(BLURAY_BDJ_BOOTCLASSPATH)
# Same jars, as --runtime arguments for the post-build API check.
BLURAY_JAVA6_RUNTIME := $(patsubst %,--runtime %,\
	$(subst :, ,$(BLURAY_BDJ_BOOTCLASSPATH)))
# The Java 5 API index the built jars are verified against (never compiled
# against). An index rather than a class library because none is
# redistributable for Java 5; see contrib/java5-api/README.
BLURAY_JAVA5_API ?= $(wildcard $(SRC)/../java5-api/*.txt.gz)

# ct.sym for the Java 6 check, which is a different JDK from the one that
# compiles: historical release data only exists from JDK 9 on (it is what
# --release reads), while emitting Java 5 bytecode needs JDK 8. Probed
# separately so neither requirement drags in the other; without it the Java 6
# check is skipped, and the Java 5 one above carries the load.
# The version is verified rather than inferred from the path: "java_home -v 11"
# happily answers with a much newer JDK when no 11 is installed, and a JDK 21
# ct.sym no longer carries release 6 at all.
BLURAY_CTSYM ?= $(shell \
	for d in "$$(/usr/libexec/java_home -v 11 2>/dev/null)" \
	         "$(HOME)"/.sdkman/candidates/java/1[01]* \
	         /Library/Java/JavaVirtualMachines/*1[01]*/Contents/Home \
	         /usr/lib/jvm/java-1[01]-*; do \
		test -r "$$d/lib/ct.sym" || continue; \
		"$$d/bin/javac" -version 2>&1 | grep -qE '^javac (9|10|11)\.' || continue; \
		echo "$$d/lib/ct.sym"; break; \
	done)
BLURAY_CTSYM := $(BLURAY_CTSYM)

ifneq ($(BLURAY_JDK_HOME),)
ifneq ($(BLURAY_ANT),)
BLURAY_BDJ := 1
endif
endif

BLURAY_CONF = -Dfreetype=enabled -Dlibxml2=enabled

ifdef BLURAY_BDJ
# java9=false leaves libbluray's java_src_version at its 1.5 default instead of
# deriving it from the javac version; see the comment block above.
BLURAY_CONF += -Dbdj_jar=enabled -Dbdj_type=j2se -Djava9=false \
	-Dbdj_bootclasspath="$(BLURAY_BDJ_BOOTCLASSPATH)"
# javac/ant are resolved through PATH by both meson (compiler probe) and ant
# (actual compilation), and ant additionally requires JAVA_HOME.
BLURAY_JAVA_ENV := JAVA_HOME="$(BLURAY_JDK_HOME)" \
	PATH="$(BLURAY_JDK_HOME)/bin:$(PREFIX)/bin:$(PATH)"
BLURAY_BUILD_ENV := export $(BLURAY_JAVA_ENV);
else
BLURAY_CONF += -Dbdj_jar=disabled
endif
ifdef HAVE_CROSS_COMPILE
BLURAY_CONF += -Denable_tools=false
endif

ifneq ($(WITH_FONTCONFIG), 0)
DEPS_bluray += fontconfig $(DEPS_fontconfig)
BLURAY_CONF += -Dfontconfig=enabled

else
BLURAY_CONF += -Dfontconfig=disabled
endif

$(TARBALLS)/libbluray-$(BLURAY_VERSION).tar.xz:
	$(call download,$(BLURAY_URL))

.sum-bluray: libbluray-$(BLURAY_VERSION).tar.xz

bluray: libbluray-$(BLURAY_VERSION).tar.xz .sum-bluray
	$(UNPACK)
	$(APPLY) $(SRC)/bluray/0001-Link-with-gdi32-when-using-freetype-in-Windows.patch
	$(APPLY) $(SRC)/bluray/0002-darwin-dont-define-POSIX_C_SOURCE.patch
	$(APPLY) $(SRC)/bluray/0003-macos-load-Apple-Java-6-through-the-JavaVM-framework.patch
	$(APPLY) $(SRC)/bluray/0004-bdj-run-on-java-5.patch
	$(APPLY) $(SRC)/bluray/0005-add-bd_open_stream_dev.patch
	$(MOVE)

.bluray: MESON_EXTRA_ENV = $(BLURAY_JAVA_ENV)
.bluray: bluray crossfile.meson
	rm -rf $(PREFIX)/share/java/libbluray*.jar
	$(MESONCLEAN)
ifdef BLURAY_BDJ
	@echo "bluray: BD-J menus ON (jar targets Java 5), JDK: $(BLURAY_JDK_HOME)"
ifeq ($(BLURAY_BDJ_BOOTCLASSPATH),)
	@echo "bluray: note: BLURAY_BDJ_BOOTCLASSPATH unset. Documented APIs are"
	@echo "bluray:       still verified after the build, but JDK internals can"
	@echo "bluray:       only be pinned by compiling against a Java 6 rt.jar."
endif
ifeq ($(BLURAY_JAVA5_API),)
	@echo "bluray: note: no Java 5 API index found, so the jars are not checked"
	@echo "bluray:       against the Java 5 floor. See contrib/java5-api/README."
endif
else
	@echo "bluray: BD-J menus OFF (Blu-ray discs with Java menus will play the"
	@echo "bluray:          main title only). Needs ant plus a JDK 8 (javac 9+"
	@echo "bluray:          cannot emit Java 5 bytecode); set BLURAY_JDK_HOME"
	@echo "bluray:          to select one."
endif
	$(MESON) $(BLURAY_CONF)
	+$(BLURAY_BUILD_ENV) $(MESONBUILD)
ifdef BLURAY_BDJ
ifneq ($(BLURAY_PYTHON),)
ifneq ($(BLURAY_CTSYM),)
	$(BLURAY_PYTHON) $(SRC)/bluray/check-bdj-java6.py \
		--ct-sym "$(BLURAY_CTSYM)" \
		$(BLURAY_JAVA6_RUNTIME) $(PREFIX)/share/java/libbluray*.jar
else
	@echo "bluray: note: no JDK 9-11 found, skipping the Java 6 API check"
	@echo "bluray:       (its ct.sym is the only source of per-release API"
	@echo "bluray:       data; set BLURAY_CTSYM to point at one)."
endif
ifneq ($(BLURAY_JAVA5_API),)
	$(BLURAY_PYTHON) $(SRC)/bluray/check-bdj-java5.py \
		$(patsubst %,--api-index %,$(BLURAY_JAVA5_API)) \
		$(PREFIX)/share/java/libbluray*.jar
endif
else
	@echo "bluray: WARNING: python3 missing, skipping the Java API checks"
endif
endif
	touch $@
