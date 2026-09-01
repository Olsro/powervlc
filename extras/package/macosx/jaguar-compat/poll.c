/*****************************************************************************
 * poll.c: poll() emulation for Mac OS X 10.2
 *****************************************************************************
 * Copyright (C) 2007-2012 Remi Denis-Courmont
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or (at
 * your option) any later version.
 *****************************************************************************
 * Jaguar has select(), but poll() was only added in Mac OS X 10.3.  Keep the
 * replacement in the common Jaguar compatibility archive so VLC and bundled
 * download engines can use the same implementation.
 *****************************************************************************/

#include <poll.h>
#include <sys/select.h>
#include <sys/time.h>
#include <fcntl.h>
#include <pthread.h>
#include <errno.h>
#include <stdlib.h>

#define POLL_SLICE_MS 100

static int poll_once(struct pollfd *fds, nfds_t nfds, int timeout)
{
    fd_set rdset, wrset, exset;
    struct timeval tv = { 0, 0 };
    int maxfd = -1;
    nfds_t i;

    FD_ZERO(&rdset);
    FD_ZERO(&wrset);
    FD_ZERO(&exset);

    for (i = 0; i < nfds; ++i) {
        int fd = fds[i].fd;

        fds[i].revents = 0;
        if (fd < 0)
            continue;
        if (fd >= FD_SETSIZE) {
            errno = EINVAL;
            return -1;
        }
        if (fd > maxfd)
            maxfd = fd;
        if (fds[i].events & (POLLIN | POLLRDNORM))
            FD_SET(fd, &rdset);
        if (fds[i].events & (POLLOUT | POLLWRNORM))
            FD_SET(fd, &wrset);
        if (fds[i].events & POLLPRI)
            FD_SET(fd, &exset);
    }

    if (timeout >= 0) {
        div_t d = div(timeout, 1000);
        tv.tv_sec = d.quot;
        tv.tv_usec = d.rem * 1000;
    }

    {
        int ready = select(maxfd + 1, &rdset, &wrset, &exset,
                           timeout >= 0 ? &tv : NULL);
        if (ready < 0) {
            if (errno != EBADF)
                return -1;

            ready = 0;
            for (i = 0; i < nfds; ++i) {
                if (fds[i].fd >= 0 && fcntl(fds[i].fd, F_GETFD) == -1) {
                    fds[i].revents = POLLNVAL;
                    ++ready;
                }
            }
            return ready ? ready : -1;
        }

        for (i = 0; i < nfds; ++i) {
            int fd = fds[i].fd;
            if (fd < 0)
                continue;
            if (FD_ISSET(fd, &rdset))
                fds[i].revents |= fds[i].events & (POLLIN | POLLRDNORM);
            if (FD_ISSET(fd, &wrset))
                fds[i].revents |= fds[i].events & (POLLOUT | POLLWRNORM);
            if (FD_ISSET(fd, &exset))
                fds[i].revents |= POLLPRI;
        }
        return ready;
    }
}

int poll(struct pollfd *fds, nfds_t nfds, int timeout)
{
    pthread_testcancel();

    if (timeout >= 0)
        return poll_once(fds, nfds, timeout);

    for (;;) {
        int ready = poll_once(fds, nfds, POLL_SLICE_MS);
        if (ready != 0)
            return ready;
        pthread_testcancel();
    }
}
