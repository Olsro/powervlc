# Accelerated MPEG-2 (DVD) playback — hardware compatibility

PowerVLC can hand MPEG-2 decoding to the GPU's dedicated video engine on PowerPC
Macs, and let the GPU also composite DVD subtitles and menu-button highlights on
top of the decoded picture at no per-frame cost. This document states **exactly
which hardware is supported**, how support is determined, and what it takes to
add more.

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

PowerVLC **discovers the plug-in dynamically**: it walks the IOKit registry for
the accelerator node's `IODVDBundleName` property — the very plug-in Apple itself
would use for that GPU — and derives the bundle path from it. Nothing is
hardcoded to one machine.

Discovery alone is not the gate, however. A family is used only if it also
appears in the **admitted-families table** (`s_dd_families` in
`modules/codec/dvddriver_backend.c`), which carries the per-plug-in facts that
cannot be discovered: private-context size, subpicture layout offsets, and the
handful of behavioural quirks each plug-in has. Two families are admitted today:
**`ATIRadeon`** and **`ATIRage128`**.

**The authoritative test on any machine:**

```bash
ioreg -l -w 0 | grep -B2 -A2 IODVDBundleName
```

If it reports a bundle whose class is not in the admitted table, the machine
falls back to software decoding — safely, and by design.

> ⚠️ Do **not** force a family match. Pointing one family's plug-in at a GPU of
> another family switches the hardware path on and then **wedges the GPU** — it
> happened on a Mac mini G4's Radeon 9200 on 2026-07-23 and required a full power
> cycle. Each family needs its own derivation (see the last section).

## Validated hardware

Two families, each on its own machine.

### `ATIRadeon` — first-generation Radeon

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

Test machine: iBook G3 (Mobility Radeon 7500 / RV200), triple-boot 10.2.8 /
10.3.9 / 10.4.11.

### `ATIRage128` — Rage 128 and Rage 128 Pro

| Device ID | Chip | Marketing name | Status |
| --- | --- | --- | --- |
| `0x4C46` | Rage Mobility M3 | Mobility 128 | **Validated** |
| `0x5245`, `0x5246`, `0x524B`, `0x524C` | Rage 128 GL/VR | Rage 128 | Candidate |
| `0x5045`, `0x5046`, `0x5052` | Rage 128 Pro | Rage 128 Pro | Candidate |
| `0x4C45` | Rage Mobility M3 variant | Mobility 128 | Candidate |
| `0x5452` | Rage 128 Pro Ultra | — | Candidate |

Test machine: iBook G3 Dual USB 600 MHz (`PowerBook4,1`, `ATY,RageM3`, 8 MB
VRAM, 256 MB RAM), triple-boot 10.2.8 / 10.3.9 / 10.4.11. This is the most
constrained machine in the fleet and the one that most needs the offload.

Its context layout differs from the Radeon one in two zones, and **10.2 ships a
completely different driver binary** (42 748 bytes) from 10.3/10.4 — different
context size (348 bytes against 760) and a different subpicture mechanism. Both
are handled; see the caveats below.

### Operating systems

Validated on **both** machines:

| OS | Darwin | Hardware MPEG-2 decode | GPU-composited subtitles | GPU-composited menu highlight |
| --- | --- | --- | --- | --- |
| 10.2.8 Jaguar | 6 | ✅ | ✅ | ✅ |
| 10.3.9 Panther | 7 | ✅ | ✅ | ✅ |
| 10.4.11 Tiger | 8 | ✅ | ✅ | ✅ |

10.5 Leopard still ships `ATIRadeonDVDDriver.bundle` with the same context layout
as 10.4, so the same code path should apply — **not yet run**.

### What "validated" covers

DVD playback windowed and full screen, full-screen toggling, seeks, **animated
DVD menus decoded on the GPU**, GPU-composited subtitles, and **menu-button
highlights composited by the GPU**, following both mouse and keyboard.

On the Rage 128 iBook, animated menus decode in **6.4 ms per frame against a
40 ms budget**, with presentation at 75 µs. On Jaguar the hardware path is the
difference between **one frame in three decoded** and **~95 %**.

## Known caveats

**Apple's own ATI kernel driver for this generation is fragile.** On the
validated Radeon iBook it has produced kernel panics in `IOGraphicsFamily`
**under Apple's own DVD Player**, unrelated to PowerVLC. Hardware decoding is
enabled by default because the gain is large and the failure mode is a hang
rather than data loss, but a machine that wedges needs a **complete power-off** —
a warm restart leaves the GPU degraded.

**Full screen from a *still* menu shows black until the next picture.** The
surface follows the window by *reopening* the decoder, and every reopen path is
written "at the next I picture" — because that is the only moment the decoder
runs. A still menu emits no further picture, so the surface stays attached to the
windowed window and the full-screen window shows black. It is not a freeze and
nothing is lost: any action that produces a new picture — including blind
keyboard navigation in the menu — restores it immediately, as does returning to
windowed mode. Animated menus and films are unaffected.

The proper fix has been scoped and deliberately deferred: it needs a decoder-side
service thread (nothing else runs when no picture flows) **and** retention of the
last submitted picture so it can be replayed into the freshly reopened context.
Half of it is worthless without the other half. ⚠️ Do **not** attempt the obvious
shortcut of re-attaching the surface to the new window while the device stays
open: it was tried, and it breaks the decoder→surface binding permanently — black
in full screen *and* after returning to windowed. Only `DVDDriverOpenDevice`
establishes that binding reliably (see `dvddriver_bind_window`, kept as a
deliberately empty function carrying that warning).

## Two decoding lessons that are not family-specific

Both were established on 2026-08-05 and both live in the codec layer, so they
apply to every family.

**Coefficient scan order.** MPEG-2 has two coefficient scan orders, chosen per
picture by `alternate_scan`. The ATI descriptor format carries only (skip, value)
pairs — it cannot express which order is in use, so the driver always assumes the
classic zigzag. Feeding it the picture's own table wrecks every coefficient that
is not the DC term. Symptom to recognise: the image stays **geometrically
correct** (the DC term is at position 0 in both tables, so each block's average
brightness is right) but **loses all detail, in coarse blocks**. That is *not*
the signature of wrong motion compensation, which displaces blocks instead. DVD
menus are frequently authored with alternate scan while the feature film is not —
which is exactly how this stayed hidden.

⚠️ **libmpeg2 permutes its scan tables** at IDCT init (and permutes them
*differently* in the AltiVec build). `DCTblock` is therefore not in raster order,
and only libmpeg2's own table can read it back. Never write a zigzag table by
hand, and never identify a table by its contents — after permutation `scan[1]` is
4 and 32, not 1 and 8. Compare pointers.

**Field prediction works.** The ATI field motion-compensation engine was believed
for several sessions to be an unreversible wall. It is not: once the scan-order
defect was fixed, interlaced menus decoded correctly *through that very engine*.
The earlier verdict was reached by attributing corruption to the only suspicious
feature known to be present, without checking that removing it removed the
corruption — it did not.

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

### `ATIRagePro` — Rage LT Pro / Pro / XL

`0x4C49`, `0x4C47`, `0x4749`, `0x4750`, `0x4C4E`, `0x4756`. **No DVD plug-in
ships for this class**, so there is nothing to drive: these GPUs have no
accelerated MPEG-2 path on Mac OS X. This covers the oldest G3s — iMac G3 with
Rage IIc/Pro, beige Power Mac G3, Wallstreet and Lombard PowerBooks.

## Which Macs this covers

With `ATIRage128` validated, the coverage now includes most of the machines that
actually need it. G4 and G5 have AltiVec and decode DVD-resolution MPEG-2 in
software without difficulty; the machines that genuinely need hardware offload
are the **G3s**, which have no AltiVec at all.

| Mac | GPU | Family | Status |
| --- | --- | --- | --- |
| Power Mac G3 (Blue & White) | Rage 128 | `ATIRage128` | Supported |
| PowerBook G3 (Pismo), iBook G3 (clamshell, early Dual USB) | Rage Mobility 128 | `ATIRage128` | Supported |
| iMac G3 (later revisions) | Rage 128 VR / Pro / Ultra | `ATIRage128` | Supported |
| iBook G3 (2002-2003) | Mobility Radeon 7500 | `ATIRadeon` | Supported |
| iMac G3 (early), Power Mac G3 (beige), PowerBook G3 (Wallstreet, Lombard) | Rage IIc / Pro / LT Pro | `ATIRagePro` | No Apple plug-in — never |

The `ATIRadeon` family also covers early G4 machines: eMac (2003, Radeon 7500),
PowerBook G4 Titanium (Mobility M6/M7), Power Mac G4 with a 7000/7200/7500 card.

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

1. **Add it to the admitted-families table** (`s_dd_families`). Bundle discovery
   is already automatic via `IODVDBundleName`; what the table supplies is the
   per-plug-in layout and quirks. ⚠️ Its initialisers are positional — update
   *every* entry when adding a field.
2. **Derive the private-context layout** for that plug-in, by disassembly.
   `DVDDriverGetSPBuffer` gives the two subpicture buffer arrays directly;
   `DVDDriverShowMPBuffer` reveals the display flags it gates on. Use a
   period-correct `otool` — modern ones reject these Mach-O files
   ("load command 18 obsolete"). ⚠️ Follow the *context register* (`r3` on entry
   and its copies) and ignore stack-based accesses: mixing the two produced a
   map with fields that do not exist, and cost several wrong turns.
3. **Check whether `DVDDriverSetSPBuffer` is a stub.** On some plug-ins it does
   not blit: it only records the buffer index and raises a redraw flag. Those
   need the raw SPU packet deposited in the second buffer series and one
   `DVDDriverApplySPDCSQ` call per command of the *first* display-control
   sequence — the recipe derived for 10.2 Jaguar and reused for the Rage 128.
   ⚠️ On such plug-ins **the driver parses that raw packet itself**, so menu
   highlights need their colours rewritten *inside the packet copy* — overriding
   them in our own descriptor has no effect there. This is why hardware subtitles
   can work perfectly while the menu highlight stays invisible.
4. **Validate on the actual silicon**, one chip at a time, with the machine
   physically reachable. Expect GPU wedges while getting it wrong, and expect to
   power the machine fully off after each one.
   ⚠️ Deploy **every** plug-in the change touches, not just the one you edited.
   A stale `libmacosx_qt_plugin` on one boot partition presented as a real bug
   (inverted mouse selection in menus) and cost an hour of searching in code that
   was already correct.
