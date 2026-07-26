/*****************************************************************************
 * darwin.c : Put text on the video, using freetype2
 *****************************************************************************
 * Copyright (C) 2015 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne@videolan.org>
 *          Jean-Baptiste Kempf <jb@videolan.org>
 *          Salah-Eddin Shaban <salshaaban@gmail.com>
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
 * along with this program; if not, write to the Free Software Foundation, Inc.,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

/*****************************************************************************
 * Preamble
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_filter.h>                                      /* filter_sys_t */
#include <vlc_charset.h>                                     /* FromCFString */

#include <CoreFoundation/CoreFoundation.h>
#include <CoreText/CoreText.h>
#include <ApplicationServices/ApplicationServices.h>   /* ATS (pre-10.6 fallback) */
#include <limits.h>                                     /* PATH_MAX */

#include "../platform_fonts.h"

/* ATSFontGetFileReference is a 10.5 symbol not declared by the 10.4 SDK headers.
 * Declare it and weak-import it so the plugin still loads on 10.4 (where it just
 * yields no path); on 10.5 it resolves a font's file the way CoreText's
 * kCTFontURLAttribute does from 10.6 on. */
extern OSStatus ATSFontGetFileReference(ATSFontRef iFont, FSRef *oFile)
    __attribute__((weak_import));

char* getPathForFontDescription(CTFontDescriptorRef fontDescriptor);
void addNewFontToFamily(filter_t *p_filter, CTFontDescriptorRef iter, char *path, vlc_family_t *family, int index);

/* Resolve a font descriptor's file path on Mac OS X 10.5, where
 * kCTFontURLAttribute (10.6+) is unavailable. Returns a malloc'd POSIX path or
 * NULL. */
static char *getPathForFontDescriptionPre106(CTFontDescriptorRef fontDescriptor)
{
    if (&ATSFontGetFileReference == NULL)
        return NULL;
    CFStringRef psname =
        CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontNameAttribute);
    if (psname == NULL)
        return NULL;
    ATSFontRef atsFont = ATSFontFindFromPostScriptName(psname, kATSOptionFlagsDefault);
    CFRelease(psname);
    if (atsFont == (ATSFontRef)0 || atsFont == kATSFontRefUnspecified)
        return NULL;
    FSRef fsRef;
    if (ATSFontGetFileReference(atsFont, &fsRef) != noErr)
        return NULL;
    UInt8 path[PATH_MAX];
    if (FSRefMakePath(&fsRef, path, sizeof(path)) != noErr)
        return NULL;
    return strdup((char *)path);
}


char* getPathForFontDescription(CTFontDescriptorRef fontDescriptor)
{
    /* kCTFontURLAttribute requires Mac OS X 10.6; fall back to ATS on 10.5. */
    CFURLRef url = NULL;
    if (__builtin_available(macOS 10.6, *))
        url = CTFontDescriptorCopyAttribute(fontDescriptor, kCTFontURLAttribute);
    if (url == NULL)
        return getPathForFontDescriptionPre106(fontDescriptor);
    CFStringRef path = CFURLCopyFileSystemPath(url, kCFURLPOSIXPathStyle);
    if (path == NULL) {
        CFRelease(url);
        return NULL;
    }
    char *retPath = FromCFString(path, kCFStringEncodingUTF8);
    CFRelease(path);
    CFRelease(url);
    return retPath;
}

static CFIndex getFontIndexInFontFile(const char* psz_filePath, const char* psz_family) {
    CFIndex index = kCFNotFound;
    CFURLRef url = CFURLCreateFromFileSystemRepresentation(kCFAllocatorDefault, (const UInt8 *)psz_filePath, strlen(psz_filePath), false);
    if (url == NULL) {
        return kCFNotFound;
    }
    /* CTFontManagerCreateFontDescriptorsFromURL() requires Mac OS X 10.6. */
    CFArrayRef fontDescriptors;
    if (__builtin_available(macOS 10.6, *))
        fontDescriptors = CTFontManagerCreateFontDescriptorsFromURL(url);
    else {
        CFRelease(url);
        return kCFNotFound;
    }
    if (fontDescriptors == NULL) {
        CFRelease(url);
        return kCFNotFound;
    }
    CFIndex numberOfFontDescriptors = CFArrayGetCount(fontDescriptors);
    CFStringRef targetFontName = CFStringCreateWithCString(kCFAllocatorDefault, psz_family, kCFStringEncodingUTF8);
    if (targetFontName == NULL) {
        CFRelease(fontDescriptors);
        CFRelease(url);
        return kCFNotFound;
    }

    for (CFIndex i = 0; i < numberOfFontDescriptors; i++) {
        CTFontDescriptorRef descriptor = (CTFontDescriptorRef)CFArrayGetValueAtIndex(fontDescriptors, i);
        CFStringRef familyName = (CFStringRef)CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute);
        CFStringRef fontName = (CFStringRef)CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute);
        CFStringRef displayName = (CFStringRef)CTFontDescriptorCopyAttribute(descriptor, kCTFontDisplayNameAttribute);

        if (CFStringCompare(targetFontName, familyName, kCFCompareCaseInsensitive) == kCFCompareEqualTo ||
            CFStringCompare(targetFontName, fontName, kCFCompareCaseInsensitive) == kCFCompareEqualTo ||
            CFStringCompare(targetFontName, displayName, kCFCompareCaseInsensitive) == kCFCompareEqualTo) {
            index = i;
        }

        CFRelease(familyName);
        CFRelease(fontName);
        CFRelease(displayName);

        if (index != kCFNotFound) {
            break;
        }
    }
    CFRelease(targetFontName);
    CFRelease(fontDescriptors);
    CFRelease(url);
    return index;
}

void addNewFontToFamily(filter_t *p_filter, CTFontDescriptorRef iter, char *path, vlc_family_t *family, int index)
{
    bool b_bold = false;
    bool b_italic = false;
    CFDictionaryRef fontTraits = CTFontDescriptorCopyAttribute(iter, kCTFontTraitsAttribute);
    CFNumberRef trait = CFDictionaryGetValue(fontTraits, kCTFontWeightTrait);
    float traitValue = 0.;
    CFNumberGetValue(trait, kCFNumberFloatType, &traitValue);
    b_bold = traitValue > 0.23;
    trait = CFDictionaryGetValue(fontTraits, kCTFontSlantTrait);
    traitValue = 0.;
    CFNumberGetValue(trait, kCFNumberFloatType, &traitValue);
    b_italic = traitValue > 0.03;

#ifndef NDEBUG
    msg_Dbg(p_filter, "New font: bold %i italic %i path '%s'", b_bold, b_italic, path);
#else
    VLC_UNUSED(p_filter);
#endif
    NewFont(path, index, b_bold, b_italic, family);

    CFRelease(fontTraits);
}

const vlc_family_t *CoreText_GetFamily(filter_t *p_filter, const char *psz_family)
{
    filter_sys_t *p_sys = p_filter->p_sys;

    if (unlikely(psz_family == NULL)) {
        return NULL;
    }

    char *psz_lc = ToLower(psz_family);
    if (unlikely(!psz_lc)) {
        return NULL;
    }

    /* let's double check if we have parsed this family already */
    vlc_family_t *p_family = vlc_dictionary_value_for_key(&p_sys->family_map, psz_lc);
    if (p_family) {
        free(psz_lc);
        return p_family;
    }

    CTFontCollectionRef coreTextFontCollection = NULL;
    CFArrayRef matchedFontDescriptions = NULL;

    /* we search for family name, display name and name to find them all */
    const size_t numberOfAttributes = 3;
    CTFontDescriptorRef coreTextFontDescriptors[numberOfAttributes];
    CFMutableDictionaryRef coreTextAttributes[numberOfAttributes];
    CFStringRef attributeNames[numberOfAttributes] = {
        kCTFontFamilyNameAttribute,
        kCTFontDisplayNameAttribute,
        kCTFontNameAttribute,
    };

#ifndef NDEBUG
    msg_Dbg(p_filter, "Creating new family for '%s'", psz_family);
#endif

    CFStringRef familyName = CFStringCreateWithCString(kCFAllocatorDefault,
                                                       psz_family,
                                                       kCFStringEncodingUTF8);
    for (size_t x = 0; x < numberOfAttributes; x++) {
        coreTextAttributes[x] = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, NULL, NULL);
        CFDictionaryAddValue(coreTextAttributes[x], attributeNames[x], familyName);
        coreTextFontDescriptors[x] = CTFontDescriptorCreateWithAttributes(coreTextAttributes[x]);
    }

    CFArrayRef coreTextFontDescriptorsArray = CFArrayCreate(kCFAllocatorDefault,
                                                            (const void **)&coreTextFontDescriptors,
                                                            numberOfAttributes, NULL);

    coreTextFontCollection = CTFontCollectionCreateWithFontDescriptors(coreTextFontDescriptorsArray, 0);
    if (coreTextFontCollection == NULL) {
        msg_Warn(p_filter,"CTFontCollectionCreateWithFontDescriptors (1) failed!");
        goto end;
    }

    matchedFontDescriptions = CTFontCollectionCreateMatchingFontDescriptors(coreTextFontCollection);
    if (matchedFontDescriptions == NULL) {
        msg_Warn(p_filter, "CTFontCollectionCreateMatchingFontDescriptors (2) failed!");
        goto end;
    }

    CFIndex numberOfFoundFontDescriptions = CFArrayGetCount(matchedFontDescriptions);

    char *path = NULL;

    /* create a new family object */
    p_family = NewFamily(p_filter, psz_lc, &p_sys->p_families, &p_sys->family_map, psz_lc);
    if (unlikely(!p_family)) {
        goto end;
    }

    for (CFIndex i = 0; i < numberOfFoundFontDescriptions; i++) {
        CTFontDescriptorRef iter = CFArrayGetValueAtIndex(matchedFontDescriptions, i);
        path = getPathForFontDescription(iter);

        /* check if the path is empty, which can happen in rare circumstances */
        if (path == NULL || *path == '\0') {
            FREENULL(path);
            continue;
        }

        /* get the index of the font family in the font file */
        CFIndex fontIndex = getFontIndexInFontFile(path, psz_lc);
        if (fontIndex == kCFNotFound) {
            FREENULL(path);
            continue;
        }

        addNewFontToFamily(p_filter, iter, path, p_family, fontIndex);
    }

end:
    if (matchedFontDescriptions != NULL) {
        CFRelease(matchedFontDescriptions);
    }
    if (coreTextFontCollection != NULL) {
        CFRelease(coreTextFontCollection);
    }

    for (size_t x = 0; x < numberOfAttributes; x++) {
        CFRelease(coreTextAttributes[x]);
        CFRelease(coreTextFontDescriptors[x]);
    }

    CFRelease(coreTextFontDescriptorsArray);
    CFRelease(familyName);
    free(psz_lc);

    return p_family;
}

vlc_family_t *CoreText_GetFallbacks(filter_t *p_filter, const char *psz_family, uni_char_t codepoint)
{
    filter_sys_t *p_sys = p_filter->p_sys;
    if (unlikely(psz_family == NULL)) {
        return NULL;
    }

    vlc_family_t *p_family = NULL;
    CFStringRef postScriptFallbackFontname = NULL;
    CTFontDescriptorRef fallbackFontDescriptor = NULL;
    char *psz_lc_fallback = NULL;
    char *psz_fontPath = NULL;

    CFStringRef familyName = CFStringCreateWithCString(kCFAllocatorDefault,
                                                       psz_family,
                                                       kCFStringEncodingUTF8);
    CTFontRef font = CTFontCreateWithName(familyName, 0, NULL);
    uint32_t littleEndianCodePoint = OSSwapHostToLittleInt32(codepoint);
    CFStringRef codepointString = CFStringCreateWithBytes(kCFAllocatorDefault,
                                                          (const UInt8 *)&littleEndianCodePoint,
                                                          sizeof(littleEndianCodePoint),
                                                          kCFStringEncodingUTF32LE,
                                                          false);
    CTFontRef fallbackFont = CTFontCreateForString(font, codepointString, CFRangeMake(0,1));
    CFStringRef fallbackFontFamilyName = CTFontCopyFamilyName(fallbackFont);

    /* create a new family object */
    char *psz_fallbackFamilyName = FromCFString(fallbackFontFamilyName, kCFStringEncodingUTF8);
    if (psz_fallbackFamilyName == NULL) {
        msg_Warn(p_filter, "Failed to convert font family name CFString to C string");
        goto done;
    }
#ifndef NDEBUG
    msg_Dbg(p_filter, "Will deploy fallback font '%s'", psz_fallbackFamilyName);
#endif

    psz_lc_fallback = ToLower(psz_fallbackFamilyName);

    p_family = vlc_dictionary_value_for_key(&p_sys->family_map, psz_lc_fallback);
    if (p_family) {
        goto done;
    }

    p_family = NewFamily(p_filter, psz_lc_fallback, &p_sys->p_families, &p_sys->family_map, psz_lc_fallback);
    if (unlikely(!p_family)) {
        goto done;
    }

    postScriptFallbackFontname = CTFontCopyPostScriptName(fallbackFont);
    fallbackFontDescriptor = CTFontDescriptorCreateWithNameAndSize(postScriptFallbackFontname, 0.);
    psz_fontPath = getPathForFontDescription(fallbackFontDescriptor);

    /* check if the path is empty, which can happen in rare circumstances */
    if (psz_fontPath == NULL || *psz_fontPath == '\0') {
        goto done;
    }

    /* get the index of the font family in the font file */
    CFIndex fontIndex = getFontIndexInFontFile(psz_fontPath, psz_fallbackFamilyName);
    if (fontIndex == kCFNotFound) {
        goto done;
    }

    addNewFontToFamily(p_filter, fallbackFontDescriptor, strdup(psz_fontPath), p_family, fontIndex);

done:
    CFRelease(familyName);
    CFRelease(font);
    CFRelease(codepointString);
    CFRelease(fallbackFont);
    CFRelease(fallbackFontFamilyName);
    free(psz_fallbackFamilyName);
    free(psz_lc_fallback);
    free(psz_fontPath);
    if (postScriptFallbackFontname != NULL)
        CFRelease(postScriptFallbackFontname);
    if (fallbackFontDescriptor != NULL)
        CFRelease(fallbackFontDescriptor);
    return p_family;
}
