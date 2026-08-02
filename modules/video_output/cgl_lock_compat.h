/*****************************************************************************
 * cgl_lock_compat.h: CGL context locking that also works on Mac OS X 10.3
 *****************************************************************************
 * CGLLockContext()/CGLUnlockContext() came with the multithreaded GL engine
 * in Mac OS X 10.4. When the deployment target is older the SDK weak-imports
 * them, so on a 10.3 system they resolve to NULL and calling them jumps to 0.
 *
 * The lock exists to serialise our own vout thread against the AppKit
 * -drawRect: path on the same context; a recursive mutex does exactly that.
 * It is process-wide rather than per-context, which only matters if two vouts
 * render at once -- they then take turns instead of running in parallel.
 * Machines that stop at 10.3 are single-GPU 233-400 MHz G3s, so that is free.
 *
 * On 10.4 and later nothing changes: the real CGL functions are used.
 *****************************************************************************/

#ifndef VLC_CGL_LOCK_COMPAT_H
#define VLC_CGL_LOCK_COMPAT_H

#include <OpenGL/OpenGL.h>
#include <pthread.h>

static pthread_mutex_t cgl_compat_lock;
static pthread_once_t  cgl_compat_once = PTHREAD_ONCE_INIT;

static void cgl_compat_init(void)
{
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&cgl_compat_lock, &attr);
    pthread_mutexattr_destroy(&attr);
}

static inline CGLError vlc_CGLLockContext(CGLContextObj ctx)
{
    /* Taken through a variable rather than compared directly: on the 10.4+
     * builds the symbol is not weak and GCC would warn that its address is
     * always true. */
    CGLError (*lock)(CGLContextObj) = CGLLockContext;

    if (lock != NULL)
        return lock(ctx);

    pthread_once(&cgl_compat_once, cgl_compat_init);
    pthread_mutex_lock(&cgl_compat_lock);
    return kCGLNoError;
}

static inline CGLError vlc_CGLUnlockContext(CGLContextObj ctx)
{
    CGLError (*unlock)(CGLContextObj) = CGLUnlockContext;

    if (unlock != NULL)
        return unlock(ctx);

    pthread_once(&cgl_compat_once, cgl_compat_init);
    pthread_mutex_unlock(&cgl_compat_lock);
    return kCGLNoError;
}

#ifdef __OBJC__
/* -[NSOpenGLContext CGLContextObj] is 10.3, and below it there is no accessor
 * at all: the only way to reach the CGL context is to make the NSOpenGLContext
 * current and ask CGL which one is. That is NOT usable here. It was tried, and
 * it deadlocked the video output on 10.2 every time: -makeCurrentContext gets
 * called from the video thread while the main thread is inside -reshape with
 * the same context current, outside of any lock -- the lock is what this
 * function is being called to obtain in the first place.
 *
 * NULL is the honest answer, and it costs nothing here:
 *  - vlc_CGLLockContext/Unlock below fall back to a mutex on anything under
 *    10.4 and never look at the pointer;
 *  - the only other users, the "macosx-glcontext" variable (Core Image
 *    filters, the CVPX converter) and CGLSetParameter for the swap interval,
 *    are 10.8+ code paths or cosmetic, and both already handle NULL.
 *
 * Only for translation units that already pull in Cocoa. */
static inline CGLContextObj vlc_CGLContextOf(NSOpenGLContext *context)
{
    if (context == nil)
        return NULL;

    if ([context respondsToSelector:@selector(CGLContextObj)])
        return (CGLContextObj)[context CGLContextObj];

    return NULL;
}
#endif /* __OBJC__ */

#endif /* VLC_CGL_LOCK_COMPAT_H */
