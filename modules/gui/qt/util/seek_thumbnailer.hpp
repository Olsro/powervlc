/*****************************************************************************
 * seek_thumbnailer.hpp : seek bar hover thumbnails
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

#ifndef VLC_QT_SEEK_THUMBNAILER_HPP_
#define VLC_QT_SEEK_THUMBNAILER_HPP_

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "qt.hpp"

/* ⚠ vlc_threads.h, pulled in by qt.hpp, defines msleep() as a function-like
 * macro, and qthread.h declares `static void msleep(unsigned long)`: the
 * macro eats that declaration and the header stops compiling ("a type
 * specifier is required for all declarations"). No other Qt header in this
 * interface includes <QThread>, which is why this never came up before.
 * Hide the macro for the length of the include only -- the worker sleeps
 * through VLC's msleep(), in microseconds, and wants the macro back. */
#pragma push_macro("msleep")
#undef msleep
#include <QThread>
#pragma pop_macro("msleep")

#include <QMutex>
#include <QWaitCondition>
#include <QHash>
#include <QImage>
#include <QString>
#include <QStringList>

class QPixmap;

/* Renders the preview shown in the seek bar hover tooltip. Port of the two
 * mac interfaces' thumbnailers (modules/gui/macosx/VLCSeekThumbnailer.m).
 *
 * VLC 3.0 has no core thumbnailer, so the frame is decoded by a second,
 * silent input on the same file whose stream output re-encodes it to a
 * temporary png (no vout is ever instantiated for such a headless input,
 * and the contribs' ffmpeg carries no encoder, hence VLC's own png one).
 * Local files only: a network stream would open a second connection to the
 * server. Requests are served one at a time by this thread, only the latest
 * one survives, and results are cached.
 *
 * The object IS the worker thread; everything public is called from the GUI
 * thread and the answer comes back through thumbnailReady(), i.e. a queued
 * connection. QImage rather than QPixmap on purpose: a QPixmap may only be
 * touched by the GUI thread.
 *
 * One instance for the whole interface, shared through acquire()/release():
 * the main window and the fullscreen controller each own a seek bar, only
 * one of them is ever hovered, and a preview decoded for one is the same
 * image the other would ask for. Both connect to thumbnailReady() and each
 * keeps what matches the position it is showing. */
class SeekThumbnailer : public QThread
{
    Q_OBJECT
public:
    /* Take a reference on the shared thumbnailer, creating it on the first
     * call, and drop one -- which destroys it, joining the worker thread,
     * once the last seek bar is gone. GUI thread only, which is where every
     * seek bar is built and destroyed. */
    static SeekThumbnailer *acquire( intf_thread_t * );
    static void release( SeekThumbnailer * );

    /* True when the preview for that position is already known, in which
     * case @a pixmap receives it. GUI thread only. */
    bool cachedThumbnail( double fraction, QPixmap &pixmap );

    /* Queue a render of the CURRENT playlist item at that position. Replaces
     * whatever was queued before; thumbnailReady() may never come (network
     * stream, no video, failure, preference off). GUI thread only. */
    void requestThumbnail( double fraction );

signals:
    void thumbnailReady( const QImage &, double fraction );

protected:
    void run() Q_DECL_OVERRIDE;

private:
    /* private: the instance is shared, see acquire() */
    SeekThumbnailer( intf_thread_t * );
    virtual ~SeekThumbnailer();

    static SeekThumbnailer *instance;
    static unsigned instanceRefs;

    /* what the current item is, resolved on the GUI thread */
    bool currentMedia( QString &uri, double &durationSeconds );
    /* worker thread */
    QImage renderThumbnail( const QString &uri, double seconds );
    static QString cacheKey( const QString &uri, double seconds );

    intf_thread_t *p_intf;
    QString pngPath;

    QMutex mutex;                 /* guards everything below */
    QWaitCondition wakeUp;
    bool b_quit;
    bool b_pending;
    QString pendingUri;
    QString pendingKey;
    double pendingSeconds;
    double pendingFraction;
    QHash<QString, QImage> cache;
    QStringList cacheOrder;       /* oldest first, for the FIFO cap */
};

#endif
