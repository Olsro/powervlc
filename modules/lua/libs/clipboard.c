/*****************************************************************************
 * clipboard.c: system clipboard access for Lua scripts
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

#ifndef  _GNU_SOURCE
#   define  _GNU_SOURCE
#endif

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <stdbool.h>

#include <vlc_common.h>
#include <vlc_plugin.h>

#include "../vlc.h"
#include "../libs.h"

#if defined(__APPLE__)
/* Plain C through the Objective-C runtime: NSPasteboard is resolved at run
 * time, so this file neither links AppKit nor needs an Objective-C compiler,
 * and the exact same code covers Mac OS X 10.2 through current macOS. */
#include <objc/objc-runtime.h>
#include <CoreFoundation/CoreFoundation.h>

typedef id   (*vlc_objc_send_id)(id, SEL);
typedef long (*vlc_objc_send_long2)(id, SEL, id, id);

static bool ClipboardSetText(const char *psz_text)
{
    bool b_ok = false;
    Class pb_class = objc_getClass("NSPasteboard");
    Class pool_class = objc_getClass("NSAutoreleasePool");
    if (pb_class == NULL || pool_class == NULL)
        return false;   /* AppKit is not loaded: headless run */

    id pool = ((vlc_objc_send_id)objc_msgSend)((id)pool_class,
                                               sel_registerName("new"));

    id pb = ((vlc_objc_send_id)objc_msgSend)((id)pb_class,
                                             sel_registerName("generalPasteboard"));
    if (pb != NULL)
    {
        /* NSStringPboardType by value; current macOS bridges it to
         * public.utf8-plain-text, 10.2 knows it natively */
        CFStringRef type = CFSTR("NSStringPboardType");
        CFStringRef text = CFStringCreateWithCString(kCFAllocatorDefault,
                                                     psz_text,
                                                     kCFStringEncodingUTF8);
        if (text != NULL)
        {
            CFArrayRef types = CFArrayCreate(kCFAllocatorDefault,
                                             (const void **)&type, 1,
                                             &kCFTypeArrayCallBacks);
            if (types != NULL)
            {
                ((vlc_objc_send_long2)objc_msgSend)(pb,
                    sel_registerName("declareTypes:owner:"),
                    (id)types, NULL);
                b_ok = ((vlc_objc_send_long2)objc_msgSend)(pb,
                    sel_registerName("setString:forType:"),
                    (id)text, (id)type) != 0;
                CFRelease(types);
            }
            CFRelease(text);
        }
    }

    ((vlc_objc_send_id)objc_msgSend)(pool, sel_registerName("release"));
    return b_ok;
}

#elif defined(_WIN32)
#include <windows.h>

static bool ClipboardSetText(const char *psz_text)
{
    int i_len = MultiByteToWideChar(CP_UTF8, 0, psz_text, -1, NULL, 0);
    if (i_len <= 0)
        return false;

    HGLOBAL h = GlobalAlloc(GMEM_MOVEABLE, (SIZE_T)i_len * sizeof(WCHAR));
    if (h == NULL)
        return false;
    WCHAR *dst = GlobalLock(h);
    if (dst == NULL)
    {
        GlobalFree(h);
        return false;
    }
    MultiByteToWideChar(CP_UTF8, 0, psz_text, -1, dst, i_len);
    GlobalUnlock(h);

    if (!OpenClipboard(NULL))
    {
        GlobalFree(h);
        return false;
    }
    EmptyClipboard();
    bool b_ok = SetClipboardData(CF_UNICODETEXT, h) != NULL;
    CloseClipboard();
    if (!b_ok)
        GlobalFree(h);   /* ownership only moves to the system on success */
    return b_ok;
}

#else

static bool ClipboardSetText(const char *psz_text)
{
    /* No portable clipboard without a toolkit on this platform; scripts
     * fall back to showing the text in a selectable field. */
    (void)psz_text;
    return false;
}

#endif

/*****************************************************************************
 * Lua bindings
 *****************************************************************************/

static int vlclua_clipboard_set( lua_State *L )
{
    const char *psz_text = luaL_checkstring( L, 1 );
    lua_pushboolean( L, ClipboardSetText( psz_text ) );
    return 1;
}

static const luaL_Reg vlclua_clipboard_reg[] = {
    { "set", vlclua_clipboard_set },
    { NULL, NULL }
};

void luaopen_clipboard( lua_State *L )
{
    lua_newtable( L );
    luaL_register( L, NULL, vlclua_clipboard_reg );
    lua_setfield( L, -2, "clipboard" );
}
