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
                [webView setAutoresizingMask:NSViewHeightSizable | NSViewWidthSizable];
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
                NSImageView *imageView = [[NSImageView alloc] init];
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

                /* The widget's own text carries tab-separated column headers;
                 * without one the list stays a plain headerless column. */
                NSArray *headers = nil;
                if (widget->psz_text && strchr(widget->psz_text, '\t'))
                    headers = [toNSStr(widget->psz_text) componentsSeparatedByString:@"\t"];
                [list setColumnHeaders:headers];

                NSMutableArray *contentArray = [NSMutableArray array];
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
                    NSDictionary *entry = [NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSNumber numberWithInt:value->i_id], @"id",
                                           text, @"text",
                                           cells, @"cells",
                                           sortKeys, @"sortKeys",
                                           nil];
                    [contentArray addObject:entry];
                }
                list.contentArray = contentArray;
                /* fresh content comes in the extension's order */
                [list setSortColumn:-1];
                [list setProgrammaticSelection:YES];
                [list reloadData];
                [list fitColumnsToContent];
                /* and is read from its first row: keeping the scroll of
                 * the list that was there before leaves the user looking
                 * at the middle of something else */
                if ([contentArray count] > 0)
                    [list showTopOfList];
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
                            waitUntilDone:YES];

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
    for (value = widget->p_values; value != NULL; value = value->p_next)
        value->b_selected = [selectedIds containsObject:[NSNumber numberWithInt:value->i_id]];

    /* Only a selection the user made is an event: repopulating the list
     * changes the selection too, and that must not reach the extension. */
    if (![list programmaticSelection])
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
    if (!widget || [list clickedRow] < 0)
        return;

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
    for (value = widget->p_values; value != NULL; value = value->p_next, i++)
        value->b_selected = (i == [popup indexOfSelectedItem]);

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
- (int)destroyExtensionDialog:(extension_dialog_t *)p_dialog
{
    assert(p_dialog);

    VLCDialogWindow *dialogWindow = (__bridge VLCDialogWindow*)p_dialog->p_sys_intf;
    if (!dialogWindow) {
        msg_Warn(getIntf(), "dialog window not found");
        return VLC_EGENERIC;
    }

    /* a debounced text change must not fire at a widget that is going
     * away with this window */
    [NSObject cancelPreviousPerformRequestsWithTarget:self];

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

            BOOL visible = !p_dialog->b_hide;
            if (visible) {
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
            if (visible)
                [dialogWindow makeKeyAndOrderFront:self];
            else
                [dialogWindow orderOut:nil];
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

    NSValue *o_value = [NSValue valueWithPointer:p_dialog];
    [self performSelectorOnMainThread:@selector(updateExtensionDialog:)
                           withObject:o_value
                        waitUntilDone:YES];
}

@end
