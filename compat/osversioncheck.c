/*****************************************************************************
 * osversioncheck.c: GCD-free __builtin_available() runtime for Mac OS X 10.5
 *****************************************************************************
 * Copyright © 2026 VLC authors and VideoLAN
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/* Clang compiles __builtin_available()/@available into calls to compiler-rt's
 * __isOSVersionAtLeast(), whose implementation relies on Grand Central
 * Dispatch (dispatch_once_f) -- absent from Mac OS X 10.5, the very release
 * those guards are supposed to protect. Defining the symbol here (libcompat
 * is linked into libvlccore, every plugin and the binaries, ahead of the
 * compiler-rt builtins archive the driver appends) shadows compiler-rt's
 * version with one that only needs sysctl(3). Only compiled in when
 * targeting Mac OS X releases without GCD; see configure.ac. */

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#ifdef __APPLE__

#include <stdint.h>
#include <stdio.h>
#include <sys/types.h>
#include <sys/sysctl.h>

int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor);
int32_t __isPlatformVersionAtLeast(uint32_t platform, int32_t major,
                                   int32_t minor, int32_t subminor);

static void version_get(int32_t ver[3])
{
    char buf[48];
    size_t len = sizeof (buf) - 1;

    ver[0] = ver[1] = ver[2] = 0;

    /* Exact product version; sysctl present since Mac OS X 10.13.4 */
    if (sysctlbyname("kern.osproductversion", buf, &len, NULL, 0) == 0)
    {
        buf[len] = '\0';
        if (sscanf(buf, "%d.%d.%d", &ver[0], &ver[1], &ver[2]) >= 2)
            return;
    }

    /* Fallback: map the Darwin kernel major version. Exact for the
     * releases lacking the sysctl above (Darwin 9 = 10.5 ... 17 = 10.13);
     * the bugfix component is unknowable here and left at 0. */
    len = sizeof (buf) - 1;
    if (sysctlbyname("kern.osrelease", buf, &len, NULL, 0) == 0)
    {
        int darwin_major = 0;
        buf[len] = '\0';
        if (sscanf(buf, "%d", &darwin_major) == 1 && darwin_major >= 4)
        {
            if (darwin_major >= 20) /* Darwin 20 = macOS 11 */
            {
                ver[0] = darwin_major - 9;
                ver[1] = 0;
            }
            else
            {
                ver[0] = 10;
                ver[1] = darwin_major - 4;
            }
        }
    }
}

static const int32_t *version_cached(void)
{
    /* No synchronization: concurrent first calls all write the same
     * values, and the guard is only flipped after they are in place. */
    static int32_t ver[3];
    static volatile int initialized = 0;

    if (!initialized)
    {
        version_get(ver);
        initialized = 1;
    }
    return ver;
}

int32_t __isOSVersionAtLeast(int32_t major, int32_t minor, int32_t subminor)
{
    const int32_t *ver = version_cached();

    if (ver[0] != major)
        return ver[0] > major;
    if (ver[1] != minor)
        return ver[1] > minor;
    return ver[2] >= subminor;
}

/* Newer clang releases emit this variant instead (platform 1 = macOS);
 * forward, ignoring the platform: this file only ever targets macOS. */
int32_t __isPlatformVersionAtLeast(uint32_t platform, int32_t major,
                                   int32_t minor, int32_t subminor)
{
    (void) platform;
    return __isOSVersionAtLeast(major, minor, subminor);
}

#endif /* __APPLE__ */
