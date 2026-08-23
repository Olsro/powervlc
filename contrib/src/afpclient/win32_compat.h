#ifndef AFP_WIN32_COMPAT_H
#define AFP_WIN32_COMPAT_H

#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
# define WIN32_LEAN_AND_MEAN
#endif
#ifndef NOMINMAX
# define NOMINMAX
#endif
#include <winsock2.h>
#include <ws2tcpip.h>
#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <string.h>
#include <sys/types.h>

/* MinGW does not expose the BSD endian macros used by utils.h.  Leaving
 * these undefined makes `BYTE_ORDER == BIG_ENDIAN` evaluate as `0 == 0`,
 * silently disabling every 64-bit host/network conversion. */
#ifndef LITTLE_ENDIAN
# define LITTLE_ENDIAN 1234
#endif
#ifndef BIG_ENDIAN
# define BIG_ENDIAN 4321
#endif
#ifndef BYTE_ORDER
# define BYTE_ORDER LITTLE_ENDIAN
#endif

typedef unsigned int uid_t;
typedef unsigned int gid_t;
typedef uint64_t u_int64_t;

#ifndef O_SYNC
# define O_SYNC 0
#endif

static inline unsigned int afp_sleep(unsigned int seconds)
{
    Sleep(seconds * 1000);
    return 0;
}

#define sleep afp_sleep
#define bcmp(left, right, length) memcmp((left), (right), (length))
#define geteuid() ((uid_t)0)
#define getgid() ((gid_t)0)

static inline size_t afp_strlcpy(char *destination, const char *source,
                                 size_t size)
{
    size_t length = strlen(source);
    if (size != 0) {
        size_t copied = length < size - 1 ? length : size - 1;
        memcpy(destination, source, copied);
        destination[copied] = '\0';
    }
    return length;
}

#define strlcpy afp_strlcpy

#ifdef pascal
# undef pascal
#endif

struct statvfs {
    uint64_t f_bsize;
    uint64_t f_frsize;
    uint64_t f_blocks;
    uint64_t f_bfree;
    uint64_t f_bavail;
    uint64_t f_files;
    uint64_t f_ffree;
    uint64_t f_favail;
    uint64_t f_fsid;
    uint64_t f_flag;
    uint64_t f_namemax;
};

struct passwd {
    char *pw_name;
    uid_t pw_uid;
    gid_t pw_gid;
};

#ifndef LOG_ERR
# define LOG_ERR 3
# define LOG_WARNING 4
# define LOG_NOTICE 5
# define LOG_INFO 6
# define LOG_DEBUG 7
#endif

static inline int afp_wsa_errno(int error)
{
    switch (error) {
    case WSAEINTR: return EINTR;
    case WSAEBADF: return EBADF;
    case WSAEACCES: return EACCES;
    case WSAEINVAL: return EINVAL;
    case WSAEMFILE: return EMFILE;
    case WSAEWOULDBLOCK: return EAGAIN;
    case WSAEINPROGRESS: return EINPROGRESS;
    case WSAEALREADY: return EALREADY;
    case WSAENOTSOCK: return ENOTSOCK;
    case WSAEDESTADDRREQ: return EDESTADDRREQ;
    case WSAEMSGSIZE: return EMSGSIZE;
    case WSAEPROTOTYPE: return EPROTOTYPE;
    case WSAENOPROTOOPT: return ENOPROTOOPT;
    case WSAEPROTONOSUPPORT: return EPROTONOSUPPORT;
    case WSAESOCKTNOSUPPORT:
    case WSAEOPNOTSUPP: return EOPNOTSUPP;
    case WSAEAFNOSUPPORT: return EAFNOSUPPORT;
    case WSAEADDRINUSE: return EADDRINUSE;
    case WSAEADDRNOTAVAIL: return EADDRNOTAVAIL;
    case WSAENETDOWN: return ENETDOWN;
    case WSAENETUNREACH: return ENETUNREACH;
    case WSAENETRESET: return ENETRESET;
    case WSAECONNABORTED: return ECONNABORTED;
    case WSAECONNRESET: return ECONNRESET;
    case WSAENOBUFS: return ENOBUFS;
    case WSAEISCONN: return EISCONN;
    case WSAENOTCONN: return ENOTCONN;
    case WSAETIMEDOUT: return ETIMEDOUT;
    case WSAECONNREFUSED: return ECONNREFUSED;
    case WSAEHOSTUNREACH: return EHOSTUNREACH;
    default: return EIO;
    }
}

static inline void afp_set_wsa_errno(void)
{
    errno = afp_wsa_errno(WSAGetLastError());
}

static inline int afp_socket_startup(void)
{
    WSADATA data;
    int result = WSAStartup(MAKEWORD(2, 2), &data);
    if (result != 0)
        errno = afp_wsa_errno(result);
    return result == 0 ? 0 : -1;
}

static inline int afp_socket_read(int fd, void *buffer, size_t length)
{
    int result = recv((SOCKET)fd, (char *)buffer,
                      length > INT_MAX ? INT_MAX : (int)length, 0);
    if (result == SOCKET_ERROR)
        afp_set_wsa_errno();
    return result == SOCKET_ERROR ? -1 : result;
}

static inline int afp_socket_write(int fd, const void *buffer, size_t length)
{
    int result = send((SOCKET)fd, (const char *)buffer,
                      length > INT_MAX ? INT_MAX : (int)length, 0);
    if (result == SOCKET_ERROR)
        afp_set_wsa_errno();
    return result == SOCKET_ERROR ? -1 : result;
}

static inline int afp_socket_close(int fd)
{
    int result = closesocket((SOCKET)fd);
    if (result == SOCKET_ERROR)
        afp_set_wsa_errno();
    return result == SOCKET_ERROR ? -1 : result;
}

static inline const char *afp_inet_ntop(int family, const void *address,
                                        char *buffer, size_t length)
{
    struct sockaddr_storage storage;
    DWORD buffer_length = length > MAXDWORD ? MAXDWORD : (DWORD)length;
    DWORD sockaddr_length;
    memset(&storage, 0, sizeof(storage));
    if (family == AF_INET) {
        struct sockaddr_in *addr = (struct sockaddr_in *)&storage;
        addr->sin_family = AF_INET;
        memcpy(&addr->sin_addr, address, sizeof(addr->sin_addr));
        sockaddr_length = sizeof(*addr);
    } else if (family == AF_INET6) {
        struct sockaddr_in6 *addr = (struct sockaddr_in6 *)&storage;
        addr->sin6_family = AF_INET6;
        memcpy(&addr->sin6_addr, address, sizeof(addr->sin6_addr));
        sockaddr_length = sizeof(*addr);
    } else {
        errno = EAFNOSUPPORT;
        return NULL;
    }
    if (WSAAddressToStringA((struct sockaddr *)&storage, sockaddr_length,
                            NULL, buffer, &buffer_length) != 0) {
        afp_set_wsa_errno();
        return NULL;
    }
    return buffer;
}

static inline int afp_gettimeofday(struct timeval *tv, void *timezone)
{
    FILETIME filetime;
    ULARGE_INTEGER ticks;
    (void)timezone;
    GetSystemTimeAsFileTime(&filetime);
    ticks.LowPart = filetime.dwLowDateTime;
    ticks.HighPart = filetime.dwHighDateTime;
    ticks.QuadPart -= UINT64_C(116444736000000000);
    tv->tv_sec = (long)(ticks.QuadPart / UINT64_C(10000000));
    tv->tv_usec = (long)((ticks.QuadPart % UINT64_C(10000000)) / 10);
    return 0;
}

#define inet_ntop afp_inet_ntop
#define gettimeofday afp_gettimeofday

#endif
#endif
