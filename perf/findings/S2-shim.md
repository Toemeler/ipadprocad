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

**α_stress = 4.807e-3 ms/edge², constant to 0.9 % over a 4× range.** It exceeds
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

## Prediction P2 — the counters, and a conservation law

`allEdges()` stops calling `occt_shape_edge_info`, so the counter that names
that call must stop counting for it. It is replaced by two: one crossing
counter and one work counter.

```
Target        : ffi.occt.edgeInfo.calls, and two new counters
Baseline      : ffi.occt.edgeInfo.calls = 8316   (perf/baseline.json)
                ffi.occt.allEdges       n = 42   (span)
Mechanism     : 8316 = 100 single-edge calls + 8216 edges enumerated across
                42 allEdges() calls. The 100: kernel.edgeInfo1 (n=20) and
                kernel.edgeInfoScale.{24,60,120,240} (n=20 each).
Change        : allEdges() makes ONE crossing and reports the edge count
                separately.
Predicted     : ffi.occt.edgeInfo.calls   8316 -> 100   (exact)
                ffi.occt.edgesInfo.calls  new  ->  42   (exact)
                ffi.occt.edgesInfo.edges  new  -> 8216  (exact)
Derivation    : 100 + 8216 = 8316. The SUM IS INVARIANT. Work was regrouped,
                not dropped.
Falsifiable by: any of the three integers coming out different. These are
                counters — exact, invariant under a change of processor,
                zero false positives from noise (§15.4 tier 1). If
                edgesInfo.edges + edgeInfo.calls != 8316, either a scenario
                changed or the enumeration lost edges, and BOTH are defects.
Risk          : none to behaviour; this is a bookkeeping prediction whose
                only purpose is to be exactly right or exactly wrong.
```

**This will be reported by the gate as a counter regression.** Saying so in
advance is the plan's §5 Session 4 instruction and it applies here identically:
a counter that changes is a finding, and this one is the win.

## Prediction P3 — the single-edge path is a control and must NOT improve

```
Target        : kernel.edgeInfo1, kernel.edgeInfoScale.{24,60,120,240}
Baseline      : 1.5394 / 0.3230 / 0.7765 / 1.5429 / 3.1248 ms
Mechanism     : occt_shape_edge_info keeps building its own context per call.
Change        : none to its cost — the refactor moves code, not work.
Predicted     : unchanged, within the run's own noise floor. k = 0.985
                stays 0.985.
Falsifiable by: any of these five means moving by more than the measured
                floor for the family.
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
solids chosen to exercise every branch — a box (12 straight edges, all convex),
a cylinder (circular edges, a seam), a solid with a concave edge (so the
convexity sign is exercised in both directions), and a filleted solid (spline
edges, i.e. the `default:` curve-type branch). Exact equality, not a tolerance:
a tolerance would hide precisely the reordering this test exists to catch.

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
- **`sweepProfile` (§6.1, 81.9 ms mean, 392 ms worst).** Not touched. It is an
  absolute cost with a two-point slope behind it and no scaling claim; there is
  no cost model to optimise against, and §7 of the plan says an exponent whose
  interval spans nothing is not something to optimise against.
- **Adopting the bulk path inside `part_model.dart`'s `edgesOf`.** That file is
  Session 5's. `edgesOf` is `shape.allEdges()`, so it inherits the change
  without anyone editing it.
- **Re-recording `perf/baseline.json`.** Plan §0 rule 3.

