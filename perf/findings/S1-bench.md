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
- **Did one thing it should not have**, and it is recorded rather than tidied
  away: Session 1 wrote its own headers over `perf/findings/CROSS-SESSION.md`
  and `CONFLICTS.md` on the assumption that they did not exist. They did, with
  the append-only rule already at the top of each and a `README.md` beside them
  naming every session's file. Nothing was lost — both held headers and no
  entries — and the originals have been restored with Session 1's entries
  re-titled into the format those files already specified. The correction is
  `CROSS-SESSION.md`'s third entry, appended rather than substituted for the
  wrong one. `git show origin/<branch>:<path>` costs one command and would have
  prevented it.
- **Did not build a simulator lane, a sampling profiler, or the 30-minute
  session scenario.** §15.5 lists all three as unbuilt; only Lane C was
  assigned.
- **Did not predict any absolute duration.** The harness cannot support one and
  §13.3 forbids quoting one. Every prediction above is about an exponent, a
  ratio, or a scaling — quantities that transfer across machines.

## 3. Adjudication

**Capture:** `bench-out/kernel-bench-linux.*`, published to the `ci-logs-bench`
branch. Linux / x86_64, 4 cores, OCCT 7.9.3 static Release with the repository's
own `OCCT_COMMON_FLAGS`, shim v20 unmodified (`CALIBRATION.txt` hash matches, so
the gate was live). Ladder 60 / 120 / 240 / 480 profile points = 180 / 360 / 720
/ 1440 edges; 7 repetitions per operation per rung, one warm-up discarded, a
30 s wall budget per operation per rung.

**Run with `--validate`. Exit code 0. `HARNESS: VALIDATED`.**

**Two full runs were taken, and the second is the published one.** The first is
reported here as a repeatability check, because an instrument that has been run
once has not been shown to repeat — §3.2 of the profile spends a section on
exactly that, and it would be a poor joke to build a calibrated benchmark and
then quote a single run of it.

| op | run 1 k | run 2 k | R² (run 2) |
| --- | ---: | ---: | ---: |
| `build` | 1.058 | 1.079 | 0.9984 |
| `edgeInfo1` | 1.052 | **1.053** | 0.9985 |
| `allEdges` | 2.070 | **2.057** | 0.9996 |
| `buildOnly` | 0.938 | 0.978 | 0.9995 |
| `counts` | 1.006 | 1.040 | 0.9989 |
| `bbox` | 0.985 | 0.984 | 0.9972 |
| `mesh` | 0.950 | 0.945 | 0.9964 |
| `fuse` | 1.322 | 1.362 | 0.9987 |
| `cut` | 1.368 | 1.359 | 0.9969 |
| `rayHits` | 0.263 | 0.318 | 0.9591 |

The two gating exponents repeat to **0.001 and 0.013**. Nothing in the table
moves by more than 0.055, and the two that do (`rayHits`, `buildOnly`) are the
smallest and the noisiest quantities in the run.

### 3.1 The calibration — the thing the plan asks for

| op | device k | device CI (as printed) | bench k | bench CI | R² | verdict |
| --- | ---: | --- | ---: | --- | ---: | --- |
| `edgeInfo1` | 0.99 | [0.970, 1.010] | **1.053** | [0.996, 1.110] | 0.9985 | **AGREES** |
| `allEdges` | 2.012 | [1.910, 2.113] | **2.057** | [1.999, 2.115] | 0.9996 | **AGREES** |
| `buildOnly` (control) | 1.063 | [0.959, 1.167] | **0.978** | [0.948, 1.007] | 0.9995 | **AGREES** |

`allEdges` also overlaps the *tool-convention* interval [1.996, 2.027] — the
narrower of the two readings of §6.5 evidence 4 (`CROSS-SESSION.md` S1-1), so
the agreement does not depend on which convention is chosen.

**The subject and the control separate cleanly**: [1.999, 2.115] against
[0.948, 1.007], disjoint by a factor the device also found (2.012 against
1.063). §6.5 evidence 4's central claim — that this is a difference of
*exponent*, not of constant — reproduces on a machine that shares nothing with
the iPad but the source code.

### 3.2 Prediction by prediction

| | Predicted | Measured | |
| --- | --- | --- | --- |
| **P1** per-call exponent | k ∈ [0.95, 1.05], interval overlaps device | **1.053** [0.996, 1.110], R² 0.9985 | **HELD** on its falsification criterion (k outside [0.9, 1.1] or R² < 0.99 — neither); the point estimate sits **0.003 above** the narrower band quoted, in both runs, which is a fifth of the fit's own standard error (0.029) and is not a resolvable difference. |
| **P2** enumeration exponent | k ∈ [1.90, 2.10] | **2.057** [1.999, 2.115], R² 0.9996 | **HELD** |
| **P2b** composition | k(allEdges) − k(edgeInfo1) = 1.00 ± 0.08 | **1.004** (run 1: 1.018) | **HELD** — and this is the sharpest result in the run. |
| **P3** control separates | k ∈ [0.95, 1.30], interval disjoint from `allEdges` | **0.978** [0.948, 1.007], disjoint | **HELD** in run 2, **narrowly refuted on the point estimate in run 1** (0.938, twelve thousandths below the band's floor). The disjointness — the whole point — holds in both. The near-miss is worth recording rather than quietly dropping: my own reasoning said a desktop "should sit at or below" the device's 1.063, and I then wrote a band that was asymmetric *upward*. It went down, as my sentence said it would, past a floor I had no reason to set. |
| **P4** ratio growth | 3.2×–4.6× over a 4× size range | **4.02×** (64.8× at 360 edges → 260.3× at 1440) | **HELD**, near the centre. Device: 4.23× over the same range. |
| **P5** allocation | count per call linear, k ∈ [0.85, 1.15]; live bytes within ±1 kB of zero | **k = 0.9824**, R² = **0.99997**, CI [0.975, 0.989]; live delta **exactly 0** at all four rungs, in both runs | **HELD**, and more precisely than predicted. The *constant* was a guess (~12 per shape-edge) and was wrong by 6×: the real figure is **76 allocations and 10.1 kB per shape-edge, per call**. I said the constant was a guess and the exponent was the prediction; that is how it turned out. |
| **P6** fillet flat against edge count | \|k\| < 0.15, R² < 0.5 | **k = 0.636**, R² = 0.9941 | **REFUTED AS WRITTEN.** The Risk clause registered with it says why, and it was the right risk: I aimed the prediction at the plan's *summary* of §6.3 rather than at §6.3's own table. See below — the mechanism is confirmed, the target was mis-stated. |

**P2b deserves the emphasis.** §6.5 closes its mechanism by arithmetic:
0.985 + 1 = 1.985 against a measured 2.012, agreeing to 1.3 %. On this machine
the same closure gives 1.053 + 1 = 2.053 against a measured 2.057, agreeing to
**0.2 %** (run 1: 0.9 %). Two machines, two clocks, two instruction sets, one
arithmetic. That is what makes the diagnosis a property of the code rather than
of the iPad.

### 3.3 P6, in full, because a refuted prediction is a result

I predicted `fillet.edges` would be flat because `OPTIMIZATION_PLAN.md` §5 told
Session 2 it was: *"Fillet and chamfer cost the same for 1, 4 or 12 edges —
25.5 ms flat, k = 0.00 … Flat cost against a swept axis means the work is not
per-edge; find what the fixed cost is."*

It is not flat, and there is no fixed cost to find. §6.3's own table gives
`filletEdges` at 10.1 / 20.8 / 46.7 ms for 1 / 4 / 12 edges; §10.2's flat row
carries the scenario's *name* against its `ffi.occt.allEdges` child span's
*numbers*, which the appendix makes explicit. The full write-up is
`CROSS-SESSION.md` S1-4. What Lane C reproduces:

| quantity | device | Lane C |
| --- | ---: | ---: |
| blend alone, exponent over 1 → 12 edges | 0.616 | **0.639** |
| candidate search : blend at one edge | 4.9× | **5.02×** |
| search + blend (what the device span covers), exponent | — | **0.198**, R² 0.93 |
| radius r = 1 → r = 4 on the same solid | 65× | **24.3×** |

Two readings of the same run, reported as two operations, so the ambiguity that
produced the plan's brief cannot recur.

### 3.4 What the harness found that nobody asked it to

**The transient allocation traffic, which is the mechanism made concrete.**
§6.5 argues that each `edge_info` call builds four whole-shape structures and
throws them away, and supports it with `rssDeltaMB` = 0 — consistent with the
claim but equally consistent with doing nothing at all with memory. Lane C
measures the discarded work directly:

| edges | one `edgeInfo1` call | | `allEdges` over the whole solid | |
| ---: | ---: | ---: | ---: | ---: |
| | allocations | bytes | allocations | transient bytes |
| 180 | 14 152 | 1.99 MB | 2 837 909 | 0.38 GB |
| 360 | 27 714 | 3.82 MB | 11 116 356 | 1.46 GB |
| 720 | 54 838 | 7.48 MB | 44 080 127 | 5.74 GB |
| 1440 | 109 092 | 14.94 MB | **175 480 701** | **22.90 GB** |

Net heap change: **zero, at every rung, for both, in both runs.** Enumerating
the edges of a 1440-edge solid moves **22.9 GB through the allocator and keeps
none of it** — 175 million malloc/free pairs to answer 1440 questions. Per
shape-edge per call: 76 allocations, 10.1 kB, constant to 4 % across an 8×
range of size. The counts are identical to the digit between the two runs,
which is what a deterministic quantity should look like and a useful check that
the counter is measuring the program rather than the machine.

That is the same finding as §6.5's, in a currency where it is not arguable.

**The closure check, with the FFI boundary removed.** §6.5 evidence 3 multiplies
the per-call cost by the edge count and accounts for **91.9 %** of `allEdges`,
attributing the residual 8.1 % to "boundary crossings and Dart-side list
construction". Lane C is native throughout — there is no boundary and no Dart —
and still shows a residual:

| edges | accounted by per-call cost |
| ---: | ---: |
| 180 | 91.5 % |
| 360 | 91.1 % |
| 720 | 89.8 % |
| 1440 | 91.2 % |

**91.9 % on the device, 89.8–91.5 % here — and here there is no boundary to
cross and no Dart list to build.** The residual is therefore not the FFI
boundary. It is what happens when n such calls run back to back: allocator and
cache state, which a single isolated call does not pay. That the two numbers
land on top of each other while one of them has an FFI boundary and the other
has none is the strongest form the argument can take.

**This strengthens the plan's own advice.** §5 warns Session 2 that batching
from Dart "would save the boundary crossings, which are 8.1 % of the cost, and
leave the quadratic entirely intact". The saving available at the boundary is
smaller than 8.1 % — most of that residual is present without a boundary at
all. The argument for fixing this in the shim rather than in Dart is stronger
than the profile states, not weaker.

**Ray casting is clean.** `rayHits` fits **k = 0.318** [0.146, 0.489] against
shape size (0.263 in run 1) — nearly flat, and nothing like `edgeInfo1`'s 1.05 on the same
solids. Whatever `occt_shape_edge_info` does that makes it Θ(shape),
`occt_ray_hits` does not do. A useful control: the defect is not "any query on
an OCCT solid is linear in the solid".

**Booleans bend upward past the device ladder's last rung** — `fuse`
k = 1.362 [1.283, 1.441], `cut` k = 1.359 [1.245, 1.474], with the local
exponent climbing 1.22 → 1.28 → 1.48 across the ladder, against §6.2's
1.07 [1.03, 1.12] measured over a range that stops at 432 edges. Written up as
`CROSS-SESSION.md` S1-5, with a request to extend `ramp.kernel.boolean` on the
next device capture.

### 3.5 A second discontinuity in fillet, found by chasing an anomaly

`filletEx1` — one vertical corner edge, fixed 0.1 mm radius — came out at
**45.8 ms at the smallest rung against 14.5 / 29.4 / 56.9 ms at the three
larger ones**, reproducibly, across three runs. The three larger rungs double
cleanly with size (k = 1.00); the smallest is 3× its own trend.

The shim's own report rules out the obvious cause: `dropped = 0`,
`scale = 1.000000` at every rung, so no edge is being skipped and the tangency
retry ladder never fires. Two probes then separate the remaining candidates:

**A — hold `n` at 60 (the corner angle fixed at 174°, the shape fixed at 180
edges) and sweep the profile radius over 16×:**

| profile radius | facet | radius : facet | ms |
| ---: | ---: | ---: | ---: |
| 10 | 1.05 mm | 0.0955 | 32.9 |
| 20 | 2.09 mm | 0.0478 | 34.7 |
| 40 | 4.19 mm | 0.0239 | 31.6 |
| 80 | 8.37 mm | 0.0119 | 33.1 |
| 160 | 16.75 mm | 0.0060 | 32.4 |

**Flat.** The blend's size relative to the geometry it sits in does not matter.

**B — hold radius : facet at 0.0239 and sweep `n`:**

| n | edges | dihedral | ms |
| ---: | ---: | ---: | ---: |
| 60 | 180 | 174.00° | **33.1** |
| 120 | 360 | 177.00° | 10.9 |
| 240 | 720 | 178.50° | 21.8 |
| 480 | 1440 | 179.25° | 43.8 |

From `n` = 120 up the cost doubles with the shape, exactly (10.9 → 21.8 →
43.8, k = 1.00, intercept ≈ 0). Extrapolating that law back to `n` = 60 gives
≈ 5.4 ms. The observed 33.1 ms carries **an excess of about 28 ms that has
vanished by `n` = 120** — i.e. between a 174° corner and a 177° one.

So `occt_fillet_edges_ex` has a **second** cost discontinuity beside §6.3's
radius one: at fixed shape size and fixed relative radius, a blend on a
slightly-sharper corner costs several times a blend on a flatter one. It is a
function of `n` and not of the radius-to-facet ratio; whether the mechanism is
the dihedral angle itself or the topology at the blended edge's ends is not
established here, and Session 2 owns the shim. Written up for them in
`CROSS-SESSION.md` S1-6. The point for Lane C is that the question went from
"an unexplained number" to "two probes and a bounded answer" in five minutes,
which is what the instrument is for.

### 3.6 Two defects found in the harness, by running it

Both were found by the instrument being used, which is the argument for
building it:

1. **The ladder's fillet radius was derived from the ladder itself** (a quarter
   of the smallest facet it reached), so `--sizes 60,120,240` and
   `--sizes 60,120,240,480` measured different operations at the same rung. A
   benchmark whose fixture moves with its arguments cannot compare two runs,
   which is the only thing anyone wants a benchmark for. Now a fixed 0.1 mm.
2. **The ladder selected "the first filletable edge"**, whose *kind* varied with
   the rung — so the sweep measured a cap edge on one rung and a vertical corner
   on the next, and its cost went *down* as the shape grew. Now selected by arc
   length, which picks a prism's vertical corner edge at every size.

### 3.7 What is still not established

- **Whether the `filletEx1` corner-angle excess (§3.5) is caused by the
  dihedral angle specifically.** It is established that the excess depends on
  `n` and not on the radius-to-facet ratio; `n` also changes the topology at the
  blended edge's two ends, and this run cannot separate the two.
- **Absolute cost against the device.** Not established, not establishable, and
  not attempted. Lane C's `fillet.edges` at one edge is 26.5 ms against the
  device's 10.1; its `allEdges` at 1440 edges is 38.8 s against the device's
  10.0 s. These say nothing except that the two machines differ, which §13.3
  already said.
- ~~**Whether the exponents hold on arm64.**~~ **Settled — see §3.8.**
- **Any claim that an optimisation works.** Nothing has been optimised. That is
  Sessions 2–5's work, and this is the instrument they may now use between
  device captures.


## 4. arm64 — the ISA the plan actually asked for

§15.5 named a mac runner for one reason: the same ISA family as the iPad chip.
The macOS job finished its cold OCCT build in CI run 32236240201 and published
to `ci-logs-bench/macos/`. **It lands closer to the device than the x86_64 job
does:**

| op | device | Lane C arm64 | Lane C x86_64 |
| --- | ---: | ---: | ---: |
| `edgeInfo1` | 0.99 [0.970, 1.010] | **0.989** [0.889, 1.090] | 1.053 [0.996, 1.110] |
| `allEdges` | 2.012 [1.910, 2.113] | **1.975** [1.930, 2.021] | 2.057 [1.999, 2.115] |
| `buildOnly` | 1.063 [0.959, 1.167] | 0.982 [0.906, 1.058] | 0.978 [0.948, 1.007] |
| **P2b** composition | — | **0.986** | 1.004 |

`edgeInfo1` on arm64 reproduces the device's per-call exponent **to 0.001**.
Both jobs are `HARNESS: VALIDATED`; the arm64 one is the number to quote.

**This also resolves something the x86_64 run left open.** Its `edgeInfo1` sat
at 1.05 with a tight interval — inside the device's when the interval was wide
and only barely overlapping when it narrowed. That looked like it might be a
defect in the harness. It is not: on arm64 the same code, the same fixture and
the same fit give 0.989. The 1.05 is an x86_64 property, and the honest reading
is that the *x86_64 job's* `edgeInfo1` exponent runs a few percent hot and
should not be the one anyone quotes. It still gates, because a harness whose
gate only bites where it is comfortable is not a gate — but the arm64 figure is
the one that answers "does Lane C reproduce §6.5".

**The allocation counters agree across the two platforms to the digit** — 14 152
/ 27 714 / 54 838 / 109 092 allocations per `edgeInfo1` call, and 2 837 909 /
11 116 356 / 44 080 127 for `allEdges`, identical on Linux under `ld --wrap` and
on Darwin under the zone interposition. Two different interposition mechanisms,
two different libc++/libstdc++, one number. That is the strongest available
evidence that the counter measures the program rather than the machine, and it
was not designed as a test — it fell out of running the same binary logic twice.
Byte totals differ by 5–7 % between platforms, which is allocator granularity
and is what should differ.