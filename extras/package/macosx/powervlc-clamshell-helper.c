/*
 * PowerVLC legacy HDMI 3D scanout helper.
 *
 * The Ivy Bridge framebuffer in the 2012 MacBook Pro cannot reliably drive
 * its internal LVDS pipe alongside a 1920x2205 HDMI frame-packing scanout.
 * Publishing the same clamshell resource used by IOGraphics is the only
 * tested transition that completely stops LVDS on Mavericks.  This helper is
 * intentionally tiny because PowerVLC launches it as root through
 * Authorization Services.
 *
 * It stays alive on the bidirectional pipe supplied by
 * AuthorizationExecuteWithPrivileges.  Closing PowerVLC, including an
 * abnormal termination, closes that pipe and restores the open-lid state.
 */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOKitLib.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static volatile sig_atomic_t interrupted;

static void stop_helper(int signal_number)
{
    (void)signal_number;
    interrupted = 1;
}

static IOReturn publish_state(io_service_t resources, Boolean closed)
{
    return IORegistryEntrySetCFProperty(resources,
                                        CFSTR("AppleClamshellState"),
                                        closed ? kCFBooleanTrue
                                               : kCFBooleanFalse);
}

int main(int argc, char **argv)
{
    if (argc != 2 || strcmp(argv[1], "hold") != 0)
        return 64;

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    io_service_t resources = IOServiceGetMatchingService(
        kIOMasterPortDefault, IOServiceMatching("IOResources"));
#pragma clang diagnostic pop
    if (resources == IO_OBJECT_NULL)
        return 2;

    signal(SIGINT, stop_helper);
    signal(SIGTERM, stop_helper);

    IOReturn result = publish_state(resources, true);
    if (result == kIOReturnSuccess)
    {
        char byte;
        while (!interrupted && read(STDIN_FILENO, &byte, 1) > 0)
            ;
    }

    /* The Authorization pipe can be closed while the real lid is down during
     * system sleep.  Leaving AppleClamshellState=true in that branch strands
     * Mavericks without an internal scanout after wake (and WindowServer can
     * then block uninterruptibly).  Exiting this synthetic owner must always
     * return the resource to the normal open-lid state; the physical lid
     * driver remains authoritative and will republish a genuine closed state
     * independently when appropriate. */
    IOReturn restore = publish_state(resources, false);

    IOObjectRelease(resources);
    return result == kIOReturnSuccess && restore == kIOReturnSuccess ? 0 : 3;
}
