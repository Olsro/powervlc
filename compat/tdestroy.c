/**
 * @file tdestroy.c
 * @brief replacement for GNU tdestroy()
 */
/*****************************************************************************
 * Copyright (C) 2009, 2018 Rémi Denis-Courmont
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

#include <assert.h>
#include <stdlib.h>
#ifdef HAVE_SEARCH_H
# include <search.h>
#endif

#ifdef HAVE_TFIND
/* Mac OS X 10.6 and earlier lack __thread support; serialize with a mutex
 * instead of using thread-local state. */
#if defined(__APPLE__) && defined(__ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__) \
    && __ENVIRONMENT_MAC_OS_X_VERSION_MIN_REQUIRED__ < 1070
# include <pthread.h>
# define VLC_COMPAT_TLS
static pthread_mutex_t tdestroy_lock = PTHREAD_MUTEX_INITIALIZER;
# define TDESTROY_LOCK()   pthread_mutex_lock(&tdestroy_lock)
# define TDESTROY_UNLOCK() pthread_mutex_unlock(&tdestroy_lock)
#else
# define VLC_COMPAT_TLS __thread
# define TDESTROY_LOCK()   (void)0
# define TDESTROY_UNLOCK() (void)0
#endif

static VLC_COMPAT_TLS struct
{
    const void **tab;
    size_t count;
} list = { NULL, 0 };

static void list_nodes(const void *node, const VISIT which, const int depth)
{
    (void) depth;

    if (which != postorder && which != leaf)
        return;

    const void **tab = realloc(list.tab, sizeof (*tab) * (list.count + 1));
    if (tab == NULL)
        abort();

    tab[list.count] = *(const void **)node;
    list.tab = tab;
    list.count++;
}

static VLC_COMPAT_TLS const void *smallest;

static int cmp_smallest(const void *a, const void *b)
{
    if (a == b)
        return 0;
    if (a == smallest)
        return -1;
    if (b == smallest)
        return +1;
    abort();
}

void tdestroy(void *root, void (*freenode)(void *))
{
    const void **tab;
    size_t count;

    assert(freenode != NULL);

    TDESTROY_LOCK();

    /* Enumerate nodes in order */
    assert(list.count == 0);
    twalk(root, list_nodes);
    tab = list.tab;
    count = list.count;
    list.tab = NULL;
    list.count = 0;

    /* Destroy the tree */
    for (size_t i = 0; i < count; i++)
    {
         void *node = (void *)(tab[i]);

         smallest = node;
         node = tdelete(node, &root, cmp_smallest);
         assert(node != NULL);
    }
    assert (root == NULL);

    TDESTROY_UNLOCK();

    /* Destroy the nodes */
    for (size_t i = 0; i < count; i++)
         freenode((void *)(tab[i]));
    free(tab);
}
#endif /* HAVE_TFIND */
