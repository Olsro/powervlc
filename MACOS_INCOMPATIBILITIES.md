# PowerVLC — Compatibility by macOS / architecture environment
*This document has been entirely AI-generated*

This document records **what works, degrades, or is absent depending on the macOS version and CPU architecture** PowerVLC runs on (a fork of VLC 3.0.x for old Macs, branch `retrocompatibility/oldmacs`).

It is **maintained by hand**. See [§14 Maintenance](#14-maintaining-this-document) for update rules and the authoritative sources.

> **Confidence legend**
> - ✅ **tested on real target hardware** (iBook G3 Tiger, Mac Mini G4 on Tiger then Leopard, Intel MacBook on Leopard…)
> - ⚠️ **open limitation or known degradation**
>
> **Matrix cell legend**
> - ✅ available · ⚠️ degraded / partial · ❌ absent (not compiled or not loadable) · 🔺 requires an external component · — not applicable

---

## 1. Target environments

### 1.1 Build slices

Each target produces a distinct Mach-O slice. The **universal** binary merges up to 7 of them via `lipo`.

| Build | Arch / subtype | macOS min | SDK | Compiler | SIMD | Endian / word | Interface(s) |
|---|---|---|---|---|---|---|---|
| `buildg3` | ppc (ppc750) | **10.2** | 10.4u | FSF GCC 13 (Tiger) | — (`--disable-altivec`) | BE / 32-bit | legacy |
| `buildg4` | ppc (ppc7400) | **10.2** | 10.4u | FSF GCC 13 | AltiVec | BE / 32-bit | legacy |
| `buildg4e` | ppc (ppc7450) | **10.2** | 10.4u | FSF GCC 13 | AltiVec | BE / 32-bit | legacy |
| `buildg5` | ppc (ppc970) | **10.2** | 10.4u | FSF GCC 13 | AltiVec | BE / 32-bit | legacy |
| `buildx86` | i386 | 10.4 (10.4.4) | 10.4u | FSF GCC 13 (Tiger) | — (`--disable-mmx --disable-sse`) | LE / 32-bit | legacy |
| `buildx64` | x86_64 | 10.5 *(see 1.2)* | modern Xcode | Apple clang | SSE2 | LE / 64-bit | modern + legacy |
| `buildarm64` | arm64 | 11.0 | modern Xcode | Apple clang | NEON | LE / 64-bit | modern + legacy |
| `builduniversal` | fat (the 7 above) | **10.2** (per arch) | — | — (`lipo` merge) | — | — | both worlds |

- **G4 / G4e / G5 share one set of contribs** built for the lowest common ISA (`-mcpu=7400 -maltivec`); only VLC itself is tuned per variant. The PowerPC slice embedded in the universal is in practice `ppc750`, which loads on **any G3/G4/G5** by subtype grading.
- **G3 has no AltiVec** (`ppc750`, `-mcpu=750`); it uses separate contribs.
- The **PPC and i386 toolchains are FSF GCC** (not clang): this **mechanically excludes every plugin written in ARC** (see §4, §6).
- **i386 asm**: **ffmpeg's x86 asm (SSE2+ IDCT / motion-comp / DSP, for every codec) IS re-enabled** — its EXTERNAL (nasm) asm assembles position-independent (`--enable-pic`), the non-PIC GCC INLINE asm is disabled (`--disable-inline-asm`, else the H.264 CABAC inline emits an illegal text-relocation), and the plugin links with `-Wl,-read_only_relocs,suppress` (the few remaining external-asm text relocations are allowed, making those text pages writable — a minor cost). cpu-flag detection still works via ffmpeg's external `ff_cpu_cpuid`. Needs `nasm`/`yasm` at build time. VLC's OWN chroma/scaler MMX/SSE stays disabled (the GPU planar path in `macosx_gl1` does YUV→RGB instead); **dav1d** x86 asm stays disabled (SIGBUS, §see AV1). A Core 2 Duo handles the rest in C.

### 1.2 Which slice runs on which Mac?

| Mac / OS | Slice loaded | Interface | Notes |
|---|---|---|---|
| PowerPC G3/G4/G5 — **Jaguar 10.2 / Panther 10.3** | `ppc750` … `ppc970` | **legacy** | See §1.3. Shipped in the universal bundle, **launch validated on a real 10.2 iBook** |
| PowerPC G3 — Tiger 10.4 / Leopard 10.5 | `ppc750` | **legacy** | GPU often lacks GLSL → GL1 vout (§9) |
| PowerPC G4 / G5 — Tiger 10.4 / Leopard 10.5 | `ppc` (tuned) | **legacy** | AltiVec active |
| Intel 32-bit only — 10.4.4 → 10.6 | `i386` | **legacy** | Core Solo/Duo of the first Intel Macs |
| Intel 64-bit — **10.5.8** | `i386` (chosen on purpose) | **legacy** | The `x86_64` slice is **gated to 10.6** (see below) |
| Intel 64-bit — **10.6** (Snow Leopard) | `x86_64` | **legacy** | The modern interface requires 10.7 → legacy fallback |
| Intel 64-bit — **10.7+** (Lion →) | `x86_64` | **modern** (+ legacy, switchable) | |
| Apple Silicon — 11.0+ | `arm64` | **modern** (+ legacy) | x86_64 also runs under Rosetta |

### 1.3 The 10.2 Jaguar floor (every PowerPC slice)

**All four PowerPC slices** (`ppc750`, `ppc7400`, `ppc7450`, `ppc970`) target **10.2**,
and the universal bundle ships them: `LSMinimumSystemVersion = 10.2`,
`…ByArchitecture:ppc = 10.2.0`. Launch and DVD playback validated on a real
iBook G3 (PowerBook4,3, Radeon 7500): interface, playlist, audio, **video**, DVD
playback and even the **ATI hardware MPEG-2 decoder** all run. It is built with the same
FSF GCC 13 / 10.4u SDK, only `-mmacosx-version-min=10.2` changes — plus the
compatibility work below.

What Jaguar lacks and how it is worked around:

| Missing on 10.2 | Consequence | Workaround |
|---|---|---|
| `dlopen`/`dlsym`/`dlclose` (10.3+) | 329 of 332 Mach-Os reference them — nothing loads | `jaguar-compat/dlcompat.c` over `NSCreateObjectFileImageFromFile`/`NSLinkModule`. ⚠️ `NSLookupSymbolInModule()` does **not** search the sub-frameworks an umbrella re-exports, so a fallback to `NSIsSymbolNameDefined`/`NSLookupAndBindSymbol` is required — without it every `dlsym` on an umbrella framework silently returns NULL |
| Dylib exports found **only** through the table of contents | Every symbol of a shipped dylib reads as undefined | `add-dylib-toc.py`, run **last** (after `install_name_tool`) on `Contents/MacOS/lib/*.dylib` |
| ObjC 1.0 runtime | A `.m` defining **no class** leaves `module->symtab` NULL and `_objcInit()` dereferences it → the process dies at `dlopen`, silently | `check-objc-modules.sh` guards the bundle at build time |
| `@try/@catch` does not catch Foundation exceptions | Diagnosis impossible from inside the app | stderr of a Finder-launched app goes to `/var/tmp/console.log` |
| `sysconf(_SC_PAGESIZE)` returns **-1** | `block_mmap_Alloc` gets `p_start=NULL`; plug-in cache unusable (25 s startup) | `block_PageSize()` falls back to `getpagesize()` |
| `snprintf(NULL, 0, …)` returns **-1** | `vlc_http_msg_format()` returns NULL → **no HTTP/1.1 request can be built** (HTTP/2 worked, hence the clue) | one-byte probe buffer in `messages.c`, `memstream.c`, `vasprintf.c`. ⚠️ Do **not** redefine `snprintf` in a compat library: it collides with `libSystemStubs.a` (`duplicate symbol _snprintf$LDBLStub`) |
| UTIs (`LSItemContentTypes`, 10.4+) | VLC declares the common formats by UTI only → invisible in "Open With" | 29 `CFBundleTypeExtensions` blocks (127 extensions) in `share/Info.plist.in` |
| `CGSMainConnectionID` (10.3+) | The private CGS path used by the hardware decoder has no connection | `GetCGSConnectionID()`, exported by **QD** — reachable only thanks to the `dlsym` fallback above |
| AppKit APIs added in 10.3/10.4 | `-setHidden:`, NSMenu delegates, alternating table rows, `sizeLastColumnToFit`… | compatibility layer in `legacy_macosx/misc.m`; a menu carrying a **submenu is never validated**, so dynamic submenus rebuild from an `-[NSMenu update]` subclass |
| AUHAL never sets `kAudioTimeStampHostTimeValid` | `ca_TimeGet()` returns -1 permanently: no audio clock feedback | tolerated; ⚠️ see §13 |

> **Two silent traps closed while lowering the floor.** ① Neither a contrib prefix nor a
> build directory recorded the deployment target it was made for, and **neither is
> rebuilt or reconfigured in place** — lowering the floor would have linked 10.4 objects
> into a "10.2" bundle with no error at all, the failure showing up only as a dyld error
> on the old machine. Both now carry a `.powervlc-osx-min` stamp, checked at start-up.
> ② `make-universal.sh` compiles its own **architecture trampoline** (`vlctrampoline.c`)
> and did so **without `-mmacosx-version-min`**: the Tiger cross-GCC defaulted to 10.4,
> and the whole bundle died on Jaguar with `undefined reference to _snprintf$LDBL128`
> even though every real slice was correct. That stub now builds with
> `-mmacosx-version-min=10.2` **and `-lSystemStubs`** (below 10.4 the SDK redirects the
> printf family to `_<fn>$LDBLStub`, which lives only in that static library — without
> it the stub does not even link).

> > **Why the `x86_64` slice is gated to 10.6 and not 10.5.8** (`make-universal.sh:118-131`): the Mach-O produced by the modern clang carries the `LC_DYLD_INFO_ONLY` load command, which Leopard 10.5's `dyld` does not understand. Result: on an Intel 10.5.8 machine, **all** native interface plugins (modern **and** legacy) would fail to load and VLC would fall back to the Lua CLI interface (a "lua error" dialog). By declaring `LSMinimumSystemVersionByArchitecture:x86_64 = 10.6.0`, LaunchServices on 10.5.8 picks the **i386** slice (legacy toolchain, loads cleanly, legacy interface): the app "just works" with no manual 32-bit toggle. ✅ (validated on a 2007 white MacBook, round 89)

### 1.3 macOS version reference

| Version | Name | Year | Architectures |
|---|---|---|---|
| 10.4 | Tiger | 2005 | PPC + Intel (from 10.4.4) |
| 10.5 | Leopard | 2007 | PPC + Intel — **last PowerPC OS** |
| 10.6 | Snow Leopard | 2009 | Intel (32/64) — **last usable 32-bit Intel OS** |
| 10.7 | Lion | 2011 | Intel 64 — first *modern* interface |
| 10.8 | Mountain Lion | 2012 | Intel 64 |
| 10.9–10.11 | Mavericks / Yosemite / El Capitan | 2013–15 | Intel 64 |
| 10.12–10.15 | Sierra / High Sierra / Mojave / Catalina | 2016–19 | Intel 64 |
| 11+ | Big Sur, Monterey, … | 2020 → | Intel 64 + **Apple Silicon** |

---

## 2. Summary matrix (feature × environment)

Columns: **G3** (ppc750) · **G4/G5** (ppc AltiVec) · **i386** (Intel 32) · **x64 ≤10.6** (Intel 64 on Snow Leopard) · **x64 ≥10.7** (Intel 64 on Lion and up) · **ARM** (Apple Silicon 11+).

| Feature | G3 | G4/G5 | i386 | x64 ≤10.6 | x64 ≥10.7 | ARM |
|---|:--:|:--:|:--:|:--:|:--:|:--:|
| **Modern interface** (Cocoa/ARC/autolayout) | ❌ | ❌ | ❌ | ❌¹ | ✅ | ✅ |
| **Legacy interface** (10.4-safe) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Chromecast** (sending) | ❌ | ❌ | ❌ | ❌² | ✅ | ✅ |
| **Network discovery mDNS/Bonjour** (renderers) | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **UPnP / DLNA / SAT>IP** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **SAP/SDP, HTTP, HLS/DASH** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **HTTPS / TLS** | ✅ gnutls | ✅ gnutls | ✅ gnutls | ✅ | ✅ | ✅ |
| **Notifications** | 🔺 Growl | 🔺 Growl | 🔺 Growl | 🔺 Growl³ | ✅ native⁴ | ✅ native |
| **Hardware decode (VideoToolbox)** | ❌ | ❌ | ❌ | ❌⁸ | ✅ | ✅ |
| **Hardware decode (VDA, H.264 only)** | ❌ | ❌ | ❌ | ✅⁸ | ⚠️⁸ | — |
| **AV1 (dav1d)** | ⚠️ slow C | ⚠️ slow C | ⚠️⁵ | ✅ | ✅ | ✅ |
| **AltiVec (PPC acceleration)** | ❌ | ✅ | — | — | — | — |
| **MMX/SSE/NEON** | — | — | ❌ | ✅ SSE | ✅ SSE | ✅ NEON |
| **Subtitles / OSD (freetype)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Multi-script font fallback (CoreText)** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Vout for GPUs without GLSL (fixed GL1)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Accelerated QuickTime vout (ICM)** | ✅ | ✅ | ✅ | ❌ | ❌ | ❌ |
| **CoreAnimation vout (caopengllayer)** | ❌ | ❌ | ❌ | ❌¹ | ❌¹ | ✅ |
| **AVFoundation capture** (camera/screen via AVF) | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Auto-update (Sparkle) (But disable anyway in this fork globally)** | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Keychain** (password storage) | ❌ | ❌ | ❌ | ✅ | ✅ | ✅ |
| **Keyboard media keys** | ⚠️⁶ | ⚠️⁶ | ⚠️⁶ | ✅ | ✅ | ✅ |
| **Apple Remote (IR)** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Speech synthesis (TTS)** | ⚠️⁷ | ⚠️⁷ | ⚠️⁷ | ✅ | ✅ | ✅ |
| **Lua internet SDs** (Jamendo, Icecast…) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Blu-ray BD-J menus** | ⚠️⁹ | ⚠️⁹ | ⚠️⁹ | ⚠️⁹ | ⚠️⁹ | ⚠️⁹ |

**Notes:**
1. `❌¹`: the **modern interface** requires macOS 10.7 (the dylib fails to load below that) → legacy fallback. The **caopengllayer** vout requires 10.6 (GCD) **and** is compiled only in the arm64 slice (the x64 slice targets 10.5 → not compiled); on Intel, rendering goes through **macosx** (GLSL) or **GL1**.
2. `❌²`: the Chromecast plugin *is* compiled in the x86_64 slice, but with `-mmacosx-version-min=10.7` → below 10.7 `dyld` refuses it → **unavailable on 10.5/10.6**.
3. `🔺³`: on Snow Leopard 10.6 there is no native notification center → **Growl required** (as on 10.4/10.5).
4. `✅⁴`: native `NSUserNotification` from **10.8** onward. On 10.7, Growl fallback.
5. `⚠️⁵`: on i386, dav1d's x86-32 asm is **disabled** (to avoid a SIGBUS crash) → it runs the **C fallback**, like PPC — no SIMD, so slower than the x86_64/arm64 asm path (though an Intel CPU handles it better than a PowerPC one). Decoding is correct, just not accelerated.
6. `⚠️⁶`: legacy media keys require `[NSEvent eventWithCGEvent:]` (**10.5+**) → **inoperative on 10.4**, working from **10.5** (with the accessibility permission). Since the PPC/i386 columns span 10.4→10.6, the cell depends on the installed OS.
7. `⚠️⁷`: TTS works everywhere, but **automatic language detection** requires 10.5+ → on Tiger 10.4, the default system voice is used.
8. `⁸`: the two hardware decoders cover **disjoint** OS ranges. `videotoolbox` is built `-mmacosx-version-min=10.8`, so on **Snow Leopard 10.6 `dyld` refuses it** — hardware decoding there is **VDA**, which needs 10.6.3+ and one of that era's GPUs (9400M/320M/GT 330M, Intel HD). On **10.7** VDA is still the only one; from **10.8** VideoToolbox loads and outranks it (capability 800 vs 100), so VDA stops being used. VDA is H.264 **only**; every other codec is software below 10.8. See §7.1bis.

9. `⚠️⁹`: BD-J menus need a **JRE installed on the user's machine** — macOS has not shipped one since 10.6, and libbluray loads it at runtime. Two things had to be fixed for the old Macs. **(a) Bytecode:** the BD-J jars we bundle are compiled to **Java 5** (class file v49), which is the floor on **10.4 and 10.5 PowerPC** — those top out at Apple's Java 1.5.0_19, Java 6 on Mac having been Intel-only. That needs a **JDK 8** to build (javac 9+ dropped `-source 1.5`). Lowering the bytecode version is not sufficient on its own: the BD-J layer replaces JDK internals, and `java.io.FileSystem`, `java.awt.peer.ComponentPeer` and `FramePeer` changed shape between Java 5 and Java 6, while `java.awt.Container.{get,set}ComponentZOrder` are **final** in Java 5 (overriding them makes `HScene` fail verification the moment it loads). Contrib patch `0004-bdj-run-on-java-5` adds the four missing Java 5 methods and turns the two `HScene` overrides into private helpers, keeping a **single jar valid on both** Java 5 and modern JREs. Compilation still uses the Java 6 boot class path (`contrib/java6-bootclasspath/`) because the compatibility methods must see the Java 6 shapes; `check-bdj-java6.py` fails the build if anything added after Java 6 is referenced, and `check-bdj-java5.py` additionally verifies the jars against a real Java 5 class library when `contrib/java5-bootclasspath/` has been populated (Apple's is not redistributable, so it ships empty). Verified against Apple Java 1.5.0_19 from a 10.4.11 PPC install: the only post-Java-5 references left are inside methods a Java 5 VM never dispatches to. **(b) Finding the VM:** stock libbluray **cannot find Apple's Java 6 at all** — measured on 10.6.8 with 1.6.0_65. It has no `libjli.dylib`, `/usr/libexec/java_home` points at a JDK with no `lib/server`, and the VM libraries in `Contents/Libraries` export only `JNI_CreateJavaVM_Impl`. Contrib patch `0003-macos-load-Apple-Java-6-through-the-JavaVM-framework` loads the `JavaVM` umbrella framework instead, which exports `JNI_CreateJavaVM` and dispatches to the VM matching the process architecture (`libjvm.dylib` is i386-only, `libserver.dylib` is universal). That mechanism is **verified on hardware in both i386 and x86_64**; the full BD-J path on a real disc is **not yet tested**. Targeting Java 5 removes the dependency on the community **Java 6 PowerPC** port, which reportedly runs interpreted (no JIT); menus may still be too slow on G3/G4. Without a JRE, a BD-J disc still plays its main title, without menus.

Detailed causes are in the sections below.

---

## 3. Graphical interface

Three interface modules coexist, arbitrated by **capability score** and by build-time gating:

| Interface | Directory | Score | Compiled for |
|---|---|---|---|
| **Modern** | `modules/gui/macosx` | 200 | x86_64 + arm64 slices, `-mmacosx-version-min=10.7` |
| **Legacy** | `modules/gui/legacy_macosx` | 50 | any target whose min < 10.6 (+ forced on x64/arm64) |
| Minimal | `modules/gui/minimal_macosx` | 50 | opt-in `--enable-minimal-macosx` (disabled by default) |

- **Modern = 10.7+ only.** The dylib is built with load commands that pre-Lion `dyld` rejects: below 10.7 it simply fails to load and VLC falls back to the lower-scored interface (legacy). There is **no runtime version guard** — the `dlopen` failure is the gate.
- **Legacy = everywhere, and the only possible UI on PPC and Intel 32-bit.** Written in MRC (manual memory management) and drawn by code (no XIB), 10.4-compatible.
- **Modern ↔ Legacy switch**: on a ≥ 10.7 system both modules are present (x64/arm64 slice) and the user can switch via the menu. The "switch to the modern interface" item on the legacy side only appears from **10.7.5** onward (`VLCLegacyOSVersionAtLeast(10,7,5)`). ✅ (switch tested locally)

### 3.1 Legacy vs Modern behavioral differences

| Aspect | Modern (`macosx`) | Legacy (`legacy_macosx`) |
|---|---|---|
| Layout | XIB / autolayout | code / frames (no XIB) |
| Memory | ARC | MRC (manual pools) |
| Dark mode | follows system **Dark Aqua** (10.14+); otherwise a manual theme | **manual** grey/dark theme (`legacy-macosx-dark` option), no system following |
| Native fullscreen (Lion) | ✅ | ❌ (custom fullscreen only) |
| Sidebar | real `PXSourceList` | `NSTableView` mimicking the look |
| Menu bar icon | `VLCStatusBarIcon` (Sierra API) | ❌ absent |
| Notch / safe area | ✅ (Monterey 12) | ❌ |
| Rosetta detection / per-arch update feed | ✅ | ❌ |

### 3.2 Version gates in the MODERN interface

Detection via `NSAppKitVersionNumber` (`CompatibilityFixes.h`). Each feature falls back cleanly below its threshold:

| UI feature | Requires | Below the threshold |
|---|---|---|
| **Dark Aqua dark mode** (system following) | 10.14 Mojave | manual dark theme (borderless chrome) |
| **Native fullscreen** | 10.7 Lion | custom FS button |
| **Title-bar rendering** (variations) | 10.10 Yosemite / 10.11 El Capitan gates | "lion-" images/buttons |
| **Persistent menu bar icon** | 10.12 Sierra | manual remove/recreate of the item |
| **HUD views** (Effects panels) | custom drawing < 10.10; **native vibrancy** ≥ 10.10 | — |
| **Now Playing / modern media keys** | 10.12.2 | `SPMediaKeyTap` fallback |
| **Multi-monitor / separate Spaces** | 10.9 Mavericks | default behavior |
| **`NSByteCountFormatter`** (sizes) | 10.8 | manual formatting |
| **Notch / safe area** | 12.0 Monterey | no inset removal |
| **Big Sur-style sidebar** | 11.0 | default icon margins |
| **Rosetta detection + per-arch Sparkle feed** | 11.0 **and** `__x86_64__` | — *(the only architecture gate in the UI code)* |

### 3.3 Version gates in the LEGACY interface

Central helper `VLCLegacyOSVersionAtLeast()` (reads `SystemVersion.plist`, without Gestalt or `@available`).

| UI feature | Requires | Below the threshold |
|---|---|---|
| **Layer backing** (`setWantsLayer:`) | 10.14 | no layer-backed rendering |
| **Fullscreen artwork** (FS panel) | 10.5 (AppKit ≥ 949) | fallback to VLC 2.x artwork (PDF tinting renders solid rectangles on 10.4) |
| **Media keys** (event tap) | 10.5 | ❌ none on 10.4 |
| **Volume slider** (thin rail) | SDK ≥ 10.5 | 5 px rail computed by hand (`barRectFlipped:` outside the 10.4 contract) |
| **Blu-ray** (`IOBDMedia.h`) | SDK ≥ 10.5 | not included (header absent from the 10.4u SDK) |
| **Preferences icons** | 10.5 | manual 32×32 rebake (10.4 `NSButtonCell` ignores `setSize:`) |
| **Apple menu** (`setAppleMenu:`) | — | on 10.4, called via `respondsToSelector:` to avoid a duplicate "VLC" menu |
| **HUD windows** | `NSHUDWindowMask` = 10.6 | everything hand-drawn (custom rounded background) |

---

## 4. Casting & network discovery

**Summary: the entire Chromecast ecosystem is absent on PowerPC and Intel 32-bit.** Three cumulative, independent causes:

1. **Chromecast sender** (`stream_out/chromecast`) — requires `protoc` **and** `protobuf-lite`. But protobuf uses `__thread` (TLS), available only from **macOS 10.7** → the protobuf contrib is **not** built on the Tiger toolchains (darwin8) → `BUILD_CHROMECAST` is never enabled. The plugin is also compiled `-mmacosx-version-min=10.7`. ✅ (absence confirmed)
2. **Bonjour discovery** (`bonjour.m`, mDNS via `NSNetServiceBrowser`) — this is the module that **finds** Chromecasts and feeds the "Renderer" menu. Written in **ARC** (clang) and forced `-mmacosx-version-min=10.6` → **never built** on PPC/i386 (FSF GCC, `HAVE_OBJC_ARC=no`). ⚠️ open limitation: no mDNS discovery on PowerPC.
3. **microdns fallback** — the `libmicrodns` contrib is **excluded on all Darwin** by its rule, and is only cross-compiled for x86_64 (out of band). Absent on PPC/i386 **and** arm64.

| Feature | Requires | Where it is built | Otherwise |
|---|---|---|---|
| **Chromecast** sender | protobuf-lite + macOS ≥ 10.7 | x86_64, arm64 | not compiled (PPC/i386); rejected by `dyld` below 10.7 (x64) |
| **Bonjour / mdns_renderer** discovery | ARC (clang) + 10.6 | x86_64, arm64 | ❌ PPC/i386 → "No renderer" menu |
| **microdns** (fallback mDNS) | contrib added out of band | x86_64 only | ❌ elsewhere |
| **UPnP / DLNA / SAT>IP** | libupnp | **all** targets | — (works on PPC Tiger) |
| **SAP / SDP** (multicast announcements) | — | **all** targets | — |
| **HTTP / HLS / DASH / Smooth** | portable | **all** targets | — |
| **TLS — SecureTransport** (Apple backend) | SDK 10.6 (`SecPolicyCreateSSL`) | x64, arm64 | **gnutls** fallback |
| **TLS — gnutls** (portable backend) | — | **all** targets | this is THE TLS backend on PPC/Tiger |

> **In short:** encrypted network playback (HTTPS, HLS-over-TLS, radios, Jellyfin…), UPnP/DLNA and SAP **work on PowerPC Tiger**; only **Chromecast casting and its discovery** are reserved for the x86_64/arm64 slices.

---

## 5. Notifications

The `osx_notifications` plugin is compiled **on all targets**. It picks a back-end at runtime in this order:

1. **Native `NSUserNotification`** — if the build SDK is ≥ 10.8 **and** the runtime OS is ≥ 10.8. This is the only "no dependency" path.
2. **Modern Growl framework** — only if `Growl.framework` was embedded in the contribs. **This is not the case on any target** (`HAVE_GROWL_FRAMEWORK` undefined everywhere): the modern framework SDK does not build on PPC 10.4/10.5.
3. **Distributed Growl protocol (≤ 1.2)** — universal fallback via `NSDistributedNotificationCenter`, **one-way**.

**Consequence per environment:**

| Environment | Notifications |
|---|---|
| macOS **10.8+** (x64 ≥ 10.8, arm64) | ✅ native `NSUserNotification`, nothing to install |
| macOS **10.7** | 🔺 distributed Growl protocol → **Growl must be installed and running** |
| macOS **10.4 – 10.6** (PPC, Intel 32, Intel 64 on SL) | 🔺 distributed Growl protocol → **Growl must be installed and running** |

- On old systems, **without a Growl daemon listening, no notification is shown** — but **no crash** (silent no-op, commented "harmless no-op when Growl is not installed").
- On PPC, the app icon is attached by hand. The in-process `.icns` decoder **fails on 10.5**, so the code goes through **IconServices** (`[NSWorkspace iconForFile:]`, tolerant). ✅
- No notification is emitted while VLC is in the foreground (intended behavior, all versions).

---

## 6. System integrations & peripherals

### 6.1 Media keys (keyboard play/pause)
- **Modern interface**: `VLCRemoteControlService` (MediaPlayer.framework) from **10.12.2**; below that, `SPMediaKeyTap` (event tap). *A theoretical micro-gap exists on 10.12.0/10.12.1 where neither path is active.*
- **Legacy interface**: event tap requiring `[NSEvent eventWithCGEvent:]` (**10.5+**) **and the accessibility permission**. **Nothing on 10.4.** On 10.6+, it tracks the "last active media app"; on 10.4/10.5, it only intercepts when VLC is in the foreground.

### 6.2 Apple Remote (IR receiver)
- Depends on the **IR receiver hardware** (`AppleIRController` via IOKit) — absent from all Macs since ~2010. No macOS version gate to enable it.
- Button mapping ("HID cookies") is **OS-version-specific**, not arch-specific. The `AppleIRController` element cookies sit at a different base offset per release: Tiger 10.4 (`14_…`), Leopard 10.5 (`31_…`), Snow Leopard→10.12 (`33_…`), then further shifts at **10.13** and **10.15**. All branches handled in `VLCLegacyAppleRemote.m -init`. On **≤10.5** cookie `19` is part of every button string (`31_…_19_18_`), so the "remote switched" interception in the queue callback is gated to **10.6+** — otherwise every press would corrupt the string and spuriously fire `kRemoteControl_Switched`.
- ✅ **Validated on a real Apple Remote** on the Intel MacBook (i386 slice) under **Tiger 10.4** *and* **Leopard 10.5** (play/pause, volume ±, arrows) — 2026-07-19. PPC/G-series share the exact same OS-version cookie tables (IR receivers were essentially absent from PowerPC Macs).

### 6.3 Keychain (password storage)
- The `keychain` plugin is written in **ARC** → requires **macOS 10.6+** and clang → **not compiled on PPC/i386**. Below that, VLC falls back to the encrypted-file / memory keystore.
- The per-entry **accessibility** setting (`keychain-accessibility-type`) requires **10.9 Mavericks**; ignored below.
- iCloud Keychain sync: depending on iCloud being enabled system-side.

### 6.4 Speech synthesis (TTS, `nsspeechsynthesizer`)
- Compiled everywhere. Works on all versions.
- **Automatic language detection** (`CFStringTokenizerCopyBestStringLanguage`) requires **10.5+** → on **Tiger 10.4**, the default system voice is used (degradation, not failure). ⚠️

### 6.5 Motion sensor (Sudden Motion Sensor, `unimotion` / `motion` plugin)
- Depends on **hardware**: PowerBook/iBook (I2C/PMU sensor, **PPC**), MacBook Pro (SMC, **Intel**). Desktops and recent machines have no sensor → plugin inactive.
- API gate: `IOConnectCallStructMethod` (**10.5+**) vs `IOConnectMethodStructureIStructureO` (Tiger 10.4).

### 6.6 App icon / .icns (Tiger & Leopard)
- On **Tiger**, the generic icon came from (a) the **creator code** `VLC#` hijacking the icon association (fixed: signature `????`), then (b) the **.icns size** (10.4 IconServices chokes above ~547 KB; the 1024 px element was removed). ✅
- On **10.5**, the in-process `NSImage` decoder fails to read an `.icns` containing PNG elements → the icon disappears wherever the app draws it itself (alert dialogs, Growl). Workarounds: elements re-encoded as JPEG2000, routing through IconServices. ✅

---

## 7. Codecs & decoding

### 7.1 Hardware decode — VideoToolbox (10.8+)
- The `videotoolbox` plugin + `glconv_cvpx` glue: `VideoToolbox.framework` is **absent from pre-10.8 SDKs** → **never built on PPC or i386**. Compiled `-mmacosx-version-min=10.8`, present on **x86_64 + arm64**.
- Hardware codecs supported: **H264, HEVC, MPEG-4 part 2, H263, ProRes, DV, MPEG-1/2**. **No AV1, no VP9.**
- **HEVC** hardware: requires SDK ≥ 10.13 + `VTIsHardwareDecodeSupported` at runtime.
- On PPC/i386, everything goes through **software decoding** (ffmpeg/libmpeg2, with AltiVec on G4/G5).

### 7.1bis Hardware decode — VDA (10.6.3 → 10.7, H.264 only)
- `VideoDecodeAcceleration.framework` shipped with **10.6.3** for the GPUs of that era (**GeForce 9400M / 320M / GT 330M**, Intel HD). It is the **only** hardware decoder on 10.6 and 10.7, since public VideoToolbox starts at 10.8.
- The framework is **absent from the 10.4u/10.5 SDKs** → `HAVE_VDA_FRAMEWORK` is false → the `vda` plugin is **never built on PPC or i386**. Present on **x86_64 + arm64**, compiled `-mmacosx-version-min=10.6`.
- **On by default.** It cannot displace the modern path: `videotoolbox` declares capability **800** against `vda`'s **100**, so from 10.8 on VideoToolbox always wins. When the chipset or the stream is unsupported, the module returns `VLCDEC_RELOAD` and VLC restarts the chain on `avcodec` (capability 70). ✅ fallback verified by fault injection on the 320M — no crash.
- **Zero-copy is what makes it worth having.** Decoded frames stay in GPU memory (IOSurface-backed `CVPixelBuffer` → `glconv_cvpx` → `CGLTexImageIOSurface2D`). Reading them back to system memory costs more than it saves.
- **Output format matters enormously**: these engines write **packed 4:2:2 (`2vuy`)** natively. Asking VDA for a 4:2:0 layout still succeeds, but it converts every frame **on the CPU** on the way out. Measured on a **GeForce 320M**, 1080p H.264, fullscreen, share of one core:

  | Path | CPU |
  |---|---|
  | software (avcodec) | 79.7 % |
  | VDA, readback + `memcpy` (old) | 81.5 % |
  | VDA zero-copy asking NV12 / I420 | 51.9 % / 51.5 % |
  | **VDA zero-copy asking UYVY** (default) | **9.0 %** |

  With DTS audio on top, full playback goes from **83 %** of a core to **18 %**. ✅ validated on the 2010 MacBook (10.6.8, 320M)
- Overridable with `--vda-chroma` (`auto`/`uyvy`/`nv12`/`i420`) should another chipset prefer a different native format.
- ⚠️ **One VDA session at a time per GPU**, and the driver holds it for several seconds after the client dies — a second instance gets `VDADecoderCreate` **-12473** and silently falls back to software.

### 7.2 AV1 (dav1d)
- **i386**: dav1d's x86-32 asm is **broken on Mach-O** (SIGBUS in `ipred_z1_ssse3`) → **disabled** (`enable_asm=false`) → **C** path (correct, slower). ✅ (crash avoided)
- **x86_64 / arm64**: asm kept (SSSE3/AVX2; NEON) → full performance.
- **PowerPC**: dav1d has **no PowerPC SIMD** → C path in practice. Works but **very slow**: ~2-4 fps at 720p on a G4, *slow-motion* at 480p on a G3 (dav1d has no *hurry-up*, it slows the whole pipeline instead of dropping frames). ⚠️ beyond a realistic hardware budget.
- AV1 is provided via **dav1d** (ffmpeg 4.x has no AV1); an aligned-allocation patch covers < 10.6.

### 7.3 AltiVec (PowerPC acceleration)
- **G4/G4e/G5 only** (`-maltivec`), **never G3** (`--disable-altivec`), nonexistent on Intel/ARM → C path.
- Optimizations gated on `HAVE_ALTIVEC` + big-endian: `i420_yuy2`, RenderX deinterlacing, and (PowerVLC-specific ffmpeg patches) h264 qpel8, CABAC renorm via `cntlzw`, chroma deblocking, half-pel MC. All bit-exact, with a C fallback.
- MPEG-2 decoding goes through **avcodec (AltiVec)** on G4+; `libmpeg2` serves as a lightweight decoder (AltiVec MC on G4/G5, word-at-a-time 32-bit MC on G3).

### 7.4 MMX / SSE / NEON
- **i386**: **ffmpeg** x86 asm (SSE2+) re-enabled — external nasm asm + `--disable-inline-asm` + `-Wl,-read_only_relocs,suppress` at link (see §1.1). VLC-native chroma/scaler MMX/SSE stays disabled (GPU planar path handles YUV→RGB). Big decode speedup for heavy codecs.
- **x86_64**: SSE2 (auto).
- **arm64**: NEON (auto).

---

## 8. Subtitles & fonts (freetype / CoreText)

- **Subtitle/OSD rendering**: works everywhere, but with font-discovery differences.
- **Default font**: on **macOS < 10.6** (so all PPC + i386 Tiger slices, and i386 Leopard), the default font is `Helvetica.dfont` (HelveticaNeue does not exist before 10.6). Without this gate, the default font would point to a missing file → **subtitles not rendered**. ✅
- **Multi-script fallback (CoreText)**: Darwin font discovery (`fonts/darwin.c`) requires the `CoreText.h` header, **absent from the 10.4u SDK** (which only ships a header-less SPI stub) → on **PPC G3/G4/G5 and i386 (SDK 10.4u)**, freetype **falls back to the default face only** (no fallback for CJK, Arabic, etc.). Active on x86_64/arm64 (and on an i386 target built with SDK 10.5). ⚠️
- History: on **i386 / Leopard 10.5**, subtitles were broken ("Error creating face for Helvetica") because the CoreText `getPathForFontDescription` path is gated 10.6+ → NULL on 10.5. Fixed with a pre-10.6 **ATS fallback** (`ATSFontFindFromPostScriptName`). ✅ (round 90)

---

## 9. Video output (OpenGL)

Four `vout display` modules, chosen by priority and GPU capabilities:

| Module | Priority | Requires | Target / GPU |
|---|:--:|---|---|
| `caopengllayer` | 300 | macOS 10.6+ (GCD) — **compiled arm64 only** | modern CoreAnimation |
| `macosx` | 250 | OSX (always built) — uses GLSL | GPUs with shaders |
| `macosx_qt` | (QuickTime) | SDK with QuickTime.h (**old SDKs**) | accelerated ICM/QuickDraw blit **PPC** |
| `macosx_gl1` | 60 | OSX (always built) | **GPUs without GLSL** — fixed OpenGL 1.1 pipeline |

**Effective order:**
- On **arm64**: `caopengllayer` (300).
- On **Intel / PPC**: `macosx` (250, GLSL) then `macosx_gl1` (60) as a last resort when the GPU cannot compile shaders.

**Hard cases on old GPUs (all resolved by the GL1 path):**
- **iBook G3 GPUs** (Rage 128, Mobility Radeon 7500) **have no GLSL** → the old modern vout failed ("no suitable vout"). Resolved by the **fixed-function GL1** path. ✅
- The **Radeon 9200** (Mini/eMac/iMac G4) under **Leopard 10.5.8** is a **GL 1.3 without hardware GLSL**, yet the driver **advertises GLSL 1.20**: VLC engaged shaders that "compile" but the GPU does not execute → **black video (sound OK)**. Resolved by detection (GL < 2.0 + advertised GLSL ⇒ fixed-function). ✅
- The same 9200 is **POT-only** (no non-power-of-two textures) under Leopard → `glTexSubImage2D` crash on the first frame, fixed (upload only the visible region). ✅
- The Intel MacBook's **GMA950** is a **real GL2** → normal shader path, unchanged. ✅

**GL1 packed vs planar paths:**
- **GL1 packed** (`GL_YCBCR_422_APPLE`) = robust default, all GPUs. The chroma choice depends on endianness (`YUYV` on big-endian PPC, `UYVY` on little-endian) via `WORDS_BIGENDIAN`.
- **GL1 planar** (YUV via GPU combiners) = **opt-in** (default off), requires `GL_ATI_texture_env_combine3` (any Radeon ≥ 9000 + Mobility 7500). ⚠️ In **windowed** mode it never produced a correct result (surface recomposited on every flush); it is only clean in **fullscreen** (page-flip). Exposed in the preferences with a **red warning**.

---

## 10. Miscellaneous (auto-update, capture, Lua, DVD/Blu-ray)

### 10.1 Automatic update (Sparkle)
- Sparkle (auto-update) is **not** embedded on the PPC/i386 targets (modern framework). Available on x86_64/arm64. On Apple Silicon / Rosetta, the update feed is chosen by architecture (ARM64 feed if the binary is translated).

### 10.2 AVFoundation capture (camera / screen via AVF)
- `avcapture` / `avaudiocapture`: the `-framework AVFoundation` link test fails on the 10.4u SDK (+ needs ARC/10.7) → **not compiled on PPC/i386**. Present on x86_64/arm64.

### 10.3 Lua modules / internet SDs
- **Lua bytecode (`.luac`) is not portable** across endianness and word size → on **PPC (big-endian) and i386 (32-bit)**, a `.luac` compiled on the build machine (arm64 64-bit LE) is rejected ("bad header in precompiled chunk"), which broke **all internet SDs** (Jamendo, Icecast…). Fixed by **shipping the `.lua` source** under the `.luac` name (the interpreter recompiles at load time, on any arch). ✅ Slight overhead on first load.
- The Icecast SD (~20 MB of XML parsed in Lua = minutes at 100% CPU) was removed then reinstated **with debounce** on Tiger. A confirmation is requested before enabling a Lua SD.

### 10.4 DVD & Blu-ray
- **Mounted DVD (`/Volumes/…/VIDEO_TS`) that stopped at the title entry**: this was a **Tiger kernel physiological bug** (xnu-792: a `read()` > 128 KB from a *raw device* into an unaligned/unfaulted buffer only transfers the first chunk), **specific to PowerPC Tiger**. Fixed in the libdvdnav contrib (4096 alignment + pre-fault). Unaffected on a modern kernel. ✅ *(period workaround: read the ISO directly instead of the mounted disc.)*
- The **look-ahead cache** (decode-ahead) is finely tuned for the single-core PPC (DVD MPEG-2 was counterproductive before the fixes). The cache is **enabled on DVD movies**, **inhibited on menus** (dvdnav) and **inhibited for the whole session on Blu-ray** (BD-J/HDMV are unmappable).
- **Blu-ray**: the `IOBDMedia.h` header only exists from SDK 10.5 (gated on the legacy side).
- **AACS (retail Blu-ray decryption)**: `libaacs` is built as a **shared** library by `contrib/src/aacs` and bundled in `Contents/MacOS/lib/libaacs.dylib` on **every** slice — there is no version or architecture gate, since libbluray only `dlopen()`s it (no SDK involved). `bluray.c` exports `LIBAACS_PATH` pointing at the bundled copy, because a `.app` is on no library search path. **Verified so far on arm64 only** (built, loaded, all symbols libbluray needs resolved); the PowerPC/Intel-32 slices are built the same way but have not been exercised on hardware yet.
- **Importing a key database**: opening a `keydb.cfg` file offers to copy it to `~/Library/Preferences/aacs/KEYDB.cfg`, where libaacs reads it (`modules/demux/keydb.c`). The popups come from the core dialog API, so they work in **both** interfaces — the legacy provider used to silently reject every question dialog and now shows a modal alert (`VLCLegacyMain.m`). No keys are shipped with the player.

---

## 11. Summary by macOS version

- **10.2 Jaguar / 10.3 Panther** (PPC): **legacy** interface via the dedicated `buildg3-jaguar` slice (§1.3). Everything the 10.4 floor offers minus what Jaguar itself lacks; **DVD playback and the ATI hardware decoder work**. ⚠️ Not merged into the universal bundle today — `make-universal.sh` still declares `ppc = 10.4.0`.
- **10.4 Tiger** (PPC & Intel 32): **legacy** interface; notifications **via Growl**; **no media keys** (legacy requires 10.5); TTS without language detection; no CoreText (default face only); no Chromecast/Bonjour/Keychain/VideoToolbox/AVFoundation/Sparkle; fixed GL1 or QuickTime vout.
- **10.5 Leopard** (PPC & Intel): same, but **legacy media keys OK** (10.5+, with accessibility), Blu-ray header available. On Intel 64-bit, the **i386** slice is chosen (x86_64 gated to 10.6).
- **10.6 Snow Leopard** (Intel): **x86_64** slice; interface **still legacy** (modern = 10.7); notifications **via Growl**; VideoToolbox/Keychain/AVFoundation/Chromecast **available**; `caopengllayer` **not** (compiled arm64 only).
- **10.7 Lion**: **modern interface** available (native fullscreen); notifications **still Growl** (native = 10.8).
- **10.8 Mountain Lion**: **native notifications** `NSUserNotification` (end of the Growl dependency).
- **10.9 → 10.15**: UI refinements (Spaces 10.9, HUD/Yosemite vibrancy 10.10, StatusBar/Now-Playing Sierra 10.12, Dark Aqua Mojave 10.14…).
- **11 Big Sur+ / Apple Silicon**: **arm64** slice; `caopengllayer`; notch/safe-area; Rosetta detection and per-architecture update feed; x86_64 also runs under Rosetta.

---

## 12. Summary by architecture

- **PowerPC G3**: legacy; **no AltiVec**; GPU often **without GLSL** → GL1; AV1 in slow-motion; the rest of the software codecs hold up to ~480p.
- **PowerPC G4/G5**: legacy; **AltiVec**; real-time H264/HEVC up to 1080p (G4); **no** Chromecast/Bonjour/Keychain/VideoToolbox/AVFoundation.
- **Intel 32-bit (i386)**: legacy; **everything in C** (no MMX/SSE); AV1 in C (asm disabled, no crash); **no** Chromecast/Bonjour/Keychain/VideoToolbox/AVFoundation/CoreText.
- **Intel 64-bit (x86_64)**: modern (≥ 10.7) + legacy; SSE2; VideoToolbox, Chromecast, Bonjour, Keychain, AVFoundation; `caopengllayer` **not compiled** (`macosx`/GL1 path).
- **Apple Silicon (arm64)**: modern + legacy; NEON; `caopengllayer`; all network/casting integrations **except microdns** (discovery via Bonjour only).

---

## 13. Known open limitations

| # | Limitation | Environment | Status |
|---|---|---|---|
| 1 | **No mDNS/Bonjour network discovery** (hence no Chromecast discovery) | PowerPC (and i386) | Open — MRC/10.4 port of `bonjour.m` not done |
| 2 | **AV1 beyond budget** (dav1d in C: ~2-4 fps at 720p on G4, slow-motion 480p on G3) | PowerPC | Hardware limit, not a bug |
| 3 | **`Non-aligned pointer being freed`** (~13 msgs) when reading audio metadata | i386 **and** ppc | Open — harmless (playback OK); cause = static init of the bundled libstdc++ GCC13 vs the system one, not taglib |
| 4 | **Keyboard media keys & Apple Remote** validated on real hardware (Intel 10.4/10.5); media keys need 10.5+ (none on 10.4 by design, see ⚠️⁶) | all (legacy) | ✅ Validated |
| 5 | **Chromecast** compiles but **no real cast tested**; unavailable on 10.4–10.6 | x86_64/arm64 | To validate for real |
| 6 | **Windowed GL1 planar** does not render correctly | ATI/PPC GPUs | Worked around (default = packed; planar fullscreen only) |

---
- ⚠️ **10.2 — DVD playback stutters with the ATI hardware decoder.** The path works
  (2.5× the software decoder: ~23.5 vs ~9 frames/s at 720×576) but never reaches the
  25 fps of the source, and the residual irregularity is visible. Apple's own DVD
  Player is perfectly smooth on the same machine, same GPU, same driver. Eliminated by
  measurement: the surface pool, the vout's retention policy, the clock, input
  starvation, the entropy decoder, the WindowServer (4.5 % CPU), the frame-drop policy,
  the display-composition calls, the audio clock and the resampler, and VSync (the
  panel exposes no configurable refresh — 9 modes, all fixed-timing). With audio
  disabled the presentation cadence becomes near perfect (93.5 % of intervals on the
  40 ms grid) **and the stutter is still visible**, so the defect is in *what* is shown,
  not *when*. Investigation suspended; see the project memory for the full list of
  closed leads.
- ⚠️ **10.2 — untested:** subtitles, window resize during playback, long files.

---

## 14. Maintaining this document

**Authoritative sources** (in priority order):
1. `buildXXX/config.status` (the `ac_cs_config` line = exact configure invocation) and `buildXXX/config.h` + the `.dylib`s actually produced in each bundle — **the ground truth on what is compiled where**.
2. `configure.ac` (the `AM_CONDITIONAL` / `HAVE_*`: `HAVE_OBJC_ARC`, `HAVE_VT_FRAMEWORK`, `HAVE_CORETEXT`, `HAVE_QUICKTIME_FRAMEWORK`, `HAVE_OSX_GCD`, `HAVE_SECURETRANSPORT`, `HAVE_ALTIVEC`, `BUILD_CHROMECAST`, `HAVE_GROWL_FRAMEWORK`…).
3. `extras/package/macosx/build.sh` (arch → min OS / SDK / toolchain / CPU flags matrix, `:147-204`) and `make-universal.sh` (`LSMinimumSystemVersionByArchitecture` floors, slice assembly).
4. The `Makefile.am` of the modules involved (`-mmacosx-version-min=…` gates, `if HAVE_…`).
5. `HANDOFF-tiger-ppc-build.md` — detailed log (rounds), **tests on real machines**, root causes and revisions.

**Doc pitfalls to watch for:**
- The HANDOFF's "canonical command" shows `--disable-osx-notifications / --disable-chromecast / --disable-macosx-avfoundation` that are **no longer passed**: `config.status` is authoritative. `osx_notifications` is actually **ON everywhere**; Chromecast/AVFoundation drop out on their own (missing dependency/SDK), not via `--disable`.
- The interface-switch threshold is **10.7** in the code (not 10.7.5 — the latter only gates the appearance of the menu item on the legacy side).
- Distinguish **compiled** (the plugin exists) from **loadable/active** (`dyld` accepts it, the hardware/OS allows it at runtime). E.g.: x86_64 Chromecast is *compiled* but ignored below 10.7.

**When to update:** whenever a new version/arch gate is added (`MAC_OS_X_VERSION_*`, `respondsToSelector:`, `@available`, `HAVE_*`, `-mmacosx-version-min`), whenever a module becomes conditional, and after every test on a new real machine/OS.

---

*Last compiled: 2026-07-19. Based on the state of the `retrocompatibility/oldmacs` branch (HANDOFF rounds 41→90).*
