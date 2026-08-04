/*****************************************************************************
 * radiobrowser.c: random station picker for the Radio-Browser.info directory
 *****************************************************************************
 * Copyright © 2026 the PowerVLC team
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

/*****************************************************************************
 * The radiobrowser service discovery (share/lua/sd/radiobrowser.lua) offers a
 * "play a random station" entry at the top of every list it builds.  Such an
 * entry cannot be a plain API URL handed to the playlist demuxer:
 *
 *  - the core resolves a playlist entry once and for all.  The station it
 *    yields becomes a child of the entry, and every later activation plays
 *    that child again instead of asking for a new station.
 *  - the API mirrors cache their replies, so the very same "order=random"
 *    query keeps handing out the same station anyway.
 *
 * Both problems go away at the access layer: "radiobrowser://" resolves the
 * query afresh at every activation, with a parameter that defeats the mirror
 * caches, and hands the station over as an access redirection.  The playlist
 * entry therefore stays a leaf and is asked again at the next press.
 *
 * Supported locations:
 *   radiobrowser://random                     any station of the database
 *   radiobrowser://random/cc/FR               any station of one country
 *   radiobrowser://random/in/AD:8,AL:48,...   any station of a set of
 *                                             countries, each drawn with a
 *                                             probability proportional to its
 *                                             station count (this is how the
 *                                             continents, which the API knows
 *                                             nothing about, are handled)
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <stdlib.h>
#include <string.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_access.h>
#include <vlc_input.h>
#include <vlc_input_item.h>
#include <vlc_stream.h>
#include <vlc_rand.h>

#define API_BASE "https://all.api.radio-browser.info"

/* The separator input_item_CombineCuratedTitle() (src/input/item.c) puts
 * between the name an entry was given and the title the stream announces.
 * Reused here so that a drawn station reads
 * "Play a random station (Europe) ||| Radio Nova ||| <what ICY says>". */
#define SEP " ||| "

/* Info category the station details are filed under, in the "Codec details"
 * tree of the media information window. */
#define INFO_CATEGORY "Radio-Browser.info"

/* Every query below asks for a single station: a bigger reply means the
 * mirror is serving something else entirely. */
#define REPLY_MAX (256 * 1024)
#define CHUNK 16384

/* "all.api.radio-browser.info" is the round-robin DNS entry over the live
 * mirrors, and a mirror may be down: each new connection usually lands on
 * another one, so simply retry as the API documentation recommends.  The
 * search endpoint is the expensive one and mirrors do answer 502/503 on it
 * in bursts (one try in six succeeded while this was being written), hence
 * the generous count: a rejection costs one round-trip, not a timeout. */
#define ATTEMPTS 6

static int Open(vlc_object_t *);

vlc_module_begin()
    set_shortname("Radio-Browser")
    set_description(N_("Radio-Browser.info random station picker"))
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_ACCESS)
    set_capability("access", 0)
    add_shortcut("radiobrowser")
    set_callbacks(Open, NULL)
vlc_module_end()

/*****************************************************************************
 * Reads a whole (small) API reply into a NUL-terminated buffer.
 *
 * The access is opened bare, on purpose: vlc_stream_NewURL() ends with
 * stream_FilterAutoNew(), and share/lua/playlist/radiobrowser.lua probes
 * exactly the URLs queried here.  It would attach itself to the reply and
 * turn it into a directory stream, out of which not a single byte can be
 * read.  vlc_stream_Read() copes with a filterless access by itself, both
 * for pf_read and for the pf_block that the HTTP access provides.
 *****************************************************************************/
static char *Fetch(vlc_object_t *obj, const char *url)
{
    stream_t *s = vlc_access_NewMRL(obj, url);
    if (s == NULL)
        return NULL;

    char *buf = NULL;
    size_t len = 0;

    for (;;)
    {
        char *grown = realloc(buf, len + CHUNK + 1);
        if (unlikely(grown == NULL))
        {
            free(buf);
            buf = NULL;
            break;
        }
        buf = grown;

        ssize_t val = vlc_stream_Read(s, buf + len, CHUNK);
        if (val <= 0)
            break;

        len += val;
        if (len > REPLY_MAX)
        {
            msg_Warn(obj, "oversized reply from %s", url);
            free(buf);
            buf = NULL;
            break;
        }
    }

    vlc_stream_Delete(s);

    if (buf == NULL)
        return NULL;

    if (len == 0)
    {
        free(buf);
        return NULL;
    }

    buf[len] = '\0';
    return buf;
}

/*****************************************************************************
 * Copies the value of the first occurrence of an XML attribute, resolving
 * the entities the API escapes the URLs with (&amp; mostly).
 *****************************************************************************/
static char *AttributeDup(const char *xml, const char *name)
{
    char needle[32];

    if ((size_t)snprintf(needle, sizeof (needle), " %s=\"", name)
                                                       >= sizeof (needle))
        return NULL;

    const char *p = strstr(xml, needle);
    if (p == NULL)
        return NULL;
    p += strlen(needle);

    /* An escaped quote is written "&quot;": the first raw one closes the
     * attribute. */
    const char *end = strchr(p, '"');
    if (end == NULL)
        return NULL;

    char *out = malloc(end - p + 1);
    if (unlikely(out == NULL))
        return NULL;

    char *o = out;
    while (p < end)
    {
        const char *semi = (*p == '&') ? memchr(p, ';', end - p) : NULL;
        if (semi == NULL)
        {
            *(o++) = *(p++);
            continue;
        }

        const char *ent = p + 1;
        size_t entlen = semi - ent;
        unsigned long cp = 0;

        if (entlen == 3 && !memcmp(ent, "amp", 3))
            cp = '&';
        else if (entlen == 2 && !memcmp(ent, "lt", 2))
            cp = '<';
        else if (entlen == 2 && !memcmp(ent, "gt", 2))
            cp = '>';
        else if (entlen == 4 && !memcmp(ent, "quot", 4))
            cp = '"';
        else if (entlen == 4 && !memcmp(ent, "apos", 4))
            cp = '\'';
        else if (entlen > 1 && ent[0] == '#')
            cp = (ent[1] == 'x' || ent[1] == 'X')
                 ? strtoul(ent + 2, NULL, 16) : strtoul(ent + 1, NULL, 10);

        if (cp > 0 && cp < 0x80)
        {
            *(o++) = (char)cp;
            p = semi + 1;
        }
        else
        {   /* Not something we know how to fold into a URL: keep it as it
             * came rather than mangle the address. */
            memcpy(o, p, semi - p + 1);
            o += semi - p + 1;
            p = semi + 1;
        }
    }
    *o = '\0';

    if (*out == '\0')
    {
        free(out);
        return NULL;
    }
    return out;
}

/*****************************************************************************
 * Hands what the API says about the drawn station over to the input item.
 *
 * The entry keeps its "radiobrowser://" URI for ever -- that is precisely
 * what lets it be drawn again at the next press -- so without this nothing
 * downstream could tell which station is playing, and the address of a
 * stream worth keeping would be lost the moment the next one is drawn.
 *
 * The name is rebuilt rather than appended to: whatever a previous press
 * left behind is cut off at the first separator, so the entry reads
 * "<what the service discovery named it> ||| <station>", to which
 * input_item_CombineCuratedTitle() appends the ICY title once the stream
 * announces one.  The title meta is reset along with it, or the ICY suffix
 * of the previous station would linger over this one.
 *****************************************************************************/
static void Publish(stream_t *access, const char *xml, const char *url)
{
    input_item_t *item = (access->p_input != NULL)
                       ? input_GetItem(access->p_input) : NULL;
    if (item == NULL)
        return;

    char *name = AttributeDup(xml, "name");
    char *entry = input_item_GetName(item);

    if (name != NULL && entry != NULL)
    {
        char *previous = strstr(entry, SEP);
        if (previous != NULL)
            *previous = '\0';

        char *combined;
        if (likely(asprintf(&combined, "%s" SEP "%s", entry, name) != -1))
        {
            input_item_SetName(item, combined);
            input_item_SetMeta(item, vlc_meta_Title, combined);
            free(combined);
        }
    }
    free(entry);

    /* The media information window shows no URL field of its own, so the
     * address also goes into the description, where it can be read and
     * copied without digging into the details tree. */
    input_item_SetURL(item, url);
    input_item_SetDescription(item, url);
    input_item_AddInfo(item, INFO_CATEGORY, _("Stream URL"), "%s", url);

    if (name != NULL)
        input_item_AddInfo(item, INFO_CATEGORY, _("Station"), "%s", name);
    free(name);

    char *value = AttributeDup(xml, "homepage");
    if (value != NULL)
    {
        input_item_SetPublisher(item, value);
        input_item_AddInfo(item, INFO_CATEGORY, _("Homepage"), "%s", value);
        free(value);
    }

    value = AttributeDup(xml, "country");
    if (value != NULL)
    {
        /* not _("Country"): that message is the music genre everywhere but
         * in English ("Kantri", "Country music"...) */
        input_item_AddInfo(item, INFO_CATEGORY,
                           vlc_pgettext("Radio station", "Country"),
                           "%s", value);
        free(value);
    }

    value = AttributeDup(xml, "language");
    if (value != NULL)
    {
        input_item_SetLanguage(item, value);
        free(value);
    }

    value = AttributeDup(xml, "tags");
    if (value != NULL)
    {
        input_item_SetGenre(item, value);
        free(value);
    }

    value = AttributeDup(xml, "codec");
    if (value != NULL)
    {
        input_item_AddInfo(item, INFO_CATEGORY, _("Codec"), "%s", value);
        free(value);
    }

    value = AttributeDup(xml, "bitrate");
    if (value != NULL)
    {
        long bitrate = strtol(value, NULL, 10);

        if (bitrate > 0)
            input_item_AddInfo(item, INFO_CATEGORY, _("Bitrate"),
                               "%ld kb/s", bitrate);
        free(value);
    }
}

/*****************************************************************************
 * Draws one country out of a "CC:stationcount,CC:stationcount..." list, each
 * with a probability proportional to its station count.  Weighted reservoir
 * sampling: a single pass, no allocation, and the whole list is honoured
 * whatever its length.
 *****************************************************************************/
static bool PickCountry(const char *list, char code[3])
{
    unsigned long total = 0;
    bool picked = false;
    const char *p = list;

    while (p[0] >= 'A' && p[0] <= 'Z' && p[1] >= 'A' && p[1] <= 'Z')
    {
        char current[3] = { p[0], p[1], '\0' };
        unsigned long weight = 1;

        p += 2;
        if (*p == ':')
        {
            char *end;

            weight = strtoul(p + 1, &end, 10);
            p = end;
        }

        if (weight > 0)
        {
            total += weight;
            if ((unsigned long)vlc_lrand48() % total < weight)
            {
                memcpy(code, current, sizeof (current));
                picked = true;
            }
        }

        if (*p != ',')
            break;
        p++;
    }

    return picked;
}

/*****************************************************************************
 * Open: pick a station and redirect to it
 *****************************************************************************/
static int Open(vlc_object_t *obj)
{
    stream_t *access = (stream_t *)obj;
    const char *location = access->psz_location;
    char filter[32] = "";

    if (location == NULL)
        return VLC_EGENERIC;

    if (!strcmp(location, "random"))
        ; /* the whole database */
    else if (!strncmp(location, "random/cc/", 10))
    {
        const char *cc = location + 10;

        if (cc[0] < 'A' || cc[0] > 'Z' || cc[1] < 'A' || cc[1] > 'Z'
         || cc[2] != '\0')
        {
            msg_Err(access, "invalid country code in \"%s\"", location);
            return VLC_EGENERIC;
        }
        snprintf(filter, sizeof (filter), "&countrycode=%s", cc);
    }
    else if (!strncmp(location, "random/in/", 10))
    {
        char code[3];

        if (!PickCountry(location + 10, code))
        {
            msg_Err(access, "no country to draw from in \"%s\"", location);
            return VLC_EGENERIC;
        }
        snprintf(filter, sizeof (filter), "&countrycode=%s", code);
    }
    else
    {
        msg_Err(access, "unsupported location \"%s\"", location);
        return VLC_EGENERIC;
    }

    for (unsigned attempt = 0; attempt < ATTEMPTS; attempt++)
    {
        char *url;

        /* "rnd" is never read by the API: it is there so that the mirror
         * caches cannot answer twice in a row with the same station. */
        if (asprintf(&url, API_BASE "/xml/stations/search"
                     "?hidebroken=true&order=random&limit=1&rnd=%08lx%s",
                     (unsigned long)vlc_lrand48(), filter) == -1)
            return VLC_ENOMEM;

        char *xml = Fetch(obj, url);
        free(url);

        if (xml == NULL)
            continue;

        /* "url_resolved" is the stream the API itself reached by following
         * whatever redirection or playlist the station advertises: preferring
         * it keeps the redirection below a plain audio stream, which is what
         * lets the playlist entry stay a leaf. */
        char *station = AttributeDup(xml, "url_resolved");
        if (station == NULL)
            station = AttributeDup(xml, "url");

        if (station == NULL)
        {
            free(xml);
            continue;
        }

        msg_Dbg(access, "random station: %s", station);
        Publish(access, xml, station);
        free(xml);

        /* The core keeps and releases the URL we replace. */
        access->psz_url = station;
        return VLC_ACCESS_REDIRECT;
    }

    msg_Err(access, "no station could be drawn from " API_BASE);
    return VLC_EGENERIC;
}
