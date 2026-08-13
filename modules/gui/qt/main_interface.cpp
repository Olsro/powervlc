/*****************************************************************************
 * main_interface.cpp : Main interface
 ****************************************************************************
 * Copyright (C) 2006-2011 VideoLAN and AUTHORS
 * $Id$
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Jean-Baptiste Kempf <jb@videolan.org>
 *          Ilkka Ollakka <ileoo@videolan.org>
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
 * along with this program; if not, write to the Free Software Foundation, Inc.,
 * 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "qt.hpp"

#include "main_interface.hpp"
#include "input_manager.hpp"                    // Creation
#include "actions_manager.hpp"                  // killInstance

#include "util/customwidgets.hpp"               // qtEventToVLCKey, QVLCStackedWidget
#include "util/qt_dirs.hpp"                     // toNativeSeparators
#include "util/imagehelper.hpp"

#include "components/interface_widgets.hpp"     // bgWidget, videoWidget
#include "components/controller.hpp"            // controllers
#include "components/playlist/playlist.hpp"     // plWidget
#include "dialogs/firstrun.hpp"                 // First Run
#include "dialogs/playlist.hpp"                 // PlaylistDialog

#include "menus.hpp"                            // Menu creation
#include "recents.hpp"                          // RecentItems when DnD

#include <QCloseEvent>
#include <QKeyEvent>

#include <QUrl>
#include <QSize>
#include <QDate>
#include <QMimeData>

#include <QWindow>
#include <QMenu>
#include <QMenuBar>
#include <QLabel>
#include <QStackedWidget>
#include <QScreen>
#ifdef _WIN32
#include <QFileInfo>
#endif

#ifndef QT_NO_STATUSBAR
# include <QStatusBar>
#endif

#if ! HAS_QT510 && defined(QT5_HAS_X11)
# include <QX11Info>
# include <X11/Xlib.h>
#endif

#include <QTimer>

#include <vlc_actions.h>                    /* Wheel event */
#include <vlc_vout_display.h>               /* vout_thread_t and VOUT_ events */

// #define DEBUG_INTF

/* Callback prototypes */
static int PopupMenuCB( vlc_object_t *p_this, const char *psz_variable,
                        vlc_value_t old_val, vlc_value_t new_val, void *param );
static int IntfShowCB( vlc_object_t *p_this, const char *psz_variable,
                       vlc_value_t old_val, vlc_value_t new_val, void *param );
static int IntfBossCB( vlc_object_t *p_this, const char *psz_variable,
                       vlc_value_t old_val, vlc_value_t new_val, void *param );
static int IntfRevealControlsCB( vlc_object_t *p_this, const char *psz_variable,
                                 vlc_value_t old_val, vlc_value_t new_val,
                                 void *param );
#ifdef _WIN32
static int IntfVideoDragCB( vlc_object_t *p_this, const char *psz_variable,
                            vlc_value_t old_val, vlc_value_t new_val,
                            void *param );
#endif
static int IntfRaiseMainCB( vlc_object_t *p_this, const char *psz_variable,
                           vlc_value_t old_val, vlc_value_t new_val,
                           void *param );

const QEvent::Type MainInterface::ToolbarsNeedRebuild =
        (QEvent::Type)QEvent::registerEventType();

MainInterface::MainInterface( intf_thread_t *_p_intf ) : QVLCMW( _p_intf )
{
    /* Variables initialisation */
    bgWidget             = NULL;
    videoWidget          = NULL;
    playlistWidget       = NULL;
    stackCentralOldWidget= NULL;
    lastWinScreen        = NULL;
    sysTray              = NULL;
    fullscreenControls   = NULL;
    cryptedLabel         = NULL;
    controls             = NULL;
    inputC               = NULL;

    b_hideAfterCreation  = false; // --qt-start-minimized
    playlistVisible      = false;
    input_name           = "";
    b_interfaceFullScreen= false;
    b_hasPausedWhenMinimized = false;
    i_kc_offset          = false;
    b_maximizedView      = false;
    b_isWindowTiled      = false;

    /* Ask for Privacy */
    FirstRun::CheckAndRun( this, p_intf );

    /**
     *  Configuration and settings
     *  Pre-building of interface
     **/
    /* Main settings */
    setFocusPolicy( Qt::StrongFocus );
    setAcceptDrops( true );
    setWindowRole( "vlc-main" );
    setWindowIcon( QApplication::windowIcon() );
    setWindowOpacity( var_InheritFloat( p_intf, "qt-opacity" ) );

    /* Does the interface resize to video size or the opposite */
    b_autoresize = var_InheritBool( p_intf, "qt-video-autoresize" );

    /* Are we in the enhanced always-video mode or not ? */
    b_minimalView = var_InheritBool( p_intf, "qt-minimal-view" );

    /* Do we want anoying popups or not */
    i_notificationSetting = var_InheritInteger( p_intf, "qt-notification" );

    /* */
    b_pauseOnMinimize = var_InheritBool( p_intf, "qt-pause-minimized" );

    /* Set the other interface settings */
    settings = getSettings();

    /* */
    b_plDocked = getSettings()->value( "MainWindow/pl-dock-status", true ).toBool();

    /* Should the UI stays on top of other windows */
    b_interfaceOnTop = var_InheritBool( p_intf, "video-on-top" );

    /* "Hide controls during playback" (Video menu) */
    b_autoHideControls = var_InheritBool( p_intf, "qt-hide-controls" );
    b_controlsHiddenPlayback = false;
    b_hiddenDragActive = false;
    b_hiddenDragAnchored = false;
    lastVideoZoom = 0.;
    b_videoDrivenResize = false;
    b_hiddenDragIsResize = false;
    hiddenDragResizeH = hiddenDragResizeV = 0;
    i_autoHideOutsideTicks = i_autoHideRevealTicks = 0;
    autoHideControlsTimer = new QTimer( this );
    autoHideControlsTimer->setInterval( 500 );
    connect( autoHideControlsTimer, &QTimer::timeout,
             this, &MainInterface::autoHideControlsTick );
    autoHideControlsTimer->start();

    /**************************
     *  UI and Widgets design
     **************************/
    setVLCWindowsTitle();

    /************
     * Menu Bar *
     ************/
    VLCMenuBar::createMenuBar( this, p_intf );
    connect( THEMIM->getIM(), &InputManager::voutListChanged,
             THEDP, &DialogsProvider::destroyPopupMenu );

    createMainWidget( settings );

#ifndef QT_NO_STATUSBAR
    /**************
     * Status Bar *
     **************/
    createStatusBar();
    setStatusBarVisibility( getSettings()->value( "MainWindow/status-bar-visible", false ).toBool() );
#endif

    /*********************************
     * Create the Systray Management *
     *********************************/
    initSystray();

    /*************************************************************
     * Connect the input manager to the GUI elements it manages  *
     * Beware initSystray did some connects on input manager too *
     *************************************************************/
    /**
     * Connects on nameChanged()
     * Those connects are different because options can impeach them to trigger.
     **/
    /* Main Interface statusbar */
    connect( THEMIM->getIM(), &InputManager::nameChanged,
             this, &MainInterface::setName );
    /* and title of the Main Interface*/
    if( var_InheritBool( p_intf, "qt-name-in-title" ) )
    {
        connect( THEMIM->getIM(), &InputManager::nameChanged,
                 this, &MainInterface::setVLCWindowsTitle );
    }
    connect( THEMIM, &MainInputManager::inputChanged, this, &MainInterface::onInputChanged );

    /* END CONNECTS ON IM */

    /* VideoWidget connects for asynchronous calls */
    b_videoFullScreen = false;
    connect( this, &MainInterface::askGetVideo,
             this, &MainInterface::getVideoSlot,
             Qt::BlockingQueuedConnection );
    connect( this, &MainInterface::askReleaseVideo,
             this, &MainInterface::releaseVideoSlot,
             Qt::BlockingQueuedConnection );
    connect( this, &MainInterface::askVideoOnTop, this, &MainInterface::setVideoOnTop );

    if( videoWidget )
    {
        if( b_autoresize )
        {
            connect( videoWidget, &VideoWidget::sizeChanged,
                     this, &MainInterface::videoSizeChanged );
        }
        connect( this, &MainInterface::askVideoToResize,
                 this, &MainInterface::setVideoSize );

        connect( this, &MainInterface::askVideoSetFullScreen,
                 this, &MainInterface::setVideoFullScreen );
        connect( this, &MainInterface::askHideMouse,
                 this, &MainInterface::setHideMouse );
    }

    connect( THEDP, &DialogsProvider::toolBarConfUpdated, this, &MainInterface::toolBarConfUpdated );
    installEventFilter( this );

    connect( this, &MainInterface::askToQuit, THEDP, &DialogsProvider::quit );

    connect( this, &MainInterface::askBoss, this, &MainInterface::setBoss );
    connect( this, &MainInterface::askRaise, this, &MainInterface::setRaise );
    connect( this, &MainInterface::askRevealControls,
             this, &MainInterface::revealControlsPlayback );
    connect( this, &MainInterface::askVideoDrag,
             this, &MainInterface::videoDragRelayed );


    connect( THEDP, &DialogsProvider::releaseMouseEvents, this, &MainInterface::voutReleaseMouseEvents ) ;
    /** END of CONNECTS**/


    /************
     * Callbacks
     ************/
    var_AddCallback( p_intf->obj.libvlc, "intf-toggle-fscontrol", IntfShowCB, p_intf );
    var_AddCallback( p_intf->obj.libvlc, "intf-boss", IntfBossCB, p_intf );
    var_AddCallback( p_intf->obj.libvlc, "intf-show", IntfRaiseMainCB, p_intf );

    /* Register callback for the intf-popupmenu variable */
    var_AddCallback( p_intf->obj.libvlc, "intf-popupmenu", PopupMenuCB, p_intf );

    /* "Hide controls during playback" plumbing shared with the core: the
     * bool tells it the controls are gone (fullscreen-style OSD, video
     * double-click rerouted), the trigger is the core asking for them
     * back */
    var_Create( p_intf->obj.libvlc, "intf-controls-hidden", VLC_VAR_BOOL );
    var_Create( p_intf->obj.libvlc, "intf-reveal-controls", VLC_VAR_VOID );
    var_AddCallback( p_intf->obj.libvlc, "intf-reveal-controls",
                     IntfRevealControlsCB, p_intf );

#ifdef _WIN32
    /* ⚠ On Windows the vout builds a child window of its own inside the
     * one we hand it and answers the mouse in its own thread: VideoWidget
     * never sees a single event there, so dragging the picture could not
     * move the window -- and with the controls auto-hidden there is no
     * frame left to grab either. Asking the core for the relay (the
     * variable existing IS the request) is the only channel; everywhere
     * else the widget's own events are used and this stays unregistered. */
    var_Create( p_intf->obj.libvlc, "intf-video-drag", VLC_VAR_INTEGER );
    var_AddCallback( p_intf->obj.libvlc, "intf-video-drag",
                     IntfVideoDragCB, p_intf );
#endif


    /* Final Sizing, restoration and placement of the interface */
    if( settings->value( "MainWindow/playlist-visible", false ).toBool() )
        togglePlaylist();

    QVLCTools::restoreWidgetPosition( settings, this, QSize(600, 420) );

    b_interfaceFullScreen = isFullScreen();

    setVisible( !b_hideAfterCreation );

    /* Switch to minimal view if needed, must be called after the show() */
    if( b_minimalView )
        toggleMinimalView( true );

    computeMinimumSize();
}

MainInterface::~MainInterface()
{
    /* Unsure we hide the videoWidget before destroying it */
    if( stackCentralOldWidget == videoWidget )
        showTab( bgWidget );

    if( videoWidget )
        releaseVideoSlot(true);

    /* Be sure to kill the actionsManager... Only used in the MI and control */
    ActionsManager::killInstance();

    /* Delete the FSC controller */
    delete fullscreenControls;

    /* Save states */

    settings->beginGroup("MainWindow");
    settings->setValue( "pl-dock-status", b_plDocked );

    /* Save playlist state */
    settings->setValue( "playlist-visible", playlistVisible );

    settings->setValue( "adv-controls",
                        getControlsVisibilityStatus() & CONTROLS_ADVANCED );
    settings->setValue( "status-bar-visible", b_statusbarVisible );

    /* Save the stackCentralW sizes */
    settings->setValue( "bgSize", stackWidgetsSizes[bgWidget] );
    settings->setValue( "playlistSize", stackWidgetsSizes[playlistWidget] );
    settings->endGroup();

    /* Save this size */
    QVLCTools::saveWidgetPosition(settings, this);

    /* Unregister callbacks */
    var_DelCallback( p_intf->obj.libvlc, "intf-boss", IntfBossCB, p_intf );
    var_DelCallback( p_intf->obj.libvlc, "intf-show", IntfRaiseMainCB, p_intf );
    var_DelCallback( p_intf->obj.libvlc, "intf-toggle-fscontrol", IntfShowCB, p_intf );
    var_DelCallback( p_intf->obj.libvlc, "intf-popupmenu", PopupMenuCB, p_intf );
    var_DelCallback( p_intf->obj.libvlc, "intf-reveal-controls",
                     IntfRevealControlsCB, p_intf );
#ifdef _WIN32
    var_DelCallback( p_intf->obj.libvlc, "intf-video-drag",
                     IntfVideoDragCB, p_intf );
    var_Destroy( p_intf->obj.libvlc, "intf-video-drag" );
#endif
    var_SetBool( p_intf->obj.libvlc, "intf-controls-hidden", false );

    p_intf->p_sys->p_mi = NULL;
}

void MainInterface::computeMinimumSize()
{
    int minWidth = 80;
    if( menuBar()->isVisible() )
        minWidth += controls->sizeHint().width();

    setMinimumWidth( minWidth );
}

/*****************************
 *   Main UI handling        *
 *****************************/
void MainInterface::recreateToolbars()
{
    bool b_adv = getControlsVisibilityStatus() & CONTROLS_ADVANCED;

    delete controls;
    delete inputC;

    controls = new ControlsWidget( p_intf, b_adv, this );
    inputC = new InputControlsWidget( p_intf, this );
    mainLayout->insertWidget( 2, inputC );
    mainLayout->insertWidget( settings->value( "MainWindow/ToolbarPos", false ).toBool() ? 0: 3,
                              controls );

    if( fullscreenControls )
    {
        delete fullscreenControls;
        fullscreenControls = new FullscreenControllerWidget( p_intf, this );
        connect( fullscreenControls, &FullscreenControllerWidget::keyPressed,
                 this, &MainInterface::handleKeyPress );
        THEMIM->requestVoutUpdate();
    }

    setMinimalView( b_minimalView );
}

void MainInterface::reloadPrefs()
{
    i_notificationSetting = var_InheritInteger( p_intf, "qt-notification" );
    b_pauseOnMinimize = var_InheritBool( p_intf, "qt-pause-minimized" );
    if( !var_InheritBool( p_intf, "qt-fs-controller" ) && fullscreenControls )
    {
        delete fullscreenControls;
        fullscreenControls = NULL;
    }
}

void MainInterface::createResumePanel( QWidget *w )
{
    resumePanel = new QWidget( w );
    resumePanel->hide();
    QHBoxLayout *resumePanelLayout = new QHBoxLayout( resumePanel );
    resumePanelLayout->setSpacing( 0 ); resumePanelLayout->setContentsMargins( 0, 0, 0, 0 );

    QLabel *continuePixmapLabel = new QLabel();
    continuePixmapLabel->setPixmap( ImageHelper::loadSvgToPixmap( ":/menu/help.svg" , fontMetrics().height(), fontMetrics().height()) );
    continuePixmapLabel->setContentsMargins( 5, 0, 5, 0 );

    QLabel *continueLabel = new QLabel( qtr( "Do you want to restart the playback where left off?") );

    QToolButton *cancel = new QToolButton( resumePanel );
    cancel->setAutoRaise( true );
    cancel->setText( "X" );

    QPushButton *ok = new QPushButton( qtr( "&Continue" )  );

    resumePanelLayout->addWidget( continuePixmapLabel );
    resumePanelLayout->addWidget( continueLabel );
    resumePanelLayout->addStretch( 1 );
    resumePanelLayout->addWidget( ok );
    resumePanelLayout->addWidget( cancel );

    resumeTimer = new QTimer( resumePanel );
    resumeTimer->setSingleShot( true );
    resumeTimer->setInterval( 6000 );

    connect( resumeTimer, &QTimer::timeout, this, &MainInterface::hideResumePanel );
    connect( cancel, &QToolButton::clicked, this, &MainInterface::hideResumePanel );
    connect( THEMIM->getIM(), &InputManager::resumePlayback, this, &MainInterface::showResumePanel );
    BUTTONACT( ok, resumePlayback );

    w->layout()->addWidget( resumePanel );
}

void MainInterface::showResumePanel( int64_t _time ) {
    int setting = var_InheritInteger( p_intf, "qt-continue" );

    if( setting == 0 )
        return;

    i_resumeTime = _time;

    if( setting == 2)
        resumePlayback();
    else
    {
        if( !isFullScreen() && !isMaximized() && !b_isWindowTiled )
            resizeWindow( width(), height() + resumePanel->height() );
        resumePanel->setVisible(true);
        resumeTimer->start();
    }
}

void MainInterface::hideResumePanel()
{
    if( resumePanel->isVisible() )
    {
        if( !isFullScreen() && !isMaximized() && !b_isWindowTiled )
            resizeWindow( width(), height() - resumePanel->height() );
        resumePanel->hide();
        resumeTimer->stop();
    }
}

void MainInterface::resumePlayback()
{
    if( THEMIM->getIM()->hasInput() ) {
        var_SetInteger( THEMIM->getInput(), "time", i_resumeTime );
    }
    hideResumePanel();
}

void MainInterface::onInputChanged( bool hasInput )
{
    if( hasInput == false )
        return;
    int autoRaise = var_InheritInteger( p_intf, "qt-auto-raise" );
    if ( autoRaise == MainInterface::RAISE_NEVER )
        return;
    if( THEMIM->getIM()->hasVideo() == true )
    {
        if( ( autoRaise & MainInterface::RAISE_VIDEO ) == 0 )
            return;
    }
    else if ( ( autoRaise & MainInterface::RAISE_AUDIO ) == 0 )
        return;
    emit askRaise();
}

void MainInterface::createMainWidget( QSettings *creationSettings )
{
    /* Create the main Widget and the mainLayout */
    QWidget *main = new QWidget;
    setCentralWidget( main );
    mainLayout = new QVBoxLayout( main );
    main->setContentsMargins( 0, 0, 0, 0 );
    mainLayout->setSpacing( 0 ); mainLayout->setContentsMargins( 0, 0, 0, 0 );

    createResumePanel( main );
    /* */
    stackCentralW = new QVLCStackedWidget( main );

    /* Bg Cone */
    if ( QDate::currentDate().dayOfYear() >= QT_XMAS_JOKE_DAY
         && var_InheritBool( p_intf, "qt-icon-change" ) )
    {
        bgWidget = new EasterEggBackgroundWidget( p_intf );
        connect( this, SIGNAL( kc_pressed() ), bgWidget, SLOT( animate() ) );
    }
    else
        bgWidget = new BackgroundWidget( p_intf );

    stackCentralW->addWidget( bgWidget );
    if ( !var_InheritBool( p_intf, "qt-bgcone" ) )
        bgWidget->setWithArt( false );
    else
        if ( var_InheritBool( p_intf, "qt-bgcone-expands" ) )
            bgWidget->setExpandstoHeight( true );

    /* And video Outputs */
    if( var_InheritBool( p_intf, "embedded-video" ) )
    {
        videoWidget = new VideoWidget( p_intf, stackCentralW );
        stackCentralW->addWidget( videoWidget );
    }
    mainLayout->insertWidget( 1, stackCentralW );

    stackWidgetsSizes[bgWidget] =
        creationSettings->value( "MainWindow/bgSize", QSize( 600, 0 ) ).toSize();
    /* Resize even if no-auto-resize, because we are at creation */
    resizeStack( stackWidgetsSizes[bgWidget].width(), stackWidgetsSizes[bgWidget].height() );

    /* Create the CONTROLS Widget */
    controls = new ControlsWidget( p_intf,
        creationSettings->value( "MainWindow/adv-controls", false ).toBool(), this );
    inputC = new InputControlsWidget( p_intf, this );

    mainLayout->insertWidget( 2, inputC );
    mainLayout->insertWidget(
        creationSettings->value( "MainWindow/ToolbarPos", false ).toBool() ? 0: 3,
        controls );

    /* Visualisation, disabled for now, they SUCK */
    #if 0
    visualSelector = new VisualSelector( p_intf );
    mainLayout->insertWidget( 0, visualSelector );
    visualSelector->hide();
    #endif


    /* Enable the popup menu in the MI */
    main->setContextMenuPolicy( Qt::CustomContextMenu );
    connect( main, &QWidget::customContextMenuRequested,
             THEDP, &DialogsProvider::setPopupMenu );

    if ( depth() > 8 ) /* 8bit depth has too many issues with opacity */
        /* Create the FULLSCREEN CONTROLS Widget */
        if( var_InheritBool( p_intf, "qt-fs-controller" ) )
        {
            fullscreenControls = new FullscreenControllerWidget( p_intf, this );
            connect( fullscreenControls, &FullscreenControllerWidget::keyPressed,
                     this, &MainInterface::handleKeyPress );
        }

    if ( b_interfaceOnTop )
        setWindowFlags( windowFlags() | Qt::WindowStaysOnTopHint );
}

inline void MainInterface::initSystray()
{
    bool b_systrayAvailable = QSystemTrayIcon::isSystemTrayAvailable();
    bool b_systrayWanted = var_InheritBool( p_intf, "qt-system-tray" );

    if( var_InheritBool( p_intf, "qt-start-minimized") )
    {
        if( b_systrayAvailable )
        {
            b_systrayWanted = true;
            b_hideAfterCreation = true;
        }
        else
            msg_Err( p_intf, "cannot start minimized without system tray bar" );
    }

    if( b_systrayAvailable && b_systrayWanted )
        createSystray();
}

#ifndef QT_NO_STATUSBAR
inline void MainInterface::createStatusBar()
{
    /****************
     *  Status Bar  *
     ****************/
    /* Widgets Creation*/
    QStatusBar *statusBarr = statusBar();

    TimeLabel *timeLabel = new TimeLabel( p_intf );
    nameLabel = new ClickableQLabel();
    nameLabel->setTextInteractionFlags( Qt::TextSelectableByMouse
                                      | Qt::TextSelectableByKeyboard );
    SpeedLabel *speedLabel = new SpeedLabel( p_intf, this );

    /* Styling those labels */
    timeLabel->setFrameStyle( QFrame::Sunken | QFrame::Panel );
    speedLabel->setFrameStyle( QFrame::Sunken | QFrame::Panel );
    nameLabel->setFrameStyle( QFrame::Sunken | QFrame::StyledPanel);
    auto updateStyle = [=]() {
        timeLabel->setStyleSheet(
            "QLabel:hover { color: black; background-color: rgba(255, 255, 255, 50%) }" );
        speedLabel->setStyleSheet(
            "QLabel:hover { color: black; background-color: rgba(255, 255, 255, 50%) }" );
        /* pad both label and its tooltip */
        nameLabel->setStyleSheet( "padding-left: 5px; padding-right: 5px;" );

    };
    updateStyle();
//same as Qt::AA_UseStyleSheetPropagationInWidgetStyles
#if !HAS_QT57
    connect(qApp, &QApplication::paletteChanged, this, [updateStyle](){
        updateStyle();
    });
#endif

    /* and adding those */
    statusBarr->addWidget( nameLabel, 8 );
    statusBarr->addPermanentWidget( speedLabel, 0 );
    statusBarr->addPermanentWidget( timeLabel, 0 );

    connect( nameLabel, SIGNAL( doubleClicked() ), THEDP, SLOT( epgDialog() ) );
    /* timeLabel behaviour:
       - double clicking opens the goto time dialog
       - right-clicking and clicking just toggle between remaining and
         elapsed time.*/
    connect( timeLabel, &TimeLabel::doubleClicked, THEDP, &DialogsProvider::gotoTimeDialog );

#ifndef QT_NO_STATUSBAR
    connect( THEMIM->getIM(), &InputManager::encryptionChanged,
             this, &MainInterface::showCryptedLabel );
#endif

    /* This shouldn't be necessary, but for somehow reason, the statusBarr
       starts at height of 20px and when a text is shown it needs more space.
       But, as the QMainWindow policy doesn't allow statusBar to change QMW's
       geometry, we need to force a height. If you have a better idea, please
       tell me -- jb
     */
    statusBarr->setFixedHeight( statusBarr->sizeHint().height() + 2 );
}
#endif

/**********************************************************************
 * Handling of sizing of the components
 **********************************************************************/

void MainInterface::debug()
{
#ifdef DEBUG_INTF
    if( controls ) {
        msg_Dbg( p_intf, "Controls size: %i - %i", controls->size().height(), controls->size().width() );
        msg_Dbg( p_intf, "Controls minimumsize: %i - %i", controls->minimumSize().height(), controls->minimumSize().width() );
        msg_Dbg( p_intf, "Controls sizeHint: %i - %i", controls->sizeHint().height(), controls->sizeHint().width() );
    }

    msg_Dbg( p_intf, "size: %i - %i", size().height(), size().width() );
    msg_Dbg( p_intf, "sizeHint: %i - %i", sizeHint().height(), sizeHint().width() );
    msg_Dbg( p_intf, "minimumsize: %i - %i", minimumSize().height(), minimumSize().width() );

    msg_Dbg( p_intf, "Stack size: %i - %i", stackCentralW->size().height(), stackCentralW->size().width() );
    msg_Dbg( p_intf, "Stack sizeHint: %i - %i", stackCentralW->sizeHint().height(), stackCentralW->sizeHint().width() );
    msg_Dbg( p_intf, "Central size: %i - %i", centralWidget()->size().height(), centralWidget()->size().width() );
#endif
}

inline void MainInterface::showVideo() { showTab( videoWidget ); }
inline void MainInterface::restoreStackOldWidget( bool video_closing )
            { showTab( stackCentralOldWidget, video_closing ); }

inline void MainInterface::showTab( QWidget *widget, bool video_closing )
{
    if ( !widget ) widget = bgWidget; /* trying to restore a null oldwidget */
#ifdef DEBUG_INTF
    if ( stackCentralOldWidget )
        msg_Dbg( p_intf, "Old stackCentralOldWidget %s at index %i",
                 stackCentralOldWidget->metaObject()->className(),
                 stackCentralW->indexOf( stackCentralOldWidget ) );
    msg_Dbg( p_intf, "ShowTab request for %s", widget->metaObject()->className() );
#endif
    if ( stackCentralW->currentWidget() == widget )
        return;

    /* fixing when the playlist has been undocked after being hidden.
       restoreStackOldWidget() is called when video stops but
       stackCentralOldWidget would still be pointing to playlist */
    if ( widget == playlistWidget && !isPlDocked() )
        widget = bgWidget;

    stackCentralOldWidget = stackCentralW->currentWidget();
    if( !isFullScreen() )
        stackWidgetsSizes[stackCentralOldWidget] = stackCentralW->size();

    /* If we are playing video, embedded */
    if( !video_closing && videoWidget && THEMIM->getIM()->hasVideo() )
    {
        /* Video -> Playlist */
        if( videoWidget == stackCentralOldWidget && widget == playlistWidget )
        {
            stackCentralW->removeWidget( videoWidget );
            videoWidget->show(); videoWidget->raise();
        }

        /* Playlist -> Video */
        if( playlistWidget == stackCentralOldWidget && widget == videoWidget )
        {
            playlistWidget->artContainer->removeWidget( videoWidget );
            videoWidget->show(); videoWidget->raise();
            stackCentralW->addWidget( videoWidget );
        }

        /* Embedded playlist -> Non-embedded playlist */
        if( bgWidget == stackCentralOldWidget && widget == videoWidget )
        {
            /* In rare case when video is started before the interface */
            if( playlistWidget != NULL )
                playlistWidget->artContainer->removeWidget( videoWidget );
            videoWidget->show(); videoWidget->raise();
            stackCentralW->addWidget( videoWidget );
            stackCentralW->setCurrentWidget( videoWidget );
        }
    }

    stackCentralW->setCurrentWidget( widget );
    if( b_autoresize )
        resizeStack( stackWidgetsSizes[widget].width(), stackWidgetsSizes[widget].height() );

#ifdef DEBUG_INTF
    msg_Dbg( p_intf, "Stack state changed to %s, index %i",
              stackCentralW->currentWidget()->metaObject()->className(),
              stackCentralW->currentIndex() );
    msg_Dbg( p_intf, "New stackCentralOldWidget %s at index %i",
              stackCentralOldWidget->metaObject()->className(),
              stackCentralW->indexOf( stackCentralOldWidget ) );
#endif

    /* This part is done later, to account for the new pl size */
    if( !video_closing && videoWidget && THEMIM->getIM()->hasVideo() &&
        videoWidget == stackCentralOldWidget && widget == playlistWidget )
    {
        playlistWidget->artContainer->addWidget( videoWidget );
        playlistWidget->artContainer->setCurrentWidget( videoWidget );
    }
}

void MainInterface::toggleFSC()
{
   if( !fullscreenControls ) return;

   IMEvent *eShow = new IMEvent( IMEvent::FullscreenControlToggle );
   QApplication::postEvent( fullscreenControls, eShow );
}

/****************************************************************************
 * Video Handling
 ****************************************************************************/

/**
 * NOTE:
 * You must not change the state of this object or other Qt UI objects,
 * from the video output thread - only from the Qt UI main loop thread.
 * All window provider queries must be handled through signals or events.
 * That's why we have all those emit statements...
 */
bool MainInterface::getVideo( struct vout_window_t *p_wnd,
                              unsigned int i_width, unsigned int i_height,
                              bool fullscreen )
{
    bool result;

    /* This is a blocking call signal. Results are stored directly in the
     * vout_window_t and boolean pointers. Beware of deadlocks! */
    emit askGetVideo( p_wnd, i_width, i_height, fullscreen, &result );
    return result;
}

void MainInterface::getVideoSlot( struct vout_window_t *p_wnd,
                                  unsigned i_width, unsigned i_height,
                                  bool fullscreen, bool *res )
{
    /* Hidden or minimized, activate */
    if( isHidden() || isMinimized() )
        toggleUpdateSystrayMenu();

    /* Request the videoWidget */
    if ( !videoWidget )
    {
        videoWidget = new VideoWidget( p_intf, stackCentralW );
        stackCentralW->addWidget( videoWidget );
    }
    *res = videoWidget->request( p_wnd );
    if( *res ) /* The videoWidget is available */
    {
        /* first source for the picture ratio the bare window is kept at
         * ("Hide controls during playback"); setVideoSize() refreshes it
         * afterwards, but only ever gets called with autoresize on */
        if( i_width > 0 && i_height > 0 )
            videoNativeSize = QSize( i_width, i_height );

        setVideoFullScreen( fullscreen );

        /* Consider the video active now */
        showVideo();

        /* Ask videoWidget to resize correctly, if we are in normal mode */
        if( b_autoresize ) {
#if HAS_QT56
            qreal factor = videoWidget->devicePixelRatioF();

            i_width = qRound( (qreal) i_width / factor );
            i_height = qRound( (qreal) i_height / factor );
#endif

            videoWidget->setSize( i_width, i_height );
        }
    }
}

/* Asynchronous call from the WindowClose function */
void MainInterface::releaseVideo( void )
{
    emit askReleaseVideo(false);
}

/* Function that is CONNECTED to the previous emit */
void MainInterface::releaseVideoSlot( bool forced )
{
    /* This function is called when the embedded video window is destroyed,
     * or in the rare case that the embedded window is still here but the
     * Qt interface exits. */
    assert( videoWidget );
    videoWidget->release( forced );
    setVideoOnTop( false );
    setVideoFullScreen( false );
    hideResumePanel();

    if( stackCentralW->currentWidget() == videoWidget )
        restoreStackOldWidget( true );
    else if( playlistWidget &&
             playlistWidget->artContainer->currentWidget() == videoWidget )
    {
        playlistWidget->artContainer->setCurrentIndex( 0 );
        stackCentralW->addWidget( videoWidget );
    }

    /* We don't want to have a blank video to popup */
    stackCentralOldWidget = bgWidget;
}

// The provided size is in physical pixels, coming from the core.
void MainInterface::setVideoSize( unsigned int w, unsigned int h )
{
    /* Everything below works in LOGICAL pixels: the picture box, the
     * window geometry and the video widget all do, and mixing the two
     * units on a HiDPI screen would put the box off by the scale
     * factor. */
#if HAS_QT56
    float factor = videoWidget ? videoWidget->devicePixelRatioF() : 1.0f;
#else
    float factor = 1.0f;
#endif
    QSize requested( qRound( (float)w / factor ), qRound( (float)h / factor ) );
    if( requested.width() > 0 && requested.height() > 0 )
        videoNativeSize = requested;

    if( b_controlsHiddenPlayback )
    {
        hiddenWindowFollowVideoSize( requested );
        return;
    }

    /* see pictureSizeForRequest(): the bare window is the picture
     * itself, the decorated one keeps its chrome around it, but both
     * follow the same rule */
    QSize picture = pictureSizeForRequest( requested,
        videoWidget ? videoWidget->size() : QSize() );
    if( picture.width() <= 0 || picture.height() <= 0 )
        return;
    w = picture.width();
    h = picture.height();

    if (!isFullScreen() && !isMaximized() )
    {
        /* Resize video widget to video size, or keep it at the same
         * size. Call setSize() either way so that vout_window_ReportSize
         * will always get called.
         * If the video size is too large for the screen, resize it
         * to the screen size.
         */
        if (b_autoresize)
        {
            /* A picture bigger than the screen has to be scaled down to
             * what is left once the window's own furniture is counted.
             *
             * ⚠ Upstream looked at the HEIGHT alone and then took the full
             * screen WIDTH: a 1080p film opened a window as wide as the
             * screen plus its frame borders, as tall as the work area plus
             * whatever its chrome estimate was short of, and the picture
             * inside it was letterboxed for good measure. And nothing ever
             * moved the window afterwards, so one that already sat low on
             * the screen simply grew under the task bar (reported on
             * Windows XP with Big Buck Bunny, 13/08/2026).
             *
             * The furniture is measured, not estimated: the difference
             * between the whole window, frame included, and the widget the
             * video lives in IS everything else, whatever it is made of --
             * the same measurement the auto-hidden window is built on. */
            const QRect available = availableScreenGeometry();
            const QSize chrome = frameGeometry().size() - stackCentralW->size();
            const QSize box( available.width() - chrome.width(),
                             available.height() - chrome.height() );

            if( box.width() > 0 && box.height() > 0
             && ( (int)w > box.width() || (int)h > box.height() ) )
            {
                const double fit = qMin( (double)box.width() / (double)w,
                                         (double)box.height() / (double)h );
                w = qMax( 1, (int)( w * fit ) );
                h = qMax( 1, (int)( h * fit ) );
                /* what the user is now watching in: a later crop or aspect
                 * change is fitted into this, not into the full picture */
                pictureBox = QSize( w, h );
            }
            msg_Dbg( p_intf, "Logical video size: %ux%u", w, h );

            setVideoWidgetSizeFromRequest( QSize( w, h ) );
            /* ... and put back on screen whatever the resize did */
            QTimer::singleShot( 0, this, &MainInterface::keepInsideScreen );
        }
        else
            setVideoWidgetSizeFromRequest( videoWidget->size() );
    }
}

/* Resizing the video widget because the VOUT asked for it, as opposed to
 * the user dragging the window frame. Qt has no equivalent of AppKit's
 * -windowWillResize:toSize: (which only the user reaches), and
 * resizeEvent() fires on both, so our own resizes are flagged here for
 * resizeEvent() to skip: the picture box must remember what the USER
 * chose, never what a crop asked for. The flag is dropped on the next
 * turn of the event loop, once the layout has settled. */
void MainInterface::setVideoWidgetSizeFromRequest( const QSize &size )
{
    if( !videoWidget )
        return;
    lastVideoRequestSize = size;
    b_videoDrivenResize = true;
    videoWidget->setSize( size.width(), size.height() );
    QTimer::singleShot( 0, this, [this]() { b_videoDrivenResize = false; } );
}

void MainInterface::resizeEvent( QResizeEvent *event )
{
    QVLCMW::resizeEvent( event );

    /* the user resized the decorated window by hand (frame drag, tiling,
     * maximise): that is the box a later crop has to fit into. The bare
     * window records its own box while it is being dragged. */
    if( b_videoDrivenResize || b_controlsHiddenPlayback || !videoWidget )
        return;
    if( stackCentralW->currentWidget() != videoWidget )
        return;
    if( videoWidget->size() == lastVideoRequestSize )
        return;
    pictureBox = videoWidget->size();
}

void MainInterface::videoSizeChanged( int w, int h )
{
    if( !playlistWidget || playlistWidget->artContainer->currentWidget() != videoWidget )
        resizeStack( w, h );
}

void MainInterface::setVideoFullScreen( bool fs )
{
    b_videoFullScreen = fs;
    if( fs )
    {
        int numscreen = var_InheritInteger( p_intf, "qt-fullscreen-screennumber" );

        if ( numscreen >= 0 && numscreen < QGuiApplication::screens().length() )
        {
            if( fullscreenControls )
                fullscreenControls->setTargetScreen( numscreen );

            QRect screenres = QGuiApplication::screens()[ numscreen ]->geometry();
            lastWinScreen = windowHandle()->screen();
            windowHandle()->setScreen(QGuiApplication::screens()[numscreen]);

            /* To be sure window is on proper-screen in xinerama */
            if( !screenres.contains( pos() ) )
            {
                lastWinPosition = pos();
                lastWinSize = size();
                msg_Dbg( p_intf, "Moving video to correct position");
                move( QPoint( screenres.x(), screenres.y() ) );
            }
        }

        if( playlistWidget != NULL && playlistWidget->artContainer->currentWidget() == videoWidget )
            showTab( videoWidget );

        /* we won't be able to get its windowed sized once in fullscreen, so update it now */
        stackWidgetsSizes[stackCentralW->currentWidget()] = stackCentralW->size();

        /* */
        displayNormalView();
        setInterfaceFullScreen( true );
    }
    else
    {
        setMinimalView( b_minimalView );
        setInterfaceFullScreen( b_interfaceFullScreen );
        if( lastWinScreen != NULL )
            windowHandle()->setScreen(lastWinScreen);
        if( lastWinPosition.isNull() == false )
        {
            move( lastWinPosition );
            resizeWindow( lastWinSize.width(), lastWinSize.height() );
            lastWinPosition = QPoint();
            lastWinSize = QSize();
        }

    }
    videoWidget->sync();
}

void MainInterface::setHideMouse( bool hide )
{
    videoWidget->setCursor( hide ? Qt::BlankCursor : Qt::ArrowCursor );
}

/* Slot to change the video always-on-top flag.
 * Emit askVideoOnTop() to invoke this from other thread. */
void MainInterface::setVideoOnTop( bool on_top )
{
    //don't apply changes if user has already sets its interface on top
    if ( b_interfaceOnTop )
        return;

    Qt::WindowFlags oldflags = windowFlags(), newflags;

    if( on_top )
        newflags = oldflags | Qt::WindowStaysOnTopHint;
    else
        newflags = oldflags & ~Qt::WindowStaysOnTopHint;
    if( newflags != oldflags && !b_videoFullScreen )
    {
        setWindowFlags( newflags );
        show(); /* necessary to apply window flags */
    }
}

void MainInterface::setInterfaceAlwaysOnTop( bool on_top )
{
    b_interfaceOnTop = on_top;
    Qt::WindowFlags oldflags = windowFlags(), newflags;

    if( on_top )
        newflags = oldflags | Qt::WindowStaysOnTopHint;
    else
        newflags = oldflags & ~Qt::WindowStaysOnTopHint;
    if( newflags != oldflags && !b_videoFullScreen )
    {
        setWindowFlags( newflags );
        show(); /* necessary to apply window flags */
    }
    /* the same switch now lives in two menus (View, and Video right above
     * "Hide Controls" as on the mac): whichever is used, both follow */
    emit alwaysOnTopToggled( on_top );
}

/* Asynchronous call from WindowControl function */
int MainInterface::controlVideo( int i_query, va_list args )
{
    switch( i_query )
    {
    case VOUT_WINDOW_SET_SIZE:
    {
        unsigned int i_width  = va_arg( args, unsigned int );
        unsigned int i_height = va_arg( args, unsigned int );

        emit askVideoToResize( i_width, i_height );
        return VLC_SUCCESS;
    }
    case VOUT_WINDOW_SET_STATE:
    {
        unsigned i_arg = va_arg( args, unsigned );
        unsigned on_top = i_arg & VOUT_WINDOW_STATE_ABOVE;

        emit askVideoOnTop( on_top != 0 );
        return VLC_SUCCESS;
    }
    case VOUT_WINDOW_SET_FULLSCREEN:
    {
        bool b_fs = va_arg( args, int );

        emit askVideoSetFullScreen( b_fs );
        return VLC_SUCCESS;
    }
    case VOUT_WINDOW_HIDE_MOUSE:
    {
        bool b_hide = va_arg( args, int );

        emit askHideMouse( b_hide );
        return VLC_SUCCESS;
    }
    default:
        msg_Warn( p_intf, "unsupported control query" );
        return VLC_EGENERIC;
    }
}

/*****************************************************************************
 * Playlist, Visualisation and Menus handling
 *****************************************************************************/
/**
 * Toggle the playlist widget or dialog
 **/
void MainInterface::createPlaylist()
{
    PlaylistDialog *dialog = PlaylistDialog::getInstance( p_intf );

    if( b_plDocked )
    {
        playlistWidget = dialog->exportPlaylistWidget();
        stackCentralW->addWidget( playlistWidget );
        stackWidgetsSizes[playlistWidget] = settings->value( "playlistSize", QSize( 600, 300 ) ).toSize();
    }
    connect( dialog, &PlaylistDialog::visibilityChanged, this, &MainInterface::setPlaylistVisibility );
}

void MainInterface::togglePlaylist()
{
    if( !playlistWidget ) createPlaylist();

    PlaylistDialog *dialog = PlaylistDialog::getInstance( p_intf );
    if( b_plDocked )
    {
        if ( dialog->hasPlaylistWidget() )
            playlistWidget = dialog->exportPlaylistWidget();
        /* Playlist is not visible, show it */
        if( stackCentralW->currentWidget() != playlistWidget )
        {
            if( stackCentralW->indexOf( playlistWidget ) == -1 )
                stackCentralW->addWidget( playlistWidget );
            showTab( playlistWidget );
        }
        else /* Hide it! */
        {
            restoreStackOldWidget();
        }
        playlistVisible = ( stackCentralW->currentWidget() == playlistWidget );
    }
    else
    {
        playlistVisible = !playlistVisible;
        if ( ! dialog->hasPlaylistWidget() )
            dialog->importPlaylistWidget( playlistWidget );
        if ( playlistVisible )
            dialog->show();
        else
            dialog->hide();
    }
    debug();
}

const Qt::Key MainInterface::kc[10] =
{
    Qt::Key_Up, Qt::Key_Up,
    Qt::Key_Down, Qt::Key_Down,
    Qt::Key_Left, Qt::Key_Right, Qt::Key_Left, Qt::Key_Right,
    Qt::Key_B, Qt::Key_A
};

void MainInterface::dockPlaylist( bool p_docked )
{
    if( b_plDocked == p_docked ) return;
    /* some extra check */
    if ( b_plDocked && !playlistWidget ) createPlaylist();

    b_plDocked = p_docked;
    PlaylistDialog *dialog = PlaylistDialog::getInstance( p_intf );

    if( !p_docked ) /* Previously docked */
    {
        playlistVisible = playlistWidget->isVisible();

        /* repositioning the videowidget __before__ exporting the
           playlistwidget into the playlist dialog avoids two unneeded
           calls to the server in the qt library to reparent the underlying
           native window back and forth.
           For Wayland, this is mandatory since reparenting is not implemented.
           For X11 or Windows, this is just an optimization. */
        if ( videoWidget && THEMIM->getIM()->hasVideo() )
            showTab(videoWidget);
        else
            showTab(bgWidget);

        /* playlistwidget exported into the playlist dialog */
        stackCentralW->removeWidget( playlistWidget );
        dialog->importPlaylistWidget( playlistWidget );
        if ( playlistVisible ) dialog->show();
    }
    else /* Previously undocked */
    {
        playlistVisible = dialog->isVisible() && !( videoWidget && THEMIM->getIM()->hasVideo() );
        dialog->hide();
        playlistWidget = dialog->exportPlaylistWidget();
        stackCentralW->addWidget( playlistWidget );

        /* If playlist is invisible don't show it */
        if( playlistVisible ) showTab( playlistWidget );
    }
}

/*
 * displayNormalView is the private function used by
 * the SLOT setVideoFullScreen to restore the menuBar
 * if minimal view is off
 */
void MainInterface::displayNormalView()
{
    menuBar()->setVisible( false );
    controls->setVisible( false );
#ifndef QT_NO_STATUSBAR
    statusBar()->setVisible( false );
#endif
    inputC->setVisible( false );
}

/*
 * setMinimalView is the private function used by
 * the SLOT toggleMinimalView
 */
void MainInterface::setMinimalView( bool b_minimal )
{
    bool b_menuBarVisible = menuBar()->isVisible();
    bool b_controlsVisible = controls->isVisible();
#ifndef QT_NO_STATUSBAR
    bool b_statusBarVisible = statusBar()->isVisible();
#endif
    bool b_inputCVisible = inputC->isVisible();

    if( !isFullScreen() && !isMaximized() && b_minimal && !b_isWindowTiled )
    {
        int i_heightChange = 0;

        if( b_menuBarVisible )
            i_heightChange += menuBar()->height();
        if( b_controlsVisible )
            i_heightChange += controls->height();
#ifndef QT_NO_STATUSBAR
        if( b_statusBarVisible )
            i_heightChange += statusBar()->height();
#endif
        if( b_inputCVisible )
            i_heightChange += inputC->height();

        if( i_heightChange != 0 )
            resizeWindow( width(), height() - i_heightChange );
    }

    menuBar()->setVisible( !b_minimal );
    controls->setVisible( !b_minimal );
#ifndef QT_NO_STATUSBAR
    statusBar()->setVisible( !b_minimal && b_statusbarVisible );
#endif
    inputC->setVisible( !b_minimal );

    if( !isFullScreen() && !isMaximized() && !b_minimal && !b_isWindowTiled )
    {
        int i_heightChange = 0;

        if( !b_menuBarVisible && menuBar()->isVisible() )
            i_heightChange += menuBar()->height();
        if( !b_controlsVisible && controls->isVisible() )
            i_heightChange += controls->height();
#ifndef QT_NO_STATUSBAR
        if( !b_statusBarVisible && statusBar()->isVisible() )
            i_heightChange += statusBar()->height();
#endif
        if( !b_inputCVisible && inputC->isVisible() )
            i_heightChange += inputC->height();

        if( i_heightChange != 0 )
            resizeWindow( width(), height() + i_heightChange );
    }
}

/*
 * This public SLOT is used for moving to minimal View Mode
 *
 * If b_minimal is false, then we are normalView
 */
void MainInterface::toggleMinimalView( bool b_minimal )
{
    if( !b_minimalView && b_autoresize ) /* Normal mode */
    {
        if( stackCentralW->currentWidget() == bgWidget )
        {
            if( stackCentralW->height() < 16 )
            {
                resizeStack( stackCentralW->width(), 100 );
            }
        }
    }
    b_minimalView = b_minimal;
    if( !b_videoFullScreen )
    {
        setMinimalView( b_minimalView );
        computeMinimumSize();
    }

    emit minimalViewToggled( b_minimalView );
}

/*****************************************************************************
 * "Hide controls during playback" (Video menu, qt-hide-controls)
 *****************************************************************************/

void MainInterface::setAutoHideControls( bool enable )
{
    if( b_autoHideControls == enable )
        return;
    b_autoHideControls = enable;
    config_PutInt( p_intf, "qt-hide-controls", enable );
    if( !enable )
        revealControlsPlayback();
    i_autoHideOutsideTicks = 0;
    emit autoHideControlsToggled( enable );
}

bool MainInterface::shouldAutoHideControls()
{
    if( !b_autoHideControls || b_controlsHiddenPlayback )
        return false;
    if( isFullScreen() || b_videoFullScreen || b_minimalView )
        return false;
    /* the video being on show is the whole condition: a pause hides just
     * as well (the OSD is the feedback then), the playlist view never
     * does */
    if( !videoWidget || stackCentralW->currentWidget() != videoWidget )
        return false;
    return THEMIM->getInput() != NULL;
}

/* 500 ms tick, running for the interface's lifetime. Hiding waits for
 * the mouse to have been outside the window for 3 s; revealing waits for
 * the video to have been gone for 2.5 s, since the gaps of a loop
 * restart or of an item transition are shorter than that and must not
 * count. Coming back over the window never reveals by itself: that takes
 * a double click on the video. */
void MainInterface::autoHideControlsTick()
{
    if( b_controlsHiddenPlayback )
    {
        if( !b_autoHideControls || isFullScreen() || b_videoFullScreen )
        {
            revealControlsPlayback();
            return;
        }
        bool videoShown = videoWidget
            && stackCentralW->currentWidget() == videoWidget
            && THEMIM->getInput() != NULL;
        if( videoShown )
            i_autoHideRevealTicks = 0;
        else if( ++i_autoHideRevealTicks >= 5 )
            revealControlsPlayback();
        return;
    }

    i_autoHideRevealTicks = 0;
    if( !shouldAutoHideControls() || geometry().contains( QCursor::pos() ) )
    {
        i_autoHideOutsideTicks = 0;
        return;
    }
    if( ++i_autoHideOutsideTicks >= 6 )
        hideControlsPlayback();
}

/* Where the picture actually sits on screen, in global coordinates: the
 * video widget minus the letterbox bands the vout draws inside it. The
 * bare window is shrunk onto exactly that, so the picture neither moves
 * nor changes size when the decorations go away, bands included.
 * TODO(linux-windows round): verify setWindowFlags() does not disturb
 * the embedded vout on X11/Win32 (the native window is recreated). */
QRect MainInterface::pictureGeometryOnScreen() const
{
    if( !videoWidget )
        return QRect();

    QRect rect( videoWidget->mapToGlobal( QPoint( 0, 0 ) ),
                videoWidget->size() );
    if( videoNativeSize.width() <= 0 || videoNativeSize.height() <= 0
     || rect.width() <= 0 || rect.height() <= 0 )
        return rect;

    double scale = qMin( (double)rect.width() / videoNativeSize.width(),
                         (double)rect.height() / videoNativeSize.height() );
    QSize picture( qRound( videoNativeSize.width() * scale ),
                   qRound( videoNativeSize.height() * scale ) );
    rect.translate( ( rect.width() - picture.width() ) / 2,
                    ( rect.height() - picture.height() ) / 2 );
    rect.setSize( picture );
    return rect;
}

/* Every picture transformation -- zoom, crop, aspect ratio, the rotation
 * of the video effects, or simply another item -- reaches the interface
 * as the vout asking for a window size, and that is also what a plain
 * restart does. Telling them apart: a restart asks for the size it asked
 * for last time and is ignored, so the size the user settled on survives
 * every loop; a request that keeps the picture SHAPE and only changes
 * its scale is a zoom (Half/Normal/Double, or the matching hotkeys), an
 * explicit "make it this big", taken as is; a request that changes the
 * SHAPE (crop, aspect ratio, rotation, another item) is fitted inside
 * the box the user is watching in, so it never grows -- cropping a
 * half-size window would otherwise blow it up to full screen, because
 * the core drops the zoom factor on a crop change and then asks for the
 * natural size. The box only follows what the user asks for (a zoom, a
 * hand resize), never a shape change, so going 16:9 -> 4:3 -> 16:9 lands
 * back on the very same window instead of shrinking every time. */
/* The zoom factor the vout is currently applying, 0 when there is no
 * video to ask. */
double MainInterface::currentVideoZoom()
{
    input_thread_t *p_input = THEMIM->getInput();
    vout_thread_t *p_vout = p_input != NULL ? input_GetVout( p_input ) : NULL;
    if( p_vout == NULL )
        return 0.;

    const double zoom = var_GetFloat( p_vout, "zoom" );
    vlc_object_release( p_vout );
    return zoom;
}

QSize MainInterface::pictureSizeForRequest( const QSize &requested,
                                            const QSize &area )
{
    if( requested.width() <= 0 || requested.height() <= 0 )
        return QSize();

    QSize previous = lastRequestedVideoSize;
    lastRequestedVideoSize = requested;
    if( previous == requested )
        return QSize();

    /* Half / Normal / Double, and the hotkeys that do the same, all go
     * through the vout's "zoom": that is how a scale change the *user*
     * asked for is told apart from one the stream decided on its own. */
    const double zoom = currentVideoZoom();
    const double previousZoom = lastVideoZoom;
    lastVideoZoom = zoom;

    double ratio = (double)requested.width() / requested.height();
    bool sameShape = ( previous.width() > 0 && previous.height() > 0
        && qAbs( ratio - (double)previous.width() / previous.height() )
           <= ratio * 0.005 );

    /* the very first request opens the window at the size of the media,
     * as it always did */
    if( previous.width() <= 0 || previous.height() <= 0 )
    {
        pictureBox = requested;
        return requested;
    }

    if( sameShape )
    {
        /* ⚠ Same shape, another size, and nobody asked to zoom: this is
         * an adaptive stream switching variant, which it does several
         * times a programme. Following it made the window take the pixel
         * size of each variant and, one step up after another, end up
         * filling the screen on its own. The window belongs to the
         * viewer; only a shape change re-fits it (below). */
        if( zoom <= 0. || zoom == previousZoom )
            return QSize();

        pictureBox = requested;
        return requested;
    }

    QSize box = ( pictureBox.width() > 0 && pictureBox.height() > 0 )
        ? pictureBox : area;
    if( box.width() <= 0 || box.height() <= 0 )
        return requested;
    double fit = qMin( (double)box.width() / requested.width(),
                       (double)box.height() / requested.height() );
    return QSize( qRound( requested.width() * fit ),
                  qRound( requested.height() * fit ) );
}

void MainInterface::hiddenWindowFollowVideoSize( const QSize &requested )
{
    if( !b_controlsHiddenPlayback )
        return;

    QRect frame = geometry();
    QSize picture = pictureSizeForRequest( requested, frame.size() );
    if( picture.width() <= 0 || picture.height() <= 0 )
        return;

    /* keep it on the screen, at the ratio it just took */
    QRect screen = QGuiApplication::primaryScreen()->availableGeometry();
    double fit = qMin( 1., qMin( (double)screen.width() / picture.width(),
                                 (double)screen.height() / picture.height() ) );
    if( fit < 1. )
        picture = QSize( qRound( picture.width() * fit ),
                         qRound( picture.height() * fit ) );
    if( picture.width() < 160 || picture.height() < 90 )
        return;

    /* grow or shrink from the top left corner, where the eye is */
    frame.setSize( picture );
    setGeometry( frame );
}

void MainInterface::hideControlsPlayback()
{
    if( b_controlsHiddenPlayback || !shouldAutoHideControls()
     || geometry().contains( QCursor::pos() ) )
        return;

    QRect picture = pictureGeometryOnScreen();
    /* a video widget caught mid-relayout or mid-teardown (playback
     * ending, the playlist view coming and going) measures next to
     * nothing: shrinking the window onto that would leave a sliver
     * behind and there would be no picture to watch anyway */
    if( picture.width() < 160 || picture.height() < 90 )
        return;

    b_controlsHiddenPlayback = true;
    geometryBeforeHidingControls = geometry();
    lastRequestedVideoSize = videoNativeSize;
    pictureBox = picture.size();

    setMinimalView( true );
    setWindowFlags( windowFlags() | Qt::FramelessWindowHint );
    show();

    /* fit the window around the picture: both steps work from the
     * difference between the window and the video widget, so whatever
     * margins the style leaves are taken care of */
    QCoreApplication::processEvents( QEventLoop::ExcludeUserInputEvents );
    resize( size() + ( picture.size() - videoWidget->size() ) );
    QCoreApplication::processEvents( QEventLoop::ExcludeUserInputEvents );
    move( pos() + ( picture.topLeft()
                    - videoWidget->mapToGlobal( QPoint( 0, 0 ) ) ) );

    hiddenControlsInitialGeometry = geometry();
    var_SetBool( p_intf->obj.libvlc, "intf-controls-hidden", true );
}

void MainInterface::revealControlsPlayback()
{
    if( !b_controlsHiddenPlayback )
        return;
    b_controlsHiddenPlayback = false;
    b_hiddenDragActive = false;

    /* what was there before, carrying over whatever the user moved or
     * resized the bare window to meanwhile */
    QRect hidden = geometry();
    QRect restored = geometryBeforeHidingControls;
    restored.translate( hidden.x() - hiddenControlsInitialGeometry.x(),
                        hidden.y() - hiddenControlsInitialGeometry.y() );
    restored.setSize( restored.size()
        + ( hidden.size() - hiddenControlsInitialGeometry.size() ) );

    /* ⚠ hide() FIRST, and only here. Qt recreates the native window when
     * the frameless hint is ADDED, so the bare window loses its
     * decorations on its own; taking the hint away again does not go
     * through that path and the window manager is never told -- measured
     * on the Qt bench: after leaving the mode the controls and the menu
     * bar were back but _MOTIF_WM_HINTS still asked for no decoration at
     * all, leaving a title-bar-less window. Hiding by hand forces the
     * recreation the WM needs to redecorate. */
    hide();
    setWindowFlags( windowFlags() & ~Qt::FramelessWindowHint );
    show();
    setMinimalView( b_minimalView );

    QCoreApplication::processEvents( QEventLoop::ExcludeUserInputEvents );
    setGeometry( restored );

    var_SetBool( p_intf->obj.libvlc, "intf-controls-hidden", false );

    /* the delay restarts from zero: the mouse being outside already is
     * not enough to hide again right away */
    i_autoHideOutsideTicks = 0;
}

/*****************************************************************************
 * Moving and resizing the bare window
 *
 * Frameless means the window manager has no frame left to grab: the video
 * widget hands its mouse over instead. A drag started in a corner resizes
 * (the window IS the picture, so its ratio is kept and the opposite corner
 * stays put), anywhere else moves. Same deal as the two mac interfaces.
 *****************************************************************************/

#define HIDDEN_CORNER_ZONE 24

/* Dragging the picture always moves the window, controls hidden or not:
 * it is the natural grab area. Only the auto-hidden state adds the corner
 * resize zones, since the window manager frame is gone there. */
bool MainInterface::beginHiddenControlsDrag( const QPoint &globalPos )
{
    /* A maximized window is where the window manager put it, and dragging
     * its picture must not tear it off that -- no more than dragging a
     * maximized window by its title bar does on this platform. Fullscreen,
     * likewise, has nowhere to go. */
    if( b_videoFullScreen || isFullScreen() || isMaximized() )
    {
        b_hiddenDragActive = false;
        return false;
    }

    hiddenDragStartMouse = globalPos;
    /* ⚠ pos() is the FRAME corner, geometry() the client one, and they are
     * a title bar apart on a decorated window. move() places the frame:
     * feeding it geometry().topLeft() dropped the window by exactly the
     * height of its title bar at the first step of every drag, before it
     * started following the pointer properly. setGeometry(), used by the
     * corner resize below, takes the client rect instead -- hence the two
     * anchors. */
    hiddenDragStartPos = pos();
    hiddenDragStartGeometry = geometry();
    b_hiddenDragActive = true;
    b_hiddenDragAnchored = false;

    if( !b_controlsHiddenPlayback )
    {
        hiddenDragResizeH = 0;
        hiddenDragResizeV = 0;
        b_hiddenDragIsResize = false;
        return true;
    }

    hiddenDragResizeH =
        ( globalPos.x() - hiddenDragStartGeometry.left() <= HIDDEN_CORNER_ZONE ) ? -1 :
        ( ( hiddenDragStartGeometry.right() - globalPos.x() <= HIDDEN_CORNER_ZONE ) ? 1 : 0 );
    hiddenDragResizeV =
        ( globalPos.y() - hiddenDragStartGeometry.top() <= HIDDEN_CORNER_ZONE ) ? -1 :
        ( ( hiddenDragStartGeometry.bottom() - globalPos.y() <= HIDDEN_CORNER_ZONE ) ? 1 : 0 );
    b_hiddenDragIsResize = ( hiddenDragResizeH != 0 && hiddenDragResizeV != 0 );

    return true;
}

/* What the window may occupy: the screen it is ON (not the primary one),
 * minus the task bar and any other reserved strip. */
QRect MainInterface::availableScreenGeometry() const
{
    const QScreen *scr = windowHandle() != NULL ? windowHandle()->screen()
                                                : QGuiApplication::primaryScreen();
    return scr != NULL ? scr->availableGeometry() : QRect();
}

/* A window that just grew -- because a bigger picture arrived, because the
 * playlist opened -- keeps the corner it had, so it grows downwards and to
 * the right, straight under the task bar. Nothing upstream brings it back;
 * this does, moving it as little as possible and never resizing it (the
 * size is the caller's business). */
void MainInterface::keepInsideScreen()
{
    const QRect available = availableScreenGeometry();
    const QRect frame = frameGeometry();

    if( available.isEmpty() || frame.isEmpty() || isFullScreen()
     || isMaximized() || b_videoFullScreen )
        return;

    QPoint corner = frame.topLeft();
    if( frame.width() <= available.width() && frame.right() > available.right() )
        corner.setX( available.right() - frame.width() + 1 );
    if( frame.height() <= available.height() && frame.bottom() > available.bottom() )
        corner.setY( available.bottom() - frame.height() + 1 );
    /* a window too big for the screen is pinned to the top left corner,
     * where the menu bar and the controls at least stay reachable */
    if( corner.x() < available.left() )
        corner.setX( available.left() );
    if( corner.y() < available.top() )
        corner.setY( available.top() );

    if( corner != frame.topLeft() )
        move( corner );   /* move() places the FRAME, like frameGeometry() */
}

/* Keeps enough of the window on the screen to grab it again: with the
 * controls hidden the picture is the whole grab area, so a window dragged
 * fully past an edge could not be brought back at all. Dragging it partly
 * out stays allowed, as everywhere else. */
QPoint MainInterface::dragOriginKeptReachable( const QPoint &origin )
{
    const QRect visible = availableScreenGeometry();
    if( visible.isEmpty() )
        return origin;

    QPoint kept = origin;
    const int margin = qMin( 120, width() );
    const int vmargin = qMin( 60, height() );

    if( kept.x() + width() < visible.left() + margin )
        kept.setX( visible.left() + margin - width() );
    if( kept.x() > visible.right() - margin )
        kept.setX( visible.right() - margin );

    if( kept.y() < visible.top() )
        kept.setY( visible.top() );
    if( kept.y() > visible.bottom() - vmargin )
        kept.setY( visible.bottom() - vmargin );

    return kept;
}

/* ⚠⚠ Whether the button is REALLY still down, which neither the vout nor
 * Qt can be trusted about here.
 *
 * The vout owns the mouse messages of the video window and follows the
 * buttons through them -- but any window that grabs the pointer takes
 * those messages away, and a context menu is enough. The vout then never
 * sees the release, goes on believing the button is held, and a "drag" is
 * relayed for every motion that follows: the window trailed the bare
 * pointer around the screen, which is what "right click, then click the
 * video" did. Qt's own QMouseEvent::buttons() comes from the same
 * interrupted stream and is no better.
 *
 * A grab cannot fool the physical key state. Reading the button that is
 * PRIMARY for this user: swapping the buttons swaps the virtual keys too. */
bool MainInterface::dragButtonStillHeld() const
{
#ifdef _WIN32
    const int vk = GetSystemMetrics( SM_SWAPBUTTON ) ? VK_RBUTTON : VK_LBUTTON;
    return ( GetAsyncKeyState( vk ) & 0x8000 ) != 0;
#else
    return true;
#endif
}

void MainInterface::dragHiddenControlsTo( const QPoint &globalPos )
{
    if( !b_hiddenDragActive )
        return;

    if( !dragButtonStillHeld() )
    {
        /* the gesture ended somewhere nobody told us about */
        endHiddenControlsDrag();
        return;
    }

    /* ⚠ The FIRST move of a drag re-takes the anchor instead of acting on
     * it. A press whose release never came back to us leaves the drag
     * armed with an anchor belonging to another gesture entirely, and the
     * next move then teleports the window by the distance between two
     * unrelated pointer positions. That is what "click a menu, then click
     * the video" did on Windows -- the menu's mouse grab hands us events
     * the vout normally keeps, so the press and the release do not come
     * from the same place. It is also what the two macOS interfaces were
     * bitten by (there the fix was to follow the event deltas).
     * Re-anchoring costs the couple of pixels between the press and the
     * first move, and makes the jump impossible by construction. */
    if( !b_hiddenDragAnchored )
    {
        b_hiddenDragAnchored = true;
        hiddenDragStartMouse = globalPos;
        hiddenDragStartPos = pos();
        hiddenDragStartGeometry = geometry();
        return;
    }

    QPoint delta = globalPos - hiddenDragStartMouse;

    if( !b_hiddenDragIsResize )
    {
        move( dragOriginKeptReachable( hiddenDragStartPos + delta ) );
        return;
    }

    /* one dimension drives, the picture ratio gives the other */
    int width = hiddenDragStartGeometry.width()
              + delta.x() * hiddenDragResizeH;
    if( width < 160 )
        width = 160;
    double ratio = ( videoNativeSize.width() > 0
                     && videoNativeSize.height() > 0 )
        ? (double)videoNativeSize.height() / videoNativeSize.width()
        : (double)hiddenDragStartGeometry.height()
          / hiddenDragStartGeometry.width();

    QRect rect = hiddenDragStartGeometry;
    rect.setWidth( width );
    rect.setHeight( qRound( width * ratio ) );
    if( hiddenDragResizeH < 0 )
        rect.moveRight( hiddenDragStartGeometry.right() );
    if( hiddenDragResizeV < 0 )
        rect.moveBottom( hiddenDragStartGeometry.bottom() );

    setGeometry( rect );
    /* resizing by hand redefines the box a later crop fits into */
    pictureBox = rect.size();
}

void MainInterface::endHiddenControlsDrag()
{
    b_hiddenDragActive = false;
}

void MainInterface::emitRevealControls()
{
    emit askRevealControls();
}

/* Relayed by the core from the vout thread (Windows): hop to the GUI
 * thread, where the pointer position can be read and the window moved. */
void MainInterface::emitVideoDrag( int phase )
{
    emit askVideoDrag( phase );
}

/* No coordinates come with the relay: the vout knows the picture, not the
 * screen. QCursor::pos() is read here instead -- by the time this runs the
 * pointer is where it is NOW, which is exactly what the drag needs. */
void MainInterface::videoDragRelayed( int phase )
{
    switch( phase )
    {
    case 1: /* pressed */
        beginHiddenControlsDrag( QCursor::pos() );
        break;
    case 2: /* moved */
        dragHiddenControlsTo( QCursor::pos() );
        break;
    default: /* released */
        endHiddenControlsDrag();
        break;
    }
}

/* toggling advanced controls buttons */
void MainInterface::toggleAdvancedButtons()
{
    controls->toggleAdvanced();
//    if( fullscreenControls ) fullscreenControls->toggleAdvanced();
}

/* Get the visibility status of the controls (hidden or not, advanced or not) */
int MainInterface::getControlsVisibilityStatus()
{
    if( !controls ) return 0;
    return( (controls->isVisible() ? CONTROLS_VISIBLE : CONTROLS_HIDDEN )
            + CONTROLS_ADVANCED * controls->b_advancedVisible );
}

/* Get whether the advanced buttons widget is available
 * (if its actually present in any of the configurable locations).
 */
bool MainInterface::isAdvancedWidgetAvailable()
{
    if( !controls) return false;
    return controls->advancedAvailable();
}

StandardPLPanel *MainInterface::getPlaylistView()
{
    if( !playlistWidget ) return NULL;
    else return playlistWidget->mainView;
}

void MainInterface::setStatusBarVisibility( bool b_visible )
{
#ifndef QT_NO_STATUSBAR
    statusBar()->setVisible( b_visible );
    b_statusbarVisible = b_visible;
    if( controls ) controls->setGripVisible( !b_statusbarVisible );
#endif
}


void MainInterface::setPlaylistVisibility( bool b_visible )
{
    if( isPlDocked() || THEDP->isDying() || (playlistWidget && playlistWidget->isMinimized() ) )
        return;

    playlistVisible = b_visible;
}

/************************************************************************
 * Other stuff
 ************************************************************************/
void MainInterface::setName( const QString& name )
{
    input_name = name; /* store it for the QSystray use */
#ifndef QT_NO_STATUSBAR
    /* Display it in the status bar, but also as a Tooltip in case it doesn't
       fit in the label */
    nameLabel->setText( name );
    nameLabel->setToolTip( name );
#endif // QT_NO_STATUSBAR
}

/**
 * Give the decorations of the Main Window a correct Name.
 * If nothing is given, set it to VLC...
 **/
void MainInterface::setVLCWindowsTitle( const QString& aTitle )
{
    if( aTitle.isEmpty() )
    {
        setWindowTitle( qtr( "PowerVLC media player" ) );
    }
    else
    {
        setWindowTitle( aTitle + " - " + qtr( "PowerVLC media player" ) );
    }
}

void MainInterface::showCryptedLabel( bool b_show )
{
#ifndef QT_NO_STATUSBAR
    if( cryptedLabel == NULL )
    {
        cryptedLabel = new QLabel;
        // The lock icon is not the right one for DRM protection/scrambled.
        //cryptedLabel->setPixmap( QPixmap( ":/lock.svg" ) );
        cryptedLabel->setText( "DRM" );
#ifndef QT_NO_STATUSBAR
        statusBar()->addWidget( cryptedLabel );
#endif
    }

    cryptedLabel->setVisible( b_show );
#endif
}

/*****************************************************************************
 * Systray Icon and Systray Menu
 *****************************************************************************/
/**
 * Create a SystemTray icon and a menu that would go with it.
 * Connects to a click handler on the icon.
 **/
void MainInterface::createSystray()
{
    QIcon iconVLC;
    if( QDate::currentDate().dayOfYear() >= QT_XMAS_JOKE_DAY && var_InheritBool( p_intf, "qt-icon-change" ) )
        iconVLC = QIcon::fromTheme( "powervlc-xmas", QIcon( ":/logo/vlc128-xmas.png" ) );
    else
        iconVLC = QIcon::fromTheme( PACKAGE_USERDIR, QIcon( ":/logo/vlc256.png" ) );
    sysTray = new QSystemTrayIcon( iconVLC, this );
    sysTray->setToolTip( qtr( "PowerVLC media player" ));

    systrayMenu = new QMenu( qtr( "PowerVLC media player" ), this );
    systrayMenu->setIcon( iconVLC );

    VLCMenuBar::updateSystrayMenu( this, p_intf, true );
    sysTray->show();

    connect( sysTray, &QSystemTrayIcon::activated,
             this, &MainInterface::handleSystrayClick );

    /* Connects on nameChanged() */
    connect( THEMIM->getIM(), &InputManager::nameChanged,
             this, &MainInterface::updateSystrayTooltipName );
    /* Connect PLAY_STATUS on the systray */
    connect( THEMIM->getIM(), &InputManager::playingStatusChanged,
             this, &MainInterface::updateSystrayTooltipStatus );
}

void MainInterface::toggleUpdateSystrayMenuWhenVisible()
{
    hide();
}

void MainInterface::resizeWindow(int w, int h)
{
    /* Never ask for a window the screen cannot hold.
     *
     * setVideoSize() already caps the size it hands to the video widget, but it
     * is not the only road here: videoSizeChanged() -> resizeStack() arrives
     * with the video's NATIVE size and no cap at all. Starting a 720p file on a
     * 1024x600 netbook therefore grew the window to 1280x794 for a fraction of
     * a second before the cap brought it back to 1024x532 -- and that was
     * enough. Faced with a window taller than the screen, the window manager
     * slides it up; when the window then shrinks, the position stays put, so
     * the title bar ends up above the top edge, out of reach of the mouse.
     * Qt saves that geometry on exit, so every later run started off-screen
     * too. Capping here, at the single choke point through which every resize
     * passes, means the oversized transient never happens.
     *
     * The screen is the one the window is actually on, not the primary one:
     * they differ as soon as there are two monitors. */
    const QScreen *scr = windowHandle() != NULL ? windowHandle()->screen()
                                               : QGuiApplication::primaryScreen();
    if( scr != NULL )
    {
        const QRect avail = scr->availableGeometry();
        /* The frame is drawn by the window manager and is not part of the
         * size we set here; leave room for it, or the decorated window still
         * overflows. It only becomes measurable once the window is mapped. */
        const QSize deco = frameGeometry().size() - geometry().size();
        w = qMin( w, avail.width()  - qMax( 0, deco.width()  ) );
        h = qMin( h, avail.height() - qMax( 0, deco.height() ) );
    }

#if ! HAS_QT510 && defined(QT5_HAS_X11)
    if( QX11Info::isPlatformX11() )
    {
#if HAS_QT56
        qreal dpr = devicePixelRatioF();
#else
        qreal dpr = devicePixelRatio();
#endif
        QSize size(w, h);
        size = size.boundedTo(maximumSize()).expandedTo(minimumSize());
        /* X11 window managers are not required to accept geometry changes on
         * the top-level window.  Unfortunately, Qt < 5.10 assumes that the
         * change will succeed, and resizes all sub-windows unconditionally.
         * By calling XMoveResizeWindow directly, Qt will not see our change
         * request until the ConfigureNotify event on success
         * and not at all if it is rejected. */
        XResizeWindow( QX11Info::display(), winId(),
                       (unsigned int)size.width() * dpr, (unsigned int)size.height() * dpr);
        return;
    }
#endif
    resize(w, h);
}

/**
 * Updates the Systray Icon's menu and toggle the main interface
 */
void MainInterface::toggleUpdateSystrayMenu()
{
    /* If hidden, show it */
    if( isHidden() )
    {
        show();
        activateWindow();
    }
    else if( isMinimized() )
    {
        /* Minimized */
        showNormal();
        activateWindow();
    }
    else
    {
        /* Visible (possibly under other windows) */
        toggleUpdateSystrayMenuWhenVisible();
    }
    if( sysTray )
        VLCMenuBar::updateSystrayMenu( this, p_intf );
}

/* First Item of the systray menu */
void MainInterface::showUpdateSystrayMenu()
{
    if( isHidden() )
        show();
    if( isMinimized() )
        showNormal();
    activateWindow();

    VLCMenuBar::updateSystrayMenu( this, p_intf );
}

/* First Item of the systray menu */
void MainInterface::hideUpdateSystrayMenu()
{
    hide();
    VLCMenuBar::updateSystrayMenu( this, p_intf );
}

/* Click on systray Icon */
void MainInterface::handleSystrayClick(
                                    QSystemTrayIcon::ActivationReason reason )
{
    switch( reason )
    {
        case QSystemTrayIcon::Trigger:
        case QSystemTrayIcon::DoubleClick:
#ifdef Q_OS_MAC
            VLCMenuBar::updateSystrayMenu( this, p_intf );
#else
            toggleUpdateSystrayMenu();
#endif
            break;
        case QSystemTrayIcon::MiddleClick:
            sysTray->showMessage( qtr( "PowerVLC media player" ),
                    qtr( "Control menu for the player" ),
                    QSystemTrayIcon::Information, 3000 );
            break;
        default:
            break;
    }
}

/**
 * Updates the name of the systray Icon tooltip.
 * Doesn't check if the systray exists, check before you call it.
 **/
void MainInterface::updateSystrayTooltipName( const QString& name )
{
    if( name.isEmpty() )
    {
        sysTray->setToolTip( qtr( "PowerVLC media player" ) );
    }
    else
    {
        sysTray->setToolTip( name );
        if( ( i_notificationSetting == NOTIFICATION_ALWAYS ) ||
            ( i_notificationSetting == NOTIFICATION_MINIMIZED && (isMinimized() || isHidden()) ) )
        {
            sysTray->showMessage( qtr( "PowerVLC media player" ), name,
                    QSystemTrayIcon::NoIcon, 3000 );
        }
    }

    VLCMenuBar::updateSystrayMenu( this, p_intf );
}

/**
 * Updates the status of the systray Icon tooltip.
 * Doesn't check if the systray exists, check before you call it.
 **/
void MainInterface::updateSystrayTooltipStatus( int i_status )
{
    switch( i_status )
    {
    case PLAYING_S:
        sysTray->setToolTip( input_name );
        break;
    case PAUSE_S:
        sysTray->setToolTip( input_name + " - " + qtr( "Paused") );
        break;
    default:
        sysTray->setToolTip( qtr( "PowerVLC media player" ) );
        break;
    }
    VLCMenuBar::updateSystrayMenu( this, p_intf );
}

void MainInterface::changeEvent(QEvent *event)
{
    if( event->type() == QEvent::WindowStateChange )
    {
        QWindowStateChangeEvent *windowStateChangeEvent = static_cast<QWindowStateChangeEvent*>(event);
        Qt::WindowStates newState = windowState();
        Qt::WindowStates oldState = windowStateChangeEvent->oldState();

        /* b_maximizedView stores if the window was maximized before entering fullscreen.
         * It is set when entering maximized mode, unset when leaving it to normal mode.
         * Upon leaving full screen, if b_maximizedView is set,
         * the window should be maximized again. */
        if( newState & Qt::WindowMaximized &&
            !( oldState & Qt::WindowMaximized ) )
            b_maximizedView = true;

        if( !( newState & Qt::WindowMaximized ) &&
            oldState & Qt::WindowMaximized &&
            !b_videoFullScreen )
            b_maximizedView = false;

        if( !( newState & Qt::WindowFullScreen ) &&
            oldState & Qt::WindowFullScreen &&
            b_maximizedView )
        {
            showMaximized();
            return;
        }

        if( newState & Qt::WindowMinimized )
        {
            b_hasPausedWhenMinimized = false;

            if( THEMIM->getIM()->playingStatus() == PLAYING_S &&
                THEMIM->getIM()->hasVideo() && !THEMIM->getIM()->hasVisualisation() &&
                b_pauseOnMinimize )
            {
                b_hasPausedWhenMinimized = true;
                THEMIM->pause();
            }
        }
        else if( oldState & Qt::WindowMinimized && !( newState & Qt::WindowMinimized ) )
        {
            if( b_hasPausedWhenMinimized )
            {
                THEMIM->play();
            }
        }
    }

    QWidget::changeEvent(event);
}

/************************************************************************
 * D&D Events
 ************************************************************************/
void MainInterface::dropEvent(QDropEvent *event)
{
    dropEventPlay( event, true );
}

/**
 * dropEventPlay
 *
 * Event called if something is dropped onto a VLC window
 * \param event the event in question
 * \param b_play whether to play the file immediately
 * \param b_playlist true to add to playlist, false to add to media library
 * \return nothing
 */
void MainInterface::dropEventPlay( QDropEvent *event, bool b_play, bool b_playlist )
{
    if( event->possibleActions() & ( Qt::CopyAction | Qt::MoveAction | Qt::LinkAction ) )
       event->setDropAction( Qt::CopyAction );
    else
        return;

    const QMimeData *mimeData = event->mimeData();

    /* D&D of a subtitles file, add it on the fly */
    if( mimeData->urls().count() == 1 && THEMIM->getIM()->hasInput() )
    {
        if( !input_AddSlave( THEMIM->getInput(), SLAVE_TYPE_SPU,
                 qtu( mimeData->urls()[0].toString() ), true, true, true ) )
        {
            event->accept();
            return;
        }
    }

    bool first = b_play;
    foreach( const QUrl &url, mimeData->urls() )
    {
        if( url.isValid() )
        {
            QString mrl = toURI( url.toEncoded().constData() );
#ifdef _WIN32
            QFileInfo info( url.toLocalFile() );
            if( info.exists() && info.isSymLink() )
            {
                QString target = info.symLinkTarget();
                QUrl url;
                if( QFile::exists( target ) )
                {
                    url = QUrl::fromLocalFile( target );
                }
                else
                {
                    url.setUrl( target );
                }
                mrl = toURI( url.toEncoded().constData() );
            }
#endif
            if( mrl.length() > 0 )
            {
                Open::openMRL( p_intf, mrl, first, b_playlist );
                first = false;
            }
        }
    }

    /* Browsers give content as text if you dnd the addressbar,
       so check if mimedata has valid url in text and use it
       if we didn't get any normal Urls()*/
    if( !mimeData->hasUrls() && mimeData->hasText() &&
        QUrl(mimeData->text()).isValid() )
    {
        QString mrl = toURI( mimeData->text() );
        Open::openMRL( p_intf, mrl, first, b_playlist );
    }
    event->accept();
}
void MainInterface::dragEnterEvent(QDragEnterEvent *event)
{
     event->acceptProposedAction();
}
void MainInterface::dragMoveEvent(QDragMoveEvent *event)
{
     event->acceptProposedAction();
}
void MainInterface::dragLeaveEvent(QDragLeaveEvent *event)
{
     event->accept();
}

/************************************************************************
 * Events stuff
 ************************************************************************/
void MainInterface::keyPressEvent( QKeyEvent *e )
{
    handleKeyPress( e );

    /* easter eggs sequence handling */
    if ( e->key() == kc[ i_kc_offset ] )
        i_kc_offset++;
    else
        i_kc_offset = 0;

    if ( i_kc_offset == (sizeof( kc ) / sizeof( Qt::Key )) )
    {
        i_kc_offset = 0;
        emit kc_pressed();
    }
}

void MainInterface::handleKeyPress( QKeyEvent *e )
{
    if( ( ( e->modifiers() & Qt::ControlModifier ) && ( e->key() == Qt::Key_H ) ) ||
        ( b_minimalView && !b_videoFullScreen && e->key() == Qt::Key_Escape ) )
    {
        toggleMinimalView( !b_minimalView );
        e->accept();
    }
    else if( ( e->modifiers() & Qt::ControlModifier ) && ( e->key() == Qt::Key_K ) &&
        playlistWidget )
    {
        playlistWidget->setSearchFieldFocus();
        e->accept();
    }

    int i_vlck = qtEventToVLCKey( e );
    if( i_vlck > 0 )
    {
        var_SetInteger( p_intf->obj.libvlc, "key-pressed", i_vlck );
        e->accept();
    }
    else
        e->ignore();
}

void MainInterface::wheelEvent( QWheelEvent *e )
{
    int i_vlckey = qtWheelEventToVLCKey( e );
    var_SetInteger( p_intf->obj.libvlc, "key-pressed", i_vlckey );
    e->accept();
}

void MainInterface::closeEvent( QCloseEvent *e )
{
//  hide();
    if ( b_minimalView )
        setMinimalView( false );
    if( videoWidget )
        releaseVideoSlot( true );
    emit askToQuit(); /* ask THEDP to quit, so we have a unique method */
    /* Accept session quit. Otherwise we break the desktop mamager. */
    e->accept();
}

bool MainInterface::eventFilter( QObject *obj, QEvent *event )
{
    if ( event->type() == MainInterface::ToolbarsNeedRebuild ) {
        event->accept();
        recreateToolbars();
        return true;
    } else {
        return QObject::eventFilter( obj, event );
    }
}

void MainInterface::toolBarConfUpdated()
{
    QApplication::postEvent( this, new QEvent( MainInterface::ToolbarsNeedRebuild ) );
}

void MainInterface::setInterfaceFullScreen( bool fs )
{
    if( fs )
        setWindowState( windowState() | Qt::WindowFullScreen );
    else
        setWindowState( windowState() & ~Qt::WindowFullScreen );
}
void MainInterface::toggleInterfaceFullScreen()
{
    b_interfaceFullScreen = !b_interfaceFullScreen;
    if( !b_videoFullScreen )
        setInterfaceFullScreen( b_interfaceFullScreen );
    emit fullscreenInterfaceToggled( b_interfaceFullScreen );
}

void MainInterface::emitBoss()
{
    emit askBoss();
}
void MainInterface::setBoss()
{
    THEMIM->pause();
    if( sysTray )
    {
        hide();
    }
    else
    {
        showMinimized();
    }
}

void MainInterface::emitRaise()
{
    emit askRaise();
}
void MainInterface::setRaise()
{
    activateWindow();
    raise();
}

void MainInterface::voutReleaseMouseEvents()
{
    if (videoWidget)
    {
        QPoint pos = QCursor::pos();
        QPoint localpos = videoWidget->mapFromGlobal(pos);
        int buttons = QApplication::mouseButtons();
        int i_button = 1;
        while (buttons != 0)
        {
            if ( (buttons & 1) != 0 )
            {
                QMouseEvent new_e( QEvent::MouseButtonRelease, localpos,
                                   (Qt::MouseButton)i_button, (Qt::MouseButton)i_button, Qt::NoModifier );
                QApplication::sendEvent(videoWidget, &new_e);
            }
            buttons >>= 1;
            i_button <<= 1;
        }

    }
}

/*****************************************************************************
 * PopupMenuCB: callback triggered by the intf-popupmenu playlist variable.
 *  We don't show the menu directly here because we don't want the
 *  caller to block for a too long time.
 *****************************************************************************/
static int PopupMenuCB( vlc_object_t *, const char *,
                        vlc_value_t, vlc_value_t new_val, void *param )
{
    intf_thread_t *p_intf = (intf_thread_t *)param;

    if( p_intf->pf_show_dialog )
    {
        p_intf->pf_show_dialog( p_intf, INTF_DIALOG_POPUPMENU,
                                new_val.b_bool, NULL );
    }

    return VLC_SUCCESS;
}

/*****************************************************************************
 * IntfShowCB: callback triggered by the intf-toggle-fscontrol libvlc variable.
 *****************************************************************************/
static int IntfShowCB( vlc_object_t *, const char *,
                       vlc_value_t, vlc_value_t, void *param )
{
    intf_thread_t *p_intf = (intf_thread_t *)param;
    p_intf->p_sys->p_mi->toggleFSC();

    /* Show event */
     return VLC_SUCCESS;
}

/*****************************************************************************
 * IntfRaiseMainCB: callback triggered by the intf-show-main libvlc variable.
 *****************************************************************************/
static int IntfRaiseMainCB( vlc_object_t *, const char *,
                            vlc_value_t, vlc_value_t, void *param )
{
    intf_thread_t *p_intf = (intf_thread_t *)param;
    p_intf->p_sys->p_mi->emitRaise();

    return VLC_SUCCESS;
}

/*****************************************************************************
 * IntfRevealControlsCB: the core saw a double click on the video while the
 * windowed controls were auto-hidden ("intf-reveal-controls").
 *****************************************************************************/
static int IntfRevealControlsCB( vlc_object_t *, const char *,
                                 vlc_value_t, vlc_value_t, void *param )
{
    intf_thread_t *p_intf = (intf_thread_t *)param;
    p_intf->p_sys->p_mi->emitRevealControls();

    return VLC_SUCCESS;
}

#ifdef _WIN32
/*****************************************************************************
 * IntfVideoDragCB: the core relaying a left drag on the video, which the
 * vout's own child window would otherwise have kept to itself
 * ("intf-video-drag": 1 pressed, 2 moved, 3 released).
 *****************************************************************************/
static int IntfVideoDragCB( vlc_object_t *, const char *,
                            vlc_value_t, vlc_value_t newval, void *param )
{
    intf_thread_t *p_intf = (intf_thread_t *)param;
    p_intf->p_sys->p_mi->emitVideoDrag( newval.i_int );

    return VLC_SUCCESS;
}
#endif

/*****************************************************************************
 * IntfBossCB: callback triggered by the intf-boss libvlc variable.
 *****************************************************************************/
static int IntfBossCB( vlc_object_t *, const char *,
                       vlc_value_t, vlc_value_t, void *param )
{
    intf_thread_t *p_intf = (intf_thread_t *)param;
    p_intf->p_sys->p_mi->emitBoss();

    return VLC_SUCCESS;
}
