/*****************************************************************************
 * VLCApplication.m: MacOS X interface module
 *****************************************************************************
 * Copyright (C) 2002-2016 VLC authors and VideoLAN
 * $Id$
 *
 * Authors: Derk-Jan Hartman <hartman at videolan.org>
 *          Felix Paul Kühne <fkuehne at videolan dot org>
 *          Pierre d'Herbemont <pdherbemont # videolan org>
 *          David Fuhrmann <david dot fuhrmann at googlemail dot com>
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
 * Preamble
 *****************************************************************************/

#import "VLCApplication.h"
#import "VLCMain.h"

#include <vlc_playlist.h>
#include <vlc_services_discovery.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>

/* A mounted NAS can leave a kernel stat() uninterruptible for minutes. The
 * media-library shutdown correctly requests cancellation, but libvlc_release
 * must still join that thread and Cocoa's main thread would consequently
 * appear frozen. Hide the already-closing application immediately and keep a
 * final process-level deadline. Normal cleanup exits well before it; only a
 * wedged network syscall reaches _exit(). Scan checkpoints make that fallback
 * recoverable (at most the current checkpoint batch is replayed). */
static void *VLCQuitWatchdog(void *opaque)
{
    (void)opaque;
    struct timespec delay = { 3, 0 };
    while (nanosleep(&delay, &delay) != 0)
        ;
    _exit(0);
}

static void VLCStartQuitWatchdog(void)
{
    pthread_t thread;
    if (pthread_create(&thread, NULL, VLCQuitWatchdog, NULL) == 0)
        pthread_detach(thread);
}

static BOOL VLCDeviceTransferIsActive(void)
{
    playlist_t *playlist = pl_Get(getIntf());
    for (NSUInteger index = 0; index < 64; ++index) {
        NSString *service = [NSString stringWithFormat:
            @"powervlc_device{index=%lu}", (unsigned long)index];
        if (!playlist_IsServicesDiscoveryLoaded(playlist, service.UTF8String))
            continue;
        services_discovery_transfer_status_t status = { 0 };
        int result = playlist_ServicesDiscoveryControl(playlist,
            service.UTF8String, SD_CMD_POWERVLC_DEVICE_TRANSFERS, &status);
        BOOL active = result == VLC_SUCCESS && status.b_synchronizing;
        for (size_t i = 0; i < status.i_count; ++i) {
            free(status.p_items[i].psz_source);
            free(status.p_items[i].psz_destination);
        }
        free(status.p_items);
        if (active) return YES;
    }
    return NO;
}

static BOOL VLCDeviceHasPendingChanges(void)
{
    playlist_t *playlist = pl_Get(getIntf());
    for (NSUInteger index = 0; index < 64; ++index) {
        NSString *service = [NSString stringWithFormat:
            @"powervlc_device{index=%lu}", (unsigned long)index];
        if (!playlist_IsServicesDiscoveryLoaded(playlist, service.UTF8String))
            continue;
        services_discovery_transfer_status_t status = { 0 };
        int result = playlist_ServicesDiscoveryControl(playlist,
            service.UTF8String, SD_CMD_POWERVLC_DEVICE_TRANSFERS, &status);
        BOOL pending = result == VLC_SUCCESS && status.b_pending_changes;
        for (size_t i = 0; i < status.i_count; ++i) {
            free(status.p_items[i].psz_source);
            free(status.p_items[i].psz_destination);
        }
        free(status.p_items);
        if (pending) return YES;
    }
    return NO;
}

static void VLCDevicePendingChangesControl(int command)
{
    playlist_t *playlist = pl_Get(getIntf());
    for (NSUInteger index = 0; index < 64; ++index) {
        NSString *service = [NSString stringWithFormat:
            @"powervlc_device{index=%lu}", (unsigned long)index];
        if (playlist_IsServicesDiscoveryLoaded(playlist, service.UTF8String))
            playlist_ServicesDiscoveryControl(playlist, service.UTF8String,
                                               command);
    }
}

/*****************************************************************************
 * VLCApplication implementation
 *****************************************************************************/

@implementation VLCApplication
// when user selects the quit menu from dock it sends a terminate:
// but we need to send a stop: to properly exits libvlc.
// However, we are not able to change the action-method sent by this standard menu item.
// thus we override terminate: to send a stop:
- (void)terminate:(id)sender
{
    [self activateIgnoringOtherApps:YES];
    if (VLCDeviceTransferIsActive()) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = _NS("Synchronization in progress");
        alert.informativeText = _NS("A portable player is still being synchronized. Quitting now will interrupt the current transfer.");
        [alert addButtonWithTitle:_NS("Continue Synchronization")];
        [alert addButtonWithTitle:_NS("Quit Anyway")];
        if ([alert runModal] != NSAlertSecondButtonReturn)
            return;
    }
    if (VLCDeviceHasPendingChanges()) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = _NS("Portable-player changes are pending");
        alert.informativeText = _NS("One or more iPods contain changes that have not been validated. Validate them before quitting, or discard them.");
        [alert addButtonWithTitle:_NS("Finalize Changes")];
        [alert addButtonWithTitle:_NS("Quit Without Finalizing")];
        [alert addButtonWithTitle:_NS("Cancel")];
        NSInteger answer = [alert runModal];
        if (answer == NSAlertFirstButtonReturn) {
            VLCDevicePendingChangesControl(SD_CMD_POWERVLC_DEVICE_COMMIT);
            return;
        }
        if (answer != NSAlertSecondButtonReturn)
            return;
        VLCDevicePendingChangesControl(SD_CMD_POWERVLC_DEVICE_DISCARD);
    }
    VLCStartQuitWatchdog();
    /* The user has completed every quit confirmation. Do not leave a frozen
     * window visible while libvlc performs its bounded cleanup. */
    [self hide:sender];
    [self stop:sender];

    // Trigger event in loop to force evaluating the stop flag
    NSEvent* event = [NSEvent otherEventWithType:NSApplicationDefined
                                        location:NSMakePoint(0,0)
                                   modifierFlags:0
                                       timestamp:0.0
                                    windowNumber:0
                                         context:nil
                                         subtype:0
                                           data1:0
                                           data2:0];
    [NSApp postEvent:event atStart:YES];
}

@end
