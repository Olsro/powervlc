/*****************************************************************************
 * macosx_browser_addon.m: hand the browser add-on to the user's browser
 *****************************************************************************
 * Copyright (C) 2026 the PowerVLC team
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/* The add-on is the browser half of PowerVLC: it sends what the browser is
 * playing over to the player, and lets the player read pages the user has
 * opened -- the only way in on browsers older than Firefox 69, which
 * refuse to run a bookmarklet on any page carrying a security policy.
 *
 * Installing it is one click: open the .xpi with the browser the user
 * already uses, and the browser takes it from there. Opening it with
 * LaunchServices alone would not do -- nothing on a Mac claims .xpi -- so
 * the default handler for http:// is asked for by name. */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

#include <vlc_common.h>
#include <vlc_configuration.h>

#import "macosx_browser_addon.h"

NSString *VLCBrowserAddonPath(void)
{
    char *psz_dir = config_GetDataDir();
    if (psz_dir == NULL)
        return nil;

    NSString *path = [[NSString stringWithUTF8String:psz_dir]
                        stringByAppendingPathComponent:@"powervlc.xpi"];
    free(psz_dir);

    if (![[NSFileManager defaultManager] fileExistsAtPath:path])
        return nil;
    return path;
}

/* The browser the user actually browses with, which is the only one worth
 * putting the add-on in. LSCopyDefaultHandlerForURLScheme is there from
 * 10.4 on, so this works on every system the fork supports. */
static NSString *VLCDefaultBrowserPath(void)
{
    NSString *path = nil;
    CFStringRef cfIdent = LSCopyDefaultHandlerForURLScheme(CFSTR("http"));

    if (cfIdent != NULL) {
        path = [[NSWorkspace sharedWorkspace]
                  absolutePathForAppBundleWithIdentifier:(NSString *)cfIdent];
        CFRelease(cfIdent);
    }
    return path;
}

BOOL VLCBrowserAddonInstall(void)
{
    NSString *addon = VLCBrowserAddonPath();
    if (addon == nil)
        return NO;

    NSString *browser = VLCDefaultBrowserPath();
    if (browser != nil
     && [[NSWorkspace sharedWorkspace] openFile:addon
                                withApplication:browser])
        return YES;

    /* No default browser, or it turned the file down: let the system try
     * whatever it has. Better a Finder window than a menu item that looks
     * broken. */
    return [[NSWorkspace sharedWorkspace] openFile:addon];
}
