#!/usr/bin/env python3
"""Rewrite a Mach-O's install name, or a dependency it names, in place.

This is install_name_tool's job, and it is done here instead because
install_name_tool cannot be run on one of the slices at all.

The x86_64 slice deploys to 10.5, and on a deployment target that old the
current ld (ld-1230) lays __LINKEDIT out in an order cctools refuses to touch:
every dylib comes back "function starts data out of place". build.sh already
documents that for strip (see the -Wl,-S comment there) and reproduces it in
three lines; install_name_tool hits the very same wall, on the stock library
straight out of contrib:

    clang -arch x86_64 -mmacosx-version-min=10.5 -g -dynamiclib t.c -o t.dylib
    install_name_tool -id @executable_path/lib/t.dylib t.dylib
    # -> fatal error: function starts data out of place

Rather than fix that slice one way and the other six another -- which is how a
packaging bug survives on the slice nobody re-checks -- every slice goes
through this.

What makes it safe is that we only ever *shorten* a name: an absolute build
tree path ("/Users/.../contrib/<triple>/lib/libaacs.0.dylib") becomes
"@executable_path/lib/libaacs.dylib". The string lives inside the dylib load
command itself, whose cmdsize the linker already rounded up, so the
replacement is written over the old bytes and NUL-padded to the end of the
command. Nothing moves: not one segment, section, symbol or __LINKEDIT offset
changes, which is exactly why the layout cctools chokes on is irrelevant here.
A name that would not fit is an error, never a silent no-op.

Mach-O code signatures are not touched either -- and are invalidated by any
edit, here as with install_name_tool. The caller re-signs (build.sh does).

Usage:
    set-dylib-name.py --id <new-name> <file>...
    set-dylib-name.py --change <old-name> <new-name> <file>...

Exit status is 0 when every file was already correct or was rewritten, 1 on
any failure. --change on a file that does not name <old-name> is not a
failure: it is the normal case when sweeping a whole bundle.
"""

import struct
import sys

MH_MAGIC = 0xFEEDFACE
MH_CIGAM = 0xCEFAEDFE
MH_MAGIC_64 = 0xFEEDFACF
MH_CIGAM_64 = 0xCFFAEDFE
FAT_MAGIC = 0xCAFEBABE
FAT_CIGAM = 0xBEBAFECA
FAT_MAGIC_64 = 0xCAFEBABF
FAT_CIGAM_64 = 0xBFBAFECA

LC_REQ_DYLD = 0x80000000
LC_ID_DYLIB = 0xD
# Every load command that carries a dylib_command, i.e. a name we may have to
# follow. LC_LOAD_UPWARD_DYLIB and LC_LAZY_LOAD_DYLIB never show up in this
# bundle; they cost one list entry each and would otherwise be a silent miss.
DEPENDENCY_COMMANDS = (
    0xC,                    # LC_LOAD_DYLIB
    0x18 | LC_REQ_DYLD,     # LC_LOAD_WEAK_DYLIB
    0x1F | LC_REQ_DYLD,     # LC_REEXPORT_DYLIB
    0x20,                   # LC_LAZY_LOAD_DYLIB
    0x23 | LC_REQ_DYLD,     # LC_LOAD_UPWARD_DYLIB
)


class MachOError(Exception):
    pass


def _slices(data):
    """Yield the file offset of every thin Mach-O header in the file."""
    if len(data) < 8:
        raise MachOError("too short to be a Mach-O")

    magic = struct.unpack(">I", data[:4])[0]
    if magic in (FAT_MAGIC, FAT_CIGAM, FAT_MAGIC_64, FAT_CIGAM_64):
        # A fat header is big-endian by definition, whichever way the magic
        # reads; the CIGAM spellings only exist because a little-endian tool
        # wrote the number without swapping it.
        wide = magic in (FAT_MAGIC_64, FAT_CIGAM_64)
        endian = ">" if magic in (FAT_MAGIC, FAT_MAGIC_64) else "<"
        nfat = struct.unpack(endian + "I", data[4:8])[0]
        entry = 32 if wide else 20
        off_field = endian + ("Q" if wide else "I")
        for i in range(nfat):
            base = 8 + i * entry
            # fat_arch: cputype, cpusubtype, offset, size, align
            at = base + (16 if wide else 8)
            yield struct.unpack(off_field, data[at:at + (8 if wide else 4)])[0]
        return

    yield 0


def _header(data, base):
    """Return (endian, is64, ncmds, first-load-command-offset)."""
    magic = struct.unpack(">I", data[base:base + 4])[0]
    if magic == MH_MAGIC:
        endian, is64 = ">", False
    elif magic == MH_CIGAM:
        endian, is64 = "<", False
    elif magic == MH_MAGIC_64:
        endian, is64 = ">", True
    elif magic == MH_CIGAM_64:
        endian, is64 = "<", True
    else:
        raise MachOError("not a Mach-O (magic 0x%08x)" % magic)

    # mach_header: magic cputype cpusubtype filetype ncmds sizeofcmds flags
    # mach_header_64 appends a reserved word.
    ncmds = struct.unpack(endian + "I", data[base + 16:base + 20])[0]
    return endian, is64, ncmds, base + (32 if is64 else 28)


def _dylib_names(data, base):
    """Yield (cmd, lc_offset, cmdsize, name_offset, name) per dylib command."""
    endian, _is64, ncmds, off = _header(data, base)
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack(endian + "II", data[off:off + 8])
        if cmdsize < 8 or cmdsize % 4:
            raise MachOError("malformed load command (cmdsize %d)" % cmdsize)
        if cmd == LC_ID_DYLIB or cmd in DEPENDENCY_COMMANDS:
            # dylib_command: cmd cmdsize | name.offset timestamp
            # current_version compatibility_version
            name_off = struct.unpack(endian + "I", data[off + 8:off + 12])[0]
            if not 12 <= name_off < cmdsize:
                raise MachOError("dylib name offset %d out of its command"
                                 % name_off)
            raw = data[off + name_off:off + cmdsize]
            yield cmd, off, cmdsize, name_off, raw.split(b"\0", 1)[0].decode()
        off += cmdsize


def rewrite(path, new_name, old_name=None, set_id=False):
    """Rewrite this file's id (set_id) or its references to old_name.

    Returns the number of load commands changed.
    """
    with open(path, "rb") as fh:
        data = bytearray(fh.read())

    new = new_name.encode()
    changed = 0

    for base in _slices(data):
        for cmd, off, cmdsize, name_off, name in _dylib_names(data, base):
            if set_id:
                if cmd != LC_ID_DYLIB or name == new_name:
                    continue
            else:
                if cmd == LC_ID_DYLIB or name != old_name:
                    continue

            room = cmdsize - name_off
            if len(new) + 1 > room:
                raise MachOError(
                    "\"%s\" does not fit in the load command (%d bytes of "
                    "room, %d needed). Only shortening a name is safe in "
                    "place; a longer one needs the command to grow, which "
                    "moves everything after it." % (new_name, room,
                                                    len(new) + 1))
            data[off + name_off:off + cmdsize] = new.ljust(room, b"\0")
            changed += 1

    if changed:
        with open(path, "r+b") as fh:
            fh.write(data)
    return changed


def main(argv):
    if len(argv) >= 4 and argv[1] == "--id":
        mode, new, old, files = "id", argv[2], None, argv[3:]
    elif len(argv) >= 5 and argv[1] == "--change":
        mode, old, new, files = "change", argv[2], argv[3], argv[4:]
    else:
        sys.stderr.write(__doc__.split("Usage:", 1)[1].lstrip("\n"))
        return 1

    status = 0
    for path in files:
        try:
            n = rewrite(path, new, old_name=old, set_id=(mode == "id"))
        except (MachOError, OSError, struct.error) as exc:
            sys.stderr.write("set-dylib-name: %s: %s\n" % (path, exc))
            status = 1
            continue
        if n:
            print("  NAME     %s: %s -> %s"
                  % (path, "id" if mode == "id" else old, new))
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
