/*****************************************************************************
 * powervlc_media_preferences.cpp: PowerVLC media and device preferences
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "qt.hpp"
#include "components/powervlc_media_preferences.hpp"
#include "main_interface.hpp"
#include "components/playlist/playlist.hpp"

#include <vlc_configuration.h>
#include <vlc_playlist.h>
#include <vlc_services_discovery.h>

#include <QCheckBox>
#include <QComboBox>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QFileDialog>
#include <QFileInfo>
#include <QFormLayout>
#include <QGroupBox>
#include <QHBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QSpinBox>
#include <QTableWidget>
#include <QTreeWidget>
#include <QVBoxLayout>

namespace
{
enum { SerializedRole = Qt::UserRole + 57 };

static QString configString( vlc_object_t *obj, const char *name )
{
    char *value = config_GetPsz( obj, name );
    QString result = value ? qfu( value ) : QString();
    free( value );
    return result;
}

/* The core database uses percent escaping. Encode the rule separators too so
 * a user-entered pipe or semicolon never changes the rule grammar. */
static QString encodeField( const QString &value )
{
    const QByteArray bytes = value.toUtf8();
    QByteArray result;
    static const char hex[] = "0123456789ABCDEF";
    result.reserve( bytes.size() * 3 );
    for( unsigned char c : bytes )
    {
        if( c >= 0x20 && c != '%' && c != '\t' && c != '\r' && c != '\n'
         && c != '|' && c != ';' )
            result.append( static_cast<char>( c ) );
        else
        {
            result.append( '%' );
            result.append( hex[c >> 4] );
            result.append( hex[c & 15] );
        }
    }
    return QString::fromLatin1( result );
}

static int hexValue( QChar c )
{
    ushort u = c.unicode();
    if( u >= '0' && u <= '9' ) return u - '0';
    if( u >= 'a' && u <= 'f' ) return u - 'a' + 10;
    if( u >= 'A' && u <= 'F' ) return u - 'A' + 10;
    return -1;
}

static QString decodeField( const QString &value )
{
    QByteArray bytes = value.toLatin1();
    QByteArray result;
    result.reserve( bytes.size() );
    for( int i = 0; i < bytes.size(); ++i )
    {
        if( bytes[i] == '%' && i + 2 < bytes.size() )
        {
            int a = hexValue( QLatin1Char( bytes[i + 1] ) );
            int b = hexValue( QLatin1Char( bytes[i + 2] ) );
            if( a >= 0 && b >= 0 )
            {
                result.append( static_cast<char>( (a << 4) | b ) );
                i += 2;
                continue;
            }
        }
        result.append( bytes[i] );
    }
    return QString::fromUtf8( result );
}

static QPushButton *button( const QString &text, QBoxLayout *layout )
{
    QPushButton *result = new QPushButton( text );
    layout->addWidget( result );
    return result;
}

static void prepareTree( QTreeWidget *tree, const QStringList &headers )
{
    tree->setColumnCount( headers.size() );
    tree->setHeaderLabels( headers );
    tree->setRootIsDecorated( false );
    tree->setAlternatingRowColors( true );
    tree->setSelectionMode( QAbstractItemView::SingleSelection );
    tree->header()->setSectionResizeMode( 0, QHeaderView::Stretch );
    for( int i = 1; i < headers.size(); ++i )
        tree->header()->setSectionResizeMode( i, QHeaderView::ResizeToContents );
}

class SmartPlaylistDialog : public QDialog
{
public:
    SmartPlaylistDialog( QWidget *parent, const QString &serialized = QString() )
        : QDialog( parent ), name( new QLineEdit ), match( new QComboBox ),
          limit( new QSpinBox ), rules( new QTableWidget( 0, 3 ) )
    {
        setWindowTitle( qtr( "Smart Playlist" ) );
        resize( 720, 360 );
        QVBoxLayout *outer = new QVBoxLayout( this );
        QFormLayout *form = new QFormLayout;
        form->addRow( qtr( "Name" ), name );
        match->addItem( qtr( "all of the following rules" ), "all" );
        match->addItem( qtr( "any of the following rules" ), "any" );
        form->addRow( qtr( "Match" ), match );
        limit->setRange( 0, 100000 );
        limit->setSpecialValueText( qtr( "No limit" ) );
        form->addRow( qtr( "Maximum number of items" ), limit );
        outer->addLayout( form );

        rules->setHorizontalHeaderLabels( QStringList() << qtr( "Field" )
                                                       << qtr( "Condition" )
                                                       << qtr( "Value" ) );
        rules->horizontalHeader()->setSectionResizeMode( 0, QHeaderView::ResizeToContents );
        rules->horizontalHeader()->setSectionResizeMode( 1, QHeaderView::ResizeToContents );
        rules->horizontalHeader()->setSectionResizeMode( 2, QHeaderView::Stretch );
        rules->verticalHeader()->hide();
        outer->addWidget( rules );
        QHBoxLayout *ruleButtons = new QHBoxLayout;
        QPushButton *add = button( qtr( "Add rule" ), ruleButtons );
        QPushButton *remove = button( qtr( "Remove rule" ), ruleButtons );
        ruleButtons->addStretch();
        outer->addLayout( ruleButtons );
        connect( add, &QPushButton::clicked, this, [this] { addRule(); } );
        connect( remove, &QPushButton::clicked, this, [this] {
            int row = rules->currentRow();
            if( row >= 0 ) rules->removeRow( row );
        } );

        QDialogButtonBox *buttons = new QDialogButtonBox(
            QDialogButtonBox::Ok | QDialogButtonBox::Cancel );
        connect( buttons, &QDialogButtonBox::accepted, this, [this] {
            if( name->text().trimmed().isEmpty() )
            {
                QMessageBox::warning( this, qtr( "Smart Playlist" ),
                                      qtr( "Give this smart playlist a name." ) );
                return;
            }
            if( rules->rowCount() == 0 ) addRule();
            accept();
        } );
        connect( buttons, &QDialogButtonBox::rejected, this, &QDialog::reject );
        outer->addWidget( buttons );

        if( !serialized.isEmpty() ) load( serialized );
        if( rules->rowCount() == 0 ) addRule();
    }

    QString serialize() const
    {
        QStringList encodedRules;
        for( int row = 0; row < rules->rowCount(); ++row )
        {
            QComboBox *field = qobject_cast<QComboBox *>( rules->cellWidget( row, 0 ) );
            QComboBox *op = qobject_cast<QComboBox *>( rules->cellWidget( row, 1 ) );
            QLineEdit *value = qobject_cast<QLineEdit *>( rules->cellWidget( row, 2 ) );
            if( !field || !op || !value ) continue;
            encodedRules << encodeField( field->currentData().toString() ) + "|"
                          + encodeField( op->currentData().toString() ) + "|"
                          + encodeField( value->text() );
        }
        return encodeField( name->text().trimmed() ) + "\t"
             + match->currentData().toString() + "\t"
             + QString::number( limit->value() ) + "\t"
             + encodedRules.join( ";" );
    }

    QString displayName() const { return name->text().trimmed(); }
    QString summary() const
    {
        return qtr( "%1 rules, match %2, limit %3" )
            .arg( rules->rowCount() )
            .arg( match->currentData().toString() == "all" ? qtr( "all" )
                                                            : qtr( "any" ) )
            .arg( limit->value() == 0 ? qtr( "none" )
                                      : QString::number( limit->value() ) );
    }

private:
    QLineEdit *name;
    QComboBox *match;
    QSpinBox *limit;
    QTableWidget *rules;

    void addRule( const QString &fieldId = "title",
                  const QString &operatorId = "contains",
                  const QString &text = QString() )
    {
        int row = rules->rowCount();
        rules->insertRow( row );
        QComboBox *field = new QComboBox;
        field->addItem( qtr( "Title" ), "title" );
        field->addItem( qtr( "Artist" ), "artist" );
        field->addItem( qtr( "Album" ), "album" );
        field->addItem( qtr( "Path" ), "path" );
        field->addItem( qtr( "Media type" ), "type" );
        field->addItem( qtr( "File size (bytes)" ), "size" );
        field->addItem( qtr( "Modified (Unix time)" ), "modified" );
        field->addItem( qtr( "Rating (0–5 stars)" ), "rating" );
        int fieldIndex = field->findData( fieldId );
        field->setCurrentIndex( fieldIndex >= 0 ? fieldIndex : 0 );

        QComboBox *op = new QComboBox;
        op->addItem( qtr( "contains" ), "contains" );
        op->addItem( qtr( "does not contain" ), "not_contains" );
        op->addItem( qtr( "is" ), "is" );
        op->addItem( qtr( "is not" ), "is_not" );
        op->addItem( qtr( "starts with" ), "starts_with" );
        op->addItem( qtr( "ends with" ), "ends_with" );
        op->addItem( qtr( "is greater than" ), "greater" );
        op->addItem( qtr( "is less than" ), "less" );
        op->addItem( qtr( "is after" ), "after" );
        op->addItem( qtr( "is before" ), "before" );
        int opIndex = op->findData( operatorId );
        op->setCurrentIndex( opIndex >= 0 ? opIndex : 0 );
        QLineEdit *value = new QLineEdit( text );
        rules->setCellWidget( row, 0, field );
        rules->setCellWidget( row, 1, op );
        rules->setCellWidget( row, 2, value );
    }

    void load( const QString &serialized )
    {
        QStringList fields = serialized.split( '\t' );
        if( fields.size() < 4 ) return;
        name->setText( decodeField( fields[0] ) );
        int matchIndex = match->findData( fields[1] );
        if( matchIndex >= 0 ) match->setCurrentIndex( matchIndex );
        limit->setValue( fields[2].toInt() );
        const QString rulesField = fields.mid( 3 ).join( "\t" );
        for( const QString &rule : rulesField.split( ';', QString::SkipEmptyParts ) )
        {
            QStringList parts = rule.split( '|' );
            if( parts.size() >= 3 )
                addRule( decodeField( parts[0] ), decodeField( parts[1] ),
                         decodeField( parts.mid( 2 ).join( "|" ) ) );
        }
    }
};

class DeviceDialog : public QDialog
{
public:
    DeviceDialog( QWidget *parent, const QString &serialized = QString() )
        : QDialog( parent ), name( new QLineEdit ), path( new QLineEdit ),
          kind( new QComboBox ), transcode( new QCheckBox ), codec( new QComboBox ),
          bitrate( new QSpinBox ), albumArtistAsComposer( new QCheckBox ),
          backup( new QLineEdit )
    {
        setWindowTitle( qtr( "Portable Player" ) );
        QVBoxLayout *outer = new QVBoxLayout( this );
        QFormLayout *form = new QFormLayout;
        form->addRow( qtr( "Name" ), name );

        QWidget *pathRow = new QWidget;
        QHBoxLayout *pathLayout = new QHBoxLayout( pathRow );
        pathLayout->setContentsMargins( 0, 0, 0, 0 );
        pathLayout->addWidget( path );
        QPushButton *browsePath = button( qtr( "Browse…" ), pathLayout );
        form->addRow( qtr( "Mount point or folder" ), pathRow );

        kind->addItem( qtr( "USB / storage player" ), "storage" );
        kind->addItem( qtr( "Apple iPod (libgpod)" ), "ipod" );
        kind->addItem( qtr( "Rockbox player" ), "rockbox" );
        form->addRow( qtr( "Device type" ), kind );
        transcode->setText( qtr( "Convert incompatible audio copies" ) );
        form->addRow( QString(), transcode );
        codec->addItem( "MP3", "mp3" );
        codec->addItem( "AAC / M4A", "aac" );
        codec->addItem( "FLAC", "flac" );
        codec->setCurrentIndex( codec->findData( "aac" ) );
        form->addRow( qtr( "Preferred audio format" ), codec );
        bitrate->setRange( 64, 512 ); bitrate->setSuffix( " kb/s" );
        bitrate->setValue( 256 );
        form->addRow( qtr( "Audio bitrate" ), bitrate );
        form->addRow( qtr( "Map Album Artist to Composer (Apple iPod)" ),
                      albumArtistAsComposer );

        outer->addLayout( form );

        connect( browsePath, &QPushButton::clicked, this, [this] {
            QString selected = QFileDialog::getExistingDirectory(
                this, qtr( "Choose Portable Player" ), path->text() );
            if( selected.isEmpty() ) return;
            path->setText( QDir::cleanPath( selected ) );
            QFileInfo rockbox( QDir( selected ).filePath( ".rockbox" ) );
            QFileInfo ipod( QDir( selected ).filePath( "iPod_Control" ) );
            const QString detected = ipod.exists() ? "ipod"
                                   : rockbox.exists() ? "rockbox" : "storage";
            kind->setCurrentIndex( kind->findData( detected ) );
            if( name->text().trimmed().isEmpty() )
                name->setText( QFileInfo( selected ).fileName() );
        } );
        connect( transcode, &QCheckBox::toggled, codec, &QWidget::setEnabled );
        connect( transcode, &QCheckBox::toggled, bitrate, &QWidget::setEnabled );
        connect( kind, static_cast<void (QComboBox::*)(int)>(
                         &QComboBox::currentIndexChanged ), this, [this] {
            albumArtistAsComposer->setEnabled(
                kind->currentData().toString() == "ipod" );
        } );

        QDialogButtonBox *buttons = new QDialogButtonBox(
            QDialogButtonBox::Ok | QDialogButtonBox::Cancel );
        connect( buttons, &QDialogButtonBox::accepted, this, [this] {
            if( name->text().trimmed().isEmpty() || path->text().trimmed().isEmpty() )
            {
                QMessageBox::warning( this, qtr( "Portable Player" ),
                    qtr( "A portable player needs a name and a folder." ) );
                return;
            }
            if( !QFileInfo( path->text() ).isDir() )
            {
                QMessageBox::warning( this, qtr( "Portable Player" ),
                                      qtr( "The selected folder is not available." ) );
                return;
            }
            accept();
        } );
        connect( buttons, &QDialogButtonBox::rejected, this, &QDialog::reject );
        outer->addWidget( buttons );

        if( !serialized.isEmpty() ) load( serialized );
        codec->setEnabled( transcode->isChecked() );
        bitrate->setEnabled( transcode->isChecked() );
        albumArtistAsComposer->setEnabled(
            kind->currentData().toString() == "ipod" );
    }

    QString serialize() const
    {
        return (QStringList()
            << encodeField( name->text().trimmed() )
            << encodeField( QDir::cleanPath( path->text().trimmed() ) )
            << encodeField( kind->currentData().toString() )
            << (transcode->isChecked() ? "1" : "0")
            << encodeField( codec->currentData().toString() )
            << QString::number( bitrate->value() )
            << (kind->currentData().toString() == "ipod"
                && albumArtistAsComposer->isChecked() ? "1" : "0")
            << "0" << "0"
            << encodeField( backup->text().trimmed() )).join( "\t" );
    }

    QString displayName() const { return name->text().trimmed(); }
    QString displayPath() const { return QDir::cleanPath( path->text().trimmed() ); }
    QString displayKind() const { return kind->currentText(); }

private:
    QLineEdit *name;
    QLineEdit *path;
    QComboBox *kind;
    QCheckBox *transcode;
    QComboBox *codec;
    QSpinBox *bitrate;
    QCheckBox *albumArtistAsComposer;
    QLineEdit *backup;

    void load( const QString &serialized )
    {
        QStringList values = serialized.split( '\t' );
        if( values.size() < 10 ) return;
        name->setText( decodeField( values[0] ) );
        path->setText( decodeField( values[1] ) );
        int kindIndex = kind->findData( decodeField( values[2] ) );
        if( kindIndex >= 0 ) kind->setCurrentIndex( kindIndex );
        transcode->setChecked( values[3].toInt() != 0 );
        const QString storedCodec = decodeField( values[4] );
        int codecIndex = codec->findData( storedCodec.isEmpty() ? "aac"
                                                                : storedCodec );
        if( codecIndex >= 0 ) codec->setCurrentIndex( codecIndex );
        const int storedBitrate = values[5].toInt();
        bitrate->setValue( storedBitrate > 0 ? storedBitrate : 256 );
        albumArtistAsComposer->setChecked( values[6].toInt() != 0 );
        backup->setText( decodeField( values.mid( 9 ).join( "\t" ) ) );
    }
};
}

PowerVLCMediaLibraryPrefs::PowerVLCMediaLibraryPrefs( intf_thread_t *intf,
                                                       QWidget *parent )
    : QWidget( parent ), p_intf( intf ), managedFolder( new QLineEdit ),
      folders( new QTreeWidget ), smartPlaylists( new QTreeWidget ),
      monitorInterval( new QSpinBox ), maximumComponent( new QSpinBox ),
      maximumPath( new QSpinBox )
{
    QVBoxLayout *outer = new QVBoxLayout( this );

    QGroupBox *managedGroup = new QGroupBox( qtr( "Managed Media Folder" ) );
    QVBoxLayout *managedLayout = new QVBoxLayout( managedGroup );
    QHBoxLayout *managedRow = new QHBoxLayout;
    managedRow->addWidget( managedFolder );
    QPushButton *browseManaged = button( qtr( "Browse…" ), managedRow );
    managedLayout->addLayout( managedRow );
    QLabel *managedHint = new QLabel( qtr(
        "Imported files are copied into Music, Movies, Shows, Podcasts or "
        "Playlists using portable, Jellyfin-compatible names." ) );
    managedHint->setWordWrap( true );
    managedLayout->addWidget( managedHint );
    outer->addWidget( managedGroup );

    QString managed = configString( VLC_OBJECT( p_intf ),
                                    "powervlc-ml-managed-folder" );
    if( managed.isEmpty() )
        managed = QDir::home().filePath( "Music/PowerVLC media library" );
    managedFolder->setText( QDir::cleanPath( managed ) );
    connect( browseManaged, &QPushButton::clicked, this, [this] {
        QString selected = QFileDialog::getExistingDirectory(
            this, qtr( "Choose Managed Media Folder" ), managedFolder->text(),
            QFileDialog::ShowDirsOnly | QFileDialog::DontResolveSymlinks );
        if( !selected.isEmpty() ) managedFolder->setText( QDir::cleanPath( selected ) );
    } );

    QGroupBox *foldersGroup = new QGroupBox( qtr( "Library Folders" ) );
    QVBoxLayout *foldersLayout = new QVBoxLayout( foldersGroup );
    prepareTree( folders, QStringList() << qtr( "Folder" )
                                       << qtr( "Monitor" )
                                       << qtr( "Shared cache" ) );
    folders->setToolTip( qtr( "Uncheck Shared cache to store this folder's "
        "database in the managed media folder. Its tracks remain visible "
        "while a network volume is offline." ) );
    foldersLayout->addWidget( folders );
    QHBoxLayout *folderButtons = new QHBoxLayout;
    QPushButton *addFolderButton = button( qtr( "Add…" ), folderButtons );
    QPushButton *editFolderButton = button( qtr( "Edit…" ), folderButtons );
    QPushButton *removeFolderButton = button( qtr( "Remove" ), folderButtons );
    folderButtons->addStretch();
    foldersLayout->addLayout( folderButtons );
    outer->addWidget( foldersGroup, 1 );
    connect( addFolderButton, &QPushButton::clicked, this,
             [this] { addFolder(); } );
    connect( editFolderButton, &QPushButton::clicked, this,
             [this] { editFolder(); } );
    connect( folders, &QTreeWidget::itemDoubleClicked, this,
             [this]( QTreeWidgetItem *, int ) { editFolder(); } );
    connect( removeFolderButton, &QPushButton::clicked, this, [this] {
        delete folders->takeTopLevelItem( folders->indexOfTopLevelItem(
                                             folders->currentItem() ) );
    } );

    const QString folderConfig = configString( VLC_OBJECT( p_intf ),
                                               "powervlc-ml-folders" );
    for( const QString &line : folderConfig.split( '\n', QString::SkipEmptyParts ) )
    {
        QStringList values = line.split( '\t' );
        if( values.size() < 2 ) continue;
        QTreeWidgetItem *item = new QTreeWidgetItem( folders );
        item->setFlags( item->flags() | Qt::ItemIsUserCheckable );
        item->setText( 0, decodeField( values.mid( 1 ).join( "\t" ) ) );
        item->setCheckState( 1, values[0].contains( 'm' ) ? Qt::Checked
                                                         : Qt::Unchecked );
        item->setCheckState( 2, values[0].contains( 'd' ) ? Qt::Checked
                                                         : Qt::Unchecked );
    }

    QGroupBox *smartGroup = new QGroupBox( qtr( "Smart Playlists" ) );
    QVBoxLayout *smartLayout = new QVBoxLayout( smartGroup );
    prepareTree( smartPlaylists, QStringList() << qtr( "Name" )
                                              << qtr( "Rules" ) );
    smartLayout->addWidget( smartPlaylists );
    QHBoxLayout *smartButtons = new QHBoxLayout;
    QPushButton *addSmart = button( qtr( "New…" ), smartButtons );
    QPushButton *editSmart = button( qtr( "Edit…" ), smartButtons );
    QPushButton *removeSmart = button( qtr( "Remove" ), smartButtons );
    smartButtons->addStretch();
    smartLayout->addLayout( smartButtons );
    outer->addWidget( smartGroup, 1 );
    connect( addSmart, &QPushButton::clicked, this,
             [this] { addSmartPlaylist(); } );
    connect( editSmart, &QPushButton::clicked, this,
             [this] { editSmartPlaylist(); } );
    connect( smartPlaylists, &QTreeWidget::itemDoubleClicked, this,
             [this]( QTreeWidgetItem *, int ) { editSmartPlaylist(); } );
    connect( removeSmart, &QPushButton::clicked, this, [this] {
        delete smartPlaylists->takeTopLevelItem(
            smartPlaylists->indexOfTopLevelItem( smartPlaylists->currentItem() ) );
    } );

    const QString smartConfig = configString( VLC_OBJECT( p_intf ),
                                              "powervlc-ml-smart-playlists" );
    for( const QString &line : smartConfig.split( '\n', QString::SkipEmptyParts ) )
    {
        QStringList values = line.split( '\t' );
        if( values.size() < 4 ) continue;
        QTreeWidgetItem *item = new QTreeWidgetItem( smartPlaylists );
        item->setText( 0, decodeField( values[0] ) );
        item->setText( 1, qtr( "%1 mode, limit %2" )
                       .arg( values[1] == "any" ? qtr( "any" ) : qtr( "all" ) )
                       .arg( values[2].toInt() == 0 ? qtr( "none" ) : values[2] ) );
        item->setData( 0, SerializedRole, line );
    }

    QGroupBox *limitsGroup = new QGroupBox( qtr( "Maintenance" ) );
    QFormLayout *limits = new QFormLayout( limitsGroup );
    monitorInterval->setRange( 15, 86400 ); monitorInterval->setSuffix( " s" );
    monitorInterval->setValue( config_GetInt( VLC_OBJECT( p_intf ),
                                              "powervlc-ml-monitor-interval" ) );
    maximumComponent->setRange( 48, 240 ); maximumComponent->setSuffix( qtr( " bytes" ) );
    maximumComponent->setValue( config_GetInt( VLC_OBJECT( p_intf ),
                                               "powervlc-ml-max-component" ) );
    maximumPath->setRange( 96, 1024 ); maximumPath->setSuffix( qtr( " bytes" ) );
    maximumPath->setValue( config_GetInt( VLC_OBJECT( p_intf ),
                                          "powervlc-ml-max-path" ) );
    limits->addRow( qtr( "Maximum idle monitoring interval (seconds)" ),
                    monitorInterval );
    limits->addRow( qtr( "Maximum file/folder name" ), maximumComponent );
    limits->addRow( qtr( "Maximum complete path" ), maximumPath );
    outer->addWidget( limitsGroup );
}

void PowerVLCMediaLibraryPrefs::addFolder()
{
    QString selected = QFileDialog::getExistingDirectory(
        this, qtr( "Add Library Folder" ), QDir::homePath() );
    if( selected.isEmpty() ) return;
    selected = QDir::cleanPath( selected );
    for( int i = 0; i < folders->topLevelItemCount(); ++i )
        if( folders->topLevelItem( i )->text( 0 ) == selected ) return;
    bool cache = true;
    if( QFileInfo( QDir( selected ).filePath( ".powervlcmediafolder.db" ) ).exists() )
        cache = QMessageBox::question( this, qtr( "Existing Media Cache" ),
            qtr( "This folder already contains a PowerVLC media cache. Use it?" ) )
                == QMessageBox::Yes;
    QTreeWidgetItem *item = new QTreeWidgetItem( folders );
    item->setFlags( item->flags() | Qt::ItemIsUserCheckable );
    item->setText( 0, selected );
    item->setCheckState( 1, Qt::Unchecked );
    item->setCheckState( 2, cache ? Qt::Checked : Qt::Unchecked );
}

void PowerVLCMediaLibraryPrefs::editFolder()
{
    QTreeWidgetItem *item = folders->currentItem();
    if( item == nullptr ) return;
    QDialog dialog( this );
    dialog.setWindowTitle( qtr( "Edit Library Folder" ) );
    QVBoxLayout *layout = new QVBoxLayout( &dialog );
    QLabel *path = new QLabel( item->text( 0 ), &dialog );
    path->setTextInteractionFlags( Qt::TextSelectableByMouse );
    layout->addWidget( path );
    QCheckBox *monitor = new QCheckBox( qtr( "Monitor this folder" ), &dialog );
    monitor->setChecked( item->checkState( 1 ) == Qt::Checked );
    layout->addWidget( monitor );
    QCheckBox *cache = new QCheckBox(
        qtr( "Use a shared cache stored in this folder" ), &dialog );
    cache->setChecked( item->checkState( 2 ) == Qt::Checked );
    layout->addWidget( cache );
    QLabel *help = new QLabel( qtr( "When Shared cache is disabled, the "
        "database is kept in the managed media folder so tracks remain "
        "visible while this folder is offline." ), &dialog );
    help->setWordWrap( true ); layout->addWidget( help );
    QDialogButtonBox *buttons = new QDialogButtonBox(
        QDialogButtonBox::Save | QDialogButtonBox::Cancel, &dialog );
    connect( buttons, &QDialogButtonBox::accepted, &dialog, &QDialog::accept );
    connect( buttons, &QDialogButtonBox::rejected, &dialog, &QDialog::reject );
    layout->addWidget( buttons );
    if( dialog.exec() != QDialog::Accepted ) return;
    item->setCheckState( 1, monitor->isChecked() ? Qt::Checked : Qt::Unchecked );
    item->setCheckState( 2, cache->isChecked() ? Qt::Checked : Qt::Unchecked );
}

void PowerVLCMediaLibraryPrefs::addSmartPlaylist()
{
    SmartPlaylistDialog dialog( this );
    if( dialog.exec() != QDialog::Accepted ) return;
    QTreeWidgetItem *item = new QTreeWidgetItem( smartPlaylists );
    item->setText( 0, dialog.displayName() );
    item->setText( 1, dialog.summary() );
    item->setData( 0, SerializedRole, dialog.serialize() );
}

void PowerVLCMediaLibraryPrefs::editSmartPlaylist()
{
    QTreeWidgetItem *item = smartPlaylists->currentItem();
    if( !item ) return;
    SmartPlaylistDialog dialog( this, item->data( 0, SerializedRole ).toString() );
    if( dialog.exec() != QDialog::Accepted ) return;
    item->setText( 0, dialog.displayName() );
    item->setText( 1, dialog.summary() );
    item->setData( 0, SerializedRole, dialog.serialize() );
}

void PowerVLCMediaLibraryPrefs::apply()
{
    const QString managed = QDir::cleanPath( managedFolder->text().trimmed() );
    bool folderConfigurationChanged = managed != configString(
        VLC_OBJECT( p_intf ), "powervlc-ml-managed-folder" );
    config_PutPsz( VLC_OBJECT( p_intf ), "powervlc-ml-managed-folder", qtu( managed ) );
    QStringList folderLines;
    for( int i = 0; i < folders->topLevelItemCount(); ++i )
    {
        QTreeWidgetItem *item = folders->topLevelItem( i );
        QString flags;
        if( item->checkState( 1 ) == Qt::Checked ) flags += 'm';
        if( item->checkState( 2 ) == Qt::Checked ) flags += 'd';
        folderLines << flags + "\t" + encodeField( item->text( 0 ) );
    }
    const QString folderConfiguration = folderLines.join( "\n" );
    folderConfigurationChanged |= folderConfiguration != configString(
        VLC_OBJECT( p_intf ), "powervlc-ml-folders" );
    config_PutPsz( VLC_OBJECT( p_intf ), "powervlc-ml-folders",
                   qtu( folderConfiguration ) );
    QStringList smartLines;
    for( int i = 0; i < smartPlaylists->topLevelItemCount(); ++i )
        smartLines << smartPlaylists->topLevelItem( i )
                         ->data( 0, SerializedRole ).toString();
    const QString smartConfiguration = smartLines.join( "\n" );
    const bool smartConfigurationChanged = smartConfiguration !=
        configString( VLC_OBJECT( p_intf ), "powervlc-ml-smart-playlists" );
    config_PutPsz( VLC_OBJECT( p_intf ), "powervlc-ml-smart-playlists",
                   qtu( smartConfiguration ) );
    config_PutInt( VLC_OBJECT( p_intf ), "powervlc-ml-monitor-interval",
                   monitorInterval->value() );
    config_PutInt( VLC_OBJECT( p_intf ), "powervlc-ml-max-component",
                   maximumComponent->value() );
    config_PutInt( VLC_OBJECT( p_intf ), "powervlc-ml-max-path",
                   maximumPath->value() );

    QDir root( managed );
    root.mkpath( "." );
    const QStringList branches = QStringList() << "Music" << "Movies"
        << "Shows" << "Podcasts" << "Playlists";
    for( const QString &branch : branches )
        root.mkpath( branch );
    if( folderConfigurationChanged
     && playlist_IsServicesDiscoveryLoaded( THEPL, "powervlc_library" ) )
        playlist_ServicesDiscoveryControl( THEPL, "powervlc_library",
                                            SD_CMD_POWERVLC_RESCAN );
    if( smartConfigurationChanged
     && playlist_IsServicesDiscoveryLoaded( THEPL, "powervlc_library" ) )
        playlist_ServicesDiscoveryControl( THEPL, "powervlc_library",
                            SD_CMD_POWERVLC_LIBRARY_RELOAD_SMART );
}

PowerVLCPortablePlayersPrefs::PowerVLCPortablePlayersPrefs( intf_thread_t *intf,
                                                            QWidget *parent )
    : QWidget( parent ), p_intf( intf ), devices( new QTreeWidget ),
      maximumComponent( new QSpinBox ), maximumPath( new QSpinBox )
{
    QVBoxLayout *outer = new QVBoxLayout( this );
    QLabel *intro = new QLabel( qtr(
        "PowerVLC keeps originals unchanged. Each player receives portable "
        "copies and an incremental .powervlcdevice.db index." ) );
    intro->setWordWrap( true ); outer->addWidget( intro );
    prepareTree( devices, QStringList() << qtr( "Player" ) << qtr( "Folder" )
                                       << qtr( "Type" ) );
    outer->addWidget( devices, 1 );
    QHBoxLayout *buttons = new QHBoxLayout;
    QPushButton *add = button( qtr( "Add…" ), buttons );
    QPushButton *edit = button( qtr( "Edit…" ), buttons );
    QPushButton *remove = button( qtr( "Remove" ), buttons );
    buttons->addStretch(); outer->addLayout( buttons );
    connect( add, &QPushButton::clicked, this, [this] { addDevice(); } );
    connect( edit, &QPushButton::clicked, this, [this] { editDevice(); } );
    connect( devices, &QTreeWidget::itemDoubleClicked, this,
             [this]( QTreeWidgetItem *, int ) { editDevice(); } );
    connect( remove, &QPushButton::clicked, this, [this] {
        delete devices->takeTopLevelItem(
            devices->indexOfTopLevelItem( devices->currentItem() ) );
        applyDevices();
    } );

    QString config = configString( VLC_OBJECT( p_intf ), "powervlc-devices" );
    config.replace( '|', '\n' );
    for( const QString &line : config.split( '\n', QString::SkipEmptyParts ) )
    {
        QStringList values = line.split( '\t' );
        if( values.size() < 10 ) continue;
        QTreeWidgetItem *item = new QTreeWidgetItem( devices );
        item->setText( 0, decodeField( values[0] ) );
        item->setText( 1, decodeField( values[1] ) );
        const QString kind = decodeField( values[2] );
        item->setText( 2, kind == "ipod" ? qtr( "Apple iPod" )
                        : kind == "rockbox" ? qtr( "Rockbox" )
                                             : qtr( "USB / storage" ) );
        item->setData( 0, SerializedRole, line );
    }

    QGroupBox *limitsGroup = new QGroupBox( qtr( "FAT32 and Legacy Player Limits" ) );
    QFormLayout *limits = new QFormLayout( limitsGroup );
    maximumComponent->setRange( 32, 240 ); maximumComponent->setSuffix( qtr( " bytes" ) );
    maximumComponent->setValue( config_GetInt( VLC_OBJECT( p_intf ),
                                               "powervlc-device-max-component" ) );
    maximumPath->setRange( 96, 1024 ); maximumPath->setSuffix( qtr( " bytes" ) );
    maximumPath->setValue( config_GetInt( VLC_OBJECT( p_intf ),
                                         "powervlc-device-max-path" ) );
    limits->addRow( qtr( "Maximum file/folder name" ), maximumComponent );
    limits->addRow( qtr( "Maximum complete path" ), maximumPath );
    outer->addWidget( limitsGroup );
}

void PowerVLCPortablePlayersPrefs::addDevice()
{
    DeviceDialog dialog( this );
    if( dialog.exec() != QDialog::Accepted ) return;
    QTreeWidgetItem *item = new QTreeWidgetItem( devices );
    item->setText( 0, dialog.displayName() );
    item->setText( 1, dialog.displayPath() );
    item->setText( 2, dialog.displayKind() );
    item->setData( 0, SerializedRole, dialog.serialize() );
    applyDevices();
}

void PowerVLCPortablePlayersPrefs::editDevice()
{
    QTreeWidgetItem *item = devices->currentItem();
    if( !item ) return;
    DeviceDialog dialog( this, item->data( 0, SerializedRole ).toString() );
    if( dialog.exec() != QDialog::Accepted ) return;
    item->setText( 0, dialog.displayName() );
    item->setText( 1, dialog.displayPath() );
    item->setText( 2, dialog.displayKind() );
    item->setData( 0, SerializedRole, dialog.serialize() );
    applyDevices();
}

void PowerVLCPortablePlayersPrefs::applyDevices()
{
    QString oldConfig = configString( VLC_OBJECT( p_intf ),
                                      "powervlc-devices" );
    oldConfig.replace( '|', '\n' );
    const QStringList oldLines = oldConfig.split( '\n',
                                                  QString::SkipEmptyParts );
    QStringList lines;
    for( int i = 0; i < devices->topLevelItemCount(); ++i )
        lines << devices->topLevelItem( i )->data( 0, SerializedRole ).toString();
    const QByteArray deviceConfig = lines.join( "|" ).toUtf8();
    config_PutPsz( VLC_OBJECT( p_intf ), "powervlc-devices",
                   deviceConfig.constData() );
    var_Create( p_intf->obj.libvlc, "powervlc-devices", VLC_VAR_STRING );
    var_SetString( p_intf->obj.libvlc, "powervlc-devices",
                   deviceConfig.constData() );
    config_SaveConfigFile( p_intf );
    for( int i = 0; i < 64; ++i )
    {
        const QString oldLine = i < oldLines.size() ? oldLines[i] : QString();
        const QString newLine = i < lines.size() ? lines[i] : QString();
        if( oldLine == newLine ) continue;
        const QByteArray chain = QString( "powervlc_device{index=%1}" )
                                     .arg( i ).toUtf8();
        if( !oldLine.isEmpty()
         && playlist_IsServicesDiscoveryLoaded( THEPL, chain.constData() ) )
            playlist_ServicesDiscoveryRemove( THEPL, chain.constData() );
        if( !newLine.isEmpty() )
            playlist_ServicesDiscoveryAdd( THEPL, chain.constData() );
    }
    if( p_intf->p_sys->p_mi )
        p_intf->p_sys->p_mi->reloadPowerDevices();
}

void PowerVLCPortablePlayersPrefs::apply()
{
    applyDevices();
    config_PutInt( VLC_OBJECT( p_intf ), "powervlc-device-max-component",
                   maximumComponent->value() );
    config_PutInt( VLC_OBJECT( p_intf ), "powervlc-device-max-path",
                   maximumPath->value() );
}
