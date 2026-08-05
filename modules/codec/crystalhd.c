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


//#define DEBUG_CRYSTALHD 1

/*****************************************************************************
 * Module descriptor
 *****************************************************************************/
static int        OpenDecoder  ( vlc_object_t * );
static void       CloseDecoder ( vlc_object_t * );

#define CRYSTALHD_ENABLE_TEXT N_("Hardware decoding (Crystal HD)")
#define CRYSTALHD_ENABLE_LONGTEXT N_( \
    "Decode H.264, VC-1 and MPEG-2 video on the Broadcom Crystal HD card " \
    "installed in this Mac. Untick to decode with the processor instead; " \
    "playback also falls back to the processor on its own whenever the " \
    "card cannot handle a stream." )

vlc_module_begin ()
    set_category( CAT_INPUT )
    set_subcategory( SUBCAT_INPUT_VCODEC )
    set_description( N_("Crystal HD hardware video decoder") )
#ifdef __APPLE__
    /* Above videotoolbox (800): a Mac with this card in its mini-PCIe slot got
     * it precisely because its CPU cannot keep up, and on the vintage systems
     * involved videotoolbox is either absent or limited. Ranking picks the
     * decoder at open time only, so anything the card cannot handle -- no card
     * at all, an unsupported codec, or a device already claimed by another
     * process -- makes OpenDecoder return an error and lets the next decoder
     * in line take over. */
    set_capability( "video decoder", 900 )
#else
    /* Everywhere else this module has always been opt-in, selected only
     * through --codec crystalhd. Leave that behaviour alone. */
    set_capability( "video decoder", 0 )
#endif
    set_callbacks( OpenDecoder, CloseDecoder )
#ifdef __APPLE__
    /* Same shape as videotoolbox's own switch: because this module outranks
     * every software decoder, a user who wants to compare against the CPU
     * path -- or who hits a stream the card mishandles -- otherwise has no
     * way out short of --codec on a command line. Unticking it makes
     * OpenDecoder decline and the next decoder in line take over. */
    add_bool( "crystalhd", true, CRYSTALHD_ENABLE_TEXT,
              CRYSTALHD_ENABLE_LONGTEXT, false )
#endif
    add_shortcut( "crystalhd" )
vlc_module_end ()

/*****************************************************************************
 * Local prototypes
 *****************************************************************************/
static int DecodeBlock   ( decoder_t *p_dec, block_t *p_block );
static void Flush        ( decoder_t *p_dec );
static bool PullPictures ( decoder_t *p_dec );
static void *OutputThread( void *p_data );
// static void crystal_CopyPicture ( picture_t *, BC_DTS_PROC_OUT* );
static int crystal_insert_sps_pps(decoder_t *, uint8_t *, uint32_t);

/*****************************************************************************
 * decoder_sys_t : CrysalHD decoder structure
 *****************************************************************************/
struct decoder_sys_t
{
    HANDLE bcm_handle;       /* Device Handle */

    uint8_t *p_sps_pps_buf;  /* SPS/PPS buffer */
    size_t   i_sps_pps_size; /* SPS/PPS size */

    uint8_t i_nal_size;     /* NAL header size */

    /* Callback */
    picture_t       *p_pic;
    BC_DTS_PROC_OUT *proc_out;

    /* Flush mode the card accepts while running, 0 until probed */
    uint32_t i_flush_mode;

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
    HINSTANCE p_bcm_dll;
    BC_STATUS (WINAPI *OurDtsCloseDecoder)( HANDLE hDevice );
    BC_STATUS (WINAPI *OurDtsDeviceClose)( HANDLE hDevice );
    BC_STATUS (WINAPI *OurDtsFlushInput)( HANDLE hDevice, U32 Mode );
    BC_STATUS (WINAPI *OurDtsStopDecoder)( HANDLE hDevice );
    BC_STATUS (WINAPI *OurDtsGetDriverStatus)( HANDLE hDevice,
                            BC_DTS_STATUS *pStatus );
    BC_STATUS (WINAPI *OurDtsProcInput)( HANDLE hDevice, U8 *pUserData,
                            U32 ulSizeInBytes, U64 timeStamp, BOOL encrypted );
    BC_STATUS (WINAPI *OurDtsProcOutput)( HANDLE hDevice, U32 milliSecWait,
                            BC_DTS_PROC_OUT *pOut );
    BC_STATUS (WINAPI *OurDtsIsEndOfStream)( HANDLE hDevice, U8* bEOS );
    BC_STATUS (WINAPI *OurDtsSetSkipPictureMode)( HANDLE hDevice, U32 SkipMode );
    BC_STATUS (WINAPI *OurDtsFlushRxCapture)( HANDLE hDevice, BOOL bDiscardOnly );
#endif
};

/* Held from just before the device is opened until it is closed. A plain
 * flag rather than a semaphore: what it guards is a piece of hardware with
 * exactly one seat, and the answer is only ever yes or no. */
static vlc_mutex_t chd_device_lock = VLC_STATIC_MUTEX;
static bool        chd_device_busy = false;

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

/*****************************************************************************
* OpenDecoder: probe the decoder and return score
*****************************************************************************/
static int OpenDecoder( vlc_object_t *p_this )
{
    decoder_t *p_dec = (decoder_t*)p_this;
    decoder_sys_t *p_sys;

#ifdef __APPLE__
    /* Declining here rather than not registering at all keeps the ranking
     * machinery intact: the next video decoder in line opens normally, and
     * an explicit --codec crystalhd still overrides the preference. */
    if( !var_InheritBool( p_dec, "crystalhd" ) )
        return VLC_EGENERIC;
#endif

    /* Codec specifics */
    uint32_t i_bcm_codec_subtype = 0;
    switch ( p_dec->fmt_in.i_codec )
    {
    case VLC_CODEC_H264:
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
    p_sys->i_sps_pps_size   = 0;
    p_sys->i_flush_mode     = 0;
    p_sys->b_flea           = false;
    p_sys->b_thread         = false;
    p_sys->b_stop           = false;
    vlc_mutex_init( &p_sys->lock );
    vlc_cond_init( &p_sys->wait );
    p_sys->i_reset          = 0;
    p_sys->b_skip_mode      = false;
    p_sys->p_sps_pps_buf    = NULL;
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
        return VLC_EGENERIC;
    }

#define LOAD_SYM( a ) \
    BC_FUNC( a )  = (void *)GetProcAddress( p_sys->p_bcm_dll, ( #a ) ); \
    if( !BC_FUNC( a ) ) { \
        msg_Err( p_dec, "missing symbol " # a ); return VLC_EGENERIC; }

#define LOAD_SYM_PSYS( a ) \
    p_sys->BC_FUNC( a )  = (void *)GetProcAddress( p_sys->p_bcm_dll, #a ); \
    if( !p_sys->BC_FUNC( a ) ) { \
        msg_Err( p_dec, "missing symbol " # a ); return VLC_EGENERIC; }

    BC_STATUS (WINAPI *OurDtsDeviceOpen)( HANDLE *hDevice, U32 mode );
    LOAD_SYM( DtsDeviceOpen );
    BC_STATUS (WINAPI *OurDtsCrystalHDVersion)( HANDLE  hDevice, PBC_INFO_CRYSTAL bCrystalInfo );
    LOAD_SYM( DtsCrystalHDVersion );
    BC_STATUS (WINAPI *OurDtsSetColorSpace)( HANDLE hDevice, BC_OUTPUT_FORMAT Mode422 );
    LOAD_SYM( DtsSetColorSpace );
    BC_STATUS (WINAPI *OurDtsSetInputFormat)( HANDLE hDevice, BC_INPUT_FORMAT *pInputFormat );
    LOAD_SYM( DtsSetInputFormat );
    BC_STATUS (WINAPI *OurDtsOpenDecoder)( HANDLE hDevice, U32 StreamType );
    LOAD_SYM( DtsOpenDecoder );
    BC_STATUS (WINAPI *OurDtsStartDecoder)( HANDLE hDevice );
    LOAD_SYM( DtsStartDecoder );
    BC_STATUS (WINAPI *OurDtsStartCapture)( HANDLE hDevice );
    LOAD_SYM( DtsStartCapture );
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
    BC_STATUS sts = BC_STS_ERROR;
    for( int i_try = 0; i_try < 3; i_try++ )
    {
        sts = BC_FUNC(DtsDeviceOpen)( &p_sys->bcm_handle,
                 (DTS_PLAYBACK_MODE | DTS_LOAD_FILE_PLAY_FW |
                  DTS_SKIP_TX_CHK_CPB | DTS_PLAYBACK_DROP_RPT_MODE |
                  DTS_DFLT_RESOLUTION(vdecRESOLUTION_720p23_976)) );
        if( sts == BC_STS_SUCCESS )
            break;
        if( i_try + 1 < 3 )
            msleep( 300 * 1000 );
    }

    if( sts != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't find and open the BCM CrystalHD device" );
        CrystalHDWarnUnusable( p_dec );
        vlc_cond_destroy( &p_sys->wait );
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

    /* Packed 4:2:2, in the byte order that reaches the screen without a
     * conversion on this platform (see CRYSTALHD_OUTPUT_MODE above). */
    if( BC_FUNC(DtsSetColorSpace)( p_sys->bcm_handle, CRYSTALHD_OUTPUT_MODE )
            != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't set the color space. Please report this!" );
        goto error;
    }

    /* Prepare Input for the device */
    BC_INPUT_FORMAT p_in;
    memset( &p_in, 0, sizeof(BC_INPUT_FORMAT) );
    p_in.OptFlags    = 0x51; /* 0b 0 1 01 0001 */
    p_in.mSubtype    = i_bcm_codec_subtype;
    p_in.startCodeSz = p_sys->i_nal_size;
    p_in.pMetaData   = p_sys->p_sps_pps_buf;
    p_in.metaDataSz  = p_sys->i_sps_pps_size;
    p_in.width       = p_dec->fmt_in.video.i_width;
    p_in.height      = p_dec->fmt_in.video.i_height;
    p_in.Progressive = true;

    if( BC_FUNC(DtsSetInputFormat)( p_sys->bcm_handle, &p_in ) != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't set the color space. Please report this!" );
        goto error;
    }

    /* Open a decoder */
    if( BC_FUNC(DtsOpenDecoder)( p_sys->bcm_handle, BC_STREAM_TYPE_ES )
            != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't open the CrystalHD decoder" );
        goto error;
    }

    /* Start it */
    if( BC_FUNC(DtsStartDecoder)( p_sys->bcm_handle ) != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't start the decoder" );
        goto error;
    }

    if( BC_FUNC(DtsStartCapture)( p_sys->bcm_handle ) != BC_STS_SUCCESS )
    {
        msg_Err( p_dec, "Couldn't start the capture" );
        goto error_complete;
    }

    /* Set output properties */
    /* Start pulling frames only once capture is running. */
    if( vlc_clone( &p_sys->thread, OutputThread, p_dec,
                   VLC_THREAD_PRIORITY_INPUT ) )
    {
        msg_Err( p_dec, "Couldn't start the CrystalHD output thread" );
        goto error;
    }
    p_sys->b_thread = true;

    p_dec->fmt_out.i_codec        = CRYSTALHD_OUTPUT_CHROMA;
    p_dec->fmt_out.video.i_width  = p_dec->fmt_in.video.i_width;
    p_dec->fmt_out.video.i_height = p_dec->fmt_in.video.i_height;

    /* Set callbacks */
    p_dec->pf_decode = DecodeBlock;
    p_dec->pf_flush  = Flush;

    msg_Info( p_dec, "Opened CrystalHD hardware with success" );
    return VLC_SUCCESS;

error_complete:
    BC_FUNC_PSYS(DtsCloseDecoder)( p_sys->bcm_handle );
error:
    BC_FUNC_PSYS(DtsDeviceClose)( p_sys->bcm_handle );
    vlc_cond_destroy( &p_sys->wait );
    vlc_mutex_destroy( &p_sys->lock );
    free( p_sys->p_sps_pps_buf );
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
    vlc_mutex_destroy( &p_sys->lock );

    /* The seat is free again: the next stream may have the card. Released
     * only once the device is really closed, never before. */
    CrystalHDReleaseDevice();

    free( p_sys->p_sps_pps_buf );
#ifdef DEBUG_CRYSTALHD
    msg_Dbg( p_dec, "done cleaning up CrystalHD" );
#endif
    free( p_sys );
}

#if defined(__KERNEL__) || defined(__LINUX_USER__)
static BC_STATUS ourCallback(void *shnd, uint32_t width, uint32_t height, uint32_t stride, void *pOut)
{
    BC_DTS_PROC_OUT *proc_in  = (BC_DTS_PROC_OUT*)pOut;
#else
static BC_STATUS ourCallback(void *shnd, uint32_t width, uint32_t height, uint32_t stride, BC_DTS_PROC_OUT *proc_in)
{
#endif
    VLC_UNUSED(width); VLC_UNUSED(height); VLC_UNUSED(stride);

    decoder_t *p_dec          = (decoder_t *)shnd;
    BC_DTS_PROC_OUT *proc_out = p_dec->p_sys->proc_out;

    /* Direct Rendering */
    /* Do not allocate for the second-field in the pair, in interlaced */
    if( !(proc_in->PicInfo.flags & VDEC_FLAG_INTERLACED_SRC) ||
        !(proc_in->PicInfo.flags & VDEC_FLAG_FIELDPAIR) )
    {
        if( !decoder_UpdateVideoFormat( p_dec ) )
            p_dec->p_sys->p_pic = decoder_NewPicture( p_dec );
    }

    /* */
    picture_t *p_pic = p_dec->p_sys->p_pic;
    if( !p_pic )
    {
        return BC_STS_ERROR;
    }

    /* Interlacing */
    p_pic->b_progressive     = !(proc_in->PicInfo.flags & VDEC_FLAG_INTERLACED_SRC);
    p_pic->b_top_field_first = !(proc_in->PicInfo.flags & VDEC_FLAG_BOTTOM_FIRST);
    p_pic->i_nb_fields       = p_pic->b_progressive? 1: 2;

    /* Filling out the struct */
    proc_out->Ybuff      = !(proc_in->PicInfo.flags & VDEC_FLAG_FIELDPAIR) ?
                             &p_pic->p[0].p_pixels[0] :
                             &p_pic->p[0].p_pixels[p_pic->p[0].i_pitch];
    proc_out->YbuffSz    = 2 * p_pic->p[0].i_pitch;

    /* Line stride in pixels; packed 4:2:2 is two bytes per pixel. */
    unsigned i_stride_px = p_pic->p[0].i_pitch / 2;
    const unsigned i_width = p_dec->fmt_out.video.i_width;

    /* The BCM70012 lays its lines out on a quantised stride -- 720, 1280 or
     * 1920 pixels -- regardless of the real width, a lib/driver quirk that
     * XBMC compensates for when it copies frames out. Here the card DMAs
     * straight into this picture, so give it the padding that matches, but
     * only when the buffer is genuinely wide enough: getting this wrong would
     * have the hardware write past the end of the picture. Untested, no
     * BCM70012 to hand; the guard is what makes it safe to ship anyway. */
    if( !p_dec->p_sys->b_flea )
    {
        const unsigned i_quantised = (i_width <= 720)  ? 720
                                   : (i_width <= 1280) ? 1280
                                                       : 1920;
        if( i_quantised <= i_stride_px )
            i_stride_px = i_quantised;
    }

    proc_out->StrideSz   = (proc_in->PicInfo.flags & VDEC_FLAG_INTERLACED_SRC)?
                            2 * i_stride_px - i_width:
                            i_stride_px - i_width;
    proc_out->PoutFlags |= BC_POUT_FLAGS_STRIDE;              /* Trust Stride info */

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
    BC_DTS_STATUS driver_stat;

    /* Keep the output thread out while the card is flushed and its queue
     * emptied, so it cannot queue a pre-seek picture in between. */
    vlc_mutex_lock( &p_sys->lock );

    /* Follow XBMC, which is the reference implementation for this hardware:
     * it only flushes the card on the BCM70012, and leaves the BCM70015
     * alone -- there it just discards what it has already pulled out. Mode 2
     * is what XBMC uses (input, decoded and to-be-decoded buffers).
     *
     * VLC_CHD_FLUSHMODE=<n> overrides this for measuring one behaviour
     * against another on real hardware: 0 touches nothing, 1/2/4 force that
     * mode on either chip. */
    static int i_forced_mode = -1;
    if( unlikely(i_forced_mode < 0) )
    {
        const char *psz_mode = getenv( "VLC_CHD_FLUSHMODE" );
        i_forced_mode = psz_mode ? atoi( psz_mode ) : -1;
        if( i_forced_mode < 0 )
            i_forced_mode = -2;   /* unset: use the XBMC behaviour */
    }

    if( i_forced_mode >= 0 )
    {
        if( i_forced_mode > 0 )
            BC_FUNC_PSYS(DtsFlushInput)( p_sys->bcm_handle, i_forced_mode );
        p_sys->i_reset = 10;
    }
    else if( !p_sys->b_flea )
    {
        /* BCM70012: exactly what XBMC does. */
        if( BC_FUNC_PSYS(DtsFlushInput)( p_sys->bcm_handle, 2 ) != BC_STS_SUCCESS )
            msg_Warn( p_dec, "CrystalHD: flushing the decoder failed" );

        /* Skip pictures over the next few input blocks so the card can get
         * ahead again instead of decoding everything the seek hands it
         * (XBMC's m_reset = 10). */
        p_sys->i_reset = 10;
    }
    else
    {
        /* BCM70015: mode 2 as well, which is what XBMC uses. It used to fail
         * here, back when pictures were only pulled once per input block --
         * with the output thread keeping the ready list empty it succeeds.
         *
         * Do NOT reach for mode 4 ("also flushes the driver's buffers"): it
         * is accepted, and on a short clip the card then never emits another
         * picture at all -- a seek forward freezes the image until the end of
         * the file. Measured on this BCM70015: seeking to 9 s in a 15 s clip
         * yields 0 pictures with mode 4 against 50 with mode 2. */
        if( BC_FUNC_PSYS(DtsFlushInput)( p_sys->bcm_handle, 2 ) != BC_STS_SUCCESS )
            msg_Warn( p_dec, "CrystalHD: flushing the decoder failed" );
    }

    /* Frames already transferred can still be sitting in the ready list, and
     * they are pre-seek ones: pull them out and throw them away rather than
     * letting the next DecodeBlock queue them. */
    for( unsigned i = 0; i < CRYSTALHD_MAX_DRAIN; i++ )
    {
        if( BC_FUNC_PSYS(DtsGetDriverStatus)( p_sys->bcm_handle, &driver_stat )
                != BC_STS_SUCCESS || driver_stat.ReadyListCount == 0 )
            break;

        BC_DTS_PROC_OUT proc_out;
        memset( &proc_out, 0, sizeof(BC_DTS_PROC_OUT) );
        proc_out.PicInfo.width  = p_dec->fmt_out.video.i_width;
        proc_out.PicInfo.height = p_dec->fmt_out.video.i_height;
        proc_out.PoutFlags      = BC_POUT_FLAGS_SIZE;
        proc_out.AppCallBack    = ourCallback;
        proc_out.hnd            = p_dec;
        p_sys->proc_out         = &proc_out;

        if( BC_FUNC_PSYS(DtsProcOutput)( p_sys->bcm_handle, 0, &proc_out )
                != BC_STS_SUCCESS )
            break;

        if( p_sys->p_pic )
        {
            picture_Release( p_sys->p_pic );
            p_sys->p_pic = NULL;
        }
    }

    /* A half-built interlaced pair would pair its first field with a post-seek
     * second one. */
    if( p_sys->p_pic )
    {
        picture_Release( p_sys->p_pic );
        p_sys->p_pic = NULL;
    }

    vlc_mutex_unlock( &p_sys->lock );
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

    /* First check the status of the decode to produce pictures */
    if( BC_FUNC_PSYS(DtsGetDriverStatus)( p_sys->bcm_handle, &driver_stat ) != BC_STS_SUCCESS )
    {
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
            /* Valid input block, so we can send to HW to decode */
            BC_STATUS status = BC_FUNC_PSYS(DtsProcInput)( p_sys->bcm_handle,
                                            p_block->p_buffer,
                                            p_block->i_buffer,
                                            p_block->i_pts >= VLC_TICK_INVALID ? TO_BC_PTS(p_block->i_pts) : 0, false );

            block_Release( p_block );

            if( status != BC_STS_SUCCESS )
                return VLCDEC_SUCCESS;

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
 * Called from the output thread, under p_sys->lock. The card holds several
 * decoded frames and stops decoding altogether once its ready list is full,
 * so this must run continuously rather than once per input block: that is the
 * whole point of the thread, and what XBMC's CMPCOutputThread does.
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

    /* Prepare the Output structure */
    /* We always expect and use YUY2 */
    memset( &proc_out, 0, sizeof(BC_DTS_PROC_OUT) );
    proc_out.PicInfo.width  = p_dec->fmt_out.video.i_width;
    proc_out.PicInfo.height = p_dec->fmt_out.video.i_height;
    proc_out.PoutFlags      = BC_POUT_FLAGS_SIZE;
    proc_out.AppCallBack    = ourCallback;
    proc_out.hnd            = p_dec;
    p_sys->proc_out         = &proc_out;

    /* */
    BC_STATUS sts = BC_FUNC_PSYS(DtsProcOutput)( p_sys->bcm_handle, 128, &proc_out );
#ifdef DEBUG_CRYSTALHD
    if( sts != BC_STS_SUCCESS )
        msg_Err( p_dec, "DtsProcOutput returned %i", sts );
#endif

    uint8_t b_eos;
    /* Whether to look for another picture once this one is dealt with. Only
     * the paths that consumed something from the queue set it. */
    bool b_drain_more = false;
    picture_t *p_pic = p_sys->p_pic;
    switch( sts )
    {
        case BC_STS_SUCCESS:
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
                b_drain_more = true;
                break;
            }

            //  crystal_CopyPicture( p_pic, &proc_out );
            crystal_FixGreenPixel( p_pic );
            p_pic->date = proc_out.PicInfo.timeStamp > 0 ?
                          FROM_BC_PTS(proc_out.PicInfo.timeStamp) : VLC_TICK_INVALID;

            if( unlikely(i_trace) )
                msg_Dbg( p_dec, "CHDTRACE out raw=%"PRIu64" pts=%"PRId64
                                " now=%"PRId64" delta=%"PRId64" ready=%u free=%u",
                         (uint64_t)proc_out.PicInfo.timeStamp, p_pic->date,
                         mdate(), p_pic->date - mdate(),
                         driver_stat.ReadyListCount, driver_stat.FreeListCount );
            //p_pic->date += 100 * 1000;
#ifdef DEBUG_CRYSTALHD
            msg_Dbg( p_dec, "TS Output is %"PRIu64, p_pic->date);
#endif
            decoder_QueueVideo( p_dec, p_pic );
            b_queued = true;

            /* Handed over to the video output: drop our reference so the
             * cleanup below does not release it, and let the callback build a
             * fresh picture for the next frame. */
            p_pic = NULL;
            p_sys->p_pic = NULL;
            b_drain_more = true;
            break;

        case BC_STS_DEC_NOT_OPEN:
        case BC_STS_DEC_NOT_STARTED:
            msg_Err( p_dec, "Decoder not opened or started" );
            break;

        case BC_STS_INV_ARG:
            msg_Warn( p_dec, "Invalid arguments. Please report" );
            break;

        case BC_STS_FMT_CHANGE:    /* Format change */
            /* if( !(proc_out.PoutFlags & BC_POUT_FLAGS_PIB_VALID) )
                break; */
            p_dec->fmt_out.video.i_width  = proc_out.PicInfo.width;
            p_dec->fmt_out.video.i_height = proc_out.PicInfo.height;
            if( proc_out.PicInfo.height == 1088 )
                p_dec->fmt_out.video.i_height = 1080;
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
        case BC_STS_IO_XFR_ERROR:
        case BC_STS_IO_USER_ABORT:
        case BC_STS_IO_ERROR:
            msg_Err( p_dec, "ProcOutput return mode not implemented. Please report" );
            break;
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
        if( PullPictures( p_dec ) )
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

    return (p_sys->p_sps_pps_buf) ? VLC_SUCCESS : VLC_EGENERIC;
}

