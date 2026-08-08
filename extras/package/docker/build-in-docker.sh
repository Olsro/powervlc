#!/bin/sh
#
# build-in-docker.sh — build PowerVLC Windows/Linux artifacts on any machine
# with Docker (in particular an Apple-Silicon Mac), and drop the results into
# extras/package/docker/out/.
#
# PowerVLC is an unofficial fork of VLC, not affiliated with VideoLAN.
#
# Usage:
#   ./extras/package/docker/build-in-docker.sh <target> [more targets...]
#
# Targets:
#   win32                 PowerVLC-<ver>-win32.exe    (mingw-w64 GCC, msvcrt, XP floor)
#   win64                 PowerVLC-<ver>-win64.exe    (mingw-w64 GCC, msvcrt, Vista floor)
#   winarm64              PowerVLC-<ver>-winarm64.exe (llvm-mingw, ucrt, Win10 floor)
#
# Every Windows target ships TWO archives, from one and the same build:
#   powervlc-<ver>-<arch>-nsis.zip      the NSIS installer, zipped
#   powervlc-<ver>-<arch>-portable.zip  the app tree, settings kept next to
#                                       powervlc.exe (see package.mak)
#   linux-arm64-appimage  PowerVLC-<ver>-aarch64.AppImage   (native on arm64 host: fast)
#   linux-amd64-appimage  PowerVLC-<ver>-x86_64.AppImage    (emulated on arm64 host: slow)
#   linux-i386-appimage   PowerVLC-<ver>-i386.AppImage      (emulated, legacy)
#
# Housekeeping subcommands (instead of a target):
#   reclaim               drop the per-target build dirs, KEEP the contribs
#   clean                 delete the build volumes outright (contribs included)
#
# Speed note (arm64 host): Windows targets cross-compile with a NATIVE arm64
# toolchain (fast). linux-arm64 is native (fast). linux-amd64 / linux-i386 run
# under QEMU emulation and can take hours. See README.md.
#
# Disk: Docker Desktop's virtual disk is a hard ceiling and the three Windows
# targets share one volume (~23 GB of contribs plus 2-5 GB per target). Each
# build reclaims the other targets' build dirs when free space drops under
# PVLC_MIN_FREE_GB (default 10), so a full campaign fits without babysitting.
#
# The build runs from a CLEAN copy of your working tree (tracked + new files,
# minus git-ignored build artifacts), so it never mixes with your macOS build
# dirs.

set -eu

DOCKER_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$DOCKER_DIR/../../.." && pwd)"
OUT="$DOCKER_DIR/out"
mkdir -p "$OUT"

# PowerVLC product version, for AppImage filenames (the Windows targets derive
# their own version from configure/git).
PVLC_VER="$(sed -n 's/^POWERVLC_VERSION="\(.*\)"/\1/p' "$REPO/configure.ac" | head -1)"
[ -n "$PVLC_VER" ] || PVLC_VER="1.2.0"

# VLC derives its revision string from git; /work is not a git repo (the clean
# copy excludes .git), so compute it here and drop it into src/revision.txt,
# which VLC's build reads as the non-git fallback.
REVISION="$(git -C "$REPO" describe --always HEAD 2>/dev/null || echo "$PVLC_VER")"

# Populate /work with a clean snapshot of the working tree (committed + untracked
# non-ignored files). Used by the Windows and Linux (AppImage) builds.
# Two passes: everything except the vendored contrib source tarballs is synced
# normally; the tarballs are synced with --ignore-existing so a re-run never
# rewrites their mtime (which would needlessly re-extract/rebuild contribs).
#
# The tmpwrk* sweep matters more than it looks: autopoint creates tmpwrk<pid>
# in the source root and removes it on exit, so a build interrupted there (a
# killed container, a full disk, ^C) leaves one behind -- and autopoint then
# refuses to start FOREVER with "directory tmpwrkNNNN already exists". The
# state that makes a rerun resume is also the state that makes it fail.
# The compiled catalogues (po/*.gmo) get a pass of their own because they are
# git-ignored -- so the snapshot above leaves them out -- AND because nothing
# in the container would rebuild them: gettext hangs the .gmo off `stamp-po`,
# which only fires when the .pot changes, so a .po edited by hand is compiled
# on the host and NEVER recompiled by make. Without this pass the container
# keeps whatever .gmo its persistent volume happened to have, and the build
# silently ships a catalogue several strings short of the sources it was made
# from (caught on the 1.2.0 round: 6138 messages in the Windows fr.mo against
# 6143 on the Mac). They are byte-identical everywhere -- architecture plays
# no part in a .mo -- so copying the host's is exactly right.
SEED='set -e; git config --global --add safe.directory /src;
  ( cd /src && git ls-files -co --exclude-standard -z \
      | grep -zv "^contrib/tarballs/" \
      | rsync -0a --files-from=- /src/ /work/ );
  ( cd /src && git ls-files -co --exclude-standard -z -- contrib/tarballs \
      | rsync -0a --ignore-existing --files-from=- /src/ /work/ );
  ( cd /src && ls po/*.gmo 2>/dev/null \
      | rsync -a --files-from=- /src/ /work/ ) || true;
  mkdir -p /work/src; printf "%s\n" "${REVISION:-unknown}" > /work/src/revision.txt;
  rm -rf /work/tmpwrk*;
  cd /work'

# WORK_VOL: a persistent named Docker volume mounted at /work, so build state
# (extras/tools, contribs, the VLC build dir) SURVIVES between runs — a retry
# after a fix RESUMES instead of recompiling everything. Set per target below.
# Reset with:  ./build-in-docker.sh clean
WORK_VOL=""

# Docker Desktop's virtual disk is a hard ceiling (Settings > Resources), and
# it is easy to hit: the three Windows targets SHARE one volume, where the
# contribs alone are ~23 GB and each target's build directory adds 2-5 GB more.
# Running out mid-build is not a clean failure. Sometimes it is an unrelated
# "install: error writing ...: No space left on device" deep inside make, hours
# in. Worse, it can be SILENT CORRUPTION: the compiler writes a zero-length
# object, and the error you finally see is a link failure with a wall of
# undefined references (or "strip: input file ... has no sections"). If you
# ever see either, check free space before you debug the code.
#
# 20 and not 10: a from-scratch Windows contrib build (Qt above all) eats well
# over 10 GB, so a run starting at 14 GB free cleared a 10 GB bar and then hit
# the wall anyway. The reclaim only runs once, at startup, so the bar has to
# cover the whole build. Override with PVLC_MIN_FREE_GB=<n>.
PVLC_MIN_FREE_GB="${PVLC_MIN_FREE_GB:-20}"

docker_run() { # docker_run <platform> <image> <shell-command>
  docker run --rm --platform "$1" \
    -v "$REPO":/src:ro -v "$OUT":/out -v "${WORK_VOL}":/work \
    -e "PVLC_VER=$PVLC_VER" -e "REVISION=$REVISION" \
    -e "PVLC_MIN_FREE_GB=$PVLC_MIN_FREE_GB" \
    "$2" sh -eu -c "$3"
}

# Shell snippet evaluated INSIDE the container (prepended to the build command,
# so it costs no extra docker run). Its text is substituted verbatim -- shell
# expansion is not recursive -- so it is written as plain container-side shell,
# with no escaping. It uses only cut/tr, no awk, to stay clear of nested quotes.
#
# pvlc_reclaim drops the build directories of the OTHER targets sharing this
# volume when space runs short. It never touches contrib/: rebuilding a build
# directory costs minutes, rebuilding the Windows contribs costs hours.
DISK_HELPERS='
pvlc_free_gb() {
  df -P -BG /work | tail -1 | tr -s " " | cut -d" " -f4 | tr -d "G"
}
pvlc_reclaim() {  # pvlc_reclaim <name of the target being built>
  keep=$1
  min=${PVLC_MIN_FREE_GB:-10}
  free=$(pvlc_free_gb)
  echo "  disk: ${free}G free in the work volume (reclaim below ${min}G)"
  if [ "$free" -ge "$min" ]; then return 0; fi
  for d in /work/win32* /work/win64* /work/winarm64*; do
    [ -d "$d" ] || continue
    case "$d" in
      /work/${keep}*) continue ;;
    esac
    echo "  disk: below ${min}G — dropping stale build dir $d (contribs kept)"
    rm -rf "$d"
  done
  echo "  disk: $(pvlc_free_gb)G free after reclaim"
  return 0
}
'

# Zip what a target just produced, mirroring the macOS convention: section 4 of
# BUILD-POWERVLC.md ships every bundle as powervlc-<version>-<label>.zip, so
# the Windows installers and the Linux AppImages are archived the same way.
# The Windows callers pass '<arch>-nsis' as the label, since a Windows target
# now also produces a '<arch>-portable' archive (which needs no wrapping and
# does not go through here).
# The raw .exe / .AppImage is KEPT alongside the zip -- that is the file you
# run locally; the zip is the one you hand out.
#
# Only what THIS run produced goes in: out/ keeps every artifact ever built,
# so a plain "*win64*.exe" glob also swept up the installers of previous
# versions and shipped all of them in a single zip. The caller lays down a
# stamp file just before the build; anything not newer than it belongs to
# another version and stays out.
#
# Never fatal: a missing zip binary or an unexpected artifact name must not
# throw away a build that can take hours under emulation.
package_zip() { # package_zip <label> <glob relative to $OUT> <stamp file>
  ( cd "$OUT"
    if ! command -v zip >/dev/null 2>&1; then
      echo "WARN: 'zip' not found; skipping the $1 archive" >&2
      exit 0
    fi
    if [ -n "${3:-}" ] && [ -e "$3" ]; then
      files=$(find . -maxdepth 1 -name "$2" -newer "$3" 2>/dev/null \
              | sed 's|^\./||')
    else
      files=$(ls $2 2>/dev/null || true)
    fi
    if [ -z "$files" ]; then
      echo "WARN: nothing matching '$2'; no $1 archive made" >&2
      exit 0
    fi
    zipname="powervlc-$PVLC_VER-$1.zip"
    rm -f "$zipname"
    zip -qj "$zipname" $files
    echo "  packaged: $OUT/$zipname" )
}

build_windows() { # build_windows <arch-flags> <name-glob>
  WORK_VOL="powervlc-build-windows"
  # marks the artifacts of this run, see package_zip
  STAMP=$(mktemp)
  # Only (re)build the image when it does not exist yet: the docker build
  # is not reproducible offline (bionic-era apt repositories move), and a
  # pruned build cache would otherwise force a full re-run of it.
  # (retry once: a busy daemon can fail a first inspect transiently)
  docker image inspect powervlc-win >/dev/null 2>&1 || \
  { sleep 3; docker image inspect powervlc-win >/dev/null 2>&1; } || \
  docker build --platform linux/arm64 -t powervlc-win \
    -f "$DOCKER_DIR/Dockerfile.windows" "$DOCKER_DIR"
  docker_run linux/arm64 powervlc-win \
    "$SEED
     $DISK_HELPERS
     # The three Windows targets share this volume, so the two we are NOT
     # building are dead weight once their installers are in out/ -- reclaim
     # them rather than dying on ENOSPC halfway through 'make install'.
     pvlc_reclaim $2
     # Clean stale packaging staging so a re-package does not objcopy-strip the
     # NSIS setup exe left by a previous run (\"spad-setup.exe: file truncated\"),
     # AND remove the install prefix (_win32) so 'make install' re-populates it
     # without renamed-away leftovers (e.g. a stale libvlc.dll shipped by the
     # 'InstallFile *.dll' wildcard next to the new libpowervlc.dll).
     rm -rf /work/$2*/vlc-* /work/$2*/PowerVLC-* /work/$2*/symbols-* /work/$2*/spad-setup.exe /work/$2*/_win32 2>/dev/null || true
     # -l enables NLS. Without it win32/build.sh adds --disable-nls and the
     # installed app has NO locale/ catalogs at all, so the UI stays English
     # whatever language the user picks in the preferences (the NSIS
     # 'InstallFolderOptional locale' uses File /nonfatal, so the empty
     # folder is skipped in silence rather than failing the package).
     # -r is RELEASE MODE, and is not the same thing as the 'r' of -i (which
     # only names the installer flavour). Without it win32/build.sh adds
     # --enable-debug, so every Windows installer shipped before this was a
     # debug build: assertions live, NDEBUG unset. On Windows XP that showed
     # up as a Microsoft Visual C++ Runtime Library assertion box on every
     # quit (src/modules/entry.c). macOS has always defined NDEBUG.
     extras/package/win32/build.sh $1 -r -l -i r
     found=\$(find /work -maxdepth 2 -name 'PowerVLC-*-$2*.exe' -o -maxdepth 2 -name 'vlc-*-$2*.exe' | head -20)
     [ -n \"\$found\" ] || { echo 'ERROR: no $2 installer produced'; exit 1; }
     for f in \$found; do cp -v \"\$f\" /out/; done
     # The portable archive (package-win32-portable-zip) is already the final
     # deliverable -- a zip of the app tree with the 'portable' marker folder in
     # it -- so it is copied out under its release name directly rather than
     # being wrapped in a second zip like the installer is. Renaming here and
     # not in the Makefile keeps the case fold from biting: /out lives on the
     # host, and on macOS 'PowerVLC-....zip' and 'powervlc-....zip' are the
     # same file.
     port=\$(find /work -maxdepth 2 -name 'PowerVLC-*-$2-portable.zip' | head -1)
     [ -n \"\$port\" ] || { echo 'ERROR: no $2 portable archive produced'; exit 1; }
     cp -v \"\$port\" \"/out/powervlc-\$PVLC_VER-$2-portable.zip\""
  # '-nsis': what this zip holds is the installer, and it now has a portable
  # sibling to be told apart from. The plain 'powervlc-<ver>-<arch>.zip' of
  # earlier releases was this same file under an ambiguous name.
  package_zip "$2-nsis" "*$2*.exe" "$STAMP"
  rm -f "$STAMP"
}

build_linux_appimage() { # build_linux_appimage <platform> <base-image> <appimage-arch>
  arch_tag="$(echo "$1" | tr '/' '-')"
  WORK_VOL="powervlc-build-$arch_tag"
  # marks the artifacts of this run, see package_zip
  STAMP=$(mktemp)
  # See build_windows: reuse the existing image rather than re-running an
  # apt-get against end-of-life repositories.
  docker image inspect "powervlc-linux-$arch_tag" >/dev/null 2>&1 || \
  { sleep 3; docker image inspect "powervlc-linux-$arch_tag" >/dev/null 2>&1; } || \
  docker build --platform "$1" --build-arg BASE="$2" -t "powervlc-linux-$arch_tag" \
    -f "$DOCKER_DIR/Dockerfile.linux" "$DOCKER_DIR"
  docker_run "$1" "powervlc-linux-$arch_tag" \
    "$SEED
     $DISK_HELPERS
     # Each Linux target owns its volume, so there is nothing here to reclaim
     # from -- report the headroom so a later ENOSPC is not a surprise.
     echo \"  disk: \$(pvlc_free_gb)G free in the work volume\"
     # Build the FFmpeg 8.1 contrib (static) instead of linking the
     # distribution's ancient one: same decoders (ATRAC9, APV, the 8.x
     # improvements) in the AppImages as in every other target. The
     # contrib state persists in the work volume, so this is a one-off.
     # ffmpeg's x86 assembly needs nasm, absent from the image: build it
     # with the in-tree tools (no-op when the tool already exists).
     ( cd extras/tools && ./bootstrap && make .buildnasm 2>/dev/null || make .nasm || true )
     export PATH=\"/work/extras/tools/build/bin:\$PATH\"
     ( cd contrib && mkdir -p native && cd native && \
       ../bootstrap && VLC_FFMPEG_NO_OPENJPEG=1 make .ffmpeg .postproc )
     CONTRIB_PREFIX=\$(ls -d /work/contrib/*-linux-gnu* 2>/dev/null | grep -v contrib- | head -1)
     export PKG_CONFIG_PATH=\"\$CONTRIB_PREFIX/lib/pkgconfig\${PKG_CONFIG_PATH:+:\$PKG_CONFIG_PATH}\"
     ./bootstrap
     # --disable-update-check: no integrated updater in the fork. It is
     # already configure's default, stated here so it stays off.
     ./configure --disable-wayland --enable-merge-ffmpeg \
                 --disable-update-check --prefix=/usr
     make -j\$(nproc)
     # Stale AppImages from previous runs (older version strings) linger in
     # the persistent volume and would be copied out and zipped alongside
     # the fresh one: keep only what this run produces.
     rm -f /work/PowerVLC-*.AppImage
     VERSION=\"\$PVLC_VER\" BUILDDIR=/work WORKDIR=/work \
       extras/package/appimage/build-appimage.sh
     cp -v /work/PowerVLC-*.AppImage /out/"
  package_zip "linux-$3" "PowerVLC-*-$3.AppImage" "$STAMP"
  rm -f "$STAMP"
}

[ "$#" -ge 1 ] || { grep '^#   ' "$0" | sed 's/^#  //'; exit 1; }

if [ "$1" = "clean" ]; then
  echo "Removing PowerVLC build volumes..."
  docker volume ls -q | grep '^powervlc-build-' | xargs -r docker volume rm || true
  exit 0
fi

# 'reclaim' is the middle ground between doing nothing and 'clean': it drops
# the per-target build directories (minutes to rebuild) and any interrupted
# autopoint tmpwrk, but KEEPS the contribs (hours to rebuild). Reach for it
# when the Docker disk is full and you would rather not lose the expensive
# state -- the build itself does this automatically under PVLC_MIN_FREE_GB.
if [ "$1" = "reclaim" ]; then
  echo "Dropping per-target build directories (contribs are kept)..."
  for v in $(docker volume ls -q | grep '^powervlc-build-' || true); do
    echo "  volume $v"
    docker run --rm -v "$v":/work alpine sh -c '
      for d in /work/win32* /work/win64* /work/winarm64* /work/tmpwrk*; do
        [ -e "$d" ] || continue
        echo "    rm $d"
        rm -rf "$d"
      done
      df -h /work | tail -1 | sed "s/^/    /"' 2>/dev/null || \
      echo "    (skipped: could not run the alpine helper)"
  done
  exit 0
fi

for TARGET in "$@"; do
  echo "======================================================================"
  echo "  PowerVLC docker build: $TARGET"
  echo "======================================================================"
  case "$TARGET" in
    win32)    build_windows "-a i686"        "win32"    ;;
    win64)    build_windows "-a x86_64"      "win64"    ;;
    winarm64) build_windows "-a aarch64 -u"  "winarm64" ;;
    linux-arm64-appimage) build_linux_appimage linux/arm64 ubuntu:18.04 aarch64 ;;
    linux-amd64-appimage) build_linux_appimage linux/amd64 ubuntu:18.04 x86_64 ;;
    linux-i386-appimage)  build_linux_appimage linux/386  i386/debian:bullseye i386 ;;
    *) echo "unknown target: $TARGET"; exit 1 ;;
  esac
done

echo
echo "Done. Artifacts in: $OUT"
ls -la "$OUT"
