/*****************************************************************************
 * bluray_keydb.c: find a disc's main playlist in the user's AACS key database
 *****************************************************************************
 * Copyright (C) 2026 PowerVLC
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <vlc_common.h>
#include <vlc_arrays.h>
#include <vlc_configuration.h>
#include <vlc_fs.h>

#include <ctype.h>

#include "bluray_keydb.h"

/* Long enough for every line of a FindVUK database (the longest measured is
 * under 1700 bytes). Overlong lines are not truncated into a bogus match: the
 * remainder is drained and the line skipped, see _read_line(). */
#define KEYDB_LINE_MAX 4096

/* An entry looks like
 *   0x<40 hex digits> = <title> | D | ... ; <comment>
 * and the playlist, when present, lives in the comment as
 *   MainPlaylist: NNNNN.mpls
 * The marker is matched case-insensitively; the '0x' prefix and the id are
 * too, because databases from different tools disagree on the case of the hex.
 */
#define KEYDB_MAIN_PLAYLIST_MARKER "mainplaylist:"

/**
 * Read one line into buf, without its newline.
 *
 * @return true on success, false at end of file. *pb_partial is set when the
 *         line did not fit and had to be drained -- the caller must ignore the
 *         contents rather than match a truncated line.
 */
static bool _read_line(FILE *f, char *buf, size_t i_size, bool *pb_partial)
{
    *pb_partial = false;

    if (fgets(buf, i_size, f) == NULL)
        return false;

    size_t i_len = strlen(buf);
    if (i_len > 0 && buf[i_len - 1] == '\n') {
        buf[i_len - 1] = '\0';
        return true;
    }

    /* No newline: either the last line of the file, or a line longer than the
     * buffer. Drain the rest so the next call starts on a line boundary. */
    int c;
    while ((c = fgetc(f)) != EOF && c != '\n')
        *pb_partial = true;

    return true;
}

/**
 * Case-insensitive search for a marker, then for "NNNNN.mpls" after it.
 *
 * @return the playlist number, or BLURAY_KEYDB_NO_PLAYLIST.
 */
static int _parse_main_playlist(const char *psz_line)
{
    const size_t i_marker = strlen(KEYDB_MAIN_PLAYLIST_MARKER);
    const char *p = psz_line;

    for (; *p != '\0'; p++) {
        if (strncasecmp(p, KEYDB_MAIN_PLAYLIST_MARKER, i_marker) != 0)
            continue;

        p += i_marker;
        while (*p == ' ' || *p == '\t')
            p++;

        /* Exactly the five digits of an .mpls file name, nothing else: a
         * shorter or longer run is not a playlist reference and must not be
         * rounded into one. */
        unsigned int i_playlist = 0;
        int i_digits = 0;
        while (isdigit((unsigned char)*p)) {
            i_playlist = i_playlist * 10 + (unsigned int)(*p - '0');
            i_digits++;
            p++;
        }

        if (i_digits == 5 && strncasecmp(p, ".mpls", 5) == 0)
            return (int)i_playlist;

        /* Malformed marker: keep looking, the line may carry another one. */
    }

    return BLURAY_KEYDB_NO_PLAYLIST;
}

/**
 * Scan one key database for the disc.
 *
 * @param pb_opened set when the file existed and was read to the end, so the
 *        caller can stop instead of scanning the same tens of megabytes again
 *        under the other spelling of the name -- which on a case-insensitive
 *        filesystem is the very same file.
 */
static int _scan_file(vlc_object_t *obj, const char *psz_path,
                      const char *psz_hex_id, bool *pb_opened)
{
    *pb_opened = false;

    FILE *f = vlc_fopen(psz_path, "rb");
    if (f == NULL)
        return BLURAY_KEYDB_NO_PLAYLIST;

    *pb_opened = true;

    msg_Dbg(obj, "looking up the main playlist in %s", psz_path);

    char *psz_line = malloc(KEYDB_LINE_MAX);
    if (unlikely(psz_line == NULL)) {
        fclose(f);
        return BLURAY_KEYDB_NO_PLAYLIST;
    }

    int i_playlist = BLURAY_KEYDB_NO_PLAYLIST;
    bool b_partial;

    while (_read_line(f, psz_line, KEYDB_LINE_MAX, &b_partial)) {
        /* Cheapest possible rejection first: these files run to tens of
         * megabytes and all but one line is uninteresting. */
        if (psz_line[0] != '0' || (psz_line[1] != 'x' && psz_line[1] != 'X'))
            continue;
        if (strncasecmp(psz_line + 2, psz_hex_id, 40) != 0)
            continue;
        if (b_partial)
            continue;

        int i_found = _parse_main_playlist(psz_line);
        if (i_found != BLURAY_KEYDB_NO_PLAYLIST) {
            i_playlist = i_found;
            break;
        }
        /* Same disc id can appear several times (one entry per VID); only
         * some of them carry the comment. Keep scanning. */
    }

    free(psz_line);
    fclose(f);

    return i_playlist;
}

int bluray_KeydbFindMainPlaylist(vlc_object_t *obj, const uint8_t *p_disc_id)
{
    if (p_disc_id == NULL)
        return BLURAY_KEYDB_NO_PLAYLIST;

    char psz_hex_id[41];
    for (int i = 0; i < 20; i++)
        snprintf(psz_hex_id + i * 2, 3, "%02X", p_disc_id[i]);

    char *psz_dir = config_GetDiscLibDir("aacs");
    if (psz_dir == NULL)
        return BLURAY_KEYDB_NO_PLAYLIST;

    /* libaacs opens "KEYDB.cfg", and the importer writes that name too. A database
     * dropped in by hand is often lowercase, which is indistinguishable on
     * macOS and Windows but not on a case-sensitive filesystem, so try both
     * rather than silently ignoring it there. */
    static const char *const ppsz_names[] = { "KEYDB.cfg", "keydb.cfg" };

    int i_playlist = BLURAY_KEYDB_NO_PLAYLIST;

    for (size_t i = 0; i < ARRAY_SIZE(ppsz_names); i++) {
        char *psz_path;
        if (asprintf(&psz_path, "%s"DIR_SEP"%s", psz_dir, ppsz_names[i]) < 0)
            break;

        bool b_opened;
        i_playlist = _scan_file(obj, psz_path, psz_hex_id, &b_opened);
        free(psz_path);

        if (b_opened)
            break;
    }

    free(psz_dir);

    return i_playlist;
}
