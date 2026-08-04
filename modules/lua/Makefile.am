luadir = $(pluginsdir)/lua

liblua_plugin_la_SOURCES = \
	lua/extension.c lua/extension.h \
	lua/extension_thread.c \
	lua/intf.c \
	lua/meta.c \
	lua/demux.c \
	lua/services_discovery.c \
	lua/vlc.c lua/vlc.h \
	lua/libs.h \
	lua/libs/configuration.c \
	lua/libs/equalizer.c \
	lua/libs/gettext.c \
	lua/libs/dialog.c \
	lua/libs/httpd.c \
	lua/libs/input.c lua/libs/input.h \
	lua/libs/messages.c \
	lua/libs/misc.c lua/libs/misc.h \
	lua/libs/net.c \
	lua/libs/objects.c lua/libs/objects.h \
	lua/libs/osd.c \
	lua/libs/playlist.c \
	lua/libs/sd.c \
	lua/libs/stream.c \
	lua/libs/strings.c \
	lua/libs/variables.c lua/libs/variables.h \
	lua/libs/video.c \
	lua/libs/vlm.c \
	lua/libs/volume.c \
	lua/libs/xml.c \
	lua/libs/io.c \
	lua/libs/errno.c \
	lua/libs/clipboard.c \
	lua/libs/http.c \
	lua/libs/browser.c \
	lua/libs/keystore.c

if HAVE_WIN32
liblua_plugin_la_SOURCES += lua/libs/win.c
endif
liblua_plugin_la_CFLAGS = $(AM_CFLAGS) $(LUA_CFLAGS) -I$(srcdir)/lua
liblua_plugin_la_LIBADD = $(LUA_LIBS) $(SOCKET_LIBS) $(LIBDL) $(LIBM) $(LIBPTHREAD)
# lua/libs/http.c undoes the Content-Encoding a fingerprinting guard
# forces us to ask for
liblua_plugin_la_LIBADD += -lz
# Set unconditionally, then append per platform -- the idiom every other plugin
# here follows (see libscreen/libcdda in modules/access/Makefile.am). As soon as
# a *_la_LDFLAGS exists ANYWHERE in the file, automake links with that variable
# instead of falling back to AM_LDFLAGS; defining it only inside "if HAVE_DARWIN"
# therefore left it EMPTY everywhere else, silently dropping the -no-undefined
# that common.am puts in AM_LDFLAGS. On mingw that is fatal and nowhere near the
# cause: "libtool: error: can't build aarch64-w64-mingw32 shared library unless
# -no-undefined is specified" while linking liblua_plugin.la.
liblua_plugin_la_LDFLAGS = $(AM_LDFLAGS)
if HAVE_DARWIN
# lua/libs/clipboard.c reaches NSPasteboard through the Objective-C runtime
liblua_plugin_la_LIBADD += -lobjc
liblua_plugin_la_LDFLAGS += -Wl,-framework,CoreFoundation
endif
if HAVE_WIN32
# lua/libs/clipboard.c uses the Win32 clipboard
liblua_plugin_la_LIBADD += -luser32
endif
if BUILD_LUA
lua_LTLIBRARIES = liblua_plugin.la
endif
