# S14 — the sweep that does not build: the corner, the instrument, and the fix

**Session:** S14 (round three, `claude/perf-opt3-sweep`).
**Branch:** `claude/perf-opt3-sweep-rnw51l`, cut from `claude/perf-opt2` at
`cb1d183`.
**Owns:** `backend/occt/shim/**`, `backend/bench/**`, this file.
**Governing rules:** `OPTIMIZATION_PLAN_2.md`, `perf/findings/README.md`,
`OPTIMIZATION_PLAN.md` §2 for the prediction form.

---

## 0. The finding this session exists for

A device capture on 2026-08-24 (build `cb1d183`) ran S11's opt-in
`profile.*` tier for the first time. The numbers below are transcribed from the
session brief; **the capture itself is not in this repository**, so every device
figure in this file is a quotation, not something I can re-read.

`profile.sweep.segments` — an N-segment ring swept along a 16-span path:

| N | device | outcome |
| ---: | ---: | --- |
| 32 | 91 ms | ok |
| 128 | 1 253 ms | ok |
| 512 | 132 112 ms | ok |
| **1200** | **231 085 ms** | **FAILED** — `occt_sweep_profile: BRep_API: command not done` |
| 2048 | — | never ran; the ladder's 150 s budget wall stopped it |

`profile.sweep.spans` — the profile held at 512 segments, the PATH varied:

| spans | corners | device | outcome |
| ---: | ---: | ---: | --- |
| 1 | 0 | 94 ms | ok |
| 4 | 3 | 79 306 ms | ok |
| 16 | 15 | 132 093 ms | ok |
| 64 | 63 | 69 501 ms | **FAILED** (a time-to-failure, not a time-to-build) |

**The 1200 rung is a correctness defect with a performance defect wrapped around
it.** Four minutes and 940 MB of RSS produce no solid. Getting it to build is
the primary objective; making it quick is the second.

### 0.1 The fixture, in exact numbers

Both ladders come from `frontend/lib/perf_scenarios_profile.dart`:
`occt.sweepProfile([arcRing(segments, 6)], identityMat34(), arcPath(spans+1, 60))`.

* **profile** — `arcRing(n, 6)`: a regular n-gon of circumradius **6** in the
  XY plane, every bulge zero.
* **path** — `arcPath(n, 60)`: point *i* at `t = i/(n-1)`, `a = t·π/2`,
  `(18 sin a, 18 (1 − cos a), 60 t)`. A helix: a quarter-turn of radius 18 in
  XY while z rises linearly to 60. Constant speed, arc length **66.33**,
  radius of curvature **99.06** everywhere.

Derived, and needed by every prediction below:

| spans | segment length | total polyline turning | max corner |
| ---: | ---: | ---: | ---: |
| 1 | 65.18 | 0° | 0° |
| 4 | 16.56 | 28.472° | 9.491° |
| 16 | 4.145 | 35.944° | 2.396° |
| 64 | 1.036 | 37.764° | 0.599° |

Two things to notice before reading any hypothesis into the discontinuity:

1. **The corners are shallow and the miter is not degenerate.** At 16 spans a
   corner turns 2.4°; the section's outer edge is displaced by
   `6·tan(1.2°) = 0.126`, against a segment length of 4.145. Nothing overlaps.
   Whatever is expensive, it is not the miter running out of room.
2. **Total turning is nearly constant across the ladder** — 28.5°, 35.9°,
   37.8° — because it is a fixed curve sampled at three densities. The corner
   *count* varies 5×; the total turning varies 1.26×. **The spans ladder
   therefore separates "per corner" from "per degree turned", and that is the
   most useful thing in the whole capture.**

### 0.2 Two structural facts, read from source before any measurement

* `spine_from_points` (`backend/occt/shim/occt_capi.cpp:3478`) builds a
  `BRepBuilderAPI_MakePolygon`. **Every spine that reaches the kernel is a
  polyline**, whatever the user drew.
* `occt_sweep_profile` sets `mk.SetTransitionMode(BRepBuilderAPI_RightCorner)`
  unconditionally. That mode exists to treat corners and is inert without them.

And `sampleEntity(arcSamples: 64)` flattens an arc into 64 spans regardless of
the arc's angle (S11 §1.1, `CROSS-SESSION.md` S11-5), so **the 64-span rung —
the one that failed — is what the app does when a user sweeps along an arc.**

---

## 1. Pre-registration, round 1 — the mechanism

**Registered before the instrument was written and before a line of the shim
was touched.** These are predictions about *where the time is*, not about a
fix; the fix's own predictions are registered separately in §3, after these are
adjudicated.

Lane C rules apply (`perf/findings/S1-bench.md`, `backend/bench/README.md`):
relative costs, exponents, ratios and allocation counts may be read from a
desktop run; **absolute milliseconds may not be read as iPad milliseconds.**
Every prediction below is therefore stated as a ratio.

### Prediction P1 — the time is inside `MakePipeShell::Build`, not in the tail

```
Target        : occt_sweep_profile at 512 segments x 16 spans, broken into
                phases: profile wires, spine, mk.Build(), mk.MakeSolid(),
                ShapeUpgrade_UnifySameDomain, wrap.
Baseline      : the whole call, 132 093 ms on device (§0). No phase has ever
                been measured separately, on any machine.
Mechanism     : finish_pipe runs UnifySameDomain over the WHOLE result
                unconditionally. On an 8 194-face shape that is whole-shape
                work, and this project has twice found whole-shape-per-item
                work in edge_info (S2, S6). It is a live candidate and it is
                the one the session brief names.
Change        : none. Instrument only.
Predicted     : Build() >= 90 % of the call.  UnifySameDomain <= 5 %.
Derivation    : the 1-span rung is 94 ms for a 512-face result, and that 94 ms
                ALREADY CONTAINS a UnifySameDomain over 514 faces. So
                Unify(514) < 94 ms, and 8 194 faces is 15.9x that shape.
                  linear in faces   : Unify(8194) < 1.5 s  = 1.1 % of 132 s
                  quadratic in faces: Unify(8194) < 23.9 s = 18 % of 132 s
                The 5 % ceiling asserts the linear end of that bracket. It is
                the strong form on purpose: a prediction that only excludes
                the quadratic end excludes almost nothing.
Falsifiable by: any phase other than Build() taking more than 10 % of the call
                at 512x16. If UnifySameDomain is above 18 % the arithmetic
                above is wrong at both ends and the tail is the story.
Risk          : the bench's phase breakdown is a REPLICA of the shim pipeline,
                not the shim itself, so it can only be believed if the sum of
                the phases matches the shim's own occt_sweep_profile within a
                few per cent on the same fixture. That check is part of the
                instrument and its result is reported whichever way it falls.
```

### Prediction P2 — the step is corner treatment, and it is ~99 % of the call

```
Target        : the 843x step between 1 span (94 ms) and 4 spans (79 306 ms)
                at a fixed 512-segment profile.
Baseline      : §0's spans ladder.
Mechanism     : RightCorner is the only work in the pipeline that exists
                because of corners. In OCCT it reaches BRepFill_Sweep's corner
                treatment, which trims each pair of adjacent swept shells
                against each other; each shell here carries 512 lateral faces.
Change        : none. Instrument only: the bench runs the same fixture with
                BRepBuilderAPI_Transformed, which does no corner trimming.
Predicted     : with corner trimming removed, 512x16 costs at most 5x the
                face-proportional extrapolation from the 1-span rung
                — i.e. a >= 50x reduction against RightCorner.
Derivation    : 1 span = 94 ms for 514 faces = 0.183 ms/face. 512x16 is 8 194
                faces, so face-proportional cost is 1.50 s. Measured 132.09 s
                is 88x that; the excess, 130.6 s, is 98.9 % of the call and is
                not proportional to output. If it is corner work, removing it
                leaves <= 5 x 1.50 s = 7.5 s, and 132.09 / 7.5 = 17.6x is the
                weakest reduction consistent with the model. The prediction
                takes 50x as the claim and 17.6x as the refutation floor.
Falsifiable by: Transformed mode costing more than a fifth of RightCorner's
                time on the same fixture. That would say the corner treatment
                is not the step and would send this session back to the phase
                table.
Risk          : Transformed may FAIL on this fixture (the shim's own comment
                says it fails outright on sharp corners). A failure is a
                result, not a missing measurement: it would mean the cheap
                mode is not reachable and the fix must be the spine instead.
```

### Prediction P3 — the cost is per degree turned, not per corner

```
Target        : profile.sweep.spans, 512 segments, spans 1 / 2 / 4 / 8 / 16 / 64.
Baseline      : device 94 ms / — / 79 306 ms / — / 132 093 ms / failed.
Mechanism     : if corner treatment cost were a fixed price per corner, 3 -> 15
                corners would cost 5x. It costs 1.67x. If it were proportional
                to output faces it would also cost 4x. The quantity that is
                nearly invariant across the ladder is the TOTAL TURNING, and
                the amount of interpenetration two adjacent shells have to be
                trimmed out of is proportional to the angle between them.
Change        : none. Instrument only.
Predicted     : a two-term model  cost = A x corners + B x degrees  fits the
                two measured rungs, and B x degrees dominates:
                  A = 2 851 ms/corner, B = 2 484.9 ms/degree (device units)
                  A x corners share at 16 spans: 42.8 s of 132.1 s = 32 %
                  B x degrees share at 16 spans: 89.3 s of 132.1 s = 68 %
                In RATIOS, which is what Lane C may adjudicate, taking the
                16-span rung as 1.000:
                  spans   2 -> 0.367     spans   8 -> 0.781
                  spans   4 -> 0.600     spans  32 -> 1.368
                The sharp claim is the 2-span rung: ONE corner costs 37 % of
                what FIFTEEN corners cost.
Derivation    : solve  3A + 28.472B = 79 306  and  15A + 35.944B = 132 093
                (turning angles from §0.1) -> B = 2 484.9, A = 2 851.
                Two points, two parameters, so the FIT is not evidence; the
                INTERPOLATION to 2 and 8 spans and the extrapolation to 32 are.
Falsifiable by: the bench's 2-span rung landing below 0.15 or above 0.60 of its
                16-span rung. Below 0.15 means the cost really is per corner
                (a pure per-corner model predicts 1/15 = 0.067); above 0.60
                means something worse than either model.
Risk          : the desktop's constant differs from the device's, which is
                exactly why this is registered as a ratio. If the bench
                reproduces neither the step nor the sublinearity, the bench is
                measuring something else and nothing else in this file may be
                believed.
```

### Prediction P4 — the 1200-segment failure is `Build()` returning not-done

```
Target        : the FAILING rung, 1200 segments x 16 spans.
Baseline      : "occt_sweep_profile: BRep_API: command not done" after
                231 085 ms. That string is the shim's own text for
                !mk.IsDone() ... actually finish_pipe writes "the sweep failed
                (path too tight for the section?)" for that case, so the
                quoted message is an OCCT Standard_Failure caught by
                OCCT_CATCH, not the IsDone branch.
Mechanism     : an exception escaping the pipeline is thrown from inside
                BRepFill's corner trimming when the trimmed shell cannot be
                closed, or from BRepBuilderAPI when a downstream step is asked
                for a result that was never built.
Predicted     : the bench reproduces a FAILURE at 1200x16 (any of: exception,
                IsDone false, MakeSolid false, no material), and the failure
                disappears when corner trimming is removed.
Derivation    : none is possible — this is a reproduction claim, not a number.
                It is registered because a fix that makes a failing case build
                must first be shown to fail.
Falsifiable by: 1200x16 building cleanly on the desktop. That would mean the
                failure is resource-dependent (940 MB of RSS on a device with
                less headroom than this container) rather than geometric, and
                the fix would have to be argued on memory rather than on
                topology.
Risk          : desktop OCCT is 7.9.3 built here with the same flags as CI, so
                the kernel matches the device's. The machine does not.
```

---

*(§2 — what the instrument measured — and §3 — the fix and its own
pre-registration — are written after this file is committed.)*

---

## 2. What the instrument measured

### 2.0 The instrument, and what it cost to have one

There was no OCCT in this container and no sweep op in Lane C, so both were
built: OCCT 7.9.3 from the pinned submodule with `occt-build.yml`'s own
configure flags (about 100 minutes on four cores), then the sweep ladders in
`backend/bench/**` and a scratch probe for the experiments that are not worth
keeping. **Flutter is present too** (3.35.4, downloaded into the scratchpad),
so `flutter analyze` and `flutter test` were run here rather than deferred to
CI — see §6.

Every absolute millisecond below is a **desktop** millisecond on a shared
four-core container, and `backend/bench/README.md`'s table binds: ratios,
exponents and structural facts may be read across to the device; absolute times
may not. The container is roughly **3.4× slower than the iPad** on this
operation (512 segments × 16 spans: 447 118 ms here against the device's
132 112 ms), which is itself only a sanity check, not a calibration.

Some of the runs below overlapped on a four-core box, so individual absolute
times carry contention noise. Every *comparison* quoted as a ratio was taken
from runs of the same fixture under the same conditions, and the headline
ladders are re-measured cleanly by the benchmark in §5.

### 2.1 P1 — HELD. The time is in `Build()`, and the tail is 2.3 %

The replica of `finish_pipe`'s pipeline agrees with the shipped entry point to
**0.14 %** (7 260.6 ms against 7 250.2 ms at 128 segments × 16 spans), which is
what licences the phase table:

| phase | ms | share |
| --- | ---: | ---: |
| profile wire | 0.3 | 0.004 % |
| spine | 0.0 | — |
| **`MakePipeShell::Build()`** | **7 010.7** | **96.6 %** |
| `MakeSolid()` + `Shape()` | 84.0 | 1.2 % |
| `ShapeUpgrade_UnifySameDomain` | 165.6 | 2.3 % |

Predicted: Build ≥ 90 %, Unify ≤ 5 %. Measured 96.6 % and 2.3 %. **P1 holds at
both ends.**

And one thing worth saying plainly, because the brief named `UnifySameDomain`
as a candidate: on this shape it **merges nothing**. With it the result has
2 050 faces; without it, 2 050 faces. It costs 165 ms to change nothing. That
is a real if small waste, it is NOT the sweep's problem, and I did not remove
it — a face merge that is a no-op on a ring is not a no-op on a profile with
collinear runs, which is most real profiles.

### 2.2 P2 — SPLIT. The corner treatment is the step, but the size of the win
depends on the rung, and at the rung I registered it the number was wrong

P2 predicted "at most 5× the face-proportional extrapolation, i.e. a ≥ 50×
reduction". Removing corner treatment (`BRepBuilderAPI_Transformed`) gives:

| rung | shipped | Transformed | reduction |
| --- | ---: | ---: | ---: |
| 128 seg × 16 spans | 7 260.6 ms | 415.5 ms | **17.5×** |
| 512 seg × 16 spans | 447 118 ms | 2 314.4 ms | **193×** |
| 1200 seg × 16 spans | (see §2.5) | 6 104.7 ms | — |

* The **face-proportional clause HELD, easily**: the 1-span rung at 128
  segments is 62.5 ms for 130 faces = 0.481 ms/face, so 2 050 faces
  face-proportional is 985 ms, and Transformed came in at 415.5 ms — 0.42× of
  it, against a ceiling of 5×.
* The **"≥ 50×" clause is REFUTED at 128 segments** (17.5×) and vindicated at
  512 (193×). I registered one number for a quantity that turns out to depend
  strongly on the rung, and the rung I could reach cheaply was not the rung the
  device measured. That is the prediction being wrong, not the mechanism.

The reason the reduction grows is §2.4: the shipped path is nearly **cubic** in
profile segments and the corner-free paths are nearly **linear**, so their
ratio grows as roughly n².

### 2.3 P3 — HELD, with the point estimate 46 % off. The cost is per corner AND
per degree turned, and neither term alone fits

The spans ladder at 128 segments, through the shipped entry point:

| spans | corners | total turning | ms | ÷ the 16-span rung | P3 predicted |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 1 | 0 | 0° | 62.5 | 0.009 | 0 |
| 2 | 1 | 18.379° | 1 824.7 | **0.251** | 0.367 |
| 4 | 3 | 28.472° | 3 442.4 | 0.474 | 0.600 |
| 8 | 7 | 33.481° | 4 661.9 | 0.642 | 0.781 |
| 16 | 15 | 35.944° | 7 266.1 | 1.000 | 1.000 |
| 32 | 31 | 37.160° | 12 263.3 | 1.688 | 1.368 |
| 64 | 63 | 37.764° | 21 220.7 | 2.920 | 2.070 |

**The step reproduces**: one corner turns 62.5 ms into 1 824.7 ms — **29× for a
single 18° joint**, with no change in the profile at all.

P3's refutation window was a 2-span rung below 0.15 or above 0.60. Measured
**0.251**, so P3 survives — and its central claim survives well: one corner
costs a quarter of what fifteen cost, where a pure per-corner model says
1/15 = 0.067. But the registered point estimate of 0.367 was **46 % high**, and
it was derived from the device's two rungs at 512 segments; the split between
the two terms is not the same at 128.

Refitting the two-term model on all six bench rungs (subtracting the corner-free
1-span rung as the baseline):

```
cost − 62.5 ms  =  287.43 ms × corners  +  82.73 ms × degrees turned
```

fits every rung to within **±5 %** (worst 0.952, best 1.003). Neither single
term does: per-corner alone spans 0.20–1.06 across the ladder, per-degree alone
spans 0.50–2.94. **Both terms are real**, which is the structural claim P3 was
making, and it is now measured on six points rather than fitted through two.

### 2.4 The exponent, and the thing nobody had measured: it is cubic

`occt_sweep_profile` against profile segments at a fixed 16-span path:

| segments | shipped | ratio to previous | local k |
| ---: | ---: | ---: | ---: |
| 32 | 445.9 ms | | |
| 128 | 7 250.2 ms | 16.3× over 4× | **2.00** |
| 512 | 447 118 ms | 61.7× over 4× | **2.97** |

Two rungs of a fit are not a fit, but the *local* exponents are unambiguous and
they are getting worse: quadratic at the bottom of the ladder, cubic at the
top. The corner-free variants over the same range sit near 1:

| variant | 64 | 128 | 512 | 1200 | 2048 | local k, 128→512 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| smooth spine | 183.1 | 439.7 | 1 696.2 | 4 811.8 | 9 772.6 | **0.98** |
| Transformed | — | 415.5 | 2 314.4 | 6 104.7 | — | **1.24** |

That is the whole finding in one line: **the corner treatment turns a linear
sweep into a cubic one**, and everything else follows from it.

### 2.5 P4 — the failing regime, and it is worse than a failure

P4 predicted the bench would reproduce a failure at 1200 × 16. What the bench
found first is worse, and it was found on a rung nobody had looked at:

```
$ probe shim 64 64          # 64-segment ring, 64-span sampled arc
free(): invalid next size (fast)
Aborted (SIGABRT)
```

**A 64-segment profile swept along a 64-span sampled arc corrupts the heap and
aborts the process, through the shipped `occt_sweep_profile` entry point.** Not
an exception — `OCCT_CATCH` never runs, the shim's `OSD::SetSignal` handler
never runs, and glibc kills the process. In the app that is a crash with no log
line after it.

And 64 spans is not exotic. `sampleEntity(arcSamples: 64)` produces **exactly
64 spans for every arc and circle in the application**, whatever its angle
(S11-5). Any sweep along an arc is one profile-size away from this.

One rung below it, the shipped path does not crash — it lies:

| fixture | shipped | smooth spine | analytic |
| --- | ---: | ---: | ---: |
| 64 seg × 16 spans | 6 774.9447, valid | 6 774.9153, valid | 6 774.9447 |
| 64 seg × 32 spans | **7 490.0386, INVALID** | 6 774.9447, valid | 6 774.9447 |
| 64 seg × 64 spans | **process abort** | 6 774.9510, valid | 6 774.9447 |

**At 32 spans it returns a solid that is 10.6 % too large and fails
`BRepCheck_Analyzer`, in 2.4 seconds, with no error and no warning.** Nothing
in the shim checks validity on this path, so the app would accept it.

The threshold has a geometric explanation that the fixture makes exact. The
section is a ring of radius 6 lying in the XY plane while the path's initial
tangent is 25.23° off Z, so the section's own extent ALONG the path is
6·sin 25.23° = **2.56**. The span length is 66.33/spans: 4.15 at 16 spans,
**2.07 at 32**, 1.04 at 64. The regime turns bad exactly where the span becomes
shorter than the section's extent along it — i.e. where a corner's two shells
no longer merely touch but pass through each other. That is a real user
situation (a 12 mm bar swept along a 36 mm-radius arc), not a synthetic one.

*(P4's own rung, 1200 × 16 through the shipped path, was still running when
this section was written; §5 records how it ended.)*

### 2.6 The levers, measured — and two of them are refuted

At 128 segments × 16 spans, all through the same replica:

| lever | ms | faces | volume | valid? | verdict |
| --- | ---: | ---: | ---: | :-: | --- |
| shipped (RightCorner, polyline) | 7 260.6 | 2 050 | 6 783.1153 | yes | the baseline |
| **`UnifySameDomain` removed** | 7 262.6 | 2 050 | 6 783.1153 | yes | **no effect — refuted as a target** |
| `RoundCorner` | 2 014.4 | 3 970 | 6 783.0272 | **NO** | refuted |
| **`angmin` deadband raised to 5°** | 944.5 | 2 050 | **8 982.6281** | **NO** | **refuted — the shape is 32 % too big** |
| `Transformed` | 415.5 | 2 050 | 6 783.1153 | yes | works here |
| **smooth (C2 B-spline) spine** | **439.7** | **130** | 6 783.0858 | yes | **works, and 15.8× fewer faces** |

Two of these deserve their own paragraph because they were live candidates.

**The deadband is refuted, and this matters because it was the obvious fix.**
`BRepOffsetAPI_MakePipeShell::SetTransitionMode` hard-codes `angmin = 1.0e-2`
rad = **0.573°**, and `BRepFill_Sweep::PerformCorner` skips a joint shallower
than that ("This is not a corner"). Our 64-span rung's joints are **0.599°** —
just above it. Widening that deadband so shallow joints are skipped looks
irresistible and it produces **rubbish**: at 5° the solid is 32 % too big and
invalid. An untreated corner does not disappear, it leaves the two adjacent
shells passing through each other. Measured, not assumed.

**`Transformed` cannot simply be switched on**, and the shim's own comment was
right. On the L-path of smoke scenario [30] — a 10×10 square, 40 up then 30
across, a 90° joint:

| mode | volume | faces | valid? |
| --- | ---: | ---: | :-: |
| RightCorner (shipped) | **6 000.000000** (analytic) | 10 | yes |
| RoundCorner | 6 000.000000 | 10 | yes |
| **Transformed** | **3 200.000000** | 10 | **NO** |

Swept the same way at shallower joints it is fine, and the two converge:

| joint | RightCorner | Transformed | difference |
| ---: | ---: | ---: | ---: |
| 90° | 6 000.000 | 3 200.000 INVALID | −46.7 % |
| 45° | 6 585.786 | 6 121.320 | −7.1 % |
| 15° | 6 868.348 | 6 897.777 | +0.43 % |
| 5.625° | 6 950.873 | 6 985.554 | +0.50 % |
| 2° | 6 982.545 | 6 998.172 | +0.22 % |

### 2.7 The control that needed no new surface: the coil already does it right

`occt_coil_profile` sweeps its section along a **`Geom_CylindricalSurface`
helix — one analytic edge**, and sets no transition mode at all. It is the same
operation with a spine that is a curve instead of a sample of one, it is in the
shipped shim today, and it is not slow. The sweep's spine is a polyline for one
reason only: `spine_from_points` is handed points, because
`resolvePath`/`sketchCurve` flattened the curve before the kernel ever saw it.

### 2.8 Volume is NOT a discriminating invariant for a sweep — and an identity
I can use but cannot derive

The shipped mitered sweep and the `Transformed` sweep at 128 × 16 have volumes
equal to **1.3e-14 relative** — and they are **different solids**: the
symmetric difference is **4.6 % of the volume each way**, and their bounding
boxes differ (`[…, 23.501, 23.695, 63.048]` against `[…, 24.000, 24.000,
60.000]`). Any equivalence test for this operation that compares volumes is
measuring almost nothing. The smoke scenario in §4 uses the symmetric
difference and the bounding box instead.

The identity itself, which every non-degenerate rung obeys to 8–10 significant
figures across three corner modes and six span counts:

&nbsp;&nbsp;&nbsp;&nbsp;`V = A(n) · L · cos 25.2316°`

with `A(n)` the regular n-gon's area at circumradius 6 and **L = 66.328259, the
TRUE arc length of the underlying curve** — not the polyline's own length,
which runs from 66.024 at 2 spans to 66.328 at 64. A mitered sweep along a
2-span polyline whose own length is 66.024 encloses the volume of the smooth
sweep along the 66.328-long curve, exactly.

**I cannot derive why.** The obvious model — prisms cut at bisector planes, so
`V = A·cos·L_polyline` — predicts 6 752.0 at 2 spans and the measurement is
6 783.1153. The corner corrections apparently supply the difference exactly, at
every sampling density. It is repeatable, it is useful as an analytic pin, and
it is in §7 as something I do not understand.
