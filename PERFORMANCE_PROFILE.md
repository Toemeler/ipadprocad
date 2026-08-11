# Performance Profile — what every part of the app actually costs

**Analysis only.** Nothing here proposes a fix, and nothing in the app was
changed to produce it. This is the inventory: for each subsystem, what it
costs, how that cost grows, and whether it is smooth or a problem. The
optimisation work is deliberately a separate exercise — the rule this branch
has run under since M209 is that no optimisation happens without a scenario
number attached (PERF_PLAN.md §5, the M75 lesson).

Companion documents: `PERF_PLAN.md` (how the measurement was planned),
`PERF_ANALYSIS.md` (§8–15, the milestone-by-milestone record of how each
finding was arrived at), `HANDOFF.md` (the entry point). This file is the
*result*: the numbers, organised by what part of the app they describe.

---

## 0. How to read this document

Every number below is from a real device, not a simulator and not a
projection. Where a number is extrapolated it says so in the same sentence.

Three verdicts are used, and they mean specific things:

| Verdict | Meaning |
| --- | --- |
| **SMOOTH** | Cost is negligible at realistic sizes AND the curve is linear or better. Not a candidate for work. |
| **WATCH** | Cheap today, but the curve is superlinear — it becomes a problem at a size the app can plausibly reach. |
| **PROBLEM** | Expensive now, at sizes that occur in normal use. |

A "cost curve" is written as `n^k`, fitted by least squares across the sweep
sizes. The exponent is the number that survives a change of chip; the
milliseconds are specific to this device in this state.

---

## 1. The run these numbers come from

| | |
| --- | --- |
| Bundle | `bug20260811T104745` |
| Build | `cd961ee` |
| Device OS | iPadOS 27.0 (24A5390f), `ios_arm64` |
| Processors | 9 (9 active), 7374 MB physical |
| Kernels | OCCT shim v17 (OCCT 7.9.3), qcad C-API 0.1.0 (Qt 6.7.3) |
| Dart | 3.12.2 stable |
| Headless suite | 24 354 ms wall |
| UI suite | 1 138 ms wall |
| Session total | 42 210 ms |

The suite is self-driving: fixed inputs, no human tapping, one JSON per run.
That is what makes these numbers comparable to each other and to the next run.

---

## 2. Is this run trustworthy?

This section comes first on purpose. A suite that ran while the device was
throttling produces real numbers about a machine nobody has.

| Probe | Pre-suite | Post-suite |
| --- | --- | --- |
| Thermal state | `nominal` (ordinal 0) | `nominal` (ordinal 0) |
| **Low Power Mode** | **ON** | **ON** |
| Footprint (`phys_footprint`) | 1372 MB | 1234 MB |
| Available (`os_proc_available_memory`) | 3747 MB | 3885 MB |
| Resident (RSS) | 234 MB | 323 MB |
| Peak resident | 243 MB | 323 MB |
| CPU | 81 % | 257 % |
| Threads | 19 | 26 |

**The one caveat that governs every absolute number below: Low Power Mode was
on for the whole run.** Thermal stayed nominal, so this was not heat — the CPU
was capped by policy. On the previous comparison (build `7fb7f8b` vs
`9bfe397`, PERF_ANALYSIS §13.2) the same condition made everything uniformly
~1.9–2.05× slower across completely unrelated subsystems.

So: **absolute milliseconds here are roughly 2× pessimistic. Exponents,
ratios, and call counts are unaffected**, which is exactly why this document
leads with those wherever a choice exists.

### 2.1 Noise floor — how big a difference has to be before it means anything

`quality.variance` re-runs four representative operations and reports spread.
Without this, every "regression" is a coin flip.

| Operation | Median | IQR | Full spread |
| --- | ---: | ---: | ---: |
| `extrude` | 2834 µs | **0 %** | 3 % |
| `solve` | 281 µs | 4 % | 18 % |
| `analyze` | 1777 µs | 13 % | 17 % |
| `splineEval` | 104 µs | 7 % | **67 %** |

Kernel work is essentially noise-free (extrude IQR 0 %). Anything under ~15 %
on `analyze` is not a signal. `splineEval` swings 67 % end to end, so only
large changes there mean anything.

### 2.2 Dead measurements in this run

A scenario that measures nothing still reports a number, and a fast zero is
indistinguishable from a fast operation. Three showed up:

| Counter | Count | Status |
| --- | ---: | --- |
| `kernel.sweepTwist.fail` | 4 | Twisted sweep returns null. **Reason still unobtainable** — see §14.2. |
| `tool.build.fillet.null` | 2 | Expected. The generic point generator cannot guarantee a fittable corner; `tools.fillet2d` covers it properly. |
| `tool.build.chamfer.null` | 2 | Expected, same reason. |

### 2.3 What the frame counters do and do not say

Session frames: **304 frames, 39.0 fps, 162 jank frames**, frame total p50
35.997 ms / p95 37.57 ms / worst 154.437 ms.

That looks alarming and is **not** a usability reading. Build and raster —
the parts the app controls — are healthy:

| Phase | avg | p50 | p95 | worst |
| --- | ---: | ---: | ---: | ---: |
| `frame.build` (Dart) | 0.323 ms | 0.175 ms | 0.835 ms | 6.32 ms |
| `frame.raster` (GPU) | 2.232 ms | 2.213 ms | 3.457 ms | 8.87 ms |

Build + raster is ~2.4 ms at p50 against a 36 ms frame total. The gap is the
UI thread being blocked by the suite's own synchronous kernel calls — the
suite spends 24 seconds hammering OCCT on the platform thread on purpose. The
jank is the measurement, not the app at rest.

---

## 3. Scoreboard — the whole app, ranked

| # | Subsystem | Cost | Curve | Verdict |
| ---: | --- | ---: | ---: | --- |
| 1 | `occt_shape_edge_info` / `allEdges` | 243 ms avg, **1701 ms worst**, 32.9 % of the suite | **n^1.93–1.98** | **PROBLEM** |
| 2 | Solver LM fallback | **50.4 ms** vs 0.27 ms normal (**186×**) | cliff, not a curve | **PROBLEM** |
| 3 | Painter solves twice per dragged frame | 86.8 % of paint time in a drag | — | **PROBLEM** |
| 4 | `analyzeSketch` | 156 ms @ 256 entities | **n^2.0–2.9** | **PROBLEM** |
| 5 | Fillet radius sensitivity | 10 ms → **658 ms** (65×) on the same solid | discontinuous | **PROBLEM** |
| 6 | `ffi.occt.sweepProfile` | **159.8 ms avg**, 395.9 ms worst | n^1.06 | **PROBLEM** (absolute) |
| 7 | Booleans | 14.2 ms avg fuse, 126.5 ms worst | n^0.94–1.22 | **WATCH** (absolute) |
| 8 | RealityKit origin planes | 33.4 ms of 33.5 ms first scene push | n=1 | **WATCH** |
| 9 | `newSurfacesOf` (provenance) | 0.72 ms @ 362 faces | **n^1.85** | **WATCH** |
| 10 | `modify.intersections` | 0.33 ms @ 20 entities | **n^2.25** | **WATCH** |
| 11 | Part rebuild end-to-end | 25.1 ms @ 6 features | n^1.71 | **WATCH** |
| — | Everything else in §13 | — | linear or better | **SMOOTH** |

---

## 4. Startup

`launch.toFirstFrame` = **171.2 ms**.

All 20 instrumented startup steps together account for ~15.7 ms of that:

| Step | ms |
| --- | ---: |
| `Engine.create` (backend probe) | 4.782 |
| OCCT smoke test | 3.163 |
| symbol lookup + `qcad_init()` | 2.482 |
| `getApplicationDocumentsDirectory` (platform channel) | 2.243 |
| `qcad_document_new()` | 1.682 |
| `WidgetsFlutterBinding.ensureInitialized` | 0.377 |
| `refreshSaved` | 0.288 |
| probe `qcad_add_line()` | 0.206 |
| `Engine.create` (smoke) | 0.130 |
| `loadRemembered` | 0.124 |
| `migrateLegacyDocuments` | 0.063 |
| probe entity round-trip | 0.061 |
| `runApp` | 0.037 |
| `setPreferredOrientations` | 0.035 |
| probe `qcad_document_free()` | 0.035 |
| `DynamicLibrary.process()` | 0.020 |
| `reacquireExternals` | 0.020 |
| `AppState()` | 0.015 |
| hide system UI | 0.013 |
| `qcad_version()` | 0.006 |

**Verdict: SMOOTH.** The app's own startup work is ~9 % of time-to-first-frame;
the rest is Flutter engine boot. Nothing here is worth touching. Note this is
171 ms *in Low Power Mode* — the earlier run on build `7fb7f8b` measured
76.6 ms.

---

## 5. 2D — sketching

### 5.1 The painter, phase by phase

`2d.paint` over the session: **n=300, 100.86 ms total, 0.336 ms average.**
Eighteen named phases, plus `2d.paint.z` which catches anything after the last
mark (if `z` ever grows, a phase is missing).

| Phase | total ms | avg ms | share |
| --- | ---: | ---: | ---: |
| `constraints` | 34.78 | 0.1159 | **34.5 %** |
| `ent.dofColour` | 33.62 | 0.1121 | **33.3 %** |
| `entities` | 31.42 | 0.1047 | 31.2 % |
| `editRef` | 0.35 | 0.0012 | 0.3 % |
| `z` (unaccounted) | 0.25 | 0.0008 | 0.2 % |
| `ent.halo` | 0.10 | 0.0003 | 0.1 % |
| `gearGhost` | 0.04 | 0.0001 | 0.0 % |
| `freehand` | 0.03 | 0.0001 | 0.0 % |
| `boxSelect` | 0.03 | 0.0001 | 0.0 % |
| `snap` | 0.03 | 0.0001 | 0.0 % |
| `bg` | 0.03 | 0.0001 | 0.0 % |
| `cursorHints` | 0.02 | 0.0001 | 0.0 % |
| `modifyGhost` | 0.02 | 0.0001 | 0.0 % |
| `pattern` | 0.02 | 0.0001 | 0.0 % |
| `notice` | 0.02 | 0.0001 | 0.0 % |
| `toolPreview` | 0.02 | 0.0001 | 0.0 % |
| `ent.projectEdges` | 0.02 | 0.0001 | 0.0 % |
| `ent.images` | 0.01 | 0.0000 | 0.0 % |
| `slice` | 0.00 | 0.0000 | 0.0 % |

`2d.paint.z` at 0.2 % confirms the phase decomposition is complete — the
probe reports its own gaps and there is no gap.

**Two phases carry 67.8 % of painting, and neither of them is drawing.**
Both `constraints` and `ent.dofColour` contain a call to
`app.displayGeometry`, which runs the constraint solver *inside*
`CustomPainter.paint`.

### 5.2 Static paint vs painting during a drag — the same code, two worlds

`ui.paint.sweep.64` — static paint, 64 entities, 30 frames:

| Phase | avg ms | share |
| --- | ---: | ---: |
| `entities` | 0.2124 | **97.3 %** |
| `constraints` | 0.0022 | 1.0 % |
| `ent.dofColour` | 0.0010 | 0.5 % |
| whole `2d.paint` | 0.2183 | |

`ui.drag60` — one second of dragging at 60 fps, same sketch:

| Phase | avg ms | share |
| --- | ---: | ---: |
| `constraints` | 0.2772 | **43.6 %** |
| `ent.dofColour` | 0.2748 | **43.2 %** |
| `entities` | 0.0802 | 12.6 % |
| whole `2d.paint` | 0.6359 | |

**During a drag, 86.8 % of paint time is solving and 12.6 % is drawing.** The
static case is the exact inverse: 97.3 % drawing.

**And the solve happens twice per painted frame.** The counters are
unambiguous: 60 painted frames, `2d.displayGeometry` n=**120**,
`2d.displayGeometry.solves` = **120**, `solve.total` n=**120**. The two call
sites are `viewport.dart:2088` (inside the `ent.dofColour` segment) and
`viewport.dart:2683` (inside the `constraints` segment). Both compute the same
answer.

Session-wide the same pattern: `2d.displayGeometry` n=240, avg 0.2821 ms.

**Verdict: PROBLEM** (item 3 on the scoreboard). Note the *phase name is
misleading* — the earlier reading "dofColour is 85 % of painting" was wrong;
it is the solve sitting inside that segment. The actual DOF colouring
(`carrierFixed` per entity) is inside `entities` and costs ~0.11 ms at 128
entities, roughly linear.

### 5.3 Interaction — snap and pick

| Path | n | avg | p50 | p95 | worst |
| --- | ---: | ---: | ---: | ---: | ---: |
| `2d.snap` | 240 | **0.0079 ms** | 0.009 | 0.010 | 0.012 |
| `2d.pickEntity` | 480 | **0.0899 ms** | 0.127 | 0.140 | 0.280 |

From `ui.snapHover` (120 hovers): snap 0.0079 ms, pick 0.0497 ms.

**Snapping is 6–11× cheaper than the entity pick next to it.** Snap was the
phase that appeared in *no* report until M212 because the measurement point
did not exist; now measured, it is the cheapest thing on the pointer path.

**Verdict: SMOOTH**, both.

### 5.4 The constraint solver

Session totals: `solve.total` n=**726**, avg 2.5744 ms, **p50 0.271 ms**,
p95 0.279 ms, **worst 66.948 ms**.

| Layer | n | avg | worst |
| --- | ---: | ---: | ---: |
| `solve.total` | 726 | 2.5744 ms | 66.948 ms |
| `solve.slvs` (native attempt + verification) | 726 | 0.6120 ms | 18.417 ms |
| `ffi.slvs.solve` (libslvs itself) | 722 | **0.4922 ms** | 18.249 ms |
| `solve.lm` (Dart fallback) | **28** | **50.4125 ms** | 64.695 ms |

Path counters for the session:

| Counter | Value |
| --- | ---: |
| `solve.path.slvs` | 698 |
| `solve.path.lm` | **28** |
| `solve.slvs.rejected.residual` | 24 |

**3.9 % of solves took the LM path, and each cost 186× a normal one.** That
is the entire explanation for a p50 of 0.271 ms sitting next to a worst of
66.9 ms — the mean of 2.57 ms is an artefact of mixing two populations.

The mechanism, isolated by `solve.overConstrained` (10 solves):

| Layer | avg ms | share |
| --- | ---: | ---: |
| `solve.total` | 66.352 | 100 % |
| `solve.lm` (Dart Levenberg-Marquardt) | 64.176 | **96.7 %** |
| `solve.slvs` | 2.156 | 3.2 % |
| `ffi.slvs.solve` (libslvs) | 0.228 | **0.34 %** |

libslvs does essentially the same work in both cases (0.228 ms here vs
0.220 ms in the normal drag). The 290× difference is entirely Dart-side:
`solver.dart:2172` verifies the native result against its own residuals,
discards it above tolerance (`solve.slvs.rejected.residual` = 10 for these 10
solves), and then runs the Dart LM — twice during a drag (`lm-frozen`, then
`lm-relaxed`), 80 iterations of finite-difference Jacobians over a
168-parameter system each time.

A normal drag, for contrast (`ui.drag60`, 120 solves): `solve.total` 0.2711 ms,
`solve.slvs` 0.2585 ms, `ffi.slvs.solve` 0.2202 ms — **81 % of the time is in
libslvs**, exactly where it should be. `solve.path.slvs` = 120, `solve.path.lm`
= 0.

**Verdict: normal solving is SMOOTH (0.27 ms). The fallback is a PROBLEM.**
The number to check first on any "dragging is janky" report is
`solve.path.lm`: non-zero means the sketch fell off the fast path.

Solve cost against sketch size (`ramp.solve`, settled sketch — the per-solve
floor):

| Entities | ms | local exponent |
| ---: | ---: | ---: |
| 8 | 0.076 | — |
| 16 | 0.075 | n^-0.02 |
| 24 | 0.118 | n^1.13 |
| 32 | 0.168 | n^1.22 |
| 48 | 0.304 | n^1.46 |
| 64 | 0.481 | n^1.59 |
| 96 | 0.936 | n^1.64 |
| 128 | 1.531 | n^1.71 |
| 192 | 3.179 | n^1.80 |
| 256 | **5.374** | n^1.82 |

The local exponent *climbs* steadily from ~1.1 to ~1.8. Even so, 5.4 ms at 256
entities is affordable. Size is not the solver's problem; the fallback is.

Constraint **density** at fixed entity count (`ramp.density`, redundant
repetitions — how a sketch becomes over-constrained in practice):

| Density × | ms | local exponent |
| ---: | ---: | ---: |
| 1 | 0.452 | — |
| 2 | 1.337 | n^1.57 |
| 3 | 2.704 | n^1.74 |
| 4 | 4.741 | n^1.95 |
| 6 | 10.277 | n^1.91 |
| 8 | **18.289** | **n^2.00** |

Density is quadratic and steady at it. This is the axis nobody had measured
before M219, and it is the one a user grows by over-constraining a sketch.

### 5.5 DOF analysis (`analyzeSketch`)

Session: n=**75**, avg 8.939 ms, p50 0.776 ms, p95 27.546 ms, **worst
158.852 ms**.

It builds a finite-difference Jacobian (a full residual evaluation *per
parameter*) then reduces it row-wise, and it runs on **every rebuild, every
solve and every tab switch** (`app_state.dart:2163`, `:2183`, `:6486`).

`ramp.analyze` — fine steps, with the local exponent between neighbours:

| Entities | ms | local exponent |
| ---: | ---: | ---: |
| 8 | 0.066 | — |
| 16 | 0.206 | n^1.65 |
| 24 | 0.433 | n^1.84 |
| 32 | 0.782 | n^2.05 |
| 48 | 1.791 | n^2.04 |
| 64 | 5.800 | **n^4.08** |
| 96 | 13.503 | n^2.08 |
| 128 | 22.562 | n^1.78 |
| 192 | 71.969 | n^2.86 |
| 256 | **156.069** | n^2.69 |

Two things the coarse three-point sweep (`analysis.sweep`, n^2.24) could never
have shown, and which are the reason ramps exist:

* **A knee at 64 entities** — a local exponent of 4.08 across one step, then
  back to ~2.0. Something changes behaviour there; a smooth power-law fit
  averages it away entirely.
* **The exponent rises again past 128** (2.86, 2.69) as the cubic row
  reduction takes over.

**Verdict: PROBLEM.** At 256 entities a single analysis is 156 ms, and it runs
on every solve.

### 5.6 Drag, end to end

`ramp.drag` — the full painter-path drag, per frame:

| Entities | ms | local exponent |
| ---: | ---: | ---: |
| 8 | 2.302 | — |
| 16 | 0.570 | n^-2.01 |
| 24 | 0.968 | n^1.31 |
| 32 | 1.420 | n^1.33 |
| 48 | 5.345 | **n^3.27** |
| 64 | 4.591 | n^-0.53 |
| 96 | 8.875 | n^1.63 |
| 128 | **14.893** | n^1.80 |

The negative exponents at 16 and 64 are warm-up and noise (the first rung
carries fixture cost). The signal is the trend: **14.9 ms per dragged frame at
128 entities**, which at two solves per frame is already outside a 120 Hz
budget and close to the edge of 60 Hz.

### 5.7 Drawing tools — all 26

Every tool in `toolMeta`, driven generically so a new tool is measured the day
it is added — all 26, ranked, 100 builds each:

| # | Tool | avg ms | | # | Tool | avg ms |
| ---: | --- | ---: | --- | ---: | --- | ---: |
| 1 | `eqCurve` | 0.04248 | | 14 | `rectTwoPoint` | 0.00048 |
| 2 | `bridge` | 0.01013 | | 15 | `polygon` | 0.00044 |
| 3 | `circleTangent` | 0.01006 | | 16 | `ellipse` | 0.00008 |
| 4 | `arcTangent` | 0.00356 | | 17 | `arcThreePoint` | 0.00007 |
| 5 | `fillet` | 0.00356 | | 18 | `lineMid` | 0.00006 |
| 6 | `chamfer` | 0.00237 | | 19 | `point` | 0.00004 |
| 7 | `splineInterp` | 0.00119 | | 20 | `circleCenter` | 0.00003 |
| 8 | `slotCC` | 0.00118 | | 21 | `rect2PC` | 0.00003 |
| 9 | `splineCV` | 0.00112 | | 22 | `slotOverall` | 0.00003 |
| 10 | `splineFree` | 0.00108 | | 23 | `slotCP` | 0.00003 |
| 11 | `slot3A` | 0.00101 | | 24 | `rect3PC` | 0.00002 |
| 12 | `slotCPA` | 0.00093 | | 25 | `arcCenter` | 0.00001 |
| 13 | `line` | 0.00054 | | 26 | `rect3P` | 0.00000 |

**Verdict: SMOOTH.** The slowest tool in the app builds geometry in 42
microseconds. Tool construction is not a cost centre and never was.

Related 2D geometry work:

| Operation | n | avg | curve |
| --- | ---: | ---: | ---: |
| `spline.curveFor` (evaluation, 64 CVs) | 600 | 0.594 ms | n^1.30 |
| `tool.spline.cv` / `.interp` (construction) | 20 | 0.002 ms | flat |
| `tools.filletMaxRadius` (40-step binary search) | 20 | 0.0495 ms | — |
| `ellipse.curve` | 200 | 0.0020 ms | — |
| `freehand.fit` | 60 | 0.0872 ms | n^1.59 |
| `freehand.smooth` | 60 | 0.0785 ms | — |
| `freehand.dedupe` | 60 | 0.0044 ms | — |

Spline **evaluation** is 300× spline **construction** — the split that makes
that visible was deliberate. `filletMaxRadius` is 46× a single fillet
computation, as predicted from the 40-iteration search, but 0.05 ms absolute.

### 5.8 Modify operations

| Operation | n | avg ms | curve |
| --- | ---: | ---: | ---: |
| `modify.intersectionsWithOthers` | 136 | 0.0063 | **n^2.25** |
| `modify.trimEntity` | 68 | 0.0084 | n^1.83 |
| `modify.trim` | 68 | 0.0081 | |
| `modify.transformGeo` | 80 | 0.0058 | n^1.25 |
| `modify.extendEntity` | 40 | 0.0049 | |
| `modify.extend` | 40 | 0.0043 | |
| `modify.stretchGeo` | 40 | 0.0042 | |
| `modify.offsetChainAt` | 100 | 0.0035 | |
| `modify.offsetEntity` | 800 | 0.0004 | |

`modify.intersections` at 20 entities: 0.33 ms total, n^2.25.

**Verdict: WATCH.** Everything is microseconds today, but intersections is the
steepest curve in 2D and it runs on every modify click. At 200 entities the
exponent projects ~33 ms; at 600, ~350 ms.

### 5.9 Constraints

Cost of *adding* one constraint of each of the 12 types:

| Type | avg ms |
| --- | ---: |
| **`dimension`** | **44.1995** |
| **`tangent`** | **12.1735** |
| **`fix`** | **11.1805** |
| `perpendicular` | 4.4260 |
| `parallel` | 0.6500 |
| `coincident` | 0.6290 |
| `collinear` | 0.6235 |
| `symmetric` | 0.5915 |
| `midpoint` | 0.5850 |
| `horizontal` | 0.5615 |
| `concentric` | 0.5590 |
| `vertical` | 0.5215 |
| `equal` | 0.5195 |
| `smooth` | 0.4395 |

**Entering one dimension costs 44.2 ms — 85× a coincident.** The expensive
four are exactly the ones whose result libslvs does not deliver cleanly, so
verification fails and the Dart LM runs. This is §5.4's cliff seen from the
editing side rather than the dragging side.

Supporting operations, all smooth:

| Operation | n | avg ms |
| --- | ---: | ---: |
| `constraints.encode` | 40 | 0.2675 |
| `constraints.decode` | 40 | 0.1728 |
| `constraints.inferConstraints` | 80 | 0.0039 |
| `constraints.inferPointBindings` | 80 | 0.0025 |

### 5.10 Gears

| | |
| --- | ---: |
| `gear.curve` (cold generation) | 0.6067 ms avg (n=120) |
| `gear.curve.cached` | **0.0010 ms** avg (n=1200) |
| Cache speed-up | **432×** (475 µs → 1 µs) |
| Cost per point | ~0.21 µs, exactly linear |

At 10 / 20 / 40 teeth: 5.91 / 11.14 / 19.22 ms per scenario batch, n^0.85.

**Verdict: SMOOTH, and the memo works.** Four 20-tooth gears cost ~1 ms once,
on load. Gears were the original suspect in the crashing part and they are
comprehensively cleared.

---

## 6. 3D — the kernel

### 6.1 Creation operations

| Operation | n | avg ms | worst | curve |
| --- | ---: | ---: | ---: | ---: |
| **`sweepProfile`** | 16 | **159.77** | **395.95** | n^1.06 |
| `coilProfile` | 6 | 28.99 | 47.50 | n^0.44 |
| `loftSections` | 10 | 13.79 | 35.64 | n^0.39 |
| `extrudeProfileArcs` | 410 | 3.92 | 66.21 | n^1.00 |
| `revolveProfile` | 12 | 2.95 | 5.54 | n^0.99 |
| `extrudeProfile` | 12 | 0.93 | 1.82 | — |
| `makeCylinder` | 18 | 0.0097 | 0.021 | — |
| `makeBox` | 9 | 0.164 | 1.273 | — |

Swept against profile point count, all comparable on the same axis:

| Profile pts | extrude.arcs | revolve | mesh.complexity |
| ---: | ---: | ---: | ---: |
| 12 | 0.72 ms | 0.55 ms | 1.39 ms |
| 48 | 2.83 ms | 2.16 ms | 5.13 ms |
| 120 | 7.15 ms | 5.48 ms | 12.86 ms |

`kernel.sweep.path` (96-point path): **204.86 ms per sweep.**

**Verdict: sweep is a PROBLEM in absolute terms** — 160 ms average, 396 ms
worst, and it is a normal modelling operation. Everything else in this table
is smooth and linear. Extrude, the most-used operation in the app (410 calls
this run), is 3.9 ms.

### 6.2 Booleans

| Operation | n | avg ms | p95 | worst |
| --- | ---: | ---: | ---: | ---: |
| `fuse` | 90 | 14.22 | 76.03 | 126.49 |
| `cut` | 16 | 17.32 | 90.21 | 90.89 |
| `common` | 16 | 16.57 | 86.77 | 87.07 |
| `unify` | 44 | 0.0808 | 0.095 | 0.141 |

`ramp.boolean` against operand complexity:

| Profile pts | ms | local exponent |
| ---: | ---: | ---: |
| 12 | 10.013 | — |
| 24 | 19.215 | n^0.94 |
| 36 | 29.181 | n^1.03 |
| 48 | 39.868 | n^1.08 |
| 72 | 62.880 | n^1.12 |
| 96 | 87.625 | n^1.15 |
| 144 | **143.908** | n^1.22 |

An 8-deep fusion chain (`kernel.boolean.chain`): 8 fuses, 8.201 ms each,
65.9 ms total.

**Verdict: WATCH.** The curve is near-linear and drifting up only slowly, which
is as good as booleans get. But 144 ms for one boolean on a 144-point profile
is a visible stall, and a rebuild does one per feature. `unify` is free.

### 6.3 Fillet and chamfer

This is where the topology defect surfaces as user-visible behaviour.

| Scenario | `allEdges` | `filletEdges` | ratio |
| --- | ---: | ---: | ---: |
| 1 edge | **49.31 ms** | 10.10 ms | candidate search = **4.9×** the rounding |
| 4 edges | 49.49 ms | 20.76 ms | 2.4× |
| 12 edges | 49.28 ms | 46.66 ms | 1.06× |

**`allEdges` is flat at ~49 ms** — it is the same 72-edge solid every time —
while the actual rounding scales with edge count. The fitted curve for
`kernel.fillet.edges` is **n^-0.00**: the wall time does not move at all with
the number of edges filleted, because finding the candidates dominates.

`chamferEdges`: n=6, avg 25.24 ms, worst 46.22 ms — same shape (`n^-0.00`).

**Radius sensitivity is the sharper finding:**

| | |
| --- | ---: |
| `kernel.fillet.radius`, 3 calls | 699.59 ms total |
| average | 233.20 ms |
| **worst (r = 4.0)** | **657.71 ms** |
| r = 1.0 on the same solid | ~10 ms |
| **ratio** | **~65×** |

A radius large enough to reach neighbouring geometry is not a slower version
of the same operation — it is a different operation.

**Verdict: PROBLEM**, on both axes.

### 6.4 Tessellation

| Operation | n | avg ms | p95 | worst |
| --- | ---: | ---: | ---: | ---: |
| `meshCreate` (OCCT tessellating) | 302 | 4.4797 | 6.565 | 41.605 |
| `meshCopyOut` (Dart copying the result) | 302 | **0.0046** | 0.008 | 0.197 |

`ramp.mesh`:

| Profile pts | ms | local exponent |
| ---: | ---: | ---: |
| 12 | 2.203 | — |
| 48 | 8.018 | n^0.98 |
| 96 | 15.869 | n^0.93 |
| 192 | 33.090 | n^1.05 |
| 288 | **49.982** | n^1.02 |

**`meshCreate` is 974× `meshCopyOut`.** Separating those two was one of the
design decisions of the measurement net, and it settles a plausible
suspicion: the FFI boundary is *not* where tessellation cost lives. Nine typed
copies of hundreds of thousands of doubles cost 4.6 microseconds. The cost is
OCCT tessellating, and it is dead linear.

**Verdict: SMOOTH** (linear, and the boundary is exonerated).

### 6.5 Topology queries — the defect

This is finding #1, and it is now proven three independent ways.

**Session cost:**

| | |
| --- | ---: |
| `ffi.occt.allEdges` | n=**50** |
| total | **12 163.32 ms** |
| average | **243.27 ms** |
| p50 | 49.954 ms |
| p95 | **1171.47 ms** |
| worst | **1701.81 ms** |
| share of the whole suite | **32.9 %** |
| `ffi.occt.edgeInfo.calls` | **6552** |

**Proof 1 — the growth curve.** `ramp.allEdges`, with per-edge cost:

| Profile pts | Edges | ms | local exponent | per edge |
| ---: | ---: | ---: | ---: | ---: |
| 12 | ~36 | 14.12 | — | 392 µs |
| 24 | ~72 | 50.80 | n^1.85 | 706 µs |
| 36 | ~108 | 111.16 | n^1.93 | 1029 µs |
| 48 | ~144 | 195.94 | n^1.97 | 1361 µs |
| 72 | ~216 | 433.75 | n^1.96 | 2008 µs |
| 96 | ~288 | 765.89 | n^1.98 | 2659 µs |
| 144 | ~432 | **1708.56** | n^1.98 | **3955 µs** |

The local exponent converges on **1.98** and stays there. This is a clean
quadratic, not a knee. Per-edge cost grows 10× across the ramp — the tell that
each call is doing work proportional to the whole shape.

**Proof 2 — one call against a growing shape.** `kernel.query.edgeInfoScale`
asks for **the same edge** (edge 1) twenty times, on solids of increasing
size. Only the surrounding shape changes:

| Profile pts | Edges | Faces | per call | vs smallest |
| ---: | ---: | ---: | ---: | ---: |
| 24 | 72 | 26 | 0.6252 ms | 1.00× |
| 60 | 180 | 62 | 1.5080 ms | 2.41× |
| 120 | 360 | 122 | 3.0383 ms | 4.86× |
| 240 | 720 | 242 | **6.0729 ms** | **9.73×** |

**Edges ×10 → the cost of one unchanged query ×9.73.** A single `edgeInfo` is
O(shape). `allEdges` makes one such call per edge. n × O(n) = O(n²) is then
arithmetic, not inference.

> **Read the fitted verdict carefully here.** `perf_report.py` labels this
> family "linear" (n^0.99), which reads as reassuring. For this family linear
> is the *damning* result, because the swept axis is not the amount of work
> requested — it is the size of the shape that one fixed unit of work has to
> look at. The report tool has no way to know the difference; a reader does.

**Proof 3 — the control queries.** On the *same* 360-edge solid:

| Query | avg ms | vs `edgeInfo` |
| --- | ---: | ---: |
| `kernel.edgeInfo1` (one edge) | 2.9911 | 1× |
| `kernel.counts()` | 0.2052 | **14.6× cheaper** |
| `kernel.bbox()` | 0.1651 | **18.1× cheaper** |

Touching the shape is cheap. Crossing the FFI boundary is cheap. Asking about
one edge is not. And 360 × 2.9911 ms = 1076.8 ms against a measured
`allEdges` of ~1171 ms — **92 %** of the total explained by per-call cost, the
remaining 8 % being the boundary crossings and the Dart-side list build.

**The source, for completeness** (`backend/occt/shim/occt_capi.cpp`): each call
performs *four* whole-shape operations — `TopExp::MapShapes` (:1738),
`TopExp::MapShapesAndAncestors` (:1792), `BRepBndLib::Add` (:1832) and
constructing a `BRepClass3d_SolidClassifier` (:1836) — then discards all four.
The last two sit in the convexity branch, which runs for any edge with exactly
two adjacent faces: on a closed solid, the majority.

**Verdict: PROBLEM — the single largest cost in the application.**
Extrapolated to the ~3400-edge part that crashed the app, ~48 s.

### 6.6 Placement — transform and mirror

| Operation | n | avg ms |
| --- | ---: | ---: |
| `ffi.occt.transform` | 140 | 0.4302 |
| `ffi.occt.mirror` | 40 | 2.6702 |

Head to head, on the *same* solid within one scenario:

| Solid | `mirror` | `transform` | ratio |
| ---: | ---: | ---: | ---: |
| 72 edges | 0.886 ms | 0.291 ms | **3.04×** |
| 360 edges | 4.440 ms | 1.481 ms | **3.00×** |

A consistent 3× at both sizes, both linear in shape size. The extra 2× is the
reflection plus the orientation correction the shim applies so the result can
enter a boolean directly. A mirror pattern pays this per occurrence.

**Verdict: SMOOTH**, with the ratio recorded so a mirror pattern's cost is
predictable.

### 6.7 Ray casting

| Operation | n | avg ms | p95 | worst |
| --- | ---: | ---: | ---: | ---: |
| `kernel.rayHit` | 120 | 0.2431 | 0.242 | 1.237 |
| `ffi.occt.rayHits` | 120 | 0.2427 | 0.241 | 1.235 |

**Verdict: SMOOTH.** Essentially all of `rayHit` is the native call; the Dart
wrapper adds 0.4 µs.

### 6.8 Feature rebuild, end to end

| | n | avg | p95 | worst |
| --- | ---: | ---: | ---: | ---: |
| `part.rebuildAll` | 18 | 13.53 ms | 25.43 ms | 25.90 ms |
| `kernel.feature` | 60 | 1.1704 ms | 1.237 ms | 1.606 ms |
| `kernel.feature.extrude` | 60 | 1.1699 ms | 1.236 ms | 1.604 ms |

`app.rebuildPart` swept on feature count: 1 → 3.78 ms, 3 → 40.81 ms,
6 → 75.16 ms, fitted **n^1.71**.

Inside the 6-feature rebuild (3 forced passes, 18 feature computations):

| Component | n | total ms | avg |
| --- | ---: | ---: | ---: |
| `part.rebuildAll` | 3 | 75.16 | 25.05 |
| `ffi.occt.fuse` | 15 | 45.90 | 3.060 |
| `kernel.feature` | 18 | 20.56 | 1.142 |
| `ffi.occt.meshCreate` | 33 | 12.48 | 0.378 |
| `ffi.occt.extrudeProfileArcs` | 18 | 6.75 | 0.375 |

`part.rebuild.passes` = 3, `kernel.feature.ok` = 18, `meshCopyOut.tris` = 4620.

**The boolean fold is 61 % of a rebuild.** `ramp.build` (creation only, no
fold) is dead linear at n^1.00–1.04 across 12→288 profile points, which
isolates the superlinearity to the accumulating boolean, not to feature
construction.

`ramp.solids` — holding N solids simultaneously — is also linear
(n^0.94–1.05, 1 → 8.07 ms, 16 → 126.19 ms).

**Verdict: WATCH.** 25 ms for a 6-feature part is fine; n^1.71 to 40 features
is not.

---

## 7. 3D — the display path

### 7.1 Scene payload (Dart side)

| Operation | n | avg ms | worst |
| --- | ---: | ---: | ---: |
| `app.buildScenePayload` | 60 | 0.0157 | 0.303 |
| `app.sceneSignature` | 360 | 0.0007 | 0.006 |
| `app.buildOverlaysPayload` | 10 | 0.0010 | — |
| `app.sceneRevs` | 60 | 0.0000 | — |
| `3d.push` | 2 | 0.0915 | 0.183 |

**Verdict: SMOOTH.** Everything Dart does to prepare a scene for RealityKit is
free. The signature check that decides whether to push at all costs 0.7 µs.

### 7.2 Past the platform-view boundary (native RealityKit)

Measured natively in `RvPerf.swift` and *pulled* by Dart, so no channel
round-trip contaminates the measurement.

| Phase | ms | share |
| --- | ---: | ---: |
| `rv.native.setScene` | 33.51 | 100 % |
| ├─ **`rv.native.planes`** | **33.36** | **99.6 %** |
| ├─ `rv.native.sketches` | 0.08 | 0.2 % |
| ├─ `rv.native.solids` | **0.04** | 0.1 % |
| ├─ `rv.native.setCamera` | 0.08 | — |
| ├─ `rv.native.placeCamera` | 0.02 | — |
| ├─ `rv.native.setOverlays` | 0.02 | — |
| ├─ `rv.native.accents` | 0.00 | — |
| └─ `rv.native.highlight` | 0.00 | — |

Dart-side, for the same single push: `rv.setScene` 35.73 ms, `rv.setOverlays`
35.72 ms, `rv.setCamera` 35.09 ms (n=1 each).

**The mesh upload is effectively free (0.04 ms) and the three origin planes
cost 33.36 ms.** The intuitive assumption — that pushing a scene is dominated
by geometry — is simply false, and it was not falsifiable at all before the
native drain existed. This is first-call cost (RealityKit entity and material
creation, n=1), but it is a 33 ms hitch when a part opens.

Down from 55.24 ms on build `9bfe397`, though both runs were in Low Power Mode
so the comparison is soft.

**Verdict: WATCH** — small, one-off, but it is the whole cost of showing a part.

### 7.3 Projection of model edges into a sketch

| Operation | n | avg ms | p95 | worst |
| --- | ---: | ---: | ---: | ---: |
| `project.partEdges` | 60 | 0.1572 | 0.507 | 1.531 |
| `app.partEdges` | 60 | 0.1575 | 0.507 | 1.531 |

At 3 features × 48 points: 0.047 ms.

**Verdict: SMOOTH.** Projection was a named stress case in M76/M77 and it is
comprehensively cleared — provided `allEdges` is not on its path.

### 7.4 3D picking

| Operation | n | avg ms | worst |
| --- | ---: | ---: | ---: |
| `app.pickEdge3d` | 180 | 0.0232 | 0.152 |

**Verdict: SMOOTH.**

### 7.5 Mesh diagnostics

| Operation | n | avg ms |
| --- | ---: | ---: |
| `app.meshSelfReport` | 6 | 0.1253 |
| `app.meshAnomalies` | 3 | 0.0000 |

**Verdict: SMOOTH.**

---

## 8. Face provenance (M213) and part patterns (M212)

Both arrived from `main` with no measurement at all and were instrumented in
M220.

### 8.1 Provenance — the rebuild path

`faceSurfaces` and `newSurfacesOf` run inside `recomputeAllFeatures`, once per
feature, on **every rebuild** (`part_model.dart:6988-6990`); for a
body-modifying feature `faceSurfaces` runs twice.

| Profile pts | Triangles | Faces | `faceSurfaces` | `newSurfacesOf` |
| ---: | ---: | ---: | ---: | ---: |
| 24 | 92 | 26 | 0.009 ms | 0.005 ms |
| 120 | 476 | 122 | 0.046 ms | 0.093 ms |
| 360 | 1436 | 362 | 0.139 ms | **0.721 ms** |
| **curve** | | | **n^1.01** | **n^1.85** |

Session: `faceSurfaces` n=60 avg 0.0673 ms; `newSurfaces` n=60 avg 0.2721 ms,
p95 0.722 ms.

`faceSurfaces` is linear, as expected — one pass over triangles.
`newSurfacesOf` is **quadratic**, as predicted from the source
(`base.any(...)` inside a loop over `result`, `part_model.dart:3701`) — face
count ×13.9 gives time ×144.

**Verdict: `faceSurfaces` SMOOTH; `newSurfacesOf` WATCH.** 0.72 ms per
modifying feature is nothing today. At 10× the face count the quadratic makes
it ~70 ms per feature, per rebuild.

### 8.2 Provenance — the pick path

`attributeFaces` answers "which feature made this face" and is cached per mesh
identity (`app_state.dart:4859`).

| Features | avg ms | faces attributed |
| ---: | ---: | ---: |
| 2 | 0.172 | 62 |
| 6 | 0.285 | 62 |
| 12 | 0.577 | 62 |
| **curve** | **n^0.65** | |

Session: n=30, avg 0.3347 ms, p95 0.591 ms.

Structurally this is a triple loop (faces × features × surfaces-per-feature)
and it was predicted to be a product. **The measurement says otherwise** — the
`break` after the first surface match keeps the inner loop short, and the cost
grows *sublinearly* with feature count.

**Verdict: SMOOTH.** A prediction that did not survive contact with the
device, recorded as such.

One structural note that the timings do not capture: `featureOfFace` calls
`faceSurfaces(solid.mesh)` a second time purely to put a count into a log line
(`app_state.dart:4864`), immediately after `attributeFaces` computed the same
decomposition internally. It sits behind the cache, so it runs once per mesh
identity rather than per frame.

### 8.3 Part patterns — all five kinds

| Kind | span avg | 20 iterations | occurrences produced |
| --- | ---: | ---: | ---: |
| rectangular | 0.0015 ms | 0.017 ms | 15 (of count 16) |
| circular | 0.0122 ms | 0.083 ms | 15 (of count 16) |
| sketch-driven | 0.0014 ms | 0.016 ms | 16 (of 16 points) |
| along-a-curve | 0.0213 ms | 0.422 ms | 15 |
| mirror | 0.0000 ms | 0.000 ms | 1 (constant by construction) |

Curves: rectangular n^0.93, circular n^1.35, sketch-driven n^1.05 — all
linear. `app.patternPreview` (the 2D sketch pattern, redrawn every frame while
its dialog is open): n=200, avg 0.0195 ms.

**Verdict: SMOOTH, all of it.** The Dart arithmetic of a pattern is free. The
along-a-curve variant costs ~14× the straight one (0.0213 vs 0.0015 ms) and is
still 21 microseconds. **The cost of a pattern is therefore entirely in the
kernel** — the mirror scenario exists precisely to establish that, and
`kernel.mirror` (§6.6) measures the part that actually costs something.

*Contract worth knowing:* a pattern of count *n* yields *n−1* placements. The
identity placement is dropped (`part_model.dart:3370`) because it **is** the
original feature.

---

## 9. Documents, history, codecs

| Operation | n | avg ms | worst |
| --- | ---: | ---: | ---: |
| `io.savePart` (incl. disk) | 1 | 21.136 | — |
| `app.sketch.encodeCons` | 40 | 0.2692 | 0.413 |
| `app.sketch.decodeCons` | 40 | 0.1726 | 0.342 |
| `app.part.toJson` | 40 | 0.0083 | 0.015 |
| `app.checkpoint` (undo snapshot) | 120 | 0.1437 | 0.613 |
| `ffi.qcad.allGeometry` | 32 | 0.0661 | 0.180 |
| `ffi.qcad.addLine` | 762 | 0.0034 | 0.179 |
| `ffi.qcad.addCircle` | 761 | 0.0032 | 0.049 |
| `app.engineFill` | 20 | 0.5083 | 0.823 |

`app.history` swept: 8 → 0.98 ms, 24 → 2.09 ms, 64 → 5.44 ms, **n^0.82**.

**Verdict: SMOOTH.** Serialisation, undo journaling and the qcad round-trip are
all cheap and linear or better. Disk I/O is deliberately excluded from the
sweeps — its wall time is governed by iOS storage pressure and is not fixable
in this code — but the one real `savePart` observed took 21.1 ms in total.

`ffi.qcad.allGeometry` is worth a note: it is structurally `1 + 3n` boundary
crossings plus a per-entity allocation pair, which was flagged as a concern
before measurement. At 0.066 ms for a full document read, it is cleared.

---

## 10. UI shell

| Signal | Value |
| --- | ---: |
| `menu.ribbon.builds` (whole session) | **1** |
| `toolbar.setItems.calls` / `rows.hit` / `rows.miss` | 2 / 1 / 2 |
| `tabbar.setTabs.calls` / `rows.miss` | 2 / 2 |
| `browser.setRows.calls` / `rows.hit` / `rows.miss` | 1 / 1 / 1 |
| `rv.setScene.calls` / `setOverlays` / `setCamera` | 1 / 1 / 1 |

**Verdict: SMOOTH.** The ribbon was built **once** in the entire session. The
interesting number for the ribbon was never its duration (microseconds) but
its frequency — a ribbon rebuilding during a drag would have been a real find.
It does not. Platform-view channels are similarly quiet: single-digit call
counts with the signature caches doing their job.

---

## 11. Memory

| Measure | Value |
| --- | ---: |
| RSS | 313 MB (peak 313 MB, max 323 MB) |
| `phys_footprint` | 1372 → 1234 MB |
| Available before jetsam | 3747 → 3885 MB |
| Physical memory | 7374 MB |
| **Per solid** | **2 KB** |
| **Per triangle** | **14 bytes** |
| Per entity | (measured, sub-KB) |

Two things to take from this:

* **The footprint/RSS ratio is ~4×** (1234 MB vs 313 MB). Plausible for
  RealityKit/Metal, where IOSurface and GPU allocations count toward the
  footprint but not RSS — but large enough that it should be corroborated
  before any decision rests on it. Flagged in PERF_ANALYSIS §13.8 and still
  open. **iOS kills on footprint, not RSS**, so this is the number that
  matters.
* **14 bytes per triangle** makes file-size questions arithmetic rather than
  guesswork. A 100 000-triangle model is ~1.4 MB of mesh.

Headroom in this run was comfortable (3.9 GB). The session that died during a
fillet reported 839 MB RSS — and its footprint, the number that actually
triggered the kill, was never captured, which is why the native probe exists.

---

## 12. Frame budget — how big a sketch still fits

`quality.frameBudget` computes the largest sketch that fits in a frame,
accounting for the **two** solves per painted frame that the painter really
does:

| Target | Max entities |
| --- | ---: |
| 120 Hz (8.3 ms) | **192** |
| 60 Hz (16.7 ms) | **256** |

In Low Power Mode. These are the numbers that turn "it feels slow" into "you
are above the budget at this size".

---

## 13. Every cost curve in one table

Fitted exponents across all sweep families in this run, ordered by steepness.

| Family | Sizes → ms | n^k | Verdict |
| --- | --- | ---: | --- |
| `modify.intersections` | 4:0.01 10:0.08 20:0.33 | **2.25** | superlinear |
| `analysis.sweep` | 8:0.20 24:1.81 64:21.82 | **2.24** | superlinear |
| `ramp.density` | 1:0.45 → 8:18.29 | **2.00** | superlinear |
| `ramp.allEdges` | 12:14.12 → 144:1708.56 | **1.98** | superlinear |
| `kernel.allEdges.sweep` | 12:13.66 48:191.73 120:1169.67 | **1.93** | superlinear |
| `app.provenance.newSurfaces` | 24:0.05 120:0.93 360:7.21 | **1.85** | superlinear |
| `modify.trim` | 4:0.01 10:0.06 20:0.21 | 1.83 | superlinear |
| `ramp.solve` | 8:0.08 → 256:5.37 | 1.82 | superlinear |
| `ramp.drag` | 8:2.30 → 128:14.89 | 1.80 | superlinear |
| `app.rebuildPart` | 1:3.78 3:40.81 6:75.16 | **1.71** | superlinear |
| `tools.freehand` | 64:0.03 256:0.21 1024:2.44 | 1.59 | linear |
| `solve.sweep` | 8:0.83 24:3.97 64:21.20 | 1.55 | linear |
| `app.pattern.occurrences.circular` | 4:0.02 16:0.08 64:0.85 | 1.35 | linear |
| `tools.splineEval` | 4:1.61 16:8.82 64:59.38 | 1.30 | linear |
| `modify.transform` | 24:0.02 128:0.17 | 1.25 | linear |
| `ramp.boolean` | 12:10.01 → 144:143.91 | 1.22 | linear |
| `app.pattern.rect` | 4:0.05 16:0.28 64:1.17 | 1.17 | linear |
| `kernel.boolean.complex` | 12:8.06 48:33.88 120:99.94 | 1.09 | linear |
| `kernel.sweep` | 12:89.90 48:392.27 | 1.06 | linear |
| `app.pattern.occurrences.points` | 4:0.00 16:0.02 64:0.07 | 1.05 | linear |
| `ramp.solids` | 1:8.07 → 16:126.19 | 1.05 | linear |
| `ramp.build` | 12:0.79 → 288:17.89 | 1.04 | linear |
| `ramp.mesh` | 12:2.20 → 288:49.98 | 1.02 | linear |
| `app.provenance.faceSurfaces` | 24:0.09 120:0.46 360:1.39 | 1.01 | linear |
| `kernel.mirror` | 24:8.86 120:44.40 | 1.00 | linear |
| `kernel.extrude.arcs` | 12:0.72 48:2.83 120:7.15 | 1.00 | linear |
| `kernel.revolve` | 12:0.55 48:2.16 120:5.48 | 0.99 | linear |
| **`kernel.query.edgeInfoScale`** | 24:12.48 → 240:121.44 | **0.99** | **see §6.5 — linear here is the bad result** |
| `kernel.mesh.complexity` | 12:1.39 48:5.13 120:12.86 | 0.96 | linear |
| `ui.paint.sweep` | 8:0.94 24:2.52 64:6.55 | 0.93 | linear |
| `app.pattern.occurrences` | 4:0.00 16:0.02 64:0.06 | 0.93 | linear |
| `constraints.infer` | 8:0.01 24:0.03 64:0.07 | 0.91 | linear |
| `gear.curve` | 10:5.91 20:11.14 40:19.22 | 0.85 | linear |
| `app.history` | 8:0.98 24:2.09 64:5.44 | 0.82 | linear |
| `app.engineFill` | 24:1.21 128:3.85 | 0.69 | sublinear |
| `app.provenance.attribute` | 2:0.86 6:1.43 12:2.88 | 0.65 | sublinear |
| `kernel.coil` | 1:15.50 4:23.31 12:47.50 | 0.44 | sublinear |
| `kernel.loft` | 2:5.96 4:8.18 8:10.24 | 0.39 | sublinear |
| `kernel.fillet.edges` | 1:49.31 4:49.49 12:49.28 | **-0.00** | flat — `allEdges` dominates |
| `kernel.chamfer.edges` | 1:49.45 4:49.16 12:49.13 | **-0.00** | flat — same cause |
| `tools.spline` | 4:0.00 16:0.00 64:0.05 | — | unmeasurably fast |

---

## 14. What is still NOT measured

Named explicitly so coverage is not mistaken for completeness.

### 14.1 Structural gaps

1. **Inside the C++.** We know `edgeInfo` is O(shape) and we know from reading
   which four operations cause it. We do not have a per-line profile of the
   shim. `kernel.query.edgeInfoScale` bounds it from outside; from Dart there
   is nothing further.
2. **RealityKit's own render loop.** `RvPerf` measures to the hand-off. What
   the renderer then does on its own schedule belongs to the OS.
3. **A sampling profiler.** The suite says which *operation* costs what; a
   profiler says which *line*. For `analyzeSketch` that is the difference
   between "the rank analysis is cubic" and "this loop is". Planned as Track A4
   in PERF_PLAN.md, never built.
4. **`applyBlendOccurrence`** (patterned fillets) has no scenario.
5. **End-to-end rebuild of a real `PatternFeature`** — `app.rebuildPart` drives
   extrusions; a pattern additionally folds a boolean per occurrence, which is
   a different curve.
6. **The twelve leaf widgets of the ribbon**, and the dialogs. For these the
   count matters more than the duration, and `menu.ribbon.builds` = 1 makes
   them uninteresting for now.
7. **Undo journal SIZE.** The duration is measured (`app.checkpoint`); the
   memory the journal holds is not.

### 14.2 A gap in the apparatus itself

**Failure reasons cannot reach the bundle.** `kernel.sweepTwist.fail` = 4 in
this run, and M216 added `lastError` logging precisely so the next run would
say *why*. It is not in the bundle, and the ordering explains it: `log.txt`
ends at 10:47:45 with "BUG REPORT REQUESTED", while the suite ran at 10:48:10
— **25 seconds after the log was captured**. The diagnostic is written after
the snapshot that would carry it, so it can never appear. Any failure reason
belongs in the suite's own JSON, which is written after the suite by
construction.

### 14.3 Conditions never yet captured

* **A run that is not in Low Power Mode.** Both recent device runs were capped.
  Every absolute number in this document is ~2× pessimistic and no clean
  best-case baseline exists.
* **The stress tier has still never run on a device.** It is green in CI and
  shipped in the build; type `stress` in the bug description to include it.
  Its ladders are the only thing that answers "where does it actually fall
  over" rather than extrapolating.
* **A 30-minute continuous session.** Scenario 18 in the catalogue, never run.
  It is the only one that finds a leak, and a CAD session is an hour, not a
  click.

---

## 15. Appendix — how the headline numbers moved across builds

All three device runs were taken under different conditions; this is for
direction, not for precision.

| Measure | `7fb7f8b` (6 Aug) | `9bfe397` (6 Aug, LPM) | `cd961ee` (11 Aug, LPM) |
| --- | ---: | ---: | ---: |
| `allEdges` @ 360 edges | 607 ms | 1171 ms | ~1170 ms |
| One `edgeInfo` @ 360 edges | — | 3.014 ms | **3.038 ms** |
| `analysis` @ 64 entities | 15.69 ms | 26.27 ms | 5.80 ms* |
| `solve.sweep` @ 64 | 7.96 ms | 16.31 ms | 21.20 ms |
| `gear.curve` @ 20 teeth | 5.13 ms | 9.85 ms | 11.14 ms |
| `rv.native.setScene` | — | 55.44 ms | 33.51 ms |
| Low Power Mode | off | **on** | **on** |

\* `ramp.analyze.64` rather than the coarse `analysis.sweep.64` (21.82 ms in
this run) — the ramp uses a different fixture progression, so the two are not
directly comparable.

The `edgeInfo` reproduction is the one to note: **3.014 ms and 3.038 ms on
different builds five days apart** — the defect is perfectly stable and
perfectly reproducible, which is what makes it safe to work on.

---

*Generated from `bug20260811T104745`, build `cd961ee`, iPadOS 27.0.
Regenerate any table with `python3 ci/perf_report.py <bundle.zip>`.*
