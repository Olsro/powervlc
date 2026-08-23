/*****************************************************************************
 * main_interface.hpp : Main Interface
 ****************************************************************************
 * Copyright (C) 2006-2010 VideoLAN and AUTHORS
 * $Id$
 *
 * Authors: Clément Stenac <zorglub@videolan.org>
 *          Jean-Baptiste Kempf <jb@videolan.org>
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

#ifndef QVLC_MAIN_INTERFACE_H_
#define QVLC_MAIN_INTERFACE_H_

#include "qt.hpp"

#include "util/qvlcframe.hpp"

#include <QSystemTrayIcon>
#include <QStackedWidget>

#ifdef _WIN32
# include <shobjidl.h>
#endif

class QSettings;
class QCloseEvent;
class QKeyEvent;
class QResizeEvent;
class QLabel;
class QEvent;
class VideoWidget;
class BackgroundWidget;
class PlaylistWidget;
class VisualSelector;
class ControlsWidget;
class InputControlsWidget;
class FullscreenControllerWidget;
class QVBoxLayout;
class QMenu;
class QSize;
class QScreen;
class QTimer;
class StandardPLPanel;
struct vout_window_t;

class MainInterface : public QVLCMW
{
    Q_OBJECT

    friend class PlaylistWidget;

public:
    /* tors */
    MainInterface( intf_thread_t *);
    virtual ~MainInterface();

    static const QEvent::Type ToolbarsNeedRebuild;

    /* Video requests from core */
    bool getVideo( struct vout_window_t *,
                   unsigned int i_width, unsigned int i_height, bool );
    void releaseVideo( void );
    int  controlVideo( int i_query, va_list args );

    /* Getters */
    QSystemTrayIcon *getSysTray() { return sysTray; }
    QMenu *getSysTrayMenu() { return systrayMenu; }
    FullscreenControllerWidget* getFullscreenControllerWidget() { return fullscreenControls; }
    enum
    {
        CONTROLS_VISIBLE  = 0x1,
        CONTROLS_HIDDEN   = 0x2,
        CONTROLS_ADVANCED = 0x4,
    };
    enum
    {
        RAISE_NEVER,
        RAISE_VIDEO,
        RAISE_AUDIO,
        RAISE_AUDIOVIDEO,
    };
    int getControlsVisibilityStatus();
    bool isAdvancedWidgetAvailable();
    bool isPlDocked() { return ( b_plDocked != false ); }
    bool isInterfaceFullScreen() { return b_interfaceFullScreen; }
    bool isInterfaceAlwaysOnTop() { return b_interfaceOnTop; }
    StandardPLPanel* getPlaylistView();
    bool addNetworkLocation( const QString& mrl );

protected:
    void dropEventPlay( QDropEvent* event, bool b_play ) { dropEventPlay(event, b_play, true); }
    void dropEventPlay( QDropEvent *, bool, bool );
    void changeEvent( QEvent * ) Q_DECL_OVERRIDE;
    void dropEvent( QDropEvent *) Q_DECL_OVERRIDE;
    void dragEnterEvent( QDragEnterEvent * ) Q_DECL_OVERRIDE;
    void dragMoveEvent( QDragMoveEvent * ) Q_DECL_OVERRIDE;
    void dragLeaveEvent( QDragLeaveEvent * ) Q_DECL_OVERRIDE;
    void closeEvent( QCloseEvent *) Q_DECL_OVERRIDE;
    void keyPressEvent( QKeyEvent *) Q_DECL_OVERRIDE;
    void wheelEvent( QWheelEvent * ) Q_DECL_OVERRIDE;
    /* "Hide controls during playback": tells a hand resize of the window
     * from one we asked for ourselves (see setVideoWidgetSizeFromRequest) */
    void resizeEvent( QResizeEvent * ) Q_DECL_OVERRIDE;
    bool eventFilter(QObject *, QEvent *) Q_DECL_OVERRIDE;
    virtual void toggleUpdateSystrayMenuWhenVisible();
    void resizeWindow(int width, int height);

protected:
    /* Main Widgets Creation */
    void createMainWidget( QSettings* );
    void createStatusBar();
    void createPlaylist();
    void createResumePanel( QWidget *w );

    /* Systray */
    void createSystray();
    void initSystray();
    void handleSystray();

    /* Central StackWidget Management */
    void showTab( QWidget *, bool video_closing = false );
    void showVideo();
    void restoreStackOldWidget( bool video_closing = false );

    /* */
    void displayNormalView();
    void setMinimalView( bool );
    void setInterfaceFullScreen( bool );
    void computeMinimumSize();

    /* */
    QSettings           *settings;
    QSystemTrayIcon     *sysTray;
    QMenu               *systrayMenu;

    QString              input_name;
    QVBoxLayout         *mainLayout;
    ControlsWidget      *controls;
    InputControlsWidget *inputC;
    FullscreenControllerWidget *fullscreenControls;

    /* Widgets */
    QStackedWidget      *stackCentralW;

    VideoWidget         *videoWidget;
    BackgroundWidget    *bgWidget;
    PlaylistWidget      *playlistWidget;
    //VisualSelector      *visualSelector;

    /* resume panel */
    QWidget             *resumePanel;
    QTimer              *resumeTimer;
    int64_t             i_resumeTime;

    /* Status Bar */
    QLabel              *nameLabel;
    QLabel              *cryptedLabel;

    /* Status and flags */
    QWidget             *stackCentralOldWidget;
    QPoint              lastWinPosition;
    QSize               lastWinSize;  /// To restore the same window size when leaving fullscreen
    QScreen             *lastWinScreen;

    QMap<QWidget *, QSize> stackWidgetsSizes;

    /* Flags */
    unsigned             i_notificationSetting; /// Systray Notifications
    bool                 b_autoresize;          ///< persistent resizable window
    bool                 b_videoFullScreen;     ///< --fullscreen
    bool                 b_hideAfterCreation;
    bool                 b_minimalView;         ///< Minimal video
    bool                 b_interfaceFullScreen;
    bool                 b_interfaceOnTop;      ///keep UI on top
    bool                 b_pauseOnMinimize;
    bool                 b_maximizedView;
    bool                 b_isWindowTiled;
    /* States */
    bool                 playlistVisible;       ///< Is the playlist visible ?
//    bool                 videoIsActive;       ///< Having a video now / THEMIM->hasV
//    bool                 b_visualSelectorEnabled;
    bool                 b_plDocked;            ///< Is the playlist docked ?

    bool                 b_hasPausedWhenMinimized;
    bool                 b_statusbarVisible;

    /* "Hide controls during playback" (Video menu, qt-hide-controls):
     * once the mouse has left the window for a few seconds during
     * windowed playback, the controls, the menu bar and the window frame
     * go away and the window shrinks onto the video, which keeps its
     * exact size and position on screen. A double click on the video
     * (rerouted by the core through "intf-reveal-controls") brings
     * everything back. */
    /* Polled rather than driven by enter/leave events: those fire on the
     * main window as soon as the pointer moves onto the video child
     * widget, which is precisely where it spends its time here. */
    QTimer              *autoHideControlsTimer;    ///< 500 ms, always on
    int                  i_autoHideOutsideTicks;   ///< mouse outside
    int                  i_autoHideRevealTicks;    ///< video gone
    bool                 b_autoHideControls;       ///< the master switch
    bool                 b_controlsHiddenPlayback; ///< currently hidden
    bool shouldAutoHideControls();
    QRect pictureGeometryOnScreen() const;
    void hiddenWindowFollowVideoSize( const QSize & );
    QSize pictureSizeForRequest( const QSize &requested, const QSize &area );
    double currentVideoZoom();
    QPoint dragOriginKeptReachable( const QPoint &origin );
    bool dragButtonStillHeld() const;
    /* the work area of the screen the window is on -- task bar excluded */
    QRect availableScreenGeometry() const;
    void setVideoWidgetSizeFromRequest( const QSize & );
    /* geometry bookkeeping: the bare window is exactly the picture, and
     * revealing puts back what was there before, carrying over whatever
     * the user moved or resized it to meanwhile */
    QSize                videoNativeSize;          ///< ratio of the picture
    QSize                lastRequestedVideoSize;   ///< spots a plain restart
    double               lastVideoZoom;            ///< spots a zoom the user asked for
    QSize                pictureBox;               ///< a shape change fits in
    QSize                lastVideoRequestSize;     ///< size we asked for
    bool                 b_videoDrivenResize;      ///< ours, not the user's
    QRect                geometryBeforeHidingControls;
    QRect                hiddenControlsInitialGeometry;
    /* the bare window has no frame left for the window manager to grab:
     * a drag started in a CORNER resizes it (picture ratio kept, opposite
     * corner anchored), anywhere else moves it */
    QPoint               hiddenDragStartMouse;
    QPoint               hiddenDragStartPos;       ///< FRAME corner, for move()
    QRect                hiddenDragStartGeometry;  ///< client rect, for setGeometry()
    bool                 b_hiddenDragActive;
    bool                 b_hiddenDragAnchored;     ///< a move has anchored it
    bool                 b_hiddenDragIsResize;
    int                  hiddenDragResizeH;        ///< -1 left, +1 right
    int                  hiddenDragResizeV;        ///< -1 top, +1 bottom

    static const Qt::Key kc[10]; /* easter eggs */
    int i_kc_offset;

public slots:
    void dockPlaylist( bool b_docked = true );
    void toggleMinimalView( bool );
    void togglePlaylist();
    void toggleUpdateSystrayMenu();
    void showUpdateSystrayMenu();
    void hideUpdateSystrayMenu();
    void toggleAdvancedButtons();
    void toggleInterfaceFullScreen();
    void toggleFSC();
    void setInterfaceAlwaysOnTop( bool );

    void setStatusBarVisibility(bool b_visible);
    void setPlaylistVisibility(bool b_visible);

    /* Manage the Video Functions from the vout threads */
    void getVideoSlot( struct vout_window_t *,
                       unsigned i_width, unsigned i_height, bool, bool * );
    void releaseVideoSlot( bool forced );

    void emitBoss();
    void emitRaise();

    /* "Hide controls during playback" */
    void setAutoHideControls( bool );
    bool autoHideControlsEnabled() { return b_autoHideControls; }
    void emitRevealControls();
    /* the core relaying a drag on the picture, where the vout took the
     * mouse messages before any widget could see them (Windows) */
    void emitVideoDrag( int phase );
    /* the video widget hands its mouse over while the window is bare:
     * begin returns false when there is nothing to drag */
    bool controlsHiddenForPlayback() const { return b_controlsHiddenPlayback; }
    bool beginHiddenControlsDrag( const QPoint &globalPos );
    void dragHiddenControlsTo( const QPoint &globalPos );
    void endHiddenControlsDrag();

    virtual void reloadPrefs();
    void toolBarConfUpdated();

protected slots:
    void debug();
    void recreateToolbars();
    void setName( const QString& );
    void setVLCWindowsTitle( const QString& title = "" );
    void handleSystrayClick( QSystemTrayIcon::ActivationReason );
    void updateSystrayTooltipName( const QString& );
    void updateSystrayTooltipStatus( int );
    void showCryptedLabel( bool );

    void handleKeyPress( QKeyEvent * );

    void resizeStack( int w, int h )
    {
        if( !isFullScreen() && !isMaximized() && !b_isWindowTiled )
        {
            if( b_minimalView )
                resizeWindow( w, h ); /* Oh yes, it shouldn't
                                   be possible that size() - stackCentralW->size() < 0
                                   since stackCentralW is contained in the QMW... */
            else
                resizeWindow( width() - stackCentralW->width() + w, height() - stackCentralW->height() + h );
        }
        debug();
    }

    void setVideoSize( unsigned int, unsigned int );
    void videoSizeChanged( int, int );
    virtual void setVideoFullScreen( bool );
    void setHideMouse( bool );
    void setVideoOnTop( bool );
    void setBoss();
    void setRaise();
    void voutReleaseMouseEvents();

    void showResumePanel( int64_t);
    void hideResumePanel();
    void resumePlayback();
    void onInputChanged( bool );

    /* "Hide controls during playback" */
    void autoHideControlsTick();
    void hideControlsPlayback();
    void revealControlsPlayback();
    void videoDragRelayed( int phase );
    /* brings a window that just grew back inside the work area */
    void keepInsideScreen();

signals:
    void askGetVideo( struct vout_window_t *, unsigned, unsigned, bool,
                      bool * );
    void askReleaseVideo( bool );
    void askVideoToResize( unsigned int, unsigned int );
    void askVideoSetFullScreen( bool );
    void askHideMouse( bool );
    void askVideoOnTop( bool );
    void minimalViewToggled( bool );
    void fullscreenInterfaceToggled( bool );
    void askToQuit();
    void askBoss();
    void askRaise();
    void askRevealControls();
    void askVideoDrag( int phase );
    void autoHideControlsToggled( bool );
    void alwaysOnTopToggled( bool );
    void kc_pressed(); /* easter eggs */
};

#endif
