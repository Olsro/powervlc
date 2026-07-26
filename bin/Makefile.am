# Building vlc
#
if BUILD_VLC
if HAVE_OSX
bin_PROGRAMS = powervlc-osx
noinst_PROGRAMS = powervlc-osx-static
else
bin_PROGRAMS = powervlc
noinst_PROGRAMS = powervlc-static
endif
endif
EXTRA_DIST = vlc_win32_rc.rc.in
CLEANFILES = vlc_win32_rc.rc

SUFFIXES = .rc.in .rc

AM_CPPFLAGS = $(CPPFLAGS_vlc)
AM_CFLAGS = $(CFLAGS_vlc)
if HAVE_DBUS
AM_CPPFLAGS += -DHAVE_DBUS
endif

#
# Main VLC executable
#
powervlc_LDADD = ../lib/libpowervlc.la $(LIBPTHREAD)
powervlc_CPPFLAGS = $(AM_CPPFLAGS)
if !HAVE_WIN32
powervlc_SOURCES = vlc.c override.c
powervlc_LDADD += $(LIBDL)
else
powervlc_SOURCES = winvlc.c
powervlc_DEPENDENCIES = vlc_win32_rc.$(OBJEXT)
powervlc_LDFLAGS = -mwindows -Wc,-static
powervlc_LDADD += vlc_win32_rc.$(OBJEXT)
libbreakpad_wrapper_la_SOURCES = breakpad.cpp
libbreakpad_wrapper_la_LIBADD = $(BREAKPAD_LIBS)
libbreakpad_wrapper_la_LDFLAGS = -static
libbreakpad_wrapper_la_CXXFLAGS = $(AM_CXXFLAGS) $(BREAKPAD_CFLAGS) -DBREAKPAD_URL=\"@BREAKPAD_URL@\"
if HAVE_BREAKPAD
noinst_LTLIBRARIES = libbreakpad_wrapper.la
powervlc_LDADD += libbreakpad_wrapper.la -lstdc++ -lwininet
powervlc_DEPENDENCIES += libbreakpad_wrapper.la
powervlc_CPPFLAGS += -DHAVE_BREAKPAD
endif
endif

powervlc_osx_SOURCES = darwinvlc.m
powervlc_osx_LDFLAGS = $(LDFLAGS_vlc) -Wl,-framework,CoreFoundation,-framework,Cocoa
if HAVE_DYLD_RPATH
powervlc_osx_LDFLAGS += -Xlinker -rpath -Xlinker "@executable_path/lib/"
powervlc_osx_LDFLAGS += -Xlinker -rpath -Xlinker "@executable_path/plugins/"
powervlc_osx_LDFLAGS += -Xlinker -rpath -Xlinker "@executable_path/../Frameworks/"
endif
if HAVE_BREAKPAD
powervlc_osx_LDFLAGS += -Wl,-framework,Breakpad
powervlc_osx_OBJCFLAGS = -F$(CONTRIB_DIR)/Frameworks
powervlc_osx_CPPFLAGS = -DHAVE_BREAKPAD
endif
powervlc_osx_LDADD = ../lib/libpowervlc.la

powervlc_osx_static_SOURCES = $(powervlc_osx_SOURCES)
powervlc_osx_static_OBJCFLAGS = $(AM_OBJCFLAGS) \
	-DTOP_BUILDDIR=\"$$(cd "$(top_builddir)"; pwd)\" \
	-DTOP_SRCDIR=\"$$(cd "$(top_srcdir)"; pwd)\" \
	$(NULL)
powervlc_osx_static_LDFLAGS = $(powervlc_osx_LDFLAGS) -static
if HAVE_DYLD_RPATH
powervlc_osx_static_LDFLAGS += -Xlinker -rpath -Xlinker "@executable_path/../lib/.libs/"
powervlc_osx_static_LDFLAGS += -Xlinker -rpath -Xlinker "@executable_path/../src/.libs/"
powervlc_osx_static_LDFLAGS += -Xlinker -rpath -Xlinker "@executable_path/../Frameworks/"
endif
powervlc_osx_static_LDADD = $(powervlc_osx_LDADD)
if HAVE_BREAKPAD
powervlc_osx_static_LDFLAGS += -Wl,-framework,Breakpad
powervlc_osx_static_OBJCFLAGS += -F$(CONTRIB_DIR)/Frameworks
powervlc_osx_static_CPPFLAGS = -DHAVE_BREAKPAD
endif


#
# Static (debug) VLC executable
#
powervlc_static_SOURCES = $(powervlc_SOURCES)
powervlc_static_CFLAGS = $(AM_CFLAGS) \
	-DTOP_BUILDDIR=\"$$(cd "$(top_builddir)"; pwd)\" \
	-DTOP_SRCDIR=\"$$(cd "$(top_srcdir)"; pwd)\" \
	$(NULL)
powervlc_static_CPPFLAGS = $(powervlc_CPPFLAGS)
powervlc_static_DEPENDENCIES = $(powervlc_DEPENDENCIES)
powervlc_static_LDADD = $(powervlc_LDADD)
powervlc_static_LDFLAGS = $(powervlc_LDFLAGS) -no-install -static

#
# Root wrapper
#
if BUILD_VLC
if !HAVE_WIN32
if !HAVE_OS2
bin_PROGRAMS += powervlc-wrapper
endif
endif
endif
powervlc_wrapper_SOURCES = rootwrap.c
powervlc_wrapper_LDADD = $(SOCKET_LIBS)

vlc_win32_rc.rc: $(top_builddir)/config.status vlc_win32_rc.rc.in
	cd "$(top_builddir)" && \
	$(SHELL) ./config.status --file="bin/$@"

vlc_win32_rc.$(OBJEXT): vlc_win32_rc.rc $(top_srcdir)/extras/package/win32/vlc.exe.manifest
	$(WINDRES) --include-dir $(top_srcdir)/share/icons --include-dir $(top_srcdir)/extras/package/win32 -i $< -o $@

#
# Plug-ins cache generator
#
if HAVE_DYNAMIC_PLUGINS
vlclib_PROGRAMS = powervlc-cache-gen
endif
powervlc_cache_gen_SOURCES = cachegen.c
powervlc_cache_gen_LDADD = \
	$(GNUGETOPT_LIBS) \
	../compat/libcompat.la \
	../lib/libpowervlc.la
if HAVE_WIN32
powervlc_cache_gen_LDADD += vlc_win32_rc.$(OBJEXT)
powervlc_cache_gen_LDFLAGS = -Wc,-static
powervlc_cache_gen_DEPENDENCIES = vlc_win32_rc.$(OBJEXT)
endif

#
# Plug-ins cache
#
if HAVE_DYNAMIC_PLUGINS
noinst_DATA = ../modules/plugins.dat
endif
MOSTLYCLEANFILES = $(noinst_DATA)

if HAVE_OSX
if BUILD_VLC
install-data-local:
	cd $(bindir); mv powervlc-osx powervlc

endif
endif

.PHONY: ../modules/plugins.dat

../modules/plugins.dat: powervlc-cache-gen$(EXEEXT)
	$(AM_V_at)rm -f ../modules/plugins.dat
	$(AM_V_GEN)if test "$(build)" = "$(host)"; then \
		./powervlc-cache-gen$(EXEEXT) `realpath ../modules` ; \
	else \
		echo "Cross-compilation: cache generation skipped!" ; \
	fi
