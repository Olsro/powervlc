/*****************************************************************************
 * recents.cpp : Recents MRL (menu)
 *****************************************************************************
 * Copyright © 2008-2014 VideoLAN and VLC authors
 * $Id$
 *
 * Authors: Ludovic Fauvet <etix@l0cal.com>
 *          Jean-baptiste Kempf <jb@videolan.org>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * ( at your option ) any later version.
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

#include "qt.hpp"
#include "recents.hpp"
#include "dialogs_provider.hpp"
#include "menus.hpp"
#include "util/qt_dirs.hpp"

#include <QStringList>
#include <QRegularExpression>
#include <QSignalMapper>
#include <QSettings>

#include "main_interface.hpp"

#ifdef _WIN32
    #include <shlobj.h>
    /* typedef enum  {
        SHARD_PIDL              = 0x00000001,
        SHARD_PATHA             = 0x00000002,
        SHARD_PATHW             = 0x00000003,
        SHARD_APPIDINFO         = 0x00000004,
        SHARD_APPIDINFOIDLIST   = 0x00000005,
        SHARD_LINK              = 0x00000006,
        SHARD_APPIDINFOLINK     = 0x00000007,
        SHARD_SHELLITEM         = 0x00000008
    } SHARD; */
    #define SHARD_PATHW 0x00000003

    #include <vlc_charset.h>
#endif

#include <vlc_input_item.h>
#include <vlc_url.h>

static bool isFileMRL( const QString &mrl )
{
    char *path = vlc_uri2path( qtu( mrl ) );
    if( !path )
        return false;
    free( path );
    return true;
}

RecentsMRL::RecentsMRL( intf_thread_t *_p_intf ) : p_intf( _p_intf )
{
    recentFiles = QStringList();
    recentStreams = QStringList();
    fileTimes = QStringList();
    streamTimes = QStringList();

    signalMapper = new QSignalMapper( this );
    connect( signalMapper,
            QSIGNALMAPPER_MAPPEDSTR_SIGNAL,
            this,
            &RecentsMRL::playMRL );

    /* Load the filter psz */
    char* psz_tmp = var_InheritString( p_intf, "qt-recentplay-filter" );
    if( psz_tmp && *psz_tmp )
        filter = new QRegularExpression( psz_tmp, QRegularExpression::CaseInsensitiveOption );
    else
        filter = NULL;
    free( psz_tmp );

    load();
    isActive = var_InheritBool( p_intf, "qt-recentplay" );
    if( !isActive ) clear();
}

RecentsMRL::~RecentsMRL()
{
    save();
    delete filter;
}

void RecentsMRL::addRecent( const QString &mrl )
{
    if ( !isActive || ( filter && filter->match( mrl ).hasMatch() ) )
        return;

    const bool file = isFileMRL( mrl );
    QStringList &list = file ? recentFiles : recentStreams;
    QStringList &times = file ? fileTimes : streamTimes;

#ifdef _WIN32
    /* Add local files to the Windows 7 default list in taskbar. */
    if( file )
    {
        char* path = vlc_uri2path( qtu( mrl ) );
        wchar_t *wmrl = ToWide( path );
        SHAddToRecentDocs( SHARD_PATHW, wmrl );
        free( wmrl );
        free( path );
    }
#endif

    int i_index = list.indexOf( mrl );
    if( 0 <= i_index )
    {
        /* move to the front */
        list.move( i_index, 0 );
        times.move( i_index, 0 );
    }
    else
    {
        list.prepend( mrl );
        times.prepend( "-1" );
        if( list.count() > RECENTS_LIST_SIZE ) {
            list.takeLast();
            times.takeLast();
        }
    }
    VLCMenuBar::updateRecents( p_intf );
    save();
}

void RecentsMRL::clear()
{
    if ( recentFiles.isEmpty() && recentStreams.isEmpty() )
        return;

    recentFiles.clear();
    recentStreams.clear();
    fileTimes.clear();
    streamTimes.clear();
    if( isActive ) VLCMenuBar::updateRecents( p_intf );
    save();
}

void RecentsMRL::clearFiles()
{
    if( recentFiles.isEmpty() )
        return;
    recentFiles.clear();
    fileTimes.clear();
    if( isActive ) VLCMenuBar::updateRecents( p_intf );
    save();
}

void RecentsMRL::clearStreams()
{
    if( recentStreams.isEmpty() )
        return;
    recentStreams.clear();
    streamTimes.clear();
    if( isActive ) VLCMenuBar::updateRecents( p_intf );
    save();
}

QStringList RecentsMRL::recentFileList()
{
    return recentFiles;
}

QStringList RecentsMRL::recentStreamList()
{
    return recentStreams;
}

void RecentsMRL::load()
{
    QSettings *settings = getSettings();
    const bool hasSplitHistory = settings->contains( "RecentsMRL/fileList" )
                              || settings->contains( "RecentsMRL/streamList" );
    QStringList files;
    QStringList streams;
    QStringList times;
    QStringList streamResumeTimes;

    if( hasSplitHistory )
    {
        files = settings->value( "RecentsMRL/fileList" ).toStringList();
        streams = settings->value( "RecentsMRL/streamList" ).toStringList();
        times = settings->value( "RecentsMRL/fileTimes" ).toStringList();
        streamResumeTimes = settings->value(
            "RecentsMRL/streamTimes" ).toStringList();
    }
    else
    {
        /* Migrate the mixed list used by earlier PowerVLC releases. */
        const QStringList oldList = settings->value( "RecentsMRL/list" ).toStringList();
        const QStringList oldTimes = settings->value( "RecentsMRL/times" ).toStringList();
        for( int i = 0; i < oldList.count(); ++i )
        {
            if( isFileMRL( oldList.at(i) ) )
            {
                files.append( oldList.at(i) );
                times.append( oldTimes.value(i, "-1") );
            }
            else
            {
                streams.append( oldList.at(i) );
                streamResumeTimes.append( oldTimes.value(i, "-1") );
            }
        }
    }

    /* Apply the configured privacy filter to both lists. */
    for( int i = 0; i < files.count(); ++i )
    {
        if ( !filter || !filter->match( files.at(i) ).hasMatch() ) {
            recentFiles.append( files.at(i) );
            fileTimes.append( times.value(i, "-1" ) );
        }
    }
    for( int i = 0; i < streams.count(); ++i )
    {
        if( !filter || !filter->match( streams.at(i) ).hasMatch() ) {
            recentStreams.append( streams.at(i) );
            streamTimes.append( streamResumeTimes.value(i, "-1" ) );
        }
    }
}

void RecentsMRL::save()
{
    QSettings *settings = getSettings();
    settings->setValue( "RecentsMRL/fileList", recentFiles );
    settings->setValue( "RecentsMRL/streamList", recentStreams );
    settings->setValue( "RecentsMRL/fileTimes", fileTimes );
    settings->setValue( "RecentsMRL/streamTimes", streamTimes );
    settings->remove( "RecentsMRL/list" );
    settings->remove( "RecentsMRL/times" );
}

void RecentsMRL::playMRL( const QString &mrl )
{
    /* Entries created by Connect to Server reopen in the browser.  Other
     * network MRLs remain ordinary recent streams and start playback. */
    if( getSettings()->value( "ConnectToServer/recents" ).toStringList()
            .contains( mrl ) )
    {
        if( p_intf->p_sys->p_mi->addNetworkLocation( mrl ) )
            return;
    }
    Open::openMRL( p_intf, mrl );
}

int RecentsMRL::time( const QString &mrl )
{
    if( !isActive )
        return -1;

    int i_index = recentFiles.indexOf( mrl );
    if( i_index != -1 )
        return fileTimes.value(i_index, "-1").toInt();

    i_index = recentStreams.indexOf( mrl );
    return i_index != -1 ? streamTimes.value(i_index, "-1").toInt() : -1;
}

void RecentsMRL::setTime( const QString &mrl, const int64_t time )
{
    int i_index = recentFiles.indexOf( mrl );
    if( i_index != -1 )
        fileTimes[i_index] = QString::number( time / 1000 );
    else
    {
        i_index = recentStreams.indexOf( mrl );
        if( i_index != -1 )
            streamTimes[i_index] = QString::number( time / 1000 );
    }
}

int Open::openMRL( intf_thread_t *p_intf,
                    const QString &mrl,
                    bool b_start,
                    bool b_playlist)
{
    return openMRLwithOptions( p_intf, mrl, NULL, b_start, b_playlist );
}

int Open::openMRLwithOptions( intf_thread_t* p_intf,
                     const QString &mrl,
                     QStringList *options,
                     bool b_start,
                     bool b_playlist,
                     const char *title)
{
    /* Options */
    const char **ppsz_options = NULL;
    int i_options = 0;

    if( options != NULL && options->count() > 0 )
    {
        ppsz_options = new const char *[options->count()];
        for( int j = 0; j < options->count(); j++ ) {
            QString option = colon_unescape( options->at(j) );
            if( !option.isEmpty() ) {
                ppsz_options[i_options] = strdup(qtu(option));
                i_options++;
            }
        }
    }

    /* Add to playlist */
    int i_ret = playlist_AddExt( THEPL, qtu(mrl), title, b_start,
                  i_options, ppsz_options, VLC_INPUT_OPTION_TRUSTED,
                  b_playlist );

    /* Add to recent items, only if played */
    if( i_ret == VLC_SUCCESS && b_start && b_playlist )
        RecentsMRL::getInstance( p_intf )->addRecent( mrl );

    /* Free options */
    if ( ppsz_options != NULL )
    {
        for ( int i = 0; i < i_options; ++i )
            free( (char*)ppsz_options[i] );
        delete[] ppsz_options;
    }
    return i_ret;
}
