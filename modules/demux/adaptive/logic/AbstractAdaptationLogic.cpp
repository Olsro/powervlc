/*
 * AbstractAdaptationLogic.cpp
 *****************************************************************************
 * Copyright (C) 2010 - 2011 Klagenfurt University
 *
 * Created on: Aug 10, 2010
 * Authors: Christopher Mueller <christopher.mueller@itec.uni-klu.ac.at>
 *          Christian Timmerer  <christian.timmerer@itec.uni-klu.ac.at>
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published
 * by the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/
#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include "AbstractAdaptationLogic.h"
#include "../playlist/BaseAdaptationSet.h"
#include "../playlist/BaseRepresentation.h"

#include <limits>

using namespace adaptive::logic;

AbstractAdaptationLogic::AbstractAdaptationLogic    (vlc_object_t *obj)
{
    p_obj = obj;
    maxwidth = std::numeric_limits<int>::max();
    maxheight = std::numeric_limits<int>::max();
}

void AbstractAdaptationLogic::updateDownloadRate    (const adaptive::ID &, size_t,
                                                     mtime_t, mtime_t)
{
}

void AbstractAdaptationLogic::setMaxDeviceResolution (int w, int h)
{
    maxwidth = (w > 0) ? w : std::numeric_limits<int>::max();
    maxheight = (h > 0) ? h : std::numeric_limits<int>::max();
}

/* PowerVLC: the quality the user pinned, if any.
 *
 * Read from the object tree on every call rather than cached: the
 * variable lives on the input thread (where the interfaces can reach it,
 * see PlaylistManager::exportQualities) while the choice is applied here,
 * on the manager thread. Going through the variable API means no lock and
 * no lifetime rule of our own -- and a live playlist may be reloaded, or
 * replaced period by period, under our feet at any time.
 *
 * The pin is a bandwidth, and only an EXACT match counts: the same value
 * identifies the same variant across playlist reloads, and an adaptation
 * set that does not carry it (the audio-only or subtitle sets of a DASH
 * stream) is left to its own logic instead of being pinned to whatever
 * happens to be nearest. */
BaseRepresentation *
AbstractAdaptationLogic::getRepresentation(BaseAdaptationSet *adaptSet,
                                           BaseRepresentation *prevRep)
{
    if(adaptSet && p_obj)
    {
        const int64_t forced = var_InheritInteger(p_obj, "adaptive-quality");
        if(forced > 0)
        {
            const std::vector<BaseRepresentation *> &reps = adaptSet->getRepresentations();
            for(BaseRepresentation *rep : reps)
            {
                if(rep->getBandwidth() == (uint64_t) forced)
                    return rep;
            }
        }
    }
    return getNextRepresentation(adaptSet, prevRep);
}
