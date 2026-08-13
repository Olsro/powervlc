#!/bin/sh
# Refresh share/certs/ca-certificates.crt from the current Mozilla root list.
#
# PowerVLC ships this bundle and loads it IN ADDITION to the operating
# system's trust store (see modules/misc/gnutls.c). That is the whole point on
# the systems this fork targets: their store is readable but frozen years ago,
# so it knows nothing of the roots today's HTTPS signs with. Windows XP has no
# ISRG Root X1 -- no Let's Encrypt, which is most of the small web.
#
# ⚠ Run this DELIBERATELY, not from the build. A build that downloads its own
# trust anchors stops being reproducible, silently changes what it trusts
# between two builds of the same commit, and fails or ships something stale on
# a machine without network. Refresh it, look at what changed, commit it.
#
# Usage: share/certs/update-ca-bundle.sh
set -eu

DEST="$(dirname "$0")/ca-certificates.crt"
URL="https://curl.se/ca/cacert.pem"
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

echo "fetching $URL"
curl -fsS -o "$TMP" "$URL"

# It must parse, and hold a plausible number of roots: a truncated download or
# an HTML error page must never overwrite the bundle.
n=$(grep -c 'BEGIN CERTIFICATE' "$TMP" || true)
[ "$n" -ge 80 ] || { echo "only $n certificates: refusing" >&2; exit 1; }
if command -v openssl >/dev/null 2>&1; then
    ok=$(openssl crl2pkcs7 -nocrl -certfile "$TMP" 2>/dev/null \
         | openssl pkcs7 -print_certs -noout 2>/dev/null \
         | grep -c '^subject=' || true)
    [ "$ok" = "$n" ] || { echo "$ok of $n parse: refusing" >&2; exit 1; }
fi

# ISRG Root X1 is the one this whole mechanism exists for.
grep -q 'ISRG Root X1' "$TMP" || { echo "no ISRG Root X1: refusing" >&2; exit 1; }

old=$(grep -c 'BEGIN CERTIFICATE' "$DEST" 2>/dev/null || echo 0)
cp "$TMP" "$DEST"
echo "$DEST: $old -> $n root certificates"
echo "Review the diff before committing: some roots are REMOVALS."
