/*****************************************************************************
 * VLCLegacyMediaInfo.m: media information window for the legacy interface
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

#import "VLCLegacyMediaInfo.h"
#import "misc.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyControls.h"
#import "VLCLegacyHUDWindow.h"

#include <vlc_playlist.h>
#include <vlc_input.h>
#include <vlc_input_item.h>
#include <vlc_meta.h>
#include <vlc_es.h>
#include <vlc_url.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

#define HUD_WIDTH  506.0f
#define HUD_HEIGHT 476.0f

/* One row of the Codec Details tree: a category ("Stream 0") holding its
 * properties ("Codec", "Resolution", ...), or one such property. Mirrors
 * VLCInfoTreeItem of the modern interface, in manual retain/release. */
@interface VLCLegacyInfoNode : NSObject
{
    NSString *name;
    NSString *value;
    NSMutableArray *children;
}
- (id)initWithName:(NSString *)aName value:(NSString *)aValue;
- (NSString *)name;
- (NSString *)value;
- (NSMutableArray *)children;
@end

@implementation VLCLegacyInfoNode
- (id)initWithName:(NSString *)aName value:(NSString *)aValue
{
    if (self = [super init]) {
        name = [aName copy];
        value = [aValue copy];
        children = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void)dealloc
{
    [name release];
    [value release];
    [children release];
    [super dealloc];
}
- (NSString *)name { return name; }
- (NSString *)value { return value; }
- (NSMutableArray *)children { return children; }
@end

/* input_item_t strings are UTF-8; NSString's "%s" does not decode it */
static NSString *infoString(const char *psz)
{
    if (!psz)
        return @"";
    NSString *s = [NSString stringWithUTF8String:psz];
    return s ? s : @"";
}

/* the editable metadata rows, in the 2.2 MediaInfo order */
static const struct {
    const char *title;                      /* label (gettext key) */
    char *(*pf_get)(input_item_t *);
    void (*pf_set)(input_item_t *, const char *);
} meta_rows[MEDIA_INFO_META_COUNT] = {
    { N_("Title"),        input_item_GetTitle,       input_item_SetTitle },
    { N_("Artist"),       input_item_GetArtist,      input_item_SetArtist },
    { N_("Album"),        input_item_GetAlbum,       input_item_SetAlbum },
    { N_("Date"),         input_item_GetDate,        input_item_SetDate },
    { N_("Genre"),        input_item_GetGenre,       input_item_SetGenre },
    { N_("Track Number"), input_item_GetTrackNum,    input_item_SetTrackNum },
    { N_("Description"),  input_item_GetDescription,
                          input_item_SetDescription },
    { N_("Copyright"),    input_item_GetCopyright,   input_item_SetCopyright },
    { N_("Publisher"),    input_item_GetPublisher,   input_item_SetPublisher },
    { N_("Language"),     input_item_GetLanguage,    input_item_SetLanguage },
    { N_("Encoded by"),   input_item_GetEncodedBy,   input_item_SetEncodedBy },
    { N_("Now Playing"),  input_item_GetNowPlaying,  input_item_SetNowPlaying },
};

@implementation VLCLegacyMediaInfo

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
{
    if (self = [super init]) {
        core = [interaction retain];
        p_intf = [interaction intf];
    }
    return self;
}

- (void)dealloc
{
    [refreshTimer invalidate];
    [panes[0] release];
    [panes[1] release];
    [panes[2] release];
    [streamNodes release];
    [streamsSignature release];
    [window release];
    [core release];
    [super dealloc];
}

/*****************************************************************************
 * dark control helpers
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
    VLCLegacySetCellLineBreakMode([label cell], NSLineBreakByTruncatingTail);
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
        VLCLegacySetCellLineBreakMode([field cell], NSLineBreakByTruncatingMiddle);
    [field setStringValue:@""];
    [parent addSubview:field];
    return field;
}

/*****************************************************************************
 * panes
 *****************************************************************************/

- (NSView *)buildGeneralPane
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 482, 352)] autorelease];

    artworkView = [[[NSImageView alloc]
        initWithFrame:NSMakeRect(6, 246, 100, 100)] autorelease];
    [artworkView setEditable:NO];
    /* -unregisterDraggedTypes is 10.3; below it, a view that never
     * registered a type has nothing to unregister anyway */
    if ([artworkView respondsToSelector:@selector(unregisterDraggedTypes)])
        [artworkView unregisterDraggedTypes];
    [pane addSubview:artworkView];

    int i;
    for (i = 0; i < MEDIA_INFO_META_COUNT; i++) {
        float y = 332 - i * 24;
        NSTextField *label = [self hudLabel:_NS(meta_rows[i].title)
                                      frame:NSMakeRect(116, y + 2, 104, 14)
                                       bold:NO in:pane];
        [label setAlignment:NSRightTextAlignment];
        metaFields[i] = [self hudValue:NSMakeRect(226, y + 1, 248, 16)
                              editable:YES in:pane];
    }

    [self hudLabel:_NS("Location") frame:NSMakeRect(6, 30, 104, 14)
              bold:NO in:pane];
    uriField = [self hudValue:NSMakeRect(6, 9, 468, 16) editable:NO
                           in:pane];

    return pane;
}

- (NSView *)buildCodecPane
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 482, 352)] autorelease];

    NSScrollView *scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(6, 8, 468, 336)] autorelease];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSNoBorder];
    /* The dark HUD background has to come from the SCROLL view, not the outline
     * view: an outline view only paints the rows it has, and this pane is
     * empty until a medium is playing. On 10.4 something else filled the
     * rest; on 10.2 the pane was simply transparent, showing the window
     * behind it through the "Codec Details" tab and its white scroller. */
    [scroll setDrawsBackground:YES];
    [scroll setBackgroundColor:
        [NSColor colorWithCalibratedWhite:0.13f alpha:1.0f]];

    streamsOutline = [[[NSOutlineView alloc]
        initWithFrame:[[scroll contentView] bounds]] autorelease];

    NSTableColumn *nameColumn = [[[NSTableColumn alloc]
        initWithIdentifier:@"name"] autorelease];
    /* the property names are the long side once translated ("Valeur de
     * ReplayGain pour l'album"), the values are mostly short */
    [nameColumn setWidth:210];
    NSTableColumn *valueColumn = [[[NSTableColumn alloc]
        initWithIdentifier:@"value"] autorelease];
    [valueColumn setWidth:256];
    [streamsOutline addTableColumn:nameColumn];
    [streamsOutline addTableColumn:valueColumn];
    [streamsOutline setOutlineTableColumn:nameColumn];

    /* HUD look: dark background, white text (set per cell below, an
     * NSTextFieldCell keeps its own colour) */
    [streamsOutline setBackgroundColor:
        [NSColor colorWithCalibratedWhite:0.13f alpha:1.0f]];
    [streamsOutline setHeaderView:nil];
    if ([streamsOutline respondsToSelector:@selector(setGridStyleMask:)])
        [streamsOutline setGridStyleMask:NSTableViewGridNone];
    if ([streamsOutline respondsToSelector:@selector(setUsesAlternatingRowBackgroundColors:)])
        [streamsOutline setUsesAlternatingRowBackgroundColors:NO];
    [streamsOutline setIndentationPerLevel:12];
    [streamsOutline setAutoresizesOutlineColumn:NO];
    [streamsOutline setRowHeight:14];
    [streamsOutline setDataSource:(id)self];
    [streamsOutline setDelegate:(id)self];

    [scroll setDocumentView:streamsOutline];
    [pane addSubview:scroll];

    return pane;
}

/*****************************************************************************
 * Codec Details tree (NSOutlineView data source / delegate)
 *****************************************************************************/

- (NSInteger)outlineView:(NSOutlineView *)outlineView
  numberOfChildrenOfItem:(id)item
{
    if (!item)
        return streamNodes ? (NSInteger)[streamNodes count] : 0;
    return (NSInteger)[[item children] count];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return item ? [[item children] count] > 0 : YES;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index
           ofItem:(id)item
{
    NSArray *level = item ? (NSArray *)[item children] : (NSArray *)streamNodes;
    if (index < 0 || (NSUInteger)index >= [level count])
        return nil;
    return [level objectAtIndex:index];
}

- (id)outlineView:(NSOutlineView *)outlineView
objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item
{
    if (!item)
        return @"";
    return [[tableColumn identifier] isEqualToString:@"name"]
        ? [item name] : [item value];
}

- (void)outlineView:(NSOutlineView *)outlineView willDisplayCell:(id)cell
     forTableColumn:(NSTableColumn *)tableColumn item:(id)item
{
    if (![cell isKindOfClass:[NSTextFieldCell class]])
        return;
    /* ⚠ White text needs a cell that does NOT paint its own background:
     * on 10.2 every row came out with a white block behind each string,
     * the dark table background showing only in the gaps. Already the
     * default from 10.3 on, so this changes nothing there. */
    [cell setDrawsBackground:NO];
    [cell setTextColor:[NSColor whiteColor]];
    /* categories in bold, their properties in the plain small font */
    BOOL isCategory = [[item children] count] > 0;
    /* 10pt for the properties: both a translated name and a full codec
     * description have to fit in the 468pt the HUD pane offers */
    [cell setFont:isCategory
        ? [NSFont boldSystemFontOfSize:11] : [NSFont systemFontOfSize:10]];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView
    shouldSelectItem:(id)item
{
    return NO;      /* read-only tree, a selection highlight adds nothing */
}

- (NSTextField *)statsRow:(NSString *)title x:(float)x y:(float)y
                       in:(NSView *)parent
{
    NSTextField *label = [self hudLabel:title
                                  frame:NSMakeRect(x, y + 2, 130, 14)
                                   bold:NO in:parent];
    [label setAlignment:NSRightTextAlignment];
    NSTextField *value = [self hudValue:NSMakeRect(x + 136, y, 96, 17)
                               editable:NO in:parent];
    [value setAlignment:NSRightTextAlignment];
    return value;
}

- (NSView *)buildStatsPane
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, 482, 352)] autorelease];

    /* left column: Input, Video (2.2 grouping) */
    [self hudLabel:_NS("Input") frame:NSMakeRect(6, 328, 200, 16)
              bold:YES in:pane];
    readBytesField = [self statsRow:_NS("Read at media") x:2 y:304
                                 in:pane];
    inputBitrateField = [self statsRow:_NS("Input bitrate") x:2 y:282
                                    in:pane];
    demuxBytesField = [self statsRow:_NS("Demuxed") x:2 y:260 in:pane];
    demuxBitrateField = [self statsRow:_NS("Stream bitrate") x:2 y:238
                                    in:pane];

    [self hudLabel:_NS("Video") frame:NSMakeRect(6, 196, 200, 16)
              bold:YES in:pane];
    videoDecodedField = [self statsRow:_NS("Decoded blocks") x:2 y:172
                                    in:pane];
    displayedField = [self statsRow:_NS("Displayed frames") x:2 y:150
                                 in:pane];
    lostFramesField = [self statsRow:_NS("Lost frames") x:2 y:128
                                  in:pane];
    /* look-ahead decode cache (video-cache-mb): live fill / target (with
     * the percentage) and the memory it really uses, so the user can
     * size the option against what the machine sustains */
    videoCacheField = [self statsRow:_NS("Pictures cached") x:2 y:106
                                  in:pane];
    videoCacheMemField = [self statsRow:_NS("Size") x:2 y:84 in:pane];

    /* right column: Audio (3.0 dropped the 2.2 "Streaming" group) */
    [self hudLabel:_NS("Audio") frame:NSMakeRect(246, 328, 200, 16)
              bold:YES in:pane];
    audioDecodedField = [self statsRow:_NS("Decoded blocks") x:242 y:304
                                    in:pane];
    playedABuffersField = [self statsRow:_NS("Played buffers") x:242 y:282
                                      in:pane];
    lostABuffersField = [self statsRow:_NS("Lost buffers") x:242 y:260
                                    in:pane];

    return pane;
}

/*****************************************************************************
 * window
 *****************************************************************************/

- (void)selectPane:(id)sender
{
    int selected = (int)[sender tag];
    [tabHighlight setFrame:
        NSInsetRect([tabButtons[selected] frame], -4, -2)];
    [tabHighlight setNeedsDisplay:YES];
    int i;
    for (i = 0; i < 3; i++) {
        if (i == selected) {
            if (![panes[i] superview])
                [paneContainer addSubview:panes[i]];
        } else if ([panes[i] superview])
            [panes[i] removeFromSuperview];
    }
    for (i = 0; i < 3; i++) {
        NSDictionary *attributes = [NSDictionary
            dictionaryWithObjectsAndKeys:
                i == selected
                    ? [NSFont boldSystemFontOfSize:12]
                    : [NSFont systemFontOfSize:12],
                NSFontAttributeName,
                i == selected
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

- (void)buildWindow
{
    window = [[VLCLegacyHUDPanel alloc]
        initWithContentRect:NSMakeRect(0, 0, HUD_WIDTH, HUD_HEIGHT)
                  styleMask:NSBorderlessWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    [window setTitle:_NS("Media Information")];
    [window setOpaque:NO];
    [window setBackgroundColor:[NSColor clearColor]];
    [window setMovableByWindowBackground:YES];
    [window setReleasedWhenClosed:NO];
    [window setDelegate:(id)self];
    NSView *content = [window contentView];

    VLCLegacyHUDBackgroundView *background =
        [[[VLCLegacyHUDBackgroundView alloc]
            initWithFrame:NSMakeRect(0, 0, HUD_WIDTH, HUD_HEIGHT)]
            autorelease];
    [background setAutoresizingMask:NSViewWidthSizable
                                   | NSViewHeightSizable];
    [content addSubview:background];

    /* HUD title bar: close button + centered title. Drawn by hand: a
     * borderless NSButton with an attributed-string glyph corrupts on
     * Tiger over the translucent HUD (the button cell repaints its own
     * background/glyph independently of the HUD view and the artifacts
     * accumulate). A plain view + two bezier strokes has no cell and no
     * font dependency, nothing to corrupt. */
    VLCLegacyHUDCloseButton *closeButton = [[[VLCLegacyHUDCloseButton alloc]
        initWithFrame:NSMakeRect(8, HUD_HEIGHT - 22, 16, 16)] autorelease];
    [closeButton setTarget:self action:@selector(closeWindow:)];
    [content addSubview:closeButton];

    NSTextField *titleLabel = [self hudLabel:_NS("Media Information")
        frame:NSMakeRect(100, HUD_HEIGHT - 22, HUD_WIDTH - 200, 15)
         bold:YES in:content];
    [titleLabel setAlignment:NSCenterTextAlignment];

    /* pane selector, like the 2.2 HUD tabs; a rounded highlight marks
     * the selected one */
    tabHighlight = [[[VLCLegacyHUDTabHighlightView alloc]
        initWithFrame:NSZeroRect] autorelease];
    [content addSubview:tabHighlight];
    static const char *const tabs[3] =
        { N_("General"), N_("Codec Details"), N_("Statistics") };
    /* equal widths, generous gaps: the selection highlight must never
     * crowd a neighbour's caption */
    float x = (HUD_WIDTH - (3 * 120 + 2 * 24)) / 2;
    int i;
    for (i = 0; i < 3; i++) {
        tabButtons[i] = [[[NSButton alloc]
            initWithFrame:NSMakeRect(x, HUD_HEIGHT - 52, 120, 20)]
            autorelease];
        [tabButtons[i] setButtonType:NSMomentaryChangeButton];
        [tabButtons[i] setBordered:NO];
        [tabButtons[i] setTitle:_NS(tabs[i])];
        [tabButtons[i] setTag:i];
        [tabButtons[i] setTarget:self];
        [tabButtons[i] setAction:@selector(selectPane:)];
        [content addSubview:tabButtons[i]];
        x += 144;
    }

    /* plain container; the pane views are swapped manually */
    paneContainer = [[[NSView alloc]
        initWithFrame:NSMakeRect(12, 46, 482, 352)] autorelease];
    panes[0] = [[self buildGeneralPane] retain];
    panes[1] = [[self buildCodecPane] retain];
    panes[2] = [[self buildStatsPane] retain];
    [content addSubview:paneContainer];

    /* Save Metadata, bottom right like 2.2; sized to its localized title */
    NSDictionary *saveAttributes = [NSDictionary
        dictionaryWithObjectsAndKeys:
            [NSFont boldSystemFontOfSize:12], NSFontAttributeName, nil];
    float saveWidth = (float)ceil([_NS("Save Metadata")
        sizeWithAttributes:saveAttributes].width) + 16;
    NSButton *saveButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(HUD_WIDTH - saveWidth - 14, 12,
                                 saveWidth, 24)]
        autorelease];
    [saveButton setButtonType:NSMomentaryChangeButton];
    [saveButton setBordered:NO];
    {
        NSDictionary *attributes = [NSDictionary
            dictionaryWithObjectsAndKeys:
                [NSFont boldSystemFontOfSize:12], NSFontAttributeName,
                [NSColor whiteColor], NSForegroundColorAttributeName,
                [NSNumber numberWithInt:NSUnderlineStyleSingle],
                NSUnderlineStyleAttributeName, nil];
        [saveButton setAttributedTitle:
            [[[NSAttributedString alloc]
                initWithString:_NS("Save Metadata")
                    attributes:attributes] autorelease]];
    }
    [saveButton setTarget:self];
    [saveButton setAction:@selector(saveMetaData:)];
    [content addSubview:saveButton];

    [self selectPane:tabButtons[0]];
    [window center];
}

- (void)closeWindow:(id)sender
{
    [window orderOut:sender];
    [refreshTimer invalidate];
    refreshTimer = nil;
}

/* debug helper, like -[VLCLegacyPrefs debugSelectPane:] */
- (void)debugSelectPane:(NSNumber *)index
{
    int i = [index intValue];

    if (i >= 0 && i < 3)
        [self selectPane:tabButtons[i]];
}

- (void)showWindow
{
    if (!window)
        [self buildWindow];
    lastItem = NULL;
    [self refresh:nil];
    if (!refreshTimer) {
        refreshTimer =
            [NSTimer scheduledTimerWithTimeInterval:2.0
                                             target:self
                                           selector:@selector(refresh:)
                                           userInfo:nil
                                            repeats:YES];
        /* The default runloop mode alone starves the timer whenever the
         * user drags a slider, holds a menu open or a modal panel runs:
         * the stats then visibly stop refreshing. (NSRunLoopCommonModes
         * is 10.5+, list the modes explicitly.) */
        [[NSRunLoop currentRunLoop] addTimer:refreshTimer
                                     forMode:NSEventTrackingRunLoopMode];
        [[NSRunLoop currentRunLoop] addTimer:refreshTimer
                                     forMode:NSModalPanelRunLoopMode];
    }
    [window makeKeyAndOrderFront:nil];
}

- (void)windowWillClose:(NSNotification *)notification
{
    [refreshTimer invalidate];
    refreshTimer = nil;
}

/*****************************************************************************
 * content refresh
 *****************************************************************************/

- (void)clearFields
{
    int i;
    for (i = 0; i < MEDIA_INFO_META_COUNT; i++)
        [metaFields[i] setStringValue:@""];
    [uriField setStringValue:@""];
    [artworkView setImage:nil];
    [streamsSignature release];
    streamsSignature = nil;
    [streamNodes release];
    streamNodes = nil;
    [streamsOutline reloadData];
}

- (void)fillMetaFromItem:(input_item_t *)p_item
{
    int i;
    for (i = 0; i < MEDIA_INFO_META_COUNT; i++) {
        char *psz = meta_rows[i].pf_get(p_item);
        [metaFields[i] setStringValue:psz && *psz
            ? [NSString stringWithUTF8String:psz] : @""];
        free(psz);
    }
    /* prefer the fallback name for an empty title, like 2.2 */
    if (![[metaFields[0] stringValue] length]) {
        char *psz = input_item_GetTitleFbName(p_item);
        if (psz) {
            [metaFields[0] setStringValue:
                [NSString stringWithUTF8String:psz]];
            free(psz);
        }
    }

    char *psz_uri = input_item_GetURI(p_item);
    if (psz_uri)
        vlc_uri_decode(psz_uri);
    [uriField setStringValue:psz_uri
        ? [NSString stringWithUTF8String:psz_uri] : @""];
    free(psz_uri);

    /* artwork */
    NSImage *art = nil;
    char *psz_art = input_item_GetArtworkURL(p_item);
    if (psz_art) {
        char *psz_path = vlc_uri2path(psz_art);
        if (psz_path) {
            art = [[[NSImage alloc] initWithContentsOfFile:
                [NSString stringWithUTF8String:psz_path]] autorelease];
            free(psz_path);
        }
        free(psz_art);
    }
    [artworkView setImage:art];
}

- (void)refreshStreamsFromItem:(input_item_t *)p_item
{
    /* Build the same tree as the modern interface: the categories the
     * demuxers and decoders publish on the item ("Stream 0" and its
     * properties), which carry far more than the fourcc summary this
     * pane used to print. */
    NSMutableArray *nodes = [NSMutableArray array];
    NSMutableString *signature = [NSMutableString string];

    vlc_mutex_lock(&p_item->lock);
    int i;
    for (i = 0; i < p_item->i_categories; i++) {
        const info_category_t *cat = p_item->pp_categories[i];
        VLCLegacyInfoNode *catNode = [[[VLCLegacyInfoNode alloc]
            initWithName:infoString(cat->psz_name) value:@""] autorelease];
        [signature appendFormat:@"[%@]", [catNode name]];

        int j;
        for (j = 0; j < cat->i_infos; j++) {
            const info_t *info = cat->pp_infos[j];
            VLCLegacyInfoNode *infoNode = [[[VLCLegacyInfoNode alloc]
                initWithName:infoString(info->psz_name)
                       value:infoString(info->psz_value)] autorelease];
            [[catNode children] addObject:infoNode];
            [signature appendFormat:@"%@=%@;", [infoNode name],
                                               [infoNode value]];
        }
        [nodes addObject:catNode];
    }
    vlc_mutex_unlock(&p_item->lock);

    /* Reloading drops the expansion state and repaints the whole list;
     * this pane is refreshed 4 times a second while it is open, so only
     * touch the view when the contents actually changed (same rule as
     * the stats fields below). */
    if (streamsSignature && [streamsSignature isEqualToString:signature])
        return;

    [streamsSignature release];
    streamsSignature = [signature copy];
    [streamNodes release];
    streamNodes = [nodes retain];

    [streamsOutline reloadData];
    /* Show the properties straight away, like the modern interface.
     * -expandItem:nil expandChildren:YES is documented to expand
     * everything but does nothing on Tiger's AppKit: expand each
     * category explicitly (no fast enumeration either, the PowerPC
     * targets build with GCC 4.0.1). */
    NSUInteger n, count = [streamNodes count];
    for (n = 0; n < count; n++)
        [streamsOutline expandItem:[streamNodes objectAtIndex:n]
                    expandChildren:YES];
}

/* Update a stats field only when its text actually changes: these fields
 * sit on the translucent HUD background, and Tiger's AppKit leaves ghost
 * artifacts behind when non-opaque text fields redraw 4 times a second
 * for minutes (the stats window is typically left open to watch the
 * decode cache fill). */
static void setFieldIfChanged(NSTextField *field, NSString *value)
{
    if (![[field stringValue] isEqualToString:value])
        [field setStringValue:value];
}

/* Queried through the (synchronous) input control rather than the stats
 * struct: the input's stats tick stops while paused, and a pause is
 * exactly when the look-ahead cache visibly fills up. */
- (void)refreshVideoCacheFromInput:(input_thread_t *)p_input
{
    size_t i_count = 0, i_target = 0, i_bytes = 0;
    input_Control(p_input, INPUT_GET_VIDEO_CACHE_STATE, &i_count, &i_target,
                  &i_bytes);
    if (i_target > 0) {
        setFieldIfChanged(videoCacheField, [NSString
            stringWithFormat:@"%d / %d (%d%%)", (int)i_count, (int)i_target,
            (int)(100 * i_count / i_target)]);
        setFieldIfChanged(videoCacheMemField, [NSString
            stringWithFormat:_NS("%.1f MiB"),
            (float)i_bytes / (1024 * 1024)]);
    } else {
        setFieldIfChanged(videoCacheField, @"-");
        setFieldIfChanged(videoCacheMemField, @"-");
    }
}

- (void)refreshStatsFromItem:(input_item_t *)p_item
{
    input_stats_t *p_stats = p_item->p_stats;
    if (!p_stats)
        return;

    vlc_mutex_lock(&p_stats->lock);
    /* formats cloned from 2.2's playlistinfo.m */
    setFieldIfChanged(readBytesField, [NSString
        stringWithFormat:_NS("%.1f KiB"),
        (float)(p_stats->i_read_bytes) / 1024]);
    setFieldIfChanged(inputBitrateField, [NSString
        stringWithFormat:@"%6.0f kb/s",
        (float)(p_stats->f_input_bitrate) * 8000]);
    setFieldIfChanged(demuxBytesField, [NSString
        stringWithFormat:_NS("%.1f KiB"),
        (float)(p_stats->i_demux_read_bytes) / 1024]);
    setFieldIfChanged(demuxBitrateField, [NSString
        stringWithFormat:@"%6.0f kb/s",
        (float)(p_stats->f_demux_bitrate) * 8000]);

    setFieldIfChanged(videoDecodedField, [NSString stringWithFormat:@"%d",
        (int)p_stats->i_decoded_video]);
    setFieldIfChanged(displayedField, [NSString stringWithFormat:@"%d",
        (int)p_stats->i_displayed_pictures]);
    setFieldIfChanged(lostFramesField, [NSString stringWithFormat:@"%d",
        (int)p_stats->i_lost_pictures]);

    setFieldIfChanged(audioDecodedField, [NSString stringWithFormat:@"%d",
        (int)p_stats->i_decoded_audio]);
    setFieldIfChanged(playedABuffersField, [NSString stringWithFormat:@"%d",
        (int)p_stats->i_played_abuffers]);
    setFieldIfChanged(lostABuffersField, [NSString stringWithFormat:@"%d",
        (int)p_stats->i_lost_abuffers]);
    vlc_mutex_unlock(&p_stats->lock);
}

- (void)refresh:(NSTimer *)timer
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input) {
        if (lastItem) {
            lastItem = NULL;
            [self clearFields];
        }
        return;
    }

    input_item_t *p_item = input_GetItem(p_input);

    /* only (re)fill the editable fields when the item changes, so a
     * refresh never stomps on an edit in progress */
    if ((void *)p_item != lastItem) {
        lastItem = (void *)p_item;
        [self fillMetaFromItem:p_item];
    }
    [self refreshStreamsFromItem:p_item];
    /* Recompute the stats block right now: the input's own periodic
     * stats tick pauses with the input, which is exactly when the
     * look-ahead cache visibly pre-fills and the user watches this
     * tab -- without this the whole tab freezes on pause. */
    input_Control(p_input, INPUT_UPDATE_STATS);
    [self refreshStatsFromItem:p_item];
    [self refreshVideoCacheFromInput:p_input];

    vlc_object_release(p_input);
}

/*****************************************************************************
 * metadata writing (2.2 saveMetaData:)
 *****************************************************************************/

- (void)saveMetaData:(id)sender
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    input_item_t *p_item = input_GetItem(p_input);

    int i;
    for (i = 0; i < MEDIA_INFO_META_COUNT; i++)
        meta_rows[i].pf_set(p_item,
            [[metaFields[i] stringValue] UTF8String]);

    playlist_t *p_playlist = pl_Get(p_intf);
    if (input_item_WriteMeta(VLC_OBJECT(p_playlist), p_item) != VLC_SUCCESS)
        msg_Warn(p_intf, "unable to write metadata");

    /* refresh from what was actually stored */
    lastItem = NULL;
    [self refresh:nil];
    vlc_object_release(p_input);
}

@end
