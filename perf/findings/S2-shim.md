# S2 — The OCCT shim: the quadratic

Session 2 of the five in `OPTIMIZATION_PLAN.md`. Owns
`backend/occt/shim/**` and `frontend/lib/ffi/occt_engine.dart`.

Everything above the line `## Results` was written **before any code was
changed**, which is the point of it (plan §2). Nothing in this file is a
device measurement; this session has no device, and §13.3 forbids quoting
simulator numbers as iPad milliseconds.

---

## 1. What the profile establishes, restated so the arithmetic below is checkable

`PERFORMANCE_PROFILE.md` §6.5. Four independent lines of evidence, of which two
carry the arithmetic this session uses:

- **Evidence 2** (`kernel.query.edgeInfoScale`): one `edgeInfo` call against
  *the same edge* on solids of growing size. Requested work held constant, only
  the surrounding shape varies. **k = 0.985**, R² = 0.9998.
- **Evidence 4** (`stress.allEdges` vs `stress.buildOnly`): the isolation.
  **k = 2.012** [1.910, 2.113] against a control at **1.063** [0.959, 1.167],
  on identical solids, with the control doing strictly more work.

Composition: 0.985 + 1 = 1.985 against a measured 2.012 — agreement to 1.3 %.

**Mechanism in source** (`backend/occt/shim/occt_capi.cpp`, located by symbol,
not by the line numbers the profile cites — those have drifted):
`occt_shape_edge_info` performs four whole-shape operations *per call* and
discards all four:

| Operation | Cost class | Needed per edge? |
| --- | --- | --- |
| `TopExp::MapShapes(EDGE)` | Θ(E) | no — the map is a property of the shape |
| `TopExp::MapShapesAndAncestors(EDGE, FACE)` | Θ(E + F) | no — same |
| `BRepBndLib::Add` | Θ(F) | no — the bounding box is a property of the shape |
| `BRepClass3d_SolidClassifier` **construction** | Θ(F log F) | no — the classifier is loaded with the shape |

Only `BRepClass3d_SolidClassifier::Perform(point)` is genuinely per-edge.

### 1.1 The fitted per-call cost, from the committed baseline

`perf/baseline.json`, uncapped reference arm, build `230f179`. Per-call means
from `kernel.edgeInfoScale.*` against the exact edge-count gauges
`kernel.edgeInfoScale.edges.*`:

| Edges E | mean per call (n = 20) |
| ---: | ---: |
| 72 | 0.3230 ms |
| 180 | 0.7765 ms |
| 360 | 1.5429 ms |
| 720 | 3.1248 ms |

Ordinary least squares, `c(E) = αE + β`:

```
α = 4.3295e-3 ms/edge     β = 9.28e-5 ms      (residuals +3.5, -0.4, -1.0, +0.2 %)
power fit                  k = 0.9851
```

**β is indistinguishable from zero.** That is the single most important number
in this file: the size-*independent* part of one `edge_info` call — the curve
adaptor, the arc-length integration, the two face normals, the classifier
`Perform` — is below the resolution of a four-rung ladder spanning 10× in size.
An upper bound for it is the largest positive residual of the purely
proportional model, **0.0113 ms/edge** at the smallest rung; the fitted value is
**0.0001 ms/edge**. Call this quantity **r**, with `r ∈ [0.0001, 0.011] ms`.

### 1.2 The same constant read off the stress ladder

`stress.allEdges.*` against the `stress.allEdges.edges` gauge (1440 at the
terminal rung, 3 profile-arc rungs at 120/240/480 profile points):

| Edges E | measured | T/E² |
| ---: | ---: | ---: |
| 360 | 616 ms | 4.753e-3 |
| 720 | 2 508 ms | 4.838e-3 |
| 1440 | 10 017 ms | 4.831e-3 |

**α_stress = 4.807e-3 ms/edge², constant to 1.1 % over a 4× range.** It exceeds
the `edgeInfoScale` α by 11 %, and that gap is itself constant across the
ladder — i.e. it is a difference in the *fixture* (faces per edge), not a
missing E² term. See §3.3 for why this matters.

---

## 2. The change

A **bulk entry point**, as the plan specifies — one traversal filling an array
for all edges — plus its Dart binding. Not a Dart-side batching of the existing
call: §6.5 evidence 3 puts the boundary crossings at 8.1 % of the cost and
leaves the quadratic entirely intact.

```c
/* v21 */
int occt_shape_edges_info(const occt_shape *shape, double *out12n, int cap);
```

Implemented so that **bit-identity is structural, not tested-for**: the
per-edge body of `occt_shape_edge_info` is factored out verbatim into
`edge_info_one(ctx, index, out12)`, and the four whole-shape operations move
into an `edge_info_ctx` that the per-edge body cannot tell apart. The
single-edge entry point builds one context per call (its cost is therefore
unchanged, by construction); the bulk entry point builds one per shape.

The context builds each of the four lazily, so the single-edge path performs
exactly the operations it performed before, in the same order, and no others.

---

## Prediction P1 — the bulk path removes the quadratic from `stress.allEdges`

```
Target        : stress.allEdges.{120,240,480}, and the two rungs the ladder
                could not reach
Baseline      : 616 / 2508 / 10017 ms at 360 / 720 / 1440 edges
                (perf/baseline.json spans; PERFORMANCE_PROFILE.md §6.5 ev. 4)
Mechanism     : n calls x Θ(n) whole-shape work per call. Four operations,
                each a property of the SHAPE, recomputed once per EDGE.
Change        : one shared context per enumeration; per-edge body untouched.
Predicted     : see table
Derivation    : T_new(E) = S(E) + E*(r + d)
                  S(E) = the whole-shape work of ONE old call = α_stress * E
                         = 4.807e-3 * E ms          [§1.2]
                  r    = size-independent per-edge work, [0.0001, 0.011] ms
                                                      [§1.1]
                  d    = Dart-side per-edge cost that SURVIVES the change
                         (one OcctEdgeInfo construction), <= 0.002 ms
                         [assumption, falsified below]
Falsifiable by: the fitted exponent of the stress.allEdges family. Predicted
                k in [0.95, 1.10]. A post-change fit of k > 1.5 refutes this
                prediction outright.
Risk          : see §3.1 — the hypothesis that the classifier's CONSTRUCTION,
                not its Perform, is the size-dependent cost.
```

| Profile pts | Edges | Baseline | **Predicted** | Interval | Implied factor |
| ---: | ---: | ---: | ---: | --- | ---: |
| 120 | 360 | 616 ms | **4.1 ms** | [1.8, 6.4] | ≈ 150× |
| 240 | 720 | 2 508 ms | **8.2 ms** | [3.6, 12.9] | ≈ 306× |
| 480 | 1 440 | 10 017 ms | **16.4 ms** | [7.1, 25.7] | ≈ 611× |
| 960 | 2 880 | *budget exceeded* | **32.5 ms** | [14.1, 51.2] | — |
| 1920 | 5 760 | *budget exceeded* | **65.1 ms** | [27.9, 102.6] | — |

Central value = midpoint of the interval; the interval is `r`'s bound
propagated, not a confidence interval in the statistical sense.

**Gauge consequences, which the gate will report as changes (§15.4 tier 2):**

| Gauge | Baseline | Predicted |
| --- | ---: | ---: |
| `stress.allEdges.maxSize` | 480 | **1920** |
| `stress.allEdges.edges` | 1440 | **5760** |

The ladder stops on a 4000 ms budget. At the predicted cost the terminal rung
of the `buildOnly` control (1920 profile points) is reached with 97 % of the
budget unspent, so `allEdges` should end the run at the same ceiling as its
control — which is the cleanest possible statement of "the exponents now
match". A `maxSize` that stops short of 1920 bounds the true cost from below:
whatever rung it stops at, that rung exceeded 4000 ms.

## Prediction P2 — the counters, exactly

`allEdges()` stops calling `occt_shape_edge_info`, so the counter that names
that call must stop counting for it.

**What the baseline counter actually was.** `ffi.occt.edgeInfo.calls` = 8316 was
emitted *only* from `allEdges()`, once per call with `by = n`. The direct
single-edge callers — `kernel.edgeInfo1` and `kernel.edgeInfoScale.*` — emitted
nothing. So 8316 is **edges enumerated**, not calls made, and the name was
already wrong before this change.

After the change the name is made true and the work is counted separately:

| Counter | Baseline | Predicted | Source of the number |
| --- | ---: | ---: | --- |
| `ffi.occt.edgeInfo.calls` | 8316 | **100** | `kernel.edgeInfo1` n = 20 plus `kernel.edgeInfoScale.{24,60,120,240}` n = 20 each — the only direct callers left |
| `ffi.occt.edgesInfo.calls` | — | **44** | `ffi.occt.allEdges` n = 42, plus two stress rungs (below) |
| `ffi.occt.edgesInfo.edges` | — | **16 956** | 8316 + 2880 + 5760 |

```
Falsifiable by: any of the three integers coming out different. Counters are
                exact, processor-invariant and noise-free (§15.4 tier 1), so
                these are the sharpest predictions in this file.
Risk          : the last two are CONDITIONAL ON P1, and deliberately so.
```

**Why the last two depend on P1, and what that buys.** `stress.kernel.allEdges`
is a ladder over `[120, 240, 480, 960, 1920]` profile points that stops when a
rung exceeds 4000 ms; it has been stopping at 480. If P1 holds, the last two
rungs run and enumerate 2880 and 5760 more edges. So the counter *reports how
far the ladder got*, which makes the three-way outcome exactly readable:

| `edgesInfo.edges` | `edgesInfo.calls` | Means |
| ---: | ---: | --- |
| 16 956 | 44 | the ladder reached 1920 points — P1 holds |
| 11 196 | 43 | it reached 960 and stopped — a partial win |
| 8 316 | 42 | it still stops at 480 — P1 refuted |
| anything else | — | **a scenario changed, which is a defect, not a result** |

The last row is the point of writing this down: any fourth value means the
suite is not running the work the baseline recorded, and the durations under it
are not comparable to anything.

**Two more gate entries follow from the same cause**, both expected:

- `stress.allEdges.edges` (gauge, the last completed rung): 1440 → **5760**.
  The gate calls a changed gauge a failure — "the fixture changed size" — and
  here it is right that it does, and right that the change is deliberate.
- `stress.allEdges.maxSize` (ceiling gauge): 480 → **1920**, reported as
  "ceiling up (improvement)".
- `ffi.occt.allEdges` span: n 42 → 44, which the gate reports as a CALLS
  failure because the means are then not comparable. They are not; the span is
  now averaging over two rungs the baseline never reached.

**All of this will be reported by the gate as failures.** Saying so in advance
is what the plan asks of Session 4 for the same reason, and it applies here
identically: a counter that changes is a finding, and these are the win.

## Prediction P3 — the single-edge path is a control and must NOT improve

```
Target        : kernel.edgeInfo1, kernel.edgeInfoScale.{24,60,120,240}
Baseline      : 1.5394 / 0.3230 / 0.7765 / 1.5429 / 3.1248 ms
Mechanism     : occt_shape_edge_info keeps building its own context per call.
Change        : none to its cost — the refactor moves code, not work.
Predicted     : unchanged, within the run's own noise floor. k = 0.985
                stays 0.985.
Falsifiable by: any of these five means moving by more than the measured
                floor for the family. And, at counter level and exactly:
                ffi.occt.edgeInfo.calls must be 100 (P2) — five spans of
                n = 20, all of them still going through the single-edge
                door. A smaller number means something quietly stopped
                calling it.
Risk          : if they IMPROVE, the refactor changed the single-edge path's
                cost, which means the lazy context is not reproducing the
                original order of operations. That is a defect, not a bonus:
                it would mean the two paths are no longer doing the same work,
                and the bit-identity argument of §2 rests on them doing so.
```

A control that must stay still is worth as much as a subject that must move.
Without it, an improvement in `allEdges` is consistent with having quietly
dropped one of the four whole-shape operations altogether.

## Prediction P4 — the profile's 8.1 % residual is model error, not per-edge overhead

This one contradicts a statement in `PERFORMANCE_PROFILE.md`, so it is
registered separately and prominently.

§6.5 evidence 3 closes the cost model at 360 edges: 360 × 2.9862 ms = 1075.0 ms
against a measured 1169.7 ms, and attributes **the residual 8.1 % to "boundary
crossings and Dart-side list construction"**.

```
Target        : the residual term in the allEdges cost model
Baseline      : 8.1 % at 360 edges (§6.5 ev. 3); reproduced here as
                +9.8 / +11.7 / +11.6 % at 360 / 720 / 1440 edges when the
                edgeInfoScale α is applied to the stress ladder (§1.2)
Mechanism     : the profile's attribution implies 0.263 ms per edge of
                boundary + list cost on the capped arm (0.137 ms uncapped).
                One Dart FFI crossing into a static C function plus one
                12-double calloc/free pair is on the order of a MICROSECOND.
                0.137 ms is ~100x too large for that attribution to hold.
Change        : the bulk path removes the crossings and the per-edge
                calloc/free, and keeps the Dart list construction.
Predicted     : the residual does NOT survive. If it were boundary cost, the
                new path would still pay the list-construction half of it;
                if it were per-crossing cost, ~1040 ms of the 10017 ms at
                1440 edges would remain. Predicted remaining: < 3 ms.
Derivation    : the residual is constant at ~11 % across a 4x size range,
                i.e. it scales as E^2, not as E. A per-edge cost cannot
                scale as E^2. It is therefore a difference in α between the
                edgeInfoScale fixture and the stress fixture — different
                faces per edge — not an overhead term at all.
Falsifiable by: stress.allEdges.480 landing near 1000 ms rather than near
                16 ms. That result would confirm the profile's attribution
                and refute this entry.
Risk          : this is the entry most likely to be wrong, because it argues
                against a measurement-backed document from arithmetic alone.
```

---

## 3. Threats to validity, stated before the result

### 3.1 The one that could sink P1: which half of the classifier costs

The four whole-shape operations are hoisted. Three of them (`MapShapes`,
`MapShapesAndAncestors`, `BRepBndLib::Add`) are unambiguously whole-shape work
that happens once. The fourth is not one operation but two:

- `BRepClass3d_SolidClassifier(shape)` — **construction**, which loads the solid
  and builds the explorer's face structure. Hoisted.
- `cls.Perform(point, tol)` — **the query**, one per edge. **Not hoisted, and
  not hoistable**: it is the actual per-edge question.

P1 assumes construction is the size-dependent half and `Perform` is
sub-linear. §1.1 supports that indirectly — the whole per-call cost is
proportional to shape size with an intercept of zero, and *something* in the
call must be Θ(shape) — but it does not distinguish the two halves, because the
old code always paid both together and never varied one without the other.

If `Perform` is instead a linear scan over faces, `allEdges` stays quadratic
with a smaller constant. **The measurement that distinguishes them is the
post-change exponent**, and it is exactly the measurement the device run
produces. Two branches, registered:

| Hypothesis | Post-change `stress.allEdges` fit |
| --- | --- |
| **H1 (registered as P1)** construction dominates | k ∈ [0.95, 1.10], terminal rung ≈ 16 ms |
| **H2** `Perform` dominates | k ≈ 2.0 retained, terminal rung ≈ 0.85 × 10 017 ≈ 8 500 ms |

H2 is not a null result. It would relocate the finding — from "the shim
recomputes shape-wide maps per edge" to "OCCT's point-in-solid classification is
linear in face count" — and the follow-up would be a different fix (classify
once per *face pair* rather than per edge, or replace classification with an
orientation-based convexity test, which the source comment records as having
been tried and found fragile).

### 3.2 Bit-identity is argued structurally, not just tested

The per-edge computation is textually the same code, reached through a context
whose only difference is *when* its members were built. The arguments that the
hoisted objects are shape-properties and not call-properties:

- `TopExp::MapShapes(s, EDGE, m)` — a pure function of `s`. `FindKey(i)`
  returns the same edge.
- `TopExp::MapShapesAndAncestors(s, EDGE, FACE, m)` — a pure function of `s`.
  Face *order* within each list is a property of the traversal, which is the
  same traversal.
- `BRepBndLib::Add(s, bb)` — the box, and therefore `step`, is a pure function
  of `s`. The original constructs `bb` fresh and adds `s` once; so does the
  context.
- `BRepClass3d_SolidClassifier(s)` — reused across `Perform` calls, which is
  the class's documented usage. `Perform` resets classifier state; `State()` is
  read immediately after.

The face-ORDER point is the one that would silently corrupt data if wrong: the
convexity sign comes from `fl.First()` and `fl.Last()`, and the chamfer
reference face is documented as "the FIRST face adjacent to the edge in OCCT's
ancestor map". One map built once per shape gives every edge the same first and
last face it had before, because it is the same map the old code rebuilt each
time.

Pinned by test `[35]` in `backend/occt/tests/smoke_occt.c`: bulk against
per-edge, **all twelve doubles compared for exact bitwise equality**, on four
solids — a box (12 straight edges, all convex), a cylinder (circular edges, a
seam), an L-prism (a reflex profile vertex, so the convexity sign is exercised
in both directions), and a filleted solid. Exact equality, not a tolerance: a
tolerance would hide precisely the reordering this test exists to catch.

**This has now run** — see §6.4 for the result, and for the one branch the
fixtures turned out not to reach.

### 3.3 What this session cannot establish

- **Any absolute timing.** No device, no iPad. Every number in §2 is a model
  output.
- **Whether `α_stress` transfers.** The prediction uses the stress fixture's own
  constant, which is the right one for the stress ladder and possibly not for
  `app.blendPattern.edgeQuery` or `ramp.allEdges`.
- **The classifier question of §3.1**, until either Session 1's Lane C runs or
  the device capture happens.

---

## 4. Deliberately not done

- **`kernel.fillet.edges` flatness (§6.3, §10.2, k = 0.00).** Diagnosed, not
  changed — see §5. The finding is that the flat cost is OCCT's, not the
  shim's.
- **Fillet radius sensitivity (10 ms at r = 1.0 against 658 ms at r = 4.0).**
  See §5.2. Recorded as OCCT behaviour, not a shim defect.
- **`sweepProfile` (§6.1).** Not touched — an absolute cost with a two-point
  slope behind it and no scaling claim, so there is no cost model to optimise
  against. Reading it did produce one testable claim about a cost axis the
  suite does not sweep; see §5.3.
- **Adopting the bulk path inside `part_model.dart`'s `edgesOf`.** That file is
  Session 5's. `edgesOf` is `shape.allEdges()`, so it inherits the change
  without anyone editing it.
- **Re-recording `perf/baseline.json`.** Plan §0 rule 3.

---

## 5. The other two findings in §6.3, and why neither produced a code change

### 5.1 Fillet and chamfer cost the same for 1, 4 or 12 edges

Measured (§10.2, uncapped reference arm, and reproduced on an earlier capped
run at 49.3–49.5 ms):

| | 1 edge | 4 edges | 12 edges | fit |
| --- | ---: | ---: | ---: | --- |
| `kernel.fillet.edges` | 25.54 ms | 25.57 ms | 25.83 ms | **k = 0.00**, R² = 0.0025 |
| `kernel.chamfer.edges` | 25.54 ms | 25.57 ms | 25.83 ms | **k = 0.00** |

The plan asks: "flat cost against a swept axis means the work is not per-edge;
find what the fixed cost is." Reading `occt_fillet_edges_ex` and the helpers it
calls, the happy path — where `blend_ladder` succeeds on its first rung, which
is what the fixture does — performs **six whole-shape operations, none of which
depends on how many edges are in the set**:

| # | Operation | Where | Scales with |
| --- | --- | --- | --- |
| 1 | `TopExp::MapShapes(EDGE)` | `occt_fillet_edges_ex` entry | edges |
| 2 | `solid_volume(base)` → `BRepGProp::VolumeProperties` | `c.base_vol` | faces |
| 3 | `BRepFilletAPI_MakeFillet mk(base, ChFi3d_Rational)` | `try_fillet_build` | the shape |
| 4 | `mk.Build()` | `try_fillet_build` | the shape |
| 5 | `solid_volume(out)` | `blend_result_ok` | faces of the result |
| 6 | `BRepCheck_Analyzer(out).IsValid()` | `blend_result_ok` | the whole result |

Only `mk.Add(radius, edge)` — step 4's input — is per-edge, and it is a
constant-time registration, not a build. **k = 0.00 is therefore not a
surprise; it is what this control flow predicts.** The measurement and the
source agree, which is the useful part: it means there is no hidden per-edge
cost to go looking for.

**Nothing here can be removed without changing behaviour, and behaviour does
not change.** Steps 3 and 4 are OCCT's own blend and are irreducible. Steps 2,
5 and 6 are the catastrophe guard, and its history is in the source: OCCT's
`BRepFilletAPI` reports `IsDone()` and still hands back solids that fail
`BRepCheck_Analyzer` — self-intersecting wires, invalid pcurves on the blend
faces. Dropping the guard would make blends that currently fail cleanly start
succeeding with a corrupt solid. That is a behaviour change of the worst kind:
invisible until the part is reopened.

So this is recorded as a **closed question, not an unfixed defect**. What would
change it is not shim work but a cheaper guard, and evaluating one needs a
measurement of the guard alone — which Lane C can produce and this session
cannot (see `CROSS-SESSION.md`, S2-2).

One thing that *is* worth stating, because §6.3 states its converse: at one
filleted edge the profile measures the candidate search (`allEdges`) at 4.9× the
blending itself. That ratio is a statement about `allEdges`, and it is this
session's main change that moves it. If P1 holds, candidate search stops being
the dominant half of "fillet one edge" and the flat 25.5 ms becomes the whole
of it.

### 5.2 The 65× radius discontinuity

| Quantity | Value |
| --- | ---: |
| `filletEdges` at r = 1.0, one solid | ≈ 10 ms |
| `filletEdges` at r = 4.0, same solid | **658 ms** |
| Ratio | **≈ 65×** |

n = 3. The profile is explicit that this is "a demonstration of magnitude, not
a characterised curve", and it says why: "a radius large enough to reach
neighbouring geometry is not a slower instance of the same operation; it is a
different operation."

The plan's instruction was "understand it before touching it; this may be
OCCT's own behaviour and not fixable in the shim, which is a legitimate result
to record." **That is the result.** The shim's contribution to a fillet at
r = 4.0 is identical to its contribution at r = 1.0 — the same six operations
of §5.1, on the same solid, with one number different in one `mk.Add` call.
Everything that differs happens inside `BRepFilletAPI_MakeFillet::Build()`,
where a blend surface that intersects neighbouring faces forces the walking
algorithm to trim and re-intersect against geometry a small radius never
touches.

There is one shim-side amplifier worth naming, and it is not the cause but it
multiplies the cost when the radius is *just* too large: `blend_ladder` retries
a failed build at five relative sizes (1.0, 1−10⁻⁶, 1−10⁻⁵, …), and
`blend_edges_subset` will then probe each edge alone and rebuild the survivors.
A radius that fails on the first four rungs pays for five whole builds. That is
deliberate — it is what makes a 2 mm fillet on a 2 mm wall work at all, and the
source records the OCCT issue behind it — and the 658 ms figure is a *success*,
so it did not walk the ladder. But it means the tail of this distribution is
far worse than 65×, and anyone measuring it should count builds, not only
milliseconds.

**No change made.** Changing the ladder changes which fillets build, which is a
behaviour change, and it would be one made against n = 3.

### 5.3 `sweepProfile` — read, not changed, and one structural claim worth testing

§6.1 measures `sweepProfile` at 160 ms mean / 396 ms max over n = 16, with
`kernel.sweep.path` at 205 ms per sweep on a 96-point path. Its fitted exponent
is a two-point slope (N = 2) and the profile makes no scaling claim from it. The
plan's own rule — do not optimise against an exponent whose interval supports
nothing — applies, so no change was made.

Reading the source did produce one thing the profile does not have, and it is
falsifiable:

**A swept profile with holes costs (1 + h) whole sweeps, not one.**
`finish_pipe` builds the outer section with one `BRepOffsetAPI_MakePipeShell`,
and then, for each hole wire, constructs **another complete
`MakePipeShell`**, builds it, solidifies it, and cuts it out with a
`BRepAlgoAPI_Cut` — followed by one `ShapeUpgrade_UnifySameDomain` over the
result. The source says why (a multi-wire section is not reliable through
`MakePipeShell`), so this is a deliberate choice, not an oversight.

The consequence for cost is not recorded anywhere: **`sweepProfile` should be
linear in hole count with a slope of roughly one whole sweep per hole, plus a
boolean.** The suite's sweep fixtures appear to have no holes, so nothing
measured touches this axis, and the 160 ms mean is the *cheapest* case.

```
Predicted     : sweepProfile(h holes) ≈ (1 + h) × sweepProfile(0) + h × cut
Derivation    : one MakePipeShell Build + MakeSolid per hole, plus one
                BRepAlgoAPI_Cut per hole, from finish_pipe's loop.
                §6.2 puts a boolean cut at 17.3 ms mean, so at 160 ms per
                sweep the cut is ~10 % of each additional hole.
Falsifiable by: a sweep ladder over HOLE COUNT — 0, 1, 2, 4 holes, one
                fixed path and section. A flat result refutes this outright.
Risk          : none taken — no code changed. This is a claim about cost
                that the suite cannot currently see, offered so it can be
                measured rather than assumed.
```

A ladder over hole count belongs in the perf suite, which nobody may edit in
this split (§3), so this stays a registered claim rather than a measurement.

---

## 6. Results — host-side, which is all this session can produce

No device measurement exists yet. Everything below is verification, not
measurement, and the distinction is the whole point of §2 of the plan.

### 6.1 What was actually changed

| File | Change |
| --- | --- |
| `backend/occt/shim/occt_capi.cpp` | `edge_info_ctx` + `edge_info_one()` factored out of `occt_shape_edge_info`; new `occt_shape_edges_info`; shim version 20 → 21 |
| `backend/occt/shim/occt_capi.h` | the new entry point and its contract |
| `backend/occt/tests/smoke_occt.c` | scenario **[35]**, the bitwise identity pin |
| `frontend/lib/ffi/occt_engine.dart` | `_EdgesInfoN/D`, the eager lookup, `OcctEdgeInfo.decodeRecord`, `allEdges()` rewritten to one call, counters |
| `frontend/test/bulk_edge_info_test.dart` | new — the Dart half of the decode, pinned |

Nothing else. In particular: no file belonging to another session, no
`PERFORMANCE_PROFILE.md`, no `perf/baseline.json`, no `frontend/lib/perf*.dart`.

### 6.2 Verification actually run

| Gate | Result |
| --- | --- |
| `flutter test` | **2056 passing**, including the 6 new ones (2050 before them) |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | **0 errors**; 55 infos/warnings, all pre-existing and none in a file this session touched |
| `python3 -m unittest discover -s ci -p 'test_*.py'` | **45 passing** |
| C++ shim | **not compilable here** — see below |
| `smoke_occt.c` | `gcc -fsyntax-only -Wall -Wextra -std=c99` against the real `occt_capi.h`: clean |

**The C++ could not be compiled in this session and that is a real gap.**
`backend/occt/CMakeLists.txt` consumes an OCCT *install tree* built from the
submodule in `backend/occt/upstream`, and that submodule is not checked out
here. What was done instead: the new block — `edge_info_ctx`, `edge_info_one`,
both entry points — was extracted and compiled in isolation under
`g++ -std=c++17 -fsyntax-only -Wall -Wextra` against hand-written stand-ins for
the OCCT types it touches. Clean, no warnings. That proves syntax and type
usage; it does **not** prove that `BRepClass3d_SolidClassifier` behaves as
assumed when one instance answers many `Perform` calls. The `occt-build.yml`
job is what actually compiles this, and smoke scenario [35] is what actually
checks the assumption.

### 6.3 The two things a reader should be most sceptical of

1. **Reusing one `BRepClass3d_SolidClassifier` across every edge.** This is the
   assumption the whole change rests on and the one nothing on this host can
   verify. Constructing once and calling `Perform` many times is the class's
   documented usage, and scenario [35] compares the resulting convexity flags
   bitwise against the per-edge path on four solids — but only CI runs that.
   **It has now been run and it passed; §6.4.** Had it failed, the fix was a
   fresh classifier per edge, which keeps three of the four hoists and most of
   the win.
2. **The per-edge failure marker.** The old path could fail one edge and carry
   on; a positional array cannot return null. Type −1 reproduces the old
   semantics, and `bulk_edge_info_test.dart` pins the distinction between −1
   (drop) and 0 (degenerate, keep) — because getting *that* backwards would
   renumber every edge after a degenerate one, which is exactly the silent
   corruption §3.2 is about.

### 6.4 The identity pin, run on real OCCT

`occt-build.yml` does not fire on a branch — it triggers on `main` and on
manual dispatch — so it was dispatched by hand against
`claude/perf-opt-shim` @ `a37a18d`. Run
[32236991271](https://github.com/Toemeler/ipadprocad/actions/runs/32236991271),
both jobs green, log committed to `ci-logs-occt/smoke.log` on
`ci-debug-logs-occt`. Reading the log rather than the checkmark, per the
HANDOFF rule:

```
Prototype OCCT shim v21 (OCCT 7.9.3) (shim ABI v21)
[35] box:      12 edges, bulk wrote 12 — 0 of 12 records differ
[35] cylinder:  3 edges, bulk wrote  3 — 0 of  3 records differ
[35] L-prism:  18 edges, bulk wrote 18 — 0 of 18 records differ
[35] filleted: 15 edges, bulk wrote 15 — 0 of 15 records differ
[35] coverage: convex edges 44, concave edges 1, curve-kind mask 0x6
OCCT SMOKE: PASS
```

**48 edges across four solids, every one of twelve doubles bitwise equal
between the shared-context path and the per-call path.** That settles the
question §3.1 and §6.3 flagged as the largest risk in this change: one
`BRepClass3d_SolidClassifier`, loaded once and asked 48 times, returns exactly
what 48 freshly constructed ones returned — including the 1 concave edge, where
a stale classifier would have flipped a sign and reattached a fillet as a
round. The hoist is sound.

The iOS job also passed, so the new symbol links into the device archive and
`nm` still finds the full `_occt_*` surface.

**One thing the run refutes, and it is mine.** §3.2 claimed the filleted solid
would reach the curve-type `switch`'s `default:` branch with spline edges. The
coverage mask came back **0x6** — bits 1 and 2, straight and circular, and
nothing else. OCCT's `ChFi3d_Rational` blend on a box edge produces lines and
arcs, not B-splines, so **the `default:` branch is not exercised by any fixture
in [35]**. The exposure is small — that branch writes `out10[0] = 4` and falls
through to the same shared code every other kind uses, so it cannot diverge
between the two paths on its own — but the claim was wrong and the branch is
untested rather than tested. A fixture that would reach it is a lofted or swept
solid; adding one is a follow-up, not a blocker.

---

## 7. Adjudication — P1 is refuted on its central claim, and that is the useful part

Session 1's Lane C landed while this session was still open and measured the
bulk path directly. The full reply is `CROSS-SESSION.md` S1-7; the numbers,
Linux/x86_64, shim v21, four rungs, 7 repetitions, `HARNESS: VALIDATED`:

| edges | per-edge loop | one bulk call | speed-up |
| ---: | ---: | ---: | ---: |
| 180 | 502.1 ms | 33.18 ms | 15.1× |
| 360 | 2 312.4 ms | 125.11 ms | 18.5× |
| 720 | 9 010.4 ms | 456.97 ms | 19.7× |
| 1440 | 36 702.0 ms | **1 775.37 ms** | **20.7×** |

| fit | k | R² | 95 % CI |
| --- | ---: | ---: | --- |
| per-edge | 2.054 | 0.9994 | [1.984, 2.123] |
| **bulk** | **1.909** | **0.9999** | **[1.887, 1.932]** |

### 7.1 What each prediction did

| | Claim | Outcome |
| --- | --- | --- |
| **P1** | `stress.allEdges` k → [0.95, 1.10] | **REFUTED.** k = 1.909 [1.887, 1.932]. The interval excludes the prediction by a mile, R² = 0.9999 over an 8× range, local exponents 1.915 / 1.869 / 1.958 — no knee, no bending toward linear. |
| **P1, direction** | the quadratic's *cost* collapses | Partly upheld: a factor of 20 out of the constant, and the drop of 0.145 in the exponent is real (the two intervals are disjoint). But a constant is not what P1 predicted. |
| **P3** | the single-edge path must NOT improve | **UPHELD, and this is what makes the rest readable.** `edgeInfo1` 1.053 → 1.077 and per-edge `allEdges` 2.057 → 2.054, both intervals overlapping their v20 counterparts and both still agreeing with §6.5. The control did not move. |
| **P1, RSS** | the `12 × n` buffer is invisible | **UPHELD.** `rss_delta_mb` +0.00 at every rung, net live bytes exactly zero. |
| **P2, P4** | counters; the 8.1 % residual | **Not yet adjudicable** — both need the device run. Note that P4 now looks *more* likely, not less: a residual attributed to per-edge boundary cost cannot be what the exponent shows. |

**P1 was wrong about the mechanism being fully accounted for, and §3.1 said in
advance which of two hypotheses that would mean.** H2 — "something inside the
enumeration is still Θ(shape) per edge" — is what the data support.

### 7.2 What the residual quadratic actually was

Not the classifier. Session 1 raised `BRepClass3d_SolidClassifier::Perform` as
the candidate and was explicit that it was "a hypothesis from the measurement,
not a reading of OCCT's source". Reading the source, in this session's own
file, finds a plainer culprit:

```c
for (TopExp_Explorer ex(face, TopAbs_EDGE); ex.More(); ex.Next())
    if (ex.Current().IsSame(edge)) { ori = ...; break; }
```

`into_face_dir` **scanned the face to find the edge it had just been handed**.
O(edges of the face), asked twice per edge. On an n-gon prism — the fixture
both the profile and Lane C ladder over — the solid has two end faces bounded
by n edges each and n side faces bounded by four, so two thirds of all edges
touch an end face and an enumeration performs **2n × O(n)** explorer steps.

**Lane C's allocation counters settle it, and they were not collected for this
purpose**, which is what makes them good evidence:

| n (profile pts) | edges | allocations | per edge |
| ---: | ---: | ---: | ---: |
| 60 | 180 | 184 544 | 1 025.2 |
| 120 | 360 | 633 459 | 1 759.6 |
| 240 | 720 | 2 326 372 | 3 231.1 |
| 480 | 1 440 | 8 885 798 | 6 170.7 |

Fitting allocations per edge against n:

```
alloc/edge = 12.252·n + 290.0      residuals below 0.1 % at all four rungs
```

**Exactly linear in n.** A per-edge cost proportional to the *face being
scanned* produces that; a fixed cost per edge produces a constant. The slope
implies ≈ 18.4 allocations per explorer step once the two-thirds fraction is
taken out, which is what a `TopExp_Explorer` costs per step.

The classifier hypothesis fits the totals too — 12.252·n allocations per call
would be ≈ 12 per face — so the counters alone do not exclude it. What excludes
it as *the* explanation is that the scan is a visible O(n) loop in the shim's
own source with no reason to exist, and removing it is free. If the exponent
does not fall after removing it, the classifier is next, and §7.4 says what
that would look like.

### 7.3 The fix

The bulk path builds a **face-edge orientation index**: one explorer pass per
face, on first request, keyed `(face index, edge index)`, first occurrence
winning exactly as the scan's `break` did. Θ(face-edge incidences) = Θ(E) on a
manifold solid, against the Θ(E·F) it replaces.

Three details that are about correctness, not speed:

- The index for a face is built **from the very `TopoDS_Face` object the caller
  passed**, not from a separate `MapShapes(FACE)` pass. A face reached through
  the ancestor map and one reached through `MapShapes` could differ in
  orientation, and every edge orientation an explorer reports is composed with
  its face's. Exploring the caller's own object removes that question instead
  of answering it.
- A second face that is `IsSame` to an indexed one but oriented the other way
  **falls back to the scan**. In a valid solid this never fires; it costs one
  byte per face to be sure.
- `emplace`, not assignment, so the first occurrence wins. A **seam edge
  appears twice in its face**, once each way, and the scan took the first.

The single-edge entry point keeps the scan. Building an E-sized index to answer
one question is waste, and that path is P3's control.

`into_face_dir` is split into `edge_ori_in_face` (the scan) and
`into_face_dir_with_ori` (the geometry), so index and scan feed **identical**
downstream code. Smoke `[35]` compares the two paths bitwise and is therefore
now a direct pin of the index against the scan it replaces — with a 24-gon
prism added, because it is the only fixture there with a face big enough for
the two to differ in cost.

## Prediction P5 — the second quadratic, registered before Lane C reruns

```
Target        : Lane C's allEdgesBulk ladder, 60/120/240/480 profile points
Baseline      : 33.18 / 125.11 / 456.97 / 1775.37 ms, k = 1.909 [1.887, 1.932]
Mechanism     : into_face_dir's O(edges of face) scan, twice per edge, over
                end faces carrying n edges each — 2n x O(n) per enumeration.
Change        : a per-shape face-edge orientation index in the bulk path.
Derivation    : fitting the measured ladder as bulk(E) = aE^2 + bE gives
                  a = 8.198e-4 ms/edge^2   b = 0.0524 ms/edge
                (model reproduces 360 and 1440 exactly by construction, 720
                to +1.3 % and 180 to +8.5 %). If the scan IS the aE^2 term,
                removing it leaves bE plus a Theta(E) setup.
Predicted     : 9.4 / 18.9 / 37.7 / 75.5 ms   (interval [0.8x, 1.5x])
                k -> 1.00, predicted interval [0.95, 1.15]
                a further 23.5x at the 1440 rung, 490x against the per-edge
                loop it started as
Falsifiable by: THE ALLOCATION COUNTER, which is sharper than the timings.
                alloc/edge = 12.252*n + 290.0 fits to better than 0.1 %. If
                the scan is the whole n-dependent term, alloc/edge becomes
                ~290 CONSTANT and total allocations at 1440 edges fall from
                8.886e6 to ~4.2e5 — a factor of 21. A counter that stays
                proportional to n refutes this outright and hands the finding
                straight to BRepClass3d_SolidClassifier::Perform.
Risk          : see §7.4.
```

### 7.4 If P5 is refuted too

Then `Perform` is Θ(faces) and the convexity branch is inherently quadratic
over an enumeration. That is not a dead end, but it is a different fix and a
larger one, and it is **not** this session's to make on the evidence available:

- The classifier exists to decide convex from concave, and the source records
  that the cross-product formulations were tried first and reported *every*
  edge convex. Replacing it is a correctness change with a known failure mode.
- The cheap alternative is to classify once per **face pair** rather than once
  per edge — edges sharing the same two faces on a prism's rim have the same
  answer only when the faces meet the same way along their whole length, which
  is not true in general.
- Either way it wants a device or Lane C run to justify, and an identity pin
  wider than `[35]`.

Recorded for §8 rather than acted on.

### 7.5 One correction to §5.1, from Session 1's measurement

§5.1 offered a threshold: "if it comes out small — say under 15 % — the
question is closed for good." Lane C measured it, and **it is not closed**:

| | ms |
| --- | ---: |
| `occt_shape_volume` (the guard runs two) | 1.105 |
| `occt_shape_valid` (`BRepCheck_Analyzer`) | 6.480 |
| guard lower bound = 2 × volume + valid | **8.690** |
| whole `occt_fillet_edges_ex` at one edge | 19.222 |
| **guard as a fraction** | **≥ 45.2 %** |

A lower bound, because the second integration runs on the *result* solid, which
carries the blend. **Nearly half the cost of blending one edge is the
correctness guard, and `BRepCheck_Analyzer` alone is a third of it.**

This session still does not change it — the guard is why a blend that would
hand back a self-intersecting solid fails cleanly instead, and that is
behaviour. But §5.1's verdict of "closed question" was written against a
threshold that the measurement did not meet, and it is withdrawn: **it is an
open question for §8**, with the number attached.
