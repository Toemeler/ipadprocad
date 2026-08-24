# Lane C — the headless kernel benchmark

A C++ benchmark against the OCCT C-ABI shim. No iOS, no Flutter, no device: it
builds and runs anywhere the shim builds, in minutes.

```bash
# once — the kernel it measures
git submodule update --init --depth 1 -- backend/occt/upstream
cmake -S backend/occt/upstream -B backend/occt/build-occt-host -G Ninja \
      -DINSTALL_DIR="$PWD/backend/occt/install-host" \
      $(sed -n '/OCCT_COMMON_FLAGS/,/USE_VTK=OFF/p' \
          .github/workflows/occt-build.yml | grep -o '\-D[A-Za-z_]*=[A-Za-z]*')
cmake --build backend/occt/build-occt-host -j && \
cmake --install backend/occt/build-occt-host

# every time
cmake -S backend/bench -B build-bench -G Ninja -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="$PWD/backend/occt/install-host"
cmake --build build-bench -j
./build-bench/occt_bench --md bench-out/kernel-bench.md \
                         --json bench-out/kernel-bench.json
```

`--quick` is a three-rung, three-rep run for when you only want the shape.
`--help` lists the rest.

---

## What these numbers may and may not be used for

This is not negotiable and it is repeated on every output the harness produces.
`PERFORMANCE_PROFILE.md` §13.3 states the rule for the simulator track and the
same reasoning applies here, for a stronger reason — this runs on a desktop, at
a higher clock, with no thermal ceiling and no memory pressure.

| May be read | May **not** be read |
| --- | --- |
| Relative cost between operations | Any absolute millisecond as an iPad millisecond |
| Fitted exponents and their intervals | A predicted device duration |
| Allocation counts, bytes, RSS | Frame times, jank, anything about rendering |
| Structural change — "does it still do this per edge?" | A verdict on whether a change is *worth* shipping |

Quoting a desktop millisecond as a device millisecond is the M75 error in new
clothing, and the profile spends a whole section on what that cost the first
time.

---

## Why it is trustworthy: the calibration

A benchmark nobody has checked is an opinion. This one is checked against the
device, on the two exponents that `PERFORMANCE_PROFILE.md` §6.5 establishes over
four independent lines of evidence, reproduced on two clock arms:

| Quantity | Device | Where |
| --- | --- | --- |
| one `occt_shape_edge_info` against a **growing shape** | k = 0.99, CI [0.97, 1.01] | §6.5 evidence 2 |
| the full per-edge **enumeration** | k = 2.012, CI [1.910, 2.113] | §6.5 evidence 4 |
| the control (`buildOnly`: build + counts + full mesh) | k = 1.063, CI [0.959, 1.167] | §6.5 evidence 4 |

`--validate` makes agreement — interval overlap — the exit code. If the harness
does not reproduce those exponents, **the harness is wrong, not the device**
(`OPTIMIZATION_PLAN.md` §5, Session 1).

The fixture is the device fixture. `stress.kernel.allEdges` builds
`extrudeProfileArcs(ringProfile(n, 40), 10.0)`; `ringProfile` is a regular
n-gon of radius 40 with every bulge zero (`frontend/lib/perf_scenarios.dart`
:151), so the solid is an n-gon prism with 3n edges and n+2 faces.
`bench_occt.cpp` rebuilds exactly that in C and sweeps the same rungs.
Comparability to §6.5 rests on it — do not "improve" the fixture without
re-deriving the calibration.

The statistics are the device's statistics. `bench_stats.cpp` is a deliberate
translation of `ci/perf_profile.py`'s `fit()`, down to the `n > 2` rule for
standard errors and the 1.96 multiplier; the fast CI job feeds both
implementations the profile's own published rungs and fails if they disagree in
the ninth decimal. Change one and you must change the other.

### The gate expires, on purpose

`CALIBRATION.txt` records the content hash of `occt_capi.cpp`. While it
matches, the exponent check **fails the CI job**. Once the shim changes it
becomes informational — because Session 2's entire job is to make `allEdges`
stop fitting 2.012, and a permanent gate on that exponent would go red forever
for the best possible reason. See that file for when to re-record it.

### One thing the harness reports about the profile

Refitting §6.5 evidence 4's three published rungs reproduces k = 2.0117 and
se = 0.00799 exactly, but the printed interval [1.910, 2.113] is
k ± 12.706·se — the Student-t interval at one degree of freedom, where
evidence 1 (N = 7) and evidence 2 (N = 4) in the same section both print
k ± 1.96·se, which is what `ci/perf_profile.py` computes. Two conventions in
one section. The published interval is 6.4× wider than the tooling's, so
gating on it alone would be a lenient test wearing a strict test's clothes:
the harness therefore reports the comparison against **both**, gates on the
published one, and logs the discrepancy in `perf/findings/CROSS-SESSION.md`
(S1-1) rather than fixing a file it does not own.

---

## What it measures

Per rung of the ladder (default 60 / 120 / 240 / 480 profile points =
180 / 360 / 720 / 1440 edges — the device's `stress.allEdges` rungs, with one
smaller rung added so the fit has four points like evidence 2 rather than
three):

| op | what it is | why |
| --- | --- | --- |
| `build` | `occt_extrude_profile_arcs` | the fixture's own cost; §6.1 |
| `edgeInfo1` | ONE `occt_shape_edge_info`, index 1 | §6.5 evidence 2 — the per-call cost against shape size |
| `allEdges` | the per-edge loop `OcctShape.allEdges()` runs | §6.5 — the quadratic, with the FFI boundary out of the picture |
| `buildOnly` | build + `counts` + full mesh | §6.5 evidence 4's control — it does strictly *more* work |
| `counts`, `bbox` | whole-shape queries | §6.5 evidence 3 — touching the shape is cheap |
| `mesh` | `occt_mesh_create` at the app's 0.2 / 0.35 | §6.4 |
| `fuse`, `cut` | booleans on operands of the rung's complexity | §6.2 |
| `rayHits` | one ray through the solid | §6.7, the 3D pick path |
| `filletEx1` | `occt_fillet_edges_ex`, one edge | §6.3 against shape size |

Then the SWEEP ladders — the axis no tier measured until the device did, and
the one that found a defect rather than a cost. The fixture is the perf tier's
own (`perf_scenarios_profile.dart`): `arcRing(segments, 6)` swept along
`arcPath(spans + 1, 60)`, a quarter turn of radius 18 climbing to z = 60.

| op | swept axis | what it answers |
| --- | --- | --- |
| `sweep.segments` | 32 / 64 / 128 (default) | the shipped path, `OCCT_SWEEP_PATH_AUTO` |
| `sweep.legacy` | the same, capped at `--sweep-legacy-max` | **v23**, `OCCT_SWEEP_PATH_POLY` — old against new in ONE run |
| `sweep.coil` | the same | the CONTROL: `occt_coil_profile` sweeps the same quarter turn along an exact helix |
| `sweep.spans` | 1 / 2 / 4 / 8 / 16 | corner COUNT against total TURNING — the two are separable here |
| `sweep.ph.*` | per rung | the five phases inside one v23 call |
| `sweep.var.*` | at one rung | the levers, each with its volume, face count and validity |

Three things about them are deliberate:

* **The legacy arm is capped** (`--sweep-legacy-max`, default 128). v23 costs
  **447 s** at 512 segments and does not finish at all at 1200 — it fails after
  **742 s**. A job that runs on every push cannot climb that; the cap moves for
  anyone who wants to watch it break.
* **A failed rung is recorded, not dropped.** `Measured::ok` is false, the
  reports print **FAILED**, the JSON carries `"ok": false` (schema
  `kernel-bench/2`), and no fit includes it. Its `mean_ms` is a
  time-to-failure. Without this the device's broken 1200-segment rung would
  rank as its fastest large one.
* **`sweep.var.*` reports geometry next to cost**, because a cheaper sweep that
  builds a different solid is not a cheaper sweep — and two of the obvious
  levers are exactly that. See `perf/findings/S14-sweep.md` §2.6.

`sweep.ph.*` comes from `bench_sweep.cpp`, a REPLICA of the shim's pipeline
built from the same OCCT classes, because the cost lives inside one C call and
`BRepOffsetAPI_MakePipeShell` hides the one parameter worth varying (OCCT's
`angmin` corner deadband, hard-coded at 1e-2 rad). The run prints
`replica check: shim (POLY) … vs replica …  ratio …`; **read the phase table
only if that ratio is near 1.**

Then two sweeps on a fixed `ring(24, 40) × 10` solid, which is the device's own
fillet fixture:

| op | swept axis | the device finding it targets |
| --- | --- | --- |
| `filletCandidateSearch` | — | §6.3: the candidate search costs 4.9× the blending at one edge, and it is an enumeration |
| `fillet.edges` | 1, 4, 12 edges blended | §6.3: **flat**, 25.5 ms, k = 0.00 — the work is not per-edge |
| `fillet.radius` | r = 0.5, 1, 2, 4 | §6.3: 10 ms at r=1 against 658 ms at r=4, a 65× discontinuity |

### Timing

One warm-up iteration is discarded (the device suite's convention, §1.3), then
`--reps` samples, stopping early on a per-rung wall budget so the top of the
ladder stays reachable. The reported `n` is always the count actually achieved.

Operations that are pure queries are run in an **inner loop** calibrated so
each sample clears 2 ms, and the reported figure is per call. Without it the
cheap end of the ladder is measured at the clock's noise floor and the exponent
is a fit through noise — the same reasoning §1.2 applies to the device's 1 µs
quantum.

### Memory

`ru_maxrss` gives peak RSS (kilobytes on Linux, **bytes** on Darwin — the
conversion is in `peakRssMb`). Allocation counts and bytes come from
`bench_alloc.cpp`, which interposes on two layers because one is not enough:

* the C allocator — `-Wl,--wrap=malloc` on GNU ld, a definition of `malloc` on
  Apple ld64. This catches OCCT's own manager: classes carrying
  `DEFINE_STANDARD_ALLOC` reach `malloc` inside TKernel, which is a static
  archive on our link line.
* the C++ allocator — a replacement of the global `operator new`/`delete`.
  Symbol redirection only reaches calls resolved on *our* link line, and
  libstdc++ is a shared library whose `operator new` called its own `malloc`
  long before we linked. Before this was added, a 500-element
  `vector<string>` workload reported **zero** allocations.

Neither is trusted on the strength of a platform check. `allocSelfTest()` runs
a known workload through both layers at startup and refuses the mechanism if
the counters did not move; then, after the ladder, the benchmark checks that
real kernel work moved them at all. If either check fails, every allocation
column reports `n/a` and the JSON carries `available: false`. Reporting nothing
is better than reporting zeroes that look like a finding.

The transient volume is the interesting column. §6.5's mechanism claim is that
each `edge_info` builds four whole-shape structures and throws them away; the
device measured `rssDeltaMB` = 0 across the whole ladder, which is consistent
with that but cannot distinguish it from doing no memory work at all. Bytes
requested per call can.

---

## Output

* stdout — a live table, then the calibration verdict, ending in
  `LANE C: PASS` / `LANE C: FAIL`. Read the marker, not the exit code
  (`HANDOFF.md`'s rule, and `backend/occt/tests/smoke_occt.c` follows it too).
* `--md` — the same thing as a document, with every operation's note.
* `--json` — `schema: kernel-bench/1`, for anything that wants to diff two runs.

CI publishes all three to the **`ci-logs-bench` branch**, per platform, not
only as an artifact. §13.1 is why: `sim-perf.yml` was green from run 32 onward
and not one of its numbers was ever read, because artifacts come from blob
storage the restricted network refuses. A measurement with no delivery path is
not a measurement.

## Files

| | |
| --- | --- |
| `bench_occt.cpp` | the ladder, the sweeps, the fits, the reports |
| `bench_sweep.{h,cpp}` | the sweep pipeline rebuilt so its phases and its levers can be told apart |
| `bench_stats.{h,cpp}` | mean / sd / p95, and the log-log OLS fit |
| `bench_stats_test.cpp` | that arithmetic against analytic ground truth |
| `bench_alloc.{h,cpp}` | the two-layer allocation counter and its self-test |
| `CALIBRATION.txt` | the shim hash the exponent gate keys on |
| `publish-bench.sh` | the delivery path, retrying rather than force-pushing |
