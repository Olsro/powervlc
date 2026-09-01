#!/bin/sh
# Build a minimal Ubuntu 18.04 (glibc 2.27) sysroot without ever executing its
# x86 programs.  dpkg-deb only unpacks archives, so this stays native on arm64.
set -eu

arch="$1"
case "$arch" in
  amd64) triplet=x86_64-linux-gnu; sysarch=x86_64-linux-gnu ;;
  i386)  triplet=i686-linux-gnu; sysarch=i386-linux-gnu ;;
  *) echo "Usage: $0 amd64|i386" >&2; exit 64 ;;
esac

# Bionic's base archive remains on the primary archive; only later updates
# moved away.  Keeping this at the frozen base release is intentional.
base=https://archive.ubuntu.com/ubuntu
index=/tmp/bionic-${arch}-Packages.gz
universe_index=/tmp/bionic-${arch}-universe-Packages.gz
multiverse_index=/tmp/bionic-${arch}-multiverse-Packages.gz
plain_index=/tmp/bionic-${arch}-Packages
root=/opt/sysroots/${triplet}-glibc-2.27
mkdir -p "$root" /tmp/bionic-debs
curl -fsSL "$base/dists/bionic/main/binary-$arch/Packages.gz" -o "$index"
curl -fsSL "$base/dists/bionic/universe/binary-$arch/Packages.gz" -o "$universe_index"
curl -fsSL "$base/dists/bionic/multiverse/binary-$arch/Packages.gz" -o "$multiverse_index"
gzip -cd "$index" "$universe_index" "$multiverse_index" > "$plain_index"

package_field() { # package_field <package> <field>
  awk -v want="$1" -v field="$2" 'BEGIN { RS=""; FS="\n" }
    $1 == "Package: " want {
      for (i = 1; i <= NF; i++) if ($i ~ ("^" field ": ")) {
        sub("^" field ": ", "", $i); value=$i
        for (j = i + 1; j <= NF && $j ~ /^ /; j++) value=value " " substr($j, 2)
        print value; exit
      }
    }' "$plain_index"
}

package_url() { package_field "$1" Filename; }

# Keep the cross build feature-equivalent to the native Bionic/arm64 build.
# The native Dockerfile calls `apt-get build-dep vlc`; here we read the same
# source package metadata and only unpack the target .deb archives.
vlc_build_deps() {
  sources=/tmp/bionic-universe-Sources.gz
  curl -fsSL "$base/dists/bionic/universe/source/Sources.gz" -o "$sources"
  gzip -cd "$sources" |
    awk 'BEGIN { RS=""; FS="\n" }
      $1 == "Package: vlc" {
        for (i = 1; i <= NF; i++) if ($i ~ /^Build-Depends:/) {
          sub(/^Build-Depends: /, "", $i); print $i
          for (j = i + 1; j <= NF && $j ~ /^ /; j++) print substr($j, 2)
          exit
        }
      }' | tr ',' '\n'
}

# Resolve the target Qt5 development closure from Bionic's Packages files. We
# extract archives only; their x86 tools are never run. Alternatives choose the
# first package that actually exists in this architecture's index.
resolve_packages() { # roots are passed as arguments
  wanted=/tmp/bionic-${arch}-wanted
  printf '%s\n' "$@" | sort -u > "$wanted"
  while :; do
    before="$(wc -l < "$wanted")"
    while IFS= read -r pkg; do
      package_field "$pkg" Pre-Depends
      package_field "$pkg" Depends
    done < "$wanted" | tr ',' '\n' | sort -u | while IFS= read -r atom; do
      alternatives="$(printf '%s' "$atom" | sed -E 's/\([^)]*\)//g; s/\[[^]]*\]//g; s/<[^>]*>//g; s/:any|:native//g')"
      oldifs=$IFS; IFS='|'
      for candidate in $alternatives; do
        candidate="$(printf '%s' "$candidate" | tr -d ' ' )"
        [ -n "$candidate" ] || continue
        if [ -n "$(package_url "$candidate")" ]; then
          printf '%s\n' "$candidate" >> "$wanted"
          break
        fi
      done
      IFS=$oldifs
    done
    sort -u "$wanted" -o "$wanted"
    [ "$(wc -l < "$wanted")" -eq "$before" ] && break
  done
  cat "$wanted"
}

# These packages provide the loader, C headers, crt objects and kernel UAPI
# headers.  The cross compiler brings libgcc/libstdc++ itself.
roots=/tmp/bionic-${arch}-roots
{ printf '%s\n' libc6 libc6-dev linux-libc-dev libsidplay2-dev libupnp-dev; vlc_build_deps; } |
    tr '|' '\n' | sed -E 's/\([^)]*\)//g; s/\[[^]]*\]//g; s/<[^>]*>//g; s/:any|:native//g' |
    awk '{ gsub(/^[[:space:]]+|[[:space:]]+$/, ""); if ($0 != "") print }' > "$roots"

for pkg in $(resolve_packages $(cat "$roots")); do
  path="$(package_url "$pkg")"
  [ -n "$path" ] || { echo "Missing $pkg:$arch in bionic" >&2; exit 1; }
  deb=/tmp/bionic-debs/"${path##*/}"
  curl -fsSL "$base/$path" -o "$deb"
  dpkg-deb -x "$deb" "$root"
done

# Packages record development-library symlinks as absolute paths (for example
# /lib/x86_64-linux-gnu/libdl.so.2).  Absolute links escape a sysroot when ld
# opens them, so turn them into equivalent relative links before GCC sees it.
find "$root" -type l -lname '/*' -print | while IFS= read -r link; do
  target="$(readlink "$link")"
  relative="$(realpath --relative-to="$(dirname "$link")" "$root$target")"
  ln -sfn "$relative" "$link"
done

# GCC expects target headers/libraries below /usr/<triplet>; Debian's cross
# compiler finds the canonical paths once they are exposed there.
mkdir -p "$root/usr/$triplet"
ln -sfn ../include "$root/usr/$triplet/include"
ln -sfn ../lib "$root/usr/$triplet/lib"

# glibc's architecture-specific headers are installed in Debian's multiarch
# directory.  A GCC configured with /usr/include as its native target header
# directory still includes <bits/...> relative to /usr/include, so make those
# headers visible at the canonical location inside the sysroot.
for directory in asm bits gnu sys; do
  if [ -d "$root/usr/include/$sysarch/$directory" ]; then
    ln -sfn "$sysarch/$directory" "$root/usr/include/$directory"
  fi
done

# Likewise, GCC's generic x86 linker specs probe /lib and /usr/lib before the
# Debian multiarch directories.  Expose only links to the Bionic objects and
# linker scripts already in this sysroot; this must never fall back to host
# libraries.
for directory in lib usr/lib; do
  multiarch="$root/$directory/$sysarch"
  [ -d "$multiarch" ] || continue
  find "$multiarch" -mindepth 1 -maxdepth 1 \( -type f -o -type l \) -print |
    while IFS= read -r file; do
      name="${file##*/}"
      ln -sfn "$sysarch/$name" "$root/$directory/$name"
    done
done
printf '%s\n' "glibc=2.27" > "$root/.powervlc-sysroot"
