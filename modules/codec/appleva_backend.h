/*****************************************************************************
 * appleva_backend.h : décodage MPEG-2 accéléré matériel via AppleVA
 *****************************************************************************
 * Backend GPU-agnostique (ATI Radeon, Intel GMA950, nVidia) pour vieux Macs
 * PPC/Intel (10.4-10.5). Pilote la pipeline privée AppleVA du lecteur DVD
 * d'Apple : le CPU fait le VLD (via libmpeg2), le GPU fait la motion-comp
 * (+ iDCT sur ATI). Voir doc/appleva-mpeg2-hwaccel-spec.md.
 *
 * Le setup (disponibilité + renderer + contexte) est VALIDÉ sur GMA950
 * (prototypes va_detect/va_init). Le feed macrobloc reste à finaliser.
 *
 * ⚠️⚠️ AVERTISSEMENT (trace DVD Player, 2026-07-20) : ce backend pilote
 * `IntelVARendererIDCTMCP`, mais la trace du VRAI DVD Player (hook byte-patch
 * injecté) montre que **DVD Player n'appelle JAMAIS IDCTMCP** — c'est une
 * fonction reliquat inutilisée. Le vrai décodage HW passe par des commandes GPU
 * BRUTES (io_connect), sans API propre. => Ce code NE PRODUIT PAS de décodage
 * fonctionnel (surfaces vides). Gardé comme référence ABI/vtable AppleVA.
 * Voir doc/appleva-mpeg2-hwaccel-spec.md §CONCLUSION + mémoire
 * powervlc-appleva-dvdplayer-trace-conclusion.
 *****************************************************************************/
#ifndef VLC_APPLEVA_BACKEND_H
#define VLC_APPLEVA_BACKEND_H

#include <stdint.h>
#include <stdbool.h>

/* Contexte opaque du backend. */
typedef struct appleva_ctx appleva_ctx;

/*
 * Renvoie true si l'accélération MPEG-2 matérielle est disponible sur
 * l'écran principal (gate AVAFGetGPURenderer). N'ouvre rien.
 * VALIDÉ : marche même hors session GUI.
 */
bool appleva_available(void);

/*
 * Ouvre le backend pour un flux width x height. Charge AppleVA, récupère et crée
 * le renderer GPU, crée le contexte de décodage LIÉ à la surface WindowServer
 * (CGS) fournie par l'appelant (le vout) : (cgs_connection, cgs_window,
 * cgs_surface). Le décodeur écrit directement dans cette surface d'affichage.
 * Renvoie NULL si indisponible (l'appelant doit alors retomber sur le CPU).
 * VALIDÉ end-to-end sur GMA950.
 */
appleva_ctx *appleva_open(unsigned width, unsigned height,
                          uint32_t cgs_connection, uint32_t cgs_window,
                          uint32_t cgs_surface);

/*
 * Assemblage + soumission d'une picture (API streaming alignée sur slice.c) :
 *   appleva_picture_begin(ctx, coding_type, alt_scan, pic_structure, nb_mbs)
 *   appleva_picture_add_mb(ctx, type_index, cbp, blocks, scan)  × nb_mbs
 *   appleva_picture_submit(ctx)
 * Construisent les flux de picture_params (descriptors/coeffs/CBP) et lancent
 * IntelVARendererIDCTMCP sur le GPU. Voir spec §3. Renvoient 0 si succès.
 *
 *   coding_type    : 1=I 2=P 3=B
 *   alt_scan       : 0/1 (table de scan alternée)
 *   pic_structure  : 0=frame (1/2=field, à venir)
 *   type_index     : index type du descriptor macrobloc (desc[0x14])
 *   cbp            : coded_block_pattern, bits 0x20..0x01 = Y0 Y1 Y2 Y3 U V
 *   blocks[6]      : DCTblock déquantifié de chaque bloc (NULL si bit CBP à 0)
 *   scan           : decoder->scan de libmpeg2
 */
int  appleva_picture_begin(appleva_ctx *ctx, int coding_type, int alt_scan,
                           int pic_structure, unsigned nb_mbs);
int  appleva_picture_submit(appleva_ctx *ctx);

/*
 * API streaming par bloc (alignée sur la boucle de slice.c) :
 *   appleva_picture_mb_begin(ctx, type_index, cbp)      au début du macrobloc
 *   appleva_picture_mb_block(ctx, dctblock, scan)       pour CHAQUE bloc codé, dans l'ordre
 *   appleva_picture_mb_end(ctx)                         à la fin du macrobloc
 * cbp en convention GPU (bit 0x20>>b = bloc b) : utiliser appleva_cbp_from_libmpeg2()
 * pour convertir un coded_block_pattern de libmpeg2 (bit 1<<b = bloc b).
 */
void appleva_picture_mb_begin(appleva_ctx *ctx, int type_index, uint8_t cbp);
void appleva_picture_mb_block(appleva_ctx *ctx, const int16_t *dctblock,
                              const uint8_t *scan);
void appleva_picture_mb_end(appleva_ctx *ctx);
uint8_t appleva_cbp_from_libmpeg2(unsigned mpeg2_cbp);

/* Helper : macrobloc complet (begin + blocs codés + end). blocks[b]=NULL si non
 * codé ; cbp en convention GPU. Pratique pour les harnais de test. */
void appleva_picture_add_mb(appleva_ctx *ctx, int type_index, uint8_t cbp,
                            const int16_t *const blocks[6], const uint8_t *scan);

/*
 * Ré-encode un bloc 8×8 déquantifié de libmpeg2 (decoder->DCTblock) au format
 * coefficients du driver : {u8 run, u8 pad, i16 level} en ordre zigzag.
 *   dctblock : les 64 coeffs (ordre de stockage selon `scan`)
 *   scan     : decoder->scan (scan[zz] = index de stockage du coeff zigzag zz)
 *   out      : buffer ≥ 64*4 o
 * Retourne le nombre de coefficients non nuls émis. Voir spec §4.
 */
unsigned appleva_encode_block(const int16_t *dctblock, const uint8_t *scan,
                              uint8_t *out);

/* Présente la surface décodée (SwapToExternalTargetImage). index = surface 0..3. */
void appleva_present(appleva_ctx *ctx, unsigned index);

/* DEBUG : région mémoire mappée par le GPU (adresse + taille). Après _present. */
void appleva_debug_mapped(appleva_ctx *ctx, void **addr, uint32_t *size);
uint32_t appleva_debug_ctx_u32(appleva_ctx *ctx, unsigned off);

/* Ferme le backend et libère les ressources GPU. */
void appleva_close(appleva_ctx *ctx);

#endif /* VLC_APPLEVA_BACKEND_H */
