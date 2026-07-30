/*****************************************************************************
 * bluray_darwin_disc.c: read a Blu-ray disc over MMC on Mac OS X 10.4
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

/* Built everywhere the plugin is, but only has a body on Darwin: it is listed
 * unconditionally in Makefile.am rather than behind an automake conditional. */
#ifdef __APPLE__

#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>

#include <IOKit/IOKitLib.h>
#include <IOKit/IOBSD.h>
#include <IOKit/IOCFPlugIn.h>

/* SCSICmds_INQUIRY_Definitions.h, pulled in by SCSITaskLib.h, has struct members
 * literally named VERSION and REVISION -- which config.h has already turned into
 * macros. libaacs hits the same wall and works around it the same way. */
#pragma push_macro("VERSION")
#pragma push_macro("REVISION")
#undef VERSION
#undef REVISION
#include <IOKit/scsi/SCSITaskLib.h>
#pragma pop_macro("REVISION")
#pragma pop_macro("VERSION")

#include <vlc_common.h>
#include <vlc_fs.h>

#include "bluray_darwin_disc.h"

/* SCSITaskSGElement only appears in the 10.5 SDK, where it is IOVirtualRange on
 * 32 bit and IOAddressRange on 64 bit. The 10.4u SDK has neither the typedef nor
 * a 64 bit target, so IOVirtualRange -- which it does have, and which is what
 * SetScatterGatherEntries takes there -- is the right stand-in. */
#if !defined(MAC_OS_X_VERSION_10_5) \
 || MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5
typedef IOVirtualRange SCSITaskSGElement;
#endif

#define BD_BLOCK        2048

/* One READ(10) per refill. 64 KB is where this tops out on the reference
 * hardware (Pioneer USB 2 drive on a Mac Mini G4): 2 KB gives 0.60 MB/s,
 * 6 KB 1.91, 32 KB 7.26, 64 KB 8.34 and 128 KB 8.27 -- USB command latency
 * dominates until the transfers get big, then the drive does. Since libbluray
 * asks for one 6144 byte aligned unit at a time, without this read-ahead the
 * whole thing would run at 1.9 MB/s, well under the ~31.5 Mbps a retail title
 * needs; with it there is better than 2x headroom. */
#define CACHE_BLOCKS    32

/* Number of read-ahead windows kept at once. One is enough for playback, which
 * walks the disc forwards, but not for opening it: libudfread alternates
 * between a file's data and the directory / ICB entries describing the next
 * one, which live far away, so a single window is evicted by every other read.
 * Measured on Rio (163 playlists, 292 clip info files): 728 read calls turned
 * into 463 physical reads, 228 of them jumping backwards, at ~67 ms of seek
 * each. Keeping a few windows lets the metadata stay resident. The transfer
 * size is untouched -- that one was measured on the reference USB 2 hardware
 * and playback depends on it. Costs CACHE_WAYS * 64 KB of memory. */
#define CACHE_WAYS      8
#define READ10_TIMEOUT  20000   /* ms; optical drives can be slow to spin up */

struct bluray_disc_t
{
    vlc_object_t                *obj;

    /* Raw device backend: >= 0 when reading through /dev/rdiskN rather than
     * MMC. The two differ only in how a run of blocks is fetched; the
     * read-ahead above them is what actually matters. */
    int                          fd;

    IOCFPlugInInterface        **plugin;
    MMCDeviceInterface         **mmc;
    SCSITaskDeviceInterface    **task_dev;

    /* Read-ahead windows, one allocation, page aligned so a transfer never
     * straddles in a way the driver has to bounce. A way holds no data while
     * its lba is -1; stamp orders them for eviction (0 = never used). */
    uint8_t                     *cache;
    struct {
        int                      lba;
        int                      count;
        uint64_t                 stamp;
    }                            way[CACHE_WAYS];
    uint64_t                     clock;

    vlc_mutex_t                  lock;

    /* How the windows fared, reported once at close: a disc that opens slowly
     * shows up here as a refill count close to the call count. */
    uint64_t                     reads, refills;
};

/* Buffer of one read-ahead window. */
static inline uint8_t *CacheWay(bluray_disc_t *p, int i)
{
    return p->cache + (size_t)i * CACHE_BLOCKS * BD_BLOCK;
}

/*****************************************************************************
 * READ(10)
 *****************************************************************************/

static int SendRead10(bluray_disc_t *, uint32_t, uint16_t, void *);

/* Fetches num_blocks starting at lba, whichever backend this reader uses.
 * Returns the number of blocks obtained, or a negative value. */
static int FetchBlocks(bluray_disc_t *p, uint32_t lba, uint16_t blocks,
                       void *buf)
{
    if (p->fd >= 0) {
        ssize_t got = pread(p->fd, buf, (size_t)blocks * BD_BLOCK,
                            (off_t)lba * BD_BLOCK);
        if (got <= 0)
            return -1;
        return (int)(got / BD_BLOCK);
    }
    return SendRead10(p, lba, blocks, buf);
}

static int SendRead10(bluray_disc_t *p, uint32_t lba, uint16_t blocks,
                      void *buf)
{
    SCSITaskInterface **task;
    SCSITaskSGElement range;
    SCSITaskStatus status = 0;
    SCSI_Sense_Data sense;
    UInt64 transferred = 0;
    UInt8 cdb[10];
    IOReturn rc;

    task = (*p->task_dev)->CreateSCSITask(p->task_dev);
    if (task == NULL)
        return -1;

    cdb[0] = 0x28;                          /* READ(10) */
    cdb[1] = 0;
    cdb[2] = (lba >> 24) & 0xff;
    cdb[3] = (lba >> 16) & 0xff;
    cdb[4] = (lba >>  8) & 0xff;
    cdb[5] =  lba        & 0xff;
    cdb[6] = 0;
    cdb[7] = (blocks >> 8) & 0xff;
    cdb[8] =  blocks       & 0xff;
    cdb[9] = 0;

    range.address = (IOVirtualAddress)(uintptr_t)buf;
    range.length  = (UInt32)blocks * BD_BLOCK;

    if ((*task)->SetCommandDescriptorBlock(task, cdb, sizeof(cdb))
            != kIOReturnSuccess
     || (*task)->SetScatterGatherEntries(task, &range, 1, range.length,
                                         kSCSIDataTransfer_FromTargetToInitiator)
            != kIOReturnSuccess
     || (*task)->SetTimeoutDuration(task, READ10_TIMEOUT) != kIOReturnSuccess)
    {
        (*task)->Release(task);
        return -1;
    }

    memset(&sense, 0, sizeof(sense));
    rc = (*task)->ExecuteTaskSync(task, &sense, &status, &transferred);
    (*task)->Release(task);

    if (rc != kIOReturnSuccess || status != kSCSITaskStatus_GOOD) {
        msg_Warn(p->obj, "READ(10) at LBA %u failed (rc 0x%08x, status %d, "
                 "sense %02x/%02x/%02x)", lba, (unsigned)rc, (int)status,
                 sense.SENSE_KEY & 0x0f, sense.ADDITIONAL_SENSE_CODE,
                 sense.ADDITIONAL_SENSE_CODE_QUALIFIER);
        return -1;
    }

    return (int)(transferred / BD_BLOCK);
}

/*****************************************************************************
 * Claiming the drive
 *****************************************************************************/

static bool MatchesBSDName(io_service_t service, const char *psz_bsd_name)
{
    CFStringRef data;
    char name[128] = "";
    bool b_match;

    if (psz_bsd_name == NULL)
        return true;

    data = IORegistryEntrySearchCFProperty(service, kIOServicePlane,
                                           CFSTR(kIOBSDNameKey),
                                           kCFAllocatorDefault,
                                           kIORegistryIterateRecursively);
    if (data == NULL)
        return false;

    b_match = CFStringGetCString(data, name, sizeof(name),
                                 kCFStringEncodingASCII)
           && !strcmp(name, psz_bsd_name);
    CFRelease(data);

    return b_match;
}

/* Claims the drive behind one io_service_t. Leaves p->task_dev set and
 * exclusive access held on success. */
static int ClaimService(bluray_disc_t *p, io_service_t service)
{
    SInt32 score = 0;
    IOReturn rc;

    if (IOCreatePlugInInterfaceForService(service, kIOMMCDeviceUserClientTypeID,
                                          kIOCFPlugInInterfaceID, &p->plugin,
                                          &score) != kIOReturnSuccess
     || p->plugin == NULL)
        return VLC_EGENERIC;

    (*p->plugin)->QueryInterface(p->plugin,
                                 CFUUIDGetUUIDBytes(kIOMMCDeviceInterfaceID),
                                 (LPVOID *)&p->mmc);
    if (p->mmc == NULL)
        goto error;

    p->task_dev = (*p->mmc)->GetSCSITaskDeviceInterface(p->mmc);
    if (p->task_dev == NULL)
        goto error;

    /* Without this every command comes back refused -- verified, it is not
     * merely advisory. It also fails with kIOReturnBusy while the volume is
     * mounted, which is exactly the case this backend does not have to handle:
     * where the disc mounts, the raw device works and this code is not used. */
    rc = (*p->task_dev)->ObtainExclusiveAccess(p->task_dev);
    if (rc != kIOReturnSuccess) {
        msg_Dbg(p->obj, "could not obtain exclusive access (0x%08x)",
                (unsigned)rc);
        (*p->task_dev)->Release(p->task_dev);
        p->task_dev = NULL;
        goto error;
    }

    return VLC_SUCCESS;

error:
    if (p->mmc != NULL) {
        (*p->mmc)->Release(p->mmc);
        p->mmc = NULL;
    }
    if (p->plugin != NULL) {
        IODestroyPlugInInterface(p->plugin);
        p->plugin = NULL;
    }
    return VLC_EGENERIC;
}

bluray_disc_t *bluray_disc_OpenMMC(vlc_object_t *obj, const char *psz_bsd_name)
{
    /* IOBDServices is what a Blu-ray drive publishes from 10.5 on. Tiger has no
     * IOBDStorageFamily, so the same drive appears under IODVDServices there --
     * same MMC user client, same CDBs. Both are tried, BD first. */
    static const char *const ppsz_classes[] = { "IOBDServices", "IODVDServices" };

    bluray_disc_t *p = calloc(1, sizeof(*p));
    if (unlikely(p == NULL))
        return NULL;

    p->obj = obj;
    p->fd = -1;
    for (int i = 0; i < CACHE_WAYS; i++)
        p->way[i].lba = -1;
    vlc_mutex_init(&p->lock);

    /* Page aligned: the buffer is handed to the SCSI layer directly. */
    p->cache = valloc((size_t)CACHE_WAYS * CACHE_BLOCKS * BD_BLOCK);
    if (unlikely(p->cache == NULL))
        goto error;

    for (size_t i = 0; i < ARRAY_SIZE(ppsz_classes); i++) {
        io_iterator_t it = 0;
        io_service_t service;

        if (IOServiceGetMatchingServices(kIOMasterPortDefault,
                                         IOServiceMatching(ppsz_classes[i]),
                                         &it) != KERN_SUCCESS)
            continue;

        while ((service = IOIteratorNext(it)) != 0) {
            if (MatchesBSDName(service, psz_bsd_name)
             && ClaimService(p, service) == VLC_SUCCESS) {
                /* Only a drive that answers a read actually has our disc: with
                 * no BSD name to go on, the built-in SuperDrive matches too and
                 * comes back "medium not present". */
                uint8_t *probe = p->cache;
                if (SendRead10(p, 0, 1, probe) == 1) {
                    msg_Dbg(obj, "reading the disc over MMC (%s)",
                            ppsz_classes[i]);
                    IOObjectRelease(service);
                    IOObjectRelease(it);
                    return p;
                }
                (*p->task_dev)->ReleaseExclusiveAccess(p->task_dev);
                (*p->task_dev)->Release(p->task_dev);
                p->task_dev = NULL;
                (*p->mmc)->Release(p->mmc);
                p->mmc = NULL;
                IODestroyPlugInInterface(p->plugin);
                p->plugin = NULL;
            }
            IOObjectRelease(service);
        }
        IOObjectRelease(it);
    }

    msg_Dbg(obj, "no optical drive answered over MMC");

error:
    msg_Dbg(p->obj, "disc reader: %llu reads, %llu window refills",
            (unsigned long long)p->reads, (unsigned long long)p->refills);
    free(p->cache);
    vlc_mutex_destroy(&p->lock);
    free(p);
    return NULL;
}

/*
 * Raw device backend.
 *
 * Where the OS can read the disc (10.5, 10.6) libbluray could open the device
 * itself -- but it asks libudfread for one 6144 byte unit at a time, and that
 * request size is exactly what optical drives on USB 2 are worst at. Measured
 * on the Mac Mini G4: 6 KB gives 3.88 MB/s, i.e. 31 Mbps, which is the bitrate
 * of the reference disc with no margin at all -- the demuxer falls behind and
 * rebuffers. The same device answers 14.7 MB/s at 1 MB per request. So the
 * blocks go through the same read-ahead as the MMC path rather than straight to
 * libudfread. (A faster host hides this: the same 6 KB reads give 9.45 MB/s on
 * the MacBook Pro, which is why 10.6 looked fine without it.)
 */
bluray_disc_t *bluray_disc_OpenRaw(vlc_object_t *obj, const char *psz_device)
{
    bluray_disc_t *p = calloc(1, sizeof(*p));
    if (unlikely(p == NULL))
        return NULL;

    p->obj = obj;
    p->fd = -1;
    for (int i = 0; i < CACHE_WAYS; i++)
        p->way[i].lba = -1;
    vlc_mutex_init(&p->lock);

    p->cache = valloc((size_t)CACHE_WAYS * CACHE_BLOCKS * BD_BLOCK);
    if (unlikely(p->cache == NULL))
        goto error;

    p->fd = vlc_open(psz_device, O_RDONLY);
    if (p->fd == -1)
        goto error;

    /* Same rule as everywhere else here: a device that opens but answers
     * nothing is not usable (that is 10.4, where BD media is taken for a CD). */
    if (FetchBlocks(p, 0, 1, p->cache) != 1)
        goto error;

    msg_Dbg(obj, "reading the disc through %s with read-ahead", psz_device);
    return p;

error:
    if (p->fd >= 0)
        close(p->fd);
    msg_Dbg(p->obj, "disc reader: %llu reads, %llu window refills",
            (unsigned long long)p->reads, (unsigned long long)p->refills);
    free(p->cache);
    vlc_mutex_destroy(&p->lock);
    free(p);
    return NULL;
}

void bluray_disc_Close(bluray_disc_t *p)
{
    if (p == NULL)
        return;

    if (p->fd >= 0)
        close(p->fd);
    if (p->task_dev != NULL) {
        (*p->task_dev)->ReleaseExclusiveAccess(p->task_dev);
        (*p->task_dev)->Release(p->task_dev);
    }
    if (p->mmc != NULL)
        (*p->mmc)->Release(p->mmc);
    if (p->plugin != NULL)
        IODestroyPlugInInterface(p->plugin);

    msg_Dbg(p->obj, "disc reader: %llu reads, %llu window refills",
            (unsigned long long)p->reads, (unsigned long long)p->refills);
    free(p->cache);
    vlc_mutex_destroy(&p->lock);
    free(p);
}

void *bluray_disc_TaskInterface(bluray_disc_t *p)
{
    return p != NULL ? p->task_dev : NULL;
}

/*****************************************************************************
 * Block reader
 *****************************************************************************/

int bluray_disc_ReadBlocks(void *handle, void *buf, int lba, int num_blocks)
{
    bluray_disc_t *p = handle;
    uint8_t *out = buf;
    int done = 0;

    /* Either backend will do; the raw one has no task_dev, the MMC one no fd. */
    if (p == NULL || (p->fd < 0 && p->task_dev == NULL)
     || lba < 0 || num_blocks <= 0)
        return -1;

    vlc_mutex_lock(&p->lock);
    p->reads++;

    while (done < num_blocks) {
        int want = lba + done;

        /* Everything goes through the page-aligned window, including runs
         * larger than it, which are simply fetched a window at a time.
         *
         * Reading straight into the caller's buffer would save a copy but is
         * not safe: it belongs to libbluray and is only sector aligned, and a
         * raw device switches to the kernel's physio path above a few
         * kilobytes, where an unaligned buffer is rejected outright. Measured
         * on 10.5: a 6 KB pread into an unaligned buffer succeeds, the same
         * pread of 64 KB returns EFAULT -- which is what made libudfread fail
         * to open the disc at all. The copy costs nothing next to a USB 2
         * transfer. */
        int hit = -1;
        for (int i = 0; i < CACHE_WAYS; i++) {
            if (p->way[i].lba >= 0 && want >= p->way[i].lba
             && want < p->way[i].lba + p->way[i].count) {
                hit = i;
                break;
            }
        }

        if (hit < 0) {
            /* least recently used way; an unused one has stamp 0 and wins */
            int victim = 0;
            for (int i = 1; i < CACHE_WAYS; i++)
                if (p->way[i].stamp < p->way[victim].stamp)
                    victim = i;

            p->refills++;
            int got = FetchBlocks(p, want, CACHE_BLOCKS, CacheWay(p, victim));
            if (got <= 0) {
                p->way[victim].lba = -1;
                break;
            }
            p->way[victim].lba   = want;
            p->way[victim].count = got;
            hit = victim;
        }
        p->way[hit].stamp = ++p->clock;

        int offset = want - p->way[hit].lba;
        int avail  = p->way[hit].count - offset;
        int take   = num_blocks - done;
        if (take > avail)
            take = avail;

        memcpy(out + done * BD_BLOCK, CacheWay(p, hit) + offset * BD_BLOCK,
               (size_t)take * BD_BLOCK);
        done += take;
    }

    vlc_mutex_unlock(&p->lock);

    return done > 0 ? done : -1;
}

#endif /* __APPLE__ */
