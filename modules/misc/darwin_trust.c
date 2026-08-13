/*****************************************************************************
 * darwin_trust.c: trust anchors of the Mac OS X keychain
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

/* GnuTLS has no backend for the Apple keychain: on every Mac OS X release,
 * gnutls_certificate_set_x509_system_trust() fails with "unimplemented", so
 * the only authorities VLC knows are the ones it ships itself. A root the
 * user installed for an internal site is therefore ignored.
 *
 * SecTrustCopyAnchorCertificates() returns the *effective* anchor set: the
 * authorities of SystemRootCertificates.keychain plus the ones the user gave
 * a "trust as root" setting to, and minus the ones marked as untrusted --
 * measured on 10.6.8, where a root added with "add-trusted-cert -r trustRoot"
 * appears in the list and the same root set to "-r deny" disappears from it
 * while remaining physically present in the keychain files. Enumerating the
 * keychains with SecKeychainSearch would have trusted that denied root, and
 * would also have promoted to anchor every leaf certificate the user merely
 * stored; this API is both simpler and the only safe one.
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <stddef.h>
#include <stdint.h>

#include <AvailabilityMacros.h>
#include <CoreFoundation/CoreFoundation.h>

#include "darwin_trust.h"

/* Deliberately NOT including <Security/Security.h>: weak_import only takes
 * effect on the FIRST declaration of a symbol, and the SDK header declares
 * these without it. Declaring them here keeps the choice a run-time one on
 * every slice -- the ppc ones are built against the 10.4 SDK but deploy down
 * to 10.2, where SecTrustCopyAnchorCertificates (10.3) does not exist, and
 * the x86_64/arm64 ones are built against a current SDK yet deploy down to
 * 10.5. A compile-time #if on the SDK version would guard neither.
 * SecCertificateRef is an opaque pointer, so void * is ABI-compatible. */
typedef void *vlc_SecCertificateRef;

extern int32_t SecTrustCopyAnchorCertificates(CFArrayRef *anchors)
    __attribute__((weak_import));                               /* 10.3+ */

/* Getting the DER out of a certificate needs two different functions, and
 * which of them may even be *named* is an SDK question, not a runtime one:
 * weak_import still requires the linker to find the symbol in the SDK stub.
 * SecCertificateCopyData is 10.5, so the 10.4 SDK does not export it and
 * referencing it there fails to link; SecCertificateGetData goes back to
 * 10.0 and is still exported today, but is only of use below 10.6. Hence one
 * guard on MAX_ALLOWED (what the SDK can name) and one on MIN_REQUIRED (what
 * the oldest supported system needs) -- and a NULL test on top of both,
 * because a slice built against a current SDK still deploys down to 10.5. */
#if !defined(MAC_OS_X_VERSION_MAX_ALLOWED) \
 || MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
extern int32_t SecCertificateCopyData(vlc_SecCertificateRef cert,
                                      CFDataRef *data)
    __attribute__((weak_import));                               /* 10.5+ */
# define VLC_HAVE_CERT_COPY_DATA 1
#endif

#if !defined(MAC_OS_X_VERSION_MIN_REQUIRED) \
 || MAC_OS_X_VERSION_MIN_REQUIRED < 1060
/* ⚠ The threshold is 10.6, not the 10.5 the documentation gives for
 * SecCertificateCopyData: measured on Leopard 10.5.8 (MacBook 2007), the
 * Security framework does NOT export it -- dlsym returns NULL while
 * SecCertificateGetData is there. The x86_64 slice deploys to 10.5, so
 * without this fallback it would read the keychain and get nothing out of
 * it. Current SDKs still export SecCertificateGetData, so referencing it
 * costs nothing.
 *
 * CSSM_DATA is { CSSM_SIZE Length; uint8 *Data; }, CSSM_SIZE being
 * pointer-sized, so size_t matches. The buffer belongs to the certificate
 * object and must not be freed. */
struct vlc_cssm_data
{
    size_t Length;
    unsigned char *Data;
};

extern int32_t SecCertificateGetData(vlc_SecCertificateRef cert,
                                     struct vlc_cssm_data *data)
    __attribute__((weak_import));                               /* 10.0+ */
# define VLC_HAVE_CSSM_CERT_DATA 1
#endif

/* Hands one certificate's DER encoding to the callback. */
static int vlc_darwin_anchor_der(vlc_SecCertificateRef cert,
                                 vlc_darwin_anchor_cb cb, void *opaque)
{
#ifdef VLC_HAVE_CERT_COPY_DATA
    if (&SecCertificateCopyData != NULL)
    {
        CFDataRef data = NULL;

        if (SecCertificateCopyData(cert, &data) == 0 && data != NULL)
        {
            cb(opaque, CFDataGetBytePtr(data), CFDataGetLength(data));
            CFRelease(data);
            return 0;
        }
    }
#endif
#ifdef VLC_HAVE_CSSM_CERT_DATA
    if (&SecCertificateGetData != NULL)
    {
        struct vlc_cssm_data data = { 0, NULL };

        if (SecCertificateGetData(cert, &data) == 0 && data.Data != NULL)
        {
            cb(opaque, data.Data, data.Length);
            return 0;
        }
    }
#endif
    return -1;
}

int vlc_darwin_foreach_anchor(vlc_darwin_anchor_cb cb, void *opaque)
{
    CFArrayRef anchors = NULL;

    if (&SecTrustCopyAnchorCertificates == NULL)
        return -1;
    if (SecTrustCopyAnchorCertificates(&anchors) != 0 || anchors == NULL)
        return -1;

    CFIndex count = CFArrayGetCount(anchors);
    int done = 0;

    for (CFIndex i = 0; i < count; i++)
    {
        vlc_SecCertificateRef cert =
            (vlc_SecCertificateRef)CFArrayGetValueAtIndex(anchors, i);

        if (cert != NULL && vlc_darwin_anchor_der(cert, cb, opaque) == 0)
            done++;
    }

    CFRelease(anchors);
    return done;
}
