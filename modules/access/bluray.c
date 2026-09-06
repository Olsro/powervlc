/*****************************************************************************
 * bluray.c: Blu-ray disc support plugin
 *****************************************************************************
 * Copyright © 2010-2012 VideoLAN, VLC authors and libbluray AUTHORS
 *
 * Authors: Jean-Baptiste Kempf <jb@videolan.org>
 *          Hugo Beauzée-Luyssen <hugo@videolan.org>
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <assert.h>
#include <ctype.h>      /* isalpha() */
#ifdef _WIN32
# include <windows.h>   /* GetUserDefaultUILanguage() */
# include <wctype.h>    /* iswalpha() */
#endif

#ifdef HAVE_GETMNTENT_R
# include <mntent.h>
#endif
#include <fcntl.h>      /* O_* */
#include <unistd.h>     /* close() */
#include <sys/stat.h>

#ifdef __APPLE__
# include <CoreFoundation/CoreFoundation.h>
# include <sys/param.h>
# include <sys/ucred.h>
# include <sys/mount.h>
# include <dlfcn.h>
# include "bluray_darwin_disc.h"
#endif

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_demux.h>                      /* demux_t */
#include <vlc_input.h>                      /* Seekpoints, chapters */
#include <vlc_atomic.h>
#include <vlc_dialog.h>                     /* BD+/AACS warnings */
#include <vlc_vout.h>                       /* vout_PutSubpicture / subpicture_t */
#include <vlc_vout_osd.h>                   /* vout_OSDMessage */
#include <vlc_url.h>                        /* vlc_path2uri */
#include <vlc_iso_lang.h>
#include <vlc_fs.h>

#include "../demux/mpeg/timestamps.h"
#include "../demux/timestamps_filter.h"

/* FIXME we should find a better way than including that */
#include "../../src/text/iso-639_def.h"


#include <libbluray/bluray.h>
#include <libbluray/bluray-version.h>
#include <libbluray/keys.h>
#include <libbluray/meta_data.h>
#include <libbluray/overlay.h>
#include <libbluray/clpi_data.h>
#include <libbluray/filesystem.h>
#include <libbluray/mpls_data.h>

#include "bluray_keydb.h"

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/

#define BD_MENU_TEXT        N_("Blu-ray menus")
#define BD_MENU_LONGTEXT    N_("Use Blu-ray menus. If disabled, "\
                                "the movie will start directly. Some discs "\
                                "run their menus as a Java (BD-J) application "\
                                "that keeps one processor core busy for as "\
                                "long as the disc is playing, so disabling "\
                                "menus can matter on an older machine.")
#define BD_LIVE_TEXT        N_("Allow BD-Live network access")
#define BD_LIVE_LONGTEXT    N_("Allow Blu-ray Java applications to contact "\
                                "Internet servers. Disabled by default for "\
                                "privacy and because many BD-Live services "\
                                "are obsolete; enabling it may delay menus.")
#define BD_REGION_TEXT      N_("Region code")
#define BD_REGION_LONGTEXT  N_("Blu-Ray player region code. "\
                                "Some discs can be played only with a correct region code.")
#define BD_FORCED_SUBS_TEXT     N_("Show forced subtitles")
#define BD_FORCED_SUBS_LONGTEXT N_("When the disc hides the subtitle stream, "\
                                "keep decoding it and display only its forced "\
                                "captions, as a standalone Blu-ray player does.")
#define BD_KEYDB_PL_TEXT     N_("Use the main playlist from the key database")
#define BD_KEYDB_PL_LONGTEXT N_("Some discs hide the feature among hundreds of "\
                                "decoy playlists of the same length, so the longest "\
                                "one is not the right one. When playing without menus, "\
                                "start on the playlist your KEYDB.cfg records for this "\
                                "disc, if it records one. Titles are named after their "\
                                ".mpls file either way, so another one can still be picked.")

static const char *const ppsz_region_code[] = {
    "A", "B", "C" };
static const char *const ppsz_region_code_text[] = {
    "Region A", "Region B", "Region C" };

#define REGION_DEFAULT   1   /* Index to region list. Actual region code is (1<<REGION_DEFAULT) */
#define LANGUAGE_DEFAULT ("eng")

#if BLURAY_VERSION >= BLURAY_VERSION_CODE(0,8,0)
# define BLURAY_DEMUX
#endif

#ifndef BD_STREAM_TYPE_VIDEO_HEVC
# define BD_STREAM_TYPE_VIDEO_HEVC 0x24
#endif

#define BD_CLUSTER_SIZE 6144
#define BD_READ_SIZE    (10 * BD_CLUSTER_SIZE)

/* Main and dependent M2TS files do not have proportional byte offsets when
 * their elementary-stream bitrates vary.  Rio's 00945/00948 pair, for
 * example, has identical PTS for all 3888 access units but the dependent
 * offset runs as much as 14 MiB ahead of the whole-file byte ratio.  Keep a
 * small timestamp lead and catch up in bounded bursts instead of waiting for
 * that approximation to starve one eye. */
#define MVC_TARGET_TIME_LEAD VLC_TICK_FROM_MS(750)
#define MVC_FEED_BURST       (4 * BD_READ_SIZE)
#define MVC_MAX_BYTE_LEAD    (UINT64_C(64) * 1024 * 1024)
#define MVC_QUEUE_LIMIT      256
#define MVC_TIMESTAMP_TOLERANCE VLC_TICK_FROM_MS(1)

/* Callbacks */
static int  blurayOpen (vlc_object_t *);
static void blurayClose(vlc_object_t *);

vlc_module_begin ()
    set_shortname(N_("Blu-ray"))
    set_description(N_("Blu-ray Disc support (libbluray)"))

    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_ACCESS)
    set_capability("access_demux", 200)
    add_bool("bluray-menu", true, BD_MENU_TEXT, BD_MENU_LONGTEXT, false)
    add_bool("bluray-bd-live", false, BD_LIVE_TEXT, BD_LIVE_LONGTEXT, true)
    add_bool("bluray-forced-subs", true, BD_FORCED_SUBS_TEXT, BD_FORCED_SUBS_LONGTEXT, false)
    add_string("bluray-region", ppsz_region_code[REGION_DEFAULT], BD_REGION_TEXT, BD_REGION_LONGTEXT, false)
        change_string_list(ppsz_region_code, ppsz_region_code_text)
    add_bool("bluray-keydb-playlist", true, BD_KEYDB_PL_TEXT, BD_KEYDB_PL_LONGTEXT, false)

    add_shortcut("bluray", "file")

    set_callbacks(blurayOpen, blurayClose)

#ifdef BLURAY_DEMUX
    /* demux module */
    add_submodule()
        set_description( "BluRay demuxer" )
        set_category( CAT_INPUT )
        set_subcategory( SUBCAT_INPUT_DEMUX )
        set_capability( "demux", 5 )
        set_callbacks( blurayOpen, blurayClose )
#endif

vlc_module_end ()

/* libbluray's overlay.h defines 2 types of overlay (bd_overlay_plane_e). */
#define MAX_OVERLAY 2

typedef enum OverlayStatus {
    Closed = 0,
    ToDisplay,  //Used to mark the overlay to be displayed the first time.
    Displayed,
    Outdated    //used to update the overlay after it has been sent to the vout
} OverlayStatus;

typedef struct bluray_overlay_t
{
    vlc_mutex_t         lock;
    int                 i_channel;
    OverlayStatus       status;
    subpicture_region_t *p_regions;
    int                 width, height;
    int                 stereo_offset;
    int64_t             i_pts;
    vlc_tick_t          i_update_date;
    video_palette_t     palette;
    bool                b_palette_valid;

    /* pointer to last subpicture updater.
     * used to disconnect this overlay from vout when:
     * - the overlay is closed
     * - vout is changed and this overlay is sent to the new vout
     */
    struct subpicture_updater_sys_t *p_updater;
} bluray_overlay_t;

struct  demux_sys_t
{
    BLURAY              *bluray;
    bool                b_draining;
    bool                b_bdj_session_held;
    /* A target is armed only by PowerVLC's explicit time/position/chapter
     * controls.  BD-J also emits BD_EVENT_SEEK for its own menu and play-item
     * transitions, so deriving preroll from every PCR reset makes feature
     * video leak underneath menu overlays. */
    bool                b_user_seek_preroll;
    vlc_tick_t          i_user_seek_preroll;

    /* Titles */
    unsigned int        i_title;
    unsigned int        i_longest_title;
    input_title_t       **pp_title;

    /* Events */
    DECL_ARRAY(BD_EVENT) events_delayed;

    vlc_mutex_t             pl_info_lock;
    BLURAY_TITLE_INFO      *p_pl_info;
    const BLURAY_CLIP_INFO *p_clip_info;
    enum
    {
        BD_CLIP_APP_TYPE_TS_MAIN_PATH_MOVIE = 1,
        BD_CLIP_APP_TYPE_TS_MAIN_PATH_TIMED_SLIDESHOW = 2,
        BD_CLIP_APP_TYPE_TS_MAIN_PATH_BROWSABLE_SLIDESHOW = 3,
        BD_CLIP_APP_TYPE_TS_SUB_PATH_BROWSABLE_SLIDESHOW = 4,
        BD_CLIP_APP_TYPE_TS_SUB_PATH_INTERACTIVE_MENU = 5,
        BD_CLIP_APP_TYPE_TS_SUB_PATH_TEXT_SUBTITLE = 6,
        BD_CLIP_APP_TYPE_TS_SUB_PATH_ELEMENTARY_STREAM_PATH = 7,
    } clip_application_type;

    /* Attachments */
    int                 i_attachments;
    input_attachment_t  **attachments;
    int                 i_cover_idx;

    /* Meta information */
    const META_DL       *p_meta;

    /* Menus */
    bluray_overlay_t    *p_overlays[MAX_OVERLAY];
    bool                b_fatal_error;
    bool                b_menu;
    bool                b_menu_open;
    /* A newly opened disc may inherit a live HDMI 3D session and the exact
     * same MVC vout format, in which case the display module is not reopened. */
    bool                b_inherited_stereo_presentation;
    bool                b_stereo_presentation_checked;
    uint64_t            i_uo_mask;
    bool                b_bdj_overlay;      /* BD-J ARGB plane is up, see
                                             * blurayCacheInhibitUpdate() */
    bool                b_popup_available;
    vlc_tick_t          i_last_ig_user_input;
    vlc_tick_t          i_last_ig_activation;
    vlc_tick_t          i_still_end_time;
    bool                b_bdj_still_codec_override;
    bool                b_bdj_still_codec_restart_pending;
    bool                b_had_input_codec;
    char                *psz_codec_before_bdj_still;

    vlc_mutex_t         bdj_overlay_lock; /* used to lock BD-J overlay open/close while overlays are being sent to vout */

    /* */
    vout_thread_t       *p_vout;

    es_out_id_t         *p_dummy_video;

    /* TS stream */
    es_out_t            *p_tf_out;
    es_out_t            *p_out;
    es_out_t            *p_esc_out;
    bool                b_spu_enable;       /* enabled / disabled */
    vlc_demux_chained_t *p_parser;
    vlc_demux_chained_t *p_mvc_parser;      /* stereoscopic extension TS */
    es_out_t            *p_mvc_out;         /* filters the extension to PID 0x1012 */
    BD_FILE_H           *p_mvc_file;
    int                 i_mvc_sub_path;
    int                 i_mvc_clip;
    int                 i_current_playitem;
    bool                b_stereoscopic_output; /* PSR22 / disc-selected mode */
    uint64_t            i_mvc_main_size;
    uint64_t            i_mvc_clip_size;
    uint64_t            i_mvc_main_read;
    uint64_t            i_mvc_clip_read;
    bool                b_mvc_feed_catching_up;
    bool                b_flushed;
    bool                b_pl_playing;       /* true when playing playlist */
    bool                b_have_playitem;    /* the first item establishes the
                                             * input clock; later ones join clips */
    bool                b_playitem_reset_pending; /* suppress the duplicate
                                                   * discontinuity event in
                                                   * the same read batch */
    int                 i_playitem_seen_in_batch; /* libbluray can enqueue the
                                                   * same PLAYITEM twice */
    bool                b_mvc_playlist_handoff; /* keep the HDMI 3D vout while
                                                 * two MVC playlists join */
    bool                b_cache_inhibited;  /* look-ahead cache, see blurayCacheInhibitUpdate() */

    /* stream input */
    vlc_mutex_t         read_block_lock;

    /* Used to store bluray disc path */
    char                *psz_bd_path;
#ifdef __APPLE__
    /* Set only where the disc has to be read over MMC (10.4); NULL otherwise. */
    bluray_disc_t        *p_mmc;
#endif
};

/* libbluray embeds one process-wide JVM and its Java bridge keeps process-wide
 * static state (nativePointer, registered native methods and action manager).
 * An input can be opened while the preceding input is still being destroyed,
 * so serialize complete BD-J lifetimes rather than merely individual calls. */
static vlc_mutex_t bdj_session_lock = VLC_STATIC_MUTEX;
static vlc_cond_t bdj_session_wait = VLC_STATIC_COND;
static bool bdj_session_active = false;

static void blurayAcquireBdjSession(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    vlc_mutex_lock(&bdj_session_lock);
    while (bdj_session_active) {
        msg_Dbg(p_demux, "waiting for the previous BD-J session to shut down");
        vlc_cond_wait(&bdj_session_wait, &bdj_session_lock);
    }
    bdj_session_active = true;
    p_sys->b_bdj_session_held = true;
    vlc_mutex_unlock(&bdj_session_lock);
}

static void blurayReleaseBdjSession(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if (!p_sys->b_bdj_session_held)
        return;

    vlc_mutex_lock(&bdj_session_lock);
    p_sys->b_bdj_session_held = false;
    bdj_session_active = false;
    vlc_cond_signal(&bdj_session_wait);
    vlc_mutex_unlock(&bdj_session_lock);
}

/*
 * Local ES index storage
 */
typedef struct
{
    es_format_t fmt;
    es_out_id_t *p_es;
    int i_next_block_flags;
    bool b_recyling;
} es_pair_t;

/* MVC base and dependent views are carried as separate PES streams in an
 * SSIF/M2TS.  The decoder must receive the NAL units belonging to the same
 * access unit together, just as a demuxer would deliver a single AVC stream. */
typedef struct
{
    block_t *first;
    block_t **last;
    unsigned count;
} mvc_block_queue_t;

static void mvcQueueInit(mvc_block_queue_t *queue)
{
    queue->first = NULL;
    queue->last = &queue->first;
    queue->count = 0;
}

static void mvcQueueRelease(mvc_block_queue_t *queue)
{
    block_ChainRelease(queue->first);
    mvcQueueInit(queue);
}

static void mvcQueuePush(mvc_block_queue_t *queue, block_t *block)
{
    if (block->p_next != NULL)
        block = block_ChainGather(block);
    if (block == NULL)
        return;
    block->p_next = NULL;
    *queue->last = block;
    queue->last = &block->p_next;
    queue->count++;
}

static block_t *mvcQueuePop(mvc_block_queue_t *queue)
{
    block_t *block = queue->first;
    if (block == NULL)
        return NULL;
    queue->first = block->p_next;
    block->p_next = NULL;
    queue->count--;
    if (queue->first == NULL)
        queue->last = &queue->first;
    return block;
}

static vlc_tick_t mvcBlockDate(const block_t *block)
{
    return block->i_dts != VLC_TICK_INVALID ? block->i_dts : block->i_pts;
}

static bool es_pair_Add(vlc_array_t *p_array, const es_format_t *p_fmt,
                        es_out_id_t *p_es)
{
    es_pair_t *p_pair = malloc(sizeof(*p_pair));
    if (likely(p_pair != NULL))
    {
        p_pair->p_es = p_es;
        p_pair->i_next_block_flags = 0;
        p_pair->b_recyling = false;
        if(vlc_array_append(p_array, p_pair) != VLC_SUCCESS)
        {
            free(p_pair);
            p_pair = NULL;
        }
        else
        {
            es_format_Init(&p_pair->fmt, p_fmt->i_cat, p_fmt->i_codec);
            es_format_Copy(&p_pair->fmt, p_fmt);
        }
    }
    return p_pair != NULL;
}

static void es_pair_Remove(vlc_array_t *p_array, es_pair_t *p_pair)
{
    vlc_array_remove(p_array, vlc_array_index_of_item(p_array, p_pair));
    es_format_Clean(&p_pair->fmt);
    free(p_pair);
}

static es_pair_t *getEsPair(vlc_array_t *p_array,
                            bool (*match)(const es_pair_t *, const void *),
                            const void *param)
{
    for (size_t i = 0; i < vlc_array_count(p_array); ++i)
    {
        es_pair_t *p_pair = vlc_array_item_at_index(p_array, i);
        if(match(p_pair, param))
            return p_pair;
    }
    return NULL;
}

static bool es_pair_compare_PID(const es_pair_t *p_pair, const void *p_pid)
{
    return p_pair->fmt.i_id == *((const int *)p_pid);
}

static bool es_pair_compare_ES(const es_pair_t *p_pair, const void *p_es)
{
    return p_pair->p_es == (const es_out_id_t *)p_es;
}

static bool es_pair_compare_Unused(const es_pair_t *p_pair, const void *priv)
{
    VLC_UNUSED(priv);
    return p_pair->b_recyling;
}

static es_pair_t *getEsPairByPID(vlc_array_t *p_array, int i_pid)
{
    return getEsPair(p_array, es_pair_compare_PID, &i_pid);
}

static es_pair_t *getEsPairByES(vlc_array_t *p_array, const es_out_id_t *p_es)
{
    return getEsPair(p_array, es_pair_compare_ES, p_es);
}

static es_pair_t *getUnusedEsPair(vlc_array_t *p_array)
{
    return getEsPair(p_array, es_pair_compare_Unused, 0);
}

/*
 * Subpicture updater
*/
struct subpicture_updater_sys_t
{
    vlc_mutex_t          lock;      // protect p_overlay pointer and ref_cnt
    bluray_overlay_t    *p_overlay; // NULL if overlay has been closed
    int                  ref_cnt;   // one reference in vout (subpicture_t), one in input (bluray_overlay_t)
};

/*
 * cut the connection between vout and overlay.
 * - called when vout is closed or overlay is closed.
 * - frees subpicture_updater_sys_t when both sides have been closed.
 */
static void unref_subpicture_updater(subpicture_updater_sys_t *p_sys)
{
    vlc_mutex_lock(&p_sys->lock);
    int refs = --p_sys->ref_cnt;
    p_sys->p_overlay = NULL;
    vlc_mutex_unlock(&p_sys->lock);

    if (refs < 1) {
        vlc_mutex_destroy(&p_sys->lock);
        free(p_sys);
    }
}

/* Get a 3 char code
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

/* Interface language, the way gettext sees it. Kept in step with the same
 * helper in dvdnav.c -- a Blu-ray reads its player language registers
 * (PSR16/17/18) exactly as a DVD reads its SPRMs, and answering "eng" to a
 * disc because nobody typed a preference declares the user an English
 * speaker to EVERY disc: a French Blu-ray then takes its English branch and
 * its BD-J menus come up in English on a French install (measured on
 * Windows XP with RIO, 14/08/2026). */
static const char *DemuxGetUILanguage( char *psz_buffer, size_t i_size )
{
    static const char *const ppsz_vars[] =
        { "LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG" };

    for( size_t i = 0; i < ARRAY_SIZE(ppsz_vars); i++ )
    {
        const char *psz_env = getenv( ppsz_vars[i] );
        if( psz_env == NULL )
            continue;

        /* "fr", "fr_FR", "fr_FR.UTF-8", "fr_FR@euro", "fr:en" */
        size_t i_len = 0;
        while( isalpha( (unsigned char)psz_env[i_len] ) )
            i_len++;
        /* rejects "C" and "POSIX", which are not languages */
        if( i_len < 2 || i_len > 3 || i_len >= i_size )
            continue;

        memcpy( psz_buffer, psz_env, i_len );
        psz_buffer[i_len] = '\0';
        return psz_buffer;
    }

#ifdef __APPLE__
    /* Finder-launched applications normally have no useful POSIX locale, and
     * inherited shells can even provide C.UTF-8 while AppKit correctly uses
     * French.  Ask the same native preference that macOS uses for the UI. */
    /* CFLocaleCopyPreferredLanguages() was added after the 10.4 SDK.  The
     * underlying AppleLanguages preference has existed since the first OS X
     * releases and is also what Finder-launched applications use there. */
    CFPropertyListRef language_pref = CFPreferencesCopyAppValue(
        CFSTR("AppleLanguages"), kCFPreferencesCurrentApplication );
    CFArrayRef languages = NULL;
    if( language_pref != NULL )
    {
        if( CFGetTypeID( language_pref ) == CFArrayGetTypeID() )
            languages = (CFArrayRef)language_pref;
        else
        {
            CFRelease( language_pref );
            language_pref = NULL;
        }
    }
    if( languages != NULL )
    {
        if( CFArrayGetCount( languages ) > 0 )
        {
            CFStringRef preferred = CFArrayGetValueAtIndex( languages, 0 );
            CFStringRef canonical =
                CFLocaleCreateCanonicalLanguageIdentifierFromString(
                    kCFAllocatorDefault, preferred );
            char psz_locale[64];

            if( canonical != NULL &&
                CFStringGetCString( canonical, psz_locale, sizeof(psz_locale),
                                    kCFStringEncodingUTF8 ) )
            {
                size_t i_len = 0;
                while( isalpha( (unsigned char)psz_locale[i_len] ) )
                    i_len++;
                if( i_len >= 2 && i_len <= 3 && i_len < i_size )
                {
                    memcpy( psz_buffer, psz_locale, i_len );
                    psz_buffer[i_len] = '\0';
                    CFRelease( canonical );
                    CFRelease( languages );
                    return psz_buffer;
                }
            }
            if( canonical != NULL )
                CFRelease( canonical );
        }
        CFRelease( languages );
    }
#endif

#ifdef _WIN32
    /* An empty environment does not mean "no preference" here: winvlc only
     * exports LANG when a language was picked by hand, and on "auto" gettext
     * asks Windows itself (GETTEXT_MUI). Ask it the same question. */
    {
        LANGID langid = GetUserDefaultUILanguage();
        wchar_t wbuf[16];
        int i_wlen = GetLocaleInfoW( MAKELCID( langid, SORT_DEFAULT ),
                                     LOCALE_SISO639LANGNAME,
                                     wbuf, ARRAY_SIZE(wbuf) );
        size_t i_len = 0;
        while( i_wlen > 0 && wbuf[i_len] != L'\0'
            && iswalpha( wbuf[i_len] ) && i_len + 1 < i_size )
        {
            psz_buffer[i_len] = (char)wbuf[i_len];
            i_len++;
        }
        if( i_len >= 2 )
        {
            psz_buffer[i_len] = '\0';
            return psz_buffer;
        }
    }
#endif

    return NULL;
}

static const char *DemuxGetLanguageCode( demux_t *p_demux, const char *psz_var )
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

    return pl != NULL ? pl->psz_iso639_2T : LANGUAGE_DEFAULT;
}

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
static es_out_t *esOutNew(vlc_object_t*, es_out_t *, void *);
static es_out_t *escape_esOutNew(vlc_object_t *, es_out_t *);
static es_out_t *mvc_esOutNew(es_out_t *);

static int   blurayControl(demux_t *, int, va_list);
static int   blurayDemux(demux_t *);

static void  blurayInitTitles(demux_t *p_demux, uint32_t menu_titles);
static int   bluraySetTitle(demux_t *p_demux, int i_title);
static bool  blurayIsBdjTitle(demux_t *p_demux);
static void  bluraySetBdjStillDecoder(demux_t *p_demux, bool enable);

static void  blurayOverlayProc(void *ptr, const BD_OVERLAY * const overlay);
static void  blurayArgbOverlayProc(void *ptr, const BD_ARGB_OVERLAY * const overlay);

static int   onMouseEvent(vlc_object_t *p_vout, const char *psz_var,
                          vlc_value_t old, vlc_value_t val, void *p_data);
static int   onIntfEvent(vlc_object_t *, char const *,
                         vlc_value_t, vlc_value_t, void *);

static void  blurayRestartParser(demux_t *p_demux, bool, bool);
static void  blurayCloseMVCClip(demux_t *p_demux);
static void  blurayOpenMVCClip(demux_t *p_demux, uint32_t clip);
static void  blurayFeedMVC(demux_t *p_demux, size_t main_bytes);
static void  bluraySeekMVC(demux_t *p_demux);
static void  notifyDiscontinuityToParser( demux_sys_t *p_sys );


#define STILL_IMAGE_NOT_SET    0
#define STILL_IMAGE_INFINITE  -1

#define CURRENT_TITLE p_sys->pp_title[p_demux->info.i_title]
#define CUR_LENGTH    CURRENT_TITLE->i_length

/* */
static void FindMountPoint(char **file)
{
    char *device = *file;
#ifdef HAVE_GETMNTENT_R
    /* bd path may be a symlink (e.g. /dev/dvd -> /dev/sr0), so make sure
     * we look up the real device */
    char *bd_device = realpath(device, NULL);
    if (bd_device == NULL)
        return;

    struct stat st;
    if (lstat (bd_device, &st) == 0 && S_ISBLK (st.st_mode)) {
        FILE *mtab = setmntent ("/proc/self/mounts", "r");
        if (mtab) {
            struct mntent *m, mbuf;
            char buf [8192];

            while ((m = getmntent_r (mtab, &mbuf, buf, sizeof(buf))) != NULL) {
                if (!strcmp (m->mnt_fsname, bd_device)) {
                    free(device);
                    *file = strdup(m->mnt_dir);
                    break;
                }
            }
            endmntent (mtab);
        }
    }
    free(bd_device);

#elif defined(__APPLE__)
    struct stat st;
    if (!stat (device, &st) && S_ISBLK (st.st_mode)) {
        int fs_count = getfsstat (NULL, 0, MNT_NOWAIT);
        if (fs_count > 0) {
            int bufSize = fs_count * sizeof (struct statfs);
            struct statfs* mbuf = malloc(bufSize);
            getfsstat (mbuf, bufSize, MNT_NOWAIT);
            for (int i = 0; i < fs_count; ++i)
                if (!strcmp (mbuf[i].f_mntfromname, device)) {
                    free(device);
                    *file = strdup(mbuf[i].f_mntonname);
                    free(mbuf);
                    return;
                }

            free(mbuf);
        }
    }
#else
# warning Disc device to mount point not implemented
    VLC_UNUSED( device );
#endif
}

#ifdef __APPLE__
/*
 * Prefer the raw device node over the mount point.
 *
 * Mac OS X 10.6 regressed its UDF driver: it issues one SCSI command per 2048
 * byte sector with no clustering at all, which caps a mounted BD-ROM at about
 * 21 Mbps over USB 2 (measured with iostat: KB/t = 2.00, ~1300 tps). Retail
 * titles run well above that -- the reference disc here averages 31.5 Mbps --
 * so the demuxer starves, pts_delay climbs and playback rebuffers every few
 * seconds. Reading the device directly and letting libbluray's own UDF reader
 * do the parsing issues 6 KB requests instead, which the same drive answers at
 * 75 Mbps; larger requests reach 149 Mbps. 10.5 does cluster (KB/t = 170) and
 * does not need this, but the raw path is no slower there.
 *
 * Falls back to whatever it was given when the raw device cannot actually be
 * read. That is not hypothetical: 10.4 has no Blu-ray storage family, so it
 * misdetects BD media as a CD with 2352 byte blocks and every read on the
 * device returns EOF -- the disc does not even mount there. Probing with a real
 * read rather than open() is what tells the two apart.
 */
static bool FindRawDevice(char **file)
{
    char *path = *file;
    char *raw = NULL;

    if (!strncmp(path, "/dev/r", 6)) {
        /* Already a raw device node -- but still probe it below rather than
         * trusting the name: on 10.4 the node exists and opens, and only a
         * read reveals that it answers EOF. */
        raw = strdup(path);
        if (raw == NULL)
            return false;
    } else if (!strncmp(path, "/dev/", 5)) {
        if (asprintf(&raw, "/dev/r%s", path + 5) < 0)
            return false;
    } else {
        /* a mount point: statfs gives the block device backing it */
        struct statfs st;
        if (statfs(path, &st) != 0
         || strncmp(st.f_mntfromname, "/dev/", 5)
         || asprintf(&raw, "/dev/r%s", st.f_mntfromname + 5) < 0)
            return false;
    }

    /* One aligned sector is enough to tell a working device node from one that
     * answers EOF. The buffer has to be page aligned, not just the offset and
     * length: an unaligned one goes down the kernel's physio path and faults on
     * Tiger. valloc() rather than posix_memalign(), which is 10.6+. */
    bool b_usable = false;
    int fd = vlc_open(raw, O_RDONLY);
    if (fd != -1) {
        void *buf = valloc(2048);
        if (buf != NULL) {
            b_usable = read(fd, buf, 2048) == 2048;
            free(buf);
        }
        vlc_close(fd);
    }

    if (!b_usable) {
        free(raw);
        return false;
    }

    free(*file);
    *file = raw;
    return true;
}

/* Hands our MMC channel to libaacs, which cannot open its own: SCSITaskLib
 * grants exclusive access to a single owner. libbluray dlopen()s libaacs by the
 * path SetupDiscLibPath() exported, so opening that same path here yields the
 * very same image and therefore the same globals. Absent from older libaacs
 * builds, hence the dlsym() rather than a direct call. */
static void ShareMMCWithLibaacs(demux_t *p_demux, void *task_interface)
{
    const char *psz_lib = getenv("LIBAACS_PATH");
    if (psz_lib == NULL)
        return;

    /* SetupDiscLibPath() exports the path *without* the extension, because that
     * is what libbluray expects to append to. dlopen() needs the real file. */
    char *psz_file;
    if (asprintf(&psz_file, "%s.dylib", psz_lib) < 0)
        return;

    void *handle = dlopen(psz_file, RTLD_LAZY | RTLD_LOCAL);
    free(psz_file);
    if (handle == NULL) {
        msg_Warn(p_demux, "could not open %s.dylib to share the MMC channel",
                 psz_lib);
        return;
    }

    void (*pf_use)(void *) = dlsym(handle, "aacs_use_external_mmc");
    if (pf_use != NULL) {
        pf_use(task_interface);
        msg_Dbg(p_demux, "handed the MMC channel to libaacs");
    } else {
        msg_Warn(p_demux, "this libaacs cannot share our MMC channel; "
                 "AACS discs will need a keydb entry");
    }
    /* deliberately not dlclose()d: libbluray holds the same image anyway, and
     * closing it would drop the pointer just installed. */
}
#endif

static void blurayReleaseVout(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if (p_sys->p_vout != NULL) {
        var_DelCallback(p_sys->p_vout, "mouse-moved", onMouseEvent, p_demux);
        var_DelCallback(p_sys->p_vout, "mouse-clicked", onMouseEvent, p_demux);

        for (int i = 0; i < MAX_OVERLAY; i++) {
            bluray_overlay_t *p_ov = p_sys->p_overlays[i];
            if (p_ov) {
                vlc_mutex_lock(&p_ov->lock);
                if (p_ov->i_channel != -1) {
                    /* A title transition can retire the current vout while a
                     * BD-J graphics plane is still registered.  Flushing its
                     * channel here is the normal hand-off to the replacement
                     * vout, not a playback failure. */
                    msg_Dbg(p_demux, "flushing Blu-ray subpicture channel before releasing vout");
                    vout_FlushSubpictureChannel(p_sys->p_vout, p_ov->i_channel);
                }
                p_ov->i_channel = -1;
                p_ov->status = ToDisplay;
                vlc_mutex_unlock(&p_ov->lock);

                if (p_ov->p_updater) {
                    unref_subpicture_updater(p_ov->p_updater);
                    p_ov->p_updater = NULL;
                }
            }
        }

        vlc_object_release(p_sys->p_vout);
        p_sys->p_vout = NULL;
    }
}

/*****************************************************************************
 * BD-J background video
 *****************************************************************************/

static es_out_id_t * blurayCreateBackgroundUnlocked(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if (p_sys->p_dummy_video)
        return p_sys->p_dummy_video;

    msg_Info(p_demux, "Start background");

    /* */
    es_format_t fmt;
    es_format_Init( &fmt, VIDEO_ES, VLC_CODEC_I420 );
    video_format_Setup( &fmt.video, VLC_CODEC_I420,
                        1920, 1080, 1920, 1080, 1, 1);
    fmt.i_priority = ES_PRIORITY_SELECTABLE_MIN;
    fmt.i_id = 4115; /* 4113 = main video. 4114 = MVC. 4115 = unused. */
    fmt.i_group = 1;

    p_sys->p_dummy_video = es_out_Add(p_demux->out, &fmt);

    if (!p_sys->p_dummy_video) {
        msg_Err(p_demux, "Error adding background ES");
        goto out;
    }

    /* A stalled playlist may already own the selected video slot even though
     * it has never produced a frame.  Explicitly select the synthetic ES so
     * the ARGB plane gets a vout; relying on automatic selection only works
     * when the BD-J application has no playlist at all. */
    es_out_Control(p_demux->out, ES_OUT_SET_ES, p_sys->p_dummy_video);

    block_t *p_block = block_Alloc(fmt.video.i_width * fmt.video.i_height *
                                   fmt.video.i_bits_per_pixel / 8);
    if (!p_block) {
        msg_Err(p_demux, "Error allocating block for background video");
        goto out;
    }

    /* This is a demux timestamp, not a wall-clock deadline.  Using mdate()
     * here injects the machine uptime into the shared Blu-ray input clock.
     * A short-lived BD-J plane can be created between the title reset and
     * the first real movie PCR (Angry Birds does this for roughly 30 ms),
     * leaving all following movie pictures scheduled thousands of seconds
     * away until the late-picture recovery eventually purges them.
     *
     * Stay on the current media timeline when one exists.  Immediately after
     * a reset GET_CURRENT_PCR deliberately fails, so start the self-contained
     * synthetic stream at VLC_TICK_0 instead.  The next authored PCR can then
     * establish its own reference without inheriting machine uptime. */
    vlc_tick_t i_background_pcr = VLC_TICK_0;
    (void)es_out_Control(p_demux->out, ES_OUT_GET_CURRENT_PCR,
                         &i_background_pcr);
    const vlc_tick_t i_background_date =
        i_background_pcr + CLOCK_FREQ / 25;
    p_block->i_dts = p_block->i_pts = i_background_date;

    uint8_t *p = p_block->p_buffer;
    memset(p, 0, fmt.video.i_width * fmt.video.i_height);
    p += fmt.video.i_width * fmt.video.i_height;
    memset(p, 0x80, fmt.video.i_width * fmt.video.i_height / 2);

    /* Establish a clock reference for the synthetic stream.  Cars 3 keeps a
     * real but empty playlist selected, whose reset clock otherwise rejects
     * this absolute timestamp as being far in the future. */
    es_out_SetPCR(p_demux->out, i_background_pcr);
    es_out_Send(p_demux->out, p_sys->p_dummy_video, p_block);
    es_out_SetPCR(p_demux->out, i_background_date);

 out:
    es_format_Clean(&fmt);
    return p_sys->p_dummy_video;
}

static void stopBackground(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if (!p_sys->p_dummy_video) {
        return;
    }

    msg_Info(p_demux, "Stop background");

    es_out_Del(p_demux->out, p_sys->p_dummy_video);
    p_sys->p_dummy_video = NULL;
}

/*****************************************************************************
 * cache current playlist (title) information
 *****************************************************************************/

static void setTitleInfo(demux_sys_t *p_sys, BLURAY_TITLE_INFO *info)
{
    vlc_mutex_lock(&p_sys->pl_info_lock);

    if (p_sys->p_pl_info) {
        bd_free_title_info(p_sys->p_pl_info);
    }
    p_sys->p_pl_info   = info;
    p_sys->p_clip_info = NULL;

    if (p_sys->p_pl_info && p_sys->p_pl_info->clip_count) {
        p_sys->p_clip_info = &p_sys->p_pl_info->clips[0];
    }

    vlc_mutex_unlock(&p_sys->pl_info_lock);
}

/*****************************************************************************
 * create input attachment for thumbnail
 *****************************************************************************/

static void attachThumbnail(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if (!p_sys->p_meta)
        return;

#if BLURAY_VERSION >= BLURAY_VERSION_CODE(0,9,0)
    if (p_sys->p_meta->thumb_count > 0 && p_sys->p_meta->thumbnails) {
        int64_t size;
        void *data;
        if (bd_get_meta_file(p_sys->bluray, p_sys->p_meta->thumbnails[0].path, &data, &size) > 0) {
            char psz_name[64];
            input_attachment_t *p_attachment;

            snprintf(psz_name, sizeof(psz_name), "picture%d_%s", p_sys->i_attachments, p_sys->p_meta->thumbnails[0].path);

            p_attachment = vlc_input_attachment_New(psz_name, NULL, "Album art", data, size);
            if (p_attachment) {
                p_sys->i_cover_idx = p_sys->i_attachments;
                TAB_APPEND(p_sys->i_attachments, p_sys->attachments, p_attachment);
            }
        }
        free(data);
    }
#endif
}

/*****************************************************************************
 * stream input
 *****************************************************************************/

static int probeStream(demux_t *p_demux)
{
    /* input must be seekable */
    bool b_canseek = false;
    vlc_stream_Control( p_demux->s, STREAM_CAN_SEEK, &b_canseek );
    if (!b_canseek) {
        return VLC_EGENERIC;
    }

    /* first sector(s) should be filled with zeros */
    ssize_t i_peek;
    const uint8_t *p_peek;
    i_peek = vlc_stream_Peek( p_demux->s, &p_peek, 2048 );
    if( i_peek != 2048 ) {
        return VLC_EGENERIC;
    }
    while (i_peek > 0) {
        if (p_peek[ --i_peek ]) {
            return VLC_EGENERIC;
        }
    }

    return VLC_SUCCESS;
}

#ifdef BLURAY_DEMUX
static int blurayReadBlock(void *object, void *buf, int lba, int num_blocks)
{
    demux_t *p_demux = (demux_t*)object;
    demux_sys_t *p_sys = p_demux->p_sys;
    int result = -1;

    assert(p_demux->s != NULL);

    vlc_mutex_lock(&p_sys->read_block_lock);

    if (vlc_stream_Seek( p_demux->s, lba * INT64_C(2048) ) == VLC_SUCCESS) {
        size_t  req = (size_t)2048 * num_blocks;
        ssize_t got;

        got = vlc_stream_Read( p_demux->s, buf, req);
        if (got < 0) {
            msg_Err(p_demux, "read from lba %d failed", lba);
        } else {
            result = got / 2048;
        }
    } else {
       msg_Err(p_demux, "seek to lba %d failed", lba);
    }

    vlc_mutex_unlock(&p_sys->read_block_lock);

    return result;
}
#endif

/*****************************************************************************
 * probing of local files
 *****************************************************************************/

/* Descriptor Tag (ECMA 167, 3/7.2) */
static int decode_descriptor_tag(const uint8_t *buf)
{
    uint16_t id;
    uint8_t  checksum = 0;
    int      i;

    id = buf[0] | (buf[1] << 8);

    /* calculate tag checksum */
    for (i = 0; i < 4; i++) {
        checksum = (uint8_t)(checksum + buf[i]);
    }
    for (i = 5; i < 16; i++) {
        checksum = (uint8_t)(checksum + buf[i]);
    }

    if (checksum != buf[4]) {
        return -1;
    }

    return id;
}

static int probeFile(const char *psz_name)
{
    struct stat stat_info;
    uint8_t peek[2048];
    unsigned i;
    int ret = VLC_EGENERIC;
    int fd;

    fd = vlc_open(psz_name, O_RDONLY | O_NONBLOCK);
    if (fd == -1) {
        return VLC_EGENERIC;
    }

    if (fstat(fd, &stat_info) == -1) {
        goto bailout;
    }
    if (!S_ISREG(stat_info.st_mode) && !S_ISBLK(stat_info.st_mode)) {
        goto bailout;
    }

    /* first sector should be filled with zeros */
    if (read(fd, peek, sizeof(peek)) != sizeof(peek)) {
        goto bailout;
    }
    for (i = 0; i < sizeof(peek); i++) {
        if (peek[ i ]) {
            goto bailout;
        }
    }

    /* Check AVDP tag checksum */
    if (lseek(fd, 256 * 2048, SEEK_SET) == -1 ||
        read(fd, peek, 16) != 16 ||
        decode_descriptor_tag(peek) != 2) {
        goto bailout;
    }

    ret = VLC_SUCCESS;

bailout:
    vlc_close(fd);
    return ret;
}

/*****************************************************************************
 * SetupDiscLibPath: point libbluray at the descrambling libraries we ship
 *
 * libbluray does not link against libaacs or libbdplus, it dlopen()s them
 * under plain names ("libaacs.dylib", "libbdplus.dll", "libaacs.so.0"...).
 * That relies on the platform library search path, which is fine for a
 * distribution package but not for the copies we bundle: an application bundle
 * is on no search path, and DYLD_/LD_LIBRARY_PATH cannot be counted on.
 * libbluray does try @executable_path itself on Darwin, but that is one dyld
 * behaviour on one platform to bet a retail Blu-ray on; it tries $LIBAACS_PATH
 * / $LIBBDPLUS_PATH before anything else, so point those at our own copies -
 * unless the user already selected an implementation, e.g. libmmbd.
 *
 * The variables hold the path *without* the extension: libbluray appends the
 * platform one itself (see dl_dlopen() in libbluray).
 *****************************************************************************/
static void SetupDiscLibPath(demux_t *p_demux, const char *psz_lib,
                             const char *psz_var)
{
#ifdef _WIN32
    static const char psz_ext[] = ".dll";
#elif defined(__APPLE__)
    static const char psz_ext[] = ".dylib";
#else
    static const char psz_ext[] = ".so.0";
#endif
    static const char *const ppsz_fmt[] = {
        "%s/lib/%s",  /* VLC.app/Contents/MacOS + /lib */
        "%s/%s",      /* Windows: beside powervlc.exe; UNIX: $libdir */
        "%s/../%s",   /* UNIX: $libdir is .../lib/vlc, library in lib/ */
    };
    static vlc_mutex_t lock = VLC_STATIC_MUTEX;

    vlc_mutex_lock(&lock);

    if (getenv(psz_var) != NULL)
        goto out;

    char *psz_libdir = config_GetLibDir();
    if (psz_libdir == NULL)
        goto out;

    for (size_t i = 0; i < ARRAY_SIZE(ppsz_fmt); i++) {
        char *psz_base;
        if (asprintf(&psz_base, ppsz_fmt[i], psz_libdir, psz_lib) < 0)
            break;

        char *psz_file;
        if (asprintf(&psz_file, "%s%s", psz_base, psz_ext) < 0) {
            free(psz_base);
            break;
        }

        struct stat st;
        bool b_found = vlc_stat(psz_file, &st) == 0 && !S_ISDIR(st.st_mode);
        if (b_found) {
            msg_Dbg(p_demux, "using bundled descrambling library %s", psz_file);
            setenv(psz_var, psz_base, 1);
        }

        free(psz_file);
        free(psz_base);

        if (b_found)
            break;
    }

    free(psz_libdir);
out:
    vlc_mutex_unlock(&lock);
}

/*****************************************************************************
 * blurayOpen: module init function
 *****************************************************************************/
static int blurayOpen(vlc_object_t *object)
{
    demux_t *p_demux = (demux_t*)object;
    demux_sys_t *p_sys;
    bool forced;
    uint64_t i_init_pos = 0;

    const char *error_msg = NULL;
#define BLURAY_ERROR(s) do { error_msg = s; goto error; } while(0)

    if (unlikely(!p_demux->p_input))
        return VLC_EGENERIC;

    forced = !strcasecmp(p_demux->psz_access, "bluray");

    if (p_demux->s) {
        if (!strcasecmp(p_demux->psz_access, "file")) {
            /* use access_demux for local files */
            return VLC_EGENERIC;
        }

        if (probeStream(p_demux) != VLC_SUCCESS) {
            return VLC_EGENERIC;
        }

    } else if (!forced) {
        if (!p_demux->psz_file) {
            return VLC_EGENERIC;
        }

        /* Do not touch ordinary audio files while probing access-demux
         * modules. On network libraries probeFile() adds several synchronous
         * reads per track before the metadata reader is reached. */
        static const char *const audio_extensions[] = {
            ".aac", ".ac3", ".aif", ".aiff", ".alac", ".ape", ".dts",
            ".flac", ".m4a", ".m4b", ".mp2", ".mp3", ".oga", ".ogg",
            ".opus", ".wav", ".wma", NULL
        };
        const char *extension = strrchr(p_demux->psz_file, '.');
        if (extension != NULL)
            for (size_t i = 0; audio_extensions[i] != NULL; ++i)
                if (!strcasecmp(extension, audio_extensions[i]))
                    return VLC_EGENERIC;

        if (probeFile(p_demux->psz_file) != VLC_SUCCESS) {
            return VLC_EGENERIC;
        }
    }

    /* */
    p_demux->p_sys = p_sys = vlc_obj_calloc(object, 1, sizeof(*p_sys));
    if (unlikely(!p_sys))
        return VLC_ENOMEM;

    p_sys->i_still_end_time = STILL_IMAGE_NOT_SET;
    p_sys->i_last_ig_user_input = VLC_TICK_INVALID;
    p_sys->i_last_ig_activation = VLC_TICK_INVALID;
    p_sys->i_mvc_sub_path = -1;
    p_sys->i_mvc_clip = -1;
    p_sys->i_current_playitem = -1;
    /* Profile-5 discs start in their authored 3D preference. An explicit
     * BD_EVENT_STEREOSCOPIC_STATUS overrides this before/while the selected
     * playlist is opened. Non-menu title playback keeps its former MVC
     * behavior. */
    p_sys->b_stereoscopic_output = true;
    p_sys->b_inherited_stereo_presentation =
        var_InheritInteger(p_demux, "stereo3d-fullscreen-display") > 0;
    /* init demux info fields */
    p_demux->info.i_update    = 0;
    p_demux->info.i_title     = 0;
    p_demux->info.i_seekpoint = 0;

    TAB_INIT(p_sys->i_title, p_sys->pp_title);
    TAB_INIT(p_sys->i_attachments, p_sys->attachments);
    ARRAY_INIT(p_sys->events_delayed);

    vlc_mutex_init(&p_sys->pl_info_lock);
    vlc_mutex_init(&p_sys->bdj_overlay_lock);
    vlc_mutex_init(&p_sys->read_block_lock); /* used during bd_open_stream() */

    /* request sub demuxers to skip continuity check as some split
       file concatenation are just resetting counters... */
    var_Create( p_demux, "ts-cc-check", VLC_VAR_BOOL );
    var_SetBool( p_demux, "ts-cc-check", false );
    var_Create( p_demux, "ts-standard", VLC_VAR_STRING );
    var_SetString( p_demux, "ts-standard", "mpeg" );
    var_Create( p_demux, "ts-pmtfix-waitdata", VLC_VAR_BOOL );
    var_SetBool( p_demux, "ts-pmtfix-waitdata", false );
    var_Create( p_demux, "ts-patfix", VLC_VAR_BOOL );
    var_SetBool( p_demux, "ts-patfix", false );
    var_Create( p_demux, "ts-pcr-offsetfix", VLC_VAR_BOOL );
    var_SetBool( p_demux, "ts-pcr-offsetfix", false );

    var_AddCallback( p_demux->p_input, "intf-event", onIntfEvent, p_demux );

    /* Tells the interfaces whether to offer their pop-up menu entry
     * (INPUT_NAV_POPUP). Created for every Blu-ray, menus or not, and given
     * its value once menus are known to run (see below): without menus there
     * is never a pop-up, and an existing variable reading false is what the
     * interfaces expect. */
    var_Create( p_demux->p_input, INPUT_POPUP_MENU_VAR, VLC_VAR_BOOL );

    /* Open BluRay */
    SetupDiscLibPath(p_demux, "libaacs", "LIBAACS_PATH");
    SetupDiscLibPath(p_demux, "libbdplus", "LIBBDPLUS_PATH");
#ifdef BLURAY_DEMUX
    if (p_demux->s) {
        i_init_pos = vlc_stream_Tell(p_demux->s);

        p_sys->bluray = bd_init();
        if (!bd_open_stream(p_sys->bluray, p_demux, blurayReadBlock)) {
            bd_close(p_sys->bluray);
            p_sys->bluray = NULL;
        }
    } else
#endif
    {
        if (!p_demux->psz_file) {
            /* no path provided (bluray://). use default DVD device. */
            p_sys->psz_bd_path = var_InheritString(object, "dvd");
        } else {
            /* store current bd path */
            p_sys->psz_bd_path = strdup(p_demux->psz_file);
        }

#ifdef __APPLE__
        /* Read the disc ourselves rather than through the OS filesystem, and
         * always with read-ahead. Three cases, in decreasing order of
         * preference:
         *
         *  - the raw device answers (10.5, 10.6): read /dev/rdiskN directly,
         *    which is what gets 10.6 past its 2 KB per command UDF driver;
         *  - it does not (10.4, where BD media is taken for a CD and the block
         *    device returns EOF): drive the disc over MMC instead;
         *  - neither: fall back to the mount point, i.e. upstream behaviour.
         *
         * Either way the blocks reach libbluray through the same read-ahead:
         * libudfread asks for one 6144 byte unit at a time, and that request
         * size is where USB 2 optical drives collapse (3.88 MB/s on the Mac
         * Mini G4, against 14.7 MB/s at 1 MB per request).
         */
        FindMountPoint(&p_sys->psz_bd_path);
        if (FindRawDevice(&p_sys->psz_bd_path)) {
            /* Readable device node: read it ourselves anyway. Letting
             * libbluray open it would have libudfread ask for one 6144 byte
             * unit at a time, which is the request size USB 2 optical drives
             * are worst at -- see bluray_disc_OpenRaw(). */
            p_sys->p_mmc = bluray_disc_OpenRaw(VLC_OBJECT(p_demux),
                                               p_sys->psz_bd_path);
        }
        if (p_sys->p_mmc == NULL) {
            /* IOKit knows the media as "disk1", never "rdisk1", so drop the
             * raw-device prefix if the caller handed us one. NULL means "any
             * optical drive that answers", which is what a bare bluray:// with
             * no path ends up as. */
            const char *psz_bsd = NULL;
            if (!strncmp(p_sys->psz_bd_path, "/dev/", 5)) {
                psz_bsd = p_sys->psz_bd_path + 5;
                if (!strncmp(psz_bsd, "rdisk", 5))
                    psz_bsd++;
            }

            p_sys->p_mmc = bluray_disc_OpenMMC(VLC_OBJECT(p_demux), psz_bsd);
        }

        if (p_sys->p_mmc != NULL) {
            /* Only the MMC backend has a channel to share; the raw one reads
             * through a plain fd and leaves libaacs to open the drive itself.
             * Must come before libbluray touches libaacs. */
            void *mmc_chan = bluray_disc_TaskInterface(p_sys->p_mmc);
            if (mmc_chan != NULL)
                ShareMMCWithLibaacs(p_demux, mmc_chan);

            p_sys->bluray = bd_init();
            if (p_sys->bluray != NULL
             && !bd_open_stream_dev(p_sys->bluray, p_sys->p_mmc,
                                    bluray_disc_ReadBlocks,
                                    p_sys->psz_bd_path, NULL)) {
                bd_close(p_sys->bluray);
                p_sys->bluray = NULL;
            }
        } else {
            msg_Dbg(p_demux, "opening Blu-ray at %s", p_sys->psz_bd_path);
            p_sys->bluray = bd_open(p_sys->psz_bd_path, NULL);
        }
#else
        /* If we're passed a block device, try to convert it to the mount point. */
        FindMountPoint(&p_sys->psz_bd_path);

        msg_Dbg(p_demux, "opening Blu-ray at %s", p_sys->psz_bd_path);
        p_sys->bluray = bd_open(p_sys->psz_bd_path, NULL);

#ifdef _WIN32
        /* Windows XP tops out at UDF 2.01 and a Blu-ray is UDF 2.5: the
         * volume never mounts, Explorer shows nothing, and the open above
         * dies on "failed opening UDF image H:\". The data is perfectly
         * readable all the same -- libbluray carries its own UDF reader --
         * but it has to be handed the RAW VOLUME, because libudfread opens
         * whatever path it is given with a plain _wopen() and never adds the
         * device prefix itself (contrib/libudfread, block_input_new()).
         *
         * So on a drive root that would not open, try again as \\.\X:.
         * Second, not first: Vista and later mount the disc perfectly well,
         * and the mounted path is the one the rest of the world (and the
         * user's own file manager) agrees on. This is the same reasoning as
         * the raw-device path above for macOS, whose 10.6 UDF driver reads
         * 2 KB at a time.
         *
         * Measured on Windows XP SP3 with RIO: unreadable before, and after
         * this "HDMV Titles: 5, BD-J Titles: 86", AACS decrypted, BD-J
         * running (14/08/2026). */
        if (p_sys->bluray == NULL
         && p_sys->psz_bd_path != NULL
         && ((p_sys->psz_bd_path[0] >= 'A' && p_sys->psz_bd_path[0] <= 'Z')
          || (p_sys->psz_bd_path[0] >= 'a' && p_sys->psz_bd_path[0] <= 'z'))
         && p_sys->psz_bd_path[1] == ':'
         && (p_sys->psz_bd_path[2] == '\0'
          || ((p_sys->psz_bd_path[2] == '\\' || p_sys->psz_bd_path[2] == '/')
              && p_sys->psz_bd_path[3] == '\0'))) {
            char *psz_raw;
            if (asprintf(&psz_raw, "\\\\.\\%c:", p_sys->psz_bd_path[0]) >= 0) {
                msg_Dbg(p_demux, "%s did not open, trying the raw volume %s",
                        p_sys->psz_bd_path, psz_raw);
                p_sys->bluray = bd_open(psz_raw, NULL);
                if (p_sys->bluray != NULL) {
                    /* keep it: libaacs and the disc-eject path below both
                     * use psz_bd_path, and only this spelling reaches the
                     * disc on this system */
                    free(p_sys->psz_bd_path);
                    p_sys->psz_bd_path = psz_raw;
                } else
                    free(psz_raw);
            }
        }
#endif
#endif
    }
    if (!p_sys->bluray) {
        goto error;
    }

    /* Warning the user about AACS/BD+ */
    const BLURAY_DISC_INFO *disc_info = bd_get_disc_info(p_sys->bluray);

    /* Is it a bluray? */
    if (!disc_info->bluray_detected) {
        if (forced) {
            BLURAY_ERROR(_("Path doesn't appear to be a Blu-ray"));
        }
        goto error;
    }

    msg_Info(p_demux, "First play: %i, Top menu: %i\n"
                      "HDMV Titles: %i, BD-J Titles: %i, Other: %i",
             disc_info->first_play_supported, disc_info->top_menu_supported,
             disc_info->num_hdmv_titles, disc_info->num_bdj_titles,
             disc_info->num_unsupported_titles);

    /* AACS */
    if (disc_info->aacs_detected) {
        msg_Dbg(p_demux, "Disc is using AACS");
        if (!disc_info->libaacs_detected)
            /* libaacs ships with the player (see contrib/src/aacs), so this
             * means the copy next to it is gone or unloadable. */
            BLURAY_ERROR(_("The AACS decoding library could not be loaded, so "
                      "this Blu-ray Disc cannot be read."));
        if (!disc_info->aacs_handled) {
            if (disc_info->aacs_error_code) {
                switch (disc_info->aacs_error_code) {
                case BD_AACS_CORRUPTED_DISC:
                    BLURAY_ERROR(_("Blu-ray Disc is corrupted."));
                case BD_AACS_NO_CONFIG:
                    BLURAY_ERROR(_("No AACS key database was found. Open a "
                      "keydb.cfg file with this player to install one."));
                case BD_AACS_NO_PK:
                    BLURAY_ERROR(_("No valid processing key found in AACS config file."));
                case BD_AACS_NO_CERT:
                    BLURAY_ERROR(_("No valid host certificate found in AACS config file."));
                case BD_AACS_CERT_REVOKED:
                    BLURAY_ERROR(_("AACS Host certificate revoked."));
                case BD_AACS_MMC_FAILED:
                    BLURAY_ERROR(_("AACS MMC failed."));
                }
            }
        }
    }

    /* BD+ */
    if (disc_info->bdplus_detected) {
        msg_Dbg(p_demux, "Disc is using BD+");
        if (!disc_info->libbdplus_detected)
            BLURAY_ERROR(_("This Blu-ray Disc needs a library for BD+ decoding"
                      ", and your system does not have it."));
        if (!disc_info->bdplus_handled)
            BLURAY_ERROR(_("Your system BD+ decoding library does not work. "
                      "Missing configuration?"));
    }

    /* set player region code */
    char *psz_region = var_InheritString(p_demux, "bluray-region");
    unsigned int region = psz_region ? (psz_region[0] - 'A') : REGION_DEFAULT;
    free(psz_region);
    bd_set_player_setting(p_sys->bluray, BLURAY_PLAYER_SETTING_REGION_CODE, 1<<region);

    /* set preferred languages */
    const char *psz_code = DemuxGetLanguageCode( p_demux, "audio-language" );
    bd_set_player_setting_str(p_sys->bluray, BLURAY_PLAYER_SETTING_AUDIO_LANG, psz_code);
    psz_code = DemuxGetLanguageCode( p_demux, "sub-language" );
    bd_set_player_setting_str(p_sys->bluray, BLURAY_PLAYER_SETTING_PG_LANG,    psz_code);
    psz_code = DemuxGetLanguageCode( p_demux, "menu-language" );
    bd_set_player_setting_str(p_sys->bluray, BLURAY_PLAYER_SETTING_MENU_LANG,  psz_code);

    /* Network access by on-disc Java code is opt-in. Apart from avoiding
     * unexpected third-party connections, this prevents dead BD-Live
     * services from holding old menus on their loading screen indefinitely. */
    bd_set_player_setting(p_sys->bluray, BLURAY_PLAYER_SETTING_NETWORK_ACCESS,
                          var_InheritBool(p_demux, "bluray-bd-live"));

    /* Get disc metadata */
    p_sys->p_meta = bd_get_meta(p_sys->bluray);
    if (!p_sys->p_meta)
        msg_Warn(p_demux, "Failed to get meta info.");

    p_sys->i_cover_idx = -1;
    attachThumbnail(p_demux);

    p_sys->b_menu = var_InheritBool(p_demux, "bluray-menu");

    /* Check BD-J capability */
    if (p_sys->b_menu && disc_info->bdj_detected && !disc_info->bdj_handled) {
        msg_Err(p_demux, "BD-J menus not supported. Playing without menus. "
                "BD-J support: %d, JVM found: %d, JVM usable: %d",
                disc_info->bdj_supported, disc_info->libjvm_detected, disc_info->bdj_handled);
        vlc_dialog_display_error(p_demux, _("Java required"),
             _("This Blu-ray disc requires Java for menus support.%s\nThe disc will be played without menus."),
             !disc_info->libjvm_detected ? _("Java was not found on your system.") : "");
        p_sys->b_menu = false;
    }

    /* Offer the pop-up menu entry for the whole disc as soon as menus run.
     * The obvious gate -- BD_EVENT_POPUP -- cannot be used: libbluray raises
     * it from the HDMV graphics controller only (GC_STATUS_POPUP, set when an
     * interactive composition uses IG_UI_MODEL_POPUP), and the BD-J path never
     * raises it at all. Gating on it would grey the entry out forever on every
     * BD-J disc. So the key is always offered while menus are on, and the disc
     * decides what to do with it -- some ignore it, which is the same as on a
     * set-top player. */
    var_SetBool(p_demux->p_input, INPUT_POPUP_MENU_VAR, p_sys->b_menu);

    /* Get titles and chapters */
    blurayInitTitles(p_demux, disc_info->num_hdmv_titles + disc_info->num_bdj_titles + 1/*Top Menu*/ + 1/*First Play*/);

    /*
     * Initialize the event queue, so we can receive events in blurayDemux(Menu).
     */
    bd_get_event(p_sys->bluray, NULL);

    /* Registering overlay event handler */
    bd_register_overlay_proc(p_sys->bluray, p_demux, blurayOverlayProc);

    if (p_sys->b_menu) {

        /* Register ARGB overlay handler for BD-J */
        if (disc_info->num_bdj_titles) {
            blurayAcquireBdjSession(p_demux);
            bd_register_argb_overlay_proc(p_sys->bluray, p_demux, blurayArgbOverlayProc, NULL);
        }

        /* libbluray will start playback from "First-Title" title */
        if (bd_play(p_sys->bluray) == 0)
            BLURAY_ERROR(_("Failed to start bluray playback. Please try without menu support."));

    } else {
        /* set start title number */
        if (bluraySetTitle(p_demux, p_sys->i_longest_title) != VLC_SUCCESS) {
            msg_Err(p_demux, "Could not set the title %d", p_sys->i_longest_title);
            goto error;
        }
    }

    p_sys->p_tf_out = timestamps_filter_es_out_New(p_demux->out,
                                                    VLC_OBJECT(p_demux));
    if(unlikely(!p_sys->p_tf_out))
        goto error;

    es_out_t *out_id = p_sys->p_tf_out;
    if (unlikely(disc_info->udf_volume_id &&
                 !strncmp(disc_info->udf_volume_id, "VLC Escape", strlen("VLC Escape"))))
    {
        p_sys->p_esc_out = escape_esOutNew(VLC_OBJECT(p_demux), p_sys->p_tf_out);
        out_id = p_sys->p_esc_out;
    }
    else
        p_sys->p_esc_out = NULL;

    p_sys->p_out = esOutNew(VLC_OBJECT(p_demux), out_id, p_demux);
    if (unlikely(p_sys->p_out == NULL))
        goto error;

    p_sys->p_mvc_out = mvc_esOutNew(p_sys->p_out);
    if (unlikely(p_sys->p_mvc_out == NULL))
        goto error;

#if defined(__arm64__) || defined(__aarch64__)
    /* Prefer a valid authored clock (needed for stable LPCM on Albator), but
     * let the TS demuxer derive one when a playlist starts its PES timeline
     * several seconds away from PCR (Dragons). */
    var_Create(p_demux, "ts-trust-pcr", VLC_VAR_BOOL);
    var_SetBool(p_demux, "ts-trust-pcr", true);
    var_Create(p_demux, "ts-pcr-autofallback", VLC_VAR_BOOL);
    var_SetBool(p_demux, "ts-pcr-autofallback", true);
#endif

    p_sys->p_parser = vlc_demux_chained_New(VLC_OBJECT(p_demux), "ts", p_sys->p_out);
    if (!p_sys->p_parser) {
        msg_Err(p_demux, "Failed to create TS demuxer");
        goto error;
    }

    p_demux->pf_control = blurayControl;
    p_demux->pf_demux   = blurayDemux;

    /* Playback starts in first play / a menu, so the look-ahead cache is
     * inhibited to begin with; blurayCacheInhibitUpdate() re-allows it once a
     * title is actually playing. */
    p_sys->b_cache_inhibited = true;
    es_out_Control(p_demux->out, ES_OUT_SET_VIDEO_CACHE_INHIBIT, true);

    /* A Blu-ray presentation is one continuous display session even though
     * libbluray replaces all video ESes between first-play clips, menus and
     * titles. Tell the input core not to destroy its recyclable vout in those
     * short no-ES gaps: on HDMI MVC that teardown also restores the 4K
     * desktop and makes the projector leave 3D before the next clip exists. */
    var_Create(p_demux->p_input, "bluray-disc-session", VLC_VAR_BOOL);
    var_SetBool(p_demux->p_input, "bluray-disc-session", true);

    return VLC_SUCCESS;

error:
    if (error_msg)
        vlc_dialog_display_error(p_demux, _("Blu-ray error"), "%s", error_msg);
    blurayClose(object);

    if (p_demux->s != NULL) {
        /* restore stream position */
        if (vlc_stream_Seek(p_demux->s, i_init_pos) != VLC_SUCCESS) {
            msg_Err(p_demux, "Failed to seek back to stream start");
            return VLC_ETIMEOUT;
        }
    }

    return VLC_EGENERIC;
#undef BLURAY_ERROR
}


/*****************************************************************************
 * blurayClose: module destroy function
 *****************************************************************************/
static void blurayClose(vlc_object_t *object)
{
    demux_t *p_demux = (demux_t*)object;
    demux_sys_t *p_sys = p_demux->p_sys;

    if (var_Type(p_demux->p_input, "bluray-disc-session") != 0)
        var_SetBool(p_demux->p_input, "bluray-disc-session", false);

    bluraySetBdjStillDecoder(p_demux, false);

    var_DelCallback( p_demux->p_input, "intf-event", onIntfEvent, p_demux );
    var_Destroy( p_demux->p_input, INPUT_POPUP_MENU_VAR );

    setTitleInfo(p_sys, NULL);

    /* The extension file belongs to libbluray's disc object, so it must be
     * closed before bd_close(). */
    blurayCloseMVCClip(p_demux);
    if (p_sys->p_mvc_out != NULL) {
        es_out_Delete(p_sys->p_mvc_out);
        p_sys->p_mvc_out = NULL;
    }

    /*
     * Close libbluray first.
     * This will close all the overlays before we release p_vout
     * bd_close(NULL) can crash
     */
    if (p_sys->bluray) {
        bd_close(p_sys->bluray);
    }
    blurayReleaseBdjSession(p_demux);

#ifdef __APPLE__
    /* After libbluray, which still had libaacs holding our interface. Exclusive
     * access is dropped only here: on 10.4 releasing it makes the OS re-probe
     * media it cannot identify, and it answers by ejecting the disc. */
    if (p_sys->p_mmc != NULL) {
        if (bluray_disc_TaskInterface(p_sys->p_mmc) != NULL)
            ShareMMCWithLibaacs(p_demux, NULL);
        bluray_disc_Close(p_sys->p_mmc);
        p_sys->p_mmc = NULL;
    }
#endif

    blurayReleaseVout(p_demux);

    if (p_sys->p_parser)
        vlc_demux_chained_Delete(p_sys->p_parser);

    if (p_sys->p_out != NULL)
        es_out_Delete(p_sys->p_out);
    if (p_sys->p_esc_out != NULL)
        es_out_Delete(p_sys->p_esc_out);
    if(p_sys->p_tf_out)
        timestamps_filter_es_out_Delete(p_sys->p_tf_out);

    /* Titles */
    for (unsigned int i = 0; i < p_sys->i_title; i++)
        vlc_input_title_Delete(p_sys->pp_title[i]);
    TAB_CLEAN(p_sys->i_title, p_sys->pp_title);

    for (int i = 0; i < p_sys->i_attachments; i++)
      vlc_input_attachment_Delete(p_sys->attachments[i]);
    TAB_CLEAN(p_sys->i_attachments, p_sys->attachments);

    ARRAY_RESET(p_sys->events_delayed);

    vlc_mutex_destroy(&p_sys->pl_info_lock);
    vlc_mutex_destroy(&p_sys->bdj_overlay_lock);
    vlc_mutex_destroy(&p_sys->read_block_lock);

    free(p_sys->psz_bd_path);
}

/*****************************************************************************
 * Elementary streams handling
 *****************************************************************************/
static uint8_t blurayGetStreamsUnlocked(demux_sys_t *p_sys,
                                        int i_stream_type,
                                        BLURAY_STREAM_INFO **pp_streams)
{
    if(!p_sys->p_clip_info)
        return 0;

    switch(i_stream_type)
    {
        case BD_EVENT_AUDIO_STREAM:
            *pp_streams = p_sys->p_clip_info->audio_streams;
            return p_sys->p_clip_info->audio_stream_count;
        case BD_EVENT_PG_TEXTST_STREAM:
            *pp_streams = p_sys->p_clip_info->pg_streams;
            return p_sys->p_clip_info->pg_stream_count;
        default:
            return 0;
    }
}

static BLURAY_STREAM_INFO * blurayGetStreamInfoUnlocked(demux_sys_t *p_sys,
                                                        int i_stream_type,
                                                        uint8_t i_stream_idx)
{
    BLURAY_STREAM_INFO *p_streams = NULL;
    uint8_t i_streams_count = blurayGetStreamsUnlocked(p_sys, i_stream_type, &p_streams);
    if(i_stream_idx < i_streams_count)
        return &p_streams[i_stream_idx];
    else
        return NULL;
}

static BLURAY_STREAM_INFO * blurayGetStreamInfoByPIDUnlocked(demux_sys_t *p_sys,
                                                             int i_pid)
{
    for(int i_type=BD_EVENT_AUDIO_STREAM; i_type<=BD_EVENT_SECONDARY_VIDEO_STREAM; i_type++)
    {
        BLURAY_STREAM_INFO *p_streams;
        uint8_t i_streams_count = blurayGetStreamsUnlocked(p_sys, i_type, &p_streams);
        for(uint8_t i=0; i<i_streams_count; i++)
        {
            if(p_streams[i].pid == i_pid)
                return &p_streams[i];
        }
    }
    return NULL;
}

static void setStreamLang(demux_sys_t *p_sys, es_format_t *p_fmt)
{
    vlc_mutex_lock(&p_sys->pl_info_lock);

    BLURAY_STREAM_INFO *p_stream = blurayGetStreamInfoByPIDUnlocked(p_sys, p_fmt->i_id);
    if(p_stream)
    {
        free(p_fmt->psz_language);
        p_fmt->psz_language = strndup((const char *)p_stream->lang, 3);
    }

    vlc_mutex_unlock(&p_sys->pl_info_lock);
}

static void setStreamVideoRate(demux_sys_t *p_sys, es_format_t *p_fmt)
{
    unsigned numerator = 0, denominator = 1;

    vlc_mutex_lock(&p_sys->pl_info_lock);
    const BLURAY_STREAM_INFO *p_stream = NULL;
    if (p_sys->p_clip_info != NULL)
    {
        const BLURAY_CLIP_INFO *p_clip = p_sys->p_clip_info;
        for (uint8_t i = 0; i < p_clip->video_stream_count; ++i)
            if (p_clip->video_streams[i].pid == p_fmt->i_id)
            {
                p_stream = &p_clip->video_streams[i];
                break;
            }
        for (uint8_t i = 0; p_stream == NULL &&
             i < p_clip->sec_video_stream_count; ++i)
            if (p_clip->sec_video_streams[i].pid == p_fmt->i_id)
            {
                p_stream = &p_clip->sec_video_streams[i];
                break;
            }
    }

    if (p_stream != NULL)
        switch (p_stream->rate)
        {
            case BLURAY_VIDEO_RATE_24000_1001:
                numerator = 24000; denominator = 1001; break;
            case BLURAY_VIDEO_RATE_24:
                numerator = 24; break;
            case BLURAY_VIDEO_RATE_25:
                numerator = 25; break;
            case BLURAY_VIDEO_RATE_30000_1001:
                numerator = 30000; denominator = 1001; break;
            case BLURAY_VIDEO_RATE_50:
                numerator = 50; break;
            case BLURAY_VIDEO_RATE_60000_1001:
                numerator = 60000; denominator = 1001; break;
            default:
                break;
        }
    vlc_mutex_unlock(&p_sys->pl_info_lock);

    /* The MPEG-TS parser commonly rounds 24000/1001 to 24/1 before the vout
     * is created.  That is harmless on a normal desktop, but it selects the
     * distinct exact-24.000 private HDMI timing on Mavericks and forces a
     * periodic cadence correction.  The clip declaration is authoritative
     * for Blu-ray and preserves the fractional clock all the way to the HDMI
     * mode selector. */
    if (numerator != 0)
    {
        p_fmt->video.i_frame_rate = numerator;
        p_fmt->video.i_frame_rate_base = denominator;
    }
}

static int blurayGetStreamPID(demux_sys_t *p_sys, int i_stream_type, uint8_t i_stream_idx)
{
    vlc_mutex_lock(&p_sys->pl_info_lock);

    BLURAY_STREAM_INFO *p_stream = blurayGetStreamInfoUnlocked(p_sys,
                                                               i_stream_type,
                                                               i_stream_idx);
    int i_pid = p_stream ? p_stream->pid : -1;

    vlc_mutex_unlock(&p_sys->pl_info_lock);

    return i_pid;
}

/*****************************************************************************
 * bluray fake es_out
 *****************************************************************************/
typedef struct
{
    es_out_t *p_dst_out;
    vlc_object_t *p_obj;
    vlc_array_t es; /* es_pair_t */
    bool b_entered_recycling;
    bool b_restart_decoders_on_reuse;
    void *priv;
    bool b_discontinuity;
    bool b_disable_output;
    bool b_lowdelay;
    bool b_forced_subs; /* show forced captions of a hidden PG stream */
    mvc_block_queue_t mvc_base;
    mvc_block_queue_t mvc_dependent;
    bool b_mvc_active;
    bool b_mvc_expected;
    bool b_mvc_base_right;
    bool b_mvc_sync_warning;
    bool b_mvc_discontinuity;
    vlc_tick_t i_mvc_dependent_pts_offset;
    vlc_tick_t i_mvc_base_date;
    vlc_tick_t i_mvc_dependent_date;
    vlc_mutex_t lock;
    struct
    {
        int i_audio_pid; /* Selected audio stream. -1 if default */
        int i_spu_pid;   /* Selected spu stream. -1 if default */
    } selected;
} bluray_esout_sys_t;

static void blurayResetMVCUnlocked(bluray_esout_sys_t *sys)
{
    mvcQueueRelease(&sys->mvc_base);
    mvcQueueRelease(&sys->mvc_dependent);
    sys->b_mvc_discontinuity = false;
    sys->i_mvc_base_date = VLC_TICK_INVALID;
    sys->i_mvc_dependent_date = VLC_TICK_INVALID;
}

static void bluraySetMVCFormat(es_format_t *fmt, bool base_right)
{
    fmt->i_cat = VIDEO_ES;
    fmt->i_codec = VLC_CODEC_H264_MVC;
    fmt->b_packetized = true;
    fmt->video.multiview_mode = base_right
                              ? MULTIVIEW_STEREO_FRAMEPACKED_RIGHT_BASE
                              : MULTIVIEW_STEREO_FRAMEPACKED;
}

enum
{
    BLURAY_ES_OUT_CONTROL_SET_ES_BY_PID = ES_OUT_PRIVATE_START,
    BLURAY_ES_OUT_CONTROL_UNSET_ES_BY_PID,
    BLURAY_ES_OUT_CONTROL_SET_SPU_VISIBILITY,
    BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY,
    BLURAY_ES_OUT_CONTROL_ENABLE_OUTPUT,
    BLURAY_ES_OUT_CONTROL_DISABLE_OUTPUT,
    BLURAY_ES_OUT_CONTROL_ENABLE_LOW_DELAY,
    BLURAY_ES_OUT_CONTROL_DISABLE_LOW_DELAY,
    BLURAY_ES_OUT_CONTROL_RANDOM_ACCESS,
    BLURAY_ES_OUT_CONTROL_RESTART_PRIMARY_VIDEO,
    BLURAY_ES_OUT_CONTROL_RESTART_2D_AV,
    BLURAY_ES_OUT_CONTROL_STOP_RETAINED_AV,
    BLURAY_ES_OUT_CONTROL_SET_MVC_EXPECTED,
    BLURAY_ES_OUT_CONTROL_GET_MVC_PROGRESS,
};

static es_out_id_t *bluray_esOutAdd(es_out_t *p_out, const es_format_t *p_fmt)
{
    bluray_esout_sys_t *esout_sys = (bluray_esout_sys_t *)p_out->p_sys;
    demux_t *p_demux = esout_sys->priv;
    demux_sys_t *p_sys = p_demux->p_sys;
    es_format_t fmt;
    bool b_select = false;
    bool b_new_es = false;

    es_format_Copy(&fmt, p_fmt);

    vlc_mutex_lock(&esout_sys->lock);

    switch (fmt.i_cat) {
    case VIDEO_ES:
        if(esout_sys->b_lowdelay)
        {
            fmt.video.i_frame_rate = 1; fmt.video.i_frame_rate_base = 1;
            fmt.b_packetized = true;
        }
        else
            setStreamVideoRate(p_sys, &fmt);
        b_select = (p_fmt->i_id == 0x1011);
        /* PID 0x1011 is the AVC-compatible base view and 0x1012 is the MVC
         * dependent view in an HDMV transport stream.  Once either side has
         * exposed the pair, make the selected base ES use the MVC decoder. */
        if (p_fmt->i_id == 0x1012 ||
            (p_fmt->i_id == 0x1011 && esout_sys->b_mvc_expected))
        {
            esout_sys->b_mvc_active = true;
            bluraySetMVCFormat(&fmt, esout_sys->b_mvc_base_right);
        }
        fmt.i_priority = ES_PRIORITY_NOT_SELECTABLE;
        break;
    case AUDIO_ES:
        b_select = (esout_sys->selected.i_audio_pid == p_fmt->i_id);
        fmt.i_priority = ES_PRIORITY_NOT_SELECTABLE;
        setStreamLang(p_sys, &fmt);
        break ;
    case SPU_ES:
        if (esout_sys->selected.i_spu_pid == p_fmt->i_id)
        {
            if (p_sys->b_spu_enable)
                b_select = true;
            else if (esout_sys->b_forced_subs)
            {
                /* BD semantics: a hidden PG stream still displays its
                 * forced captions. Keep it selected and mark the track
                 * forced so the decoder only renders those (see
                 * avcodec/subtitle.c). */
                b_select = true;
                fmt.subs.b_forced = true;
            }
        }
        fmt.i_priority = ES_PRIORITY_NOT_SELECTABLE;
        setStreamLang(p_sys, &fmt);
        break ;
    default:
        break ;
    }

    es_out_id_t *p_es = NULL;
    if (p_fmt->i_id >= 0) {
        /* Ensure we are not overriding anything */
        es_pair_t *p_pair = getEsPairByPID(&esout_sys->es, p_fmt->i_id);
        if (p_pair == NULL)
        {
            msg_Info(p_demux, "Adding ES %d select %d", p_fmt->i_id, b_select);
            p_es = es_out_Add(esout_sys->p_dst_out, &fmt);
            b_new_es = true;
            es_pair_Add(&esout_sys->es, &fmt, p_es);

            if (p_fmt->i_id == 0x1012)
            {
                es_pair_t *p_base = getEsPairByPID(&esout_sys->es, 0x1011);
                if (p_base != NULL && p_base->fmt.i_codec != VLC_CODEC_H264_MVC)
                {
                    es_format_t mvc_fmt;
                    es_format_Copy(&mvc_fmt, &p_base->fmt);
                    bluraySetMVCFormat(&mvc_fmt,
                                       esout_sys->b_mvc_base_right);
                    msg_Info(p_demux, "Blu-ray 3D MVC pair detected (PIDs 0x1011/0x1012)");
                    es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES_FMT,
                                   p_base->p_es, &mvc_fmt);
                    es_format_Clean(&p_base->fmt);
                    es_format_Copy(&p_base->fmt, &mvc_fmt);
                    es_format_Clean(&mvc_fmt);
                }
            }
        }
        else
        {
            msg_Info(p_demux, "Reusing ES %d", p_fmt->i_id);
            p_pair->b_recyling = false;
            p_es = p_pair->p_es;
            if(!es_format_IsSimilar(p_fmt, &p_pair->fmt) ||
               p_fmt->b_packetized != p_pair->fmt.b_packetized ||
               strcmp(fmt.psz_language ? fmt.psz_language : "",
                      p_pair->fmt.psz_language ? p_pair->fmt.psz_language : "") ||
               esout_sys->b_restart_decoders_on_reuse)
            {
                es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES_FMT, p_pair->p_es, &fmt);
                es_format_Clean(&p_pair->fmt);
                es_format_Copy(&p_pair->fmt, &fmt);
            }
        }
    }

    if (p_es)
    {
        if(b_select)
            es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES, p_es);
        else
            es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES_STATE, p_es, false);

        /* A same-process disc change can recycle PID 0x1011 before the BD-J
         * play item reaches its one-frame still. Merely changing the inherited
         * codec preference does not replace that already-running VideoToolbox
         * decoder, so explicitly recreate it while the override is active. */
        if (p_fmt->i_id == 0x1011 &&
            p_sys->b_bdj_still_codec_restart_pending) {
            if (!b_new_es)
                es_out_Control(esout_sys->p_dst_out, ES_OUT_RESTART_ES, p_es);
            p_sys->b_bdj_still_codec_restart_pending = false;
        }
    }
    es_format_Clean(&fmt);

    vlc_mutex_unlock(&esout_sys->lock);

    return p_es;
}

static void bluray_esOutDeleteNonReusedESUnlocked(es_out_t *p_out)
{
    bluray_esout_sys_t *esout_sys = (bluray_esout_sys_t *)p_out->p_sys;

    if(esout_sys->b_discontinuity)
        esout_sys->b_discontinuity = false;

    if(!esout_sys->b_entered_recycling)
        return;

    esout_sys->b_entered_recycling = false;
    esout_sys->b_restart_decoders_on_reuse = true;

    es_pair_t *p_pair;
    while((p_pair = getUnusedEsPair(&esout_sys->es)))
    {
        msg_Info(esout_sys->p_obj, "Trashing unused ES %d", p_pair->fmt.i_id);
        es_out_Del(esout_sys->p_dst_out, p_pair->p_es);
        es_pair_Remove(&esout_sys->es, p_pair);
    }

    if (!esout_sys->b_mvc_expected &&
        (getEsPairByPID(&esout_sys->es, 0x1011) == NULL ||
         getEsPairByPID(&esout_sys->es, 0x1012) == NULL))
    {
        esout_sys->b_mvc_active = false;
        blurayResetMVCUnlocked(esout_sys);
    }
}

static block_t *blurayGatherMVCUnlocked(bluray_esout_sys_t *sys)
{
    block_t *outputs = NULL;
    block_t **last = &outputs;

    while (sys->mvc_base.first != NULL && sys->mvc_dependent.first != NULL)
    {
        vlc_tick_t base_date = mvcBlockDate(sys->mvc_base.first);
        vlc_tick_t dependent_date = mvcBlockDate(sys->mvc_dependent.first);

        if (base_date != VLC_TICK_INVALID && dependent_date != VLC_TICK_INVALID &&
            (base_date - dependent_date > MVC_TIMESTAMP_TOLERANCE ||
             dependent_date - base_date > MVC_TIMESTAMP_TOLERANCE))
        {
            mvc_block_queue_t *older = base_date < dependent_date
                                     ? &sys->mvc_base : &sys->mvc_dependent;
            block_Release(mvcQueuePop(older));
            /* Skipping either view breaks MVC inter-picture dependencies.
             * Flush the decoder on the first pair where the two timelines
             * meet again, rather than letting the missing reference poison
             * every picture until the next playlist. */
            sys->b_mvc_discontinuity = true;
            if (!sys->b_mvc_sync_warning)
            {
                msg_Warn(sys->p_obj, "discarding an unmatched Blu-ray MVC "
                         "access unit: base date %"PRId64", dependent date "
                         "%"PRId64" (delta %"PRId64" us, dropped %s, "
                         "queued %u/%u)",
                         base_date, dependent_date,
                         base_date - dependent_date,
                         older == &sys->mvc_base ? "base" : "dependent",
                         sys->mvc_base.count, sys->mvc_dependent.count);
                sys->b_mvc_sync_warning = true;
            }
            continue;
        }

        block_t *base = mvcQueuePop(&sys->mvc_base);
        block_t *dependent = mvcQueuePop(&sys->mvc_dependent);
        base->i_flags |= dependent->i_flags;
        if (sys->b_mvc_discontinuity)
        {
            base->i_flags |= BLOCK_FLAG_DISCONTINUITY;
            sys->b_mvc_discontinuity = false;
        }
        base->p_next = dependent;
        block_t *stereo = block_ChainGather(base);
        if (stereo == NULL)
            continue;
        *last = stereo;
        last = &stereo->p_next;
    }

    /* A corrupt playlist must not grow queues indefinitely.  A normal MVC
     * stream stays below the H.264 reorder depth and never reaches this. */
    while (sys->mvc_base.count > MVC_QUEUE_LIMIT)
    {
        block_Release(mvcQueuePop(&sys->mvc_base));
        sys->b_mvc_discontinuity = true;
    }
    while (sys->mvc_dependent.count > MVC_QUEUE_LIMIT)
    {
        block_Release(mvcQueuePop(&sys->mvc_dependent));
        sys->b_mvc_discontinuity = true;
    }

    return outputs;
}

static int bluray_esOutSend(es_out_t *p_out, es_out_id_t *p_es, block_t *p_block)
{
    bluray_esout_sys_t *esout_sys = (bluray_esout_sys_t *)p_out->p_sys;
    block_t *mvc_output = NULL;
    es_out_id_t *mvc_es = NULL;
    vlc_mutex_lock(&esout_sys->lock);

    es_pair_t *p_pair = getEsPairByES(&esout_sys->es, p_es);
#if defined(__APPLE__) && defined(__aarch64__)
    /* The primary and dependent M2TS files are parsed on independent worker
     * threads.  On Apple Silicon the primary parser can consume its input
     * more than twenty seconds ahead of the dependent parser in a fraction
     * of a second (Raiponce 00056.mpls).  The generic queue limit then drops
     * MVC access units, which looks like an instantly skipped or frozen
     * trailer.
     *
     * Briefly yield the primary parser only when its decoded timestamp is
     * genuinely ahead and its pairing queue is already deep.  Releasing the
     * mutex lets the dependent parser publish the missing units.  The wait
     * is bounded so a menu jump or malformed dependent stream can never
     * deadlock parser teardown.  This is parser back-pressure, not the old
     * NVIDIA per-input-block throttle that starved interleaved audio. */
    if (p_pair != NULL && p_pair->fmt.i_id == 0x1011 &&
        esout_sys->b_mvc_active)
    {
        for (unsigned wait = 0; wait < 100; ++wait)
        {
            const bool dependent_behind =
                esout_sys->i_mvc_base_date != VLC_TICK_INVALID &&
                (esout_sys->i_mvc_dependent_date == VLC_TICK_INVALID ||
                 esout_sys->i_mvc_dependent_date + MVC_TARGET_TIME_LEAD <
                     esout_sys->i_mvc_base_date);
            /* During HDMI frame-packing setup the two latest timestamps can
             * be only a few frames apart while the primary parser has still
             * accumulated hundreds of same-timestamp/sliced blocks and the
             * dependent queue is empty. Queue imbalance is therefore the
             * authoritative pressure signal; the timestamp test additionally
             * covers a non-empty but genuinely lagging dependent queue. */
            const bool unpaired_primary =
                esout_sys->mvc_base.count >= 64 &&
                esout_sys->mvc_dependent.count == 0;
            if (!unpaired_primary &&
                (esout_sys->mvc_base.count < 64 || !dependent_behind))
                break;

            vlc_mutex_unlock(&esout_sys->lock);
            msleep(VLC_TICK_FROM_MS(10));
            vlc_mutex_lock(&esout_sys->lock);
            p_pair = getEsPairByES(&esout_sys->es, p_es);
            if (p_pair == NULL || p_pair->fmt.i_id != 0x1011 ||
                !esout_sys->b_mvc_active)
                break;
        }
    }
#endif
    /* The dependent MVC parser is deliberately primed before the primary
     * parser at a play-item boundary.  It must not finalize the shared ES
     * recycling pass: doing so deletes PID 0x1011 while it is merely waiting
     * for the new primary PMT, then recreates the decoder after the only
     * dependent still-picture AU has already passed.  The first primary (or
     * any ordinary non-dependent) packet remains responsible for cleanup. */
    if (p_pair == NULL || p_pair->fmt.i_id != 0x1012)
        bluray_esOutDeleteNonReusedESUnlocked(p_out);

    if(p_pair && p_pair->i_next_block_flags)
    {
        p_block->i_flags |= p_pair->i_next_block_flags;
        p_pair->i_next_block_flags = 0;
    }
    if(esout_sys->b_disable_output)
    {
        block_Release(p_block);
        p_block = NULL;
    }

    if (p_block != NULL && p_pair != NULL && esout_sys->b_mvc_active &&
        (p_pair->fmt.i_id == 0x1011 || p_pair->fmt.i_id == 0x1012))
    {
        if (p_pair->fmt.i_id == 0x1012 &&
            esout_sys->i_mvc_dependent_pts_offset != 0) {
            if (p_block->i_pts != VLC_TICK_INVALID)
                p_block->i_pts -= esout_sys->i_mvc_dependent_pts_offset;
            if (p_block->i_dts != VLC_TICK_INVALID)
                p_block->i_dts -= esout_sys->i_mvc_dependent_pts_offset;
        }
        vlc_tick_t date = mvcBlockDate(p_block);
        if (date != VLC_TICK_INVALID)
        {
            if (p_pair->fmt.i_id == 0x1011)
                esout_sys->i_mvc_base_date = date;
            else
                esout_sys->i_mvc_dependent_date = date;
        }
        mvcQueuePush(p_pair->fmt.i_id == 0x1011 ? &esout_sys->mvc_base
                                                : &esout_sys->mvc_dependent,
                     p_block);
        p_block = NULL;
        mvc_output = blurayGatherMVCUnlocked(esout_sys);
        es_pair_t *base = getEsPairByPID(&esout_sys->es, 0x1011);
        mvc_es = base != NULL ? base->p_es : NULL;
    }
    vlc_mutex_unlock(&esout_sys->lock);

    int result = VLC_SUCCESS;
    while (mvc_output != NULL)
    {
        block_t *next = mvc_output->p_next;
        mvc_output->p_next = NULL;
        if (mvc_es != NULL)
            result = es_out_Send(esout_sys->p_dst_out, mvc_es, mvc_output);
        else
            block_Release(mvc_output);
        mvc_output = next;
    }
    return (p_block) ? es_out_Send(esout_sys->p_dst_out, p_es, p_block) : result;
}

static void bluray_esOutDel(es_out_t *p_out, es_out_id_t *p_es)
{
    bluray_esout_sys_t *esout_sys = (bluray_esout_sys_t *)p_out->p_sys;

    vlc_mutex_lock(&esout_sys->lock);

    if(esout_sys->b_discontinuity)
        esout_sys->b_discontinuity = false;

    es_pair_t *p_pair = getEsPairByES(&esout_sys->es, p_es);
    if (p_pair)
    {
        p_pair->b_recyling = true;
        esout_sys->b_entered_recycling = true;
    }

    vlc_mutex_unlock(&esout_sys->lock);
}

static int bluray_esOutControl(es_out_t *p_out, int i_query, va_list args)
{
    bluray_esout_sys_t *esout_sys = (bluray_esout_sys_t *)p_out->p_sys;
    int i_ret;
    vlc_mutex_lock(&esout_sys->lock);

    if(esout_sys->b_disable_output &&
       i_query < ES_OUT_PRIVATE_START)
    {
        vlc_mutex_unlock(&esout_sys->lock);
        return VLC_EGENERIC;
    }

    if(esout_sys->b_discontinuity)
        esout_sys->b_discontinuity = false;

    switch(i_query)
    {
        case BLURAY_ES_OUT_CONTROL_SET_ES_BY_PID:
        case BLURAY_ES_OUT_CONTROL_UNSET_ES_BY_PID:
        {
            bool b_select = (i_query == BLURAY_ES_OUT_CONTROL_SET_ES_BY_PID);
            const int i_bluray_stream_type = va_arg(args, int);
            const int i_pid = va_arg(args, int);
            switch(i_bluray_stream_type)
            {
                case BD_EVENT_AUDIO_STREAM:
                    esout_sys->selected.i_audio_pid = i_pid;
                    break;
                case BD_EVENT_PG_TEXTST_STREAM:
                    esout_sys->selected.i_spu_pid = i_pid;
                    break;
                default:
                    break;
            }

            es_pair_t *p_pair = getEsPairByPID(&esout_sys->es, i_pid);
            if(unlikely(!p_pair))
            {
                vlc_mutex_unlock(&esout_sys->lock);
                return VLC_EGENERIC;
            }

            if(b_select)
                i_ret = es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES, p_pair->p_es);
            else
                i_ret = es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES_STATE,
                                      p_pair->p_es, false);
            break;
        };

        case BLURAY_ES_OUT_CONTROL_SET_SPU_VISIBILITY:
        {
            const bool b_visible = va_arg(args, int);
            es_pair_t *p_pair = getEsPairByPID(&esout_sys->es,
                                               esout_sys->selected.i_spu_pid);
            if (unlikely(!p_pair))
            {
                i_ret = VLC_EGENERIC;
                break;
            }

            if (!b_visible && !esout_sys->b_forced_subs)
            {
                /* forced captions disabled: plain hide */
                i_ret = es_out_Control(esout_sys->p_dst_out,
                                       ES_OUT_SET_ES_STATE, p_pair->p_es, false);
                break;
            }

            /* Visible: full display. Hidden: keep the track selected but
             * marked forced, the decoder then only renders the forced
             * captions (BD semantics). */
            const bool b_forced_only = !b_visible;
            if (p_pair->fmt.subs.b_forced != b_forced_only)
            {
                p_pair->fmt.subs.b_forced = b_forced_only;
                es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES_FMT,
                               p_pair->p_es, &p_pair->fmt);
            }
            i_ret = es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES,
                                   p_pair->p_es);
        } break;

        case BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY:
        {
            esout_sys->b_discontinuity = true;
            blurayResetMVCUnlocked(esout_sys);
            i_ret = VLC_SUCCESS;
        } break;

        case BLURAY_ES_OUT_CONTROL_RANDOM_ACCESS:
        {
            esout_sys->b_restart_decoders_on_reuse = !va_arg(args, int);
            i_ret = VLC_SUCCESS;
        } break;

        case BLURAY_ES_OUT_CONTROL_RESTART_PRIMARY_VIDEO:
        {
            es_pair_t *video = getEsPairByPID(&esout_sys->es, 0x1011);
            i_ret = video != NULL
                  ? es_out_Control(esout_sys->p_dst_out, ES_OUT_RESTART_ES,
                                   video->p_es)
                  : VLC_EGENERIC;
        } break;

        case BLURAY_ES_OUT_CONTROL_RESTART_2D_AV:
        {
            unsigned restarted = 0;

            /* A chained TS parser is replaced at every non-MVC play item,
             * but the Blu-ray ES proxy deliberately keeps tracks with the
             * same PID alive.  ES_OUT_SET_ES_FMT only recreates their
             * decoder when the next PMT happens to change the format.  VC-1
             * clips normally reuse the exact same format, leaving both its
             * packetizer and reference pictures from the preceding M2TS in
             * place.  Hopper consequently corrupts the first GOP of every
             * joined clip even though each M2TS decodes cleanly alone.
             *
             * Restart every selected audio/video decoder after the old TS
             * parser has been joined.  The next PMT may recreate audio once
             * more when the codec changes (AC-3/DTS), which is intentional;
             * it then starts with the new clip's format and timestamps. */
            for (size_t i = 0; i < vlc_array_count(&esout_sys->es); ++i)
            {
                es_pair_t *pair = vlc_array_item_at_index(&esout_sys->es, i);
                if (pair->fmt.i_cat != VIDEO_ES && pair->fmt.i_cat != AUDIO_ES)
                    continue;

                es_out_Control(esout_sys->p_dst_out, ES_OUT_RESTART_ES,
                               pair->p_es);
                pair->i_next_block_flags |= BLOCK_FLAG_DISCONTINUITY;
                restarted++;
            }
            msg_Dbg(esout_sys->p_obj, "restarted %u retained 2D Blu-ray A/V ES",
                    restarted);
            i_ret = VLC_SUCCESS;
        } break;

        case BLURAY_ES_OUT_CONTROL_STOP_RETAINED_AV:
        {
            unsigned stopped = 0;

            /* At the first play item of a replacement playlist there can be
             * a live decoder behind a recycled PID, although the new PMT has
             * not arrived yet.  Updating that selected ES from H.264 to
             * MPEG-2 is asynchronous in the input core; a one-frame menu can
             * overtake the update and be submitted to the old decoder.  Tear
             * selected A/V down first. bluray_esOutAdd() applies the new
             * format and selects it again before forwarding any new block. */
            for (size_t i = 0; i < vlc_array_count(&esout_sys->es); ++i)
            {
                es_pair_t *pair = vlc_array_item_at_index(&esout_sys->es, i);
                if (pair->fmt.i_cat != VIDEO_ES && pair->fmt.i_cat != AUDIO_ES)
                    continue;

                es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES_STATE,
                               pair->p_es, false);
                pair->i_next_block_flags |= BLOCK_FLAG_DISCONTINUITY;
                stopped++;
            }
            msg_Dbg(esout_sys->p_obj, "stopped %u retained Blu-ray A/V ES "
                    "before replacement playlist", stopped);
            i_ret = VLC_SUCCESS;
        } break;

        case BLURAY_ES_OUT_CONTROL_ENABLE_OUTPUT:
        case BLURAY_ES_OUT_CONTROL_DISABLE_OUTPUT:
        {
            esout_sys->b_disable_output = (i_query == BLURAY_ES_OUT_CONTROL_DISABLE_OUTPUT);
            i_ret = VLC_SUCCESS;
        } break;

        case BLURAY_ES_OUT_CONTROL_ENABLE_LOW_DELAY:
        case BLURAY_ES_OUT_CONTROL_DISABLE_LOW_DELAY:
        {
            esout_sys->b_lowdelay = (i_query == BLURAY_ES_OUT_CONTROL_ENABLE_LOW_DELAY);
            i_ret = VLC_SUCCESS;
        } break;

        case BLURAY_ES_OUT_CONTROL_SET_MVC_EXPECTED:
        {
            const bool expected = va_arg(args, int);
            const bool base_right = va_arg(args, int);
            const vlc_tick_t dependent_pts_offset = va_arg(args, vlc_tick_t);
            esout_sys->b_mvc_expected = expected;
            esout_sys->b_mvc_base_right = base_right;
            esout_sys->b_mvc_active = expected;
            esout_sys->b_mvc_sync_warning = false;
            blurayResetMVCUnlocked(esout_sys);
            esout_sys->i_mvc_dependent_pts_offset = dependent_pts_offset;

            /* Usually this is set before the main TS has advertised PID
             * 0x1011. Also handle menu-driven playlist changes where the
             * base decoder already exists. */
            es_pair_t *base = getEsPairByPID(&esout_sys->es, 0x1011);
            if (expected && base != NULL &&
                base->fmt.i_codec != VLC_CODEC_H264_MVC)
            {
                es_format_t mvc_fmt;
                es_format_Copy(&mvc_fmt, &base->fmt);
                bluraySetMVCFormat(&mvc_fmt, base_right);
                i_ret = es_out_Control(esout_sys->p_dst_out,
                                       ES_OUT_SET_ES_FMT, base->p_es,
                                       &mvc_fmt);
                es_format_Clean(&base->fmt);
                es_format_Copy(&base->fmt, &mvc_fmt);
                es_format_Clean(&mvc_fmt);
            }
            else if (!expected && base != NULL &&
                     base->fmt.i_codec == VLC_CODEC_H264_MVC)
            {
                /* A BD-J menu can jump directly from an MVC background to
                 * a 2D AVC trailer while PID 0x1012 is still present in the
                 * ES recycling table.  Leaving the selected base stream as
                 * mvc1 makes Edge264 wait forever for the now-absent second
                 * view: the input clock and seek bar advance over a frozen
                 * last menu frame.  Restore the AVC-compatible base view as
                 * soon as the MVC sub-path closes, before the new PMT reuses
                 * PID 0x1011. */
                es_format_t avc_fmt;
                es_format_Copy(&avc_fmt, &base->fmt);
                avc_fmt.i_codec = VLC_CODEC_H264;
                avc_fmt.video.multiview_mode = MULTIVIEW_2D;
                i_ret = es_out_Control(esout_sys->p_dst_out,
                                       ES_OUT_SET_ES_FMT, base->p_es,
                                       &avc_fmt);
                es_format_Clean(&base->fmt);
                es_format_Copy(&base->fmt, &avc_fmt);
                es_format_Clean(&avc_fmt);
            }
            else
                i_ret = VLC_SUCCESS;
        } break;

        case BLURAY_ES_OUT_CONTROL_GET_MVC_PROGRESS:
        {
            *va_arg(args, vlc_tick_t *) = esout_sys->i_mvc_base_date;
            *va_arg(args, vlc_tick_t *) = esout_sys->i_mvc_dependent_date;
            *va_arg(args, unsigned *) = esout_sys->mvc_base.count;
            *va_arg(args, unsigned *) = esout_sys->mvc_dependent.count;
            i_ret = VLC_SUCCESS;
        } break;

        case ES_OUT_SET_ES_DEFAULT:
        case ES_OUT_SET_ES:
        case ES_OUT_SET_ES_STATE:
            i_ret = VLC_EGENERIC;
            break;

        case ES_OUT_SET_ES_FMT:
        {
            /* A sub-demuxer (ts.c PGS forced-caption detection) updates the
             * format: re-apply our own adjustments (language, priority,
             * forced-only display of a hidden PG stream) before forwarding,
             * or they would be lost on the core side. */
            es_out_id_t *p_esid = va_arg(args, es_out_id_t *);
            es_format_t *p_updfmt = va_arg(args, es_format_t *);
            es_pair_t *p_pair = getEsPairByES(&esout_sys->es, p_esid);
            if (p_pair == NULL)
            {
                i_ret = es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES_FMT,
                                       p_esid, p_updfmt);
                break;
            }

            demux_t *p_demux = esout_sys->priv;
            demux_sys_t *p_sys = p_demux->p_sys;
            es_format_t fmt;
            es_format_Copy(&fmt, p_updfmt);
            if (fmt.i_cat == AUDIO_ES || fmt.i_cat == SPU_ES)
            {
                fmt.i_priority = ES_PRIORITY_NOT_SELECTABLE;
                setStreamLang(p_sys, &fmt);
            }
            if (fmt.i_cat == SPU_ES &&
                esout_sys->selected.i_spu_pid == fmt.i_id &&
                !p_sys->b_spu_enable && esout_sys->b_forced_subs)
                fmt.subs.b_forced = true;

            i_ret = es_out_Control(esout_sys->p_dst_out, ES_OUT_SET_ES_FMT,
                                   p_esid, &fmt);
            es_format_Clean(&p_pair->fmt);
            es_format_Copy(&p_pair->fmt, &fmt);
            es_format_Clean(&fmt);
        } break;

        case ES_OUT_GET_ES_STATE:
            va_arg(args, es_out_id_t *);
            *va_arg(args, bool *) = true;
            i_ret = VLC_SUCCESS;
            break;

        default:
            i_ret = es_out_vaControl(esout_sys->p_dst_out, i_query, args);
            break;
    }
    vlc_mutex_unlock(&esout_sys->lock);
    return i_ret;
}

static void bluray_esOutDestroy(es_out_t *p_out)
{
    bluray_esout_sys_t *esout_sys = (bluray_esout_sys_t *)p_out->p_sys;

    blurayResetMVCUnlocked(esout_sys);
    for (size_t i = 0; i < vlc_array_count(&esout_sys->es); ++i)
    {
        es_pair_t *pair = vlc_array_item_at_index(&esout_sys->es, i);
        es_format_Clean(&pair->fmt);
        free(pair);
    }
    vlc_array_clear(&esout_sys->es);
    vlc_mutex_destroy(&esout_sys->lock);
    free(p_out->p_sys);
    free(p_out);
}

static es_out_t *esOutNew(vlc_object_t *p_obj, es_out_t *p_dst_out, void *priv)
{
    es_out_t    *p_out = malloc(sizeof(*p_out));
    if (unlikely(p_out == NULL))
        return NULL;

    p_out->pf_add       = bluray_esOutAdd;
    p_out->pf_control   = bluray_esOutControl;
    p_out->pf_del       = bluray_esOutDel;
    p_out->pf_destroy   = bluray_esOutDestroy;
    p_out->pf_send      = bluray_esOutSend;

    bluray_esout_sys_t *esout_sys = malloc(sizeof(*esout_sys));
    if (unlikely(esout_sys == NULL))
    {
        free(p_out);
        return NULL;
    }
    p_out->p_sys = (es_out_sys_t *) esout_sys;
    vlc_array_init(&esout_sys->es);
    esout_sys->p_dst_out = p_dst_out;
    esout_sys->p_obj = p_obj;
    esout_sys->priv = priv;
    esout_sys->b_discontinuity = false;
    esout_sys->b_disable_output = false;
    esout_sys->b_entered_recycling = false;
    esout_sys->b_restart_decoders_on_reuse = true;
    esout_sys->b_lowdelay = false;
    esout_sys->b_forced_subs = var_InheritBool(p_obj, "bluray-forced-subs");
    mvcQueueInit(&esout_sys->mvc_base);
    mvcQueueInit(&esout_sys->mvc_dependent);
    esout_sys->b_mvc_active = false;
    esout_sys->b_mvc_expected = false;
    esout_sys->b_mvc_base_right = false;
    esout_sys->b_mvc_sync_warning = false;
    esout_sys->b_mvc_discontinuity = false;
    esout_sys->i_mvc_dependent_pts_offset = 0;
    esout_sys->i_mvc_base_date = VLC_TICK_INVALID;
    esout_sys->i_mvc_dependent_date = VLC_TICK_INVALID;
    esout_sys->selected.i_audio_pid = -1;
    esout_sys->selected.i_spu_pid = -1;
    vlc_mutex_init(&esout_sys->lock);
    return p_out;
}

/* The MVC extension clip is a complete transport stream with its own PAT,
 * PMT and PCR, but only its dependent video elementary stream belongs in the
 * primary playback graph. Forwarding the second PCR would make two demuxers
 * fight over the same input clock; forwarding its other streams would also
 * duplicate audio and subtitles. This small es_out keeps only PID 0x1012 and
 * deliberately consumes all program/timing controls locally. */
typedef struct
{
    es_out_id_t *dst;
} mvc_es_id_t;

typedef struct
{
    es_out_t *dst;
} mvc_esout_sys_t;

static es_out_id_t *mvc_esOutAdd(es_out_t *out, const es_format_t *fmt)
{
    mvc_esout_sys_t *sys = (mvc_esout_sys_t *)out->p_sys;
    mvc_es_id_t *id = malloc(sizeof(*id));
    if (unlikely(id == NULL))
        return NULL;

    id->dst = NULL;
    if (fmt->i_cat == VIDEO_ES && fmt->i_id == 0x1012)
        id->dst = es_out_Add(sys->dst, fmt);

    /* The TS demuxer needs a stable non-NULL token even for discarded ES. */
    return (es_out_id_t *)id;
}

static int mvc_esOutSend(es_out_t *out, es_out_id_t *es, block_t *block)
{
    mvc_esout_sys_t *sys = (mvc_esout_sys_t *)out->p_sys;
    mvc_es_id_t *id = (mvc_es_id_t *)es;
    if (id->dst != NULL)
        return es_out_Send(sys->dst, id->dst, block);
    block_Release(block);
    return VLC_SUCCESS;
}

static void mvc_esOutDel(es_out_t *out, es_out_id_t *es)
{
    mvc_esout_sys_t *sys = (mvc_esout_sys_t *)out->p_sys;
    mvc_es_id_t *id = (mvc_es_id_t *)es;
    if (id->dst != NULL)
        es_out_Del(sys->dst, id->dst);
    free(id);
}

static int mvc_esOutControl(es_out_t *out, int query, va_list args)
{
    mvc_esout_sys_t *sys = (mvc_esout_sys_t *)out->p_sys;

    switch (query)
    {
        case ES_OUT_GET_ES_STATE:
        {
            mvc_es_id_t *id = (mvc_es_id_t *)va_arg(args, es_out_id_t *);
            bool *selected = va_arg(args, bool *);
            *selected = id->dst != NULL;
            return VLC_SUCCESS;
        }
        case ES_OUT_SET_ES_FMT:
        {
            mvc_es_id_t *id = (mvc_es_id_t *)va_arg(args, es_out_id_t *);
            es_format_t *fmt = va_arg(args, es_format_t *);
            return id->dst != NULL
                 ? es_out_Control(sys->dst, ES_OUT_SET_ES_FMT, id->dst, fmt)
                 : VLC_SUCCESS;
        }
        case ES_OUT_SET_ES_STATE:
        {
            mvc_es_id_t *id = (mvc_es_id_t *)va_arg(args, es_out_id_t *);
            bool selected = va_arg(args, int);
            return id->dst != NULL
                 ? es_out_Control(sys->dst, ES_OUT_SET_ES_STATE,
                                  id->dst, selected)
                 : VLC_SUCCESS;
        }
        case ES_OUT_SET_ES_SCRAMBLED_STATE:
        {
            mvc_es_id_t *id = (mvc_es_id_t *)va_arg(args, es_out_id_t *);
            bool scrambled = va_arg(args, int);
            return id->dst != NULL
                 ? es_out_Control(sys->dst, ES_OUT_SET_ES_SCRAMBLED_STATE,
                                  id->dst, scrambled)
                 : VLC_SUCCESS;
        }
        default:
            return VLC_SUCCESS;
    }
}

static void mvc_esOutDestroy(es_out_t *out)
{
    free(out->p_sys);
    free(out);
}

static es_out_t *mvc_esOutNew(es_out_t *dst)
{
    es_out_t *out = malloc(sizeof(*out));
    mvc_esout_sys_t *sys = malloc(sizeof(*sys));
    if (unlikely(out == NULL || sys == NULL))
    {
        free(out);
        free(sys);
        return NULL;
    }
    sys->dst = dst;
    out->p_sys = (es_out_sys_t *)sys;
    out->pf_add = mvc_esOutAdd;
    out->pf_send = mvc_esOutSend;
    out->pf_del = mvc_esOutDel;
    out->pf_control = mvc_esOutControl;
    out->pf_destroy = mvc_esOutDestroy;
    return out;
}

/*****************************************************************************
 * subpicture_updater_t functions:
 *****************************************************************************/

static bluray_overlay_t *updater_lock_overlay(subpicture_updater_sys_t *p_upd_sys)
{
    /* this lock is held while vout accesses overlay. => overlay can't be closed. */
    vlc_mutex_lock(&p_upd_sys->lock);

    bluray_overlay_t *ov = p_upd_sys->p_overlay;
    if (ov) {
        /* this lock is held while vout accesses overlay. => overlay can't be modified. */
        vlc_mutex_lock(&ov->lock);
        return ov;
    }

    /* overlay has been closed */
    vlc_mutex_unlock(&p_upd_sys->lock);
    return NULL;
}

static void updater_unlock_overlay(subpicture_updater_sys_t *p_upd_sys)
{
    assert (p_upd_sys->p_overlay);

    vlc_mutex_unlock(&p_upd_sys->p_overlay->lock);
    vlc_mutex_unlock(&p_upd_sys->lock);
}

static int subpictureUpdaterValidate(subpicture_t *p_subpic,
                                      bool b_fmt_src, const video_format_t *p_fmt_src,
                                      bool b_fmt_dst, const video_format_t *p_fmt_dst,
                                      vlc_tick_t i_ts)
{
    VLC_UNUSED(b_fmt_src);
    VLC_UNUSED(b_fmt_dst);
    VLC_UNUSED(p_fmt_src);
    VLC_UNUSED(p_fmt_dst);
    VLC_UNUSED(i_ts);

    subpicture_updater_sys_t *p_upd_sys = p_subpic->updater.p_sys;
    bluray_overlay_t         *p_overlay = updater_lock_overlay(p_upd_sys);

    if (!p_overlay) {
        return 1;
    }

    int res = p_overlay->status == Outdated &&
              (p_overlay->i_update_date <= VLC_TICK_INVALID ||
               i_ts >= p_overlay->i_update_date);

    updater_unlock_overlay(p_upd_sys);

    return res;
}

static void subpictureUpdaterUpdate(subpicture_t *p_subpic,
                                    const video_format_t *p_fmt_src,
                                    const video_format_t *p_fmt_dst,
                                    vlc_tick_t i_ts)
{
    VLC_UNUSED(p_fmt_src);
    VLC_UNUSED(p_fmt_dst);
    VLC_UNUSED(i_ts);
    subpicture_updater_sys_t *p_upd_sys = p_subpic->updater.p_sys;
    bluray_overlay_t         *p_overlay = updater_lock_overlay(p_upd_sys);

    if (!p_overlay) {
        return;
    }

    /*
     * When this function is called, all p_subpic regions are gone.
     * We need to duplicate our regions (stored internally) to this subpic.
     */
    subpicture_region_t *p_src = p_overlay->p_regions;
    if (!p_src) {
        updater_unlock_overlay(p_upd_sys);
        return;
    }

    subpicture_region_t **p_dst = &p_subpic->p_region;
    while (p_src != NULL) {
        *p_dst = subpicture_region_Copy(p_src);
        if (*p_dst == NULL)
            break;
        (*p_dst)->i_stereo_offset = p_overlay->stereo_offset;
        p_dst = &(*p_dst)->p_next;
        p_src = p_src->p_next;
    }
    if (*p_dst != NULL)
        (*p_dst)->p_next = NULL;
    p_overlay->status = Displayed;
    p_overlay->i_update_date = VLC_TICK_INVALID;

    updater_unlock_overlay(p_upd_sys);
}

static void subpictureUpdaterDestroy(subpicture_t *p_subpic)
{
    subpicture_updater_sys_t *p_upd_sys = p_subpic->updater.p_sys;
    bluray_overlay_t         *p_overlay = updater_lock_overlay(p_upd_sys);

    if (p_overlay) {
        /* vout is closed (seek, new clip, ?). Overlay must be redrawn. */
        p_overlay->status = ToDisplay;
        p_overlay->i_channel = -1;
        updater_unlock_overlay(p_upd_sys);
    }

    unref_subpicture_updater(p_upd_sys);
}

static subpicture_t *bluraySubpictureCreate(bluray_overlay_t *p_ov)
{
    subpicture_updater_sys_t *p_upd_sys = malloc(sizeof(*p_upd_sys));
    if (unlikely(p_upd_sys == NULL)) {
        return NULL;
    }

    p_upd_sys->p_overlay = p_ov;

    subpicture_updater_t updater = {
        .pf_validate = subpictureUpdaterValidate,
        .pf_update   = subpictureUpdaterUpdate,
        .pf_destroy  = subpictureUpdaterDestroy,
        .p_sys       = p_upd_sys,
    };

    subpicture_t *p_pic = subpicture_New(&updater);
    if (p_pic == NULL) {
        free(p_upd_sys);
        return NULL;
    }

    p_pic->i_original_picture_width = p_ov->width;
    p_pic->i_original_picture_height = p_ov->height;
    p_pic->b_ephemer = true;
    p_pic->b_absolute = true;

    vlc_mutex_init(&p_upd_sys->lock);
    p_upd_sys->ref_cnt = 2;

    p_ov->p_updater = p_upd_sys;

    return p_pic;
}

/*****************************************************************************
 * User input events:
 *****************************************************************************/
static int onMouseEvent(vlc_object_t *p_vout, const char *psz_var, vlc_value_t old,
                        vlc_value_t val, void *p_data)
{
    demux_t     *p_demux = (demux_t*)p_data;
    demux_sys_t *p_sys   = p_demux->p_sys;
    int x = val.coords.x;
    int y = val.coords.y;
    VLC_UNUSED(old);
    VLC_UNUSED(p_vout);
    p_sys->i_last_ig_user_input = mdate();

    /* PowerVLC exposes an MVC title to the vout as two vertically stacked
     * 1920x1080 views.  Blu-ray interactive graphics, however, always use a
     * single-view coordinate space.  Let either displayed eye drive the same
     * BD-J button instead of sending the lower eye's out-of-range Y value. */
    if (p_sys->i_mvc_sub_path >= 0)
    {
        int plane_height = 0;

        vlc_mutex_lock(&p_sys->bdj_overlay_lock);
        for (int plane = 0; plane < MAX_OVERLAY; ++plane)
            if (p_sys->p_overlays[plane] != NULL &&
                p_sys->p_overlays[plane]->height > plane_height)
                plane_height = p_sys->p_overlays[plane]->height;
        vlc_mutex_unlock(&p_sys->bdj_overlay_lock);

        if (plane_height > 0 && y >= plane_height)
            y %= plane_height;
    }

    if (psz_var[6] == 'm')   //Mouse moved
        bd_mouse_select(p_sys->bluray, -1, x, y);
    else if (psz_var[6] == 'c') {
        /* The direct KMS fullscreen controller shares the vout mouse
         * variables with Blu-ray menus. Its callback runs first and marks a
         * hit here so a click on Pause/Seek is not also activated in BD-J. */
        if (var_Type(p_vout, "kms3d-control-click-until") != 0 &&
            mdate() < var_GetInteger(p_vout,
                                     "kms3d-control-click-until"))
            return VLC_SUCCESS;
        bd_mouse_select(p_sys->bluray, -1, x, y);
        p_sys->i_last_ig_activation = mdate();
        bd_user_input(p_sys->bluray, -1, BD_VK_MOUSE_ACTIVATE);
    } else {
        vlc_assert_unreachable();
    }
    return VLC_SUCCESS;
}

static int sendKeyEvent(demux_sys_t *p_sys, unsigned int key)
{
    p_sys->i_last_ig_user_input = mdate();
    if (key == BD_VK_ENTER)
        p_sys->i_last_ig_activation = p_sys->i_last_ig_user_input;

    /* Navigation keys belong to the disc for the whole Blu-ray session,
     * including the short interval between two interactive pages. libbluray
     * can reject an input while the new page is being assembled. Reporting
     * that rejection to the input core makes it reinterpret the same arrow as
     * generic playback control (up/down = volume, left/right = seek), which
     * both changes playback state and displays an unsolicited OSD. The event
     * was nevertheless addressed to a navigation-capable demux: consume it
     * here even when the current HDMV/BD-J page cannot use it yet. */
    (void)bd_user_input(p_sys->bluray, -1, key);

    return VLC_SUCCESS;
}

/*****************************************************************************
 * libbluray overlay handling:
 *****************************************************************************/

static void blurayCloseOverlay(demux_t *p_demux, int plane)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    bluray_overlay_t *ov = p_sys->p_overlays[plane];

    if (ov != NULL) {

        /* drop overlay from vout */
        if (ov->p_updater) {
            unref_subpicture_updater(ov->p_updater);
        }
        /* no references to this overlay exist in vo anymore */
        if (p_sys->p_vout && ov->i_channel != -1) {
            vout_FlushSubpictureChannel(p_sys->p_vout, ov->i_channel);
        }

        vlc_mutex_destroy(&ov->lock);
        subpicture_region_ChainDelete(ov->p_regions);
        free(ov);

        p_sys->p_overlays[plane] = NULL;
    }

    for (int i = 0; i < MAX_OVERLAY; i++)
        if (p_sys->p_overlays[i])
            return;

    /* All overlays have been closed. A full-screen HDMV still no longer
     * needs to keep the last video picture through decoder flushes, and the
     * next feature may use the viewer's automatic crop again. */
    if (p_sys->p_vout != NULL) {
        vout_ChangeStaticFrameHold(p_sys->p_vout, false);
        vout_ChangeInteractiveOverlay(p_sys->p_vout, false);
    } else {
        vout_thread_t *vout = input_GetVout(p_demux->p_input);
        if (vout != NULL) {
            vout_ChangeStaticFrameHold(vout, false);
            vout_ChangeInteractiveOverlay(vout, false);
            vlc_object_release(vout);
        }
    }
    blurayReleaseVout(p_demux);
}

/*
 * Mark the overlay as "ToDisplay" status.
 * This will not send the overlay to the vout instantly, as the vout
 * may not be acquired (not acquirable) yet.
 * If is has already been acquired, the overlay has already been sent to it,
 * therefore, we only flag the overlay as "Outdated"
 */
static void blurayActivateOverlay(demux_t *p_demux, int plane)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    bluray_overlay_t *ov = p_sys->p_overlays[plane];

    if(!ov)
        return;

    /*
     * If the overlay is already displayed, mark the picture as outdated.
     * We must NOT use vout_PutSubpicture if a picture is already displayed.
     */
    vlc_mutex_lock(&ov->lock);
    if (ov->status >= Displayed && p_sys->p_vout) {
        ov->status = Outdated;
        vlc_mutex_unlock(&ov->lock);
        vout_RefreshSubpicture(p_sys->p_vout);
        return;
    }

    /*
     * Mark the overlay as available, but don't display it right now.
     * the blurayDemuxMenu will send it to vout, as it may be unavailable when
     * the overlay is computed
     */
    ov->status = ToDisplay;
    vlc_mutex_unlock(&ov->lock);

}

/**
 * Destroy every regions in the subpicture.
 * This is done in two steps:
 * - Wiping our private regions list
 * - Flagging the overlay as outdated, so the changes are replicated from
 *   the subpicture_updater_t::pf_update
 * This doesn't destroy the subpicture, as the overlay may be used again by libbluray.
 */
static void blurayClearOverlay(demux_t *p_demux, int plane)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    bluray_overlay_t *ov = p_sys->p_overlays[plane];

    if(!ov)
        return;

    vlc_mutex_lock(&ov->lock);

    subpicture_region_ChainDelete(ov->p_regions);
    ov->p_regions = NULL;
    ov->status = Outdated;

    vlc_mutex_unlock(&ov->lock);
}

static void blurayInitOverlay(demux_t *p_demux, int plane, int width, int height)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if(p_sys->p_overlays[plane])
    {
        /* Should not happen */
        msg_Warn( p_demux, "Trying to init over an existing overlay" );
        blurayClearOverlay( p_demux, plane );
        blurayCloseOverlay( p_demux, plane );
    }

    bluray_overlay_t *ov = calloc(1, sizeof(*ov));
    if (unlikely(ov == NULL))
        return;

    ov->width = width;
    ov->height = height;
    ov->i_channel = -1;
    ov->i_update_date = VLC_TICK_INVALID;

    vlc_mutex_init(&ov->lock);

    p_sys->p_overlays[plane] = ov;

    /* HDMV can retire and immediately recreate its video decoder between
     * the final background picture and an infinite interactive still. Mark
     * the active vout before that asynchronous teardown reaches it. Without
     * the retained picture, focus changes are accepted by libbluray but the
     * updated IG plane has nothing against which it can be recomposited.
     * BD-J has its own synthetic-background path and does not use this hold. */
    if (!p_sys->b_bdj_overlay && !p_sys->b_popup_available) {
        vout_thread_t *vout = input_GetVout(p_demux->p_input);
        if (vout != NULL) {
            vout_ChangeStaticFrameHold(vout, true);
            vlc_object_release(vout);
        }
    }
}

/*
 * This will draw to the overlay by adding a region to our region list
 * This will have to be copied to the subpicture used to render the overlay.
 */
/* ARGB in word order -> byte order */
#ifdef WORDS_BIG_ENDIAN
# define ARGB_OVERLAY_CHROMA VLC_CODEC_ARGB
#else
# define ARGB_OVERLAY_CHROMA VLC_CODEC_BGRA
#endif

static void blurayDrawOverlay(demux_t *p_demux, const BD_OVERLAY* const eventov)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    bluray_overlay_t *ov = p_sys->p_overlays[eventov->plane];
    if(!ov)
        return;

    /*
     * Compute a subpicture_region_t.
     * It will be copied and sent to the vout later.
     */
    vlc_mutex_lock(&ov->lock);

    const bool ig_canvas = eventov->plane == BD_OVERLAY_IG;
    const int reg_x = ig_canvas ? 0 : eventov->x;
    const int reg_y = ig_canvas ? 0 : eventov->y;
    const unsigned reg_w = ig_canvas ? ov->width : eventov->w;
    const unsigned reg_h = ig_canvas ? ov->height : eventov->h;
    const vlc_fourcc_t reg_chroma = ig_canvas ? VLC_CODEC_YUVA
                                              : VLC_CODEC_YUVP;

    if (eventov->palette != NULL) {
        ov->palette.i_entries = 256;
        for (int i = 0; i < 256; ++i) {
            ov->palette.palette[i][0] = eventov->palette[i].Y;
            ov->palette.palette[i][1] = eventov->palette[i].Cb;
            ov->palette.palette[i][2] = eventov->palette[i].Cr;
            ov->palette.palette[i][3] = eventov->palette[i].T;
        }
        ov->b_palette_valid = true;
    }

    /* Find a region to update */
    subpicture_region_t *p_reg = ov->p_regions;
    subpicture_region_t *p_last = NULL;
    while (p_reg != NULL) {
        p_last = p_reg;
        if (p_reg->i_x == reg_x && p_reg->i_y == reg_y &&
            p_reg->fmt.i_width == reg_w &&
            p_reg->fmt.i_height == reg_h &&
            p_reg->fmt.i_chroma == reg_chroma)
            break;
        p_reg = p_reg->p_next;
    }

    /* If there is no region to update, create a new one. */
    if (!p_reg) {
        video_format_t fmt;
        video_format_Init(&fmt, 0);
        video_format_Setup(&fmt, reg_chroma, reg_w, reg_h,
                           reg_w, reg_h, 1, 1);

        p_reg = subpicture_region_New(&fmt);
        if (p_reg) {
            p_reg->i_x = reg_x;
            p_reg->i_y = reg_y;
            if (ig_canvas) {
                for (int c = 0; c < 4; ++c) {
                    plane_t *plane = &p_reg->p_picture->p[c];
                    for (unsigned y = 0; y < reg_h; ++y)
                        memset(plane->p_pixels + y * plane->i_pitch, 0,
                               reg_w);
                }
            }
            /* Append it to our list. */
            if (p_last != NULL)
                p_last->p_next = p_reg;
            else /* If we don't have a last region, then our list empty */
                ov->p_regions = p_reg;
        }
        else
        {
            vlc_mutex_unlock(&ov->lock);
            return;
        }
    }

    uint8_t yuva_palette[256][4];
    if (ig_canvas) {
        memset(yuva_palette, 0, sizeof(yuva_palette));
        if (ov->b_palette_valid) {
            memcpy(yuva_palette, ov->palette.palette,
                   sizeof(yuva_palette));
        }
    }

    /* Now we can update the region, regardless it's an update or an insert */
    const BD_PG_RLE_ELEM *img = eventov->img;
    for (int y = 0; y < eventov->h; y++)
        for (int x = 0; x < eventov->w;) {
            if (ig_canvas) {
                picture_t *picture = p_reg->p_picture;
                const unsigned palette_index = img->color & 0xff;
                const uint8_t *src = yuva_palette[palette_index];
                for (unsigned pixel = 0; pixel < img->len; ++pixel) {
                    const unsigned px = eventov->x + x + pixel;
                    const unsigned py = eventov->y + y;
                    /* DRAW updates the overlay plane, it is not a source-over
                     * blend operation. libbluray deliberately omits WIPE when
                     * a button state changes to an object with identical
                     * bounds; transparent pixels in the new object must then
                     * erase the previous selection. Keeping the full YUVA
                     * canvas still avoids overlapping VLC regions, while
                     * replacing all four components preserves HDMV plane
                     * semantics. */
                    for (int c = 0; c < 4; ++c)
                        picture->p[c].p_pixels[
                            py * picture->p[c].i_pitch + px] = src[c];
                }
            } else {
                plane_t *p = &p_reg->p_picture->p[0];
                memset(&p->p_pixels[y * p->i_pitch + x],
                       img->color, img->len);
            }
            x += img->len;
            img++;
        }

    if (!ig_canvas && eventov->palette) {
        p_reg->fmt.p_palette->i_entries = 256;
        for (int i = 0; i < 256; ++i) {
            p_reg->fmt.p_palette->palette[i][0] = eventov->palette[i].Y;
            p_reg->fmt.p_palette->palette[i][1] = eventov->palette[i].Cb;
            p_reg->fmt.p_palette->palette[i][2] = eventov->palette[i].Cr;
            p_reg->fmt.p_palette->palette[i][3] = eventov->palette[i].T;
        }
    }

    vlc_mutex_unlock(&ov->lock);
    /*
     * /!\ The region is now stored in our internal list, but not in the subpicture /!\
     */
}

/* BD_OVERLAY_WIPE describes an arbitrary plane rectangle, not necessarily the
 * exact bounds of a preceding DRAW. Interactive buttons are often assembled
 * from several regions and libbluray wipes their union before drawing the new
 * selection. Keeping partially intersecting regions leaves fragments of the
 * previous screen visible until a later full clear. */
static void blurayWipeOverlay(demux_t *p_demux, const BD_OVERLAY *eventov)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    bluray_overlay_t *ov = p_sys->p_overlays[eventov->plane];
    if (ov == NULL)
        return;

    const unsigned wipe_x2 = eventov->x + eventov->w;
    const unsigned wipe_y2 = eventov->y + eventov->h;

    vlc_mutex_lock(&ov->lock);
    subpicture_region_t **link = &ov->p_regions;
    while (*link != NULL) {
        subpicture_region_t *region = *link;
        const unsigned reg_x1 = region->i_x;
        const unsigned reg_y1 = region->i_y;
        const unsigned reg_x2 = reg_x1 + region->fmt.i_width;
        const unsigned reg_y2 = reg_y1 + region->fmt.i_height;
        const unsigned x1 = __MAX((unsigned)eventov->x, reg_x1);
        const unsigned y1 = __MAX((unsigned)eventov->y, reg_y1);
        const unsigned x2 = __MIN(wipe_x2, reg_x2);
        const unsigned y2 = __MIN(wipe_y2, reg_y2);

        if (x1 >= x2 || y1 >= y2) {
            link = &region->p_next;
            continue;
        }

        if (x1 == reg_x1 && y1 == reg_y1 &&
            x2 == reg_x2 && y2 == reg_y2) {
            *link = region->p_next;
            subpicture_region_Delete(region);
            continue;
        }

        if (region->fmt.i_chroma == VLC_CODEC_YUVA) {
            for (int c = 0; c < 4; ++c) {
                plane_t *plane = &region->p_picture->p[c];
                for (unsigned y = y1 - reg_y1; y < y2 - reg_y1; ++y)
                    memset(plane->p_pixels + y * plane->i_pitch +
                           x1 - reg_x1, 0, x2 - x1);
            }
        } else {
            plane_t *plane = &region->p_picture->p[0];
            for (unsigned y = y1 - reg_y1; y < y2 - reg_y1; ++y)
                /* Palette entry 0xff is guaranteed transparent by the
                 * Blu-ray overlay contract. */
                memset(plane->p_pixels + y * plane->i_pitch + x1 - reg_x1,
                       0xff, x2 - x1);
        }
        link = &region->p_next;
    }
    vlc_mutex_unlock(&ov->lock);
}

static void blurayOverlayProc(void *ptr, const BD_OVERLAY *const overlay)
{
    demux_t *p_demux = (demux_t*)ptr;
    demux_sys_t *p_sys = p_demux->p_sys;

    if (!overlay) {
        msg_Info(p_demux, "Closing overlays.");
        for (int i = 0; i < MAX_OVERLAY; i++)
            blurayCloseOverlay(p_demux, i);
        return;
    }

    if(overlay->plane >= MAX_OVERLAY)
        return;

    switch (overlay->cmd) {
    case BD_OVERLAY_INIT:
        msg_Info(p_demux, "Initializing overlay");
        vlc_mutex_lock(&p_sys->bdj_overlay_lock);
        blurayInitOverlay(p_demux, overlay->plane, overlay->w, overlay->h);
        vlc_mutex_unlock(&p_sys->bdj_overlay_lock);
        break;
    case BD_OVERLAY_CLOSE:
        vlc_mutex_lock(&p_sys->bdj_overlay_lock);
        blurayClearOverlay(p_demux, overlay->plane);
        blurayCloseOverlay(p_demux, overlay->plane);
        vlc_mutex_unlock(&p_sys->bdj_overlay_lock);
        break;
    case BD_OVERLAY_CLEAR:
        msg_Dbg(p_demux, "Blu-ray overlay clear plane %u", overlay->plane);
        blurayClearOverlay(p_demux, overlay->plane);
        break;
    case BD_OVERLAY_HIDE:
        msg_Dbg(p_demux, "Blu-ray overlay hide plane %u", overlay->plane);
        blurayClearOverlay(p_demux, overlay->plane);
        break;
    case BD_OVERLAY_FLUSH: {
        vlc_tick_t update_date = VLC_TICK_INVALID;
        vlc_tick_t current = VLC_TICK_INVALID;
        const bool recent_user_input =
            p_sys->i_last_ig_user_input != VLC_TICK_INVALID &&
            mdate() - p_sys->i_last_ig_user_input <= VLC_TICK_FROM_MS(500);
        if (overlay->plane == BD_OVERLAY_IG &&
            !recent_user_input &&
            es_out_Control(p_demux->out, ES_OUT_GET_CURRENT_PCR,
                           &current) == VLC_SUCCESS) {
            uint64_t title_time = bd_tell_time(p_sys->bluray);
            uint64_t clip_start = 0;
            uint64_t clip_in = 0;

            vlc_mutex_lock(&p_sys->pl_info_lock);
            if (p_sys->p_clip_info != NULL) {
                clip_start = p_sys->p_clip_info->start_time;
                clip_in = p_sys->p_clip_info->in_time;
            }
            vlc_mutex_unlock(&p_sys->pl_info_lock);

            if (title_time >= clip_start) {
                vlc_tick_t target = FROM_SCALE_NZ(clip_in +
                                                  title_time - clip_start);
                if (target > current) {
                    vlc_tick_t delay = target - current;
                    if (delay < VLC_TICK_FROM_SEC(10)) {
                        update_date = mdate() + delay;
                        msg_Dbg(p_demux, "scheduling Blu-ray IG in %"PRId64
                                " ms (target=%"PRId64", current=%"PRId64")",
                                MS_FROM_VLC_TICK(delay), target, current);
                    }
                }
            }
        }
        /* libbluray commonly leaves IG flushes undated.  Its automatic page
         * construction then reaches us at the demux head, roughly pts_delay
         * before the matching menu background is presented.  Use that known
         * output delay when the local play-item clock cannot be mapped onto
         * the filter's continuous timeline.  Never delay hover/key redraws:
         * those are direct UI feedback and must remain immediate. */
        if (overlay->plane == BD_OVERLAY_IG &&
            update_date == VLC_TICK_INVALID &&
            !recent_user_input) {
            vlc_tick_t system_origin;
            vlc_tick_t presentation_delay;
            if (es_out_Control(p_demux->out, ES_OUT_GET_PCR_SYSTEM,
                               &system_origin, &presentation_delay) == VLC_SUCCESS &&
                presentation_delay > 0 &&
                presentation_delay < VLC_TICK_FROM_SEC(10)) {
                update_date = mdate() + presentation_delay;
                msg_Dbg(p_demux, "scheduling automatic Blu-ray IG by output "
                        "delay: %"PRId64" ms",
                        MS_FROM_VLC_TICK(presentation_delay));
            }
        }
        if (p_sys->p_overlays[overlay->plane]) {
            vlc_mutex_lock(&p_sys->p_overlays[overlay->plane]->lock);
            p_sys->p_overlays[overlay->plane]->i_pts = overlay->pts;
            /* Preserve a previously armed deadline across the short PCR
             * reset at a menu-loop boundary, when the fresh clock is not yet
             * queryable but libbluray redraws the same page. */
            if (update_date > VLC_TICK_INVALID)
                p_sys->p_overlays[overlay->plane]->i_update_date = update_date;
            vlc_mutex_unlock(&p_sys->p_overlays[overlay->plane]->lock);
        }
        msg_Dbg(p_demux, "Blu-ray overlay flush plane %u pts=%"PRId64
                " (%.3fs), disc=%.3fs, input=%.3fs",
                overlay->plane, overlay->pts,
                overlay->pts / 90000.0,
                bd_tell_time(p_sys->bluray) / 90000.0,
                var_GetInteger(p_demux->p_input, "time") /
                    (double)CLOCK_FREQ);
        blurayActivateOverlay(p_demux, overlay->plane);
        break;
    }
    case BD_OVERLAY_DRAW:
        msg_Dbg(p_demux, "Blu-ray overlay draw plane %u, region %u,%u %ux%u",
                overlay->plane, overlay->x, overlay->y, overlay->w, overlay->h);
        blurayDrawOverlay(p_demux, overlay);
        break;
    case BD_OVERLAY_WIPE:
        msg_Dbg(p_demux, "Blu-ray overlay wipe plane %u, region %u,%u %ux%u",
                overlay->plane, overlay->x, overlay->y, overlay->w, overlay->h);
        blurayWipeOverlay(p_demux, overlay);
        break;
    default:
        msg_Warn(p_demux, "Unknown BD overlay command: %u", overlay->cmd);
        break;
    }
}

/*
 * ARGB overlay (BD-J)
 */
static void blurayInitArgbOverlay(demux_t *p_demux, int plane, int width, int height)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    blurayInitOverlay(p_demux, plane, width, height);

    if (!p_sys->p_overlays[plane]->p_regions) {
        video_format_t fmt;
        video_format_Init(&fmt, 0);
        video_format_Setup(&fmt, ARGB_OVERLAY_CHROMA, width, height, width, height, 1, 1);

        p_sys->p_overlays[plane]->p_regions = subpicture_region_New(&fmt);
    }
}

static void blurayDrawArgbOverlay(demux_t *p_demux, const BD_ARGB_OVERLAY* const eventov)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    bluray_overlay_t *ov = p_sys->p_overlays[eventov->plane];
    if(!ov)
        return;

    vlc_mutex_lock(&ov->lock);

    /* Find a region to update */
    subpicture_region_t *p_reg = ov->p_regions;
    if (!p_reg || p_reg->fmt.i_chroma != ARGB_OVERLAY_CHROMA ||
        p_reg->fmt.i_width < (unsigned)ov->width ||
        p_reg->fmt.i_height < (unsigned)ov->height) {
        /* A title/playlist transition can clear the VLC region while the
         * Java graphics plane remains open.  libbluray consequently sends
         * DRAW/FLUSH updates without another INIT.  Recreate the backing
         * region here instead of silently dropping all subsequent menu text. */
        msg_Dbg(p_demux, "recreating missing BD-J ARGB backing region");
        subpicture_region_ChainDelete(ov->p_regions);
        ov->p_regions = NULL;

        video_format_t fmt;
        video_format_Init(&fmt, 0);
        video_format_Setup(&fmt, ARGB_OVERLAY_CHROMA,
                          ov->width, ov->height,
                          ov->width, ov->height, 1, 1);
        p_reg = subpicture_region_New(&fmt);
        ov->p_regions = p_reg;
    }
    if (!p_reg || eventov->x + eventov->w > p_reg->fmt.i_width ||
        eventov->y + eventov->h > p_reg->fmt.i_height) {
        msg_Warn(p_demux,
                 "rejecting BD-J ARGB update %u,%u %ux%u (region=%p, %ux%u)",
                 eventov->x, eventov->y, eventov->w, eventov->h,
                 (void *)p_reg,
                 p_reg ? p_reg->fmt.i_width : 0,
                 p_reg ? p_reg->fmt.i_height : 0);
        vlc_mutex_unlock(&ov->lock);
        return;
    }

    /* Now we can update the region */
    const uint32_t *src0 = eventov->argb;
    uint8_t        *dst0 = p_reg->p_picture->p[0].p_pixels +
                           p_reg->p_picture->p[0].i_pitch * eventov->y +
                           eventov->x * 4;
    /* always true as for now, see bd_bdj_osd_cb */
    /* Row by row. The single-shot path this replaced was guarded by
     * "eventov->stride == i_pitch", comparing a stride in pixels with a pitch
     * in bytes: never true for a 4-byte chroma, so it never ran -- and its
     * length, stride * h - x, ignored the y offset already applied to dst0,
     * so it would have run off the end of the picture if it ever had. */
    for(uint16_t h = 0; h < eventov->h; h++)
    {
        memcpy(dst0, src0, eventov->w * 4);
        dst0 = dst0 + p_reg->p_picture->p[0].i_pitch;
        src0 = src0 + eventov->stride;
    }

    vlc_mutex_unlock(&ov->lock);
    /*
     * /!\ The region is now stored in our internal list, but not in the subpicture /!\
     */
}

static void blurayArgbOverlayProc(void *ptr, const BD_ARGB_OVERLAY *const overlay)
{
    demux_t *p_demux = (demux_t*)ptr;
    demux_sys_t *p_sys = p_demux->p_sys;

    if(overlay->plane >= MAX_OVERLAY)
        return;

    switch (overlay->cmd) {
    case BD_ARGB_OVERLAY_INIT:
        msg_Dbg(p_demux, "BD-J ARGB overlay init plane %u, %ux%u",
                overlay->plane, overlay->w, overlay->h);
        vlc_mutex_lock(&p_sys->bdj_overlay_lock);
        /* libbluray raises BD_EVENT_MENU alongside this very command;
         * remember that the flag now tracks a BD-J plane rather than an
         * open menu (see blurayCacheInhibitUpdate). */
        p_sys->b_bdj_overlay = true;
        blurayInitArgbOverlay(p_demux, overlay->plane, overlay->w, overlay->h);
        if (p_sys->p_overlays[overlay->plane])
            p_sys->p_overlays[overlay->plane]->stereo_offset =
                overlay->stereo_offset;
        vlc_mutex_unlock(&p_sys->bdj_overlay_lock);
        break;
    case BD_ARGB_OVERLAY_CLOSE:
        vlc_mutex_lock(&p_sys->bdj_overlay_lock);
        p_sys->b_bdj_overlay = false;
        blurayClearOverlay(p_demux, overlay->plane);
        blurayCloseOverlay(p_demux, overlay->plane);
        vlc_mutex_unlock(&p_sys->bdj_overlay_lock);
        break;
    case BD_ARGB_OVERLAY_FLUSH:
        msg_Dbg(p_demux, "BD-J ARGB overlay flush plane %u, region %u,%u %ux%u",
                overlay->plane, overlay->x, overlay->y, overlay->w, overlay->h);
        if (p_sys->p_overlays[overlay->plane]) {
            vlc_mutex_lock(&p_sys->p_overlays[overlay->plane]->lock);
            p_sys->p_overlays[overlay->plane]->stereo_offset =
                overlay->stereo_offset;
            vlc_mutex_unlock(&p_sys->p_overlays[overlay->plane]->lock);
        }
        blurayActivateOverlay(p_demux, overlay->plane);
        break;
    case BD_ARGB_OVERLAY_DRAW:
        msg_Dbg(p_demux, "BD-J ARGB overlay draw plane %u, region %u,%u %ux%u",
                overlay->plane, overlay->x, overlay->y, overlay->w, overlay->h);
        blurayDrawArgbOverlay(p_demux, overlay);
        break;
    default:
        msg_Warn(p_demux, "Unknown BD ARGB overlay command: %u", overlay->cmd);
        break;
    }
}

static void bluraySendOverlayToVout(demux_t *p_demux, bluray_overlay_t *p_ov)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    assert(p_ov != NULL);
    assert(p_ov->i_channel == -1);

    if (p_ov->p_updater) {
        unref_subpicture_updater(p_ov->p_updater);
        p_ov->p_updater = NULL;
    }

    subpicture_t *p_pic = bluraySubpictureCreate(p_ov);
    if (!p_pic) {
        msg_Err(p_demux, "bluraySubpictureCreate() failed");
        return;
    }

    p_pic->i_start = p_pic->i_stop =
        p_ov->i_update_date > VLC_TICK_INVALID ? p_ov->i_update_date : mdate();
    p_pic->i_channel = vout_RegisterSubpictureChannel(p_sys->p_vout);
    p_ov->i_channel = p_pic->i_channel;
    vout_ChangeInteractiveOverlay(p_sys->p_vout, true);
    msg_Dbg(p_demux, "sending Blu-ray overlay %ux%u to vout channel %d",
            p_ov->width, p_ov->height, p_ov->i_channel);

    /*
     * After this point, the picture should not be accessed from the demux thread,
     * as it is held by the vout thread.
     * This must be done only once per subpicture, ie. only once between each
     * blurayInitOverlay & blurayCloseOverlay call.
     */
    vout_PutSubpicture(p_sys->p_vout, p_pic);

    /*
     * Mark the picture as Outdated, as it contains no region for now.
     * This will make the subpicture_updater_t call pf_update
     */
    p_ov->status = Outdated;
}

static bool blurayTitleIsRepeating(BLURAY_TITLE_INFO *title_info,
                                   unsigned repeats, unsigned ratio)
{
#if BLURAY_VERSION >= BLURAY_VERSION_CODE(1, 0, 0)
    const BLURAY_CLIP_INFO *prev = NULL;
    unsigned maxrepeats = 0;
    unsigned sequence = 0;
    if(!title_info->chapter_count)
        return false;

    for (unsigned int j = 0; j < title_info->chapter_count; j++)
    {
        unsigned i = title_info->chapters[j].clip_ref;
        if(i < title_info->clip_count)
        {
            if(prev == NULL ||
               /* non repeated does not need start time offset */
               title_info->clips[i].start_time == 0 ||
               /* repeats occurs on same segment */
               memcmp(title_info->clips[i].clip_id, prev->clip_id, 6) ||
               prev->in_time != title_info->clips[i].in_time ||
               prev->pkt_count != title_info->clips[i].pkt_count)
            {
                sequence = 0;
                prev = &title_info->clips[i];
                continue;
            }
            else
            {
                if(maxrepeats < sequence++)
                    maxrepeats = sequence;
            }
        }
    }
    return (maxrepeats > repeats &&
            (100 * maxrepeats / title_info->chapter_count) >= ratio);
#else
    return false;
#endif
}

static void blurayUpdateTitleInfo(input_title_t *t, BLURAY_TITLE_INFO *title_info)
{
    t->i_length = FROM_SCALE_NZ(title_info->duration);

    for (int i = 0; i < t->i_seekpoint; i++)
        vlc_seekpoint_Delete( t->seekpoint[i] );
    TAB_CLEAN(t->i_seekpoint, t->seekpoint);

    /* FIXME: have libbluray expose repeating titles */
    if(blurayTitleIsRepeating(title_info, 50, 90))
        return;

    for (unsigned int j = 0; j < title_info->chapter_count; j++) {
        seekpoint_t *s = vlc_seekpoint_New();
        if (!s) {
            break;
        }
        s->i_time_offset = FROM_SCALE_NZ(title_info->chapters[j].start);
#if BLURAY_VERSION >= BLURAY_VERSION_CODE(1,5,0)
        /* Chapter names, where the disc carries them (libbluray >= 1.5.0
         * resolves them in the preferred language). Every interface already
         * displays seekpoint names, so there is nothing else to do. */
        if (title_info->chapters[j].chapter_name != NULL &&
            title_info->chapters[j].chapter_name[0] != '\0')
            s->psz_name = strdup(title_info->chapters[j].chapter_name);
#endif

        TAB_APPEND(t->i_seekpoint, t->seekpoint, s);
    }
}

static void blurayInitTitles(demux_t *p_demux, uint32_t menu_titles)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    const BLURAY_DISC_INFO *di = bd_get_disc_info(p_sys->bluray);

    /* get and set the titles */
    uint32_t i_title = menu_titles;

    /* Playlist the key database names as the feature, when it names one. Only
     * looked up when it can actually be used: with menus the disc decides what
     * plays, and the scan walks a file that runs to tens of megabytes. */
    int i_keydb_playlist = BLURAY_KEYDB_NO_PLAYLIST;

    vlc_tick_t i_scan_start = mdate();

    if (!p_sys->b_menu) {
        i_title = bd_get_titles(p_sys->bluray, TITLES_RELEVANT, 60);
        p_sys->i_longest_title = bd_get_main_title(p_sys->bluray);

        if (di != NULL && di->aacs_detected &&
            var_InheritBool(p_demux, "bluray-keydb-playlist"))
            i_keydb_playlist = bluray_KeydbFindMainPlaylist(VLC_OBJECT(p_demux),
                                                            di->disc_id);
    }

    for (uint32_t i = 0; i < i_title; i++) {
        input_title_t *t = vlc_input_title_New();
        if (!t)
            break;

        if (!p_sys->b_menu) {
            BLURAY_TITLE_INFO *title_info = bd_get_title_info(p_sys->bluray, i, 0);

            /* Name every title after the playlist it actually plays. Without
             * this the list is a bare "Title 1..N" that cannot be matched to
             * anything on the disc or to what a key database says -- which is
             * precisely what playlist obfuscation relies on. */
            if (title_info != NULL) {
                const uint32_t i_playlist = title_info->playlist;

                blurayUpdateTitleInfo(t, title_info);

                if ((int)i_playlist == i_keydb_playlist) {
                    /* Believe the database over the longest-title heuristic:
                     * on an obfuscated disc the decoys share the feature's
                     * duration, so the heuristic is picking among them at
                     * random. */
                    p_sys->i_longest_title = i;
                    if (asprintf(&t->psz_name, _("%05u.mpls (main playlist)"),
                                 i_playlist) < 0)
                        t->psz_name = NULL;
                    msg_Dbg(p_demux, "key database names %05u.mpls as the main "
                            "playlist, selecting title %u", i_playlist, i);
                } else if (asprintf(&t->psz_name, "%05u.mpls", i_playlist) < 0) {
                    t->psz_name = NULL;
                }
            }

            bd_free_title_info(title_info);

        } else if (i == 0) {
            t->psz_name = strdup(_("Top Menu"));
            t->i_flags = INPUT_TITLE_MENU | INPUT_TITLE_INTERACTIVE;
        } else if (i == i_title - 1) {
            t->psz_name = strdup(_("First Play"));
            if (di && di->first_play && di->first_play->interactive) {
                t->i_flags = INPUT_TITLE_INTERACTIVE;
            }
        } else {
            /* add possible title name from disc metadata */
            if (di && di->titles && i <= di->num_titles) {
                if (di->titles[i]->name) {
                    t->psz_name = strdup(di->titles[i]->name);
                }
                if (di->titles[i]->interactive) {
                    t->i_flags = INPUT_TITLE_INTERACTIVE;
                }
            }
        }

        TAB_APPEND(p_sys->i_title, p_sys->pp_title, t);
    }

    /* Every playlist on the disc is read here, twice for the ones kept: the
     * scan is the bulk of the time to first picture, and it is entirely made
     * of small reads scattered over the disc. */
    if (!p_sys->b_menu)
        msg_Dbg(p_demux, "scanned %u titles in %" PRId64 " ms",
                i_title, (mdate() - i_scan_start) / 1000);
}

static void blurayRestartParser(demux_t *p_demux, bool b_flush, bool b_random_access)
{
    /*
     * This is a hack and will have to be removed.
     * The parser should be flushed, and not destroy/created each time
     * we are changing title.
     */
    demux_sys_t *p_sys = p_demux->p_sys;

    if(b_flush)
        es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_DISABLE_OUTPUT);

    if (p_sys->p_parser)
        vlc_demux_chained_Delete(p_sys->p_parser);

    if(b_flush)
        es_out_Control(p_sys->p_tf_out, ES_OUT_TF_FILTER_RESET);

    p_sys->p_parser = vlc_demux_chained_New(VLC_OBJECT(p_demux), "ts", p_sys->p_out);
    if (!p_sys->p_parser)
        msg_Err(p_demux, "Failed to create TS demuxer");

    es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_ENABLE_OUTPUT);

    es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_RANDOM_ACCESS, b_random_access);
}

static void blurayCloseMVCClip(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if (p_sys->p_mvc_parser != NULL)
    {
        vlc_demux_chained_Delete(p_sys->p_mvc_parser);
        p_sys->p_mvc_parser = NULL;
    }
    if (p_sys->p_mvc_file != NULL)
    {
        p_sys->p_mvc_file->close(p_sys->p_mvc_file);
        p_sys->p_mvc_file = NULL;
    }
    p_sys->i_mvc_clip = -1;
    p_sys->i_mvc_main_size = 0;
    p_sys->i_mvc_clip_size = 0;
    p_sys->i_mvc_main_read = 0;
    p_sys->i_mvc_clip_read = 0;
    p_sys->b_mvc_feed_catching_up = false;
    if (p_sys->p_out != NULL)
        es_out_Control(p_sys->p_out,
                       BLURAY_ES_OUT_CONTROL_SET_MVC_EXPECTED, false, false,
                       (vlc_tick_t)0);
}

static bool blurayClpiPresentationStart(const CLPI_CL *clpi, uint8_t stc_id,
                                        uint32_t *start)
{
    if (clpi == NULL || start == NULL)
        return false;

    for (uint8_t i = 0; i < clpi->sequence.num_atc_seq; ++i) {
        const CLPI_ATC_SEQ *atc = &clpi->sequence.atc_seq[i];
        if (atc->stc_seq == NULL || stc_id < atc->offset_stc_id ||
            stc_id >= atc->offset_stc_id + atc->num_stc_seq)
            continue;

        *start = atc->stc_seq[stc_id - atc->offset_stc_id]
                         .presentation_start_time;
        return true;
    }
    return false;
}

static bool blurayReadMVC(demux_t *p_demux, size_t bytes)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    if (p_sys->p_mvc_file == NULL || p_sys->p_mvc_parser == NULL)
        return false;

    block_t *block = block_Alloc(bytes);
    if (unlikely(block == NULL))
        return false;
    int64_t read = p_sys->p_mvc_file->read(p_sys->p_mvc_file,
                                           block->p_buffer, bytes);
    if (read <= 0)
    {
        block_Release(block);
        p_sys->p_mvc_file->close(p_sys->p_mvc_file);
        p_sys->p_mvc_file = NULL;
        if (read < 0)
            msg_Warn(p_demux, "error reading Blu-ray MVC extension clip");
        return false;
    }

    block->i_buffer = read;
    p_sys->i_mvc_clip_read += read;
    vlc_demux_chained_Send(p_sys->p_mvc_parser, block);
    return true;
}

static bool blurayProbeMVCPts(BD_FILE_H *file, uint64_t size,
                              uint64_t offset, uint64_t *pts,
                              uint64_t *packet_offset)
{
    if (file == NULL || pts == NULL || packet_offset == NULL || offset >= size)
        return false;

    offset -= offset % 192;
    if (file->seek(file, offset, SEEK_SET) < 0)
        return false;

    /* A high-bitrate MVC access unit can span well over one normal demux
     * block, so use a wide enough window to reach the next PES header from an
     * arbitrary packet boundary. */
    const size_t probe_size = 16 * BD_READ_SIZE;
    block_t *probe = block_Alloc(probe_size);
    if (unlikely(probe == NULL))
        return false;
    int64_t read = file->read(file, probe->p_buffer, probe->i_buffer);
    if (read <= 0) {
        block_Release(probe);
        return false;
    }

    for (size_t pos = 0; pos + 192 <= (size_t)read; pos += 192) {
        const uint8_t *ts = &probe->p_buffer[pos + 4];
        if (ts[0] != 0x47 || !(ts[1] & 0x40))
            continue;
        const unsigned pid = ((ts[1] & 0x1f) << 8) | ts[2];
        if (pid != 0x1012)
            continue;

        const unsigned adaptation = (ts[3] >> 4) & 3;
        if (!(adaptation & 1))
            continue;
        size_t payload = 4;
        if (adaptation & 2) {
            payload += 1 + ts[4];
            if (payload >= 188)
                continue;
        }
        if (payload + 14 > 188 || ts[payload] != 0 ||
            ts[payload + 1] != 0 || ts[payload + 2] != 1 ||
            !(ts[payload + 7] & 0x80))
            continue;

        const uint8_t *encoded = &ts[payload + 9];
        *pts = ((uint64_t)(encoded[0] & 0x0e) << 29) |
               ((uint64_t)encoded[1] << 22) |
               ((uint64_t)(encoded[2] & 0xfe) << 14) |
               ((uint64_t)encoded[3] << 7) |
               ((uint64_t)encoded[4] >> 1);
        *packet_offset = offset + pos;
        block_Release(probe);
        return true;
    }

    block_Release(probe);
    return false;
}

/* Locate the dependent stream by its own PES clock when the disc omitted the
 * optional CPI-SS index. A fixed byte ratio is not a time map for VBR video:
 * on Rio it lands the dependent view 26 seconds ahead of the base view.
 * Rewind from the binary-search result so the base view's preceding random
 * access point is always covered too. */
static bool blurayFindMVCOffsetByPts(BD_FILE_H *file, uint64_t size,
                                     uint64_t target_pts, uint64_t *offset)
{
    uint64_t low = 0;
    uint64_t high = size;
    uint64_t best = 0;
    bool found = false;

    /* Sixteen probes resolve even a 50 GiB extension to well below one MiB,
     * without making an optical drive perform dozens of random seeks. */
    for (unsigned attempt = 0; attempt < 16 &&
         high > low + BD_CLUSTER_SIZE; ++attempt) {
        uint64_t middle = low + (high - low) / 2;
        middle -= middle % BD_CLUSTER_SIZE;
        uint64_t pts, packet;
        if (!blurayProbeMVCPts(file, size, middle, &pts, &packet)) {
            high = middle;
            continue;
        }
        if (pts <= target_pts) {
            found = true;
            best = packet;
            low = packet + BD_CLUSTER_SIZE;
        } else {
            high = middle;
        }
    }

    if (!found)
        return false;
    const uint64_t preroll = UINT64_C(4) * 1024 * 1024;
    *offset = best > preroll ? best - preroll : 0;
    *offset -= *offset % BD_CLUSTER_SIZE;
    return true;
}

static void blurayOpenMVCClip(demux_t *p_demux, uint32_t clip)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    blurayCloseMVCClip(p_demux);

    if (!p_sys->b_stereoscopic_output) {
        msg_Dbg(p_demux, "keeping Blu-ray MVC extension disabled: disc output mode is 2D");
        return;
    }

    /* A one-picture HDMV menu is safer and visually equivalent as mono. Its
     * dependent stream can terminate in the same access unit as its base;
     * Edge264 then legally outputs the AVC-compatible base before the MVC
     * extension reaches it, leaving no second chance once STILL is entered.
     * The frame-packed OpenGL path duplicates MULTIVIEW_2D into both eyes, so
     * keeping this play item on ordinary H.264 also preserves HDMI 3D mode. */
    bool hdmv_still = false;
    vlc_mutex_lock(&p_sys->pl_info_lock);
    if (p_sys->p_clip_info != NULL)
        hdmv_still = p_sys->p_clip_info->still_mode != 0;
    vlc_mutex_unlock(&p_sys->pl_info_lock);
    if (hdmv_still) {
        msg_Dbg(p_demux, "duplicating HDMV still menu into both HDMI 3D eyes");
        return;
    }

    MPLS_PL *pl = bd_get_title_mpls(p_sys->bluray);
    if (p_sys->i_mvc_sub_path < 0 || pl == NULL ||
        (unsigned)p_sys->i_mvc_sub_path >= pl->ext_sub_count ||
        clip >= pl->list_count)
        return;

    MPLS_SUB *path = &pl->ext_sub_path[p_sys->i_mvc_sub_path];
    if (clip >= path->sub_playitem_count)
        return;
    MPLS_SUB_PI *sub = &path->sub_play_item[clip];
    if (sub->clip_count == 0 || sub->clip == NULL)
        return;

    msg_Dbg(p_demux, "MVC play-item timing: main=%u..%u, dependent=%u..%u, "
            "sync item=%u pts=%u", pl->play_item[clip].in_time,
            pl->play_item[clip].out_time, sub->in_time, sub->out_time,
            sub->sync_play_item_id, sub->sync_pts);

    char filename[sizeof(sub->clip[0].clip_id) + sizeof(".m2ts")];
    snprintf(filename, sizeof(filename), "%.5s.m2ts", sub->clip[0].clip_id);
    p_sys->p_mvc_file = bd_clip_open(p_sys->bluray, filename);
    if (p_sys->p_mvc_file == NULL)
    {
        msg_Warn(p_demux, "cannot open Blu-ray MVC extension clip %s", filename);
        return;
    }

    /* BD_FILE_H::seek() is documented to return the resulting offset, but
     * libbluray's native Windows file backend currently forwards fseeko64's
     * status code instead (zero on success).  That made every dependent MVC
     * clip opened from a mounted volume look empty, while ISO stream access
     * worked because its UDF backend returns the offset.  Query tell() after
     * the successful end seek so both conforming and status-returning
     * backends produce the real size. */
    int64_t size = -1;
    if (p_sys->p_mvc_file->seek(p_sys->p_mvc_file, 0, SEEK_END) >= 0)
        size = p_sys->p_mvc_file->tell(p_sys->p_mvc_file);
    if (size <= 0 || p_sys->p_mvc_file->seek(p_sys->p_mvc_file, 0, SEEK_SET) < 0)
    {
        msg_Warn(p_demux, "cannot size Blu-ray MVC extension clip %s", filename);
        blurayCloseMVCClip(p_demux);
        return;
    }

    vlc_mutex_lock(&p_sys->pl_info_lock);
    const uint64_t main_size = p_sys->p_clip_info != NULL
                             ? (uint64_t)p_sys->p_clip_info->pkt_count * 192 : 0;
    vlc_mutex_unlock(&p_sys->pl_info_lock);
    if (main_size == 0)
    {
        msg_Warn(p_demux, "Blu-ray main clip has no packet count for MVC sync");
        blurayCloseMVCClip(p_demux);
        return;
    }

    p_sys->p_mvc_parser = vlc_demux_chained_New(VLC_OBJECT(p_demux), "ts",
                                                 p_sys->p_mvc_out);
    if (p_sys->p_mvc_parser == NULL)
    {
        msg_Err(p_demux, "cannot create Blu-ray MVC extension demuxer");
        blurayCloseMVCClip(p_demux);
        return;
    }

    p_sys->i_mvc_clip = clip;
    p_sys->i_mvc_main_size = main_size;
    p_sys->i_mvc_clip_size = size;
    vlc_mutex_lock(&p_sys->pl_info_lock);
    const bool base_right = p_sys->p_pl_info != NULL &&
                            p_sys->p_pl_info->mvc_base_view_r_flag;
    vlc_mutex_unlock(&p_sys->pl_info_lock);

    /* Main and dependent M2TS files can use different STC origins even when
     * their MPLS in/out times are identical.  Pairing their raw PTS made the
     * decoder skip the base-view pre-roll and start from a non-random POC,
     * which showed as macroblocks after a BD-J top-menu jump. */
    vlc_tick_t dependent_pts_offset = 0;
    CLPI_CL *main_clpi = bd_get_clpi(p_sys->bluray, clip);
    CLPI_CL *dependent_clpi =
        bd_get_clip_clpi(p_sys->bluray, sub->clip[0].clip_id);
    uint32_t main_start, dependent_start;
    if (pl->play_item[clip].clip != NULL &&
        blurayClpiPresentationStart(main_clpi,
                                   pl->play_item[clip].clip[0].stc_id,
                                   &main_start) &&
        blurayClpiPresentationStart(dependent_clpi,
                                   sub->clip[0].stc_id,
                                   &dependent_start)) {
        dependent_pts_offset =
            ((int64_t)dependent_start - (int64_t)main_start) * CLOCK_FREQ /
            INT64_C(45000);
        msg_Dbg(p_demux, "MVC STC alignment: main=%u dependent=%u, offset=%"PRId64
                " us", main_start, dependent_start, dependent_pts_offset);
    }
    bd_free_clpi(main_clpi);
    bd_free_clpi(dependent_clpi);

    es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_SET_MVC_EXPECTED,
                   true, base_right, dependent_pts_offset);
    msg_Info(p_demux, "Blu-ray 3D MVC extension: %s (%" PRIu64
             " bytes, main %" PRIu64 " bytes)", filename,
             p_sys->i_mvc_clip_size, p_sys->i_mvc_main_size);

    /* The VDA/320M path needs a larger initial dependent-view burst to avoid
     * waiting for its hardware hand-off.  With dual Edge264 on Apple Silicon,
     * a low-bitrate menu can fit hundreds of access units in that burst and
     * overflow the MVC pairing queue before the first base unit arrives.
     * Retain the original one-block PAT/PMT priming on that architecture. */
#if defined(__APPLE__) && defined(__aarch64__)
    /* Even one 6144-byte cluster contains more than 256 tiny dependent-view
     * access units in Albator's menu background. Do not run that parser ahead
     * at all: the first normal demux iteration submits primary and
     * proportional dependent data back-to-back, and both TS streams repeat
     * PAT/PMT often enough to initialize from there. */
    const uint64_t prime = 0;
#else
    const uint64_t prime = MVC_FEED_BURST;
#endif
    if (prime != 0)
        blurayReadMVC(p_demux, __MIN(prime, p_sys->i_mvc_clip_size));
}

static void blurayFeedMVC(demux_t *p_demux, size_t main_bytes)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    if (p_sys->p_mvc_file == NULL || p_sys->i_mvc_main_size == 0)
        return;

    p_sys->i_mvc_main_read += main_bytes;
    uint64_t proportional = (uint64_t)((double)p_sys->i_mvc_main_read *
                                       (double)p_sys->i_mvc_clip_size /
                                       (double)p_sys->i_mvc_main_size);
    if (proportional > p_sys->i_mvc_clip_size)
        proportional = p_sys->i_mvc_clip_size;
    /* The primary and dependent TS parsers are asynchronous.  The byte ratio
     * is needed to keep reading while the primary parser is temporarily
     * behind its input; timestamps alone can otherwise leave the dependent
     * file half-read when bd_read() reaches the end of the play item.  Apply
     * the ratio in bounded bursts and throttle it with the decoded queues. */
    uint64_t target = p_sys->i_mvc_clip_read;

    vlc_tick_t base_date = VLC_TICK_INVALID;
    vlc_tick_t dependent_date = VLC_TICK_INVALID;
    unsigned base_queued = 0, dependent_queued = 0;
    bool have_progress =
        es_out_Control(p_sys->p_out,
                       BLURAY_ES_OUT_CONTROL_GET_MVC_PROGRESS,
                       &base_date, &dependent_date,
                       &base_queued, &dependent_queued) == VLC_SUCCESS;

    /* Do not let the demux thread enqueue an entire primary play item while
     * its chained parser is still behind the faster dependent parser.  Once
     * the parsed dependent queue reaches roughly 1.3 seconds, wait for the
     * already-enqueued primary blocks to consume it.  Without this pressure
     * bd_read_ext() can reach a menu still and stop calling the feeder while
     * tens of seconds of primary data remain inside the chained parser. */
    if (have_progress && base_date != VLC_TICK_INVALID &&
        dependent_queued >= 32 && base_queued == 0)
    {
#if !(defined(__APPLE__) && defined(__aarch64__))
        /* The VDA/GeForce 320M path needs to yield the single primary-parser
         * core while the already-fed dependent parser is far ahead.  Doing
         * this after every 60 KiB block on Apple Silicon hard-caps the whole
         * primary multiplex at roughly 6 MiB/s.  A short high-bitrate peak
         * then holds back the interleaved AC-3 packets even though decoded
         * video remains buffered, producing repeatable HDMI underruns.  The
         * asynchronous parsers have independent cores on Apple Silicon, so
         * query their progress without imposing that legacy throttle. */
        msleep(10000);
#endif
        have_progress =
            es_out_Control(p_sys->p_out,
                           BLURAY_ES_OUT_CONTROL_GET_MVC_PROGRESS,
                           &base_date, &dependent_date,
                           &base_queued, &dependent_queued) == VLC_SUCCESS;
    }

    const bool catching_up = have_progress && base_date != VLC_TICK_INVALID &&
        (dependent_date == VLC_TICK_INVALID ||
         dependent_date < base_date + MVC_TARGET_TIME_LEAD);
    const bool queue_has_room = !have_progress || dependent_queued < 32 ||
                                base_queued > dependent_queued;

    if (queue_has_room &&
        (p_sys->i_mvc_clip_read < proportional || catching_up))
    {
        /* Let the chained parser publish its new queue state between bursts.
         * A single 60 KiB block is about 17 low-bitrate menu pictures on
         * Apple Silicon, already enough to cover normal scheduling jitter. */
#if defined(__APPLE__) && defined(__aarch64__)
        const uint64_t burst_size = BD_READ_SIZE;
#else
        const uint64_t burst_size = MVC_FEED_BURST;
#endif
        uint64_t burst = p_sys->i_mvc_clip_read + burst_size;
        uint64_t cap = proportional;
#if defined(__APPLE__) && defined(__aarch64__)
        /* Do not manufacture a 64 MiB lead on a low-bitrate menu.  One input
         * block primes PAT/PMT and the proportional target supplies the rest
         * in lockstep with bd_read_ext(). */
        if (cap < p_sys->i_mvc_clip_size &&
            p_sys->i_mvc_clip_read == 0)
            cap += __MIN((uint64_t)BD_READ_SIZE,
                         p_sys->i_mvc_clip_size - cap);
#else
        if (UINT64_MAX - cap < MVC_MAX_BYTE_LEAD)
            cap = UINT64_MAX;
        else
            cap += MVC_MAX_BYTE_LEAD;
#endif
        if (cap > p_sys->i_mvc_clip_size)
            cap = p_sys->i_mvc_clip_size;
        if (burst > cap)
            burst = cap;
        target = burst;
    }

    if (catching_up != p_sys->b_mvc_feed_catching_up)
    {
        if (catching_up)
            msg_Dbg(p_demux, "MVC dependent view catch-up: timeline %"PRId64
                    " us, queued %u/%u, byte lead %"PRIu64,
                    dependent_date == VLC_TICK_INVALID ? INT64_MIN :
                    dependent_date - base_date,
                    base_queued, dependent_queued,
                    p_sys->i_mvc_clip_read > proportional ?
                    p_sys->i_mvc_clip_read - proportional : 0);
        else
            msg_Dbg(p_demux, "MVC dependent view recovered its timestamp lead");
        p_sys->b_mvc_feed_catching_up = catching_up;
    }

    while (p_sys->i_mvc_clip_read + BD_CLUSTER_SIZE <= target)
    {
        uint64_t due = target - p_sys->i_mvc_clip_read;
        size_t bytes = due > BD_READ_SIZE ? BD_READ_SIZE : (size_t)due;
        bytes -= bytes % BD_CLUSTER_SIZE;
        if (bytes == 0 || !blurayReadMVC(p_demux, bytes))
            break;
    }
}

static void bluraySeekMVC(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    const int clip = p_sys->i_mvc_clip;
    if (clip < 0)
        return;

    const uint64_t title_time = bd_tell_time(p_sys->bluray);
    uint64_t start = 0, duration = 0;
    vlc_mutex_lock(&p_sys->pl_info_lock);
    if (p_sys->p_clip_info != NULL)
    {
        start = p_sys->p_clip_info->start_time;
        duration = p_sys->p_clip_info->out_time - p_sys->p_clip_info->in_time;
    }
    vlc_mutex_unlock(&p_sys->pl_info_lock);

    blurayOpenMVCClip(p_demux, clip);
    if (p_sys->p_mvc_file == NULL || duration == 0 || title_time <= start)
        return;

    double position = (double)(title_time - start) / (double)duration;
    if (position > 1.0)
        position = 1.0;
    uint64_t offset = (uint64_t)(position * p_sys->i_mvc_clip_size);

    /* A proportional byte offset can be tens of seconds away on a VBR
     * extension stream (Rio starts with a much higher dependent-view
     * bitrate). Find the authored timestamp directly in the dependent
     * transport stream; retain the ratio as a fallback for malformed clips.
     * BLURAY_CLIP_INFO times are 90 kHz while MPLS timestamps are 45 kHz. */
    MPLS_PL *pl = bd_get_title_mpls(p_sys->bluray);
    if (pl != NULL && p_sys->i_mvc_sub_path >= 0 &&
        (unsigned)p_sys->i_mvc_sub_path < pl->ext_sub_count &&
        (unsigned)clip < pl->list_count) {
        MPLS_SUB *path = &pl->ext_sub_path[p_sys->i_mvc_sub_path];
        if ((unsigned)clip < path->sub_playitem_count) {
            MPLS_SUB_PI *sub = &path->sub_play_item[clip];
            if (sub->clip_count != 0 && sub->clip != NULL) {
                uint64_t main_timestamp = pl->play_item[clip].in_time +
                                          (title_time - start) / 2;
                uint64_t dependent_timestamp = sub->in_time;
                if (main_timestamp > sub->sync_pts)
                    dependent_timestamp += main_timestamp - sub->sync_pts;
                if (sub->out_time > sub->in_time &&
                    dependent_timestamp >= sub->out_time)
                    dependent_timestamp = sub->out_time - 1;

                if (dependent_timestamp <= UINT64_MAX / 2 &&
                    blurayFindMVCOffsetByPts(
                        p_sys->p_mvc_file, p_sys->i_mvc_clip_size,
                        dependent_timestamp * 2, &offset)) {
                    msg_Dbg(p_demux, "MVC PES seek timestamp %"PRIu64
                            " to byte %"PRIu64,
                            dependent_timestamp * 2, offset);
                }
            }
        }
    }
    offset -= offset % BD_CLUSTER_SIZE;
    if (offset > p_sys->i_mvc_clip_read &&
        p_sys->p_mvc_file->seek(p_sys->p_mvc_file, offset, SEEK_SET) >= 0)
    {
        /* blurayOpenMVCClip() primes PAT/PMT from byte zero. Seeking only the
         * file used to leave those first dependent-view access units queued
         * in the chained TS demuxer; after a BD-J playlist jump they could be
         * hundreds of seconds away from the new base-view timestamp. Start a
         * fresh parser at the packet-aligned offset so no pre-seek PES or
         * timestamp state can leak into the new MVC pair. PAT/PMT tables are
         * repeated in the transport stream and are picked up by the prime
         * read below. */
        vlc_demux_chained_Delete(p_sys->p_mvc_parser);
        p_sys->p_mvc_parser = vlc_demux_chained_New(VLC_OBJECT(p_demux), "ts",
                                                     p_sys->p_mvc_out);
        if (p_sys->p_mvc_parser == NULL)
        {
            msg_Err(p_demux, "cannot recreate Blu-ray MVC extension demuxer after seek");
            blurayCloseMVCClip(p_demux);
            return;
        }

        es_out_Control(p_sys->p_out,
                       BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
        p_sys->i_mvc_clip_read = offset;
        /* Resume the byte-ratio feeder from the dependent offset we actually
         * selected. Keeping the old time-ratio main counter can make its
         * proportional target precede the new file position; no more MVC data
         * is then submitted until the base parser has run many seconds ahead. */
        p_sys->i_mvc_main_read =
            (uint64_t)((double)offset * (double)p_sys->i_mvc_main_size /
                       (double)p_sys->i_mvc_clip_size);
        const uint64_t remaining = p_sys->i_mvc_clip_size - offset;
        if (remaining != 0)
            blurayReadMVC(p_demux, __MIN((uint64_t)BD_READ_SIZE, remaining));
        msg_Dbg(p_demux, "MVC extension seek to %.3f (%" PRIu64 " bytes)",
                position, offset);
    }
}

static void blurayTopMenuRefused(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    vout_thread_t *vout = input_GetVout(p_demux->p_input);
    if (vout == NULL)
        return;

    const char *message = p_sys->i_uo_mask & BLURAY_UO_MENU_CALL
                        ? _("Operation prohibited by the disc")
                        : _("Top Menu is not available");
    /* Use an explicit, long-lived centred message. The default helper is
     * deliberately brief and bottom-aligned; the Legacy controller can cover
     * it before the user sees the refusal. */
    vout_OSDText(vout, VOUT_SPU_CHANNEL_OSD, 0, 3 * CLOCK_FREQ, message);
    vlc_object_release(vout);
}

/*****************************************************************************
 * bluraySetTitle: select new BD title
 *****************************************************************************/
static int bluraySetTitle(demux_t *p_demux, int i_title)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if (p_sys->b_menu) {
        int result;
        if (i_title <= 0) {
            msg_Dbg(p_demux, "Playing TopMenu Title");
            if (p_sys->i_uo_mask & BLURAY_UO_MENU_CALL) {
                blurayTopMenuRefused(p_demux);
                return VLC_EGENERIC;
            }
            result = bd_menu_call(p_sys->bluray, -1);
        } else if (i_title >= (int)p_sys->i_title - 1) {
            msg_Dbg(p_demux, "Playing FirstPlay Title");
            result = bd_play_title(p_sys->bluray, BLURAY_TITLE_FIRST_PLAY);
        } else {
            msg_Dbg(p_demux, "Playing Title %i", i_title);
            result = bd_play_title(p_sys->bluray, i_title);
        }

        if (result == 0) {
            msg_Err(p_demux, "cannot play bd title '%d'", i_title);
            if (i_title <= 0)
                blurayTopMenuRefused(p_demux);
            return VLC_EGENERIC;
        }

        return VLC_SUCCESS;
    }

    /* Looking for the main title, ie the longest duration */
    if (i_title < 0)
        i_title = p_sys->i_longest_title;
    else if ((unsigned)i_title > p_sys->i_title)
        return VLC_EGENERIC;

    msg_Dbg(p_demux, "Selecting Title %i", i_title);

    if (bd_select_title(p_sys->bluray, i_title) == 0) {
        msg_Err(p_demux, "cannot select bd title '%d'", i_title);
        return VLC_EGENERIC;
    }

    return VLC_SUCCESS;
}

#if BLURAY_VERSION < BLURAY_VERSION_CODE(0,9,2)
#  define BLURAY_AUDIO_STREAM 0
#endif

static void blurayOnUserStreamSelection(demux_t *p_demux, int i_pid)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    vlc_mutex_lock(&p_sys->pl_info_lock);

    if(i_pid == -AUDIO_ES)
        bd_select_stream(p_sys->bluray, BLURAY_AUDIO_STREAM, 0, 0);
    else if(i_pid == -SPU_ES)
        bd_select_stream(p_sys->bluray, BLURAY_PG_TEXTST_STREAM, 0, 0);
    else if (p_sys->p_clip_info)
    {
        if ((i_pid & 0xff00) == 0x1100) {
            bool b_in_playlist = false;
            // audio
            for (int i_id = 0; i_id < p_sys->p_clip_info->audio_stream_count; i_id++) {
                if (i_pid == p_sys->p_clip_info->audio_streams[i_id].pid) {
                    bd_select_stream(p_sys->bluray, BLURAY_AUDIO_STREAM, i_id + 1, 1);

                    if(!p_sys->b_menu)
                        bd_set_player_setting_str(p_sys->bluray, BLURAY_PLAYER_SETTING_AUDIO_LANG,
                                  (const char *) p_sys->p_clip_info->audio_streams[i_id].lang);
                    b_in_playlist = true;
                    break;
                }
            }
            if(!b_in_playlist && !p_sys->b_menu)
            {
                /* Without menu, the selected playlist might not be correct and only
                   exposing a subset of PID, although same length */
                msg_Warn(p_demux, "Incorrect playlist for menuless track, forcing");
                es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_SET_ES_BY_PID,
                               BD_EVENT_AUDIO_STREAM, i_pid);
            }
        } else if ((i_pid & 0xff00) == 0x1200 || i_pid == 0x1800) {
            bool b_in_playlist = false;
            // subtitle
            for (int i_id = 0; i_id < p_sys->p_clip_info->pg_stream_count; i_id++) {
                if (i_pid == p_sys->p_clip_info->pg_streams[i_id].pid) {
                    bd_select_stream(p_sys->bluray, BLURAY_PG_TEXTST_STREAM, i_id + 1, 1);
                    if(!p_sys->b_menu)
                        bd_set_player_setting_str(p_sys->bluray, BLURAY_PLAYER_SETTING_PG_LANG,
                                   (const char *) p_sys->p_clip_info->pg_streams[i_id].lang);
                    b_in_playlist = true;
                    break;
                }
            }
            if(!b_in_playlist && !p_sys->b_menu)
            {
                msg_Warn(p_demux, "Incorrect playlist for menuless track, forcing");
                es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_SET_ES_BY_PID,
                               BD_EVENT_PG_TEXTST_STREAM, i_pid);
            }
        }
    }

    vlc_mutex_unlock(&p_sys->pl_info_lock);
}

/*****************************************************************************
 * blurayControl: handle the controls
 *****************************************************************************/
static int blurayControl(demux_t *p_demux, int query, va_list args)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    bool     *pb_bool;
    int64_t  *pi_64;

    switch (query) {
    case DEMUX_CAN_SEEK:
    case DEMUX_CAN_PAUSE:
    case DEMUX_CAN_CONTROL_PACE:
         pb_bool = va_arg(args, bool *);
         *pb_bool = true;
         break;

    case DEMUX_GET_PTS_DELAY:
        pi_64 = va_arg(args, int64_t *);
        *pi_64 = INT64_C(1000) * var_InheritInteger(p_demux, "disc-caching");
#if defined(__arm64__) || defined(__aarch64__)
        /* CoreAudio must tear down and reopen the encoded HDMI stream when a
         * Blu-ray play item switches passthrough codec (Hopper changes from
         * AC-3 to DTS after its first eight seconds).  The stock 300 ms disc
         * cache is almost entirely consumed by that device reconfiguration,
         * leaving only about 100 ms scheduled and causing immediate
         * underruns for the remainder of the clip.  Keep one second queued
         * on Apple Silicon so both encoded formats survive natural M2TS
         * boundaries without changing the user's caching preference when it
         * is already larger. */
        if (*pi_64 < VLC_TICK_FROM_SEC(1))
            *pi_64 = VLC_TICK_FROM_SEC(1);
#endif
        break;

    case DEMUX_SET_PAUSE_STATE:
    {
#ifdef BLURAY_RATE_NORMAL
        bool b_paused = (bool)va_arg(args, int);
        if (bd_set_rate(p_sys->bluray, BLURAY_RATE_NORMAL * (!b_paused)) < 0) {
            return VLC_EGENERIC;
        }
#endif
        break;
    }
    case DEMUX_SET_ES:
    {
        int i_id = va_arg(args, int);
        blurayOnUserStreamSelection(p_demux, i_id);
        break;
    }
    case DEMUX_SET_TITLE:
    {
        int i_title = va_arg(args, int);
        if (bluraySetTitle(p_demux, i_title) != VLC_SUCCESS) {
            /* make sure GUI restores the old setting in title menu ... */
            p_demux->info.i_update |= INPUT_UPDATE_TITLE | INPUT_UPDATE_SEEKPOINT;
            return VLC_EGENERIC;
        }
        blurayRestartParser(p_demux, true, false);
        notifyDiscontinuityToParser(p_sys);
        p_sys->b_draining = false;
        es_out_Control(p_demux->out, ES_OUT_RESET_PCR);
        es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
        break;
    }
    case DEMUX_SET_SEEKPOINT:
    {
        int i_chapter = va_arg(args, int);
        bd_seek_chapter(p_sys->bluray, i_chapter);
        p_sys->b_user_seek_preroll = true;
        p_sys->i_user_seek_preroll = FROM_SCALE_NZ(bd_tell_time(p_sys->bluray));
        blurayRestartParser(p_demux, true, false);
        notifyDiscontinuityToParser(p_sys);
        p_sys->b_draining = false;
        es_out_Control(p_demux->out, ES_OUT_RESET_PCR);
        p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;
        break;
    }

    case DEMUX_GET_TITLE_INFO:
    {
        input_title_t ***ppp_title = va_arg(args, input_title_t***);
        int *pi_int             = va_arg(args, int *);
        int *pi_title_offset    = va_arg(args, int *);
        int *pi_chapter_offset  = va_arg(args, int *);

        /* */
        *pi_title_offset   = 0;
        *pi_chapter_offset = 0;

        /* Duplicate local title infos */
        *pi_int = 0;
        *ppp_title = vlc_alloc(p_sys->i_title, sizeof(input_title_t *));
        if(!*ppp_title)
            return VLC_EGENERIC;
        for (unsigned int i = 0; i < p_sys->i_title; i++)
        {
            input_title_t *p_dup = vlc_input_title_Duplicate(p_sys->pp_title[i]);
            if(p_dup)
                (*ppp_title)[(*pi_int)++] = p_dup;
        }

        return VLC_SUCCESS;
    }

    case DEMUX_GET_LENGTH:
    {
        int64_t *pi_length = va_arg(args, int64_t *);
        if(p_demux->info.i_title < (int) p_sys->i_title &&
           (CURRENT_TITLE->i_flags & INPUT_TITLE_INTERACTIVE))
                return VLC_EGENERIC;
        *pi_length = p_demux->info.i_title < (int) p_sys->i_title ? CUR_LENGTH : 0;
        return VLC_SUCCESS;
    }
    case DEMUX_SET_TIME:
    {
        int64_t i_time = va_arg(args, int64_t);
        p_sys->b_user_seek_preroll = true;
        p_sys->i_user_seek_preroll = i_time;
        bd_seek_time(p_sys->bluray, TO_SCALE_NZ(i_time));
        blurayRestartParser(p_demux, true, true);
        notifyDiscontinuityToParser(p_sys);
        p_sys->b_draining = false;
        es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
        return VLC_SUCCESS;
    }
    case DEMUX_GET_TIME:
    {
        int64_t *pi_time = va_arg(args, int64_t *);
        if( p_demux->info.i_title < (int) p_sys->i_title &&
           (CURRENT_TITLE->i_flags & INPUT_TITLE_INTERACTIVE))
                return VLC_EGENERIC;
        *pi_time = FROM_SCALE_NZ(bd_tell_time(p_sys->bluray));
        return VLC_SUCCESS;
    }

    case DEMUX_GET_POSITION:
    {
        double *pf_position = va_arg(args, double *);
        if(p_demux->info.i_title < (int) p_sys->i_title &&
           (CURRENT_TITLE->i_flags & INPUT_TITLE_INTERACTIVE))
                return VLC_EGENERIC;
        *pf_position = p_demux->info.i_title < (int) p_sys->i_title && CUR_LENGTH > 0 ?
                      (double)FROM_SCALE_NZ(bd_tell_time(p_sys->bluray))/CUR_LENGTH : 0.0;
        return VLC_SUCCESS;
    }
    case DEMUX_SET_POSITION:
    {
        double f_position = va_arg(args, double);
        const vlc_tick_t i_time = f_position * CUR_LENGTH;
        p_sys->b_user_seek_preroll = true;
        p_sys->i_user_seek_preroll = i_time;
        bd_seek_time(p_sys->bluray, TO_SCALE_NZ(i_time));
        blurayRestartParser(p_demux, true, true);
        notifyDiscontinuityToParser(p_sys);
        p_sys->b_draining = false;
        es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
        return VLC_SUCCESS;
    }

    case DEMUX_GET_META:
    {
        vlc_meta_t *p_meta = va_arg(args, vlc_meta_t *);
        const META_DL *meta = p_sys->p_meta;
        if (meta == NULL)
            return VLC_EGENERIC;

        if (!EMPTY_STR(meta->di_name)) vlc_meta_SetTitle(p_meta, meta->di_name);

        if (!EMPTY_STR(meta->language_code)) vlc_meta_AddExtra(p_meta, "Language", meta->language_code);
        if (!EMPTY_STR(meta->filename)) vlc_meta_AddExtra(p_meta, "Filename", meta->filename);
        if (!EMPTY_STR(meta->di_alternative)) vlc_meta_AddExtra(p_meta, "Alternative", meta->di_alternative);

        // if (meta->di_set_number > 0) vlc_meta_SetTrackNum(p_meta, meta->di_set_number);
        // if (meta->di_num_sets > 0) vlc_meta_AddExtra(p_meta, "Discs numbers in Set", meta->di_num_sets);

        if (p_sys->i_cover_idx >= 0 && p_sys->i_cover_idx < p_sys->i_attachments) {
            char psz_url[128];
            snprintf( psz_url, sizeof(psz_url), "attachment://%s",
                      p_sys->attachments[p_sys->i_cover_idx]->psz_name );
            vlc_meta_Set( p_meta, vlc_meta_ArtworkURL, psz_url );
        }
        else if (meta->thumb_count > 0 && meta->thumbnails && p_sys->psz_bd_path) {
            char *psz_thumbpath;
            if (asprintf(&psz_thumbpath, "%s" DIR_SEP "BDMV" DIR_SEP "META" DIR_SEP "DL" DIR_SEP "%s",
                          p_sys->psz_bd_path, meta->thumbnails[0].path) > -1) {
                char *psz_thumburl = vlc_path2uri(psz_thumbpath, "file");
                free(psz_thumbpath);
                if (unlikely(psz_thumburl == NULL))
                    return VLC_ENOMEM;

                vlc_meta_SetArtURL(p_meta, psz_thumburl);
                free(psz_thumburl);
            }
        }

        return VLC_SUCCESS;
    }

    case DEMUX_GET_ATTACHMENTS:
    {
        input_attachment_t ***ppp_attach =
            va_arg(args, input_attachment_t ***);
        int *pi_int = va_arg(args, int *);

        if (p_sys->i_attachments <= 0)
            return VLC_EGENERIC;

        *pi_int = 0;
        *ppp_attach = vlc_alloc(p_sys->i_attachments, sizeof(input_attachment_t *));
        if(!*ppp_attach)
            return VLC_EGENERIC;
        for (int i = 0; i < p_sys->i_attachments; i++)
        {
            input_attachment_t *p_dup = vlc_input_attachment_Duplicate(p_sys->attachments[i]);
            if(p_dup)
                (*ppp_attach)[(*pi_int)++] = p_dup;
        }
        return VLC_SUCCESS;
    }

    case DEMUX_NAV_ACTIVATE:
        if (p_sys->b_popup_available && !p_sys->b_menu_open) {
            return sendKeyEvent(p_sys, BD_VK_POPUP);
        }
        return sendKeyEvent(p_sys, BD_VK_ENTER);
    case DEMUX_NAV_UP:
        return sendKeyEvent(p_sys, BD_VK_UP);
    case DEMUX_NAV_DOWN:
        return sendKeyEvent(p_sys, BD_VK_DOWN);
    case DEMUX_NAV_LEFT:
        return sendKeyEvent(p_sys, BD_VK_LEFT);
    case DEMUX_NAV_RIGHT:
        return sendKeyEvent(p_sys, BD_VK_RIGHT);
    case DEMUX_NAV_POPUP:
        return sendKeyEvent(p_sys, BD_VK_POPUP);
    case DEMUX_NAV_MENU:
        if (p_sys->b_menu) {
            if (p_sys->i_uo_mask & BLURAY_UO_MENU_CALL) {
                msg_Dbg(p_demux, "Top Menu call prohibited by the disc");
                blurayTopMenuRefused(p_demux);
                return VLC_EGENERIC;
            }
            if (bd_menu_call(p_sys->bluray, -1) == 1) {
                p_demux->info.i_update |= INPUT_UPDATE_TITLE | INPUT_UPDATE_SEEKPOINT;
                return VLC_SUCCESS;
            }
            msg_Err(p_demux, "Can't select Top Menu title");
            blurayTopMenuRefused(p_demux);
            return VLC_EGENERIC;
        }
        return VLC_EGENERIC;

    case DEMUX_CAN_RECORD:
    case DEMUX_GET_FPS:
    case DEMUX_SET_GROUP:
    case DEMUX_HAS_UNSUPPORTED_META:
    default:
        return VLC_EGENERIC;
    }
    return VLC_SUCCESS;
}

/*****************************************************************************
 * libbluray event handling
 *****************************************************************************/
static void writeTsPacketWDiscontinuity( uint8_t *p_buf, uint16_t i_pid,
                                         const uint8_t *p_payload, uint8_t i_payload )
{
    uint8_t ts_header[] = {
        0x00, 0x00, 0x00, 0x00,                /* TP extra header (ATC) */
        0x47,
        0x40 | ((i_pid & 0x1f00) >> 8), i_pid & 0xFF, /* PUSI + PID */
        i_payload ? 0x30 : 0x20,               /* adaptation field, payload / no payload */
        192 - (4 + 5) - i_payload,             /* adaptation field length */
        0x82,                                  /* af: discontinuity indicator + priv data */
        0x0E,                                  /* priv data size */
         'V',  'L',  'C',  '_',
         'D',  'I',  'S',  'C',  'O',  'N',  'T',  'I',  'N',  'U',
    };

    memcpy( p_buf, ts_header, sizeof(ts_header) );
    memset( &p_buf[sizeof(ts_header)], 0xFF, 192 - sizeof(ts_header) - i_payload );
    if( i_payload )
        memcpy( &p_buf[192 - i_payload], p_payload, i_payload );
}

static void notifyStreamsDiscontinuity( vlc_demux_chained_t *p_parser,
                                        const BLURAY_STREAM_INFO *p_sinfo, size_t i_sinfo )
{
    for( size_t i=0; i< i_sinfo; i++ )
    {
        const uint16_t i_pid = p_sinfo[i].pid;

        block_t *p_block = block_Alloc(192);
        if (!p_block)
            return;

        writeTsPacketWDiscontinuity( p_block->p_buffer, i_pid, NULL, 0 );

        vlc_demux_chained_Send(p_parser, p_block);
    }
}

#define DONOTIFY(memb) notifyStreamsDiscontinuity( p_sys->p_parser, p_clip->memb##_streams, \
                                                   p_clip->memb##_stream_count )

static void notifyDiscontinuityToParser( demux_sys_t *p_sys )
{
    const BLURAY_CLIP_INFO *p_clip = p_sys->p_clip_info;
    if( p_clip )
    {
        DONOTIFY(audio);
        DONOTIFY(video);
        DONOTIFY(pg);
        DONOTIFY(ig);
        DONOTIFY(sec_audio);
        DONOTIFY(sec_video);
    }
}

#undef DONOTIFY

static void streamFlush( demux_sys_t *p_sys )
{
    /*
     * MPEG-TS demuxer does not flush last video frame if size of PES packet is unknown.
     * Packet is flushed only when TS packet with PUSI flag set is received.
     *
     * Fix this by emitting (video) ts packet with PUSI flag set.
     * Add video sequence end code to payload so that also video decoder is flushed.
     * Set PES packet size in the payload so that it will be sent to decoder immediately.
     */

    if (p_sys->b_flushed)
        return;

    block_t *p_block = block_Alloc(192);
    if (!p_block)
        return;

    bd_stream_type_e i_coding_type;

    /* set correct sequence end code */
    vlc_mutex_lock(&p_sys->pl_info_lock);
    if (p_sys->p_clip_info != NULL)
        i_coding_type = p_sys->p_clip_info->video_streams[0].coding_type;
    else
        i_coding_type = 0;
    vlc_mutex_unlock(&p_sys->pl_info_lock);

    uint8_t i_eos;
    switch( i_coding_type )
    {
        case BLURAY_STREAM_TYPE_VIDEO_MPEG1:
        case BLURAY_STREAM_TYPE_VIDEO_MPEG2:
        default:
            i_eos = 0xB7; /* MPEG2 sequence end */
            break;
        case BLURAY_STREAM_TYPE_VIDEO_VC1:
        case BLURAY_STREAM_TYPE_VIDEO_H264:
            i_eos = 0x0A; /* VC1 / H.264 sequence end */
            break;
        case BD_STREAM_TYPE_VIDEO_HEVC:
            i_eos = 0x48; /* HEVC sequence end NALU */
            break;
    }

    uint8_t seq_end_pes[] = {
        0x00, 0x00, 0x01, 0xe0, 0x00, 0x07, 0x80, 0x00, 0x00,  /* PES header */
        0x00, 0x00, 0x01, i_eos,                               /* PES payload: sequence end */
        0x00, /* 2nd byte for HEVC NAL, pads others */
    };

    writeTsPacketWDiscontinuity( p_block->p_buffer, 0x1011, seq_end_pes, sizeof(seq_end_pes) );

    vlc_demux_chained_Send(p_sys->p_parser, p_block);
    p_sys->b_flushed = true;
}

static void blurayResetStillImage( demux_t *p_demux )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if (p_sys->i_still_end_time != STILL_IMAGE_NOT_SET) {
        p_sys->i_still_end_time = STILL_IMAGE_NOT_SET;

        vout_thread_t *vout = input_GetVout(p_demux->p_input);
        if (vout != NULL) {
            vout_ChangeStaticFrameHold(vout, false);
            vlc_object_release(vout);
        }

        blurayRestartParser(p_demux, false, false);
        es_out_Control(p_demux->out, ES_OUT_RESET_PCR);
    }
}

static void blurayStillImage( demux_t *p_demux, unsigned i_timeout )
{
    demux_sys_t *p_sys = p_demux->p_sys;

    /* time period elapsed ? */
    if (p_sys->i_still_end_time != STILL_IMAGE_NOT_SET &&
        p_sys->i_still_end_time != STILL_IMAGE_INFINITE &&
        p_sys->i_still_end_time <= mdate()) {
        msg_Dbg(p_demux, "Still image end");
        bd_read_skip_still(p_sys->bluray);

        blurayResetStillImage(p_demux);
        return;
    }

    /* show last frame as still image */
    if (p_sys->i_still_end_time == STILL_IMAGE_NOT_SET) {
        if (i_timeout) {
            msg_Dbg(p_demux, "Still image (%d seconds)", i_timeout);
            p_sys->i_still_end_time = mdate() + i_timeout * CLOCK_FREQ;
        } else {
            msg_Dbg(p_demux, "Still image (infinite)");
            p_sys->i_still_end_time = STILL_IMAGE_INFINITE;
        }

        /* Flush the final unterminated PES for ordinary still pictures.  Do
         * not do this for an HDMV interactive plane: the synthetic H.264 EOS
         * retires the decoder/vout before blurayHandleOverlays() runs later
         * in this demux iteration.  With no following picture an infinite
         * menu still can never acquire another vout, so its decoded buttons
         * remain permanently ToDisplay (Up's language menu is one example).
         * Keeping the existing decoder alive also keeps the real menu
         * background instead of replacing it with a dummy black picture.
         * BD-J stills retain the flush that Rio needs for its pre-menu Xlet. */
        bool b_keep_hdmv_vout = false;
        if (!blurayIsBdjTitle(p_demux)) {
            vlc_mutex_lock(&p_sys->bdj_overlay_lock);
            for (int i = 0; i < MAX_OVERLAY; ++i) {
                if (p_sys->p_overlays[i] != NULL) {
                    b_keep_hdmv_vout = true;
                    break;
                }
            }
            vlc_mutex_unlock(&p_sys->bdj_overlay_lock);
        }

        if (b_keep_hdmv_vout) {
            msg_Dbg(p_demux, "Keeping video output alive for HDMV menu still");
            /* A frame-packed HDMV menu can consist of one very short MVC
             * access unit.  Both TS files have been read by the time the
             * STILL event arrives, but the unterminated final PES can still
             * be sitting in the asynchronous parser/decoder.  Without the
             * normal EOS flush no first picture ever reaches the retained
             * vout: the IG buttons are decoded, yet the window stays black.
             * The Blu-ray session vout hold now preserves that output across
             * this targeted flush, so draining MVC here is safe. */
            streamFlush(p_sys);
        } else {
            /* The synchronous decoder selected for one-frame BD-J stills
             * below delivers their real background before the ARGB plane is
             * attached. Do not arm the HDMV last-frame policy here: when the
             * vout is recycled it still contains the preceding disc's frame
             * (Cars 2's castle while opening Cars 3), which that policy would
             * deliberately preserve across this flush. */
            streamFlush(p_sys);
        }

        /* stop buffering */
        bool b_empty;
        es_out_Control( p_demux->out, ES_OUT_GET_EMPTY, &b_empty );
    }

    /* avoid busy loops (read returns no data) */
    msleep( 40000 );
}

static void blurayOnStreamSelectedEvent(demux_t *p_demux, uint32_t i_type, uint32_t i_id)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    int i_pid = -1;

    /* The param we get is the real stream id, not an index, ie. it starts from 1 */
    i_id--;

    if (i_type == BD_EVENT_AUDIO_STREAM) {
        i_pid = blurayGetStreamPID(p_sys, i_type, i_id);
    } else if (i_type == BD_EVENT_PG_TEXTST_STREAM) {
        i_pid = blurayGetStreamPID(p_sys, i_type, i_id);
    }

    if (i_pid > 0)
    {
        es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_SET_ES_BY_PID, (int)i_type, i_pid);
        if (i_type == BD_EVENT_PG_TEXTST_STREAM)
            /* apply the display flag: a hidden PG stream stays selected in
             * forced-captions-only mode (or is plainly deselected when
             * bluray-forced-subs is off) */
            es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_SET_SPU_VISIBILITY,
                           (int)p_sys->b_spu_enable);
    }
}

/*****************************************************************************
 * HDR / colour attributes declared by the playlist (libbluray >= 1.5.0)
 *****************************************************************************
 * The BDMV stream entry carries these only for HEVC (coding type 0x24), that
 * is on UHD discs; everywhere else libbluray leaves them zeroed, which reads
 * exactly like "SDR, unspecified colour space". So the guard is on the coding
 * type, not on the values.
 *
 * They are published as information and deliberately NOT pushed into
 * es_format_t. The HEVC elementary stream signals its own transfer function
 * and primaries in the VUI and the mastering-display SEI, the decoders already
 * act on that, and a playlist declaration that disagreed with the stream would
 * make the picture worse rather than better. What this adds is the disc's own
 * statement of what it holds, which belongs in "Media Information" -- where
 * every interface shows it without any interface-side code.
 *****************************************************************************/
#if BLURAY_VERSION >= BLURAY_VERSION_CODE(1,5,0)

#define BD_INFO_CAT N_("Blu-ray")

static void blurayUpdateVideoInfo(demux_t *p_demux, const BLURAY_TITLE_INFO *info)
{
    input_thread_t *p_input = p_demux->p_input;
    if (p_input == NULL)
        return;

    input_Control(p_input, INPUT_DEL_INFO, vlc_gettext(BD_INFO_CAT), NULL);

    if (info == NULL || info->clip_count == 0)
        return;

    const BLURAY_CLIP_INFO *p_clip = &info->clips[0];
    if (p_clip->video_stream_count == 0)
        return;

    const BLURAY_STREAM_INFO *p_video = &p_clip->video_streams[0];
    if (p_video->coding_type != BD_STREAM_TYPE_VIDEO_HEVC)
        return;

    const char *psz_range;
    switch (p_video->dynamic_range_type) {
        case BLURAY_DYNAMIC_RANGE_SDR:          psz_range = "SDR";           break;
        case BLURAY_DYNAMIC_RANGE_HDR10:        psz_range = "HDR10";         break;
        case BLURAY_DYNAMIC_RANGE_DOLBY_VISION: psz_range = "Dolby Vision";  break;
        default:                                psz_range = NULL;            break;
    }
    if (psz_range != NULL)
        input_Control(p_input, INPUT_ADD_INFO, vlc_gettext(BD_INFO_CAT),
                      _("Dynamic range"), "%s", psz_range);

    const char *psz_space;
    switch (p_video->color_space) {
        case BLURAY_COLOR_SPACE_BT709:  psz_space = "BT.709";  break;
        case BLURAY_COLOR_SPACE_BT2020: psz_space = "BT.2020"; break;
        default:                        psz_space = NULL;      break;
    }
    if (psz_space != NULL)
        input_Control(p_input, INPUT_ADD_INFO, vlc_gettext(BD_INFO_CAT),
                      _("Color space"), "%s", psz_space);

    if (p_video->hdr_plus_flag)
        input_Control(p_input, INPUT_ADD_INFO, vlc_gettext(BD_INFO_CAT),
                      "HDR10+", "%s", _("Yes"));

    if (p_clip->dv_stream_count > 0)
        input_Control(p_input, INPUT_ADD_INFO, vlc_gettext(BD_INFO_CAT),
                      _("Dolby Vision tracks"), "%u", p_clip->dv_stream_count);

    if (info->sdr_conversion_notification_flag)
        input_Control(p_input, INPUT_ADD_INFO, vlc_gettext(BD_INFO_CAT),
                      _("SDR conversion notice"), "%s", _("Yes"));

    /* cr_flag is the one attribute libbluray exposes without naming: its own
     * dump tools print it as a raw byte and the header carries no comment, so
     * there is nothing truthful to label it with in a user-facing panel.
     * Logged instead of guessed. */
    msg_Dbg(p_demux, "playlist video attributes: dynamic_range=%u color_space=%u "
            "cr_flag=%u hdr_plus=%u dv_streams=%u",
            p_video->dynamic_range_type, p_video->color_space,
            p_video->cr_flag, p_video->hdr_plus_flag, p_clip->dv_stream_count);
}
#else
# define blurayUpdateVideoInfo(a, b) do { (void)(a); (void)(b); } while (0)
#endif

static void blurayUpdatePlaylist(demux_t *p_demux, unsigned i_playlist)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    blurayCloseMVCClip(p_demux);
    p_sys->i_mvc_sub_path = -1;
    p_sys->i_current_playitem = -1;
    blurayRestartParser(p_demux, true, false);

    /* read title info and init some values */
    if (!p_sys->b_menu)
        p_demux->info.i_title = bd_get_current_title(p_sys->bluray);
    p_demux->info.i_seekpoint = 0;
    p_demux->info.i_update |= INPUT_UPDATE_TITLE | INPUT_UPDATE_SEEKPOINT;

    BLURAY_TITLE_INFO *p_title_info = bd_get_playlist_info(p_sys->bluray, i_playlist, 0);
    if (p_title_info) {
        blurayUpdateTitleInfo(p_sys->pp_title[p_demux->info.i_title], p_title_info);
        if (p_sys->b_menu)
            p_demux->info.i_update |= INPUT_UPDATE_TITLE_LIST;
    }
    blurayUpdateVideoInfo(p_demux, p_title_info);
    setTitleInfo(p_sys, p_title_info);

    MPLS_PL *pl = bd_get_title_mpls(p_sys->bluray);
    if (pl != NULL)
    {
        for (unsigned i = 0; i < pl->ext_sub_count; ++i)
        {
            if (pl->ext_sub_path[i].type == mpls_sub_path_ss_video &&
                pl->ext_sub_path[i].sub_playitem_count == pl->list_count)
            {
                p_sys->i_mvc_sub_path = i;
                msg_Info(p_demux, "Blu-ray stereoscopic MVC sub-path %u "
                         "detected (base view is %s eye)", i,
                         p_title_info != NULL &&
                         p_title_info->mvc_base_view_r_flag ? "right" : "left");
                break;
            }
        }
    }

    blurayResetStillImage(p_demux);
}

static void blurayOnClipUpdate(demux_t *p_demux, uint32_t clip)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    bool b_short_bdj_still = false;

    vlc_mutex_lock(&p_sys->pl_info_lock);

    p_sys->p_clip_info = NULL;

    if (p_sys->p_pl_info && clip < p_sys->p_pl_info->clip_count) {

        p_sys->p_clip_info = &p_sys->p_pl_info->clips[clip];

        /* VideoToolbox can lose an H.264 stream made of a single still frame
         * while its asynchronous session is being configured and drained.
         * BD-J language screens commonly use exactly that construction. */
        b_short_bdj_still = p_sys->p_clip_info->still_mode != 0 &&
                            p_sys->p_clip_info->video_stream_count > 0 &&
                            p_sys->p_clip_info->video_streams[0].coding_type ==
                                BLURAY_STREAM_TYPE_VIDEO_H264;

    /* Let's assume a single video track for now.
     * This may brake later, but it's enough for now.
     */
        assert(p_sys->p_clip_info->video_stream_count >= 1);
    }

    CLPI_CL *clpi = bd_get_clpi(p_sys->bluray, clip);
    if (clpi != NULL) {
        if (clpi->clip.application_type != p_sys->clip_application_type) {
            if(p_sys->clip_application_type == BD_CLIP_APP_TYPE_TS_MAIN_PATH_TIMED_SLIDESHOW ||
               clpi->clip.application_type == BD_CLIP_APP_TYPE_TS_MAIN_PATH_TIMED_SLIDESHOW)
                blurayRestartParser(p_demux, false, false);

            if(clpi->clip.application_type == BD_CLIP_APP_TYPE_TS_MAIN_PATH_TIMED_SLIDESHOW)
                es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_ENABLE_LOW_DELAY);
            else
                es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_DISABLE_LOW_DELAY);
        }
        bd_free_clpi(clpi);
    } else {
        msg_Dbg(p_demux, "current Blu-ray clip metadata unavailable during title transition");
    }

    vlc_mutex_unlock(&p_sys->pl_info_lock);

    /* The same one-frame loss occurs in an HDMV still after an MVC-to-mono
     * menu handoff. Keep VideoToolbox for normal H.264 clips, but use the
     * synchronous decoder for every authored one-picture menu. */
    bluraySetBdjStillDecoder(p_demux,
                             b_short_bdj_still && p_sys->b_menu);

    blurayResetStillImage(p_demux);
}

static void bluraySetBdjStillDecoder(demux_t *p_demux, bool enable)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    if (enable == p_sys->b_bdj_still_codec_override)
        return;

    if (enable) {
        p_sys->b_had_input_codec =
            var_Type(p_demux->p_input, "codec") != 0;
        p_sys->psz_codec_before_bdj_still =
            var_InheritString(p_demux->p_input, "codec");
        var_Create(p_demux->p_input, "codec", VLC_VAR_STRING);
        var_SetString(p_demux->p_input, "codec", "avcodec");
        p_sys->b_bdj_still_codec_override = true;
        p_sys->b_bdj_still_codec_restart_pending = true;
        msg_Dbg(p_demux, "using synchronous decoder for BD-J still frame");
        return;
    }

    if (p_sys->b_had_input_codec)
        var_SetString(p_demux->p_input, "codec",
                      p_sys->psz_codec_before_bdj_still != NULL
                          ? p_sys->psz_codec_before_bdj_still : "");
    else
        var_Destroy(p_demux->p_input, "codec");

    free(p_sys->psz_codec_before_bdj_still);
    p_sys->psz_codec_before_bdj_still = NULL;
    p_sys->b_bdj_still_codec_override = false;
    p_sys->b_bdj_still_codec_restart_pending = true;
    msg_Dbg(p_demux, "restored preferred decoder after BD-J still frame");
}

/*
 * The look-ahead decode cache (video-cache-mb) is worth having on a Blu-ray --
 * these are the highest bitrates the player ever sees -- but only while a title
 * is actually playing. It used to be inhibited for the whole session, which
 * threw the feature away on the one source that needs it most.
 *
 * What has to be avoided is a fill episode opening over material that cannot
 * feed it: menus and stills produce roughly one picture at a time, so the gate
 * would sit waiting for a target it can never reach while the user stares at a
 * frozen menu. dvdnav solves this per domain (see DvdnavCacheInhibitUpdate);
 * the same three conditions apply here.
 *
 * es_out is only told on a change, so this is cheap to call per demux
 * iteration.
 */
static void blurayCacheInhibitUpdate(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    /* BD_EVENT_MENU does NOT mean "the user is sitting in a menu", and
     * taking it at face value inhibited the look-ahead cache for entire
     * episodes.
     *
     * MEASURED on a commercial HDMV disc (Snow Leopard, title started
     * from the top menu): the flag went to 1 as the episode began and
     * stayed there to the end, so the cache never engaged once -- the
     * cushion sat at ~26 pictures against a target of 82. There the flag
     * mirrors the graphics controller's GC_STATUS_MENU_OPEN, which is
     * raised as soon as the interactive plane has been DRAWN, including
     * the pop-up menu of a feature title, which stays drawn over the
     * running episode. BD_EVENT_POPUP separates the two cases: libbluray
     * sets it exactly when the interactive composition uses
     * IG_UI_MODEL_POPUP, i.e. a menu laid over playing video rather than
     * a full-screen menu page. So a drawn menu only counts as a menu
     * when it is not a pop-up -- verified on the same disc, which still
     * inhibits correctly on its real full-screen menu page.
     *
     * BD-J has the same trap by a different route: bd_bdj_osd_cb() raises
     * BD_EVENT_MENU the moment the application CREATES its ARGB plane
     * and only drops it when that plane closes, while a feature title
     * keeps the plane up throughout to serve its pop-up menu. Once that
     * plane exists the flag likewise says nothing about a menu. The explicit
     * top-menu title flag is different: Angry Birds keeps its ARGB plane open
     * there while a sequence of 46-second menu backgrounds plays. Letting the
     * cache read those clips ahead delivers their end events to the Xlet
     * before presentation; its controls remain transparent and the apparent
     * intro loops forever. */
    bool b_bdj_top_menu = p_sys->b_bdj_overlay &&
                          p_demux->info.i_title >= 0 &&
                          p_demux->info.i_title < (int)p_sys->i_title &&
                          (CURRENT_TITLE->i_flags & INPUT_TITLE_MENU);
    bool b_menu_shown = p_sys->b_menu_open
                     && (!p_sys->b_bdj_overlay || b_bdj_top_menu)
                     && !p_sys->b_popup_available;

    bool b_inhibit = !p_sys->b_pl_playing            /* menu / first play */
                  || b_menu_shown                    /* interactive menu up */
                  || p_sys->i_still_end_time != STILL_IMAGE_NOT_SET
                  /* The base video and audio share one chained TS parser.
                   * A large decoded MVC look-ahead fills the video fifo and
                   * blocks that parser before it can deliver later audio PES,
                   * producing periodic HDMI underruns. Edge264 and the vout
                   * retain their ordinary decode/display pools; only the
                   * optional user look-ahead cache is disabled here. */
                  || p_sys->p_mvc_parser != NULL;

    if (b_inhibit != p_sys->b_cache_inhibited) {
        p_sys->b_cache_inhibited = b_inhibit;
        es_out_Control(p_demux->out, ES_OUT_SET_VIDEO_CACHE_INHIBIT, b_inhibit);
    }
}

/* A BD-J application normally closes its ARGB plane when it hands playback
 * to another title. Some language selectors only clear it and terminate
 * without sending CLOSE (Frozen does this). Retire a plane that is known to
 * be empty, or one crossing into HDMV, rather than leaving its subpicture
 * attached above the next video's vout. */
static void blurayCloseStaleBdjOverlay(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    vlc_mutex_lock(&p_sys->bdj_overlay_lock);
    if (p_sys->b_bdj_overlay) {
        msg_Dbg(p_demux, "Closing stale BD-J overlay at title handoff");
        p_sys->b_bdj_overlay = false;
        for (int i = 0; i < MAX_OVERLAY; ++i) {
            blurayClearOverlay(p_demux, i);
            blurayCloseOverlay(p_demux, i);
        }
    }
    vlc_mutex_unlock(&p_sys->bdj_overlay_lock);

    p_sys->b_menu_open = false;
    p_sys->b_popup_available = false;
}

static void blurayHandleEvent(demux_t *p_demux, const BD_EVENT *e, bool b_delayed)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    switch (e->event) {
    case BD_EVENT_TITLE:
    {
        const bool b_was_bdj = blurayIsBdjTitle(p_demux);
        msg_Dbg(p_demux, "Blu-ray title selected: %u", e->param);
        if (e->param == BLURAY_TITLE_FIRST_PLAY)
            p_demux->info.i_title = p_sys->i_title - 1;
        else
            p_demux->info.i_title = e->param;
        /* An empty plane is not necessarily stale: Disney BD-J applications
         * clear it while handing off between their own video titles, then
         * reuse the same still-open Java plane for the main menu.  Closing it
         * here discards every later DRAW because libbluray does not emit a
         * second INIT.  Retire it only when playback actually leaves BD-J. */
        if (b_was_bdj && !blurayIsBdjTitle(p_demux))
            blurayCloseStaleBdjOverlay(p_demux);
        /* this is feature title, we don't know yet which playlist it will play (if any) */
        setTitleInfo(p_sys, NULL);
        /* reset title infos here ? */
        p_demux->info.i_update |= INPUT_UPDATE_TITLE | INPUT_UPDATE_SEEKPOINT; /* might be BD-J title with no video */
        break;
    }
    case BD_EVENT_PLAYLIST:
        /* Start of playlist playback (?????.mpls) */
        msg_Dbg(p_demux, "Blu-ray playlist selected: %05u.mpls", e->param);
        blurayUpdatePlaylist(p_demux, e->param);
        bool b_first_playitem_still = false;
        vlc_mutex_lock(&p_sys->pl_info_lock);
        if (p_sys->p_pl_info != NULL && p_sys->p_pl_info->clip_count > 0)
            b_first_playitem_still =
                p_sys->p_pl_info->clips[0].still_mode != 0;
        vlc_mutex_unlock(&p_sys->pl_info_lock);

        if (b_first_playitem_still) {
            /* Some HDMV menus expose a one-frame MPEG-2 still immediately
             * after a short H.264 first-play title (Toy Story 3). Retiring
             * the selected A/V decoder here ensures that the new PMT creates
             * MPEG-2 before the final PES is flushed below. Scope this to
             * authored still playlists: ordinary and MVC playlist handoffs
             * retain their established seamless path. */
            es_out_Control(p_sys->p_out,
                           BLURAY_ES_OUT_CONTROL_STOP_RETAINED_AV);
            blurayRestartParser(p_demux, true, false);
            es_out_Control(p_demux->out, ES_OUT_RESET_PCR);
        } else if (p_sys->b_pl_playing) {
            /* previous playlist was stopped in middle. flush to avoid delay */
            msg_Info(p_demux, "Stopping playlist playback");
            blurayRestartParser(p_demux, false, false);
            es_out_Control(p_demux->out, ES_OUT_RESET_PCR);
        }
        p_sys->b_pl_playing = true;
        p_sys->b_have_playitem = false;
        break;
    case BD_EVENT_PLAYITEM:
    {
        if (p_sys->i_playitem_seen_in_batch == (int)e->param) {
            msg_Dbg(p_demux, "ignoring duplicate Blu-ray play item %u in the same event batch",
                    e->param);
            break;
        }
        p_sys->i_playitem_seen_in_batch = e->param;
        p_sys->i_current_playitem = e->param;
        const bool b_continuing_playlist = p_sys->b_have_playitem;
        const bool b_user_activated_playitem =
            p_sys->i_last_ig_activation != VLC_TICK_INVALID &&
            mdate() - p_sys->i_last_ig_activation <= VLC_TICK_FROM_SEC(2);
        p_sys->b_have_playitem = true;
        msg_Dbg(p_demux, "Blu-ray play item selected: %u", e->param);
        /* The parser teardown below was introduced for the Intel/NVIDIA
         * asynchronous MVC path.  On Apple Silicon both views are decoded by
         * Edge264 and the teardown erases the timestamp filter's learned
         * PCR/PES offset at every BD-J play item (Dragons starts PES about
         * 11.7 seconds after PCR).  Keep the original lightweight handoff on
         * arm64: mark the old elementary streams discontinuous, then replace
         * only the dependent clip. */
#if defined(__arm64__) || defined(__aarch64__)
        /* With dual Edge264, feed the current play item in a burst so the
         * primary TS parser always has enough interleaved audio through
         * bitrate peaks. At a NATURAL end only, wait for that asynchronous
         * primary FIFO to drain before replacing the dependent parser. The
         * former 320M per-block throttle kept libbluray and the parser close
         * together but starved both audio and video; removing it without this
         * handoff let PLAYITEM close the old dependent view while its queued
         * base pictures were still being parsed, yielding a black intro.
         *
         * A user menu jump occurs before i_mvc_main_read reaches the declared
         * clip size and deliberately bypasses this wait, so navigation stays
         * immediate. While draining, continue feeding the already-complete
         * dependent file in bounded bursts so every remaining base AU can be
         * paired. */
        if (p_sys->p_mvc_parser != NULL && p_sys->p_parser != NULL &&
            p_sys->i_mvc_main_size != 0 &&
            p_sys->i_mvc_main_read + BD_READ_SIZE >= p_sys->i_mvc_main_size)
        {
            const vlc_tick_t started = mdate();
            const vlc_tick_t deadline = started + VLC_TICK_FROM_SEC(60);
            /* bd_read_ext() has reached the declared end of the primary
             * clip.  Round the accounting up to that exact boundary: the
             * last read can be shorter than BD_READ_SIZE, and using its byte
             * ratio otherwise leaves the tail of the dependent file unread.
             * Keep servicing both asynchronous parsers until the dependent
             * file has also been submitted and consumed. */
            p_sys->i_mvc_main_read = p_sys->i_mvc_main_size;
            while (vlc_demux_chained_GetBytes(p_sys->p_parser) != 0 ||
                   p_sys->i_mvc_clip_read < p_sys->i_mvc_clip_size ||
                   vlc_demux_chained_GetBytes(p_sys->p_mvc_parser) != 0)
            {
                blurayFeedMVC(p_demux, 0);
                if (mdate() >= deadline)
                    break;
                msleep(VLC_TICK_FROM_MS(10));
            }

            msg_Dbg(p_demux, "natural MVC parser drain submitted %"PRIu64
                    "/%"PRIu64" dependent bytes",
                    p_sys->i_mvc_clip_read, p_sys->i_mvc_clip_size);

            /* Emptying the chained TS FIFO only means that the compressed
             * blocks reached the decoders.  With a multi-second input lead,
             * most of the clip can still be in the decoder/vout FIFOs.  If
             * PLAYITEM tears the ES down now, those queued pictures are
             * discarded while the already-scheduled S/PDIF audio continues
             * to play (Dragons' DreamWorks logo consequently stays black).
             *
             * Keep this natural clip end alive until the video decoder and
             * the vout have actually emptied. ES_OUT_GET_EMPTY includes both
             * the compressed decoder FIFO and the decoded-picture FIFO.  A
             * bounded wait keeps a malformed disc from wedging navigation
             * forever. */
            bool empty = false;
            do
            {
                es_out_Control(p_sys->p_out, ES_OUT_GET_EMPTY, &empty);
                if (!empty)
                    msleep(10000);
            }
            while (!empty && mdate() < deadline);

            msg_Dbg(p_demux, "drained natural MVC play-item handoff in %"PRId64
                    " ms%s", (mdate() - started) / 1000,
                    empty ? "" : " (timed out)");
        }
        /* A 2D Blu-ray playlist may change both video GOP and passthrough
         * audio codec at a play-item boundary (Hopper alternates VC-1 with
         * AC-3/DTS clips).  The chained TS parser is asynchronous: resetting
         * the input clock while its old FIFO is still alive lets an old PCR
         * re-anchor that freshly reset clock.  New packets then arrive up to
         * several seconds late, while old and new VC-1 access units coexist
         * in the decoder and corrupt its reference pictures.
         *
         * Join and discard the old parser first, reset the timestamp filter,
         * and only then reset the input clock.  MVC uses the carefully
         * drained seamless handoff above and must retain its continuous
         * parser and clock. */
        if (b_continuing_playlist && p_sys->p_mvc_parser == NULL) {
            blurayRestartParser(p_demux, true, false);
            es_out_Control(p_sys->p_out,
                           BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
            es_out_Control(p_sys->p_out,
                           BLURAY_ES_OUT_CONTROL_RESTART_2D_AV);
            es_out_Control(p_demux->out, ES_OUT_RESET_PCR);
            msg_Dbg(p_demux, "joined parser and restarted retained A/V before "
                             "2D Blu-ray play-item reset");
        } else if (b_continuing_playlist && b_user_activated_playitem) {
            /* An authored menu command is a non-seamless jump even when it
             * happens to stay inside the same MVC playlist.  Keeping the
             * several seconds of already-decoded menu background made the
             * button look unresponsive and delayed the selected title. Drop
             * that old lead just as an explicit seek does; natural clip
             * boundaries retain the seamless, fully-drained path above. */
            blurayCloseMVCClip(p_demux);
            blurayRestartParser(p_demux, true, false);
            es_out_Control(p_sys->p_out,
                           BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
            es_out_Control(p_demux->out, ES_OUT_RESET_PCR);
            p_sys->b_draining = false;
            p_sys->i_last_ig_activation = VLC_TICK_INVALID;
            msg_Dbg(p_demux, "flushed buffered MVC menu background after "
                     "user activation");
        } else if (b_continuing_playlist)
            notifyDiscontinuityToParser(p_sys);
#else
        if (p_sys->p_mvc_parser != NULL) {
            blurayCloseMVCClip(p_demux);
            msg_Dbg(p_demux, "synchronizing both MVC parsers at play-item boundary");
            blurayRestartParser(p_demux, true, false);
            es_out_Control(p_sys->p_out,
                           BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
            es_out_Control(p_demux->out, ES_OUT_RESET_PCR);
        } else {
            notifyDiscontinuityToParser(p_sys);
        }
#endif
        blurayOnClipUpdate(p_demux, e->param);
        blurayOpenMVCClip(p_demux, e->param);
        break;
    }
    case BD_EVENT_CHAPTER:
        if (e->param && e->param < 0xffff)
          p_demux->info.i_seekpoint = e->param - 1;
        else
          p_demux->info.i_seekpoint = 0;
        p_demux->info.i_update |= INPUT_UPDATE_SEEKPOINT;
        break;
    case BD_EVENT_PLAYMARK:
    case BD_EVENT_ANGLE:
        break;
    case BD_EVENT_SEEK:
    {
        /* Seek will happen with any chapter/title or bd_seek(),
           but also BD-J initiated. We can't make the difference
           between input or vm ones, better double flush/pcr reset
           than break the clock by throwing post random access PCR */
        blurayRestartParser(p_demux, true, true);
        notifyDiscontinuityToParser(p_sys);
        es_out_Control(p_sys->p_out, ES_OUT_RESET_PCR);
        if (p_sys->b_user_seek_preroll) {
            /* Input controls use the playlist timeline, whereas the blocks
             * emitted by the TS parser retain the current clip's MPEG-TS
             * timestamp origin.  They differ substantially on real discs
             * (about 11.7 seconds on Dragons).  Feeding the playlist value
             * to es_out therefore ended preroll before the first AC-3 block
             * and made that block reach CoreAudio roughly 0.5 s late.
             * Map the requested playlist time into the clip timestamp domain
             * described by libbluray before setting the display boundary. */
            vlc_tick_t i_playlist_target = p_sys->i_user_seek_preroll;
            vlc_tick_t i_stream_target = i_playlist_target;
            uint64_t i_clip_start = 0;
            uint64_t i_clip_in = 0;

            vlc_mutex_lock(&p_sys->pl_info_lock);
            if (p_sys->p_clip_info != NULL) {
                i_clip_start = p_sys->p_clip_info->start_time;
                i_clip_in = p_sys->p_clip_info->in_time;
                const uint64_t i_playlist_target_90k =
                    TO_SCALE_NZ(i_playlist_target);
                if (i_playlist_target_90k >= i_clip_start)
                    i_stream_target = FROM_SCALE_NZ(i_clip_in +
                                      i_playlist_target_90k - i_clip_start);
            }
            vlc_mutex_unlock(&p_sys->pl_info_lock);

            es_out_Control(p_demux->out, ES_OUT_SET_NEXT_DISPLAY_TIME,
                           i_stream_target);
            msg_Dbg(p_demux, "user seek preroll playlist=%"PRId64
                    " stream=%"PRId64" (clip start=%"PRIu64
                    " in=%"PRIu64")",
                    i_playlist_target, i_stream_target,
                    i_clip_start, i_clip_in);
            p_sys->b_user_seek_preroll = false;
        }
        bluraySeekMVC(p_demux);
        break;
    }
    case BD_EVENT_STEREOSCOPIC_STATUS:
    {
        const bool stereoscopic = e->param != 0;
        msg_Dbg(p_demux, "Blu-ray disc selected %s output",
                stereoscopic ? "3D" : "2D");
        /* A BD-J application can advertise its default 2D output and then
         * select a 3D configuration immediately before the accompanying
         * PLAYLIST/PLAYITEM events. Rebuilding the two parsers for both
         * transient states detaches the still-open ARGB menu plane and makes
         * its buttons disappear. Record the final requested state here; the
         * playlist transition already closes the old MVC parser once, and
         * PLAYITEM opens the dependent view only when this value is true.
         * Disc-authored 2D/3D choices therefore keep the same BD-J plane while
         * still applying before the first picture of the selected playlist.
         * Flush queued paired pictures before that normal transition: a
         * short MVC intro can otherwise leave the chained parser waiting for
         * its mate when the following playlist closes it. This does not
         * remove either ES or recreate the vout. */
        if (stereoscopic != p_sys->b_stereoscopic_output)
            es_out_Control(p_sys->p_out,
                           BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
        p_sys->b_stereoscopic_output = stereoscopic;
        break;
    }
#if BLURAY_VERSION >= BLURAY_VERSION_CODE(0,8,1)
    case BD_EVENT_UO_MASK_CHANGED:
        p_sys->i_uo_mask = e->param;
        break;
#endif
    case BD_EVENT_MENU:
        p_sys->b_menu_open = e->param;
        break;
    case BD_EVENT_POPUP:
        p_sys->b_popup_available = e->param;
        /* A pop-up is composited over continuously playing feature video;
         * it must not retain the static-frame policy armed when the IG plane
         * was first created (the POPUP event can arrive after OVERLAY_INIT). */
        if (p_sys->b_popup_available) {
            if (p_sys->p_vout != NULL) {
                vout_ChangeStaticFrameHold(p_sys->p_vout, false);
            } else {
                vout_thread_t *vout = input_GetVout(p_demux->p_input);
                if (vout != NULL) {
                    vout_ChangeStaticFrameHold(vout, false);
                    vlc_object_release(vout);
                }
            }
        }
        /* HDMV only -- never raised by BD-J. The interfaces are not driven
         * from here (see INPUT_POPUP_MENU_VAR at open time); the flag serves
         * the navigation and the look-ahead cache below. */
        msg_Dbg(p_demux, "BD_EVENT_POPUP: pop-up menu %s",
                p_sys->b_popup_available ? "available" : "unavailable");
        break;

    /*
     * Errors
     */
    case BD_EVENT_ERROR:
        /* fatal error (with menus) */
        vlc_dialog_display_error(p_demux, _("Blu-ray error"),
                                 "Playback with BluRay menus failed");
        p_sys->b_fatal_error = true;
        break;
    case BD_EVENT_ENCRYPTED:
        vlc_dialog_display_error(p_demux, _("Blu-ray error"),
                                 "This disc seems to be encrypted");
        p_sys->b_fatal_error = true;
        break;
    case BD_EVENT_READ_ERROR:
        msg_Err(p_demux, "bluray: read error\n");
        break;

    /*
     * stream selection events
     */
    case BD_EVENT_PG_TEXTST:
        p_sys->b_spu_enable = e->param;
        /* the display toggle may come without a following stream event */
        es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_SET_SPU_VISIBILITY,
                       (int)e->param);
        break;
    case BD_EVENT_AUDIO_STREAM:
    case BD_EVENT_PG_TEXTST_STREAM:
         if(b_delayed)
             blurayOnStreamSelectedEvent(p_demux, e->event, e->param);
         else
             ARRAY_APPEND(p_sys->events_delayed, *e);
        break;
    case BD_EVENT_IG_STREAM:
        /* Confirms which localized HDMV menu plane libbluray selected. */
        msg_Dbg(p_demux, "Blu-ray interactive graphics stream selected: %u",
                e->param);
        break;
    case BD_EVENT_SECONDARY_AUDIO:
    case BD_EVENT_SECONDARY_AUDIO_STREAM:
    case BD_EVENT_SECONDARY_VIDEO:
    case BD_EVENT_SECONDARY_VIDEO_STREAM:
    case BD_EVENT_SECONDARY_VIDEO_SIZE:
        break;

    /*
     * playback control events
     */
    case BD_EVENT_PLAYLIST_STOP:
        /* BD-J can queue the replacement playlist before reporting that the
         * preceding one was stopped (Angry Birds does this when Top Menu is
         * requested during its intro).  The event contract says to flush all
         * buffers.  Ignoring it left base-view packets and MVC references from
         * both playlists in the recycled decoder, displaying a frozen,
         * macroblocked frame until the next clean random-access point. */
        msg_Dbg(p_demux, "Blu-ray playlist stopped; flushing playback state");
        p_sys->b_draining = false;
        p_sys->b_pl_playing = false;
        blurayCloseMVCClip(p_demux);
        blurayRestartParser(p_demux, true, false);
        es_out_Control(p_sys->p_out,
                       BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
        es_out_Control(p_demux->out, ES_OUT_RESET_PCR);
        break;
    case BD_EVENT_STILL_TIME:
        blurayStillImage(p_demux, e->param);
        break;
    case BD_EVENT_STILL:
        msg_Dbg(p_demux, "Blu-ray still state: %u", e->param);
        /* BD_EVENT_STILL is emitted by both the JVM and the HDMV graphics VM.
         * Only the BD-J form must flush the last access unit and hold it here:
         * an HDMV STILL_ON belongs to an interactive menu object whose IG
         * plane may be flushed immediately afterwards. Flushing the video ES
         * for that event can retire the only vout before the pending IG plane
         * is attached, leaving a perfectly live menu with invisible buttons
         * (seen on Up at the Walt Disney Studios first-play page).
         *
         * Ignoring the BD-J form, on the other hand, made Rio's pre-menu
         * sequence loop while its Xlet waited in still mode. Keep that fix,
         * but scope it to BD-J titles. HDMV play-item stills continue to use
         * BD_EVENT_STILL_TIME below. */
        if (blurayIsBdjTitle(p_demux)) {
            if (e->param)
                blurayStillImage(p_demux, 0); /* 0 -> STILL_IMAGE_INFINITE */
            else
                blurayResetStillImage(p_demux);
        }
        break;
    case BD_EVENT_DISCONTINUITY:
        /* reset demuxer (partially decoded PES packets must be dropped) */
        blurayRestartParser(p_demux, false, true);
        es_out_Control(p_sys->p_out, BLURAY_ES_OUT_CONTROL_FLAG_DISCONTINUITY);
        break;
    case BD_EVENT_END_OF_TITLE:
        if(p_sys->b_pl_playing)
        {
            notifyDiscontinuityToParser(p_sys);
            blurayRestartParser(p_demux, false, false);
            p_sys->b_draining = true;
            p_sys->b_pl_playing = false;
        }
        break;
    case BD_EVENT_IDLE:
        /* nothing to do (ex. BD-J is preparing menus, waiting user input or running animation) */
        /* avoid busy loop (bd_read() returns no data) */
        msleep( 40000 );
        break;

    default:
        msg_Warn(p_demux, "event: %d param: %d", e->event, e->param);
        break;
    }
}

static bool blurayIsBdjTitle(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    unsigned int i_title = p_demux->info.i_title;
    const BLURAY_DISC_INFO *di = bd_get_disc_info(p_sys->bluray);

    if (di && di->titles) {
        if ((i_title <= di->num_titles && di->titles[i_title] && di->titles[i_title]->bdj) ||
            (i_title == p_sys->i_title - 1 && di->first_play && di->first_play->bdj)) {
          return true;
        }
    }

    return false;
}

static bool blurayUsesLinuxKms3d(demux_t *p_demux)
{
#ifdef __linux__
    char *vout = var_InheritString(p_demux, "vout");
    bool uses_kms3d = vout != NULL && strcmp(vout, "kms3d") == 0;
    free(vout);
    return uses_kms3d;
#else
    VLC_UNUSED(p_demux);
    return false;
#endif
}

static void blurayHandleOverlays(demux_t *p_demux, int nread)
{
    demux_sys_t *p_sys = p_demux->p_sys;

    vlc_mutex_lock(&p_sys->bdj_overlay_lock);

    for (int i = 0; i < MAX_OVERLAY; i++) {
        bluray_overlay_t *ov = p_sys->p_overlays[i];
        if (!ov) {
            continue;
        }
        vlc_mutex_lock(&ov->lock);
        bool display = ov->status == ToDisplay;
        bool refresh_due = ov->status == Outdated &&
                           ov->i_update_date > VLC_TICK_INVALID &&
                           mdate() >= ov->i_update_date;
        int stale_channel = -1;
        subpicture_updater_sys_t *stale_updater = NULL;
        if (refresh_due) {
            ov->i_update_date = VLC_TICK_INVALID;
            stale_channel = ov->i_channel;
            stale_updater = ov->p_updater;
            ov->i_channel = -1;
            ov->p_updater = NULL;
            ov->status = ToDisplay;
        }
        vlc_mutex_unlock(&ov->lock);
        /* The video decoder can save and reuse its vout between the initial
         * empty IG flush and this deliberately delayed completed page.  That
         * resets the SPU heap without changing the vout object, leaving the
         * overlay's registered channel stale.  Replace that channel at the
         * deadline instead of trying to refresh a subpicture that the reused
         * vout no longer owns. */
        if (refresh_due) {
            msg_Dbg(p_demux, "replacing scheduled Blu-ray overlay channel "
                    "for plane %d", i);
            if (p_sys->p_vout != NULL && stale_channel != -1)
                vout_FlushSubpictureChannel(p_sys->p_vout, stale_channel);
            if (stale_updater != NULL)
                unref_subpicture_updater(stale_updater);
            if (p_sys->p_vout != NULL) {
                bluraySendOverlayToVout(p_demux, ov);
                display = false;
            } else {
                display = true;
            }
        }
        if (display) {
            bool b_new_vout = false;

            msg_Dbg(p_demux, "Blu-ray overlay ready, vout=%p, read=%d",
                    (void *)p_sys->p_vout, nread);
            if (p_sys->p_vout == NULL) {
                p_sys->p_vout = input_GetVout(p_demux->p_input);
                b_new_vout = p_sys->p_vout != NULL;
            }

            /* NOTE: we might want to enable background video always when there's no video stream playing.
               Now, with some discs, there are perioids (even seconds) during which the video window
               disappears and just playlist is shown.
               (sometimes BD-J runs slowly ...)
            */
            if (!p_sys->p_vout && !p_sys->p_dummy_video && p_sys->b_menu &&
                nread == 0 &&
                (blurayIsBdjTitle(p_demux) ||
                 blurayUsesLinuxKms3d(p_demux))) {

                /* A playlist record does not guarantee that its selected
                 * video stream will ever produce a picture. Some BD-J first
                 * play titles enter an infinite still with such an empty
                 * stream; others hand off from a BD-J first-play title to an
                 * HDMV background before creating their ARGB menu. In both
                 * cases the ready graphics plane needs a video output. */
                if(blurayCreateBackgroundUnlocked(p_demux) != NULL) {
                    p_sys->p_vout = input_GetVout(p_demux->p_input);
                    b_new_vout = p_sys->p_vout != NULL;
                }
            }

            if (p_sys->p_vout != NULL) {
                /* This vout can have been obtained either before or after the
                 * synthetic BD-J background was created.  In both cases its
                 * first adoption must wire the interactive-menu callbacks. */
                if (b_new_vout) {
                    var_AddCallback(p_sys->p_vout, "mouse-moved", onMouseEvent, p_demux);
                    var_AddCallback(p_sys->p_vout, "mouse-clicked", onMouseEvent, p_demux);
                }
                bluraySendOverlayToVout(p_demux, ov);
            }
        }
    }

    vlc_mutex_unlock(&p_sys->bdj_overlay_lock);
}

static int onIntfEvent( vlc_object_t *p_input, char const *psz_var,
                        vlc_value_t oldval, vlc_value_t val, void *p_data )
{
    (void)p_input; (void) psz_var; (void) oldval;
    demux_t *p_demux = p_data;
    demux_sys_t *p_sys = p_demux->p_sys;

    if (val.i_int == INPUT_EVENT_VOUT) {

        const bool uses_linux_kms3d = blurayUsesLinuxKms3d(p_demux);

        /* input_GetVout() can publish a replacement vout while the Blu-ray
         * menu still owns a reference to the retired one.  This happens on
         * Linux when a short MVC menu clip is replaced by its still/background
         * decoder: the old vout object remains perfectly callable, so merely
         * testing p_vout for NULL sends the IG plane to a dead control queue.
         * Compare identities on every VOUT event and let the normal overlay
         * hand-off recreate the channel for the replacement. */
        if (uses_linux_kms3d) {
            vout_thread_t *current_vout = input_GetVout(p_demux->p_input);
            if (current_vout != NULL) {
                if (p_sys->p_vout != NULL && p_sys->p_vout != current_vout) {
                    msg_Dbg(p_demux, "Blu-ray video output changed (%p -> %p), "
                            "reattaching menu overlay",
                            (void *)p_sys->p_vout, (void *)current_vout);
                    blurayReleaseVout(p_demux);
                }
                vlc_object_release(current_vout);
            }
        }

        /* Replacing one MVC disc with another can reuse the existing vout
         * without reopening its macOS display module.  If the file chooser
         * left fullscreen, assert only the missing true edge as soon as the
         * new input publishes its vout.  Never replay false/true: that older
         * workaround exposed Finder and could leave a later menu windowed. */
        if (p_sys->b_inherited_stereo_presentation &&
            !p_sys->b_stereo_presentation_checked) {
            vout_thread_t *vout = input_GetVout(p_demux->p_input);
            if (vout != NULL) {
                p_sys->b_stereo_presentation_checked = true;
                if (!var_GetBool(vout, "fullscreen")) {
                    var_SetBool(vout, "fullscreen", true);
                    msg_Info(p_demux, "restoring retained HDMI 3D fullscreen "
                             "for replacement Blu-ray");
                }
                vlc_object_release(vout);
            }
        }

        /* An HDMV first-play title can flush its short background clip before
         * libbluray creates the interactive plane (Cars 2 does this by about
         * 30 ms).  Arm the last-frame hold as soon as the vout exists, while
         * displayed.current still owns that background.  Waiting for
         * BD_OVERLAY_INIT is too late: the display keeps the pixels on screen,
         * but VLC has already released the picture needed to blend the menu. */
        if (p_sys->b_menu && !p_sys->b_popup_available &&
            !blurayIsBdjTitle(p_demux)) {
            vout_thread_t *vout = input_GetVout(p_demux->p_input);
            if (vout != NULL) {
                vout_ChangeStaticFrameHold(vout, true);
                vlc_object_release(vout);
            }
        }

        vlc_mutex_lock(&p_sys->bdj_overlay_lock);
        bool b_hold_hdmv_menu_vout = false;
        if (p_sys->p_vout != NULL &&
            p_sys->b_menu_open &&
            !p_sys->b_popup_available &&
            !p_sys->b_bdj_overlay) {
            for (int i = 0; i < MAX_OVERLAY; ++i) {
                if (p_sys->p_overlays[i] != NULL) {
                    b_hold_hdmv_menu_vout = true;
                    break;
                }
            }
        }

        /* The TS parser is recreated at an HDMV playlist boundary.  VLC then
         * reports the old decoder's vout as temporarily free before the new
         * decoder has a complete picture.  The VOUT event can race a few
         * milliseconds ahead of BD_EVENT_STILL_TIME, so key this on the
         * already-open full-screen HDMV menu rather than the still deadline.
         * Such a menu may have no next picture: releasing our reference would
         * permanently detach its interactive plane.  Popup menus are excluded
         * because their plane intentionally persists over a feature title. */
        if (b_hold_hdmv_menu_vout) {
            msg_Dbg(p_demux, "Holding video output for infinite HDMV menu still");
        } else if( p_sys->p_vout != NULL ) {
            blurayReleaseVout(p_demux);
        }
        vlc_mutex_unlock(&p_sys->bdj_overlay_lock);

        /* A display-module restart can destroy the SPU heap without changing
         * the vout object itself.  In that case subpictureUpdaterDestroy()
         * puts the plane back in ToDisplay.  Always service that state after
         * a VOUT event, including while retaining an HDMV still; the handler
         * is a no-op when the existing channel is still attached. */
        if (!b_hold_hdmv_menu_vout || uses_linux_kms3d)
            blurayHandleOverlays(p_demux, 1);
    }

    return VLC_SUCCESS;
}

static int blurayDemux(demux_t *p_demux)
{
    demux_sys_t *p_sys = p_demux->p_sys;
    BD_EVENT e;

    if(p_sys->b_draining)
    {
        bool b_empty = false;
        if(es_out_Control(p_sys->p_out, ES_OUT_GET_EMPTY, &b_empty) != VLC_SUCCESS || b_empty)
        {
            es_out_Control(p_sys->p_out, ES_OUT_RESET_PCR);
            p_sys->b_draining = false;
        }
        else
        {
            msg_Dbg(p_demux, "Draining...");
            msleep( 40000 );
            return VLC_DEMUXER_SUCCESS;
        }
    }

    block_t *p_block = block_Alloc(BD_READ_SIZE);
    if (!p_block)
        return VLC_DEMUXER_EGENERIC;

    int nread;

    /* bd_read[_ext]() may return PLAYITEM directly and leave an identical
     * copy in libbluray's event queue. Treat those as one transition. The
     * marker is deliberately reset for every read so a later seek back to
     * the same clip remains a real play-item change. */
    p_sys->i_playitem_seen_in_batch = -1;

    if (p_sys->b_menu == false) {
        nread = bd_read(p_sys->bluray, p_block->p_buffer, BD_READ_SIZE);
        while (bd_get_event(p_sys->bluray, &e))
            blurayHandleEvent(p_demux, &e, false);
    } else {
        nread = bd_read_ext(p_sys->bluray, p_block->p_buffer, BD_READ_SIZE, &e);
        while (e.event != BD_EVENT_NONE) {
            blurayHandleEvent(p_demux, &e, false);
            bd_get_event(p_sys->bluray, &e);
        }
    }

    /* The duplicate marker is meaningful only inside this libbluray event
     * batch. A disc which emits PLAYITEM without DISCONTINUITY must not cause
     * an unrelated discontinuity on the next read to be ignored. */
    p_sys->b_playitem_reset_pending = false;

    /* After the events, so a title/menu/still transition takes effect on the
     * same iteration that reported it. */
    blurayCacheInhibitUpdate(p_demux);

    /* Process delayed selections events */
    for(int i=0; i<p_sys->events_delayed.i_size; i++)
        blurayHandleEvent(p_demux, &p_sys->events_delayed.p_elems[i], true);
    p_sys->events_delayed.i_size = 0;


    blurayHandleOverlays(p_demux, nread);

    if (nread <= 0) {
        block_Release(p_block);
        if (p_sys->b_fatal_error || nread < 0) {
            msg_Err(p_demux, "bluray: stopping playback after fatal error\n");
            return VLC_DEMUXER_EGENERIC;
        }
        /* The chained primary TS parser can still be consuming blocks after
         * libbluray has reached a play-item still/end.  Keep servicing the
         * throttled dependent-view feeder while its file is incomplete;
         * otherwise a late primary parser can build a many-second base queue
         * with no remaining demux iteration capable of supplying its pairs. */
        if (p_sys->p_mvc_file != NULL &&
            p_sys->i_mvc_clip_read < p_sys->i_mvc_clip_size) {
            blurayFeedMVC(p_demux, 0);
            msleep(VLC_TICK_FROM_MS(10));
            return VLC_DEMUXER_SUCCESS;
        }
        if (!p_sys->b_menu) {
            return VLC_DEMUXER_EOF;
        }
        /* Still mode yields no data until the disc leaves it. The timed
         * (HDMV) still paces itself inside blurayStillImage(), which libbluray
         * re-arms on every read; the BD-J one is a single transition event, so
         * without this the demuxer would spin on bd_read_ext() burning a core
         * for as long as the menu is up. */
        if (p_sys->i_still_end_time == STILL_IMAGE_INFINITE)
            msleep(40000);
        return VLC_DEMUXER_SUCCESS;
    }

    p_block->i_buffer = nread;

    stopBackground(p_demux);

    /* The dependent parser is primed when its clip is opened, so the first
     * base access unit already has a pair available.  From here on publish
     * the primary block first: it also carries the audio streams, and making
     * it wait behind dependent-view catch-up stalls HDMI audio for hundreds
     * of milliseconds whenever that queue is throttled. */
    vlc_demux_chained_Send(p_sys->p_parser, p_block);
    blurayFeedMVC(p_demux, nread);

#if defined(__APPLE__) && defined(__aarch64__)
    if (p_sys->p_mvc_parser != NULL)
    {
        /* Give both chained TS workers one scheduling quantum to publish
         * their decoded pairing depth before bd_read_ext() queues the next
         * 60 KiB from each file.  One millisecond still permits about
         * 60 MiB/s of compressed input (far beyond Blu-ray's maximum), while
         * the former NVIDIA 10 ms throttle was slow enough to starve audio. */
        msleep(1000);
    }
#endif

    p_sys->b_flushed = false;

    return VLC_DEMUXER_SUCCESS;
}

/*****************************************************************************
 * bluray Escape es_out
 *****************************************************************************/
struct escape_es_id
{
    es_out_id_t *es;
    bool drop_first;
    vlc_tick_t first_dts;
};

struct escape_esout_sys
{
    es_out_t *dst_out;
    vlc_tick_t  offset_pcr;

    vlc_array_t es_ids; /* escape_es_id */
};

static es_out_id_t *escape_esOutAdd(es_out_t *out, const es_format_t *fmt)
{
    struct escape_esout_sys *esout_sys = (struct escape_esout_sys *)out->p_sys;

    struct escape_es_id *esc_id = malloc(sizeof(*esc_id));
    if (!esc_id)
        return NULL;
    esc_id->es = es_out_Add(esout_sys->dst_out, fmt);
    if (!esc_id->es)
    {
        free(esc_id);
        return NULL;
    }
    esc_id->first_dts = -1;
    esc_id->drop_first = fmt->i_cat == VIDEO_ES;
    if (vlc_array_append(&esout_sys->es_ids, esc_id) != VLC_SUCCESS)
    {
        es_out_Del(esout_sys->dst_out, esc_id->es);
        free(esc_id);
        return NULL;
    }
    return esc_id->es;
}

static struct escape_es_id *escape_GetEscOutId(es_out_t *out, es_out_id_t *es,
                                               size_t *out_idx)
{
    struct escape_esout_sys *esout_sys = (struct escape_esout_sys *)out->p_sys;

    for (size_t i = 0; i < vlc_array_count(&esout_sys->es_ids); ++i)
    {
        struct escape_es_id *esc_id = vlc_array_item_at_index(&esout_sys->es_ids, i);
        if (esc_id->es == es)
        {
            if (out_idx)
                *out_idx = i;
            return esc_id;
        }
    }
    return NULL;
}

static int escape_esOutSend(es_out_t *out, es_out_id_t *es, block_t *block)
{
    struct escape_esout_sys *esout_sys = (struct escape_esout_sys *)out->p_sys;
    struct escape_es_id *esc_id = escape_GetEscOutId(out, es, NULL);
    if (esc_id == NULL)
        return VLC_EGENERIC;

    if (esout_sys->offset_pcr != -1)
    {
        if (esc_id->first_dts == -1)
        {
            esc_id->first_dts = block->i_dts;
            if (esc_id->drop_first)
                block->i_flags |= BLOCK_FLAG_PREROLL;
        }
        vlc_tick_t offset = esout_sys->offset_pcr - esc_id->first_dts;
        block->i_pts += offset;
        block->i_dts += offset;
    }

    return es_out_Send(esout_sys->dst_out, es, block);
}

static void escape_esOutDel(es_out_t *out, es_out_id_t *es)
{
    struct escape_esout_sys *esout_sys = (struct escape_esout_sys *)out->p_sys;
    size_t index;
    struct escape_es_id *esc_id = escape_GetEscOutId(out, es, &index);
    if (esc_id == NULL)
        return;

    vlc_array_remove(&esout_sys->es_ids, index);
    es_out_Del(esout_sys->dst_out, es);
    free(esc_id);
}

static int escape_esOutControl(es_out_t *p_out, int query, va_list args)
{
    struct escape_esout_sys *esout_sys = (struct escape_esout_sys *)p_out->p_sys;
    int ret;

    switch (query)
    {
        case ES_OUT_RESET_PCR:
            for (size_t i = 0; i < vlc_array_count(&esout_sys->es_ids); ++i)
            {
                struct escape_es_id *esc_id = vlc_array_item_at_index(&esout_sys->es_ids, i);
                esc_id->first_dts = -1;
            }
            esout_sys->offset_pcr = -1;

            ret = es_out_vaControl(esout_sys->dst_out, query, args);
            break;
        case ES_OUT_SET_GROUP_PCR:
        {
            int group = va_arg( args, int );
            vlc_tick_t pcr = va_arg( args, int64_t );

            if (esout_sys->offset_pcr == -1)
                esout_sys->offset_pcr = pcr;
            ret = es_out_Control(esout_sys->dst_out, query, group, pcr);
            break;
        }
        default:
            ret = es_out_vaControl(esout_sys->dst_out, query, args);
            break;
    }
    return ret;
}

static void escape_esOutDestroy(es_out_t *p_out)
{
    struct escape_esout_sys *esout_sys = (struct escape_esout_sys *)p_out->p_sys;

    vlc_array_clear(&esout_sys->es_ids);
    free(p_out->p_sys);
    free(p_out);
}

static es_out_t *escape_esOutNew(vlc_object_t *p_obj, es_out_t *dst_out)
{
    es_out_t *out = malloc(sizeof(*out));
    if (unlikely(out == NULL))
        return NULL;

    out->pf_add       = escape_esOutAdd;
    out->pf_control   = escape_esOutControl;
    out->pf_del       = escape_esOutDel;
    out->pf_destroy   = escape_esOutDestroy;
    out->pf_send      = escape_esOutSend;

    struct escape_esout_sys *esout_sys = malloc(sizeof(*esout_sys));
    if (unlikely(esout_sys == NULL))
    {
        free(out);
        return NULL;
    }
    out->p_sys = (es_out_sys_t *) esout_sys;
    vlc_array_init(&esout_sys->es_ids);
    esout_sys->offset_pcr = -1;
    esout_sys->dst_out = dst_out;

    var_Create( p_obj, "ts-trust-pcr", VLC_VAR_BOOL );
    var_SetBool( p_obj, "ts-trust-pcr", false );
    return out;
}
