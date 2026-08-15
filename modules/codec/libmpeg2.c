/*****************************************************************************
 * libmpeg2.c: mpeg2 video decoder module making use of libmpeg2.
 *****************************************************************************
 * Copyright (C) 1999-2001 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Gildas Bazin <gbazin@videolan.org>
 *          Christophe Massiot <massiot@via.ecp.fr>
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
 * NOTA BENE: this module requires the linking against a library which is
 * known to require licensing under the GNU General Public License version 2
 * (or later). Therefore, the result of compiling this module will normally
 * be subject to the terms of that later license.
 *****************************************************************************/


/*****************************************************************************
 * Preamble
 *****************************************************************************/

#warning This module is not officially supported anymore

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif
#include <assert.h>

#include <vlc_common.h>
#include <sys/time.h>
#include <sys/utsname.h>
#include <vlc_plugin.h>
#include <vlc_codec.h>
#include <vlc_block_helper.h>
#include <vlc_cpu.h>
#include "cc.h"
#include "synchro.h"

#include <mpeg2.h>

#ifdef __APPLE__
# include "dvddriver_backend.h"  /* décodage MPEG-2 accéléré matériel (ATI DVDDriver, G3/G4) */
# include "dvddriver_piccontext.h" /* U4 : contexte picture (present piloté par le vout) */
# include "dvddriver_spu.h"      /* SP4 : sous-titres sur le plan subpicture matériel */
#endif

/*****************************************************************************
 * decoder_sys_t : libmpeg2 decoder descriptor
 *****************************************************************************/
#define DPB_COUNT (3+1)
typedef struct
{
    picture_t *p_picture;
    bool      b_linked;
    bool      b_displayed;
} picture_dpb_t;

struct decoder_sys_t
{
    /*
     * libmpeg2 properties
     */
    mpeg2dec_t          *p_mpeg2dec;
    const mpeg2_info_t  *p_info;
    bool                b_skip;

    /*
     * Input properties
     */
    vlc_tick_t       i_previous_pts;
    vlc_tick_t       i_current_pts;
    vlc_tick_t       i_previous_dts;
    vlc_tick_t       i_current_dts;
    bool             b_garbage_pic;
    bool             b_after_sequence_header; /* is it the next frame after
                                               * the sequence header ?    */
    bool             b_slice_i;             /* intra-slice refresh stream */
    bool             b_second_field;

    bool             b_preroll;

    /* */
    picture_dpb_t        p_dpb[DPB_COUNT];

    /*
     * Output properties
     */
    decoder_synchro_t *p_synchro;
    int             i_sar_num;
    int             i_sar_den;
    vlc_tick_t      i_last_frame_pts;

    /* Closed captioning support */
    uint32_t        i_cc_flags;
    vlc_tick_t      i_cc_pts;
    vlc_tick_t      i_cc_dts;
#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)
    cc_data_t       cc;
#endif
    uint8_t        *p_gop_user_data;
    uint32_t        i_gop_user_data;

#ifdef __APPLE__
    /* Décodage MPEG-2 accéléré matériel (ATI DVDDriver). b_hwaccel : l'option est
     * activée ET un décodeur HW existe. p_hw : contexte backend, créé au premier
     * STATE_SEQUENCE (quand w×h est connu). b_hw_picture : la picture en cours de
     * décodage est une I-frame capturée pour le GPU (→ soumise au STATE_SLICE). */
    bool             b_hwaccel;
    bool             b_hw_picture;
    /* Nature du contenu entrelacé : film 25 fps codé en 2:2 (les deux champs
     * viennent du MÊME instant → le tissage est correct, le bob n'apporterait
     * rien et coûterait la moitié de la résolution verticale) ou vraie vidéo
     * entrelacée (champs à 1/50 s d'écart → le bob double la fluidité).
     * `progressive_frame` est justement le drapeau qui le dit. */
    uint32_t         i_pic_prog, i_pic_inter, i_fields_2, i_fields_3;
    dvddriver_ctx   *p_hw;
    /* Dimensions pour lesquelles p_hw a été ouvert : un changement de résolution
     * en cours de flux (chaînage de titres) exige de fermer/rouvrir le décodeur
     * HW, sinon rect/surfaces/clamp gardent les anciennes dimensions. */
    unsigned         i_hw_width, i_hw_height;
    /* Fenêtre CGS à laquelle la surface a été liée à l'ouverture. Le passage
     * en plein écran déplace la vidéo dans une AUTRE fenêtre : la surface
     * resterait liée à une fenêtre invisible (écran noir). On rouvre alors le
     * décodeur sur la nouvelle fenêtre. */
    int              i_hw_wid;
    /* U4 — present piloté par le VOUT (remplace M3/hw_surf_owner) : au submit on
     * attache à la picture_t un picture_context_t {out_idx, génération} ; le vout,
     * à l'affichage (ordre PTS), présente la surface si sa génération est à jour.
     * Le pacing PTS du vout s'applique alors au present matériel → synchro A/V.
     * i_probe_defers : nombre de fois où le commit a été différé en attendant que
     * le vout publie son wid (chemin A-idéal, surface sur la fenêtre VLC) — borné
     * pour retomber sur la fenêtre Carbon si le vout ne vient jamais. */
    unsigned         i_probe_defers;
    /* 2a — PROBE-THEN-COMMIT (gate de livraison entrelacé). Plutôt que de décider
     * le mode à l'ouverture (une picture field refusée au submit en remplacement
     * est perdue des DEUX côtés : CPU a sauté IDCT+MC, GPU refuse), on démarre
     * TOUJOURS en CPU pur, on observe le type de prédiction des P/B pendant
     * ~2 s, puis on décide UNE fois à une I-frame :
     *   - flux progressif (prédiction frame) → ouvrir le HW en REMPLACEMENT
     *     plein écran à cette I-frame (les réfs repartent de la I, pas besoin de
     *     réfs « chaudes ») → gain CPU ;
     *   - flux entrelacé (field-predicted) → NE PAS ouvrir le HW, rester 100 %
     *     CPU (zéro corruption, comportement PowerVLC actuel sur DVD entrelacé).
     * b_hw_probe : la sonde est active (mode par défaut ; contournée si le toggle
     * /tmp/hw_replace force explicitement 0/1). b_hw_committed : décision prise.
     * i_probe_pb / i_probe_field : P/B observées et, parmi elles, field-predicted.
     * i_probe_pics : total de pictures observées (garde-fou flux tout-I). */
    bool             b_hw_probe;
    bool             b_hw_committed;
    /* Le backend a abandonné le matériel (stalls répétés dans DVDDriverDecode →
     * garde-fou anti-wedge) : on ne soumet plus rien et le CPU reprend tout. */
    bool             b_hw_giveup;
    /* Une picture de RÉFÉRENCE (I ou P) n'a pas pu être décodée par le GPU : la
     * chaîne de références matérielle a divergé du flux. Tout ce qui suit prédit
     * à partir d'une surface périmée — image juste par endroits, fausse là où ça
     * bouge. On gèle l'affichage matériel jusqu'à la prochaine I décodée avec
     * succès, qui repart d'une chaîne saine (une I ne référence rien). */
    bool             b_hw_stale;
    /* SP2b — images restant avant de rejouer UNE FOIS la séquence subpicture
     * (0 = ne rien rejouer). Jamais sur le chemin de present, jamais par image. */
    int              i_sp_replay;
    int              i_sp_pulse, i_sp_tick;   /* réaffichage SP borné (SP2c) */
    int              i_sp_dest_left, i_sp_dest_tick;   /* sonde ctx[0x204] (SP5b) */
    /* Réouverture différée du décodeur matériel après un changement de fenêtre
     * (bascule plein écran). On NE peut PAS fermer et rouvrir dans le même appel
     * — ça gèle VLC (l'input ne s'arrête plus) — donc on ferme, on lève ce
     * drapeau, et on rouvre à l'image I SUIVANTE. Le type de flux étant déjà
     * connu, on saute la sonde : la reprise coûte un GOP au lieu de la sonde
     * complète plus un GOP. */
    bool             b_hw_reopen;
    /* Modifications du portage 10.2 actives ? (cf. mpeg2-hwaccel-102mods) */
    bool             b_102mods;
    /* PERF Panther : horodatage du picture_begin (segment CPU vs Decode) */
    unsigned long    i_hw_pic_t0;
    bool             b_async;        /* soumission GPU asynchrone active */
    unsigned         i_hw_open_fails; /* échecs d'ouverture consécutifs (retente aux I) */
    /* ★ AUTO-RENAISSANCE (10.3, « dédoublement jusqu'au seek ») : la surface
     * CGS créée à la 1re ouverture peut naître dans un état de composition
     * défectueux (fenêtre en cours de résize 4:3→16:9 à la transition
     * menu→film, app active…) : le WindowServer la double-bufferise et chaque
     * flush alterne tampon frais/périmé → image N mêlée à N-1 à l'écran,
     * INVISIBLE de tous les compteurs internes (present ~500 µs au lieu de
     * ~2 ms — la bascule de tampon remplace la recomposition). Un seek répare
     * en recréant la surface une fois la géométrie stable. On automatise :
     * UNE renaissance différée ~2 s après chaque premier engagement. */
    bool             b_hw_selfheal_done;
    unsigned         i_hw_selfheal_pics;
    int64_t          i_hw_domain_gen; /* génération de domaine dvdnav à l'ouverture */
    unsigned         i_probe_pb, i_probe_field, i_probe_pics;
    /* Garde « vraie vidéo entrelacée » (cf. HW_CVT_MIN_PCT) : décision prise une
     * seule fois par flux, et compteur de pictures observées depuis le commit. */
    bool             b_cvt_checked;
    unsigned         i_cvt_pics;
#endif
};

#ifdef __APPLE__
/* Les modifications du chemin matériel apportées par le portage 10.2 sont-elles
 * actives ? Elles ont toutes été mesurées sur Jaguar ; sur Darwin 8 et au-delà
 * elles remplacent un comportement validé sur ce système-là. */
static bool Hw102Mods( decoder_t *p_dec )
{
    int i_want = (int) var_InheritInteger( p_dec, "mpeg2-hwaccel-102mods" );
    struct utsname uts;

    if( i_want >= 0 )
        return i_want != 0;

    /* Darwin 6 (10.2 Jaguar) SEUL : c'est là qu'elles ont été mesurées. Sur
     * Darwin 7 (10.3) elles coûtent 3 ms de plus par Decode et un tiers des
     * images ; sur Darwin 8 (10.4) elles wedgent le GPU. */
    return uname( &uts ) == 0 && atoi( uts.release ) > 0
        && atoi( uts.release ) < 7;
}

/* Mode field effectif. -1 = automatique : mode 4 là où les modifications 10.2
 * sont actives (il y a été mesuré), mode 1 ailleurs — c'est le défaut validé
 * sur Tiger, et le commentaire d'origine du module qualifie le mode 4
 * d'impasse. ⚠ Les DEUX lecteurs de l'option doivent passer par ici : la
 * décision « entrelacé → matériel ou 100 % CPU » teste `> 0`, et un -1 non
 * résolu y vaut « désactivé ». */
static int HwFieldMode( decoder_t *p_dec, bool b_102mods )
{
    int i_field = (int) var_InheritInteger( p_dec, "mpeg2-hwaccel-field" );

    if( i_field < 0 )
        i_field = b_102mods ? 4 : 1;
    return i_field;
}
#endif

#ifdef __APPLE__
/* 2a — nombre minimal de P/B à observer avant de trancher (assez pour voir la
 * field-prediction d'un flux entrelacé), plafond de pictures (flux tout-I → on
 * tranche quand même), et seuil de field-prediction (le VOB entrelacé en a
 * ~100 %, un progressif propre 0 %). */
#define HW_PROBE_MIN_PB   8u
#define HW_PROBE_MAX_PICS 80u
#define HW_PROBE_FIELD_PCT 5u
/* U4 — nombre max de I-frames où le commit attend le wid du vout (chemin A-idéal)
 * avant de retomber sur la fenêtre Carbon (cas sans vout). */
#define HW_MAX_COMMIT_DEFERS 4u

/* ★★★ GARDE « VRAIE VIDÉO ENTRELACÉE » — ce qu'elle pèse, et pourquoi le
 * critère a changé (2026-08-05, mesure hors machine).
 *
 * La sonde ci-dessus mesure la field-prediction AU NIVEAU PICTURE. Elle rend
 * 100 % aussi bien sur un DVD de cinéma que sur les menus animés, alors que les
 * deux se comportent de façon OPPOSÉE sur ce GPU : le verdict utile se prend au
 * MACROBLOC. Le mode 4 ne convertit en prédiction trame que si les DEUX
 * prédictions de champ portent le même vecteur et la même parité — vrai pour du
 * film (les deux champs viennent de la même image), faux pour de la vidéo
 * native. Ce qui n'est pas converti part au moteur field natif de l'ATI, dont
 * l'adressage n'est pas reversé : blocs déplacés qui s'accumulent sur le GOP.
 *
 * ⚠⚠ LE PREMIER CRITÈRE ÉTAIT LE MAUVAIS, et il coûtait toute l'accélération.
 * Il exigeait qu'une majorité des macroblocs FIELD soit convertible, et
 * démontait le décodage matériel sinon. Or la mesure faite hors machine sur le
 * VOB de menu du disque de test (harnais `scratchpad/mb/mbstat.c`, qui rejoue la
 * MÊME libmpeg2 que la machine) dit ceci :
 *   macroblocs à prédiction par champ = **3,5 % du total** ; le reste (96,5 %)
 *   est déjà en prédiction TRAME, donc décodé EXACTEMENT par ce GPU.
 * Le taux de convertibilité parmi ces 3,5 % est effectivement proche de zéro —
 * mais s'en servir pour tout couper revenait à jeter 96,5 % de travail juste et
 * à repasser 100 % au CPU, que cette machine ne tient pas à 720×576. C'est
 * exactement le symptôme rapporté : « net 2 s, pixelisé quand le matériel
 * s'engage, puis net mais ça lague » — la dernière phase étant le repli CPU.
 *
 * ⇒ On pèse désormais le DÉGÂT RÉEL : la part des macroblocs qui partent au
 * moteur field, rapportée au TOTAL des macroblocs. En dessous du seuil, on garde
 * l'accélération ; au-dessus (vraie vidéo 50i, où la prédiction par champ
 * domine), on rend la main au CPU, lent mais correct.
 * ⚠ Le film n'est concerné dans aucun cas : il a ZÉRO macrobloc field. */
#define HW_CVT_MIN_MB   8000u   /* ~5 pictures 720x576 : de quoi juger */
#define HW_CVT_MAX_PCT    25u   /* part max du total laissée au moteur field */
/* Plafond de pictures après lesquelles on cesse d'interroger le compteur : un flux
 * sans AUCUN macrobloc field (le cas du film) n'a rien à décider. */
#define HW_CVT_MAX_PICS   60u

/* GATE DE RÉSOLUTION — plafond de ce que le décodeur ATI sait faire.
 * Il a longtemps été fixé à CIF (384×288) parce que le 720×576 s'effondrait ; on
 * croyait à un mur de débit GPU. C'était faux : le vrai coupable était le premier
 * DVDDriverDecode (~865 ms de setup one-shot) qui mettait la synchro en retard,
 * donc plus aucune picture affichée, donc plus aucun buffer MP rendu au driver,
 * donc blocage (cf. doc/pb-offload/perf-720x576-plan.md). Une fois le décodeur
 * pré-chauffé à l'ouverture et les buffers correctement recyclés, on mesure sur
 * l'iBook G3 à 720×576 : Decode ~4,4 ms/picture + present ~0,5 ms, pour un budget
 * de 40 ms — et en A/B sur le même clip, CPU ~29 % contre ~53 % en logiciel, avec
 * 5 pictures en retard contre 78.
 * Le plafond ne sert donc plus qu'à refuser ce que ce décodeur DVD n'a jamais été
 * conçu pour traiter (MPEG-2 HD) : on couvre toutes les résolutions DVD (720×576
 * PAL, 720×480 NTSC) avec un peu de marge. Override : /tmp/hw_force. */
#define HW_MAX_PIXELS_REALTIME (768u * 576u)   /* ~442k px : tout le DVD, pas la HD */
#endif

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
static int  OpenDecoder( vlc_object_t * );
static void CloseDecoder( vlc_object_t * );

static int DecodeVideo( decoder_t *, block_t *);
#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)
static void SendCc( decoder_t *p_dec );
#endif

static picture_t *GetNewPicture( decoder_t * );
static void PutPicture( decoder_t *, picture_t * );

static void GetAR( decoder_t *p_dec );

static void Reset( decoder_t *p_dec );

/* */
static void DpbInit( decoder_t * );
static void DpbClean( decoder_t * );
static picture_t *DpbNewPicture( decoder_t * );
static void DpbUnlinkPicture( decoder_t *, picture_t * );
static int DpbDisplayPicture( decoder_t *, picture_t * );

#ifdef __APPLE__
#define MPEG2_HWACCEL_TEXT N_("Use MPEG-2 hardware acceleration when available")
#define MPEG2_HWACCEL_LONGTEXT N_( \
    "Decode MPEG-2 streams on the GPU (the AppleVA pipeline of Apple's DVD " \
    "Player) whenever a hardware decoder is present (ATI, Intel GMA950, " \
    "nVidia), falling back to the libmpeg2 software decoder automatically. " \
    "Cuts CPU load dramatically on old Macs." )
#define MPEG2_HWACCEL_FIELD_TEXT N_("Field mode of the MPEG-2 hardware decoder (advanced)")
#define MPEG2_HWACCEL_FIELD_LONGTEXT N_( \
    "Hardware decoding of field-predicted macroblocks (interlaced streams, " \
    "DVD). 0 = off (interlaced content falls back to the processor); " \
    "4 = equivalent frame prediction (the default: the field engine of the " \
    "GPU tears on motion); 1/2/3 = native field engine, for debugging only." )
#define MPEG2_HWACCEL_SUBS_TEXT N_("Subtitles and OSD over hardware-accelerated video")
#define MPEG2_HWACCEL_SUBS_LONGTEXT N_( \
    "Compose the subtitles (DVD SPU) and the on-screen display over the " \
    "picture decoded by the GPU. Without this option the hardware output " \
    "covers everything and subtitles stay invisible. Only affects the video " \
    "shown in the VLC window." )
#define MPEG2_ASYNC_TEXT N_("Asynchronous GPU submission (advanced)")
#define MPEG2_ASYNC_LONGTEXT N_( \
    "Issue the DVDDriverDecode call on a dedicated thread, so that the VLD " \
    "of the next picture runs while the GPU works. Measured on the iBook G3: " \
    "Decode is time spent blocked in the driver, and overlapping it removes " \
    "the shortfall in the 40 ms per picture budget." )
#define MPEG2_102MODS_TEXT N_("10.2 port changes on the hardware path (advanced)")
#define MPEG2_102MODS_LONGTEXT N_( \
    "-1 = automatic (on under Mac OS X 10.2 and 10.3, off from 10.4 on, " \
    "where they replaced behaviour validated on the machine itself), " \
    "0 = off, 1 = on." )
#define MPEG2_HWSUBS_TEXT N_("DVD subtitles drawn by the GPU")
#define MPEG2_HWSUBS_LONGTEXT N_( \
    "Hand the DVD subtitles to the subpicture plane of the ATI hardware " \
    "decoder: the GPU composes them onto the picture itself, at no per-picture " \
    "cost, where drawing them through a window costs 15 to 50 ms on this " \
    "hardware. No effect while hardware decoding is off, as software rendering " \
    "then takes over." )
#endif

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
vlc_module_begin ()
    set_description( N_("MPEG I/II video decoder (using libmpeg2)") )
#if (defined (__powerpc__) || defined (__POWERPC__)) && !defined (__ALTIVEC__)
    /* Pure-C libmpeg2 profiled ~30% lighter than avcodec's mpeg2 decoder
     * on a G3, the difference between a black screen and watchable DVD
     * playback; avcodec (70) stays preferred everywhere else. */
    set_capability( "video decoder", 80 )
#else
    set_capability( "video decoder", 50 )
#endif
    set_category( CAT_INPUT )
    set_subcategory( SUBCAT_INPUT_VCODEC )
    set_callbacks( OpenDecoder, CloseDecoder )
    add_shortcut( "libmpeg2" )
#ifdef __APPLE__
    add_bool( "mpeg2-hwaccel", true, MPEG2_HWACCEL_TEXT, MPEG2_HWACCEL_LONGTEXT, false )
    /* Chantier S — remplace l'ancien gate fichier /tmp/hw_subs. Décidé ICI (le
     * décodeur ouvre la surface) et publié sur le bus pour le vout : un seul
     * point de décision, sinon vout et backend peuvent diverger (cf.
     * DVDDRIVER_VAR_SUBS dans dvddriver_piccontext.h). */
    add_bool( "mpeg2-hwaccel-subs", true, MPEG2_HWACCEL_SUBS_TEXT,
              MPEG2_HWACCEL_SUBS_LONGTEXT, false )
    /* Option AVANCÉE (privée, non affichée) : mode de déblocage du décodage HW des
     * MB field-predicted (flux entrelacés). 0 = field NON soumis au GPU → repli CPU ;
     * 1 = brut (A/B) ; 2 = clamp MV vertical field ; 3 = clamp + full-pel vertical.
     * **DÉFAUT = 1 (moteur field natif, vecteur vertical à l'échelle correcte).**
     * Le mode 4 (conversion en prédiction frame) est une IMPASSE : mesuré sur un
     * vrai DVD, seuls 10 997 macroblocs field sur 669 561 (1,6 %) ont leurs deux
     * prédictions de champ identiques, donc convertibles exactement — pour les
     * 98,4 % restants aucun vecteur frame n'est équivalent. C'est bien le moteur
     * field du GPU qu'il faut alimenter correctement (le lecteur DVD d'Apple lit
     * ces disques proprement sur ce même matériel : le moteur fonctionne).
     * Voir doc/pb-offload/phase2-field-findings.md. */
    /* Défaut 4 (prédiction frame équivalente) et non 1 (moteur field brut) :
     * le commentaire de dvddriver_picture_mb_begin l'annonçait déjà comme le
     * défaut voulu pour l'entrelacé, mais l'option était restée à 1. Mesuré sur
     * le DVD de Chihiro (iBook G3, 10.2) : images affichées par tranche de 5 s
     * 113-116 → 117-121, retard moyen 1-2 ms → 0,3-0,6 ms, et surtout PIRE
     * retard 40 ms → 5 ms, ce qui est précisément la régularité qui manquait. */
    add_integer( "mpeg2-hwaccel-field", -1, MPEG2_HWACCEL_FIELD_TEXT,
                 MPEG2_HWACCEL_FIELD_LONGTEXT, true )
        change_integer_range( -1, 4 )
        change_private()
    /* ⚠ Interrupteur des modifications apportées au chemin matériel par le
     * portage Mac OS X 10.2. Toutes ont été MESURÉES SUR JAGUAR puis appliquées
     * à tous les systèmes, dont 10.4 — où elles ont remplacé un comportement
     * qui y avait, lui, été validé. Résultat : la lecture DVD accélérée, fiable
     * en 1.0.0 sur Tiger, y WEDGE le GPU dès les premières images (processus en
     * état U inkillable, aucun present, « waiting decoder fifos to empty » en
     * boucle ; reproduit deux fois machine fraîchement éteinte et rallumée).
     * -1 = automatique : actives sous Darwin 8 (10.2/10.3), inactives à partir
     * de 10.4 ; 0 = jamais ; 1 = toujours. Sert aussi à bisecter sans
     * reconstruire. */
    add_integer( "mpeg2-hwaccel-102mods", -1, MPEG2_102MODS_TEXT,
                 MPEG2_102MODS_LONGTEXT, true )
        change_integer_range( -1, 1 )
        change_private()
    /* ⚠ DÉFAUT OFF : mesuré sur Panther, le recouvrement fonctionne (l'attente
     * de la fin du Decode précédent tombe à ~200 ms sur 35 s de lecture) mais
     * n'apporte AUCUN gain de cadence — le goulot est le CPU, pas l'attente du
     * GPU. Le laisser actif changerait un chemin validé sur Tiger contre rien.
     * Conservé comme outil : il redeviendra utile si le coût CPU baisse. */
    add_bool( "mpeg2-hwaccel-async", false, MPEG2_ASYNC_TEXT,
              MPEG2_ASYNC_LONGTEXT, true )
        change_private()
    /* SP4/SP10 — sous-titres DVD incrustés par le plan subpicture MATÉRIEL.
     * Défaut ON : validé sur le RV200/Tiger avec le protocole 1.1 à un seul
     * STA_DSP par apparition. Les SET_COLOR/SET_CONTR supplémentaires restent
     * réservés au Rage 128 ; sur le RV200 ils causaient une grosse saccade à
     * chaque sous-titre alors que SetSPBuffer avait déjà chargé ces valeurs.
     * ⚠ Quand ce module prend la piste, il REMPLACE `spudec` : si le décodage
     * matériel n'est finalement pas actif, les sous-titres sont perdus plutôt
     * que rendus en logiciel (un avertissement est émis une fois). Mettre
     * l'option à 0 rétablit le rendu logiciel. */
    add_bool( "mpeg2-hwaccel-hwsubs", true, MPEG2_HWSUBS_TEXT,
              MPEG2_HWSUBS_LONGTEXT, false )

    /* Sous-module « spu decoder » : consomme les paquets SPU bruts du disque et
     * les remet au plan subpicture matériel au lieu d'en faire un subpicture_t.
     * Priorité au-dessus de `spudec` (75) ; il décline quand le décodeur
     * matériel n'est pas ouvert, et spudec reprend alors la main. */
    add_submodule ()
    set_description( N_("DVD subtitles on the ATI hardware subpicture plane") )
    set_capability( "spu decoder", 100 )
    set_category( CAT_INPUT )
    set_subcategory( SUBCAT_INPUT_SCODEC )
    set_callbacks( dvddriver_spu_Open, dvddriver_spu_Close )
#endif
vlc_module_end ()

/*****************************************************************************
 * OpenDecoder: probe the decoder and return score
 *****************************************************************************/
static int OpenDecoder( vlc_object_t *p_this )
{
    decoder_t *p_dec = (decoder_t*)p_this;
    decoder_sys_t *p_sys;
    uint32_t i_accel = 0;

    if( p_dec->fmt_in.i_codec != VLC_CODEC_MPGV )
        return VLC_EGENERIC;

    /* Select only recognized original format (standard mpeg video) */
    switch( p_dec->fmt_in.i_original_fourcc )
    {
    case VLC_FOURCC('m','p','g','1'):
    case VLC_FOURCC('m','p','g','2'):
    case VLC_FOURCC('m','p','g','v'):
    case VLC_FOURCC('P','I','M','1'):
    case VLC_FOURCC('h','d','v','2'):
        break;
    default:
        if( p_dec->fmt_in.i_original_fourcc )
            return VLC_EGENERIC;
        break;
    }

    /* Allocate the memory needed to store the decoder's structure */
    if( ( p_dec->p_sys = p_sys = calloc( 1, sizeof(*p_sys)) ) == NULL )
        return VLC_ENOMEM;

    /* Initialize the thread properties */
    p_sys->p_mpeg2dec = NULL;
    p_sys->p_synchro  = NULL;
    p_sys->p_info     = NULL;
    p_sys->i_current_pts  = 0;
    p_sys->i_previous_pts = 0;
    p_sys->i_current_dts  = 0;
    p_sys->i_previous_dts = 0;
    p_sys->i_sar_num = 0;
    p_sys->i_sar_den = 0;
    p_sys->b_garbage_pic = false;
    p_sys->b_slice_i  = false;
    p_sys->b_second_field = false;
    p_sys->b_skip     = false;
    p_sys->b_preroll = false;
    DpbInit( p_dec );

    p_sys->i_cc_pts = 0;
    p_sys->i_cc_dts = 0;
    p_sys->i_cc_flags = 0;
#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)
    cc_Init( &p_sys->cc );
#endif
    p_sys->p_gop_user_data = NULL;
    p_sys->i_gop_user_data = 0;

#ifdef __APPLE__
    /* Accélération matérielle MPEG-2 (AppleVA) : gate = option activée + un
     * décodeur GPU présent sur l'écran principal. Le contexte est créé plus
     * tard (STATE_SEQUENCE, quand les dimensions + la surface du vout sont
     * connues) ; ici on ne fait que décider si on tentera le chemin HW. */
    p_sys->p_hw = NULL;
    p_sys->b_hw_picture = false;
    p_sys->b_hw_probe = false;
    p_sys->b_hw_committed = false;
    p_sys->b_hw_giveup = false;
    p_sys->b_hw_stale = false;
    p_sys->b_hw_reopen = false;
    p_sys->b_102mods = Hw102Mods( p_dec );
    p_sys->i_hw_open_fails = 0;
    p_sys->b_hw_selfheal_done = false;
    p_sys->i_hw_selfheal_pics = 0;
    p_sys->i_probe_pb = p_sys->i_probe_field = p_sys->i_probe_pics = 0;
    p_sys->i_probe_defers = 0;
    p_sys->b_cvt_checked = false;
    p_sys->i_cvt_pics = 0;
    p_sys->b_hwaccel = var_InheritBool( p_dec, "mpeg2-hwaccel" )
                       && dvddriver_available();
    /* U4 — bus libvlc : le vout lit le device HW (DVDDRIVER_VAR_CTX) + le callback
     * de present (DVDDRIVER_VAR_PRESENT) à chaque display pour présenter les
     * surfaces (jamais en cache → NULL au close = plus de present). Créés ici,
     * posés à l'ouverture du contexte, remis NULL au close. */
    var_Create( p_dec->obj.libvlc, DVDDRIVER_VAR_CTX,     VLC_VAR_ADDRESS );
    var_Create( p_dec->obj.libvlc, DVDDRIVER_VAR_PRESENT, VLC_VAR_ADDRESS );
    var_Create( p_dec->obj.libvlc, DVDDRIVER_VAR_HIDE,    VLC_VAR_ADDRESS );
    var_Create( p_dec->obj.libvlc, DVDDRIVER_VAR_SP_HIDE, VLC_VAR_ADDRESS );
    var_SetAddress( p_dec->obj.libvlc, DVDDRIVER_VAR_HIDE,
                    (void *) dvddriver_set_surface_hidden );
    var_SetAddress( p_dec->obj.libvlc, DVDDRIVER_VAR_SP_HIDE,
                    (void *) dvddriver_sp_hide );
    /* Chantier S — valeur RÉELLE posée par HwOpenContext (elle dépend aussi du
     * chemin d'affichage retenu) ; le vout ne la lit qu'au premier present
     * matériel, donc toujours après. Ici, seulement l'existence + un défaut sûr. */
    var_Create( p_dec->obj.libvlc, DVDDRIVER_VAR_SUBS,    VLC_VAR_BOOL );
    var_SetBool( p_dec->obj.libvlc, DVDDRIVER_VAR_SUBS,   false );
    var_Create( p_dec->obj.libvlc, DVDDRIVER_VAR_HOLD,    VLC_VAR_BOOL );
    var_SetBool( p_dec->obj.libvlc, DVDDRIVER_VAR_HOLD,   false );
    var_Create( p_dec->obj.libvlc, "dvddriver-domain-gen", VLC_VAR_INTEGER );
    p_sys->i_hw_domain_gen = var_GetInteger( p_dec->obj.libvlc,
                                             "dvddriver-domain-gen" );
    msg_Dbg( p_dec, "décodage MPEG-2 matériel (ATI DVDDriver) : %s",
             p_sys->b_hwaccel ? "disponible, sera tenté" : "non (repli libmpeg2 CPU)" );
    msg_Dbg( p_dec, "modifications du portage 10.2 sur le chemin matériel : %s",
             p_sys->b_102mods ? "ACTIVES" : "inactives (comportement 1.0.0)" );
    {
        const char *psz_fam = dvddriver_family_name();
        msg_Dbg( p_dec, "greffon de carte retenu : %s",
                 psz_fam ? psz_fam : "aucun" );
    }
#endif

#if defined( __i386__ ) || defined( __x86_64__ )
    if( vlc_CPU_MMX() )
        i_accel |= MPEG2_ACCEL_X86_MMX;
    if( vlc_CPU_3dNOW() )
        i_accel |= MPEG2_ACCEL_X86_3DNOW;
    if( vlc_CPU_MMXEXT() )
        i_accel |= MPEG2_ACCEL_X86_MMXEXT;
#elif defined( __powerpc__ ) || defined( __ppc__ ) || defined( __ppc64__ )
    if( vlc_CPU_ALTIVEC() )
        i_accel |= MPEG2_ACCEL_PPC_ALTIVEC;

#elif defined(__arm__)
# ifdef MPEG2_ACCEL_ARM
    i_accel |= MPEG2_ACCEL_ARM;
# endif
# ifdef MPEG2_ACCEL_ARM_NEON
    if( vlc_CPU_ARM_NEON() )
        i_accel |= MPEG2_ACCEL_ARM_NEON;
# endif

    /* TODO: sparc */
#else
    /* If we do not know this CPU, trust libmpeg2's feature detection */
    i_accel = MPEG2_ACCEL_DETECT;

#endif

    /* Set CPU acceleration features */
    mpeg2_accel( i_accel );

    /* Initialize decoder */
    p_sys->p_mpeg2dec = mpeg2_init();
    if( p_sys->p_mpeg2dec == NULL)
    {
        msg_Err( p_dec, "mpeg2_init() failed" );
        free( p_sys );
        return VLC_EGENERIC;
    }

    p_sys->p_info = mpeg2_info( p_sys->p_mpeg2dec );

    p_dec->pf_decode = DecodeVideo;
    p_dec->pf_flush  = Reset;
    p_dec->fmt_out.i_codec = 0;

    return VLC_SUCCESS;
}

/*****************************************************************************
 * RunDecoder: the libmpeg2 decoder
 *****************************************************************************/
#ifdef __APPLE__
/* Callbacks de capture macrobloc appelés par mpeg2_slice() (libmpeg2 patché).
 * priv = le contexte backend DVDDriver. Images I/P/B frame-predicted capturées
 * (gate dans slice.c) → mb_type dérivé de macroblock_modes ci-dessous. */
static void HwMbBegin( void *priv, int macroblock_modes, unsigned cbp,
                       const int16_t *mv, const uint8_t *field_select )
{
    /* mb_type depuis macroblock_modes (constantes libmpeg2 : INTRA=1,
     * MOTION_BACKWARD=4, MOTION_FORWARD=8, MOTION_TYPE_SHIFT=6, MC_FIELD=1) :
     * intra→0 ; sinon fwd/bwd/bidir=1/2/3 (+4 si field-predicted). En phase 1
     * (MC_FRAME uniquement, cf. slice.c hw_capture) le +4 field ne survient pas. */
    int i_mb_type;
    if( macroblock_modes & 1 )
        i_mb_type = 0;                                   /* intra */
    else
    {
        int b_fwd = macroblock_modes & 8;
        int b_bwd = macroblock_modes & 4;
        i_mb_type = ( b_fwd && b_bwd ) ? 3 : b_fwd ? 1 : b_bwd ? 2 : 4;
        if( ( macroblock_modes >> 6 ) == 1 )            /* MC_FIELD */
            i_mb_type += 4;
    }
    /* Bit DCT_TYPE_INTERLACED (=32) → field-DCT (desc[0x15]) : sinon artefact
     * « peigne » sur le détail fin. */
    int i_dct_type = ( macroblock_modes & 32 ) ? 1 : 0;
    dvddriver_picture_mb_begin( priv, i_mb_type, i_dct_type,
                                dvddriver_cbp_from_libmpeg2( cbp ),
                                mv, field_select );
}
/* Capture run/level au fil de la VLD (slice.c du contrib) : quand elle est
 * armée, les paires (position zigzag, valeur) du bloc courant sont déjà prêtes
 * — plus de re-balayage des 64 positions du DCTblock (54 % du temps de
 * mpeg2_slice au PC-sampling sur G3). /tmp/hw_norl rétablit l'ancien chemin
 * pour l'A/B. */
extern int16_t mpeg2_hw_rl[68][2];
extern int     mpeg2_hw_rl_n;
extern int     mpeg2_hw_rl_on;
extern void    mpeg2_set_hw_rl( int on );
extern uint8_t mpeg2_scan_norm[64];

static void HwBlock( void *priv, const int16_t *dctblock, const uint8_t *scan )
{
    /* Les deux familles ATI n'ont pas le même contrat sur alternate_scan.
     * Le Rage 128, validé ainsi en 1.2.0, interprète toujours les positions
     * comme du zigzag classique : le chemin run/level capturé dans l'ordre du
     * flux n'est donc sûr que si le flux est déjà en zigzag, sinon il faut
     * relire DCTblock avec la table classique permutée par libmpeg2. Le RV200
     * accepte l'ordre réel du flux et conserve son chemin validé. */
    const bool b_fixed = dvddriver_uses_fixed_zigzag( priv );
    if( mpeg2_hw_rl_on && ( !b_fixed || scan == mpeg2_scan_norm ) )
        dvddriver_picture_mb_block_rl( priv, mpeg2_hw_rl, mpeg2_hw_rl_n );
    else
        dvddriver_picture_mb_block( priv, dctblock,
                                    b_fixed ? mpeg2_scan_norm : scan );
}
static void HwMbEnd( void *priv )
{
    dvddriver_picture_mb_end( priv );
}

/* U4 — CONTEXTE PICTURE (privé au décodeur). Attaché à chaque picture décodée sur
 * le GPU : identifie sa surface (out_idx) + la génération de cette surface au
 * submit. Le vout le présente via le callback HwPresentCallback (posté sur le bus
 * libvlc), sans jamais introspecter cette structure (opaque côté vout). */
#define HW_PIC_MAGIC 0x44564431u   /* 'DVD1' */
typedef struct
{
    picture_context_t ctx;      /* base VLC (destroy/copy) — DOIT être en 1er */
    uint32_t          magic;
    dvddriver_ctx    *hw;        /* indicatif ; le present utilise le device du bus */
    int               out_idx;
    unsigned          generation;
} hw_pic_context_t;

/* La surface GPU est RÉSERVÉE tant qu'un contexte la référence : VLC détruit le
 * contexte que la picture ait été affichée ou droppée, c'est donc le signal fiable
 * « le vout n'a plus besoin de cette surface ». */
static void HwPicCtxDestroy( picture_context_t *p )
{
    hw_pic_context_t *c = (hw_pic_context_t *)p;
    if( c->magic == HW_PIC_MAGIC && c->out_idx >= 0 )
        dvddriver_surface_release( c->hw, c->out_idx );
    free( p );
}
static picture_context_t *HwPicCtxCopy( picture_context_t *p )
{
    hw_pic_context_t *n = malloc( sizeof(*n) );
    if( n ) {
        *n = *(hw_pic_context_t *)p;
        if( n->out_idx >= 0 )
            dvddriver_surface_hold( n->hw, n->out_idx );  /* une réservation par copie */
    }
    return (picture_context_t *)n;
}
static picture_context_t *HwPicContextNew( dvddriver_ctx *hw, int out_idx )
{
    hw_pic_context_t *c = malloc( sizeof(*c) );
    if( c == NULL )
        return NULL;
    c->ctx.destroy = HwPicCtxDestroy;
    c->ctx.copy    = HwPicCtxCopy;
    c->magic       = HW_PIC_MAGIC;
    c->hw          = hw;
    c->out_idx     = out_idx;
    /* out_idx < 0 = contexte INVALIDE : picture que le GPU n'a pas décodée et
     * qu'il ne faut pas afficher (ses références logicielles sont vides en mode
     * remplacement). Aucune surface à réserver ni à présenter. */
    c->generation  = ( out_idx >= 0 ) ? dvddriver_surf_generation( hw, out_idx ) : 0;
    if( out_idx >= 0 )
        dvddriver_surface_hold( hw, out_idx );   /* libérée par HwPicCtxDestroy */
    return (picture_context_t *)c;
}
/* Callback posté sur DVDDRIVER_VAR_PRESENT : le vout l'appelle avec {device courant
 * (bus libvlc), picture->context}. Présente la surface si le contexte est un des
 * nôtres et sa génération est à jour. Renvoie true si c'était une picture HW. */
unsigned g_hw_cb_calls = 0;
static bool HwPresentCallback( dvddriver_ctx *hw, picture_context_t *pctx,
                               int wid, int x, int y, int w, int h )
{
    if( hw == NULL || pctx == NULL )
        return false;
    hw_pic_context_t *c = (hw_pic_context_t *)pctx;
    if( c->magic != HW_PIC_MAGIC )
        return false;
    /* Diagnostic : distingue « le vout n'appelle pas » de « on refuse ». */
    extern unsigned g_hw_cb_calls;
    g_hw_cb_calls++;
    (void) wid;   /* le suivi de fenêtre se fait par RÉOUVERTURE du décodeur
                   * (STATE_SEQUENCE) : ré-attacher la surface à chaud cassait
                   * définitivement la liaison décodeur→surface (écran noir même
                   * après retour en fenêtré). */
    if( c->out_idx < 0 )
        return true;   /* picture invalide : rien à présenter, on garde l'image */
    dvddriver_set_present_rect( hw, x, y, w, h );   /* suit la fenêtre VLC (no-op Carbon) */
    dvddriver_present_index_gen( hw, c->out_idx, c->generation );
    return true;
}

/* U4 — chemin A-idéal PAR DÉFAUT : lier la sortie HW à la FENÊTRE VLC (wid publié
 * par le vout en U1) plutôt qu'à une fenêtre Carbon séparée (validé en U2). On
 * peut forcer l'ancien chemin Carbon avec /tmp/hw_carbon=1 (A/B, debug). */
static bool HwForceCarbon( void )
{
    FILE *fw = fopen( "/tmp/hw_carbon", "r" );
    if( !fw )
        return false;
    int on = 0;
    if( fscanf( fw, "%d", &on ) != 1 )
        on = 0;
    fclose( fw );
    return on != 0;
}
/* Chantier PERF — le gate de résolution (HW_MAX_PIXELS_REALTIME) refuse le HW en
 * remplacement au-delà d'une résolution où le GPU tient le temps réel. /tmp/hw_force
 * (présent, quel que soit le contenu) le contourne pour les runs de bench / RE GPU. */
static bool HwForceResolution( void )
{
    FILE *fw = fopen( "/tmp/hw_force", "r" );
    if( !fw )
        return false;
    fclose( fw );
    return true;
}
/* Garde-fou fichier pour les expériences du chantier SP (absent = inactif). */
static bool HwGate( const char *path )
{
    FILE *f = fopen( path, "r" );
    if( !f )
        return false;
    fclose( f );
    return true;
}

/* wid de la fenêtre vout publié en U1 (0 si le vout n'a pas encore reshapé). */
static int HwVoutWid( decoder_t *p_dec )
{
    return (int) var_InheritInteger( p_dec, "dvddriver-vout-wid" );
}

/* Ouvre le contexte HW ATI aux dimensions du flux courant, branche les hooks de
 * capture de libmpeg2, et fixe le mode de décodage (i_replace : 0=additif/CPU
 * complet + capture GPU en //, 1=REMPLACEMENT = saute IDCT+MC CPU + fenêtre HW
 * plein écran). Échec → repli CPU silencieux (b_hwaccel désactivé). Retourne true
 * si le contexte HW est ouvert. Partagé par l'ouverture directe (toggle forcé) et
 * la validation de la sonde 2a. */
static bool HwOpenContext( decoder_t *p_dec, int i_replace )
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    const mpeg2_sequence_t *p_seq = p_sys->p_info->sequence;

    /* U4 — A-idéal par défaut : lier la surface à la fenêtre VLC (wid U1), sauf si
     * /tmp/hw_carbon force l'ancien chemin. 0 → fenêtre Carbon séparée. */
    int i_ext_wid = HwForceCarbon() ? 0 : HwVoutWid( p_dec );
    /* Chantier 3 : mode field (option privée avancée, remplace /tmp/field_exp). */
    int i_field = HwFieldMode( p_dec, p_sys->b_102mods );
    /* Chantier S — sous-titres/OSD par-dessus la surface HW. Possible UNIQUEMENT
     * sur le chemin U4 (surface liée à la fenêtre VLC) : la vue GL de VLC ne
     * recouvre pas la fenêtre Carbon séparée, elle ne peut donc rien y dessiner. */
    bool b_subs = var_InheritBool( p_dec, "mpeg2-hwaccel-subs" ) && i_ext_wid != 0;

    p_sys->p_hw = dvddriver_open( p_seq->width, p_seq->height,
                                  i_replace /* display_mode plein écran */,
                                  i_ext_wid /* wid fenêtre VLC (0=fenêtre Carbon) */,
                                  i_field   /* mode field (0=off/repli CPU) */,
                                  b_subs    /* sous-titres/OSD superposés */ );
    if( p_sys->p_hw == NULL )
    {
        /* ★ NE PAS abandonner définitivement : après un seek dvdnav le
         * décodeur est détruit/recréé et la NOUVELLE instance tente son
         * ouverture pendant que l'ancienne n'a pas fini de fermer
         * (s_dd_instances encore pris par les pictures en vol) → NULL une
         * fois. Mesuré : « ATI actif » restait à 1 sur toute la session et le
         * film continuait en CPU (le « ça lague après seek »). On retente aux
         * images I suivantes, avec un plafond pour les vrais échecs. */
        if( ++p_sys->i_hw_open_fails < 8 )
        {
            p_sys->b_hw_reopen = true;   /* nouvelle tentative à la prochaine I */
            msg_Dbg( p_dec, "ouverture décodeur HW ATI KO (essai %u) → "
                     "nouvelle tentative à la prochaine I", p_sys->i_hw_open_fails );
            return false;
        }
        p_sys->b_hwaccel = false;
        msg_Dbg( p_dec, "ouverture décodeur HW ATI KO → repli CPU" );
        return false;
    }
    p_sys->i_hw_width  = p_seq->width;
    p_sys->i_hw_height = p_seq->height;
    p_sys->i_hw_wid    = i_ext_wid;
    p_sys->i_hw_open_fails = 0;
    p_sys->i_hw_domain_gen = var_GetInteger( p_dec->obj.libvlc,
                                             "dvddriver-domain-gen" );
    /* Recouvrement VLD/Decode. Pas sous les modifications 10.2 : le pipeline
     * Jaguar a été validé en séquentiel, ne pas le déstabiliser. */
    {
        bool b_async = var_InheritBool( p_dec, "mpeg2-hwaccel-async" )
                    && !p_sys->b_102mods;
        p_sys->b_async = b_async;
        dvddriver_set_async( p_sys->p_hw, b_async );
        if( b_async )
            msg_Dbg( p_dec, "soumission GPU asynchrone active" );
    }
    {
        FILE *f = fopen( "/tmp/hw_norl", "r" );
        int b_rl = ( f == NULL );
        if( f != NULL ) fclose( f );
        mpeg2_set_hw_rl( b_rl );
        msg_Dbg( p_dec, "capture run/level dans la VLD : %s",
                 b_rl ? "active" : "désactivée (/tmp/hw_norl)" );
    }
    mpeg2_hwaccel_t hw = { p_sys->p_hw, HwMbBegin, HwBlock, HwMbEnd };
    mpeg2_hwaccel( p_sys->p_mpeg2dec, &hw );
    mpeg2_set_hw_replace( i_replace );
    /* U4 — publier le device + le callback de present sur le bus libvlc → le vout
     * présentera les surfaces (present piloté par le vout, ordre PTS). */
    /* Chantier S — publier AVANT le device/callback : le vout lit cette variable
     * au premier present matériel, qui ne peut avoir lieu qu'après ces deux-là. */
    var_SetBool( p_dec->obj.libvlc, DVDDRIVER_VAR_SUBS, b_subs );
    var_SetAddress( p_dec->obj.libvlc, DVDDRIVER_VAR_CTX,     p_sys->p_hw );
    /* Le nouveau contexte est publié : le vout peut se remettre à afficher. */
    var_SetBool( p_dec->obj.libvlc, DVDDRIVER_VAR_HOLD, false );
    var_SetAddress( p_dec->obj.libvlc, DVDDRIVER_VAR_PRESENT, (void *)HwPresentCallback );
    msg_Info( p_dec, "décodage MPEG-2 matériel ATI actif (%ux%u)%s%s%s",
              p_seq->width, p_seq->height,
              i_replace ? " — mode REMPLACEMENT" : " — mode additif",
              /* ⚠ ce que le backend a RETENU : il refuse le wid externe sur
               * les familles GPU qui n'affichent que dans leur propre fenêtre
               * (Rage 128). Annoncer i_ext_wid ici donnait un message FAUX. */
              dvddriver_uses_external_window( p_sys->p_hw )
                        ? " (surface sur la fenêtre VLC)"
                        : " (fenêtre Carbon séparée)",
              /* idem : l'incrustation exige la fenêtre VLC, donc elle tombe
               * avec elle quand le backend a gardé sa fenêtre Carbon. */
              ( b_subs && dvddriver_uses_external_window( p_sys->p_hw ) )
                        ? ", sous-titres/OSD superposés" : "" );
    /* Chantier SP — reconnaissance du plan subpicture matériel (lecture seule).
     * Objectif : savoir si les descripteurs renvoyés par DVDDriverGetSPBuffer
     * sont des adresses exploitables côté CPU ou des poignées GPU. */
    {
        uint32_t probe[16], keycolor = 0;
        if( dvddriver_sp_probe( p_sys->p_hw, probe, &keycolor ) )
        {
            msg_Info( p_dec, "plan subpicture matériel PRÉSENT — couleur-clé 0x%08x",
                      keycolor );
            msg_Info( p_dec, "  descripteurs SP [0x2F4] : %08x %08x %08x %08x "
                             "%08x %08x %08x %08x", probe[0], probe[1], probe[2],
                      probe[3], probe[4], probe[5], probe[6], probe[7] );
            msg_Info( p_dec, "  descripteurs SP [0x2D4] : %08x %08x %08x %08x "
                             "%08x %08x %08x %08x", probe[8], probe[9], probe[10],
                      probe[11], probe[12], probe[13], probe[14], probe[15] );
            uint32_t words[8];
            if( dvddriver_sp_first_words( p_sys->p_hw, words ) )
                msg_Info( p_dec, "  premier mot de chaque tampon : %08x %08x %08x "
                          "%08x %08x %08x %08x %08x", words[0], words[1], words[2],
                          words[3], words[4], words[5], words[6], words[7] );

            uint32_t oo[7];
            if( dvddriver_open_outputs( p_sys->p_hw, oo ) )
                msg_Info( p_dec, "  sorties OpenDevice : caps=%08x (bit1 %s) "
                          "dims=%08x,%08x,%08x,%08x five=%u eight=%u",
                          oo[0], (oo[0] & 2) ? "ARMÉ" : "absent",
                          oo[1], oo[2], oo[3], oo[4], oo[5], oo[6] );

            uint32_t st[5];
            if( dvddriver_sp_state( p_sys->p_hw, st ) )
                msg_Info( p_dec, "  état SP : mode[0x1FC]=%08x capacités[0x20]=%08x "
                          "(bit1 %s) ctx[0]=%08x tampon[0x1B0]=%08x enable[0x1C8]=%08x",
                          st[0], st[4], (st[4] & 2) ? "ARMÉ" : "absent",
                          st[1], st[2], st[3] );

            /* SP1 — accès en écriture. Fait ICI, avant le premier Decode. */
            if( HwGate( "/tmp/hw_sp_write" ) )
            {
                uint32_t back[2] = { 0, 0 };
                if( dvddriver_sp_write_test( p_sys->p_hw, 0, back ) )
                    msg_Info( p_dec, "SP1 écriture tampon 0 : relu %08x %08x "
                              "(attendu a5a5f00d 12345678)", back[0], back[1] );
                else
                    msg_Warn( p_dec, "SP1 : écriture impossible" );
            }
            /* SP2b — la séquence SP posée AVANT le premier Decode est peut-être
             * effacée par le décodage qui suit. On la rejoue alors une seule
             * fois, plus tard (compteur d'images), jamais par image. */
            p_sys->i_sp_replay = HwGate( "/tmp/hw_sp_late" ) ? 100 : 0;
            p_sys->i_sp_pulse  = HwGate( "/tmp/hw_sp_pulse" ) ? 20 : 0;
            p_sys->i_sp_tick   = 0;
            p_sys->i_sp_dest_left = 6;   /* six relevés espacés, lecture seule */
            p_sys->i_sp_dest_tick = 0;
            /* SP2 — premier affichage : bande pleine en bas de l'image. */
            if( HwGate( "/tmp/hw_sp_show" ) )
            {
                int rc[6] = { 0, 0, 0, 0, 0, 0 };
                if( dvddriver_sp_show_test( p_sys->p_hw, p_seq->width,
                                            p_seq->height, rc ) )
                {
                    msg_Info( p_dec, "SP2 affichage test : EnableSP=%d SetPalette=%d "
                              "ApplyDCSQ=%d SetSPBuffer=%d ShowSPBuffer=%d "
                              "(paquet %d octets)", rc[0], rc[1], rc[2], rc[3],
                              rc[4], rc[5] );
                    /* SP7 — contrôle de la géométrie effectivement posée dans le
                     * driver. Le pas de ligne DOIT être l'arrondi à 64 de la
                     * LARGEUR (768 en 720×576) ; s'il vaut la hauteur, le rect
                     * Mac { top, left, bottom, right } est encore transposé. */
                    uint32_t g[4];
                    if( dvddriver_sp_geometry( p_sys->p_hw, g ) )
                        msg_Info( p_dec, "  SP7 géométrie : destination=%08x "
                                  "largeur[0x410]=%u pas[0x414]=%u hauteur[0x418]=%u "
                                  "→ %s", g[0], g[1], g[2], g[3],
                                  ( g[2] == ( ( p_seq->width + 63 ) & ~63u ) )
                                      ? "COHÉRENT" : "TRANSPOSÉ" );
                    /* SP7b — quelle étape reste muette ? Empreintes = (mots non
                     * nuls << 16) | hachage, sur la source (bitmap 2 bits/px) et
                     * sur la destination (plan ARGB). */
                    uint32_t sg[6];
                    if( dvddriver_sp_stage_probes( p_sys->p_hw, sg ) )
                    {
                        msg_Info( p_dec, "  SP7b source  : avant ApplyDCSQ %08x → "
                                  "après %08x → RLE %s", sg[0], sg[1],
                                  sg[0] == sg[1] ? "NON DÉCODÉ" : "DÉCODÉ" );
                        msg_Info( p_dec, "  SP7b dest.   : avant SetSPBuffer %08x → "
                                  "après %08x → après ShowSPBuffer %08x → blit %s "
                                  "(drapeau[0x1D0] après SetSPBuffer = %u)",
                                  sg[2], sg[3], sg[4],
                                  ( sg[2] == sg[3] && sg[2] == sg[4] )
                                      ? "MUET" : "ÉCRIT", sg[5] );
                    }
                }
                else
                    msg_Warn( p_dec, "SP2 : préparation impossible" );
            }
        }
        else
            msg_Dbg( p_dec, "plan subpicture matériel indisponible" );
    }

    /* S5 — limitation documentée : sur le repli fenêtre Carbon, rien ne peut être
     * superposé. Prévenir explicitement plutôt que de laisser croire à un bug. */
    if( !i_ext_wid && var_InheritBool( p_dec, "mpeg2-hwaccel-subs" ) )
        msg_Warn( p_dec, "sortie matérielle en fenêtre Carbon séparée : "
                         "sous-titres et OSD NE SERONT PAS affichés" );
    return true;
}
#endif

static picture_t *DecodeBlock( decoder_t *p_dec, block_t **pp_block )
{
    decoder_sys_t   *p_sys = p_dec->p_sys;
    mpeg2_state_t   state;

    block_t *p_block;

    if( !pp_block || !*pp_block )
        return NULL;

    p_block = *pp_block;
    if( p_block->i_flags & (BLOCK_FLAG_CORRUPTED) )
        Reset( p_dec );

    while( 1 )
    {
        state = mpeg2_parse( p_sys->p_mpeg2dec );

        switch( state )
        {
        case STATE_SEQUENCE:
        {
            /* */
            DpbClean( p_dec );

            /* */
            mpeg2_custom_fbuf( p_sys->p_mpeg2dec, 1 );

            if( p_sys->p_synchro )
                decoder_SynchroRelease( p_sys->p_synchro );

            if( p_sys->p_info->sequence->frame_period <= 0 )
                p_sys->p_synchro = NULL;
            else
                p_sys->p_synchro =
                decoder_SynchroInit( p_dec, (uint32_t)(UINT64_C(1001000000) *
                                27 / p_sys->p_info->sequence->frame_period) );
            p_sys->b_after_sequence_header = true;

#ifdef __APPLE__
            /* Décodage matériel : décider comment le chemin HW s'engage maintenant
             * que les dimensions sont connues. Trois régimes (cf. 2a) :
             *   - toggle /tmp/hw_replace présent (0 ou 1) → mode FORCÉ hérité
             *     (ouverture directe, additif ou remplacement) pour l'A/B et le debug ;
             *   - absent → PROBE-THEN-COMMIT : on n'ouvre PAS le HW ici, on démarre en
             *     CPU pur et on observe le type de prédiction des P/B ; la décision
             *     (remplacement plein écran / CPU pur) est prise plus bas à une I-frame.
             * Changement de résolution en cours de flux (chaînage de titres) : le
             * contexte HW garde les dimensions d'ouverture → fermer, purger, et
             * RELANCER la sonde (le nouveau flux peut être d'un autre type). */
            int i_wid_now = HwVoutWid( p_dec );
            bool b_wid_changed = ( p_sys->p_hw != NULL && p_sys->i_hw_wid > 0
                                && i_wid_now > 0 && i_wid_now != p_sys->i_hw_wid );
            if( p_sys->p_hw != NULL
             && ( b_wid_changed
               || p_sys->p_info->sequence->width  != p_sys->i_hw_width
               || p_sys->p_info->sequence->height != p_sys->i_hw_height ) )
            {
                if( b_wid_changed )
                    msg_Dbg( p_dec, "fenêtre vidéo %d → %d (plein écran ?) : "
                             "réouverture du décodeur matériel",
                             p_sys->i_hw_wid, i_wid_now );
                else
                msg_Dbg( p_dec, "résolution HW %ux%u → %ux%u : réouverture décodeur",
                         p_sys->i_hw_width, p_sys->i_hw_height,
                         p_sys->p_info->sequence->width,
                         p_sys->p_info->sequence->height );
                mpeg2_hwaccel( p_sys->p_mpeg2dec, NULL );   /* décrocher les hooks */
                mpeg2_set_hw_replace( 0 );
                /* NULLer le bus AVANT close pour que le vout cesse de présenter. */
                var_SetAddress( p_dec->obj.libvlc, DVDDRIVER_VAR_CTX, NULL );
                { uint32_t iv[8], n = 0;
          dvddriver_present_intervals( p_sys->p_hw, iv, &n );
          if( n > 0 )
              msg_Info( p_dec, "cadence de présentation (%u images) : <25ms=%u "
                        "<33=%u <37=%u <43=%u <50=%u <60=%u <100=%u >=100=%u",
                        n, iv[0], iv[1], iv[2], iv[3], iv[4], iv[5], iv[6], iv[7] ); }
        dvddriver_close( p_sys->p_hw );
                p_sys->p_hw = NULL;
                p_sys->b_hw_picture = false;
                p_sys->b_hw_committed = false;   /* relancer la sonde sur le nouveau flux */
                p_sys->i_probe_pb = p_sys->i_probe_field = p_sys->i_probe_pics = 0;
                p_sys->i_probe_defers = 0;
            }
            if( p_sys->b_hwaccel && p_sys->p_hw == NULL && !p_sys->b_hw_committed )
            {
                /* U5 : plus de toggle /tmp/hw_replace — le probe-then-commit (2a)
                 * est le SEUL chemin. On démarre en CPU pur et on décide à une
                 * I-frame (STATE_PICTURE) : progressif → HW remplacement sur la
                 * fenêtre VLC ; entrelacé → 100 % CPU. L'activation globale se fait
                 * par l'option mpeg2-hwaccel (déjà lue à l'OpenDecoder). */
                p_sys->b_hw_probe = true;
                p_sys->i_probe_pb = p_sys->i_probe_field = p_sys->i_probe_pics = 0;
                msg_Dbg( p_dec, "décodage matériel : sonde progressif/entrelacé "
                                "(CPU pur, décision à la prochaine I après ~%u P/B)",
                         HW_PROBE_MIN_PB );
            }
#endif

            /* Set the first 2 reference frames */
            GetAR( p_dec );
            for( int i = 0; i < 2; i++ )
            {
                picture_t *p_picture = DpbNewPicture( p_dec );
                if( !p_picture )
                {
                    Reset( p_dec );
                    block_Release( p_block );
                    return NULL;
                }
                PutPicture( p_dec, p_picture );
            }
            break;
        }

        case STATE_GOP:
            /* There can be userdata in a GOP. It needs to be remembered for the next picture. */
            if( p_sys->p_info->user_data_len > 2 )
            {
                free( p_sys->p_gop_user_data );
                p_sys->p_gop_user_data = calloc( p_sys->p_info->user_data_len, sizeof(uint8_t) );
                if( p_sys->p_gop_user_data )
                {
                    p_sys->i_gop_user_data = p_sys->p_info->user_data_len;
                    memcpy( p_sys->p_gop_user_data, p_sys->p_info->user_data, p_sys->p_info->user_data_len );
                }
            }
            break;

        case STATE_PICTURE:
        {
            const mpeg2_info_t *p_info = p_sys->p_info;
            const mpeg2_picture_t *p_current = p_info->current_picture;

            vlc_tick_t i_pts, i_dts;

            if( p_sys->b_after_sequence_header &&
                (p_current->flags &
                    PIC_MASK_CODING_TYPE) == PIC_FLAG_CODING_TYPE_P )
            {
                /* Intra-slice refresh. Simulate a blank I picture. */
                msg_Dbg( p_dec, "intra-slice refresh stream" );
                decoder_SynchroNewPicture( p_sys->p_synchro,
                                           I_CODING_TYPE, 2, 0, 0,
                                           p_info->sequence->flags & SEQ_FLAG_LOW_DELAY );
                decoder_SynchroDecode( p_sys->p_synchro );
                decoder_SynchroEnd( p_sys->p_synchro, I_CODING_TYPE, 0 );
                p_sys->b_slice_i = true;
            }
            p_sys->b_after_sequence_header = false;

#ifdef __APPLE__
            /* ★ SUIVI DE LA FENÊTRE D'AFFICHAGE (bascule plein écran ⇄ fenêtré).
             * L'interface legacy déplace la vue vidéo dans une AUTRE fenêtre ; la
             * surface, elle, reste liée à celle capturée à l'ouverture → écran
             * noir. La ré-attache à chaud de la surface a été essayée et casse
             * DÉFINITIVEMENT la liaison décodeur→surface (cf. dvddriver_bind_window)
             * : le seul moyen fiable est de ROUVRIR le décodeur sur la nouvelle
             * fenêtre. On le fait à une image I, qui ne référence rien — aucune
             * référence matérielle à reconstituer.
             * ⚠ Ce test était auparavant placé au STATE_SEQUENCE : il n'y était
             * JAMAIS atteint en cours de lecture, car libmpeg2 signale les en-têtes
             * de séquence identiques par STATE_SEQUENCE_REPEATED (non traité ici) —
             * d'où un plein écran toujours noir. */
            /* ★ BUG A — changement de domaine dvdnav (MENU→FILM) : signalé par
             * le demux via la génération sur le bus (aucune discontinuité de
             * bloc, horodatages continus). Un matériel ouvert sur le MENU
             * dédouble le film : renaissance, même mécanique que le flush. */
            /* ★ AUTO-RENAISSANCE RETIRÉE (29/07 midi) : mesuré à
             * l'instrumentation PRESENT split, le premier engagement est SAIN
             * (flush ~1,4-2 ms par present) et c'est toute RÉOUVERTURE en cours
             * de lecture qui atterrit en mode de composition cassé (flush
             * ~420 µs, images mêlées à l'écran) — la renaissance « équivalent
             * seek » CAUSAIT donc le scintillement qu'elle devait réparer.
             * Règle : ne JAMAIS fermer/rouvrir le matériel en cours de lecture
             * sans nécessité (le suivi de fenêtre reste le seul cas légitime). */
            if( p_sys->p_hw != NULL )
            {
                int64_t gen = var_GetInteger( p_dec->obj.libvlc,
                                              "dvddriver-domain-gen" );
                if( gen != p_sys->i_hw_domain_gen )
                {
                    /* ★ Plus de fermeture/réouverture ici (29/07 midi, cf.
                     * Reset()) : gel des références jusqu'à la prochaine I. */
                    msg_Dbg( p_dec, "changement de domaine dvdnav : références "
                             "matérielles périmées, gel jusqu'à la prochaine I" );
                    p_sys->b_hw_picture = false;
                    p_sys->b_hw_stale = true;
                    p_sys->i_hw_domain_gen = gen;
                }
            }
            /* Réouverture différée demandée au changement de fenêtre : on la fait
             * à l'image I suivante (ce test est AVANT la détection ci-dessous,
             * sinon il se déclencherait sur l'image même où l'on vient de fermer). */
            if( p_sys->b_hw_reopen && p_sys->p_hw == NULL
             && (p_current->flags & PIC_MASK_CODING_TYPE) == PIC_FLAG_CODING_TYPE_I )
            {
                p_sys->b_hw_reopen = false;
                HwOpenContext( p_dec, 1 /*remplacement*/ );
            }
            if( p_sys->p_hw != NULL
             && (p_current->flags & PIC_MASK_CODING_TYPE) == PIC_FLAG_CODING_TYPE_I )
            {
                int i_wid_now = HwVoutWid( p_dec );
                if( i_wid_now > 0 && p_sys->i_hw_wid > 0
                 && i_wid_now != p_sys->i_hw_wid )
                {
                    msg_Dbg( p_dec, "fenêtre vidéo %d → %d : réouverture du "
                             "décodeur matériel sur la nouvelle fenêtre",
                             p_sys->i_hw_wid, i_wid_now );
                    mpeg2_hwaccel( p_sys->p_mpeg2dec, NULL );
                    mpeg2_set_hw_replace( 0 );
                    /* Suspendre l'affichage AVANT de dépublier le contexte :
                     * les pictures déjà en file chez le vout portent encore un
                     * contexte matériel mais ne pourront plus être présentées. */
                    /* ⚠ Regatée derrière 102mods le 2026-07-29 : dé-gater HOLD +
                     * rejet de réouverture n'a PAS réparé la bascule plein écran
                     * sur 10.3 et a coïncidé avec un retour du scintillement en
                     * fenêtré. État connu-bon = gates d'origine. La bascule
                     * plein écran reste un chantier ouvert (cf. mémoire). */
                    if( p_sys->b_102mods )
                        var_SetBool( p_dec->obj.libvlc, DVDDRIVER_VAR_HOLD, true );
                    var_SetAddress( p_dec->obj.libvlc, DVDDRIVER_VAR_CTX, NULL );
                    dvddriver_close( p_sys->p_hw );
                    p_sys->p_hw = NULL;
                    p_sys->b_hw_picture = false;
                    p_sys->b_hw_stale = false;
                    /* ⚠ NE PAS rouvrir ICI. Fermer puis rouvrir le device dans le
                     * MÊME appel (DVDTerminateLibrary suivi d'un DVDInitializeLibrary,
                     * pendant que le vout tient encore des surfaces) GÈLE VLC :
                     * l'input ne s'arrête plus (« stopping current input » en
                     * boucle), process en état S, quit impossible. On repasse donc
                     * par le chemin NORMAL, déjà éprouvé : relancer la sonde, qui
                     * rouvrira le décodeur à une prochaine image I — quelques
                     * dixièmes de seconde de décodage logiciel, puis le matériel
                     * reprend sur la bonne fenêtre. */
                    /* Le type de flux est déjà connu : pas de nouvelle sonde, on
                     * rouvre simplement à l'image I suivante (cf. b_hw_reopen).
                     * ⚠ Ne pas repasser par la sonde en remettant b_hw_committed à
                     * false : elle n'est armée qu'au STATE_SEQUENCE, jamais atteint
                     * en cours de lecture (STATE_SEQUENCE_REPEATED) — le décodeur
                     * restait alors en CPU pur définitivement (CPU à 100 %). */
                    p_sys->b_hw_reopen = true;
                }
            }
#endif

#ifdef __APPLE__
            /* 2a — SONDE progressif/entrelacé. On observe le type de prédiction de
             * la picture COURANTE au niveau header (mpeg2_pic_field_predicted, fiable
             * même si la picture est ensuite droppée). À une I-frame, une fois assez
             * de P/B observées, on tranche UNE fois :
             *   - < seuil de field-prediction → progressif → ouvrir le HW en
             *     REMPLACEMENT plein écran DÈS CETTE I (elle devient la 1re réf HW) ;
             *   - >= seuil → entrelacé → NE PAS ouvrir le HW, rester 100 % CPU. */
            if( p_sys->b_hw_probe && !p_sys->b_hw_committed )
            {
                int i_ct = p_current->flags & PIC_MASK_CODING_TYPE;
                bool b_is_i = ( i_ct == PIC_FLAG_CODING_TYPE_I );
                if( i_ct == PIC_FLAG_CODING_TYPE_P ||
                    i_ct == PIC_FLAG_CODING_TYPE_B )
                {
                    p_sys->i_probe_pb++;
                    if( mpeg2_pic_field_predicted( p_sys->p_mpeg2dec ) )
                        p_sys->i_probe_field++;
                }
                p_sys->i_probe_pics++;

                /* Décider TOUJOURS à une I (frontière de GOP = réfs propres, et le
                 * HW démarre forcément sur une I) : soit on a vu assez de P/B pour
                 * juger la field-prediction, soit le plafond de pictures est atteint
                 * (flux tout-I : i_probe_pb=0 → pct=0 → progressif). Un flux sans
                 * aucune I reste en sonde/CPU (correct) — le HW ne pourrait pas
                 * démarrer sans I de toute façon. */
                /* ★★★ MENU DVD : TRANCHER DÈS LA PREMIÈRE I.
                 * Un menu FIXE ne produit AUCUNE image P ou B — la sonde ne peut
                 * donc jamais atteindre son quota, et le contexte matériel ne
                 * s'ouvre jamais. Un repli temporel ne servirait à rien non plus :
                 * ce code ne s'exécute qu'à l'ARRIVÉE d'une image, et sur un menu
                 * fixe il n'en arrive plus.
                 * Conséquence mesurée (Chihiro, menus fixes) : 0 décodage
                 * matériel, et le module de sous-titres — qui prend désormais la
                 * piste dans les menus — attendait un contexte qui ne venait pas.
                 * Plus aucune surbrillance, là où le rendu logiciel s'en chargeait
                 * avant. C'est cette régression que l'on corrige ici.
                 * Le verdict de field est alors sans objet (aucune P/B mesurée) :
                 * on retient ENTRELACÉ, qui est de toute façon ce que mesurent les
                 * menus animés et qui ouvre le contexte en mode remplacement. */
                const bool b_menus =
                    ( p_dec->obj.parent != NULL
                      && var_Type( p_dec->obj.parent, "highlight" ) != 0 );
                bool b_enough = b_is_i
                             && ( b_menus
                               || p_sys->i_probe_pb  >= HW_PROBE_MIN_PB
                               || p_sys->i_probe_pics >= HW_PROBE_MAX_PICS );
                /* U4/A-idéal : on veut lier la surface à la fenêtre VLC (défaut).
                 * Course réelle : le commit décodeur peut précéder le 1er reshape
                 * du vout → wid pas encore publié. DIFFÉRER le commit (rester en
                 * sonde/CPU, lecture correcte) jusqu'à ce que le wid soit dispo —
                 * borné par HW_MAX_COMMIT_DEFERS pour retomber sur la fenêtre Carbon
                 * si le vout ne vient jamais (cas sans affichage). */
                /* ★★ MENU FIXE : ATTENDRE LE WID, NE PAS LE REPORTER.
                 * Le report ci-dessous compte sur une PROCHAINE image I pour
                 * retenter — hypothèse fausse sur un menu fixe, où il n'en vient
                 * plus aucune : le commit n'avait alors jamais lieu et le
                 * contexte matériel ne s'ouvrait pas (mesuré sur les menus fixes
                 * de Chihiro : sonde conclue, puis « commit différé (1/4) », et
                 * plus rien). On attend donc le wid ICI, brièvement et une seule
                 * fois. Coût nul en lecture normale : on n'y entre que si le wid
                 * manque encore, ce qui ne dure que le temps du premier reshape
                 * du vout. */
                if( b_enough && b_menus && !HwForceCarbon()
                 && HwVoutWid( p_dec ) == 0 )
                {
                    for( unsigned i = 0; i < 25 && HwVoutWid( p_dec ) == 0; i++ )
                        msleep( 20000 );
                    if( HwVoutWid( p_dec ) != 0 )
                        msg_Dbg( p_dec, "menu DVD : wid du vout obtenu après "
                                        "attente — commit immédiat" );
                }
                if( b_enough && !HwForceCarbon() && HwVoutWid( p_dec ) == 0
                 && p_sys->i_probe_defers < HW_MAX_COMMIT_DEFERS )
                {
                    p_sys->i_probe_defers++;
                    msg_Dbg( p_dec, "U4 : vout wid pas encore publié → commit différé "
                                    "(%u/%u)", p_sys->i_probe_defers, HW_MAX_COMMIT_DEFERS );
                    b_enough = false;
                }
                if( b_enough )
                {
                    unsigned pct = p_sys->i_probe_pb
                        ? ( p_sys->i_probe_field * 100u ) / p_sys->i_probe_pb : 0;
                    bool b_field = b_menus || ( pct >= HW_PROBE_FIELD_PCT );
                    msg_Info( p_dec, "décodage matériel : sonde terminée — %u/%u P/B "
                              "field-predicted (%u%%) → flux %s",
                              p_sys->i_probe_field, p_sys->i_probe_pb, pct,
                              b_field ? "ENTRELACÉ" : "PROGRESSIF" );
                    p_sys->b_hw_probe = false;
                    p_sys->b_hw_committed = true;
                    /* GATE DE RÉSOLUTION : le décodeur ATI est un décodeur DVD ; on
                     * refuse ce qui dépasse (MPEG-2 HD) et on reste 100 % CPU.
                     * /tmp/hw_force contourne (bench / RE GPU). */
                    unsigned i_px = p_sys->p_info->sequence->width
                                  * p_sys->p_info->sequence->height;
                    if( i_px > HW_MAX_PIXELS_REALTIME && !HwForceResolution() )
                    {
                        msg_Info( p_dec, "décodage matériel : résolution %ux%u "
                                  "(%u px) > seuil temps réel GPU (%u px) → repli "
                                  "100 %% CPU (le HW droppe à cette résolution ; "
                                  "/tmp/hw_force pour forcer)",
                                  p_sys->p_info->sequence->width,
                                  p_sys->p_info->sequence->height, i_px,
                                  HW_MAX_PIXELS_REALTIME );
                        p_sys->b_hwaccel = false;
                    }
                    else if( b_field )
                    {
                        /* Entrelacé (le cas du DVD réel). mpeg2-hwaccel-field>0
                         * (défaut 2) → on ouvre le HW en remplacement sur cette I ;
                         * le mode field est passé au backend par HwOpenContext.
                         * Validé sur DVD PAL entrelacé : image propre à 5,4 ms/pic.
                         * =0 → l'entrelacé reste 100 % CPU (échappatoire si une
                         * source à vrai mouvement par champ déchire). */
                        int i_field = HwFieldMode( p_dec, p_sys->b_102mods );
                        if( i_field > 0 && b_is_i )
                        {
                            msg_Info( p_dec, "décodage matériel : entrelacé accéléré "
                                      "(mode field %d) — mode REMPLACEMENT", i_field );
                            HwOpenContext( p_dec, 1 /*remplacement*/ );
                        }
                        else if( !b_is_i )
                            ;   /* attendre la prochaine I pour ouvrir */
                        else
                        {
                            msg_Info( p_dec, "décodage matériel : flux entrelacé et "
                                      "mpeg2-hwaccel-field=0 → décodage 100 %% CPU" );
                            p_sys->b_hwaccel = false;
                        }
                    }
                    else if( b_is_i )
                    {
                        /* Progressif : ouvrir en remplacement plein écran. Cette I
                         * est capturée dès maintenant (begin ci-dessous) et devient
                         * la 1re référence HW. Échec d'open → repli CPU (dans le
                         * helper). */
                        HwOpenContext( p_dec, 1 /*remplacement*/ );
                    }
                }
            }

            /* Décodage matériel : démarrer l'assemblage d'une picture (I, P ou B
             * frame-predicted ; le gate final est dans slice.c). Les macroblocs
             * seront accumulés par les hooks pendant le mpeg2_parse suivant, puis
             * soumis au STATE_SLICE. */
            if( p_current->flags & PIC_FLAG_PROGRESSIVE_FRAME )
                p_sys->i_pic_prog++;
            else
                p_sys->i_pic_inter++;
            if( p_current->nb_fields == 2 )      p_sys->i_fields_2++;
            else if( p_current->nb_fields == 3 ) p_sys->i_fields_3++;

            p_sys->b_hw_picture = false;
            if( p_sys->p_hw != NULL && !p_sys->b_hw_giveup )
            {
                int i_ct = p_current->flags & PIC_MASK_CODING_TYPE;
                int i_coding = ( i_ct == PIC_FLAG_CODING_TYPE_I ) ? 1
                             : ( i_ct == PIC_FLAG_CODING_TYPE_P ) ? 2
                             : ( i_ct == PIC_FLAG_CODING_TYPE_B ) ? 3
                             : 0;   /* seuls I/P/B capturés (frame-predicted) */
                if( i_coding != 0 )
                {
                    const mpeg2_sequence_t *p_seq = p_sys->p_info->sequence;
                    unsigned nb_mbs = ((p_seq->width  + 15) / 16)
                                    * ((p_seq->height + 15) / 16);
                    /* begin pour I et P ; si la picture n'est finalement pas
                     * capturée par slice.c (P non frame-predicted, field), submit
                     * détecte mb_index != nb_mbs et saute proprement. */
                    {
                        struct timeval tv0;
                        gettimeofday( &tv0, NULL );
                        p_sys->i_hw_pic_t0 =
                            (unsigned long) tv0.tv_sec * 1000000UL + tv0.tv_usec;
                    }
                    if( dvddriver_picture_begin( p_sys->p_hw, i_coding, 3 /*frame*/,
                                                 nb_mbs ) == 0 )
                        p_sys->b_hw_picture = true;
                }
            }
#endif

#ifdef PIC_FLAG_PTS
            i_pts = p_current->flags & PIC_FLAG_PTS ?
                ( ( p_current->pts ==
                    (uint32_t)p_sys->i_current_pts ) ?
                  p_sys->i_current_pts : p_sys->i_previous_pts ) : 0;
            i_dts = 0;

            /* Hack to handle demuxers which only have DTS timestamps */
            if( !i_pts && !p_block->i_pts && p_block->i_dts > 0 )
            {
                if( p_info->sequence->flags & SEQ_FLAG_LOW_DELAY ||
                    (p_current->flags &
                      PIC_MASK_CODING_TYPE) == PIC_FLAG_CODING_TYPE_B )
                {
                    i_pts = p_block->i_dts;
                }
            }
            p_block->i_pts = p_block->i_dts = 0;
            /* End hack */

#else /* New interface */

            i_pts = p_current->flags & PIC_FLAG_TAGS ?
                ( ( p_current->tag == (uint32_t)p_sys->i_current_pts ) ?
                            p_sys->i_current_pts : p_sys->i_previous_pts ) : 0;
            i_dts = p_current->flags & PIC_FLAG_TAGS ?
                ( ( p_current->tag2 == (uint32_t)p_sys->i_current_dts ) ?
                            p_sys->i_current_dts : p_sys->i_previous_dts ) : 0;
#endif

            /* If nb_fields == 1, it is a field picture, and it will be
             * followed by another field picture for which we won't call
             * decoder_SynchroNewPicture() because this would have other
             * problems, so we take it into account here.
             * This kind of sucks, but I didn't think better. --Meuuh
             */
            decoder_SynchroNewPicture( p_sys->p_synchro,
                                       p_current->flags & PIC_MASK_CODING_TYPE,
                                       p_current->nb_fields == 1 ? 2 :
                                       p_current->nb_fields, i_pts, i_dts,
                                       p_info->sequence->flags & SEQ_FLAG_LOW_DELAY );


            picture_t *p_pic;

            if( p_dec->b_frame_drop_allowed && !p_sys->b_preroll &&
                !(p_sys->b_slice_i
                   && ((p_current->flags
                         & PIC_MASK_CODING_TYPE) == PIC_FLAG_CODING_TYPE_P))
                   && !decoder_SynchroChoose( p_sys->p_synchro,
                              p_current->flags
                                & PIC_MASK_CODING_TYPE,
                              /*p_sys->p_vout->render_time*/ 0 /*FIXME*/,
                              p_info->sequence->flags & SEQ_FLAG_LOW_DELAY ) )
                p_pic = NULL;
            else
            {
                p_pic = DpbNewPicture( p_dec );
                if( !p_pic )
                {
                    Reset( p_dec );

                    p_pic = DpbNewPicture( p_dec );
                    if( !p_pic )
                    {
                        mpeg2_reset( p_sys->p_mpeg2dec, 1 );
                        block_Release( p_block );
                        return NULL;
                    }
                }
            }

            mpeg2_skip( p_sys->p_mpeg2dec, p_pic == NULL );
            p_sys->b_skip = p_pic == NULL;
#ifdef __APPLE__
            /* Picture sautée par le synchro : libmpeg2 ne décodera pas ses
             * slices, donc aucun macrobloc n'arrivera aux hooks. La soumettre
             * quand même produisait un DVDDriverDecode rc=-2 [0/nb_mbs] et lui
             * attachait un contexte matériel invalide — 174 fois sur 1208
             * pictures en 45 s, presque toutes des B. Rien à décoder, rien à
             * afficher : on désarme la picture matérielle. (Les B ne servent de
             * référence à personne, la chaîne GPU reste intacte.)
             * ⚠ Dé-gaté de b_102mods le 29/07 : gaté Jaguar-seulement lors du
             * rollback en bloc des 102mods, alors que ce désarmement est
             * bénéfique PARTOUT. Sans lui, la B sautée passe quand même par la
             * soumission et ATTEND ~70 ms une surface libre qu'elle n'utilisera
             * jamais (mesuré Panther, wait=48-73 ms sur chaque rc=-2) : jeter
             * une image COÛTE plus qu'elle n'économise, d'où le cycle verrouillé
             * « une B sur deux jetée » (cadence bimodale 40/80 ms perçue comme
             * un dédoublement) dont seul un seek sortait. */
            if( p_sys->b_skip )
                p_sys->b_hw_picture = false;
#endif
            if( p_pic != NULL )
                decoder_SynchroDecode( p_sys->p_synchro );
            else
                decoder_SynchroTrash( p_sys->p_synchro );

            PutPicture( p_dec, p_pic );

            if( p_info->user_data_len > 2 || p_sys->i_gop_user_data > 2 )
            {
                p_sys->i_cc_pts = i_pts;
                p_sys->i_cc_dts = i_dts;
                if( (p_current->flags
                             & PIC_MASK_CODING_TYPE) == PIC_FLAG_CODING_TYPE_P )
                    p_sys->i_cc_flags = BLOCK_FLAG_TYPE_P;
                else if( (p_current->flags
                             & PIC_MASK_CODING_TYPE) == PIC_FLAG_CODING_TYPE_B )
                    p_sys->i_cc_flags = BLOCK_FLAG_TYPE_B;
                else p_sys->i_cc_flags = BLOCK_FLAG_TYPE_I;
#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)
                bool b_top_field_first = p_sys->p_info->current_picture->flags
                                           & PIC_FLAG_TOP_FIELD_FIRST;
#endif
                if( p_sys->i_gop_user_data > 2 )
                {
                    /* We now have picture info for any cached user_data out of the gop */
#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)
                    cc_ProbeAndExtract( &p_sys->cc, b_top_field_first,
                                &p_sys->p_gop_user_data[0], p_sys->i_gop_user_data );
#endif
                    p_sys->i_gop_user_data = 0;
                }

                /* Extract the CC from the user_data of the picture */
#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)
                if( p_info->user_data_len > 2 )
                    cc_ProbeAndExtract( &p_sys->cc, b_top_field_first,
                                &p_info->user_data[0], p_info->user_data_len );

                if( p_sys->cc.i_data )
                    SendCc( p_dec );
#endif
            }
        }
        break;


        case STATE_BUFFER:
            if( !p_block->i_buffer )
            {
                block_Release( p_block );
                return NULL;
            }

#ifdef __APPLE__
            /* ★ DISCONTINUITÉ (cellule/domaine dvdnav) : comme au flush, NE PAS
             * fermer le matériel (29/07 midi — toute réouverture en cours de
             * lecture atterrit en composition cassée, cf. Reset()). Références
             * périmées → gel jusqu'à la prochaine I. */
            if( (p_block->i_flags & BLOCK_FLAG_DISCONTINUITY)
             && p_sys->p_hw != NULL )
            {
                msg_Dbg( p_dec, "discontinuité : références matérielles "
                         "périmées, gel jusqu'à la prochaine I" );
                p_sys->b_hw_picture = false;
                p_sys->b_hw_stale = true;
            }
#endif
            if( (p_block->i_flags & (BLOCK_FLAG_DISCONTINUITY
                                      | BLOCK_FLAG_CORRUPTED)) &&
                p_sys->p_synchro &&
                p_sys->p_info->sequence &&
                p_sys->p_info->sequence->width != (unsigned)-1 )
            {
                decoder_SynchroReset( p_sys->p_synchro );
                if( p_sys->p_info->current_fbuf != NULL &&
                    p_sys->p_info->current_fbuf->id != NULL )
                {
                    p_sys->b_garbage_pic = true;
                }
                if( p_sys->b_slice_i )
                {
                    decoder_SynchroNewPicture( p_sys->p_synchro,
                                               I_CODING_TYPE, 2, 0, 0,
                                               p_sys->p_info->sequence->flags &
                                                            SEQ_FLAG_LOW_DELAY );
                    decoder_SynchroDecode( p_sys->p_synchro );
                    decoder_SynchroEnd( p_sys->p_synchro, I_CODING_TYPE, 0 );
                }
#ifdef __APPLE__
                /* ★ BUG A (dédoublement via les menus DVD) : la frontière
                 * menu→film sans flush laisse l'association horodatage→picture
                 * (mpeg2_tag_picture) décalée d'une picture pour tout le film —
                 * chaque image porte la date de sa voisine, ±40 ms de
                 * va-et-vient invisible aux compteurs. Un seek répare parce que
                 * Reset() fait mpeg2_reset(,0)+DpbClean ; faire pareil ici,
                 * seule cette resynchronisation manquait au chemin
                 * discontinuité. Coût : au pire un GOP re-sondé (chaque GOP DVD
                 * porte un en-tête de séquence). */
                if( p_block->i_flags & BLOCK_FLAG_DISCONTINUITY )
                {
                    msg_Dbg( p_dec, "discontinuité : resynchronisation du "
                             "tagging PTS (mpeg2_reset léger + DpbClean)" );
                    mpeg2_reset( p_sys->p_mpeg2dec, 0 );
                    DpbClean( p_dec );
                }
#endif
            }

            if( p_block->i_flags & BLOCK_FLAG_PREROLL )
            {
                p_sys->b_preroll = true;
            }
            else if( p_sys->b_preroll )
            {
                p_sys->b_preroll = false;
                if( p_sys->p_synchro )
                    decoder_SynchroReset( p_sys->p_synchro );
            }

#ifdef PIC_FLAG_PTS
            if( p_block->i_pts )
            {
                mpeg2_pts( p_sys->p_mpeg2dec, (uint32_t)p_block->i_pts );

#else /* New interface */
            if( p_block->i_pts || p_block->i_dts )
            {
                mpeg2_tag_picture( p_sys->p_mpeg2dec,
                                   (uint32_t)p_block->i_pts,
                                   (uint32_t)p_block->i_dts );
#endif
#ifdef __APPLE__
                /* ★ BUG A (dédoublement via les menus DVD) : le passage
                 * MENU→FILM de dvdnav ne redémarre PAS le décodeur et n'émet
                 * AUCUNE discontinuité de bloc — mais il SAUTE d'horloge (le
                 * film repart sur une base de temps différente du menu). Un
                 * décodeur matériel ouvert sur le contenu du MENU tisse alors
                 * des champs croisés pour tout le film (sonde et mode field
                 * décidés sur le menu). Détecter le saut ici et faire renaître
                 * le matériel à la prochaine image I — même mécanique que le
                 * flush, validée : après un seek, l'image redevient nette.
                 * Seuil 2 s : les PTS d'un flux continu avancent d'un pas
                 * d'image ; un vrai changement de domaine saute largement plus.
                 * Coût d'un faux positif : une renaissance (≈ 1 GOP en CPU). */
                if( p_sys->p_hw != NULL && p_block->i_dts
                 && p_sys->i_current_dts )
                {
                    vlc_tick_t d = p_block->i_dts - p_sys->i_current_dts;
                    if( d < -CLOCK_FREQ * 2 || d > CLOCK_FREQ * 2 )
                    {
                        /* ★ Plus de fermeture/réouverture (29/07 midi, cf.
                         * Reset()) : gel jusqu'à la prochaine I. */
                        msg_Dbg( p_dec, "saut d'horloge (%lld ms) : références "
                                 "matérielles périmées, gel jusqu'à la prochaine I",
                                 (long long)( d / 1000 ) );
                        p_sys->b_hw_picture = false;
                        p_sys->b_hw_stale = true;
                    }
                }
#endif
                p_sys->i_previous_pts = p_sys->i_current_pts;
                p_sys->i_current_pts = p_block->i_pts;
                p_sys->i_previous_dts = p_sys->i_current_dts;
                p_sys->i_current_dts = p_block->i_dts;
            }

            mpeg2_buffer( p_sys->p_mpeg2dec, p_block->p_buffer,
                          p_block->p_buffer + p_block->i_buffer );

            p_block->i_buffer = 0;
            break;

#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)

        case STATE_SEQUENCE_MODIFIED:
            GetAR( p_dec );
            break;
#endif
        case STATE_PICTURE_2ND:
            p_sys->b_second_field = true;
            break;


        case STATE_INVALID_END:
        case STATE_END:
        case STATE_SLICE:
        {
            picture_t *p_pic = NULL;

#ifdef __APPLE__
            /* SP5b — la destination du blit subpicture se renseigne-t-elle en
             * cours de lecture ? Simple lecture, quelques fois, espacées. */
            if( p_sys->i_sp_dest_left > 0 && ++p_sys->i_sp_dest_tick >= 25 )
            {
                p_sys->i_sp_dest_tick = 0;
                p_sys->i_sp_dest_left--;
                uint32_t pr[3][8];
                int np = dvddriver_sp_dest_probes( p_sys->p_hw, pr );
                msg_Info( p_dec, "SP5b destination ctx[0x204] = %08x (%d relevés)",
                          dvddriver_sp_dest( p_sys->p_hw ), np );
                for( int k = 0; k < np; k++ )
                    msg_Info( p_dec, "  Show #%d : empreinte 64 Ko avant %08x "
                              "après %08x → %s", k, pr[k][0], pr[k][4],
                              pr[k][0] == pr[k][4] ? "INCHANGÉ (le blit ne "
                              "s'exécute pas)" : "MODIFIÉ (le blit écrit)" );
            }
            /* SP2c — l'incrustation n'est peut-être visible que le temps d'une
             * image (comme le plan vidéo, qu'il faut réafficher). On la
             * réaffiche à cadence BORNÉE : une fois par seconde, vingt fois au
             * plus — jamais par image, la règle qui a coûté un gel. */
            if( p_sys->i_sp_pulse > 0 && ++p_sys->i_sp_tick >= 25 )
            {
                p_sys->i_sp_tick = 0;
                p_sys->i_sp_pulse--;
                dvddriver_sp_reshow( p_sys->p_hw );
            }
            /* SP2b — rejeu UNIQUE de la séquence subpicture après quelques
             * dizaines d'images : elle est peut-être effacée par le décodage
             * qui suit son installation à l'ouverture. */
            if( p_sys->i_sp_replay > 0 && --p_sys->i_sp_replay == 0
             && p_sys->p_hw != NULL && p_sys->p_info->sequence != NULL )
            {
                int rc[6] = { 0, 0, 0, 0, 0, 0 };
                const mpeg2_sequence_t *sq = p_sys->p_info->sequence;
                if( dvddriver_sp_show_test( p_sys->p_hw, sq->width, sq->height, rc ) )
                    msg_Info( p_dec, "SP2b rejoué en cours de lecture : EnableSP=%d "
                              "SetPalette=%d ApplyDCSQ=%d SetSPBuffer=%d "
                              "ShowSPBuffer=%d", rc[0], rc[1], rc[2], rc[3], rc[4] );
            }
            /* Décodage matériel : la picture I vient d'être entièrement parsée
             * (macroblocs capturés par les hooks) → construire pic_desc et la
             * soumettre au GPU (DVDDriverDecode). Une seule fois par picture. */
            if( p_sys->b_hw_picture )
            {
                /* Le temps passé à ATTENDRE une surface GPU libre (et, en
                 * asynchrone, la fin du Decode précédent) n'est pas du travail
                 * de décodage : c'est le contrôle de flux qui retient un
                 * décodeur EN AVANCE. Laissé dans p_tau, il fait croire au
                 * synchro qu'il ne tient pas le temps réel et lui fait jeter un
                 * tiers des images alors que le budget est tenu. */
                int i_hw_rc = dvddriver_picture_submit( p_sys->p_hw );
                /* Exclusion active AUSSI en synchrone depuis le 29/07 : sur
                 * Panther, l'attente de surface (~28 ms par P quand les 5
                 * surfaces tournent à flux tendu) gonflait le tau et
                 * verrouillait le synchro dans un cycle « une B sur deux
                 * jetée » (cadence bimodale 40/80 ms, perçue comme un
                 * dédoublement) dont seul un seek le sortait. Le « sans gain
                 * mesuré » historique datait de l'époque où le pipeline était
                 * réellement en retard (CPU-segment I à 85 ms) ; le budget est
                 * tenu depuis les correctifs gettext/UI. /tmp/hw_noexcl
                 * rétablit l'ancien comportement pour l'A/B sans rebuild. */
                bool b_excl = true;
                {
                    FILE *fx = fopen( "/tmp/hw_noexcl", "r" );
                    if( fx != NULL ) { b_excl = false; fclose( fx ); }
                }
                if( p_sys->p_synchro != NULL && ( p_sys->b_async || b_excl ) )
                    decoder_SynchroExcludeTime( p_sys->p_synchro,
                        (vlc_tick_t) dvddriver_last_surf_wait_us( p_sys->p_hw )
                      + (vlc_tick_t) dvddriver_last_submit_wait_us( p_sys->p_hw ) );
                if( i_hw_rc == -4 && !p_sys->b_hw_giveup )
                {
                    /* Garde-fou anti-wedge déclenché côté backend : DVDDriverDecode
                     * s'est bloqué plusieurs secondes à répétition. On rend la main
                     * au CPU (fin du mode remplacement) plutôt que de continuer
                     * vers un wedge GPU qui exigerait d'éteindre la machine. */
                    msg_Warn( p_dec, "décodage matériel ABANDONNÉ (blocages répétés "
                              "dans DVDDriverDecode) → retour 100 %% CPU" );
                    mpeg2_set_hw_replace( 0 );
                    p_sys->b_hw_giveup = true;
                }
                /* Type de la picture qu'on vient de soumettre. */
                int i_ct_sub = p_sys->p_info->current_picture ?
                    (p_sys->p_info->current_picture->flags & PIC_MASK_CODING_TYPE) : 0;
                bool b_is_ref = ( i_ct_sub == PIC_FLAG_CODING_TYPE_I
                               || i_ct_sub == PIC_FLAG_CODING_TYPE_P );
                /* Chemin asynchrone : l'échec d'un Decode remonte à la picture
                 * SUIVANTE. Même politique que le rc≠0 synchrone : une
                 * référence perdue gèle l'affichage jusqu'à la prochaine I. */
                int i_async_fail = dvddriver_async_take_failure( p_sys->p_hw );
                if( i_async_fail != 0 && i_async_fail != 3 /* pas une B */ )
                {
                    msg_Warn( p_dec, "Decode asynchrone échoué sur une référence "
                              "(type %d) → gel jusqu'à la prochaine I", i_async_fail );
                    p_sys->b_hw_stale = true;
                }
                if( i_hw_rc != 0 && b_is_ref )
                    p_sys->b_hw_stale = true;   /* chaîne de références rompue */
                else if( i_hw_rc == 0 && i_ct_sub == PIC_FLAG_CODING_TYPE_I )
                    p_sys->b_hw_stale = false;  /* une I repart d'une chaîne saine */

                if( i_hw_rc == 0 && !p_sys->b_hw_stale )
                {
                    /* U4 : la picture vient d'être décodée dans la surface out_idx.
                     * On attache à la picture_t un contexte {surface, génération}
                     * → le VOUT présentera cette surface au moment d'AFFICHER la
                     * picture (ordre PTS, thread vout). PAS de present ici (décodage
                     * ≠ affichage ; et le pacing PTS du vout donne la synchro A/V). */
                    int i_out = dvddriver_out_index( p_sys->p_hw );
                    picture_t *p_hwpic = ( p_sys->p_info->current_fbuf ) ?
                                         p_sys->p_info->current_fbuf->id : NULL;
                    if( i_out >= 0 && p_hwpic != NULL )
                    {
                        if( p_hwpic->context != NULL )
                        {   /* défensif : libérer un contexte résiduel */
                            p_hwpic->context->destroy( p_hwpic->context );
                            p_hwpic->context = NULL;
                        }
                        p_hwpic->context =
                            HwPicContextNew( p_sys->p_hw, i_out );
                    }
                }
                else
                {
                    /* ★ PICTURE À NE PAS AFFICHER, EN MODE REMPLACEMENT.
                     * Deux cas : (a) le GPU ne l'a pas décodée ; (b) il l'a
                     * décodée mais à partir d'une chaîne de références rompue
                     * (b_hw_stale) — son contenu est faux là où ça bouge.
                     * Ne SURTOUT pas la laisser s'afficher : en remplacement, la
                     * reconstruction logicielle des références a été sautée (slice.c
                     * n'a fait ni iDCT ni motion-comp), donc les plans logiciels des
                     * références sont VIDES. Une picture retombée sur le CPU est donc
                     * prédite à partir de rien → pavés de bouillie à l'écran, sur les
                     * seules zones en mouvement (les zones fixes n'ont pas de
                     * résidu). C'est ce qui restait visible en lecture : ~13 pictures
                     * par lecture, soit un artefact toutes les quelques secondes.
                     * On lui attache donc un contexte matériel INVALIDE : le vout le
                     * reconnaît comme une picture HW (il saute le rendu GL) mais rien
                     * n'est présenté → la dernière image correcte reste affichée. */
                    picture_t *p_hwpic = ( p_sys->p_info->current_fbuf ) ?
                                         p_sys->p_info->current_fbuf->id : NULL;
                    if( p_hwpic != NULL && !p_sys->b_hw_giveup )
                    {
                        if( p_hwpic->context != NULL )
                        {
                            p_hwpic->context->destroy( p_hwpic->context );
                            p_hwpic->context = NULL;
                        }
                        p_hwpic->context = HwPicContextNew( p_sys->p_hw, -1 );
                    }
                }
                int i_ct2 = p_sys->p_info->current_picture ?
                    (p_sys->p_info->current_picture->flags & PIC_MASK_CODING_TYPE) : 0;
                char c_type = i_ct2 == PIC_FLAG_CODING_TYPE_I ? 'I'
                            : i_ct2 == PIC_FLAG_CODING_TYPE_P ? 'P'
                            : i_ct2 == PIC_FLAG_CODING_TYPE_B ? 'B' : '?';
                unsigned u_cap = 0, u_tot = 0;
                dvddriver_last_progress( p_sys->p_hw, &u_cap, &u_tot );
                {
                    struct timeval tvn;
                    gettimeofday( &tvn, NULL );
                    unsigned long now = (unsigned long) tvn.tv_sec * 1000000UL
                                      + tvn.tv_usec;
                    unsigned long wall = now - p_sys->i_hw_pic_t0;
                    unsigned long dec  = dvddriver_last_decode_us( p_sys->p_hw );
                    unsigned long wait = dvddriver_last_surf_wait_us( p_sys->p_hw );
                    /* cpu = mur - Decode - attente de surface : la part VLD +
                     * hooks + encodage, celle qui n'est PAS recouvrable. */
                    msg_Dbg( p_dec, "DVDDriverDecode (matériel %c) rc=%d [%u/%u mb]%s%d"
                             " dt=%lu us cpu=%lu wait=%lu",
                             c_type, i_hw_rc, u_cap, u_tot,
                             i_hw_rc == 0 ? " → surface " : " (rc≠0) ",
                             i_hw_rc == 0 ? dvddriver_out_index( p_sys->p_hw ) : -1,
                             dec, wall > dec + wait ? wall - dec - wait : 0, wait );
                }
                /* PERF (chantier 720×576, temporaire) : attribution du budget par
                 * picture entre Decode (GPU) et present (ShowMPBuffer + CGS).
                 * Logué tous les 50 submits → un run court suffit, et le log
                 * survit à une sortie non propre. */
                static unsigned s_perf_n = 0;
                if( ++s_perf_n % 50 == 0 )
                {
                    unsigned n_d = 0, n_p = 0, n_st = 0;
                    unsigned long us_d = 0, us_p = 0;
                    dvddriver_perf_get( p_sys->p_hw, &n_d, &us_d, &n_p, &us_p,
                                        &n_st );
                    msg_Dbg( p_dec, "PERF HW : Decode %u appels, %lu us total, "
                              "%lu us/appel | present %u appels, %lu us total, "
                              "%lu us/appel | present périmés %u",
                              n_d, us_d, n_d ? us_d / n_d : 0,
                              n_p, us_p, n_p ? us_p / n_p : 0, n_st );
                    msg_Dbg( p_dec, "PERF HW : attentes de surface GPU=%u",
                             dvddriver_surf_waits( p_sys->p_hw ) );
                    {
                        unsigned sc[3];
                        dvddriver_show_counts( p_sys->p_hw, sc );
                        msg_Dbg( p_dec, "PERF HW : Show par chemin — cible=%u "
                                 "drainage=%u recyclage=%u", sc[0], sc[1], sc[2] );
                    }
                    msg_Dbg( p_dec, "PERF HW : rappels de present reçus du vout=%u",
                             g_hw_cb_calls );
                    unsigned mb8[8] = {0}, dct2[2] = {0}, cvt3[3] = {0};
                    dvddriver_mb_stats( p_sys->p_hw, mb8, dct2, cvt3 );
                    msg_Dbg( p_dec, "STAT MB : intra=%u fwd=%u bwd=%u bidir=%u "
                             "skip=%u ffwd=%u fbwd=%u fbidir=%u | dct frame=%u "
                             "champ=%u", mb8[0], mb8[1], mb8[2], mb8[3], mb8[4],
                             mb8[5], mb8[6], mb8[7], dct2[0], dct2[1] );
                    msg_Dbg( p_dec, "STAT FIELD : convertis exactement=%u, "
                             "convertis par approximation=%u, laissés au moteur "
                             "field=%u", cvt3[0], cvt3[2], cvt3[1] );
                }
                p_sys->b_hw_picture = false;

                /* ★★★ GARDE « VRAIE VIDÉO ENTRELACÉE » — cf. HW_CVT_MIN_PCT.
                 * La sonde a jugé au niveau PICTURE ; ici on juge sur ce qui se
                 * passe VRAIMENT au macrobloc. Si les prédictions de champ ne
                 * sont pas convertibles en prédiction frame, tout part au moteur
                 * field natif de l'ATI et l'image est fausse : mieux vaut un
                 * décodage logiciel lent et correct. */
                if( !p_sys->b_cvt_checked && p_sys->p_hw != NULL )
                {
                    unsigned mb8[8] = { 0 }, cvt3[3] = { 0, 0, 0 };
                    dvddriver_mb_stats( p_sys->p_hw, mb8, NULL, cvt3 );
                    unsigned u_tot_mb = 0;
                    for( int i = 0; i < 8; i++ )
                        u_tot_mb += mb8[i];

                    if( u_tot_mb >= HW_CVT_MIN_MB )
                    {
                        p_sys->b_cvt_checked = true;
                        /* Le dégât, c'est ce qui part au moteur field, rapporté
                         * au TOTAL — pas la part des seuls macroblocs field. */
                        const unsigned pct_bad = ( cvt3[1] * 100u ) / u_tot_mb;
                        msg_Dbg( p_dec, "décodage matériel : macroblocs à "
                                 "prédiction par champ — %u convertis exactement, "
                                 "%u approchés, %u laissés au moteur field, soit "
                                 "%u %% des %u macroblocs (seuil de repli %u %%)",
                                 cvt3[0], cvt3[2], cvt3[1], pct_bad, u_tot_mb,
                                 HW_CVT_MAX_PCT );
                        if( pct_bad > HW_CVT_MAX_PCT )
                        {
                            msg_Info( p_dec, "décodage matériel : %u %% des "
                                      "macroblocs partent au moteur field de "
                                      "l'ATI, dont l'adressage produit une image "
                                      "fausse — vraie vidéo entrelacée → repli "
                                      "100 %% CPU pour ce flux", pct_bad );
                            /* Même séquence de démontage que la réouverture sur
                             * changement de fenêtre : suspendre l'affichage AVANT
                             * de dépublier le contexte, sinon les pictures déjà en
                             * file chez le vout portent un contexte mort. */
                            mpeg2_hwaccel( p_sys->p_mpeg2dec, NULL );
                            mpeg2_set_hw_replace( 0 );
                            if( p_sys->b_102mods )
                                var_SetBool( p_dec->obj.libvlc,
                                             DVDDRIVER_VAR_HOLD, true );
                            var_SetAddress( p_dec->obj.libvlc,
                                            DVDDRIVER_VAR_CTX, NULL );
                            dvddriver_close( p_sys->p_hw );
                            p_sys->p_hw = NULL;
                            p_sys->b_hw_stale = false;
                            /* ⚠ DÉFINITIF pour ce flux : ni b_hw_reopen, ni
                             * relance de sonde. Rouvrir reviendrait à repayer la
                             * même image fausse à chaque I. */
                            p_sys->b_hw_reopen = false;
                            p_sys->b_hwaccel   = false;
                        }
                    }
                    else if( ++p_sys->i_cvt_pics >= HW_CVT_MAX_PICS )
                    {
                        /* Trop peu de macroblocs soumis pour juger, et on a assez
                         * attendu : on cesse d'interroger le compteur. */
                        p_sys->b_cvt_checked = true;
                    }
                }
            }
#endif

            if( p_sys->p_info->display_fbuf &&
                p_sys->p_info->display_fbuf->id )
            {
                p_pic = p_sys->p_info->display_fbuf->id;

#ifdef __APPLE__
                /* ★ TROU DE RÉOUVERTURE (bascule plein écran ⇄ fenêtré). Le
                 * décodeur matériel vient d'être fermé et sera rouvert à la
                 * prochaine image I. Dans l'intervalle le décodage repasse au CPU
                 * — mais en mode REMPLACEMENT les plans logiciels des références
                 * n'ont JAMAIS été reconstruits : ces P/B sont prédites à partir
                 * de rien et sortent en bouillie (l'écran vert et les glitchs vus
                 * à la bascule). Elles n'ont aucune valeur : on les jette et la
                 * dernière image correcte reste affichée le temps du trou. */
                if( p_sys->b_hw_reopen && p_sys->b_102mods )
                {
                    DpbUnlinkPicture( p_dec, p_pic );
                    p_pic = NULL;
                }
                else
#endif
                if( DpbDisplayPicture( p_dec, p_pic ) )
                    p_pic = NULL;

                decoder_SynchroEnd( p_sys->p_synchro,
                                    p_sys->p_info->display_picture->flags & PIC_MASK_CODING_TYPE,
                                    p_sys->b_garbage_pic );

                if( p_pic )
                {
                    p_pic->date = decoder_SynchroDate( p_sys->p_synchro );
                    if( p_sys->b_garbage_pic )
                        p_pic->date = 0; /* ??? */
                    p_sys->b_garbage_pic = false;
                }
            }

            if( p_sys->p_info->discard_fbuf &&
                p_sys->p_info->discard_fbuf->id )
            {
                DpbUnlinkPicture( p_dec, p_sys->p_info->discard_fbuf->id );
            }

            if( p_pic )
            {
                if( state == STATE_END )
                    p_pic->b_force = true; /* For still frames */

                /* Avoid frames with identical timestamps.
                 * Especially needed for still frames in DVD menus. */
                if( p_sys->i_last_frame_pts == p_pic->date )
                    p_pic->date++;
                p_sys->i_last_frame_pts = p_pic->date;
                return p_pic;
            }
            break;
        }

        case STATE_INVALID:
        {
            msg_Err( p_dec, "invalid picture encountered" );
            /* I don't think we have anything to do, but well without
             * docs ... */
            break;
        }

        default:
            break;
        }
    }

    /* Never reached */
    return NULL;
}

static int DecodeVideo( decoder_t *p_dec, block_t *p_block)
{
    if( p_block == NULL ) /* No Drain */
        return VLCDEC_SUCCESS;

    block_t **pp_block = &p_block;
    picture_t *p_pic;
    while( ( p_pic = DecodeBlock( p_dec, pp_block ) ) != NULL )
        decoder_QueueVideo( p_dec, p_pic );
    return VLCDEC_SUCCESS;
}

/*****************************************************************************
 * CloseDecoder: libmpeg2 decoder destruction
 *****************************************************************************/
static void CloseDecoder( vlc_object_t *p_this )
{
    decoder_t *p_dec = (decoder_t *)p_this;
    decoder_sys_t *p_sys = p_dec->p_sys;

#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)
    cc_Flush( &p_sys->cc );
#endif

    DpbClean( p_dec );

    free( p_sys->p_gop_user_data );

    if( p_sys->p_synchro ) decoder_SynchroRelease( p_sys->p_synchro );

    if( p_sys->p_mpeg2dec ) mpeg2_close( p_sys->p_mpeg2dec );

#ifdef __APPLE__
    /* U4 : retirer le contexte du bus AVANT close → le vout cesse de présenter
     * (il lit dvddriver-ctx à chaque display, jamais en cache). Puis close ferme
     * le device (sous mutex : couvre un present déjà entré). */
    var_SetAddress( p_dec->obj.libvlc, DVDDRIVER_VAR_CTX, NULL );
    var_SetBool( p_dec->obj.libvlc, DVDDRIVER_VAR_SUBS, false );
    if( p_sys->p_hw )
    {
        msg_Info( p_dec, "nature du contenu : %u images progressive_frame, "
                  "%u entrelacées ; nb_fields 2=%u 3=%u",
                  p_sys->i_pic_prog, p_sys->i_pic_inter,
                  p_sys->i_fields_2, p_sys->i_fields_3 );
        uint32_t iv[8], n = 0;
        dvddriver_present_intervals( p_sys->p_hw, iv, &n );
        if( n > 0 )
            msg_Info( p_dec, "cadence de présentation (%u images) : <25ms=%u "
                      "<33=%u <37=%u <43=%u <50=%u <60=%u <100=%u >=100=%u",
                      n, iv[0], iv[1], iv[2], iv[3], iv[4], iv[5], iv[6], iv[7] );
        msg_Info( p_dec, "attentes cumulées : submit(fin du Decode précédent)=%lu ms, "
                  "surface=%lu ms",
                  dvddriver_submit_wait_us( p_sys->p_hw ) / 1000,
                  dvddriver_surf_wait_total_us( p_sys->p_hw ) / 1000 );
        uint32_t dh[8], dn = 0;
        dvddriver_decode_times( p_sys->p_hw, dh, &dn );
        if( dn > 0 )
            msg_Info( p_dec, "durées de Decode (%u appels) : <4ms=%u <8=%u "
                      "<12=%u <16=%u <24=%u <40=%u <80=%u >=80=%u",
                      dn, dh[0], dh[1], dh[2], dh[3], dh[4], dh[5], dh[6], dh[7] );
        dvddriver_close( p_sys->p_hw );
    }
    var_SetAddress( p_dec->obj.libvlc, DVDDRIVER_VAR_SP_HIDE, NULL );
    var_Destroy( p_dec->obj.libvlc, DVDDRIVER_VAR_CTX );
    var_Destroy( p_dec->obj.libvlc, DVDDRIVER_VAR_PRESENT );
    var_Destroy( p_dec->obj.libvlc, DVDDRIVER_VAR_HIDE );
    var_Destroy( p_dec->obj.libvlc, DVDDRIVER_VAR_SP_HIDE );
    var_Destroy( p_dec->obj.libvlc, DVDDRIVER_VAR_SUBS );
    /* Le flag REMPLACEMENT est un global libmpeg2 (partagé entre instances de
     * décodeur). Le remettre à 0 pour qu'une instance suivante en CPU pur (flux
     * entrelacé) ne l'hérite pas actif. Inoffensif si déjà 0. */
    mpeg2_set_hw_replace( 0 );
#endif

    free( p_sys );
}

/*****************************************************************************
 * Reset: reset the decoder state
 *****************************************************************************/
static void Reset( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)
    cc_Flush( &p_sys->cc );
#endif
    mpeg2_reset( p_sys->p_mpeg2dec, 0 );
    DpbClean( p_dec );

#ifdef __APPLE__
    /* ★ FLUSH (seek) : NE PAS fermer le décodeur matériel (29/07 midi).
     * La fermeture/réouverture au flush datait de la théorie « matériel ouvert
     * sur le menu » (réfutée : les vraies causes du dédoublement étaient le
     * seuil DELTA du synchro et la réouverture elle-même — toute réouverture
     * en cours de lecture atterrit dans un mode de composition WindowServer
     * cassé, flush ~420 µs au lieu de ~2 ms, mesuré). On garde le matériel
     * ouvert : les références GPU sont périmées après le seek, on gèle
     * l'affichage jusqu'à la prochaine I (b_hw_stale), qui ne référence rien. */
    if( p_sys->p_hw != NULL )
    {
        /* Reset vidéo est garanti au seek, contrairement au flush du décodeur
         * SPU qui peut arriver après coup : retirer le dernier calque ici. */
        dvddriver_sp_hide( p_sys->p_hw );
        msg_Dbg( p_dec, "flush : références matérielles périmées, "
                 "gel jusqu'à la prochaine I (décodeur conservé)" );
        p_sys->b_hw_picture = false;
        p_sys->b_hw_stale = true;
    }
#endif
}

/*****************************************************************************
 * GetNewPicture: Get a new picture from the vout and set the buf struct
 *****************************************************************************/
static picture_t *GetNewPicture( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    picture_t *p_pic;

    p_dec->fmt_out.video.i_width = p_sys->p_info->sequence->width;
    p_dec->fmt_out.video.i_visible_width =
        p_sys->p_info->sequence->picture_width;
    p_dec->fmt_out.video.i_height = p_sys->p_info->sequence->height;
    p_dec->fmt_out.video.i_visible_height =
        p_sys->p_info->sequence->picture_height;
    p_dec->fmt_out.video.i_sar_num = p_sys->i_sar_num;
    p_dec->fmt_out.video.i_sar_den = p_sys->i_sar_den;

    if( p_sys->p_info->sequence->frame_period > 0 )
    {
        p_dec->fmt_out.video.i_frame_rate =
            (uint32_t)( (uint64_t)1001000000 * 27 /
                        p_sys->p_info->sequence->frame_period );
        p_dec->fmt_out.video.i_frame_rate_base = 1001;
    }

    p_dec->fmt_out.i_codec =
        ( p_sys->p_info->sequence->chroma_height <
          p_sys->p_info->sequence->height ) ?
        VLC_CODEC_I420 : VLC_CODEC_I422;

    /* Get a new picture */
    if( decoder_UpdateVideoFormat( p_dec ) )
        return NULL;
    p_pic = decoder_NewPicture( p_dec );

    if( p_pic == NULL )
        return NULL;

    /* In hardware replacement mode the GPU's field engine has already woven
     * the two fields: the picture that comes out is progressive, and saying
     * otherwise makes the core insert a software deinterlace filter. That
     * filter costs a good part of a G3 -- and, worse, it hands the vout NEW
     * pictures, which carry no hardware picture context: the vout then never
     * presents the GPU surface (measured on 10.2: "present matériel non
     * engagé ... context=0x0", 800 pictures in a row). */
    p_pic->b_progressive = ( p_sys->b_102mods && p_sys->b_hwaccel
                             && p_sys->p_hw != NULL ) ? true
        : ( p_sys->p_info->current_picture != NULL ?
            p_sys->p_info->current_picture->flags & PIC_FLAG_PROGRESSIVE_FRAME
          : 1 );
    p_pic->b_top_field_first = p_sys->p_info->current_picture != NULL ?
        p_sys->p_info->current_picture->flags & PIC_FLAG_TOP_FIELD_FIRST : 1;
    p_pic->i_nb_fields = p_sys->p_info->current_picture != NULL ?
        p_sys->p_info->current_picture->nb_fields : 2;

    return p_pic;
}

#if MPEG2_RELEASE >= MPEG2_VERSION (0, 5, 0)
/*****************************************************************************
 * SendCc: Sends the Closed Captions for the CC decoder.
 *****************************************************************************/
static void SendCc( decoder_t *p_dec )
{
    decoder_sys_t   *p_sys = p_dec->p_sys;
    block_t         *p_cc = NULL;

    if( !p_sys->cc.b_reorder && p_sys->cc.i_data <= 0 )
        return;

    p_cc = block_Alloc( p_sys->cc.i_data);
    if( p_cc )
    {
        memcpy( p_cc->p_buffer, p_sys->cc.p_data, p_sys->cc.i_data );
        p_cc->i_dts =
        p_cc->i_pts = p_sys->cc.b_reorder ? p_sys->i_cc_pts : p_sys->i_cc_dts;
        p_cc->i_flags = p_sys->i_cc_flags & BLOCK_FLAG_TYPE_MASK;
        decoder_cc_desc_t desc;
        desc.i_608_channels = p_sys->cc.i_608channels;
        desc.i_708_channels = p_sys->cc.i_708channels;
        desc.i_reorder_depth = p_sys->cc.b_reorder ? 0 : -1;
        decoder_QueueCc( p_dec, p_cc, &desc );
    }
    cc_Flush( &p_sys->cc );
    return;
}
#endif

/*****************************************************************************
 * GetAR: Get aspect ratio
 *****************************************************************************/
static void GetAR( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    int i_old_sar_num = p_sys->i_sar_num;
    int i_old_sar_den = p_sys->i_sar_den;

    /* Check whether the input gave a particular aspect ratio */
    if( p_dec->fmt_in.video.i_sar_num > 0 &&
        p_dec->fmt_in.video.i_sar_den > 0 )
    {
        p_sys->i_sar_num = p_dec->fmt_in.video.i_sar_num;
        p_sys->i_sar_den = p_dec->fmt_in.video.i_sar_den;
    }
    /* Use the value provided in the MPEG sequence header */
    else if( p_sys->p_info->sequence->pixel_height > 0 )
    {
        p_sys->i_sar_num = p_sys->p_info->sequence->pixel_width;
        p_sys->i_sar_den = p_sys->p_info->sequence->pixel_height;
    }
    else
    {
        /* Invalid aspect, assume 4:3.
         * This shouldn't happen and if it does it is a bug
         * in libmpeg2 (likely triggered by an invalid stream) */
        p_sys->i_sar_num = p_sys->p_info->sequence->picture_height * 4;
        p_sys->i_sar_den = p_sys->p_info->sequence->picture_width * 3;
    }

    if( p_sys->i_sar_num == i_old_sar_num &&
        p_sys->i_sar_den == i_old_sar_den )
        return;

    if( p_sys->p_info->sequence->frame_period > 0 )
        msg_Dbg( p_dec,
                 "%dx%d (display %d,%d), sar %i:%i, %u.%03u fps",
                 p_sys->p_info->sequence->picture_width,
                 p_sys->p_info->sequence->picture_height,
                 p_sys->p_info->sequence->display_width,
                 p_sys->p_info->sequence->display_height,
                 p_sys->i_sar_num, p_sys->i_sar_den,
                 (uint32_t)((uint64_t)1001000000 * 27 /
                     p_sys->p_info->sequence->frame_period / 1001),
                 (uint32_t)((uint64_t)1001000000 * 27 /
                     p_sys->p_info->sequence->frame_period % 1001) );
    else
        msg_Dbg( p_dec, "bad frame period" );
}

/*****************************************************************************
 * PutPicture: Put a picture_t in mpeg2 context
 *****************************************************************************/
static void PutPicture( decoder_t *p_dec, picture_t *p_picture )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* */
    uint8_t *pp_buf[3];
    for( int j = 0; j < 3; j++ )
        pp_buf[j] = p_picture ? p_picture->p[j].p_pixels : NULL;
    mpeg2_set_buf( p_sys->p_mpeg2dec, pp_buf, p_picture );

    /* Completely broken API, why the hell does it suppose
     * the stride of the chroma planes ! */
    if( p_picture )
        mpeg2_stride( p_sys->p_mpeg2dec, p_picture->p[Y_PLANE].i_pitch );
}


/**
 * Initialize a virtual Decoded Picture Buffer to workaround
 * libmpeg2 deficient API
 */
static void DpbInit( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    for( int i = 0; i < DPB_COUNT; i++ )
        p_sys->p_dpb[i].p_picture = NULL;
}
/**
 * Empty and reset the current DPB
 */
static void DpbClean( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    for( int i = 0; i < DPB_COUNT; i++ )
    {
        picture_dpb_t *p = &p_sys->p_dpb[i];
        if( !p->p_picture )
            continue;
        if( p->b_linked )
            picture_Release( p->p_picture );
        if( !p->b_displayed )
            picture_Release( p->p_picture );

        p->p_picture = NULL;
    }
}
/**
 * Retrieve a picture and reserve a place in the DPB
 */
static picture_t *DpbNewPicture( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    picture_dpb_t *p;
    int i;

    for( i = 0; i < DPB_COUNT; i++ )
    {
        p = &p_sys->p_dpb[i];
        if( !p->p_picture )
            break;
    }
    if( i >= DPB_COUNT )
    {
        msg_Err( p_dec, "Leaking picture" );
        return NULL;
    }

    p->p_picture = GetNewPicture( p_dec );
    if( p->p_picture )
    {
        picture_Hold( p->p_picture );
        p->b_linked = true;
        p->b_displayed = false;

        p->p_picture->date = 0;
    }
    return p->p_picture;
}
static picture_dpb_t *DpbFindPicture( decoder_t *p_dec, picture_t *p_picture )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    for( int i = 0; i < DPB_COUNT; i++ )
    {
        picture_dpb_t *p = &p_sys->p_dpb[i];
        if( p->p_picture == p_picture )
            return p;
    }
    return NULL;
}
/**
 * Unlink the provided picture and ensure that the decoder
 * does not own it anymore.
 */
static void DpbUnlinkPicture( decoder_t *p_dec, picture_t *p_picture )
{
    picture_dpb_t *p = DpbFindPicture( p_dec, p_picture );

    /* XXX it is needed to workaround libmpeg2 bugs */
    if( !p || !p->b_linked )
    {
        msg_Err( p_dec, "DpbUnlinkPicture called on an invalid picture" );
        return;
    }

    assert( p && p->b_linked );

    picture_Release( p->p_picture );
    p->b_linked = false;

    if( !p->b_displayed )
        picture_Release( p->p_picture );
    p->p_picture = NULL;
}
/**
 * Mark the provided picture as displayed.
 */
static int DpbDisplayPicture( decoder_t *p_dec, picture_t *p_picture )
{
    picture_dpb_t *p = DpbFindPicture( p_dec, p_picture );

    /* XXX it is needed to workaround libmpeg2 bugs */
    if( !p || p->b_displayed || !p->b_linked )
    {
        msg_Err( p_dec, "DpbDisplayPicture called on an invalid picture" );
        return VLC_EGENERIC;
    }

    assert( p && !p->b_displayed && p->b_linked );

    p->b_displayed = true;
    return VLC_SUCCESS;
}
