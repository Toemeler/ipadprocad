# Session 1 — Lane C: a measurement loop that does not need an iPad

`OPTIMIZATION_PLAN.md` §5, Session 1. `PERFORMANCE_PROFILE.md` §15.5 specified
this instrument and it was never built; §2 of the plan says why it matters now.

> **Read §2's rule before the numbers below.** Predictions are registered
> *before* the change and adjudicated afterwards, whether or not they survive.
> A prediction that comes out wrong is a result and is written up as one.

---

## 0. What Session 1 is, and what "done" means for it

Every other session is flying blind between now and the user's next device
capture. Session 1 does not optimise anything: it builds the loop that lets the
kernel sessions see their own work in minutes.

The plan's own definition of done:

> the bench runs in CI, publishes durable output, and its fitted exponents for
> `edge_info` and `allEdges` agree with §6.5 within their confidence intervals.
> Report the agreement explicitly in your findings file — that comparison is
> the harness's validation.

So the deliverable is not "a benchmark". It is **a benchmark that has been
shown to reproduce the device's finding**, plus the delivery path that makes
its numbers readable, plus the honest statement of what it may not be used for.

---

## 1. Pre-registered predictions

Registered **before** the harness was first run against a built OCCT. The build
of OpenCASCADE was still in progress when this section was written; the
adjudication is §3.

Session 1's predictions are about the *instrument*, not about an optimisation.
That is the right target: nobody may use this harness to judge Session 2's or
Session 5's work until these hold.

---

### Prediction P1 — the harness reproduces the per-call exponent

```
Target        : bench op `edgeInfo1` — one occt_shape_edge_info against a
                growing shape, fitted against edge count
Baseline      : k = 0.99, R² = 0.9999, 95 % CI [0.97, 1.01]
                (PERFORMANCE_PROFILE.md §6.5 evidence 2; the compositional
                closure paragraph of the same section quotes 0.985, and
                refitting the four published rungs gives 0.9887)
Mechanism     : occt_shape_edge_info performs four WHOLE-SHAPE operations per
                call and discards all four — TopExp::MapShapes,
                TopExp::MapShapesAndAncestors, BRepBndLib::Add, and the
                construction of a BRepClass3d_SolidClassifier (the latter two
                in the convexity branch, taken for any edge with two adjacent
                faces, which on a closed solid is most of them). All four are
                linear in the size of the shape.
Change        : none — this is the instrument being checked against the device.
Predicted     : k in [0.95, 1.05]; the 95 % interval overlaps [0.97, 1.01]
Derivation    : the work per call is a constant number of whole-shape
                traversals, each Θ(subshapes). Subshape count of an n-gon prism
                is exactly 3n edges + (n+2) faces + 2n vertices, i.e. Θ(n). One
                fixed unit of requested work over a Θ(n) traversal is k = 1.
                The device measured 0.9887 against that ideal 1.000, a
                deviation of 1.1 % attributable to the fixed per-call cost that
                does not scale. The desktop's ratio of fixed to scaling cost
                differs, so the tolerance is widened from the device's ±0.02 to
                ±0.05 — but not the direction: anything at or below ~0.5 means
                the traversal is not happening and the fixture is wrong.
Falsifiable by: a fitted k below 0.9 or above 1.1, or an R² below 0.99.
                Either says the harness is measuring something other than what
                §6.5 measured.
Risk          : the inner-loop repetition could let the CPU cache the whole
                shape in L2 at small rungs and not at large ones, which would
                INFLATE the exponent. If k lands near 1.2–1.4 with high R²,
                suspect this before suspecting the kernel.
```

### Prediction P2 — the harness reproduces the quadratic

```
Target        : bench op `allEdges` — the per-edge enumeration, fitted against
                edge count
Baseline      : k = 2.012, R² = 1.0000, 95 % CI [1.910, 2.113]
                (§6.5 evidence 4, reference arm, LPM off)
Mechanism     : allEdges issues one occt_shape_edge_info per edge. With P1's
                per-call cost being Θ(shape), n calls give n × Θ(n).
Change        : none — instrument check.
Predicted     : k in [1.90, 2.10]; the 95 % interval overlaps [1.910, 2.113]
Derivation    : composition, exactly as §6.5 does it. P1's exponent + 1.
                0.985 + 1 = 1.985 predicted the device's measured 2.012, an
                agreement of 1.3 %. The same arithmetic applies here: whatever
                `edgeInfo1` fits, `allEdges` must fit within about 0.05 of it
                plus one. THAT internal consistency is the stronger test, and
                it is checked below as P2b.
Falsifiable by: k outside [1.85, 2.15], or an R² below 0.995.
Risk          : none specific. If P1 holds and P2 fails, the harness is
                measuring the two things inconsistently and both numbers are
                suspect.
```

### Prediction P2b — internal consistency, which needs no device at all

```
Target        : k(allEdges) − k(edgeInfo1)
Baseline      : exactly 1, by arithmetic, not by measurement
Predicted     : 1.00 ± 0.08
Derivation    : n calls each costing Θ(n^a) gives Θ(n^(a+1)). This holds on any
                machine, at any clock, under any thermal state. It is the one
                prediction in this file that a desktop can adjudicate on its own
                authority, and it is therefore the most valuable: a harness that
                satisfies P2b is internally coherent even if it disagrees with
                the device on the absolute exponents.
Falsifiable by: a difference outside [0.92, 1.08].
Risk          : `allEdges` re-reads occt_shape_edge_count once per iteration
                while `edgeInfo1` does not. That is one extra Θ(n) traversal
                spread over n calls — a Θ(1) contribution per call, which
                cannot move the exponent.
```

### Prediction P3 — the control separates

```
Target        : bench op `buildOnly` (build + counts + full mesh) against edges
Baseline      : k = 1.063, 95 % CI [0.959, 1.167] (§6.5 evidence 4)
Predicted     : k in [0.95, 1.30], and its interval DISJOINT from allEdges'
Derivation    : building and tessellating an n-gon prism is linear in n — n
                lateral faces, each meshed independently. The device's 1.063
                carries a small superlinear component; a desktop with more cache
                should sit at or below it. The tolerance is asymmetric upward
                because tessellation memory traffic can bend it.
Falsifiable by: overlap between the two intervals. That would mean the fixture
                does not separate the subject from the control, and the whole
                comparison in §6.5 evidence 4 would fail to reproduce.
Risk          : at 1440 edges the mesh is large enough to leave cache; if the
                top rung bends upward, report the local exponents rather than
                only the fit.
```

### Prediction P4 — the ratio grows, and by a computable factor

```
Target        : allEdges / buildOnly, at the bottom and the top of the ladder
Baseline      : device 47.4x at 360 edges, 200.3x at 1440 edges — a growth of
                4.23x across a 4x range of size (§6.5 evidence 4)
Predicted     : the ratio at 1440 edges divided by the ratio at 360 edges lands
                in [3.2, 4.6]
Derivation    : the ratio scales as n^(k_allEdges − k_buildOnly). Using the
                device's exponents, 2.012 − 1.063 = 0.949, and a 4x change in n
                gives 4^0.949 = 3.65x. The device's observed 4.23x sits above
                that because its two fits are drawn through the same three
                points the ratio is read from. The interval spans the
                predictions from both exponent pairs.
Falsifiable by: a ratio that does not grow, which would mean a difference in
                CONSTANT rather than in exponent — and would refute the whole
                §6.5 diagnosis on this machine.
Risk          : the absolute ratio on a desktop will NOT be 47x and 200x, and
                nobody should expect it to be. Only its growth is predicted.
```

### Prediction P5 — the allocation counters see the discarded work

```
Target        : `edgeInfo1` alloc_calls and live_bytes per call
Baseline      : `stress.allEdges.rssDeltaMB` = 0 MB across the whole device
                ladder (§6.5). Consistent with "builds and discards", but not
                distinguishable by RSS from "does nothing with memory".
Mechanism     : per call OCCT builds a TopTools_IndexedMap over the edges
                (Θ(n) cells), an IndexedDataMapOfShapeListOfShape from edges to
                faces (Θ(n) cells plus a list node per adjacency, and a closed
                prism has 2 faces per edge), a Bnd_Box filled by traversing
                every face, and a solid classifier. Every one is freed on
                return.
Predicted     : alloc_calls per `edgeInfo1` call grows LINEARLY with edge count,
                fitting k in [0.85, 1.15]; and live_bytes per call is within
                ±1 kB of zero at every rung.
Derivation    : allocation count is dominated by the two maps. A
                NCollection map of m entries allocates its bucket array plus one
                cell per entry, so ~m + O(1) allocations; the ancestor map adds
                one list node per (edge, face) incidence, of which there are
                2 × 3n = 6n on a closed n-gon prism. Total of order
                3n + 3n + 6n ~ 12n allocations per call, i.e. strictly linear.
                The constant is a guess; the EXPONENT is not, and that is what
                is predicted.
                live_bytes near zero follows from every structure being a local
                whose destructor runs before return — the same claim the device's
                0 MB rssDelta supports, measured here at a resolution RSS
                cannot reach.
Falsifiable by: a flat allocation count against shape size, which would put the
                cost somewhere other than the four traversals; or a live_bytes
                that climbs, which would mean the call LEAKS and would be a far
                more urgent finding than the quadratic.
Risk          : the counters do not see allocations made inside libc itself.
                For OCCT's own manager and for libstdc++'s operator new they do
                (bench_alloc.cpp interposes on both; the self-test proves it).
```

### Prediction P6 — the fillet cost is flat against edge count

```
Target        : bench op `fillet.edges`, swept over 1 / 4 / 12 edges blended on
                a fixed ring(24, 40) x 10 solid
Baseline      : 25.5 ms flat, k = 0.00, reproduced under both clocks and across
                two builds (§6.3, §10.2)
Predicted     : |k| < 0.15 and R² < 0.5 — a stated ABSENCE of relationship
Derivation    : a flat cost against a swept axis means the work is not
                per-edge. §6.3 already localises most of it: the candidate
                search costs 4.9x the blending at one edge, and the candidate
                search is an enumeration, which is Session 2's quadratic in a
                different hat.
Falsifiable by: a k above 0.3, which would mean the desktop DOES see per-edge
                cost and the device's flatness is a clock artefact.
Risk          : this harness times only the blend call, whereas the device
                scenario also builds the candidate list inside the same span.
                If the flatness comes from the candidate search dominating,
                this harness will NOT reproduce it — and that is a useful
                result, not a harness failure. `filletCandidateSearch` is
                measured separately so the two can be told apart.
```

---

## 2. What Session 1 deliberately did not do

- **Did not touch `backend/occt/shim/**` or `frontend/lib/ffi/occt_engine.dart`.**
  Session 2 owns them. The harness reaches `occt_capi` through
  `add_subdirectory`, so the shim can change underneath it without either side
  needing to know.
- **Did not re-record `perf/baseline.json`, and did not edit
  `PERFORMANCE_PROFILE.md`.** §3 and §7.
- **Did not fix the interval-convention discrepancy** it found in §6.5
  (`CROSS-SESSION.md` S1-1). It is in a file nobody edits, and the harness
  works around it in the open by reporting against both conventions.
- **Did not build a simulator lane, a sampling profiler, or the 30-minute
  session scenario.** §15.5 lists all three as unbuilt; only Lane C was
  assigned.
- **Did not predict any absolute duration.** The harness cannot support one and
  §13.3 forbids quoting one. Every prediction above is about an exponent, a
  ratio, or a scaling — quantities that transfer across machines.

## 3. Adjudication

*(filled in below, after the first run against a built OCCT)*
