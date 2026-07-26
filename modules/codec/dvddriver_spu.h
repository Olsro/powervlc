/*****************************************************************************
 * dvddriver_spu.h : sous-titres DVD incrustés par le plan subpicture matériel
 *****************************************************************************
 * Sous-module « spu decoder » du plugin libmpeg2. Il ne produit AUCUN
 * subpicture_t : il décode le RLE du paquet SPU et remet le bitmap 2 bits/pixel
 * au décodeur matériel ATI, qui l'incruste lui-même sur la vidéo. Le descripteur
 * de module vit dans libmpeg2.c (un seul vlc_module_begin par plugin).
 *****************************************************************************/
#ifndef VLC_DVDDRIVER_SPU_H
#define VLC_DVDDRIVER_SPU_H

int  dvddriver_spu_Open (vlc_object_t *);
void dvddriver_spu_Close(vlc_object_t *);

#endif /* VLC_DVDDRIVER_SPU_H */
