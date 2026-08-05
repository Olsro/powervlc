#!/bin/sh
# Builds share/powervlc.xpi out of powervlc/.
#
# Deliberately not a build rule: an .xpi is a zip, every cross build of
# this fork would have to have zip(1), and the add-on changes about once a
# year. Run this by hand after touching bootstrap.js or install.rdf, and
# commit the result alongside the sources.
set -e
here=$(cd "$(dirname "$0")" && pwd)
out=$here/../powervlc.xpi

rm -f "$out"
cd "$here/powervlc"
# -X drops the extra attributes, so the same sources give the same file.
zip -X -r "$out" install.rdf bootstrap.js >/dev/null
echo "$out"
unzip -l "$out"
