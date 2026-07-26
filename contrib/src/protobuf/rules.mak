# protobuf
PROTOBUF_VERSION := 3.1.0
PROTOBUF_URL := $(GITHUB)/google/protobuf/releases/download/v$(PROTOBUF_VERSION)/protobuf-cpp-$(PROTOBUF_VERSION).tar.gz

ifdef HAVE_MACOSX
# protobuf requires __thread thread-local storage, only available since
# macOS 10.7 (it is only needed by the chromecast module anyway)
ifeq ($(call darwin_min_os_at_least, 10.7), true)
CAN_BUILD_PROTOBUF := 1
endif
else
CAN_BUILD_PROTOBUF := 1
endif

ifdef CAN_BUILD_PROTOBUF
PKGS += protobuf
endif
ifeq ($(call need_pkg, "protobuf-lite >= 3.1.0 protobuf-lite < 3.2.0"),)
PKGS_FOUND += protobuf
endif

$(TARBALLS)/protobuf-$(PROTOBUF_VERSION)-cpp.tar.gz:
	$(call download_pkg,$(PROTOBUF_URL),protobuf)

.sum-protobuf: protobuf-$(PROTOBUF_VERSION)-cpp.tar.gz

DEPS_protobuf = zlib $(DEPS_zlib)
ifdef HAVE_WIN32
DEPS_protobuf += pthreads $(DEPS_pthreads)
endif

PROTOBUFVARS := DIST_LANG="cpp"

protobuf: protobuf-$(PROTOBUF_VERSION)-cpp.tar.gz .sum-protobuf
	$(UNPACK)
	mv protobuf-$(PROTOBUF_VERSION) protobuf-$(PROTOBUF_VERSION)-cpp
	$(APPLY) $(SRC)/protobuf/dont-build-protoc.patch
	$(APPLY) $(SRC)/protobuf/include-algorithm.patch
	$(MOVE)

.protobuf: protobuf
	$(RECONF)
	cd $< && $(HOSTVARS) $(PROTOBUFVARS) ./configure $(HOSTCONF) --with-protoc="$(PROTOC)"
	$(MAKE) -C $< && $(MAKE) -C $< install
	touch $@
