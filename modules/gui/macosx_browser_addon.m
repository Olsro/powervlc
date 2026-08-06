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

/* This file is compiled into both interfaces: the modern one under ARC, the
 * legacy one under manual retain/release with a GCC that predates ARC
 * entirely. A Core Foundation pointer handed to Objective-C needs __bridge
 * under ARC and must not carry it otherwise, and __has_feature itself does
 * not exist on the legacy compiler. */
#ifndef __has_feature
# define __has_feature(x) 0
#endif
#if __has_feature(objc_arc)
# define VLC_BRIDGE(type, expr) ((__bridge type)(expr))
#else
# define VLC_BRIDGE(type, expr) ((type)(expr))
#endif

/* Both interfaces compile this file, and on 10.7+ both plugins can be resident
 * at once (the interface switcher). The anchor class below must therefore not
 * carry the same name in the two copies, or the Objective-C runtime warns that
 * it is implemented twice. Each plugin's Makefile.am passes its own tag. */
#ifndef VLC_OBJC_ANCHOR_TAG
# define VLC_OBJC_ANCHOR_TAG Shared
#endif
#define VLC_ANCHOR_JOIN_(a, b) a##b
#define VLC_ANCHOR_JOIN(a, b) VLC_ANCHOR_JOIN_(a, b)
#define VLC_ANCHOR_CLASS(base) VLC_ANCHOR_JOIN(base, VLC_OBJC_ANCHOR_TAG)

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
                  absolutePathForAppBundleWithIdentifier:VLC_BRIDGE(NSString *, cfIdent)];
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

/*****************************************************************************
 * ⚠ ANCRE OBJECTIVE-C — NE PAS SUPPRIMER (Mac OS X 10.2)
 *****************************************************************************
 * Même défaut que dans macosx_crystalhd.m, et pour la même raison : ce
 * fichier utilise Objective-C (Cocoa) mais ne définissait aucune classe, donc
 * son module laisse `module->symtab` à NULL. L'`_objcInit()` de 10.2 le
 * déréférence et tue le processus au `dlopen` du greffon qui le contient —
 * ici encore l'interface legacy, l'unique fournisseur de fenêtre vidéo.
 * Compiler en .c n'est pas une option : le fichier envoie des messages à
 * NSWorkspace. Contrôlé par extras/package/macosx/check-objc-modules.sh.
 *****************************************************************************/
@interface VLC_ANCHOR_CLASS(VLCBrowserAddonObjCAnchor) : NSObject
@end
@implementation VLC_ANCHOR_CLASS(VLCBrowserAddonObjCAnchor)
@end
