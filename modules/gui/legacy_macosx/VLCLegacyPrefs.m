/*****************************************************************************
 * VLCLegacyPrefs.m: simple preferences for the legacy Mac OS X interface
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

#import "VLCLegacyPrefs.h"
#import "misc.h"
#import "VLCLegacyCoreInteraction.h"
#import "VLCLegacyControls.h"

#include <vlc_playlist.h>
#include <vlc_configuration.h>
#include <vlc_modules.h>
#include <vlc_plugin.h>
#include <vlc_config_cat.h>
#include <vlc_aout.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

#define PANE_INTERFACE 0
#define PANE_AUDIO     1
#define PANE_VIDEO     2
#define PANE_SUBS      3
#define PANE_INPUT     4
#define PANE_HOTKEYS   5

/* window geometry (VLC 3.0 simple prefs proportions) */
#define PREFS_WIDTH        720.0f
#define PREFS_HEIGHT       560.0f
#define PREFS_PANE_HEIGHT  430.0f

enum {
    ENTRY_BOOL,
    ENTRY_INT,
    ENTRY_FLOAT,
    ENTRY_STRING,
    ENTRY_CHOICE_INT,    /* popup; values in choiceValues (NSNumber) */
    ENTRY_CHOICE_STRING  /* popup; values in choiceValues (NSString) */
};

/* The VLC 3.0 language list (NSUserDefaults "language", read by
 * darwinvlc.m at startup) */
static struct {
    const char iso[6];
    const char name[34];
    BOOL isRightToLeft;

} const language_map[] = {
    { "auto",  N_("Auto"),              NO },
    { "en",    "American English",      NO },
    { "ar",    "عربي",                  YES },
    { "an",    "Aragonés",              NO },
    { "as_IN", "অসমীয়া",                 NO },
    { "ast",   "Asturianu",             NO },
    { "be",    "беларуская мова",       NO },
    { "brx",   "बर'/बड़",                 NO },
    { "bn",    "বাংলা",                   NO },
    { "pt_BR", "Português Brasileiro",  NO },
    { "en_GB", "British English",       NO },
    { "my",    "မြန်မာစာ",                NO },
    { "el",    "Νέα Ελληνικά",          NO },
    { "bg",    "български език",        NO },
    { "ca",    "Català",                NO },
    { "zh_TW", "正體中文",                NO },
    { "co",    "Corsu",                 NO },
    { "cs",    "Čeština",               NO },
    { "cy",    "Cymraeg",               NO },
    { "da",    "Dansk",                 NO },
    { "nl",    "Nederlands",            NO },
    { "fi",    "Suomi",                 NO },
    { "eo",    "Esperanto",             NO },
    { "et",    "eesti keel",            NO },
    { "eu",    "Euskara",               NO },
    { "fr",    "Français",              NO },
    { "ga",    "Gaeilge",               NO },
    { "gd",    "Gàidhlig",              NO },
    { "gl",    "Galego",                NO },
    { "gu",    "ગુજરાતી",                 NO },
    { "de",    "Deutsch",               NO },
    { "he",    "עברית",                 YES },
    { "hr",    "hrvatski",              NO },
    { "kn",    "ಕನ್ನಡ",                   NO },
    { "lv",    "Latviešu valoda",       NO },
    { "hu",    "Magyar",                NO },
    { "mr",    "मराठी",                   NO },
    { "is",    "íslenska",              NO },
    { "id",    "Bahasa Indonesia",      NO },
    { "it",    "Italiano",              NO },
    { "ie",    "Interlingue",           NO },
    { "ja",    "日本語",                 NO },
    { "ko",    "한국어",                  NO },
    { "lt",    "lietuvių",              NO },
    { "lo",    "ລາວ",                   NO },
    { "mk",    "македонски",            NO },
    { "ms",    "Melayu",                NO },
    { "nb",    "Bokmål",                NO },
    { "nn",    "Nynorsk",               NO },
    { "kk",    "Қазақ тілі",            NO },
    { "km",    "ភាសាខ្មែរ",                NO },
    { "ne",    "नेपाली",                  NO },
    { "oc",    "Occitan",               NO },
    { "or_IN", "ଓଡ଼ିଆ",                  NO },
    { "pl",    "Polski",                NO },
    { "pt_PT", "Português",             NO },
    { "pa",    "ਪੰਜਾਬੀ",                  NO },
    { "ro",    "Română",                NO },
    { "ru",    "Русский",               NO },
    { "zh_CN", "简体中文",                NO },
    { "sm",    "Gagana Sāmoa",          NO },
    { "si",    "සිංහල",                   NO },
    { "sr",    "српски",                NO },
    { "sk",    "Slovensky",             NO },
    { "sl",    "slovenščina",           NO },
    { "es",    "Español",               NO },
    { "es_MX", "Español Mexicano",      NO },
    { "sv",    "Svenska",               NO },
    { "sw",    "كِسوَحِيلِ",                YES },
    { "th",    "ภาษาไทย",               NO },
    { "tr",    "Türkçe",                NO },
    { "uk",    "украї́нська мо́ва",       NO },
    { "vi",    "tiếng Việt",            NO },
    { "wa",    "Walon",                 NO }
};


/* One configuration item bound to one control */
@interface VLCLegacyPrefEntry : NSObject
{
@public
    const char *name;      /* static string */
    int type;
    id control;            /* NSButton / NSTextField / NSPopUpButton */
    NSArray *choiceValues;
    NSString *loadedValue; /* canonical value at last loadValues, for
                              dirty detection (see -save:) */
}
- (NSString *)currentStringValue;
@end

@implementation VLCLegacyPrefEntry
/* A canonical string for the control's current state, comparable across a
 * load/save round trip regardless of the on-screen formatting. */
- (NSString *)currentStringValue
{
    switch (type) {
    case ENTRY_BOOL:
        return [control state] == NSOnState ? @"1" : @"0";
    case ENTRY_INT:
        return [NSString stringWithFormat:@"%d", [control intValue]];
    case ENTRY_FLOAT:
        return [NSString stringWithFormat:@"%.4f", [control floatValue]];
    case ENTRY_STRING:
        return [control stringValue] ? [control stringValue] : @"";
    case ENTRY_CHOICE_INT:
    case ENTRY_CHOICE_STRING:
        return [NSString stringWithFormat:@"%ld",
                (long)[control indexOfSelectedItem]];
    }
    return @"";
}

- (void)dealloc
{
    /* the entry owns its control: the advanced panes replace the whole
     * document view, and committing through an unretained control after
     * such a swap crashed on freed objects */
    [control release];
    [choiceValues release];
    [loadedValue release];
    [super dealloc];
}
@end

/* Advanced options are laid out top-down: a flipped container makes the
 * y computation natural and keeps the content glued to the top. */
@interface VLCLegacyFlippedView : NSView
@end
@implementation VLCLegacyFlippedView
- (BOOL)isFlipped { return YES; }
@end

/* The font panel sends -changeFont: down the responder chain; forward it
 * to the controller (a plain NSObject outside the chain). */
@interface VLCLegacyPrefsWindow : NSWindow
{
@public
    VLCLegacyPrefs *controller;   /* weak */
}
@end
@implementation VLCLegacyPrefsWindow
- (void)changeFont:(id)sender
{
    [controller performSelector:@selector(fontChanged:) withObject:sender];
}
@end

/*****************************************************************************
 * hotkey capture panel: port of VLCHotkeyChangeWindow (the panel itself
 * captures every key press, converts it to the VLC textual form and
 * reports it to the controller)
 *****************************************************************************/

static NSString *eventToVLCKeyString(NSEvent *theEvent)
{
    NSMutableString *tempString = [NSMutableString string];
    NSString *keyString = [theEvent characters];
    if (![keyString length])
        return nil;
    unichar key = [keyString characterAtIndex:0];
    unsigned int i_modifiers = (unsigned int)[theEvent modifierFlags];

    /* '+' separator: the exact format of the core defaults
     * (src/libvlc-module.c "Command+Right"), so saved values and
     * duplicate lookups compare like with like */
    if (i_modifiers & NSCommandKeyMask)
        [tempString appendString:@"Command+"];
    if (i_modifiers & NSControlKeyMask)
        [tempString appendString:@"Ctrl+"];
    if (i_modifiers & NSShiftKeyMask)
        [tempString appendString:@"Shift+"];
    if (i_modifiers & NSAlternateKeyMask)
        [tempString appendString:@"Alt+"];

    if (key == NSUpArrowFunctionKey)          [tempString appendString:@"Up"];
    else if (key == NSDownArrowFunctionKey)   [tempString appendString:@"Down"];
    else if (key == NSLeftArrowFunctionKey)   [tempString appendString:@"Left"];
    else if (key == NSRightArrowFunctionKey)  [tempString appendString:@"Right"];
    else if (key >= NSF1FunctionKey && key <= NSF12FunctionKey)
        [tempString appendFormat:@"F%d", (int)(key - NSF1FunctionKey + 1)];
    else if (key == NSInsertFunctionKey)      [tempString appendString:@"Insert"];
    else if (key == NSHomeFunctionKey)        [tempString appendString:@"Home"];
    else if (key == NSEndFunctionKey)         [tempString appendString:@"End"];
    else if (key == NSPageUpFunctionKey)      [tempString appendString:@"Page Up"];
    else if (key == NSPageDownFunctionKey)    [tempString appendString:@"Page Down"];
    else if (key == NSMenuFunctionKey)        [tempString appendString:@"Menu"];
    else if (key == NSTabCharacter)           [tempString appendString:@"Tab"];
    else if (key == NSCarriageReturnCharacter || key == NSEnterCharacter)
        [tempString appendString:@"Enter"];
    else if (key == NSDeleteCharacter)        [tempString appendString:@"Delete"];
    else if (key == NSBackspaceCharacter)     [tempString appendString:@"Backspace"];
    else if (key == 0x001B)                   [tempString appendString:@"Esc"];
    else if (key == ' ')                      [tempString appendString:@"Space"];
    else if ([[[theEvent charactersIgnoringModifiers] lowercaseString] length])
        [tempString appendString:
            [[theEvent charactersIgnoringModifiers] lowercaseString]];
    else
        return nil;
    return tempString;
}

@interface VLCLegacyHotkeyCapturePanel : NSPanel
{
@public
    VLCLegacyPrefs *controller;   /* weak */
}
@end

@implementation VLCLegacyHotkeyCapturePanel
- (BOOL)acceptsFirstResponder { return YES; }
- (BOOL)becomeFirstResponder { return YES; }
- (BOOL)resignFirstResponder
{
    /* stay first responder or the key presses are missed */
    return NO;
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent
{
    NSString *key = eventToVLCKeyString(theEvent);
    if (!key)
        return NO;
    return [controller changeHotkeyTo:key];
}

- (void)keyDown:(NSEvent *)theEvent
{
    NSString *key = eventToVLCKeyString(theEvent);
    if (!key || ![controller changeHotkeyTo:key])
        [super keyDown:theEvent];
}
@end

/* Pretty ⌘⌥⇧⌃-style rendering of a VLC key string, port of
 * -[VLCStringUtility OSXStringKeyToString:] */
/* canonical "Command+Ctrl+Shift+Alt+key" form for comparisons: accepts
 * both '+' and '-' separators (the core writes '+', older vlcrc values
 * and the pre-1.0 capture panel used '-') and any modifier order */
static NSString *canonicalKeyString(NSString *theString)
{
    if (![theString length])
        return @"";
    NSString *rest = theString;
    BOOL cmd = NO, ctrl = NO, shift = NO, alt = NO;
    for (;;) {
        BOOL *flag = NULL;
        unsigned len = 0;
        if ([rest length] > 8
         && [[rest substringToIndex:7] caseInsensitiveCompare:@"Command"]
            == NSOrderedSame) {
            flag = &cmd; len = 7;
        } else if ([rest length] > 5
         && [[rest substringToIndex:4] caseInsensitiveCompare:@"Ctrl"]
            == NSOrderedSame) {
            flag = &ctrl; len = 4;
        } else if ([rest length] > 6
         && [[rest substringToIndex:5] caseInsensitiveCompare:@"Shift"]
            == NSOrderedSame) {
            flag = &shift; len = 5;
        } else if ([rest length] > 4
         && [[rest substringToIndex:3] caseInsensitiveCompare:@"Alt"]
            == NSOrderedSame) {
            flag = &alt; len = 3;
        } else
            break;
        unichar sep = [rest characterAtIndex:len];
        if (sep != '+' && sep != '-')
            break;
        *flag = YES;
        rest = [rest substringFromIndex:len + 1];
    }
    NSMutableString *s = [NSMutableString string];
    if (cmd)   [s appendString:@"Command+"];
    if (ctrl)  [s appendString:@"Ctrl+"];
    if (shift) [s appendString:@"Shift+"];
    if (alt)   [s appendString:@"Alt+"];
    [s appendString:[rest lowercaseString]];
    return s;
}

static NSString *prettyKeyString(NSString *theString)
{
    if (![theString length])
        return _NS("Not Set");
    NSMutableString *s = [NSMutableString stringWithString:theString];
    [s replaceOccurrencesOfString:@"-" withString:@""
                          options:0 range:NSMakeRange(0, [s length] - 1)];
    [s replaceOccurrencesOfString:@"+" withString:@""
                          options:0 range:NSMakeRange(0, [s length] - 1)];
#define REP(a, b) [s replaceOccurrencesOfString:a \
    withString:[NSString stringWithUTF8String:b] \
    options:0 range:NSMakeRange(0, [s length])]
    REP(@"Command", "\xE2\x8C\x98");
    REP(@"Alt", "\xE2\x8C\xA5");
    REP(@"Shift", "\xE2\x87\xA7");
    REP(@"Ctrl", "\xE2\x8C\x83");
    REP(@"Right", "\xE2\x86\x92");
    REP(@"Left", "\xE2\x86\x90");
    REP(@"Page Up", "\xE2\x87\x9E");
    REP(@"Page Down", "\xE2\x87\x9F");
    REP(@"Up", "\xE2\x86\x91");
    REP(@"Down", "\xE2\x86\x93");
    REP(@"Enter", "\xe2\x86\xb5");
    REP(@"Tab", "\xe2\x87\xa5");
    REP(@"Delete", "\xe2\x8c\xab");
#undef REP
    return [s capitalizedString];
}

@implementation VLCLegacyPrefs

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
{
    if (self = [super init]) {
        core = [interaction retain];
        p_intf = [interaction intf];
        entries = [[NSMutableArray alloc] init];
        categoryTree = [[NSMutableArray alloc] init];
        advancedEntries = [[NSMutableArray alloc] init];
        hotkeyNames = [[NSMutableArray alloc] init];
        hotkeyTexts = [[NSMutableArray alloc] init];
        hotkeyValues = [[NSMutableArray alloc] init];
        hotkeyDirty = [[NSMutableArray alloc] init];
        captureRow = -1;
    }
    return self;
}

- (void)dealloc
{
    [capturePanel release];
    [captureKeyInTransition release];
    [window release];
    [entries release];
    [categoryTree release];
    [advancedEntries release];
    [hotkeyNames release];
    [hotkeyTexts release];
    [hotkeyValues release];
    [hotkeyDirty release];
    [core release];
    [super dealloc];
}

/*****************************************************************************
 * row building helpers; the panes are FLIPPED document views inside
 * scroll views, so y grows downward
 *****************************************************************************/

- (NSTextField *)label:(NSString *)text at:(float)y in:(NSView *)parent
{
    NSTextField *label = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(16, y, 216, 17)] autorelease];
    [label setEditable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [label setAlignment:NSRightTextAlignment];
    [[label cell] setFont:[NSFont systemFontOfSize:12]];
    [label setStringValue:text];
    [parent addSubview:label];
    return label;
}

/* bold section header, standing in for the 3.0 NSBox titles */
- (float)header:(NSString *)text at:(float)y in:(NSView *)parent
{
    NSTextField *label = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(16, y + 6, 600, 17)] autorelease];
    [label setEditable:NO];
    [label setBordered:NO];
    [label setDrawsBackground:NO];
    [[label cell] setFont:[NSFont boldSystemFontOfSize:12]];
    [label setStringValue:text];
    [parent addSubview:label];
    return y + 32;
}

- (void)addEntry:(const char *)name type:(int)type control:(id)control
         choices:(NSArray *)values
{
    VLCLegacyPrefEntry *entry = [[[VLCLegacyPrefEntry alloc] init]
        autorelease];
    entry->name = name;
    entry->type = type;
    entry->control = [control retain];
    entry->choiceValues = [values retain];
    [entries addObject:entry];
}

- (NSButton *)checkbox:(NSString *)title config:(const char *)name
                    at:(float)y in:(NSView *)parent
{
    NSButton *box = [[[NSButton alloc]
        initWithFrame:NSMakeRect(240, y, 440, 18)] autorelease];
    [box setButtonType:NSSwitchButton];
    [[box cell] setFont:[NSFont systemFontOfSize:12]];
    [box setTitle:title];
    [parent addSubview:box];
    if (name)
        [self addEntry:name type:ENTRY_BOOL control:box choices:nil];
    return box;
}

- (NSTextField *)textField:(NSString *)labelText config:(const char *)name
                      type:(int)type at:(float)y in:(NSView *)parent
                     width:(float)width
{
    [self label:labelText at:y in:parent];
    NSTextField *field = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(240, y - 3, width, 22)] autorelease];
    [[field cell] setFont:[NSFont systemFontOfSize:12]];
    [[field cell] setWraps:NO];
    [[field cell] setScrollable:YES];
    [parent addSubview:field];
    if (name)
        [self addEntry:name type:type control:field choices:nil];
    return field;
}

- (NSPopUpButton *)popup:(NSString *)labelText config:(const char *)name
                  titles:(NSArray *)titles values:(NSArray *)values
                intValues:(BOOL)isInt at:(float)y in:(NSView *)parent
{
    if (labelText)
        [self label:labelText at:y in:parent];
    NSPopUpButton *popup = [[[NSPopUpButton alloc]
        initWithFrame:NSMakeRect(238, y - 4, 260, 24) pullsDown:NO]
        autorelease];
    unsigned i;
    for (i = 0; i < [titles count]; i++)
        [popup addItemWithTitle:[titles objectAtIndex:i]];
    [parent addSubview:popup];
    if (name)
        [self addEntry:name
                  type:isInt ? ENTRY_CHOICE_INT : ENTRY_CHOICE_STRING
               control:popup choices:values];
    return popup;
}

/* popup fed by the core's own choice lists (translated, and always in
 * sync with the modules); nil when the option does not exist in this
 * build. label nil = the option's own (translated) text. */
- (NSPopUpButton *)popupForConfig:(const char *)name
                            label:(NSString *)labelText
                               at:(float)y in:(NSView *)parent
{
    module_config_t *p_item = config_FindConfig(name);
    if (!p_item)
        return nil;
    BOOL isInt = p_item->i_type == CONFIG_ITEM_INTEGER
              || p_item->i_type == CONFIG_ITEM_RGB;

    int64_t *pi_values = NULL;
    char **ppsz_values = NULL, **ppsz_texts = NULL;
    ssize_t choices = isInt
        ? config_GetIntChoices(VLC_OBJECT(p_intf), name,
                               &pi_values, &ppsz_texts)
        : config_GetPszChoices(VLC_OBJECT(p_intf), name,
                               &ppsz_values, &ppsz_texts);
    if (choices <= 0)
        return nil;

    if (!labelText)
        labelText = p_item->psz_text
            ? _NS(p_item->psz_text) : [NSString stringWithUTF8String:name];
    NSMutableArray *titles = [NSMutableArray array];
    NSMutableArray *values = [NSMutableArray array];
    ssize_t c;
    for (c = 0; c < choices; c++) {
        [titles addObject:[NSString stringWithUTF8String:
            ppsz_texts[c] ? ppsz_texts[c] : ""]];
        if (isInt)
            [values addObject:[NSNumber numberWithLongLong:pi_values[c]]];
        else {
            [values addObject:[NSString stringWithUTF8String:
                ppsz_values[c] ? ppsz_values[c] : ""]];
            free(ppsz_values[c]);
        }
        free(ppsz_texts[c]);
    }
    free(pi_values);
    free(ppsz_values);
    free(ppsz_texts);

    NSPopUpButton *popup = [self popup:labelText config:name
                                titles:titles values:values
                             intValues:isInt at:y in:parent];
    if (p_item->psz_longtext)
        [popup setToolTip:_NS(p_item->psz_longtext)];
    return popup;
}

- (NSButton *)smallButton:(NSString *)title at:(NSRect)rect
                       in:(NSView *)parent action:(SEL)action
{
    NSButton *button = [[[NSButton alloc] initWithFrame:rect] autorelease];
    [button setBezelStyle:NSRoundedBezelStyle];
    [[button cell] setControlSize:NSSmallControlSize];
    [[button cell] setFont:[NSFont systemFontOfSize:
        VLCLegacySystemFontSizeForControlSize(NSSmallControlSize)]];
    [button setTitle:title];
    [button setTarget:self];
    [button setAction:action];
    [parent addSubview:button];
    return button;
}

- (NSMatrix *)radioMatrix:(NSString *)labelText
                   titles:(NSArray *)titles
                       at:(float)y in:(NSView *)parent
                   action:(SEL)action
{
    if (labelText)
        [self label:labelText at:y in:parent];
    NSButtonCell *prototype = [[[NSButtonCell alloc] init] autorelease];
    [prototype setButtonType:NSRadioButton];
    [prototype setFont:[NSFont systemFontOfSize:12]];
    [prototype setTitle:@""];
    NSMatrix *matrix = [[[NSMatrix alloc]
        initWithFrame:NSMakeRect(240, y - 2,
                                 440, 22.0f * [titles count])
                 mode:NSRadioModeMatrix
            prototype:prototype
         numberOfRows:(int)[titles count]
      numberOfColumns:1] autorelease];
    [matrix setCellSize:NSMakeSize(440, 20)];
    [matrix setIntercellSpacing:NSMakeSize(0, 2)];
    unsigned i;
    for (i = 0; i < [titles count]; i++)
        [[matrix cellAtRow:i column:0] setTitle:[titles objectAtIndex:i]];
    if (action) {
        [matrix setTarget:self];
        [matrix setAction:action];
    }
    [parent addSubview:matrix];
    return matrix;
}

/* wraps a finished flipped document into the fixed-size pane viewport */
- (NSView *)wrapPane:(VLCLegacyFlippedView *)doc height:(float)height
{
    [doc setFrameSize:NSMakeSize(704, height)];
    NSScrollView *scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 0, PREFS_WIDTH, PREFS_PANE_HEIGHT)]
        autorelease];
    [scroll setHasVerticalScroller:YES];
    if ([scroll respondsToSelector:@selector(setAutohidesScrollers:)])
        [scroll setAutohidesScrollers:YES];
    [scroll setBorderType:NSNoBorder];
    [scroll setDrawsBackground:NO];
    [scroll setDocumentView:doc];
    [[scroll contentView] scrollToPoint:NSMakePoint(0, 0)];
    return scroll;
}

/* configuration options may be missing from a given build (modules not
 * compiled on that target); every optional row checks first */
static BOOL haveConfig(const char *name)
{
    return config_FindConfig(name) != NULL;
}

- (BOOL)hasModule:(NSString *)moduleName inConfig:(const char *)configName
{
    char *psz = config_GetPsz(p_intf, configName);
    if (!psz)
        return NO;
    NSArray *components = [[NSString stringWithUTF8String:psz]
        componentsSeparatedByString:@":"];
    free(psz);
    return [components containsObject:moduleName];
}

- (void)changeModule:(NSString *)moduleName inConfig:(const char *)configName
              enable:(BOOL)enable
{
    char *psz = config_GetPsz(p_intf, configName);
    NSMutableArray *components = [NSMutableArray array];
    if (psz) {
        [components addObjectsFromArray:[[NSString stringWithUTF8String:psz]
            componentsSeparatedByString:@":"]];
        free(psz);
    }
    if (enable) {
        if (![components containsObject:moduleName])
            [components addObject:moduleName];
    } else
        [components removeObject:moduleName];
    [components removeObject:@""];
    config_PutPsz(p_intf, configName,
        [[components componentsJoinedByString:@":"] UTF8String]);
}

/*****************************************************************************
 * Interface pane (VLC 3.0 order: language, style, playback control,
 * behaviour, privacy, HTTP web interface)
 *****************************************************************************/

- (NSView *)buildInterfacePane
{
    VLCLegacyFlippedView *pane = [[[VLCLegacyFlippedView alloc]
        initWithFrame:NSMakeRect(0, 0, 704, 100)] autorelease];
    float y = 16;

    /* language (NSUserDefaults, read by darwinvlc at startup) */
    NSMutableArray *languages = [NSMutableArray array];
    unsigned i;
    for (i = 0; i < sizeof(language_map) / sizeof(language_map[0]); i++)
        [languages addObject:strcmp(language_map[i].iso, "auto")
            ? [NSString stringWithUTF8String:language_map[i].name]
            : _NS("Auto")];
    languagePopup = [self popup:_NS("Language") config:NULL
                         titles:languages values:nil intValues:NO
                             at:y in:pane];
    y += 30;

    /* interface style radios, driving legacy-macosx-dark */
    styleMatrix = [self radioMatrix:_NS("Interface style")
                             titles:[NSArray arrayWithObjects:
                                     _NS("Bright"), _NS("Dark"), nil]
                                 at:y in:pane action:NULL];
    y += 50;

    y = [self header:_NS("Playback control") at:y in:pane];
    NSPopUpButton *continuePopup = [self popupForConfig:
        "legacy-macosx-continue-playback"
        label:_NS("Continue playback") at:y in:pane];
    if (continuePopup)
        y += 30;
    /* Apple Remote / media keys, backed by the legacy module options */
    [self checkbox:_NS("Control playback with the Apple Remote")
            config:"legacy-macosx-appleremote" at:y in:pane];
    y += 24;
    [self checkbox:_NS("Control system volume with the Apple Remote")
            config:"legacy-macosx-appleremote-sysvol" at:y in:pane];
    y += 24;
    [self checkbox:_NS("Control playback with media keys")
            config:"legacy-macosx-mediakeys" at:y in:pane];
    y += 24;
    /* modern-module-only feature: greyed out, like 3.0 does for absent
     * optional modules */
    {
        NSButton *box = [self checkbox:
            _NS("Display VLC status menu icon") config:NULL at:y in:pane];
        [box setEnabled:NO];
        [box setToolTip:_NS("This setting requires the modern interface.")];
        y += 24;
    }
    y += 6;

    y = [self header:_NS("Playback behaviour") at:y in:pane];
    notificationsCheckbox = [self checkbox:
        _NS("Enable notifications on playlist item change")
        config:NULL at:y in:pane];
    /* the notification module's NAME is osx_notifications; "growl" is
     * only its config shortcut (module_exists matches names, not
     * shortcuts, so testing "growl" always failed) */
    if (!module_exists("osx_notifications"))
        [notificationsCheckbox setEnabled:NO];
    y += 24;
    /* the option is declared with change_integer_list by the legacy
     * module, so the core provides the (translated) choices */
    if ([self popupForConfig:"legacy-macosx-control-itunes"
                       label:_NS("Control external music players")
                          at:y + 4 in:pane])
        y += 36;

    y = [self header:_NS("Privacy / Network Interaction") at:y in:pane];
    [self checkbox:_NS("Allow metadata network access")
            config:"metadata-network-access" at:y in:pane];
    y += 30;

    y = [self header:_NS("HTTP web interface") at:y in:pane];
    luaHTTPCheckbox = [self checkbox:_NS("Enable HTTP web interface")
                              config:NULL at:y in:pane];
    [luaHTTPCheckbox setTarget:self];
    [luaHTTPCheckbox setAction:@selector(luaHTTPToggled:)];
    y += 26;
    luaHTTPPasswordField = [self textField:_NS("Password") config:NULL
                                      type:ENTRY_STRING at:y in:pane
                                     width:200];
    y += 34;

    return [self wrapPane:pane height:y];
}

/*****************************************************************************
 * Audio pane
 *****************************************************************************/

- (NSView *)buildAudioPane
{
    VLCLegacyFlippedView *pane = [[[VLCLegacyFlippedView alloc]
        initWithFrame:NSMakeRect(0, 0, 704, 100)] autorelease];
    float y = 16;

    [self checkbox:_NS("Enable audio") config:"audio" at:y in:pane];
    y += 30;

    volumeMatrix = [self radioMatrix:nil
                              titles:[NSArray arrayWithObjects:
                _NS("Keep audio level between sessions"),
                _NS("Always reset audio start level to:"), nil]
                                  at:y in:pane
                              action:@selector(volumeMatrixChanged:)];
    y += 24;
    /* the radio label ("Always reset audio start level to:") runs to ~x=492
     * once translated (French is ~232 px from x=258); start the slider past
     * it so it no longer sits on top of the text, keeping the value field
     * inside the 704 px pane */
    volumeSlider = [[[NSSlider alloc]
        initWithFrame:NSMakeRect(516, y, 130, 21)] autorelease];
    [volumeSlider setMinValue:0];
    [volumeSlider setMaxValue:200];
    [volumeSlider setTarget:self];
    [volumeSlider setAction:@selector(volumeSliderChanged:)];
    [pane addSubview:volumeSlider];
    volumeField = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(652, y, 48, 22)] autorelease];
    [[volumeField cell] setFont:[NSFont systemFontOfSize:12]];
    [volumeField setTarget:self];
    [volumeField setAction:@selector(volumeFieldChanged:)];
    [pane addSubview:volumeField];
    y += 36;

    [self textField:_NS("Preferred Audio language") config:"audio-language"
               type:ENTRY_STRING at:y in:pane width:200];
    y += 30;

    y = [self header:_NS("Resampling") at:y in:pane];
    {
        /* Speex is a band-limited resampler that costs a fraction of
         * libsamplerate's SINC for the permanent clock-drift correction,
         * with no audible loss (cf. the old-Mac testbeds). Only the drift
         * resampler is affected; fixed-rate conversion keeps its converter. */
        NSButton *box = [self checkbox:_NS("Efficient resampling (Speex)")
                config:"audio-efficient-resampler" at:y in:pane];
        [box setToolTip:_NS("Use the lightweight Speex resampler for "
            "audio/video clock-drift correction instead of the heavier SINC. "
            "Recommended on older Macs. Fixed sample-rate conversion for "
            "music (e.g. 44.1 to 48 kHz) is left untouched.")];
        if (!module_exists("speex_resampler"))
            [box setEnabled:NO];
        y += 30;
    }

    if (haveConfig("audio-visual")) {
        [self popupForConfig:"audio-visual" label:_NS("Visualization")
                          at:y in:pane];
        y += 34;
    }

    y = [self header:@"Last.fm" at:y in:pane];
    lastfmCheckbox = [self checkbox:
        _NS("Submit played tracks stats to Last.fm") config:NULL
        at:y in:pane];
    [lastfmCheckbox setTarget:self];
    [lastfmCheckbox setAction:@selector(lastfmToggled:)];
    y += 26;
    lastfmUserField = [self textField:_NS("Username") config:NULL
                                 type:ENTRY_STRING at:y in:pane width:200];
    y += 28;
    lastfmPasswordField = [[[NSSecureTextField alloc]
        initWithFrame:NSMakeRect(240, y - 3, 200, 22)] autorelease];
    [self label:_NS("Password") at:y in:pane];
    [[lastfmPasswordField cell] setFont:[NSFont systemFontOfSize:12]];
    [pane addSubview:lastfmPasswordField];
    y += 34;
    if (!module_exists("audioscrobbler")) {
        [lastfmCheckbox setEnabled:NO];
        [lastfmUserField setEnabled:NO];
        [lastfmPasswordField setEnabled:NO];
    }

    return [self wrapPane:pane height:y];
}

/*****************************************************************************
 * Video pane
 *****************************************************************************/

- (NSView *)buildVideoPane
{
    VLCLegacyFlippedView *pane = [[[VLCLegacyFlippedView alloc]
        initWithFrame:NSMakeRect(0, 0, 704, 100)] autorelease];
    float y = 16;

    [self checkbox:_NS("Enable video") config:"video" at:y in:pane];
    y += 30;

    y = [self header:_NS("Display") at:y in:pane];
    [self checkbox:_NS("Show video within the main window")
            config:"embedded-video" at:y in:pane]; y += 24;
    [self checkbox:_NS("Pause the video playback when minimized")
            config:"legacy-macosx-pause-minimized" at:y in:pane]; y += 24;
    [self checkbox:_NS("Always on top")
            config:"video-on-top" at:y in:pane]; y += 24;
    [self checkbox:_NS("Window decorations")
            config:"video-deco" at:y in:pane]; y += 30;

    y = [self header:_NS("Fullscreen settings") at:y in:pane];
    [self checkbox:_NS("Fullscreen")
            config:"fullscreen" at:y in:pane]; y += 24;
    [self checkbox:_NS("Black screens in fullscreen")
            config:"legacy-macosx-black" at:y in:pane]; y += 28;
    /* one entry per attached screen, tagged with its display id (same
     * scheme as the 3.0 "Fullscreen Video Device" popup) */
    {
        NSMutableArray *titles = [NSMutableArray array];
        NSMutableArray *values = [NSMutableArray array];
        [titles addObject:_NS("Default")];
        [values addObject:[NSNumber numberWithInt:0]];
        NSArray *screens = [NSScreen screens];
        unsigned i;
        for (i = 0; i < [screens count]; i++) {
            NSRect frame = [[screens objectAtIndex:i] frame];
            [titles addObject:[NSString stringWithFormat:@"%@ %u (%ix%i)",
                _NS("Screen"), i + 1,
                (int)frame.size.width, (int)frame.size.height]];
            [values addObject:[[[screens objectAtIndex:i] deviceDescription]
                objectForKey:@"NSScreenNumber"]];
        }
        [self popup:_NS("Fullscreen Video Device")
             config:"legacy-macosx-vdev"
             titles:titles values:values intValues:YES at:y in:pane];
        y += 34;
    }

    y = [self header:_NS("Video") at:y in:pane];
    /* Apple-DVD-Player-style deinterlacing quality (mapped to a software
     * deinterlacer in VLCLegacyMenu.m). "Best quality" is offered only where
     * the CPU can sustain it, matching how Apple greys it on slower Macs.
     * Applies to new playback; the Video menu changes it live. */
    {
        NSMutableArray *dTitles = [NSMutableArray array];
        NSMutableArray *dValues = [NSMutableArray array];
        const struct { const char *t; int v; } dq[] = {
            { N_("Disabled"),        0 },
            { N_("Good quality"),    1 },
            { N_("Optimal quality"), 2 },
            { N_("Best quality"),    3 },
            { N_("Custom"),          4 },   /* raw method set from the Video menu */
        };
        unsigned di;
        for (di = 0; di < sizeof(dq) / sizeof(dq[0]); di++) {
            if (dq[di].v == 3 && !VLCLegacyBestDeinterlaceAvailable())
                continue;
            [dTitles addObject:_NS(dq[di].t)];
            [dValues addObject:[NSNumber numberWithInt:dq[di].v]];
        }
        deintQualityPopup = [self popup:_NS("Deinterlacing")
                                 config:"legacy-macosx-deinterlace"
                                 titles:dTitles values:dValues
                              intValues:YES at:y in:pane];
        [deintQualityPopup setTarget:self];
        [deintQualityPopup setAction:@selector(deinterlaceQualityChanged:)];
        y += 30;

        /* Revealed only for the "Custom" preset: the raw deinterlace method,
         * fed by the core's own (translated) choice list. */
        deintMethodLabel = [self label:_NS("Deinterlace mode") at:y in:pane];
        {
            char **mv = NULL, **mt = NULL;
            NSMutableArray *mTitles = [NSMutableArray array];
            NSMutableArray *mValues = [NSMutableArray array];
            ssize_t mn = config_GetPszChoices(VLC_OBJECT(p_intf),
                                              "deinterlace-mode", &mv, &mt);
            ssize_t mc;
            for (mc = 0; mc < mn; mc++) {
                if (mv[mc]) {
                    [mTitles addObject:[NSString stringWithUTF8String:
                        (mt[mc] && *mt[mc]) ? mt[mc] : mv[mc]]];
                    [mValues addObject:[NSString stringWithUTF8String:mv[mc]]];
                }
                free(mv[mc]);
                free(mt[mc]);
            }
            free(mv);
            free(mt);
            deintMethodPopup = [self popup:nil config:"deinterlace-mode"
                                    titles:mTitles values:mValues
                                 intValues:NO at:y in:pane];
        }
        y += 34;
        [self syncDeinterlaceMethodVisibility];
    }

    /* GPU planar YUV (gl1 combiner path). ON by default: it roughly halves
     * the CPU on DVD-sized video by moving the YUV->RGB off the CPU.
     *
     * There used to be a note here warning that this mode disabled the
     * look-ahead decode cache below. That was true while the display pool
     * carried a fixed +4 cushion: planar renders straight into that pool, and
     * DecoderVideoCacheTarget switches the cache off under a 24-picture
     * cushion, so asking for a cache did nothing. macosx_gl1.m's Pool() now
     * sizes the cushion from the requested budget (bounded by RAM), so the
     * cache works in both modes and the note is gone. */
    if (haveConfig("gl1-planar")) {
        [self checkbox:_NS("GPU planar YUV rendering")
                config:"gl1-planar" at:y in:pane];
        y += 30;
    }

    y = [self header:_NS("Video snapshots") at:y in:pane];
    snapshotPathField = [self textField:_NS("Folder") config:"snapshot-path"
               type:ENTRY_STRING at:y in:pane width:340];
    [self smallButton:_NS("Browse...")
                   at:NSMakeRect(588, y - 4, 96, 24)
                   in:pane action:@selector(browseSnapshotPath:)];
    y += 30;
    [self textField:_NS("Prefix") config:"snapshot-prefix"
               type:ENTRY_STRING at:y in:pane width:120];
    y += 30;
    [self checkbox:_NS("Sequential numbering")
            config:"snapshot-sequential" at:y in:pane];
    y += 26;
    if ([self popupForConfig:"snapshot-format" label:_NS("Format")
                          at:y in:pane])
        y += 34;

    y = [self header:_NS("Look-ahead decode cache") at:y in:pane];
    NSTextField *mbField = [self textField:_NS("Cache size (MB, 0 = off)")
             config:"video-cache-mb"
               type:ENTRY_INT at:y in:pane width:70];
    [mbField setToolTip:_NS("Maximum memory VLC may use to decode video "
        "pictures ahead of the display clock, to absorb transient "
        "slowdowns without dropping frames. 0 disables the feature.")];
    y += 30;
    NSTextField *fillField = [self textField:
             _NS("Fill threshold before playback (%)")
             config:"video-cache-fill-percent"
               type:ENTRY_INT at:y in:pane width:70];
    [fillField setToolTip:_NS("Playback (and any seek) waits until the "
        "cache reaches this percentage full, or end of stream. The "
        "Play/Pause key skips the wait at any time.")];
    y += 30;
    NSTextField *maxSecField = [self textField:
             _NS("Cache limit (seconds, 0 = none)")
             config:"video-cache-max-seconds"
               type:ENTRY_INT at:y in:pane width:70];
    [maxSecField setToolTip:_NS("Caps the cache to this many seconds of "
        "video regardless of the memory budget above, so light content "
        "does not needlessly inflate memory use or the fill-in wait.")];
    y += 34;

    return [self wrapPane:pane height:y];
}

/*****************************************************************************
 * Subtitles / OSD pane
 *****************************************************************************/

- (NSView *)buildSubtitlesPane
{
    VLCLegacyFlippedView *pane = [[[VLCLegacyFlippedView alloc]
        initWithFrame:NSMakeRect(0, 0, 704, 100)] autorelease];
    float y = 16;

    [self checkbox:_NS("Enable OSD") config:"osd" at:y in:pane];
    y += 30;

    [self textField:_NS("Preferred subtitle language")
             config:"sub-language"
               type:ENTRY_STRING at:y in:pane width:200];
    y += 30;
    if ([self popupForConfig:"subsdec-encoding" label:_NS("Default encoding")
                          at:y in:pane])
        y += 34;

    y = [self header:_NS("Display Settings") at:y in:pane];
    if (haveConfig("freetype-font")) {
        fontField = [self textField:_NS("Font") config:"freetype-font"
                   type:ENTRY_STRING at:y in:pane width:250];
        [self smallButton:_NS("Choose...")
                       at:NSMakeRect(500, y - 4, 96, 24)
                       in:pane action:@selector(chooseFont:)];
        y += 30;
    }
    if ([self popupForConfig:"freetype-rel-fontsize" label:_NS("Font size")
                          at:y in:pane])
        y += 30;
    if ([self popupForConfig:"freetype-color" label:_NS("Font color")
                          at:y in:pane])
        y += 30;
    if (haveConfig("freetype-opacity")) {
        [self label:_NS("Opacity") at:y in:pane];
        opacitySlider = [[[NSSlider alloc]
            initWithFrame:NSMakeRect(240, y - 2, 180, 21)] autorelease];
        [opacitySlider setMinValue:0];
        [opacitySlider setMaxValue:100];
        [opacitySlider setTarget:self];
        [opacitySlider setAction:@selector(opacitySliderChanged:)];
        [pane addSubview:opacitySlider];
        opacityField = [[[NSTextField alloc]
            initWithFrame:NSMakeRect(430, y - 3, 48, 22)] autorelease];
        [[opacityField cell] setFont:[NSFont systemFontOfSize:12]];
        [opacityField setTarget:self];
        [opacityField setAction:@selector(opacityFieldChanged:)];
        [pane addSubview:opacityField];
        y += 32;
    }
    if (haveConfig("freetype-bold")) {
        [self checkbox:_NS("Force bold") config:"freetype-bold" at:y in:pane];
        y += 26;
    }
    if ([self popupForConfig:"freetype-outline-color" label:nil at:y in:pane])
        y += 30;
    if ([self popupForConfig:"freetype-outline-thickness" label:nil
                          at:y in:pane])
        y += 30;
    y += 4;

    return [self wrapPane:pane height:y];
}

/*****************************************************************************
 * Input / Codecs pane
 *****************************************************************************/

- (NSView *)buildInputPane
{
    VLCLegacyFlippedView *pane = [[[VLCLegacyFlippedView alloc]
        initWithFrame:NSMakeRect(0, 0, 704, 100)] autorelease];
    float y = 16;

    recordPathField = [self textField:_NS("Record directory or filename")
             config:"input-record-path"
               type:ENTRY_STRING at:y in:pane width:340];
    [self smallButton:_NS("Browse...")
                   at:NSMakeRect(588, y - 4, 96, 24)
                   in:pane action:@selector(browseRecordPath:)];
    y += 34;

    y = [self header:_NS("Codecs / Muxers") at:y in:pane];
    if (haveConfig("vda")) {
        NSButton *hwBox = [self checkbox:_NS("Hardware decoding")
                                  config:"vda" at:y in:pane];
        [hwBox setToolTip:_NS("Use the hardware H.264 decoder of Mac OS X "
            "10.6.3 and later. If the graphics chipset does not support "
            "it, VLC automatically falls back to software decoding.")];
        y += 26;
    } else if (haveConfig("videotoolbox")) {
        [self checkbox:_NS("Hardware decoding")
                config:"videotoolbox" at:y in:pane];
        y += 26;
    }
    if (haveConfig("mpeg2-hwaccel")) {
        NSButton *mp2Box = [self checkbox:_NS("Hardware MPEG-2 decoding (ATI)")
                                   config:"mpeg2-hwaccel" at:y in:pane];
        [mp2Box setToolTip:_NS("Decode DVDs and MPEG-2 streams on the GPU of "
            "compatible ATI Macs (iBook/PowerBook G3-G4). Automatically falls "
            "back to software decoding when the hardware is absent or the "
            "stream is interlaced.")];
        y += 26;
    }
    if (haveConfig("crystalhd")) {
        NSButton *chdBox = [self checkbox:_NS("Hardware decoding (Crystal HD)")
                                   config:"crystalhd" at:y in:pane];
        [chdBox setToolTip:_NS("Decode H.264, VC-1 and MPEG-2 video on the "
            "Broadcom Crystal HD card installed in this Mac. Untick to decode "
            "with the processor instead; playback also falls back to the "
            "processor on its own whenever the card cannot handle a stream.")];
        y += 26;
    }
    [self checkbox:_NS("Skip frames") config:"skip-frames" at:y in:pane];
    y += 28;
    if (haveConfig("postproc-q")) {
        [self textField:_NS("Post-Processing Quality") config:"postproc-q"
                   type:ENTRY_INT at:y in:pane width:70];
        y += 30;
    }
    if ([self popupForConfig:"avi-index" label:_NS("Repair AVI Files")
                          at:y in:pane])
        y += 30;
    if ([self popupForConfig:"avcodec-skiploopfilter"
                       label:_NS("Skip the loop filter for H.264 decoding")
                          at:y in:pane])
        y += 34;

    y = [self header:_NS("Caching") at:y in:pane];
    {
        static const struct { const char *title; int msec; } levels[6] = {
            { N_("Custom"), 0 },
            { N_("Lowest Latency"), 100 },
            { N_("Low Latency"), 200 },
            { N_("Normal"), 300 },
            { N_("Higher Latency"), 500 },
            { N_("Highest Latency"), 1000 },
        };
        NSMutableArray *titles = [NSMutableArray array];
        int i;
        for (i = 0; i < 6; i++)
            [titles addObject:_NS(levels[i].title)];
        cacheLevelPopup = [self popup:_NS("Default Caching Level")
                               config:NULL
                               titles:titles values:nil intValues:NO
                                   at:y in:pane];
        for (i = 0; i < 6; i++)
            [[cacheLevelPopup itemAtIndex:i] setTag:levels[i].msec];
        y += 26;
        cacheCustomLabel = [[[NSTextField alloc]
            initWithFrame:NSMakeRect(240, y, 440, 30)] autorelease];
        [cacheCustomLabel setEditable:NO];
        [cacheCustomLabel setBordered:NO];
        [cacheCustomLabel setDrawsBackground:NO];
        [[cacheCustomLabel cell] setFont:[NSFont systemFontOfSize:11]];
        [[cacheCustomLabel cell] setWraps:YES];
        [cacheCustomLabel setTextColor:
            [NSColor colorWithCalibratedWhite:0.4 alpha:1.0]];
        [cacheCustomLabel setStringValue:
            _NS("Use the complete preferences to configure custom caching "
                "values for each access module.")];
        [pane addSubview:cacheCustomLabel];
        y += 40;
    }

    return [self wrapPane:pane height:y];
}

/*****************************************************************************
 * Hotkeys pane
 *****************************************************************************/

- (NSView *)buildHotkeysPane
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, PREFS_WIDTH, PREFS_PANE_HEIGHT)]
        autorelease];

    NSTextField *hint = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(16, PREFS_PANE_HEIGHT - 28, 688, 17)]
        autorelease];
    [hint setEditable:NO];
    [hint setBordered:NO];
    [hint setDrawsBackground:NO];
    [[hint cell] setFont:[NSFont systemFontOfSize:11]];
    [hint setTextColor:[NSColor colorWithCalibratedWhite:0.4 alpha:1.0]];
    [hint setStringValue:
        _NS("Select an action to change the associated hotkey:")];
    [pane addSubview:hint];

    NSScrollView *scroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(16, 44, 688, PREFS_PANE_HEIGHT - 80)]
        autorelease];
    [scroll setHasVerticalScroller:YES];
    [scroll setBorderType:NSBezelBorder];

    hotkeysTable = [[[NSTableView alloc]
        initWithFrame:[[scroll contentView] bounds]] autorelease];
    NSTableColumn *actionColumn =
        [[[NSTableColumn alloc] initWithIdentifier:@"action"] autorelease];
    [[actionColumn headerCell] setStringValue:_NS("Action")];
    [actionColumn setWidth:470];
    [actionColumn setEditable:NO];
    [hotkeysTable addTableColumn:actionColumn];
    NSTableColumn *keyColumn =
        [[[NSTableColumn alloc] initWithIdentifier:@"shortcut"] autorelease];
    [[keyColumn headerCell] setStringValue:_NS("Shortcut")];
    [keyColumn setWidth:180];
    [keyColumn setEditable:NO];
    [hotkeysTable addTableColumn:keyColumn];
    [hotkeysTable setDataSource:(id)self];
    /* double-click opens the 3.0 capture panel */
    [hotkeysTable setTarget:self];
    [hotkeysTable setDoubleAction:@selector(hotkeyTableDoubleClicked:)];
    [scroll setDocumentView:hotkeysTable];
    [pane addSubview:scroll];

    [self smallButton:_NS("Change Hotkey")
                   at:NSMakeRect(16, 10, 200, 26)
                   in:pane action:@selector(hotkeyTableDoubleClicked:)];
    [self smallButton:_NS("Clear")
                   at:NSMakeRect(224, 10, 90, 26)
                   in:pane action:@selector(clearHotkey:)];

    return pane;
}

/*****************************************************************************
 * window
 *****************************************************************************/

- (void)addToolbarButton:(NSString *)title icon:(NSString *)icon
                     tag:(int)tag x:(float)x width:(float)width
                      in:(NSView *)parent
{
    NSButton *button = [[[NSButton alloc]
        initWithFrame:NSMakeRect(x, PREFS_HEIGHT - 78, width, 68)]
        autorelease];
    [button setButtonType:NSMomentaryChangeButton];
    [button setBordered:NO];
    NSImage *image = VLCLegacyImage(icon);
#if defined(MAC_OS_X_VERSION_MIN_REQUIRED) && MAC_OS_X_VERSION_MIN_REQUIRED < 1050
    /* 10.4's NSButtonCell draws multi-rep images at their native size and
     * ignores -setSize: — the 128px cone icons then overflow above the
     * button row. Bake a single 32x32 rep by hand. */
    {
        NSImage *baked =
            [[[NSImage alloc] initWithSize:NSMakeSize(32, 32)] autorelease];
        [baked lockFocus];
        [image drawInRect:NSMakeRect(0, 0, 32, 32)
                 fromRect:NSZeroRect
                operation:NSCompositeSourceOver
                 fraction:1.0f];
        [baked unlockFocus];
        image = baked;
    }
#else
    [image setSize:NSMakeSize(32, 32)];
#endif
    [button setImage:image];
    [button setImagePosition:NSImageAbove];
    [[button cell] setFont:[NSFont systemFontOfSize:11]];
    [button setTitle:title];
    [button setTag:100 + tag];
    [button setTarget:self];
    [button setAction:@selector(switchPane:)];
    [parent addSubview:button];
}

- (void)buildWindow
{
    VLCLegacyPrefsWindow *prefsWindow = [[VLCLegacyPrefsWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, PREFS_WIDTH, PREFS_HEIGHT)
                  styleMask:NSTitledWindowMask | NSClosableWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    prefsWindow->controller = self;
    window = prefsWindow;
    [window setTitle:_NS("Preferences")];
    [window setReleasedWhenClosed:NO];
    NSView *content = [window contentView];

    /* icon row, VLC 3.0 simple-preferences style; the buttons are sized
     * to their localized captions so no title gets clipped */
    struct { const char *title; NSString *icon; } panes[6] = {
        { N_("Interface"),        @"VLCInterfaceCone" },
        { N_("Audio"),            @"VLCAudioCone" },
        { N_("Video"),            @"VLCVideoCone" },
        { N_("Subtitles / OSD"),  @"VLCSubtitleCone" },
        { N_("Input / Codecs"),   @"VLCInputCone" },
        { N_("Hotkeys"),          @"VLCHotkeysCone" },
    };
    NSDictionary *titleAttributes = [NSDictionary dictionaryWithObject:
        [NSFont systemFontOfSize:11] forKey:NSFontAttributeName];
    float widths[6];
    float total = 0;
    int i;
    for (i = 0; i < 6; i++) {
        widths[i] = (float)ceil([_NS(panes[i].title)
            sizeWithAttributes:titleAttributes].width) + 16;
        if (widths[i] < 72)
            widths[i] = 72;
        total += widths[i];
    }
    float x = (PREFS_WIDTH - total) / 2;
    if (x < 4)
        x = 4;
    for (i = 0; i < 6; i++) {
        [self addToolbarButton:_NS(panes[i].title) icon:panes[i].icon
                           tag:i x:x width:widths[i] in:content];
        x += widths[i];
    }

    NSBox *separator = [[[NSBox alloc]
        initWithFrame:NSMakeRect(0, PREFS_HEIGHT - 84, PREFS_WIDTH, 1)]
        autorelease];
    [separator setBoxType:NSBoxSeparator];
    [content addSubview:separator];

    tabView = [[[NSTabView alloc]
        initWithFrame:NSMakeRect(0, 46, PREFS_WIDTH, PREFS_PANE_HEIGHT)]
        autorelease];
    [tabView setTabViewType:NSNoTabsNoBorder];

    NSView *paneViews[6];
    paneViews[PANE_INTERFACE] = [self buildInterfacePane];
    paneViews[PANE_AUDIO] = [self buildAudioPane];
    paneViews[PANE_VIDEO] = [self buildVideoPane];
    paneViews[PANE_SUBS] = [self buildSubtitlesPane];
    paneViews[PANE_INPUT] = [self buildInputPane];
    paneViews[PANE_HOTKEYS] = [self buildHotkeysPane];
    for (i = 0; i < 6; i++) {
        NSTabViewItem *item = [[[NSTabViewItem alloc]
            initWithIdentifier:[NSNumber numberWithInt:i]] autorelease];
        [item setView:paneViews[i]];
        [tabView addTabViewItem:item];
    }
    [content addSubview:tabView];

    /* advanced mode container (hidden by default) */
    [self buildAdvancedContainer];
    [content addSubview:advancedContainer];

    toggleButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(16, 10, 140, 28)] autorelease];
    [toggleButton setTitle:_NS("Show All")];
    [toggleButton setBezelStyle:NSRoundedBezelStyle];
    [toggleButton setTarget:self];
    [toggleButton setAction:@selector(toggleAdvanced:)];
    [content addSubview:toggleButton];

    /* bottom buttons */
    NSButton *saveButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(PREFS_WIDTH - 124, 10, 108, 28)]
        autorelease];
    [saveButton setTitle:_NS("Save")];
    [saveButton setBezelStyle:NSRoundedBezelStyle];
    [saveButton setKeyEquivalent:@"\r"];
    [saveButton setTarget:self];
    [saveButton setAction:@selector(save:)];
    [content addSubview:saveButton];

    NSButton *cancelButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(PREFS_WIDTH - 236, 10, 108, 28)]
        autorelease];
    [cancelButton setTitle:_NS("Cancel")];
    [cancelButton setBezelStyle:NSRoundedBezelStyle];
    [cancelButton setKeyEquivalent:@"\033"];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(cancel:)];
    [content addSubview:cancelButton];

    [window center];
}

/* NSTabView relayouts leave the scrolling panes at arbitrary offsets;
 * pin the visible pane back to its top */
- (void)scrollCurrentPaneToTop
{
    NSView *paneView = [[tabView selectedTabViewItem] view];
    if ([paneView isKindOfClass:[NSScrollView class]]) {
        NSScrollView *scroll = (NSScrollView *)paneView;
        [[scroll contentView] scrollToPoint:NSMakePoint(0, 0)];
        [scroll reflectScrolledClipView:[scroll contentView]];
    }
}

- (void)switchPane:(id)sender
{
    [tabView selectTabViewItemAtIndex:[sender tag] - 100];
    [self scrollCurrentPaneToTop];
}

/* debug hook */
- (void)debugSelectPane:(NSNumber *)index
{
    [tabView selectTabViewItemAtIndex:[index intValue]];
    [self scrollCurrentPaneToTop];
}

/*****************************************************************************
 * custom controls behaviors
 *****************************************************************************/

- (void)volumeMatrixChanged:(id)sender
{
    BOOL reset = [volumeMatrix selectedRow] == 1;
    [volumeSlider setEnabled:reset];
    [volumeField setEnabled:reset];
}

- (void)volumeSliderChanged:(id)sender
{
    [volumeField setIntValue:[volumeSlider intValue]];
}

- (void)volumeFieldChanged:(id)sender
{
    [volumeSlider setIntValue:[volumeField intValue]];
}

- (void)opacitySliderChanged:(id)sender
{
    [opacityField setIntValue:[opacitySlider intValue]];
}

- (void)opacityFieldChanged:(id)sender
{
    [opacitySlider setIntValue:[opacityField intValue]];
}

- (void)luaHTTPToggled:(id)sender
{
    [luaHTTPPasswordField setEnabled:
        [luaHTTPCheckbox state] == NSOnState];
}

- (void)lastfmToggled:(id)sender
{
    BOOL on = [lastfmCheckbox state] == NSOnState;
    [lastfmUserField setEnabled:on];
    [lastfmPasswordField setEnabled:on];
}

- (void)browseIntoField:(NSTextField *)field directoriesOnly:(BOOL)dirs
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    [panel setCanChooseFiles:!dirs];
    [panel setCanChooseDirectories:YES];
    [panel setAllowsMultipleSelection:NO];
    if ([panel runModalForDirectory:[field stringValue] file:nil]
            == NSOKButton && [[panel filenames] count])
        [field setStringValue:[[panel filenames] objectAtIndex:0]];
}

- (void)browseSnapshotPath:(id)sender
{
    [self browseIntoField:snapshotPathField directoriesOnly:YES];
}

- (void)browseRecordPath:(id)sender
{
    [self browseIntoField:recordPathField directoriesOnly:YES];
}

- (void)chooseFont:(id)sender
{
    NSFontManager *manager = [NSFontManager sharedFontManager];
    NSFont *current = [NSFont fontWithName:[fontField stringValue] size:12];
    if (!current)
        current = [NSFont systemFontOfSize:12];
    [manager setSelectedFont:current isMultiple:NO];
    [manager orderFrontFontPanel:self];
    [window makeKeyAndOrderFront:nil];
}

/* responder-chain callback, forwarded by VLCLegacyPrefsWindow */
- (void)fontChanged:(id)sender
{
    NSFont *base = [NSFont fontWithName:[fontField stringValue] size:12];
    if (!base)
        base = [NSFont systemFontOfSize:12];
    NSFont *chosen = [sender convertFont:base];
    if (chosen)
        [fontField setStringValue:[chosen fontName]];
}

/*****************************************************************************
 * advanced mode ("Show All"): every option of every module
 *****************************************************************************/

- (void)buildAdvancedContainer
{
    advancedContainer = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 46, PREFS_WIDTH, PREFS_HEIGHT - 54)]
        autorelease];
    VLCLegacySetViewHidden(advancedContainer, YES);

    float height = PREFS_HEIGHT - 54;
    NSScrollView *treeScroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(0, 0, 210, height)] autorelease];
    [treeScroll setHasVerticalScroller:YES];
    [treeScroll setBorderType:NSBezelBorder];
    categoryOutline = [[[NSOutlineView alloc]
        initWithFrame:[[treeScroll contentView] bounds]] autorelease];
    [categoryOutline setHeaderView:nil];
    [categoryOutline setRowHeight:16];
    [categoryOutline setIndentationPerLevel:12];
    NSTableColumn *column =
        [[[NSTableColumn alloc] initWithIdentifier:@"name"] autorelease];
    [column setWidth:190];
    [column setEditable:NO];
    [categoryOutline addTableColumn:column];
    [categoryOutline setOutlineTableColumn:column];
    [categoryOutline setDataSource:(id)self];
    [categoryOutline setDelegate:(id)self];
    [treeScroll setDocumentView:categoryOutline];
    [advancedContainer addSubview:treeScroll];

    optionsScroll = [[[NSScrollView alloc]
        initWithFrame:NSMakeRect(218, 0, PREFS_WIDTH - 218, height)]
        autorelease];
    [optionsScroll setHasVerticalScroller:YES];
    [optionsScroll setBorderType:NSBezelBorder];
    [advancedContainer addSubview:optionsScroll];
}

- (BOOL)moduleHasVisibleConfig:(module_t *)p_module
{
    unsigned confsize;
    module_config_t *p_config = module_config_get(p_module, &confsize);
    BOOL has = NO;
    unsigned i;
    for (i = 0; i < confsize && !has; i++)
        if (CONFIG_ITEM(p_config[i].i_type) && p_config[i].psz_name
            && !p_config[i].b_internal && !p_config[i].b_removed)
            has = YES;
    module_config_free(p_config);
    return has;
}

- (NSMutableDictionary *)subcatNode:(int)subcat
{
    /* find or create the category / subcategory nodes */
    int cat = subcat / 100;
    const char *psz_cat = config_CategoryNameGet(cat);
    const char *psz_subcat = config_CategoryNameGet(subcat);
    if (!psz_cat || !psz_subcat)
        return nil;

    NSMutableDictionary *catNode = nil;
    unsigned i;
    for (i = 0; i < [categoryTree count]; i++)
        if ([[[categoryTree objectAtIndex:i] objectForKey:@"id"]
                intValue] == cat) {
            catNode = [categoryTree objectAtIndex:i];
            break;
        }
    if (!catNode) {
        catNode = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [NSString stringWithUTF8String:psz_cat], @"title",
            @"cat", @"kind",
            [NSNumber numberWithInt:cat], @"id",
            [NSMutableArray array], @"children", nil];
        [categoryTree addObject:catNode];
    }

    NSMutableArray *subcats = [catNode objectForKey:@"children"];
    for (i = 0; i < [subcats count]; i++)
        if ([[[subcats objectAtIndex:i] objectForKey:@"id"]
                intValue] == subcat)
            return [subcats objectAtIndex:i];
    NSMutableDictionary *subcatNode =
        [NSMutableDictionary dictionaryWithObjectsAndKeys:
            [NSString stringWithUTF8String:psz_subcat], @"title",
            @"subcat", @"kind",
            [NSNumber numberWithInt:subcat], @"id",
            [NSMutableArray array], @"children", nil];
    [subcats addObject:subcatNode];
    return subcatNode;
}

- (void)loadModuleList
{
    if ([categoryTree count])
        return;

    size_t count;
    module_t **list = module_list_get(&count);
    size_t i;

    /* first the core: its subcategory hints create the tree skeleton in
     * the canonical order */
    for (i = 0; i < count; i++)
        if (module_is_main(list[i])) {
            unsigned confsize;
            module_config_t *p_config =
                module_config_get(list[i], &confsize);
            unsigned j;
            for (j = 0; j < confsize; j++)
                if (p_config[j].i_type == CONFIG_SUBCATEGORY)
                    [self subcatNode:(int)p_config[j].value.i];
            module_config_free(p_config);
            break;
        }

    /* then every plugin under its (category, subcategory) */
    for (i = 0; i < count; i++) {
        module_t *p_module = list[i];
        if (module_is_main(p_module)
         || ![self moduleHasVisibleConfig:p_module])
            continue;
        unsigned confsize;
        module_config_t *p_config = module_config_get(p_module, &confsize);
        int subcat = SUBCAT_ADVANCED_MISC;
        unsigned j;
        for (j = 0; j < confsize; j++)
            if (p_config[j].i_type == CONFIG_SUBCATEGORY)
                subcat = (int)p_config[j].value.i;
        module_config_free(p_config);

        NSMutableDictionary *parent = [self subcatNode:subcat];
        if (!parent)
            parent = [self subcatNode:SUBCAT_ADVANCED_MISC];
        if (!parent)
            continue;
        const char *psz_name = module_get_name(p_module, false);
        if (!psz_name)
            psz_name = module_get_object(p_module);
        [[parent objectForKey:@"children"] addObject:
            [NSDictionary dictionaryWithObjectsAndKeys:
                [NSString stringWithUTF8String:psz_name], @"title",
                @"module", @"kind",
                [NSValue valueWithPointer:p_module], @"module",
                nil]];
    }

    /* modules sorted alphabetically inside each subcategory */
    unsigned c, sc;
    for (c = 0; c < [categoryTree count]; c++) {
        NSMutableArray *subcats =
            [[categoryTree objectAtIndex:c] objectForKey:@"children"];
        for (sc = 0; sc < [subcats count]; sc++) {
            NSMutableArray *mods =
                [[subcats objectAtIndex:sc] objectForKey:@"children"];
            VLCLegacySortDictionariesByTitle(mods);
        }
    }
    module_list_free(list);
    [categoryOutline reloadData];
}

- (void)commitAdvancedEntries
{
    unsigned i;
    for (i = 0; i < [advancedEntries count]; i++) {
        VLCLegacyPrefEntry *entry = [advancedEntries objectAtIndex:i];
        switch (entry->type) {
        case ENTRY_BOOL:
            config_PutInt(p_intf, entry->name,
                          [entry->control state] == NSOnState);
            break;
        case ENTRY_INT:
            config_PutInt(p_intf, entry->name, [entry->control intValue]);
            break;
        case ENTRY_FLOAT:
            config_PutFloat(p_intf, entry->name, [entry->control floatValue]);
            break;
        case ENTRY_STRING:
            config_PutPsz(p_intf, entry->name,
                          [[entry->control stringValue] UTF8String]);
            break;
        case ENTRY_CHOICE_INT:
        {
            int index = (int)[entry->control indexOfSelectedItem];
            if (index >= 0 && (unsigned)index < [entry->choiceValues count])
                config_PutInt(p_intf, entry->name,
                    [[entry->choiceValues objectAtIndex:index] longLongValue]);
            break;
        }
        case ENTRY_CHOICE_STRING:
        {
            int index = (int)[entry->control indexOfSelectedItem];
            if (index >= 0 && (unsigned)index < [entry->choiceValues count])
                config_PutPsz(p_intf, entry->name,
                    [[entry->choiceValues objectAtIndex:index] UTF8String]);
            break;
        }
        }
    }
}

- (void)addAdvancedEntry:(const char *)name type:(int)type
                 control:(id)control choices:(NSArray *)values
{
    VLCLegacyPrefEntry *entry = [[[VLCLegacyPrefEntry alloc] init]
        autorelease];
    entry->name = name;
    entry->type = type;
    entry->control = [control retain];
    entry->choiceValues = [values retain];
    [advancedEntries addObject:entry];
}

- (void)rebuildOptionsForModule:(module_t *)p_module
                   subcatFilter:(int)subcatFilter
{
    [self commitAdvancedEntries];
    [advancedEntries removeAllObjects];

    unsigned confsize;
    module_config_t *p_config = module_config_get(p_module, &confsize);

    float width = PREFS_WIDTH - 218 - 22;
    VLCLegacyFlippedView *doc = [[[VLCLegacyFlippedView alloc]
        initWithFrame:NSMakeRect(0, 0, width, 10)] autorelease];
    float y = 12;
    int currentSubcat = -1;
    unsigned i;
    for (i = 0; i < confsize; i++) {
        module_config_t *item = p_config + i;

        if (item->i_type == CONFIG_SUBCATEGORY)
            currentSubcat = (int)item->value.i;
        if (subcatFilter >= 0 && currentSubcat != subcatFilter)
            continue;

        if (item->i_type == CONFIG_SECTION && item->psz_text) {
            NSTextField *section = [[[NSTextField alloc]
                initWithFrame:NSMakeRect(8, y, width - 16, 17)] autorelease];
            [section setEditable:NO];
            [section setBordered:NO];
            [section setDrawsBackground:NO];
            [[section cell] setFont:[NSFont boldSystemFontOfSize:12]];
            [section setStringValue:[NSString stringWithUTF8String:
                vlc_gettext(item->psz_text)]];
            [doc addSubview:section];
            y += 26;
            continue;
        }
        if (!CONFIG_ITEM(item->i_type) || !item->psz_name
            || item->b_internal || item->b_removed)
            continue;

        NSString *text = item->psz_text
            ? [NSString stringWithUTF8String:vlc_gettext(item->psz_text)]
            : [NSString stringWithUTF8String:item->psz_name];
        NSString *longText = item->psz_longtext
            ? [NSString stringWithUTF8String:vlc_gettext(item->psz_longtext)]
            : nil;

        if (item->i_type == CONFIG_ITEM_BOOL) {
            NSButton *box = [[[NSButton alloc]
                initWithFrame:NSMakeRect(12, y, width - 24, 18)] autorelease];
            [box setButtonType:NSSwitchButton];
            [[box cell] setFont:[NSFont systemFontOfSize:11]];
            [box setTitle:text];
            if (longText)
                [box setToolTip:longText];
            [box setState:config_GetInt(p_intf, item->psz_name)
                ? NSOnState : NSOffState];
            [doc addSubview:box];
            [self addAdvancedEntry:item->psz_name type:ENTRY_BOOL
                           control:box choices:nil];
            y += 26;
            continue;
        }

        /* label + control */
        NSTextField *label = [[[NSTextField alloc]
            initWithFrame:NSMakeRect(8, y + 2, 190, 16)] autorelease];
        [label setEditable:NO];
        [label setBordered:NO];
        [label setDrawsBackground:NO];
        [label setAlignment:NSRightTextAlignment];
        [[label cell] setFont:[NSFont systemFontOfSize:11]];
        VLCLegacySetCellLineBreakMode([label cell], NSLineBreakByTruncatingTail);
        [label setStringValue:text];
        if (longText)
            [label setToolTip:longText];
        [doc addSubview:label];

        BOOL isInt = item->i_type == CONFIG_ITEM_INTEGER
                  || item->i_type == CONFIG_ITEM_RGB;
        BOOL isFloat = item->i_type == CONFIG_ITEM_FLOAT;

        /* choice list (built through the core so callbacks work) */
        if (isInt || !isFloat) {
            int64_t *pi_values = NULL;
            char **ppsz_values = NULL, **ppsz_texts = NULL;
            ssize_t choices = isInt
                ? config_GetIntChoices(VLC_OBJECT(p_intf), item->psz_name,
                                       &pi_values, &ppsz_texts)
                : config_GetPszChoices(VLC_OBJECT(p_intf), item->psz_name,
                                       &ppsz_values, &ppsz_texts);
            if (choices > 0) {
                NSPopUpButton *popup = [[[NSPopUpButton alloc]
                    initWithFrame:NSMakeRect(204, y - 2, width - 216, 24)
                        pullsDown:NO] autorelease];
                NSMutableArray *values = [NSMutableArray array];
                char *psz_current = NULL;
                int64_t i_current = 0;
                if (isInt)
                    i_current = config_GetInt(p_intf, item->psz_name);
                else
                    psz_current = config_GetPsz(p_intf, item->psz_name);
                ssize_t c;
                for (c = 0; c < choices; c++) {
                    [popup addItemWithTitle:[NSString stringWithUTF8String:
                        ppsz_texts[c] ? ppsz_texts[c] : ""]];
                    if (isInt) {
                        [values addObject:
                            [NSNumber numberWithLongLong:pi_values[c]]];
                        if (pi_values[c] == i_current)
                            [popup selectItemAtIndex:c];
                    } else {
                        const char *choice = ppsz_values[c]
                            ? ppsz_values[c] : "";
                        [values addObject:
                            [NSString stringWithUTF8String:choice]];
                        if (psz_current && !strcmp(psz_current, choice))
                            [popup selectItemAtIndex:c];
                        free(ppsz_values[c]);
                    }
                    free(ppsz_texts[c]);
                }
                free(pi_values);
                free(ppsz_values);
                free(ppsz_texts);
                free(psz_current);
                if (longText)
                    [popup setToolTip:longText];
                [doc addSubview:popup];
                [self addAdvancedEntry:item->psz_name
                                  type:isInt ? ENTRY_CHOICE_INT
                                             : ENTRY_CHOICE_STRING
                               control:popup choices:values];
                y += 28;
                continue;
            }
        }

        NSTextField *field = [[[NSTextField alloc]
            initWithFrame:NSMakeRect(204, y, width - 216, 20)] autorelease];
        [[field cell] setFont:[NSFont systemFontOfSize:11]];
        [[field cell] setWraps:NO];
        [[field cell] setScrollable:YES];
        if (longText)
            [field setToolTip:longText];
        if (isInt) {
            [field setStringValue:[NSString stringWithFormat:@"%lld",
                (long long)config_GetInt(p_intf, item->psz_name)]];
            [self addAdvancedEntry:item->psz_name type:ENTRY_INT
                           control:field choices:nil];
        } else if (isFloat) {
            [field setStringValue:[NSString stringWithFormat:@"%.3f",
                config_GetFloat(p_intf, item->psz_name)]];
            [self addAdvancedEntry:item->psz_name type:ENTRY_FLOAT
                           control:field choices:nil];
        } else {
            char *psz = config_GetPsz(p_intf, item->psz_name);
            [field setStringValue:psz
                ? [NSString stringWithUTF8String:psz] : @""];
            free(psz);
            [self addAdvancedEntry:item->psz_name type:ENTRY_STRING
                           control:field choices:nil];
        }
        [doc addSubview:field];
        y += 28;
    }
    module_config_free(p_config);

    [doc setFrameSize:NSMakeSize(width + 10, y + 8)];
    [optionsScroll setDocumentView:doc];
    [[optionsScroll contentView] scrollToPoint:NSMakePoint(0, 0)];
}

/* debug hook (VLC_LEGACY_SHOW=prefssub<id>): renders a subcategory's core
 * options without going through the outline view */
- (void)debugShowSubcat:(NSNumber *)subcat
{
    module_t *p_core = [self coreModule];
    if (p_core)
        [self rebuildOptionsForModule:p_core subcatFilter:[subcat intValue]];
}

- (void)toggleAdvanced:(id)sender
{
    advancedMode = !advancedMode;
    if (advancedMode) {
        [window makeFirstResponder:nil];
        [self loadModuleList];
        VLCLegacySetViewHidden(advancedContainer, NO);
        VLCLegacySetViewHidden(tabView, YES);
        int i;
        for (i = 0; i < 6; i++)
            VLCLegacySetViewHidden(
                VLCLegacyViewWithTag([window contentView], 100 + i), YES);
        [toggleButton setTitle:_NS("Basic")];
        if ([categoryOutline selectedRow] < 0 && [categoryTree count]) {
            [categoryOutline expandItem:[categoryTree objectAtIndex:0]];
            VLCLegacySelectRow(categoryOutline, 1);
        }
    } else {
        [window makeFirstResponder:nil];
        [self commitAdvancedEntries];
        VLCLegacySetViewHidden(advancedContainer, YES);
        VLCLegacySetViewHidden(tabView, NO);
        int i;
        for (i = 0; i < 6; i++)
            VLCLegacySetViewHidden(
                VLCLegacyViewWithTag([window contentView], 100 + i), NO);
        [toggleButton setTitle:_NS("Show All")];
        [self loadValues];
    }
}

/*****************************************************************************
 * values <-> configuration
 *****************************************************************************/

- (void)loadValues
{
    unsigned i;
    for (i = 0; i < [entries count]; i++) {
        VLCLegacyPrefEntry *entry = [entries objectAtIndex:i];
        switch (entry->type) {
        case ENTRY_BOOL:
            [entry->control setState:config_GetInt(p_intf, entry->name)
                ? NSOnState : NSOffState];
            break;
        case ENTRY_INT:
            [entry->control setStringValue:[NSString stringWithFormat:@"%d",
                (int)config_GetInt(p_intf, entry->name)]];
            break;
        case ENTRY_FLOAT:
            [entry->control setStringValue:[NSString stringWithFormat:@"%.2f",
                config_GetFloat(p_intf, entry->name)]];
            break;
        case ENTRY_STRING:
        {
            char *psz = config_GetPsz(p_intf, entry->name);
            [entry->control setStringValue:psz
                ? [NSString stringWithUTF8String:psz] : @""];
            free(psz);
            break;
        }
        case ENTRY_CHOICE_INT:
        {
            int value = (int)config_GetInt(p_intf, entry->name);
            unsigned j;
            [entry->control selectItemAtIndex:0];
            for (j = 0; j < [entry->choiceValues count]; j++)
                if ([[entry->choiceValues objectAtIndex:j] intValue]
                        == value) {
                    [entry->control selectItemAtIndex:j];
                    break;
                }
            break;
        }
        case ENTRY_CHOICE_STRING:
        {
            char *psz = config_GetPsz(p_intf, entry->name);
            NSString *value = psz
                ? [NSString stringWithUTF8String:psz] : @"";
            free(psz);
            unsigned j;
            [entry->control selectItemAtIndex:0];
            for (j = 0; j < [entry->choiceValues count]; j++)
                if ([[entry->choiceValues objectAtIndex:j]
                        isEqualToString:value]) {
                    [entry->control selectItemAtIndex:j];
                    break;
                }
            break;
        }
        }
        /* remember the freshly loaded value so -save: can tell whether the
         * user actually touched this control */
        [entry->loadedValue release];
        entry->loadedValue = [[entry currentStringValue] copy];
    }

    [self loadCustomValues];
    /* the raw method picker only makes sense for the "Custom" preset */
    [self syncDeinterlaceMethodVisibility];
}

/* Show the deinterlace method picker only when the quality preset is "Custom".
 * Compare the selected TITLE rather than an index: "Best quality" is omitted on
 * Macs that cannot run it, which shifts every index below it. */
- (void)syncDeinterlaceMethodVisibility
{
    if (!deintQualityPopup || !deintMethodPopup)
        return;
    BOOL custom = [[deintQualityPopup titleOfSelectedItem]
                      isEqualToString:_NS("Custom")];
    VLCLegacySetViewHidden(deintMethodPopup, !custom);
    VLCLegacySetViewHidden(deintMethodLabel, !custom);
}

- (void)deinterlaceQualityChanged:(id)sender
{
    [self syncDeinterlaceMethodVisibility];
}

- (void)loadCustomValues
{
    /* language (NSUserDefaults) */
    NSString *pref = [[NSUserDefaults standardUserDefaults]
        objectForKey:@"language"];
    unsigned sel = 0, x;
    for (x = 0; x < sizeof(language_map) / sizeof(language_map[0]); x++)
        if (pref && !strcmp(language_map[x].iso, [pref UTF8String]))
            sel = x;
    [languagePopup selectItemAtIndex:sel];

    /* interface style */
    [styleMatrix selectCellAtRow:
        config_GetInt(p_intf, "legacy-macosx-dark") ? 1 : 0 column:0];

    /* notifications (growl control module) */
    [notificationsCheckbox setState:
        [self hasModule:@"growl" inConfig:"control"]
            ? NSOnState : NSOffState];

    /* lua http interface */
    BOOL httpEnabled = [self hasModule:@"http" inConfig:"extraintf"];
    [luaHTTPCheckbox setState:httpEnabled ? NSOnState : NSOffState];
    [luaHTTPPasswordField setEnabled:httpEnabled];
    if (haveConfig("http-password")) {
        char *psz = config_GetPsz(p_intf, "http-password");
        [luaHTTPPasswordField setStringValue:psz
            ? [NSString stringWithUTF8String:psz] : @""];
        free(psz);
    }

    /* audio volume persistence */
    if (config_GetInt(p_intf, "volume-save")) {
        [volumeMatrix selectCellAtRow:0 column:0];
        [volumeSlider setEnabled:NO];
        [volumeField setEnabled:NO];
        [volumeSlider setIntValue:100];
        [volumeField setIntValue:100];
    } else {
        [volumeMatrix selectCellAtRow:1 column:0];
        [volumeSlider setEnabled:YES];
        [volumeField setEnabled:YES];
        int vol = (int)((float)var_InheritInteger(p_intf, "auhal-volume")
                        * 200.0f / AOUT_VOLUME_MAX);
        [volumeSlider setIntValue:vol];
        [volumeField setIntValue:vol];
    }

    /* last.fm */
    if (module_exists("audioscrobbler")) {
        BOOL on = config_ExistIntf(VLC_OBJECT(p_intf), "audioscrobbler");
        [lastfmCheckbox setState:on ? NSOnState : NSOffState];
        [lastfmUserField setEnabled:on];
        [lastfmPasswordField setEnabled:on];
        if (haveConfig("lastfm-username")) {
            char *psz = config_GetPsz(p_intf, "lastfm-username");
            [lastfmUserField setStringValue:psz
                ? [NSString stringWithUTF8String:psz] : @""];
            free(psz);
        }
        if (haveConfig("lastfm-password")) {
            char *psz = config_GetPsz(p_intf, "lastfm-password");
            [lastfmPasswordField setStringValue:psz
                ? [NSString stringWithUTF8String:psz] : @""];
            free(psz);
        }
    }

    /* subtitles opacity (0-255 stored, % shown) */
    if (opacitySlider) {
        int pct = (int)(config_GetInt(p_intf, "freetype-opacity")
                        * 100.0 / 255.0 + 0.5);
        [opacitySlider setIntValue:pct];
        [opacityField setIntValue:pct];
    }

    /* composite caching level: "Custom" unless every *-caching value
     * derives from file-caching with the 3.0 factors */
    {
        int i_cache = (int)config_GetInt(p_intf, "file-caching");
        bool cache_equal =
            (i_cache * (10 / 3) == config_GetInt(p_intf, "network-caching"))
         && (i_cache == config_GetInt(p_intf, "disc-caching"))
         && (i_cache == config_GetInt(p_intf, "live-caching"));
        if (cache_equal) {
            [cacheLevelPopup selectItemAtIndex:0];
            int j;
            for (j = 0; j < (int)[cacheLevelPopup numberOfItems]; j++)
                if ([[cacheLevelPopup itemAtIndex:j] tag] == i_cache) {
                    [cacheLevelPopup selectItemAtIndex:j];
                    break;
                }
            VLCLegacySetViewHidden(cacheCustomLabel, YES);
        } else {
            [cacheLevelPopup selectItemAtIndex:0];   /* Custom */
            VLCLegacySetViewHidden(cacheCustomLabel, NO);
        }
    }
}

- (void)loadHotkeys
{
    [hotkeyNames removeAllObjects];
    [hotkeyTexts removeAllObjects];
    [hotkeyValues removeAllObjects];
    [hotkeyDirty removeAllObjects];

    module_t *p_main = module_find("core");
    if (!p_main)
        return;
    unsigned confsize;
    module_config_t *p_config = module_config_get(p_main, &confsize);
    unsigned i;
    for (i = 0; i < confsize; i++) {
        module_config_t *item = p_config + i;
        if (item->i_type != CONFIG_ITEM_KEY || !item->psz_name
            || strncmp(item->psz_name, "key-", 4))
            continue;
        [hotkeyNames addObject:
            [NSString stringWithUTF8String:item->psz_name]];
        [hotkeyTexts addObject:item->psz_text
            ? [NSString stringWithUTF8String:vlc_gettext(item->psz_text)]
            : [NSString stringWithUTF8String:item->psz_name]];
        char *psz = config_GetPsz(p_intf, item->psz_name);
        [hotkeyValues addObject:psz
            ? [NSString stringWithUTF8String:psz] : @""];
        free(psz);
        [hotkeyDirty addObject:[NSNumber numberWithBool:NO]];
    }
    module_config_free(p_config);
    [hotkeysTable reloadData];
}

- (void)save:(id)sender
{
    [window makeFirstResponder:nil];
    if (advancedMode)
        [self commitAdvancedEntries];
    unsigned i;
    for (i = 0; i < [entries count]; i++) {
        VLCLegacyPrefEntry *entry = [entries objectAtIndex:i];
        /* Skip controls the user did not touch. Several config keys
         * (audio-language, sub-language, …) are exposed both here and in
         * the "Show All" pane; writing an untouched simple control back
         * unconditionally would clobber an edit just made over there. */
        if (entry->loadedValue
            && [[entry currentStringValue] isEqualToString:entry->loadedValue])
            continue;
        switch (entry->type) {
        case ENTRY_BOOL:
            config_PutInt(p_intf, entry->name,
                          [entry->control state] == NSOnState);
            break;
        case ENTRY_INT:
            config_PutInt(p_intf, entry->name, [entry->control intValue]);
            break;
        case ENTRY_FLOAT:
            config_PutFloat(p_intf, entry->name,
                            [entry->control floatValue]);
            break;
        case ENTRY_STRING:
            config_PutPsz(p_intf, entry->name,
                          [[entry->control stringValue] UTF8String]);
            break;
        case ENTRY_CHOICE_INT:
        {
            int index = (int)[entry->control indexOfSelectedItem];
            if (index >= 0 && (unsigned)index < [entry->choiceValues count])
                config_PutInt(p_intf, entry->name,
                    [[entry->choiceValues objectAtIndex:index] intValue]);
            break;
        }
        case ENTRY_CHOICE_STRING:
        {
            int index = (int)[entry->control indexOfSelectedItem];
            if (index >= 0 && (unsigned)index < [entry->choiceValues count])
                config_PutPsz(p_intf, entry->name,
                    [[entry->choiceValues objectAtIndex:index] UTF8String]);
            break;
        }
        }
    }

    /* language */
    {
        int index = (int)[languagePopup indexOfSelectedItem];
        if (index >= 0
         && (unsigned)index < sizeof(language_map) / sizeof(language_map[0]))
        {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:[NSString stringWithUTF8String:
                                    language_map[index].iso]
                         forKey:@"language"];

            /* Sens d'écriture, comme le fait +[VLCSimplePrefsController
             * updateRightToLeftSettings] côté moderne : sans ça, choisir
             * l'arabe, l'hébreu ou le persan traduisait bien l'interface mais
             * la laissait disposée de gauche à droite. En « Auto » on RETIRE
             * les clés au lieu de les poser à NO, pour rendre la main à la
             * détection du système. */
            if (!strcmp(language_map[index].iso, "auto")) {
                [defaults removeObjectForKey:@"NSForceRightToLeftWritingDirection"];
                [defaults removeObjectForKey:@"AppleTextDirection"];
            } else {
                BOOL rtl = language_map[index].isRightToLeft;
                [defaults setBool:rtl
                           forKey:@"NSForceRightToLeftWritingDirection"];
                [defaults setBool:rtl forKey:@"AppleTextDirection"];
            }

            /* ⚠ INDISPENSABLE : contrairement au reste du panneau, la langue
             * ne passe pas par config_PutPsz()/config_SaveConfigFile() mais par
             * NSUserDefaults, et sur les vieux systèmes (pas de cfprefsd) rien
             * ne vide le cache sur disque à la sortie de l'application. Sans ce
             * -synchronize le réglage était perdu au redémarrage, et le
             * CFPreferencesCopyAppValue(CFSTR("language")) de bin/darwinvlc.m
             * ne le voyait donc jamais. Le contrôleur moderne
             * (VLCSimplePrefsController.m) le fait déjà. */
            [defaults synchronize];
        }
    }

    /* interface style */
    config_PutInt(p_intf, "legacy-macosx-dark",
                  [styleMatrix selectedRow] == 1);

    /* notifications */
    if ([notificationsCheckbox isEnabled])
        [self changeModule:@"growl" inConfig:"control"
                    enable:[notificationsCheckbox state] == NSOnState];

    /* lua http interface */
    [self changeModule:@"http" inConfig:"extraintf"
                enable:[luaHTTPCheckbox state] == NSOnState];
    if (haveConfig("http-password"))
        config_PutPsz(p_intf, "http-password",
                      [[luaHTTPPasswordField stringValue] UTF8String]);

    /* audio volume persistence */
    config_PutInt(p_intf, "volume-save", [volumeMatrix selectedRow] == 0);
    if ([volumeField isEnabled] && haveConfig("auhal-volume"))
        config_PutInt(p_intf, "auhal-volume",
                      [volumeField intValue] * AOUT_VOLUME_MAX / 200);

    /* last.fm */
    if (module_exists("audioscrobbler")) {
        if ([lastfmCheckbox state] == NSOnState)
            config_AddIntf(VLC_OBJECT(p_intf), "audioscrobbler");
        else
            config_RemoveIntf(VLC_OBJECT(p_intf), "audioscrobbler");
        if (haveConfig("lastfm-username"))
            config_PutPsz(p_intf, "lastfm-username",
                          [[lastfmUserField stringValue] UTF8String]);
        if (haveConfig("lastfm-password"))
            config_PutPsz(p_intf, "lastfm-password",
                          [[lastfmPasswordField stringValue] UTF8String]);
    }

    /* subtitles opacity */
    if (opacityField && haveConfig("freetype-opacity"))
        config_PutInt(p_intf, "freetype-opacity",
                      (int)([opacityField intValue] * 255.0 / 100.0 + 0.5));

    /* composite caching level */
    {
        int tag = (int)[[cacheLevelPopup selectedItem] tag];
        if (tag != 0) {
            config_PutInt(p_intf, "file-caching", tag);
            config_PutInt(p_intf, "network-caching", tag * (10 / 3));
            config_PutInt(p_intf, "disc-caching", tag);
            config_PutInt(p_intf, "live-caching", tag);
        }
    }

    for (i = 0; i < [hotkeyNames count]; i++) {
        if (![[hotkeyDirty objectAtIndex:i] boolValue])
            continue;
        config_PutPsz(p_intf,
                      [[hotkeyNames objectAtIndex:i] UTF8String],
                      [[hotkeyValues objectAtIndex:i] UTF8String]);
    }

    /* apply the session-visible playback modes immediately */
    playlist_t *p_playlist = pl_Get(p_intf);
    var_SetBool(p_playlist, "video-on-top",
                config_GetInt(p_intf, "video-on-top"));

    /* apply Apple Remote / media keys / external player changes live */
    [core shutdownRemoteAndMediaKeys];
    [core setupRemoteAndMediaKeys];
    if ([NSApp isActive])
        [core startListeningWithAppleRemote];

    config_SaveConfigFile(p_intf);
    [window orderOut:nil];
}

- (void)cancel:(id)sender
{
    [window orderOut:nil];
}

- (void)showWindow
{
    if (!window)
        [self buildWindow];
    [self loadValues];
    [self loadHotkeys];
    [tabView selectTabViewItemAtIndex:PANE_INTERFACE];
    [self scrollCurrentPaneToTop];
    [window makeKeyAndOrderFront:nil];
}

/*****************************************************************************
 * hotkeys table data source + capture panel
 *****************************************************************************/

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
    return (NSInteger)[hotkeyNames count];
}

- (id)tableView:(NSTableView *)tableView
    objectValueForTableColumn:(NSTableColumn *)column
                          row:(NSInteger)row
{
    if (row < 0 || (unsigned)row >= [hotkeyNames count])
        return @"";
    if ([[column identifier] isEqualToString:@"action"])
        return [hotkeyTexts objectAtIndex:row];
    return prettyKeyString([hotkeyValues objectAtIndex:row]);
}

- (void)buildCapturePanel
{
    VLCLegacyHotkeyCapturePanel *panel = [[VLCLegacyHotkeyCapturePanel alloc]
        initWithContentRect:NSMakeRect(0, 0, 400, 168)
                  styleMask:NSTitledWindowMask
                    backing:NSBackingStoreBuffered
                      defer:NO];
    panel->controller = self;
    capturePanel = panel;
    [capturePanel setTitle:_NS("Change Hotkey")];
    [capturePanel setReleasedWhenClosed:NO];
    NSView *content = [capturePanel contentView];

    captureActionLabel = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(16, 118, 368, 38)] autorelease];
    [captureActionLabel setEditable:NO];
    [captureActionLabel setBordered:NO];
    [captureActionLabel setDrawsBackground:NO];
    [captureActionLabel setAlignment:NSCenterTextAlignment];
    [[captureActionLabel cell] setFont:[NSFont systemFontOfSize:12]];
    [[captureActionLabel cell] setWraps:YES];
    [content addSubview:captureActionLabel];

    captureKeysLabel = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(16, 84, 368, 26)] autorelease];
    [captureKeysLabel setEditable:NO];
    [captureKeysLabel setBordered:NO];
    [captureKeysLabel setDrawsBackground:NO];
    [captureKeysLabel setAlignment:NSCenterTextAlignment];
    [[captureKeysLabel cell] setFont:[NSFont boldSystemFontOfSize:16]];
    [content addSubview:captureKeysLabel];

    captureTakenLabel = [[[NSTextField alloc]
        initWithFrame:NSMakeRect(16, 50, 368, 30)] autorelease];
    [captureTakenLabel setEditable:NO];
    [captureTakenLabel setBordered:NO];
    [captureTakenLabel setDrawsBackground:NO];
    [captureTakenLabel setAlignment:NSCenterTextAlignment];
    [[captureTakenLabel cell] setFont:[NSFont systemFontOfSize:11]];
    [[captureTakenLabel cell] setWraps:YES];
    [captureTakenLabel setTextColor:[NSColor redColor]];
    [content addSubview:captureTakenLabel];

    NSButton *cancelButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(184, 10, 100, 28)] autorelease];
    [cancelButton setTitle:_NS("Cancel")];
    [cancelButton setBezelStyle:NSRoundedBezelStyle];
    [cancelButton setTarget:self];
    [cancelButton setAction:@selector(captureCancel:)];
    [content addSubview:cancelButton];

    captureOKButton = [[[NSButton alloc]
        initWithFrame:NSMakeRect(288, 10, 100, 28)] autorelease];
    [captureOKButton setTitle:_NS("OK")];
    [captureOKButton setBezelStyle:NSRoundedBezelStyle];
    [captureOKButton setTarget:self];
    [captureOKButton setAction:@selector(captureOK:)];
    [content addSubview:captureOKButton];

    [capturePanel center];
}

- (void)hotkeyTableDoubleClicked:(id)sender
{
    int row = (int)[hotkeysTable selectedRow];
    if (row < 0 || (unsigned)row >= [hotkeyNames count])
        return;
    if (!capturePanel)
        [self buildCapturePanel];
    captureRow = row;
    [captureKeyInTransition release];
    captureKeyInTransition = nil;
    [captureActionLabel setStringValue:[NSString stringWithFormat:
        _NS("Press new keys for\n\"%@\""),
        [hotkeyTexts objectAtIndex:row]]];
    [captureKeysLabel setStringValue:
        prettyKeyString([hotkeyValues objectAtIndex:row])];
    [captureTakenLabel setStringValue:@""];
    [captureOKButton setEnabled:NO];
    [capturePanel makeKeyAndOrderFront:nil];
    [NSApp runModalForWindow:capturePanel];
    [capturePanel orderOut:nil];
}

/* like indexOfObject: but comparing canonical key forms, so
 * "Command-Right", "Command+Right" and "Shift+Command+Right"-style
 * variants of the same combination are all recognized */
- (unsigned)indexOfHotkeyValue:(NSString *)key
{
    NSString *canonical = canonicalKeyString(key);
    if (![canonical length])
        return (unsigned)NSNotFound;
    unsigned i;
    for (i = 0; i < [hotkeyValues count]; i++)
        if ([canonicalKeyString([hotkeyValues objectAtIndex:i])
                isEqualToString:canonical])
            return i;
    return (unsigned)NSNotFound;
}

- (BOOL)changeHotkeyTo:(NSString *)key
{
    if (![key length]) {
        [captureKeysLabel setStringValue:_NS("Invalid combination")];
        [captureTakenLabel setStringValue:
            _NS("Regrettably, these keys cannot be assigned as hotkey "
                "shortcuts.")];
        [captureOKButton setEnabled:NO];
        return NO;
    }
    [captureKeysLabel setStringValue:prettyKeyString(key)];
    unsigned taken = [self indexOfHotkeyValue:key];
    if (taken != (unsigned)NSNotFound && (int)taken != captureRow)
        [captureTakenLabel setStringValue:[NSString stringWithFormat:
            _NS("This combination is already taken by \"%@\"."),
            [hotkeyTexts objectAtIndex:taken]]];
    else
        [captureTakenLabel setStringValue:@""];
    [captureOKButton setEnabled:YES];
    [captureKeyInTransition release];
    captureKeyInTransition = [key retain];
    return YES;
}

- (void)captureOK:(id)sender
{
    if (captureRow >= 0 && captureKeyInTransition
     && (unsigned)captureRow < [hotkeyValues count]) {
        /* steal the combination from any other action, like 3.0 */
        unsigned taken = [self indexOfHotkeyValue:captureKeyInTransition];
        if (taken != (unsigned)NSNotFound && (int)taken != captureRow) {
            [hotkeyValues replaceObjectAtIndex:taken withObject:@""];
            [hotkeyDirty replaceObjectAtIndex:taken
                                   withObject:[NSNumber numberWithBool:YES]];
        }
        [hotkeyValues replaceObjectAtIndex:captureRow
                                withObject:captureKeyInTransition];
        [hotkeyDirty replaceObjectAtIndex:captureRow
                               withObject:[NSNumber numberWithBool:YES]];
        [hotkeysTable reloadData];
    }
    [NSApp stopModal];
}

- (void)captureCancel:(id)sender
{
    [NSApp stopModal];
}

- (void)clearHotkey:(id)sender
{
    int row = (int)[hotkeysTable selectedRow];
    if (row < 0 || (unsigned)row >= [hotkeyValues count])
        return;
    [hotkeyValues replaceObjectAtIndex:row withObject:@""];
    [hotkeyDirty replaceObjectAtIndex:row
                           withObject:[NSNumber numberWithBool:YES]];
    [hotkeysTable reloadData];
}

- (module_t *)coreModule
{
    size_t count;
    module_t **list = module_list_get(&count);
    module_t *p_core = NULL;
    size_t i;
    for (i = 0; i < count; i++)
        if (module_is_main(list[i])) {
            p_core = list[i];
            break;
        }
    module_list_free(list);
    return p_core;
}

/* outline view: categories -> subcategories -> modules */
- (NSInteger)outlineView:(NSOutlineView *)outlineView
    numberOfChildrenOfItem:(id)item
{
    if (!item)
        return (NSInteger)[categoryTree count];
    return (NSInteger)[[item objectForKey:@"children"] count];
}

- (id)outlineView:(NSOutlineView *)outlineView
            child:(NSInteger)index
           ofItem:(id)item
{
    NSArray *children = item
        ? [item objectForKey:@"children"] : categoryTree;
    return [children objectAtIndex:index];
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item
{
    return [[item objectForKey:@"children"] count] > 0;
}

- (id)outlineView:(NSOutlineView *)outlineView
    objectValueForTableColumn:(NSTableColumn *)column
                       byItem:(id)item
{
    return [item objectForKey:@"title"];
}

- (void)outlineViewSelectionDidChange:(NSNotification *)notification
{
    if ([notification object] != categoryOutline)
        return;
    int row = (int)[categoryOutline selectedRow];
    if (row < 0)
        return;
    id item = [categoryOutline itemAtRow:row];
    NSString *kind = [item objectForKey:@"kind"];
    [window makeFirstResponder:nil];
    if ([kind isEqualToString:@"module"]) {
        [self rebuildOptionsForModule:
            [[item objectForKey:@"module"] pointerValue]
                         subcatFilter:-1];
    } else if ([kind isEqualToString:@"subcat"]) {
        /* core options of that subcategory, like the 3.0 tree */
        module_t *p_core = [self coreModule];
        if (p_core)
            [self rebuildOptionsForModule:p_core
                             subcatFilter:[[item objectForKey:@"id"]
                                              intValue]];
    } else {
        /* category/header row: commit and forget the previous pane BEFORE
         * its controls go away with the document view */
        [self commitAdvancedEntries];
        [advancedEntries removeAllObjects];
        [optionsScroll setDocumentView:
            [[[VLCLegacyFlippedView alloc]
                initWithFrame:NSMakeRect(0, 0, 420, 10)] autorelease]];
    }
}

@end
