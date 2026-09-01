/*****************************************************************************
 * playlist.cpp : Custom widgets for the playlist
 ****************************************************************************
 * Copyright © 2007-2010 the VideoLAN team
 * $Id$
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Jean-Baptiste Kempf <jb@videolan.org>
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

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "components/playlist/playlist.hpp"
#include "components/playlist/standardpanel.hpp"  /* MainView */
#include "components/playlist/selector.hpp"       /* PLSelector */
#include "components/playlist/playlist_model.hpp" /* PLModel */
#include "components/interface_widgets.hpp"       /* CoverArtLabel */

#include "util/searchlineedit.hpp"

#include "input_manager.hpp"                      /* art signal */
#include "main_interface.hpp"                     /* DropEvent TODO remove this*/

#include <QMenu>
#include <QFile>
#include <QMimeData>
#include <QSignalMapper>
#include <QSlider>
#include <QStackedWidget>
#include <QUrl>

#include <vlc_playlist.h>
#include <vlc_services_discovery.h>

#define PVLC_ML_SCAN_ACTIVE   "powervlc-ml-scan-active"
#define PVLC_ML_SCAN_DONE     "powervlc-ml-scan-done"
#define PVLC_ML_SCAN_TOTAL    "powervlc-ml-scan-total"
#define PVLC_ML_SCAN_REVISION "powervlc-ml-scan-revision"

static int PowerVLCMediaLibraryScanChanged( vlc_object_t *, const char *,
                                             vlc_value_t, vlc_value_t,
                                             void *opaque )
{
    QMetaObject::invokeMethod( static_cast<PlaylistWidget *>( opaque ),
                               "updateScanProgress", Qt::QueuedConnection );
    return VLC_SUCCESS;
}

/**********************************************************************
 * Playlist Widget. The embedded playlist
 **********************************************************************/

PlaylistWidget::PlaylistWidget( intf_thread_t *_p_i, QWidget *_par )
               : QWidget( _par ), p_intf ( _p_i )
{

    setContentsMargins( 0, 3, 0, 3 );

    QGridLayout *layout = new QGridLayout( this );
    layout->setContentsMargins( 0, 0, 0, 0 ); layout->setSpacing( 0 );

    /*******************
     * Left            *
     *******************/
    /* We use a QSplitter for the left part */
    leftSplitter = new QSplitter( Qt::Vertical, this );

    /* Source Selector */
    selector = new PLSelector( this, p_intf );
    leftSplitter->addWidget( selector );

    /* Create a Container for the Art Label
       in order to have a beautiful resizing for the selector above it */
    artContainer = new QStackedWidget;

    /* Art label */
    CoverArtLabel *art = new CoverArtLabel( artContainer, p_intf );
    art->setToolTip( qtr( "Double click to get media information" ) );
    artContainer->addWidget( art );

    connect( THEMIM->getIM(), QOverload<QString>::of(&InputManager::artChanged),
             art, QOverload<const QString &>::of(&CoverArtLabel::showArtUpdate) );
    connect( THEMIM->getIM(), QOverload<input_item_t *>::of(&InputManager::artChanged),
             art, QOverload<input_item_t *>::of(&CoverArtLabel::showArtUpdate) );

    leftSplitter->addWidget( artContainer );

    /*******************
     * Right           *
     *******************/
    /* Initialisation of the playlist */
    playlist_t * p_playlist = THEPL;
    PL_LOCK;
    playlist_item_t *p_root = p_playlist->p_playing;
    PL_UNLOCK;

    setMinimumWidth( 400 );

    PLModel *model = PLModel::getPLModel( p_intf );

    mainView = new StandardPLPanel( this, p_intf, p_root, selector, model );

    QHBoxLayout *topbarLayout = new QHBoxLayout();
    topbarLayout->setSpacing( 10 );
    layout->addLayout( topbarLayout, 0, 0 );

    /* Location Bar */
    locationBar = new LocationBar( model );
    locationBar->setSizePolicy( QSizePolicy::Ignored, QSizePolicy::Preferred );
    topbarLayout->addWidget( locationBar );
    connect( locationBar, &LocationBar::invoked,
             mainView, QOverload<const QModelIndex &>::of(&StandardPLPanel::browseInto) );

    /* Button to switch views */
    QToolButton *viewButton = new QToolButton( this );
    viewButton->setIcon( style()->standardIcon( QStyle::SP_FileDialogDetailedView ) );
    viewButton->setToolTip( qtr("Change playlistview") );
    topbarLayout->addWidget( viewButton );

    viewButton->setMenu( StandardPLPanel::viewSelectionMenu( mainView ));
    connect( viewButton, &QToolButton::clicked, mainView, &StandardPLPanel::cycleViews );

    /* Search */
    searchEdit = new SearchLineEdit( this );
    searchEdit->setMaximumWidth( 250 );
    searchEdit->setMinimumWidth( 80 );
    searchEdit->setToolTip( qtr("Search the playlist") );
    topbarLayout->addWidget( searchEdit );
    connect( searchEdit, &SearchLineEdit::textChanged,
             mainView, &StandardPLPanel::search );
    connect( searchEdit, &SearchLineEdit::searchDelayedChanged,
             mainView, &StandardPLPanel::searchDelayed );

    connect( mainView, &StandardPLPanel::viewChanged,
             this, &PlaylistWidget::changeView );

    /* Connect the activation of the selector to a redefining of the PL */
    connect( selector, &PLSelector::categoryActivated,
             mainView, QOverload<playlist_item_t *, bool>::of(&StandardPLPanel::setRootItem), Qt::DirectConnection );
    connect( selector, &PLSelector::categoryActivated, this,
             [this]( playlist_item_t *, bool listOnly ) {
                 artContainer->setVisible( !listOnly );
             } );
    mainView->setRootItem( p_root, false );
    connect( selector, &PLSelector::SDCategorySelected, mainView, &StandardPLPanel::setWaiting );
    connect( selector, &PLSelector::powerDeviceBusyChanged,
             mainView, &QWidget::setDisabled );

    /* */
    split = new QSplitter( this );

    /* Add the two sides of the QSplitter */
    split->addWidget( leftSplitter );
    split->addWidget( mainView );

    QList<int> sizeList;
    sizeList << 180 << 420 ;
    split->setSizes( sizeList );
    split->setStretchFactor( 0, 0 );
    split->setStretchFactor( 1, 3 );
    split->setCollapsible( 1, false );
    leftSplitter->setMaximumWidth( 250 );

    /* In case we want to keep the splitter information */
    // components shall never write there setting to a fixed location, may infer
    // with other uses of the same component...
    getSettings()->beginGroup("Playlist");
    split->restoreState( getSettings()->value("splitterSizes").toByteArray());
    leftSplitter->restoreState( getSettings()->value("leftSplitterGeometry").toByteArray() );
    getSettings()->endGroup();

    layout->addWidget( split, 1, 0, 1, -1 );

    setAcceptDrops( true );
    setWindowTitle( qtr( "Playlist" ) );
    setWindowRole( "vlc-playlist" );
    setWindowIcon( QApplication::windowIcon() );

    var_Create( p_intf->obj.libvlc, PVLC_ML_SCAN_ACTIVE, VLC_VAR_BOOL );
    var_Create( p_intf->obj.libvlc, PVLC_ML_SCAN_DONE, VLC_VAR_INTEGER );
    var_Create( p_intf->obj.libvlc, PVLC_ML_SCAN_TOTAL, VLC_VAR_INTEGER );
    var_Create( p_intf->obj.libvlc, PVLC_ML_SCAN_REVISION, VLC_VAR_INTEGER );
    var_AddCallback( p_intf->obj.libvlc, PVLC_ML_SCAN_REVISION,
                     PowerVLCMediaLibraryScanChanged, this );
}

bool PlaylistWidget::addNetworkLocation( const QString& mrl )
{
    return selector->addNetworkLocation( mrl );
}

void PlaylistWidget::reloadPowerDevices()
{
    selector->reloadPowerDevices();
}

PlaylistWidget::~PlaylistWidget()
{
    var_DelCallback( p_intf->obj.libvlc, PVLC_ML_SCAN_REVISION,
                     PowerVLCMediaLibraryScanChanged, this );
    getSettings()->beginGroup("Playlist");
    getSettings()->setValue( "splitterSizes", split->saveState() );
    getSettings()->setValue( "leftSplitterGeometry", leftSplitter->saveState() );
    getSettings()->endGroup();
    msg_Dbg( p_intf, "Playlist Destroyed" );
}

void PlaylistWidget::dropEvent( QDropEvent *event )
{
    const int category = selector->getCurrentItemCategory();
    if( category == IS_POWER_ML )
    {
        if( !playlist_IsServicesDiscoveryLoaded( THEPL, "powervlc_library" )
         && playlist_ServicesDiscoveryAdd( THEPL, "powervlc_library" )
                                                        != VLC_SUCCESS )
            return;
        bool imported = false;
        for( const QUrl &url : event->mimeData()->urls() )
        {
            if( !url.isLocalFile() ) continue;
            QByteArray path = QFile::encodeName( url.toLocalFile() );
            services_discovery_import_t request = {
                path.constData(), NULL, NULL, NULL, NULL
            };
            imported |= playlist_ServicesDiscoveryControl( THEPL,
                "powervlc_library", SD_CMD_POWERVLC_IMPORT, &request )
                                                            == VLC_SUCCESS;
        }
        if( imported ) event->acceptProposedAction();
        return;
    }
    if( category != IS_PL && category != IS_ML ) return;

    if( p_intf->p_sys->p_mi )
        p_intf->p_sys->p_mi->dropEventPlay( event, false,
                                            category == IS_PL );
}
void PlaylistWidget::dragEnterEvent( QDragEnterEvent *event )
{
    event->acceptProposedAction();
}

void PlaylistWidget::closeEvent( QCloseEvent *event )
{
    if( THEDP->isDying() )
    {
        p_intf->p_sys->p_mi->playlistVisible = true;
        event->accept();
    }
    else
    {
        p_intf->p_sys->p_mi->playlistVisible = false;
        hide();
        event->ignore();
    }
}

void PlaylistWidget::forceHide()
{
    leftSplitter->hide();
    mainView->hide();
    updateGeometry();
}

void PlaylistWidget::forceShow()
{
    leftSplitter->show();
    mainView->show();
    updateGeometry();
}

void PlaylistWidget::changeView( const QModelIndex& index )
{
    locationBar->setIndex( index );
    updateScanProgress();
}

void PlaylistWidget::updateScanProgress()
{
    if( !var_GetBool( p_intf->obj.libvlc, PVLC_ML_SCAN_ACTIVE ) )
    {
        locationBar->setScanProgressText( QString() );
        return;
    }
    quint64 done = qMax<qint64>( 0, var_GetInteger( p_intf->obj.libvlc,
                                                    PVLC_ML_SCAN_DONE ) );
    quint64 total = qMax<qint64>( 0, var_GetInteger( p_intf->obj.libvlc,
                                                     PVLC_ML_SCAN_TOTAL ) );
    if( total == 0 ) return;
    unsigned percent = done >= total ? 100
                     : static_cast<unsigned>( (double)done * 100.0 / total );
    quint64 remaining = done < total ? total - done : 0;
    QString format = remaining == 1
        ? qtr( "Media Library — scanning %1% · %2 file remaining" )
        : qtr( "Media Library — scanning %1% · %2 files remaining" );
    locationBar->setScanProgressText( format.arg( percent ).arg( remaining ) );
}

void PlaylistWidget::setSearchFieldFocus()
{
    searchEdit->setFocus();
}

#include <QSignalMapper>
#include <QMenu>
#include <QPainter>
LocationBar::LocationBar( VLCModel *m )
{
    setModel( m );
    mapper = new QSignalMapper( this );
    connect( mapper, QSIGNALMAPPER_MAPPEDINT_SIGNAL, this, &LocationBar::invoke );

    btnMore = new LocationButton( "...", false, true, this );
    menuMore = new QMenu( this );
    btnMore->setMenu( menuMore );
}

void LocationBar::setIndex( const QModelIndex &index )
{
    qDeleteAll( buttons );
    buttons.clear();
    qDeleteAll( actions );
    actions.clear();

    QModelIndex i = index;
    bool first = true;

    while( true )
    {
        QString text = model->getTitle( i );

        QAbstractButton *btn = new LocationButton( text, first, !first, this );
        btn->setProperty( "powervlcNormalTitle", text );
        btn->setSizePolicy( QSizePolicy::Maximum, QSizePolicy::Fixed );
        buttons.append( btn );

        QAction *action = new QAction( text, this );
        actions.append( action );
        connect( btn, &QAbstractButton::clicked, action, &QAction::trigger );

        mapper->setMapping( action, model->itemId( i ) );
        connect( action, &QAction::triggered, mapper, QOverload<>::of(&QSignalMapper::map) );

        first = false;

        if( i.isValid() ) i = i.parent();
        else break;
    }

    QString prefix;
    for( int a = actions.count() - 1; a >= 0 ; a-- )
    {
        actions[a]->setText( prefix + actions[a]->text() );
        prefix += QString("  ");
    }

    if( isVisible() ) layOut( size() );
}

void LocationBar::setScanProgressText( const QString &text )
{
    const QString mediaLibrary = qtr( "Media Library" );
    const QString powerLibrary = qtr( "PowerVLC Media Library" );
    bool changed = false;
    for( int i = 0; i < buttons.count(); ++i )
    {
        QAbstractButton *button = qobject_cast<QAbstractButton *>( buttons[i] );
        if( !button ) continue;
        QString normal = button->property( "powervlcNormalTitle" ).toString();
        if( normal != mediaLibrary && normal != powerLibrary ) continue;
        QString displayed = text.isEmpty() ? normal : text;
        if( button->text() != displayed )
        {
            button->setText( displayed );
            if( i < actions.count() ) actions[i]->setText( displayed );
            changed = true;
        }
    }
    if( changed && isVisible() ) layOut( size() );
}

void LocationBar::setRootIndex()
{
    setIndex( QModelIndex() );
}

void LocationBar::invoke( int i_id )
{
    QModelIndex index = model->indexByPLID( i_id, 0 );
    emit invoked ( index );
}

void LocationBar::layOut( const QSize& size )
{
    menuMore->clear();
    widths.clear();

    int count = buttons.count();
    int totalWidth = 0;
    for( int i = 0; i < count; i++ )
    {
        int w = buttons[i]->sizeHint().width();
        widths.append( w );
        totalWidth += w;
        if( totalWidth > size.width() ) break;
    }

    int x = 0;
    int shown = widths.count();

    if( totalWidth > size.width() && count > 1 )
    {
        QSize sz = btnMore->sizeHint();
        btnMore->setGeometry( 0, 0, sz.width(), size.height() );
        btnMore->show();
        x = sz.width();
        totalWidth += x;
    }
    else
    {
        btnMore->hide();
    }
    for( int i = count - 1; i >= 0; i-- )
    {
        if( totalWidth <= size.width() || i == 0)
        {
            buttons[i]->setGeometry( x, 0, qMin( size.width() - x, widths[i] ), size.height() );
            buttons[i]->show();
            x += widths[i];
            totalWidth -= widths[i];
        }
        else
        {
            menuMore->addAction( actions[i] );
            buttons[i]->hide();
            if( i < shown ) totalWidth -= widths[i];
        }
    }
}

void LocationBar::resizeEvent ( QResizeEvent * event )
{
    layOut( event->size() );
}

QSize LocationBar::sizeHint() const
{
    return btnMore->sizeHint();
}

LocationButton::LocationButton( const QString &text, bool bold,
                                bool arrow, QWidget * parent )
  : QPushButton( parent ), b_arrow( arrow )
{
    QFont font;
    font.setBold( bold );
    setFont( font );
    setText( text );
}

#define PADDING 4

void LocationButton::paintEvent ( QPaintEvent * )
{
    QStyleOptionButton option;
    option.initFrom( this );
    option.state |= QStyle::State_Enabled;
    QPainter p( this );

    if( underMouse() )
    {
        p.save();
        p.setRenderHint( QPainter::Antialiasing, true );
        QColor c = palette().color( QPalette::Highlight );
        p.setPen( c );
        p.setBrush( c.lighter( 150 ) );
        p.setOpacity( 0.2 );
        p.drawRoundedRect( option.rect.adjusted( 0, 2, 0, -2 ), 5, 5 );
        p.restore();
    }

    QRect r = option.rect.adjusted( PADDING, 0, -PADDING - (b_arrow ? 10 : 0), 0 );

    QString str( text() );
    /* This check is absurd, but either it is not done properly inside elidedText(),
       or boundingRect() is wrong */
    if( r.width() < fontMetrics().size(Qt::TextHideMnemonic, text()).width() )
        str = fontMetrics().elidedText( text(), Qt::ElideRight, r.width(), Qt::TextHideMnemonic  );
    p.drawText( r, Qt::AlignVCenter | Qt::AlignLeft | Qt::TextHideMnemonic , str );

    if( b_arrow )
    {
        option.rect.setWidth( 10 );
        option.rect.moveRight( rect().right() );
        style()->drawPrimitive( QStyle::PE_IndicatorArrowRight, &option, &p );
    }
}

QSize LocationButton::sizeHint() const
{
    QSize s( fontMetrics().size( Qt::TextHideMnemonic, text() ) );
    /* Add two pixels to width: font metrics are buggy, if you pass text through elidation
       with exactly the width of its bounding rect, sometimes it still elides */
    s.setWidth( s.width() + ( 2 * PADDING ) + ( b_arrow ? 10 : 0 ) + 2 );
    s.setHeight( s.height() + 2 * PADDING );
    return s;
}

#undef PADDING
