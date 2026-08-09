# How it feels on real hardware

Tested on real hardware I own, here's my reports. Compared to old VLC (especially 0.9.10 from 2009), expect much more stability & features, enjoy there more than 15 years of dev & bug fixes from the VLC team.

Compared to VLC 2.x old builds, there's still many "real world" improvements, I am for example thinking on the much improved m3u8 support so if you can find transcoded low-res streams, it will work really great with seeking, audio, etc.

Here's some examples using my own legacy machines.
*(I don't own all generations, so feel free to share your results on social medias, I am very curious to know how PowerVLC behaves on your own hardware!)*

## iBook G3
Running with 384MB of RAM. HDD was replaced with a 128GB mSata SSD.
*Tested with 10.2.8 (Jaguar), 10.3.9 (Panther) and 10.4.11 (Tiger).*

- Can generally play/stream 240p contents in AV1, H265, H264.
- DVDs work really great, around 50% of CPU load just like how the real Apple DVD Player app can achieve on this hardware. It's fully accelerated by the GPU, subtitles and menu highlights included — validated on Radeon *and* Rage 128 machines, on all three of 10.2, 10.3 and 10.4.
- Good as a FLAC music player, the modern UI shines and is way more capable than what 0.9.10 was capable of back then on Tiger. I did not try effects but for simple music playback it does the job reliably, and plays everything gapless.

## Mac Mini G4
Running on Tiger, 1GB of RAM. HDD was replaced with a 128GB mSata SSD.
*Tested with both 10.4.11 (Tiger) and 10.5.8 (Leopard).*

- Can generally play/stream 480p contents in AV1, H265, H264. 720p may work sometimes with very low bitrates but is over the specs.
- For 720p content, you may want to enable the look-ahead cache to get smooth playback, at the expense of regular pauses to fill the cache (in my opinion it's pretty bad but it's at least watchable rather than a movie with constant frame drops all over the place).
- DVD content is smooth with deinterlacing ON, no surprises it's easy for this machine.

## MacBook 2007 (GMA950 / Core 2 Duo)
*Tested with 10.5.8 (Leopard) and 10.6.8 (Snow Leopard).*

This machine is like the good old Intel Atom netbooks but featuring a much faster 64 bits CPU. The GMA950 is known to really put it down and is not even capable of doing h.264 hardware decoding.

Expect easy 720p files handling, and even lite 1080p. Though your problem will be the heat, those Core 2 Duo get hot when you push them too hard.

Blu-ray remuxes work reliably with the look-ahead cache enabled, but CPU will be maxed all the time.

If you add a **Crystal HD** (BCM70015) mini-PCIe card, PowerVLC now drives it: H.264, VC-1 and MPEG-2 are offloaded to the card and 1080p is held with low CPU usage. The kernel extension is bundled and installed straight from the Help menu. Modded Apple TVs, Mac Minis and hackintoshed netbooks get the same second breath.

## MacBook Pro 2010 13-inch (NVIDIA 320m)
*Tested with 10.6.8 (Snow Leopard) and 10.9.5 (Mavericks).*

PowerVLC is shining there with HD content, using full VDA hardware acceleration even on Snow Leopard. Blu-rays can be played with very low CPU usage.
