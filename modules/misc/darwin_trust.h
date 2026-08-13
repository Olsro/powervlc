/*****************************************************************************
 * darwin_trust.h: trust anchors of the Mac OS X keychain
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

#ifndef VLC_DARWIN_TRUST_H
#define VLC_DARWIN_TRUST_H 1

#include <stddef.h>

/**
 * Callback receiving one trust anchor, DER-encoded. The buffer is only valid
 * for the duration of the call.
 */
typedef void (*vlc_darwin_anchor_cb)(void *opaque, const unsigned char *der,
                                     size_t len);

/**
 * Walks the trust anchors of the Mac OS X keychain, i.e. the certificate
 * authorities the system ships plus the ones the user added and marked as
 * trusted, minus the ones marked as untrusted.
 *
 * @return the number of anchors passed to the callback, or -1 when the
 * keychain cannot be read at all (Mac OS X 10.2, whose Security framework
 * predates the API).
 */
int vlc_darwin_foreach_anchor(vlc_darwin_anchor_cb cb, void *opaque);

#endif
