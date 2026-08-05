/*****************************************************************************
 * dvddriver_backend.h : décodage MPEG-2 accéléré matériel via l'ABI DVDDriver*
 *                       (ATI Radeon des vieux Mac PPC — iBook/PowerBook G3/G4)
 *****************************************************************************
 * Chemin RÉEL du décodage DVD matériel sur PPC ATI (ce que le lecteur DVD
 * d'Apple utilise vraiment) : le CPU fait le VLD (via libmpeg2), le GPU ATI
 * fait iDCT + motion-compensation via le bundle ATIRadeonDVDDriver
 * (`DVDDriverOpenDevice` / `DVDDriverDecode` / `DVDDriverShowMPBuffer`).
 *
 * VALIDÉ sur iBook G3 (harnais ati_open.c/ati_decode.c) : ouverture du
 * décodeur + soumission d'une frame de macroblocs → rc=0, ATIR6DVDContext
 * instancié, pas de crash. Voir doc/appleva-mpeg2-hwaccel-spec.md §6.
 *
 * Contrairement à appleva_backend.c (qui vise IntelVARendererIDCTMCP, chemin
 * NON utilisé par DVD Player), ce backend vise l'ABI DVDDriver* qui EST le
 * décodage HW effectif sur ATI PPC.
 *****************************************************************************/
#ifndef VLC_DVDDRIVER_BACKEND_H
#define VLC_DVDDRIVER_BACKEND_H

#include <stdint.h>
#include <stdbool.h>

/* Contexte opaque du backend. */
typedef struct dvddriver_ctx dvddriver_ctx;

/*
 * Renvoie true si le décodage DVD matériel ATI est disponible : le bundle
 * /System/Library/Extensions/ATIRadeonDVDDriver.bundle se charge ET un service
 * IOKit "ATIRadeon" existe. N'ouvre pas le décodeur.
 */
bool dvddriver_available(void);
/* Nom du greffon de carte retenu (découverte IODVDBundleName), NULL si aucun. */
const char *dvddriver_family_name(void);

/*
 * Ouvre le décodeur HW pour un flux width×height. Crée une surface WindowServer
 * (CGS) offscreen à laquelle la sortie du décodeur est liée (CGSBindSurface),
 * récupère le service ATIRadeon, appelle DVDInitializeLibrary + DVDDriverOpenDevice.
 * Renvoie NULL si indisponible (l'appelant retombe alors sur libmpeg2 CPU).
 */
/* display_mode : 0 = petite fenêtre HW native 1:1 (additif, A/B avec le vout
 * logiciel) ; 1 = fenêtre HW plein écran, surface mise à l'échelle (letterbox) →
 * la fenêtre HW DEVIENT l'affichage vidéo (mode remplacement M4).
 * external_wid : U2 (expérience-GATE, A-idéal) — si > 0, ne pas créer de fenêtre
 * Carbon, lier la surface décodeur à CETTE fenêtre (numéro CGS de la fenêtre VLC
 * publié par le vout en U1). 0 = comportement connu (fenêtre Carbon séparée).
 * field_exp : mode de déblocage du décodage HW des MB field-predicted (option
 * mpeg2-hwaccel-field). 0 = field non soumis → repli CPU (défaut sûr) ; 1 = brut ;
 * 2 = clamp MV vertical field. En display_mode, 0 est auto-promu à 2 (sinon une
 * picture field serait perdue des deux côtés). Remplace l'ancien /tmp/field_exp.
 * subs_overlay : chantier S — sous-titres/OSD superposés à la vidéo matérielle.
 * N'a de sens qu'avec external_wid > 0 (l'incrustation est faite par le vout,
 * qui ne couvre pas la fenêtre Carbon séparée). Le décodeur passe ici la MÊME
 * valeur qu'il publie sur DVDDRIVER_VAR_SUBS (source de vérité unique) ;
 * remplace l'ancien gate fichier /tmp/hw_subs. L'ORDRE de la surface, lui, ne
 * change pas : deux surfaces CGS d'une même fenêtre ne se mélangent pas
 * (mesuré G3/RV200), l'incrustation passe par une fenêtre distincte.
 */
dvddriver_ctx *dvddriver_open(unsigned width, unsigned height, int display_mode,
                              int external_wid, int field_exp, bool subs_overlay);

/*
 * Assemblage + soumission d'une picture (API streaming alignée sur slice.c) :
 *   dvddriver_picture_begin(ctx, coding_type, pic_structure, nb_mbs)
 *   [ mb_begin(ctx, mb_type, dct_type, cbp) ; mb_block(ctx, dctblock, scan)×N ; mb_end(ctx) ] × nb_mbs
 *   dvddriver_picture_submit(ctx)   → DVDDriverDecode
 *   dvddriver_present(ctx)          → DVDDriverShowMPBuffer (optionnel)
 *
 *   coding_type   : 1=I 2=P 3=B (seul I géré pour l'instant)
 *   pic_structure : 3=frame (1/2=field, à venir)
 *   mb_type       : mb_desc[0x14] (0=intra ; 1..7 inter/field, à venir)
 *   cbp           : convention GPU (bit 0x20>>b = bloc b) — sert au walker de blocs.
 *                   Utiliser dvddriver_cbp_from_libmpeg2() pour convertir.
 */
int  dvddriver_picture_begin(dvddriver_ctx *ctx, int coding_type,
                             int pic_structure, unsigned nb_mbs);
/* mb_type : 0=intra 1=fwd 2=bwd 3=bidir 4=skip 5/6/7=field. dct_type : 0/1.
 * mv : 8× i16 {fwd0.xy, bwd0.xy, fwd1.xy, bwd1.xy} demi-pel (0 en intra/skip).
 * field_select : 4× u8 (0 en MC_FRAME). */
void dvddriver_picture_mb_begin(dvddriver_ctx *ctx, int mb_type, int dct_type,
                                uint8_t cbp, const int16_t *mv,
                                const uint8_t *field_select);
void dvddriver_picture_mb_block(dvddriver_ctx *ctx, const int16_t *dctblock,
                                const uint8_t *scan);
void dvddriver_picture_mb_block_rl(dvddriver_ctx *ctx, const int16_t (*rl)[2],
                                   int n);
void dvddriver_picture_mb_end(dvddriver_ctx *ctx);
int  dvddriver_picture_submit(dvddriver_ctx *ctx);
/* Soumission asynchrone : Decode sur un worker dédié, recouvert par la VLD de
 * la picture suivante (profondeur 1). take_failure renvoie le coding_type d'un
 * Decode échoué depuis la dernière interrogation (0 sinon) — l'équivalent
 * différé du rc≠0 synchrone. */
void dvddriver_set_async(dvddriver_ctx *ctx, bool on);
int  dvddriver_async_take_failure(dvddriver_ctx *ctx);
void dvddriver_present(dvddriver_ctx *ctx);

/* M3 (sync/réordonnancement) : découple la présentation (ordre d'AFFICHAGE) de la
 * soumission (ordre de DÉCODAGE). Après un submit rc=0, l'appelant lit l'index de
 * surface de sortie (dvddriver_out_index) et l'associe à la picture_t* décodée ;
 * au moment d'afficher display_fbuf, il présente la surface par index. */
int  dvddriver_out_index(const dvddriver_ctx *ctx);
void dvddriver_present_index(dvddriver_ctx *ctx, int idx);

/* U4 — present piloté par le vout (thread vout, ordre PTS → synchro A/V).
 *  - dvddriver_surf_generation(ctx, idx) : génération courante de la surface idx.
 *    Le codec la capture au submit et l'attache à la picture_t (contexte).
 *  - dvddriver_present_index_gen(ctx, idx, gen) : présente idx SEULEMENT si sa
 *    génération vaut encore gen (sinon surface réécrite → saute, garde l'image).
 *  - dvddriver_set_present_rect(ctx, x,y,w,h) : rect de present en coords
 *    FENÊTRE-locales (le vout le met à jour pour suivre la géométrie vidéo U1).
 * Tous thread-safe (mutex interne partagé avec Decode/Show/Close). */
unsigned dvddriver_surf_generation(dvddriver_ctx *ctx, int idx);

/* ★ Réservation d'une surface pour le compte d'une picture VLC. Le GPU n'a que
 * 5 surfaces alors que VLC prend une dizaine de pictures d'avance : sans
 * réservation, chaque surface est réécrite avant d'être affichée et le present
 * est systématiquement rejeté (génération périmée). hold au moment où le
 * décodeur attache le contexte à la picture, release quand VLC détruit ce
 * contexte (picture affichée OU droppée). Le décodeur ATTEND une surface libre
 * → il est cadencé sur l'affichage au lieu de courir devant. */
void dvddriver_surface_hold(dvddriver_ctx *ctx, int idx);
void dvddriver_surface_release(dvddriver_ctx *ctx, int idx);

/* ★ Ré-attache la surface décodeur à une AUTRE fenêtre CGS. Nécessaire au passage
 * en plein écran : l'interface legacy déplace la vue vidéo dans une nouvelle
 * fenêtre, alors que la surface reste liée à celle capturée à l'ouverture — d'où
 * un écran noir. Sans effet si wid est déjà celui en cours. */
void dvddriver_bind_window(dvddriver_ctx *ctx, int wid);
void     dvddriver_present_index_gen(dvddriver_ctx *ctx, int idx, unsigned gen);
void     dvddriver_set_present_rect(dvddriver_ctx *ctx, int x, int y, int w, int h);

/* PERF (chantier 720×576, temporaire) — cumuls depuis l'ouverture : nombre
 * d'appels et temps total passé dans DVDDriverDecode (GPU) et dans le present
 * (ShowMPBuffer + CGSSetSurfaceBounds + CGSFlushSurface). Permet d'attribuer le
 * budget par picture entre CPU / Decode / present en UN seul run.
 * Gates de mesure associés : /tmp/hw_nodecode (saute Decode, garde le present),
 * /tmp/hw_nopresent=1|2 (saute le present, garde Decode). */
/* DIAGNOSTIC qualité : répartition des macroblocs soumis par type (8) et par
 * type de DCT (2, frame/champ). */
/* cvt3 : conversion des macroblocs à prédiction par CHAMP vers la prédiction
 * TRAME — [0] exacte, [1] laissé au moteur field natif, [2] approchée. */
void dvddriver_mb_stats(dvddriver_ctx *ctx, unsigned *mb8, unsigned *dct2,
                        unsigned *cvt3);

void dvddriver_perf_get(dvddriver_ctx *ctx, unsigned *n_dec, unsigned long *us_dec,
                        unsigned *n_pres, unsigned long *us_pres, unsigned *n_stale);

/* Diagnostic : nombre de macroblocs capturés / attendus pour la picture courante
 * (utile pour comprendre un submit rc=-2 = capture incomplète). */
unsigned dvddriver_surf_waits(const dvddriver_ctx *ctx);
/* Diagnostic « retours en arrière » : nombre d'appels Show par chemin —
 * [0] image cible demandée par le vout, [1] boucle de drainage du present,
 * [2] dd_recycle_locked (contre-pression / filet anti-famine). */
void dvddriver_show_counts(const dvddriver_ctx *ctx, unsigned out[3]);
void dvddriver_last_progress(const dvddriver_ctx *ctx, unsigned *captured,
                             unsigned *total);

/* Convertit un CBP libmpeg2 (bit 1<<b = bloc b) en convention GPU (bit 0x20>>b = bloc b). */
uint8_t dvddriver_cbp_from_libmpeg2(unsigned mpeg2_cbp);

/*
 * Ré-encode un bloc 8×8 déquantifié de libmpeg2 (decoder->DCTblock) au format
 * coefficients du driver : {u8 run, u8 pad, i16 level} en ordre zigzag.
 * scan = decoder->scan ; out ≥ 64*4 o. Retourne le nombre de coeffs non nuls.
 * dc_bias est retranché du DC (zz=0, après /16) : 1024 pour luma ET chroma
 * (le driver centre toutes les composantes sur 128). Voir dvddriver_backend.c.
 */
unsigned dvddriver_encode_block(const int16_t *dctblock, const uint8_t *scan,
                                int dc_bias, uint8_t *out);

/* Histogramme des intervalles entre deux presents (ms) : [0]<25 [1]<33 [2]<37
 * [3]<43 [4]<50 [5]<60 [6]<100 [7]>=100, plus le total. Distingue une cadence
 * irrégulière de notre côté d'une saccade structurelle 25 fps / écran 60 Hz. */
void dvddriver_decode_times(dvddriver_ctx *ctx, uint32_t out[8], uint32_t *n);
unsigned long dvddriver_last_decode_us(dvddriver_ctx *ctx);
unsigned long dvddriver_last_surf_wait_us(dvddriver_ctx *ctx);
unsigned long dvddriver_submit_wait_us(dvddriver_ctx *ctx);
unsigned long dvddriver_last_submit_wait_us(dvddriver_ctx *ctx);
unsigned long dvddriver_surf_wait_total_us(dvddriver_ctx *ctx);
void dvddriver_present_intervals(dvddriver_ctx *ctx, uint32_t out[8],
                                 uint32_t *total);

/* Ferme le décodeur HW et libère les ressources. */
void dvddriver_close(dvddriver_ctx *ctx);
/* Escamote la surface (ordre Z sous le contenu) sans fermer le décodeur. */
void dvddriver_set_surface_hidden(dvddriver_ctx *ctx, bool hidden);

/* ── SP4 : sous-titres du disque incrustés par le GPU ───────────────────────
 * Le driver ATI possède un plan subpicture qu'il compose lui-même sur la vidéo
 * décodée, à coût nul par image. En mode « surface » (le nôtre), il N'INTERPRÈTE
 * PAS le paquet SPU : son moteur ApplySPDCSQ ignore la commande 0x06 (adresses
 * des trames RLE) et sort aussitôt sur 0x01/0x02. C'est donc l'hôte qui décode
 * le RLE et fournit le bitmap 2 bits/pixel — le module « spu decoder »
 * dvddriver_spu.c s'en charge, et ne passe ici que le résultat.
 * Validé sur iBook G3 le 2026-07-23 ; voir doc/pb-offload/sp-hardware-subtitles-plan.md. */
typedef struct
{
    const uint8_t *bitmap;      /* 2 bits/pixel, 4 px/octet POIDS FORT D'ABORD,
                                 * 192 octets par ligne, coordonnées ABSOLUES
                                 * dans l'image (le placement se fait par la
                                 * transparence, pas par le rectangle).       */
    unsigned       lines;       /* lignes utiles, ≤ 576                       */
    uint8_t        palette[64]; /* palette du disque : 16 × { 0, Y, Cr, Cb }  */
    uint16_t       colors;      /* commande SPU 0x03 — 4 index, 4 bits chacun */
    uint16_t       contrasts;   /* commande SPU 0x04 — 4 alphas, 4 bits chacun*/
    int64_t        hide_in_us;  /* durée d'affichage ; ≤ 0 = pas d'échéance   */
    /* ── 10.2 SEULEMENT : le pilote décode le paquet LUI-MÊME ────────────────
     * Relevé sur le DVD Player d'Apple avec un relais journalisant : il ne
     * décode pas le RLE, il dépose le PAQUET SPU BRUT dans le tampon de la
     * série b puis appelle `ApplySPDCSQ` une fois par commande, l'argument
     * étant l'OFFSET de l'octet de commande DANS CE PAQUET. Le blit du pilote
     * 10.2 exige ce paquet : il l'analyse pour en déduire la ligne de départ
     * (ctx[0x1B4]). Le champ `bitmap` ci-dessus reste la voie de 10.3/10.4, où
     * c'est bien à l'hôte de décoder. */
    const uint8_t *packet;      /* paquet SPU brut, en-tête compris           */
    unsigned       packet_size;
    const uint16_t *cmd_off;    /* offsets des octets de commande, dans l'ordre*/
    unsigned       cmd_count;
} dvddriver_sp_picture;

/* true si le plan SP est exploitable sur ce device (toutes les entrées résolues). */
bool dvddriver_sp_usable(dvddriver_ctx *ctx);
/* Incruste `sp`. Un montage par SOUS-TITRE, JAMAIS par image. La cadence est
 * plafonnée à 10/s en interne : au-delà, l'appel renvoie false et compte un
 * abandon (garde-fou contre un DCSQ pathologique — c'est une rafale d'appels SP
 * qui a figé la machine le 2026-07-22). */
/* `probes` (facultatif, peut être NULL) — DISPOSITION UNIQUE, un indice = une
 * valeur. ⚠ Ne jamais réutiliser un indice : une double écriture m'a déjà fait
 * journaliser « couleurs/contrastes = 0 » et croire à un défaut inexistant.
 *   [0] pixels opaques du plan APRÈS toute la séquence
 *   [1] pixels opaques du plan AVANT la séquence
 *   [2] première couleur opaque rencontrée (ARGB)
 *   [3] empreinte de la source que nous venons d'écrire
 *   [4] pointeur de destination ctx[0x204]
 *   [5] pixels opaques JUSTE APRÈS SetSPBuffer (c'est lui qui blitte)
 *   [6] (couleurs << 16) | contrastes, tels que passés au driver
 *   [7] drapeau ctx[0x1D0] juste après SetSPBuffer                          */
bool dvddriver_sp_submit(dvddriver_ctx *ctx, const dvddriver_sp_picture *sp,
                         uint32_t probes[8]);
/* Efface l'incrustation (bitmap entièrement transparent, plan laissé armé). */
bool dvddriver_sp_hide(dvddriver_ctx *ctx);
/* Échéance de disparition atteinte ? Lecture seule, aucun appel driver. */
bool dvddriver_sp_hide_due(dvddriver_ctx *ctx);
/* Les six mots que la routine d'affichage du driver compose dans sa commande
 * IOKit : [0] haut, [1] gauche, [2] droite, [3] décalage de ligne source,
 * [4] découpe haut, [5] découpe bas. Lecture seule. */
void dvddriver_sp_display_words(dvddriver_ctx *ctx, int32_t out[6]);
/* Compteurs de diagnostic : [0] incrustations, [1] effacements, [2] abandons. */
void dvddriver_sp_counters(dvddriver_ctx *ctx, uint32_t out[3]);

/* ── Chantier SP (sous-titres composés par le décodeur matériel) ────────────
 * Sonde de reconnaissance : renvoie true si le plan subpicture est disponible
 * et remplit `probe` avec les 16 mots relevés par DVDDriverGetSPBuffer à
 * l'ouverture (8 descripteurs × 2 champs) ainsi que la couleur-clé du plan SP.
 * Sert à établir si ces descripteurs sont des adresses exploitables côté CPU
 * ou de simples poignées GPU — le désassemblage ne tranche pas. */
bool dvddriver_sp_probe(dvddriver_ctx *ctx, uint32_t probe[16], uint32_t *keycolor);
/* Premier mot lu à l'adresse de chacun des 8 tampons SP : confirme (ou non)
 * que ces descripteurs sont des adresses mappées dans le processus. */
bool dvddriver_sp_first_words(dvddriver_ctx *ctx, uint32_t words[8]);
/* SP1 — teste l'accès en ÉCRITURE au tampon SP idx (motif écrit, relu, effacé).
 * ⚠ uniquement AVANT le premier Decode. */
bool dvddriver_sp_write_test(dvddriver_ctx *ctx, int idx, uint32_t read_back[2]);
/* SP2 — pose un sous-titre de test (bande pleine en bas de l'image) dans le plan
 * matériel et l'affiche. rc[] reçoit les codes de retour du driver. */
bool dvddriver_sp_show_test(dvddriver_ctx *ctx, unsigned width, unsigned height,
                            int rc[6]);
/* Mots du contexte driver qui gouvernent le plan SP :
 * [0] ctx+0x1FC (drapeau de mode), [1] ctx[0], [2] ctx+0x1B0, [3] ctx+0x1C8. */
bool dvddriver_sp_state(dvddriver_ctx *ctx, uint32_t out[5]);   /* [4] = ctx[0x20], capacités */
/* Valeurs de SORTIE d'OpenDevice, longtemps ignorées par ce backend :
 * [0] caps (son BIT 1 gouverne le plan subpicture), [1..4] dims, [5] five, [6] eight. */
bool dvddriver_open_outputs(dvddriver_ctx *ctx, uint32_t out[7]);
/* Réaffiche l'incrustation SP déjà montée. ⚠ appels ESPACÉS uniquement. */
bool dvddriver_sp_reshow(dvddriver_ctx *ctx);
/* Destination du blit subpicture (ctx[0x204]), lecture seule. 0 = non renseignée. */
uint32_t dvddriver_sp_dest(dvddriver_ctx *ctx);
/* SP5c — contenu de la destination du blit avant/après les premiers Show. */
int dvddriver_sp_dest_probes(dvddriver_ctx *ctx, uint32_t out[3][8]);
/* SP7 — géométrie du blit, lecture seule : [0] ctx[0x204] destination ARGB,
 * [1] ctx[0x410] largeur, [2] ctx[0x414] pas de ligne, [3] ctx[0x418] hauteur.
 * En 720×576 on attend 720 / 768 / 576 ; un pas de 576 signalerait un rect
 * encore transposé. */
bool dvddriver_sp_geometry(dvddriver_ctx *ctx, uint32_t out[4]);
/* SP7b — empreintes par ÉTAPE de la séquence SP (lecture seule), pour isoler
 * celle qui reste muette : [0]/[1] source avant/après ApplySPDCSQ,
 * [2]/[3]/[4] destination avant SetSPBuffer / après / après ShowSPBuffer,
 * [5] ctx[0x1D0] relu après SetSPBuffer. Chaque empreinte vaut
 * (mots non nuls << 16) | hachage. Renvoie 0 si la séquence n'a pas tourné. */
int dvddriver_sp_stage_probes(dvddriver_ctx *ctx, uint32_t out[6]);

/* La surface est-elle liée à la fenêtre de VLC (true) ou à la fenêtre Carbon
 * que le backend a créée (false) ? L'appelant PROPOSE un wid externe, mais le
 * backend peut le refuser — certaines familles GPU n'affichent que dans leur
 * propre fenêtre. À interroger APRÈS dvddriver_open() pour savoir ce qui a
 * réellement été retenu. */
bool dvddriver_uses_external_window(dvddriver_ctx *ctx);

#endif /* VLC_DVDDRIVER_BACKEND_H */
