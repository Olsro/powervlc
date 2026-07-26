#!/usr/bin/env python3
"""Recolour the PowerVLC traffic cone from VLC orange to PowerVLC red.

The transform is a hue compression towards pure red, applied only to pixels
whose hue already sits in the orange band.  Saturation and value are kept, so
every gradient, shadow and antialiased edge survives; the white cone bands, the
document sheets behind the file-type icons and any non-orange artwork are left
byte-identical.

It understands the three container formats the tree actually ships:

* SVG   — rewrites the ``rgb(r,g,b)`` literals of the vector master;
* PNG / ICO / BMP — straight pixel pass with Pillow;
* ICNS  — parsed element by element.  Each element is re-encoded **in the
  format it already used**, which matters: ``ic08``/``ic09`` encoded as PNG
  instead of JPEG 2000 make the in-process 10.4/10.5 icns reader return nil for
  the *whole* icon (see make-universal-icns.py).  The classic 10.4 families
  ``is32``/``il32``/``ih32``/``it32`` are 24-bit RLE, decoded and re-encoded
  here; masks (``*8mk``), ``info`` and ``TOC `` are copied verbatim.

Usage:  recolor_assets.py <file> [<file> ...]     (edits in place)
        recolor_assets.py --check <file>          (report, write nothing)
"""
import io
import os
import re
import struct
import sys

import numpy as np
from PIL import Image

# --- the colour transform -------------------------------------------------
# Variant "B - rouge vif": hue is multiplied by 0.15 in the 0..1 hue space, so
# the cone's 15deg..38deg orange spread lands on a 2deg..6deg red spread while
# keeping its internal ordering (highlights stay lighter than shadows).
HUE_FACTOR = 0.15
# Only touch the orange band.  Anything bluer/greener (the white bands' cool
# grey, the film reels in the sidebar icons, blue document sheets) is untouched.
HUE_LO, HUE_HI = 0.010, 0.150

RGB_RE = re.compile(r"rgb\((\d+),\s*(\d+),\s*(\d+)\)")
# The Qt pixmaps are SVGs that write their fills as #rrggbb / #rgb instead.
HEX_RE = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")
CLASSIC_RLE = {"is32": 16, "il32": 32, "ih32": 48, "it32": 128}
MASKS = {"s8mk", "l8mk", "h8mk", "t8mk", "icm#", "ics#", "ich#", "ICN#", "info", "TOC "}


def recolor_array(rgb):
    """rgb: uint8 array (..., 3) -> recoloured copy + count of touched pixels."""
    a = rgb.astype(np.float32) / 255.0
    r, g, b = a[..., 0], a[..., 1], a[..., 2]
    mx = a.max(-1)
    mn = a.min(-1)
    d = mx - mn
    h = np.zeros_like(mx)
    nz = d > 1e-6
    # standard rgb->hue, 0..1
    ir = nz & (mx == r)
    ig = nz & (mx == g) & ~ir
    ib = nz & ~ir & ~ig
    with np.errstate(invalid="ignore", divide="ignore"):
        h[ir] = ((g - b)[ir] / d[ir]) % 6.0
        h[ig] = ((b - r)[ig] / d[ig]) + 2.0
        h[ib] = ((r - g)[ib] / d[ib]) + 4.0
    h /= 6.0
    s = np.zeros_like(mx)
    s[mx > 0] = (d / np.where(mx > 0, mx, 1.0))[mx > 0]
    v = mx

    sel = nz & (h >= HUE_LO) & (h <= HUE_HI)
    h2 = np.where(sel, h * HUE_FACTOR, h)

    # hsv -> rgb, vectorised
    i = np.floor(h2 * 6.0)
    f = h2 * 6.0 - i
    p = v * (1.0 - s)
    q = v * (1.0 - f * s)
    t = v * (1.0 - (1.0 - f) * s)
    i = (i.astype(np.int32) % 6)
    out = np.stack([
        np.choose(i, [v, q, p, p, t, v]),
        np.choose(i, [t, v, v, q, p, p]),
        np.choose(i, [p, p, t, v, v, q]),
    ], axis=-1)
    out = np.rint(np.clip(out, 0, 1) * 255).astype(np.uint8)
    # leave untouched pixels bit-identical instead of trusting the roundtrip
    out = np.where(sel[..., None], out, rgb)
    return out, int(sel.sum())


def recolor_image(im, keep_mode=False):
    """PIL image (any mode) -> (recoloured image, count of touched pixels).

    With keep_mode, the original storage mode is preserved instead of widening
    to RGBA.  That matters for the NSIS/MSI installer bitmaps: the welcome
    bitmap is a palettised BMP, and handing NSIS a 32-bit one changes both its
    size and how it composites.  A palette image is recoloured by rewriting its
    palette, which leaves the pixel indices — and the bit depth — untouched.
    """
    if keep_mode and im.mode == "P":
        pal = im.getpalette()
        arr = np.array(pal, dtype=np.uint8).reshape(1, -1, 3)
        out, n = recolor_array(arr)
        new = im.copy()
        new.putpalette(out.reshape(-1).tolist())
        return new, n
    mode = im.mode
    arr = np.array(im.convert("RGBA"))
    rgb, n = recolor_array(arr[..., :3])
    arr[..., :3] = rgb
    out = Image.fromarray(arr, "RGBA")
    if keep_mode and mode in ("RGB", "L"):
        out = out.convert(mode)
    return out, n


# --- classic 24-bit RLE (is32 / il32 / ih32 / it32) ------------------------
def rle24_decode(data, npix):
    """Decode one channel plane stream; returns (plane bytes, bytes consumed)."""
    out = bytearray()
    i = 0
    while len(out) < npix:
        c = data[i]; i += 1
        if c & 0x80:
            out += bytes([data[i]]) * ((c & 0x7F) + 3)
            i += 1
        else:
            n = c + 1
            out += data[i:i + n]
            i += n
    if len(out) != npix:
        raise ValueError("RLE overrun: %d != %d" % (len(out), npix))
    return bytes(out), i


def rle24_encode(plane):
    """PackBits-style encoder matching Apple's icns 24-bit RLE."""
    out = bytearray()
    i, n = 0, len(plane)
    lit = bytearray()

    def flush():
        nonlocal lit
        while lit:
            chunk, lit = lit[:128], lit[128:]
            out.append(len(chunk) - 1)
            out.extend(chunk)

    while i < n:
        run = 1
        while i + run < n and plane[i + run] == plane[i] and run < 130:
            run += 1
        if run >= 3:
            flush()
            out.append(0x80 | (run - 3))
            out.append(plane[i])
            i += run
        else:
            lit.append(plane[i])
            i += 1
    flush()
    return bytes(out)


def classic_decode(etype, blob):
    npix = CLASSIC_RLE[etype] ** 2
    head = b""
    data = blob
    if etype == "it32":                     # 128x128 carries a 4-byte zero header
        head, data = blob[:4], blob[4:]
    if len(data) == npix * 3:               # stored uncompressed
        planes = [data[0:npix], data[npix:2 * npix], data[2 * npix:]]
        return head, planes, False
    planes, off = [], 0
    for _ in range(3):
        plane, used = rle24_decode(data[off:], npix)
        planes.append(plane)
        off += used
    return head, planes, True


def classic_encode(head, planes, compressed):
    if not compressed:
        return head + b"".join(planes)
    return head + b"".join(rle24_encode(p) for p in planes)


def recolor_classic(etype, blob):
    side = CLASSIC_RLE[etype]
    head, planes, comp = classic_decode(etype, blob)
    arr = np.stack([np.frombuffer(p, dtype=np.uint8).reshape(side, side) for p in planes], -1)
    out, n = recolor_array(arr)
    planes = [out[..., c].tobytes() for c in range(3)]
    return classic_encode(head, planes, comp), n


# --- icns container --------------------------------------------------------
def icns_elements(data):
    if data[:4] != b"icns":
        raise ValueError("not an icns file")
    out, off = [], 8
    while off + 8 <= len(data):
        etype = data[off:off + 4].decode("latin1")
        elen = struct.unpack(">I", data[off + 4:off + 8])[0]
        if elen < 8 or off + elen > len(data):
            raise ValueError("corrupt element %r" % etype)
        out.append((etype, data[off + 8:off + elen]))
        off += elen
    return out


def is_jp2(blob):
    return blob[:12] == b"\x00\x00\x00\x0cjP  \r\n\x87\n"


def is_png(blob):
    return blob[:8] == b"\x89PNG\r\n\x1a\n"


def recolor_icns(data, report):
    elements = icns_elements(data)
    picked, total = [], 0
    for etype, blob in elements:
        if etype in CLASSIC_RLE:
            new, n = recolor_classic(etype, blob)
            fmt = "rle24"
        elif is_png(blob) or is_jp2(blob):
            jp2 = is_jp2(blob)
            im = Image.open(io.BytesIO(blob))
            im.load()
            out, n = recolor_image(im)
            buf = io.BytesIO()
            if jp2:
                # must stay JPEG 2000: a PNG payload in ic08/ic09 makes the
                # 10.4/10.5 in-process reader fail the entire icon.
                out.save(buf, format="JPEG2000", irreversible=False, no_jp2=False)
            else:
                out.save(buf, format="PNG", optimize=True)
            new = buf.getvalue()
            fmt = "jp2" if jp2 else "png"
            if jp2 and not is_jp2(new):
                raise ValueError("%s: re-encode lost the JPEG 2000 wrapper" % etype)
        elif etype in MASKS:
            new, n, fmt = blob, 0, "copy"
        else:
            new, n, fmt = blob, 0, "copy?"
        report.append("      %-5s %-6s %7d -> %7d B, %d px" % (etype, fmt, len(blob), len(new), n))
        total += n
        picked.append((etype, new))
    body = b"".join(t.encode("latin1") + struct.pack(">I", len(b) + 8) + b for t, b in picked)
    return b"icns" + struct.pack(">I", len(body) + 8) + body, total


# --- drivers ---------------------------------------------------------------
def _one(r, g, b):
    out, k = recolor_array(np.array([[[r, g, b]]], dtype=np.uint8))
    return tuple(int(x) for x in out[0][0]), k


def recolor_svg(text):
    n = [0]

    def sub_rgb(m):
        (r, g, b), k = _one(*(int(x) for x in m.groups()))
        n[0] += k
        return "rgb(%d,%d,%d)" % (r, g, b)

    def sub_hex(m):
        h = m.group(1)
        if len(h) == 3:
            h = "".join(c * 2 for c in h)
        (r, g, b), k = _one(int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16))
        n[0] += k
        return "#%02x%02x%02x" % (r, g, b)

    return HEX_RE.sub(sub_hex, RGB_RE.sub(sub_rgb, text)), n[0]


def process(path, check=False):
    ext = os.path.splitext(path)[1].lower()
    report = []
    with open(path, "rb") as fh:
        raw = fh.read()
    if ext == ".svg":
        new_text, n = recolor_svg(raw.decode("utf-8"))
        new = new_text.encode("utf-8")
    elif ext == ".icns":
        new, n = recolor_icns(raw, report)
    else:
        im = Image.open(io.BytesIO(raw))
        fmt = im.format
        if fmt == "ICO":
            # Each .ico frame is its own artwork (small sizes are hand-tuned, not
            # downscales), so recolour every frame and re-pack them all.  Pillow
            # can only write an .ico by downsampling a single image, hence magick.
            import shutil
            import subprocess
            import tempfile
            tool = shutil.which("magick") or shutil.which("convert")
            if not tool:
                raise SystemExit("%s: need ImageMagick (magick/convert) to repack "
                                 "a multi-frame .ico" % path)
            n = 0
            with tempfile.TemporaryDirectory() as td:
                names = []
                for size in sorted(im.ico.sizes()):
                    fr, k = recolor_image(im.ico.getimage(size))
                    n += k
                    name = os.path.join(td, "f-%04d.png" % size[0])
                    fr.save(name, format="PNG")
                    names.append(name)
                dst = os.path.join(td, "out.ico")
                subprocess.run([tool] + names + [dst], check=True)
                new = open(dst, "rb").read()
        else:
            im.load()
            # BMPs here are installer artwork consumed by NSIS/WiX, which care
            # about bit depth and DPI; PNGs are free to be RGBA.
            out, n = recolor_image(im, keep_mode=(fmt == "BMP"))
            buf = io.BytesIO()
            save_kw = {"format": fmt}
            if fmt == "PNG":
                save_kw["optimize"] = True
            if fmt == "BMP" and im.info.get("dpi"):
                save_kw["dpi"] = im.info["dpi"]
            out.save(buf, **save_kw)
            new = buf.getvalue()
    changed = new != raw
    print("%-70s %s (%d px touched)" % (path, "CHANGED" if changed else "identical", n))
    for line in report:
        print(line)
    if not check and changed:
        with open(path, "wb") as fh:
            fh.write(new)
    return changed


if __name__ == "__main__":
    args = sys.argv[1:]
    check = "--check" in args
    args = [a for a in args if a != "--check"]
    if not args:
        raise SystemExit(__doc__)
    for p in args:
        process(p, check)
