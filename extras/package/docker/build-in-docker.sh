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
#   linux-amd64-appimage  PowerVLC-<ver>-x86_64.AppImage    (native cross-build on arm64)
#   linux-i386-appimage   PowerVLC-<ver>-i386.AppImage      (native cross-build on arm64)
#   linux-amd64-cross-check  verify native arm64 -> amd64 GCC/sysroot
#   linux-i386-cross-check   verify native arm64 -> i386 GCC/sysroot
#   linux-amd64-cross-configure  configure a minimal native-cross VLC build
#   linux-i386-cross-configure   configure a minimal native-cross VLC build
#   linux-amd64-cross-ffmpeg     build the FFmpeg contrib natively-cross
#   linux-i386-cross-ffmpeg      build the FFmpeg contrib natively-cross
#   linux-amd64-cross-build      compile the configured VLC core natively-cross
#   linux-i386-cross-build       compile the configured VLC core natively-cross
#   linux-amd64-cross-toolchain  build the glibc-2.27 GCC C/C++ toolchain
#   linux-i386-cross-toolchain   build the glibc-2.27 GCC C/C++ toolchain
#
# Housekeeping subcommands (instead of a target):
#   reclaim               drop the per-target build dirs, KEEP the contribs
#   clean                 delete the build volumes outright (contribs included)
#
# Speed note (arm64 host): Windows targets cross-compile with a NATIVE arm64
# toolchain (fast). linux-arm64 is native; linux-amd64 / linux-i386 are native
# arm64 cross-compilations with Bionic sysroots. See README.md.
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
[ -n "$PVLC_VER" ] || {
    echo "Unable to read POWERVLC_VERSION from configure.ac" >&2
    exit 1
}

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
      | rsync -0a --ignore-missing-args --files-from=- /src/ /work/ );
  ( cd /src && git ls-files -co --exclude-standard -z -- contrib/tarballs \
      | rsync -0a --ignore-existing --ignore-missing-args --files-from=- /src/ /work/ );
  ( cd /work && git -C /src ls-files -d -z | xargs -0 -r rm -f -- );
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

cross_image() {
  case "$1" in
    amd64) printf '%s\n' powervlc-linux-cross-qt-amd64-v6 ;;
    i386)  printf '%s\n' powervlc-linux-cross-qt-i386-v2 ;;
  esac
}

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
  docker run --rm --platform "$1" --entrypoint /bin/sh \
    -v "$REPO":/src:ro -v "$OUT":/out -v "${WORK_VOL}":/work \
    -e "PVLC_VER=$PVLC_VER" -e "REVISION=$REVISION" \
    -e "PVLC_MIN_FREE_GB=$PVLC_MIN_FREE_GB" \
    "$2" -eu -c "$3"
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
  case "$keep" in
    win32) keep_arch=i686 ;;
    win64) keep_arch=x86_64 ;;
    winarm64) keep_arch=aarch64 ;;
    *) keep_arch="$keep" ;;
  esac
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
  for d in /work/build/dependencies/amule/windows-*; do
    [ -d "$d" ] || continue
    case "$d" in
      /work/build/dependencies/amule/windows-$keep_arch) continue ;;
    esac
    echo "  disk: dropping stale private-engine build $d"
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

# Linux release ZIPs also carry a distribution-neutral, unprivileged installer.
# The visible executable is the shell implementation itself: unlike an extracted
# .desktop file it needs no desktop-specific trust metadata before its first run.
# It installs the AppImage and its embedded desktop entry in XDG paths.
package_linux_zip() { # package_linux_zip <label> <glob relative to $OUT> <stamp file>
  ( cd "$OUT"
    label=$1
    pattern=$2
    stamp=$3
    if ! command -v zip >/dev/null 2>&1; then
      echo "WARN: 'zip' not found; skipping the $label archive" >&2
      exit 0
    fi
    files=$(find . -maxdepth 1 -name "$pattern" -newer "$stamp" 2>/dev/null \
            | sed 's|^\./||')
    if [ -z "$files" ]; then
      echo "WARN: nothing matching '$pattern'; no $label archive made" >&2
      exit 0
    fi
    set -- $files
    if [ "$#" -ne 1 ]; then
      echo "ERROR: expected exactly one AppImage for the $label archive, found $#" >&2
      exit 1
    fi
    installer_script="$REPO/extras/package/appimage/install-powervlc.sh"
    installer_i18n="$REPO/extras/package/appimage/install-powervlc-i18n.sh"
    test -x "$installer_script"
    test -r "$installer_i18n"
    zipname="powervlc-$PVLC_VER-$label.zip"
    rm -f "$zipname"
    stage=$(mktemp -d "$OUT/.powervlc-linux-zip.XXXXXX")
    trap 'rm -rf "$stage"' EXIT HUP INT TERM
    for file in $files; do cp "$file" "$stage/"; done
    cp "$installer_script" "$stage/Install PowerVLC"
    cp "$installer_i18n" "$stage/.install-powervlc-i18n.sh"
    chmod 0755 "$stage/Install PowerVLC"
    chmod 0644 "$stage/.install-powervlc-i18n.sh"
    /bin/sh -n "$stage/Install PowerVLC"
    /bin/sh -n "$stage/.install-powervlc-i18n.sh"
    /bin/sh "$stage/Install PowerVLC" --help >/dev/null
    ( cd "$stage" && zip -q "$OUT/$zipname" ./* \
        ./.install-powervlc-i18n.sh )
    rm -rf "$stage"
    trap - EXIT HUP INT TERM
    echo "  packaged: $OUT/$zipname (AppImage + double-click installer)" )
}

# The compiler image is deliberately linux/arm64 on Apple Silicon, but the
# cache generator has to load the finished PE plug-ins. Run that short
# finalization step in a target-matched Wine container: no Windows host is
# involved, and no target emulation slows down the multi-hour compilation.
finalize_windows_portable() { # finalize_windows_portable <win target> <input name> <output name>
  case "$1" in
    win32)    cache_platform=linux/386 ;;
    win64)    cache_platform=linux/amd64 ;;
    winarm64) cache_platform=linux/arm64 ;;
    *) echo "ERROR: unsupported Windows cache target: $1" >&2; return 2 ;;
  esac
  cache_arch=${cache_platform#linux/}
  cache_image="powervlc-wine-cache-${cache_arch}-v1"

  docker build --platform "$cache_platform" -t "$cache_image" \
    -f "$DOCKER_DIR/Dockerfile.windows-cache" "$DOCKER_DIR"

  docker run --rm --network none --platform "$cache_platform" \
    -v "$OUT":/out \
    "$cache_image" "$1" "/out/$2" "/out/$3"
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
  raw_port_name=".powervlc-$PVLC_VER-$2-portable.raw.zip"
  final_port_name="powervlc-$PVLC_VER-$2-portable.zip"
  rm -f "$OUT/$raw_port_name" "$OUT/$final_port_name"
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
     # libafpclient and libsmb2 are linked statically into their plugins, which
     # means Automake cannot see changed contrib archives through pkg-config
     # -l flags. Relink these small targets on every packaging run so network
     # fixes are never hidden behind an otherwise valid incremental build.
     rm -f /work/$2*/modules/libafp_plugin.la /work/$2*/modules/.libs/libafp_plugin.dll \
           /work/$2*/modules/libsmb2_plugin.la /work/$2*/modules/.libs/libsmb2_plugin.dll \
           2>/dev/null || true
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
     # Copy the raw portable tree to a hidden intermediate. A target-matched
     # Wine container below generates plugins.dat from the exact stripped DLL
     # set and publishes the verified release archive. Renaming here and not in
     # the Makefile also keeps the case fold from biting: /out lives on the
     # host, and on macOS 'PowerVLC-....zip' and 'powervlc-....zip' are the same
     # file.
     port=\$(find /work -maxdepth 2 -name 'PowerVLC-*-$2-portable.zip' | head -1)
     [ -n \"\$port\" ] || { echo 'ERROR: no $2 portable archive produced'; exit 1; }
     cp -v \"\$port\" \"/out/$raw_port_name\""

  if finalize_windows_portable "$2" "$raw_port_name" "$final_port_name"; then
    rm -f "$OUT/$raw_port_name"
  else
    status=$?
    rm -f "$OUT/$raw_port_name" "$STAMP"
    return "$status"
  fi
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
     # ffmpeg's x86 assembly needs nasm and the libsmb2 contrib needs CMake;
     # neither is present in the old distro images. Build both with the
     # in-tree tools (a no-op after the per-architecture volume has cached
     # them).
    ( cd extras/tools && ./bootstrap && make .buildnasm && \
      { command -v cmake >/dev/null 2>&1 || make .buildcmake; } )
     export PATH=\"/work/extras/tools/build/bin:\$PATH\"
     # Meson 1.x requires Python >= 3.7, while the glibc 2.27 base deliberately
     # uses Ubuntu 18.04 and Python 3.6. Keep a checked, target-local Meson for
     # that old runtime instead of lowering the tools used by other platforms.
     if ! python3 -c 'import sys; assert sys.version_info >= (3, 7)' 2>/dev/null; then
       meson_root=/work/.scratch-tools/meson-0.60.3
       meson_tar=/work/.scratch-tools/meson-0.60.3.tar.gz
       mkdir -p /work/.scratch-tools
       if [ ! -f \"\$meson_tar\" ]; then
         curl -fL --retry 3 -o \"\$meson_tar\" \
           https://github.com/mesonbuild/meson/releases/download/0.60.3/meson-0.60.3.tar.gz
       fi
       echo '0aa6ef71c20cd899ebb0b202c6319e093e1df1c39fa58c94a1bb479efe630213272127346eab589948898d115d02d64f4bdffd892fbb9700884c1edf2dc6c6dc  '\"\$meson_tar\" | sha512sum -c -
       if [ ! -x \"\$meson_root/meson.py\" ]; then
         tar -xzf \"\$meson_tar\" -C /work/.scratch-tools
       fi
       ln -sf \"\$meson_root/meson.py\" /work/extras/tools/build/bin/meson
     else
       ( cd extras/tools && make .buildmeson )
     fi
     ( cd contrib && mkdir -p native && cd native && \
       ../bootstrap && VLC_FFMPEG_NO_OPENJPEG=1 \
       make -j\$(nproc) .ffmpeg .postproc .afpclient .smb2 .bluray .edge264 )
     CONTRIB_PREFIX=\$(ls -d /work/contrib/*-linux-gnu* 2>/dev/null | grep -v contrib- | head -1)
     export PKG_CONFIG_PATH=\"\$CONTRIB_PREFIX/lib/pkgconfig\${PKG_CONFIG_PATH:+:\$PKG_CONFIG_PATH}\"
     ./bootstrap
     # --disable-update-check: no integrated updater in the fork. It is
     # already configure's default, stated here so it stays off.
     # Modern FFmpeg no longer exports the VLC 3 VDPAU adapter helpers. The
     # ARM64 AppImage has no legacy libavcodec fallback, so omit that unusable
     # module just as the FFmpeg contrib omits its VDPAU pixel format.
     ./configure --disable-wayland --disable-vdpau \
                 --enable-merge-ffmpeg --enable-smb2 \
                 --disable-update-check --prefix=/usr
     make -j\$(nproc)
     # Stale AppImages from previous runs (older version strings) linger in
     # the persistent volume and would be copied out and zipped alongside
     # the fresh one: keep only what this run produces.
     rm -f /work/PowerVLC-*.AppImage
     VERSION=\"\$PVLC_VER\" BUILDDIR=/work WORKDIR=/work \
       extras/package/appimage/build-appimage.sh
     cp -v /work/PowerVLC-*.AppImage /out/"
  package_linux_zip "linux-$3" "PowerVLC-*-$3.AppImage" "$STAMP"
  rm -f "$STAMP"
}

check_linux_cross() { # check_linux_cross <amd64|i386>
  # Do not set --platform to an x86 value here: this image and both compiler
  # processes are arm64 programs.  The produced ELF alone is x86.
  docker image inspect powervlc-linux-cross-v2 >/dev/null 2>&1 || \
  docker build --platform linux/arm64 -t powervlc-linux-cross-v2 \
    -f "$DOCKER_DIR/Dockerfile.linux-cross" "$DOCKER_DIR"
  docker run --rm --platform linux/arm64 powervlc-linux-cross-v2 \
    /work/check-linux-cross.sh "$1"
}

configure_linux_cross() { # configure_linux_cross <amd64|i386>
  case "$1" in amd64) triplet=x86_64-linux-gnu; sysarch=x86_64-linux-gnu ;; i386) triplet=i686-linux-gnu; sysarch=i386-linux-gnu ;; esac
  WORK_VOL="powervlc-build-linux-cross-$1"
  docker_run linux/arm64 "$(cross_image "$1")" \
    "git config --global --add safe.directory /src
     ( cd /src && git ls-files -co --exclude-standard -z | tar --null -T - -cf - ) | tar -C /work -xf -
     mkdir -p /work/src; printf '%s\\n' \"$REVISION\" > /work/src/revision.txt
     cd /work
     sysroot=/opt/sysroots/$triplet-glibc-2.27
     contrib=/work/contrib-$triplet-glibc227
     test -f \"\$contrib/lib/pkgconfig/libavcodec.pc\"
     toolchain=/work/.toolchains/prefix/$triplet
     test -x "\$toolchain/bin/$triplet-gcc"
     export PATH="/opt/protoc-3.0/src/.libs:/opt/qt-host/bin:\$toolchain/driver-bin:\$PATH"
     export LD_LIBRARY_PATH="/opt/protoc-3.0/src/.libs:/opt/qt-host/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
     export CC="\$toolchain/driver-bin/$triplet-gcc" CXX="\$toolchain/driver-bin/$triplet-g++" AR=$triplet-ar RANLIB=$triplet-ranlib
     export CFLAGS=\"--sysroot=\$sysroot -isystem \$sysroot/usr/include/$sysarch -I\$sysroot/usr/include/freetype2 -I\$sysroot/usr/include/libxml2 -B\$toolchain/bin -B\$sysroot/usr/lib/$sysarch -L\$sysroot/usr/lib/$sysarch\" CXXFLAGS=\"--sysroot=\$sysroot -isystem \$sysroot/usr/include/$sysarch -I\$sysroot/usr/include/freetype2 -I\$sysroot/usr/include/libxml2 -B\$toolchain/bin -B\$sysroot/usr/lib/$sysarch -L\$sysroot/usr/lib/$sysarch\" LDFLAGS=\"--sysroot=\$sysroot -B\$toolchain/bin -B\$sysroot/usr/lib/$sysarch -L\$sysroot/usr/lib/$sysarch -Wl,-rpath-link,/work/cross-$1/src/.libs\"
     export PKG_CONFIG_SYSROOT_DIR=\"\$sysroot\" PKG_CONFIG_LIBDIR=\"\$contrib/lib/pkgconfig:\$sysroot/usr/lib/$sysarch/pkgconfig:\$sysroot/usr/lib/pkgconfig:\$sysroot/usr/share/pkgconfig\" PKG_CONFIG_PATH=\"\$contrib/lib/pkgconfig\"
     export MOC=/opt/qt-host/bin/moc RCC=/opt/qt-host/bin/rcc UIC=/opt/qt-host/bin/uic QMAKE=/opt/qt-host/bin/qmake
     ./bootstrap
     mkdir -p /work/cross-$1 && cd /work/cross-$1
     ../configure --host=$triplet --build=aarch64-linux-gnu --with-contrib=\"\$contrib\" --prefix=/usr \\
       --disable-wayland --enable-merge-ffmpeg --enable-smb2 --disable-update-check
     find . -name Makefile -type f -exec sed -i \"s#\$sysroot/work/contrib-$triplet-glibc227#/work/contrib-$triplet-glibc227#g\" {} \;
     sed -i \"s#-lbluray #/work/contrib-$triplet-glibc227/lib/libbluray.a #g\" modules/Makefile
     for lib in avcodec avformat avutil postproc swscale; do
       sed -i \"s#-l\$lib #/work/contrib-$triplet-glibc227/lib/lib\$lib.a #g\" modules/Makefile
     done
     # The Bionic sysroot also contains an incompatible libplacebo 0.2 shared
     # object and its -L path precedes the contrib directory. Pin the modern
     # static archive selected by configure so the DOVI renderer cannot bind
     # to the old ABI during cross-linking.
     sed -i \"s#-lplacebo #/work/contrib-$triplet-glibc227/lib/libplacebo.a #g\" modules/Makefile
     # FFmpeg 7 removed two VDPAU helper symbols still used by VLC's VDPAU
     # module. Keep modern FFmpeg for normal playback, but link that single
     # compatibility module to Bionic's libavcodec 57, which exports them.
     sed -i '/^libvdpau_avcodec_plugin_la_LIBADD =/,/^\$/ s#\$(AVCODEC_LIBS)#-Wl,/opt/sysroots/$triplet-glibc-2.27/usr/lib/$sysarch/libavcodec.so -Wl,/opt/sysroots/$triplet-glibc-2.27/usr/lib/$sysarch/libavutil.so#g' modules/Makefile
     echo \"OK: VLC configured natively for $triplet with glibc 2.27.\""
}

build_linux_cross_ffmpeg() { # build_linux_cross_ffmpeg <amd64|i386>
  case "$1" in amd64) triplet=x86_64-linux-gnu; sysarch=x86_64-linux-gnu ;; i386) triplet=i686-linux-gnu; sysarch=i386-linux-gnu ;; esac
  WORK_VOL="powervlc-build-linux-cross-$1"
  docker_run linux/arm64 "$(cross_image "$1")" \
    "git config --global --add safe.directory /src
     ( cd /src && git ls-files -co --exclude-standard -z | tar --null -T - -cf - ) | tar -C /work -xf -
     cd /work
     sysroot=/opt/sysroots/$triplet-glibc-2.27
     ( cd extras/tools && ./bootstrap && rm -rf nasm .nasm && CC=gcc CXX=g++ make .buildnasm )
     # Ubuntu 22.04 provides Meson 0.61, while the pinned libplacebo renderer
     # needs Meson 1.3. Keep the host-side build tool in the persistent volume;
     # it never becomes part of the glibc-2.27 target runtime.
     meson_root=/work/.scratch-tools/meson-1.3.2
     meson_tar=/work/.scratch-tools/meson-1.3.2.tar.gz
     mkdir -p /work/.scratch-tools
     if [ ! -f \"\$meson_tar\" ]; then
       curl -fL --retry 3 -o \"\$meson_tar\" \
         https://github.com/mesonbuild/meson/releases/download/1.3.2/meson-1.3.2.tar.gz
     fi
     echo '6369c6d64f91c769f0f4d3e2445bb3615785998489d41acba2134b44ec89abd04bd97a3d3d17c64779eb40b0bf4808e3419eb47638169446a98824d680f37a7b  '\"\$meson_tar\" | sha512sum -c -
     if [ ! -x \"\$meson_root/meson.py\" ]; then
       tar -xzf \"\$meson_tar\" -C /work/.scratch-tools
     fi
     ln -sf \"\$meson_root/meson.py\" /work/extras/tools/build/bin/meson
     export PATH=/work/extras/tools/build/bin:\$PATH
     toolchain=/work/.toolchains/prefix/$triplet
     test -x "\$toolchain/bin/$triplet-gcc"
     export PATH="\$toolchain/driver-bin:\$PATH"
     export CC="\$toolchain/driver-bin/$triplet-gcc" CXX="\$toolchain/driver-bin/$triplet-g++" AR=$triplet-ar RANLIB=$triplet-ranlib
     export CFLAGS=\"--sysroot=\$sysroot -isystem \$sysroot/usr/include/$sysarch -B\$toolchain/bin -B\$sysroot/usr/lib/$sysarch -L\$sysroot/usr/lib/$sysarch\" CXXFLAGS=\"--sysroot=\$sysroot -isystem \$sysroot/usr/include/$sysarch -B\$toolchain/bin -B\$sysroot/usr/lib/$sysarch -L\$sysroot/usr/lib/$sysarch\" LDFLAGS=\"--sysroot=\$sysroot -B\$toolchain/bin -B\$sysroot/usr/lib/$sysarch -L\$sysroot/usr/lib/$sysarch\"
     mkdir -p /work/contrib-cross-$1-glibc227 && cd /work/contrib-cross-$1-glibc227
     ../contrib/bootstrap --build=aarch64-linux-gnu --host=$triplet --prefix=../contrib-$triplet-glibc227
     # libbluray's Meson invocation intentionally isolates pkg-config.  Make
     # the Bionic fontconfig metadata visible there while keeping its matching
     # Bionic library in the sysroot.
     for pc in fontconfig expat; do
       cp "\$sysroot/usr/lib/$sysarch/pkgconfig/\$pc.pc" "../contrib-$triplet-glibc227/lib/pkgconfig/"
     done
     # Keep Bionic's fontconfig/freetype pair, but build libbluray itself: VLC
     # uses a non-public libbluray header not shipped by Ubuntu's -dev package.
     touch .fontconfig .dep-fontconfig
     # The 64-bit OpenGL output uses current libplacebo for Dolby Vision RPU
     # mapping.  It used to be omitted from this reduced contrib target, which
     # silently configured the AppImage with only VLC's legacy SDR shader path.
     make -j\$(nproc) .ffmpeg .postproc .afpclient .smb2 .bluray .libplacebo .edge264
     test -f ../contrib-$triplet-glibc227/lib/pkgconfig/libavcodec.pc
     echo \"OK: FFmpeg contrib built natively for $triplet.\""
}

build_linux_cross_core() { # build_linux_cross_core <amd64|i386>
  WORK_VOL="powervlc-build-linux-cross-$1"
  docker_run linux/arm64 "$(cross_image "$1")" \
    "export PATH=/opt/protoc-3.0/src/.libs:/opt/qt-host/bin:\$PATH
     export LD_LIBRARY_PATH=/opt/protoc-3.0/src/.libs:/opt/qt-host/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}
     test -f /work/cross-$1/config.status
     make -C /work/cross-$1/modules stream_out/chromecast/3.0/cast_channel.pb.cc
     find /work/cross-$1/modules/stream_out/chromecast -name '*.pb.cc' -exec sed -i 's/::google::protobuf::internal::NewPermanentCallback/::google::protobuf::NewPermanentCallback/g' {} \;
     make -C /work/cross-$1 -j\$(nproc)
     echo \"OK: VLC core built natively for $1.\""
}

build_linux_cross_appimage() { # build_linux_cross_appimage <amd64|i386>
  case "$1" in amd64) label=x86_64 ;; i386) label=i386 ;; esac
  # Keep the cross path's release layout identical to the native Linux path:
  # the raw AppImage is useful locally and the versioned ZIP is what the
  # release collector picks up.  The stamp also prevents stale artifacts in
  # the persistent cross volume from being folded into a new release archive.
  STAMP=$(mktemp)
  build_legacy_cross_toolchain "$1"
  build_linux_cross_ffmpeg "$1"
  configure_linux_cross "$1"
  build_linux_cross_core "$1"
  WORK_VOL="powervlc-build-linux-cross-$1"
  docker_run linux/arm64 "$(cross_image "$1")" \
    "sh /src/extras/package/docker/package-cross-appimage.sh $1
     cp -v /work/PowerVLC-\$PVLC_VER-$label.AppImage /out/"
  package_linux_zip "linux-$label" "PowerVLC-*-$label.AppImage" "$STAMP"
  rm -f "$STAMP"
}

build_legacy_cross_toolchain() { # build_legacy_cross_toolchain <amd64|i386>
  WORK_VOL="powervlc-build-linux-cross-$1"
  docker run --rm --platform linux/arm64 --entrypoint /bin/sh \
    -v "$REPO":/src:ro -v "${WORK_VOL}":/work \
    powervlc-linux-cross-v13 -eu -c "sh /src/extras/package/docker/build-legacy-gcc.sh $1"
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
    linux-amd64-appimage) build_linux_cross_appimage amd64 ;;
    linux-i386-appimage)  build_linux_cross_appimage i386 ;;
    linux-amd64-cross-check) check_linux_cross amd64 ;;
    linux-i386-cross-check)  check_linux_cross i386 ;;
    linux-amd64-cross-configure) configure_linux_cross amd64 ;;
    linux-i386-cross-configure)  configure_linux_cross i386 ;;
    linux-amd64-cross-ffmpeg) build_linux_cross_ffmpeg amd64 ;;
    linux-i386-cross-ffmpeg)  build_linux_cross_ffmpeg i386 ;;
    linux-amd64-cross-build) build_linux_cross_core amd64 ;;
    linux-i386-cross-build)  build_linux_cross_core i386 ;;
    linux-amd64-cross-toolchain) build_legacy_cross_toolchain amd64 ;;
    linux-i386-cross-toolchain)  build_legacy_cross_toolchain i386 ;;
    *) echo "unknown target: $TARGET"; exit 1 ;;
  esac
done

echo
echo "Done. Artifacts in: $OUT"
ls -la "$OUT"
