guidir = $(pluginsdir)/gui
gui_LTLIBRARIES =

libncurses_plugin_la_SOURCES = gui/ncurses.c
libncurses_plugin_la_CPPFLAGS = $(AM_CPPFLAGS) $(NCURSES_CFLAGS)
libncurses_plugin_la_LIBADD = $(NCURSES_LIBS) $(LIBPTHREAD) $(LIBM)
if HAVE_NCURSES
gui_LTLIBRARIES += libncurses_plugin.la
endif

EXTRA_DIST += gui/eject.c

libminimal_macosx_plugin_la_SOURCES = \
	gui/minimal_macosx/intf.h gui/minimal_macosx/intf.m \
	gui/minimal_macosx/misc.h gui/minimal_macosx/misc.m \
	gui/minimal_macosx/VLCMinimalVoutWindow.h gui/minimal_macosx/VLCMinimalVoutWindow.m \
	gui/minimal_macosx/macosx.c
# Manual retain/release (no -fobjc-arc): ARC requires the Mac OS X 10.6
# Obj-C runtime, and this module's purpose is providing a video window on
# older releases where the full macosx interface cannot build.
# Carbon: SetSystemUIMode(), the pre-10.6 way to hide the menu bar/Dock.
libminimal_macosx_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-exceptions
libminimal_macosx_plugin_la_LDFLAGS = $(AM_LDFLAGS) -rpath '$(guidir)' -Wl,-framework,Cocoa,-framework,Carbon
EXTRA_LTLIBRARIES += libminimal_macosx_plugin.la
gui_LTLIBRARIES += $(LTLIBminimal_macosx)

# Legacy Mac OS X interface: video window + main menu for releases too old
# for the full macosx interface (target < 10.6). Manual retain/release
# (ARC requires the 10.6 runtime); Carbon for SetSystemUIMode(), the
# pre-10.6 way to hide the menu bar/Dock in fullscreen.
liblegacy_macosx_plugin_la_SOURCES = \
	gui/macosx_crystalhd.h gui/macosx_crystalhd.m \
	gui/macosx_browser_addon.h gui/macosx_browser_addon.m \
	gui/legacy_macosx/intf.h gui/legacy_macosx/intf.m \
	gui/legacy_macosx/misc.h gui/legacy_macosx/misc.m \
	gui/legacy_macosx/VLCLegacyVoutWindow.h gui/legacy_macosx/VLCLegacyVoutWindow.m \
	gui/legacy_macosx/VLCLegacyCustomCropAr.h gui/legacy_macosx/VLCLegacyCustomCropAr.m \
	gui/legacy_macosx/VLCLegacyMenu.h gui/legacy_macosx/VLCLegacyMenu.m \
	gui/legacy_macosx/VLCLegacyCoreInteraction.h gui/legacy_macosx/VLCLegacyCoreInteraction.m \
	gui/legacy_macosx/VLCLegacyMainWindow.h gui/legacy_macosx/VLCLegacyMainWindow.m \
	gui/legacy_macosx/VLCLegacyOpen.h gui/legacy_macosx/VLCLegacyOpen.m \
	gui/legacy_macosx/VLCLegacyOutput.h gui/legacy_macosx/VLCLegacyOutput.m \
	gui/legacy_macosx/VLCLegacyMain.h gui/legacy_macosx/VLCLegacyMain.m \
	gui/legacy_macosx/VLCLegacyPrefs.h gui/legacy_macosx/VLCLegacyPrefs.m \
	gui/legacy_macosx/VLCLegacyAudioEffects.h gui/legacy_macosx/VLCLegacyAudioEffects.m \
	gui/legacy_macosx/VLCLegacyHUDWindow.h gui/legacy_macosx/VLCLegacyHUDWindow.m \
	gui/legacy_macosx/VLCLegacyVideoEffects.h gui/legacy_macosx/VLCLegacyVideoEffects.m \
	gui/legacy_macosx/VLCLegacyTrackSync.h gui/legacy_macosx/VLCLegacyTrackSync.m \
	gui/legacy_macosx/VLCLegacyMessages.h gui/legacy_macosx/VLCLegacyMessages.m \
	gui/legacy_macosx/VLCLegacyConvertAndSave.h gui/legacy_macosx/VLCLegacyConvertAndSave.m \
	gui/legacy_macosx/VLCLegacyAddons.h gui/legacy_macosx/VLCLegacyAddons.m \
	gui/legacy_macosx/VLCLegacyExtensionsDialogProvider.h \
	gui/legacy_macosx/VLCLegacyExtensionsDialogProvider.m \
	gui/legacy_macosx/VLCLegacyMediaInfo.h gui/legacy_macosx/VLCLegacyMediaInfo.m \
	gui/legacy_macosx/VLCLegacyBookmarks.h gui/legacy_macosx/VLCLegacyBookmarks.m \
	gui/legacy_macosx/VLCLegacyFSPanel.h gui/legacy_macosx/VLCLegacyFSPanel.m \
	gui/legacy_macosx/VLCLegacyControls.h gui/legacy_macosx/VLCLegacyControls.m \
	gui/legacy_macosx/VLCLegacySeekThumbnailer.h \
	gui/legacy_macosx/VLCLegacySeekThumbnailer.m \
	gui/legacy_macosx/VLCLegacyAbout.h gui/legacy_macosx/VLCLegacyAbout.m \
	gui/legacy_macosx/VLCLegacyAppleRemote.h gui/legacy_macosx/VLCLegacyAppleRemote.m \
	gui/legacy_macosx/VLCLegacyMediaKeys.h gui/legacy_macosx/VLCLegacyMediaKeys.m \
	gui/legacy_macosx/VLCLegacySystemVolume.h gui/legacy_macosx/VLCLegacySystemVolume.c \
	gui/legacy_macosx/macosx.c
# VLC_OBJC_ANCHOR_TAG: see the same flag on libmacosx_plugin -- the two shared
# .m files each define an empty anchor class, and both plugins can be resident
# together, so the class names have to differ per plugin.
liblegacy_macosx_plugin_la_OBJCFLAGS = $(AM_OBJCFLAGS) -fobjc-exceptions \
	-DVLC_OBJC_ANCHOR_TAG=Legacy
# Force per-target object names for the C sources too: without this,
# macosx.c compiles as plain macosx.lo and the MODULE_NAME rule (derived
# from the object basename) registers the module as "macosx" -- colliding
# with the modern interface module, and module_exists("legacy_macosx")
# can never find it (the interface switcher menu item depends on it).
liblegacy_macosx_plugin_la_CFLAGS = $(AM_CFLAGS)
# IOKit: optical media type detection (Open dialog) and the Apple Remote
# HID access; CoreAudio: system volume control for the Apple Remote;
# ApplicationServices: the CGEventTap of the media keys support.
liblegacy_macosx_plugin_la_LDFLAGS = $(AM_LDFLAGS) -rpath '$(guidir)' -Wl,-framework,Cocoa,-framework,Carbon,-framework,IOKit,-framework,CoreAudio,-framework,ApplicationServices,-framework,Security
EXTRA_LTLIBRARIES += liblegacy_macosx_plugin.la
gui_LTLIBRARIES += $(LTLIBlegacy_macosx)

include gui/macosx/Makefile.am
include gui/qt/Makefile.am
include gui/skins2/Makefile.am
