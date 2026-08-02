# PowerVLC Changelog

PowerVLC is an unofficial fork of VLC 3.0.x universally compatible with more legacy systems, not affiliated with VideoLAN.

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
