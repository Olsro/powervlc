/*****************************************************************************
 * crystalhd.c: CrystalHD decoder
 *****************************************************************************
 * Copyright © 2010-2011 VideoLAN
 *
 * Authors: Jean-Baptiste Kempf <jb@videolan.org>
 *          Narendra Sankar <nsankar@broadcom.com>
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
 * Preamble
 *****************************************************************************/

#ifdef HAVE_CONFIG_H
# include "config.h"
#endif

/* TODO
 * - pts = 0?
 * - mpeg4-asp
 * - win32 testing
 */

/* VLC includes */
#include <vlc_common.h>
#include <vlc_plugin.h>
#include <vlc_codec.h>
#include <vlc_dialog.h>
#include "../packetizer/h264_nal.h"

#ifdef __APPLE__
# include "crystalhd_osx.h"
#endif

/* Workaround for some versions of libcrystalHD.
 * The Broadcom headers gate the POSIX typedefs (HANDLE and friends) and the
 * shape of the output callback behind __LINUX_USER__. Everything but the
 * Windows SDK needs it, macOS included: the contrib builds the library itself
 * and passes the very same define. */
#if !defined(_WIN32)
#  define __LINUX_USER__
#endif

/* CrystalHD */
#include <libcrystalhd/bc_dts_defs.h>
#include <libcrystalhd/bc_dts_types.h>

#if defined(HAVE_LIBCRYSTALHD_BC_DRV_IF_H) /* Win32 */
#  include <libcrystalhd/bc_drv_if.h>
#elif defined(_WIN32)
#  define USE_DL_OPENING 1
#else
#  include <libcrystalhd/libcrystalhd_if.h>
#endif

/* On a normal Win32 build, well aren't going to ship the BCM dll
   And forcing users to install the right dll at the right place will not work
   Therefore, we need to dl_open and resolve the symbols */
#ifdef USE_DL_OPENING
#  warning DLL opening mode
#  define BC_FUNC( a ) Our ## a
#  define BC_FUNC_PSYS( a ) p_sys->Our ## a
#else
#  define BC_FUNC( a ) a
#  define BC_FUNC_PSYS( a ) a
#endif

#include <assert.h>

/* BC pts are multiple of 100ns */
#define TO_BC_PTS( a ) ( a * 10 + 1 )
#define FROM_BC_PTS( a ) ((a - 1) /10)

/* Output colour space: packed 4:2:2, YUY2 byte order.
 *
 * Do not "optimise" this into UYVY to match some video output. Measured on a
 * BCM70015: DtsSetColorSpace(OUTPUT_MODE422_UYVY) returns BC_STS_SUCCESS and
 * the decoder opens happily, but the card keeps emitting YUY2 regardless --
 * the frames then come out with luma and chroma swapped (a test pattern turns
 * into nothing but green and magenta). Accepting the mode is not honouring it.
 * 4:2:0 is refused outright, so YUY2 is the only usable output. */
#define CRYSTALHD_OUTPUT_MODE   OUTPUT_MODE422_YUY2
#define CRYSTALHD_OUTPUT_CHROMA VLC_CODEC_YUYV

/* Upper bound when draining the card's ready list. BC_RX_LIST_CNT is 8 on
 * Darwin but 16 on Linux, and it lives in a driver header the contrib does not
 * install -- hence a local constant, sized for the larger of the two with room
 * to spare. It is only a guard against spinning, not a target. */
#define CRYSTALHD_MAX_DRAIN 32

/* How long the output thread waits when the card has nothing ready. Short
 * enough not to add latency of its own, and it is woken early on close. */
#define CRYSTALHD_POLL_DELAY (CLOCK_FREQ / 200)   /* 5 ms */

/* How many consecutive pictures may carry an extrapolated timestamp before
 * giving up and letting the core drop them: a card that stops timestamping
 * altogether must not free-run away from the real timeline. */
#define CRYSTALHD_MAX_EXTRAPOLATE 6

/* Wedge watchdog: blocks fed with no picture coming back before the output
 * thread rebuilds the decoder. In steady playback the card outputs about
 * one picture per input block, so a run of this many with nothing back is
 * already a clear stall -- keep it low, it sets how long the picture stays
 * frozen before recovery starts (at 24 fps 40 blocks is under two seconds;
 * 120 was five). The one case where the card legitimately outputs nothing
 * for a while is re-priming after a reset/flush, before it has seen a
 * fresh IDR -- that window is excluded separately (b_await_idr), so this
 * bound only ever measures a genuine mid-stream stall. Rather than a hard
 * cap (which froze the picture dead once reached), restarts are
 * rate-limited in wall time: a stream the card cannot decode limps rather
 * than dies, and a transient wedge is cleared promptly. */
#define CRYSTALHD_WEDGE_BLOCKS 40
#define CRYSTALHD_RESTART_COOLDOWN (CLOCK_FREQ * 3)

/* How far ahead of the display clock the decoder is allowed to get.
 *
 * A software decoder cannot outrun the clock -- it is the slow part. This
 * card can, by a wide margin: 1080p costs it almost nothing, so it empties
 * whatever the demuxer has read ahead as fast as the bus allows. The core
 * refuses a picture scheduled more than pts_delay + buffering + 9 s into the
 * future ("early picture skipped"), and that refusal is self-reinforcing: a
 * skipped picture is released at once, which refills the picture pool, which
 * removes the only back-pressure there was, which lets the card run further
 * ahead still. Measured on a 1080p Invidious stream: 126 consecutive pictures
 * skipped over 5.25 s, 14 frames displayed in the whole run, picture frozen
 * with the CPU idle.
 *
 * So bound the lead ourselves, on the input side, which is where VLC expects
 * a decoder to push back: a decoder that takes its time stops draining its
 * fifo, the fifo backs up into es_out, and the demuxer slows down. 4 s sits
 * well above normal operation (the pipeline's own lead is pts_delay, 1.5 s,
 * and the measured steady-state handoff was 2.5 s) and well below the ~10.6 s
 * where the core starts refusing pictures. */
#define CRYSTALHD_MAX_LEAD  (CLOCK_FREQ * 4)
/* ★ How much of the STREAM the card may be sitting on: the distance between
 * the block being fed and the last picture pulled back out.
 *
 * This, not the lead over the clock, is the quantity that actually runs away
 * here, and the two are independent because this decoder is split across two
 * threads. The output thread is throttled for free -- decoder_NewPicture()
 * blocks once the picture pool is empty, so what we PULL can never outrun the
 * display by more than the pool. Nothing whatsoever throttled what we FEED.
 * A software decoder cannot have this bug: it pulls and pushes on one thread,
 * so the pool bounds both ends at once.
 *
 * Measured on an Invidious 720p30 stream (2026-08-11), where the whole file
 * lands in a few seconds and es_out then hands the decoder the lot: in 5.7 s
 * of wall time the decoder thread had fed the card up to 49.3 s of content
 * while the output was still at 6.57 s -- a gap of 42.8 s, with the old
 * throttle reporting a perfectly healthy "avance 2.5 s" throughout, because
 * it was watching the output.
 *
 * The gap is not merely wasteful, it is what freezes the picture: a reset
 * (pre-emptive or otherwise) flushes everything the card holds, and decoding
 * resumes wherever the INPUT had got to. The content therefore jumps forward
 * by exactly this gap. Both resets of that run are in the trace: the first
 * skipped 1.47 s -> 5.13 s (gap 3.7 s at the time), the second resumed at
 * 40.7 s while the vout was still at 6.5 s -- every picture produced after it
 * was dated ~34 s in the future, so the vout could never display one, never
 * returned a picture to the pool, and the output thread parked in
 * decoder_NewPicture() for good. Audio played on; the image never moved.
 *
 * ⚠⚠ Sized in FRAMES, and generously, because the card does not hand pictures
 * back one at a time: it accumulates a BATCH of 32 and releases them together
 * (~1.3 s at 25 fps, inherent, five open-flag combinations measured). Starve
 * it below two batches in flight and it runs stop-and-go, falling behind real
 * time for good. Measured on Windows XP with the 848x480 pattern, whole file:
 *   cap 0.5 s -> 433 late pictures, handoff lead sinking to -17.8 s
 *   cap 2 s   -> 433 late, identical
 *   cap 3 s   -> 140 late, handoff lead back to +0.4 s and steady
 *   cap 6 s / 8 s -> same as 3 s, so the knee is just under three seconds
 * 80 frames is two batches plus margin: 2.7 s at 30 fps, 3.3 s at 24.
 *
 * A large cap costs nothing now that a rebuild is the exception rather than
 * the rule (see b_needs_preemptive): what a flush discards is bounded by the
 * approach tightening, which pulls the depth down before a planned rebuild.
 * What matters here is only that it stays BOUNDED -- the bug this fixes was
 * an input running 42.8 s ahead, not four. */
#define CRYSTALHD_DEPTH_FRAMES 80
#define CRYSTALHD_MAX_CARD_DEPTH (CLOCK_FREQ * 3)
/* How long the output may stay silent before the cap is widened. Holding is
 * only legitimate while pictures keep coming out; once they stop, the card is
 * wedged, and both recovery paths need BLOCKS FED to notice -- the wedge
 * watchdog counts them, and a re-primed decoder needs them to find its
 * keyframe. Neither can run while the input is held. */
#define CRYSTALHD_LEAD_MAX_HOLD (CLOCK_FREQ * 5)
/* ...and how long a silence means the card is not coming back at all. A card
 * that has truly stalled never recovers -- the rebuild the watchdog orders
 * brings the decoder up cleanly and not one further picture comes out
 * (measured on both platforms). Past this, hand the stream to software
 * rather than leave the picture frozen for the rest of the film, which is
 * exactly what happened on Windows: the card died at 36 s of a 50 s clip and
 * the audio played on to the end over a still image.
 * ⚠ Only after a restart has been tried: before that, a long silence is
 * ordinary start-up or a seek preroll. */
#define CRYSTALHD_DEAD_SILENCE (CLOCK_FREQ * 12)
/* ...but widen the cap, never remove it. Letting go entirely is what turned
 * the second freeze into a 20.4 s hole: the output stopped at 10.10 s, the
 * input ran free to 30.47 s in 5.6 s of wall time, and the reset that
 * followed resumed there -- twenty seconds of film skipped to recover from
 * one stall. The slack only has to cover the threshold the watchdog in
 * question counts to, because whatever gets fed past the last picture is
 * exactly what the next flush will skip:
 *   - CRYSTALHD_WEDGE_BLOCKS (40) ~= 1.3 s at 30 fps;
 *   - CRYSTALHD_REPRIME_BLOCKS ~= 3.3 s.
 * 4 s covers both.
 *
 * ⚠ There is deliberately NO extra slack while re-priming, tempting as it is
 * -- the card has just been rebuilt and "obviously" needs feeding. It does
 * not need much: it re-primes on the very keyframe that triggered the reset.
 * Granting it 8 s of slack was measured to cause the freeze it was meant to
 * avoid: after the reset at 3.32 s the decoder thread fed content 5.133 ->
 * 10.166 s in TEN MILLISECONDS, the fresh card burned its whole ~150-frame
 * budget in one gulp, and the next keyframe arrived while b_await_idr was
 * still set -- so the pre-emptive reset that would have saved it was skipped,
 * and the picture froze for good. Feed a re-priming card at the ordinary
 * pace and the keyframes land where they are needed. */
#define CRYSTALHD_DEPTH_SLACK_STALL   (CLOCK_FREQ * 4)
/* A MODEST extra depth while re-priming. The card does not start producing
 * off the keyframe alone -- it has an eight-deep output pipeline to fill --
 * and the steady-state cap starves it: measured, a rebuild left it silent for
 * 5.56 s, i.e. until CRYSTALHD_LEAD_MAX_HOLD gave up and widened the cap.
 * Half a second more is enough, and it costs nothing in skipped content: what
 * a flush discards is the depth in STEADY state, and the throttle pulls the
 * depth back to the base cap as soon as pictures flow again.
 * ⚠ Keep it small. At 8 s this same slack caused the freeze it was meant to
 * cure -- see the note above. */
#define CRYSTALHD_DEPTH_SLACK_REPRIME (CLOCK_FREQ / 2)
/* ★ Anticipating the keyframe. A pre-emptive rebuild discards whatever the
 * card is holding, so the skip IS the depth at that instant. Rather than try
 * to empty the card once the keyframe is here (see the reverted attempt just
 * below), pace the input tighter over the last stretch BEFORE it, so the
 * depth has already fallen to the card's floor by the time it arrives.
 *
 * Nothing is waited for on the spot: the input simply lets the output catch
 * up a little more than usual, which is ordinary back-pressure -- the card
 * keeps decoding and the vout keeps displaying off its own lead throughout.
 *
 * The floor is not zero: the card will not surrender its reorder tail, and it
 * has an eight-deep output pipeline to keep fed, so asking for less only
 * stalls (that is exactly how the reverted drain failed).
 * ⚠⚠ Count that floor in FRAMES, not seconds. Fixed at 0.3 s it was fine on
 * 720p30 (nine frames) and starved the card on 1080p24, where 0.3 s is barely
 * seven: 517 late pictures and playback slower than real time on a file that
 * had been flawless. i_date_interval is the interval the output thread has
 * actually measured, so the floor follows the content. APPROACH_DEPTH sits at that floor, and the tightening only
 * applies
 * only once the budget is spent. APPROACH_MAX_HOLD bounds it: a card that goes quiet just before a keyframe
 * must not be able to park the run there. */
/* How long to let the card empty itself after the keyframe has been fed and
 * before the flush. Generous: it is bounded by the card's own progress and
 * costs nothing when the card is healthy. */
#define CRYSTALHD_REPLAY_WAIT (CLOCK_FREQ * 3 / 2)
/* ...and stop early once the card has been quiet this long: it never gives
 * back the last two or three frames, so the target date is not actually
 * reachable and only the progress tells us when it is done. */
#define CRYSTALHD_REPLAY_QUIET (CLOCK_FREQ / 8)
/* Hard cap on the replay queue, so a card that never gives anything back
 * cannot make it grow without bound. 48 blocks is ~1.6 s at 30 fps and a
 * megabyte or so of compressed video; past that, rebuild anyway and accept
 * the skip, exactly as before this existed. */
#define CRYSTALHD_REPLAY_MAX_BLOCKS 48
/* Fallback bound on the drain when the card keeps claiming it has pictures
 * ready but none come out. */
#define CRYSTALHD_REPLAY_STUCK (CLOCK_FREQ / 2)
#define CRYSTALHD_APPROACH_FRAMES   8
#define CRYSTALHD_APPROACH_FALLBACK (CLOCK_FREQ * 3 / 10)
#define CRYSTALHD_APPROACH_MAX_HOLD (CLOCK_FREQ * 2 / 5)
/* ⛔ Draining the card before the pre-emptive flush: TRIED AND REVERTED.
 * Stopping the input and waiting for the card to empty cut the skip from
 * 0.47 s to 0.20 s -- and no further, because the reorder tail is exactly
 * what it will not release (the note further down says so). The wait then
 * always ran to its 2 s bound: nine 2.3 s holes in a 50 s clip, punctuality
 * down from 139 to 117 frames per 5 s, 277 late pictures against 3. A bad
 * trade; the skip is cheaper than the stall. */
/* How long the decoder thread will wait for a restart to finish before giving
 * up on the block in hand. Sized from the measurement the restart itself now
 * logs; generous, because losing input is worse than stalling briefly. */
#define CRYSTALHD_RESTART_WAIT (CLOCK_FREQ * 5)
/* Extra pictures on top of the DPB-derived pool, so the pipeline can actually
 * hold CRYSTALHD_MIN_PTS_DELAY of lead. 20 covers 1.5 s at 30 fps once the
 * core's own reserve is counted in, without turning a 1080p stream into a
 * memory problem on the machines this fork targets. */
#define CRYSTALHD_EXTRA_PICTURES 20
/* Waiting is done in slices so a flush or a close is never sat through.
 * 50 ms: msleep() refuses anything under 10 ms. */
#define CRYSTALHD_LEAD_SLICE (CLOCK_FREQ / 20)
/* While re-priming (b_await_idr: after a reset/flush, before the card has
 * output its first picture) the card legitimately produces nothing for a
 * while -- a seek preroll can be a whole GOP, more than the steady-state
 * threshold above. Use a much wider bound there so the watchdog does not
 * false-fire on the re-prime, yet still catches a card that never comes
 * back (~8 s at 24 fps). */
#define CRYSTALHD_REPRIME_BLOCKS 200

/* How many blocks the card may swallow between two pre-emptive rebuilds.
 *
 * This, not elapsed time, is what the card actually runs out of: measured on
 * an Invidious 720p30 stream it decodes ~150 frames and stops, whatever the
 * wall clock says. A rebuild is only free at a keyframe (the fresh decoder
 * re-primes on it), so the rule is "rebuild at the first keyframe once the
 * budget is spent" -- which resets at every keyframe when they are 152 frames
 * apart, and skips a few when they are dense.
 *
 * ⚠ It replaces CRYSTALHD_RESTART_COOLDOWN on this path, which vetoed exactly
 * the rebuild that mattered: with keyframes 5.067 s apart in CONTENT, the
 * wall gap between two of them drops below the 3 s cooldown whenever the
 * pipeline is catching up, and the reset was silently skipped. Measured:
 * "IDRDBG pts=15233334 await=0 depuis_reset=2665 ms" -- no reset, card dead
 * at 15.20 s. The cooldown still guards the reactive wedge path, where
 * spinning on a device reset is a real risk. */
#define CRYSTALHD_RESET_BUDGET 100
/* The decoder is rebuilt pre-emptively at the first keyframe once that budget
 * is spent, before its per-GOP leak stalls it. Timed to a keyframe, the
 * fresh decoder re-primes on that very frame, so the only cost is whatever
 * the card was still holding -- bounded by CRYSTALHD_MAX_CARD_DEPTH. The
 * reactive watchdog stays as the backstop for content that stalls sooner.
 * Measured on an Invidious 720p30 stream (keyframes every 5.067 s): the card
 * decodes ~150 frames and stops. It survived exactly the keyframes that got
 * a reset and died at the first one that did not. */

/* ⛔ Do not try DtsSetScaleParams to lift the 720p output cap: measured on
 * DIL 3.22.0, it returns BC_STS_NOT_IMPL (3) at every resolution. Kodi never
 * calls it either. The cap is not negotiable through that API.
 *
 * Device-open flags. DTS_PLAYBACK_DROP_RPT_MODE is what XBMC opens with.
 *
 * The resolution hint is NOT: XBMC passes vdecRESOLUTION_720p23_976, and on
 * Windows that hint BINDS -- measured on a BCM70015 with DIL 3.22.0, every
 * 1080p stream came back decoded at 1280x720, whatever the input format
 * declared. The card then reports a format change to 720p mid-stream, the
 * conversion chain downstream is still built for the source size, and
 * swscale writes past the end of its destination. vdecRESOLUTION_CUSTOM (0)
 * asks for no preset at all, which is what a player that does not know the
 * stream in advance actually wants.
 *
 * Shared by OpenDecoder and the wedge restart so the two never drift. */
/* Input-format OptFlags. The top bit is what makes the width/height fields
 * below it mean anything: without it the card ignores them and keeps decoding
 * at the DTS_DFLT_RESOLUTION hint given at open time -- measured, a 1080p
 * stream came out as 1280x720. The two call sites used to disagree (the
 * restart path had this value, the initial open still carried upstream's old
 * 0x51), so one shared constant now, as for the open flags. */
#define CRYSTALHD_INPUT_OPTFLAGS ( 0x80000000 | vdecFrameRate23_97 )

/* ⛔ DTS_LOAD_FILE_PLAY_FW is NOT optional: without it DtsProcOutput refuses
 * every call outright (BC_STS_ERR_USAGE -- "use the NoCopy interface"), and
 * the picture info block is never parsed either. Measured on a BCM70015: the
 * module still opens and is still selected, but not one frame ever comes out.
 * Dropping it looks like a spectacular win if the only thing being counted is
 * late pictures, because zero pictures are never late.
 *
 * ⚠ The card batches its output: fed a steady 6-7 frames every 250 ms, it
 * emits nothing for ~900 ms then hands back ~32 frames at once -- about 1.3 s
 * of latency. That is inherent, not ours: five distinct open-flag
 * combinations were measured (with and without DTS_PLAYBACK_DROP_RPT_MODE,
 * DTS_ADAPTIVE_OUTPUT_PER, DTS_SINGLE_THREADED_MODE, and the exact mode
 * Broadcom's own DirectShow filter uses, 0x0401c200) and every one of them
 * batches identically. VLC's default pipeline lead is --file-caching, 300 ms,
 * far too little to absorb it, so the first frames of each burst arrive past
 * their display date and are dropped: a visible hitch roughly every 1.3 s.
 * Raising the lead is the cure -- 480p H.264, whole file: 300 ms => 332 late
 * pictures, 1000 ms => 31, 1500 ms => none. Hence CRYSTALHD_MIN_PTS_DELAY,
 * claimed through decoder_t::i_min_pts_delay so nobody has to know to pass
 * --file-caching by hand. A batch is 32 pictures whatever the frame rate, so
 * the slowest rate is the worst case: 1.33 s at 24 fps. 1.5 s is that plus a
 * little, and it is a floor -- a larger caching setting still wins. */
#ifdef USE_DL_OPENING
/* ⚠ The Windows DIL batches far harder than the macOS one, and 1.5 s is not
 * enough there: the card's own latency eats the lead whole and the pictures
 * arrive at the vout barely ahead of their date, some behind it. Measured on
 * XP with the 848x480 pattern, whole file (software decoding of the same file
 * is clean, 0 late, so this is the card path):
 *   lead 1.5 s -> 140 late, handoff lead +0.34 s avg but LEAST -0.77 s
 *   lead 2.5 s -> 0 late,   handoff lead +1.33 s avg, least +0.29 s
 *   lead 3.5 s -> 0 late,   handoff lead +1.63 s avg, least +1.30 s
 * 3 s takes the margin without asking for a second more than needed. macOS
 * measures a ~0.9 s effective lead on a whole film with 3 late pictures, so
 * it does not need this and should not pay the extra start-up latency. */
#define CRYSTALHD_MIN_PTS_DELAY (3 * CLOCK_FREQ)       /* 3 s, Windows DIL */
#else
#define CRYSTALHD_MIN_PTS_DELAY (3 * CLOCK_FREQ / 2)   /* 1.5 s */
#endif

#define CRYSTALHD_OPEN_FLAGS \
    ( DTS_PLAYBACK_MODE | DTS_LOAD_FILE_PLAY_FW | DTS_SKIP_TX_CHK_CPB | \
      DTS_PLAYBACK_DROP_RPT_MODE | DTS_DFLT_RESOLUTION(vdecRESOLUTION_CUSTOM) )


//#define DEBUG_CRYSTALHD 1

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
static int        OpenDecoder  ( vlc_object_t * );
static void       CloseDecoder ( vlc_object_t * );

#define CRYSTALHD_ENABLE_TEXT N_("Hardware decoding (Crystal HD)")
#define CRYSTALHD_ENABLE_LONGTEXT N_( \
    "Decode H.264, VC-1 and MPEG-2 video on the Broadcom Crystal HD card " \
    "installed in this machine. Untick to decode with the processor instead; " \
    "playback also falls back to the processor on its own whenever the " \
    "card cannot handle a stream." )

vlc_module_begin ()
    set_category( CAT_INPUT )
    set_subcategory( SUBCAT_INPUT_VCODEC )
    set_description( N_("Crystal HD hardware video decoder") )
    /* Above videotoolbox (800): a machine with this card in its mini-PCIe slot
     * got it precisely because its CPU cannot keep up, and on the vintage
     * systems involved the platform decoders are either absent or limited.
     * Ranking picks the decoder at open time only, so anything the card cannot
     * handle -- no card at all, no driver, an unsupported codec, or a device
     * already claimed by another process -- makes OpenDecoder return an error
     * and lets the next decoder in line take over.
     *
     * The same rank on every platform, deliberately: the card behaves the same
     * everywhere, so the user should not have to know that it is automatic on
     * one system and needs --codec crystalhd on another. What used to make
     * that unsafe outside Apple was the cost of probing on machines with no
     * card; OpenDecoder now bails out early and cheaply in that case. */
    set_capability( "video decoder", 900 )
    set_callbacks( OpenDecoder, CloseDecoder )
    /* Same shape as videotoolbox's own switch: because this module outranks
     * every software decoder, a user who wants to compare against the CPU
     * path -- or who hits a stream the card mishandles -- otherwise has no
     * way out short of --codec on a command line. Unticking it makes
     * OpenDecoder decline and the next decoder in line take over. */
    add_bool( "crystalhd", true, CRYSTALHD_ENABLE_TEXT,
              CRYSTALHD_ENABLE_LONGTEXT, false )
    add_shortcut( "crystalhd" )
vlc_module_end ()

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
static int DecodeBlock   ( decoder_t *p_dec, block_t *p_block );
static void Flush        ( decoder_t *p_dec );
static bool PullPictures ( decoder_t *p_dec );
static void *OutputThread( void *p_data );
static int  CrystalHDStartHardware( decoder_t *p_dec );
// static void crystal_CopyPicture ( picture_t *, BC_DTS_PROC_OUT* );
static int crystal_insert_sps_pps(decoder_t *, uint8_t *, uint32_t);
static block_t *crystal_maybe_prepend_spspps( decoder_t *, block_t * );
static void crystal_RebuildAtIdr( decoder_t * );
static void crystal_ReplayClear( decoder_sys_t * );
static block_t *crystal_strip_eos( decoder_t *, block_t * );

/*****************************************************************************
 * decoder_sys_t : CrysalHD decoder structure
 *****************************************************************************/
struct decoder_sys_t
{
    HANDLE bcm_handle;       /* Device Handle */

    uint8_t *p_sps_pps_buf;  /* SPS/PPS buffer, AnnexB (for SetInputFormat) */
    size_t   i_sps_pps_size; /* SPS/PPS size */

    /* Same parameter sets in the stream's own length-prefixed form, to
     * prepend to each IDR (see crystal_maybe_prepend_spspps). NULL for
     * non-avc1 codecs. */
    uint8_t *p_sps_pps_avc;
    size_t   i_sps_pps_avc_size;
    unsigned i_idr_seen;     /* IDRs we prepended parameter sets to */

    uint8_t i_nal_size;     /* NAL header size */
    uint32_t i_bcm_subtype; /* BC_MSUBTYPE_*, kept to rebuild the decoder */

    /* Callback state. Only the output thread runs DtsProcOutput (and thus
     * the callback), so everything here is private to it -- no lock. */
    picture_t       *p_pic;
    BC_DTS_PROC_OUT *proc_out;
    unsigned         i_pic_gen;      /* generation p_pic was allocated under */

    /* Output dating, private to the output thread. The card occasionally
     * delivers a picture without a timestamp; the core drops undated
     * pictures ("non-dated video buffer received"), one visible hitch
     * each time. Extrapolate instead from the previous picture. */
    vlc_tick_t i_last_date;
    vlc_tick_t i_date_interval;
    unsigned   i_extrapolated;       /* consecutive extrapolations */

    /* Flush generation, under lock. Bumped by Flush(); the output thread
     * discards any picture decoded under an older generation instead of
     * queueing it. This is what keeps pre-seek frames off the screen now
     * that Flush() itself no longer touches the card (see Flush). */
    unsigned i_flush_gen;

    /* Blocks fed since the card last delivered a picture, under lock.
     * The BCM70015 leaks an internal resource per IDR on complex content
     * and stalls after a handful of them: it keeps accepting input, its
     * ready list stays empty forever, no error is reported anywhere
     * (measured 08/08/2026 -- real YouTube 720p AND 1080p, both far under
     * the chip's Level-4.1 ceiling, stall after ~7 IDRs; content with
     * rare keyframes never stalls). Priming a healthy decoder never takes
     * more than a couple dozen blocks, so a long dry spell means the card
     * is stuck: reset it (see CrystalHDRestartHardware). */
    unsigned i_blocks_since_out;
    /* Blocks fed since the decoder was last rebuilt: the card's
     * budget, see CRYSTALHD_RESET_BUDGET. */
    unsigned i_blocks_since_reset;

    /* Rebuild-at-keyframe replay (see crystal_RebuildAtIdr). While
     * b_replay_pending, every block fed is also kept here, chained through
     * p_next, so the rebuilt decoder can be handed the exact same sequence
     * starting at the keyframe -- nothing is lost to the flush.
     * i_replay_target is the keyframe's PTS, the date the card must reach
     * before it has given back everything from the previous GOP;
     * i_replay_seen/i_replay_moved track that progress across calls;
     * i_drop_upto suppresses the pictures the replay produces a second
     * time. */
    block_t *p_replay_head;
    block_t *p_replay_tail;
    unsigned i_replay_blocks;
    vlc_tick_t i_replay_target;
    vlc_tick_t i_replay_seen;
    vlc_tick_t i_replay_moved;
    vlc_tick_t i_drop_upto;
    bool     b_replay_pending;
    unsigned i_restarts;
    vlc_tick_t i_last_restart;   /* mdate() of the last restart, rate limit */
    /* Set after a reset/flush: the card cannot output until it is fed a
     * fresh IDR, so the wedge watchdog must not count that gap. Cleared
     * when the next IDR goes in. Under lock. */
    bool     b_await_idr;


    /* Consecutive DtsProcOutput I/O failures, so the message above is said
     * once instead of per pull. */
    unsigned i_io_errors;

    /* Said once: the geometry handed to the card on the first callback. */
    bool     b_buffer_logged;

    /* Said once: what the card reported delivering on its first picture. */
    bool     b_output_logged;

    /* Said once: the stall was traced to our own empty picture pool rather
     * than to the card. Rate-limits a message a squeezed pipeline would
     * otherwise repeat at every threshold. */
    bool     b_pool_stall_logged;

    /* Date of the last picture handed to the core, for the lead throttle.
     * Distinct from i_last_date, which belongs to the output thread alone:
     * this one is read from the decoder thread, so it is written and read
     * under the lock. VLC_TICK_INVALID until the first dated picture. */
    vlc_tick_t i_last_out_date;

    /* Said once: the throttle had to hold the input back. */
    bool     b_lead_logged;
    /* Said once: the stream carries End of Sequence markers. */
    bool     b_eos_logged;

    /* Set the first time the card really wedges. Until then the pre-emptive
     * rebuild stays disarmed: it costs two frames at every keyframe, and
     * with the End of Sequence markers stripped (see crystal_strip_eos) most
     * content never needs it at all -- measured, this stream went from nine
     * rebuilds and 1.17 s of skipped video to none and nothing. Content that
     * does hit the card's per-IDR stall arms it on its first hiccup and is
     * protected from then on. */
    bool     b_needs_preemptive;

    /* Throttle state, kept ACROSS calls on purpose. Held locally, it made the
     * escape hatch fire once per block instead of once per stall: every block
     * arrived with a fresh deadline and sat out the full hold, so a stalled
     * card was fed one block every CRYSTALHD_LEAD_MAX_HOLD -- and a card that
     * has just been reset is starved of the very keyframe it needs to come
     * back. Measured: 55 blocks in ten seconds after a reset, card at
     * ready=0 free=8 throughout, a recoverable stall turned permanent.
     * i_hold_date is the output date last observed, i_hold_since when it last
     * moved, b_hold_given_up latches once it has been still too long and
     * clears the moment a picture comes out. */
    vlc_tick_t i_hold_date;
    vlc_tick_t i_hold_since;
    bool     b_hold_given_up;



    /* Set between the two halves of an interlaced field pair: the card then
     * wants its buffer one line into the picture. Tracked here because the
     * buffer is now filled in BEFORE the call, where this picture's own
     * interlace flags are not known yet. */
    bool     b_second_field;

    /* The card's real output geometry is not known until it has produced
     * something: it decodes 1080p streams at 1280x720 on this driver, and
     * Broadcom's own DirectShow filter gets exactly the same -- verified by
     * interposing on bcmDIL.dll, 460 calls, every one of them 1280x720. So
     * the first picture goes into a plain buffer of our own instead of a
     * VLC one: nothing is advertised to the core, and no video output is
     * built, until the size is known for certain. Announcing the container
     * size and correcting it afterwards is what used to crash -- the
     * conversion chain keeps the geometry it was created with. */
    bool     b_geometry_known;
    uint8_t *p_probe_buf;
    size_t   i_probe_sz;

    /* What the last returned PicInfo said about interlacing. Used to size the
     * stride padding of the NEXT buffer, since that has to be decided before
     * the card tells us anything about the picture it is about to deliver. */
    bool     b_interlaced;

    /* IDRs fed since the last reset, under lock. The card leaks a resource
     * per IDR and stalls after several; rather than wait for that stall
     * and its visible freeze, reset pre-emptively every few IDRs, timed to
     * an IDR so the fresh decoder re-primes on it at once and the vout's
     * lead hides the ~100 ms gap (see crystal_maybe_prepend_spspps). */
    vlc_cond_t reset_done;   /* output thread -> DecodeBlock: reset finished */

    /* Highest input pts fed since the last flush, under lock. The card
     * cannot legitimately output a timestamp it was never fed, yet it has
     * been seen echoing one far in the future (08/08/2026): a picture
     * dated that far ahead parks the video output on it -- it sits at the
     * head of the queue, never due, everything behind it waits, and the
     * pipeline stalls with the audio still playing. Output dates beyond
     * this bound are demoted to "no timestamp" and re-derived. */
    vlc_tick_t i_max_in_pts;

    /* Card flush request, under lock. Set by Flush(), performed and
     * cleared by DecodeBlock (both on the decoder thread; the lock is for
     * the output thread's benefit). The DIL's flush stops and closes the
     * hardware decoder and the next DtsProcInput reopens it, so the flush
     * is performed right before the first post-seek input: no post-seek
     * data can be caught in it, and every input-side call stays on one
     * thread.
     *
     * While it is pending, everything the card delivers is by definition
     * pre-seek and must be discarded: the generation check alone does not
     * cover it -- the frames still sitting in the card at Flush() time get
     * PULLED under the new generation, and on a network stream the window
     * until the first post-seek block (= the card flush) spans a whole
     * rebuffering. Measured 08/08/2026 on a direct googlevideo stream:
     * those frames reached the video output with their old timestamps,
     * unconvertible under the post-seek clock ("Could not convert
     * timestamp"), clogged the look-ahead cushion and froze the picture
     * for good while the audio played on. */
    bool     b_flush_card;
    uint32_t i_card_flush_mode;

    /* Hardware-restart request, under lock. Set by DecodeBlock (input
     * thread) when the wedge watchdog fires; performed by the output
     * thread, which is the only other DIL caller, at the top of its loop
     * where it holds the lock and is not inside DtsProcOutput. While it
     * is pending DecodeBlock feeds the card nothing. Single producer
     * (DecodeBlock sets), single consumer (OutputThread clears). */
    bool     b_restart;

    /* Set by the output thread when device resets have failed to revive
     * the card; DecodeBlock then returns VLCDEC_RELOAD so the core falls
     * back to software. Under lock. */
    bool     b_want_reload;
    /* Consecutive device resets that produced no picture: the card is
     * unrecoverable once this passes a small bound. */
    unsigned i_dead_resets;

    /* Which chip: the BCM70015 ("Flea") and the BCM70012 ("Link") need
     * different handling in several places, exactly as XBMC does. */
    bool     b_flea;
    /* Post-seek catch-up, mirroring XBMC's m_reset/m_skip_state: skip
     * pictures for a few input blocks so the card can get ahead again. */
    unsigned i_reset;
    bool     b_skip_mode;

    /* Output thread. The card holds several decoded frames and stops
     * decoding once its ready list fills up, so something has to empty that
     * list continuously rather than once per input block -- which is what
     * XBMC's CMPCOutputThread does, and why seeking behaves there. */
    vlc_thread_t thread;
    bool         b_thread;   /* thread actually started */
    vlc_mutex_t  lock;       /* guards the output path and the flush */
    vlc_cond_t   wait;       /* wakes the thread on stop */
    bool         b_stop;     /* under lock */

#ifdef USE_DL_OPENING
    /* These are __cdecl, NOT WINAPI/__stdcall. bcmDIL.dll exports the DIL
     * entry points as cdecl -- visible in the C++-decorated duplicates it also
     * exports, which carry the `YA` (cdecl) marker. Declaring them stdcall
     * builds and links fine and even survives the first call, but GCC then
     * emits a `sub esp, N` after each call to compensate for a cleanup the
     * callee never performs: esp drifts by the argument size every time, and
     * with -O2 (no frame pointer) every later esp-relative local access slides
     * with it. The symptom is a wild jump on the SECOND DIL call --
     * DtsCrystalHDVersion -- into whatever the shifted slot happens to hold,
     * typically a string. Verified on Windows XP SP3 / DIL 3.6.9. */
    HINSTANCE p_bcm_dll;
    BC_STATUS (*OurDtsCloseDecoder)( HANDLE hDevice );
    BC_STATUS (*OurDtsDeviceClose)( HANDLE hDevice );
    BC_STATUS (*OurDtsFlushInput)( HANDLE hDevice, U32 Mode );
    BC_STATUS (*OurDtsStopDecoder)( HANDLE hDevice );
    BC_STATUS (*OurDtsGetDriverStatus)( HANDLE hDevice,
                            BC_DTS_STATUS *pStatus );
    BC_STATUS (*OurDtsProcInput)( HANDLE hDevice, U8 *pUserData,
                            U32 ulSizeInBytes, U64 timeStamp, BOOL encrypted );
    BC_STATUS (*OurDtsProcOutput)( HANDLE hDevice, U32 milliSecWait,
                            BC_DTS_PROC_OUT *pOut );
    BC_STATUS (*OurDtsIsEndOfStream)( HANDLE hDevice, U8* bEOS );
    BC_STATUS (*OurDtsSetSkipPictureMode)( HANDLE hDevice, U32 SkipMode );
    BC_STATUS (*OurDtsFlushRxCapture)( HANDLE hDevice, BOOL bDiscardOnly );
    /* ★ The bring-up half. These used to be locals in OpenDecoder, which is
     * the ONLY reason Windows had no restart path -- CrystalHDStartHardware()
     * could not reach them, so the whole wedge/pre-emptive machinery was
     * compiled out and a stalled card stayed stalled for the rest of the
     * film. Measured on XP: with the End of Sequence markers stripped the
     * card now survives eight keyframes instead of one, then hits the other
     * stall (~9 IDRs) with nothing to recover it. */
    BC_STATUS (*OurDtsSetColorSpace)( HANDLE hDevice, BC_OUTPUT_FORMAT Mode422 );
    BC_STATUS (*OurDtsSetInputFormat)( HANDLE hDevice,
                            BC_INPUT_FORMAT *pInputFormat );
    BC_STATUS (*OurDtsOpenDecoder)( HANDLE hDevice, U32 StreamType );
    BC_STATUS (*OurDtsStartDecoder)( HANDLE hDevice );
    BC_STATUS (*OurDtsStartCapture)( HANDLE hDevice );
    BC_STATUS (*OurDtsDeviceOpen)( HANDLE *hDevice, U32 mode );
#endif
};

/* Held from just before the device is opened until it is closed. A plain
 * flag rather than a semaphore: what it guards is a piece of hardware with
 * exactly one seat, and the answer is only ever yes or no. */
static vlc_mutex_t chd_device_lock = VLC_STATIC_MUTEX;
static bool        chd_device_busy = false;

/* Set the first time the device opens successfully. Guards the retry loop in
 * OpenDecoder: retrying is worth 600 ms when the card is real and merely
 * still settling, and pure waste on a machine that only has the driver
 * installed. Never cleared -- a card that answered once is a card. */
static bool        chd_device_seen = false;

#ifdef USE_DL_OPENING
/* Set once the Broadcom DIL has been looked for and not found. bcmDIL.dll
 * ships only with the vendor driver, so its absence means there is no card to
 * talk to, and the answer will not change while the process runs. Worth
 * remembering now that the module is auto-selected: without this, every
 * single decoder open on every Windows machine without the card would walk
 * the DLL search path three times over. This is the Win32 counterpart of the
 * IOKit pre-check macOS does. */
static bool        chd_dll_missing = false;
#endif

/* Quarantine: when the card wedges on a stream and device resets do not
 * revive it (a large-keyframe stall the BCM70015 cannot decode -- real
 * 1080p YouTube does it deterministically, while avcodec handles the same
 * stream fine), the module gives up on the hardware, returns VLCDEC_RELOAD
 * so the core re-probes, and declines here for a while so the software
 * decoder takes over instead of the card wedging again in a loop. Coarse
 * (process-wide) but a wedged card is a strong enough signal, and it
 * self-clears so a later, decodable stream tries the hardware again. */
static vlc_tick_t  chd_quarantine_until = VLC_TICK_INVALID;
#define CRYSTALHD_QUARANTINE (CLOCK_FREQ * 120)

static bool CrystalHDClaimDevice( void )
{
    bool b_free;

    vlc_mutex_lock( &chd_device_lock );
    b_free = !chd_device_busy;
    if( b_free )
        chd_device_busy = true;
    vlc_mutex_unlock( &chd_device_lock );

    return b_free;
}

static void CrystalHDReleaseDevice( void )
{
    vlc_mutex_lock( &chd_device_lock );
    chd_device_busy = false;
    vlc_mutex_unlock( &chd_device_lock );
}

/* Common teardown for the failure paths that sit between p_sys being fully
 * built and the hardware being open: everything initialised above, plus the
 * one-seat device claim. Skipping the release used to be invisible because
 * those paths were only reachable with --codec crystalhd; now that the module
 * is auto-selected, a machine that has the driver but no card would take the
 * seat on its first decoder open and never give it back, so every later open
 * would decline for the wrong reason. */
static void CrystalHDAbortOpen( decoder_sys_t *p_sys )
{
    vlc_cond_destroy( &p_sys->wait );
    vlc_cond_destroy( &p_sys->reset_done );
    vlc_mutex_destroy( &p_sys->lock );
    free( p_sys );
    CrystalHDReleaseDevice();
}

/* Says out loud that the card is there and unusable, once per run.
 *
 * Falling back to software is the right thing to do -- the video plays --
 * but doing it silently is not: on a machine bought for this card, "it
 * suddenly got slow" is all the user sees, and the reason sits in a debug
 * line nobody reads. Measured 05/08/2026: an abnormal exit leaves the
 * device refusing every open, for every process, until the driver is
 * reloaded; a whole evening of testing went by in software that way.
 *
 * Once, because the demuxer asks for a decoder again on every seek and a
 * dialog per seek would be worse than the silence. */
static void CrystalHDWarnUnusable( decoder_t *p_dec )
{
    static bool b_warned = false;
    bool b_first;

    vlc_mutex_lock( &chd_device_lock );
    b_first = !b_warned;
    b_warned = true;
    vlc_mutex_unlock( &chd_device_lock );

    if( !b_first )
        return;

    vlc_dialog_display_error( p_dec,
        _( "Crystal HD decoder unavailable" ),
        _( "The Crystal HD card is installed but its device cannot be "
           "opened, so this video is being decoded in software and will "
           "be slower.\n\n"
           "This usually clears up by reloading the driver: Help > "
           "Reload the Crystal HD driver." ) );
}

/* Bring the hardware decoder up on an already-open device: colour space,
 * input format, open, start, capture. Factored out of OpenDecoder so the
 * wedge watchdog can tear the decoder down and run it again. On any
 * failure it closes whatever it had opened, leaving only the device open
 * (the state OpenDecoder's `error` label expects).
 *
 * Not built for the Win32 dlopen path: there these entry points are
 * resolved into OpenDecoder's locals, not into p_sys, so they cannot be
 * reached from a separate function -- Win32 keeps the inline bring-up. */
static int CrystalHDStartHardware( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    BC_INPUT_FORMAT p_in;
    memset( &p_in, 0, sizeof(BC_INPUT_FORMAT) );
    /* OptFlags: bits 0:3 default frame rate, bits 4:5 operation mode
     * (Blu-ray), bit 6 mpcOutPutMaxFRate, bit 7 single-threaded. The
     * upstream 0x51 sets the Blu-ray operation-mode bit and max-frame-rate
     * on every stream, which this hardware has no business seeing on plain
     * High-profile content. XBMC, the reference for this hardware, sets
     * neither -- just the frame-rate hint with the high bit. Follow it.
     * (This is not what fixes the IDR wedge -- SPS/PPS-per-IDR is -- but
     * there is no reason to keep the stray Blu-ray bits either.) */
    p_in.OptFlags    = CRYSTALHD_INPUT_OPTFLAGS;
    p_in.mSubtype    = p_sys->i_bcm_subtype;
    p_in.startCodeSz = p_sys->i_nal_size;
    p_in.pMetaData   = p_sys->p_sps_pps_buf;
    p_in.metaDataSz  = p_sys->i_sps_pps_size;
    p_in.width       = p_dec->fmt_in.video.i_width;
    p_in.height      = p_dec->fmt_in.video.i_height;
    p_in.Progressive = true;

    msg_Dbg( p_dec, "declaring to the card: %ux%u, subtype %u, startCodeSz %u, "
                    "metaData %u B, OptFlags 0x%x",
             p_in.width, p_in.height, (unsigned)p_in.mSubtype,
             (unsigned)p_in.startCodeSz, (unsigned)p_in.metaDataSz,
             (unsigned)p_in.OptFlags );

    if( BC_FUNC_PSYS(DtsSetInputFormat)( p_sys->bcm_handle, &p_in )
            != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't set the input format. Please report this!" );
        return VLC_EGENERIC;
    }

    if( BC_FUNC_PSYS(DtsOpenDecoder)( p_sys->bcm_handle, BC_STREAM_TYPE_ES )
            != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't open the CrystalHD decoder" );
        return VLC_EGENERIC;
    }

    /* Colour space AFTER the decoder is open, never before. Kodi -- the one
     * implementation with a track record on this hardware -- orders it
     * SetInputFormat, OpenDecoder, SetColorSpace, and the order matters:
     * configuring the output of a decoder that does not exist yet leaves the
     * card on a default. Measured with the call made too early: the card
     * reported the right decode size but wrote only half the width and half
     * the height of it -- a quarter picture in the corner of the buffer, the
     * untouched remainder coming out green. */
    if( BC_FUNC_PSYS(DtsSetColorSpace)( p_sys->bcm_handle, CRYSTALHD_OUTPUT_MODE )
            != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't set the color space. Please report this!" );
        return VLC_EGENERIC;
    }


    if( BC_FUNC_PSYS(DtsStartDecoder)( p_sys->bcm_handle ) != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't start the decoder" );
        BC_FUNC_PSYS(DtsCloseDecoder)( p_sys->bcm_handle );
        return VLC_EGENERIC;
    }

    if( BC_FUNC_PSYS(DtsStartCapture)( p_sys->bcm_handle ) != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't start the capture" );
        BC_FUNC_PSYS(DtsStopDecoder)( p_sys->bcm_handle );
        BC_FUNC_PSYS(DtsCloseDecoder)( p_sys->bcm_handle );
        return VLC_EGENERIC;
    }

    return VLC_SUCCESS;
}

/* Recover a wedged card. Called from the output thread (the sole
 * DtsProcOutput caller) under p_sys->lock, so no capture/status call can
 * run against the handle mid-restart.
 *
 * Decoder-level (Stop/Close, then bring the decoder back up on the same
 * device -- no DtsDeviceClose, no firmware re-push). When this was tried
 * before SPS/PPS-per-IDR was in place it only limped: the reopened
 * decoder hit the next IDR with no parameter sets and wedged again at
 * once, so a full device reset was needed. With SPS/PPS now prepended to
 * every IDR the reopened decoder gets fresh parameter sets on the next
 * keyframe and recovers cleanly -- and this is far cheaper than a device
 * reopen (measured: recovers within a frame or two, real time held across
 * repeated resets), so the hiccup is barely visible. The backstop for the
 * rare case where even this does not take is unchanged: two resets with
 * no picture in between quarantine the card and fall back to software. */
static void CrystalHDRestartHardware( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* Two callers: the pre-emptive path fires at an IDR while the card is
     * still healthy (few dry blocks), the wedge watchdog after a stall
     * (i_blocks_since_out at the threshold). Tell them apart in the log --
     * and, further down, in what they are allowed to conclude. Captured
     * now: i_blocks_since_out is cleared in between. */
    const bool b_preemptive =
        ( p_sys->i_blocks_since_out < CRYSTALHD_WEDGE_BLOCKS );

    if( !b_preemptive )
    {
        msg_Warn( p_dec, "CrystalHD wedged (%u blocks in, no picture out): "
                  "restarting the decoder (reset #%u)",
                  p_sys->i_blocks_since_out, p_sys->i_restarts + 1 );
        /* It really does stall on this content: from now on, rebuild at
         * keyframes rather than wait for the next stall. */
        p_sys->b_needs_preemptive = true;
    }
    else
        msg_Dbg( p_dec, "CrystalHD pre-emptive decoder reset (#%u) before the "
                 "per-IDR stall", p_sys->i_restarts + 1 );

    BC_FUNC_PSYS(DtsFlushInput)( p_sys->bcm_handle, 2 );
    BC_FUNC_PSYS(DtsStopDecoder)( p_sys->bcm_handle );
    BC_FUNC_PSYS(DtsCloseDecoder)( p_sys->bcm_handle );


    if( p_sys->p_pic )
    {
        picture_Release( p_sys->p_pic );
        p_sys->p_pic = NULL;
    }

    if( CrystalHDStartHardware( p_dec ) != VLC_SUCCESS )
        msg_Err( p_dec, "CrystalHD decoder bring-up failed after reset" );

    p_sys->i_blocks_since_out = 0;
    p_sys->i_blocks_since_reset = 0;
    p_sys->i_last_date = VLC_TICK_INVALID;
    /* ⚠ i_last_out_date is deliberately NOT cleared here. A reset rebuilds
     * the decoder; it does not move the stream's timeline, so the last date
     * we produced stays the right reference for the lead throttle. Clearing
     * it blinded the throttle for as long as the card took to re-prime --
     * measured on a 720p30 stream, the first "early picture skipped" landed
     * six log lines after a pre-emptive reset, and the throttle only woke up
     * once the card was 14.4 s ahead instead of the 4 s it is meant to hold.
     * Only Flush() clears it, because only a seek really does move the
     * timeline. */
    p_sys->i_extrapolated = 0;
    p_sys->i_last_restart = mdate();
    p_sys->i_restarts++;
    /* The reopened decoder produces nothing until the next IDR: hold the
     * wedge watchdog off until then, so it does not fire on the re-prime. */
    p_sys->b_await_idr = true;

    /* No picture has come out since the previous reset (i_dead_resets is
     * cleared in PullPictures whenever one does): the reset did not revive
     * the card. Past a small bound the card is decoding nothing on this
     * stream -- some real 1080p content wedges the BCM70015 on its large
     * keyframes and no reset clears it. Give up on the hardware: quarantine
     * it and ask DecodeBlock to reload into software.
     *
     * Only a reset the WATCHDOG ordered counts. A pre-emptive one is
     * scheduled maintenance -- it fires on an IDR count, before any stall,
     * on a card that is working perfectly -- so "it produced no picture
     * since" says nothing about the hardware. It routinely says something
     * about us instead: during the initial buffering the video output
     * returns nothing to the picture pool, so no picture can come out of
     * any decoder, and both pre-emptive resets of a 1080p stream were being
     * booked as evidence of a dying card. Measured on a 1800x1080 Invidious
     * stream: pre-emptive resets #1 and #2 during buffering, then one
     * genuine watchdog reset, and the card was retired into software on a
     * count of two failures that had not happened. */
    if( b_preemptive )
        return;

    if( ++p_sys->i_dead_resets >= 2 )
    {
        msg_Err( p_dec, "CrystalHD is not recovering (%u dead resets): "
                 "falling back to software decoding for this stream",
                 p_sys->i_dead_resets );
        vlc_mutex_lock( &chd_device_lock );
        chd_quarantine_until = mdate() + CRYSTALHD_QUARANTINE;
        vlc_mutex_unlock( &chd_device_lock );
        p_sys->b_want_reload = true;   /* under p_sys->lock (held by caller) */
    }
}

/*****************************************************************************
 * crystal_H264WithinLimits: is this stream inside what the chip can do?
 *****************************************************************************
 * The BCM70012 and BCM70015 decode H.264 up to High profile LEVEL 4.1 -- in
 * practice 1080p30. Handed more, the card does not refuse anything: it opens,
 * decodes for a moment and then stops dead, still swallowing input and
 * producing nothing (ready=0, free list full, FramesCaptured frozen).
 * Measured on a 1800x1080 Level 4.2 60 fps YouTube stream: 56 pictures, under
 * a second of video, then silence. The watchdog then spends ~13 s restarting
 * a chip that was never going to recover before quarantining it and falling
 * back to software -- 13 s of frozen picture where declining at open costs
 * nothing and gets avcodec straight away.
 *
 * Two independent tests, because either datum can be missing:
 *  - the advertised level, when the demuxer filled it in (mp4 reads it from
 *    avcC), which is the authoritative answer;
 *  - the macroblock rate, for containers that advertise nothing. Level 4.1
 *    allows 245760 macroblocks per second, which is exactly 1920x1088 at
 *    30 fps, so the two tests agree by construction.
 * Anything not known is not held against the stream: an unknown level and an
 * unknown frame rate leave the card to try, as before.
 *****************************************************************************/
#define CRYSTALHD_MAX_H264_LEVEL   41
#define CRYSTALHD_MAX_MB_PER_SEC   245760   /* H.264 Level 4.1 */

static bool crystal_H264WithinLimits( decoder_t *p_dec )
{
    const es_format_t *p_fmt = &p_dec->fmt_in;

    /* es_format_t::i_level is filled in by the H.264 PACKETIZER, which does
     * not run on an already-packetized avc1 track -- it is 0 here for every
     * mp4. The level is in the extradata all the same: avcC is
     * [1][profile][compat][LEVEL][...], so byte 3, and that is the datum the
     * demuxer read its own profile from. Fall back to the format field for
     * containers that do fill it. */
    int i_level = p_fmt->i_level;
    if( p_fmt->i_extra >= 4 && p_fmt->p_extra != NULL &&
        ((const uint8_t *)p_fmt->p_extra)[0] == 1 )
        i_level = ((const uint8_t *)p_fmt->p_extra)[3];

    if( i_level > 0 && i_level > CRYSTALHD_MAX_H264_LEVEL )
    {
        msg_Dbg( p_dec, "H.264 level %d.%d is beyond what this card decodes "
                 "(4.1): leaving the stream to software",
                 i_level / 10, i_level % 10 );
        return false;
    }

    if( p_fmt->video.i_frame_rate > 0 && p_fmt->video.i_frame_rate_base > 0 &&
        p_fmt->video.i_width > 0 && p_fmt->video.i_height > 0 )
    {
        /* Macroblocks are 16x16 and a partial one still counts. */
        const uint64_t i_mbs = ( ( p_fmt->video.i_width  + 15 ) / 16 )
                             * ( ( p_fmt->video.i_height + 15 ) / 16 );
        const uint64_t i_mb_rate = i_mbs * p_fmt->video.i_frame_rate
                                         / p_fmt->video.i_frame_rate_base;
        if( i_mb_rate > CRYSTALHD_MAX_MB_PER_SEC )
        {
            msg_Dbg( p_dec, "%ux%u at %.2f fps is %"PRIu64" macroblocks/s, "
                     "past this card's %u (H.264 level 4.1): leaving the "
                     "stream to software",
                     p_fmt->video.i_width, p_fmt->video.i_height,
                     (double)p_fmt->video.i_frame_rate
                         / p_fmt->video.i_frame_rate_base,
                     i_mb_rate, CRYSTALHD_MAX_MB_PER_SEC );
            return false;
        }
    }

    return true;
}

/*****************************************************************************
* OpenDecoder: probe the decoder and return score
*****************************************************************************/
static int OpenDecoder( vlc_object_t *p_this )
{
    decoder_t *p_dec = (decoder_t*)p_this;
    decoder_sys_t *p_sys;

    /* Declining here rather than not registering at all keeps the ranking
     * machinery intact: the next video decoder in line opens normally, and
     * an explicit --codec crystalhd still overrides the preference. */
    if( !var_InheritBool( p_dec, "crystalhd" ) )
        return VLC_EGENERIC;

    /* Codec specifics */
    uint32_t i_bcm_codec_subtype = 0;
    switch ( p_dec->fmt_in.i_codec )
    {
    case VLC_CODEC_H264:
        if( !crystal_H264WithinLimits( p_dec ) )
            return VLC_EGENERIC;
        if( p_dec->fmt_in.i_original_fourcc == VLC_FOURCC( 'a', 'v', 'c', '1' ) )
            i_bcm_codec_subtype = BC_MSUBTYPE_AVC1;
        else
            i_bcm_codec_subtype = BC_MSUBTYPE_H264;
        break;
    case VLC_CODEC_VC1:
        i_bcm_codec_subtype = BC_MSUBTYPE_VC1;
        break;
    case VLC_CODEC_WMV3:
        i_bcm_codec_subtype = BC_MSUBTYPE_WMV3;
        break;
    case VLC_CODEC_WMVA:
        i_bcm_codec_subtype = BC_MSUBTYPE_WMVA;
        break;
    case VLC_CODEC_MPGV:
        i_bcm_codec_subtype = BC_MSUBTYPE_MPEG2VIDEO;
        break;
/* Not ready for production yet
    case VLC_CODEC_MP4V:
        i_bcm_codec_subtype = BC_MSUBTYPE_DIVX;
        break;
    case VLC_CODEC_DIV3:
        i_bcm_codec_subtype = BC_MSUBTYPE_DIVX311;
        break; */
    default:
        return VLC_EGENERIC;
    }

#ifdef USE_DL_OPENING
    /* Same intent as the IOKit pre-check below: on a machine with no card the
     * common case must cost nothing. Windows offers no equally cheap way to
     * ask whether the card is there, but the vendor DLL is a good proxy --
     * it is installed with the driver and nothing else ships it -- and once
     * the search has come up empty the answer is settled for this process. */
    vlc_mutex_lock( &chd_device_lock );
    bool b_no_dll = chd_dll_missing;
    vlc_mutex_unlock( &chd_device_lock );
    if( b_no_dll )
        return VLC_EGENERIC;
#endif

#ifdef __APPLE__
    /* Check the hardware before touching the library. The plugin ships on
     * every Intel Mac build, but almost none of them have a mini-PCIe slot to
     * put a card in, so the common case must cost nothing. */
    uint16_t i_pci_device;
    if( !CrystalHDOSXFindCard( &i_pci_device ) )
        return VLC_EGENERIC;

    if( !CrystalHDOSXDriverReady() )
    {
        msg_Warn( p_dec, "CrystalHD card present (PCI id %04x) but its driver "
                         "is not loaded, falling back to software decoding",
                  i_pci_device );
        return VLC_EGENERIC;
    }

    /* A 64-bit process cannot reach a 32-bit driver, and the driver matches
     * the kernel: on a Mac that never boots a 64-bit kernel (no 64-bit
     * graphics driver) the card is present, installed, and still out of
     * reach. The kext refuses such a caller outright -- without that guard it
     * would panic the machine -- so stop here rather than fail obscurely. */
    if( CrystalHDOSXBlockedBy64BitProcess() )
    {
        msg_Warn( p_dec, "CrystalHD card present but unreachable: this is a "
                         "64-bit process and the driver is 32-bit. Relaunch "
                         "PowerVLC in 32-bit mode to use the card." );
        return VLC_EGENERIC;
    }

    CrystalHDOSXSetFirmwarePath( p_dec );
#endif

    /* One decoder at a time, and the check happens BEFORE the library is
     * touched at all.
     *
     * The card decodes one stream, and libcrystalhd keeps a single context
     * per process. A second instance is not a theoretical case: an HLS
     * seek produces one every time -- the demuxer builds the elementary
     * stream of the new segment and asks for a decoder while the old one
     * is still running -- and Jellyfin transcodes to HLS. Measured on a
     * BCM70015 (05/08/2026, reproduced deterministically): the second
     * DtsDeviceOpen fails, as it should, but it takes the RUNNING
     * decoder's context down with it, and that decoder's output thread
     * then dies in DtsGetDrvStat. The card is left wedged afterwards --
     * every later open fails until the kext is reloaded, and playback
     * falls back to software with nothing said.
     *
     * Refusing here costs nothing: the second stream gets avcodec, which
     * is what it would have got anyway, and the one already playing keeps
     * the hardware. */
    /* Under quarantine after an unrecoverable wedge: let software decode.
     * Checked before claiming the device so the reload lands on avcodec. */
    vlc_mutex_lock( &chd_device_lock );
    bool b_quarantined = ( chd_quarantine_until != VLC_TICK_INVALID &&
                           mdate() < chd_quarantine_until );
    vlc_mutex_unlock( &chd_device_lock );
    if( b_quarantined )
    {
        msg_Dbg( p_dec, "CrystalHD is quarantined after an unrecoverable "
                        "wedge, decoding this stream in software" );
        return VLC_EGENERIC;
    }

    if( !CrystalHDClaimDevice() )
    {
        msg_Dbg( p_dec, "CrystalHD is already decoding another stream, "
                        "letting another decoder take this one" );
        return VLC_EGENERIC;
    }

    /* Allocate the memory needed to store the decoder's structure */
    p_sys = malloc( sizeof(*p_sys) );
    if( !p_sys )
    {
        CrystalHDReleaseDevice();
        return VLC_ENOMEM;
    }

    /* Fill decoder_sys_t */
    p_dec->p_sys            = p_sys;
    p_sys->i_nal_size       = 4; // assume 4 byte start codes
    p_sys->i_bcm_subtype    = i_bcm_codec_subtype;
    p_sys->i_sps_pps_size   = 0;
    p_sys->i_pic_gen        = 0;
    p_sys->i_last_date      = VLC_TICK_INVALID;
    p_sys->i_date_interval  = 0;
    p_sys->i_extrapolated   = 0;
    p_sys->i_flush_gen      = 0;
    p_sys->i_blocks_since_out = 0;
    p_sys->i_blocks_since_reset = 0;
    p_sys->i_restarts       = 0;
    p_sys->i_last_restart   = VLC_TICK_INVALID;
    /* Start in the re-prime state: the card produces nothing until it has
     * digested the first IDR and filled its reorder pipeline, which over a
     * paced network feed can take well over the steady-state threshold.
     * Cleared, like every re-prime, when the first picture actually comes
     * out (see PullPictures). Without this the watchdog fires on the very
     * first GOP (measured on a real 1080p stream: captured=0 at the first
     * "wedge"). */
    p_sys->b_await_idr      = true;
    p_sys->i_io_errors      = 0;
    p_sys->b_buffer_logged  = false;
    p_sys->b_output_logged  = false;
    p_sys->b_pool_stall_logged = false;
    p_sys->i_last_out_date  = VLC_TICK_INVALID;
    p_sys->b_lead_logged    = false;
    p_sys->b_eos_logged     = false;
    /* ⛔ Arming this from the start on the Windows DIL was TRIED AND
     * REVERTED, twice, the second time on a clean machine: six rebuilds gave
     * 835 late pictures against 6 without. And it would not have helped
     * anyway. ⚠ What stalls the Windows DIL is the CONTENT, not a counter: at
     * 1200x720 and 30 fps a synthetic pattern runs 2054 frames and another
     * real video 2083, both without a single wedge, while one particular
     * clip dies around 33 s whether it comes from YouTube or from a local
     * x264 re-encode of the same pictures. macOS plays that clip whole.
     * Neither a decoder rebuild nor a full device close/reopen helps, and
     * nor does dropping DTS_SKIP_TX_CHK_CPB, nor unloading and reloading
     * bcmDIL.dll itself. Whatever accumulates survives every teardown we can
     * reach from here and only dies with the process, so it lives in the
     * vendor's kernel driver -- which, unlike the userspace library, we
     * cannot replace. Let the card run at full rate for as long as it lasts,
     * then hand the stream to software. */
    p_sys->b_needs_preemptive = false;
    p_sys->i_hold_date      = VLC_TICK_INVALID;
    p_sys->i_hold_since     = VLC_TICK_INVALID;
    p_sys->b_hold_given_up  = false;
    /* ⚠ p_sys is malloc'd, not calloc'd: every field of decoder_sys_t has to
     * be set here. Leaving these three out cost a full debugging round --
     * b_replay_pending came up true on the very first block and sent a wild
     * p_idr_replay pointer into the rebuild path. */
    p_sys->p_replay_head    = NULL;
    p_sys->p_replay_tail    = NULL;
    p_sys->i_replay_blocks  = 0;
    p_sys->i_replay_target  = VLC_TICK_INVALID;
    p_sys->i_replay_seen    = VLC_TICK_INVALID;
    p_sys->i_replay_moved   = VLC_TICK_INVALID;
    p_sys->i_drop_upto      = VLC_TICK_INVALID;
    p_sys->b_replay_pending = false;
    p_sys->b_second_field   = false;
    p_sys->b_geometry_known = false;
    p_sys->p_probe_buf      = NULL;
    p_sys->i_probe_sz       = 0;
    p_sys->b_interlaced     = false;
    p_sys->i_max_in_pts     = VLC_TICK_INVALID;
    p_sys->b_flush_card     = false;
    p_sys->b_restart        = false;
    p_sys->b_want_reload    = false;
    p_sys->i_dead_resets    = 0;
    p_sys->i_card_flush_mode = 2;
    p_sys->b_flea           = false;
    p_sys->b_thread         = false;
    p_sys->b_stop           = false;
    vlc_mutex_init( &p_sys->lock );
    vlc_cond_init( &p_sys->wait );
    vlc_cond_init( &p_sys->reset_done );
    p_sys->i_reset          = 0;
    p_sys->b_skip_mode      = false;
    p_sys->p_sps_pps_buf    = NULL;
    p_sys->p_sps_pps_avc    = NULL;
    p_sys->i_sps_pps_avc_size = 0;
    p_sys->i_idr_seen       = 0;
    p_dec->p_sys->p_pic     = NULL;
    p_dec->p_sys->proc_out  = NULL;

    /* Win32 code *
     * We cannot link and ship BCM dll, even with LGPL license (too big)
     * and if we don't ship it, the plugin would not work depending on the
     * installation order => DLopen */
#ifdef USE_DL_OPENING
#  define DLL_NAME "bcmDIL.dll"
#  define PATHS_NB 3
    static const TCHAR *psz_paths[PATHS_NB] = {
        TEXT(DLL_NAME),
        TEXT("C:\\Program Files\\Broadcom\\Broadcom CrystalHD Decoder\\" DLL_NAME),
        TEXT("C:\\Program Files (x86)\\Broadcom\\Broadcom CrystalHD Decoder\\" DLL_NAME),
    };
    for( int i = 0; i < PATHS_NB; i++ )
    {
        HINSTANCE p_bcm_dll = LoadLibrary( psz_paths[i] );
        if( p_bcm_dll )
        {
            p_sys->p_bcm_dll = p_bcm_dll;
            break;
        }
    }
    if( !p_sys->p_bcm_dll )
    {
        msg_Dbg( p_dec, "Couldn't load the CrystalHD dll");
        vlc_mutex_lock( &chd_device_lock );
        chd_dll_missing = true;
        vlc_mutex_unlock( &chd_device_lock );
        CrystalHDAbortOpen( p_sys );
        return VLC_EGENERIC;
    }

#define LOAD_SYM( a ) \
    BC_FUNC( a )  = (void *)GetProcAddress( p_sys->p_bcm_dll, ( #a ) ); \
    if( !BC_FUNC( a ) ) { \
        msg_Err( p_dec, "missing symbol " # a ); \
        CrystalHDAbortOpen( p_sys ); return VLC_EGENERIC; }

#define LOAD_SYM_PSYS( a ) \
    p_sys->BC_FUNC( a )  = (void *)GetProcAddress( p_sys->p_bcm_dll, #a ); \
    if( !p_sys->BC_FUNC( a ) ) { \
        msg_Err( p_dec, "missing symbol " # a ); \
        CrystalHDAbortOpen( p_sys ); return VLC_EGENERIC; }

    LOAD_SYM_PSYS( DtsDeviceOpen );
    BC_STATUS (*OurDtsCrystalHDVersion)( HANDLE  hDevice, PBC_INFO_CRYSTAL bCrystalInfo );
    LOAD_SYM( DtsCrystalHDVersion );
    LOAD_SYM_PSYS( DtsSetColorSpace );
    LOAD_SYM_PSYS( DtsSetInputFormat );
    LOAD_SYM_PSYS( DtsOpenDecoder );
    LOAD_SYM_PSYS( DtsStartDecoder );
    LOAD_SYM_PSYS( DtsStartCapture );
    LOAD_SYM_PSYS( DtsCloseDecoder );
    LOAD_SYM_PSYS( DtsDeviceClose );
    LOAD_SYM_PSYS( DtsFlushInput );
    LOAD_SYM_PSYS( DtsStopDecoder );
    LOAD_SYM_PSYS( DtsGetDriverStatus );
    LOAD_SYM_PSYS( DtsProcInput );
    LOAD_SYM_PSYS( DtsProcOutput );
    LOAD_SYM_PSYS( DtsIsEndOfStream );
    LOAD_SYM_PSYS( DtsSetSkipPictureMode );
    LOAD_SYM_PSYS( DtsFlushRxCapture );
#undef LOAD_SYM
#undef LOAD_SYM_PSYS
#endif /* USE_DL_OPENING */

#ifdef DEBUG_CRYSTALHD
    msg_Dbg( p_dec, "Trying to open CrystalHD HW");
#endif

    /* Get the handle for the device */
    /* DTS_PLAYBACK_DROP_RPT_MODE and the default resolution hint are what
     * XBMC opens with, and it is the reference for this hardware. */
    /* Three tries rather than one: the device a decoder has just closed
     * takes a moment to come back, and a stream that changes format --
     * every HLS segment boundary -- asks for a new decoder right then.
     * Giving up on the first refusal sent those into software for the
     * rest of the playback. */
    /* ...but only once the card has proved it exists. Now that the module is
     * auto-selected on every platform, "driver installed, no card" is a real
     * configuration, and there the retries would cost 600 ms on every single
     * decoder open for nothing. So the first failure is final until one open
     * has succeeded in this process. */
    bool b_may_retry;
    vlc_mutex_lock( &chd_device_lock );
    b_may_retry = chd_device_seen;
    vlc_mutex_unlock( &chd_device_lock );

    const int i_tries = b_may_retry ? 3 : 1;
    BC_STATUS sts = BC_STS_ERROR;
    for( int i_try = 0; i_try < i_tries; i_try++ )
    {
        sts = BC_FUNC_PSYS(DtsDeviceOpen)( &p_sys->bcm_handle,
                                           CRYSTALHD_OPEN_FLAGS );
        if( sts == BC_STS_SUCCESS )
            break;
        if( i_try + 1 < i_tries )
            msleep( 300 * 1000 );
    }

    if( sts == BC_STS_SUCCESS )
    {
        vlc_mutex_lock( &chd_device_lock );
        chd_device_seen = true;
        vlc_mutex_unlock( &chd_device_lock );
    }

    if( sts != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't find and open the BCM CrystalHD device" );
        CrystalHDWarnUnusable( p_dec );
        vlc_cond_destroy( &p_sys->wait );
    vlc_cond_destroy( &p_sys->reset_done );
        vlc_mutex_destroy( &p_sys->lock );
        free( p_sys );
        CrystalHDReleaseDevice();
        return VLC_EGENERIC;
    }

    /* Which chip this is drives several workarounds below, so this query is
     * not debug-only: device == 1 means BCM70015 ("Flea"), otherwise it is a
     * BCM70012 ("Link"). Same test as XBMC's m_has_bcm70015. */
    BC_INFO_CRYSTAL info;
    if( BC_FUNC(DtsCrystalHDVersion)( p_sys->bcm_handle, &info ) == BC_STS_SUCCESS )
    {
        p_sys->b_flea = (info.device == 1);
        msg_Dbg( p_dec, "CrystalHD %s, driver %i.%i.%i, library %i.%i.%i, "
            "firmware %i.%i.%i",
            p_sys->b_flea ? "BCM70015" : "BCM70012",
            info.drvVersion.drvRelease, info.drvVersion.drvMajor,
            info.drvVersion.drvMinor,
            info.dilVersion.dilRelease, info.dilVersion.dilMajor,
            info.dilVersion.dilMinor,
            info.fwVersion.fwRelease,   info.fwVersion.fwMajor,
            info.fwVersion.fwMinor );
    }
    else
        msg_Warn( p_dec, "could not identify the CrystalHD chip, assuming "
                         "BCM70012 and its workarounds" );

    /* WMV3 only decodes on the BCM70015; XBMC refuses it on the older chip
     * rather than let it produce garbage. */
    if( i_bcm_codec_subtype == BC_MSUBTYPE_WMV3 && !p_sys->b_flea )
    {
        msg_Dbg( p_dec, "WMV3 needs a BCM70015, letting another decoder try" );
        goto error;
    }

    /* Special case for AVC1 */
    if( i_bcm_codec_subtype == BC_MSUBTYPE_AVC1 )
    {
        if( p_dec->fmt_in.i_extra > 0 )
        {
            msg_Dbg( p_dec, "Parsing extra infos for avc1" );
            if( crystal_insert_sps_pps( p_dec, (uint8_t*)p_dec->fmt_in.p_extra,
                        p_dec->fmt_in.i_extra ) != VLC_SUCCESS )
                goto error;
        }
        else
        {
            msg_Err( p_dec, "Missing extra infos for avc1" );
            goto error;
        }
    }

    /* Colour space, input format, decoder, capture: the whole hardware
     * bring-up, in a helper so the wedge watchdog can run it again. Used on
     * every platform now that the Win32 dlopen path keeps its entry points
     * in p_sys rather than in locals. */
    if( CrystalHDStartHardware( p_dec ) != VLC_SUCCESS )
        goto error;

    /* Set output properties */
    /* Start pulling frames only once capture is running. */
    if( vlc_clone( &p_sys->thread, OutputThread, p_dec,
                   VLC_THREAD_PRIORITY_INPUT ) )
    {
        msg_Err( p_dec, "Couldn't start the CrystalHD output thread" );
        /* The decoder is open and running by now: without this, the
         * device would stay claimed for good (it is exclusive) and every
         * later playback would fail with BC_STS_DEC_EXIST_OPEN. */
        BC_FUNC_PSYS(DtsStopDecoder)( p_sys->bcm_handle );
        goto error_complete;
    }
    p_sys->b_thread = true;

    p_dec->fmt_out.i_codec        = CRYSTALHD_OUTPUT_CHROMA;
    p_dec->fmt_out.video.i_width  = p_dec->fmt_in.video.i_width;
    p_dec->fmt_out.video.i_height = p_dec->fmt_in.video.i_height;
    p_dec->fmt_out.video.i_visible_width  = p_dec->fmt_in.video.i_width;
    p_dec->fmt_out.video.i_visible_height = p_dec->fmt_in.video.i_height;

    /* Set callbacks */
    p_dec->pf_decode = DecodeBlock;
    p_dec->pf_flush  = Flush;

    /* Claim the lead the card's batched output needs (see
     * CRYSTALHD_OPEN_FLAGS). Without it the head of every batch misses its
     * display date and the picture hitches roughly once a second. */
    p_dec->i_min_pts_delay = CRYSTALHD_MIN_PTS_DELAY;

    /* And the buffers to hold that lead. Asking for 1.5 s of lead means
     * 1.5 s worth of pictures in flight -- 45 at 30 fps -- on top of the
     * handful the card keeps for itself; the core's own pool is sized from
     * the DPB and stops around 28. Short of that, the output thread blocks
     * in decoder_NewPicture() waiting for the video output to hand one back,
     * and it stops collecting from the card. Measured on a 720p30 stream
     * before this: 4101 ms of every 5 s spent waiting for a picture against
     * 207 ms actually talking to the card, the card sitting on ready=7
     * free=1, and playback crawling at 7 fps while the audio ran on time.
     * The cost is memory, and only while the card is in use: at 1200x720 in
     * packed 4:2:2 a picture is 1.7 MB, so this is ~34 MB. */
    p_dec->i_extra_picture_buffers = CRYSTALHD_EXTRA_PICTURES;

    msg_Info( p_dec, "Opened CrystalHD hardware with success" );
    return VLC_SUCCESS;

error_complete:
    BC_FUNC_PSYS(DtsCloseDecoder)( p_sys->bcm_handle );
error:
    BC_FUNC_PSYS(DtsDeviceClose)( p_sys->bcm_handle );
    vlc_cond_destroy( &p_sys->wait );
    vlc_cond_destroy( &p_sys->reset_done );
    vlc_mutex_destroy( &p_sys->lock );
    free( p_sys->p_probe_buf );
    block_ChainRelease( p_sys->p_replay_head );
    free( p_sys->p_sps_pps_buf );
    free( p_sys->p_sps_pps_avc );
    free( p_sys );
    CrystalHDReleaseDevice();
    return VLC_EGENERIC;
}

/*****************************************************************************
 * CloseDecoder: decoder destruction
 *****************************************************************************/
static void CloseDecoder( vlc_object_t *p_this )
{
    decoder_t *p_dec = (decoder_t *)p_this;
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* Stop pulling before touching the device: the thread calls into the
     * library too, and must not be running while it is torn down. */
    if( p_sys->b_thread )
    {
        vlc_mutex_lock( &p_sys->lock );
        p_sys->b_stop = true;
        vlc_cond_signal( &p_sys->wait );
        vlc_mutex_unlock( &p_sys->lock );
        vlc_join( p_sys->thread, NULL );
    }

    /* Tear down unconditionally: the device is exclusive, so bailing out on
     * the first failing step would leave it open for good and every later
     * playback would fail with BC_STS_DEC_EXIST_OPEN. Report, but keep going. */
    if( BC_FUNC_PSYS(DtsFlushInput)( p_sys->bcm_handle, 2 ) != BC_STS_SUCCESS )
        msg_Warn( p_dec, "CrystalHD: flushing the input failed" );

    /* On the BCM70012 the internal queues have to be released here or the
     * next DtsStartCapture fails -- a driver/library bug XBMC documents. The
     * BCM70015 must not get this call. */
    if( !p_sys->b_flea &&
        BC_FUNC_PSYS(DtsFlushRxCapture)( p_sys->bcm_handle, false ) != BC_STS_SUCCESS )
        msg_Warn( p_dec, "CrystalHD: releasing the capture queues failed" );
    if( BC_FUNC_PSYS(DtsStopDecoder)( p_sys->bcm_handle ) != BC_STS_SUCCESS )
        msg_Warn( p_dec, "CrystalHD: stopping the decoder failed" );
    if( BC_FUNC_PSYS(DtsCloseDecoder)( p_sys->bcm_handle ) != BC_STS_SUCCESS )
        msg_Warn( p_dec, "CrystalHD: closing the decoder failed" );
    if( BC_FUNC_PSYS(DtsDeviceClose)( p_sys->bcm_handle ) != BC_STS_SUCCESS )
        msg_Warn( p_dec, "CrystalHD: closing the device failed" );

    if( p_sys->p_pic )
        picture_Release( p_sys->p_pic );

    vlc_cond_destroy( &p_sys->wait );
    vlc_cond_destroy( &p_sys->reset_done );
    vlc_mutex_destroy( &p_sys->lock );

    /* The seat is free again: the next stream may have the card. Released
     * only once the device is really closed, never before. */
    CrystalHDReleaseDevice();

    free( p_sys->p_sps_pps_buf );
    free( p_sys->p_sps_pps_avc );
#ifdef DEBUG_CRYSTALHD
    msg_Dbg( p_dec, "done cleaning up CrystalHD" );
#endif
    free( p_sys );
}

/* Hand the card the picture it is to fill.
 *
 * This used to be an AppCallBack: the DIL was supposed to call back once it
 * knew the picture, and the buffer was filled from inside that callback. The
 * callback IS invoked by the Windows DIL 3.6.9 -- traced -- yet every
 * DtsProcOutput still failed with BC_STS_IO_XFR_ERROR and not one frame ever
 * came out. AppCallBack appears nowhere in Broadcom's own header: the
 * documented contract for DtsProcOutput is that "the actual data buffer to be
 * filled with the decoded data is allocated by the caller", i.e. Ybuff and
 * YbuffSz are set in the structure BEFORE the call. That is what this does,
 * and it is also what the one field-proven implementation (XBMC/Kodi) does.
 *
 * The cost of moving out of the callback is that this picture's own interlace
 * flags are not known yet; they are applied after the call, from the PicInfo
 * the card returns. Only the field-pair buffer offset has to be decided up
 * front, hence p_sys->b_second_field. */

/* The card lays its lines out on a quantised stride and pads to it. The
 * module used to assume this was a BCM70012 quirk; it is not. Measured on a
 * BCM70015 by interposing on bcmDIL.dll: for an 848-wide stream, Broadcom's
 * own DirectShow filter asks for StrideSz 176, i.e. a 1024-pixel stride.
 *
 * So advertise a BUFFER that wide and keep the visible width truthful --
 * exactly what the two pairs in video_format_t are for. A picture whose
 * pitch does not reach the quantised stride gets its lines written at the
 * card's spacing rather than ours, and the content walks off both edges. */
static unsigned crystal_QuantisedStride( unsigned i_width )
{
    if( i_width <= 1024 ) return 1024;
    if( i_width <= 1280 ) return 1280;
    if( i_width <= 1920 ) return 1920;
    return i_width;
}

static BC_STATUS crystal_PrepareOutput( decoder_t *p_dec,
                                        BC_DTS_PROC_OUT *proc_out )
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    const bool b_second_field = p_sys->b_second_field;

    /* Probe phase: hand the card a buffer of our own, sized for the stream
     * (an upper bound, since the card only ever comes back smaller), and
     * tell VLC nothing yet. */
    if( !p_sys->b_geometry_known )
    {
        if( !p_sys->p_probe_buf )
        {
            unsigned w = p_dec->fmt_in.video.i_width  ? p_dec->fmt_in.video.i_width  : 1920;
            unsigned h = p_dec->fmt_in.video.i_height ? p_dec->fmt_in.video.i_height : 1088;
            p_sys->i_probe_sz  = (size_t)w * (h + 8) * 2;   /* packed 4:2:2 + slack */
            p_sys->p_probe_buf = malloc( p_sys->i_probe_sz );
            if( !p_sys->p_probe_buf )
                return BC_STS_ERROR;
        }
        memset( p_sys->p_probe_buf, 0, p_sys->i_probe_sz );
        proc_out->Ybuff    = p_sys->p_probe_buf;
        proc_out->YbuffSz  = (uint32_t)(p_sys->i_probe_sz / 4);
        proc_out->StrideSz = 0;
        proc_out->PoutFlags |= BC_POUT_FLAGS_STRIDE;
        return BC_STS_SUCCESS;
    }

    /* ⚠ Never start a picture allocation with a restart pending. This runs on
     * the output thread, decoder_NewPicture() blocks for as long as the pool
     * is empty, and the output thread is the ONLY one that can service the
     * restart -- so the wait is on a condition nobody left is able to bring
     * about. Meanwhile DecodeBlock drops every incoming block for the whole
     * duration, which is what turns a routine pre-emptive reset into a frozen
     * picture: measured on a 720p30 stream, one reset stayed pending for over
     * 300 blocks, ten seconds of video thrown away with the audio playing on.
     * Give the loop its turn back instead; the restart is serviced at the top
     * of the next iteration and the pull resumes right after. */
    vlc_mutex_lock( &p_sys->lock );
    const bool b_restart_pending = p_sys->b_restart;
    vlc_mutex_unlock( &p_sys->lock );
    if( unlikely(b_restart_pending) )
        return BC_STS_ERROR;

    /* Direct rendering: one picture per field PAIR, so the second half of a
     * pair reuses the picture the first half allocated. */
    if( !b_second_field )
    {
        if( !decoder_UpdateVideoFormat( p_dec ) )
            p_sys->p_pic = decoder_NewPicture( p_dec );
    }

    /* */
    picture_t *p_pic = p_sys->p_pic;
    if( !p_pic )
    {
        return BC_STS_ERROR;
    }

    /* Filling out the struct */
    proc_out->Ybuff      = !b_second_field ?
                             &p_pic->p[0].p_pixels[0] :
                             &p_pic->p[0].p_pixels[p_pic->p[0].i_pitch];
    /* YbuffSz counts 4-BYTE UNITS, not bytes. Nothing in the Broadcom headers
     * says so; the proof is upstream's original allocation, which read
     *     YbuffSz = width * height / 2;
     *     Ybuff   = malloc( YbuffSz * 4 );   // Allocate in bytes
     * and whose arithmetic lands exactly on pitch * height for packed 4:2:2.
     *
     * Describing the buffer as "2 * pitch" -- two lines, or eight once the
     * unit is taken into account -- had the DIL refuse every single transfer
     * with BC_STS_IO_XFR_ERROR (status 15). The decoder then produced not one
     * frame: audio played, the picture stayed black, and the only clue was a
     * message that said "return mode not implemented".
     *
     * Measured from the real start offset, since the field-pair path hands
     * the card a pointer one line into the picture. */
    const ptrdiff_t i_offset = proc_out->Ybuff - p_pic->p[0].p_pixels;
    proc_out->YbuffSz    = (uint32_t)
        ((p_pic->p[0].i_pitch * p_pic->p[0].i_lines - i_offset) / 4);

    /* Line stride in pixels; packed 4:2:2 is two bytes per pixel. */
    unsigned i_stride_px = p_pic->p[0].i_pitch / 2;
    /* The VISIBLE width, not the buffer's. The padding the card is told about
     * is the gap between its line spacing and the real picture: measured on a
     * BCM70015, Broadcom's own filter sends StrideSz 176 for an 848-wide
     * stream, i.e. 1024 - 848. Computing it from the buffer width gives 0,
     * and the card then writes nothing at all -- the picture comes out
     * uniformly green, YUY2 zero. */
    const unsigned i_width = p_dec->fmt_out.video.i_visible_width ?
                             p_dec->fmt_out.video.i_visible_width :
                             p_dec->fmt_out.video.i_width;

    /* The stride the card uses is the picture's, already quantised by
     * crystal_QuantisedStride(). So the padding to declare is what separates
     * that stride from the visible picture. Interlaced sources arrive one
     * field at a time, so every other line belongs to the other field and
     * the padding doubles; go by what the last picture reported, since this
     * one's flags are not known before the call returns. */
    /* The card DOES honour this: declaring 0 while the picture pitch was
     * wider made it write its lines end to end, each one 176 pixels left of
     * where it belonged, and the frame came out shredded on a diagonal with
     * the tail of the buffer never written. So the gap between the picture's
     * pitch and its visible width is exactly what to declare -- which for a
     * quantised buffer is the same 176 Broadcom's own filter sends.
     * Interlaced sources need it doubled, the two fields being interleaved
     * line by line. */
    proc_out->StrideSz = p_sys->b_interlaced ?
                          2 * i_stride_px - i_width :
                          i_stride_px - i_width;

    /* STRIDE *and* SIZE, with PicInfo filled in -- exactly what Broadcom's
     * own DirectShow filter sends (PoutFlags 0x6, PicInfo preset to the real
     * picture size), captured by interposing on bcmDIL.dll.
     *
     * BC_POUT_FLAGS_SIZE means "take the size from the application", so it
     * only makes sense together with a PicInfo that says something. Passing
     * SIZE while PicInfo was still memset to zero told the DIL to copy a
     * 0x0 picture: the buffer came back untouched, uniformly green (YUY2
     * zero), which was misread as SIZE being incompatible with supplying our
     * own buffer. It is not -- the size was simply missing.
     *
     * Without SIZE, the DIL's copy loop reads its source line from a stride
     * it works out on its own, and on a BCM70015 it gets it wrong in the most
     * misleading way possible: every destination line receives the SAME
     * source line. The result still looks plausible -- vertical colour bars
     * come out sharp, in the right places, in the right colours, because bars
     * are identical on every line -- while every feature that varies down the
     * picture (overlays, motion, fine detail) is silently gone. Verified by
     * dumping the raw buffer: all 480 lines were byte-identical. */
    proc_out->PicInfo.width  = i_width;
    proc_out->PicInfo.height = p_dec->fmt_out.video.i_visible_height ?
                               p_dec->fmt_out.video.i_visible_height :
                               p_dec->fmt_out.video.i_height;
    proc_out->PoutFlags |= BC_POUT_FLAGS_STRIDE | BC_POUT_FLAGS_SIZE;

    /* Once per decoder: the exact geometry handed to the card. When the DIL
     * answers with an I/O error on every call, these are the numbers to
     * check first -- buffer size against pitch times height, and the stride
     * padding against the real width. */
    if( !p_sys->b_buffer_logged )
    {
        p_sys->b_buffer_logged = true;
        msg_Dbg( p_dec, "handing the card: %ux%u, pitch %d B, YbuffSz %u B, "
                        "stride pad %u px, lines %d",
                 i_width, p_dec->fmt_out.video.i_height,
                 p_pic->p[0].i_pitch, proc_out->YbuffSz,
                 proc_out->StrideSz, p_pic->p[0].i_visible_lines );
    }

    return BC_STS_SUCCESS;
}

/****************************************************************************
 * crystal_FixGreenPixel: paper over a driver quirk
 ****************************************************************************
 * The driver stashes internal information in the first pixel of every field
 * it delivers and restores the original value afterwards. When that restore
 * does not happen it leaves the pixel at zero instead, which is bright green
 * in YUV rather than the black it would be in RGB. Replicate the second pixel
 * over the first, as XBMC does.
 ****************************************************************************/
static void crystal_FixGreenPixel( picture_t *p_pic )
{
    uint8_t *p_pixels = p_pic->p[0].p_pixels;

    /* Packed 4:2:2 puts two pixels in four bytes whichever the byte order, so
     * the second pixel pair starts at byte 4 and there has to be one to copy
     * from. */
    if( p_pic->p[0].i_visible_pitch < 8 )
        return;

    memcpy( p_pixels, p_pixels + 4, 4 );

    /* Interlaced content is delivered as two separate fields, so the second
     * one carries its own poisoned pixel at the start of the next line. */
    if( !p_pic->b_progressive && p_pic->p[0].i_visible_lines > 1 )
    {
        p_pixels += p_pic->p[0].i_pitch;
        memcpy( p_pixels, p_pixels + 4, 4 );
    }
}

/****************************************************************************
 * Flush: drop everything still in flight, after a seek
 ****************************************************************************
 * Without this the module is simply never told a seek happened, and the card
 * keeps handing over pictures decoded before it, still carrying their old
 * timestamps. The video output judges every one of them stale and drops it,
 * so playback becomes a slideshow while the seek bar advances normally.
 ****************************************************************************/
static void Flush( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* This function must never block and never call into the DIL.
     *
     * It runs on the decoder thread, and the output thread can at this very
     * moment be asleep inside decoder_NewPicture() waiting for a free
     * picture -- paused playback with a full look-ahead cache keeps the
     * pool empty for as long as the pause lasts. The buffers it is waiting
     * for are freed by the core-side vout flush, which happens only AFTER
     * this callback returns: waiting here on anything the output thread
     * holds is a deadlock, not a delay. (The old version held p_sys->lock
     * across a drain of the card and could freeze the whole video pipeline
     * on a seek-while-paused.)
     *
     * So: bump the flush generation and return. The output thread discards
     * every picture decoded under an older generation -- including the
     * held first field of an interlaced pair -- the moment it can run
     * again, and the card itself is flushed by the decoder thread right
     * before the first post-seek input block (see DecodeBlock): the DIL's
     * flush stops and closes the hardware decoder and lets the next
     * DtsProcInput reopen it, so ordering it that way guarantees no
     * post-seek data is ever caught in the flush. */
    /* Follow XBMC, the reference implementation for this hardware: mode 2
     * (input, decoded and to-be-decoded buffers).
     *
     * Do NOT reach for mode 4 ("also flushes the driver's buffers"): it is
     * accepted, and on a short clip the card then never emits another
     * picture at all -- a seek forward freezes the image until the end of
     * the file. Measured on this BCM70015: seeking to 9 s in a 15 s clip
     * yields 0 pictures with mode 4 against 50 with mode 2.
     *
     * VLC_CHD_FLUSHMODE=<n> overrides this for measuring one behaviour
     * against another on real hardware: 0 touches nothing, 1/2/4 force
     * that mode on either chip. */
    static int i_forced_mode = -1;
    if( unlikely(i_forced_mode < 0) )
    {
        const char *psz_mode = getenv( "VLC_CHD_FLUSHMODE" );
        i_forced_mode = psz_mode ? atoi( psz_mode ) : -1;
        if( i_forced_mode < 0 )
            i_forced_mode = -2;   /* unset: use the XBMC behaviour */
    }
    bool b_flush_card = true;
    if( i_forced_mode >= 0 )
    {
        if( i_forced_mode == 0 )
            b_flush_card = false;
        else
            p_sys->i_card_flush_mode = i_forced_mode;
    }

    vlc_mutex_lock( &p_sys->lock );
    p_sys->i_flush_gen++;
    p_sys->b_flush_card = b_flush_card;
    /* Rebuilt from the post-seek input: a backward seek must lower it. */
    p_sys->i_max_in_pts = VLC_TICK_INVALID;
    /* Same reason for the throttle's reference: after a backward seek the
     * pre-seek date sits far in the future and would hold the input back
     * for as long as the seek went back. */
    p_sys->i_last_out_date = VLC_TICK_INVALID;
    /* A seek invalidates any pending keyframe replay. */
    crystal_ReplayClear( p_sys );
    p_sys->i_drop_upto      = VLC_TICK_INVALID;
    /* A flush legitimately gaps the output; don't let its recovery count
     * toward the wedge watchdog until the post-seek IDR is fed. */
    p_sys->i_blocks_since_out = 0;
    p_sys->b_await_idr = true;
    vlc_cond_signal( &p_sys->wait );   /* drain the stale frames promptly */
    vlc_mutex_unlock( &p_sys->lock );

    /* Skip pictures over the next few input blocks so the card can get
     * ahead again instead of decoding everything the seek hands it (XBMC's
     * m_reset = 10). BCM70012 only: tried on the BCM70015 too and it is
     * measurably worse there (recovery after a seek went from 364 ms to
     * 767 ms), which is presumably why XBMC never does it. */
    if( !p_sys->b_flea || i_forced_mode >= 0 )
        p_sys->i_reset = 10;
}

/****************************************************************************
 * crystal_ThrottleLead: keep the card from outrunning the display
 ****************************************************************************
 * Holds the block about to be fed until BOTH are back within bounds:
 *
 *   - the card's in-flight depth, i_pts minus the last picture pulled out,
 *     against CRYSTALHD_MAX_CARD_DEPTH. This is the one that runs away, and
 *     it needs no clock -- so unlike the lead below it also works during the
 *     initial buffering, which is exactly the window the runaway starts in;
 *   - the lead of our output over the clock, against CRYSTALHD_MAX_LEAD, so
 *     the card cannot race ahead of the display until the core starts
 *     refusing its pictures as "early".
 *
 * Runs on the decoder thread: not returning is precisely the point -- it is
 * what stops the decoder fifo from draining, and that back-pressure is what
 * slows the demuxer down. It never blocks the OUTPUT thread, which is the
 * only one that can drain the card, so holding here always resolves itself.
 *
 * Returns as soon as there is any reason not to wait: no picture out yet, a
 * flush or a restart pending, or the decoder closing. When the output goes
 * quiet -- the card wedged rather than merely ahead -- the cap is WIDENED so
 * the recovery paths get the blocks they need to count, never dropped.
 ****************************************************************************/
static void crystal_ThrottleLead( decoder_t *p_dec, const block_t *p_block )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* What this block will ask the card to hold. Undated blocks say nothing
     * about depth; the clock check below still applies to them. */
    const vlc_tick_t i_in = p_block->i_pts != VLC_TICK_INVALID ?
                            p_block->i_pts : p_block->i_dts;

    /* Per-block: when this block started waiting on the approach cap. */
    vlc_tick_t i_approach_since = VLC_TICK_INVALID;
    /* ⚠ And an absolute bound on this block's wait, whatever the reason.
     * Delaying the decoder thread is the whole point here; DEADLOCKING it is
     * a different thing entirely -- it also stops the flush acknowledgement
     * the core waits for on every seek, so a throttle that never returns
     * takes the seek machinery down with it. Past this, feed the block and
     * let the ordinary watchdogs judge. */
    const vlc_tick_t i_block_deadline = mdate() + CRYSTALHD_LEAD_MAX_HOLD;

    for( ;; )
    {
        const vlc_tick_t i_now = mdate();

        vlc_mutex_lock( &p_sys->lock );
        const vlc_tick_t i_date = p_sys->i_last_out_date;
        /* Measured output interval, for the frame-counted approach floor. */
        const vlc_tick_t i_interval = p_sys->i_date_interval;
        const bool b_leave = p_sys->b_stop || p_sys->b_flush_card
                             || p_sys->b_restart;
        /* Freshly rebuilt and not yet producing: see the slack below. */
        const bool b_repriming = p_sys->b_await_idr;
        /* Has the output moved since we last looked? i_hold_since starts at
         * the FIRST call rather than at open, so an output that has simply
         * not started yet is never mistaken for one that has stopped. */
        if( i_date != p_sys->i_hold_date
            || p_sys->i_hold_since == VLC_TICK_INVALID )
        {
            p_sys->i_hold_date  = i_date;
            p_sys->i_hold_since = i_now;
            p_sys->b_hold_given_up = false;
        }
        else if( !p_sys->b_hold_given_up
                 && i_now - p_sys->i_hold_since >= CRYSTALHD_LEAD_MAX_HOLD )
        {
            p_sys->b_hold_given_up = true;
            msg_Dbg( p_dec, "the card has produced nothing for %"PRId64" s: "
                     "widening the cap so the watchdog can see it",
                     (vlc_tick_t)(CRYSTALHD_LEAD_MAX_HOLD / CLOCK_FREQ) );
        }
        /* Silent long past a restart: it is not slow, it is gone. */
        else if( !p_sys->b_want_reload && p_sys->i_restarts > 0
                 && i_date != VLC_TICK_INVALID
                 && i_now - p_sys->i_hold_since >= CRYSTALHD_DEAD_SILENCE )
        {
            msg_Warn( p_dec, "CrystalHD has produced nothing for %"PRId64" s "
                      "after a restart: giving the stream to software",
                      (vlc_tick_t)(CRYSTALHD_DEAD_SILENCE / CLOCK_FREQ) );
            vlc_mutex_lock( &chd_device_lock );
            chd_quarantine_until = mdate() + CRYSTALHD_QUARANTINE;
            vlc_mutex_unlock( &chd_device_lock );
            p_sys->b_want_reload = true;
            /* ⚠ And give the thread back at once. Setting the flag is not
             * enough: DecodeBlock only reads it AFTER this function returns,
             * so looping on here would hold the reload it just asked for --
             * measured, the request was logged and nothing happened, the
             * picture staying frozen to the end of the film. */
            vlc_mutex_unlock( &p_sys->lock );
            return;
        }
        const bool b_given_up = p_sys->b_hold_given_up;

        /* Is a pre-emptive rebuild due? Once the budget is spent, the very
         * next keyframe triggers one -- whenever it turns up. That is the
         * whole condition, and it needs no prediction of where the keyframe
         * is: predicting it from the measured rhythm was tried and missed
         * exactly the irregular ones (this clip has a keyframe at 32.2 s,
         * 1.8 s after the previous, and those flushes kept their full 0.47 s
         * skip while the regular ones fell to 0.23 s). */
        /* ...and only when a rebuild is actually coming. Without the
         * b_needs_preemptive half the counter never resets (nothing rebuilds
         * it), so the tightened cap stayed on for the whole film and starved
         * the card: measured, one 5 s window down to 96 frames and 191 late
         * pictures on a stream that is otherwise flawless. */
        bool b_approach =
            ( p_sys->b_needs_preemptive
              && p_sys->i_blocks_since_reset >= CRYSTALHD_RESET_BUDGET );
        vlc_mutex_unlock( &p_sys->lock );

        /* Bound the approach hold PER BLOCK, not per window: the window spans
         * a second and a half of content, so a deadline started at its first
         * block simply expired and left the rest of the approach unpaced --
         * measured, the depth at the flush stayed at 434-468 ms, the cap
         * never biting at all. Once the depth is down, later blocks pass
         * straight through anyway, so only the first few ever wait. */
        if( !b_approach )
            i_approach_since = VLC_TICK_INVALID;
        else if( i_approach_since == VLC_TICK_INVALID )
            i_approach_since = i_now;
        else if( i_now - i_approach_since >= CRYSTALHD_APPROACH_MAX_HOLD )
            b_approach = false;   /* not worth stalling the run for */

        if( b_leave || i_date == VLC_TICK_INVALID )
            return;
        if( i_now >= i_block_deadline )
        {
            if( !p_sys->b_lead_logged )
            {
                p_sys->b_lead_logged = true;
                msg_Dbg( p_dec, "held this block for %"PRId64" s: feeding it "
                         "anyway rather than stall the decoder thread",
                         (vlc_tick_t)(CRYSTALHD_LEAD_MAX_HOLD / CLOCK_FREQ) );
            }
            return;
        }

        /* Widen the cap when the card needs blocks to recover -- never remove
         * it: whatever is fed past the last picture out is exactly what the
         * next flush will skip. */
        vlc_tick_t i_cap = i_interval > 0 ?
                           CRYSTALHD_DEPTH_FRAMES * i_interval :
                           CRYSTALHD_MAX_CARD_DEPTH;
        if( b_given_up )
            i_cap += CRYSTALHD_DEPTH_SLACK_STALL;
        else if( b_repriming )
            i_cap += CRYSTALHD_DEPTH_SLACK_REPRIME;
        else if( b_approach )
        {
            vlc_tick_t i_floor = i_interval > 0 ?
                                 CRYSTALHD_APPROACH_FRAMES * i_interval :
                                 CRYSTALHD_APPROACH_FALLBACK;
            if( i_cap > i_floor )
                i_cap = i_floor;
        }

        const vlc_tick_t i_depth = ( i_in != VLC_TICK_INVALID ) ?
                                   i_in - i_date : 0;

        /* VLC_TICK_INVALID while the input is still buffering or paused:
         * no clock to place it against, so this half simply does not apply
         * -- the depth check above carries the throttle on its own. */
        vlc_tick_t i_lead = 0;
        const vlc_tick_t i_display = decoder_GetDisplayDate( p_dec, i_date );
        if( i_display != VLC_TICK_INVALID )
            i_lead = i_display - mdate();

        if( i_depth <= i_cap && i_lead <= CRYSTALHD_MAX_LEAD )
            return;

        if( !p_sys->b_lead_logged )
        {
            p_sys->b_lead_logged = true;
            msg_Dbg( p_dec, "holding the input back: the card is sitting on "
                     "%"PRId64" ms of stream, %"PRId64" ms ahead of the clock",
                     i_depth / 1000, i_lead / 1000 );
        }

        msleep( CRYSTALHD_LEAD_SLICE );
    }
}

/****************************************************************************
 * crystal_RebuildAtIdr: rebuild the decoder without losing the reorder tail
 ****************************************************************************
 * Called on the decoder thread, right after a keyframe has been handed to
 * the card and with the rebuild armed (b_replay_pending). Three steps:
 *   1. wait for the card to hand back everything up to that keyframe -- the
 *      keyframe itself is what forces it to, an IDR emptying the DPB;
 *   2. rebuild the decoder, which is now holding nothing worth keeping;
 *   3. feed the keyframe again, so the fresh decoder primes on it.
 * The picture the replay re-emits is a duplicate of one already delivered;
 * i_drop_upto suppresses it in PullPictures.
 * Every wait is bounded, and a stop/flush/restart abandons the sequence --
 * the rebuild then simply does not happen and the budget carries over.
 ****************************************************************************/
/* Drop the replay queue. Call with the lock held. */
static void crystal_ReplayClear( decoder_sys_t *p_sys )
{
    block_ChainRelease( p_sys->p_replay_head );
    p_sys->p_replay_head   = NULL;
    p_sys->p_replay_tail   = NULL;
    p_sys->i_replay_blocks = 0;
    p_sys->b_replay_pending = false;
    p_sys->i_replay_target = VLC_TICK_INVALID;
    p_sys->i_replay_seen   = VLC_TICK_INVALID;
    p_sys->i_replay_moved  = VLC_TICK_INVALID;
}

/* Append a copy of a block just fed to the card. Lock held. */
static void crystal_ReplayAppend( decoder_sys_t *p_sys, const block_t *p_block )
{
    block_t *p_copy = block_Duplicate( (block_t *)p_block );
    if( !p_copy )                 /* out of memory: give up on the replay */
    {
        crystal_ReplayClear( p_sys );
        return;
    }
    p_copy->p_next = NULL;
    if( p_sys->p_replay_tail )
        p_sys->p_replay_tail->p_next = p_copy;
    else
        p_sys->p_replay_head = p_copy;
    p_sys->p_replay_tail = p_copy;
    p_sys->i_replay_blocks++;
}

static void crystal_RebuildAtIdr( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    vlc_mutex_lock( &p_sys->lock );

    if( p_sys->b_stop || p_sys->b_flush_card || p_sys->b_restart )
    {
        crystal_ReplayClear( p_sys );
        vlc_mutex_unlock( &p_sys->lock );
        return;
    }

    /* 1. Let the card empty itself. The keyframe now sitting in it is what
     *    makes it do so -- an IDR empties the DPB, so every picture it was
     *    holding must come out first. Wait only while it is still giving
     *    something back: waiting for the keyframe's own date to be REACHED
     *    runs to the bound every time, since the card keeps two or three
     *    frames whatever happens. Measured that way the rebuild cost 1.9 s
     *    of frozen picture against a vout lead of about one second, 198 late
     *    pictures where there had been 3. */
    const vlc_tick_t i_target = p_sys->i_replay_target;
    const vlc_tick_t i_end = mdate() + CRYSTALHD_REPLAY_WAIT;
    vlc_tick_t i_seen = p_sys->i_last_out_date;
    vlc_tick_t i_moved = mdate();
    while( !p_sys->b_stop && !p_sys->b_flush_card && !p_sys->b_restart
           && i_target != VLC_TICK_INVALID
           && ( p_sys->i_last_out_date == VLC_TICK_INVALID
                || p_sys->i_last_out_date < i_target )
           && mdate() < i_end )
    {
        /* ⚠ Ask the CARD whether it still holds anything, do not infer it
         * from the output going quiet. The output thread is paced by the
         * picture pool, itself paced by the vout in real time, so a card
         * with two frames still ready looks exactly like a card with none
         * -- and flushing on that signal threw those two away, once per
         * keyframe. ReadyListCount says it outright. The quiet check stays
         * as the fallback for a card that stops answering. */
        BC_DTS_STATUS st;
        memset( &st, 0, sizeof(st) );
        const bool b_status =
            BC_FUNC_PSYS(DtsGetDriverStatus)( p_sys->bcm_handle, &st )
                == BC_STS_SUCCESS;

        if( p_sys->i_last_out_date != i_seen )
        {
            i_seen  = p_sys->i_last_out_date;
            i_moved = mdate();
        }
        else if( b_status && st.ReadyListCount == 0
                 && mdate() - i_moved >= CRYSTALHD_REPLAY_QUIET )
            break;      /* nothing left in it, and nothing in flight */
        else if( mdate() - i_moved >= CRYSTALHD_REPLAY_STUCK )
            break;      /* it has stopped answering: do not wait on it */

        vlc_mutex_unlock( &p_sys->lock );
        msleep( CRYSTALHD_LEAD_SLICE );
        vlc_mutex_lock( &p_sys->lock );
    }

    if( p_sys->b_stop || p_sys->b_flush_card || p_sys->b_restart )
    {
        crystal_ReplayClear( p_sys );
        vlc_mutex_unlock( &p_sys->lock );
        return;
    }

    /* 2. Whatever it handed over must not be handed over twice: the replay
     *    decodes the keyframe again. */
    p_sys->i_drop_upto = p_sys->i_last_out_date;

    /* Rebuild, on the output thread as always. */
    p_sys->b_restart = true;
    vlc_cond_signal( &p_sys->wait );
    const vlc_tick_t i_deadline = mdate() + CRYSTALHD_RESTART_WAIT;
    while( p_sys->b_restart && !p_sys->b_stop )
        if( vlc_cond_timedwait( &p_sys->reset_done, &p_sys->lock, i_deadline ) )
            break;
    const bool b_ready = ( !p_sys->b_restart && !p_sys->b_stop );

    block_t *p_replay = p_sys->p_replay_head;
    p_sys->p_replay_head   = NULL;
    p_sys->p_replay_tail   = NULL;
    p_sys->i_replay_blocks = 0;
    p_sys->b_replay_pending = false;
    p_sys->i_replay_target = VLC_TICK_INVALID;
    p_sys->i_replay_seen   = VLC_TICK_INVALID;
    p_sys->i_replay_moved  = VLC_TICK_INVALID;
    if( !b_ready )
        p_sys->i_drop_upto = VLC_TICK_INVALID;
    vlc_mutex_unlock( &p_sys->lock );

    /* Hand the fresh decoder the exact same sequence, starting at the
     * keyframe it needs to prime on. */
    while( p_replay )
    {
        block_t *p_next = p_replay->p_next;
        if( b_ready )
            BC_FUNC_PSYS(DtsProcInput)( p_sys->bcm_handle,
                        p_replay->p_buffer, p_replay->i_buffer,
                        p_replay->i_pts > VLC_TICK_INVALID ?
                            TO_BC_PTS(p_replay->i_pts) : 0, false );
        p_replay->p_next = NULL;
        block_Release( p_replay );
        p_replay = p_next;
    }
}

/****************************************************************************
 * DecodeBlock: the whole thing
 ****************************************************************************/
static int DecodeBlock( decoder_t *p_dec, block_t *p_block )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* Timestamp/queue tracing, off unless VLC_CHD_TRACE is set. Resolved once
     * rather than per picture: this sits in the decoding path. */
    static int i_trace = -1;
    if( unlikely(i_trace < 0) )
        i_trace = (getenv( "VLC_CHD_TRACE" ) != NULL);

    BC_DTS_STATUS driver_stat;

    /* Hold the input back while the card is too far ahead of the clock (see
     * CRYSTALHD_MAX_LEAD). Done before anything else, and only for a real
     * block: a drain (p_block == NULL) must never be delayed. */
    if( p_block != NULL )
        crystal_ThrottleLead( p_dec, p_block );

    /* Hardware restart pending: the wedge watchdog fired and the output
     * thread is (or is about to be) rebuilding the decoder. Feed it
     * nothing until it has, and drop this block -- the stream will
     * re-prime from the next input. */
    vlc_mutex_lock( &p_sys->lock );
    const bool b_restart_pending = p_sys->b_restart;
    const bool b_want_reload = p_sys->b_want_reload;
    vlc_mutex_unlock( &p_sys->lock );

    /* The card is unrecoverable on this stream: ask the core to reload the
     * decoder. It re-probes, crystalhd declines (quarantine), and avcodec
     * takes over. Contract: do NOT release or modify p_block on RELOAD --
     * the same block is fed to the next module. */
    if( unlikely(b_want_reload) )
        return VLCDEC_RELOAD;

    if( unlikely(b_restart_pending) && p_block != NULL )
    {
        /* Wait the restart out instead of throwing the block away. Rebuilding
         * the decoder takes the card a long time (measured below), and this
         * branch used to discard every block for its whole duration -- over
         * 300 of them on a 720p30 stream, ten seconds of video gone, picture
         * frozen with the audio playing on. Nothing here needs the decoder
         * thread, so waiting simply applies back-pressure: the fifo backs up
         * into es_out, the demuxer slows down, and not one byte is lost.
         * Bounded and interruptible all the same -- a restart that never
         * completes must not hold playback hostage, and past the bound the
         * old behaviour (drop) is the safety net. */
        vlc_mutex_lock( &p_sys->lock );
        const vlc_tick_t i_deadline = mdate() + CRYSTALHD_RESTART_WAIT;
        while( p_sys->b_restart && !p_sys->b_stop )
            if( vlc_cond_timedwait( &p_sys->reset_done, &p_sys->lock,
                                    i_deadline ) )
                break;
        const bool b_still_restarting = p_sys->b_restart;
        vlc_mutex_unlock( &p_sys->lock );

        if( b_still_restarting )
        {
            static unsigned s_dropped = 0;
            if( ( s_dropped++ % 50 ) == 0 )
                msg_Warn( p_dec, "bloc jete: le redemarrage n'en finit pas "
                          "(%u depuis le debut)", s_dropped );
            block_Release( p_block );
            return VLCDEC_SUCCESS;
        }
        /* Restart done: fall through and feed this block normally. */
    }
    else if( unlikely(b_restart_pending) )
        return VLCDEC_SUCCESS;   /* drain request during a restart */

    /* Deferred card flush from Flush(): performed here, on the decoder
     * thread, before the first post-seek input reaches the card. The DIL
     * stops and closes the hardware decoder during this call and the
     * DtsProcInput below transparently reopens it. */
    if( unlikely(p_sys->b_flush_card) )
    {
        if( BC_FUNC_PSYS(DtsFlushInput)( p_sys->bcm_handle,
                                         p_sys->i_card_flush_mode )
                != BC_STS_SUCCESS )
            msg_Warn( p_dec, "CrystalHD: flushing the decoder failed" );
        /* Cleared only once the card is really flushed: up to this point
         * the output thread treats everything the card delivers as
         * pre-seek and discards it. */
        vlc_mutex_lock( &p_sys->lock );
        p_sys->b_flush_card = false;
        vlc_mutex_unlock( &p_sys->lock );
    }

    /* First check the status of the decode to produce pictures */
    if( BC_FUNC_PSYS(DtsGetDriverStatus)( p_sys->bcm_handle, &driver_stat ) != BC_STS_SUCCESS )
    {
        if( p_block )   /* pf_decode(NULL) is the drain request at EOS */
            block_Release( p_block );
        return VLCDEC_SUCCESS;
    }

    if( p_block )
    {
        if( unlikely(i_trace) )
            msg_Dbg( p_dec, "CHDTRACE in  pts=%"PRId64" now=%"PRId64
                            " ready=%u free=%u",
                     p_block->i_pts, mdate(),
                     driver_stat.ReadyListCount, driver_stat.FreeListCount );

        if( ( p_block->i_flags & (BLOCK_FLAG_CORRUPTED) ) == 0 )
        {
            /* Re-inject SPS/PPS ahead of every IDR (avc1 keeps its
             * parameter sets out of band, in avcC, so the elementary
             * stream carries none). The DIL sends the stored ones only
             * once, before the first frame; without fresh parameter sets
             * the BCM70015 wedges after only a couple of IDRs. Feeding
             * them at each IDR, in the stream's own length-prefixed form,
             * pushes the stall out to ~7 IDRs (measured) -- it does not
             * cure the card's per-IDR leak, but it maximises the runway
             * between the resets that do. This is what XBMC does; the DIL
             * sees the sets are already present and does not double them. */
            /* Strip what stops this card dead before anything else
             * looks at the block. */
            p_block = crystal_strip_eos( p_dec, p_block );
            p_block = crystal_maybe_prepend_spspps( p_dec, p_block );
            if( !p_block )
                return VLCDEC_SUCCESS;

            if( p_block->i_pts > VLC_TICK_INVALID )
            {
                vlc_mutex_lock( &p_sys->lock );
                if( p_sys->i_max_in_pts == VLC_TICK_INVALID ||
                    p_block->i_pts > p_sys->i_max_in_pts )
                    p_sys->i_max_in_pts = p_block->i_pts;
                vlc_mutex_unlock( &p_sys->lock );
            }

            /* Valid input block, so we can send to HW to decode */
            /* Strictly greater: VLC_TICK_INVALID means "no timestamp", and
             * the old >= comparison was always true -- an undated block got
             * TO_BC_PTS(0) = 1, which the card echoed back as an almost-zero
             * timestamp instead of the "none" (0) the output path expects. */
            BC_STATUS status = BC_FUNC_PSYS(DtsProcInput)( p_sys->bcm_handle,
                                            p_block->p_buffer,
                                            p_block->i_buffer,
                                            p_block->i_pts > VLC_TICK_INVALID ? TO_BC_PTS(p_block->i_pts) : 0, false );

            /* Kept until the replay bookkeeping below is done with it. */
            block_t *p_last_fed = p_block;

            /* A rebuild is armed: keep feeding the card -- that is what
             * makes it release the previous GOP's reorder tail, an IDR
             * emptying the DPB -- and keep a copy of everything fed, so the
             * rebuilt decoder can be given the same sequence back.
             * Rebuild once the card has either reached the keyframe or gone
             * quiet, i.e. once it has given back all it means to. */
            vlc_mutex_lock( &p_sys->lock );
            bool b_rebuild = false;
            if( unlikely(p_sys->b_replay_pending) )
            {
                if( status == BC_STS_SUCCESS )
                    crystal_ReplayAppend( p_sys, p_last_fed );
                b_rebuild = ( p_sys->b_replay_pending
                              && p_sys->i_replay_blocks > 0 );
            }
            vlc_mutex_unlock( &p_sys->lock );
            block_Release( p_last_fed );
            if( unlikely(b_rebuild) )
                crystal_RebuildAtIdr( p_dec );

            if( status != BC_STS_SUCCESS )
            {
                /* Diagnostic: the input side refusing data is one way the
                 * card can silently stop. Rate-limited so a persistent
                 * failure does not flood. */
                static unsigned i_in_err = 0;
                if( ( i_in_err++ % 64 ) == 0 )
                    msg_Warn( p_dec, "DtsProcInput refused a block: status %d "
                              "(ready=%u free=%u)", status,
                              driver_stat.ReadyListCount,
                              driver_stat.FreeListCount );
                return VLCDEC_SUCCESS;
            }

            /* Wedge watchdog: the card takes blocks but the output thread
             * has produced no picture in a long while -- the large-keyframe
             * stall (see i_blocks_since_out): ready list forever empty, no
             * error anywhere, picture frozen with the audio playing on.
             * Priming a healthy decoder never needs more than a couple
             * dozen blocks, so ask the output thread to rebuild the
             * decoder. */
            vlc_mutex_lock( &p_sys->lock );
            unsigned i_dry = ++p_sys->i_blocks_since_out;
            p_sys->i_blocks_since_reset++;
            /* Rate-limited in wall time rather than hard-capped: never
             * give up the hardware for good (a hard cap once froze the
             * picture dead), never spin (the device reset is heavy). The
             * ultimate give-up is elsewhere: two resets that produce no
             * picture quarantine the card and fall back to software.
             * A wider bound while re-priming (b_await_idr) than in steady
             * playback: the card is meant to output nothing until it has
             * digested a fresh IDR and any seek preroll. */
            unsigned i_threshold = p_sys->b_await_idr ? CRYSTALHD_REPRIME_BLOCKS
                                                      : CRYSTALHD_WEDGE_BLOCKS;
            bool b_stalled = ( i_dry >= i_threshold &&
                               !p_sys->b_restart &&
                               ( p_sys->i_last_restart == VLC_TICK_INVALID ||
                                 mdate() - p_sys->i_last_restart
                                     > CRYSTALHD_RESTART_COOLDOWN ) );
            vlc_mutex_unlock( &p_sys->lock );

            if( b_stalled )
            {
                /* Snapshot the card's queue state at the wedge: a full
                 * ready list that never drains points at the output/pool
                 * side, an empty one that never fills at the decode side.
                 * This is the datum the whole freeze hunt kept lacking. */
                BC_DTS_STATUS st;
                bool b_status = BC_FUNC_PSYS(DtsGetDriverStatus)(
                                    p_sys->bcm_handle, &st ) == BC_STS_SUCCESS;
                if( b_status )
                    msg_Warn( p_dec, "wedge after IDR #%u: ready=%u free=%u "
                              "captured=%u dropped=%u input=%u inputBusy=%u "
                              "PIBmiss=%u cpbEmpty=%u txBuf=%u",
                              p_sys->i_idr_seen,
                              st.ReadyListCount, st.FreeListCount,
                              st.FramesCaptured, st.FramesDropped,
                              st.InputCount, st.InputBusyCount,
                              st.PIBMissCount, st.cpbEmptySize,
                              st.TxBufData );

                /* And now act on it. A ready list with pictures in it means
                 * the card is decoding perfectly well and WE are the ones
                 * not collecting -- the picture pool is empty, because the
                 * pipeline is trying to run further ahead than the pool can
                 * hold. That is ordinary back-pressure, not a wedge, and the
                 * core says as much on the same line of the log ("buffer
                 * deadlock prevented"). Restarting the card there is not
                 * merely useless, it is destructive: it throws away every
                 * decoded frame still in the ready list, produces no picture
                 * (there is nowhere to put one), and so counts as a dead
                 * reset -- two of those and the card is quarantined into
                 * software for the whole stream. Measured on a 1800x1080
                 * Invidious stream: 5 s of buffering against a 28-picture
                 * pool (1.2 s at 24 fps), the pool empties, and a working
                 * card was being retired after three IDRs.
                 * Give the output side a fresh window instead; if the card
                 * really does go dry later, the counter builds again and the
                 * restart happens then. */
                if( b_status && st.ReadyListCount > 0 )
                {
                    if( !p_sys->b_pool_stall_logged )
                    {
                        p_sys->b_pool_stall_logged = true;
                        msg_Warn( p_dec, "the card has %u pictures waiting and "
                                  "no free buffer left: the stall is on our "
                                  "side (empty picture pool), not the card's. "
                                  "Not restarting it.", st.ReadyListCount );
                    }
                    vlc_mutex_lock( &p_sys->lock );
                    p_sys->i_blocks_since_out = 0;
                    vlc_mutex_unlock( &p_sys->lock );
                }
                else
                {
                    vlc_mutex_lock( &p_sys->lock );
                    bool b_ask_restart = !p_sys->b_restart;
                    if( b_ask_restart )
                        p_sys->b_restart = true;
                    vlc_mutex_unlock( &p_sys->lock );
                    if( b_ask_restart )
                    {
                        vlc_cond_signal( &p_sys->wait );
                        return VLCDEC_SUCCESS;
                    }
                }
            }

            /* Catch-up after a seek, as XBMC does: skip pictures for a few
             * blocks so the card can get back ahead of the clock, then put it
             * back to normal. BCM70012 only -- tried on the BCM70015 too and
             * it is measurably worse there (recovery after a seek went from
             * 364 ms to 767 ms), which is presumably why XBMC never does it. */
            if( !p_sys->b_flea )
            {
                if( p_sys->i_reset > 0 )
                {
                    p_sys->i_reset--;
                    if( !p_sys->b_skip_mode )
                    {
                        p_sys->b_skip_mode = true;
                        BC_FUNC_PSYS(DtsSetSkipPictureMode)( p_sys->bcm_handle, 1 );
                    }
                }
                else if( p_sys->b_skip_mode )
                {
                    p_sys->b_skip_mode = false;
                    BC_FUNC_PSYS(DtsSetSkipPictureMode)( p_sys->bcm_handle, 0 );
                }
            }
        }
    }
#ifdef DEBUG_CRYSTALHD
    else
    {
        if( driver_stat.ReadyListCount != 0 )
            msg_Err( p_dec, " Input NULL but have pictures %u", driver_stat.ReadyListCount );
    }
#endif

    /* Nothing else to do here: the output thread empties the card's ready
     * list on its own, which is what keeps the card decoding. */
    return VLCDEC_SUCCESS;
}

/****************************************************************************
 * PullPictures: take everything the card has finished decoding
 ****************************************************************************
 * Called from the output thread, WITHOUT p_sys->lock: the callback inside
 * DtsProcOutput allocates from the video output's picture pool and can
 * legitimately sleep there for as long as the pool stays empty (paused
 * playback with a full look-ahead cache). Nothing that another thread needs
 * may be held across that sleep. The callback state (p_pic, proc_out, the
 * dating fields) needs no lock at all: this thread is the only DtsProcOutput
 * caller, so it is the only one to touch it. The flush generation is the
 * one shared piece, read under lock at each turn of the drain loop.
 *
 * The card holds several decoded frames and stops decoding altogether once
 * its ready list is full, so this must run continuously rather than once
 * per input block: that is the whole point of the thread, and what XBMC's
 * CMPCOutputThread does.
 *
 * Returns true when at least one picture was handed to the video output, so
 * the caller can come straight back instead of waiting.
 ****************************************************************************/
static bool PullPictures( decoder_t *p_dec )
{
    decoder_sys_t *p_sys = p_dec->p_sys;
    BC_DTS_PROC_OUT proc_out;
    BC_DTS_STATUS driver_stat;
    bool b_queued = false;

    /* Timestamp/queue tracing, off unless VLC_CHD_TRACE is set. */
    static int i_trace = -1;
    if( unlikely(i_trace < 0) )
        i_trace = (getenv( "VLC_CHD_TRACE" ) != NULL);

    if( BC_FUNC_PSYS(DtsGetDriverStatus)( p_sys->bcm_handle, &driver_stat )
            != BC_STS_SUCCESS )
        return false;

    /* Drain the card's ready list instead of taking a single picture per input
     * block. The hardware holds up to BC_RX_LIST_CNT frames, and pulling only
     * one at a time leaves that queue permanently full: every picture then
     * reaches the video output around five frames late and is dropped as
     * stale, which looks like a slideshow even though the card is barely
     * working. The bound is a safety net -- the queue holds BC_RX_LIST_CNT (8)
     * frames on Darwin, and a status read that stops decreasing must not spin
     * forever. */
    for( unsigned i_drained = 0; i_drained < CRYSTALHD_MAX_DRAIN; i_drained++ )
    {
    if( driver_stat.ReadyListCount == 0 )
        break;

    /* Snapshot the flush generation for this pull, and drop a held first
     * field left over from before a flush: pairing it with a post-seek
     * second field would show a frankenstein frame. */
    vlc_mutex_lock( &p_sys->lock );
    const unsigned i_gen = p_sys->i_flush_gen;
    const bool b_flush_pending = p_sys->b_flush_card;
    vlc_mutex_unlock( &p_sys->lock );
    if( p_sys->p_pic && p_sys->i_pic_gen != i_gen )
    {
        picture_Release( p_sys->p_pic );
        p_sys->p_pic = NULL;
        p_sys->i_last_date = VLC_TICK_INVALID;
        p_sys->i_extrapolated = 0;
    }
    picture_t *p_before = p_sys->p_pic;

    /* Prepare the Output structure. We always expect and use YUY2.
     *
     * The structure starts fully zeroed; crystal_PrepareOutput fills in the
     * buffer, the stride and -- once the geometry is settled -- PicInfo, which
     * BC_POUT_FLAGS_SIZE turns into a request rather than an answer. It must
     * not be preset before that point: echoing the open-time resolution hint
     * back at the card is what made it report a spurious format change. */
    memset( &proc_out, 0, sizeof(BC_DTS_PROC_OUT) );
    p_sys->proc_out         = &proc_out;

    /* Hand it the picture to fill, before the call and not from a callback:
     * see crystal_PrepareOutput. */
    BC_STATUS sts = crystal_PrepareOutput( p_dec, &proc_out );
    if( sts != BC_STS_SUCCESS )
        return false;

    sts = BC_FUNC_PSYS(DtsProcOutput)( p_sys->bcm_handle, 128, &proc_out );
#ifdef DEBUG_CRYSTALHD
    if( sts != BC_STS_SUCCESS )
        msg_Err( p_dec, "DtsProcOutput returned %i", sts );
#endif

    /* The callback allocated the picture under this pull's generation. */
    if( p_sys->p_pic != p_before )
        p_sys->i_pic_gen = i_gen;

    uint8_t b_eos;
    /* Whether to look for another picture once this one is dealt with. Only
     * the paths that consumed something from the queue set it. */
    bool b_drain_more = false;
    picture_t *p_pic = p_sys->p_pic;
    switch( sts )
    {
        case BC_STS_SUCCESS:
            /* Once per decoder: what the card says it actually delivered.
             * YBuffDoneSz is the byte count it transferred, so comparing it
             * with pitch * height says immediately whether the picture was
             * filled whole or only in part -- the unwritten remainder shows
             * up as green, YUY2 zero being green rather than black. */
            /* No format change came, but a picture did: take the geometry
             * from it. Some streams never trigger BC_STS_FMT_CHANGE, and
             * without this the probe buffer would be used forever and not a
             * frame would ever reach the core. */
            if( !p_sys->b_geometry_known )
            {
                unsigned w = proc_out.PicInfo.width;
                unsigned h = proc_out.PicInfo.height == 1088 ?
                                 1080 : proc_out.PicInfo.height;
                if( w > 0 && h > 0 )
                {
                    msg_Dbg( p_dec, "card settles on %ux%u; configuring the "
                                    "core for that", w, h );
                    p_dec->fmt_out.video.i_width  = crystal_QuantisedStride( w );
                    p_dec->fmt_out.video.i_height = h;
                    p_dec->fmt_out.video.i_visible_width  = w;
                    p_dec->fmt_out.video.i_visible_height = h;
                }
                p_sys->b_geometry_known = true;
                free( p_sys->p_probe_buf );
                p_sys->p_probe_buf = NULL;
                b_drain_more = true;
                break;      /* this one went into the probe buffer */
            }

            if( !p_sys->b_output_logged )
            {
                p_sys->b_output_logged = true;
                msg_Dbg( p_dec, "card delivered: %ux%u, %u B transferred "
                                "(a full picture would be %d B), 422 mode %u, "
                                "PicInfo flags 0x%x, discontinuities %u",
                         proc_out.PicInfo.width, proc_out.PicInfo.height,
                         proc_out.YBuffDoneSz,
                         p_sys->p_pic ? p_sys->p_pic->p[0].i_pitch
                                        * p_sys->p_pic->p[0].i_visible_lines : 0,
                         proc_out.b422Mode, proc_out.PicInfo.flags,
                         proc_out.discCnt );
            }
            if( !(proc_out.PoutFlags & BC_POUT_FLAGS_PIB_VALID) )
            {
                msg_Dbg( p_dec, "Invalid PIB" );
                break;
            }

            if( !p_pic )
                break;

            /* In interlaced mode, do not push the first field in the pipeline.
             * Keep p_sys->p_pic: the callback reuses that very picture for the
             * second field rather than allocating another one. */
            if( (proc_out.PicInfo.flags & VDEC_FLAG_INTERLACED_SRC) &&
               !(proc_out.PicInfo.flags & VDEC_FLAG_FIELDPAIR) )
            {
                p_pic = NULL;
                p_sys->b_interlaced   = true;
                p_sys->b_second_field = true;   /* next call fills the pair */
                b_drain_more = true;
                break;
            }

            /* Interlace attributes come from the PicInfo the card just
             * returned; they could not be known when the buffer was handed
             * over. Also remember, for the next buffer, whether the source
             * is interlaced and whether the next output is this pair's
             * second field. */
            p_pic->b_progressive     = !(proc_out.PicInfo.flags & VDEC_FLAG_INTERLACED_SRC);
            p_pic->b_top_field_first = !(proc_out.PicInfo.flags & VDEC_FLAG_BOTTOM_FIRST);
            p_pic->i_nb_fields       = p_pic->b_progressive ? 1 : 2;
            p_sys->b_interlaced      = !p_pic->b_progressive;
            p_sys->b_second_field    = false;

            //  crystal_CopyPicture( p_pic, &proc_out );
            crystal_FixGreenPixel( p_pic );

            /* Date the picture. When the card delivers one without a
             * timestamp, extrapolate from the previous picture instead of
             * queueing it undated: the core drops undated pictures with a
             * "non-dated video buffer received" warning, one skipped frame
             * -- a visible hitch -- each time. Bounded, so a wholesale
             * timestamp loss cannot run away from the real timeline. */
            {
                vlc_tick_t date = proc_out.PicInfo.timeStamp > 0 ?
                          FROM_BC_PTS(proc_out.PicInfo.timeStamp) : VLC_TICK_INVALID;

                /* The card cannot output a timestamp it was never fed:
                 * anything beyond the highest input pts (plus pipeline
                 * slack) is bogus, and one such date parks the video
                 * output for good (it waits for that far-future instant at
                 * the head of its queue). Demote it to "no timestamp": the
                 * extrapolation below rebuilds a sane date from the
                 * previous picture. */
                /* Not while a card flush is pending: those frames are
                 * discarded whole a few lines below, and running them
                 * through this gate first (max necessarily INVALID, the
                 * flush reset it) would only spam the log with discards
                 * of frames that were already dead. */
                if( date != VLC_TICK_INVALID && !b_flush_pending )
                {
                    vlc_mutex_lock( &p_sys->lock );
                    const vlc_tick_t i_max_in = p_sys->i_max_in_pts;
                    vlc_mutex_unlock( &p_sys->lock );
                    if( i_max_in == VLC_TICK_INVALID ||
                        date > i_max_in + CLOCK_FREQ )
                    {
                        msg_Dbg( p_dec, "CrystalHD: discarding bogus output "
                                 "timestamp %"PRId64" (max input pts %"PRId64")",
                                 date, i_max_in );
                        date = VLC_TICK_INVALID;
                    }
                }

                if( date != VLC_TICK_INVALID )
                {
                    if( p_sys->i_last_date != VLC_TICK_INVALID &&
                        date > p_sys->i_last_date &&
                        date - p_sys->i_last_date < CLOCK_FREQ )
                        p_sys->i_date_interval = date - p_sys->i_last_date;
                    p_sys->i_extrapolated = 0;
                }
                else if( p_sys->i_last_date != VLC_TICK_INVALID &&
                         p_sys->i_date_interval > 0 &&
                         p_sys->i_extrapolated < CRYSTALHD_MAX_EXTRAPOLATE )
                {
                    date = p_sys->i_last_date + p_sys->i_date_interval;
                    p_sys->i_extrapolated++;
                }
                if( date != VLC_TICK_INVALID )
                    p_sys->i_last_date = date;
                p_pic->date = date;

                /* ⚠ i_last_out_date is NOT published here. This picture may
                 * still be dropped a few lines below -- as a pre-seek stale
                 * frame, or as the duplicate of a replayed keyframe -- and
                 * publishing the date of a picture nobody will ever see
                 * poisons the throttle's only reference.
                 *
                 * That is a DEADLOCK, not a glitch: Flush() clears the
                 * reference on a seek, the card then hands back one frame
                 * from BEFORE the seek, its old date lands here, and the
                 * depth to the new position reads as enormous. The throttle
                 * holds the decoder thread, so the card is never fed, so no
                 * newer picture can ever come out. The core then waits five
                 * seconds for a flush acknowledgement that cannot come and
                 * gives up -- measured on a seek torture: 24 pictures in four
                 * minutes, "sitting on 17166 ms of stream", 22 timed-out
                 * flushes, and not one watchdog fired because the card was
                 * perfectly healthy. Published below, once the picture is
                 * actually kept. */
            }

            /* Re-prime parasite drop. Right after a reset the card re-emits
             * one frame the flushed pipeline still held, WITHOUT a timestamp
             * (the DIL loses the PTS association across the Close/Open, and
             * the reset cleared i_last_date so the extrapolation above cannot
             * rebuild one either). Queued undated, the core logs "non-dated
             * video buffer received" and mishandles it -- measured as exactly
             * one "picture is too late (missing 303 ms)" drop per reset, i.e.
             * one visible skipped frame every ~7 s: the whole residual judder
             * once the wedges themselves are pre-empted. Drop it here instead
             * and hold the re-prime gate: the card's very next frame carries a
             * real PTS (the genuine post-reset content, already ~2 s ahead in
             * the look-ahead) and resumes the timeline seamlessly, so the core
             * never sees the undated parasite at all. Steady state is
             * untouched (b_await_idr is false there, and a legitimately
             * undated frame is still extrapolated); the wide REPRIME watchdog
             * still bounds the gate should nothing datable ever arrive. */
            {
                vlc_mutex_lock( &p_sys->lock );
                const bool b_repriming = p_sys->b_await_idr;
                vlc_mutex_unlock( &p_sys->lock );
                if( b_repriming && p_pic->date == VLC_TICK_INVALID )
                {
                    picture_Release( p_pic );
                    p_pic = NULL;
                    p_sys->p_pic = NULL;
                    b_drain_more = true;
                    break;
                }
            }

            /* Duplicate of the keyframe that was replayed across a rebuild
             * (see crystal_RebuildAtIdr): its picture went out before the
             * flush, this is the same one decoded again. */
            if( p_pic->date != VLC_TICK_INVALID )
            {
                vlc_mutex_lock( &p_sys->lock );
                const bool b_dup = ( p_sys->i_drop_upto != VLC_TICK_INVALID
                                     && p_pic->date <= p_sys->i_drop_upto );
                if( !b_dup )
                    p_sys->i_drop_upto = VLC_TICK_INVALID;
                vlc_mutex_unlock( &p_sys->lock );
                if( b_dup )
                {
                    picture_Release( p_pic );
                    p_pic = NULL;
                    p_sys->p_pic = NULL;
                    b_drain_more = true;
                    break;
                }
            }

            if( unlikely(i_trace) )
                msg_Dbg( p_dec, "CHDTRACE out raw=%"PRIu64" pts=%"PRId64
                                " now=%"PRId64" delta=%"PRId64" ready=%u free=%u",
                         (uint64_t)proc_out.PicInfo.timeStamp, p_pic->date,
                         mdate(), p_pic->date - mdate(),
                         driver_stat.ReadyListCount, driver_stat.FreeListCount );
#ifdef DEBUG_CRYSTALHD
            msg_Dbg( p_dec, "TS Output is %"PRIu64, p_pic->date);
#endif
            /* A flush may have landed while this frame was being pulled --
             * it is then a pre-seek frame -- and as long as the deferred
             * card flush has not run yet (b_flush_card), EVERYTHING the
             * card delivers is still pre-seek: the frames it held at
             * Flush() time get pulled under the new generation, and on a
             * network stream that window spans the whole post-seek
             * rebuffering. Queueing them sent old-clock timestamps into
             * the video output and froze it (measured 08/08/2026).
             * Discard, do not queue.
             * (Checked without holding the lock across decoder_QueueVideo;
             * a flush arriving in the hairline between this check and the
             * queueing lets one stale frame through, which the video
             * output then drops on its own as late -- harmless.) */
            vlc_mutex_lock( &p_sys->lock );
            {
                const bool b_stale = ( i_gen != p_sys->i_flush_gen )
                                  || b_flush_pending
                                  || p_sys->b_flush_card;
                vlc_mutex_unlock( &p_sys->lock );
                if( b_stale )
                {
                    picture_Release( p_pic );
                    p_pic = NULL;
                    p_sys->p_pic = NULL;
                    p_sys->i_last_date = VLC_TICK_INVALID;
                    p_sys->i_extrapolated = 0;
                    b_drain_more = true;   /* keep draining the stale batch */
                    break;
                }
            }

            /* Now that it is really going out, it is a valid reference for
             * the lead throttle (see the note where this used to be done). */
            if( p_pic->date != VLC_TICK_INVALID )
            {
                vlc_mutex_lock( &p_sys->lock );
                p_sys->i_last_out_date = p_pic->date;
                vlc_mutex_unlock( &p_sys->lock );
            }

            decoder_QueueVideo( p_dec, p_pic );
            b_queued = true;

            /* A picture came out: the card is alive and past any re-prime,
             * so reset the wedge watchdog, lift the re-prime gate, and
             * clear the unrecoverable-reset counter. */
            vlc_mutex_lock( &p_sys->lock );
            p_sys->i_blocks_since_out = 0;
            p_sys->b_await_idr = false;
            p_sys->i_dead_resets = 0;
            vlc_mutex_unlock( &p_sys->lock );

            /* Handed over to the video output: drop our reference so the
             * cleanup below does not release it, and let the callback build a
             * fresh picture for the next frame. */
            p_pic = NULL;
            p_sys->p_pic = NULL;
            b_drain_more = true;
            break;

        case BC_STS_DEC_NOT_OPEN:
        case BC_STS_DEC_NOT_STARTED:
            /* Normal right after a card flush: the DIL closes the hardware
             * decoder and the next input block reopens it. Nothing to pull
             * until then. */
            break;

        case BC_STS_INV_ARG:
            msg_Warn( p_dec, "Invalid arguments. Please report" );
            break;

        case BC_STS_FMT_CHANGE:    /* Format change */
        {
            /* if( !(proc_out.PoutFlags & BC_POUT_FLAGS_PIB_VALID) )
                break; */
            unsigned i_new_w = proc_out.PicInfo.width;
            unsigned i_new_h = proc_out.PicInfo.height;
            if( i_new_h == 1088 )
                i_new_h = 1080;

            /* Believe what the card reports. An earlier version of this
             * code refused any announcement smaller than the container, on
             * the theory that it was the open-time hint echoing back. It was
             * not: the card really was decoding to 720p, because the input
             * format had not been told otherwise (see
             * CRYSTALHD_INPUT_OPTFLAGS). Refusing the report only turned a
             * merely downscaled picture into a corrupt one -- VLC allocated
             * 1920x1080 while the card filled 1280x720 of it, and the rest,
             * never written, came out green. */
            /* Adopt whatever the card says, without argument. It really
             * does decode 1080p at 1280x720 on this driver -- Broadcom's own
             * DirectShow filter gets the same, verified by interposition --
             * and refusing the stream for that would trade hardware decoding
             * at a tenth of the CPU for software decoding this machine
             * cannot sustain. The picture is simply upscaled at display,
             * which is exactly what the reference implementation does. */
            /* BOTH pairs. i_width/i_height describe the BUFFER,
             * i_visible_* the picture inside it, and VLC sizes pictures from
             * the visible pair. Setting only the first left a 1280-wide
             * buffer carrying 1080 visible lines, and swscale -- told one
             * geometry, handed another -- wrote past the end of its
             * destination. Same trap as macosx_qt's green band. */
            p_dec->fmt_out.video.i_width  = crystal_QuantisedStride( i_new_w );
            p_dec->fmt_out.video.i_height = i_new_h;
            p_dec->fmt_out.video.i_visible_width  = i_new_w;
            p_dec->fmt_out.video.i_visible_height = i_new_h;
            p_sys->b_geometry_known = true;
            free( p_sys->p_probe_buf );
            p_sys->p_probe_buf = NULL;

            /* The picture in hand was allocated for the old geometry, and the
             * card is about to fill pictures of a different size. Drop it so
             * the next round allocates one that matches; keeping it crashed
             * on the very first 1080p stream that reported a change, the
             * conversion downstream reading a picture whose dimensions no
             * longer described its buffer. Any half-built field pair goes
             * with it: pairing fields across a format change would show a
             * frame stitched from two different geometries. */
            if( p_sys->p_pic )
            {
                picture_Release( p_sys->p_pic );
                p_sys->p_pic = NULL;
                p_pic = NULL;
            }
            p_sys->b_second_field = false;
            p_sys->i_last_date    = VLC_TICK_INVALID;
            p_sys->i_extrapolated = 0;
#define setAR( a, b, c ) case a: p_dec->fmt_out.video.i_sar_num = b; \
                                 p_dec->fmt_out.video.i_sar_den = c; break;
            switch( proc_out.PicInfo.aspect_ratio )
            {
                setAR( vdecAspectRatioSquare, 1, 1 )
                setAR( vdecAspectRatio12_11, 12, 11 )
                setAR( vdecAspectRatio10_11, 10, 11 )
                setAR( vdecAspectRatio16_11, 16, 11 )
                setAR( vdecAspectRatio40_33, 40, 33 )
                setAR( vdecAspectRatio24_11, 24, 11 )
                setAR( vdecAspectRatio20_11, 20, 11 )
                setAR( vdecAspectRatio32_11, 32, 11 )
                setAR( vdecAspectRatio80_33, 80, 33 )
                setAR( vdecAspectRatio18_11, 18, 11 )
                setAR( vdecAspectRatio15_11, 15, 11 )
                setAR( vdecAspectRatio64_33, 64, 33 )
                setAR( vdecAspectRatio160_99, 160, 99 )
                setAR( vdecAspectRatio4_3, 4, 3 )
                setAR( vdecAspectRatio16_9, 16, 9 )
                setAR( vdecAspectRatio221_1, 221, 1 )
                default: break;
            }
#undef setAR
            msg_Dbg( p_dec, "Format Change Detected [%i, %i], AR: %i/%i",
                    proc_out.PicInfo.width, proc_out.PicInfo.height,
                    p_dec->fmt_out.video.i_sar_num,
                    p_dec->fmt_out.video.i_sar_den );
            /* This consumed a queue entry too, so keep draining. */
            b_drain_more = true;
            break;
        }

        /* Nothing is documented here... */
        case BC_STS_NO_DATA:
            if( BC_FUNC_PSYS(DtsIsEndOfStream)( p_sys->bcm_handle, &b_eos )
                    == BC_STS_SUCCESS )
                if( b_eos )
                    msg_Dbg( p_dec, "End of Stream" );
            break;
        case BC_STS_TIMEOUT:       /* Timeout */
            msg_Err( p_dec, "ProcOutput timeout" );
            break;
        /* Three distinct I/O failures, worth telling apart: XFR_ERROR is the
         * DMA into our picture going wrong (buffer address, size or stride),
         * USER_ABORT is the transfer being cancelled, ERROR is everything
         * else. Lumping them under one wordless message cost an evening --
         * the card was returning one of these on every single call, so not a
         * frame was ever produced, and all the log said was "not
         * implemented". Rate-limited: this fires per pull attempt. */
        case BC_STS_IO_XFR_ERROR:
        case BC_STS_IO_USER_ABORT:
        case BC_STS_IO_ERROR:
        {
            const char *psz_which = sts == BC_STS_IO_XFR_ERROR ? "DMA transfer"
                                  : sts == BC_STS_IO_USER_ABORT ? "user abort"
                                                                : "I/O";
            if( p_sys->i_io_errors == 0 )
                msg_Err( p_dec, "ProcOutput %s error (status %i): the card "
                                "cannot deliver into the picture we hand it. "
                                "No frame will come out; falling back to "
                                "software decoding is the usual cure.",
                         psz_which, sts );
            p_sys->i_io_errors++;
            break;
        }
        default:
            msg_Err( p_dec, "Unknown return status. Please report %i", sts );
            break;
    }

    if( p_pic )
    {
        picture_Release( p_pic );
        p_sys->p_pic = NULL;
    }

    if( !b_drain_more )
        break;

    /* Re-read the queue depth: the point of the loop is to keep pulling while
     * the card still has frames waiting. */
    if( BC_FUNC_PSYS(DtsGetDriverStatus)( p_sys->bcm_handle, &driver_stat )
            != BC_STS_SUCCESS )
        break;
    }

    return b_queued;
}

/****************************************************************************
 * OutputThread: keep the card's ready list empty
 ****************************************************************************/
static void *OutputThread( void *p_data )
{
    decoder_t *p_dec = p_data;
    decoder_sys_t *p_sys = p_dec->p_sys;

    vlc_mutex_lock( &p_sys->lock );
    while( !p_sys->b_stop )
    {
        /* Wedge watchdog fired: rebuild the decoder here, holding the
         * lock, where no DtsProcOutput is in flight. */
        if( unlikely(p_sys->b_restart) )
        {
            CrystalHDRestartHardware( p_dec );
            p_sys->b_restart = false;
            /* A proactive reset waits on the decoder thread for this. */
            vlc_cond_signal( &p_sys->reset_done );
            continue;
        }
        vlc_mutex_unlock( &p_sys->lock );
        /* The lock is NOT held while pulling: the picture allocation inside
         * DtsProcOutput can sleep on an empty pool for as long as the video
         * output holds every buffer (see PullPictures). */
        bool b_busy = PullPictures( p_dec );
        vlc_mutex_lock( &p_sys->lock );

        if( b_busy || p_sys->b_stop )
            continue;   /* something came out: look again right away */

        /* Nothing ready. Wait a little, but stay interruptible so closing
         * the decoder does not have to sit through the delay. */
        vlc_cond_timedwait( &p_sys->wait, &p_sys->lock,
                            mdate() + CRYSTALHD_POLL_DELAY );
    }
    vlc_mutex_unlock( &p_sys->lock );

    return NULL;
}

#if 0
/* Copy the data
 * FIXME: this should not exist */
static void crystal_CopyPicture ( picture_t *p_pic, BC_DTS_PROC_OUT* p_out )
{
    int i_dst_stride;
    uint8_t *p_dst, *p_dst_end;
    uint8_t *p_src = p_out->Ybuff;

    p_dst         = p_pic->p[0].p_pixels;
    i_dst_stride  = p_pic->p[0].i_pitch;
    p_dst_end     = p_dst  + (i_dst_stride * p_out->PicInfo.height);

    for( ; p_dst < p_dst_end; p_dst += i_dst_stride, p_src += (p_out->PicInfo.width * 2))
        memcpy( p_dst, p_src, p_out->PicInfo.width * 2); // Copy in bytes
}
#endif

/* Parse the SPS/PPS Metadata to feed the decoder for avc1 */
static int crystal_insert_sps_pps( decoder_t *p_dec,
                                   uint8_t *p_buf,
                                   uint32_t i_buf_size)
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    p_sys->i_sps_pps_size = 0;
    p_sys->p_sps_pps_buf = h264_avcC_to_AnnexB_NAL( p_buf, i_buf_size,
                           &p_sys->i_sps_pps_size, &p_sys->i_nal_size );

    if( !p_sys->p_sps_pps_buf )
        return VLC_EGENERIC;

    /* Also keep the parameter sets in the stream's length-prefixed form,
     * to prepend to each IDR. Build it from the Annex B version just
     * produced: for each SPS/PPS NAL write a 4-byte big-endian length
     * (matching i_nal_size, always 4 here) followed by the NAL. */
    const uint8_t *p_sps, *p_pps, *p_ext;
    size_t i_sps = 0, i_pps = 0, i_ext = 0;
    if( h264_AnnexB_get_spspps( p_sys->p_sps_pps_buf, p_sys->i_sps_pps_size,
                                &p_sps, &i_sps, &p_pps, &i_pps,
                                &p_ext, &i_ext ) && i_sps && i_pps )
    {
        const size_t i_total = 4 + i_sps + 4 + i_pps;
        uint8_t *p = malloc( i_total );
        if( p )
        {
            uint8_t *q = p;
            #define PUT_NAL(ptr,len) do { \
                q[0] = (len) >> 24; q[1] = (len) >> 16; \
                q[2] = (len) >> 8;  q[3] = (len); \
                memcpy( q + 4, (ptr), (len) ); q += 4 + (len); } while(0)
            PUT_NAL( p_sps, i_sps );
            PUT_NAL( p_pps, i_pps );
            #undef PUT_NAL
            p_sys->p_sps_pps_avc = p;
            p_sys->i_sps_pps_avc_size = i_total;
        }
    }
    if( !p_sys->p_sps_pps_avc )
        msg_Warn( p_dec, "could not build length-prefixed SPS/PPS; the card "
                         "may wedge on a later keyframe" );

    return VLC_SUCCESS;
}

/* Build a new block with the length-prefixed SPS/PPS in front of p_block.
 * Returns NULL on allocation failure. Does not consume p_block. */
/****************************************************************************
 * crystal_strip_eos: remove End of Sequence / End of Stream NAL units
 ****************************************************************************
 * ★★★★★ These kill the BCM70015 outright. YouTube's DASH segments carry an
 * End of Sequence (type 10) at every GOP boundary -- ten of them in a 50 s
 * clip -- and the card decodes normally right up to one and then simply
 * stops: FramesCaptured frozen, ReadyListCount 0, every output buffer free,
 * no error anywhere, its input buffer still holding the data it will now
 * never decode. Only a full rebuild gets it going again, which is what the
 * whole pre-emptive-rebuild machinery was working around.
 *
 * Proved three ways: the stream stalls after exactly 151 frames, one short of
 * the 152-frame GOP; a re-encode of the SAME pictures without the marker
 * plays all 1351 frames with a GOP of 300; and injecting a type 10 by hand
 * into a stream that had none produced not a single picture.
 *
 * Both markers are pure signalling -- "the coded video sequence ends here" --
 * and carry no picture data, so dropping them changes nothing for any decoder
 * that does not need telling. Cheap too: the common case is a walk with no
 * allocation.
 ****************************************************************************/
static block_t *crystal_strip_eos( decoder_t *p_dec, block_t *p_block )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    /* ⚠⚠ avc1 ONLY. i_nal_size is initialised to 4 for every codec and is
     * only ever corrected by the avcC parser, so testing it alone would let
     * this walk loose on MPEG-2 and VC-1 elementary streams, where the first
     * four bytes are a start code (00 00 01 B3) that reads as a 435-byte NAL
     * length. The walk would then jump to an arbitrary offset and could well
     * find a byte whose low five bits are 10 or 11 -- and truncate the block
     * at it. p_sps_pps_avc is built only when avcC extradata parsed, which is
     * exactly the length-prefixed case. Same gate as
     * crystal_maybe_prepend_spspps. */
    if( !p_sys->p_sps_pps_avc || p_sys->i_nal_size != 4 )
        return p_block;

    /* First pass: is there anything to strip at all? */
    bool b_found = false;
    size_t i_pos = 0;
    while( i_pos + 5 <= p_block->i_buffer )
    {
        const uint32_t i_nal = GetDWBE( p_block->p_buffer + i_pos );
        const uint8_t i_type = p_block->p_buffer[i_pos+4] & 0x1F;
        if( i_type == 10 || i_type == 11 )
        {
            b_found = true;
            break;
        }
        if( i_nal == 0 || i_pos + 4 + (size_t)i_nal <= i_pos )
            break;
        i_pos += 4 + i_nal;
    }
    if( !b_found )
        return p_block;

    block_t *p_new = block_Alloc( p_block->i_buffer );
    if( !p_new )
        return p_block;      /* out of memory: feed it as-is */

    size_t i_out = 0;
    i_pos = 0;
    while( i_pos + 5 <= p_block->i_buffer )
    {
        const uint32_t i_nal = GetDWBE( p_block->p_buffer + i_pos );
        const uint8_t i_type = p_block->p_buffer[i_pos+4] & 0x1F;
        if( i_nal == 0 || i_pos + 4 + (size_t)i_nal <= i_pos
            || i_pos + 4 + (size_t)i_nal > p_block->i_buffer )
            break;           /* malformed: stop and keep what we have */
        if( i_type != 10 && i_type != 11 )
        {
            memcpy( p_new->p_buffer + i_out, p_block->p_buffer + i_pos,
                    4 + i_nal );
            i_out += 4 + i_nal;
        }
        i_pos += 4 + i_nal;
    }
    /* Anything the walk could not parse travels along untouched. */
    if( i_pos < p_block->i_buffer )
    {
        memcpy( p_new->p_buffer + i_out, p_block->p_buffer + i_pos,
                p_block->i_buffer - i_pos );
        i_out += p_block->i_buffer - i_pos;
    }
    p_new->i_buffer = i_out;
    p_new->i_pts    = p_block->i_pts;
    p_new->i_dts    = p_block->i_dts;
    p_new->i_flags  = p_block->i_flags;
    block_Release( p_block );

    if( !p_sys->b_eos_logged )
    {
        p_sys->b_eos_logged = true;
        msg_Dbg( p_dec, "stripping End of Sequence markers: this card stops "
                 "dead on them" );
    }
    return p_new;
}

static block_t *crystal_prepend_spspps( decoder_sys_t *p_sys, block_t *p_block )
{
    block_t *p_new = block_Alloc( p_sys->i_sps_pps_avc_size
                                  + p_block->i_buffer );
    if( !p_new )
        return NULL;
    memcpy( p_new->p_buffer, p_sys->p_sps_pps_avc, p_sys->i_sps_pps_avc_size );
    memcpy( p_new->p_buffer + p_sys->i_sps_pps_avc_size,
            p_block->p_buffer, p_block->i_buffer );
    p_new->i_pts = p_block->i_pts;
    p_new->i_dts = p_block->i_dts;
    p_new->i_flags = p_block->i_flags;
    return p_new;
}

/****************************************************************************
 * crystal_maybe_prepend_spspps: feed parameter sets ahead of each IDR
 ****************************************************************************
 * avc1 carries its SPS/PPS out of band (avcC), so the elementary stream
 * has none and the card only ever gets them once, before the first frame.
 * Real 1080p then wedges the BCM70015 at the second GOP's (large) IDR.
 * Detect an IDR by walking the block's length-prefixed NAL units -- the
 * BLOCK_FLAG_TYPE_I flag is not set on these blocks -- and, when found,
 * return a new block with the length-prefixed SPS/PPS in front. The DIL
 * sees the parameter sets are already present and does not add its own.
 ****************************************************************************/
static block_t *crystal_maybe_prepend_spspps( decoder_t *p_dec,
                                              block_t *p_block )
{
    decoder_sys_t *p_sys = p_dec->p_sys;

    if( !p_sys->p_sps_pps_avc || p_sys->i_nal_size != 4 )
        return p_block;

    /* Walk the 4-byte length-prefixed NAL units looking for an IDR (type
     * 5). Bounded by the buffer; a malformed length just stops the scan. */
    bool b_idr = false;
    size_t i_pos = 0;
    while( i_pos + 5 <= p_block->i_buffer )
    {
        uint32_t i_nal = (p_block->p_buffer[i_pos]   << 24) |
                         (p_block->p_buffer[i_pos+1] << 16) |
                         (p_block->p_buffer[i_pos+2] << 8)  |
                          p_block->p_buffer[i_pos+3];
        const uint8_t i_type = p_block->p_buffer[i_pos+4] & 0x1F;
        if( i_type == 5 )   /* coded slice of an IDR picture */
        {
            b_idr = true;
            break;
        }
        if( i_nal == 0 || i_pos + 4 + i_nal < i_pos + 4 )   /* guard */
            break;
        i_pos += 4 + i_nal;
    }

    if( !b_idr )
        return p_block;

    /* ★ Rebuild timed to this keyframe -- but AFTER it, not before.
     *
     * The old order (flush, then feed the keyframe to the fresh decoder)
     * threw away everything the card was still holding, ~8 frames of reorder
     * tail, once per keyframe. Feeding the keyframe FIRST costs nothing and
     * gets that tail back: an IDR empties the DPB by definition, so the card
     * must hand over every picture it was sitting on before it can show the
     * keyframe. Wait for it to do so, then rebuild, then feed the SAME
     * keyframe again -- an IDR is self-contained, so a second copy re-primes
     * the new decoder exactly as the first primed the old one.
     *
     * (The note this replaces claimed a "drain first" attempt saved nothing
     * because the card will not release in-flight frames on demand. True --
     * but it does release them when decoding forward, and the keyframe is
     * what makes it decode forward. The earlier attempt waited without
     * feeding it.)
     *
     * All this happens in DecodeBlock once the block has actually been fed;
     * here we only arm it and keep the copy. */
    vlc_mutex_lock( &p_sys->lock );
    /* ⚠ Gated on b_await_idr, NOT on a count of IDRs seen: the count was
     * written by this thread and zeroed by CrystalHDRestartHardware() on the
     * OUTPUT thread, with a lock-releasing wait in between, so the two raced
     * and the rebuild fired every OTHER keyframe. b_await_idr says exactly
     * what is meant -- "this decoder is fresh and has yet to produce" -- and
     * cannot race with itself. */
    const bool b_proactive = ( p_sys->b_needs_preemptive
                               && !p_sys->b_await_idr
                               && !p_sys->b_restart && !p_sys->b_stop
                               && !p_sys->b_replay_pending
                               && p_sys->i_blocks_since_reset
                                      >= CRYSTALHD_RESET_BUDGET );
    vlc_mutex_unlock( &p_sys->lock );

    if( ( p_sys->i_idr_seen++ % 64 ) == 0 )
        msg_Dbg( p_dec, "prepended SPS/PPS to IDR #%u", p_sys->i_idr_seen );

    block_t *p_new = crystal_prepend_spspps( p_sys, p_block );
    if( !p_new )
        return p_block;   /* out of memory: feed the frame as-is */
    block_Release( p_block );

    if( b_proactive )
    {
        /* Arm the rebuild. From here until crystal_RebuildAtIdr fires, every
         * block fed is also copied aside (see DecodeBlock), this keyframe
         * first, so the rebuilt decoder can be handed the identical
         * sequence and nothing is lost to the flush. */
        vlc_mutex_lock( &p_sys->lock );
        crystal_ReplayClear( p_sys );
        p_sys->i_replay_target = p_new->i_pts;
        p_sys->i_replay_seen   = p_sys->i_last_out_date;
        p_sys->i_replay_moved  = mdate();
        p_sys->b_replay_pending = true;
        vlc_mutex_unlock( &p_sys->lock );
    }
    return p_new;
}

