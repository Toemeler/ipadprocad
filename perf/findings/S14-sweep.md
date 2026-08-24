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
