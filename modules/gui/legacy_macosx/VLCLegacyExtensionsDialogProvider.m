/*****************************************************************************
 * VLCLegacyExtensionsDialogProvider.m: extension dialogs (legacy interface)
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

#import "VLCLegacyExtensionsDialogProvider.h"
#import "misc.h"

#include <vlc_dialog.h>
#include <vlc_extensions.h>

/* The modern provider renders EXTENSION_WIDGET_HTML in a WebView. WebKit is
 * not a dependency of this interface and is absent from a bare 10.2 install,
 * so rich text goes through -[NSAttributedString initWithHTML:] (10.0) into a
 * plain NSTextView instead. Simple markup -- what extensions actually emit --
 * renders; scripting does not, which is no loss in a dialog. */

#define GRID_MARGIN  12.f
#define GRID_SPACING 8.f

/* Cells are tab-separated; a cell may carry "display\037sortkey" so that a
 * column sorts on a real value (a timestamp) rather than on its label. */
#define VLC_DIALOG_SORTKEY_SEP @"\037"

/*****************************************************************************
 * widget-carrying controls
 *****************************************************************************/

/* Hand-written accessors, not @property/@synthesize: synthesised properties
 * emit calls to objc_getProperty()/objc_setProperty(), which the Objective-C
 * runtime of 10.2-10.4 does not export. The link fails outright. */
#define VLC_LEGACY_WIDGET_ACCESSORS                                          \
- (extension_widget_t *)widget { return widget; }                            \
- (void)setWidget:(extension_widget_t *)aWidget { widget = aWidget; }

@interface VLCLegacyDialogButton : NSButton
{
    extension_widget_t *widget;
}
- (extension_widget_t *)widget;
- (void)setWidget:(extension_widget_t *)aWidget;
@end

@interface VLCLegacyDialogTextField : NSTextField
{
    extension_widget_t *widget;
}
- (extension_widget_t *)widget;
- (void)setWidget:(extension_widget_t *)aWidget;
@end

@interface VLCLegacyDialogSecureTextField : NSSecureTextField
{
    extension_widget_t *widget;
}
- (extension_widget_t *)widget;
- (void)setWidget:(extension_widget_t *)aWidget;
@end

@interface VLCLegacyDialogPopUpButton : NSPopUpButton
{
    extension_widget_t *widget;
@public
    /* set while the menu is refilled: that changes the selection too, and
     * the extension must not be told the user picked anything */
    BOOL programmaticSelection;
}
- (extension_widget_t *)widget;
- (void)setWidget:(extension_widget_t *)aWidget;
@end

/* no NSTableViewDataSource conformance: the protocol is only formal from
 * 10.6, and is informal on the SDK this interface is built against */
@interface VLCLegacyDialogList : NSTableView
{
    extension_widget_t *widget;
    NSMutableArray *contentArray;
    int sortColumn;         /* -1 while unsorted */
    BOOL sortAscending;
    BOOL programmaticSelection;  /* set while WE change the selection */
    NSArray *columnWeights;      /* natural width of each column's content */
    BOOL layingOut;
    NSTimeInterval filledAt;     /* when the list last got its content */
}
- (BOOL)programmaticSelection;
- (void)setProgrammaticSelection:(BOOL)flag;
/* Share the visible width between columns in proportion to their content,
 * so long URLs and titles are readable without dragging a divider. */
- (void)fitColumnsToContent;
- (void)layoutColumns;
- (extension_widget_t *)widget;
- (void)setWidget:(extension_widget_t *)aWidget;
- (void)setContentArray:(NSMutableArray *)array;
- (NSMutableArray *)contentArray;
- (void)setColumnHeaders:(NSArray *)headers;
- (int)sortColumn;
- (void)sortByColumn:(int)index ascending:(BOOL)ascending;
/* Show the first row, now and once more on the next turn of the run
 * loop. Call after filling the list. */
- (void)showTopOfList;
- (void)scrollToTopOfList;
- (BOOL)sortAscending;
- (void)resetSort;
@end

@interface VLCLegacyDialogWindow : NSWindow
{
    extension_dialog_t *dialog;
}
- (extension_dialog_t *)dialog;
- (void)setDialog:(extension_dialog_t *)aDialog;
@end

@implementation VLCLegacyDialogButton
VLC_LEGACY_WIDGET_ACCESSORS
@end

@implementation VLCLegacyDialogTextField
VLC_LEGACY_WIDGET_ACCESSORS
@end

@implementation VLCLegacyDialogSecureTextField
VLC_LEGACY_WIDGET_ACCESSORS
@end

@implementation VLCLegacyDialogPopUpButton
VLC_LEGACY_WIDGET_ACCESSORS
@end

@implementation VLCLegacyDialogWindow
- (extension_dialog_t *)dialog { return dialog; }
- (void)setDialog:(extension_dialog_t *)aDialog { dialog = aDialog; }
@end

/* qsort-style comparator for -sortUsingFunction:context: -- blocks do not
 * exist on the runtimes this interface targets */
struct VLCLegacySortCtx
{
    int column;
    BOOL ascending;
};

static NSString *VLCLegacyCell(id row, NSString *key, int column)
{
    NSArray *cells = [row objectForKey:key];
    if (column < 0 || (unsigned)column >= [cells count])
        return @"";
    return [cells objectAtIndex:column];
}

static NSInteger VLCLegacyCompareRows(id a, id b, void *opaque)
{
    struct VLCLegacySortCtx *ctx = (struct VLCLegacySortCtx *)opaque;
    NSString *keyA = VLCLegacyCell(a, @"sortKeys", ctx->column);
    NSString *keyB = VLCLegacyCell(b, @"sortKeys", ctx->column);
    NSComparisonResult result;

    if ([keyA length] && [keyB length]) {
        /* an explicit key: compare as numbers, which is what dates and
         * counts carry one for */
        double da = [keyA doubleValue], db = [keyB doubleValue];
        if (da != db)
            result = (da < db) ? NSOrderedAscending : NSOrderedDescending;
        else
            result = [keyA compare:keyB options:NSNumericSearch];
    } else {
        result = [VLCLegacyCell(a, @"cells", ctx->column)
                     compare:VLCLegacyCell(b, @"cells", ctx->column)
                     options:NSCaseInsensitiveSearch | NSNumericSearch];
    }
    if (!ctx->ascending) {
        if (result == NSOrderedAscending)
            result = NSOrderedDescending;
        else if (result == NSOrderedDescending)
            result = NSOrderedAscending;
    }
    return result;
}

@implementation VLCLegacyDialogList
VLC_LEGACY_WIDGET_ACCESSORS

- (void)setContentArray:(NSMutableArray *)array
{
    [array retain];
    [contentArray release];
    contentArray = array;
}

- (NSMutableArray *)contentArray
{
    return contentArray;
}

/* Fresh content is read from its first row. Twice: the clip view is
 * still being laid out when the list is filled, and the scroll it
 * settles on is not necessarily the one asked for. */
- (void)showTopOfList
{
    filledAt = [NSDate timeIntervalSinceReferenceDate];
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

/* A flick of the trackpad keeps sending scroll events after the finger
 * is up, and they go to whatever list is under the pointer -- opening
 * another season while the previous one was still gliding carried that
 * scroll into the new list. Only the momentum of a gesture that ended
 * before this content existed is dropped; mice of this vintage have no
 * momentum at all, and answer no to the test below. */
- (void)scrollWheel:(NSEvent *)event
{
    if ([event respondsToSelector:@selector(momentumPhase)]
     && [event momentumPhase] != 0
     && [NSDate timeIntervalSinceReferenceDate] - filledAt < 1.0)
        return;
    [super scrollWheel:event];
}

- (void)dealloc
{
    [contentArray release];
    [columnWeights release];
    [super dealloc];
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
        font = [NSFont systemFontOfSize:12.f];
    NSDictionary *attributes =
        [NSDictionary dictionaryWithObject:font forKey:NSFontAttributeName];

    NSMutableArray *weights = [NSMutableArray array];
    unsigned i, n;
    for (i = 0; i < [columns count]; i++) {
        float widest = 0.f;
        if ([self headerView] != nil) {
            NSString *title =
                [[[columns objectAtIndex:i] headerCell] stringValue];
            widest = [title sizeWithAttributes:attributes].width;
        }
        for (n = 0; n < [contentArray count]; n++) {
            NSDictionary *row = [contentArray objectAtIndex:n];
            NSArray *cells = [row objectForKey:@"cells"];
            NSString *text = (i < [cells count])
                ? [cells objectAtIndex:i] : [row objectForKey:@"text"];
            float width = [text sizeWithAttributes:attributes].width;
            if (width > widest)
                widest = width;
        }
        [weights addObject:[NSNumber numberWithFloat:widest + 12.f]];
    }
    [weights retain];
    [columnWeights release];
    columnWeights = weights;
    [self layoutColumns];
}

- (void)layoutColumns
{
    NSArray *columns = [self tableColumns];
    if (layingOut || columnWeights == nil
     || [columnWeights count] != [columns count])
        return;

    NSScrollView *scrollView = [self enclosingScrollView];
    float available = scrollView
        ? [[scrollView contentView] bounds].size.width
        : [self bounds].size.width;
    available -= [self intercellSpacing].width * [columns count];
    if (available < 120.f)
        return;   /* not laid out yet: keep whatever we have */

    double total = 0;
    unsigned i, widest = 0;
    for (i = 0; i < [columnWeights count]; i++) {
        float weight = [[columnWeights objectAtIndex:i] floatValue];
        total += weight;
        if (weight > [[columnWeights objectAtIndex:widest] floatValue])
            widest = i;
    }
    if (total <= 0)
        return;

    layingOut = YES;
    float used = 0.f;
    for (i = 0; i < [columns count]; i++) {
        float width;
        if (total <= available) {
            /* everything fits: give each column what it needs and hand the
             * slack to the longest one, rather than padding them all */
            width = [[columnWeights objectAtIndex:i] floatValue];
            if (i == widest)
                width += (float)(available - total);
        } else if (i + 1 == [columns count]) {
            width = available - used;   /* no rounding crumbs on the right */
        } else {
            width = (float)floor(available
                * [[columnWeights objectAtIndex:i] floatValue] / total);
        }
        if (width < 48.f)
            width = 48.f;
        [[columns objectAtIndex:i] setWidth:width];
        used += width;
    }
    layingOut = NO;
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    [self layoutColumns];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[contentArray count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (row < 0 || (unsigned)row >= [contentArray count])
        return @"";
    NSDictionary *entry = [contentArray objectAtIndex:row];
    NSArray *cells = [entry objectForKey:@"cells"];
    if (!cells)
        return [entry objectForKey:@"text"];
    if ([[self tableColumns] count] == 1 && [cells count] == 1)
        return [cells objectAtIndex:0];
    int columnIndex = [[column identifier] intValue];
    return (columnIndex >= 0 && (unsigned)columnIndex < [cells count])
        ? [cells objectAtIndex:columnIndex] : @"";
}

- (void)setColumnHeaders:(NSArray *)headers
{
    unsigned wanted = headers ? (unsigned)[headers count] : 1;

    while ([[self tableColumns] count] > wanted)
        [self removeTableColumn:[[self tableColumns] lastObject]];
    while ([[self tableColumns] count] < wanted) {
        NSTableColumn *column = [[[NSTableColumn alloc] init] autorelease];
        [column setEditable:NO];
        [self addTableColumn:column];
    }
    NSArray *columns = [self tableColumns];
    unsigned i;
    for (i = 0; i < [columns count]; i++) {
        NSTableColumn *column = [columns objectAtIndex:i];
        [column setIdentifier:[NSString stringWithFormat:@"%u", i]];
        if (headers)
            [[column headerCell]
                setStringValue:[headers objectAtIndex:i]];
    }

    if (headers && ![self headerView])
        [self setHeaderView:
            [[[NSTableHeaderView alloc] init] autorelease]];
    else if (!headers && [self headerView])
        [self setHeaderView:nil];
}

- (int)sortColumn { return sortColumn; }
- (BOOL)sortAscending { return sortAscending; }
- (void)resetSort { sortColumn = -1; sortAscending = YES; }
- (BOOL)programmaticSelection { return programmaticSelection; }
- (void)setProgrammaticSelection:(BOOL)flag { programmaticSelection = flag; }

- (void)sortByColumn:(int)index ascending:(BOOL)ascending
{
    struct VLCLegacySortCtx ctx;
    ctx.column = index;
    ctx.ascending = ascending;
    sortColumn = index;
    sortAscending = ascending;
    [contentArray sortUsingFunction:VLCLegacyCompareRows context:&ctx];
    [self reloadData];
}

@end

/*****************************************************************************
 * grid view
 *****************************************************************************
 * Extensions place their widgets on a row/column grid with spans. This lays
 * that grid out from the natural size of each control: columns take the width
 * of their widest single-column occupant, rows the height of their tallest,
 * and a spanning control widens the last column it covers when the span is
 * too narrow for it.
 *****************************************************************************/

@interface VLCLegacyDialogGridView : NSView
{
    NSMutableArray *cells;   /* dictionaries: view, row, col, rowSpan, colSpan */
}
- (void)setSubview:(NSView *)view
             atRow:(int)row
            column:(int)column
           rowSpan:(int)rowSpan
           colSpan:(int)colSpan;
- (void)removeSubviewFromGrid:(NSView *)view;
- (NSSize)preferredSize;
- (NSSize)preferredSizeForWidth:(float)targetWidth;
- (void)layoutGrid;
@end

/* A dialog may never demand more room than the display holds, and must
 * always be shrinkable to something a small screen can show. */
#define VLC_LEGACY_MIN_DIALOG_W 360.f
#define VLC_LEGACY_MIN_DIALOG_H 200.f
/* how long typing must pause before the extension hears about it */
#define VLC_LEGACY_TEXT_DEBOUNCE 0.3
/* below this a column shows nothing useful, so the shortfall of a window
 * narrower than its content is taken from the wider tracks first */
#define VLC_LEGACY_MIN_COLUMN_W 48.f

static void VLCLegacyClampToScreen(NSWindow *window, NSSize *size)
{
    NSScreen *screen = [window screen];
    if (!screen)
        screen = [NSScreen mainScreen];
    if (!screen)
        return;

    NSRect visible = [screen visibleFrame];
    NSRect content = [NSWindow contentRectForFrameRect:visible
                                             styleMask:[window styleMask]];
    if (size->width > content.size.width)
        size->width = content.size.width;
    if (size->height > content.size.height)
        size->height = content.size.height;
}

/* natural size of a control, honouring the width/height hints of the widget */
static NSSize VLCLegacyPreferredSize(NSView *view, extension_widget_t *widget)
{
    NSSize size = NSMakeSize(0, 0);

    if ([view isKindOfClass:[NSScrollView class]]) {
        /* lists and rich text have no natural size worth speaking of */
        size = NSMakeSize(320, 140);
    } else if ([view isKindOfClass:[NSImageView class]]) {
        NSImage *image = [(NSImageView *)view image];
        size = image ? [image size] : NSMakeSize(160, 120);
    } else if ([view isKindOfClass:[NSProgressIndicator class]]) {
        size = NSMakeSize(32, 32);
    } else if ([view isKindOfClass:[NSControl class]]) {
        /* Ask the cell, never -sizeToFit: that one RESIZES the control,
         * and measuring must not lay anything out. The window is only
         * re-laid out when it changes size, so a measure taken after the
         * last layout used to leave every control at its text width --
         * an emptied entry field ended up a few pixels wide. */
        NSCell *cell = [(NSControl *)view cell];
        size = cell ? [cell cellSize] : [view frame].size;
        /* an empty entry field asks for nothing at all */
        if ([view isKindOfClass:[NSTextField class]]
         && [(NSTextField *)view isEditable] && size.width < 220)
            size.width = 220;
        /* A rounded bezel clips its last glyph at the fitted width. How
         * much it eats is not the same on every release -- on 10.2 the
         * cell's own answer left "< Retour" cut -- so rather than pad a
         * guess, measure the title with the font it is drawn in and keep
         * room for the two end caps. */
        if ([view isKindOfClass:[NSButton class]]) {
            NSButton *button = (NSButton *)view;
            NSFont *font = [button font];
            NSString *title = [button title];
            size.width += 16;
            if (font != nil && [title length] > 0) {
                NSDictionary *attrs = [NSDictionary
                    dictionaryWithObject:font forKey:NSFontAttributeName];
                float needed = [title sizeWithAttributes:attrs].width + 32.f;
                if (size.width < needed)
                    size.width = needed;
            }
        }
    } else {
        size = [view frame].size;
    }

    if (widget != NULL) {
        if (widget->i_width > 0 && size.width < widget->i_width)
            size.width = widget->i_width;
        if (widget->i_height > 0 && size.height < widget->i_height)
            size.height = widget->i_height;
    }
    if (size.width < 1)
        size.width = 1;
    if (size.height < 1)
        size.height = 1;
    return size;
}

@implementation VLCLegacyDialogGridView

- (id)initWithFrame:(NSRect)frame
{
    if (self = [super initWithFrame:frame])
        cells = [[NSMutableArray alloc] init];
    return self;
}

- (void)dealloc
{
    [cells release];
    [super dealloc];
}

- (BOOL)isFlipped
{
    return YES;   /* row 0 at the top, like the grid the extension describes */
}

- (NSMutableDictionary *)cellForView:(NSView *)view
{
    unsigned i;
    for (i = 0; i < [cells count]; i++) {
        NSMutableDictionary *cell = [cells objectAtIndex:i];
        if ([cell objectForKey:@"view"] == view)
            return cell;
    }
    return nil;
}

- (void)setSubview:(NSView *)view
             atRow:(int)row
            column:(int)column
           rowSpan:(int)rowSpan
           colSpan:(int)colSpan
{
    NSMutableDictionary *cell = [self cellForView:view];
    if (!cell) {
        cell = [NSMutableDictionary dictionary];
        [cell setObject:view forKey:@"view"];
        [cells addObject:cell];
        [self addSubview:view];
    }
    [cell setObject:[NSNumber numberWithInt:row] forKey:@"row"];
    [cell setObject:[NSNumber numberWithInt:column] forKey:@"col"];
    [cell setObject:[NSNumber numberWithInt:rowSpan < 1 ? 1 : rowSpan]
             forKey:@"rowSpan"];
    [cell setObject:[NSNumber numberWithInt:colSpan < 1 ? 1 : colSpan]
             forKey:@"colSpan"];
}

- (void)removeSubviewFromGrid:(NSView *)view
{
    NSMutableDictionary *cell = [self cellForView:view];
    if (!cell)
        return;
    [view removeFromSuperview];
    [cells removeObject:cell];
}

/* A wrapping label given less width than its longest line breaks it
 * again, on lines nobody measured: ask the cell how tall it really is at
 * the width it will get, so a paragraph is never cut off at the bottom.
 * Run once on the natural widths (to size the window) and again on the
 * final ones (to lay out), since the two can differ a lot. */
- (void)growRows:(float *)heights forWrappingLabelsWithWidths:(const float *)widths
{
    unsigned n;
    for (n = 0; n < [cells count]; n++) {
        NSMutableDictionary *cell = [cells objectAtIndex:n];
        NSView *view = [cell objectForKey:@"view"];
        int row = [[cell objectForKey:@"row"] intValue];
        int col = [[cell objectForKey:@"col"] intValue];
        int rowSpan = [[cell objectForKey:@"rowSpan"] intValue];
        int colSpan = [[cell objectForKey:@"colSpan"] intValue];

        if (row >= 64 || col >= 64 || rowSpan != 1)
            continue;
        if (![view isKindOfClass:[NSTextField class]]
         || [(NSTextField *)view isEditable]
         || ![[(NSTextField *)view cell] wraps])
            continue;
        extension_widget_t *lw = [self widgetOfView:view];
        if (lw && lw->b_hide)
            continue;

        float available = 0.f;
        int c;
        for (c = col; c < col + colSpan && c < 64; c++)
            available += widths[c] + (c > col ? GRID_SPACING : 0.f);
        if (available <= 0.f)
            continue;

        /* Only a text that does not fit on one line needs this: asking a
         * cell for a bounded size adds the paragraph spacing of its
         * style, and a one-line heading would gain empty space around it. */
        NSCell *labelCell = [(NSTextField *)view cell];
        if ([labelCell cellSize].width <= available)
            continue;

        NSSize wrapped = [labelCell cellSizeForBounds:
            NSMakeRect(0.f, 0.f, available, 100000.f)];
        if (wrapped.height > heights[row])
            heights[row] = wrapped.height;
    }
}

/* Fills widths[]/heights[] with the track sizes, returns the grid dimensions.
 * Both output arrays must hold at least 64 entries. */
- (void)measureColumns:(float *)widths
                  rows:(float *)heights
               columns:(int *)outCols
                  rows:(int *)outRows
{
    int i, maxCol = 0, maxRow = 0;

    for (i = 0; i < 64; i++) {
        widths[i] = 0.f;
        heights[i] = 0.f;
    }

    /* single-track occupants define the tracks */
    unsigned n;
    for (n = 0; n < [cells count]; n++) {
        NSMutableDictionary *cell = [cells objectAtIndex:n];
        NSView *view = [cell objectForKey:@"view"];
        int row = [[cell objectForKey:@"row"] intValue];
        int col = [[cell objectForKey:@"col"] intValue];
        int rowSpan = [[cell objectForKey:@"rowSpan"] intValue];
        int colSpan = [[cell objectForKey:@"colSpan"] intValue];

        if (row + rowSpan > maxRow)
            maxRow = row + rowSpan;
        if (col + colSpan > maxCol)
            maxCol = col + colSpan;
        if (row >= 64 || col >= 64)
            continue;

        extension_widget_t *w = [self widgetOfView:view];
        NSSize size = (w && w->b_hide) ? NSMakeSize(0, 0)
            : VLCLegacyPreferredSize(view, w);

        if (colSpan == 1 && size.width > widths[col])
            widths[col] = size.width;
        if (rowSpan == 1 && size.height > heights[row])
            heights[row] = size.height;
    }

    if (maxCol > 64) maxCol = 64;
    if (maxRow > 64) maxRow = 64;

    /* a spanning occupant widens the last track it covers if it does not
     * fit -- except a wrapping label, which would rather break its text
     * than force the window to the width of one long line */
    for (n = 0; n < [cells count]; n++) {
        NSMutableDictionary *cell = [cells objectAtIndex:n];
        NSView *view = [cell objectForKey:@"view"];
        int row = [[cell objectForKey:@"row"] intValue];
        int col = [[cell objectForKey:@"col"] intValue];
        int rowSpan = [[cell objectForKey:@"rowSpan"] intValue];
        int colSpan = [[cell objectForKey:@"colSpan"] intValue];

        extension_widget_t *w = [self widgetOfView:view];
        if ((w && w->b_hide) || row >= 64 || col >= 64)
            continue;
        if ([view isKindOfClass:[NSTextField class]]
         && ![(NSTextField *)view isEditable]
         && [[(NSTextField *)view cell] wraps])
            continue;   /* it wraps; the height pass below sizes it */

        NSSize size = VLCLegacyPreferredSize(view, w);

        if (colSpan > 1) {
            float have = 0.f;
            int c;
            for (c = col; c < col + colSpan && c < 64; c++)
                have += widths[c] + (c > col ? GRID_SPACING : 0.f);
            if (have < size.width && col + colSpan - 1 < 64)
                widths[col + colSpan - 1] += size.width - have;
        }
        if (rowSpan > 1) {
            float have = 0.f;
            int r, last = -1, covered = 0;
            for (r = row; r < row + rowSpan && r < 64; r++) {
                have += heights[r] + (r > row ? GRID_SPACING : 0.f);
                last = r;
                covered++;
            }
            if (have < size.height && last >= 0) {
                /* A picture is scaled into the block its rows come to, so
                 * a short block leaves it squashed: it raises them all,
                 * evenly. Piling the difference on the last row instead
                 * opened a hole between the text above and what follows.
                 * Anything else does grow that last row, as before. */
                if ([view isKindOfClass:[NSImageView class]]) {
                    float share = (size.height - have) / covered;
                    for (r = row; r <= last; r++)
                        heights[r] += share;
                } else {
                    heights[last] += size.height - have;
                }
            }
        }
    }

    [self growRows:heights forWrappingLabelsWithWidths:widths];

    *outCols = maxCol;
    *outRows = maxRow;
}

/* the widget behind a control, or NULL for containers we wrapped ourselves */
- (extension_widget_t *)widgetOfView:(NSView *)view
{
    if ([view respondsToSelector:@selector(widget)])
        return (extension_widget_t *)[(id)view widget];
    if ([view isKindOfClass:[NSScrollView class]]) {
        NSView *doc = [(NSScrollView *)view documentView];
        if ([doc respondsToSelector:@selector(widget)])
            return (extension_widget_t *)[(id)doc widget];
    }
    return NULL;
}

/* The height a paragraph needs depends on the width it is given, so the
 * two cannot be measured independently: pass the width the window will
 * actually have (0 for the natural one). Sizing a window from the
 * natural width while laying it out at another left the last rows below
 * the bottom edge. */
- (NSSize)preferredSizeForWidth:(float)targetWidth
{
    float widths[64], heights[64];
    int cols = 0, rows = 0, i;
    float w = 0.f, h = 0.f;

    [self measureColumns:widths rows:heights columns:&cols rows:&rows];

    for (i = 0; i < cols && i < 64; i++)
        w += widths[i] + (i > 0 ? GRID_SPACING : 0.f);
    w += 2 * GRID_MARGIN;

    if (targetWidth > 0.f) {
        [self adjustWidths:widths columns:cols toWidth:targetWidth];
        [self growRows:heights forWrappingLabelsWithWidths:widths];
    }

    for (i = 0; i < rows && i < 64; i++)
        h += heights[i] + (i > 0 ? GRID_SPACING : 0.f);

    return NSMakeSize(w, h + 2 * GRID_MARGIN);
}

- (NSSize)preferredSize
{
    return [self preferredSizeForWidth:0.f];
}

/* Spread the difference between what the widgets asked for and the width
 * they actually get: extra room goes to the last column so lists grow,
 * and a shortfall is taken from the columns that can give. */
- (void)adjustWidths:(float *)widths columns:(int)cols toWidth:(float)available
{
    int i;
    /* Which columns hold a picture. An image has a size of its own:
     * squeezing its column only shrinks the picture, while text and
     * controls can give. But it never takes more than a third of the
     * window either -- what stands beside it needs the rest more. */
    BOOL rigid[64];
    unsigned c;
    for (i = 0; i < 64; i++)
        rigid[i] = NO;
    for (c = 0; c < [cells count]; c++) {
        NSMutableDictionary *cell = [cells objectAtIndex:c];
        if (![[cell objectForKey:@"view"] isKindOfClass:[NSImageView class]])
            continue;
        int col = [[cell objectForKey:@"col"] intValue];
        int colSpan = [[cell objectForKey:@"colSpan"] intValue];
        int k;
        for (k = col; k < col + colSpan && k < 64; k++)
            rigid[k] = YES;
    }
    if (available > 0.f) {
        float cap = available / 3.f;
        for (i = 0; i < cols && i < 64; i++)
            if (rigid[i] && widths[i] > cap)
                widths[i] = cap;
    }

    /* hand any width the window has beyond the natural one to the last column,
     * so that lists and text areas grow when the user resizes -- but never
     * to a picture, which would only stand in an ever wider empty frame
     * while the text beside it kept its first width */
    float natural = 2 * GRID_MARGIN;
    for (i = 0; i < cols && i < 64; i++)
        natural += widths[i] + (i > 0 ? GRID_SPACING : 0.f);
    float extraW = available - natural;
    if (extraW > 0 && cols > 0 && cols <= 64) {
        int grower = cols - 1;
        while (grower > 0 && rigid[grower])
            grower--;
        widths[grower] += extraW;
    } else if (extraW < 0 && cols > 0 && cols <= 64) {
        /* Narrower than what the widgets asked for: rather than let the
         * right-hand tracks fall off the edge, take the shortfall from
         * every column in proportion to its width, down to a floor that
         * keeps each one legible. Picture columns sit it out, see above. */
        /* A label can be truncated and an entry field can hold fewer
         * characters, but a button title is either readable or it is
         * not: a column holding one never shrinks below it. */
        float floors[64];
        for (i = 0; i < 64; i++)
            floors[i] = VLC_LEGACY_MIN_COLUMN_W;
        for (c = 0; c < [cells count]; c++) {
            NSMutableDictionary *cell = [cells objectAtIndex:c];
            NSView *view = [cell objectForKey:@"view"];
            if (![view isKindOfClass:[NSButton class]])
                continue;
            if ([[cell objectForKey:@"colSpan"] intValue] > 1)
                continue;
            int col = [[cell objectForKey:@"col"] intValue];
            if (col < 0 || col >= 64)
                continue;
            float want = VLCLegacyPreferredSize(view,
                             [self widgetOfView:view]).width;
            if (floors[col] < want)
                floors[col] = want;
        }

        float shrinkable = 0.f;
        for (i = 0; i < cols && i < 64; i++)
            if (!rigid[i] && widths[i] > floors[i])
                shrinkable += widths[i] - floors[i];
        if (shrinkable > 0.f) {
            float missing = -extraW;
            if (missing > shrinkable)
                missing = shrinkable;
            for (i = 0; i < cols && i < 64; i++) {
                if (rigid[i] || widths[i] <= floors[i])
                    continue;
                widths[i] -= missing * (widths[i] - floors[i]) / shrinkable;
            }
        }
    }

}

- (void)layoutGrid
{
    float widths[64], heights[64];
    int cols = 0, rows = 0, i;

    [self measureColumns:widths rows:heights columns:&cols rows:&rows];

    [self adjustWidths:widths columns:cols toWidth:[self bounds].size.width];

    /* The columns have their final width now, which is not the width the
     * first pass measured against: a paragraph squeezed into a narrower
     * column needs more lines, and it was those lines that got cut off. */
    [self growRows:heights forWrappingLabelsWithWidths:widths];

    float naturalH = 2 * GRID_MARGIN;
    for (i = 0; i < rows && i < 64; i++)
        naturalH += heights[i] + (i > 0 ? GRID_SPACING : 0.f);
    float extraH = [self bounds].size.height - naturalH;
    if (extraH > 0 && rows > 0 && rows <= 64) {
        /* Spare height belongs to the rows holding a list or a text area:
         * those are the only widgets that can show more of themselves.
         * Handing it to the last row instead just pushed a label down and
         * left the list at its minimum size. */
        BOOL flexible[64];
        int flexibleRows = 0;
        for (i = 0; i < 64; i++)
            flexible[i] = NO;

        unsigned c;
        for (c = 0; c < [cells count]; c++) {
            NSMutableDictionary *cell = [cells objectAtIndex:c];
            NSView *view = [cell objectForKey:@"view"];
            if (![view isKindOfClass:[NSScrollView class]])
                continue;
            int row = [[cell objectForKey:@"row"] intValue];
            int rowSpan = [[cell objectForKey:@"rowSpan"] intValue];
            int r;
            for (r = row; r < row + rowSpan && r < 64 && r < rows; r++) {
                if (!flexible[r]) {
                    flexible[r] = YES;
                    flexibleRows++;
                }
            }
        }

        if (flexibleRows > 0) {
            float share = extraH / flexibleRows;
            for (i = 0; i < rows && i < 64; i++)
                if (flexible[i])
                    heights[i] += share;
        } else
            heights[rows - 1] += extraH;
    }

    unsigned n;
    for (n = 0; n < [cells count]; n++) {
        NSMutableDictionary *cell = [cells objectAtIndex:n];
        NSView *view = [cell objectForKey:@"view"];
        int row = [[cell objectForKey:@"row"] intValue];
        int col = [[cell objectForKey:@"col"] intValue];
        int rowSpan = [[cell objectForKey:@"rowSpan"] intValue];
        int colSpan = [[cell objectForKey:@"colSpan"] intValue];
        int c, r;

        if (row >= 64 || col >= 64)
            continue;

        float x = GRID_MARGIN, y = GRID_MARGIN, w = 0.f, h = 0.f;

        for (c = 0; c < col && c < 64; c++)
            x += widths[c] + GRID_SPACING;
        for (r = 0; r < row && r < 64; r++)
            y += heights[r] + GRID_SPACING;
        for (c = col; c < col + colSpan && c < 64; c++)
            w += widths[c] + (c > col ? GRID_SPACING : 0.f);
        for (r = row; r < row + rowSpan && r < 64; r++)
            h += heights[r] + (r > row ? GRID_SPACING : 0.f);

        /* buttons and check boxes look wrong stretched across a whole span */
        if ([view isKindOfClass:[NSButton class]]) {
            NSSize want = VLCLegacyPreferredSize(view, [self widgetOfView:view]);
            if (want.width < w)
                w = want.width;
            if (want.height < h)
                h = want.height;
        }

        /* A picture is not stretched either: the photo border is drawn
         * around the whole view, so a picture covering tall rows would
         * hang in the middle of an empty frame. Keep its own size and
         * centre it on the block it covers. */
        if ([view isKindOfClass:[NSImageView class]]) {
            NSSize want = VLCLegacyPreferredSize(view, [self widgetOfView:view]);
            if (want.width > 0.f && want.width < w) {
                x += (w - want.width) / 2;
                w = want.width;
            }
            /* Top of the block, level with the title it illustrates --
             * centred, it drifted away from the text it belongs to as
             * sections were unfolded below. */
            if (want.height > 0.f && want.height < h)
                h = want.height;
        }

        [view setFrame:NSMakeRect(x, y, w, h)];
    }
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldSize
{
    (void)oldSize;
    [self layoutGrid];
}

@end

/*****************************************************************************
 * provider
 *****************************************************************************/

@interface VLCLegacyExtensionsDialogProvider ()
- (void)updateExtensionDialog:(NSValue *)value;
@end

static void extensionDialogCallback(extension_dialog_t *p_ext_dialog,
                                    void *p_data)
{
    VLCLegacyExtensionsDialogProvider *provider =
        (VLCLegacyExtensionsDialogProvider *)p_data;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    if (provider)
        [provider performSelectorOnMainThread:@selector(updateExtensionDialog:)
                                   withObject:[NSValue valueWithPointer:
                                                   p_ext_dialog]
                                waitUntilDone:YES];
    [pool release];
}

@implementation VLCLegacyExtensionsDialogProvider

- (id)initWithIntf:(intf_thread_t *)intf
{
    if (self = [super init]) {
        p_intf = intf;
        vlc_dialog_provider_set_ext_callback(p_intf, extensionDialogCallback,
                                             self);
    }
    return self;
}

- (void)stop
{
    if (p_intf) {
        vlc_dialog_provider_set_ext_callback(p_intf, NULL, NULL);
        p_intf = NULL;
    }
}

- (void)dealloc
{
    [self stop];
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [super dealloc];
}

/*****************************************************************************
 * control creation and refresh
 *****************************************************************************/

- (NSView *)createControlForWidget:(extension_widget_t *)widget
{
    switch (widget->type) {
    case EXTENSION_WIDGET_LABEL:
    {
        NSTextField *field = [[NSTextField alloc] init];
        [field setEditable:NO];
        [field setBordered:NO];
        [field setDrawsBackground:NO];
        [field setSelectable:YES];
        /* a label whose text carries newlines is a paragraph: draw every
         * line of it, at the font's own leading rather than a grid row
         * apart */
        [[field cell] setWraps:YES];
        return field;
    }
    case EXTENSION_WIDGET_CHECK_BOX:
    {
        VLCLegacyDialogButton *button = [[VLCLegacyDialogButton alloc] init];
        [button setButtonType:NSSwitchButton];
        [button setWidget:widget];
        [button setTarget:self];
        [button setAction:@selector(triggerClick:)];
        return button;
    }
    case EXTENSION_WIDGET_BUTTON:
    {
        VLCLegacyDialogButton *button = [[VLCLegacyDialogButton alloc] init];
        [button setBezelStyle:NSRoundedBezelStyle];
        [button setWidget:widget];
        [button setTarget:self];
        [button setAction:@selector(triggerClick:)];
        return button;
    }
    case EXTENSION_WIDGET_TEXT_FIELD:
    {
        VLCLegacyDialogTextField *field =
            [[VLCLegacyDialogTextField alloc] init];
        [field setWidget:widget];
        [field setEditable:YES];
        [field setBezeled:YES];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(syncTextField:)
                   name:NSControlTextDidChangeNotification
                 object:field];
        /* Enter validates the field, like any search box */
        [field setTarget:self];
        [field setAction:@selector(textFieldActivated:)];
        return field;
    }
    case EXTENSION_WIDGET_PASSWORD:
    {
        VLCLegacyDialogSecureTextField *field =
            [[VLCLegacyDialogSecureTextField alloc] init];
        [field setWidget:widget];
        [field setEditable:YES];
        [field setBezeled:YES];
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(syncTextField:)
                   name:NSControlTextDidChangeNotification
                 object:field];
        /* Enter validates the field, like any search box */
        [field setTarget:self];
        [field setAction:@selector(textFieldActivated:)];
        return field;
    }
    case EXTENSION_WIDGET_DROPDOWN:
    {
        VLCLegacyDialogPopUpButton *popup =
            [[VLCLegacyDialogPopUpButton alloc] init];
        [popup setWidget:widget];
        [popup setTarget:self];
        [popup setAction:@selector(popUpSelectionChanged:)];
        return popup;
    }
    case EXTENSION_WIDGET_LIST:
    {
        NSScrollView *scroll = [[NSScrollView alloc] init];
        [scroll setHasVerticalScroller:YES];
        [scroll setBorderType:NSBezelBorder];

        VLCLegacyDialogList *list =
            [[[VLCLegacyDialogList alloc] init] autorelease];
        [list setHeaderView:nil];
        [list setAllowsMultipleSelection:YES];
        [list setWidget:widget];
        [list resetSort];

        NSTableColumn *column =
            [[[NSTableColumn alloc] initWithIdentifier:@"0"] autorelease];
        [column setEditable:NO];
        [list addTableColumn:column];
        [list setDataSource:(id)list];
        [list setDelegate:(id)self];
        [list setTarget:self];
        [list setDoubleAction:@selector(listDoubleClicked:)];

        [scroll setDocumentView:list];
        return scroll;
    }
    case EXTENSION_WIDGET_IMAGE:
    {
        NSImageView *imageView = [[NSImageView alloc] init];
        [imageView setImageFrameStyle:NSImageFramePhoto];
        /* NSImageScaleProportionallyUpOrDown is 10.5; this is its ancestor */
        [imageView setImageScaling:NSScaleProportionally];
        [imageView setEditable:NO];
        return imageView;
    }
    case EXTENSION_WIDGET_HTML:
    {
        NSScrollView *scroll = [[NSScrollView alloc] init];
        [scroll setHasVerticalScroller:YES];
        [scroll setBorderType:NSBezelBorder];

        NSTextView *textView = [[[NSTextView alloc] init] autorelease];
        [textView setEditable:NO];
        [textView setDrawsBackground:NO];
        [scroll setDocumentView:textView];
        return scroll;
    }
    case EXTENSION_WIDGET_SPIN_ICON:
    {
        NSProgressIndicator *spinner = [[NSProgressIndicator alloc] init];
        [spinner setStyle:NSProgressIndicatorSpinningStyle];
        [spinner setDisplayedWhenStopped:NO];
        return spinner;
    }
    }

    msg_Err(p_intf, "unhandled extension widget type %i", widget->type);
    return nil;
}

/* rich text, tolerating the plain strings most widgets actually carry */
static NSAttributedString *VLCLegacyAttributedText(const char *psz_text)
{
    NSString *string = psz_text ? [NSString stringWithUTF8String:psz_text] : nil;
    if (!string)
        string = @"";

    if ([string rangeOfString:@"<"].location == NSNotFound)
        return [[[NSAttributedString alloc] initWithString:string] autorelease];

    /* The HTML parser assumes Latin-1 unless the markup says otherwise,
     * which turned every accent and dash of a UTF-8 label into mojibake
     * ("Direct play â€” ..."). Saying so in the document itself works on
     * every system version, unlike the options: parameter. */
    string = [@"<meta http-equiv=\"Content-Type\" "
               "content=\"text/html; charset=utf-8\">" stringByAppendingString:string];
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSAttributedString *rich = data
        ? [[[NSAttributedString alloc] initWithHTML:data
                                 documentAttributes:NULL] autorelease] : nil;
    return rich ? rich
        : [[[NSAttributedString alloc] initWithString:string] autorelease];
}

- (void)updateControl:(NSView *)control forWidget:(extension_widget_t *)widget
{
    switch (widget->type) {
    case EXTENSION_WIDGET_LABEL:
        [(NSTextField *)control
            setAttributedStringValue:VLCLegacyAttributedText(widget->psz_text)];
        break;

    case EXTENSION_WIDGET_HTML:
    {
        NSTextView *textView = (NSTextView *)[(NSScrollView *)control
                                                  documentView];
        NSAttributedString *rich = VLCLegacyAttributedText(widget->psz_text);
        [[textView textStorage] setAttributedString:rich];
        break;
    }

    case EXTENSION_WIDGET_TEXT_FIELD:
    case EXTENSION_WIDGET_PASSWORD:
        /* only push the core value in when it differs, so that typing is not
         * interrupted by an update triggered from the extension side */
        if (widget->psz_text) {
            NSString *string = [NSString stringWithUTF8String:widget->psz_text];
            if (string && ![[(NSTextField *)control stringValue]
                                isEqualToString:string])
                [(NSTextField *)control setStringValue:string];
        }
        break;

    case EXTENSION_WIDGET_CHECK_BOX:
    case EXTENSION_WIDGET_BUTTON:
        [(NSButton *)control setTitle:widget->psz_text
            ? [NSString stringWithUTF8String:widget->psz_text] : @""];
        if (widget->type == EXTENSION_WIDGET_CHECK_BOX)
            [(NSButton *)control
                setState:widget->b_checked ? NSOnState : NSOffState];
        break;

    case EXTENSION_WIDGET_DROPDOWN:
    {
        VLCLegacyDialogPopUpButton *popup =
            (VLCLegacyDialogPopUpButton *)control;
        struct extension_widget_value_t *value;
        int selected = -1, i = 0;

        popup->programmaticSelection = YES;
        [popup removeAllItems];
        for (value = widget->p_values; value != NULL;
             value = value->p_next, i++) {
            [popup addItemWithTitle:value->psz_text
                ? [NSString stringWithUTF8String:value->psz_text] : @""];
            if (value->b_selected)
                selected = i;
        }
        if (selected >= 0)
            [popup selectItemAtIndex:selected];
        [popup synchronizeTitleAndSelectedItem];
        popup->programmaticSelection = NO;
        break;
    }

    case EXTENSION_WIDGET_LIST:
    {
        VLCLegacyDialogList *list =
            (VLCLegacyDialogList *)[(NSScrollView *)control documentView];
        NSMutableArray *array = [NSMutableArray array];
        struct extension_widget_value_t *value;

        /* tab-separated headers in the widget text = native columns */
        NSArray *headers = nil;
        if (widget->psz_text && strchr(widget->psz_text, '\t'))
            headers = [[NSString stringWithUTF8String:widget->psz_text]
                          componentsSeparatedByString:@"\t"];
        [list setColumnHeaders:headers];

        for (value = widget->p_values; value != NULL; value = value->p_next) {
            NSString *text = value->psz_text
                ? [NSString stringWithUTF8String:value->psz_text] : @"";
            NSMutableArray *cells = [NSMutableArray array];
            NSMutableArray *sortKeys = [NSMutableArray array];
            NSArray *rawCells = [text componentsSeparatedByString:@"\t"];
            unsigned c;
            for (c = 0; c < [rawCells count]; c++) {
                NSString *cell = [rawCells objectAtIndex:c];
                NSRange sep = [cell rangeOfString:VLC_DIALOG_SORTKEY_SEP];
                if (sep.location == NSNotFound) {
                    [cells addObject:cell];
                    [sortKeys addObject:@""];
                } else {
                    [cells addObject:[cell substringToIndex:sep.location]];
                    [sortKeys addObject:
                        [cell substringFromIndex:sep.location + sep.length]];
                }
            }
            [array addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithInt:value->i_id], @"id",
                text, @"text",
                cells, @"cells",
                sortKeys, @"sortKeys",
                nil]];
        }
        [list setProgrammaticSelection:YES];
        [list setContentArray:array];
        [list resetSort];   /* fresh content, extension's order */
        [list reloadData];
        [list fitColumnsToContent];

        /* restore the selection the extension asked for */
        int row = 0;
        [list deselectAll:nil];
        for (value = widget->p_values; value != NULL;
             value = value->p_next, row++) {
            if (value->b_selected)
                [list selectRow:row byExtendingSelection:YES];
        }

        /* Fresh content is read from its first row: keeping the scroll of
         * whatever was in the list before leaves the user looking at the
         * middle of something else. */
        if ([array count] > 0)
            [list showTopOfList];
        [list setProgrammaticSelection:NO];
        break;
    }

    case EXTENSION_WIDGET_IMAGE:
    {
        NSImage *image = nil;
        if (widget->psz_text) {
            NSString *path = [NSString stringWithUTF8String:widget->psz_text];
            if (path)
                image = [[[NSImage alloc] initWithContentsOfFile:path]
                            autorelease];
        }
        [(NSImageView *)control setImage:image];
        break;
    }

    case EXTENSION_WIDGET_SPIN_ICON:
        if (widget->i_spin_loops != 0)
            [(NSProgressIndicator *)control startAnimation:self];
        else
            [(NSProgressIndicator *)control stopAnimation:self];
        break;
    }
}

/*****************************************************************************
 * actions coming back from the user
 *****************************************************************************/

- (void)triggerClick:(id)sender
{
    extension_widget_t *widget = [(VLCLegacyDialogButton *)sender widget];
    if (!widget)
        return;

    vlc_mutex_lock(&widget->p_dialog->lock);
    if (widget->type == EXTENSION_WIDGET_BUTTON)
        extension_WidgetClicked(widget->p_dialog, widget);
    else
        widget->b_checked = [(NSButton *)sender state] == NSOnState;
    vlc_mutex_unlock(&widget->p_dialog->lock);
}

- (void)syncTextField:(NSNotification *)notification
{
    id sender = [notification object];
    extension_widget_t *widget = nil;

    if ([sender respondsToSelector:@selector(widget)])
        widget = (extension_widget_t *)[sender widget];
    if (!widget)
        return;

    vlc_mutex_lock(&widget->p_dialog->lock);
    free(widget->psz_text);
    widget->psz_text = strdup([[sender stringValue] UTF8String]);
    vlc_mutex_unlock(&widget->p_dialog->lock);

    /* Tell the extension once the typing stops, not once per key: a
     * search box that refills a list of a thousand rows would crawl on
     * the machines this interface exists for. */
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(notifyTextChanged:)
                                               object:sender];
    [self performSelector:@selector(notifyTextChanged:)
               withObject:sender
               afterDelay:VLC_LEGACY_TEXT_DEBOUNCE];
}

- (void)notifyTextChanged:(id)sender
{
    extension_widget_t *widget = nil;
    if ([sender respondsToSelector:@selector(widget)])
        widget = (extension_widget_t *)[(id)sender widget];
    if (!widget)
        return;

    extension_WidgetSelectionChanged(widget->p_dialog, widget);
}

- (void)popUpSelectionChanged:(id)sender
{
    VLCLegacyDialogPopUpButton *popup = (VLCLegacyDialogPopUpButton *)sender;
    extension_widget_t *widget = [popup widget];
    struct extension_widget_value_t *value;
    int i = 0;

    if (!widget)
        return;
    for (value = widget->p_values; value != NULL; value = value->p_next, i++)
        value->b_selected = (i == [(NSPopUpButton *)sender indexOfSelectedItem]);

    /* a choice the user made is an event; refilling the menu is not */
    if (!popup->programmaticSelection)
        extension_WidgetSelectionChanged(widget->p_dialog, widget);
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    id sender = [notification object];
    if (![sender isKindOfClass:[VLCLegacyDialogList class]])
        return;

    VLCLegacyDialogList *list = sender;
    extension_widget_t *widget = [list widget];
    struct extension_widget_value_t *value;

    if (!widget)
        return;
    /* Map by value id, not by row index: sorting reorders the rows on
     * screen while p_values keeps the extension's order.
     * -selectedRowIndexes is 10.3; -isRowSelected: works everywhere */
    NSMutableSet *selectedIds = [NSMutableSet set];
    NSArray *rows = [list contentArray];
    unsigned i;
    for (i = 0; i < [rows count]; i++) {
        if ([list isRowSelected:(NSInteger)i])
            [selectedIds addObject:
                [[rows objectAtIndex:i] objectForKey:@"id"]];
    }
    for (value = widget->p_values; value != NULL; value = value->p_next)
        value->b_selected = [selectedIds containsObject:
            [NSNumber numberWithInt:value->i_id]] ? true : false;

    /* only report what the user did, not our own repopulation */
    if (![list programmaticSelection])
        extension_WidgetSelectionChanged(widget->p_dialog, widget);
}

- (void)tableView:(NSTableView *)tableView
    didClickTableColumn:(NSTableColumn *)tableColumn
{
    if (![tableView isKindOfClass:[VLCLegacyDialogList class]])
        return;
    VLCLegacyDialogList *list = (VLCLegacyDialogList *)tableView;
    if (![list headerView])
        return;

    int columnIndex = [[tableColumn identifier] intValue];
    BOOL ascending = ([list sortColumn] == columnIndex)
        ? ![list sortAscending] : YES;
    [list setProgrammaticSelection:YES];
    [list deselectAll:nil];
    [list sortByColumn:columnIndex ascending:ascending];
    [list setProgrammaticSelection:NO];
}

- (void)textFieldActivated:(id)sender
{
    extension_widget_t *widget = nil;
    if ([sender respondsToSelector:@selector(widget)])
        widget = (extension_widget_t *)[sender widget];
    if (!widget)
        return;

    /* the extension reads the value back with get_text(): make sure the
     * core carries what is on screen before the callback runs */
    vlc_mutex_lock(&widget->p_dialog->lock);
    free(widget->psz_text);
    widget->psz_text = strdup([[sender stringValue] UTF8String]);
    extension_WidgetClicked(widget->p_dialog, widget);
    vlc_mutex_unlock(&widget->p_dialog->lock);
}

- (void)listDoubleClicked:(id)sender
{
    if (![sender isKindOfClass:[VLCLegacyDialogList class]])
        return;
    VLCLegacyDialogList *list = sender;
    extension_widget_t *widget = [list widget];
    if (!widget || [list clickedRow] < 0)
        return;

    vlc_mutex_lock(&widget->p_dialog->lock);
    extension_WidgetClicked(widget->p_dialog, widget);
    vlc_mutex_unlock(&widget->p_dialog->lock);
}

- (BOOL)windowShouldClose:(id)sender
{
    extension_dialog_t *dialog = [(VLCLegacyDialogWindow *)sender dialog];
    if (dialog)
        extension_DialogClosed(dialog);
    return YES;
}

/*****************************************************************************
 * dialog lifecycle -- all of this runs on the main thread
 *****************************************************************************/

/* Note: the caller holds p_dialog->lock. */
- (void)updateWidgets:(extension_dialog_t *)p_dialog
{
    VLCLegacyDialogWindow *window =
        (VLCLegacyDialogWindow *)p_dialog->p_sys_intf;
    VLCLegacyDialogGridView *grid =
        (VLCLegacyDialogGridView *)[window contentView];
    extension_widget_t *widget;

    FOREACH_ARRAY(widget, p_dialog->widgets) {
        if (!widget)
            continue;   /* the array is sparse while a dialog is being built */

        NSView *control = (NSView *)widget->p_sys_intf;
        BOOL update = widget->b_update;

        if (widget->b_kill) {
            if (control) {
                [grid removeSubviewFromGrid:control];
                [[NSNotificationCenter defaultCenter] removeObserver:self
                                                                name:nil
                                                              object:control];
                [control release];
                widget->p_sys_intf = NULL;
            }
            continue;
        }

        if (!control) {
            control = [self createControlForWidget:widget];
            if (!control)
                continue;
            widget->p_sys_intf = control;   /* the grid holds it too; we own
                                             * the +1 from the constructor */
            update = YES;
        }

        if (update) {
            [self updateControl:control forWidget:widget];
            VLCLegacySetViewHidden(control, widget->b_hide ? YES : NO);

            int row = widget->i_row - 1;
            int col = widget->i_column - 1;
            if (row < 0) {
                /* unplaced widgets stack under the grid, as in the Qt one */
                row = 0;
                col = 0;
            }
            if (col < 0)
                col = 0;
            [grid setSubview:control
                       atRow:row
                      column:col
                     rowSpan:widget->i_vert_span
                     colSpan:widget->i_horiz_span];
            widget->b_update = false;
        }
    }
    FOREACH_END()

    [grid layoutGrid];
}

/* Width may be squeezed: columns give some of theirs, text wraps or is
 * clipped and the dialog stays usable. Height cannot -- a row that no
 * longer fits is simply not drawn -- so the natural height becomes the
 * floor, itself capped by the screen so that the window always fits. */
- (void)updateMinimumSizeOfWindow:(NSWindow *)window
                       forContent:(NSSize)content
{
    NSSize floorSize = NSMakeSize(VLC_LEGACY_MIN_DIALOG_W,
                                  content.height > VLC_LEGACY_MIN_DIALOG_H
                                      ? content.height
                                      : VLC_LEGACY_MIN_DIALOG_H);
    VLCLegacyClampToScreen(window, &floorSize);

    /* the minimum is a FRAME size: account for the title bar */
    [window setMinSize:[NSWindow frameRectForContentRect:
        NSMakeRect(0, 0, floorSize.width, floorSize.height)
                                              styleMask:
        [window styleMask]].size];
}

/* Note: the caller holds p_dialog->lock. */
- (VLCLegacyDialogWindow *)createExtensionDialog:(extension_dialog_t *)p_dialog
{
    VLCLegacyDialogWindow *window = [[VLCLegacyDialogWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 320, 200)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                          | NSResizableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setReleasedWhenClosed:NO];
    [window setDelegate:(id)self];
    [window setDialog:p_dialog];
    [window setTitle:p_dialog->psz_title
        ? [NSString stringWithUTF8String:p_dialog->psz_title] : @""];
    VLCLegacyDenyNativeFullscreen(window);

    VLCLegacyDialogGridView *grid = [[[VLCLegacyDialogGridView alloc]
        initWithFrame:NSMakeRect(0, 0, 320, 200)] autorelease];
    [grid setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
    [window setContentView:grid];

    p_dialog->p_sys_intf = window;   /* owned here, released on destroy */

    [self updateWidgets:p_dialog];

    NSSize wanted = [grid preferredSize];
    if (p_dialog->i_width > 0 && wanted.width < p_dialog->i_width)
        wanted.width = p_dialog->i_width;
    if (p_dialog->i_height > 0 && wanted.height < p_dialog->i_height)
        wanted.height = p_dialog->i_height;
    /* same ceiling the update path applies: one very long label must not
     * decide how wide the window opens */
    if (wanted.width > 720.f)
        wanted.width = 720.f;
    VLCLegacyClampToScreen(window, &wanted);
    /* the width is settled: ask again how tall the content is at THAT
     * width, since a narrower paragraph takes more lines */
    wanted.height = [grid preferredSizeForWidth:wanted.width].height;
    if (p_dialog->i_height > 0 && wanted.height < p_dialog->i_height)
        wanted.height = p_dialog->i_height;
    VLCLegacyClampToScreen(window, &wanted);
    [window setContentSize:wanted];
    [self updateMinimumSizeOfWindow:window forContent:wanted];
    [grid layoutGrid];

    return window;
}

/* Note: the caller holds p_dialog->lock. */
- (void)destroyExtensionDialog:(extension_dialog_t *)p_dialog
{
    VLCLegacyDialogWindow *window =
        (VLCLegacyDialogWindow *)p_dialog->p_sys_intf;
    extension_widget_t *widget;

    if (!window)
        return;

    /* a debounced text change must not fire at a widget that is going
     * away with this window */
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    FOREACH_ARRAY(widget, p_dialog->widgets) {
        if (widget && widget->p_sys_intf) {
            NSView *control = (NSView *)widget->p_sys_intf;
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:nil
                                                          object:control];
            [control release];
            widget->p_sys_intf = NULL;
        }
    }
    FOREACH_END()

    [window setDelegate:nil];
    [window close];
    [window release];
    p_dialog->p_sys_intf = NULL;
}

- (void)updateExtensionDialog:(NSValue *)value
{
    extension_dialog_t *p_dialog = [value pointerValue];
    VLCLegacyDialogWindow *window;

    if (!p_dialog)
        return;

    window = (VLCLegacyDialogWindow *)p_dialog->p_sys_intf;
    if (p_dialog->b_kill && !window) {
        /* an extension that failed to start still asks for its dialog */
        return;
    }

    vlc_mutex_lock(&p_dialog->lock);

    if (!p_dialog->b_kill && !window) {
        window = [self createExtensionDialog:p_dialog];
        if (!p_dialog->b_hide) {
            [window center];
            [window makeKeyAndOrderFront:self];
        } else
            [window orderOut:nil];
    } else if (!p_dialog->b_kill && window) {
        [self updateWidgets:p_dialog];
        /* The window was only sized at creation. A long status message or
         * a freshly filled list widens the natural size afterwards; grow,
         * or every track past the window edge is drawn clipped. */
        VLCLegacyDialogGridView *grid =
            (VLCLegacyDialogGridView *)[window contentView];
        NSSize wanted = [grid preferredSize];
        if (wanted.width > 720.f)
            wanted.width = 720.f;   /* absurd texts must not eat the screen */
        NSSize current = [[window contentView] frame].size;
        if (wanted.width < current.width)
            wanted.width = current.width;   /* the user may have widened it */
        VLCLegacyClampToScreen(window, &wanted);
        wanted.height = [grid preferredSizeForWidth:wanted.width].height;
        VLCLegacyClampToScreen(window, &wanted);
        if (wanted.width > current.width || wanted.height > current.height) {
            NSSize grown = NSMakeSize(
                wanted.width > current.width ? wanted.width : current.width,
                wanted.height > current.height ? wanted.height
                                               : current.height);
            [window setContentSize:grown];
        }
        /* widgets came or went: what the content needs vertically changed
         * with them */
        [self updateMinimumSizeOfWindow:window forContent:wanted];
        /* Measuring is only a measurement now, but the widgets that just
         * changed still need to be placed against the size we settled on. */
        [grid layoutGrid];
        if (p_dialog->psz_title) {
            NSString *title = [NSString stringWithUTF8String:
                                   p_dialog->psz_title];
            if (title && ![[window title] isEqualToString:title])
                [window setTitle:title];
        }
        if (!p_dialog->b_hide)
            [window makeKeyAndOrderFront:self];
        else
            [window orderOut:nil];
    } else if (p_dialog->b_kill) {
        [self destroyExtensionDialog:p_dialog];
    }

    vlc_cond_signal(&p_dialog->cond);
    vlc_mutex_unlock(&p_dialog->lock);
}

@end
