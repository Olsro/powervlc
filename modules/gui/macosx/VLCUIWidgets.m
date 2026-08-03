/*****************************************************************************
 * VLCUIWidgets.m: Widgets for VLC's extensions dialogs for Mac OS X
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

#import "CompatibilityFixes.h"
#import "VLCUIWidgets.h"

#import <stdlib.h>

@implementation VLCDialogButton

@end


@implementation VLCDialogPopUpButton

@end


@implementation VLCDialogTextField

@end


@implementation VLCDialogSecureTextField

@end


@implementation VLCDialogLabel
- (void)resetCursorRects {
    [self addCursorRect:[self bounds] cursor:[NSCursor arrowCursor]];
}
@end

@implementation VLCDialogWindow

@end


@interface VLCDialogList ()
{
    NSArray *_columnWeights;   ///< natural width of each column's content
    BOOL _layingOut;
    NSTimeInterval _filledAt;  ///< when this list last got its content
}
@end

@implementation VLCDialogList

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [self.contentArray count];
}

/* The natural width of a column is that of its widest value, header
 * included. Columns then share the visible width in that proportion. */
- (void)fitColumnsToContent
{
    NSArray *columns = [self tableColumns];
    if ([columns count] == 0)
        return;

    NSFont *font = [[[columns objectAtIndex:0] dataCell] font];
    if (font == nil)
        font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:font
                                                           forKey:NSFontAttributeName];

    NSMutableArray *weights = [NSMutableArray array];
    for (NSUInteger i = 0; i < [columns count]; i++) {
        CGFloat widest = 0;
        if ([self headerView] != nil) {
            NSString *title = [[[columns objectAtIndex:i] headerCell] stringValue];
            widest = [title sizeWithAttributes:attributes].width;
        }
        for (NSDictionary *row in self.contentArray) {
            NSArray *cells = [row objectForKey:@"cells"];
            NSString *text = (i < [cells count]) ? [cells objectAtIndex:i]
                                                 : [row objectForKey:@"text"];
            CGFloat width = [text sizeWithAttributes:attributes].width;
            if (width > widest)
                widest = width;
        }
        [weights addObject:[NSNumber numberWithDouble:widest + 12.0]];
    }
    _columnWeights = weights;
    [self layoutColumns];
}

- (void)layoutColumns
{
    NSArray *columns = [self tableColumns];
    if (_layingOut || _columnWeights == nil
     || [_columnWeights count] != [columns count])
        return;

    NSScrollView *scrollView = [self enclosingScrollView];
    CGFloat available = scrollView ? [[scrollView contentView] bounds].size.width
                                   : [self bounds].size.width;
    available -= [self intercellSpacing].width * [columns count];
    if (available < 120)
        return; /* not laid out yet: keep whatever we have */

    double total = 0;
    NSUInteger widest = 0;
    for (NSUInteger i = 0; i < [_columnWeights count]; i++) {
        double weight = [[_columnWeights objectAtIndex:i] doubleValue];
        total += weight;
        if (weight > [[_columnWeights objectAtIndex:widest] doubleValue])
            widest = i;
    }
    if (total <= 0)
        return;

    _layingOut = YES;
    CGFloat used = 0;
    for (NSUInteger i = 0; i < [columns count]; i++) {
        CGFloat width;
        if (total <= available) {
            /* everything fits: give each column what it needs and hand the
             * slack to the longest one, rather than padding them all */
            width = [[_columnWeights objectAtIndex:i] doubleValue];
            if (i == widest)
                width += available - total;
        } else if (i + 1 == [columns count]) {
            width = available - used;   /* no rounding crumbs on the right */
        } else {
            width = floor(available * [[_columnWeights objectAtIndex:i] doubleValue] / total);
        }
        if (width < 48)
            width = 48;
        [[columns objectAtIndex:i] setWidth:width];
        used += width;
    }
    _layingOut = NO;
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self layoutColumns];
}

/* Fresh content is read from its first row. Twice: the clip view is
 * still being laid out when the list is filled, and the scroll it
 * settles on is not necessarily the one asked for. */
- (void)showTopOfList
{
    _filledAt = [NSDate timeIntervalSinceReferenceDate];
    [self scrollToTopOfList];
    [self performSelector:@selector(scrollToTopOfList) withObject:nil
               afterDelay:0];
}

- (void)scrollToTopOfList
{
    NSClipView *clip = [[self enclosingScrollView] contentView];
    if (!clip)
        return;
    /* The column headers float over the top of the clip view rather than
     * beside it, so scrolling to zero tucks the first row underneath them
     * -- a list of episodes that opened on number 2. Its real top is one
     * header higher, which is what AppKit itself settles on when the rows
     * all fit. */
    CGFloat header = [self headerView] ? [[self headerView] frame].size.height
                                       : 0;
    NSRect bounds = [clip bounds];
    if ([clip isFlipped])
        bounds.origin.y = -header;
    else {
        bounds.origin.y = NSMaxY([self frame]) - bounds.size.height;
        if (bounds.origin.y < 0)
            bounds.origin.y = 0;   /* a document shorter than the clip view */
    }
    [clip scrollToPoint:bounds.origin];
    [[self enclosingScrollView] reflectScrolledClipView:clip];
}

/* A flick of the trackpad keeps sending scroll events long after the
 * finger is up, and they go to whatever list is under the pointer -- so
 * opening another season while the previous one was still gliding
 * carried that scroll straight into the new list. The user's own gesture
 * is left alone: only the momentum of a gesture that ended before this
 * content existed is dropped. */
- (void)scrollWheel:(NSEvent *)event
{
    if ([event respondsToSelector:@selector(momentumPhase)]
     && [event momentumPhase] != NSEventPhaseNone
     && [NSDate timeIntervalSinceReferenceDate] - _filledAt < 1.0)
        return;
    [super scrollWheel:event];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
    NSDictionary *entry = [self.contentArray objectAtIndex:rowIndex];
    NSArray *cells = [entry objectForKey:@"cells"];
    if (!cells)
        return [entry objectForKey:@"text"];
    if ([[self tableColumns] count] == 1 && [cells count] == 1)
        return [cells objectAtIndex:0];
    NSUInteger columnIndex = (NSUInteger)[[aTableColumn identifier] integerValue];
    return columnIndex < [cells count] ? [cells objectAtIndex:columnIndex] : @"";
}

- (void)setColumnHeaders:(NSArray *)headers
{
    NSUInteger wanted = headers ? [headers count] : 1;

    while ([[self tableColumns] count] > wanted)
        [self removeTableColumn:[[self tableColumns] lastObject]];
    while ([[self tableColumns] count] < wanted) {
        NSTableColumn *column = [[NSTableColumn alloc] init];
        [column setEditable:NO];
        [self addTableColumn:column];
    }
    /* identifiers index into the row's cells */
    NSArray *columns = [self tableColumns];
    for (NSUInteger i = 0; i < [columns count]; i++) {
        NSTableColumn *column = [columns objectAtIndex:i];
        [column setIdentifier:[NSString stringWithFormat:@"%lu", (unsigned long)i]];
        /* editable cells swallow double-clicks */
        [column setEditable:NO];
        if (headers)
            [[column headerCell] setStringValue:[headers objectAtIndex:i]];
    }

    if (headers && ![self headerView])
        [self setHeaderView:[[NSTableHeaderView alloc] init]];
    else if (!headers && [self headerView])
        [self setHeaderView:nil];
}

- (void)sortByColumn:(NSInteger)index ascending:(BOOL)ascending
{
    self.sortColumn = index;
    self.sortAscending = ascending;
    [self.contentArray sortUsingComparator:^(NSDictionary *a, NSDictionary *b) {
        NSArray *keysA = [a objectForKey:@"sortKeys"];
        NSArray *keysB = [b objectForKey:@"sortKeys"];
        NSString *keyA = (NSUInteger)index < [keysA count] ? [keysA objectAtIndex:index] : @"";
        NSString *keyB = (NSUInteger)index < [keysB count] ? [keysB objectAtIndex:index] : @"";

        NSComparisonResult result;
        if ([keyA length] && [keyB length]) {
            /* an explicit key: compare as numbers when both are numeric,
             * which is the whole point of dates and counts having one */
            double da = [keyA doubleValue], db = [keyB doubleValue];
            if (da != db)
                result = (da < db) ? NSOrderedAscending : NSOrderedDescending;
            else
                result = [keyA compare:keyB options:NSNumericSearch];
        } else {
            NSArray *cellsA = [a objectForKey:@"cells"];
            NSArray *cellsB = [b objectForKey:@"cells"];
            NSString *textA = (NSUInteger)index < [cellsA count] ? [cellsA objectAtIndex:index] : @"";
            NSString *textB = (NSUInteger)index < [cellsB count] ? [cellsB objectAtIndex:index] : @"";
            result = [textA compare:textB
                            options:NSCaseInsensitiveSearch | NSNumericSearch];
        }
        if (!ascending) {
            if (result == NSOrderedAscending)
                result = NSOrderedDescending;
            else if (result == NSOrderedDescending)
                result = NSOrderedAscending;
        }
        return result;
    }];
    [self reloadData];
}
@end

/* Track sizes are asked for over and over while laying out -- a column
 * width is needed by every view in it, and computing one walks every
 * view and measures text. Cached for the duration of a layout pass and
 * thrown away whenever the geometry changes; without this a dialog of a
 * couple of dozen widgets took seconds to lay out, once per frame of the
 * window's resize animation. */
#define VLC_DIALOG_MAX_TRACKS 64

@interface VLCDialogGridView()
{
    NSUInteger _rowCount, _colCount;
    NSMutableArray *_griddedViews;

    CGFloat _colWidth[VLC_DIALOG_MAX_TRACKS];
    BOOL _colWidthKnown[VLC_DIALOG_MAX_TRACKS];
    CGFloat _rowHeight[VLC_DIALOG_MAX_TRACKS];
    BOOL _rowHeightKnown[VLC_DIALOG_MAX_TRACKS];
    CGFloat _naturalHeight[VLC_DIALOG_MAX_TRACKS];
    BOOL _naturalHeightKnown[VLC_DIALOG_MAX_TRACKS];
    CGFloat _constrainedHeight[VLC_DIALOG_MAX_TRACKS];
    BOOL _constrainedHeightKnown[VLC_DIALOG_MAX_TRACKS];
    CGFloat _slack;
    BOOL _slackKnown;
    BOOL _appliedSizeHint;   /* the extension's set_size, honoured once */
}
- (void)invalidateTrackCache;
@end

@implementation VLCDialogGridView

- (NSUInteger)numViews
{
    return [_griddedViews count];
}

- (void)invalidateTrackCache
{
    for (NSUInteger i = 0; i < VLC_DIALOG_MAX_TRACKS; i++) {
        _colWidthKnown[i] = NO;
        _rowHeightKnown[i] = NO;
        _naturalHeightKnown[i] = NO;
        _constrainedHeightKnown[i] = NO;
    }
    _slackKnown = NO;
}

- (id)init
{
    if ((self = [super init])) {
        _colCount = 0;
        _rowCount = 0;
        _griddedViews = [[NSMutableArray alloc] init];
    }

    return self;
}

- (void)recomputeCount
{
    _colCount = 0;
    _rowCount = 0;
    for (NSDictionary *obj in _griddedViews) {
        NSUInteger row = [[obj objectForKey:@"row"] intValue];
        NSUInteger col = [[obj objectForKey:@"col"] intValue];
        /* count the whole span, not just the starting cell: a phantom
         * column that only spans reach gets handed the entire remaining
         * width in widthOfColumn:, blowing the layout past the window */
        NSUInteger rowSpan = __MAX(1, [[obj objectForKey:@"rowSpan"] intValue]);
        NSUInteger colSpan = __MAX(1, [[obj objectForKey:@"colSpan"] intValue]);
        if (col + colSpan > _colCount)
            _colCount = col + colSpan;
        if (row + rowSpan > _rowCount)
            _rowCount = row + rowSpan;
    }
}

- (void)recomputeWindowSize
{
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(recomputeWindowSize) object:nil];

    NSWindow *window = [self window];
    NSRect frame = [window frame];
    NSRect contentRect = [window contentRectForFrameRect:frame];
    /* the content size, NOT frame.size: the latter includes the title bar,
     * so every update used to grow the window by its height */
    contentRect.size = [self flexSize:contentRect.size];
    NSRect newFrame = [window frameRectForContentRect:contentRect];
    newFrame.origin.y -= newFrame.size.height - frame.size.height;
    newFrame.origin.x -= (newFrame.size.width - frame.size.width) / 2;

    /* A dialog grows downwards from its title bar, so unfolding a long
     * section pushed its whole body under the bottom of the screen --
     * from where the user cannot reach it, and it reads as a window that
     * vanished. Keep it inside the visible area, and never taller. */
    NSScreen *onScreen = [window screen] ?: [NSScreen mainScreen];
    if (onScreen) {
        NSRect visible = [onScreen visibleFrame];
        if (newFrame.size.height > visible.size.height)
            newFrame.size.height = visible.size.height;
        if (newFrame.size.width > visible.size.width)
            newFrame.size.width = visible.size.width;
        if (newFrame.origin.y < visible.origin.y)
            newFrame.origin.y = visible.origin.y;
        if (NSMaxY(newFrame) > NSMaxY(visible))
            newFrame.origin.y = NSMaxY(visible) - newFrame.size.height;
        if (newFrame.origin.x < visible.origin.x)
            newFrame.origin.x = visible.origin.x;
        if (NSMaxX(newFrame) > NSMaxX(visible))
            newFrame.origin.x = NSMaxX(visible) - newFrame.size.width;
    }

    /* Not animated: every frame of the animation resizes the content
     * view, and every resize lays the whole grid out again. A dialog of
     * a few dozen widgets then took tens of seconds to appear. */
    [window setFrame:newFrame display:YES animate:NO];

    /* Width may be squeezed -- columns give some of theirs and text is
     * clipped -- but a row that no longer fits is simply not drawn. So
     * the height the content needs becomes the floor, unless a row can
     * genuinely shrink (a list), and never more than the screen holds. */
    CGFloat minHeight = [self minimumContentHeight];
    if (minHeight > contentRect.size.height)
        minHeight = contentRect.size.height;
    NSScreen *screen = [window screen] ?: [NSScreen mainScreen];
    if (screen) {
        NSRect visible = [window contentRectForFrameRect:[screen visibleFrame]];
        if (minHeight > visible.size.height)
            minHeight = visible.size.height;
    }
    [window setContentMinSize:NSMakeSize(240, minHeight)];
}

- (NSSize)objectSizeToFit:(NSView *)view
{
    /* An image cell answers a placeholder size, not the size of what it
     * holds: ask the picture itself. */
    if ([view isKindOfClass:[NSImageView class]]) {
        NSImage *image = [(NSImageView *)view image];
        return image ? [image size] : NSMakeSize(0, 0);
    }
    if ([view isKindOfClass:[NSControl class]]) {
        NSControl *control = (NSControl *)view;
        return [[control cell] cellSize];
    }
    return [view frame].size;
}

- (CGFloat)marginX
{
    return 16;
}
- (CGFloat)marginY
{
    return 8;
}

/* A label that wraps is as tall as its text needs at the width it will
 * be given, not one line: without this a paragraph showed its first line
 * and hid the rest. Column widths do not depend on row heights, so the
 * width is already known here. */
- (CGFloat)wrappedHeightOfView:(NSView *)view inCell:(NSDictionary *)obj
{
    if (![view isKindOfClass:[NSTextField class]]
     || [(NSTextField *)view isEditable]
     || ![[(NSTextField *)view cell] wraps])
        return 0;

    NSUInteger col = [[obj objectForKey:@"col"] intValue];
    NSUInteger colSpan = __MAX(1, [[obj objectForKey:@"colSpan"] intValue]);
    CGFloat available = 0;
    for (NSUInteger c = col; c < col + colSpan && c < _colCount; c++)
        available += [self widthOfColumn:c] + (c > col ? [self marginX] : 0);
    if (available <= 0)
        return 0;

    /* Only a text that does not fit on one line needs this: asking a cell
     * for a bounded size adds the paragraph spacing of its style, and a
     * one-line heading would gain empty space above and below. */
    NSCell *cell = [(NSTextField *)view cell];
    if ([cell cellSize].width <= available)
        return 0;

    return [cell cellSizeForBounds:
        NSMakeRect(0, 0, available, CGFLOAT_MAX)].height;
}

/* The height the widgets living in this row alone ask for. Views
 * spanning several rows are handled apart, below.
 *
 * Cached: the span floor below asks this of every row it covers, and is
 * itself asked once per row, so an uncached pass came to a few hundred
 * thousand cell measurements on a dialog of thirty widgets. */
- (CGFloat)naturalHeightOfRow:(NSUInteger)targetRow
{
    if (targetRow < VLC_DIALOG_MAX_TRACKS && _naturalHeightKnown[targetRow])
        return _naturalHeight[targetRow];

    CGFloat height = 0;
    for(NSDictionary *obj in _griddedViews) {
        NSUInteger row = [[obj objectForKey:@"row"] intValue];
        if (row != targetRow)
            continue;
        NSUInteger rowSpan = [[obj objectForKey:@"rowSpan"] intValue];
        if (rowSpan != 1)
            continue;
        CGFloat wrapped = [self wrappedHeightOfView:[obj objectForKey:@"view"]
                                             inCell:obj];
        if (wrapped > height)
            height = wrapped;
        NSView *view = [obj objectForKey:@"view"];
        if ([view autoresizingMask] & NSViewHeightSizable)
            continue;
        NSSize sizeToFit = [self objectSizeToFit:view];
        if (height < sizeToFit.height)
            height = sizeToFit.height;
    }

    if (targetRow < VLC_DIALOG_MAX_TRACKS) {
        _naturalHeight[targetRow] = height;
        _naturalHeightKnown[targetRow] = YES;
    }
    return height;
}

/* An image covering several rows is drawn into the block they come to,
 * so a short block leaves it squashed. It therefore raises a floor under
 * every row it covers -- shared out evenly, since piling the whole
 * difference on the last one opens a hole in the middle of the dialog.
 * Only images: a list or a paragraph gains from being given the room it
 * has, and would keep the window from ever shrinking. */
- (CGFloat)imageSpanFloorForRow:(NSUInteger)targetRow
{
    CGFloat extra = 0;
    for (NSDictionary *obj in _griddedViews) {
        NSUInteger row = [[obj objectForKey:@"row"] intValue];
        NSUInteger rowSpan = __MAX(1, [[obj objectForKey:@"rowSpan"] intValue]);
        if (rowSpan < 2 || targetRow < row || targetRow >= row + rowSpan)
            continue;
        NSView *view = [obj objectForKey:@"view"];
        if (![view isKindOfClass:[NSImageView class]])
            continue;

        CGFloat have = 0;
        NSUInteger covered = 0;
        BOOL flexible = NO;
        for (NSUInteger r = row; r < row + rowSpan && r < _rowCount; r++) {
            CGFloat natural = [self naturalHeightOfRow:r];
            if (!natural) {
                flexible = YES;    /* that row already takes what is left */
                break;
            }
            have += natural + (covered ? [self marginY] : 0);
            covered++;
        }
        if (flexible || !covered)
            continue;

        CGFloat need = [self objectSizeToFit:view].height;
        if (need > have) {
            CGFloat share = (need - have) / covered;
            if (share > extra)
                extra = share;
        }
    }
    return extra;
}

- (CGFloat)constrainedHeightOfRow:(NSUInteger)targetRow
{
    if (targetRow < VLC_DIALOG_MAX_TRACKS && _constrainedHeightKnown[targetRow])
        return _constrainedHeight[targetRow];

    CGFloat height = [self naturalHeightOfRow:targetRow];
    /* zero means flexible: it takes whatever the window has left */
    if (height)
        height += [self imageSpanFloorForRow:targetRow];

    if (targetRow < VLC_DIALOG_MAX_TRACKS) {
        _constrainedHeight[targetRow] = height;
        _constrainedHeightKnown[targetRow] = YES;
    }
    return height;
}

- (CGFloat)remainingRowsHeight
{
    NSUInteger height = [self marginY];
    if (!_rowCount)
        return 0;
    NSUInteger autosizedRows = 0;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        CGFloat constrainedHeight = [self constrainedHeightOfRow:i];
        if (!constrainedHeight)
            autosizedRows++;
        height += constrainedHeight + [self marginY];
    }
    CGFloat remaining = 0;
    if (height < self.bounds.size.height && autosizedRows)
        remaining = (self.bounds.size.height - height) / autosizedRows;
    if (remaining < 0)
        remaining = 0;

    return remaining;
}

/* Height left over once every row has taken what it needs, shared out
 * when no row is flexible. Without this the whole difference piled up
 * above the first row, as a margin nobody asked for. */
- (CGFloat)rowSlack
{
    if (!_rowCount)
        return 0;

    CGFloat used = [self marginY];
    for (NSUInteger i = 0; i < _rowCount; i++) {
        CGFloat constrained = [self constrainedHeightOfRow:i];
        if (!constrained)
            return 0;   /* that row already absorbs the slack */
        used += constrained + [self marginY];
    }

    CGFloat slack = self.bounds.size.height - used;
    return slack > 0 ? slack / _rowCount : 0;
}

- (CGFloat)heightOfRow:(NSUInteger)targetRow
{
    NSAssert(targetRow < _rowCount, @"accessing a non existing row");
    if (targetRow < VLC_DIALOG_MAX_TRACKS && _rowHeightKnown[targetRow])
        return _rowHeight[targetRow];

    CGFloat height = [self constrainedHeightOfRow:targetRow];
    height = height ? height + [self rowSlack] : [self remainingRowsHeight];

    if (targetRow < VLC_DIALOG_MAX_TRACKS) {
        _rowHeight[targetRow] = height;
        _rowHeightKnown[targetRow] = YES;
    }
    return height;
}


- (CGFloat)topOfRow:(NSUInteger)targetRow
{
    CGFloat top = [self marginY];
    for (NSUInteger i = 1; i < _rowCount - targetRow; i++)
        top += [self heightOfRow:_rowCount - i] + [self marginY];

    return top;
}

- (CGFloat)constrainedWidthOfColumn:(NSUInteger)targetColumn
{
    CGFloat width = 0;
    for(NSDictionary *obj in _griddedViews) {
        NSUInteger col = [[obj objectForKey:@"col"] intValue];
        if (col != targetColumn)
            continue;
        NSUInteger colSpan = [[obj objectForKey:@"colSpan"] intValue];
        if (colSpan != 1)
            continue;
        NSView *view = [obj objectForKey:@"view"];
        /* A picture is drawn at its own size, so its column asks for that
         * width and no more -- although the view resizes with the window
         * like a list, widening it only pads the picture with emptiness
         * and takes the room from the text beside it. */
        if ([view isKindOfClass:[NSImageView class]]) {
            CGFloat natural = [self objectSizeToFit:view].width;
            if (width < natural)
                width = natural;
            continue;
        }
        if ([view autoresizingMask] & NSViewWidthSizable)
            return 0;
        NSSize sizeToFit = [self objectSizeToFit:view];
        if (width < sizeToFit.width)
            width = sizeToFit.width;
    }
    return width;
}

- (CGFloat)remainingColumnWidth
{
    NSUInteger width = [self marginX];
    if (!_colCount)
        return 0;
    NSUInteger autosizedCol = 0;
    for (NSUInteger i = 0; i < _colCount; i++) {
        CGFloat constrainedWidth = [self constrainedWidthOfColumn:i];
        if (!constrainedWidth)
            autosizedCol++;
        width += constrainedWidth + [self marginX];
    }
    CGFloat remaining = 0;
    if (width < self.bounds.size.width && autosizedCol)
        remaining = (self.bounds.size.width - width) / autosizedCol;
    if (remaining < 0)
        remaining = 0;
    return remaining;
}

/* Width left over once every column has taken what it needs, shared out
 * when NO column is flexible: labels, buttons and drop-downs all have a
 * fixed size, so a dialog made of those kept its widgets packed against
 * the left edge and left the rest of the window empty -- and a list
 * spanning them stayed just as narrow. */
/* A column of labels and buttons gains nothing from being wider -- the
 * text just sits further from the field it names. Entry fields, lists
 * and drop-downs do use the room, so the slack goes to them. */
- (BOOL)columnUsesSlack:(NSUInteger)targetColumn
{
    for (NSDictionary *obj in _griddedViews) {
        NSUInteger col = [[obj objectForKey:@"col"] intValue];
        NSUInteger colSpan = __MAX(1, [[obj objectForKey:@"colSpan"] intValue]);
        if (targetColumn < col || targetColumn >= col + colSpan)
            continue;

        NSView *view = [obj objectForKey:@"view"];
        if ([view isKindOfClass:[NSImageView class]])
            continue;   /* it is drawn at its own size, see above */
        if ([view isKindOfClass:[NSScrollView class]]
         || [view isKindOfClass:[NSPopUpButton class]])
            return YES;
        if ([view isKindOfClass:[NSTextField class]]
         && [(NSTextField *)view isEditable])
            return YES;
    }
    return NO;
}

- (CGFloat)columnSlack
{
    if (!_colCount)
        return 0;
    if (_slackKnown)
        return _slack;
    _slackKnown = YES;
    _slack = 0;

    CGFloat used = [self marginX];
    NSUInteger takers = 0;
    for (NSUInteger i = 0; i < _colCount; i++) {
        CGFloat constrained = [self constrainedWidthOfColumn:i];
        if (!constrained)
            return 0;   /* that column already absorbs the slack */
        if ([self columnUsesSlack:i])
            takers++;
        used += constrained + [self marginX];
    }

    CGFloat slack = self.bounds.size.width - used;
    if (slack <= 0)
        return 0;
    /* nobody in particular: spread it rather than leave a gap at the edge */
    _slack = slack / (takers > 0 ? takers : _colCount);
    return _slack;
}

- (CGFloat)widthOfColumn:(NSUInteger)targetColumn
{
    if (targetColumn < VLC_DIALOG_MAX_TRACKS && _colWidthKnown[targetColumn])
        return _colWidth[targetColumn];

    CGFloat width = [self constrainedWidthOfColumn:targetColumn];
    if (!width) {
        width = [self remainingColumnWidth];
        if (targetColumn < VLC_DIALOG_MAX_TRACKS) {
            _colWidth[targetColumn] = width;
            _colWidthKnown[targetColumn] = YES;
        }
        return width;
    }
    CGFloat slack = [self columnSlack];
    if (slack > 0 && ![self columnUsesSlack:targetColumn]) {
        /* only if every column is in the same case, see -columnSlack */
        BOOL anyTaker = NO;
        for (NSUInteger i = 0; i < _colCount && !anyTaker; i++)
            anyTaker = [self columnUsesSlack:i];
        if (anyTaker)
            slack = 0;
    }

    width += slack;
    if (targetColumn < VLC_DIALOG_MAX_TRACKS) {
        _colWidth[targetColumn] = width;
        _colWidthKnown[targetColumn] = YES;
    }
    return width;
}


- (CGFloat)leftOfColumn:(NSUInteger)targetColumn
{
    CGFloat left = [self marginX];
    for (NSUInteger i = 0; i < targetColumn; i++) {
        left += [self widthOfColumn:i] + [self marginX];
    }
    return left;
}

- (void)relayout
{
    /* the tracks are worked out once here and reused by every view */
    [self invalidateTrackCache];

    for(NSDictionary *obj in _griddedViews) {
        NSUInteger row = [[obj objectForKey:@"row"] intValue];
        NSUInteger col = [[obj objectForKey:@"col"] intValue];
        NSUInteger rowSpan = [[obj objectForKey:@"rowSpan"] intValue];
        NSUInteger colSpan = [[obj objectForKey:@"colSpan"] intValue];
        NSView *view = [obj objectForKey:@"view"];
        NSRect rect;

        // Get the height
        if ([view autoresizingMask] & NSViewHeightSizable || rowSpan > 1) {
            CGFloat height = 0;
            for (NSUInteger r = 0; r < rowSpan; r++) {
                if (row + r >= _rowCount)
                    break;
                height += [self heightOfRow:row + r] + [self marginY];
            }
            rect.size.height = height - [self marginY];
        }
        else {
            CGFloat wrapped = [self wrappedHeightOfView:view inCell:obj];
            rect.size.height = wrapped > 0 ? wrapped
                                           : [self objectSizeToFit:view].height;
        }

        // Get the width
        if ([view autoresizingMask] & NSViewWidthSizable) {
            CGFloat width = 0;
            for (NSUInteger c = 0; c < colSpan; c++)
                width += [self widthOfColumn:col + c] + [self marginX];
            rect.size.width = width - [self marginX];
        }
        else {
            rect.size.width = [self objectSizeToFit:view].width;
            /* clamp to the columns the view was given: a long label must
             * truncate rather than spill over its neighbours */
            CGFloat avail = 0;
            for (NSUInteger c = 0; c < colSpan && col + c < _colCount; c++)
                avail += [self widthOfColumn:col + c] + [self marginX];
            avail -= [self marginX];
            if (avail > 0 && rect.size.width > avail)
                rect.size.width = avail;
        }

        /* A picture keeps its own size: scaling proportionally, it would
         * otherwise blow itself up to whatever column it was handed. And
         * whatever the window, it leaves two thirds of the width to the
         * text beside it. */
        CGFloat imageLeft = 0;
        if ([view isKindOfClass:[NSImageView class]]) {
            NSSize natural = [self objectSizeToFit:view];
            CGFloat cap = self.bounds.size.width / 3;
            CGFloat maxWidth = rect.size.width;
            if (natural.width > 0 && natural.width < maxWidth)
                maxWidth = natural.width;
            if (cap > 0 && cap < maxWidth)
                maxWidth = cap;
            if (natural.height > 0 && natural.height < rect.size.height)
                rect.size.height = natural.height;
            if (maxWidth < rect.size.width) {
                imageLeft = (rect.size.width - maxWidth) / 2;
                rect.size.width = maxWidth;
            }
        }

        /* Top corner. A view spanning several rows is centred on the whole
         * block it covers, not on the first row of it: doing the latter
         * pushed a tall image far above the window and cut it off. */
        CGFloat blockTop = [self topOfRow:row] + [self heightOfRow:row];
        NSUInteger lastRow = row + __MAX(1, rowSpan) - 1;
        if (lastRow >= _rowCount)
            lastRow = _rowCount ? _rowCount - 1 : row;
        CGFloat blockBottom = [self topOfRow:lastRow];
        if ([view isKindOfClass:[NSImageView class]])
            /* Top of the block, level with the title it illustrates --
             * centred, it drifted away from the text it belongs to as
             * sections were unfolded below. */
            rect.origin.y = blockTop - rect.size.height;
        else
            rect.origin.y = blockBottom
                          + ((blockTop - blockBottom) - rect.size.height) / 2;
        rect.origin.x = [self leftOfColumn:col] + imageLeft;

        [view setFrame:rect];
        [view setNeedsDisplay:YES];
    }
}

- (NSMutableDictionary *)objectForView:(NSView *)view
{
    for (NSMutableDictionary *dict in _griddedViews)
    {
        if ([dict objectForKey:@"view"] == view)
            return dict;
    }
    return nil;
}

- (void)addSubview:(NSView *)view atRow:(NSUInteger)row column:(NSUInteger)column
                                                       rowSpan:(NSUInteger)rowSpan
                                                       colSpan:(NSUInteger)colSpan
{
    /* count the whole span, see -recomputeCount */
    if (row + __MAX(1, rowSpan) > _rowCount)
        _rowCount = row + __MAX(1, rowSpan);
    if (column + __MAX(1, colSpan) > _colCount)
        _colCount = column + __MAX(1, colSpan);

    NSMutableDictionary *dict = [self objectForView:view];
    if (!dict) {
        dict = [NSMutableDictionary dictionary];
        [dict setObject:view forKey:@"view"];
        [_griddedViews addObject:dict];
    }
    [dict setObject:[NSNumber numberWithInt:rowSpan] forKey:@"rowSpan"];
    [dict setObject:[NSNumber numberWithInt:colSpan] forKey:@"colSpan"];
    [dict setObject:[NSNumber numberWithInt:row] forKey:@"row"];
    [dict setObject:[NSNumber numberWithInt:column] forKey:@"col"];

    [self addSubview:view];
    [self relayout];

    // Recompute the size of the window after making sure we won't see anymore update
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(recomputeWindowSize) object:nil];
    [self performSelector:@selector(recomputeWindowSize) withObject:nil afterDelay:0.1];
}

- (void)updateSubview:(NSView *)view
                atRow:(NSUInteger)row
               column:(NSUInteger)column
              rowSpan:(NSUInteger)rowSpan
              colSpan:(NSUInteger)colSpan
{
    NSDictionary *oldDict = [self objectForView:view];
    if (!oldDict) {
        [self addSubview:view
                   atRow:row
                  column:column
                 rowSpan:rowSpan
                 colSpan:colSpan];
        return;
    }
    [self relayout];

    /* The new content may need more room (a label that grew, a list that
     * was filled): resize the window like addSubview: does, otherwise the
     * autosized columns get squeezed instead. */
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(recomputeWindowSize) object:nil];
    [self performSelector:@selector(recomputeWindowSize) withObject:nil afterDelay:0.1];
}

- (void)removeSubview:(NSView *)view
{
    NSDictionary *dict = [self objectForView:view];
    if (dict)
        [_griddedViews removeObject:dict];
    [view removeFromSuperview];

    [self recomputeCount];
    [self recomputeWindowSize];

    [self relayout];
    [self setNeedsDisplay:YES];
}

- (void)setFrame:(NSRect)frameRect
{
    [super setFrame:frameRect];
    [self relayout];
}

/* A window resizes its content view through -setFrameSize:, never
 * -setFrame:. Without this, the grid kept the geometry it was given while
 * the window was still at its minimum size: the widgets stayed crammed in
 * the left half and every later resize was ignored. */
- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self relayout];
}

/* The height below which rows would be hidden. A row that can stretch --
 * a list, a text area -- gets a small allowance rather than its natural
 * size, since it can show fewer lines. This is the floor for both the
 * window's minimum and the size computed for the content: when the two
 * disagreed, the window sprang back to the larger one on the next widget
 * update and could not be made smaller. */
- (CGFloat)minimumContentHeight
{
    CGFloat height = [self marginY];
    for (NSUInteger i = 0; i < _rowCount; i++) {
        CGFloat constrained = [self constrainedHeightOfRow:i];
        height += (constrained ? constrained : 48) + [self marginY];
    }
    return height;
}

- (NSSize)flexSize:(NSSize)size
{
    if (!_rowCount || !_colCount)
        return size;

    /* measures the tracks against the size being asked about */
    [self invalidateTrackCache];

    CGFloat minWidth = [self marginX];
    BOOL canFlexWidth = NO;
    for (NSUInteger i = 0; i < _colCount; i++) {
        CGFloat constrained = [self constrainedWidthOfColumn:i];
        if (!constrained) {
            canFlexWidth = YES;
            constrained = 128;
        }
        minWidth += constrained + [self marginX];
    }

    /* Controls spanning several columns are invisible to the per-column
     * pass above, so a wide check box or button used to get clipped at
     * the window edge. Make sure the window can hold them too. */
    for (NSDictionary *obj in _griddedViews) {
        NSView *view = [obj objectForKey:@"view"];
        if (![view isKindOfClass:[NSControl class]])
            continue;
        /* a wrapping label breaks its text rather than demand the width
         * of its longest line */
        if ([view isKindOfClass:[NSTextField class]]
         && ![(NSTextField *)view isEditable]
         && [[(NSTextField *)view cell] wraps])
            continue;
        NSUInteger colSpan = [[obj objectForKey:@"colSpan"] intValue];
        if (colSpan <= 1)
            continue;
        NSUInteger col = [[obj objectForKey:@"col"] intValue];
        CGFloat required = [self marginX] * 2 + [self objectSizeToFit:view].width;
        for (NSUInteger i = 0; i < _colCount; i++) {
            if (i >= col && i < col + colSpan)
                continue;
            CGFloat constrained = [self constrainedWidthOfColumn:i];
            if (!constrained)
                constrained = 128;
            required += constrained + [self marginX];
        }
        /* very long texts should truncate, not dictate a giant window */
        if (required > 640)
            required = 640;
        if (minWidth < required)
            minWidth = required;
    }
    if (size.width < minWidth)
        size.width = minWidth;
    if (!canFlexWidth)
        size.width = minWidth;

    /* An extension may ask for more room than its widgets strictly need:
     * a list of long URLs is unreadable at its "natural" width. It is a
     * hint for the size the window OPENS at, though, not a floor: applied
     * every time, it undid the user's own resizing at the next update. */
    NSWindow *window = [self window];
    extension_dialog_t *dialog = NULL;
    if (!_appliedSizeHint && [window isKindOfClass:[VLCDialogWindow class]])
        dialog = [(VLCDialogWindow *)window dialog];
    if (dialog != NULL && dialog->i_width > 0 && size.width < dialog->i_width)
        size.width = dialog->i_width;

    /* Only now can the height be asked for: a paragraph needs more lines
     * the narrower it is, so measuring it before the width was settled
     * answered for a window that no longer exists. The difference was
     * handed out as slack -- a few pixels of air under every single row,
     * for a dialog noticeably taller than its contents. */
    if (fabs(size.width - [self bounds].size.width) > 0.5) {
        NSSize probe = [self bounds].size;
        probe.width = size.width;
        [super setFrameSize:probe];
        [self invalidateTrackCache];
    }

    BOOL canFlexHeight = NO;
    for (NSUInteger i = 0; i < _rowCount; i++) {
        if (![self constrainedHeightOfRow:i]) {
            canFlexHeight = YES;
            break;
        }
    }
    CGFloat minHeight = [self minimumContentHeight];

    if (size.height < minHeight)
        size.height = minHeight;
    if (!canFlexHeight)
        size.height = minHeight;

    if (dialog != NULL) {
        if (dialog->i_height > 0 && size.height < dialog->i_height)
            size.height = dialog->i_height;
        if (dialog->i_width > 0 || dialog->i_height > 0)
            _appliedSizeHint = YES;
    }
    return size;
}

@end
