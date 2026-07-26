/*****************************************************************************
 * VLCLegacyVideoEffects.m: video effects window for the legacy interface
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

#import "VLCLegacyVideoEffects.h"
#import "VLCLegacyCoreInteraction.h"

#include <vlc_playlist.h>
#include <vlc_input.h>
#include <vlc_vout.h>
#include <vlc_configuration.h>
#include <vlc_strings.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

/* NSUserDefaults keys, identical to VLCVideoEffectsWindowController so a
 * profile created with the modern interface keeps working here */
#define VE_PROFILES_KEY        @"VideoEffectProfiles"
#define VE_PROFILE_NAMES_KEY   @"VideoEffectProfileNames"
#define VE_SELECTED_KEY        @"VideoEffectSelectedProfile"
#define VE_APPLY_ON_STARTUP    @"VideoEffectApplyProfileOnStartup"

/* the 3.0.23 default profile string (hue field appended in profile v3) */
static NSString *const kDefaultProfileString =
    @";;;0;1.000000;1.000000;1.000000;1.000000;0.050000;16;2.000000;OTA=;4;4;"
    @"16711680;20;15;120;Z3JhZGllbnQ=;1;0;16711680;6;80;VkxD;-1;;-1;255;2;3;"
    @"3;0;-180.000000";

static const struct { const char *title; int tag; } position_items[9] = {
    { N_("Center"),       0 }, { N_("Left"),        1 },
    { N_("Right"),        2 }, { N_("Top"),         4 },
    { N_("Bottom"),       8 }, { N_("Top-Left"),    5 },
    { N_("Top-Right"),    6 }, { N_("Bottom-Left"), 9 },
    { N_("Bottom-Right"), 10 },
};

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

static vlc_value_t valInt(int64_t i)   { vlc_value_t v; v.i_int = i; return v; }
static vlc_value_t valFloat(float f)   { vlc_value_t v; v.f_float = f; return v; }
static vlc_value_t valBool(bool b)     { vlc_value_t v; v.b_bool = b; return v; }
static vlc_value_t valStr(const char *s)
{
    vlc_value_t v;
    v.psz_string = (char *)s;
    return v;
}

static NSString *hexString(int64_t value)
{
    return [NSString stringWithFormat:@"%06llX",
            (unsigned long long)(value & 0xFFFFFF)];
}

static int64_t hexValue(NSString *string)
{
    return (int64_t)strtoull([string UTF8String], NULL, 16);
}

@implementation VLCLegacyVideoEffects

+ (void)initialize
{
    if (self != [VLCLegacyVideoEffects class])
        return;
    NSDictionary *appDefaults = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSArray arrayWithObject:kDefaultProfileString], VE_PROFILES_KEY,
        [NSArray arrayWithObject:_NS("Default")], VE_PROFILE_NAMES_KEY,
        nil];
    [[NSUserDefaults standardUserDefaults] registerDefaults:appDefaults];
}

- (id)initWithCore:(VLCLegacyCoreInteraction *)interaction
{
    if (self = [super init]) {
        core = [interaction retain];
        p_intf = [interaction intf];

        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if ([defaults boolForKey:VE_APPLY_ON_STARTUP]) {
            /* the widgets do not exist yet; the option helpers still
             * create the playlist variables (messages to nil are no-ops) */
            [self resetValues];
            [self loadProfile];
        } else
            [defaults setInteger:0 forKey:VE_SELECTED_KEY];
    }
    return self;
}

- (void)dealloc
{
    [core release];
    [super dealloc];
}

/*****************************************************************************
 * option helpers (playlist-object variables, created with inheritance so
 * later vouts pick them up, exactly like the 3.0 window)
 *****************************************************************************/

- (float)floatOption:(const char *)name
{
    playlist_t *p_playlist = pl_Get(p_intf);
    var_Create(p_playlist, name, VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
    return var_GetFloat(p_playlist, name);
}

- (int64_t)intOption:(const char *)name
{
    playlist_t *p_playlist = pl_Get(p_intf);
    var_Create(p_playlist, name, VLC_VAR_INTEGER | VLC_VAR_DOINHERIT);
    return var_GetInteger(p_playlist, name);
}

- (BOOL)boolOption:(const char *)name
{
    playlist_t *p_playlist = pl_Get(p_intf);
    var_Create(p_playlist, name, VLC_VAR_BOOL | VLC_VAR_DOINHERIT);
    return var_GetBool(p_playlist, name) ? YES : NO;
}

/* caller owns nothing; empty string for unset */
- (NSString *)stringOption:(const char *)name
{
    playlist_t *p_playlist = pl_Get(p_intf);
    var_Create(p_playlist, name, VLC_VAR_STRING | VLC_VAR_DOINHERIT);
    char *psz = var_GetNonEmptyString(p_playlist, name);
    NSString *string = psz ? [NSString stringWithUTF8String:psz] : @"";
    free(psz);
    return string;
}

/*****************************************************************************
 * window construction
 *****************************************************************************/

- (NSTextField *)labeledRow:(NSString *)title y:(float)y x:(float)x
                     labelW:(float)labelW in:(NSView *)parent
{
    NSTextField *label = [self hudLabel:title
                                  frame:NSMakeRect(x, y + 2, labelW, 14)
                                   bold:NO in:parent];
    [label setAlignment:NSRightTextAlignment];
    return label;
}

- (NSSlider *)sliderRow:(NSString *)title y:(float)y x:(float)x
                    min:(double)min max:(double)max action:(SEL)action
                     in:(NSView *)parent
{
    [self labeledRow:title y:y x:x labelW:92 in:parent];
    return [self hudSlider:NSMakeRect(x + 98, y - 2, 172, 19)
                       min:min max:max action:action in:parent];
}

/* editable numeric field + stepper pair sharing one action */
- (NSTextField *)fieldRow:(NSString *)title y:(float)y x:(float)x
                   min:(double)min max:(double)max step:(double)step
               stepper:(NSStepper **)stepperOut action:(SEL)action
                    in:(NSView *)parent
{
    [self labeledRow:title y:y x:x labelW:132 in:parent];
    NSTextField *field = [self hudValue:NSMakeRect(x + 138, y, 56, 17)
                               editable:YES in:parent];
    [field setTarget:self];
    [field setAction:action];
    [field setDelegate:(id)self];
    NSStepper *stepper = [self hudStepper:NSMakeRect(x + 198, y - 2, 15, 22)
                                      min:min max:max increment:step
                                   action:action in:parent];
    if (stepperOut)
        *stepperOut = stepper;
    return field;
}

- (void)addPositionItems:(NSPopUpButton *)popup
{
    int i;
    for (i = 0; i < 9; i++) {
        [popup addItemWithTitle:_NS(position_items[i].title)];
        [[popup lastItem] setTag:position_items[i].tag];
    }
}

- (NSView *)buildBasicPane:(NSSize)size
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)]
        autorelease];
    float top = size.height;

    /* left column: Image Adjust */
    adjustCheckbox = [self hudCheckbox:_NS("Image Adjust")
                                 frame:NSMakeRect(8, top - 26, 240, 18)
                                action:@selector(enableAdjust:) in:pane];
    adjustHueSlider = [self sliderRow:_NS("Hue") y:top - 56 x:8
                                  min:-180 max:180
                               action:@selector(adjustSliderChanged:)
                                   in:pane];
    adjustContrastSlider = [self sliderRow:_NS("Contrast") y:top - 82 x:8
                                       min:0 max:2
                                    action:@selector(adjustSliderChanged:)
                                        in:pane];
    adjustBrightnessSlider = [self sliderRow:_NS("Brightness") y:top - 108
                                           x:8 min:0 max:2
                                      action:@selector(adjustSliderChanged:)
                                          in:pane];
    adjustBrightnessCheckbox =
        [self hudCheckbox:_NS("Brightness Threshold")
                    frame:NSMakeRect(106, top - 132, 190, 18)
                   action:@selector(enableAdjustBrightnessThreshold:)
                       in:pane];
    adjustSaturationSlider = [self sliderRow:_NS("Saturation") y:top - 160
                                           x:8 min:0 max:3
                                      action:@selector(adjustSliderChanged:)
                                          in:pane];
    adjustGammaSlider = [self sliderRow:_NS("Gamma") y:top - 186 x:8
                                    min:0 max:10
                                 action:@selector(adjustSliderChanged:)
                                     in:pane];
    adjustResetButton = [self hudPushButton:_NS("Reset")
                                      frame:NSMakeRect(106, top - 222, 80, 22)
                                     action:@selector(adjustReset:) in:pane];

    /* right column: Sharpen / Banding removal / Film Grain */
    float rx = 316;
    sharpenCheckbox = [self hudCheckbox:_NS("Sharpen")
                                  frame:NSMakeRect(rx, top - 26, 240, 18)
                                 action:@selector(enableSharpen:) in:pane];
    sharpenSlider = [self sliderRow:_NS("Sigma") y:top - 56 x:rx
                                min:0 max:2
                             action:@selector(sharpenSliderChanged:)
                                 in:pane];

    bandingCheckbox = [self hudCheckbox:_NS("Banding removal")
                                  frame:NSMakeRect(rx, top - 92, 240, 18)
                                 action:@selector(enableBanding:) in:pane];
    bandingSlider = [self sliderRow:_NS("Radius") y:top - 122 x:rx
                                min:4 max:32
                             action:@selector(bandingSliderChanged:)
                                 in:pane];
    [bandingSlider setNumberOfTickMarks:8];
    [bandingSlider setAllowsTickMarkValuesOnly:YES];

    grainCheckbox = [self hudCheckbox:_NS("Film Grain")
                                frame:NSMakeRect(rx, top - 158, 240, 18)
                               action:@selector(enableGrain:) in:pane];
    grainSlider = [self sliderRow:_NS("Variance") y:top - 188 x:rx
                              min:0 max:40
                           action:@selector(grainSliderChanged:) in:pane];

    return pane;
}

- (NSView *)buildCropPane:(NSSize)size
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)]
        autorelease];
    float centerX = size.width / 2 - 96;
    float top = size.height;

    cropTopTextField = [self fieldRow:_NS("Top") y:top - 60 x:centerX
                                  min:0 max:1000 step:1
                              stepper:&cropTopStepper
                               action:@selector(cropFieldChanged:) in:pane];
    cropLeftTextField = [self fieldRow:_NS("Left") y:top - 120 x:centerX - 160
                                   min:0 max:1000 step:1
                               stepper:&cropLeftStepper
                                action:@selector(cropFieldChanged:) in:pane];
    cropRightTextField = [self fieldRow:_NS("Right") y:top - 120
                                      x:centerX + 160
                                    min:0 max:1000 step:1
                                stepper:&cropRightStepper
                                 action:@selector(cropFieldChanged:) in:pane];
    cropBottomTextField = [self fieldRow:_NS("Bottom") y:top - 180 x:centerX
                                     min:0 max:1000 step:1
                                 stepper:&cropBottomStepper
                                  action:@selector(cropFieldChanged:)
                                      in:pane];

    cropSyncTopBottomCheckbox =
        [self hudCheckbox:_NS("Synchronize top and bottom")
                    frame:NSMakeRect(centerX - 60, top - 230, 300, 18)
                   action:@selector(cropFieldChanged:) in:pane];
    cropSyncLeftRightCheckbox =
        [self hudCheckbox:_NS("Synchronize left and right")
                    frame:NSMakeRect(centerX - 60, top - 254, 300, 18)
                   action:@selector(cropFieldChanged:) in:pane];

    return pane;
}

- (NSView *)buildGeometryPane:(NSSize)size
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)]
        autorelease];
    float top = size.height;

    /* left column */
    transformCheckbox = [self hudCheckbox:_NS("Transform")
                                    frame:NSMakeRect(8, top - 26, 240, 18)
                                   action:@selector(enableTransform:)
                                       in:pane];
    transformPopup = [self hudPopup:NSMakeRect(24, top - 54, 220, 22)
                             action:@selector(transformModifierChanged:)
                                 in:pane];
    static const struct { const char *title; const char *value; }
        transform_items[5] = {
        { N_("Rotate by 90 degrees"),  "90" },
        { N_("Rotate by 180 degrees"), "180" },
        { N_("Rotate by 270 degrees"), "270" },
        { N_("Flip horizontally"),     "hflip" },
        { N_("Flip vertically"),       "vflip" },
    };
    int i;
    for (i = 0; i < 5; i++) {
        [transformPopup addItemWithTitle:_NS(transform_items[i].title)];
        [[transformPopup lastItem] setRepresentedObject:
            [NSString stringWithUTF8String:transform_items[i].value]];
    }

    zoomCheckbox = [self hudCheckbox:_NS("Magnification/Zoom")
                               frame:NSMakeRect(8, top - 88, 260, 18)
                              action:@selector(enableZoom:) in:pane];

    puzzleCheckbox = [self hudCheckbox:_NS("Puzzle game")
                                 frame:NSMakeRect(8, top - 120, 240, 18)
                                action:@selector(enablePuzzle:) in:pane];
    puzzleRowsTextField = [self fieldRow:_NS("Rows") y:top - 148 x:24
                                     min:2 max:16 step:1
                                 stepper:&puzzleRowsStepper
                                  action:@selector(puzzleModifierChanged:)
                                      in:pane];
    puzzleColumnsTextField = [self fieldRow:_NS("Columns") y:top - 172 x:24
                                        min:2 max:16 step:1
                                    stepper:&puzzleColumnsStepper
                                     action:@selector(puzzleModifierChanged:)
                                         in:pane];

    /* right column */
    float rx = 316;
    cloneCheckbox = [self hudCheckbox:_NS("Clone")
                                frame:NSMakeRect(rx, top - 26, 240, 18)
                               action:@selector(enableClone:) in:pane];
    cloneNumberTextField = [self fieldRow:_NS("Number of clones")
                                        y:top - 54 x:rx
                                      min:2 max:20 step:1
                                  stepper:&cloneNumberStepper
                                   action:@selector(cloneModifierChanged:)
                                       in:pane];

    wallCheckbox = [self hudCheckbox:_NS("Wall")
                               frame:NSMakeRect(rx, top - 96, 240, 18)
                              action:@selector(enableWall:) in:pane];
    wallRowsTextField = [self fieldRow:_NS("Rows") y:top - 124 x:rx
                                   min:1 max:15 step:1
                               stepper:&wallRowsStepper
                                action:@selector(wallModifierChanged:)
                                    in:pane];
    wallColumnsTextField = [self fieldRow:_NS("Columns") y:top - 148 x:rx
                                      min:1 max:15 step:1
                                  stepper:&wallColumnsStepper
                                   action:@selector(wallModifierChanged:)
                                       in:pane];

    return pane;
}

- (NSView *)buildColorPane:(NSSize)size
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)]
        autorelease];
    float top = size.height;

    /* left column */
    thresholdCheckbox = [self hudCheckbox:_NS("Color threshold")
                                    frame:NSMakeRect(8, top - 26, 240, 18)
                                   action:@selector(enableThreshold:)
                                       in:pane];
    [self labeledRow:_NS("Color") y:top - 52 x:8 labelW:92 in:pane];
    thresholdColorTextField = [self hudValue:NSMakeRect(106, top - 52, 76, 17)
                                    editable:YES in:pane];
    [thresholdColorTextField setTarget:self];
    [thresholdColorTextField setAction:
        @selector(thresholdModifierChanged:)];
    [thresholdColorTextField setDelegate:(id)self];
    thresholdSaturationSlider = [self sliderRow:_NS("Saturation")
                                              y:top - 78 x:8 min:0 max:100
                                         action:@selector(thresholdModifierChanged:)
                                             in:pane];
    thresholdSimilaritySlider = [self sliderRow:_NS("Similarity")
                                              y:top - 104 x:8 min:0 max:100
                                         action:@selector(thresholdModifierChanged:)
                                             in:pane];

    sepiaCheckbox = [self hudCheckbox:_NS("Sepia")
                                frame:NSMakeRect(8, top - 136, 240, 18)
                               action:@selector(enableSepia:) in:pane];
    sepiaTextField = [self fieldRow:_NS("Intensity") y:top - 162 x:8
                                min:0 max:255 step:1
                            stepper:&sepiaStepper
                             action:@selector(sepiaModifierChanged:)
                                 in:pane];

    gradientCheckbox = [self hudCheckbox:_NS("Gradient")
                                   frame:NSMakeRect(8, top - 194, 240, 18)
                                  action:@selector(enableGradient:)
                                      in:pane];
    [self labeledRow:_NS("Mode") y:top - 222 x:8 labelW:92 in:pane];
    gradientModePopup = [self hudPopup:NSMakeRect(106, top - 226, 164, 22)
                                action:@selector(gradientModifierChanged:)
                                    in:pane];
    static const struct { const char *title; const char *value; }
        gradient_items[3] = {
        { N_("Gradient"), "gradient" },
        { N_("Edge"),     "edge" },
        { N_("Hough"),    "hough" },
    };
    int i;
    for (i = 0; i < 3; i++) {
        [gradientModePopup addItemWithTitle:_NS(gradient_items[i].title)];
        [[gradientModePopup lastItem] setRepresentedObject:
            [NSString stringWithUTF8String:gradient_items[i].value]];
    }
    gradientColorCheckbox = [self hudCheckbox:_NS("Color")
                                        frame:NSMakeRect(106, top - 250, 90, 18)
                                       action:@selector(gradientModifierChanged:)
                                           in:pane];
    gradientCartoonCheckbox =
        [self hudCheckbox:_NS("Cartoon")
                    frame:NSMakeRect(200, top - 250, 100, 18)
                   action:@selector(gradientModifierChanged:) in:pane];

    /* right column */
    float rx = 316;
    extractCheckbox = [self hudCheckbox:_NS("Color extraction")
                                  frame:NSMakeRect(rx, top - 26, 240, 18)
                                 action:@selector(enableExtract:) in:pane];
    [self labeledRow:_NS("Color") y:top - 52 x:rx labelW:92 in:pane];
    extractTextField = [self hudValue:NSMakeRect(rx + 98, top - 52, 76, 17)
                             editable:YES in:pane];
    [extractTextField setTarget:self];
    [extractTextField setAction:@selector(extractModifierChanged:)];
    [extractTextField setDelegate:(id)self];

    invertCheckbox = [self hudCheckbox:_NS("Invert colors")
                                 frame:NSMakeRect(rx, top - 84, 240, 18)
                                action:@selector(enableInvert:) in:pane];

    posterizeCheckbox = [self hudCheckbox:_NS("Posterize")
                                    frame:NSMakeRect(rx, top - 112, 240, 18)
                                   action:@selector(enablePosterize:)
                                       in:pane];
    posterizeTextField = [self fieldRow:_NS("Posterize level") y:top - 138
                                      x:rx min:2 max:256 step:1
                                stepper:&posterizeStepper
                                 action:@selector(posterizeModifierChanged:)
                                     in:pane];

    blurCheckbox = [self hudCheckbox:_NS("Motion blur")
                               frame:NSMakeRect(rx, top - 170, 240, 18)
                              action:@selector(enableBlur:) in:pane];
    blurSlider = [self sliderRow:_NS("Factor") y:top - 198 x:rx
                             min:1 max:127
                          action:@selector(blurModifierChanged:) in:pane];

    motiondetectCheckbox = [self hudCheckbox:_NS("Motion Detect")
                                       frame:NSMakeRect(rx, top - 230, 240, 18)
                                      action:@selector(enableMotionDetect:)
                                          in:pane];
    watereffectCheckbox = [self hudCheckbox:_NS("Water effect")
                                      frame:NSMakeRect(rx, top - 254, 240, 18)
                                     action:@selector(enableWaterEffect:)
                                         in:pane];
    wavesCheckbox = [self hudCheckbox:_NS("Waves")
                                frame:NSMakeRect(rx, top - 278, 240, 18)
                               action:@selector(enableWaves:) in:pane];
    psychedelicCheckbox = [self hudCheckbox:_NS("Psychedelic")
                                      frame:NSMakeRect(rx, top - 302, 240, 18)
                                     action:@selector(enablePsychedelic:)
                                         in:pane];

    return pane;
}

- (NSView *)buildMiscPane:(NSSize)size
{
    NSView *pane = [[[NSView alloc]
        initWithFrame:NSMakeRect(0, 0, size.width, size.height)]
        autorelease];
    float top = size.height;

    addTextCheckbox = [self hudCheckbox:_NS("Add text")
                                  frame:NSMakeRect(8, top - 26, 240, 18)
                                 action:@selector(enableAddText:) in:pane];
    [self labeledRow:_NS("Text") y:top - 52 x:8 labelW:92 in:pane];
    addTextTextTextField = [self hudValue:NSMakeRect(106, top - 52, 200, 17)
                                 editable:YES in:pane];
    [addTextTextTextField setTarget:self];
    [addTextTextTextField setAction:@selector(addTextModifierChanged:)];
    [addTextTextTextField setDelegate:(id)self];
    [self labeledRow:_NS("Position") y:top - 80 x:8 labelW:92 in:pane];
    addTextPositionPopup = [self hudPopup:NSMakeRect(106, top - 84, 160, 22)
                                   action:@selector(addTextModifierChanged:)
                                       in:pane];
    [self addPositionItems:addTextPositionPopup];

    addLogoCheckbox = [self hudCheckbox:_NS("Add logo")
                                  frame:NSMakeRect(8, top - 124, 240, 18)
                                 action:@selector(enableAddLogo:) in:pane];
    [self labeledRow:_NS("Logo") y:top - 150 x:8 labelW:92 in:pane];
    addLogoLogoTextField = [self hudValue:NSMakeRect(106, top - 150, 200, 17)
                                 editable:YES in:pane];
    [addLogoLogoTextField setTarget:self];
    [addLogoLogoTextField setAction:@selector(addLogoModifierChanged:)];
    [addLogoLogoTextField setDelegate:(id)self];
    [self labeledRow:_NS("Position") y:top - 178 x:8 labelW:92 in:pane];
    addLogoPositionPopup = [self hudPopup:NSMakeRect(106, top - 182, 160, 22)
                                   action:@selector(addLogoModifierChanged:)
                                       in:pane];
    [self addPositionItems:addLogoPositionPopup];
    addLogoTransparencySlider = [self sliderRow:_NS("Transparency")
                                              y:top - 210 x:8
                                            min:0 max:255
                                         action:@selector(addLogoModifierChanged:)
                                             in:pane];

    anaglyphCheckbox = [self hudCheckbox:_NS("Anaglyph")
                                   frame:NSMakeRect(316, top - 26, 240, 18)
                                  action:@selector(enableAnaglyph:) in:pane];

    return pane;
}

- (void)buildWindow
{
    [self buildHUDWithTitle:_NS("Video Effects")
                       size:NSMakeSize(640, 496)
                  tabTitles:[NSArray arrayWithObjects:
                                _NS("Basic"), _NS("Crop"), _NS("Geometry"),
                                _NS("Color"), _NS("Miscellaneous"), nil]
               bottomMargin:44];

    NSSize paneSize = [[self paneContainer] bounds].size;
    [self setPane:[self buildBasicPane:paneSize] atIndex:0];
    [self setPane:[self buildCropPane:paneSize] atIndex:1];
    [self setPane:[self buildGeometryPane:paneSize] atIndex:2];
    [self setPane:[self buildColorPane:paneSize] atIndex:3];
    [self setPane:[self buildMiscPane:paneSize] atIndex:4];

    /* profile row at the bottom, like the 3.0 window */
    NSView *content = [window contentView];
    profilePopup = [self hudPopup:NSMakeRect(17, 10, 200, 22)
                           action:@selector(profileSelectorAction:)
                               in:content];
    applyProfileCheckbox =
        [self hudCheckbox:_NS("Apply profile at next launch")
                    frame:NSMakeRect(228, 12, 260, 18)
                   action:@selector(applyProfileCheckboxChanged:)
                       in:content];
    [applyProfileCheckbox setState:
        [[NSUserDefaults standardUserDefaults] boolForKey:VE_APPLY_ON_STARTUP]
            ? NSOnState : NSOffState];

    [self resetCropValues];
    [self resetProfileSelector];
}

- (void)windowWillShow
{
    /* the 3.0 window zeroes the crop values on input change, so a stale
     * crop is never pushed into a new video */
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    void *item = p_input ? (void *)input_GetItem(p_input) : NULL;
    if (p_input)
        vlc_object_release(p_input);
    if (item != lastInputItem) {
        lastInputItem = item;
        [self resetCropValues];
    }
    [self resetValues];
}

/*****************************************************************************
 * state refresh
 *****************************************************************************/

- (void)setAdjustEnabled:(BOOL)enabled
{
    [adjustHueSlider setEnabled:enabled];
    [adjustContrastSlider setEnabled:enabled];
    [adjustBrightnessSlider setEnabled:enabled];
    [adjustBrightnessCheckbox setEnabled:enabled];
    [adjustSaturationSlider setEnabled:enabled];
    [adjustGammaSlider setEnabled:enabled];
    [adjustResetButton setEnabled:enabled];
}

- (void)resetCropValues
{
    [cropTopTextField setStringValue:@"0"];
    [cropLeftTextField setStringValue:@"0"];
    [cropRightTextField setStringValue:@"0"];
    [cropBottomTextField setStringValue:@"0"];
    [cropTopStepper setIntValue:0];
    [cropLeftStepper setIntValue:0];
    [cropRightStepper setIntValue:0];
    [cropBottomStepper setIntValue:0];
    [cropSyncTopBottomCheckbox setState:NSOffState];
    [cropSyncLeftRightCheckbox setState:NSOffState];
}

- (void)resetValues
{
    playlist_t *p_playlist = pl_Get(p_intf);
    char *psz;
    BOOL b_state;

    /* checkboxes from the current filter chains */
    psz = var_InheritString(p_playlist, "video-filter");
#define FILTER_ON(name) (psz && strstr(psz, name) != NULL)
    [adjustCheckbox setState:FILTER_ON("adjust") ? NSOnState : NSOffState];
    [sharpenCheckbox setState:FILTER_ON("sharpen") ? NSOnState : NSOffState];
    [bandingCheckbox setState:FILTER_ON("gradfun") ? NSOnState : NSOffState];
    [grainCheckbox setState:FILTER_ON("grain") ? NSOnState : NSOffState];
    [transformCheckbox setState:
        FILTER_ON("transform") ? NSOnState : NSOffState];
    [zoomCheckbox setState:FILTER_ON("magnify") ? NSOnState : NSOffState];
    [puzzleCheckbox setState:FILTER_ON("puzzle") ? NSOnState : NSOffState];
    [thresholdCheckbox setState:
        FILTER_ON("colorthres") ? NSOnState : NSOffState];
    [sepiaCheckbox setState:FILTER_ON("sepia") ? NSOnState : NSOffState];
    [gradientCheckbox setState:
        FILTER_ON("gradient") ? NSOnState : NSOffState];
    [extractCheckbox setState:FILTER_ON("extract") ? NSOnState : NSOffState];
    [invertCheckbox setState:FILTER_ON("invert") ? NSOnState : NSOffState];
    [posterizeCheckbox setState:
        FILTER_ON("posterize") ? NSOnState : NSOffState];
    [blurCheckbox setState:
        FILTER_ON("motionblur") ? NSOnState : NSOffState];
    [motiondetectCheckbox setState:
        FILTER_ON("motiondetect") ? NSOnState : NSOffState];
    [watereffectCheckbox setState:
        FILTER_ON("ripple") ? NSOnState : NSOffState];
    [wavesCheckbox setState:FILTER_ON("wave") ? NSOnState : NSOffState];
    [psychedelicCheckbox setState:
        FILTER_ON("psychedelic") ? NSOnState : NSOffState];
    [anaglyphCheckbox setState:
        FILTER_ON("anaglyph") ? NSOnState : NSOffState];
    free(psz);

    psz = var_InheritString(p_playlist, "sub-source");
    [addTextCheckbox setState:FILTER_ON("marq") ? NSOnState : NSOffState];
    [addLogoCheckbox setState:FILTER_ON("logo") ? NSOnState : NSOffState];
    free(psz);

    psz = var_InheritString(p_playlist, "video-splitter");
    [cloneCheckbox setState:FILTER_ON("clone") ? NSOnState : NSOffState];
    [wallCheckbox setState:FILTER_ON("wall") ? NSOnState : NSOffState];
    free(psz);
#undef FILTER_ON

    /* Basic */
    b_state = [adjustCheckbox state] == NSOnState;
    [adjustHueSlider setFloatValue:[self floatOption:"hue"]];
    [adjustContrastSlider setFloatValue:[self floatOption:"contrast"]];
    [adjustBrightnessSlider setFloatValue:[self floatOption:"brightness"]];
    [adjustBrightnessCheckbox setState:
        [self boolOption:"brightness-threshold"] ? NSOnState : NSOffState];
    [adjustSaturationSlider setFloatValue:[self floatOption:"saturation"]];
    [adjustGammaSlider setFloatValue:[self floatOption:"gamma"]];
    [self setAdjustEnabled:b_state];

    [sharpenSlider setFloatValue:[self floatOption:"sharpen-sigma"]];
    [sharpenSlider setEnabled:[sharpenCheckbox state] == NSOnState];
    [bandingSlider setIntValue:(int)[self intOption:"gradfun-radius"]];
    [bandingSlider setEnabled:[bandingCheckbox state] == NSOnState];
    [grainSlider setFloatValue:[self floatOption:"grain-variance"]];
    [grainSlider setEnabled:[grainCheckbox state] == NSOnState];

    /* Geometry */
    NSString *transformType = [self stringOption:"transform-type"];
    int i;
    for (i = 0; i < [transformPopup numberOfItems]; i++) {
        if ([[[transformPopup itemAtIndex:i] representedObject]
                isEqualToString:transformType]) {
            [transformPopup selectItemAtIndex:i];
            break;
        }
    }
    [transformPopup setEnabled:[transformCheckbox state] == NSOnState];

    b_state = [puzzleCheckbox state] == NSOnState;
    [puzzleRowsTextField setIntValue:(int)[self intOption:"puzzle-rows"]];
    [puzzleRowsStepper setIntValue:(int)[self intOption:"puzzle-rows"]];
    [puzzleColumnsTextField setIntValue:(int)[self intOption:"puzzle-cols"]];
    [puzzleColumnsStepper setIntValue:(int)[self intOption:"puzzle-cols"]];
    [puzzleRowsTextField setEnabled:b_state];
    [puzzleRowsStepper setEnabled:b_state];
    [puzzleColumnsTextField setEnabled:b_state];
    [puzzleColumnsStepper setEnabled:b_state];

    b_state = [cloneCheckbox state] == NSOnState;
    [cloneNumberTextField setIntValue:(int)[self intOption:"clone-count"]];
    [cloneNumberStepper setIntValue:(int)[self intOption:"clone-count"]];
    [cloneNumberTextField setEnabled:b_state];
    [cloneNumberStepper setEnabled:b_state];

    b_state = [wallCheckbox state] == NSOnState;
    [wallRowsTextField setIntValue:(int)[self intOption:"wall-rows"]];
    [wallRowsStepper setIntValue:(int)[self intOption:"wall-rows"]];
    [wallColumnsTextField setIntValue:(int)[self intOption:"wall-cols"]];
    [wallColumnsStepper setIntValue:(int)[self intOption:"wall-cols"]];
    [wallRowsTextField setEnabled:b_state];
    [wallRowsStepper setEnabled:b_state];
    [wallColumnsTextField setEnabled:b_state];
    [wallColumnsStepper setEnabled:b_state];

    /* Color */
    b_state = [thresholdCheckbox state] == NSOnState;
    [thresholdColorTextField setStringValue:
        hexString([self intOption:"colorthres-color"])];
    [thresholdSaturationSlider setIntValue:
        (int)[self intOption:"colorthres-saturationthres"]];
    [thresholdSimilaritySlider setIntValue:
        (int)[self intOption:"colorthres-similaritythres"]];
    [thresholdColorTextField setEnabled:b_state];
    [thresholdSaturationSlider setEnabled:b_state];
    [thresholdSimilaritySlider setEnabled:b_state];

    b_state = [sepiaCheckbox state] == NSOnState;
    [sepiaTextField setIntValue:(int)[self intOption:"sepia-intensity"]];
    [sepiaStepper setIntValue:(int)[self intOption:"sepia-intensity"]];
    [sepiaTextField setEnabled:b_state];
    [sepiaStepper setEnabled:b_state];

    b_state = [gradientCheckbox state] == NSOnState;
    NSString *gradientMode = [self stringOption:"gradient-mode"];
    for (i = 0; i < [gradientModePopup numberOfItems]; i++) {
        if ([[[gradientModePopup itemAtIndex:i] representedObject]
                isEqualToString:gradientMode]) {
            [gradientModePopup selectItemAtIndex:i];
            break;
        }
    }
    [gradientColorCheckbox setState:
        [self intOption:"gradient-type"] ? NSOnState : NSOffState];
    [gradientCartoonCheckbox setState:
        [self boolOption:"gradient-cartoon"] ? NSOnState : NSOffState];
    [gradientModePopup setEnabled:b_state];
    [gradientColorCheckbox setEnabled:b_state];
    [gradientCartoonCheckbox setEnabled:b_state];

    [extractTextField setStringValue:
        hexString([self intOption:"extract-component"])];
    [extractTextField setEnabled:[extractCheckbox state] == NSOnState];

    b_state = [posterizeCheckbox state] == NSOnState;
    [posterizeTextField setIntValue:(int)[self intOption:"posterize-level"]];
    [posterizeStepper setIntValue:(int)[self intOption:"posterize-level"]];
    [posterizeTextField setEnabled:b_state];
    [posterizeStepper setEnabled:b_state];

    [blurSlider setIntValue:(int)[self intOption:"blur-factor"]];
    [blurSlider setEnabled:[blurCheckbox state] == NSOnState];

    /* Miscellaneous */
    b_state = [addTextCheckbox state] == NSOnState;
    [addTextTextTextField setStringValue:[self stringOption:"marq-marquee"]];
    [addTextPositionPopup selectItemWithTag:[self intOption:"marq-position"]];
    [addTextTextTextField setEnabled:b_state];
    [addTextPositionPopup setEnabled:b_state];

    b_state = [addLogoCheckbox state] == NSOnState;
    [addLogoLogoTextField setStringValue:[self stringOption:"logo-file"]];
    [addLogoPositionPopup selectItemWithTag:[self intOption:"logo-position"]];
    [addLogoTransparencySlider setIntValue:
        (int)[self intOption:"logo-opacity"]];
    [addLogoLogoTextField setEnabled:b_state];
    [addLogoPositionPopup setEnabled:b_state];
    [addLogoTransparencySlider setEnabled:b_state];
}

/* commit text fields when focus leaves them, not only on Return */
- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = [notification object];
    if ([field action])
        [self performSelector:[field action] withObject:field];
}

/*****************************************************************************
 * Basic actions
 *****************************************************************************/

- (void)enableAdjust:(id)sender
{
    BOOL b_on = [adjustCheckbox state] == NSOnState;
    [core setVideoFilter:"adjust" on:b_on];
    [self setAdjustEnabled:b_on];
}

- (void)adjustReset:(id)sender
{
    [adjustHueSlider setFloatValue:0.0f];
    [adjustContrastSlider setFloatValue:1.0f];
    [adjustBrightnessSlider setFloatValue:1.0f];
    [adjustSaturationSlider setFloatValue:1.0f];
    [adjustGammaSlider setFloatValue:1.0f];
    [core setVideoFilterProperty:"hue" forFilter:"adjust"
                       withValue:valFloat(0.0f)];
    [core setVideoFilterProperty:"contrast" forFilter:"adjust"
                       withValue:valFloat(1.0f)];
    [core setVideoFilterProperty:"brightness" forFilter:"adjust"
                       withValue:valFloat(1.0f)];
    [core setVideoFilterProperty:"saturation" forFilter:"adjust"
                       withValue:valFloat(1.0f)];
    [core setVideoFilterProperty:"gamma" forFilter:"adjust"
                       withValue:valFloat(1.0f)];
}

- (void)adjustSliderChanged:(id)sender
{
    const char *psz_property = NULL;
    if (sender == adjustHueSlider)
        psz_property = "hue";
    else if (sender == adjustContrastSlider)
        psz_property = "contrast";
    else if (sender == adjustBrightnessSlider)
        psz_property = "brightness";
    else if (sender == adjustSaturationSlider)
        psz_property = "saturation";
    else if (sender == adjustGammaSlider)
        psz_property = "gamma";
    if (psz_property)
        [core setVideoFilterProperty:psz_property forFilter:"adjust"
                           withValue:valFloat([sender floatValue])];
}

- (void)enableAdjustBrightnessThreshold:(id)sender
{
    [core setVideoFilterProperty:"brightness-threshold"
                       forFilter:"adjust"
                       withValue:valBool([sender state] == NSOnState)];
}

- (void)enableSharpen:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"sharpen" on:b_on];
    [sharpenSlider setEnabled:b_on];
}

- (void)sharpenSliderChanged:(id)sender
{
    [core setVideoFilterProperty:"sharpen-sigma" forFilter:"sharpen"
                       withValue:valFloat([sender floatValue])];
}

- (void)enableBanding:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"gradfun" on:b_on];
    [bandingSlider setEnabled:b_on];
}

- (void)bandingSliderChanged:(id)sender
{
    [core setVideoFilterProperty:"gradfun-radius" forFilter:"gradfun"
                       withValue:valInt([sender intValue])];
}

- (void)enableGrain:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"grain" on:b_on];
    [grainSlider setEnabled:b_on];
}

- (void)grainSliderChanged:(id)sender
{
    [core setVideoFilterProperty:"grain-variance" forFilter:"grain"
                       withValue:valFloat([sender floatValue])];
}

/*****************************************************************************
 * Crop
 *****************************************************************************/

- (void)cropFieldChanged:(id)sender
{
    /* keep each field/stepper pair in sync */
    if (sender == cropTopStepper)
        [cropTopTextField setIntValue:[cropTopStepper intValue]];
    else if (sender == cropTopTextField)
        [cropTopStepper setIntValue:[cropTopTextField intValue]];
    else if (sender == cropBottomStepper)
        [cropBottomTextField setIntValue:[cropBottomStepper intValue]];
    else if (sender == cropBottomTextField)
        [cropBottomStepper setIntValue:[cropBottomTextField intValue]];
    else if (sender == cropLeftStepper)
        [cropLeftTextField setIntValue:[cropLeftStepper intValue]];
    else if (sender == cropLeftTextField)
        [cropLeftStepper setIntValue:[cropLeftTextField intValue]];
    else if (sender == cropRightStepper)
        [cropRightTextField setIntValue:[cropRightStepper intValue]];
    else if (sender == cropRightTextField)
        [cropRightStepper setIntValue:[cropRightTextField intValue]];

    if ([cropSyncTopBottomCheckbox state] == NSOnState) {
        if (sender == cropBottomTextField || sender == cropBottomStepper) {
            [cropTopTextField setIntValue:[cropBottomTextField intValue]];
            [cropTopStepper setIntValue:[cropBottomTextField intValue]];
        } else {
            [cropBottomTextField setIntValue:[cropTopTextField intValue]];
            [cropBottomStepper setIntValue:[cropTopTextField intValue]];
        }
    }
    if ([cropSyncLeftRightCheckbox state] == NSOnState) {
        if (sender == cropRightTextField || sender == cropRightStepper) {
            [cropLeftTextField setIntValue:[cropRightTextField intValue]];
            [cropLeftStepper setIntValue:[cropRightTextField intValue]];
        } else {
            [cropRightTextField setIntValue:[cropLeftTextField intValue]];
            [cropRightStepper setIntValue:[cropLeftTextField intValue]];
        }
    }

    /* direct vout variables, no filter involved (3.0 behavior) */
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;
    vout_thread_t **pp_vouts;
    size_t i_vouts, i;
    if (!input_Control(p_input, INPUT_GET_VOUTS, &pp_vouts, &i_vouts)
        && pp_vouts) {
        for (i = 0; i < i_vouts; i++) {
            var_SetInteger(pp_vouts[i], "crop-top",
                           [cropTopTextField intValue]);
            var_SetInteger(pp_vouts[i], "crop-bottom",
                           [cropBottomTextField intValue]);
            var_SetInteger(pp_vouts[i], "crop-left",
                           [cropLeftTextField intValue]);
            var_SetInteger(pp_vouts[i], "crop-right",
                           [cropRightTextField intValue]);
            vlc_object_release(pp_vouts[i]);
        }
        free(pp_vouts);
    }
    vlc_object_release(p_input);
}

/*****************************************************************************
 * Geometry
 *****************************************************************************/

- (void)enableTransform:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"transform" on:b_on];
    [transformPopup setEnabled:b_on];
}

- (void)transformModifierChanged:(id)sender
{
    NSString *type = [[transformPopup selectedItem] representedObject];
    [core setVideoFilterProperty:"transform-type" forFilter:"transform"
                       withValue:valStr([type UTF8String])];
}

- (void)enableZoom:(id)sender
{
    [core setVideoFilter:"magnify" on:[sender state] == NSOnState];
}

- (void)enablePuzzle:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"puzzle" on:b_on];
    [puzzleRowsTextField setEnabled:b_on];
    [puzzleRowsStepper setEnabled:b_on];
    [puzzleColumnsTextField setEnabled:b_on];
    [puzzleColumnsStepper setEnabled:b_on];
}

- (void)puzzleModifierChanged:(id)sender
{
    if (sender == puzzleRowsStepper)
        [puzzleRowsTextField setIntValue:[puzzleRowsStepper intValue]];
    else if (sender == puzzleRowsTextField)
        [puzzleRowsStepper setIntValue:[puzzleRowsTextField intValue]];
    else if (sender == puzzleColumnsStepper)
        [puzzleColumnsTextField setIntValue:[puzzleColumnsStepper intValue]];
    else if (sender == puzzleColumnsTextField)
        [puzzleColumnsStepper setIntValue:[puzzleColumnsTextField intValue]];

    [core setVideoFilterProperty:"puzzle-rows" forFilter:"puzzle"
                       withValue:valInt([puzzleRowsTextField intValue])];
    [core setVideoFilterProperty:"puzzle-cols" forFilter:"puzzle"
                       withValue:valInt([puzzleColumnsTextField intValue])];
}

- (void)enableClone:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    /* clone and wall are mutually exclusive (3.0 behavior) */
    if (b_on && [wallCheckbox state] == NSOnState) {
        [wallCheckbox setState:NSOffState];
        [self enableWall:wallCheckbox];
    }
    [core setVideoFilter:"clone" on:b_on];
    [cloneNumberTextField setEnabled:b_on];
    [cloneNumberStepper setEnabled:b_on];
}

- (void)cloneModifierChanged:(id)sender
{
    if (sender == cloneNumberStepper)
        [cloneNumberTextField setIntValue:[cloneNumberStepper intValue]];
    else
        [cloneNumberStepper setIntValue:[cloneNumberTextField intValue]];
    [core setVideoFilterProperty:"clone-count" forFilter:"clone"
                       withValue:valInt([cloneNumberTextField intValue])];
}

- (void)enableWall:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    if (b_on && [cloneCheckbox state] == NSOnState) {
        [cloneCheckbox setState:NSOffState];
        [self enableClone:cloneCheckbox];
    }
    [core setVideoFilter:"wall" on:b_on];
    [wallRowsTextField setEnabled:b_on];
    [wallRowsStepper setEnabled:b_on];
    [wallColumnsTextField setEnabled:b_on];
    [wallColumnsStepper setEnabled:b_on];
}

- (void)wallModifierChanged:(id)sender
{
    if (sender == wallRowsStepper)
        [wallRowsTextField setIntValue:[wallRowsStepper intValue]];
    else if (sender == wallRowsTextField)
        [wallRowsStepper setIntValue:[wallRowsTextField intValue]];
    else if (sender == wallColumnsStepper)
        [wallColumnsTextField setIntValue:[wallColumnsStepper intValue]];
    else if (sender == wallColumnsTextField)
        [wallColumnsStepper setIntValue:[wallColumnsTextField intValue]];

    [core setVideoFilterProperty:"wall-rows" forFilter:"wall"
                       withValue:valInt([wallRowsTextField intValue])];
    [core setVideoFilterProperty:"wall-cols" forFilter:"wall"
                       withValue:valInt([wallColumnsTextField intValue])];
}

/*****************************************************************************
 * Color
 *****************************************************************************/

- (void)enableThreshold:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"colorthres" on:b_on];
    [thresholdColorTextField setEnabled:b_on];
    [thresholdSaturationSlider setEnabled:b_on];
    [thresholdSimilaritySlider setEnabled:b_on];
}

- (void)thresholdModifierChanged:(id)sender
{
    if (sender == thresholdColorTextField)
        [core setVideoFilterProperty:"colorthres-color"
                           forFilter:"colorthres"
                           withValue:valInt(hexValue(
                               [thresholdColorTextField stringValue]))];
    else if (sender == thresholdSaturationSlider)
        [core setVideoFilterProperty:"colorthres-saturationthres"
                           forFilter:"colorthres"
                           withValue:valInt([sender intValue])];
    else if (sender == thresholdSimilaritySlider)
        [core setVideoFilterProperty:"colorthres-similaritythres"
                           forFilter:"colorthres"
                           withValue:valInt([sender intValue])];
}

- (void)enableSepia:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"sepia" on:b_on];
    [sepiaTextField setEnabled:b_on];
    [sepiaStepper setEnabled:b_on];
}

- (void)sepiaModifierChanged:(id)sender
{
    if (sender == sepiaStepper)
        [sepiaTextField setIntValue:[sepiaStepper intValue]];
    else
        [sepiaStepper setIntValue:[sepiaTextField intValue]];
    [core setVideoFilterProperty:"sepia-intensity" forFilter:"sepia"
                       withValue:valInt([sepiaTextField intValue])];
}

- (void)enableGradient:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"gradient" on:b_on];
    [gradientModePopup setEnabled:b_on];
    [gradientColorCheckbox setEnabled:b_on];
    [gradientCartoonCheckbox setEnabled:b_on];
}

- (void)gradientModifierChanged:(id)sender
{
    if (sender == gradientModePopup) {
        NSString *mode = [[gradientModePopup selectedItem] representedObject];
        [core setVideoFilterProperty:"gradient-mode" forFilter:"gradient"
                           withValue:valStr([mode UTF8String])];
    } else if (sender == gradientColorCheckbox)
        [core setVideoFilterProperty:"gradient-type" forFilter:"gradient"
                           withValue:valInt(
                               [sender state] == NSOnState ? 1 : 0)];
    else
        [core setVideoFilterProperty:"gradient-cartoon"
                           forFilter:"gradient"
                           withValue:valBool([sender state] == NSOnState)];
}

- (void)enableExtract:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"extract" on:b_on];
    [extractTextField setEnabled:b_on];
}

- (void)extractModifierChanged:(id)sender
{
    [core setVideoFilterProperty:"extract-component" forFilter:"extract"
                       withValue:valInt(hexValue(
                           [extractTextField stringValue]))];
}

- (void)enableInvert:(id)sender
{
    [core setVideoFilter:"invert" on:[sender state] == NSOnState];
}

- (void)enablePosterize:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"posterize" on:b_on];
    [posterizeTextField setEnabled:b_on];
    [posterizeStepper setEnabled:b_on];
}

- (void)posterizeModifierChanged:(id)sender
{
    if (sender == posterizeStepper)
        [posterizeTextField setIntValue:[posterizeStepper intValue]];
    else
        [posterizeStepper setIntValue:[posterizeTextField intValue]];
    [core setVideoFilterProperty:"posterize-level" forFilter:"posterize"
                       withValue:valInt([posterizeTextField intValue])];
}

- (void)enableBlur:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"motionblur" on:b_on];
    [blurSlider setEnabled:b_on];
}

- (void)blurModifierChanged:(id)sender
{
    [core setVideoFilterProperty:"blur-factor" forFilter:"motionblur"
                       withValue:valInt([sender intValue])];
}

- (void)enableMotionDetect:(id)sender
{
    [core setVideoFilter:"motiondetect" on:[sender state] == NSOnState];
}

- (void)enableWaterEffect:(id)sender
{
    [core setVideoFilter:"ripple" on:[sender state] == NSOnState];
}

- (void)enableWaves:(id)sender
{
    [core setVideoFilter:"wave" on:[sender state] == NSOnState];
}

- (void)enablePsychedelic:(id)sender
{
    [core setVideoFilter:"psychedelic" on:[sender state] == NSOnState];
}

/*****************************************************************************
 * Miscellaneous
 *****************************************************************************/

- (void)enableAddText:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"marq" on:b_on];
    [addTextTextTextField setEnabled:b_on];
    [addTextPositionPopup setEnabled:b_on];
}

- (void)addTextModifierChanged:(id)sender
{
    [core setVideoFilterProperty:"marq-marquee" forFilter:"marq"
                       withValue:valStr(
                           [[addTextTextTextField stringValue] UTF8String])];
    [core setVideoFilterProperty:"marq-position" forFilter:"marq"
                       withValue:valInt(
                           [[addTextPositionPopup selectedItem] tag])];
}

- (void)enableAddLogo:(id)sender
{
    BOOL b_on = [sender state] == NSOnState;
    [core setVideoFilter:"logo" on:b_on];
    [addLogoLogoTextField setEnabled:b_on];
    [addLogoPositionPopup setEnabled:b_on];
    [addLogoTransparencySlider setEnabled:b_on];
}

- (void)addLogoModifierChanged:(id)sender
{
    [core setVideoFilterProperty:"logo-file" forFilter:"logo"
                       withValue:valStr(
                           [[addLogoLogoTextField stringValue] UTF8String])];
    [core setVideoFilterProperty:"logo-position" forFilter:"logo"
                       withValue:valInt(
                           [[addLogoPositionPopup selectedItem] tag])];
    [core setVideoFilterProperty:"logo-opacity" forFilter:"logo"
                       withValue:valInt(
                           [addLogoTransparencySlider intValue])];
}

- (void)enableAnaglyph:(id)sender
{
    [core setVideoFilter:"anaglyph" on:[sender state] == NSOnState];
}

/*****************************************************************************
 * profiles (VLCVideoEffectsWindowController behavior, NSUserDefaults)
 *****************************************************************************/

- (NSInteger)currentProfileIndex
{
    return [[NSUserDefaults standardUserDefaults]
        integerForKey:VE_SELECTED_KEY];
}

- (NSArray *)nonDefaultProfileNames
{
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [[NSUserDefaults standardUserDefaults]
            objectForKey:VE_PROFILE_NAMES_KEY]];
    if ([names count])
        [names removeObjectAtIndex:0];
    return names;
}

- (NSString *)generateProfileString
{
    playlist_t *p_playlist = pl_Get(p_intf);
    return [NSString stringWithFormat:
        @"%@;%@;%@;%lli;%f;%f;%f;%f;%f;%lli;%f;%@;%lli;%lli;%lli;%lli;%lli;"
        @"%lli;%@;%lli;%lli;%lli;%lli;%lli;%@;%lli;%@;%lli;%lli;%lli;%lli;"
        @"%lli;%lli;%f",
        B64EncAndFree(var_InheritString(p_playlist, "video-filter")),
        B64EncAndFree(var_InheritString(p_playlist, "sub-source")),
        B64EncAndFree(var_InheritString(p_playlist, "video-splitter")),
        0LL, /* hue was an integer until 3.0 */
        var_InheritFloat(p_playlist, "contrast"),
        var_InheritFloat(p_playlist, "brightness"),
        var_InheritFloat(p_playlist, "saturation"),
        var_InheritFloat(p_playlist, "gamma"),
        var_InheritFloat(p_playlist, "sharpen-sigma"),
        (long long)var_InheritInteger(p_playlist, "gradfun-radius"),
        var_InheritFloat(p_playlist, "grain-variance"),
        B64EncAndFree(var_InheritString(p_playlist, "transform-type")),
        (long long)var_InheritInteger(p_playlist, "puzzle-rows"),
        (long long)var_InheritInteger(p_playlist, "puzzle-cols"),
        (long long)var_InheritInteger(p_playlist, "colorthres-color"),
        (long long)var_InheritInteger(p_playlist,
                                      "colorthres-saturationthres"),
        (long long)var_InheritInteger(p_playlist,
                                      "colorthres-similaritythres"),
        (long long)var_InheritInteger(p_playlist, "sepia-intensity"),
        B64EncAndFree(var_InheritString(p_playlist, "gradient-mode")),
        (long long)(int)var_InheritBool(p_playlist, "gradient-cartoon"),
        (long long)var_InheritInteger(p_playlist, "gradient-type"),
        (long long)var_InheritInteger(p_playlist, "extract-component"),
        (long long)var_InheritInteger(p_playlist, "posterize-level"),
        (long long)var_InheritInteger(p_playlist, "blur-factor"),
        B64EncAndFree(var_InheritString(p_playlist, "marq-marquee")),
        (long long)var_InheritInteger(p_playlist, "marq-position"),
        B64EncAndFree(var_InheritString(p_playlist, "logo-file")),
        (long long)var_InheritInteger(p_playlist, "logo-position"),
        (long long)var_InheritInteger(p_playlist, "logo-opacity"),
        (long long)var_InheritInteger(p_playlist, "clone-count"),
        (long long)var_InheritInteger(p_playlist, "wall-rows"),
        (long long)var_InheritInteger(p_playlist, "wall-cols"),
        (long long)(int)var_InheritBool(p_playlist, "brightness-threshold"),
        var_InheritFloat(p_playlist, "hue")];
}

- (void)loadProfile
{
    playlist_t *p_playlist = pl_Get(p_intf);
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger profileIndex = [self currentProfileIndex];
    NSString *profileString;

    if (profileIndex == 0)
        profileString = kDefaultProfileString;
    else {
        NSArray *profiles = [defaults objectForKey:VE_PROFILES_KEY];
        if (profileIndex < 0 || (unsigned)profileIndex >= [profiles count])
            return;
        profileString = [profiles objectAtIndex:profileIndex];
    }

    NSArray *items = [profileString componentsSeparatedByString:@";"];
    if ([items count] < 32) {
        msg_Err(p_intf, "Error in parsing profile string");
        return;
    }

    /* filter chains: playlist + running vouts (non-splitters) */
    NSString *videoFilter = B64Dec([items objectAtIndex:0]);
    NSString *subSource = B64Dec([items objectAtIndex:1]);
    NSString *videoSplitter = B64Dec([items objectAtIndex:2]);
    var_SetString(p_playlist, "video-filter", [videoFilter UTF8String]);
    var_SetString(p_playlist, "sub-source", [subSource UTF8String]);
    char *psz_splitter = var_InheritString(p_playlist, "video-splitter");
    if ((psz_splitter == NULL) != ([videoSplitter length] == 0)
     || (psz_splitter
         && strcmp(psz_splitter, [videoSplitter UTF8String]) != 0))
        var_SetString(p_playlist, "video-splitter",
                      [videoSplitter UTF8String]);
    free(psz_splitter);

    input_thread_t *p_input = playlist_CurrentInput(p_playlist);
    if (p_input) {
        vout_thread_t **pp_vouts;
        size_t i_vouts, i;
        if (!input_Control(p_input, INPUT_GET_VOUTS, &pp_vouts, &i_vouts)
            && pp_vouts) {
            for (i = 0; i < i_vouts; i++) {
                var_SetString(pp_vouts[i], "video-filter",
                              [videoFilter UTF8String]);
                var_SetString(pp_vouts[i], "sub-source",
                              [subSource UTF8String]);
                vlc_object_release(pp_vouts[i]);
            }
            free(pp_vouts);
        }
        vlc_object_release(p_input);
    }

#define ITEM_F(idx)  valFloat([[items objectAtIndex:idx] floatValue])
#define ITEM_I(idx)  valInt([[items objectAtIndex:idx] intValue])
#define ITEM_B(idx)  valBool([[items objectAtIndex:idx] intValue] != 0)
#define ITEM_S(idx)  valStr([B64Dec([items objectAtIndex:idx]) UTF8String])
    [core setVideoFilterProperty:"contrast" forFilter:"adjust"
                       withValue:ITEM_F(4)];
    [core setVideoFilterProperty:"brightness" forFilter:"adjust"
                       withValue:ITEM_F(5)];
    [core setVideoFilterProperty:"saturation" forFilter:"adjust"
                       withValue:ITEM_F(6)];
    [core setVideoFilterProperty:"gamma" forFilter:"adjust"
                       withValue:ITEM_F(7)];
    [core setVideoFilterProperty:"sharpen-sigma" forFilter:"sharpen"
                       withValue:ITEM_F(8)];
    [core setVideoFilterProperty:"gradfun-radius" forFilter:"gradfun"
                       withValue:ITEM_I(9)];
    [core setVideoFilterProperty:"grain-variance" forFilter:"grain"
                       withValue:ITEM_F(10)];
    [core setVideoFilterProperty:"transform-type" forFilter:"transform"
                       withValue:ITEM_S(11)];
    [core setVideoFilterProperty:"puzzle-rows" forFilter:"puzzle"
                       withValue:ITEM_I(12)];
    [core setVideoFilterProperty:"puzzle-cols" forFilter:"puzzle"
                       withValue:ITEM_I(13)];
    [core setVideoFilterProperty:"colorthres-color" forFilter:"colorthres"
                       withValue:ITEM_I(14)];
    [core setVideoFilterProperty:"colorthres-saturationthres"
                       forFilter:"colorthres" withValue:ITEM_I(15)];
    [core setVideoFilterProperty:"colorthres-similaritythres"
                       forFilter:"colorthres" withValue:ITEM_I(16)];
    [core setVideoFilterProperty:"sepia-intensity" forFilter:"sepia"
                       withValue:ITEM_I(17)];
    [core setVideoFilterProperty:"gradient-mode" forFilter:"gradient"
                       withValue:ITEM_S(18)];
    [core setVideoFilterProperty:"gradient-cartoon" forFilter:"gradient"
                       withValue:ITEM_B(19)];
    [core setVideoFilterProperty:"gradient-type" forFilter:"gradient"
                       withValue:ITEM_I(20)];
    [core setVideoFilterProperty:"extract-component" forFilter:"extract"
                       withValue:ITEM_I(21)];
    [core setVideoFilterProperty:"posterize-level" forFilter:"posterize"
                       withValue:ITEM_I(22)];
    [core setVideoFilterProperty:"blur-factor" forFilter:"motionblur"
                       withValue:ITEM_I(23)];
    [core setVideoFilterProperty:"marq-marquee" forFilter:"marq"
                       withValue:ITEM_S(24)];
    [core setVideoFilterProperty:"marq-position" forFilter:"marq"
                       withValue:ITEM_I(25)];
    [core setVideoFilterProperty:"logo-file" forFilter:"logo"
                       withValue:ITEM_S(26)];
    [core setVideoFilterProperty:"logo-position" forFilter:"logo"
                       withValue:ITEM_I(27)];
    [core setVideoFilterProperty:"logo-opacity" forFilter:"logo"
                       withValue:ITEM_I(28)];
    [core setVideoFilterProperty:"clone-count" forFilter:"clone"
                       withValue:ITEM_I(29)];
    [core setVideoFilterProperty:"wall-rows" forFilter:"wall"
                       withValue:ITEM_I(30)];
    [core setVideoFilterProperty:"wall-cols" forFilter:"wall"
                       withValue:ITEM_I(31)];

    if ([items count] >= 33)
        [core setVideoFilterProperty:"brightness-threshold"
                           forFilter:"adjust" withValue:ITEM_B(32)];
    if ([items count] >= 34)
        [core setVideoFilterProperty:"hue" forFilter:"adjust"
                           withValue:ITEM_F(33)];
    else {
        /* profiles from before 3.0 stored hue as an int in [0, 360] */
        float hueValue = [[items objectAtIndex:3] floatValue] - 180.0f;
        [core setVideoFilterProperty:"hue" forFilter:"adjust"
                           withValue:valFloat(hueValue)];
    }
#undef ITEM_F
#undef ITEM_I
#undef ITEM_B
#undef ITEM_S
}

- (void)resetProfileSelector
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
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
               action:@selector(addProfile:) keyEquivalent:@""] autorelease];
    [item setTarget:self];
    [[profilePopup menu] addItem:item];
    if ([nonDefault count]) {
        item = [[[NSMenuItem alloc]
            initWithTitle:_NS("Organize profiles...")
                   action:@selector(removeProfile:) keyEquivalent:@""]
            autorelease];
        [item setTarget:self];
        [[profilePopup menu] addItem:item];
    }

    NSInteger selected = [self currentProfileIndex];
    if (selected < 0
     || (unsigned)selected >= [nonDefault count] + 1)
        selected = 0;
    [profilePopup selectItemAtIndex:selected];
    /* only non-default profiles are loaded on selection, so a saved
     * vlcrc/command-line setup is never overwritten silently */
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
        [defaults objectForKey:VE_PROFILES_KEY]];
    if ((unsigned)index >= [profiles count])
        return;
    [profiles replaceObjectAtIndex:index
                        withObject:[self generateProfileString]];
    [defaults setObject:profiles forKey:VE_PROFILES_KEY];
    [defaults synchronize];
}

- (void)saveCurrentProfileAtTerminate
{
    if ([self currentProfileIndex] > 0) {
        [self saveCurrentProfile];
        return;
    }
    /* profile 0 is never saved; auto-create a custom one when the user
     * asked to re-apply the current setup at next launch */
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *profileString = [self generateProfileString];
    if (![defaults boolForKey:VE_APPLY_ON_STARTUP]
     || [profileString isEqualToString:kDefaultProfileString])
        return;

    NSMutableArray *profiles = [NSMutableArray arrayWithArray:
        [defaults objectForKey:VE_PROFILES_KEY]];
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [defaults objectForKey:VE_PROFILE_NAMES_KEY]];
    int number = 0;
    NSString *name;
    do {
        name = [NSString stringWithFormat:@"Custom%03i", number++];
    } while ([names containsObject:name]);
    [profiles addObject:profileString];
    [names addObject:name];
    [defaults setObject:profiles forKey:VE_PROFILES_KEY];
    [defaults setObject:names forKey:VE_PROFILE_NAMES_KEY];
    [defaults setInteger:(NSInteger)[profiles count] - 1
                  forKey:VE_SELECTED_KEY];
    [defaults synchronize];
}

- (void)profileSelectorAction:(id)sender
{
    [self saveCurrentProfile];
    [[NSUserDefaults standardUserDefaults]
        setInteger:[profilePopup indexOfSelectedItem]
            forKey:VE_SELECTED_KEY];
    [self loadProfile];
    [self resetValues];
}

- (void)addProfile:(id)sender
{
    /* the popup selection moved to the action item; restore it first */
    [profilePopup selectItemAtIndex:[self currentProfileIndex]];

    NSString *name = VLCLegacyRunTextPrompt(
        _NS("Duplicate current profile for a new profile"),
        _NS("Enter a name for the new profile:"),
        _NS("Save"), _NS("Cancel"), @"");
    if (!name)
        return;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [defaults objectForKey:VE_PROFILE_NAMES_KEY]];
    if (![name length] || [names containsObject:name]) {
        NSRunAlertPanel(_NS("Please enter a unique name for the new "
                            "profile."),
                        @"%@", _NS("OK"), nil, nil,
                        _NS("Multiple profiles with the same name are not "
                            "allowed."));
        return;
    }

    NSMutableArray *profiles = [NSMutableArray arrayWithArray:
        [defaults objectForKey:VE_PROFILES_KEY]];
    [profiles addObject:[self generateProfileString]];
    [names addObject:name];
    [defaults setObject:profiles forKey:VE_PROFILES_KEY];
    [defaults setObject:names forKey:VE_PROFILE_NAMES_KEY];
    [defaults setInteger:(NSInteger)[profiles count] - 1
                  forKey:VE_SELECTED_KEY];
    [defaults synchronize];
    [self resetProfileSelector];
}

- (void)removeProfile:(id)sender
{
    [profilePopup selectItemAtIndex:[self currentProfileIndex]];

    NSInteger index = VLCLegacyRunPopupPrompt(
        _NS("Remove a preset"),
        _NS("Select the preset you would like to remove:"),
        _NS("Remove"), _NS("Cancel"),
        [self nonDefaultProfileNames]);
    if (index < 0)
        return;
    index++;   /* the Default entry is not offered for removal */

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray *profiles = [NSMutableArray arrayWithArray:
        [defaults objectForKey:VE_PROFILES_KEY]];
    NSMutableArray *names = [NSMutableArray arrayWithArray:
        [defaults objectForKey:VE_PROFILE_NAMES_KEY]];
    if ((unsigned)index >= [profiles count])
        return;
    [profiles removeObjectAtIndex:index];
    [names removeObjectAtIndex:index];
    [defaults setObject:profiles forKey:VE_PROFILES_KEY];
    [defaults setObject:names forKey:VE_PROFILE_NAMES_KEY];
    if ([self currentProfileIndex] >= index)
        [defaults setInteger:[self currentProfileIndex] - 1
                      forKey:VE_SELECTED_KEY];
    [defaults synchronize];
    [self resetProfileSelector];
}

- (void)applyProfileCheckboxChanged:(id)sender
{
    [[NSUserDefaults standardUserDefaults]
        setBool:[sender state] == NSOnState forKey:VE_APPLY_ON_STARTUP];
}

@end
