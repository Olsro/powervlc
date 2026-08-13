#!/bin/sh
# update-pot.sh — safely regenerate po/vlc.pot and merge the catalogs.
#
# Why this script exists
# ---------------------
# `make update-po` is not safe in this tree. The 21 headers uic generates from
# modules/gui/qt/ui/*.ui exist ONLY in the build tree, and POTFILES.in keeps
# them commented out (listing them would put non-existent files into the
# $(POTFILES) prerequisite list that config.status builds). An extraction run
# that way silently drops ~360 Qt interface strings; the msgmerge that follows
# then marks them obsolete (`#~`) in all 105 catalogs, msgfmt stops compiling
# them into the .gmo files, and the application falls back to English. That is
# exactly what the 2026-07-25 template did to the fork's own strings.
#
# This script:
#   1. generates the Qt headers with uic (same recipe as modules/gui/qt/Makefile.am);
#   2. extracts with the exact options from po/Makevars;
#   3. REFUSES to write anything if any msgid disappears from the template,
#      unless it is listed in po/POT-REMOVED.txt (justified removals);
#   4. only then replaces vlc.pot, merges the 105 catalogs and rebuilds the
#      .gmo files, reporting the obsolete-entry count before and after.
#
# Usage
# -----
#   ./po/update-pot.sh --check          extract and report, write NOTHING (default)
#   ./po/update-pot.sh --update         write vlc.pot, merge the .po, rebuild the .gmo
#   ./po/update-pot.sh --update --allow-losses
#                                       proceed despite unlisted removals
#                                       (ONLY after reading the report)
#
# Environment
#   UIC=/path/to/uic          Qt 5 user interface compiler (auto-detected otherwise)
#   XGETTEXT=..., MSGMERGE=..., MSGFMT=...

set -e

srcdir=$(cd "$(dirname "$0")/.." && pwd)
podir="$srcdir/po"

mode=check
allow_losses=no
for arg in "$@"; do
    case "$arg" in
        --check)         mode=check ;;
        --update)        mode=update ;;
        --allow-losses)  allow_losses=yes ;;
        -h|--help)       sed -n '2,32p' "$0"; exit 0 ;;
        *) echo "update-pot.sh: unknown option: $arg" >&2; exit 2 ;;
    esac
done

XGETTEXT=${XGETTEXT:-xgettext}
MSGMERGE=${MSGMERGE:-msgmerge}
MSGFMT=${MSGFMT:-msgfmt}

# ---------------------------------------------------------------- uic
if [ -z "$UIC" ]; then
    for cand in uic-qt5 uic \
                /opt/homebrew/opt/qt@5/bin/uic \
                /usr/local/opt/qt@5/bin/uic \
                /usr/lib/qt5/bin/uic; do
        if command -v "$cand" >/dev/null 2>&1 && "$cand" --version 2>&1 | grep -q ' 5\.'; then
            UIC=$cand; break
        fi
    done
fi
if [ -z "$UIC" ]; then
    cat >&2 <<'EOF'
update-pot.sh: no Qt 5 uic found.
  Install it (brew install qt@5) or point at it:
      UIC=/path/to/uic ./po/update-pot.sh
  Failing that, the headers already built for Windows can be pulled out of the
  Docker volume and dropped into the staging directory:
      docker run --rm -v powervlc-build-windows:/work powervlc-win \
        tar -C /work/win32 -cf - modules/gui/qt/ui | tar -C "$stage" -xf -
EOF
    exit 1
fi
echo "uic      : $UIC ($("$UIC" --version 2>&1))"
echo "xgettext : $($XGETTEXT --version | sed 1q)"

# ------------------------------------------------ generated Qt headers (staging)
stage=$(mktemp -d "${TMPDIR:-/tmp}/vlc-pot-stage.XXXXXX")
trap 'rm -rf "$stage"' EXIT INT TERM
mkdir -p "$stage/modules/gui/qt/ui"

# Same recipe as the `.ui.h:` rule in modules/gui/qt/Makefile.am.
nui=0
for ui in "$srcdir"/modules/gui/qt/ui/*.ui; do
    b=$(basename "$ui" .ui)
    out="$stage/modules/gui/qt/ui/$b.h"
    echo '#define Q_(a,b) QString::fromUtf8(_(a))' > "$out.tmp"
    "$UIC" -tr "Q_" "$ui" >> "$out.tmp"
    sed -e 's/Q_(\"_(\\\"\(.*\)\\\")"/Q_("\1"/' "$out.tmp" > "$out"
    rm -f "$out.tmp"
    nui=$((nui + 1))
done
echo "Qt headers built: $nui"

# The Qt headers stay commented out in POTFILES.in (see the note at the end of
# that file). Uncomment them here, for this extraction only.
potfiles="$stage/POTFILES.in"
sed 's|^#modules/gui/qt/ui/|modules/gui/qt/ui/|' "$podir/POTFILES.in" > "$potfiles"
nqt=$(grep -c '^modules/gui/qt/ui/' "$potfiles" || true)
if [ "$nqt" -ne "$nui" ]; then
    echo "update-pot.sh: POTFILES.in lists $nqt Qt headers but $nui were built." >&2
    echo "  The two lists must match — update POTFILES.in." >&2
    exit 1
fi

# Every active line of POTFILES.in must resolve, either in the source tree or in
# the staging tree. Otherwise xgettext skips the file without saying so.
unresolved=$(awk '/^[^#]/ && NF' "$potfiles" | while read -r f; do
    [ -f "$srcdir/$f" ] || [ -f "$stage/$f" ] || echo "$f"
done)
if [ -n "$unresolved" ]; then
    echo "update-pot.sh: files listed in POTFILES.in but not found:" >&2
    echo "$unresolved" | sed 's/^/  /' >&2
    exit 1
fi

# ---------------------------------------------------------------- extraction
newpot="$stage/vlc.pot.new"
# Options taken from po/Makevars (XGETTEXT_OPTIONS). The second --directory
# exposes the generated Qt headers, exactly the way `--directory=..` exposes
# top_builddir during a `make update-po` inside a fully built tree.
$XGETTEXT --default-domain=vlc \
    --directory="$srcdir" --directory="$stage" \
    --add-comments=TRANSLATORS: --add-comments=xgettext: \
    --keyword=_ --keyword=N_ --keyword=_NS --keyword=_ANS --keyword=qtr \
    --keyword=Q_ --keyword=vlc_ngettext:1,2 --keyword=vlc_pgettext:1c,2 \
    --language=C++ --from-code=UTF-8 \
    --files-from="$potfiles" \
    --copyright-holder=VideoLAN \
    --msgid-bugs-address=vlc-devel@videolan.org \
    -o "$newpot" 2>"$stage/xgettext.log" || {
        echo "update-pot.sh: xgettext failed:" >&2; cat "$stage/xgettext.log" >&2; exit 1; }
grep -v 'warning: Message contains an embedded URL' "$stage/xgettext.log" >&2 || true

# ---------------------------------------------------- safety net: lost msgids
export VLC_POT_OLD="$podir/vlc.pot" VLC_POT_NEW="$newpot" \
       VLC_POT_REMOVED="$podir/POT-REMOVED.txt"

# The condition of an `if` is exempt from `set -e`: we want to branch on the
# check's exit status rather than die on it.
if python3 - <<'PYEOF'
import os, re, sys

def parse(path):
    """Return {key: [source refs]}; key is msgctxt\x04msgid, or msgid alone."""
    entries, cur, refs, field, obsolete = {}, {}, [], None, False

    def unquote(s):
        s = s.strip()
        return (s[1:-1].encode('utf-8').decode('unicode_escape')
                .encode('latin-1').decode('utf-8'))

    def flush():
        nonlocal cur, refs, obsolete
        mid = cur.get('msgid')
        if mid and not obsolete:
            key = cur['msgctxt'] + '\x04' + mid if 'msgctxt' in cur else mid
            entries.setdefault(key, list(refs))
        cur, refs, obsolete = {}, [], False

    pat = re.compile(r'^(msgctxt|msgid|msgid_plural|msgstr(?:\[\d+\])?)\s+(".*")\s*$')
    with open(path, encoding='utf-8') as f:
        for raw in f:
            line = raw.rstrip('\n')
            if line.startswith('#: '):
                refs.extend(line[3:].split()); continue
            if line.startswith('#~ '):
                obsolete = True; line = line[3:]
            elif line.startswith('#'):
                continue
            if not line.strip():
                flush(); field = None; continue
            m = pat.match(line)
            if m:
                if m.group(1) in ('msgctxt', 'msgid') and m.group(1) in cur:
                    flush()
                field = m.group(1); cur[field] = unquote(m.group(2)); continue
            if line.startswith('"') and field:
                cur[field] += unquote(line)
    flush()
    return entries

old = parse(os.environ['VLC_POT_OLD'])
new = parse(os.environ['VLC_POT_NEW'])

removed_path = os.environ['VLC_POT_REMOVED']
allowed = set()
if os.path.exists(removed_path):
    for line in open(removed_path, encoding='utf-8'):
        line = line.rstrip('\n')
        if line and not line.startswith('#'):
            allowed.add(line.replace('\\n', '\n').replace('\\t', '\t'))

lost = sorted(set(old) - set(new))
gained = sorted(set(new) - set(old))
unjustified = [k for k in lost if k not in allowed]

print()
print("template in place : %d strings" % len(old))
print("new template      : %d strings" % len(new))
print("gained            : %d" % len(gained))
print("lost              : %d (%d justified by POT-REMOVED.txt)"
      % (len(lost), len(lost) - len(unjustified)))

if unjustified:
    from collections import Counter
    c = Counter(r.rsplit(':', 1)[0] for k in unjustified for r in old[k])
    print()
    print("UNJUSTIFIED LOSSES — by source file of the template in place:")
    for f, n in c.most_common():
        print("  %4d  %s" % (n, f))
    print()
    print("First 20:")
    for k in unjustified[:20]:
        print("  %s" % k.replace('\n', '\\n')[:110])
    print()
    print("What to do:")
    print("  * if the source file is gone or the string was reworded, add these")
    print("    msgids to po/POT-REMOVED.txt (one per line, \\n escaped);")
    print("  * otherwise POTFILES.in has a gap: add the source file to it.")

sys.exit(3 if unjustified else 0)
PYEOF
then
    :
else
    if [ "$allow_losses" = yes ]; then
        echo "!! --allow-losses: proceeding despite the losses above."
    else
        echo
        echo "update-pot.sh: STOPPED, nothing was modified."
        exit 1
    fi
fi

if [ "$mode" = check ]; then
    echo
    echo "--check: nothing written. Re-run with --update to apply."
    exit 0
fi

# --------------------------------------------------------- write and merge
before=$(cat "$podir"/*.po | grep -c '^#~ msgid ' || true)

cp "$newpot" "$podir/vlc.pot"
echo
echo "po/vlc.pot updated."

n=0
for po in "$podir"/*.po; do
    $MSGMERGE --quiet --previous --backup=none --update "$po" "$podir/vlc.pot"
    n=$((n + 1))
done
echo "catalogs merged: $n"

# --------------------------------------------------------- check and .gmo
ko=0
for po in "$podir"/*.po; do
    if ! $MSGFMT -c --statistics -o "${po%.po}.gmo" "$po" 2>"$stage/msgfmt.log"; then
        echo "  msgfmt FAILED: $(basename "$po")" >&2
        sed 's/^/    /' "$stage/msgfmt.log" >&2
        ko=$((ko + 1))
    fi
done
after=$(cat "$podir"/*.po | grep -c '^#~ msgid ' || true)

echo
echo "obsolete entries (#~) across all catalogs: $before -> $after"
if [ "$ko" -ne 0 ]; then
    echo "update-pot.sh: $ko catalog(s) invalid." >&2
    exit 1
fi
echo "OK — $n catalogs valid, .gmo files rebuilt."
echo
echo "Remember: the compiled catalogs also have to reach the bundles."
echo "See BUILD-POWERVLC.md section 5.2."
