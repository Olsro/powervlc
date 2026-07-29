/*****************************************************************************
 * dlcompat.c: dlopen() and friends for Mac OS X 10.2
 *****************************************************************************
 * The dynamic loader compatibility functions (dlopen/dlsym/dlclose/dlerror)
 * only arrived with Mac OS X 10.3. Verified on a 10.2.1 install: none of them
 * is exported by its libSystem. Before 10.3 the way to load a bundle was the
 * dyld "library functions", which is what this file wraps -- the same thing
 * the historical dlcompat library did, and the same calls VLC itself carried
 * in src/modules/os.c until 2009 (commit 27953d60c9).
 *
 * <dlfcn.h> declares dlopen() without any availability annotation, so a build
 * targeting 10.2 emits a HARD reference to it: nothing is weak-imported and
 * check-weak-symbols.sh cannot see the problem. Measured on the 10.2 bundle:
 * 329 of its 332 Mach-O files reference _dlopen and _dlsym, which is why this
 * one file unblocks nearly everything.
 *
 * Only compiled into the slices whose deployment target is below 10.3.
 *****************************************************************************/

#include <mach-o/dyld.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach/machine.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/types.h>

#define RTLD_LAZY   0x1
#define RTLD_NOW    0x2
#define RTLD_LOCAL  0x4
#define RTLD_GLOBAL 0x8

static pthread_mutex_t dl_lock = PTHREAD_MUTEX_INITIALIZER;
static char dl_last_error[512];

static void dl_set_error(const char *msg)
{
    pthread_mutex_lock(&dl_lock);
    if (msg == NULL)
        dl_last_error[0] = '\0';
    else
    {
        strncpy(dl_last_error, msg, sizeof (dl_last_error) - 1);
        dl_last_error[sizeof (dl_last_error) - 1] = '\0';
    }
    pthread_mutex_unlock(&dl_lock);
}

char *dlerror(void)
{
    static char returned[512];

    pthread_mutex_lock(&dl_lock);
    if (dl_last_error[0] == '\0')
    {
        pthread_mutex_unlock(&dl_lock);
        return NULL;
    }
    strcpy(returned, dl_last_error);
    dl_last_error[0] = '\0';
    pthread_mutex_unlock(&dl_lock);
    return returned;
}

/* NSCreateObjectFileImageFromFile() CRASHES the whole process on a thin 64-bit
 * Mach-O: measured on 10.3.9, a thin arm64 file (cputype 0x0100000c) kills it
 * with EXC_BAD_ACCESS inside NSCreateImageFromFileOrMemory(), before it ever
 * gets a chance to return a code. A thin x86_64 file and every fat file --
 * including one whose slices are all 64-bit, and one holding only ppc7400/
 * ppc7450/ppc970 -- come back cleanly with NSObjectFileImageArch instead.
 *
 * This matters for the universal package and not for the per-arch ones: lipo
 * leaves a plugin that exists on a single architecture as a THIN file of that
 * architecture, and 7 of them (libaom, libvpx, libx265, libaudiotoolboxmidi,
 * libcaopengllayer, the two chromecast ones) are arm64-only. The 10.2/10.3
 * slices walk the same plugins directory as every other slice, so the first
 * one of those killed the process at launch, with no log line at all.
 *
 * Whitelist rather than blacklist: what we refuse only costs a warning, what
 * we let through wrongly costs the process. Accept a fat archive (dyld picks
 * the slice itself, and reports its failure properly) and a thin big-endian
 * 32-bit PowerPC image; refuse everything else. */
static int dl_image_is_loadable(const char *path)
{
    uint32_t head[4];
    int fd = open(path, O_RDONLY);
    ssize_t got;

    if (fd < 0)
        return 1;   /* let dyld report the real errno */

    got = read(fd, head, sizeof (head));
    close(fd);

    if (got < (ssize_t)sizeof (head))
        return 1;   /* too short to be a Mach-O; dyld will say so */

    /* We are big-endian here, so these load in file order. */
    if (head[0] == FAT_MAGIC || head[0] == FAT_CIGAM)
        return 1;

    if (head[0] == MH_MAGIC)
        return head[1] == CPU_TYPE_POWERPC;

    return 0;
}

void *dlopen(const char *path, int mode)
{
    NSObjectFileImage image;
    NSObjectFileImageReturnCode ret;

    dl_set_error(NULL);

    /* dlopen(NULL) means "the main program": nothing to link, and
     * NSLookupSymbolInModule() is not the right lookup for it either --
     * dlsym() below handles a NULL handle through the global symbol table. */
    if (path == NULL)
        return (void *)-1;

    if (!dl_image_is_loadable(path))
    {
        dl_set_error("not a PowerPC Mach-O image");
        return NULL;
    }

    ret = NSCreateObjectFileImageFromFile(path, &image);
    if (ret != NSObjectFileImageSuccess)
    {
        /* A dylib is not a bundle: it cannot be NSLinkModule()d, but it can
         * be added to the program with NSAddImage(). */
        if (ret == NSObjectFileImageInappropriateFile)
        {
            const struct mach_header *mh =
                NSAddImage(path, NSADDIMAGE_OPTION_RETURN_ON_ERROR);

            if (mh != NULL)
                return (void *)mh;
        }
        dl_set_error("cannot create object file image");
        return NULL;
    }

    unsigned long options = NSLINKMODULE_OPTION_RETURN_ON_ERROR;

    /* PRIVATE is RTLD_LOCAL, BINDNOW is RTLD_NOW. Binding now matters: it is
     * what makes a module referencing a missing symbol fail HERE, cleanly,
     * instead of jumping to a null pointer on first use. */
    if (!(mode & RTLD_GLOBAL))
        options |= NSLINKMODULE_OPTION_PRIVATE;
    if (mode & RTLD_NOW)
        options |= NSLINKMODULE_OPTION_BINDNOW;

    NSModule module = NSLinkModule(image, path, options);

    NSDestroyObjectFileImage(image);

    if (module == NULL)
    {
        NSLinkEditErrors errors;
        const char *file, *err;
        int errnum;

        NSLinkEditError(&errors, &errnum, &file, &err);
        dl_set_error(err != NULL ? err : "cannot link module");
        return NULL;
    }
    return module;
}

int dlclose(void *handle)
{
    dl_set_error(NULL);

    if (handle == NULL || handle == (void *)-1)
        return 0;

    /* An image added with NSAddImage() cannot be removed; report success
     * rather than an error, as unloading is best-effort anyway. */
    if (!NSUnLinkModule((NSModule)handle, NSUNLINKMODULE_OPTION_NONE))
        return 0;
    return 0;
}

void *dlsym(void *handle, const char *symbol)
{
    /* NSLookupSymbolInModule() takes the linker name, not the C one: unlike
     * dlsym() it does not prepend the Mach-O underscore. */
    size_t len = strlen(symbol);
    char *name = malloc(len + 2);
    NSSymbol sym = NULL;

    dl_set_error(NULL);

    if (name == NULL)
    {
        dl_set_error("out of memory");
        return NULL;
    }
    name[0] = '_';
    memcpy(name + 1, symbol, len + 1);

    if (handle == NULL || handle == (void *)-1)
    {
        /* Whole-program lookup. */
        if (NSIsSymbolNameDefined(name))
            sym = NSLookupAndBindSymbol(name);
    }
    else
    {
        sym = NSLookupSymbolInModule((NSModule)handle, name);

        /* NSLookupSymbolInModule() searches THAT image and nothing else,
         * where dlsym() also searches the sub-frameworks an umbrella
         * re-exports. Asking ApplicationServices for CGSAddSurface -- which
         * really lives in its CoreGraphics sub-framework -- therefore came
         * back empty, and with it the whole ATI hardware decoder path, which
         * resolves the private CGS entry points exactly that way.
         * The image is loaded by now, so its symbols are in the global table:
         * fall back to it. Less strict than dlsym() about WHICH library
         * answers, which costs nothing here -- these are system frameworks
         * with unique symbol names. */
        if (sym == NULL && NSIsSymbolNameDefined(name))
            sym = NSLookupAndBindSymbol(name);
    }

    free(name);

    if (sym == NULL)
    {
        dl_set_error("symbol not found");
        return NULL;
    }
    return NSAddressOfSymbol(sym);
}

/* libbluray uses dladdr() to locate itself. There is no faithful pre-10.3
 * equivalent, and every caller in this tree treats a zero return as "unknown",
 * so report failure rather than invent an answer. */
int dladdr(const void *addr, void *info)
{
    (void) addr; (void) info;
    dl_set_error("dladdr is not available before Mac OS X 10.3");
    return 0;
}
