/*****************************************************************************
 * VLCLegacyOpen.m: open dialogs for the legacy Mac OS X interface
 *****************************************************************************
 * Copyright © 2026 VLC authors and VideoLAN
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
# import "config.h"
#endif

#import "VLCLegacyOpen.h"
#import "misc.h"
#import "VLCLegacyOutput.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyMenu.h"

#include <vlc_playlist.h>
#include <vlc_input_item.h>
#include <vlc_url.h>
#include <vlc_configuration.h>
#include <vlc_plugin.h>    /* CONFIG_ITEM_* */

#include <sys/param.h>
#include <sys/mount.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/IOBSD.h>
#include <IOKit/storage/IOCDMedia.h>
#include <IOKit/storage/IODVDMedia.h>
#include <sys/ucred.h>
#if !defined(MAC_OS_X_VERSION_MAX_ALLOWED) || MAC_OS_X_VERSION_MAX_ALLOWED >= 1050
/* Blu-ray media class, absent from the 10.4 SDK */
# include <IOKit/storage/IOBDMedia.h>
#endif
#include <ApplicationServices/ApplicationServices.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/* media kinds, as detected by -[VLCStringUtility getVolumeTypeFromMountPath:] */
static NSString *const kVLCMediaAudioCD = @"AudioCD";
static NSString *const kVLCMediaDVD = @"DVD";
static NSString *const kVLCMediaVCD = @"VCD";
static NSString *const kVLCMediaSVCD = @"SVCD";
static NSString *const kVLCMediaBD = @"Blu-ray";
static NSString *const kVLCMediaVideoTSFolder = @"VIDEO_TS";
static NSString *const kVLCMediaBDMVFolder = @"BDMV";
static NSString *const kVLCMediaUnknown = @"Unknown";

/*****************************************************************************
 * volume inspection, 10.4-safe stand-ins for the VLCStringUtility helpers
 * (statfs + IOKit instead of FSGetVolumeParms, which is 10.5+)
 *****************************************************************************/

static NSString *bsdNameForMountPath(NSString *mountPath)
{
    struct statfs stat;
    if (statfs([mountPath fileSystemRepresentation], &stat) != 0)
        return nil;
    const char *node = stat.f_mntfromname;
    if (!strncmp(node, "/dev/", 5))
        node += 5;
    if (!*node)
        return nil;
    return [NSString stringWithUTF8String:node];
}

static NSString *bsdNodeForMountPath(NSString *mountPath)
{
    NSString *bsdName = bsdNameForMountPath(mountPath);
    if (!bsdName)
        return @"";
    return [NSString stringWithFormat:@"/dev/r%@", bsdName];
}

/*
 * Optical media the OS holds but could not mount.
 *
 * Mac OS X 10.4 has no Blu-ray storage family, so a BD-ROM is published as
 * IOCDMedia with a 2352 byte block size: nothing mounts it, and
 * -mountedRemovableMedia therefore never lists it. Without this the disc simply
 * does not appear under "Open Disc" on Tiger, even though the player can read
 * it perfectly well over MMC (see modules/access/bluray_darwin_mmc.c).
 *
 * The rule is deliberately narrow -- an optical drive, holding whole ejectable
 * media, bigger than any DVD, that nothing has mounted. CDs and DVDs mount fine
 * and are picked up the usual way, so they never reach this.
 */
#define MIN_UNMOUNTED_OPTICAL_SIZE (10ULL * 1000 * 1000 * 1000)

/* kGenericCDROMIcon, spelled out so this file does not have to pull in Carbon
 * for a single OSType. -iconForFileType:@"public.disc" looks like the modern
 * spelling but answers a blank image on 10.4, where UTIs are not yet what
 * NSWorkspace resolves icons by. */
#define VLC_GENERIC_CDROM_ICON 0x63646472 /* 'cddr' */

static NSImage *opticalDiscIcon(void)
{
    return [[NSWorkspace sharedWorkspace]
        iconForFileType:NSFileTypeForHFSTypeCode(VLC_GENERIC_CDROM_ICON)];
}

/* "PIONEER BD-RW BDR-XS07U" rather than "disk1". The strings come from the
 * drive's INQUIRY data, which IOKit exposes under Device Characteristics on the
 * SCSI nub -- hence the search through the parents. */
static NSString *opticalDriveName(io_service_t service)
{
    CFDictionaryRef chars = IORegistryEntrySearchCFProperty(service,
        kIOServicePlane, CFSTR("Device Characteristics"), kCFAllocatorDefault,
        kIORegistryIterateRecursively);
    if (chars == NULL)
        return nil;

    NSString *name = nil;
    if (CFGetTypeID(chars) == CFDictionaryGetTypeID()) {
        NSDictionary *dict = (NSDictionary *)chars;
        NSString *vendor  = [dict objectForKey:@"Vendor Name"];
        NSString *product = [dict objectForKey:@"Product Name"];
        /* Index loops, not fast enumeration: "for (x in y)" needs
         * objc_enumerationMutation(), which the Mac OS X 10.4 Objective-C
         * runtime does not have -- it links but fails at 10.5+ only. */
        NSMutableArray *words = [NSMutableArray array];
        NSArray *parts = [NSArray arrayWithObjects:vendor, product, nil];
        unsigned p, w;
        for (p = 0; p < [parts count]; p++) {
            NSString *part = [parts objectAtIndex:p];
            if (![part isKindOfClass:[NSString class]])
                continue;
            /* the INQUIRY fields are blank-padded, so squeeze runs of spaces */
            NSArray *bits = [part componentsSeparatedByString:@" "];
            for (w = 0; w < [bits count]; w++) {
                NSString *bit = [bits objectAtIndex:w];
                if ([bit length] > 0)
                    [words addObject:bit];
            }
        }
        if ([words count] > 0)
            name = [words componentsJoinedByString:@" "];
    }
    CFRelease(chars);
    return name;
}

static BOOL bsdNameIsMounted(const char *bsdName)
{
    char node[MAXPATHLEN];
    snprintf(node, sizeof(node), "/dev/%s", bsdName);

    int count = getfsstat(NULL, 0, MNT_NOWAIT);
    if (count <= 0)
        return NO;

    struct statfs *buf = malloc(count * sizeof(*buf));
    if (!buf)
        return NO;

    count = getfsstat(buf, (int)(count * sizeof(*buf)), MNT_NOWAIT);
    BOOL mounted = NO;
    for (int i = 0; i < count && !mounted; i++)
        mounted = !strcmp(buf[i].f_mntfromname, node);

    free(buf);
    return mounted;
}

static NSArray *unmountedOpticalDevices(void)
{
    static const char *const classes[] = { "IOBDServices", "IODVDServices" };
    NSMutableArray *found = [NSMutableArray array];

    for (size_t c = 0; c < sizeof(classes) / sizeof(classes[0]); c++) {
        io_iterator_t it = 0;
        if (IOServiceGetMatchingServices(kIOMasterPortDefault,
                                         IOServiceMatching(classes[c]),
                                         &it) != KERN_SUCCESS)
            continue;

        io_service_t service;
        while ((service = IOIteratorNext(it)) != 0) {
            CFStringRef bsd = IORegistryEntrySearchCFProperty(service,
                kIOServicePlane, CFSTR(kIOBSDNameKey), kCFAllocatorDefault,
                kIORegistryIterateRecursively);
            CFNumberRef size = IORegistryEntrySearchCFProperty(service,
                kIOServicePlane, CFSTR("Size"), kCFAllocatorDefault,
                kIORegistryIterateRecursively);

            char name[128] = "";
            long long bytes = 0;
            if (bsd && CFStringGetCString(bsd, name, sizeof(name),
                                          kCFStringEncodingASCII)
             && size && CFNumberGetValue(size, kCFNumberLongLongType, &bytes)
             && (unsigned long long)bytes >= MIN_UNMOUNTED_OPTICAL_SIZE
             && !bsdNameIsMounted(name)) {
                NSString *path = [NSString stringWithFormat:@"/dev/%s", name];
                NSString *label = opticalDriveName(service);
                if (label == nil)
                    label = kVLCMediaBD;
                [found addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                    path, @"path", path, @"devicePath",
                    kVLCMediaBD, @"mediaType", label, @"displayName",
                    opticalDiscIcon(), @"image", nil]];
            }

            if (bsd)
                CFRelease(bsd);
            if (size)
                CFRelease(size);
            IOObjectRelease(service);
        }
        IOObjectRelease(it);
    }

    return found;
}

static NSString *volumeTypeForMountPath(NSString *mountPath)
{
    NSString *bsdName = bsdNameForMountPath(mountPath);
    if (bsdName) {
        CFMutableDictionaryRef matchingDict =
            IOBSDNameMatching(kIOMasterPortDefault, 0, [bsdName UTF8String]);
        io_service_t service =
            IOServiceGetMatchingService(kIOMasterPortDefault, matchingDict);
        if (service != IO_OBJECT_NULL) {
            NSString *result = nil;
            if (IOObjectConformsTo(service, kIOCDMediaClass))
                result = kVLCMediaAudioCD;
            else if (IOObjectConformsTo(service, kIODVDMediaClass))
                result = kVLCMediaDVD;
#ifdef kIOBDMediaClass
            else if (IOObjectConformsTo(service, kIOBDMediaClass))
                result = kVLCMediaBD;
#endif
            IOObjectRelease(service);
            if (result)
                return result;
        }
    }

    if ([mountPath rangeOfString:@"VIDEO_TS"
                         options:NSCaseInsensitiveSearch
                               | NSBackwardsSearch].location != NSNotFound)
        return kVLCMediaVideoTSFolder;
    if ([mountPath rangeOfString:@"BDMV"
                         options:NSCaseInsensitiveSearch
                               | NSBackwardsSearch].location != NSNotFound)
        return kVLCMediaBDMVFolder;

    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *dirContents = [fm directoryContentsAtPath:mountPath];
    unsigned i;
    for (i = 0; i < [dirContents count]; i++) {
        NSString *currentFile = [dirContents objectAtIndex:i];
        NSString *fullPath =
            [mountPath stringByAppendingPathComponent:currentFile];
        BOOL isDir;
        if ([fm fileExistsAtPath:fullPath isDirectory:&isDir] && isDir) {
            if ([currentFile caseInsensitiveCompare:@"SVCD"]
                    == NSOrderedSame)
                return kVLCMediaSVCD;
            if ([currentFile caseInsensitiveCompare:@"VCD"]
                    == NSOrderedSame)
                return kVLCMediaVCD;
            if ([currentFile caseInsensitiveCompare:@"BDMV"]
                    == NSOrderedSame)
                return kVLCMediaBDMVFolder;
            if ([currentFile caseInsensitiveCompare:@"VIDEO_TS"]
                    == NSOrderedSame)
                return kVLCMediaVideoTSFolder;
        }
    }
    return kVLCMediaUnknown;
}

@implementation VLCLegacyOpen

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
{
    if (self = [super init]) {
        core = [interaction retain];
        p_intf = [interaction intf];
        output = [[VLCLegacyOutput alloc] initWithIntf:p_intf];
        allMediaDevices = [[NSMutableArray alloc] init];
        specialMediaFolders = [[NSMutableArray alloc] init];
        displayIDs = [[NSMutableArray alloc] init];
        mrl = [@"" retain];
    }
    return self;
}

- (void)dealloc
{
    [[[NSWorkspace sharedWorkspace] notificationCenter]
        removeObserver:self];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [window release];
    [netUDPPanel release];
    [fileSubSheet release];
    [discNoDiscView release];
    [discAudioCDView release];
    [discDVDView release];
    [discDVDwomenusView release];
    [discVCDView release];
    [discBDView release];
    [allMediaDevices release];
    [specialMediaFolders release];
    [displayIDs release];
    [filePath release];
    [fileSlavePath release];
    [subPath release];
    [mrl release];
    [output release];
    [core release];
    [super dealloc];
}

/*****************************************************************************
 * control helpers
 *****************************************************************************/

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame
                    in:(NSView *)parent
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame]
        autorelease];
    [label setEditable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [[label cell] setFont:[NSFont systemFontOfSize:11]];
    [label setStringValue:text];
    [parent addSubview:label];
    return label;
}

- (NSTextField *)field:(NSRect)frame in:(NSView *)parent
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame]
        autorelease];
    [[field cell] setFont:[NSFont systemFontOfSize:11]];
    [[field cell] setControlSize:NSSmallControlSize];
    /* long input scrolls on one line instead of wrapping */
    [[field cell] setWraps:NO];
    [[field cell] setScrollable:YES];
    [parent addSubview:field];
    return field;
}

- (NSButton *)button:(NSString *)title action:(SEL)action
               frame:(NSRect)frame in:(NSView *)parent
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [[button cell] setControlSize:NSSmallControlSize];
    [button setFont:[NSFont systemFontOfSize:11]];
    [button setTarget:self];
    [button setAction:action];
    [parent addSubview:button];
    return button;
}

- (NSButton *)checkbox:(NSString *)title frame:(NSRect)frame
                action:(SEL)action in:(NSView *)parent
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setButtonType:NSSwitchButton];
    [button setTitle:title];
    [[button cell] setFont:[NSFont systemFontOfSize:11]];
    [[button cell] setControlSize:NSSmallControlSize];
    [button setTarget:self];
    [button setAction:action];
    [parent addSubview:button];
    return button;
}

- (NSPopUpButton *)popup:(NSRect)frame action:(SEL)action in:(NSView *)parent
{
    NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame:frame
                                                       pullsDown:NO]
        autorelease];
    [[popup cell] setControlSize:NSSmallControlSize];
    [popup setFont:[NSFont systemFontOfSize:11]];
    [popup setTarget:self];
    [popup setAction:action];
    [parent addSubview:popup];
    return popup;
}

- (NSStepper *)stepper:(NSRect)frame min:(int)min max:(int)max
                action:(SEL)action in:(NSView *)parent
{
    NSStepper *stepper = [[[NSStepper alloc] initWithFrame:frame]
        autorelease];
    [stepper setMinValue:min];
    [stepper setMaxValue:max];
    [stepper setTarget:self];
    [stepper setAction:action];
    [parent addSubview:stepper];
    return stepper;
}

- (NSImageView *)iconWell:(NSRect)frame in:(NSView *)parent
{
    NSImageView *well = [[[NSImageView alloc] initWithFrame:frame]
        autorelease];
    [well setEditable:NO];
    /* -unregisterDraggedTypes is 10.3; below it, a view that never
     * registered a type has nothing to unregister anyway */
    if ([well respondsToSelector:@selector(unregisterDraggedTypes)])
        [well unregisterDraggedTypes];
    [parent addSubview:well];
    return well;
}

/*****************************************************************************
 * MRL plumbing (VLCOpenWindowController setMRL:)
 *****************************************************************************/

- (void)setMRL:(NSString *)newMRL
{
    if (!newMRL)
        newMRL = @"";
    NSString *trimmed = [newMRL stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    [mrl release];
    mrl = [trimmed retain];
    [mrlField setStringValue:mrl];
    [okButton setEnabled:[mrl length] > 0];
}

- (void)addMRL:(NSString *)theMrl options:(NSArray *)options
{
    int i_options = (int)[options count];
    const char **ppsz_options = NULL;
    if (i_options > 0) {
        ppsz_options = malloc(i_options * sizeof (*ppsz_options));
        if (ppsz_options == NULL)
            i_options = 0;
        int i;
        for (i = 0; i < i_options; i++)
            ppsz_options[i] = [[options objectAtIndex:i] UTF8String];
    }
    playlist_AddExt(pl_Get(p_intf), [theMrl UTF8String], NULL, true,
                    i_options, (const char *const *)ppsz_options,
                    VLC_INPUT_OPTION_TRUSTED, true);
    free(ppsz_options);
    VLCLegacyNoteRecentItem(theMrl);
}

/*****************************************************************************
 * plain file panel (menu "Open File...", 3.0 behavior)
 *****************************************************************************/

- (void)openFile
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:YES];
    [panel setTitle:_NS("Open File")];
    [panel setPrompt:_NS("Open")];
    if ([panel runModal] != NSOKButton)
        return;

    playlist_t *p_playlist = pl_Get(p_intf);
    NSArray *urls = [panel URLs];
    unsigned count = (unsigned)[urls count];
    unsigned i;
    for (i = 0; i < count; i++) {
        char *psz_uri =
            vlc_path2uri([[[urls objectAtIndex:i] path] UTF8String], "file");
        if (!psz_uri)
            continue;
        playlist_Add(p_playlist, psz_uri, i == 0);
        VLCLegacyNoteRecentItem([NSString stringWithUTF8String:psz_uri]);
        free(psz_uri);
    }
}

- (void)openSubtitleFile
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setAllowsMultipleSelection:NO];
    if ([panel runModal] != NSOKButton)
        return;
    [core addSubtitleFileToCurrentInput:
        [[[panel URLs] objectAtIndex:0] path]];
}

/*****************************************************************************
 * file pane
 *****************************************************************************/

/* The application icon with ALL its representations. On old AppKit,
 * -[NSApp applicationIconImage] only carries a small rep, which looks
 * terrible scaled up to the 128 px disc pane icon. */
- (NSImage *)applicationIconImage
{
    NSString *path = [[NSBundle mainBundle] pathForResource:@"VLC"
                                                     ofType:@"icns"];
    if (path) {
        NSImage *icon = [[[NSImage alloc] initWithContentsOfFile:path]
            autorelease];
        if (icon)
            return icon;
    }
    return [NSApp applicationIconImage];
}

/* the 3.0 placeholder icon (File-Icons/generic.icns) */
- (NSImage *)genericFileIcon
{
    NSImage *icon = [NSImage imageNamed:@"generic"];
    if (!icon)
        icon = [[NSWorkspace sharedWorkspace] iconForFileType:@""];
    return icon;
}

- (NSView *)buildFilePane
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 562, 300)] autorelease];

    fileIconWell = [self iconWell:NSMakeRect(16, 236, 48, 48) in:pane];
    [fileIconWell setImage:[self genericFileIcon]];
    fileNameStubLabel = [self label:_NS("Choose a file")
                              frame:NSMakeRect(76, 252, 330, 17) in:pane];
    [[fileNameStubLabel cell] setFont:[NSFont systemFontOfSize:13]];
    fileNameLabel = [self label:@"" frame:NSMakeRect(76, 252, 330, 17)
                             in:pane];
    [[fileNameLabel cell] setFont:[NSFont systemFontOfSize:13]];
    [self button:_NS("Browse...") action:@selector(openFileBrowse:)
           frame:NSMakeRect(446, 246, 100, 28) in:pane];
    fileTreatAsPipeButton =
        [self checkbox:_NS("Treat as a pipe rather than as a file")
                 frame:NSMakeRect(76, 228, 360, 18)
                action:@selector(openFileStreamChanged:) in:pane];
    VLCLegacySetViewHidden(fileTreatAsPipeButton, YES);

    fileSlaveCheckbox =
        [self checkbox:_NS("Play another media synchronously")
                 frame:NSMakeRect(16, 192, 426, 18)
                action:@selector(inputSlaveAction:) in:pane];
    fileSlaveIconWell = [self iconWell:NSMakeRect(36, 156, 24, 24) in:pane];
    fileSlaveFilenameLabel = [self label:@""
                                   frame:NSMakeRect(68, 160, 330, 16)
                                      in:pane];
    fileSelectSlaveButton = [self button:_NS("Choose...")
                                  action:@selector(inputSlaveAction:)
                                   frame:NSMakeRect(446, 152, 100, 28)
                                      in:pane];
    [fileSelectSlaveButton setEnabled:NO];

    fileSubCheckbox = [self checkbox:_NS("Add Subtitle File:")
                               frame:NSMakeRect(16, 122, 400, 18)
                              action:@selector(subsChanged:) in:pane];
    fileSubtitlesIconWell = [self iconWell:NSMakeRect(36, 86, 24, 24)
                                        in:pane];
    fileSubtitlesFilenameLabel = [self label:@""
                                       frame:NSMakeRect(68, 90, 330, 16)
                                          in:pane];
    fileSubSettingsButton = [self button:_NS("Choose...")
                                  action:@selector(subFileSettings:)
                                   frame:NSMakeRect(446, 82, 100, 28)
                                      in:pane];
    [fileSubSettingsButton setEnabled:NO];

    fileCustomTimingCheckbox = [self checkbox:_NS("Custom playback")
                                        frame:NSMakeRect(16, 46, 166, 18)
                                       action:@selector(fileTimeCustomization:)
                                           in:pane];
    fileStartTimeLabel = [self label:_NS("Start time")
                               frame:NSMakeRect(186, 48, 94, 14) in:pane];
    fileStartTimeField = [self field:NSMakeRect(282, 44, 64, 20) in:pane];
    fileStopTimeLabel = [self label:_NS("Stop time")
                              frame:NSMakeRect(354, 48, 94, 14) in:pane];
    fileStopTimeField = [self field:NSMakeRect(450, 44, 64, 20) in:pane];
    [fileStartTimeLabel setTextColor:[NSColor disabledControlTextColor]];
    [fileStopTimeLabel setTextColor:[NSColor disabledControlTextColor]];
    [fileStartTimeField setEnabled:NO];
    [fileStopTimeField setEnabled:NO];

    return pane;
}

- (void)openFilePathChanged:(id)sender
{
    if (filePath && [filePath length] > 0) {
        BOOL b_stream = [fileTreatAsPipeButton state];
        BOOL b_dir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:filePath
                                             isDirectory:&b_dir];

        char *psz_uri = vlc_path2uri([filePath UTF8String], "file");
        if (!psz_uri)
            return;
        NSMutableString *mrlString =
            [NSMutableString stringWithUTF8String:psz_uri];
        NSRange offile = [mrlString rangeOfString:@"file"];
        free(psz_uri);

        if (b_dir)
            [mrlString replaceCharactersInRange:offile
                                     withString:@"directory"];
        else if (b_stream)
            [mrlString replaceCharactersInRange:offile withString:@"stream"];

        [fileNameLabel setStringValue:
            [[NSFileManager defaultManager] displayNameAtPath:filePath]];
        VLCLegacySetViewHidden(fileNameStubLabel, YES);
        VLCLegacySetViewHidden(fileTreatAsPipeButton, NO);
        [fileIconWell setImage:
            [[NSWorkspace sharedWorkspace] iconForFile:filePath]];
        VLCLegacySetViewHidden(fileIconWell, NO);
        [self setMRL:mrlString];
    } else {
        [fileNameLabel setStringValue:@""];
        VLCLegacySetViewHidden(fileNameStubLabel, NO);
        VLCLegacySetViewHidden(fileTreatAsPipeButton, YES);
        [fileIconWell setImage:[self genericFileIcon]];
        [self setMRL:@""];
    }
}

- (void)openFileBrowse:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:YES];
    [panel setTitle:_NS("Open File")];
    [panel setPrompt:_NS("Open")];
    if ([panel runModal] == NSOKButton) {
        [filePath release];
        filePath = [[[[panel URLs] objectAtIndex:0] path] retain];
        [self openFilePathChanged:nil];
    }
}

- (void)openFileStreamChanged:(id)sender
{
    [self openFilePathChanged:nil];
}

- (void)inputSlaveAction:(id)sender
{
    if (sender == fileSlaveCheckbox)
        [fileSelectSlaveButton setEnabled:[fileSlaveCheckbox state]];
    else {
        NSOpenPanel *panel = [NSOpenPanel openPanel];
        [panel setCanChooseFiles:YES];
        [panel setCanChooseDirectories:NO];
        if ([panel runModal] == NSOKButton) {
            [fileSlavePath release];
            fileSlavePath = [[[[panel URLs] objectAtIndex:0] path] retain];
        }
    }
    if (fileSlavePath && [fileSlaveCheckbox state] == NSOnState) {
        [fileSlaveFilenameLabel setStringValue:
            [[NSFileManager defaultManager]
                displayNameAtPath:fileSlavePath]];
        [fileSlaveIconWell setImage:
            [[NSWorkspace sharedWorkspace] iconForFile:fileSlavePath]];
    } else {
        [fileSlaveFilenameLabel setStringValue:@""];
        [fileSlaveIconWell setImage:nil];
    }
}

- (void)fileTimeCustomization:(id)sender
{
    BOOL b_value = [fileCustomTimingCheckbox state];
    [fileStartTimeField setEnabled:b_value];
    [fileStopTimeField setEnabled:b_value];
    [fileStartTimeLabel setTextColor:b_value
        ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]];
    [fileStopTimeLabel setTextColor:b_value
        ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]];
}

/*****************************************************************************
 * subtitle settings sheet ("Choose..." next to "Add Subtitle File:")
 *****************************************************************************/

- (void)addChoicesOf:(const char *)name to:(NSPopUpButton *)popup
        selectActual:(BOOL)selectActual
{
    module_config_t *p_item = config_FindConfig(name);
    if (!p_item)
        return;
    int i;
    for (i = 0; i < (int)p_item->list_count; i++) {
        if (p_item->list_text && p_item->list_text[i])
            [popup addItemWithTitle:_NS(p_item->list_text[i])];
        else
            [popup addItemWithTitle:[NSString stringWithFormat:@"%d",
                (int)p_item->list.i[i]]];
    }
    if (!selectActual)
        return;
    /* preselect the configured value */
    if (p_item->i_type == CONFIG_ITEM_STRING && p_item->value.psz) {
        for (i = 0; i < (int)p_item->list_count; i++)
            if (p_item->list.psz[i]
             && !strcmp(p_item->value.psz, p_item->list.psz[i])) {
                [popup selectItemAtIndex:i];
                break;
            }
    } else if (p_item->i_type == CONFIG_ITEM_INTEGER) {
        for (i = 0; i < (int)p_item->list_count; i++)
            if (p_item->value.i == p_item->list.i[i]) {
                [popup selectItemAtIndex:i];
                break;
            }
    }
}

- (void)buildSubSheet
{
    fileSubSheet = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 420, 380)
                  styleMask:NSTitledWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    NSView *content = [fileSubSheet contentView];

    NSBox *fileBox = [[[NSBox alloc]
        initWithFrame:NSMakeRect(16, 232, 388, 132)] autorelease];
    [fileBox setTitle:_NS("Subtitle File")];
    [[fileBox titleCell] setFont:[NSFont systemFontOfSize:11]];
    [content addSubview:fileBox];
    NSView *fileInner = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 364, 98)] autorelease];
    [fileBox setContentView:fileInner];

    fileSubPathField = [self field:NSMakeRect(8, 70, 250, 19) in:fileInner];
    [fileSubPathField setEditable:NO];
    [self button:_NS("Browse...") action:@selector(subFileBrowse:)
           frame:NSMakeRect(262, 64, 96, 28) in:fileInner];
    fileSubOverrideCheckbox = [self checkbox:_NS("Override parameters")
                                       frame:NSMakeRect(8, 40, 200, 18)
                                      action:@selector(subOverride:)
                                          in:fileInner];
    [self label:_NS("Delay") frame:NSMakeRect(8, 12, 60, 14) in:fileInner];
    fileSubDelayField = [self field:NSMakeRect(70, 8, 60, 20) in:fileInner];
    [fileSubDelayField setIntValue:0];
    [fileSubDelayField setEnabled:NO];
    fileSubDelayStepper = [self stepper:NSMakeRect(134, 4, 19, 27)
                                    min:-1000 max:1000
                                 action:@selector(subDelayStepper:)
                                     in:fileInner];
    [fileSubDelayStepper setEnabled:NO];
    [self label:_NS("FPS") frame:NSMakeRect(180, 12, 40, 14) in:fileInner];
    fileSubFPSField = [self field:NSMakeRect(222, 8, 60, 20) in:fileInner];
    [fileSubFPSField setFloatValue:1.0];
    [fileSubFPSField setEnabled:NO];
    fileSubFPSStepper = [self stepper:NSMakeRect(286, 4, 19, 27)
                                  min:0 max:1000
                               action:@selector(subFPSStepper:)
                                   in:fileInner];
    [fileSubFPSStepper setIntValue:1];
    [fileSubFPSStepper setEnabled:NO];

    NSBox *fontBox = [[[NSBox alloc]
        initWithFrame:NSMakeRect(16, 64, 388, 156)] autorelease];
    [fontBox setTitle:_NS("Font Properties")];
    [[fontBox titleCell] setFont:[NSFont systemFontOfSize:11]];
    [content addSubview:fontBox];
    NSView *fontInner = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 364, 122)] autorelease];
    [fontBox setContentView:fontInner];

    [self label:_NS("Subtitle encoding") frame:NSMakeRect(8, 94, 150, 14)
             in:fontInner];
    fileSubEncodingPopup = [self popup:NSMakeRect(160, 88, 196, 22)
                                action:nil in:fontInner];
    {
        module_config_t *p_item = config_FindConfig("subsdec-encoding");
        if (p_item) {
            int i;
            for (i = 0; i < (int)p_item->list_count; i++) {
                [fileSubEncodingPopup addItemWithTitle:
                    _NS(p_item->list_text[i])];
                [[fileSubEncodingPopup lastItem] setRepresentedObject:
                    [NSString stringWithFormat:@"%s", p_item->list.psz[i]]];
                if (p_item->value.psz
                 && !strcmp(p_item->value.psz, p_item->list.psz[i]))
                    [fileSubEncodingPopup selectItem:
                        [fileSubEncodingPopup lastItem]];
            }
            if ([fileSubEncodingPopup indexOfSelectedItem] < 0)
                [fileSubEncodingPopup selectItemAtIndex:0];
        }
    }
    [self label:_NS("Font size") frame:NSMakeRect(8, 62, 150, 14)
             in:fontInner];
    fileSubSizePopup = [self popup:NSMakeRect(160, 56, 196, 22)
                            action:nil in:fontInner];
    [self addChoicesOf:"freetype-rel-fontsize" to:fileSubSizePopup
          selectActual:YES];
    [self label:_NS("Subtitle alignment") frame:NSMakeRect(8, 30, 150, 14)
             in:fontInner];
    fileSubAlignPopup = [self popup:NSMakeRect(160, 24, 196, 22)
                             action:nil in:fontInner];
    {
        module_config_t *p_item = config_FindConfig("subsdec-align");
        if (p_item) {
            int i;
            for (i = 0; i < (int)p_item->list_count; i++)
                [fileSubAlignPopup addItemWithTitle:
                    _NS(p_item->list_text[i])];
            [fileSubAlignPopup selectItemAtIndex:p_item->value.i];
        }
    }

    NSButton *ok = [self button:_NS("OK") action:@selector(subCloseSheet:)
                          frame:NSMakeRect(312, 12, 92, 28) in:content];
    [ok setKeyEquivalent:@"\r"];
}

- (void)subFileSettings:(id)sender
{
    if (!fileSubSheet)
        [self buildSubSheet];
    [NSApp beginSheet:fileSubSheet
       modalForWindow:window
        modalDelegate:self
       didEndSelector:NULL
          contextInfo:nil];
}

- (void)subCloseSheet:(id)sender
{
    [fileSubSheet orderOut:sender];
    [NSApp endSheet:fileSubSheet];
    [self subsChanged:nil];
}

- (void)subFileBrowse:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setAllowsMultipleSelection:NO];
    if ([panel runModal] != NSOKButton)
        return;
    [subPath release];
    subPath = [[[[panel URLs] objectAtIndex:0] path] retain];
    [fileSubPathField setStringValue:subPath];
}

- (void)subOverride:(id)sender
{
    BOOL on = [fileSubOverrideCheckbox state] == NSOnState;
    [fileSubDelayField setEnabled:on];
    [fileSubDelayStepper setEnabled:on];
    [fileSubFPSField setEnabled:on];
    [fileSubFPSStepper setEnabled:on];
}

- (void)subDelayStepper:(id)sender
{
    [fileSubDelayField setIntValue:[fileSubDelayStepper intValue]];
}

- (void)subFPSStepper:(id)sender
{
    [fileSubFPSField setIntValue:[fileSubFPSStepper intValue]];
}

- (void)subsChanged:(id)sender
{
    if ([fileSubCheckbox state] == NSOnState) {
        [fileSubSettingsButton setEnabled:YES];
        if (subPath) {
            [fileSubtitlesFilenameLabel setStringValue:
                [[NSFileManager defaultManager]
                    displayNameAtPath:subPath]];
            [fileSubtitlesIconWell setImage:
                [[NSWorkspace sharedWorkspace] iconForFile:subPath]];
        }
    } else {
        [fileSubSettingsButton setEnabled:NO];
        [fileSubtitlesFilenameLabel setStringValue:@""];
        [fileSubtitlesIconWell setImage:nil];
    }
}

/*****************************************************************************
 * disc pane
 *****************************************************************************/

- (NSButton *)videoTSButtonIn:(NSView *)parent y:(float)y
{
    return [self button:_NS("Open VIDEO_TS / BDMV folder")
                 action:@selector(openSpecialMediaFolder:)
                  frame:NSMakeRect(20, y, 300, 28) in:parent];
}

- (NSTextField *)discTitleLabelIn:(NSView *)parent y:(float)y
{
    NSTextField *label = [self label:@"" frame:NSMakeRect(0, y, 340, 17)
                                  in:parent];
    [[label cell] setFont:[NSFont boldSystemFontOfSize:13]];
    return label;
}

- (void)addTitleChapterRowTo:(NSView *)parent y:(float)y
                  titleField:(NSTextField **)titleField
                titleStepper:(NSStepper **)titleStepper
                chapterField:(NSTextField **)chapterField
              chapterStepper:(NSStepper **)chapterStepper
                      action:(SEL)action
{
    [self label:_NS("Title") frame:NSMakeRect(20, y + 4, 60, 14) in:parent];
    *titleField = [self field:NSMakeRect(84, y, 46, 20) in:parent];
    [*titleField setIntValue:1];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(discFieldChanged:)
               name:NSControlTextDidChangeNotification object:*titleField];
    *titleStepper = [self stepper:NSMakeRect(134, y - 4, 19, 27)
                              min:1 max:999 action:action in:parent];
    [*titleStepper setIntValue:1];
    [self label:_NS("Chapter") frame:NSMakeRect(180, y + 4, 60, 14)
             in:parent];
    *chapterField = [self field:NSMakeRect(244, y, 46, 20) in:parent];
    [*chapterField setIntValue:0];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(discFieldChanged:)
               name:NSControlTextDidChangeNotification
             object:*chapterField];
    *chapterStepper = [self stepper:NSMakeRect(294, y - 4, 19, 27)
                                min:0 max:999 action:action in:parent];
}

- (NSView *)buildDiscPane
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 562, 300)] autorelease];

    discSelectorPopup = [self popup:NSMakeRect(16, 264, 530, 26)
                             action:@selector(discSelectorChanged:)
                                 in:pane];
    VLCLegacySetViewHidden(discSelectorPopup, YES);

    discIconView = [self iconWell:NSMakeRect(40, 80, 128, 128) in:pane];

    NSRect subRect = NSMakeRect(210, 30, 340, 220);

    /* "Insert Disc" */
    discNoDiscView = [[NSView alloc] initWithFrame:subRect];
    discNoDiscLabel = [self label:_NS("Insert Disc")
                            frame:NSMakeRect(0, 130, 340, 20)
                               in:discNoDiscView];
    [[discNoDiscLabel cell] setFont:[NSFont boldSystemFontOfSize:14]];
    [self videoTSButtonIn:discNoDiscView y:80];

    /* Audio CD */
    discAudioCDView = [[NSView alloc] initWithFrame:subRect];
    discAudioCDLabel = [self discTitleLabelIn:discAudioCDView y:140];
    discAudioCDTrackCountLabel = [self label:@""
                                       frame:NSMakeRect(0, 118, 340, 15)
                                          in:discAudioCDView];
    [self videoTSButtonIn:discAudioCDView y:60];

    /* DVD with menus */
    discDVDView = [[NSView alloc] initWithFrame:subRect];
    discDVDLabel = [self discTitleLabelIn:discDVDView y:140];
    discDVDMenusCheckbox = [self checkbox:_NS("DVD menus")
                                    frame:NSMakeRect(20, 101, 320, 18)
                                   action:@selector(dvdreadOptionChanged:)
                                       in:discDVDView];
    [discDVDMenusCheckbox setState:NSOnState];
    [discDVDMenusCheckbox setToolTip:
        _NS("Play the disc with its own menus. Unticking this plays a title "
            "directly and lets you pick the title and chapter numbers.")];
    [self videoTSButtonIn:discDVDView y:60];

    /* DVD without menus */
    discDVDwomenusView = [[NSView alloc] initWithFrame:subRect];
    discDVDwomenusLabel = [self discTitleLabelIn:discDVDwomenusView y:150];
    discDVDwomenusMenusCheckbox = [self checkbox:_NS("DVD menus")
                                           frame:NSMakeRect(20, 115, 320, 18)
                                          action:@selector(dvdreadOptionChanged:)
                                              in:discDVDwomenusView];
    [discDVDwomenusMenusCheckbox setState:NSOffState];
    [discDVDwomenusMenusCheckbox setToolTip:
        _NS("Play the disc with its own menus. Unticking this plays a title "
            "directly and lets you pick the title and chapter numbers.")];
    [self addTitleChapterRowTo:discDVDwomenusView y:76
                    titleField:&discDVDwomenusTitleField
                  titleStepper:&discDVDwomenusTitleStepper
                  chapterField:&discDVDwomenusChapterField
                chapterStepper:&discDVDwomenusChapterStepper
                        action:@selector(dvdreadOptionChanged:)];
    [self videoTSButtonIn:discDVDwomenusView y:30];

    /* VCD */
    discVCDView = [[NSView alloc] initWithFrame:subRect];
    discVCDLabel = [self discTitleLabelIn:discVCDView y:150];
    [self addTitleChapterRowTo:discVCDView y:100
                    titleField:&discVCDTitleField
                  titleStepper:&discVCDTitleStepper
                  chapterField:&discVCDChapterField
                chapterStepper:&discVCDChapterStepper
                        action:@selector(vcdOptionChanged:)];
    [self videoTSButtonIn:discVCDView y:40];

    /* Blu-ray */
    discBDView = [[NSView alloc] initWithFrame:subRect];
    discBDLabel = [self discTitleLabelIn:discBDView y:140];
    discBDMenusCheckbox = [self checkbox:_NS("Blu-ray menus")
                                   frame:NSMakeRect(20, 104, 320, 18)
                                  action:NULL in:discBDView];
    /* Seed it here as well: the pane may never be shown before the user hits
     * Open on a bluray:// address typed into the MRL field. */
    [discBDMenusCheckbox setState:
        var_InheritBool(p_intf, "bluray-menu") ? NSOnState : NSOffState];
    [discBDMenusCheckbox setToolTip:
        _NS("Play the disc with its own menus. Some discs run their menus as "
            "a Java (BD-J) application that keeps one processor core busy for "
            "as long as the disc is playing, which older Macs may not have to "
            "spare. Unticking this starts the main feature directly. The "
            "initial state of this box comes from the preferences.")];
    [self videoTSButtonIn:discBDView y:60];

    return pane;
}

- (NSDictionary *)scanPath:(NSString *)path
{
    NSString *type = volumeTypeForMountPath(path);
    NSImage *image = [[NSWorkspace sharedWorkspace] iconForFile:path];
    NSString *devicePath;

    /* BDMV path must not end with the BDMV directory */
    if ([type isEqualToString:kVLCMediaBDMVFolder]
     && [[path lastPathComponent] isEqualToString:@"BDMV"])
        path = [path stringByDeletingLastPathComponent];

    if ([type isEqualToString:kVLCMediaVideoTSFolder]
     || [type isEqualToString:kVLCMediaBD]
     || [type isEqualToString:kVLCMediaBDMVFolder]
     || [type isEqualToString:kVLCMediaUnknown])
        devicePath = path;
    else
        devicePath = bsdNodeForMountPath(path);

    return [NSDictionary dictionaryWithObjectsAndKeys:
        path, @"path", devicePath, @"devicePath", type, @"mediaType",
        image, @"image", nil];
}

- (void)scanOpticalMedia:(id)sender
{
    [allMediaDevices removeAllObjects];

    NSArray *paths = [[NSWorkspace sharedWorkspace] mountedRemovableMedia];
    unsigned i;
    for (i = 0; i < [paths count]; i++)
        [allMediaDevices addObject:
            [self scanPath:[paths objectAtIndex:i]]];
    /* Discs the OS could not mount: on 10.4 that is every Blu-ray. */
    [allMediaDevices addObjectsFromArray:unmountedOpticalDevices()];
    [allMediaDevices addObjectsFromArray:specialMediaFolders];

    [discSelectorPopup removeAllItems];
    unsigned count = (unsigned)[allMediaDevices count];
    if (count > 0) {
        for (i = 0; i < count; i++) {
            NSDictionary *dict = [allMediaDevices objectAtIndex:i];
            /* Unmounted discs carry their own label: displayNameAtPath: on a
             * device node would only ever answer "disk1". */
            NSString *title = [dict objectForKey:@"displayName"];
            if (title == nil)
                title = [[NSFileManager defaultManager]
                            displayNameAtPath:[dict objectForKey:@"path"]];
            [discSelectorPopup addItemWithTitle:title];
        }
        VLCLegacySetViewHidden(discSelectorPopup, count <= 1);
        if (sender == specialMediaFolders && count > 0)
            [discSelectorPopup selectItemAtIndex:count - 1];
        if ([[[tabView selectedTabViewItem] identifier] intValue]
                == OPEN_TAB_DISC)
            [self discSelectorChanged:nil];
    } else {
        VLCLegacySetViewHidden(discSelectorPopup, YES);
        if ([[[tabView selectedTabViewItem] identifier] intValue]
                == OPEN_TAB_DISC)
            [self setMRL:@""];
        [self showOpticalMediaView:discNoDiscView
                          withIcon:[self applicationIconImage]];
    }
}

- (void)showOpticalMediaView:(NSView *)theView withIcon:(NSImage *)icon
{
    if (discCurrentView == theView) {
        [icon setSize:NSMakeSize(128, 128)];
        [discIconView setImage:icon];
        return;
    }
    if (discCurrentView)
        [discCurrentView removeFromSuperview];
    NSView *pane = [[tabView tabViewItemAtIndex:OPEN_TAB_DISC] view];
    [pane addSubview:theView];
    discCurrentView = theView;
    [icon setSize:NSMakeSize(128, 128)];
    [discIconView setImage:icon];
}

- (void)showOpticalAtPath:(NSDictionary *)valueDictionary
{
    NSString *diskType = [valueDictionary objectForKey:@"mediaType"];
    NSString *opticalDevicePath = [valueDictionary objectForKey:@"path"];
    NSString *devicePath = [valueDictionary objectForKey:@"devicePath"];
    NSImage *image = [valueDictionary objectForKey:@"image"];

    if ([diskType isEqualToString:kVLCMediaDVD]
     || [diskType isEqualToString:kVLCMediaVideoTSFolder]) {
        [discDVDLabel setStringValue:[[NSFileManager defaultManager]
            displayNameAtPath:opticalDevicePath]];
        [discDVDwomenusLabel setStringValue:[discDVDLabel stringValue]];
        if (!b_nodvdmenus) {
            [self setMRL:[NSString stringWithFormat:@"dvdnav://%@",
                devicePath]];
            [self showOpticalMediaView:discDVDView withIcon:image];
        } else {
            [self setMRL:[NSString stringWithFormat:@"dvdread://%@#%i:%i-",
                devicePath, [discDVDwomenusTitleField intValue],
                [discDVDwomenusChapterField intValue]]];
            [self showOpticalMediaView:discDVDwomenusView withIcon:image];
        }
    } else if ([diskType isEqualToString:kVLCMediaAudioCD]) {
        [discAudioCDLabel setStringValue:[[NSFileManager defaultManager]
            displayNameAtPath:opticalDevicePath]];
        [discAudioCDTrackCountLabel setStringValue:
            [NSString stringWithFormat:_NS("%i tracks"),
                (int)[[[NSFileManager defaultManager]
                    directoryContentsAtPath:opticalDevicePath] count] - 1]];
        [self showOpticalMediaView:discAudioCDView withIcon:image];
        [self setMRL:[NSString stringWithFormat:@"cdda://%@", devicePath]];
    } else if ([diskType isEqualToString:kVLCMediaVCD]) {
        [discVCDLabel setStringValue:[[NSFileManager defaultManager]
            displayNameAtPath:opticalDevicePath]];
        [self showOpticalMediaView:discVCDView withIcon:image];
        [self setMRL:[NSString stringWithFormat:@"vcd://%@#%i:%i",
            devicePath, [discVCDTitleField intValue],
            [discVCDChapterField intValue]]];
    } else if ([diskType isEqualToString:kVLCMediaSVCD]) {
        [discVCDLabel setStringValue:[[NSFileManager defaultManager]
            displayNameAtPath:opticalDevicePath]];
        [self showOpticalMediaView:discVCDView withIcon:image];
        [self setMRL:[NSString stringWithFormat:@"vcd://%@@%i:%i",
            devicePath, [discVCDTitleField intValue],
            [discVCDChapterField intValue]]];
    } else if ([diskType isEqualToString:kVLCMediaBD]
            || [diskType isEqualToString:kVLCMediaBDMVFolder]) {
        /* Same reason as the popup title: a device node has no display name
         * worth showing, so prefer the label we built from the drive. */
        NSString *bdLabel = [valueDictionary objectForKey:@"displayName"];
        if (bdLabel == nil)
            bdLabel = [[NSFileManager defaultManager]
                          displayNameAtPath:opticalDevicePath];
        [discBDLabel setStringValue:bdLabel];
        /* Preselect from the preferences every time the pane is shown, so the
         * box always mirrors the setting the user last chose there. */
        [discBDMenusCheckbox setState:
            var_InheritBool(p_intf, "bluray-menu") ? NSOnState : NSOffState];
        [self showOpticalMediaView:discBDView withIcon:image];
        [self setMRL:[NSString stringWithFormat:@"bluray://%@",
            opticalDevicePath]];
    } else {
        msg_Warn(p_intf, "unknown disk type, no idea what to display");
        [self showOpticalMediaView:discNoDiscView
                          withIcon:[self applicationIconImage]];
        [self setMRL:@""];
    }
}

- (void)discSelectorChanged:(id)sender
{
    int selected = (int)[discSelectorPopup indexOfSelectedItem];
    if (selected < 0 || (unsigned)selected >= [allMediaDevices count])
        return;
    [self showOpticalAtPath:[allMediaDevices objectAtIndex:selected]];
}

- (void)openSpecialMediaFolder:(id)sender
{
    /* this is for VIDEO_TS and BDMV folders */
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:YES];
    [panel setCanChooseFiles:NO];
    [panel setTitle:[sender title]];
    [panel setPrompt:_NS("Open")];
    if ([panel runModal] != NSOKButton)
        return;
    NSString *path = [[[panel URLs] objectAtIndex:0] path];
    if (![path length])
        return;
    [specialMediaFolders addObject:[self scanPath:path]];
    [self scanOpticalMedia:specialMediaFolders];
}

- (NSString *)selectedDiscDevicePath
{
    int selected = (int)[discSelectorPopup indexOfSelectedItem];
    if (selected < 0 || (unsigned)selected >= [allMediaDevices count])
        return @"";
    return [[allMediaDevices objectAtIndex:selected]
        objectForKey:@"devicePath"];
}

- (void)dvdreadOptionChanged:(id)sender
{
    NSString *devicePath = [self selectedDiscDevicePath];

    /* Key on the control itself: matching against the translated title used
     * to work only as long as both strings kept their exact wording in every
     * locale. Each box then goes back to the state its own view stands for,
     * since the click that brought us here toggled it. */
    if (sender == discDVDwomenusMenusCheckbox) {
        b_nodvdmenus = NO;
        [discDVDMenusCheckbox setState:NSOnState];
        [discDVDwomenusMenusCheckbox setState:NSOffState];
        [self setMRL:[NSString stringWithFormat:@"dvdnav://%@", devicePath]];
        [self showOpticalMediaView:discDVDView
                          withIcon:[discIconView image]];
        return;
    }
    if (sender == discDVDMenusCheckbox) {
        b_nodvdmenus = YES;
        [discDVDMenusCheckbox setState:NSOnState];
        [discDVDwomenusMenusCheckbox setState:NSOffState];
        [self showOpticalMediaView:discDVDwomenusView
                          withIcon:[discIconView image]];
    }

    if (sender == discDVDwomenusTitleStepper)
        [discDVDwomenusTitleField setIntValue:
            [discDVDwomenusTitleStepper intValue]];
    if (sender == discDVDwomenusChapterStepper)
        [discDVDwomenusChapterField setIntValue:
            [discDVDwomenusChapterStepper intValue]];

    [self setMRL:[NSString stringWithFormat:@"dvdread://%@#%i:%i-",
        devicePath, [discDVDwomenusTitleField intValue],
        [discDVDwomenusChapterField intValue]]];
}

- (void)vcdOptionChanged:(id)sender
{
    if (sender == discVCDTitleStepper)
        [discVCDTitleField setIntValue:[discVCDTitleStepper intValue]];
    if (sender == discVCDChapterStepper)
        [discVCDChapterField setIntValue:[discVCDChapterStepper intValue]];

    [self setMRL:[NSString stringWithFormat:@"vcd://%@@%i:%i",
        [self selectedDiscDevicePath], [discVCDTitleField intValue],
        [discVCDChapterField intValue]]];
}

- (void)discFieldChanged:(NSNotification *)notification
{
    id field = [notification object];
    if (field == discDVDwomenusTitleField
     || field == discDVDwomenusChapterField)
        [self dvdreadOptionChanged:nil];
    else if (field == discVCDTitleField || field == discVCDChapterField)
        [self vcdOptionChanged:nil];
}

/*****************************************************************************
 * network pane
 *****************************************************************************/

- (NSView *)buildNetworkPane
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 562, 300)] autorelease];

    [self label:_NS("URL") frame:NSMakeRect(16, 266, 100, 14) in:pane];
    netHTTPURLField = [self field:NSMakeRect(16, 238, 530, 22) in:pane];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(openNetInfoChanged:)
               name:NSControlTextDidChangeNotification
             object:netHTTPURLField];

    NSTextField *help = [self label:
        _NS("To Open a usual network stream (HTTP, RTSP, RTMP, MMS, FTP, "
            "etc.), just enter the URL in the field above. If you want to "
            "open a RTP or UDP stream, press the button below.")
        frame:NSMakeRect(16, 120, 530, 90) in:pane];
    [help setTextColor:[NSColor colorWithCalibratedWhite:0.42 alpha:1.0]];
    [[help cell] setWraps:YES];

    [self button:_NS("Open RTP/UDP Stream")
          action:@selector(openNetUDPButtonAction:)
           frame:NSMakeRect(16, 20, 240, 28) in:pane];

    return pane;
}

- (void)buildUDPPanel
{
    netUDPPanel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 430, 340)
                  styleMask:NSTitledWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    NSView *content = [netUDPPanel contentView];

    NSButtonCell *radioProto = [[[NSButtonCell alloc] init] autorelease];
    [radioProto setButtonType:NSRadioButton];
    [radioProto setFont:[NSFont systemFontOfSize:11]];

    [self label:_NS("Protocol") frame:NSMakeRect(20, 300, 90, 14)
             in:content];
    netUDPProtocolMatrix = [[[NSMatrix alloc]
        initWithFrame:NSMakeRect(120, 274, 200, 42)
                 mode:NSRadioModeMatrix
            prototype:radioProto
         numberOfRows:2
      numberOfColumns:1] autorelease];
    [netUDPProtocolMatrix setCellSize:NSMakeSize(120, 20)];
    [[netUDPProtocolMatrix cellAtRow:0 column:0] setTitle:@"UDP"];
    [[netUDPProtocolMatrix cellAtRow:0 column:0] setTag:0];
    [[netUDPProtocolMatrix cellAtRow:1 column:0] setTitle:@"RTP"];
    [[netUDPProtocolMatrix cellAtRow:1 column:0] setTag:1];
    [netUDPProtocolMatrix setTarget:self];
    [netUDPProtocolMatrix setAction:@selector(openNetModeChanged:)];
    [content addSubview:netUDPProtocolMatrix];

    [self label:_NS("Mode") frame:NSMakeRect(20, 250, 90, 14) in:content];
    netModeMatrix = [[[NSMatrix alloc]
        initWithFrame:NSMakeRect(120, 224, 200, 42)
                 mode:NSRadioModeMatrix
            prototype:radioProto
         numberOfRows:2
      numberOfColumns:1] autorelease];
    [netModeMatrix setCellSize:NSMakeSize(140, 20)];
    [[netModeMatrix cellAtRow:0 column:0] setTitle:_NS("Unicast")];
    [[netModeMatrix cellAtRow:0 column:0] setTag:0];
    [[netModeMatrix cellAtRow:1 column:0] setTitle:_NS("Multicast")];
    [[netModeMatrix cellAtRow:1 column:0] setTag:1];
    [netModeMatrix setTarget:self];
    [netModeMatrix setAction:@selector(openNetModeChanged:)];
    [content addSubview:netModeMatrix];

    /* unicast: local port */
    [self label:_NS("Port") frame:NSMakeRect(20, 192, 90, 14) in:content];
    netUDPPortField = [self field:NSMakeRect(120, 188, 80, 20) in:content];
    [netUDPPortField setIntValue:config_GetInt(p_intf, "server-port")];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(openNetInfoChanged:)
               name:NSControlTextDidChangeNotification
             object:netUDPPortField];
    netUDPPortStepper = [self stepper:NSMakeRect(204, 184, 19, 27)
                                  min:0 max:65535
                               action:@selector(openNetStepperChanged:)
                                   in:content];
    [netUDPPortStepper setTag:0];
    [netUDPPortStepper setIntValue:[netUDPPortField intValue]];

    /* multicast: address + port */
    [self label:_NS("IP Address") frame:NSMakeRect(20, 156, 96, 14)
             in:content];
    netUDPMAddressField = [self field:NSMakeRect(120, 152, 180, 20)
                                   in:content];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(openNetInfoChanged:)
               name:NSControlTextDidChangeNotification
             object:netUDPMAddressField];
    [self label:_NS("Port") frame:NSMakeRect(20, 128, 90, 14) in:content];
    netUDPMPortField = [self field:NSMakeRect(120, 124, 80, 20) in:content];
    [netUDPMPortField setIntValue:config_GetInt(p_intf, "server-port")];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(openNetInfoChanged:)
               name:NSControlTextDidChangeNotification
             object:netUDPMPortField];
    netUDPMPortStepper = [self stepper:NSMakeRect(204, 120, 19, 27)
                                   min:0 max:65535
                                action:@selector(openNetStepperChanged:)
                                    in:content];
    [netUDPMPortStepper setTag:1];
    [netUDPMPortStepper setIntValue:[netUDPMPortField intValue]];

    NSTextField *help = [self label:
        _NS("If you want to open a multicast stream, enter the respective "
            "IP address given by the stream provider. In unicast mode, VLC "
            "will use your machine's IP automatically.\n\nTo open a stream "
            "using a different protocol, just press Cancel to close this "
            "sheet.")
        frame:NSMakeRect(20, 52, 390, 62) in:content];
    [help setTextColor:[NSColor colorWithCalibratedWhite:0.42 alpha:1.0]];
    [[help cell] setWraps:YES];
    [[help cell] setFont:[NSFont systemFontOfSize:10]];

    NSButton *cancel = [self button:_NS("Cancel")
                             action:@selector(openNetUDPButtonAction:)
                              frame:NSMakeRect(240, 12, 88, 28) in:content];
    [cancel setKeyEquivalent:@"\033"];
    NSButton *ok = [self button:_NS("Open")
                         action:@selector(openNetUDPOK:)
                          frame:NSMakeRect(332, 12, 88, 28) in:content];
    [ok setKeyEquivalent:@"\r"];
}

- (NSString *)udpMRLString
{
    NSString *mrlString;
    BOOL rtp = [[netUDPProtocolMatrix selectedCell] tag] == 1;

    if ([[netModeMatrix selectedCell] tag] == 0) {
        /* unicast */
        int port = [netUDPPortField intValue];
        mrlString = rtp ? @"rtp://" : @"udp://";
        if (port != config_GetInt(p_intf, "server-port"))
            mrlString = [mrlString stringByAppendingFormat:@"@:%i", port];
    } else {
        /* multicast */
        NSString *address = [netUDPMAddressField stringValue];
        int port = [netUDPMPortField intValue];
        mrlString = [NSString stringWithFormat:@"%@://@%@",
            rtp ? @"rtp" : @"udp", address];
        if (port != config_GetInt(p_intf, "server-port"))
            mrlString = [mrlString stringByAppendingFormat:@":%i", port];
    }
    return mrlString;
}

- (void)openNetInfoChanged:(id)sender
{
    if (netUDPPanel && [netUDPPanel isVisible]) {
        [self setMRL:[self udpMRLString]];
        return;
    }

    NSString *mrlString = [[netHTTPURLField stringValue]
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    const char *orig_uri = [mrlString UTF8String];
    if (!orig_uri)
        return;
    char *fixed_uri = vlc_uri_fixup(orig_uri);
    if (fixed_uri) {
        mrlString = [NSString stringWithUTF8String:fixed_uri];
        free(fixed_uri);
    }
    [self setMRL:mrlString];
}

- (void)openNetModeChanged:(id)sender
{
    if (sender == netModeMatrix) {
        if ([[netModeMatrix selectedCell] tag] == 0)
            [netUDPPanel makeFirstResponder:netUDPPortField];
        else
            [netUDPPanel makeFirstResponder:netUDPMAddressField];
    }
    [self openNetInfoChanged:nil];
}

- (void)openNetStepperChanged:(id)sender
{
    if ([sender tag] == 0)
        [netUDPPortField setIntValue:[netUDPPortStepper intValue]];
    else
        [netUDPMPortField setIntValue:[netUDPMPortStepper intValue]];
    [self openNetInfoChanged:nil];
}

- (void)openNetUDPButtonAction:(id)sender
{
    if ([[sender title] isEqualToString:_NS("Cancel")]) {
        [netUDPPanel orderOut:sender];
        [NSApp endSheet:netUDPPanel];
        [self openNetInfoChanged:nil];
        return;
    }
    if (!netUDPPanel)
        [self buildUDPPanel];
    [NSApp beginSheet:netUDPPanel
       modalForWindow:window
        modalDelegate:self
       didEndSelector:NULL
          contextInfo:nil];
    [self openNetInfoChanged:nil];
}

- (void)openNetUDPOK:(id)sender
{
    NSString *mrlString = [self udpMRLString];
    [self setMRL:mrlString];
    [netHTTPURLField setStringValue:mrlString];
    [netUDPPanel orderOut:sender];
    [NSApp endSheet:netUDPPanel];
}

/*****************************************************************************
 * capture pane
 *****************************************************************************/

- (NSView *)buildCapturePane
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 562, 300)] autorelease];

    captureModePopup = [self popup:NSMakeRect(16, 264, 220, 26)
                            action:@selector(openCaptureModeChanged:)
                                in:pane];
    [captureModePopup addItemWithTitle:_NS("Input Devices")];
    [captureModePopup addItemWithTitle:_NS("Screen")];

    captureTabView = [[[NSTabView alloc]
        initWithFrame:NSMakeRect(8, 8, 546, 246)] autorelease];
    [captureTabView setTabViewType:NSNoTabsNoBorder];

    /* --- input devices --- */
    NSView *devices = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 546, 246)] autorelease];
    qtkVideoCheckbox = [self checkbox:_NS("Video")
                                frame:NSMakeRect(24, 196, 100, 18)
                               action:@selector(qtkToggleUIElements:)
                                   in:devices];
    qtkVideoDevicePopup = [self popup:NSMakeRect(140, 190, 320, 26)
                               action:nil in:devices];
    [qtkVideoDevicePopup addItemWithTitle:_NS("None")];
    [qtkVideoDevicePopup setEnabled:NO];
    qtkAudioCheckbox = [self checkbox:_NS("Audio")
                                frame:NSMakeRect(24, 156, 100, 18)
                               action:@selector(qtkToggleUIElements:)
                                   in:devices];
    qtkAudioDevicePopup = [self popup:NSMakeRect(140, 150, 320, 26)
                               action:nil in:devices];
    [qtkAudioDevicePopup addItemWithTitle:_NS("None")];
    [qtkAudioDevicePopup setEnabled:NO];
    NSTabViewItem *devicesItem = [[[NSTabViewItem alloc]
        initWithIdentifier:@"devices"] autorelease];
    [devicesItem setView:devices];
    [captureTabView addTabViewItem:devicesItem];

    /* --- screen --- */
    NSView *screen = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 546, 246)] autorelease];
    [self label:[NSString stringWithFormat:@"%@:", _NS("Screen")]
          frame:NSMakeRect(24, 208, 130, 14) in:screen];
    screenPopup = [self popup:NSMakeRect(160, 202, 260, 26)
                       action:@selector(screenChanged:) in:screen];
    [self label:[NSString stringWithFormat:@"%@:", _NS("Frames per Second")]
          frame:NSMakeRect(24, 176, 150, 14) in:screen];
    screenFPSField = [self field:NSMakeRect(180, 172, 56, 20) in:screen];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(screenFPSfieldChanged:)
               name:NSControlTextDidChangeNotification
             object:screenFPSField];
    screenFPSStepper = [self stepper:NSMakeRect(240, 166, 19, 27)
                                 min:1 max:100
                              action:@selector(screenStepperChanged:)
                                  in:screen];
    [self label:[NSString stringWithFormat:@"%@:", _NS("Subscreen left")]
          frame:NSMakeRect(24, 144, 150, 14) in:screen];
    screenLeftField = [self field:NSMakeRect(180, 140, 56, 20) in:screen];
    screenLeftStepper = [self stepper:NSMakeRect(240, 134, 19, 27)
                                  min:0 max:32000
                               action:@selector(screenStepperChanged:)
                                   in:screen];
    [self label:[NSString stringWithFormat:@"%@:", _NS("Subscreen top")]
          frame:NSMakeRect(290, 144, 150, 14) in:screen];
    screenTopField = [self field:NSMakeRect(446, 140, 56, 20) in:screen];
    screenTopStepper = [self stepper:NSMakeRect(506, 134, 19, 27)
                                 min:0 max:32000
                              action:@selector(screenStepperChanged:)
                                  in:screen];
    [self label:[NSString stringWithFormat:@"%@:", _NS("Subscreen Width")]
          frame:NSMakeRect(24, 112, 150, 14) in:screen];
    screenWidthField = [self field:NSMakeRect(180, 108, 56, 20) in:screen];
    screenWidthStepper = [self stepper:NSMakeRect(240, 102, 19, 27)
                                   min:0 max:32000
                                action:@selector(screenStepperChanged:)
                                    in:screen];
    [self label:[NSString stringWithFormat:@"%@:", _NS("Subscreen Height")]
          frame:NSMakeRect(290, 112, 150, 14) in:screen];
    screenHeightField = [self field:NSMakeRect(446, 108, 56, 20) in:screen];
    screenHeightStepper = [self stepper:NSMakeRect(506, 102, 19, 27)
                                    min:0 max:32000
                                 action:@selector(screenStepperChanged:)
                                     in:screen];
    screenFollowMouseCheckbox = [self checkbox:_NS("Follow the mouse")
                                         frame:NSMakeRect(24, 72, 250, 18)
                                        action:nil in:screen];
    screenqtkAudioCheckbox = [self checkbox:_NS("Capture Audio")
                                      frame:NSMakeRect(24, 40, 150, 18)
                                     action:@selector(screenAudioChanged:)
                                         in:screen];
    screenqtkAudioPopup = [self popup:NSMakeRect(180, 34, 260, 26)
                               action:nil in:screen];
    [screenqtkAudioPopup addItemWithTitle:_NS("None")];
    [screenqtkAudioPopup setEnabled:NO];
    NSTabViewItem *screenItem = [[[NSTabViewItem alloc]
        initWithIdentifier:@"screen"] autorelease];
    [screenItem setView:screen];
    [captureTabView addTabViewItem:screenItem];

    [pane addSubview:captureTabView];
    return pane;
}

- (void)openCaptureModeChanged:(id)sender
{
    if ([[[captureModePopup selectedItem] title]
            isEqualToString:_NS("Screen")]) {
        [captureTabView selectTabViewItemAtIndex:1];
        [self setMRL:@"screen://"];
        [screenHeightField setIntValue:
            (int)config_GetInt(p_intf, "screen-height")];
        [screenWidthField setIntValue:
            (int)config_GetInt(p_intf, "screen-width")];
        [screenFPSField setFloatValue:
            config_GetFloat(p_intf, "screen-fps")];
        [screenFPSStepper setIntValue:[screenFPSField intValue]];
        [screenLeftField setIntValue:
            (int)config_GetInt(p_intf, "screen-left")];
        [screenTopField setIntValue:
            (int)config_GetInt(p_intf, "screen-top")];
        [screenFollowMouseCheckbox setState:
            config_GetInt(p_intf, "screen-follow-mouse")
                ? NSOnState : NSOffState];

        /* screen list */
        unsigned int displayCount = 0;
        if (CGGetOnlineDisplayList(0, NULL, &displayCount)
                == kCGErrorSuccess && displayCount > 0) {
            CGDirectDisplayID *ids =
                malloc(displayCount * sizeof (*ids));
            if (ids && CGGetOnlineDisplayList(displayCount, ids,
                    &displayCount) == kCGErrorSuccess) {
                int displayID =
                    (int)config_GetInt(p_intf, "screen-display-id");
                int screenIndex =
                    (int)config_GetInt(p_intf, "screen-index");
                [displayIDs removeAllObjects];
                [screenPopup removeAllItems];
                unsigned int i;
                for (i = 0; i < displayCount; i++) {
                    CGRect rect = CGDisplayBounds(ids[i]);
                    [screenPopup addItemWithTitle:
                        [NSString stringWithFormat:@"Screen %d (%dx%d)",
                            i + 1, (int)rect.size.width,
                            (int)rect.size.height]];
                    [displayIDs addObject:
                        [NSNumber numberWithUnsignedInt:ids[i]]];
                    if (i == 0 || displayID == (int)ids[i]
                     || screenIndex - 1 == (int)i) {
                        [screenPopup selectItemAtIndex:i];
                        [screenLeftStepper setMaxValue:rect.size.width];
                        [screenTopStepper setMaxValue:rect.size.height];
                        [screenWidthStepper setMaxValue:rect.size.width];
                        [screenHeightStepper setMaxValue:rect.size.height];
                    }
                }
            }
            free(ids);
        }
    } else {
        [captureTabView selectTabViewItemAtIndex:0];
        [self qtkToggleUIElements:nil];
    }
}

- (void)screenFPSfieldChanged:(NSNotification *)notification
{
    [screenFPSStepper setIntValue:[screenFPSField intValue]];
    if ([[screenFPSField stringValue] isEqualToString:@""])
        [screenFPSField setFloatValue:1.0];
    [self setMRL:@"screen://"];
}

- (void)screenStepperChanged:(id)sender
{
    if (sender == screenFPSStepper)
        [screenFPSField setIntValue:[screenFPSStepper intValue]];
    else if (sender == screenLeftStepper)
        [screenLeftField setIntValue:[screenLeftStepper intValue]];
    else if (sender == screenTopStepper)
        [screenTopField setIntValue:[screenTopStepper intValue]];
    else if (sender == screenWidthStepper)
        [screenWidthField setIntValue:[screenWidthStepper intValue]];
    else if (sender == screenHeightStepper)
        [screenHeightField setIntValue:[screenHeightStepper intValue]];
}

- (void)screenChanged:(id)sender
{
    int selected = (int)[screenPopup indexOfSelectedItem];
    if (selected < 0 || (unsigned)selected >= [displayIDs count])
        return;
    CGRect rect = CGDisplayBounds((CGDirectDisplayID)
        [[displayIDs objectAtIndex:selected] unsignedIntValue]);
    [screenLeftStepper setMaxValue:rect.size.width];
    [screenTopStepper setMaxValue:rect.size.height];
    [screenWidthStepper setMaxValue:rect.size.width];
    [screenHeightStepper setMaxValue:rect.size.height];
    [screenqtkAudioPopup setEnabled:[screenqtkAudioCheckbox state]];
}

- (void)screenAudioChanged:(id)sender
{
    [screenqtkAudioPopup setEnabled:[screenqtkAudioCheckbox state]];
}

- (void)qtkToggleUIElements:(id)sender
{
    /* AVFoundation/QTKit capture devices need modules that only exist on
     * newer releases; the popups list "None" and the MRL stays empty,
     * exactly what 3.0 shows without any capture device */
    [qtkAudioDevicePopup setEnabled:[qtkAudioCheckbox state]];
    [qtkVideoDevicePopup setEnabled:[qtkVideoCheckbox state]];
    [self setMRL:@""];
}

/*****************************************************************************
 * window
 *****************************************************************************/

- (void)buildWindow
{
    window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 596, 460)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:_NS("Open Source")];
    [window setReleasedWhenClosed:NO];
    NSView *content = [window contentView];

    tabView = [[[NSTabView alloc]
        initWithFrame:NSMakeRect(10, 96, 576, 356)] autorelease];
    struct { const char *title; SEL builder; } tabs[4] = {
        { N_("File"),    @selector(buildFilePane) },
        { N_("Disc"),    @selector(buildDiscPane) },
        { N_("Network"), @selector(buildNetworkPane) },
        { N_("Capture"), @selector(buildCapturePane) },
    };
    int i;
    for (i = 0; i < 4; i++) {
        NSTabViewItem *item = [[[NSTabViewItem alloc]
            initWithIdentifier:[NSNumber numberWithInt:i]] autorelease];
        [item setLabel:_NS(tabs[i].title)];
        [item setView:[self performSelector:tabs[i].builder]];
        [tabView addTabViewItem:item];
    }
    [tabView setDelegate:(id)self];
    [content addSubview:tabView];

    /* the disclosed MRL row, like the 3.0 window */
    mrlDisclosureButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(12, 66, 18, 18)] autorelease];
    [mrlDisclosureButton setBezelStyle:NSDisclosureBezelStyle];
    [mrlDisclosureButton setButtonType:NSOnOffButton];
    [mrlDisclosureButton setTitle:@""];
    [mrlDisclosureButton setTarget:self];
    [mrlDisclosureButton setAction:@selector(expandMRLfieldAction:)];
    [content addSubview:mrlDisclosureButton];
    mrlLabel = [self label:_NS("Media Resource Locator (MRL)")
                     frame:NSMakeRect(34, 68, 400, 14) in:content];
    mrlField = [self field:NSMakeRect(12, 44, 572, 20) in:content];
    VLCLegacySetViewHidden(mrlField, YES);
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(mrlFieldChanged:)
               name:NSControlTextDidChangeNotification object:mrlField];

    /* bottom row */
    outputCheckbox = [self checkbox:_NS("Stream output:")
                              frame:NSMakeRect(18, 16, 130, 18)
                             action:@selector(outputCheckboxChanged:)
                                 in:content];
    outputSettingsButton = [self button:_NS("Settings...")
                                 action:@selector(outputSettings:)
                                  frame:NSMakeRect(148, 10, 110, 28)
                                     in:content];
    [outputSettingsButton setEnabled:NO];

    okButton = [self button:_NS("Open") action:@selector(openClicked:)
                      frame:NSMakeRect(494, 10, 92, 28) in:content];
    [okButton setKeyEquivalent:@"\r"];
    [okButton setEnabled:NO];
    NSButton *cancel = [self button:_NS("Cancel")
                             action:@selector(cancelClicked:)
                              frame:NSMakeRect(398, 10, 92, 28) in:content];
    [cancel setKeyEquivalent:@"\033"];

    /* watch mounts/unmounts like the 3.0 controller */
    NSNotificationCenter *wsCenter =
        [[NSWorkspace sharedWorkspace] notificationCenter];
    [wsCenter addObserver:self selector:@selector(scanOpticalMedia:)
                     name:NSWorkspaceDidMountNotification object:nil];
    [wsCenter addObserver:self selector:@selector(scanOpticalMedia:)
                     name:NSWorkspaceDidUnmountNotification object:nil];

    [self scanOpticalMedia:nil];
    [window center];
}

- (void)expandMRLfieldAction:(id)sender
{
    VLCLegacySetViewHidden(mrlField,
                           [mrlDisclosureButton state] == NSOffState);
}

- (void)mrlFieldChanged:(NSNotification *)notification
{
    /* manual MRL edits win over the pane-composed value */
    [mrl release];
    mrl = [[[mrlField stringValue] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceAndNewlineCharacterSet]] retain];
    [okButton setEnabled:[mrl length] > 0];
}

- (void)outputCheckboxChanged:(id)sender
{
    [outputSettingsButton setEnabled:[outputCheckbox state]];
}

- (void)outputSettings:(id)sender
{
    [output beginSheetForWindow:window];
}

- (void)tabView:(NSTabView *)theTabView
    didSelectTabViewItem:(NSTabViewItem *)tabViewItem
{
    switch ([[tabViewItem identifier] intValue]) {
    case OPEN_TAB_FILE:
        [self openFilePathChanged:nil];
        break;
    case OPEN_TAB_DISC:
        [self scanOpticalMedia:nil];
        break;
    case OPEN_TAB_NETWORK:
        [self openNetInfoChanged:nil];
        [netHTTPURLField selectText:nil];
        break;
    case OPEN_TAB_CAPTURE:
        [self openCaptureModeChanged:nil];
        break;
    }
}

- (void)showTab:(int)tab
{
    if (!window)
        [self buildWindow];
    if ([tabView indexOfTabViewItem:[tabView selectedTabViewItem]] == tab)
        [self tabView:tabView
            didSelectTabViewItem:[tabView selectedTabViewItem]];
    else
        [tabView selectTabViewItemAtIndex:tab];
    [window makeKeyAndOrderFront:nil];
}

/*****************************************************************************
 * open
 *****************************************************************************/

- (int)secondsFromTimeString:(NSString *)string
{
    NSArray *components = [string componentsSeparatedByString:@":"];
    unsigned count = (unsigned)[components count];
    if (count == 1)
        return [[components objectAtIndex:0] intValue];
    if (count == 2)
        return [[components objectAtIndex:0] intValue] * 60
             + [[components objectAtIndex:1] intValue];
    if (count == 3)
        return [[components objectAtIndex:0] intValue] * 3600
             + [[components objectAtIndex:1] intValue] * 60
             + [[components objectAtIndex:2] intValue];
    return 0;
}

- (void)cancelClicked:(id)sender
{
    [window orderOut:nil];
}

- (void)openClicked:(id)sender
{
    NSString *theMrl = [[mrlField stringValue]
        stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (![theMrl length])
        theMrl = mrl;
    if (![theMrl length])
        return;

    NSMutableArray *options = [NSMutableArray array];

    /* Blu-ray menus. Keyed on the MRL rather than on the selected pane so a
     * bluray:// address typed by hand gets the box's value too, and always
     * passed explicitly so this item overrides the preference. */
    if ([theMrl hasPrefix:@"bluray://"])
        [options addObject:([discBDMenusCheckbox state] == NSOnState)
            ? @"bluray-menu" : @"no-bluray-menu"];

    if ([fileSubCheckbox state] == NSOnState && subPath) {
        [options addObject:
            [NSString stringWithFormat:@"sub-file=%@", subPath]];
        if ([fileSubOverrideCheckbox state] == NSOnState) {
            [options addObject:[NSString stringWithFormat:@"sub-delay=%i",
                [fileSubDelayField intValue] * 10]];
            [options addObject:[NSString stringWithFormat:@"sub-fps=%f",
                [fileSubFPSField floatValue]]];
        }
        [options addObject:
            [NSString stringWithFormat:@"subsdec-encoding=%@",
                [[fileSubEncodingPopup selectedItem] representedObject]]];
        [options addObject:
            [NSString stringWithFormat:@"subsdec-align=%i",
                (int)[fileSubAlignPopup indexOfSelectedItem]]];
        module_config_t *p_item = config_FindConfig("freetype-rel-fontsize");
        if (p_item && [fileSubSizePopup indexOfSelectedItem] >= 0
         && [fileSubSizePopup indexOfSelectedItem] < (int)p_item->list_count)
            [options addObject:
                [NSString stringWithFormat:@"freetype-rel-fontsize=%i",
                    p_item->list.i[[fileSubSizePopup
                                       indexOfSelectedItem]]]];
    }

    if ([fileCustomTimingCheckbox state] == NSOnState) {
        int start =
            [self secondsFromTimeString:[fileStartTimeField stringValue]];
        if (start > 0)
            [options addObject:
                [NSString stringWithFormat:@"start-time=%i", start]];
        int stop =
            [self secondsFromTimeString:[fileStopTimeField stringValue]];
        if (stop != 0)
            [options addObject:
                [NSString stringWithFormat:@"stop-time=%i", stop]];
    }

    if ([outputCheckbox state] == NSOnState) {
        NSArray *soutMRL = [output soutMRL];
        unsigned i;
        for (i = 0; i < [soutMRL count]; i++)
            [options addObject:[soutMRL objectAtIndex:i]];
    }

    if ([fileSlaveCheckbox state] && fileSlavePath)
        [options addObject:
            [NSString stringWithFormat:@"input-slave=%@", fileSlavePath]];

    if ([[[tabView selectedTabViewItem] identifier] intValue]
            == OPEN_TAB_CAPTURE
     && [[[captureModePopup selectedItem] title]
            isEqualToString:_NS("Screen")]) {
        int selected = (int)[screenPopup indexOfSelectedItem];
        [options addObject:[NSString stringWithFormat:@"screen-fps=%f",
            [screenFPSField floatValue]]];
        if (selected >= 0 && (unsigned)selected < [displayIDs count])
            [options addObject:
                [NSString stringWithFormat:@"screen-display-id=%i",
                    [[displayIDs objectAtIndex:selected] intValue]]];
        [options addObject:[NSString stringWithFormat:@"screen-left=%i",
            [screenLeftField intValue]]];
        [options addObject:[NSString stringWithFormat:@"screen-top=%i",
            [screenTopField intValue]]];
        [options addObject:[NSString stringWithFormat:@"screen-width=%i",
            [screenWidthField intValue]]];
        [options addObject:[NSString stringWithFormat:@"screen-height=%i",
            [screenHeightField intValue]]];
        if ([screenFollowMouseCheckbox state] == NSOnState)
            [options addObject:@"screen-follow-mouse"];
        else
            [options addObject:@"no-screen-follow-mouse"];
    }

    [self addMRL:theMrl options:options];
    [window orderOut:nil];
}

@end
