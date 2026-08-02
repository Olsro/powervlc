/*****************************************************************************
 * VLCLegacyExtensionsDialogProvider.h: extension dialogs (legacy interface)
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

#import <Cocoa/Cocoa.h>

#include <vlc_common.h>
#include <vlc_interface.h>

/* Renders the dialogs that Lua extensions build (VLSub's configuration
 * window, for instance). Without a provider registered through
 * vlc_dialog_provider_set_ext_callback(), an extension creates its dialog and
 * nothing ever displays it: clicking the extension simply does nothing. Only
 * Qt and the modern Mac interface had one. */
@interface VLCLegacyExtensionsDialogProvider : NSObject
{
    intf_thread_t *p_intf;
}

- (id)initWithIntf:(intf_thread_t *)intf;

/* Unregisters the callback. Must run before the object is released, so that
 * no core thread can reach a half-destroyed provider. */
- (void)stop;

@end
