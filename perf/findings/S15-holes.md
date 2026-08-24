# S15 — a holed profile should build too: the assembly, and the guard it needs

**Session:** S15 (round three, the second sweep session).
**Branch:** `claude/s15-holed-profile-sweep-cus40t`, cut from
`claude/perf-opt2` at `1b0675c`.
**Owns:** `backend/occt/shim/**`, `backend/bench/**`, `backend/occt/tests/**`,
this file.
**Governing rules:** `OPTIMIZATION_PLAN_2.md`, `perf/findings/README.md`,
`OPTIMIZATION_PLAN.md` §2 for the prediction form.
**Reads as given, does not re-derive:** `perf/findings/S14-sweep.md` §10 and
§12.

---

## 0. The gap this session exists for

S14 fixed the sweep for profiles **without** holes. A 1200-segment ring on a
16-span sampled arc went from failing after 742 249 ms to building valid in
3 559.2 ms, and the fitted exponent from ~3 to 1.150 (S14 §5.2).

A profile **with** a hole gets none of that, and the reason is one line of
`occt_sweep_profile_ex`:

```cpp
    const int effective_mode =
        (path_mode == OCCT_SWEEP_PATH_AUTO && nloops > 1)
            ? OCCT_SWEEP_PATH_POLY
            : path_mode;
```

A holed profile is forced back onto the v23 polyline spine, because
`finish_pipe` removes each hole with a `BRepAlgoAPI_Cut` and that boolean costs
21 653.6 ms between two smooth-spine solids against 66.0 ms for the two sweeps
that feed it (S14 §4.1). So the holed path still takes the mitered route and
still fails at exactly the size the owner's goal names.

**The bar for this session:** a 1200-segment profile with a hole, swept along an
arc, must build and must be valid.

### 0.1 What S14 settled, and is not re-tested here

1. **`MakePipeShell` cannot take a multi-wire section on OCCT 7.9.3.** Settled
   from source: `BRepFill_Section`'s constructor accepts a WIRE or a VERTEX and
   throws `"BRepFill_Section: bad shape type of section"` for anything else
   (S14 §12.1). Sweeping the annulus as one section is not available.
2. **The alternative — assemble instead of subtract — is prototyped and
   measured at 24 segments.** Two lateral shells plus two planar end caps
   whose outer boundary is the outer sweep's end section and whose inner
   boundary is the hole's, sewn and made solid. Same volume to ten significant
   figures, same face count, both valid, 5 730× faster on the smooth spine
   (S14 §12.2).
3. **It is NOT verified at 1200 segments.** S14 killed its prototype after
   25 minutes and labelled its own explanation — that the process was stuck in
   `vol()` / `BRepCheck_Analyzer` rather than in construction — an inference
   from where a timer sat, not a measurement (S14 §12.2, §14.3 item 3).

Item 3 is the first thing this session settles, because if **verification**
costs 25 minutes then the right design is a different one, not merely a slower
schedule.

---

## 1. Pre-registration, round 1 — where the 25 minutes goes

Nothing in the shipped path is changed by anything in this section. The
instrument is a separate host-only executable (`backend/bench/hole_probe.cpp`),
built from the same `occt_capi` translation unit the app links, and it times
the assembly's stages **separately** so that the question S14 could only infer
an answer to can be answered by measurement.

The stages it separates, on a 1200-segment r = 6 ring with an r = 3 hole over
the 16-span sampled arc, SMOOTH spine:

| stage | what it covers |
| --- | --- |
| `sweep` | the two `BRepOffsetAPI_MakePipeShell::Build()` calls |
| `caps` | the two planar cap faces, outer wire + inner wire |
| `sew` | `BRepBuilderAPI_Sewing` over the four pieces, and the solid |
| `unify` | `ShapeUpgrade_UnifySameDomain`, which `finish_pipe` already runs |
| `volume` | `BRepGProp::VolumeProperties` |
| `valid` | `BRepCheck_Analyzer::IsValid` |

`sweep + caps + sew` is CONSTRUCTION. `volume + valid` is VERIFICATION and is
**not in the shipped path at all** — `finish_pipe` never calls either. `unify`
is shipped and is counted with construction.

```
## Prediction P1 — construction at 1200 segments is seconds, not minutes
Target        : the assembly of a 1200-segment r=6 ring with an r=3 hole over
                the 16-span sampled arc, SMOOTH spine; stages sweep+caps+sew
                +unify only.
Baseline      : none exists — S14's prototype never reported one.
Predicted     : under 30 000 ms.
Derivation    : the finished solid has 1200 + 1200 + 2 = 2402 faces against
                the 24-segment prototype's 50, a factor of 48.0.
                - the two sweeps cost 30.1 ms at 24 segments (S14 §12.2) and
                  the sweep's fitted exponent in SEGMENTS is k = 1.150
                  (S14 §5.2), so 30.1 x 50^1.150 = 30.1 x 90.0 = 2 709 ms.
                  Cross-check: [37d] builds ONE unholed 1200-segment sweep,
                  and unifies, measures and validates it, in 3 559.2 ms total,
                  so ~1.35 s for one sweep is consistent.
                - caps+sew cost 3.7 ms at 24 segments. Sewing uses a
                  BRepBuilderAPI_CellFilter and should be near-linear in faces:
                  3.7 x 48 = 178 ms. Allowing it to be QUADRATIC instead gives
                  3.7 x 48^2 = 8 525 ms.
                - unify is shipped today and [37d] pays it at 1202 faces
                  inside its 3 559.2 ms; at 2402 faces, linearly, ~2x that
                  share.
                Ceiling: 2 709 + 8 525 + a few seconds of unify = ~15 s.
                Registered at 30 000 ms, i.e. double the ceiling.
Falsifiable by: construction above 30 000 ms. That would mean the assembly
                itself does not scale, the 24-segment table is misleading, and
                S14's inference is wrong in the direction that kills the
                design rather than merely delays it.

## Prediction P2 — verification is what cost 25 minutes, and one call does it
Target        : the same shape; stage `valid` alone, against the same stage on
                the UNHOLED 1200-segment sweep built in the same run.
Predicted     : the holed solid's BRepCheck_Analyzer costs at least 20x the
                unholed solid's, and is the single largest stage.
Mechanism     : BRepCheck_Face::IntersectWires
                (backend/occt/upstream/src/BRepCheck/BRepCheck_Face.cxx:240)
                runs its wire-pair loop as `while (Index < Nbwire)`. An
                unholed sweep's end cap has ONE wire, so that body never
                executes and the check is free. A holed sweep's cap has TWO,
                so each cap runs Intersect(outer, inner) — a full
                edge x edge double loop.
Derivation    : 1200 x 1200 = 1 440 000 edge pairs per cap, 2 880 000 over the
                two caps. Each iteration calls
                BRep_Tool::CurveOnSurface(edg2, F, first2, last2) BEFORE the
                Bnd_Box2d rejection, and the cap is planar with no stored
                pcurve on its inner wire, so every one of those calls goes
                through BRep_Tool::CurveOnPlane and CONSTRUCTS a projected
                Geom2d curve. At 1 us each that is 2.9 s; at 100 us each it is
                288 s; at 500 us each it is 1 440 s, which is the 25 minutes
                S14 saw. The unholed control pays ZERO of this.
                Note the two rings are radially separated by 3 units and every
                edge box is a sub-unit segment, so essentially NO pair reaches
                Geom2dInt_GInter: the cost is the per-pair setup, 2.88e6 times.
Falsifiable by: a ratio under 20x, or any other single stage exceeding
                `valid`. Either moves the 25 minutes somewhere I have not
                looked and makes P3 the interesting result instead.

## Prediction P3 — the split, stated as a share
Target        : the same measurement.
Predicted     : verification (volume + valid) is more than 50 % of the whole
                holed 1200-segment measurement, and construction is less than
                10 % of it.
Derivation    : P1 caps construction at ~15 s expected; P2 puts `valid` alone
                in the hundreds of seconds. If both hold, construction's share
                is 15 / (15 + several hundred) < 10 %.
Falsifiable by: construction above 10 %. This is the prediction that decides
                whether the design is right, as distinct from P1/P2 which
                decide where the time goes: if CONSTRUCTION is the expensive
                half, the assembly route is not obviously better than the
                boolean at scale and this session should say so and stop.

## Prediction P4 — the shipped v26 route, at the same size, does not finish
Target        : occt_sweep_profile_ex on the same 1200-segment holed profile
                and the same 16-span arc, exactly as shipped (AUTO), capped at
                900 000 ms.
Predicted     : no solid — either a null return or the cap expiring.
Derivation    : nloops > 1 forces OCCT_SWEEP_PATH_POLY, so the outer wire is
                swept along v23's mitered polyline spine, and S14 measured
                that exact configuration WITHOUT a hole as FAILED after
                742 249 ms (S14 §5.2). Adding a hole adds a second sweep of
                the same kind and a boolean between them; it cannot become
                cheaper.
Falsifiable by: a solid coming back. That would mean the holed path is not
                actually broken at 1200 and the premise of this session is
                wrong.

## Prediction P0 — the instrument reproduces S14's 24-segment table
Target        : the same probe at 24 segments, 16 spans.
Predicted     : polyline spine 5 031.442237 and 770 faces; smooth spine
                5 031.420889 and 50 faces; both valid; the assembly's own
                volume equal to the boolean's to 10 significant figures.
Derivation    : these are S14 §12.2's measured numbers. This arm exists so
                that a disagreement is attributed to my instrument rather
                than to the kernel.
Falsifiable by: any disagreement, which invalidates every number below it.
```

---

## 2. What the instrument measured

Machine: 4-core Linux container, OCCT 7.9.3 built Release/static from the
pinned submodule with the `VENDOR.md` configure line, shim and probe at `-O2`.
**It is about 2.9× slower than the machine S14 measured on** — S14's [37d]
reports the unholed 1200-segment sweep, unified, measured and validated, at
3 559.2 ms, and the same subset of stages here is 10 230 ms. Every absolute
number below carries that factor; every ratio does not.

### 2.1 P0 — the instrument agrees with S14, to the last bit

```
--- 24 seg, r=3 hole, 16 spans, polyline spine
  A boolean :      457.3 ms  vol 5031.442237  faces 770  valid
  B assembly:  CONSTRUCTION 365.0 ms   VERIFICATION 72.1 ms
               vol 5031.442237  faces 770  valid
  A/B volume delta: 0.000e+00 relative
--- 24 seg, r=3 hole, 16 spans, SMOOTH spine
  A boolean :    17698.3 ms  vol 5031.420889  faces 50  valid
  B assembly:  CONSTRUCTION  54.4 ms   VERIFICATION 340.7 ms
               vol 5031.420889  faces 50  valid
  A/B volume delta: 0.000e+00 relative
```

S14 §12.2's volumes and face counts, reproduced: 5 031.442237 / 770 and
5 031.420889 / 50. **P0 HELD**, and it held harder than it was written — the
prediction asked for agreement to ten significant figures and the two routes
returned the *same double*, `0.000e+00` relative. That is worth more than the
speed table: it says the assembly is not merely close to the subtraction, it is
the same solid.

### 2.2 P1–P3 — the staged 1200-segment measurement

```
--- 1200 seg, 16-span arc, SMOOTH spine
  UNHOLED control: sweep  1382.2  caps  102.3  sew 2294.4  unify 121.3
                   | volume  7905.4  valid   821.8
                   CONSTRUCTION  3900.1 ms (30.9 %)
                   VERIFICATION  8727.3 ms (69.1 %)   total 12627.4 ms
                   vol 6785.779141  faces 1202  valid
  HOLED assembly : sweep  2518.6  caps  110.7  sew 5094.6  unify 228.8
                   | volume 16778.5  valid  8817.1
                   CONSTRUCTION  7952.7 ms (23.7 %)
                   VERIFICATION 25595.6 ms (76.3 %)   total 33548.3 ms
                   vol 5089.335272  faces 2402  valid
  valid(holed)/valid(unholed) = 10.7x
```

**A 1200-segment profile with a hole, swept along the sampled arc, BUILDS, and
is VALID.** Construction is 7 952.7 ms on a machine 2.9× slower than S14's, so
call it ~2.8 s there. Its volume is 5 089.335272 against an analytic annulus of
5 089.356844 — `0.5·1200·(36−9)·sin(2π/1200) × 60`, where the 60 is exact
because `hypot(18, 120/π)·(π/2) × (120/π)/hypot(18, 120/π) = 60` — a relative
difference of **4.24e-6**, the same order as [37d]'s 4.1e-6 on the unholed
sweep and for the same reason (the interpolated spine is not the sampled
polyline).

| | prediction | outcome |
| --- | --- | --- |
| **P0** | the probe reproduces S14 §12.2 | **HELD**, bit for bit |
| **P1** | construction under 30 000 ms | **HELD** — 7 952.7 ms, against a derived ceiling of ~15 s |
| **P2** | `valid` is ≥ 20× the unholed one AND the largest stage | **REFUTED, both halves** — 10.7×, and `volume` (16 778.5 ms) is larger than `valid` (8 817.1 ms) |
| **P3** | verification > 50 %, construction < 10 % | **HALF HELD** — verification is 76.3 %, but construction is 23.7 %, not under 10 % |
| **P4** | the shipped route does not finish | see §2.4 |

### 2.3 The 25 minutes does not reproduce, and that is the result

S14 killed its prototype after 25 minutes and inferred, from where its timer
sat, that the process was stuck in `vol()` / `BRepCheck_Analyzer`. **I cannot
reproduce a stall of any kind.** The whole operation — both sweeps, both caps,
the sew, the unify, the volume AND the validity check — is 33.5 s here, which
is ~11.7 s scaled to S14's machine. Construction alone is ~2.8 s there.

So S14's §14.3 item 3 ("I am reasonably confident the stall is in verification
rather than construction") is **wrong in a way that is better than being
right**: it was neither. Something else about that prototype stalled, and I
cannot say what, because the prototype is not in the repository. What I can
say is what my probe does differently and what I would look at first:

* the cap is built with `BRepLib_MakeFace(outerWire, onlyPlane=true)` and the
  inner wire is added to *that* face with `BRep_Builder`. A prototype that
  instead handed BOTH wires to a plane-finding `BRepBuilderAPI_MakeFace` would
  run `BRepLib_FindSurface` over 2 400 edges rather than 1 200, twice;
* sewing runs at `Precision::Confusion()` over faces that **already share their
  boundary edges** — the cap's outer wire IS `mk.FirstShape()`, the lateral
  shell's own free boundary, the same `TShape`. A prototype that rebuilt the
  cap wire from points instead of reusing that handle would make sewing do real
  geometric matching on 2 402 faces rather than recognising identity;
* a Debug OCCT is a different kernel (`OPTIMIZATION_PLAN_2.md` and
  `backend/bench/CMakeLists.txt` §build-type both say so) and would account for
  a large factor on its own.

**I am recording this as an unreproduced measurement, not as a refutation of
S14.** S14 labelled its own claim an inference, which is exactly why this was
worth an hour: the label was doing its job.

### 2.4 P2 refuted: what actually costs, and why it matters more than the ratio

The mechanism P2 named is real and visible — `valid` goes from 821.8 ms to
8 817.1 ms, a 10.7× jump for a solid with only 2× the faces, and
`BRepCheck_Face::IntersectWires` running `Intersect(outer, inner)` over
1 200 × 1 200 edge pairs per cap is the only thing in that check that a second
wire switches on. But the *magnitude* was wrong (10.7×, not ≥ 20×) and, more
importantly, **`volume` is the biggest stage in the whole measurement**, at
16 778.5 ms — and it is 7 905.4 ms for the unholed control too, i.e. it scales
with faces and has nothing to do with holes at all. `BRepGProp::VolumeProperties`
over B-spline faces costs about 7 ms per face on this machine, and neither S14
nor I had any reason to expect that.

**Neither `volume` nor `valid` is in the shipped path.** `finish_pipe` calls
neither. So the honest split for the product is:

| | shipped | this measurement |
| --- | ---: | ---: |
| holed 1200-segment sweep, construction | **7 952.7 ms** | 23.7 % |
| measuring and checking it afterwards | 0 ms | 76.3 % |

**Verification does cost more than construction — 3.2× more — and it is the
test suite that pays it, not the user.** That is the answer to the question the
brief asked to be answered early, and it changes one thing about the design:
the smoke test cannot afford to call `occt_shape_volume` *and*
`occt_shape_valid` on a 2 402-face solid on every CI run without adding ~26 s
to it. It does not change the shim.

---

## 3. Pre-registration, round 2 — the change

The measurement clears the design: the assembly builds a 1200-segment holed
profile in 8.0 s where the shipped route does not build it at all, its volume
is the analytic annulus, and at 24 segments it returns *the same double* the
boolean returns. What is left is the risk S14 named and did not take:
**nothing checks that a hole is inside its outer boundary**, and the boolean
did not need it to be.

### 3.1 The guard, derived

The assembly is only equivalent to the subtraction when each hole is a genuine
hole: strictly inside the outer boundary, and not overlapping or containing
another hole. The subtraction needs none of that — it removes whatever the hole
solid occupies, inside the body or outside it.

The test is done in the profile's own 2D coordinates, on `xyb`, before any wire
exists, and that is a choice with a reason: `placed_profile_wires` maps every
loop through **one** `mat34`, and an affine placement preserves inside and
outside, so containment in the sketch plane is containment in 3D. Testing the
placed wires instead would mean 3D distance queries over B-Rep edges for the
same answer.

For loops that carry bulges the polygon through the vertices is not the loop:
an arc bulges off its chord by its sagitta. So each loop is flattened at **2°
per sub-chord** and the largest sagitta discarded is carried with it; the
separation test then has to beat that error rather than merely find a
positive gap.

Sufficiency, stated as an argument because it is the whole guard:

> If one vertex of hole *H* is inside outer *O*, and no point of *H*'s boundary
> is within `margin` of *O*'s boundary, then *H* is entirely inside *O* — a
> connected closed curve that does not touch *O* cannot have points on both
> sides of it.

with `margin = sag(O) + sag(H) + 1e-7·diag`, where `diag` is the profile's
bounding-box diagonal. The two sagittae make the polygon test conservative
about the true arcs; the relative term keeps it scale-free.

The same test between each pair of holes, plus "neither hole's first vertex is
inside the other", rules out overlap and nesting.

**When the guard says no, `finish_pipe` runs the v26 boolean, unchanged.** That
is the fallback, and it is not a reimplementation of the boolean — it is the
same lines.

### 3.2 What changes for the caller

`occt_shim_version()` goes **26 → 27**. A caller that tests for 27 learns:

1. **A holed profile is assembled, not subtracted**, whenever every hole is
   strictly inside the outer boundary and the holes are pairwise disjoint.
   Same solid, different route, and it succeeds at sizes where the boolean
   did not return at all.
2. **`OCCT_SWEEP_PATH_AUTO` now smooths a holed path.** The `nloops > 1`
   restriction that forced POLY existed because of the boolean's cost, and the
   boolean is gone from that path. **This is a behaviour change**: a holed
   sweep along a sampled arc comes back with a *different face count and a
   slightly different volume* than v26's mitered one — the same change v24
   made for unholed profiles, for the same reason and in the same direction.
3. **A hole that is not strictly inside still works**, by the v26 boolean, and
   AUTO still forces POLY in that case so the fallback does not land on the
   expensive spine.

Version 27 is taken here and nowhere else on this branch; `CROSS-SESSION.md`
carries the claim.

```
## Prediction P5 — the assembly IS the subtraction, at every fixture [37f] has
Target        : smoke [37f] arm 2, 24-segment r=6 ring with an r=3 hole, the
                tilted arc path at 8 spans, orientations 0, 1 and 2, POLY.
Baseline      : v26 satisfies tube == outer - hole to 1e-9 at all three.
Predicted     : still equal to 1e-9 at all three, still valid, and on
                orientation 0 equal to the LAST BIT.
Derivation    : §2.1 ran exactly this comparison at 16 spans on both spines and
                measured a relative delta of 0.000e+00 — the two routes
                returned the same double, not merely the same ten figures.
                Nothing about 8 spans differs in kind.
Falsifiable by: any residual above 1e-9. A residual that appears only at one
                orientation would mean the cap is being built against the
                wrong frame, which is v26's defect wearing a new hat.

## Prediction P6 — AUTO smooths a holed profile now, and it is visible
Target        : smoke [37f] arm 3, which today asserts AUTO == POLY for a holed
                profile, 24 segments, 8 spans.
Baseline      : v26: identical volume and face count, because AUTO was forced
                to POLY.
Predicted     : AUTO and POLY now DIFFER. AUTO gives 2*24 + 2 = 50 faces;
                POLY gives 8 * 24 * 2 + 2 = 386. AUTO's volume is within
                1e-4 relative of the analytic annulus
                (A(6) - A(3)) * 60 = 83.857371 * 60 = 5031.442237.
Derivation    : the smoothed spine is one interpolated edge, so each profile
                segment sweeps ONE face: 24 outer + 24 inner + 2 caps = 50,
                which is what §2.1 measured at 16 spans. The polyline spine
                gives one face per profile segment per span, less what
                UnifySameDomain merges; [37f] prints the number and the test
                asserts only that the two differ and that AUTO is 50.
                The volume tolerance is 1e-4 and not 1e-9 because an
                interpolated spine is not the sampled polyline — [37d]
                measures that gap as 4.1e-6 on the unholed sweep and §2.2
                measures it as 4.24e-6 on the holed one.
Falsifiable by: AUTO == POLY, i.e. the restriction not actually lifted.
Note          : THIS IS THE BEHAVIOUR CHANGE. It is the same one v24 made for
                unholed profiles, and it is routed, not merged.

## Prediction P7 — a hole that pokes out is REFUSED, and the fallback is the
##               boolean itself
Target        : outer 24-gon r=6, hole 24-gon r=2 centred at (5.5, 0), arc
                path, orientation 0.
Predicted     : occt_sweep_profile_ex returns a solid whose volume equals
                occt_cut(sweep(outer), sweep(hole))'s to 1e-9, and is valid.
Derivation    : the hole's farthest vertex is at 5.5 + 2 = 7.5 from the origin
                against an outer circumradius of 6, and its nearest is at 3.5,
                so its boundary crosses the outer's; the flattened polygons
                intersect, the minimum separation is 0, and
                profile_holes_are_separate returns false. finish_pipe then
                takes the v26 branch, which is the same BRepAlgoAPI_Cut
                between the same two swept solids that the comparison operand
                is built from. The two are the same OCCT operation on the same
                operands, so they agree to whatever BRepAlgoAPI_Cut is
                deterministic to, which is exactly.
Falsifiable by: any difference above 1e-9, or an ASSEMBLY that succeeds — the
                second is the dangerous one, because it would mean the guard
                let through the case it exists for and the solid would be
                wrong rather than merely different.
Risk registered: this is S14 §12.3 risk 2 and §14.3 item 4, the reason that
                proposal was handed over rather than committed.

## Prediction P8 — the guard costs nothing worth measuring
Target        : profile_holes_are_separate on the 1200 + 1200 vertex fixture.
Predicted     : under 50 ms, i.e. under 1 % of the 7 952.7 ms construction.
Derivation    : neither loop carries a bulge, so flattening is a copy of
                2 400 points. The separation test is a double loop over
                1 200 x 1 200 = 1 440 000 segment pairs, each of which is
                rejected by an axis-aligned box test (four comparisons) before
                any distance arithmetic; at 5 ns a pair that is 7.2 ms. The
                point-in-polygon test is one crossing count over 1 200 edges.
                Registered at 50 ms, seven times the estimate.
Falsifiable by: above 50 ms. Then the naive double loop needs a uniform grid
                over the outer loop's segments, which turns it linear because
                the query radius is the margin and the margin is tiny — and I
                will say so rather than ship an O(n*m) guard on the hot path.

## Prediction P9 — two holes, and three
Target        : a STRAIGHT path of length 40, 24-gon outer r=6, orientation 0.
                (a) two r=1.5 holes at (+-3, 0);  (b) three r=1.2 holes at
                radius 3, 120 deg apart.
Predicted     : (a) 3 913.343962   (b) 3 935.705928, both to 1e-9 relative,
                both valid, and (a) 5 * 24 + 2 = 122 faces before
                UnifySameDomain merges the straight run.
Derivation    : a regular 24-gon of circumradius R has area
                0.5 * 24 * R^2 * sin(15 deg) = 3.1058285412 * R^2.
                A(6) = 111.809827, A(1.5) = 6.988114, A(1.2) = 4.472393.
                A straight sweep of a constant section is area x length:
                (111.809827 - 2*6.988114) * 40 = 3 913.343962
                (111.809827 - 3*4.472393) * 40 = 3 935.705928
Falsifiable by: any residual above 1e-9. This is S14 §12.3 risk 4 — "k inner
                wires per cap, mechanical, untested" — and the arithmetic is
                what makes it not merely "it did not crash".

## Prediction P10 — a tapered holed sweep, both spines
Target        : straight path length 40, 24-gon r=6 with an r=3 hole, taper
                5 deg; and the same profile on the arc path, both spines.
Predicted     : the straight one is 3 656.315818 to 1e-9 relative and valid;
                the arc ones equal their own outer-minus-hole to 1e-9.
Derivation    : finish_pipe gives the outer wire and every hole the SAME
                Law_Linear(0 -> 1, 1 -> 1+k) with k = tan(5 deg) = 0.087488664,
                and BRepFill_PipeShell applies that law about the section's own
                location frame — one station on the spine, shared by both
                wires. So at every station the two sections are one homothety
                of the profile about a common centre, which preserves
                containment and keeps the two end sections coplanar. The
                annular area at station t is (A_out - A_in) * s(t)^2, so
                V = (A_out - A_in) * L * integral[0,1] (1+kt)^2 dt
                  = 83.857371 * 40 * (1 + k + k^2/3)
                  = 3 354.294825 * 1.090040086 = 3 656.315818.
                Cross-check on the same law from a run I did not take:
                [37g] measures an UNHOLED 5 deg taper as
                6 766.447913 -> 7 375.699522, a ratio of 1.0900399 against
                the 1.0900401 above.
Falsifiable by: any residual above 1e-9. This is S14 §12.3 risk 3 — "I believe
                the caps still match, and I did not test it".

## Prediction P11 — the coil moves by a differential, not by a constant
Target        : occt_coil_profile, 24-segment r=6 ring with an r=3 hole,
                quarter turn of radius 18 rising 60.
Baseline      : S14 P16 pinned 5 562.133035056, 50 faces, valid, and pinned it
                as EQUAL to its own outer-minus-hole.
Predicted     : still 50 faces, still valid, and still equal to its own
                outer-minus-hole to 1e-9. I do NOT predict the same double as
                v26: the coil is the one caller whose holed path was already
                exact under the boolean, so the differential is the claim and
                S14's recorded constant is not.
Derivation    : the coil's spine is a single helical edge, so the lateral
                shells are 24 faces each and the caps are one wire plus one:
                24 + 24 + 2 = 50, which is what the boolean produced too.
                finish_pipe is shared, so the coil takes the assembly for free.
Falsifiable by: a differential residual above 1e-9, or a face count that is
                not 50. A face count change here WOULD be a surprise, because
                the boolean between a helical tube and its hole already
                produced the clean 50.

## Prediction P12 — a non-coplanar hole end section is NOT constructible, and
##                  the guard for it is a backstop nothing reaches
Predicted     : I cannot build a fixture that makes the coplanarity check fire.
Derivation    : placed_profile_wires builds every loop from the same 2D xyb in
                the XY plane and maps all of them through ONE mat34, so every
                section starts coplanar; finish_pipe then places the outer wire
                and every hole with the same spine, the same trihedron mode,
                the same WithCorrection and the same taper law (v26 made those
                four agree), so the two end sections are the same rigid motion
                and the same homothety of two coplanar wires. Coplanarity is
                preserved by both.
Falsifiable by: NOTHING I CAN WRITE, and that is registered rather than
                claimed. The guard is kept anyway — it is a dozen vertex
                distances against a plane, it costs nothing, and if any future
                change breaks one of those four agreements it turns a wrong
                solid into a fallback. If the check is deleted, this prediction
                fails silently and no test notices. Same shape as S14's P19.
                This ANSWERS S14 §12.3's fourth open item, which asked whether
                the case is constructible before relying on it being
                impossible: it is not constructible today, and the reliance is
                backed by a runtime check rather than by the argument alone.

## Prediction P13 — overlapping holes fall back, and match the boolean
Target        : outer 24-gon r=6, two r=2 holes at (-1.5, 0) and (+1.5, 0),
                which overlap; straight path, length 40.
Predicted     : the guard refuses, the boolean runs, and the volume equals
                occt_cut(occt_cut(sweep(outer), sweep(h1)), sweep(h2)) to
                1e-9.
Derivation    : the two hole polygons are 3 apart at their centres with a
                circumradius of 2 each, so their boundaries cross and the
                pairwise separation is 0. An assembly here would put two
                overlapping inner wires on one cap face and produce a solid
                that is not the difference of anything.
Falsifiable by: the assembly succeeding.

## Prediction P14 — the Dart side does not move
Target        : flutter analyze and flutter test.
Predicted     : delta ZERO. No file under frontend/ is touched by this
                session.
Falsifiable by: any change in either, which would mean I edited something I
                do not own.
```

---

## 4. What was built

Three commits, and each reverts on its own:

| | |
| --- | --- |
| `bdaf900` | the instrument — `backend/bench/hole_probe.cpp`, off by default |
| `4918eb6` | the change — the guard, the assembly, the fallback, the lifted restriction, scenario [39] |
| `26bc628` | Lane C's missing holed ladder |

### 4.1 The change, in three pieces

**The guard, `profile_holes_are_separate`.** Runs on `xyb` in the profile's own
2D coordinates before any wire exists. Flattens each loop at 2° per sub-chord,
keeping the largest sagitta it discards; then, for every hole, checks that one
of its vertices is inside loop 0 and that no point of its boundary comes within
`sag(O) + sag(H) + 1e-7·diag` of loop 0's; then the same between every pair of
holes, plus "neither hole's first vertex is inside the other". **1.52 ms at
1200 × 1200 vertices** — P8's ceiling was 50 ms and its estimate 7.2 ms; the
axis-aligned rejection is cheaper than I costed it because two concentric rings
fail the first comparison of four.

**The assembly, `assemble_holed_pipe`.** Takes `mk.Shape()` and
`mk.FirstShape()`/`LastShape()` **before** `MakeSolid`, because
`BRepFill_PipeShell::MakeSolid` caps the shell in place and turns those end
wires into end faces; sweeps each hole with the same configuration the boolean
branch uses (one shared `configure_hole_pipe`, so the two routes cannot drift
apart on v26's repair); builds each cap with `BRepLib_MakeFace(outer,
onlyPlane)` — the same call OCCT's own `PerformPlan` makes — and adds the inner
wires to it; sews; requires exactly one shell, no free edges, no multiple
edges, and every input face present; then settles the global sense with
`BRepClass3d_SolidClassifier::PerformInfinitePoint`, as `MakeSolid` does.

**The fallback.** The v26 `BRepAlgoAPI_Cut` loop, unchanged, in an `else`. It is
the same lines and not a reimplementation, which is what makes "the fallback
produces what the boolean produced" checkable rather than aspirational. It
costs one extra sweep per hole when the assembly declines partway, on a path
that was already going to pay for a boolean.

### 4.2 Adjudication

| | prediction | outcome |
| --- | --- | --- |
| **P5** | the assembly is the subtraction at [37f]'s fixtures | **HELD** — all three orientations equal to 1e-9; [39g] adds the direct comparison against `occt_cut` and gets 3.6e-16 (POLY) and 1.8e-16 (SMOOTH) with **the same face count**, 386/386 and 50/50 |
| **P6** | AUTO smooths a holed profile now | **HELD** — 50 faces against POLY's 386, volume 5 031.037365 against the analytic annulus 5 031.440835, 8.0e-5 relative, inside the registered 1e-4 |
| **P7** | a poking hole is refused and matches the boolean | **HELD** — orientation 0 exact (0.000e+00), orientation 1 at 1.5e-16. **The first version of this arm FAILED and the failure was mine**: see §4.4 |
| **P8** | the guard costs under 50 ms at 1200 × 1200 | **HELD** — 1.52 ms |
| **P9** | two and three holes are analytic | **HELD** — 3 913.343961950 and 3 935.705927447 against 3 913.343961950 and 3 935.705927447, and 7.5e-15 on the arc |
| **P10** | a tapered holed sweep is analytic | **HELD on the straight path** — 3 656.315817683 against 3 656.315817683. **Its arc arms found a defect that is not mine**: §4.3 |
| **P11** | the coil moves by a differential, not a constant | **HELD** — 5 562.133035056 and 50 faces, the same value S14's P16 recorded, equal to its own outer-minus-hole at 8.2e-16 |
| **P12** | a non-coplanar hole end section is not constructible | **AS REGISTERED — argued, not pinned.** No fixture reaches the check |
| **P13** | overlapping holes fall back and match the boolean | **HELD** — 3 548.350261969 against the double cut, exact |
| **P14** | the Dart side does not move | **HELD** — `git diff origin/claude/perf-opt2 -- frontend/` is empty |
| **P0–P4** | round one | §2.2 |

**And the bar.** `[39f]`: a 1200-segment ring with an r=3 hole on the 16-span
sampled arc — **2 402 faces, valid, volume 5 089.335272 against an analytic
5 089.356844 (4.24e-6)** — where the v26 route returns nothing after
490 407.2 ms with `occt_sweep_profile: BRep_API: command not done`.

### 4.3 A defect this session found and did NOT fix

**A tapered sweep along a spine of more than one edge produces an INVALID
solid, and it has nothing to do with holes.**

Found by P10's arc arm, which asserted validity and did not get it. Measured
against the **v26** shim built from this branch's parent commit, in the same
run, on the **single-loop** sweep — so the assembly is not involved at all:

| fixture | v26 | v27 |
| --- | --- | --- |
| 24-gon r=6, 8-span polyline arc, taper 5°, **one loop** | 10 476.381185581 **INVALID** | 10 476.381185581 **INVALID** |
| the same, taper 0 | 6 708.589649052 valid | 6 708.589649052 valid |
| the same, taper 5°, SMOOTH spine | 7 312.043216529 valid | 7 312.043216529 valid |
| 10×10 square, **drawn 90° L path**, taper 5°, plain AUTO | 8 555.054342 **INVALID** | 8 555.054342 **INVALID** |
| the same, taper 0 | 7 000.000000 valid | 7 000.000000 valid |

Every digit identical between the two shims. **A one-edge spine is fine; a
straight path is fine; a smoothed run is fine.** What is not fine is a taper
across a mitered joint — and the last row matters most, because a drawn
90° corner is not an exotic input. It is a swept bar with a draft angle, under
plain `OCCT_SWEEP_PATH_AUTO`, and the app would accept and draw the result.

Not fixed here, deliberately: it is a second defect, in a second mechanism
(`SetLaw` across `BRepFill_Sweep::PerformCorner` rather than anything about
holes), and it deserves its own pre-registration rather than being folded into
a commit about something else. `[39b]` records it in the test file and asserts
what can honestly be asserted instead — that the tube equals the boolean
exactly, and that it is valid **exactly when the unholed sweep it is made from
is**. The assembly is not allowed to be worse than its own ingredients; it is
not asked to be better. **`Needs:` integrator.**

### 4.4 The guard was wrong, and a fixture I nearly did not write caught it

`flatten_loop` computed the arc centre by stepping **against** the chord's left
normal. A DXF bulge is `tan(θ/4)` and a positive one is counter-clockwise; a
body turning counter-clockwise keeps its centre of curvature on its left, so
the belly is on the right — which is also why `arc_loop_signed_area` **adds**
the segment area for `b > 0` on a counter-clockwise loop. The sign was
inverted.

The arithmetic that settles it is one line. With `p0 = (0,0)`, `p1 = (10,0)`,
`b = tan 22.5°`, rotating `p0` about the centre by θ must land on `p1`:

```
  m - n*h : centre (5.000, -5.000)  endpoint (-0.000, -10.000)   wrong
  m + n*h : centre (5.000,  5.000)  endpoint ( 10.000,   0.000)  p1
```

**What it cost, had it shipped:** the flattened polygon traces a region the
profile does not have, so the guard answers a question about the wrong shape —
and it can therefore say *"this hole is safely inside"* about a hole that is
not. That is a false YES, which is the one failure mode the guard exists to
prevent, and it produces a **wrong solid** rather than a slow one. It was found
by a bulged fixture reporting "separate" for a hole outside the profile.

Two checks now stand behind it, both in the repository:

* `[39h]` sweeps a **true circle** — a 2-point loop with bulge 1 at both
  vertices, two semicircles, area exactly 25π — with a 24-gon hole, and pins
  3 017.359511941 against an analytic 3 017.359511941 (3.0e-16). A profile with
  no straight edges at all, so the flattening has nowhere to hide.
* the same circle with a hole **straddling** its wall at x = 4.5…5.5: refused,
  boolean, 3 121.926488718 against `occt_cut`'s 3 121.926488718 — and
  `outer − hole` printed beside it at 3 101.592653590, which is what proves the
  hole really straddles rather than merely sitting near the wall.

And separately, `flatten_loop`'s signed area now agrees with
`arc_loop_signed_area`'s on five loops (square, bowed in, bowed out, and a
circle both ways), in sign and to the sagitta: 30.1386 against 30.1101,
169.8614 against 169.8899, ±78.5239 against ±78.5398.

### 4.5 The other thing the first run caught, in the test rather than the code

`[39c]`'s reference sweeps asked for `OCCT_SWEEP_PATH_AUTO`. The **tube** asks
for AUTO too, but the guard refuses that profile, so AUTO falls back to POLY
for it — while a *single-loop* reference sweep asked for AUTO is smoothed. Two
different spines, compared as though they were one.

Orientation 0 came out 1.1 % apart and orientation 1 agreed to 4e-10, which is
the tell: "Fixed" gives `A × rise` whatever the path does in XY, so it cannot
see a spine change. Naming the mode on all three sweeps is what makes that arm
a differential.

### 4.6 Lane C had no holed sweep at all

`sweep.holed` is new, and the reason it is new is worth saying: **nothing in
the per-push gate exercised a two-loop profile.** That is how a holed sweep
stayed on the v23 mitered spine, and stayed failing at 1200 segments, through
v24, v25 and v26 without anything noticing.

| ladder | k | R² | interval |
| --- | ---: | ---: | --- |
| `sweep.segments` | 1.194 | 0.9945 | [1.020, 1.368] |
| **`sweep.holed`** | **1.143** | 0.9987 | [1.061, 1.226] |
| `sweep.legacy` (v23) | 1.914 | 0.9785 | [1.359, 2.470] |
| `sweep.coil` | 1.388 | 0.9491 | [0.758, 2.018] |

95.2 / 221.3 / 464.7 ms at 32 / 64 / 128 segments, against the unholed
43.6 / 110.9 / 228.1 — **almost exactly 2×, which is what "two sweeps instead
of one" predicts** and is the shape of the claim rather than a number to
record. The holed sweep now sits in the same family as the unholed one.

---

## 5. What I am unsure of

1. **The 25 minutes I could not reproduce.** §2.3. S14 killed a prototype after
   25 minutes at 1200 segments; the same operation here is 33.5 s end to end
   and ~11.7 s scaled to S14's machine. I have three candidate explanations
   (a plane fit over both wires instead of one, a rebuilt cap wire defeating
   sewing's identity match, a Debug kernel) and **no way to choose between
   them**, because the prototype is not in the repository. If the real cause is
   none of those and it is something my probe also does, then the number I am
   quoting for construction is wrong by two orders of magnitude and I have not
   noticed. What makes me think that is unlikely is [39f], which builds the
   thing through the shipped entry point in a smoke test and takes 8 s — but
   that is the same code path as the probe, so it is not independent evidence.

2. **P12 is argued, not pinned, and I said so before I wrote it.** No fixture I
   can build makes the coplanarity check fire, because `placed_profile_wires`
   puts every loop in one plane and `finish_pipe` places them all with one
   spine, one trihedron, one `WithCorrection` and one taper law. Delete the
   check and nothing goes red. It is kept because those four agreements are
   *conventions between two call sites*, not invariants the type system holds,
   and v26 exists because two of them had silently disagreed since v15.

3. **The guard's margin is `1e-7 · diag` and I chose that number by
   analogy, not by derivation.** The sagitta terms are derived — they are the
   flattening's own error and they belong there. The relative term is there to
   keep the test scale-free and to refuse a hole that is *exactly* tangent to
   the wall, where the assembly and the boolean genuinely disagree about what
   the solid is. I do not know what the right value is. Too small and a
   tangent hole assembles into a solid with a degenerate cap edge; too large
   and a legitimately-thin wall falls back to a boolean it did not need. I have
   tested neither end. **A wall thinner than 1e-7 of the profile's diagonal is
   the case to build a fixture for**, and I did not.

4. **Sewing is 64 % of construction at 1200 segments** — 5 094.6 ms of
   7 952.7 ms — and it is doing less work than it looks like it should. The
   cap's outer wire IS `mk.FirstShape()`, which is the lateral shell's own free
   boundary, the same `TShape`, so there is nothing to match there. A shell
   built directly with `BRep_Builder` would skip almost all of it. I did not
   take that, because sewing is also what settles the face orientations (the
   hole's shell must face *into* the hole) and what reports `NbFreeEdges()`,
   which is the closed-shell guard. **Measured, not taken** — the trade is
   about 5 s at 1200 segments against doing the orientation reasoning by hand,
   and I would want a fixture for a *non-convex* profile before touching it.

5. **`BRepGProp::VolumeProperties` costs 7 ms per B-spline face** and I found
   that by accident, looking for something else. It is the largest single stage
   in the 1200-segment measurement — 16 778.5 ms, more than the whole
   construction — and it is equally large on the *unholed* control, so it has
   nothing to do with this session. It is not in the shipped path either. But
   `occt_shape_volume` **is** called by the app, and nothing anywhere in this
   repository's profile says it is not free. I have not looked at where.

6. **The taper defect in §4.3 is characterised, not diagnosed.** I know it
   needs a taper and a spine of more than one edge, I know it predates v27
   digit for digit, and I know a drawn L path reaches it under plain AUTO. I do
   not know whether the shell self-intersects at the miter, whether the caps
   are wrong, or whether `Law_Linear` and `BRepFill_Sweep::PerformCorner`
   simply do not compose. I stopped at "not mine to fix in this commit" rather
   than at "understood".

7. **[39f] costs about 33 s of a 2 m 12 s smoke run on this machine**, and
   three quarters of that is the two verification calls, not the sweep. On the
   CI runner (~2.9× faster here) it should be ~12 s. If that becomes the
   reason someone drops the arm, **drop `occt_shape_volume` before
   `occt_shape_valid`** — a solid that builds and is invalid is the worst
   outcome available at that size, and it is the cheaper of the two calls.

8. **Everything S14 §14.3 still says.** Item 3 (the hole assembly at scale) is
   answered. Item 4 (containment) is answered by a guard whose margin is item 3
   of this list. Items 1, 2, 5 and 6 stand exactly as written — and item 6, "I
   do not know what else in this shim is only ever exercised straight", just
   collected another example that is not about holes at all: §4.3's taper.

---

## 6. Definition of done

| | |
| --- | --- |
| `flutter analyze --no-pub --no-fatal-infos --no-fatal-warnings` | 56 issues, **delta ZERO** — and provably so rather than by comparison: `git diff origin/claude/perf-opt2 -- frontend/` is empty, no Dart file is touched |
| `flutter test` | **2 368 passed**, three consecutive runs, full logs kept (§6.1) |
| `python3 -m unittest discover -s ci -p 'test_*.py'` | **52 tests, OK** |
| `occt_smoke` on real OCCT 7.9.3 | **PASS**, 2 m 12 s, with a scenario per new claim: [39a] two and three holes, [39b] taper, [39c] a hole poking out, [39d] overlapping holes, [39e] the coil, [39f] the 1200-segment bar, [39g] the assembly against the boolean, [39h] arcs and a straddling hole; [37f] arm 3 inverted |
| `occt_mesh_recon_test` | **86 passed, 0 failed** |
| `occt_bench` (Lane C) | **LANE C: PASS**; `HARNESS: NOT VALIDATED` on `edgeInfo1`, which is the run-to-run instrument variance S14 §5.4 measured at a spread of 0.118 on untouched code |
| predictions before the code | `d6f25b6` (P0–P4) → `bdaf900`; `c937778` (P5–P14) → `4918eb6` |
| separate, revertible commits | instrument `bdaf900`, change `4918eb6`, Lane C `26bc628` |
| `perf/baseline.json`, `PERFORMANCE_PROFILE.md`, `frontend/lib/perf*.dart` | untouched |

`pubspec.lock` is untouched, and that took two attempts: the first Flutter I
installed was 3.35.5, which resolved `characters` and `intl` **downwards** and
rewrote the lock. Reverted, and the whole verification re-run on **3.47.1**,
which is what round one's §1.4 says CI uses.
