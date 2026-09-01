<div align="center">

<img src="share/icons/256x256/powervlc.png" alt="PowerVLC" width="168">

# PowerVLC

[![Latest release](https://img.shields.io/github/v/release/Olsro/powervlc?display_name=release&label=latest&color=e63312)](https://github.com/Olsro/powervlc/releases/latest)
[![macOS 10.2 and up](https://img.shields.io/badge/macOS-10.2%20%E2%86%92%2026-e63312)](#supported-systems)
[![Windows XP SP3 and up](https://img.shields.io/badge/Windows-XP%20SP3%20%E2%86%92%2011-e63312)](#supported-systems)
[![Linux AppImage](https://img.shields.io/badge/Linux-AppImage-e63312)](#supported-systems)
[![Support on Patreon](https://img.shields.io/badge/support-Patreon-e63312)](https://www.patreon.com/Olsro)

[Download](#download) · [How it feels on real Macs](MACOS_REAL_HARDWARE_FEELINGS.md) · [On a Linux netbook](LINUX_REAL_HARDWARE_TESTS.md) · [Exclusive features](#extra-features-on-powervlc-that-even-the-modern-vlc-dont-havenever-had) · [Changelog](CHANGELOG-POWERVLC.md) · [FAQ](FAQ-POWERVLC.md)

</div>

---

PowerVLC is an open source fork of VLC 3 by **Olsro** for the community with extra features, bug fixes, improvements, and more compatible with older hardware and OS versions. On Mac OS X, PowerVLC can run on anything that can at least run Mac OS X Jaguar 10.2 (2002): welcome to the retro future !

## Download

Grab the latest build from the [**Releases page**](https://github.com/Olsro/powervlc/releases/latest), then pick the archive that matches your machine:

| You have | Archive | Required OS |
| --- | --- | --- |
| Any Mac, one bundle for all of them | `mac-universal` | 10.2 and later |
| Mac PowerPC G3 | `mac-g3` | 10.2 and later |
| Mac PowerPC G4 (AltiVec) | `mac-g4` | 10.2 and later |
| Mac PowerPC G5 (AltiVec) | `mac-g5` | 10.2 and later |
| Mac Intel 32-bit | `mac-x86` | 10.4 and later (up to Mojave 10.14) |
| Mac Intel 64-bit | `mac-x64` | 10.6 and later |
| Mac Apple Silicon | `mac-arm64` | 11.0 and later |
| PC Windows 32-bit | `win32-nsis` or `win32-portable` | XP SP3 and later |
| PC Windows 64-bit | `win64-nsis` or `win64-portable` | Vista and later |
| PC Windows on ARM | `winarm64-nsis` or `winarm64-portable` | Windows 10 and later |
| PC Linux x86_64 / i386 / aarch64 | `linux-*` (AppImage) | Any distro with AppImage support and glibc 2.27+ (for Ubuntu, it's 18.04 or newer) |

The universal bundle runs on **every** supported Mac and architecture out of a single download — it is simply much bigger, since it carries all the slices at once. On a legacy Mac with a small disk, the per-architecture archive is the better pick.

Building it yourself is documented in [BUILD-POWERVLC.md](BUILD-POWERVLC.md).

## Features (more than all the goodnesses already available in VLC 3 upstream)
- Look-ahead cache & general optimisations to improve smoothness & compatibility on older hardware
- SSL/TLS using gnuTLS with bundled certs on all platforms. Benefits particularily on outdated OS that has antique TLS and root certs.
- Gapless playback
- h.264 3D MVC (Blu-rays 3D), with menus. Frame packed 3D supported, can switch your screen automatically in 3D mode.
- mp3/rockbox players & iPods syncing
- Persistent bookmarks
- Dolby Vision (HEVC Profiles 7 + 8.1), including FEL. When playing Dolby Vision content, PowerVLC will automatically use MacOS private system APIs to proceed the display mode switch.
- CJK & special characters support on Windows (including XP)
- CRT TV filters, with all the RetroArch CRT filters (including the very famous CRT-Royale which looks gorgeous)
- Superfast organized multimedia library
- Hardware GPU MPEG-2 acceleration with some Mac G3 ATI cards
- Crystal HD (BCM70015) hardware decoding on macOS
- Easy to play commercial Blu-Rays: just drag & drop the keydb.cfg into the window and it's enough to play a commercial blu-ray on all platforms supported by PowerVLC (excepted Mac OS X 10.2/10.3). If you don't intend to use Blu-Ray menus, PowerVLC can now select automatically the right obfuscated playlist defined in the keydb.cfg file. In general, a lot of efforts has been done in PowerVLC to make the playback of commercial discs as reliable & smooth as possible.
- Heavily tuned, refined subtly, & bugs fixed
- Technical backports & contrib updates from upstream VLC 4
- Revamped extensions system where you can find complete content browsers to find content in a very optimised & lite way. Includes out of the box in-app optimised browsers for Invidious (YouTube), PeerTube (including SepiaSearch, format/audio/subtitle selection and downloads), Internet Archive (movies and audio), Jellyfin, Audiobookshelf, Subsonic / Navidrome / Airsonic, Soulseek (download and direct streaming, without chat or uploads), eMule/eD2k/Kad (direct EC control of a headless engine), and Podcast discovery.
- Radios Browser: find stations all over the world, save your favourites in your library and play randomly a station to discover new ones
- Web Browser add-on companion compatible with PowerFox, Basilisk (all kind of Legacy Firefox based on the XUL platform)
- Picture-In-Picture mode (all window controls hidden) available on all OS (on Mac OS X 10.2 to 10.5, the title bar from the window can't be removed though)
- Hover the seekbar to see a thumbnail of the targetted time
- Clip creation mode: optimised & ergonic way to export a customised part of a content
- Automatic cropping of the black bars (auto crop) depending on the content you're watching. No more manual adjustment and need to know the ratio of your files/IPTV streams by yourself.
- Native CRT display filter for low-resolution and broadcast-era video, with resolution-aware scanlines, phosphor masks, halation, diffusion, and a vintage-anime preset. It is built for every PowerVLC platform and keeps subtitles outside the effect.
- Mac OS X: can now show the album cover art on the main window + see chapters marks on the seekbar
- AppImage on Linux, which contains all dependencies on its own so is very easy to use & very compatible with a large amount of different Linux distros
- IPTV/adaptative streams handling improvements: define exactly the quality you want and select automatically the lowest/highest one as a favourite for the next streams you're going to watch

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

## Retro machines general usage tricks

- Use also some other *neo-retro* projects like Basilisk (10.7+) or PowerFox (10.4+) so you can find radio streams links to send on to PowerVLC from the modern web; enjoy synergies.
- https://macintoshgarden.org/ is awesome, browsing this site from old Safari works really well and this site is very "old browsers" friendly.
- If you have access to a Jellyfin or Audiobookshelf server, the bundled extensions browse it directly from PowerVLC — no browser needed at all.
- Best way to share files to an old Mac from a modern machine is by setting up the AFP protocol with netatalk using Docker: https://netatalk.io/docker — PowerVLC was tested and it can stream files just fine directly from an AFP shared drive.
- On G3 machines, forget about USB because USB1.1 is nightmarishly slow as hell. Though if you still own Firewire 400 devices, those will be fast, Firewire 400 is close to USB2.

## Documentation

| Document | What's inside |
| --- | --- |
| [CHANGELOG-POWERVLC.md](CHANGELOG-POWERVLC.md) | Everything that changed, release by release |
| [FAQ-POWERVLC.md](FAQ-POWERVLC.md) | Frequently asked questions about the fork |
| [MACOS_REAL_HARDWARE_FEELINGS.md](MACOS_REAL_HARDWARE_FEELINGS.md) | How it feels on each machine I tested |
| [LINUX_REAL_HARDWARE_TESTS.md](LINUX_REAL_HARDWARE_TESTS.md) | Running it on an old Linux netbook, and the one setup step it needs |
| [BUILD-POWERVLC.md](BUILD-POWERVLC.md) | Building every target, and the universal bundle |
| [ACCELERATED-MPEG2-COMPATIBILITY.md](ACCELERATED-MPEG2-COMPATIBILITY.md) | Which GPUs get accelerated DVD playback, and why |
| [CRT-FILTER.md](CRT-FILTER.md) | Using and tuning the built-in CRT display filter |
| [MACOS_INCOMPATIBILITIES.md](MACOS_INCOMPATIBILITIES.md) | What each old macOS version can and cannot do |

## Get help

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

## Legal
For interoperability, some extensions may include the ability to access peer-2-peer networks and content discovery platforms so users can conveniently find copyright-free content. It's up to the user to download only rightfully owned content, and up to the platforms to moderate themselves and remove copyright-infringing content.

PowerVLC just lists what the platform sends to it like a web browser does for a webpage, and just plays what the user wants it to play.

---

<div align="center">

PowerVLC is an unofficial fork of VLC 3.0.x, not affiliated with VideoLAN.<br>
Licensed under the GNU General Public License v2 or later, like VLC itself.

</div>
