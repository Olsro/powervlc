#!/usr/bin/env python3
"""List every Objective-C selector a 32-bit PowerPC Mach-O file sends.

The selectors a plug-in sends are the ones that decide whether it works on an
old system: a class that is missing stops it from loading and says so, but a
missing *method* only raises NSInvalidArgumentException at the moment it is
called -- and AppKit swallows exceptions raised inside a
-performSelectorOnMainThread:, so the interface simply stops building itself
halfway with nothing in the log.

Pairs with check-jaguar-selectors.c, which takes this list and reports the
ones no class on the target system implements.

Usage: list-objc-selectors.py [--sent | --defined] <macho> [macho...]

  --sent     (default) selectors the file sends -- what it needs the system,
             or itself, to implement
  --defined  selectors the file implements itself, to be subtracted from the
             sent list before blaming the system for the rest
"""

import struct
import sys

MH_MAGIC = 0xFEEDFACE
LC_SEGMENT = 0x1


def sections(data):
    """(segname, sectname, addr, size, offset) for every section."""
    magic, _, _, _, ncmds, _, _ = struct.unpack(">7I", data[:28])
    if magic != MH_MAGIC:
        raise ValueError("not a 32-bit big-endian Mach-O")

    out = []
    offset = 28
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack(">2I", data[offset:offset + 8])
        if cmd == LC_SEGMENT:
            segname = data[offset + 8:offset + 24].rstrip(b"\0").decode()
            nsects = struct.unpack(">I", data[offset + 48:offset + 52])[0]
            sect = offset + 56
            for _ in range(nsects):
                sectname = data[sect:sect + 16].rstrip(b"\0").decode()
                addr, size, off = struct.unpack(">3I",
                                                data[sect + 32:sect + 44])
                out.append((segname, sectname, addr, size, off))
                sect += 68
        offset += cmdsize
    return out


def read_cstring(data, sects, addr):
    for _, _, sect_addr, size, off in sects:
        if sect_addr <= addr < sect_addr + size:
            start = off + (addr - sect_addr)
            end = data.index(b"\0", start)
            return data[start:end].decode("utf-8", "replace")
    return None


METHOD_SECTIONS = ("__inst_meth", "__cls_meth",
                   "__cat_inst_meth", "__cat_cls_meth")


def sent_selectors(data, sects):
    found = set()
    for segname, sectname, _, size, off in sects:
        # __message_refs holds one pointer per selector sent; the strings it
        # points at live in __cstring (or __OBJC,__selector_strs on some
        # compilers), so the address is resolved section by section.
        if (segname, sectname) != ("__OBJC", "__message_refs"):
            continue
        for i in range(0, size, 4):
            addr = struct.unpack(">I", data[off + i:off + i + 4])[0]
            name = read_cstring(data, sects, addr)
            if name:
                found.add(name)
    return found


def defined_selectors(data, sects):
    """Walk the method lists: {obsolete, count, {name, types, imp} * count}.

    Before the runtime fixes them up, the name fields still hold pointers to
    the selector strings, which is exactly what is wanted here.
    """
    found = set()
    for segname, sectname, _, size, off in sects:
        if segname != "__OBJC" or sectname not in METHOD_SECTIONS:
            continue
        pos = off
        end = off + size
        while pos + 8 <= end:
            count = struct.unpack(">i", data[pos + 4:pos + 8])[0]
            if count <= 0 or pos + 8 + count * 12 > end:
                break
            for i in range(count):
                entry = pos + 8 + i * 12
                addr = struct.unpack(">I", data[entry:entry + 4])[0]
                name = read_cstring(data, sects, addr)
                if name:
                    found.add(name)
            pos += 8 + count * 12
    return found


def selectors(path, mode):
    with open(path, "rb") as handle:
        data = handle.read()

    sects = sections(data)
    if mode == "--defined":
        return defined_selectors(data, sects)
    return sent_selectors(data, sects)


def main():
    argv = sys.argv[1:]
    mode = "--sent"
    if argv and argv[0] in ("--sent", "--defined"):
        mode = argv.pop(0)

    if not argv:
        print(__doc__, file=sys.stderr)
        return 2

    everything = set()
    for path in argv:
        try:
            everything |= selectors(path, mode)
        except ValueError as exc:
            print("skipped %s: %s" % (path, exc), file=sys.stderr)

    for name in sorted(everything):
        print(name)
    return 0


if __name__ == "__main__":
    sys.exit(main())
