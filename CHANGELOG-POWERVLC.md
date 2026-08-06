# PowerVLC Changelog

PowerVLC is an unofficial fork of VLC 3.0.x universally compatible with more legacy systems, not affiliated with VideoLAN.

## 1.2.0 (2026-08-09)

### New features — all platforms (modern machines included)

- **Four ready-to-use extensions are now shipped with the player**, all
  built from plain dialog widgets so they render on every interface —
  the modern macOS one, the legacy Mac OS X one and Qt on Windows/Linux:
  - **Invidious**: browse public instances, search videos, channels and
    playlists, and play at the quality you pick. Instances that have shut
    their JSON API down are read from their HTML pages instead, and the
    DASH manifest is rebuilt locally, so a working instance stays working.
  - **Jellyfin**: browse a server (movies, series, seasons, episodes) and
    play either the original file or an HLS stream transcoded at the
    chosen quality. Sign in with an API key or with a username and
    password; the flow follows the JellyDinosaur front-end, and PowerVLC
    announces itself under its own name in the server's session list.
  - **Subsonic / Navidrome / Airsonic**: browse a music server the way a
    music player does — by album, album artist, genre, playlist or song —
    with a per-view search box, a favourites filter, star/unstar from the
    right-click menu, gapless playback, server-side transcoding, and
    downloads either dragged straight out to the Finder or saved to the
    Downloads folder with a live progress bar.
  - **Podcast discovery (iTunes)**: search Apple's public podcast
    directory, sort the results, open a show on a page carrying its
    artwork and its own description (read from the feed, the only place
    it exists), and subscribe in one click — the feed is written into the
    very preference the Podcasts service reads, so the show joins the
    sidebar next to the ones added by hand and survives the next launch.
- **Sites guarded by an anti-bot challenge are handed to your browser.**
  A growing number of servers put a JavaScript proof-of-work (Anubis) or
  a captcha in front of every page. PowerVLC does not try to solve those:
  it opens the page in the browser you already have — even a Mac OS X
  10.4 machine runs a current one — and takes back the session the
  browser legitimately earned, through a one-shot loopback server behind
  an unguessable path. Only the *page* is ever handed over: the media
  itself is always fetched by the player.
- **PowerVLC browser add-on**, shipped with the application and installed
  in one click from the Help menu (“Install the PowerVLC add-on in your
  browser…”). It sends what the browser is playing over to the player,
  and it is the only way in on browsers older than Firefox 69 — the ones
  legacy Macs run — which refuse to run a bookmarklet on any page
  carrying a security policy.
- **Play a random radio station** from the Radio-Browser directory:
  worldwide, per continent, or within the country you are browsing. A new
  `radiobrowser://` access resolves a fresh station at every activation
  and defeats the mirrors' caching, so pressing it again really does give
  another station.
- **Searches ignore accents, ligatures and typographic punctuation**:
  typing `au coeur de l'histoire` now finds *Au Cœur de l’Histoire*. Case
  folding is applied to both sides in the core (new `vlc_strfold()`), so
  every interface and every list benefits.
- **A far richer extension API**, which third-party extensions can use
  too, implemented identically in the three dialog providers: check
  boxes, drop-down lists, multi-column lists that sort by clicking a
  header, right-click context menus, double-click activation,
  selection-changed events, rows that can be dragged out to the Finder,
  centred images — plus new Lua bindings for the clipboard
  (`vlc.clipboard`), HTTP with POST, custom headers and cookies
  (`vlc.http`), the system keystore (`vlc.keystore` — the Keychain on
  macOS, Secret Service or KWallet on Linux, an encrypted file
  elsewhere), the running interface language (`vlc.config.language`),
  unfiltered stream reads (`vlc.raw_stream`) and the browser handoff
  above (`vlc.browser`).
- **Cover art in WebP now displays.** Upstream leaves WebP to the vpx
  module, which only knows the bare VP8 bitstream and fails on every
  actual `.webp` file, so servers handing out WebP artwork showed no
  artwork at all.

### Improvements — all platforms (modern machines included)

- **Extension translations moved to per-language catalogues**
  (`share/lua/i18n/<extension>/<code>.lua`): only the language in use is
  ever read, instead of parsing sixteen of them at every activation. 72
  catalogues, 18 languages, and English underneath string by string so an
  untranslated entry shows in English rather than as a hole. All the new
  strings of the release are also propagated to the 105 shipped
  interface languages.
- **PowerVLC no longer shares its user folder with a stock VLC install**
  on Windows and Linux (`powervlc` instead of `vlc`): same folder meant
  the same preferences *and* the same art cache, so a wrong cover cached
  by one was served back by the other. Upstream's pre-XDG fallback was
  also removed — it silently imported a neighbouring VLC's configuration
  on first launch and then deleted it.
- **A dead host no longer freezes whoever is waiting on it**: the
  connect() wait is now bounded by `ipv4-timeout` instead of running into
  the kernel's TCP timeout (75 seconds on Darwin).
- **A decoder that falls behind gives up filtering before it gives up
  frames**, in two steps: B slices first, then all slices, and only then
  are whole frames dropped. This costs nothing on a machine that is
  keeping up — it only fires once the decoder is already several frames
  late — so a 2007 Core 2 Duo meeting a 1080p stream benefits from it for
  the same reason a G4 does.
- **Extensions can no longer hang the application on exit**: each one now
  carries an interruption context, so network I/O blocked on a dead host
  is aborted when quitting instead of being waited on.
- Filling an extension list with thousands of rows was quadratic (every
  append walked the whole chain); it is now constant-time — felt on any
  machine, crippling on the slow ones this fork exists for.
- Extensions name themselves in the interface language: the scan state
  that runs `descriptor()` now offers the string library and the
  interface language, so a menu entry is no longer stuck in English.
- Playlist scripts can translate the item names they build, which until
  now stayed English whatever language was chosen.
- Numbers are parsed in the C locale again: launched from a French (or
  any comma-decimal) environment, every Lua script parsing JSON failed
  with “no valid JSON”.
- The self-healing plugin cache, until now compiled for macOS only, also
  covers Windows: the portable archive no longer pays a full plugin scan
  at every start, and a third-party plugin dropped into `plugins/` is
  scanned once instead of at every launch.

### New features — legacy Macs

- **Crystal HD hardware decoding.** PowerVLC drives the Broadcom Crystal
  HD mini-PCIe card (BCM70015) found in — or added to — older Intel Macs,
  offloading H.264, VC-1 and MPEG-2 to it, with a fallback to the
  processor whenever the card cannot handle a stream. The kernel
  extension is bundled and installed, reloaded or removed straight from
  the Help menu (no version of macOS before 10.15 lets userspace map a
  PCIe device's registers, so there is no way around a kext here), and
  the client and the driver now agree on an ABI token so a mismatched
  pair refuses to talk instead of corrupting kernel memory.
- **Accelerated DVD playback on the oldest G3s.** The GPU plug-in is now
  discovered dynamically from IOKit's own `IODVDBundleName` instead of
  being hardcoded to one family, and a second family — **`ATIRage128`** —
  is admitted alongside `ATIRadeon`. Validated end to end on an iBook G3
  with a Rage 128 Mobility: accelerated decoding *and* GPU-composited
  subtitles on all three of Mac OS X 10.2, 10.3 and 10.4.
- **Animated DVD menus are accelerated too.** They were unusable — the
  picture kept its geometry but lost all detail, then the CPU fallback
  made it lag. Two causes, both found by replaying the disc's own menu
  VOB off-machine: the menus are coded with MPEG-2's **alternate
  coefficient scan** (100 % of their pictures, where films use the
  classic zigzag) which the ATI coefficient format cannot express, and
  the guard meant to protect true interlaced video was measuring the
  wrong thing — it dropped the hardware path over 3.5 % of macroblocks
  and sent the other 96.5 % of already-correct work back to a CPU that
  cannot keep up at 720×576.
- **Menu-button highlights are composited by the GPU** as well, on
  10.2 through 10.4 — including Jaguar, whose driver parses the raw
  subpicture packet itself and therefore needs the highlight palette
  written back into it.
- **HEVC gets AltiVec on PowerPC**: SAO, IDCT and motion compensation.
  Paired with a new H.264 chroma motion-compensation routine (the single
  hottest function in the measured H.264 profile, 10.4 % of decode time
  on its own).

### Improvements — legacy Macs

- **AC-3 is decoded by liba52 rather than libavcodec on the G3s** (the
  PowerPC slices without AltiVec): measured on a 600 MHz iBook G3 during
  DVD playback, 68.9 % CPU against 72.3 %, *and* floating-point decoding
  where libavcodec falls back to its 16-bit fixed-point path. A new Audio
  preference turns it off.
- The 32-bit Intel slice now gets the PowerPC decoding trade-offs, since
  its entire population is 2006-2009 hardware: in-loop deblocking skipped
  on non-reference frames (in HEVC this drops SAO as well — measured
  +14 % at 854×480 and +11 % at 1080p on 10-bit content), and the
  keyframe slideshow rather than a black screen when a stream is hopeless.
  The 64-bit slices, which span a 2006 Core 2 Duo to an Apple Silicon
  Mac, deliberately keep full quality and rely on the late-frame
  escalation instead.
- **The keyframe slideshow no longer oscillates**: keyframe-only decoding
  always catches up, so the decoder used to leave the slideshow at once,
  fall behind again and burn another five seconds of black screen before
  coming back. It now holds the slideshow for a minimum time, doubling
  that hold on every immediate relapse, so hopeless content settles into
  a steady slideshow while a one-off hiccup still recovers in seconds.
- **An optical drive that gives up no longer looks like a freeze.** When
  the drive drops the disc mid-playback, libdvdnav keeps returning
  success on empty events forever; PowerVLC now watches the time since
  the last real block, checks whether the media is still there, and says
  so instead of spinning silently. Still frames and menu waits rearm the
  watchdog, so a legitimately silent menu never trips it.
- The Crystal HD card can be switched off from the legacy Preferences
  window like any other decoder.

### Fixes — legacy Macs

- **The G5 slice of 1.1.0 crashed at startup** on a PowerMac7,2 (and so
  did the universal build on any G5, which grades that slice highest).
  GCC's `-mcpu=970` silently enables 64-bit GPR instructions inside a
  32-bit binary, and Mac OS X does not preserve the upper halves of the
  registers across a context switch for a 32-bit task. Now built with
  `-mno-powerpc64`, as Apple's own GCC always did.
- **Toggling fullscreen during accelerated playback could freeze the
  whole machine**, SSH included. Going fullscreen moves the video view
  into a borderless window, which makes AppKit destroy and recreate its
  QuickDraw port — while the video thread may be drawing into it. The
  drawing lock is now held across the move.
- **The menu-highlight refresh only ever ran once.** It sat after the
  deadline computation in the subpicture thread, and a button change is
  not a deadline: 30 button presses produced a single redraw. The
  highlight now moves with the keyboard and the mouse.
- **Blu-ray and DVD menus ignored the mouse in windowed mode** on Mac OS
  X 10.4: AppKit routes mouse-moved events to the first responder, not to
  the view under the pointer, and this output — the one used by cards
  without rectangle textures, such as the iBook G3's Rage Mobility — was
  not claiming it.
- **The interface language was not remembered** on the legacy interface:
  it is stored in NSUserDefaults, and on systems without `cfprefsd`
  nothing flushes that to disk on quit. Choosing Arabic, Hebrew or
  Persian also translated the interface without laying it out
  right-to-left; both are fixed.
- Audio on Mac OS X 10.2 was reported as broken by a probe failing on a
  property that simply does not exist on that system — logged as an error
  at every launch while playback was in fact fine, in 5.1.

### Fixes — Windows and Linux

- **Blu-ray decryption, x265 and SRT were silently missing from the
  Windows builds.** A handful of components (libaacs, libbdplus, the
  x265, GME and SRT plugins) import a mingw runtime DLL that nothing
  shipped; `LoadLibrary` then fails, the plugin drops out of the cache,
  and the feature vanishes without a single error message. Every runtime
  DLL the tree actually imports is now staged, and a missing one fails
  the build instead of the user's playback.
- **No non-macOS build at all could be produced** for a while: defining a
  plugin's `LDFLAGS` inside a platform conditional makes automake link
  with that (empty) variable everywhere else, dropping the
  `-no-undefined` that mingw requires — reported as an error nowhere near
  its cause.
- The Windows release archives could contain the installers of previous
  versions, swept up by a glob over an output directory that keeps every
  artifact ever built.

### New features — Windows

- **A portable archive** is now published next to the installer for each
  Windows target, from the very same binaries: it carries a `portable`
  folder next to `powervlc.exe`, and the core then keeps the
  configuration, the media library and the caches there instead of in
  `%APPDATA%`. The marker folder ships a README inside it, so no
  extractor can quietly drop it and turn the portable build back into a
  normal one writing behind the user's back.

### Build & packaging

- **The universal bundle went from 797 MB to 520 MB** without losing a
  single module or a single decoded bit:
  - the `g4e` slice was dropped after measuring it on the machine it
    existed for, a 1.42 GHz Mac mini G4: 0.5 % on MPEG-2 DVD playback and
    nothing at all on H.264 720p, for ~90 MB. `-mcpu=7450` only
    reschedules PowerVLC's own code, while decoding time is spent in the
    contribs, which were the shared build either way. A 7450 now grades
    the `ppc7400` slice highest and keeps AltiVec (dropping *that* one
    instead would fall back to `ppc750`, i.e. no AltiVec at all — 13 %
    slower);
  - `-Wl,-dead_strip` on every plugin (623 → 520 MB), verified module by
    module and bit-exact on decoding;
  - debug symbols actually stripped for the first time, including on the
    x86_64 slice, whose 10.5 deployment target produces a `__LINKEDIT`
    layout that `strip` refuses to touch — the debug info is dropped at
    link time there instead, keeping every local function name so
    backtraces stay readable.
- **Bundled libraries no longer carry the build machine's paths.** libaacs
  and libbdplus — the only contribs built shared, because libbluray
  `dlopen()`s them — advertised an absolute path that exists on no other
  machine, on all seven slices. Every bundled library whose id is still
  an absolute non-system path is now normalised to
  `@executable_path/lib/`, generically rather than by name, with a small
  Mach-O editor because `install_name_tool` cannot run on the x86_64
  slice at all.
- The Crystal HD contrib is rebuilt whenever it changes: it defines the
  ioctl layout the client uses to talk to a kernel extension shared with
  every other program on the machine, and nothing was rebuilding it on
  the incremental path.
- **A Tahoe-format application icon** for modern Macs, generated by a new
  script, alongside the existing ones.
- `ACCELERATED-MPEG2-COMPATIBILITY.md` rewritten around the two admitted
  GPU families and the machines each was validated on.

## 1.1.0 (2026-08-02)

### New features — all platforms (modern machines included)

- **Forced subtitles done right** (backported from VLC 4.0 — and beyond):
  cherry-picked the complete master forced-subtitles series — forced flag in
  the ES format, forced-only rendering in the DVD and PGS subtitle decoders,
  DVD forced-caption track detection and description (audio and subtitle
  `code_extension`), correct handling of hidden subpicture streams, and
  forced-track prioritization in default track selection.
- **Blu-ray forced PGS track detection, which even VLC master lacks**: the
  TS demux scans presentation composition segments for the forced flag, and
  PowerVLC shows only the forced captions of such tracks (new
  `bluray-forced-subs` option, enabled by default).
- **DVD-Audio (AUDIO_TS) playback** in the dvdread module, using the new
  libdvdread 7.x API: title table, track seeking and duration, LPCM/MLP
  AOB demuxing.
- **BD+ protected Blu-rays**: libbdplus is now shipped alongside libaacs.
- **Automatic main-playlist selection on Blu-rays with obfuscated
  playlists**, using the information declared in `keydb.cfg`.
- Blu-ray **pop-up menu** entry (shortcut and context menu) usable on both
  HDMV and BD-J discs.
- New Help-menu entries to open the libaacs/libbdplus configuration folders,
  and a `keydb.cfg` import dialog.
- **Radio-Browser.info directory** in the Internet section of the sidebar:
  browse the community webradio database by continent and country, the
  stations of a country being fetched only when it is unfolded. Station
  lists are cleaned up — names trimmed, duplicates removed, sorted
  alphabetically with the **best quality first among same-named stations**
  (multiple relays of national radios), and every entry carries its
  codec/bitrate in the Description column. Broken stations are filtered
  out by the API, fetches are retried over the directory mirrors, and a
  failed discovery shows a self-explaining entry instead of a silent empty
  list — selecting the service again reloads it in the background.
  Country fetches get a generous explicit timeout (the core preparse
  default of 5 seconds silently killed the biggest countries), and a
  country left empty by a failed fetch is retried when unfolded again.

### Improvements — all platforms (modern machines included)

- Rebased onto upstream VLC **3.0.24** (982 commits of fixes and
  improvements from the upcoming release).
- **FFmpeg 4.4 → 8.1.2** on every target — newer decoders and years of codec
  fixes, including on the legacy PowerPC/i386 builds thanks to rebased
  AltiVec/H.264 patches.
- DVD libraries updated to the new-generation releases: **libdvdcss 1.6.0,
  libdvdread 7.1.1, libdvdnav 7.0.0**.
- **libbluray 1.5.0** and **libaacs 0.12.0**, with parsing of the richer
  disc metadata the new libbluray provides; fontconfig 2.16.0, dav1d 1.5.x
  and many smaller library bumps.
- Linux AppImages now bundle the contrib **FFmpeg 8.1** (static) instead of
  linking the distribution's ancient FFmpeg 3.4 — same codec coverage (AV1
  film grain, APV, ATRAC9, …) as every other target.
- All new PowerVLC strings translated/propagated to the **105 shipped
  languages** (a batch of fork strings that had been written in French was
  also anglicized, with translations for the most common languages).
- PowerVLC now **introduces itself as PowerVLC**: HTTP requests carry
  `PowerVLC/1.1.0 LibPowerVLC/1.1.0` instead of VLC's user agent, the
  application id is `com.github.PowerVLC`, and the icon name and the
  Last.fm client string follow suit. Servers that log or gate on the player
  are no longer told this is VLC 3.0.24.
- Unbrowsed directories (radio directory countries, file-browser folders)
  now show their disclosure triangle right away in every interface, and
  load their content when unfolded — no need to enter them once first.
- **Stream titles no longer erase curated names**: an entry named by a
  playlist or an on-line directory keeps that name when the stream
  announces its own title (ICY names are often raw mount points), shown as
  "Name ||| stream title" — so the playing station stays recognizable, and
  still matches the search filter.
- Keyboard navigation in the playlist works everywhere: Left/Right fold
  and unfold nodes in the modern macOS interface, and the legacy interface
  gains full arrow-key navigation plus **Return to play the selection**.
  The keys keep controlling DVD menus whenever the video has focus.
- Items appended while a search filter is active (a radio directory still
  loading) are now filtered like the rest, and a failing stream can no
  longer make playback fall back on entries the filter hides.
- Services discovery trees mirror an external source and can no longer be
  reordered by drag and drop; dragging their entries out, to the playlist
  or the media library, still works.

### Fixes — all platforms (modern machines included)

- **BD-J Blu-ray menus finally work**: fixed a process race, the JVM library
  lookup, fontconfig setup, and restored the resource loading that modern
  JDKs (18+) broke by removing the Java security manager.
- The **look-ahead cache never engaged** after a decoder restart (every DVD
  and Blu-ray title change): fixed, raising the decode cushion from 26 to
  79 frames — Blu-ray H.264 1080p now plays with zero dropped frames even
  on a MacBook 2007.
- Fixed an instant-fallback path in Blu-ray subtitle blending during
  hardware decoding ("no matching alpha blending routine").
- Raw-device Blu-ray disc access on Mac OS X, bypassing Snow Leopard's
  2 KB-per-read UDF ceiling that throttled high-bitrate discs.

### New features — legacy Macs

- **Mac OS X 10.2 "Jaguar" and 10.3 "Panther" support**: minimum system
  lowered from 10.4 to 10.2.8 — interface, video, audio and DVD playback
  are functional (new `jaguar-compat` runtime shims: dlcompat, libc and
  Objective-C compatibility layers), with a dedicated Jaguar application
  icon. Hardware-accelerated DVD decoding works on 10.2 with ATI GPUs.
  The port includes the hardening these systems needed to be reliable:
  interface language detection, robust Stop/playlist buttons (audio-flush
  deadlock, stale video surface on 10.3), and quitting without freezing.
- **GPU motion-compensation offload** for progressive DVDs on G3/G4 (ATI
  `DVDDriver` backend): about one third less CPU during playback.
- **DVD subtitles composited by the GPU** (hardware subpicture plane), on
  by default on the accelerated path.
- **AV1 with AltiVec** on G4 (dav1d PowerPC SIMD port, with a runtime guard
  so G3 machines keep working).
- BD-J interoperability jar rebuilt as **Java 5 bytecode**, keeping Blu-ray
  menus possible on period JVMs (a Java 5 API index is vendored under
  `contrib/java5-api/`).
- **Extensions support, including the extensions browser to download new extensions straight from PowerVLC**

### Improvements — legacy Macs

- Accelerated DVD playback polish: interface raised to 25 fps, A/V sync
  tightened from 75 ms to 20 ms, flicker eliminated, instant fullscreen
  toggle.
- H.264 on PowerPC: new AltiVec loop-filter, chroma motion-compensation and
  reference-prefetch routines plus an inlined CABAC decoder; smooth 720p
  H.264 validated on a Mac Mini G4.
- i386 builds: inline assembly and the full FFmpeg x86 SIMD re-enabled
  (about +25 % H.264 decoding speed).
- Removed a redundant staging copy in the cache path (~11 % CPU back on G4).

### Fixes — legacy Macs

- Fixed the hardware DVD player path and cursor hiding in the legacy
  interface.
- Stop/playlist button reliability hardening (the audio-flush deadlock
  work) also covers Mac OS X 10.4.
- Fixed a minutes-long interface stall when folding a playlist node with
  thousands of entries (quadratic behavior in the outline view's row
  bookkeeping).
- Fixed the Title column being duplicated when toggling the optional
  playlist columns.
- The playlist search filter is now honored by playback advance, exactly
  like the other interfaces.
- The playlist selection survives list refreshes (station lists loading,
  metadata updates), keeping keyboard navigation usable throughout.
- **No more frozen quit while a webradio plays on Mac OS X 10.2/10.3**:
  tearing an HTTP/2 connection down joins its receive thread, which these
  ancient pthreads cannot wake — they have no cancellation point in
  poll(), and a local socket shutdown does not wake select() either — so
  the quit hung until the server dropped the connection minutes later.
  The receive thread now waits on VLC's interruptible poll and the
  destructor interrupts it deterministically, on every platform; HTTP/2
  stays enabled.

### Fixes — Windows

- **The 32-bit build now actually starts on Windows XP SP3.** It has claimed
  that floor since 1.0.0 but never ran there: the core library imported
  `_putenv_s`, one of the "secure CRT" functions that only reached
  `msvcrt.dll` with Windows Vista, and Windows refuses to load a binary
  whose imports it cannot resolve. The same class of imports was removed
  from libcaca, librist, libupnp and libarchive, whose plugins had been
  quietly unavailable for the same reason.
- **Sound on Windows XP.** DirectSound asks for a 6 MiB playback buffer, a
  size some drivers accept at creation and then refuse to play — leaving
  the machine silent while the log fills with one
  `cannot start playing buffer` per audio block. PowerVLC now negotiates
  the size, halving it until the device agrees to play (768 KiB on the
  machine this was found on). Machines that are happy with 6 MiB are
  unaffected. Reproduced identically on stock VLC 3.0.23: the 6 MiB buffer
  has been upstream since 2013.
- **Plugins that could not load on Windows XP now do**: the XML reader —
  and with it the media library, which silently failed to open — plus
  libbluray, libass and the archive stream extractor. They pulled in
  Vista-only entry points: `bcrypt.dll` (the CNG crypto API, used by
  libxml2 and libarchive merely to seed a random number), libxml2's
  `InitOnceExecuteOnce`, and the `_mkgmtime32`/`_mkgmtime64` time
  functions, which unlike `_fstat64` Windows XP does not provide.
- **The Windows installers were debug builds.** The release flag was
  missing from the packaging call, so assertions were live: quitting
  PowerVLC on XP raised a "Microsoft Visual C++ Runtime Library — Assertion
  failed" dialog. All three Windows targets are now built in release mode,
  which also removes the debug overhead from playback.

### Build & packaging

- Full multi-target build validated: 7 macOS slices (arm64, x86_64, i386,
  G3, G4, G4e, G5), the universal bundle with its legacy trampoline,
  Windows 32/64/arm64 NSIS installers, and Linux AppImages
  (aarch64, x86_64, i386) built through Docker from a single machine.
- Contribs switched to the upstream 3.0.24 recipes, with all PowerVLC
  patches re-ported on top, then rebased again onto the current upstream
  3.0.x tip (libgcrypt 1.12.2, a CEA-708 closed-caption parsing fix).
- Icons and the application identity renamed from `vlc` to `powervlc`
  throughout — icon files, desktop entries, the Windows resource and the
  AppImage.
- Only `COPYING` is shipped at the root of the Windows install now.
  AUTHORS, THANKS, NEWS and README were informational copies that nothing
  read: the About window builds its text from those files at compile time.
- Dozens of contrib build fixes for the legacy toolchains: pre-10.7
  availability guards across gnutls, srt, gcrypt, libnfs, libass and
  friends, CMake cross-probe fixes for the GCC PowerPC/i386 compilers,
  and hardened Docker build scripts (image reuse, in-tree nasm).

## 1.0.0 (2026-07-26)

Initial public release: VLC 3.0.x brought back to Mac OS X 10.4 Tiger and
PowerPC (G3/G4/G5) alongside modern Macs, with the rewritten Legacy
interface, **gapless audio playback** and the **look-ahead cache** (both
benefiting modern machines too), accelerated DVD playback groundwork,
Blu-ray (libaacs) support, and experimental Windows/Linux builds.
