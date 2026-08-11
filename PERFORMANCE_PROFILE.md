# Performance Profile — a measurement report

**Analysis only.** No optimisation is proposed here and nothing in the
application was changed to produce these results. This document reports what
each subsystem costs, how that cost scales, and with what confidence.

Companion documents: `PERF_PLAN.md` (experimental design), `PERF_ANALYSIS.md`
(§8–15, chronological derivation of each finding), `HANDOFF.md` (entry point).

---

## 1. Method

Numbers without a stated method are anecdotes. This section defines how every
value below was obtained and what it can support.

### 1.1 Instrument

Timing is `Perf.span`: a pooled `Stopwatch` around a synchronous body,
recorded via `sw.elapsedMicroseconds / 1000.0` (`perf.dart:372`). Two
consequences follow and govern the whole report:

| Property | Value |
| --- | --- |
| Quantum *q* (tick) | **1 µs = 0.001 ms** |
| Observation domain | integer multiples of *q* |
| Per-probe overhead | one `Stopwatch` start/stop + one map lookup; no allocation |
| Aggregation | count, sum, mean, p50, p95, max, over a 128-sample ring buffer |

Counters (`Perf.count`) and gauges (`Perf.gauge`) are exact integers and carry
no timing uncertainty. **Where a count and a duration answer the same
question, the count is the stronger evidence** — it is exact, and it is
invariant under a change of processor.

### 1.2 Quantization model and resolution classes

Because observations are integer-quantized, a uniform quantization model
applies. For a single observation the quantization standard deviation is

> σ_q = q / √12 = 0.289 µs

and for a mean of *n* independent observations the standard error contributed
by quantization alone is

> SE_q = q / √(12·n)

Define the signal-to-noise ratio of a reported mean as SNR = x̄ / SE_q. Every
span in this run was classified on that basis:

| Class | Criterion | Count (of 273 spans) | Treatment |
| --- | --- | ---: | --- |
| **Resolved** | SNR ≥ 10 | **239** | Reported as a measurement |
| **Marginal** | 3 ≤ SNR < 10 | 12 | Reported with the caveat inline |
| **Unresolved** | SNR < 3 | 22 | Reported as **“< 1 µs”**, never as a number |

This matters. Twenty-two spans in this run — including
`pattern.occurrences.mirror`, `app.sceneRevs`, `app.undoStep`,
`app.redoStep`, `sketch.syncProjections`, `modify.offset`, and seven drawing
tools — produced a mean of 0.00000 ms. That value is **not** a measurement of
zero; it is the statement that every observation fell below one microsecond.
Quoting it as “0.000 ms” would imply a precision the instrument does not have.

### 1.3 Measurement scope — two accumulators, and why they differ

Every timing appears in two places, and confusing them was the source of two
errors in an earlier draft of this document. They are stated here as a
convention that the rest of the report follows.

| Scope | Source | Contents |
| --- | --- | --- |
| **Scenario** | `perf_suite.json`, `perf_suite_ui.json` | Spans recorded *inside one bracketed scenario*, measured pass only |
| **Session** | `perf_snapshot.json` | Every span recorded over the process lifetime, **including the warm-up pass** |

Because `runPerfSuite` executes a warm-up pass before the measured one,
**session counts are approximately twice scenario counts**. This is verified
rather than assumed: `ffi.occt.allEdges` records n = 25 / 6077.70 ms in
scenario scope and n = 50 / 12 163.32 ms in session scope — a ratio of exactly
2.0, with the *means* agreeing to 0.07 % (243.11 ms vs 243.27 ms).

The consequences for reading this report:

* **Means, p50, p95 and maxima are safe in either scope** and are quoted from
  session scope, which has the larger sample.
* **Totals and shares are scenario-scope only.** A share computed from a
  session total against a scenario denominator is meaningless.
* Every share below uses the denominator `ci/perf_report.py` uses: the sum of
  all span totals across both runners, 18 480.63 ms for this run.

### 1.4 Significant figures

Values are reported to **three significant figures, truncated at the
quantization floor** for their sample size. A mean over n = 100 has
SE_q ≈ 2.9 × 10⁻⁵ ms, so four decimal places in ms is the finest defensible
resolution; a single observation (n = 1) supports three.

Sample size *n* is given for every timing statistic in this report. A
statistic without an *n* is not interpretable and none appears here.

### 1.5 Curve fitting

Cost curves are fitted by ordinary least squares on log-transformed axes,
giving the exponent *k* in t ∝ n^k. For each family this report gives:

* **N** — number of distinct sizes measured (not the number of observations);
* ***k*** — the fitted exponent;
* **R²** — fraction of log-variance explained;
* **95 % CI on *k*** — from the standard error of the slope, `t ≈ 1.96`.

Three rules are applied and never silently violated:

1. **N = 2 yields a slope, not a fit.** Two points have zero residual degrees
   of freedom: R² is 1.000 by construction and no confidence interval exists.
   Such families are marked *slope only* and no scaling claim is made from
   them.
2. **A low R² is a result, not a failure.** Where the data do not support a
   power law, that is reported as the finding rather than a number being
   quoted anyway.
3. **A wide CI forbids a claim.** Where the interval spans linear and
   quadratic, the report says the two cannot be distinguished.

The size axis differs per family (profile points, entity count, feature count,
edge count) and is stated with each table. The dependent variable is the
scenario’s **dominant span total** — the largest single span recorded inside
the scenario — which excludes fixture construction. This is the same metric
`ci/perf_report.py` uses, so any table here can be regenerated.

### 1.6 Verdict criteria

Three verdicts are used, defined numerically rather than by impression:

| Verdict | Criteria (both required) |
| --- | --- |
| **SMOOTH** | Cost < 1 ms at the largest measured size, **and** upper CI bound on *k* ≤ 1.2 |
| **WATCH** | Cost currently tolerable, **but** lower CI bound on *k* > 1.2 |
| **PROBLEM** | Cost > 10 ms at a size reachable in ordinary use, at any *k* |

Where a verdict rests on judgement beyond these thresholds, the judgement is
stated in the same sentence.

### 1.7 Known confounds

Stated up front because each one limits what the data can support.

1. **Low Power Mode was active for the entire run** (verified at both ends).
   The CPU is capped by policy. A prior controlled comparison — builds
   `7fb7f8b` (LPM off) and `9bfe397` (LPM on), same suite — measured a uniform
   1.67–2.05× slowdown across four unrelated subsystems, so **absolute times
   here are approximately 2× pessimistic** for this device at full clock.
   Ratios, exponents and counts are unaffected. This condition is **not only a
   confound**: §3.5 shows it is a usable proxy for slower hardware, and states
   the limits of that reading.
2. **Self-interference.** The suite executes synchronous FFI calls on the UI
   thread for 24 s. Frame statistics for the session are therefore *of the
   measurement*, not of the application at rest (§3.4).
3. **Warm-up.** Fixtures are memoised and a warm-up pass runs before
   measurement, but the first rung of a ramp still carries more construction
   cost than later rungs. Where this is visible it is noted.
4. **Memoisation.** `gearCurve` memoises on full geometric identity; the cold
   path is measured only because the scenario explicitly clears the cache
   between calls. Any operation with an undisclosed cache is a systematic risk
   to this kind of measurement, and this one was found the hard way (M212).
5. **Single-device.** All results are from one iPad. Nothing here supports a
   claim about any other chip except through the exponents.

---

## 2. Experimental conditions

| Parameter | Value |
| --- | --- |
| Bundle | `bug20260811T104745` |
| Build | `cd961ee` |
| OS | iPadOS 27.0 (24A5390f) |
| Architecture | `ios_arm64` |
| Logical processors | 9 (9 active) |
| Physical memory | 7374 MB |
| Geometry kernel | OCCT shim v17 (OCCT 7.9.3) |
| 2D kernel | qcad C-API 0.1.0 (Qt 6.7.3) |
| Constraint solver | libslvs (native) + Dart Levenberg–Marquardt fallback |
| Dart | 3.12.2 stable |
| Headless suite wall time | 24 354 ms |
| UI suite wall time | 1 138 ms |
| Session wall time | 42 210 ms |

Inputs are fixed and scripted; no human interaction occurs during a run. This
is what makes the run comparable to another run of the same build, and to a
different build of the same suite.

---

## 3. Validity checks

### 3.1 Device state (native probe, sampled before and after the suite)

| Quantity | Pre-suite | Post-suite | Interpretation |
| --- | ---: | ---: | --- |
| Thermal state | `nominal` (0) | `nominal` (0) | No throttling |
| **Low Power Mode** | **on** | **on** | **CPU capped — see §1.7 confound 1, and §3.5** |
| `phys_footprint` | 1372 MB | 1234 MB | The metric jetsam acts on |
| `os_proc_available_memory` | 3747 MB | 3885 MB | Headroom ample |
| Resident (RSS) | 234 MB | 323 MB | |
| Peak resident | 243 MB | 323 MB | |
| CPU | 81 % | 257 % | Multi-core during suite |
| Thread count | 19 | 26 | |

Thermal state constant at both ends means no time-dependent drift confound:
measurements from the second half of the run are comparable with the first.

### 3.2 Repeatability — the noise floor

`quality.variance` re-executes four representative operations and reports
dispersion. Without this, any run-to-run difference is uninterpretable.

| Operation | Median | IQR | Full spread | Smallest meaningful difference |
| --- | ---: | ---: | ---: | ---: |
| `extrude` | 2834 µs | **0 %** | 3 % | ~3 % |
| `solve` | 281 µs | 4 % | 18 % | ~18 % |
| `analyze` | 1777 µs | 13 % | 17 % | ~17 % |
| `splineEval` | 104 µs | 7 % | **67 %** | ~67 % |

Kernel work is effectively noise-free. **A change below ~17 % in `analyze` or
`solve`, or below ~67 % in `splineEval`, is not a signal.** This is the
threshold against which any future baseline diff must be read.

### 3.3 Null-measurement audit

A scenario that reaches nothing still emits a number, and a fast zero is
indistinguishable from a fast operation. Guards are therefore explicit:

| Counter | Value | Status |
| --- | ---: | --- |
| `kernel.sweepTwist.fail` | 4 | **Genuine failure.** Twisted sweep returns null. Cause still unobtainable — §9.2. |
| `tool.build.fillet.null` | 2 | Expected: the generic point generator cannot guarantee a fittable corner. Covered by `tools.fillet2d`. |
| `tool.build.chamfer.null` | 2 | Expected, same cause. |

All other scenarios published a non-zero subject gauge. Specifically, the
M220 fixtures were verified to reach their subject on-device: face
decomposition returned 26/122/362 surfaces at the three sizes, attribution
matched 62 faces, and the five pattern kinds produced 15/15/16/15/1
placements — each equal to the value its host-side test asserts.

### 3.4 What the frame counters do and do not measure

Session: n = 304 frames, 39.0 fps, 162 frames over 33 ms.

| Phase | n | mean | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: | ---: |
| `frame.build` (Dart) | 304 | 0.323 ms | 0.175 ms | 0.835 ms | 6.32 ms |
| `frame.raster` (GPU) | 304 | 2.23 ms | 2.21 ms | 3.46 ms | 8.87 ms |
| `frame.total` | 304 | 25.6 ms | 36.0 ms | 37.6 ms | 154 ms |

Build + raster ≈ 2.4 ms at p50 against a 36 ms frame total. **The residual is
the UI thread blocked by the suite’s own synchronous kernel calls** (§1.7 confound 2).
These figures characterise the instrument under load, not the application in
use, and no usability conclusion is drawn from them.

### 3.5 Low Power Mode as a proxy for older hardware

The cap is an accidental controlled experiment, and a useful one: the app must
also run on iPads considerably slower than an M4. The question is what kind of
transform Low Power Mode applies — a uniform clock scaling, or a change in the
machine's balance.

**The data answer it.** Four subsystems, same suite, same device, LPM off → on:

| Subsystem | Work dominated by | LPM off | LPM on | ratio |
| --- | --- | ---: | ---: | ---: |
| `allEdges` @ 360 edges | native C++ topology traversal (pointer-chasing, memory-bound) | 607 ms | 1171 ms | **1.929** |
| `analysis.sweep.64` | Dart dense matrix reduction | 15.69 ms | 26.27 ms | 1.674 |
| `solve.sweep.64` | native libslvs + Dart verification | 7.96 ms | 16.31 ms | 2.049 |
| `gear.curve.20` | Dart transcendental arithmetic (compute-bound) | 5.13 ms | 9.85 ms | **1.920** |

Mean 1.893, SD 0.157, **CV 8.3 %**, range 1.674–2.049.

The decisive comparison is the first row against the last: a **memory-bound
native traversal** and a **compute-bound Dart floating-point loop** scale by
1.929 and 1.920 — a difference of 0.5 %. Had the cap altered memory bandwidth
or cache behaviour disproportionately, those two would have separated sharply.
They do not. **Low Power Mode behaves as a clock scalar, not as a different
machine.**

**Why this proxy is unusually valid for this application.** Finding B1 of the
original survey still holds: there is not a single `Isolate` in the codebase,
and all 58 FFI entry points execute synchronously on the UI thread. The app is
therefore clock-bound and effectively single-threaded on its critical path, so
core count is nearly irrelevant to it and clock is nearly everything — exactly
the axis Low Power Mode moves. For a parallel application this proxy would be
much weaker.

#### What it does and does not stand in for

| Axis of an older iPad | Proxied? | Basis |
| --- | --- | --- |
| Lower CPU clock | **Yes, well** | Uniform 1.89× across unrelated subsystems |
| Single-thread-bound critical path | **Yes** | Zero isolates; all FFI on the UI thread |
| 60 Hz panel rather than ProMotion | **Yes, incidentally** | LPM caps refresh; §8.6 gives the 60 Hz budget |
| Smaller caches / lower memory bandwidth | **No** | LPM leaves the balance unchanged; an older SoC would not, and `allEdges` is precisely the pointer-chasing workload that would degrade *more* than the scalar predicts |
| **Less RAM, lower jetsam ceiling** | **No** | This device had 3.7–3.9 GB of headroom throughout. A 3–4 GB iPad has far less |
| Weaker GPU | **Not tested** | `frame.raster` p95 was 3.46 ms here and is not GPU-limited |

The unproxied memory axis is the consequential one: **the field crash was a
memory kill on `phys_footprint`, and Low Power Mode says nothing whatsoever
about that.** The two figures that do transfer unchanged, because they are
properties of the data rather than of the processor, are **14 bytes per
triangle** and **2 KB per solid** (§8.5). On a 4 GB iPad those convert directly
into a much lower ceiling on model size.

#### What a slower device can still handle

For a cost model t = c·n^e, holding wall time fixed, the reachable size on a
device k times slower scales as k^(−1/e). Taking k = 1.893 — that is, treating
these LPM figures as the *fast* case and asking about a device a further factor
of 1.89 slower:

| Operation | e | Reachable size vs the faster device |
| --- | ---: | ---: |
| `analyzeSketch` | 2.30 | 75.8 % |
| `allEdges` | 1.935 | **71.9 %** |
| Constraint density | 1.79 | 70.0 % |
| Booleans | 1.07 | 55.1 % |
| Mesh / extrude | 0.99 | 52.5 % |

**A non-obvious consequence: steeper exponents lose *less* reachable size.**
Because a quadratic cost climbs fast, only a modest reduction in size is needed
to absorb a given slowdown, whereas a linear operation must halve its input to
absorb a factor of two. This inverts the intuition that superlinear operations
are the ones that "fall off a cliff" on weaker hardware — on the *size* axis
they degrade most gracefully. What makes them dangerous is not their behaviour
across devices but their behaviour across model sizes on any one device.

Applying this to the dominant defect — the model size at which `allEdges`
alone consumes one second:

| Device state | 1-second threshold |
| --- | ---: |
| This device, LPM off (≈ 1.89× faster) | ≈ 456 edges |
| **This device, LPM on (as measured)** | **≈ 328 edges** |
| A device a further 1.89× slower | ≈ 236 edges |

A part with a few hundred edges is unremarkable. On slower hardware the defect
of §6.5 is not merely slower — it is reached by smaller models.

#### Standing recommendation

Because the transform is uniform and the application is clock-bound, **runs
under Low Power Mode are worth keeping deliberately**, not merely tolerated
when they happen. The productive protocol is to capture both: an uncapped run
for the device's true best case, and a capped run as a standing lower bound
that approximates weaker hardware. What a capped run cannot substitute for is a
**memory**-constrained one, and that gap can only be closed on a device with
less RAM, or by the stress tier's memory ladders (§9.3), which have still never
been executed on any device.

---

---

## 4. Summary of results

Ranked by severity. Every row is expanded, with its evidence, in §5–§8.

| # | Subsystem | Measured cost | *k* [95 % CI] | Verdict |
| ---: | --- | ---: | ---: | --- |
| 1 | `occt_shape_edge_info` / `allEdges` | 243 ms mean, 1702 ms max, 32.9 % of measured span time | **1.935** [1.910, 1.960] | **PROBLEM** |
| 2 | Solver LM fallback | 50.4 ms vs 0.271 ms (186×) | bimodal, not a curve | **PROBLEM** |
| 3 | Painter solves twice per dragged frame | 86.8 % of paint time | — (exact counts) | **PROBLEM** |
| 4 | `analyzeSketch` | 156 ms at 256 entities | **2.30** [2.15, 2.46] | **PROBLEM** |
| 5 | Fillet radius sensitivity | 10 ms → 658 ms (≈65×) | discontinuous | **PROBLEM** |
| 6 | `sweepProfile` | 160 ms mean, 396 ms max | 1.06 (slope only) | **PROBLEM** (absolute) |
| 7 | Constraint density | 18.3 ms at 8× redundancy | **1.79** [1.69, 1.88] | **WATCH** |
| 8 | Booleans | 14.2 ms mean, 126 ms max | **1.07** [1.03, 1.12] | **WATCH** (absolute) |
| 9 | RealityKit origin planes | 33.4 of 33.5 ms | n = 1 | **WATCH** |
| 10 | `newSurfacesOf` | 0.721 ms at 362 faces | **1.85** [1.84, 1.86] | **WATCH** |
| 11 | `modify.intersections` | 0.331 ms at 20 entities | **2.25** [2.05, 2.45] | **WATCH** |
| 12 | Part rebuild | 25.1 ms at 6 features | 1.71 [1.04, 2.39] — **indeterminate** | **WATCH** |

---

## 5. Results — 2D

### 5.1 Painter decomposition

`2d.paint`, session: n = 300, total 101 ms, mean 0.336 ms. Eighteen named
phases plus `2d.paint.z`, which captures anything after the final mark.

| Phase | n | mean (ms) | share | class |
| --- | ---: | ---: | ---: | --- |
| `constraints` | 300 | 0.1159 | 34.5 % | resolved |
| `ent.dofColour` | 300 | 0.1121 | 33.3 % | resolved |
| `entities` | 300 | 0.1047 | 31.2 % | resolved |
| `editRef` | 300 | 0.0012 | 0.3 % | resolved |
| `z` (unaccounted) | 300 | 0.0008 | 0.2 % | marginal |
| `ent.halo` | 300 | 0.0003 | 0.1 % | marginal |
| 12 further phases | 300 | ≤ 0.0001 each | < 0.1 % total | unresolved |
| `slice` | 300 | < 1 µs | — | **unresolved** |

**Completeness check:** `2d.paint.z` at 0.2 % confirms the decomposition
accounts for the function. The probe reports its own gaps, and there is no gap.

### 5.2 Static paint versus paint during a drag

The same function measured in two regimes. This is the most consequential
comparison in the 2D path.

| Phase | Static (`ui.paint.sweep.64`, n = 30) | Dragging (`ui.drag60`, n = 60) |
| --- | ---: | ---: |
| `entities` | **0.2124 ms (97.3 %)** | 0.0802 ms (12.6 %) |
| `constraints` | 0.0022 ms (1.0 %) | **0.2772 ms (43.6 %)** |
| `ent.dofColour` | 0.0010 ms (0.5 %) | **0.2748 ms (43.2 %)** |
| whole `2d.paint` | 0.2183 ms | 0.6359 ms |

**Static painting is 97.3 % drawing. Painting during a drag is 86.8 % solving
and 12.6 % drawing.** The regimes are inverted.

The cause is established by exact counters, not by timing inference:

| Counter (`ui.drag60`) | Value |
| --- | ---: |
| Frames painted | 60 |
| `2d.displayGeometry` invocations | **120** |
| `2d.displayGeometry.solves` | **120** |
| `solve.total` invocations | **120** |
| `solve.path.slvs` | 120 |
| `solve.path.lm` | 0 |

Exactly **two solves per painted frame**, from two call sites —
`viewport.dart:2088` (within the `ent.dofColour` segment) and
`viewport.dart:2683` (within the `constraints` segment) — computing the same
result. Session-wide: `2d.displayGeometry` n = 240, mean 0.2821 ms.

**Verdict: PROBLEM.** Note also that the phase name misleads: an earlier
reading, “dofColour is 85 % of painting”, attributed the cost to DOF colouring.
It is the solve located inside that segment. The colouring itself
(`carrierFixed` per entity) sits in `entities` and costs ≈ 0.11 ms at 128
entities.

### 5.3 Pointer path

| Path | n | mean | p50 | p95 | max |
| --- | ---: | ---: | ---: | ---: | ---: |
| `2d.snap` | 240 | 0.0079 ms | 0.009 | 0.010 | 0.012 |
| `2d.pickEntity` | 480 | 0.0899 ms | 0.127 | 0.140 | 0.280 |

Isolated (`ui.snapHover`, n = 120 each): snap 0.0079 ms, pick 0.0497 ms — a
ratio of 6.3.

**Snapping costs between 1/6 and 1/11 of the entity pick beside it.** Snap
appeared in no report before M212 because the measurement point did not exist;
measured, it is the cheapest step on the pointer path. **Verdict: SMOOTH**
(both; largest measured value 0.28 ms, no size dependence claimed).

### 5.4 Constraint solver

Session: `solve.total` n = 726, mean 2.57 ms, **p50 0.271 ms**, p95 0.279 ms,
**max 66.9 ms**.

A mean of 2.57 ms sitting between a p50 of 0.271 ms and a max of 66.9 ms is
the signature of **two populations**, not of dispersion around a centre. The
path counters identify them exactly:

| Counter | Value | Share |
| --- | ---: | ---: |
| `solve.path.slvs` (native accepted) | 698 | 96.1 % |
| `solve.path.lm` (Dart fallback) | **28** | **3.9 %** |
| `solve.slvs.rejected.residual` | 24 | — |

| Layer | n | mean | max |
| --- | ---: | ---: | ---: |
| `solve.total` | 726 | 2.57 ms | 66.9 ms |
| `solve.slvs` (native attempt + verification) | 726 | 0.612 ms | 18.4 ms |
| `ffi.slvs.solve` (libslvs proper) | 722 | 0.492 ms | 18.2 ms |
| `solve.lm` (Dart fallback) | **28** | **50.4 ms** | 64.7 ms |

**The fallback costs 186× a fast-path solve.** The mean of 2.57 ms describes
neither population and should not be quoted.

Mechanism, isolated (`solve.overConstrained`, n = 10):

| Layer | mean | share of `solve.total` |
| --- | ---: | ---: |
| `solve.total` | 66.4 ms | 100 % |
| `solve.lm` | 64.2 ms | **96.7 %** |
| `solve.slvs` | 2.16 ms | 3.2 % |
| `ffi.slvs.solve` | 0.228 ms | **0.34 %** |

libslvs performs comparably in both regimes (0.2281 ms here against 0.2202 ms
in a normal drag — a ratio of 1.04). The end-to-end difference between an
over-constrained solve and a normal one is **66.352 / 0.2711 = 245×**, and
**all of it is Dart-side.**
`solver.dart:2172` verifies the native result against its own residuals,
rejects it above tolerance (`solve.slvs.rejected.residual` = 10 for these 10
solves), then runs the Dart Levenberg–Marquardt — twice during a drag
(`lm-frozen`, then `lm-relaxed`), each 80 iterations of finite-difference
Jacobians over a 168-parameter system.

For contrast, a normal drag (`ui.drag60`, n = 120): `solve.total` 0.271 ms,
`solve.slvs` 0.259 ms, `ffi.slvs.solve` 0.220 ms — **81 % of the time inside
libslvs**, which is where it belongs.

**Verdict: fast-path solving SMOOTH; the fallback a PROBLEM.** `solve.path.lm`
is the first quantity to inspect on any report of drag stutter: non-zero means
the sketch left the fast path.

**Scaling of the fast path** (`ramp.solve`, settled sketch; axis = entities):

N = 10, **k = 1.34, R² = 0.9498, 95 % CI [1.13, 1.56]**

| Entities | 8 | 16 | 24 | 32 | 48 | 64 | 96 | 128 | 192 | 256 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ms | 0.076 | 0.075 | 0.118 | 0.168 | 0.304 | 0.481 | 0.936 | 1.53 | 3.18 | **5.37** |

The CI excludes both linear and quadratic; growth is superlinear but modest,
and 5.37 ms at 256 entities is affordable. **Size is not the solver’s problem.**

**Scaling with constraint density** at fixed entity count (`ramp.density`,
redundant repetitions — how sketches become over-constrained in practice):

N = 6, **k = 1.79, R² = 0.9971, 95 % CI [1.69, 1.88]**

| Density × | 1 | 2 | 3 | 4 | 6 | 8 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| ms | 0.452 | 1.34 | 2.70 | 4.74 | 10.3 | **18.3** |

Density is markedly steeper than entity count and the interval is tight. This
axis was unmeasured before M219 and is the one a user grows by
over-constraining. **Verdict: WATCH.**

### 5.5 Degree-of-freedom analysis (`analyzeSketch`)

Session: n = 75, mean 8.94 ms, p50 0.776 ms, p95 27.5 ms, **max 159 ms**.

Executes on every rebuild, every solve and every tab switch
(`app_state.dart:2163`, `:2183`, `:6486`). Builds a finite-difference Jacobian
— a full residual evaluation per parameter — then reduces it row-wise.

`ramp.analyze`, N = 10, **k = 2.30, R² = 0.9908, 95 % CI [2.15, 2.46]**

| Entities | ms | local exponent vs previous |
| ---: | ---: | ---: |
| 8 | 0.066 | — |
| 16 | 0.206 | 1.65 |
| 24 | 0.433 | 1.84 |
| 32 | 0.782 | 2.05 |
| 48 | 1.79 | 2.04 |
| 64 | 5.80 | **4.08** |
| 96 | 13.5 | 2.08 |
| 128 | 22.6 | 1.78 |
| 192 | 72.0 | 2.86 |
| 256 | **156** | 2.69 |

The 95 % CI excludes quadratic from below at the top end and the **local**
exponents are not constant — evidence that a single power law is an
approximation here, not a law:

* a **discontinuity at 64 entities** (local exponent 4.08 across one step,
  then back to ≈ 2.0), which a three-point fit averages away entirely;
* a **rising exponent past 128** (2.86, 2.69), consistent with cubic row
  reduction becoming dominant.

This is the specific reason ramps exist: a fit through three points assumes
the curve *is* a power law and cannot reveal a knee.

**Verdict: PROBLEM.** 156 ms per analysis at 256 entities, on every solve.

### 5.6 Drag, end to end

`ramp.drag`, N = 8, k = 0.96, **R² = 0.6213**, 95 % CI [0.36, 1.55].

| Entities | 8 | 16 | 24 | 32 | 48 | 64 | 96 | 128 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ms | 2.30 | 0.570 | 0.968 | 1.42 | 5.35 | 4.59 | 8.88 | **14.9** |

**No exponent is claimed for this family.** R² = 0.62 and a CI spanning
[0.36, 1.55] mean the data do not support a power law: the first rung carries
fixture cost and two rungs (16, 64) fall below their predecessors. Per rule
rule 2 of §1.5, this is reported as an absence of fit rather than as a number.

What the data *do* support is the endpoint: **14.9 ms per dragged frame at 128
entities**, which at two solves per frame exceeds a 120 Hz budget and
approaches the 60 Hz limit.

### 5.7 Drawing tools

All 26 tools in `toolMeta`, driven generically so a new tool is measured on
the day it is added. n = 100 each; SE_q = 2.9 × 10⁻⁵ ms.

| # | Tool | mean (ms) | | # | Tool | mean (ms) |
| ---: | --- | ---: | --- | ---: | --- | ---: |
| 1 | `eqCurve` | 0.0425 | | 14 | `rectTwoPoint` | 0.0005 |
| 2 | `bridge` | 0.0101 | | 15 | `polygon` | 0.0004 |
| 3 | `circleTangent` | 0.0101 | | 16 | `ellipse` | 0.0001 |
| 4 | `arcTangent` | 0.0036 | | 17 | `arcThreePoint` | 0.0001 |
| 5 | `fillet` | 0.0036 | | 18 | `lineMid` | < 1 µs |
| 6 | `chamfer` | 0.0024 | | 19 | `point` | < 1 µs |
| 7 | `splineInterp` | 0.0012 | | 20 | `circleCenter` | < 1 µs |
| 8 | `slotCC` | 0.0012 | | 21 | `rect2PC` | < 1 µs |
| 9 | `splineCV` | 0.0011 | | 22 | `slotOverall` | < 1 µs |
| 10 | `splineFree` | 0.0011 | | 23 | `slotCP` | < 1 µs |
| 11 | `slot3A` | 0.0010 | | 24 | `rect3PC` | < 1 µs |
| 12 | `slotCPA` | 0.0009 | | 25 | `arcCenter` | < 1 µs |
| 13 | `line` | 0.0005 | | 26 | `rect3P` | < 1 µs |

Ranks 18–26 are in the **unresolved** class (§1.2): their means fall below the
instrument’s floor and are reported as such rather than as numbers.

**Verdict: SMOOTH.** The slowest tool constructs geometry in 42.5 µs. Tool
construction is not a cost centre. The upper bound on the whole family is
`eqCurve` at 0.0425 ms — three orders of magnitude below a frame budget.

Associated 2D geometry:

| Operation | n | mean | fit |
| --- | ---: | ---: | --- |
| `spline.curveFor` (evaluation, 64 CVs) | 600 | 0.594 ms | k = 1.30 [1.22, 1.39], R² = 0.999 |
| `tool.spline.cv` / `.interp` (construction) | 20 | 0.002 ms | marginal |
| `tools.filletMaxRadius` (40-step search) | 20 | 0.0495 ms | — |
| `ellipse.curve` | 200 | 0.0020 ms | — |
| `freehand.fit` | 60 | 0.0872 ms | k = 1.59 [1.38, 1.79] |
| `freehand.smooth` | 60 | 0.0785 ms | — |
| `freehand.dedupe` | 60 | 0.0044 ms | — |

Spline **evaluation** exceeds spline **construction** by roughly 300× — the
separation that makes that visible was deliberate. `filletMaxRadius` costs
46× a single fillet computation, matching the prediction from its 40-iteration
binary search, at 0.0495 ms absolute.

### 5.8 Modify operations

| Operation | n | mean (ms) | fit |
| --- | ---: | ---: | --- |
| `modify.intersectionsWithOthers` | 136 | 0.0063 | **k = 2.25 [2.05, 2.45]**, R² = 0.998 |
| `modify.trimEntity` | 68 | 0.0084 | k = 1.83 [1.76, 1.89], R² = 1.000 |
| `modify.transformGeo` | 80 | 0.0058 | k = 1.25, slope only (N = 2) |
| `modify.extendEntity` | 40 | 0.0049 | — |
| `modify.stretchGeo` | 40 | 0.0042 | — |
| `modify.offsetChainAt` | 100 | 0.0035 | — |
| `modify.offsetEntity` | 800 | 0.0004 | marginal |
| `modify.offset` | 800 | < 1 µs | **unresolved** |

**`modify.intersections` carries the steepest well-determined exponent in the
2D path** — the CI excludes anything below 2.05 — and it executes on every
modify click. At 20 entities it costs 0.331 ms. Extrapolating the fitted model
(and labelling it as extrapolation): ≈ 33 ms at 200 entities, ≈ 350 ms at 600.

**Verdict: WATCH.** Microseconds today; the exponent is the concern.

### 5.9 Constraints

Cost of adding one constraint, by type (n = 2 each — small samples, reported
because the spread between types is far larger than the uncertainty within
one):

| Type | mean (ms) | | Type | mean (ms) |
| --- | ---: | --- | --- | ---: |
| **`dimension`** | **44.2** | | `symmetric` | 0.592 |
| **`tangent`** | **12.2** | | `midpoint` | 0.585 |
| **`fix`** | **11.2** | | `horizontal` | 0.562 |
| `perpendicular` | 4.43 | | `concentric` | 0.559 |
| `parallel` | 0.650 | | `vertical` | 0.522 |
| `coincident` | 0.629 | | `equal` | 0.520 |
| `collinear` | 0.624 | | `smooth` | 0.440 |

**Entering one dimension costs 70× a coincident constraint, and 101× the
cheapest (`smooth`).** The four
expensive types are precisely those whose native result fails verification,
triggering the Dart LM path of §5.4. This is the same defect observed from the
editing side rather than the dragging side, and the two observations are
mutually corroborating.

Supporting operations, all SMOOTH:

| Operation | n | mean (ms) |
| --- | ---: | ---: |
| `constraints.encode` | 40 | 0.268 |
| `constraints.decode` | 40 | 0.173 |
| `constraints.inferConstraints` | 80 | 0.0039 |
| `constraints.inferPointBindings` | 80 | 0.0025 |

`constraints.infer`: k = 0.91 [0.76, 1.06] — linear, R² = 0.993.

### 5.10 Gear generation

| Quantity | n | value |
| --- | ---: | ---: |
| `gear.curve` (cold) | 120 | 0.607 ms |
| `gear.curve.cached` | 1200 | 0.0010 ms |
| Cold path, isolated | — | 475 µs |
| Warm path, isolated | — | 1 µs |
| **Cache speed-up** | — | **432×** |

`gear.curve` fit: k = 0.85 [0.78, 0.92], R² = 0.998 — **sublinear to linear**,
≈ 0.21 µs per generated point.

**Verdict: SMOOTH, and the memoisation is effective.** Four 20-tooth gears
cost ≈ 1 ms once, at load. Gears were the original suspect for the crash in
the field; they are excluded by these measurements.

---

## 6. Results — 3D geometry kernel

### 6.1 Feature construction

| Operation | n | mean | max | fit |
| --- | ---: | ---: | ---: | --- |
| **`sweepProfile`** | 16 | **160 ms** | **396 ms** | k = 1.06, slope only (N = 2) |
| `coilProfile` | 6 | 29.0 ms | 47.5 ms | k = 0.44 [0.25, 0.64] |
| `loftSections` | 10 | 13.8 ms | 35.6 ms | k = 0.39 [0.32, 0.47] |
| `extrudeProfileArcs` | 410 | 3.92 ms | 66.2 ms | **k = 1.00 [0.98, 1.01]** |
| `revolveProfile` | 12 | 2.95 ms | 5.54 ms | **k = 0.99 [0.98, 1.01]** |
| `extrudeProfile` | 12 | 0.929 ms | 1.82 ms | — |
| `makeCylinder` | 18 | 0.0097 ms | 0.021 ms | — |
| `makeBox` | 9 | 0.164 ms | 1.27 ms | — |

Common axis (profile points), directly comparable:

| Profile points | `extrude.arcs` | `revolve` | `mesh.complexity` |
| ---: | ---: | ---: | ---: |
| 12 | 0.722 ms | 0.554 ms | 1.39 ms |
| 48 | 2.83 ms | 2.16 ms | 5.13 ms |
| 120 | 7.15 ms | 5.48 ms | 12.9 ms |

`kernel.sweep.path` (96-point path): **205 ms per sweep**, n = 3.

**Verdict: sweep is a PROBLEM on absolute cost** — 160 ms mean over 16
observations, 396 ms max, for an ordinary modelling operation. Its exponent is
a two-point slope and no scaling claim is made. Extrude, the most-executed
kernel operation in this run (n = 410), is 3.92 ms and exactly linear
(CI [0.98, 1.01]).

### 6.2 Boolean operations

| Operation | n | mean | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| `fuse` | 90 | 14.2 ms | 76.0 ms | 126 ms |
| `cut` | 16 | 17.3 ms | 90.2 ms | 90.9 ms |
| `common` | 16 | 16.6 ms | 86.8 ms | 87.1 ms |
| `unify` | 44 | 0.0808 ms | 0.095 ms | 0.141 ms |

`ramp.boolean` (axis = operand profile points): N = 7, **k = 1.07, R² = 0.9974,
95 % CI [1.03, 1.12]**

| Profile points | 12 | 24 | 36 | 48 | 72 | 96 | 144 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| ms | 10.0 | 19.2 | 29.2 | 39.9 | 62.9 | 87.6 | **144** |

The CI excludes quadratic decisively and barely admits anything above linear —
about as favourable as boolean scaling gets. An 8-deep fusion chain
(`kernel.boolean.chain`) averages 8.20 ms per fuse over 8 operations.

**Verdict: WATCH on absolute cost.** 144 ms for a single boolean on a
144-point profile is a perceptible stall, and a rebuild performs one per
feature. `unify` is negligible.

### 6.3 Fillet and chamfer

| Edges filleted | `allEdges` | `filletEdges` | ratio |
| ---: | ---: | ---: | ---: |
| 1 | **49.3 ms** | 10.1 ms | candidate search = **4.9×** the rounding |
| 4 | 49.5 ms | 20.8 ms | 2.4× |
| 12 | 49.3 ms | 46.7 ms | 1.06× |

`kernel.fillet.edges` fit: N = 3, k = −0.00, **R² = 0.0025**.

**R² ≈ 0 is the result.** The null hypothesis — that total cost is independent
of the number of edges filleted — is not rejected. The wall time does not move
because candidate search dominates it. `kernel.chamfer.edges` behaves
identically (k = −0.00, R² = 0.877 on a range of 0.3 %, i.e. also flat;
`chamferEdges` itself n = 6, mean 25.2 ms, max 46.2 ms).

**Radius sensitivity** (`kernel.fillet.radius`, n = 3):

| Quantity | Value |
| --- | ---: |
| `filletEdges` mean | 233 ms |
| `filletEdges` max (r = 4.0) | **658 ms** |
| r = 1.0 on the same solid | ≈ 10 ms |
| **Ratio** | **≈ 65×** |

A radius large enough to reach neighbouring geometry is not a slower instance
of the same operation; it is a different operation. With n = 3 this is a
demonstration of magnitude, not a characterised curve.

**Verdict: PROBLEM** on both axes.

### 6.4 Tessellation

| Operation | n | mean | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| `meshCreate` (OCCT tessellating) | 302 | 4.48 ms | 6.57 ms | 41.6 ms |
| `meshCopyOut` (Dart copying across FFI) | 302 | **0.0046 ms** | 0.008 ms | 0.197 ms |

Both are in the resolved class (`meshCopyOut` SNR ≈ 277).

`ramp.mesh`: N = 9, **k = 0.99, R² = 0.9992, 95 % CI [0.97, 1.01]** — linear
to within ±2 %, over a 24× range of input size (12 → 288 profile points,
2.20 → 50.0 ms).

**`meshCreate` exceeds `meshCopyOut` by a factor of 974.** This was a
falsifiable question — nine typed copies of up to hundreds of thousands of
doubles could plausibly have dominated — and the answer is unambiguous: the
FFI boundary is **not** where tessellation cost lives. Separating the two
spans is what made the question answerable.

**Verdict: SMOOTH** (linear within a tight interval; boundary exonerated).

### 6.5 Topology queries — the principal finding

Three independent lines of evidence, each capable of refuting the others.

**Observed cost.**

| Quantity | Scenario scope | Session scope |
| --- | ---: | ---: |
| `ffi.occt.allEdges` observations | n = **25** | n = **50** (incl. warm-up) |
| Total | **6077.70 ms** | 12 163.32 ms |
| Mean | **243.11 ms** | 243.27 ms |
| p50 | — | 50.0 ms |
| p95 | — | **1171 ms** |
| Max | — | **1702 ms** |
| **Share of all measured span time** | **32.9 %** | — |
| `ffi.occt.edgeInfo.calls` (exact counter) | — | **6552** |

Per §1.3: the two scopes differ by the warm-up pass (ratio exactly 2.0) and
their means agree to 0.07 %. The share is scenario-scope against the
18 480.63 ms denominator; distribution statistics are session-scope.

**Evidence 1 — growth curve.** `ramp.allEdges`, N = 7,
**k = 1.935, R² = 0.99978, 95 % CI [1.910, 1.960]**

| Profile pts | Edges | ms | local exponent | µs per edge |
| ---: | ---: | ---: | ---: | ---: |
| 12 | ≈ 36 | 14.1 | — | 392 |
| 24 | ≈ 72 | 50.8 | 1.85 | 706 |
| 36 | ≈ 108 | 111 | 1.93 | 1029 |
| 48 | ≈ 144 | 196 | 1.97 | 1361 |
| 72 | ≈ 216 | 434 | 1.96 | 2008 |
| 96 | ≈ 288 | 766 | 1.98 | 2659 |
| 144 | ≈ 432 | **1709** | 1.98 | **3955** |

R² = 0.9998 over a 12× range, with local exponents converging on 1.98 and
remaining there. This is a clean quadratic with no knee. Per-edge cost rises
10× across the ramp — the diagnostic signature of per-call work proportional
to the whole shape.

**Evidence 2 — one call against a growing shape.** `kernel.query.edgeInfoScale`
queries **the same edge** (index 1), 20 times, on solids of increasing size.
The requested work is held constant; only the surrounding shape varies.

N = 4, **k = 0.99, R² = 0.9999, 95 % CI [0.97, 1.01]**

| Profile pts | Edges | Faces | mean per call (n = 40) | ratio to smallest |
| ---: | ---: | ---: | ---: | ---: |
| 24 | 72 | 26 | 0.6252 ms | 1.00 |
| 60 | 180 | 62 | 1.5080 ms | 2.41 |
| 120 | 360 | 122 | 3.0383 ms | 4.86 |
| 240 | 720 | 242 | **6.0729 ms** | **9.71** |

Edge and face counts are exact gauges read from the kernel, not derived.

Edge count ×10 → cost of one unchanged query ×9.71, with the exponent’s CI
excluding anything outside [0.97, 1.01]. **A single `edgeInfo` is Θ(shape).**
`allEdges` issues one per edge; n × Θ(n) = Θ(n²) then follows arithmetically
rather than by inference. A flat line here would have refuted the hypothesis
and returned the diagnosis to the FFI boundary; it did not appear.

> **Interpretation warning.** `ci/perf_report.py` labels this family “linear”.
> For this family linear is the *positive* result for the defect hypothesis,
> because the swept axis is not the quantity of work requested but the size of
> the shape one fixed unit of work must traverse. The tool cannot distinguish
> the two; a reader must.

**Evidence 3 — control queries on the same solid** (360 edges):

| Query | n | mean | ratio |
| --- | ---: | ---: | ---: |
| `kernel.edgeInfo1` (one edge) | 20 | 2.9862 ms | 1.00 |
| `kernel.counts()` | 20 | 0.2061 ms | **1/14.5** |
| `kernel.bbox()` | 20 | 0.1651 ms | **1/18.1** |

Touching the shape is cheap; crossing the FFI boundary is cheap; querying one
edge is not. **Closure check:** 360 × 2.9862 ms = 1075.0 ms against the measured
`allEdges` of 1169.7 ms on the same solid (`kernel.allEdges.sweep.120`) —
**91.9 % of the total accounted for by per-call cost**, the residual 8.1 %
being boundary crossings and Dart-side list construction. Both figures are
scenario-scope, so the comparison is like-for-like.

**Mechanism in source** (`backend/occt/shim/occt_capi.cpp`): each call performs
four whole-shape operations — `TopExp::MapShapes` (:1738),
`TopExp::MapShapesAndAncestors` (:1792), `BRepBndLib::Add` (:1832), and
construction of a `BRepClass3d_SolidClassifier` (:1836) — and discards all
four. The latter two lie in the convexity branch, taken for any edge with
exactly two adjacent faces: on a closed solid, the majority.

**Extrapolation to the part that crashed in the field (≈ 3400 edges),** stated
as extrapolation with its interval propagated from the fit:

| Basis | Predicted `allEdges` |
| --- | ---: |
| Central (k = 1.935) | **90.4 s** |
| CI lower (k = 1.910) | 75.8 s |
| CI upper (k = 1.960) | 108 s |

Correcting for Low Power Mode (§1.7 confound 1 and §3.5, ≈ 1.89×) gives an order of **40–55 s** on
an uncapped device, consistent with the ≈ 48 s previously derived by a
different route.

**Verdict: PROBLEM — the largest single cost in the application.**

### 6.6 Placement

| Operation | n | mean |
| --- | ---: | ---: |
| `ffi.occt.transform` | 140 | 0.430 ms |
| `ffi.occt.mirror` | 40 | 2.67 ms |

Paired comparison, both operations on the **same solid within one scenario**
(n = 10 each), which controls for shape:

| Solid | `mirror` | `transform` | ratio |
| ---: | ---: | ---: | ---: |
| 72 edges | 0.886 ms | 0.291 ms | **3.04** |
| 360 edges | 4.44 ms | 1.48 ms | **3.00** |

The ratio is stable at 3.0 across a 5× change in shape size — a stronger
statement than either absolute value, and invariant to the Low Power Mode
confound. The excess is the reflection plus the orientation correction the
shim applies so the result may enter a boolean directly.

`kernel.mirror` fit: k = 1.00, **slope only (N = 2)** — no scaling claim.

**Verdict: SMOOTH**, with the ratio recorded so a mirror pattern’s cost is
predictable (it is paid once per occurrence).

### 6.7 Ray casting

| Operation | n | mean | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| `kernel.rayHit` | 120 | 0.243 ms | 0.242 | 1.24 |
| `ffi.occt.rayHits` | 120 | 0.243 ms | 0.241 | 1.24 |

The difference between the two is 0.4 µs — below the instrument’s floor,
i.e. the Dart wrapper adds nothing measurable. **Verdict: SMOOTH.**

### 6.8 Feature rebuild

| Quantity | n | mean | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| `part.rebuildAll` | 18 | 13.5 ms | 25.4 ms | 25.9 ms |
| `kernel.feature` | 60 | 1.17 ms | 1.24 ms | 1.61 ms |
| `kernel.feature.extrude` | 60 | 1.17 ms | 1.24 ms | 1.60 ms |

`app.rebuildPart` (axis = feature count): N = 3, k = 1.71, R² = 0.9608,
**95 % CI [1.04, 2.39]**.

**The interval spans linear to quadratic; the two cannot be distinguished from
three points.** Per rule 3 of §1.5 no scaling claim is made. The measured values
are 3.78 ms (1 feature), 40.8 ms (3), 75.2 ms (6).

Composition of the 6-feature rebuild (3 forced passes, 18 feature computations):

| Component | n | total | mean | share |
| --- | ---: | ---: | ---: | ---: |
| `part.rebuildAll` | 3 | 75.2 ms | 25.1 ms | 100 % |
| `ffi.occt.fuse` | 15 | 45.9 ms | 3.06 ms | **61 %** |
| `kernel.feature` | 18 | 20.6 ms | 1.14 ms | 27 % |
| `ffi.occt.meshCreate` | 33 | 12.5 ms | 0.378 ms | 17 % |
| `ffi.occt.extrudeProfileArcs` | 18 | 6.75 ms | 0.375 ms | 9 % |

Exact counters: `part.rebuild.passes` = 3, `kernel.feature.ok` = 18,
`meshCopyOut.tris` = 4620.

**The boolean fold accounts for 61 % of a rebuild.** Construction alone
(`ramp.build`) is linear — N = 9, k = 0.99, R² = 0.9994, CI [0.97, 1.01] —
which localises any superlinearity to the accumulating boolean rather than to
feature construction. Holding N solids simultaneously (`ramp.solids`) is also
linear: N = 7, k = 0.99, R² = 0.9999, CI [0.98, 1.00].

**Verdict: WATCH.** 25 ms for six features is acceptable; the growth law is
undetermined and must be measured at higher feature counts before any claim.

---

## 7. Results — display path

### 7.1 Scene preparation (Dart side)

| Operation | n | mean | class |
| --- | ---: | ---: | --- |
| `app.buildScenePayload` | 60 | 0.0157 ms | resolved |
| `app.sceneSignature` | 360 | 0.0007 ms | marginal |
| `app.buildOverlaysPayload` | 10 | 0.0010 ms | marginal |
| `3d.push` | 2 | 0.0915 ms | resolved |
| `app.sceneRevs` | 120 | **< 1 µs** | **unresolved** |

**Verdict: SMOOTH.** Everything Dart does to prepare a scene is at or below
the instrument’s floor. The signature check that decides whether to push at
all is itself unmeasurably cheap.

### 7.2 Beyond the platform-view boundary (native RealityKit)

Measured in `RvPerf.swift` and **pulled** by Dart rather than pushed, so no
channel round-trip is included in the measurement. All values n = 1 — single
observations, reported as such, with no dispersion implied.

| Phase | ms (n = 1) | share |
| --- | ---: | ---: |
| `rv.native.setScene` | 33.5 | 100 % |
| ├─ **`rv.native.planes`** | **33.4** | **99.6 %** |
| ├─ `rv.native.sketches` | 0.08 | 0.2 % |
| ├─ `rv.native.solids` | **0.04** | 0.1 % |
| ├─ `rv.native.setCamera` | 0.08 | — |
| ├─ `rv.native.placeCamera` | 0.02 | — |
| ├─ `rv.native.setOverlays` | 0.02 | — |
| ├─ `rv.native.accents` | < 1 µs | unresolved |
| └─ `rv.native.highlight` | < 1 µs | unresolved |

Dart-side, same single push: `rv.setScene` 35.7 ms, `rv.setOverlays` 35.7 ms,
`rv.setCamera` 35.1 ms.

**Mesh upload costs 0.04 ms; the three origin planes cost 33.4 ms — 99.6 % of
the push.** The intuitive expectation, that scene push is dominated by
geometry, is contradicted. This was not falsifiable at all before the native
drain existed. The measurement is first-call cost (RealityKit entity and
material construction, n = 1) and cannot be generalised to steady state.

Previous run (`9bfe397`) measured 55.4 ms for the same phase; both runs were
under Low Power Mode, so the comparison is directional only.

**Verdict: WATCH** — small and non-recurring, but it is the entire cost of
first displaying a part.

### 7.3 Projection and 3D picking

| Operation | n | mean | p95 | max |
| --- | ---: | ---: | ---: | ---: |
| `project.partEdges` | 60 | 0.157 ms | 0.507 ms | 1.53 ms |
| `app.partEdges` | 60 | 0.158 ms | 0.507 ms | 1.53 ms |
| `app.pickEdge3d` | 180 | 0.0232 ms | 0.056 ms | 0.152 ms |
| `app.meshSelfReport` | 6 | 0.125 ms | — | — |
| `app.meshAnomalies` | 6 | < 1 µs | — | **unresolved** |

**Verdict: SMOOTH.** Projection was a named stress case in M76/M77 and is
excluded by these measurements — conditional on `allEdges` not lying on its
path.

---

## 8. Results — provenance, patterns, documents, shell, memory

### 8.1 Face provenance (M213)

Rebuild path — executes once per feature on every rebuild
(`part_model.dart:6988–6990`); twice for a body-modifying feature.

| Profile pts | Triangles | Faces | `faceSurfaces` | `newSurfacesOf` |
| ---: | ---: | ---: | ---: | ---: |
| 24 | 92 | 26 | 0.009 ms | 0.005 ms |
| 120 | 476 | 122 | 0.046 ms | 0.093 ms |
| 360 | 1436 | 362 | 0.139 ms | **0.721 ms** |

| Function | N | *k* | R² | 95 % CI |
| --- | ---: | ---: | ---: | ---: |
| `faceSurfaces` | 3 | **1.01** | 1.0000 | [1.00, 1.02] |
| `newSurfacesOf` | 3 | **1.85** | 1.0000 | [1.84, 1.86] |

Session: `faceSurfaces` n = 60, mean 0.0673 ms; `newSurfacesOf` n = 60,
mean 0.272 ms, p95 0.722 ms.

`faceSurfaces` is linear to within ±2 %, as predicted from a single pass over
triangles. **`newSurfacesOf` is confirmed near-quadratic with an exceptionally
tight interval** — predicted from source (`base.any(...)` nested in a loop over
`result`, `part_model.dart:3701`) *before* measurement, and confirmed: face
count ×13.9 produced time ×144.

Pick path — `attributeFaces`, cached per mesh identity
(`app_state.dart:4859`):

| Features | mean | faces attributed |
| ---: | ---: | ---: |
| 2 | 0.172 ms | 62 |
| 6 | 0.285 ms | 62 |
| 12 | 0.577 ms | 62 |

N = 3, k = 0.65, R² = 0.9502, **95 % CI [0.36, 0.95]**. The interval lies
entirely below 1: growth is **sublinear** in feature count.

**This refutes the pre-measurement hypothesis.** The function is structurally a
triple loop (faces × features × surfaces-per-feature) and was predicted to
scale as a product. It does not: the `break` after the first surface match
truncates the inner loop. Recorded as a refuted prediction rather than
omitted. **Verdict: SMOOTH.**

*Structural note not captured by timing:* `featureOfFace` invokes
`faceSurfaces(solid.mesh)` a second time solely to obtain a count for a log
line (`app_state.dart:4864`), immediately after `attributeFaces` computed the
same decomposition internally. It lies behind the cache, so it executes once
per mesh identity rather than per frame.

### 8.2 Part patterns (M212/M213)

| Kind | n | mean per call | occurrences | fit |
| --- | ---: | ---: | ---: | --- |
| rectangular | 120 | 0.0015 ms | 15 | k = 0.93, slope only |
| circular | 120 | 0.0122 ms | 15 | k = 1.35 [0.98, 1.72] |
| sketch-driven | 120 | 0.0014 ms | 16 | k = 1.05, slope only |
| along-a-curve | 40 | 0.0213 ms | 15 | single size |
| mirror | 40 | **< 1 µs** | 1 | constant by construction |

`app.patternPreview` (2D sketch pattern, redrawn each frame while its dialog
is open): n = 200, mean 0.0195 ms.

**Verdict: SMOOTH throughout.** The largest pattern cost measured is 0.0213 ms.
The along-a-curve variant costs ≈ 14× the straight case and remains 21 µs.
**The cost of a part pattern therefore lies entirely in the kernel** — which is
precisely what the mirror scenario was constructed to establish, and
`kernel.mirror` (§6.6) quantifies the part that is not free.

*Behavioural contract, pinned by test:* a pattern of count *n* yields *n − 1*
placements; the identity placement is discarded (`part_model.dart:3370`)
because it **is** the original feature.

### 8.3 Documents, history, serialisation

| Operation | n | mean | max |
| --- | ---: | ---: | ---: |
| `io.savePart` (including disk) | 1 | 21.1 ms | — |
| `app.sketch.encodeCons` | 40 | 0.269 ms | 0.413 ms |
| `app.sketch.decodeCons` | 40 | 0.173 ms | 0.342 ms |
| `app.part.toJson` | 40 | 0.0083 ms | 0.015 ms |
| `app.checkpoint` (undo snapshot) | 120 | 0.144 ms | 0.613 ms |
| `app.undoStep` / `app.redoStep` | 120 | **< 1 µs** | **unresolved** |
| `ffi.qcad.allGeometry` | 32 | 0.0661 ms | 0.180 ms |
| `ffi.qcad.addLine` | 762 | 0.0034 ms | 0.179 ms |
| `ffi.qcad.addCircle` | 761 | 0.0032 ms | 0.049 ms |
| `app.engineFill` | 20 | 0.508 ms | 0.823 ms |

`app.history`: N = 3, k = 0.82, R² = 0.9900, CI [0.66, 0.98] — sublinear.

**Verdict: SMOOTH.** Disk I/O is deliberately excluded from the sweeps: its
wall time is governed by iOS storage pressure and is not addressable in this
code, so including it would manufacture regressions with no cause. The single
observed real `savePart` took 21.1 ms in total.

`ffi.qcad.allGeometry` merits a note: it is structurally 1 + 3n boundary
crossings plus a per-entity allocation pair, and was flagged as a concern
before measurement. At 0.0661 ms for a whole-document read it is excluded.

### 8.4 UI shell

Exact counters for the entire session:

| Signal | Value |
| --- | ---: |
| `menu.ribbon.builds` | **1** |
| `toolbar.setItems.calls` / `rows.hit` / `rows.miss` | 2 / 1 / 2 |
| `tabbar.setTabs.calls` / `rows.miss` | 2 / 2 |
| `browser.setRows.calls` / `rows.hit` / `rows.miss` | 1 / 1 / 1 |
| `rv.setScene` / `setOverlays` / `setCamera` calls | 1 / 1 / 1 |

**Verdict: SMOOTH.** The ribbon was constructed **once** in the whole session.
For the ribbon the informative quantity was never duration (microseconds) but
frequency — a ribbon rebuilding during a drag would have been a genuine
finding. It does not. These are exact counts and carry no timing uncertainty.

### 8.5 Memory

| Measure | Value |
| --- | ---: |
| RSS | 313 MB (peak 313 MB, max 323 MB) |
| `phys_footprint` | 1372 → 1234 MB |
| `os_proc_available_memory` | 3747 → 3885 MB |
| Physical memory | 7374 MB |
| **Per solid** | **2 KB** |
| **Per triangle** | **14 bytes** |

Two observations:

* **The footprint-to-RSS ratio is ≈ 4** (1234 MB against 313 MB). This is
  plausible for RealityKit/Metal, where IOSurface and GPU allocations count
  toward footprint but not RSS, but the discrepancy is large enough that it
  requires independent corroboration before any decision rests on it. Open
  since `PERF_ANALYSIS.md` §13.8. **iOS terminates on footprint, not RSS**, so this
  is the operative number.
* **14 bytes per triangle** converts file-size questions into arithmetic: a
  100 000-triangle model is ≈ 1.4 MB of mesh.

Headroom in this run was ample (3.9 GB). The session that terminated during a
fillet reported 839 MB RSS; its footprint — the quantity that actually
triggered termination — was never captured, which is the reason the native
probe exists.

### 8.6 Frame budget

`quality.frameBudget` computes the largest sketch fitting one frame, using the
**two** solves per painted frame the painter actually performs (§5.2):

| Target | Maximum entities |
| --- | ---: |
| 120 Hz (8.3 ms) | **192** |
| 60 Hz (16.7 ms) | **256** |

Under Low Power Mode; the uncapped figures are correspondingly higher.

---

## 9. Threats to validity and unmeasured quantities

### 9.1 Structural gaps

1. **Interior of the C++ shim.** `edgeInfo` is established as Θ(shape) and the
   four responsible operations are identified by reading. No per-line profile
   exists. §6.5 bounds it from outside; from Dart nothing further is possible.
2. **RealityKit’s render loop.** `RvPerf` measures to hand-off only.
3. **No sampling profiler.** The suite attributes cost to *operations*; a
   profiler attributes it to *lines*. For `analyzeSketch` this is the
   difference between “rank reduction is cubic” and “this loop is”. Specified
   as Track A4 in `PERF_PLAN.md`; not built.
4. **`applyBlendOccurrence`** (patterned fillets) has no scenario.
5. **End-to-end rebuild of a `PatternFeature`** — `app.rebuildPart` drives
   extrusions only; a pattern additionally folds one boolean per occurrence,
   which is a different curve.
6. **Ribbon leaf widgets and dialogs.** Frequency matters more than duration
   here, and `menu.ribbon.builds` = 1 makes them uninteresting at present.
7. **Undo journal size.** Duration measured (`app.checkpoint`); retained
   memory not.

### 9.2 A defect in the apparatus

**Failure causes cannot reach the bundle.** `kernel.sweepTwist.fail` = 4, and
M216 added `lastError` logging expressly so the next run would report *why*.
It is absent, and the ordering explains it: `log.txt` terminates at 10:47:45
with “BUG REPORT REQUESTED”, while the suite executed at 10:48:10 — **25
seconds after the log was captured**. The diagnostic is written after the
snapshot intended to carry it and therefore can never appear. Any failure
cause belongs in the suite’s own JSON, which is written after the suite by
construction.

### 9.3 Conditions never yet observed

* **A run with Low Power Mode off.** Both recent device runs were capped.
  Every absolute figure here is ≈ 2× pessimistic for this device at full clock,
  and no clean best-case baseline exists. Note this is a gap in the *upper*
  bound only — §3.5 argues the capped run is the more useful of the two for
  the older-hardware question, so the correct remedy is to hold both, not to
  replace one with the other.
* **A memory-constrained device.** The unproxied axis (§3.5). This device had
  3.7–3.9 GB of headroom; the field crash was a `phys_footprint` kill. Nothing
  in this report constrains behaviour on a 3–4 GB iPad except the
  hardware-independent 14 bytes/triangle and 2 KB/solid.
* **The stress tier has never executed on a device.** It is green in CI and
  present in the build (type `stress` in the bug description to include it).
  Its ladders are the only instrument that measures where the application
  actually fails rather than extrapolating to it — and every failure figure in
  this document is therefore an extrapolation.
* **A 30-minute continuous session.** Scenario 18 of the catalogue, never run.
  It is the only one capable of detecting a leak, and a CAD session is an hour,
  not a click.

---

## 10. Complete cost-model table

All fitted families. Dependent variable: dominant span total. Ordered by
exponent. **N** is the number of distinct sizes; families with N = 2 provide a
slope with zero residual degrees of freedom and support no scaling claim.

| Family | N | *k* | R² | 95 % CI | Range (ms) | Status |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `modify.intersections` | 3 | 2.25 | 0.9979 | [2.05, 2.45] | 0.009–0.331 | quadratic |
| `analysis.sweep` | 3 | 2.24 | 0.9951 | [1.93, 2.55] | 0.204–21.8 | quadratic |
| `ramp.analyze` | 10 | **2.30** | 0.9908 | [2.15, 2.46] | 0.066–156 | **quadratic+, knee at 64** |
| `kernel.allEdges.sweep` | 3 | 1.93 | 0.9999 | [1.89, 1.97] | 13.7–1170 | quadratic |
| `ramp.allEdges` | 7 | **1.935** | 0.9998 | [1.910, 1.960] | 14.1–1709 | **quadratic** |
| `app.provenance.newSurfaces` | 3 | 1.85 | 1.0000 | [1.84, 1.86] | 0.048–7.21 | quadratic |
| `modify.trim` | 3 | 1.83 | 0.9996 | [1.76, 1.89] | 0.011–0.209 | superlinear |
| `ramp.density` | 6 | 1.79 | 0.9971 | [1.69, 1.88] | 0.452–18.3 | superlinear |
| `app.rebuildPart` | 3 | 1.71 | 0.9608 | [1.04, 2.39] | 3.78–75.2 | **indeterminate** |
| `tools.freehand` | 3 | 1.59 | 0.9956 | [1.38, 1.79] | 0.030–2.44 | superlinear |
| `solve.sweep` | 3 | 1.55 | 0.9971 | [1.39, 1.72] | 0.834–21.2 | superlinear |
| `app.pattern.occurrences.circular` | 3 | 1.35 | 0.9810 | [0.98, 1.72] | 0.020–0.850 | indeterminate |
| `ramp.solve` | 10 | 1.34 | 0.9498 | [1.13, 1.56] | 0.076–5.37 | superlinear |
| `tools.splineEval` | 3 | 1.30 | 0.9989 | [1.22, 1.39] | 1.61–59.4 | superlinear |
| `modify.transform` | 2 | 1.25 | — | slope only | 0.021–0.171 | no claim |
| `app.pattern.rect` | 3 | 1.17 | 0.9952 | [1.01, 1.33] | 0.046–1.17 | ≈ linear |
| `kernel.boolean.complex` | 3 | 1.09 | 0.9987 | [1.01, 1.17] | 8.07–99.9 | linear |
| `ramp.boolean` | 7 | 1.07 | 0.9974 | [1.03, 1.12] | 10.0–144 | linear |
| `kernel.sweep` | 2 | 1.06 | — | slope only | 89.9–392 | no claim |
| `app.pattern.occurrences.points` | 2 | 1.05 | — | slope only | 0.016–0.069 | no claim |
| `app.provenance.faceSurfaces` | 3 | 1.01 | 1.0000 | [1.00, 1.02] | 0.090–1.39 | linear |
| `kernel.mirror` | 2 | 1.00 | — | slope only | 8.86–44.4 | no claim |
| `kernel.extrude.arcs` | 3 | 1.00 | 1.0000 | [0.98, 1.01] | 0.722–7.15 | linear |
| `kernel.revolve` | 3 | 0.99 | 0.9999 | [0.98, 1.01] | 0.554–5.48 | linear |
| **`kernel.query.edgeInfoScale`** | 4 | **0.99** | 0.9999 | [0.97, 1.01] | 12.5–121 | **linear ⇒ Θ(shape) per call** |
| `ramp.build` | 9 | 0.99 | 0.9994 | [0.97, 1.01] | 0.787–17.9 | linear |
| `ramp.mesh` | 9 | 0.99 | 0.9992 | [0.97, 1.01] | 2.20–50.0 | linear |
| `ramp.solids` | 7 | 0.99 | 0.9999 | [0.98, 1.00] | 8.07–126 | linear |
| `kernel.mesh.complexity` | 3 | 0.96 | 0.9997 | [0.93, 1.00] | 1.39–12.9 | linear |
| `ramp.drag` | 8 | 0.96 | **0.6213** | [0.36, 1.55] | 0.570–14.9 | **no fit** |
| `ui.paint.sweep` | 3 | 0.93 | 0.9995 | [0.89, 0.98] | 0.936–6.55 | linear |
| `app.pattern.occurrences` | 2 | 0.93 | — | slope only | 0.017–0.062 | no claim |
| `constraints.infer` | 3 | 0.91 | 0.9928 | [0.76, 1.06] | 0.011–0.073 | linear |
| `gear.curve` | 3 | 0.85 | 0.9981 | [0.78, 0.92] | 5.91–19.2 | sublinear |
| `app.history` | 3 | 0.82 | 0.9900 | [0.66, 0.98] | 0.979–5.44 | sublinear |
| `app.engineFill` | 2 | 0.69 | — | slope only | 1.21–3.85 | no claim |
| `app.provenance.attribute` | 3 | 0.65 | 0.9502 | [0.36, 0.95] | 0.862–2.88 | sublinear |
| `kernel.coil` | 3 | 0.44 | 0.9513 | [0.25, 0.64] | 15.5–47.5 | sublinear |
| `kernel.loft` | 3 | 0.39 | 0.9905 | [0.32, 0.47] | 5.96–10.2 | sublinear |
| `kernel.fillet.edges` | 3 | −0.00 | **0.0025** | [−0.00, 0.00] | 49.3–49.5 | **independent of n** |
| `kernel.chamfer.edges` | 3 | −0.00 | 0.8770 | [−0.00, −0.00] | 49.1–49.5 | **independent of n** |

---

## 11. Hypotheses and outcomes

Predictions made before measurement, and how each resolved. Recorded whether
or not they were confirmed.

| # | Hypothesis | Outcome | Evidence |
| ---: | --- | --- | --- |
| 1 | One `edgeInfo` call is Θ(whole shape), making `allEdges` Θ(n²) | **Confirmed** | k = 0.99 [0.97, 1.01] on fixed work vs growing shape; 92 % closure against measured `allEdges` |
| 2 | `newSurfacesOf` is quadratic in face count | **Confirmed** | k = 1.85 [1.84, 1.86], R² = 1.0000 |
| 3 | `attributeFaces` scales as a product of faces × features × surfaces | **Refuted** | k = 0.65 [0.36, 0.95] — sublinear; the early `break` truncates the inner loop |
| 4 | FFI boundary crossing dominates tessellation cost | **Refuted** | `meshCreate` : `meshCopyOut` = 974 : 1 |
| 5 | Scene push is dominated by geometry upload | **Refuted** | origin planes 99.6 %, mesh upload 0.1 % |
| 6 | Ribbon rebuilds during interaction | **Refuted** | `menu.ribbon.builds` = 1 for the entire session |
| 7 | Gear generation is a crash suspect | **Refuted** | k = 0.85, 432× cache speed-up, ≈ 1 ms for four gears |
| 8 | Pattern arithmetic contributes materially | **Refuted** | all five kinds ≤ 0.0213 ms |
| 9 | Fillet cost scales with the number of edges filleted | **Refuted** | R² = 0.0025; cost independent of n, dominated by candidate search |
| 10 | The 3.92 s solver outlier is size-driven | **Refuted** | fast-path solve is 0.271 ms at any measured size; the outlier is the LM fallback (bimodal, 186×) |
| 11 | Low Power Mode is only a confound to be corrected away | **Refuted** | It is a uniform clock scalar (CV 8.3 %, memory-bound and compute-bound workloads within 0.5 % of each other) and therefore a usable proxy for slower hardware — §3.5 |

Eight of eleven predictions were refuted. This is the intended function of the
exercise: the measurements exist to overturn assumptions, and a suite that only
ever confirmed them would not be earning its cost.

---

## 12. Reproducibility across builds

Three device runs under differing conditions. Directional, not precise —
except where noted.

| Measure | `7fb7f8b` (6 Aug) | `9bfe397` (6 Aug) | `cd961ee` (11 Aug) |
| --- | ---: | ---: | ---: |
| Low Power Mode | **off** | **on** | **on** |
| `allEdges` @ 360 edges | 607 ms | 1171 ms | ≈ 1170 ms |
| **One `edgeInfo` @ 360 edges** | — | **3.014 ms** | **3.038 ms** |
| `analysis` @ 64 entities | 15.7 ms | 26.3 ms | 21.8 ms |
| `solve.sweep` @ 64 | 7.96 ms | 16.3 ms | 21.2 ms |
| `gear.curve` @ 20 teeth | 5.13 ms | 9.85 ms | 11.1 ms |
| `rv.native.setScene` | — | 55.4 ms | 33.5 ms |

**The `edgeInfo` measurement reproduces to 0.8 % across two builds five days
apart** (3.014 ms and 3.038 ms, independent runs, independent binaries). The
defect is stable and precisely reproducible, which is the property that makes
it safe to act on.

The LPM-off to LPM-on transition (columns 1 → 2) produced a uniform
1.67–2.05× slowdown across four unrelated subsystems, which is the empirical
basis for the ≈ 2× correction applied throughout this report (§1.7 confound 1).

---

*Source: `bug20260811T104745`, build `cd961ee`, iPadOS 27.0, single device.
All tables regenerable via `python3 ci/perf_report.py <bundle.zip>`; fit
statistics (R², CI) computed as specified in §1.5.*
