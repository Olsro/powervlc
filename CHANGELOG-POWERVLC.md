# PowerVLC Changelog

PowerVLC is an unofficial fork of VLC 3.0.x universally compatible with more legacy systems, not affiliated with VideoLAN.

## 1.3.2 (2026-08-22)

### PowerPC performance

- **dav1d now exposes its complete big-endian AltiVec decoder on G4/G5.**
  Refreshed `powerpc-ports` patches fix the 32-bit dispatcher, stack alignment
  and Wiener byte shuffle. All 658 AltiVec checks pass on a 1.42 GHz Mac mini
  G4; an AV1 848x480 decode uses 11.1% less CPU time and rises from 69.8 to
  78.4 fps.
- **x264 encoding is AltiVec-accelerated on G4/G5 instead of being forced to
  C.** Its restored big-endian backend passes all 8- and 10-bit checkasm
  families. On the same G4, a mono-threaded medium-preset encode rises from
  10.27 to 20.08 fps (1.96x) while producing a bit-identical H.264 stream.
  G3 builds retain the scalar path.

### Capture on Mac OS X 10.2 to 10.6 and fixed on the Legacy UI

- **Capture devices are available again throughout the supported macOS
  range.** The Open Capture panel now lists cameras, capture cards and audio
  inputs instead of a permanently empty menu, opens the device selected by
  its stable system identifier, and can add a microphone or line input to a
  camera or screen capture. It chooses the capture API that the system has:
  AVFoundation on recent macOS, QTKit on Leopard through Snow Leopard, and
  QuickTime Sequence Grabber on 32-bit Jaguar, Panther and Tiger. These last
  three releases can therefore use the same Open Capture workflow despite
  predating the modern capture frameworks.
- **Audio capture is reliable alongside legacy video capture.** On Mac OS X
  10.2 through 10.6, the interface uses Sequence Grabber for a separate audio
  input rather than opening a competing QTKit audio graph. Its delayed audio
  callbacks are now accepted, their clock is aligned with the video capture
  clock, and 16-bit PCM is exported in the byte order expected by recordings.
  This restores sound to camera and screen captures and keeps it synchronized
  with the picture.
- **QTKit capture tolerates the older implementations actually shipped by
  Tiger.** Methods advertised by newer SDK headers are checked at runtime;
  when timestamps or frame-rate controls are unavailable, capture uses VLC's
  monotonic clock instead of crashing the capture thread.
- **Webcam colours are correct on big-endian PowerPC Macs.** The zero-copy
  OpenGL 1.1 path treated QTKit's `2vuy`/UYVY frames as YUY2, producing a
  green and magenta picture on G3 and G4 systems. Packed YCbCr texture order
  now follows the target's endianness without adding a CPU conversion. The
  fix was validated with an AUKEY PC-LM1E USB webcam on a Mac mini G4 running
  Tiger.
- **The Capture panel and its device discovery are now Jaguar-safe.** Device
  names use CoreFoundation conversions available on 10.2, QuickTime remains
  initialized while devices are enumerated, and the panel avoids the workspace
  APIs that crash during Jaguar startup. It also always refreshes the selected
  tab, preventing a stale capture URL from being opened.

### Extensions and adaptive streaming

- **Live HLS streams stay smooth when a new segment arrives on single-core
  Macs.** The background downloader no longer competes with the real-time
  video output at the same fixed scheduler priority while decrypting TLS
  bursts. On a Mac mini G4 playing Pluto TV, this removes the regular dropped
  frames previously seen at every five-second segment boundary while keeping
  the decoded-picture and network buffers full.
- **Standing stream-quality choices are saved immediately.** Choosing
  Automatic, Lowest, Highest or a resolution ceiling now survives a crash,
  forced quit or indefinitely running TV stream; only an individual
  playlist's exact-bitrate pin remains intentionally temporary.
- **Invidious can now choose a dubbing track before playback.** When YouTube
  exposes several audio tracks, the video dialog lists them (with the
  original/default track first) and starts the selected one alongside the
  chosen resolution. This works with both the Invidious API and its HTML
  fallback, including DASH manifests with one adaptation set per language.
- **Invidious subtitles can now be chosen before playback.** Captions from
  the API and from the HTML player fallback are listed in the dialog and are
  passed to the player as an external subtitle track. URLs with HTML-escaped
  characters or literal spaces are normalised before opening.
- **Changing to a selected audio stream in adaptive media no longer leaves
  playback silent.** A newly selected, previously disabled stream is now
  reactivated, positioned and primed before normal buffering priorities can
  abandon it. DASH indexes needed by that stream are also read up front, so
  the first media segment is available immediately.
- **Copy Link now copies the quality actually selected.** A per-resolution
  adaptive video entry copies its own stream URL; the untouched DASH choice
  still copies the manifest URL.

### Fixes — playback and video output

- **Fullscreen follows live display-mode changes on legacy macOS.** Tiger can
  keep reporting the previous `NSScreen` size after a resolution switch, so a
  1440×900 desktop changed to 1024×768 still produced a 1440×900 fullscreen
  window. PowerVLC now takes the current geometry from Core Graphics for its
  video windows, black secondary screens and fullscreen controller, and also
  keeps automatic video resizing inside the newly visible desktop.
- **The mouse wheel changes volume while it is over the video again.** The
  OpenGL view used by G4/G5 Macs and the QuickTime/QuickDraw view retained for
  G3 and old Intel Macs now pass wheel events to the legacy interface's volume
  handler, including its on-screen feedback.
- **Seeking while paused reliably shows the new picture.** A picture still
  in flight before the seek could consume the single frame requested after a
  decoder flush; with direct rendering, the decoder could also be blocked by
  every display buffer held by the paused output. The flush now releases only
  obsolete queued frames, arms the post-seek picture at the right moment and
  makes the video output present it immediately. This restores reliable
  seek-bar previews and frame-accurate clip trimming while paused.
- **VDA H.264 decoding is more stable on older NVIDIA Macs.** VDA callbacks
  now retain only CoreVideo buffers and are delivered on VLC's decoder thread,
  rather than allocating output pictures from Apple's private callback thread.
  The compressed input stays alive until the asynchronous driver has finished
  with it, fixing a use-after-free seen on Snow Leopard; flushes and format
  changes also reject racing callbacks safely. Frames retain their display
  order and the zero-copy path remains in use.
- **Automatic black-bar cropping works with VDA's native UYVY output.** It
  now reads the luma bytes from packed UYVY directly instead of requiring a
  conversion that the CoreVideo path cannot perform, preserving hardware
  decoding and its low CPU use.
- **Hardware video picture pools no longer ask old allocators for a zero-byte
  buffer.** Opaque CoreVideo pictures have no CPU planes by design; avoiding
  that allocation fixes the allocator corruption seen when a full hardware
  picture pool is created on older macOS.

### Fixes — Windows

- **Portable builds no longer become extremely slow to open after repeated
  launches.** Their self-healing plug-in cache was saved with no entries, so
  PowerVLC scanned and loaded every plug-in DLL again on every startup; on
  some Windows 11 systems this delayed the main window by up to a minute. The
  complete cache is now written after the first scan and reused thereafter.

### Fixes — macOS integration and compatibility

- **Audio output recovers automatically after waking a legacy Mac.** The
  legacy interface restarts the output device on wake, addressing CoreAudio
  drivers that did not resume their render callback after sleep.
- **The About window reports the installed bundle's version consistently.**
  Both Mac interfaces take the product version, core version and build date
  from the application bundle, with the compiled values as a fallback. A
  universal application can no longer show an old version in one incrementally
  rebuilt architecture slice.
- **Modern Apple toolchains and older deployment targets build more
  reliably.** The VDA plugin keeps the module-name symbol visible while the
  current linker combines its helper objects, and the CoreVideo-to-CoreVideo
  transfer module is omitted where its VideoToolbox API is unavailable.
- **The PowerVLC icon appears on Jaguar in the universal application bundle.**
  The universal icon now contains only the classic representations Jaguar can
  read; newer icon formats previously made Finder fall back to a generic icon.

## 1.3.1 (2026-08-15)

### Fixes — all platforms

- **Recording and clip export: a cut landing on an open-GOP key frame gave
  a degraded picture.** Modern encoders open a group of pictures with a
  frame that is followed, in the order pictures are decoded, by pictures
  that are *shown before it* and that reference the past. The capture cut
  those away by timestamp, which was right for them but took the first
  full picture of the new group with them — everything referencing it then
  decoded to rubbish until the next key frame. Measured on an HEVC clip
  cut at such a frame: 175 of 403 pictures unusable, seven seconds of
  visibly broken video. The buffer is now cut where the key frame actually
  sits in the stream, not by timestamp.
- **The exported clip now holds the tracks you are watching.** The fast
  clip export ran a second, headless input, and an input that writes to a
  file selects *every* track of the media: the clip carried all the audio
  tracks of the file and players opened whichever one was flagged as the
  default, never the one being played, and the pile of tracks pushed the
  container choice onto a fallback that mangled H.264 timestamps. The
  export now names the playing video, audio and subtitle tracks
  explicitly, so the clip has exactly them — and lands in a container that
  fits (MP4/TS rather than ASF).
- **Subtitles are exported with the clip.** Embedded text subtitles ride
  along as a track; external subtitle files (the usual movie plus `.srt`)
  are now attached to the export as well, which the copied input had been
  dropping. Picture-based subtitles from Blu-ray remuxes (PGS) and DVDs
  (VOBSUB) are carried too — see the Matroska entry below.
- **An exported subtitle is now selected when its clip is opened.** The
  export already keeps the subtitle that was playing, but Matroska files
  did not say that it was the default track. The player opening the clip
  could therefore leave subtitles off. That selected track now carries the
  container's default-track flag; ordinary recordings and clips without a
  subtitle are unchanged.

### Recording and clip export

- **Recordings and clips can now be written as Matroska**, and it is what
  they use whenever no other container fits. That is what finally lets a
  clip keep its subtitles: styled ASS/SSA, Blu-ray PGS bitmaps and DVD
  VOBSUB images are copied across untouched, where before every one of
  them was dropped in silence. It also rescues the raw PCM soundtrack of a
  Blu-ray remux, which used to drag the whole recording down to AVI or
  ASF. Nothing is re-encoded.
- **A subtitle track could be left out of a recording entirely.** The
  container is decided as soon as the buffer fills, and on a 26 Mbit/s
  remux that happens six seconds in — long before a subtitle first has
  anything to say. The decision now waits for the tracks the player knows
  it selected, and a track that still turns up too late is reported rather
  than dropped without a word.
- **Pictures went missing from Matroska recordings, then stuttered once a
  second.** libavformat drops a picture whose decode timestamp does not
  advance, and the timestamps VLC carries for a straight copy are not
  reliably ordered: on an H.264 Blu-ray remux that cost 108 pictures out
  of 1339, three at every key frame. Pushing the offending timestamps
  forward brought the pictures back but crammed three of them into three
  milliseconds at each key frame — a visible hiccup every second. The
  decode order is now rebuilt from the presentation times themselves, so
  a recording keeps every picture *and* shows each one exactly when the
  source does.
- Where a clip can begin on a picture that resets the decoder, it now
  does, which removes the last two mis-predicted frames at the very start.
  On material whose reset points are minutes apart it stays where it is
  rather than throw away what was asked for.

### Extensions

- **Invidious: the two halves of a high-definition download are now put
  back together by the player itself.** Above 720p YouTube serves the
  picture and the sound separately, and combining them used to mean
  ffmpeg — a program to install, a script written next to the files and a
  terminal window opening on it. The Matroska output added in this
  release takes every pair YouTube serves, H.264+AAC as readily as
  VP9+Opus, so the *Combine* button now does the work in place, without
  re-encoding, at disk speed, and without interrupting whatever is
  playing. Progress is shown while it runs, and the ffmpeg route is gone
  entirely — nothing is written next to your files any more.
- **Invidious: “this extension is not responding” during a download.**
  YouTube hands each connection the stream at the speed it would be
  played at, so on a soundtrack — a quarter of the bitrate — a single
  read takes over two seconds, and a full turn of the eight connections
  nearly twenty. The extension only claimed to be alive once per turn,
  which is twice the ten seconds after which the player offers to kill
  it. It now says so before every read, and hands the thread back as soon
  as its share of it is up rather than at the end of a turn.

### Fixes — disc menus

- **Blu-ray discs were always told the user speaks English.** A disc does
  not pick its own menu language: the player declares a preference and the
  disc branches on it. DVDs have been told the interface language since
  1.2.0 when no preference is set; Blu-ray never was, so a French disc took
  its English branch and its BD-J menus came up in English on a French
  install. It now answers the same way a DVD does. An explicit "Menu
  language" preference still wins, as before.
- **On Windows the interface language was invisible to discs.** The
  launcher only exports it to the environment when a language has been
  picked by hand; left on automatic — the default — the interface gets its
  language straight from Windows and the environment stays empty, so discs
  fell back to English even though the menus, buttons and dialogs were in
  French. Discs are now told what Windows says the user reads. Linux and
  macOS already carried it in the environment and are unchanged.
- **Blu-ray menu graphics could disappear when the display could not
  compose them itself.** The software compositor advertised two packed
  pixel layouts that it cannot actually blend, so a menu delivered in one
  of them was accepted and then silently discarded. Such menus are now
  converted to a supported layout before blending; they also remain
  present in snapshots.
- **Choosing whether to run disc menus is now explicit on macOS.** Both
  the modern and legacy Open Disc panels have separate *DVD menus* and
  *Blu-ray menus* checkboxes. The Blu-ray choice follows a preference but
  can still be overridden for one disc, and the interfaces now make clear
  that BD-J menus can occupy a processor core. The Qt Open Disc panel
  carries the same warning.

### Fixes — DVD playback

- **DVDs played without menus now use the disc's actual timeline.** The
  old reader estimated time and seeking from the number of sectors, an
  assumption that drifts on variable-bitrate titles and counts alternate
  camera angles more than once. Elapsed time, total duration, the seek bar
  and the requested seek position now share the timestamps and cell path
  recorded on the disc. Chapter separators consequently appear at their
  real times and remain in agreement with the chapter named in the seek
  tooltip.

### Fixes — hardware decoding on legacy Macs

- **Fixes related to accelerated DVD playback (ATI)** It should work better, but still need more attention
- **CrystalHD no longer freezes interlaced MPEG-2 video after a seek.** A
  flush that occurred between the two fields of a picture left the
  decoder permanently waiting for the missing field while audio carried
  on. The pending-field state is now reset with the hardware buffers.

### Fixes — Windows

- **Blu-ray discs can now be read on Windows XP.** XP's UDF driver stops at
  version 2.01 and a Blu-ray is 2.5, so the disc never mounts: Explorer
  shows an empty drive and the player could not open it either. The data
  was always readable — the player carries its own UDF reader — it simply
  had to be pointed at the raw volume instead of at a mount point that
  does not exist. A drive that refuses to open the ordinary way is now
  retried that way, which also brings AACS and BD-J with it. Windows Vista
  and later mount the disc themselves and are unaffected.

### Fixes — Windows and Linux (Qt interface)

- **The hover preview never appeared on a subtitled media.** The picture
  is produced by a silent second reader writing a PNG, and that reader was
  told to leave subtitles out — with the switch that governs playback, not
  the one that governs a file being written. So a media whose subtitle
  track is flagged as default, which is to say an ordinary film, had that
  track written into the file *in front of* the picture, and the image
  loader refused a file beginning with a line of dialogue instead of a
  PNG. The macOS interfaces were spared because their image loaders skip
  ahead to the picture. The reader now leaves subtitles out for real, and
  the loader starts at the picture whatever precedes it.

### Clip creation mode

- **A held step key now accelerates.** Nudging a clip bound by one frame
  is the right amount for one press, but on a twenty minute film a frame
  is a fortieth of a pixel on the seek bar — holding the key looked like
  it did nothing. The step now stays at one frame for the first presses,
  so a tap is still exact to the frame, then climbs gradually — a frame at
  a time at first, up to twenty-five frames a press — while the key stays
  down, and returns to one frame as soon as it is released. Three seconds
  of held key travel about half a minute of media. All three interfaces
  get this from the core.

### Fixes — legacy interface (macOS)

- **The separate video window's seek bar was a plain one.** It showed no
  chapter separators and no live tooltip, while the same bar in the
  playlist window and in the fullscreen controls showed both. It is now
  the same seek bar everywhere: chapter separators, hovered time, chapter
  name, preview thumbnail, and the two clip-creation knobs.
- **The separate video's time and chapter controls now match the main
  window and fullscreen controls.** The right-hand field shows elapsed
  time by default, changes between elapsed and remaining time when
  clicked, and opens *Jump to Time* on a double-click with the current
  time already filled in. Chapter information is retried when a DVD makes
  it available late, unnamed DVD chapters receive the usual generic
  names, and the hover tooltip remains visible and correctly tracked
  after resizing or changing window mode, including on Panther.
- **Window shadows are now optional.** They remain enabled by default on
  machines with AltiVec, but are disabled by default on G3 systems where
  measurements showed lost displayed frames. The legacy preference takes
  effect immediately; an active ATI video session keeps the window shape
  required by its hardware overlay.
- **The separate video window offered the system's own fullscreen.**
  macOS grants it to any resizable window, and this one fought with the
  player's own fullscreen. Refused, like the other windows of this
  interface already did; the green button zooms again, and the player's
  fullscreen is unaffected.
- **Fullscreen left a strip of desktop along the bottom of the screen.**
  Hiding the menu bar changes the screen layout, and macOS answers by
  nudging the window back down into what it thinks is the visible area —
  by exactly the height of the menu bar it has just hidden. The window
  accepted the nudge; it now holds its ground, and the picture reaches
  the bottom edge again.
- **Opening the fullscreen controls could crash on Tiger.** Its AppKit
  advertises the cell line-breaking selector used for the media title but can
  dereference an invalid internal object when it is applied to a newly created
  text cell. Tiger now uses the same safe single-line clipping fallback as
  Panther and Jaguar; Leopard and later retain ellipsis truncation.

## 1.3.0 (2026-08-13)

### New features — all platforms (modern machines included)

- **Clip creation mode**: cut a piece out of what is playing, without
  re-encoding it and without leaving the player. It is entered from the
  playback menu right below Record (⌘⇧C on the Macs) and turns the seek
  bar into a pair of knobs — one holds the start of the clip, the other
  its end — while a thin marker keeps following the playback position.
  Moving either knob seeks there, so what you set a bound on is what you
  see; dragging between them scrubs without touching the bounds. The
  jump shortcuts and the bare arrow keys resize the selected bound
  instead of seeking, one frame at a time for the short steps and by
  their configured size for the long ones, so a clip can be framed
  exactly. Playback pauses when it reaches the end bound and replays the
  clip from its start when you press play again. Record then writes
  exactly that range — and writes it as fast as the disk allows, through
  a second headless input instead of playing the clip through at normal
  speed: a minute of video lands in a fraction of a second, and the
  playback you are watching is not disturbed at all. Discs (which are
  driven by titles and menus, so a second reader would restart in the
  menu) and media that cannot be seeked or whose length is unknown (live
  streams) are still recorded as they play, at normal speed.
  The fullscreen controls carry the same seek bar, so a clip can be
  framed, previewed and recorded in fullscreen exactly as in a window.
  Dragging a bound previews it as you go: the picture follows the handle
  at a steady ten frames a second, and a single pixel nudge — what
  trimming to the frame is made of — is shown too, instead of being
  swallowed until the button is released.
  Getting the first and last frames right took work down in the core:
  the seek and the start of the recording are now a single input control
  (a seek is refused while recording, and in the other order the demuxer
  runs between the two and the key frame the clip should open on is
  already gone); that seek is deliberately imprecise, because a precise
  one makes demuxers swallow everything between the preceding key frame
  and the target, which is up to a whole GOP of what the user framed;
  the recorder then starts at the last key frame at or before the bound
  rather than the first one it happens to see; and the end bound is
  crossed by the *demuxer*, not by the playback clock, which would
  overshoot by the whole buffering lead.
  Two recording fixes came out of it, and they apply to plain recordings
  too: a clip that starts exactly on a key frame no longer opens on a
  black second (the recorder aligned every stream on the *latest* first
  block, which let an audio stream starting a few milliseconds later
  push the start past that key frame — the whole leading GOP was then
  dropped, and the picture only came back at the next key frame), and
  recordings are now named `powervlc-record-…` instead of `vlc-record-…`.
- **Dragging the picture moves the window**, in all three interfaces,
  whether the controls are showing or not. A maximized or fullscreen
  window stays where it was put.
- **Clicking the seek bar lands on the time the tooltip announced.** Both
  macOS interfaces drew their own knob but let AppKit turn a click into a
  position, and AppKit measures that with a knob width of its own: the two
  disagreed by a couple of pixels, which on a 1h30 media meant a seek
  landing up to 17 seconds away from the hovered time (measured: tooltip
  07:39, playback 07:48). The seek bars now convert the click themselves,
  with the same formula that draws the knob and fills the tooltip.
- **Hide controls during playback** (aka Picture-In-Picture), in all three interfaces (Video >
  Hide Controls During Playback, ⌘⇧H or Ctrl+Shift+H, off by default).
  A few seconds after the mouse has left the window during windowed
  playback, the controls bar and the window title bar go away and the
  window shrinks onto the picture itself, which keeps its exact size and
  position on screen — a bare rectangle of video, with no black bands
  and nothing else. A double click on the video brings everything back.
  The window has no frame left for the window manager to grab, so a drag
  started in a corner resizes it (the picture's ratio kept, the opposite
  corner anchored) and a drag anywhere else moves it. Keyboard shortcuts
  keep working meanwhile and now draw the fullscreen-style OSD sliders
  for position and volume: the core shows them whenever the video is the
  only thing on screen, which used to mean fullscreen only.
- **Hovering the seek bar shows a preview of that moment**, in all three
  interfaces, in the tooltip that already carries the hovered time and
  the name of the chapter it falls in. VLC 3.0 has no thumbnailer of its
  own, so the frame is decoded by a second, silent input on the same
  file, whose stream output re-encodes it to a temporary image; requests
  wait for the mouse to settle, only the latest one is served, results
  are cached, and network streams are excluded (a preview would open a
  second connection to the server). Discs are excluded too, and by more
  than their scheme: a disc dropped from the file manager is the mounted
  volume, so a preview would have set a second reader loose on the
  drive — they are recognised by their tree (a folder holding VIDEO_TS
  or BDMV, which covers a disc copied to a hard drive), by their disc
  image extensions, and on the Macs by a UDF or ISO 9660 mount. It can
  be turned off from the
  interface preferences — and is off by default on the PowerPC builds,
  where that extra decode is taken out of the playback. The legacy Mac
  interface gets the same thing written to a Jaguar floor: no GCD, no
  blocks, no NSCache and no tracking areas — one worker thread at a time
  and a tracking rectangle with a 10 Hz follow timer.
- **An up-to-date list of root certificates is shipped and trusted
  alongside the operating system's own.** The systems this fork targets
  do not fail HTTPS for lack of a trust store — Windows XP has one that
  gnutls reads perfectly well — but because that store stopped being
  updated years ago and knows nothing of the roots today's web signs
  with, ISRG Root X1 (Let's Encrypt) first among them. The bundle is
  therefore added to the system store rather than used as a fallback for
  it, which is what the old code did and which never ran on XP.
  `--no-gnutls-bundled-trust` restores the strict system-only behaviour,
  since a root an administrator removed from the system store does come
  back this way. The bundle is refreshed by a script that is run
  deliberately and never from the build: a build that downloads its own
  trust anchors is no longer reproducible.
- **Automatic cropping of the black bars**, as a new *Automatic* entry at
  the top of Video > Crop (`--crop=auto` on the command line). The bars
  are measured on the picture itself, a few times a second, and cropped
  away without touching a single pixel of the decoded frame: it is the
  same zero-copy crop the ratio entries below it use, so it costs
  nothing to display and works on every video output, down to QuickDraw
  on Mac OS X 10.2. The measurement is HandBrake's — a row or a column
  counts as a border only when its average luma is dark *and* every one
  of its samples sits within sixteen of that average, which is what
  separates a flat mat from a dark night scene — taken over a rolling
  window of frames rather than a single one, so a fade through black, a
  title card or the credits cannot drag the decision with them. The
  first crop lands about eight tenths of a second after the picture
  does, and is corrected once, to the pixel, when enough frames have
  been seen. From then on the decision is taken over half a minute of
  samples: a scene that happens to be dark right up to the mat measures
  a wider mat, and over a short window that was enough to make the
  picture resize in the middle of a scene. Cropping *more* than what is
  already in force is refused outright unless every single sample of that
  window agrees, since that direction is what a dark scene produces --
  a night sky over a 4:3 programme reads as a wider mat and takes the
  picture with it until the daylight comes back. Cropping less goes
  through at once: that direction means picture is being cut. Content
  whose aspect ratio genuinely changes mid-programme is still followed -- a television
  channel going full frame for its advert break loses the crop within
  seconds, and gets it back the moment the programme's own mat returns,
  which is recognised as one this source has already worn rather than
  having to win the half-minute vote again. A two-pixel disagreement is
  never acted on, since every change moves the window. Hardware-decoded pictures (VideoToolbox, and any other
  opaque surface) are measured too, through a conversion done only on
  the frames that are actually sampled.
- **A custom crop ratio and a custom aspect ratio can be typed in**, from
  a *Custom* entry at the bottom of Video > Crop and Video > Aspect ratio
  in all three interfaces — a backport of VLC 4.0's panel. What is
  entered is applied at once, added to the menu so it can be picked again
  without retyping, and kept for the next run in `custom-crop-ratios` /
  `custom-aspect-ratios`. The whole thing is typed at the keyboard: Tab
  walks from one side of the ratio to the other, and typing replaces what
  the field holds instead of inserting into it. Switching Video > Crop between *Default*
  and *Automatic* is remembered too, so the choice holds for the next
  video and the next run; a ratio picked from the same menu is not, being
  a decision about the video in front of the viewer rather than a lasting
  preference.

### Improvements — all platforms (modern machines included)

- **The Invidious extension now offers both cadences of a 60 fps
  upload** instead of one of them at random. YouTube publishes such a
  video at 30 and at 60 fps, the manifest lists both, and the quality
  menu kept whichever came first — which matters here, because 1080p60
  is H.264 level 4.2, past the Crystal HD's 4.1 ceiling: the card takes
  the stream, decodes under a second of it (56 pictures, measured) and
  stops dead, while 1080p30 of the same video decodes in hardware. Both
  are now listed, spelled out as "1080p — avc1 — 60 fps" rather than
  folded into the resolution, tallest first and the plain cadence before
  the high one — a choice for the viewer to make, on a machine that can
  carry it.
- **The Invidious extension downloads a video, and shows its
  thumbnail.** The video view now carries the picture in a column of its
  own, fetched from the connected instance and never from Google's own
  thumbnail host: the streams may have been routed through the instance
  on purpose, and a picture is not worth undoing that. Beside Play there
  is a Download button, which writes the quality currently selected into
  the Downloads folder under a name like "Title [1080p].mp4", so that the
  same video fetched twice at two qualities is two files rather than one
  overwritten. It moves on the extension's own timer in bounded slices —
  the window stays alive, a progress bar follows it, and the same button
  cancels it — and a transfer that stopped short of the length announced
  is thrown away instead of being left looking like a playable file.
  Above 720p, YouTube publishes picture and sound as separate streams and
  nothing here can mux them, so those qualities come down as two files
  and the closing message says which is which.
  The download opens **four connections at once**, each asking for its own
  quarter of the file and writing it straight into place. That is not a
  refinement: measured against a public instance, a single connection was
  served at a flat 211 KiB/s — 0.275 s for every 64 KiB read, with a
  regularity that rules out congestion — which is this video's own
  bitrate. The relay hands the file over at the speed it would be watched
  at, so a ten-minute video took ten minutes. The ceiling is per
  connection: the same download over four runs at 723 KiB/s and rising.
  No thread was needed for this. Every stream VLC opens already carries
  the `prefetch` filter, which reads up to 16 MiB ahead **on a thread of
  its own**, so four streams fill their buffers concurrently while the
  extension walks round them taking what has arrived. A server that
  refuses ranges is detected on the spot (the seek fails) and the
  download falls back to the single connection it always used — all or
  nothing, because half a set of slices would be a corrupt file. The rate
  is shown beside the progress bar.
  The pacing is per stream, at each stream's own bitrate — measured a
  second time on the audio track of that same video: 28 KiB/s a
  connection, which is exactly what that track is encoded at. An audio
  track therefore takes as long to fetch as the video it belongs to
  unless there are enough connections, so eight are opened, and the file
  is cut into twice as many pieces as there are connections: a small file
  then uses them all, and **a connection that drops puts what is left of
  its piece back in the queue** instead of leaving a hole. A tick is now
  bounded by the clock (250 ms) rather than by a byte count — 4 MiB is
  five seconds of a video stream and thirty-seven of an audio one, so the
  progress bar used to sit still for half a minute at a time on the
  second file, with Cancel stuck behind it.
- **The sound of a video can be downloaded on its own**, from a button of
  its own. The quality list already held "audio only" entries — but only
  in API mode; on an instance whose JSON API is closed, the list is built
  from the watch page and has none, even though every DASH quality in it
  names the audio track it would play as a slave input. The button looks
  in all three places, in the order that respects what was chosen: the
  selected entry when it is already a sound-only one, the sound that goes
  with the selected quality when that quality keeps picture and sound
  apart, and failing both, whatever sound-only stream the list holds. A
  video that only offers combined streams gets a message saying so rather
  than a button that pretends: pulling the sound out of a combined stream
  is a re-encode, which is the ffmpeg button's business.
- **The two halves of a high-resolution download can be put back together
  in one click.** Above 720p YouTube publishes picture and sound
  separately, and this player cannot mux them: its mp4 muxer takes H.264
  and AAC, and there is no matroska muxer in the bundle at all, so a
  VP9+Opus pair would have nowhere to go. Rather than half a feature, a
  button hands the job to **ffmpeg** — which the user installs, or does
  not. Nothing runs behind anyone's back: a script is written next to the
  files and a terminal window is opened on it, so the command, ffmpeg's
  own output and the "ffmpeg is not installed" case are all in plain
  sight. The output is Matroska, which takes every pair YouTube serves
  and cannot collide with either source file, and the streams are copied,
  never re-encoded. If no terminal can be opened the command goes to the
  clipboard instead.
- **Extension dialogs stop flickering.** In the Qt interface the window
  was resized once per widget added, updated or removed, and to a layout
  wish that collapses while a rebuilt widget is momentarily empty: the
  Invidious list of public instances snapped small and back a dozen
  times as it filled. The dialog is now resized once, at the end, and
  once on screen it only ever grows.
- **MPEG-2 video inside a `.mov` container plays.** The `m2v1` fourcc —
  what ffmpeg's own mov muxer writes — was in no table, so the file was
  opened and then played nothing at all. `m1v1`, its MPEG-1 counterpart,
  is recognised as well.
- **Hundreds of translated strings came back to life in every
  language.** A template regenerated through `make` on 2026-07-25 had
  dropped the Qt interface strings it could not extract, `msgmerge` had
  marked them obsolete across every catalogue, and `msgfmt` had stopped
  compiling them: those parts of the interface silently reverted to
  English in all of them. The French catalogue went from 735 obsolete
  entries to 260, and the other 104 followed. The remaining ones are
  genuine removals, listed and verified one by one. Sardinian, whose
  catalogue was in the tree but missing from `LINGUAS`, is built and
  shipped for the first time — 106 languages.

### Fixes — all platforms (modern machines included)

- **A DVD could start the film with a subtitle track nobody asked
  for** — on a region 2 disc carrying Arabic, English and three French
  tracks, playback began with the Arabic one, treated as forced-only.
  The disc had in fact selected no subtitle at all: libdvdnav answers
  "stream 0, hidden" both when a disc really asks for forced subtitles
  on its first track and when its subpicture register holds no
  selection, because the lookup then falls back to the first available
  stream. The register itself is now read — libdvdnav documents the
  field that carries it but only ever filled it for audio, so a patch
  fills it — and a track is auto-selected only when the disc really
  picked one, still forced-only when the disc says so.
- **HTTPS was impossible on Mac OS X 10.6 and 10.7, and the player
  blamed the server.** Those systems' own TLS stack stops at TLS 1.0,
  which every current server refuses — the handshake came back
  `errSSLPeerProtocolVersion` and the interface reported the site as
  unreachable while it was answering perfectly. That stack also had the
  highest priority, so it won the choice and took HTTPS down with it.
  Only the 64-bit Intel build was affected, and only when run below
  10.8: the PowerPC and 32-bit Intel builds never carried that stack in
  the first place, so they were already using the bundled one.
  PowerVLC now always speaks TLS through the copy of GnuTLS it ships:
  one negotiation everywhere regardless of the host system's age, and
  the up-to-date list of certificate authorities that travels with the
  player — plus the ones from the system keychain wherever it exposes
  them, so a privately added authority still works.
- **The player was killed outright the first time anything needed a
  stored password** on Mac OS X 10.6 — browsing a media server, for
  instance. The keychain plug-in is written against a runtime that only
  exists from 10.7, but it was built whenever the compiler understood
  the dialect rather than when the system could run it: loading it made
  the dynamic linker terminate the process. It is no longer built for
  those systems, which fall back to the portable password store.
- **A DVD's seek bar could stop telling the truth mid-film** — the
  remaining time jumping by minutes, the position knob freezing at the
  start or sliding back, the hover preview refusing to open, and clicks
  landing a minute away from what the tooltip promised. Underneath, the
  seek bar was reading two different rulers. Chapter markers and the
  hover tooltip are laid out in *time*, while the knob and seeking used
  libdvdnav's *sector* position — two measures that only agree on a
  constant bitrate. Worse, both of the library's answers are unusable on
  a disc with multiple camera angles: the sector position gives up
  entirely inside an angle block, and the running time counts such
  blocks twice (measured on one disc: 4:16 announced for a picture
  actually at 2:09). Everything now runs off a single ruler — the
  chapter table the markers themselves come from, re-anchored at every
  chapter boundary and every seek, with the clock filling in between —
  so the knob, the tooltip, the markers and where a click lands finally
  agree. Seeking to the very end also keeps a second in hand, so the
  disc still reaches the commands that roll the credits.
- **Discs were always told the viewer was an English speaker.** The
  language registers a DVD reads to choose its audio track, its
  subtitles and its menus fell back to English whenever the preferred
  language settings were left empty, which they are by default. They now
  fall back to the language the interface is running in, so a disc that
  branches on the viewer's language takes the right branch out of the
  box. An explicit preference still wins, and English remains the last
  resort.
- **An extension could vanish from the menu with a single line in the
  log.** Since Lua 5.2 `luaopen_string()` only returns the string
  library instead of also setting the global, so the scan pass that
  reads an extension's descriptor had `string` set to nil: any script
  touching `string.*` outside a function died on the spot and was never
  listed. That is what took the iTunes podcast extension away.
- **`--start-time` was ignored when recording or converting.** The seek
  was queued as a control, so the main loop had already demuxed the
  first blocks from position zero and the stream output — which nothing
  paces — had written them to the destination by the time it was
  applied. It is now performed synchronously, before any of that.
- **An imprecise seek in a fragmented MP4 lands on the fragment's key
  frame**, like the non-fragmented path already did, instead of
  swallowing every sample up to the target — the samples a bounded
  recording needs.
- **A crop no longer comes back late, or wrong, when a stream loops.**
  Every input format change tears the video output's display down and
  builds a new one, which crops nothing; the crop was only put back
  afterwards, from the interface variable, so each turn of a looping
  stream — an Invidious video on repeat, an adaptive stream that comes
  back at another quality — showed the uncropped frame for a moment and
  moved the window twice. The crop in force is now held by the video
  output itself and re-applied to the new display before it shows its
  first picture. A crop counted in pixels is dropped when the source
  comes back at a different resolution, where it would have cut the
  wrong place; the automatic detection remembers what it measured for
  each of the last four resolutions instead, and puts it straight back.
- **The video window grew until it filled the screen on an adaptive
  stream.** Every variant change reaches the interface as a request for a
  window the size of the new variant's pixels, which is indistinguishable
  from the request Video > Half/Normal/Double Size makes -- so the window
  followed it, one step up after another, until the screen stopped it.
  A scale change is now only followed when the vout's zoom factor
  actually changed, i.e. when the viewer asked for it; a stream changing
  resolution behind their back leaves the window alone. Both macOS
  interfaces.
- **The next item in the playlist inherited the crop of the previous
  one.** The automatic detection remembers the mat it measured so an
  adaptive stream that changes variant is cropped again straight away,
  and it scales that mat to a resolution it has not seen yet as long as
  the frame has the same shape -- which is exactly what put a film's
  2.39 letterbox on the 4:3 programme that followed it, black pillars
  and all. What was learnt is now dropped as soon as the video output is
  handed a different item; a crop set by hand still carries over, as it
  always did.
- **Fullscreen could leave part of the screen uncovered** in the legacy
  interface, with the controls auto-hidden: the auto-hide tick revealed
  them as soon as it noticed fullscreen, which laid the windowed frame
  back over the fullscreen one, and the video view was never resized to
  the enlarged window -- a Cocoa view keeps its origin at the bottom, so
  the picture sat on the bottom edge with a black band above it. The
  controls are now revealed *before* the transition, as the modern
  interface already did, and the view is given the window's bounds
  explicitly on the way in and out.
- **A click on the picture just after a click in the menu bar teleported
  the video window** (legacy interface, controls hidden). Dragging the
  picture moves the window, and the legacy path honoured *any* drag
  reaching the video view -- including the one that follows a click whose
  press had been swallowed by the menu tracking loop, which was then read
  as the continuation of whatever drag happened last and moved the window
  by the distance between two unrelated pointer positions. A drag is now
  only honoured between a press on the picture and its own release.
- **The video window could walk off the left of the screen on its own.**
  Dragging the picture moves the window, and the drag was measured from
  an anchor read with `+[NSEvent mouseLocation]` — where the pointer is
  when the event is *handled*, not where it was clicked. The interface
  thread does stall (an adaptive stream fetching its playlist is enough),
  and the window then jumped by however far the pointer had travelled
  meanwhile; the flag that says a drag is in progress was never cleared
  on mouse up either. The drag now follows the pointer's own deltas, and
  neither interface will let the window be dragged so far out that there
  is nothing left to grab it by.

### New features — macOS (both interfaces)

- **Chapters are marked on the seek bar** — main window, fullscreen
  panel and legacy interface alike, where the Qt interface already had
  them — whenever the media carries seekpoints with time offsets, with
  the chapter name in the hover tooltip. Media that numbers its chapters
  without naming them — most discs, and plenty of containers — gets
  "Chapter 1", "Chapter 2"… rather than a blank, in all four seek bars
  and in the same wording the Chapter menu has always used.

### Improvements — macOS

- **The window is no longer locked to the video's aspect ratio by
  default** in the modern interface: it resizes freely and the picture
  is letterboxed inside it, like the legacy interface and like every
  other player. Video > Aspect ratio > Lock Aspect Ratio puts the old
  behaviour back.

### Fixes — legacy Macs

- **Every film started with a few seconds of blocky rubbish** on the
  Intel Macs whose graphics chip has no video decode engine — a GMA950
  or GMA X3100 running 10.6.3 or later, where the decode framework
  exists but the chip behind it does not. Hardware decoding was
  offered, accepted, and only found to be unavailable once the decoder
  actually tried to start — at which point the whole decoder had to be
  swapped for the software one, which then picked the stream up in the
  middle of a group of pictures and drew broken frames until the next
  key frame. That happened at the start of every single file. The
  hardware is now asked once per session, before anything is committed
  to, so those machines go straight to software decoding and start
  clean. Machines that do have the engine are unaffected: only a plain
  "this hardware cannot do it" answer is taken as final, any other
  refusal leaves the previous behaviour alone. Verified on both — a
  GMA950 Mac mini and a GeForce 320M MacBook Pro, both on 10.6.8.
- **The screen could go to sleep in the middle of a film.** The core
  only hooked its screensaver inhibitor onto X11, HWND and Wayland
  windows, so on the legacy interface — whose window is an `NSObject`
  one — the inhibitor was never even loaded, and the module that pokes
  `UpdateSystemActivity()` for these systems never ran.
- **⌘ + a digit was dead on every non-US keyboard under 10.2 to 10.4.**
  When the digit row needs Shift (AZERTY, QWERTZ…), the event carries
  the unshifted character of the key, which matches neither a menu
  equivalent nor a core hotkey; modern AppKit falls back to an
  ASCII-capable layout for this, the AppKit of those releases does not.
  The window sizes (⌘0/1/2) and Fit to Screen (⌘3) are now matched on
  the layout-independent virtual key codes — verified on a French iBook
  under 10.2.8.
- **The legacy menu bar carries the same shortcuts as the modern
  interface**: Quit, Reveal in Finder, Find, Stop, Random, Fit to
  Screen, Fullscreen and Float on Top, with the items backed by a core
  hotkey showing the key that is actually configured.
- **Video > Float on Top did nothing.** The interface dropped the
  window-state query the core sends: the embedded picture lives in the
  main window, so floating above other applications is that window's
  level, not a property of a vout of its own.
- **An item dropped above another in the playlist was inserted at the
  bottom of the list.** AppKit falls back on a "drop ON" proposal
  (`NSOutlineViewDropOnItemIndex`) as soon as it declines to aim at a
  row — over the row being dragged, and over a leaf — and on the root
  that reached the move as "append at the end": the row flew to the
  bottom of the playlist instead of landing where the pointer was, which
  read as "dropped above, inserted below". The proposal is now
  retargeted at the insertion point actually under the pointer. Dropping
  onto a node still puts the rows inside it, and dropping on the empty
  area below the last row still appends. The displayed position is also
  translated into the core's own child index, which the two stop sharing
  as soon as a live search hides rows from the list.
- **Fullscreen video wrapped around the notch** of a 14 or 16 inch
  MacBook Pro. `-[NSScreen frame]` includes the menu bar strip the
  camera housing sits in, and this interface sizes its fullscreen
  windows itself, so nothing kept the picture out of it — the modern
  interface already subtracts the same safe area. The window still
  covers the whole display, since one shrunk to avoid the notch shows
  the *desktop* in the strip instead; the picture now stops below the
  camera, and the window's black background fills what is left, which is
  what native fullscreen does. All three fullscreen paths are covered
  (host window, dedicated window and the vout's own window), and screens
  without a notch are left exactly as they were.
- **"Show video within the main window" and "Window decorations" did
  nothing.** Both checkboxes were displayed by the legacy preferences
  but read by the modern interface only, so the legacy one always
  embedded the picture, whatever they were set to. Unchecking the first
  now opens the video in a window of its own, decorated or bare
  according to the second. Priority is the reverse of the modern
  interface's, on purpose: there, an unchecked "Window decorations"
  detaches the video whatever else is set, so re-checking "Show video
  within the main window" appeared to do nothing at all. Here the first
  checkbox decides alone, and the second only says whether that separate
  window has a title bar. An audit of every option the legacy
  preferences expose found no other one left unread.
  A decorated separate window carries its own controls — backward,
  play/pause, forward, seek bar, duration and fullscreen, no Stop and no
  Playlist button, exactly what the modern interface puts in its
  detached window; a window asked to have no decorations gets none, as
  in the modern interface. Hiding the controls during playback and
  pausing on minimisation both reach it, and a size the video asks for
  is scaled down to fit the screen with the aspect ratio kept — "Double
  size" on a 1080p film asks for 3840×2160, which no screen here can
  hold.

### Fixes — macOS (modern interface)

- **The detached video window opened with black bands above and below a
  1:1 picture.** The window chrome is measured as the difference between
  the window and the video view, which assumes the video view already
  has the size its constraints give it; on the very first vout of a
  detached window Auto Layout has not run on the nib yet, so the
  measurement was 22 pt too generous — 1024×854 instead of 1024×832 for
  a 1024×768 picture. Layout is now forced before measuring.

### Crystal HD — Macs and Windows

- **The Crystal HD card is now driven on Windows too**, Windows XP SP3
  included, where it is the difference between 1080p and a slideshow.
  Bringing the macOS work over meant more than a rebuild: the DIL
  exports its entry points as `__cdecl` and not `__stdcall` (declaring
  them the usual way builds, links, survives one call, and then jumps
  into whatever the drifting stack pointer holds), the colour space has
  to be configured *after* the decoder is opened or the card writes a
  quarter picture into the corner of the buffer and leaves the rest
  green, and the card lays its lines out on a quantised stride — so the
  buffer is advertised at that width while the visible width stays
  truthful. The restart path, which lived in local variables of the
  open routine, was lifted out so Windows has one at all.
- **The video no longer freezes with the sound playing on.** This
  decoder runs on two threads, and only one of them was throttled: the
  picture pool bounds what is *pulled* from the card, nothing bounded
  what was *fed* to it. Measured on a 720p30 Invidious stream, the
  decoder had pushed 49.3 s of content into the card while its output
  was still at 6.57 s — a 42.8 s gap, with the old throttle reporting a
  perfectly healthy lead because it was watching the wrong end. Any
  reset then resumed the film where the *input* had got to, so pictures
  came out dated tens of seconds in the future, the video output could
  never display one, never returned it to the pool, and the decoder
  parked for good. The amount of stream the card may sit on is now
  bounded in frames — generously, since it releases pictures in batches
  of 32 and starving it makes it run stop-and-go — and widened, never
  removed, while the output is silent.
- **A decoder can now tell the core how much lead it needs.** Caching
  options are sized on the assumption that decoding is near-instant,
  which a card that returns its pictures in batches makes false: every
  frame at the head of a batch missed its display date. The Crystal HD
  claims 3 s on Windows, whose DIL batches hardest, and the core takes
  it as a floor that a larger caching setting still wins over.
- **A card that has truly stopped hands the stream back to the
  processor** instead of leaving a still image for the rest of the film,
  which is what used to happen on Windows when it died 36 s into a 50 s
  clip.

### New features — Windows and Linux

- **Always on top is now in the Video menu**, right above Hide Controls
  During Playback, where the two macOS interfaces have always had it. The
  View menu keeps its own entry, and the two follow each other.

### Fixes — Windows and Linux

- **Recording produced nothing at all on Windows when the "My Videos"
  folder did not exist** — no file, no message, not a line in the log at
  the highest verbosity. That folder is not a given: a fresh Windows XP
  profile carries My Music and My Pictures and leaves the video one
  unset until something creates it. The player asked the system for it,
  got nothing back, and abandoned the recording there. It now falls
  through to the music folder and then to the documents folder, and says
  so in the log if even that fails. The clip creation mode showed the
  same defect from the other end: unable to name a file, its fast export
  declined and the clip was recorded by playing it through at normal
  speed instead.
- **A recording announced itself under a mangled path on Windows.** The
  variable that tells the rest of the player which file a recording has
  just produced carried the copy escaped for the streaming chain instead
  of the path itself, so every backslash came back doubled: the My Videos
  list gained an entry pointing nowhere, and the clip export — which
  checks that the file it is told about is the one it asked for —
  reported a failure over a clip it had just written correctly. The two
  strings are identical on systems whose paths need no escaping, which is
  why this had never shown.
- **A video larger than the screen opened a window larger than the
  screen**, its lower edge under the task bar. Only the height was ever
  compared, so a picture too wide for a screen tall enough went through
  untouched; and when the height did not fit, the window was given the
  full width of the screen — which its frame borders then exceeded — with
  the picture letterboxed inside the result. Nothing moved the window
  afterwards either, so one that already sat low on the screen simply
  grew downwards off it. The picture is now scaled, aspect ratio kept, to
  what the work area leaves once the window's own furniture is measured
  rather than estimated, and a window that ends up sticking out is
  brought back inside the work area.
- **The Blu-ray pop-up menu entry in the Qt interface was dead.** It was
  wired to a slot of the wrong object, so Qt refused the connection at
  run time and the entry did nothing on every disc that offers one.
- **A window whose title bar had been left off the top of the screen
  came back there for ever**, and a title bar that cannot be reached
  cannot be dragged back. Restored geometry is now pushed down into the
  work area.
- **Every extension carrying a translation catalogue failed to activate
  on Linux** ("Could not activate extension!"): the catalogues were
  installed into the library tree while Lua looks for them under the
  data tree. On macOS the packaging merges both, which is why it went
  unnoticed; on Linux they are `/usr/lib/vlc` and `/usr/share/vlc`, and
  only VLSub — which ships no catalogue — still worked.
- **Video is no longer decoded, converted and scaled by the processor
  when the display hardware could do it.** The OpenGL output outranks
  every other X11 output, so it won even where Mesa has fallen back to
  llvmpipe — an ordinary Debian 13 on a 945GME, since Mesa 25 dropped
  the DRI2 path that generation needs. Measured there on 52 s of 854×480
  H.264 (Atom N270): 91.3 s of CPU through OpenGL against 39.9 s through
  XVideo. The module now declines a software-rasterised context unless
  it is holding a hardware surface no other output could take, or unless
  `--gl-software` says otherwise.
- **The Windows file properties, the Add/Remove Programs entry and the
  crash dialogs reported VideoLAN and the upstream VLC version.** The
  version resources of the executable, the core library and every plugin
  now carry PowerVLC's own name and version.

### Build & packaging

- **The i386 AppImage segfaulted at startup and quietly lost a third of
  its plugins.** linuxdeploy gives every file it merely scans a
  `RUNPATH` of plain `$ORIGIN`, which for a VLC plugin points at its own
  category folder and never at the bundled libraries: plugins whose
  dependencies were not already loaded dropped out — including VLC's
  private helpers, which takes out *every* X11 video output — and the Qt
  interface plugin fell back to the host's Qt through `ld.so.cache`
  while the platform plugin still came from the bundle, mixing two Qt
  builds into an instant crash. The build now repairs those paths with
  `patchelf` between deploying and packaging, and hard-fails if the
  repair did not take. Exporting `LD_LIBRARY_PATH` from the launcher was
  tried first and rejected: it is inherited by child processes, and
  `dbus-launch` dies on our older libraries, taking the D-Bus and MPRIS
  interface with it. Measured: 472 → 511 modules loaded, no load
  failures.
- Two more AppImage traps closed: the MIME helper desktop files that
  `make install` lays down are dropped, since linuxdeploy hands
  appimagetool the alphabetically first one and `vlc-opendvd.desktop`
  would have given the bundle its name and icon; and libaacs/libbdplus
  are bundled again after the core library rename left the lookup
  resolving to `.` and silently copying them into the working
  directory — retail Blu-ray had gone with it. The build image now
  installs both, which `build-dep vlc` never pulls in because libbluray
  `dlopen()`s them.
- **`make` can no longer destroy the translations.** Regenerating the
  template through the gettext rule cannot work in this tree — the Qt
  interface headers exist only in the build tree, so `POTFILES.in` has
  to keep them commented out and the extraction loses ~360 strings,
  which `msgmerge` then marks obsolete everywhere. The rule now refuses
  and points at a new `po/update-pot.sh`, which builds those headers
  with `uic`, checks that every listed file actually resolves, compares
  the msgid sets before and after and aborts on any unjustified loss —
  the justified ones living in `po/POT-REMOVED.txt`, 123 removals each
  verified against the source tree. Documented in BUILD-POWERVLC.md.
- The root certificate bundle is installed next to the executable on
  Windows, and refreshed by `share/certs/update-ca-bundle.sh`, which
  validates what it downloaded before overwriting anything.
- **LINUX_REAL_HARDWARE_TESTS.md**, notes from running the AppImage on
  an Atom N270 netbook — including the one setup step that class of
  machine needs, since the DPMS request any player makes segfaults the X
  server on that Intel generation with the legacy driver.

## 1.2.0 (2026-08-09)

### New features — all platforms (modern machines included)

- **Four ready-to-use extensions are now shipped with the player**, all
  built from plain dialog widgets so they render on every interface —
  the modern macOS one, the legacy Mac OS X one and Qt on Windows/Linux:
  - **Invidious**: browse public instances, search videos, channels and
    playlists, and play at the quality you pick. Instances that have shut
    their JSON API down are read from their HTML pages instead, and the
    DASH manifest is rebuilt locally, so a working instance stays working.
    The media itself is fetched straight from Google's servers rather than
    relayed through the instance — one hop less on a machine that has none
    to spare.
  - **Jellyfin**: browse a server (movies, series, seasons, episodes,
    and the live TV line-up) and play either the original file or an HLS
    stream transcoded at the chosen quality. Sign in with an API key or
    with a username and password; the flow follows the JellyDinosaur
    front-end, and PowerVLC announces itself under its own name in the
    server's session list. Live channels are ordered the way a remote
    control numbers them, searchable, and show what is on right now when
    the server has a guide; a channel the server itself pulls from a
    remote playlist is opened at that playlist directly, so the whole
    ladder of qualities and the alternate audio and subtitle renditions
    reach the player instead of being flattened into the single transport
    stream the server would hand back. Transcoding is asked for at
    44 100 Hz, the rate the built-in output of a legacy Mac actually runs
    at, so the player is not left resampling every frame on a processor
    with nothing to spare.
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
  itself is always fetched by the player. The page holds one request open
  until there is something to take rather than knocking on the player
  several times a second, which on these machines matters: a second
  guarded video reuses the same handover, and a tab busy walking a
  challenge says so instead of looking like an idle relay.
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
  another station — and the station drawn is checked before it is handed
  over, since the directory's “broken” flag only reflects its own last
  sweep and a dead one would end the entry rather than draw again.
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
- **The quality of an adaptive stream can be pinned by hand**, from a new
  Quality submenu under Video Track present in all three interfaces:
  automatic, lowest, highest, or one named variant of that stream. Left
  alone, HLS and DASH pick a quality from a bandwidth estimate and change
  their mind mid-programme — which on these machines means being handed a
  resolution the processor cannot decode. Beside it sits a standing
  **resolution ceiling** (“Auto quality by resolution”, the module's own
  `adaptive-maxheight`, until now reachable only from the command line):
  that one is a property of the machine rather than of the stream, so it
  is set once and applies to everything played afterwards. Both can be
  changed while the stream is playing, and the lowest/highest choices keep
  obeying the ceiling.

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
- **Audio drift is no longer corrected audibly on a single reading.**
  Flushing the output or padding it with silence is heard, and one late
  measurement — one scheduling hiccup — used to be enough to order it;
  three consecutive ones are now required (`aout-drift-confirm`). How the
  correction is made is decided per stream (`aout-drift-silence`): an
  audio-only stream has nothing to stay in step with, so the resampler
  absorbs the offset inaudibly, while a stream with video keeps the
  silence padding that holds the picture and the sound together. The input
  pushes the change when a programme declares its video track late, so a
  transport stream is not stuck with the audio-only policy for good.
- **The cheap resampler is now chosen by architecture rather than
  everywhere.** Speex with a short filter is worth its lower stopband on
  the PowerPC and 32-bit x86 slices, where libsamplerate's SINC costs real
  CPU (measured on a 1.42 GHz Mac mini G4: 4 s of extra work per 115 s of
  audio); modern targets pay nothing for SINC and keep VLC's own ranking.
  And the choice is made in one place only — the module priority used to
  say the same thing a second time, and the two disagreed.
- **Extension dialogs stay where they are put.** Changing view inside an
  extension deletes the dialog and builds the next one, so a window the
  user thinks of as one window is really a succession of them, each
  centred afresh: moving it meant nothing. The position now carries over,
  in the Qt provider as in the macOS ones, and falls back to centring if
  the remembered spot no longer lands on any screen.
- Every line of the log file is stamped with the time elapsed since the
  first one, and on Windows the file is unbuffered: the C runtime treats
  line buffering as full buffering there, so a crash used to take the last
  few kilobytes with it — precisely the part worth reading.

### Fixes — all platforms (modern machines included)

- **Subtitles on a rotated video came out squashed.** The canvas they are
  rendered on had the rotation applied to it twice, so any clip filmed on
  a phone held upright got its subpictures stretched along one axis.
- **Semi-transparent pixels of a PNG were rendered too dark.** libpng was
  asked for alpha-premultiplied colour and every consumer downstream
  multiplied by the alpha a second time: a cover at alpha 128 over white
  landed on 191 instead of 255.
- **A video output could fail to start at all** on a small picture format:
  the look-ahead cache sizes its picture pool from a memory budget, and a
  few hundred megabytes divided by a small picture asks for thousands of
  them — past the allocator's ceiling, where it returns nothing and the
  video output dies with it (measured on a PowerBook G4: a 320×180 clip
  asked for 3021 pictures and played no video whatsoever). The budget is
  now clamped, and the ceiling is a public constant so the two cannot
  drift apart again.
- **A single broken timestamp could freeze the picture for good.** A
  picture dated a minute or more into the future sits at the head of the
  queue, is never due, holds everything behind it and gates the decoder
  shut while the audio plays on. Such a date is now called out and stepped
  over.
- **Changing quality on an adaptive stream flickered the whole window** on
  macOS: the video track is removed and re-added, and if re-buffering
  finished before the new decoder asked for its output the free one was
  destroyed a moment before it was needed — a new output means a new
  window, so the interface fell back to the playlist and popped back to
  video at every switch.
- **A fragmented MP4 could freeze the picture while the audio played on,
  with nothing in the log** — seen live on Invidious DASH streams after a
  network outage. Three separate silent stalls: a fragment index whose
  positions disagree with the fragments' own timestamps, an unreachable
  run seeked to for ever, and fragments walked at full pace without a
  single sample sent. Each is now detected, reported and recovered from by
  re-anchoring on the next fragment.
- **The position froze half-way through a fragmented MP4** while the film
  played on to the end: an inverted test left no track eligible to close
  the segment, so the demuxer's own time simply stopped advancing — and
  the progress bar and the displayed duration, which are read from it,
  stopped with it (measured on an 18.9 s clip whose clock stayed at 11 s).
- **The position also advanced in jerks** on those same streams, seven
  updates over nineteen seconds: the input loop sleeps until the next
  timestamp the source announces, which in a fragmented format means the
  next fragment boundary, seconds away, and it slept through every
  interface refresh due in between. The wait is now capped at 250 ms,
  which costs the source nothing — the position is derived from the
  playback clock.
- **A second input file could reset the playback clock**, so the picture
  froze and the position fell back to 00:00 while the audio already
  queued played on. A demuxer does not know whether it is the main source
  or the slave and emits its timing either way; the slave is only coarsely
  aligned, and in a fragmented format it overshoots by a whole fragment,
  so the clock was fed two timings seconds apart in turn and treated the
  older one as arriving too late. A slave's timing is now swallowed — its
  stream timestamps are absolute and stay valid, only the clock is the
  main source's business.
- **Clicking in an extension list could crash the player.** A widget event
  travels as a raw pointer and a script is free to rebuild its widgets
  while one is still queued — which is exactly what refilling a listing
  does; the queue is now purged of the events naming a widget being freed.
- **Playing an item without saying where it lives sent playback off into
  another list when it ended.** That is the only call an extension has,
  and several core paths use it too — “add and play”, the hotkeys, the
  D-Bus tracklist: the item was played from the context node of the
  *previous* playback, and since the queue of what comes next is built by
  walking the leaves under that node, the follow-on came from wherever
  the user had been before. Seen with a video started from the Invidious
  extension, which carried on into a Radio-Browser station played half an
  hour earlier. The item's own root is now used.
- A text box built by an extension wrapped its contents on the macOS
  interfaces, so a long URL — the copy-the-link box of the Invidious and
  Jellyfin views — showed several lines of which only one was visible. A
  text field is single-line by contract: it now scrolls instead.

### New features — legacy Macs

- **Crystal HD hardware decoding.** PowerVLC drives the Broadcom Crystal
  HD mini-PCIe card (BCM70015) found in — or added to — older Intel Macs,
  offloading H.264, VC-1 and MPEG-2 to it, with a fallback to the
  processor whenever the card cannot handle a stream. The kernel
  extension is bundled and installed, reloaded or removed straight from
  the Help menu (no version of macOS before 10.15 lets userspace map a
  PCIe device's registers, so there is no way around a kext here), and
  the client and the driver now agree on an ABI token so a mismatched
  pair refuses to talk instead of corrupting kernel memory. 1080p is
  held, which took working around a chip that leaks an internal resource
  on every keyframe of complex content and then stalls silently — it goes
  on accepting input, delivers nothing, and reports no error: parameter
  sets are prepended to every keyframe, the decoder is reset pre-emptively
  every few of them (timed to a keyframe, so the video output's lead hides
  the gap), and a watchdog rebuilds it within a frame or two if it wedges
  anyway — the fallback to the processor being the last resort rather than
  a loop of wedge and reset.
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
- **HEVC gets AltiVec on PowerPC**: SAO, the inverse transform, motion
  compensation — including the whole-pel cases and residual addition —
  measured on a 1.42 GHz 7447A at 16.8 → 26.9 fps on 854×480 10-bit
  content (+60 %), with output bit-identical to the C reference on every
  sample. Paired with a new H.264 chroma motion-compensation routine (the
  single hottest function in the measured H.264 profile, 10.4 % of decode
  time on its own).
- **A large AltiVec series imported into ffmpeg for PowerPC**, on top of
  the fork's own H.264 and HEVC work: a VP9 decoder (DSP, loop filters and
  the 4×4 to 32×32 inverse transforms), a split-radix FFT backend for
  av_tx, Opus and AAC kernels (SBR, parametric stereo, postfilter), H.264
  16×16 intra prediction, byte-precise `emulated_edge_mc`, the
  swresample resamplers, and fixes to the existing VP8 and VP9 paths.
  Registrations are tuned per CPU from bench results rather than assumed:
  a kernel measured slower than the C code on a 7447A is not installed.
  Decode time on that 7447A: −7.2 % on VP9 480p, −2.0 % on HEVC 480p.

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
- **AAC is decoded by libavcodec rather than faad2** on the legacy slices:
  libfaad2's inverse filterbank is what AAC playback actually costs there.
  Measured on a 700 MHz iBook G3, 48 kHz stereo 256 kb/s: 17.0 s of CPU
  per 60 s of media through faad2 against 15.2 s through libavcodec — 3 %
  of the machine handed back to the video decoder. faad2 stays as the
  fallback for the streams libavcodec turns down, and the modern slices
  keep the historic order.

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
  the view under the pointer, and the OpenGL 1 output — the one used by
  cards without rectangle textures, such as the iBook G3's Rage Mobility
  — was not claiming it.
- **The interface language was not remembered** on the legacy interface:
  it is stored in NSUserDefaults, and on systems without `cfprefsd`
  nothing flushes that to disk on quit. Choosing Arabic, Hebrew or
  Persian also translated the interface without laying it out
  right-to-left; both are fixed.
- Audio on Mac OS X 10.2 was reported as broken by a probe failing on a
  property that simply does not exist on that system — logged as an error
  at every launch while playback was in fact fine, in 5.1.
- **Dialogue was missing from 5.1 soundtracks** on machines whose driver
  does not report a channel layout — an iBook G3 under Panther, whose
  built-in output is stereo. The audio unit was then opened with the
  input's own six channels, and the centre channel, which on a DVD is
  where the dialogue lives, went nowhere: music and effects played
  perfectly while the actors were inaudible. The format is now forced to
  stereo in that case and the core does the downmix, which knows to fold
  the centre channel into the two front ones.
- **HDR clips played black on AGP-era GPUs.** libplacebo's tone mapper
  appends a hundred-odd instructions to the conversion shader, and
  Shader-Model-2 hardware caps the fragment pipeline far below that — the
  ATI R300 family, i.e. every GPU an AGP-era PowerBook or iMac G4 and G5
  shipped with, allows 64 ALU instructions. The driver does not always
  report the overflow: the program links and then draws black, while SDR
  clips, whose shader stays short, play fine. The budget is now read from
  the driver and the tone mapper kept only where it can actually run.
- **Videos carrying a rotation tag were not rotated** by the OpenGL 1
  output — the one used by cards without rectangle textures — merely
  squeezed into the portrait rectangle computed for them. The fixed
  pipeline has no vertex shader to carry the orientation matrix, so the
  rotation is now baked into the texture coordinates. The QuickDraw
  output still stretches such clips, deliberately: the rotation was
  written and checked correct there too, but the moment the matrix swaps
  the axes QuickTime's decompression sequence leaves its fast path for a
  general software resampling — a 640×360 clip took an iBook G3 from
  41 % CPU to a machine that no longer answered over SSH. It is kept
  behind a switch, off, rather than shipped at that price.
- **A green band across the bottom of H.264 video** on the QuickDraw
  output, with the picture squashed vertically to make room for it: the
  image handed to QuickTime was described with the decoder's buffer
  dimensions rather than the visible ones, so the alignment padding — 18
  rows of untouched, therefore green, YUV on a 640×360 stream — was
  blitted and stretched along with the picture. DVDs never showed it,
  MPEG-2 asking for no such padding.
- **Cropping did nothing on either legacy output.** The core applies the
  Crop menu to the source description only, which is what the window
  measures itself against: the window duly took the cropped aspect ratio
  while both outputs went on drawing the whole picture, squashed into it.
  Both now crop for real — through the texture coordinates on the OpenGL 1
  side, by moving the blit origin and restarting the sequence on the
  QuickDraw side — rounded to even pixels so the chroma cannot land half a
  pixel off and fringe the edges.
- **The playlist button still left video on screen** on Mac OS X 10.3,
  where the interface merely hides the video view instead of removing a
  host window. Two things kept covering the list, on different content:
  the hardware decoder's CGS surface, which the window server composites
  for as long as it has a shape — so on an accelerated DVD the button
  appeared to do nothing — and the QuickDraw blit, which writes straight
  into the window's port without passing through AppKit's view hierarchy,
  so an H.264 clip painted itself back over the interface at every frame.
  Both are now suppressed while the view is hidden, from a visibility the
  main thread publishes and the video thread only ever reads.
- **Cover art came out with red and blue traded** on PowerPC: two separate
  upstream big-endian bugs, one handing libav a byte-swapped format id for
  a picture that carries no colour mask (which is all libpng and libjpeg
  produce), the other naming bit-order formats where byte order was meant.
  Little-endian builds never went down either branch, which is why it went
  unnoticed upstream.
- **A thread parked in the replacement `poll()` could never be cancelled**
  before Mac OS X 10.5, which delivers cancellation to a thread already
  inside a system call where earlier releases do not — so quitting could
  wait for ever on any subsystem stopped that way, the HTTP server among
  them. It now sleeps in slices and tests for cancellation between them.

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
- **The Windows and Linux builds could ship stale translations.** The
  compiled catalogues are git-ignored, so the snapshot handed to the build
  container left them out, and nothing inside would rebuild them — gettext
  only recompiles a `.po` when the template changes, so a catalogue edited
  by hand is compiled on the host and never again. The container then kept
  whatever its persistent volume happened to hold: caught on the 1.2.0
  round with 6138 messages in the Windows French catalogue against 6143 on
  the Mac.
- Playlist item icons in the Qt interface keep the orange accent of the
  source selector they sit next to, instead of the red used by the menus
  and the Open dialog.

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
- **Diagnostics for audio sync**, which is what settled the drift work of
  this release: the audio output prints a sync report once a second (how
  much audio the filter chain was given against how much it returned, the
  resampling in force, the delay and the drift) and dumps the preceding
  measurements when it decides to correct, while the WASAPI output
  reports the device's own position and the frames fed to it against the
  same wall clock — the drift alone can never tell a sound card running
  off-rate from a chain losing audio. A new `--wasapi-dump-file` writes
  the exact bytes handed to the device, so the waveform can be examined
  off the machine.

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
