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

### 2.9 P4 — HELD, on the device's own rung and with the device's own message

```
shim  seg=1200  spans=16   FAILED after 742 249.0 ms
                           : occt_sweep_profile: BRep_API: command not done
```

The same rung, the same error string, on a machine the device has never
touched. Device 231 085 ms, here 742 249 ms — a factor of 3.2, against the
3.4 the 512 rung gives, so the failure is not a resource effect of one machine.
P4's alternative — "it builds cleanly on the desktop, so the failure is about
the device's memory" — is refuted.

The same rung with a smooth spine: **4 811.8 ms, valid, 1 202 faces.**

---

## 3. Pre-registration, round 2 — the change

Registered **before the shim was touched**, with §2 in hand. The change, in one
sentence:

> `spine_from_points` will keep building a polyline for the joints somebody
> drew, and will interpolate a C2 B-spline through the runs of points that came
> from the application's own curve sampler — so a sweep along an arc has no
> joints for the corner treatment to spend cubic time on.

**The threshold, derived and not tuned.** `sketchCurve`
(`part_model.dart:8647`) hands every arc and circle to
`sampleEntity(g, arcSamples: 64)` (`snap.dart:453`), which splits the entity's
sweep into **64 equal steps regardless of its angle**. The largest joint that
sampler can emit is therefore a full circle's, `360/64 = 5.625°`, and a 90°
arc's is 1.406°. So:

* a joint **≤ 5.625°** *can* have come from the sampler;
* a joint **> 5.625°** *cannot*, and is a vertex somebody drew.

The number is a property of the caller, not of the benchmark. §2.6's table says
what it costs to be wrong in each direction at that angle: at 5.625° the
mitered and un-mitered answers differ by 0.50 %, at 90° by 46.7 % — so the
threshold sits where the two treatments still nearly agree, and the catastrophe
is four times further out. If `arcSamples` ever stops being 64, this must move
with it, and the code says so.

### Prediction P5 — the shim reproduces the replica

```
Target        : occt_sweep_profile, 1200 segments x 16 spans, after the change
Baseline      : FAILS after 742 249 ms today (§2.9)
Mechanism     : the replica already ran this pipeline: smooth spine, RightCorner
                still set (it is inert with no joints), 4 811.8 ms, valid.
Change        : spine_from_points gains the run-splitting described above.
Predicted     : 4 812 ms +- 15 %, VALID, exactly 1 202 faces
Derivation    : the shim adds two things the replica lacks — the joint scan,
                O(npath) over 17 points, and GeomAPI_Interpolate over 17 points,
                whose whole phase measured 0.1 ms. Both are below the noise of
                a 4.8-second operation, so the prediction is the replica's own
                number with an interval for a contended box.
Falsifiable by: above 6 000 ms, or a face count other than 1 202, or an invalid
                solid. Any of the three means the shim is not doing what the
                replica did.
Risk          : GeomAPI_Interpolate is C2 through the points; the replica used
                exactly that call, so the risk is in the plumbing, not the maths.
```

### Prediction P6 — a drawn corner is untouched, bit for bit

```
Target        : the L-path of smoke scenario [30] — 10x10 square, 40 up then 30
                across, one 90-degree joint.
Baseline      : volume 6 000.000000 exactly, 10 faces, valid (§2.6)
Mechanism     : 90 deg > 5.625 deg, so no run is smoothed, so the spine is the
                same BRepBuilderAPI_MakePolygon wire the shim builds today and
                every later call sees identical arguments.
Change        : as above.
Predicted     : IDENTICAL. Volume 6 000.000000, 10 faces, valid, and the
                symmetric difference against the legacy path EXACTLY zero.
Derivation    : not arithmetic — identity. The code path is the same objects in
                the same order.
Falsifiable by: any difference whatsoever, in volume, face count or topology.
                This is the strongest test in the set and the one that says the
                fix does not round off geometry a user drew.
Risk          : an off-by-one in the run splitter could smooth a two-point run
                or drop the corner vertex. That is exactly what this catches.
```

### Prediction P7 — the silently invalid rung becomes correct

```
Target        : 64 segments x 32 spans, where the shipped path returns an
                INVALID solid 10.6 % too large in 2.4 s and reports nothing.
Baseline      : 7 490.0386, INVALID (§2.5)
Predicted     : 6 774.94 +- 0.5 %, VALID, 66 faces
Derivation    : analytic. A(64) . L . cos(tilt)
                = 112.915746 x 66.328259 x 0.904592 = 6 774.9447, and the
                replica's smooth spine measured 6 774.9447 at this rung — the
                analytic value to eight figures.
Falsifiable by: outside +-0.5 % of 6 774.94, invalid, or a face count != 66.
Risk          : the analytic identity of §2.8 is empirical, not derived. If it
                is a property of THIS fixture rather than of sweeps, the pin is
                weaker than it looks — but it is checked against a measured
                value as well as a computed one.
```

### Prediction P8 — the process stops aborting

```
Target        : 64 segments x 64 spans, which today corrupts the heap and kills
                the process through occt_sweep_profile (§2.5).
Predicted     : a valid solid, 66 faces, 6 774.94 +- 0.5 %, and the process
                survives.
Derivation    : the smooth spine has no joints, so BRepFill_Sweep::PerformCorner
                and BRepFill_TrimShellCorner — the only code the corrupting rung
                reaches that the 16-span rung does not — never run. The replica
                already built this rung: 138.6 ms, valid, 6 774.9510.
Falsifiable by: any abort, null, or invalid result.
Risk          : if the corruption is NOT in the corner path the fix will not
                touch it, and the same rung will abort again. That would refute
                the mechanism claim of the whole session, not just this
                prediction.
```

### Prediction P9 — the exponent falls from ~3 to ~1

```
Target        : the bench's sweep.segments fit over 32 / 128 / 512 / 1200 / 2048
Baseline      : shipped local exponents 2.00 (32->128) and 2.97 (128->512)
Predicted     : fitted k in [0.85, 1.40], R2 > 0.98
Derivation    : the replica's smooth-spine rungs — 183.1 (64), 439.7 (128),
                1 696.2 (512), 4 811.8 (1200), 9 772.6 (2048) — fit
                k = 1.1202, R2 = 0.9974, 95 % CI [1.055, 1.186]. The registered
                interval is wider than that CI because the shim's ladder starts
                at 32, where fixed costs matter more, and because the box is
                shared.
Falsifiable by: k above 1.6 — which would mean a superlinear term survived the
                change — or R2 below 0.98, which would mean there is a knee the
                fit is hiding.
```

### Prediction P10 — nothing else in the shim moves

```
Target        : Lane C's calibration — edgeInfo1, allEdges, buildOnly against
                PERFORMANCE_PROFILE.md §6.5.
Mechanism     : the change touches spine_from_points and occt_sweep_profile and
                nothing else. No other entry point reads either.
Predicted     : the benchmark still prints LANE C: PASS, with the three
                calibration exponents inside the same intervals they agree with
                before the change, measured in the same run.
Falsifiable by: any calibration verdict flipping to DISAGREES.
Note          : CALIBRATION.txt is NOT re-recorded. Its hash is already stale
                (8c46e48 recorded, f18342b in the tree) and the integrator ruled
                on 2026-08-21 that it stays that way until a round-two device
                capture against a v22 kernel. This change makes the hash move
                again and that is all it does.
```

---

## 4. What was built

### 4.1 The shim — v24

`spine_from_points_ex` splits the path into **maximal runs whose interior
joints are all ≤ 5.625°**. Each run of three or more points becomes one edge
carrying a C2 B-spline **interpolated through every point**; a run of two stays
a line; a joint above the threshold stays a vertex of the wire and is still
mitered by `BRepBuilderAPI_RightCorner`, which is left set and is simply inert
where there are no joints left. An interpolation that will not run falls back
to that run's straight segments, which is what v23 would have built.

`occt_sweep_profile_ex(..., path_mode)` exposes it:

| mode | what it does |
| --- | --- |
| `OCCT_SWEEP_PATH_AUTO` | the above. `occt_sweep_profile` now passes this. |
| `OCCT_SWEEP_PATH_POLY` | **v23, bit for bit.** The reference arm of every differential test, and the escape hatch. |
| `OCCT_SWEEP_PATH_SMOOTH` | one interpolated curve through the whole path whatever its joints. |

Two things the measurements forced that the plan did not have:

* **On a smoothed spine the trihedron becomes corrected Frenet.** Plain Frenet
  carries the curve's *torsion*: on this fixture's helix that is 81° of section
  rotation over the path, which a circular section hides completely and a
  square one does not. Measured on a square section: polyline Frenet and
  polyline corrected Frenet are identical at 2, 4 and 16 spans (same volume,
  same bounding box, every printed digit), and smoothed corrected Frenet
  reproduces the polyline's bounding box while smoothed plain Frenet does not.
  So corrected Frenet is the choice that changes nothing where nothing was
  smoothed, and it is applied only where something was.
* **AUTO does not smooth a profile with holes.** `finish_pipe` sweeps each hole
  and CUTS it out. Between two solids made of planes that boolean is cheap;
  between two solids made of general swept surfaces it is not:

  | 24-segment ring, r=3 hole, 16 spans | ms |
  | --- | ---: |
  | sweep the body (smoothed) | 36.5 |
  | sweep the hole (smoothed) | 29.5 |
  | **the cut between them** | **21 653.6** |
  | the whole v23 operation, for comparison | 258.7 |

  Smoothing a holed profile would be about **80× slower**. So a holed profile
  keeps the v23 spine exactly — and keeps v23's failure at large segment
  counts. §6.1.

`occt_shim_version()` is **24**, taken by the session that owns
`backend/occt/shim/**`, per the rule that survived the v17 and v21 collisions.
The human-readable string had said `v21` since v21 while the number went 22, 23;
it now says v24 and tracks.

### 4.2 Lane C — the sweep ladders

`sweep.segments` (the shipped path) and `sweep.legacy` (`OCCT_SWEEP_PATH_POLY`)
run the same fixture in the same process, which is what makes the comparison a
differential rather than a memory. `sweep.coil` is the control — the same
quarter turn as an exact helix, through an entry point that already existed.
`sweep.spans` separates corner count from total turning. `sweep.ph.*` breaks
one v23 call into its five phases through a replica in `bench_sweep.cpp`, and
the run prints the replica-versus-shim ratio so the phase table can be
disbelieved when it deserves to be. `sweep.var.*` measures the levers with
volume, face count and validity beside each cost.

Three details that are not incidental:

* **`Measured::ok`, and JSON schema `kernel-bench/2`.** A failing rung is
  recorded with its time-to-failure, marked FAILED in both reports, and
  excluded from every fit. Without it the device's broken 1200-segment rung
  would have ranked as its fastest large one.
* **The legacy arm is capped** (`--sweep-legacy-max`, default 128). v23 costs
  447 s at 512 and does not finish at 1200. A job that runs on every push
  cannot climb that.
* **A rung is probed once before it is measured**, because `measureOp` would
  otherwise pay for a failing rung eight times to learn what one attempt knows.

### 4.3 The smoke test — scenario [37], green on real OCCT

```
[37a] L path 90 deg: AUTO vol=6000.000000000 f=8 e=18 v=12
                   | POLY vol=6000.000000000 f=8 e=18 v=12
[37b] 64 seg x 16 spans: AUTO f=66 vol=6774.914831 | POLY f=1026 vol=6774.944740
                                                   | analytic 6774.942852
[37c] joint 5.0 deg -> 6 faces (smoothed), 6.5 deg -> 8 faces (mitered)
[37d] 1200 seg x 16 spans: f=1202 vol=6785.779141 (analytic 6785.807235)
                           — v23 FAILED here
[37f] tube on a STRAIGHT path: vol=3354.294825 (analytic 3354.294825) valid
[37f] tube on a sampled arc: AUTO=4871.741766 POLY=4871.741766 (annulus
      5031.440835 — BOTH under by 3.17 %, and it predates v24)
[37g] taper 5 deg on a smoothed spine: 6766.447913 -> 7375.699522 valid
[37e] 64 seg x 32 spans: f=66 vol=6774.943168 (analytic 6774.942852) valid
[37e] 64 seg x 64 spans: f=66 vol=6774.943032 (analytic 6774.942852) valid
OCCT SMOKE: PASS
```

Note what each arm is entitled to claim. **[37a] and [37f] are differential** —
old against new, one run, one machine, exact equality asserted, no recorded
constant anywhere. **[37d] and [37e] cannot be**, and the scenario says so in
its own comment: v23 produces *nothing* at those sizes (a failure, and a
process abort), so there is no old behaviour to be equivalent to and the check
is against arithmetic instead. That is the exception `OPTIMIZATION_PLAN_2.md`
§1.4 anticipated, stated explicitly rather than quietly.

[37c] is the derived threshold, pinned from both sides. [37g] found a bug in
[37f] on the way — an arm that swept along whatever path the arm above had left
in the shared buffer — which is why every arm now fills its own fixture.

---

## 5. Adjudication

| | prediction | outcome |
| --- | --- | --- |
| **P1** | Build ≥ 90 %, Unify ≤ 5 % | **HELD** — 96.0 % and 2.8 % (n=5) |
| **P2** | ≥ 50× from removing corner treatment; ≤ 5× face-proportional | **SPLIT** — face-proportional clause held easily; "≥ 50×" **refuted at 128 segments** (17.5×) and vindicated at 512 (193×) |
| **P3** | two-term model; 2-span rung at 0.367 of the 16-span | **HELD** — 0.251, inside the [0.15, 0.60] window, point estimate 46 % high; refit on six rungs gives 287.4 ms/corner + 82.7 ms/degree to ±5 % |
| **P4** | the failure reproduces off-device | **HELD** — same rung, same message, 742 249 ms |
| **P5** | 4 812 ms ± 15 %, 1 202 faces, valid | **SPLIT — refuted on time.** 1 202 faces and valid; **3 559.2 ms** (n=5, CV 1.5 %), 26 % BELOW the interval |
| **P6** | a drawn 90° corner untouched, bit for bit | **HELD** — volume, faces, edges and vertices all identical ([37a]) |
| **P7** | 64 × 32: 6 774.94 ± 0.5 %, valid, 66 faces | **HELD** — 6 774.943168, valid, 66 faces (was 7 490.04 and INVALID) |
| **P8** | 64 × 64 stops aborting | **HELD** — 6 774.943032, valid, 66 faces; the process survives |
| **P9** | fitted k in [0.85, 1.40], R² > 0.98 | **HELD** — k = **1.1496** [1.092, 1.207], R² = 0.998 over five rungs |
| **P10** | nothing else in the shim moves | **HELD, but not the way I wrote it down** — `LANE C: PASS`; `allEdges` and `buildOnly` agree in every run; `edgeInfo1`'s verdict **flips run to run on this container, with the code unchanged**. §5.4 |

### 5.1 Why P5 was refuted, because the reason is about method

I registered `4 812 ms ± 15 %` from **one sample** of the replica, taken while
three other jobs were running on a four-core box. Three later single samples of
the shim on the same box read 3 447, 5 498 and 5 893 ms — a CV of 26 % — so an
interval of ±15 % was narrower than the instrument's own noise. The benchmark's
five-rep measurement on a quiet machine is **3 559.2 ms with a CV of 1.5 %**,
and that is 26 % below the interval I registered.

The prediction is refuted, and it is refuted in the direction of *better*. The
mistake was not the model; it was quoting a single contended sample as a
centre. Lane C reps and reports CV for exactly this reason and I did not use it
before registering.

### 5.4 P10, and an instrument finding I did not go looking for

The first full run after the change printed `HARNESS: VALIDATED` with all three
calibration exponents agreeing, and I nearly wrote that down as P10 held. The
**second** run of the same binary printed `HARNESS: NOT VALIDATED`, because
`edgeInfo1` fitted 1.122 instead of 1.038.

`occt_shape_edge_info` is not touched by v24 — not a line — so I ran the ladder
three more times, quietly, and fitted it each time:

| run | `edgeInfo1` k | verdict against device [0.970, 1.010] |
| --- | ---: | --- |
| 1 (with sweeps) | 1.038 [0.987, 1.089] | AGREES |
| 2 (with sweeps) | 1.122 [1.080, 1.164] | DISAGREES |
| 3 | 1.056 [1.019, 1.094] | DISAGREES |
| 4 | 1.095 [0.963, 1.227] | AGREES |
| 5 | 1.156 [1.109, 1.203] | DISAGREES |

**A spread of 0.118 in the fitted exponent, on identical code, from a gate
whose device interval is 0.040 wide.** Every run is above the device's
interval; whether the printed verdict says AGREES depends on how wide the
bench's own confidence interval came out that time, which depends on the noise.

So P10's *claim* — that nothing else in the shim moved — holds, and the two
exponents that carry the §6.5 finding (`allEdges` 2.08, `buildOnly` 0.99–1.03)
agree in every run. But the sentence I wrote for it ("all three calibration
exponents AGREE") describes one run, not the instrument. On a shared container
`edgeInfo1`'s verdict is a coin toss, and anyone reading a single Lane C run's
calibration line as a pass or fail on this operation is reading noise. That is
consistent with the integrator's 2026-08-21 ruling, which already recorded a
real ~0.08 desktop-versus-device gap on `edgeInfo1` — this measures its
run-to-run component for the first time. Reported to Lane C's owner in
`CROSS-SESSION.md`.

### 5.2 The headline, old against new in one run on one machine

`sweep.legacy` (v23) against `sweep.segments` (v24), same process, same fixture:

| segments (16-span sampled arc) | v23 | v24 | |
| ---: | ---: | ---: | ---: |
| 32 | 350.3 ms | 49.7 ms | 7.0× |
| 64 | 934.6 ms | 132.7 ms | 7.0× |
| 128 | 4 666.7 ms | 271.7 ms | 17.2× |
| 512 | **447 118 ms** | 1 223.6 ms | **365×** |
| 1200 | **FAILED after 742 249 ms** | **3 559.2 ms, valid** | — |

(The 512 and 1200 v23 figures are from the probe; the benchmark's legacy arm is
capped at 128 so that it can run on every push.)

Fitted exponents, five rungs each: **v24 k = 1.150** [1.092, 1.207] R² 0.998,
against v23's local 2.00 at the bottom of the ladder and **2.97** from 128 to
512. The control — `occt_coil_profile`, which has always swept along an exact
helix — fits **k = 1.269**, so the sweep now sits in the same family as the
operation that never had this defect.

### 5.3 The threshold is visible in the ladder, and so is its limit

`sweep.spans` at 128 segments, with the path's sharpest joint beside it:

| spans | sharpest joint | v24 | smoothed? |
| ---: | ---: | ---: | :-: |
| 1 | — | 51.5 ms | no joints |
| 2 | 18.379° | 1 046.6 ms | **no** |
| 4 | 9.491° | 2 174.7 ms | **no** |
| 8 | 4.783° | 250.5 ms | yes |
| 16 | 2.396° | 262.8 ms | yes |

The cost falls off a cliff exactly where the sharpest joint crosses 5.625°.
That is the derived threshold doing what it was derived to do — and it is also
the honest statement of what is NOT fixed: a path whose joints are 9.5° is, by
the derivation, a path somebody drew, and mitering it is still what OCCT does
and still costs what it costs. §6.1.

---

## 6. What I deliberately did not do, and what is therefore unfinished

### 6.1 A holed profile is not fixed, and a multi-corner path is not fixed

These are the two halves that are still broken, and both are quantified above
rather than described:

* **Holed profiles keep the v23 spine.** §4.1's table is why: smoothing one
  would make it ~80× slower, because the hole is removed with a boolean and
  that boolean is between planes today and between general swept surfaces if
  the spine curves. So a 1200-segment profile *with a hole* swept along an arc
  still fails exactly as it did. The way out is not to smooth less; it is to
  stop cutting holes out of sweeps at all — a multi-wire section, or a shell
  assembly, which is a bigger change than this one and belongs to whoever
  schedules it. **`Needs:` integrator.**
* **A path with joints above 5.625° is still mitered, and still cubic.** By the
  derivation those joints are geometry somebody drew, and mitering them is
  correct. It is also, at 512 segments and three corners, 79 s on the device.
  §5.3's table shows it: 4 spans at 128 segments is 2 174.7 ms where 8 spans is
  250.5 ms. **Nothing in this session makes a drawn corner cheap**, and if the
  owner's "extremely complex parts" include a 1200-segment profile on an
  L-shaped path, that case is untouched.

### 6.2 Three defects found and not fixed, on purpose

1. **A holed sweep along a tilted path loses 3.2 % of its volume, and has since
   v15.** `finish_pipe` adds the hole with `WithCorrection = Standard_True`
   while `occt_sweep_profile` adds the outer wire with the caller's own setting
   — `Standard_False` for orientation 0 — so the two are placed against
   different frames on any path the section is not perpendicular to. On a
   straight path both are exact (3 383.238902 against an analytic
   3 383.238902); on the arc path both v23 and v24 come out 3.18 % under the
   annulus. Smoke [37f] pins the *differential* (v24 reproduces v23 exactly)
   and prints the deficit. Fixing it is a second behaviour change with a
   different cause and bundling it would make this one impossible to judge.
2. **Orientation 1 ("Fixed") produces an INVALID solid on a climbing path.**
   Measured on a square section along this fixture's arc: volume 16 429 where
   the answer is 6 000, and `BRepCheck_Analyzer` says invalid — in v23, at 2, 4
   and 16 spans alike. A smoothed spine happens to fix it (6 000.0098, valid),
   but orientation 1 does not take the smoothed path today because nothing
   about the mode changes which spine is built. Recorded; not chased.
3. **A CIRCLE used as a sweep path is swept as an open 63-edge polyline.**
   `sampleEntity` repeats the first point at the end, `spine_from_points`
   drops it as a duplicate, and nothing calls `MakePolygon::Close()` — so the
   loop never closes. v24 preserves this exactly (it dedupes identically before
   splitting). Whether a closed sweep path *should* close is a product
   question, not a shim one.

### 6.3 Things I did not touch

* **`ShapeUpgrade_UnifySameDomain` stays.** The brief named it as a candidate
  and the measurement says it is 2.8 % of the call and merges nothing on a ring
  — but "merges nothing on a ring" is not "merges nothing", and a profile with
  collinear runs is the normal case. Removing it to save 2.8 % would be a
  behaviour change bought with no evidence.
* **The fillet guard (`S2-shim.md` §7.5) and the twist refusal are untouched.**
* **No Dart.** `resolvePath`, `sketchCurve` and `sampleEntity` are where the
  real fix lives — the caller knows whether it sampled a curve and should not
  make the shim infer it — and they are not this session's files. §8.1.
* **`CALIBRATION.txt` is NOT re-recorded.** Its hash was already stale and the
  integrator ruled on 2026-08-21 that it stays that way until a round-two
  device capture against a v22 kernel. This change moves the hash again; that
  is all it does.
* **`perf/baseline.json`, `PERFORMANCE_PROFILE.md` and `frontend/lib/perf*.dart`
  are untouched.** The perf tier's `profile.sweep.*` scenarios are unchanged,
  so the next capture's numbers are comparable to this one's by construction.

---

## 7. What I am unsure of

This section is not a formality. In order of how much it would cost to be
wrong:

1. **Whether 5.625° is the right threshold in the field, as opposed to the
   right threshold by derivation.** The derivation is sound — it is the ceiling
   of `sampleEntity(arcSamples: 64)` — but it only covers arcs and circles.
   `splineCurveFor` flattens to a *tolerance*, not to an angle, so a spline
   with a tight local curvature can produce joints above 5.625° that are still
   sampling artefacts, and those paths stay slow. I have not measured what
   joint angles real spline paths actually produce, because that needs the app
   and a real sketch. **If someone can dump the joint-angle histogram of a few
   real sweep paths, that is the single most useful follow-up measurement.**
2. **The volume identity of §2.8.** `V = A(n)·L·cos 25.2316°` with L the TRUE
   arc length reproduces every non-degenerate rung to 8–10 figures, across
   three corner modes and six span counts — and the obvious derivation
   (prisms cut at bisector planes, so `L_polyline`) predicts 6 752.0 where the
   measurement is 6 783.1153. Something makes the corner corrections supply
   exactly the difference at every sampling density and I do not know what. The
   smoke test uses it as an analytic pin, so if it is a property of this
   fixture rather than of sweeps, that pin is weaker than it looks. It is
   checked against a measured value as well as a computed one, which limits the
   damage.
3. **Whether corrected Frenet is right in general or only here.** I measured
   that polyline Frenet and polyline corrected Frenet agree on ONE fixture at
   three span counts. The reasoning behind it — a polyline has no torsion, so
   the correction has nothing to correct — is sound, but it is reasoning, and
   a spine mixing a smoothed run with a drawn corner is a case I did not
   measure at all.
4. **What the 4.4 % displaced volume looks like to a person.** The new solid
   encloses the same volume as the old one with about 4.4 % of it somewhere
   else, and its bounding box differs by up to 3 units on a 60-unit part. I
   believe the new one is closer to what the user drew — it follows the arc
   instead of a 16-chord approximation of it — but I have no rendering and no
   iPad, and "closer to the intent" is an argument, not a measurement.
5. **Everything about time on a device.** Every millisecond here is a desktop
   millisecond on a shared four-core container, roughly 3.4× slower than the
   iPad on this operation. The exponents and the ratios transfer; the durations
   do not, and `backend/bench/README.md` says why in more detail than this.
6. **The heap corruption's exact mechanism.** I established that it goes away
   when the corner path is not taken, which is what P8 claimed. I did not run
   it under a sanitiser and I cannot tell you which structure OCCT overruns, so
   "the corner treatment corrupts the heap" is an attribution by elimination
   rather than a diagnosis. It also means I cannot promise there is no other
   route to it.

---

## 8. Handover

### 8.1 The real fix is one line of Dart that is not mine to write

The shim now *infers* which joints came from a sampler. It should not have to.
`resolvePath` → `sketchCurve` (`part_model.dart:7382`, `:8647`) **knows**: it
just called `sampleEntity(g, arcSamples: 64)` on an arc, or `splineCurveFor` on
a spline, or read a genuine polyline. Passing that knowledge through — one
extra argument to `sweepProfile`, and `OCCT_SWEEP_PATH_SMOOTH` or `_POLY`
instead of `_AUTO` — would make the threshold unnecessary for the two cases it
covers and would cover the spline case it does not (§7.1). `occt_sweep_profile_ex`
exists and takes the argument today; nothing in Dart passes it.

### 8.2 What the integrator has to decide

**This is a behaviour change and it is not mine to merge.** A sweep along a
sampled arc now has `segments + 2` faces where it had `segments × spans + 2`,
the same volume to eight figures, and about 4.4 % of that volume in a different
place. Anything that reattaches a downstream feature to a sweep's face or edge
by index or fingerprint may reattach differently **on parts that already
exist** — which is the same class of risk S2 and S6 carried, in a different
operation.

The escape hatch is `OCCT_SWEEP_PATH_POLY` and it is exactly v23. If the
decision is "not yet", one line in `occt_sweep_profile` reverts the default and
everything else here — the ladders, the failing-rung reporting, the smoke
scenario, the two refuted levers — still stands.

### 8.3 Definition of done

| | |
| --- | --- |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | **56 issues, delta ZERO** — the same 56 lines before and after, diffed. (The brief says 55; this container's Flutter is 3.35.4, one analyzer version's worth of difference. The delta is what matters and it is zero — no Dart file was touched.) |
| `flutter test` | **2 365 passed, 1 skipped** — identical to the pre-change run on the same machine |
| `python3 -m unittest discover -s ci -p 'test_*.py'` | **49 tests, OK** |
| `occt_smoke` on real OCCT 7.9.3 | **OCCT SMOKE: PASS**, including new scenario [37] and its failing-regime arm |
| `occt_mesh_recon_test` | **86 passed, 0 failed** |
| `occt_bench` (Lane C) | **LANE C: PASS, HARNESS: VALIDATED** — all three calibration exponents still agree with §6.5 |
| `bench_stats_test` | **BENCH STATS: PASS** |
| Predictions committed before the code | `e525cd6` (P1–P4, before the instrument) and `3b0bfe4` (P5–P10, before the shim) |

`pubspec.lock` was re-resolved by a local `flutter pub get` (this container's
SDK pins older packages than CI's) and was **reverted**; `git status` is clean
of it. Nobody should read a lockfile change into this branch.

---

# Round two — the wrong parts

The integrator's review kept the v24 merge decision open and sent me back for
the three defects §6.2 recorded and declined to bundle. Each is a separate
behaviour change with its own commit, so each can be judged and reverted on its
own. **Nothing below assumes v24 ships**, and `OCCT_SWEEP_PATH_POLY` remains
exact v23 throughout.

---

## 9. Item 1 — orientation 1 ("Fixed"): the mode is wrong, and the spine is a red herring

### 9.1 "Happens to fix it" was the right thing to be suspicious of

§6.2 recorded that a smoothed spine appeared to fix orientation 1 and that I
did not know why. The integrator asked for a mechanism before a fix. There is
one, it is in OCCT's source, and **it has nothing to do with the spine.**

`occt_sweep_profile` maps orientation 1 to
`BRepOffsetAPI_MakePipeShell::SetMode(const gp_Dir&)`. That is
`BRepFill_PipeShell::Set(const gp_Dir&)`, which builds a
**`GeomFill_ConstantBiNormal`** law. OCCT has a *different* entry point for what
this project's own comment says orientation 1 means — "Fixed keeps the section's
own orientation":

```cpp
void BRepFill_PipeShell::Set(const gp_Ax2& Axe)      // BRepFill_PipeShell.cxx:278
{
  myTrihedron = GeomFill_IsFixed;                    // "all sections parallel"
  ...
  Handle(GeomFill_Fixed) TLaw = new (GeomFill_Fixed)(V1, V2);
}
```

**The shim has been calling the wrong one since v15.** And here is what the
wrong one does (`GeomFill_ConstantBiNormal::D0`):

```cpp
  BiNormal = BN;                                     // forced to (0,0,1)
  if (BiNormal.Crossed(Tangent).Magnitude() > Precision::Confusion()) {
    Normal  = BiNormal.Crossed(Tangent).Normalized();
    Tangent = Normal.Crossed(BiNormal);              // <-- the tangent is REPLACED
  }
```

`Normal × BiNormal` is perpendicular to the binormal, so the frame's tangent
becomes the **horizontal projection of the real tangent, re-normalised**. On
this fixture's path the true tangent is 25.23° off +Z, i.e. **64.77° away from
horizontal** — so the section is swept along a direction 64.77° from where the
spine actually goes. On a single straight segment that mismatch is a constant
and comes out in the wash. On a polyline it compounds at every joint into a
shell that passes through itself.

### 9.2 Measured, with a square section because a circular one cannot show it

"Fixed" keeps every section parallel to the XY plane, so by Cavalieri the
volume is the section area times the **total rise in z**, whatever the path does
in XY: `100 × 60 = 6000`, exactly, for every path below. Driving
`BRepFill_PipeShell` directly, 10×10 square:

| path | `ConstantBiNormal` (shipped) | `Fixed` via `gp_Ax2` |
| --- | ---: | ---: |
| straight up +Z, 2 points | 4 000.0000 valid | 4 000.0000 valid |
| straight chord to (18,18,60) | 6 000.0000 valid | 6 000.0000 valid |
| arc path, **2 spans** | 7 448.5352 **+24.1 % INVALID** | **6 000.0000 valid** |
| arc path, **4 spans** | 8 980.7801 **+49.7 % INVALID** | **6 000.0000 valid** |
| arc path, **16 spans** | 16 429.0722 **+173.8 % INVALID** | **6 000.0000 valid** |

Three things follow, and the second is the one the integrator asked for:

1. **A straight path is exact in both modes.** That is why five sessions and a
   device capture never saw this: the mode only misbehaves once the path bends.
2. **`Fixed` is exactly right on the POLYLINE spine** — 6 000.0000 and valid at
   every span count, with a bounding box of exactly `y ∈ [−5, 23]`,
   `z ∈ [0, 60]`, which is the analytic one. **So the repair does not need v24,
   and the two decisions stay uncoupled.** Said loudly because the integrator
   asked for it to be: *if v24 is rejected, this fix still works.*
3. **The smooth spine was a coincidence of VOLUME, not a fix.** On a smoothed
   spine `ConstantBiNormal` gives 6 000.0015 and valid — but its bounding box is
   `y ∈ [−5.594, 23.002]` where `Fixed` gives `y ∈ [−5.001, 23.000]`. A square
   of half-width 5 whose bounding half-extent is 5.594 has been **rotated by
   about 6.8°**: `5(cos θ + sin θ) = 5.594`. The part is twisted. It is §2.8's
   lesson again — the volume of a sweep is nearly blind to what the section
   does on the way.

   *(I tried to quantify that with a symmetric difference and it came back
   nonsense — each cut returned essentially its whole first operand, 100 % both
   ways, which is impossible for two solids whose bounding boxes coincide to
   half a millimetre. The boolean between two smooth-spine solids is not
   trustworthy here, which is consistent with §4.1's finding about that same
   boolean. I am not quoting it; the bounding box is the discriminator.)*

### 9.3 The `gp_Ax2`'s value does not matter, measured rather than assumed

`GeomFill_Fixed` is a **constant** trihedron, so the location law's transform
along the spine ought to be a pure translation with the frame cancelling out.
Rather than assume that, three unrelated axes on the 16-span polyline:

| `gp_Ax2` | volume | bounding box |
| --- | ---: | --- |
| `(origin, +Z, +X)` | 6 000.0000 | y [−5.000, 23.000] z [0, 60] |
| `((7,−3,11), +X, +Y)` | 6 000.0000 | y [−5.000, 23.000] z [0, 60] |
| `(origin, (1,2,3), (3,0,−1))` | 6 000.0000 | y [−5.000, 23.000] z [0, 60] |

Identical to every printed digit. **So no `mat34` plumbing is needed** and the
shim can use a readable constant, with this table as the reason it is allowed
to. (The cancellation argument is reasoning; the table is one fixture. Both are
stated.)

### 9.4 Pre-registration — item 1

Registered **before the shim was touched for this item**. §9.1–9.3 are probe
measurements against `BRepFill_PipeShell` directly; these are about what
`occt_sweep_profile` does after the change.

```
## Prediction P11 — orientation 1 returns the analytic volume, on the v23 spine
Target        : occt_sweep_profile(orientation = 1), 10x10 square, arc path,
                OCCT_SWEEP_PATH_POLY, at 2 / 4 / 16 spans
Baseline      : 7 448.5352 / 8 980.7801 / 16 429.0722, all INVALID
Mechanism     : GeomFill_ConstantBiNormal replaces the frame's tangent with the
                horizontal projection of the real one (§9.1). GeomFill_Fixed
                does not, because it is constant.
Change        : SetMode(gp_Dir) -> SetMode(gp_Ax2) for orientation 1.
Predicted     : 6 000.0 within 1e-9 relative, VALID, at all three span counts
Derivation    : Cavalieri. Sections parallel to XY, so V = A x (rise in z)
                = 100 x 60 = 6000 exactly, whatever the path does in XY.
Falsifiable by: any deviation above 1e-9 relative, or an invalid solid.
Risk          : none identified; the probe already produced these numbers
                through BRepFill_PipeShell, so the risk is in the plumbing.

## Prediction P12 — the repair is INDEPENDENT of v24
Target        : the same fixture through OCCT_SWEEP_PATH_POLY, i.e. with the
                v23 spine and none of v24's smoothing.
Predicted     : identical to P11. If v24 is reverted, item 1 still works.
Derivation    : the probe's Fixed column IS the polyline spine (§9.2).
Falsifiable by: orientation 1 being correct only under AUTO/SMOOTH. That would
                couple two decisions the integrator is keeping apart, and it
                would be reported at the top of this section rather than here.

## Prediction P13 — a straight path is unchanged, bit for bit
Target        : orientation 1 on a 2-point path, both modes.
Baseline      : 4 000.000000 (up +Z) and 6 000.000000 (chord), both valid
Predicted     : IDENTICAL after the change — same volume, same face count.
Derivation    : with one straight segment the frame is constant in both laws,
                so both reduce to the same translation. Measured: both modes
                give 4 000.0000 and 6 000.0000 exactly today.
Falsifiable by: any difference at all on a 2-point path. This is the arm that
                says the fix does not disturb the case that works.
```

---

## 10. Item 2 — the holed sweep, 3.2 % short since v15

### 10.1 The diagnosis, with a control I did not have to build

§6.2 named the cause: `finish_pipe` adds every hole with
`WithCorrection = Standard_True` while `occt_sweep_profile` adds the outer wire
with the caller's own setting, which is `Standard_False` for orientations 0 and
1. `WithCorrection` rotates the section to sit orthogonal to the spine, so the
two wires of one solid are placed against different frames.

The clean way to test that is not an analytic model at all: **a tube's volume
must be the difference of the two single-loop sweeps that make it.** That is a
differential, it needs no identity, and it is measurable today. 24-segment
ring, r = 6 with an r = 3 hole, v23 spine:

| orientation | outer | hole | outer − hole | the tube | error |
| ---: | ---: | ---: | ---: | ---: | ---: |
| 0, 8 spans | 6 708.589649 | 1 677.147412 | 5 031.442237 | 4 871.741766 | **−3.174 %** |
| 0, 16 spans | 6 708.589649 | 1 677.147412 | 5 031.442237 | 4 871.356213 | **−3.182 %** |
| 1, 8 spans | 6 708.589649 | 1 677.147412 | 5 031.442237 | 4 871.741557 | **−3.174 %** |
| **2**, 8 spans | 7 413.988889 | 1 853.497222 | 5 560.491666 | **5 560.491666** | **+0.000 %** |
| **2**, 16 spans | 7 415.610166 | 1 853.902542 | 5 561.707625 | **5 561.707625** | **+0.000 %** |

**Orientation 2 is exact, and that is the control.** Orientation 2 is the one
whose `correct` flag is `Standard_True` — the same value the holes hard-code.
When the caller's setting happens to agree with the holes', the tube is the
difference of its parts to every digit. That isolates `WithCorrection` as the
cause rather than leaving it as the most plausible of several.

The same control exists in the other operation: `occt_coil_profile` adds its
outer wire with `Standard_True` too, and a holed coil measures
**5 562.133035056** against an outer-minus-hole of **5 562.133035056** —
exact. The coil has never had this defect, for the same reason.

And note the third agreement: `outer − hole = 5 031.442237` is also the
analytic annulus `(A_out − A_in) · L · cos 25.2316°` to six decimals. Three
independent routes to the same number, and the shipped tube misses all three.

### 10.2 Pre-registration — item 2

```
## Prediction P14 — a tube becomes the difference of its parts, exactly
Target        : occt_sweep_profile, 24-segment ring r=6 with an r=3 hole,
                arc path, orientation 0, OCCT_SWEEP_PATH_POLY
Baseline      : 4 871.741766 (8 spans) and 4 871.356213 (16 spans)
Mechanism     : the hole is added with WithCorrection = Standard_True and the
                outer with the caller's Standard_False, so the two wires are
                placed against different frames (§10.1).
Change        : finish_pipe takes the caller's with_correction and uses it for
                the holes, in both the taper and the plain branch.
Predicted     : 5 031.442237 at BOTH span counts, to within 1e-9 of
                (outer - hole), and within 1e-6 of the analytic annulus
Derivation    : outer 6 708.589649 minus hole 1 677.147412 = 5 031.442237,
                measured through the same entry point in the same run; and
                (A_out - A_in) . L . cos(tilt)
                = (112.915746/... see below) = 5 031.442237 analytically.
                For a 24-gon: A_out = 0.5.24.36.sin(15 deg) = 111.7615,
                A_in = 0.5.24.9.sin(15 deg) = 27.9404, difference 83.8211;
                x L 66.328259 x cos 25.2316 deg = 5 031.4422.
Falsifiable by: any residual above 1e-9 relative against (outer - hole). A
                residual that SHRINKS but does not vanish would mean
                WithCorrection is one of two causes, not the cause.
Risk          : the holes are cut with a boolean, and §9.2 already found that
                boolean untrustworthy between two smooth-spine solids. This
                fixture is a POLYLINE spine, where it is well behaved.

## Prediction P15 — orientation 2 does not move, bit for bit
Target        : the same fixture at orientation 2
Baseline      : 5 560.491666 (8 spans), 5 561.707625 (16 spans) — already exact
Predicted     : IDENTICAL, every digit
Derivation    : orientation 2's `correct` is Standard_True, which is what the
                holes hard-code today; threading the caller's value through
                leaves True as True. Nothing in that path changes.
Falsifiable by: any change at all. This is the arm that says the fix is a
                repair and not a re-tuning.

## Prediction P16 — the coil does not move, bit for bit
Target        : occt_coil_profile, 24-segment ring r=6 with an r=3 hole,
                quarter turn of radius 18 rising 60
Baseline      : 5 562.133035056, 50 faces, valid — already exact against its
                own outer-minus-hole
Predicted     : IDENTICAL, every digit, and still 50 faces
Derivation    : the coil adds its outer with Standard_True, so the caller's
                value IS True and the holes keep the setting they have.
Falsifiable by: any change. The coil shares finish_pipe with the sweep, so it
                is the function's other caller and the one most likely to be
                broken by a signature change.
```

---

## 11. Item 3 — the Dart side: the caller stops making the shim guess

### 11.1 What the caller actually knows

`sketchCurve` (`part_model.dart:8647`) is a four-way switch and every branch
knows exactly what it produced:

| the entity | what `sketchCurve` does | what the joints mean |
| --- | --- | --- |
| `Geo.arc`, `Geo.circle` | `sampleEntity(g, arcSamples: 64)` | **every joint is a sampling artefact**, always, by construction |
| `Geo.polyline`, `spline == straight` | the vertices themselves | **every joint is one somebody placed** |
| `Geo.polyline`, spline / ellipse / gear | `splineCurveFor(g)` → flatten to a tolerance | *mostly* sampling — but a flattened gear outline keeps a real cusp at every tooth |
| `Geo.line` | two points | no joints at all |

So the classification the shim has been inferring from a 5.625° threshold is
available for free at the call site, and it is *better* than the inference in
both directions:

* an arc is smooth **whatever its joint angle**, so a coarse arc no longer
  depends on staying under a threshold;
* a polyline vertex is a design feature **however shallow**, so a hand-drawn
  5° bend stops being rounded off.

The middle row is the one that must stay on the heuristic, and this is the
reason: `splineCurveFor` routes `Geo.gearTag` to `gearCurve`, and an involute
gear outline flattened into a polyline has a **genuine sharp corner at every
tooth**. Declaring SMOOTH there would round off the teeth of a part whose whole
purpose is its teeth. So a flattened spline is passed as AUTO and the 5.625°
threshold arbitrates — which is exactly the case §7.1 said it could not measure,
now handled by not having to.

### 11.2 The trap, and how far I could actually pin it

`_sweepArgSig` hashes the RESOLVED arguments, and `f.sweptFrom` decides whether
the kernel is called at all. The path mode is now one of those arguments, so it
must enter the key — otherwise a user who changes the path's *kind* gets the
old solid back.

**I could not build the fixture that isolates this, and I want to be exact
about why.** It needs two sketch entities that resolve to *identical* points
under different modes, and no such pair exists: a `Geo.line` and a two-point
straight polyline both classify POLY, and every other pair produces different
sampled points. So the direct test — same `pts`, different mode, expect a
rebuild — is not constructible through the app's API.

What IS pinned, and what is only argued:

* **Pinned:** the classification itself, because `resolvePath`'s new sibling
  returns the mode and the test calls it directly on each entity kind.
* **Pinned:** that the mode reaches the kernel, by a fake that folds it into
  its result.
* **Pinned:** the guard's existing differential — clear the key, recompute, and
  compare — now runs with the mode among the compared arguments.
* **Argued from the code, not pinned:** that a mode change *alone* forces a
  rebuild. The mode is written into the key beside `orientation`, in the same
  buffer, by the same function; if that line is deleted the argued claim fails
  and no test I can write would notice.

That last line is the honest state of it, and it is the kind of thing this
file's §7 exists for.

### 11.3 Pre-registration — item 3

```
## Prediction P17 — declaring SMOOTH for an arc reproduces AUTO exactly
Target        : a 64-segment ring swept along a 16-span sampled arc, AUTO
                against SMOOTH, through occt_sweep_profile_ex
Baseline      : AUTO gives 66 faces, volume 6 774.914831 (smoke [37b])
Mechanism     : sampleEntity splits an arc's sweep into 64 EQUAL steps, so its
                joints are sweep/64 <= 5.625 deg by construction — which is the
                threshold AUTO already smooths at.
Predicted     : IDENTICAL volume and face count.
Derivation    : a full circle is the extreme case, 360/64 = 5.625 deg, and
                kJointEps puts it inside rather than on the line. A 90 deg arc
                is 1.40625 deg. Every arc is therefore already smoothed by AUTO,
                so declaring it can only agree.
Falsifiable by: any difference at all. That would mean the heuristic and the
                declaration disagree on the case they must agree on, and the
                threshold is wrong rather than merely unnecessary.

## Prediction P18 — declaring POLY for a DRAWN polyline changes the result
Target        : a 3-point polyline path with a 5.0 deg joint, square section
Baseline      : v24 AUTO smooths it: 6 faces (one spline edge + 2 caps)
Predicted     : 8 faces — two straight spine edges, mitered, less the two side
                faces UnifySameDomain merges across the bend
Derivation    : smoke [37c] measured both counts already: a 5.0 deg joint under
                AUTO gives 6, a 6.5 deg joint gives 8. Declaring POLY moves the
                5.0 deg case to the 6.5 deg case's answer.
Falsifiable by: 6 faces, i.e. the declaration not reaching the shim.
Note          : this IS a behaviour change against v24, deliberately, and in
                the direction of correctness — the vertex was drawn, so the
                corner is real. It is also the one case where wiring the truth
                through makes the app do something DIFFERENT rather than the
                same thing for better reasons.

## Prediction P19 — the mode enters the rebuild key
Target        : _sweepArgSig
Predicted     : a mode change alone produces a different key.
Falsifiable by: nothing I can write. See 11.2 — the fixture is not
                constructible, because no two sketch entity kinds resolve to
                identical points under different modes. Registered as ARGUED
                rather than pinned, and labelled as such wherever it is quoted.
```

---

## 12. Item 4 — holed profiles: costed, measured, and NOT built

The integrator asked for a costed proposal rather than an implementation, with
one specific question settled and enough measurement to make the estimate real.
Both are below. **I stopped at the prototype.**

### 12.1 The question first: can `MakePipeShell` take a multi-wire section on 7.9.3? NO.

Settled by source, not by experiment. Every profile handed to
`BRepFill_PipeShell::Add` reaches `BRepFill_Section`'s constructor, which is
exhaustive:

```cpp
  if (aProfile.ShapeType() == TopAbs_WIRE)         wire = TopoDS::Wire(aProfile);
  else if (aProfile.ShapeType() == TopAbs_VERTEX)  { ...degenerate wire... }
  else
    throw Standard_Failure("BRepFill_Section: bad shape type of section");
```

A face with inner boundaries **throws**. One section is one wire, on the
version we pin. So "sweep the annulus as a single section" is not available
and the design has to be the other one.

### 12.2 The other design, prototyped and measured

Sweep each wire to its **lateral shell** as the shim already does, then instead
of subtracting one solid from the other, **assemble**: take both lateral shells,
build the two end caps as planar faces whose outer boundary is the outer
sweep's end section and whose inner boundary is the hole's (`FirstShape()` and
`LastShape()` hand those wires back), sew the four pieces, make a solid.

24-segment ring, r = 6 with an r = 3 hole, 16 spans:

| spine | **A** — the boolean (today) | **B** — shell assembly | volume, A / B | faces |
| --- | ---: | ---: | --- | ---: |
| polyline | 85.4 ms | **17.1 ms** | 5 031.442237 / 5 031.442237 | 770 / 770 |
| smooth | **21 208.5 ms** | **3.7 ms** | 5 031.420889 / 5 031.420889 | 50 / 50 |

**Same volume to ten significant figures, same face count, both valid, and
5 730× faster on the spine that matters.** The two sweeps themselves cost
30.1 ms on the smooth spine, so a holed smooth sweep would total about
**34 ms** where the boolean route costs 21.2 s — and where v23's polyline route
costs 258 ms.

*(A 1200-segment run was started to make the estimate real at the size the
owner's goal names; §12.5 records what it said.)*

### 12.3 What I would build, and what it would break

**Build:** in `finish_pipe`, replace the per-hole `BRepAlgoAPI_Cut` with the
assembly above, keeping the boolean as a fallback when the assembly does not
produce exactly one closed shell. Roughly 40–60 lines. Then lift the
`nloops > 1` restriction in `occt_sweep_profile_ex`, because the reason for it
is the boolean and the boolean would be gone.

**What it would break, and these are not hypothetical:**

1. **Face count and topology change for every holed sweep**, exactly as v24
   does for unholed ones. Same fingerprint-reattachment risk, same owner's
   call. It would want to be gated with v24, not shipped past it.
2. **The assembly assumes each hole is strictly inside the outer boundary and
   that the two sweeps' end sections are coplanar.** The boolean did not: it is
   a general subtraction and copes with a hole that pokes out, by removing
   material outside as well. **Nothing in `placed_profile_wires` checks
   containment today**, so this trades a general operation for a special one
   and needs a guard the code does not currently have. That is the main risk
   and the main reason this is a proposal rather than a commit.
3. **Taper.** `finish_pipe` applies the taper law to the holes too, so both end
   sections are scaled — I believe the caps still match, and I did not test it.
   Unverified.
4. **Multiple holes** need k inner wires per cap. Mechanical, untested.

### 12.4 What it would cost to verify

The differential already exists and already passes: smoke `[37f]` asserts a
tube equals its outer sweep minus its hole sweep, at all three orientations, in
one run. Route B satisfies it exactly (that is the 5 031.442237 above). What
would have to be ADDED:

* containment: a hole that pokes outside the outer boundary — assembly must
  refuse or fall back, and the result must match the boolean's;
* two and three holes;
* a tapered holed sweep, both spines;
* a hole whose end section is not coplanar with the outer's, if that is even
  constructible — I could not think of a way, which is itself worth checking
  before relying on it.

Call it a day's work with the fixtures the smoke test already has, and the risk
is concentrated in the containment guard rather than in the assembly.

### 12.5 Recommendation

**The measurement says it is small and the win is large**, so on the
integrator's own terms this is a "very likely tell you to build it". Two
caveats I would want acknowledged before starting: the containment guard is
new behaviour that nothing currently checks, and the face-count change couples
this to the v24 decision rather than standing beside it.

**Not built. Handed over.**
