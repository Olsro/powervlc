/*****************************************************************************
 * VLCLegacyTrackSync.m: track synchronization window (legacy interface)
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

#import "VLCLegacyTrackSync.h"
#import "VLCLegacyCoreInteraction.h"

#include <vlc_playlist.h>
#include <vlc_input.h>
#include <vlc_vout.h>

#define _NS(s) ((NSString *)[NSString stringWithUTF8String:vlc_gettext(s)])

#define SUBSDELAY_CFG_MODE   "subsdelay-mode"
#define SUBSDELAY_CFG_FACTOR "subsdelay-factor"
#define SUBSDELAY_MODE_ABSOLUTE                0
#define SUBSDELAY_MODE_RELATIVE_SOURCE_DELAY   1
#define SUBSDELAY_MODE_RELATIVE_SOURCE_CONTENT 2

@implementation VLCLegacyTrackSync

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
    [core release];
    [super dealloc];
}

/*****************************************************************************
 * window
 *****************************************************************************/

- (NSTextField *)syncRow:(NSString *)title y:(float)y suffix:(NSString *)unit
                 stepper:(NSStepper **)stepperOut min:(double)min
                     max:(double)max step:(double)step action:(SEL)action
                      in:(NSView *)parent
{
    NSTextField *label = [self hudLabel:title
                                  frame:NSMakeRect(8, y + 2, 236, 14)
                                   bold:NO in:parent];
    [label setAlignment:NSRightTextAlignment];
    NSTextField *field = [self hudValue:NSMakeRect(252, y, 92, 17)
                               editable:YES in:parent];
    [field setAlignment:NSRightTextAlignment];
    [field setTarget:self];
    [field setAction:action];
    [field setDelegate:(id)self];
    NSStepper *stepper = [self hudStepper:NSMakeRect(350, y - 2, 15, 22)
                                      min:min max:max increment:step
                                   action:action in:parent];
    if (stepperOut)
        *stepperOut = stepper;
    if ([unit length])
        [self hudLabel:unit frame:NSMakeRect(372, y + 2, 40, 14)
                  bold:NO in:parent];
    return field;
}

- (void)buildWindow
{
    [self buildHUDWithTitle:_NS("Track Synchronization")
                       size:NSMakeSize(450, 264)
                  tabTitles:nil
               bottomMargin:40];

    NSView *pane = [[[NSView alloc]
        initWithFrame:[[self paneContainer] bounds]] autorelease];
    NSSize size = [pane bounds].size;
    float top = size.height;

    /* Audio/Video group */
    [self hudLabel:_NS("Audio/Video") frame:NSMakeRect(4, top - 18, 200, 15)
              bold:YES in:pane];
    avAdvanceTextField = [self syncRow:_NS("Audio track synchronization:")
                                     y:top - 44 suffix:_NS("s")
                               stepper:&avStepper min:-60 max:60 step:0.5
                                action:@selector(avValueChanged:) in:pane];
    [avAdvanceTextField setToolTip:_NS("A positive value means that the "
        "audio is ahead of the video")];

    /* Subtitles/Video group */
    [self hudLabel:_NS("Subtitles/Video")
             frame:NSMakeRect(4, top - 78, 200, 15) bold:YES in:pane];
    svAdvanceTextField = [self syncRow:_NS("Subtitle track synchronization:")
                                     y:top - 104 suffix:_NS("s")
                               stepper:&svAdvanceStepper min:-60 max:60
                                  step:0.5
                                action:@selector(svAdvanceValueChanged:)
                                    in:pane];
    [svAdvanceTextField setToolTip:_NS("A positive value means that the "
        "subtitles are ahead of the video")];
    svSpeedTextField = [self syncRow:_NS("Subtitle speed:") y:top - 130
                              suffix:_NS("fps")
                             stepper:&svSpeedStepper min:0 max:100 step:0.2
                              action:@selector(svSpeedValueChanged:)
                                  in:pane];
    svDurTextField = [self syncRow:_NS("Subtitle duration factor:")
                                 y:top - 156 suffix:@""
                           stepper:&svDurStepper min:0 max:20 step:0.2
                            action:@selector(svDurationValueChanged:)
                                in:pane];

    /* the duration tooltip depends on the subsdelay mode, like 3.0 */
    int i_mode = (int)var_InheritInteger(p_intf, SUBSDELAY_CFG_MODE);
    switch (i_mode) {
    case SUBSDELAY_MODE_ABSOLUTE:
        [svDurTextField setToolTip:_NS("Extend subtitle duration by this "
            "value.\nSet 0 to disable.")];
        break;
    case SUBSDELAY_MODE_RELATIVE_SOURCE_DELAY:
        [svDurTextField setToolTip:_NS("Multiply subtitle duration by "
            "this value.\nSet 0 to disable.")];
        break;
    case SUBSDELAY_MODE_RELATIVE_SOURCE_CONTENT:
        [svDurTextField setToolTip:_NS("Recalculate subtitle duration "
            "according\nto their content and this value.\nSet 0 to "
            "disable.")];
        break;
    }

    [self setPane:pane atIndex:0];

    /* Reset button in the bottom-left corner, like SyncTracks.xib */
    [self hudPushButton:_NS("Reset") frame:NSMakeRect(14, 10, 80, 22)
                 action:@selector(resetValues:) in:[window contentView]];

    [self resetValues:nil];
}

- (void)windowWillShow
{
    [self updateValues];
    if (!refreshTimer) {
        refreshTimer =
            [NSTimer scheduledTimerWithTimeInterval:2.0
                                             target:self
                                           selector:@selector(refresh:)
                                           userInfo:nil
                                            repeats:YES];
        [[NSRunLoop currentRunLoop] addTimer:refreshTimer
                                     forMode:NSEventTrackingRunLoopMode];
        [[NSRunLoop currentRunLoop] addTimer:refreshTimer
                                     forMode:NSModalPanelRunLoopMode];
    }
}

- (void)closeWindow:(id)sender
{
    [refreshTimer invalidate];
    refreshTimer = nil;
    [super closeWindow:sender];
}

- (void)refresh:(NSTimer *)timer
{
    /* skip while the user edits a field */
    NSResponder *responder = [window firstResponder];
    if ([responder isKindOfClass:[NSText class]])
        return;
    [self updateValues];
}

/*****************************************************************************
 * core synchronisation
 *****************************************************************************/

- (void)updateValues
{
    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (!p_input)
        return;

    [avAdvanceTextField setDoubleValue:
        var_GetInteger(p_input, "audio-delay") / 1000000.0];
    [svAdvanceTextField setDoubleValue:
        var_GetInteger(p_input, "spu-delay") / 1000000.0];
    [svSpeedTextField setFloatValue:var_GetFloat(p_input, "sub-fps")];
    [avStepper setDoubleValue:[avAdvanceTextField doubleValue]];
    [svAdvanceStepper setDoubleValue:[svAdvanceTextField doubleValue]];
    [svSpeedStepper setDoubleValue:[svSpeedTextField doubleValue]];

    vlc_object_release(p_input);
}

- (void)resetValues:(id)sender
{
    [avAdvanceTextField setDoubleValue:0.0];
    [svAdvanceTextField setDoubleValue:0.0];
    [svSpeedTextField setDoubleValue:1.0];
    [svDurTextField setDoubleValue:0.0];
    [avStepper setDoubleValue:0.0];
    [svAdvanceStepper setDoubleValue:0.0];
    [svSpeedStepper setDoubleValue:1.0];
    [svDurStepper setDoubleValue:0.0];

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        var_SetInteger(p_input, "audio-delay", 0);
        var_SetInteger(p_input, "spu-delay", 0);
        var_SetFloat(p_input, "sub-fps", 1.0f);
        vlc_object_release(p_input);
    }
    [self svDurationValueChanged:nil];
}

- (void)controlTextDidEndEditing:(NSNotification *)notification
{
    NSTextField *field = [notification object];
    if ([field action])
        [self performSelector:[field action] withObject:field];
}

- (void)avValueChanged:(id)sender
{
    if (sender == avStepper)
        [avAdvanceTextField setDoubleValue:[avStepper doubleValue]];
    else
        [avStepper setDoubleValue:[avAdvanceTextField doubleValue]];

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        var_SetInteger(p_input, "audio-delay",
            (int64_t)([avAdvanceTextField doubleValue] * 1000000.0));
        vlc_object_release(p_input);
    }
}

- (void)svAdvanceValueChanged:(id)sender
{
    if (sender == svAdvanceStepper)
        [svAdvanceTextField setDoubleValue:[svAdvanceStepper doubleValue]];
    else
        [svAdvanceStepper setDoubleValue:
            [svAdvanceTextField doubleValue]];

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        var_SetInteger(p_input, "spu-delay",
            (int64_t)([svAdvanceTextField doubleValue] * 1000000.0));
        vlc_object_release(p_input);
    }
}

- (void)svSpeedValueChanged:(id)sender
{
    if (sender == svSpeedStepper)
        [svSpeedTextField setDoubleValue:[svSpeedStepper doubleValue]];
    else
        [svSpeedStepper setDoubleValue:[svSpeedTextField doubleValue]];

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        var_SetFloat(p_input, "sub-fps",
                     (float)[svSpeedTextField doubleValue]);
        vlc_object_release(p_input);
    }
}

- (void)svDurationValueChanged:(id)sender
{
    if (sender == svDurStepper)
        [svDurTextField setDoubleValue:[svDurStepper doubleValue]];
    else
        [svDurStepper setDoubleValue:[svDurTextField doubleValue]];

    float factor = (float)[svDurTextField doubleValue];

    input_thread_t *p_input = playlist_CurrentInput(pl_Get(p_intf));
    if (p_input) {
        /* the subsdelay filter reads its factor from the vouts */
        vout_thread_t **pp_vouts;
        size_t i_vouts, i;
        if (!input_Control(p_input, INPUT_GET_VOUTS, &pp_vouts, &i_vouts)
            && pp_vouts) {
            for (i = 0; i < i_vouts; i++) {
                var_SetFloat(pp_vouts[i], SUBSDELAY_CFG_FACTOR, factor);
                vlc_object_release(pp_vouts[i]);
            }
            free(pp_vouts);
        }
        vlc_object_release(p_input);
    }
    /* persist for future vouts too */
    var_Create(pl_Get(p_intf), SUBSDELAY_CFG_FACTOR,
               VLC_VAR_FLOAT | VLC_VAR_DOINHERIT);
    var_SetFloat(pl_Get(p_intf), SUBSDELAY_CFG_FACTOR, factor);

    [core setVideoFilter:"subsdelay" on:factor > 0];
}

@end
