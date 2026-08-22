/*****************************************************************************
 * input_slider.cpp : VolumeSlider and SeekSlider
 ****************************************************************************
 * Copyright (C) 2006-2011 the VideoLAN team
 * $Id$
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Jean-Baptiste Kempf <jb@videolan.org>
 *          Ludovic Fauvet <etix@videolan.org>
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

#include "qt.hpp"

#include "util/input_slider.hpp"
#include "util/timetooltip.hpp"
#include "util/seek_thumbnailer.hpp"
#include "adapters/seekpoints.hpp"
#include "input_manager.hpp"
#include "imagehelper.hpp"
#include "customwidgets.hpp"
#include <vlc_actions.h>

#include <QPaintEvent>
#include <QPainter>
#include <QPainterPath>
#include <QPixmap>
#include <QImage>
#include <QBitmap>
#include <QStyleOptionSlider>
#include <QLinearGradient>
#include <QTimer>
#include <QRadialGradient>
#include <QLinearGradient>
#include <QSize>
#include <QPalette>
#include <QColor>
#include <QPoint>
#include <QPropertyAnimation>
#include <QApplication>
#include <QDebug>
#include <QScreen>
#include <QSequentialAnimationGroup>

namespace {
    int const MIN_SLIDER_VALUE = 0;
    int const MAX_SLIDER_VALUE = 10000;

    int const CHAPTER_SPOT_SIZE = 3;

    int const FADE_DURATION = 300;
    int const FADEOUT_DELAY = 2000;
}

SeekSlider::SeekSlider( intf_thread_t *p_intf, Qt::Orientation q, QWidget *_parent, bool _static )
          : QSlider( q, _parent ), p_intf( p_intf ), b_classic( _static ), animLoading( NULL )
{
    isSliding = false;
    isJumping = false;
    f_buffering = 0.0;
    mHandleOpacity = 1.0;
    mLoading = 0.0;
    chapters = NULL;
    mHandleLength = -1;
    b_seekable = true;
    alternativeStyle = NULL;
    b_clipMode = false;
    activeClipKnob = 0;
    f_clipMarker = 0.f;
    hoverFraction = -1.;

    // prepare some static colors
    QPalette p = palette();
    QColor background = p.color( QPalette::Active, QPalette::Window );
    tickpointForeground = p.color( QPalette::Active, QPalette::WindowText );
    tickpointForeground.setHsv( tickpointForeground.hue(),
            ( background.saturation() + tickpointForeground.saturation() ) / 2,
            ( background.value() + tickpointForeground.value() ) / 2 );

    // set the background color and gradient
    QColor backgroundBase( p.window().color() );
    backgroundGradient.setColorAt( 0.0, backgroundBase.darker( 140 ) );
    backgroundGradient.setColorAt( 1.0, backgroundBase );

    // set the foreground color and gradient
    QColor foregroundBase( 50, 156, 255 );
    foregroundGradient.setColorAt( 0.0,  foregroundBase );
    foregroundGradient.setColorAt( 1.0,  foregroundBase.darker( 140 ) );

    // prepare the handle's gradient
    handleGradient.setColorAt( 0.0, p.window().color().lighter( 120 ) );
    handleGradient.setColorAt( 0.9, p.window().color().darker( 120 ) );

    // prepare the handle's shadow gradient
    QColor shadowBase = p.shadow().color();
    if( shadowBase.lightness() > 100 )
        shadowBase = QColor( 60, 60, 60 ); // Palette's shadow is too bright
    shadowDark = shadowBase.darker( 150 );
    shadowLight = shadowBase.lighter( 180 );
    shadowLight.setAlpha( 50 );

    /* Timer used to fire intermediate updatePos() when sliding */
    seekLimitTimer = new QTimer( this );
    seekLimitTimer->setSingleShot( true );

    /* Tooltip bubble */
    mTimeTooltip = new TimeTooltip( NULL );
    mTimeTooltip->setMouseTracking( true );

    /* Preview of the hovered position, decoded by a second input. Asked for
     * only once the mouse has settled: sweeping the bar would otherwise
     * queue a decode per pixel, and on the machines this fork exists for
     * that decode is taken out of the playback. Shared with the other seek
     * bar of the interface -- one worker, one cache. */
    thumbnailer = SeekThumbnailer::acquire( p_intf );
    thumbnailTimer = new QTimer( this );
    thumbnailTimer->setSingleShot( true );
    thumbnailTimer->setInterval( 500 );

    /* Properties */
    setRange( MIN_SLIDER_VALUE, MAX_SLIDER_VALUE );
    setSingleStep( 2 );
    setPageStep( 10 );
    setMouseTracking( true );
    setTracking( true );
    setFocusPolicy( Qt::NoFocus );

    /* Use the new/classic style */
    setMinimumHeight( 18 );
    if( !b_classic )
    {
        alternativeStyle = new SeekStyle;
        setStyle( alternativeStyle );
    }

    /* Init to 0 */
    setPosition( -1.0, 0, 0 );
    secstotimestr( psz_length, 0 );

    animHandle = new QPropertyAnimation( this, "handleOpacity", this );
    animHandle->setDuration( FADE_DURATION );
    animHandle->setStartValue( 0.0 );
    animHandle->setEndValue( 1.0 );

    QPropertyAnimation *animLoadingIn = new QPropertyAnimation( this, "loadingProperty", this );
    animLoadingIn->setDuration( 2000 );
    animLoadingIn->setStartValue( 0.0 );
    animLoadingIn->setEndValue( 1.0 );
    animLoadingIn->setEasingCurve( QEasingCurve::OutBounce );
    QPropertyAnimation *animLoadingOut = new QPropertyAnimation( this, "loadingProperty", this );
    animLoadingOut->setDuration( 2000 );
    animLoadingOut->setStartValue( 1.0 );
    animLoadingOut->setEndValue( 0.0 );
    animLoadingOut->setEasingCurve( QEasingCurve::OutBounce );

    animLoading = new QSequentialAnimationGroup( this );
    animLoading->addAnimation( animLoadingIn );
    animLoading->addAnimation( animLoadingOut );
    animLoading->setLoopCount( -1 );

    hideHandleTimer = new QTimer( this );
    hideHandleTimer->setSingleShot( true );
    hideHandleTimer->setInterval( FADEOUT_DELAY );

    startAnimLoadingTimer = new QTimer( this );
    startAnimLoadingTimer->setSingleShot( true );
    startAnimLoadingTimer->setInterval( 500 );

    connect( MainInputManager::getInstance(), &MainInputManager::inputChanged, this, &SeekSlider::inputUpdated );
    connect( this, &SeekSlider::sliderMoved, this, &SeekSlider::startSeekTimer );
    connect( seekLimitTimer, &QTimer::timeout, this, &SeekSlider::updatePos );
    connect( hideHandleTimer, &QTimer::timeout, this, &SeekSlider::hideHandle );
    connect( startAnimLoadingTimer, &QTimer::timeout, this, &SeekSlider::startAnimLoading );
    connect( thumbnailTimer, &QTimer::timeout, this, &SeekSlider::requestHoverThumbnail );
    connect( thumbnailer, &SeekThumbnailer::thumbnailReady,
             this, &SeekSlider::hoverThumbnailReady );
    mTimeTooltip->installEventFilter( this );

    connect(&wheelEventConverter, &WheelToVLCConverter::vlcWheelKey, this, [this](int vlcButton){
        vlc_tick_t i_size = var_InheritInteger( this->p_intf->obj.libvlc, "short-jump-size" );
        int i_mode = var_InheritInteger( this->p_intf->obj.libvlc, "hotkeys-x-wheel-mode" );

        //ignore modifiers
        switch (vlcButton & 0x00FF0000) {
        case KEY_MOUSEWHEELDOWN:
        case KEY_MOUSEWHEELLEFT:
            if (i_mode != 3)
                i_size = - i_size;
            break;
        case KEY_MOUSEWHEELUP:
        case KEY_MOUSEWHEELRIGHT:
            if (i_mode == 3)
                i_size = - i_size;
            break;
        default:
            break;
        }

        float posOffset = static_cast<float>( i_size ) / static_cast<float>( inputLength );
        setValue( value() + posOffset * maximum() );
        emit sliderDragged( value() / static_cast<float>( maximum() ) );
    });
}

SeekSlider::~SeekSlider()
{
    /* Explicitly, and first. The thumbnailer is shared, so this only ends
     * the worker thread when the other seek bar has gone too -- and then it
     * joins it, which has to happen while the interface it decodes with is
     * still whole. Disconnect first: nothing should be delivered to a slider
     * that is being destroyed. */
    disconnect( thumbnailer, 0, this, 0 );
    SeekThumbnailer::release( thumbnailer );
    delete chapters;
    if ( alternativeStyle )
        delete alternativeStyle;
    delete mTimeTooltip;
}

/***
 * \brief Sets the chapters seekpoints adapter
 *
 * \params SeekPoints initilized with current intf thread
***/
void SeekSlider::setChapters( SeekPoints *chapters_ )
{
    delete chapters;
    chapters = chapters_;
    chapters->setParent( this );
}

/***
 * \brief Main public method, superseeding setValue. Disabling the slider when neeeded
 *
 * \param pos Position, between 0 and 1. -1 disables the slider
 * \param time Elapsed time. Unused
 * \param legnth Duration time.
 ***/
void SeekSlider::setPosition( float pos, int64_t time, int length )
{
    VLC_UNUSED(time);
    if( pos == -1.0  || ! b_seekable )
    {
        setEnabled( false );
        mTimeTooltip->hide();
        isSliding = false;
        setValue( 0 );
        return;
    }
    else
        setEnabled( true );

    if( b_clipMode )
    {
        /* the handles hold the clip bounds; only the thin marker follows
         * the playback position */
        f_clipMarker = pos;
        if( !isSliding )
            setValue( THEMIM->getIM()->clipStartPosition() * maximum() );
        update();
    }
    else if( !isSliding )
    {
        setValue( pos * static_cast<float>( maximum() ) );
        if ( animLoading != NULL && pos >= 0.0f && animLoading->state() != QAbstractAnimation::Stopped )
        {
            animLoading->stop();
            mLoading = 0.0f;
        }

    }

    inputLength = length;
}

void SeekSlider::startSeekTimer()
{
    /* Only fire one update, when sliding, every 150ms */
    if( isSliding && !seekLimitTimer->isActive() )
        seekLimitTimer->start( 150 );
}

void SeekSlider::updatePos()
{
    float f_pos = value() / static_cast<float>( maximum() );
    emit sliderDragged( f_pos ); /* Send new position to VLC's core */
}

void SeekSlider::updateBuffering( float f_buffering_ )
{
    if ( f_buffering_ < f_buffering )
        bufferingStart = QTime::currentTime();
    f_buffering = f_buffering_;
    if ( f_buffering > 0.0 || isEnabled() ) {
        animLoading->stop();
        startAnimLoadingTimer->stop();
        mLoading = 0.0;
    }
    repaint();
}

void SeekSlider::inputUpdated( bool b_has_input )
{
    if ( b_has_input == false ) {
        animLoading->stop();
        startAnimLoadingTimer->stop();
        mLoading = 0.0;
        repaint();
    }
    else if ( f_buffering == 0.0 && !isEnabled() )
        startAnimLoadingTimer->start();
}

void SeekSlider::processReleasedButton()
{
    if ( !isSliding && !isJumping ) return;
    isSliding = false;
    if ( b_clipMode )
    {
        /* The drag is display-paced; force its exact trailing position now. */
        THEMIM->getIM()->flushClipPreview();
        activeClipKnob = 0;
        seekLimitTimer->stop();
        return;
    }
    bool b_seekPending = seekLimitTimer->isActive();
    seekLimitTimer->stop(); /* We're not sliding anymore: only last seek on release */
    if ( isJumping )
    {
        isJumping = false;
        return;
    }
    if( b_seekPending && isEnabled() )
        updatePos();
}

void SeekSlider::mouseReleaseEvent( QMouseEvent *event )
{
    if ( event->button() != Qt::LeftButton && event->button() != Qt::MiddleButton )
    {
        QSlider::mouseReleaseEvent( event );
        return;
    }
    event->accept();
    processReleasedButton();
}

/* PowerVLC clip creation mode */

void SeekSlider::updateClipCreationMode()
{
    InputManager *im = THEMIM->getIM();
    b_clipMode = im->clipCreationMode();
    activeClipKnob = 0;
    if( b_clipMode )
    {
        setValue( im->clipStartPosition() * maximum() );
        f_clipMarker = (float)im->clipStartPosition();
    }
    update();
}

/* One knob interaction step (press or drag). On the knobs: drag that
 * bound. Strictly between them: plain seek (scrub), bounds untouched.
 * Outside the range: pull the nearest bound. Every step seeks so the
 * user previews what the clip will contain. */
void SeekSlider::clipKnobInteract( int xPos )
{
    InputManager *im = THEMIM->getIM();
    float fraction = getValuePercentageFromXPos( xPos );

    if( activeClipKnob == 0 )
    {
        int margin = handleLength() / 2;
        int width = size().width() - 2 * margin;
        int xStart = margin + im->clipStartPosition() * width;
        int xEnd = margin + im->clipEndPosition() * width;
        /* each bound is grabbed by its OUTER side (plus a couple of pixels
         * of slop inwards), and the midpoint between the two bounds always
         * splits them: a handle sitting next to the other one can still be
         * picked on its own side, however close they are */
        int grab = qMax( handleLength() / 2, 4 );
        const int slop = 2;
        int middle = ( xStart + xEnd ) / 2;
        int startInner = qMin( xStart + slop, middle );
        int endInner = qMax( xEnd - slop, middle );
        if( xPos >= xStart - grab && xPos <= startInner )
            activeClipKnob = 1;
        else if( xPos >= endInner && xPos <= xEnd + grab )
            activeClipKnob = 2;
        else if( xPos > xStart && xPos < xEnd )
            activeClipKnob = 3;
        else
            activeClipKnob = ( xPos <= xStart ) ? 1 : 2;
    }

    im->noteClipInteraction();
    switch( activeClipKnob )
    {
    case 1:
        if( fraction > im->clipEndPosition() )
            fraction = im->clipEndPosition();
        im->setClipStartPosition( fraction );
        im->setClipSelectedKnob( 1 ); /* the frame-step shortcuts follow */
        setValue( fraction * maximum() );
        break;
    case 2:
        if( fraction < im->clipStartPosition() )
            fraction = im->clipStartPosition();
        im->setClipEndPosition( fraction );
        im->setClipSelectedKnob( 2 );
        break;
    default: /* scrub, clamped to the clip */
        fraction = qBound( (float)im->clipStartPosition(), fraction,
                           (float)im->clipEndPosition() );
        break;
    }
    f_clipMarker = fraction;
    clipSeekPreview( fraction ); /* seek, for an instant preview */
    update();
}

/* Clip trimming is a visual operation: mirror the macOS interfaces and send
 * every movement to the input.  Pacing these seeks made short movements and
 * intermediate positions update only the handle while the displayed frame
 * stayed behind it, which made precise trimming effectively blind. */
void SeekSlider::clipSeekPreview( float fraction )
{
    emit sliderDragged( fraction );
}

void SeekSlider::mousePressEvent( QMouseEvent* event )
{
    /* Right-click */
    if ( !isEnabled() ||
         ( event->button() != Qt::LeftButton && event->button() != Qt::MiddleButton )
       )
    {
        QSlider::mousePressEvent( event );
        return;
    }

    if( b_clipMode )
    {
        isSliding = true;
        activeClipKnob = 0;
        clipKnobInteract( event->x() );
        event->accept();
        return;
    }

    isJumping = false;
    /* handle chapter clicks */
    int i_width = size().width();
    if ( chapters && inputLength && i_width)
    {
        if ( orientation() == Qt::Horizontal ) /* TODO: vertical */
        {
             /* only on chapters zone */
            if ( event->y() < CHAPTER_SPOT_SIZE ||
                 event->y() > ( size().height() - CHAPTER_SPOT_SIZE ) )
            {
                QList<SeekPoint> points = chapters->getPoints();
                int i_selected = -1;
                bool b_startsnonzero = false; /* as we always starts at 1 */
                if ( points.count() > 0 ) /* do we need an extra offset ? */
                    b_startsnonzero = ( points.at(0).time > 0 );
                int i_min_diff = i_width + 1;
                for( int i = 0 ; i < points.count() ; i++ )
                {
                    int x = points.at(i).time / 1000000.0 / inputLength * i_width;
                    int diff_x = abs( x - event->x() );
                    if ( diff_x < i_min_diff )
                    {
                        i_min_diff = diff_x;
                        i_selected = i + ( ( b_startsnonzero )? 1 : 0 );
                    } else break;
                }
                if ( i_selected && i_min_diff < 4 ) // max 4px around mark
                {
                    chapters->jumpTo( i_selected );
                    event->accept();
                    isJumping = true;
                    return;
                }
            }
        }
    }

    isSliding = true ;

    setValue( getValueFromXPos( event->x() ) );
    emit sliderMoved( value() );
    event->accept();
}

void SeekSlider::mouseMoveEvent( QMouseEvent *event )
{
    if ( ! ( event->buttons() & ( Qt::LeftButton | Qt::MiddleButton ) ) )
    {
        /* Handle button release when mouserelease has been hijacked by popup */
        processReleasedButton();
    }

    if ( !isEnabled() ) return event->accept();

    if( isSliding )
    {
        if( b_clipMode )
            clipKnobInteract( event->x() );
        else
        {
            setValue( getValueFromXPos( event->x() ) );
            emit sliderMoved( value() );
        }
    }

    /* Tooltip */
    if ( inputLength > 0 )
    {
        int margin = handleLength();
        int posX = qMax( rect().left() + margin, qMin( rect().right() - margin, event->x() ) );

        QString chapterLabel;

        if ( orientation() == Qt::Horizontal ) /* TODO: vertical */
        {
            QList<SeekPoint> points = chapters->getPoints();
            int i_selected = -1;
            for( int i = 0 ; i < points.count() ; i++ )
            {
                int x = margin + points.at(i).time / 1000000.0 / inputLength * (size().width() - 2*margin);
                if ( event->x() >= x )
                    i_selected = i;
            }
            if ( i_selected >= 0 && i_selected < points.size() )
            {
                chapterLabel = points.at( i_selected ).name;
            }
        }

        /* PowerVLC: hovering anywhere between the two bounds also tells how
         * long the clip currently is -- what the trimming is actually for,
         * and what the mac interfaces show (VLCSlider, _NS("Clip:")). */
        if ( b_clipMode )
        {
            InputManager *im = THEMIM->getIM();
            float f_hovered = getValuePercentageFromXPos( event->x() );
            if ( f_hovered >= im->clipStartPosition()
              && f_hovered <= im->clipEndPosition() )
            {
                char psz_clip[MSTRTIME_MAX_SIZE];
                secstotimestr( psz_clip,
                    ( im->clipEndPosition() - im->clipStartPosition() )
                    * inputLength );
                if ( !chapterLabel.isEmpty() )
                    chapterLabel += " — ";
                chapterLabel += qtr( "Clip:" ) + QString( " " )
                              + qfu( psz_clip );
            }
        }

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
        const auto pos = event->globalPosition();
#else
        const auto pos = event->globalPos();
#endif
        QPoint target( pos.x() - ( event->x() - posX ),
                QWidget::mapToGlobal( QPoint( 0, 0 ) ).y() );
        if( likely( size().width() > handleLength() ) ) {
            secstotimestr( psz_length, getValuePercentageFromXPos( event->x() ) * inputLength );
            hoverFraction = getValuePercentageFromXPos( event->x() );
            updateHoverPreview();
            mTimeTooltip->setTip( target, psz_length, chapterLabel );
        }
    }
    event->accept();
}

/* PowerVLC. Show the preview of the position now under the mouse: from the
 * cache when it is there, otherwise nothing (rather than the previous
 * position's image, which would be a lie) and a request once the mouse has
 * stopped moving for a moment. */
void SeekSlider::updateHoverPreview()
{
    QPixmap preview;

    /* Read every time: turning the preference off mid-film has to take the
     * images away at once, cached ones included -- someone turning it off
     * is someone whose machine is struggling with it. */
    if( !var_InheritBool( p_intf, "qt-hover-thumbnails" ) )
    {
        thumbnailTimer->stop();
        mTimeTooltip->setPreview( QPixmap() );
        return;
    }

    if( thumbnailer->cachedThumbnail( hoverFraction, preview ) )
    {
        thumbnailTimer->stop();
        mTimeTooltip->setPreview( preview );
        return;
    }

    mTimeTooltip->setPreview( QPixmap() );
    thumbnailTimer->start();
}

void SeekSlider::requestHoverThumbnail()
{
    /* the mouse left, or the tooltip went away, while we were waiting */
    if( hoverFraction < 0. || !mTimeTooltip->isVisible() )
        return;

    thumbnailer->requestThumbnail( hoverFraction );
}

void SeekSlider::hoverThumbnailReady( const QImage &image, double fraction )
{
    /* A decode takes as long as it takes: by now the mouse may be somewhere
     * else entirely, and the image belongs to the position it was asked
     * for. The cache keeps it for when that position is hovered again. */
    if( hoverFraction < 0. || !mTimeTooltip->isVisible() || image.isNull() )
        return;

    QPixmap current;
    if( thumbnailer->cachedThumbnail( hoverFraction, current ) )
        mTimeTooltip->setPreview( current );
    else if( qAbs( fraction - hoverFraction ) < 0.0005 )
        mTimeTooltip->setPreview( QPixmap::fromImage( image ) );
}

void SeekSlider::wheelEvent( QWheelEvent *event )
{
    /* scrolling would silently move the clip start bound */
    if( b_clipMode )
    {
        event->accept();
        return;
    }
    /* Don't do anything if we are for somehow reason sliding */
    if( !isSliding && isEnabled() )
        wheelEventConverter.wheelEvent(event);
    event->accept();
}

#if QT_VERSION >= QT_VERSION_CHECK(6, 0, 0)
void SeekSlider::enterEvent( QEnterEvent * )
#else
void SeekSlider::enterEvent( QEvent * )
#endif
{
    /* Cancel the fade-out timer */
    hideHandleTimer->stop();
    /* Only start the fade-in if needed */
    if( isEnabled() && animHandle->direction() != QAbstractAnimation::Forward )
    {
        /* If pause is called while not running Qt will complain */
        if( animHandle->state() == QAbstractAnimation::Running )
            animHandle->pause();
        animHandle->setDirection( QAbstractAnimation::Forward );
        animHandle->start();
    }
    /* Don't show the tooltip if the slider is disabled or a menu is open */
    if( isEnabled() && inputLength > 0 && !qApp->activePopupWidget() )
        mTimeTooltip->show();
}

void SeekSlider::leaveEvent( QEvent * )
{
    hideHandleTimer->start();
    /* Hide the tooltip
       - if the mouse leave the slider rect (Note: it can still be
         over the tooltip!)
       - if another window is on the way of the cursor */
    if( !rect().contains( mapFromGlobal( QCursor::pos() ) ) ||
      ( !isActiveWindow() && !mTimeTooltip->isActiveWindow() ) )
    {
        mTimeTooltip->hide();
        /* nothing is hovered any more: drop the pending preview request
         * and the image, so the next hover starts from its own position */
        hoverFraction = -1.;
        thumbnailTimer->stop();
        mTimeTooltip->setPreview( QPixmap() );
    }
}

void SeekSlider::paintEvent( QPaintEvent *ev )
{
    if ( alternativeStyle )
    {
        SeekStyle::SeekStyleOption option;
        option.initFrom( this );
        if ( QTime::currentTime() > bufferingStart.addSecs( 1 ) )
            option.buffering = f_buffering;
        else
            option.buffering = 0.0;
        option.length = inputLength;
        option.animate = ( animHandle->state() == QAbstractAnimation::Running
                           || hideHandleTimer->isActive() );
        /* in clip creation mode the two bounds ARE the handles: hide the
         * style's own one instead of stacking a third circle on the start
         * bound (SeekStyle applies this opacity to the handle+shadow) */
        option.animationopacity = b_clipMode ? 0.0 : mHandleOpacity;
        option.animationloading = mLoading;
        /* The filled part of the bar means "the clip", not "played": in
         * clip mode the slider value holds the START bound, so letting the
         * style fill [0..start] painted everything BEFORE the clip solid
         * blue -- the exact opposite of what it says. The range itself is
         * filled by paintClipExtras() below, as the two macOS interfaces
         * do (VLCSliderCell fills [start..end] there). */
        option.sliderPosition = b_clipMode ? minimum() : sliderPosition();
        option.sliderValue = value();
        option.maximum = maximum();
        option.minimum = minimum();
        if ( chapters ) foreach( const SeekPoint &point, chapters->getPoints() )
            option.points << point.time;
        QPainter painter( this );
        style()->drawComplexControl( QStyle::CC_Slider, &option, &painter, this );
        if( b_clipMode )
            paintClipExtras( painter );
    }
    else
    {
        QSlider::paintEvent( ev );
        if( b_clipMode )
        {
            QPainter painter( this );
            paintClipExtras( painter );
        }
    }
}

/* Clip creation mode: highlight the [start..end] range, draw the second
 * (end bound) handle and a thin marker on the playback position. */
void SeekSlider::paintClipExtras( QPainter &painter )
{
    InputManager *im = THEMIM->getIM();
    int margin = handleLength() / 2;
    int width = size().width() - 2 * margin;
    if( width <= 0 )
        return;

    int xStart = margin + im->clipStartPosition() * width;
    int xEnd = margin + im->clipEndPosition() * width;
    int xMarker = margin + f_clipMarker * width;
    int h = height();

    painter.setRenderHint( QPainter::Antialiasing, true );

    /* range highlight */
    QColor rangeColor( 50, 156, 255, 70 );
    painter.fillRect( QRect( xStart, h / 2 - 3, qMax( xEnd - xStart, 1 ), 6 ),
                      rangeColor );

    /* playback marker */
    painter.fillRect( QRect( xMarker - 1, 2, 2, h - 4 ),
                      QColor( 50, 156, 255 ) );

    /* Both bounds are drawn as HALF discs pointing away from the clip: the
     * flat edge sits exactly on the bound, and two bounds sitting next to
     * each other never cover one another (which is also what the grab
     * areas in clipKnobInteract() assume). Same shape as the two macOS
     * interfaces. */
    int diameter = qBound( 8, h - 6, 14 );
    qreal radius = diameter / 2.0;
    qreal cy = h / 2.0;
    painter.setPen( QPen( palette().shadow().color(), 0.5 ) );
    painter.setBrush( palette().base() );

    QPainterPath startKnob;
    startKnob.moveTo( xStart, cy - radius );
    /* left half: 90 deg -> 270 deg counterclockwise, then the flat edge */
    startKnob.arcTo( QRectF( xStart - radius, cy - radius,
                             diameter, diameter ), 90, 180 );
    startKnob.closeSubpath();
    painter.drawPath( startKnob );

    QPainterPath endKnob;
    endKnob.moveTo( xEnd, cy + radius );
    endKnob.arcTo( QRectF( xEnd - radius, cy - radius,
                           diameter, diameter ), 270, 180 );
    endKnob.closeSubpath();
    painter.drawPath( endKnob );
}

void SeekSlider::hideEvent( QHideEvent * )
{
    mTimeTooltip->hide();
    hoverFraction = -1.;
    thumbnailTimer->stop();
    mTimeTooltip->setPreview( QPixmap() );
}

bool SeekSlider::eventFilter( QObject *obj, QEvent *event )
{
    if( obj == mTimeTooltip )
    {
        if( event->type() == QEvent::MouseMove )
        {
            QMouseEvent* mev = static_cast<QMouseEvent*>( event );

            if( rect().contains( mapFromGlobal( mev->globalPos() ) ) )
                return false;
        }

        /* PowerVLC: same escape for a Leave. The tooltip is laid out around
         * the pointer, tip included, so growing it to hold a preview puts
         * the pointer inside it and the next move takes the pointer back
         * out -- a Leave Qt works out from the geometry, whatever the
         * window's empty input shape says. Before the preview the tooltip
         * was a small box well above the seek bar and this never happened;
         * with it, every hover that followed a displayed preview was
         * cancelled here, one preview in two. */
        if( event->type() == QEvent::Leave &&
            rect().contains( mapFromGlobal( QCursor::pos() ) ) )
            return false;

        if( event->type() == QEvent::Leave ||
            event->type() == QEvent::MouseMove )
        {
            mTimeTooltip->hide();
            hoverFraction = -1.;
            thumbnailTimer->stop();
            mTimeTooltip->setPreview( QPixmap() );
        }

        return false;
    }

    return QSlider::eventFilter( obj, event );
}

QSize SeekSlider::sizeHint() const
{
    if ( b_classic )
        return QSlider::sizeHint();
    return ( orientation() == Qt::Horizontal ) ? QSize( 100, 18 )
                                               : QSize( 18, 100 );
}

qreal SeekSlider::handleOpacity() const
{
    return mHandleOpacity;
}

qreal SeekSlider::loading() const
{
    return mLoading;
}

void SeekSlider::setHandleOpacity(qreal opacity)
{
    mHandleOpacity = opacity;
    /* Request a new paintevent */
    update();
}

void SeekSlider::setLoading(qreal loading)
{
    mLoading = loading;
    /* Request a new paintevent */
    update();
}

inline int SeekSlider::handleLength()
{
    if ( mHandleLength > 0 )
        return mHandleLength;

    /* Ask for the length of the handle to the underlying style */
    QStyleOptionSlider option;
    initStyleOption( &option );
    mHandleLength = style()->pixelMetric( QStyle::PM_SliderLength, &option );
    return mHandleLength;
}

inline int SeekSlider::getValueFromXPos( int posX )
{
    return QStyle::sliderValueFromPosition(
        minimum(), maximum(),
        posX    - handleLength() / 2,
        width() - handleLength(),
        false
    );
}

inline float SeekSlider::getValuePercentageFromXPos( int posX )
{
    return getValueFromXPos( posX ) / static_cast<float>( maximum() );
}

void SeekSlider::hideHandle()
{
    /* If pause is called while not running Qt will complain */
    if( animHandle->state() == QAbstractAnimation::Running )
        animHandle->pause();
    /* Play the animation backward */
    animHandle->setDirection( QAbstractAnimation::Backward );
    animHandle->start();
}

void SeekSlider::startAnimLoading()
{
    animLoading->start();
}

/* This work is derived from Amarok's work under GPLv2+
    - Mark Kretschmann
    - Gábor Lehel
   */
#define WLENGTH   85  // px
#define WHEIGHT   26  // px
#define PADDINGL  6   // px
#define PADDINGR  6   // px
#define SOUNDMIN  0   // %

SoundSlider::SoundSlider( QWidget *_parent, float _i_step,
                          char *psz_colors, int max )
                        : QAbstractSlider( _parent )
{
    f_step = (float)(_i_step * 10000)
           / (float)((max - SOUNDMIN) * AOUT_VOLUME_DEFAULT);
    setRange( SOUNDMIN, max);
    setMouseTracking( true );
    isSliding = false;
    b_mouseOutside = true;
    b_isMuted = false;

    setFixedSize( WLENGTH, WHEIGHT );

    pixOutside = ImageHelper::loadSvgToPixmap(":/toolbar/volslide-outside.svg", width(), height() );

    const QPixmap temp = ImageHelper::loadSvgToPixmap(":/toolbar/volslide-inside.svg", width(), height() );
    const QBitmap mask( temp.createHeuristicMask() );

    pixGradient = QPixmap( pixOutside.size() );
    pixGradient2 = QPixmap( pixOutside.size() );
    dark = isDarkPaletteEnabled(nullptr);

#if HAS_QT56
    pixGradient.setDevicePixelRatio(QApplication::primaryScreen()->devicePixelRatio());
    pixGradient2.setDevicePixelRatio(QApplication::primaryScreen()->devicePixelRatio());
#endif

    /* Gradient building from the preferences */
    QLinearGradient gradient( PADDINGL, 2, width() - PADDINGR, 2 );
    QLinearGradient gradient2( PADDINGL, 2, width()- PADDINGR, 2 );

    QStringList colorList = qfu( psz_colors ).split( ";" );
    free( psz_colors );

    /* Fill with 255 if the list is too short */
    if( colorList.count() < 12 )
        for( int i = colorList.count(); i < 12; i++)
            colorList.append( "255" );

    background = palette().color( QPalette::Active, QPalette::Window );
    foreground = palette().color( QPalette::Active, QPalette::WindowText );
    foreground.setHsv( foreground.hue(),
                    ( background.saturation() + foreground.saturation() ) / 2,
                    ( background.value() + foreground.value() ) / 2 );

    textfont.setPointSize( 7 );
    textrect.setRect( 0, 0, 34, 15 );

    /* Regular colors */
#define c(i) colorList.at(i).toInt()
#define add_color(gradient, range, c1, c2, c3) \
    gradient.setColorAt( range, QColor( c(c1), c(c2), c(c3) ) );

    /* Desaturated colors */
#define desaturate(c) c->setHsvF( c->hueF(), 0.2 , 0.5, 1.0 )
#define add_desaturated_color(gradient, range, c1, c2, c3) \
    foo = new QColor( c(c1), c(c2), c(c3) );\
    desaturate( foo ); gradient.setColorAt( range, *foo );\
    delete foo;

    /* combine the two helpers */
#define add_colors( gradient1, gradient2, range, c1, c2, c3 )\
    add_color( gradient1, range, c1, c2, c3 ); \
    add_desaturated_color( gradient2, range, c1, c2, c3 );

    float f_mid_point = ( 100.0 / maximum() );
    QColor * foo;
    add_colors( gradient, gradient2, 0.0, 0, 1, 2 );
    add_colors( gradient, gradient2, f_mid_point - 0.05, 3, 4, 5 );
    add_colors( gradient, gradient2, f_mid_point + 0.05, 6, 7, 8 );
    add_colors( gradient, gradient2, 1.0, 9, 10, 11 );

    painter.begin( &pixGradient );
    painter.setPen( Qt::NoPen );
    painter.setBrush( gradient );
    painter.drawRect( pixGradient.rect() );
    painter.end();

    painter.begin( &pixGradient2 );
    painter.setPen( Qt::NoPen );
    painter.setBrush( gradient2 );
    painter.drawRect( pixGradient2.rect() );
    painter.end();

    pixGradient.setMask( mask );
    pixGradient2.setMask( mask );

    connect(&wheelEventConverter, &WheelToVLCConverter::vlcWheelKey, this, [this](int vlcButton){
        int newvalue = 0;
        //ignore modifiers
        switch (vlcButton & 0x00FF0000) {
        case KEY_MOUSEWHEELDOWN:
        case KEY_MOUSEWHEELLEFT:
            newvalue = value() - f_step;
            break;
        case KEY_MOUSEWHEELUP:
        case KEY_MOUSEWHEELRIGHT:
            newvalue = value() + f_step;
            break;
        default:
            return;
        }

        setValue( __MIN( __MAX( minimum(), newvalue ), maximum() ) );
        emit sliderMoved( value() );
    });
}

void SoundSlider::wheelEvent( QWheelEvent *event )
{
    wheelEventConverter.wheelEvent(event);
    event->accept();
    emit sliderReleased();
}

void SoundSlider::mousePressEvent( QMouseEvent *event )
{
    if( event->button() != Qt::RightButton )
    {
        /* We enter the sliding mode */
        isSliding = true;
        i_oldvalue = value();
        emit sliderPressed();
        changeValue( event->x() );
        emit sliderMoved( value() );
    }
}

void SoundSlider::processReleasedButton()
{
    if( !b_mouseOutside && value() != i_oldvalue )
    {
        emit sliderReleased();
        setValue( value() );
        emit sliderMoved( value() );
    }
    isSliding = false;
    b_mouseOutside = false;
}

void SoundSlider::mouseReleaseEvent( QMouseEvent *event )
{
    if( event->button() != Qt::RightButton )
        processReleasedButton();
}

void SoundSlider::mouseMoveEvent( QMouseEvent *event )
{
    /* handle mouserelease hijacking */
    if ( isSliding && ( event->buttons() & ~Qt::RightButton ) == Qt::NoButton )
        processReleasedButton();

    if( isSliding )
    {
        QRect rect( PADDINGL - 15,    -1,
                    width() - PADDINGR + 15 * 2 , width() + 5 );
        if( !rect.contains( event->pos() ) )
        { /* We are outside */
            if ( !b_mouseOutside )
                setValue( i_oldvalue );
            b_mouseOutside = true;
        }
        else
        { /* We are inside */
            b_mouseOutside = false;
            changeValue( event->x() );
            emit sliderMoved( value() );
        }
    }
    else
    {
        int i = ( ( event->x() - PADDINGL ) * maximum() ) / ( width() - ( PADDINGR + PADDINGL ) );
        i = __MIN( __MAX( 0, i ), maximum() );
        setToolTip( QString("%1  %" ).arg( i ) );
    }
}

void SoundSlider::changeValue( int x )
{
    setValue( ( ( x - PADDINGL ) * maximum() ) / ( width() - ( PADDINGR + PADDINGL ) ) );
}

void SoundSlider::setMuted( bool m )
{
    b_isMuted = m;
    update();
}

void SoundSlider::paintEvent( QPaintEvent *e )
{
    QPixmap *paintGradient;
    if (b_isMuted)
        paintGradient = &this->pixGradient2;
    else
        paintGradient = &this->pixGradient;

    painter.begin( this );

    float f_scale = paintGradient->width() / float( width() );
    const int offsetDst = int( ( ( width() - ( PADDINGR + PADDINGL ) ) * value() + 100 ) / maximum() ) + PADDINGL;
    const int offsetSrc = int( ( ( paintGradient->width() - ( PADDINGR + PADDINGL ) * f_scale ) * value() + 100 ) / maximum() + PADDINGL * f_scale );

    painter.drawPixmap( 0, 0, offsetDst, height(), *paintGradient, 0, 0, offsetSrc, paintGradient->height() );
    painter.drawPixmap( 0, 0, width(), height(), pixOutside, 0, 0,  pixOutside.width(), pixOutside.height() );

    if (dark)
        painter.setPen(Qt::white);
    else
        painter.setPen(foreground);
    painter.setFont( textfont );
    painter.drawText( textrect, Qt::AlignRight | Qt::AlignVCenter,
                      QString::number( value() ) + '%' );

    painter.end();
    e->accept();
}
