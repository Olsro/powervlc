/*****************************************************************************
 * nsspeechsynthesizer.m: Simple text to Speech renderer for Mac OS X
 *****************************************************************************
 * Copyright (C) 2015 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan # org>
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

/*****************************************************************************
 * Preamble
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_filter.h>
#include <vlc_subpicture.h>

#import <Cocoa/Cocoa.h>

/* NSUInteger only appeared with the 10.5 SDK */
#ifndef NSINTEGER_DEFINED
typedef int NSInteger;
typedef unsigned int NSUInteger;
#define NSINTEGER_DEFINED 1
#endif

/* Mac OS X 10.2's Objective-C runtime walks the __module_info records of
 * every image it is handed and reads module->symtab without checking it for
 * NULL -- and GCC leaves exactly that pointer NULL in an Objective-C file
 * that defines no class of its own, as this one does not. The result is not
 * a plug-in that declines to load: it is a bus error inside _objcInit(),
 * which takes the whole process down the moment the plug-in is dlopen()ed.
 * One throwaway class gives the module a symtab and settles it.
 * extras/package/macosx/check-objc-modules.sh guards against it coming back. */
@interface VLCSpeechSynthesizerModuleAnchor : NSObject
@end
@implementation VLCSpeechSynthesizerModuleAnchor
@end

static int Create (vlc_object_t *);
static void Destroy(vlc_object_t *);
static int RenderText(filter_t *,
                      subpicture_region_t *,
                      subpicture_region_t *,
                      const vlc_fourcc_t *);

vlc_module_begin ()
set_description(N_("Speech synthesis for Mac OS X"))
set_category(CAT_VIDEO)
set_subcategory(SUBCAT_VIDEO_SUBPIC)

set_capability("text renderer", 0)
set_callbacks(Create, Destroy)
vlc_module_end ()

struct filter_sys_t
{
    id speechSynthesizer;   /* an NSSpeechSynthesizer, see Create() */
    NSString *currentLocale;
    NSString *lastString;
};

/* NSSpeechSynthesizer arrived with 10.3, and naming it literally would emit a
 * hard .objc_class_name_ reference -- which on 10.2 stops this plug-in from
 * loading rather than merely making it decline the job. Resolved by name, the
 * module simply reports failure there. */
static Class SpeechSynthesizerClass(void)
{
    return NSClassFromString(@"NSSpeechSynthesizer");
}

static int  Create (vlc_object_t *p_this)
{
    filter_t *p_filter = (filter_t *)p_this;
    filter_sys_t *p_sys;
    Class synthClass = SpeechSynthesizerClass();

    if (synthClass == Nil) {
        msg_Dbg(p_filter, "no speech synthesizer on this system version");
        return VLC_EGENERIC;
    }

    p_filter->p_sys = p_sys = malloc(sizeof(filter_sys_t));
    if (!p_sys)
        return VLC_ENOMEM;

    p_sys->currentLocale = p_sys->lastString = @"";
    p_sys->speechSynthesizer = [[synthClass alloc] init];

    p_filter->pf_render = RenderText;

    return VLC_SUCCESS;
}

static void Destroy(vlc_object_t *p_this)
{
    filter_t *p_filter = (filter_t *)p_this;
    filter_sys_t *p_sys = p_filter->p_sys;

    [p_sys->speechSynthesizer stopSpeaking];
    [p_sys->speechSynthesizer release];
    p_sys->speechSynthesizer = nil;

    [p_sys->lastString release];
    p_sys->lastString = nil;

    [p_sys->currentLocale release];
    p_sys->currentLocale = nil;

    free(p_sys);
}

static NSString * languageCodeForString(NSString *string) {
#if defined(MAC_OS_X_VERSION_MAX_ALLOWED) && MAC_OS_X_VERSION_MAX_ALLOWED < 1050
    /* CFStringTokenizer is 10.5+; keep the default voice on Tiger */
    (void)string;
    return nil;
#else
    return (NSString *)CFStringTokenizerCopyBestStringLanguage((CFStringRef)string, CFRangeMake(0, [string length]));
#endif
}

static int RenderText(filter_t *p_filter,
                      subpicture_region_t *p_region_out,
                      subpicture_region_t *p_region_in,
                      const vlc_fourcc_t *p_chroma_list)
{
    /* explicit pool: @autoreleasepool is clang-only and this file stays
     * MRC anyway (the two are equivalent without ARC) */
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    {
        filter_sys_t *p_sys = p_filter->p_sys;
        text_segment_t *p_segment = p_region_in->p_text;

        if (!p_segment) {
            [pool release];
            return VLC_EGENERIC;
        }

        for ( const text_segment_t *s = p_segment; s != NULL; s = s->p_next ) {
            if ( !s->psz_text )
                continue;

            if (strlen(s->psz_text) == 0)
                continue;

            NSString *stringToSpeech = [NSString stringWithUTF8String:s->psz_text];

            if ([p_sys->lastString isEqualToString:stringToSpeech])
                continue;

            if ([stringToSpeech isEqualToString:@"\n"])
                continue;

            p_sys->lastString = [stringToSpeech retain];

            msg_Dbg(p_filter, "Speaking '%s'", [stringToSpeech UTF8String]);

            NSString *detectedLocale = languageCodeForString(stringToSpeech);
            if (detectedLocale != nil) {
                if (![detectedLocale isEqualToString:p_sys->currentLocale]) {
                    p_sys->currentLocale = [detectedLocale retain];
                    msg_Dbg(p_filter, "switching speaker locale to '%s'", [p_sys->currentLocale UTF8String]);
                    NSArray *voices = [SpeechSynthesizerClass() availableVoices];
                    NSUInteger count = [voices count];
                    NSRange range = NSMakeRange(0, 2);

                    for (NSUInteger i = 0; i < count; i++) {
                        NSDictionary *voiceAttributes = [SpeechSynthesizerClass() attributesForVoice: [voices objectAtIndex:i]];
                        NSString *voiceLanguage = [voiceAttributes objectForKey:@"VoiceLanguage"];
                        if ([p_sys->currentLocale isEqualToString:[voiceLanguage substringWithRange:range]]) {
                            NSString *voiceName = [voiceAttributes objectForKey:@"VoiceName"];
                            msg_Dbg(p_filter, "switched to voice '%s'", [voiceName UTF8String]);
                            if ([voiceName isEqualToString:@"Agnes"] || [voiceName isEqualToString:@"Albert"])
                                continue;
                            [p_sys->speechSynthesizer setVoice: [voices objectAtIndex:i]];
                            break;
                        }
                    }
                }
            }

            [p_sys->speechSynthesizer startSpeakingString:stringToSpeech];
        }

        [pool release];
        return VLC_SUCCESS;
    }
}
