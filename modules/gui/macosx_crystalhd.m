/*****************************************************************************
 * macosx_crystalhd.m: Crystal HD driver detection and installation
 *****************************************************************************
 * Copyright © 2026 PowerVLC
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

#import "macosx_crystalhd.h"

#import <AppKit/AppKit.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <Security/Authorization.h>
/* kAuthorizationRightExecute lives here, not in Authorization.h. */
#import <Security/AuthorizationTags.h>

#include <vlc_common.h>

#include <sys/utsname.h>
#include <sys/sysctl.h>
#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <mach-o/fat.h>
#include <mach-o/loader.h>
#include <mach-o/arch.h>

/* Kept in sync with the PCI ids matched by the kext's Info.plist and with
 * modules/codec/crystalhd_osx.c, which does the same probe for the decoder. */
#define CRYSTALHD_VENDOR_BROADCOM   0x14e4
#define CRYSTALHD_DEVICE_BCM70012   0x1612
#define CRYSTALHD_DEVICE_BCM70015   0x1615

#define CRYSTALHD_KEXT_NAME     @"BroadcomCrystalHD.kext"
#define CRYSTALHD_SCRIPT_NAME   @"crystalhd-kext"

#define CRYSTALHD_PROMPT_DEFAULT @"VLCCrystalHDStartupPromptSuppressed"

/*****************************************************************************
 * Hardware probing
 *****************************************************************************/
static BOOL ReadPCIWord(io_service_t service, CFStringRef key, uint16_t *pi_value)
{
    CFTypeRef p_ref = IORegistryEntryCreateCFProperty(service, key,
                                                      kCFAllocatorDefault, 0);
    if (p_ref == NULL)
        return NO;

    BOOL b_ok = NO;
    if (CFGetTypeID(p_ref) == CFDataGetTypeID() && CFDataGetLength(p_ref) >= 2) {
        /* Raw config space bytes, little endian: do not cast, PowerPC would
         * read them backwards. */
        const UInt8 *p_bytes = CFDataGetBytePtr(p_ref);
        *pi_value = p_bytes[0] | (p_bytes[1] << 8);
        b_ok = YES;
    }

    CFRelease(p_ref);
    return b_ok;
}

static BOOL CardIsPresent(void)
{
    CFMutableDictionaryRef p_match = IOServiceMatching("IOPCIDevice");
    if (p_match == NULL)
        return NO;

    /* IOServiceGetMatchingServices consumes the dictionary even on failure.
     * MACH_PORT_NULL selects the default port and, unlike
     * kIOMasterPortDefault, is not deprecated on recent SDKs. */
    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(MACH_PORT_NULL, p_match,
                                     &iterator) != KERN_SUCCESS)
        return NO;

    BOOL b_found = NO;
    io_service_t service;

    while (!b_found &&
           (service = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        uint16_t i_vendor, i_device;

        if (ReadPCIWord(service, CFSTR("vendor-id"), &i_vendor) &&
            ReadPCIWord(service, CFSTR("device-id"), &i_device) &&
            i_vendor == CRYSTALHD_VENDOR_BROADCOM &&
            (i_device == CRYSTALHD_DEVICE_BCM70012 ||
             i_device == CRYSTALHD_DEVICE_BCM70015))
            b_found = YES;

        IOObjectRelease(service);
    }

    IOObjectRelease(iterator);
    return b_found;
}

/*****************************************************************************
 * Driver location
 *****************************************************************************/
static NSString *InstalledDriverPath(void)
{
    NSFileManager *fm = [NSFileManager defaultManager];

    /* /Library/Extensions is where third-party kexts belong from 10.9 on;
     * everything older only looks in /System/Library/Extensions. Check both,
     * so a driver installed under either layout is found. */
    /* Indexed loop, not fast enumeration: this file is also compiled for the
     * legacy interface, which targets 10.4, and for..in needs the 10.5
     * runtime. */
    NSArray *dirs = [NSArray arrayWithObjects:@"/Library/Extensions",
                                              @"/System/Library/Extensions",
                                              nil];
    unsigned count = [dirs count];
    for (unsigned i = 0; i < count; i++) {
        NSString *path = [[dirs objectAtIndex:i]
                            stringByAppendingPathComponent:CRYSTALHD_KEXT_NAME];
        BOOL isDir = NO;
        if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir)
            return path;
    }

    return nil;
}

static NSString *BundledDriverPath(void)
{
    return [[NSBundle mainBundle] pathForResource:@"BroadcomCrystalHD"
                                           ofType:@"kext"];
}

static NSString *HelperScriptPath(void)
{
    return [[NSBundle mainBundle] pathForResource:CRYSTALHD_SCRIPT_NAME
                                           ofType:@"sh"];
}

/*****************************************************************************
 * Kernel architecture
 *****************************************************************************
 * A kext is loaded into the kernel, so it has to match the kernel's own
 * architecture. That is not the CPU's: most 64-bit Macs of this era boot a
 * 32-bit kernel, and 10.6 does so by default on all but a few models.
 *****************************************************************************/
static cpu_type_t RunningKernelCPUType(void)
{
    struct utsname u;

    if (uname(&u) != 0)
        return CPU_TYPE_ANY;

    if (strcmp(u.machine, "x86_64") == 0)
        return CPU_TYPE_X86_64;
    if (strcmp(u.machine, "i386") == 0 || strcmp(u.machine, "i486") == 0 ||
        strcmp(u.machine, "i586") == 0 || strcmp(u.machine, "i686") == 0)
        return CPU_TYPE_I386;
    if (strncmp(u.machine, "Power", 5) == 0)
        return CPU_TYPE_POWERPC;

    return CPU_TYPE_ANY;
}

/* Read the architectures out of the kext's Mach-O rather than assuming what
 * was shipped, so this keeps working unchanged once a 64-bit slice exists. */
static BOOL BinaryHasCPUType(NSString *binaryPath, cpu_type_t wanted)
{
    NSData *data = [NSData dataWithContentsOfFile:binaryPath];
    if (data == nil || [data length] < sizeof(struct fat_header))
        return NO;

    const uint8_t *bytes = (const uint8_t *)[data bytes];
    uint32_t magic = *(const uint32_t *)bytes;

    /* Fat binaries store their headers big endian whatever the host. */
    if (magic == FAT_MAGIC || magic == FAT_CIGAM) {
        const struct fat_header *fh = (const struct fat_header *)bytes;
        uint32_t nfat = OSSwapBigToHostInt32(fh->nfat_arch);

        if ([data length] < sizeof(*fh) + nfat * sizeof(struct fat_arch))
            return NO;

        const struct fat_arch *fa =
            (const struct fat_arch *)(bytes + sizeof(*fh));
        for (uint32_t i = 0; i < nfat; i++) {
            if ((cpu_type_t)OSSwapBigToHostInt32(fa[i].cputype) == wanted)
                return YES;
        }
        return NO;
    }

    if (magic == MH_MAGIC || magic == MH_CIGAM) {
        const struct mach_header *mh = (const struct mach_header *)bytes;
        cpu_type_t type = (magic == MH_MAGIC)
                        ? mh->cputype : (cpu_type_t)OSSwapInt32(mh->cputype);
        return type == wanted;
    }

    if (magic == MH_MAGIC_64 || magic == MH_CIGAM_64) {
        const struct mach_header_64 *mh = (const struct mach_header_64 *)bytes;
        cpu_type_t type = (magic == MH_MAGIC_64)
                        ? mh->cputype : (cpu_type_t)OSSwapInt32(mh->cputype);
        return type == wanted;
    }

    return NO;
}

BOOL VLCCrystalHDDriverMatchesKernel(void)
{
    NSString *kext = BundledDriverPath();
    if (kext == nil)
        return NO;

    NSString *binary = [[kext stringByAppendingPathComponent:@"Contents/MacOS"]
                        stringByAppendingPathComponent:@"BroadcomCrystalHD"];

    return BinaryHasCPUType(binary, RunningKernelCPUType());
}

BOOL VLCCrystalHDBlockedBy64BitProcess(void)
{
    /* A 32-bit build can always talk to a 32-bit driver. */
    if (sizeof(void *) == 4)
        return NO;

    /* 64-bit process: only a 64-bit kernel can carry it through to the
     * driver. The kext matches the kernel, never the application. */
    return RunningKernelCPUType() == CPU_TYPE_I386;
}

BOOL VLCCrystalHDCanBoot32BitKernel(void)
{
    /* Darwin 11 is Mac OS X 10.7, the last release with a 32-bit kernel to
     * boot into; 10.8 shipped 64-bit only. */
    char release[64] = "";
    size_t len = sizeof(release);

    if (sysctlbyname("kern.osrelease", release, &len, NULL, 0) != 0)
        return NO;

    return atoi(release) <= 11;
}

/*****************************************************************************
 * State
 *****************************************************************************/
VLCCrystalHDState VLCCrystalHDGetState(void)
{
    BOOL card = CardIsPresent();
    BOOL driver = (InstalledDriverPath() != nil);

    if (card && driver)
        return VLCCrystalHDReady;
    if (card)
        return VLCCrystalHDCardWithoutDriver;
    if (driver)
        return VLCCrystalHDDriverWithoutCard;

    return VLCCrystalHDAbsent;
}

BOOL VLCCrystalHDStartupPromptSuppressed(void)
{
    return [[NSUserDefaults standardUserDefaults]
                boolForKey:CRYSTALHD_PROMPT_DEFAULT];
}

void VLCCrystalHDSuppressStartupPrompt(void)
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:YES forKey:CRYSTALHD_PROMPT_DEFAULT];
    [defaults synchronize];
}

/*****************************************************************************
 * Privileged execution
 *****************************************************************************
 * AuthorizationExecuteWithPrivileges has been deprecated since 10.7, but its
 * replacement (SMJobBless) arrived in 10.6 and needs a signed helper tool and
 * a launchd job -- neither of which exists on the 10.4/10.5 systems this
 * player still targets. One prompt, one script, no installed helper.
 *****************************************************************************/
/* Everything the privileged work needs, so that it can run away from the main
 * thread without touching a single Objective-C object. Plain C on purpose:
 * this file is compiled both under manual retain/release for the 10.4
 * interface and under ARC for the modern one, and the two disagree about what
 * a secondary thread owes an autorelease pool. */
typedef struct
{
    char *psz_script;
    char *psz_action;
    char *psz_argument;         /* NULL for actions that take none */

    OSStatus i_status;
    char *psz_output;           /* malloc'd, NUL terminated, may stay NULL */

    volatile int b_done;
} chd_helper_t;

static void HelperAppendOutput(chd_helper_t *p_helper, const char *p_bytes,
                               size_t i_bytes)
{
    size_t i_used = p_helper->psz_output ? strlen(p_helper->psz_output) : 0;
    char *p_grown = realloc(p_helper->psz_output, i_used + i_bytes + 1);

    if (p_grown == NULL)
        return;

    memcpy(p_grown + i_used, p_bytes, i_bytes);
    p_grown[i_used + i_bytes] = '\0';
    p_helper->psz_output = p_grown;
}

static void HelperRun(chd_helper_t *p_helper)
{
    /* Acquire the right here, in the application, instead of handing an empty
     * authorization to AuthorizationExecuteWithPrivileges and letting
     * /usr/libexec/security_authtrampoline ask for it. The trampoline is a
     * root-owned tool with no presence in the window server, and a password
     * panel raised on its behalf has no application to belong to. */
    AuthorizationItem right;
    right.name        = kAuthorizationRightExecute;
    right.valueLength = 0;
    right.value       = NULL;
    right.flags       = 0;

    AuthorizationRights rights = { 1, &right };
    AuthorizationFlags flags = kAuthorizationFlagDefaults
                             | kAuthorizationFlagInteractionAllowed
                             | kAuthorizationFlagPreAuthorize
                             | kAuthorizationFlagExtendRights;

    AuthorizationRef auth = NULL;
    p_helper->i_status = AuthorizationCreate(&rights,
                                             kAuthorizationEmptyEnvironment,
                                             flags, &auth);
    if (p_helper->i_status != errAuthorizationSuccess)
        return;

    /* Run through /bin/sh rather than executing the script directly, so this
     * does not depend on the executable bit surviving packaging.
     *
     * -p is not cosmetic. AuthorizationExecuteWithPrivileges runs the tool
     * through the trampoline, and on 10.4 that binary is merely setuid-root:
     * it imports no setuid at all, it just execs. The tool therefore starts
     * with the real uid still the user's and only the effective uid at 0 --
     * and a shell started that way throws the effective uid away unless -p is
     * given. The script then ran unprivileged and every write to
     * /System/Library/Extensions failed with EPERM, which the user saw as an
     * install that asked for a password and then refused to do anything.
     * Later systems raise both ids in the trampoline, hence 10.4 only. */
    char *args[5];
    int i = 0;
    args[i++] = (char *)"-p";
    args[i++] = p_helper->psz_script;
    args[i++] = p_helper->psz_action;
    if (p_helper->psz_argument != NULL)
        args[i++] = p_helper->psz_argument;
    args[i] = NULL;

    FILE *pipe = NULL;
#ifdef __clang__
# pragma clang diagnostic push
# pragma clang diagnostic ignored "-Wdeprecated-declarations"
#endif
    p_helper->i_status = AuthorizationExecuteWithPrivileges(
                                            auth, "/bin/sh",
                                            kAuthorizationFlagDefaults,
                                            args, &pipe);
#ifdef __clang__
# pragma clang diagnostic pop
#endif

    /* AuthorizationExecuteWithPrivileges does not report the child's exit
     * status, so the script prints a marker on success and the reason for the
     * failure otherwise; both are surfaced to the user. */
    if (p_helper->i_status == errAuthorizationSuccess && pipe != NULL) {
        char buffer[512];
        size_t got;

        while ((got = fread(buffer, 1, sizeof(buffer), pipe)) > 0)
            HelperAppendOutput(p_helper, buffer, got);
        fclose(pipe);
    }

    AuthorizationFree(auth, kAuthorizationFlagDefaults);
}

static void *HelperThread(void *p_opaque)
{
    chd_helper_t *p_helper = (chd_helper_t *)p_opaque;

    HelperRun(p_helper);
    p_helper->b_done = 1;
    return NULL;
}

static BOOL RunHelper(NSString *action, NSString *argument,
                      NSString *successMarker, NSString *failureMessage,
                      NSString **ppsz_error)
{
    NSString *script = HelperScriptPath();

    if (script == nil) {
        if (ppsz_error)
            *ppsz_error = @"The installer script is missing from the "
                           "application bundle.";
        return NO;
    }

    /* The run loop is turned below, so the menu that got us here is live
     * again and could get us here a second time. */
    static BOOL b_running = NO;
    if (b_running)
        return NO;

    chd_helper_t helper;
    memset(&helper, 0, sizeof(helper));
    helper.psz_script   = strdup([script fileSystemRepresentation]);
    helper.psz_action   = strdup([action UTF8String]);
    helper.psz_argument = (argument != nil)
                        ? strdup([argument fileSystemRepresentation]) : NULL;

    NSString *output = nil;
    pthread_t thread;

    if (helper.psz_script == NULL || helper.psz_action == NULL ||
        (argument != nil && helper.psz_argument == NULL) ||
        pthread_create(&thread, NULL, HelperThread, &helper) != 0) {
        free(helper.psz_script);
        free(helper.psz_action);
        free(helper.psz_argument);
        if (ppsz_error)
            *ppsz_error = @"Could not ask for administrator rights.";
        return NO;
    }

    /* ⚠ The password panel MUST NOT be raised from a blocked main thread.
     * SecurityAgent shows it system modally: it takes the whole session's
     * input, and it needs the application it is asking for to keep answering
     * the window server so its own panel can come forward and take the
     * keyboard. With the main thread stuck inside AuthorizationCreate the
     * panel was drawn and then nothing on the Mac answered the mouse or the
     * keyboard again -- only the pointer moved. Diagnosed on 10.5 on
     * 2026-08-05; 10.4 tolerated it, which is why it surfaced late. So the
     * privileged work runs on its own thread and the main thread does what it
     * would normally do: turn its run loop. */
    b_running = YES;
    while (!helper.b_done) {
        [[NSRunLoop currentRunLoop]
            runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }
    pthread_join(thread, NULL);
    b_running = NO;

    if (helper.psz_output != NULL)
        output = [NSString stringWithUTF8String:helper.psz_output];
    if (output == nil)
        output = @"";

    OSStatus st = helper.i_status;

    free(helper.psz_script);
    free(helper.psz_action);
    free(helper.psz_argument);
    free(helper.psz_output);

    if (st != errAuthorizationSuccess) {
        if (ppsz_error) {
            /* Dismissing the password panel is a normal answer, not a fault
             * worth an alarming message. */
            *ppsz_error = (st == errAuthorizationCanceled)
                        ? nil
                        : @"Administrator rights were refused.";
        }
        return NO;
    }

    if ([output rangeOfString:successMarker].location != NSNotFound)
        return YES;

    if (ppsz_error) {
        NSString *trimmed = [output stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        *ppsz_error = [trimmed length] > 0 ? trimmed : failureMessage;
    }
    return NO;
}

BOOL VLCCrystalHDInstallDriver(NSString **ppsz_error)
{
    NSString *kext = BundledDriverPath();

    if (kext == nil) {
        if (ppsz_error)
            *ppsz_error = @"This build does not ship the Crystal HD driver.";
        return NO;
    }

    return RunHelper(@"install", kext, @"installed:",
                     @"The driver could not be installed.", ppsz_error);
}

BOOL VLCCrystalHDUninstallDriver(NSString **ppsz_error)
{
    return RunHelper(@"uninstall", nil, @"removed",
                     @"The driver could not be removed.", ppsz_error);
}

BOOL VLCCrystalHDReloadDriver(NSString **ppsz_error)
{
    return RunHelper(@"reload", nil, @"reloaded:",
                     @"The driver could not be reloaded.", ppsz_error);
}

/*****************************************************************************
 * User-facing flows
 *****************************************************************************
 * NSRunAlertPanel rather than NSAlert: this file is shared with the legacy
 * interface, which runs as far back as systems where NSAlert either does not
 * exist or cannot be driven this simply.
 *****************************************************************************/
/* Named _NS, like the interfaces' own helper: it is one of the keywords in
 * po/Makevars, so xgettext actually sees these strings. A differently named
 * macro would make every one of them invisible to extraction. */
#define _NS(s) [NSString stringWithUTF8String:vlc_gettext(s)]

/* Explain the one case where installing cannot help: the driver is 32-bit and
 * a kext must match the running kernel, not the CPU. Returns YES when the
 * caller should stop. */
static BOOL WarnIfKernelMismatch(void)
{
    if (VLCCrystalHDDriverMatchesKernel())
        return NO;

    if (VLCCrystalHDCanBoot32BitKernel())
        NSRunAlertPanel(_NS("Crystal HD acceleration"),
            _NS("The bundled driver is 32-bit only, and this Mac is "
                   "running a 64-bit kernel.\n\nRestart while holding the 3 "
                   "and 2 keys to start a 32-bit kernel, then install the "
                   "driver."),
            _NS("OK"), nil, nil);
    else
        NSRunAlertPanel(_NS("Crystal HD acceleration"),
            _NS("The bundled driver is 32-bit only, and this version of "
                   "macOS runs a 64-bit kernel exclusively.\n\nThe card "
                   "cannot be used until a 64-bit driver is available."),
            _NS("OK"), nil, nil);

    return YES;
}

static void ReportOutcome(BOOL b_ok, NSString *psz_error, NSString *psz_success)
{
    if (b_ok) {
        NSRunAlertPanel(_NS("Crystal HD acceleration"), @"%@",
                        _NS("OK"), nil, nil, psz_success);
        return;
    }

    /* A cancelled password prompt leaves no error and deserves no alert. */
    if (psz_error == nil)
        return;

    NSRunAlertPanel(_NS("Crystal HD acceleration"), @"%@",
                    _NS("OK"), nil, nil, psz_error);
}

BOOL VLCCrystalHDRunInstallFlow(BOOL b_offerSuppress)
{
    if (WarnIfKernelMismatch())
        return NO;

    /* long, not NSInteger: that type only exists from the 10.5 SDK on, and
     * the legacy interface keeps its own shim in a header this file must not
     * depend on. Both int and NSInteger widen to long without loss. */
    long choice =
        NSRunAlertPanel(_NS("Crystal HD acceleration"),
            _NS("PowerVLC found a Crystal HD card in this Mac. The card "
                   "can decode H.264, VC-1 and MPEG-2 video in hardware, "
                   "which this Mac cannot do on its own.\n\nUsing it needs a "
                   "driver, which PowerVLC can install for you. You will be "
                   "asked for an administrator password."),
            _NS("Install"),
            b_offerSuppress ? _NS("Don't Ask Again") : nil,
            _NS("Not Now"));

    if (b_offerSuppress && choice == NSAlertAlternateReturn) {
        VLCCrystalHDSuppressStartupPrompt();
        return NO;
    }

    if (choice != NSAlertDefaultReturn)
        return NO;

    NSString *error = nil;
    BOOL b_ok = VLCCrystalHDInstallDriver(&error);

    ReportOutcome(b_ok, error,
        _NS("The Crystal HD driver is installed. Hardware acceleration "
               "will be used for video that the card supports."));
    return b_ok;
}

BOOL VLCCrystalHDRunUninstallFlow(void)
{
    long choice =
        NSRunAlertPanel(_NS("Crystal HD acceleration"),
            _NS("Remove the Crystal HD driver from this Mac?\n\nVideo will "
                   "be decoded by the processor again. You will be asked for "
                   "an administrator password."),
            _NS("Remove"), nil, _NS("Cancel"));

    if (choice != NSAlertDefaultReturn)
        return NO;

    NSString *error = nil;
    BOOL b_ok = VLCCrystalHDUninstallDriver(&error);

    ReportOutcome(b_ok, error,
                  _NS("The Crystal HD driver has been removed."));
    return b_ok;
}

/* An abnormal exit can leave the card refusing every open while the driver
 * looks perfectly healthy -- the service is there, idle, with no client, and
 * DtsDeviceOpen still fails, even as root. Playback then falls back to
 * software, which is correct but slow, and nothing short of taking the driver
 * out and putting it back clears it. This is that, in one click, instead of a
 * Terminal session. Measured on a BCM70015, 05/08/2026. */
BOOL VLCCrystalHDRunReloadFlow(void)
{
    long choice =
        NSRunAlertPanel(_NS("Crystal HD acceleration"),
            _NS("Reload the Crystal HD driver?\n\nUse this when video has "
                   "started being decoded by the processor although the card "
                   "is installed. Nothing playing may be using the card, and "
                   "you will be asked for an administrator password."),
            _NS("Reload"), nil, _NS("Cancel"));

    if (choice != NSAlertDefaultReturn)
        return NO;

    NSString *error = nil;
    BOOL b_ok = VLCCrystalHDReloadDriver(&error);

    ReportOutcome(b_ok, error,
                  _NS("The Crystal HD driver has been reloaded."));
    return b_ok;
}

void VLCCrystalHDMaybePromptAtStartup(void)
{
    VLCCrystalHDState state = VLCCrystalHDGetState();

    if (state == VLCCrystalHDAbsent || VLCCrystalHDStartupPromptSuppressed())
        return;

    /* Card present but out of reach because this process is 64-bit on a
     * 32-bit kernel. Say so: installing the driver would change nothing, and
     * the user has a way out. */
    if (VLCCrystalHDBlockedBy64BitProcess()) {
        long choice = NSRunAlertPanel(_NS("Crystal HD acceleration"),
            _NS("This Mac has a Crystal HD card, but PowerVLC is running "
                   "in 64-bit mode and the card's driver is 32-bit -- this "
                   "Mac's graphics chip has no 64-bit driver, so it always "
                   "starts a 32-bit system.\n\nTo use the card, quit "
                   "PowerVLC, select it in the Finder, choose File > Get "
                   "Info and tick \"Open in 32-bit mode\"."),
            _NS("OK"), _NS("Don't Ask Again"), nil);

        if (choice == NSAlertAlternateReturn)
            VLCCrystalHDSuppressStartupPrompt();
        return;
    }

    if (state != VLCCrystalHDCardWithoutDriver)
        return;

    VLCCrystalHDRunInstallFlow(YES);
}

/*****************************************************************************
 * ⚠ ANCRE OBJECTIVE-C — NE PAS SUPPRIMER (Mac OS X 10.2)
 *****************************************************************************
 * Ce fichier utilise Objective-C (Foundation) mais ne DÉFINISSAIT aucune
 * classe. Un tel module laisse `module->symtab` à NULL, et l'`_objcInit()` de
 * 10.2 le déréférence : le processus meurt au `dlopen` du greffon qui le
 * contient, SANS une ligne de journal — le greffon d'interface legacy, donc
 * l'unique fournisseur de fenêtre vidéo, d'où « no vout window modules » et
 * zéro image décodée. Diagnostiqué sur l'iBook G3 Jaguar le 2026-08-05.
 * Une classe vide suffit à peupler le symtab. L'autre remède (compiler en .c)
 * ne s'applique PAS ici : les en-têtes AppKit/Foundation exigent Objective-C.
 * Contrôlé par extras/package/macosx/check-objc-modules.sh, que build.sh
 * exécute sur les cibles 10.0-10.2.
 *****************************************************************************/
@interface VLCCrystalHDObjCAnchor : NSObject
@end
@implementation VLCCrystalHDObjCAnchor
@end
