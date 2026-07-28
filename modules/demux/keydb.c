/*****************************************************************************
 * keydb.c: AACS key database (KEYDB.cfg) importer
 *****************************************************************************
 * Copyright (C) 2026 Olsro
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
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

/*****************************************************************************
 * A key database is not media, so opening one used to be a dead end: the
 * player probed every demuxer, found nothing and reported a broken file. Yet
 * dropping keydb.cfg on the player is exactly what a user who just downloaded
 * one tries to do, because the place it actually belongs to is an invisible
 * directory nobody should have to know about.
 *
 * So claim the file, offer to install it where libaacs looks for it, and play
 * nothing. libaacs reads <config home>/aacs/KEYDB.cfg (keydbcfg.c); the
 * directory is what config_GetDiscLibDir() answers, so that this importer and
 * the "Open the libaacs folder" item of every interface's Help menu can never
 * end up pointing at two different places.
 *
 * The name is spelled KEYDB.cfg on the way out even when the imported file is
 * lowercase: only case-insensitive filesystems would forgive us otherwise.
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

#include <errno.h>
#include <sys/stat.h>

#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_demux.h>
#include <vlc_dialog.h>
#include <vlc_fs.h>

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
static int  Open (vlc_object_t *);
static void Close(vlc_object_t *);

/* Probed before every other demuxer: the filename test below rejects
 * everything else in a handful of instructions, and nothing may claim a key
 * database before we get the chance to import it. */
vlc_module_begin()
    set_shortname(N_("AACS keys"))
    set_description(N_("AACS key database importer"))
    set_category(CAT_INPUT)
    set_subcategory(SUBCAT_INPUT_DEMUX)
    set_capability("demux", 300)
    set_callbacks(Open, Close)
    add_shortcut("keydb")
vlc_module_end()

/* The largest key database we accept. Real ones are a few megabytes; this is
 * only here so that a file misnamed keydb.cfg cannot be copied endlessly. */
#define KEYDB_MAX_SIZE (64 * 1024 * 1024)

#define KEYDB_SNIFF_SIZE 4096

/*****************************************************************************
 * Detection
 *****************************************************************************/

/* Last path component of the URL or of the local path, whichever we have. */
static const char *BaseName(demux_t *p_demux)
{
    const char *psz_path = p_demux->psz_file ? p_demux->psz_file
                                             : p_demux->psz_location;
    if (psz_path == NULL)
        return NULL;

    for (const char *p = psz_path + strlen(psz_path); p > psz_path; p--)
        if (p[-1] == '/' || p[-1] == '\\')
            return p;

    return psz_path;
}

static bool HasKeydbName(demux_t *p_demux)
{
    const char *psz_name = BaseName(p_demux);

    return psz_name != NULL && !strcasecmp(psz_name, "keydb.cfg");
}

/* A key database is a text file. Checking that much keeps us from offering to
 * import, say, a renamed video, without trying to out-guess the many
 * hand-edited databases in the wild (libaacs itself is the one to judge the
 * contents, and it skips what it does not understand). */
static bool LooksLikeText(stream_t *s)
{
    const uint8_t *p_peek;
    ssize_t i_peek = vlc_stream_Peek(s, &p_peek, KEYDB_SNIFF_SIZE);

    if (i_peek <= 0)
        return false;

    return memchr(p_peek, '\0', i_peek) == NULL;
}

/*****************************************************************************
 * Import
 *****************************************************************************/

/* <config home>/aacs and <config home>/aacs/KEYDB.cfg, i.e. the directory
 * libaacs reads its key database from and the database itself. The directory
 * itself comes from the core: the Help menu of every interface opens the very
 * same one, and the two must never disagree. */
static int KeydbPaths(char **ppsz_dir, char **ppsz_file)
{
    char *psz_dir = config_GetDiscLibDir("aacs");
    if (psz_dir == NULL)
        return VLC_EGENERIC;

    char *psz_file;
    if (asprintf(&psz_file, "%s"DIR_SEP"KEYDB.cfg", psz_dir) < 0) {
        free(psz_dir);
        return VLC_ENOMEM;
    }

    *ppsz_dir = psz_dir;
    *ppsz_file = psz_file;
    return VLC_SUCCESS;
}

/* vlc_mkdir() only creates the last level, and none of the parents are
 * guaranteed: a fresh account has no ~/.config, and libvlccore keeps its own
 * recursive helper (config_CreateDir) private to the core. */
static int MakeDirs(const char *psz_dir)
{
    char *psz = strdup(psz_dir);
    if (psz == NULL) {
        errno = ENOMEM;
        return VLC_EGENERIC;
    }

    /* Never try to create a root: "/" on UNIX, "C:\" on Windows. */
    char *p = psz;
    if (((p[0] >= 'a' && p[0] <= 'z') || (p[0] >= 'A' && p[0] <= 'Z'))
     && p[1] == ':')
        p += 2;
    while (*p == '/' || *p == '\\')
        p++;

    int ret = VLC_EGENERIC;
    for (;; p++) {
        if (*p != '\0' && *p != '/' && *p != '\\')
            continue;

        const char c = *p;
        *p = '\0';

        errno = 0;
        const bool b_failed = *psz != '\0'
                           && vlc_mkdir(psz, 0700) != 0 && errno != EEXIST;
        *p = c;

        if (b_failed)
            break;
        if (c == '\0') {
            ret = VLC_SUCCESS;
            break;
        }
    }

    const int i_errno = errno;
    free(psz);
    errno = i_errno;
    return ret;
}

/* Copies the stream to psz_dst, atomically: a database half-written over a
 * working one would break playback of every disc, not just the new one. */
static int CopyStream(demux_t *p_demux, const char *psz_dst)
{
    stream_t *s = p_demux->s;
    char *psz_tmp;

    if (vlc_stream_Seek(s, 0) != VLC_SUCCESS) {
        errno = EIO;
        return VLC_EGENERIC;
    }

    if (asprintf(&psz_tmp, "%s.tmp", psz_dst) < 0) {
        errno = ENOMEM;
        return VLC_EGENERIC;
    }

    int ret = VLC_EGENERIC;
    FILE *file = vlc_fopen(psz_tmp, "wb");
    if (file == NULL)
        goto out;

    uint64_t i_total = 0;
    for (;;) {
        char buf[16384];
        ssize_t i_read = vlc_stream_Read(s, buf, sizeof (buf));

        if (i_read < 0) {
            errno = EIO;
            goto close;
        }
        if (i_read == 0)
            break;

        i_total += i_read;
        if (i_total > KEYDB_MAX_SIZE) {
            errno = EFBIG;
            goto close;
        }
        if (fwrite(buf, 1, i_read, file) != (size_t)i_read)
            goto close;
    }

    if (i_total == 0) {
        errno = EINVAL;
        goto close;
    }

    if (fclose(file) != 0) {
        file = NULL;
        goto close;
    }
    file = NULL;

    if (vlc_rename(psz_tmp, psz_dst) != 0)
        goto close;

    msg_Info(p_demux, "imported %"PRIu64" bytes of AACS keys into %s",
             i_total, psz_dst);
    ret = VLC_SUCCESS;

close:
    if (file != NULL)
        fclose(file);
    if (ret != VLC_SUCCESS)
        vlc_unlink(psz_tmp);
out:
    free(psz_tmp);
    return ret;
}

/* Single-button popup: the question dialog is the only interface-agnostic way
 * to get a modal notification in front of the user. */
static void Notify(demux_t *p_demux, vlc_dialog_question_type type,
                   const char *psz_title, const char *psz_text)
{
    vlc_dialog_wait_question(p_demux, type, _("OK"), NULL, NULL,
                             psz_title, "%s", psz_text);
}

static void Import(demux_t *p_demux)
{
    char *psz_dir, *psz_dst;

    if (KeydbPaths(&psz_dir, &psz_dst) != VLC_SUCCESS) {
        msg_Err(p_demux, "cannot locate the AACS configuration directory");
        return;
    }

    const char *psz_ask =
        _("A keydb.cfg file was detected. This file contains the keys used to "
          "decrypt Blu-ray discs. Do you want to import it automatically?");

    /* Overwriting somebody's key database is not something to do behind their
     * back, so say so before asking. */
    struct stat st;
    bool b_replace = vlc_stat(psz_dst, &st) == 0;

    char *psz_question = NULL;
    if (b_replace
     && asprintf(&psz_question, "%s\n\n%s", psz_ask,
                 _("A key database is already installed and will be "
                   "replaced.")) < 0)
        psz_question = NULL;

    int i_answer = vlc_dialog_wait_question(p_demux,
                        VLC_DIALOG_QUESTION_NORMAL,
                        _("No"), _("Yes"), NULL,
                        _("Blu-ray key database detected"),
                        "%s", psz_question ? psz_question : psz_ask);
    free(psz_question);

    if (i_answer != 1) {
        msg_Dbg(p_demux, "AACS key database import declined (%d)", i_answer);
        goto out;
    }

    char *psz_text;

    if (MakeDirs(psz_dir) != VLC_SUCCESS) {
        const char *psz_err = vlc_strerror_c(errno);

        msg_Err(p_demux, "cannot create %s: %s", psz_dir, psz_err);
        if (asprintf(&psz_text, _("The folder %s could not be created: %s"),
                     psz_dir, psz_err) >= 0) {
            Notify(p_demux, VLC_DIALOG_QUESTION_CRITICAL,
                   _("Key database import failed"), psz_text);
            free(psz_text);
        }
        goto out;
    }

    errno = 0;
    if (CopyStream(p_demux, psz_dst) != VLC_SUCCESS) {
        const char *psz_err = vlc_strerror_c(errno);

        msg_Err(p_demux, "cannot write %s: %s", psz_dst, psz_err);
        if (asprintf(&psz_text, _("The key database could not be copied to "
                                  "%s: %s"), psz_dst, psz_err) >= 0) {
            Notify(p_demux, VLC_DIALOG_QUESTION_CRITICAL,
                   _("Key database import failed"), psz_text);
            free(psz_text);
        }
        goto out;
    }

    if (asprintf(&psz_text, _("The key database was installed in %s.\n\n"
                              "Encrypted Blu-ray discs can now be played."),
                 psz_dst) >= 0) {
        Notify(p_demux, VLC_DIALOG_QUESTION_NORMAL,
               _("Key database imported"), psz_text);
        free(psz_text);
    }

out:
    free(psz_dst);
    free(psz_dir);
}

/*****************************************************************************
 * Demuxer: there is nothing to play
 *****************************************************************************/
static int Demux(demux_t *p_demux)
{
    (void) p_demux;
    return VLC_DEMUXER_EOF;
}

static int Control(demux_t *p_demux, int i_query, va_list args)
{
    return demux_vaControlHelper(p_demux->s, 0, -1, 0, 1, i_query, args);
}

static int Open(vlc_object_t *p_this)
{
    demux_t *p_demux = (demux_t *)p_this;

    if (p_demux->s == NULL) /* access_demux, nothing to read */
        return VLC_EGENERIC;

    if (!HasKeydbName(p_demux) || !LooksLikeText(p_demux->s))
        return VLC_EGENERIC;

    p_demux->pf_demux   = Demux;
    p_demux->pf_control = Control;
    p_demux->p_sys      = NULL;

    /* Preparsing happens for every item added to the playlist, in the
     * background: it reads metadata and must never talk to the user. The
     * question belongs to the moment the file is really opened. */
    if (!p_demux->b_preparsing)
        Import(p_demux);

    return VLC_SUCCESS;
}

static void Close(vlc_object_t *p_this)
{
    (void) p_this;
}
