# Native HDMI frame-packed 3D on Linux

PowerVLC's `kms3d` video output sends decoded MVC eyes through the standard
DRM/KMS stereo API. It reads the physical display modes after enabling
`DRM_CLIENT_CAP_STEREO_3D`, selects the frame-packing timing closest to the
content rate, and restores every CRTC and connector when playback ends. No
EDID override or vendor API is used.

Desktop compositors generally omit stereo modes and own DRM master. The
`powervlc-kms3d-run` launcher therefore moves playback to a dedicated virtual
terminal, where the same KMS path works below Wayland or Xorg. It temporarily
adds the launching user to the child process's `video` group; no permanent
group change or capability is required. Other displays on the selected GPU are
blanked for playback and their exact state is restored afterward.

The launcher also forwards the standard VLC keyboard shortcuts and pointer
events while the graphical session is inactive. Space pauses and resumes;
menu arrows, media keys, volume, seek, track and subtitle shortcuts retain
their normal VLC actions. Escape, `F`, or a double click releases DRM/KMS and
restores the graphical terminal. The same PowerVLC process and Blu-ray input
stay alive, so BD-J menu state and playback position are preserved. Pressing
`F`, using the fullscreen button, or double-clicking the window reacquires DRM
and selects the frame-packing timing again instead of stretching the two-eye
image inside an ordinary desktop fullscreen window. The launcher changes the
hidden VT to graphics mode before either transition, preventing framebuffer
console text from flashing on both multi-display and single-display systems.

With an AppImage beside the launcher:

```sh
./powervlc-kms3d-run ./PowerVLC-x86_64.AppImage \
  bluray:///path/to/disc-or-image.iso
```

The launcher uses polkit when invoked by a desktop user. Systems without
`pkexec` can run the same command through `sudo`. It requires the standard
Linux `kbd` (`openvt`, `fgconsole`, `chvt`) and `util-linux` (`setpriv`)
utilities, plus a kernel DRM driver exposing HDMI stereo modes. The DRM stereo
client capability has been available since Linux 3.13. Intel i915 was validated
with 1080p at 24000/1001; AMDGPU, Nouveau and NVIDIA DRM use the same UAPI and
are selected without vendor-specific branches when their driver publishes a
matching mode.
