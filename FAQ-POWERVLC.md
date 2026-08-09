# FAQ

## Why the name PowerVLC?
Because it supports PowerPC Macs and I got inspired by PowerFox which is also a very high quality project to keep old machines alive.

## Is this really VLC3? How is that possible? Did VideoLAN abandon old Mac OS because they were lazy?
In reality, the Legacy UI that you will use and that feels the same has been recoded from scratch in AppKit to be compatible with 10.2+. Many edge cases & tests had to be done on real machines. AI helped, but even with AI, VLC is still one of the most complex applications in the world. Considering the amount of implied work, their decision to drop some compatibility over time is totally understandable. Supporting older systems is not magical, there's plenty of edge cases & API support each time you target one more older system with all the related machines. Things get even more complicated by adding other architectures: Intel x86 / PPC / PPC AltiVec. It's impressive they could still keep up at maintaining Windows XP compatibility as of this day.

Even Mac OS X 10.5 and 10.6 that feel mostly the same graphically had many internal differences in reality.

PowerVLC is derived from the whole VLC3 source code and crafted with love for you to feel the same, but internally many things had to be improved so it feels great & powerful on your legacy hardware & OS. And some things had to be heavily recoded & changed internally so it can just work as intended on this hardware, even if you probably won't feel it because everything has been carefully tested for you to feel the same at usage.

## When VLC4 is released, do you plan to rebase on VLC4?
The UI will be completely moved to much more modern tech on VLC4. I plan only to take what users really want & technical "under-the-hood" improvements provided by VLC4. VLC4 is not even released at this point, but as of today I plan to keep on the legacy of VLC3 visually and in terms of user experience just like how PowerFox remained on the legacy of the Firefox Australis user experience.

## What about upstream VLC?
I don't have the time to invest on making those improvements available on upstream VLC, though I allow anyone to submit patches on my behalf if you've got interest in any of them. Just credit me and the name of this fork (PowerVLC) on the description of your commits & pull requests. No gatekeeping there, sharing is caring.

## Supporting MacOS Classic (9) or X 10.0/10.1?
Not planned.

## Current quality level
I believe most features will work, with some obvious limitations on old systems. Though there's real chances things will work bad for you on your specific machine, which is also why I encourage donations which will afford me to get more legacy Macs models to test on.
