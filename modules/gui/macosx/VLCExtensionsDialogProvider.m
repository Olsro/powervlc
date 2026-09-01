/*****************************************************************************
 * VLCExtensionsDialogProvider.m: Mac OS X Extensions Dialogs
 *****************************************************************************
 * Copyright (C) 2010-2015 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Pierre d'Herbemont <pdherbemont # videolan org>
 *          Brendon Justin <brendonjustin@gmail.com>,
 *          Derk-Jan Hartman <hartman@videolan dot org>,
 *          Felix Paul Kühne <fkuehne@videolan dot org>
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

#import "VLCExtensionsDialogProvider.h"

#import "VLCMain.h"
#import "VLCExtensionsManager.h"
#import "misc.h"
#import "VLCUIWidgets.h"

#import <WebKit/WebKit.h>
#import <stdlib.h>

/* How long typing must pause before the extension hears about it, in
 * seconds. Long enough that a burst of keys is one event, short enough
 * to feel immediate. */
#define VLC_EXTENSION_TEXT_DEBOUNCE 0.3

/* A synchronous performSelectorOnMainThread deadlocks during application
 * teardown: the main thread joins the Lua extension worker while that worker
 * is waiting for the main thread to repaint its dialog. Keep the dialog
 * descriptor alive through a small cancellable request instead. Ordinary
 * updates still wait for AppKit (preserving widget lifetime); an update that
 * has not started after two seconds is cancelled safely. */
typedef struct
{
    vlc_mutex_t lock;
    vlc_cond_t cond;
    extension_dialog_t *dialog;
    unsigned refs;
    bool running;
    bool done;
    bool cancelled;
} VLCExtensionDialogRequest;

static VLCExtensionDialogRequest *VLCDialogRequestCreate(extension_dialog_t *dialog)
{
    VLCExtensionDialogRequest *request = calloc(1, sizeof(*request));
    if (!request)
        return NULL;
    vlc_mutex_init(&request->lock);
    vlc_cond_init(&request->cond);
    request->dialog = dialog;
    request->refs = 2; /* extension worker + queued main-thread selector */
    return request;
}

static void VLCDialogRequestRelease(VLCExtensionDialogRequest *request)
{
    bool destroy;
    vlc_mutex_lock(&request->lock);
    destroy = --request->refs == 0;
    vlc_mutex_unlock(&request->lock);
    if (destroy) {
        vlc_cond_destroy(&request->cond);
        vlc_mutex_destroy(&request->lock);
        free(request);
    }
}

/*****************************************************************************
 * VLCExtensionsDialogProvider implementation
 *****************************************************************************/

static void extensionDialogCallback(extension_dialog_t *p_ext_dialog,
                                    void *p_data);

static NSView *createControlFromWidget(extension_widget_t *widget, id self)
{
    @autoreleasepool {
        assert(!widget->p_sys_intf);
        switch (widget->type) {
            case EXTENSION_WIDGET_HTML:
            {
                WebView *webView = [[WebView alloc] initWithFrame:NSMakeRect (0,0,1,1)];
                /* An explicit height makes a rich-text area a compact,
                 * scrollable excerpt (user biographies, notes) instead of
                 * competing equally with the main results list. */
                if (widget->i_width > 0 || widget->i_height > 0) {
                    NSSize size = NSMakeSize(widget->i_width > 0 ? widget->i_width : 1,
                                             widget->i_height > 0 ? widget->i_height : 1);
                    [webView setFrameSize:size];
                }
                [webView setAutoresizingMask:widget->i_height > 0
                    ? NSViewWidthSizable
                    : (NSViewHeightSizable | NSViewWidthSizable)];
                [webView setDrawsBackground:NO];
                return webView;
            }
            case EXTENSION_WIDGET_LABEL:
            {
                VLCDialogLabel *field = [[VLCDialogLabel alloc] init];
                [field setEditable:NO];
                [field setBordered:NO];
                [field setDrawsBackground:NO];
                [field setAllowsEditingTextAttributes:YES];
                [field setSelectable:YES];
                [field setFont:[NSFont systemFontOfSize:0]];
                [[field cell] setControlSize:NSRegularControlSize];
                /* a label whose text carries newlines is a paragraph: draw
                 * every line of it, at the font's own leading rather than
                 * a grid row apart */
                [[field cell] setWraps:YES];
                [field setAutoresizingMask:NSViewNotSizable];
                return field;
            }
            case EXTENSION_WIDGET_TEXT_FIELD:
            {
                VLCDialogTextField *field = [[VLCDialogTextField alloc] init];
                [field setWidget:widget];
                [field setAutoresizingMask:NSViewWidthSizable];
                [field setFont:[NSFont systemFontOfSize:0]];
                [[field cell] setControlSize:NSRegularControlSize];
                /* Un champ de saisie est mono-ligne par contrat. Sans le dire,
                 * la cellule d'un NSTextField construit par programme ENROULE,
                 * et une URL un peu longue — la zone de copie du lien des
                 * extensions Invidious et Jellyfin — s'affiche sur plusieurs
                 * lignes dont une seule tient dans la hauteur du champ.
                 * ⛔ Pas `setUsesSingleLineMode:` : elle est **10.10+** alors
                 * que cette tranche vise 10.7, et `-Wunguarded-availability`
                 * casse le build arm64. `wraps:NO` + `scrollable:YES` existe
                 * depuis toujours, fait le même travail ici (le texte défile
                 * au lieu de se replier) et c'est déjà l'idiome du
                 * fournisseur legacy. */
                [[field cell] setWraps:NO];
                [[field cell] setScrollable:YES];
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncTextField:)  name:NSControlTextDidChangeNotification object:field];
                /* Enter validates the field, like any search box */
                [field setTarget:self];
                [field setAction:@selector(textFieldActivated:)];
                return field;
            }
            case EXTENSION_WIDGET_PASSWORD:
            {
                VLCDialogSecureTextField *field = [[VLCDialogSecureTextField alloc] init];
                [field setWidget:widget];
                [field setAutoresizingMask:NSViewWidthSizable];
                [field setFont:[NSFont systemFontOfSize:0]];
                [[field cell] setControlSize:NSRegularControlSize];
                [[field cell] setWraps:NO];          /* cf. le champ texte */
                [[field cell] setScrollable:YES];
                [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncTextField:)  name:NSControlTextDidChangeNotification object:field];
                [field setTarget:self];
                [field setAction:@selector(textFieldActivated:)];
                return field;
            }

            case EXTENSION_WIDGET_CHECK_BOX:
            {
                VLCDialogButton *button = [[VLCDialogButton alloc] init];
                [button setButtonType:NSSwitchButton];
                [button setWidget:widget];
                [button setAction:@selector(triggerClick:)];
                [button setTarget:self];
                [button setFont:[NSFont systemFontOfSize:0.0]];
                [[button cell] setControlSize:NSRegularControlSize];
                [button setAutoresizingMask:NSViewWidthSizable];
                return button;
            }
            case EXTENSION_WIDGET_BUTTON:
            {
                VLCDialogButton *button = [[VLCDialogButton alloc] init];
                [button setBezelStyle:NSRoundedBezelStyle];
                [button setWidget:widget];
                [button setAction:@selector(triggerClick:)];
                [button setTarget:self];
                [button setFont:[NSFont systemFontOfSize:0.0]];
                [[button cell] setControlSize:NSRegularControlSize];
                [button setAutoresizingMask:NSViewNotSizable];
                return button;
            }
            case EXTENSION_WIDGET_DROPDOWN:
            {
                VLCDialogPopUpButton *popup = [[VLCDialogPopUpButton alloc] init];
                [popup setAction:@selector(popUpSelectionChanged:)];
                [popup setTarget:self];
                [popup setWidget:widget];
                return popup;
            }
            case EXTENSION_WIDGET_LIST:
            {
                NSScrollView *scrollView = [[NSScrollView alloc] init];
                [scrollView setHasVerticalScroller:YES];
                VLCDialogList *list = [[VLCDialogList alloc] init];
                [list setUsesAlternatingRowBackgroundColors:YES];
                [list setHeaderView:nil];
                [list setAllowsMultipleSelection:YES];
                [scrollView setDocumentView:list];
                [scrollView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];

                NSTableColumn *column = [[NSTableColumn alloc] init];
                /* editable cells swallow double-clicks (they start editing
                 * instead of sending the double action) */
                [column setEditable:NO];
                [list addTableColumn:column];
                [list setDataSource:list];
                [list setDelegate:self];
                [list setWidget:widget];
                [list setSortColumn:-1];
                [list setTarget:self];
                [list setDoubleAction:@selector(listDoubleClicked:)];
                return scrollView;
            }
            case EXTENSION_WIDGET_IMAGE:
            {
                VLCDialogImageView *imageView = [[VLCDialogImageView alloc] init];
                [imageView setWidget:widget];
                [imageView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
                [imageView setImageFrameStyle:NSImageFramePhoto];
                [imageView setImageScaling:NSImageScaleProportionallyUpOrDown];
                return imageView;
            }
            case EXTENSION_WIDGET_SPIN_ICON:
            {
                NSProgressIndicator *spinner = [[NSProgressIndicator alloc] init];
                [spinner setUsesThreadedAnimation:YES];
                [spinner setStyle:NSProgressIndicatorSpinningStyle];
                [spinner setDisplayedWhenStopped:YES];
                [spinner startAnimation:self];
                return spinner;
            }
            default:
                msg_Err(getIntf(), "Unhandled Widget type %i", widget->type);
                return nil;
        }
    }
}

static void updateControlFromWidget(NSView *control, extension_widget_t *widget, id self)
{
    @autoreleasepool {
        NSString * const defaultStyleCSS = @"<style>*{ font-family: \
            -apple-system-body, -apple-system, \
            HelveticaNeue, Arial, sans-serif; }</style>";
        switch (widget->type) {
            case EXTENSION_WIDGET_HTML:
            {
                // Get the web view
                assert([control isKindOfClass:[WebView class]]);
                WebView *webView = (WebView *)control;
                NSString *string = [defaultStyleCSS stringByAppendingString:toNSStr(widget->psz_text)];
                [[webView mainFrame] loadHTMLString:string baseURL:[NSURL URLWithString:@""]];
                [webView setNeedsDisplay:YES];
                break;
            }
            case EXTENSION_WIDGET_LABEL:
            case EXTENSION_WIDGET_PASSWORD:
            case EXTENSION_WIDGET_TEXT_FIELD:
            {
                if (!widget->psz_text)
                    break;
                assert([control isKindOfClass:[NSControl class]]);
                NSControl *field = (NSControl *)control;
                NSString *text = toNSStr(widget->psz_text);

                /* Only markup goes through the HTML parser: it is a WebKit
                 * round-trip per widget, and its Latin-1 input encoding
                 * dropped every character outside that set -- an em dash or
                 * a curly quote in a label emptied the whole label.
                 */
                if ([text rangeOfString:@"<"].location == NSNotFound) {
                    [field setStringValue:text];
                    break;
                }

                NSString *string = [defaultStyleCSS stringByAppendingString:text];
                NSDictionary *options =
                    [NSDictionary dictionaryWithObject:
                        [NSNumber numberWithUnsignedInteger:NSUTF8StringEncoding]
                                                forKey:NSCharacterEncodingDocumentOption];
                NSAttributedString *attrString =
                    [[NSAttributedString alloc]
                        initWithHTML:[string dataUsingEncoding:NSUTF8StringEncoding]
                             options:options
                  documentAttributes:NULL];
                if (attrString)
                    [field setAttributedStringValue:attrString];
                else
                    [field setStringValue:text];
                break;
            }
            case EXTENSION_WIDGET_CHECK_BOX:
            case EXTENSION_WIDGET_BUTTON:
            {
                assert([control isKindOfClass:[NSButton class]]);
                NSButton *button = (NSButton *)control;
                [button setTitle:toNSStr(widget->psz_text)];
                if (widget->type == EXTENSION_WIDGET_CHECK_BOX)
                    [button setState:widget->b_checked ? NSOnState : NSOffState];
                break;
            }
            case EXTENSION_WIDGET_DROPDOWN:
            {
                assert([control isKindOfClass:[VLCDialogPopUpButton class]]);
                VLCDialogPopUpButton *popup = (VLCDialogPopUpButton *)control;
                [popup setProgrammaticSelection:YES];
                [popup removeAllItems];
                struct extension_widget_value_t *value;
                NSInteger selected = -1, index = 0;
                for (value = widget->p_values; value != NULL;
                     value = value->p_next, index++) {
                    [[popup menu] addItemWithTitle:toNSStr(value->psz_text) action:nil keyEquivalent:@""];
                    /* the script may have chosen an entry other than the
                     * first one, see set_value */
                    if (value->b_selected)
                        selected = index;
                }

                if (selected >= 0)
                    [popup selectItemAtIndex:selected];
                [popup synchronizeTitleAndSelectedItem];
                [self popUpSelectionChanged:popup];
                [popup setProgrammaticSelection:NO];
                break;
            }
            case EXTENSION_WIDGET_LIST:
            {
                assert([control isKindOfClass:[NSScrollView class]]);
                NSScrollView *scrollView = (NSScrollView *)control;
                assert([[scrollView documentView] isKindOfClass:[VLCDialogList class]]);
                VLCDialogList *list = (VLCDialogList *)[scrollView documentView];
                BOOL hadContent = [list.contentArray count] > 0;
                NSPoint scrollOrigin = [[scrollView contentView] bounds].origin;
                NSInteger previousSortColumn = list.sortColumn;
                BOOL previousSortAscending = list.sortAscending;

                /* The widget's own text carries tab-separated column headers;
                 * without one the list stays a plain headerless column. */
                NSArray *headers = nil;
                if (widget->psz_text && strchr(widget->psz_text, '\t'))
                    headers = [toNSStr(widget->psz_text) componentsSeparatedByString:@"\t"];
                [list setColumnHeaders:headers];

                NSMutableArray *contentArray = [NSMutableArray array];
                NSMutableSet *selectedIds = [NSMutableSet set];
                struct extension_widget_value_t *value;
                for (value = widget->p_values; value != NULL; value = value->p_next)
                {
                    NSString *text = toNSStr(value->psz_text);
                    NSMutableArray *cells = [NSMutableArray array];
                    NSMutableArray *sortKeys = [NSMutableArray array];
                    for (NSString *cell in [text componentsSeparatedByString:@"\t"]) {
                        NSRange sep = [cell rangeOfString:@VLC_DIALOG_SORTKEY_SEP];
                        if (sep.location == NSNotFound) {
                            [cells addObject:cell];
                            [sortKeys addObject:@""];
                        } else {
                            [cells addObject:[cell substringToIndex:sep.location]];
                            [sortKeys addObject:[cell substringFromIndex:NSMaxRange(sep)]];
                        }
                    }
                    NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                           [NSNumber numberWithInt:value->i_id], @"id",
                                           text, @"text",
                                           cells, @"cells",
                                           sortKeys, @"sortKeys",
                                           nil];
                    /* rows with a promised file name may be dragged out */
                    if (value->psz_dragname)
                        [entry setObject:toNSStr(value->psz_dragname)
                                  forKey:@"dragname"];
                    [contentArray addObject:entry];
                    if (value->b_selected)
                        [selectedIds addObject:[NSNumber numberWithInt:value->i_id]];
                }
                list.contentArray = contentArray;
                [list setProgrammaticSelection:YES];
                /* The extension's requested order wins. Otherwise preserve
                 * the column the user clicked while progressive results are
                 * added to this same list. */
                if (widget->i_sort_column > 0)
                    [list sortByColumn:widget->i_sort_column - 1
                             ascending:widget->b_sort_ascending];
                else if (previousSortColumn >= 0
                      && (NSUInteger)previousSortColumn < [[list tableColumns] count])
                    [list sortByColumn:previousSortColumn
                             ascending:previousSortAscending];
                else
                    [list setSortColumn:-1];
                [list reloadData];
                [list fitColumnsToContent];
                [list deselectAll:nil];
                NSMutableIndexSet *selectedRows = [NSMutableIndexSet indexSet];
                for (NSUInteger row = 0; row < [list.contentArray count]; row++) {
                    NSNumber *rowId = [[list.contentArray objectAtIndex:row]
                                          objectForKey:@"id"];
                    if ([selectedIds containsObject:rowId])
                        [selectedRows addIndex:row];
                }
                [list selectRowIndexes:selectedRows byExtendingSelection:NO];
                /* Progressive searches refill the same widget repeatedly.
                 * Keep the viewport where the user left it; forcing the top
                 * on each newly arrived result made long eMule and Soulseek
                 * lists effectively impossible to browse. A genuinely new
                 * list still starts at its first row. */
                if (hadContent) {
                    NSClipView *clip = [scrollView contentView];
                    [clip scrollToPoint:[clip constrainScrollPoint:scrollOrigin]];
                    [scrollView reflectScrolledClipView:clip];
                } else if ([contentArray count] > 0) {
                    [list showTopOfList];
                }
                [list setProgrammaticSelection:NO];
                break;
            }
            case EXTENSION_WIDGET_IMAGE:
            {
                assert([control isKindOfClass:[NSImageView class]]);
                NSImageView *imageView = (NSImageView *)control;
                NSString *string = widget->psz_text ? toNSStr(widget->psz_text) : nil;
                NSImage *image = nil;
                if (string)
                    image = [[NSImage alloc] initWithContentsOfURL:[NSURL fileURLWithPath:string]];
                [imageView setImage:image];
                break;
            }
            case EXTENSION_WIDGET_SPIN_ICON:
            {
                assert([control isKindOfClass:[NSProgressIndicator class]]);
                NSProgressIndicator *progressIndicator = (NSProgressIndicator *)control;
                if (widget->i_spin_loops != 0)
                    [progressIndicator startAnimation:self];
                else
                    [progressIndicator stopAnimation:self];
                break;
            }
        }
    }
}

/**
 * Ask the dialogs provider to create a new dialog
 **/

static void extensionDialogCallback(extension_dialog_t *p_ext_dialog,
                                    void *p_data)

{
    @autoreleasepool {
        VLCExtensionsDialogProvider *provider = (__bridge VLCExtensionsDialogProvider *)p_data;
        if (!provider)
            return;

        [provider manageDialog:p_ext_dialog];
        return;
    }
}

@implementation VLCExtensionsDialogProvider

- (id)init
{
    self = [super init];
    if (self) {
        intf_thread_t *p_intf = getIntf();
        vlc_dialog_provider_set_ext_callback(p_intf, extensionDialogCallback, (__bridge void *)self);
    }
    return self;
}

- (void)dealloc
{
    vlc_dialog_provider_set_ext_callback(getIntf(), NULL, NULL);
}

- (void)performEventWithObject:(NSValue *)objectValue ofType:(const char*)type
{
    NSString *typeString = toNSStr(type);

    if ([typeString isEqualToString: @"dialog-extension"]) {
        [self performSelectorOnMainThread:@selector(updateExtensionDialog:)
                               withObject:objectValue
                            waitUntilDone:YES
                                    modes:@[NSDefaultRunLoopMode]];

    }
    else
        msg_Err(getIntf(), "unhandled dialog type: '%s'", type);
}

- (void)triggerClick:(id)sender
{
    assert([sender isKindOfClass:[VLCDialogButton class]]);
    VLCDialogButton *button = sender;
    extension_widget_t *widget = [button widget];

    /* The notification is deliberately sent with the dialog unlocked: it
     * wakes the extension thread, which may answer with a dialog update
     * the main thread has to run -- holding the lock here would make the
     * two wait on each other. */
    if (widget->type == EXTENSION_WIDGET_BUTTON) {
        extension_WidgetClicked(widget->p_dialog, widget);
        return;
    }

    vlc_mutex_lock(&widget->p_dialog->lock);
    widget->b_checked = [button state] == NSOnState;
    vlc_mutex_unlock(&widget->p_dialog->lock);
    /* a toggle is a click too: scripts with an on_toggle callback react
     * on the spot, scripts without one never see the event */
    extension_WidgetClicked(widget->p_dialog, widget);
}

- (void)syncTextField:(NSNotification *)notifcation
{
    id sender = [notifcation object];
    assert([sender isKindOfClass:[VLCDialogTextField class]] ||
        [sender isKindOfClass:[VLCDialogSecureTextField class]]);
    NSTextField *field = sender;
    extension_widget_t *widget;

    if ([sender isKindOfClass:[VLCDialogTextField class]])
        widget = [(VLCDialogTextField*)field widget];
    else if ([sender isKindOfClass:[VLCDialogSecureTextField class]])
        widget = [(VLCDialogSecureTextField*)field widget];
    else
        return;

    vlc_mutex_lock(&widget->p_dialog->lock);
    free(widget->psz_text);
    widget->psz_text = strdup([[field stringValue] UTF8String]);
    vlc_mutex_unlock(&widget->p_dialog->lock);

    /* Tell the extension once the typing stops, not once per key: a
     * search box that refills a list of a thousand rows would crawl on
     * the machines this build exists for. */
    [NSObject cancelPreviousPerformRequestsWithTarget:self
                                             selector:@selector(notifyTextChanged:)
                                               object:field];
    [self performSelector:@selector(notifyTextChanged:)
               withObject:field
               afterDelay:VLC_EXTENSION_TEXT_DEBOUNCE];
}

- (void)notifyTextChanged:(id)sender
{
    extension_widget_t *widget = nil;
    if ([sender isKindOfClass:[VLCDialogTextField class]])
        widget = [(VLCDialogTextField *)sender widget];
    else if ([sender isKindOfClass:[VLCDialogSecureTextField class]])
        widget = [(VLCDialogSecureTextField *)sender widget];
    if (!widget)
        return;

    /* unlocked, see -triggerClick: */
    extension_WidgetSelectionChanged(widget->p_dialog, widget);
}

- (void)tableViewSelectionDidChange:(NSNotification *)notifcation
{
    id sender = [notifcation object];
    assert(sender && [sender isKindOfClass:[VLCDialogList class]]);
    VLCDialogList *list = sender;

    /* Our own repopulation lands here too, and must be left alone
     * entirely: it runs from updateWidgets, which already holds the
     * dialog lock on this very thread, and taking it again below would
     * freeze the application (the mutex is not recursive). A
     * header-click sort clears the model at the sort site instead. */
    if ([list programmaticSelection])
        return;

    /* Map by value id, not by row index: a header-click sort reorders the
     * rows on screen while p_values keeps the extension's order. */
    NSMutableSet *selectedIds = [NSMutableSet set];
    NSIndexSet *selectedIndexes = [list selectedRowIndexes];
    for (NSUInteger i = [selectedIndexes firstIndex]; i != NSNotFound;
         i = [selectedIndexes indexGreaterThanIndex:i]) {
        if (i < [list.contentArray count])
            [selectedIds addObject:[[list.contentArray objectAtIndex:i] objectForKey:@"id"]];
    }

    extension_widget_t *widget = [list widget];
    struct extension_widget_value_t *value;
    /* Under the lock: the extension thread frees this whole chain on
     * widget:clear(), and a script that refills a list as the user
     * types was writing b_selected into freed memory (a crash on a
     * plain click, reached from -[NSTableView mouseDown:]). */
    vlc_mutex_lock(&widget->p_dialog->lock);
    for (value = widget->p_values; value != NULL; value = value->p_next)
        value->b_selected = [selectedIds containsObject:[NSNumber numberWithInt:value->i_id]];
    vlc_mutex_unlock(&widget->p_dialog->lock);

    extension_WidgetSelectionChanged(widget->p_dialog, widget);
}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn
{
    if (![tableView isKindOfClass:[VLCDialogList class]])
        return;
    VLCDialogList *list = (VLCDialogList *)tableView;
    if (![list headerView])
        return;

    NSInteger columnIndex = [[tableColumn identifier] integerValue];
    BOOL ascending = (list.sortColumn == columnIndex) ? !list.sortAscending : YES;
    [list setProgrammaticSelection:YES];
    [list deselectAll:nil];
    [list sortByColumn:columnIndex ascending:ascending];
    [list setProgrammaticSelection:NO];

    /* The rows moved, so nothing is selected any more: say so in the
     * model too, or the extension would act on rows the user can no
     * longer see highlighted. */
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
    if ([sender isKindOfClass:[VLCDialogTextField class]])
        widget = [(VLCDialogTextField *)sender widget];
    else if ([sender isKindOfClass:[VLCDialogSecureTextField class]])
        widget = [(VLCDialogSecureTextField *)sender widget];
    if (!widget)
        return;

    /* the extension reads the value back with get_text(): make sure the
     * core carries what is on screen before the callback runs */
    vlc_mutex_lock(&widget->p_dialog->lock);
    free(widget->psz_text);
    widget->psz_text = strdup([[(NSTextField *)sender stringValue] UTF8String]);
    vlc_mutex_unlock(&widget->p_dialog->lock);

    /* unlocked, see -triggerClick: */
    extension_WidgetClicked(widget->p_dialog, widget);
}

- (void)listDoubleClicked:(id)sender
{
    if (![sender isKindOfClass:[VLCDialogList class]])
        return;
    VLCDialogList *list = sender;
    extension_widget_t *widget = [list widget];
    NSInteger clickedRow = [list clickedRow];
    if (!widget || clickedRow < 0
     || (NSUInteger)clickedRow >= [list.contentArray count])
        return;

    /* Do not rely on tableViewSelectionDidChange: having run before the
     * activation callback.  A live search can refill the list between the
     * two clicks and clear its selection even though clickedRow still names
     * the row the user activated.  Snapshot that row's stable value id into
     * the extension model immediately before dispatching the double-click. */
    NSNumber *clickedId = [[list.contentArray objectAtIndex:clickedRow]
                              objectForKey:@"id"];
    vlc_mutex_lock(&widget->p_dialog->lock);
    for (struct extension_widget_value_t *value = widget->p_values;
         value != NULL; value = value->p_next)
        value->b_selected = (value->i_id == [clickedId intValue]);
    vlc_mutex_unlock(&widget->p_dialog->lock);

    /* unlocked, see -triggerClick: -- and a double-click runs inside the
     * table's own event tracking, the worst possible moment to hold a
     * lock the main thread needs again */
    extension_WidgetClicked(widget->p_dialog, widget);
}

- (void)popUpSelectionChanged:(id)sender
{
    assert([sender isKindOfClass:[VLCDialogPopUpButton class]]);
    VLCDialogPopUpButton *popup = sender;
    extension_widget_t *widget = [popup widget];
    struct extension_widget_value_t *value;
    unsigned i = 0;
    /* The value chain belongs to the extension thread, see above -- but
     * updateControlFromWidget calls this method itself while holding
     * the dialog lock, and taking it again there would freeze. */
    BOOL locked = NO;
    if (![popup programmaticSelection]) {
        vlc_mutex_lock(&widget->p_dialog->lock);
        locked = YES;
    }
    for (value = widget->p_values; value != NULL; value = value->p_next, i++)
        value->b_selected = (i == [popup indexOfSelectedItem]);
    if (locked)
        vlc_mutex_unlock(&widget->p_dialog->lock);

    /* Tell the extension, so a script can react to the choice right away
     * -- but only for a choice the user made: refilling the menu lands
     * here as well. */
    if (![popup programmaticSelection])
        extension_WidgetSelectionChanged(widget->p_dialog, widget);
}

- (NSSize)windowWillResize:(NSWindow *)sender toSize:(NSSize)frameSize
{
    NSView *contentView = [sender contentView];
    assert([contentView isKindOfClass:[VLCDialogGridView class]]);
    VLCDialogGridView *gridView = (VLCDialogGridView *)contentView;

    NSRect rect = NSMakeRect(0, 0, 0, 0);
    rect.size = frameSize;
    rect = [sender contentRectForFrameRect:rect];
    rect.size = [gridView flexSize:rect.size];
    rect = [sender frameRectForContentRect:rect];
    return rect.size;
}

- (BOOL)windowShouldClose:(id)sender
{
    assert([sender isKindOfClass:[VLCDialogWindow class]]);
    VLCDialogWindow *window = sender;
    extension_dialog_t *dialog = [window dialog];
    extension_DialogClosed(dialog);

    /* Clearing p_sys_intf before taking the lock skipped the release
     * below, leaking the window and its whole widget tree. */
    vlc_mutex_lock(&dialog->lock);
    if (dialog->p_sys_intf) {
        CFRelease(dialog->p_sys_intf);
        dialog->p_sys_intf = NULL;
    }
    vlc_cond_signal(&dialog->cond);
    vlc_mutex_unlock(&dialog->lock);

    return YES;
}

- (void)updateWidgets:(extension_dialog_t *)dialog
{
    extension_widget_t *widget;
    VLCDialogWindow *dialogWindow = (__bridge VLCDialogWindow *)(dialog->p_sys_intf);

    FOREACH_ARRAY(widget, dialog->widgets) {
        if (!widget)
            continue; /* Some widgets may be NULL@this point */

        BOOL shouldDestroy = widget->b_kill;

        /* Ownership should not be transfered back to ARC here, as
         * we might just want to update something.
         */
        NSView *control = (__bridge NSView *)widget->p_sys_intf;
        BOOL update = widget->b_update;

        if (!control && !shouldDestroy) {
            control = createControlFromWidget(widget, self);
            if (control == NULL)
                msg_Err(getIntf(), "Failed to create control from widget!");
            updateControlFromWidget(control, widget, self);
            /* Ownership needs to be given-up, if ARC would remain with the
             * ownership, the object could be freed while it is still referenced
             * and the invalid reference would be used later.
             */
            widget->p_sys_intf = (__bridge_retained void *)control;
            update = YES; // Force update and repositionning
            [control setHidden:widget->b_hide];
        }

        if (update && !shouldDestroy) {
            updateControlFromWidget(control, widget, self);
            [control setHidden:widget->b_hide];

            int row = widget->i_row - 1;
            int col = widget->i_column - 1;
            int hsp = __MAX(1, widget->i_horiz_span);
            int vsp = __MAX(1, widget->i_vert_span);
            if (row < 0) {
                row = 4;
                col = 0;
            }

            VLCDialogGridView *gridView = (VLCDialogGridView *)[dialogWindow contentView];
            [gridView updateSubview:control atRow:row column:col rowSpan:vsp colSpan:hsp];

            widget->b_update = false;
        }

        if (shouldDestroy) {
            VLCDialogGridView *gridView = (VLCDialogGridView *)[dialogWindow contentView];
            [gridView removeSubview:control];
            /* Explicitily release here, as we do not have transfered ownership to ARC,
             * given that not in all cases we want to destroy the widget.
             */
            if (widget->p_sys_intf) {
                CFRelease(widget->p_sys_intf);
                widget->p_sys_intf = NULL;
            }
        }
    }
    FOREACH_END()
}

/** Create a dialog
 * Note: Lock on p_dialog->lock must be held. */
- (VLCDialogWindow *)createExtensionDialog:(extension_dialog_t *)p_dialog
{
    VLCDialogWindow *dialogWindow;

    BOOL shouldDestroy = p_dialog->b_kill;
    if (!shouldDestroy) {
        NSRect content = NSMakeRect(0, 0, 1, 1);
        dialogWindow = [[VLCDialogWindow alloc] initWithContentRect:content
                                                          styleMask:NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask
                                                            backing:NSBackingStoreBuffered
                                                              defer:NO];
        [dialogWindow setReleasedWhenClosed:NO];
        [dialogWindow setDelegate:self];
        [dialogWindow setDialog:p_dialog];
        [dialogWindow setTitle:toNSStr(p_dialog->psz_title)];

        VLCDialogGridView *gridView = [[VLCDialogGridView alloc] init];
        [gridView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
        [dialogWindow setContentView:gridView];

        p_dialog->p_sys_intf = (void *)CFBridgingRetain(dialogWindow);
    }

    [self updateWidgets:p_dialog];

    if (shouldDestroy) {
        [dialogWindow setDelegate:nil];
        [dialogWindow close];
        p_dialog->p_sys_intf = NULL;
        dialogWindow = nil;
    }

    return dialogWindow;
}

/** Destroy a dialog
 * Note: Lock on p_dialog->lock must be held. */
/* Where each extension's window was left standing.
 *
 * A script that shows another screen does it by deleting its dialog and
 * building the next one, so what the user sees as one window is really
 * a succession of them -- and every new one was being centred. Moving
 * the window then meant nothing: the next view snapped it back. */
static NSMutableDictionary *VLCDialogCorners(void)
{
    static NSMutableDictionary *corners = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ corners = [NSMutableDictionary dictionary]; });
    return corners;
}

static id VLCDialogCornerKey(extension_dialog_t *p_dialog)
{
    /* the extension owning the dialog, not the dialog itself: the whole
     * point is to carry across a dialog being replaced */
    return @((unsigned long)p_dialog->p_sys);
}

- (int)destroyExtensionDialog:(extension_dialog_t *)p_dialog
{
    assert(p_dialog);

    VLCDialogWindow *dialogWindow = (__bridge VLCDialogWindow*)p_dialog->p_sys_intf;
    if (!dialogWindow) {
        msg_Warn(getIntf(), "dialog window not found");
        return VLC_EGENERIC;
    }

    /* Remember the corner before it goes: the next screen this
     * extension shows is a brand new window, and it should come up
     * where the user left this one. */
    if ([dialogWindow isVisible]) {
        NSRect frame = [dialogWindow frame];
        [VLCDialogCorners() setObject:
            [NSValue valueWithPoint:NSMakePoint(frame.origin.x,
                                                NSMaxY(frame))]
                               forKey:VLCDialogCornerKey(p_dialog)];
    }

    /* a debounced text change must not fire at a widget that is going
     * away with this window */
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

    /* The grid schedules its own resize a tenth of a second after a
     * widget changes, and that request is held by the run loop, not by
     * us: a dialog torn down within that tenth -- which is exactly what
     * a double-click on a list that has just been refilled does -- left
     * it to fire on a view whose window is gone by then, and it reads
     * that window's frame. Cancel it while the view is still ours. */
    NSView *contentView = [dialogWindow contentView];
    if ([contentView isKindOfClass:[VLCDialogGridView class]])
        [NSObject cancelPreviousPerformRequestsWithTarget:contentView
                          selector:@selector(recomputeWindowSize)
                            object:nil];

    [dialogWindow setDelegate:nil];
    [dialogWindow close];
    dialogWindow = nil;

    /* Release the reference retained by CFBridgingRetain in
     * createExtensionDialog. We use CFRelease rather than
     * CFBridgingRelease to avoid transferring ownership back
     * to ARC, which would crash as the pointer is still live
     * on the call stack.
     */
    CFRelease(p_dialog->p_sys_intf);
    p_dialog->p_sys_intf = NULL;
    vlc_cond_signal(&p_dialog->cond);
    return VLC_SUCCESS;
}

/**
 * Update/Create/Destroy a dialog
 **/
- (VLCDialogWindow *)updateExtensionDialog:(NSValue *)o_value
{
    extension_dialog_t *p_dialog = [o_value pointerValue];

    VLCDialogWindow *dialogWindow = (__bridge VLCDialogWindow*) p_dialog->p_sys_intf;
    if (p_dialog->b_kill && !dialogWindow) {
        /* This extension could not be activated properly but tried
           to create a dialog. We must ignore it. */
        return NULL;
    }

    vlc_mutex_lock(&p_dialog->lock);
    /* Whatever happens below, this lock must be given back: an AppKit call
     * that raises unwinds straight past the unlock, and the extension
     * thread then waits on this dialog for good -- a frozen application,
     * as the lock is taken again on the next update. */
    @try {
        if (!p_dialog->b_kill && !dialogWindow) {
            dialogWindow = [self createExtensionDialog:p_dialog];

            /* Give it its real size before deciding where it goes. The
             * window is born one point wide and is only fitted to its
             * content on the next turn of the run loop, so both branches
             * below -- the remembered corner and -center -- were placing
             * a 1x1 window, and whatever it grew into afterwards ended up
             * somewhere else entirely. */
            [(VLCDialogGridView *)[dialogWindow contentView]
                recomputeWindowSize];

            BOOL visible = !p_dialog->b_hide;
            if (visible) {
                /* Where this extension's last window stood, if it had
                 * one: the top-left corner, since the window under it
                 * may not be the same height and that corner is the one
                 * a reader thinks of as "where the window is". */
                NSValue *corner = [VLCDialogCorners()
                    objectForKey:VLCDialogCornerKey(p_dialog)];
                if (corner) {
                    NSPoint topLeft = [corner pointValue];
                    NSRect frame = [dialogWindow frame];
                    [dialogWindow setFrameOrigin:
                        NSMakePoint(topLeft.x, topLeft.y - frame.size.height)];
                    NSScreen *screen = [dialogWindow screen]
                                     ?: [NSScreen mainScreen];
                    /* a screen that changed, or a window that grew, must
                     * not put it out of reach */
                    if (!screen
                     || !NSIntersectsRect([dialogWindow frame],
                                          [screen visibleFrame]))
                        [dialogWindow center];
                } else
                    [dialogWindow center];
                [dialogWindow makeKeyAndOrderFront:self];
            } else
                [dialogWindow orderOut:nil];

            [dialogWindow setHas_lock:NO];
        }
        else if (!p_dialog->b_kill && dialogWindow) {
            [dialogWindow setHas_lock:YES];
            [self updateWidgets:p_dialog];
            if (strcmp([[dialogWindow title] UTF8String],
                        p_dialog->psz_title) != 0) {
                NSString *titleString = toNSStr(p_dialog->psz_title);

                [dialogWindow setTitle:titleString];
            }

            [dialogWindow setHas_lock:NO];

            BOOL visible = !p_dialog->b_hide;
            /* Updating a label or a progress value must not steal the
             * foreground from the video window (or another application).
             * Only order an existing dialog when it is transitioning from
             * hidden to visible; otherwise preserve its current z-order and
             * key-window state. */
            if (!visible)
                [dialogWindow orderOut:nil];
            else if (![dialogWindow isVisible])
                [dialogWindow makeKeyAndOrderFront:self];
        }
        else if (p_dialog->b_kill) {
            [self destroyExtensionDialog:p_dialog];
        }
    }
    @catch (NSException *exception) {
        msg_Err(getIntf(), "Exception while updating extension dialog: %s (%s)",
                [[exception name] UTF8String], [[exception reason] UTF8String]);
    }
    @finally {
        vlc_cond_signal(&p_dialog->cond);
        vlc_mutex_unlock(&p_dialog->lock);
    }
    return dialogWindow;
}

/**
 * Ask the dialog manager to create/update/kill the dialog. Thread-safe.
 **/
- (void)manageDialog:(extension_dialog_t *)p_dialog
{
    assert(p_dialog);

    if ([NSThread isMainThread]) {
        [self updateExtensionDialog:[NSValue valueWithPointer:p_dialog]];
        return;
    }

    VLCExtensionDialogRequest *request = VLCDialogRequestCreate(p_dialog);
    if (!request)
        return;
    NSValue *o_value = [NSValue valueWithPointer:request];
    /* The default run loop mode, and no other. Without naming modes,
     * Foundation queues this in the COMMON modes, which AppKit has added
     * event tracking to -- so a dialog rebuilt in answer to a click ran
     * in the middle of that very click, tearing the window down while
     * -[NSTableView mouseDown:] was still tracking inside it. The legacy
     * interface crashed outright on that (a freed button cell, caught in
     * a 10.2 crash report); here it is the same re-entrancy. Holding the
     * update until the click is over costs the extension thread a few
     * milliseconds and it holds no lock of ours meanwhile. */
    [self performSelectorOnMainThread:@selector(runExtensionDialogRequest:)
                           withObject:o_value
                        waitUntilDone:NO
                                modes:@[NSDefaultRunLoopMode]];

    mtime_t deadline = mdate() + 2 * CLOCK_FREQ;
    vlc_mutex_lock(&request->lock);
    while (!request->done) {
        if (request->running) {
            vlc_cond_wait(&request->cond, &request->lock);
        } else if (vlc_cond_timedwait(&request->cond, &request->lock,
                                      deadline) != 0) {
            if (!request->running && !request->done)
                request->cancelled = true;
            break;
        }
    }
    vlc_mutex_unlock(&request->lock);
    VLCDialogRequestRelease(request);
}

- (void)runExtensionDialogRequest:(NSValue *)value
{
    VLCExtensionDialogRequest *request = [value pointerValue];
    vlc_mutex_lock(&request->lock);
    if (request->cancelled) {
        request->done = true;
        vlc_cond_signal(&request->cond);
        vlc_mutex_unlock(&request->lock);
        VLCDialogRequestRelease(request);
        return;
    }
    request->running = true;
    vlc_mutex_unlock(&request->lock);

    [self updateExtensionDialog:[NSValue valueWithPointer:request->dialog]];

    vlc_mutex_lock(&request->lock);
    request->running = false;
    request->done = true;
    vlc_cond_signal(&request->cond);
    vlc_mutex_unlock(&request->lock);
    VLCDialogRequestRelease(request);
}

@end
