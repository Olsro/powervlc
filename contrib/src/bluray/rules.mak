# LIBBLURAY

BLURAY_VERSION := 1.5.0
BLURAY_URL := $(VIDEOLAN)/libbluray/$(BLURAY_VERSION)/libbluray-$(BLURAY_VERSION).tar.xz

ifdef BUILD_DISCS
PKGS += bluray
endif

# PowerVLC's Blu-ray module uses the private MVC/clip accessors added by the
# patches below. A distribution libbluray, regardless of its version, cannot
# provide that ABI, so release builds must always use this contrib copy.

# fontconfig is what resolves a BD-J font *family* ("SansSerif", the name a
# menu asks for) to a font *file*. Without it
# Java_java_awt_BDFontMetrics_resolveFontN() has no backend on Darwin -- there
# is a Win32 one, and nothing else -- so it logs "BD-J font config support not
# compiled in" and returns NULL for every lookup. Discs that ship their own
# fonts in BDMV/AUXDATA are unaffected, but the ones that rely on the player's
# (measured: BDMV/AUXDATA is empty on the BD-J disc tested here) then draw
# their menus with no text at all.
#
# On Darwin this is a prerequisite for BD-J menus, not a nicety. Measured on a
# BD-J disc whose BDMV/AUXDATA is empty (so it carries no font of its own):
# with fontconfig off, resolveFontN() has no backend at all on this platform
# -- there is a Win32 one and nothing else -- so every family lookup returns
# NULL, BD-J falls back to the JVM's own Lucida fonts which modern JDKs no
# longer ship, and the menu xlet ends up unable to draw a single pixel:
#   24 x "ERROR: Can't resolve font ..."  (the only errors in the whole log)
#   BDRootWindow: sync() ignored (overlay not open, empty overlay)
# libbluray deliberately withholds the overlay until something is drawn, so
# nothing is ever displayed even though BD-J itself started correctly.
#
# Switching it on was blocked until now by fontconfig 2.12.3 crashing on a
# current macOS; contrib/src/fontconfig moved to 2.16.0 for this.
ifdef HAVE_ANDROID
WITH_FONTCONFIG = 0
else
ifdef HAVE_DARWIN_OS
WITH_FONTCONFIG = 1
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
# 1. The bytecode version. libbluray derives it from whichever javac it finds
#    (see src/libbluray/bdj/meson.build):
#      javac < 9 -> 1.4 (BD-J) / 1.5 (asm)   javac 9..11 -> 1.6
#      javac 12..17 -> 1.7                   javac >= 18 -> 1.8
#    Up to 1.4.0 that derivation was gated behind a "java9" option which, when
#    off, left both at 1.5; libbluray 1.5.0 removed the option and the
#    derivation now always runs. So the only lever left is the compiler, and
#    the JDK is pinned here rather than taken from the ambient PATH --
#    otherwise the runtime requirement of a release would depend on the build
#    host. javac 9 dropped -source/-target 1.5, so this needs a JDK 8; without
#    one (and ant) BD-J is switched off explicitly rather than silently
#    producing a jar the old machines cannot load.
#
#    With a JDK 8 the BD-J classes now come out as class file v48 (Java 1.4)
#    instead of v49 (Java 5) -- below the floor this contrib cares about, which
#    is what upstream's "Improve Java 1.4 compatibility" work in 1.4.1 aimed
#    for. The checks at the bottom of this file are unchanged: proving the jars
#    stay inside the Java 5 API also proves they stay loadable, whichever of
#    the two versions the bytecode carries.
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
# The bytecode version follows from BLURAY_JDK_HOME alone -- libbluray 1.5.0
# dropped the java9 option that used to override it; see the comment block above.
BLURAY_CONF += -Dbdj_jar=enabled -Dbdj_type=j2se \
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

bluray: libbluray-$(BLURAY_VERSION).tar.xz .sum-bluray \
	$(wildcard $(SRC)/bluray/*.patch)
	$(UNPACK)
	$(APPLY) $(SRC)/bluray/0002-darwin-dont-define-POSIX_C_SOURCE.patch
	$(APPLY) $(SRC)/bluray/0003-macos-load-Apple-Java-6-through-the-JavaVM-framework.patch
	$(APPLY) $(SRC)/bluray/0004-bdj-run-on-java-5.patch
	$(APPLY) $(SRC)/bluray/0005-add-bd_open_stream_dev.patch
	$(APPLY) $(SRC)/bluray/0006-macos-java_home-probe-survives-a-host-that-reaps-children.patch
	$(APPLY) $(SRC)/bluray/0007-macos-find-libjli-in-the-modern-jdk-layout.patch
	$(APPLY) $(SRC)/bluray/0008-bdj-leave-PRESENT-applications-unloaded.patch
	$(APPLY) $(SRC)/bluray/0009-bdj-materialise-bd-rom-files-without-a-security-manager.patch
	$(APPLY) $(SRC)/bluray/0010-expose-mvc-extension-path.patch
	$(APPLY) $(SRC)/bluray/0011-use-backup-for-substituted-3d-capability-reads.patch
	$(APPLY) $(SRC)/bluray/0012-propagate-bdj-s3d-graphics-offset.patch
	$(APPLY) $(SRC)/bluray/0013-bdj-run-without-security-manager-on-java-24.patch
	$(APPLY) $(SRC)/bluray/0014-select-ig-stream-by-menu-language.patch
	$(APPLY) $(SRC)/bluray/0015-restore-duplicated-substituted-3d-capability-reads.patch
	$(APPLY) $(SRC)/bluray/0016-bdj-create-sockets-on-java-17.patch
	$(APPLY) $(SRC)/bluray/0017-bdj-cache-disc-identity-for-random-access.patch
	$(APPLY) $(SRC)/bluray/0018-make-bdj-network-access-configurable.patch
	$(APPLY) $(SRC)/bluray/0019-fix-bdj-graphics-and-mouse-input.patch
	$(APPLY) $(SRC)/bluray/0020-harden-bdj-session-shutdown.patch
	$(APPLY) $(SRC)/bluray/0021-fix-hdmv-3d-capability-comparisons.patch
	$(APPLY) $(SRC)/bluray/0022-lock-current-clip-metadata-access.patch
	$(APPLY) $(SRC)/bluray/0023-expose-named-clip-metadata.patch
	$(APPLY) $(SRC)/bluray/0024-expose-s3d-graphics-offset-sequence-control.patch
ifdef HAVE_WIN32
ifeq ($(ARCH),i386)
	# The bundled libudfread maps strtok_r() onto strtok_s(), a "secure CRT"
	# entry point that only reached msvcrt.dll with Windows Vista. The win32
	# slice targets XP SP3, where importing it stops the Blu-ray plugin from
	# loading at all, so carry a local strtok_r() instead. (Not strtok():
	# udfread walks a path while the caller may hold another tokenizer.)
	sed -i.orig -e 's/^#define strtok_r strtok_s$$/static char *udfread_strtok_r(char *s, const char *d, char **p)\n{\n    if (!s) s = *p;\n    if (!s) return NULL;\n    s += strspn(s, d);\n    if (!*s) { *p = NULL; return NULL; }\n    { char *e = s + strcspn(s, d); if (*e) *e++ = 0; *p = e; }\n    return s;\n}\n#define strtok_r udfread_strtok_r/' \
	    $(UNPACK_DIR)/contrib/libudfread/src/udfread.c
endif
endif
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
