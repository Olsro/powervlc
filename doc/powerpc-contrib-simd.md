# PowerPC contrib SIMD audit and G4 benchmarks

This note records the 2026-08-22 sync against
[`macos-powerpc/powerpc-ports`](https://github.com/macos-powerpc/powerpc-ports)
at commit `17d8cbbd22a271329fa9d9823f89a8187501b205` and the measurements used to
decide which patches PowerVLC ships.

## Test machine and build

- Mac mini `PowerMac10,1`, 1.42 GHz PowerPC 7450 (7447A), one CPU and an
  AltiVec unit.
- Mac OS X 10.4.11 / Darwin 8.11.0.
- PowerVLC legacy cross-toolchain: FSF GCC 13, Mac OS X 10.4u SDK, deployment
  target 10.2, `-mcpu=7400 -mtune=7400 -maltivec -mabi=altivec`.
- All end-to-end measurements are mono-threaded and are the mean of three
  runs on the physical machine (interleaved C/AltiVec for x264).

## dav1d 1.5.4

The refreshed `powerpc-ports` patches fix three issues in the former local
series: 32-bit big-endian PPC now gets the stack alignment required by its
AltiVec buffers, the generic inverse-transform/motion-compensation/loop-filter
dispatchers are enabled for `ARCH_PPC` rather than only `ARCH_PPC64LE`, and
the big-endian Wiener restoration shuffle is corrected. The later compound
prediction and sub-pixel MC patches were already current. PowerVLC's Darwin
runtime AltiVec check remains last in the series.

Correctness was checked with dav1d checkasm 1.2.0, seed 42. The former build
failed `wiener_7tap_8bpc_altivec` and `wiener_5tap_8bpc_altivec`, while most
AltiVec families were not installed by the dispatcher. The refreshed build
passes all 658 AltiVec checks, including CDEF, inverse transforms, loop
filters, Wiener restoration, motion compensation and compound blending.

`checkasm --bench --duration=100 --json 42` measured 294 AltiVec functions:
278 beat their C reference and the geometric-mean speed-up is 2.70x. An
experiment that left the two slower horizontal-loop-filter families in C was
also tested, but made a real decode 0.36% slower, so it is deliberately not
shipped.

The application benchmark decodes a 60-second, 1,440-frame, 848x480 AV1 IVF
stream with `--threads 1 --framedelay 1 --filmgrain 0 --quiet`:

| dav1d build | Mean user time | Throughput |
|---|---:|---:|
| Former PowerVLC patches | 20.643 s | 69.76 fps |
| Refreshed patches | 18.360 s | 78.43 fps |

That is 11.06% less CPU time and 12.43% more decoding throughput.

## x264

The two `powerpc-ports` patches restore the VSX-less big-endian AltiVec
backend and fix chroma-MC byte order plus uninitialised vector lanes. A small
PowerVLC configure patch substitutes FSF GCC's AltiVec flags for the historic
Apple GCC flags and enables `<altivec.h>`. VSX stays disabled because Tiger's
PowerPC assembler cannot encode those POWER7 instructions. G4/G5 contribs now
use AltiVec; the G3 contrib continues to pass `--disable-asm`.

x264 checkasm passes every reported 8-bit family (29 groups) and the 10-bit
path. A final PowerVLC tuning patch leaves the four tiny registrations that
lose on the 7447A in C. Its full 8-bit micro-benchmark then pairs 103 AltiVec
functions with C: all 103 win and the geometric-mean kernel speed-up is 2.65x.
Three interleaved encodes put this selection 0.1% ahead of the complete
upstream registration (inside run-to-run noise), so it has no application
regression and also avoids the much slower field-scan kernel on interlaced
input.

The end-to-end test encodes 240 YUV420 frames at 352x288, preset `medium`,
CRF 23 and one thread:

| x264 build | Mean user time | Throughput | Output bitrate |
|---|---:|---:|---:|
| C (`--disable-asm`) | 21.273 s | 10.27 fps | 348.65 kbit/s |
| AltiVec, G4-tuned | 10.513 s | 20.08 fps | 348.65 kbit/s |

The AltiVec build uses 50.58% less CPU time and is 1.96x faster end to end.
Both encoded elementary streams have the same MD5,
`b06cb77a815189ac45ab05a1870f3707`.

## FFmpeg and other ports

PowerVLC already contained every `powerpc-ports` FFmpeg patch useful to the
shared G4/G5 contrib. Upstream patches 1 through 31 match the local imported
series (apart from deliberate overlap-removal subsets); patches 32 through 38
were originally taken from PowerVLC's own H.264, HEVC and 7447A tuning work.
Patch 39 only refines G5-specific `_ARCH_PWR4` registration. The shared
contrib is compiled for a 7400 and already has the G4-optimal width floors, so
importing it would not change the generated G4 code.

The other current candidates do not improve a supported slice: AOM's PPC
backend needs ISA 2.06 (newer than a G4), libvpx is intentionally not built on
legacy Darwin PPC, and x265 is an encoder that is unavailable on the 10.2
target and whose Apple PPC path is disabled by the port. No new G3 or Intel
patch from this audit had a reachable, measurable benefit.
