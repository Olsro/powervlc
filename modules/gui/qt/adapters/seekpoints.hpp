/*****************************************************************************
 * seekpoints.hpp : Chapters & Bookmarks (menu)
 *****************************************************************************
 * Copyright © 2011 the VideoLAN team
 *
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

#ifndef SEEKPOINTS_HPP
#define SEEKPOINTS_HPP

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_interface.h>
#include <vlc_input.h>

#include <QObject>
#include <QList>
#include <QMutex>
#include <QString>

class SeekPoint
{
public:
    /* i_index est le numéro affiché du chapitre (1 pour le premier) : beaucoup
     * de disques et de conteneurs numérotent leurs chapitres sans les nommer,
     * et le survol de la barre n'avait alors rien à montrer. Même repli que le
     * menu Chapitre du cœur (src/input/var.c), y compris le test de la chaîne
     * VIDE, et même chaîne de catalogue — donc déjà traduite partout. */
    SeekPoint( seekpoint_t *seekpoint, int i_index = 0 )
    {
        time = seekpoint->i_time_offset;
        if( seekpoint->psz_name != NULL && *seekpoint->psz_name != '\0' )
            name = QString::fromUtf8( seekpoint->psz_name );
        else if( i_index > 0 )
            /* pas `qtr` ici : il vient de qt.hpp, que cet en-tête n'inclut
             * pas (et n'a pas à inclure). N_() garde la chaîne extractible. */
            name = QString::fromUtf8( vlc_gettext( N_("Chapter %i") ) )
                       .replace( "%i", QString::number( i_index ) );
    };
    int64_t time;
    QString name;
};

class SeekPoints : public QObject
{
    Q_OBJECT
public:
    SeekPoints( QObject *, intf_thread_t * );
    QList<SeekPoint> const getPoints();
    bool access() { return listMutex.tryLock( 100 ); }
    void release() { listMutex.unlock(); }
    bool jumpTo( int );

public slots:
    void update();

private:
    QList<SeekPoint> pointsList;
    QMutex listMutex;
    intf_thread_t *p_intf;
};

#endif // SEEKPOINTS_HPP
