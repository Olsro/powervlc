/*****************************************************************************
 * extensions.cpp: Extensions manager for Qt: dialogs manager
 ****************************************************************************
 * Copyright (C) 2009-2010 VideoLAN and authors
 * $Id$
 *
 * Authors: Jean-Philippe André < jpeg # videolan.org >
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

#include "extensions.hpp"
#include "extensions_manager.hpp" // for isUnloading()

#include <vlc_dialog.h>

#include <QGridLayout>
#include <QPushButton>
#include <QSignalMapper>
#include <QLabel>
#include <QPixmap>
#include <QLineEdit>
#include <QTextBrowser>
#include <QCheckBox>
#include <QTreeWidget>
#include <QHeaderView>
#include <QComboBox>
#include <QCloseEvent>
#include <QKeyEvent>
#include <QMenu>
#include <QTimer>
#include <QHash>
#include <QScreen>
#include <QGuiApplication>
#include "util/customwidgets.hpp"

ExtensionsDialogProvider *ExtensionsDialogProvider::instance = NULL;

/**
 * Where each extension's dialog last stood.
 *
 * Changing view inside an extension deletes its dialog and builds the next
 * one, so what the user sees as a single window is really a succession of
 * them -- and Qt centres every new one. Moving the window therefore meant
 * nothing: the next view snapped it back to the middle of the screen.
 *
 * Keyed by the EXTENSION (p_dialog->p_sys) and not by the dialog, because
 * carrying the position across a dialog being replaced is the entire point.
 * The macOS provider keeps the same map, for the same reason.
 */
static QHash<const void *, QPoint> & DialogCorners()
{
    static QHash<const void *, QPoint> corners;
    return corners;
}

/** Remember where a dialog stands, just before it goes away. */
static void SaveDialogCorner( const QWidget *dialog,
                              const extension_dialog_t *p_dialog )
{
    if( dialog->isVisible() )
        DialogCorners().insert( p_dialog->p_sys,
                                dialog->frameGeometry().topLeft() );
}

/** Put a freshly built dialog back where its predecessor stood. */
static void RestoreDialogCorner( QWidget *dialog,
                                 const extension_dialog_t *p_dialog )
{
    if( !DialogCorners().contains( p_dialog->p_sys ) )
        return;

    dialog->move( DialogCorners().value( p_dialog->p_sys ) );

    /* A screen that went away, a resolution that changed, or a window that
     * grew since must not put it out of reach: if the remembered spot leaves
     * it on no screen at all, let it be centred as a new dialog would be. */
    const QRect frame = dialog->frameGeometry();
    foreach( const QScreen *screen, QGuiApplication::screens() )
        if( screen->availableGeometry().intersects( frame ) )
            return;

    const QScreen *primary = QGuiApplication::primaryScreen();
    if( primary != NULL )
    {
        const QRect avail = primary->availableGeometry();
        dialog->move( avail.center()
                      - QPoint( dialog->width() / 2, dialog->height() / 2 ) );
    }
}

static void DialogCallback( extension_dialog_t *p_ext_dialog,
                            void *p_data );


ExtensionsDialogProvider::ExtensionsDialogProvider( intf_thread_t *_p_intf,
                                                    extensions_manager_t *p_mgr )
        : QObject( NULL ), p_intf( _p_intf ), p_extensions_manager( p_mgr )
{
    vlc_dialog_provider_set_ext_callback( p_intf, DialogCallback, NULL );

    connect( this, &ExtensionsDialogProvider::SignalDialog,
             this, &ExtensionsDialogProvider::UpdateExtDialog );
}

ExtensionsDialogProvider::~ExtensionsDialogProvider()
{
    msg_Dbg( p_intf, "ExtensionsDialogProvider is quitting..." );
    vlc_dialog_provider_set_ext_callback( p_intf, NULL, NULL );
}

/** Create a dialog
 * Note: Lock on p_dialog->lock must be held. */
ExtensionDialog* ExtensionsDialogProvider::CreateExtDialog(
        extension_dialog_t *p_dialog )
{
    ExtensionDialog *dialog = new ExtensionDialog( p_intf,
                                                   p_extensions_manager,
                                                   p_dialog );
    p_dialog->p_sys_intf = (void*) dialog;
    connect( dialog, &ExtensionDialog::destroyDialog,
             this, &ExtensionsDialogProvider::DestroyExtDialog );
    return dialog;
}

/** Destroy a dialog
 * Note: Lock on p_dialog->lock must be held. */
int ExtensionsDialogProvider::DestroyExtDialog( extension_dialog_t *p_dialog )
{
    assert( p_dialog );
    ExtensionDialog *dialog = ( ExtensionDialog* ) p_dialog->p_sys_intf;
    if( !dialog )
        return VLC_EGENERIC;
    /* Before it goes: the next view this extension shows is a brand new
     * window, and it should come up where the user left this one. */
    SaveDialogCorner( dialog, p_dialog );
    delete dialog;
    p_dialog->p_sys_intf = NULL;
    vlc_cond_signal( &p_dialog->cond );
    return VLC_SUCCESS;
}

/**
 * Update/Create/Destroy a dialog
 **/
ExtensionDialog* ExtensionsDialogProvider::UpdateExtDialog(
        extension_dialog_t *p_dialog )
{
    assert( p_dialog );

    ExtensionDialog *dialog = ( ExtensionDialog* ) p_dialog->p_sys_intf;
    if( p_dialog->b_kill && !dialog )
    {
        /* This extension could not be activated properly but tried
           to create a dialog. We must ignore it. */
        return NULL;
    }

    vlc_mutex_lock( &p_dialog->lock );
    if( !p_dialog->b_kill && !dialog )
    {
        dialog = CreateExtDialog( p_dialog );
        /* Positioned before it is shown, so it does not appear centred and
         * then jump. The dialog already has its real size here: its
         * constructor runs UpdateWidgets(), which resizes it. */
        RestoreDialogCorner( dialog, p_dialog );
        dialog->setVisible( !p_dialog->b_hide );
        dialog->has_lock = false;
    }
    else if( !p_dialog->b_kill && dialog )
    {
        dialog->has_lock = true;
        dialog->UpdateWidgets();
        if( strcmp( qtu( dialog->windowTitle() ),
                    p_dialog->psz_title ) != 0 )
            dialog->setWindowTitle( qfu( p_dialog->psz_title ) );
        dialog->has_lock = false;
        dialog->setVisible( !p_dialog->b_hide );
    }
    else if( p_dialog->b_kill )
    {
        DestroyExtDialog( p_dialog );
    }
    vlc_cond_signal( &p_dialog->cond );
    vlc_mutex_unlock( &p_dialog->lock );
    return dialog;
}

/**
 * Ask the dialog manager to create/update/kill the dialog. Thread-safe.
 **/
void ExtensionsDialogProvider::ManageDialog( extension_dialog_t *p_dialog )
{
    assert( p_dialog );
    ExtensionsManager *extMgr = ExtensionsManager::getInstance( p_intf );
    assert( extMgr != NULL );
    if( !extMgr->isUnloading() )
        emit SignalDialog( p_dialog ); // Safe because we signal Qt thread
    else
        UpdateExtDialog( p_dialog ); // This is safe, we're already in Qt thread
}

/**
 * Ask the dialogs provider to create a new dialog
 **/
static void DialogCallback( extension_dialog_t *p_ext_dialog,
                            void *p_data )
{
    (void) p_data;

    ExtensionsDialogProvider *p_edp = ExtensionsDialogProvider::getInstance();
    if( p_edp )
        p_edp->ManageDialog( p_ext_dialog );
}


ExtensionDialog::ExtensionDialog( intf_thread_t *_p_intf,
                                  extensions_manager_t *p_mgr,
                                  extension_dialog_t *_p_dialog )
         : QDialog( NULL ), p_intf( _p_intf ), p_extensions_manager( p_mgr )
         , p_dialog( _p_dialog ), has_lock(true)
{
    assert( p_dialog );
    connect( ExtensionsDialogProvider::getInstance(), &ExtensionsDialogProvider::destroyed,
             this, &ExtensionDialog::parentDestroyed );

    msg_Dbg( p_intf, "Creating a new dialog: '%s'", p_dialog->psz_title );
    this->setWindowFlags( Qt::WindowMinMaxButtonsHint
                        | Qt::WindowCloseButtonHint );
    this->setWindowTitle( qfu( p_dialog->psz_title ) );

    layout = new QGridLayout( this );
    clickMapper = new QSignalMapper( this );
    connect( clickMapper, QSIGNALMAPPER_MAPPEDOBJ_SIGNAL, this, &ExtensionDialog::TriggerClick );
    inputMapper = new QSignalMapper( this );
    connect( inputMapper, QSIGNALMAPPER_MAPPEDOBJ_SIGNAL, this, &ExtensionDialog::SyncInput );
    selectMapper = new QSignalMapper( this );
    connect( selectMapper, QSIGNALMAPPER_MAPPEDOBJ_SIGNAL, this, &ExtensionDialog::SyncSelection );

    /* Typing is reported to the extension once the keys stop: a search
     * box that refills a long list would crawl otherwise. */
    p_debounced_widget = NULL;
    inputDebounce = new QTimer( this );
    inputDebounce->setSingleShot( true );
    inputDebounce->setInterval( 300 );
    connect( inputDebounce, &QTimer::timeout,
             this, &ExtensionDialog::NotifyTextChanged );

    UpdateWidgets();
}

ExtensionDialog::~ExtensionDialog()
{
    msg_Dbg( p_intf, "Deleting extension dialog '%s'", qtu(windowTitle()) );
}

/* Column separator inside a list cell, and inside the widget text that
 * carries the headers. Same convention as the macOS providers. */
static const QChar kCellSep = QLatin1Char( '\t' );
/* US (0x1F) separates what a cell SHOWS from what it is ORDERED ON. A script
 * needs it as soon as the readable form and the real order disagree: a
 * localised date, or "565,000 subscribers". */
static const QChar kSortKeySep = QLatin1Char( '\x1f' );

/**
 * Split one tab-separated string into its cells, and each cell into its
 * displayed text and its optional sort key.
 */
static void SplitCells( const QString &raw, QStringList &texts,
                        QStringList &keys )
{
    const QStringList cells = raw.split( kCellSep );
    for( const QString &cell : cells )
    {
        const int us = cell.indexOf( kSortKeySep );
        if( us < 0 )
        {
            texts << cell;
            keys << QString();
        }
        else
        {
            texts << cell.left( us );
            keys << cell.mid( us + 1 );
        }
    }
}

/**
 * A row of an extension list.
 *
 * Exists only to sort on the key rather than on the label, and to compare
 * numerically when both keys are numbers -- otherwise "10" sorts before "9"
 * and a column of sizes or counts is worse than useless. Falls back to the
 * displayed text when a cell carries no key, and to a locale-aware compare,
 * which is what the macOS side gets from NSNumericSearch.
 */
class ExtensionListItem : public QTreeWidgetItem
{
public:
    ExtensionListItem() : QTreeWidgetItem() {}

    bool operator<( const QTreeWidgetItem &other ) const override
    {
        const QTreeWidget *tree = treeWidget();
        const int col = tree ? tree->sortColumn() : 0;
        const QString a = key( this, col );
        const QString b = key( &other, col );

        bool aNum = false, bNum = false;
        const double da = a.toDouble( &aNum );
        const double db = b.toDouble( &bNum );
        if( aNum && bNum )
            return da < db;

        return QString::localeAwareCompare( a, b ) < 0;
    }

private:
    static QString key( const QTreeWidgetItem *item, int col )
    {
        const QString k = item->data( col, Qt::UserRole + 1 ).toString();
        return k.isEmpty() ? item->text( col ) : k;
    }
};

/**
 * (Re)build a list widget from the values the extension put in it.
 *
 * Cells are tab-separated and become real columns, with the widget's own text
 * carrying the header labels under the same convention -- which is what the
 * macOS providers have always done. A script that never sets a header text
 * gets one nameless column, i.e. exactly the plain list it had before.
 */
void ExtensionDialog::FillList( QTreeWidget *list,
                                extension_widget_t *p_widget )
{
    struct extension_widget_t::extension_widget_value_t *p_value;

    QStringList headers, headerKeys;
    if( p_widget->psz_text != NULL && *p_widget->psz_text != '\0' )
        SplitCells( qfu( p_widget->psz_text ), headers, headerKeys );

    /* A row may carry more cells than there are headers (and the other way
     * round); the widest wins, so nothing a script wrote is ever dropped. */
    int columns = headers.count();
    for( p_value = p_widget->p_values; p_value != NULL;
         p_value = p_value->p_next )
    {
        const int n = qfu( p_value->psz_text ).count( kCellSep ) + 1;
        if( n > columns )
            columns = n;
    }
    if( columns < 1 )
        columns = 1;

    /* Was this view already sorting -- because the script asked for an order,
     * or because the user clicked a header? Refilling must undo neither. */
    const bool wasSorting = list->isSortingEnabled();

    /* Sorting off while filling: with it on, every insertion re-sorts the
     * whole tree, which a few thousand rows would make painful. */
    list->setSortingEnabled( false );
    list->clear();
    list->setColumnCount( columns );

    if( headers.isEmpty() )
    {
        list->setHeaderHidden( true );
    }
    else
    {
        while( headers.count() < columns )
            headers << QString();
        list->setHeaderLabels( headers );
        list->setHeaderHidden( false );
    }

    for( p_value = p_widget->p_values; p_value != NULL;
         p_value = p_value->p_next )
    {
        QStringList texts, keys;
        SplitCells( qfu( p_value->psz_text ), texts, keys );

        ExtensionListItem *item = new ExtensionListItem();
        for( int c = 0; c < columns; c++ )
        {
            item->setText( c, texts.value( c ) );
            if( !keys.value( c ).isEmpty() )
                item->setData( c, Qt::UserRole + 1, keys.value( c ) );
        }
        /* ⚠ The row is identified by its i_id and never by its position:
         * sorting reorders the view, not p_values. Selection is mapped back
         * through this, the same lesson the macOS side learned the hard way. */
        item->setData( 0, Qt::UserRole, p_value->i_id );
        list->addTopLevelItem( item );
    }

    /* The order the script asked for (1-based, 0 = leave as added).
     *
     * ⚠⚠ Never just switch sorting on and leave the column to Qt.
     * QTreeView::setSortingEnabled(true) sorts straight away by whatever the
     * header's indicator currently says, and a fresh QHeaderView says column
     * 0, Qt::DescendingOrder -- so arming it here handed every list back
     * reversed, Z to A. The indicator has to be set first, or sorting has to
     * stay off. */
    if( p_widget->i_sort_column > 0 && p_widget->i_sort_column <= columns )
    {
        /* sortByColumn() sets the indicator AND sorts even while sorting is
         * disabled, so the order is right before it is armed. */
        list->sortByColumn( p_widget->i_sort_column - 1,
                            p_widget->b_sort_ascending ? Qt::AscendingOrder
                                                       : Qt::DescendingOrder );
        list->setSortingEnabled( true );
    }
    else if( wasSorting )
    {
        /* The user picked a column earlier: refilling keeps their choice,
         * since the header still carries that indicator. */
        list->setSortingEnabled( true );
    }
    else
    {
        /* Nothing asked, nothing picked: keep the order the script added its
         * rows in -- which is what i_sort_column == 0 means, and what the
         * macOS providers do. Sorting is armed by the first header click
         * instead (see the connection made in CreateWidget). */
        list->setSortingEnabled( false );
    }

    /* Last: setSortingEnabled() also drives this, and a list whose header is
     * shown should stay clickable whether or not it is sorting yet. */
    list->header()->setSectionsClickable( !headers.isEmpty() );

    for( int c = 0; c < columns; c++ )
        list->resizeColumnToContents( c );
}

/**
 * resize() to the layout's wish, with the width kept within reason.
 *
 * A dialog grows to whatever its widgets ask for, and an unwrapped label asks
 * for the width of its longest line: one paragraph of description made the
 * window several times wider than the screen. Labels now wrap, but a wrapped
 * label still reports a single-line sizeHint until something bounds its width
 * -- so bound it here. 720 is the cap the macOS providers already use, for
 * this very reason. A script that asked for a wider dialog still gets it:
 * its own request wins over the cap.
 */
void ExtensionDialog::ResizeToHint()
{
    QSize hint = sizeHint();
    const int cap = qMax( 720, p_dialog->i_width );

    if( hint.width() > cap )
    {
        hint.setWidth( cap );
        /* a label can only say how tall it is once it knows how wide it
         * may be */
        if( layout != NULL && layout->hasHeightForWidth() )
            hint.setHeight( qMax( hint.height(),
                                  layout->heightForWidth( cap ) ) );
    }

    /* Once on screen, only ever grow.
     *
     * A rebuilt widget is empty for an instant, and the layout's wish collapses
     * with it: resizing to that wish shrinks the window, and the next moment --
     * when the widget has its content back -- grows it again. The user sees the
     * window snap small and back for every update. Invidious' "list public
     * instances" does it twice, once when it clears the list and once when it
     * fills it, and both were plainly visible.
     *
     * Only while the dialog is already visible: an unmapped QWidget reports a
     * default 640x480 that has nothing to do with its content, and honouring it
     * would floor every extension dialog at that size. Shrinking is not lost
     * either -- changing view inside an extension destroys the dialog and
     * builds the next one, which starts from its own hint (see
     * DialogCorners()). */
    if( isVisible() )
        hint = hint.expandedTo( size() );

    resize( hint );
}

QWidget* ExtensionDialog::CreateWidget( extension_widget_t *p_widget )
{
    QLabel *label = NULL;
    QPushButton *button = NULL;
    QTextBrowser *textArea = NULL;
    QLineEdit *textInput = NULL;
    QCheckBox *checkBox = NULL;
    QComboBox *comboBox = NULL;
    QTreeWidget *list = NULL;
    SpinningIcon *spinIcon = NULL;
    struct extension_widget_t::extension_widget_value_t *p_value = NULL;

    assert( p_widget->p_sys_intf == NULL );

    switch( p_widget->type )
    {
        case EXTENSION_WIDGET_LABEL:
            label = new QLabel( qfu( p_widget->psz_text ), this );
            p_widget->p_sys_intf = label;
            label->setTextFormat( Qt::RichText );
            label->setOpenExternalLinks( true );
            /* Without this a paragraph is laid out as one endless line and
             * drags the whole dialog out with it -- a film synopsis made the
             * window wider than the screen. See also ResizeToHint(), which
             * bounds the width a wrapped label is first measured at. */
            label->setWordWrap( true );
            return label;

        case EXTENSION_WIDGET_BUTTON:
            button = new QPushButton( qfu( p_widget->psz_text ), this );
            clickMapper->setMapping( button, new WidgetMapper( button, p_widget ) );
            connect( button, &QPushButton::clicked, clickMapper, QOverload<>::of(&QSignalMapper::map) );
            p_widget->p_sys_intf = button;
            return button;

        case EXTENSION_WIDGET_IMAGE:
            label = new QLabel( this );
            label->setPixmap( QPixmap( qfu( p_widget->psz_text ) ) );
            if( p_widget->i_width > 0 )
                label->setMaximumWidth( p_widget->i_width );
            if( p_widget->i_height > 0 )
                label->setMaximumHeight( p_widget->i_height );
            /* Kept to its own size and hung from the top of the cells it
             * covers: stretched to a block of several rows, a poster came
             * out distorted and drifted away from the text it goes with.
             * A script whose picture sits beside a list asks for the
             * middle of the block instead (set_centered). */
            label->setAlignment( p_widget->b_image_centered
                                 ? Qt::AlignCenter
                                 : ( Qt::AlignTop | Qt::AlignHCenter ) );
            p_widget->p_sys_intf = label;
            return label;

        case EXTENSION_WIDGET_HTML:
            textArea = new QTextBrowser( this );
            textArea->setOpenExternalLinks( true );
            textArea->setHtml( qfu( p_widget->psz_text ) );
            p_widget->p_sys_intf = textArea;
            return textArea;

        case EXTENSION_WIDGET_TEXT_FIELD:
            textInput = new QLineEdit( this );
            textInput->setText( qfu( p_widget->psz_text ) );
            textInput->setReadOnly( false );
            textInput->setEchoMode( QLineEdit::Normal );
            inputMapper->setMapping( textInput, new WidgetMapper( textInput, p_widget ) );
            /// @note: maybe it would be wiser to use textEdited here?
            connect( textInput, &QLineEdit::textChanged,
                     inputMapper, QOverload<>::of(&QSignalMapper::map) );
            /* Enter validates the field, like any search box */
            clickMapper->setMapping( textInput, new WidgetMapper( textInput, p_widget ) );
            connect( textInput, &QLineEdit::returnPressed,
                     clickMapper, QOverload<>::of(&QSignalMapper::map) );
            p_widget->p_sys_intf = textInput;
            return textInput;

        case EXTENSION_WIDGET_PASSWORD:
            textInput = new QLineEdit( this );
            textInput->setText( qfu( p_widget->psz_text ) );
            textInput->setReadOnly( false );
            textInput->setEchoMode( QLineEdit::Password );
            inputMapper->setMapping( textInput, new WidgetMapper( textInput, p_widget ) );
            /// @note: maybe it would be wiser to use textEdited here?
            connect( textInput, &QLineEdit::textChanged,
                     inputMapper, QOverload<>::of(&QSignalMapper::map) );
            /* Enter validates the field, like any search box */
            clickMapper->setMapping( textInput, new WidgetMapper( textInput, p_widget ) );
            connect( textInput, &QLineEdit::returnPressed,
                     clickMapper, QOverload<>::of(&QSignalMapper::map) );
            p_widget->p_sys_intf = textInput;
            return textInput;

        case EXTENSION_WIDGET_CHECK_BOX:
            checkBox = new QCheckBox( this );
            checkBox->setText( qfu( p_widget->psz_text ) );
            checkBox->setChecked( p_widget->b_checked );
            clickMapper->setMapping( checkBox, new WidgetMapper( checkBox, p_widget ) );
            connect( checkBox, &QCheckBox::stateChanged, clickMapper, QOverload<>::of(&QSignalMapper::map) );
            p_widget->p_sys_intf = checkBox;
            return checkBox;

        case EXTENSION_WIDGET_DROPDOWN:
            comboBox = new QComboBox( this );
            comboBox->setEditable( false );
            for( p_value = p_widget->p_values;
                 p_value != NULL;
                 p_value = p_value->p_next )
            {
                comboBox->addItem( qfu( p_value->psz_text ), p_value->i_id );
            }
            /* Set current item.
             *
             * ⚠ By the selected VALUE, not by the widget's text: set_value()
             * only ever sets b_selected on the value it matches (dialog.c) and
             * never touches psz_text, so looking the text up here could not
             * work. It found nothing, the box kept item 0, and a script that
             * had carefully picked an entry got whatever sorted first -- the
             * Podcasts extension opened on the South African store on a French
             * system, simply because "Afrique du Sud" comes first in French.
             * UpdateWidget() has always done it this way; creation had not. */
            for( p_value = p_widget->p_values;
                 p_value != NULL;
                 p_value = p_value->p_next )
            {
                if( !p_value->b_selected )
                    continue;
                int idx = comboBox->findData( p_value->i_id );
                if( idx >= 0 )
                    comboBox->setCurrentIndex( idx );
                break;
            }
            selectMapper->setMapping( comboBox, new WidgetMapper( comboBox, p_widget ) );
            connect( comboBox, QOverload<int>::of(&QComboBox::currentIndexChanged),
                     selectMapper, QOverload<>::of(&QSignalMapper::map) );
            return comboBox;

        case EXTENSION_WIDGET_LIST:
            list = new QTreeWidget( this );
            list->setSelectionMode( QAbstractItemView::ExtendedSelection );
            /* a flat list of rows, not a tree: no expanders, no indent */
            list->setRootIsDecorated( false );
            list->setUniformRowHeights( true );
            list->setAllColumnsShowFocus( true );
            /* the header may need dragging when a column is wider than the
             * dialog, which is common for URLs */
            list->header()->setStretchLastSection( true );
            /* Sorting is armed by the first header click, not up front: see
             * FillList(). QHeaderView flips its indicator on a click as long
             * as the sections are clickable, even with sorting still off, and
             * a click on a column that was not the sorted one starts
             * ASCENDING -- which is the order a first click should give.
             * (No recursion here: setSortingEnabled() re-applies the very
             * same indicator, and QHeaderView::setSortIndicator() returns
             * early when nothing changed.) */
            connect( list->header(), &QHeaderView::sortIndicatorChanged,
                     list, [list]( int, Qt::SortOrder ) {
                         if( !list->isSortingEnabled() )
                             list->setSortingEnabled( true );
                     } );
            FillList( list, p_widget );
            selectMapper->setMapping( list, new WidgetMapper( list, p_widget ) );
            connect( list, &QTreeWidget::itemSelectionChanged,
                     selectMapper, QOverload<>::of(&QSignalMapper::map) );
            /* double-click forwards to the optional Lua list callback */
            clickMapper->setMapping( list, new WidgetMapper( list, p_widget ) );
            connect( list, &QTreeWidget::itemDoubleClicked,
                     clickMapper, QOverload<>::of(&QSignalMapper::map) );
            /* right-click: the context menu the extension attached with
             * set_menu. set_drag (drag-out with a file promise) has no
             * Qt wiring yet: downloads go through the button and this
             * menu instead. */
            list->setContextMenuPolicy( Qt::CustomContextMenu );
            connect( list, &QTreeWidget::customContextMenuRequested,
                     this, [this, list, p_widget]( const QPoint &pos ) {
                         ListContextMenu( list, p_widget, pos );
                     } );
            return list;

        case EXTENSION_WIDGET_SPIN_ICON:
            spinIcon = new SpinningIcon( this );
            spinIcon->play( p_widget->i_spin_loops );
            p_widget->p_sys_intf = spinIcon;
            return spinIcon;

        default:
            msg_Err( p_intf, "Widget type %d unknown", p_widget->type );
            return NULL;
    }
}

/**
 * Forward click event to the extension
 * @param object A WidgetMapper, whose data() is the p_widget
 **/
int ExtensionDialog::TriggerClick( QObject *object )
{
    assert( object != NULL );
    WidgetMapper *mapping = static_cast< WidgetMapper* >( object );
    extension_widget_t *p_widget = mapping->getWidget();

    QCheckBox *checkBox = NULL;
    int i_ret = VLC_EGENERIC;

    bool lockedHere = false;
    if( !has_lock )
    {
        vlc_mutex_lock( &p_dialog->lock );
        has_lock = true;
        lockedHere = true;
    }

    switch( p_widget->type )
    {
        case EXTENSION_WIDGET_BUTTON:
        case EXTENSION_WIDGET_LIST:
        case EXTENSION_WIDGET_TEXT_FIELD:
        case EXTENSION_WIDGET_PASSWORD:
            /* for a list this is a double-click, for an entry field the
             * Enter key; the Lua side only acts when the script registered
             * a callback for it */
            i_ret = extension_WidgetClicked( p_dialog, p_widget );
            break;

        case EXTENSION_WIDGET_CHECK_BOX:
            checkBox = static_cast< QCheckBox* >( p_widget->p_sys_intf );
            p_widget->b_checked = checkBox->isChecked();
            /* A toggle is a click too -- but only one the user made:
             * UpdateWidget re-checks the box while the dialog lock is
             * already held, and lockedHere is false then. Scripts
             * without an on_toggle callback never see the event. */
            if( lockedHere )
                i_ret = extension_WidgetClicked( p_dialog, p_widget );
            else
                i_ret = VLC_SUCCESS;
            break;

        default:
            msg_Dbg( p_intf, "A click event was triggered by a wrong widget" );
            break;
    }

    if( lockedHere )
    {
        vlc_mutex_unlock( &p_dialog->lock );
        has_lock = false;
    }

    return i_ret;
}

/**
 * Right-click on a list: pop up the context menu the extension attached
 * with set_menu and forward the picked entry (1-based); the clicked row
 * becomes the selection the extension reads.
 **/
void ExtensionDialog::ListContextMenu( QTreeWidget *list,
                                       extension_widget_t *p_widget,
                                       const QPoint &pos )
{
    QTreeWidgetItem *item = list->itemAt( pos );
    if( item == NULL )
        return;

    /* the labels belong to the extension thread: copy them under the
     * dialog lock and hold it for nothing else -- the menu below runs
     * an event loop */
    QStringList labels;
    bool lockedHere = false;
    if( !has_lock )
    {
        vlc_mutex_lock( &p_dialog->lock );
        has_lock = true;
        lockedHere = true;
    }
    for( int i = 0; i < p_widget->i_menu; i++ )
        labels << qfu( p_widget->pp_menu[i] );
    if( lockedHere )
    {
        vlc_mutex_unlock( &p_dialog->lock );
        has_lock = false;
    }
    if( labels.isEmpty() )
        return;

    /* a user action: the selection change does reach the extension, so
     * its state follows the highlight */
    if( !item->isSelected() )
        list->setCurrentItem( item );

    QMenu menu( list );
    for( int i = 0; i < labels.count(); i++ )
        menu.addAction( labels.at( i ) )->setData( i + 1 );
    QAction *picked = menu.exec( list->viewport()->mapToGlobal( pos ) );
    if( picked == NULL )
        return;
    p_widget->i_menu_choice = picked->data().toInt();
    /* unlocked on purpose: this wakes the extension thread, which may
     * answer with an update this very thread has to run */
    extension_WidgetMenuSelected( p_dialog, p_widget );
}

/**
 * Synchronize psz_text with the widget's text() value on update
 * @param object A WidgetMapper
 **/
void ExtensionDialog::SyncInput( QObject *object )
{
    assert( object != NULL );

    bool lockedHere = false;
    if( !has_lock )
    {
        vlc_mutex_lock( &p_dialog->lock );
        has_lock = true;
        lockedHere = true;
    }

    WidgetMapper *mapping = static_cast< WidgetMapper* >( object );
    extension_widget_t *p_widget = mapping->getWidget();
    assert( p_widget->type == EXTENSION_WIDGET_TEXT_FIELD
            || p_widget->type == EXTENSION_WIDGET_PASSWORD );
    /* Synchronize psz_text with the new value */
    QLineEdit *widget = static_cast< QLineEdit* >( p_widget->p_sys_intf );
    char *psz_text = widget->text().isNull() ? NULL : strdup( qtu( widget->text() ) );
    free( p_widget->psz_text );
    p_widget->psz_text =  psz_text;

    if( lockedHere )
    {
        vlc_mutex_unlock( &p_dialog->lock );
        has_lock = false;
        /* lockedHere means the user typed this; refilling the field from
         * the extension gets here too and must not bounce back at it. */
        p_debounced_widget = p_widget;
        inputDebounce->start();
    }
}

/**
 * Typing stopped: hand the change to the extension.
 **/
void ExtensionDialog::NotifyTextChanged()
{
    if( p_debounced_widget == NULL )
        return;
    extension_widget_t *p_widget = p_debounced_widget;
    p_debounced_widget = NULL;
    /* unlocked on purpose: this wakes the extension thread, which may
     * answer with an update this very thread has to run */
    extension_WidgetSelectionChanged( p_dialog, p_widget );
}

/**
 * Synchronize parameter b_selected in the values list
 * @param object A WidgetMapper
 **/
void ExtensionDialog::SyncSelection( QObject *object )
{
    assert( object != NULL );
    struct extension_widget_t::extension_widget_value_t *p_value;

    bool lockedHere = false;
    if( !has_lock )
    {
        vlc_mutex_lock( &p_dialog->lock );
        has_lock = true;
        lockedHere = true;
    }

    WidgetMapper *mapping = static_cast< WidgetMapper* >( object );
    extension_widget_t *p_widget = mapping->getWidget();
    assert( p_widget->type == EXTENSION_WIDGET_DROPDOWN
            || p_widget->type == EXTENSION_WIDGET_LIST );

    if( p_widget->type == EXTENSION_WIDGET_DROPDOWN )
    {
        QComboBox *combo = static_cast< QComboBox* >( p_widget->p_sys_intf );
        for( p_value = p_widget->p_values;
             p_value != NULL;
             p_value = p_value->p_next )
        {
//             if( !qstrcmp( p_value->psz_text, qtu( combo->currentText() ) ) )
            if( combo->itemData( combo->currentIndex(), Qt::UserRole ).toInt()
                == p_value->i_id )
            {
                p_value->b_selected = true;
            }
            else
            {
                p_value->b_selected = false;
            }
        }
        free( p_widget->psz_text );
        p_widget->psz_text = strdup( qtu( combo->currentText() ) );
    }
    else if( p_widget->type == EXTENSION_WIDGET_LIST )
    {
        QTreeWidget *list = static_cast<QTreeWidget*>( p_widget->p_sys_intf );
        QList<QTreeWidgetItem *> selection = list->selectedItems();
        for( p_value = p_widget->p_values;
             p_value != NULL;
             p_value = p_value->p_next )
        {
            bool b_selected = false;
            foreach( const QTreeWidgetItem *item, selection )
            {
                /* by id, never by row: sorting reorders the view only */
                if( item->data( 0, Qt::UserRole ).toInt() == p_value->i_id )
                {
                    b_selected = true;
                    break;
                }
            }
            p_value->b_selected = b_selected;
        }
    }

    if( lockedHere )
    {
        /* lockedHere means the signal came from the user: repopulating a
         * list or a drop-down emits it too, and that must not reach the
         * extension */
        vlc_mutex_unlock( &p_dialog->lock );
        has_lock = false;
        /* unlocked: the notification wakes the extension thread, which
         * may answer with an update this thread has to run */
        extension_WidgetSelectionChanged( p_dialog, p_widget );
    }
}

void ExtensionDialog::UpdateWidgets()
{
    assert( p_dialog );
    extension_widget_t *p_widget;
    /* Resize once, at the end. Resizing inside the loop made the window jump
     * to a new size for every widget added, updated or removed: filling a list
     * of public Invidious instances redrew the frame a dozen times in a row,
     * which reads as flicker. The end result is identical -- sizeHint() is a
     * property of the finished layout, not of the order it was built in. */
    bool resize_pending = false;
    FOREACH_ARRAY( p_widget, p_dialog->widgets )
    {
        if( !p_widget ) continue; /* Some widgets may be NULL at this point */
        QWidget *widget;
        int row = p_widget->i_row - 1;
        int col = p_widget->i_column - 1;
        if( row < 0 )
        {
            row = layout->rowCount();
            col = 0;
        }
        else if( col < 0 )
            col = layout->columnCount();
        int hsp = __MAX( 1, p_widget->i_horiz_span );
        int vsp = __MAX( 1, p_widget->i_vert_span );
        if( !p_widget->p_sys_intf && !p_widget->b_kill )
        {
            widget = CreateWidget( p_widget );
            if( !widget )
            {
                msg_Warn( p_intf, "Could not create a widget for dialog %s",
                          p_dialog->psz_title );
                continue;
            }
            widget->setVisible( !p_widget->b_hide );
            layout->addWidget( widget, row, col, vsp, hsp );
            if( ( p_widget->i_width > 0 ) && ( p_widget->i_height > 0 ) )
                widget->resize( p_widget->i_width, p_widget->i_height );
            p_widget->p_sys_intf = widget;
            resize_pending = true;
            /* If an update was required, cancel it as we just created the widget */
            p_widget->b_update = false;
        }
        else if( p_widget->p_sys_intf && !p_widget->b_kill
                 && p_widget->b_update )
        {
            widget = UpdateWidget( p_widget );
            if( !widget )
            {
                msg_Warn( p_intf, "Could not update a widget for dialog %s",
                          p_dialog->psz_title );
                if( resize_pending )
                    ResizeToHint();
                return;
            }
            widget->setVisible( !p_widget->b_hide );
            layout->addWidget( widget, row, col, vsp, hsp );
            if( ( p_widget->i_width > 0 ) && ( p_widget->i_height > 0 ) )
                widget->resize( p_widget->i_width, p_widget->i_height );
            p_widget->p_sys_intf = widget;
            resize_pending = true;

            /* Do not update again */
            p_widget->b_update = false;
        }
        else if( p_widget->p_sys_intf && p_widget->b_kill )
        {
            DestroyWidget( p_widget );
            p_widget->p_sys_intf = NULL;
            resize_pending = true;
        }
    }
    FOREACH_END()

    if( resize_pending )
        ResizeToHint();

    /* The extension may ask for more room than its widgets need (a list of
     * long URLs is unreadable at its natural width). Only ever grow. */
    if( p_dialog->i_width > 0 || p_dialog->i_height > 0 )
        this->resize( qMax( width(), p_dialog->i_width ),
                      qMax( height(), p_dialog->i_height ) );
}

QWidget* ExtensionDialog::UpdateWidget( extension_widget_t *p_widget )
{
    QLabel *label = NULL;
    QPushButton *button = NULL;
    QTextBrowser *textArea = NULL;
    QLineEdit *textInput = NULL;
    QCheckBox *checkBox = NULL;
    QComboBox *comboBox = NULL;
    QTreeWidget *list = NULL;
    SpinningIcon *spinIcon = NULL;
    struct extension_widget_t::extension_widget_value_t *p_value = NULL;

    assert( p_widget->p_sys_intf != NULL );

    switch( p_widget->type )
    {
        case EXTENSION_WIDGET_LABEL:
            label = static_cast< QLabel* >( p_widget->p_sys_intf );
            label->setText( qfu( p_widget->psz_text ) );
            return label;

        case EXTENSION_WIDGET_BUTTON:
            // FIXME: looks like removeMappings does not work
            button = static_cast< QPushButton* >( p_widget->p_sys_intf );
            button->setText( qfu( p_widget->psz_text ) );
            clickMapper->removeMappings( button );
            clickMapper->setMapping( button, new WidgetMapper( button, p_widget ) );
            connect( button, &QPushButton::clicked, clickMapper, QOverload<>::of(&QSignalMapper::map) );
            return button;

        case EXTENSION_WIDGET_IMAGE:
            label = static_cast< QLabel* >( p_widget->p_sys_intf );
            label->setPixmap( QPixmap( qfu( p_widget->psz_text ) ) );
            /* set_centered may have been called after the picture was
             * created, so the alignment is settled here too */
            label->setAlignment( p_widget->b_image_centered
                                 ? Qt::AlignCenter
                                 : ( Qt::AlignTop | Qt::AlignHCenter ) );
            return label;

        case EXTENSION_WIDGET_HTML:
            textArea = static_cast< QTextBrowser* >( p_widget->p_sys_intf );
            textArea->setHtml( qfu( p_widget->psz_text ) );
            return textArea;

        case EXTENSION_WIDGET_TEXT_FIELD:
            textInput = static_cast< QLineEdit* >( p_widget->p_sys_intf );
            textInput->setText( qfu( p_widget->psz_text ) );
            return textInput;

        case EXTENSION_WIDGET_PASSWORD:
            textInput = static_cast< QLineEdit* >( p_widget->p_sys_intf );
            textInput->setText( qfu( p_widget->psz_text ) );
            return textInput;

        case EXTENSION_WIDGET_CHECK_BOX:
            checkBox = static_cast< QCheckBox* >( p_widget->p_sys_intf );
            checkBox->setText( qfu( p_widget->psz_text ) );
            checkBox->setChecked( p_widget->b_checked );
            return checkBox;

        case EXTENSION_WIDGET_DROPDOWN:
            comboBox = static_cast< QComboBox* >( p_widget->p_sys_intf );
            // method widget:clear()
            if ( p_widget->p_values == NULL )
            {
                comboBox->clear();
                return comboBox;
            }
            // method widget:addvalue()
            for( p_value = p_widget->p_values;
                 p_value != NULL;
                 p_value = p_value->p_next )
            {
                if ( comboBox->findText( qfu( p_value->psz_text ) ) < 0 )
                    comboBox->addItem( qfu( p_value->psz_text ), p_value->i_id );
                /* the script may have chosen an entry other than the
                 * first one, see set_value */
                if ( p_value->b_selected )
                {
                    int idx = comboBox->findData( p_value->i_id );
                    if ( idx >= 0 && idx != comboBox->currentIndex() )
                        comboBox->setCurrentIndex( idx );
                }
            }
            return comboBox;

        case EXTENSION_WIDGET_LIST:
            list = static_cast< QTreeWidget* >( p_widget->p_sys_intf );
            FillList( list, p_widget );
            return list;

        case EXTENSION_WIDGET_SPIN_ICON:
            spinIcon = static_cast< SpinningIcon* >( p_widget->p_sys_intf );
            if( !spinIcon->isPlaying() && p_widget->i_spin_loops != 0 )
                spinIcon->play( p_widget->i_spin_loops );
            else if( spinIcon->isPlaying() && p_widget->i_spin_loops == 0 )
                spinIcon->stop();
            p_widget->i_height = p_widget->i_width = 16;
            return spinIcon;

        default:
            msg_Err( p_intf, "Widget type %d unknown", p_widget->type );
            return NULL;
    }
}

void ExtensionDialog::DestroyWidget( extension_widget_t *p_widget,
                                     bool b_cond )
{
    assert( p_widget && p_widget->b_kill );
    /* a debounced text change must not fire at a widget that is gone */
    if( p_debounced_widget == p_widget )
    {
        inputDebounce->stop();
        p_debounced_widget = NULL;
    }
    QWidget *widget = static_cast< QWidget* >( p_widget->p_sys_intf );
    delete widget;
    p_widget->p_sys_intf = NULL;
    if( b_cond )
        vlc_cond_signal( &p_dialog->cond );
}

/** Implement closeEvent() in order to intercept the event */
void ExtensionDialog::closeEvent( QCloseEvent * )
{
    assert( p_dialog != NULL );
    msg_Dbg( p_intf, "Dialog '%s' received a closeEvent",
             p_dialog->psz_title );
    extension_DialogClosed( p_dialog );
}

/** Grab some keyboard input (ESC, ...) and handle actions manually */
void ExtensionDialog::keyPressEvent( QKeyEvent *event )
{
    assert( p_dialog != NULL );
    switch( event->key() )
    {
    case Qt::Key_Escape:
        close();
        return;
    case Qt::Key_Return:
    case Qt::Key_Enter:
        /* Enter belongs to whatever holds the focus, and to nothing else.
         *
         * A QLineEdit emits returnPressed() -- which is how the extension
         * hears about it -- and then IGNORES the key, so it bubbles up to
         * QDialog::keyPressEvent(), which clicks the first autoDefault
         * QPushButton it can find. In Subsonic that meant typing a search and
         * pressing Enter also pressed "back to the connection page", a button
         * the user never aimed at and which threw the session away.
         *
         * Swallowing it here rather than clearing autoDefault on every button
         * keeps the case that does make sense: a button that HAS the focus
         * still acts on Enter, because QPushButton handles the key itself and
         * it never reaches us. */
        event->accept();
        return;
    default:
        QDialog::keyPressEvent( event );
        return;
    }
}

void ExtensionDialog::parentDestroyed()
{
    msg_Dbg( p_intf, "About to destroy dialog '%s'", p_dialog->psz_title );
    deleteLater(); // May not work at this point (event loop can be ended)
    p_dialog->p_sys_intf = NULL;
    vlc_cond_signal( &p_dialog->cond );
}
