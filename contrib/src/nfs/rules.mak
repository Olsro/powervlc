# NFS
NFS_VERSION := 5.0.1
NFS_URL := $(GITHUB)/sahlberg/libnfs/archive/libnfs-$(NFS_VERSION).tar.gz

PKGS += nfs
ifeq ($(call need_pkg,"libnfs >= 1.10"),)
PKGS_FOUND += nfs
endif

$(TARBALLS)/libnfs-$(NFS_VERSION).tar.gz:
	$(call download_pkg,$(NFS_URL),nfs)

.sum-nfs: libnfs-$(NFS_VERSION).tar.gz

nfs: libnfs-$(NFS_VERSION).tar.gz .sum-nfs
	$(UNPACK)
	mv libnfs-libnfs-$(NFS_VERSION) libnfs-$(NFS_VERSION)
	$(UPDATE_AUTOCONFIG)
	$(APPLY) $(SRC)/nfs/0001-fallback-IFNAMSIZ.patch
	$(MOVE)

NFS_CONF := --disable-examples --disable-utils --disable-werror
ifdef HAVE_MACOSX
# The 10.4 SDK's net/if.h is not self-contained so configure's
# standalone probe reports it missing, yet libnfs-sync.c needs struct
# ifconf from it: force it on, the patch makes libnfs-private.h include
# <sys/socket.h> right before it.
NFS_CONF += ac_cv_header_net_if_h=yes
endif

.nfs: nfs
	cd $< && ./bootstrap
	cd $< && $(HOSTVARS) ./configure $(HOSTCONF) $(NFS_CONF)
	$(MAKE) -C $< install
	touch $@
