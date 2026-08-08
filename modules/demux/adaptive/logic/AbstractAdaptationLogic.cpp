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
#include "Representationselectors.hpp"
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
 * A positive pin is a bandwidth, and only an EXACT match counts: the same
 * value identifies the same variant across playlist reloads, and an
 * adaptation set that does not carry it (the audio-only or subtitle sets
 * of a DASH stream) is left to its own logic instead of being pinned to
 * whatever happens to be nearest.
 *
 * QUALITY_LOWEST/HIGHEST mean the same as the "lowest"/"highest" values of
 * "adaptive-logic", and go through the same selector so that they keep
 * obeying the maximum device resolution -- but they can be switched while
 * a stream plays, and they apply to whatever plays next.
 *
 * "adaptive-maxheight" is the resolution ceiling, a standing preference of
 * the machine rather than a choice about this stream: the best variant
 * that stays under it, from the first segment on, which is what an old
 * machine wants and what the bottom of the ladder (a 144p nobody wants to
 * watch) is not. It outranks the automatic logic and the two standing
 * modes above -- but NOT a variant the user pinned by hand, which is a
 * deliberate act about this one stream and would otherwise be impossible
 * to obtain while the ceiling is on. */
BaseRepresentation *
AbstractAdaptationLogic::getRepresentation(BaseAdaptationSet *adaptSet,
                                           BaseRepresentation *prevRep)
{
    if(adaptSet && p_obj)
    {
        const int64_t forced = var_InheritInteger(p_obj, "adaptive-quality");
        BaseRepresentation *rep = nullptr;

        if(forced > 0) /* a variant, picked by hand: it wins */
        {
            for(BaseRepresentation *candidate : adaptSet->getRepresentations())
            {
                if(candidate->getBandwidth() == (uint64_t) forced)
                    return candidate;
            }
        }

        /* A ceiling can only be honoured by a playlist that says how big
         * its variants are, and plenty do not (Pluto TV carries bandwidths
         * alone). Applying it there would let every variant through and
         * hand back the biggest -- the opposite of what was asked -- so
         * those streams are left to the choice below. */
        const int64_t i_ceiling = var_InheritInteger(p_obj, "adaptive-maxheight");
        bool b_sized = false;
        if(i_ceiling > 0)
        {
            for(BaseRepresentation *candidate : adaptSet->getRepresentations())
                b_sized |= (candidate->getHeight() > 0);
        }

        if(b_sized)
        {
            const int i_cap = (int) i_ceiling;
            RepresentationSelector selector(maxwidth,
                    (maxheight < i_cap) ? maxheight : i_cap);
            rep = (forced == QUALITY_LOWEST) ? selector.lowest(adaptSet)
                                             : selector.select(adaptSet);
            if(rep)
                return rep;
        }

        if(forced == QUALITY_LOWEST || forced == QUALITY_HIGHEST)
        {
            RepresentationSelector selector(maxwidth, maxheight);
            rep = (forced == QUALITY_LOWEST) ? selector.lowest(adaptSet)
                                             : selector.highest(adaptSet);
            if(rep)
                return rep;
        }
    }
    return getNextRepresentation(adaptSet, prevRep);
}
