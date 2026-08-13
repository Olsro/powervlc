/*****************************************************************************
 * seek_thumbnailer.cpp : seek bar hover thumbnails
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC authors
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
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#include "util/seek_thumbnailer.hpp"
#include "input_manager.hpp"

#include <vlc_input.h>
#include <vlc_input_item.h>

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QPixmap>
#include <QUrl>

/* How many previews are kept. One 240-pixel-wide frame is a few tens of
 * kilobytes, and a cache hit is what makes a second pass over the same part
 * of the seek bar instant. */
#define THUMBNAIL_CACHE_SIZE 40
/* Give up on a render past this. The secondary input restarts decoding at
 * the previous key frame, and on a slow machine already busy playing the
 * whole chain can need several seconds -- a tighter cap would abort just
 * before the image lands. */
#define THUMBNAIL_TIMEOUT_MS 20000
#define THUMBNAIL_POLL_MS 50

/* ⚠ A disc, or a disc IMAGE, cannot be previewed: a second reader reopens at
 * the MENU and never at the instant asked for, and it costs a whole dvdnav or
 * libbluray open. Disc schemes are already turned away by the "file://" test;
 * this catches the disc image opened as a plain file. */
static bool uriIsDiscLike( const QString &uri )
{
    const QString lower = uri.toLower();
    if( lower.contains( "/video_ts" ) || lower.contains( "/bdmv" ) )
        return true;
    static const char *const exts[] = { ".iso", ".img", ".bin", ".cue",
                                        ".nrg", ".mdf", ".toast" };
    for( size_t i = 0; i < sizeof(exts)/sizeof(exts[0]); i++ )
        if( lower.endsWith( exts[i] ) )
            return true;

    /* ⚠⚠⚠ A disc DROPPED on the application went straight through. Opened
     * through "Open Disc" it carries a scheme (dvdsimple://…) the "file://"
     * test turns away; dropped from the file manager it is the MOUNTED
     * VOLUME -- file:///Volumes/ROBOTS, /media/ROBOTS, D:/ -- with neither
     * "/video_ts" in the path nor a disc-image extension. Hovering the seek
     * bar then started a second reader on the disc: the drive hammering away
     * and the picture freezing at every preview (reproduced on a real DVD).
     * The disc TREE is what identifies it whatever the mount point is called,
     * and it covers a disc copied to a hard drive too. */
    const QString path = QUrl( uri ).toLocalFile();
    if( path.isEmpty() )
        return false;
    QFileInfo info( path );
    if( info.isDir() )
    {
        QDir dir( path );
        if( dir.exists( "VIDEO_TS" ) || dir.exists( "BDMV" )
         || dir.exists( "video_ts" ) || dir.exists( "bdmv" ) )
            return true;
    }
    return false;
}

SeekThumbnailer *SeekThumbnailer::instance = NULL;
unsigned SeekThumbnailer::instanceRefs = 0;

SeekThumbnailer *SeekThumbnailer::acquire( intf_thread_t *p_intf )
{
    if( instance == NULL )
        instance = new SeekThumbnailer( p_intf );
    instanceRefs++;
    return instance;
}

void SeekThumbnailer::release( SeekThumbnailer *thumbnailer )
{
    if( thumbnailer == NULL || thumbnailer != instance || instanceRefs == 0 )
        return;
    if( --instanceRefs > 0 )
        return;

    /* Last seek bar gone: join the worker while the interface it decodes
     * with is still whole. */
    delete instance;
    instance = NULL;
}

SeekThumbnailer::SeekThumbnailer( intf_thread_t *_p_intf )
    : QThread( NULL ), p_intf( _p_intf ), b_quit( false ), b_pending( false ),
      pendingSeconds( 0. ), pendingFraction( 0. )
{
    /* No QObject parent on purpose: the instance outlives whichever seek bar
     * happened to ask for it first. */
    QString dir = QString( "%1/powervlc-seek-thumbs-%2" )
                    .arg( QDir::tempPath() )
                    .arg( QCoreApplication::applicationPid() );
    QDir().mkpath( dir );
    /* Forward slashes, even on Windows: this path goes into a stream output
     * chain, where a backslash is an escape character. */
    pngPath = QString( "%1/hover.png" ).arg( dir );
}

SeekThumbnailer::~SeekThumbnailer()
{
    mutex.lock();
    b_quit = true;          /* also aborts a render in flight */
    b_pending = false;
    wakeUp.wakeAll();
    mutex.unlock();
    wait();

    QFile::remove( pngPath );
}

QString SeekThumbnailer::cacheKey( const QString &uri, double seconds )
{
    /* One preview per second of media: the mouse moves by pixels, and on a
     * two-hour film a pixel is far less than a second. */
    return QString( "%1#%2" ).arg( uri ).arg( qRound64( seconds ) );
}

/* The item being played, as the worker needs it: a URI it can open on its
 * own and a duration to turn a fraction into a time. */
bool SeekThumbnailer::currentMedia( QString &uri, double &durationSeconds )
{
    input_thread_t *p_input = THEMIM->getInput();
    if( !p_input )
        return false;

    input_item_t *p_item = input_GetItem( p_input );
    if( !p_item )
        return false;

    char *psz_uri = input_item_GetURI( p_item );
    vlc_tick_t i_duration = input_item_GetDuration( p_item );
    if( !psz_uri )
        return false;

    /* Local files only. */
    bool b_ok = i_duration > 0 && !strncasecmp( psz_uri, "file://", 7 );
    if( b_ok )
    {
        uri = qfu( psz_uri );
        durationSeconds = (double)i_duration / CLOCK_FREQ;
        if( uriIsDiscLike( uri ) )
            b_ok = false;
    }
    free( psz_uri );
    return b_ok;
}

bool SeekThumbnailer::cachedThumbnail( double fraction, QPixmap &pixmap )
{
    QString uri;
    double duration;

    if( !currentMedia( uri, duration ) )
        return false;

    QMutexLocker locker( &mutex );
    QHash<QString, QImage>::const_iterator it =
        cache.constFind( cacheKey( uri, fraction * duration ) );
    if( it == cache.constEnd() )
        return false;

    pixmap = QPixmap::fromImage( it.value() );
    return !pixmap.isNull();
}

void SeekThumbnailer::requestThumbnail( double fraction )
{
    /* Read every time rather than once: the preference can be turned off
     * from the Simple Preferences while the player is running, which is
     * exactly what someone does when the machine turns out to be too slow
     * for it. The time and chapter tooltip is unaffected either way. */
    if( !var_InheritBool( p_intf, "qt-hover-thumbnails" ) )
        return;

    QString uri;
    double duration;
    if( !currentMedia( uri, duration ) )
        return;

    double seconds = fraction * duration;
    QString key = cacheKey( uri, seconds );

    QMutexLocker locker( &mutex );
    if( b_quit || cache.contains( key ) )
        return;
    /* Latest hover wins: a queued request that has not started yet is
     * simply replaced. */
    pendingUri = uri;
    pendingKey = key;
    pendingSeconds = seconds;
    pendingFraction = fraction;
    b_pending = true;
    wakeUp.wakeAll();

    if( !isRunning() )
        start( QThread::LowPriority );
}

void SeekThumbnailer::run()
{
    for( ;; )
    {
        mutex.lock();
        while( !b_quit && !b_pending )
            wakeUp.wait( &mutex );
        if( b_quit )
        {
            mutex.unlock();
            return;
        }
        QString uri = pendingUri;
        QString key = pendingKey;
        double seconds = pendingSeconds;
        double fraction = pendingFraction;
        b_pending = false;
        mutex.unlock();

        QImage image = renderThumbnail( uri, seconds );
        if( image.isNull() )
            continue;

        mutex.lock();
        if( b_quit )
        {
            mutex.unlock();
            return;
        }
        if( !cache.contains( key ) )
        {
            cache.insert( key, image );
            cacheOrder.append( key );
            while( cacheOrder.size() > THUMBNAIL_CACHE_SIZE )
                cache.remove( cacheOrder.takeFirst() );
        }
        mutex.unlock();

        emit thumbnailReady( image, fraction );
    }
}

/* Worker thread. A silent secondary input whose stream output re-encodes the
 * decoded frame into a temporary png: stopped by hand as soon as the first
 * frame has been written, and bounded by a stop-time in case that misses. */
QImage SeekThumbnailer::renderThumbnail( const QString &uri, double seconds )
{
    QFile::remove( pngPath );

    input_item_t *p_item = input_item_New( qtu( uri ), "seek-thumbnail" );
    if( !p_item )
        return QImage();

    char *psz_option;
    if( asprintf( &psz_option, "start-time=%.3f", seconds ) != -1 )
    {
        input_item_AddOption( p_item, psz_option, VLC_INPUT_OPTION_TRUSTED );
        free( psz_option );
    }
    /* Belt and braces: the input is meant to be stopped by hand on the first
     * frame, but if that ever misses again it must not decode the rest of the
     * film. A two second window always holds a frame, and one frame per
     * second of media caps what the encoder writes at a couple of pictures.
     * Measured on the Qt bench, 300 s into a ten minute file: 256 ms and
     * 432 kB with the window alone, 94 ms and 33 kB with both. */
    if( asprintf( &psz_option, "stop-time=%.3f", seconds + 2. ) != -1 )
    {
        input_item_AddOption( p_item, psz_option, VLC_INPUT_OPTION_TRUSTED );
        free( psz_option );
    }
    if( asprintf( &psz_option, "sout=#transcode{vcodec=png,width=240,fps=1}:"
                  "std{access=file,mux=es,dst='%s'}", qtu( pngPath ) ) != -1 )
    {
        input_item_AddOption( p_item, psz_option, VLC_INPUT_OPTION_TRUSTED );
        free( psz_option );
    }
    /* ⚠ Software decoding forced for this input: VideoToolbox hands back an
     * OPAQUE surface the png encoder cannot read ("Failed to create video
     * converter"), and on 10.6 VDA fails outright inside a stream output
     * ("VDADecoderCreate failed: -12470" then "cannot continue streaming due
     * to errors with codec h264") -- measured in the legacy interface, same
     * pipeline. One frame is decoded here; playback keeps the hardware. */
    static const char *const ppsz_options[] = {
        "no-audio", "no-spu", "no-osd", "no-video-title-show",
        "no-sout-audio", "sout-video",
        "no-videotoolbox", "no-vda", "avcodec-hw=none",
    };
    for( size_t i = 0; i < ARRAY_SIZE(ppsz_options); i++ )
        input_item_AddOption( p_item, ppsz_options[i], VLC_INPUT_OPTION_TRUSTED );

    input_thread_t *p_input = input_Create( p_intf, p_item, "seek-thumb",
                                            NULL, NULL );
    if( p_input )
    {
        if( input_Start( p_input ) == VLC_SUCCESS )
        {
            for( int i = 0; i < THUMBNAIL_TIMEOUT_MS / THUMBNAIL_POLL_MS; i++ )
            {
                input_state_e state = input_GetState( p_input );
                if( state == END_S || state == ERROR_S )
                    break;
                if( QFileInfo( pngPath ).size() > 0 )
                    break;
                /* The interface may be closing: a render can outlive the
                 * hover by many seconds, and the destructor waits on this
                 * thread. */
                mutex.lock();
                bool b_abort = b_quit;
                mutex.unlock();
                if( b_abort )
                    break;
                /* ⚠ The leading :: is load-bearing. This class derives from
                 * QThread, which has a static msleep() taking MILLIseconds,
                 * and inside a member function class scope wins over the
                 * global one: an unqualified msleep() slept a thousand times
                 * too long -- fifty seconds per poll, so the secondary input
                 * ran to the end of the media (a 72 MB temporary png for a
                 * ten minute file) and the preview came back, if at all, long
                 * after the pointer had moved on. The macro in vlc_threads.h
                 * only rewrites the argument (msleep(d) -> msleep(check_delay(d))),
                 * so it hides the collision instead of catching it, and its
                 * "cannot sleep for such short a time" assertion fires on a
                 * millisecond value, which reads like a vindication of the
                 * wrong call. */
                ::msleep( THUMBNAIL_POLL_MS * INT64_C(1000) );
            }
            input_Stop( p_input );
        }
        input_Close( p_input );
    }
    input_item_Release( p_item );

    /* The stream output may have written several concatenated png frames
     * before the stop took effect; a reader only decodes the first one. */
    QImage image;
    image.load( pngPath, "PNG" );
    QFile::remove( pngPath );
    return image;
}
