<div align="center">

<img src="share/icons/256x256/powervlc.png" alt="PowerVLC" width="168">

# PowerVLC

**Your universally compatible video player, based on VLC 3.**

From a 1999 PowerPC G3 running Mac OS X 10.2 "Jaguar" to an Apple Silicon Mac — same app, same experience.

[![Latest release](https://img.shields.io/github/v/release/Olsro/powervlc?display_name=release&label=latest&color=e63312)](https://github.com/Olsro/powervlc/releases/latest)
[![macOS 10.2 and up](https://img.shields.io/badge/macOS-10.2%20%E2%86%92%2026-e63312)](#supported-systems)
[![Windows XP SP3 and up](https://img.shields.io/badge/Windows-XP%20SP3%20%E2%86%92%2011-e63312)](#supported-systems)
[![Linux AppImage](https://img.shields.io/badge/Linux-AppImage-e63312)](#supported-systems)
[![Support on Patreon](https://img.shields.io/badge/support-Patreon-e63312)](https://www.patreon.com/Olsro)

[Download](#download) · [How it feels on real hardware](MACOS_REAL_HARDWARE_FEELINGS.md) · [Exclusive features](#extra-features-on-powervlc-that-even-the-modern-vlc-dont-havenever-had) · [Changelog](CHANGELOG-POWERVLC.md) · [FAQ](#faq)

</div>

---

Windows XP SP3 (2007) continued to receive official VLC updates, whereas the Mac OS X minimal version bumped several times, requiring 10.7.5 (2011). Starting with VLC4, things will get worse: Mac OS X 10.10+ (2014) / Windows 7 (2009) will be required.

PowerVLC supports almost every feature & nitpick the real VLC3 does, back to Jaguar 10.2. User experience is the same between all OS, though 10.7+ users can freely switch to the "Modern" interface as they do not need the Legacy UI rewrite.

PowerVLC also supports modern SSL, with bundled certs, making it possible to stream HTTPS web radios smoothly even using a G3.

Don't expect miracles, you will be limited by your hardware/GPU/memory bandwidth so keep your expectations reasonable and be patient. But PowerVLC will attempt to give your hardware the best it can achieve.

## Download

Grab the latest build from the [**Releases page**](https://github.com/Olsro/powervlc/releases/latest), then pick the archive that matches your machine:

| You have | Archive |
| --- | --- |
| Any Mac, one bundle for all of them | `mac-universal` |
| PowerPC G3 | `mac-g3` |
| PowerPC G4 (AltiVec) | `mac-g4` |
| PowerPC G5 | `mac-g5` |
| Intel Mac on 10.4 / 10.5 | `mac-x86` |
| Intel Mac on 10.6 and later | `mac-x64` |
| Apple Silicon Mac | `mac-arm64` |
| Windows 32-bit (XP SP3 and later) | `win32-nsis` or `win32-portable` |
| Windows 64-bit | `win64-nsis` or `win64-portable` |
| Windows on ARM | `winarm64-nsis` or `winarm64-portable` |
| Linux x86_64 / i386 / aarch64 | `linux-*` (AppImage) |

The universal bundle runs on **every** supported Mac and architecture out of a single download — it is simply much bigger, since it carries all the slices at once. On a legacy Mac with a small disk, the per-architecture archive is the better pick.

Building it yourself is documented in [BUILD-POWERVLC.md](BUILD-POWERVLC.md).

### Supported systems

| Platform | Range | Interface |
| --- | --- | --- |
| Mac OS X PowerPC (G3 / G4 / G5) | 10.2 "Jaguar" → 10.5 "Leopard" | Legacy |
| Mac OS X / macOS Intel 32-bit | 10.4 → 10.6 | Legacy |
| macOS Intel 64-bit | 10.6 → 26 | Legacy or Modern |
| macOS Apple Silicon | 11.0 → 26 | Legacy or Modern |
| Windows (32 / 64 / ARM64) | XP SP3 → 11 | Qt |
| Linux (x86_64 / i386 / aarch64) | AppImage | Qt |

Windows and Linux builds are real and shipped, but they get far less testing than the Mac ones — the look-ahead cache, gapless playback and the bundled extensions all work there.

## How it feels on real hardware

I have personally tested PowerVLC on my own machines. See the results here: [MACOS_REAL_HARDWARE_FEELINGS.md](MACOS_REAL_HARDWARE_FEELINGS.md)

## Extra features on PowerVLC that even the modern VLC don't have/never had

- **Look-ahead cache.** An optional cache based on decoded frames. If you accept some slowdown & a lot of (configurable) extra RAM usage, you can get smooth playback on content your machine can't exactly decode real time reliably (for example h.264 720p on a Mac Mini G4). The playback will need to stop from time to time in order to do the buffering, but will be 100% smooth all the rest of the time.
- **Gapless playback for music.** This is crucial to listen correctly to many live albums recorded that way, and iTunes supports that since iTunes 7.
- **Cover art in the bottom left of the main window on Mac OS** (the Windows version of VLC has been able to do that for a long time).
- **Hardware GPU MPEG-2 acceleration on old Mac ATI cards.** The first 3rd party program ever doing it, calling private APIs from the system that were never reverse engineered before. This allows comfortable MPEG-2 streams to be played on G3s from the early 2000s. DVD subtitles and animated menu highlights are composited by the GPU too. See [ACCELERATED-MPEG2-COMPATIBILITY.md](ACCELERATED-MPEG2-COMPATIBILITY.md) for the exact list of validated GPUs.
- **Crystal HD (BCM70015) hardware decoding on macOS**, with the kext bundled and installed, reloaded or removed from the Help menu.
- **AltiVec everywhere it counts** on G4/G5: HEVC (+60% measured on 480p 10-bit), H.264, VP9, AV1, FFT, Opus/AAC — every kernel bit-identical to the C reference, and installed only on the CPUs where it measured faster.
- **Simple, more user friendly and straightforward commercial Blu-Ray playback:**
	- Targets the lowest Java at compile, so only Java 5 is required to play BD-J menus on PowerVLC.
	- Can load the Java 6 bundled into Snow Leopard automatically (same about the Java 5 shipped on Tiger/Leopard).
	- libaacs and libbdplus are already included, and a convenient importation workflow has been integrated: just drag & drop/open your `keydb.cfg` and PowerVLC will ask you to automatically import it into the right place, then insert your Blu-ray disc and it will play (with menus also if Java 6+ is available on your system).
	- Menu items in the "Help" menu to quickly open folders related to content decryption using libaacs/libbdplus.
	- Forced subtitle detection on PGS tracks, which even VLC master lacks.
- **Searches that ignore accents, ligatures and typographic punctuation**: typing `au coeur de l'histoire` finds *Au Cœur de l'Histoire*, everywhere in the app.

## Streaming, without a modern browser

- **Four extensions are shipped with the player**, and they render identically on the modern macOS interface, the legacy Mac OS X one and Qt on Windows/Linux:
	- **Invidious** — browse instances, search videos, channels and playlists, pick your quality. The media is fetched straight from Google's servers rather than relayed, which is one hop less on a machine that has none to spare.
	- **Jellyfin** — browse a server (movies, series, seasons, episodes, live TV) and play the original file or an HLS stream transcoded at the quality you choose.
	- **Subsonic / Navidrome / Airsonic** — browse a music server the way a music player does, with search, favourites, gapless playback, server-side transcoding and downloads.
	- **Podcast discovery (iTunes)** — search Apple's public directory, open a show with its artwork and description, and subscribe in one click.
- **Radio-Browser.info directory** in the Internet section of the sidebar: browse the community webradio database by continent and country, or jump to a random station worldwide.
- **Invidious instances guarded by an anti-bot challenge are handed to your browser.** PowerVLC does not try to solve JavaScript proof-of-work or captchas: it opens the page in the browser you already have — even a Mac OS X 10.4 machine runs a current one — and takes back the session the browser legitimately earned. Only the *page* is ever handed over: the media itself is always fetched by the player.
- **A PowerVLC browser add-on** is shipped with the application and installed in one click from the Help menu. It sends what the browser is playing over to the player, and it is the only way in on browsers older than Firefox 69 — the ones legacy Macs run.

## Philosophy of this project

- **Open source.**
- **Ecological**: to give the most of what your legacy hardware is already capable of.
- **Learning**: it was an experiment by itself and a challenge, I was absolutely not sure at start that I would go this far but little by little here it is.
- **Performance**: faster than VLC on older hardware & can do fun stuff even on a barebone G3 PowerPC.
- **Not fancy stuff**, focus on technical works & keeping things simple. I was inspired by the project "PowerFox" which made the experience feel like Australis Firefox even if it has too many improvements under the hood to feel great on old machines.
- **No bullshit**: you are not a product. No tracking there, total user freedom.
- **Not too deep & automated AI integrations**: I want to use AI only for high-value operations & not integrate too much in automated pipelines. There's an ecological impact with AI, I don't want to use it to review automatically all PR I will receive even the troll ones. Manual orchestration is the way for me, so I get the control to call those new fancy tools only when I will be sure they will provide me a good added value.
- **Universality**: I provide a universal binary, compatible with all MacOS versions starting 10.2 & architectures (ppc, intel x86, intel x86_64, apple silicon arm64).
- **Compiled with AltiVec instructions** for G4 and G5 processors so you can get the best performance possible there.

## FAQ

### Why the name PowerVLC?
Because it supports PowerPC Macs and I got inspired by PowerFox which is also a very high quality project to keep old machines alive.

### Is this really VLC3? How is that possible? Did VideoLAN abandon old Mac OS because they were lazy?
In reality, the Legacy UI that you will use and that feels the same has been recoded from scratch in AppKit to be compatible with 10.2+. Many edge cases & tests had to be done on real machines. AI helped, but even with AI, VLC is still one of the most complex applications in the world. Considering the amount of implied work, their decision to drop some compatibility over time is totally understandable. Supporting older systems is not magical, there's plenty of edge cases & API support each time you target one more older system with all the related machines. Things get even more complicated by adding other architectures: Intel x86 / PPC / PPC AltiVec. It's impressive they could still keep up at maintaining Windows XP compatibility as of this day.

Even Mac OS X 10.5 and 10.6 that feel mostly the same graphically had many internal differences in reality.

PowerVLC is derived from the whole VLC3 source code and crafted with love for you to feel the same, but internally many things had to be improved so it feels great & powerful on your legacy hardware & OS. And some things had to be heavily recoded & changed internally so it can just work as intended on this hardware, even if you probably won't feel it because everything has been carefully tested for you to feel the same at usage.

### When VLC4 is released, do you plan to rebase on VLC4?
The UI will be completely moved to much more modern tech on VLC4. I plan only to take what users really want & technical "under-the-hood" improvements provided by VLC4. VLC4 is not even released at this point, but as of today I plan to keep on the legacy of VLC3 visually and in terms of user experience just like how PowerFox remained on the legacy of the Firefox Australis user experience.

### What about upstream VLC?
I don't have the time to invest on making those improvements available on upstream VLC, though I allow anyone to submit patches on my behalf if you've got interest in any of them. Just credit me and the name of this fork (PowerVLC) on the description of your commits & pull requests. No gatekeeping there, sharing is caring.

### Supporting MacOS Classic (9) or X 10.0/10.1?
Not planned.

### Current quality level
I believe most features will work, with some obvious limitations on old systems. Though there's real chances things will work bad for you on your specific machine, which is also why I encourage donations which will afford me to get more legacy Macs models to test on.

## Retro machines general usage tricks

- Use also some other *neo-retro* projects like Basilisk (10.7+) or PowerFox (10.4+) so you can find radio streams links to send on to PowerVLC from the modern web; enjoy synergies.
- https://macintoshgarden.org/ is awesome, browsing this site from old Safari works really well and this site is very "old browsers" friendly.
- If you have access to a Jellyfin server, the bundled Jellyfin extension browses it directly from PowerVLC — no browser needed at all.
- Best way to share files to an old Mac from a modern machine is by setting up the AFP protocol with netatalk using Docker: https://netatalk.io/docker — PowerVLC was tested and it can stream files just fine directly from an AFP shared drive.
- On G3 machines, forget about USB because USB1.1 is nightmarishly slow as hell. Though if you still own Firewire 400 devices, those will be fast, Firewire 400 is close to USB2.

## Documentation

| Document | What's inside |
| --- | --- |
| [CHANGELOG-POWERVLC.md](CHANGELOG-POWERVLC.md) | Everything that changed, release by release |
| [BUILD-POWERVLC.md](BUILD-POWERVLC.md) | Building every target, and the universal bundle |
| [ACCELERATED-MPEG2-COMPATIBILITY.md](ACCELERATED-MPEG2-COMPATIBILITY.md) | Which GPUs get accelerated DVD playback, and why |
| [MACOS_INCOMPATIBILITIES.md](MACOS_INCOMPATIBILITIES.md) | What each old macOS version can and cannot do |

## Support

PowerVLC is a hobby project. Don't expect professional support & quick reviews to your PR or questions, or to assist you personally if you have a problem. Patreon members are prioritized on individual support, with no guarantees too. I share all of my work because I believe in its quality and because it is at least useful to me and I am sure at least someone else will enjoy all the effort, but I don't want too much pressure and I want to keep your expectations reasonable. I am a solo dev, not affiliated with the whole VideoLAN organization (which is also a non-profit by the way).

I am not making a Discord and my own community platforms because I want to pass my time on the code on my projects and focus on quality of the application rather than on moderation & community management.

I plan to keep up at following the next VLC3 updates, but won't provide any guarantees even by doing my best at making things right.

If you encounter a problem, the good practice there is to make a GitHub issue indicating:

- Your machine & GPU
- Exact MacOS version
- What happened and how to reproduce
- Launch the binary with `-vv` args then dump the console logs & provide them in your report (not mandatory but can help)

The more data & context you give, the more likely I will be able to reproduce then submit a patch to improve your experience.

Please do not contact me for support requests & use only GitHub issues ideally. I believe most issues you may find should be visible to the whole community. It's better for transparency & this allows me to link code (PR) directly with your issues.

## AI usage

- Not in any way on my social media posts and when doing support, as I want to keep this human
- AI helped to improve the presentation of this README, which was initially entirely redacted without assistance. AI helped to generate docs from code, but then it was always human reviewed and often improved afterwards to fit my quality standards.
- The AI automated some tests during dev, but everything I produced was carefully human tested on real machines, and heavily iterated so it won't feel as "AI slop".
- Heavy usage for code generation. Most of the code was entirely AI generated, though it does not mean this app was "vibe coded", as the AI did shit/wrong many times. Plenty of manual work had to be done and the years of real experience working on several projects helped me to drive the new fancy AI tools. It's not vibe code there, it's hard work, repetitive work, but much accelerated by AI tools handled with love.

## Contact & Support

Here you can support me financially: https://www.patreon.com/Olsro

To contact me directly, here is also my email: olsroparadise@proton.me

You can support this work by putting a star in this GitHub project, writing positive comments all around, and by recommending this application to your relatives.

## Credits

- All contributors from VLC/VideoLAN since the beginning
- Jean-Baptiste Kempf for being a source of inspiration & motivation. VLC is really one of the most important programs coming from the "french tech", using it since years and it was always installed on all of my computers as the must-have program that can play anything I throw at it.
- All the contributors from all the open source contrib projects related to this project
- All of my Patreons for supporting me financially

---

<div align="center">

PowerVLC is an unofficial fork of VLC 3.0.x, not affiliated with VideoLAN.<br>
Licensed under the GNU General Public License v2 or later, like VLC itself.

</div>
