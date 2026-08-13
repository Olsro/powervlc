/*****************************************************************************
 * dvdnav.c: DVD module using the dvdnav library.
 *****************************************************************************
 * Copyright (C) 2004-2009 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Laurent Aimar <fenrir@via.ecp.fr>
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <assert.h>
#include <ctype.h>      /* isalpha() */
#include <sys/stat.h>
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>     /* close() */

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_input.h>
#include <vlc_access.h>
#include <vlc_demux.h>
#include <vlc_charset.h>
#include <vlc_fs.h>
#include <vlc_vout.h>
#include <vlc_dialog.h>
#include <vlc_iso_lang.h>

/* FIXME we should find a better way than including that */
#include "../../src/text/iso-639_def.h"


#include <dvdnav/dvdnav.h>
/* Expose without patching headers */
dvdnav_status_t dvdnav_jump_to_sector_by_time(dvdnav_t *, uint64_t, int32_t);

#include "../demux/mpeg/pes.h"
#include "../demux/mpeg/ps.h"

#include "disc_helper.h"
#include "dvd_description.h"

#ifndef DVDREAD_VERSION_CODE /* defined de facto in 6.0 */
# define DVDREAD_VERSION_CODE(major, minor, micro) (((major) * 10000) + ((minor) * 100) +  ((micro) * 1))
# define DVDREAD_VERSION DVDREAD_VERSION_CODE(5,0,3)
#endif

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
#define ANGLE_TEXT N_("DVD angle")
#define ANGLE_LONGTEXT N_( \
     "Default DVD angle." )

#define MENU_TEXT N_("Start directly in menu")
#define MENU_LONGTEXT N_( \
    "Start the DVD directly in the main menu. This "\
    "will try to skip all the useless warning introductions." )

#define LANGUAGE_DEFAULT ("en")

/* dvdnav_get_active_spu_stream sets this bit when subtitles are hidden
   and only forced captions should show */
#define DVDNAV_SPU_HIDDEN 0x80

static int  AccessDemuxOpen ( vlc_object_t * );
static void Close( vlc_object_t * );

#if DVDREAD_VERSION >= 50300 && defined( HAVE_STREAM_CB_IN_DVDNAV_H )
#define HAVE_DVDNAV_DEMUX
static int  DemuxOpen ( vlc_object_t * );
#endif

vlc_module_begin ()
    set_shortname( N_("DVD with menus") )
    set_description( N_("DVDnav Input") )
    set_category( CAT_INPUT )
    set_subcategory( SUBCAT_INPUT_ACCESS )
    add_integer( "dvdnav-angle", 1, ANGLE_TEXT,
        ANGLE_LONGTEXT, false )
    add_bool( "dvdnav-menu", true,
        MENU_TEXT, MENU_LONGTEXT, false )
    set_capability( "access_demux", 5 )
    add_shortcut( "dvd", "dvdnav", "file" )
    set_callbacks( AccessDemuxOpen, Close )
#ifdef HAVE_DVDNAV_DEMUX
    add_submodule()
        set_description( N_("DVDnav demuxer") )
        set_category( CAT_INPUT )
        set_subcategory( SUBCAT_INPUT_DEMUX )
        set_capability( "demux", 5 )
        set_callbacks( DemuxOpen, Close )
        add_shortcut( "dvd", "iso" )
#endif
vlc_module_end ()

/* Shall we use libdvdnav's read ahead cache? */
#ifdef __OS2__
#define DVD_READ_CACHE 0
#else
#define DVD_READ_CACHE 1
#endif

#define BLOCK_FLAG_CELL_DISCONTINUITY (BLOCK_FLAG_PRIVATE_SHIFT << 1)

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
struct demux_sys_t
{
    dvdnav_t    *dvdnav;

    /* */
    bool        b_reset_pcr;
    bool        b_readahead;
    /* Last look-ahead-cache inhibition state sent to es_out (menu
     * domains inhibit, the VTS title domain allows -- see
     * ES_OUT_SET_VIDEO_CACHE_INHIBIT). */
    bool        b_cache_inhibited;
    /* Deferred VTS_CHANGE (round 88): the demux runs cushion-depth
     * AHEAD of the display, so the VM reaches the end of a PGC
     * (first-play trailers!) while the user is still WATCHING it. The
     * stock handler tore the pipeline down on the spot (PCR reset +
     * es_out_Del of every track), discarding the undisplayed tail.
     * Instead the side effects are parked here and executed only once
     * es_out reports empty -- same drain discipline as DVDNAV_WAIT. */
    bool        b_vts_change_pending;

    struct
    {
        bool         b_created;
        bool         b_enabled;
        vlc_mutex_t  lock;
        vlc_timer_t  timer;
    } still;

    /* track */
    ps_track_t  tk[PS_TK_COUNT];
    int         i_mux_rate;

    /* event */
    vout_thread_t *p_vout;

    /* palette for menus */
    uint32_t clut[16];
    uint8_t  palette[4][4];
    bool b_spu_change;
    /* SPST_REG tel que la machine virtuelle du disque le porte, publié par
     * DVDNAV_SPU_STREAM_CHANGE : 0-31 = flux réellement choisi, bit 0x40 =
     * affiché (sinon « forcés seulement »), au-delà = AUCUN sous-titre
     * choisi.  -1 tant qu'aucun évènement n'est arrivé. */
    int i_spu_logical;
    /* Dernières position et heure STABILISÉES, tenues pendant les fenêtres où
     * la machine virtuelle du disque n'a pas encore fixé sa position (cf.
     * DEMUX_GET_POSITION). */
    bool   b_position_known;
    double f_last_position;
    vlc_tick_t i_last_time;
    vlc_tick_t i_stable_wall;   /* mdate() au dernier relevé stable */
    vlc_tick_t i_explicit_anchor_wall;  /* mdate() au dernier saut DEMANDÉ */
    bool       b_paused;
    vlc_tick_t i_pause_wall;

    /* Aspect ration */
    struct {
        unsigned i_num;
        unsigned i_den;
    } sar;

    /* */
    int           i_title;
    input_title_t **title;
    int           cur_title;
    int           cur_seekpoint;

    /* length of program group chain */
    vlc_tick_t  i_pgc_length;
    int         i_vobu_index;
    int         i_vobu_flush;

    /* ★★★ SURVEILLANCE DU SUPPORT (2026-08-05) — un lecteur optique qui lâche
     * ne doit pas se traduire par un gel muet.
     * Constaté sur l'iBook G3 : en revenant au menu, le lecteur a rendu une
     * erreur de lecture IRRÉCUPÉRABLE puis a laissé tomber le disque
     * (`ASC=0x11/0x06`, puis `ASC=0x3a` « support absent », `disk1: I/O
     * error`, `media is not present`). libdvdnav a alors échoué à ouvrir le
     * VTS (`ifoOpenVTSI failed`) MAIS a continué à rendre DVDNAV_STATUS_OK sur
     * des événements sans données (HOP_CHANNEL, NOP…). Le démultiplexeur
     * tournait donc à vide indéfiniment et le décodeur attendait une image I
     * qui ne pouvait plus arriver : de l'extérieur, un gel sans explication.
     * ⇒ On mesure le temps écoulé depuis le dernier bloc de données RÉEL. Au
     * delà du seuil, on vérifie que le support répond encore ; s'il a disparu,
     * on le DIT à l'utilisateur et on arrête proprement.
     * ⚠ Une image fixe (STILL_FRAME) ou une attente (WAIT) sont des états
     * LÉGITIMES sans données : ils réarment le chronomètre, sans quoi tout menu
     * fixe déclencherait une fausse alerte. */
    vlc_tick_t  i_last_block;      /* date du dernier bloc utile */
    char       *psz_media_path;    /* chemin à vérifier (NULL = non vérifiable) */
    bool        b_media_lost;      /* alerte déjà émise : ne pas la répéter */

    /* ★★ La sortie vidéo vient de changer ⇒ REPUBLIER la surbrillance du menu.
     * Posé par `EventIntf` (fil de l'input), consommé par `Demux` (fil du
     * démultiplexeur). ⚠ C'est bien au fil du démultiplexeur de faire le
     * travail : `ButtonUpdate` appelle libdvdnav, qui n'est PAS réentrante —
     * l'appeler depuis le rappel d'événement la ferait courir contre la boucle
     * de démultiplexage. Un simple booléen suffit ici : la seule conséquence
     * d'une course serait un rafraîchissement décalé d'une itération. */
    bool        b_highlight_refresh;
};

/* Silence sans données au-delà duquel on soupçonne le lecteur. Généreux : un
 * DVD sain peut légitimement rester muet le temps d'un changement de VTS sur un
 * lecteur lent (le G3 met plusieurs secondes à recaler la tête). On ne veut
 * PAS d'alerte à tort — le coût d'un faux positif est d'interrompre une lecture
 * qui va bien. */
#define DVD_MEDIA_SILENCE_TIMEOUT  VLC_TICK_FROM_SEC(12)

/*****************************************************************************
 * Surveillance du support optique — cf. le commentaire de `i_last_block`.
 *****************************************************************************/

/* Le support répond-il encore ? On ne se fie PAS au seul silence de libdvdnav :
 * on interroge le système de fichiers, seul juge fiable. `stat()` sur le point
 * de montage échoue dès que le noyau a retiré le disque (« media is not
 * present »), et `access()` sur VIDEO_TS confirme qu'on peut encore le lire.
 * Renvoie vrai tant que tout va bien, y compris quand on ne peut pas juger
 * (chemin inconnu, flux distant) : dans le doute, ne JAMAIS interrompre. */
static bool MediaStillPresent( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if( p_sys->psz_media_path == NULL || *p_sys->psz_media_path == '\0' )
        return true;

    struct stat st;
    if( stat( p_sys->psz_media_path, &st ) != 0 )
        return false;
    if( !S_ISDIR( st.st_mode ) )
        return true;            /* image disque ou nœud de périphérique */

    char *psz_vts;
    if( asprintf( &psz_vts, "%s/VIDEO_TS", p_sys->psz_media_path ) < 0 )
        return true;            /* plus de mémoire : ne rien conclure */
    const bool b_ok = ( access( psz_vts, R_OK ) == 0 );
    free( psz_vts );
    return b_ok;
}

/* Alerte l'utilisateur UNE seule fois, puis demande l'arrêt du démultiplexeur. */
static int MediaLostFail( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if( !p_sys->b_media_lost )
    {
        p_sys->b_media_lost = true;
        msg_Err( p_demux, "le support optique ne répond plus — lecture arrêtée" );
        vlc_dialog_display_error( p_demux, _("Disc no longer readable"), "%s",
            _("The disc stopped responding, so playback cannot continue.\n\n"
              "The drive reported an unrecoverable read error, or the disc is "
              "no longer in the drive. This is often caused by an overheated "
              "drive on an older machine, and more rarely by a dirty or "
              "damaged disc. Let the machine cool down, then insert the disc "
              "again.") );
    }
    return -1;      /* le démultiplexeur s'arrête proprement */
}

static int Control( demux_t *, int, va_list );
static int Demux( demux_t * );
static int DemuxBlock( demux_t *, const uint8_t *, int );
static void DemuxForceStill( demux_t * );

static void DemuxTitles( demux_t * );
static void ESSubtitleUpdate( demux_t * );
static vlc_tick_t DvdnavExtrapolatedTime( demux_sys_t * );
static void ButtonUpdate( demux_t *, bool );

static void ESNew( demux_t *, int );
static int ProbeDVD( const char * );

static char *DemuxGetLanguageCode( demux_t *p_demux, const char *psz_var );

static int ControlInternal( demux_t *, int, ... );

static void StillTimer( void * );

static int EventMouse( vlc_object_t *, char const *,
                       vlc_value_t, vlc_value_t, void * );
static int EventIntf( vlc_object_t *, char const *,
                      vlc_value_t, vlc_value_t, void * );

#if DVDNAV_VERSION >= 60100
static void DvdNavLog( void *foo, dvdnav_logger_level_t i, const char *p, va_list z)
{
    msg_GenericVa( (demux_t*)foo, i, p, z );
}
#endif

/*****************************************************************************
 * CommonOpen:
 *****************************************************************************/
static int CommonOpen( vlc_object_t *p_this,
                       dvdnav_t *p_dvdnav, bool b_readahead )
{
    demux_t     *p_demux = (demux_t*)p_this;
    demux_sys_t *p_sys;
    int         i_angle;
    char        *psz_code;

    assert( p_dvdnav );

    /* Fill p_demux field */
    DEMUX_INIT_COMMON(); p_sys = p_demux->p_sys;
    p_sys->dvdnav = p_dvdnav;

    ps_track_init( p_sys->tk );
    p_sys->i_spu_logical = -1;
    p_sys->b_readahead = b_readahead;

    /* Surveillance du support (cf. `i_last_block`). Le chemin n'est connu que
     * dans le cas access_demux, où `p_demux->psz_file` porte le point de
     * montage ; ailleurs il reste NULL et la surveillance se désarme d'elle-même
     * — c'est voulu, mieux vaut ne rien surveiller que de couper à tort. */
    p_sys->i_last_block = mdate();
    p_sys->b_media_lost = false;
    p_sys->b_highlight_refresh = false;
    p_sys->psz_media_path = ( p_demux->psz_file && *p_demux->psz_file )
                          ? strdup( p_demux->psz_file ) : NULL;

    /* Discs open on first-play/menu material: keep the look-ahead
     * cache out of the way until a title (VTS) domain is entered --
     * menu loops fire PCR resets that would each open a pointless fill
     * episode parking the SPU decoder (no highlight meanwhile). The
     * per-domain updates live in DvdnavCacheInhibitUpdate(). */
    p_sys->b_cache_inhibited = true;
    p_sys->b_vts_change_pending = false;
    es_out_Control( p_demux->out, ES_OUT_SET_VIDEO_CACHE_INHIBIT, true );

    /* Configure dvdnav */
    if( dvdnav_set_readahead_flag( p_sys->dvdnav, p_sys->b_readahead ) !=
          DVDNAV_STATUS_OK )
    {
        msg_Warn( p_demux, "cannot set read-a-head flag" );
    }

    if( dvdnav_set_PGC_positioning_flag( p_sys->dvdnav, 1 ) !=
          DVDNAV_STATUS_OK )
    {
        msg_Warn( p_demux, "cannot set PGC positioning flag" );
    }

    /* Set menu language */
    psz_code = DemuxGetLanguageCode( p_demux, "menu-language" );
    if( dvdnav_menu_language_select( p_sys->dvdnav, psz_code ) !=
        DVDNAV_STATUS_OK )
    {
        msg_Warn( p_demux, "can't set menu language to '%s' (%s)",
                  psz_code, dvdnav_err_to_string( p_sys->dvdnav ) );
        /* We try to fall back to 'en' */
        if( strcmp( psz_code, LANGUAGE_DEFAULT ) )
            dvdnav_menu_language_select( p_sys->dvdnav, (char*)LANGUAGE_DEFAULT );
    }
    free( psz_code );

    /* Set audio language */
    psz_code = DemuxGetLanguageCode( p_demux, "audio-language" );
    if( dvdnav_audio_language_select( p_sys->dvdnav, psz_code ) !=
        DVDNAV_STATUS_OK )
    {
        msg_Warn( p_demux, "can't set audio language to '%s' (%s)",
                  psz_code, dvdnav_err_to_string( p_sys->dvdnav ) );
        /* We try to fall back to 'en' */
        if( strcmp( psz_code, LANGUAGE_DEFAULT ) )
            dvdnav_audio_language_select( p_sys->dvdnav, (char*)LANGUAGE_DEFAULT );
    }
    free( psz_code );

    /* Set spu language */
    psz_code = DemuxGetLanguageCode( p_demux, "sub-language" );
    if( dvdnav_spu_language_select( p_sys->dvdnav, psz_code ) !=
        DVDNAV_STATUS_OK )
    {
        msg_Warn( p_demux, "can't set spu language to '%s' (%s)",
                  psz_code, dvdnav_err_to_string( p_sys->dvdnav ) );
        /* We try to fall back to 'en' */
        if( strcmp( psz_code, LANGUAGE_DEFAULT ) )
            dvdnav_spu_language_select(p_sys->dvdnav, (char*)LANGUAGE_DEFAULT );
    }
    free( psz_code );

    DemuxTitles( p_demux );

    if( var_CreateGetBool( p_demux, "dvdnav-menu" ) )
    {
        msg_Dbg( p_demux, "trying to go to dvd menu" );

        if( dvdnav_title_play( p_sys->dvdnav, 1 ) != DVDNAV_STATUS_OK )
        {
            msg_Err( p_demux, "cannot set title (can't decrypt DVD?)" );
            vlc_dialog_display_error( p_demux, _("Playback failure"), "%s",
                _("VLC cannot set the DVD's title. It possibly "
                  "cannot decrypt the entire disc.") );
            free( p_sys );
            return VLC_EGENERIC;
        }

        if( dvdnav_menu_call( p_sys->dvdnav, DVD_MENU_Title ) !=
            DVDNAV_STATUS_OK )
        {
            /* Try going to menu root */
            if( dvdnav_menu_call( p_sys->dvdnav, DVD_MENU_Root ) !=
                DVDNAV_STATUS_OK )
                    msg_Warn( p_demux, "cannot go to dvd menu" );
        }
    }

    i_angle = var_CreateGetInteger( p_demux, "dvdnav-angle" );
    if( i_angle <= 0 ) i_angle = 1;

    /* FIXME hack hack hack hack FIXME */
    /* Get p_input and create variable */
    var_Create( p_demux->p_input, "x-start", VLC_VAR_INTEGER );
    var_Create( p_demux->p_input, "y-start", VLC_VAR_INTEGER );
    var_Create( p_demux->p_input, "x-end", VLC_VAR_INTEGER );
    var_Create( p_demux->p_input, "y-end", VLC_VAR_INTEGER );
    var_Create( p_demux->p_input, "color", VLC_VAR_ADDRESS );
    var_Create( p_demux->p_input, "menu-palette", VLC_VAR_ADDRESS );
    var_Create( p_demux->p_input, "highlight", VLC_VAR_BOOL );

    /* catch vout creation event */
    var_AddCallback( p_demux->p_input, "intf-event", EventIntf, p_demux );

    p_sys->still.b_enabled = false;
    vlc_mutex_init( &p_sys->still.lock );
    if( !vlc_timer_create( &p_sys->still.timer, StillTimer, p_sys ) )
        p_sys->still.b_created = true;

    return VLC_SUCCESS;
}

/*****************************************************************************
 * AccessDemuxOpen:
 *****************************************************************************/
static int AccessDemuxOpen ( vlc_object_t *p_this )
{
    demux_t *p_demux = (demux_t*)p_this;
    dvdnav_t *p_dvdnav = NULL;
    char *psz_file = NULL;
    const char *psz_path = NULL;
    int i_ret = VLC_EGENERIC;
    bool forced = false;

    if( !strncmp(p_demux->psz_access, "dvd", 3) )
        forced = true;

    if( !p_demux->psz_file || !*p_demux->psz_file )
    {
        /* Only when selected */
        if( !forced )
            return VLC_EGENERIC;

        psz_file = var_InheritString( p_this, "dvd" );
    }
    else
        psz_file = strdup( p_demux->psz_file );

#if defined( _WIN32 ) || defined( __OS2__ )
    if( psz_file != NULL )
    {
        /* Remove trailing backslash, otherwise dvdnav_open will fail */
        size_t flen = strlen( psz_file );
        if( flen > 0 && psz_file[flen - 1] == '\\' )
            psz_file[flen - 1] = '\0';
    }
    else
        psz_file = strdup("");
#endif

    if( unlikely(psz_file == NULL) )
        return VLC_EGENERIC;

    /* Try some simple probing to avoid going through dvdnav_open too often */
    if( !forced && ProbeDVD( psz_file ) != VLC_SUCCESS )
        goto bailout;

    if( forced && DiscProbeMacOSPermission( p_this, psz_file ) != VLC_SUCCESS )
        goto bailout;

    /* Open dvdnav */
#if DVDREAD_VERSION < DVDREAD_VERSION_CODE(6, 1, 2)
    /* In libdvdread prior to 6.1.2, UTF8 is not supported for windows and
     * requires a prior conversion.
     * For non win32/os2 platforms, this is just a no-op */
    psz_path = ToLocale( psz_file );
#else
    psz_path = psz_file;
#endif
#if DVDNAV_VERSION >= 60100
    dvdnav_logger_cb cbs;
    cbs.pf_log = DvdNavLog;
    if( dvdnav_open2( &p_dvdnav, p_demux, &cbs, psz_path  ) != DVDNAV_STATUS_OK )
#else
    if( dvdnav_open( &p_dvdnav, psz_path  ) != DVDNAV_STATUS_OK )
#endif
    {
        msg_Warn( p_demux, "cannot open DVD (%s)", psz_file);
        goto bailout;
    }

    i_ret = CommonOpen( p_this, p_dvdnav, !!DVD_READ_CACHE );
    if( i_ret != VLC_SUCCESS )
        dvdnav_close( p_dvdnav );

bailout:
    free( psz_file );
#if DVDREAD_VERSION < DVDREAD_VERSION_CODE(6, 1, 2)
    if( psz_path )
        LocaleFree( psz_path );
#endif
    return i_ret;
}

#ifdef HAVE_DVDNAV_DEMUX
/*****************************************************************************
 * StreamProbeDVD: very weak probing that avoids going too often into a dvdnav_open()
 *****************************************************************************/
static int StreamProbeDVD( stream_t *s )
{
    /* first sector should be filled with zeros */
    ssize_t i_peek;
    const uint8_t *p_peek;
    i_peek = vlc_stream_Peek( s, &p_peek, 2048 );
    if( i_peek < 512 ) {
        return VLC_EGENERIC;
    }
    while (i_peek > 0) {
        if (p_peek[ --i_peek ]) {
            return VLC_EGENERIC;
        }
    }

    /* ISO 9660 volume descriptor */
    char iso_dsc[6];
    if( vlc_stream_Seek( s, 0x8000 + 1 ) != VLC_SUCCESS
     || vlc_stream_Read( s, iso_dsc, sizeof (iso_dsc) ) < (int)sizeof (iso_dsc)
     || memcmp( iso_dsc, "CD001\x01", 6 ) )
        return VLC_EGENERIC;

    /* Try to find the anchor (2 bytes at LBA 256) */
    uint16_t anchor;

    if( vlc_stream_Seek( s, 256 * DVD_VIDEO_LB_LEN ) == VLC_SUCCESS
     && vlc_stream_Read( s, &anchor, 2 ) == 2
     && GetWLE( &anchor ) == 2 )
        return VLC_SUCCESS;
    else
        return VLC_EGENERIC;
}

/*****************************************************************************
 * dvdnav stream callbacks
 *****************************************************************************/
static int stream_cb_seek( void *demux, uint64_t pos )
{
    return vlc_stream_Seek( ((demux_t *)demux)->s, pos );
}

static int stream_cb_read( void *demux, void* buffer, int size )
{
    return vlc_stream_Read( ((demux_t *)demux)->s, buffer, size );
}

/*****************************************************************************
 * DemuxOpen:
 *****************************************************************************/
static int DemuxOpen ( vlc_object_t *p_this )
{
    demux_t *p_demux = (demux_t*)p_this;
    dvdnav_t *p_dvdnav = NULL;
    bool forced = false, b_seekable = false;

    if( p_demux->psz_demux != NULL
     && !strncmp(p_demux->psz_demux, "dvd", 3) )
        forced = true;

    /* StreamProbeDVD need FASTSEEK, but if dvd is forced, we don't probe thus
     * don't need fastseek */
    vlc_stream_Control( p_demux->s, forced ? STREAM_CAN_SEEK : STREAM_CAN_FASTSEEK,
                    &b_seekable );
    if( !b_seekable )
        return VLC_EGENERIC;

    /* Try some simple probing to avoid going through dvdnav_open too often */
    if( !forced && StreamProbeDVD( p_demux->s ) != VLC_SUCCESS )
        return VLC_EGENERIC;

    static dvdnav_stream_cb stream_cb =
    {
        .pf_seek = stream_cb_seek,
        .pf_read = stream_cb_read,
        .pf_readv = NULL,
    };

    /* Open dvdnav with stream callbacks */
#if DVDNAV_VERSION >= 60100
    dvdnav_logger_cb cbs;
    cbs.pf_log = DvdNavLog;
    if( dvdnav_open_stream2( &p_dvdnav, p_demux,
                             &cbs, &stream_cb ) != DVDNAV_STATUS_OK )
#else
    if( dvdnav_open_stream( &p_dvdnav, p_demux,
                            &stream_cb ) != DVDNAV_STATUS_OK )
#endif
    {
        msg_Warn( p_demux, "cannot open DVD with open_stream" );
        return VLC_EGENERIC;
    }

    int i_ret = CommonOpen( p_this, p_dvdnav, false );
    if( i_ret != VLC_SUCCESS )
        dvdnav_close( p_dvdnav );
    return i_ret;
}
#endif

/*****************************************************************************
 * Close:
 *****************************************************************************/
static void Close( vlc_object_t *p_this )
{
    demux_t     *p_demux = (demux_t*)p_this;
    demux_sys_t *p_sys = p_demux->p_sys;

    /* Stop vout event handler */
    var_DelCallback( p_demux->p_input, "intf-event", EventIntf, p_demux );
    if( p_sys->p_vout != NULL )
    {   /* Should not happen, but better be safe than sorry. */
        msg_Warn( p_sys->p_vout, "removing dangling mouse DVD callbacks" );
        var_DelCallback( p_sys->p_vout, "mouse-moved", EventMouse, p_demux );
        var_DelCallback( p_sys->p_vout, "mouse-clicked", EventMouse, p_demux );
    }

    /* Stop still image handler */
    if( p_sys->still.b_created )
        vlc_timer_destroy( p_sys->still.timer );
    vlc_mutex_destroy( &p_sys->still.lock );

    var_Destroy( p_demux->p_input, "highlight" );
    var_Destroy( p_demux->p_input, "x-start" );
    var_Destroy( p_demux->p_input, "x-end" );
    var_Destroy( p_demux->p_input, "y-start" );
    var_Destroy( p_demux->p_input, "y-end" );
    var_Destroy( p_demux->p_input, "color" );
    var_Destroy( p_demux->p_input, "menu-palette" );

    for( int i = 0; i < PS_TK_COUNT; i++ )
    {
        ps_track_t *tk = &p_sys->tk[i];
        if( tk->b_configured )
        {
            es_format_Clean( &tk->fmt );
            if( tk->es ) es_out_Del( p_demux->out, tk->es );
        }
    }

    free( p_sys->psz_media_path );

    /* Free the array of titles */
    for( int i = 0; i < p_sys->i_title; i++ )
        vlc_input_title_Delete( p_sys->title[i] );
    TAB_CLEAN( p_sys->i_title, p_sys->title );

    dvdnav_close( p_sys->dvdnav );
    free( p_sys );
}

/*****************************************************************************
 * Control:
 *****************************************************************************/
static int Control( demux_t *p_demux, int i_query, va_list args )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    input_title_t ***ppp_title;
    int i;

    switch( i_query )
    {
        /* ⚠⚠⚠ La DURÉE ne dépend pas de la position en secteurs. Elle était
         * pourtant rendue sous la même garde : quand `dvdnav_get_position()`
         * échoue — ce qui arrive en cours de lecture, aux frontières de
         * cellule et sur les images fixes — on renvoyait EGENERIC et le cœur
         * remettait la longueur à ZÉRO, alors que `i_pgc_length` était juste
         * là et parfaitement connue.
         *
         * Mesuré sur un DVD ROBOTS : à t=233,560 s le journal porte
         * `pgc_length=433303200` (4814,48 s) et, un dixième de seconde plus
         * tard, la barre voyait `len=0` — pour ne plus revenir avant une
         * bonne minute. Conséquences vues par l'utilisateur : le survol de la
         * barre n'ouvrait plus son infobulle et le seek ne menait nulle part
         * (les deux convertissent une fraction en temps, donc en rien du
         * tout), et le champ de temps SAUTAIT — il retombe sur le temps
         * écoulé quand la durée est nulle, au lieu du temps restant. Puis
         * tout « se réparait seul » dès que la position redevenait lisible.
         *
         * La longueur est donc rendue AVANT la garde, et la garde ne protège
         * plus que ce qui a réellement besoin des secteurs. */
        case DEMUX_GET_LENGTH:
            if( p_sys->i_pgc_length > 0 )
            {
                *va_arg( args, int64_t * ) = (int64_t)p_sys->i_pgc_length;
                return VLC_SUCCESS;
            }
            return VLC_EGENERIC;

        /* ⚠⚠⚠ `dvdnav_get_position()` échoue en pleine lecture, et pas
         * qu'un instant. Deux causes dans `searching.c` : « New position not
         * yet determined » (l'état de la VM a bougé — saut de canal, domaine,
         * VTS, redémarrage de cellule — et la position mémorisée ne
         * correspond plus) et une cellule courante que le balayage saute
         * (bloc d'angles dont on ne joue pas la première cellule — ce DVD a
         * bien plusieurs angles, ses pré-commandes portent des `SetSTN
         * angle=1/2`). Le curseur restait alors collé au début et le seek
         * ramenait à la position de départ.
         *
         * Or le TEMPS, lui, est parfaitement disponible
         * (`dvdnav_get_current_time()`, cf. DEMUX_GET_TIME) et la durée du
         * PGC aussi. On se rabat donc dessus : c'est la même grandeur, par
         * un autre chemin. Même chose pour le saut, via
         * `dvdnav_jump_to_sector_by_time()` — exactement ce que fait
         * DEMUX_SET_TIME, qui n'a jamais posé de problème. */
        /* ⚠⚠⚠ UN SEUL AXE : LE TEMPS.
         *
         * La barre est graduée en temps de bout en bout — l'infobulle affiche
         * `fraction × durée`, les marqueurs de chapitre sont des décalages
         * temporels, et le clic cherche par le temps. Faire avancer le curseur
         * avec la position en SECTEURS mélangeait deux axes qui ne coïncident
         * pas sur un flux à débit variable : le curseur ne tombait jamais sur
         * ses propres marqueurs.
         *
         * Les deux fonctions de libdvdnav sont écartées, chacune pour une
         * raison mesurée sur un DVD ROBOTS :
         *  - `dvdnav_get_position()` (secteurs) échoue durablement dans les
         *    blocs d'angles — sa boucle saute la cellule courante et rend −1 ;
         *  - `dvdnav_get_current_time()` additionne les cellules précédentes
         *    et compte DEUX FOIS les blocs d'angles : 4 min 16 annoncées pour
         *    une image à 2 min 09, et 4 min 29 après un saut à 6 min 58.
         *
         * On tient donc le temps nous-mêmes : une ANCRE reposée à chaque
         * frontière de chapitre (`dvdnav_describe_title_chapters()`, la table
         * même qui place les marqueurs) et à chaque saut demandé, plus
         * l'horloge entre deux. La dérive est bornée par la longueur d'un
         * chapitre et les pauses sont défalquées. La position en secteurs ne
         * sert plus que de dernier recours, avant qu'aucune ancre n'existe. */
        case DEMUX_GET_POSITION:
        {
            if( p_sys->b_position_known && p_sys->i_pgc_length > 0 )
            {
                vlc_tick_t i_now = DvdnavExtrapolatedTime( p_sys );
                double f_pos = (double)i_now / (double)p_sys->i_pgc_length;
                if( f_pos < 0. )
                    f_pos = 0.;
                if( f_pos > 1. )
                    f_pos = 1.;
                *va_arg( args, double* ) = f_pos;
                return VLC_SUCCESS;
            }

            uint32_t pos, len;
            if( dvdnav_get_position( p_sys->dvdnav, &pos, &len ) ==
                  DVDNAV_STATUS_OK && len != 0 )
            {
                *va_arg( args, double* ) = (double)pos / (double)len;
                return VLC_SUCCESS;
            }
            return VLC_EGENERIC;
        }

        case DEMUX_SET_POSITION:
        {
            double f_pos = va_arg( args, double );
            uint32_t pos, len;

            /* Un saut réussi est la meilleure estimation qu'on ait : elle
             * remplace l'ancre, sinon on tiendrait la position d'AVANT le
             * saut pendant que la VM se refixe.
             *
             * ⚠⚠⚠ REPOSER AUSSI L'HORODATAGE. Une ancre est un COUPLE
             * (temps, instant) : ne remettre que le temps laissait
             * l'extrapolation ajouter tout le délai écoulé depuis le relevé
             * PRÉCÉDENT. Mesuré : un clic sur 00:00 affichait 00:12, et
             * l'écart grossissait à chaque clic — 01:16 après quelques-uns. */
            p_sys->f_last_position = f_pos;
            p_sys->i_last_time =
                (vlc_tick_t)( f_pos * (double)p_sys->i_pgc_length );
            p_sys->i_stable_wall = mdate();
            p_sys->b_position_known = true;

            /* ⚠⚠⚠ CHERCHER PAR LE TEMPS D'ABORD. La barre est graduée en
             * TEMPS de bout en bout : l'infobulle affiche `fraction × durée`,
             * et les marqueurs de chapitre sont posés sur des décalages
             * temporels. Chercher en SECTEURS, sur un flux à débit variable,
             * ne tombe pas au même endroit — mesuré : infobulle à 6 min 58,
             * atterrissage à 5 min 56, soit 62 s d'écart. Le clic doit mener
             * là où la barre l'a promis ; la recherche par secteur ne sert
             * plus que de secours. */
            p_sys->i_explicit_anchor_wall = mdate();

            /* ⚠ Ne jamais viser la toute fin du PGC. Un titre de DVD se
             * termine par des post-commandes — c'est elles qui enchaînent sur
             * le générique, souvent un AUTRE titre. Atterrir sur les derniers
             * instants ne laisse pas de quoi les atteindre : la lecture
             * s'arrêtait là, et il fallait viser un peu avant pour que la
             * bascule se fasse. On garde donc une seconde de marge : le clic
             * mène au bout du film, la lecture y arrive normalement, et le
             * disque enchaîne de lui-même. */
            vlc_tick_t i_target =
                (vlc_tick_t)( f_pos * (double)p_sys->i_pgc_length );
            if( i_target > p_sys->i_pgc_length - CLOCK_FREQ )
                i_target = p_sys->i_pgc_length - CLOCK_FREQ;
            if( i_target < 0 )
                i_target = 0;

            if( p_sys->i_pgc_length > 0
             && dvdnav_jump_to_sector_by_time( p_sys->dvdnav,
                    i_target * 9 / 100, SEEK_SET ) == DVDNAV_STATUS_OK )
            {
                p_sys->i_last_time = i_target;
                p_sys->f_last_position =
                    (double)i_target / (double)p_sys->i_pgc_length;
                return VLC_SUCCESS;   /* voir la NOTE ci-dessous */
            }

            if( dvdnav_get_position( p_sys->dvdnav, &pos, &len ) ==
                  DVDNAV_STATUS_OK && len != 0
             && dvdnav_sector_search( p_sys->dvdnav, (uint32_t)( f_pos * len ),
                                      SEEK_SET ) == DVDNAV_STATUS_OK )
            {
                /* NOTE: do NOT fire ES_OUT_RESET_PCR from here "to
                 * close the stale window before the HOP lands" --
                 * tried in round 74 and it made things WORSE (the
                 * title-entry churn also traverses this control and
                 * the extra reset re-mixed the pipeline: 892 late
                 * pictures vs 234 without it). The deferred
                 * HOP_CHANNEL reset is the lesser evil: ~1 s of
                 * pre-seek cushion plays before the episode
                 * re-arms. */
                return VLC_SUCCESS;
            }
            return VLC_EGENERIC;
        }

        case DEMUX_GET_TIME:
            /* même axe que DEMUX_GET_POSITION ci-dessus : sans ça le chrono
             * et le curseur racontaient deux histoires différentes */
            if( p_sys->b_position_known )
            {
                *va_arg( args, vlc_tick_t * ) = DvdnavExtrapolatedTime( p_sys );
                return VLC_SUCCESS;
            }
            if( p_sys->i_pgc_length > 0 )
            {
                *va_arg( args, vlc_tick_t * ) =
                    dvdnav_get_current_time( p_sys->dvdnav ) * 100 / 9;
                return VLC_SUCCESS;
            }
            break;

        case DEMUX_SET_TIME:
        {
            vlc_tick_t i_time = va_arg( args, vlc_tick_t );
            if( dvdnav_jump_to_sector_by_time( p_sys->dvdnav,
                                               i_time * 9 / 100,
                                               SEEK_SET ) == DVDNAV_STATUS_OK )
            {
                p_sys->i_last_time = i_time;
                p_sys->i_stable_wall = mdate();
                p_sys->i_explicit_anchor_wall = p_sys->i_stable_wall;
                p_sys->b_position_known = true;
                if( p_sys->i_pgc_length > 0 )
                    p_sys->f_last_position =
                        (double)i_time / (double)p_sys->i_pgc_length;
                /* See DEMUX_SET_POSITION: no eager reset here. */
                return VLC_SUCCESS;
            }
            msg_Err( p_demux, "can't set time to %" PRId64, i_time );
            return VLC_EGENERIC;
        }

        /* Special for access_demux */
        case DEMUX_CAN_PAUSE:
        case DEMUX_CAN_SEEK:
        case DEMUX_CAN_CONTROL_PACE:
            /* TODO */
            *va_arg( args, bool * ) = true;
            return VLC_SUCCESS;

        case DEMUX_SET_PAUSE_STATE:
        {
            /* suivi pour DvdnavExtrapolatedTime() : une extrapolation qui
             * continue d'avancer pendant une pause afficherait un chrono qui
             * tourne sur une image figée */
            bool b_paused = (bool)va_arg( args, int );
            if( b_paused && !p_sys->b_paused )
                p_sys->i_pause_wall = mdate();
            else if( !b_paused && p_sys->b_paused )
                p_sys->i_stable_wall += mdate() - p_sys->i_pause_wall;
            p_sys->b_paused = b_paused;
            return VLC_SUCCESS;
        }

        case DEMUX_GET_TITLE_INFO:
            ppp_title = va_arg( args, input_title_t*** );

            /* Duplicate title infos */
            *ppp_title = vlc_alloc( p_sys->i_title, sizeof( input_title_t * ) );
            if( !*ppp_title )
                return VLC_EGENERIC;
            for( i = 0; i < p_sys->i_title; i++ )
            {
                (*ppp_title)[i] = vlc_input_title_Duplicate( p_sys->title[i] );
                if(!(*ppp_title)[i])
                {
                    while( i )
                        free( (*ppp_title)[--i] );
                    free( *ppp_title );
                    return VLC_EGENERIC;
                }
            }
            *va_arg( args, int* ) = p_sys->i_title;
            *va_arg( args, int* ) = 0; /* Title offset */
            *va_arg( args, int* ) = 1; /* Chapter offset */
            return VLC_SUCCESS;

        case DEMUX_SET_TITLE:
            i = va_arg( args, int );
            if( i == 0 && dvdnav_menu_call( p_sys->dvdnav, DVD_MENU_Root )
                  != DVDNAV_STATUS_OK )
            {
                msg_Warn( p_demux, "cannot set title/chapter" );
                return VLC_EGENERIC;
            }

            if( i != 0 )
            {
                dvdnav_still_skip( p_sys->dvdnav );
                if( dvdnav_title_play( p_sys->dvdnav, i ) != DVDNAV_STATUS_OK )
                {
                    msg_Warn( p_demux, "cannot set title/chapter" );
                    return VLC_EGENERIC;
                }
            }

            p_demux->info.i_update |=
                INPUT_UPDATE_TITLE | INPUT_UPDATE_SEEKPOINT;
            p_sys->cur_title = i;
            p_sys->cur_seekpoint = 0;
            return VLC_SUCCESS;

        case DEMUX_SET_SEEKPOINT:
            i = va_arg( args, int );
            if( p_sys->cur_title == 0 )
            {
                static const int argtab[] = {
                    DVD_MENU_Escape,
                    DVD_MENU_Root,
                    DVD_MENU_Title,
                    DVD_MENU_Part,
                    DVD_MENU_Subpicture,
                    DVD_MENU_Audio,
                    DVD_MENU_Angle
                };
                enum { numargs = sizeof(argtab)/sizeof(int) };
                if( (unsigned)i >= numargs || DVDNAV_STATUS_OK !=
                           dvdnav_menu_call(p_sys->dvdnav,argtab[i]) )
                    return VLC_EGENERIC;
            }
            else if( dvdnav_part_play( p_sys->dvdnav, p_sys->cur_title,
                                       i + 1 ) != DVDNAV_STATUS_OK )
            {
                msg_Warn( p_demux, "cannot set title/chapter" );
                return VLC_EGENERIC;
            }
            /* ⚠⚠ Réancrer le temps sur le DÉBUT DU CHAPITRE visé. Sans ça,
             * l'ancre restait celle d'avant le saut : la position se met à
             * flotter dès que la VM bouge (ce qu'un saut de chapitre fait
             * forcément), on tenait puis on extrapolait la valeur d'AVANT, et
             * le chapitre choisi paraissait retomber là où on se trouvait
             * (mesuré : « Chapitre 2 » affiché à 00:07). Le début du chapitre
             * est déjà connu — c'est celui-là même qui place le marqueur sur
             * la barre (DemuxTitles / dvdnav_describe_title_chapters). */
            if( p_sys->cur_title > 0 && p_sys->cur_title < p_sys->i_title
             && i >= 0 && i < p_sys->title[p_sys->cur_title]->i_seekpoint )
            {
                p_sys->i_last_time =
                    p_sys->title[p_sys->cur_title]->seekpoint[i]->i_time_offset;
                if( p_sys->i_pgc_length > 0 )
                    p_sys->f_last_position = (double)p_sys->i_last_time
                                           / (double)p_sys->i_pgc_length;
                p_sys->i_stable_wall = mdate();
                p_sys->b_position_known = true;
            }
            else
                p_sys->b_position_known = false;   /* rien de fiable à tenir */

            p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;
            p_sys->cur_seekpoint = i;
            return VLC_SUCCESS;

        case DEMUX_GET_TITLE:
            *va_arg( args, int * ) = p_sys->cur_title;
            break;

        case DEMUX_GET_SEEKPOINT:
            *va_arg( args, int * ) = p_sys->cur_seekpoint;
            break;

        case DEMUX_GET_PTS_DELAY:
            *va_arg( args, int64_t * ) =
                INT64_C(1000) * var_InheritInteger( p_demux, "disc-caching" );
            return VLC_SUCCESS;

        case DEMUX_GET_META:
        {
            const char *title_name = NULL;

            dvdnav_get_title_string(p_sys->dvdnav, &title_name);
            if( (NULL != title_name) && ('\0' != title_name[0]) )
            {
                vlc_meta_t *p_meta = va_arg( args, vlc_meta_t* );
                vlc_meta_Set( p_meta, vlc_meta_Title, title_name );
                return VLC_SUCCESS;
            }
            return VLC_EGENERIC;
        }

        case DEMUX_NAV_ACTIVATE:
        {
            pci_t *pci = dvdnav_get_current_nav_pci( p_sys->dvdnav );

            if( dvdnav_button_activate( p_sys->dvdnav, pci ) != DVDNAV_STATUS_OK )
                return VLC_EGENERIC;
            ButtonUpdate( p_demux, true );
            break;
        }

        case DEMUX_NAV_UP:
        {
            pci_t *pci = dvdnav_get_current_nav_pci( p_sys->dvdnav );

            if( dvdnav_upper_button_select( p_sys->dvdnav, pci ) != DVDNAV_STATUS_OK )
                return VLC_EGENERIC;
            break;
        }

        case DEMUX_NAV_DOWN:
        {
            pci_t *pci = dvdnav_get_current_nav_pci( p_sys->dvdnav );

            if( dvdnav_lower_button_select( p_sys->dvdnav, pci ) != DVDNAV_STATUS_OK )
                return VLC_EGENERIC;
            break;
        }

        case DEMUX_NAV_LEFT:
        {
            pci_t *pci = dvdnav_get_current_nav_pci( p_sys->dvdnav );

            if( dvdnav_left_button_select( p_sys->dvdnav, pci ) != DVDNAV_STATUS_OK )
                return VLC_EGENERIC;
            break;
        }

        case DEMUX_NAV_RIGHT:
        {
            pci_t *pci = dvdnav_get_current_nav_pci( p_sys->dvdnav );

            if( dvdnav_right_button_select( p_sys->dvdnav, pci ) != DVDNAV_STATUS_OK )
                return VLC_EGENERIC;
            break;
        }

        case DEMUX_NAV_MENU:
        {
            if( dvdnav_menu_call( p_sys->dvdnav, DVD_MENU_Title )
                != DVDNAV_STATUS_OK )
            {
                msg_Warn( p_demux, "cannot select Title menu" );
                if( dvdnav_menu_call( p_sys->dvdnav, DVD_MENU_Root )
                    != DVDNAV_STATUS_OK )
                {
                    msg_Warn( p_demux, "cannot select Root menu" );
                    return VLC_EGENERIC;
                }
            }
            p_demux->info.i_update |=
                INPUT_UPDATE_TITLE | INPUT_UPDATE_SEEKPOINT;
            p_sys->cur_title = 0;
            p_sys->cur_seekpoint = 2;
            break;
        }

        /* TODO implement others */
        default:
            return VLC_EGENERIC;
    }

    return VLC_SUCCESS;
}

static int ControlInternal( demux_t *p_demux, int i_query, ... )
{
    va_list args;
    int     i_result;

    va_start( args, i_query );
    i_result = Control( p_demux, i_query, args );
    va_end( args );

    return i_result;
}
/*****************************************************************************
 * Demux:
 *****************************************************************************/

/* Aligns es_out's look-ahead-cache inhibition on the current dvdnav
 * domain: inhibited everywhere except the VTS title domain (the film).
 * Menu domains loop cells and fire PCR resets at will -- each would
 * open a fill episode that parks the SPU decoder (no menu highlight
 * for seconds); title playback on the other hand is exactly what the
 * cache exists for (MPEG-2 above budget on a G3). Called from every
 * event that can change the domain; cheap and idempotent. */
static void DvdnavCacheInhibitUpdate( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    /* Stills inhibit too, not just menu domains: a still feeds ~one
     * picture and then trickles (the STILL_FRAME path sleeps 40 ms per
     * event), so a fill gate against it can only crawl -- observed at
     * title entry (studio-logo stills): 2-3 pictures in 5 s, the
     * too-slow valve firing, and the user's fill-percent never
     * honoured. When the still ends, es_out re-opens a proper fill
     * episode (see ES_OUT_SET_VIDEO_CACHE_INHIBIT), so the wait lands
     * right where the real film starts. */
    vlc_mutex_lock( &p_sys->still.lock );
    bool b_still = p_sys->still.b_enabled;
    vlc_mutex_unlock( &p_sys->still.lock );
    bool b_inhibit = !dvdnav_is_domain_vts( p_sys->dvdnav ) || b_still;

    if( b_inhibit != p_sys->b_cache_inhibited )
    {
        p_sys->b_cache_inhibited = b_inhibit;
        es_out_Control( p_demux->out, ES_OUT_SET_VIDEO_CACHE_INHIBIT,
                        b_inhibit );
    }
}

/* Deferred DVDNAV_VTS_CHANGE side effects (see b_vts_change_pending):
 * exactly the stock handler body, run only once the pipeline is empty. */
static void DemuxProcessVtsChange( demux_t *p_demux )
{
    /* ★ Signal au décodeur MPEG-2 matériel (libmpeg2/ATI, PowerPC) : un
     * changement de domaine (MENU→FILM notamment) n'émet ni redémarrage de
     * décodeur ni discontinuité de bloc, et les horodatages restent continus —
     * or un décodeur GPU ouvert sur le contenu du MENU tisse des champs
     * croisés pour tout le film (images dédoublées, mesuré sur 10.3). On
     * incrémente une génération de domaine sur le bus libvlc ; le décodeur la
     * consulte et fait renaître son contexte matériel à l'image I suivante. */
    var_Create( p_demux->obj.libvlc, "dvddriver-domain-gen", VLC_VAR_INTEGER );
    var_SetInteger( p_demux->obj.libvlc, "dvddriver-domain-gen",
        var_GetInteger( p_demux->obj.libvlc, "dvddriver-domain-gen" ) + 1 );

    demux_sys_t *p_sys = p_demux->p_sys;
    int32_t i_title = 0;
    int32_t i_part  = 0;

    msg_Dbg( p_demux, "processing deferred VTS_CHANGE (pipeline drained)" );

    /* Domain may have flipped menu<->title: align the cache
     * inhibition BEFORE the PCR reset opens (or not) an episode. */
    DvdnavCacheInhibitUpdate( p_demux );

    /* reset PCR */
    es_out_Control( p_demux->out, ES_OUT_RESET_PCR );

    for( int i = 0; i < PS_TK_COUNT; i++ )
    {
        ps_track_t *tk = &p_sys->tk[i];
        if( tk->b_configured )
        {
            es_format_Clean( &tk->fmt );
            if( tk->es )
            {
                es_out_Del( p_demux->out, tk->es );
                tk->es = NULL;
            }
        }
        tk->b_configured = false;
    }

    /* ★ BUG A (images dédoublées via les menus DVD) : la frontière de domaine
     * ne portait AUCUN drapeau de bloc — le décodeur enchaînait menu→film sans
     * flush et son association horodatage→picture (mpeg2_tag_picture) restait
     * décalée pour tout le film (chaque image affichée à la date de sa voisine
     * = ±40 ms de va-et-vient permanent, invisible aux compteurs internes).
     * Marquer le premier bloc de chaque piste comme au CELL_CHANGE : converti
     * en BLOCK_FLAG_DISCONTINUITY dès le premier bloc à DTS valide, il déclenche
     * côté libmpeg2 SynchroReset + resynchronisation du tagging + renaissance
     * du décodeur matériel. */
    for( int i = 0; i < PS_TK_COUNT; i++ )
        p_sys->tk[i].i_next_block_flags |= BLOCK_FLAG_CELL_DISCONTINUITY;

    uint32_t i_width, i_height;
    if( dvdnav_get_video_resolution( p_sys->dvdnav,
                                     &i_width, &i_height ) )
        i_width = i_height = 0;
    switch( dvdnav_get_video_aspect( p_sys->dvdnav ) )
    {
    case 0:
        p_sys->sar.i_num = 4 * i_height;
        p_sys->sar.i_den = 3 * i_width;
        break;
    case 3:
        p_sys->sar.i_num = 16 * i_height;
        p_sys->sar.i_den =  9 * i_width;
        break;
    default:
        p_sys->sar.i_num = 0;
        p_sys->sar.i_den = 0;
        break;
    }

    if( dvdnav_current_title_info( p_sys->dvdnav, &i_title,
                                   &i_part ) == DVDNAV_STATUS_OK )
    {
        if( i_title >= 0 && i_title < p_sys->i_title &&
            p_sys->cur_title != i_title )
        {
            p_demux->info.i_update |= INPUT_UPDATE_TITLE;
            p_sys->cur_title = i_title;
        }
    }
}

static int Demux( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    uint8_t buffer[DVD_VIDEO_LB_LEN];
    uint8_t *packet = buffer;
    int i_event;
    int i_len;
    dvdnav_status_t status;

    if( p_sys->b_vts_change_pending )
    {
        /* Drain gate (round 88): hold the VM here -- no new blocks, no
         * teardown -- until everything already demuxed has actually
         * been SHOWN (ES_OUT_GET_EMPTY counts the decoded look-ahead
         * cushion through vout_IsEmpty). Same 40 ms nap discipline as
         * DVDNAV_WAIT below; the input keeps servicing controls between
         * calls, and a user jump flushes es_out, which releases the
         * gate at once. */
        bool b_empty;
        es_out_Control( p_demux->out, ES_OUT_GET_EMPTY, &b_empty );
        if( !b_empty )
        {
            msleep( 40*1000 );
            return 1;
        }
        p_sys->b_vts_change_pending = false;
        DemuxProcessVtsChange( p_demux );
    }

    /* Republication de la surbrillance après un changement de sortie vidéo,
     * faite ICI pour rester sur le fil du démultiplexeur (cf. le champ).
     *
     * ⛔⛔ DÉSARMÉE PAR DÉFAUT (2026-08-05) — CE CORRECTIF A GELÉ LA MACHINE.
     * Mesure : capture d'écran désarmée SEULE ⇒ bascule plein écran en ~10 s,
     * SANS gel (validé à l'écran). Le MÊME build + cette republication ⇒ gel
     * total, SSH compris, donc au niveau GPU et non applicatif. C'est la seule
     * différence entre les deux essais.
     * Mécanisme soupçonné, cohérent avec l'incident du 2026-07-22 (« ShowSPBuffer
     * sur le chemin de present a FIGÉ le GPU, extinction complète requise ») :
     * republier la surbrillance PENDANT la reconstruction de la sortie vidéo
     * fait travailler le plan subpicture au moment précis où le décodeur
     * matériel rouvre son contexte sur une nouvelle fenêtre.
     * ⇒ Une simple temporisation ne suffirait pas : il faut d'abord garantir que
     * la sortie ET le contexte matériel sont stabilisés. Repris derrière
     * `/tmp/dvd_hl_refresh` le jour où on saura le faire proprement. */
    if( p_sys->b_highlight_refresh )
    {
        p_sys->b_highlight_refresh = false;
        static int s_hl = -1;
        if( s_hl < 0 )
            s_hl = ( access( "/tmp/dvd_hl_refresh", F_OK ) == 0 ) ? 1 : 0;
        if( s_hl > 0 )
            ButtonUpdate( p_demux, false );
    }

    if( p_sys->b_readahead )
        status = dvdnav_get_next_cache_block( p_sys->dvdnav, &packet, &i_event,
                                              &i_len );
    else
        status = dvdnav_get_next_block( p_sys->dvdnav, packet, &i_event,
                                        &i_len );
    if( status == DVDNAV_STATUS_ERR )
    {
        msg_Warn( p_demux, "cannot get next block (%s)",
                  dvdnav_err_to_string( p_sys->dvdnav ) );
        /* ★ Avant de mettre l'échec sur le compte du disque ou du titre, voir
         * si le support est encore là : c'est la cause la plus probable, et la
         * seule qu'on puisse expliquer clairement à l'utilisateur. */
        if( !MediaStillPresent( p_demux ) )
            return MediaLostFail( p_demux );
        if( p_sys->cur_title == 0 )
        {
            msg_Dbg( p_demux, "jumping to first title" );
            return ControlInternal( p_demux, DEMUX_SET_TITLE, 1 ) == VLC_SUCCESS ? 1 : -1;
        }
        return -1;
    }

    /* ★★ CHIEN DE GARDE — libdvdnav peut rendre DVDNAV_STATUS_OK indéfiniment
     * sur des événements SANS DONNÉES après un échec d'ouverture de VTS
     * (`ifoOpenVTSI failed`) : rien n'arrive plus, et rien ne le signale. On ne
     * coupe pas sur le silence seul — on s'en sert comme déclencheur pour aller
     * DEMANDER au système si le support répond encore. */
    if( mdate() - p_sys->i_last_block > DVD_MEDIA_SILENCE_TIMEOUT )
    {
        if( !MediaStillPresent( p_demux ) )
            return MediaLostFail( p_demux );
        /* Support présent : silence légitime (lecteur lent, VTS long à
         * recaler). On réarme, sinon on interrogerait le disque à chaque
         * bloc — coûteux sur un lecteur optique. */
        p_sys->i_last_block = mdate();
    }

    /* Réarmement du chien de garde. Un bloc de données est la preuve directe
     * que le lecteur répond ; une image FIXE ou une ATTENTE sont des états
     * légitimement muets (menu fixe, drainage) et ne doivent surtout pas être
     * pris pour une panne — sans quoi tout menu fixe couperait la lecture. */
    if( i_event == DVDNAV_BLOCK_OK || i_event == DVDNAV_STILL_FRAME
     || i_event == DVDNAV_WAIT )
        p_sys->i_last_block = mdate();

    switch( i_event )
    {
    case DVDNAV_BLOCK_OK:   /* mpeg block */
        vlc_mutex_lock( &p_sys->still.lock );
        vlc_timer_schedule( p_sys->still.timer, false, 0, 0 );
        p_sys->still.b_enabled = false;
        vlc_mutex_unlock( &p_sys->still.lock );
        /* Still just ended (if one was on): re-allow the cache BEFORE
         * the deferred PCR reset below -- that reset then opens the
         * fill episode gating the REAL content at fill-percent, right
         * where the film starts. */
        DvdnavCacheInhibitUpdate( p_demux );
        if( p_sys->b_reset_pcr )
        {
            es_out_Control( p_demux->out, ES_OUT_RESET_PCR );
            p_sys->b_reset_pcr = false;
        }
        DemuxBlock( p_demux, packet, i_len );
        if( p_sys->i_vobu_index > 0 )
        {
            if( p_sys->i_vobu_flush == p_sys->i_vobu_index )
                DemuxForceStill( p_demux );
            p_sys->i_vobu_index++;
        }
        break;

    case DVDNAV_NOP:    /* Nothing */
        msg_Dbg( p_demux, "DVDNAV_NOP" );
        break;

    case DVDNAV_STILL_FRAME:
    {
        dvdnav_still_event_t *event = (dvdnav_still_event_t*)packet;
        bool b_still_init = false;

        vlc_mutex_lock( &p_sys->still.lock );
        if( !p_sys->still.b_enabled )
        {
            msg_Dbg( p_demux, "DVDNAV_STILL_FRAME" );
            msg_Dbg( p_demux, "     - length=0x%x", event->length );
            p_sys->still.b_enabled = true;

            if( event->length != 0xff && p_sys->still.b_created )
            {
                vlc_tick_t delay = event->length * CLOCK_FREQ;
                vlc_timer_schedule( p_sys->still.timer, false, delay, 0 );
            }

            b_still_init = true;
        }
        vlc_mutex_unlock( &p_sys->still.lock );

        if( b_still_init )
        {
            /* Entering a still: inhibit the fill gate (a still trickles
             * ~one picture, a gate against it can only crawl into the
             * too-slow valve). */
            DvdnavCacheInhibitUpdate( p_demux );
            DemuxForceStill( p_demux );
            p_sys->b_reset_pcr = true;
        }
        msleep( 40000 );
        break;
    }

    case DVDNAV_SPU_CLUT_CHANGE:
    {
        int i;

        msg_Dbg( p_demux, "DVDNAV_SPU_CLUT_CHANGE" );
        /* Update color lookup table (16 *uint32_t in packet) */
        memcpy( p_sys->clut, packet, 16 * sizeof( uint32_t ) );

        /* HACK to get the SPU tracks registered in the right order */
        for( i = 0; i < 0x1f; i++ )
        {
            if( dvdnav_spu_stream_to_lang( p_sys->dvdnav, i ) != 0xffff )
                ESNew( p_demux, 0xbd20 + i );
        }
        /* END HACK */
        break;
    }

    case DVDNAV_SPU_STREAM_CHANGE:
    {
        dvdnav_spu_stream_change_event_t *event =
            (dvdnav_spu_stream_change_event_t*)packet;
        int i;

        msg_Dbg( p_demux, "DVDNAV_SPU_STREAM_CHANGE" );
        msg_Dbg( p_demux, "     - physical_wide=%d",
                 event->physical_wide );
        msg_Dbg( p_demux, "     - physical_letterbox=%d",
                 event->physical_letterbox);
        msg_Dbg( p_demux, "     - physical_pan_scan=%d",
                 event->physical_pan_scan );
        msg_Dbg( p_demux, "     - logical=%d", event->logical );

        /* ⚠ Cet évènement arrive APRÈS le changement de cellule qui a déjà fait
         * naître les pistes de sous-titres : mesuré sur un DVD ROBOTS, les
         * cinq `es_out_Add` précèdent de trois lignes de journal le premier
         * SPU_STREAM_CHANGE. Elles ont donc été créées sans connaître le
         * registre du disque. Comme le drapeau « forcés seulement » est figé
         * dans le format à la création, on ne peut pas se contenter de
         * re-sélectionner : quand le registre change de sens, on jette les
         * pistes SPU et on laisse le HACK ci-dessous les recréer — c'est le
         * même démontage que sur un changement de VTS, et il ne coûte que les
         * sous-titres. */
        if( p_sys->i_spu_logical != event->logical )
        {
            p_sys->i_spu_logical = event->logical;

            for( i = 0; i < 0x20; i++ )
            {
                ps_track_t *tk = &p_sys->tk[ps_id_to_tk(0xbd20 + i)];
                if( !tk->b_configured )
                    continue;
                es_format_Clean( &tk->fmt );
                if( tk->es )
                {
                    es_out_Del( p_demux->out, tk->es );
                    tk->es = NULL;
                }
                tk->b_configured = false;
            }
        }

        ESSubtitleUpdate( p_demux );
        p_sys->b_spu_change = true;

        /* HACK to get the SPU tracks registered in the right order */
        for( i = 0; i < 0x1f; i++ )
        {
            if( dvdnav_spu_stream_to_lang( p_sys->dvdnav, i ) != 0xffff )
                ESNew( p_demux, 0xbd20 + i );
        }
        /* END HACK */
        break;
    }

    case DVDNAV_AUDIO_STREAM_CHANGE:
    {
        dvdnav_audio_stream_change_event_t *event =
            (dvdnav_audio_stream_change_event_t*)packet;
        msg_Dbg( p_demux, "DVDNAV_AUDIO_STREAM_CHANGE" );
        msg_Dbg( p_demux, "     - physical=%d", event->physical );
        /* TODO */
        break;
    }

    case DVDNAV_VTS_CHANGE:
    {
        dvdnav_vts_change_event_t *event = (dvdnav_vts_change_event_t*)packet;
        msg_Dbg( p_demux, "DVDNAV_VTS_CHANGE (deferred until drained)" );
        msg_Dbg( p_demux, "     - vtsN=%d", event->new_vtsN );
        msg_Dbg( p_demux, "     - domain=%d", event->new_domain );

        /* Do NOT tear the pipeline down here: whatever the display has
         * not shown yet (the whole look-ahead cushion of a trailer that
         * the VM just finished READING) would be discarded. Park the
         * side effects; the gate at the top of Demux() runs them once
         * es_out is really empty. Every dvdnav query the deferred
         * handler makes (resolution, aspect, title info) reads the
         * CURRENT VM state, which stays put while we hold off
         * dvdnav_get_next_block. */
        p_sys->b_vts_change_pending = true;
        break;
    }

    case DVDNAV_CELL_CHANGE:
    {
        int32_t i_title = 0;
        int32_t i_part  = 0;

        dvdnav_cell_change_event_t *event =
            (dvdnav_cell_change_event_t*)packet;
        msg_Dbg( p_demux, "DVDNAV_CELL_CHANGE" );
        msg_Dbg( p_demux, "     - cellN=%d", event->cellN );
        msg_Dbg( p_demux, "     - pgN=%d", event->pgN );
        msg_Dbg( p_demux, "     - cell_length=%"PRId64, event->cell_length );
        msg_Dbg( p_demux, "     - pg_length=%"PRId64, event->pg_length );
        msg_Dbg( p_demux, "     - pgc_length=%"PRId64, event->pgc_length );
        msg_Dbg( p_demux, "     - cell_start=%"PRId64, event->cell_start );
        msg_Dbg( p_demux, "     - pg_start=%"PRId64, event->pg_start );

        /* Menu<->title transitions inside the SAME VTS surface here
         * without any DVDNAV_VTS_CHANGE: re-align the cache inhibition
         * on every cell change (no-op when the domain is unchanged). */
        DvdnavCacheInhibitUpdate( p_demux );

        /* Store the length in time of the current PGC */
        if( p_sys->i_pgc_length != event->pgc_length / 90 * 1000 )
            p_sys->b_position_known = false;  /* autre PGC : cache périmé */
        p_sys->i_pgc_length = event->pgc_length / 90 * 1000;
        p_sys->i_vobu_index = 0;
        p_sys->i_vobu_flush = 0;

        for( int i=0; i<PS_TK_COUNT; i++ )
            p_sys->tk[i].i_next_block_flags |= BLOCK_FLAG_CELL_DISCONTINUITY;

        /* FIXME is it correct or there is better way to know chapter change */
        if( dvdnav_current_title_info( p_sys->dvdnav, &i_title,
                                       &i_part ) == DVDNAV_STATUS_OK )
        {
            if( i_title >= 0 && i_title < p_sys->i_title )
            {
                p_demux->info.i_update |= INPUT_UPDATE_TITLE;
                p_sys->cur_title = i_title;

                if( i_part >= 1 && i_part <= p_sys->title[i_title]->i_seekpoint )
                {
                    p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;

                    /* ⚠⚠⚠ Ré-ancrage sur le DÉBUT DU CHAPITRE. C'est la seule
                     * heure de ce disque en laquelle on puisse avoir
                     * confiance : elle vient de `dvdnav_describe_title_chapters()`,
                     * la même table qui place les marqueurs de la barre.
                     * `dvdnav_get_current_time()`, lui, additionne les
                     * cellules précédentes et compte DEUX FOIS les blocs
                     * d'angles — mesuré sur ce disque : 4 min 16 annoncées
                     * pour une image réellement à 2 min 09.
                     * Le chapitre est atteint quel que soit le chemin (menus
                     * du disque compris), donc l'ancre se remet d'aplomb
                     * toute seule à chaque frontière ; entre deux, c'est
                     * l'horloge qui avance (DvdnavExtrapolatedTime). Un
                     * relevé de position en secteurs, quand il redevient
                     * disponible, reprend la main aussitôt. */
                    /* ⚠ mais PAS juste après un saut demandé par
                     * l'utilisateur : on a atterri au MILIEU d'un chapitre et
                     * le début de ce chapitre serait une régression. */
                    if( ( p_sys->cur_seekpoint != i_part - 1
                          || !p_sys->b_position_known )
                     && mdate() - p_sys->i_explicit_anchor_wall
                            > 3 * CLOCK_FREQ )
                    {
                        p_sys->i_last_time = p_sys->title[i_title]
                                                 ->seekpoint[i_part - 1]
                                                 ->i_time_offset;
                        if( p_sys->i_pgc_length > 0 )
                            p_sys->f_last_position =
                                (double)p_sys->i_last_time
                                / (double)p_sys->i_pgc_length;
                        p_sys->i_stable_wall = mdate();
                        p_sys->b_position_known = true;
                    }
                    p_sys->cur_seekpoint = i_part - 1;
                }
            }
        }
        break;
    }

    case DVDNAV_NAV_PACKET:
    {
        p_sys->i_vobu_index = 1;
        p_sys->i_vobu_flush = 0;

        /* Look if we have need to force a flush (and when) */
        const pci_t *p_pci = dvdnav_get_current_nav_pci( p_sys->dvdnav );
        if( unlikely(!p_pci) )
            break;
        const pci_gi_t *p_pci_gi = &p_pci->pci_gi;
        if( p_pci_gi->vobu_se_e_ptm != 0 && p_pci_gi->vobu_se_e_ptm < p_pci_gi->vobu_e_ptm )
        {
            const dsi_t *p_dsi = dvdnav_get_current_nav_dsi( p_sys->dvdnav );
            if( unlikely(!p_dsi) )
                break;
            const dsi_gi_t *p_dsi_gi = &p_dsi->dsi_gi;
            if( p_dsi_gi->vobu_3rdref_ea != 0 )
                p_sys->i_vobu_flush = p_dsi_gi->vobu_3rdref_ea;
            else if( p_dsi_gi->vobu_2ndref_ea != 0 )
                p_sys->i_vobu_flush = p_dsi_gi->vobu_2ndref_ea;
            else if( p_dsi_gi->vobu_1stref_ea != 0 )
                p_sys->i_vobu_flush = p_dsi_gi->vobu_1stref_ea;
        }

#ifdef DVDNAV_DEBUG
        msg_Dbg( p_demux, "DVDNAV_NAV_PACKET" );
#endif
        /* A lot of thing to do here :
         *  - handle packet
         *  - fetch pts (for time display)
         *  - ...
         */
        DemuxBlock( p_demux, packet, i_len );
        if( p_sys->b_spu_change )
        {
            ButtonUpdate( p_demux, false );
            p_sys->b_spu_change = false;
        }
        break;
    }

    case DVDNAV_STOP:   /* EOF */
        msg_Dbg( p_demux, "DVDNAV_STOP" );

        if( p_sys->b_readahead )
            dvdnav_free_cache_block( p_sys->dvdnav, packet );
        return 0;

    case DVDNAV_HIGHLIGHT:
    {
        dvdnav_highlight_event_t *event = (dvdnav_highlight_event_t*)packet;
        msg_Dbg( p_demux, "DVDNAV_HIGHLIGHT" );
        msg_Dbg( p_demux, "     - display=%d", event->display );
        msg_Dbg( p_demux, "     - buttonN=%d", event->buttonN );
        ButtonUpdate( p_demux, false );
        break;
    }

    case DVDNAV_HOP_CHANNEL:
        msg_Dbg( p_demux, "DVDNAV_HOP_CHANNEL" );
        p_sys->i_vobu_index = 0;
        p_sys->i_vobu_flush = 0;
        /* Hops land on menus as often as on titles: align the cache
         * inhibition before the reset can open an episode. */
        DvdnavCacheInhibitUpdate( p_demux );
        es_out_Control( p_demux->out, ES_OUT_RESET_PCR );
        break;

    case DVDNAV_WAIT:
        msg_Dbg( p_demux, "DVDNAV_WAIT" );

        bool b_empty;
        es_out_Control( p_demux->out, ES_OUT_GET_EMPTY, &b_empty );
        if( !b_empty )
        {
            msleep( 40*1000 );
        }
        else
        {
            dvdnav_wait_skip( p_sys->dvdnav );
            p_sys->b_reset_pcr = true;
        }
        break;

    default:
        msg_Warn( p_demux, "Unknown event (0x%x)", i_event );
        break;
    }

    if( p_sys->b_readahead )
        dvdnav_free_cache_block( p_sys->dvdnav, packet );

    return 1;
}

/* Get a 2 char code
 * FIXME: partiallyy duplicated from src/input/es_out.c
 */
static const iso639_lang_t *DemuxFindLanguage( const char *psz_lang )
{
    if( psz_lang == NULL || *psz_lang == '\0' )
        return NULL;

    for( const iso639_lang_t *pl = p_languages; pl->psz_eng_name != NULL; pl++ )
    {
        if( !strcasecmp( pl->psz_eng_name, psz_lang ) ||
            !strcasecmp( pl->psz_iso639_1, psz_lang ) ||
            !strcasecmp( pl->psz_iso639_2T, psz_lang ) ||
            !strcasecmp( pl->psz_iso639_2B, psz_lang ) )
            return pl;
    }
    return NULL;
}

/* Langue de l'INTERFACE, telle que gettext la voit.
 *
 * Les registres de langue du disque (SPRM 0, 16 et 18) ne choisissent pas une
 * piste : ils disent au DVD ce que l'utilisateur préfère, et ce sont les
 * pré-commandes du disque qui en déduisent la piste audio et les sous-titres à
 * activer. Retomber sur « en » quand aucune préférence n'est saisie revient
 * donc à se déclarer anglophone auprès de TOUS les disques — un DVD zone 2 qui
 * compare SPRM18 à « fr » prenait systématiquement sa branche anglaise.
 *
 * On prend plutôt la langue de l'interface : sur macOS `system_Init()` recopie
 * déjà la préférence système dans LANG (src/darwin/specific.c), et ailleurs
 * c'est l'environnement qui la porte. Ordre de priorité de gettext. */
static const char *DemuxGetUILanguage( char *psz_buffer, size_t i_size )
{
    static const char *const ppsz_vars[] =
        { "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" };

    for( size_t i = 0; i < ARRAY_SIZE(ppsz_vars); i++ )
    {
        const char *psz_env = getenv( ppsz_vars[i] );
        if( psz_env == NULL )
            continue;

        /* « fr », « fr_FR », « fr_FR.UTF-8 », « fr_FR@euro », « fr:en » */
        size_t i_len = 0;
        while( isalpha( (unsigned char)psz_env[i_len] ) )
            i_len++;
        /* écarte « C » et « POSIX », qui ne sont pas des langues */
        if( i_len < 2 || i_len > 3 || i_len >= i_size )
            continue;

        memcpy( psz_buffer, psz_env, i_len );
        psz_buffer[i_len] = '\0';
        return psz_buffer;
    }
    return NULL;
}

static char *DemuxGetLanguageCode( demux_t *p_demux, const char *psz_var )
{
    const iso639_lang_t *pl = NULL;
    char *psz_lang = var_CreateGetString( p_demux, psz_var );

    if( psz_lang != NULL )
    {
        /* XXX: we will use only the first value
         * (and ignore other ones in case of a list) */
        char *p = strchr( psz_lang, ',' );
        if( p != NULL )
            *p = '\0';

        pl = DemuxFindLanguage( psz_lang );
        free( psz_lang );
    }

    if( pl == NULL )
    {
        char psz_ui[8];
        pl = DemuxFindLanguage( DemuxGetUILanguage( psz_ui, sizeof(psz_ui) ) );
        if( pl != NULL )
            msg_Dbg( p_demux, "no \"%s\" preference, telling the disc the "
                     "interface language \"%s\"", psz_var, pl->psz_iso639_1 );
    }

    return strdup( pl != NULL ? pl->psz_iso639_1 : LANGUAGE_DEFAULT );
}

static void DemuxTitles( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    input_title_t *t;
    seekpoint_t *s;
    int32_t i_titles;

    /* Menu */
    t = vlc_input_title_New();
    t->i_flags = INPUT_TITLE_MENU | INPUT_TITLE_INTERACTIVE;
    t->psz_name = strdup( "DVD Menu" );

    s = vlc_seekpoint_New();
    s->psz_name = strdup( "Resume" );
    TAB_APPEND( t->i_seekpoint, t->seekpoint, s );

    s = vlc_seekpoint_New();
    s->psz_name = strdup( "Root" );
    TAB_APPEND( t->i_seekpoint, t->seekpoint, s );

    s = vlc_seekpoint_New();
    s->psz_name = strdup( "Title" );
    TAB_APPEND( t->i_seekpoint, t->seekpoint, s );

    s = vlc_seekpoint_New();
    s->psz_name = strdup( "Chapter" );
    TAB_APPEND( t->i_seekpoint, t->seekpoint, s );

    s = vlc_seekpoint_New();
    s->psz_name = strdup( "Subtitle" );
    TAB_APPEND( t->i_seekpoint, t->seekpoint, s );

    s = vlc_seekpoint_New();
    s->psz_name = strdup( "Audio" );
    TAB_APPEND( t->i_seekpoint, t->seekpoint, s );

    s = vlc_seekpoint_New();
    s->psz_name = strdup( "Angle" );
    TAB_APPEND( t->i_seekpoint, t->seekpoint, s );

    TAB_APPEND( p_sys->i_title, p_sys->title, t );

    /* Find out number of titles/chapters */
    dvdnav_get_number_of_titles( p_sys->dvdnav, &i_titles );

    if( i_titles > 90 )
        msg_Err( p_demux, "This is probably an Arccos Protected DVD. This could take time..." );

    for( int i = 1; i <= i_titles; i++ )
    {
        uint64_t i_title_length;
        uint64_t *p_chapters_time;

        int32_t i_chapters = dvdnav_describe_title_chapters( p_sys->dvdnav, i,
                                                            &p_chapters_time,
                                                            &i_title_length );
        if( i_chapters < 1 )
        {
            i_title_length = 0;
            p_chapters_time = NULL;
        }
        t = vlc_input_title_New();
        t->i_length = i_title_length * 1000 / 90;
        for( int j = 0; j < __MAX( i_chapters, 1 ); j++ )
        {
            s = vlc_seekpoint_New();
            if( p_chapters_time )
            {
                if ( j > 0 )
                    s->i_time_offset = p_chapters_time[j - 1] * 1000 / 90;
                else
                    s->i_time_offset = 0;
            }
            TAB_APPEND( t->i_seekpoint, t->seekpoint, s );
        }
        free( p_chapters_time );
        TAB_APPEND( p_sys->i_title, p_sys->title, t );
    }
}

/*****************************************************************************
 * Update functions:
 *****************************************************************************/
static void ButtonUpdate( demux_t *p_demux, bool b_mode )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    int32_t i_title, i_part;

    dvdnav_current_title_info( p_sys->dvdnav, &i_title, &i_part );

    dvdnav_highlight_area_t hl;
    int32_t i_button;
    bool    b_button_ok;

    if( dvdnav_get_current_highlight( p_sys->dvdnav, &i_button )
        != DVDNAV_STATUS_OK )
    {
        msg_Err( p_demux, "dvdnav_get_current_highlight failed" );
        return;
    }

    b_button_ok = false;
    if( i_button > 0 && i_title ==  0 )
    {
        pci_t *pci = dvdnav_get_current_nav_pci( p_sys->dvdnav );

        b_button_ok = DVDNAV_STATUS_OK ==
                  dvdnav_get_highlight_area( pci, i_button, b_mode, &hl );
    }

    if( b_button_ok )
    {
        for( unsigned i = 0; i < 4; i++ )
        {
            uint32_t i_yuv = p_sys->clut[(hl.palette>>(16+i*4))&0x0f];
            uint8_t i_alpha = ( (hl.palette>>(i*4))&0x0f ) * 0xff / 0xf;

            p_sys->palette[i][0] = (i_yuv >> 16) & 0xff;
            p_sys->palette[i][1] = (i_yuv >> 0) & 0xff;
            p_sys->palette[i][2] = (i_yuv >> 8) & 0xff;
            p_sys->palette[i][3] = i_alpha;
        }

        vlc_global_lock( VLC_HIGHLIGHT_MUTEX );
        var_SetInteger( p_demux->p_input, "x-start", hl.sx );
        var_SetInteger( p_demux->p_input, "x-end",  hl.ex );
        var_SetInteger( p_demux->p_input, "y-start", hl.sy );
        var_SetInteger( p_demux->p_input, "y-end", hl.ey );

        var_SetAddress( p_demux->p_input, "menu-palette", p_sys->palette );
        var_SetBool( p_demux->p_input, "highlight", true );

        msg_Dbg( p_demux, "buttonUpdate %d", i_button );
    }
    else
    {
        msg_Dbg( p_demux, "buttonUpdate not done b=%d t=%d",
                 i_button, i_title );

        /* Show all */
        vlc_global_lock( VLC_HIGHLIGHT_MUTEX );
        var_SetBool( p_demux->p_input, "highlight", false );
    }
    vlc_global_unlock( VLC_HIGHLIGHT_MUTEX );
}

/* Le disque a-t-il RÉELLEMENT choisi un sous-titre ?
 *
 * ⚠⚠⚠ dvdnav_get_active_spu_stream() ne permet pas de répondre. Quand
 * SPST_REG ne porte aucune sélection valable — c'est son état au réarmement
 * de la machine virtuelle, où libdvdnav y met 62 —, la résolution échoue et
 * la bibliothèque se rabat EN SILENCE sur le premier flux disponible, puis le
 * marque « masqué » puisque le registre n'a pas son bit d'affichage. On
 * croyait donc que le disque demandait « flux 0, forcés seulement » et on
 * sélectionnait cette piste : sur un DVD ROBOTS zone 2 (5 pistes ar/en/fr/fr/fr,
 * toutes en code_extension 0), c'est la piste ARABE qui démarrait, marquée
 * forcée, alors que le disque ne demande aucun sous-titre.
 *
 * On lit donc SPST_REG lui-même, publié par le champ `logical` de
 * DVDNAV_SPU_STREAM_CHANGE (cf. contrib/src/dvdnav/0004-*.patch : libdvdnav
 * documente ce champ mais ne le remplit que pour l'audio). Avec une libdvdnav
 * NON corrigée il n'est pas initialisé : hors de la plage d'un registre à
 * 6 bits, on s'en remet au comportement d'origine plutôt que de refuser
 * toute sélection. */
static bool DvdnavSpuIsSelected( demux_sys_t *p_sys )
{
    if( p_sys->i_spu_logical < 0 || p_sys->i_spu_logical > 0x3f )
        return true;                        /* libdvdnav non corrigée */
    return (p_sys->i_spu_logical & ~0x40) < 32;
}

/* Temps de lecture pendant une panne DURABLE de la position (cf.
 * DEMUX_GET_POSITION, mode B). On repart du dernier relevé stable et on
 * avance à l'horloge, en défalquant les pauses.
 *
 * ⚠ Surtout PAS `dvdnav_get_current_time()` ici. Dans un bloc d'angles, la
 * somme des cellules précédentes suit un AUTRE chemin sur le disque et
 * surcompte : mesuré, le chrono a sauté d'une minute à 4 min 25 en pleine
 * lecture. Une extrapolation ne peut ni sauter ni reculer ; elle dérive au
 * pire de la durée de la panne, et se recale dès que la position revient. */
static vlc_tick_t DvdnavExtrapolatedTime( demux_sys_t *p_sys )
{
    vlc_tick_t i_wall = p_sys->b_paused ? p_sys->i_pause_wall : mdate();
    vlc_tick_t i_elapsed = i_wall - p_sys->i_stable_wall;

    if( i_elapsed < 0 )
        i_elapsed = 0;

    vlc_tick_t i_time = p_sys->i_last_time + i_elapsed;
    if( p_sys->i_pgc_length > 0 && i_time > p_sys->i_pgc_length )
        i_time = p_sys->i_pgc_length;
    return i_time;
}

static void ESSubtitleUpdate( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    int         i_spu = dvdnav_get_active_spu_stream( p_sys->dvdnav );
    int32_t i_title, i_part;

    ButtonUpdate( p_demux, false );

    dvdnav_current_title_info( p_sys->dvdnav, &i_title, &i_part );
    if( i_title > 0 ) return;

    /* dvdnav_get_active_spu_stream sets (in)visibility flag as 0xF0 */
    if( i_spu >= 0 && i_spu <= 0x1f )
    {
        ps_track_t *tk = &p_sys->tk[ps_id_to_tk(0xbd20 + i_spu)];

        ESNew( p_demux, 0xbd20 + i_spu );

        /* be sure to unselect it (reset) */
        if( tk->es )
        {
            es_out_Control( p_demux->out, ES_OUT_SET_ES_STATE, tk->es,
                            (bool)false );

            /* now select it */
            es_out_Control( p_demux->out, ES_OUT_SET_ES, tk->es );
        }
    }
    else
    {
        for( i_spu = 0; i_spu <= 0x1F; i_spu++ )
        {
            ps_track_t *tk = &p_sys->tk[ps_id_to_tk(0xbd20 + i_spu)];
            if( tk->es )
            {
                es_out_Control( p_demux->out, ES_OUT_SET_ES_STATE, tk->es,
                                (bool)false );
            }
        }
    }
}

/*****************************************************************************
 * DemuxBlock: demux a given block
 *****************************************************************************/
static int DemuxBlock( demux_t *p_demux, const uint8_t *p, int len )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    while( len > 0 )
    {
        int i_size = ps_pkt_size( p, len );
        if( i_size <= 0 || i_size > len )
        {
            break;
        }

        /* Create a block */
        block_t *p_pkt = block_Alloc( i_size );
        memcpy( p_pkt->p_buffer, p, i_size);

        /* Parse it and send it */
        switch( 0x100 | p[3] )
        {
        case 0x1b9:
        case 0x1bb:
        case 0x1bc:
#ifdef DVDNAV_DEBUG
            if( p[3] == 0xbc )
            {
                msg_Warn( p_demux, "received a PSM packet" );
            }
            else if( p[3] == 0xbb )
            {
                msg_Warn( p_demux, "received a SYSTEM packet" );
            }
#endif
            block_Release( p_pkt );
            break;

        case 0x1ba:
        {
            int64_t i_scr;
            int i_mux_rate;
            if( !ps_pkt_parse_pack( p_pkt, &i_scr, &i_mux_rate ) )
            {
                es_out_SetPCR( p_demux->out, i_scr + 1 );
                if( i_mux_rate > 0 ) p_sys->i_mux_rate = i_mux_rate;
            }
            block_Release( p_pkt );
            break;
        }
        default:
        {
            int i_id = ps_pkt_id( p_pkt, PS_SOURCE_VOB );
            if( i_id >= 0xc0 )
            {
                ps_track_t *tk = &p_sys->tk[ps_id_to_tk(i_id)];

                if( !tk->b_configured )
                {
                    ESNew( p_demux, i_id );
                }

                if( tk->es &&
                    !ps_pkt_parse_pes( VLC_OBJECT(p_demux), p_pkt, tk->i_skip ) )
                {
                    int i_next_block_flags = tk->i_next_block_flags;
                    tk->i_next_block_flags = 0;
                    if( i_next_block_flags & BLOCK_FLAG_CELL_DISCONTINUITY )
                    {
                        if( p_pkt->i_dts >= VLC_TICK_INVALID )
                        {
                            i_next_block_flags &= ~BLOCK_FLAG_CELL_DISCONTINUITY;
                            i_next_block_flags |= BLOCK_FLAG_DISCONTINUITY;
                        }
                        else tk->i_next_block_flags = BLOCK_FLAG_CELL_DISCONTINUITY;
                    }
                    p_pkt->i_flags |= i_next_block_flags;
                    es_out_Send( p_demux->out, tk->es, p_pkt );
                }
                else
                {
                    tk->i_next_block_flags = 0;
                    block_Release( p_pkt );
                }
            }
            else
            {
                block_Release( p_pkt );
            }
            break;
        }
        }

        p += i_size;
        len -= i_size;
    }

    return VLC_SUCCESS;
}

/*****************************************************************************
 * Force still images to be displayed by sending EOS and stopping buffering.
 *****************************************************************************/
static void DemuxForceStill( demux_t *p_demux )
{
    static const uint8_t buffer[] = {
        0x00, 0x00, 0x01, 0xe0, 0x00, 0x07,
        0x80, 0x00, 0x00,
        0x00, 0x00, 0x01, 0xB7,
    };
    DemuxBlock( p_demux, buffer, sizeof(buffer) );

    bool b_empty;
    es_out_Control( p_demux->out, ES_OUT_GET_EMPTY, &b_empty );
}

/*****************************************************************************
 * ESNew: register a new elementary stream
 *****************************************************************************/
static void ESNew( demux_t *p_demux, int i_id )
{
    demux_sys_t *p_sys = p_demux->p_sys;
    ps_track_t  *tk = &p_sys->tk[ps_id_to_tk(i_id)];
    bool  b_select = false;

    if( tk->b_configured ) return;

    if( ps_track_fill( tk, NULL, i_id, NULL, true ) )
    {
        msg_Warn( p_demux, "unknown codec for id=0x%x", i_id );
        return;
    }

    /* Add a new ES */
    if( tk->fmt.i_cat == VIDEO_ES )
    {
        tk->fmt.video.i_sar_num = p_sys->sar.i_num;
        tk->fmt.video.i_sar_den = p_sys->sar.i_den;
        b_select = true;
    }
    else if( tk->fmt.i_cat == AUDIO_ES )
    {
        int i_audio = -1;
        /* find the audio number PLEASE find another way */
        if( (i_id&0xbdf8) == 0xbd88 )       /* dts */
        {
            i_audio = i_id&0x07;
        }
        else if( (i_id&0xbdf0) == 0xbd80 )  /* a52 */
        {
            i_audio = i_id&0xf;
        }
        else if( (i_id&0xbdf0) == 0xbda0 )  /* lpcm */
        {
            i_audio = i_id&0x1f;
        }
        else if( ( i_id&0xe0 ) == 0xc0 )    /* mpga */
        {
            i_audio = i_id&0x1f;
        }
        if( i_audio >= 0 )
        {
            int i_lang = dvdnav_audio_stream_to_lang( p_sys->dvdnav, i_audio );
            if( i_lang != 0xffff )
            {
                tk->fmt.psz_language = malloc( 3 );
                tk->fmt.psz_language[0] = (i_lang >> 8)&0xff;
                tk->fmt.psz_language[1] = (i_lang     )&0xff;
                tk->fmt.psz_language[2] = 0;
            }
            if( dvdnav_get_active_audio_stream( p_sys->dvdnav ) == i_audio )
            {
                b_select = true;
            }

            /* Audio track description from code_extension */
            audio_attr_t audio_attr;
            if( dvdnav_get_audio_attr( p_sys->dvdnav, i_audio, &audio_attr )
                == DVDNAV_STATUS_OK )
            {
                    if( audio_attr.code_extension < ARRAY_SIZE(dvd_audio_code_ext)
                    && dvd_audio_code_ext[audio_attr.code_extension] )
                    tk->fmt.psz_description =
                        strdup( vlc_gettext( dvd_audio_code_ext[audio_attr.code_extension] ) );
            }
        }
    }
    else if( tk->fmt.i_cat == SPU_ES )
    {
        int32_t i_title, i_part;
        int i_lang = dvdnav_spu_stream_to_lang( p_sys->dvdnav, i_id&0x1f );
        if( i_lang != 0xffff )
        {
            tk->fmt.psz_language = malloc( 3 );
            tk->fmt.psz_language[0] = (i_lang >> 8)&0xff;
            tk->fmt.psz_language[1] = (i_lang     )&0xff;
            tk->fmt.psz_language[2] = 0;
        }

        /* Subtitle track description from code_extension */
        subp_attr_t subp_attr;
        memset( &subp_attr, 0, sizeof(subp_attr) );
        if( dvdnav_get_spu_attr( p_sys->dvdnav, i_id&0x1f, &subp_attr )
            == DVDNAV_STATUS_OK )
        {
            if( subp_attr.code_extension < ARRAY_SIZE(dvd_spu_code_ext)
                && dvd_spu_code_ext[subp_attr.code_extension] )
                tk->fmt.psz_description =
                    strdup( vlc_gettext( dvd_spu_code_ext[subp_attr.code_extension] ) );

            if( subp_attr.code_extension == DVD_SUBP_CODE_EXT_FORCED )
                tk->fmt.subs.b_forced = true;
        }

        /* Palette */
        tk->fmt.subs.spu.palette[0] = SPU_PALETTE_DEFINED;
        memcpy( &tk->fmt.subs.spu.palette[1], p_sys->clut,
                16 * sizeof( uint32_t ) );

        /* We select only when we are not in the menu */
        int i_active_spu = dvdnav_get_active_spu_stream( p_sys->dvdnav );
        int i_title_ok = dvdnav_current_title_info( p_sys->dvdnav, &i_title, &i_part );
        if( i_title_ok == DVDNAV_STATUS_OK &&
            i_title > 0 && i_active_spu != -1 && DvdnavSpuIsSelected( p_sys ) &&
            (i_active_spu & 0x1f) == (i_id&0x1f) )
        {
            b_select = true;
            if( i_active_spu & DVDNAV_SPU_HIDDEN )
                tk->fmt.subs.b_forced = true;
        }
        msg_Dbg( p_demux, "spu es 0x%2.2x (subp %d) lang=%4.4x code_ext=%d "
                 "active_spu=%d (0x%2.2x) reg=%d title=%d select=%d forced=%d",
                 i_id, i_id & 0x1f, i_lang, subp_attr.code_extension,
                 i_active_spu, i_active_spu & 0xff, p_sys->i_spu_logical,
                 i_title_ok == DVDNAV_STATUS_OK ? i_title : -1,
                 b_select, tk->fmt.subs.b_forced );
    }

    tk->fmt.i_id = i_id;
    tk->es = es_out_Add( p_demux->out, &tk->fmt );
    if( b_select && tk->es )
    {
        es_out_Control( p_demux->out, ES_OUT_SET_ES, tk->es );
    }
    tk->b_configured = true;

    if( tk->fmt.i_cat == VIDEO_ES ) ButtonUpdate( p_demux, false );
}

/*****************************************************************************
 * Still image end
 *****************************************************************************/
static void StillTimer( void *p_data )
{
    demux_sys_t    *p_sys = p_data;

    vlc_mutex_lock( &p_sys->still.lock );
    if( likely(p_sys->still.b_enabled) )
    {
        p_sys->still.b_enabled = false;
        dvdnav_still_skip( p_sys->dvdnav );
    }
    vlc_mutex_unlock( &p_sys->still.lock );
}

static int EventMouse( vlc_object_t *p_vout, char const *psz_var,
                       vlc_value_t oldval, vlc_value_t val, void *p_data )
{
    demux_t *p_demux = p_data;
    demux_sys_t *p_sys = p_demux->p_sys;

    /* FIXME? PCI usage thread safe? */
    pci_t *pci = dvdnav_get_current_nav_pci( p_sys->dvdnav );
    int x = val.coords.x;
    int y = val.coords.y;

    if( psz_var[6] == 'm' ) /* mouse-moved */
        dvdnav_mouse_select( p_sys->dvdnav, pci, x, y );
    else
    {
        assert( psz_var[6] == 'c' ); /* mouse-clicked */

        ButtonUpdate( p_demux, true );
        dvdnav_mouse_activate( p_sys->dvdnav, pci, x, y );
    }
    (void)p_vout;
    (void)oldval;
    return VLC_SUCCESS;
}

static int EventIntf( vlc_object_t *p_input, char const *psz_var,
                      vlc_value_t oldval, vlc_value_t val, void *p_data )
{
    demux_t *p_demux = p_data;
    demux_sys_t *p_sys = p_demux->p_sys;

    if (val.i_int == INPUT_EVENT_VOUT)
    {
        if( p_sys->p_vout != NULL )
        {
            var_DelCallback( p_sys->p_vout, "mouse-moved", EventMouse, p_demux );
            var_DelCallback( p_sys->p_vout, "mouse-clicked", EventMouse, p_demux );
            vlc_object_release( p_sys->p_vout );
        }

        p_sys->p_vout = input_GetVout( (input_thread_t *)p_input );
        if( p_sys->p_vout != NULL )
        {
            var_AddCallback( p_sys->p_vout, "mouse-moved", EventMouse, p_demux );
            var_AddCallback( p_sys->p_vout, "mouse-clicked", EventMouse, p_demux );
            /* ★★ La sortie vidéo a été RECRÉÉE (bascule plein écran, changement
             * de fenêtre) : son décodeur de sous-images repart vierge, donc la
             * surbrillance du bouton courant a disparu de l'écran alors que la
             * navigation, elle, fonctionne toujours. Symptôme exact : plus
             * aucune flèche dans le menu après la bascule, mais un clic
             * sélectionne bien la bonne entrée, et les flèches ne réapparaissent
             * qu'en entrant dans un sous-menu (le premier événement HIGHLIGHT
             * suivant). On redemande donc une publication. */
            p_sys->b_highlight_refresh = true;
        }
    }
    (void) psz_var; (void) oldval;
    return VLC_SUCCESS;
}

/*****************************************************************************
 * ProbeDVD: very weak probing that avoids going too often into a dvdnav_open()
 *****************************************************************************/
static int ProbeDVD( const char *psz_name )
{
    if( !*psz_name )
        /* Triggers libdvdcss autodetection */
        return VLC_SUCCESS;

    int fd = vlc_open( psz_name, O_RDONLY | O_NONBLOCK );
    if( fd == -1 )
#ifdef HAVE_FDOPENDIR
        return VLC_EGENERIC;
#else
        return (errno == ENOENT) ? VLC_EGENERIC : VLC_SUCCESS;
#endif

    int ret = VLC_EGENERIC;
    struct stat stat_info;

    if( fstat( fd, &stat_info ) == -1 )
         goto bailout;
    if( !S_ISREG( stat_info.st_mode ) )
    {
        if( S_ISDIR( stat_info.st_mode ) || S_ISBLK( stat_info.st_mode ) )
            ret = VLC_SUCCESS; /* Let dvdnav_open() do the probing */
        goto bailout;
    }

    /* ISO 9660 volume descriptor */
    char iso_dsc[6];
    if( lseek( fd, 0x8000 + 1, SEEK_SET ) == -1
     || read( fd, iso_dsc, sizeof (iso_dsc) ) < (int)sizeof (iso_dsc)
     || memcmp( iso_dsc, "CD001\x01", 6 ) )
        goto bailout;

    /* Try to find the anchor (2 bytes at LBA 256) */
    uint16_t anchor;

    if( lseek( fd, 256 * DVD_VIDEO_LB_LEN, SEEK_SET ) != -1
     && read( fd, &anchor, 2 ) == 2
     && GetWLE( &anchor ) == 2 )
        ret = VLC_SUCCESS; /* Found a potential anchor */
bailout:
    vlc_close( fd );
    return ret;
}
