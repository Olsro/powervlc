#!/bin/sh
#
# Install or remove the Broadcom Crystal HD kernel extension bundled with
# PowerVLC. Run with administrator rights by the application; it is also safe
# to run by hand:
#
#   sudo ./crystalhd-kext.sh install /path/to/BroadcomCrystalHD.kext
#   sudo ./crystalhd-kext.sh uninstall
#   sudo ./crystalhd-kext.sh reload
#
# There is no way around a kernel extension here: no version of macOS before
# 10.15 lets a userspace process map a PCIe device's registers, and the cards
# involved only ever appeared in Macs far older than that.

set -e

# AuthorizationExecuteWithPrivileges hands the application a pipe on this
# script's standard output alone; whatever goes to standard error is dropped
# on the floor, leaving the application with nothing to show but a generic
# failure. Fold the two together so the real reason reaches the user.
exec 2>&1

KEXT_NAME="BroadcomCrystalHD.kext"
BUNDLE_ID="com.broadcom.crystalhd.driver"

# /Library/Extensions is the supported home from 10.9 on; older systems only
# look in /System/Library/Extensions.
if [ -d /Library/Extensions ] && [ "$(sw_vers -productVersion | cut -d. -f2)" -ge 9 ] 2>/dev/null; then
    EXT_DIR="/Library/Extensions"
else
    EXT_DIR="/System/Library/Extensions"
fi
TARGET="$EXT_DIR/$KEXT_NAME"

usage() {
    echo "usage: $0 install <path-to-kext> | uninstall | reload" >&2
    exit 2
}

refresh_caches() {
    # Touching the directory is what makes the system notice the change on
    # every release; kextcache is absent or spelled differently on the oldest
    # ones, so its failure must not abort the install.
    touch "$EXT_DIR" 2>/dev/null || true
    if [ -x /usr/sbin/kextcache ]; then
        /usr/sbin/kextcache -system-prelinked-kernel >/dev/null 2>&1 || \
        /usr/sbin/kextcache -system-caches >/dev/null 2>&1 || true
    fi
}

case "$1" in
install)
    SRC="$2"
    [ -n "$SRC" ] || usage
    if [ ! -d "$SRC" ]; then
        echo "source kext not found: $SRC" >&2
        exit 1
    fi

    # A kext must match the architecture of the running kernel, which is not
    # the same thing as the CPU's: plenty of 64-bit Macs boot a 32-bit kernel.
    # uname -m reports the kernel's own architecture.
    KERNEL_ARCH=$(uname -m)
    if ! lipo -info "$SRC/Contents/MacOS/"* 2>/dev/null | grep -q "$KERNEL_ARCH"; then
        echo "This driver does not include a $KERNEL_ARCH slice, and the" >&2
        echo "running kernel is $KERNEL_ARCH." >&2
        case "$(sw_vers -productVersion)" in
        10.6*|10.7*)
            echo "Boot with the 3 and 2 keys held down to start a 32-bit" >&2
            echo "kernel, then install again." >&2
            ;;
        *)
            echo "This version of macOS has no 32-bit kernel to fall back on." >&2
            ;;
        esac
        exit 1
    fi

    # Unload any previous copy first, otherwise the freshly installed one
    # cannot claim the device.
    if kextstat -b "$BUNDLE_ID" 2>/dev/null | grep -q "$BUNDLE_ID"; then
        kextunload -b "$BUNDLE_ID" >/dev/null 2>&1 || true
    fi

    rm -rf "$TARGET"
    cp -R "$SRC" "$TARGET"

    # kextload refuses a bundle that is not owned by root:wheel, which is
    # exactly how it comes out of an application bundle.
    chown -R root:wheel "$TARGET"
    chmod -R 755 "$TARGET"

    refresh_caches

    # Load it now so the user does not have to reboot. On the next boot the
    # PCI match in the kext's Info.plist loads it automatically.
    if [ -x /usr/bin/kextutil ]; then
        /usr/bin/kextutil "$TARGET" || exit 1
    else
        /sbin/kextload "$TARGET" || exit 1
    fi

    echo "installed: $TARGET"
    ;;

uninstall)
    if kextstat -b "$BUNDLE_ID" 2>/dev/null | grep -q "$BUNDLE_ID"; then
        # A device still in use cannot be unloaded; say so rather than leaving
        # the user with a half-removed driver and no explanation.
        if ! kextunload -b "$BUNDLE_ID"; then
            echo "the driver is in use, quit anything playing video and retry" >&2
            exit 1
        fi
    fi

    for dir in /System/Library/Extensions /Library/Extensions; do
        [ -d "$dir/$KEXT_NAME" ] && rm -rf "$dir/$KEXT_NAME"
    done

    refresh_caches
    echo "removed"
    ;;

reload)
    # An abnormal exit can leave the card refusing every open, for every
    # process, while the driver looks perfectly healthy: the service is
    # there, idle, with no client, and DtsDeviceOpen still fails -- even as
    # root. Taking the driver out and putting it back is what clears it,
    # and it is the whole of this verb. Measured on a BCM70015, 05/08/2026.
    if ! kextstat -b "$BUNDLE_ID" 2>/dev/null | grep -q "$BUNDLE_ID"; then
        echo "the driver is not loaded; install it first" >&2
        exit 1
    fi
    if [ ! -d "$TARGET" ]; then
        # Loaded from somewhere this script did not put it: reloading would
        # have nothing to load back.
        for dir in /System/Library/Extensions /Library/Extensions; do
            [ -d "$dir/$KEXT_NAME" ] && TARGET="$dir/$KEXT_NAME"
        done
    fi
    if [ ! -d "$TARGET" ]; then
        echo "cannot find $KEXT_NAME on this system" >&2
        exit 1
    fi

    if ! kextunload -b "$BUNDLE_ID"; then
        echo "the driver is in use, quit anything playing video and retry" >&2
        exit 1
    fi
    if [ -x /usr/bin/kextutil ]; then
        /usr/bin/kextutil "$TARGET" || exit 1
    else
        /sbin/kextload "$TARGET" || exit 1
    fi
    echo "reloaded: $TARGET"
    ;;

*)
    usage
    ;;
esac
