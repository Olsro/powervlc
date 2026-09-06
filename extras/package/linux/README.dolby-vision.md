# Native Dolby Vision HDMI on Linux

Linux DRM exposes HDR10 metadata but, through kernel 7.0, has no public Dolby
Vision connector property. PowerVLC therefore separates rendering from the
vendor-specific HDMI transport:

* `--gl-dovi-hdmi --gl-dovi-peak=<nits>` makes the OpenGL Dolby Vision renderer
  produce a 10-bit BT.2020/PQ source-led signal. Without this switch the normal
  SDR tone mapper remains active.
* `powervlc-intel-dovi-helper` installs the Dolby Vision VSIF below Xorg or
  Wayland. It accepts no register addresses or values, verifies the physical
  EDID, active 10-bit scanout and known i915 InfoFrame layout, and restores the
  exact original packets on exit.

Build the helper with:

```sh
cc -O2 -Wall -Wextra -o powervlc-intel-dovi-helper \
  powervlc-intel-dovi-helper.c
```

For a manual test, start PowerVLC first and then keep the helper alive for that
process:

```sh
sudo ./powervlc-intel-dovi-helper --pid "$(pgrep -n powervlc)"
```

The helper currently enables Intel i915 HSW-and-newer transcoders after runtime
layout checks. AMDGPU and NVIDIA do not expose a stable userspace API for an
arbitrary Dolby VSIF; PowerVLC uses their public HDR10 path when available and
otherwise its SDR tone mapper. A future DRM Dolby property can be added as a
higher-priority transport backend without changing the renderer.

An X11 or Xwayland OpenGL window cannot advertise an HDR colorspace. PowerVLC
therefore presents its fallback as ordinary sRGB after applying the Dolby RPU
and tone mapping. If GNOME's HDR mode is active, Mutter converts that sRGB
window to the BT.2100 desktop output. PowerVLC deliberately does not apply a
second HDR-desktop curve: doing so destroys highlight detail. This same path is
also the safe fallback on SDR displays and on older desktops without HDR color
management.

The Linux x86/x86_64 AppImages retain a glibc 2.27 floor (Ubuntu 18.04). The
transport is independent of desktop protocol and works from Xorg and Wayland;
the compositor must provide a 10-bit scanout before the helper will enable it.
