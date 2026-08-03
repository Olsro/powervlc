/*****************************************************************************
 * tls.c
 *****************************************************************************
 * Copyright © 2004-2016 Rémi Denis-Courmont
 * $Id$
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

/**
 * @file
 * Transport Layer Socket abstraction.
 *
 * This file implements the Transport Layer Socket (vlc_tls) abstraction.
 */

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#ifdef HAVE_POLL
# include <poll.h>
#endif
#include <assert.h>
#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifdef HAVE_SYS_UIO_H
# include <sys/uio.h>
#endif
#ifdef HAVE_NETINET_TCP_H
# include <netinet/tcp.h>
#endif
#ifndef SOL_TCP
# define SOL_TCP IPPROTO_TCP
#endif

#include <vlc_common.h>
#include "libvlc.h"

#include <vlc_tls.h>
#include <vlc_modules.h>
#include <vlc_interrupt.h>

/*** TLS credentials ***/

static int tls_server_load(void *func, va_list ap)
{
    int (*activate) (vlc_tls_creds_t *, const char *, const char *) = func;
    vlc_tls_creds_t *crd = va_arg (ap, vlc_tls_creds_t *);
    const char *cert = va_arg (ap, const char *);
    const char *key = va_arg (ap, const char *);

    return activate (crd, cert, key);
}

static int tls_client_load(void *func, va_list ap)
{
    int (*activate) (vlc_tls_creds_t *) = func;
    vlc_tls_creds_t *crd = va_arg (ap, vlc_tls_creds_t *);

    return activate (crd);
}

static void tls_unload(void *func, va_list ap)
{
    void (*deactivate) (vlc_tls_creds_t *) = func;
    vlc_tls_creds_t *crd = va_arg (ap, vlc_tls_creds_t *);

    deactivate (crd);
}

vlc_tls_creds_t *
vlc_tls_ServerCreate (vlc_object_t *obj, const char *cert_path,
                      const char *key_path)
{
    vlc_tls_creds_t *srv = vlc_custom_create (obj, sizeof (*srv),
                                              "tls server");
    if (unlikely(srv == NULL))
        return NULL;

    if (key_path == NULL)
        key_path = cert_path;

    srv->module = vlc_module_load (srv, "tls server", NULL, false,
                                   tls_server_load, srv, cert_path, key_path);
    if (srv->module == NULL)
    {
        msg_Err (srv, "TLS server plugin not available");
        vlc_object_release (srv);
        return NULL;
    }

    return srv;
}

vlc_tls_creds_t *vlc_tls_ClientCreate (vlc_object_t *obj)
{
    vlc_tls_creds_t *crd = vlc_custom_create (obj, sizeof (*crd),
                                              "tls client");
    if (unlikely(crd == NULL))
        return NULL;

    crd->module = vlc_module_load (crd, "tls client", NULL, false,
                                   tls_client_load, crd);
    if (crd->module == NULL)
    {
        msg_Err (crd, "TLS client plugin not available");
        vlc_object_release (crd);
        return NULL;
    }

    return crd;
}

void vlc_tls_Delete (vlc_tls_creds_t *crd)
{
    if (crd == NULL)
        return;

    vlc_module_unload(crd, crd->module, tls_unload, crd);
    vlc_object_release (crd);
}


/*** TLS  session ***/

static vlc_tls_t *vlc_tls_SessionCreate(vlc_tls_creds_t *crd,
                                        vlc_tls_t *sock,
                                        const char *host,
                                        const char *const *alpn)
{
    vlc_tls_t *session;
    int canc = vlc_savecancel();
    session = crd->open(crd, sock, host, alpn);
    vlc_restorecancel(canc);
    if (session != NULL)
        session->p = sock;
    return session;
}

void vlc_tls_SessionDelete (vlc_tls_t *session)
{
    int canc = vlc_savecancel();
    session->close(session);
    vlc_restorecancel(canc);
}

static void cleanup_tls(void *data)
{
    vlc_tls_t *session = data;

    vlc_tls_SessionDelete (session);
}

#undef vlc_tls_ClientSessionCreate
vlc_tls_t *vlc_tls_ClientSessionCreate(vlc_tls_creds_t *crd, vlc_tls_t *sock,
                                       const char *host, const char *service,
                                       const char *const *alpn, char **alp)
{
    int val;

    vlc_tls_t *session = vlc_tls_SessionCreate(crd, sock, host, alpn);
    if (session == NULL)
        return NULL;

    int canc = vlc_savecancel();
    vlc_tick_t deadline = mdate ();
    deadline += var_InheritInteger (crd, "ipv4-timeout") * 1000;

    struct pollfd ufd[1];
    ufd[0].fd = vlc_tls_GetFD(sock);

    vlc_cleanup_push (cleanup_tls, session);
    while ((val = crd->handshake(crd, session, host, service, alp)) != 0)
    {
        if (val < 0 || vlc_killed() )
        {
            if (val < 0)
                msg_Err(crd, "TLS session handshake error");
error:
            vlc_tls_SessionDelete (session);
            session = NULL;
            break;
        }

        vlc_tick_t now = mdate ();
        if (now > deadline)
           now = deadline;

        assert (val <= 2);
        ufd[0] .events = (val == 1) ? POLLIN : POLLOUT;

        vlc_restorecancel(canc);
        val = vlc_poll_i11e(ufd, 1, (deadline - now) / 1000);
        canc = vlc_savecancel();
        if (val == 0)
        {
            msg_Err(crd, "TLS session handshake timeout");
            goto error;
        }
    }
    vlc_cleanup_pop();
    vlc_restorecancel(canc);
    return session;
}

vlc_tls_t *vlc_tls_ServerSessionCreate(vlc_tls_creds_t *crd,
                                       vlc_tls_t *sock,
                                       const char *const *alpn)
{
    return vlc_tls_SessionCreate(crd, sock, NULL, alpn);
}

ssize_t vlc_tls_Read(vlc_tls_t *session, void *buf, size_t len, bool waitall)
{
    struct pollfd ufd;
    struct iovec iov;

    ufd.fd = vlc_tls_GetFD(session);
    ufd.events = POLLIN;
    iov.iov_base = buf;
    iov.iov_len = len;

    for (size_t rcvd = 0;;)
    {
        if (vlc_killed())
        {
            errno = EINTR;
            return -1;
        }

        ssize_t val = session->readv(session, &iov, 1);
        if (val > 0)
        {
            if (!waitall)
                return val;
            iov.iov_base = (char *)iov.iov_base + val;
            iov.iov_len -= val;
            rcvd += val;
        }
        if (iov.iov_len == 0 || val == 0)
            return rcvd;
        if (val == -1)
        {
            if (vlc_killed())
                return -1;
            if (errno != EINTR && errno != EAGAIN)
                return rcvd ? (ssize_t)rcvd : -1;
        }

        vlc_poll_i11e(&ufd, 1, -1);
    }
}

ssize_t vlc_tls_Write(vlc_tls_t *session, const void *buf, size_t len)
{
    struct pollfd ufd;
    struct iovec iov;

    ufd.fd = vlc_tls_GetFD(session);
    ufd.events = POLLOUT;
    iov.iov_base = (void *)buf;
    iov.iov_len = len;

    for (size_t sent = 0;;)
    {
        if (vlc_killed())
        {
            errno = EINTR;
            return -1;
        }

        ssize_t val = session->writev(session, &iov, 1);
        if (val > 0)
        {
            iov.iov_base = ((char *)iov.iov_base) + val;
            iov.iov_len -= val;
            sent += val;
        }
        if (iov.iov_len == 0 || val == 0)
            return sent;
        if (val == -1)
        {
            if (vlc_killed())
                return -1;
            if (errno != EINTR && errno != EAGAIN)
                return sent ? (ssize_t)sent : -1;
        }

        vlc_poll_i11e(&ufd, 1, -1);
    }
}

char *vlc_tls_GetLine(vlc_tls_t *session)
{
    char *line = NULL;
    size_t linelen = 0, linesize = 0;

    do
    {
        if (linelen == linesize)
        {
            linesize += 1024;

            char *newline = realloc(line, linesize);
            if (unlikely(newline == NULL))
                goto error;
            line = newline;
        }

        if (vlc_tls_Read(session, line + linelen, 1, false) <= 0)
            goto error;
    }
    while (line[linelen++] != '\n');

    if (linelen >= 2 && line[linelen - 2] == '\r')
        line[linelen - 2] = '\0';
    else
        line[linelen - 1] = '\0';
    return line;

error:
    free(line);
    return NULL;
}

typedef struct vlc_tls_socket
{
    struct vlc_tls tls;
    int fd;
    /* Bound on a deferred connect() wait, in microseconds (0 = none).
     * Set from "ipv4-timeout" by vlc_tls_SocketOpenTCP(): without it a
     * dead host only fails after the kernel TCP timeout (75 s on Darwin),
     * freezing whoever is waiting on the connection. */
    vlc_tick_t connect_timeout;
    socklen_t peerlen;
    struct sockaddr peer[];
} vlc_tls_socket_t;

static int vlc_tls_SocketGetFD(vlc_tls_t *tls)
{
    vlc_tls_socket_t *sock = (struct vlc_tls_socket *)tls;

    return sock->fd;
}

static ssize_t vlc_tls_SocketRead(vlc_tls_t *tls, struct iovec *iov,
                                  unsigned count)
{
    struct msghdr msg =
    {
        .msg_iov = iov,
        .msg_iovlen = count,
    };

    return recvmsg(vlc_tls_SocketGetFD(tls), &msg, 0);
}

static ssize_t vlc_tls_SocketWrite(vlc_tls_t *tls, const struct iovec *iov,
                                   unsigned count)
{
    const struct msghdr msg =
    {
        .msg_iov = (struct iovec *)iov,
        .msg_iovlen = count,
    };

    return sendmsg(vlc_tls_SocketGetFD(tls), &msg, MSG_NOSIGNAL);
}

static int vlc_tls_SocketShutdown(vlc_tls_t *tls, bool duplex)
{
    return shutdown(vlc_tls_SocketGetFD(tls), duplex ? SHUT_RDWR : SHUT_WR);
}

static void vlc_tls_SocketClose(vlc_tls_t *tls)
{
    net_Close(vlc_tls_SocketGetFD(tls));
    free(tls);
}

static vlc_tls_t *vlc_tls_SocketAlloc(int fd,
                                      const struct sockaddr *restrict peer,
                                      socklen_t peerlen)
{
    vlc_tls_socket_t *sock = malloc(sizeof (*sock) + peerlen);
    if (unlikely(sock == NULL))
        return NULL;

    vlc_tls_t *tls = &sock->tls;

    tls->get_fd = vlc_tls_SocketGetFD;
    tls->readv = vlc_tls_SocketRead;
    tls->writev = vlc_tls_SocketWrite;
    tls->shutdown = vlc_tls_SocketShutdown;
    tls->close = vlc_tls_SocketClose;
    tls->p = NULL;

    sock->fd = fd;
    sock->connect_timeout = 0;
    sock->peerlen = peerlen;
    if (peerlen > 0)
        memcpy(sock->peer, peer, peerlen);
    return tls;
}

vlc_tls_t *vlc_tls_SocketOpen(int fd)
{
    return vlc_tls_SocketAlloc(fd, NULL, 0);
}

int vlc_tls_SocketPair(int family, int protocol, vlc_tls_t *pair[2])
{
    int fds[2];

    if (vlc_socketpair(family, SOCK_STREAM, protocol, fds, true))
        return -1;

    for (size_t i = 0; i < 2; i++)
    {
        setsockopt(fds[i], SOL_SOCKET, SO_REUSEADDR,
                   &(int){ 1 }, sizeof (int));

        pair[i] = vlc_tls_SocketAlloc(fds[i], NULL, 0);
        if (unlikely(pair[i] == NULL))
        {
            net_Close(fds[i]);
            if (i)
                vlc_tls_SessionDelete(pair[0]);
            else
                net_Close(fds[1]);
            return -1;
        }
    }
    return 0;
}

/**
 * Allocates an unconnected transport layer socket.
 */
static vlc_tls_t *vlc_tls_SocketAddrInfo(const struct addrinfo *restrict info)
{
    int fd = vlc_socket(info->ai_family, info->ai_socktype, info->ai_protocol,
                        true /* nonblocking */);
    if (fd == -1)
        return NULL;

    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &(int){ 1 }, sizeof (int));

    if (info->ai_socktype == SOCK_STREAM && info->ai_protocol == IPPROTO_TCP)
        setsockopt(fd, SOL_TCP, TCP_NODELAY, &(int){ 1 }, sizeof (int));

    vlc_tls_t *sk = vlc_tls_SocketAlloc(fd, info->ai_addr, info->ai_addrlen);
    if (unlikely(sk == NULL))
        net_Close(fd);
    return sk;
}

/**
 * Waits for pending transport layer socket connection.
 */
static int vlc_tls_WaitConnect(vlc_tls_t *tls)
{
    const vlc_tls_socket_t *sock = (vlc_tls_socket_t *)tls;
    const int fd = vlc_tls_GetFD(tls);
    struct pollfd ufd;
    vlc_tick_t deadline = (sock->connect_timeout > 0)
        ? mdate() + sock->connect_timeout : 0;

    ufd.fd = fd;
    ufd.events = POLLOUT;

    int ret;
    do
    {
        if (vlc_killed())
        {
            errno = EINTR;
            return -1;
        }

        int wait_ms = -1;
        if (deadline != 0)
        {
            vlc_tick_t remaining = deadline - mdate();
            if (remaining <= 0)
            {
                errno = ETIMEDOUT;
                return -1;
            }
            wait_ms = remaining / 1000 + 1;
        }
        ret = vlc_poll_i11e(&ufd, 1, wait_ms);
    }
    while (ret <= 0);

    int val;
    socklen_t len = sizeof (val);

    if (getsockopt(fd, SOL_SOCKET, SO_ERROR, &val, &len))
        return -1;

    if (val != 0)
    {
        errno = val;
        return -1;
    }
    return 0;
}

/**
 * Connects a transport layer socket.
 */
static ssize_t vlc_tls_Connect(vlc_tls_t *tls)
{
    const vlc_tls_socket_t *sock = (vlc_tls_socket_t *)tls;

    if (connect(sock->fd, sock->peer, sock->peerlen) == 0)
        return 0;
#ifndef _WIN32
    if (errno != EINPROGRESS)
        return -1;
#else
    if (WSAGetLastError() != WSAEWOULDBLOCK)
        return -1;
#endif
    return vlc_tls_WaitConnect(tls);
}

/* Callback for combined connection establishment and initial send */
static ssize_t vlc_tls_ConnectWrite(vlc_tls_t *tls,
                                    const struct iovec *iov,unsigned count)
{
#ifdef MSG_FASTOPEN
    vlc_tls_socket_t *sock = (vlc_tls_socket_t *)tls;
    const struct msghdr msg =
    {
        .msg_name = sock->peer,
        .msg_namelen = sock->peerlen,
        .msg_iov = (struct iovec *)iov,
        .msg_iovlen = count,
    };
    ssize_t ret;

    /* Next time, write directly. Do not retry to connect. */
    tls->writev = vlc_tls_SocketWrite;

    ret = sendmsg(vlc_tls_SocketGetFD(tls), &msg, MSG_NOSIGNAL|MSG_FASTOPEN);
    if (ret >= 0)
    {   /* Fast open in progress */
        return ret;
    }

    if (errno == EINPROGRESS)
    {
        if (vlc_tls_WaitConnect(tls))
            return -1;
    }
    else
    if (errno != EOPNOTSUPP)
        return -1;
    /* Fast open not supported or disabled... fallback to normal mode */
#else
    tls->writev = vlc_tls_SocketWrite;
#endif

    if (vlc_tls_Connect(tls))
        return -1;

    return vlc_tls_SocketWrite(tls, iov, count);
}

/*****************************************************************************
 * Happy Eyeballs (RFC 8305)
 *****************************************************************************
 * The addresses of a name used to be tried strictly one after another, and
 * vlc_tls_WaitConnect() polls without a deadline. So a dual-stack host whose
 * IPv6 path is a black hole stalled every connection for the kernel's full
 * TCP timeout -- 75 s on Darwin -- before the IPv4 address was even tried.
 * Measured on api-addons.videolan.org, which is exactly such a host.
 *
 * Attempts are now interleaved by family and raced, the first one to connect
 * winning. Single-address names keep the old deferred-connect path: there is
 * nothing to race, and deferring lets TCP Fast Open carry the first payload
 * in the SYN.
 *****************************************************************************/
#define VLC_HE_MAX_ADDRS     16 /* addresses considered at all */
#define VLC_HE_MAX_INFLIGHT   6 /* RFC 8305 §5: cap on parallel attempts */
#define VLC_HE_ATTEMPT_DELAY 250 /* ms, RFC 8305 §5 recommended value */

struct vlc_tls_attempt
{
    vlc_tls_t *sock;
    size_t index;
};

/**
 * Copies the address list into @c tab, alternating address families.
 * @return the number of addresses copied.
 */
static size_t vlc_tls_InterleaveAddrInfo(const struct addrinfo *res,
                                         const struct addrinfo *tab[],
                                         size_t max)
{
    size_t n = 0;

    for (const struct addrinfo *p = res; p != NULL && n < max; p = p->ai_next)
        tab[n++] = p;
    if (n < 2)
        return n;

    /* RFC 8305 §4: alternate families, the family of the first address
     * first. The order within a family is kept as the resolver gave it: it
     * already encodes the system destination address policy (RFC 6724). */
    const struct addrinfo *first[VLC_HE_MAX_ADDRS];
    const struct addrinfo *other[VLC_HE_MAX_ADDRS];
    size_t nfirst = 0, nother = 0;
    const int family = tab[0]->ai_family;

    for (size_t i = 0; i < n; i++)
    {
        if (tab[i]->ai_family == family)
            first[nfirst++] = tab[i];
        else
            other[nother++] = tab[i];
    }

    size_t k = 0, i = 0, j = 0;

    while (i < nfirst || j < nother)
    {
        if (i < nfirst)
            tab[k++] = first[i++];
        if (j < nother)
            tab[k++] = other[j++];
    }
    return n;
}

/**
 * Races connection attempts against the addresses of @c tab.
 * @param winner set to the index in @c tab of the address that won
 * @return a connected socket, or NULL with @c errno set.
 */
static vlc_tls_t *vlc_tls_SocketRace(vlc_object_t *obj,
                                     const struct addrinfo *const tab[],
                                     size_t n, size_t *restrict winner)
{
    struct vlc_tls_attempt inflight[VLC_HE_MAX_INFLIGHT];
    struct pollfd ufd[VLC_HE_MAX_INFLIGHT];
    size_t count = 0, next = 0;
    int saved_errno = ENETUNREACH;

    /* Overall bound: without it, once every address is in flight the race
     * waits on the kernel TCP timeout (75 s on Darwin) when the host
     * silently drops SYNs. Same knob as every other connect path. */
    vlc_tick_t timeout = var_InheritInteger(obj, "ipv4-timeout") * 1000;
    vlc_tick_t deadline = (timeout > 0) ? mdate() + timeout : 0;

    while (count > 0 || next < n)
    {
        /* Start attempts until one is actually pending: an address that
         * fails outright must not consume the staggering delay. */
        while (next < n && count < VLC_HE_MAX_INFLIGHT)
        {
            const size_t index = next++;
            const struct addrinfo *ai = tab[index];
            vlc_tls_t *sock = vlc_tls_SocketAddrInfo(ai);

            if (sock == NULL)
            {
                saved_errno = errno;
                continue;
            }

            if (connect(vlc_tls_GetFD(sock), ai->ai_addr, ai->ai_addrlen) == 0)
            {   /* Connected without waiting (loopback, or a warm path). */
                for (size_t i = 0; i < count; i++)
                    vlc_tls_SessionDelete(inflight[i].sock);
                *winner = index;
                return sock;
            }
#ifdef _WIN32
            if (WSAGetLastError() != WSAEWOULDBLOCK)
#else
            if (errno != EINPROGRESS)
#endif
            {
                saved_errno = errno;
                vlc_tls_SessionDelete(sock);
                continue;
            }

            inflight[count].sock = sock;
            inflight[count].index = index;
            count++;
            break; /* let this one breathe before starting the next */
        }

        if (count == 0)
            break; /* nothing pending and no address left */

        for (size_t i = 0; i < count; i++)
        {
            ufd[i].fd = vlc_tls_GetFD(inflight[i].sock);
            ufd[i].events = POLLOUT;
            ufd[i].revents = 0;
        }

        /* Only wait forever once the last address is in flight -- and
         * never past the overall deadline. */
        int wait_ms = (next < n) ? VLC_HE_ATTEMPT_DELAY : -1;
        if (deadline != 0)
        {
            vlc_tick_t remaining = deadline - mdate();
            if (remaining <= 0)
            {
                saved_errno = ETIMEDOUT;
                goto fail;
            }
            int remaining_ms = remaining / 1000 + 1;
            if (wait_ms < 0 || remaining_ms < wait_ms)
                wait_ms = remaining_ms;
        }
        int ret = vlc_poll_i11e(ufd, count, wait_ms);
        if (ret < 0)
        {
            saved_errno = errno;
            goto fail;
        }
        if (ret == 0)
            continue; /* delay expired: next address, or deadline check */

        for (size_t i = 0; i < count; )
        {
            if (ufd[i].revents == 0)
            {
                i++;
                continue;
            }

            int val = 0;
            socklen_t len = sizeof (val);

            if (getsockopt(ufd[i].fd, SOL_SOCKET, SO_ERROR, &val, &len) == 0
             && val == 0)
            {   /* Winner: drop every other attempt. */
                vlc_tls_t *sock = inflight[i].sock;

                *winner = inflight[i].index;
                for (size_t j = 0; j < count; j++)
                    if (j != i)
                        vlc_tls_SessionDelete(inflight[j].sock);
                return sock;
            }

            saved_errno = (val != 0) ? val : errno;
            msg_Dbg(obj, "connection attempt failed: %s",
                    vlc_strerror_c(saved_errno));
            vlc_tls_SessionDelete(inflight[i].sock);
            /* compact both arrays in step, and re-examine this slot */
            inflight[i] = inflight[--count];
            ufd[i] = ufd[count];
        }
    }

fail:
    for (size_t i = 0; i < count; i++)
        vlc_tls_SessionDelete(inflight[i].sock);
    errno = saved_errno;
    return NULL;
}

vlc_tls_t *vlc_tls_SocketOpenAddrInfo(const struct addrinfo *restrict info,
                                      bool defer_connect)
{
    vlc_tls_t *sock = vlc_tls_SocketAddrInfo(info);
    if (sock == NULL)
        return NULL;

    if (defer_connect)
    {   /* The socket is not connected yet.
         * The connection will be triggered on the first send. */
        sock->writev = vlc_tls_ConnectWrite;
    }
    else
    {
        if (vlc_tls_Connect(sock))
        {
            vlc_tls_SessionDelete(sock);
            sock = NULL;
        }
    }
    return sock;
}

vlc_tls_t *vlc_tls_SocketOpenTCP(vlc_object_t *obj, const char *name,
                                 unsigned port)
{
    struct addrinfo hints =
    {
        .ai_socktype = SOCK_STREAM,
        .ai_protocol = IPPROTO_TCP,
    }, *res;

    assert(name != NULL);
    msg_Dbg(obj, "resolving %s ...", name);

    int val = vlc_getaddrinfo_i11e(name, port, &hints, &res);
    if (val != 0)
    {   /* TODO: C locale for gai_strerror() */
        msg_Err(obj, "cannot resolve %s port %u: %s", name, port,
                gai_strerror(val));
        return NULL;
    }

    msg_Dbg(obj, "connecting to %s port %u ...", name, port);

    const struct addrinfo *tab[VLC_HE_MAX_ADDRS];
    size_t n = vlc_tls_InterleaveAddrInfo(res, tab, VLC_HE_MAX_ADDRS);
    size_t winner;
    vlc_tls_t *tls = vlc_tls_SocketRace(obj, tab, n, &winner);

    if (tls == NULL)
        msg_Err(obj, "connection error: %s", vlc_strerror_c(errno));

    freeaddrinfo(res); /* tab[] points into res: not one line sooner */
    return tls;
}

vlc_tls_t *vlc_tls_SocketOpenTLS(vlc_tls_creds_t *creds, const char *name,
                                 unsigned port, const char *service,
                                 const char *const *alpn, char **alp)
{
    struct addrinfo hints =
    {
        .ai_socktype = SOCK_STREAM,
        .ai_protocol = IPPROTO_TCP,
    }, *res;

    msg_Dbg(creds, "resolving %s ...", name);

    int val = vlc_getaddrinfo_i11e(name, port, &hints, &res);
    if (val != 0)
    {   /* TODO: C locale for gai_strerror() */
        msg_Err(creds, "cannot resolve %s port %u: %s", name, port,
                gai_strerror(val));
        return NULL;
    }

    const struct addrinfo *tab[VLC_HE_MAX_ADDRS];
    size_t n = vlc_tls_InterleaveAddrInfo(res, tab, VLC_HE_MAX_ADDRS);
    vlc_tls_t *tls = NULL;

    while (n > 0)
    {
        vlc_tls_t *tcp;
        size_t winner = 0;

        if (n == 1)
        {   /* Nothing to race. Keep deferring the connect so that TCP Fast
             * Open can carry the TLS ClientHello in the SYN. */
            tcp = vlc_tls_SocketOpenAddrInfo(tab[0], true);
            if (tcp == NULL)
            {
                msg_Err(creds, "socket error: %s", vlc_strerror_c(errno));
                break;
            }
            /* bound the deferred connect wait like the raced path */
            ((vlc_tls_socket_t *)tcp)->connect_timeout =
                var_InheritInteger(creds, "ipv4-timeout") * 1000;
        }
        else
        {
            tcp = vlc_tls_SocketRace(VLC_OBJECT(creds), tab, n, &winner);
            if (tcp == NULL)
            {
                msg_Err(creds, "connection error: %s", vlc_strerror_c(errno));
                break;
            }
        }

        tls = vlc_tls_ClientSessionCreate(creds, tcp, name, service, alpn, alp);
        if (tls != NULL)
            break; /* Success! */

        msg_Err(creds, "connection error: %s", vlc_strerror_c(errno));
        vlc_tls_SessionDelete(tcp);

        /* A TLS failure is rarely address-specific, but a multi-homed host
         * can genuinely have one bad endpoint, and the sequential code this
         * replaces did try them all. Drop the loser and race what is left. */
        memmove(&tab[winner], &tab[winner + 1],
                (n - winner - 1) * sizeof (tab[0]));
        n--;
    }

    freeaddrinfo(res); /* tab[] points into res: not one line sooner */
    return tls;
}
