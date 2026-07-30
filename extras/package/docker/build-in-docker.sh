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
#   linux-arm64-appimage  PowerVLC-<ver>-aarch64.AppImage   (native on arm64 host: fast)
#   linux-amd64-appimage  PowerVLC-<ver>-x86_64.AppImage    (emulated on arm64 host: slow)
#   linux-i386-appimage   PowerVLC-<ver>-i386.AppImage      (emulated, legacy)
#
# Speed note (arm64 host): Windows targets cross-compile with a NATIVE arm64
# toolchain (fast). linux-arm64 is native (fast). linux-amd64 / linux-i386 run
# under QEMU emulation and can take hours. See README.md.
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
[ -n "$PVLC_VER" ] || PVLC_VER="1.1.0"

# VLC derives its revision string from git; /work is not a git repo (the clean
# copy excludes .git), so compute it here and drop it into src/revision.txt,
# which VLC's build reads as the non-git fallback.
REVISION="$(git -C "$REPO" describe --always HEAD 2>/dev/null || echo "$PVLC_VER")"

# Populate /work with a clean snapshot of the working tree (committed + untracked
# non-ignored files). Used by the Windows and Linux (AppImage) builds.
# Two passes: everything except the vendored contrib source tarballs is synced
# normally; the tarballs are synced with --ignore-existing so a re-run never
# rewrites their mtime (which would needlessly re-extract/rebuild contribs).
SEED='set -e; git config --global --add safe.directory /src;
  ( cd /src && git ls-files -co --exclude-standard -z \
      | grep -zv "^contrib/tarballs/" \
      | rsync -0a --files-from=- /src/ /work/ );
  ( cd /src && git ls-files -co --exclude-standard -z -- contrib/tarballs \
      | rsync -0a --ignore-existing --files-from=- /src/ /work/ );
  mkdir -p /work/src; printf "%s\n" "${REVISION:-unknown}" > /work/src/revision.txt;
  cd /work'

# WORK_VOL: a persistent named Docker volume mounted at /work, so build state
# (extras/tools, contribs, the VLC build dir) SURVIVES between runs — a retry
# after a fix RESUMES instead of recompiling everything. Set per target below.
# Reset with:  ./build-in-docker.sh clean
WORK_VOL=""

docker_run() { # docker_run <platform> <image> <shell-command>
  docker run --rm --platform "$1" \
    -v "$REPO":/src:ro -v "$OUT":/out -v "${WORK_VOL}":/work \
    -e "PVLC_VER=$PVLC_VER" -e "REVISION=$REVISION" \
    "$2" sh -eu -c "$3"
}

# Zip what a target just produced, mirroring the macOS convention: section 4 of
# BUILD-POWERVLC.md ships every bundle as powervlc-<version>-<target>.zip, so
# the Windows installers and the Linux AppImages are archived the same way.
# The raw .exe / .AppImage is KEPT alongside the zip -- that is the file you
# run locally; the zip is the one you hand out.
#
# Never fatal: a missing zip binary or an unexpected artifact name must not
# throw away a build that can take hours under emulation.
package_zip() { # package_zip <label> <glob relative to $OUT>
  ( cd "$OUT"
    if ! command -v zip >/dev/null 2>&1; then
      echo "WARN: 'zip' not found; skipping the $1 archive" >&2
      exit 0
    fi
    files=$(ls $2 2>/dev/null || true)
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
  docker build --platform linux/arm64 -t powervlc-win \
    -f "$DOCKER_DIR/Dockerfile.windows" "$DOCKER_DIR"
  docker_run linux/arm64 powervlc-win \
    "$SEED
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
     extras/package/win32/build.sh $1 -l -i r
     found=\$(find /work -maxdepth 2 -name 'PowerVLC-*-$2*.exe' -o -maxdepth 2 -name 'vlc-*-$2*.exe' | head -20)
     [ -n \"\$found\" ] || { echo 'ERROR: no $2 installer produced'; exit 1; }
     for f in \$found; do cp -v \"\$f\" /out/; done"
  package_zip "$2" "*$2*.exe"
}

build_linux_appimage() { # build_linux_appimage <platform> <base-image> <appimage-arch>
  arch_tag="$(echo "$1" | tr '/' '-')"
  WORK_VOL="powervlc-build-$arch_tag"
  docker build --platform "$1" --build-arg BASE="$2" -t "powervlc-linux-$arch_tag" \
    -f "$DOCKER_DIR/Dockerfile.linux" "$DOCKER_DIR"
  docker_run "$1" "powervlc-linux-$arch_tag" \
    "$SEED
     ./bootstrap
     # --disable-update-check: no integrated updater in the fork. It is
     # already configure's default, stated here so it stays off.
     ./configure --disable-wayland --enable-merge-ffmpeg \
                 --disable-update-check --prefix=/usr
     make -j\$(nproc)
     VERSION=\"\$PVLC_VER\" BUILDDIR=/work WORKDIR=/work \
       extras/package/appimage/build-appimage.sh
     cp -v /work/PowerVLC-*.AppImage /out/"
  package_zip "linux-$3" "PowerVLC-*-$3.AppImage"
}

[ "$#" -ge 1 ] || { grep '^#   ' "$0" | sed 's/^#  //'; exit 1; }

if [ "$1" = "clean" ]; then
  echo "Removing PowerVLC build volumes..."
  docker volume ls -q | grep '^powervlc-build-' | xargs -r docker volume rm || true
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
