#!/usr/bin/env python3
"""Add a table of contents to a Mach-O dylib, for Mac OS X 10.2's dyld.

Darwin 6 (Mac OS X 10.2) looks up a dylib's exported symbols through the
LC_DYSYMTAB *table of contents* -- a name-sorted array of (symbol, module)
pairs -- and through the module and reference tables beside it. From 10.4 on,
dyld ignores all three and scans the sorted external symbols instead.

Modern ld64 stopped emitting them: it only ever produces single-module dylibs,
and `-multi_module` is accepted and silently ignored (verified on ld64-236,
ntoc stays 0). The result loads fine on 10.4 and up, and on 10.2 every one of
its symbols reads as undefined -- the library is mapped, dyld simply has
nothing to search. Measured on a 10.2.1 iBook: a five-line libfoo.dylib
exporting one function fails exactly like the 2.2 MB libvlccore.

This rebuilds the three tables for a single module covering the whole library
and appends them past the string table, which needs no existing offset to
move: only LC_DYSYMTAB's own fields, LC_SYMTAB's strsize and the __LINKEDIT
segment size change.

Usage: add-dylib-toc.py <dylib> [<dylib>...]
"""

import struct
import sys

LC_SEGMENT = 0x1
LC_SYMTAB = 0x2
LC_DYSYMTAB = 0xB

MH_MAGIC = 0xFEEDFACE          # 32-bit, and big-endian once we pick '>'
MH_DYLIB = 0x6

N_TYPE = 0x0E
N_SECT = 0xE
N_EXT = 0x01

REFERENCE_FLAG_DEFINED = 2
REFERENCE_FLAG_UNDEFINED_NON_LAZY = 0
REFERENCE_TYPE = 0x0F   # mask of n_desc holding the reference type

NLIST_SIZE = 12
MODULE_SIZE = 52
MODULE_NAME = b"__jaguar_toc\x00"

# Reasons that mean "this file simply is not a thin PowerPC dylib", as opposed
# to a real failure. A fat file lands here too: the only one in the bundle is
# the toolchain's libgcc_s, which nothing links, so slicing it apart would be
# work for no result -- revisit if something ever depends on it.
SKIPPABLE = ("already has a table of contents",
             "not a dylib",
             "no exported symbol",
             "not a 32-bit big-endian Mach-O")


def align4(n):
    return (n + 3) & ~3


def patch(path):
    with open(path, "rb") as f:
        data = bytearray(f.read())

    magic, = struct.unpack_from(">I", data, 0)
    if magic != MH_MAGIC:
        return "not a 32-bit big-endian Mach-O (fat or 64-bit?)"

    _, cputype, _, filetype, ncmds, _, _ = struct.unpack_from(">7I", data, 0)
    if filetype != MH_DYLIB:
        return "not a dylib"

    symtab_off = dysymtab_off = linkedit_off = None
    off = 28                                     # sizeof(mach_header)
    for _ in range(ncmds):
        cmd, cmdsize = struct.unpack_from(">2I", data, off)
        if cmd == LC_SYMTAB:
            symtab_off = off
        elif cmd == LC_DYSYMTAB:
            dysymtab_off = off
        elif cmd == LC_SEGMENT:
            name = data[off + 8:off + 24].rstrip(b"\x00")
            if name == b"__LINKEDIT":
                linkedit_off = off
        off += cmdsize

    if symtab_off is None or dysymtab_off is None or linkedit_off is None:
        return "missing LC_SYMTAB, LC_DYSYMTAB or __LINKEDIT"

    symoff, nsyms, stroff, strsize = struct.unpack_from(">4I", data,
                                                        symtab_off + 8)
    dys = list(struct.unpack_from(">18I", data, dysymtab_off + 8))
    (ilocalsym, nlocalsym, iextdefsym, nextdefsym,
     iundefsym, nundefsym) = dys[0:6]

    if dys[7] != 0:                              # ntoc
        return "already has a table of contents"
    if nextdefsym == 0:
        return "no exported symbol"

    # The tables must sit at the very end: everything we append goes after the
    # string table, so no existing offset shifts.
    end = stroff + strsize
    if end != len(data):
        # Some linkers leave padding; tolerate it, but never overwrite data.
        end = max(end, len(data))

    def symbol_name(index):
        strx, = struct.unpack_from(">I", data, symoff + index * NLIST_SIZE)
        z = data.index(b"\x00", stroff + strx)
        return bytes(data[stroff + strx:z])

    # --- the module name lives in the string table, so extend it first
    name_strx = strsize
    data[end:end] = MODULE_NAME
    strsize += len(MODULE_NAME)
    end += len(MODULE_NAME)

    pad = align4(end) - end
    data[end:end] = b"\x00" * pad
    end += pad

    # --- table of contents: every exported symbol, sorted by name, because
    #     dyld binary-searches it
    toc_entries = sorted(range(iextdefsym, iextdefsym + nextdefsym),
                         key=symbol_name)
    tocoff = end
    toc = bytearray()
    for index in toc_entries:
        toc += struct.pack(">2I", index, 0)      # module 0: the only one
    data[end:end] = toc
    end += len(toc)

    # --- module table: one module covering the whole library
    modtaboff = end
    refs_start = 0
    nrefs = nextdefsym + nundefsym
    module = struct.pack(
        ">13I",
        name_strx,          # module_name
        iextdefsym, nextdefsym,
        refs_start, nrefs,
        ilocalsym, nlocalsym,
        0, 0,               # iextrel, nextrel
        0, 0,               # iinit_iterm, ninit_nterm
        0, 0,               # objc_module_info_addr / _size
    )
    data[end:end] = module
    end += MODULE_SIZE

    # --- reference table: what this module defines and what it needs.
    # The flags of an undefined entry MUST be copied from the symbol's own
    # n_desc, not invented: the low bits hold its REFERENCE_TYPE, which says
    # whether dyld binds it lazily, and whether it is weak. Marking everything
    # UNDEFINED_NON_LAZY tells dyld to resolve the whole set eagerly at link
    # time -- including symbols that are weak-imported precisely because the
    # running system may not have them.
    extrefsymoff = end
    refs = bytearray()
    for index in range(iextdefsym, iextdefsym + nextdefsym):
        refs += struct.pack(">I", (index << 8) | REFERENCE_FLAG_DEFINED)
    for index in range(iundefsym, iundefsym + nundefsym):
        n_desc, = struct.unpack_from(">H", data,
                                     symoff + index * NLIST_SIZE + 6)
        refs += struct.pack(">I", (index << 8) | (n_desc & REFERENCE_TYPE))
    data[end:end] = refs
    end += len(refs)

    # --- patch LC_SYMTAB (strsize) and LC_DYSYMTAB (the three tables)
    struct.pack_into(">I", data, symtab_off + 20, strsize)
    dys[6], dys[7] = tocoff, len(toc_entries)            # tocoff, ntoc
    dys[8], dys[9] = modtaboff, 1                        # modtaboff, nmodtab
    dys[10], dys[11] = extrefsymoff, nrefs               # extrefsymoff, n...
    struct.pack_into(">18I", data, dysymtab_off + 8, *dys)

    # --- grow __LINKEDIT to cover what we appended
    vmaddr, vmsize, fileoff, filesize = struct.unpack_from(
        ">4I", data, linkedit_off + 24)
    filesize = end - fileoff
    vmsize = align4096 = (filesize + 0xFFF) & ~0xFFF
    struct.pack_into(">4I", data, linkedit_off + 24,
                     vmaddr, vmsize, fileoff, filesize)

    with open(path, "wb") as f:
        f.write(data)
    return None


def main(argv):
    if len(argv) < 2:
        print(__doc__, file=sys.stderr)
        return 1

    status = 0
    for path in argv[1:]:
        try:
            error = patch(path)
        except Exception as exc:                 # noqa: BLE001
            error = str(exc)
        if error is None:
            print("toc: %s" % path)
            continue

        print("toc: %s: skipped (%s)" % (path, error), file=sys.stderr)

        # "Skipped" is the normal outcome for everything that is not a thin
        # PowerPC dylib -- symlinks to an already-patched target, bundles,
        # fat files. Only a real failure (unreadable, truncated, malformed)
        # should stop the build; anything the running system cannot load
        # would be caught later by the launch itself.
        if not any(reason in error for reason in SKIPPABLE):
            status = 1
    return status


if __name__ == "__main__":
    sys.exit(main(sys.argv))
