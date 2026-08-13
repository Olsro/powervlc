/*****************************************************************************
 * VLCLegacyCustomCropAr.m: custom crop / aspect ratio panel (legacy)
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#import <vlc_common.h>

#import "VLCLegacyCustomCropAr.h"
#import "misc.h"

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

@implementation VLCLegacyCustomCropAr

- (NSTextField *)makeLabel:(NSString *)string frame:(NSRect)frame
                 alignment:(NSTextAlignment)alignment in:(NSView *)parent
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame] autorelease];
    [label setStringValue:string];
    [label setAlignment:alignment];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    [parent addSubview:label];
    return label;
}

- (id)initWithTitle:(NSString *)title ratio:(NSString *)ratio
{
    self = [super init];
    if (!self)
        return nil;

    window = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 360, 132)
                  styleMask:NSTitledWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:title];
    [window setReleasedWhenClosed:NO];
    VLCLegacyDenyNativeFullscreen(window);

    NSView *content = [window contentView];

    [self makeLabel:title frame:NSMakeRect(20, 92, 320, 17)
          alignment:NSLeftTextAlignment in:content];

    numeratorField = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(20, 56, 130, 22)] autorelease];
    [content addSubview:numeratorField];
    [self makeLabel:@":" frame:NSMakeRect(150, 58, 20, 17)
          alignment:NSCenterTextAlignment in:content];
    denominatorField = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(170, 56, 130, 22)] autorelease];
    [content addSubview:denominatorField];

    /* Start from what is in force, when it is a ratio -- the variable can
     * also hold a crop window or a border, which this panel cannot show. */
    unsigned num = 0, den = 0;
    if (ratio && sscanf([ratio UTF8String], "%u:%u", &num, &den) == 2
     && num > 0 && den > 0) {
        [numeratorField setIntValue:(int)num];
        [denominatorField setIntValue:(int)den];
    }

    NSButton *cancelButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(150, 14, 96, 32)] autorelease];
    [cancelButton setTitle:_NS("Cancel")];
    [cancelButton setBezelStyle:NSRoundedBezelStyle];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(cancelPressed:)];
    [cancelButton setKeyEquivalent:@"\033"];
    [content addSubview:cancelButton];

    NSButton *applyButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(248, 14, 96, 32)] autorelease];
    [applyButton setTitle:_NS("Apply")];
    [applyButton setBezelStyle:NSRoundedBezelStyle];
    [applyButton setTarget:self];
    [applyButton setAction:@selector(applyPressed:)];
    [applyButton setKeyEquivalent:@"\r"];
    [content addSubview:applyButton];

    /* ⚠ A window built in code has no key view loop -- a nib carries one,
     * this does not -- and without it Tab does not walk from one field to
     * the next, which is how anyone types a ratio. */
    [numeratorField setNextKeyView:denominatorField];
    [denominatorField setNextKeyView:cancelButton];
    [cancelButton setNextKeyView:applyButton];
    [applyButton setNextKeyView:numeratorField];

    [window setInitialFirstResponder:numeratorField];
    return self;
}

- (void)dealloc
{
    [window release];
    [super dealloc];
}

- (void)applyPressed:(id)sender
{
    [NSApp stopModalWithCode:NSOKButton];
}

- (void)cancelPressed:(id)sender
{
    [NSApp stopModalWithCode:NSCancelButton];
}

- (NSString *)ratio
{
    int num = [numeratorField intValue];
    int den = [denominatorField intValue];

    /* An empty or zero side would reach the vout as "0:0", which reads as
     * "no crop at all" -- silently doing the opposite of what was asked. */
    if (num <= 0 || den <= 0)
        return nil;

    return [NSString stringWithFormat:@"%d:%d", num, den];
}

+ (NSString *)runModalWithTitle:(NSString *)title currentRatio:(NSString *)ratio
{
    VLCLegacyCustomCropAr *panel = [[VLCLegacyCustomCropAr alloc]
        initWithTitle:title ratio:ratio];
    if (!panel)
        return nil;

    [panel->window center];
    NSInteger result = [NSApp runModalForWindow:panel->window];
    [panel->window orderOut:nil];

    NSString *value = (result == NSOKButton) ? [panel ratio] : nil;
    [value retain];
    [panel release];
    return [value autorelease];
}

@end
