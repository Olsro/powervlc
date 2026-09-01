#!/bin/sh
# Verify an x86 Linux compiler can run completely natively in the arm64 image.
# This is intentionally a small, deterministic prerequisite check before the
# full VLC/AppImage cross recipe is enabled.
set -eu

case "${1:-}" in
    amd64) triplet=x86_64-linux-gnu; expected='ELF 64-bit.*x86-64' ;;
    i386)  triplet=i686-linux-gnu;   expected='ELF 32-bit.*Intel 80386' ;;
    *) echo "Usage: $0 amd64|i386" >&2; exit 64 ;;
esac

sysroot=/opt/sysroots/${triplet}-glibc-2.27
[ -f "$sysroot/.powervlc-sysroot" ] || { echo "Missing $sysroot" >&2; exit 1; }
src=/tmp/pvlc-cross-check.c
out=/tmp/pvlc-cross-check
printf '%s\n' '#define _GNU_SOURCE' '#include <sys/mman.h>' \
  'int main(void) { return memfd_create("pvlc", 0) < -1; }' > "$src"
"$triplet-gcc" --sysroot="$sysroot" -O2 -Werror "$src" -o "$out"

description="$(file -b "$out")"
printf '%s\n' "$description"
printf '%s\n' "$description" | grep -Eq "$expected" || {
    echo "ERROR: expected a $1 ELF executable" >&2
    exit 1
}

# Reading an ELF header does not execute it.  This assertion catches an
# accidental fallback to the arm64 compiler without relying on QEMU.
machine="$(readelf -h "$out" | sed -n 's/^ *Machine: *//p')"
case "$1:$machine" in
    amd64:Advanced\ Micro\ Devices\ X86-64|i386:Intel\ 80386) ;;
    *) echo "ERROR: unexpected ELF machine: $machine" >&2; exit 1 ;;
esac

echo "OK: $triplet compiler and linker ran natively; output is $machine."
readelf --version-info "$out" | grep -q 'GLIBC_2.27' || {
    echo "ERROR: executable is not linked against the glibc 2.27 sysroot" >&2
    exit 1
}
echo "OK: executable is linked against the Ubuntu 18.04 glibc 2.27 sysroot."
