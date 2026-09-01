#!/bin/sh
# Merge per-architecture PowerVLC.app bundles into one universal bundle.
#
# Usage: make-universal.sh <output.app> <input1.app> [input2.app ...]
# e.g.   make-universal.sh build/macos/universal/PowerVLC.app \
#            build/macos/arm64/PowerVLC.app build/macos/x64/PowerVLC.app \
#            build/macos/x86/PowerVLC.app build/macos/g3/PowerVLC.app
#
# Every regular file present in several inputs is lipo-merged when it is
# a Mach-O, taken from the FIRST input otherwise (list the preferred
# bundle first). Files present in a single input are copied as-is: the
# modern interface plugin only exists in the x86_64/arm64 builds, the
# Tiger-only artwork only in the PPC ones — a fat bundle simply carries
# both. Symlinks are reproduced from the first input providing them.
set -e

OUT="$1"
[ $# -ge 2 ] || { echo "usage: $0 <output.app> <input.app>..." >&2; exit 1; }
shift

command -v lipo >/dev/null || { echo "lipo not found" >&2; exit 1; }

lipo_merge()
{
    merge_dest=$1
    merge_list=$2
    set --
    while IFS= read -r merge_candidate; do
        [ -n "$merge_candidate" ] && set -- "$@" "$merge_candidate"
    done <<EOF
$merge_list
EOF
    lipo -create "$@" -output "$merge_dest"
}

for IN in "$@"; do
    [ -d "$IN" ] || { echo "missing input bundle: $IN" >&2; exit 1; }
done

rm -rf "$OUT"
mkdir -p "$OUT"

# union of relative paths across all inputs; plugins.dat is a per-arch
# plugin cache from the build machine and must never ship in the merge
TMPLIST=$(mktemp)
for IN in "$@"; do
    (cd "$IN" && find . \( -type f -o -type l \) -print)
done | grep -v 'plugins\.dat$' | sort -u > "$TMPLIST"

while IFS= read -r REL; do
    REL=${REL#./}
    DEST="$OUT/$REL"
    mkdir -p "$(dirname "$DEST")"

    # first input holding this path wins for symlinks / non-Mach-O
    FIRST=""
    CANDIDATES=""
    for IN in "$@"; do
        if [ -e "$IN/$REL" ] || [ -L "$IN/$REL" ]; then
            [ -n "$FIRST" ] || FIRST="$IN/$REL"
            if [ -f "$IN/$REL" ] && [ ! -L "$IN/$REL" ]; then
                CANDIDATES="$CANDIDATES
$IN/$REL"
            fi
        fi
    done

    if [ -L "$FIRST" ]; then
        cp -P "$FIRST" "$DEST"
        continue
    fi

    # De-duplicate candidates by architecture before lipo. Several inputs
    # can carry the very same slice — every PowerPC sub-build ships the
    # IDENTICAL ppc750 GCC runtime (libgcc_s/libstdc++/libatomic), and lipo
    # aborts when two inputs share an arch. The old code fell back to a plain
    # `cp` of the first input, which dropped every other slice: libgcc_s.1.1
    # ended up i386-only, so on a PowerPC Mac no plugin depending on it could
    # load (upnp, live555, taglib, mkv…). Keep one file per distinct arch so
    # a real fat is produced (ppc750 loads on every G3/G4/G5 by subtype grading).
    UNIQUE=""
    SEEN=" "
    OLDIFS=$IFS
    IFS='
'
    for CAND in $(printf '%s' "$CANDIDATES" | grep .); do
        CARCHS=$(lipo -archs "$CAND" 2>/dev/null) || CARCHS=""
        [ -n "$CARCHS" ] || continue          # not Mach-O: skip
        NEW=no
        for A in $CARCHS; do
            case "$SEEN" in
                *" $A "*) ;;
                *) NEW=yes; SEEN="$SEEN$A " ;;
            esac
        done
        [ "$NEW" = yes ] && UNIQUE="$UNIQUE$CAND
"
    done
    IFS=$OLDIFS

    NUNIQUE=$(printf '%s' "$UNIQUE" | grep -c . || true)
    if [ "$NUNIQUE" -gt 1 ]; then
        lipo_merge "$DEST" "$UNIQUE" \
            || cp "$FIRST" "$DEST"
    else
        cp "$FIRST" "$DEST"
    fi
done < "$TMPLIST"
rm -f "$TMPLIST"

# application icon carrying BOTH the Tiger element families and the
# modern PNG sizes (a per-input icns would miss one world or the other)
SCRIPTDIR=$(cd "$(dirname "$0")" && pwd)
UNIICON="$SCRIPTDIR/../../../modules/gui/legacy_macosx/Resources/VLC-universal.icns"
if [ -f "$UNIICON" ] && [ -d "$OUT/Contents/Resources" ]; then
    cp "$UNIICON" "$OUT/Contents/Resources/VLC.icns"
fi

# the Info.plist came from the FIRST input: relax the launch gate so the
# oldest supported release accepts the bundle (10.2, the PowerPC floor), with
# per-architecture minimums for LaunchServices that understand them
PLIST="$OUT/Contents/Info.plist"
if [ -f "$PLIST" ]; then
    PB=/usr/libexec/PlistBuddy
    $PB -c "Set :LSMinimumSystemVersion 10.2" "$PLIST" 2>/dev/null || true
    $PB -c "Delete :LSMinimumSystemVersionByArchitecture" "$PLIST" 2>/dev/null || true
    $PB -c "Add :LSMinimumSystemVersionByArchitecture dict" "$PLIST" 2>/dev/null && {
        # Every PowerPC slice (G3/G4/G4e/G5) is built with
        # -mmacosx-version-min=10.2 and carries the Jaguar compatibility
        # layer, so LaunchServices may offer the bundle from 10.2 on.
        $PB -c "Add :LSMinimumSystemVersionByArchitecture:ppc string 10.2.0" "$PLIST"
        $PB -c "Add :LSMinimumSystemVersionByArchitecture:i386 string 10.4.4" "$PLIST"
        # x86_64 gate is 10.6, NOT 10.5.8, on purpose: the Intel 64-bit slice
        # is built by the modern Xcode toolchain and its Mach-Os carry
        # LC_DYLD_INFO_ONLY (0x80000022), a load command Leopard's dyld (10.5)
        # does not understand — every native-interface plugin (macosx AND
        # legacy_macosx) then fails to load and VLC falls back to the Lua CLI
        # interface, which on a windowed launch surfaces as a "lua interface
        # error" dialog. The legacy toolchain that could emit a 10.5-loadable
        # binary cannot build the ARC modern interface, so a single x86_64
        # slice cannot serve both worlds. Gating x86_64 at 10.6 makes
        # LaunchServices on a 10.5.8 Intel Mac pick the i386 slice instead
        # (built by the legacy toolchain, loads cleanly, legacy interface),
        # so the app "just works" with no manual "open in 32-bit mode"; the
        # x86_64 slice serves 10.6+ where its modern Mach-O is loadable.
        $PB -c "Add :LSMinimumSystemVersionByArchitecture:x86_64 string 10.6.0" "$PLIST"
        $PB -c "Add :LSMinimumSystemVersionByArchitecture:arm64 string 11.0" "$PLIST"
    } 2>/dev/null || true
fi

# --- architecture trampoline --------------------------------------------
# Old 64-bit-capable Macs (Tiger 10.4 / Leopard 10.5) grade a universal
# binary's 64-bit slice highest and crash on it (no 64-bit Cocoa), and their
# LaunchServices ignores the plist gate above. Interpose a tiny libSystem-only
# stub as the bundle executable: its own 64-bit slice runs fine on those
# systems, and it re-exec()s the real binary picking a slice the running OS
# can use -- legacy_powerVLC (i386/ppc, no 64-bit slice to mis-grade) on Darwin<=9,
# fat_powerVLC (full universal) otherwise. All architectures stay in the bundle.
# Applied only to genuinely mixed bundles (both a 32-bit and a 64-bit slice);
# a modern-only or PPC-only bundle needs no trampoline. See vlctrampoline.c.
MACOSDIR="$OUT/Contents/MacOS"
EXE=$($PB -c "Print :CFBundleExecutable" "$PLIST" 2>/dev/null || echo VLC)
REALBIN="$MACOSDIR/$EXE"
STUBSRC="$SCRIPTDIR/vlctrampoline.c"
if [ -f "$REALBIN" ] && [ -f "$STUBSRC" ]; then
    ALLARCHS=$(lipo -archs "$REALBIN" 2>/dev/null || echo "")
    HAS64=no; HAS32=no
    for A in $ALLARCHS; do
        case "$A" in
            x86_64|arm64) HAS64=yes ;;
            i386|ppc*)    HAS32=yes ;;
        esac
    done

    if [ "$HAS64" = yes ] && [ "$HAS32" = yes ]; then
        LT="${VLC_LEGACY_TOOLCHAIN:-$HOME/Projects/darwin-legacy-toolchain}"
        CC_I386="$LT/opt/gcc-i686-tiger/bin/tiger-cc"
        [ -x "$CC_I386" ] || CC_I386="$LT/opt/gcc-i686/bin/tiger-cc"
        CC_PPC="$LT/opt/gcc-ppc-tiger/bin/tiger-cc"

        # one compile per canonical target (all ppc subtypes -> a single ppc
        # slice, which grades on every G3/G4/G5)
        TARGETS=""
        for A in $ALLARCHS; do
            case "$A" in ppc*) K=ppc ;; *) K=$A ;; esac
            case " $TARGETS " in *" $K "*) ;; *) TARGETS="$TARGETS $K" ;; esac
        done

        TD=$(mktemp -d)
        STUBS=""; OK=yes
        for K in $TARGETS; do
            OBJ="$TD/stub.$K"
            case "$K" in
                # ⚠ The deployment target MUST be stated. Left implicit, the
                # Tiger cross-GCC defaults to 10.4 and the PowerPC stub comes
                # out referencing `_snprintf$LDBL128` -- the 128-bit long-double
                # variant that only exists from 10.4 on. The bundle then dies at
                # launch on Jaguar with "undefined reference to
                # _snprintf$LDBL128", even though every real slice was built
                # for 10.2: the two-line trampoline was the whole problem.
                i386)   "$CC_I386" -arch i386 -mmacosx-version-min=10.4 \
                            -O2 -o "$OBJ" "$STUBSRC" 2>/dev/null || OK=no ;;
                # -lSystemStubs: below 10.4 the SDK redirects the printf family
                # to `_<fn>$LDBLStub`, which lives in that static library and
                # nowhere else -- without it the stub does not even link.
                ppc)    "$CC_PPC"  -arch ppc  -mmacosx-version-min=10.2 \
                            -O2 -o "$OBJ" "$STUBSRC" -lSystemStubs \
                            2>/dev/null || OK=no ;;
                x86_64) xcrun clang -arch x86_64 -mmacosx-version-min=10.4 -O2 -o "$OBJ" "$STUBSRC" 2>/dev/null || OK=no ;;
                arm64)  xcrun clang -arch arm64  -mmacosx-version-min=11.0 -O2 -o "$OBJ" "$STUBSRC" 2>/dev/null || OK=no ;;
                *)      OK=no ;;
            esac
            [ "$OK" = yes ] || break
            STUBS="$STUBS $OBJ"
        done

        if [ "$OK" = yes ] && [ -n "$STUBS" ]; then
            mv "$REALBIN" "$MACOSDIR/fat_powerVLC"
            RM=""
            case " $ALLARCHS " in *" x86_64 "*) RM="$RM -remove x86_64" ;; esac
            case " $ALLARCHS " in *" arm64 "*)  RM="$RM -remove arm64" ;; esac
            # shellcheck disable=SC2086
            lipo "$MACOSDIR/fat_powerVLC" $RM -output "$MACOSDIR/legacy_powerVLC"
            # shellcheck disable=SC2086
            lipo -create $STUBS -output "$REALBIN"
            chmod +x "$REALBIN" "$MACOSDIR/fat_powerVLC" "$MACOSDIR/legacy_powerVLC"
            # Sign the new executables now so the final --deep bundle seal is
            # consistent: a single --deep pass mis-seals a bundle that just
            # gained loose executables in Contents/MacOS ("a sealed resource is
            # missing or invalid"); signing them first fixes it.
            for B in "$REALBIN" "$MACOSDIR/fat_powerVLC" "$MACOSDIR/legacy_powerVLC"; do
                codesign --force --sign - "$B" 2>/dev/null || true
            done
            echo "trampoline: $EXE stub [$(lipo -archs "$REALBIN")]" \
                 "-> legacy_powerVLC [$(lipo -archs "$MACOSDIR/legacy_powerVLC")] / fat_powerVLC [$ALLARCHS]"
        else
            echo "trampoline: SKIPPED, could not build stub for all of [$ALLARCHS]" >&2
        fi
        rm -rf "$TD"
    fi
fi

# Lua bytecode is per-architecture; a universal bundle spans big- and
# little-endian, 32- and 64-bit, so ship portable source (see lua-portable.sh)
"$SCRIPTDIR/lua-portable.sh" "$OUT" || true

# ad-hoc signature: arm64 slices must be signed to load on Apple Silicon
codesign --force --deep --sign - "$OUT" 2>/dev/null || true

echo "universal bundle created at $OUT"
