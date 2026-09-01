/*****************************************************************************
 * VLCLegacyHUDWindow.h: shared HUD panel chrome for the legacy interface
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

#import <Cocoa/Cocoa.h>

#include <vlc_common.h>

/* NSInteger/CGFloat only appeared with the 10.5 SDK */
#ifndef NSINTEGER_DEFINED
typedef int NSInteger;
typedef unsigned int NSUInteger;
#define NSINTEGER_DEFINED 1
#endif
#ifndef CGFLOAT_DEFINED
typedef float CGFloat;
#define CGFLOAT_DEFINED 1
#endif

/* Dark rounded HUD background (2.2 shipped BGHUDAppKit for this;
 * NSHUDWindowMask needs 10.6, so everything is drawn by hand) */
@interface VLCLegacyHUDBackgroundView : NSView
@end

/* rounded highlight behind the selected pane button */
@interface VLCLegacyHUDTabHighlightView : NSView
@end

/* Close "cross" drawn with beziers: a borderless NSButton corrupts over
 * the translucent HUD on Tiger */
@interface VLCLegacyHUDCloseButton : NSView
{
    id target;
    SEL action;
    BOOL pressed;
    BOOL darkStyle;
}
- (void)setTarget:(id)t action:(SEL)a;
/* dark cross for light (non-HUD) windows, e.g. Convert & Stream */
- (void)setDarkStyle:(BOOL)flag;
@end

/* borderless panel that still accepts key status (text fields need it) */
@interface VLCLegacyHUDPanel : NSPanel
@end

#define VLC_LEGACY_HUD_MAX_TABS 8

/* Base controller for the black tabbed windows (Media Information look):
 * borderless dark panel, close cross, centered title, a row of pane
 * buttons with a rounded highlight, and a swapped pane container.
 * Subclasses implement -buildPanes (create the pane views and register
 * them with setPane:atIndex:) and may override -windowWillShow. */
@interface VLCLegacyHUDController : NSObject
{
@protected
    NSPanel *window;
    NSView *paneContainer;
    NSButton *tabButtons[VLC_LEGACY_HUD_MAX_TABS];
    NSView *panes[VLC_LEGACY_HUD_MAX_TABS];
    int tabCount;
    int selectedTab;
    NSView *tabHighlight;
    float hudWidth;
    float hudHeight;
}

/* builds the window chrome; tabTitles may be nil (single pane windows).
 * The pane container fills the window between the tab row and
 * bottomMargin points from the bottom edge. */
- (void)buildHUDWithTitle:(NSString *)title
                     size:(NSSize)size
                tabTitles:(NSArray *)titles
             bottomMargin:(float)bottomMargin;
- (void)setPane:(NSView *)pane atIndex:(int)index;
- (void)selectPaneAtIndex:(int)index;
- (int)selectedPaneIndex;
- (NSPanel *)hudWindow;
- (NSView *)paneContainer;

/* subclass hooks */
- (void)buildWindow;        /* must call buildHUDWithTitle:... */
- (void)windowWillShow;     /* refresh the controls from the core state */

- (void)showWindow;
- (void)toggleWindow;
- (void)closeWindow:(id)sender;

/* control factories, all styled for the dark background */
- (NSTextField *)hudLabel:(NSString *)text frame:(NSRect)frame
                     bold:(BOOL)bold in:(NSView *)parent;
- (NSTextField *)hudValue:(NSRect)frame editable:(BOOL)editable
                       in:(NSView *)parent;
- (NSButton *)hudCheckbox:(NSString *)title frame:(NSRect)frame
                   action:(SEL)action in:(NSView *)parent;
- (NSButton *)hudPushButton:(NSString *)title frame:(NSRect)frame
                     action:(SEL)action in:(NSView *)parent;
- (NSSlider *)hudSlider:(NSRect)frame min:(double)min max:(double)max
                 action:(SEL)action in:(NSView *)parent;
- (NSPopUpButton *)hudPopup:(NSRect)frame action:(SEL)action
                         in:(NSView *)parent;
- (NSStepper *)hudStepper:(NSRect)frame min:(double)min max:(double)max
                increment:(double)increment action:(SEL)action
                       in:(NSView *)parent;
@end

/* App-modal prompt with one text field (the 3.0 VLCTextfieldPanelController
 * runs as a sheet; an app-modal panel is the 10.4-safe equivalent).
 * Returns the entered string, or nil when cancelled. */
NSString *VLCLegacyRunTextPrompt(NSString *title, NSString *subtitle,
                                 NSString *okTitle, NSString *cancelTitle,
                                 NSString *initialValue);

/* App-modal username/password prompt used by the core credential dialog.
 * Empty passwords are valid. Returns NO only when the user cancels. */
BOOL VLCLegacyRunLoginPrompt(NSString *title, NSString *subtitle,
                             NSString *initialUsername, BOOL askStore,
                             NSString **username, NSString **password,
                             BOOL *store);

/* App-modal prompt with one popup (VLCPopupPanelController equivalent).
 * Returns the selected index, or -1 when cancelled. */
NSInteger VLCLegacyRunPopupPrompt(NSString *title, NSString *subtitle,
                                  NSString *okTitle, NSString *cancelTitle,
                                  NSArray *items);
