/*****************************************************************************
 * VLCAboutWindowController.m
 *****************************************************************************
 * Copyright (C) 2001-2014 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Derk-Jan Hartman <thedj@users.sourceforge.net>
 *          Felix Paul Kühne <fkuehne -at- videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/

#import "VLCAboutWindowController.h"

#import "VLCMain.h"
#import <vlc_intf_strings.h>
#import <vlc_about.h>
#import "CompatibilityFixes.h"

#import "VLCScrollingClipView.h"

#ifdef __x86_64__
#define PLATFORM "Intel 64bit"
#else
#define PLATFORM "Apple Silicon"
#endif

@interface VLCAboutWindowController ()
{
    NSString *_authorsString;
    /* NSTextView overlaid on the (now hidden) o_joinus_txt field so we can
     * intercept clicks on the embedded VideoLAN links. */
    NSTextView *_joinusTextView;
}
@end

@implementation VLCAboutWindowController

- (id)init
{
    self = [super initWithWindowNibName:@"About"];
    if (self) {
        [self setWindowFrameAutosaveName:@"about"];
    }
    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
}

/*****************************************************************************
* VLC About Window
*****************************************************************************/

- (void)showAbout
{
    [self window];

    /* Show the window */
    [o_credits_scrollview setHidden:YES];
    [o_credits_textview setHidden:YES];
    [_joinusTextView setHidden:NO];
    [o_copyright_field setHidden:NO];
    [o_powervlc_field setHidden:NO];
    [o_revision_field setHidden:NO];
    [o_name_version_field setHidden:NO];
    [o_credits_textview scrollPoint:NSMakePoint(0, 0)];

    /* PowerVLC: the About box is taller than the legacy one to fit the
     * attribution paragraph; force the content size so a stale saved window
     * frame from an older build can't clip it (the window isn't resizable). */
    [[self window] setContentSize:NSMakeSize(721.0, 436.0)];

    [self showWindow:nil];
}

- (void)windowDidLoad
{
    [[self window] setCollectionBehavior: NSWindowCollectionBehaviorFullScreenAuxiliary];

    NSString *copyrightText = [[[NSBundle mainBundle] infoDictionary] objectForKey:@"NSHumanReadableCopyright"];
    [o_copyright_field setStringValue: copyrightText];

    /* PowerVLC attribution, shown right below the copyright line with the very
     * same font/color as the copyright field. */
    [o_powervlc_field setEditable:NO];
    [o_powervlc_field setSelectable:YES];
    [o_powervlc_field setBordered:NO];
    [o_powervlc_field setBezeled:NO];
    [o_powervlc_field setDrawsBackground:NO];
    [[o_powervlc_field cell] setUsesSingleLineMode:NO];
    [[o_powervlc_field cell] setScrollable:NO];
    [[o_powervlc_field cell] setWraps:YES];
    [o_powervlc_field setFont:[o_copyright_field font]];
    [o_powervlc_field setTextColor:[o_copyright_field textColor]];
    [o_powervlc_field setStringValue:_NS("PowerVLC Copyright © 2026 Olsro. PowerVLC is an unofficial fork of VLC, not affiliated with VideoLAN. PowerVLC could not have existed without all the contributors who have worked on VLC since its very beginning. A heartfelt thank you to each and every one of them.")];

    /* l10n */
    [[self window] setTitle: @"PowerVLC"];
    [o_name_field setStringValue: @"PowerVLC"];
    NSDictionary *stringAttributes = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:NSUnderlineStyleSingle], NSUnderlineStyleAttributeName, [NSColor VLCSecondaryLabelColor], NSForegroundColorAttributeName, [NSFont systemFontOfSize:13], NSFontAttributeName, nil];
    NSAttributedString *attrStr;
    attrStr = [[NSAttributedString alloc] initWithString:_NS("Credits") attributes:stringAttributes];
    [o_credits_btn setAttributedTitle:attrStr];
    attrStr = [[NSAttributedString alloc] initWithString:_NS("License") attributes:stringAttributes];
    [o_gpl_btn setAttributedTitle:attrStr];
    attrStr = [[NSAttributedString alloc] initWithString:_NS("Authors") attributes:stringAttributes];
    [o_authors_btn setAttributedTitle:attrStr];
    [o_trademarks_txt setStringValue:_NS("VLC media player and VideoLAN are trademarks of the VideoLAN Association.")];

    /* setup the creator / revision field */
    NSString *compiler;
#ifdef __clang__
    compiler = [NSString stringWithFormat:@"clang %s", __clang_version__];
#else
    compiler = [NSString stringWithFormat:@"llvm-gcc %s", __VERSION__];
#endif
    [o_revision_field setStringValue: [NSString stringWithFormat:@"Compiled by %s with %@ (%s %s)", VLC_CompileBy(), compiler, __DATE__, __TIME__]];

    /* Setup the nameversion field */
#ifdef POWERVLC_VERSION
    [o_name_version_field setStringValue: [NSString stringWithFormat:@"Version %s (%s) - Forked from VLC %s", POWERVLC_VERSION, __DATE__, VERSION_MESSAGE]];
#else
    [o_name_version_field setStringValue: [NSString stringWithFormat:@"Version %s (%s)", VERSION_MESSAGE, PLATFORM]];
#endif

    NSMutableArray *tmpArray = [NSMutableArray arrayWithArray: [toNSStr(psz_authors) componentsSeparatedByString:@"\n\n"]];
    NSUInteger count = [tmpArray count];
    for (NSUInteger i = 0; i < count; i++) {
        [tmpArray replaceObjectAtIndex:i withObject:[[tmpArray objectAtIndex:i]stringByReplacingOccurrencesOfString:@"\n" withString:@", "]];
        [tmpArray replaceObjectAtIndex:i withObject:[[tmpArray objectAtIndex:i]stringByReplacingOccurrencesOfString:@", -" withString:@"\n-" options:0 range:NSRangeFromString(@"0 30")]];
        [tmpArray replaceObjectAtIndex:i withObject:[[tmpArray objectAtIndex:i]stringByReplacingOccurrencesOfString:@"-, " withString:@"-\n" options:0 range:NSRangeFromString(@"0 30")]];
        [tmpArray replaceObjectAtIndex:i withObject:[[tmpArray objectAtIndex:i]stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]]];
    }
    _authorsString = [tmpArray componentsJoinedByString:@"\n\n"];

    /* setup join us! */
    NSString *joinus = toNSStr(_(""
                                 "<p>VLC media player is a free and open source media player, encoder, and "
                                 "streamer made by the volunteers of the <a href=\"https://www.videolan.org/"
                                 "\"><span style=\" text-decoration: underline; color:#0057ae;\">VideoLAN</"
                                 "span></a> community.</p><p>VLC uses its internal codecs, works on "
                                 "essentially every popular platform, and can read almost all files, CDs, "
                                 "DVDs, network streams, capture cards and other media formats!</p><p><a href="
                                 "\"https://www.videolan.org/contribute/\"><span style=\" text-decoration: "
                                 "underline; color:#0057ae;\">Help and join us!</span></a>"));

    NSString *joinUsWithStyle = [NSString stringWithFormat:@"<div style=\"text-align:left;font-family: -apple-system, Helvetica Neue;\">%@</div>", joinus];
    NSMutableAttributedString *joinus_readytorender = [[NSMutableAttributedString alloc] initWithHTML:[joinUsWithStyle dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES]
                                                                                              options:@{NSCharacterEncodingDocumentOption : [NSNumber numberWithInt:NSUTF8StringEncoding]}
                                                                                   documentAttributes:NULL];
    [joinus_readytorender setAttributes:@{NSForegroundColorAttributeName : [NSColor VLCSecondaryLabelColor],
                                          NSFontAttributeName : [NSFont systemFontOfSize:12.]}
                                  range:NSMakeRange(0, joinus_readytorender.length)];
    /* PowerVLC: render the "join us" blurb in an NSTextView instead of the XIB
     * NSTextField, so we can intercept clicks on its VideoLAN links and route
     * them through the confirmation dialog (see -textView:clickedOnLink:...).
     * The original NSTextField is kept (hidden) so the Auto Layout constraints
     * that position this area stay intact; the text view is pinned on top of it. */
    NSView *joinusAnchor = (NSView *)o_joinus_txt;
    NSView *joinusHost = [joinusAnchor superview];
    _joinusTextView = [[NSTextView alloc] initWithFrame:[joinusAnchor frame]];
    [_joinusTextView setTranslatesAutoresizingMaskIntoConstraints:NO];
    [_joinusTextView setDrawsBackground:NO];
    [_joinusTextView setEditable:NO];
    [_joinusTextView setSelectable:YES];
    [_joinusTextView setTextContainerInset:NSMakeSize(0.0, 0.0)];
    [[_joinusTextView textContainer] setLineFragmentPadding:0.0];
    [_joinusTextView setDelegate:self];
    [[_joinusTextView textStorage] setAttributedString:joinus_readytorender];
    [joinusHost addSubview:_joinusTextView];
    [joinusHost addConstraints:@[
        [NSLayoutConstraint constraintWithItem:_joinusTextView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:joinusAnchor attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:_joinusTextView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:joinusAnchor attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:_joinusTextView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:joinusAnchor attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:_joinusTextView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:joinusAnchor attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0]
    ]];
    [joinusAnchor setHidden:YES];

    [o_credits_textview setString: @""];

    /* Setup the window */
    [o_credits_textview setDrawsBackground: NO];
    [o_credits_scrollview setDrawsBackground: NO];
    [[self window] setExcludedFromWindowsMenu:YES];
    [[self window] setMenu:nil];

    if (config_GetInt(getIntf(), "macosx-icon-change")) {
        /* After day 354 of the year, the usual VLC cone is replaced by another cone
         * wearing a Father Xmas hat.
         * Note: this icon doesn't represent an endorsement of The Coca-Cola Company.
         */
        NSCalendar *gregorian =
        [[NSCalendar alloc] initWithCalendarIdentifier:NSGregorianCalendar];
        NSUInteger dayOfYear = [gregorian ordinalityOfUnit:NSDayCalendarUnit inUnit:NSYearCalendarUnit forDate:[NSDate date]];

        if (dayOfYear >= 354)
            [o_icon_view setImage: [NSImage imageNamed:@"VLC-Xmas"]];
    }
}

- (void)windowDidBecomeKey:(NSNotification *)notification
{
    [(VLCScrollingClipView *)[o_credits_scrollview contentView] startScrolling];
}

- (void)windowDidResignKey:(NSNotification *)notification
{
    [(VLCScrollingClipView *)[o_credits_scrollview contentView] stopScrolling];
}

- (IBAction)buttonAction:(id)sender
{
    [o_credits_scrollview setHidden:NO];
    [o_credits_textview setHidden:NO];
    [_joinusTextView setHidden:YES];
    [o_copyright_field setHidden:YES];
    [o_powervlc_field setHidden:YES];
    [o_revision_field setHidden:YES];
    [o_name_version_field setHidden:YES];

    NSString *stringToDisplay;
    if (sender == o_authors_btn)
        stringToDisplay = _authorsString;
    else if (sender == o_credits_btn)
        stringToDisplay = [toNSStr(psz_thanks) stringByReplacingOccurrencesOfString:@"\n" withString:@" "
                                                                            options:0 range:NSRangeFromString(@"680 2")];
    else
        stringToDisplay = toNSStr(psz_license);

    NSAttributedString *attributedString = [[NSAttributedString alloc] initWithString:stringToDisplay
                                                                           attributes:@{NSForegroundColorAttributeName : [NSColor VLCSecondaryLabelColor],
                                                                                        NSFontAttributeName : [NSFont systemFontOfSize:12.]}];
    [[o_credits_textview textStorage] setAttributedString:attributedString];

    VLCScrollingClipView *scrollView = (VLCScrollingClipView *)[o_credits_scrollview contentView];
    [scrollView resetScrolling];
    [scrollView startScrolling];
}

/* Intercept clicks on the VideoLAN links embedded in the "join us" blurb and
 * route them through the confirmation dialog instead of opening them directly. */
- (BOOL)textView:(NSTextView *)textView clickedOnLink:(id)link atIndex:(NSUInteger)charIndex
{
    NSURL *url = nil;
    if ([link isKindOfClass:[NSURL class]])
        url = link;
    else if ([link isKindOfClass:[NSString class]])
        url = [NSURL URLWithString:link];

    [VLCMain openURLWithVideoLANConfirmation:url];

    /* Returning YES tells AppKit we handled the click, so it won't open the
     * link itself and bypass the confirmation. */
    return YES;
}

/*****************************************************************************
* VLC GPL Window, action called from the about window and the help menu
*****************************************************************************/

- (void)showGPL
{
    [self showAbout];
    [self buttonAction:nil];
}

@end
