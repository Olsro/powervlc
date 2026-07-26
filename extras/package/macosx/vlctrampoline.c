/*****************************************************************************
 * vlctrampoline.c: PowerVLC universal-bundle architecture trampoline
 *****************************************************************************
 * This tiny program is the bundle's CFBundleExecutable. It exists to work
 * around a fatal quirk of old, 64-bit-capable Macs:
 *
 *   Tiger (10.4) and Leopard (10.5) on a 64-bit-capable CPU grade a
 *   universal binary's 64-bit slice HIGHEST and run it, even though they
 *   have no 64-bit Cocoa/AppKit -- the real VLC then crashes at launch
 *   (EXC_BREAKPOINT / "unknown load command 0x8000001C"). Their
 *   LaunchServices also predates and ignores LSMinimumSystemVersionByArch,
 *   so the Info.plist gate cannot save them.
 *
 * The trick (documented behaviour): those systems DO run 64-bit *Unix*
 * binaries -- just not the Cocoa API. This stub links ONLY libSystem, so its
 * own 64-bit slice runs fine there; it then re-exec()s the real binary,
 * choosing a slice set the running OS can actually use:
 *
 *   Darwin kernel major <= 9  (Tiger 10.4, Leopard 10.5)  -> legacy_powerVLC
 *                                       (i386 + ppc, no 64-bit slice, so the
 *                                        kernel cannot mis-grade to 64-bit)
 *   otherwise (Snow Leopard 10.6 and newer)               -> fat_powerVLC
 *                                       (the full universal binary)
 *
 * Both real binaries MUST end in "VLC": libvlccore derives its plugin
 * directory (src/darwin/dirs.c, config_GetLibDir) by finding a loaded image
 * whose name ends in "VLC". argv is passed through UNCHANGED -- notably the
 * -psn_* handed over by LaunchServices, without which the GUI session
 * hand-off breaks and the app comes up with no window.
 *
 * Built for every architecture the bundle ships (i386/ppc via the legacy
 * toolchain, x86_64/arm64 via clang) by extras/package/macosx/make-universal.sh.
 *****************************************************************************/
#include <unistd.h>
#include <sys/utsname.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <limits.h>
#include <libgen.h>
#include <mach-o/dyld.h>   /* _NSGetExecutablePath */

int main(int argc, char **argv)
{
    char exe[PATH_MAX];
    uint32_t sz = sizeof(exe);
    if (_NSGetExecutablePath(exe, &sz) != 0)
        return 66;

    /* dirname() may scribble on its argument: give it a copy */
    char dircopy[PATH_MAX];
    strncpy(dircopy, exe, sizeof(dircopy));
    dircopy[sizeof(dircopy) - 1] = '\0';
    char *dir = dirname(dircopy);

    struct utsname u;
    int major = 0;
    if (uname(&u) == 0)                 /* robust under 64-bit on Tiger,     */
        major = atoi(u.release);        /* unlike sysctlbyname("kern.osrelease") */

    const char *primary  = (major > 0 && major <= 9) ? "legacy_powerVLC"
                                                     : "fat_powerVLC";
    const char *fallback = (major > 0 && major <= 9) ? "fat_powerVLC"
                                                     : "legacy_powerVLC";

    char target[PATH_MAX];
    snprintf(target, sizeof(target), "%s/%s", dir, primary);
    if (access(target, X_OK) != 0)      /* bundle may ship only one variant */
        snprintf(target, sizeof(target), "%s/%s", dir, fallback);

    argv[0] = target;                   /* keep argv (incl. -psn_*) intact  */
    execv(target, argv);
    perror("PowerVLC trampoline: execv");
    return 127;
}
