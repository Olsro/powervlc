/*****************************************************************************
 * input_manager.cpp : Manage an input and interact with its GUI elements
 ****************************************************************************
 * Copyright (C) 2006-2008 the VideoLAN team
 * $Id$
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Ilkka Ollakka  <ileoo@videolan.org>
 *          Jean-Baptiste <jb@videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "input_manager.hpp"
#include "recents.hpp"

#include <vlc_actions.h>           /* ACTION_ID */
#include <vlc_url.h>            /* vlc_uri_decode */
#include <vlc_strings.h>        /* vlc_strfinput */
#include <vlc_aout.h>           /* audio_output_t */
#include <vlc_vout_osd.h>       /* vout_OSDText */
#include <vlc_subpicture.h>     /* SUBPICTURE_ALIGN_* */

#include <QApplication>
#include <QDateTime>
#include <QFile>
#include <QFileInfo>
#include <QDir>
#include <QSignalMapper>
#include <QMessageBox>
#include <QTimer>

#include <assert.h>

static int InputEvent( vlc_object_t *, const char *,
                       vlc_value_t, vlc_value_t, void * );
static int VbiEvent( vlc_object_t *, const char *,
                     vlc_value_t, vlc_value_t, void * );

/* Ensure arbitratry (not dynamically allocated) event IDs are not in use */
static inline void registerAndCheckEventIds( int start, int end )
{
    for ( int i=start ; i<=end ; i++ )
        Q_ASSERT( QEvent::registerEventType( i ) == i ); /* event ID collision ! */
}

/**********************************************************************
 * InputManager implementation
 **********************************************************************
 * The Input Manager can be the main one around the playlist
 * But can also be used for VLM dialog or similar
 **********************************************************************/

InputManager::InputManager( MainInputManager *mim, intf_thread_t *_p_intf) :
                           QObject( mim ), p_intf( _p_intf )
{
    p_mim        = mim;
    i_old_playing_status = END_S;
    oldName      = "";
    artUrl       = "";
    p_input      = NULL;
    p_input_vbi  = NULL;
    f_rate       = 0.;
    p_item       = NULL;
    b_video      = false;
    timeA        = 0;
    timeB        = 0;
    b_clipMode   = false;
    f_clipStart  = 0.;
    f_clipEnd    = 0.;
    b_clipRecording = false;
    f_clipLastPos = -1.;
    clipLastInteractionMs = 0;
    i_clipPausedAtEnd = 0;
    i_clipSelectedKnob = 2;
    p_clipExport = NULL;
    clipExportTimer = new QTimer( this );
    clipExportTimer->setInterval( 250 );
    connect( clipExportTimer, &QTimer::timeout,
             this, &InputManager::clipExportPoll );
    clipPreviewTimer = new QTimer( this );
    clipPreviewTimer->setSingleShot( true );
    clipPreviewTimer->setInterval( 33 );
    clipPreviewTimer->setTimerType( Qt::PreciseTimer );
    b_clipPreviewPending = false;
    f_clipPreviewTarget = 0.;
    connect( clipPreviewTimer, &QTimer::timeout,
             this, &InputManager::clipPreviewTimeout );
    f_cache      = -1.; /* impossible initial value, different from all */
    registerAndCheckEventIds( IMEvent::PositionUpdate, IMEvent::FullscreenControlPlanHide );
    registerAndCheckEventIds( PLEvent::PLItemAppended, PLEvent::PLEmpty );
}

InputManager::~InputManager()
{
    delInput();
}

void InputManager::inputChangedHandler()
{
    setInput( p_mim->getInput() );
}

/* Define the Input used.
   Add the callbacks on input
   p_input is held once here */
void InputManager::setInput( input_thread_t *_p_input )
{
    delInput();
    p_input = _p_input;
    if( p_input != NULL )
    {
        msg_Dbg( p_intf, "IM: Setting an input" );
        vlc_object_hold( p_input );
        addCallbacks();

        UpdateStatus();
        UpdateName();
        UpdateArt();
        UpdateTeletext();
        UpdateNavigation();
        UpdateVout();

        p_item = input_GetItem( p_input );
        emit rateChanged( var_GetFloat( p_input, "rate" ) );

        /* Get Saved Time */
        if( p_item->i_type == ITEM_TYPE_FILE )
        {
            char *uri = input_item_GetURI( p_item );

            int i_time = RecentsMRL::getInstance( p_intf )->time( qfu(uri) );
            if( i_time > 0 && qfu( uri ) != lastURI &&
                    !var_GetFloat( p_input, "run-time" ) &&
                    !var_GetFloat( p_input, "start-time" ) &&
                    !var_GetFloat( p_input, "stop-time" ) )
            {
                emit resumePlayback( (int64_t)i_time * 1000 );
            }
            playlist_Lock( THEPL );
            // Add root items only
            playlist_item_t* p_node = playlist_CurrentPlayingItem( THEPL );
            if ( p_node != NULL && p_node->p_parent != NULL && p_node->p_parent->i_id == THEPL->p_playing->i_id )
            {
                // Save the latest URI to avoid asking to restore the
                // position on the same input file.
                lastURI = qfu( uri );
                RecentsMRL::getInstance( p_intf )->addRecent( lastURI );
            }
            playlist_Unlock( THEPL );
            free( uri );
        }
    }
    else
    {
        p_item = NULL;
        lastURI.clear();
        assert( !p_input_vbi );
        emit rateChanged( var_InheritFloat( p_intf, "rate" ) );
    }
}

/* delete Input if it ever existed.
   Delete the callbacls on input
   p_input is released once here */
void InputManager::delInput()
{
    if( !p_input ) return;
    msg_Dbg( p_intf, "IM: Deleting the input" );

    /* the clip creation mode is bound to the item it was entered on */
    exitClipCreationMode();

    /* Save time / position */
    char *uri = input_item_GetURI( p_item );
    if( uri != NULL ) {
        float f_pos = var_GetFloat( p_input , "position" );
        int64_t i_time = -1;

        if( f_pos >= 0.05f && f_pos <= 0.95f
         && var_GetInteger( p_input, "length" ) >= 60 * CLOCK_FREQ )
            i_time = var_GetInteger( p_input, "time");

        RecentsMRL::getInstance( p_intf )->setTime( qfu(uri), i_time );
        free(uri);
    }

    delCallbacks();
    i_old_playing_status = END_S;
    p_item               = NULL;
    oldName              = "";
    artUrl               = "";
    b_video              = false;
    timeA                = 0;
    timeB                = 0;
    f_rate               = 0. ;

    if( p_input_vbi )
    {
        vlc_object_release( p_input_vbi );
        p_input_vbi = NULL;
    }

    vlc_object_release( p_input );
    p_input = NULL;

    emit positionUpdated( -1.0, 0 ,0 );
    emit rateChanged( var_InheritFloat( p_intf, "rate" ) );
    emit nameChanged( "" );
    emit chapterChanged( 0 );
    emit titleChanged( 0 );
    emit playingStatusChanged( END_S );

    emit teletextPossible( false );
    emit AtoBchanged( false, false );
    emit voutChanged( false );
    emit voutListChanged( NULL, 0 );

    /* Reset all InfoPanels but stats */
    emit artChanged( NULL );
    emit artChanged( "" );
    emit infoChanged( NULL );
    emit currentMetaChanged( (input_item_t *)NULL );

    emit encryptionChanged( false );
    emit recordingStateChanged( false );

    emit cachingChanged( 0.0 );
}

/* Convert the event from the callbacks in actions */
void InputManager::customEvent( QEvent *event )
{
    int i_type = event->type();
    IMEvent *ple = static_cast<IMEvent *>(event);

    if( i_type == IMEvent::ItemChanged )
        UpdateMeta( ple->item() );

    if( !hasInput() )
        return;

    /* Actions */
    switch( i_type )
    {
    case IMEvent::PositionUpdate:
        UpdatePosition();
        break;
    case IMEvent::StatisticsUpdate:
        UpdateStats();
        break;
    case IMEvent::ItemChanged:
        /* Ignore ItemChanged_Type event that does not apply to our input */
        if( p_item == ple->item() )
        {
            UpdateStatus();
            UpdateName();
            UpdateArt();
            UpdateMeta();
            /* Update duration of file */
        }
        break;
    case IMEvent::ItemStateChanged:
        UpdateStatus();
        break;
    case IMEvent::MetaChanged:
        UpdateMeta();
        UpdateName(); /* Needed for NowPlaying */
        UpdateArt(); /* Art is part of meta in the core */
        break;
    case IMEvent::InfoChanged:
        UpdateInfo();
        break;
    case IMEvent::ItemTitleChanged:
        UpdateNavigation();
        UpdateName(); /* Display the name of the Chapter, if exists */
        break;
    case IMEvent::ItemRateChanged:
        UpdateRate();
        break;
    case IMEvent::ItemEsChanged:
        UpdateTeletext();
        // We don't do anything ES related. Why ?
        break;
    case IMEvent::ItemTeletextChanged:
        UpdateTeletext();
        break;
    case IMEvent::InterfaceVoutUpdate:
        UpdateVout();
        break;
    case IMEvent::SynchroChanged:
        emit synchroChanged();
        break;
    case IMEvent::CachingEvent:
        UpdateCaching();
        break;
    case IMEvent::BookmarksChanged:
        emit bookmarksChanged();
        break;
    case IMEvent::InterfaceAoutUpdate:
        UpdateAout();
        break;
    case IMEvent::RecordingEvent:
        UpdateRecord();
        break;
    case IMEvent::ProgramChanged:
        UpdateProgramEvent();
        break;
    case IMEvent::EPGEvent:
        UpdateEPG();
        break;
    default:
        msg_Warn( p_intf, "This shouldn't happen: %i", i_type );
        vlc_assert_unreachable();
    }
}

/* Add the callbacks on Input. Self explanatory */
inline void InputManager::addCallbacks()
{
    var_AddCallback( p_input, "intf-event", InputEvent, this );
}

/* Delete the callbacks on Input. Self explanatory */
inline void InputManager::delCallbacks()
{
    var_DelCallback( p_input, "intf-event", InputEvent, this );
}

/* The core hotkeys module redirects the jump actions (and the bare arrow
 * keys) to this input variable while it exists, so that a jump shortcut
 * nudges the selected clip bound instead of seeking -- the only way to
 * frame a clip to the frame. Value convention (see hotkeys.c): +-1 = one
 * frame, anything else = a signed amount of microseconds. Runs on the
 * hotkeys thread: hop to the Qt thread. */
static int ClipStepCallback( vlc_object_t *, const char *,
                             vlc_value_t, vlc_value_t newval, void *param )
{
    InputManager *im = (InputManager *)param;
    QMetaObject::invokeMethod( im, "clipStepFromCore", Qt::QueuedConnection,
                               Q_ARG( qint64, (qint64)newval.i_int ) );
    return VLC_SUCCESS;
}

/* Static callbacks for IM */
int MainInputManager::ItemChanged( vlc_object_t *, const char *,
                                   vlc_value_t, vlc_value_t val, void *param )
{
    InputManager *im = (InputManager*)param;
    input_item_t *p_item = static_cast<input_item_t *>(val.p_address);

    IMEvent *event = new IMEvent( IMEvent::ItemChanged, p_item );
    QApplication::postEvent( im, event );
    return VLC_SUCCESS;
}

static int InputEvent( vlc_object_t *, const char *,
                       vlc_value_t, vlc_value_t newval, void *param )
{
    InputManager *im = (InputManager*)param;
    IMEvent *event;

    switch( newval.i_int )
    {
    case INPUT_EVENT_STATE:
        event = new IMEvent( IMEvent::ItemStateChanged );
        break;
    case INPUT_EVENT_RATE:
        event = new IMEvent( IMEvent::ItemRateChanged );
        break;
    case INPUT_EVENT_POSITION:
    //case INPUT_EVENT_LENGTH:
        event = new IMEvent( IMEvent::PositionUpdate );
        break;

    case INPUT_EVENT_TITLE:
    case INPUT_EVENT_CHAPTER:
        event = new IMEvent( IMEvent::ItemTitleChanged );
        break;

    case INPUT_EVENT_ES:
        event = new IMEvent( IMEvent::ItemEsChanged );
        break;
    case INPUT_EVENT_TELETEXT:
        event = new IMEvent( IMEvent::ItemTeletextChanged );
        break;

    case INPUT_EVENT_STATISTICS:
        event = new IMEvent( IMEvent::StatisticsUpdate );
        break;

    case INPUT_EVENT_VOUT:
        event = new IMEvent( IMEvent::InterfaceVoutUpdate );
        break;
    case INPUT_EVENT_AOUT:
        event = new IMEvent( IMEvent::InterfaceAoutUpdate );
        break;

    case INPUT_EVENT_ITEM_META: /* Codec MetaData + Art */
        event = new IMEvent( IMEvent::MetaChanged );
        break;
    case INPUT_EVENT_ITEM_INFO: /* Codec Info */
        event = new IMEvent( IMEvent::InfoChanged );
        break;

    case INPUT_EVENT_AUDIO_DELAY:
    case INPUT_EVENT_SUBTITLE_DELAY:
        event = new IMEvent( IMEvent::SynchroChanged );
        break;

    case INPUT_EVENT_CACHE:
        event = new IMEvent( IMEvent::CachingEvent );
        break;

    case INPUT_EVENT_BOOKMARK:
        event = new IMEvent( IMEvent::BookmarksChanged );
        break;

    case INPUT_EVENT_RECORD:
        event = new IMEvent( IMEvent::RecordingEvent );
        break;

    case INPUT_EVENT_PROGRAM:
        /* This is for PID changes */
        event = new IMEvent( IMEvent::ProgramChanged );
        break;

    case INPUT_EVENT_ITEM_EPG:
        /* EPG data changed */
        event = new IMEvent( IMEvent::EPGEvent );
        break;

    case INPUT_EVENT_SIGNAL:
        /* This is for capture-card signals */
        /* event = new IMEvent( SignalChanged_Type );
        break; */
    default:
        event = NULL;
        break;
    }

    if( event )
        QApplication::postEvent( im, event );
    return VLC_SUCCESS;
}

static int VbiEvent( vlc_object_t *, const char *,
                     vlc_value_t, vlc_value_t, void *param )
{
    InputManager *im = (InputManager*)param;
    IMEvent *event = new IMEvent( IMEvent::ItemTeletextChanged );

    QApplication::postEvent( im, event );
    return VLC_SUCCESS;
}

void InputManager::UpdatePosition()
{
    /* Update position */
    int64_t i_length = var_GetInteger(  p_input , "length" );
    int64_t i_time = var_GetInteger(  p_input , "time");
    float f_pos = var_GetFloat(  p_input , "position" );
    emit positionUpdated( f_pos, i_time, i_length / CLOCK_FREQ );
}

void InputManager::UpdateNavigation()
{
    /* Update navigation status */
    vlc_value_t val; val.i_int = 0;
    vlc_value_t val2; val2.i_int = 0;

    var_Change( p_input, "title", VLC_VAR_CHOICESCOUNT, &val, NULL );

    if( val.i_int > 0 )
    {
        bool b_menu = false;
        if( val.i_int > 1 )
        {
            input_title_t **pp_title = NULL;
            int i_title = 0;
            if( input_Control( p_input, INPUT_GET_FULL_TITLE_INFO, &pp_title, &i_title ) == VLC_SUCCESS )
            {
                for( int i = 0; i < i_title; i++ )
                {
                    if( pp_title[i]->i_flags & INPUT_TITLE_MENU )
                        b_menu = true;
                    vlc_input_title_Delete(pp_title[i]);
                }
                free( pp_title );
            }
        }

        /* p_input != NULL since val.i_int != 0 */
        var_Change( p_input, "chapter", VLC_VAR_CHOICESCOUNT, &val2, NULL );

        emit titleChanged( b_menu );
        emit chapterChanged( val2.i_int > 1 );
    }
    else
        emit chapterChanged( false );

    if( hasInput() )
        emit inputCanSeek( var_GetBool( p_input, "can-seek" ) );
    else
        emit inputCanSeek( false );
}

void InputManager::UpdateStatus()
{
    /* Update playing status */
    int state = var_GetInteger( p_input, "state" );
    if( i_old_playing_status != state )
    {
        i_old_playing_status = state;
        emit playingStatusChanged( state );
    }
}

void InputManager::UpdateRate()
{
    /* Update Rate */
    float f_new_rate = var_GetFloat( p_input, "rate" );
    if( f_new_rate != f_rate )
    {
        f_rate = f_new_rate;
        /* Update rate */
        emit rateChanged( f_rate );
    }
}

void InputManager::UpdateName()
{
    /* Update text, name and nowplaying */
    QString name;

    /* Try to get the nowplaying */
    char *format = var_InheritString( p_intf, "input-title-format" );
    char *formatted = NULL;
    if (format != NULL)
    {
        formatted = vlc_strfinput( p_input, format );
        free( format );
        if( formatted != NULL )
        {
            name = qfu(formatted);
            free( formatted );
        }
    }

    /* If we have Nothing */
    if( name.simplified().isEmpty() )
    {
        char *uri = input_item_GetURI( input_GetItem( p_input ) );
        char *file = uri ? strrchr( uri, '/' ) : NULL;
        if( file != NULL )
        {
            vlc_uri_decode( ++file );
            name = qfu(file);
        }
        else
            name = qfu(uri);
        free( uri );
    }

    name = name.trimmed();

    if( oldName != name )
    {
        emit nameChanged( name );
        oldName = name;
    }
}

int InputManager::playingStatus() const
{
    return i_old_playing_status;
}

bool InputManager::hasAudio()
{
    if( hasInput() )
    {
        vlc_value_t val;
        var_Change( p_input, "audio-es", VLC_VAR_CHOICESCOUNT, &val, NULL );
        return val.i_int > 0;
    }
    return false;
}

bool InputManager::hasVisualisation()
{
    if( !p_input )
        return false;

    audio_output_t *aout = input_GetAout( p_input );
    if( !aout )
        return false;

    char *visual = var_InheritString( aout, "visual" );
    vlc_object_release( aout );

    if( !visual )
        return false;

    free( visual );
    return true;
}

void InputManager::UpdateTeletext()
{
    const bool b_enabled = var_CountChoices( p_input, "teletext-es" ) > 0;
    const int i_teletext_es = var_GetInteger( p_input, "teletext-es" );

    /* Teletext is possible. Show the buttons */
    emit teletextPossible( b_enabled );

    /* If Teletext is selected */
    if( b_enabled && i_teletext_es >= 0 )
    {
        /* Then, find the current page */
        int i_page = 100;
        bool b_transparent = false;

        if( p_input_vbi )
        {
            var_DelCallback( p_input_vbi, "vbi-page", VbiEvent, this );
            vlc_object_release( p_input_vbi );
        }

        if( input_GetEsObjects( p_input, i_teletext_es, &p_input_vbi, NULL, NULL ) )
            p_input_vbi = NULL;

        if( p_input_vbi )
        {
            /* This callback is not remove explicitly, but interfaces
             * are guaranted to outlive input */
            var_AddCallback( p_input_vbi, "vbi-page", VbiEvent, this );

            i_page = var_GetInteger( p_input_vbi, "vbi-page" );
            b_transparent = !var_GetBool( p_input_vbi, "vbi-opaque" );
        }
        emit newTelexPageSet( i_page );
        emit teletextTransparencyActivated( b_transparent );

    }
    emit teletextActivated( b_enabled && i_teletext_es >= 0 );
}

void InputManager::UpdateEPG()
{
    emit epgChanged();
}

void InputManager::UpdateVout()
{
    size_t i_vout;
    vout_thread_t **pp_vout;

    if( !p_input )
        return;

    /* Get current vout lists from input */
    if( input_Control( p_input, INPUT_GET_VOUTS, &pp_vout, &i_vout ) )
    {
        i_vout = 0;
        pp_vout = NULL;
    }

    /* */
    emit voutListChanged( pp_vout, i_vout );

    /* */
    bool b_old_video = b_video;
    b_video = i_vout > 0;
    if( !!b_old_video != !!b_video )
        emit voutChanged( b_video );

    /* Release the vout list */
    for( size_t i = 0; i < i_vout; i++ )
        vlc_object_release( (vlc_object_t*)pp_vout[i] );
    free( pp_vout );
}

void InputManager::UpdateAout()
{
    /* TODO */
}

void InputManager::UpdateCaching()
{
    float f_newCache = var_GetFloat ( p_input, "cache" );
    if( f_newCache != f_cache )
    {
        f_cache = f_newCache;
        /* Update cache */
        emit cachingChanged( f_cache );
    }
}

void InputManager::requestArtUpdate( input_item_t *p_item, bool b_forced )
{
    bool b_current_item = false;
    if ( !p_item && hasInput() )
    {   /* default to current item */
        p_item = input_GetItem( p_input );
        b_current_item = true;
    }

    if ( p_item )
    {
        /* check if it has already been enqueued */
        if ( p_item->p_meta && !b_forced )
        {
            int status = vlc_meta_GetStatus( p_item->p_meta );
            if ( status & ( ITEM_ART_NOTFOUND|ITEM_ART_FETCHED ) )
                return;
        }
        libvlc_ArtRequest( p_intf->obj.libvlc, p_item,
                           (b_forced) ? META_REQUEST_OPTION_SCOPE_ANY
                                      : META_REQUEST_OPTION_NONE );
        /* No input will signal the cover art to update,
             * let's do it ourself */
        if ( b_current_item )
            UpdateArt();
        else
            emit artChanged( p_item );
    }
}

const QString InputManager::decodeArtURL( input_item_t *p_item )
{
    assert( p_item );

    char *psz_art = input_item_GetArtURL( p_item );
    if( psz_art )
    {
        char *psz = vlc_uri2path( psz_art );
        free( psz_art );
        psz_art = psz;
    }

#if 0
    /* Taglib seems to define a attachment://, It won't work yet */
    url = url.replace( "attachment://", "" );
#endif

    QString path = qfu( psz_art ? psz_art : "" );
    free( psz_art );
    return path;
}

void InputManager::UpdateArt()
{
    QString url = decodeArtURL( input_GetItem( p_input ) );

    /* the art hasn't changed, no need to update */
    if(artUrl == url)
        return;

    /* Update Art meta */
    artUrl = url;
    emit artChanged( artUrl );
}

void InputManager::setArt( input_item_t *p_item, QString fileUrl )
{
    if( hasInput() )
    {
        char *psz_cachedir = config_GetUserDir( VLC_CACHE_DIR );
        QString old_url = p_mim->getIM()->decodeArtURL( p_item );
        old_url = QDir( old_url ).canonicalPath();

        if( old_url.startsWith( QString::fromUtf8( psz_cachedir ) ) )
            QFile( old_url ).remove(); /* Purge cached artwork */

        free( psz_cachedir );

        input_item_SetArtURL( p_item , fileUrl.toUtf8().constData() );
        UpdateArt();
    }
}

inline void InputManager::UpdateStats()
{
    emit statisticsUpdated( input_GetItem( p_input ) );
}

inline void InputManager::UpdateMeta( input_item_t *p_item_ )
{
    emit metaChanged( p_item_ );
    emit artChanged( p_item_ );
}

inline void InputManager::UpdateMeta()
{
    emit currentMetaChanged( input_GetItem( p_input ) );
}

inline void InputManager::UpdateInfo()
{
    assert( p_input );
    emit infoChanged( input_GetItem( p_input ) );
}

void InputManager::UpdateRecord()
{
    bool b_recording = var_GetBool( p_input, "record" );
    /* the core may have ended a clip recording itself (record-stop-time) */
    if( !b_recording )
        b_clipRecording = false;
    emit recordingStateChanged( b_recording );
}

void InputManager::UpdateProgramEvent()
{
    bool b_scrambled = var_GetBool( p_input, "program-scrambled" );
    emit encryptionChanged( b_scrambled );
}

/* User update of the slider */
void InputManager::sliderUpdate( float new_pos )
{
    if( b_clipMode )
        queueClipPreview( new_pos );
    else
    {
        if( hasInput() )
            var_SetFloat( p_input, "position", new_pos );
        emit seekRequested( new_pos );
    }
}

void InputManager::sectionPrev()
{
    if( hasInput() )
    {
        int i_type = var_Type( p_input, "next-chapter" );
        var_TriggerCallback( p_input, (i_type & VLC_VAR_TYPE) != 0 ?
                             "prev-chapter":"prev-title" );
    }
}

void InputManager::sectionNext()
{
    if( hasInput() )
    {
        int i_type = var_Type( p_input, "next-chapter" );
        var_TriggerCallback( p_input, (i_type & VLC_VAR_TYPE) != 0 ?
                             "next-chapter":"next-title" );
    }
}

void InputManager::sectionMenu()
{
    if( hasInput() )
    {
        var_TriggerCallback( p_input, "menu-title" );
    }
}

/* Blu-ray pop-up menu, drawn over the running movie (unlike the disc root
 * menu of sectionMenu()) */
void InputManager::discPopupMenu()
{
    if( hasInput() )
    {
        input_ShowPopupMenu( p_input );
    }
}

/*
 *  Teletext Functions
 */

void InputManager::changeProgram( int program )
{
    if( hasInput() )
    {
        var_SetInteger( p_input, "program", program );
    }
}

/* Set a new Teletext Page */
void InputManager::telexSetPage( int page )
{
    if( hasInput() && p_input_vbi )
    {
        const int i_teletext_es = var_GetInteger( p_input, "teletext-es" );

        if( i_teletext_es >= 0 )
        {
            var_SetInteger( p_input_vbi, "vbi-page", page );
            emit newTelexPageSet( page );
        }
    }
}

/* Set the transparency on teletext */
void InputManager::telexSetTransparency( bool b_transparentTelextext )
{
    if( hasInput() && p_input_vbi )
    {
        var_SetBool( p_input_vbi, "vbi-opaque", !b_transparentTelextext );
        emit teletextTransparencyActivated( b_transparentTelextext );
    }
}

void InputManager::activateTeletext( bool b_enable )
{
    vlc_value_t list;
    vlc_value_t text;
    if( hasInput() && !var_Change( p_input, "teletext-es", VLC_VAR_GETCHOICES, &list, &text ) )
    {
        if( list.p_list->i_count > 0 )
        {
            /* Prefer the page 100 if it is present */
            int i;
            for( i = 0; i < text.p_list->i_count; i++ )
            {
                /* The description is the page number as a string */
                const char *psz_page = text.p_list->p_values[i].psz_string;
                if( psz_page && !strcmp( psz_page, "100" ) )
                    break;
            }
            if( i >= list.p_list->i_count )
                i = 0;
            var_SetInteger( p_input, "spu-es", b_enable ? list.p_list->p_values[i].i_int : -1 );
        }
        var_FreeList( &list, &text );
    }
}

void InputManager::reverse()
{
    if( hasInput() )
    {
        float f_rate_ = var_GetFloat( p_input, "rate" );
        var_SetFloat( p_input, "rate", -f_rate_ );
    }
}

void InputManager::slower()
{
    var_SetInteger( p_intf->obj.libvlc, "key-action", ACTIONID_SLOWER );
}

void InputManager::faster()
{
    var_SetInteger( p_intf->obj.libvlc, "key-action", ACTIONID_FASTER );
}

void InputManager::littlefaster()
{
    var_SetInteger( p_intf->obj.libvlc, "key-action", ACTIONID_RATE_FASTER_FINE );
}

void InputManager::littleslower()
{
    var_SetInteger( p_intf->obj.libvlc, "key-action", ACTIONID_RATE_SLOWER_FINE );
}

void InputManager::normalRate()
{
    var_SetFloat( THEPL, "rate", 1. );
}

void InputManager::setRate( int new_rate )
{
    var_SetFloat( THEPL, "rate",
                 (float)INPUT_RATE_DEFAULT / (float)new_rate );
}

void InputManager::jumpFwd()
{
    int i_interval = var_InheritInteger( p_input, "short-jump-size" );
    if( i_interval > 0 && hasInput() )
    {
        vlc_tick_t val = CLOCK_FREQ * i_interval;
        var_SetInteger( p_input, "time-offset", val );
    }
}

void InputManager::jumpBwd()
{
    int i_interval = var_InheritInteger( p_input, "short-jump-size" );
    if( i_interval > 0 && hasInput() )
    {
        vlc_tick_t val = -CLOCK_FREQ * i_interval;
        var_SetInteger( p_input, "time-offset", val );
    }
}

void InputManager::setAtoB()
{
    if( !timeA )
    {
        timeA = var_GetInteger( p_mim->getInput(), "time"  );
    }
    else if( !timeB )
    {
        timeB = var_GetInteger( p_mim->getInput(), "time"  );
        var_SetInteger( p_mim->getInput(), "time" , timeA );
        connect( this, &InputManager::positionUpdated,
                 this, &InputManager::AtoBLoop );
    }
    else
    {
        timeA = 0;
        timeB = 0;
        disconnect( this, &InputManager::positionUpdated,
                    this, &InputManager::AtoBLoop );
    }
    emit AtoBchanged( (timeA != 0 ), (timeB != 0 ) );
}

/* Function called regularly when in an AtoB loop */
void InputManager::AtoBLoop( float, int64_t i_time, int )
{
    if( timeB && i_time >= timeB )
        var_SetInteger( p_mim->getInput(), "time" , timeA );
}

/**********************************************************************
 * Clip creation mode (PowerVLC): both seek bar knobs define the clip
 * bounds with instant preview; Record then saves exactly that range,
 * bounded core-side by "record-clip-position" / "record-stop-time".
 **********************************************************************/

void InputManager::toggleClipCreationMode()
{
    if( b_clipMode )
    {
        exitClipCreationMode();
        return;
    }

    if( !p_input || !var_GetBool( p_input, "can-seek" ) )
        return;

    double pos = var_GetFloat( p_input, "position" );
    int64_t duration = var_GetInteger( p_input, "length" );

    /* place the end knob right next to the start knob: 10 seconds ahead,
     * bounded to stay between 1% and 5% of the item */
    double delta = 0.05;
    if( duration > 0 )
    {
        delta = (double)(10 * CLOCK_FREQ) / (double)duration;
        delta = qBound( 0.01, delta, 0.05 );
    }

    f_clipStart = qBound( 0., pos, 1. );
    f_clipEnd = qMin( f_clipStart + delta, 1. );
    f_clipLastPos = -1.;
    i_clipPausedAtEnd = 0;
    /* the frame-step shortcuts default to the end bound, like the two
     * macOS interfaces */
    i_clipSelectedKnob = 2;
    clipPreviewTimer->stop();
    b_clipPreviewPending = false;
    f_clipPreviewTarget = pos;
    b_clipMode = true;

    /* hotkeys -> interface channel for the frame-step shortcuts */
    var_Create( p_input, "clip-frame-step",
                VLC_VAR_INTEGER | VLC_VAR_ISCOMMAND );
    var_AddCallback( p_input, "clip-frame-step", ClipStepCallback, this );

    connect( this, &InputManager::positionUpdated,
             this, &InputManager::clipModeLoop );
    emit clipCreationModeChanged( true );
}

void InputManager::exitClipCreationMode()
{
    if( !b_clipMode )
        return;

    /* a running extraction has no reason to survive the mode */
    if( p_clipExport )
        finishClipExport( true );

    if( p_input )
    {
        var_SetInteger( p_input, "record-stop-time", 0 );
        var_SetInteger( p_input, "record-start-time", 0 );
        if( b_clipRecording )
            var_SetBool( p_input, "record", false );
    }
    if( p_input && var_Type( p_input, "clip-frame-step" ) != 0 )
    {
        var_DelCallback( p_input, "clip-frame-step", ClipStepCallback, this );
        var_Destroy( p_input, "clip-frame-step" );
    }
    /* Do not lose the exact last pixel/frame if the mode is closed inside
     * the 33 ms trailing window. */
    flushClipPreview();
    clipPreviewTimer->stop();

    b_clipRecording = false;
    b_clipMode = false;
    i_clipPausedAtEnd = 0;

    disconnect( this, &InputManager::positionUpdated,
                this, &InputManager::clipModeLoop );
    emit clipCreationModeChanged( false );
}

void InputManager::setClipStartPosition( double pos )
{
    f_clipStart = qBound( 0., pos, 1. );
}

void InputManager::setClipEndPosition( double pos )
{
    f_clipEnd = qBound( 0., pos, 1. );

    /* follow a live adjustment of the end bound during a clip recording */
    if( b_clipRecording && p_input )
    {
        int64_t duration = var_GetInteger( p_input, "length" );
        if( duration > 0 )
            var_SetInteger( p_input, "record-stop-time",
                            (int64_t)( f_clipEnd * (double)duration ) );
    }
}

/* One-frame nudge of the last-selected bound, for surgical trimming.
 * Falls back to 25 fps when the demux did not expose a frame rate. */
void InputManager::clipStepFrames( int direction )
{
    if( !p_input )
        return;

    double frameSec = 1. / 25.;
    input_item_t *p_item_ = input_GetItem( p_input );
    if( p_item_ )
    {
        vlc_mutex_lock( &p_item_->lock );
        for( int i = 0; i < p_item_->i_es; i++ )
        {
            const es_format_t *fmt = p_item_->es[i];
            if( fmt->i_cat == VIDEO_ES && fmt->video.i_frame_rate > 0
             && fmt->video.i_frame_rate_base > 0 )
            {
                frameSec = (double)fmt->video.i_frame_rate_base
                         / (double)fmt->video.i_frame_rate;
                break;
            }
        }
        vlc_mutex_unlock( &p_item_->lock );
    }
    clipNudgeSelectedBoundBySeconds( direction * frameSec );
}

/* Move the selected bound by a signed amount of seconds and preview it. */
void InputManager::clipNudgeSelectedBoundBySeconds( double seconds )
{
    if( !p_input )
        return;
    int64_t duration = var_GetInteger( p_input, "length" );
    if( duration <= 0 )
        return;

    double step = seconds * (double)CLOCK_FREQ / (double)duration;
    double target;
    if( i_clipSelectedKnob == 1 )
    {
        target = qBound( 0., f_clipStart + step, f_clipEnd );
        f_clipStart = target;
    }
    else
    {
        target = qBound( f_clipStart, f_clipEnd + step, 1. );
        /* the setter follows a live recording's record-stop-time */
        setClipEndPosition( target );
    }
    noteClipInteraction();

    queueClipPreview( target );
}

/* A jump shortcut the core hotkeys module redirected to us (Qt thread). */
void InputManager::clipStepFromCore( qint64 value )
{
    if( !b_clipMode )
        return;
    /* small value = a count of frames (it ramps up while the key is held),
     * larger = microseconds; see the convention in hotkeys.c */
    if( value != 0 && value >= -1000 && value <= 1000 )
        clipStepFrames( (int)value );
    else
        clipNudgeSelectedBoundBySeconds( (double)value / CLOCK_FREQ );
}

void InputManager::noteClipInteraction()
{
    clipLastInteractionMs = QDateTime::currentMSecsSinceEpoch();
    /* touching a bound invalidates a pending "parked at the end bound":
     * the next play must resume normally, not jump back to the start */
    i_clipPausedAtEnd = 0;
}

/* Accurate seeks are much slower than Windows mouse/touch/key-repeat events.
 * Sending every raw event simply flushes the decoder again before its first
 * requested picture can reach the vout.  Send the leading edge immediately,
 * then coalesce to the newest target at roughly one 30-fps display interval.
 * A lone arrow press therefore remains immediate, while a drag remains live
 * and always finishes on its exact last position. */
void InputManager::queueClipPreview( double position )
{
    f_clipPreviewTarget = qBound( 0., position, 1. );
    if( clipPreviewTimer->isActive() )
    {
        b_clipPreviewPending = true;
        return;
    }

    b_clipPreviewPending = false;
    sendClipPreview( f_clipPreviewTarget );
    clipPreviewTimer->start();
}

void InputManager::sendClipPreview( double position )
{
    if( p_input )
        var_SetFloat( p_input, "position", (float)position );
    emit seekRequested( (float)position );
}

void InputManager::flushClipPreview()
{
    if( !b_clipPreviewPending )
        return;

    clipPreviewTimer->stop();
    b_clipPreviewPending = false;
    sendClipPreview( f_clipPreviewTarget );
}

void InputManager::clipPreviewTimeout()
{
    if( !b_clipMode || !b_clipPreviewPending )
        return;

    b_clipPreviewPending = false;
    sendClipPreview( f_clipPreviewTarget );
    clipPreviewTimer->start();
}

/* Message on the video and in the log: a fast extraction is over in a
 * blink and the user needs to be told where it went. */
void InputManager::clipExportNotify( const QString &message )
{
    if( p_input )
    {
        vout_thread_t *p_vout = input_GetVout( p_input );
        if( p_vout )
        {
            /* ⚠ vout_OSDMessage() would show it for ONE second in the top
             * right corner. A fast export is over in a blink and this
             * message is the only sign it happened at all, while the user
             * is looking at the bottom of the window, where the bounds and
             * the record button are: one second there is one second not
             * looked at (missed on the Windows bench). Three, then, same
             * place as everything else the OSD says. */
            vout_OSDText( p_vout, VOUT_SPU_CHANNEL_OSD,
                          SUBPICTURE_ALIGN_TOP | SUBPICTURE_ALIGN_RIGHT,
                          3 * CLOCK_FREQ, qtu( message ) );
            vlc_object_release( p_vout );
        }
    }
    msg_Info( p_intf, "%s", qtu( message ) );
}

/* Extracts [A..B] through a second headless input, at disk speed and
 * without touching the playback. false when the core cannot extract from
 * this input (live stream, unknown length): record it live instead. */
bool InputManager::startClipExport()
{
    if( p_clipExport )
        return true;

    int64_t duration = var_GetInteger( p_input, "length" );
    if( duration <= 0 )
        return false;

    p_clipExport = input_ClipExportNew( p_intf, p_input,
                        (vlc_tick_t)( f_clipStart * (double)duration ),
                        (vlc_tick_t)( f_clipEnd * (double)duration ) );
    if( !p_clipExport )
        return false;

    clipExportTimer->start();
    clipExportNotify( qtr( "Exporting clip…" ) );
    return true;
}

void InputManager::finishClipExport( bool b_cancelled )
{
    if( !p_clipExport )
        return;

    clipExportTimer->stop();
    char *psz_file = input_ClipExportFinish( p_clipExport );
    p_clipExport = NULL;

    if( b_cancelled )
        clipExportNotify( qtr( "Clip export cancelled" ) );
    else if( psz_file )
        clipExportNotify( qtr( "Clip saved:" ) + " "
                          + QFileInfo( qfu( psz_file ) ).fileName() );
    else
        clipExportNotify( qtr( "Clip export failed" ) );
    free( psz_file );
}

void InputManager::clipExportPoll()
{
    if( p_clipExport && !input_ClipExportIsRunning( p_clipExport ) )
        finishClipExport( false );
}

void InputManager::recordClipToggle()
{
    if( !p_input )
        return;

    if( p_clipExport )
    {
        /* a fast extraction is running: give it up */
        finishClipExport( true );
        return;
    }

    if( b_clipRecording )
    {
        /* cancel the running clip recording */
        var_SetInteger( p_input, "record-stop-time", 0 );
        var_SetInteger( p_input, "record-start-time", 0 );
        var_SetBool( p_input, "record", false );
        b_clipRecording = false;
        return;
    }

    /* extracted at disk speed by a second input when the media allows it;
     * the playback the user is watching is not disturbed at all */
    if( startClipExport() )
        return;

    /* arm the demux-paced stop bound, then let the core seek to the clip
     * start and start recording in ONE input control */
    int64_t duration = var_GetInteger( p_input, "length" );
    var_SetInteger( p_input, "record-stop-time",
                    duration > 0
                        ? (int64_t)( f_clipEnd * (double)duration ) : 0 );
    var_SetInteger( p_input, "record-start-time",
                    duration > 0
                        ? (int64_t)( f_clipStart * (double)duration ) : 0 );
    var_SetFloat( p_input, "record-clip-position", (float)f_clipStart );
    b_clipRecording = true;

    if( var_GetInteger( p_input, "state" ) == PAUSE_S )
        playlist_TogglePause( THEPL );
}

/* Function called regularly while in clip creation mode. Keeps the preview
 * inside [A..B] exactly like the two macOS interfaces: never before A,
 * never past B, and playing again after the end-bound pause replays the
 * clip from A. i_length is in SECONDS (see the positionUpdated emitter). */
void InputManager::clipModeLoop( float pos, int64_t, int i_length )
{
    if( !p_input )
        return;

    int state = var_GetInteger( p_input, "state" );

    /* end-bound pause state machine, see the i_clipPausedAtEnd comment */
    if( i_clipPausedAtEnd == 1 && state == PAUSE_S )
        i_clipPausedAtEnd = 2;
    else if( i_clipPausedAtEnd == 2 && state == PLAYING_S )
    {
        /* resumed by any path (button, hotkey, another interface): the
         * clip replays from its start bound */
        i_clipPausedAtEnd = 0;
        var_SetFloat( p_input, "position", (float)f_clipStart );
        f_clipLastPos = f_clipStart;
        return;
    }

    /* one second as a fraction of the media, 0 when the length is unknown */
    double posPerSec = i_length > 0 ? 1. / (double)i_length : 0.;

    /* A bound sitting at the very END of the media cannot be caught by the
     * poll: nothing is ever sampled between it and EOF, so the input runs
     * out, the item ends and the mode goes with it. Pause a hair earlier in
     * that case -- but NEVER while recording, where the exact stop belongs
     * to the core (record-stop-time, on the raw demux clock) and pulling the
     * preview back would truncate the clip. */
    double endBound = f_clipEnd;
    if( !b_clipRecording && posPerSec > 0. )
    {
        double lastSafe = 1. - 0.5 * posPerSec;
        if( endBound > lastSafe )
            endBound = lastSafe;
    }

    /* The playback must never run OUTSIDE [A..B]: before A it is pulled
     * back to A, at B it pauses. A LEVEL test, not the crossing it used to
     * be. Suppressed right after a knob interaction: dragging a bound seeks
     * repeatedly around it and must not leave the player paused. */
    bool interacting = ( QDateTime::currentMSecsSinceEpoch()
                         - clipLastInteractionMs ) < 500;
    if( !interacting && state == PLAYING_S )
    {
        if( posPerSec > 0. && pos < f_clipStart - 0.25 * posPerSec )
        {
            var_SetFloat( p_input, "position", (float)f_clipStart );
            f_clipLastPos = f_clipStart;
            return;
        }
        if( pos >= endBound )
        {
            if( b_clipRecording )
            {
                /* backstop -- the core normally ended it at the bound */
                var_SetBool( p_input, "record", false );
                b_clipRecording = false;
            }
            playlist_Pause( THEPL );
            i_clipPausedAtEnd = 1;
        }
    }
    f_clipLastPos = pos;
}

/**********************************************************************
 * MainInputManager implementation. Wrap an input manager and
 * take care of updating the main playlist input.
 * Used in the main playlist Dialog
 **********************************************************************/

MainInputManager::MainInputManager( intf_thread_t *_p_intf )
    : QObject(NULL), p_input( NULL), p_intf( _p_intf ),
      random( VLC_OBJECT(THEPL), "random" ),
      repeat( VLC_OBJECT(THEPL), "repeat" ), loop( VLC_OBJECT(THEPL), "loop" ),
      volume( VLC_OBJECT(THEPL), "volume" ), mute( VLC_OBJECT(THEPL), "mute" )
{
    im = new InputManager( this, p_intf );

    /* Audio Menu */
    menusAudioMapper = new QSignalMapper();
    connect( menusAudioMapper, QSIGNALMAPPER_MAPPEDSTR_SIGNAL, this, &MainInputManager::menusUpdateAudio );

    /* Core Callbacks */
    var_AddCallback( THEPL, "item-change", MainInputManager::ItemChanged, im );
    var_AddCallback( THEPL, "input-current", MainInputManager::PLItemChanged, this );
    var_AddCallback( THEPL, "leaf-to-parent", MainInputManager::LeafToParent, this );
    var_AddCallback( THEPL, "playlist-item-append", MainInputManager::PLItemAppended, this );
    var_AddCallback( THEPL, "playlist-item-deleted", MainInputManager::PLItemRemoved, this );

    /* Core Callbacks to widget */
    random.addCallback( this, SLOT(notifyRandom(bool)) );
    repeat.addCallback( this, SLOT(notifyRepeatLoop(bool)) );
    loop.addCallback(   this, SLOT(notifyRepeatLoop(bool)) );
    volume.addCallback( this, SLOT(notifyVolume(float)) );
    mute.addCallback(   this, SLOT(notifyMute(bool)) );

    /* Warn our embedded IM about input changes */
    connect( this, &MainInputManager::inputChanged,
             im, &InputManager::inputChangedHandler, Qt::DirectConnection );
}

MainInputManager::~MainInputManager()
{
    if( p_input )
    {
       vlc_object_release( p_input );
       p_input = NULL;
       emit inputChanged( false );
    }

    var_DelCallback( THEPL, "input-current", MainInputManager::PLItemChanged, this );
    var_DelCallback( THEPL, "item-change", MainInputManager::ItemChanged, im );
    var_DelCallback( THEPL, "leaf-to-parent", MainInputManager::LeafToParent, this );

    var_DelCallback( THEPL, "playlist-item-append", MainInputManager::PLItemAppended, this );
    var_DelCallback( THEPL, "playlist-item-deleted", MainInputManager::PLItemRemoved, this );

    delete menusAudioMapper;
}

vout_thread_t* MainInputManager::getVout()
{
    return p_input ? input_GetVout( p_input ) : NULL;
}

QVector<vout_thread_t*> MainInputManager::getVouts() const
{
    vout_thread_t **pp_vout;
    size_t i_vout;

    if( p_input == NULL
     || input_Control( p_input, INPUT_GET_VOUTS, &pp_vout, &i_vout ) != VLC_SUCCESS
     || i_vout == 0 )
        return QVector<vout_thread_t*>();

    QVector<vout_thread_t*> vector = QVector<vout_thread_t*>();
    vector.reserve( i_vout );
    for( size_t i = 0; i < i_vout; i++ )
    {
        assert( pp_vout[i] );
        vector.append( pp_vout[i] );
    }
    free( pp_vout );

    return vector;
}

audio_output_t * MainInputManager::getAout()
{
    return playlist_GetAout( THEPL );
}

void MainInputManager::customEvent( QEvent *event )
{
    int type = event->type();

    PLEvent *plEv;

    // msg_Dbg( p_intf, "New MainIM Event of type: %i", type );
    switch( type )
    {
    case PLEvent::PLItemAppended:
        plEv = static_cast<PLEvent*>( event );
        emit playlistItemAppended( plEv->getItemId(), plEv->getParentId() );
        return;
    case PLEvent::PLItemRemoved:
        plEv = static_cast<PLEvent*>( event );
        emit playlistItemRemoved( plEv->getItemId() );
        return;
    case PLEvent::PLEmpty:
        plEv = static_cast<PLEvent*>( event );
        emit playlistNotEmpty( plEv->getItemId() >= 0 );
        return;
    case PLEvent::LeafToParent:
        plEv = static_cast<PLEvent*>( event );
        emit leafBecameParent( plEv->getItemId() );
        return;
    default:
        if( type != IMEvent::ItemChanged ) return;
    }
    probeCurrentInput();
}

void MainInputManager::probeCurrentInput()
{
    if( p_input != NULL )
        vlc_object_release( p_input );
    p_input = playlist_CurrentInput( THEPL );
    emit inputChanged( p_input != NULL );
}

/* Playlist Control functions */
void MainInputManager::stop()
{
   playlist_Stop( THEPL );
}

void MainInputManager::next()
{
   playlist_Next( THEPL );
}

void MainInputManager::prev()
{
   playlist_Prev( THEPL );
}

void MainInputManager::prevOrReset()
{
    if( !p_input || var_GetInteger( p_input, "time") < INT64_C(10000) )
        playlist_Prev( THEPL );
    else
        getIM()->sliderUpdate( 0.0 );
}

void MainInputManager::togglePlayPause()
{
    playlist_TogglePause( THEPL );
}

void MainInputManager::play()
{
    playlist_Play( THEPL );
}

void MainInputManager::pause()
{
    playlist_Pause( THEPL );
}

void MainInputManager::toggleRandom()
{
    config_PutInt( p_intf, "random", var_ToggleBool( THEPL, "random" ) );
}

void MainInputManager::notifyRandom(bool value)
{
    emit randomChanged(value);
}

void MainInputManager::notifyRepeatLoop(bool)
{
    int i_state = NORMAL;

    if( var_GetBool( THEPL, "loop" ) )   i_state = REPEAT_ALL;
    if( var_GetBool( THEPL, "repeat" ) ) i_state = REPEAT_ONE;

    emit repeatLoopChanged( i_state );
}

void MainInputManager::loopRepeatLoopStatus()
{
    /* Toggle Normal -> Loop -> Repeat -> Normal ... */
    bool loop = var_GetBool( THEPL, "loop" );
    bool repeat = var_GetBool( THEPL, "repeat" );

    if( repeat )
    {
        loop = false;
        repeat = false;
    }
    else if( loop )
    {
        loop = false;
        repeat = true;
    }
    else
    {
        loop = true;
        //repeat = false;
    }

    var_SetBool( THEPL, "loop", loop );
    var_SetBool( THEPL, "repeat", repeat );
    config_PutInt( p_intf, "loop", loop );
    config_PutInt( p_intf, "repeat", repeat );
}

void MainInputManager::activatePlayQuit( bool b_exit )
{
    var_SetBool( THEPL, "play-and-exit", b_exit );
    config_PutInt( p_intf, "play-and-exit", b_exit );
}

bool MainInputManager::getPlayExitState()
{
    return var_InheritBool( THEPL, "play-and-exit" );
}

bool MainInputManager::hasEmptyPlaylist()
{
    playlist_Lock( THEPL );
    bool b_empty = playlist_IsEmpty( THEPL );
    playlist_Unlock( THEPL );
    return b_empty;
}

/****************************
 * Static callbacks for MIM *
 ****************************/
int MainInputManager::PLItemChanged( vlc_object_t *, const char *,
                                     vlc_value_t, vlc_value_t, void *param )
{
    MainInputManager *mim = (MainInputManager*)param;

    IMEvent *event = new IMEvent( IMEvent::ItemChanged );
    QApplication::postEvent( mim, event );
    return VLC_SUCCESS;
}

int MainInputManager::LeafToParent( vlc_object_t *, const char *,
                                    vlc_value_t, vlc_value_t val, void *param )
{
    MainInputManager *mim = (MainInputManager*)param;

    PLEvent *event = new PLEvent( PLEvent::LeafToParent, val.i_int );

    QApplication::postEvent( mim, event );
    return VLC_SUCCESS;
}

void MainInputManager::notifyVolume( float volume )
{
    emit volumeChanged( volume );
}

void MainInputManager::notifyMute( bool mute )
{
    emit soundMuteChanged(mute);
}


void MainInputManager::menusUpdateAudio( const QString& data )
{
    audio_output_t *aout = getAout();
    if( aout != NULL )
    {
        aout_DeviceSet( aout, qtu(data) );
        vlc_object_release( aout );
    }
}

int MainInputManager::PLItemAppended( vlc_object_t *, const char *,
                                      vlc_value_t, vlc_value_t cur,
                                      void *data )
{
    MainInputManager *mim = static_cast<MainInputManager*>(data);
    playlist_item_t *item = static_cast<playlist_item_t *>( cur.p_address );

    PLEvent *event = new PLEvent( PLEvent::PLItemAppended, item->i_id,
        (item->p_parent != NULL) ? item->p_parent->i_id : -1  );
    QApplication::postEvent( mim, event );

    event = new PLEvent( PLEvent::PLEmpty, item->i_id, 0  );
    QApplication::postEvent( mim, event );
    return VLC_SUCCESS;
}

int MainInputManager::PLItemRemoved( vlc_object_t *obj, const char *,
                                     vlc_value_t, vlc_value_t cur, void *data )
{
    playlist_t *pl = (playlist_t *) obj;
    MainInputManager *mim = static_cast<MainInputManager*>(data);
    playlist_item_t *item = static_cast<playlist_item_t *>( cur.p_address );

    PLEvent *event = new PLEvent( PLEvent::PLItemRemoved, item->i_id, 0  );
    QApplication::postEvent( mim, event );
    // can't use playlist_IsEmpty(  ) as it isn't true yet
    if ( pl->items.i_size == 1 ) // lock is held
    {
        event = new PLEvent( PLEvent::PLEmpty, -1, 0 );
        QApplication::postEvent( mim, event );
    }
    return VLC_SUCCESS;
}

void MainInputManager::changeFullscreen( bool new_val )
{
    if ( var_GetBool( THEPL, "fullscreen" ) != new_val)
        var_SetBool( THEPL, "fullscreen", new_val );
}
