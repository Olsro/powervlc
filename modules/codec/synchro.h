/*****************************************************************************
 * vlc_codec_synchro.h: frame-dropping structures
 *****************************************************************************
 * Copyright (C) 1999-2005 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Christophe Massiot <massiot@via.ecp.fr>
 *          Jean-Marc Dressler <polux@via.ecp.fr>
 *          Stéphane Borel <stef@via.ecp.fr>
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
 * decoder_synchro_t : timers for the video synchro
 *****************************************************************************/
/* Read the discussion on top of decoder_synchro.c for more information. */
/* Pictures types */
#define I_CODING_TYPE           1
#define P_CODING_TYPE           2
#define B_CODING_TYPE           3
#define D_CODING_TYPE           4 /* MPEG-1 ONLY */
/* other values are reserved */

/*****************************************************************************
 * Prototypes
 *****************************************************************************/
decoder_synchro_t * decoder_SynchroInit( decoder_t *, int ) VLC_USED;
void decoder_SynchroRelease( decoder_synchro_t * );
void decoder_SynchroReset( decoder_synchro_t * );
bool decoder_SynchroChoose( decoder_synchro_t *, int, int, bool );
void decoder_SynchroTrash( decoder_synchro_t * );
void decoder_SynchroDecode( decoder_synchro_t * );
void decoder_SynchroEnd( decoder_synchro_t *, int, bool );
/* Retranche du coût mesuré d'une picture un temps qui n'est PAS du travail de
 * décodage : sur le chemin matériel, l'attente d'une surface GPU libre est le
 * signe que le décodeur a pris de l'AVANCE, pas qu'il peine. La compter dans
 * p_tau fait croire au synchro qu'il ne tient pas la cadence et lui fait
 * jeter des images sans raison. */
void decoder_SynchroExcludeTime( decoder_synchro_t *, vlc_tick_t );
vlc_tick_t decoder_SynchroDate( decoder_synchro_t * ) VLC_USED;
void decoder_SynchroNewPicture( decoder_synchro_t *, int, int, vlc_tick_t, vlc_tick_t, bool );

