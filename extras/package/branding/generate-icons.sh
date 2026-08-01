#!/bin/sh
# generate-icons.sh — build the PowerVLC Windows/Linux raster icons from the
# vector master powervlc.svg.
#
# Outputs (into $OUTDIR, default ./out next to this script):
#   powervlc.png            256x256 RGBA — the canonical Linux/desktop PNG
#   powervlc.ico            multi-size Windows icon (16/32/48/64/128/256)
#   png/vlc-<N>.png    the individual rasters (16/32/48/128/256/512)
#
# The two files powervlc.ico and powervlc.png are named to match the paths the Windows
# NSIS/MSI packaging and the Linux desktop entry already reference
# (share/icons/powervlc.ico, share/icons/powervlc.png), so installing is a plain copy —
# no packaging path changes. See README.md for the copy step.
#
# The script detects whatever SVG->raster + ICO tooling is present and fails
# with a clear message if none is usable, rather than emitting garbage.
#
# Usage:  ./generate-icons.sh [OUTDIR]
set -eu

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
SVG="$SCRIPT_DIR/powervlc.svg"
OUTDIR="${1:-$SCRIPT_DIR/out}"
PNGDIR="$OUTDIR/png"

# Icon sizes.
PNG_SIZES="16 32 48 128 256 512"   # standalone PNG deliverables
ICO_SIZES="16 32 48 64 128 256"    # frames packed into the .ico

die() { echo "generate-icons.sh: error: $*" >&2; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }

[ -f "$SVG" ] || die "vector master not found: $SVG"

# --- pick an SVG rasteriser --------------------------------------------------
# rasterise <src.svg> <size> <dst.png>
RASTER=""
if have rsvg-convert; then
    RASTER="rsvg"
elif have inkscape; then
    RASTER="inkscape"
elif have cairosvg; then
    RASTER="cairosvg"
elif have magick && magick -list format 2>/dev/null | grep -qi 'SVG'; then
    RASTER="magick"
elif have convert; then
    # ImageMagick 6 — only usable for SVG if it has an rsvg/inkscape delegate.
    RASTER="convert"
fi
[ -n "$RASTER" ] || die "no SVG rasteriser found. Install one of:
  rsvg-convert (librsvg), inkscape, cairosvg, or ImageMagick with an SVG delegate."

rasterise() { # <size> <dst.png>
    _sz="$1"; _dst="$2"
    case "$RASTER" in
        rsvg)     rsvg-convert -w "$_sz" -h "$_sz" -o "$_dst" "$SVG" ;;
        inkscape) inkscape "$SVG" --export-type=png --export-filename="$_dst" \
                      -w "$_sz" -h "$_sz" >/dev/null 2>&1 ;;
        cairosvg) cairosvg "$SVG" -o "$_dst" -W "$_sz" -H "$_sz" ;;
        magick)   magick -background none -density 384 "$SVG" \
                      -resize "${_sz}x${_sz}" "$_dst" ;;
        convert)  convert -background none -density 384 "$SVG" \
                      -resize "${_sz}x${_sz}" "$_dst" ;;
    esac
}

# --- pick an ICO assembler ---------------------------------------------------
ICO=""
if have magick; then
    ICO="magick"
elif have convert; then
    ICO="convert"
elif have png2ico; then
    ICO="png2ico"
elif have icotool; then
    ICO="icotool"
fi
[ -n "$ICO" ] || die "no ICO assembler found. Install one of:
  ImageMagick (magick/convert), png2ico, or icotool (icoutils)."

echo "generate-icons.sh: rasteriser=$RASTER  ico-assembler=$ICO"
echo "generate-icons.sh: output -> $OUTDIR"

rm -rf "$OUTDIR"
mkdir -p "$PNGDIR"

# --- rasterise every size we need (union of PNG + ICO sizes) -----------------
ALL_SIZES=$(printf '%s\n%s\n' "$PNG_SIZES" "$ICO_SIZES" | tr ' ' '\n' \
            | grep -v '^$' | sort -n -u)
for sz in $ALL_SIZES; do
    out="$PNGDIR/vlc-$sz.png"
    rasterise "$sz" "$out"
    [ -s "$out" ] || die "rasteriser produced empty file for size $sz"
done

# --- canonical standalone PNG (256px) ---------------------------------------
cp "$PNGDIR/vlc-256.png" "$OUTDIR/powervlc.png"

# --- assemble the .ico -------------------------------------------------------
ICO_INPUTS=""
for sz in $ICO_SIZES; do
    ICO_INPUTS="$ICO_INPUTS $PNGDIR/vlc-$sz.png"
done

case "$ICO" in
    magick)  # shellcheck disable=SC2086
             magick $ICO_INPUTS "$OUTDIR/powervlc.ico" ;;
    convert) # shellcheck disable=SC2086
             convert $ICO_INPUTS "$OUTDIR/powervlc.ico" ;;
    png2ico) # shellcheck disable=SC2086
             png2ico "$OUTDIR/powervlc.ico" $ICO_INPUTS ;;
    icotool) # shellcheck disable=SC2086
             icotool -c -o "$OUTDIR/powervlc.ico" $ICO_INPUTS ;;
esac
[ -s "$OUTDIR/powervlc.ico" ] || die "ICO assembler produced an empty file"

# --- sanity check ------------------------------------------------------------
if have file; then
    echo "generate-icons.sh: validating with 'file':"
    file "$OUTDIR/powervlc.ico" "$OUTDIR/powervlc.png" | sed 's/^/  /'
    file "$OUTDIR/powervlc.ico" | grep -qi 'icon resource' \
        || die "powervlc.ico did not validate as a Windows icon resource"
    file "$OUTDIR/powervlc.png" | grep -qi 'PNG image' \
        || die "powervlc.png did not validate as a PNG image"
fi

echo "generate-icons.sh: done."
echo "  $OUTDIR/powervlc.ico"
echo "  $OUTDIR/powervlc.png"
echo "  $PNGDIR/vlc-<size>.png"
echo
echo "To install the branded art into the packaging paths, copy:"
echo "  cp \"$OUTDIR/powervlc.ico\" \"$SCRIPT_DIR/../../../share/icons/powervlc.ico\""
echo "  cp \"$OUTDIR/powervlc.png\" \"$SCRIPT_DIR/../../../share/icons/powervlc.png\""
