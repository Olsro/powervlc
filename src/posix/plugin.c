/*****************************************************************************
 * plugin.c : Low-level dynamic library handling
 *****************************************************************************
 * Copyright (C) 2001-2007 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Sam Hocevar <sam@zoy.org>
 *          Ethan C. Baldridge <BaldridgeE@cadmus.com>
 *          Hans-Peter Jansen <hpj@urpla.net>
 *          Gildas Bazin <gbazin@videolan.org>
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include "modules/modules.h"

#include <sys/types.h>

/* Mac OS X 10.2 has no dlopen(): the dynamic loader compatibility functions
 * only arrived with 10.3, and before that the way to load a bundle was the
 * dyld "library functions" (NSCreateObjectFileImageFromFile/NSLinkModule).
 * VLC used to carry that backend -- it was dropped in 2009 (commit 27953d60c9)
 * because NSModule crashed on 64-bit, which cannot happen on the 32-bit
 * PowerPC slices this branch targets.
 *
 * <dlfcn.h> declares dlopen() without any availability annotation, so unlike
 * every other pre-10.4 API the linker would emit a HARD reference to it and
 * the whole app would die at launch on 10.2 with "Symbol not found: _dlopen"
 * -- with nothing weak-imported for check-weak-symbols.sh to report. We
 * therefore declare the four functions ourselves as weak_import, which makes
 * the choice a runtime one: the very same binary uses dlopen() from 10.3
 * onwards and falls back to dyld below that. */
#if defined(__APPLE__)
# include <AvailabilityMacros.h>
# if defined(MAC_OS_X_VERSION_MIN_REQUIRED) \
  && MAC_OS_X_VERSION_MIN_REQUIRED < MAC_OS_X_VERSION_10_3
#  define VLC_DYLD_FALLBACK 1
# endif
#endif

#ifdef VLC_DYLD_FALLBACK
/* Deliberately not including <dlfcn.h>: the attribute has to be on the first
 * declaration to take effect. */
# include <mach-o/dyld.h>
extern void *dlopen(const char *, int) __attribute__((weak_import));
extern void *dlsym(void *, const char *) __attribute__((weak_import));
extern int   dlclose(void *) __attribute__((weak_import));
extern char *dlerror(void) __attribute__((weak_import));
# define RTLD_NOW   0x2
# define RTLD_LAZY  0x1
#else
# include <dlfcn.h>
#endif

#ifdef HAVE_VALGRIND_VALGRIND_H
# include <valgrind/valgrind.h>
#endif

/**
 * Load a dynamically linked library using a system dependent method.
 *
 * \param p_this vlc object
 * \param path library file
 * \param p_handle the module handle returned
 * \return 0 on success as well as the module handle.
 */
int module_Load (vlc_object_t *p_this, const char *path,
                 module_handle_t *p_handle, bool lazy)
{
#if defined (RTLD_NOW)
    const int flags = lazy ? RTLD_LAZY : RTLD_NOW;
#elif defined (DL_LAZY)
    const int flags = DL_LAZY;
#else
    const int flags = 0;
#endif

#ifdef VLC_DYLD_FALLBACK
    void *(*p_dlopen)(const char *, int) = dlopen;

    if( p_dlopen == NULL )
    {
        NSObjectFileImage image;

        if( NSCreateObjectFileImageFromFile( path, &image )
                != NSObjectFileImageSuccess )
        {
            msg_Warn( p_this, "cannot create image from `%s'", path );
            return -1;
        }

        /* NSLINKMODULE_OPTION_PRIVATE is RTLD_LOCAL and
         * NSLINKMODULE_OPTION_BINDNOW is RTLD_NOW: a plugin that references a
         * symbol the running system does not have must fail here, cleanly,
         * the way dlopen(RTLD_NOW) does -- that is what lets the loader skip
         * an unusable plugin instead of crashing later. */
        unsigned long options = NSLINKMODULE_OPTION_RETURN_ON_ERROR
                              | NSLINKMODULE_OPTION_PRIVATE;
        if( !lazy )
            options |= NSLINKMODULE_OPTION_BINDNOW;

        NSModule module = NSLinkModule( image, path, options );

        /* The image is only needed to link, not to keep the module alive. */
        NSDestroyObjectFileImage( image );

        if( module == NULL )
        {
            NSLinkEditErrors errors;
            const char *psz_errfile, *psz_err;
            int i_errnum;

            NSLinkEditError( &errors, &i_errnum, &psz_errfile, &psz_err );
            msg_Warn( p_this, "cannot load module `%s' (%s)", path, psz_err );
            return -1;
        }
        *p_handle = module;
        return 0;
    }
#endif

    module_handle_t handle = dlopen (path, flags);
    if( handle == NULL )
    {
        msg_Warn( p_this, "cannot load module `%s' (%s)", path, dlerror() );
        return -1;
    }
    *p_handle = handle;
    return 0;
}

/**
 * CloseModule: unload a dynamic library
 *
 * This function unloads a previously opened dynamically linked library
 * using a system dependent method. No return value is taken in consideration,
 * since some libraries sometimes refuse to close properly.
 * \param handle handle of the library
 * \return nothing
 */
void module_Unload( module_handle_t handle )
{
#ifdef VLC_DYLD_FALLBACK
    int (*p_dlclose)(void *) = dlclose;

    if( p_dlclose == NULL )
    {
        NSUnLinkModule( (NSModule)handle, NSUNLINKMODULE_OPTION_NONE );
        return;
    }
#endif
#if !defined(__SANITIZE_ADDRESS__)
#ifdef HAVE_VALGRIND_VALGRIND_H
    if( RUNNING_ON_VALGRIND > 0 )
        return; /* do not dlclose() so that we get proper stack traces */
#endif
    dlclose( handle );
#else
    (void) handle;
#endif
}

/**
 * Looks up a symbol from a dynamically loaded library
 *
 * This function queries a loaded library for a symbol specified in a
 * string, and returns a pointer to it. We don't check for dlerror() or
 * similar functions, since we want a non-NULL symbol anyway.
 *
 * @param handle handle to the module
 * @param psz_function function name
 * @return NULL on error, or the address of the symbol
 */
void *module_Lookup( module_handle_t handle, const char *psz_function )
{
#ifdef VLC_DYLD_FALLBACK
    void *(*p_dlsym)(void *, const char *) = dlsym;

    if( p_dlsym == NULL )
    {
        /* Unlike dlsym(), NSLookupSymbolInModule() is not given the C name
         * but the linker one, so the Mach-O underscore has to be prepended. */
        char psz_call[strlen( psz_function ) + 2];

        psz_call[0] = '_';
        memcpy( psz_call + 1, psz_function, sizeof( psz_call ) - 1 );

        NSSymbol sym = NSLookupSymbolInModule( (NSModule)handle, psz_call );
        return (sym != NULL) ? NSAddressOfSymbol( sym ) : NULL;
    }
#endif
    return dlsym( handle, psz_function );
}
