/*****************************************************************************
 * dvddriver_spu.c : sous-titres DVD incrustés par le plan subpicture MATÉRIEL
 *****************************************************************************
 * Chantier SP4. Le décodeur matériel ATI (dvddriver_backend.c) possède un plan
 * subpicture que le GPU compose lui-même sur la vidéo décodée, sans aucun coût
 * par image — là où une incrustation par fenêtre coûte 15 à 50 ms sur ce
 * matériel (mesuré, cf. doc/pb-offload/subs-osd-findings.md).
 *
 * ⚠ Ce que le driver NE fait PAS. On pourrait croire qu'il suffit de lui passer
 * le paquet SPU brut : il exporte `DVDDriverApplySPDCSQ`, qui a tout l'air d'un
 * interpréteur de séquence de commandes. Il n'en est rien dans NOTRE mode
 * (« surface », ctx[0x1FC] == 0) : son moteur sort immédiatement sur les
 * commandes 0x00/0x01/0x02 et IGNORE PUREMENT la commande 0x06, celle qui porte
 * les adresses des deux trames RLE — et il renvoie 0 dans tous les cas, si bien
 * que son code de retour ne signale rien. Le décodage du RLE incombe donc à
 * l'hôte, ce qui explique que le tampon source du driver soit mappé côté CPU et
 * fasse exactement 192 octets × 576 lignes.
 *
 * Partage des rôles, établi par désassemblage puis vérifié sur iBook G3 :
 *   ici       : paquet SPU → bitmap 2 bits/pixel au format du driver ;
 *   le GPU    : palette, alpha, incrustation, composition à chaque image.
 *
 * Ce module ne produit AUCUN subpicture_t. Il se sélectionne quand le décodage
 * matériel est demandé ET disponible sur la machine ; sinon il décline et
 * `spudec` (priorité 75) reprend la main avec le rendu logiciel habituel.
 * ⚠ Le critère ne peut PAS être « le contexte matériel existe » : mesuré sur le
 * G3, la piste de sous-titres s'ouvre AVANT que le décodeur vidéo n'ait créé le
 * sien (il lui faut l'en-tête de séquence). Le contexte est donc relu à chaque
 * paquet, jamais mis en cache.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_codec.h>

#include <sys/utsname.h>

#include "dvddriver_backend.h"
#include "dvddriver_piccontext.h"
#include "dvddriver_spu.h"

/* Commandes d'une séquence SPU (identiques à modules/codec/spudec/spudec.h). */
#define SPU_CMD_FORCE_DISPLAY    0x00
#define SPU_CMD_START_DISPLAY    0x01
#define SPU_CMD_STOP_DISPLAY     0x02
#define SPU_CMD_SET_PALETTE      0x03
#define SPU_CMD_SET_ALPHACHANNEL 0x04
#define SPU_CMD_SET_COORDINATES  0x05
#define SPU_CMD_SET_OFFSETS      0x06
#define SPU_CMD_SET_COLCON       0x07
#define SPU_CMD_END              0xff

/* Format du plan source du driver : 192 octets par ligne (768 pixels à 2 bits,
 * la largeur DVD 720 arrondie à 64), 576 lignes. */
#define SP_PITCH 192u
#define SP_LINES 576u

/* ★ SP5 — un sous-titre prêt, en attente de SA date d'affichage.
 * Le bitmap est décodé dès l'analyse du paquet (le RLE coûte quelques ms sur un
 * G3 : le faire au moment de l'affichage ajouterait ce retard là où il se voit).
 * Les dates sont dans l'horloge système, converties du PTS par
 * decoder_GetDisplayDate. */
/* Taille retenue pour le paquet brut : les sous-titres d'un film tiennent
 * largement dedans (1 à 5 Ko mesurés ; 1272 octets dans la trace du DVD Player),
 * et 4 entrées de file à 24 Ko restent modestes à côté des 110 Ko de bitmap que
 * chacune porte déjà. Un paquet plus gros est simplement rendu en logiciel. */
#define SP_PKT_MAX 24576u
#define SP_CMD_MAX 64u

typedef struct
{
    uint8_t  bitmap[SP_PITCH * SP_LINES];
    uint8_t  palette[64];
    uint16_t colors, contrasts;
    unsigned lines;
    vlc_tick_t i_show, i_hide;    /* dates système ; i_hide == 0 = pas d'échéance */
    bool     b_used;
    /* 10.2 : le pilote veut le paquet BRUT et l'offset de chaque commande. */
    uint8_t  packet[SP_PKT_MAX];
    unsigned packet_size;
    uint16_t cmd_off[SP_CMD_MAX];
    unsigned cmd_count;
} sp_entry_t;

/* Profondeur de file. Les paquets SPU arrivent quelques secondes avant leur
 * affichage (davantage avec le cache DVD profond de ce projet) ; quatre suffit
 * largement, et chaque entrée coûte 108 Ko. */
#define SP_QUEUE 4

typedef struct
{
    /* ⚠ Aucun pointeur de device n'est conservé ici : il est RELU sur le bus
     * libvlc à chaque paquet. Le décodeur vidéo peut le fermer à tout moment
     * (fin de piste, repli CPU), et un pointeur en cache ferait appeler le
     * driver sur de la mémoire libérée. */

    /* Réassemblage : un paquet SPU peut arriver en plusieurs blocs. */
    uint8_t  buffer[65536];
    unsigned i_spu;               /* octets accumulés                          */
    unsigned i_spu_size;          /* taille annoncée par l'en-tête, 0 = inconnue */
    vlc_tick_t i_pts;             /* horodatage du paquet en cours             */

    /* Bitmap de travail, au pas du driver. */
    uint8_t  bitmap[SP_PITCH * SP_LINES];

    /* ★ SP5 — ordonnanceur : un fil dédié réveillé à la date d'affichage.
     * Il ne peut pas s'agir du fil de décodage (il ne se réveille qu'à l'arrivée
     * d'un paquet, donc trop tôt) ni du fil du vout (on n'appelle pas le driver
     * par image). Un fil à part, réveillé sur échéance, ne fait qu'un appel par
     * transition. */
    vlc_thread_t thread;
    vlc_mutex_t  lock;
    vlc_cond_t   wait;
    bool         b_thread;
    bool         b_quit;
    sp_entry_t  *queue;           /* SP_QUEUE entrées                          */
    unsigned     i_head, i_tail;
    vlc_tick_t   i_hide_at;       /* échéance de l'incrustation en cours       */
    vlc_tick_t   i_shown_at;      /* date réelle de la dernière incrustation   */
    /* ⚠ Un rafraîchissement périodique de l'incrustation a existé ici (deux fois
     * par seconde). Il n'apportait RIEN à la visibilité — le vrai défaut était
     * `ClearSP` — et il rejouait toute la séquence, sondes comprises : c'est une
     * des deux causes des saccades constatées en lecture. Ne pas le remettre. */
    bool         b_visible;

    /* Mise au point : /tmp/hw_sp_nohide neutralise l'EFFACEMENT en gardant
     * l'ordonnancement exact de l'AFFICHAGE. C'est le seul A/B qui sépare un
     * défaut de calage d'un défaut de l'effacement lui-même. */
    bool     b_nohide;
    /* /tmp/hw_sp_stick : n'affiche QUE le premier sous-titre et le laisse en
     * place jusqu'à la fin. Expérience décisive : si un sous-titre figé est
     * visible sur toutes les captures, l'affichage n'est pas transitoire et le
     * défaut est de temporisation ; s'il n'est visible que sur une, il l'est. */
    bool     b_stick, b_stuck;
    /* /tmp/hw_sp_direct : incruste depuis le FIL DE DÉCODAGE, à l'arrivée du
     * paquet, comme avant l'ordonnanceur. Seule différence restante entre le
     * run où quatre sous-titres se voyaient et ceux où un seul se voit : le fil
     * d'où partent les appels driver. */
    bool     b_direct;
    bool     b_probe;             /* sondes de diagnostic (coûteuses)          */
    /* Surbrillance des menus : on garde une copie de l'incrustation en cours
     * pour pouvoir la reposer quand l'utilisateur change de bouton — la
     * surbrillance bouge SANS nouveau paquet SPU. Événementiel, jamais
     * périodique. */
    sp_entry_t   cur;
    bool         b_have_cur;
    bool         b_hl_dirty;
    uint8_t     *p_scratch;       /* bitmap de travail (recadrage)             */
    /* 10.2 : copie de travail du paquet SPU BRUT. Sur ce système le pilote
     * analyse lui-même le paquet ; il faut donc y réécrire les couleurs de la
     * surbrillance, sans quoi il redessine le calque aux couleurs normales. */
    uint8_t     *p_pkt_scratch;
    uint32_t i_shown, i_failed, i_late, i_dropped;
    bool     b_warned_nohw;
    /* Mise au point : /tmp/hw_sp_nohide désarme l'effacement. Sert à séparer un
     * défaut de RENDU (rien ne s'affiche jamais) d'un défaut de TEMPORISATION
     * (on affiche et on efface trop tôt, le décodeur tournant en avance sur
     * l'affichage). Sans ce partage, les deux causes sont indiscernables. */
    bool     b_dump;              /* dépose les paquets bruts dans /tmp        */
    unsigned i_dumped;
} dvddriver_spu_sys_t;

/*****************************************************************************
 * Décodage RLE → bitmap 2 bits/pixel
 *****************************************************************************
 * Le flux RLE est une suite de codes à base de quartets, entrelacée en deux
 * trames (lignes paires / impaires), chacune commençant à un décalage donné par
 * la commande 0x06. Un code vaut (longueur << 2) | couleur ; il se lit sur 1, 2,
 * 3 ou 4 quartets selon sa magnitude, et une longueur nulle signifie « jusqu'au
 * bout de la ligne ». Chaque ligne se termine sur une frontière d'octet.
 * (Même algorithme que modules/codec/spudec/parse.c, mais écrivant directement
 * le bitmap packé du driver plutôt qu'un subpicture_t : ni conversion, ni
 * allocation, ni copie intermédiaire.)
 *****************************************************************************/
static inline unsigned AddNibble(unsigned i_code, const uint8_t *p_src,
                                 unsigned *pi_index)
{
    if( *pi_index & 1 )
        return (i_code << 4) | (p_src[(*pi_index)++ >> 1] & 0xf);
    return (i_code << 4) | (p_src[(*pi_index)++ >> 1] >> 4);
}

/* Écrit `len` pixels de valeur `color` (0..3) à partir de (x, y). */
static void SpPutRun(uint8_t *p_bitmap, unsigned x, unsigned y, unsigned len,
                     unsigned color)
{
    if( y >= SP_LINES )
        return;
    uint8_t *p_line = p_bitmap + (size_t) y * SP_PITCH;
    for( unsigned i = 0; i < len; i++ )
    {
        const unsigned px = x + i;
        if( px >= SP_PITCH * 4 )
            break;
        const unsigned shift = 6 - 2 * (px & 3);      /* poids fort d'abord */
        p_line[px >> 2] = (uint8_t) ((p_line[px >> 2] & ~(3u << shift))
                                     | ((color & 3u) << shift));
    }
}

/* Décode les deux trames dans le bitmap, aux coordonnées ABSOLUES du
 * sous-titre. Renvoie false si le flux sort des bornes du paquet. */
static bool SpDecodeRLE(decoder_t *p_dec, const uint8_t *p_spu, unsigned i_size,
                        const unsigned pi_offset[2], unsigned x1, unsigned y1,
                        unsigned width, unsigned height, uint8_t *p_bitmap)
{
    /* Les décalages de la commande 0x06 sont relatifs au début du PAQUET ;
     * comme parse.c, on travaille en quartets à partir de l'octet 4. */
    unsigned pi_table[2] = { (pi_offset[0] - 4) << 1, (pi_offset[1] - 4) << 1 };
    const uint8_t *p_data = p_spu + 4;
    const unsigned i_data_size = i_size > 4 ? i_size - 4 : 0;

    for( unsigned i_y = 0; i_y < height; i_y++ )
    {
        unsigned *pi_index = &pi_table[i_y & 1];   /* trame paire / impaire */
        unsigned i_x = 0;

        while( i_x < width )
        {
            unsigned i_code = 0;
            for( unsigned i_min = 1; i_min <= 0x40 && i_code < i_min; i_min <<= 2 )
            {
                if( (*pi_index >> 1) + 4 >= i_data_size )
                {
                    msg_Warn( p_dec, "paquet SPU tronqué (lecture RLE hors bornes)" );
                    return false;
                }
                i_code = AddNibble( i_code, p_data, pi_index );
            }
            /* 14 bits de tête à zéro = « reste de la ligne ». */
            unsigned i_len = i_code >> 2;
            if( i_code < 0x0004 || i_len > width - i_x )
                i_len = width - i_x;

            SpPutRun( p_bitmap, x1 + i_x, y1 + i_y, i_len, i_code & 3 );
            i_x += i_len;
        }
        /* Fin de ligne : réalignement sur une frontière d'octet. */
        *pi_index += *pi_index & 1;
    }
    return true;
}

/* Palette du disque (CLUT AYVU du démultiplexeur) au format du driver :
 * 4 octets par entrée, { 0, Y, Cr, Cb }. */
static void SpBuildPalette(const uint32_t *p_clut, uint8_t pal[64])
{
    memset( pal, 0, 64 );
    if( p_clut[0] )                      /* [0] = drapeau « palette présente » */
    {
        for( int k = 0; k < 16; k++ )
        {
            const uint32_t i_ayvu = p_clut[1 + k];
            pal[k * 4 + 1] = (uint8_t) (i_ayvu >> 16);   /* Y  */
            pal[k * 4 + 2] = (uint8_t) (i_ayvu >> 8);    /* Cr */
            pal[k * 4 + 3] = (uint8_t)  i_ayvu;          /* Cb */
        }
        return;
    }
    /* Pas de CLUT : repli en niveaux de gris, index 0 noir → 15 blanc. */
    for( int k = 0; k < 16; k++ )
    {
        pal[k * 4 + 1] = (uint8_t) (16 + k * 15);
        pal[k * 4 + 2] = 0x80;
        pal[k * 4 + 3] = 0x80;
    }
}

/*****************************************************************************
 * Surbrillance des menus DVD
 *****************************************************************************
 * ⚠ La surbrillance n'est PAS dans le paquet SPU. C'est `vout_subpictures.c`
 * qui l'applique au `subpicture_t` produit par `spudec` : il lit sur l'objet
 * input les variables posées par le démultiplexeur dvdnav — `highlight`,
 * `x-start`/`y-start`/`x-end`/`y-end` et `menu-palette` — puis RECADRE la région
 * sur le rectangle du bouton et FORCE la palette (UpdateSPU + force_crop /
 * force_palette).
 * Comme ce module ne produit aucun `subpicture_t`, tout ce mécanisme était
 * court-circuité : les menus s'affichaient sans surbrillance. On refait donc
 * ici les deux mêmes opérations — le plan SP sait faire l'une comme l'autre.
 * `p_dec->obj.parent` EST l'objet input (input_DecoderNew le passe en parent),
 * donc les variables sont lisibles directement. Si `highlight` n'existe pas
 * (pas de menus, lecture normale), tout ceci est un no-op.
 *****************************************************************************/
static vlc_object_t *SpInput(decoder_t *p_dec)
{
    return p_dec->obj.parent;
}

/* Renvoie true si une surbrillance est active ; remplit alors le rectangle du
 * bouton et la palette/contrastes du menu. */
static bool SpGetHighlight(decoder_t *p_dec, int rect[4], uint8_t pal[64],
                           uint16_t *pi_colors, uint16_t *pi_contrasts)
{
    vlc_object_t *p_input = SpInput( p_dec );
    vlc_value_t val;

    if( p_input == NULL
     || var_Get( p_input, "highlight", &val ) != VLC_SUCCESS || !val.b_bool )
        return false;

    /* Même verrou que dvdnav pour poser ces valeurs : sans lui on peut lire un
     * rectangle à moitié mis à jour au moment d'un changement de bouton. */
    vlc_global_lock( VLC_HIGHLIGHT_MUTEX );
    rect[0] = var_GetInteger( p_input, "x-start" );
    rect[1] = var_GetInteger( p_input, "y-start" );
    rect[2] = var_GetInteger( p_input, "x-end" );
    rect[3] = var_GetInteger( p_input, "y-end" );

    if( var_Get( p_input, "menu-palette", &val ) == VLC_SUCCESS
     && val.p_address != NULL )
    {
        /* menu-palette : 4 entrées { Y, U, V, alpha 0..255 } (cf. dvdnav.c).
         * Le driver veut { 0, Y, Cr, Cb } par entrée, et notre descripteur
         * donne par valeur de pixel un index de palette (4 bits) et un
         * contraste (4 bits). On charge donc les 4 couleurs du menu dans les
         * entrées 0..3 et on fait pointer chaque valeur de pixel sur la sienne. */
        const uint8_t (*mp)[4] = val.p_address;
        uint16_t i_co = 0, i_ct = 0;
        memset( pal, 0, 64 );
        for( int i = 0; i < 4; i++ )
        {
            pal[i * 4 + 1] = mp[i][0];                    /* Y  */
            pal[i * 4 + 2] = mp[i][2];                    /* Cr */
            pal[i * 4 + 3] = mp[i][1];                    /* Cb */
            i_co |= (uint16_t) i << (4 * i);              /* index i → entrée i */
            i_ct |= (uint16_t) ((mp[i][3] * 15 + 127) / 255) << (4 * i);
        }
        *pi_colors    = i_co;
        *pi_contrasts = i_ct;
    }
    vlc_global_unlock( VLC_HIGHLIGHT_MUTEX );
    return true;
}

/* Recadrage : tout ce qui est hors du rectangle du bouton devient la valeur 0
 * (transparente), exactement comme le `force_crop` de VLC. */
static void SpCropToHighlight(uint8_t *p_bitmap, const int rect[4])
{
    const int x1 = rect[0] < 0 ? 0 : rect[0];
    const int y1 = rect[1] < 0 ? 0 : rect[1];
    const int x2 = rect[2] > (int) (SP_PITCH * 4) ? (int) (SP_PITCH * 4) : rect[2];
    const int y2 = rect[3] > (int) SP_LINES ? (int) SP_LINES : rect[3];

    for( unsigned y = 0; y < SP_LINES; y++ )
    {
        uint8_t *p_line = p_bitmap + (size_t) y * SP_PITCH;
        if( (int) y < y1 || (int) y >= y2 )
        {
            memset( p_line, 0, SP_PITCH );
            continue;
        }
        for( int x = 0; x < (int) (SP_PITCH * 4); x++ )
            if( x < x1 || x >= x2 )
                p_line[x >> 2] &= (uint8_t) ~(3u << (6 - 2 * (x & 3)));
    }
}

/* Device matériel courant. ⚠ RELU sur le bus à chaque usage, jamais mis en
 * cache : le décodeur vidéo peut le fermer à tout moment. */
static dvddriver_ctx *SpHw(decoder_t *p_dec)
{
    dvddriver_ctx *p_hw =
        var_GetAddress( p_dec->obj.libvlc, DVDDRIVER_VAR_CTX );
    return ( p_hw != NULL && dvddriver_sp_usable( p_hw ) ) ? p_hw : NULL;
}

/*****************************************************************************
 * Analyse du paquet et mise en file
 *****************************************************************************/
static void SpParseAndQueue(decoder_t *p_dec)
{
    dvddriver_spu_sys_t *p_sys = p_dec->p_sys;
    const uint8_t *p = p_sys->buffer;
    const unsigned i_size = p_sys->i_spu_size;

    if( i_size < 5 )
        return;
    unsigned i_dcsq = (unsigned) ((p[2] << 8) | p[3]);

    /* Valeurs par défaut : image entière, tout opaque. */
    unsigned x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    unsigned pi_offset[2] = { 0, 0 };
    uint16_t i_colors = 0, i_contrasts = 0;
    bool b_has_offsets = false, b_has_area = false, b_start = false;
    int64_t i_start_us = 0, i_stop_us = -1;

    /* Parcours de la CHAÎNE de séquences : chacune porte son propre délai
     * (unités de 1024/90000 s) et se termine par 0xff. Les délais sont à NOTRE
     * charge : le driver ignore les commandes d'apparition/disparition. */
    /* 10.2 : offsets des octets de commande DANS LE PAQUET, dans l'ordre —
     * c'est exactement ce que le DVD Player d'Apple passe à `ApplySPDCSQ`. */
    uint16_t pi_cmd[SP_CMD_MAX];
    unsigned i_ncmd = 0;

    unsigned i_guard = 0;
    while( i_dcsq + 4 <= i_size && i_guard++ < 32 )
    {
        const unsigned i_delay = (unsigned) ((p[i_dcsq] << 8) | p[i_dcsq + 1]);
        const unsigned i_next  = (unsigned) ((p[i_dcsq + 2] << 8) | p[i_dcsq + 3]);
        const int64_t i_date_us = ((int64_t) i_delay * 1024 * 100) / 9;
        unsigned i = i_dcsq + 4;
        bool b_end = false;

        while( i < i_size && !b_end )
        {
            switch( p[i] )   /* relevé de l'offset, commandes CONNUES seulement */
            {
            case SPU_CMD_FORCE_DISPLAY:  case SPU_CMD_START_DISPLAY:
            case SPU_CMD_STOP_DISPLAY:   case SPU_CMD_SET_PALETTE:
            case SPU_CMD_SET_ALPHACHANNEL: case SPU_CMD_SET_COORDINATES:
            case SPU_CMD_SET_OFFSETS:    case SPU_CMD_SET_COLCON:
                /* ⚠⚠ PREMIÈRE DCSQ SEULEMENT. La chaîne en contient d'autres, à
                 * des dates ultérieures, et la seconde porte presque toujours le
                 * `STOP_DISPLAY` (0x02) qui EFFACE le drapeau d'affichage
                 * `ctx[0x1C4]`. Les rejouer toutes revient à dire « affiche »
                 * puis « arrête » dans le même souffle : mesuré, 0x1C4 retombait
                 * à 0 et rien n'apparaissait, alors que le blit tournait bien
                 * (0x1B4 = 196). Le DVD Player n'applique que les commandes de la
                 * DCSQ courante — les cinq de la trace (00/01, 03, 04, 05, 06) —
                 * et c'est notre propre échéance (`i_hide`) qui retire ensuite le
                 * sous-titre. */
                if( i_guard == 1 && i_ncmd < SP_CMD_MAX )
                    pi_cmd[i_ncmd++] = (uint16_t) i;
                break;
            default: break;
            }
            switch( p[i] )
            {
            case SPU_CMD_FORCE_DISPLAY:
            case SPU_CMD_START_DISPLAY:
                if( !b_start ) { b_start = true; i_start_us = i_date_us; }
                i += 1;
                break;
            case SPU_CMD_STOP_DISPLAY:
                i_stop_us = i_date_us;
                i += 1;
                break;
            case SPU_CMD_SET_PALETTE:
                if( i + 3 > i_size ) return;
                i_colors = (uint16_t) ((p[i + 1] << 8) | p[i + 2]);
                i += 3;
                break;
            case SPU_CMD_SET_ALPHACHANNEL:
                if( i + 3 > i_size ) return;
                i_contrasts = (uint16_t) ((p[i + 1] << 8) | p[i + 2]);
                i += 3;
                break;
            case SPU_CMD_SET_COORDINATES:
                if( i + 7 > i_size ) return;
                x1 = ((unsigned) p[i + 1] << 4) | (p[i + 2] >> 4);
                x2 = (((unsigned) p[i + 2] & 0xf) << 8) | p[i + 3];
                y1 = ((unsigned) p[i + 4] << 4) | (p[i + 5] >> 4);
                y2 = (((unsigned) p[i + 5] & 0xf) << 8) | p[i + 6];
                b_has_area = true;
                i += 7;
                break;
            case SPU_CMD_SET_OFFSETS:
                if( i + 5 > i_size ) return;
                pi_offset[0] = (unsigned) ((p[i + 1] << 8) | p[i + 2]);
                pi_offset[1] = (unsigned) ((p[i + 3] << 8) | p[i + 4]);
                b_has_offsets = true;
                i += 5;
                break;
            case SPU_CMD_SET_COLCON:
                /* Contrastes par zone (menus) : non géré, on saute le bloc. */
                if( i + 3 > i_size ) return;
                i += 1 + ((unsigned) (p[i + 1] << 8) | p[i + 2]);
                break;
            case SPU_CMD_END:
            default:
                b_end = true;
                break;
            }
        }
        if( i_next == i_dcsq || i_next == 0 || i_next >= i_size )
            break;
        i_dcsq = i_next;
    }


    /* Un paquet sans données RLE ni zone d'affichage n'est qu'un ordre
     * d'effacement (fin d'un sous-titre précédent). */
    if( !b_has_offsets || !b_has_area || x2 < x1 || y2 < y1 )
    {
        /* Paquet sans données ni zone = ordre d'effacement. On le programme
         * comme les autres, à sa date, plutôt que d'effacer tout de suite. */
        vlc_mutex_lock( &p_sys->lock );
        p_sys->i_hide_at = mdate();
        vlc_cond_signal( &p_sys->wait );
        vlc_mutex_unlock( &p_sys->lock );
        return;
    }
    if( pi_offset[0] < 4 || pi_offset[1] < 4 )
        return;

    const unsigned i_width  = x2 - x1 + 1;
    const unsigned i_height = y2 - y1 + 1;
    if( i_width == 0 || i_height == 0 || y2 >= SP_LINES )
        return;

    memset( p_sys->bitmap, 0, sizeof( p_sys->bitmap ) );
    if( !SpDecodeRLE( p_dec, p, i_size, pi_offset, x1, y1,
                      i_width, i_height, p_sys->bitmap ) )
    {
        p_sys->i_failed++;
        return;
    }

    const uint32_t *p_clut = p_dec->fmt_in.subs.spu.palette;

    /* ★ SP5 — CALAGE SUR LA DATE D'AFFICHAGE, et non sur l'arrivée du paquet.
     * Le décodeur tourne en avance sur l'affichage (d'autant plus que le cache
     * DVD de ce projet est profond) : incruster dès l'arrivée faisait apparaître
     * ET disparaître les sous-titres trop tôt — mesuré, 4 captures sur 12
     * contre 7 sur 12 en rendu logiciel sur la même séquence.
     * `decoder_GetDisplayDate` convertit un horodatage de décodage en date
     * système. S'il n'est pas disponible (horloge pas encore établie), on se
     * rabat sur « maintenant » : mieux vaut un sous-titre en avance qu'aucun. */
    const vlc_tick_t i_pts = p_sys->i_pts;
    vlc_tick_t i_show = decoder_GetDisplayDate( p_dec, i_pts + i_start_us );
    vlc_tick_t i_hide = i_stop_us > i_start_us
                      ? decoder_GetDisplayDate( p_dec, i_pts + i_stop_us ) : 0;
    if( i_show == VLC_TICK_INVALID )
        i_show = mdate();
    if( i_hide == VLC_TICK_INVALID )
        i_hide = i_stop_us > i_start_us ? i_show + (i_stop_us - i_start_us) : 0;

    /* ⚠ ROBUSTESSE AUTOUR D'UN SEEK. `decoder_GetDisplayDate` s'appuie sur
     * l'horloge de référence de l'entrée ; juste après un saut elle est remise
     * à zéro et rend des dates DÉJÀ PASSÉES — mesuré jusqu'à 3,8 s de retard,
     * et le journal de VLC le dit lui-même (« no reference clock », « Could not
     * get display date »). Suivre ces dates revient à afficher un sous-titre
     * longtemps après son moment, puis à l'effacer aussitôt.
     * Règle : une date d'affichage périmée de plus d'une demi-seconde n'est pas
     * crédible → on affiche maintenant et on DÉCALE la fin d'autant, ce qui
     * préserve la durée voulue par le disque. */
    const vlc_tick_t i_now = mdate();
    if( i_show < i_now - VLC_TICK_FROM_MS(500) )
    {
        const vlc_tick_t i_shift = i_now - i_show;
        i_show = i_now;
        if( i_hide != 0 )
            i_hide += i_shift;
    }
    /* Une fin antérieure au début ne veut rien dire : on retombe sur la durée
     * nominale du DCSQ, ou sur « pas d'échéance ». */
    if( i_hide != 0 && i_hide <= i_show )
        i_hide = i_stop_us > i_start_us
               ? i_show + (i_stop_us - i_start_us) : 0;

    if( p_sys->b_direct )
    {
        dvddriver_sp_picture sp;
        memset( &sp, 0, sizeof( sp ) );
        sp.bitmap    = p_sys->bitmap;
        sp.lines     = y2 + 1;
        sp.colors    = i_colors;
        sp.contrasts = i_contrasts;
        sp.hide_in_us = -1;
        SpBuildPalette( p_clut, sp.palette );
        if( dvddriver_sp_submit( SpHw( p_dec ), &sp, NULL ) )
            p_sys->i_shown++;
        else
            p_sys->i_failed++;
        return;
    }

    vlc_mutex_lock( &p_sys->lock );
    if( p_sys->i_head - p_sys->i_tail >= SP_QUEUE )
    {
        /* File pleine : on jette le PLUS ANCIEN non affiché plutôt que le
         * nouveau — un sous-titre récent est toujours plus utile qu'un ancien
         * dont la date est probablement déjà passée. */
        p_sys->i_tail++;
        p_sys->i_dropped++;
    }
    sp_entry_t *e = &p_sys->queue[p_sys->i_head % SP_QUEUE];
    memcpy( e->bitmap, p_sys->bitmap, sizeof( e->bitmap ) );
    e->lines     = y2 + 1;
    e->colors    = i_colors;
    e->contrasts = i_contrasts;
    e->i_show    = i_show;
    e->i_hide    = i_hide;

    SpBuildPalette( p_clut, e->palette );
    /* 10.2 : le pilote décode le paquet lui-même — on le conserve tel quel, avec
     * les offsets de commande relevés ci-dessus. Un paquet trop gros pour notre
     * réserve laisse simplement `packet_size` à 0 : le backend retombe alors sur
     * le bitmap, et le rendu logiciel prendra le relais si le blit ne produit
     * rien. */
    if( i_size <= SP_PKT_MAX )
    {
        memcpy( e->packet, p, i_size );
        e->packet_size = i_size;
        e->cmd_count   = i_ncmd;
        memcpy( e->cmd_off, pi_cmd, i_ncmd * sizeof( pi_cmd[0] ) );
    }
    else
    {
        e->packet_size = 0;
        e->cmd_count   = 0;
    }
    p_sys->i_head++;
    vlc_cond_signal( &p_sys->wait );
    vlc_mutex_unlock( &p_sys->lock );

    msg_Dbg( p_dec, "SP4 paquet %u o : zone %u,%u→%u,%u (%ux%u) couleurs=%04x "
             "contrastes=%04x clut=%s → affichage dans %lld ms, durée %lld ms",
             i_size, x1, y1, x2, y2, i_width, i_height, i_colors, i_contrasts,
             p_clut[0] ? "disque" : "repli",
             (long long) ((i_show - mdate()) / 1000),
             (long long) (i_hide ? (i_hide - i_show) / 1000 : -1) );
}

/* Assemble la picture à remettre au driver, surbrillance de menu comprise.
 * Appelé sous le verrou ; `p_scratch` n'est touché que par le fil. */
static void SpBuildPicture(decoder_t *p_dec, const sp_entry_t *e,
                           dvddriver_sp_picture *sp)
{
    dvddriver_spu_sys_t *p_sys = p_dec->p_sys;

    memset( sp, 0, sizeof( *sp ) );
    sp->lines     = e->lines;
    sp->colors    = e->colors;
    sp->contrasts = e->contrasts;
    sp->hide_in_us = -1;          /* l'échéance est tenue par le fil, pas là-bas */
    memcpy( sp->palette, e->palette, sizeof( sp->palette ) );
    /* 10.2 : le backend s'en sert à la place du bitmap (cf. dvddriver_sp_submit). */
    sp->packet      = e->packet;
    sp->packet_size = e->packet_size;
    sp->cmd_off     = e->cmd_off;
    sp->cmd_count   = e->cmd_count;

    int hl[4];
    if( p_sys->p_scratch != NULL
     && SpGetHighlight( p_dec, hl, sp->palette, &sp->colors, &sp->contrasts ) )
    {
        memcpy( p_sys->p_scratch, e->bitmap, SP_PITCH * SP_LINES );
        SpCropToHighlight( p_sys->p_scratch, hl );
        sp->bitmap = p_sys->p_scratch;
        sp->lines  = SP_LINES;

        /* ★★★ 10.2 — RÉÉCRIRE LES COULEURS DANS LE PAQUET BRUT.
         * Sur 10.3/10.4 le pilote blitte depuis NOTRE descripteur : lui donner
         * `colors`/`contrasts` de la palette de menu suffit. Sur 10.2 le pilote
         * est un binaire tout différent qui ANALYSE le paquet SPU brut qu'on lui
         * dépose — il y relit donc les commandes de couleur (0x03) et d'opacité
         * (0x04) D'ORIGINE, celles du calque non sélectionné, et redessine sans
         * surbrillance. D'où : sous-titres matériels parfaits sur Jaguar (leurs
         * couleurs sont dans le paquet) mais surbrillance de menu invisible.
         * On lui remet donc une COPIE du paquet dont ces deux commandes portent
         * les valeurs du menu. `cmd_off` donne l'emplacement de chaque octet de
         * commande : aucune analyse à refaire ici. */
        if( e->packet_size > 0 && e->packet_size <= SP_PKT_MAX
         && p_sys->p_pkt_scratch != NULL )
        {
            uint8_t *q = p_sys->p_pkt_scratch;
            memcpy( q, e->packet, e->packet_size );
            for( unsigned k = 0; k < e->cmd_count; k++ )
            {
                const unsigned o = e->cmd_off[k];
                if( o + 2 >= e->packet_size )
                    continue;
                if( q[o] == SPU_CMD_SET_PALETTE )
                {
                    q[o + 1] = (uint8_t) (sp->colors >> 8);
                    q[o + 2] = (uint8_t) (sp->colors & 0xff);
                }
                else if( q[o] == SPU_CMD_SET_ALPHACHANNEL )
                {
                    q[o + 1] = (uint8_t) (sp->contrasts >> 8);
                    q[o + 2] = (uint8_t) (sp->contrasts & 0xff);
                }
            }
            sp->packet = q;
        }
    }
    else
        sp->bitmap = e->bitmap;
}

/*****************************************************************************
 * Fil d'ordonnancement : incruste et efface À LA DATE VOULUE
 *****************************************************************************/
static void *SpThread(void *p_data)
{
    decoder_t *p_dec = p_data;
    dvddriver_spu_sys_t *p_sys = p_dec->p_sys;

    vlc_mutex_lock( &p_sys->lock );
    for( ;; )
    {
        if( p_sys->b_quit )
            break;

        /* ★★★ CHANGEMENT DE BOUTON — TRAITÉ AVANT TOUTE ÉCHÉANCE.
         *
         * ⚠⚠ Ce bloc vivait plus bas, APRÈS le calcul d'échéance et les attentes.
         * Il n'était donc atteignable que si une échéance venait d'expirer — or
         * un changement de bouton n'est PAS une échéance. Quand rien n'était en
         * file et rien d'affiché, l'échéance valait zéro, le fil repartait en
         * `vlc_cond_wait` : le rappel le réveillait bien, la boucle recalculait
         * zéro, et il se rendormait sans jamais exécuter le rafraîchissement.
         * Résultat mesuré : 30 changements de bouton, 7 calques analysés, **une
         * seule incrustation** — la surbrillance apparaissait une fois puis ne
         * bougeait plus, ni au clavier ni à la souris.
         * C'est une action IMMÉDIATE : elle se traite en tête de boucle.
         *
         * Il suffit d'avoir une incrustation en mémoire : on la repose avec le
         * nouveau rectangle et la nouvelle palette. Le rappel `highlight`
         * n'existe QUE dans les menus, donc cela ne peut pas ressusciter un
         * sous-titre de film. On annule aussi l'échéance d'effacement : dans un
         * menu la surbrillance doit rester tant qu'on y est. */
        if( p_sys->b_hl_dirty && p_sys->b_have_cur )
        {
            p_sys->b_hl_dirty = false;
            dvddriver_sp_picture sp;
            SpBuildPicture( p_dec, &p_sys->cur, &sp );
            vlc_mutex_unlock( &p_sys->lock );
            dvddriver_sp_submit( SpHw( p_dec ), &sp, NULL );
            vlc_mutex_lock( &p_sys->lock );
            p_sys->b_visible = true;
            p_sys->i_hide_at = 0;
            continue;
        }

        /* Prochaine échéance : soit l'effacement de l'incrustation en cours,
         * soit l'affichage du sous-titre en tête de file. */
        vlc_tick_t i_deadline = 0;
        const bool b_has_next = p_sys->i_head != p_sys->i_tail;
        if( b_has_next )
            i_deadline = p_sys->queue[p_sys->i_tail % SP_QUEUE].i_show;
        if( p_sys->b_visible && p_sys->i_hide_at != 0
         && (i_deadline == 0 || p_sys->i_hide_at < i_deadline) )
            i_deadline = p_sys->i_hide_at;

        if( i_deadline == 0 )
        {
            vlc_cond_wait( &p_sys->wait, &p_sys->lock );
            continue;
        }
        if( mdate() < i_deadline )
        {
            vlc_cond_timedwait( &p_sys->wait, &p_sys->lock, i_deadline );
            continue;
        }

        /* Échéance atteinte. */
        /* ⚠ L'échéance doit être CONSOMMÉE dans tous les cas, y compris quand on
         * choisit de ne rien faire : sinon la boucle se réveille aussitôt sur la
         * même échéance déjà passée et tourne à vide EN TENANT LE VERROU, ce qui
         * affame le fil de décodage (constaté : VLC bloqué à l'arrêt sur
         * « waiting decoder fifos to empty », 42 % de CPU). */
        if( p_sys->b_visible && p_sys->i_hide_at != 0
         && mdate() >= p_sys->i_hide_at
         && (!b_has_next
             || p_sys->i_hide_at <= p_sys->queue[p_sys->i_tail % SP_QUEUE].i_show) )
        {
            const vlc_tick_t i_shown_at = p_sys->i_shown_at;
            p_sys->i_hide_at = 0;
            if( p_sys->b_nohide )
                continue;
            p_sys->b_visible = false;
            vlc_mutex_unlock( &p_sys->lock );
            dvddriver_sp_hide( SpHw( p_dec ) );
            msg_Dbg( p_dec, "SP5 effacé après %lld ms d'affichage",
                     (long long) ((mdate() - i_shown_at) / 1000) );
            vlc_mutex_lock( &p_sys->lock );
            continue;
        }


        if( p_sys->b_stuck )
        {
            p_sys->i_tail = p_sys->i_head;   /* on ignore la suite du flux */
            p_sys->i_hide_at = 0;
            vlc_cond_wait( &p_sys->wait, &p_sys->lock );
            continue;
        }

        if( !b_has_next )
            continue;

        /* Copie locale : le driver est appelé HORS du verrou (il prend le sien,
         * et un appel driver peut durer ; garder les deux verrous imbriqués
         * exposerait à un interblocage avec le fil de décodage). */
        /* ★★★ NE PAS CONSOMMER L'ENTRÉE SI LE CONTEXTE MATÉRIEL N'EST PAS LÀ.
         * Le calque peut être mis en file AVANT que le décodeur vidéo n'ait
         * ouvert son contexte (c'est même la règle dans un menu). L'échéance
         * d'affichage tombait alors trop tôt, la soumission échouait, et
         * l'entrée était consommée quand même — perdue. Sur un menu ANIMÉ le
         * paquet suivant rattrapait la chose ; sur un menu FIXE il n'y en a pas
         * d'autre, et la surbrillance ne revenait jamais (mesuré sur Chihiro :
         * « 0 incrustés, 1 en échec »).
         * On repousse donc l'échéance de 100 ms sans toucher à la file. */
        if( SpHw( p_dec ) == NULL )
        {
            vlc_cond_timedwait( &p_sys->wait, &p_sys->lock,
                                mdate() + VLC_TICK_FROM_MS(100) );
            continue;
        }
        sp_entry_t *e = &p_sys->queue[p_sys->i_tail % SP_QUEUE];
        p_sys->cur = *e;
        p_sys->b_have_cur = true;
        p_sys->b_hl_dirty = false;
        dvddriver_sp_picture sp;
        SpBuildPicture( p_dec, e, &sp );
        const vlc_tick_t i_hide = e->i_hide;
        const vlc_tick_t i_late = mdate() - e->i_show;
        p_sys->i_tail++;
        p_sys->b_visible = true;
        p_sys->i_hide_at = i_hide;
        p_sys->i_shown_at = mdate();
        if( p_sys->b_stick )
            p_sys->b_stuck = true;
        vlc_mutex_unlock( &p_sys->lock );
        msg_Dbg( p_dec, "SP5 affiché (retard %lld ms) pour %lld ms",
                 (long long) (i_late / 1000),
                 (long long) (i_hide ? (i_hide - mdate()) / 1000 : -1) );

        if( i_late > VLC_TICK_FROM_MS(200) )
            p_sys->i_late++;
        /* ⚠ SONDES HORS DU CHEMIN NORMAL. Chacune balaie tout le plan ARGB
         * (768 × 576 mots) en mémoire GPU NON CACHÉE, trois fois par
         * incrustation, et le fait SOUS LE VERROU que prend aussi le décodage
         * vidéo : c'est l'autre cause des saccades. Elles ne servent qu'au
         * diagnostic → activées par /tmp/hw_sp_probe uniquement. */
        uint32_t pr[8] = { 0, 0, 0, 0, 0, 0, 0, 0 };
        if( dvddriver_sp_submit( SpHw( p_dec ), &sp,
                                 p_sys->b_probe ? pr : NULL ) )
            p_sys->i_shown++;
        else
            p_sys->i_failed++;
        int32_t dw[6] = { 0, 0, 0, 0, 0, 0 };
        dvddriver_sp_display_words( SpHw( p_dec ), dw );
        if( p_sys->b_probe )
        msg_Dbg( p_dec, "SP5 #%u : source=%08x cc=%08x — plan avant=%u, "
                 "après SetSPBuffer=%u (drapeau %u), à la fin=%u  %s",
                 p_sys->i_shown, pr[3], pr[6], pr[1], pr[5], pr[7], pr[0],
                 pr[5] == 0 ? "← LE BLIT NE PRODUIT RIEN"
                 : pr[0] == 0 ? "← PRODUIT PUIS EFFACÉ" : "" );
        if( p_sys->b_probe )
            msg_Dbg( p_dec, "SP-ÉTAT : ligneDepart(0x1B4)=%d affichage(0x1C4)=%d "
                     "aRedessiner(0x1D0)=%d | plan %d,%d→%d,%d | bouton %d,%d",
                     dw[0], dw[1], dw[2],
                     (int16_t) (dw[3] >> 16), (int16_t) dw[3],
                     (int16_t) (dw[4] >> 16), (int16_t) dw[4],
                     (int16_t) (dw[5] >> 16), (int16_t) dw[5] );
        vlc_mutex_lock( &p_sys->lock );
    }
    vlc_mutex_unlock( &p_sys->lock );
    return NULL;
}

/*****************************************************************************
 * Decode : réassemblage puis analyse
 *****************************************************************************/
static int Decode(decoder_t *p_dec, block_t *p_block)
{
    dvddriver_spu_sys_t *p_sys = p_dec->p_sys;


    if( p_block == NULL )                                    /* pas de drain */
        return VLCDEC_SUCCESS;
    if( p_block->i_flags & BLOCK_FLAG_CORRUPTED )
    {
        p_sys->i_spu = p_sys->i_spu_size = 0;
        block_Release( p_block );
        return VLCDEC_SUCCESS;
    }
    /* ★★★ NE PAS JETER SUR DISCONTINUITÉ — c'était la cause de l'absence totale
     * de surbrillance dans les menus (2026-08-05).
     * Une discontinuité invalide le paquet PARTIEL en cours de réassemblage, pas
     * le bloc qui l'accompagne. Or dans un menu DVD, la navigation provoque un
     * saut à chaque entrée de menu et à chaque changement de bouton : les paquets
     * SPU y arrivent donc quasi TOUJOURS marqués `DISCONTINUITY`, et on les
     * jetait tous — silencieusement, sans compteur ni message, ce qui donnait
     * « le module prend la piste et n'incruste jamais rien ».
     * `spudec` (le rendu logiciel, qui lui affiche bien la surbrillance) ne
     * regarde QUE `CORRUPTED` : c'était la seule différence de traitement entre
     * les deux chemins. */
    if( p_block->i_flags & BLOCK_FLAG_DISCONTINUITY )
        p_sys->i_spu = p_sys->i_spu_size = 0;

    /* ★★ NE PLUS JETER LE PAQUET QUAND LE CONTEXTE MATÉRIEL N'EST PAS ENCORE LÀ.
     * L'en-tête de ce fichier le dit : la piste de sous-titres s'ouvre AVANT que
     * le décodeur vidéo n'ait créé son contexte (il lui faut l'en-tête de
     * séquence). Dans un MENU, le paquet qui porte le graphisme des boutons
     * arrive précisément dans cette fenêtre — on le jetait, et il n'y en avait
     * pas d'autre : plus aucune surbrillance de toute la session.
     * Or le paquet n'est pas incrusté ici : il est analysé, mis en file, et
     * soumis PLUS TARD par le fil d'ordonnancement, qui relit le contexte au
     * moment de la soumission (`dvddriver_sp_submit( SpHw( p_dec ), … )`).
     * Rien n'oblige donc à exiger le contexte dès maintenant. S'il n'apparaît
     * jamais, les soumissions échoueront et le compteur « en échec » le dira —
     * ce qui est visible, contrairement à un abandon silencieux. */
    if( SpHw( p_dec ) == NULL && !p_sys->b_warned_nohw )
    {
        p_sys->b_warned_nohw = true;
        msg_Dbg( p_dec, "paquet SPU reçu avant le contexte matériel — mis en "
                        "file, il sera incrusté dès que le décodeur vidéo aura "
                        "ouvert le sien" );
    }

    if( p_sys->i_spu_size == 0 )
    {
        /* L'horodatage du PREMIER bloc porte celui du paquet entier. */
        p_sys->i_pts = p_block->i_pts;
        if( p_block->i_buffer < 4 )
        {
            block_Release( p_block );
            return VLCDEC_SUCCESS;
        }
        p_sys->i_spu_size = (unsigned) ((p_block->p_buffer[0] << 8)
                                      |  p_block->p_buffer[1]);
        p_sys->i_spu      = 0;
        if( p_sys->i_spu_size < 5 || p_sys->i_spu_size > sizeof( p_sys->buffer ) )
        {
            p_sys->i_spu_size = 0;
            block_Release( p_block );
            return VLCDEC_SUCCESS;
        }
    }

    const unsigned i_copy = __MIN( (unsigned) p_block->i_buffer,
                                   p_sys->i_spu_size - p_sys->i_spu );
    memcpy( p_sys->buffer + p_sys->i_spu, p_block->p_buffer, i_copy );
    p_sys->i_spu += i_copy;
    block_Release( p_block );

    if( p_sys->i_spu >= p_sys->i_spu_size )
    {
        /* Mise au point : /tmp/hw_sp_dump fait déposer chaque paquet réassemblé
         * dans /tmp/spu_NN.bin, pour rejouer le décodage RLE sur l'hôte — c'est
         * du CPU pur, inutile d'occuper la machine cible pour le déboguer. */
        if( p_sys->b_dump && p_sys->i_dumped < 32 )
        {
            char psz[64];
            snprintf( psz, sizeof( psz ), "/tmp/spu_%02u.bin", p_sys->i_dumped++ );
            FILE *f = fopen( psz, "wb" );
            if( f ) { fwrite( p_sys->buffer, 1, p_sys->i_spu_size, f ); fclose( f ); }
        }
        SpParseAndQueue( p_dec );
        p_sys->i_spu = p_sys->i_spu_size = 0;
    }
    return VLCDEC_SUCCESS;
}

/* dvdnav repose `highlight` à CHAQUE changement de bouton (et `var_Set` appelle
 * les callbacks même à valeur égale) : c'est exactement le signal qu'utilise
 * VLC lui-même pour son `CropCallback`. */
static int HighlightCallback(vlc_object_t *p_this, char const *psz,
                             vlc_value_t oldval, vlc_value_t newval, void *data)
{
    VLC_UNUSED(p_this); VLC_UNUSED(psz); VLC_UNUSED(oldval); VLC_UNUSED(newval);
    decoder_t *p_dec = data;
    dvddriver_spu_sys_t *p_sys = p_dec->p_sys;

    vlc_mutex_lock( &p_sys->lock );
    p_sys->b_hl_dirty = true;
    vlc_cond_signal( &p_sys->wait );
    vlc_mutex_unlock( &p_sys->lock );
    return VLC_SUCCESS;
}

/* Seek ou changement de piste : la file porte des dates devenues fausses.
 * On la vide et on efface l'incrustation en cours — sans quoi un sous-titre
 * d'avant le saut resterait figé sur la vidéo. */
static void Flush(decoder_t *p_dec)
{
    dvddriver_spu_sys_t *p_sys = p_dec->p_sys;

    vlc_mutex_lock( &p_sys->lock );
    p_sys->i_tail = p_sys->i_head;
    p_sys->i_hide_at = 0;
    const bool b_was_visible = p_sys->b_visible;
    p_sys->b_visible = false;
    vlc_mutex_unlock( &p_sys->lock );

    p_sys->i_spu = p_sys->i_spu_size = 0;
    if( b_was_visible )
        dvddriver_sp_hide( SpHw( p_dec ) );
}

/*****************************************************************************
 * Open / Close
 *****************************************************************************/
int dvddriver_spu_Open(vlc_object_t *p_this)
{
    decoder_t *p_dec = (decoder_t *) p_this;

    if( p_dec->fmt_in.i_cat != SPU_ES
     || p_dec->fmt_in.i_codec != VLC_CODEC_SPU )
        return VLC_EGENERIC;
    if( !var_InheritBool( p_dec, "mpeg2-hwaccel-hwsubs" ) )
        return VLC_EGENERIC;

    /* ✅ 30/07 — PLUS AUCUNE GARDE DE VERSION : le plan subpicture matériel
     * incruste sur les TROIS systèmes, validé à l'œil sur iBook G3 / RV200
     * (10.2.8, 10.3.9, 10.4.11). C'est `sp_available` qui décide, et lui seul.
     * La recette 10.2 a demandé deux choses que le désassemblage seul ne pouvait
     * pas donner, et qu'une trace du DVD Player d'Apple a livrées : déposer le
     * PAQUET SPU BRUT dans le tampon de la série b (le blit l'analyse pour en
     * tirer la ligne de départ), et n'appliquer que les commandes de la PREMIÈRE
     * DCSQ (les suivantes portent le STOP_DISPLAY, qui éteignait l'affichage
     * aussitôt allumé). Cf. dvddriver_sp_submit. */
    /* ⚠ On ne peut PAS conditionner la sélection à la présence du contexte
     * matériel : mesuré sur le G3, la piste de sous-titres s'ouvre AVANT que le
     * décodeur vidéo n'ait créé le sien (il lui faut l'en-tête de séquence pour
     * connaître les dimensions). Le critère porte donc sur ce qui est déjà
     * connaissable — l'option et la présence du matériel — et le contexte est
     * relu à chaque paquet. Décliner ici rend la main à `spudec` (priorité 75)
     * et au rendu logiciel. */
    if( !var_InheritBool( p_dec, "mpeg2-hwaccel" ) || !dvddriver_available() )
    {
        msg_Dbg( p_dec, "décodage matériel inactif — sous-titres en logiciel" );
        return VLC_EGENERIC;
    }

    /* ~~⚠ ENTRÉES AVEC MENUS DVD : décliner si le contexte matériel n'est pas
     * DÉJÀ là~~ — GARDE RETIRÉE le 2026-08-05, sa prémisse est morte.
     *
     * Elle reposait sur un constat explicite : « dans un menu, le décodage
     * matériel n'est pas actif ». C'était vrai tant que les menus animés
     * cassaient l'image et faisaient démonter l'accélération ; depuis la
     * correction du BALAYAGE ALTERNÉ (cf. `HwBlock` dans libmpeg2.c), **le
     * décodage matériel est actif dans les menus et c'est la surface du GPU qui
     * est affichée**.
     * Conséquence mesurée de la garde devenue fausse : on déclinait, `spudec`
     * (logiciel) prenait la piste, et son rendu n'atteignait plus jamais l'écran
     * en mode REMPLACEMENT — `macosx_qt` laisse le cœur incruster dans le tampon
     * logiciel, qui n'est plus ce qu'on affiche. Symptôme : menus nets mais
     * AUCUNE surbrillance sur l'élément sélectionné.
     * ⇒ On prend la piste et on attend le contexte matériel, qui arrive une
     * seconde après — exactement comme sur les entrées sans menus. Tout le
     * nécessaire à la surbrillance est déjà là (`SpGetHighlight` lit `highlight`,
     * `x-start`/`y-start`/`x-end`/`y-end` et `menu-palette` posées par dvdnav,
     * `SpCropToHighlight` recadre sur le bouton, et un rappel sur `highlight`
     * rafraîchit à chaque changement de bouton).
     * ⚠ Reste possible : si l'accélération n'ouvrait finalement PAS de contexte,
     * plus personne ne rendrait les sous-titres. `mpeg2-hwaccel-subs=0` rend la
     * piste à `spudec` dans ce cas. */
    if( !var_InheritBool( p_dec, "mpeg2-hwaccel-subs" ) )
    {
        msg_Dbg( p_dec, "sous-titres matériels désactivés par l'utilisateur — "
                        "rendu logiciel" );
        return VLC_EGENERIC;
    }

    dvddriver_spu_sys_t *p_sys = calloc( 1, sizeof( *p_sys ) );
    if( p_sys == NULL )
        return VLC_ENOMEM;

    p_dec->p_sys = p_sys;
    /* Aucun subpicture n'est produit (le GPU incruste), mais on annonce le même
     * format de sortie que `spudec` : la machinerie de décodage n'a pas à
     * distinguer notre cas, et un i_codec nul est un terrain inexploré. */
    p_dec->fmt_out.i_codec = VLC_CODEC_SPU;
    { FILE *f = fopen( "/tmp/hw_sp_dump", "r" );
      if( f ) { p_sys->b_dump = true; fclose( f ); } }
    { FILE *f = fopen( "/tmp/hw_sp_nohide", "r" );
      if( f ) { p_sys->b_nohide = true; fclose( f ); } }
    { FILE *f = fopen( "/tmp/hw_sp_stick", "r" );
      if( f ) { p_sys->b_stick = true; fclose( f ); } }
    { FILE *f = fopen( "/tmp/hw_sp_direct", "r" );
      if( f ) { p_sys->b_direct = true; fclose( f ); } }
    { FILE *f = fopen( "/tmp/hw_sp_probe", "r" );
      if( f ) { p_sys->b_probe = true; fclose( f ); } }

    p_sys->queue = calloc( SP_QUEUE, sizeof( *p_sys->queue ) );
    p_sys->p_scratch = malloc( SP_PITCH * SP_LINES );
    p_sys->p_pkt_scratch = malloc( SP_PKT_MAX );
    if( p_sys->queue == NULL || p_sys->p_scratch == NULL
     || p_sys->p_pkt_scratch == NULL )
    {
        free( p_sys->p_pkt_scratch );
        free( p_sys->p_scratch );
        free( p_sys->queue );
        free( p_sys );
        return VLC_ENOMEM;
    }
    vlc_mutex_init( &p_sys->lock );
    vlc_cond_init( &p_sys->wait );
    if( vlc_clone( &p_sys->thread, SpThread, p_dec, VLC_THREAD_PRIORITY_LOW ) )
    {
        vlc_cond_destroy( &p_sys->wait );
        vlc_mutex_destroy( &p_sys->lock );
        free( p_sys->queue );
        free( p_sys );
        return VLC_EGENERIC;
    }
    p_sys->b_thread = true;

    /* Surbrillance des menus DVD : dvdnav repose `highlight` à chaque
     * changement de bouton. Sans menus, la variable n'existe pas et
     * var_AddCallback échoue sans conséquence. */
    if( SpInput( p_dec ) != NULL )
        var_AddCallback( SpInput( p_dec ), "highlight", HighlightCallback, p_dec );

    p_dec->pf_decode    = Decode;
    p_dec->pf_packetize = NULL;
    p_dec->pf_flush     = Flush;

    msg_Info( p_dec, "sous-titres DVD incrustés par le GPU (plan subpicture "
                     "matériel ATI) — aucun coût par image" );
    return VLC_SUCCESS;
}

void dvddriver_spu_Close(vlc_object_t *p_this)
{
    decoder_t *p_dec = (decoder_t *) p_this;
    dvddriver_spu_sys_t *p_sys = p_dec->p_sys;

    if( SpInput( p_dec ) != NULL )
        var_DelCallback( SpInput( p_dec ), "highlight", HighlightCallback, p_dec );

    if( p_sys->b_thread )
    {
        vlc_mutex_lock( &p_sys->lock );
        p_sys->b_quit = true;
        vlc_cond_signal( &p_sys->wait );
        vlc_mutex_unlock( &p_sys->lock );
        vlc_join( p_sys->thread, NULL );
        vlc_cond_destroy( &p_sys->wait );
        vlc_mutex_destroy( &p_sys->lock );
    }

    /* Effacer avant de partir : le plan SP survit au décodeur, une incrustation
     * laissée en place resterait figée sur la vidéo. */
    dvddriver_ctx *p_hw = SpHw( p_dec );
    if( p_hw != NULL )
        dvddriver_sp_hide( p_hw );

    msg_Dbg( p_dec, "sous-titres matériels : %u incrustés, %u en échec, "
             "%u en retard (>200 ms), %u abandonnés (file pleine)",
             p_sys->i_shown, p_sys->i_failed, p_sys->i_late, p_sys->i_dropped );
    free( p_sys->p_pkt_scratch );
    free( p_sys->p_scratch );
    free( p_sys->queue );
    free( p_sys );
}
