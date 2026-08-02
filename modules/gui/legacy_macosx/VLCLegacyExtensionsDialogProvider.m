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
}
- (extension_widget_t *)widget;
- (void)setWidget:(extension_widget_t *)aWidget;
- (void)setContentArray:(NSMutableArray *)array;
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

@implementation VLCLegacyDialogList
VLC_LEGACY_WIDGET_ACCESSORS

- (void)setContentArray:(NSMutableArray *)array
{
    [array retain];
    [contentArray release];
    contentArray = array;
}

- (void)dealloc
{
    [contentArray release];
    [super dealloc];
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
    return [[contentArray objectAtIndex:row] objectForKey:@"text"];
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
- (void)layoutGrid;
@end

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
        [(NSControl *)view sizeToFit];
        size = [view frame].size;
        /* sizeToFit collapses an empty entry field to nothing */
        if ([view isKindOfClass:[NSTextField class]]
         && [(NSTextField *)view isEditable] && size.width < 160)
            size.width = 160;
        /* a rounded bezel clips its last glyph at the fitted width */
        if ([view isKindOfClass:[NSButton class]])
            size.width += 16;
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

    /* a spanning occupant widens the last track it covers if it does not fit */
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
            int r;
            for (r = row; r < row + rowSpan && r < 64; r++)
                have += heights[r] + (r > row ? GRID_SPACING : 0.f);
            if (have < size.height && row + rowSpan - 1 < 64)
                heights[row + rowSpan - 1] += size.height - have;
        }
    }

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

- (NSSize)preferredSize
{
    float widths[64], heights[64];
    int cols = 0, rows = 0, i;
    float w = 0.f, h = 0.f;

    [self measureColumns:widths rows:heights columns:&cols rows:&rows];

    for (i = 0; i < cols && i < 64; i++)
        w += widths[i] + (i > 0 ? GRID_SPACING : 0.f);
    for (i = 0; i < rows && i < 64; i++)
        h += heights[i] + (i > 0 ? GRID_SPACING : 0.f);

    return NSMakeSize(w + 2 * GRID_MARGIN, h + 2 * GRID_MARGIN);
}

- (void)layoutGrid
{
    float widths[64], heights[64];
    int cols = 0, rows = 0, i;

    [self measureColumns:widths rows:heights columns:&cols rows:&rows];

    /* hand any width the window has beyond the natural one to the last column,
     * so that lists and text areas grow when the user resizes */
    float natural = 2 * GRID_MARGIN;
    for (i = 0; i < cols && i < 64; i++)
        natural += widths[i] + (i > 0 ? GRID_SPACING : 0.f);
    float extraW = [self bounds].size.width - natural;
    if (extraW > 0 && cols > 0 && cols <= 64)
        widths[cols - 1] += extraW;

    float naturalH = 2 * GRID_MARGIN;
    for (i = 0; i < rows && i < 64; i++)
        naturalH += heights[i] + (i > 0 ? GRID_SPACING : 0.f);
    float extraH = [self bounds].size.height - naturalH;
    if (extraH > 0 && rows > 0 && rows <= 64)
        heights[rows - 1] += extraH;

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

        NSTableColumn *column =
            [[[NSTableColumn alloc] initWithIdentifier:@"text"] autorelease];
        [column setEditable:NO];
        [list addTableColumn:column];
        [list setDataSource:(id)list];
        [list setDelegate:(id)self];

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
        NSPopUpButton *popup = (NSPopUpButton *)control;
        struct extension_widget_value_t *value;
        int selected = -1, i = 0;

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
        break;
    }

    case EXTENSION_WIDGET_LIST:
    {
        VLCLegacyDialogList *list =
            (VLCLegacyDialogList *)[(NSScrollView *)control documentView];
        NSMutableArray *array = [NSMutableArray array];
        struct extension_widget_value_t *value;

        for (value = widget->p_values; value != NULL; value = value->p_next) {
            [array addObject:[NSDictionary dictionaryWithObjectsAndKeys:
                [NSNumber numberWithInt:value->i_id], @"id",
                value->psz_text
                    ? [NSString stringWithUTF8String:value->psz_text] : @"",
                @"text", nil]];
        }
        [list setContentArray:array];
        [list reloadData];

        /* restore the selection the extension asked for */
        int row = 0;
        [list deselectAll:nil];
        for (value = widget->p_values; value != NULL;
             value = value->p_next, row++) {
            if (value->b_selected)
                [list selectRow:row byExtendingSelection:YES];
        }
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
}

- (void)popUpSelectionChanged:(id)sender
{
    extension_widget_t *widget = [(VLCLegacyDialogPopUpButton *)sender widget];
    struct extension_widget_value_t *value;
    int i = 0;

    if (!widget)
        return;
    for (value = widget->p_values; value != NULL; value = value->p_next, i++)
        value->b_selected = (i == [(NSPopUpButton *)sender indexOfSelectedItem]);
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification
{
    id sender = [notification object];
    if (![sender isKindOfClass:[VLCLegacyDialogList class]])
        return;

    VLCLegacyDialogList *list = sender;
    extension_widget_t *widget = [list widget];
    struct extension_widget_value_t *value;
    int i = 0;

    if (!widget)
        return;
    /* -selectedRowIndexes is 10.3; -isRowSelected: works everywhere */
    for (value = widget->p_values; value != NULL; value = value->p_next, i++)
        value->b_selected = [list isRowSelected:i] ? true : false;
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
    [window setContentSize:wanted];
    [window setMinSize:wanted];
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
