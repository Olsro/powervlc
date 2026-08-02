/*****************************************************************************
 * objc102.c: Objective-C exceptions and @synchronized for Mac OS X 10.2
 *****************************************************************************
 * @try/@catch/@finally and @synchronized became runtime features in 10.3.
 * Verified against the libobjc of a 10.2.1 install: it exports none of
 * objc_exception_{throw,try_enter,try_exit,extract,match} nor
 * objc_sync_{enter,exit}. Without them the interface plug-in and all three
 * video outputs fail to load -- exactly the four that carry Objective-C.
 *
 * These are hard references in libobjc, not weak ones, and they are not in
 * libSystem either: neither check-weak-symbols.sh nor the libSystem inventory
 * could see them. They only surfaced as "cannot load module ... undefined
 * reference to _objc_exception_extract" at runtime.
 *
 * EXCEPTIONS. GCC hands the same address to objc_exception_try_enter() and to
 * _setjmp() (verified in the generated assembly), so the jump buffer sits at
 * offset 0 of the exception data it allocates on the stack. That is the only
 * thing this code assumes about GCC's layout: the handler chain and the
 * in-flight exception are kept here instead of in GCC's own struct, so the
 * rest of it stays opaque.
 *
 * @synchronized. A recursive mutex per object, in a small table. Objects that
 * are synchronised on are few (VLC uses it for a handful of view and picture
 * locks), so a linear table with a global guard costs nothing measurable.
 *****************************************************************************/

#include <setjmp.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <pthread.h>

/* The legacy Objective-C object and class layout, spelled out rather than
 * included: this file must not drag <objc/objc-class.h> into a plain C
 * translation unit. */
struct tiny_class
{
    struct tiny_class *isa;
    struct tiny_class *super_class;
};

struct tiny_object
{
    struct tiny_class *isa;
};

/*===========================================================================
 * Exceptions
 *=========================================================================*/

typedef struct eh_frame
{
    void            *data;       /* what GCC passed us; jmp_buf at offset 0 */
    void            *exception;  /* set by throw, taken by extract */
    struct eh_frame *next;
} eh_frame_t;

static pthread_key_t  eh_key;
static pthread_once_t eh_once = PTHREAD_ONCE_INIT;

static void eh_key_create(void)
{
    pthread_key_create(&eh_key, NULL);
}

static eh_frame_t *eh_top(void)
{
    pthread_once(&eh_once, eh_key_create);
    return pthread_getspecific(eh_key);
}

static void eh_set_top(eh_frame_t *f)
{
    pthread_once(&eh_once, eh_key_create);
    pthread_setspecific(eh_key, f);
}

void objc_exception_try_enter(void *data)
{
    eh_frame_t *f = malloc(sizeof (*f));

    if (f == NULL)
        abort();

    f->data = data;
    f->exception = NULL;
    f->next = eh_top();
    eh_set_top(f);
}

void objc_exception_try_exit(void *data)
{
    eh_frame_t *head = eh_top();

    /* Leaving the protected block normally: drop our frame. GCC pairs this
     * with the matching try_enter, so it is nearly always the head; searching
     * anyway costs nothing and never corrupts the chain if it is not. */
    for (eh_frame_t **pp = &head; *pp != NULL; pp = &(*pp)->next)
        if ((*pp)->data == data)
        {
            eh_frame_t *dead = *pp;

            *pp = dead->next;
            free(dead);
            eh_set_top(head);
            return;
        }
}

void *objc_exception_extract(void *data)
{
    eh_frame_t *f = eh_top();
    void *e = NULL;

    /* Reached after the longjmp: hand back what was thrown and drop the
     * frame the throw left in place for us. */
    if (f != NULL && f->data == data)
    {
        e = f->exception;
        eh_set_top(f->next);
        free(f);
    }
    return e;
}

void objc_exception_throw(void *exception)
{
    eh_frame_t *f = eh_top();

    if (f == NULL)
    {
        fprintf(stderr, "objc: uncaught exception, terminating\n");
        abort();
    }

    /* The frame stays on the chain: objc_exception_extract() pops it once the
     * longjmp has landed in the @catch. */
    f->exception = exception;
    _longjmp((void *) f->data, 1);
}

int objc_exception_match(void *exception_class, void *exception)
{
    struct tiny_object *obj = exception;

    if (obj == NULL)
        return 0;

    for (struct tiny_class *c = obj->isa; c != NULL; c = c->super_class)
        if ((void *) c == exception_class)
            return 1;
    return 0;
}

/*===========================================================================
 * @synchronized
 *=========================================================================*/

/* Slots are never reclaimed. Recycling one means deciding that nobody holds
 * its mutex any more, and getting that wrong -- reinitialising a mutex under
 * a thread that is about to unlock it -- corrupts the allocator in ways that
 * only surface much later, somewhere in free(). The objects a program
 * synchronises on are few and long-lived, so a slot each, kept forever, costs
 * a few dozen bytes and removes the whole question. */
typedef struct sync_slot
{
    void             *object;
    pthread_mutex_t   mutex;
    struct sync_slot *next;
} sync_slot_t;

static sync_slot_t    *sync_slots;
static pthread_mutex_t sync_table_lock = PTHREAD_MUTEX_INITIALIZER;

static pthread_mutex_t *sync_slot_for(void *object)
{
    pthread_mutex_t *found = NULL;

    pthread_mutex_lock(&sync_table_lock);
    for (sync_slot_t *s = sync_slots; s != NULL; s = s->next)
        if (s->object == object)
        {
            found = &s->mutex;
            break;
        }

    if (found == NULL)
    {
        sync_slot_t *s = malloc(sizeof (*s));

        if (s != NULL)
        {
            pthread_mutexattr_t attr;

            pthread_mutexattr_init(&attr);
            pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
            pthread_mutex_init(&s->mutex, &attr);
            pthread_mutexattr_destroy(&attr);

            s->object = object;
            s->next = sync_slots;
            sync_slots = s;
            found = &s->mutex;
        }
    }
    pthread_mutex_unlock(&sync_table_lock);
    return found;
}

int objc_sync_enter(void *object)
{
    if (object == NULL)
        return 0;

    pthread_mutex_t *m = sync_slot_for(object);

    if (m == NULL)
        return -1;
    return pthread_mutex_lock(m) == 0 ? 0 : -1;
}

int objc_sync_exit(void *object)
{
    if (object == NULL)
        return 0;

    pthread_mutex_t *m = sync_slot_for(object);

    if (m == NULL)
        return -1;
    return pthread_mutex_unlock(m) == 0 ? 0 : -1;
}
