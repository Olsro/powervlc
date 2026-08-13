# PowerVLC on real Linux hardware

Notes from running PowerVLC on an actual low-power netbook, and what you need to
set up to get a good experience on that class of machine.

## Test machine

| | |
|---|---|
| Model | Acer Aspire One netbook |
| CPU | Intel Atom N270 @ 1.60 GHz (i686, SSE/SSE2/SSSE3 — no SSE4) |
| RAM | 1 GB |
| Graphics | Intel 945GSE, `intel` X driver (SNA), 1024×600 panel |
| OS | antiX / Debian GNU/Linux 13 (trixie), IceWM |

## 1. Run it

The AppImage needs no installation and does not touch system paths, so it
coexists with a distribution VLC:

```bash
chmod +x PowerVLC-1.3.0-i386.AppImage
./PowerVLC-1.3.0-i386.AppImage
```

## 2. Required on this hardware: stop X from crashing mid-playback

**Symptom.** About 30 seconds into any video, the whole graphical session
disappears and you are back at the login screen.

**Cause.** This is a bug in the X server, not in the player. A media player asks
the system not to blank the screen while video is playing; on this generation of
Intel chipset with the legacy `intel` driver, the `xset dpms force on` request
that this triggers makes Xorg segfault. Any player that keeps the screensaver at
bay hits it — the command alone reproduces it with no player running at all.

**Fix.** Disable the DPMS extension. Create
`/etc/X11/xorg.conf.d/20-powervlc-fix.conf`:

```
Section "Extensions"
    Option "DPMS" "Disable"
EndSection
```

then restart the X session. Check it took effect:

```bash
xset -q | grep -A1 DPMS
```

should report `Server does not have the DPMS Extension`.

**What this costs you: almost nothing.** The X server's own screen blanking is a
separate mechanism and stays active, and on this driver blanking really does cut
the backlight — the panel still switches off on its own after the idle timeout.
You only lose the staged DPMS levels (standby / suspend / off) and the ability
for an application to force a power state.

To undo it, delete the file and restart X.

**Don't want to touch system configuration?** Launching PowerVLC with
`--no-disable-screensaver` avoids the crash too, at the price of the screen
blanking during playback.

## 3. What to expect

- **720p H.264 plays smoothly**, both windowed and fullscreen. That is a solid
  result for a 1.6 GHz Atom.
- **Video output is set up for you.** PowerVLC picks the XVideo path, which
  hands colour conversion and scaling to the display hardware. Nothing to
  configure.
- **480p H.264 costs roughly two thirds of one core**, leaving headroom for the
  rest of the desktop.
- **Decoding is the limit, not display.** On this machine the decoder accounts
  for most of the CPU time, so codec and resolution — not the video output —
  decide what plays. 1080p is beyond this hardware.
- **Extensions work**: Invidious, Jellyfin, Subsonic, iTunes Podcast Discovery
  and VLSub all load and run.

### A note on OpenGL

This chipset has no working hardware OpenGL on Debian 13: modern Mesa dropped
the rendering path that the legacy `intel` driver provides for this generation,
so the system falls back to software rendering. You can confirm it outside
PowerVLC with `glxinfo -B`, which reports `llvmpipe`.

This is a distribution-level situation, not a PowerVLC one, and it does not
matter here: XVideo is the cheaper path on hardware of this era anyway, and it
is the one PowerVLC uses.

## 4. Worth checking on any old machine

A background daemon spinning on a fault can quietly eat a large slice of a CPU
this small. On the test machine, `smartd` was restarting in a loop because the
SSD module reports no SMART data at all — about 10% of the CPU, permanently, for
nothing. Netbooks of this era often carry such a disk.

```bash
pgrep -a smartd     # run twice: a changing PID means it is looping
```

If it is, disabling the service is safe when the disk cannot report SMART data
in the first place.
