/*****************************************************************************
 * dvddriver_piccontext.h : contrat de present HW entre le décodeur libmpeg2 et
 *                          le vout macOS (present piloté par le vout — U4)
 *****************************************************************************
 * U4 — la picture décodée sur le GPU ATI porte un picture_context_t opaque
 * (défini en privé dans le décodeur). Au moment d'AFFICHER la picture (ordre
 * PTS, thread vout), le vout présente la surface GPU correspondante → le pacing
 * PTS du vout s'applique au present matériel = synchro A/V correcte.
 *
 * PROBLÈME de liaison : le device HW et ses fonctions vivent dans le PLUGIN
 * CODEC (liblibmpeg2). Le PLUGIN VOUT ne peut pas lier ces symboles. On passe
 * donc par le bus libvlc DEUX pointeurs (address vars) que le décodeur pose et
 * que le vout lit à chaque display (jamais en cache) :
 *   - DVDDRIVER_VAR_CTX     : le device HW (dvddriver_ctx*), NULL si fermé ;
 *   - DVDDRIVER_VAR_PRESENT : un CALLBACK (dvddriver_present_cb) fourni par le
 *     décodeur ; le vout l'appelle avec {device, picture->context} sans jamais
 *     introspecter le contexte (opaque) ni lier de symbole du codec.
 * Le callback renvoie true si la picture était une picture HW (→ le vout saute
 * le rendu GL) ; il présente la surface si sa génération est encore à jour.
 *****************************************************************************/
#ifndef VLC_DVDDRIVER_PICCONTEXT_H
#define VLC_DVDDRIVER_PICCONTEXT_H

#include <vlc_picture.h>            /* picture_context_t */
#include "dvddriver_backend.h"      /* dvddriver_ctx (opaque) */

/* Noms des variables libvlc (bus partagé décodeur ↔ vout). */
#define DVDDRIVER_VAR_CTX     "dvddriver-ctx"
#define DVDDRIVER_VAR_PRESENT "dvddriver-present"
/* Sous-titres/OSD par-dessus la surface HW (chantier S) — SOURCE DE VÉRITÉ
 * UNIQUE, posée par le décodeur à l'ouverture HW (option `mpeg2-hwaccel-subs`)
 * et lue par le vout au premier present matériel (avant, elle n'a pas encore sa
 * valeur définitive). Le décodeur passe la MÊME valeur à dvddriver_open().
 * ⚠ L'incrustation ne peut PAS se faire dans la vue GL : deux surfaces CGS
 * d'une même fenêtre ne se mélangent pas (mesuré G3/Tiger/RV200, dans les deux
 * ordres et fenêtre non opaque comprise) — le vout passe par une fenêtre enfant
 * transparente. */
#define DVDDRIVER_VAR_SUBS    "dvddriver-subs"
/* Variables de géométrie publiées par le vout (U1). */
#define DVDDRIVER_VAR_WID     "dvddriver-vout-wid"
#define DVDDRIVER_VAR_RECT_X  "dvddriver-vout-rect-x"
#define DVDDRIVER_VAR_RECT_Y  "dvddriver-vout-rect-y"
#define DVDDRIVER_VAR_RECT_W  "dvddriver-vout-rect-w"
#define DVDDRIVER_VAR_RECT_H  "dvddriver-vout-rect-h"

/* Callback de present fourni par le décodeur (posé sur DVDDRIVER_VAR_PRESENT).
 * hw       : device courant (lu par le vout sur DVDDRIVER_VAR_CTX) ;
 * pctx     : picture->context (opaque pour le vout) ;
 * x,y,w,h  : rectangle vidéo en coords FENÊTRE-locales (le vout le fournit pour
 *            que la surface liée à la fenêtre VLC suive la géométrie — U1/U4 ;
 *            ignoré pour le chemin fenêtre Carbon séparée).
 * Renvoie true si pctx était une picture HW (le vout saute alors le rendu GL). */
/* wid : numéro CGS de la fenêtre où la vidéo est affichée MAINTENANT. Il CHANGE
 * au passage en plein écran (l'interface legacy déplace la vue vidéo dans une
 * autre fenêtre) ; le décodeur ré-attache alors sa surface, sans quoi elle reste
 * liée à une fenêtre invisible et l'écran est noir. */
typedef bool (*dvddriver_present_cb)(dvddriver_ctx *hw, picture_context_t *pctx,
                                     int wid, int x, int y, int w, int h);

#endif /* VLC_DVDDRIVER_PICCONTEXT_H */
