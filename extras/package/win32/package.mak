if HAVE_WIN32
BUILT_SOURCES_distclean += \
	extras/package/win32/NSIS/vlc.win32.nsi extras/package/win32/NSIS/spad.nsi
endif

win32_destdir=@PACKAGE_DIR@
win32_debugdir=$(abs_top_builddir)/symbols-$(VERSION)
win32_xpi_destdir=$(abs_top_builddir)/vlc-plugin-$(VERSION)

7Z_OPTS=-t7z -m0=lzma -mx=9 -mfb=64 -md=32m -ms=on


if HAVE_WIN32
include extras/package/npapi.am

build-npapi: package-win-install
endif

if HAVE_ARM64
WINVERSION=PowerVLC-$(POWERVLC_VERSION)-winarm64
else
if HAVE_WIN64
WINVERSION=PowerVLC-$(POWERVLC_VERSION)-win64
else
WINVERSION=PowerVLC-$(POWERVLC_VERSION)-win32
endif
endif

# Staging directory for the portable archive, and the name the user ends up
# with after extracting it. It doubles as the top-level folder inside the zip,
# so it has to say what it is on its own: someone who downloads both archives
# must not end up with two identically named folders.
win32_portabledir=$(abs_top_builddir)/$(WINVERSION)-portable

package-win-install:
	$(MAKE) install
	cp '$(DESTDIR)$(libdir)/libpowervlc.dll.a' '$(DESTDIR)$(libdir)/libpowervlc.lib'
	cp '$(DESTDIR)$(libdir)/libpowervlccore.dll.a' '$(DESTDIR)$(libdir)/libpowervlccore.lib'
if ENABLE_PDB
	cp lib/.libs/libpowervlc.pdb '$(DESTDIR)$(bindir)'
	cp src/.libs/libpowervlccore.pdb '$(DESTDIR)$(bindir)'
	find '$(DESTDIR)$(libdir)/vlc/plugins' -name "*.dll" -exec sh -c "echo {} | sed -e 's@$(DESTDIR)$(libdir)/vlc/plugins/\(.*\)/\(.*\).dll@modules/.libs/\2.pdb $(DESTDIR)$(libdir)/vlc/plugins/\1@' | xargs -t cp " \;
endif
	touch $@

package-win-sdk: package-win-install
	mkdir -p "$(win32_destdir)/sdk/lib/"
	cp -r $(prefix)/include "$(win32_destdir)/sdk"
	cp -r $(prefix)/lib/pkgconfig "$(win32_destdir)/sdk/lib"
	cp -rv $(prefix)/lib/libpowervlc.dll.a "$(win32_destdir)/sdk/lib/libpowervlc.lib"
	cp -rv $(prefix)/lib/libpowervlccore.dll.a "$(win32_destdir)/sdk/lib/libpowervlccore.lib"
	$(DLLTOOL) -D libpowervlc.dll -l "$(win32_destdir)/sdk/lib/libpowervlc.lib" -d "$(top_builddir)/lib/.libs/libpowervlc.dll.def"
	echo "INPUT(libpowervlc.lib)" > "$(win32_destdir)/sdk/lib/vlc.lib"
	$(DLLTOOL) -D libpowervlccore.dll -l "$(win32_destdir)/sdk/lib/libpowervlccore.lib" -d "$(top_builddir)/src/.libs/libpowervlccore.dll.def"
	echo "INPUT(libpowervlccore.lib)" > "$(win32_destdir)/sdk/lib/vlccore.lib"

package-win-common: package-win-install package-win-sdk
# Executables, major libs
	find $(prefix) -maxdepth 4 \( -name "*$(LIBEXT)" -o -name "*$(EXEEXT)" \) -exec cp {} "$(win32_destdir)/" \;
# PowerVLC: nothing to rename here any more -- the executables are built as
# powervlc.exe and powervlc-cache-gen.exe by their own _PROGRAMS targets, so the
# find/cp above already copies them under the right names. The mv commands that
# used to fix up "vlc.exe" were kept only while the automake target was still
# named "vlc".

# Only the licence is shipped at the install root. AUTHORS, THANKS and NEWS
# are compiled into the binary -- src/Makefile.am generates vlc_about.h from
# COPYING, AUTHORS and THANKS_VLC, and that is what the About window shows --
# so the copies here were read by nobody and no interface opens them.
# COPYING stays: it is the licence the NSIS page displays, and shipping it is
# a condition of the GPL.
	cp "$(srcdir)/COPYING" "$(win32_destdir)/COPYING.txt"

	cp $(srcdir)/share/icons/powervlc.ico $(win32_destdir)

# Private engine resolved by vlc.config.helper("emule-engine"). Never flatten
# it with the public executables and never place it in NSIS's own helpers dir.
# The portable ZIP excludes every *helpers* path, hence the distinct name.
	test -n "$(POWERVLC_AMULED)" -a -x "$(POWERVLC_AMULED)"
	mkdir -p "$(win32_destdir)/powervlc-engines"
	cp "$(POWERVLC_AMULED)" "$(win32_destdir)/powervlc-engines/amuled.exe"
	cp "$(top_srcdir)/extras/package/amule-engine-NOTICE.txt" \
	   "$(win32_destdir)/powervlc-engines/aMule-engine.txt"

# The browser add-on. It goes to the root of the install because that is
# where config_GetDataDir() points on Windows (src/win32/dirs.c hands back
# the executable's own directory), and that is where the Help menu entry
# looks for it. Without this the file was simply not in the Windows package,
# so there was no way to install the add-on on Basilisk and the other retro
# browsers -- the very ones it exists for.
	cp $(srcdir)/share/powervlc.xpi $(win32_destdir)

# Root CA bundle, next to the executable for the same reason as the add-on
# above: that is what config_GetDataDir() returns on Windows. gnutls loads it
# IN ADDITION to the CryptoAPI store (see modules/misc/gnutls.c) -- Windows XP
# has a perfectly readable trust store that simply stopped being updated, so
# it knows nothing of ISRG Root X1 and much of today's HTTPS fails on it.
	cp $(srcdir)/share/certs/ca-certificates.crt $(win32_destdir)
	for plugindir in $(prefix)/lib/vlc/plugins/*/; do \
		plugin_destdir="$(win32_destdir)/plugins/`basename $$plugindir`"; \
		mkdir -p "$$plugin_destdir"; \
		find "$$plugindir" -type f \( -not -name '*.la' -and -not -name '*.a' \) -exec cp -v "{}" "$$plugin_destdir" \; ;\
	done
	-cp -r $(prefix)/share/locale $(win32_destdir)

# BD-J JAR
	-cp $(CONTRIB_DIR)/share/java/*.jar $(win32_destdir)/plugins/access/

# libaacs: AACS descrambling for Blu-ray. libbluray does not link against it,
# it dlopen()s "libaacs.dll", which LoadLibrary resolves from the directory of
# powervlc.exe -- so the DLL goes next to it, under that exact name (libtool
# builds it as libaacs-0.dll). A Blu-ray plugin without libaacs plays homemade
# discs only, so a missing library fails the packaging step instead of
# shipping a player that cannot read a retail disc.
	@if test -d "$(win32_destdir)/plugins/access" && \
	    ls "$(win32_destdir)/plugins/access/"*bluray* >/dev/null 2>&1; then \
		aacs=`ls $(CONTRIB_DIR)/bin/libaacs*.dll 2>/dev/null | head -1` ; \
		if test -n "$$aacs"; then \
			cp "$$aacs" "$(win32_destdir)/libaacs.dll" ; \
			echo "  PACKAGE  libaacs.dll" ; \
		else \
			echo "ERROR: the Blu-ray plugin is packaged but $(CONTRIB_DIR)/bin/libaacs-*.dll is missing." ; \
			echo "       Build it with: make -C contrib/contrib-<host> .aacs" ; \
			exit 1 ; \
		fi ; \
	fi

# libbdplus: BD+ descrambling, the second protection layer some retail Blu-rays
# carry on top of AACS. Same loading story as libaacs -- libbluray dlopen()s
# "libbdplus.dll", LoadLibrary resolves it from the directory of powervlc.exe,
# and libtool builds it as libbdplus-0.dll. Missing it is only a warning: BD+
# concerns a minority of discs, and libbdplus does nothing anyway until the
# user drops a VM into %APPDATA%\bdplus\vm0\ (the Help menu opens that folder).
	@if test -d "$(win32_destdir)/plugins/access" && \
	    ls "$(win32_destdir)/plugins/access/"*bluray* >/dev/null 2>&1; then \
		bdplus=`ls $(CONTRIB_DIR)/bin/libbdplus*.dll 2>/dev/null | head -1` ; \
		if test -n "$$bdplus"; then \
			cp "$$bdplus" "$(win32_destdir)/libbdplus.dll" ; \
			echo "  PACKAGE  libbdplus.dll" ; \
		else \
			echo "  NOTE     no libbdplus: BD+ protected discs will not play" ; \
			echo "           Build it with: make -C contrib/contrib-<host> .bdplus" ; \
		fi ; \
	fi

# mingw runtime DLLs. gcc links libgcc dynamically as soon as something needs
# unwinding, and the contrib system does not pass -static-libgcc, so a handful
# of binaries import libgcc_s_seh-1.dll (x86_64) / libgcc_s_dw2-1.dll (i686):
# libaacs, libbdplus, and the x265, gme and SRT plugins. Nothing else ships
# that DLL, and the failure is SILENT -- LoadLibrary just fails, the plugin
# drops out of the cache, and Blu-ray decryption, x265 and SRT vanish with no
# error message anywhere. So: stage every mingw runtime DLL the staged tree
# actually imports (the DLL name sits in the import table as plain ASCII,
# hence the grep) and copy it from the toolchain. llvm-mingw (winarm64) links
# its unwinder statically, imports none of these, and skips the whole loop.
	@for dll in libgcc_s_seh-1.dll libgcc_s_dw2-1.dll libgcc_s_sjlj-1.dll \
	            libwinpthread-1.dll libstdc++-6.dll; do \
		if grep -rq "$$dll" "$(win32_destdir)" 2>/dev/null && \
		   test ! -f "$(win32_destdir)/$$dll"; then \
			src=`$(CC) -print-file-name=$$dll 2>/dev/null` ; \
			if test -f "$$src"; then \
				cp "$$src" "$(win32_destdir)/$$dll" ; \
				echo "  PACKAGE  $$dll" ; \
			else \
				echo "ERROR: $$dll is imported by this build but the toolchain has no copy of it." ; \
				echo "       Without it the importing plugins fail to load, silently." ; \
				exit 1 ; \
			fi ; \
		fi ; \
	done

if BUILD_LUA
	mkdir -p $(win32_destdir)/lua/
	cp -r $(prefix)/lib/vlc/lua/* $(win32_destdir)/lua/
	cp -r $(prefix)/share/vlc/lua/* $(win32_destdir)/lua/
endif

if BUILD_SKINS
	rm -fr $(win32_destdir)/skins
	cp -r $(prefix)/share/vlc/skins2 $(win32_destdir)/skins
endif

# HRTF
	cp -r $(srcdir)/share/hrtfs $(win32_destdir)/
	cp -r $(prefix)/share/vlc/retroarch-shaders $(win32_destdir)/
	python3 $(srcdir)/extras/tools/pack-retroarch-shaders.py \
		"$(win32_destdir)/retroarch-shaders" \
		"$(win32_destdir)/retroarch-shaders.pak"
	rm -rf "$(win32_destdir)/retroarch-shaders"

# Convert to DOS line endings
	find $(win32_destdir) -type f \( -name "*xml" -or -name "*html" -or -name '*js' -or -name '*css' -or -name '*hosts' -or -iname '*txt' -or -name '*.cfg' -or -name '*.lua' \) -exec $(U2D) -q {} \;

package-win-npapi: build-npapi
	cp "$(top_builddir)/npapi-vlc/installed/lib/axvlc.dll" "$(win32_destdir)/"
	cp "$(top_builddir)/npapi-vlc/installed/lib/npvlc.dll" "$(win32_destdir)/"
	mkdir -p "$(win32_destdir)/sdk/activex/"
	cp $(top_builddir)/npapi-vlc/activex/README.TXT $(top_builddir)/npapi-vlc/share/test/test.html $(win32_destdir)/sdk/activex/

package-win-strip: package-win-common
	mkdir -p "$(win32_debugdir)"/
	find $(win32_destdir) -type f \( -name '*$(LIBEXT)' -or -name '*$(EXEEXT)' \) | while read i; \
	do if test -n "$$i" ; then \
	    $(OBJCOPY) --only-keep-debug "$$i" "$(win32_debugdir)/`basename $$i.dbg`"; \
	    $(OBJCOPY) --strip-all "$$i" ; \
	    $(OBJCOPY) --add-gnu-debuglink="$(win32_debugdir)/`basename $$i.dbg`" "$$i" ; \
	  fi ; \
	done

package-win32-webplugin-common: package-win-strip
	mkdir -p "$(win32_xpi_destdir)/plugins/"
	cp -r $(win32_destdir)/plugins/ "$(win32_xpi_destdir)/plugins/"
	cp "$(win32_destdir)/libpowervlc.dll" "$(win32_destdir)/libpowervlccore.dll" "$(win32_destdir)/npvlc.dll" "$(win32_xpi_destdir)/plugins/"
	rm -rf "$(win32_xpi_destdir)/plugins/plugins/gui/"


package-win32-xpi: package-win32-webplugin-common
	cp $(top_builddir)/npapi-vlc/npapi/package/install.rdf "$(win32_xpi_destdir)/"
	zip -r -9 $(WINVERSION).xpi $(win32_xpi_destdir)/install.rdf $(win32_xpi_destdir)/plugins


package-win32-crx: package-win32-webplugin-common
	cp $(top_builddir)/npapi-vlc/npapi/package/manifest.json "$(win32_xpi_destdir)/"
	crxmake --pack-extension "$(win32_xpi_destdir)" \
		--extension-output "$(win32_destdir)/$(WINVERSION).crx" --ignore-file install.rdf


$(win32_destdir)/NSIS/nsProcess.dll: extras/package/win32/NSIS/nsProcess/nsProcess.c extras/package/win32/NSIS/nsProcess/pluginapi.c
	mkdir -p "$(win32_destdir)/NSIS/"
if HAVE_WIN64
	i686-w64-mingw32-gcc $^ -shared -o $@ -lole32 -static-libgcc -D_UNICODE=1 -DUNICODE=1
	i686-w64-mingw32-strip $@
else
	$(CC) $^ -D_WIN32_IE=0x0601 -shared -o $@ -lole32 -static-libgcc -D_UNICODE=1 -DUNICODE=1
	$(STRIP) $@
endif

package-win32-src: package-win-strip
# Script installer
	mkdir -p "$(win32_destdir)/NSIS/"
	cp    $(top_builddir)/extras/package/win32/NSIS/vlc.win32.nsi "$(win32_destdir)/"
	cp    $(top_builddir)/extras/package/win32/NSIS/spad.nsi      "$(win32_destdir)/"
	cp -r $(srcdir)/extras/package/win32/NSIS/languages           "$(win32_destdir)/"
	cp -r $(srcdir)/extras/package/win32/NSIS/helpers             "$(win32_destdir)/"
	cp "$(top_srcdir)/extras/package/win32/NSIS/nsProcess.nsh" "$(win32_destdir)/NSIS/"
	cp "$(top_srcdir)/extras/package/win32/NSIS/vlc_branding.bmp" "$(win32_destdir)/NSIS/"

package-win32-exe: package-win32-src $(win32_destdir)/NSIS/nsProcess.dll extras/package/win32/NSIS/vlc.win32.nsi
# Create package
	if makensis -VERSION >/dev/null 2>&1; then \
	    MAKENSIS="makensis"; \
	elif [ -x "$(PROGRAMFILES)/NSIS/makensis" ]; then \
	    MAKENSIS="$(PROGRAMFILES)/NSIS/makensis"; \
	else \
	    echo 'Error: cannot locate makensis tool'; exit 1; \
	fi; \
	MAKENSIS_VERSION=`makensis -VERSION`; echo $${MAKENSIS_VERSION:1:1}; \
	if [ $${MAKENSIS_VERSION:1:1} -lt 3 ]; then \
	    echo 'Please update your nsis packager';\
	    exit 1; \
	fi; \
	eval "$$MAKENSIS $(win32_destdir)/spad.nsi"; \
	eval "$$MAKENSIS $(win32_destdir)/vlc.win32.nsi"

package-win32-zip: package-win-strip
	rm -f -- $(WINVERSION).zip
	zip -r -9 $(WINVERSION).zip vlc-$(VERSION) --exclude \*.nsi \*NSIS\* \*languages\* \*sdk\* \*helpers\* spad\*

# PowerVLC: the portable archive shipped alongside the NSIS installer.
#
# Portable mode is not a build flavour -- it is the SAME binaries. VLC's core
# already implements it: config_GetAppDir() (src/win32/dirs.c) looks for a
# folder named "portable" next to powervlc.exe and, when it finds one, puts the
# configuration, the media library and the per-user caches there instead of
# %APPDATA%\powervlc. So the only thing this target adds to the installed tree
# is that one folder; everything else is the packaging tree minus the installer
# scaffolding (NSIS scripts, the installer's own translations, the SDK).
#
# The marker folder is NOT shipped empty. A directory with no files in it is a
# zip entry that "extract here" shell integrations and several extractors drop
# without a word, and losing it would silently turn the portable build back into
# a normal one -- it would still run, just writing to %APPDATA% behind the
# user's back. A README inside it makes the folder a real payload, and it is
# also the natural place to explain what the folder does.
#
# Staged through hard links when the filesystem allows it: the tree is close to
# a gigabyte, it is only ever read here, and the Docker volume the Windows
# builds share is already the tightest resource in the campaign.
#
# No plugins.dat is generated by this cross-compiled Make target because its
# powervlc-cache-gen.exe cannot run in the linux/arm64 compiler container. The
# Docker orchestrator automatically passes this raw archive through a dedicated,
# target-matched Wine container after the final DLL stripping, verifies the
# generated relocatable cache and only then publishes the portable ZIP. Direct
# invocations of this Make target remain usable: the core writes a self-healing
# cache on first launch if the Wine finalization step was not used.
package-win32-portable-zip: package-win-strip
	rm -f -- $(WINVERSION)-portable.zip
	rm -rf -- "$(win32_portabledir)"
	cp -al "$(win32_destdir)" "$(win32_portabledir)" 2>/dev/null || \
	    { rm -rf -- "$(win32_portabledir)"; \
	      cp -a "$(win32_destdir)" "$(win32_portabledir)"; }
	rm -rf -- "$(win32_portabledir)/sdk" "$(win32_portabledir)/NSIS" \
	          "$(win32_portabledir)/languages" "$(win32_portabledir)/helpers" \
	          "$(win32_portabledir)/msi"
	rm -f -- "$(win32_portabledir)"/*.nsi "$(win32_portabledir)"/spad*
	mkdir -p "$(win32_portabledir)/portable"
	cp "$(top_srcdir)/extras/package/win32/portable-README.txt" \
	   "$(win32_portabledir)/portable/README.txt"
	zip -r -9 -q $(WINVERSION)-portable.zip "$(WINVERSION)-portable"
	rm -rf -- "$(win32_portabledir)"
	@echo "  PACKAGE  $(WINVERSION)-portable.zip"

package-win32-debug-zip: package-win-common
	rm -f -- $(WINVERSION)-debug.zip
	zip -r -9 $(WINVERSION)-debug.zip vlc-$(VERSION)

package-win32-7zip: package-win-strip
	7z a $(7Z_OPTS) $(WINVERSION).7z vlc-$(VERSION)

package-win32-debug-7zip: package-win-common
	7z a $(7Z_OPTS) $(WINVERSION)-debug.7z vlc-$(VERSION)

package-win32-cleanup:
	rm -Rf $(win32_destdir) $(win32_debugdir) $(win32_xpi_destdir) "$(win32_portabledir)"

# PowerVLC: drop package-win32-xpi (the obsolete NPAPI/Mozilla browser plugin).
#
# The two shipped artifacts are the NSIS installer and the portable archive.
# package-win32-zip and package-win32-7zip used to be pulled in here too, and
# nothing ever collected either of them: the plain zip is exactly what
# package-win32-portable-zip now produces (minus the marker folder), and the 7z
# is a second full-tree archive at -mx=9, which is several minutes of CPU and a
# gigabyte of the shared Docker volume spent on a file no release ever used.
# Both targets are still here for anyone who wants them by name.
package-win32: package-win32-portable-zip package-win32-exe

package-win32-debug: package-win32-debug-zip package-win32-debug-7zip

package-win32-release: package-win32-src $(win32_destdir)/NSIS/nsProcess.dll package-win-sdk
	mkdir -p "$(win32_destdir)/msi/"
	cp    $(top_builddir)/extras/package/win32/msi/config.wxi	  "$(win32_destdir)/msi/"
	cp    $(top_srcdir)/extras/package/win32/msi/axvlc.wxs		  "$(win32_destdir)/msi/"
	cp    $(top_srcdir)/extras/package/win32/msi/bannrbmp.bmp	  "$(win32_destdir)/msi/"
	cp    $(top_srcdir)/extras/package/win32/msi/extensions.wxs	  "$(win32_destdir)/msi/"
	cp    $(top_srcdir)/extras/package/win32/msi/LICENSE.rtf	  "$(win32_destdir)/msi/"
	cp    $(top_srcdir)/extras/package/win32/msi/product.wxs	  "$(win32_destdir)/msi/"

	7z a $(7Z_OPTS) $(WINVERSION)-release.7z $(win32_debugdir) "$(win32_destdir)/"

#######
# WinCE
#######
package-wince: package-win-strip
	rm -f -- PowerVLC-$(POWERVLC_VERSION)-wince.zip
	zip -r -9 PowerVLC-$(POWERVLC_VERSION)-wince.zip vlc-$(VERSION)

.PHONY: package-win-install package-win-common package-win-strip package-win32-webplugin-common package-win32-xpi package-win32-crx package-win32-src package-win32-exe package-win32-zip package-win32-portable-zip package-win32-debug-zip package-win32-7zip package-win32-debug-7zip package-win32-cleanup package-win32 package-win32-debug package-wince

EXTRA_DIST += \
	extras/package/win32/portable-README.txt \
	extras/package/win32/vlc.exe.manifest \
	extras/package/win32/libvlc.dll.manifest \
	extras/package/win32/configure.sh \
	extras/package/win32/NSIS/vlc.win32.nsi.in \
	extras/package/win32/NSIS/spad.nsi.in \
	extras/package/win32/NSIS/vlc_branding.bmp \
	extras/package/win32/NSIS/languages/AfrikaansExtra.nsh \
	extras/package/win32/NSIS/languages/AlbanianExtra.nsh \
	extras/package/win32/NSIS/languages/ArabicExtra.nsh \
	extras/package/win32/NSIS/languages/AsturianExtra.nsh \
	extras/package/win32/NSIS/languages/BasqueExtra.nsh \
	extras/package/win32/NSIS/languages/BosnianExtra.nsh \
	extras/package/win32/NSIS/languages/BretonExtra.nsh \
	extras/package/win32/NSIS/languages/BulgarianExtra.nsh \
	extras/package/win32/NSIS/languages/CatalanExtra.nsh \
	extras/package/win32/NSIS/languages/CorsicanExtra.nsh \
	extras/package/win32/NSIS/languages/CroatianExtra.nsh \
	extras/package/win32/NSIS/languages/CzechExtra.nsh \
	extras/package/win32/NSIS/languages/DanishExtra.nsh \
	extras/package/win32/NSIS/languages/DutchExtra.nsh \
	extras/package/win32/NSIS/languages/EnglishExtra.nsh \
	extras/package/win32/NSIS/languages/EstonianExtra.nsh \
	extras/package/win32/NSIS/languages/FinnishExtra.nsh \
	extras/package/win32/NSIS/languages/FrenchExtra.nsh \
	extras/package/win32/NSIS/languages/GalicianExtra.nsh \
	extras/package/win32/NSIS/languages/GermanExtra.nsh \
	extras/package/win32/NSIS/languages/GreekExtra.nsh \
	extras/package/win32/NSIS/languages/HebrewExtra.nsh \
	extras/package/win32/NSIS/languages/HungarianExtra.nsh \
	extras/package/win32/NSIS/languages/IcelandicExtra.nsh \
	extras/package/win32/NSIS/languages/IndonesianExtra.nsh \
	extras/package/win32/NSIS/languages/ItalianExtra.nsh \
	extras/package/win32/NSIS/languages/JapaneseExtra.nsh \
	extras/package/win32/NSIS/languages/KhmerExtra.nsh \
	extras/package/win32/NSIS/languages/KoreanExtra.nsh \
	extras/package/win32/NSIS/languages/LatvianExtra.nsh \
	extras/package/win32/NSIS/languages/LithuanianExtra.nsh \
	extras/package/win32/NSIS/languages/MalayExtra.nsh \
	extras/package/win32/NSIS/languages/MongolianExtra.nsh \
	extras/package/win32/NSIS/languages/NorwegianExtra.nsh \
	extras/package/win32/NSIS/languages/NorwegianNynorskExtra.nsh \
	extras/package/win32/NSIS/languages/PolishExtra.nsh \
	extras/package/win32/NSIS/languages/PortugueseExtra.nsh \
	extras/package/win32/NSIS/languages/PortugueseBRExtra.nsh \
	extras/package/win32/NSIS/languages/RomanianExtra.nsh \
	extras/package/win32/NSIS/languages/RussianExtra.nsh \
	extras/package/win32/NSIS/languages/ScotsGaelicExtra.nsh \
	extras/package/win32/NSIS/languages/SerbianExtra.nsh \
	extras/package/win32/NSIS/languages/SimpChineseExtra.nsh \
	extras/package/win32/NSIS/languages/SlovakExtra.nsh \
	extras/package/win32/NSIS/languages/SlovenianExtra.nsh \
	extras/package/win32/NSIS/languages/SpanishExtra.nsh \
	extras/package/win32/NSIS/languages/SwedishExtra.nsh \
	extras/package/win32/NSIS/languages/ThaiExtra.nsh \
	extras/package/win32/NSIS/languages/TradChineseExtra.nsh \
	extras/package/win32/NSIS/languages/TurkishExtra.nsh \
	extras/package/win32/NSIS/languages/UkrainianExtra.nsh \
	extras/package/win32/NSIS/languages/UzbekExtra.nsh \
	extras/package/win32/NSIS/languages/WelshExtra.nsh
