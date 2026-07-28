/*****************************************************************************
 * check-jaguar-selectors.m: report selectors no loaded class implements
 *****************************************************************************
 * Companion to list-objc-selectors.py. Compile and run this ON the old
 * system; feed it the selector list the plug-in sends and it names the ones
 * that exist nowhere in that system's frameworks -- the calls that will
 * raise NSInvalidArgumentException the moment they are reached.
 *
 *     list-objc-selectors.py --sent  libfoo.dylib > sent
 *     list-objc-selectors.py --defined libfoo.dylib > defined
 *     comm -23 sent defined > needed          # what it wants from the system
 *     cc -o check check-jaguar-selectors.m -framework Cocoa -framework Carbon
 *     ./check < needed
 *
 * It answers "does this system know this selector at all", not "does the
 * receiver respond to it": a selector another class happens to implement
 * passes here and can still fail at the call site. It is a filter for the
 * cheap half of the problem, not a proof.
 *****************************************************************************/

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>
#import <objc/objc-class.h>
#import <objc/objc-runtime.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

/* Open-addressing set of selector names, sized well above the ~40k a full
 * Cocoa + Carbon process registers. */
#define TABLE_SIZE 262144

static const char *table[TABLE_SIZE];

static unsigned long hash_of(const char *s)
{
    unsigned long h = 5381;

    while (*s)
        h = h * 33 + (unsigned char) *s++;
    return h;
}

static void insert(const char *name)
{
    unsigned long i = hash_of(name) % TABLE_SIZE;

    while (table[i] != NULL) {
        if (!strcmp(table[i], name))
            return;
        i = (i + 1) % TABLE_SIZE;
    }
    table[i] = name;
}

static int contains(const char *name)
{
    unsigned long i = hash_of(name) % TABLE_SIZE;

    while (table[i] != NULL) {
        if (!strcmp(table[i], name))
            return 1;
        i = (i + 1) % TABLE_SIZE;
    }
    return 0;
}

static void collect_class(Class cls)
{
    void *iterator = NULL;
    struct objc_method_list *methods;

    while ((methods = class_nextMethodList(cls, &iterator)) != NULL) {
        int i;

        for (i = 0; i < methods->method_count; i++)
            insert(sel_getName(methods->method_list[i].method_name));
    }
}

int main(void)
{
    /* Touching the classes forces the frameworks that are linked lazily to
     * be there before the runtime is enumerated. */
    [NSAutoreleasePool class];
    [NSApplication class];
    [NSMenu class];

    int count = objc_getClassList(NULL, 0);
    Class *classes = malloc(sizeof (Class) * count);


    if (classes == NULL)
        return 1;
    objc_getClassList(classes, count);

    int i;

    for (i = 0; i < count; i++) {
        collect_class(classes[i]);
        collect_class(classes[i]->isa);   /* class methods */
    }
    free(classes);

    char line[512];
    int missing = 0;

    while (fgets(line, sizeof (line), stdin) != NULL) {
        size_t len = strlen(line);

        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r'))
            line[--len] = '\0';
        if (len == 0)
            continue;

        if (!contains(line)) {
            printf("%s\n", line);
            missing++;
        }
    }

    fprintf(stderr, "%d selector(s) unknown to this system\n", missing);
    return missing > 0 ? 1 : 0;
}
