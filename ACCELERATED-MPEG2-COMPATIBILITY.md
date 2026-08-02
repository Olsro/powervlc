# Accelerated MPEG-2 (DVD) playback — hardware compatibility

PowerVLC can hand MPEG-2 decoding to the GPU's dedicated video engine on PowerPC
Macs, and let the GPU also composite DVD subtitles on top of the decoded picture
at no per-frame cost. This document states **exactly which hardware is
supported**, how support is determined, and what it takes to add more.

It distinguishes three things that are easy to confuse:

* **Validated** — exercised on real hardware, judged correct by eye.
* **Candidate** — the driver family is present and the API matches, but the
  private-context layout has not been derived and nothing has been run.
* **Out of scope** — a different driver generation, needing different work.

## How compatibility is decided

Apple ships **one DVD decoding plug-in per GPU family**, in
`/System/Library/Extensions/`, and each plug-in attaches to exactly one IOKit
driver class:

| bundle | IOKit class it serves |
| --- | --- |
| `ATIRadeonDVDDriver.bundle` | `ATIRadeon` |
| `ATIRadeon8500DVDDriver.bundle` | `ATIRadeon8500` |
| `ATIRadeon9700DVDDriver.bundle` | `ATIRadeon9700` |
| `ATIRage128DVDDriver.bundle` | `ATIRage128` |
| `AppleAltiVecDVDDriver.bundle` | none — software fallback (AltiVec) |

PowerVLC opens a device by looking for an IOKit service of a given class and
loading the matching bundle. Today it asks for **`ATIRadeon` only** and loads
`ATIRadeonDVDDriver.bundle`. That is the whole gate: a Mac is supported if and
only if its GPU is claimed by the `ATIRadeon` kext.

**The authoritative test on any machine** is the PCI device ID, since factory
graphics options vary within a single Mac model:

```bash
ioreg -l -w 0 | grep -B2 -A2 IODVDBundleName
```

The `IODVDBundleName` property of the accelerator service names the very plug-in
Apple would use for that GPU. If it reports something other than
`ATIRadeonDVDDriver`, the machine is not supported by PowerVLC today.

> ⚠️ Do **not** force a family match. Pointing the `ATIRadeon` plug-in at a GPU of
> another family switches the hardware path on and then **wedges the GPU** — it
> happened on a Mac mini G4's Radeon 9200 on 2026-07-23 and required a full power
> cycle. Each family needs its own derivation (see the last section).

## Validated hardware

**GPU family: first-generation Radeon (IOKit class `ATIRadeon`).**
PCI vendor `0x1002` (ATI); the device ID is the high half-word.

| Device ID | Chip | Marketing name | Status |
| --- | --- | --- | --- |
| `0x4C57` | RV200 (M7) | Mobility Radeon 7500 | **Validated** |
| `0x5157` | RV200 | Radeon 7500 | Candidate (same silicon) |
| `0x5144` | R100 | Radeon 7200 / Radeon DDR | Candidate |
| `0x5159` | RV100 | Radeon 7000 / Radeon VE | Candidate |
| `0x515A` | RV100 | Radeon 7000 / VE variant | Candidate |
| `0x4C59` | RV100 (M6) | Mobility Radeon | Candidate |
| `0x4C5A` | RV100 (M6) | Mobility Radeon variant | Candidate |

Only the **RV200** has been run. The other six chips are served by the same kext
and the same plug-in, so they are the most likely to work unchanged — but "same
family" is not "tested", and this project has already seen one close cousin wedge
a GPU.

**Operating systems — all three validated on the same machine:**

| OS | Darwin | Hardware MPEG-2 decode | GPU-composited DVD subtitles |
| --- | --- | --- | --- |
| 10.2.8 Jaguar | 6 | ✅ | ✅ |
| 10.3.9 Panther | 7 | ✅ | ✅ |
| 10.4.11 Tiger | 8 | ✅ | ✅ |

10.5 Leopard still ships `ATIRadeonDVDDriver.bundle` with the same context layout
as 10.4, so the same code path should apply — **not yet run**.

Test machine: iBook G3 (Mobility Radeon 7500 / RV200), triple-boot 10.2.8 /
10.3.9 / 10.4.11.

### What "validated" covers

DVD playback windowed and full screen, full-screen toggling, seeks, DVD menus,
and GPU-composited subtitles. On Jaguar the hardware path is the difference
between **one frame in three decoded** and **~95 %**.

### Known caveat on this hardware

Apple's own ATI kernel driver for this generation is fragile: on the validated
iBook it has produced kernel panics in `IOGraphicsFamily` **under Apple's own DVD
Player**, unrelated to PowerVLC. Hardware decoding is enabled by default because
the gain is large and the failure mode is a hang rather than data loss, but a
machine that wedges needs a **complete power-off** — a warm restart leaves the
GPU degraded.

## Which Macs actually need this — and it is not the family we support

Worth stating plainly, because it reorders the priorities. **The supported family
is not "the G3 family".** Most G3 Macs carry a Rage part, not a Radeon:

| Mac | GPU | Family |
| --- | --- | --- |
| iMac G3 (all revisions) | Rage IIc / Rage Pro / Rage 128 VR / Pro / Ultra | `ATIRagePro` or `ATIRage128` |
| Power Mac G3 (beige) | Rage II+ / Rage Pro | `ATIRagePro` |
| Power Mac G3 (Blue & White) | Rage 128 | `ATIRage128` |
| PowerBook G3 (Wallstreet, Lombard) | Rage LT Pro | `ATIRagePro` |
| PowerBook G3 (Pismo), iBook G3 (clamshell, early Dual USB) | Rage Mobility 128 | `ATIRage128` |
| **iBook G3 (2002-2003)** | **Mobility Radeon 7500** | **`ATIRadeon` — supported** |

Conversely the `ATIRadeon` family lives mostly in **early G4 machines**: eMac
(2003, Radeon 7500), PowerBook G4 Titanium (Mobility M6/M7), Power Mac G4 with a
7000/7200/7500 card.

That matters because G4 and G5 have AltiVec and decode DVD-resolution MPEG-2 in
software without difficulty — the machines that genuinely need hardware offload
are the **G3s**, which have no AltiVec at all. On the validated iBook G3 the
difference is stark: one frame in three decoded in software against ~95 % in
hardware.

**So the family worth deriving next is `ATIRage128`, not `ATIRadeon8500`/`9700`.**
Its `DVDDriverDecode` is 1077 instructions against 1084 for the Radeon one, which
suggests a full decode engine rather than motion compensation alone — suggestive,
not proof; the function body has not been read. Its context uses the
global-pointer style (its `GetSPBuffer` dereferences a global at `0x5b58`), so the
layout must be derived from scratch, and its `DVDDriverSetSPBuffer` is a
6-instruction stub — meaning subtitles would need exactly the raw-packet recipe
already established for 10.2 Jaguar.

The oldest G3s — iMac G3 with Rage IIc/Pro, beige Power Mac G3, Wallstreet and
Lombard PowerBooks — fall under `ATIRagePro`, for which **Apple ships no DVD
plug-in at all**. They will never have an accelerated MPEG-2 path.

## Not supported yet — candidates, by family

These families have a DVD plug-in exposing the **same 26 entry points**, so no
new API work is needed. What is missing for each is the **private-context
layout**: PowerVLC reads a handful of fields directly (subpicture buffer arrays,
display flags, blit destination and pitch), and those offsets are per-plug-in.

### `ATIRadeon8500` — Radeon 8500 / 9000 / 9200

| Device ID | Chip | Marketing name |
| --- | --- | --- |
| `0x514C`, `0x516C` | R200 | Radeon 8500 / 9100 |
| `0x4966`, `0x4967` | RV250 | Radeon 9000 |
| `0x4C66` | RV250 (M9) | Mobility Radeon 9000 |
| `0x5960`, `0x5961`, `0x5962`, `0x5963` | RV280 | Radeon 9200 (Pro) |
| `0x5C63` | RV280 (M9+) | Mobility Radeon 9200 |

**Reconnaissance already done** (Mac mini G4, Radeon 9200 `0x5962`, 10.5.8): the
subpicture buffer arrays sit at `ctx[0x338+4i]` and `ctx[0x318+4i]`, against
`ctx[0x2F4+4i]` / `ctx[0x2D4+4i]` on the `ATIRadeon` plug-in — both exactly
`+0x44`. Several other fields shift by the same amount (`0x208`, `0x248`,
`0x458`, `0x1F4` all carry the occurrence counts of their `+0x44` counterparts),
but **the shift is not uniform** — the mode word and two others do not follow.
So the layout must be derived field by field, not by adding a constant.

### `ATIRadeon9700` — Radeon 9500 … X800

`0x4E44`, `0x4144`, `0x4E48`, `0x4148`, `0x4150`, `0x4E50`, `0x4152`, `0x4E54`,
`0x4E56` (R300/R350/RV350/RV360 — Radeon 9500 to 9800, Mobility 9600/9700),
`0x4A48`–`0x4A4E` (R420 — X800), `0x5B60`, `0x5B62`, `0x5B64`, `0x3E50`,
`0x3E54` (RV370/RV380 — X300/X550/X600).

### `ATIRage128` — Rage 128 and Rage 128 Pro

`0x5245`, `0x5246`, `0x524B`, `0x524C`, `0x5045`, `0x5046`, `0x5052`, `0x4C45`,
`0x4C46`, `0x5452`. Note its `DVDDriverSetSPBuffer` is a 6-instruction stub, so
subtitle compositing would need the same treatment as Jaguar's (see below).

### `ATIRagePro` — Rage LT Pro / Pro / XL

`0x4C49`, `0x4C47`, `0x4749`, `0x4750`, `0x4C4E`, `0x4756`. **No DVD plug-in
ships for this class**, so there is nothing to drive: these GPUs have no
accelerated MPEG-2 path on Mac OS X.

## Out of scope — a different driver generation

Mac OS X 10.5 introduced a second, unrelated plug-in generation, `*VADriver`,
alongside the legacy `*DVDDriver` ones. It covers everything newer:
`ATIRadeonX1000VADriver` (X1300/X1600/X1900 — `0x7187`, `0x7210`, `0x71DE`,
`0x7146`, `0x7142`, `0x7109`, `0x71C5`, `0x71C0`, `0x7240`, `0x7249`, `0x7291`),
`ATIRadeonX2000VADriver` (HD 2000/3000 series — the `0x94xx`/`0x95xx` range),
`GeForceVADriver` (**all** nVidia GPUs — the kext matches vendor `0x10DE` with a
`0xFFFF` mask), and `AppleIntelGMA950VADriver` / `AppleIntelGMAX3100VADriver`.

That generation is a different API and a separate effort; see the AppleVA notes
in the project documentation. It is also the path used for MPEG-2 acceleration on
Intel Macs.

## Adding a family — what it takes

1. **Match its IOKit class and load its own plug-in.** Both are currently
   hardcoded; the bundle path can already be overridden at runtime with the
   `POWERVLC_ATI_BUNDLE` environment variable.
2. **Derive the private-context layout** for that plug-in, by disassembly.
   `DVDDriverGetSPBuffer` gives the two subpicture buffer arrays directly;
   `DVDDriverShowMPBuffer` reveals the display flags it gates on. Use a
   period-correct `otool` — modern ones reject these Mach-O files
   ("load command 18 obsolete").
3. **Check whether `DVDDriverSetSPBuffer` is a stub.** On some plug-ins it does
   not blit: it only records the buffer index and raises a redraw flag. Those
   need the raw SPU packet deposited in the second buffer series and one
   `DVDDriverApplySPDCSQ` call per command of the *first* display-control
   sequence — the recipe derived for 10.2 Jaguar.
4. **Validate on the actual silicon**, one chip at a time, with the machine
   physically reachable. Expect GPU wedges while getting it wrong, and expect to
   power the machine fully off after each one.
