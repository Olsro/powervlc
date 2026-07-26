/*****************************************************************************
 * appleva_backend.c : décodage MPEG-2 accéléré matériel via AppleVA
 *****************************************************************************
 * Voir appleva_backend.h et doc/appleva-mpeg2-hwaccel-spec.md.
 *
 * STRATÉGIE (confirmée par reverse, spec §2) : on pilote la vtable du
 * renderer GPU d'AppleVA PAR OFFSET (ABI uniforme Intel/ATI/nVidia), et NON
 * via le chemin QT (AVAFQT*) qui est le décodage HOST/CPU. Le renderer
 * s'obtient par AVAFGetGPURenderer (le GATE, validé sur GMA950).
 *
 * ÉTAT :
 *   - appleva_available() : GATE VALIDÉ sur matériel (va_detect).
 *   - appleva_open() : gate + renderer VALIDÉS ; CreateContext (@vtable 0x10)
 *     codé d'après le reverse (§2), à valider sur matériel. Échoue proprement
 *     (NULL → l'appelant retombe sur libmpeg2 CPU).
 *   - appleva_decode_picture() : le feed IDCTMCP (@vtable 0x34) reste à
 *     finaliser (picture_params + readback surface). Cf. §3/§5 de la spec.
 *****************************************************************************/
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <ApplicationServices/ApplicationServices.h>

#include "appleva_backend.h"

#define AVA_PATH \
    "/System/Library/PrivateFrameworks/AppleVA.framework/Versions/A/AppleVA"

/*
 * Offsets de la vtable du renderer GPU (l'objet renderer EST sa vtable :
 * fonctions inline à obj[off]). ABI uniforme d'AppleVA — cf. spec §4bis,
 * reversée sur le bundle GMA950 (AVACreateRenderer @0xbf0) et prouvée
 * portable par les appels `*0xNN(renderer)` d'AppleVA elle-même.
 */
enum {
    VT_CREATE_CONTEXT          = 0x10, /* (renderer, void **out_ctx, image_info*) */
    VT_DESTROY_CONTEXT         = 0x14, /* (ctx) */
    VT_IS_JOB_COMPLETE         = 0x18,
    VT_WAIT_FOR_JOB            = 0x1c,
    VT_GET_PARAM               = 0x28,
    VT_SET_PARAM               = 0x2c, /* (ctx, u32 feature, void*) — feat 0x2e=fmt pixel */
    VT_IDCTMCP                 = 0x34, /* (ctx, picture_params*) = LE DÉCODAGE */
    VT_SET_SOURCE_IMAGE_SIZE   = 0x3c, /* (ctx, {u32 w,h}*, arg2) */
    VT_SET_TARGET_IMAGE_SIZE   = 0x40, /* NO-OP sur GMA950 */
    VT_GET_TARGET_IMAGE_INFO   = 0x48, /* NO-OP sur GMA950 (surfaces gérées en interne) */
    VT_SWAP_TO_EXTERNAL_TARGET = 0x54, /* (ctx, u8 index) = submit GPU + rotation surface */
    VT_DESTROY_RENDERER        = 0x58, /* (renderer) */
};

/* Récupère le pointeur de fonction inline à l'offset off de l'objet renderer. */
#define AVA_VFN(obj, off) (*(void **)((char *)(obj) + (off)))

typedef int (*ava_init_library_fn)(void *);
typedef int (*ava_get_gpu_renderer_fn)(CGDirectDisplayID, void **);
typedef int (*ava_create_context_fn)(void *renderer, void **out_ctx, void *image_info);
typedef int (*ava_destroy_context_fn)(void *ctx);
typedef int (*ava_destroy_renderer_fn)(void *renderer);
typedef int (*ava_idctmcp_fn)(void *ctx, void *picture_params);

/* Taille d'un descriptor macrobloc (spec §3). */
#define AVA_MB_DESC_SIZE 0x1c   /* 28 o */

/*
 * image_info passé à CreateContext (spec §2, reversé + VALIDÉ sur GMA950).
 * ⚠️ [0xc/0x10/0x14] = identifiants d'une surface WindowServer (CGS) : CreateContext
 * appelle CGSBindSurface(cid, wid, sid, …) → le décodeur écrit DIRECTEMENT dans cette
 * surface d'affichage. Sans surface valide → kIOReturnInternalError (0xe00002c9).
 * Ces IDs doivent venir de la fenêtre du vout (macosx_gl1) — cf. spec §4.
 */
struct ava_image_info {
    uint32_t num_ref;
    uint32_t num_out;
    uint32_t display_id;      /* CGDirectDisplayID */
    uint32_t cgs_connection;  /* CGSConnectionID  — de la fenêtre du vout */
    uint32_t cgs_window;      /* CGSWindowID      — idem */
    uint32_t cgs_surface;     /* CGSSurfaceID     — idem */
};

struct appleva_ctx
{
    void *dl;                        /* handle dlopen(AppleVA) */
    void *renderer;                  /* renderer GPU (AVAFCreateRenderer) */
    void *decoder_ctx;               /* contexte CreateContext (vtable 0x10) */
    unsigned width, height;

    /* Accumulateur de picture (construit picture_params pour IDCTMCP, spec §3). */
    uint8_t *descriptors;            /* nb_mbs * 28 o */
    uint8_t *cbp;                    /* nb_mbs o (1 CBP/MB) */
    uint8_t *coeffs;                 /* flux run-level 4 o/coeff */
    unsigned nb_mbs;                 /* macroblocs attendus */
    unsigned mb_index;               /* macrobloc courant */
    unsigned coeffs_len;             /* octets écrits dans coeffs */
    unsigned coeffs_cap;             /* capacité de coeffs */
    int coding_type;                 /* 1=I 2=P 3=B */
    int alt_scan;                    /* pp[0x04] */
    int pic_structure;               /* pp[0x02] (0=frame) */
    /* état du macrobloc en cours (API streaming par bloc) */
    uint8_t  cur_cbp;                /* CBP (convention GPU 0x20..0x01) du MB courant */
    unsigned cur_block;              /* prochain index de bloc 0..5 à assigner */
};

/* Ouvre AppleVA et résout les symboles communs. */
static void *ava_dlopen(ava_init_library_fn *init, ava_get_gpu_renderer_fn *gpu)
{
    void *dl = dlopen(AVA_PATH, RTLD_NOW | RTLD_LOCAL);
    if (dl == NULL)
        return NULL;
    *init = (ava_init_library_fn)     dlsym(dl, "AVAFQTInitLibrary");
    *gpu  = (ava_get_gpu_renderer_fn) dlsym(dl, "AVAFGetGPURenderer");
    if (*init == NULL || *gpu == NULL) {
        dlclose(dl);
        return NULL;
    }
    return dl;
}

/* AVAFCreateRenderer(descriptor, &out_renderer, extra) : construit l'objet
 * renderer APPELABLE (magic 0x10800000, vtable) à partir du descripteur. */
typedef int (*ava_create_renderer_fn)(void *descriptor, void **out, void *extra);

/* Charge AppleVA et renvoie le renderer GPU APPELABLE de l'écran principal (ou NULL).
 * ⚠️ AVAFGetGPURenderer renvoie un DESCRIPTEUR (nœud de liste), PAS l'objet
 * appelable ; c'est AVAFCreateRenderer qui construit le renderer (validé GMA950). */
static void *ava_get_renderer(void *dl)
{
    ava_init_library_fn    init = (ava_init_library_fn)     dlsym(dl, "AVAFQTInitLibrary");
    ava_get_gpu_renderer_fn gpu = (ava_get_gpu_renderer_fn) dlsym(dl, "AVAFGetGPURenderer");
    ava_create_renderer_fn  crt = (ava_create_renderer_fn)  dlsym(dl, "AVAFCreateRenderer");
    if (init == NULL || gpu == NULL || crt == NULL || init(NULL) != 0)
        return NULL;
    void *descriptor = NULL;
    if (gpu(CGMainDisplayID(), &descriptor) != 0 || descriptor == NULL)
        return NULL;                 /* pas de GPU MPEG-2 */
    void *renderer = NULL;
    if (crt(descriptor, &renderer, NULL) != 0 || renderer == NULL)
        return NULL;
    return renderer;                 /* objet appelable (vtable à obj[0x10..]) */
}

/* ==== GATE : VALIDÉ sur matériel (va_detect) ============================= */
bool appleva_available(void)
{
    ava_init_library_fn    init;
    ava_get_gpu_renderer_fn gpu;
    void *dl = ava_dlopen(&init, &gpu);
    if (dl == NULL)
        return false;

    bool ok = false;
    if (init(NULL) == 0) {              /* charge les renderers (LoadAllRenderers) */
        void *r = NULL;
        if (gpu(CGMainDisplayID(), &r) == 0 && r != NULL)
            ok = true;                  /* un renderer GPU MPEG-2 existe */
    }
    dlclose(dl);
    return ok;
}

/* SetSourceImageSize(ctx, src_desc, workbuf) : src_desc[0] = &{u32 w, u32 h}
 * (déréférencé) ; workbuf = tampon de travail (ctx[0x28]=workbuf+4). VALIDÉ GMA950. */
typedef int (*ava_set_src_size_fn)(void *ctx, void *src_desc, void *workbuf);

/* ==== OUVERTURE ==========================================================
 * width×height + les IDs de la surface WindowServer (CGS) fournie par l'appelant
 * (le vout) : CreateContext lie la sortie du décodeur à cette surface (spec §2).
 * VALIDÉ end-to-end sur GMA950 (harnais va_surf.c). Renvoie NULL → fallback CPU. */
appleva_ctx *appleva_open(unsigned width, unsigned height,
                          uint32_t cgs_connection, uint32_t cgs_window,
                          uint32_t cgs_surface)
{
    void *dl = dlopen(AVA_PATH, RTLD_NOW | RTLD_LOCAL);
    if (dl == NULL)
        return NULL;

    void *renderer = ava_get_renderer(dl);
    if (renderer == NULL)
        goto error;                     /* pas de GPU -> l'appelant fera le fallback */

    /* CreateContext(renderer, &decoder_ctx, image_info) via la vtable (0x10) :
     * alloue le contexte GPU (0x28dc o) et lie la sortie à la surface CGS
     * (CGSBindSurface). Sans surface valide → kIOReturnInternalError. */
    ava_create_context_fn CreateContext =
        (ava_create_context_fn) AVA_VFN(renderer, VT_CREATE_CONTEXT);

    struct ava_image_info info;
    memset(&info, 0, sizeof(info));
    info.num_ref        = 2;
    info.num_out        = 4;
    info.display_id     = (uint32_t) CGMainDisplayID();
    info.cgs_connection = cgs_connection;
    info.cgs_window     = cgs_window;
    info.cgs_surface    = cgs_surface;

    void *decoder_ctx = NULL;
    if (CreateContext(renderer, &decoder_ctx, &info) != 0 || decoder_ctx == NULL)
        goto error;                     /* init GPU KO -> fallback CPU */

    /* SetSourceImageSize(0x3c) : pose les dimensions (ctx[0x30]/[0x34]) + la
     * surface cible interne (ctx[0x21d4]). src_desc[0] pointe sur {w,h}. */
    ava_set_src_size_fn SetSourceImageSize =
        (ava_set_src_size_fn) AVA_VFN(renderer, VT_SET_SOURCE_IMAGE_SIZE);
    uint32_t dims[2] = { width, height };
    void *src_desc[16] = { dims, 0 };
    static uint8_t workbuf[4096];        /* tampon de travail interne (ctx[0x28]) */
    SetSourceImageSize(decoder_ctx, src_desc, workbuf);

    /* SetParam (vtable 0x2c) : handlers = simples affectations (reversés @0x13b5/
     * 0x135b) : 0x2e → ctx[0x20]=format, 0x29 → ctx[0x2060]=mode. On ne touche PAS
     * au format (défaut 'yuvs' de la GMA950 ; forcer '2vuy' fige IDCTMCP). On pose
     * seulement le mode 0x29=2 (ce que fait AVAFQTDecodePicture avant de décoder). */
    {
        typedef int (*set_param_fn)(void *ctx, uint32_t feature, void *value);
        set_param_fn SetParam = (set_param_fn) AVA_VFN(renderer, VT_SET_PARAM);
        uint32_t v29 = 2;
        SetParam(decoder_ctx, 0x29, &v29);
    }

    appleva_ctx *ctx = calloc(1, sizeof(*ctx));
    if (ctx == NULL) {
        ava_destroy_context_fn DestroyContext =
            (ava_destroy_context_fn) AVA_VFN(renderer, VT_DESTROY_CONTEXT);
        DestroyContext(decoder_ctx);
        goto error;
    }
    ctx->dl          = dl;
    ctx->renderer    = renderer;
    ctx->decoder_ctx = decoder_ctx;
    ctx->width       = width;
    ctx->height      = height;
    return ctx;

error:
    dlclose(dl);
    return NULL;
}

/* ==== RÉ-ENCODEUR COEFFICIENTS (DCTblock libmpeg2 → run-level GPU) ========
 *
 * Convertit un bloc 8×8 déquantifié de libmpeg2 (decoder->DCTblock, ordre de
 * stockage imposé par decoder->scan, éventuellement permuté pour l'IDCT SSE2)
 * au format attendu par IntelVARendererIDCTMCP : suite de coeffs 4 o
 * {u8 run, u8 pad, i16 level} en ordre ZIGZAG (le driver dé-zigzague avec sa
 * propre table : pos+=run ; block[scan_gpu[pos]]=level ; pos++).
 *
 * `scan` = decoder->scan de libmpeg2 : scan[zz] donne l'index de stockage du
 * coeff à la position zigzag zz, donc DCTblock[scan[zz]] = coeff zigzag zz,
 * quelle que soit la permutation. `out` doit tenir 64*4 o. Retourne nb coeffs.
 *
 * NB : pas de re-quantification (libmpeg2 a déjà déquantifié ; idct_sse2_cbp du
 * driver ne reçoit aucune matrice → il attend du déquantifié). Cf. spec §4.
 */
unsigned appleva_encode_block(const int16_t *dctblock, const uint8_t *scan,
                              uint8_t *out)
{
    int last = -1;
    unsigned n = 0;
    for (int zz = 0; zz < 64; zz++) {
        int16_t v = dctblock[scan[zz]];
        if (v != 0) {
            out[0] = (uint8_t)(zz - last - 1);   /* run (écart zigzag) */
            out[1] = 0;                           /* pad */
            out[2] = (uint8_t)((uint16_t)v & 0xff);       /* level bas */
            out[3] = (uint8_t)(((uint16_t)v >> 8) & 0xff);/* level haut (i16 LE) */
            out += 4;
            n++;
            last = zz;
        }
    }
    return n;
}

/* ==== ASSEMBLAGE + SOUMISSION D'UNE PICTURE ==============================
 *
 * API streaming alignée sur la boucle de slice.c (par macrobloc, par bloc) :
 *   appleva_picture_begin() → appleva_picture_add_mb() × nb_mbs → _submit().
 * Construit les 3 flux de picture_params (descriptors 28 o, coeffs 4 o,
 * CBP 1 o/MB — spec §3) puis appelle IDCTMCP (vtable 0x34). */

/* (Ré)alloue les buffers pour une picture de nb_mbs macroblocs. */
int appleva_picture_begin(appleva_ctx *ctx, int coding_type, int alt_scan,
                          int pic_structure, unsigned nb_mbs)
{
    /* pire cas coeffs : 6 blocs × 64 coeffs × 4 o par macrobloc */
    unsigned coeffs_cap = nb_mbs * 6u * 64u * 4u;
    if (nb_mbs != ctx->nb_mbs) {
        uint8_t *d = realloc(ctx->descriptors, nb_mbs * AVA_MB_DESC_SIZE);
        uint8_t *c = realloc(ctx->cbp, nb_mbs);
        if (d == NULL || c == NULL) {
            free(d); free(c);
            ctx->descriptors = NULL; ctx->cbp = NULL; ctx->nb_mbs = 0;
            return -1;
        }
        ctx->descriptors = d;
        ctx->cbp = c;
        ctx->nb_mbs = nb_mbs;
    }
    if (coeffs_cap > ctx->coeffs_cap) {
        uint8_t *co = realloc(ctx->coeffs, coeffs_cap);
        if (co == NULL)
            return -1;
        ctx->coeffs = co;
        ctx->coeffs_cap = coeffs_cap;
    }
    memset(ctx->descriptors, 0, nb_mbs * AVA_MB_DESC_SIZE);
    memset(ctx->cbp, 0, nb_mbs);
    ctx->mb_index = 0;
    ctx->coeffs_len = 0;
    ctx->coding_type = coding_type;
    ctx->alt_scan = alt_scan;
    ctx->pic_structure = pic_structure;
    return 0;
}

/* ---- API streaming par bloc (alignée sur slice.c : begin → block × N → end) ----
 *
 * cbp est en convention GPU (bits 0x20..0x01 = Y0 Y1 Y2 Y3 U V). Attention :
 * libmpeg2 utilise la convention INVERSE (bit 1<<b = bloc b) → l'appelant doit
 * inverser les 6 bits avant (cf. appleva_cbp_from_libmpeg2). Les blocs codés
 * arrivent dans l'ordre croissant (Y0..V) donc on marche le CBP sans index. */

/* Débute un macrobloc : pose type + CBP, arme le walker de blocs. */
void appleva_picture_mb_begin(appleva_ctx *ctx, int type_index, uint8_t cbp)
{
    if (ctx->mb_index >= ctx->nb_mbs)
        return;
    uint8_t *desc = ctx->descriptors + ctx->mb_index * AVA_MB_DESC_SIZE;
    desc[0x14] = (uint8_t) type_index;
    ctx->cbp[ctx->mb_index] = cbp;
    ctx->cur_cbp = cbp;
    ctx->cur_block = 0;
}

/* Ajoute le prochain bloc CODÉ du macrobloc courant (DCTblock déquantifié). */
void appleva_picture_mb_block(appleva_ctx *ctx, const int16_t *dctblock,
                              const uint8_t *scan)
{
    if (ctx->mb_index >= ctx->nb_mbs)
        return;
    /* avance jusqu'au prochain bloc dont le bit CBP est mis */
    while (ctx->cur_block < 6 && !(ctx->cur_cbp & (0x20 >> ctx->cur_block)))
        ctx->cur_block++;
    if (ctx->cur_block >= 6)
        return;                         /* plus de bloc codé (ne devrait pas arriver) */
    uint8_t *desc = ctx->descriptors + ctx->mb_index * AVA_MB_DESC_SIZE;
    unsigned n = appleva_encode_block(dctblock, scan,
                                      ctx->coeffs + ctx->coeffs_len);
    desc[0x16 + ctx->cur_block] = (uint8_t) n;
    ctx->coeffs_len += n * 4u;
    ctx->cur_block++;
}

/* Termine le macrobloc courant (passe au suivant). */
void appleva_picture_mb_end(appleva_ctx *ctx)
{
    if (ctx->mb_index < ctx->nb_mbs)
        ctx->mb_index++;
}

/* Convertit un CBP libmpeg2 (bit 1<<b = bloc b) en CBP GPU (bit 0x20>>b = bloc b). */
uint8_t appleva_cbp_from_libmpeg2(unsigned mpeg2_cbp)
{
    uint8_t g = 0;
    for (int b = 0; b < 6; b++)
        if (mpeg2_cbp & (1u << b))
            g |= (uint8_t)(0x20 >> b);
    return g;
}

/* Ajoute un macrobloc complet (helper : begin + 6 blocs + end). blocks[b]=NULL
 * si non codé. cbp en convention GPU. Utilisé par les harnais de test. */
void appleva_picture_add_mb(appleva_ctx *ctx, int type_index, uint8_t cbp,
                            const int16_t *const blocks[6], const uint8_t *scan)
{
    appleva_picture_mb_begin(ctx, type_index, cbp);
    for (int b = 0; b < 6; b++)
        if ((cbp & (0x20 >> b)) && blocks[b] != NULL)
            appleva_picture_mb_block(ctx, blocks[b], scan);
    appleva_picture_mb_end(ctx);
}

/* Soumet la picture assemblée au GPU (IDCTMCP). Retourne 0 si succès. */
int appleva_picture_submit(appleva_ctx *ctx)
{
    if (ctx->renderer == NULL || ctx->decoder_ctx == NULL)
        return -1;

    uint8_t pp[64];
    memset(pp, 0, sizeof(pp));
    pp[0x02] = (uint8_t) ctx->pic_structure;   /* frame/field */
    pp[0x04] = (uint8_t) ctx->alt_scan;        /* table de scan */
    pp[0x06] = 0;                               /* index surface cible */
    *(void **)(pp + 0x0c) = ctx->descriptors;
    *(void **)(pp + 0x10) = ctx->coeffs;
    *(void **)(pp + 0x14) = ctx->cbp;

    ava_idctmcp_fn IDCTMCP =
        (ava_idctmcp_fn) AVA_VFN(ctx->renderer, VT_IDCTMCP);
    return IDCTMCP(ctx->decoder_ctx, pp);
}

/* Présente la surface décodée (SwapToExternalTargetImage @vtable 0x54).
 * Signature RÉVERSÉE depuis AVAFQTDrawPicture (@0x56f0) : 4 args
 *   (ctx, u8 index, image_info *arg3, u32 arg4)
 * arg3 (struct ≥0x24 o) : [0]=largeur, [4]=hauteur, [8]/[0xc]/[0x18]/[0x20] =
 * champs du descripteur picture (mis à 0 ici — sémantique à finir). arg4 = picture[0x14].
 * ⚠️ arg3/arg4 mal formés peuvent figer le GPU → tester avec watchdog court. */
typedef int (*ava_swap_fn)(void *ctx, unsigned char index, void *info, uint32_t arg4);
void appleva_present(appleva_ctx *ctx, unsigned index)
{
    if (ctx == NULL || ctx->renderer == NULL || ctx->decoder_ctx == NULL)
        return;
    ava_swap_fn Swap =
        (ava_swap_fn) AVA_VFN(ctx->renderer, VT_SWAP_TO_EXTERNAL_TARGET);
    uint8_t info[0x28];
    memset(info, 0, sizeof(info));
    *(uint32_t *)(info + 0x00) = ctx->width;
    *(uint32_t *)(info + 0x04) = ctx->height;
    Swap(ctx->decoder_ctx, (unsigned char) index, info, 0);
}

/* DEBUG : expose la région mappée par SwapToExternalTargetImage (ctx[0x21c4]
 * = base de l'aperture GPU, ctx[0x21c0] = taille). La surface '2vuy' est DEDANS
 * à un offset donné par les tables ctx[0x21d4+idx]/ctx[0x2364+idx]. */
void appleva_debug_mapped(appleva_ctx *ctx, void **addr, uint32_t *size)
{
    *addr = NULL; *size = 0;
    if (ctx == NULL || ctx->decoder_ctx == NULL)
        return;
    char *c = (char *) ctx->decoder_ctx;
    *addr = *(void **)(c + 0x21c4);
    *size = *(uint32_t *)(c + 0x21c0);
}

/* DEBUG : lit un dword du contexte GPU à l'offset donné (pour trouver l'offset
 * de la surface '2vuy' dans l'aperture). */
uint32_t appleva_debug_ctx_u32(appleva_ctx *ctx, unsigned off)
{
    if (ctx == NULL || ctx->decoder_ctx == NULL)
        return 0;
    return *(uint32_t *)((char *) ctx->decoder_ctx + off);
}

/* ==== FERMETURE ========================================================== */
void appleva_close(appleva_ctx *ctx)
{
    if (ctx == NULL)
        return;
    free(ctx->descriptors);
    free(ctx->cbp);
    free(ctx->coeffs);
    if (ctx->renderer != NULL) {
        if (ctx->decoder_ctx != NULL) {
            ava_destroy_context_fn DestroyContext =
                (ava_destroy_context_fn) AVA_VFN(ctx->renderer, VT_DESTROY_CONTEXT);
            DestroyContext(ctx->decoder_ctx);
        }
        ava_destroy_renderer_fn DestroyRenderer =
            (ava_destroy_renderer_fn) AVA_VFN(ctx->renderer, VT_DESTROY_RENDERER);
        DestroyRenderer(ctx->renderer);
    }
    if (ctx->dl != NULL)
        dlclose(ctx->dl);
    free(ctx);
}
