/*****************************************************************************
 * Copyright © 2011-2012 VideoLAN
 * $Id$
 *
 * Authors: Ludovic Fauvet <etix@l0cal.com>
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

#include "timetooltip.hpp"

#include <QApplication>
#include <QPainter>
#include <QBitmap>
#include <QFontMetrics>
#if QT_VERSION < QT_VERSION_CHECK(5, 10, 0)
#include <QDesktopWidget>
#else
#include <QScreen>
#endif

#define TIP_HEIGHT 5
/* PowerVLC: padding around the hover preview, inside the tooltip box */
#define PREVIEW_MARGIN 3

TimeTooltip::TimeTooltip( QWidget *parent ) :
    QWidget( parent )
{
    setWindowFlags( Qt::ToolTip                 |
                    Qt::WindowStaysOnTopHint    |
                    Qt::FramelessWindowHint     );

    // Tell Qt that it doesn't need to erase the background before
    // a paintEvent occurs. This should save some CPU cycles.
    setAttribute( Qt::WA_OpaquePaintEvent );
    setAttribute( Qt::WA_TranslucentBackground );
    setAttribute( Qt::WA_TransparentForMouseEvents );

    // Inherit from the system default font size -5
    mFont = QFont( "Verdana", qMax( qApp->font().pointSize() - 5, 7 ) );
    mTipX = -1;

    // By default the widget is unintialized and should not be displayed
    resize( 0, 0 );
}

void TimeTooltip::adjustPosition()
{
    if( mDisplayedText.isEmpty() )
    {
        resize( 0, 0 );
        return;
    }

    // Get the bounding box required to print the text and add some padding
    QFontMetrics metrics( mFont );
    QRect textbox = metrics.boundingRect( mDisplayedText );
    textbox.adjust( -2, -2, 2, 2 );
    textbox.moveTo( 0, 0 );

    /* PowerVLC: the preview of the hovered position sits above the text,
     * the two centred in a box as wide as the wider of them. */
    const int previewHeight = mPreview.isNull() ? 0
                            : mPreview.height() + 2 * PREVIEW_MARGIN;
    const int previewWidth  = mPreview.isNull() ? 0
                            : mPreview.width() + 2 * PREVIEW_MARGIN;
    QRect box( 0, 0, qMax( textbox.width(), previewWidth ),
               previewHeight + textbox.height() );
    QRect textArea( 0, previewHeight, box.width(), textbox.height() );

    // Resize the widget to fit our needs
    QSize size( box.width() + 1, box.height() + TIP_HEIGHT + 1 );

    /* The desired label position is just above the target.
     * ⚠ PowerVLC: upstream asked for TWICE the height on Windows, to clear
     * the mouse cursor there. That is a FIXED clearance dressed up as a
     * proportional one -- harmless while the tooltip was one line of text
     * (about 25 px), but the hover preview makes the box ten times taller,
     * and the whole tooltip then jumped a preview's height further up the
     * moment the image arrived. The clearance is now what it always meant
     * to be: a constant. */
#if defined( Q_OS_WIN )
    const int cursorClearance = 25;
#else
    const int cursorClearance = 0;
#endif
    QPoint position( mTarget.x() - size.width() / 2,
        mTarget.y() - size.height() - TIP_HEIGHT / 2 - cursorClearance );

    // Keep the tooltip on the same screen if possible
#if QT_VERSION >= QT_VERSION_CHECK(5, 10, 0)
    QRect screen{};
    auto *screenAt = QGuiApplication::screenAt( mTarget );
    if (screenAt != nullptr)
        screen = screenAt->geometry();
#else
    QRect screen = QApplication::desktop()->screenGeometry( mTarget );
#endif
    position.setX( qMax( screen.left(), qMin( position.x(),
        screen.left() + screen.width() - size.width() ) ) );
    position.setY( qMax( screen.top(), qMin( position.y(),
        screen.top() + screen.height() - size.height() ) ) );

    move( position );

    int tipX = mTarget.x() - position.x();
    mTextBox = textArea;
    if( mBox != box || mTipX != tipX )
    {
        mBox = box;
        mTipX = tipX;

        resize( size );
        buildPath();
    }
}

void TimeTooltip::buildPath()
{
    // Prepare the painter path for future use so
    // we only have to generate the text at runtime.

    // Draw the text box
    mPainterPath = QPainterPath();
    mPainterPath.addRect( mBox );

    // Draw the tip
    QPolygonF polygon;
    polygon << QPoint( qMax( 0, mTipX - 3 ), mBox.height() )
            << QPoint( mTipX, mBox.height() + TIP_HEIGHT )
            << QPoint( qMin( mTipX + 3, mBox.width() ), mBox.height() );
    mPainterPath.addPolygon( polygon );

    // Store the simplified version of the path
    mPainterPath = mPainterPath.simplified();
}

void TimeTooltip::setTip( const QPoint& target, const QString& time, const QString& text )
{
    mDisplayedText = time;
    if ( !text.isEmpty() )
        mDisplayedText.append( " - " ).append( text );

    if( mTarget != target || time.length() != mTime.length() || mText != text )
    {
        mTarget = target;
        mTime = time;
        mText = text;
        adjustPosition();
    }

    update();
    raise();
}

/* PowerVLC. Unlike setTip(), this has to lay the tooltip out itself: the
 * preview usually arrives while the mouse sits still, i.e. with the time and
 * the position unchanged, so nothing else would notice the box has grown. */
void TimeTooltip::setPreview( const QPixmap& preview )
{
    if( preview.cacheKey() == mPreview.cacheKey() )
        return;

    mPreview = preview;
    adjustPosition();
    update();
}

void TimeTooltip::show()
{
    setVisible( true );
    raise();
}

void TimeTooltip::paintEvent( QPaintEvent * )
{
    QPainter p( this );
    p.setRenderHints( QPainter::TextAntialiasing );

    p.setPen( Qt::black );
    p.setBrush( qApp->palette().base() );
    p.drawPath( mPainterPath );

    if( !mPreview.isNull() )
        p.drawPixmap( ( mBox.width() - mPreview.width() ) / 2, PREVIEW_MARGIN,
                      mPreview );

    p.setFont( mFont );
    p.setPen( QPen( qApp->palette().text(), 1 ) );
    p.drawText( mTextBox, Qt::AlignCenter, mDisplayedText );
}
