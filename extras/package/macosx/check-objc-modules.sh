#!/bin/sh
#############################################################################
# check-objc-modules.sh: find Objective-C modules with a NULL symtab
#############################################################################
# Mac OS X 10.2's _objcInit() iterates the __module_info records of an image
# and loads module->symtab without ever testing it for NULL. GCC leaves that
# pointer NULL whenever an Objective-C translation unit defines no class of
# its own -- a .m file that is really plain C, or one that only sends
# messages. A single such file makes dlopen() of its plug-in bus-error, and
# because that happens inside the module bank the whole process dies before
# printing a line: no "cannot load module", no log at all.
#
# 10.3 and later check the pointer, so this only ever matters for the 10.2
# slices -- but the fix belongs in the source (give the file a class, or
# compile it as C if it has no Objective-C in it), so the check runs on the
# built bundle and fails the build rather than warning.
#
# Usage: check-objc-modules.sh <bundle-or-binary> [more binaries...]
#############################################################################

set -e

if [ $# -lt 1 ]; then
    echo "usage: $0 <VLC.app | binary> [binary...]" >&2
    exit 2
fi

# One __module_info record is 16 bytes: version, size, name, symtab. Only the
# last word matters here.
scan_one() {
    otool -s __OBJC __module_info "$1" 2>/dev/null \
        | tail -n +3 \
        | awk '{ for (i = 2; i <= NF; i++) print $i }' \
        | awk 'NR % 4 == 0 && $1 == "00000000"' \
        | wc -l \
        | tr -d ' '
}

status=0
for target; do
    if [ -d "$target" ]; then
        binaries=$(find "$target" -type f \
            \( -name "*.dylib" -o -name "*.so" -o -perm -u+x \) )
    else
        binaries="$target"
    fi

    for binary in $binaries; do
        # Mach-O only; skip scripts, plists and the rest of a bundle
        case $(file -b "$binary" 2>/dev/null) in
            *Mach-O*) ;;
            *) continue ;;
        esac

        count=$(scan_one "$binary")
        if [ "$count" != "0" ] && [ -n "$count" ]; then
            echo "objc-modules: $binary: $count Objective-C module(s) with a NULL symtab" >&2
            status=1
        fi
    done
done

if [ $status -ne 0 ]; then
    echo "objc-modules: these would bus-error on 10.2 as soon as they are loaded." >&2
    echo "objc-modules: give each offending .m file one class of its own, or" >&2
    echo "objc-modules: compile it as .c when it holds no Objective-C at all." >&2
fi

exit $status
