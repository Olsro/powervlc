# GPGERROR
GPGERROR_VERSION := 1.56
GPGERROR_URL := $(GNUGPG)/libgpg-error/libgpg-error-$(GPGERROR_VERSION).tar.bz2

$(TARBALLS)/libgpg-error-$(GPGERROR_VERSION).tar.bz2:
	$(call download_pkg,$(GPGERROR_URL),gpg-error)

PKGS += gpg-error
ifeq ($(call need_pkg,"gpg-error >= 1.33"),)
PKGS_FOUND += gpg-error
endif

.sum-gpg-error: libgpg-error-$(GPGERROR_VERSION).tar.bz2

libgpg-error: libgpg-error-$(GPGERROR_VERSION).tar.bz2 .sum-gpg-error
	$(UNPACK)
	$(call pkg_static,"src/gpg-error.pc.in")
ifdef HAVE_MACOSX
ifneq ($(call darwin_min_os_at_least, 10.5), true)
	# On the 10.4 SDK unsetenv() returns void (pre-POSIX-2008 Apple
	# prototype), so `if (unsetenv(name))` does not compile
	sed -i.orig -e 's/if (unsetenv (name))/unsetenv (name); if (0)/' \
	    $(UNPACK_DIR)/src/sysutils.c
endif
endif
	# gpg-error doesn't know about mingw32uwp but it's the same as mingw32
	$(APPLY) $(SRC)/gpg-error/gpg-error-uwp-fix.patch

	# use CreateFile2 in Win8 as CreateFileW is forbidden in UWP
	$(APPLY) $(SRC)/gpg-error/0004-use-WCHAR-API-for-temporary-windows-folder.patch
	$(APPLY) $(SRC)/gpg-error/gpg-error-createfile2.patch

	# don't use GetFileSize on UWP
	$(APPLY) $(SRC)/gpg-error/gpg-error-uwp-GetFileSize.patch
	$(APPLY) $(SRC)/gpg-error/0007-don-t-use-GetThreadLocale-on-UWP.patch
	$(APPLY) $(SRC)/gpg-error/0008-don-t-use-GetUserNameW-on-Windows-10.patch
	$(APPLY) $(SRC)/gpg-error/0009-gpg-error-config.in-add-missing-GPG_ERROR_CONFIG_LIB.patch
	$(APPLY) $(SRC)/gpg-error/0011-logging-add-ws2tcpip.h-include-for-proper-inet_pton-.patch
	$(APPLY) $(SRC)/gpg-error/0012-use-GetCurrentProcessId-in-UWP.patch
	$(APPLY) $(SRC)/gpg-error/0013-configure-allow-building-Windows-with-disable-thread.patch
	$(APPLY) $(SRC)/gpg-error/0014-core-disable-locking-API-with-disable-threads.patch
	$(APPLY) $(SRC)/gpg-error/0015-core-disable-process-spawning-with-disable-threads.patch
	$(APPLY) $(SRC)/gpg-error/0016-core-disable-registry-access-in-UWP.patch
ifdef HAVE_WIN32
ifeq ($(ARCH),i386)
	# _putenv_s() is a "secure CRT" function: it only appears in the
	# msvcrt.dll of Windows Vista. mingw-w64 always defines
	# _CRT_SECURE_CPP_OVERLOAD_STANDARD_NAMES, so gpgrt_setenv() imports it
	# unconditionally and the DLL then fails to load on Windows XP with
	# "the procedure entry point _putenv_s could not be located in
	# msvcrt.dll" -- fatal, because libvlccore itself pulls gpg-error in
	# through libgcrypt. The win32 slice is the one whose floor is XP SP3.
	#
	# The putenv() branch gpg-error keeps for compilers without the secure
	# CRT cannot be selected instead: it reads a `buf` that is declared
	# nowhere in that scope, so it has plainly never been compiled. Keep the
	# branch that does build and give it a _putenv_s() of our own, written
	# the way that dead branch meant to.
	sed -i.orig -e 's|^/\* Wrapper around setenv so that we can have the same function in$$|static int gpgrt_putenv_s_compat (const char *name, const char *value)\n{\n  /* PowerVLC: _putenv_s() is absent from the msvcrt.dll of Windows XP. */\n  char *buf = _gpgrt_strconcat (name, "=", value, NULL);\n  if (!buf)\n    return ENOMEM;\n  if (putenv (buf))\n    return EINVAL;\n  return 0;\n}\n\n&|' \
	    -e 's/_putenv_s (/gpgrt_putenv_s_compat (/g' \
	    $(UNPACK_DIR)/src/sysutils.c
endif
endif
	# use the ANSI version of Environment API's as the rest of the code
	sed -i.orig -e 's/ExpandEnvironmentStrings /ExpandEnvironmentStringsA /g' $(UNPACK_DIR)/src/w32-reg.c
	sed -i.orig -e 's/SetEnvironmentVariable /SetEnvironmentVariableA /g' $(UNPACK_DIR)/src/sysutils.c
	sed -i.orig -e 's/GetEnvironmentVariable /GetEnvironmentVariableA /g' $(UNPACK_DIR)/src/sysutils.c

	$(MOVE)

GPGERROR_CONF := \
	--disable-nls \
	--disable-languages \
	--disable-tests \
	--disable-doc \
	--enable-install-gpg-error-config \
	--disable-threads

.gpg-error: libgpg-error
	$(RECONF)
	$(MAKEBUILDDIR)
	$(MAKECONFIGURE) $(GPGERROR_CONF)
	+$(MAKEBUILD) bin_PROGRAMS=
	+$(MAKEBUILD) bin_PROGRAMS= install
	touch $@
