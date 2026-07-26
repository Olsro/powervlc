/*****************************************************************************
 * VLCLegacyHUDWindow.m: shared HUD panel chrome for the legacy interface
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

#import "VLCLegacyHUDWindow.h"
#import "VLCLegacyControls.h"

/*****************************************************************************
 * HUD chrome views (moved from VLCLegacyMediaInfo, shared by every black
 * tabbed window)
 *****************************************************************************/

@implementation VLCLegacyHUDBackgroundView
- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor colorWithCalibratedWhite:0.09f alpha:0.92f] set];
    [VLCLegacyRoundedRectPath([self bounds], 8.0f) fill];
    /* subtle outline, like the HUD panels */
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.12f] set];
    NSBezierPath *outline = VLCLegacyRoundedRectPath(
        NSInsetRect([self bounds], 0.5f, 0.5f), 8.0f);
    [outline setLineWidth:1.0f];
    [outline stroke];
}
@end

@implementation VLCLegacyHUDTabHighlightView
- (void)drawRect:(NSRect)dirtyRect
{
    [[NSColor colorWithCalibratedWhite:1.0f alpha:0.16f] set];
    [VLCLegacyRoundedRectPath([self bounds], 5.0f) fill];
}
@end

@implementation VLCLegacyHUDCloseButton
- (void)setTarget:(id)t action:(SEL)a
{
    target = t;
    action = a;
}

- (void)setDarkStyle:(BOOL)flag
{
    darkStyle = flag;
    [self setNeedsDisplay:YES];
}

- (void)drawRect:(NSRect)dirtyRect
{
    NSRect b = NSInsetRect([self bounds], 4.5f, 4.5f);
    if (darkStyle)
        [[NSColor colorWithCalibratedWhite:pressed ? 0.1f : 0.35f
                                     alpha:1.0f] set];
    else
        [[NSColor colorWithCalibratedWhite:pressed ? 1.0f : 0.8f
                                     alpha:1.0f] set];
    NSBezierPath *cross = [NSBezierPath bezierPath];
    [cross setLineWidth:2.0f];
    [cross setLineCapStyle:NSRoundLineCapStyle];
    [cross moveToPoint:NSMakePoint(NSMinX(b), NSMinY(b))];
    [cross lineToPoint:NSMakePoint(NSMaxX(b), NSMaxY(b))];
    [cross moveToPoint:NSMakePoint(NSMinX(b), NSMaxY(b))];
    [cross lineToPoint:NSMakePoint(NSMaxX(b), NSMinY(b))];
    [cross stroke];
}

- (void)mouseDown:(NSEvent *)event
{
    pressed = YES;
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event
{
    pressed = NO;
    [self setNeedsDisplay:YES];
    NSPoint p = [self convertPoint:[event locationInWindow] fromView:nil];
    if (NSPointInRect(p, [self bounds]) && target)
        [target performSelector:action withObject:self];
}
@end

@implementation VLCLegacyHUDPanel
- (BOOL)canBecomeKeyWindow
{
    /* borderless windows refuse key status by default; the text fields
     * and sliders need it */
    return YES;
}
@end

/*****************************************************************************
 * VLCLegacyHUDController
 *****************************************************************************/

@implementation VLCLegacyHUDController

- (void)dealloc
{
    int i;
    for (i = 0; i < tabCount; i++)
        [panes[i] release];
    [window release];
    [super dealloc];
}

- (void)buildHUDWithTitle:(NSString *)title
                     size:(NSSize)size
                tabTitles:(NSArray *)titles
             bottomMargin:(float)bottomMargin
{
    hudWidth = size.width;
    hudHeight = size.height;
    tabCount = titles ? (int)[titles count] : 0;
    if (tabCount > VLC_LEGACY_HUD_MAX_TABS)
        tabCount = VLC_LEGACY_HUD_MAX_TABS;

    window = [[VLCLegacyHUDPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, hudWidth, hudHeight)
                  styleMask:NSBorderlessWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:title];
    [window setOpaque:NO];
    [window setBackgroundColor:[NSColor clearColor]];
    [window setMovableByWindowBackground:YES];
    [window setReleasedWhenClosed:NO];
    [window setDelegate:(id)self];
    NSView *content = [window contentView];

    VLCLegacyHUDBackgroundView *background =
        [[[VLCLegacyHUDBackgroundView alloc]
            initWithFrame:NSMakeRect(0, 0, hudWidth, hudHeight)]
            autorelease];
    [background setAutoresizingMask:NSViewWidthSizable
                                   | NSViewHeightSizable];
    [content addSubview:background];

    VLCLegacyHUDCloseButton *closeButton = [[[VLCLegacyHUDCloseButton alloc]
        initWithFrame:NSMakeRect(8, hudHeight - 22, 16, 16)] autorelease];
    [closeButton setTarget:self action:@selector(closeWindow:)];
    [content addSubview:closeButton];

    NSTextField *titleLabel = [self hudLabel:title
        frame:NSMakeRect(60, hudHeight - 22, hudWidth - 120, 15)
         bold:YES in:content];
    [titleLabel setAlignment:NSCenterTextAlignment];

    float paneTop = hudHeight - 34;
    if (tabCount > 0) {
        tabHighlight = [[[VLCLegacyHUDTabHighlightView alloc]
            initWithFrame:NSZeroRect] autorelease];
        [content addSubview:tabHighlight];

        /* equal-width tab buttons sized to fit the localized captions */
        float gap = 14;
        float buttonWidth = 96;
        int i;
        for (i = 0; i < tabCount; i++) {
            NSString *caption = [titles objectAtIndex:i];
            float w = (float)ceil([caption sizeWithAttributes:
                [NSDictionary dictionaryWithObjectsAndKeys:
                    [NSFont boldSystemFontOfSize:12], NSFontAttributeName,
                    nil]].width) + 12;
            if (w > buttonWidth)
                buttonWidth = w;
        }
        if (tabCount * (buttonWidth + gap) > hudWidth - 24)
            buttonWidth = (hudWidth - 24) / tabCount - gap;
        float x = (hudWidth - (tabCount * buttonWidth
                               + (tabCount - 1) * gap)) / 2;
        for (i = 0; i < tabCount; i++) {
            tabButtons[i] = [[[NSButton alloc]
                initWithFrame:NSMakeRect(x, hudHeight - 52, buttonWidth, 20)]
                autorelease];
            [tabButtons[i] setButtonType:NSMomentaryChangeButton];
            [tabButtons[i] setBordered:NO];
            [tabButtons[i] setTitle:[titles objectAtIndex:i]];
            [tabButtons[i] setTag:i];
            [tabButtons[i] setTarget:self];
            [tabButtons[i] setAction:@selector(selectPane:)];
            [content addSubview:tabButtons[i]];
            x += buttonWidth + gap;
        }
        paneTop = hudHeight - 60;
    }

    paneContainer = [[[NSView alloc]
        initWithFrame:NSMakeRect(12, bottomMargin, hudWidth - 24,
                                 paneTop - bottomMargin)] autorelease];
    [content addSubview:paneContainer];
}

- (void)setPane:(NSView *)pane atIndex:(int)index
{
    if (index < 0 || index >= VLC_LEGACY_HUD_MAX_TABS)
        return;
    [panes[index] autorelease];
    panes[index] = [pane retain];
    if (tabCount == 0 && index == 0)
        [paneContainer addSubview:pane];
}

- (void)selectPane:(id)sender
{
    [self selectPaneAtIndex:(int)[sender tag]];
}

- (void)selectPaneAtIndex:(int)index
{
    if (index < 0 || index >= tabCount)
        return;
    selectedTab = index;
    [tabHighlight setFrame:NSInsetRect([tabButtons[index] frame], -4, -2)];
    [tabHighlight setNeedsDisplay:YES];
    int i;
    for (i = 0; i < tabCount; i++) {
        if (i == index) {
            if (panes[i] && ![panes[i] superview])
                [paneContainer addSubview:panes[i]];
        } else if ([panes[i] superview])
            [panes[i] removeFromSuperview];
    }
    for (i = 0; i < tabCount; i++) {
        NSDictionary *attributes = [NSDictionary
            dictionaryWithObjectsAndKeys:
                i == index
                    ? [NSFont boldSystemFontOfSize:12]
                    : [NSFont systemFontOfSize:12],
                NSFontAttributeName,
                i == index
                    ? [NSColor whiteColor]
                    : [NSColor colorWithCalibratedWhite:0.62f alpha:1.0f],
                NSForegroundColorAttributeName,
                nil];
        [tabButtons[i] setAttributedTitle:
            [[[NSAttributedString alloc]
                initWithString:[tabButtons[i] title]
                    attributes:attributes] autorelease]];
    }
}

- (int)selectedPaneIndex
{
    return selectedTab;
}

- (NSPanel *)hudWindow
{
    return window;
}

- (NSView *)paneContainer
{
    return paneContainer;
}

- (void)buildWindow
{
    /* subclass responsibility */
}

- (void)windowWillShow
{
}

- (void)showWindow
{
    if (!window) {
        [self buildWindow];
        if (tabCount > 0)
            [self selectPaneAtIndex:0];
        [window center];
    }
    [self windowWillShow];
    [window makeKeyAndOrderFront:nil];
}

- (void)toggleWindow
{
    if (window && [window isVisible])
        [self closeWindow:nil];
    else
        [self showWindow];
}

- (void)closeWindow:(id)sender
{
    [window orderOut:sender];
}

/*****************************************************************************
 * dark control factories
 *****************************************************************************/

- (NSTextField *)hudLabel:(NSString *)text frame:(NSRect)frame
                     bold:(BOOL)bold in:(NSView *)parent
{
    NSTextField *label = [[[NSTextField alloc] initWithFrame:frame]
        autorelease];
    [label setEditable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [[label cell] setFont:bold ? [NSFont boldSystemFontOfSize:11]
                                : [NSFont systemFontOfSize:10]];
    [label setTextColor:bold
        ? [NSColor whiteColor]
        : [NSColor colorWithCalibratedWhite:0.70f alpha:1.0f]];
    [[label cell] setLineBreakMode:NSLineBreakByTruncatingTail];
    [label setStringValue:text];
    [parent addSubview:label];
    return label;
}

- (NSTextField *)hudValue:(NSRect)frame editable:(BOOL)editable
                       in:(NSView *)parent
{
    NSTextField *field = [[[NSTextField alloc] initWithFrame:frame]
        autorelease];
    [field setEditable:editable];
    [field setSelectable:YES];
    [field setBordered:NO];
    [field setDrawsBackground:editable];
    if (editable)
        [field setBackgroundColor:
            [NSColor colorWithCalibratedWhite:0.18f alpha:1.0f]];
    [field setTextColor:[NSColor whiteColor]];
    [[field cell] setFont:[NSFont systemFontOfSize:11]];
    if (editable) {
        [[field cell] setWraps:NO];
        [[field cell] setScrollable:YES];
    } else
        [[field cell] setLineBreakMode:NSLineBreakByTruncatingMiddle];
    [field setStringValue:@""];
    [parent addSubview:field];
    return field;
}

- (NSButton *)hudCheckbox:(NSString *)title frame:(NSRect)frame
                   action:(SEL)action in:(NSView *)parent
{
    NSButton *checkbox = [[[NSButton alloc] initWithFrame:frame]
        autorelease];
    [checkbox setButtonType:NSSwitchButton];
    [checkbox setTitle:title];
    /* white caption over the dark HUD */
    NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSFont systemFontOfSize:11], NSFontAttributeName,
        [NSColor whiteColor], NSForegroundColorAttributeName, nil];
    [checkbox setAttributedTitle:
        [[[NSAttributedString alloc] initWithString:title
                                         attributes:attributes]
            autorelease]];
    [checkbox setTarget:self];
    [checkbox setAction:action];
    [parent addSubview:checkbox];
    return checkbox;
}

- (NSButton *)hudPushButton:(NSString *)title frame:(NSRect)frame
                     action:(SEL)action in:(NSView *)parent
{
    /* never truncate a localized caption: grow leftward when the button
     * would overflow its parent (right-anchored Reset buttons) */
    NSFont *font = [NSFont systemFontOfSize:
        [NSFont systemFontSizeForControlSize:NSSmallControlSize]];
    float needed = (float)ceil([title sizeWithAttributes:
        [NSDictionary dictionaryWithObject:font
                                    forKey:NSFontAttributeName]].width) + 28;
    if (frame.size.width < needed) {
        if (NSMaxX(frame) + needed - frame.size.width
                > [parent bounds].size.width - 4)
            frame.origin.x -= needed - frame.size.width;
        frame.size.width = needed;
    }

    NSButton *button = [[[NSButton alloc] initWithFrame:frame] autorelease];
    [button setTitle:title];
    [button setBezelStyle:NSRoundedBezelStyle];
    [[button cell] setControlSize:NSSmallControlSize];
    [[button cell] setFont:font];
    [button setTarget:self];
    [button setAction:action];
    [parent addSubview:button];
    return button;
}

- (NSSlider *)hudSlider:(NSRect)frame min:(double)min max:(double)max
                 action:(SEL)action in:(NSView *)parent
{
    NSSlider *slider = [[[NSSlider alloc] initWithFrame:frame] autorelease];
    [slider setMinValue:min];
    [slider setMaxValue:max];
    [[slider cell] setControlSize:NSSmallControlSize];
    [slider setContinuous:YES];
    [slider setTarget:self];
    [slider setAction:action];
    [parent addSubview:slider];
    return slider;
}

- (NSPopUpButton *)hudPopup:(NSRect)frame action:(SEL)action
                         in:(NSView *)parent
{
    NSPopUpButton *popup = [[[NSPopUpButton alloc] initWithFrame:frame
                                                       pullsDown:NO]
        autorelease];
    [[popup cell] setControlSize:NSSmallControlSize];
    [[popup cell] setFont:
        [NSFont systemFontOfSize:
            [NSFont systemFontSizeForControlSize:NSSmallControlSize]]];
    [popup setTarget:self];
    [popup setAction:action];
    [parent addSubview:popup];
    return popup;
}

- (NSStepper *)hudStepper:(NSRect)frame min:(double)min max:(double)max
                increment:(double)increment action:(SEL)action
                       in:(NSView *)parent
{
    NSStepper *stepper = [[[NSStepper alloc] initWithFrame:frame]
        autorelease];
    [stepper setMinValue:min];
    [stepper setMaxValue:max];
    [stepper setIncrement:increment];
    [stepper setValueWraps:NO];
    [[stepper cell] setControlSize:NSSmallControlSize];
    [stepper setTarget:self];
    [stepper setAction:action];
    [parent addSubview:stepper];
    return stepper;
}

@end

/*****************************************************************************
 * app-modal prompts (10.4-safe stand-ins for the 3.0 sheet panels)
 *****************************************************************************/

static NSPanel *promptPanel(NSString *title, NSString *subtitle,
                            NSString *okTitle, NSString *cancelTitle,
                            id target)
{
    NSPanel *panel = [[NSPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 380, 130)
                  styleMask:NSTitledWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [panel setTitle:title];
    [panel setReleasedWhenClosed:NO];
    NSView *content = [panel contentView];

    NSTextField *label = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(16, 96, 348, 17)] autorelease];
    [label setEditable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [[label cell] setFont:[NSFont systemFontOfSize:12]];
    [label setStringValue:subtitle];
    [content addSubview:label];

    NSButton *okButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(270, 8, 96, 28)] autorelease];
    [okButton setTitle:okTitle];
    [okButton setBezelStyle:NSRoundedBezelStyle];
    [okButton setKeyEquivalent:@"\r"];
    [okButton setTarget:target];
    [okButton setAction:@selector(promptOK:)];
    [content addSubview:okButton];

    NSButton *cancelButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(170, 8, 96, 28)] autorelease];
    [cancelButton setTitle:cancelTitle];
    [cancelButton setBezelStyle:NSRoundedBezelStyle];
    [cancelButton setKeyEquivalent:@"\033"];
    [cancelButton setTarget:target];
    [cancelButton setAction:@selector(promptCancel:)];
    [content addSubview:cancelButton];

    [panel center];
    return panel;
}

@interface VLCLegacyPromptHelper : NSObject
{
@public
    BOOL accepted;
}
@end

@implementation VLCLegacyPromptHelper
- (void)promptOK:(id)sender
{
    accepted = YES;
    [NSApp stopModal];
}

- (void)promptCancel:(id)sender
{
    accepted = NO;
    [NSApp stopModal];
}
@end

NSString *VLCLegacyRunTextPrompt(NSString *title, NSString *subtitle,
                                 NSString *okTitle, NSString *cancelTitle,
                                 NSString *initialValue)
{
    VLCLegacyPromptHelper *helper =
        [[[VLCLegacyPromptHelper alloc] init] autorelease];
    NSPanel *panel = promptPanel(title, subtitle, okTitle, cancelTitle,
                                 helper);
    NSTextField *field = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(16, 56, 348, 22)] autorelease];
    [[field cell] setFont:[NSFont systemFontOfSize:12]];
    [[field cell] setWraps:NO];
    [[field cell] setScrollable:YES];
    [field setStringValue:initialValue ? initialValue : @""];
    [[panel contentView] addSubview:field];

    [panel makeKeyAndOrderFront:nil];
    [field selectText:nil];
    [NSApp runModalForWindow:panel];
    [panel orderOut:nil];
    NSString *result = helper->accepted
        ? [[[field stringValue] copy] autorelease] : nil;
    [panel release];
    return result;
}

NSInteger VLCLegacyRunPopupPrompt(NSString *title, NSString *subtitle,
                                  NSString *okTitle, NSString *cancelTitle,
                                  NSArray *items)
{
    VLCLegacyPromptHelper *helper =
        [[[VLCLegacyPromptHelper alloc] init] autorelease];
    NSPanel *panel = promptPanel(title, subtitle, okTitle, cancelTitle,
                                 helper);
    NSPopUpButton *popup = [[[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(16, 54, 348, 26) pullsDown:NO] autorelease];
    unsigned i;
    for (i = 0; i < [items count]; i++)
        /* addItemWithTitle: merges duplicate titles; raw menu items keep
         * them distinct */
        [[popup menu] addItem:[[[NSMenuItem alloc]
            initWithTitle:[items objectAtIndex:i]
                   action:nil keyEquivalent:@""] autorelease]];
    [[panel contentView] addSubview:popup];

    [panel makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:panel];
    [panel orderOut:nil];
    NSInteger result = helper->accepted
        ? [popup indexOfSelectedItem] : -1;
    [panel release];
    return result;
}
