/*****************************************************************************
 * macosx_crystalhd.h: Crystal HD driver detection and installation
 *****************************************************************************
 * Copyright © 2026 PowerVLC
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

/*
 * Shared by both Mac interfaces, as plain C functions rather than a class:
 * the legacy and modern interfaces are separate plugins, and a duplicated
 * Objective-C class name would collide in the runtime if both were ever
 * loaded (which is why every legacy class carries the VLCLegacy prefix).
 */

#ifndef VLC_MACOSX_CRYSTALHD_H
#define VLC_MACOSX_CRYSTALHD_H

#import <Foundation/Foundation.h>

typedef enum {
    /* No card and no driver: nothing to offer. */
    VLCCrystalHDAbsent,
    /* Card in the machine, driver not installed: the case worth prompting
     * about, since acceleration is one install away. */
    VLCCrystalHDCardWithoutDriver,
    /* Both present: nothing to do but offer removal. */
    VLCCrystalHDReady,
    /* Driver installed but no card, typically after the card was removed.
     * Worth offering to clean up. */
    VLCCrystalHDDriverWithoutCard,
} VLCCrystalHDState;

/**
 * Current state of the card and its driver.
 */
VLCCrystalHDState VLCCrystalHDGetState(void);

/**
 * Whether the bundled driver can be loaded by the kernel that is running.
 *
 * The bundled kext is 32-bit only, and a kext has to match the kernel's
 * architecture rather than the CPU's -- a 64-bit Mac happily runs a 32-bit
 * kernel, and many of them do. When this returns NO there is nothing to
 * install until a 64-bit driver ships.
 */
BOOL VLCCrystalHDDriverMatchesKernel(void);

/**
 * Whether this version of macOS can still be booted with a 32-bit kernel.
 *
 * True up to Mac OS X 10.7; 10.8 dropped the 32-bit kernel entirely. Only
 * meaningful when VLCCrystalHDDriverMatchesKernel() returned NO, to tell the
 * user whether rebooting would actually help.
 */
BOOL VLCCrystalHDCanBoot32BitKernel(void);

/**
 * Whether this process cannot reach the card because of its own architecture.
 *
 * macOS runs the x86_64 slice of a universal binary as soon as the CPU is
 * 64-bit, whatever the kernel is. On a Mac whose kernel stays 32-bit -- the
 * GMA 950 machines have no 64-bit graphics driver, so they never boot a
 * 64-bit kernel -- the driver is 32-bit too and cannot serve a 64-bit
 * process. The card is then present and installed, yet unusable, with
 * nothing on screen to explain it.
 */
BOOL VLCCrystalHDBlockedBy64BitProcess(void);

/**
 * Whether the user asked not to be prompted again at startup.
 */
BOOL VLCCrystalHDStartupPromptSuppressed(void);
void VLCCrystalHDSuppressStartupPrompt(void);

/**
 * Install or remove the driver, asking the user for administrator rights.
 *
 * Both return NO and fill in *ppsz_error (autoreleased, may be NULL) on
 * failure, including when the user cancels the authorisation dialog.
 */
BOOL VLCCrystalHDInstallDriver(NSString **ppsz_error);
BOOL VLCCrystalHDUninstallDriver(NSString **ppsz_error);
BOOL VLCCrystalHDReloadDriver(NSString **ppsz_error);

/**
 * Complete install flow: explains what the card can do, asks, installs, and
 * reports the outcome. Both interfaces share it so they say the same thing.
 *
 * \param b_offerSuppress add a "Don't ask again" choice, for the prompt shown
 *        automatically at startup. Pass NO when the user asked for it.
 * \return YES when the driver ended up installed.
 */
BOOL VLCCrystalHDRunInstallFlow(BOOL b_offerSuppress);

/**
 * Complete removal flow, with confirmation and outcome.
 */
BOOL VLCCrystalHDRunUninstallFlow(void);
/* Takes the driver out and puts it back: the only thing that clears a card
 * left refusing every open by an abnormal exit. */
BOOL VLCCrystalHDRunReloadFlow(void);

/**
 * Prompt shown once at startup when a card is present without its driver.
 * Does nothing when there is no card, the driver is already there, or the
 * user asked not to be reminded.
 */
void VLCCrystalHDMaybePromptAtStartup(void);

#endif /* VLC_MACOSX_CRYSTALHD_H */
