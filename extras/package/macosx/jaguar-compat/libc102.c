/*****************************************************************************
 * libc102.c: the libc that Mac OS X 10.2 does not have
 *****************************************************************************
 * Established by inventory, not by guesswork: /usr/lib/libSystem.B.dylib was
 * copied off a real 10.2.1 install and its exported symbols compared with
 * everything the bundle references. What follows is that difference, minus
 * poll() -- which VLC's own compat/ replaces cleanly -- and minus
 * kqueue()/kevent(), a kernel facility that cannot be emulated in userland
 * and which only the SRT plugins want: those two fail their load and nothing
 * else notices.
 *
 * Everything else is implemented HERE rather than through VLC's compat/,
 * even where AC_REPLACE_FUNCS offers a replacement: ac_cv_func_<fn>=no tells
 * configure the function is not DECLARED, and the 10.4u SDK declares all of
 * them -- only the runtime symbol is missing. Switching those on makes
 * compat/lldiv.c collide with <stdlib.h>'s lldiv_t, vlc_fixups.h with
 * <stdio.h>'s getc_unlocked, and its locale_t with <xlocale.h>. Implementing
 * the SDK's own declarations contradicts nothing -- and covers the contribs
 * too, which VLC's compat/ never reaches.
 *
 * Three groups:
 *  1. C99 float math. 10.2 has sin() but not sinf(): the float variants came
 *     with 10.3 (in libmx, which does not exist on 10.2 either -- /usr/lib
 *     only has libm.dylib -> libSystem.dylib). ffmpeg needs these.
 *  2. Symbol-variant aliases. The 10.4u SDK rewrites some calls to
 *     _<fn>$LDBL128 (128-bit long double, 10.4+) or _<fn>$UNIX2003 (UNIX03
 *     conformance, 10.5+). Objects that carry them include the toolchain's own
 *     libgcc.a, which was built for 10.4. On PowerPC before 10.4 long double
 *     IS double and the UNIX03 variants only differ in error-reporting corner
 *     cases, so forwarding to the plain function is exact for our uses.
 *  3. Odds and ends: tsearch, stpcpy, nl_langinfo, the stdio handles
 *     (__stdoutp), xlocale and the whole wide-character family -- UTF-8, not
 *     the single-byte C locale, since that is what every caller feeds it.
 *
 * Only compiled into the slices whose deployment target is below 10.3.
 *****************************************************************************/

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <complex.h>
#include <errno.h>
#include <langinfo.h>
#include <xlocale.h>
#include <search.h>
#include <inttypes.h>
#include <wchar.h>
#include <wctype.h>
#include <ctype.h>
#include <time.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <pthread.h>

/*===========================================================================
 * 1. C99 float math
 *=========================================================================*/

#define WRAP1F(name) \
    float name##f(float x) { return (float) name((double) x); }

WRAP1F(sin)
WRAP1F(cos)
WRAP1F(tan)
WRAP1F(atan)
WRAP1F(acos)
WRAP1F(exp)
WRAP1F(log)
WRAP1F(log10)
WRAP1F(sqrt)
WRAP1F(cbrt)

float atan2f(float y, float x) { return (float) atan2((double) y, (double) x); }
float powf(float x, float y)   { return (float) pow((double) x, (double) y); }
float hypotf(float x, float y) { return (float) hypot((double) x, (double) y); }

/* exp2/log2 are missing in their double form too. */
double exp2(double x) { return exp(x * M_LN2); }
double log2(double x) { return log(x) / M_LN2; }
float  exp2f(float x) { return (float) exp2((double) x); }
float  log2f(float x) { return (float) log2((double) x); }

/* The obvious spelling of this -- exp(a)*cos(b) + exp(a)*sin(b)*I -- is
 * exactly the shape GCC's cse_sincos pass rewrites INTO a call to cexp(), so
 * the definition ends up calling itself. It is not a builtin substitution:
 * -fno-builtin does not stop it (verified in the disassembly, `bl _cexp`
 * inside _cexp). Measured on the 10.2 machine as a runaway recursion that
 * killed MPEG-1 decoding. The volatile temporaries break the pattern, and the
 * parts are taken with __real__/__imag__ rather than creal()/cimag(), which
 * 10.2 does not have either -- that would trade one missing symbol for two. */
double complex cexp(double complex z)
{
    volatile double re = __real__ z;
    volatile double im = __imag__ z;
    volatile double r = exp(re);
    double complex out;

    __real__ out = r * cos(im);
    __imag__ out = r * sin(im);
    return out;
}

float complex cexpf(float complex z)
{
    volatile float re = __real__ z;
    volatile float im = __imag__ z;
    volatile float r = (float) exp((double) re);
    float complex out;

    __real__ out = r * (float) cos((double) im);
    __imag__ out = r * (float) sin((double) im);
    return out;
}

/*===========================================================================
 * 2. Symbol-variant aliases
 *=========================================================================*/

/* $LDBL128 -- the 128-bit long double flavour. On PowerPC below 10.4,
 * long double is double, so the plain function is the right implementation. */
int  vlc_fprintf_ldbl128(FILE *, const char *, ...) __asm("_fprintf$LDBL128");
int  vlc_sprintf_ldbl128(char *, const char *, ...) __asm("_sprintf$LDBL128");
int  vlc_vsnprintf_ldbl128(char *, size_t, const char *, va_list)
                                                  __asm("_vsnprintf$LDBL128");
long double vlc_strtold_ldbl128(const char *, char **)
                                                    __asm("_strtold$LDBL128");

int vlc_fprintf_ldbl128(FILE *f, const char *fmt, ...)
{
    va_list ap;
    int ret;

    va_start(ap, fmt);
    ret = vfprintf(f, fmt, ap);
    va_end(ap);
    return ret;
}

int vlc_sprintf_ldbl128(char *s, const char *fmt, ...)
{
    va_list ap;
    int ret;

    va_start(ap, fmt);
    ret = vsprintf(s, fmt, ap);
    va_end(ap);
    return ret;
}

int vlc_vsnprintf_ldbl128(char *s, size_t n, const char *fmt, va_list ap)
{
    return vsnprintf(s, n, fmt, ap);
}

long double vlc_strtold_ldbl128(const char *s, char **end)
{
    return strtod(s, end);
}

/* $UNIX2003 -- the UNIX03-conformant flavours, introduced in 10.5. They differ
 * from the plain ones only in a few error and cancellation corner cases. */
#define ALIAS_UNIX2003(ret, name, params, args) \
    ret vlc_##name##_u2003 params __asm("_" #name "$UNIX2003"); \
    ret vlc_##name##_u2003 params { return name args; }

ALIAS_UNIX2003(int, accept, (int a, struct sockaddr *b, socklen_t *c), (a, b, c))
ALIAS_UNIX2003(int, bind, (int a, const struct sockaddr *b, socklen_t c), (a, b, c))
ALIAS_UNIX2003(int, connect, (int a, const struct sockaddr *b, socklen_t c), (a, b, c))
ALIAS_UNIX2003(int, listen, (int a, int b), (a, b))
ALIAS_UNIX2003(ssize_t, recv, (int a, void *b, size_t c, int d), (a, b, c, d))
ALIAS_UNIX2003(ssize_t, send, (int a, const void *b, size_t c, int d), (a, b, c, d))
ALIAS_UNIX2003(size_t, fwrite, (const void *a, size_t b, size_t c, FILE *d), (a, b, c, d))
ALIAS_UNIX2003(int, nanosleep, (const struct timespec *a, struct timespec *b), (a, b))
ALIAS_UNIX2003(int, pthread_cond_wait, (pthread_cond_t *a, pthread_mutex_t *b), (a, b))
ALIAS_UNIX2003(int, pthread_cond_timedwait, (pthread_cond_t *a, pthread_mutex_t *b, const struct timespec *c), (a, b, c))
ALIAS_UNIX2003(int, pthread_join, (pthread_t a, void **b), (a, b))
ALIAS_UNIX2003(int, pthread_setcancelstate, (int a, int *b), (a, b))

/*===========================================================================
 * 3. Odds and ends
 *=========================================================================*/

/* These could in theory come from VLC's own compat/ (they are all in
 * AC_REPLACE_FUNCS), but switching those on means telling configure the
 * function is not DECLARED -- and the 10.4u SDK declares every one of them.
 * compat/lldiv.c then collides with <stdlib.h>'s lldiv_t and vlc_fixups.h
 * with <stdio.h>'s getc_unlocked. Implementing the SDK's declarations here
 * contradicts nothing, and covers the contribs at the same time. */

long long atoll(const char *s)
{
    return strtoll(s, NULL, 10);
}

lldiv_t lldiv(long long num, long long denom)
{
    lldiv_t r;

    r.quot = num / denom;
    r.rem  = num % denom;
    return r;
}

float strtof(const char *s, char **end)
{
    return (float) strtod(s, end);
}

char *strcasestr(const char *haystack, const char *needle)
{
    size_t n = strlen(needle);

    if (n == 0)
        return (char *) haystack;

    for (; *haystack != '\0'; haystack++)
        if (strncasecmp(haystack, needle, n) == 0)
            return (char *) haystack;
    return NULL;
}

char *strnstr(const char *haystack, const char *needle, size_t len)
{
    size_t n = strlen(needle);

    if (n == 0)
        return (char *) haystack;

    for (; len >= n && *haystack != '\0'; haystack++, len--)
        if (strncmp(haystack, needle, n) == 0)
            return (char *) haystack;
    return NULL;
}

/* stdio on 10.2 has no per-FILE locking to take: these are the no-ops that
 * matched the platform's own behaviour before 10.3 introduced them. */
void flockfile(FILE *f) { (void) f; }

char *stpcpy(char *dst, const char *src)
{
    size_t len = strlen(src);

    memcpy(dst, src, len + 1);
    return dst + len;
}

uintmax_t strtoumax(const char *s, char **end, int base)
{
    return strtoull(s, end, base);
}

int strerror_r(int code, char *buf, size_t len)
{
    const char *msg = strerror(code);

    if (strlen(msg) >= len)
    {
        if (len > 0)
        {
            memcpy(buf, msg, len - 1);
            buf[len - 1] = '\0';
        }
        return ERANGE;
    }
    strcpy(buf, msg);
    return 0;
}

void funlockfile(FILE *f) { (void) f; }

/* Everything this tree asks nl_langinfo() is the charset name, and the whole
 * build runs UTF-8 (VLC forces it through vlc_charset). */
char *nl_langinfo(nl_item item)
{
    static char utf8[] = "UTF-8";
    static char empty[] = "";

    return (item == CODESET) ? utf8 : empty;
}

/* No wide-character support to speak of on 10.2; VLC only uses wcwidth() to
 * lay out console output. One column per character is the right answer for
 * everything the terminal on these machines can display anyway. */
int wcwidth(wchar_t wc)
{
    if (wc == 0)
        return 0;
    if (wc < 32 || (wc >= 0x7f && wc < 0xa0))
        return -1;
    return 1;
}

int32_t OSAtomicAdd32Barrier(int32_t amount, volatile int32_t *value)
{
    return __sync_add_and_fetch(value, amount);
}

/*---------------------------------------------------------------------------
 * stdio globals. 10.2 spells stdout "&__sF[1]"; 10.4 renamed the handles to
 * __stdoutp/__stderrp. Indexing __sF ourselves is not an option: the 10.4
 * FILE grew an "_extra" field (its own comment says so), so sizeof(FILE)
 * differs and __sF[1] would land at the wrong offset on the running system.
 * fdopen() asks the platform's own stdio for a handle instead, which cannot
 * be wrong. The cost is a second buffer on the same descriptor -- harmless
 * here, where the only users are avcodec's and libbluray's log output.
 *-------------------------------------------------------------------------*/

FILE *__stdoutp;
FILE *__stderrp;

static void __attribute__((constructor)) jaguar_stdio_init(void)
{
    __stdoutp = fdopen(1, "w");
    __stderrp = fdopen(2, "w");
    if (__stderrp != NULL)
        setvbuf(__stderrp, NULL, _IONBF, 0);   /* stderr is unbuffered */
}

/*---------------------------------------------------------------------------
 * Wide characters. 10.2 has essentially none of <wchar.h>. VLC is UTF-8
 * throughout, and so is every contrib that reaches these functions, so
 * mbrtowc()/wcrtomb() implement UTF-8 rather than the single-byte C locale:
 * the C-locale answer would mangle every non-ASCII tag, filename and
 * subtitle, which is exactly what these callers handle.
 *-------------------------------------------------------------------------*/

size_t mbrtowc(wchar_t *pwc, const char *s, size_t n, mbstate_t *ps)
{
    (void) ps;

    if (s == NULL)
        return 0;
    if (n == 0)
        return (size_t) -2;

    unsigned char c = (unsigned char) s[0];
    int extra;
    wchar_t wc;

    if (c < 0x80)      { wc = c;        extra = 0; }
    else if (c < 0xC2) { errno = EILSEQ; return (size_t) -1; }
    else if (c < 0xE0) { wc = c & 0x1F; extra = 1; }
    else if (c < 0xF0) { wc = c & 0x0F; extra = 2; }
    else if (c < 0xF5) { wc = c & 0x07; extra = 3; }
    else               { errno = EILSEQ; return (size_t) -1; }

    if (n < (size_t) extra + 1)
        return (size_t) -2;

    for (int i = 1; i <= extra; i++)
    {
        unsigned char cc = (unsigned char) s[i];

        if ((cc & 0xC0) != 0x80)
        {
            errno = EILSEQ;
            return (size_t) -1;
        }
        wc = (wc << 6) | (cc & 0x3F);
    }

    if (pwc != NULL)
        *pwc = wc;
    return (wc == 0) ? 0 : (size_t) extra + 1;
}

size_t wcrtomb(char *s, wchar_t wc, mbstate_t *ps)
{
    (void) ps;

    if (s == NULL)
        return 1;

    if (wc < 0x80)
    {
        s[0] = (char) wc;
        return 1;
    }
    if (wc < 0x800)
    {
        s[0] = (char) (0xC0 | (wc >> 6));
        s[1] = (char) (0x80 | (wc & 0x3F));
        return 2;
    }
    if (wc < 0x10000)
    {
        s[0] = (char) (0xE0 | (wc >> 12));
        s[1] = (char) (0x80 | ((wc >> 6) & 0x3F));
        s[2] = (char) (0x80 | (wc & 0x3F));
        return 3;
    }
    if (wc < 0x110000)
    {
        s[0] = (char) (0xF0 | (wc >> 18));
        s[1] = (char) (0x80 | ((wc >> 12) & 0x3F));
        s[2] = (char) (0x80 | ((wc >> 6) & 0x3F));
        s[3] = (char) (0x80 | (wc & 0x3F));
        return 4;
    }
    errno = EILSEQ;
    return (size_t) -1;
}

wint_t btowc(int c)
{
    return (c == EOF || (unsigned char) c >= 0x80) ? WEOF : (wint_t) c;
}

int wctob(wint_t wc)
{
    return (wc < 0x80) ? (int) wc : EOF;
}

/* ⚠ The 10.4 SDK declares these as functions and then hides them behind
 * `#define towlower(wc) __tolower(wc)`. Defining them without undoing the
 * macro first compiled the bodies below under the names __tolower and
 * __toupper: the archive exported those, `towlower' and `towupper' were
 * nowhere, and every C++ plugin that reaches libstdc++'s locale code --
 * adaptive (so every HLS and DASH stream), mkv, dcp, sid, spatialaudio,
 * taglib -- was refused by dyld on 10.2 with nothing but a warning in the
 * log. Keep both names: callers compiled against the SDK ask for the
 * mangled one. */
#undef towlower
#undef towupper

wint_t towlower(wint_t wc)
{
    return (wc < 0x80) ? (wint_t) tolower((int) wc) : wc;
}

wint_t towupper(wint_t wc)
{
    return (wc < 0x80) ? (wint_t) toupper((int) wc) : wc;
}

wint_t __tolower(wint_t wc)
{
    return towlower(wc);
}

wint_t __toupper(wint_t wc)
{
    return towupper(wc);
}

/* 10.3 and later keep the program name for err(3) and for libraries that
 * name themselves in their messages (libass does). */
const char *getprogname(void)
{
    extern char **_NSGetProgname(void);
    char **name = _NSGetProgname();

    return (name != NULL && *name != NULL) ? *name : "PowerVLC";
}

size_t wcslen(const wchar_t *s)
{
    const wchar_t *p = s;

    while (*p != L'\0')
        p++;
    return (size_t) (p - s);
}

wchar_t *wcschr(const wchar_t *s, wchar_t c)
{
    for (; *s != L'\0'; s++)
        if (*s == c)
            return (wchar_t *) s;
    return (c == L'\0') ? (wchar_t *) s : NULL;
}

wchar_t *wcscpy(wchar_t *dst, const wchar_t *src)
{
    wchar_t *d = dst;

    while ((*d++ = *src++) != L'\0')
        ;
    return dst;
}

/* No wide collation without locales: code-point order is the only sane
 * answer, and it is what the C locale prescribes anyway. */
int wcscoll(const wchar_t *a, const wchar_t *b)
{
    for (; *a != L'\0' && *a == *b; a++, b++)
        ;
    return (int) (*a - *b);
}

size_t wcsxfrm(wchar_t *dst, const wchar_t *src, size_t n)
{
    size_t len = wcslen(src);

    if (n > 0)
    {
        size_t copy = (len < n - 1) ? len : n - 1;

        wmemcpy(dst, src, copy);
        dst[copy] = L'\0';
    }
    return len;
}

long wcstol(const wchar_t *s, wchar_t **end, int base)
{
    char buf[64];
    char *cend;
    size_t i = 0;

    while (i < sizeof (buf) - 1 && s[i] != L'\0' && s[i] < 0x80)
    {
        buf[i] = (char) s[i];
        i++;
    }
    buf[i] = '\0';

    long v = strtol(buf, &cend, base);

    if (end != NULL)
        *end = (wchar_t *) s + (cend - buf);
    return v;
}

int wcswidth(const wchar_t *s, size_t n)
{
    int width = 0;

    for (; n > 0 && *s != L'\0'; s++, n--)
    {
        int w = wcwidth(*s);

        if (w < 0)
            return -1;
        width += w;
    }
    return width;
}

size_t wcsftime(wchar_t *dst, size_t n, const wchar_t *fmt,
                const struct tm *tm)
{
    char nfmt[256], out[1024];
    size_t i = 0;

    while (i < sizeof (nfmt) - 1 && fmt[i] != L'\0')
    {
        nfmt[i] = (char) fmt[i];
        i++;
    }
    nfmt[i] = '\0';

    size_t len = strftime(out, sizeof (out), nfmt, tm);

    if (len == 0 || len >= n)
        return 0;
    for (i = 0; i < len; i++)
        dst[i] = (unsigned char) out[i];
    dst[len] = L'\0';
    return len;
}

wchar_t *wmemchr(const wchar_t *s, wchar_t c, size_t n)
{
    for (; n > 0; s++, n--)
        if (*s == c)
            return (wchar_t *) s;
    return NULL;
}

int wmemcmp(const wchar_t *a, const wchar_t *b, size_t n)
{
    for (; n > 0; a++, b++, n--)
        if (*a != *b)
            return (*a < *b) ? -1 : 1;
    return 0;
}

wchar_t *wmemcpy(wchar_t *dst, const wchar_t *src, size_t n)
{
    return memcpy(dst, src, n * sizeof (wchar_t));
}

wchar_t *wmemmove(wchar_t *dst, const wchar_t *src, size_t n)
{
    return memmove(dst, src, n * sizeof (wchar_t));
}

wchar_t *wmemset(wchar_t *s, wchar_t c, size_t n)
{
    wchar_t *p = s;

    while (n-- > 0)
        *p++ = c;
    return s;
}

wint_t getwc(FILE *f)
{
    int c = fgetc(f);

    return (c == EOF) ? WEOF : (wint_t) c;
}

wint_t putwc(wchar_t wc, FILE *f)
{
    char buf[4];
    size_t len = wcrtomb(buf, wc, NULL);

    if (len == (size_t) -1 || fwrite(buf, 1, len, f) != len)
        return WEOF;
    return (wint_t) wc;
}

wint_t ungetwc(wint_t wc, FILE *f)
{
    if (wc == WEOF || wc >= 0x80)
        return WEOF;
    return (ungetc((int) wc, f) == EOF) ? WEOF : wc;
}

/*---------------------------------------------------------------------------
 * xlocale. VLC uses it for one thing: run a stretch of code in the C locale
 * so that number parsing does not follow the user's decimal separator. On
 * 10.2 there is no per-thread locale machinery at all -- and no way to leave
 * the C locale either, since the platform predates setlocale() having any
 * effect on these paths. Handing out a single dummy locale is therefore not
 * an approximation: plain strtod() already behaves the way the callers want.
 *-------------------------------------------------------------------------*/

/* struct _xlocale is opaque in the SDK, and nothing here ever dereferences
 * the handle: any stable non-NULL address will do. */
static int c_locale_dummy_storage;
#define C_LOCALE_DUMMY ((locale_t) &c_locale_dummy_storage)

locale_t newlocale(int mask, const char *locale, locale_t base)
{
    (void) mask; (void) locale; (void) base;
    return C_LOCALE_DUMMY;
}

locale_t uselocale(locale_t loc)
{
    (void) loc;
    /* There is never a thread-specific locale here. Answering the dummy
     * handle instead makes gettext's thread-locale probe (uselocale(NULL)
     * then querylocale()) believe the thread is pinned to "C", which turns
     * every translation off. */
    return LC_GLOBAL_LOCALE;
}

int freelocale(locale_t loc)
{
    (void) loc;
    return 0;
}

const char *querylocale(int mask, locale_t loc)
{
    (void) mask; (void) loc;
    return "C";
}

int ___mb_cur_max_l(locale_t loc)
{
    (void) loc;
    return 1;   /* the C locale is single-byte */
}

/*---------------------------------------------------------------------------
 * tsearch(3) -- an unbalanced binary search tree, which is all the interface
 * promises.
 *-------------------------------------------------------------------------*/

/* The node's first member IS the key, because that is the whole interface:
 * tsearch()/tfind() hand back a pointer to the node and the caller reads the
 * key by dereferencing it as void **. Returning the link that points AT the
 * node instead -- one level of indirection too many -- compiles and runs, and
 * every lookup silently fails: VLC then reports "cannot add callback to
 * nonexistent variable" for every variable it creates. */
typedef struct tnode
{
    const void   *key;
    struct tnode *left, *right;
} tnode_t;

void *tsearch(const void *key, void **rootp,
              int (*compar)(const void *, const void *))
{
    tnode_t **n = (tnode_t **) rootp;

    if (rootp == NULL)
        return NULL;

    while (*n != NULL)
    {
        int cmp = compar(key, (*n)->key);

        if (cmp == 0)
            return *n;
        n = (cmp < 0) ? &(*n)->left : &(*n)->right;
    }

    *n = malloc(sizeof (**n));
    if (*n == NULL)
        return NULL;
    (*n)->key = key;
    (*n)->left = (*n)->right = NULL;
    return *n;
}

void *tfind(const void *key, void *const *rootp,
            int (*compar)(const void *, const void *))
{
    tnode_t *const *n = (tnode_t *const *) rootp;

    if (rootp == NULL)
        return NULL;

    while (*n != NULL)
    {
        int cmp = compar(key, (*n)->key);

        if (cmp == 0)
            return (void *) *n;
        n = (cmp < 0) ? &(*n)->left : &(*n)->right;
    }
    return NULL;
}

/* Returns the parent of the deleted node, or NULL when the key was not there.
 * Deleting the root leaves no parent to name, so hand back the root link --
 * non-NULL, which is all any caller checks. */
void *tdelete(const void *key, void **rootp,
              int (*compar)(const void *, const void *))
{
    tnode_t **n = (tnode_t **) rootp;
    tnode_t *parent = NULL;

    if (rootp == NULL)
        return NULL;

    while (*n != NULL)
    {
        int cmp = compar(key, (*n)->key);

        if (cmp == 0)
            break;
        parent = *n;
        n = (cmp < 0) ? &(*n)->left : &(*n)->right;
    }
    if (*n == NULL)
        return NULL;

    tnode_t *dead = *n;

    if (dead->left != NULL && dead->right != NULL)
    {
        /* Two children: take the leftmost node of the right subtree, which
         * has no left child, and drop its key here instead. */
        tnode_t *succ_parent = dead;
        tnode_t **succ = &dead->right;

        while ((*succ)->left != NULL)
        {
            succ_parent = *succ;
            succ = &(*succ)->left;
        }

        tnode_t *moved = *succ;

        dead->key = moved->key;
        *succ = moved->right;
        free(moved);
        return succ_parent;
    }

    *n = (dead->left != NULL) ? dead->left : dead->right;
    free(dead);
    return (parent != NULL) ? (void *) parent : (void *) rootp;
}

static void twalk_rec(const tnode_t *n,
                      void (*action)(const void *, VISIT, int), int level)
{
    if (n == NULL)
        return;

    if (n->left == NULL && n->right == NULL)
        action(n, leaf, level);
    else
    {
        action(n, preorder, level);
        twalk_rec(n->left, action, level + 1);
        action(n, postorder, level);
        twalk_rec(n->right, action, level + 1);
        action(n, endorder, level);
    }
}

void twalk(const void *root, void (*action)(const void *, VISIT, int))
{
    if (root != NULL && action != NULL)
        twalk_rec(root, action, 0);
}
