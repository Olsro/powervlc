/*****************************************************************************
 * VLCUIWidgets.h: Widgets for VLC's extensions dialogs for Mac OS X
 *****************************************************************************
 * Copyright (C) 2009-2015 the VideoLAN team and authors
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan dot>,
 *          Brendon Justin <brendonjustin@gmail.com>
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

#import <Cocoa/Cocoa.h>
#import <vlc_extensions.h>

@class VLCDialogGridView;

@interface VLCDialogButton : NSButton
@property (readwrite) extension_widget_t *widget;
@end

@interface VLCDialogPopUpButton : NSPopUpButton
@property (readwrite) extension_widget_t *widget;
/* set while the menu is being repopulated: the selection changes then
 * too, and that is not something the user did */
@property (readwrite) BOOL programmaticSelection;
@end

@interface VLCDialogLabel : NSTextField
@end

/// Carries its widget like the other controls do, so the layout can ask
/// where the picture should sit in the rows it covers.
@interface VLCDialogImageView : NSImageView
@property (readwrite) extension_widget_t *widget;
@end

@interface VLCDialogTextField : NSTextField
@property (readwrite) extension_widget_t *widget;
@end

@interface VLCDialogSecureTextField : NSSecureTextField
@property (readwrite) extension_widget_t *widget;
@end

@interface VLCDialogWindow : NSWindow
@property (readwrite) extension_dialog_t *dialog;
@property (readwrite) BOOL has_lock;
@end


/// Cells are tab-separated; a cell may carry "display\037sortkey" so that a
/// column sorts on a real value (a timestamp) rather than on its label.
#define VLC_DIALOG_SORTKEY_SEP "\037"

@interface VLCDialogList : NSTableView <NSTableViewDataSource>
@property (readwrite) extension_widget_t *widget;
@property (readwrite, retain) NSMutableArray *contentArray;
@property (readwrite) NSInteger sortColumn;      ///< -1 when unsorted
@property (readwrite) BOOL sortAscending;
/// Set while the interface itself changes the selection, so that
/// repopulating a list is not reported to the extension as a user action.
@property (readwrite) BOOL programmaticSelection;

/// Rebuild the table columns: nil headers = single headerless column,
/// otherwise one titled column per string.
- (void)setColumnHeaders:(NSArray *)headers;
/// Measure the content and share the available width between the columns,
/// so that long values (URLs, video titles) are readable without the user
/// dragging a divider on every search.
- (void)fitColumnsToContent;
/// Share the width the list has NOW between its columns. Must be called
/// whenever the box around the list changes size: a clip view only ever
/// grows its document view, so a table left in a narrower scroll view is
/// never told about it and keeps columns reaching past its right edge.
- (void)layoutColumns;
/// Sort contentArray on a column (string compare, numeric-aware).
- (void)sortByColumn:(NSInteger)index ascending:(BOOL)ascending;
/// Show the first row, now and once more on the next turn of the run
/// loop. Call after filling the list.
- (void)showTopOfList;
@end

@interface VLCDialogGridView : NSView

- (void)addSubview:(NSView *)view atRow:(NSUInteger)row column:(NSUInteger)column rowSpan:(NSUInteger)rowSpan colSpan:(NSUInteger)colSpan;
- (NSSize)flexSize:(NSSize)size;
- (void)updateSubview:(NSView *)view
                atRow:(NSUInteger)row
               column:(NSUInteger)column
              rowSpan:(NSUInteger)rowSpan
              colSpan:(NSUInteger)colSpan;
- (void)removeSubview:(NSView *)view;
/// Fit the window to the grid at once. Adding a widget only schedules this
/// for the next turn of the run loop, so that building a whole dialog
/// resizes once rather than per widget; call it directly when the window
/// has to be the right size NOW -- placing it, for one, since where it goes
/// depends on how big it is.
- (void)recomputeWindowSize;

@property (readonly) NSUInteger numViews;

@end
