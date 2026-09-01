/*****************************************************************************
 * powervlc_media_preferences.hpp: PowerVLC media and device preferences
 *****************************************************************************/

#ifndef VLC_QT_POWERVLC_MEDIA_PREFERENCES_HPP_
#define VLC_QT_POWERVLC_MEDIA_PREFERENCES_HPP_

#include <QWidget>

class QLineEdit;
class QSpinBox;
class QTreeWidget;
struct intf_thread_t;

class PowerVLCMediaLibraryPrefs : public QWidget
{
public:
    explicit PowerVLCMediaLibraryPrefs( intf_thread_t *, QWidget * = nullptr );
    void apply();

private:
    intf_thread_t *p_intf;
    QLineEdit *managedFolder;
    QTreeWidget *folders;
    QTreeWidget *smartPlaylists;
    QSpinBox *monitorInterval;
    QSpinBox *maximumComponent;
    QSpinBox *maximumPath;

    void addFolder();
    void editFolder();
    void addSmartPlaylist();
    void editSmartPlaylist();
};

class PowerVLCPortablePlayersPrefs : public QWidget
{
public:
    explicit PowerVLCPortablePlayersPrefs( intf_thread_t *, QWidget * = nullptr );
    void apply();

private:
    intf_thread_t *p_intf;
    QTreeWidget *devices;
    QSpinBox *maximumComponent;
    QSpinBox *maximumPath;

    void addDevice();
    void editDevice();
    void applyDevices();
};

#endif
