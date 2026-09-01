#!/bin/sh
# PowerVLC — Qt interface bench under Xvfb (see Dockerfile.qtbench).
#
#   qt-bench.sh build      build/refresh the image, sync the tree, compile
#   qt-bench.sh up         start the bench container + Xvfb (detached)
#   qt-bench.sh run <cmd>  run a shell command inside the bench
#   qt-bench.sh play <media> [opts]   start PowerVLC on that media, detached
#   qt-bench.sh library-db <db> <source-root> [compact-index]
#                                install a real large library cache
#   qt-bench.sh library          start PowerVLC against that cache
#   qt-bench.sh shot <name>           screenshot the X display into out/
#   qt-bench.sh stop       kill the running PowerVLC
#   qt-bench.sh down       remove the container (the build volume survives)
#
# The container keeps running between calls, so a campaign is a sequence of
# `run`/`shot` invocations against one live interface.
#
# PowerVLC is an unofficial fork of VLC, not affiliated with VideoLAN.
set -eu

DOCKER_DIR=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$DOCKER_DIR/../../.." && pwd)
OUT="$DOCKER_DIR/out/qtbench"
IMAGE=powervlc-qtbench
VOL=powervlc-qtbench
NAME=powervlc-qtbench
PLATFORM=linux/arm64
SCREEN=${PVLC_BENCH_SCREEN:-1280x800x24}

mkdir -p "$OUT"

image_build() {
  docker image inspect "$IMAGE" >/dev/null 2>&1 || \
    docker build --platform "$PLATFORM" -t "$IMAGE" \
      -f "$DOCKER_DIR/Dockerfile.qtbench" "$DOCKER_DIR"
}

# Same clean snapshot as build-in-docker.sh: tracked + untracked files, no
# build directories, plus the compiled catalogues (gitignored, and gettext
# would not regenerate them inside the container).
sync_tree() {
  REVISION=$(cd "$REPO" && git describe --tags --always 2>/dev/null || echo unknown)
  docker run --rm --platform "$PLATFORM" \
    -v "$REPO":/src:ro -v "$VOL":/work -e "REVISION=$REVISION" "$IMAGE" sh -eu -c '
      git config --global --add safe.directory /src
      cd /src && git ls-files -co --exclude-standard > /tmp/files.txt
      rsync -a --delete-excluded --files-from=/tmp/files.txt /src/ /work/
      ( cd /src && ls po/*.gmo 2>/dev/null | while read -r f; do
          cp -p "$f" "/work/$f"; done ) || true
      echo "$REVISION" > /work/src/revision.txt'
}

case "${1:-}" in
  build)
    image_build
    sync_tree
    docker run --rm --platform "$PLATFORM" -v "$VOL":/work "$IMAGE" sh -eu -c '
      cd /work
      # Regenerate configure every time: this bench deliberately builds the
      # current dirty tree, whose configure.ac/Makefile.am may have changed.
      ./bootstrap
      mkdir -p contrib/qtbench-native
      ( cd contrib/qtbench-native
        [ -f Makefile ] || ../bootstrap --prefix=/work/qtbench-afp-prefix
        if pkg-config --exists libbsd \
           && [ -f afpclient/build/build.ninja ] \
           && ! grep -q HAVE_LIBBSD afpclient/build/build.ninja; then
          rm -f .afpclient
          rm -rf afpclient/build
        fi
        make -j"$(nproc)" .afpclient )
      export PKG_CONFIG_PATH=/work/qtbench-afp-prefix/lib/pkgconfig${PKG_CONFIG_PATH:+:$PKG_CONFIG_PATH}
      ./configure --disable-wayland --disable-update-check \
          --prefix=/usr --enable-lua --enable-qt --enable-gpod --disable-bluray
      make -j"$(nproc)"
      rm -rf qtbench-data
      mkdir -p qtbench-data/lua
      rsync -a --include="*/" --include="*.luac" --exclude="*" \
          share/lua/ qtbench-data/lua/
      rsync -a share/retroarch-shaders/ qtbench-data/retroarch-shaders/
      chmod -R a+rX qtbench-data
      echo "bench build done: $(ls -la bin/.libs/powervlc | head -1)"'
    ;;
  up)
    image_build
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    docker run -d --name "$NAME" --platform "$PLATFORM" \
      -v "$VOL":/work -v "$OUT":/out --shm-size=512m "$IMAGE" \
      sh -c "su bench -c 'Xvfb :99 -screen 0 $SCREEN -nolisten tcp' & sleep 3; \
             su bench -c 'DISPLAY=:99 openbox' & sleep 2; \
             su bench -c 'DISPLAY=:99 xsetroot -solid grey'; exec tail -f /dev/null"
    sleep 3
    docker exec "$NAME" sh -c 'DISPLAY=:99 xdpyinfo | head -3'
    ;;
  run)
    shift
    docker exec -u bench -e DISPLAY=:99 -e HOME=/home/bench "$NAME" sh -c "$*"
    ;;
  play)
    shift
    media=$1; shift || true
    docker exec -d -u bench -e DISPLAY=:99 -e HOME=/home/bench "$NAME" sh -c \
      "cd /work && LD_LIBRARY_PATH=/work/lib/.libs:/work/src/.libs \
       VLC_PLUGIN_PATH=/work/modules VLC_DATA_PATH=/work/qtbench-data \
       ./bin/.libs/powervlc --no-plugins-cache -vv --file-logging \
         --logfile=/out/bench.log $* '$media' >/dev/null 2>&1"
    ;;
  library-db)
    shift
    db=${1:?library database path required}
    source_root=${2:?canonical source root required}
    compact_index=${3:-}
    [ -f "$db" ] || { echo "missing database: $db" >&2; exit 1; }
    hash=$(python3 - "$source_root" <<'PY'
import sys
h = 1469598103934665603
for byte in sys.argv[1].encode("utf-8"):
    h ^= byte
    h = (h * 1099511628211) & ((1 << 64) - 1)
print(f"{h:016x}")
PY
    )
    docker exec "$NAME" sh -eu -c '
      mkdir -p /work/qtbench-large/managed/.powervlc-cache
      mkdir -p /home/bench/.config/powervlc /home/bench/.config/pulse
      mkdir -p /home/bench/.local/share/powervlc/powervlc-media-index
      chown -R bench:bench /work/qtbench-large /home/bench/.config/powervlc \
        /home/bench/.local/share/powervlc'
    docker cp "$db" "$NAME:/work/qtbench-large/managed/.powervlc-cache/$hash.db"
    if [ -n "$compact_index" ]; then
      [ -f "$compact_index" ] || {
        echo "missing compact index: $compact_index" >&2; exit 1;
      }
      docker cp "$compact_index" \
        "$NAME:/home/bench/.local/share/powervlc/powervlc-media-index/music-index.pvli"
    else
      docker exec "$NAME" rm -f \
        /home/bench/.local/share/powervlc/powervlc-media-index/music-index.pvli \
        /home/bench/.local/share/powervlc/powervlc-media-index/music-index.pvli.tmp
    fi
    docker exec -e PVLC_SOURCE_ROOT="$source_root" "$NAME" sh -eu -c '
      config=/home/bench/.config/powervlc/powervlcrc
      sed -i "/^powervlc-ml-managed-folder=/d;/^powervlc-ml-folders=/d" \
        "$config" 2>/dev/null || true
      printf "powervlc-ml-managed-folder=/work/qtbench-large/managed\n" >>"$config"
      printf "powervlc-ml-folders=m\t%s\n" "$PVLC_SOURCE_ROOT" >>"$config"
      chown -R bench:bench /work/qtbench-large /home/bench/.config/powervlc \
        /home/bench/.local/share/powervlc'
    echo "installed $db as cache for $source_root ($hash.db)"
    ;;
  library)
    docker exec "$NAME" sh -c 'pkill -f bin/.libs/powervlc || true' || true
    docker exec "$NAME" rm -f /out/library-bench.log /out/library-stdout.log
    # Keep runtime and temporary files on the host bind mount. Long-running
    # benchmark campaigns must not fail merely because Docker Desktop's
    # internal build disk is full while the host still has ample space.
    docker exec "$NAME" sh -eu -c '
      mkdir -p /work/qtbench-runtime /out/tmp-bench
      chown bench:bench /work/qtbench-runtime
      chmod 700 /work/qtbench-runtime
      chmod 777 /out/tmp-bench'
    docker exec -d -u bench -e DISPLAY=:99 -e HOME=/home/bench \
      -e XDG_RUNTIME_DIR=/work/qtbench-runtime -e TMPDIR=/out/tmp-bench \
      "$NAME" sh -c \
      'cd /work && LD_LIBRARY_PATH=/work/lib/.libs:/work/src/.libs \
       VLC_PLUGIN_PATH=/work/modules VLC_DATA_PATH=/work/qtbench-data \
       ./bin/.libs/powervlc --no-plugins-cache --no-qt-privacy-ask -vv \
         --file-logging --logfile=/out/library-bench.log \
         >/out/library-stdout.log 2>&1'
    ;;
  shot)
    shift
    docker exec -u bench -e DISPLAY=:99 "$NAME" sh -c "import -window root /out/$1.png"
    ;;
  stop)
    docker exec "$NAME" sh -c 'pkill -f bin/.libs/powervlc || true'
    ;;
  down)
    docker rm -f "$NAME" >/dev/null 2>&1 || true
    ;;
  *)
    sed -n '2,20p' "$0"
    exit 1
    ;;
esac
