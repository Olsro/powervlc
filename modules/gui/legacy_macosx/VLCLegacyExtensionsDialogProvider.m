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
/* <objc/message.h> is a 10.5+ SDK split; the 10.4u SDK declares objc_msgSend
 * in <objc/objc-runtime.h> */
#if defined(__has_include)
# if __has_include(<objc/message.h>)
#  import <objc/message.h>
# else
#  import <objc/objc-runtime.h>
# endif
#else
# import <objc/objc-runtime.h>
#endif
#import "misc.h"

#include <unistd.h>
#include <stdio.h>
#include <vlc_dialog.h>
#include <vlc_extensions.h>

/* The modern provider renders EXTENSION_WIDGET_HTML in a WebView. WebKit is
 * not a dependency of this interface and is absent from a bare 10.2 install,
 * so rich text goes through -[NSAttributedString initWithHTML:] (10.0) into a
 * plain NSTextView instead. Simple markup -- what extensions actually emit --
 * renders; scripting does not, which is no loss in a dialog. */

/* Layout tracing, for when a dialog looks wrong on a machine that cannot be
 * debugged interactively: create /tmp/pvlc-grid-trace and every layout pass
 * writes what it measured and what it placed next to it. Checked once.
 * Declared here because the measuring pass, further down, uses it too. */
static FILE *VLCLegacyGridTrace(void);

#define GRID_MARGIN  12.f
#define GRID_SPACING 8.f

/* Cells are tab-separated; a cell may carry "display\037sortkey" so that a
 * column sorts on a real value (a timestamp) rather than on its label. */
#define VLC_DIALOG_SORTKEY_SEP @"\037"

/* Fallback height of a column header, for the systems that leave the view
 * flat rather than sizing it (see -installHeaderView:). The height AppKit
 * itself gives one on 10.2-10.5. */
#define VLC_LEGACY_HEADER_H 17.f

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
    NSArray *promisedNames;      /* file names promised by the drag under way */
    NSArray *promisedIds;        /* value ids of the rows being dragged */
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
- (void)installHeaderView:(NSTableHeaderView *)header;
- (int)sortColumn;
- (void)sortByColumn:(int)index ascending:(BOOL)ascending;
/* Show the first row, now and once more on the next turn of the run
 * loop. Call after filling the list. */
- (void)showTopOfList;
- (void)scrollToTopOfList;
- (BOOL)sortAscending;
- (void)resetSort;
@end

/* Carries its widget like the other controls do, so the layout can ask
 * where the picture should sit in the rows it covers. */
@interface VLCLegacyDialogImageView : NSImageView
{
    extension_widget_t *widget;
}
- (extension_widget_t *)widget;
- (void)setWidget:(extension_widget_t *)aWidget;
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

@implementation VLCLegacyDialogImageView
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

/* ⚠ Un `NSTextField` construit PAR PROGRAMME n'a pas les réglages qu'Interface
 * Builder pose sur les champs d'un nib : sa cellule ENROULE par défaut. Une URL
 * un peu longue s'y affichait donc sur plusieurs lignes, dont une seule tenait
 * dans la hauteur du champ — constaté sur la zone de copie du lien de la vue
 * « Invidious Video », reproduit sous Jaguar. Un champ de saisie est
 * mono-ligne par contrat : on le dit explicitement.
 * `wraps:NO` + `scrollable:YES` est l'idiome d'époque — le texte trop long
 * défile horizontalement au lieu de se replier. ⛔ Pas de
 * `setUsesSingleLineMode:`, qui est 10.6+ alors que cette interface descend
 * jusqu'à 10.2. */
static void VLCLegacyMakeSingleLine(NSTextField *field)
{
    NSCell *cell = [field cell];
    if (cell == nil)
        return;
    [cell setWraps:NO];
    [cell setScrollable:YES];
}

static NSString *VLCLegacyCell(id row, NSString *key, int column)
{
    NSArray *cells = [row objectForKey:key];
    if (column < 0 || (unsigned)column >= [cells count])
        return @"";
    return [cells objectAtIndex:column];
}

/* -localizedStandardCompare: only appears in the 10.6 SDK, and this interface
 * builds against 10.4. The -respondsToSelector: below is the runtime guard;
 * this is the compile-time one, without which the compiler assumes the method
 * returns id and rejects the function's NSComparisonResult. Declaration only:
 * the implementation is the system's, wherever it exists. */
@interface NSString (VLCLegacyStandardCompare)
- (NSComparisonResult)localizedStandardCompare:(NSString *)string;
@end

/* The order the rest of the system sorts names in -- the Finder's, with
 * accents and case where the reader expects them rather than where their
 * code points fall ("Éric" next to "Eric", not after "Zoe"). Pre-10.6
 * systems have no such comparison and keep the plain one. */
static NSComparisonResult VLCLegacyCompareLabels(NSString *a, NSString *b)
{
    if ([a respondsToSelector:@selector(localizedStandardCompare:)])
        return [a localizedStandardCompare:b];
    return [a compare:b options:NSCaseInsensitiveSearch | NSNumericSearch];
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
        result = VLCLegacyCompareLabels(VLCLegacyCell(a, @"cells", ctx->column),
                                        VLCLegacyCell(b, @"cells", ctx->column));
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

    /* Where the top is, is the clip view's business, and asking is the
     * only portable way to know it. The two systems do not agree: from
     * 10.10 the column headers sit INSIDE the clip view, over the top of
     * it, so its resting origin is one header above zero -- scrolling to
     * zero there tucks the first row under the headers, which is a list
     * of episodes that opens on number 2. On 10.2-10.5 the headers are
     * beside the clip view, in one of their own, and the top is plain
     * zero -- scrolling one header higher there leaves an empty strip
     * under the headers, which is the blank first line the podcast
     * results grew (measured on 10.2.8; it healed on any scroll, because
     * AppKit then clamped the origin to what it should have been).
     *
     * -constrainScrollPoint: answers with the nearest origin it will
     * actually hold, so an absurd value asks it for the end of its own
     * travel: -28 on 10.14, 0 on Jaguar, both measured. Deprecated since
     * 10.10 and still exact there; its replacement -constrainBoundsRect:
     * is 10.9 and does not exist on the systems this interface is for. */
    CGFloat far = [clip isFlipped] ? -100000.f : 100000.f;

    [clip scrollToPoint:[clip constrainScrollPoint:NSMakePoint(0.f, far)]];
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
    /* -momentumPhase is 10.7; this target is older, so it cannot be sent
     * literally -- a modern SDK rejects the unguarded call at compile time
     * even though -respondsToSelector: guards it at runtime, and @available
     * is not usable here. Typed objc_msgSend, as elsewhere in this
     * interface. */
    NSUInteger (*getMomentumPhase)(id, SEL) =
        (NSUInteger (*)(id, SEL))objc_msgSend;
    if ([event respondsToSelector:@selector(momentumPhase)]
     && getMomentumPhase(event, @selector(momentumPhase)) != 0
     && [NSDate timeIntervalSinceReferenceDate] - filledAt < 1.0)
        return;
    [super scrollWheel:event];
}

- (void)dealloc
{
    [contentArray release];
    [columnWeights release];
    [promisedNames release];
    [promisedIds release];
    [super dealloc];
}

/* How many rows are measured to decide the column widths, at most. */
#define VLC_LEGACY_WIDTH_SAMPLE 300

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

    /* Measuring every cell of a listing of several thousand rows is a
     * text layout per cell, redone on every refill -- with a search box
     * that refills as the user types, that is the whole cost of the
     * list on a slow machine. A spread-out sample gives the same
     * column widths in practice for a fraction of the work. */
    unsigned rowCount = (unsigned)[contentArray count];
    unsigned stride = (rowCount / VLC_LEGACY_WIDTH_SAMPLE) + 1;

    NSMutableArray *weights = [NSMutableArray array];
    unsigned i, n;
    for (i = 0; i < [columns count]; i++) {
        float widest = 0.f;
        if ([self headerView] != nil) {
            NSString *title =
                [[[columns objectAtIndex:i] headerCell] stringValue];
            widest = [title sizeWithAttributes:attributes].width;
        }
        for (n = 0; n < rowCount; n += stride) {
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

    /* Start from what each column actually needs. */
    float want[64];
    unsigned count = (unsigned)[columns count];
    if (count > 64)
        count = 64;
    for (i = 0; i < count; i++)
        want[i] = [[columnWeights objectAtIndex:i] floatValue];

    if (total <= available) {
        /* everything fits: give each column what it needs and hand the
         * slack to the longest one, rather than padding them all */
        want[widest] += (float)(available - total);
    } else {
        /* It does not fit, so something has to give -- and it should be
         * the longest column, not all of them equally. Shaving every
         * column in proportion truncated a date or a count (which need
         * a fixed, small width to mean anything) so that a column of
         * long titles could stay huge; those titles are read from their
         * beginning anyway. The shortfall is taken off the longest
         * column down to the next longest, then off both, and so on. */
        double deficit = total - available;
        unsigned guard;
        for (guard = 0; deficit > 0.5 && guard < 500; guard++) {
            unsigned iw = 0;
            float w1 = -1.f, w2 = -1.f;
            for (i = 0; i < count; i++) {
                if (want[i] > w1) { w2 = w1; w1 = want[i]; iw = i; }
                else if (want[i] > w2) { w2 = want[i]; }
            }
            float target = (w2 > 48.f) ? w2 : 48.f;
            if (w1 <= target + 0.5f) {
                /* every column is down to the same width: from here on
                 * they can only shrink together */
                float each = (float)(deficit / count);
                for (i = 0; i < count; i++) {
                    want[i] -= each;
                    if (want[i] < 48.f)
                        want[i] = 48.f;
                }
                break;
            }
            float take = (float)deficit;
            if (take > w1 - target)
                take = w1 - target;
            want[iw] -= take;
            deficit -= take;
        }
    }

    layingOut = YES;
    float used = 0.f;
    for (i = 0; i < count; i++) {
        float width = want[i];
        if (i + 1 == count && total > available)
            width = available - used;   /* no rounding crumbs on the right */
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
        [self installHeaderView:
            [[[NSTableHeaderView alloc] init] autorelease]];
    else if (!headers && [self headerView])
        [self installHeaderView:nil];
}

/* Puts the column titles where the scroll view will actually draw them.
 *
 * Two things go wrong below 10.4, and both end the same way -- a table
 * whose columns are named and whose header is nowhere to be seen (the
 * podcast results and the episode list, measured on 10.2.8; 10.7 and
 * later show it, which is why this only ever showed up on the old
 * machines):
 *
 *  - AppKit takes the height of the header from the header view itself,
 *    and -init gives that view no size at all. Later systems tile it into
 *    shape; these leave it flat, so there is nothing to draw.
 *  - the scroll view learns that its document view carries a header when
 *    the document view is SET, and it never looks again. The columns of
 *    an extension list are named well after that -- when the extension
 *    fills it -- so the header was installed into a scroll view that had
 *    already decided there was none.
 *
 * Both repairs are made only once the framework has plainly not made them
 * itself, so that nothing moves on the systems that get it right. */
- (void)installHeaderView:(NSTableHeaderView *)header
{
    NSScrollView *scroll = [self enclosingScrollView];

    [self setHeaderView:header];
    [scroll tile];

    if (header != nil) {
        if ([header frame].size.height <= 0.f)
            [header setFrame:NSMakeRect(0, 0, [self bounds].size.width,
                                        VLC_LEGACY_HEADER_H)];

        if ([header superview] == nil && scroll != nil
         && [scroll documentView] == self) {
            /* the scroll view owns its document view: putting it back is
             * what makes the header be picked up, and it must survive the
             * moment in between */
            [[self retain] autorelease];
            [scroll setDocumentView:nil];
            [scroll setDocumentView:self];
            [scroll tile];
        }
    }

    [scroll setNeedsDisplay:YES];
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

/* Right-click: the context menu the extension attached with set_menu.
 * The labels belong to the extension thread: copied under the dialog
 * lock, and nothing else happens while it is held. */
- (NSMenu *)menuForEvent:(NSEvent *)event
{
    if (!widget)
        return nil;
    NSInteger row = [self rowAtPoint:[self convertPoint:[event locationInWindow]
                                               fromView:nil]];
    if (row < 0)
        return nil;

    NSMutableArray *labels = [NSMutableArray array];
    vlc_mutex_lock(&widget->p_dialog->lock);
    int i;
    for (i = 0; i < widget->i_menu; i++) {
        NSString *label = widget->pp_menu[i]
            ? [NSString stringWithUTF8String:widget->pp_menu[i]] : nil;
        [labels addObject:label ? label : @""];
    }
    vlc_mutex_unlock(&widget->p_dialog->lock);
    if ([labels count] == 0)
        return nil;

    /* the menu acts on the row under the pointer: make it the selection
     * the extension will read. A user action, so the selection event
     * does go through -- the script's state follows the highlight. */
    if (![self isRowSelected:row])
        [self selectRow:row byExtendingSelection:NO];

    NSMenu *menu = [[[NSMenu alloc] initWithTitle:@""] autorelease];
    unsigned n;
    for (n = 0; n < [labels count]; n++) {
        NSMenuItem *item = [menu addItemWithTitle:[labels objectAtIndex:n]
                                           action:@selector(contextMenuAction:)
                                    keyEquivalent:@""];
        [item setTarget:self];
        [item setTag:(NSInteger)n + 1];   /* 1-based, like the Lua side */
    }
    return menu;
}

- (void)contextMenuAction:(id)sender
{
    if (!widget)
        return;
    widget->i_menu_choice = (int)[(NSMenuItem *)sender tag];
    vlc_mutex_lock(&widget->p_dialog->lock);
    extension_WidgetMenuSelected(widget->p_dialog, widget);
    vlc_mutex_unlock(&widget->p_dialog->lock);
}

/* Drag-out: rows whose value carries a drag name are promised to the
 * drop target as files of that name; the extension is then told where
 * they were dropped and creates them there. Both data-source methods:
 * AppKit prefers the indexed one from 10.4 on and only falls back to
 * the row-array one before that. */
- (BOOL)writeRowsCommon:(NSArray *)rowNumbers toPasteboard:(NSPasteboard *)pboard
{
    if (!widget || !widget->b_can_drag)
        return NO;

    /* A double-click that wobbles by a couple of pixels is still a
     * double-click: refusing the drag here lets it through to the
     * double action. Without this, opening a track by double-clicking
     * it could start a file promise instead, and land a download in
     * whatever folder the pointer happened to be over. */
    NSEvent *event = [NSApp currentEvent];
    if (event && [event clickCount] >= 2)
        return NO;

    NSMutableArray *names = [NSMutableArray array];
    NSMutableArray *ids = [NSMutableArray array];
    NSMutableArray *types = [NSMutableArray array];
    unsigned i;
    for (i = 0; i < [rowNumbers count]; i++) {
        unsigned row = [[rowNumbers objectAtIndex:i] unsignedIntValue];
        if (row >= [contentArray count])
            continue;
        NSDictionary *entry = [contentArray objectAtIndex:row];
        NSString *name = [entry objectForKey:@"dragname"];
        if ([name length] == 0)
            continue;
        [names addObject:name];
        [ids addObject:[entry objectForKey:@"id"]];
        NSString *type = [name pathExtension];
        [types addObject:type ? type : @""];
    }
    if ([names count] == 0)
        return NO;

    [names retain];
    [promisedNames release];
    promisedNames = names;
    [ids retain];
    [promisedIds release];
    promisedIds = ids;
    [pboard declareTypes:[NSArray arrayWithObject:NSFilesPromisePboardType]
                   owner:nil];
    [pboard setPropertyList:types forType:NSFilesPromisePboardType];
    return YES;
}

- (BOOL)tableView:(NSTableView *)tableView
        writeRows:(NSArray *)rows
     toPasteboard:(NSPasteboard *)pboard
{
    return [self writeRowsCommon:rows toPasteboard:pboard];
}

- (BOOL)tableView:(NSTableView *)tableView
        writeRowsWithIndexes:(NSIndexSet *)rowIndexes
        toPasteboard:(NSPasteboard *)pboard
{
    NSMutableArray *rows = [NSMutableArray array];
    NSUInteger i;
    for (i = [rowIndexes firstIndex]; i != NSNotFound;
         i = [rowIndexes indexGreaterThanIndex:i])
        [rows addObject:[NSNumber numberWithUnsignedInt:(unsigned)i]];
    return [self writeRowsCommon:rows toPasteboard:pboard];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)isLocal
{
    /* out of the window only: within the dialog a drop means nothing */
    return isLocal ? NSDragOperationNone : NSDragOperationCopy;
}

- (NSArray *)namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination
{
    NSArray *names = [promisedNames autorelease];
    NSArray *ids = [promisedIds autorelease];
    promisedNames = nil;
    promisedIds = nil;
    if (!widget || names == nil)
        return nil;

    /* the drop acts on the dragged rows, which may no longer be the
     * highlight: make them the selection the extension will read --
     * under the lock, the chain is the extension thread's */
    NSSet *idSet = [NSSet setWithArray:ids];
    struct extension_widget_value_t *value;
    vlc_mutex_lock(&widget->p_dialog->lock);
    for (value = widget->p_values; value != NULL; value = value->p_next)
        value->b_selected = [idSet containsObject:
            [NSNumber numberWithInt:value->i_id]] ? true : false;
    free(widget->psz_drop_dir);
    widget->psz_drop_dir = strdup([[dropDestination path] UTF8String]);
    vlc_mutex_unlock(&widget->p_dialog->lock);

    extension_WidgetDropDone(widget->p_dialog, widget);
    return names;
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

/* How wide a dialog may grow on its own, before the user resizes it.
 * A ceiling is wanted -- one very long single-line label should not open
 * a window across the whole desktop -- but a fixed one was cutting off
 * real content instead: a listing of half a dozen columns next to a
 * cover was clipped at the window edge, artwork and buttons with it.
 * The screen is the honest bound, so it is the one used. */
static CGFloat VLCLegacyMaxAutoWidth(NSWindow *window)
{
    NSScreen *screen = [window screen];
    if (!screen)
        screen = [NSScreen mainScreen];
    if (!screen)
        return 720.f;

    CGFloat widest = [screen visibleFrame].size.width * 0.9f;
    return (widest < 720.f) ? 720.f : widest;
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
         && [(NSTextField *)view isEditable]) {
            if (size.width < 220)
                size.width = 220;
            /* ⚠ …et depuis qu'ils sont mono-ligne (VLCLegacyMakeSingleLine),
             * ils en réclament BEAUCOUP trop : `-cellSize` sur une cellule qui
             * n'enroule pas rend la largeur du contenu ENTIER sur une ligne.
             * Une URL de lecture directe fait plusieurs milliers de pixels, et
             * c'est cette valeur qui servirait de largeur naturelle à la
             * colonne. Tant que la cellule enroulait, `-cellSize` répondait
             * pour la largeur qu'elle avait alors, donc bornée d'elle-même.
             * Un champ de saisie n'a pas besoin d'être aussi large que son
             * contenu : il défile. On plafonne la largeur NATURELLE ; la place
             * en trop lui revient de toute façon par `columnSlack`. */
            if (size.width > 420)
                size.width = 420;
        }
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

    if (widget != NULL && [view isKindOfClass:[NSImageView class]]
     && (widget->i_width > 0 || widget->i_height > 0)) {
        /* For a picture the hints are the size it is meant to be drawn
         * at, so they BOUND it, proportions kept. What a server sends
         * is not always what was asked for -- a cover can come back at
         * a thousand pixels square -- and a picture must not be what
         * decides how tall the window is. */
        float maxW = widget->i_width > 0 ? widget->i_width : size.width;
        float maxH = widget->i_height > 0 ? widget->i_height : size.height;
        if (size.width > maxW || size.height > maxH) {
            float scaleW = (size.width > 0) ? maxW / size.width : 1.f;
            float scaleH = (size.height > 0) ? maxH / size.height : 1.f;
            float scale = (scaleW < scaleH) ? scaleW : scaleH;
            size.width *= scale;
            size.height *= scale;
        }
    } else if (widget != NULL) {
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

        NSCell *labelCell = [(NSTextField *)view cell];
        NSSize wrapped = [labelCell cellSizeForBounds:
            NSMakeRect(0.f, 0.f, available, 100000.f)];

        /* SET the row, do not merely raise it. This runs once on the
         * natural widths and again on the final ones, and the two are not
         * the same width: a label measured against narrow natural columns
         * asks for two lines and keeps them for ever, because raising is
         * all the second pass could do. Measured on Tiger: the status line
         * of the Invidious dialog stayed 32 px tall where it draws 16,
         * which took 16 px away from the list above it and left a band of
         * white at the bottom of the window.
         *
         * Whatever else stands on the row still has its say -- the row is
         * the tallest of them and the label, at the width the label really
         * gets. */
        float others = 0.f;
        unsigned m;
        for (m = 0; m < [cells count]; m++) {
            NSMutableDictionary *other = [cells objectAtIndex:m];
            NSView *otherView = [other objectForKey:@"view"];
            if (otherView == view)
                continue;
            if ([[other objectForKey:@"row"] intValue] != row
             || [[other objectForKey:@"rowSpan"] intValue] != 1)
                continue;
            extension_widget_t *ow = [self widgetOfView:otherView];
            if (ow && ow->b_hide)
                continue;
            NSSize size = VLCLegacyPreferredSize(otherView, ow);
            if (size.height > others)
                others = size.height;
        }

        heights[row] = wrapped.height > others ? wrapped.height : others;
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

        /* A wrapping label must be measured on ONE line here: -cellSize on
         * a wrapping cell answers for the width the cell happens to have at
         * that moment, which is not the width it is about to be given, and
         * a one-line message came out two lines tall. Measured on Tiger: an
         * empty message row 16 px, the same row 32 px the moment a line of
         * text arrived -- so the list above it lost 16 px and everything
         * under it climbed, leaving a band of white at the bottom of the
         * window. growRows: below raises the row again, at the width the
         * label really gets, whenever the text does need several lines. */
        if (!(w && w->b_hide)
         && [view isKindOfClass:[NSTextField class]]
         && ![(NSTextField *)view isEditable]
         && [[(NSTextField *)view cell] wraps]) {
            NSSize oneLine = [[(NSTextField *)view cell] cellSizeForBounds:
                NSMakeRect(0.f, 0.f, 100000.f, 100000.f)];
            if (oneLine.height > 0.f)
                size.height = oneLine.height;
        }

        if (VLCLegacyGridTrace() && [view isKindOfClass:[NSTextField class]]
         && ![(NSTextField *)view isEditable]) {
            NSCell *lc = [(NSTextField *)view cell];
            NSSize cs = [lc cellSize];
            NSSize huge = [lc cellSizeForBounds:
                NSMakeRect(0.f, 0.f, 100000.f, 100000.f)];
            NSSize atFrame = [lc cellSizeForBounds:
                NSMakeRect(0.f, 0.f, [view frame].size.width, 100000.f)];
            fprintf(VLCLegacyGridTrace(),
                    "    label r%d wraps %d frameW %.0f  cellSize %.0fx%.0f"
                    "  huge %.0f  atFrame %.0f  font %.1f  len %u  \"%.40s\"\n",
                    row, [lc wraps] ? 1 : 0, [view frame].size.width,
                    cs.width, cs.height, huge.height, atFrame.height,
                    [[lc font] pointSize],
                    (unsigned)[[lc stringValue] length],
                    [[lc stringValue] UTF8String]);
        }

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
            /* A drop-down is an NSButton too, and it truncates its title
             * perfectly well -- which a push button does not, hence this
             * floor. Counting it made a whole column un-shrinkable
             * because of ONE long entry: an audio track named after the
             * film ("... DTS@768 Kbps 5.1 FRE (VFF) - French - Par
             * défaut") asked for 572 px, its column then gave nothing,
             * and the shortfall came out of the last column -- the
             * artwork, drawn 130 px past the right edge of the window. */
            if ([view isKindOfClass:[NSPopUpButton class]])
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

        float missing = -extraW;
        float shrinkable = 0.f;
        for (i = 0; i < cols && i < 64; i++)
            if (!rigid[i] && widths[i] > floors[i])
                shrinkable += widths[i] - floors[i];
        if (shrinkable > 0.f) {
            float take = (missing > shrinkable) ? shrinkable : missing;
            for (i = 0; i < cols && i < 64; i++) {
                if (rigid[i] || widths[i] <= floors[i])
                    continue;
                widths[i] -= take * (widths[i] - floors[i]) / shrinkable;
            }
            missing -= take;
        }

        /* Everything that could give has given and it still does not fit.
         * What is left over is drawn past the right edge of the window,
         * and the picture column being the last one, the picture is what
         * vanishes -- so let the pictures shrink too, as a last resort. A
         * cover shown a little smaller reads far better than one cut in
         * half by the window frame. */
        if (missing > 0.f) {
            float room = 0.f;
            for (i = 0; i < cols && i < 64; i++)
                if (rigid[i] && widths[i] > VLC_LEGACY_MIN_COLUMN_W)
                    room += widths[i] - VLC_LEGACY_MIN_COLUMN_W;
            if (room > 0.f) {
                float take = (missing > room) ? room : missing;
                for (i = 0; i < cols && i < 64; i++) {
                    if (!rigid[i] || widths[i] <= VLC_LEGACY_MIN_COLUMN_W)
                        continue;
                    widths[i] -= take
                        * (widths[i] - VLC_LEGACY_MIN_COLUMN_W) / room;
                }
            }
        }
    }

}

static FILE *VLCLegacyGridTrace(void)
{
    static FILE *trace = NULL;
    static BOOL looked = NO;

    if (!looked) {
        looked = YES;
        if (access("/tmp/pvlc-grid-trace", F_OK) == 0) {
            trace = fopen("/tmp/pvlc-grid-trace.log", "a");
            if (trace)
                setvbuf(trace, NULL, _IOLBF, 0);
        }
    }
    return trace;
}

- (void)layoutGrid
{
    float widths[64], heights[64];
    int cols = 0, rows = 0, i;
    FILE *trace = VLCLegacyGridTrace();

    [self measureColumns:widths rows:heights columns:&cols rows:&rows];

    if (trace) {
        fprintf(trace, "\n--- layout: bounds %.0fx%.0f, %d rows, %d cols\n",
                [self bounds].size.width, [self bounds].size.height,
                rows, cols);
        for (i = 0; i < rows && i < 64; i++)
            fprintf(trace, "    row %d measured %.1f\n", i, heights[i]);
    }

    [self adjustWidths:widths columns:cols toWidth:[self bounds].size.width];

    /* The columns have their final width now, which is not the width the
     * first pass measured against: a paragraph squeezed into a narrower
     * column needs more lines, and it was those lines that got cut off. */
    [self growRows:heights forWrappingLabelsWithWidths:widths];

    float naturalH = 2 * GRID_MARGIN;
    for (i = 0; i < rows && i < 64; i++)
        naturalH += heights[i] + (i > 0 ? GRID_SPACING : 0.f);
    float extraH = [self bounds].size.height - naturalH;
    if (trace)
        fprintf(trace, "    naturalH %.1f, extraH %.1f\n", naturalH, extraH);
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
            /* Top of the block by default, level with the title it
             * illustrates -- centred, it drifted away from the text it
             * belongs to as sections were unfolded below. A script whose
             * picture sits beside a list asks for the middle instead. */
            if (want.height > 0.f && want.height < h) {
                extension_widget_t *w = [self widgetOfView:view];
                if (w && w->b_image_centered)
                    y += (h - want.height) / 2;
                h = want.height;
            }
        }

        [view setFrame:NSMakeRect(x, y, w, h)];
        /* A list is a table inside a scroll view, and a clip view only
         * ever GROWS its document view to fill itself -- it never shrinks
         * it. So narrowing the box around a list does not reach the table
         * at all: -setFrameSize: is not called on it, the column widths
         * worked out for the wider box stand, and the last column ends up
         * outside the frame. That is what cut the "Durée" column off the
         * moment the cover art claimed a column of its own. */
        if ([view isKindOfClass:[NSScrollView class]]) {
            NSView *doc = [(NSScrollView *)view documentView];
            if ([doc isKindOfClass:[VLCLegacyDialogList class]])
                [(VLCLegacyDialogList *)doc layoutColumns];
        }
        if (trace)
            fprintf(trace, "    %-22s r%d c%d span %dx%d -> "
                           "x %.0f y %.0f w %.0f h %.0f\n",
                    [NSStringFromClass([view class]) UTF8String],
                    row, col, rowSpan, colSpan, x, y, w, h);
    }

    /* Nothing paints this view's background -- it is a plain NSView with no
     * drawRect: -- so the pixels a control leaves behind when the layout
     * shifts stay on screen. That is what made the dialog look as though
     * every widget had been drawn twice the moment the instance list filled
     * up: the list grew, every row below it moved, and the old rendering was
     * still there underneath. Ask for the whole thing to be repainted; the
     * window background is redrawn under a non-opaque view, which is exactly
     * what erases them. */
    [self setNeedsDisplay:YES];
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

/* Where each extension's window was left standing.
 *
 * A script that shows another screen does it by deleting its dialog and
 * building the next one, so what the user sees as one window is really
 * a succession of them -- and every new one was being centred. Moving
 * the window then meant nothing: the next view snapped it back. The
 * corner it was left at is remembered per extension and given to its
 * next window, which is what "the window stays put" means. */
static NSMutableDictionary *VLCLegacyDialogCorners(void)
{
    static NSMutableDictionary *corners = nil;
    if (!corners)
        corners = [[NSMutableDictionary alloc] init];
    return corners;
}

static id VLCLegacyCornerKey(extension_dialog_t *p_dialog)
{
    /* the extension owning the dialog, not the dialog itself: the whole
     * point is to carry across a dialog being replaced */
    return [NSNumber numberWithUnsignedLong:(unsigned long)p_dialog->p_sys];
}

static void extensionDialogCallback(extension_dialog_t *p_ext_dialog,
                                    void *p_data)
{
    VLCLegacyExtensionsDialogProvider *provider =
        (VLCLegacyExtensionsDialogProvider *)p_data;
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    /* The default run loop mode, and no other. Asked to perform without
     * naming modes, Foundation queues the message in the COMMON modes --
     * which AppKit has added event tracking to, so an update landed in
     * the middle of a mouse-down: the widgets were torn down and rebuilt
     * while -[NSWindow sendEvent:] was still working through that very
     * click, and the click finished against a button cell that had been
     * freed under it (crash in +[NSButtonCell _finishHitTracking:],
     * measured on 10.2 while a slow login was answering). Naming the
     * default mode holds the update until the click is over. The
     * extension thread waits those few milliseconds longer; it holds no
     * lock of ours while it does, so nothing else is held up. */
    if (provider)
        [provider performSelectorOnMainThread:@selector(updateExtensionDialog:)
                                   withObject:[NSValue valueWithPointer:
                                                   p_ext_dialog]
                                waitUntilDone:YES
                                        modes:[NSArray arrayWithObject:
                                                   NSDefaultRunLoopMode]];
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
        /* Selecting the text of a label hands it to the field editor,
         * and that one throws the attributes away unless it is told the
         * content is rich: one click on a bold title left it plain for
         * good, focused or not. */
        [field setAllowsEditingTextAttributes:YES];
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
        VLCLegacyMakeSingleLine(field);
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
        VLCLegacyMakeSingleLine(field);
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
        VLCLegacyDialogImageView *imageView =
            [[VLCLegacyDialogImageView alloc] init];
        [imageView setWidget:widget];
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
    if (!rich)
        return [[[NSAttributedString alloc] initWithString:string] autorelease];

    /* The HTML importer closes its last paragraph with a line break, which
     * is an empty line under every label that uses markup -- and a row
     * measured for two lines where one is drawn. */
    NSMutableAttributedString *trimmed = [[rich mutableCopy] autorelease];
    while ([trimmed length] > 0) {
        unichar last = [[trimmed string] characterAtIndex:[trimmed length] - 1];
        if (last != '\n' && last != '\r' && last != 0x2028 && last != 0x2029)
            break;
        [trimmed deleteCharactersInRange:NSMakeRange([trimmed length] - 1, 1)];
    }
    return trimmed;
}

/* Names a font for every character that does not already carry one.
 *
 * A label is drawn twice by two different pieces of AppKit: by its own
 * cell until it is clicked, and by the window's field editor from then on
 * -- clicking a label selects its text, which is the point of making them
 * selectable. The cell falls back to the CONTROL's font where the string
 * names none; the field editor falls back to its own, which is smaller.
 * So a plain label shrank the moment it was clicked and stayed shrunk
 * (measured on 10.2.8, on the podcast description and the two headings
 * above it). Saying which font the text is in leaves both with nothing to
 * guess at. Text that already names its fonts -- anything that came
 * through the HTML importer, the bold headings among it -- is untouched. */
static NSAttributedString *VLCLegacyWithBaseFont(NSAttributedString *text,
                                                 NSFont *font)
{
    NSMutableAttributedString *out = nil;
    NSUInteger i = 0, length = [text length];

    if (font == nil)
        return text;

    while (i < length) {
        NSRange range;
        id present = [text attribute:NSFontAttributeName atIndex:i
                      effectiveRange:&range];

        if (range.length == 0)
            break;              /* never spin, whatever AppKit answers */
        if (present == nil) {
            if (out == nil)
                out = [[text mutableCopy] autorelease];
            [out addAttribute:NSFontAttributeName value:font range:range];
        }
        i = NSMaxRange(range);
    }

    return out != nil ? out : text;
}

- (void)updateControl:(NSView *)control forWidget:(extension_widget_t *)widget
{
    switch (widget->type) {
    case EXTENSION_WIDGET_LABEL:
        [(NSTextField *)control setAttributedStringValue:
            VLCLegacyWithBaseFont(VLCLegacyAttributedText(widget->psz_text),
                                  [(NSTextField *)control font])];
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
            NSMutableDictionary *entry =
                [NSMutableDictionary dictionaryWithObjectsAndKeys:
                    [NSNumber numberWithInt:value->i_id], @"id",
                    text, @"text",
                    cells, @"cells",
                    sortKeys, @"sortKeys",
                    nil];
            /* rows with a promised file name may be dragged out */
            if (value->psz_dragname) {
                NSString *dragname =
                    [NSString stringWithUTF8String:value->psz_dragname];
                if (dragname)
                    [entry setObject:dragname forKey:@"dragname"];
            }
            [array addObject:entry];
        }
        [list setProgrammaticSelection:YES];
        [list setContentArray:array];
        [list resetSort];   /* fresh content, extension's order */
        /* ...unless the script asked for a column order, in which case
         * it is sorted here, by the very comparison a click on that
         * header uses -- so that both give the same thing */
        if (widget->i_sort_column > 0)
            [list sortByColumn:widget->i_sort_column - 1
                     ascending:widget->b_sort_ascending];
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
    else {
        widget->b_checked = [(NSButton *)sender state] == NSOnState;
        /* a toggle is a click too: scripts with an on_toggle callback
         * react on the spot, scripts without one never see the event */
        extension_WidgetClicked(widget->p_dialog, widget);
    }
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
    /* The value chain belongs to the extension thread, which frees it
     * whole on widget:clear(): walking it unlocked is a use-after-free
     * whenever a script refills a list while the user is clicking.
     * While the interface repopulates the menu, though, the lock is
     * already held by this thread and taking it again would freeze. */
    BOOL locked = NO;
    if (!popup->programmaticSelection) {
        vlc_mutex_lock(&widget->p_dialog->lock);
        locked = YES;
    }
    for (value = widget->p_values; value != NULL; value = value->p_next, i++)
        value->b_selected = (i == [(NSPopUpButton *)sender indexOfSelectedItem]);
    if (locked)
        vlc_mutex_unlock(&widget->p_dialog->lock);

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
    /* Our own repopulation lands here too, and must be left alone
     * entirely. It runs from updateExtensionDialog, which already holds
     * the dialog lock on this very thread: taking it again below froze
     * the whole application (the mutex is not recursive). Its
     * -deselectAll: also runs *before* the loop that restores the
     * selection the extension asked for, so writing the model from the
     * table here would wipe that selection. Same for a header-click
     * sort, which clears the model at the sort site instead. */
    if ([list programmaticSelection])
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
    /* Under the lock: the extension thread frees this whole chain on
     * widget:clear(), and a script that refills a list as the user
     * types was writing b_selected into freed memory (a crash on a
     * plain click, reached from -[NSTableView mouseDown:]). */
    vlc_mutex_lock(&widget->p_dialog->lock);
    for (value = widget->p_values; value != NULL; value = value->p_next)
        value->b_selected = [selectedIds containsObject:
            [NSNumber numberWithInt:value->i_id]] ? true : false;
    vlc_mutex_unlock(&widget->p_dialog->lock);

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

    /* The rows moved, so nothing is selected any more: say so in the
     * model too, or the extension would act on rows the user can no
     * longer see highlighted. (The selection handler stays out of the
     * way while we sort, see -tableViewSelectionDidChange:.) */
    extension_widget_t *widget = [list widget];
    if (widget) {
        struct extension_widget_value_t *value;
        vlc_mutex_lock(&widget->p_dialog->lock);
        for (value = widget->p_values; value != NULL; value = value->p_next)
            value->b_selected = false;
        vlc_mutex_unlock(&widget->p_dialog->lock);
    }
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

/* Lets go of a control the extension has withdrawn.
 *
 * Never a plain -release. A label is selectable, so clicking one hands it
 * the window's field editor and the window goes on pointing at it; and
 * AppKit holds bare pointers to the controls of the event it is in the
 * middle of. Handing the field editor back first, then autoreleasing,
 * leaves both of those pointing at something that is still there for the
 * rest of this pass through the run loop. */
static void VLCLegacyDropControl(NSView *control)
{
    NSWindow *window = [control window];

    if (window != nil)
        [window endEditingFor:control];
    VLCLegacyForgetHiddenView(control);
    [control autorelease];
}

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
                VLCLegacyDropControl(control);
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
    CGFloat widest = VLCLegacyMaxAutoWidth(window);
    if (wanted.width > widest)
        wanted.width = widest;
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

    /* Remember the corner before it goes: the next screen this
     * extension shows is a brand new window, and it should come up
     * where the user left this one. */
    if ([window isVisible]) {
        NSRect frame = [window frame];
        [VLCLegacyDialogCorners()
            setObject:[NSValue valueWithPoint:
                          NSMakePoint(frame.origin.x, NSMaxY(frame))]
               forKey:VLCLegacyCornerKey(p_dialog)];
    }

    /* a debounced text change must not fire at a widget that is going
     * away with this window */
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    FOREACH_ARRAY(widget, p_dialog->widgets) {
        if (widget && widget->p_sys_intf) {
            NSView *control = (NSView *)widget->p_sys_intf;
            [[NSNotificationCenter defaultCenter] removeObserver:self
                                                            name:nil
                                                          object:control];
            VLCLegacyDropControl(control);
            widget->p_sys_intf = NULL;
        }
    }
    FOREACH_END()

    [window setDelegate:nil];
    [window close];
    /* deferred for the same reason the controls are: the window is the
     * object AppKit is dispatching the current event through */
    [window autorelease];
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
            /* Where this extension's last window stood, if it had one:
             * the top-left corner, since the window under it may not be
             * the same height and that corner is the one a reader
             * thinks of as "where the window is". */
            NSValue *corner = [VLCLegacyDialogCorners()
                                  objectForKey:VLCLegacyCornerKey(p_dialog)];
            if (corner) {
                NSPoint topLeft = [corner pointValue];
                NSRect frame = [window frame];
                [window setFrameOrigin:
                    NSMakePoint(topLeft.x, topLeft.y - frame.size.height)];
                /* a screen that changed, or a window that grew, must not
                 * put it out of reach */
                if (![[NSScreen screens] count]
                 || !NSIntersectsRect([window frame],
                                      [[window screen] ? [window screen]
                                        : [NSScreen mainScreen] visibleFrame]))
                    [window center];
            } else
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
        CGFloat widest = VLCLegacyMaxAutoWidth(window);
        if (wanted.width > widest)
            wanted.width = widest;  /* absurd texts must not eat the screen */
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
