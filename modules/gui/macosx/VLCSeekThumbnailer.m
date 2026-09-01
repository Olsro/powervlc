/*****************************************************************************
 * VLCSeekThumbnailer.m: seek bar hover thumbnails
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

#import "VLCSeekThumbnailer.h"
#import "VLCMain.h"

#import <vlc_common.h>
#import <vlc_input.h>
#import <vlc_input_item.h>
#import <vlc_playlist.h>
#import <vlc_url.h>

/* statfs() : reconnaître un volume optique (cf. VLCURIIsDiscLike) */
#include <sys/param.h>
#include <sys/mount.h>

@interface VLCSeekThumbnailer ()
{
    dispatch_queue_t _workQueue;
    NSCache *_cache;          /* "uri#second" -> NSImage */
    NSString *_sceneDirectory;
    /* only the latest request survives; older queued ones bail out */
    volatile int64_t _requestGeneration;
}
@end

/* ⚠ A disc, or a disc IMAGE, cannot be previewed: a second reader reopens at
 * the MENU and never at the instant asked for, and it costs a whole dvdnav or
 * libbluray open. The disc schemes (dvd://, bluray://…) are already turned
 * away by the "file://" test -- verified on a real DVD, no secondary input is
 * ever created. What still slipped through was the disc image opened as a
 * plain file, recognised here by its extension or by a copied disc tree. */
static BOOL VLCURIIsDiscLike(NSString *uri)
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
     * Le survol de la barre lançait un second lecteur sur le disque : lecteur
     * optique en surchauffe et image qui se fige. On reconnaît en plus
     * l'arborescence d'un disque (VIDEO_TS / BDMV, ce qui couvre une copie
     * sur disque dur) et le volume monté en UDF ou ISO 9660. */
    NSString *path = [[NSURL URLWithString:uri] path];
    if (path == nil)
        return NO;

    NSFileManager *fm = [NSFileManager defaultManager];
    BOOL isDir = NO;
    if ([fm fileExistsAtPath:path isDirectory:&isDir] && isDir
     && ([fm fileExistsAtPath:
              [path stringByAppendingPathComponent:@"VIDEO_TS"]]
      || [fm fileExistsAtPath:
              [path stringByAppendingPathComponent:@"BDMV"]]))
        return YES;

    struct statfs sfs;
    if (statfs([path fileSystemRepresentation], &sfs) == 0
     && (strcasecmp(sfs.f_fstypename, "udf") == 0
      || strcasecmp(sfs.f_fstypename, "cd9660") == 0))
        return YES;
    return NO;
}

@implementation VLCSeekThumbnailer

+ (VLCSeekThumbnailer *)sharedInstance
{
    static VLCSeekThumbnailer *sharedInstance = nil;
    static dispatch_once_t pred;
    dispatch_once(&pred, ^{
        sharedInstance = [VLCSeekThumbnailer new];
    });
    return sharedInstance;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _workQueue = dispatch_queue_create("org.powervlc.seekthumbnailer",
                                           DISPATCH_QUEUE_SERIAL);
        _cache = [[NSCache alloc] init];
        [_cache setCountLimit:60];
        _sceneDirectory = [NSTemporaryDirectory()
            stringByAppendingPathComponent:
                [NSString stringWithFormat:@"powervlc-seek-thumbs-%d", getpid()]];
        [[NSFileManager defaultManager] createDirectoryAtPath:_sceneDirectory
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:nil];
    }
    return self;
}

- (void)thumbnailAtFraction:(double)fraction
                 completion:(void (^)(NSImage *, double))completion
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return;

    /* opt-out for slow machines: the secondary decode competes with the
     * playback for CPU (measured ~3-4 s alone, ~9 s while playing on an
     * iBook G3); the time/chapter tooltip itself stays */
    if (!var_InheritBool(p_intf, "macosx-hover-thumbnails")) {
        completion(nil, fraction);
        return;
    }

    /* snapshot what we need from the current input on the caller thread */
    input_thread_t *p_input = pl_CurrentInput(p_intf);
    if (!p_input) {
        completion(nil, fraction);
        return;
    }
    input_item_t *p_item = input_GetItem(p_input);
    char *psz_uri = p_item ? input_item_GetURI(p_item) : NULL;
    vlc_tick_t duration = p_item ? input_item_GetDuration(p_item) : 0;
    vlc_object_release(p_input);

    /* local files only: a network stream would open a second connection */
    if (!psz_uri || duration <= 0 || strncasecmp(psz_uri, "file://", 7)) {
        free(psz_uri);
        completion(nil, fraction);
        return;
    }

    NSString *uri = [NSString stringWithUTF8String:psz_uri];
    free(psz_uri);
    if (uri && VLCURIIsDiscLike(uri)) {
        completion(nil, fraction);
        return;
    }

    double seconds = fraction * ((double)duration / CLOCK_FREQ);
    NSString *cacheKey = [NSString stringWithFormat:@"%@#%lld",
                          uri, (long long)llround(seconds)];
    NSImage *cached = [_cache objectForKey:cacheKey];
    if (cached) {
        completion(cached, fraction);
        return;
    }

    int64_t generation = ++_requestGeneration;

    dispatch_async(_workQueue, ^{
        /* a newer hover superseded this request while it was queued */
        NSImage *image = nil;
        if (generation == self->_requestGeneration)
            image = [self renderThumbnailForURI:uri atSeconds:seconds];
        if (image)
            [self->_cache setObject:image forKey:cacheKey];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(image, fraction);
        });
    });
}

/* Runs on the worker queue: silent secondary input whose sout re-encodes
 * the decoded frames with VLC's own png encoder into a temporary file
 * (the contribs' ffmpeg carries no encoder at all, and the video output
 * path never instantiates a vout for such a headless input). The input is
 * stopped by hand as soon as the first frame has been written, and bounded
 * by a stop-time in case that ever misses. */
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
    static const uint8_t p_signature[8] =
        { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
    const uint8_t *bytes = (const uint8_t *)[data bytes];
    NSUInteger len = [data length];

    if (bytes == NULL || len < sizeof(p_signature) + 12)
        return nil;

    for (NSUInteger start = 0; start + sizeof(p_signature) <= len; start++) {
        if (memcmp(bytes + start, p_signature, sizeof(p_signature)) != 0)
            continue;
        for (NSUInteger i = start + sizeof(p_signature); i + 8 <= len; i++)
            if (memcmp(bytes + i, "IEND", 4) == 0)
                return [data subdataWithRange:
                            NSMakeRange(start, i + 8 - start)];
        break;      /* une image entamée mais jamais refermée */
    }
    return nil;
}

/* MVC thumbnails contain the two full-resolution eyes stacked vertically.
 * The decoder always places the left eye first (including right-base MVC),
 * so keep the upper half and restore the normal 16:9 preview geometry. The
 * tight aspect check avoids touching ordinary portrait videos. */
static NSImage *VLCLeftEyeThumbnail(NSImage *image)
{
    NSSize size = image.size;
    if (size.width <= 0. || size.height <= 0. ||
        fabs(size.height / size.width - 9. / 8.) > .02)
        return image;

    NSSize eyeSize = NSMakeSize(size.width, floor(size.height / 2.));
    NSImage *leftEye = [[NSImage alloc] initWithSize:eyeSize];
    [leftEye lockFocus];
    [image drawInRect:NSMakeRect(0., 0., eyeSize.width, eyeSize.height)
             fromRect:NSMakeRect(0., size.height - eyeSize.height,
                                 size.width, eyeSize.height)
            operation:NSCompositingOperationCopy
             fraction:1.];
    [leftEye unlockFocus];
    return leftEye;
}

- (NSImage *)renderThumbnailForURI:(NSString *)uri atSeconds:(double)seconds
{
    intf_thread_t *p_intf = getIntf();
    if (!p_intf)
        return nil;

    NSString *pngPath =
        [_sceneDirectory stringByAppendingPathComponent:@"hover.png"];
    [[NSFileManager defaultManager] removeItemAtPath:pngPath error:nil];

    input_item_t *p_item = input_item_New([uri UTF8String], "seek-thumbnail");
    if (!p_item)
        return nil;

    char *psz_option;
    if (asprintf(&psz_option, "start-time=%.3f", seconds) != -1) {
        input_item_AddOption(p_item, psz_option, VLC_INPUT_OPTION_TRUSTED);
        free(psz_option);
    }
    /* Bound what the encoder is allowed to write. The input is meant to be
     * stopped by hand on the first frame, but nothing here guarantees the
     * poll below notices in time -- the Qt port of this thumbnailer slept a
     * thousand times too long on that very loop and quietly transcoded whole
     * films. A two second window always holds a frame, and one frame per
     * second of media caps it at a couple of pictures. Measured, from the
     * first written byte to the input stopping: on an iBook G3 (Jaguar,
     * 480p) 277 kB and 5512 ms without, 120 kB and 5333 ms with, i.e. the
     * same time to the image and ~180 ms less encoding taken out of the
     * playback; on an arm64 Mac (1080p) 1.3 MB against 70 kB. */
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
    /* ⚠ Software decoding forced for this input: VideoToolbox hands back an
     * OPAQUE surface the png encoder cannot read ("Failed to create video
     * converter"), and on 10.6 VDA fails outright inside a stream output
     * ("VDADecoderCreate failed: -12470" then "cannot continue streaming due
     * to errors with codec h264") -- measured in the legacy interface, same
     * pipeline. One frame is decoded here; playback keeps the hardware. */
    static const char *const options[] = {
        "no-audio", "no-spu", "no-osd", "no-video-title-show",
        "no-sout-audio", "no-sout-spu", "sout-video",
        "no-videotoolbox", "no-vda", "avcodec-hw=none",
    };
    for (size_t i = 0; i < sizeof(options)/sizeof(options[0]); i++)
        input_item_AddOption(p_item, options[i], VLC_INPUT_OPTION_TRUSTED);

    input_thread_t *p_input = input_Create(p_intf, p_item, "seek-thumb",
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
            for (int i = 0; i < maxIterations; i++) {
                input_state_e state = input_GetState(p_input);
                if (state == END_S || state == ERROR_S)
                    break;
                NSDictionary *attributes =
                    [fileManager attributesOfItemAtPath:pngPath error:nil];
                if ([attributes fileSize] > 0)
                    break;
                usleep(50000);
            }
            input_Stop(p_input);
        }
        input_Close(p_input);
    }
    input_item_Release(p_item);

    NSData *pngData = [NSData dataWithContentsOfFile:pngPath];
    if ([pngData length] > 0) {
        NSImage *decoded = [[NSImage alloc]
            initWithData:VLCFirstPNGFrame(pngData)];
        image = VLCLeftEyeThumbnail(decoded);
    }
    return image;
}

@end
