/*****************************************************************************
 * VLCLegacyOutput.m: stream output settings sheet (legacy Mac OS X intf)
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

#import "VLCLegacyOutput.h"

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/* mux popup indexes, in the exact 3.0 order */
enum {
    MUX_TS = 0, MUX_PS, MUX_MPEG1, MUX_OGG, MUX_AVI, MUX_ASF, MUX_MP4,
    MUX_MOV, MUX_RAW, MUX_COUNT
};

@implementation VLCLegacyOutput

- (id)initWithIntf:(intf_thread_t *)intf
{
    if (self = [super init]) {
        p_intf = intf;
        transcodeString = [@"" retain];
        soutMRL = [[NSArray array] retain];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [sheet release];
    [transcodeString release];
    [soutMRL release];
    [super dealloc];
}

/*****************************************************************************
 * control helpers
 *****************************************************************************/

- (NSTextField *)label:(NSString *)text frame:(NSRect)frame in:(NSView *)parent
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
    [[field cell] setWraps:NO];
    [[field cell] setScrollable:YES];
    [parent addSubview:field];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(outputInfoChanged:)
               name:NSControlTextDidChangeNotification object:field];
    return field;
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

- (NSComboBox *)combo:(NSRect)frame values:(NSArray *)values
                   in:(NSView *)parent
{
    NSComboBox *combo = [[[NSComboBox alloc] initWithFrame:frame]
        autorelease];
    [[combo cell] setControlSize:NSSmallControlSize];
    [combo setFont:[NSFont systemFontOfSize:11]];
    [combo addItemsWithObjectValues:values];
    [parent addSubview:combo];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(transcodeInfoChanged:)
               name:NSControlTextDidChangeNotification object:combo];
    return combo;
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

/*****************************************************************************
 * sheet construction (same controls and captions as StreamOutput.xib)
 *****************************************************************************/

- (void)buildSheet
{
    sheet = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 542, 610)
                  styleMask:NSTitledWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    NSView *content = [sheet contentView];

    NSBox *optionsBox = [[[NSBox alloc]
        initWithFrame:NSMakeRect(17, 50, 508, 546)] autorelease];
    [optionsBox setTitle:_NS("Streaming and Transcoding Options")];
    [[optionsBox titleCell] setFont:[NSFont systemFontOfSize:11]];
    [content addSubview:optionsBox];
    NSView *box = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 484, 510)] autorelease];
    [optionsBox setContentView:box];

    displayCheckbox = [self checkbox:_NS("Display the stream locally")
                               frame:NSMakeRect(10, 484, 300, 18)
                              action:@selector(outputInfoChanged:) in:box];

    /* --- destination: File / Stream radio rows --- */
    NSButtonCell *radioProto = [[[NSButtonCell alloc] init] autorelease];
    [radioProto setButtonType:NSRadioButton];
    [radioProto setFont:[NSFont systemFontOfSize:11]];
    methodMatrix = [[[NSMatrix alloc]
        initWithFrame:NSMakeRect(10, 414, 80, 58)
                 mode:NSRadioModeMatrix
            prototype:radioProto
         numberOfRows:2
      numberOfColumns:1] autorelease];
    [methodMatrix setCellSize:NSMakeSize(80, 25)];
    [[methodMatrix cellAtRow:0 column:0] setTitle:_NS("File")];
    [[methodMatrix cellAtRow:1 column:0] setTitle:_NS("Stream")];
    [methodMatrix setTarget:self];
    [methodMatrix setAction:@selector(outputMethodChanged:)];
    [box addSubview:methodMatrix];

    /* file row */
    fileField = [self field:NSMakeRect(96, 452, 236, 19) in:box];
    browseButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(336, 446, 90, 28)] autorelease];
    [browseButton setTitle:_NS("Browse...")];
    [browseButton setBezelStyle:NSRoundedBezelStyle];
    [[browseButton cell] setControlSize:NSSmallControlSize];
    [browseButton setFont:[NSFont systemFontOfSize:11]];
    [browseButton setTarget:self];
    [browseButton setAction:@selector(outputFileBrowse:)];
    [box addSubview:browseButton];
    dumpCheckbox = [self checkbox:_NS("Dump raw input")
                            frame:NSMakeRect(96, 428, 200, 18)
                           action:@selector(outputInfoChanged:) in:box];

    /* stream rows */
    [self label:_NS("Type") frame:NSMakeRect(96, 394, 60, 14) in:box];
    [self label:_NS("Address") frame:NSMakeRect(160, 394, 130, 14) in:box];
    [self label:_NS("Port") frame:NSMakeRect(298, 394, 60, 14) in:box];
    [self label:@"TTL" frame:NSMakeRect(382, 394, 40, 14) in:box];
    streamTypePopup = [self popup:NSMakeRect(94, 368, 64, 22)
                           action:@selector(outputMethodChanged:) in:box];
    [streamTypePopup addItemWithTitle:@"HTTP"];
    [streamTypePopup addItemWithTitle:@"MMSH"];
    [streamTypePopup addItemWithTitle:@"UDP"];
    [streamTypePopup addItemWithTitle:@"RTP"];
    streamAddressField = [self field:NSMakeRect(162, 370, 128, 19) in:box];
    streamPortField = [self field:NSMakeRect(298, 370, 52, 19) in:box];
    [streamPortField setIntValue:1234];
    streamPortStepper = [self stepper:NSMakeRect(352, 364, 19, 27)
                                  min:0 max:65535
                               action:@selector(streamPortStepperChanged:)
                                   in:box];
    [streamPortStepper setIntValue:1234];
    streamTTLField = [self field:NSMakeRect(382, 370, 40, 19) in:box];
    [streamTTLField setIntValue:1];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(TTLChanged:)
               name:NSControlTextDidChangeNotification object:streamTTLField];
    streamTTLStepper = [self stepper:NSMakeRect(424, 364, 19, 27)
                                 min:1 max:255
                              action:@selector(streamTTLStepperChanged:)
                                  in:box];
    [streamTTLStepper setIntValue:1];

    /* --- encapsulation --- */
    [self label:_NS("Encapsulation Method")
          frame:NSMakeRect(10, 336, 220, 14) in:box];
    muxPopup = [self popup:NSMakeRect(232, 330, 130, 22)
                    action:@selector(outputMethodChanged:) in:box];
    [muxPopup addItemWithTitle:@"MPEG TS"];
    [muxPopup addItemWithTitle:@"MPEG PS"];
    [muxPopup addItemWithTitle:@"MPEG 1"];
    [muxPopup addItemWithTitle:@"Ogg"];
    [muxPopup addItemWithTitle:@"AVI"];
    [muxPopup addItemWithTitle:@"ASF"];
    [muxPopup addItemWithTitle:@"MPEG 4"];
    [muxPopup addItemWithTitle:@"Quicktime"];
    [muxPopup addItemWithTitle:@"Raw"];
    [muxPopup setAutoenablesItems:NO];

    /* --- transcoding --- */
    NSBox *transcodeBox = [[[NSBox alloc]
        initWithFrame:NSMakeRect(8, 176, 468, 146)] autorelease];
    [transcodeBox setTitle:_NS("Transcoding options")];
    [[transcodeBox titleCell] setFont:[NSFont systemFontOfSize:11]];
    [box addSubview:transcodeBox];
    NSView *trans = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 444, 112)] autorelease];
    [transcodeBox setContentView:trans];

    videoCheckbox = [self checkbox:_NS("Video")
                             frame:NSMakeRect(8, 88, 90, 18)
                            action:@selector(transcodeChanged:) in:trans];
    videoCodecPopup = [self popup:NSMakeRect(100, 84, 84, 22)
                           action:@selector(transcodeInfoChanged:) in:trans];
    {
        static NSString *const codecs[12] = {
            @"mp1v", @"mp2v", @"mp4v", @"DIV1", @"DIV2", @"DIV3",
            @"h263", @"h264", @"WMV1", @"WMV2", @"MJPG", @"theo" };
        int i;
        for (i = 0; i < 12; i++)
            [videoCodecPopup addItemWithTitle:codecs[i]];
    }
    [self label:_NS("Bitrate (kb/s)") frame:NSMakeRect(190, 88, 90, 14)
             in:trans];
    videoBitrateCombo = [self combo:NSMakeRect(282, 84, 68, 22)
                             values:[NSArray arrayWithObjects:@"16", @"32",
                                     @"64", @"96", @"128", @"192", @"256",
                                     @"384", @"512", @"768", @"1024",
                                     @"2048", @"3072", nil] in:trans];
    [self label:_NS("Scale") frame:NSMakeRect(356, 88, 40, 14) in:trans];
    videoScaleCombo = [self combo:NSMakeRect(384, 84, 56, 22)
                           values:[NSArray arrayWithObjects:@"0.25", @"0.5",
                                   @"0.75", @"1", @"1.25", @"1.5", @"1.75",
                                   @"2", nil] in:trans];
    [videoScaleCombo setStringValue:@"1"];

    audioCheckbox = [self checkbox:_NS("Audio")
                             frame:NSMakeRect(8, 32, 90, 18)
                            action:@selector(transcodeChanged:) in:trans];
    audioCodecPopup = [self popup:NSMakeRect(100, 28, 84, 22)
                           action:@selector(transcodeInfoChanged:) in:trans];
    {
        static NSString *const codecs[7] = {
            @"mpga", @"mp3 ", @"mp4a", @"a52 ", @"vorb", @"flac", @"spx " };
        int i;
        for (i = 0; i < 7; i++)
            [audioCodecPopup addItemWithTitle:codecs[i]];
    }
    [self label:_NS("Bitrate (kb/s)") frame:NSMakeRect(190, 32, 90, 14)
             in:trans];
    audioBitrateCombo = [self combo:NSMakeRect(282, 28, 68, 22)
                             values:[NSArray arrayWithObjects:@"16", @"32",
                                     @"64", @"96", @"128", @"192", @"256",
                                     @"512", nil] in:trans];
    [self label:_NS("Channels") frame:NSMakeRect(356, 32, 60, 14) in:trans];
    audioChannelsCombo = [self combo:NSMakeRect(384, 28, 56, 22)
                              values:[NSArray arrayWithObjects:@"1", @"2",
                                      @"4", @"6", nil] in:trans];

    /* --- announcing --- */
    NSBox *miscBox = [[[NSBox alloc]
        initWithFrame:NSMakeRect(8, 8, 468, 160)] autorelease];
    [miscBox setTitle:_NS("Stream Announcing")];
    [[miscBox titleCell] setFont:[NSFont systemFontOfSize:11]];
    [box addSubview:miscBox];
    NSView *misc = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 444, 126)] autorelease];
    [miscBox setContentView:misc];

    sapCheckbox = [self checkbox:_NS("SAP Announcement")
                           frame:NSMakeRect(8, 102, 210, 18)
                          action:@selector(announceChanged:) in:misc];
    rtspCheckbox = [self checkbox:_NS("RTSP Announcement")
                            frame:NSMakeRect(224, 102, 210, 18)
                           action:@selector(announceChanged:) in:misc];
    httpCheckbox = [self checkbox:_NS("HTTP Announcement")
                            frame:NSMakeRect(8, 78, 210, 18)
                           action:@selector(announceChanged:) in:misc];
    sdpFileCheckbox = [self checkbox:_NS("Export SDP as file")
                               frame:NSMakeRect(224, 78, 210, 18)
                              action:@selector(announceChanged:) in:misc];
    [self label:_NS("Channel Name") frame:NSMakeRect(8, 52, 130, 14)
             in:misc];
    channelNameField = [self field:NSMakeRect(140, 50, 296, 19) in:misc];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(transcodeInfoChanged:)
               name:NSControlTextDidChangeNotification
             object:channelNameField];
    [self label:_NS("SDP URL") frame:NSMakeRect(8, 24, 130, 14) in:misc];
    sdpURLField = [self field:NSMakeRect(140, 22, 296, 19) in:misc];
    [[NSNotificationCenter defaultCenter]
        addObserver:self selector:@selector(transcodeInfoChanged:)
               name:NSControlTextDidChangeNotification object:sdpURLField];

    /* --- OK --- */
    NSButton *okButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(432, 12, 92, 28)] autorelease];
    [okButton setTitle:_NS("OK")];
    [okButton setBezelStyle:NSRoundedBezelStyle];
    [okButton setKeyEquivalent:@"\r"];
    [okButton setTarget:self];
    [okButton setAction:@selector(outputCloseSheet:)];
    [content addSubview:okButton];

    [self transcodeChanged:nil];
    [self outputMethodChanged:nil];
}

- (void)beginSheetForWindow:(NSWindow *)parent
{
    if (!sheet)
        [self buildSheet];
    [NSApp beginSheet:sheet
       modalForWindow:parent
        modalDelegate:self
       didEndSelector:NULL
          contextInfo:nil];
}

- (void)outputCloseSheet:(id)sender
{
    [sheet orderOut:sender];
    [NSApp endSheet:sheet];
}

- (NSArray *)soutMRL
{
    /* never configured: no sout options at all, like 3.0 when the
     * StreamOutput nib was never loaded */
    if (!sheet)
        return [NSArray array];
    /* make sure the strings reflect the very last state */
    [self transcodeInfoChanged:nil];
    return soutMRL;
}

/*****************************************************************************
 * enable/disable logic — straight port of -[VLCOutput outputMethodChanged:]
 *****************************************************************************/

- (void)setMuxesEnabledFrom:(const BOOL *)enabled
{
    int i;
    for (i = 0; i < MUX_COUNT; i++)
        [[muxPopup itemAtIndex:i] setEnabled:enabled[i]];
}

- (void)outputMethodChanged:(id)sender
{
    NSString *mode = [[methodMatrix selectedCell] title];

    [sapCheckbox setEnabled:NO];
    [httpCheckbox setEnabled:NO];
    [rtspCheckbox setEnabled:NO];
    [sdpFileCheckbox setEnabled:NO];
    [channelNameField setEnabled:NO];
    [sdpURLField setEnabled:NO];
    [[muxPopup itemAtIndex:MUX_TS] setEnabled:YES];

    if ([mode isEqualToString:_NS("File")]) {
        static const BOOL muxes[MUX_COUNT] =
            { YES, YES, YES, YES, YES, YES, YES, YES, YES };
        [fileField setEnabled:YES];
        [browseButton setEnabled:YES];
        [dumpCheckbox setEnabled:YES];
        [streamAddressField setEnabled:NO];
        [streamPortField setEnabled:NO];
        [streamTTLField setEnabled:NO];
        [streamPortStepper setEnabled:NO];
        [streamTTLStepper setEnabled:NO];
        [streamTypePopup setEnabled:NO];
        [muxPopup setEnabled:YES];
        [self setMuxesEnabledFrom:muxes];
    } else {
        [fileField setEnabled:NO];
        [dumpCheckbox setEnabled:NO];
        [browseButton setEnabled:NO];
        [streamPortField setEnabled:YES];
        [streamPortStepper setEnabled:YES];
        [streamTypePopup setEnabled:YES];
        [muxPopup setEnabled:YES];

        mode = [streamTypePopup titleOfSelectedItem];
        if ([mode isEqualToString:@"HTTP"]) {
            static const BOOL muxes[MUX_COUNT] =
                { YES, YES, YES, YES, NO, YES, NO, NO, YES };
            [streamAddressField setEnabled:YES];
            [streamTTLField setEnabled:NO];
            [streamTTLStepper setEnabled:NO];
            [self setMuxesEnabledFrom:muxes];
        } else if ([mode isEqualToString:@"MMSH"]) {
            static const BOOL muxes[MUX_COUNT] =
                { NO, NO, NO, NO, NO, YES, NO, NO, NO };
            [streamAddressField setEnabled:YES];
            [streamTTLField setEnabled:NO];
            [streamTTLStepper setEnabled:NO];
            [self setMuxesEnabledFrom:muxes];
            [muxPopup selectItemAtIndex:MUX_ASF];
        } else if ([mode isEqualToString:@"UDP"]) {
            static const BOOL muxes[MUX_COUNT] =
                { YES, NO, NO, NO, NO, NO, NO, NO, YES };
            [streamAddressField setEnabled:YES];
            [streamTTLField setEnabled:YES];
            [streamTTLStepper setEnabled:YES];
            [self setMuxesEnabledFrom:muxes];
            [sapCheckbox setEnabled:YES];
            [channelNameField setEnabled:YES];
        } else if ([mode isEqualToString:@"RTP"]) {
            static const BOOL muxes[MUX_COUNT] =
                { NO, NO, NO, NO, NO, NO, NO, NO, YES };
            [streamAddressField setEnabled:YES];
            [streamTTLField setEnabled:YES];
            [streamTTLStepper setEnabled:YES];
            [self setMuxesEnabledFrom:muxes];
            [muxPopup selectItemAtIndex:MUX_RAW];
            [sapCheckbox setEnabled:YES];
            [rtspCheckbox setEnabled:YES];
            [httpCheckbox setEnabled:YES];
            [sdpFileCheckbox setEnabled:YES];
            [channelNameField setEnabled:YES];
        }
    }

    if (![[muxPopup selectedItem] isEnabled]) {
        if ([mode isEqualToString:@"RTP"])
            [muxPopup selectItemAtIndex:MUX_RAW];
        else
            [muxPopup selectItemAtIndex:MUX_TS];
    }

    [self outputInfoChanged:nil];
}

/*****************************************************************************
 * MRL composition — straight port of -[VLCOutput outputInfoChanged:]
 *****************************************************************************/

- (void)outputInfoChanged:(id)object
{
    NSString *mode, *mux, *mux_string;
    NSMutableString *announce = [NSMutableString stringWithString:@""];
    NSMutableString *mrl_string = [NSMutableString stringWithString:@":sout=#"];

    [mrl_string appendString:transcodeString];
    if ([displayCheckbox state] == NSOnState)
        [mrl_string appendString:@"duplicate{dst=display,dst="];

    mode = [[methodMatrix selectedCell] title];
    mux = [muxPopup titleOfSelectedItem];

    if ([mux isEqualToString:@"AVI"]) mux_string = @"avi";
    else if ([mux isEqualToString:@"Ogg"]) mux_string = @"ogg";
    else if ([mux isEqualToString:@"MPEG PS"]) mux_string = @"ps";
    else if ([mux isEqualToString:@"MPEG 4"]) mux_string = @"mp4";
    else if ([mux isEqualToString:@"MPEG 1"]) mux_string = @"mpeg1";
    else if ([mux isEqualToString:@"Quicktime"]) mux_string = @"mov";
    else if ([mux isEqualToString:@"ASF"]) mux_string = @"asf";
    else if ([mux isEqualToString:@"Raw"]) mux_string = @"raw";
    else mux_string = @"ts";

    /* stringByReplacingOccurrencesOfString: is 10.5+ */
    NSMutableString *filename_string =
        [NSMutableString stringWithString:[fileField stringValue]];
    [filename_string replaceOccurrencesOfString:@"\""
                                     withString:@"\\\""
                                        options:NSLiteralSearch
                                          range:NSMakeRange(0,
                                              [filename_string length])];

    if ([mode isEqualToString:_NS("File")]) {
        if ([dumpCheckbox state] == NSOnState) {
            [soutMRL release];
            soutMRL = [[NSArray arrayWithObjects:@":demux=dump",
                [NSString stringWithFormat:@":demuxdump-file=\"%@\"",
                    filename_string], nil] retain];
            return;
        }
        [mrl_string appendFormat:
            @"standard{mux=%@,access=file{no-overwrite},dst=\"%@\"}",
            mux_string, filename_string];
    } else if ([mode isEqualToString:_NS("Stream")]) {
        mode = [streamTypePopup titleOfSelectedItem];

        if ([mode isEqualToString:@"HTTP"])
            mode = @"http";
        else if ([mode isEqualToString:@"MMSH"]) {
            if ([mux isEqualToString:@"ASF"])
                mux_string = @"asfh";
            mode = @"mmsh";
        } else if ([mode isEqualToString:@"UDP"]) {
            mode = @"udp";
            if ([sapCheckbox state] == NSOnState) {
                if (![[channelNameField stringValue] isEqualToString:@""])
                    [announce appendFormat:@",sap,name=%@",
                        [channelNameField stringValue]];
                else
                    [announce appendString:@",sap"];
            }
        }
        if (![mode isEqualToString:@"RTP"]) {
            /* split hostname and path so the port lands after the host */
            NSArray *urlItems = [[streamAddressField stringValue]
                componentsSeparatedByString:@"/"];
            NSMutableString *finalStreamAddress =
                [NSMutableString string];

            if ([urlItems count] == 1)
                [finalStreamAddress appendFormat:@"\"%@:%@\"",
                    [streamAddressField stringValue],
                    [streamPortField stringValue]];
            else {
                [finalStreamAddress appendFormat:@"\"%@:%@",
                    [urlItems objectAtIndex:0],
                    [streamPortField stringValue]];
                unsigned itemCount = (unsigned)[urlItems count];
                unsigned x;
                for (x = 1; x < itemCount; x++)
                    [finalStreamAddress appendFormat:@"/%@",
                        [urlItems objectAtIndex:x]];
                [finalStreamAddress appendString:@"\""];
            }

            [mrl_string appendFormat:@"standard{mux=%@,access=%@,dst=%@%@}",
                mux_string, mode, finalStreamAddress, announce];
        } else {
            NSString *stream_name;
            if (![[channelNameField stringValue] isEqualToString:@""])
                stream_name = [NSString stringWithFormat:@",name=%@",
                    [channelNameField stringValue]];
            else
                stream_name = @"";

            if ([sapCheckbox state] == NSOnState)
                [announce appendString:@",sdp=sap"];
            if ([rtspCheckbox state] == NSOnState)
                [announce appendFormat:@",sdp=\"rtsp://%@\"",
                    [sdpURLField stringValue]];
            if ([httpCheckbox state] == NSOnState)
                [announce appendFormat:@",sdp=\"http://%@\"",
                    [sdpURLField stringValue]];
            if ([sdpFileCheckbox state] == NSOnState)
                [announce appendFormat:@",sdp=\"file://%@\"",
                    [sdpURLField stringValue]];

            [mrl_string appendFormat:@"rtp{mux=ts,dst=\"%@\",port=%@%@%@}",
                [streamAddressField stringValue],
                [streamPortField stringValue], stream_name, announce];
        }
    }
    if ([displayCheckbox state] == NSOnState)
        [mrl_string appendString:@"}"];

    [soutMRL release];
    soutMRL = [[NSArray arrayWithObject:mrl_string] retain];
}

/*****************************************************************************
 * secondary actions
 *****************************************************************************/

- (void)TTLChanged:(NSNotification *)notification
{
    config_PutInt(p_intf, "ttl", [streamTTLField intValue]);
}

- (void)outputFileBrowse:(id)sender
{
    NSString *mux = [muxPopup titleOfSelectedItem];
    NSString *mux_string;
    if ([mux isEqualToString:@"MPEG PS"]) mux_string = @"vob";
    else if ([mux isEqualToString:@"MPEG 1"]) mux_string = @"mpg";
    else if ([mux isEqualToString:@"AVI"]) mux_string = @"avi";
    else if ([mux isEqualToString:@"ASF"]) mux_string = @"asf";
    else if ([mux isEqualToString:@"Ogg"]) mux_string = @"ogm";
    else if ([mux isEqualToString:@"MPEG 4"]) mux_string = @"mp4";
    else if ([mux isEqualToString:@"Quicktime"]) mux_string = @"mov";
    else if ([mux isEqualToString:@"Raw"]) mux_string = @"raw";
    else mux_string = @"ts";

    NSSavePanel *save_panel = [NSSavePanel savePanel];
    [save_panel setTitle:_NS("Save File")];
    [save_panel setPrompt:_NS("Save")];

    if ([save_panel runModalForDirectory:nil
            file:[NSString stringWithFormat:@"vlc-output.%@", mux_string]]
            == NSFileHandlingPanelOKButton) {
        [fileField setStringValue:[save_panel filename]];
        [self outputInfoChanged:nil];
    }
}

- (void)streamPortStepperChanged:(id)sender
{
    [streamPortField setIntValue:[streamPortStepper intValue]];
    [self outputInfoChanged:nil];
}

- (void)streamTTLStepperChanged:(id)sender
{
    [streamTTLField setIntValue:[streamTTLStepper intValue]];
    [self TTLChanged:nil];
}

- (void)transcodeChanged:(id)sender
{
    BOOL video = [videoCheckbox state] == NSOnState;
    [videoCodecPopup setEnabled:video];
    [videoBitrateCombo setEnabled:video];
    [videoScaleCombo setEnabled:video];

    BOOL audio = [audioCheckbox state] == NSOnState;
    [audioCodecPopup setEnabled:audio];
    [audioBitrateCombo setEnabled:audio];
    [audioChannelsCombo setEnabled:audio];

    [self transcodeInfoChanged:nil];
}

- (void)transcodeInfoChanged:(id)object
{
    NSMutableString *transcode_string =
        [NSMutableString stringWithCapacity:200];

    if ([videoCheckbox state] == NSOnState
     || [audioCheckbox state] == NSOnState) {
        [transcode_string appendString:@"transcode{"];
        if ([videoCheckbox state] == NSOnState) {
            [transcode_string appendFormat:
                @"vcodec=\"%@\",vb=\"%@\",scale=\"%@\"",
                [videoCodecPopup titleOfSelectedItem],
                [videoBitrateCombo stringValue],
                [videoScaleCombo stringValue]];
            if ([audioCheckbox state] == NSOnState)
                [transcode_string appendString:@","];
        }
        if ([audioCheckbox state] == NSOnState) {
            [transcode_string appendFormat:@"acodec=\"%@\",ab=\"%@\"",
                [audioCodecPopup titleOfSelectedItem],
                [audioBitrateCombo stringValue]];
            if (![[audioChannelsCombo stringValue] isEqualToString:@""])
                [transcode_string appendFormat:@",channels=\"%@\"",
                    [audioChannelsCombo stringValue]];
        }
        [transcode_string appendString:@"}:"];
    }

    [transcodeString release];
    transcodeString = [transcode_string copy];
    [self outputInfoChanged:nil];
}

- (void)announceChanged:(id)sender
{
    NSString *mode = [streamTypePopup titleOfSelectedItem];
    [channelNameField setEnabled:[sapCheckbox state]
        || [mode isEqualToString:@"RTP"]];

    if ([mode isEqualToString:@"RTP"]) {
        if ([[sender title] isEqualToString:_NS("RTSP Announcement")]) {
            [httpCheckbox setState:NSOffState];
            [sdpFileCheckbox setState:NSOffState];
        } else if ([[sender title]
                       isEqualToString:_NS("HTTP Announcement")]) {
            [rtspCheckbox setState:NSOffState];
            [sdpFileCheckbox setState:NSOffState];
        } else if ([[sender title]
                       isEqualToString:_NS("Export SDP as file")]) {
            [rtspCheckbox setState:NSOffState];
            [httpCheckbox setState:NSOffState];
        }

        [sdpURLField setEnabled:([rtspCheckbox state] == NSOnState
                              || [httpCheckbox state] == NSOnState
                              || [sdpFileCheckbox state] == NSOnState)];
    }
    [self outputInfoChanged:nil];
}

@end
