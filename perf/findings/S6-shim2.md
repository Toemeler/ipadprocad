# S6 — The quadratic that survived

Session 6 of `OPTIMIZATION_PLAN_2.md`. Owns `backend/occt/shim/**` and
`frontend/lib/ffi/occt_engine.dart`.

Everything above `## 6. Results` was written **before any shipping code was
changed**, which is the point of it (`OPTIMIZATION_PLAN.md` §2). Nothing here
is a device measurement; this session has no device, and §13.3 forbids quoting
a desktop millisecond as an iPad millisecond.

---

## 0. STATUS FOR THE INTEGRATOR — read this first

**Session 6 is COMPLETE, and it needs one ruling before anything of it can
merge: the change is NOT bit-identical.** Everything else is done, built and
run against real OCCT.

**What is proposed:** shim **v22** — the convexity sign (field 11) decided
locally from the two into-face directions instead of by a solid classifier,
plus the restoration of `1c4735f`'s face-edge orientation index (this reverts
`c5f7e21`). One change, not two: the index alone is a wash and S2 was right to
revert it (§4.3.5).

| | |
| --- | --- |
| Exponent, `allEdgesBulk` | **1.9421 [1.9123, 1.9719] → 1.0757 [1.0015, 1.1499]** — Lane C's own binary, same machine, before and after. Disjoint intervals. |
| Cost at 1440 edges | 1714.9 ms → **9.23 ms**, and the factor grows with size (30.8× → 185.8×) |
| Predicted, before the change | k = 1.00, interval [0.95, 1.10]. **P1 upheld.** P2 upheld on both halves. |
| Mechanism | `BRepClass3d_SolidClassifier::Perform`, **98.6 %** of the enumeration, pinned to two lines of OCCT V7_9_3 (§2.2) |
| Allocations per edge | 1025 / 1760 / 3231 / 6171 → **33.7 at every rung** |
| Behaviour | **CHANGES.** 10 sign flips in 7 644 edges over 15 fixtures, all on features thinner than `‖bbox diagonal‖/1414` — and on every one the *pre-v22* path is wrong (§5.1) |
| Differential test | smoke **`[36]`**, old path against new, same run, same machine, bitwise (§6.3) |
| Verified on real OCCT | here, OCCT V7_9_3 `a016080b` built from the submodule with `kernel-bench.yml`'s flags. `[35]` and `[36]` green, **`OCCT SMOKE: PASS`** |
| Lane C | **`LANE C: PASS`** on both the v21 and the v22 run; the harness verdict flips on `edgeInfo1`, and §7.5 says exactly why and why CI needs nothing |
| `python3 -m unittest discover -s ci` | **45 passing** |
| `flutter analyze` / `flutter test` | **NOT RUN — no Flutter SDK in this container.** The Dart diff is 16 lines, every one a `///` comment (§6.4) |
| Files touched outside this session's ownership | **none.** `perf/baseline.json`, `PERFORMANCE_PROFILE.md`, `perf*.dart`, `backend/bench/**`, `S2-shim.md` — untouched |

**The three decisions I need are in §9**, and `CROSS-SESSION.md` S6-1 … S6-4
carry them. In short: (1) is a repair that changes behaviour acceptable, given
field 11's one consumer and its absence from every persisted fingerprint;
(2) the sequencing gate below; (3) do **not** re-record `CALIBRATION.txt` to
clear §7.5.

### 0.1 The sequencing gate is NOT satisfied, and I said so before starting

`OPTIMIZATION_PLAN_2.md` §1.1 and §5 (S6) both say: **wait for
`perf-capture-round1`.**

```
$ git fetch origin --tags && git tag --list 'perf-capture-round1'
(nothing)
```

The tag does not exist. Nor does `claude/perf-opt2`. So round one's paired
device capture has not been taken, and the reason the gate exists — that a
number which moved would belong to either round — is live.

**What I did about it.** The gate protects *the branch the capture is taken
from*, not the act of thinking. So:

- I based this work on `claude/perf-opt` at **`a762656`** (round one's tip,
  the commit the tag would name today) and developed on
  `claude/edge-path-quadratic-exponent-990pqs`, which is the branch this
  session was given.
- **I have not pushed to `claude/perf-opt`, and I have not created
  `claude/perf-opt2`.** Round one's attribution is intact: nothing this
  session did can appear in a capture taken from `claude/perf-opt`.
- Plan §3 says the first round-two session creates the integration branch
  *from the tag*. I am not that session, because there is no tag to create it
  from. Definition-of-done item 6 ("merged cleanly into `claude/perf-opt2`")
  is therefore **not met and cannot be met by me**.

`**Needs:** integrator` — take the capture, tag it, then rebase-free *merge*
this branch into `claude/perf-opt2` when you create it.

---

## 1. What round one left, and one thing my brief got wrong

### 1.1 The measured position

Round one's S2 added `occt_shape_edges_info` (shim v21): one traversal of the
shape for all edges instead of one per edge. Lane C measured it
(`CROSS-SESSION.md` S1-7, `S2-shim.md` §7):

| | Linux/x86_64 | macOS/arm64 |
| --- | --- | --- |
| 180 edges | 502.1 → 33.18 ms | 343.1 → 19.85 ms |
| 360 edges | 2 312.4 → 125.11 ms | 1 320.3 → 69.47 ms |
| 720 edges | 9 010.4 → 456.97 ms | 5 423.0 → 316.88 ms |
| 1440 edges | 36 702.0 → **1 775.37 ms** | 22 372.4 → **1 108.44 ms** |
| exponent, per-edge | 2.054 [1.984, 2.123] | 2.012 |
| exponent, bulk | **1.909 [1.887, 1.932]** | **1.960 [1.854, 2.066]** |

Cost fell 20.7×. The exponent did not follow.

**And S1 corrected itself on how much of an exponent drop is established:** on
arm64 the two intervals *overlap*, so "the exponent fell by 0.145" is one
platform's noise wearing a result's clothes and was withdrawn. The defensible
statement is the narrow one:

> The bulk path is ~20× faster and **remains quadratic**, k ≈ 1.91–1.96 across
> two platforms.

That is the baseline this session must beat, and it is an *exponent*.

### 1.2 The mechanism my brief names has been retracted — by the session that found it

My brief says S2 found the mechanism to be "a `TopExp_Explorer` over each
adjacent face's edges, once per edge". **`S2-shim.md` §7.6 withdraws that**, and
it is the first thing to get straight, because starting from a retracted
mechanism is worse than starting from none:

- S2 built the face-edge orientation index that removes that scan (`1c4735f`).
- Lane C measured it, same branch, same platform, back to back: **~2 % slower
  at every rung, exponent unmoved** (1.901 → 1.907).
- S2 reverted it in **`c5f7e21`** and worked out the constant it had never
  worked out before the change: the scan is `2n × O(n)` *iterator steps*, about
  4.6 × 10⁵ steps at n = 480 against a 1.19 × 10⁹ ns runtime — **under 0.5 % of
  the enumeration.**
- §7.6 also retracts the *evidence*: the allocation fit
  `alloc/edge = 12.252·n + 290` cannot be about the scan at all, because
  `TopExp_Explorer` walks lists that already exist and does not allocate per
  step. The fit "is still real and still unexplained".

So the standing nomination at the end of round one is Session 1's, not S2's:
`BRepClass3d_SolidClassifier::Perform` (`CROSS-SESSION.md` S1-7), explicitly
labelled "a hypothesis from the measurement, not a reading of OCCT's source",
with a specific experiment attached that nobody ran:

> the way to settle it is a variant that skips the convexity branch and a
> rerun of the same ladder.

**That experiment is §4 of this file.** Running it first is the whole design of
this session: S2's failure was not the index, it was shipping an asymptotic
argument with no constant attached. The order here is measurement, then
prediction, then code.

---

## 2. The mechanism, read out of OCCT's source rather than inferred

Round one had a hypothesis. This is the reading, against the pinned kernel —
OCCT **V7_9_3**, submodule commit `a016080b`, the exact source the app links.
Line numbers are that tree's.

### 2.1 Everything per-edge except one call is O(1) in shape size

`edge_info_one` (`backend/occt/shim/occt_capi.cpp:2280`) does, per edge:

| step | cost in shape size |
| --- | --- |
| `ctx.edges.FindKey(index)` | O(1), indexed map |
| `BRepAdaptor_Curve`, `GCPnts_AbscissaPoint::Length`, `D1`, `GetType` | O(1) |
| `edgeFaces.Contains` / `FindFromKey` | O(1), hashed on the TShape |
| `BRep_Tool::CurveOnSurface(edge, face, …)` ×2 | O(representations of the edge) ≈ O(1) |
| `BRepAdaptor_Surface` + `D1` ×2 | O(1) |
| `into_face_dir`'s `TopExp_Explorer` scan ×2 | **Θ(edges of the face)** — S2's < 0.5 % |
| **`cls.Perform(point, 1e-7)`** | **see below** |

The four whole-shape objects are already hoisted into `edge_info_ctx` and built
once per enumeration; that was S2's v21 change and it is what bought the 20.7×.

### 2.2 `BRepClass3d_SClassifier::Perform` is Θ(shape) per call, twice over

`src/BRepClass3d/BRepClass3d_SClassifier.cxx:199`. Two independent
size-proportional terms, neither of them the geometric query:

**(a) It rebuilds the edge→face ancestor map of the whole solid on every
call.** Lines 227–228, unconditional, before any geometry:

```cpp
TopTools_IndexedDataMapOfShapeListOfShape mapEF;
TopExp::MapShapesAndAncestors(SolidExplorer.GetShape(), TopAbs_EDGE, TopAbs_FACE, mapEF);
```

That is Θ(E + edge-face incidences) of allocation per `Perform`, and `mapEF` is
then read only inside one conditional branch (line 319) that a generic ray
never enters. **This is the same map the shim already built once and holds in
`ctx.faces()`** — OCCT rebuilds its own copy per query and there is no hook to
pass one in.

**(b) It intersects the ray against every face, with the rejection tests
stubbed out.** Lines 343–351 loop over all shells and all faces; the two
filters that loop consults are:

```cpp
Standard_Boolean BRepClass3d_SolidExplorer::RejectShell(const gp_Lin&) const { return Standard_False; }
Standard_Boolean BRepClass3d_SolidExplorer::RejectFace (const gp_Lin&) const { return Standard_False; }
```

(`BRepClass3d_SolidExplorer.cxx:1025` and `:1075`.) They reject nothing, ever.
So every `Perform` runs `Intersector3d.Perform` — plus a `Bounding()` and a
`GetAddToParam` — once per face of the solid.

`Segment` (`:1090`) additionally resets `myFirstFace = 0`, so `OtherSegment`
(`:478`) restarts its face walk from face 1 on every call, running an
`Extrema_ExtPS` (`:563`) on each face it touches until one yields a
non-grazing ray. That is O(1) faces in the common case and unbounded in the
bad one.

### 2.3 This is what the allocation counter was measuring all along

Lane C's counters, collected for another purpose (`S2-shim.md` §7.2):

```
alloc/edge = 12.252·n + 290.0        residuals < 0.1 % at all four rungs
```

where n is profile points. The fixture is `extrudeProfileArcs(ringProfile(n, 40), 10)`:
**E = 3n edges, F = n + 2 faces**. A per-edge cost proportional to *the ancestor
map of the whole shape* — 3n map entries and 6n list nodes per call — produces
a slope of exactly this order and is *unconditional*, which is what the fit's
sub-0.1 % residuals want. The intersection loop (b) contributes too, but
`RejectFace` returning false means it runs the bbox test and `IntCurvesFace_Intersector`
per face rather than allocating twelve blocks each.

S2 attributed the same fit to "≈ 12 allocations per face" in the classifier and
could not exclude it; §2.2(a) says which half, and says it from the source.

**Neither term can be removed from outside OCCT.** `mapEF` is a local variable;
`RejectFace` is a virtual whose only override is the one shown. Editing the
submodule is forbidden (`backend/occt/VENDOR.md`: "do not edit, ever"). So the
per-edge classifier call is a fixed Θ(shape) price, and the only lever this
session has is **how many times it is paid**.

### 2.4 What the convexity sign actually reaches — checked, not assumed

My brief says "edge indices, adjacency and orientation feed the fingerprints
that reattach features across rebuilds. Get one wrong and parts silently
reattach fillets to the wrong edge on load." That is true of the record's
**fields 0–9**, and the classifier touches none of them.

The classifier writes **field 11 only** (field 10, the dihedral angle, is
computed from the two normals before the classifier is consulted). Following
field 11 through the app:

| | |
| --- | --- |
| `OcctEdgeInfo.convexity`, `isConvex`, `isConcave` | `frontend/lib/ffi/occt_engine.dart:233, 277, 280` |
| Consumers in `frontend/lib` | **exactly one** — `app_state.dart:9204`, inside `selectAllEdges({required bool concave})`, M142's "All Fillets" / "All Rounds" |
| In the persisted edge fingerprint `EdgeSel` | **no.** `EdgeSel` stores `mx, my, mz, length, kind, radius` (`part_model.dart:1820-1828`) and `EdgeSel.score` reads `filletable` (kind, length, faceCount), kind, midpoint, radius and length (`:1838-1875`). Convexity is not stored and not scored. |
| In `dihedralDeg` consumers | **none** |

So a wrong sign in field 11 mis-fills a selection set **in front of the user,
at selection time**, on one menu command. It cannot silently reattach a blend
across a rebuild, because it is never written to a fingerprint and never read
back on load.

This is stated because it changes what risk the human is being asked to weigh,
not because it licenses anything: it is still the field that decides fillet
from round, and §5 keeps the differential pin bitwise on all twelve doubles
regardless.

---

## 3. The design space, enumerated before measuring

Given §2.2 — the per-call price is fixed — there are exactly three ways to move
the exponent, and two of them are closed.

### 3.1 Closed: make the call cheaper

No hook exists (§2.2). Editing the submodule is forbidden. Nothing to try.

### 3.2 Closed: call it fewer times, by memoising on the face pair

`S2-shim.md` §7.4 already rules on this and is right: two edges sharing the
same two faces have the same answer *only when the faces meet the same way
along their whole length*, which is false in general. It also buys nothing on
the ladder fixture, where every face pair occurs exactly once.

### 3.3 Closed: call it fewer times, by certifying a local test against proximity

A local wedge test is exact wherever the query point stays inside the tangent
wedge. That could in principle be certified per edge — "no other boundary
within `step` of the edge midpoint" — via a bounding-box tree over faces, built
once, queried in O(log F).

**It fails on the ladder's own fixture, and the arithmetic says so before any
code.** `step` is shape-wide: `1e-3 × ‖bbox diagonal‖`
(`occt_capi.cpp:2236-2245`). For `ringProfile(n, 40)` extruded 10:

```
diag = sqrt(80² + 80² + 10²) = 113.58      step = 0.1136
facet length = 2·40·sin(π/n)
    n = 480 :  0.5236     half-facet 0.262   >  step   ok
    n = 960 :  0.2618     half-facet 0.131   ≈  step   marginal
    n = 1920:  0.1309     half-facet 0.065   <  step   FAILS
```

The certificate stops holding at exactly the sizes the ladder is built to
reach, so the fallback rate would rise with n — the wrong scaling for a fix
whose whole purpose is the exponent. Closed.

*(Worth recording separately: the same arithmetic says the shipped code's
`step` is not scaled to local feature size, so above n ≈ 960 the query point
leaves the neighbourhood of its own edge. That is a property of the status quo,
not of any change. §8.)*

### 3.4 Open: call it O(1) times per shape

The classifier is a *global* procedure answering what is, for a valid manifold
solid, a *local* question. The local answer is the scalar triple product, and
the shim already computes both operands:

```
u1 = n1 × T          (into face 1, T the tangent along face 1's traversal)
u2 = n2 × (−T)       (into face 2, which traverses the shared edge the other way)
u1 · n2 = (n1 × T) · n2 = T · (n2 × n1) = u2 · n1        — an identity, not an approximation
convex  ⟺  u1 · n2 < 0
```

The two dot products are *equal by vector algebra*, so there is no second
opinion to be had from computing both.

**Why this is not simply a drop-in.** The two procedures respond differently to
a globally reversed shell:

| | `u1`, `u2` | `Q = pm + step·(u1+u2)^` | classifier `IN(Q)` | `u1 · n2` |
| --- | --- | --- | --- | --- |
| faces outward | u1, u2 | Q | answer | σ |
| every face reversed | **unchanged** — `(−n)×(−T) = n×T` | **unchanged** | **unchanged** | **−σ** |

So the shipped behaviour is a property of the *point set* and the local test is
a property of the *declared normals*. They can be reconciled with **one**
whole-shape orientation fact per enumeration — Θ(F) once, not Θ(F) per edge —
which is the shape of a fix that moves the exponent.

What it does **not** reconcile is the genuinely local disagreements: a query
point that crosses another part of the boundary (§3.3's regime), and a query
point landing inside the classifier's ON-tolerance of an edge or vertex, where
`Perform` returns `TopAbs_ON` and the shim maps everything that is not
`TopAbs_IN` to −1.

**Those are behaviour changes, they are narrow, and §1.2 of the plan does not
let S6 make them on its own authority.** The obligation this creates is §5's:
the differential test hunts for them on adversarial fixtures, and whatever it
finds is reported rather than tolerated.

---

## 4. The measurement — the experiment S1 asked for, finally run

`CROSS-SESSION.md` S1-7 named the experiment and nobody ran it:

> the way to settle it is a variant that skips the convexity branch and a
> rerun of the same ladder.

### 4.1 The apparatus, and why it can be believed

Round one had to post a job to CI and wait. This session built the kernel
locally instead: OCCT **V7_9_3** (`a016080b`) configured with
`kernel-bench.yml`'s `OCCT_COMMON_FLAGS` **verbatim**, Release, static, gcc
13.3, Linux/x86_64 — plus the repo's own `bench_stats.cpp` for the fit, so the
exponents come out of the same arithmetic Lane C and `ci/perf_profile.py` use.
One binary carries the shim compiled five ways and switches between them with a
global, so **every variant runs on the same solids in the same process**: no
run-to-run drift, no cross-machine comparison, which is the confound §7.6 of
`S2-shim.md` had to fight.

Two independent checks that this is the same program Lane C measures:

| | this machine | Lane C published |
| --- | --- | --- |
| stock `allEdgesBulk` exponent | **1.889 [1.755, 2.023]** | 1.901 [1.858, 1.943] linux · 1.960 [1.854, 2.066] arm64 · 1.909 dev-VM |
| allocations at 180 / 360 / 720 / 1440 edges | **184 544 / 633 459 / 2 326 372 / 8 885 798** | **184 544 / 633 459 / 2 326 372 / 8 885 798** |

The allocation counts agree **to the digit at every rung**. The intervals on
the exponent overlap Lane C's on both platforms and the device's 2.012
[1.910, 2.113]. This harness is measuring the thing.

### 4.2 The decomposition — 2 × 2, one process, 7 repetitions

`occt_shape_edges_info` on `extrudeProfileArcs(ringProfile(n, 40), 10)`, the
ladder's own fixture. Rows are what supplies the edge orientation, columns what
decides the convexity sign.

**Milliseconds at 1440 edges (480 profile points, 482 faces):**

| | classifier (shipped) | local wedge |
| --- | ---: | ---: |
| `TopExp_Explorer` scan (shipped) | **1375.26 ± 24.12** | 18.47 ± 0.83 |
| orientation index (`1c4735f`) | 1361.56 ± 40.17 | **7.115 ± 0.026** |

**Fitted exponent over 180 → 1440 edges:**

| | classifier | local wedge |
| --- | --- | --- |
| scan | **1.889 [1.755, 2.023]** | 1.336 [1.191, 1.482] |
| index | 1.910 [1.804, 2.016] | **0.996 [0.971, 1.020]**, R² 0.9997 |

Full ladders:

| edges | stock | wedge + scan | wedge + index | floor (no convexity at all) |
| ---: | ---: | ---: | ---: | ---: |
| 180 | 26.898 | 1.173 | 0.905 | 0.726 |
| 360 | 86.893 | 2.427 | 1.740 | 1.435 |
| 720 | 316.018 | 6.542 | 3.557 | 2.925 |
| 1440 | **1375.262** | 18.469 | **7.115** | 5.834 |
| **k** | 1.889 | 1.336 | **0.996** | 1.004 [0.993, 1.016] |

### 4.3 What that settles

**1. The residual quadratic is `BRepClass3d_SolidClassifier::Perform`, and it is
98.6 % of the enumeration.** Skipping only the classifier, everything else
untouched: 1375.262 → 18.910 ms at 1440 edges. The classifier is
**1356.35 ms of 1375.26**. Session 1's nomination is upheld; §2.2 says which
two lines inside it.

**2. The allocation fit that S2 left "still real and still unexplained" is
explained.** With the classifier replaced, allocations per edge stop depending
on n at all:

| edges | classifier: alloc/edge | local wedge: alloc/edge |
| ---: | ---: | ---: |
| 180 | 1 025.2 | **33.7** |
| 360 | 1 759.6 | **33.7** |
| 720 | 3 231.1 | **33.7** |
| 1440 | 6 170.7 | **33.7** |

Exactly constant, to one decimal, over an 8× range; 8 885 798 → 48 497 calls at
the top rung, a factor of 183. `alloc/edge = 12.252·n + 290` was the ancestor
map OCCT rebuilds inside every `Perform` (§2.2a).

**S2's discarded falsification criterion was the right one, aimed at the wrong
term.** `S2-shim.md`'s P5 says, and then marks SUPERSEDED and "wrong":

> If the scan is the whole n-dependent term, alloc/edge becomes ~290 CONSTANT
> … A counter that stays proportional to n refutes this outright and hands the
> finding straight to `BRepClass3d_SolidClassifier::Perform`.

The counter did stay proportional to n, it did hand the finding to `Perform`,
and pointed at `Perform` it now reads exactly as that sentence says it would.

**3. The scan is what remains, and only once the classifier has gone.** With
the classifier in place the scan is 13.37 ms of 1375.26 — **0.97 %**, which is
why Lane C measured S2's index as a wash and why reverting it was right. With
the classifier gone it is 13.37 of 18.91 — **70.7 % of what is left**, and it
is what holds the exponent at 1.336 instead of 1.0.

`S2-shim.md` §7.7 called this in advance, and it is worth quoting because the
session that wrote it had just been refuted and still got the next step right:

> If the classifier is fixed later and the enumeration's constant drops by the
> order §7.4 implies, the scan may well surface as the next term worth
> removing. The commit is in the history and is one `git revert` from returning
> — **with a measurement, next time, rather than an exponent.**

This is that measurement.

**4. `1c4735f` now compiles and passes `[35]` on real OCCT — the second of
S2's two reasons for reverting is discharged.** S2 reverted partly because the
index "has never been compiled anywhere": its `occt-build.yml` run was
cancelled before the smoke test ran. Built here against real OCCT and run:

```
[35] box: 0 of 12 records differ        [35] cylinder: 0 of 3 records differ
[35] L-prism: 0 of 18 records differ    [35] filleted: 0 of 15 records differ
[35] 24-gon: 0 of 72 records differ
[35] coverage: convex edges 116, concave edges 1, curve-kind mask 0x6
OCCT SMOKE: PASS
```

120 edges over five fixtures, zero differing records, whole suite green.

**5. The two changes are one change.** The index on its own, with the
classifier still there, moves nothing measurable (1375.26 → 1361.56 ms,
intervals wide open, k unmoved) — S2 measured −2 % on its machine and this one
measures +1 %, which together say "no effect". It is worth having **only**
because the classifier goes with it. They ship together or not at all.

---

## 5. The equivalence sweep — and it did NOT come out clean

Run before writing the change, on fixtures chosen to break the local test
rather than flatter it. Mode 0 (classifier) against mode 3 (local wedge),
**bitwise on all twelve doubles**, same binary, same process.

| fixture | edges | convex | concave | **sign differs** |
| --- | ---: | ---: | ---: | ---: |
| box 20³ | 12 | 12 | 0 | 0 |
| **box 200 × 0.05 × 20 (thin wall)** | 12 | 4 | 8 | **8** |
| cylinder r6 h10 (seam) | 3 | 2 | 0 | 0 |
| cylinder r0.02 h40 (thin pin) | 3 | 2 | 0 | 0 |
| L-prism (a real concave edge) | 18 | 17 | 1 | 0 |
| **slotted plate, 0.04 mm slot** | 24 | 24 | 0 | **2** |
| 10-point star (alternating convex/concave) | 60 | 50 | 10 | 0 |
| 24-gon prism | 72 | 72 | 0 | 0 |
| ring(60) / ring(480) / ring(1920) prisms | 180 / 1440 / 5760 | all | 0 | 0 |
| filleted box (tangent edges) | 15 | 13 | 0 | 0 |
| box minus through-hole | 15 | 14 | 0 | 0 |
| box with an INTERNAL void | 24 | 12 | 12 | 0 |
| revolved ring | 6 | 4 | 0 | 0 |

**7 644 edges over 15 fixtures. 10 sign differences, in 2 fixtures.**

**It is not bit-identical, and §1.4 forbids papering over that with a
tolerance.** So: which one is right?

### 5.1 On both divergent fixtures, the SHIPPED path is the wrong one

**This needs no appeal to the replacement.** A box is a convex solid; every one
of its twelve edges is an exterior corner, so the only correct answer is +1
twelve times. Vary nothing but the wall thickness:

| box | ‖diag‖ | step = ‖diag‖/1000 | thickness / step | **classifier wrong** | wedge wrong |
| --- | ---: | ---: | ---: | ---: | ---: |
| 200 × 0.3 × 20 | 201.00 | 0.2010 | 1.493 | 0 / 12 | 0 / 12 |
| 200 × 0.2 × 20 | 201.00 | 0.2010 | 0.995 | 0 / 12 | 0 / 12 |
| 200 × 0.15 × 20 | 201.00 | 0.2010 | **0.746** | 0 / 12 | 0 / 12 |
| 200 × 0.1 × 20 | 201.00 | 0.2010 | **0.498** | **8 / 12** | 0 / 12 |
| 200 × 0.05 × 20 | 201.00 | 0.2010 | 0.249 | **8 / 12** | 0 / 12 |
| 60 × 0.06 × 40 | 72.11 | 0.0721 | **0.832** | 0 / 12 | 0 / 12 |
| 60 × 0.04 × 40 | 72.11 | 0.0721 | **0.555** | **8 / 12** | 0 / 12 |

The shipped path reports **eight of a box's twelve edges as concave**. It is
not a tie between two opinions; a convex solid has no interior corners.

**The threshold is exact and it is arithmetic, not a fitted curve.** The query
point leaves the edge along the bisector of the two into-face directions, which
for a 90° corner stands at 45° to each face, so its perpendicular clearance
from the opposite wall is `step/√2`. Both sweeps cross between 0.746 and 0.555
— i.e. at **0.707**. The rule:

> The shipped convexity sign is wrong for any edge whose material is thinner
> than **‖bounding-box diagonal‖ / 1414** across the wedge bisector.

For a 100 mm part that is 0.07 mm; for a 1 m weldment, 0.7 mm. Ribs, seal
grooves and sheet-metal walls live there. `step` is a *shape-wide* constant
(`occt_capi.cpp:2236-2245`) and is not scaled to local feature size, so the
larger the part, the coarser the probe — which is backwards.

The slotted plate is the same defect wearing the other sign: a 0.04 mm slot in
a 60 × 40 × 6 plate (step 0.0724) has the probe step **across** the slot into
the material beyond, so both reentrant corners come back +1 and the fixture
reports 24 convex edges and no concave ones, on a shape that visibly has two.

### 5.2 What this makes the change

Not an optimisation that happens to be equivalent. **An optimisation whose
divergences are all repairs**, in a regime the shipped code was never right in.
That is still a behaviour change, `OPTIMIZATION_PLAN_2.md` §1.2 does not let S6
make one on its own authority, and §7 routes it rather than assuming it.

Two things it is *not*, so the ruling is made on what is actually true:

- **Not a fix to anything that is persisted.** §2.4: field 11 reaches exactly
  one caller, `selectAllEdges`, and is not written to any fingerprint. The bug
  is "All Rounds mis-selects the edges of a thin wall", visible on screen, not
  a part that reattaches its blends wrongly on load.
- **Not proven identical in general.** 7 644 edges is 15 shapes, not a proof.
  §8 lists the classes where the two must still be expected to differ.

---

## Prediction P1 — the exponent goes to one, and Lane C can refute it

```
Target        : Lane C's allEdgesBulk ladder, 60/120/240/480 profile points
                (180/360/720/1440 edges), the op it already reports.
Baseline      : Lane C linux/x86_64, shim v21, run 32281399947 at 2921d3f:
                  22.395 / 79.994 / 297.153 / 1167.509 ms
                  k = 1.901 [1.858, 1.943]
                Lane C macos/arm64, ci-logs-bench run 3:
                  19.85 / 69.47 / 316.88 / 1108.44 ms
                  k = 1.960 [1.854, 2.066]
Mechanism     : BRepClass3d_SClassifier::Perform is Theta(shape) per call and
                is called once per edge -- it rebuilds the whole solid's
                edge->face ancestor map (SClassifier.cxx:227) and intersects
                the ray against every face because RejectShell/RejectFace
                return Standard_False unconditionally (SolidExplorer.cxx:1025,
                :1075). Measured at 98.6 % of the enumeration (§4.3.1).
                Behind it, into_face_dir's per-face scan is 0.97 % of the
                whole but 70.7 % of what is left once the classifier goes.
Change        : (a) the convexity sign from the local wedge test u1 . n2,
                    which is O(1) and uses operands the code already has;
                (b) restore 1c4735f's face-edge orientation index, so the
                    orientation lookup is Theta(E) once instead of Theta(E*F).
                Both, or neither -- (b) alone measures as a wash (§4.3.5).
Derivation    : measured directly on the same ladder, same fixture, same
                fitting code (backend/bench/bench_stats.cpp), one process,
                7 repetitions -- not modelled:
                  180 edges   26.898 -> 0.905 ms
                  360 edges   86.893 -> 1.740 ms
                  720 edges  316.018 -> 3.557 ms
                 1440 edges 1375.262 -> 7.115 ms
                  k 1.889 [1.755, 2.023] -> 0.996 [0.971, 1.020], R2 0.9997
                Carried to Lane C's published linux rungs by the per-rung
                ratio measured here (0.0351 / 0.0204 / 0.0110 / 0.0052):
                  0.79 / 1.63 / 3.25 / 6.10 ms
Predicted     : k = 1.00, interval [0.95, 1.10]
                times as above, interval [0.7x, 1.4x] to carry the ISA
                difference (Lane C's two platforms differ by 0.06 in k on the
                unchanged path, and arm64 ran 1.15-1.19x faster per rung)
                a further 164x at the 1440 rung against shim v21, and 5150x
                against the per-edge loop v20 shipped
Falsifiable by: the fitted exponent of Lane C's allEdgesBulk. k > 1.10 refutes
                this outright. So does an allocation counter that keeps a term
                proportional to n: predicted alloc/edge = 33.7 CONSTANT at
                every rung (measured here at 33.7 to one decimal over an 8x
                range), total at 1440 edges 8 885 798 -> 48 497. That is the
                criterion S2's P5 wrote and then withdrew as unusable; against
                the classifier it works, because MapShapesAndAncestors
                allocates and TopExp_Explorer does not.
Risk          : §5 -- the change is not bit-identical. 10 edges of 7 644
                differ, all of them thin-feature cases where the shipped path
                is demonstrably wrong. That is a behaviour change and §7
                routes it to the integrator rather than assuming it.
                Second risk: the floor is 5.834 ms at 1440 edges, so 7.115 ms
                is already within 22 % of "do not compute convexity at all".
                There is no third change hiding behind this one.
```

## Prediction P2 — the single-edge control MOVES this time, and by how much

Round one's P3 required the single-edge path not to change cost, because round
one hoisted whole-shape work and the single-edge path had none to hoist. **This
change is in the per-edge body, so the control moves — deliberately.** Saying
so in advance is the point; a control that moves unannounced is a regression.

```
Target        : Lane C's edgeInfo1, and PERFORMANCE_PROFILE.md §6.5 evidence 2
                (kernel.query.edgeInfoScale)
Baseline      : Lane C edgeInfo1, shim v21: k = 1.077 [1.001, 1.153]
                device kernel.query.edgeInfoScale: k = 0.985 [0.942, 1.029],
                  24:0.6252  60:1.5080  120:3.0383  240:6.0729 ms
Mechanism     : the single-edge path builds its own context per call, so
                MapShapes + MapShapesAndAncestors + the bounding box stay
                Theta(shape) per call and the exponent is theirs. What leaves
                is the classifier's construction AND its Perform.
Change        : same wedge test; the single-edge path keeps the SCAN (building
                an E-sized index to answer one question is waste, and 1c4735f
                already draws that line).
Derivation    : measured here, one query against a growing shape, 20 reps:
                  72 edges  0.8920 -> 0.0441 ms   (20.2x)
                 180 edges  2.1543 -> 0.1319 ms   (16.3x)
                 360 edges  4.0408 -> 0.1983 ms   (20.4x)
                 720 edges  8.1937 -> 0.4049 ms   (20.2x)
                  k 0.958 [0.931, 0.984] -> 0.935 [0.775, 1.095]
Predicted     : cost / 16 to / 21; EXPONENT UNCHANGED, intervals overlapping.
                A single edgeInfo stays Theta(shape) and §6.5 evidence 2 stays
                true as a statement about scaling.
Falsifiable by: an edgeInfo1 exponent whose interval clears its v21 one, or a
                ratio outside [12x, 26x].
Risk          : this is the strongest single check that the change did what it
                says. The classifier was ~95 % of a single-edge query too, so
                if edgeInfo1 does NOT fall by an order of magnitude, the
                convexity branch is not being reached and the whole result is
                an artefact of a guard, not of the change.
```

## Prediction P3 — the gate will report these, and none of them is a regression

```
Target        : ci/perf_gate.py against the round-one baseline
Predicted     : - large duration drops on every allEdges span (P1)
                - stress.allEdges.maxSize 480 -> 1920 and .edges 1440 -> 5760,
                  i.e. the ladder reaches its control's ceiling. §6.5's
                  evidence-4 pairing predicts allEdges and buildOnly now stop
                  at the same rung, which is the cleanest available statement
                  of "the exponents match": buildOnly is k = 1.063 and this
                  predicts k = 1.00.
                - kernel.query.edgeInfoScale down ~20x, exponent unmoved (P2)
                - app.blendPattern.edgeQuery down by the same factor, since it
                  is N enumerations (CROSS-SESSION, S5)
                - NO counter changes. This session adds and removes no
                  ffiCount call; occt_engine.dart's counters are untouched.
Falsifiable by: any counter change at all, or a gauge moving that is not in
                this list.
```

---

## 6. Results

### 6.1 What was changed

**Shim v22**, `backend/occt/shim/occt_capi.{h,cpp}`:

| | |
| --- | --- |
| `convexity_sign()` | field 11 from the local wedge test `u1 · n2`. The guards around it — `faceCount == 2`, `dihedral > 1e-3`, both `into_face_dir` succeeding, `\|u1+u2\| > 1e-9` — are **unchanged**, so exactly the same set of edges receives a nonzero sign as before. `m.Normalize()` moved inside the reference branch, since the shipping path has no use for it. |
| the orientation index | `1c4735f` restored — this commit reverts `c5f7e21`. `perf/findings/S2-shim.md` is **not** reverted with it: that file is S2's record of what S2 did and is not mine to rewrite. |
| `occt_shape_edges_info_ref()` | **new, test-only.** The pre-v22 convexity path, so `[36]` can compare old against new in one run. Documented in the header as not-for-application-use, with the reason. Not bound in `occt_engine.dart`. |
| `occt_shim_version()` | 21 → **22**, with the version note saying what a caller learns by testing for it: whether the binary's thin-wall convexity can be trusted. |

`backend/occt/tests/smoke_occt.c`: scenario **`[36]`** (§6.3).
`frontend/lib/ffi/occt_engine.dart`: **documentation only** — 16 added lines,
every one of them a `///` comment. No Dart behaviour, no counters, no bindings.

Files touched outside this session's ownership: **none.** `perf/baseline.json`,
`PERFORMANCE_PROFILE.md`, `frontend/lib/perf*.dart`, `backend/bench/**`,
`solver.dart`, `part_model.dart` — all untouched.

### 6.2 Verified on real OCCT, here, on the pinned kernel

Not "syntax-checked in isolation", which is what `1c4735f` had and why it was
reverted. OCCT V7_9_3 `a016080b` built from the submodule with
`kernel-bench.yml`'s flags verbatim; shim, smoke test and Lane C all compiled
against it and run.

```
[35] box / cylinder / L-prism / filleted / 24-gon: 0 of 12, 3, 18, 15, 72 records differ
[36] box 20 / cylinder / L-prism / star / 24-gon / through-hole / internal void:
       fields 0..10 differ on 0, convexity differs on 0
[36] box 200 x 0.1 x 20 (THIN): fields 0..10 differ on 0, convexity differs on 8
       reference got 8 of 12 box edges wrong, shipping path 0
[36] box 60 x 0.04 x 40 (THIN): fields 0..10 differ on 0, convexity differs on 8
       reference got 8 of 12 box edges wrong, shipping path 0
[36] coverage: convex 203, concave 23, curve-kind mask 0x6, thin fixtures 2 with 16 repaired signs
OCCT SMOKE: PASS
```

`[35]` still passes, which matters more than it looks: it pins the bulk path
against the single-edge path bitwise, so it is the guard that the two entry
points did not drift apart when both changed.

### 6.3 `[36]` — how a differential test says an honest thing about a change that is not identical

The rule (§1.4) is "compare old against new on the same machine, in the same
run", and "never convert a failing equivalence pin to a tolerance to get a
green build". The two divergent fixtures make that a real design problem, and
a tolerance is exactly what must not be reached for. `[36]` splits the claim
instead:

1. **Fields 0–10, every fixture, bitwise.** Both paths run the same code for
   them, so any difference is a defect however small. Nine fixtures.
2. **Field 11, every fixture with no feature below `‖diag‖/1414`, bitwise.**
   Seven fixtures, 204 edges, including a 10-point star whose sign has to
   alternate correctly ten times around one loop and a solid with an internal
   void whose twelve cavity edges are genuinely concave.
3. **The thin fixtures assert GROUND TRUTH, not the disagreement.** A box is
   convex; the shipping path must report all twelve edges convex at every
   thickness. The reference's error count is *printed*, not asserted — so if
   some future OCCT fixes `Perform`, this test keeps passing and simply stops
   printing repairs.
4. **The thin fixtures must still reach their regime.** `check(sign_diff > 0)`
   with a message saying to re-derive the threshold. A fixture that quietly
   stops exercising the case it was built for is worse than no fixture, and
   this one says so out loud.
5. **Coverage**, as `[35]` does: convex, concave, straight and circular edges
   all actually seen, so an all-zeros implementation cannot pass by agreeing
   with itself.

### 6.4 Definition of done, item by item

| plan §6 | |
| --- | --- |
| 1. `flutter analyze` zero issues | **NOT RUN — no Flutter SDK in this container.** The Dart diff is 16 lines and all of them are `///` comments; `git diff frontend/` contains no added non-comment line. Stated rather than assumed. |
| 2. `flutter test` green | **NOT RUN**, same reason. No Dart behaviour changed. The three Dart tests that touch this record (`bulk_edge_info_test.dart`, `m136_edge_feature_test.dart`) construct `OcctEdgeInfo` from literals and never call the shim. |
| 3. `python3 -m unittest discover -s ci` | **45 passing** |
| 4. behaviour pinned by a differential test | **yes**, `[36]`, §6.3 — and it is pinned as *not* identical, with the divergence named |
| 5. predictions with arithmetic, before the change | **yes**, P1–P3 above, committed in `7c58e0f` before `a11b97a` touched the shim |
| 6. merged cleanly into `claude/perf-opt2` | **NO, and cannot be** — §0.1: no `perf-capture-round1` tag, so no integration branch exists to merge into |
| 7. findings say what was done, predicted, unsure, not done | this file; §8 is the unsure and the not-done |

---

## 7. Adjudication — Lane C's own binary, same machine, before and after

Not my harness this time: `backend/bench/occt_bench` itself, built from this
branch and from `7c58e0f` (the commit before the shim changed), run
back to back on the same machine with the same flags. Round one never had a
same-machine before/after on the gating op; this is one.

### 7.1 `allEdgesBulk` — P1

| edges | v21 | **v22** | factor |
| ---: | ---: | ---: | ---: |
| 180 | 29.893 ± 0.507 | **0.9716 ± 0.0107** | 30.8× |
| 360 | 114.796 ± 3.094 | **2.2745 ± 0.0263** | 50.5× |
| 720 | 426.846 ± 11.145 | **4.5963 ± 0.1939** | 92.9× |
| 1440 | 1714.885 ± 22.280 | **9.2273 ± 0.1531** | **185.8×** |
| **k** | **1.9421 [1.9123, 1.9719]** | **1.0757 [1.0015, 1.1499]** | |
| R² | 0.99988 | 0.99753 | |

**P1 is UPHELD.** Predicted k = 1.00, interval [0.95, 1.10]; measured
**1.0757**, inside it. The two intervals are disjoint with room to spare —
[1.9123, 1.9719] against [1.0015, 1.1499] — which is the comparison round one
could not make: S1 had to withdraw "the exponent dropped by 0.145" because on
arm64 the intervals overlapped. Here they do not overlap on either reading, and
both arms are the same machine, so no cross-platform argument is needed.

The factor **grows with size** — 30.8× → 185.8× — which is the signature of an
exponent change rather than a constant one. Round one's 20.7× was flat at
15.1 → 20.7 across the same rungs, and that flatness was the tell.

**One part of P1 I cannot yet check, and one I got right.** The predicted
*absolute* milliseconds (0.79 / 1.63 / 3.25 / 6.10) were carried onto Lane C's
*published* Linux machine, which is not this one — that comparison waits for a
Lane C run. What can be checked here is the predicted **ratio** per rung, and
it holds tightly:

| edges | predicted v22/v21 | measured | error |
| ---: | ---: | ---: | ---: |
| 180 | 0.0351 | 0.0325 | 8 % |
| 360 | 0.0204 | 0.0198 | 3 % |
| 720 | 0.0110 | 0.0108 | 2 % |
| 1440 | 0.0052 | 0.0054 | 4 % |

### 7.2 `edgeInfo1` — P2, and the control moved exactly as advertised

| edges | v21 | v22 | factor |
| ---: | ---: | ---: | ---: |
| 180 | 2.3929 | 0.12234 | 19.6× |
| 360 | 5.4097 | 0.27190 | 19.9× |
| 720 | 10.6119 | 0.55897 | 19.0× |
| 1440 | 21.5364 | 1.14704 | 18.8× |
| **k** | 1.0482 [0.9885, 1.1079] | 1.0726 [1.0339, 1.1114] | **overlapping** |

**P2 is UPHELD on both halves.** Cost / 18.8 to / 19.9, predicted [12×, 26×].
Exponent unchanged, intervals overlapping — a single `edgeInfo` is still
Θ(shape), because the single-edge path still rebuilds its whole-shape context
per call. §6.5 evidence 2 stays true as a statement about scaling; only its
constant moved.

### 7.3 The per-edge enumeration is still quadratic, and that is correct

| edges | v21 | v22 | factor |
| ---: | ---: | ---: | ---: |
| 180 | 478.58 | 22.451 | 21.3× |
| 360 | 2097.41 | 99.495 | 21.1× |
| 720 | 8682.45 | 396.867 | 21.9× |
| 1440 | 34887.17 | 1677.89 | 20.8× |
| **k** | 2.0613 [2.0221, 2.1005] | **2.0667 [2.0278, 2.1056]** | **unmoved** |

A flat ~21× with the exponent untouched — the same shape of result round one
got from hoisting, now on the other path, and for the same reason: what remains
quadratic there is `MapShapes` + `MapShapesAndAncestors` + the bounding box,
rebuilt per call. **Calling `occt_shape_edge_info` in a loop is still the wrong
thing to do**, and its doc comment still says so. `allEdges()` in Dart does not.

### 7.4 The control that must NOT move, did not

`buildOnly` builds and tessellates and touches none of this code:

| edges | v21 | v22 |
| ---: | ---: | ---: |
| 180 | 18.429 | 16.996 |
| 360 | 32.871 | 34.210 |
| 720 | 74.936 | 73.988 |
| 1440 | 131.126 | 136.754 |
| k | 0.9682 [0.8658, 1.0705] | 1.0138 [0.9542, 1.0733] |

±4 % with no trend and overlapping intervals. Machine noise, as required.

### 7.5 The harness verdict flipped — and the honest reading is "resolution", not "physics"

| | v21 | v22 |
| --- | --- | --- |
| `edgeInfo1` vs device 0.990 [0.970, 1.010] | [0.9885, 1.1079] → **AGREES** | [1.0339, 1.1114] → **DISAGREES** |
| `allEdges` vs device 2.012 [1.910, 2.113] | AGREES | AGREES |
| `buildOnly` vs device 1.063 [0.959, 1.167] | AGREES | AGREES |
| **harness verdict** | **VALIDATED** | **NOT VALIDATED** |

It would be easy to report this as "no change, the interval merely narrowed",
and that is not quite true either. Both things moved: the point estimate went
1.0482 → 1.0726 (+0.024, well inside either interval, i.e. not significant),
**and** the interval narrowed from 0.119 wide to 0.078. Neither alone flips the
verdict; together they clear the device's upper bound of 1.010 by 0.024.

The narrowing is a direct consequence of the change: `edgeInfo1` is now fast
enough that the bench takes inner repetitions (×32 at the small rung instead of
×1), and its CV falls from 5.5 % to 1.3 %. **A disagreement that was always
there is now resolvable.** That is the instrument getting sharper, not the
kernel getting worse — but it is a real disagreement and it should not be
waved away: `edgeInfo1` on a desktop and `kernel.query.edgeInfoScale` on an
iPad now measurably differ in exponent by ~0.08.

**CI already handles this correctly and needs nothing from anyone.**
`kernel-bench.yml` keys the gate on `CALIBRATION.txt`'s content hash of the
shim; the shim's hash is now `93fb7e7`, the recorded one is `8c46e48`, so
`--validate` is dropped and the comparison becomes informational — which is
exactly the case that file was written for ("a dropped `allEdges` exponent is
the intended outcome of Session 2's work, not a broken harness"). Both runs
printed **`LANE C: PASS`**.

**`CALIBRATION.txt` must NOT be re-recorded to make this go away**, and its own
text says so: "Never update it to silence a disagreement." It should be
re-recorded only after the next device capture re-establishes what the device's
`edgeInfoScale` exponent is against a v22 kernel. `backend/bench/**` is not
mine to touch in any case. **`Needs:` integrator**, as a note rather than a
task.

---

## 8. What I am unsure of, and what I deliberately did not do

### 8.1 The change is not proven identical, and here is where it must still differ

7 644 edges over 15 fixtures is evidence, not a proof. The classes where the
two paths must be expected to disagree, derived rather than observed:

| class | why | seen? |
| --- | --- | --- |
| a feature thinner than `‖diag‖/1414` | §5.1 — the probe crosses it | **yes**, 10 edges, and the classifier is wrong on all of them |
| a query point inside the classifier's ON-tolerance of an edge or vertex | `Perform` returns `TopAbs_ON`, which the shim maps to −1; the wedge has no such state | not seen; needs a shape with tolerances near `‖diag‖/1000` |
| an exactly-180° "knife" edge | `u1 · n2` is exactly 0 and v22 returns −1; the old path stepped along a direction tangent to both faces and got whatever the classifier said | not seen; both answers are arbitrary there |
| a self-intersecting or invalid solid | the classifier answers about the point set; the wedge answers about the declared normals | not tested — I could not build one through the C ABI |

The first row is the reason to make the change. The other three are why it is
**routed and not merged** (§9).

### 8.2 Things I checked and could not fault, so am not claiming as risks

- **Global shell inversion.** I expected this to be a divergence class and
  worked through it before testing: reversing every face leaves `u1` and `u2`
  unchanged (`(−n) × (−T) = n × T`), so the classifier's query point is
  unchanged too, while `u1 · n2` flips. That predicts disagreement. I could not
  produce an inverted solid through the shim's C ABI to confirm it, so it is
  **unresolved rather than absent** — I am flagging the reasoning, not a
  measurement. If the integrator wants it closed, it needs a fixture built
  against OCCT directly.
- **Seam edges.** A cylinder's seam has both `fl.First()` and `fl.Last()` on
  the same face, so `n1 == n2`, the dihedral is 0, and the `> 1e-3` guard
  excludes it before either path is reached. `[36]`'s cylinder confirms: one
  edge with sign 0, identical on both paths.
- **The orientation index against the scan.** `[35]` pins them bitwise (the
  bulk path indexes, the single-edge path scans), five fixtures, 120 edges.

### 8.3 The sqrt I chose to keep paying

The shipping path still computes `m = u1 + u2` and `m.Magnitude()` purely to
evaluate the `> 1e-9` guard, and then does not use `m`. One square root per
edge, bought deliberately: it keeps the *set* of edges that receive a sign
exactly what it was. `SquareMagnitude() > 1e-18` would save it and would change
which edges fall through in the last bits. Fidelity beat the sqrt; at 33.7
allocations and ~6 µs per edge it is not measurable anyway.

### 8.4 Not done, on purpose

- **The single-edge path keeps the scan**, as `1c4735f` decided. Building an
  E-sized index to answer one question is waste, and §7.2 shows the exponent
  there is set by the whole-shape rebuilds, not by the scan.
- **`step` is left as `‖diag‖/1000`.** Now that the shipping path does not use
  it, it survives only inside the test-only reference. Rescaling it to local
  feature size would "fix" the reference — and the reference's job is to
  reproduce pre-v22 behaviour exactly, so fixing it would destroy the test.
- **The fillet guard (`S2-shim.md` §7.5, ≥ 45.2 % of a one-edge blend)** is
  untouched. It is behaviour — a blend that would hand back a self-intersecting
  solid fails cleanly because of it — and it is a separate question from this
  one.
- **`BRepCheck_Analyzer`, `occt_shape_volume`, `fuse`/`cut`** — Lane C fits
  `fuse` at k = 1.336 and `cut` at 1.353 on this ladder, both above linear and
  neither owned by anyone. Recorded, not chased.
- **I did not touch `backend/bench/**`**, so Lane C gained no new op. The
  decomposition in §4 was done in a scratch harness outside the repo,
  linking the repo's `bench_stats.cpp` read-only, and none of it is committed.

### 8.5 What would refute this session

- A Lane C run on the published Linux or arm64 runner fitting `allEdgesBulk`
  above **k = 1.10**.
- An allocation counter still carrying a term proportional to n.
- Any fixture where fields 0–10 differ between the two paths.
- A fixture with **no** feature below `‖diag‖/1414` where the convexity signs
  differ. That would mean the local test is wrong for a reason I have not
  found, and `[36]` fails loudly on it rather than tolerating it.

---

## 9. `**Needs:** integrator`

**This is a behaviour change and `OPTIMIZATION_PLAN_2.md` §1.2 does not let S6
merge one on its own authority.** It is built, measured, tested and pushed to
`claude/edge-path-quadratic-exponent-990pqs`; whether it lands is not mine.

Three things to decide, and they are separable:

1. **The change itself.** 185.8× at 1440 edges and k 1.94 → 1.08, at the cost
   of 10 sign flips in 7 644 edges — all of them on shapes where the shipped
   path is demonstrably wrong (a box reported as having concave edges). §2.4
   is the blast radius: field 11 has one consumer, `selectAllEdges`, and is not
   in any persisted fingerprint. If the answer is no, **the orientation index
   must come out with it** (§4.3.5): alone it is a wash and S2 was right to
   revert it.

2. **The sequencing.** §0.1 — `perf-capture-round1` does not exist and neither
   does `claude/perf-opt2`. Nothing of mine has reached `claude/perf-opt`, so
   round one's attribution is intact, but this branch cannot be merged anywhere
   correct until the capture is taken and the tag exists.

3. **`CALIBRATION.txt`.** §7.5 — do not re-record it to clear the
   `edgeInfo1` disagreement. CI already degrades the gate to informational on
   its own. The right moment to re-record is after a device capture against a
   v22 kernel.

And one thing that is not a decision, just a fact worth carrying into
`PERFORMANCE_PROFILE.md` at integration: **§6.5's "principal finding" is
closed.** The extrapolation there — 56.4 s [44.9, 70.8] for the ≈ 3 400-edge
part that died in the field — was a quadratic's. Against k = 1.076 and this
ladder's constant the same enumeration is on the order of **25 ms**. The number
that has been at the top of that section since the beginning no longer
describes the code.
