/*****************************************************************************
 * VLCLegacyConvertAndSave.m: Convert & Stream window (legacy interface)
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

#import "VLCLegacyConvertAndSave.h"
#import "misc.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyHUDWindow.h"   /* modal text/popup prompts */
#import "VLCLegacyMenu.h"        /* VLCLegacyNoteRecentItem */

#include <vlc_playlist.h>
#include <vlc_input_item.h>
#include <vlc_url.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/* NSUserDefaults keys, identical to VLCConvertAndSaveWindowController so
 * custom profiles carry over between the two interfaces */
#define CAS_PROFILES_KEY      @"CASProfiles"
#define CAS_PROFILE_NAMES_KEY @"CASProfileNames"

/* encapsulation matrix tags (VLCConvertAndSaveWindowController defines) */
#define MPEGTS 0
#define WEBM   1
#define OGG    2
#define MP4    3
#define MPEGPS 4
#define MJPEG  5
#define WAV    6
#define FLV    7
#define MPEG1  8
#define MKV    9
#define RAW    10
#define AVI    11
#define ASF    12

static const struct { const char *title; int tag; } encap_formats[13] = {
    { "MPEG-TS",  MPEGTS }, { "Webm",   WEBM },  { "Ogg/Ogm", OGG },
    { "MP4/MOV",  MP4 },    { "MPEG-PS", MPEGPS }, { "MJPEG",  MJPEG },
    { "WAV",      WAV },    { "FLV",    FLV },   { "MPEG 1",  MPEG1 },
    { "MKV",      MKV },    { "RAW",    RAW },   { "AVI",     AVI },
    { "ASF/WMV",  ASF },
};

static const struct { const char *title; const char *value; }
video_codecs[14] = {
    { "MPEG-1", "mpgv" }, { "MPEG-2", "mp2v" }, { "MPEG-4", "mp4v" },
    { "DIVX 1", "DIV1" }, { "DIVX 2", "DIV2" }, { "DIVX 3", "DIV3" },
    { "H.263",  "H263" }, { "H.264",  "h264" }, { "VP8",    "VP80" },
    { "WMV1",   "WMV1" }, { "WMV2",   "WMV2" }, { "M-JPEG", "MJPG" },
    { "Theora", "theo" }, { "Dirac",  "drac" },
};

static const struct { const char *title; const char *value; }
audio_codecs[9] = {
    { "MPEG Audio", "mpga" }, { "MP3",  "mp3" },
    { "MPEG 4 Audio (AAC)", "mp4a" },
    { "A52/AC-3", "a52" }, { "Vorbis", "vorb" }, { "Flac", "flac" },
    { "Speex", "spx" }, { "WAV", "s16l" }, { "WMA2", "wma2" },
};

static const struct { const char *title; const char *value; }
subs_codecs[2] = {
    { "DVB subtitle", "dvbs" }, { "T.140", "t140" },
};

static const char *const scale_values[8] =
    { "1", "0.25", "0.5", "0.75", "1.25", "1.5", "1.75", "2" };
static const char *const samplerates[5] =
    { "8000", "11025", "22050", "44100", "48000" };

/* drop-accepting media box content */
@interface VLCLegacyCASDropView : NSView
{
@public
    VLCLegacyConvertAndSave *controller;   /* weak */
}
@end

@implementation VLCLegacyCASDropView
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    if ([[[sender draggingPasteboard] types]
            containsObject:NSFilenamesPboardType])
        return NSDragOperationCopy;
    return NSDragOperationNone;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    NSArray *files = [[sender draggingPasteboard]
        propertyListForType:NSFilenamesPboardType];
    if (![files count])
        return NO;
    NSArray *sorted = [files sortedArrayUsingSelector:
        @selector(caseInsensitiveCompare:)];
    [controller performSelector:@selector(setMediaPath:)
                     withObject:[sorted objectAtIndex:0]];
    return YES;
}
@end

@implementation VLCLegacyConvertAndSave

+ (void)initialize
{
    if (self != [VLCLegacyConvertAndSave class])
        return;
    /* the 3.0.23 default profile set, byte for byte */
    NSArray *profiles = [NSArray arrayWithObjects:
        @"mp4;1;1;0;h264;0;0;0;0;0;mpga;128;2;44100;0;1",
        @"webm;1;1;0;VP80;2000;0;0;0;0;vorb;128;2;44100;0;1",
        @"ts;1;1;0;h264;800;1;0;0;0;mpga;128;2;44100;0;0",
        @"ts;1;1;0;drac;800;1;0;0;0;mpga;128;2;44100;0;0",
        @"ogg;1;1;0;theo;800;1;0;0;0;vorb;128;2;44100;0;0",
        @"ogg;1;1;0;theo;800;1;0;0;0;flac;128;2;44100;0;0",
        @"ts;1;1;0;mp2v;800;1;0;0;0;mpga;128;2;44100;0;0",
        @"asf;1;1;0;WMV2;800;1;0;0;0;wma2;128;2;44100;0;0",
        @"asf;1;1;0;DIV3;800;1;0;0;0;mp3;128;2;44100;0;0",
        @"ogg;0;1;0;none;800;1;0;0;0;vorb;128;2;44100;none;0",
        @"raw;0;1;0;none;800;1;0;0;0;mp3;128;2;44100;none;0",
        @"mp4;0;1;0;none;800;1;0;0;0;mpga;128;2;44100;none;0",
        @"raw;0;1;0;none;800;1;0;0;0;flac;128;2;44100;none;0",
        @"wav;0;1;0;none;800;1;0;0;0;s16l;128;2;44100;none;0", nil];
    NSArray *names = [NSArray arrayWithObjects:
        @"Video - H.264 + MP3 (MP4)",
        @"Video - VP80 + Vorbis (Webm)",
        @"Video - H.264 + MP3 (TS)",
        @"Video - Dirac + MP3 (TS)",
        @"Video - Theora + Vorbis (OGG)",
        @"Video - Theora + Flac (OGG)",
        @"Video - MPEG-2 + MPGA (TS)",
        @"Video - WMV + WMA (ASF)",
        @"Video - DIV3 + MP3 (ASF)",
        @"Audio - Vorbis (OGG)",
        @"Audio - MP3",
        @"Audio - MP3 (MP4)",
        @"Audio - FLAC",
        @"Audio - CD", nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:
        [NSDictionary dictionaryWithObjectsAndKeys:
            profiles, CAS_PROFILES_KEY,
            names, CAS_PROFILE_NAMES_KEY, nil]];
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
{
    if (self = [super init]) {
        core = [interaction retain];
        p_intf = [interaction intf];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        profileNames = [[NSMutableArray alloc] initWithArray:
            [defaults arrayForKey:CAS_PROFILE_NAMES_KEY]];
        profileValueList = [[NSMutableArray alloc] initWithArray:
            [defaults arrayForKey:CAS_PROFILES_KEY]];
        currentProfile = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [fileDestinationView release];
    [streamDestinationView release];
    [window release];
    [customizePanel release];
    [streamPanel release];
    [MRL release];
    [mediaName release];
    [outputDestination release];
    [profileNames release];
    [profileValueList release];
    [currentProfile release];
    [core release];
    [super dealloc];
}

/*****************************************************************************
 * small control factories (plain aqua)
 *****************************************************************************/

static NSTextField *label(NSView *parent, NSString *text, NSRect frame,
                          BOOL bold)
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame]
        autorelease];
    [field setEditable:NO];
    [field setBordered:NO];
    [field setDrawsBackground:NO];
    [[field cell] setFont:bold ? [NSFont boldSystemFontOfSize:12]
                                : [NSFont systemFontOfSize:11]];
    VLCLegacySetCellLineBreakMode([field cell], NSLineBreakByTruncatingTail);
    [field setStringValue:text];
    [parent addSubview:field];
    return field;
}

static NSTextField *editField(NSView *parent, NSRect frame, id target)
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame]
        autorelease];
    [[field cell] setControlSize:NSSmallControlSize];
    [[field cell] setFont:[NSFont systemFontOfSize:
        VLCLegacySystemFontSizeForControlSize(NSSmallControlSize)]];
    [[field cell] setWraps:NO];
    [[field cell] setScrollable:YES];
    [parent addSubview:field];
    (void)target;
    return field;
}

static NSButton *pushButton(NSView *parent, NSString *title, NSRect frame,
                            id target, SEL action)
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [button setTarget:target];
    [button setAction:action];
    [parent addSubview:button];
    return button;
}

static NSButton *checkBox(NSView *parent, NSString *title, NSRect frame,
                          id target, SEL action)
{
    NSButton *box = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [box setButtonType:NSSwitchButton];
    [box setTitle:title];
    [[box cell] setControlSize:NSSmallControlSize];
    [[box cell] setFont:[NSFont systemFontOfSize:
        VLCLegacySystemFontSizeForControlSize(NSSmallControlSize)]];
    [box setTarget:target];
    [box setAction:action];
    [parent addSubview:box];
    return box;
}

static NSPopUpButton *popup(NSView *parent, NSRect frame)
{
    NSPopUpButton *button = [[[NSPopUpButton alloc] initWithFrame:frame
                                                        pullsDown:NO]
        autorelease];
    [[button cell] setControlSize:NSSmallControlSize];
    [[button cell] setFont:[NSFont systemFontOfSize:
        VLCLegacySystemFontSizeForControlSize(NSSmallControlSize)]];
    [parent addSubview:button];
    return button;
}

/*****************************************************************************
 * main window
 *****************************************************************************/

- (void)buildWindow
{
    window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 620, 400)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:_NS("Convert & Stream")];
    [window setReleasedWhenClosed:NO];
    NSView *content = [window contentView];

    /* --- media selection --- */
    NSBox *mediaBox = [[[NSBox alloc]
        initWithFrame:NSMakeRect(17, 290, 586, 96)] autorelease];
    [mediaBox setTitle:@""];
    [mediaBox setBoxType:NSBoxPrimary];
    [content addSubview:mediaBox];

    VLCLegacyCASDropView *dropView = [[[VLCLegacyCASDropView alloc]
        initWithFrame:[[mediaBox contentView] bounds]] autorelease];
    dropView->controller = self;
    [dropView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [dropView registerForDraggedTypes:
        [NSArray arrayWithObject:NSFilenamesPboardType]];
    [[mediaBox contentView] addSubview:dropView];

    mediaLabel = label(dropView, _NS("Drop media here"),
                       NSMakeRect(16, 40, 400, 17), YES);
    openMediaButton = pushButton(dropView, _NS("Open media..."),
                                 NSMakeRect(410, 32, 150, 28),
                                 self, @selector(openMedia:));

    /* --- profile row --- */
    label(content, _NS("Choose Profile"), NSMakeRect(20, 254, 150, 17), YES);
    profilePopup = popup(content, NSMakeRect(170, 248, 280, 24));
    [profilePopup setTarget:self];
    [profilePopup setAction:@selector(switchProfile:)];
    pushButton(content, _NS("Customize..."),
               NSMakeRect(460, 244, 140, 28),
               self, @selector(customizeProfile:));

    /* --- destination --- */
    destinationBox = [[[NSBox alloc]
        initWithFrame:NSMakeRect(17, 66, 586, 166)] autorelease];
    [destinationBox setTitle:_NS("Choose Destination")];
    [content addSubview:destinationBox];
    NSView *destContent = [destinationBox contentView];
    NSRect destBounds = [destContent bounds];

    destinationFileButton = pushButton(destContent, _NS("Save as File"),
        NSMakeRect(destBounds.size.width / 2 - 220, 56, 200, 32),
        self, @selector(iWantAFile:));
    destinationStreamButton = pushButton(destContent, _NS("Stream"),
        NSMakeRect(destBounds.size.width / 2 + 20, 56, 200, 32),
        self, @selector(iWantAStream:));
    /* small "x" reverting the destination choice: drawn cross (a text
     * push button rendered as a clipped bevel there) */
    destinationCancelButton = [[[VLCLegacyHUDCloseButton alloc]
        initWithFrame:NSMakeRect(destBounds.size.width - 30,
                                 destBounds.size.height - 28, 18, 18)]
        autorelease];
    [destinationCancelButton setDarkStyle:YES];
    [destinationCancelButton setTarget:self
                                action:@selector(cancelDestination:)];
    [destContent addSubview:destinationCancelButton];
    VLCLegacySetViewHidden(destinationCancelButton, YES);

    /* file sub-view -- RETAINED: it lives outside the view tree until
     * the user picks a destination (autorelease alone = use after free
     * on the first click) */
    fileDestinationView = [[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, destBounds.size.width,
                                 destBounds.size.height - 24)];
    fileDestinationLabel = label(fileDestinationView,
        _NS("Choose an output location"),
        NSMakeRect(20, 70, destBounds.size.width - 200, 17), NO);
    pushButton(fileDestinationView, _NS("Browse..."),
               NSMakeRect(destBounds.size.width - 160, 62, 130, 28),
               self, @selector(browseFileDestination:));

    /* stream sub-view -- RETAINED, same reason as above */
    streamDestinationView = [[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, destBounds.size.width,
                                 destBounds.size.height - 24)];
    streamSummaryLabel = label(streamDestinationView,
        _NS("Select Streaming Method"),
        NSMakeRect(20, 70, destBounds.size.width - 220, 17), NO);
    pushButton(streamDestinationView, _NS("Setup Streaming..."),
               NSMakeRect(destBounds.size.width - 190, 62, 160, 28),
               self, @selector(showStreamPanel:));

    /* --- go --- */
    okButton = pushButton(content, _NS("Go!"),
                          NSMakeRect(490, 18, 110, 32),
                          self, @selector(finalizePanel:));
    [okButton setKeyEquivalent:@"\r"];
    [okButton setEnabled:NO];

    [self recreateProfilePopup];
    [self selectProfileAtIndex:0];
    [window center];
}

- (void)showWindow
{
    if (!window)
        [self buildWindow];
    [window makeKeyAndOrderFront:nil];
}

- (void)updateOKButton
{
    BOOL b_streamingReady = !b_streaming || [outputDestination length] > 0;
    [okButton setEnabled:
        [outputDestination length] > 0 && [MRL length] > 0
        && b_streamingReady];
    [okButton setTitle:b_streaming ? _NS("Stream")
        : ([outputDestination length] ? _NS("Save") : _NS("Go!"))];
}

/*****************************************************************************
 * media selection
 *****************************************************************************/

- (void)setMediaPath:(NSString *)path
{
    char *psz_uri = vlc_path2uri([path UTF8String], "file");
    if (!psz_uri)
        return;
    [MRL release];
    MRL = [[NSString stringWithUTF8String:psz_uri] retain];
    free(psz_uri);
    [mediaName release];
    mediaName = [[[NSFileManager defaultManager] displayNameAtPath:path]
        retain];
    [mediaLabel setStringValue:mediaName ? mediaName : path];
    [self updateOKButton];
}

- (void)openMedia:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:YES];
    [panel setCanChooseDirectories:NO];
    [panel setResolvesAliases:YES];
    [panel setAllowsMultipleSelection:NO];
    if ([panel runModal] != NSOKButton)
        return;
    [self setMediaPath:[[[panel URLs] objectAtIndex:0] path]];
}

/*****************************************************************************
 * destination
 *****************************************************************************/

- (void)iWantAFile:(id)sender
{
    VLCLegacySetViewHidden(destinationFileButton, YES);
    VLCLegacySetViewHidden(destinationStreamButton, YES);
    [[destinationBox contentView] addSubview:fileDestinationView];
    VLCLegacySetViewHidden(destinationCancelButton, NO);
    b_streaming = NO;
    [self updateOKButton];
}

- (void)iWantAStream:(id)sender
{
    VLCLegacySetViewHidden(destinationFileButton, YES);
    VLCLegacySetViewHidden(destinationStreamButton, YES);
    [[destinationBox contentView] addSubview:streamDestinationView];
    VLCLegacySetViewHidden(destinationCancelButton, NO);
    b_streaming = YES;
    [self updateOKButton];
}

- (void)cancelDestination:(id)sender
{
    if ([fileDestinationView superview])
        [fileDestinationView removeFromSuperview];
    if ([streamDestinationView superview])
        [streamDestinationView removeFromSuperview];
    VLCLegacySetViewHidden(destinationCancelButton, YES);
    VLCLegacySetViewHidden(destinationFileButton, NO);
    VLCLegacySetViewHidden(destinationStreamButton, NO);
    [outputDestination release];
    outputDestination = nil;
    [fileDestinationLabel setStringValue:_NS("Choose an output location")];
    [streamSummaryLabel setStringValue:_NS("Select Streaming Method")];
    b_streaming = NO;
    [self updateOKButton];
}

- (int)currentEncapsulationTag
{
    NSCell *cell = [encapMatrix selectedCell];
    return cell ? (int)[cell tag] : MPEGTS;
}

/* mux value / file extension for the selected encapsulation cell */
- (NSString *)encapsulationFormatAsExtension:(BOOL)b_extension
{
    switch ([self currentEncapsulationTag]) {
    case MPEGTS: return @"ts";
    case WEBM:   return @"webm";
    case OGG:    return @"ogg";
    case MP4:    return b_extension ? @"m4v" : @"mp4";
    case MPEGPS: return b_extension ? @"mpg" : @"ps";
    case MJPEG:  return @"mjpeg";
    case WAV:    return @"wav";
    case FLV:    return @"flv";
    case MPEG1:  return b_extension ? @"mpg" : @"mpeg1";
    case MKV:    return @"mkv";
    case RAW:    return @"raw";
    case AVI:    return @"avi";
    case ASF:    return @"asf";
    }
    return @"ts";
}

- (void)browseFileDestination:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setCanSelectHiddenExtension:YES];
    if ([panel respondsToSelector:@selector(setCanCreateDirectories:)])
        [panel setCanCreateDirectories:YES];
    /* no clever guess for RAW (3.0 does the same) */
    NSString *file = mediaName ? mediaName : _NS("Untitled");
    if ([self currentEncapsulationTag] != RAW)
        file = [file stringByAppendingFormat:@".%@",
                [self encapsulationFormatAsExtension:YES]];
    if ([panel runModalForDirectory:nil file:file]
            != NSFileHandlingPanelOKButton)
        return;
    [outputDestination release];
    outputDestination = [[panel filename] retain];
    [fileDestinationLabel setStringValue:
        [[NSFileManager defaultManager]
            displayNameAtPath:outputDestination]];
    [self updateOKButton];
}

/*****************************************************************************
 * profiles
 *****************************************************************************/

- (void)recreateProfilePopup
{
    [profilePopup removeAllItems];
    unsigned i;
    for (i = 0; i < [profileNames count]; i++)
        [[profilePopup menu] addItem:[[[NSMenuItem alloc]
            initWithTitle:[profileNames objectAtIndex:i]
                   action:nil keyEquivalent:@""] autorelease]];
    [profilePopup addItemWithTitle:_NS("Custom")];
    [[profilePopup menu] addItem:[NSMenuItem separatorItem]];
    NSMenuItem *item = [[[NSMenuItem alloc]
        initWithTitle:_NS("Organize Profiles...")
               action:@selector(deleteProfileAction:)
        keyEquivalent:@""] autorelease];
    [item setTarget:self];
    [[profilePopup menu] addItem:item];
}

- (void)selectProfileAtIndex:(NSInteger)index
{
    if (index < 0 || (unsigned)index >= [profileValueList count])
        return;
    [profilePopup selectItemAtIndex:index];
    [self resetCustomizationBasedOnProfile:
        [profileValueList objectAtIndex:index]];
}

- (void)switchProfile:(id)sender
{
    NSInteger index = [profilePopup indexOfSelectedItem];
    if (index >= 0 && (unsigned)index < [profileValueList count])
        [self resetCustomizationBasedOnProfile:
            [profileValueList objectAtIndex:index]];
}

- (void)deleteProfileAction:(id)sender
{
    /* the popup selection moved onto the action item; restore it */
    [self recreateProfilePopup];

    NSInteger index = VLCLegacyRunPopupPrompt(
        _NS("Remove a profile"),
        _NS("Select the profile you would like to remove:"),
        _NS("Remove"), _NS("Cancel"), profileNames);
    if (index < 0 || (unsigned)index >= [profileValueList count])
        return;
    [profileNames removeObjectAtIndex:index];
    [profileValueList removeObjectAtIndex:index];
    [self storeProfilesOnDisk];
    [self recreateProfilePopup];
    [self selectProfileAtIndex:0];
}

- (void)storeProfilesOnDisk
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:profileNames forKey:CAS_PROFILE_NAMES_KEY];
    [defaults setObject:profileValueList forKey:CAS_PROFILES_KEY];
    [defaults synchronize];
}

/*****************************************************************************
 * customize panel
 *****************************************************************************/

- (NSView *)buildEncapTab
{
    NSView *view = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 460, 330)] autorelease];

    NSButtonCell *prototype = [[[NSButtonCell alloc] init] autorelease];
    [prototype setButtonType:NSRadioButton];
    [prototype setControlSize:NSSmallControlSize];
    [prototype setFont:[NSFont systemFontOfSize:
        VLCLegacySystemFontSizeForControlSize(NSSmallControlSize)]];
    [prototype setTitle:@""];

    encapMatrix = [[[NSMatrix alloc]
        initWithFrame:NSMakeRect(40, 40, 380, 250)
                 mode:NSRadioModeMatrix
            prototype:prototype
         numberOfRows:7
      numberOfColumns:2] autorelease];
    [encapMatrix setCellSize:NSMakeSize(180, 22)];
    [encapMatrix setIntercellSpacing:NSMakeSize(12, 10)];
    int i;
    for (i = 0; i < 13; i++) {
        NSButtonCell *cell = [encapMatrix cellAtRow:i % 7 column:i / 7];
        [cell setTitle:[NSString stringWithUTF8String:
            encap_formats[i].title]];
        [cell setTag:encap_formats[i].tag];
    }
    /* 14th cell: blank and disabled, like the 3.0 window */
    NSButtonCell *blank = [encapMatrix cellAtRow:6 column:1];
    [blank setTitle:@""];
    [blank setEnabled:NO];
    [blank setTransparent:YES];
    [view addSubview:encapMatrix];
    return view;
}

- (NSView *)buildVideoTab
{
    NSView *view = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 460, 330)] autorelease];
    vidCheckbox = checkBox(view, _NS("Video"),
                           NSMakeRect(20, 300, 140, 18),
                           self, @selector(videoSettingsChanged:));
    vidKeepCheckbox = checkBox(view, _NS("Keep original video track"),
                               NSMakeRect(40, 276, 260, 18),
                               self, @selector(videoSettingsChanged:));

    label(view, _NS("Codec"), NSMakeRect(40, 244, 90, 15), NO);
    vidCodecPopup = popup(view, NSMakeRect(140, 240, 180, 22));
    int i;
    for (i = 0; i < 14; i++) {
        [vidCodecPopup addItemWithTitle:
            [NSString stringWithUTF8String:video_codecs[i].title]];
        [[vidCodecPopup lastItem] setRepresentedObject:
            [NSString stringWithUTF8String:video_codecs[i].value]];
    }
    label(view, _NS("Bitrate"), NSMakeRect(40, 214, 90, 15), NO);
    vidBitrateField = editField(view, NSMakeRect(140, 210, 80, 20), self);
    label(view, _NS("Frame rate"), NSMakeRect(240, 214, 90, 15), NO);
    vidFramerateField = editField(view, NSMakeRect(336, 210, 80, 20), self);

    NSBox *resolutionBox = [[[NSBox alloc]
        initWithFrame:NSMakeRect(30, 60, 400, 130)] autorelease];
    [resolutionBox setTitle:_NS("Resolution")];
    [view addSubview:resolutionBox];
    NSView *resolution = [resolutionBox contentView];
    NSTextField *hint = label(resolution,
        _NS("You just need to fill one of the three following parameters, "
            "VLC will autodetect the other using the original aspect ratio"),
        NSMakeRect(12, 62, 370, 38), NO);
    [[hint cell] setWraps:YES];
    VLCLegacySetCellLineBreakMode([hint cell], NSLineBreakByWordWrapping);
    label(resolution, _NS("Width"), NSMakeRect(12, 30, 70, 15), NO);
    vidWidthField = editField(resolution, NSMakeRect(84, 26, 60, 20), self);
    label(resolution, _NS("Height"), NSMakeRect(160, 30, 70, 15), NO);
    vidHeightField = editField(resolution, NSMakeRect(232, 26, 60, 20),
                               self);
    label(resolution, _NS("Scale"), NSMakeRect(12, 2, 70, 15), NO);
    vidScalePopup = popup(resolution, NSMakeRect(84, -2, 100, 22));
    for (i = 0; i < 8; i++)
        [vidScalePopup addItemWithTitle:
            [NSString stringWithUTF8String:scale_values[i]]];
    return view;
}

- (NSView *)buildAudioTab
{
    NSView *view = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 460, 330)] autorelease];
    audCheckbox = checkBox(view, _NS("Audio"),
                           NSMakeRect(20, 300, 140, 18),
                           self, @selector(audioSettingsChanged:));
    audKeepCheckbox = checkBox(view, _NS("Keep original audio track"),
                               NSMakeRect(40, 276, 260, 18),
                               self, @selector(audioSettingsChanged:));

    label(view, _NS("Codec"), NSMakeRect(40, 244, 90, 15), NO);
    audCodecPopup = popup(view, NSMakeRect(140, 240, 200, 22));
    int i;
    for (i = 0; i < 9; i++) {
        [audCodecPopup addItemWithTitle:
            [NSString stringWithUTF8String:audio_codecs[i].title]];
        [[audCodecPopup lastItem] setRepresentedObject:
            [NSString stringWithUTF8String:audio_codecs[i].value]];
    }
    label(view, _NS("Bitrate"), NSMakeRect(40, 214, 90, 15), NO);
    audBitrateField = editField(view, NSMakeRect(140, 210, 80, 20), self);
    label(view, _NS("Channels"), NSMakeRect(40, 186, 90, 15), NO);
    audChannelsField = editField(view, NSMakeRect(140, 182, 80, 20), self);
    label(view, _NS("Samplerate"), NSMakeRect(40, 158, 90, 15), NO);
    audSampleratePopup = popup(view, NSMakeRect(140, 154, 120, 22));
    for (i = 0; i < 5; i++)
        [audSampleratePopup addItemWithTitle:
            [NSString stringWithUTF8String:samplerates[i]]];
    return view;
}

- (NSView *)buildSubsTab
{
    NSView *view = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 460, 330)] autorelease];
    subsCheckbox = checkBox(view, _NS("Subtitles"),
                            NSMakeRect(20, 300, 200, 18),
                            self, @selector(subSettingsChanged:));
    subsPopup = popup(view, NSMakeRect(40, 266, 200, 22));
    int i;
    for (i = 0; i < 2; i++) {
        [subsPopup addItemWithTitle:
            [NSString stringWithUTF8String:subs_codecs[i].title]];
        [[subsPopup lastItem] setRepresentedObject:
            [NSString stringWithUTF8String:subs_codecs[i].value]];
    }
    subsOverlayCheckbox = checkBox(view,
        _NS("Overlay subtitles on the video"),
        NSMakeRect(40, 238, 280, 18), self, nil);
    return view;
}

- (void)buildCustomizePanel
{
    customizePanel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 500, 452)
                  styleMask:NSTitledWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [customizePanel setTitle:_NS("Customize...")];
    [customizePanel setReleasedWhenClosed:NO];
    NSView *content = [customizePanel contentView];

    NSTabView *tabView = [[[NSTabView alloc]
        initWithFrame:NSMakeRect(10, 56, 480, 386)] autorelease];
    static const char *const tab_titles[4] = {
        N_("Encapsulation"), N_("Video codec"), N_("Audio codec"),
        N_("Subtitles"),
    };
    NSView *(*builders)(id, SEL) = NULL;
    (void)builders;
    SEL selectors[4] = { @selector(buildEncapTab),
                         @selector(buildVideoTab),
                         @selector(buildAudioTab),
                         @selector(buildSubsTab) };
    int i;
    for (i = 0; i < 4; i++) {
        NSTabViewItem *item = [[[NSTabViewItem alloc]
            initWithIdentifier:[NSNumber numberWithInt:i]] autorelease];
        [item setLabel:_NS(tab_titles[i])];
        [item setView:[self performSelector:selectors[i]]];
        [tabView addTabViewItem:item];
    }
    [content addSubview:tabView];

    pushButton(content, _NS("Save as new Profile..."),
               NSMakeRect(14, 12, 250, 28),
               self, @selector(newProfileAction:));
    NSButton *cancelButton = pushButton(content, _NS("Cancel"),
        NSMakeRect(278, 12, 100, 28), self,
        @selector(closeCustomizationCancel:));
    [cancelButton setKeyEquivalent:@"\033"];
    NSButton *applyButton = pushButton(content, _NS("Apply"),
        NSMakeRect(386, 12, 100, 28), self,
        @selector(closeCustomizationApply:));
    [applyButton setKeyEquivalent:@"\r"];
    [customizePanel center];
}

- (void)customizeProfile:(id)sender
{
    if (!customizePanel) {
        [self buildCustomizePanel];
        /* the panel controls did not exist when the initial profile was
         * selected: load it again into them */
        NSInteger index = [profilePopup indexOfSelectedItem];
        if (index >= 0 && (unsigned)index < [profileValueList count])
            [self resetCustomizationBasedOnProfile:
                [profileValueList objectAtIndex:index]];
    }
    [customizePanel makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:customizePanel];
    [customizePanel orderOut:nil];
}

- (void)closeCustomizationApply:(id)sender
{
    [self updateCurrentProfile];
    /* the settings no longer match a stored profile */
    [profilePopup selectItemAtIndex:
        (NSInteger)[profileNames count]];   /* the "Custom" entry */
    [NSApp stopModal];
}

- (void)closeCustomizationCancel:(id)sender
{
    NSInteger index = [profilePopup indexOfSelectedItem];
    if (index >= 0 && (unsigned)index < [profileValueList count])
        [self resetCustomizationBasedOnProfile:
            [profileValueList objectAtIndex:index]];
    [NSApp stopModal];
}

- (void)videoSettingsChanged:(id)sender
{
    BOOL enabled = [vidCheckbox state] == NSOnState
                && [vidKeepCheckbox state] == NSOffState;
    [vidKeepCheckbox setEnabled:[vidCheckbox state] == NSOnState];
    [vidCodecPopup setEnabled:enabled];
    [vidBitrateField setEnabled:enabled];
    [vidFramerateField setEnabled:enabled];
    [vidWidthField setEnabled:enabled];
    [vidHeightField setEnabled:enabled];
    [vidScalePopup setEnabled:enabled];
}

- (void)audioSettingsChanged:(id)sender
{
    BOOL enabled = [audCheckbox state] == NSOnState
                && [audKeepCheckbox state] == NSOffState;
    [audKeepCheckbox setEnabled:[audCheckbox state] == NSOnState];
    [audCodecPopup setEnabled:enabled];
    [audBitrateField setEnabled:enabled];
    [audChannelsField setEnabled:enabled];
    [audSampleratePopup setEnabled:enabled];
}

- (void)subSettingsChanged:(id)sender
{
    BOOL enabled = [subsCheckbox state] == NSOnState;
    [subsPopup setEnabled:enabled];
    [subsOverlayCheckbox setEnabled:enabled];
}

- (void)selectPopup:(NSPopUpButton *)codecPopup value:(NSString *)value
{
    NSInteger i;
    for (i = 0; i < [codecPopup numberOfItems]; i++) {
        if ([[[codecPopup itemAtIndex:i] representedObject]
                isEqualToString:value]) {
            [codecPopup selectItemAtIndex:i];
            return;
        }
    }
}

- (void)selectEncapsulationFormat:(NSString *)format
{
    int tag = MPEGTS;
    const char *psz = [format UTF8String];
    if (!strcmp(psz, "ts"))          tag = MPEGTS;
    else if (!strcmp(psz, "webm"))   tag = WEBM;
    else if (!strcmp(psz, "ogg") || !strcmp(psz, "ogm")) tag = OGG;
    else if (!strcmp(psz, "mp4") || !strcmp(psz, "mov")) tag = MP4;
    else if (!strcmp(psz, "ps"))     tag = MPEGPS;
    else if (!strcmp(psz, "mjpeg") || !strcmp(psz, "mpjpeg")) tag = MJPEG;
    else if (!strcmp(psz, "wav"))    tag = WAV;
    else if (!strcmp(psz, "flv"))    tag = FLV;
    else if (!strcmp(psz, "mpeg1"))  tag = MPEG1;
    else if (!strcmp(psz, "mkv"))    tag = MKV;
    else if (!strcmp(psz, "raw"))    tag = RAW;
    else if (!strcmp(psz, "avi"))    tag = AVI;
    else if (!strcmp(psz, "asf") || !strcmp(psz, "wmv")) tag = ASF;
    [encapMatrix selectCellWithTag:tag];
}

/* loads a 16-field profile string into currentProfile + the panel */
- (void)resetCustomizationBasedOnProfile:(NSString *)profileString
{
    NSArray *components =
        [profileString componentsSeparatedByString:@";"];
    if ([components count] != 16) {
        msg_Err(p_intf, "CAS: the requested profile is invalid");
        return;
    }
    [currentProfile setArray:components];

    /* the panel may not exist yet; messages to nil are no-ops but the
     * currentProfile array above is what composedOptions reads */
    [self selectEncapsulationFormat:[components objectAtIndex:0]];
    [vidCheckbox setState:[[components objectAtIndex:1] intValue]
        ? NSOnState : NSOffState];
    [audCheckbox setState:[[components objectAtIndex:2] intValue]
        ? NSOnState : NSOffState];
    [subsCheckbox setState:[[components objectAtIndex:3] intValue]
        ? NSOnState : NSOffState];

    NSString *vidCodec = [components objectAtIndex:4];
    [vidKeepCheckbox setState:
        [vidCodec isEqualToString:@"copy"] ? NSOnState : NSOffState];
    if (![vidCodec isEqualToString:@"none"]
     && ![vidCodec isEqualToString:@"copy"])
        [self selectPopup:vidCodecPopup value:vidCodec];
    [vidBitrateField setStringValue:[components objectAtIndex:5]];
    /* scale: select matching title, default "1" */
    [vidScalePopup selectItemWithTitle:[components objectAtIndex:6]];
    if ([vidScalePopup indexOfSelectedItem] < 0)
        [vidScalePopup selectItemAtIndex:0];
    [vidFramerateField setStringValue:[components objectAtIndex:7]];
    [vidWidthField setStringValue:[components objectAtIndex:8]];
    [vidHeightField setStringValue:[components objectAtIndex:9]];

    NSString *audCodec = [components objectAtIndex:10];
    [audKeepCheckbox setState:
        [audCodec isEqualToString:@"copy"] ? NSOnState : NSOffState];
    if (![audCodec isEqualToString:@"none"]
     && ![audCodec isEqualToString:@"copy"])
        [self selectPopup:audCodecPopup value:audCodec];
    [audBitrateField setStringValue:[components objectAtIndex:11]];
    [audChannelsField setStringValue:[components objectAtIndex:12]];
    [audSampleratePopup selectItemWithTitle:
        [components objectAtIndex:13]];
    if ([audSampleratePopup indexOfSelectedItem] < 0)
        [audSampleratePopup selectItemAtIndex:3];   /* 44100 */

    NSString *subsCodec = [components objectAtIndex:14];
    if (![subsCodec isEqualToString:@"none"]
     && ![subsCodec isEqualToString:@"0"])
        [self selectPopup:subsPopup value:subsCodec];
    [subsOverlayCheckbox setState:
        [[components objectAtIndex:15] intValue] ? NSOnState : NSOffState];

    [self videoSettingsChanged:nil];
    [self audioSettingsChanged:nil];
    [self subSettingsChanged:nil];
}

/* reads the panel back into currentProfile (16 fields) */
- (void)updateCurrentProfile
{
    [currentProfile removeAllObjects];
    [currentProfile addObject:[self encapsulationFormatAsExtension:NO]];
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [vidCheckbox state] == NSOnState]];
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [audCheckbox state] == NSOnState]];
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [subsCheckbox state] == NSOnState]];

    if ([vidKeepCheckbox state] == NSOnState)
        [currentProfile addObject:@"copy"];
    else {
        NSString *codec =
            [[vidCodecPopup selectedItem] representedObject];
        [currentProfile addObject:codec ? codec : @"none"];
    }
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [vidBitrateField intValue]]];
    [currentProfile addObject:[[vidScalePopup titleOfSelectedItem] length]
        ? [vidScalePopup titleOfSelectedItem] : @"1"];
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [vidFramerateField intValue]]];
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [vidWidthField intValue]]];
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [vidHeightField intValue]]];

    if ([audKeepCheckbox state] == NSOnState)
        [currentProfile addObject:@"copy"];
    else {
        NSString *codec =
            [[audCodecPopup selectedItem] representedObject];
        [currentProfile addObject:codec ? codec : @"none"];
    }
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [audBitrateField intValue]]];
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [audChannelsField intValue]]];
    [currentProfile addObject:[[audSampleratePopup titleOfSelectedItem]
        length] ? [audSampleratePopup titleOfSelectedItem] : @"44100"];

    if ([subsCheckbox state] == NSOnState) {
        NSString *codec = [[subsPopup selectedItem] representedObject];
        [currentProfile addObject:codec ? codec : @"none"];
    } else
        [currentProfile addObject:@"none"];
    [currentProfile addObject:[NSString stringWithFormat:@"%i",
        [subsOverlayCheckbox state] == NSOnState]];
}

- (void)newProfileAction:(id)sender
{
    NSString *name = VLCLegacyRunTextPrompt(
        _NS("Save as new profile"),
        _NS("Enter a name for the new profile:"),
        _NS("Save"), _NS("Cancel"), @"");
    if (![name length])
        return;
    [self updateCurrentProfile];
    [profileNames addObject:name];
    [profileValueList addObject:
        [currentProfile componentsJoinedByString:@";"]];
    [self storeProfilesOnDisk];
    [self recreateProfilePopup];
    [profilePopup selectItemAtIndex:(NSInteger)[profileNames count] - 1];
}

/*****************************************************************************
 * stream panel
 *****************************************************************************/

- (void)buildStreamPanel
{
    streamPanel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 460, 380)
                  styleMask:NSTitledWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [streamPanel setTitle:_NS("Stream Destination")];
    [streamPanel setReleasedWhenClosed:NO];
    NSView *content = [streamPanel contentView];

    label(content, _NS("Stream Destination"),
          NSMakeRect(16, 344, 300, 17), YES);
    label(content, _NS("Type"), NSMakeRect(30, 312, 90, 15), NO);
    streamTypePopup = popup(content, NSMakeRect(130, 308, 140, 22));
    [streamTypePopup addItemWithTitle:@"HTTP"];
    [streamTypePopup addItemWithTitle:@"MMSH"];
    [streamTypePopup addItemWithTitle:@"RTP"];
    [streamTypePopup addItemWithTitle:@"UDP"];
    [streamTypePopup setTarget:self];
    [streamTypePopup setAction:@selector(streamTypeToggle:)];

    label(content, _NS("Address"), NSMakeRect(30, 284, 90, 15), NO);
    streamAddressField = editField(content,
        NSMakeRect(130, 280, 300, 20), self);
    label(content, _NS("Port"), NSMakeRect(30, 256, 90, 15), NO);
    streamPortField = editField(content,
        NSMakeRect(130, 252, 80, 20), self);
    [streamPortField setStringValue:@"1234"];
    label(content, _NS("TTL"), NSMakeRect(240, 256, 60, 15), NO);
    streamTTLField = editField(content,
        NSMakeRect(300, 252, 60, 20), self);
    [streamTTLField setStringValue:@"1"];
    streamTTLStepper = [[[NSStepper alloc]
        initWithFrame:NSMakeRect(364, 250, 15, 22)] autorelease];
    [streamTTLStepper setMinValue:1];
    [streamTTLStepper setMaxValue:65535];
    [streamTTLStepper setIntValue:1];
    [streamTTLStepper setTarget:self];
    [streamTTLStepper setAction:@selector(ttlStepped:)];
    [content addSubview:streamTTLStepper];

    label(content, _NS("Stream Announcement"),
          NSMakeRect(16, 212, 300, 17), YES);
    streamSAPCheckbox = checkBox(content, _NS("SAP Announcement"),
                                 NSMakeRect(30, 186, 260, 18),
                                 self, @selector(announcementToggle:));
    label(content, _NS("Channel Name"), NSMakeRect(48, 160, 130, 15), NO);
    streamChannelField = editField(content,
        NSMakeRect(184, 156, 246, 20), self);

    NSButtonCell *prototype = [[[NSButtonCell alloc] init] autorelease];
    [prototype setButtonType:NSRadioButton];
    [prototype setFont:[NSFont systemFontOfSize:
        VLCLegacySystemFontSizeForControlSize(NSSmallControlSize)]];
    [prototype setTitle:@""];
    streamSDPMatrix = [[[NSMatrix alloc]
        initWithFrame:NSMakeRect(30, 96, 400, 52)
                 mode:NSRadioModeMatrix
            prototype:prototype
         numberOfRows:2
      numberOfColumns:2] autorelease];
    [streamSDPMatrix setCellSize:NSMakeSize(196, 20)];
    [streamSDPMatrix setIntercellSpacing:NSMakeSize(8, 8)];
    static const struct { const char *title; int tag; } sdp_cells[4] = {
        { N_("None"), 0 }, { N_("HTTP Announcement"), 1 },
        { N_("RTSP Announcement"), 2 }, { N_("Export SDP as file"), 3 },
    };
    int i;
    for (i = 0; i < 4; i++) {
        NSButtonCell *cell = [streamSDPMatrix cellAtRow:i / 2
                                                 column:i % 2];
        [cell setTitle:_NS(sdp_cells[i].title)];
        [cell setTag:sdp_cells[i].tag];
    }
    [streamSDPMatrix setTarget:self];
    [streamSDPMatrix setAction:@selector(announcementToggle:)];
    [content addSubview:streamSDPMatrix];

    label(content, _NS("SDP URL"), NSMakeRect(30, 66, 90, 15), NO);
    streamSDPField = editField(content, NSMakeRect(130, 62, 200, 20), self);
    streamSDPBrowseButton = pushButton(content, _NS("Browse..."),
        NSMakeRect(340, 56, 104, 28), self,
        @selector(sdpFileLocationSelector:));

    NSButton *cancelButton = pushButton(content, _NS("Cancel"),
        NSMakeRect(236, 12, 100, 28), self, @selector(closeStreamCancel:));
    [cancelButton setKeyEquivalent:@"\033"];
    NSButton *okStream = pushButton(content, _NS("Apply"),
        NSMakeRect(344, 12, 100, 28), self, @selector(closeStreamApply:));
    [okStream setKeyEquivalent:@"\r"];

    [streamPanel center];
    [self streamTypeToggle:nil];
}

- (void)ttlStepped:(id)sender
{
    [streamTTLField setIntValue:[streamTTLStepper intValue]];
}

- (void)showStreamPanel:(id)sender
{
    if (!streamPanel)
        [self buildStreamPanel];
    [streamPanel makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:streamPanel];
    [streamPanel orderOut:nil];
}

- (void)streamTypeToggle:(id)sender
{
    NSInteger type = [streamTypePopup indexOfSelectedItem];
    BOOL rtp = type == 2;
    BOOL udp = type == 3;
    [streamTTLField setEnabled:rtp || udp];
    [streamTTLStepper setEnabled:rtp || udp];
    [streamSAPCheckbox setEnabled:rtp || udp];
    [streamSDPMatrix setEnabled:rtp];   /* RTP only */
    [self announcementToggle:nil];
}

- (void)announcementToggle:(id)sender
{
    [streamChannelField setEnabled:
        [streamSAPCheckbox state] == NSOnState
        && [streamSAPCheckbox isEnabled]];
    int sdpTag = [streamSDPMatrix isEnabled]
        ? (int)[[streamSDPMatrix selectedCell] tag] : 0;
    [streamSDPField setEnabled:sdpTag != 0];
    [streamSDPBrowseButton setEnabled:sdpTag == 3];
}

- (void)sdpFileLocationSelector:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    [panel setCanSelectHiddenExtension:YES];
    if ([panel respondsToSelector:@selector(setCanCreateDirectories:)])
        [panel setCanCreateDirectories:YES];
    VLCLegacySetPanelFileType(panel, @"sdp");
    if ([panel runModalForDirectory:nil file:@"stream"]
            == NSFileHandlingPanelOKButton)
        [streamSDPField setStringValue:[panel filename]];
}

- (void)closeStreamCancel:(id)sender
{
    [NSApp stopModal];
}

- (void)closeStreamApply:(id)sender
{
    NSInteger type = [streamTypePopup indexOfSelectedItem];

    if (![[streamAddressField stringValue] length]) {
        NSRunInformationalAlertPanel(_NS("No Address given"), @"%@",
            _NS("OK"), nil, nil,
            _NS("In order to stream, a valid destination address is "
                "required."));
        return;
    }
    if ([streamSAPCheckbox state] == NSOnState
     && [streamSAPCheckbox isEnabled]
     && ![[streamChannelField stringValue] length]) {
        NSRunInformationalAlertPanel(_NS("No Channel Name given"), @"%@",
            _NS("OK"), nil, nil,
            _NS("SAP stream announcement is enabled. However, no channel "
                "name is provided."));
        return;
    }
    if ([streamSDPMatrix isEnabled]
     && [[streamSDPMatrix selectedCell] tag] != 0
     && ![[streamSDPField stringValue] length]) {
        NSRunInformationalAlertPanel(_NS("No SDP URL given"), @"%@",
            _NS("OK"), nil, nil,
            _NS("A SDP export is requested, but no URL is provided."));
        return;
    }

    NSString *summary = [NSString stringWithFormat:
        _NS("%@ stream to %@:%@"),
        [streamTypePopup titleOfSelectedItem],
        [streamAddressField stringValue],
        [streamPortField stringValue]];
    [streamSummaryLabel setStringValue:summary];

    [outputDestination release];
    outputDestination = [[streamAddressField stringValue] retain];
    [self updateOKButton];
    [NSApp stopModal];
}

/*****************************************************************************
 * :sout= composition and playback (port of composedOptions/finalizePanel)
 *****************************************************************************/

- (NSString *)composedOptions
{
    NSMutableString *options = [NSMutableString
        stringWithString:@":sout=#transcode{"];
    BOOL haveVideo = YES;
    BOOL haveAudio = YES;

#define FIELD(x) [currentProfile objectAtIndex:x]
    if ([FIELD(1) intValue]) {
        if (![FIELD(4) isEqualToString:@"copy"]) {
            [options appendFormat:@"vcodec=%@", FIELD(4)];
            if ([FIELD(5) intValue] > 0)
                [options appendFormat:@",vb=%@", FIELD(5)];
            if ([FIELD(6) floatValue] > 0)
                [options appendFormat:@",scale=%@", FIELD(6)];
            if ([FIELD(7) floatValue] > 0)
                [options appendFormat:@",fps=%@", FIELD(7)];
            if ([FIELD(8) intValue] > 0)
                [options appendFormat:@",width=%@", FIELD(8)];
            if ([FIELD(9) intValue] > 0)
                [options appendFormat:@",height=%@", FIELD(9)];
        } else
            haveVideo = NO;
    } else
        [options appendString:@"vcodec=none"];

    if ([FIELD(2) intValue]) {
        if (![FIELD(10) isEqualToString:@"copy"]) {
            if (haveVideo)
                [options appendString:@","];
            [options appendFormat:@"acodec=%@,ab=%@,channels=%@,"
                @"samplerate=%@", FIELD(10), FIELD(11), FIELD(12),
                FIELD(13)];
        } else
            haveAudio = NO;
    } else {
        if (haveVideo)
            [options appendString:@","];
        [options appendString:@"acodec=none"];
    }

    if ([FIELD(3) intValue]) {
        if (haveVideo || haveAudio)
            [options appendString:@","];
        [options appendFormat:@"scodec=%@", FIELD(14)];
        if ([FIELD(15) intValue])
            [options appendString:@",soverlay"];
    }
    [options appendString:@"}"];

    if (!b_streaming) {
        /* escape any double quote in the path */
        NSMutableString *escaped =
            [NSMutableString stringWithString:outputDestination];
        [escaped replaceOccurrencesOfString:@"\"" withString:@"\\\""
                                    options:0
                                      range:NSMakeRange(0,
                                          [escaped length])];
        [options appendFormat:
            @":standard{mux=%@,access=file{no-overwrite},dst=\"%@\"}",
            FIELD(0), escaped];
    } else {
        NSString *destination = [NSString stringWithFormat:@"%@:%@",
            [streamAddressField stringValue],
            [streamPortField stringValue]];
        NSInteger type = streamTypePopup
            ? [streamTypePopup indexOfSelectedItem] : 0;
        if (type == 2)
            [options appendFormat:@":rtp{mux=ts,dst=%@,port=%@",
                [streamAddressField stringValue],
                [streamPortField stringValue]];
        else if (type == 3)
            [options appendFormat:@":standard{mux=ts,dst=%@,access=udp",
                destination];
        else if (type == 1)
            [options appendFormat:@":standard{mux=asfh,dst=%@,access=mmsh",
                destination];
        else
            [options appendFormat:@":standard{mux=%@,dst=%@,access=http",
                FIELD(0), destination];

        if ([streamSAPCheckbox state] == NSOnState
         && [streamSAPCheckbox isEnabled])
            [options appendFormat:@",sap,name=\"%@\"",
                [streamChannelField stringValue]];
        if ([streamSDPMatrix isEnabled]) {
            switch ([[streamSDPMatrix selectedCell] tag]) {
            case 1:
                [options appendFormat:@",sdp=\"http://%@\"",
                    [streamSDPField stringValue]];
                break;
            case 2:
                [options appendFormat:@",sdp=\"rtsp://%@\"",
                    [streamSDPField stringValue]];
                break;
            case 3:
            {
                char *psz_uri = vlc_path2uri(
                    [[streamSDPField stringValue] UTF8String], NULL);
                if (psz_uri) {
                    [options appendFormat:@",sdp=\"%s\"", psz_uri];
                    free(psz_uri);
                }
                break;
            }
            default:
                break;
            }
        }
        [options appendString:@"}"];
    }
#undef FIELD
    return options;
}

- (void)finalizePanel:(id)sender
{
    if (b_streaming
     && streamTypePopup && [streamTypePopup indexOfSelectedItem] == 0) {
        /* WAV, MOV/MP4 and MKV cannot go through HTTP */
        int tag = [self currentEncapsulationTag];
        if (tag == WAV || tag == MP4 || tag == MKV) {
            NSRunInformationalAlertPanel(
                _NS("Invalid container format for HTTP streaming"), @"%@",
                _NS("OK"), nil, nil,
                [NSString stringWithFormat:
                    _NS("Media encapsulated as %@ cannot be streamed "
                        "through the HTTP protocol for technical reasons."),
                    [self encapsulationFormatAsExtension:YES]]);
            return;
        }
    }

    playlist_t *p_playlist = pl_Get(p_intf);
    input_item_t *p_input = input_item_New([MRL UTF8String],
        [mediaName UTF8String]);
    if (!p_input)
        return;

    input_item_AddOption(p_input, [[self composedOptions] UTF8String],
                         VLC_INPUT_OPTION_TRUSTED);
    if (b_streaming)
        input_item_AddOption(p_input,
            [[NSString stringWithFormat:@"ttl=%@",
                [streamTTLField stringValue]] UTF8String],
            VLC_INPUT_OPTION_TRUSTED);

    int returnValue = playlist_AddInput(p_playlist, p_input, false, true);
    if (returnValue == VLC_SUCCESS) {
        /* play the item right away (3.0 behavior) */
        playlist_Lock(p_playlist);
        playlist_item_t *p_item =
            playlist_ItemGetByInput(p_playlist, p_input);
        if (p_item)
            playlist_ViewPlay(p_playlist, NULL, p_item);
        playlist_Unlock(p_playlist);
    } else
        msg_Err(p_intf, "CAS: playlist add input failed");

    input_item_Release(p_input);
    [window orderOut:sender];
}

@end
