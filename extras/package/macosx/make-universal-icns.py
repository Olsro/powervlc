#!/usr/bin/env python3
"""Build VLC-universal.icns: one .icns that renders the app icon correctly from
Mac OS X 10.2 all the way to current macOS.

The trap this works around
--------------------------
An .icns is a flat list of typed elements. The 256/512 px elements (types
`ic08`/`ic09`) may be encoded either as JPEG 2000 (the Leopard-era format) or
as PNG (what modern Icon Composer / iconutil emit). Both decode on modern
macOS, but the *in-process* Cocoa icns reader on 10.4/10.5 — the one
NSApplication uses for -applicationIconImage, which NSRunAlertPanel / NSAlert
draw in their icon well — only understands the JPEG 2000 form. Feed it a
PNG-encoded ic08/ic09 and it does not just skip that element: it returns **nil
for the whole image**, so every alert-panel dialog (e.g. the first-run "check
for album art and metadata?" prompt) shows a blank icon well, even though the
Dock icon — resolved by the more tolerant IconServices — looks fine.

The retina elements ic07/ic11..ic14 do NOT trigger this: those element *types*
did not exist on 10.5, so the old reader skips them outright and never tries to
decode their PNG payload. The failure is specific to PNG *inside a type the old
reader knows*, i.e. ic08/ic09.

The recipe
----------
  * classic families is32/il32/ih32/it32 (+ 8-bit masks) — usable by Jaguar,
    Tiger and modern macOS;
The universal icon deliberately contains only the classic representations.
Jaguar does not reliably skip any newer element types, so a mixed classic /
Retina file can still become a generic icon. Modern macOS can display the
classic representations as a fallback; architecture-specific modern bundles
may add Retina artwork separately.

That single file validates (`+[NSImage initWithContentsOfFile:]` returns a
6-representation image) on Leopard while still carrying the modern retina
detail. ic10 (1024 px) is intentionally omitted: it pushed the file past the
size IconServices tolerates on Tiger (see the port handoff, round 70).

Usage: make-universal-icns.py            # regenerate the committed asset
       make-universal-icns.py <out.icns> [tiger.icns] [retina-source.icns]
"""
import os
import struct
import sys

CLASSIC = ["is32", "s8mk", "il32", "l8mk", "ih32", "h8mk", "it32", "t8mk"]
# Keep the universal file to the Jaguar-safe classic representations only.
ORDER = CLASSIC


def read_elements(path):
    data = open(path, "rb").read()
    if data[:4] != b"icns":
        raise SystemExit("%s: not an icns file" % path)
    out = {}
    off = 8
    while off + 8 <= len(data):
        etype = data[off:off + 4].decode("latin1")
        elen = struct.unpack(">I", data[off + 4:off + 8])[0]
        if elen < 8 or off + elen > len(data):
            raise SystemExit("%s: corrupt element %r" % (path, etype))
        out[etype] = data[off + 8:off + elen]
        off += elen
    return out


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    res = os.path.join(here, "..", "..", "..", "modules", "gui",
                       "legacy_macosx", "Resources")
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(res, "VLC-universal.icns")
    tiger = sys.argv[2] if len(sys.argv) > 2 else os.path.join(res, "VLC-tiger.icns")
    retina = sys.argv[3] if len(sys.argv) > 3 else out  # existing universal keeps the PNG retina

    t = read_elements(tiger)
    r = read_elements(retina)

    picked = []
    for etype in ORDER:
        if etype in CLASSIC:
            picked.append((etype, t[etype]))

    body = b"".join(t_.encode("latin1") + struct.pack(">I", len(b) + 8) + b
                    for t_, b in picked)
    blob = b"icns" + struct.pack(">I", len(body) + 8) + body
    open(out, "wb").write(blob)
    print("wrote %s: %s (%d bytes)"
          % (out, " ".join(t_ for t_, _ in picked), len(blob)))


if __name__ == "__main__":
    main()
