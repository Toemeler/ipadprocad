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

## 12. Longitudinal record — every device run of the suite

Four device runs exist. This section reports all of them, including the one
whose numbers are known-invalid, because a superseded measurement that is
quietly dropped cannot be re-examined when the reason for dropping it turns
out to be wrong.

| # | Bundle | Build | Date | LPM | Status |
| ---: | --- | --- | --- | --- | --- |
| 1 | `bug20260806T142003` | 389 | 6 Aug | unknown | **Partly invalid** — three broken fixtures (§12.1) |
| 2 | `bug20260806T155703` | `7fb7f8b` | 6 Aug | **off** | Valid; the only uncapped run |
| 3 | `bug20260806T234041` | `9bfe397` | 6 Aug | on | Valid |
| 4 | `bug20260811T104745` | `cd961ee` | 11 Aug | on | Valid; the basis of §1–§11 |

Runs 2 and 3 predate M220, so they contain no `edgeInfoScale`, no
`kernel.mirror`, no provenance and no part-pattern data — those scenarios did
not exist. Comparisons below are therefore restricted to measurements that all
the relevant runs share.

### 12.1 Run 1 (build 389) — what it measured, and what it did not

The first device execution of the self-driving suite. Its value was not its
numbers but the three fixture defects it exposed, each of which had been
producing a plausible small number rather than an obvious failure:

| Reported | Actual | Cause |
| --- | --- | --- |
| `gear.curve` = 0.000 ms (20 "calls" in 0.012 ms) | one generation, then 19 map lookups | `gearCurve` memoises on full geometric identity; a fixture is identical every time, and the warm-up pass had already filled the cache |
| `ent.dofColour` ≈ 0 | a sketch with 0.5 constraints per entity and **no analysis at all** | the colouring is guarded by `hasAnalysis &&`, short-circuited for every entity in every frame |
| `2d.snap` absent from the report entirely | the scenario called `setHover`, the *second* half of the pointer path | the snap itself lived in `_snapped`, unreachable except through a real gesture |
| `solve.*` 27 ms mean, **3.92 s worst** | real, but unexplained at the time | later identified as the LM fallback (§5.4), not a size effect |

**Invalidated by these defects:** all `solve.*`, all `gear.curve.*` and all
`ui.*` from this run. **Unaffected:** the kernel measurements, including the
first observation of the `allEdges` quadratic.

The 3.92 s solver outlier from this run remained unexplained for two further
runs and is now attributed: `solve.total` max of 178.7 ms against a p50 of
0.275 ms in run 3, while `ffi.slvs.solve` never exceeded 4.1 ms — an outlier
44× larger than anything the native solver ever took, therefore never in the
native solver.

### 12.2 Runs 2 → 4: every measurement the runs share

**2D — painter and pointer** (ms):

| Measurement | Run 2 `7fb7f8b` | Run 3 `9bfe397` | Run 4 `cd961ee` |
| --- | ---: | ---: | ---: |
| `2d.snap` per pointer move | 0.0044 | — | 0.0079 |
| `2d.pickEntity` per pointer move | 0.0234 | — | 0.0899 |
| `2d.displayGeometry` during drag | 0.1412 | — | 0.2746 |
| `ent.dofColour` static (128 entities) | 0.0008 (0.7 %) | — | 0.0010 (0.5 %) |
| `ent.dofColour` during drag | 0.1414 (43.3 %) | 43.6 % | 0.2748 (43.2 %) |
| `constraints` phase, static | 0.0011 | — | 0.0022 |
| `constraints` phase, during drag | 0.1426 | 43.5 % | 0.2772 |
| Solves per 60 painted frames | **120** | **120** | **120** |

The solves-per-frame count is **exactly 120 in all three runs** — an exact
counter, unaffected by clock, confirming the double `displayGeometry` is
structural rather than incidental.

**Constraint solver** (ms):

| Measurement | Run 2 | Run 3 | Run 4 |
| --- | ---: | ---: | ---: |
| `ffi.slvs.solve`, 128 ent / 193 cons | 0.725 | — | — |
| `ffi.slvs.solve`, drag, 48 entities | 0.114 | — | 0.2202 |
| Session `solve` mean / p95 | 0.169 / 0.148 | — | 2.5744 / 0.279 |
| `solve.drag60` per solve | — | 0.274 | 0.2711 |
| Share in libslvs, normal drag | — | 81 % | 81 % |
| `solve.sweep.64` (128 ent) per solve | — | 1.631 | — |
| **Over-constrained per solve** | — | **92.538** | **66.352** |
| Share in libslvs, over-constrained | — | **0.4 %** | **0.34 %** |
| Ratio over-constrained : normal | — | **334×** | **245×** |
| `solve.total` max | 3920 (run 1) | 178.7 | 66.9 |

The over-constrained ratio differs between runs 3 and 4 (334× vs 245×) because
the fixtures differ, not because the mechanism does: the *share* executed in
libslvs is 0.4 % and 0.34 % — agreeing to within a third of a percentage point
across two builds. The mechanism is stable; its magnitude depends on how far
the system is from satisfiable.

**Sketch analysis** (`sketch.analyze`, ms):

| Entities | Constraints | DOF | Run 2 | Run 3 | Run 4 (ramp) |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 16 | 25 | 14 | 0.101 | — | 0.206 |
| 48 | 73 | 46 | 0.934 | — | 1.791 |
| 64 | — | — | — | 26.27 | 5.800 |
| 128 | 193 | 126 | **15.694** | — | 22.562 |
| 256 | — | — | — | — | **156.069** |
| Fitted exponent | | | 2.04 → 2.88 | 2.33 | **2.30** [2.15, 2.46] |

Three independent determinations of the exponent — 2.04–2.88, 2.33, 2.30 —
from three builds. The quantity is reproducible; the run-4 confidence interval
is the first one with enough points to bound it.

**Topology queries — `allEdges`** (ms, and µs per edge):

| Edges | Run 2 | µs/edge | Run 3 | µs/edge | Run 4 | µs/edge |
| ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 36 | 7.00 | 194 | — | — | 14.12 | 392 |
| 144 | 99.66 | 692 | — | — | 195.94 | 1361 |
| 360 | **607.13** | 1687 | **1171.01** | 3253 | ~1170 | 3249 |
| Fitted exponent | 1.92 / 1.97 | | 1.93 | | **1.935** [1.910, 1.960] | |
| One `edgeInfo` @ 360 | — | | **3.014** | | **3.038** | |
| Share explained by per-call cost | — | | 92.7 % | | 91.9 % | |
| `counts()` on same solid | — | | 0.205 | | 0.2061 | |
| `bbox()` on same solid | — | | 0.166 | | 0.1651 | |
| `allEdges.repeat` (5× same solid) | 99.4 | | — | | — | |

**This is the most reproducible finding in the entire branch.** The exponent
lands at 1.92, 1.97, 1.93 and 1.935 across three builds; a single `edgeInfo`
on a 360-edge solid measures 3.014 ms and 3.038 ms on two different builds
five days apart (**0.8 % apart**); the control queries agree to three decimal
places. `allEdges.repeat` staying flat at 99.4 ms over five calls on the same
solid establishes there is no reusable setup — the cost is rebuilt per call.

**Fillet and chamfer** (ms):

| Measurement | Run 2 | Run 3 | Run 4 |
| --- | ---: | ---: | ---: |
| Candidate search (`allEdges`) | 25.56 | 49.79 | 49.31 |
| Rounding (`filletEdges`), 1 edge | 10.80 | 10.17 | 10.10 |
| **Search : rounding ratio, 1 edge** | **2.4×** | **4.9×** | **4.9×** |
| `filletEdges`, 4 edges | — | 20.76 | 20.76 |
| `filletEdges`, 12 edges | — | 47.07 | 46.66 |
| `filletEdges` max (large radius) | — | 664 | 657.7 |
| Radius sensitivity r=1 → r=4 | — | **66×** | **65×** |
| `filletMaxRadius` : `filletInventor` | — | 46.4× | 46.4× |

Runs 3 and 4 agree to within 1 % on every fillet quantity. Run 2's lower
search cost reflects a smaller fixture solid, not a different behaviour.

**Display path and kernel throughput** (ms):

| Measurement | Run 2 | Run 3 | Run 4 |
| --- | ---: | ---: | ---: |
| `rv.setScene` (Dart side) | — | 61.76 | 35.73 |
| `rv.native.setScene` | — | 55.44 | 33.51 |
| └ `rv.native.planes` | — | 55.24 (99.6 %) | 33.36 (99.6 %) |
| └ `rv.native.sketches` | — | 0.12 | 0.08 |
| └ `rv.native.solids` | — | **0.06** | **0.04** |
| `ffi.occt.sweepProfile` mean | — | 164 | 159.8 |
| `sweepProfile`, 48-pt profile | — | 419 | 395.9 |
| `constraints.add.dimension` | — | 44.7 | 44.2 |
| `launch.toFirstFrame` | **76.6** | — | 171.2 |
| Session frames / fps / jank | 807 / 93.5 / 2 | — | 304 / 39.0 / 162 |

**The origin-plane share is 99.6 % in both runs that measured it** — identical
to three significant figures across a 40 % change in absolute cost.

The frame statistics differ enormously between runs 2 and 4 (93.5 fps vs
39.0 fps). This is **not** a regression: run 2's suite was 21 scenarios, run
4's was 167 including the ramps, so run 4's session is dominated by
synchronous kernel work on the UI thread (§3.4). The comparison is not
meaningful and is shown only to prevent someone else drawing it.

**Memory**:

| Measurement | Run 3 | Run 4 |
| --- | ---: | ---: |
| `footprintMB` pre → post | 1397 → 1232 | 1372 → 1234 |
| `residentMB` pre → post | 241 → 284 | 234 → 323 |
| Footprint : RSS ratio | ≈ 5 | ≈ 4 |

The footprint/RSS discrepancy reproduces across both runs that measured it,
which strengthens the case that it is real rather than a probe artefact —
though it still does not explain it (§8.5).

### 12.3 Cross-run scaling of the Low Power Mode effect

Runs 2 → 3 are the only LPM-off → LPM-on pair, and the basis for the ≈ 1.89×
correction used throughout this report. See §3.5 for the full analysis; the
summary is that the effect is uniform (CV 8.3 %) across memory-bound and
compute-bound workloads alike, making it a clock scalar and therefore a usable
proxy for slower hardware.

### 12.4 What the longitudinal record establishes

1. **The `allEdges` defect is stable across three builds and two device
   states.** Exponent 1.92–1.935, per-call cost reproducing to 0.8 %. It is
   safe to work on: any change will show against a well-characterised baseline.
2. **Exact counters reproduce perfectly where timings do not.** 120 solves per
   60 frames in all three runs; 99.6 % origin-plane share in both; edge counts
   exact everywhere. This is the empirical case for §1.1's rule that a counter
   is stronger evidence than a duration.
3. **The solver mechanism is stable, its magnitude is not.** 0.4 % and 0.34 %
   of time in libslvs when over-constrained, across two builds — but 334× and
   245× end-to-end, because that depends on the fixture's distance from
   satisfiability. Quote the share, not the ratio.
4. **One run's numbers were partly fiction and it took a dedicated coverage
   test to find out.** Run 1 reported three plausible small numbers that were
   measurements of nothing. Everything since asserts that a scenario reached
   its subject before believing its timing.

---

## 13. Track B — the iOS Simulator

### 13.1 Why this section was empty for the whole branch

`sim-perf.yml` builds the entire native stack for `iphonesimulator/x86_64`,
builds the Flutter app against it, boots an iPad simulator, runs the app and
retrieves `performance_logs.txt` and `performance_snapshot.json` from the data
container. It has been green since run 32 (6 Aug).

**Not one of its numbers had ever been read.** The measurement worked; the
*delivery* did not. GitHub artifacts are served from Azure blob storage, which
the agent proxy refuses (HTTP 403 on the CONNECT tunnel), so the capture was
reachable only by a human downloading a zip. Item 1 of `PERF_ANALYSIS.md` §7 —
"run sim-perf once, pull `perf-capture`" — had therefore stood open since M215
while the job that satisfies it ran green a dozen times.

This is worth recording as a methodological failure in its own right: **a
measurement with no delivery path is not a measurement.** It is the same class
of defect as §9.2, where a diagnostic is written 25 seconds after the snapshot
meant to carry it.

### 13.2 The fix

The workflow now publishes its capture to a **`ci-logs-perf` branch** as well
as an artifact, reusing the pattern the repository already uses for
`ci-debug-logs-dart`, `-m3` and `-m5`. The files are small (one text log and
two JSON), so a branch is a cheap and durable channel, and git is reachable
from every environment that needs to read them. A `RUN.txt` stamps run id,
commit and timestamp, because two simulator captures are otherwise
indistinguishable.

### 13.3 What these numbers may and may not be used for

Established in `PERF_ANALYSIS.md` §6a and unchanged. Flutter refuses
`--profile` and `--release` for the simulator, so the engine is JIT/debug:

| Legitimate to read | **Not** legitimate to read |
| --- | --- |
| `ffi.occt.*`, `ffi.slvs.*`, `ffi.qcad.*` **relative to each other** | fps, `frame.build`, `frame.raster`, jank |
| **All counters** — call counts, entity counts, solves per frame, cache hit rates | absolute milliseconds as iPad milliseconds |
| Structural regressions ("does it now call this twice as often?") | anything about rendering |

The native half is built `-DCMAKE_BUILD_TYPE=Release`, exactly as for the
device, so kernel *ratios* transfer. The Dart half is unoptimised and its
frame times are meaningless. Quoting a simulator millisecond as an iPad
millisecond repeats the M75 error in new clothing.

A second, structural caveat specific to this track: the whole stack runs
**x86_64 under Rosetta** on an arm64 runner, because the Qt-for-iOS package
ships only an x86_64 simulator slice. So this is not merely a different clock
from the device — it is a different instruction set, executed under binary
translation. Relative kernel costs survive that; nothing else reliably does.

### 13.4 Status

**Open.** The delivery mechanism is built and pushed; the first capture it
produces has not yet landed at the time of writing. When `ci-logs-perf`
carries a capture, this section is to be filled with the native-kernel ratios
and the counter comparison against §5–§8, and the corresponding item in §9.3
closed.

---

## 14. Complete data appendix

Sections 1–12 are analysis: they select, rank and interpret. Selection is
where bias enters — the spans nobody printed are the spans nobody questioned —
so this appendix prints **everything the bundle contains**, unranked and
untruncated: 273 spans, 59 counters, 298 gauges and 167 scenario executions.

It is **generated, not transcribed**:

```
python3 ci/perf_profile.py <bundle.zip> --label "..." 
```

Regenerating it after the next device run is one command. Every table in
sections 1–12 can be audited against the corresponding row here, and any
number in this report that does not appear below is either derived (a ratio,
a share, a fitted exponent) or an error.

<!-- BEGIN GENERATED APPENDIX — do not edit by hand; regenerate with ci/perf_profile.py -->

<!-- generated by ci/perf_profile.py from aa715102-bug20260811T104745.zip -->

Source bundle `aa715102-bug20260811T104745.zip`, build `cd961ee`, captured 2026-08-11T10:48:11.247294 — device, iPadOS 27.0, Low Power Mode on.

Every number below is printed verbatim from the bundle. Nothing is selected, ranked away or rounded beyond the instrument's resolution.

### A. Complete span inventory

Complete inventory: **273 spans**, session scope (includes the warm-up pass). Resolution classes: **239 resolved**, 12 marginal, **22 unresolved** (mean below the 1 µs quantization floor — printed as `< 1 µs`, never as digits).

**Two different windows in one row.** `n`, `total` and `mean` cover every observation. `p50`, `p95` and `max` are computed over a **128-sample ring buffer** (`perf.dart:41`), i.e. the most recent ≤128 observations only. Where a span ran more than 128 times under changing conditions the two disagree legitimately — `2d.paint` has a mean of 0.3362 ms and a p50 of 0.6400 ms because its last 128 paints were drag frames while the earlier ones were static. Neither figure is wrong; they answer different questions, and comparing them across spans without noticing the window is an error.

#### 2D kernel — qcad entry points

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `ffi.qcad.addLine` | 762 | 2.61 | 0.0034 | 0.0030 | 0.0060 | 0.1790 | resolved |
| `ffi.qcad.addCircle` | 761 | 2.43 | 0.0032 | 0.0030 | 0.0050 | 0.0490 | resolved |
| `ffi.qcad.allGeometry` | 32 | 2.11 | 0.0661 | 0.0320 | 0.1720 | 0.1800 | resolved |

#### 2D — interaction

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `2d.displayGeometry` | 240 | 67.70 | 0.2821 | 0.2740 | 0.2820 | 1.274 | resolved |
| `2d.pickEntity` | 480 | 43.16 | 0.0899 | 0.1270 | 0.1400 | 0.2800 | resolved |
| `2d.snap` | 240 | 1.90 | 0.0079 | 0.0090 | 0.0100 | 0.0120 | resolved |

#### 2D — painter phases

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `2d.paint` | 300 | 100.86 | 0.3362 | 0.6400 | 0.6680 | 2.735 | resolved |
| `2d.paint.constraints` | 300 | 34.78 | 0.1159 | 0.2780 | 0.2930 | 1.276 | resolved |
| `2d.paint.ent.dofColour` | 300 | 33.62 | 0.1121 | 0.2780 | 0.2910 | 0.4150 | resolved |
| `2d.paint.entities` | 300 | 31.42 | 0.1047 | 0.0800 | 0.2110 | 2.728 | resolved |
| `2d.paint.editRef` | 300 | 0.35 | 0.0012 | 0.0010 | 0.0020 | 0.0040 | resolved |
| `2d.paint.z` | 300 | 0.25 | 0.0008 | 0.0010 | 0.0010 | 0.0040 | resolved |
| `2d.paint.ent.halo` | 300 | 0.10 | 0.0003 | < 1 µs | 0.0010 | 0.0020 | resolved |
| `2d.paint.gearGhost` | 300 | 0.04 | 0.0001 | < 1 µs | 0.0010 | 0.0010 | marginal |
| `2d.paint.freehand` | 300 | 0.03 | 0.0001 | < 1 µs | 0.0010 | 0.0010 | marginal |
| `2d.paint.boxSelect` | 300 | 0.03 | 0.0001 | < 1 µs | 0.0010 | 0.0050 | marginal |
| `2d.paint.snap` | 300 | 0.03 | 0.0001 | < 1 µs | 0.0010 | 0.0010 | marginal |
| `2d.paint.bg` | 300 | 0.03 | 0.0001 | < 1 µs | < 1 µs | 0.0210 | marginal |
| `2d.paint.cursorHints` | 300 | 0.02 | 0.0001 | < 1 µs | 0.0010 | 0.0010 | marginal |
| `2d.paint.modifyGhost` | 300 | 0.02 | 0.0001 | < 1 µs | 0.0010 | 0.0010 | marginal |
| `2d.paint.pattern` | 300 | 0.02 | 0.0001 | < 1 µs | 0.0010 | 0.0010 | marginal |
| `2d.paint.notice` | 300 | 0.02 | 0.0001 | < 1 µs | 0.0010 | 0.0010 | marginal |
| `2d.paint.toolPreview` | 300 | 0.02 | 0.0001 | < 1 µs | < 1 µs | 0.0010 | marginal |
| `2d.paint.ent.projectEdges` | 300 | 0.02 | 0.0001 | < 1 µs | 0.0010 | 0.0010 | marginal |
| `2d.paint.ent.images` | 300 | 0.01 | < 1 µs | < 1 µs | 0.0010 | 0.0010 | unresolved |
| `2d.paint.slice` | 300 | 0.00 | < 1 µs | < 1 µs | < 1 µs | 0.0010 | unresolved |

#### 3D kernel — OCCT entry points

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `ffi.occt.allEdges` | 50 | 12163.32 | 243.3 | 49.95 | 1171.5 | 1701.8 | resolved |
| `ffi.occt.sweepProfile` | 16 | 2556.38 | 159.8 | 176.7 | 394.1 | 395.9 | resolved |
| `ffi.occt.extrudeProfileArcs` | 410 | 1606.73 | 3.919 | 2.796 | 7.236 | 66.21 | resolved |
| `ffi.occt.filletEdges` | 14 | 1606.19 | 114.7 | 20.94 | 655.6 | 657.7 | resolved |
| `ffi.occt.meshCreate` | 302 | 1352.88 | 4.480 | 0.4340 | 6.565 | 41.60 | resolved |
| `ffi.occt.fuse` | 90 | 1280.21 | 14.22 | 4.596 | 76.03 | 126.5 | resolved |
| `ffi.occt.cut` | 16 | 277.15 | 17.32 | 2.091 | 90.21 | 90.89 | resolved |
| `ffi.occt.common` | 16 | 265.15 | 16.57 | 2.011 | 86.77 | 87.07 | resolved |
| `ffi.occt.coilProfile` | 6 | 173.95 | 28.99 | 23.80 | 47.50 | 47.50 | resolved |
| `ffi.occt.chamferEdges` | 6 | 151.43 | 25.24 | 19.43 | 46.22 | 46.22 | resolved |
| `ffi.occt.loftSections` | 10 | 137.95 | 13.79 | 8.927 | 35.64 | 35.64 | resolved |
| `ffi.occt.mirror` | 40 | 106.81 | 2.670 | 4.422 | 4.522 | 4.559 | resolved |
| `ffi.occt.transform` | 140 | 60.23 | 0.4302 | 0.2920 | 1.485 | 1.493 | resolved |
| `ffi.occt.revolveProfile` | 12 | 35.38 | 2.948 | 3.611 | 5.478 | 5.542 | resolved |
| `ffi.occt.rayHits` | 120 | 29.13 | 0.2427 | 0.2330 | 0.2410 | 1.235 | resolved |
| `ffi.occt.extrudeProfile` | 12 | 11.14 | 0.9287 | 0.9700 | 1.755 | 1.823 | resolved |
| `ffi.occt.unify` | 44 | 3.55 | 0.0808 | 0.0780 | 0.0950 | 0.1410 | resolved |
| `ffi.occt.makeBox` | 9 | 1.48 | 0.1642 | 0.0260 | 1.273 | 1.273 | resolved |
| `ffi.occt.meshCopyOut` | 302 | 1.39 | 0.0046 | 0.0020 | 0.0080 | 0.1970 | resolved |
| `ffi.occt.makeCylinder` | 18 | 0.17 | 0.0097 | 0.0090 | 0.0150 | 0.0210 | resolved |

#### 3D kernel — scenarios

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `kernel.edgeInfoScale.240` | 40 | 242.92 | 6.073 | 6.059 | 6.172 | 6.255 | resolved |
| `kernel.edgeInfoScale.120` | 40 | 121.53 | 3.038 | 3.036 | 3.063 | 3.092 | resolved |
| `kernel.edgeInfo1` | 40 | 119.65 | 2.991 | 2.987 | 3.016 | 3.112 | resolved |
| `kernel.feature` | 60 | 70.23 | 1.170 | 1.154 | 1.237 | 1.606 | resolved |
| `kernel.feature.extrude` | 60 | 70.20 | 1.170 | 1.154 | 1.236 | 1.604 | resolved |
| `kernel.edgeInfoScale.60` | 40 | 60.32 | 1.508 | 1.503 | 1.535 | 1.585 | resolved |
| `kernel.rayHit` | 120 | 29.18 | 0.2431 | 0.2340 | 0.2420 | 1.237 | resolved |
| `kernel.edgeInfoScale.24` | 40 | 25.01 | 0.6252 | 0.6240 | 0.6330 | 0.6550 | resolved |
| `kernel.counts` | 40 | 8.21 | 0.2052 | 0.2030 | 0.2140 | 0.2190 | resolved |
| `kernel.bbox` | 40 | 6.61 | 0.1651 | 0.1650 | 0.1670 | 0.1680 | resolved |

#### 3D — face provenance

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `provenance.newSurfaces` | 60 | 16.33 | 0.2721 | 0.0930 | 0.7220 | 0.7270 | resolved |
| `provenance.attributeFaces` | 30 | 10.04 | 0.3347 | 0.2870 | 0.5910 | 0.5970 | resolved |
| `provenance.faceSurfaces` | 60 | 4.04 | 0.0673 | 0.0460 | 0.1430 | 0.2820 | resolved |

#### 3D — feature rebuild

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `part.rebuildAll` | 18 | 243.53 | 13.53 | 13.71 | 25.43 | 25.90 | resolved |

#### 3D — scene push

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `3d.push` | 2 | 0.18 | 0.0915 | 0.1830 | 0.1830 | 0.1830 | resolved |
| `3d.payload` | 1 | 0.03 | 0.0310 | 0.0310 | 0.0310 | 0.0310 | resolved |

#### Application paths

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `app.checkpoint` | 120 | 17.24 | 0.1437 | 0.1040 | 0.2770 | 0.6130 | resolved |
| `app.sketch.encodeCons` | 40 | 10.77 | 0.2692 | 0.2650 | 0.2740 | 0.4130 | resolved |
| `app.engineFill` | 20 | 10.17 | 0.5083 | 0.7380 | 0.7910 | 0.8230 | resolved |
| `app.partEdges` | 60 | 9.45 | 0.1575 | 0.0480 | 0.5070 | 1.531 | resolved |
| `app.sketch.decodeCons` | 40 | 6.90 | 0.1726 | 0.1680 | 0.1720 | 0.3420 | resolved |
| `app.pickEdge3d` | 180 | 4.18 | 0.0232 | 0.0120 | 0.0560 | 0.1520 | resolved |
| `app.patternPreview` | 200 | 3.89 | 0.0195 | 0.0210 | 0.0590 | 0.0610 | resolved |
| `app.buildScenePayload` | 60 | 0.94 | 0.0157 | 0.0090 | 0.0140 | 0.3030 | resolved |
| `app.meshSelfReport` | 6 | 0.75 | 0.1253 | 0.1240 | 0.1450 | 0.1450 | resolved |
| `app.part.toJson` | 40 | 0.33 | 0.0083 | 0.0080 | 0.0090 | 0.0150 | resolved |
| `app.sceneSignature` | 360 | 0.27 | 0.0007 | 0.0010 | 0.0010 | 0.0060 | resolved |
| `app.buildOverlaysPayload` | 60 | 0.06 | 0.0010 | 0.0010 | 0.0010 | 0.0020 | resolved |
| `app.meshAnomalies` | 6 | 0.00 | < 1 µs | < 1 µs | 0.0010 | 0.0010 | unresolved |
| `app.redoStep` | 120 | 0.00 | < 1 µs | < 1 µs | < 1 µs | < 1 µs | unresolved |
| `app.sceneRevs` | 120 | 0.00 | < 1 µs | < 1 µs | < 1 µs | < 1 µs | unresolved |
| `app.undoStep` | 120 | 0.00 | < 1 µs | < 1 µs | < 1 µs | < 1 µs | unresolved |

#### Constraint solver

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `solve.total` | 726 | 1869.00 | 2.574 | 0.2710 | 0.2790 | 66.95 | resolved |
| `solve.lm` | 28 | 1411.55 | 50.41 | 64.08 | 64.53 | 64.69 | resolved |
| `solve.slvs` | 726 | 444.34 | 0.6120 | 0.2590 | 0.2660 | 18.42 | resolved |

#### Constraint solver (native)

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `ffi.slvs.solve` | 722 | 355.34 | 0.4922 | 0.2220 | 0.2270 | 18.25 | resolved |

#### Constraints

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `constraints.add.dimension` | 2 | 88.40 | 44.20 | 44.22 | 44.22 | 44.22 | resolved |
| `constraints.add.tangent` | 2 | 24.35 | 12.17 | 12.19 | 12.19 | 12.19 | resolved |
| `constraints.add.fix` | 2 | 22.36 | 11.18 | 11.29 | 11.29 | 11.29 | resolved |
| `constraints.encode` | 40 | 10.70 | 0.2675 | 0.2670 | 0.2730 | 0.2930 | resolved |
| `constraints.add.perpendicular` | 2 | 8.85 | 4.426 | 4.617 | 4.617 | 4.617 | resolved |
| `constraints.decode` | 40 | 6.91 | 0.1728 | 0.1670 | 0.1910 | 0.3320 | resolved |
| `constraints.add.parallel` | 2 | 1.30 | 0.6500 | 0.7010 | 0.7010 | 0.7010 | resolved |
| `constraints.add.coincident` | 2 | 1.26 | 0.6290 | 0.7060 | 0.7060 | 0.7060 | resolved |
| `constraints.add.collinear` | 2 | 1.25 | 0.6235 | 0.6490 | 0.6490 | 0.6490 | resolved |
| `constraints.add.symmetric` | 2 | 1.18 | 0.5915 | 0.5960 | 0.5960 | 0.5960 | resolved |
| `constraints.add.midpoint` | 2 | 1.17 | 0.5850 | 0.6090 | 0.6090 | 0.6090 | resolved |
| `constraints.add.horizontal` | 2 | 1.12 | 0.5615 | 0.5920 | 0.5920 | 0.5920 | resolved |
| `constraints.add.concentric` | 2 | 1.12 | 0.5590 | 0.5710 | 0.5710 | 0.5710 | resolved |
| `constraints.add.vertical` | 2 | 1.04 | 0.5215 | 0.5240 | 0.5240 | 0.5240 | resolved |
| `constraints.add.equal` | 2 | 1.04 | 0.5195 | 0.5230 | 0.5230 | 0.5230 | resolved |
| `constraints.add.smooth` | 2 | 0.88 | 0.4395 | 0.4430 | 0.4430 | 0.4430 | resolved |
| `constraints.inferConstraints` | 80 | 0.31 | 0.0039 | 0.0020 | 0.0130 | 0.0840 | resolved |
| `constraints.inferPointBindings` | 80 | 0.20 | 0.0025 | 0.0010 | 0.0100 | 0.0140 | resolved |

#### Document I/O

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `io.savePart` | 1 | 21.14 | 21.14 | 21.14 | 21.14 | 21.14 | resolved |

#### Drawing tools

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `tool.build.eqCurve` | 100 | 4.25 | 0.0425 | 0.0150 | 0.0680 | 1.621 | resolved |
| `tool.build.bridge` | 100 | 1.01 | 0.0101 | 0.0100 | 0.0130 | 0.0180 | resolved |
| `tool.build.circleTangent` | 100 | 1.01 | 0.0101 | 0.0040 | 0.0060 | 0.5770 | resolved |
| `tool.build.arcTangent` | 100 | 0.36 | 0.0036 | 0.0030 | 0.0040 | 0.0580 | resolved |
| `tool.build.fillet` | 100 | 0.36 | 0.0036 | 0.0030 | 0.0050 | 0.0100 | resolved |
| `tool.build.chamfer` | 100 | 0.24 | 0.0024 | 0.0020 | 0.0040 | 0.0050 | resolved |
| `tool.build.splineInterp` | 100 | 0.12 | 0.0012 | 0.0010 | 0.0020 | 0.0050 | resolved |
| `tool.build.slotCC` | 100 | 0.12 | 0.0012 | < 1 µs | < 1 µs | 0.1150 | resolved |
| `tool.build.splineCV` | 100 | 0.11 | 0.0011 | 0.0010 | 0.0020 | 0.0070 | resolved |
| `tool.build.splineFree` | 100 | 0.11 | 0.0011 | 0.0010 | 0.0020 | 0.0020 | resolved |
| `tool.build.slot3A` | 100 | 0.10 | 0.0010 | 0.0010 | 0.0010 | 0.0040 | resolved |
| `tool.build.slotCPA` | 100 | 0.09 | 0.0009 | 0.0010 | 0.0020 | 0.0040 | resolved |
| `tool.build.line` | 100 | 0.05 | 0.0005 | < 1 µs | 0.0010 | 0.0440 | resolved |
| `tool.build.rectTwoPoint` | 100 | 0.05 | 0.0005 | < 1 µs | < 1 µs | 0.0450 | resolved |
| `tool.build.polygon` | 100 | 0.04 | 0.0004 | < 1 µs | 0.0020 | 0.0030 | resolved |
| `tool.build.ellipse` | 100 | 0.01 | < 1 µs | < 1 µs | 0.0010 | 0.0020 | unresolved |
| `tool.build.arcThreePoint` | 100 | 0.01 | < 1 µs | < 1 µs | < 1 µs | 0.0030 | unresolved |
| `tool.build.lineMid` | 100 | 0.01 | < 1 µs | < 1 µs | 0.0010 | 0.0010 | unresolved |
| `tool.build.point` | 100 | 0.00 | < 1 µs | < 1 µs | < 1 µs | 0.0030 | unresolved |
| `tool.build.circleCenter` | 100 | 0.00 | < 1 µs | < 1 µs | < 1 µs | 0.0010 | unresolved |
| `tool.build.rect2PC` | 100 | 0.00 | < 1 µs | < 1 µs | < 1 µs | 0.0010 | unresolved |
| `tool.build.slotCP` | 100 | 0.00 | < 1 µs | < 1 µs | < 1 µs | 0.0010 | unresolved |
| `tool.build.slotOverall` | 100 | 0.00 | < 1 µs | < 1 µs | < 1 µs | 0.0010 | unresolved |
| `tool.build.rect3PC` | 100 | 0.00 | < 1 µs | < 1 µs | < 1 µs | 0.0010 | unresolved |
| `tool.build.arcCenter` | 100 | 0.00 | < 1 µs | < 1 µs | < 1 µs | 0.0010 | unresolved |
| `tool.build.rect3P` | 100 | 0.00 | < 1 µs | < 1 µs | < 1 µs | < 1 µs | unresolved |

#### Drawing tools (composite)

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `tools.filletMaxRadius` | 20 | 0.99 | 0.0495 | 0.0490 | 0.0510 | 0.0540 | resolved |
| `tools.filletInventor` | 100 | 0.11 | 0.0011 | 0.0010 | 0.0010 | 0.0070 | resolved |
| `tools.chamferInventor` | 100 | 0.01 | < 1 µs | < 1 µs | < 1 µs | 0.0020 | unresolved |

#### Ellipses

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `ellipse.curve` | 200 | 0.40 | 0.0020 | 0.0020 | 0.0020 | 0.0030 | resolved |

#### Freehand

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `freehand.fit` | 60 | 5.23 | 0.0872 | 0.0210 | 0.2320 | 0.3540 | resolved |
| `freehand.smooth` | 60 | 4.71 | 0.0785 | 0.0170 | 0.2170 | 0.2310 | resolved |
| `freehand.dedupe` | 60 | 0.27 | 0.0044 | 0.0020 | 0.0110 | 0.0180 | resolved |
| `freehand.resample` | 60 | 0.11 | 0.0019 | 0.0010 | 0.0050 | 0.0050 | resolved |

#### Gears

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `gear.curve` | 120 | 72.80 | 0.6067 | 0.5530 | 0.9630 | 1.117 | resolved |
| `gear.curve.cached` | 1200 | 1.25 | 0.0010 | 0.0010 | 0.0010 | 0.0080 | resolved |

#### Modify operations

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `modify.intersectionsWithOthers` | 136 | 0.86 | 0.0063 | 0.0080 | 0.0090 | 0.0260 | resolved |
| `modify.trimEntity` | 68 | 0.57 | 0.0084 | 0.0100 | 0.0110 | 0.0120 | resolved |
| `modify.trim` | 68 | 0.55 | 0.0081 | 0.0100 | 0.0110 | 0.0120 | resolved |
| `modify.transformGeo` | 80 | 0.47 | 0.0058 | 0.0080 | 0.0090 | 0.0800 | resolved |
| `modify.offsetEntity` | 800 | 0.35 | 0.0004 | < 1 µs | < 1 µs | 0.3500 | resolved |
| `modify.offsetChainAt` | 100 | 0.35 | 0.0035 | 0.0030 | 0.0030 | 0.0440 | resolved |
| `modify.extendEntity` | 40 | 0.20 | 0.0049 | 0.0050 | 0.0050 | 0.0060 | resolved |
| `modify.extend` | 40 | 0.17 | 0.0043 | 0.0040 | 0.0050 | 0.0050 | resolved |
| `modify.stretchGeo` | 40 | 0.17 | 0.0042 | 0.0040 | 0.0050 | 0.0050 | resolved |
| `modify.trimCutAway` | 20 | 0.11 | 0.0054 | 0.0050 | 0.0060 | 0.0060 | resolved |
| `modify.splitEntity` | 20 | 0.10 | 0.0052 | 0.0050 | 0.0070 | 0.0070 | resolved |
| `modify.offset` | 800 | 0.00 | < 1 µs | < 1 µs | < 1 µs | 0.0010 | unresolved |

#### Other

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `tool.spline.cv` | 120 | 0.09 | 0.0008 | < 1 µs | 0.0030 | 0.0040 | resolved |
| `tool.spline.interp` | 120 | 0.08 | 0.0007 | < 1 µs | 0.0020 | 0.0030 | resolved |

#### Patterns

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `pattern.occurrences.circular` | 120 | 1.46 | 0.0122 | 0.0040 | 0.0200 | 0.4590 | resolved |
| `pattern.occurrences.curve` | 40 | 0.85 | 0.0213 | 0.0210 | 0.0220 | 0.0260 | resolved |
| `pattern.occurrences` | 120 | 0.18 | 0.0015 | 0.0010 | 0.0030 | 0.0210 | resolved |
| `pattern.occurrences.points` | 120 | 0.17 | 0.0014 | 0.0010 | 0.0030 | 0.0100 | resolved |
| `pattern.sketchPoints` | 120 | 0.04 | 0.0003 | < 1 µs | 0.0010 | 0.0010 | resolved |
| `pattern.occurrences.mirror` | 40 | 0.00 | < 1 µs | < 1 µs | < 1 µs | < 1 µs | unresolved |

#### Projection

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `project.partEdges` | 60 | 9.43 | 0.1572 | 0.0470 | 0.5070 | 1.531 | resolved |

#### Ramps (fine-grained sweeps)

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `ramp.allEdges.144` | 2 | 3417.13 | 1708.6 | 1710.5 | 1710.5 | 1710.5 | resolved |
| `ramp.allEdges.96` | 2 | 1531.77 | 765.9 | 766.0 | 766.0 | 766.0 | resolved |
| `ramp.allEdges.72` | 2 | 867.50 | 433.7 | 434.1 | 434.1 | 434.1 | resolved |
| `ramp.allEdges.48` | 2 | 391.88 | 195.9 | 196.4 | 196.4 | 196.4 | resolved |
| `ramp.analyze.256` | 2 | 312.14 | 156.1 | 158.9 | 158.9 | 158.9 | resolved |
| `ramp.boolean.144` | 2 | 287.82 | 143.9 | 144.0 | 144.0 | 144.0 | resolved |
| `ramp.solids.16` | 2 | 252.37 | 126.2 | 127.8 | 127.8 | 127.8 | resolved |
| `ramp.allEdges.36` | 2 | 222.32 | 111.2 | 111.2 | 111.2 | 111.2 | resolved |
| `ramp.solids.12` | 2 | 186.47 | 93.23 | 93.53 | 93.53 | 93.53 | resolved |
| `ramp.boolean.96` | 2 | 175.25 | 87.62 | 87.89 | 87.89 | 87.89 | resolved |
| `ramp.analyze.192` | 2 | 143.94 | 71.97 | 72.07 | 72.07 | 72.07 | resolved |
| `ramp.solids.8` | 2 | 127.37 | 63.68 | 64.09 | 64.09 | 64.09 | resolved |
| `ramp.boolean.72` | 2 | 125.76 | 62.88 | 62.89 | 62.89 | 62.89 | resolved |
| `ramp.allEdges.24` | 2 | 101.59 | 50.80 | 50.82 | 50.82 | 50.82 | resolved |
| `ramp.mesh.288` | 2 | 99.96 | 49.98 | 50.26 | 50.26 | 50.26 | resolved |
| `ramp.solids.6` | 2 | 94.11 | 47.06 | 47.16 | 47.16 | 47.16 | resolved |
| `ramp.boolean.48` | 2 | 79.74 | 39.87 | 39.88 | 39.88 | 39.88 | resolved |
| `ramp.mesh.192` | 2 | 66.18 | 33.09 | 33.18 | 33.18 | 33.18 | resolved |
| `ramp.solids.4` | 2 | 64.05 | 32.03 | 32.29 | 32.29 | 32.29 | resolved |
| `ramp.boolean.36` | 2 | 58.36 | 29.18 | 29.21 | 29.21 | 29.21 | resolved |
| `ramp.mesh.144` | 2 | 48.94 | 24.47 | 24.78 | 24.78 | 24.78 | resolved |
| `ramp.analyze.128` | 2 | 45.12 | 22.56 | 24.04 | 24.04 | 24.04 | resolved |
| `ramp.boolean.24` | 2 | 38.43 | 19.22 | 19.22 | 19.22 | 19.22 | resolved |
| `ramp.density.8` | 2 | 36.58 | 18.29 | 18.52 | 18.52 | 18.52 | resolved |
| `ramp.build.288` | 2 | 35.79 | 17.89 | 17.93 | 17.93 | 17.93 | resolved |
| `ramp.mesh.96` | 2 | 31.74 | 15.87 | 16.18 | 16.18 | 16.18 | resolved |
| `ramp.solids.2` | 2 | 31.31 | 15.65 | 16.12 | 16.12 | 16.12 | resolved |
| `ramp.drag.128` | 2 | 29.79 | 14.89 | 15.03 | 15.03 | 15.03 | resolved |
| `ramp.allEdges.12` | 2 | 28.25 | 14.12 | 14.16 | 14.16 | 14.16 | resolved |
| `ramp.analyze.96` | 2 | 27.01 | 13.50 | 17.50 | 17.50 | 17.50 | resolved |
| `ramp.mesh.72` | 2 | 24.26 | 12.13 | 12.24 | 12.24 | 12.24 | resolved |
| `ramp.build.192` | 2 | 23.44 | 11.72 | 11.76 | 11.76 | 11.76 | resolved |
| `ramp.density.6` | 2 | 20.55 | 10.28 | 10.30 | 10.30 | 10.30 | resolved |
| `ramp.boolean.12` | 2 | 20.03 | 10.01 | 10.09 | 10.09 | 10.09 | resolved |
| `ramp.drag.96` | 2 | 17.75 | 8.875 | 8.885 | 8.885 | 8.885 | resolved |
| `ramp.build.144` | 2 | 17.48 | 8.738 | 8.763 | 8.763 | 8.763 | resolved |
| `ramp.solids.1` | 2 | 16.13 | 8.066 | 8.496 | 8.496 | 8.496 | resolved |
| `ramp.mesh.48` | 2 | 16.04 | 8.018 | 8.086 | 8.086 | 8.086 | resolved |
| `ramp.mesh.36` | 2 | 12.11 | 6.053 | 6.149 | 6.149 | 6.149 | resolved |
| `ramp.build.96` | 2 | 11.63 | 5.817 | 5.826 | 5.826 | 5.826 | resolved |
| `ramp.analyze.64` | 2 | 11.60 | 5.800 | 7.427 | 7.427 | 7.427 | resolved |
| `ramp.solve.256` | 2 | 10.75 | 5.374 | 5.400 | 5.400 | 5.400 | resolved |
| `ramp.drag.48` | 2 | 10.69 | 5.345 | 7.968 | 7.968 | 7.968 | resolved |
| `ramp.density.4` | 2 | 9.48 | 4.741 | 4.743 | 4.743 | 4.743 | resolved |
| `ramp.drag.64` | 2 | 9.18 | 4.591 | 4.760 | 4.760 | 4.760 | resolved |
| `ramp.build.72` | 2 | 8.72 | 4.359 | 4.360 | 4.360 | 4.360 | resolved |
| `ramp.mesh.24` | 2 | 8.38 | 4.189 | 4.265 | 4.265 | 4.265 | resolved |
| `ramp.solve.192` | 2 | 6.36 | 3.179 | 3.198 | 3.198 | 3.198 | resolved |
| `ramp.build.48` | 2 | 5.77 | 2.887 | 2.906 | 2.906 | 2.906 | resolved |
| `ramp.density.3` | 2 | 5.41 | 2.704 | 2.753 | 2.753 | 2.753 | resolved |
| `ramp.drag.8` | 2 | 4.60 | 2.302 | 4.336 | 4.336 | 4.336 | resolved |
| `ramp.mesh.12` | 2 | 4.41 | 2.203 | 2.302 | 2.302 | 2.302 | resolved |
| `ramp.build.36` | 2 | 4.34 | 2.171 | 2.176 | 2.176 | 2.176 | resolved |
| `ramp.analyze.48` | 2 | 3.58 | 1.791 | 1.807 | 1.807 | 1.807 | resolved |
| `ramp.solve.128` | 2 | 3.06 | 1.531 | 1.550 | 1.550 | 1.550 | resolved |
| `ramp.build.24` | 2 | 2.94 | 1.470 | 1.471 | 1.471 | 1.471 | resolved |
| `ramp.drag.32` | 2 | 2.84 | 1.420 | 1.430 | 1.430 | 1.430 | resolved |
| `ramp.density.2` | 2 | 2.67 | 1.337 | 1.337 | 1.337 | 1.337 | resolved |
| `ramp.drag.24` | 2 | 1.94 | 0.9675 | 0.9720 | 0.9720 | 0.9720 | resolved |
| `ramp.solve.96` | 2 | 1.87 | 0.9365 | 0.9440 | 0.9440 | 0.9440 | resolved |
| `ramp.build.12` | 2 | 1.57 | 0.7875 | 0.8220 | 0.8220 | 0.8220 | resolved |
| `ramp.analyze.32` | 2 | 1.56 | 0.7820 | 0.7850 | 0.7850 | 0.7850 | resolved |
| `ramp.drag.16` | 2 | 1.14 | 0.5695 | 0.5920 | 0.5920 | 0.5920 | resolved |
| `ramp.solve.64` | 2 | 0.96 | 0.4810 | 0.4960 | 0.4960 | 0.4960 | resolved |
| `ramp.density.1` | 2 | 0.90 | 0.4515 | 0.4570 | 0.4570 | 0.4570 | resolved |
| `ramp.analyze.24` | 2 | 0.87 | 0.4335 | 0.4340 | 0.4340 | 0.4340 | resolved |
| `ramp.solve.48` | 2 | 0.61 | 0.3045 | 0.3160 | 0.3160 | 0.3160 | resolved |
| `ramp.analyze.16` | 2 | 0.41 | 0.2055 | 0.2080 | 0.2080 | 0.2080 | resolved |
| `ramp.solve.32` | 2 | 0.34 | 0.1685 | 0.1780 | 0.1780 | 0.1780 | resolved |
| `ramp.solve.24` | 2 | 0.24 | 0.1185 | 0.1260 | 0.1260 | 0.1260 | resolved |
| `ramp.solve.8` | 2 | 0.15 | 0.0760 | 0.1120 | 0.1120 | 0.1120 | resolved |
| `ramp.solve.16` | 2 | 0.15 | 0.0750 | 0.0810 | 0.0810 | 0.0810 | resolved |
| `ramp.analyze.8` | 2 | 0.13 | 0.0655 | 0.0670 | 0.0670 | 0.0670 | resolved |

#### RealityKit (Dart side)

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `rv.setScene` | 1 | 35.73 | 35.73 | 35.73 | 35.73 | 35.73 | resolved |
| `rv.setOverlays` | 1 | 35.72 | 35.72 | 35.72 | 35.72 | 35.72 | resolved |
| `rv.setCamera` | 1 | 35.09 | 35.09 | 35.09 | 35.09 | 35.09 | resolved |

#### RealityKit (native, past the boundary)

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `rv.native.setScene` | 1 | 33.51 | 33.51 | 33.51 | 33.51 | 33.51 | resolved |
| `rv.native.planes` | 1 | 33.36 | 33.36 | 33.36 | 33.36 | 33.36 | resolved |
| `rv.native.sketches` | 1 | 0.08 | 0.0820 | 0.0820 | 0.0820 | 0.0820 | resolved |
| `rv.native.setCamera` | 1 | 0.08 | 0.0800 | 0.0800 | 0.0800 | 0.0800 | resolved |
| `rv.native.solids` | 1 | 0.04 | 0.0371 | 0.0371 | 0.0371 | 0.0371 | resolved |
| `rv.native.placeCamera` | 1 | 0.02 | 0.0190 | 0.0190 | 0.0190 | 0.0190 | resolved |
| `rv.native.setOverlays` | 1 | 0.02 | 0.0150 | 0.0150 | 0.0150 | 0.0150 | resolved |
| `rv.native.accents` | 1 | 0.00 | 0.0041 | 0.0041 | 0.0041 | 0.0041 | resolved |
| `rv.native.highlight` | 1 | 0.00 | < 1 µs | < 1 µs | < 1 µs | < 1 µs | unresolved |

#### Sketch analysis and rebuild

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `sketch.analyze` | 75 | 670.42 | 8.939 | 0.7760 | 27.55 | 158.9 | resolved |
| `sketch.profileLoops` | 60 | 12.36 | 0.2060 | 0.2040 | 0.2170 | 0.2300 | resolved |
| `sketch.syncProjections` | 1452 | 0.00 | < 1 µs | < 1 µs | < 1 µs | < 1 µs | unresolved |

#### Splines

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `spline.curveFor` | 600 | 140.24 | 0.2337 | 0.5880 | 0.6340 | 0.7580 | resolved |

#### Startup

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `launch.toFirstFrame` | 1 | 171.17 | 171.2 | 171.2 | 171.2 | 171.2 | resolved |

#### Startup steps

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `step.state.Engine.create (backend probe)` | 1 | 4.78 | 4.782 | 4.782 | 4.782 | 4.782 | resolved |
| `step.state.occt smoke` | 1 | 3.16 | 3.163 | 3.163 | 3.163 | 3.163 | resolved |
| `step.ffi.symbol lookup + qcad_init()` | 1 | 2.48 | 2.482 | 2.482 | 2.482 | 2.482 | resolved |
| `step.state.getApplicationDocumentsDirectory (platform channel)` | 1 | 2.24 | 2.243 | 2.243 | 2.243 | 2.243 | resolved |
| `step.ffi.qcad_document_new()` | 1 | 1.68 | 1.682 | 1.682 | 1.682 | 1.682 | resolved |
| `step.main.WidgetsFlutterBinding.ensureInitialized` | 1 | 0.38 | 0.3770 | 0.3770 | 0.3770 | 0.3770 | resolved |
| `step.state.refreshSaved` | 1 | 0.29 | 0.2880 | 0.2880 | 0.2880 | 0.2880 | resolved |
| `step.ffi.probe qcad_add_line()` | 1 | 0.21 | 0.2060 | 0.2060 | 0.2060 | 0.2060 | resolved |
| `step.state.Engine.create (smoke)` | 1 | 0.13 | 0.1300 | 0.1300 | 0.1300 | 0.1300 | resolved |
| `step.state.loadRemembered` | 1 | 0.12 | 0.1240 | 0.1240 | 0.1240 | 0.1240 | resolved |
| `step.state.migrateLegacyDocuments` | 1 | 0.06 | 0.0630 | 0.0630 | 0.0630 | 0.0630 | resolved |
| `step.ffi.probe entity_ids/geometry round-trip` | 1 | 0.06 | 0.0610 | 0.0610 | 0.0610 | 0.0610 | resolved |
| `step.main.runApp` | 1 | 0.04 | 0.0370 | 0.0370 | 0.0370 | 0.0370 | resolved |
| `step.ffi.probe qcad_document_free()` | 1 | 0.04 | 0.0350 | 0.0350 | 0.0350 | 0.0350 | resolved |
| `step.main.setPreferredOrientations (fire-and-forget)` | 1 | 0.04 | 0.0350 | 0.0350 | 0.0350 | 0.0350 | resolved |
| `step.ffi.DynamicLibrary.process()` | 1 | 0.02 | 0.0200 | 0.0200 | 0.0200 | 0.0200 | resolved |
| `step.state.reacquireExternals` | 1 | 0.02 | 0.0200 | 0.0200 | 0.0200 | 0.0200 | resolved |
| `step.main.AppState()` | 1 | 0.01 | 0.0150 | 0.0150 | 0.0150 | 0.0150 | resolved |
| `step.main.hide system UI (fire-and-forget)` | 1 | 0.01 | 0.0130 | 0.0130 | 0.0130 | 0.0130 | resolved |
| `step.ffi.qcad_version()` | 1 | 0.01 | 0.0060 | 0.0060 | 0.0060 | 0.0060 | resolved |

#### UI runner

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `ui.allGeometry` | 10 | 0.01 | 0.0005 | < 1 µs | 0.0050 | 0.0050 | marginal |

#### UI shell

| span | n | total ms | mean ms | p50 | p95 | max | class |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| `menu.ribbon.part` | 1 | 0.07 | 0.0650 | 0.0650 | 0.0650 | 0.0650 | resolved |
| `browser.sig` | 2 | 0.04 | 0.0205 | 0.0250 | 0.0250 | 0.0250 | resolved |
| `toolbar.sig` | 3 | 0.03 | 0.0097 | 0.0120 | 0.0140 | 0.0140 | resolved |
| `tabbar.sig` | 2 | 0.01 | 0.0070 | 0.0100 | 0.0100 | 0.0100 | resolved |


### B. Complete counter inventory

**59 counters**, session scope. Counters are exact integers and carry no timing uncertainty; where a counter and a duration answer the same question, the counter is the stronger evidence and is invariant under a change of processor.

#### 2D kernel — qcad entry points

| counter | value |
| --- | ---: |
| `ffi.qcad.allGeometry.entities` | 1523 |

#### 2D — interaction

| counter | value |
| --- | ---: |
| `2d.displayGeometry.solves` | 240 |

#### 3D kernel — OCCT entry points

| counter | value |
| --- | ---: |
| `ffi.occt.chamferEdges.edges` | 34 |
| `ffi.occt.edgeInfo.calls` | 6552 |
| `ffi.occt.filletEdges.edges` | 66 |
| `ffi.occt.meshCopyOut.tris` | 63016 |
| `ffi.occt.meshCopyOut.verts` | 89196 |
| `ffi.occt.meshCreate.calls` | 302 |

#### 3D kernel — scenarios

| counter | value |
| --- | ---: |
| `kernel.feature.ok` | 60 |
| `kernel.sweepTwist.fail` | 4 |

#### 3D — feature rebuild

| counter | value |
| --- | ---: |
| `part.rebuild.passes` | 18 |

#### Constraint solver

| counter | value |
| --- | ---: |
| `solve.iterationsRequested` | 20350 |
| `solve.ok` | 720 |
| `solve.path.lm` | 28 |
| `solve.path.slvs` | 698 |
| `solve.slvs.rejected.residual` | 24 |
| `solve.unsatisfied` | 6 |

#### Constraint solver (native)

| counter | value |
| --- | ---: |
| `ffi.slvs.solve.constraints` | 61310 |
| `ffi.slvs.solve.points` | 57312 |

#### Constraints

| counter | value |
| --- | ---: |
| `constraints.unsupportedInFixture.pattern` | 2 |

#### Drawing tools

| counter | value |
| --- | ---: |
| `tool.build.arcCenter.entities` | 2 |
| `tool.build.arcTangent.entities` | 2 |
| `tool.build.arcThreePoint.entities` | 2 |
| `tool.build.bridge.entities` | 2 |
| `tool.build.chamfer.null` | 2 |
| `tool.build.circleCenter.entities` | 2 |
| `tool.build.circleTangent.entities` | 2 |
| `tool.build.ellipse.entities` | 2 |
| `tool.build.eqCurve.entities` | 2 |
| `tool.build.fillet.null` | 2 |
| `tool.build.line.entities` | 2 |
| `tool.build.lineMid.entities` | 2 |
| `tool.build.point.entities` | 2 |
| `tool.build.polygon.entities` | 14 |
| `tool.build.rect2PC.entities` | 12 |
| `tool.build.rect3P.entities` | 8 |
| `tool.build.rect3PC.entities` | 12 |
| `tool.build.rectTwoPoint.entities` | 8 |
| `tool.build.slot3A.entities` | 12 |
| `tool.build.slotCC.entities` | 10 |
| `tool.build.slotCP.entities` | 10 |
| `tool.build.slotCPA.entities` | 12 |
| `tool.build.slotOverall.entities` | 10 |
| `tool.build.splineCV.entities` | 2 |
| `tool.build.splineFree.entities` | 2 |
| `tool.build.splineInterp.entities` | 2 |

#### RealityKit (Dart side)

| counter | value |
| --- | ---: |
| `rv.setCamera.calls` | 1 |
| `rv.setOverlays.calls` | 1 |
| `rv.setScene.calls` | 1 |

#### UI shell

| counter | value |
| --- | ---: |
| `browser.rows.hit` | 1 |
| `browser.rows.miss` | 1 |
| `browser.setRows.calls` | 1 |
| `browser.sig.rows` | 6 |
| `menu.ribbon.builds` | 1 |
| `tabbar.rows.miss` | 2 |
| `tabbar.setTabs.calls` | 2 |
| `toolbar.rows.hit` | 1 |
| `toolbar.rows.miss` | 2 |
| `toolbar.setItems.calls` | 2 |


### C. Complete gauge inventory

**298 gauges** (292 application, 6 machine). Gauges are exact last-written values describing the size of the input a measurement ran against — the axis a duration is meaningless without.

#### 3D kernel — scenarios

| gauge | value |
| --- | ---: |
| `kernel.blendEdges` | 12 |
| `kernel.boolOperandEdges` | 360 |
| `kernel.chainEdges` | 128 |
| `kernel.coilRevs` | 12 |
| `kernel.edgeInfoScale.edges.120` | 360 |
| `kernel.edgeInfoScale.edges.24` | 72 |
| `kernel.edgeInfoScale.edges.240` | 720 |
| `kernel.edgeInfoScale.edges.60` | 180 |
| `kernel.edgeInfoScale.faces.120` | 122 |
| `kernel.edgeInfoScale.faces.24` | 26 |
| `kernel.edgeInfoScale.faces.240` | 242 |
| `kernel.edgeInfoScale.faces.60` | 62 |
| `kernel.holes` | 12 |
| `kernel.loftSections` | 8 |
| `kernel.mesh.srcEdges` | 360 |
| `kernel.mesh.tris` | 476 |
| `kernel.pathPts` | 96 |
| `kernel.profilePts` | 48 |
| `kernel.query.edges` | 360 |
| `kernel.unify.facesAfter` | 6 |
| `kernel.unify.facesBefore` | 6 |

#### 3D — face provenance

| gauge | value |
| --- | ---: |
| `provenance.attribute.features.12` | 12 |
| `provenance.attribute.features.2` | 2 |
| `provenance.attribute.features.6` | 6 |
| `provenance.attribute.out.12` | 62 |
| `provenance.attribute.out.2` | 62 |
| `provenance.attribute.out.6` | 62 |
| `provenance.faceSurfaces.out.120` | 122 |
| `provenance.faceSurfaces.out.24` | 26 |
| `provenance.faceSurfaces.out.360` | 362 |
| `provenance.faces.120` | 122 |
| `provenance.faces.24` | 26 |
| `provenance.faces.360` | 362 |
| `provenance.newSurfaces.in.120` | 122 |
| `provenance.newSurfaces.in.24` | 26 |
| `provenance.newSurfaces.in.360` | 362 |
| `provenance.newSurfaces.out.120` | 120 |
| `provenance.newSurfaces.out.24` | 24 |
| `provenance.newSurfaces.out.360` | 360 |
| `provenance.tris.120` | 476 |
| `provenance.tris.24` | 92 |
| `provenance.tris.360` | 1436 |

#### 3D — feature rebuild

| gauge | value |
| --- | ---: |
| `part.features` | 6 |

#### Application paths

| gauge | value |
| --- | ---: |
| `app.codec.entities` | 128 |
| `app.engineEntities` | 128 |
| `app.history.entities` | 128 |
| `app.patternCopies` | 315 |
| `app.patternCount` | 64 |
| `app.pick3d.edges` | 1440 |
| `app.project.edges` | 1440 |
| `app.project.tris` | 2856 |
| `app.rebuild.features` | 6 |
| `app.scene.features` | 6 |
| `app.scene.tris` | 2856 |

#### Constraint solver

| gauge | value |
| --- | ---: |
| `solve.constraints` | 73 |
| `solve.dragged` | 1 |
| `solve.entities` | 48 |

#### Constraints

| gauge | value |
| --- | ---: |
| `constraints.encoded` | 193 |

#### Drawing tools (composite)

| gauge | value |
| --- | ---: |
| `tools.built` | 24 |
| `tools.nullResult` | 2 |
| `tools.splineCVs` | 64 |
| `tools.splinePolyPts` | 261 |

#### Freehand

| gauge | value |
| --- | ---: |
| `freehand.rawSamples` | 1024 |

#### Gears

| gauge | value |
| --- | ---: |
| `gear.curve.points` | 2160 |

#### Modify operations

| gauge | value |
| --- | ---: |
| `modify.entities` | 128 |
| `modify.intersectionsFound` | 800 |

#### Other

| gauge | value |
| --- | ---: |
| `analyze.constraints` | 193 |
| `analyze.dof` | 126 |
| `analyze.entities` | 128 |
| `features` | 0 |
| `fillet.candidates` | 72 |
| `infer.existing` | 128 |
| `infer.found` | 29 |
| `mesh.tris.last` | 188 |
| `solids` | 0 |
| `sweep.edgeCount` | 360 |
| `sweep.profilePts` | 120 |
| `triangles` | 0 |

#### Patterns

| gauge | value |
| --- | ---: |
| `pattern.occurrences.circular.out.16` | 15 |
| `pattern.occurrences.circular.out.4` | 3 |
| `pattern.occurrences.circular.out.64` | 63 |
| `pattern.occurrences.curve.out` | 15 |
| `pattern.occurrences.curve.pathPts` | 120 |
| `pattern.occurrences.mirror.out` | 1 |
| `pattern.occurrences.out.16` | 15 |
| `pattern.occurrences.out.4` | 3 |
| `pattern.occurrences.out.64` | 63 |
| `pattern.occurrences.points.out.16` | 16 |
| `pattern.occurrences.points.out.4` | 4 |
| `pattern.occurrences.points.out.64` | 64 |
| `pattern.sketchPoints.out.16` | 16 |
| `pattern.sketchPoints.out.4` | 4 |
| `pattern.sketchPoints.out.64` | 64 |

#### Quality / calibration

| gauge | value |
| --- | ---: |
| `quality.budget.entitiesAt120Hz` | 192 |
| `quality.budget.entitiesAt60Hz` | 256 |
| `quality.cache.gearColdUs` | 475 |
| `quality.cache.gearSpeedup` | 432 |
| `quality.cache.gearWarmUs` | 1 |
| `quality.memPerSolidKB` | 2 |
| `quality.memPerTriangleBytes` | 14 |
| `quality.variance.analyze.iqrPct` | 13 |
| `quality.variance.analyze.medianUs` | 1777 |
| `quality.variance.analyze.spreadPct` | 17 |
| `quality.variance.extrude.iqrPct` | 0 |
| `quality.variance.extrude.medianUs` | 2834 |
| `quality.variance.extrude.spreadPct` | 3 |
| `quality.variance.solve.iqrPct` | 4 |
| `quality.variance.solve.medianUs` | 281 |
| `quality.variance.solve.spreadPct` | 18 |
| `quality.variance.splineEval.iqrPct` | 7 |
| `quality.variance.splineEval.medianUs` | 104 |
| `quality.variance.splineEval.spreadPct` | 67 |

#### Ramps (fine-grained sweeps)

| gauge | value |
| --- | ---: |
| `ramp.allEdges.edges.12` | 36 |
| `ramp.allEdges.edges.144` | 432 |
| `ramp.allEdges.edges.24` | 72 |
| `ramp.allEdges.edges.36` | 108 |
| `ramp.allEdges.edges.48` | 144 |
| `ramp.allEdges.edges.72` | 216 |
| `ramp.allEdges.edges.96` | 288 |
| `ramp.allEdges.k.144` | 198 |
| `ramp.allEdges.k.24` | 185 |
| `ramp.allEdges.k.36` | 193 |
| `ramp.allEdges.k.48` | 198 |
| `ramp.allEdges.k.72` | 196 |
| `ramp.allEdges.k.96` | 197 |
| `ramp.allEdges.rungs` | 7 |
| `ramp.analyze.k.128` | 65 |
| `ramp.analyze.k.16` | 167 |
| `ramp.analyze.k.192` | 303 |
| `ramp.analyze.k.24` | 187 |
| `ramp.analyze.k.256` | 275 |
| `ramp.analyze.k.32` | 204 |
| `ramp.analyze.k.48` | 203 |
| `ramp.analyze.k.64` | 498 |
| `ramp.analyze.k.96` | 211 |
| `ramp.analyze.rungs` | 10 |
| `ramp.boolean.k.144` | 123 |
| `ramp.boolean.k.24` | 95 |
| `ramp.boolean.k.36` | 103 |
| `ramp.boolean.k.48` | 108 |
| `ramp.boolean.k.72` | 112 |
| `ramp.boolean.k.96` | 114 |
| `ramp.boolean.rungs` | 7 |
| `ramp.build.edges.12` | 36 |
| `ramp.build.edges.144` | 432 |
| `ramp.build.edges.192` | 576 |
| `ramp.build.edges.24` | 72 |
| `ramp.build.edges.288` | 864 |
| `ramp.build.edges.36` | 108 |
| `ramp.build.edges.48` | 144 |
| `ramp.build.edges.72` | 216 |
| `ramp.build.edges.96` | 288 |
| `ramp.build.k.144` | 99 |
| `ramp.build.k.192` | 102 |
| `ramp.build.k.24` | 96 |
| `ramp.build.k.288` | 105 |
| `ramp.build.k.36` | 96 |
| `ramp.build.k.48` | 98 |
| `ramp.build.k.72` | 103 |
| `ramp.build.k.96` | 101 |
| `ramp.build.rungs` | 9 |
| `ramp.density.cons.1` | 97 |
| `ramp.density.cons.2` | 194 |
| `ramp.density.cons.3` | 291 |
| `ramp.density.cons.4` | 388 |
| `ramp.density.cons.6` | 582 |
| `ramp.density.cons.8` | 776 |
| `ramp.density.k.2` | 158 |
| `ramp.density.k.3` | 178 |
| `ramp.density.k.4` | 189 |
| `ramp.density.k.6` | 190 |
| `ramp.density.k.8` | 197 |
| `ramp.density.path.lm.1` | 28 |
| `ramp.density.path.lm.2` | 28 |
| `ramp.density.path.lm.3` | 28 |
| `ramp.density.path.lm.4` | 28 |
| `ramp.density.path.lm.6` | 28 |
| `ramp.density.path.lm.8` | 28 |
| `ramp.density.path.slvs.1` | 407 |
| `ramp.density.path.slvs.2` | 408 |
| `ramp.density.path.slvs.3` | 409 |
| `ramp.density.path.slvs.4` | 410 |
| `ramp.density.path.slvs.6` | 411 |
| `ramp.density.path.slvs.8` | 412 |
| `ramp.density.rungs` | 6 |
| `ramp.drag.k.128` | 184 |
| `ramp.drag.k.16` | 103 |
| `ramp.drag.k.24` | 139 |
| `ramp.drag.k.32` | 133 |
| `ramp.drag.k.48` | 427 |
| `ramp.drag.k.64` | -179 |
| `ramp.drag.k.96` | 153 |
| `ramp.drag.path.lm.128` | 28 |
| `ramp.drag.path.lm.16` | 28 |
| `ramp.drag.path.lm.24` | 28 |
| `ramp.drag.path.lm.32` | 28 |
| `ramp.drag.path.lm.48` | 28 |
| `ramp.drag.path.lm.64` | 28 |
| `ramp.drag.path.lm.8` | 28 |
| `ramp.drag.path.lm.96` | 28 |
| `ramp.drag.path.slvs.128` | 400 |
| `ramp.drag.path.slvs.16` | 340 |
| `ramp.drag.path.slvs.24` | 350 |
| `ramp.drag.path.slvs.32` | 360 |
| `ramp.drag.path.slvs.48` | 370 |
| `ramp.drag.path.slvs.64` | 380 |
| `ramp.drag.path.slvs.8` | 330 |
| `ramp.drag.path.slvs.96` | 390 |
| `ramp.drag.rungs` | 8 |
| `ramp.mesh.k.144` | 105 |
| `ramp.mesh.k.192` | 102 |
| `ramp.mesh.k.24` | 97 |
| `ramp.mesh.k.288` | 100 |
| `ramp.mesh.k.36` | 91 |
| `ramp.mesh.k.48` | 100 |
| `ramp.mesh.k.72` | 102 |
| `ramp.mesh.k.96` | 104 |
| `ramp.mesh.rungs` | 9 |
| `ramp.mesh.tris.12` | 44 |
| `ramp.mesh.tris.144` | 572 |
| `ramp.mesh.tris.192` | 764 |
| `ramp.mesh.tris.24` | 92 |
| `ramp.mesh.tris.288` | 1148 |
| `ramp.mesh.tris.36` | 140 |
| `ramp.mesh.tris.48` | 188 |
| `ramp.mesh.tris.72` | 284 |
| `ramp.mesh.tris.96` | 380 |
| `ramp.solids.k.12` | 92 |
| `ramp.solids.k.16` | 111 |
| `ramp.solids.k.2` | 99 |
| `ramp.solids.k.4` | 106 |
| `ramp.solids.k.6` | 97 |
| `ramp.solids.k.8` | 107 |
| `ramp.solids.rungs` | 7 |
| `ramp.solids.tris.1` | 188 |
| `ramp.solids.tris.12` | 2256 |
| `ramp.solids.tris.16` | 3008 |
| `ramp.solids.tris.2` | 376 |
| `ramp.solids.tris.4` | 752 |
| `ramp.solids.tris.6` | 1128 |
| `ramp.solids.tris.8` | 1504 |
| `ramp.solve.cons.128` | 193 |
| `ramp.solve.cons.16` | 25 |
| `ramp.solve.cons.192` | 289 |
| `ramp.solve.cons.24` | 37 |
| `ramp.solve.cons.256` | 385 |
| `ramp.solve.cons.32` | 49 |
| `ramp.solve.cons.48` | 73 |
| `ramp.solve.cons.64` | 97 |
| `ramp.solve.cons.8` | 13 |
| `ramp.solve.cons.96` | 145 |
| `ramp.solve.k.128` | 170 |
| `ramp.solve.k.16` | 79 |
| `ramp.solve.k.192` | 182 |
| `ramp.solve.k.24` | 117 |
| `ramp.solve.k.256` | 183 |
| `ramp.solve.k.32` | 125 |
| `ramp.solve.k.48` | 151 |
| `ramp.solve.k.64` | 161 |
| `ramp.solve.k.96` | 170 |
| `ramp.solve.path.lm.128` | 28 |
| `ramp.solve.path.lm.16` | 28 |
| `ramp.solve.path.lm.192` | 28 |
| `ramp.solve.path.lm.24` | 28 |
| `ramp.solve.path.lm.256` | 28 |
| `ramp.solve.path.lm.32` | 28 |
| `ramp.solve.path.lm.48` | 28 |
| `ramp.solve.path.lm.64` | 28 |
| `ramp.solve.path.lm.8` | 28 |
| `ramp.solve.path.lm.96` | 28 |
| `ramp.solve.path.slvs.128` | 238 |
| `ramp.solve.path.slvs.16` | 232 |
| `ramp.solve.path.slvs.192` | 239 |
| `ramp.solve.path.slvs.24` | 233 |
| `ramp.solve.path.slvs.256` | 240 |
| `ramp.solve.path.slvs.32` | 234 |
| `ramp.solve.path.slvs.48` | 235 |
| `ramp.solve.path.slvs.64` | 236 |
| `ramp.solve.path.slvs.8` | 231 |
| `ramp.solve.path.slvs.96` | 237 |
| `ramp.solve.rungs` | 10 |

#### RealityKit (native, past the boundary)

| gauge | value |
| --- | ---: |
| `rv.native.accents.worstUs` | 4 |
| `rv.native.highlight.worstUs` | 0 |
| `rv.native.placeCamera.worstUs` | 19 |
| `rv.native.planes.worstUs` | 33360 |
| `rv.native.setCamera.worstUs` | 80 |
| `rv.native.setOverlays.worstUs` | 15 |
| `rv.native.setScene.worstUs` | 33508 |
| `rv.native.sketches.worstUs` | 82 |
| `rv.native.solids.worstUs` | 37 |

#### UI runner

| gauge | value |
| --- | ---: |
| `ui.paint.constraints` | 193 |
| `ui.paint.entities` | 128 |

#### Machine state (native probe)

These describe the machine, not the application. They are deliberately a separate table: mixing them is how "the code got slower" stops being distinguishable from "the iPad got hot".

| probe | value |
| --- | ---: |
| `native.availableMB.postSuite` | 3885 |
| `native.availableMB.preSuite` | 3747 |
| `native.footprintMB.postSuite` | 1234 |
| `native.footprintMB.preSuite` | 1372 |
| `native.thermal.postSuite` | 0 |
| `native.thermal.preSuite` | 0 |


### D. Complete scenario inventory

**167 scenario executions** across 2 runners, scenario scope (measured pass only). `dominant span` is the largest single span inside the scenario — the quantity the cost-model fits use, because it excludes fixture construction.

| scenario | runner | wall ms | dominant span | dominant ms | spans |
| --- | --- | ---: | --- | ---: | ---: |
| `analysis.sweep.24` | ui | 1.816 | `sketch.analyze` | 1.811 | 1 |
| `analysis.sweep.64` | ui | 21.833 | `sketch.analyze` | 21.817 | 1 |
| `analysis.sweep.8` | ui | 0.207 | `sketch.analyze` | 0.204 | 1 |
| `app.engineFill.128` | ui | 4.273 | `app.engineFill` | 3.854 | 4 |
| `app.engineFill.24` | ui | 1.402 | `app.engineFill` | 1.212 | 4 |
| `app.history.24` | ui | 2.381 | `app.checkpoint` | 2.087 | 3 |
| `app.history.64` | ui | 5.888 | `app.checkpoint` | 5.441 | 3 |
| `app.history.8` | ui | 1.169 | `app.checkpoint` | 0.979 | 3 |
| `app.meshDiagnostics` | ui | 0.363 | `app.meshSelfReport` | 0.358 | 2 |
| `app.partCodec` | ui | 0.174 | `app.part.toJson` | 0.161 | 1 |
| `app.pattern.circular` | ui | 0.436 | `app.patternPreview` | 0.425 | 1 |
| `app.pattern.mirror` | ui | 0.024 | `app.patternPreview` | 0.020 | 1 |
| `app.pattern.occurrences.16` | ui | 0.025 | `pattern.occurrences` | 0.017 | 1 |
| `app.pattern.occurrences.4` | ui | 0.012 | `—` | 0.000 | 1 |
| `app.pattern.occurrences.64` | ui | 0.080 | `pattern.occurrences` | 0.062 | 1 |
| `app.pattern.occurrences.circular.16` | ui | 0.105 | `pattern.occurrences.circular` | 0.083 | 1 |
| `app.pattern.occurrences.circular.4` | ui | 0.027 | `pattern.occurrences.circular` | 0.020 | 1 |
| `app.pattern.occurrences.circular.64` | ui | 0.867 | `pattern.occurrences.circular` | 0.850 | 1 |
| `app.pattern.occurrences.curve` | ui | 0.436 | `pattern.occurrences.curve` | 0.422 | 1 |
| `app.pattern.occurrences.mirror` | ui | 0.003 | `—` | 0.000 | 1 |
| `app.pattern.occurrences.points.16` | ui | 0.178 | `pattern.occurrences.points` | 0.016 | 2 |
| `app.pattern.occurrences.points.4` | ui | 0.164 | `—` | 0.000 | 2 |
| `app.pattern.occurrences.points.64` | ui | 0.268 | `pattern.occurrences.points` | 0.069 | 2 |
| `app.pattern.rect.16` | ui | 0.290 | `app.patternPreview` | 0.282 | 1 |
| `app.pattern.rect.4` | ui | 0.062 | `app.patternPreview` | 0.046 | 1 |
| `app.pattern.rect.64` | ui | 1.185 | `app.patternPreview` | 1.172 | 1 |
| `app.pick.sweep` | ui | 15.832 | `2d.pickEntity` | 15.738 | 1 |
| `app.pickEdge3d.1x24` | ui | 0.102 | `app.pickEdge3d` | 0.086 | 1 |
| `app.pickEdge3d.3x48` | ui | 0.350 | `app.pickEdge3d` | 0.332 | 1 |
| `app.pickEdge3d.6x120` | ui | 1.640 | `app.pickEdge3d` | 1.621 | 1 |
| `app.projectEdges.1x24` | ui | 0.132 | `app.partEdges` | 0.128 | 2 |
| `app.projectEdges.3x48` | ui | 0.482 | `app.partEdges` | 0.475 | 2 |
| `app.projectEdges.6x120` | ui | 3.183 | `app.partEdges` | 3.175 | 2 |
| `app.provenance.attribute.12` | ui | 3.176 | `provenance.attributeFaces` | 2.884 | 1 |
| `app.provenance.attribute.2` | ui | 0.913 | `provenance.attributeFaces` | 0.862 | 1 |
| `app.provenance.attribute.6` | ui | 1.569 | `provenance.attributeFaces` | 1.427 | 1 |
| `app.provenance.faceSurfaces.120` | ui | 0.471 | `provenance.faceSurfaces` | 0.462 | 1 |
| `app.provenance.faceSurfaces.24` | ui | 0.095 | `provenance.faceSurfaces` | 0.090 | 1 |
| `app.provenance.faceSurfaces.360` | ui | 1.396 | `provenance.faceSurfaces` | 1.386 | 1 |
| `app.provenance.newSurfaces.120` | ui | 1.034 | `provenance.newSurfaces` | 0.933 | 1 |
| `app.provenance.newSurfaces.24` | ui | 0.072 | `provenance.newSurfaces` | 0.048 | 1 |
| `app.provenance.newSurfaces.360` | ui | 7.502 | `provenance.newSurfaces` | 7.214 | 1 |
| `app.rebuildPart.1` | ui | 3.943 | `part.rebuildAll` | 3.778 | 8 |
| `app.rebuildPart.3` | ui | 41.258 | `part.rebuildAll` | 40.812 | 10 |
| `app.rebuildPart.6` | ui | 76.020 | `part.rebuildAll` | 75.160 | 10 |
| `app.scene.1x24` | ui | 0.138 | `app.buildScenePayload` | 0.059 | 3 |
| `app.scene.3x48` | ui | 0.183 | `app.buildScenePayload` | 0.091 | 3 |
| `app.scene.6x120` | ui | 0.249 | `app.buildScenePayload` | 0.122 | 3 |
| `app.sceneRevs` | ui | 0.017 | `—` | 0.000 | 1 |
| `app.sketchCodec` | ui | 8.848 | `app.sketch.encodeCons` | 5.283 | 2 |
| `constraints.addEachType` | ui | 77.398 | `solve.total` | 70.949 | 20 |
| `constraints.encode` | ui | 8.691 | `constraints.encode` | 5.328 | 2 |
| `constraints.infer.24` | ui | 0.063 | `constraints.inferConstraints` | 0.026 | 2 |
| `constraints.infer.64` | ui | 0.166 | `constraints.inferConstraints` | 0.073 | 2 |
| `constraints.infer.8` | ui | 0.038 | `constraints.inferConstraints` | 0.011 | 2 |
| `gear.curve.10` | ui | 6.211 | `gear.curve` | 5.910 | 2 |
| `gear.curve.20` | ui | 11.459 | `gear.curve` | 11.142 | 2 |
| `gear.curve.40` | ui | 19.473 | `gear.curve` | 19.216 | 2 |
| `kernel.allEdges.repeat` | ui | 958.733 | `ffi.occt.allEdges` | 955.845 | 2 |
| `kernel.allEdges.sweep.12` | ui | 14.441 | `ffi.occt.allEdges` | 13.660 | 2 |
| `kernel.allEdges.sweep.120` | ui | 1176.991 | `ffi.occt.allEdges` | 1169.668 | 2 |
| `kernel.allEdges.sweep.48` | ui | 194.669 | `ffi.occt.allEdges` | 191.726 | 2 |
| `kernel.boolean` | ui | 31.282 | `ffi.occt.fuse` | 11.057 | 5 |
| `kernel.boolean.chain` | ui | 65.879 | `ffi.occt.fuse` | 65.608 | 3 |
| `kernel.boolean.complex.12` | ui | 23.518 | `ffi.occt.fuse` | 8.065 | 4 |
| `kernel.boolean.complex.120` | ui | 291.705 | `ffi.occt.fuse` | 99.935 | 4 |
| `kernel.boolean.complex.48` | ui | 98.622 | `ffi.occt.fuse` | 33.879 | 4 |
| `kernel.chamfer.edges.1` | ui | 60.946 | `ffi.occt.allEdges` | 49.451 | 3 |
| `kernel.chamfer.edges.12` | ui | 96.682 | `ffi.occt.allEdges` | 49.126 | 3 |
| `kernel.chamfer.edges.4` | ui | 70.048 | `ffi.occt.allEdges` | 49.161 | 3 |
| `kernel.coil.1` | ui | 15.531 | `ffi.occt.coilProfile` | 15.504 | 1 |
| `kernel.coil.12` | ui | 47.526 | `ffi.occt.coilProfile` | 47.497 | 1 |
| `kernel.coil.4` | ui | 23.333 | `ffi.occt.coilProfile` | 23.306 | 1 |
| `kernel.extrude.arcs.12` | ui | 0.729 | `ffi.occt.extrudeProfileArcs` | 0.722 | 1 |
| `kernel.extrude.arcs.120` | ui | 7.207 | `ffi.occt.extrudeProfileArcs` | 7.152 | 1 |
| `kernel.extrude.arcs.48` | ui | 2.855 | `ffi.occt.extrudeProfileArcs` | 2.833 | 1 |
| `kernel.extrude.holes` | ui | 3.468 | `ffi.occt.extrudeProfile` | 3.314 | 1 |
| `kernel.extrude.plain` | ui | 2.285 | `ffi.occt.extrudeProfile` | 2.205 | 1 |
| `kernel.extrude.sweep` | ui | 29.128 | `ffi.occt.extrudeProfileArcs` | 28.902 | 1 |
| `kernel.extrude.taper` | ui | 125.287 | `ffi.occt.extrudeProfileArcs` | 125.154 | 1 |
| `kernel.fillet` | ui | 71.561 | `ffi.occt.allEdges` | 49.205 | 3 |
| `kernel.fillet.edges.1` | ui | 60.875 | `ffi.occt.allEdges` | 49.307 | 3 |
| `kernel.fillet.edges.12` | ui | 97.426 | `ffi.occt.allEdges` | 49.281 | 3 |
| `kernel.fillet.edges.4` | ui | 71.631 | `ffi.occt.allEdges` | 49.487 | 3 |
| `kernel.fillet.radius` | ui | 853.192 | `ffi.occt.filletEdges` | 699.591 | 3 |
| `kernel.loft.2` | ui | 5.997 | `ffi.occt.loftSections` | 5.956 | 1 |
| `kernel.loft.4` | ui | 8.223 | `ffi.occt.loftSections` | 8.178 | 1 |
| `kernel.loft.8` | ui | 10.292 | `ffi.occt.loftSections` | 10.241 | 1 |
| `kernel.loft.ruled` | ui | 43.219 | `ffi.occt.loftSections` | 43.134 | 1 |
| `kernel.mesh.complexity.12` | ui | 2.193 | `ffi.occt.meshCreate` | 1.393 | 3 |
| `kernel.mesh.complexity.120` | ui | 20.300 | `ffi.occt.meshCreate` | 12.856 | 3 |
| `kernel.mesh.complexity.48` | ui | 8.138 | `ffi.occt.meshCreate` | 5.135 | 3 |
| `kernel.mesh.repeat` | ui | 24.762 | `ffi.occt.meshCreate` | 21.790 | 3 |
| `kernel.mesh.sweep` | ui | 24.225 | `ffi.occt.meshCreate` | 15.273 | 3 |
| `kernel.mirror.120` | ui | 67.762 | `ffi.occt.mirror` | 44.399 | 3 |
| `kernel.mirror.24` | ui | 13.479 | `ffi.occt.mirror` | 8.856 | 3 |
| `kernel.query.cheap` | ui | 14.706 | `ffi.occt.extrudeProfileArcs` | 7.141 | 3 |
| `kernel.query.edgeInfoOne` | ui | 66.929 | `kernel.edgeInfo1` | 59.725 | 2 |
| `kernel.query.edgeInfoScale.120` | ui | 68.148 | `kernel.edgeInfoScale.120` | 60.632 | 2 |
| `kernel.query.edgeInfoScale.24` | ui | 13.980 | `kernel.edgeInfoScale.24` | 12.480 | 2 |
| `kernel.query.edgeInfoScale.240` | ui | 136.642 | `kernel.edgeInfoScale.240` | 121.437 | 2 |
| `kernel.query.edgeInfoScale.60` | ui | 33.840 | `kernel.edgeInfoScale.60` | 30.103 | 2 |
| `kernel.rayHits` | ui | 16.967 | `kernel.rayHit` | 14.077 | 3 |
| `kernel.revolve.12` | ui | 0.562 | `ffi.occt.revolveProfile` | 0.554 | 1 |
| `kernel.revolve.120` | ui | 5.551 | `ffi.occt.revolveProfile` | 5.478 | 1 |
| `kernel.revolve.48` | ui | 2.193 | `ffi.occt.revolveProfile` | 2.164 | 1 |
| `kernel.revolve.angle` | ui | 9.508 | `ffi.occt.revolveProfile` | 9.406 | 1 |
| `kernel.sweep.12` | ui | 90.098 | `ffi.occt.sweepProfile` | 89.904 | 1 |
| `kernel.sweep.48` | ui | 393.002 | `ffi.occt.sweepProfile` | 392.266 | 1 |
| `kernel.sweep.path` | ui | 616.594 | `ffi.occt.sweepProfile` | 614.569 | 1 |
| `kernel.sweep.twist` | ui | 177.968 | `ffi.occt.sweepProfile` | 176.824 | 1 |
| `kernel.transform` | ui | 15.143 | `ffi.occt.transform` | 11.716 | 2 |
| `kernel.unify` | ui | 1.657 | `ffi.occt.fuse` | 1.459 | 3 |
| `modify.extend` | ui | 0.105 | `modify.extendEntity` | 0.096 | 2 |
| `modify.intersections.10` | ui | 0.093 | `modify.intersectionsWithOthers` | 0.081 | 1 |
| `modify.intersections.20` | ui | 0.364 | `modify.intersectionsWithOthers` | 0.331 | 1 |
| `modify.intersections.4` | ui | 0.016 | `modify.intersectionsWithOthers` | 0.009 | 1 |
| `modify.offsetChain` | ui | 0.174 | `modify.offsetChainAt` | 0.151 | 1 |
| `modify.offsetSingle` | ui | 0.174 | `modify.offsetEntity` | 0.001 | 2 |
| `modify.split` | ui | 0.056 | `modify.splitEntity` | 0.050 | 1 |
| `modify.stretch` | ui | 0.101 | `modify.stretchGeo` | 0.082 | 1 |
| `modify.transform.128` | ui | 0.190 | `modify.transformGeo` | 0.171 | 1 |
| `modify.transform.24` | ui | 0.040 | `modify.transformGeo` | 0.021 | 1 |
| `modify.trim.10` | ui | 0.062 | `modify.trimEntity` | 0.056 | 2 |
| `modify.trim.20` | ui | 0.224 | `modify.trimEntity` | 0.209 | 2 |
| `modify.trim.4` | ui | 0.013 | `modify.trimEntity` | 0.011 | 2 |
| `modify.trimCutAway` | ui | 0.062 | `modify.trimCutAway` | 0.053 | 1 |
| `quality.caches` | ui | 4.772 | `—` | 0.000 | 0 |
| `quality.frameBudget` | ui | 22.385 | `solve.total` | 22.271 | 4 |
| `quality.memoryPerEntity` | ui | 0.167 | `—` | 0.000 | 0 |
| `quality.memoryPerSolid` | ui | 95.586 | `ffi.occt.meshCreate` | 60.305 | 3 |
| `quality.variance` | ui | 48.257 | `ffi.occt.extrudeProfileArcs` | 25.370 | 6 |
| `ramp.analyze.entities` | ui | 280.232 | `sketch.analyze` | 277.996 | 11 |
| `ramp.drag.entities` | ui | 39.822 | `solve.total` | 39.640 | 12 |
| `ramp.kernel.allEdges` | ui | 3278.966 | `ffi.occt.allEdges` | 3252.656 | 9 |
| `ramp.kernel.boolean` | ui | 392.333 | `ffi.occt.fuse` | 340.000 | 9 |
| `ramp.kernel.build` | ui | 55.698 | `ffi.occt.extrudeProfileArcs` | 54.763 | 10 |
| `ramp.kernel.mesh` | ui | 155.999 | `ffi.occt.meshCreate` | 99.239 | 12 |
| `ramp.solids` | ui | 386.594 | `ffi.occt.meshCreate` | 242.942 | 10 |
| `ramp.solve.density` | ui | 37.588 | `solve.total` | 37.442 | 10 |
| `ramp.solve.entities` | ui | 12.098 | `solve.total` | 11.989 | 14 |
| `solve.drag60` | ui | 18.786 | `solve.total` | 18.712 | 4 |
| `solve.fromViolated` | ui | 2.843 | `solve.total` | 2.789 | 4 |
| `solve.overConstrained` | ui | 663.581 | `solve.total` | 663.521 | 5 |
| `solve.sweep.24` | ui | 3.996 | `solve.total` | 3.966 | 4 |
| `solve.sweep.64` | ui | 21.243 | `solve.total` | 21.195 | 4 |
| `solve.sweep.8` | ui | 0.854 | `solve.total` | 0.834 | 4 |
| `tools.buildAll` | ui | 6.709 | `tool.build.eqCurve` | 3.499 | 26 |
| `tools.chamfer2d` | ui | 0.043 | `tools.chamferInventor` | 0.002 | 1 |
| `tools.ellipseEval` | ui | 0.256 | `ellipse.curve` | 0.201 | 1 |
| `tools.fillet2d` | ui | 0.080 | `tools.filletInventor` | 0.051 | 1 |
| `tools.filletMaxRadius` | ui | 0.498 | `tools.filletMaxRadius` | 0.491 | 1 |
| `tools.freehand.1024` | ui | 4.840 | `freehand.fit` | 2.444 | 4 |
| `tools.freehand.256` | ui | 0.443 | `freehand.fit` | 0.210 | 4 |
| `tools.freehand.64` | ui | 0.077 | `freehand.fit` | 0.030 | 4 |
| `tools.spline.16` | ui | 0.035 | `—` | 0.000 | 2 |
| `tools.spline.4` | ui | 0.015 | `—` | 0.000 | 2 |
| `tools.spline.64` | ui | 0.120 | `tool.spline.cv` | 0.045 | 2 |
| `tools.splineEval.16` | ui | 8.888 | `spline.curveFor` | 8.819 | 1 |
| `tools.splineEval.4` | ui | 1.678 | `spline.curveFor` | 1.609 | 1 |
| `tools.splineEval.64` | ui | 59.457 | `spline.curveFor` | 59.381 | 1 |
| `ui.drag60` | ui | 38.425 | `2d.paint` | 38.154 | 25 |
| `ui.engineRebuild` | ui | 0.002 | `—` | 0.000 | 2 |
| `ui.paint.sweep.24` | ui | 2.643 | `2d.paint` | 2.518 | 20 |
| `ui.paint.sweep.64` | ui | 6.749 | `2d.paint` | 6.550 | 20 |
| `ui.paint.sweep.8` | ui | 1.028 | `2d.paint` | 0.936 | 20 |
| `ui.snapHover` | ui | 7.086 | `2d.pickEntity` | 5.962 | 2 |


### E. Ramp families with local exponents

Ramps use fine steps so a **knee** is visible. A fit through three points assumes the curve *is* a power law and averages away anything that is not one; the local exponent between neighbouring rungs does not. A constant local exponent means a clean power law; a jump means a threshold, and the rung it jumps at is the size that matters.

#### `ramp.allEdges` — overall k = 1.94, R² = 0.9998, CI [1.91, 1.96]

| size | mean ms | local exponent vs previous |
| ---: | ---: | ---: |
| 12 | 14.1250 | — |
| 24 | 50.7965 | 1.85 |
| 36 | 111.1620 | 1.93 |
| 48 | 195.9385 | 1.97 |
| 72 | 433.7490 | 1.96 |
| 96 | 765.8865 | 1.98 |
| 144 | 1708.5640 | 1.98 |

#### `ramp.analyze` — overall k = 2.30, R² = 0.9908, CI [2.15, 2.46]

| size | mean ms | local exponent vs previous |
| ---: | ---: | ---: |
| 8 | 0.0655 | — |
| 16 | 0.2055 | 1.65 |
| 24 | 0.4335 | 1.84 |
| 32 | 0.7820 | 2.05 |
| 48 | 1.7910 | 2.04 |
| 64 | 5.8005 | 4.08 |
| 96 | 13.5030 | 2.08 |
| 128 | 22.5620 | 1.78 |
| 192 | 71.9690 | 2.86 |
| 256 | 156.0690 | 2.69 |

#### `ramp.boolean` — overall k = 1.07, R² = 0.9974, CI [1.03, 1.12]

| size | mean ms | local exponent vs previous |
| ---: | ---: | ---: |
| 12 | 10.0130 | — |
| 24 | 19.2155 | 0.94 |
| 36 | 29.1815 | 1.03 |
| 48 | 39.8680 | 1.08 |
| 72 | 62.8795 | 1.12 |
| 96 | 87.6250 | 1.15 |
| 144 | 143.9080 | 1.22 |

#### `ramp.build` — overall k = 0.99, R² = 0.9994, CI [0.97, 1.01]

| size | mean ms | local exponent vs previous |
| ---: | ---: | ---: |
| 12 | 0.7875 | — |
| 24 | 1.4695 | 0.90 |
| 36 | 2.1710 | 0.96 |
| 48 | 2.8870 | 0.99 |
| 72 | 4.3590 | 1.02 |
| 96 | 5.8170 | 1.00 |
| 144 | 8.7375 | 1.00 |
| 192 | 11.7205 | 1.02 |
| 288 | 17.8935 | 1.04 |

#### `ramp.density` — overall k = 1.79, R² = 0.9971, CI [1.69, 1.88]

| size | mean ms | local exponent vs previous |
| ---: | ---: | ---: |
| 1 | 0.4515 | — |
| 2 | 1.3365 | 1.57 |
| 3 | 2.7040 | 1.74 |
| 4 | 4.7405 | 1.95 |
| 6 | 10.2770 | 1.91 |
| 8 | 18.2890 | 2.00 |

#### `ramp.drag` — overall k = 0.96, R² = 0.6213, CI [0.36, 1.55]

| size | mean ms | local exponent vs previous |
| ---: | ---: | ---: |
| 8 | 2.3015 | — |
| 16 | 0.5695 | -2.01 |
| 24 | 0.9675 | 1.31 |
| 32 | 1.4200 | 1.33 |
| 48 | 5.3455 | 3.27 |
| 64 | 4.5905 | -0.53 |
| 96 | 8.8750 | 1.63 |
| 128 | 14.8935 | 1.80 |

#### `ramp.mesh` — overall k = 0.99, R² = 0.9992, CI [0.97, 1.01]

| size | mean ms | local exponent vs previous |
| ---: | ---: | ---: |
| 12 | 2.2030 | — |
| 24 | 4.1890 | 0.93 |
| 36 | 6.0535 | 0.91 |
| 48 | 8.0175 | 0.98 |
| 72 | 12.1280 | 1.02 |
| 96 | 15.8690 | 0.93 |
| 144 | 24.4695 | 1.07 |
| 192 | 33.0905 | 1.05 |
| 288 | 49.9820 | 1.02 |

#### `ramp.solids` — overall k = 0.99, R² = 0.9999, CI [0.98, 1.00]

| size | mean ms | local exponent vs previous |
| ---: | ---: | ---: |
| 1 | 8.0660 | — |
| 2 | 15.6530 | 0.96 |
| 4 | 32.0270 | 1.03 |
| 6 | 47.0560 | 0.95 |
| 8 | 63.6840 | 1.05 |
| 12 | 93.2340 | 0.94 |
| 16 | 126.1850 | 1.05 |

#### `ramp.solve` — overall k = 1.34, R² = 0.9498, CI [1.13, 1.56]

| size | mean ms | local exponent vs previous |
| ---: | ---: | ---: |
| 8 | 0.0760 | — |
| 16 | 0.0750 | -0.02 |
| 24 | 0.1185 | 1.13 |
| 32 | 0.1685 | 1.22 |
| 48 | 0.3045 | 1.46 |
| 64 | 0.4810 | 1.59 |
| 96 | 0.9365 | 1.64 |
| 128 | 1.5315 | 1.71 |
| 192 | 3.1790 | 1.80 |
| 256 | 5.3740 | 1.82 |


### F. All fitted cost models

**32 sweep families.** Dependent variable: dominant span total. Families with N = 2 yield a slope with zero residual degrees of freedom — R² is 1.000 by construction and no confidence interval exists, so they support **no scaling claim**.

| family | N | k | R² | 95 % CI | range ms |
| --- | ---: | ---: | ---: | ---: | ---: |
| `modify.intersections` | 3 | 2.25 | 0.9979 | [2.05, 2.45] | 0.009–0.331 |
| `analysis.sweep` | 3 | 2.24 | 0.9951 | [1.93, 2.55] | 0.204–21.817 |
| `kernel.allEdges.sweep` | 3 | 1.93 | 0.9999 | [1.89, 1.97] | 13.660–1169.668 |
| `app.provenance.newSurfaces` | 3 | 1.85 | 1.0000 | [1.84, 1.86] | 0.048–7.214 |
| `modify.trim` | 3 | 1.83 | 0.9996 | [1.76, 1.89] | 0.011–0.209 |
| `app.rebuildPart` | 3 | 1.71 | 0.9608 | [1.04, 2.39] | 3.778–75.160 |
| `tools.freehand` | 3 | 1.59 | 0.9956 | [1.38, 1.79] | 0.030–2.444 |
| `solve.sweep` | 3 | 1.55 | 0.9971 | [1.39, 1.72] | 0.834–21.195 |
| `app.pattern.occurrences.circular` | 3 | 1.35 | 0.9810 | [0.98, 1.72] | 0.020–0.850 |
| `tools.splineEval` | 3 | 1.30 | 0.9989 | [1.22, 1.39] | 1.609–59.381 |
| `modify.transform` | 2 | 1.25 | — | slope only (N=2) | 0.021–0.171 |
| `app.pattern.rect` | 3 | 1.17 | 0.9952 | [1.01, 1.33] | 0.046–1.172 |
| `kernel.boolean.complex` | 3 | 1.09 | 0.9987 | [1.01, 1.17] | 8.065–99.935 |
| `kernel.sweep` | 2 | 1.06 | — | slope only (N=2) | 89.904–392.266 |
| `app.pattern.occurrences.points` | 2 | 1.05 | — | slope only (N=2) | 0.016–0.069 |
| `app.provenance.faceSurfaces` | 3 | 1.01 | 1.0000 | [1.00, 1.02] | 0.090–1.386 |
| `kernel.mirror` | 2 | 1.00 | — | slope only (N=2) | 8.856–44.399 |
| `kernel.extrude.arcs` | 3 | 1.00 | 1.0000 | [0.98, 1.01] | 0.722–7.152 |
| `kernel.revolve` | 3 | 0.99 | 0.9999 | [0.98, 1.01] | 0.554–5.478 |
| `kernel.query.edgeInfoScale` | 4 | 0.99 | 0.9999 | [0.97, 1.01] | 12.480–121.437 |
| `kernel.mesh.complexity` | 3 | 0.96 | 0.9997 | [0.93, 1.00] | 1.393–12.856 |
| `ui.paint.sweep` | 3 | 0.93 | 0.9995 | [0.89, 0.98] | 0.936–6.550 |
| `app.pattern.occurrences` | 2 | 0.93 | — | slope only (N=2) | 0.017–0.062 |
| `constraints.infer` | 3 | 0.91 | 0.9928 | [0.76, 1.06] | 0.011–0.073 |
| `gear.curve` | 3 | 0.85 | 0.9981 | [0.78, 0.92] | 5.910–19.216 |
| `app.history` | 3 | 0.82 | 0.9900 | [0.66, 0.98] | 0.979–5.441 |
| `app.engineFill` | 2 | 0.69 | — | slope only (N=2) | 1.212–3.854 |
| `app.provenance.attribute` | 3 | 0.65 | 0.9502 | [0.36, 0.95] | 0.862–2.884 |
| `kernel.coil` | 3 | 0.44 | 0.9513 | [0.25, 0.64] | 15.504–47.497 |
| `kernel.loft` | 3 | 0.39 | 0.9905 | [0.32, 0.47] | 5.956–10.241 |
| `kernel.fillet.edges` | 3 | -0.00 | 0.0025 | [-0.00, 0.00] | 49.281–49.487 |
| `kernel.chamfer.edges` | 3 | -0.00 | 0.8770 | [-0.00, -0.00] | 49.126–49.451 |

<!-- END GENERATED APPENDIX -->

---

*Source: `bug20260811T104745`, build `cd961ee`, iPadOS 27.0, single device.
Sections 1–12 regenerable via `python3 ci/perf_report.py <bundle.zip>`;
section 14 via `python3 ci/perf_profile.py <bundle.zip>`. Fit statistics
(R², CI) computed as specified in §1.5.*
