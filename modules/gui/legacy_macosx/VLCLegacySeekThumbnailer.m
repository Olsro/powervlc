/*****************************************************************************
 * VLCLegacySeekThumbnailer.m: seek bar hover thumbnails (legacy interface)
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC authors
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

#ifdef HAVE_CONFIG_H
# import "config.h"
#endif

#import "VLCLegacySeekThumbnailer.h"
#import "VLCLegacyControls.h"

#include <vlc_common.h>
#include <vlc_input.h>
#include <vlc_input_item.h>
#include <vlc_playlist.h>

#include <sys/stat.h>
#include <unistd.h>
/* statfs() : reconnaître un volume optique (cf. VLCLegacyURIIsDiscLike) */
#include <sys/param.h>
#include <sys/mount.h>

/* deliveries must reach the main thread even while it sits in a modal
 * panel or an event-tracking loop (the extension-dialog freeze taught
 * that lesson); NSRunLoopCommonModes only exists since 10.5 */
static NSArray *mainThreadModes(void)
{
    return [NSArray arrayWithObjects:NSDefaultRunLoopMode,
                                     NSEventTrackingRunLoopMode,
                                     NSModalPanelRunLoopMode, nil];
}

/* ⚠ Un DISQUE ou une IMAGE de disque n'est pas prévisualisable : un second
 * lecteur y rouvre le MENU, jamais l'instant visé (même raison qui interdit
 * l'export instantané d'un clip sur disque), et il coûte l'ouverture entière
 * d'un dvdnav ou d'un libbluray. Les schémas de disque (dvd://, bluray://…)
 * sont déjà écartés par le filtre « file:// » ci-dessous -- vérifié sur un
 * DVD réel, aucune entrée secondaire n'est créée. Restait l'image de disque
 * ouverte comme un simple fichier, qui elle passait : on la reconnaît à son
 * extension, ou à l'arborescence d'un disque copié sur le disque dur. */
static BOOL VLCLegacyURIIsDiscLike(NSString *uri)
{
    NSString *lower = [uri lowercaseString];
    if ([lower rangeOfString:@"/video_ts"].location != NSNotFound
     || [lower rangeOfString:@"/bdmv"].location != NSNotFound)
        return YES;
    NSString *ext = [lower pathExtension];
    if ([ext isEqualToString:@"iso"] || [ext isEqualToString:@"img"]
     || [ext isEqualToString:@"bin"] || [ext isEqualToString:@"cue"]
     || [ext isEqualToString:@"nrg"] || [ext isEqualToString:@"mdf"]
     || [ext isEqualToString:@"toast"])
        return YES;

    /* ⚠⚠⚠ LE DISQUE GLISSÉ SUR L'APPLICATION passait tout droit. Ouvert par
     * « Ouvrir un disque » il porte un schéma (dvdsimple://…) que le filtre
     * « file:// » écarte ; GLISSÉ depuis le Finder, c'est le VOLUME MONTÉ,
     * donc `file:///Volumes/ROBOTS` — sans `/video_ts` ni extension d'image.
     * Le survol de la barre lançait alors un second lecteur sur le disque :
     * lecteur optique en surchauffe et image qui se fige à chaque vignette.
     * Deux reconnaissances, l'une comme l'autre suffisante :
     *  - le chemin porte l'arborescence d'un disque (VIDEO_TS / BDMV), ce qui
     *    couvre aussi une copie sur disque dur ;
     *  - le volume est monté en UDF ou ISO 9660 (mesuré sur le Mac mini :
     *    « /dev/disk1 on /Volumes/ROBOTS (udf, local, read-only) »), ce qui
     *    couvre les disques dont l'arborescence nous est inconnue. */
    NSString *path = [[NSURL URLWithString:uri] path];
    if (path == nil)
        return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir) {
        if ([fm fileExistsAtPath:
                [path stringByAppendingPathComponent:@"VIDEO_TS"]]
         || [fm fileExistsAtPath:
                [path stringByAppendingPathComponent:@"BDMV"]])
            return YES;
    }

    {
        struct statfs sfs;
        if (statfs([path fileSystemRepresentation], &sfs) == 0
         && (strcasecmp(sfs.f_fstypename, "udf") == 0
          || strcasecmp(sfs.f_fstypename, "cd9660") == 0))
            return YES;
    }
    return NO;
}

@implementation VLCLegacySeekThumbnailer

static VLCLegacySeekThumbnailer *sharedThumbnailer = nil;

+ (VLCLegacySeekThumbnailer *)sharedInstance
{
    if (!sharedThumbnailer)
        sharedThumbnailer = [[VLCLegacySeekThumbnailer alloc] init];
    return sharedThumbnailer;
}

- (id)init
{
    self = [super init];
    if (self) {
        cache = [[NSMutableDictionary alloc] init];
        cacheOrder = [[NSMutableArray alloc] init];
        sceneDirectory = [[NSTemporaryDirectory()
            stringByAppendingPathComponent:
                [NSString stringWithFormat:@"powervlc-seek-thumbs-%d",
                          getpid()]] retain];
        mkdir([sceneDirectory fileSystemRepresentation], 0700);
    }
    return self;
}

- (void)dealloc
{
    [cache release];
    [cacheOrder release];
    [sceneDirectory release];
    [pendingURI release];
    [pendingCacheKey release];
    [super dealloc];
}

/* Objectif tenu par l'utilisateur : l'aperçu doit apparaître en 3 s maximum
 * après le survol. Le total = anti-rebond (0,5 s) + ce qui suit. On journalise
 * donc le délai RÉEL de bout en bout, seule façon de vérifier l'objectif sur
 * la machine de l'utilisateur plutôt que sur un banc. */
- (void)requestThumbnailWithIntf:(intf_thread_t *)intf
                        fraction:(double)fraction
                       forSlider:(VLCLegacySeekSlider *)slider
{
    if (!intf || !slider)
        return;

    /* opt-out for slow machines: the secondary decode competes with the
     * playback for CPU (measured ~3-4 s alone, ~9 s while playing on an
     * iBook G3); the time/chapter tooltip itself stays */
    if (!var_InheritBool(intf, "legacy-macosx-hover-thumbnails")) {
        [slider setHoverThumbnail:nil forFraction:fraction];
        return;
    }

    /* snapshot what we need from the current input on the main thread */
    input_thread_t *p_input = pl_CurrentInput(intf);
    if (!p_input) {
        [slider setHoverThumbnail:nil forFraction:fraction];
        return;
    }
    input_item_t *p_item = input_GetItem(p_input);
    char *psz_uri = p_item ? input_item_GetURI(p_item) : NULL;
    vlc_tick_t duration = p_item ? input_item_GetDuration(p_item) : 0;
    vlc_object_release(p_input);

    /* local files only: a network stream would open a second connection.
     * ⚠ Chaque refus EFFACE la vignette retenue par la barre : sans cela
     * l'image du média PRÉCÉDENT restait affichée, et on revoyait le menu
     * d'un DVD à des instants sans rapport dès que la position survolée
     * tombait à moins de deux secondes de celle où elle avait été prise. */
    if (!psz_uri || duration <= 0 || strncasecmp(psz_uri, "file://", 7)) {
        free(psz_uri);
        [slider setHoverThumbnail:nil forFraction:fraction];
        return;
    }

    NSString *uri = [NSString stringWithUTF8String:psz_uri];
    free(psz_uri);
    if (!uri || VLCLegacyURIIsDiscLike(uri)) {
        [slider setHoverThumbnail:nil forFraction:fraction];
        return;
    }

    double seconds = fraction * ((double)duration / CLOCK_FREQ);
    NSString *cacheKey = [NSString stringWithFormat:@"%@#%d",
                          uri, (int)(seconds + 0.5)];

    NSImage *cached = [cache objectForKey:cacheKey];
    if (cached) {
        [slider setHoverThumbnail:cached forFraction:fraction];
        return;
    }

    /* remember only the latest request; whatever was pending is stale */
    [pendingURI release];
    pendingURI = [uri retain];
    [pendingCacheKey release];
    pendingCacheKey = [cacheKey retain];
    pendingSeconds = seconds;
    pendingFraction = fraction;
    pendingSlider = slider;
    hasPending = YES;

    if (!busy) {
        busy = YES;
        [self startWorkerWithIntf:intf];
    }
}

- (void)startWorkerWithIntf:(intf_thread_t *)intf
{
    hasPending = NO;
    NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:
        [NSNumber numberWithLongLong:(long long)mdate()], @"started",
        pendingURI, @"uri",
        [NSNumber numberWithDouble:pendingSeconds], @"seconds",
        [NSNumber numberWithDouble:pendingFraction], @"fraction",
        pendingCacheKey, @"key",
        [NSValue valueWithPointer:intf], @"intf",
        nil];
    [NSThread detachNewThreadSelector:@selector(workerWithParams:)
                             toTarget:self
                           withObject:params];
}

/* worker thread */
- (void)workerWithParams:(NSDictionary *)params
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

    NSImage *image = [self
        renderThumbnailWithIntf:(intf_thread_t *)
            [[params objectForKey:@"intf"] pointerValue]
                            URI:[params objectForKey:@"uri"]
                      atSeconds:[[params objectForKey:@"seconds"]
                                    doubleValue]];

    NSMutableDictionary *result =
        [NSMutableDictionary dictionaryWithDictionary:params];
    if (image)
        [result setObject:image forKey:@"image"];
    [self performSelectorOnMainThread:@selector(workerDone:)
                           withObject:result
                        waitUntilDone:NO
                                modes:mainThreadModes()];
    [pool release];
}

/* back on the main thread */
- (void)workerDone:(NSDictionary *)result
{
    busy = NO;

    NSNumber *started = [result objectForKey:@"started"];
    if (started != nil) {
        intf_thread_t *intf =
            (intf_thread_t *)[[result objectForKey:@"intf"] pointerValue];
        if (intf != NULL)
            msg_Dbg(intf, "seek thumbnail ready in %.2f s%s",
                    (double)(mdate() - (mtime_t)[started longLongValue])
                        / (double)CLOCK_FREQ,
                    [result objectForKey:@"image"] ? "" : " (empty)");
    }

    NSImage *image = [result objectForKey:@"image"];
    NSString *key = [result objectForKey:@"key"];
    if (image && key && ![cache objectForKey:key]) {
        [cache setObject:image forKey:key];
        [cacheOrder addObject:key];
        while ([cacheOrder count] > 60) {
            [cache removeObjectForKey:[cacheOrder objectAtIndex:0]];
            [cacheOrder removeObjectAtIndex:0];
        }
    }

    if (image && pendingSlider)
        [pendingSlider setHoverThumbnail:image
                             forFraction:[[result objectForKey:@"fraction"]
                                             doubleValue]];

    /* the mouse moved on while rendering: serve the newest position */
    if (hasPending && pendingCacheKey && ![pendingCacheKey isEqualToString:key]) {
        intf_thread_t *intf = (intf_thread_t *)
            [[result objectForKey:@"intf"] pointerValue];
        busy = YES;
        [self startWorkerWithIntf:intf];
    } else
        hasPending = NO;
}

/* Runs on the worker thread: silent secondary input whose sout re-encodes
 * the decoded frames with VLC's own png encoder into a temporary file
 * (the contribs' ffmpeg carries no encoder at all, and the video output
 * path never instantiates a vout for such a headless input). The input is
 * stopped by hand as soon as the first frame has been written, and bounded
 * by a stop-time in case that ever misses. Since the core seeks start-time
 * synchronously (before the main loop demuxes anything), the first png IS
 * the wanted frame. */
/* ⚠⚠⚠ Le fichier produit n'est PAS un PNG : c'est un flux élémentaire qui
 * mêle plusieurs images ET la piste de SOUS-TITRES. Mesuré sur le fichier
 * réellement écrit : 160 500 octets, quatre signatures PNG, et **68 octets de
 * texte de sous-titre en tête** (« Mme la pr… ») avant la première image.
 *
 * Le code lisait le fichier entier et le passait tel quel à `-initWithData:`,
 * en pariant sur un lecteur capable de ne décoder que la première image. Il ne
 * voyait en réalité même pas un en-tête PNG et rendait NIL : l'aperçu
 * n'apparaissait JAMAIS, alors que le journal montrait la vignette « prête »
 * et que le fichier était bien sur le disque.
 *
 * On extrait donc la première image nous-mêmes, de sa SIGNATURE au IEND qui
 * la referme (4 octets de type + 4 de CRC). Vérifié : les 39 277 octets ainsi
 * découpés décodent en 240x136. La cause amont est traitée en parallèle
 * (`no-sout-spu`), mais ce découpage reste la garantie : rien n'oblige le
 * multiplexeur à commencer par une image. */
static NSData *VLCFirstPNGFrame(NSData *data)
{
    /* ⚠ SDK 10.4 : pas de NSUInteger, et le GCC d'époque refuse une
     * déclaration dans l'en-tête d'une boucle — tout est déclaré ici. */
    static const unsigned char p_signature[8] =
        { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
    const unsigned char *bytes = (const unsigned char *)[data bytes];
    unsigned int len = (unsigned int)[data length];
    unsigned int start, i;

    if (bytes == NULL || len < sizeof(p_signature) + 12)
        return nil;

    for (start = 0; start + sizeof(p_signature) <= len; start++) {
        if (memcmp(bytes + start, p_signature, sizeof(p_signature)) != 0)
            continue;
        for (i = start + sizeof(p_signature); i + 8 <= len; i++)
            if (memcmp(bytes + i, "IEND", 4) == 0)
                return [data subdataWithRange:
                            NSMakeRange(start, i + 8 - start)];
        break;      /* une image entamée mais jamais refermée */
    }
    return nil;
}

- (NSImage *)renderThumbnailWithIntf:(intf_thread_t *)intf
                                 URI:(NSString *)uri
                           atSeconds:(double)seconds
{
    if (!intf)
        return nil;

    NSString *pngPath =
        [sceneDirectory stringByAppendingPathComponent:@"hover.png"];
    [[NSFileManager defaultManager] removeFileAtPath:pngPath handler:nil];

    input_item_t *p_item = input_item_New([uri UTF8String], "seek-thumbnail");
    if (!p_item)
        return nil;

    char *psz_option;
    if (asprintf(&psz_option, "start-time=%.3f", seconds) != -1) {
        input_item_AddOption(p_item, psz_option, VLC_INPUT_OPTION_TRUSTED);
        free(psz_option);
    }
    /* Bound what the encoder is allowed to write: the poll below is meant to
     * stop the input on the first frame, but if it ever misses, this keeps a
     * hover from transcoding the rest of the film. Measured on the iBook G3
     * (Jaguar, 480p), from the first written byte to the input stopping:
     * 277 kB and 5512 ms without, 120 kB and 5333 ms with -- the image
     * arrives just as soon, with ~180 ms less encoding stolen from the
     * playback, which is the whole reason this is off by default here. */
    if (asprintf(&psz_option, "stop-time=%.3f", seconds + 1.) != -1) {
        input_item_AddOption(p_item, psz_option, VLC_INPUT_OPTION_TRUSTED);
        free(psz_option);
    }
    if (asprintf(&psz_option, "sout=#transcode{vcodec=png,width=240,fps=1}:"
                 "std{access=file,mux=es,dst='%s'}",
                 [pngPath UTF8String]) != -1) {
        input_item_AddOption(p_item, psz_option, VLC_INPUT_OPTION_TRUSTED);
        free(psz_option);
    }
    /* ⚠ DÉCODAGE LOGICIEL IMPOSÉ pour cette entrée. Le décodeur matériel
     * rendait la vignette impossible de deux façons, mesurées :
     *  - Snow Leopard (Mac mini GMA950) : « VDADecoderCreate failed: -12470 »
     *    puis « cannot continue streaming due to errors with codec h264 » --
     *    le repli logiciel annoncé n'a pas lieu dans une chaîne de sortie, et
     *    aucune image n'est écrite ;
     *  - macOS moderne : VideoToolbox rend une surface OPAQUE, que l'encodeur
     *    png ne sait pas lire (« Failed to create video converter »).
     * Le coût est nul ici : une seule image est décodée, et le décodeur
     * matériel reste évidemment en service pour la LECTURE. */
    static const char *const options[] = {
        "no-audio", "no-spu", "no-osd", "no-video-title-show",
        "no-sout-audio", "no-sout-spu", "sout-video",
        "no-videotoolbox", "no-vda", "avcodec-hw=none",
    };
    size_t i;
    for (i = 0; i < sizeof(options)/sizeof(options[0]); i++)
        input_item_AddOption(p_item, options[i], VLC_INPUT_OPTION_TRUSTED);

    input_thread_t *p_input = input_Create(intf, p_item, "seek-thumb",
                                           NULL, NULL);
    NSImage *image = nil;
    if (p_input) {
        if (input_Start(p_input) == VLC_SUCCESS) {
            /* wait for the first frame or give up; decoding restarts at
             * the previous key frame, and on a busy slow machine (G3
             * decoding while playing) the whole chain can need ~10 s —
             * a shorter cap would abort just before the image lands */
            NSFileManager *fileManager = [NSFileManager defaultManager];
            const int maxIterations = 400; /* 400 * 50 ms = 20 s */
            int iteration;
            for (iteration = 0; iteration < maxIterations; iteration++) {
                input_state_e state = input_GetState(p_input);
                if (state == END_S || state == ERROR_S)
                    break;
                NSDictionary *attributes =
                    [fileManager fileAttributesAtPath:pngPath
                                         traverseLink:NO];
                if ([[attributes objectForKey:NSFileSize]
                        unsignedLongLongValue] > 0)
                    break;
                usleep(50000);
            }
            input_Stop(p_input);
        }
        input_Close(p_input);
    }
    input_item_Release(p_item);

    NSData *pngData = [NSData dataWithContentsOfFile:pngPath];
    if ([pngData length] > 0)
        image = [[[NSImage alloc]
                     initWithData:VLCFirstPNGFrame(pngData)] autorelease];
    return image;
}

@end
