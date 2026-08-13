/*****************************************************************************
 * VLCCustomCropArWindowController.m: custom crop / aspect ratio panel
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

#import "VLCCustomCropArWindowController.h"

#import "VLCStringUtility.h"

@interface VLCCustomCropArWindowController ()
{
    NSTextField *_numeratorField;
    NSTextField *_denominatorField;
}
@end

@implementation VLCCustomCropArWindowController

static NSTextField *CreateLabel(NSRect frame, NSString *string, NSTextAlignment alignment)
{
    NSTextField *label = [[NSTextField alloc] initWithFrame:frame];
    [label setStringValue:string];
    [label setAlignment:alignment];
    [label setBezeled:NO];
    [label setDrawsBackground:NO];
    [label setEditable:NO];
    [label setSelectable:NO];
    return label;
}

- (instancetype)initWithTitle:(NSString *)title ratio:(NSString *)ratio
{
    NSWindow *window =
        [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 360, 132)
                                   styleMask:NSWindowStyleMaskTitled
                                     backing:NSBackingStoreBuffered
                                       defer:YES];
    self = [super initWithWindow:window];
    if (self == nil)
        return nil;

    [window setTitle:title];

    NSView *content = [window contentView];

    [content addSubview:CreateLabel(NSMakeRect(20, 92, 320, 17), title,
                                    NSTextAlignmentLeft)];

    _numeratorField = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 56, 130, 22)];
    _denominatorField = [[NSTextField alloc] initWithFrame:NSMakeRect(170, 56, 130, 22)];
    [content addSubview:_numeratorField];
    [content addSubview:CreateLabel(NSMakeRect(150, 58, 20, 17), @":",
                                    NSTextAlignmentCenter)];
    [content addSubview:_denominatorField];

    /* Start from what is in force, when it is a ratio -- the variable can
     * also hold a crop window or a border, which this panel cannot show. */
    unsigned num = 0, den = 0;
    if (ratio != nil && sscanf([ratio UTF8String], "%u:%u", &num, &den) == 2
     && num > 0 && den > 0) {
        [_numeratorField setIntegerValue:num];
        [_denominatorField setIntegerValue:den];
    }

    NSButton *cancelButton =
        [[NSButton alloc] initWithFrame:NSMakeRect(150, 14, 96, 32)];
    [cancelButton setTitle:_NS("Cancel")];
    [cancelButton setBezelStyle:NSBezelStyleRounded];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(cancelPressed:)];
    [cancelButton setKeyEquivalent:@"\033"];
    [content addSubview:cancelButton];

    NSButton *applyButton =
        [[NSButton alloc] initWithFrame:NSMakeRect(248, 14, 96, 32)];
    [applyButton setTitle:_NS("Apply")];
    [applyButton setBezelStyle:NSBezelStyleRounded];
    [applyButton setTarget:self];
    [applyButton setAction:@selector(applyPressed:)];
    [applyButton setKeyEquivalent:@"\r"];
    [content addSubview:applyButton];

    /* ⚠ A window built in code has no key view loop -- a nib carries one,
     * this does not -- and without it Tab does not walk from one field to
     * the next, which is how anyone types a ratio. */
    [_numeratorField setNextKeyView:_denominatorField];
    [_denominatorField setNextKeyView:cancelButton];
    [cancelButton setNextKeyView:applyButton];
    [applyButton setNextKeyView:_numeratorField];

    [window setInitialFirstResponder:_numeratorField];
    return self;
}

- (void)applyPressed:(id)sender
{
    [NSApp stopModalWithCode:NSModalResponseOK];
}

- (void)cancelPressed:(id)sender
{
    [NSApp stopModalWithCode:NSModalResponseCancel];
}

- (NSString *)ratio
{
    NSInteger num = [_numeratorField integerValue];
    NSInteger den = [_denominatorField integerValue];

    /* An empty or zero side would reach the vout as "0:0", which reads as
     * "no crop at all" -- silently doing the opposite of what was asked. */
    if (num <= 0 || den <= 0)
        return nil;

    return [NSString stringWithFormat:@"%ld:%ld", (long)num, (long)den];
}

+ (NSString *)runModalWithTitle:(NSString *)title currentRatio:(NSString *)ratio
{
    VLCCustomCropArWindowController *controller =
        [[VLCCustomCropArWindowController alloc] initWithTitle:title ratio:ratio];

    NSWindow *window = [controller window];
    [window center];
    const NSInteger result = [NSApp runModalForWindow:window];
    [window orderOut:nil];

    return result == NSModalResponseOK ? [controller ratio] : nil;
}

@end
