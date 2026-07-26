# PowerVLC
Your universally compatible video player based on VLC3.

Windows XP SP3 (2007) continued to receive official VLC updates, whereas Mac OS X minimal version bumped several times, requiring 10.7.5 (2011). Starting VLC4, things will get worse: Mac OS X 10.10+ (2014)/Windows 7 (2009) will be required.

PowerVLC supports almost every features & nitpicks the real VLC3 does, back to Tiger & PPC machines. User experience is the same between all OS, though 10.7+ users can freely switch to use the "Modern" interface as they do not need the Legacy UI rewrite.

Linux/Windows support is available but barely tested at this moment. OpenGL look ahead cache should work on these platforms, and gapless playback aswell.

## What can PowerVLC achieve
Tested on real hardware I own, here's my reports. Compared to old VLC (especially 0.9.10 from 2009), expect much more stability & features, enjoy there more than 15 years of dev & bug fixes from the VLC team.

Compared to VLC 2.x old builds, there's still many "real world" improvements, I am for example thinking on the much improved m3u8 support so if you can find transcoded low-res streams, it will work really great with seeking, audio, etc.

PowerVLC also support modern SSL, with bundled certs, making it possible to stream HTTPS web radios smoothly even using a G3.

Don't expect miracles, you will be limited by your hardware/GPU/memory bandwidth so keep your expectations reasonable and be patient. But PowerVLC will attempt to give your hardware the best it can achieve.

Here's some example using my own legacy machines: 
(I don't own all generations, so feel free to share your results on social medias, I am very curious to know how PowerVLC behaves on your own hardware !)

### iBook G3
Running on Tiger, 384MB of RAM. HDD was replaced with a 128GB mSata SSD.
*Tested with both 10.4.11 (Tiger)*

- Can generally play/stream 240p contents in AV1, H265, H264.
- DVDs works really great, similar around 50% of CPU load just like how the real Apple DVD Player app can achieve on this hardware. It's fully accelerated.
- Good as a FLAC music player, the modern UI shines and is way more capable than what was capable 0.9.10 back then on Tiger. I did not tried effects but for simple music playback it does the job reliably, and playing everything gapless

### Mac Mini G4
Running on Tiger, 1GB of RAM. HDD was replaced with a 128GB mSata SSD.
*Tested with both 10.4.11 (Tiger) and 10.5.8 (Leopard).*

- Can generally play/stream 480p contents in AV1, H265, H264. 720p may work sometimes with very low bitrates but is over the specs.
- For 720p content, you may want to enable the look ahead cache to get smooth playback, at the expense of regular pauses to fill the cache (in my opinion it's pretty bad but it's at least watchable rather than a movie with constant frame drops all over the place)
- DVD content is smooth with deinterlacing ON, no surprises it's easy for this machine

### MacBook 2007 (GMA950/Core 2 Duo)
*Tested with 10.5.8 (Leopard) and 10.6.8 (Snow Leopard).*
This machine is like the good old Intel Atom netbooks but featuring a much faster 64 bits CPU. The GMA950 is known to really put it down and is not even capable of doing h.264 hardware decoding.

Expect easy 720p files handling, and even lite 1080p. Though your problem will be the heat, those Core 2 Duo gets hot when you push them too hard.

Blu-ray remuxes works reliably with the look ahead cache enabled, but CPU will be maxed all the time.

I ordered a Crystal HD (BCM970015) and plan to support them in Mac OS X in the future so those machines and modded Apple TV/Mac Minis/hackintoshed netbooks will be able to play smooth 1080p blu-ray content with low power usage, giving those machines the second breath they deserves too.

### MacBook Pro 2010 13-inch (NVIDIA 320m)
*Tested with 10.6.8 (Snow Leopard) and 10.9.5 (Mavericks).*
PowerVLC is shining there with HD content, using full VDA hardware acceleration even on Snow Leopard. Blu-rays can be played with very low CPU usage.

## Philosophy of this project
- Open source
- Ecological: to give the most of what your legacy hardware is already capable of
- Learning: It was an experiment by itself and a challenge, I was absolutely not sure at start that I would go this far but little by little here it is.
- Performance: faster than VLC on older hardware & can do fun stuff even on a barebone G3 PowerPC
- Not fancy stuff, focus on technical works & keeping things simple. I was inspired with the project "PowerFox" which made the experience feeling like Australis Firefox even if it has too many improvements under the hood to feel great on old machines.
- No bullshit: you are not a product. No tracking there, total user freedom.
- Not too deep & automated AI integrations: I want to use AI only for high-value operations & not integrate too much in automated pipelines. There's an ecological impact with AI, I don't want to use it to review automatically all PR I will receive even the troll ones. Manual orchestration is the way for me, so I get the control to call those new fancy tools only when I will be sure they will provide me a good added value.
- Universality: I provide a universal binary, compatible with all MacOS versions starting 10.4 & architectures (ppc, intel x86, intel x86, apple silicon arm64).
- Compiled with ALTIVEC instructions for G4 and G5 processors so you can get the best performance possible there

## Extra features on PowerVLC that even the modern VLC don't have/never had
- An optional look-ahead cache based on decoded frames. If you accept some slowdown & a lot of (configurable) extra RAM usage, you can get smooth playback on content your machine can't exactly decode real time reliably (for example h.264 720p on a Mac Mini G4). The playback will need to stop for time to time in order to do the Buffering, but will be 100% smooth all the rest of the time
- Gapless playback for music (this is crucial to listen correctly on many live albums recorded that way, and iTunes supports that since iTunes 7)
- Ability to show the cover arts in the bottom left of the main window on Mac OS (Windows version of VLC can do that since a long time)
- The first 3rd party program ever featuring hardware GPU based MPEG2 acceleration on old Macs ATI cards, calling private APIs from the system that were never reverse engineered before. This allow comfortable MPEG2 streams to be played on G3's from the early 2000.
- Simple, more user friendly and straightforward commercial Blu-Rays Playback : 
	- Targets the lowest Java at compile. So only Java 5 is required to play BD-J menus on PowerVLC
	- Can load the Java 6 bundled into Snow Leopard automatically (same about the Java 5 shipped on Tiger/Leopard)
	- Simple commercial Blu-Ray playback setup: libaacs is already included, and a convenient importation workflow has been integrated into PowerVLC: just drag & drop/open your keydb.cfg and PowerVLC will ask you to automatically import it into the right place, then insert your blu-ray disc and it will play (with menus also if Java 6+ is available on your system)

### About upstream
I don't have the time to invest on making those improvements available on upstream VLC, though I allow anyone to submit patches on my behalf if you've got interest in any of them. Just credit me and the name of this fork (PowerVLC) on the description of your commits & pull requests. No gatekeeping there, sharing is caring.

## Why the name PowerVLC ?
Because it supports PowerPC macs and I got inspired by PowerFox which is also a very high quality project to keep old machines alive.

## Is this really VLC3 ? How is that possible ? Did VideoLAN abandoned old Mac OS because they were lazy ?
In reality, the Legacy UI that you will use and that feel the same has been recoded from scratch in AppKit to be compatible 10.4. Many edge cases & tests had to be done on real machines. AI helped, but even with AI, VLC is still one of the most complex application in the world. Considering the amount of implied work, their decision to drop some compatiblity over time is totally understandable. Supporting older systems is not magical, there's plenty of edge cases & API support each time you target one more older system with all the related machines. Things gets even more complicated by adding other architectures : Intel x86/PPC/PPC ALTIVEC. It's impressive they could still keep up at maintaining Windows XP compatibility as of this day.

Even Mac OS X 10.5 and 10.6 that feels mostly the same graphically had many internal differences in reality.

PowerVLC is derived from the whole VLC3 source code and crafted with love for you to feel the same, but internally many things had to be improved so it feel great & powerful on your legacy hardware & OS. And some things had to be heavily recoded & changed internally so it can just work as intended on this hardware, even if you probably won't feel it because everything has been carefully tested for you to feel the same at usage.

## When VLC4 will be released, do you plan to migrate to VLC4 ?
The UI will be completely moved to much more modern tech on VLC4. I plan only to take what users really want & technical "under-the-hood" improvements provided by VLC4. VLC4 is not even released at this point, but as of today I plan to keep on the legacy of VLC3 visually and in terms of user experience just like how PowerFox remained on the legacy of the Firefox Australis user experience.

## Current quality level
I believe most features will work, with some obvious limitations on old systems. Though there's real chances things will work bad for you on your specific machine, which is also why I encourage donations which will afford me to get more legacy Macs models to test on.

## Retro machines general usage tricks
- Use also some others *neo-retro* projects like Basilisk (10.7+) or PowerFox (10.4+) so you can find radio streams links to send on to PowerVLC from the modern web ; enjoy synergies
- https://macintoshgarden.org/ is awesome, browsing this site from old Safari works really well and this site is very "old browsers" friendly
- If you have access to JellyFin servers, use "JellyDinosaur" my superfast JellyFin front-end so you can generate easily streaming links to use with PowerVLC. (It's not yet released sorry, I got trapped too much into the PowerVLC rabbit hole !)
- Best way to share files to an old Mac from a modern machine is by setting up the AFP protocol with netatalk using Docker: https://netatalk.io/docker PowerVLC was tested and it can stream files just fine directly from an AFP shared drive.
- On G3 machines, forget about USB because USB1.1 is nightmarishly slow as hell. Though if you still own Firewire 400 devices, those will be fast, Firewire 400 is close to USB2.

## Support
PowerVLC is an hobby project. Don't expect professionnal support & quick reviews to your PR or questions, or to assist you personnally if you have a problem. Patreon members are prioritized on individual support, with no guarantees too. I share all of my work because I believe in its quality and because it is at least useful to me and I am sure at least someone else will enjoy all the effort, but I don't want too much pressure and to keep your expectations reasonable. I am a solo dev, not affiliated with the whole VideoLAN organization (which is also a non-profit by the way).

I am not making a Discord and my own community platforms because I want to pass my time on the code on my projects and focused on quality of the application rather than on moderation & community management.

I plan to keep up at following the next VLC3 updates, but won't provide any guarantees even by doing my best at making things right.

If you encounter a problem, the good practice there is to make a GitHub issue indicating : 
- Your machine & GPU
- Exact MacOS version
- What happenned and how to reproduce
- Launch the binary with -vv args then dump the console logs & provide them in your report (not mandatory but can help)

More data & context you give, more likely I will be able to reproduce then submit a patch to improve your experience.

## AI usage
- Not the README, social media posts, and support. I want to keep this human.
- The AI automated some tests during dev, but everything I produced was carefully human tested on real machines, and heavily iterated so it won't feel as "AI slop"
- Heavy usage for code generation. Most of the code was entirely AI generated, though it does not mean this app was "vibe coded", as the AI did shit/wrong many times. Plenty of manual work had to be done and the years of real experiences working on several projects helped me to drive the new fancy AI tools. It's not vibe code there, it's hard work, repetitive work, but much accelerated by AI tools handled with love.

## Contact & Support
Here you can support me financially: https://www.patreon.com/Olsro

To contact me directly, here is also my email: olsroparadise@proton.me

You can support this work by putting a star in this GitHub project, writing positive comments all around, and by recommending this application to your relatives.

Please do not contact me for support requests & use only GitHub issues ideally. I believe most issues you may find should be visible to the whole community. It's better for transparency & this allow me to link code (PR) linked directly with your issues.

Right now at the date of writing (2026-07-26), the project is in early access which means the code right there is up to date but the compiled builds to download are exclusively available for my Patreons during one week from here: https://www.patreon.com/Olsro/posts/early-access-1-0-164876918 . I don't plan to lock all builds behind a one week early access, but for the launch it's the only compromise I found to keep open knowledge in the long term while inciting people to cover my API costs and compensate a bit of the countless of hours I put into building that project.

## Credits
- All contributors from VLC/VideoLAN since the beginning
- Jean-Baptiste Kempf for being a source of inspiration & motivation. VLC is really one of the most important programs coming from the "french tech", using it since years and it was always installed on all of my computers as the must have program that can play anything I throw on it.
- All the contributors from all the open source contrib projects related to this project
- All of my Patreons for supporting me financially
