if HAVE_DARWIN
noinst_DATA = pseudo-bundle
endif

# Symlink a pseudo-bundle
pseudo-bundle:
	$(MKDIR_P) $(top_builddir)/bin/Contents/Resources/
	$(LN_S) -nf $(abs_top_builddir)/modules/gui/macosx/UI $(top_builddir)/bin/Contents/Resources/Base.lproj
	$(LN_S) -nf $(abs_top_builddir)/share/macosx/Info.plist $(top_builddir)/bin/Contents/Info.plist
	$(LN_S) -nf $(CONTRIB_DIR)/Frameworks
	cd $(top_builddir)/bin/Contents/Resources/ && find $(abs_top_srcdir)/modules/gui/macosx/Resources/ -type f -not -path "*.lproj/*" -exec $(LN_S) -f {} \;
	cd $(top_builddir)/bin/Contents/Resources/ && find $(abs_top_srcdir)/modules/gui/legacy_macosx/Resources/ -type f -exec $(LN_S) -f {} \;

# VLC.app for packaging and giving it to your friends
# use package-macosx to get a nice dmg
VLC.app: install
	rm -Rf $@
	## Copy Contents. The installed skeleton only exists under
	## ENABLE_MACOSX_UI; when the modern UI is disabled (legacy_macosx
	## only), recreate the same flat Resources layout from the source tree.
	if test -d "$(prefix)/share/macosx/"; then \
		cp -R $(prefix)/share/macosx/ $@ ; \
	else \
		$(MKDIR_P) $@/Contents/Resources ; \
		find "$(srcdir)/modules/gui/macosx/Resources" -type f \
			-not -path "*.lproj/*" -exec cp {} $@/Contents/Resources/ \; ; \
	fi
	## Copy .strings file and .nib files
	cp -R "$(srcdir)/modules/gui/macosx/Resources/"*.lproj $@/Contents/Resources/
	## Compiled nibs only exist when the modern UI is built
	-cp -R "$(top_builddir)/modules/gui/macosx/UI/." $@/Contents/Resources/English.lproj/
	## Legacy interface artwork (VLC 2.x fullscreen panel, used by the
	## legacy_macosx module on pre-10.7 releases)
	-find "$(srcdir)/modules/gui/legacy_macosx/Resources" -name '*.png' \
		-exec cp {} $@/Contents/Resources/ \;
	## VLC 3.0 artwork the legacy interface reuses (bright-theme button
	## templates and the dropzone). Copied explicitly because the macosx
	## module's own resources are only installed under ENABLE_MACOSX_UI,
	## which is off when targeting releases the full interface no longer
	## supports.
	-cp "$(srcdir)/modules/gui/macosx/Resources/Button-Icons/"*.pdf \
		$@/Contents/Resources/
	-cp "$(srcdir)/modules/gui/macosx/Resources/mainwindow/dropzone.png" \
		"$(srcdir)/modules/gui/macosx/Resources/mainwindow_mojave_dark/mj-dropzone-dark.png" \
		$@/Contents/Resources/
	-cp "$(srcdir)/modules/gui/macosx/Resources/sidebar-icons/"*.png \
		$@/Contents/Resources/
	-find "$(srcdir)/modules/gui/macosx/Resources/mainwindow" \
		-name '*.png' ! -name '*@2x*' \
		-exec cp {} $@/Contents/Resources/ \;
	-find "$(srcdir)/modules/gui/macosx/Resources/mainwindow_dark" \
		-name '*.png' ! -name '*@2x*' ! -path '*titlebar*' \
		-exec cp {} $@/Contents/Resources/ \;
	-cp "$(srcdir)/modules/gui/macosx/Resources/File-Icons/generic.icns" \
		$@/Contents/Resources/
	## Copy Info.plist and convert to binary
	cp -R $(top_builddir)/share/macosx/Info.plist $@/Contents/
	xcrun plutil -convert binary1 $@/Contents/Info.plist
	## Create Frameworks dir and copy required ones
	mkdir -p $@/Contents/Frameworks
if HAVE_OSX_NOTIFICATIONS
	## Growl.framework is optional now: without it the notification
	## plugin uses native notifications / distributed Growl messages
	-test -d $(CONTRIB_DIR)/Frameworks/Growl.framework && \
		cp -R $(CONTRIB_DIR)/Frameworks/Growl.framework $@/Contents/Frameworks || true
endif
if HAVE_SPARKLE
	cp -R $(CONTRIB_DIR)/Frameworks/Sparkle.framework $@/Contents/Frameworks
endif
if HAVE_BREAKPAD
	cp -R $(CONTRIB_DIR)/Frameworks/Breakpad.framework $@/Contents/Frameworks
endif
	mkdir -p $@/Contents/MacOS/share/
if BUILD_LUA
	## Copy lua scripts
	cp -r "$(prefix)/share/vlc/lua" $@/Contents/MacOS/share/
	cp -r "$(prefix)/lib/vlc/lua" $@/Contents/MacOS/share/
endif
	## HRTFs
	cp -r $(srcdir)/share/hrtfs $@/Contents/MacOS/share/
	## Root CA bundle: gnutls cannot read a system trust store on Mac OS X
	## before 10.6, so the gnutls module falls back to this file in the
	## data dir (see modules/misc/gnutls.c) for HTTPS/TLS streams.
	-cp $(srcdir)/share/certs/ca-certificates.crt $@/Contents/MacOS/share/
	## Copy some other stuff (?)
	mkdir -p $@/Contents/MacOS/include/
	(cd "$(prefix)/include" && $(AMTAR) -c --exclude "plugins" vlc) | $(AMTAR) -x -C $@/Contents/MacOS/include/
	## Copy translations
	-cp -r "$(prefix)/share/locale" $@/Contents/MacOS/share/
	printf "APPL????" >| $@/Contents/PkgInfo
	## Copy libs
	mkdir -p $@/Contents/MacOS/lib
	find $(prefix)/lib -name 'libpowervlc*.dylib' -maxdepth 1 -exec cp -a {} $@/Contents/MacOS/lib \;
	## Bundle the contrib-built libc++/libc++abi (deployment targets older
	## than Mac OS X 10.9, where the OS does not ship its own libc++; see
	## contrib/src/libcxx-legacy). @executable_path/lib/ is already on the
	## main binary's rpath list, which dyld also searches when resolving
	## the plugins' @rpath/libc++*.dylib references.
	find $(CONTRIB_DIR)/lib -name 'libc++*.dylib' -maxdepth 1 -exec cp -a {} $@/Contents/MacOS/lib \; || true
	## Copy plugins
	mkdir -p $@/Contents/MacOS/plugins
	find $(prefix)/lib/vlc/plugins -name 'lib*_plugin.dylib' -maxdepth 3 -exec cp -a {} $@/Contents/MacOS/plugins \;
	## libaacs: AACS descrambling for Blu-ray. libbluray does not link
	## against it, it dlopen()s "libaacs.dylib" and searches, among others,
	## @executable_path/lib/ -- which is this directory. cp -L because
	## contrib installs libaacs.dylib as a symlink to libaacs.0.dylib.
	## The Blu-ray plugin without libaacs plays homemade discs only, so
	## treat a missing library as a packaging error rather than shipping a
	## player that silently cannot read a retail disc.
	## AACS_OPTIONAL=1 still downgrades that to a warning, but nothing sets it
	## any more: the PowerPC and Intel-32 slices used to be exempt because
	## libaacs' Darwin backend #included IOKit/storage/IOBDMediaBSDClient.h,
	## absent from the 10.4u SDK. No symbol from that header was ever used, and
	## libaacs-powervlc-tiger-and-external-mmc.patch drops the include, so
	## every slice has AACS now.
	@if ls $@/Contents/MacOS/plugins/*bluray_plugin.dylib >/dev/null 2>&1; then \
		if test -f "$(CONTRIB_DIR)/lib/libaacs.dylib"; then \
			cp -L "$(CONTRIB_DIR)/lib/libaacs.dylib" \
				$@/Contents/MacOS/lib/libaacs.dylib ; \
			echo "  BUNDLE   libaacs.dylib" ; \
		elif test "$(AACS_OPTIONAL)" = "1"; then \
			echo "  NOTE     no libaacs for this target (SDK has no Blu-ray IOKit class):" ; \
			echo "           the Blu-ray plugin will play unencrypted discs only" ; \
		else \
			echo "ERROR: the Blu-ray plugin is bundled but $(CONTRIB_DIR)/lib/libaacs.dylib is missing." ; \
			echo "       Build it with: make -C contrib/contrib-<host> .aacs" ; \
			exit 1 ; \
		fi ; \
	fi
	## libbdplus: BD+ descrambling, the second protection layer some retail
	## Blu-rays carry on top of AACS. Loaded exactly like libaacs -- libbluray
	## dlopen()s "libbdplus.dylib" from @executable_path/lib/ -- so it is
	## bundled the same way. Unlike libaacs its absence is only a warning: BD+
	## concerns a minority of discs, and libbdplus is useless anyway until the
	## user drops a VM into ~/Library/Preferences/bdplus/vm0/ (the Help menu
	## opens that folder).
	@if ls $@/Contents/MacOS/plugins/*bluray_plugin.dylib >/dev/null 2>&1; then \
		if test -f "$(CONTRIB_DIR)/lib/libbdplus.dylib"; then \
			cp -L "$(CONTRIB_DIR)/lib/libbdplus.dylib" \
				$@/Contents/MacOS/lib/libbdplus.dylib ; \
			echo "  BUNDLE   libbdplus.dylib" ; \
		else \
			echo "  NOTE     no libbdplus for this target: BD+ protected discs will not play" ; \
			echo "           Build it with: make -C contrib/contrib-<host> .bdplus" ; \
		fi ; \
	fi
	## Copy libbluray jar
	find "$(CONTRIB_DIR)/share/java/" -name 'libbluray*.jar' -maxdepth 1 -exec cp -a {} $@/Contents/MacOS/plugins \; || true
	## Install binary
	cp $(prefix)/bin/powervlc $@/Contents/MacOS/PowerVLC
	## Generate plugin cache
	if test "$(build)" = "$(host)"; then \
		bin/powervlc-cache-gen $@/Contents/MacOS/plugins ; \
	else \
		echo "Cross-compilation: cache generation skipped!" ; \
	fi
	find $@ -type d -exec chmod ugo+rx '{}' \;
	find $@ -type f -exec chmod ugo+r '{}' \;


package-macosx: VLC.app
	rm -f "$(top_builddir)/vlc-$(VERSION).dmg"
if HAVE_DMGBUILD
	@echo "Packaging fancy DMG using dmgbuild"
	cd "$(top_srcdir)/extras/package/macosx/dmg" && dmgbuild -s "dmg_settings.py" \
		-D app="$(abs_top_builddir)/VLC.app" "VLC Media Player" "$(abs_top_builddir)/vlc-$(VERSION).dmg"
else !HAVE_DMGBUILD
	@echo "Packaging non-fancy DMG"
	## Create directory for DMG contents
	mkdir -p "$(top_builddir)/vlc-$(VERSION)"
	## Copy contents
	cp -Rp "$(top_builddir)/VLC.app" "$(top_builddir)/vlc-$(VERSION)/VLC.app"
	## Symlink to Applications so users can easily drag-and-drop the App to it
	$(LN_S) -f /Applications "$(top_builddir)/vlc-$(VERSION)/"
	## Create DMG
	hdiutil create -srcfolder "$(top_builddir)/vlc-$(VERSION)" -volname "VLC Media Player" \
		-format UDBZ -fs HFS+ -o "$(top_builddir)/vlc-$(VERSION).dmg"
	## Cleanup
	rm -rf "$(top_builddir)/vlc-$(VERSION)"
endif

package-macosx-zip: VLC.app
	rm -f "$(top_builddir)/vlc-$(VERSION).zip"
	mkdir -p $(top_builddir)/vlc-$(VERSION)/Goodies/
	cp -Rp $(top_builddir)/VLC.app $(top_builddir)/vlc-$(VERSION)/VLC.app
	cd $(srcdir); cp -R AUTHORS COPYING README_VLC THANKS_VLC NEWS_VLC $(abs_top_builddir)/vlc-$(VERSION)/Goodies/
	zip -r -y -9 $(top_builddir)/vlc-$(VERSION).zip $(top_builddir)/vlc-$(VERSION)
	rm -rf "$(top_builddir)/vlc-$(VERSION)"

package-macosx-release:
	rm -f "$(top_builddir)/vlc-$(VERSION)-release.zip"
	mkdir -p $(top_builddir)/vlc-$(VERSION)-release
	cp -Rp $(top_builddir)/VLC.app $(top_builddir)/vlc-$(VERSION)-release/
	cp $(srcdir)/extras/package/macosx/dmg/* $(top_builddir)/vlc-$(VERSION)-release/
	cp "$(srcdir)/extras/package/macosx/codesign.sh" $(top_builddir)/vlc-$(VERSION)-release/
	cp "$(prefix)/lib/vlc/powervlc-cache-gen" $(top_builddir)/vlc-$(VERSION)-release/
	cp "$(srcdir)/extras/package/macosx/vlc-hardening.entitlements" $(top_builddir)/vlc-$(VERSION)-release/
	install_name_tool -add_rpath "@executable_path/VLC.app/Contents/MacOS/lib" $(top_builddir)/vlc-$(VERSION)-release/powervlc-cache-gen
	zip -r -y -9 $(top_builddir)/vlc-$(VERSION)-release.zip $(top_builddir)/vlc-$(VERSION)-release
	rm -rf "$(top_builddir)/vlc-$(VERSION)-release"

package-translations:
	mkdir -p "$(srcdir)/vlc-translations-$(VERSION)"
	for i in `cat "$(top_srcdir)/po/LINGUAS"`; do \
	  cp "$(srcdir)/po/$${i}.po" "$(srcdir)/vlc-translations-$(VERSION)/" ; \
	done
	cp "$(srcdir)/doc/translations.txt" "$(srcdir)/vlc-translations-$(VERSION)/README.txt"

	echo "#!/bin/sh" >>"$(srcdir)/vlc-translations-$(VERSION)/convert.po.sh"
	echo "" >>"$(srcdir)/vlc-translations-$(VERSION)/convert.po.sh"
	echo 'if test $$# != 1; then' >>"$(srcdir)/vlc-translations-$(VERSION)/convert.po.sh"
	echo "	echo \"Usage: convert-po.sh <.po file>\"" >>"$(srcdir)/vlc-translations-$(VERSION)/convert.po.sh"
	echo "	exit 1" >>"$(srcdir)/vlc-translations-$(VERSION)/convert.po.sh"
	echo "fi" >>"$(srcdir)/vlc-translations-$(VERSION)/convert.po.sh"
	echo "" >>"$(srcdir)/vlc-translations-$(VERSION)/convert.po.sh"
	echo 'msgfmt --statistics -o vlc.mo $$1' >>"$(srcdir)/vlc-translations-$(VERSION)/convert.po.sh"

	$(AMTAR) chof - $(srcdir)/vlc-translations-$(VERSION) \
	  | GZIP=$(GZIP_ENV) gzip -c >$(srcdir)/vlc-translations-$(VERSION).tar.gz

.PHONY: package-macosx package-macosx-zip package-macosx-release package-translations pseudo-bundle

###############################################################################
# Mac OS X project
###############################################################################

EXTRA_DIST += \
	extras/package/macosx/build.sh \
	extras/package/macosx/codesign.sh \
	extras/package/macosx/configure.sh \
	extras/package/macosx/dmg/dmg_settings.py \
	extras/package/macosx/dmg/disk_image.icns \
	extras/package/macosx/dmg/background.tiff \
	extras/package/macosx/asset_sources/vlc_app_icon.svg \
	extras/package/macosx/VLC.entitlements \
	extras/package/macosx/vlc.xcodeproj/project.pbxproj
