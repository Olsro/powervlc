# NFS
NFS_VERSION := 6.0.2
NFS_URL := $(GITHUB)/sahlberg/libnfs/archive/libnfs-$(NFS_VERSION).tar.gz

ifdef BUILD_NETWORK
PKGS += nfs
ifeq ($(call need_pkg,"libnfs >= 1.10"),)
PKGS_FOUND += nfs
endif
endif

ifneq ($(findstring gnutls,$(PKGS)),)
DEPS_nfs = gnutls $(DEPS_gnutls)
endif

$(TARBALLS)/libnfs-$(NFS_VERSION).tar.gz:
	$(call download_pkg,$(NFS_URL),nfs)

.sum-nfs: libnfs-$(NFS_VERSION).tar.gz

nfs: UNPACK_DIR=libnfs-libnfs-$(NFS_VERSION)
nfs: libnfs-$(NFS_VERSION).tar.gz .sum-nfs
	$(UNPACK)
	$(APPLY) $(SRC)/nfs/0001-cant-have-win32.h-referenced-from-a-header-we-instal.patch
	$(APPLY) $(SRC)/nfs/0002-pthread-and-win32-need-to-be-exclusive-in-multithrea.patch
	$(APPLY) $(SRC)/nfs/0003-win32-define-struct-timezone-for-non-mingw-w32.patch
	$(APPLY) $(SRC)/nfs/0004-win32-fix-build-with-MSVC.patch
	$(APPLY) $(SRC)/nfs/0005-win32-don-t-use-pthread-on-Windows.patch
	$(APPLY) $(SRC)/nfs/0001-cmake-export-the-necessary-library-in-the-pkg-config.patch
	$(APPLY) $(SRC)/nfs/0007-tls-add-support-for-kernel-without-TLS_1_3_VERSION.patch
	$(APPLY) $(SRC)/nfs/0008-tls-define-TLS_RX-if-it-s-missing.patch
ifdef HAVE_MACOSX
ifneq ($(call darwin_min_os_at_least, 10.7), true)
	# strndup() is 10.7+: give libnfs a self-contained fallback (appended
	# to the private header every source includes)
	printf '\n#if defined(__APPLE__)\n#include <stdlib.h>\n#include <string.h>\nstatic inline char *vlc_nfs_strndup(const char *s, size_t n)\n{\n    size_t l = 0;\n    while (l < n && s[l]) l++;\n    char *r = malloc(l + 1);\n    if (r) { memcpy(r, s, l); r[l] = 0; }\n    return r;\n}\n#define strndup vlc_nfs_strndup\n#endif\n' \
	    >> $(UNPACK_DIR)/include/libnfs-private.h
endif
endif
	$(MOVE)

NFS_CONF :=
ifdef HAVE_MACOSX
# The 10.4 SDK's net/if.h is not self-contained so the standalone
# check_include_file probe reports it missing, yet libnfs-sync.c needs
# struct ifconf from it: preset the cache to force it on. Safe since
# libnfs-private.h now includes <sys/socket.h> before <net/if.h>.
NFS_CONF += -DHAVE_NET_IF_H:INTERNAL=1
endif

.nfs: nfs toolchain.cmake
	$(CMAKECLEAN)
	$(HOSTVARS_CMAKE) $(CMAKE) $(NFS_CONF)
	+$(CMAKEBUILD)
	$(CMAKEINSTALL)
	touch $@
