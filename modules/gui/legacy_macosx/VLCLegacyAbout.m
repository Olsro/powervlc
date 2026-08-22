/*****************************************************************************
 * VLCLegacyAbout.m: about window for the legacy Mac OS X interface
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

#import "VLCLegacyAbout.h"
#import "misc.h"

#include <vlc_about.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

@implementation VLCLegacyAbout

- (id)initWithIntf:(intf_thread_t *)intf
{
    if (self = [super init])
        p_intf = intf;
    return self;
}

- (void)dealloc
{
    [authorsText release];
    [window release];
    [super dealloc];
}

- (NSTextField *)staticText:(NSString *)text frame:(NSRect)frame
                       font:(NSFont *)font in:(NSView *)parent
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame]
        autorelease];
    [label setEditable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setSelectable:YES];
    [[label cell] setFont:font];
    VLCLegacySetCellLineBreakMode([label cell], NSLineBreakByTruncatingTail);
    [label setStringValue:text];
    [parent addSubview:label];
    return label;
}

/* underlined link-style button, like the 2.2/3.0 about window (3.0 turned
 * the 2.2 blue links grey) */
- (NSButton *)linkButton:(NSString *)title frame:(NSRect)frame
{
    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setButtonType:NSMomentaryChangeButton];
    [button setBordered:NO];
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithInt:NSUnderlineStyleSingle],
            NSUnderlineStyleAttributeName,
        [NSColor colorWithCalibratedWhite:0.35 alpha:1.0],
            NSForegroundColorAttributeName,
        [NSFont systemFontOfSize:13], NSFontAttributeName,
        nil];
    NSAttributedString *styled = [[[NSAttributedString alloc]
        initWithString:title attributes:attributes] autorelease];
    [button setAttributedTitle:styled];
    [button setTarget:self];
    [button setAction:@selector(buttonAction:)];
    [[window contentView] addSubview:button];
    return button;
}

/* the authors list from vlc_about.h, one line per author like 2.2 */
- (NSString *)processedAuthors
{
    NSArray *blocks = [[NSString stringWithUTF8String:psz_authors]
        componentsSeparatedByString:@"\n\n"];
    NSMutableArray *result =
        [NSMutableArray arrayWithCapacity:[blocks count]];
    unsigned i;
    for (i = 0; i < [blocks count]; i++) {
        NSMutableString *entry = [NSMutableString stringWithString:
            [blocks objectAtIndex:i]];
        [entry replaceOccurrencesOfString:@"\n"
                               withString:@", "
                                  options:NSLiteralSearch
                                    range:NSMakeRange(0, [entry length])];
        [result addObject:entry];
    }
    return [result componentsJoinedByString:@"\n\n"];
}

- (void)buildWindow
{
    /* 2.2/3.0 geometry, made 70px taller than the original 356 to fit the
     * PowerVLC attribution paragraph below the copyright line */
    window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 721, 426)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:@"PowerVLC"];
    [window setReleasedWhenClosed:NO];
    [window setDelegate:(id)self];
    [window setExcludedFromWindowsMenu:YES];
    [window setBackgroundColor:
        [NSColor colorWithCalibratedWhite:0.96 alpha:1.0]];
    NSView *content = [window contentView];

    /* the application icon with all its representations */
    NSImage *icon = nil;
    NSString *iconPath = [[NSBundle mainBundle] pathForResource:@"VLC"
                                                         ofType:@"icns"];
    if (iconPath)
        icon = [[[NSImage alloc] initWithContentsOfFile:iconPath]
            autorelease];
    if (!icon)
        icon = [NSApp applicationIconImage];
    NSImageView *iconView = [[[NSImageView alloc]
        initWithFrame:NSMakeRect(26, 264, 128, 128)] autorelease];
    [iconView setImage:icon];
    [iconView setEditable:NO];
    /* -unregisterDraggedTypes is 10.3; below it, a view that never
     * registered a type has nothing to unregister anyway */
    if ([iconView respondsToSelector:@selector(unregisterDraggedTypes)])
        [iconView unregisterDraggedTypes];
    [content addSubview:iconView];

    [self staticText:@"PowerVLC"
               frame:NSMakeRect(180, 366, 520, 34)
                font:[NSFont boldSystemFontOfSize:24] in:content];

    /* Read the product version from the bundle first.  In a universal app
     * each architecture's interface plugin is built independently and an
     * incremental legacy-toolchain build can otherwise leave the literal
     * compiled into one slice behind the Info.plist (the i386 1.3.1 bundle
     * was consequently still displaying 1.2.0 here).  The bundle value is
     * also what Finder and LaunchServices report, so it is the authoritative
     * value for an installed application. */
#if defined(POWERVLC_VERSION) && defined(VERSION_MESSAGE)
    NSString *productVersion = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![productVersion isKindOfClass:[NSString class]]
        || [productVersion length] == 0)
        productVersion = [NSString stringWithUTF8String:POWERVLC_VERSION];
    NSString *buildDate = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"PowerVLCBuildDate"];
    if (![buildDate isKindOfClass:[NSString class]] || [buildDate length] == 0)
        buildDate = [NSString stringWithUTF8String:__DATE__];
    NSString *coreVersion = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"PowerVLCCoreVersion"];
    if (![coreVersion isKindOfClass:[NSString class]]
        || [coreVersion length] == 0)
        coreVersion = [NSString stringWithUTF8String:VERSION_MESSAGE];
    NSString *version = [NSString stringWithFormat:
        @"Version %@ (%@) - Forked from VLC %@",
        productVersion, buildDate, coreVersion];
#else
    NSString *version = @"";
#endif
    /* like VLCAboutWindowController, these two lines skip gettext */
    nameVersionField = [self staticText:version
               frame:NSMakeRect(180, 344, 520, 17)
                font:[NSFont systemFontOfSize:12] in:content];

#ifdef __clang__
    NSString *compiler = [NSString stringWithFormat:@"clang %s",
        __clang_version__];
#else
    NSString *compiler = [NSString stringWithFormat:@"gcc %s", __VERSION__];
#endif
    revisionField = [self staticText:[NSString stringWithFormat:
            @"Compiled by %s with %@ (%s %s)",
            VLC_CompileBy(), compiler, __DATE__, __TIME__]
               frame:NSMakeRect(180, 326, 520, 15)
                font:[NSFont systemFontOfSize:10] in:content];
    [revisionField setTextColor:
        [NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];

    /* the "join us" blurb, rendered from the translated HTML like 2.2 */
    NSString *joinus = [NSString stringWithUTF8String:vlc_gettext(""
        "<p>VLC media player is a free and open source media player, "
        "encoder, and streamer made by the volunteers of the <a href="
        "\"http://www.videolan.org/\"><span style=\" text-decoration: "
        "underline; color:#0057ae;\">VideoLAN</span></a> community.</p>"
        "<p>VLC uses its internal codecs, works on essentially every "
        "popular platform, and can read almost all files, CDs, DVDs, "
        "network streams, capture cards and other media formats!</p>"
        "<p><a href=\"http://www.videolan.org/contribute/\"><span style="
        "\" text-decoration: underline; color:#0057ae;\">Help and join "
        "us!</span></a>")];
    /* a meta charset makes the HTML importer decode UTF-8 without the
     * options: variant of initWithHTML: */
    NSString *joinusHTML = [NSString stringWithFormat:
        @"<meta http-equiv=\"Content-Type\" content=\"text/html; "
        @"charset=utf-8\">%@", joinus];
    NSAttributedString *joinusRendered = [[[NSAttributedString alloc]
        initWithHTML:[joinusHTML dataUsingEncoding:NSUTF8StringEncoding
                          allowLossyConversion:YES]
        documentAttributes:NULL] autorelease];
    /* PowerVLC: render the blurb in an NSTextView (not a label) so clicks on
     * its embedded VideoLAN links can be intercepted and routed through the
     * confirmation dialog (see -textView:clickedOnLink:atIndex:). */
    joinusField = [[[NSTextView alloc]
        initWithFrame:NSMakeRect(180, 188, 522, 130)] autorelease];
    [joinusField setEditable:NO];
    [joinusField setSelectable:YES];
    [joinusField setDrawsBackground:NO];
    [joinusField setDelegate:(id)self];
    /* A view does not clip its drawing to its own frame, so a blurb that
     * lays out taller than 130 points paints its last line over whatever
     * sits below -- which is what "Help and join us!" did to the trademark
     * line on 10.2, whose HTML importer picks a larger default font than
     * 10.4's. Two guards: pin the body font so the height is the same
     * everywhere, and bound the text container so nothing is ever laid out
     * past the frame. Link colours and underlines come from the HTML and
     * are left alone. */
    if (joinusRendered) {
        NSMutableAttributedString *blurb =
            [[joinusRendered mutableCopy] autorelease];

        [blurb addAttribute:NSFontAttributeName
                      value:[NSFont systemFontOfSize:11]
                      range:NSMakeRange(0, [blurb length])];
        [[joinusField textStorage] setAttributedString:blurb];
    }
    [joinusField setVerticallyResizable:NO];
    [joinusField setHorizontallyResizable:NO];
    [[joinusField textContainer] setContainerSize:NSMakeSize(522, 130)];
    [[joinusField textContainer] setWidthTracksTextView:YES];
    [content addSubview:joinusField];

    trademarksField = [self staticText:
            _NS("VLC media player and VideoLAN are trademarks of the "
                "VideoLAN Association.")
               frame:NSMakeRect(180, 154, 522, 28)
                font:[NSFont systemFontOfSize:10] in:content];
    [[trademarksField cell] setWraps:YES];
    [trademarksField setTextColor:
        [NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];

    NSString *copyright = [[[NSBundle mainBundle] localizedInfoDictionary]
        objectForKey:@"NSHumanReadableCopyright"];
    if (!copyright)
        copyright = [NSString stringWithUTF8String:COPYRIGHT_MESSAGE];
    copyrightField = [self staticText:copyright
               frame:NSMakeRect(180, 126, 522, 26)
                font:[NSFont systemFontOfSize:10] in:content];
    [[copyrightField cell] setWraps:YES];
    [copyrightField setTextColor:
        [NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];

    /* PowerVLC attribution, right below the copyright with the same font,
     * shown in the current interface language */
    NSString *attribution = _NS("PowerVLC Copyright © 2026 Olsro. PowerVLC is an unofficial fork of VLC, not affiliated with VideoLAN. PowerVLC could not have existed without all the contributors who have worked on VLC since its very beginning. A heartfelt thank you to each and every one of them.");
    attributionField = [self staticText:attribution
               frame:NSMakeRect(180, 54, 522, 64)
                font:[NSFont systemFontOfSize:10] in:content];
    [[attributionField cell] setWraps:YES];
    [attributionField setTextColor:
        [NSColor colorWithCalibratedWhite:0.35 alpha:1.0]];

    [self linkButton:_NS("Credits") frame:NSMakeRect(178, 18, 110, 22)];
    [self linkButton:_NS("License") frame:NSMakeRect(298, 18, 110, 22)];
    [self linkButton:_NS("Authors") frame:NSMakeRect(418, 18, 110, 22)];

    /* a well-delimited, manually scrollable text zone: the 2.2-style
     * auto-scroll ran over the whole window and made it uncontrollable */
    creditsScroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(170, 54, 534, 264)] autorelease];
    [creditsScroll setDrawsBackground:NO];
    [creditsScroll setHasVerticalScroller:YES];
    if ([creditsScroll respondsToSelector:@selector(setAutohidesScrollers:)])
        [creditsScroll setAutohidesScrollers:YES];
    [creditsScroll setBorderType:NSBezelBorder];
    creditsView = [[[NSTextView alloc]
        initWithFrame:NSMakeRect(0, 0, 519, 264)] autorelease];
    [creditsView setEditable:NO];
    [creditsView setDrawsBackground:NO];
    [creditsView setFont:[NSFont systemFontOfSize:11]];
    [creditsView setVerticallyResizable:YES];
    [creditsView setHorizontallyResizable:NO];
    [creditsScroll setDocumentView:creditsView];
    [content addSubview:creditsScroll];
    VLCLegacySetViewHidden(creditsScroll, YES);

    authorsText = [[self processedAuthors] retain];

    [window center];
}

- (void)showAbout
{
    if (!window)
        [self buildWindow];

    /* front page state, like -[VLAboutBox showAbout] */
    VLCLegacySetViewHidden(creditsScroll, YES);
    VLCLegacySetViewHidden(joinusField, NO);
    VLCLegacySetViewHidden(copyrightField, NO);
    VLCLegacySetViewHidden(attributionField, NO);
    VLCLegacySetViewHidden(trademarksField, NO);
    [creditsView scrollPoint:NSMakePoint(0, 0)];
    [window makeKeyAndOrderFront:nil];
}

- (void)windowWillClose:(NSNotification *)notification
{
}

- (void)buttonAction:(id)sender
{
    /* the title, version and compile lines stay visible: the text zone
     * only replaces the blurb below them */
    VLCLegacySetViewHidden(creditsScroll, NO);
    VLCLegacySetViewHidden(joinusField, YES);
    VLCLegacySetViewHidden(copyrightField, YES);
    VLCLegacySetViewHidden(attributionField, YES);
    VLCLegacySetViewHidden(trademarksField, YES);

    NSString *title = [(NSButton *)sender title];
    if ([title isEqualToString:_NS("Authors")])
        [creditsView setString:authorsText];
    else if ([title isEqualToString:_NS("Credits")])
        [creditsView setString:
            [NSString stringWithUTF8String:psz_thanks]];
    else
        [creditsView setString:
            [NSString stringWithUTF8String:psz_license]];

    [creditsView sizeToFit];
    [creditsView scrollPoint:NSMakePoint(0, 0)];
}

/* Intercept clicks on the VideoLAN links in the "join us" blurb and route
 * them through the confirmation dialog instead of opening them directly. */
- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link
         atIndex:(NSUInteger)charIndex
{
    NSURL *url = [link isKindOfClass:[NSURL class]] ? (NSURL *)link
               : [NSURL URLWithString:[link description]];
    VLCLegacyConfirmAndOpenVideoLANURL(url);
    return YES;
}

@end
