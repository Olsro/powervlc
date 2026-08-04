# Building PowerVLC

PowerVLC ships as **one universal application bundle** that runs on everything
from a PowerPC G3 on Mac OS X 10.4 "Tiger" up to a current Apple‑Silicon Mac.
To make that possible the app is built **once per CPU target** and the results
are then fused into a single fat `PowerVLC.app`.

The seven targets:

| Target  | CPU / machine                         | Min. macOS | Interface        |
|---------|---------------------------------------|------------|------------------|
| `g3`    | PowerPC G3 (750), no AltiVec          | 10.4       | legacy only      |
| `g4`    | PowerPC G4 (7400) + AltiVec           | 10.4       | legacy only      |
| `g4e`   | PowerPC G4e (7448/7450) + AltiVec     | 10.4       | legacy only      |
| `g5`    | PowerPC G5 (970) + AltiVec            | 10.4       | legacy only      |
| `x86`   | Intel 32‑bit                          | 10.4       | legacy only      |
| `x64`   | Intel 64‑bit                          | 10.6*      | legacy + modern  |
| `arm64` | Apple Silicon                         | 11.0       | legacy + modern  |

\*The 64‑bit Intel slice is gated at 10.6 on purpose so that a 10.5 Intel Mac
picks the `x86` slice instead (see the comments in `make-universal.sh`).

All the scripts below live in `extras/package/macosx/` and are run **from the
repository root**.

## Requirements
All these instructions were tested using an Apple Silicon Mac running Sequoia 15.7.7.
Your results may vary if you use anything different.

The macOS bundle needs the tools in section 1. The **Windows and Linux** builds
instead run inside a container — see **section 6** — and their only extra
prerequisite is **Docker Desktop** or **Rancher Desktop**.

---

## TL;DR — regenerate the whole release

Once the machine is set up (section 1), from the repo root:

```bash
# 1. Build every architecture (each writes build<target>/PowerVLC.app)
for t in g3 g4 g4e g5 x86 x64 arm64; do
    extras/package/macosx/build-powervlc.sh "$t" || break
done

# 2. Fuse them into one universal bundle (order matters — see section 3)
extras/package/macosx/make-universal.sh builduniversal/PowerVLC.app \
    buildarm64/PowerVLC.app buildx64/PowerVLC.app buildx86/PowerVLC.app \
    buildg3/PowerVLC.app  buildg4/PowerVLC.app  buildg4e/PowerVLC.app \
    buildg5/PowerVLC.app

# 3. Make the zips (one per target + the universal one)
for t in g3 g4 g4e g5 x86 x64 arm64 universal; do
    extras/package/macosx/package-powervlc.sh "$t"
done

# 4. Build Windows and Linux releases (amd64 and i386 will be slow to build, be patient)
extras/package/docker/build-in-docker.sh win64 win32 winarm64 linux-arm64-appimage linux-amd64-appimage linux-i386-appimage

# 5. Move all the generated zips to the "zips" folder in the root of the project
./collect-zips.sh
```

The first full build is slow (it compiles the third‑party libraries — the
"contribs"). Every later build is **incremental** and only recompiles what
changed, so re‑running the loop after a source edit takes minutes, not hours.

---

## 1. One‑time setup (starting from scratch on an Apple‑Silicon Mac)

This is what a fresh Mac like an M‑series MacBook needs before it can build
PowerVLC.

### 1.1 Xcode and its command‑line tools

Install Xcode from the App Store, then:

```bash
xcode-select --install
sudo xcodebuild -license accept
```

This provides `clang`, `lipo`, `codesign`, `xcrun` and the current macOS SDK —
everything needed for the `x64` and `arm64` slices.

### 1.2 Homebrew helpers

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
brew install nasm gettext autoconf automake libtool pkg-config
```

- **nasm** assembles the Intel (x86) assembly in ffmpeg — without it the 32‑bit
  Intel decoder is much slower.
- **gettext** provides `msgfmt`, used to compile the translations (section 5.2).
- The autotools are used to (re)generate `configure` when needed.

### 1.3 The legacy cross‑toolchain (for the PowerPC and Intel‑32 slices)

Modern clang can no longer target PowerPC or 10.4‑era Intel, so those five
slices (`g3 g4 g4e g5 x86`) are built with a **home‑made GCC cross‑toolchain**.
The build scripts look for it at:

```
$HOME/Projects/darwin-legacy-toolchain
```

(override with the `VLC_LEGACY_TOOLCHAIN` environment variable). It must contain:

```
darwin-legacy-toolchain/
├── opt/
│   ├── gcc-ppc-tiger/     # FSF GCC 13 → powerpc-apple-darwin8  (bin/tiger-cc, tiger-c++, legacy-luac)
│   ├── gcc-i686-tiger/    # FSF GCC 13 → i686-apple-darwin8     (bin/tiger-cc, tiger-c++)
│   └── xtools/            # darwin cctools: ld, lipo, install_name_tool, ar, nm, otool, strip…
└── sdks/
    ├── MacOSX10.4u.sdk/   # Tiger universal SDK (PPC + i386)
    └── MacOSX10.5.sdk/    # Leopard SDK (used by the reference i686-leopard target)
```

The toolchain itself is a separate project (FSF **GCC 13** + Apple's
**cctools/ld64** "darwin‑xtools", built for the `powerpc-apple-darwin8` and
`i686-apple-darwin8` triples) plus the two old SDKs extracted from the Xcode 3
installers. Building it is a one‑time effort; once the folder above exists, you
never touch it again. If you only care about the modern `x64`/`arm64` slices you
can skip this step and just build those two targets.

**Building that toolchain from scratch is documented in [section 7](#7-appendix--building-the-legacy-cross-toolchain-from-scratch)** —
sources, the four patches it needs, the exact `configure`/`cmake` lines and the
hand‑written wrapper scripts.

### 1.4 First build

Nothing else is required: the very first `build-powervlc.sh <target>` run will
fetch/compile the contribs into `contrib/<triple>/` automatically. That output
is cached, so it only happens once per target family.

---

## 2. Build one architecture

```bash
extras/package/macosx/build-powervlc.sh <target>     # target ∈ g3 g4 g4e g5 x86 x64 arm64
```

Result: `build<target>/PowerVLC.app`.

The script picks the right compiler, SDK, minimum‑OS and CPU tuning for the
target and applies the PowerVLC configure policy (see the comments at the top of
the script). Useful extra flags, passed straight through to the underlying
`build.sh`:

- `-r` — rebuild everything from scratch, **including the contribs** (use after
  changing a contrib recipe such as `contrib/src/ffmpeg/rules.mak`).
- `-c` — recompile only the contribs from source.
- no flag — **incremental**: recompile just the changed VLC objects and relink.

Example — rebuild only the G4 slice after editing an interface file:

```bash
extras/package/macosx/build-powervlc.sh g4
```

---

## 3. Merge into a universal bundle

```bash
extras/package/macosx/make-universal.sh <output.app> <input1.app> [input2.app …]
```

Every file that several inputs share is `lipo`‑merged when it is a Mach‑O;
otherwise the copy from the **first** input wins. So **list the preferred bundle
first** — the Info.plist, icon and any single‑arch resources are taken from it:

```bash
extras/package/macosx/make-universal.sh builduniversal/PowerVLC.app \
    buildarm64/PowerVLC.app buildx64/PowerVLC.app buildx86/PowerVLC.app \
    buildg3/PowerVLC.app  buildg4/PowerVLC.app  buildg4e/PowerVLC.app \
    buildg5/PowerVLC.app
```

The script also:

- relaxes the launch gate so a 10.4 Mac accepts the bundle (per‑arch minimums);
- installs a tiny **architecture trampoline** so old 32‑bit Macs don't try to
  run (and crash on) a 64‑bit slice;
- ships portable Lua and ad‑hoc code‑signs the result (needed for the arm64
  slice to load on Apple Silicon).

Result: `builduniversal/PowerVLC.app`.

---

## 4. Make the zips

```bash
extras/package/macosx/package-powervlc.sh <target>   # target ∈ g3 … arm64 OR universal
```

It reads the version from the bundle's Info.plist and writes
`build<target>/powervlc-<version>-mac-<target>.zip` next to the bundle
(`builduniversal/powervlc-<version>-mac-universal.zip` for the universal one).
The `mac` tag is there because the macOS target names (`g5`, `x64`, `universal`…)
don't say which platform they belong to, unlike `win64` or `linux-x86_64`.

---

## 5. Notes & gotchas

### 5.1 Incremental builds and shared state
`build.sh` rebuilds the shared `extras/tools` on every run, so **do not run two
`build-powervlc.sh` invocations in parallel** — build the targets one after
another.

### 5.1b Forcing a contrib to rebuild after you change its patches

Without `-c`, `build-powervlc.sh` treats an **existing contrib prefix as
complete** and rebuilds nothing in it. Add a patch under `contrib/src/<pkg>/`
and every later build will keep linking the old library — and still report
success, with no message of any kind. `make list` even prints the package under
"To-be-built packages", which is what makes this so easy to believe.

Deleting the stamp and the unpacked source is **not** enough. `rules.mak` asks
`need_pkg`, which runs `pkg-config` against the **installed prefix**; as long as
the `.pc` files are there the package counts as found and is skipped. All three
have to go:

```bash
# example: ffmpeg for the G3 (jaguar) prefix
rm -f  contrib/contrib-powerpc-apple-darwin8-jaguar/.ffmpeg
rm -rf contrib/contrib-powerpc-apple-darwin8-jaguar/ffmpeg
find contrib/powerpc-apple-darwin8-jaguar/lib/pkgconfig -maxdepth 1 \
     \( -name 'libav*' -o -name 'libswscale*' -o -name 'libpostproc*' \) -delete
```

Then check the result rather than the exit status — `ls -la
contrib/<triple>/lib/libavcodec.a` must have a new timestamp, and the unpacked
tree must contain your patch.

`build.sh` asks for `.bluray`, `.aacs` and `.ffmpeg` by name for this reason
(they carry local patches); they are one `stat` each once their stamps are
current. A contrib you patch and do *not* add to that list has the same problem.

Note for zsh users: `rm -f dir/libav*.pc.orig` **aborts the whole command** when
the glob matches nothing ("no matches found"), so a cleanup line like the above
can silently stop half way. Use `find … -delete`.

### 5.2 Translations (`.po` → `.gmo`) — two traps
Editing a `po/<lang>.po` file does **not** by itself update the app. Regenerate
the compiled catalog by hand:

```bash
msgfmt po/fr.po -o po/fr.gmo
```

And then **check it actually reached the bundles**: an *incremental* build often
does not re-install the catalog, leaving the old strings in the app. Copy it in
explicitly after building, for every target you package:

```bash
for a in g3 g4 g4e g5 x86 x64 arm64; do
    cp po/fr.gmo "build$a/PowerVLC.app/Contents/MacOS/share/locale/fr/LC_MESSAGES/vlc.mo"
done
```

Verify with `md5 po/fr.gmo build*/PowerVLC.app/Contents/MacOS/share/locale/fr/LC_MESSAGES/vlc.mo`
(they must all match). Note that `strings` on a `.mo` splits at non-ASCII bytes,
so grepping for an accented word gives a false negative — use `msgunfmt` instead.
Do this **before** `make-universal.sh`, since the universal bundle takes
non-Mach-O files from its first input.

### 5.3 Which slices carry which interface
The PowerPC and Intel‑32 targets are built with `--disable-macosx` (the modern
Cocoa interface needs 10.7+, which never ran there), so they contain only the
**legacy** interface. `x64`/`arm64` carry both and switch at runtime.

### 5.4 Verifying a bundle
```bash
lipo -archs builduniversal/PowerVLC.app/Contents/MacOS/PowerVLC   # list the fused slices
```

### 5.5 libaacs — the one contrib built as a shared library
Blu-ray discs from a shop are scrambled with AACS, and `libbluray` does not link
against the library that unscrambles them: it `dlopen()`s `libaacs` by plain
name at runtime. So `contrib/src/aacs` is built `--enable-shared` (every other
contrib is static) and the result is copied into the player:

| target  | destination                            |
|---------|----------------------------------------|
| macOS   | `PowerVLC.app/Contents/MacOS/lib/libaacs.dylib` |
| Windows | next to `powervlc.exe`, as `libaacs.dll` |
| Linux   | `usr/lib/libaacs.so.0` in the AppImage                |

`bluray.c` points `$LIBAACS_PATH` at that copy, because a bundle is on no
library search path. Check it with `-vv`: *"using bundled AACS library …"*.

Packaging **fails** if the Blu-ray plugin is there and `libaacs` is not — better
a broken build than a player that cannot read a retail disc. `build.sh` builds
the target on its own when the contrib prefix predates it (prefixes are not
rebuilt unless you pass `-c`), so no manual step is normally needed; to force
it:

```bash
make -C contrib/contrib-aarch64-apple-darwin24 .aacs
```

libaacs used to generate its key-database parser at build time, which made
**flex and bison** a build requirement; since 0.12.0 the tarball ships the
generated lexer and parser and neither tool is needed (Xcode's command line
tools provide both anyway, and the Docker images already install them).

No keys are shipped — that is the user's business. PowerVLC only makes
installing them painless: opening a `keydb.cfg` file offers to import it into
`<config dir>/aacs/KEYDB.cfg`, which is where libaacs looks (see
`modules/demux/keydb.c`).

---

## 6. Windows & Linux builds (via Docker)

The Windows installers and the Linux packages are **cross‑built inside a
container**, so the same Apple‑Silicon Mac that builds the macOS bundle can
produce them too — no second machine needed. All artifacts land in
`extras/package/docker/out/` (git‑ignored).

### 6.1 Requirement — Docker or Rancher Desktop

Install and start **Docker Desktop** *or* **Rancher Desktop** (with its
`dockerd`/moby backend, so the `docker` CLI is available). That is the only extra
prerequisite: the build images install their own toolchains automatically
(mingw‑w64 + llvm‑mingw + NSIS for Windows, Qt5 + linuxdeploy for Linux). On
Apple Silicon:

- **Windows** targets are *cross‑compiled*, so the compiler runs **natively** on
  arm64 and merely emits Windows binaries → fast, including the ARM64‑Windows one.
- **Linux arm64** is native → fast.
- **Linux amd64 / i386** run under QEMU emulation → correct but **slow** (hours).

### 6.2 Quick command — the fast, native targets

From the repository root:

```bash
extras/package/docker/build-in-docker.sh win64 win32 winarm64 linux-arm64-appimage
```

Produces in `extras/package/docker/out/`:
`PowerVLC-<ver>-win64.exe`, `-win32.exe`, `-winarm64.exe` and
`PowerVLC-<ver>-aarch64.AppImage` (`<ver>` is the PowerVLC version, e.g. `1.0.0`),
**plus the zips** — one per Linux target, **two per Windows target** (installer
and portable) — see 6.4.

Floors match VLC 3.0: win32 → Windows XP SP3, win64 → Vista, winarm64 → Windows 10.

### 6.3 Slow command — emulated Linux (run separately)

The 64‑bit and 32‑bit **x86 Linux** AppImages compile under QEMU emulation and
can take **hours**, so run them on their own when you have the time:

```bash
extras/package/docker/build-in-docker.sh linux-amd64-appimage linux-i386-appimage
```

Every Linux target is an AppImage (see the note on snap below).

### 6.4 Zips (same convention as the macOS bundles)

Each target is zipped automatically at the end of its build, next to the raw
artifact, following the naming of section 4:

```
extras/package/docker/out/powervlc-<version>-<label>.zip
```

| Build target | Zip(s) |
|---|---|
| `win32` / `win64` / `winarm64` | `powervlc-<ver>-win32-nsis.zip` **and** `powervlc-<ver>-win32-portable.zip` … |
| `linux-arm64-appimage` | `powervlc-<ver>-linux-aarch64.zip` |
| `linux-amd64-appimage` | `powervlc-<ver>-linux-x86_64.zip` |
| `linux-i386-appimage` | `powervlc-<ver>-linux-i386.zip` |

The Linux labels carry the **AppImage architecture**, not the Docker platform
name, so the zip and the file it contains agree.

The raw `.exe` / `.AppImage` is **kept** alongside its zip: that is the file you
run locally, the zip is the one you hand out. Zipping is deliberately
never fatal — a missing `zip` binary or an unexpected artifact name warns and
moves on rather than discarding a build that can take hours under emulation.

#### The two Windows archives

One build, two deliverables, from the same `-i r` run of
`extras/package/win32/build.sh`:

| Archive | Contains | Where the settings go |
|---|---|---|
| `powervlc-<ver>-<arch>-nsis.zip` | `PowerVLC-<ver>-<arch>.exe`, the NSIS installer | `%APPDATA%\powervlc` |
| `powervlc-<ver>-<arch>-portable.zip` | the folder `PowerVLC-<ver>-<arch>-portable/`, ready to run | next to `powervlc.exe`, in `portable/` |

Portable mode is **not a separate build**: the binaries are byte-for-byte the
ones in the installer. VLC's core already implements it —
`config_GetAppDir()` in `src/win32/dirs.c` looks for a folder named `portable`
next to `powervlc.exe`, and redirects the configuration, the plugin cache and
the per-user data there as soon as it finds one. So
`package-win32-portable-zip` (in `extras/package/win32/package.mak`) simply
ships the packaging tree, minus the installer scaffolding (NSIS scripts, the
installer's own translations, the SDK), plus that one folder.

Two things worth knowing about that folder:

- It is **not shipped empty**. A directory with no files in it is a zip entry
  that "extract here" shell integrations and several extractors drop without a
  word, and losing it would silently turn the portable build back into a normal
  one — it would still run, just writing to `%APPDATA%` behind the user's back.
  So it carries `README.txt` (`extras/package/win32/portable-README.txt`,
  UTF-8 **with BOM** and CRLF, so XP's Notepad renders it), which also explains
  the mode to whoever unzips it.
- The portable tree ships **no `plugins.dat`**: `powervlc-cache-gen.exe` is a
  Windows binary for a foreign architecture and the packaging runs on Linux
  with no wine (the NSIS installer runs it on the target machine instead). The
  first launch pays the full scan of the ~330 plugins and then writes the cache
  itself into `plugins/`, so it costs **one** slow start, once. That
  self-healing is the `_WIN32` branch of `AllocatePluginPath()` in
  `src/modules/bank.c` (it already existed for the macOS zips, which are
  deployed the same way): without it, nothing on Windows ever writes
  `plugins.dat` outside the installer, and the portable build would pay the
  scan on **every** start, forever.

`package-win32` no longer pulls in `package-win32-zip` and
`package-win32-7zip`: nothing ever collected either of them, the plain zip is
what the portable archive now is (minus the marker folder), and the 7z was a
second full-tree archive at `-mx=9` — minutes of CPU and a gigabyte of the
shared Docker volume for a file no release used. Both targets still work if
you invoke them by name.

### 6.5 Notes

- The first run uses the contrib source tarballs **vendored** under
  `contrib/tarballs/` (committed on purpose) and downloads the toolchains once, so
  a build never depends on a flaky download mirror.
- Each target keeps its state in a **persistent Docker volume**, so a re‑run
  *resumes* instead of recompiling from scratch. Two levels of housekeeping:
  ```bash
  extras/package/docker/build-in-docker.sh reclaim   # drop build dirs, KEEP contribs
  extras/package/docker/build-in-docker.sh clean     # delete the volumes outright
  ```
  Reach for `reclaim` first: a build directory costs minutes to rebuild, the
  Windows contribs cost hours.
- **Docker's virtual disk is a hard ceiling**, and a full campaign gets close to
  it: the three Windows targets share one volume holding ~23 GB of contribs plus
  2–5 GB per target, and each Linux target owns another 3–4 GB. Running out does
  not fail cleanly — it surfaces hours in as an unrelated
  `install: error writing …: No space left on device` inside `make install`.
  Each build therefore reclaims the *other* Windows targets' build directories
  when free space drops below **`PVLC_MIN_FREE_GB`** (default 10), never touching
  `contrib/`. Raise the ceiling in Docker Desktop → Settings → Resources if even
  that is tight, keeping an eye on the host disk it is carved from.
- An **interrupted build can poison the volume**: `autopoint` creates
  `tmpwrk<pid>` in the source root and only removes it on a clean exit, so a
  killed container or a full disk leaves one behind and every later run dies
  with `directory tmpwrkNNNN already exists`. The seed step now sweeps them, so
  this is handled — but it is why a rerun could once fail in seconds with an
  error that had nothing to do with the change being built.
- Builds run from a **clean copy of your working tree** (tracked + new files,
  minus build artifacts), so they never mix with the macOS `build*/` dirs.
- **No snap.** Linux ships as an AppImage only. snapcraft is itself a snap and
  wants LXD/multipass, so it never built reliably in a container; the Docker
  target was dropped rather than left as a trap. `extras/package/snap/` still
  holds the upstream VLC recipe, unused.
- Docker can build the binaries but not *run* them — test the `.exe` on Windows
  (and Windows‑on‑ARM hardware for `winarm64`) and the `.AppImage` on Linux.
- Full target matrix and known friction points: `extras/package/docker/README.md`.

---

## 7. Appendix — building the legacy cross-toolchain from scratch

Section 1.3 assumes `$HOME/Projects/darwin-legacy-toolchain` already exists. This
section builds it on a fresh Apple‑Silicon Mac. It is a **one‑time, ~1 h, ~15 GB**
job; nothing here is re‑run when PowerVLC's sources change.

Nothing in the tree below is produced by the PowerVLC repository — it is a
separate, self‑contained toolchain directory. The recipe was reconstructed from
the working toolchain (`config.log`, `CMakeCache.txt`, the checked‑out sources
and their local diffs), so the numbers and flags are the ones actually used to
build the shipped PowerPC/Intel‑32 slices.

### 7.0 What gets built

| Piece                 | Source                                        | Role |
|-----------------------|-----------------------------------------------|------|
| `opt/xtools`          | `iains/darwin-xtools`, branch `darwin-xtools-0-7-0r1` | cctools + ld64‑236.3: `as`, `ld`, `ar`, `ranlib`, `lipo`, `nm`, `otool`, `strip`, `install_name_tool`, `libtool` — the only assembler/linker left that emit PowerPC Mach‑O |
| `opt/gcc-ppc-tiger`   | `iains/gcc-13-branch`, tag `gcc-13.4-darwin-r0` | GCC 13.4.0 cross compiler → `powerpc-apple-darwin8` |
| `opt/gcc-i686-tiger`  | same                                          | GCC 13.4.0 cross compiler → `i686-apple-darwin8` |
| `sdks/MacOSX10.4u.sdk`| Xcode 3 / SDK archive                         | Tiger universal SDK (ppc + ppc64 + i386 + x86_64 stubs) |
| `sdks/MacOSX10.5.sdk` | Xcode 3 / SDK archive                         | Leopard SDK — source of the crt objects (7.2), and used by the optional `i686-leopard` target |

Only the four first rows plus the 10.4u SDK are needed to build `g3 g4 g4e g5 x86`.
The `opt/gcc-ppc` / `opt/gcc-i686` (darwin9 / 10.5) pair is optional — see 7.7.

Iain Sandoe's GCC branch is used rather than vanilla FSF GCC because it carries
the Darwin back‑end fixes for old PowerPC targets; his `darwin-xtools` is the
maintained build of Apple's open‑source cctools/ld64 for modern hosts.

### 7.1 Host prerequisites

```bash
brew install cmake gmp mpfr libmpc isl coreutils texinfo
```

- `gmp mpfr libmpc isl` are GCC's maths libraries — the `configure` lines below
  point at `/opt/homebrew` for all four.
- `cmake` ≥ 3.9.6 builds darwin‑xtools.
- Xcode's command‑line tools must be installed (7.3 uses Xcode's `tapi`).

### 7.2 Layout and the SDKs

```bash
export LT="$HOME/Projects/darwin-legacy-toolchain"
mkdir -p "$LT"/{src,build,opt,sdks}
```

Drop `MacOSX10.4u.sdk` and `MacOSX10.5.sdk` into `$LT/sdks/`. They come from the
Xcode 3.1/3.2 installer packages (`MacOSX10.4.Universal.pkg`, `MacOSX10.5.pkg`,
extractable with `xar`), or from one of the public SDK archives that repackage
exactly those. Sanity check — the 10.4u SDK must be the *universal* one:

```bash
file "$LT/sdks/MacOSX10.4u.sdk/usr/lib/libSystem.B.dylib"   # ppc, ppc64, i386, x86_64
```

Both SDKs then need two edits **before** GCC is built against them.

**a) Neutralize the unbalanced `#pragma options align=reset`.** Six IOKit storage
headers in the 10.4u SDK reset the struct packing without ever having set it;
Apple's GCC tolerated that, FSF GCC 13 errors out — and those headers are exactly
the ones the DVD/Blu‑ray code includes:

```bash
SDK="$LT/sdks/MacOSX10.4u.sdk"
for h in IOAppleLabelScheme IOApplePartitionScheme IOCDTypes IODVDTypes \
         IOFDiskPartitionScheme IOGUIDPartitionScheme; do
    f="$SDK/System/Library/Frameworks/IOKit.framework/Versions/A/Headers/storage/$h.h"
    [ -f "$f.orig" ] || cp "$f" "$f.orig"
    sed -i '' 's|^#pragma options align=reset|/* neutralized for FSF GCC (reset without prior set): #pragma options align=reset */|' "$f"
done
```

**b) Take the crt objects from the 10.5 SDK.** The 10.4‑era C runtime objects do
not link with the ld64‑236 / GCC 13 combination, and `lazydylib1.o` is missing
from the 10.4u SDK altogether. The originals are kept as `*.orig-10.4`:

```bash
for o in crt1.o gcrt1.o dylib1.o bundle1.o lazydylib1.o; do
    src="$LT/sdks/MacOSX10.5.sdk/usr/lib/$o"
    dst="$SDK/usr/lib/$o"
    [ -f "$dst" ] && [ ! -f "$dst.orig-10.4" ] && mv "$dst" "$dst.orig-10.4"
    cp "$src" "$dst"
done
```

(The 10.4‑specific start‑up glue that PowerPC Tiger still needs — `crt2.o`,
`crt3.o`, `crttms.o`… — is generated by GCC's own libgcc in 7.4, not taken from
the SDK.)

### 7.3 darwin‑xtools (assembler, linker, binutils)

```bash
git clone -b darwin-xtools-0-7-0r1 https://github.com/iains/darwin-xtools.git \
    "$LT/src/darwin-xtools"
```

One patch: cctools' `libtool` hardcodes an 8 KB host page size, which is wrong on
Apple Silicon (16 KB pages) and corrupts its output‑flush bookkeeping.

```bash
cd "$LT/src/darwin-xtools" && git apply - <<'EOF'
--- a/cctools/misc/libtool.c
+++ b/cctools/misc/libtool.c
@@ -2872,7 +2872,9 @@ uint64_t size)
     struct block **p, *block, *before, *after;
     kern_return_t r;
 
-	host_pagesize = 0x2000;
+	host_pagesize = getpagesize();
+	if(host_pagesize < 0x2000)
+	    host_pagesize = 0x2000;
 
 	if(cmd_flags.noflush == TRUE)
 	    return;
EOF
```

Configure, build, install:

```bash
cmake -S "$LT/src/darwin-xtools" -B "$LT/build/xtools" \
      -DCMAKE_BUILD_TYPE=MinSizeRel \
      -DCMAKE_C_COMPILER=/usr/bin/clang \
      -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
      -DCMAKE_INSTALL_PREFIX="$LT/opt/xtools" \
      -DDARWIN_PREFER_PUBLIC_SDK=YES \
      -DPACKAGE_VERSION="Darwin xtools-0.7.0r1"
make -C "$LT/build/xtools" -j"$(sysctl -n hw.ncpu)"
make -C "$LT/build/xtools" install
```

darwin‑xtools deliberately ships **no `dsymutil`** (it would need LLVM). GCC's
Darwin driver still insists on calling one, so install a no‑op and the
triple‑prefixed aliases GCC and the contribs look for:

```bash
cat > "$LT/opt/xtools/bin/dsymutil" <<'EOF'
#!/bin/sh
# no-op dsymutil for legacy cross toolchain
exit 0
EOF
chmod +x "$LT/opt/xtools/bin/dsymutil"

cd "$LT/opt/xtools/bin"
ln -sf "$PWD/dsymutil" powerpc-apple-darwin8-dsymutil
ln -sf "$PWD/dsymutil" powerpc-apple-darwin9-dsymutil
ln -sf "$PWD/dsymutil" i686-apple-darwin9-dsymutil
ln -sf "$PWD/ar"       powerpc-apple-darwin8-ar
ln -sf "$PWD/ranlib"   powerpc-apple-darwin8-ranlib
```

### 7.4 GCC 13.4 — the two cross compilers

```bash
git clone --depth 1 -b gcc-13.4-darwin-r0 \
    https://github.com/iains/gcc-13-branch "$LT/src/gcc-13"
```

One patch. `build.sh` compiles the PowerPC slices with `-mcpu=750` / `-mcpu=7400`
/ `-mcpu=970`, which makes the Darwin driver emit the subtype‑qualified arch
names `ppc750`, `ppc7400`, `ppc970`; the driver only recognises a bare `ppc` and
dies with *"this compiler does not support 'ppc750'"* while building libgcc:

```bash
cd "$LT/src/gcc-13" && git apply - <<'EOF'
--- a/gcc/config/darwin-driver.cc
+++ b/gcc/config/darwin-driver.cc
@@ -295,10 +295,12 @@ darwin_driver_init (unsigned int *decoded_options_count,
 	    seenX86 = true;
 	  else if (!strcmp ((*decoded_options)[i].arg, "x86_64"))
 	    seenX86_64 = true;
-	  else if (!strcmp ((*decoded_options)[i].arg, "ppc"))
-	    seenPPC = true;
 	  else if (!strcmp ((*decoded_options)[i].arg, "ppc64"))
 	    seenPPC64 = true;
+	  /* Accept subtype-qualified names (ppc750, ppc7400, ppc970, ...)
+	     that our own DARWIN_SUBARCH_SPEC emits when -mcpu is in use.  */
+	  else if (!strncmp ((*decoded_options)[i].arg, "ppc", 3))
+	    seenPPC = true;
 	  else if (!strcmp ((*decoded_options)[i].arg, "arm64"))
 #if !DARWIN_ARM64
 	    seenArm64 = true;
EOF
```

**PowerPC (`powerpc-apple-darwin8`).** Create the per‑target tool symlinks
*before* `make`: GCC's own `configure` is told where `as`/`ld` live, but the
libtool scripts inside the target libraries (libgcc, libstdc++, libobjc…) look
for `$prefix/$triple/bin/{ar,ranlib,libtool,…}` and silently fall back to the
host's otherwise.

```bash
mkdir -p "$LT/build/gcc-ppc-tiger" "$LT/opt/gcc-ppc-tiger/powerpc-apple-darwin8/bin"
for t in ar as dsymutil install_name_tool ld libtool lipo nm otool ranlib strip; do
    ln -sf "$LT/opt/xtools/bin/$t" \
           "$LT/opt/gcc-ppc-tiger/powerpc-apple-darwin8/bin/$t"
done

cd "$LT/build/gcc-ppc-tiger"
"$LT/src/gcc-13/configure" \
    --target=powerpc-apple-darwin8 \
    --prefix="$LT/opt/gcc-ppc-tiger" \
    --with-sysroot="$LT/sdks/MacOSX10.4u.sdk" \
    --with-as="$LT/opt/xtools/bin/as" \
    --with-ld="$LT/opt/xtools/bin/ld" \
    --with-dsymutil="$LT/opt/xtools/bin/dsymutil" \
    --with-cpu=750 \
    --enable-languages=c,c++,objc,obj-c++ \
    --with-gmp=/opt/homebrew --with-mpfr=/opt/homebrew \
    --with-mpc=/opt/homebrew --with-isl=/opt/homebrew \
    --disable-nls --disable-multilib --disable-bootstrap --with-system-zlib
make -j"$(sysctl -n hw.ncpu)"
make install
```

`--with-cpu=750` only sets the default; the AltiVec variants (`g4`, `g4e`, `g5`)
are produced by the `-mcpu=`/`-maltivec` flags `build.sh` passes per target, so
**one** PowerPC compiler covers all four PowerPC slices.

> **If `make` stops with `configure: error: Link tests are not allowed after
> GCC_NO_EXECUTABLES`** (typically in `libssp` or `libstdc++-v3`): a parallel
> `make` raced ahead of libgcc. Just run `make -j…` again — the second pass finds
> the freshly built libgcc and proceeds. Serialising the first stage
> (`make all-target-libgcc && make -j…`) avoids it entirely.

**Intel 32‑bit (`i686-apple-darwin8`).** Same recipe, no `--with-cpu`:

```bash
mkdir -p "$LT/build/gcc-i686-tiger" "$LT/opt/gcc-i686-tiger/i686-apple-darwin8/bin"
for t in ar as dsymutil install_name_tool ld libtool lipo nm otool ranlib strip; do
    ln -sf "$LT/opt/xtools/bin/$t" \
           "$LT/opt/gcc-i686-tiger/i686-apple-darwin8/bin/$t"
done

cd "$LT/build/gcc-i686-tiger"
"$LT/src/gcc-13/configure" \
    --target=i686-apple-darwin8 \
    --prefix="$LT/opt/gcc-i686-tiger" \
    --with-sysroot="$LT/sdks/MacOSX10.4u.sdk" \
    --with-as="$LT/opt/xtools/bin/as" \
    --with-ld="$LT/opt/xtools/bin/ld" \
    --with-dsymutil="$LT/opt/xtools/bin/dsymutil" \
    --enable-languages=c,c++,objc,obj-c++ \
    --with-gmp=/opt/homebrew --with-mpfr=/opt/homebrew \
    --with-mpc=/opt/homebrew --with-isl=/opt/homebrew \
    --disable-nls --disable-multilib --disable-bootstrap --with-system-zlib
make -j"$(sysctl -n hw.ncpu)"
make install
```

### 7.5 The three wrapper scripts

`build.sh` does not call `powerpc-apple-darwin8-gcc` directly — it prefers
`$prefix/bin/tiger-cc`, `tiger-c++` and `legacy-luac`. These are hand‑written and
**not produced by `make install`**; create them in *both* `opt/gcc-ppc-tiger/bin`
and `opt/gcc-i686-tiger/bin`.

`tiger-cc` — drops the Apple‑only flags old `configure` scripts hardcode, and
clears `SDKROOT` (the GCC 13 Darwin driver honours it like clang, so a host SDK
path leaked by meson/ninja would silently override the baked‑in 10.4u sysroot):

```bash
cat > "$LT/opt/gcc-ppc-tiger/bin/tiger-cc" <<'EOF'
#!/bin/sh
# Filtering wrapper around the legacy cross GCC: drops Apple-only flags
# that old configure scripts hardcode on Darwin and that FSF GCC rejects.
# The modern GCC-Darwin driver honours $SDKROOT like clang: a leaked host
# SDK path silently overrides our baked-in 10.4u sysroot (meson/ninja
# re-export it). Neutralize it here once and for all.
unset SDKROOT
real="$(dirname "$0")/powerpc-apple-darwin8-gcc"
n=$#
i=0
while [ $i -lt $n ]; do
    a=$1; shift
    case "$a" in
        -no-cpp-precomp|-cpp-precomp|-Wno-precomp) ;;
        *) set -- "$@" "$a" ;;
    esac
    i=$((i+1))
done
exec "$real" -D__powerpc__=1 "-D__builtin_available(...)=0" "$@"
EOF
```

`tiger-c++` is the same script with `real=…-g++` and three extra defines:

```
exec "$real" -D__powerpc__=1 "-D__builtin_available(...)=0" \
     -D__STDC_FORMAT_MACROS -D__STDC_CONSTANT_MACROS -D__STDC_LIMIT_MACROS "$@"
```

The Intel pair is identical except `real=…/i686-apple-darwin8-gcc` (resp. `-g++`)
and **no** `-D__powerpc__=1`.

`legacy-luac` — Lua bytecode is not portable across byte order/word size, so
instead of byte‑compiling, copy the source under the `.luac` name; the target's
Lua compiles it at load time (`build.sh` sets `LUAC`/`LUAC_ANY_ARCH` when this
exists):

```bash
cat > "$LT/opt/gcc-ppc-tiger/bin/legacy-luac" <<'EOF'
#!/bin/sh
# Fake luac for cross-compilation to a foreign byte order / word size.
# Lua bytecode is not portable across architectures, but luaL_loadfile()
# loads plain source transparently (it only treats a file as bytecode when
# it begins with the ESC "Lua" signature). So instead of byte-compiling we
# copy the source to the .luac output; the target compiles it at load time.
out=""
in=""
while [ $# -gt 0 ]; do
    case "$1" in
        -o) out="$2"; shift 2 ;;
        -*) shift ;;        # ignore other luac flags
        *)  in="$1"; shift ;;
    esac
done
[ -n "$out" ] && [ -n "$in" ] || { echo "legacy-luac: bad args" >&2; exit 1; }
cp "$in" "$out"
EOF
chmod +x "$LT"/opt/gcc-*-tiger/bin/tiger-cc "$LT"/opt/gcc-*-tiger/bin/tiger-c++ \
         "$LT"/opt/gcc-*-tiger/bin/legacy-luac
```

### 7.6 Smoke test

```bash
printf 'int main(void){return 0;}\n' > /tmp/t.c
"$LT/opt/gcc-ppc-tiger/bin/tiger-cc"  -arch ppc  -O2 -o /tmp/t.ppc  /tmp/t.c
"$LT/opt/gcc-i686-tiger/bin/tiger-cc" -arch i386 -O2 -o /tmp/t.i386 /tmp/t.c
file /tmp/t.ppc /tmp/t.i386     # "Mach-O executable ppc" / "… i386"
```

Then the real test — build the smallest slice end to end:

```bash
extras/package/macosx/build-powervlc.sh g3
```

### 7.7 Optional: the Leopard (darwin9) compilers

`build.sh` keeps an `i686-leopard` target "for reference" (10.5, `opt/gcc-i686`),
and a matching `opt/gcc-ppc` exists for `powerpc-apple-darwin9`. Neither is used
by the seven shipped targets. Build them the same way as 7.4, changing
`--target=` to `…-apple-darwin9`, `--prefix=` to `$LT/opt/gcc-i686` (resp.
`gcc-ppc`), `--with-sysroot=` to `$LT/sdks/MacOSX10.5.sdk`, and dropping
`--with-cpu`. The 10.5 SDK itself is **not** optional — 7.2 takes the crt objects
from it.

### 7.8 Notes

- Nothing in the toolchain is relocatable: the prefixes are baked into GCC and
  into `$prefix/$triple/bin` symlinks. Build it at its final path, or rebuild
  after moving it. `VLC_LEGACY_TOOLCHAIN` only tells `build.sh` where to *look*.
- `opt/xtools/bin/as` and `ld` are the only PowerPC‑capable assembler/linker in
  the setup; if a contrib picks up the host `/usr/bin/ld` instead, the failure is
  an unhelpful "unknown architecture" — check `LD`/`AR` in the environment.
- The `.orig` / `.orig-10.4` backups left in the SDKs by 7.2 make the two SDK
  edits auditable and reversible; keep them.
