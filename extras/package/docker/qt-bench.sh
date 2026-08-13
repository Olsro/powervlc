#!/bin/sh
# PowerVLC — Qt interface bench under Xvfb (see Dockerfile.qtbench).
#
#   qt-bench.sh build      build/refresh the image, sync the tree, compile
#   qt-bench.sh up         start the bench container + Xvfb (detached)
#   qt-bench.sh run <cmd>  run a shell command inside the bench
#   qt-bench.sh play <media> [opts]   start PowerVLC on that media, detached
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
      [ -f configure ] || ./bootstrap
      [ -f config.status ] || ./configure --disable-wayland --disable-update-check \
          --prefix=/usr --disable-lua --enable-qt
      make -j"$(nproc)"
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
       VLC_PLUGIN_PATH=/work/modules \
       ./bin/.libs/powervlc --no-plugins-cache -vv --file-logging \
         --logfile=/out/bench.log $* '$media' >/dev/null 2>&1"
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
