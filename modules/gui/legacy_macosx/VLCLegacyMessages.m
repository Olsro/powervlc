/*****************************************************************************
 * VLCLegacyMessages.m: Messages and Errors windows (legacy interface)
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

#import "VLCLegacyMessages.h"
#import "misc.h"

#include <vlc_common.h>
#include <vlc_interface.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/*****************************************************************************
 * Messages window
 *****************************************************************************/

static void MsgCallback(void *data, int type, const vlc_log_t *item,
                        const char *format, va_list ap)
{
    static const char *const type_names[4] =
        { "info", "error", "warning", "debug" };
    char *psz_message = NULL;
    if (vasprintf(&psz_message, format, ap) == -1)
        return;

    char *psz_line = NULL;
    if (asprintf(&psz_line, "%s %s: %s\n",
                 item->psz_module ? item->psz_module : "",
                 type_names[type & 3], psz_message) == -1) {
        free(psz_message);
        return;
    }
    free(psz_message);

    /* AppKit only on the main thread; the callback runs anywhere.
     * Manual pool: the callback thread has none. */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSString *line = [NSString stringWithUTF8String:psz_line];
    free(psz_line);
    if (line)
        [(VLCLegacyMessages *)data
            performSelectorOnMainThread:@selector(appendLine:)
                             withObject:line
                          waitUntilDone:NO];
    [pool release];
}

@implementation VLCLegacyMessages

- (id)initWithIntf:(intf_thread_t *)intf
{
    if (self = [super init])
        p_intf = intf;
    return self;
}

- (void)dealloc
{
    [self shutdown];
    [window release];
    [super dealloc];
}

- (void)buildWindow
{
    window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 600, 400)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSMiniaturizableWindowMask
                          | NSResizableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:_NS("Messages")];
    VLCLegacyDenyNativeFullscreen(window);
    [window setReleasedWhenClosed:NO];
    [window setDelegate:(id)self];
    [window setMinSize:NSMakeSize(400, 250)];
    NSView *content = [window contentView];
    NSRect bounds = [content bounds];

    NSScrollView *scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 40, bounds.size.width,
                                 bounds.size.height - 40)] autorelease];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSNoBorder];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    logView = [[[NSTextView alloc]
        initWithFrame:[[scroll contentView] bounds]] autorelease];
    [logView setEditable:NO];
    [logView setFont:[NSFont userFixedPitchFontOfSize:10]];
    [logView setAutoresizingMask:NSViewWidthSizable];
    [[logView textContainer] setWidthTracksTextView:YES];
    [logView setVerticallyResizable:YES];
    [logView setHorizontallyResizable:NO];
    [scroll setDocumentView:logView];
    [content addSubview:scroll];

    /* Buttons are sized to fit their titles: some localisations (e.g. the
     * French "Sauvegarder le journal") are far wider than the English
     * "Save log" and were clipped by a fixed 120 px width. */
    CGFloat const kBtnH   = 28;
    CGFloat const kBtnY   = 6;
    CGFloat const kBtnGap = 10;
    CGFloat const kBtnPad = 14;   /* breathing room past sizeToFit */
    CGFloat const kBtnMin = 90;

    NSButton *saveButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(0, kBtnY, 120, kBtnH)] autorelease];
    [saveButton setTitle:_NS("Save log")];
    [saveButton setBezelStyle:NSRoundedBezelStyle];
    [saveButton setTarget:self];
    [saveButton setAction:@selector(saveLog:)];
    [saveButton setAutoresizingMask:NSViewMinXMargin];
    [saveButton sizeToFit];

    NSButton *clearButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(0, kBtnY, 120, kBtnH)] autorelease];
    [clearButton setTitle:_NS("Clear log")];
    [clearButton setBezelStyle:NSRoundedBezelStyle];
    [clearButton setTarget:self];
    [clearButton setAction:@selector(clearLog:)];
    [clearButton setAutoresizingMask:NSViewMinXMargin];
    [clearButton sizeToFit];

    CGFloat saveW = NSWidth([saveButton frame]) + kBtnPad;
    if (saveW < kBtnMin) saveW = kBtnMin;
    CGFloat clearW = NSWidth([clearButton frame]) + kBtnPad;
    if (clearW < kBtnMin) clearW = kBtnMin;
    [saveButton setFrame:NSMakeRect(bounds.size.width - 10 - saveW,
                                    kBtnY, saveW, kBtnH)];
    [clearButton setFrame:NSMakeRect(bounds.size.width - 10 - saveW - kBtnGap - clearW,
                                     kBtnY, clearW, kBtnH)];
    [content addSubview:saveButton];
    [content addSubview:clearButton];

    [window center];
}

- (void)showWindow
{
    if (!window)
        [self buildWindow];
    if (!subscribed) {
        subscribed = YES;
        vlc_LogSet(p_intf->obj.libvlc, MsgCallback, self);
    }
    [window makeKeyAndOrderFront:nil];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [self shutdown];
}

- (void)shutdown
{
    if (subscribed) {
        subscribed = NO;
        vlc_LogSet(p_intf->obj.libvlc, NULL, NULL);
    }
}

- (void)appendLine:(NSString *)line
{
    NSTextStorage *storage = [logView textStorage];
    static NSDictionary *attributes = nil;
    if (!attributes)
        attributes = [[NSDictionary dictionaryWithObject:
            [NSFont userFixedPitchFontOfSize:10]
            forKey:NSFontAttributeName] retain];
    NSAttributedString *string = [[[NSAttributedString alloc]
        initWithString:line attributes:attributes] autorelease];
    [storage appendAttributedString:string];

    /* bound the buffer (an afternoon of -vv logs adds up) */
    unsigned length = (unsigned)[storage length];
    if (length > 400000)
        [storage deleteCharactersInRange:NSMakeRange(0, length - 300000)];

    [logView scrollRangeToVisible:NSMakeRange([storage length], 0)];
}

- (void)clearLog:(id)sender
{
    [[logView textStorage] deleteCharactersInRange:
        NSMakeRange(0, [[logView textStorage] length])];
}

- (void)saveLog:(id)sender
{
    NSSavePanel *panel = [NSSavePanel savePanel];
    NSString *name = [NSString stringWithFormat:
        _NS("PowerVLC Debug Log (%s).txt"), POWERVLC_VERSION];
    if ([panel runModalForDirectory:nil file:name]
            != NSFileHandlingPanelOKButton)
        return;
    NSData *data = [[logView string]
        dataUsingEncoding:NSUTF8StringEncoding];
    [data writeToFile:[panel filename] atomically:YES];
}

@end

/*****************************************************************************
 * Errors and Warnings panel
 *****************************************************************************/

@implementation VLCLegacyErrorPanel

- (id)initWithIntf:(intf_thread_t *)intf
{
    if (self = [super init]) {
        p_intf = intf;
        errors = [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)dealloc
{
    [errors release];
    [window release];
    [super dealloc];
}

- (void)buildWindow
{
    window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 500, 280)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSResizableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:_NS("Errors and Warnings")];
    VLCLegacyDenyNativeFullscreen(window);
    [window setReleasedWhenClosed:NO];
    [window setMinSize:NSMakeSize(400, 200)];
    NSView *content = [window contentView];
    NSRect bounds = [content bounds];

    NSScrollView *scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 40, bounds.size.width,
                                 bounds.size.height - 40)] autorelease];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSNoBorder];
    [scroll setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];

    NSSize contentSize = [[scroll contentView] bounds].size;
    errorView = [[[NSTextView alloc]
        initWithFrame:NSMakeRect(0, 0, contentSize.width,
                                 contentSize.height)] autorelease];
    [errorView setEditable:NO];
    [errorView setSelectable:YES];
    [errorView setDrawsBackground:NO];
    [errorView setFont:[NSFont systemFontOfSize:11]];
    [errorView setVerticallyResizable:YES];
    [errorView setHorizontallyResizable:NO];
    [errorView setAutoresizingMask:NSViewWidthSizable];
    [[errorView textContainer] setContainerSize:
        NSMakeSize(contentSize.width, 1.0e7)];
    [[errorView textContainer] setWidthTracksTextView:YES];
    [scroll setDocumentView:errorView];
    [content addSubview:scroll];

    NSButton *cleanupButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(bounds.size.width - 130, 6, 120, 28)]
        autorelease];
    [cleanupButton setTitle:_NS("Clean up")];
    [cleanupButton setBezelStyle:NSRoundedBezelStyle];
    [cleanupButton setTarget:self];
    [cleanupButton setAction:@selector(cleanupTable:)];
    [cleanupButton setAutoresizingMask:NSViewMinXMargin];
    [content addSubview:cleanupButton];

    [window center];
}

- (void)showWindow
{
    if (!window)
        [self buildWindow];
    [self refreshErrors];
    [window makeKeyAndOrderFront:nil];
}

- (void)refreshErrors
{
    if (errorView == nil)
        return;
    [errorView setString:[errors componentsJoinedByString:@"\n\n"]];
}

- (void)addError:(NSString *)line
{
    [errors addObject:line];
    if (window)
        [self refreshErrors];
}

- (void)cleanupTable:(id)sender
{
    [errors removeAllObjects];
    [self refreshErrors];
}

@end
