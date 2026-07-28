/*****************************************************************************
 * VLCLegacyAudioEffects.m: audio effects window for the legacy interface
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

#import "VLCLegacyAudioEffects.h"
#import "misc.h"
#import "VLCLegacyCoreInteraction.h"

#include <vlc_playlist.h>
#include <vlc_aout.h>
#include <vlc_strings.h>

#include "../../audio_filter/equalizer_presets.h"

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/* NSUserDefaults keys, identical to VLCAudioEffectsWindowController */
#define AE_PROFILES_KEY      @"AudioEffectProfiles"
#define AE_PROFILE_NAMES_KEY @"AudioEffectProfileNames"
#define AE_SELECTED_KEY      @"AudioEffectSelectedProfile"
#define AE_APPLY_ON_STARTUP  @"AudioEffectApplyProfileOnStartup"
#define EQ_VALUES_KEY        @"EQValues"
#define EQ_TITLES_KEY        @"EQTitles"
#define EQ_PREAMP_KEY        @"EQPreampValues"
#define EQ_NAMES_KEY         @"EQNames"

static NSString *B64EncAndFree(char *psz)
{
    if (!psz)
        return @"";
    char *psz_enc = vlc_b64_encode(psz);
    free(psz);
    if (!psz_enc)
        return @"";
    NSString *string = [NSString stringWithUTF8String:psz_enc];
    free(psz_enc);
    return string ? string : @"";
}

static NSString *B64Dec(NSString *string)
{
    if (![string length])
        return @"";
    char *psz_dec = vlc_b64_decode([string UTF8String]);
    if (!psz_dec)
        return @"";
    NSString *decoded = [NSString stringWithUTF8String:psz_dec];
    free(psz_dec);
    return decoded ? decoded : @"";
}

static NSString *defaultAudioProfileString(void)
{
    /* the 3.0.23 default: flat equalizer preset (base64), no filters,
     * stock compressor/spatializer/normalizer values */
    return [NSString stringWithFormat:
        @"ZmxhdA==;;%f;%f;%f;%f;%f;%f;%f;%f;%f;%f;%f;%f;%f;%i",
        .0, 25., 100., -11., 8., 2.5, 7., .85, 1., .4, .5, .5, 2., 0];
}

/* the compressor rows: property, caption msgid, value format, default */
static const struct {
    const char *property;
    const char *title;
    const char *format;
    float reset;
} compressor_rows[7] = {
    { "compressor-rms-peak",    N_("RMS/peak"),    "%1.1f",       0.0f },
    { "compressor-attack",      N_("Attack"),      "%2.1f ms",   25.0f },
    { "compressor-release",     N_("Release"),     "%3.1f ms",  100.0f },
    { "compressor-threshold",   N_("Threshold"),   "%2.1f dB",  -11.0f },
    { "compressor-ratio",       N_("Ratio"),       "%1.1f:1",     8.0f },
    { "compressor-knee",        N_("Knee radius"), "%1.1f dB",    2.5f },
    { "compressor-makeup-gain", N_("Makeup gain"), "%1.1f dB",    7.0f },
};

static const double compressor_ranges[7][2] = {
    { 0, 1 }, { 1.5, 400 }, { 2, 800 }, { -30, 0 }, { 1, 20 }, { 1, 10 },
    { 0, 24 },
};

/* the spatializer rows (UI value = internal value * 10) */
static const struct {
    const char *property;
    const char *title;
    float reset;   /* internal scale */
} spatializer_rows[5] = {
    { "spatializer-roomsize", N_("Size"),  0.85f },
    { "spatializer-width",    N_("Width"), 1.0f },
    { "spatializer-wet",      N_("Wet"),   0.4f },
    { "spatializer-dry",      N_("Dry"),   0.5f },
    { "spatializer-damp",     N_("Damp"),  0.5f },
};

@implementation VLCLegacyAudioEffects

+ (void)initialize
{
    if (self != [VLCLegacyAudioEffects class])
        return;

    /* seed the equalizer preset arrays from the built-in table */
    NSMutableArray *workValues =
        [NSMutableArray arrayWithCapacity:NB_PRESETS];
    NSMutableArray *workPreamp =
        [NSMutableArray arrayWithCapacity:NB_PRESETS];
    NSMutableArray *workTitles =
        [NSMutableArray arrayWithCapacity:NB_PRESETS];
    NSMutableArray *workNames =
        [NSMutableArray arrayWithCapacity:NB_PRESETS];
    int i, j;
    for (i = 0; i < NB_PRESETS; i++) {
        NSMutableString *bands = [NSMutableString string];
        for (j = 0; j < 10; j++) {
            if (j)
                [bands appendString:@" "];
            [bands appendFormat:@"%.1f", eqz_preset_10b[i].f_amp[j]];
        }
        [workValues addObject:bands];
        [workPreamp addObject:[NSString stringWithFormat:@"%1.f",
                               eqz_preset_10b[i].f_preamp]];
        [workTitles addObject:
            [NSString stringWithUTF8String:preset_list_text[i]]];
        [workNames addObject:
            [NSString stringWithUTF8String:preset_list[i]]];
    }

    NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSArray arrayWithObject:defaultAudioProfileString()],
            AE_PROFILES_KEY,
        [NSArray arrayWithObject:_NS("Default")], AE_PROFILE_NAMES_KEY,
        workValues, EQ_VALUES_KEY,
        workPreamp, EQ_PREAMP_KEY,
        workTitles, EQ_TITLES_KEY,
        workNames, EQ_NAMES_KEY,
        nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
{
    if (self = [super init]) {
        core = [interaction retain];
        p_intf = [interaction intf];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults boolForKey:AE_APPLY_ON_STARTUP]) {
            /* create the inherited variables, then load the profile
             * (messages to the not-yet-created widgets are no-ops) */
            [self equalizerUpdated];
            [self resetCompressor];
            [self resetSpatializer];
            [self resetAudioFilters];
            [self loadProfile];
        } else
            [defaults setInteger:0 forKey:AE_SELECTED_KEY];
    }
    return self;
}

- (void)dealloc
{
    [core release];
    [super dealloc];
}

/*****************************************************************************
 * shared helpers (dual write: live aout when it exists + playlist object)
 *****************************************************************************/

- (audio_output_t *)aout
{
    return playlist_GetAout(pl_Get(p_intf));
}

- (void)setAoutFloat:(const char *)name to:(float)value
{
    playlist_t *p_playlist = pl_Get(p_intf);
    audio_output_t *p_aout = [self aout];
    if (p_aout) {
        var_SetFloat(p_aout, name, value);
        vlc_object_release(p_aout);
    }
    var_Create(p_playlist, name, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
    var_SetFloat(p_playlist, name, value);
}

- (void)setAoutString:(const char *)name to:(NSString *)value
{
    playlist_t *p_playlist = pl_Get(p_intf);
    audio_output_t *p_aout = [self aout];
    if (p_aout) {
        var_SetString(p_aout, name, [value UTF8String]);
        vlc_object_release(p_aout);
    }
    var_Create(p_playlist, name, VLC_VAR_STRING | VLC_VAR_DOINHERIT);
    var_SetString(p_playlist, name, [value UTF8String]);
}

- (void)setAoutBool:(const char *)name to:(BOOL)value
{
    playlist_t *p_playlist = pl_Get(p_intf);
    audio_output_t *p_aout = [self aout];
    if (p_aout) {
        var_SetBool(p_aout, name, value);
        vlc_object_release(p_aout);
    }
    var_Create(p_playlist, name, VLC_VAR_BOOL | VLC_VAR_DOINHERIT);
    var_SetBool(p_playlist, name, value);
}

- (float)floatValue:(const char *)name
{
    playlist_t *p_playlist = pl_Get(p_intf);
    var_Create(p_playlist, name, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
    return var_GetFloat(p_playlist, name);
}

- (void)setAudioFilter:(const char *)name on:(BOOL)on
{
    playlist_EnableAudioFilter(pl_Get(p_intf), name, on);
}

- (BOOL)audioFilterOn:(const char *)name
{
    char *psz_filters = var_InheritString(pl_Get(p_intf), "audio-filter");
    BOOL enabled = psz_filters && strstr(psz_filters, name) != NULL;
    free(psz_filters);
    return enabled;
}

/*****************************************************************************
 * window construction
 *****************************************************************************/

- (NSView *)buildEqualizerPane:(NSSize)size
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)]
        autorelease];
    float top = size.height;

    equalizerEnableCheckbox = [self hudCheckbox:_NS("Enable")
        frame:NSMakeRect(8, top - 24, 90, 18)
       action:@selector(equalizerEnable:) in:pane];
    equalizerTwoPassCheckbox = [self hudCheckbox:_NS("2 Pass")
        frame:NSMakeRect(104, top - 24, 84, 18)
       action:@selector(equalizerTwoPass:) in:pane];
    [equalizerTwoPassCheckbox setToolTip:
        _NS("Filter the audio twice. This provides a more intense effect.")];
    equalizerPresetsPopup = [self hudPopup:
        NSMakeRect(size.width - 216, top - 28, 208, 22)
       action:@selector(equalizerChangePreset:) in:pane];

    /* preamp column, then the ten bands */
    float slidersTop = top - 44;
    float slidersHeight = slidersTop - 46;
    equalizerPreampSlider = [self hudSlider:
        NSMakeRect(14, 46, 21, slidersHeight)
        min:-20 max:20 action:@selector(equalizerPreAmpSliderUpdated:)
         in:pane];
    [equalizerPreampSlider setNumberOfTickMarks:9];
    NSTextField *preampLabel = [self hudLabel:_NS("Preamp")
        frame:NSMakeRect(0, 26, 52, 14) bold:NO in:pane];
    [preampLabel setAlignment:NSCenterTextAlignment];
    [preampLabel setToolTip:
        _NS("Set the global gain in dB (-20 ... 20).")];

    /* scale marks next to the preamp */
    [self hudLabel:@"+20 dB" frame:NSMakeRect(36, slidersTop - 14, 46, 12)
              bold:NO in:pane];
    [self hudLabel:@"0 dB"
             frame:NSMakeRect(36, 46 + slidersHeight / 2 - 6, 46, 12)
              bold:NO in:pane];
    [self hudLabel:@"-20 dB" frame:NSMakeRect(36, 46, 46, 12)
              bold:NO in:pane];

    int i;
    for (i = 0; i < LEGACY_EQ_BANDS; i++) {
        float x = 92 + i * 38;
        equalizerBandSliders[i] = [self hudSlider:
            NSMakeRect(x, 46, 21, slidersHeight)
            min:-20 max:20 action:@selector(equalizerBandSliderUpdated:)
             in:pane];
        [equalizerBandSliders[i] setNumberOfTickMarks:9];
        equalizerBandFields[i] = [self hudLabel:@""
            frame:NSMakeRect(x - 12, 26, 44, 14) bold:NO in:pane];
        [equalizerBandFields[i] setAlignment:NSCenterTextAlignment];
    }

    return pane;
}

- (NSView *)buildCompressorPane:(NSSize)size
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)]
        autorelease];
    float top = size.height;

    compressorEnableCheckbox =
        [self hudCheckbox:_NS("Enable dynamic range compressor")
                    frame:NSMakeRect(8, top - 24, 300, 18)
                   action:@selector(compressorEnable:) in:pane];
    compressorResetButton = [self hudPushButton:_NS("Reset")
        frame:NSMakeRect(size.width - 88, top - 28, 80, 22)
       action:@selector(resetCompressorValues:) in:pane];

    float slidersTop = top - 44;
    float slidersHeight = slidersTop - 74;
    int i;
    for (i = 0; i < 7; i++) {
        float x = 20 + i * 66;
        compressorSliders[i] = [self hudSlider:
            NSMakeRect(x + 14, 74, 21, slidersHeight)
            min:compressor_ranges[i][0] max:compressor_ranges[i][1]
            action:@selector(compressorSliderUpdated:) in:pane];
        compressorFields[i] = [self hudLabel:@""
            frame:NSMakeRect(x - 6, 54, 62, 14) bold:NO in:pane];
        [compressorFields[i] setAlignment:NSCenterTextAlignment];
        /* wrapped: several localized captions do not fit one column */
        NSTextField *caption = [self hudLabel:_NS(compressor_rows[i].title)
            frame:NSMakeRect(x - 6, 8, 62, 42) bold:NO in:pane];
        [caption setAlignment:NSCenterTextAlignment];
        [[caption cell] setWraps:YES];
        VLCLegacySetCellLineBreakMode([caption cell], NSLineBreakByWordWrapping);
    }

    return pane;
}

- (NSView *)buildSpatializerPane:(NSSize)size
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)]
        autorelease];
    float top = size.height;

    spatializerEnableCheckbox =
        [self hudCheckbox:_NS("Enable Spatializer")
                    frame:NSMakeRect(8, top - 24, 300, 18)
                   action:@selector(spatializerEnable:) in:pane];
    spatializerResetButton = [self hudPushButton:_NS("Reset")
        frame:NSMakeRect(size.width - 88, top - 28, 80, 22)
       action:@selector(resetSpatializerValues:) in:pane];

    float slidersTop = top - 44;
    float slidersHeight = slidersTop - 66;
    int i;
    for (i = 0; i < 5; i++) {
        float x = 48 + i * 84;
        spatializerSliders[i] = [self hudSlider:
            NSMakeRect(x + 20, 66, 21, slidersHeight)
            min:0 max:10 action:@selector(spatializerSliderUpdated:)
             in:pane];
        spatializerFields[i] = [self hudLabel:@""
            frame:NSMakeRect(x - 6, 46, 72, 14) bold:NO in:pane];
        [spatializerFields[i] setAlignment:NSCenterTextAlignment];
        NSTextField *caption = [self hudLabel:_NS(spatializer_rows[i].title)
            frame:NSMakeRect(x - 6, 26, 72, 14) bold:NO in:pane];
        [caption setAlignment:NSCenterTextAlignment];
    }
    [spatializerSliders[0] setToolTip:_NS("Defines the virtual surface of "
        "the room emulated by the filter.")];
    [spatializerSliders[1] setToolTip:_NS("Width of the virtual room")];

    return pane;
}

- (NSView *)buildFilterPane:(NSSize)size
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)]
        autorelease];
    float top = size.height;

    filterNormLevelCheckbox =
        [self hudCheckbox:_NS("Volume normalization")
                    frame:NSMakeRect(8, top - 24, 300, 18)
                   action:@selector(filterEnableVolumeNorm:) in:pane];
    [filterNormLevelCheckbox setToolTip:_NS("Volume normalizer")];
    filterNormLevelLabel = [self hudLabel:_NS("Maximum level")
        frame:NSMakeRect(28, top - 48, 130, 14) bold:NO in:pane];
    filterNormLevelSlider = [self hudSlider:
        NSMakeRect(164, top - 52, 240, 19)
        min:0.1 max:10 action:@selector(filterVolumeNormSliderUpdated:)
         in:pane];

    filterKaraokeCheckbox = [self hudCheckbox:_NS("Karaoke")
        frame:NSMakeRect(8, top - 88, 300, 18)
       action:@selector(filterEnableKaraoke:) in:pane];
    [filterKaraokeCheckbox setToolTip:_NS("Simple Karaoke filter")];

    filterHeadPhoneCheckbox =
        [self hudCheckbox:_NS("Headphone virtualization")
                    frame:NSMakeRect(8, top - 116, 300, 18)
                   action:@selector(filterEnableHeadPhoneVirt:) in:pane];

    filterScaleTempoCheckbox = [self hudCheckbox:_NS("Scaletempo")
        frame:NSMakeRect(8, top - 144, 300, 18)
       action:@selector(filterEnableScaleTempo:) in:pane];
    [filterScaleTempoCheckbox setToolTip:
        _NS("Audio tempo scaler synched with rate")];

    filterStereoEnhancerCheckbox =
        [self hudCheckbox:_NS("Stereo Enhancer")
                    frame:NSMakeRect(8, top - 172, 300, 18)
                   action:@selector(filterEnableStereoEnhancer:) in:pane];

    return pane;
}

- (void)buildWindow
{
    [self buildHUDWithTitle:_NS("Audio Effects")
                       size:NSMakeSize(500, 380)
                  tabTitles:[NSArray arrayWithObjects:
                                _NS("Equalizer"), _NS("Compressor"),
                                _NS("Spatializer"), _NS("Filter"), nil]
               bottomMargin:44];

    NSSize paneSize = [[self paneContainer] bounds].size;
    [self setPane:[self buildEqualizerPane:paneSize] atIndex:0];
    [self setPane:[self buildCompressorPane:paneSize] atIndex:1];
    [self setPane:[self buildSpatializerPane:paneSize] atIndex:2];
    [self setPane:[self buildFilterPane:paneSize] atIndex:3];

    NSView *content = [window contentView];
    profilePopup = [self hudPopup:NSMakeRect(17, 10, 190, 22)
                           action:@selector(profileSelectorAction:)
                               in:content];
    applyProfileCheckbox =
        [self hudCheckbox:_NS("Apply profile at next launch")
                    frame:NSMakeRect(218, 12, 270, 18)
                   action:@selector(applyProfileCheckboxChanged:)
                       in:content];
    [applyProfileCheckbox setState:
        [[NSUserDefaults standardUserDefaults] boolForKey:AE_APPLY_ON_STARTUP]
            ? NSOnState : NSOffState];

    [self resetProfileSelector];
}

- (void)windowWillShow
{
    [self equalizerUpdated];
    [self resetCompressor];
    [self resetSpatializer];
    [self resetAudioFilters];
    [self updatePresetSelector];
}

/*****************************************************************************
 * Equalizer pane
 *****************************************************************************/

- (void)setBandSliderValuesForPreset:(NSInteger)presetIndex
{
    NSArray *values = [[NSUserDefaults standardUserDefaults]
        objectForKey:EQ_VALUES_KEY];
    if (presetIndex < 0 || (unsigned)presetIndex >= [values count])
        return;
    NSArray *bands = [[values objectAtIndex:presetIndex]
        componentsSeparatedByString:@" "];
    int i;
    for (i = 0; i < LEGACY_EQ_BANDS && (unsigned)i < [bands count]; i++)
        [equalizerBandSliders[i] setFloatValue:
            [[bands objectAtIndex:i] floatValue]];
}

- (NSString *)generatePresetString
{
    NSMutableString *bands = [NSMutableString string];
    int i;
    for (i = 0; i < LEGACY_EQ_BANDS; i++) {
        if (i)
            [bands appendString:@" "];
        [bands appendFormat:@"%.1f",
            [equalizerBandSliders[i] floatValue]];
    }
    return bands;
}

- (void)setBandsFromSliders
{
    NSString *bands = [self generatePresetString];
    [self setAoutString:"equalizer-bands" to:bands];
}

- (void)equalizerUpdated
{
    playlist_t *p_playlist = pl_Get(p_intf);
    var_Create(p_playlist, "equalizer-preset",
               VLC_VAR_STRING | VLC_VAR_DOINHERIT);
    var_Create(p_playlist, "equalizer-bands",
               VLC_VAR_STRING | VLC_VAR_DOINHERIT);
    var_Create(p_playlist, "equalizer-preamp",
               VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
    var_Create(p_playlist, "equalizer-2pass",
               VLC_VAR_BOOL | VLC_VAR_DOINHERIT);

    BOOL enabled = [self audioFilterOn:"equalizer"];
    [equalizerEnableCheckbox setState:enabled ? NSOnState : NSOffState];
    [equalizerTwoPassCheckbox setState:
        var_GetBool(p_playlist, "equalizer-2pass") ? NSOnState : NSOffState];
    [self setEqualizerControlsEnabled:enabled];

    /* frequency captions depend on equalizer-vlcfreqs */
    BOOL vlcFreqs = var_InheritBool(p_playlist, "equalizer-vlcfreqs");
    static const char *const vlc_freqs[10] =
        { "60", "170", "310", "600", "1K", "3K", "6K", "12K", "14K", "16K" };
    static const char *const iso_freqs[10] =
        { "31", "63", "125", "250", "500", "1K", "2K", "4K", "8K", "16K" };
    const char *const *freqs = vlcFreqs ? vlc_freqs : iso_freqs;
    int i;
    for (i = 0; i < LEGACY_EQ_BANDS; i++)
        [equalizerBandFields[i] setStringValue:
            [NSString stringWithUTF8String:freqs[i]]];

    /* current values */
    [equalizerPreampSlider setFloatValue:
        [self floatValue:"equalizer-preamp"]];
    char *psz_bands = var_InheritString(p_playlist, "equalizer-bands");
    if (psz_bands) {
        const char *p = psz_bands;
        for (i = 0; i < LEGACY_EQ_BANDS; i++) {
            char *next;
            float value = strtof(p, &next);
            if (next == p)
                break;
            [equalizerBandSliders[i] setFloatValue:value];
            p = next;
        }
        free(psz_bands);
    }
}

- (void)setEqualizerControlsEnabled:(BOOL)enabled
{
    [equalizerPreampSlider setEnabled:enabled];
    int i;
    for (i = 0; i < LEGACY_EQ_BANDS; i++)
        [equalizerBandSliders[i] setEnabled:enabled];
}

- (void)updatePresetSelector
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *titles = [defaults objectForKey:EQ_TITLES_KEY];
    NSArray *names = [defaults objectForKey:EQ_NAMES_KEY];

    [equalizerPresetsPopup removeAllItems];
    unsigned i;
    for (i = 0; i < [titles count]; i++)
        [[equalizerPresetsPopup menu] addItem:[[[NSMenuItem alloc]
            initWithTitle:[titles objectAtIndex:i]
                   action:nil keyEquivalent:@""] autorelease]];
    [[equalizerPresetsPopup menu] addItem:[NSMenuItem separatorItem]];
    NSMenuItem *item = [[[NSMenuItem alloc]
        initWithTitle:_NS("Add new Preset...")
               action:@selector(addPresetAction:) keyEquivalent:@""]
        autorelease];
    [item setTarget:self];
    [[equalizerPresetsPopup menu] addItem:item];
    if ([names count] > 1) {
        item = [[[NSMenuItem alloc]
            initWithTitle:_NS("Organize Presets...")
                   action:@selector(deletePresetAction:) keyEquivalent:@""]
            autorelease];
        [item setTarget:self];
        [[equalizerPresetsPopup menu] addItem:item];
    }

    /* select the entry matching the current preset name */
    playlist_t *p_playlist = pl_Get(p_intf);
    char *psz_preset = var_GetNonEmptyString(p_playlist,
                                             "equalizer-preset");
    NSInteger selected = 0;
    if (psz_preset) {
        NSString *preset = [NSString stringWithUTF8String:psz_preset];
        NSUInteger found = [names indexOfObject:preset];
        if (found != NSNotFound)
            selected = (NSInteger)found;
        free(psz_preset);
    }
    if ((unsigned)selected >= [titles count])
        selected = 0;
    [equalizerPresetsPopup selectItemAtIndex:selected];

    /* mirror the preset in the sliders */
    NSArray *preamps = [defaults objectForKey:EQ_PREAMP_KEY];
    if ((unsigned)selected < [preamps count])
        [equalizerPreampSlider setFloatValue:
            [[preamps objectAtIndex:selected] floatValue]];
    [self setBandSliderValuesForPreset:selected];
}

- (void)equalizerEnable:(id)sender
{
    BOOL on = [sender state] == NSOnState;
    [self setAudioFilter:"equalizer" on:on];
    [self setEqualizerControlsEnabled:on];
}

- (void)equalizerTwoPass:(id)sender
{
    [self setAoutBool:"equalizer-2pass" to:[sender state] == NSOnState];
}

- (void)equalizerChangePreset:(id)sender
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger index = [equalizerPresetsPopup indexOfSelectedItem];
    NSArray *values = [defaults objectForKey:EQ_VALUES_KEY];
    NSArray *preamps = [defaults objectForKey:EQ_PREAMP_KEY];
    NSArray *names = [defaults objectForKey:EQ_NAMES_KEY];
    if (index < 0 || (unsigned)index >= [values count])
        return;

    [self setAoutString:"equalizer-bands"
                     to:[values objectAtIndex:index]];
    [self setAoutFloat:"equalizer-preamp"
                    to:[[preamps objectAtIndex:index] floatValue]];
    [self setAoutString:"equalizer-preset"
                     to:[names objectAtIndex:index]];

    [equalizerPreampSlider setFloatValue:
        [[preamps objectAtIndex:index] floatValue]];
    [self setBandSliderValuesForPreset:index];
}

- (void)equalizerPreAmpSliderUpdated:(id)sender
{
    [self setAoutFloat:"equalizer-preamp" to:[sender floatValue]];
}

- (void)equalizerBandSliderUpdated:(id)sender
{
    [self setBandsFromSliders];
}

- (void)addPresetAction:(id)sender
{
    /* restore the popup selection stolen by the action item */
    [self updatePresetSelector];

    NSString *text = VLCLegacyRunTextPrompt(
        _NS("Save current selection as new preset"),
        _NS("Enter a name for the new preset:"),
        _NS("Save"), _NS("Cancel"), @"");
    if (![text length])
        return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *values = [NSMutableArray arrayWithArray:
        [defaults objectForKey:EQ_VALUES_KEY]];
    NSMutableArray *titles = [NSMutableArray arrayWithArray:
        [defaults objectForKey:EQ_TITLES_KEY]];
    NSMutableArray *preamps = [NSMutableArray arrayWithArray:
        [defaults objectForKey:EQ_PREAMP_KEY]];
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [defaults objectForKey:EQ_NAMES_KEY]];

    [values addObject:[self generatePresetString]];
    [titles addObject:text];
    [preamps addObject:[NSString stringWithFormat:@"%.1f",
                        [equalizerPreampSlider floatValue]]];
    NSString *canonical = [text decomposedStringWithCanonicalMapping];
    [names addObject:canonical];

    [defaults setObject:values forKey:EQ_VALUES_KEY];
    [defaults setObject:titles forKey:EQ_TITLES_KEY];
    [defaults setObject:preamps forKey:EQ_PREAMP_KEY];
    [defaults setObject:names forKey:EQ_NAMES_KEY];
    [defaults synchronize];

    [self setAoutString:"equalizer-preset" to:canonical];
    [self updatePresetSelector];
}

- (void)deletePresetAction:(id)sender
{
    [self updatePresetSelector];

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger index = VLCLegacyRunPopupPrompt(
        _NS("Remove a preset"),
        _NS("Select the preset you would like to remove:"),
        _NS("Remove"), _NS("Cancel"),
        [defaults objectForKey:EQ_TITLES_KEY]);
    if (index < 0)
        return;

    NSMutableArray *values = [NSMutableArray arrayWithArray:
        [defaults objectForKey:EQ_VALUES_KEY]];
    NSMutableArray *titles = [NSMutableArray arrayWithArray:
        [defaults objectForKey:EQ_TITLES_KEY]];
    NSMutableArray *preamps = [NSMutableArray arrayWithArray:
        [defaults objectForKey:EQ_PREAMP_KEY]];
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [defaults objectForKey:EQ_NAMES_KEY]];
    if ((unsigned)index >= [values count])
        return;
    [values removeObjectAtIndex:index];
    [titles removeObjectAtIndex:index];
    [preamps removeObjectAtIndex:index];
    [names removeObjectAtIndex:index];
    [defaults setObject:values forKey:EQ_VALUES_KEY];
    [defaults setObject:titles forKey:EQ_TITLES_KEY];
    [defaults setObject:preamps forKey:EQ_PREAMP_KEY];
    [defaults setObject:names forKey:EQ_NAMES_KEY];
    [defaults synchronize];

    [self updatePresetSelector];
}

/*****************************************************************************
 * Compressor pane
 *****************************************************************************/

- (void)setCompressorControlsEnabled:(BOOL)enabled
{
    int i;
    for (i = 0; i < 7; i++)
        [compressorSliders[i] setEnabled:enabled];
    [compressorResetButton setEnabled:enabled];
}

- (void)updateCompressorField:(int)index
{
    [compressorFields[index] setStringValue:
        [NSString stringWithFormat:
            [NSString stringWithUTF8String:compressor_rows[index].format],
            [compressorSliders[index] floatValue]]];
}

- (void)resetCompressor
{
    BOOL enabled = [self audioFilterOn:"compressor"];
    [compressorEnableCheckbox setState:enabled ? NSOnState : NSOffState];
    [self setCompressorControlsEnabled:enabled];

    int i;
    for (i = 0; i < 7; i++) {
        [compressorSliders[i] setFloatValue:
            [self floatValue:compressor_rows[i].property]];
        [self updateCompressorField:i];
    }
}

- (void)compressorEnable:(id)sender
{
    BOOL on = [sender state] == NSOnState;
    [self setAudioFilter:"compressor" on:on];
    [self setCompressorControlsEnabled:on];
}

- (void)compressorSliderUpdated:(id)sender
{
    int i;
    for (i = 0; i < 7; i++) {
        if (sender == compressorSliders[i]) {
            [self setAoutFloat:compressor_rows[i].property
                            to:[sender floatValue]];
            [self updateCompressorField:i];
            break;
        }
    }
}

- (void)resetCompressorValues:(id)sender
{
    int i;
    for (i = 0; i < 7; i++) {
        [self setAoutFloat:compressor_rows[i].property
                        to:compressor_rows[i].reset];
        [compressorSliders[i] setFloatValue:compressor_rows[i].reset];
        [self updateCompressorField:i];
    }
}

/*****************************************************************************
 * Spatializer pane (UI values are the internal ones times ten)
 *****************************************************************************/

- (void)setSpatializerControlsEnabled:(BOOL)enabled
{
    int i;
    for (i = 0; i < 5; i++)
        [spatializerSliders[i] setEnabled:enabled];
    [spatializerResetButton setEnabled:enabled];
}

- (void)resetSpatializer
{
    BOOL enabled = [self audioFilterOn:"spatializer"];
    [spatializerEnableCheckbox setState:enabled ? NSOnState : NSOffState];
    [self setSpatializerControlsEnabled:enabled];

    int i;
    for (i = 0; i < 5; i++) {
        float value = [self floatValue:spatializer_rows[i].property] * 10.f;
        [spatializerSliders[i] setFloatValue:value];
        [spatializerFields[i] setStringValue:
            [NSString stringWithFormat:@"%1.1f", value]];
    }
}

- (void)spatializerEnable:(id)sender
{
    BOOL on = [sender state] == NSOnState;
    [self setAudioFilter:"spatializer" on:on];
    [self setSpatializerControlsEnabled:on];
}

- (void)spatializerSliderUpdated:(id)sender
{
    int i;
    for (i = 0; i < 5; i++) {
        if (sender == spatializerSliders[i]) {
            [self setAoutFloat:spatializer_rows[i].property
                            to:[sender floatValue] / 10.f];
            [spatializerFields[i] setStringValue:
                [NSString stringWithFormat:@"%1.1f", [sender floatValue]]];
            break;
        }
    }
}

- (void)resetSpatializerValues:(id)sender
{
    int i;
    for (i = 0; i < 5; i++) {
        [self setAoutFloat:spatializer_rows[i].property
                        to:spatializer_rows[i].reset];
        [spatializerSliders[i] setFloatValue:
            spatializer_rows[i].reset * 10.f];
        [spatializerFields[i] setStringValue:
            [NSString stringWithFormat:@"%1.1f",
                spatializer_rows[i].reset * 10.f]];
    }
}

/*****************************************************************************
 * Filter pane
 *****************************************************************************/

- (void)resetAudioFilters
{
    BOOL norm = [self audioFilterOn:"normvol"];
    [filterNormLevelCheckbox setState:norm ? NSOnState : NSOffState];
    [filterNormLevelSlider setEnabled:norm];
    [filterNormLevelSlider setFloatValue:
        [self floatValue:"norm-max-level"]];
    [filterKaraokeCheckbox setState:
        [self audioFilterOn:"karaoke"] ? NSOnState : NSOffState];
    [filterHeadPhoneCheckbox setState:
        [self audioFilterOn:"headphone"] ? NSOnState : NSOffState];
    [filterScaleTempoCheckbox setState:
        [self audioFilterOn:"scaletempo"] ? NSOnState : NSOffState];
    [filterStereoEnhancerCheckbox setState:
        [self audioFilterOn:"stereo_widen"] ? NSOnState : NSOffState];
}

- (void)filterEnableVolumeNorm:(id)sender
{
    BOOL on = [sender state] == NSOnState;
    [self setAudioFilter:"normvol" on:on];
    [filterNormLevelSlider setEnabled:on];
}

- (void)filterVolumeNormSliderUpdated:(id)sender
{
    [self setAoutFloat:"norm-max-level" to:[sender floatValue]];
}

- (void)filterEnableKaraoke:(id)sender
{
    [self setAudioFilter:"karaoke" on:[sender state] == NSOnState];
}

- (void)filterEnableHeadPhoneVirt:(id)sender
{
    [self setAudioFilter:"headphone" on:[sender state] == NSOnState];
}

- (void)filterEnableScaleTempo:(id)sender
{
    [self setAudioFilter:"scaletempo" on:[sender state] == NSOnState];
}

- (void)filterEnableStereoEnhancer:(id)sender
{
    [self setAudioFilter:"stereo_widen" on:[sender state] == NSOnState];
}

/*****************************************************************************
 * profiles
 *****************************************************************************/

- (NSInteger)currentProfileIndex
{
    return [[NSUserDefaults standardUserDefaults]
        integerForKey:AE_SELECTED_KEY];
}

- (NSArray *)nonDefaultProfileNames
{
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [[NSUserDefaults standardUserDefaults]
            objectForKey:AE_PROFILE_NAMES_KEY]];
    if ([names count])
        [names removeObjectAtIndex:0];
    return names;
}

- (NSString *)generateProfileString
{
    playlist_t *p_playlist = pl_Get(p_intf);
    return [NSString stringWithFormat:
        @"%@;%@;%f;%f;%f;%f;%f;%f;%f;%f;%f;%f;%f;%f;%f;%i",
        B64EncAndFree(var_GetNonEmptyString(p_playlist,
                                            "equalizer-preset")),
        B64EncAndFree(var_InheritString(p_playlist, "audio-filter")),
        var_InheritFloat(p_playlist, "compressor-rms-peak"),
        var_InheritFloat(p_playlist, "compressor-attack"),
        var_InheritFloat(p_playlist, "compressor-release"),
        var_InheritFloat(p_playlist, "compressor-threshold"),
        var_InheritFloat(p_playlist, "compressor-ratio"),
        var_InheritFloat(p_playlist, "compressor-knee"),
        var_InheritFloat(p_playlist, "compressor-makeup-gain"),
        var_InheritFloat(p_playlist, "spatializer-roomsize"),
        var_InheritFloat(p_playlist, "spatializer-width"),
        var_InheritFloat(p_playlist, "spatializer-wet"),
        var_InheritFloat(p_playlist, "spatializer-dry"),
        var_InheritFloat(p_playlist, "spatializer-damp"),
        var_InheritFloat(p_playlist, "norm-max-level"),
        (int)var_InheritBool(p_playlist, "equalizer-2pass")];
}

- (void)loadProfile
{
    playlist_t *p_playlist = pl_Get(p_intf);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger profileIndex = [self currentProfileIndex];
    NSString *profileString;

    if (profileIndex == 0)
        profileString = defaultAudioProfileString();
    else {
        NSArray *profiles = [defaults objectForKey:AE_PROFILES_KEY];
        if (profileIndex < 0 || (unsigned)profileIndex >= [profiles count])
            return;
        profileString = [profiles objectAtIndex:profileIndex];
    }

    /* disable each effect filter, the saved audio-filter list re-enables
     * exactly the stored set below */
    [self setAudioFilter:"equalizer" on:NO];
    [self setAudioFilter:"compressor" on:NO];
    [self setAudioFilter:"spatializer" on:NO];
    [self setAudioFilter:"headphone" on:NO];
    [self setAudioFilter:"normvol" on:NO];
    [self setAudioFilter:"karaoke" on:NO];

    NSArray *items = [profileString componentsSeparatedByString:@";"];
    if ([items count] < 16) {
        msg_Err(p_intf, "Error in parsing audio profile string");
        return;
    }

    NSString *presetName = B64Dec([items objectAtIndex:0]);
    NSString *audioFilters = B64Dec([items objectAtIndex:1]);
    [self setAoutString:"equalizer-preset" to:presetName];
    [self setAoutString:"audio-filter" to:audioFilters];

#define ITEM_F(idx) [[items objectAtIndex:idx] floatValue]
    [self setAoutFloat:"compressor-rms-peak" to:ITEM_F(2)];
    [self setAoutFloat:"compressor-attack" to:ITEM_F(3)];
    [self setAoutFloat:"compressor-release" to:ITEM_F(4)];
    [self setAoutFloat:"compressor-threshold" to:ITEM_F(5)];
    [self setAoutFloat:"compressor-ratio" to:ITEM_F(6)];
    [self setAoutFloat:"compressor-knee" to:ITEM_F(7)];
    [self setAoutFloat:"compressor-makeup-gain" to:ITEM_F(8)];
    [self setAoutFloat:"spatializer-roomsize" to:ITEM_F(9)];
    [self setAoutFloat:"spatializer-width" to:ITEM_F(10)];
    [self setAoutFloat:"spatializer-wet" to:ITEM_F(11)];
    [self setAoutFloat:"spatializer-dry" to:ITEM_F(12)];
    [self setAoutFloat:"spatializer-damp" to:ITEM_F(13)];
    [self setAoutFloat:"norm-max-level" to:ITEM_F(14)];
#undef ITEM_F
    [self setAoutBool:"equalizer-2pass"
                   to:[[items objectAtIndex:15] intValue] != 0];

    /* apply the equalizer preset stored with the profile */
    NSArray *names = [defaults objectForKey:EQ_NAMES_KEY];
    NSUInteger presetIndex = [names indexOfObject:presetName];
    if (presetIndex == NSNotFound)
        presetIndex = 0;
    NSArray *values = [defaults objectForKey:EQ_VALUES_KEY];
    NSArray *preamps = [defaults objectForKey:EQ_PREAMP_KEY];
    if (presetIndex < [values count]) {
        [self setAoutString:"equalizer-bands"
                         to:[values objectAtIndex:presetIndex]];
        [self setAoutFloat:"equalizer-preamp"
                        to:[[preamps objectAtIndex:presetIndex]
                               floatValue]];
        [self setAoutString:"equalizer-preset"
                         to:[names objectAtIndex:presetIndex]];
    }
}

- (void)resetProfileSelector
{
    [profilePopup removeAllItems];

    [profilePopup addItemWithTitle:_NS("Default")];
    NSArray *nonDefault = [self nonDefaultProfileNames];
    unsigned i;
    for (i = 0; i < [nonDefault count]; i++)
        [[profilePopup menu] addItem:[[[NSMenuItem alloc]
            initWithTitle:[nonDefault objectAtIndex:i]
                   action:nil keyEquivalent:@""] autorelease]];

    [[profilePopup menu] addItem:[NSMenuItem separatorItem]];
    NSMenuItem *item = [[[NSMenuItem alloc]
        initWithTitle:_NS("Duplicate current profile...")
               action:@selector(addAudioEffectsProfile:) keyEquivalent:@""]
        autorelease];
    [item setTarget:self];
    [[profilePopup menu] addItem:item];
    if ([nonDefault count]) {
        item = [[[NSMenuItem alloc]
            initWithTitle:_NS("Organize Profiles...")
                   action:@selector(removeAudioEffectsProfile:)
            keyEquivalent:@""] autorelease];
        [item setTarget:self];
        [[profilePopup menu] addItem:item];
    }

    NSInteger selected = [self currentProfileIndex];
    if (selected < 0 || (unsigned)selected >= [nonDefault count] + 1)
        selected = 0;
    [profilePopup selectItemAtIndex:selected];
    if (selected > 0)
        [self profileSelectorAction:profilePopup];
}

- (void)saveCurrentProfile
{
    NSInteger index = [self currentProfileIndex];
    if (index <= 0)
        return;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *profiles = [NSMutableArray arrayWithArray:
        [defaults objectForKey:AE_PROFILES_KEY]];
    if ((unsigned)index >= [profiles count])
        return;
    [profiles replaceObjectAtIndex:index
                        withObject:[self generateProfileString]];
    [defaults setObject:profiles forKey:AE_PROFILES_KEY];
    [defaults synchronize];
}

- (void)saveCurrentProfileAtTerminate
{
    if ([self currentProfileIndex] > 0) {
        [self saveCurrentProfile];
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *profileString = [self generateProfileString];
    if (![defaults boolForKey:AE_APPLY_ON_STARTUP]
     || [profileString isEqualToString:defaultAudioProfileString()])
        return;

    NSMutableArray *profiles = [NSMutableArray arrayWithArray:
        [defaults objectForKey:AE_PROFILES_KEY]];
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [defaults objectForKey:AE_PROFILE_NAMES_KEY]];
    int number = 0;
    NSString *name;
    do {
        name = [NSString stringWithFormat:@"Custom%03i", number++];
    } while ([names containsObject:name]);
    [profiles addObject:profileString];
    [names addObject:name];
    [defaults setObject:profiles forKey:AE_PROFILES_KEY];
    [defaults setObject:names forKey:AE_PROFILE_NAMES_KEY];
    [defaults setInteger:(NSInteger)[profiles count] - 1
                  forKey:AE_SELECTED_KEY];
    [defaults synchronize];
}

- (void)profileSelectorAction:(id)sender
{
    [self saveCurrentProfile];
    [[NSUserDefaults standardUserDefaults]
        setInteger:[profilePopup indexOfSelectedItem]
            forKey:AE_SELECTED_KEY];
    [self loadProfile];
    [self equalizerUpdated];
    [self resetCompressor];
    [self resetSpatializer];
    [self resetAudioFilters];
    [self updatePresetSelector];
}

- (void)addAudioEffectsProfile:(id)sender
{
    [profilePopup selectItemAtIndex:[self currentProfileIndex]];

    NSString *name = VLCLegacyRunTextPrompt(
        _NS("Duplicate current profile for a new profile"),
        _NS("Enter a name for the new profile:"),
        _NS("Save"), _NS("Cancel"), @"");
    if (!name)
        return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [defaults objectForKey:AE_PROFILE_NAMES_KEY]];
    if (![name length] || [names containsObject:name]) {
        NSRunAlertPanel(_NS("Please enter a unique name for the new "
                            "profile."),
                        @"%@", _NS("OK"), nil, nil,
                        _NS("Multiple profiles with the same name are not "
                            "allowed."));
        return;
    }

    NSMutableArray *profiles = [NSMutableArray arrayWithArray:
        [defaults objectForKey:AE_PROFILES_KEY]];
    [profiles addObject:[self generateProfileString]];
    [names addObject:name];
    [defaults setObject:profiles forKey:AE_PROFILES_KEY];
    [defaults setObject:names forKey:AE_PROFILE_NAMES_KEY];
    [defaults setInteger:(NSInteger)[profiles count] - 1
                  forKey:AE_SELECTED_KEY];
    [defaults synchronize];
    [self resetProfileSelector];
}

- (void)removeAudioEffectsProfile:(id)sender
{
    [profilePopup selectItemAtIndex:[self currentProfileIndex]];

    NSInteger index = VLCLegacyRunPopupPrompt(
        _NS("Remove a preset"),
        _NS("Select the preset you would like to remove:"),
        _NS("Remove"), _NS("Cancel"),
        [self nonDefaultProfileNames]);
    if (index < 0)
        return;
    index++;   /* Default is not offered for removal */

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *profiles = [NSMutableArray arrayWithArray:
        [defaults objectForKey:AE_PROFILES_KEY]];
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [defaults objectForKey:AE_PROFILE_NAMES_KEY]];
    if ((unsigned)index >= [profiles count])
        return;
    [profiles removeObjectAtIndex:index];
    [names removeObjectAtIndex:index];
    [defaults setObject:profiles forKey:AE_PROFILES_KEY];
    [defaults setObject:names forKey:AE_PROFILE_NAMES_KEY];
    if ([self currentProfileIndex] >= index)
        [defaults setInteger:[self currentProfileIndex] - 1
                      forKey:AE_SELECTED_KEY];
    [defaults synchronize];
    [self resetProfileSelector];
}

- (void)applyProfileCheckboxChanged:(id)sender
{
    [[NSUserDefaults standardUserDefaults]
        setBool:[sender state] == NSOnState forKey:AE_APPLY_ON_STARTUP];
}

@end
