# M440 — Mesh→CAD: an audit against ground truth, and the plan to make it exact

**Status:** analysis complete; **Phase 1 and the measurable half of Phase 2 are
built and merged** — see §9, which records what changed and what it measured.
Phases 3–6 remain proposed.
**Predecessor:** `M232_MESH_TO_CAD_ANALYSIS.md`, which decided to build this and
built Stages A and B. This document measures what those stages actually produce
on eight real files, finds eight defect classes, locates the root cause of four
of them in the source, and proposes the programme that closes them.

Everything numeric below was produced by running the shipping pipeline on Linux
against OCCT 7.9.3 built from the pinned submodule. Nothing is estimated.

---

## 0. The one-paragraph answer

The converter is **correct on the trivial case and unsound on every other one.**
A 16-triangle prism comes back as exactly its seven faces, valid, closed, volume
exact to the last digit. An 80-triangle prism — the same shape class, with one
arc in the profile — comes back with four faces too many, `BRepCheck` invalid,
six self-intersections and a **2.16 mm gap** between faces that should meet.
Every model above that complexity is worse. The failures are not random: they
are four specific, locatable, individually fixable mechanisms, plus one missing
stage (mesh repair) and one missing capability (feature recovery) that no amount
of fixing will produce because neither has been written. **The current output is
a dead B-Rep; the request is a feature tree.** Those are different programmes,
and §6 costs both.

---

## 1. The instrument

Before any claim about quality, there has to be something that measures it.
`mesh_check.cpp` measured *deviation* and *coverage* — is the body in the right
place. It had **zero** validity checks: `grep BRepCheck_Analyzer tests/` returned
nothing, and no code anywhere in the shim calls a self-intersection checker.

So a body could sit exactly on its mesh, pass every existing test, and still be
one a kernel refuses to fillet. That is precisely the reported failure — *"it
always delivers broken stuff or weird topology"* — and until now nothing in the
repository could see it.

Two tools were written for this audit and are committed with it:

| | |
|---|---|
| `backend/occt/tests/cad_audit.cpp` | validity (`BRepCheck_Analyzer`, every status counted per sub-shape), self-intersection (`BOPAlgo_CheckerSI` at level 9), orientation, needle/sliver/tiny-edge detection, G0 gap and G1 tangency sampled across every shared edge, surface-kind histogram by count and by area, and a diff against a reference body. Exit code 0 only when every one of them is clean. |
| `backend/occt/tests/tessellate.cpp` | B-Rep → STL at a stated deflection, with optional `float32` rounding and vertex-consistent noise. This is what makes **exact ground truth** possible: mesh a known solid, reconstruct from the triangles alone, compare against the solid it came from. |

The audit tool was validated against the one body whose answer is known: the
`Lampenbefestigung` STEP file audits `VERDICT: CLEAN`, `problems=0`, 15 faces,
0 self-intersections, G0 gap 2.8 × 10⁻¹¹ mm.

> **One instrument bug, found and fixed during the work,** because it matters for
> how the noise numbers in §5.4 should be read. The first version of
> `tessellate.cpp` jittered each *triangle corner* independently, which tears a
> shared vertex into three and destroys watertightness — it measured the tear,
> not the noise, and reported a collapse at 5 µm that was not real. Noise is now
> hashed from the vertex *position*, so every face meeting at a node moves
> together; the mesh is verified still manifold, oriented and boundary-free
> after jittering. The corrected numbers are in §5.4 and they are much milder.

---

## 2. The corpus, characterised

Eight files. Each was measured independently — in Python/NumPy, not with the code
under test, so the converter is not grading its own homework.

| # | model | source | triangles | vertices | diagonal | manifold | oriented | comps | χ | genus | class |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `Part9.3mf` | Bambu (from STEP) | 16 | 10 | 22.14 | ✓ | ✓ | 1 | 2 | 0 | **prism** |
| 2 | `Lampenbefestigung…step` | this app, shim v29 | *(reference)* | 26 | 93.74 | ✓ | ✓ | 1 | 2 | 0 | **prism** |
| 3 | `obj_1_TreeOfLife.stl` | Shapr3D | 376 | 182 | 112.80 | ✓ | ✓ | 1 | −6 | 4 | **extrusion** |
| 4 | `Lesezeichen_Schmetterling_2.3mf` | — | 10 714 | 5 285 | 166.30 | ✓ | ✓ | 1 | −72 | 37 | **extrusion** |
| 5 | `1204_TOKA_Base.stl` | — | 1 138 | 561 | 54.08 | ✓ | ✓ | 1 | −8 | 5 | **mixed** |
| 6 | `whale_stl.stl` | — | 83 178 | 41 591 | 203.93 | ✓ *(after cleanup)* | ✓ | 3 | 6 | 0,0,0 | **organic** |
| 7 | `BunnyPrintready.stl` | — | 283 632 | 141 887 | 2.67 | **✗** | **✗** | **30** | 323 | **−131.5** | **organic, broken** |
| 8 | `planetary.dxf` | — | *(not a mesh)* | — | — | — | — | — | — | — | **2D** |

Four of these have **exact, provable ground truth**, which is what makes the
audit science rather than opinion:

**#2 `Lampenbefestigung`** — every one of its 14 planes has a normal whose Y
component is exactly ±1 (two of them, at y = +5 and y = −45) or exactly 0 (the
other twelve); its single cylinder has axis exactly (0,−1,0) and radius
15.000000. Vertices 26, edges 39, faces 15, χ = 2. An N-segment closed profile
extruded as a prism has exactly 2N vertices, 3N edges and N+2 faces; N = 13 gives
26/39/15. **It is a 13-segment profile — 12 lines and one r=15 arc — extruded
50 mm.** That is the whole model, and it is not a guess.

**#1 `Part9`** — 10 unique vertices on exactly two Z levels (0 and 2), 16
triangles = 2 pentagon caps (3 each) + 5 walls (2 each). **A pentagon extruded
2 mm.** Ground truth: 7 faces.

**#3 `TreeOfLife`** — exactly 2 distinct Z levels (0 and 1) among all 182
vertices; 84 distinct exact planes (normal + offset to 1e-5), of which **2 are
horizontal and 82 vertical, and zero are anything else**; 95.3 % of area in the
two caps. **A polygon extruded 1 mm**, genus 4 = four holes. Ground truth: 84
faces.

**#4 `Schmetterling`** — exactly 2.0000 mm thick, 3 Z levels, 37 profile loops,
genus 37. An extrusion again, but its profile boundary is *curved*: 2 638
tessellated cap-boundary segments.

### 2.1 The two organic models are not the same problem

`whale` looks broken and is not: 16 zero-area triangles carry all 12 of its
non-manifold edges, and the shim's own degenerate-drop removes them. **After
`BuildMesh`, the whale is a closed, orientable, consistently-wound 2-manifold**
— three components (a body and two identical 124-vertex eyes, both positive
volume), each genus 0, χ = 6 = 3 × 2. Its difficulty is that it is analytic
nowhere: 82 567 distinct exact planes for 83 162 triangles (0.993 per triangle),
median dihedral 1.15°.

`Bunny` is genuinely broken and **stays broken**, because nothing in the pipeline
can repair it:

| defect | count | survives `BuildMesh`? |
|---|---|---|
| non-manifold edges (4 faces each) | **442** | **yes** |
| boundary edges — one hole, a single 64-edge loop | **64** | **yes** |
| inconsistently wound (duplicated directed edges) | **884** | **yes** |
| duplicate faces, all **opposite** winding (zero-thickness sheets) | **264** | **yes** |
| connected components | **30** | **yes** |
| components with **negative** signed volume (inverted shell / void) | **1** | **yes** |
| near-duplicate vertices merged only by tolerance | 158 | no — welded |

χ = 323 over 30 components gives genus **−131.5**, which no surface has. This
mesh cannot produce a valid solid, and the pipeline does not decline it — it
proceeds, which is the mechanism behind *"delivers broken stuff"*.

### 2.2 `planetary.dxf` is not a mesh, and is still relevant

It holds 7 POLYLINEs (358 vertices, **every vertex carrying a bulge — so every
segment is a circular arc**) and 5 CIRCLEs, in inches: a planetary gear set, ring
+ 3 planets + sun + a hex bore. There is no 3DFACE and no POLYFACE; mesh→CAD does
not apply to it and this audit does not pretend otherwise.

What it *is* is the two-dimensional statement of the same problem — recover exact
arcs and lines from a discretised boundary — and that is not a side issue here,
because **#3 and #4 are extrusions whose whole difficulty is their 2D profile.**
Measured with an independent greedy line/arc segmenter:

| model | tessellated profile segments | line/arc primitives | compression | ideal faces | naive faces |
|---|---|---|---|---|---|
| `TreeOfLife` | 91 | 53 (15 arcs) | 1.7× | **55** | 93 |
| `Schmetterling` | 2 638 | **321** (259 arcs) | **8.2×** | **323** | 2 640 |

*(The segmenter over-merges at the loop seam — it returns 4 primitives for
Part9's 5-sided pentagon — so these primitive counts are indicative lower bounds.
The order of magnitude is the point.)*

---

## 3. Results: every model, converted and audited

Default parameters (`tol = 0.002 × diag`, `sharp = 22°`), shipping pipeline.
"GT" is ground truth where it exists. "+unify" is the face count after a single
`ShapeUpgrade_UnifySameDomain` pass — see §4.1 for why that column exists.

| model | ms | patches | faces | +unify | GT | closed | **valid** | **self-int** | G0 gap | volume error | verdict |
|---|---|---|---|---|---|---|---|---|---|---|---|
| `Part9` | 2 | 7 | **7** | 7 | **7** | 1 | **1** | **0** | 4e−14 | **0.000 %** | **CLEAN** |
| `Lampenbefestigung` round trip | 42 | 12 | 19 | **15** | **15** | 1 | **0** | **6** | **2.159 mm** | 0.34 % | NOT CLEAN |
| `TreeOfLife` | 71 | 79 | 117 | **93** | **84** | 1 | 1 | 0 | 1.6e−14 | 0.000 % | CLEAN, over-segmented |
| `TOKA_Base` | 2 701 | 47 | 48 | 43 | — | 1 | 1 → **0** | **13** | 0.139 mm | +0.18 % | NOT CLEAN |
| `Schmetterling` | 21 858 | 326 | 2 403 | **1 401** | ~323 | 1 | **0** | **235** | 0.843 mm | +0.90 % | NOT CLEAN |
| `whale` | 25 221 | 96 | 286 | — | n/a | 1 | 1 | **151** | 0.286 mm | −0.55 % | NOT CLEAN |
| `Bunny` | **938 437** | 2 814 | **10 397** | — | n/a | **0** | — | — | — | **+4.4 %** | **BROKEN** |

Read the three columns in bold. **One model of seven is clean.** Five of the
others carry self-intersections — 6, 13, 151, 235 — and a self-intersecting solid
is one that will fail the next boolean, the next fillet, and the STEP import on
the other side. That is the user's complaint, stated as a number.

### 3.0 `Bunny`, in full, because it is the complaint itself

```
283 632 triangles, 141 887 vertices after exact dedup
  938 437 ms   mode=fit tol=0.002*diag sharp=22
  mesh     465 non-manifold, 64 boundary, 6935 flipped, diag 2.6717
  patches  2814  (plane 1595 cyl 107 cone 248 sph 52 torus 100 freeform 455 faceted 237)
  faces    2577 built, 0 failed;  edges 495 exact, 5605 approx
  result   shells 536 solids 77 closed 0   fit rms 0.000733
  shape    10397 faces, 38470 edges, 76940 vertices
  volume   0.361756            (the mesh's own volume is 0.346502 — +4.4 %)
  edges    421 free, 465 shared by more than two faces
```

Every line of that is a defect.

- **15 minutes 38 seconds** — 3 309 µs per triangle, a thousand times the
  1.9 µs/triangle M232 measured on synthetic meshes.
- It **reports** 465 non-manifold edges, 64 boundary edges and 6 935 flipped
  triangles, and then converts anyway. Nothing declines the model and nothing
  repairs it.
- **52 spheres, 100 tori, 248 cones and 107 cylinders — on a rabbit.** These are
  not features of the model; they are primitives fitted to noise.
- **`closed 0`. 536 shells and 77 solids from one object.** The output is not a
  body.
- The output B-Rep is **itself non-manifold and open**: 421 free edges and 465
  edges shared by more than two faces. The input's defects were not merely
  carried through — they were multiplied.

And the audit could not be completed on it: `BOPAlgo_CheckerSI` at level 9 was
still running after **50 minutes** on the 10 397-face result and was killed at
its cap, having printed nothing. That is a measurement in its own right — the
body is pathological enough that the kernel's own checker will not terminate on
it in any time a person would wait. The self-intersection count for `Bunny` is
therefore not "zero" and not a number; it is **unmeasurable**, which is strictly
worse than a large one.

There is no parameter setting that fixes this, because the mesh violates the
precondition every later stage assumes. This is §4.5, measured.

### 3.1 The minimal failing case, face by face

The `Lampenbefestigung` round trip is the whole problem in 80 triangles. Ground
truth is 15 faces; the reconstruction returns 19. The extra four are not noise:

| ground truth | area | reconstruction | area each |
|---|---|---|---|
| f0 plane n=(−0.79913, 0, +0.60116) | 2346.4591 | **f10 + f11**, identical planes | 1173.2296 ×2 |
| f3 plane n=(−0.65906, 0, −0.75209) | 40.1116 | **f13 + f14**, identical planes | 20.0558 ×2 |
| f10 plane n=(+0.70711, 0, −0.70711) | 250.0000 | **f15 + f16**, identical planes | 125.0004 ×2 |
| f11 plane n=(+0.65226, 0, −0.75799) | 1002.8067 | **f17 + f18**, identical planes | 501.4031 ×2 |

Four rectangles, each tessellated as two triangles, each split along its own
diagonal into two faces whose plane equations agree to seven digits and whose
areas sum to the original exactly. 15 + 4 = 19. And the cylinder:

```
GROUND TRUTH  cylinder r=15.000000  U span = 1.570796 rad =  90.0000°
RECONSTRUCTED cylinder r=14.999985  U span = 2.158801 rad = 123.6902°
```

**The cylindrical face wraps 33.69° past where the part ends.** It is a
quarter-cylinder in the original and 37 % more than that in the reconstruction.
That is the "spike": a face extending beyond its own boundary, through its
neighbours — and it is where the 6 self-intersections and the 2.16 mm G0 gap come
from.

---

## 4. Root causes, located in the source

### 4.1 D1 — the fit path never runs the same-surface merge

`ShapeUpgrade_UnifySameDomain` is called in `mesh_recon.cpp` exactly once, at the
end of the **faceted** branch, with a comment calling it *"the only thing that
makes a faceted conversion usable at all"*. The **prismatic/fit branch does not
call it.** Patch-level `MergeRegions` runs earlier, but it is gated on patches
sharing a smooth-run origin and holds pairs to a strict fit test, and nothing
afterwards catches two faces that ended up on a bit-identical plane.

Running the missing pass by hand, on the bodies as built:

| model | faces as built | after one `UnifySameDomain` | ground truth |
|---|---|---|---|
| `Lampenbefestigung` round trip | 19 | **15** | **15 — exact** |
| `TreeOfLife` | 117 | 93 | 84 |
| `TOKA_Base` | 48 | 43 | — |
| `Schmetterling` | 2 403 | **1 401** (−42 %) | ~323 |

It recovers the ground-truth face count *exactly* on the reference body and
removes 1 002 spurious faces from the butterfly. **It is necessary and it is not
sufficient**: after unifying, the reference body still reports `valid=0`, 6
self-intersections and the same 2.159 mm gap. And it is not free — `TOKA_Base`
goes from `valid=1` to `valid=0` (a `SelfIntersectingWire` appears) — so it must
be followed by re-validation and healing, never applied blind.

### 4.2 D2 — trimming is not bounded by the data

The 123.69°-vs-90° cylinder is one instance of a general failure: **a fitted
surface is not constrained to stop where its triangles stop.** The same signature
shows in the bounding box. A reconstruction cannot be larger than the mesh it
came from, and these are:

| model | mesh diagonal | B-Rep diagonal | oversize |
|---|---|---|---|
| `TOKA_Base` | 54.083 | 55.817 | **+3.2 %** |
| `Schmetterling` | 166.298 | 171.364 | **+3.0 %** |
| `whale` | 203.930 | 210.622 | **+3.3 %** |

M232 added `FaceWithinPatch`, which refuses a face that escapes its own
triangles. These bodies show it is not catching the periodic case: on a cylinder
or a cone the overshoot is *around* the axis, in the parametric U direction, and
a pole-based box does not see an over-wrapped face as larger. The three numbers
above are the same defect measured three ways.

### 4.3 D3 — nothing ever asks whether the result self-intersects

There is no call to `BOPAlgo_CheckerSI`, `BRepAlgoAPI_Check`, or
`BOPAlgo_ArgumentAnalyzer` anywhere in `mesh_recon.cpp`, `occt_capi.cpp` or the
test suite. `BRepCheck_Analyzer` appears three times in `mesh_recon.cpp` and not
on the output path. The `Report` struct has fields for patches, faces, shells,
solids and `closed` — and none for validity or self-intersection.

So the pipeline cannot know it has produced a bad body, and therefore cannot fall
back when it does. Every fallback it has (`freeform`, `faceted`, "drop the fitted
shell if it will not close") is triggered by *closure*, which all five failing
models pass.

### 4.4 D4 — recognition is fragile, and the fit can be worse than no fit

Ground truth meshed at 0.002 × diag, float32, with vertex-consistent noise:

| noise (× diag) | on this 94 mm part | faces | planes | cylinder | closed | volume error |
|---|---|---|---|---|---|---|
| 0 | 0 | 19 | 9 | **1** | 1 | 0.34 % |
| 2 × 10⁻⁵ | 1.9 µm | 19 | 9 | **1** | 1 | 0.34 % |
| **1 × 10⁻⁴** | **9.5 µm** | 20 | 9 | **0 — became a cone** | 1 | 0.003 % |
| 5 × 10⁻⁴ | 47.6 µm | 55 | 8 | 0 | 1 | 0.06 % |
| 2 × 10⁻³ | 190 µm | 75 | 5 | 0 | 1 | 0.11 % |
| 5 × 10⁻³ | 476 µm | 78 | 2 | 0 | 1 | 0.19 % |

Two findings, and the second is the more interesting one.

**The r=15 cylinder is lost at 9.5 µm of noise on a 94 mm part** — one part in
10⁴ of the diagonal, and about 200× the float32 quantisation at these
coordinates. Planes fall from 14 to 8 by 48 µm. Real files — decimated, repaired,
re-exported, scanned — carry far more than that. This is the quantitative answer
to why a pipeline that passes a synthetic suite fails on downloads.

**And at zero noise, the fitted body's volume error (0.34 %) is a hundred times
worse than the faceted fallback's (0.003 %).** On this part, recognising surfaces
actively makes the geometry less accurate than not recognising them — because the
over-extended cylinder of §3.1 adds volume the part does not have. A quality gate
comparing fitted against faceted would have caught this; there is none.

The degradation is at least graceful: closure holds throughout, and the fallback
to faceted is real. The pipeline fails *soft*, which is the right design. It just
fails very early.

### 4.5 D5 — there is no mesh repair stage

`BuildMesh` welds, drops triangles with a repeated index, and drops triangles of
zero area. That is the entire preprocessing. `BuildAdjacency` leaves non-manifold
edges unlinked *by design* — the comment argues a non-manifold edge is a feature
boundary, which is right for a CAD export and wrong for a damaged download. There
is no hole filling, no duplicate-face removal, no non-manifold resolution, no
component policy, and no mesh-level self-intersection removal.

For `whale` this happens not to matter. For `Bunny` — 442 non-manifold edges, a
64-edge hole, 884 flipped triangles, 264 opposite-wound duplicates, 30 components
— it decides the outcome before a surface has been fitted, and §3.0 is what that
decision produces: 536 shells, 77 solids, 421 free edges, not closed, 15 minutes.

Note that the shim's own report counts 465 non-manifold and 64 boundary edges
where the independent measurement found 442 and 64: the tolerance weld itself
creates 23 more non-manifold edges than the input had. Repair has to run *after*
welding, not instead of it.

### 4.6 D6 — the pipeline is not monotone in its own tolerance

`TOKA_Base`, sweeping tolerance at four sharp angles (results identical across
`sharp` = 15/22/30/40, which is a finding of its own — the adaptive
`FeatureAngleDeg` is overriding the parameter on most models):

| tol × diag | faces | surface mix | **closed** | volume error |
|---|---|---|---|---|
| **0.0005** | 90 | 37 plane, 20 cyl, 5 torus, 5 faceted | **0 — no solid** | 2.59 % |
| 0.002 | 48 | 19 plane, 17 cyl, 5 torus | 1 | 0.18 % |
| 0.005 | 69 | 17 plane, 15 cyl, 5 torus, 1 freeform, 3 faceted | 1 | 1.30 % |

**Tightening the tolerance makes the result worse and stops it being a solid at
all.** A user who asks for more accuracy gets less. `TreeOfLife` shows the mirror
image: at `sharp` ≥ 30 it invents **spheres** on a flat extruded plate (1–2 of
them) and volume error jumps from 0.000 % to 1.4–2.8 %.

### 4.7 D7 — cost is super-linear on defective input

M232 measured 1.9–3.3 µs per triangle on synthetic meshes. Measured here:

| model | triangles | time | µs/triangle |
|---|---|---|---|
| `Part9` | 16 | 2 ms | 125 |
| `TreeOfLife` | 376 | 71 ms | 189 |
| `TOKA_Base` | 1 138 | 2 701 ms | **2 374** |
| `Schmetterling` | 10 714 | 21 858 ms | **2 040** |
| `whale` | 83 178 | 25 221 ms | 303 |
| `Bunny` | 283 632 | **938 437 ms (15 min 38 s)** | **3 309** |

`Schmetterling` is 10 714 triangles and takes 21.9 seconds — on an iPad that is
an app the watchdog kills. `Bunny` is 3.4× the whale's triangles and takes **37×
the whale's time**; the difference between them is not size, it is that one is a
clean manifold and the other has 442 non-manifold edges and 30 components.
**Defects cost more than geometry does** — which is also why the repair of
Phase 1 is expected to pay for itself in Phase 6.

### 4.8 D8 — no feature recovery exists, at all

This is the gap between what the pipeline produces and what was asked for. The
request is *"a chamfer is a chamfer, an extrusion is an extrusion, a revolve is a
revolve, a fillet is a fillet"*. The `Report` struct's vocabulary is
`planes, cylinders, cones, spheres, tori, freeform, faceted` — surface kinds, not
features. Every output is a dead B-Rep with no history.

`Part9` is provably a pentagon extruded 2 mm. It converts perfectly — into seven
disconnected planar faces with no sketch, no extrude, no depth parameter, nothing
to edit. The information needed to say "extrude, 2 mm" was in the mesh (two Z
levels, 10 vertices) and is thrown away.

M232 §Stage C already identified this as the thing the app is uniquely placed to
do, because `part_model.dart` has a feature tree and `recomputeAllFeatures`
already replays history. It was never built.

---

## 5. What "absolutely perfect" has to mean, to be testable

"Perfect" cannot be a review; it has to be a gate. Proposed definition — a
conversion is **certified** when all of the following hold, checked by
`cad_audit` in CI:

1. `BRepCheck_Analyzer(shape, true).IsValid()` — and zero statuses of any kind on
   any sub-shape, not merely a true at the top.
2. `BOPAlgo_CheckerSI` at level 9 reports **zero** interferences.
3. One closed shell per input component; zero free edges; zero edges on more than
   two faces.
4. Positive volume; every face's normal outward.
5. No needle faces (4πA/P² ≥ 10⁻³), no edge shorter than 10⁻⁶ × diagonal, no
   face or edge tolerance above 10⁻⁴ × diagonal.
6. Two-sided Hausdorff distance to the input mesh below the stated tolerance —
   deviation *and* coverage, so neither an invented face nor a dropped region
   passes.
7. B-Rep bounding box no larger than the mesh's, to within tolerance.
8. G1 across every edge the mesh says is smooth; G0 gap below 10⁻⁵ × diagonal.
9. Volume within a stated bound of the mesh's, signed.
10. **Determinism and monotonicity:** the same input gives the same output, and
    tightening the tolerance never reduces the number of recognised surfaces nor
    breaks closure.

Criteria 1–9 are implemented in `cad_audit.cpp` today. Criterion 10 needs the
sweep harness of §6 Phase 0. Of the seven conversions in §3, **one passes.**

---

## 6. The plan

Six phases. Each ends in a gate that is a number, not a judgement. Phases 1–3 are
sequential (each depends on the last); 4 and 5 run in parallel after 3; 6 runs
throughout. Sizing assumes engineers fluent in computational geometry — this is
not work that parallelises across people who are learning OCCT.

### Phase 0 — The measuring apparatus (2 weeks, 1 engineer)

Nothing else can start honestly until failure is visible.

- Land `cad_audit` and `tessellate` (done — committed with this document) and
  wire both into CI as a **gate**, not a report.
- Build the corpus: these 8 files plus a generated family — every model is
  tessellated at 6 deflections × 4 noise levels × float32-on/off, giving ~200
  cases with exact ground truth from the solids they came from.
- Add the **sweep harness** for criterion 10: same input × 12 parameter settings,
  asserting determinism and monotonicity.
- Publish a scoreboard: certified / total, per defect class, per commit.

**Gate:** every number in §3 reproduces from `make audit`. Baseline: 1/7.

### Phase 1 — A guaranteed precondition: repaired, watertight, oriented (6 weeks, 2 engineers)

The fitting stages assume a clean 2-manifold and nothing establishes one. Build
`mesh_repair.{h,cpp}` between `BuildMesh` and `BuildAdjacency`, with a **proof
obligation**: it either returns a closed, orientable, consistently-wound
2-manifold, or it declines the model with a reason. No middle state.

1. Tolerance weld with a real spatial hash; snap-rounding to remove near-coincident
   vertices (`Bunny`: 158).
2. Remove duplicate faces — same winding keeps one, **opposite winding removes
   both** (`Bunny`: 264 zero-thickness sheets).
3. Resolve non-manifold edges by cutting and duplicating vertices along the edge,
   then re-pairing by geometric proximity of the incident faces (`Bunny`: 442).
4. Fill holes: identify boundary loops, triangulate with a minimum-area /
   advancing-front fill, refine to match local edge length (`Bunny`: one 64-edge
   loop).
5. Orient by BFS flood fill per component; fix global inside/out by signed
   volume.
6. Remove mesh-level self-intersections (the classic failure that becomes a B-Rep
   self-intersection later).
7. **Component policy**, surfaced in the UI rather than guessed: keep largest /
   keep all as separate bodies / boolean-union. The `whale`'s two eyes are
   separate genus-0 solids and should stay separate bodies; `Bunny`'s 30 pieces
   are a botched union and should be unioned properly.
8. Report every repair, so the user is told what was changed.

Reference methods: Attene's *"A lightweight approach to repairing digitized
polygon meshes"* (2010) for the manifold guarantee; Ju's *"Robust repair of
polygonal models"* (SIGGRAPH 2004) for the volumetric fallback when surface
repair cannot converge. Both are implementable; neither needs a new dependency.

**Gate:** all 8 corpus models, and every generated case, enter Phase 2 as
certified closed orientable manifolds — or are declined with a reason. `Bunny`
specifically must come out watertight, genus consistent, one decision made about
its 30 components.

### Phase 2 — A provably valid B-Rep (8 weeks, 2–3 engineers)

Make the output pass §5 criteria 1–9 *whatever* the recognition quality. A
faceted body that is certified beats an analytic body that is not.

1. **Bound every trimmed surface by its own data, in parameter space.** Compute
   the UV extent of a patch's triangles on its fitted surface and refuse any face
   whose UV span exceeds it by more than the sagitta. This is the direct fix for
   the 123.69°-vs-90° cylinder; it must handle periodic U and the seam. Ties
   directly to criterion 7 (bounding box).
2. **Run `UnifySameDomain` in the fit path** — then re-validate and heal, because
   §4.1 shows it can introduce a `SelfIntersectingWire`.
3. **Add the self-intersection gate.** `BOPAlgo_CheckerSI` on the result; extend
   `Report` with `valid`, `self_intersections`, `max_g0_gap`, `bbox_ratio`.
4. **Make the fallbacks quality-driven, not closure-driven.** Today the fitted
   shell is kept if it closes. It should be kept only if it *certifies* and is no
   worse than the faceted build on the Hausdorff and volume criteria — which, per
   §4.4, it sometimes is not. Build both, measure both, ship the better one.
5. Per-face fallback: a face that fails the audit reverts to its triangles while
   the rest of the model keeps its surfaces.
6. Fix D6 — audit every tolerance-dependent decision for monotonicity; make
   `sharp_deg` either authoritative or removed, since §4.6 shows it currently
   does nothing on most models.

**Gate:** 100 % of the corpus certified under §5.1–9, at every tolerance in the
sweep, including `Bunny` and `Schmetterling`. This is the phase that answers *"no
intersections, no weird normals, no spikes"*, and it answers it for every model
rather than the easy ones.

### Phase 3 — Recognition that survives real data (12 weeks, 3 engineers)

Only now is it worth making the *right* surfaces appear, because until Phase 2
"more surfaces" and "more defects" are the same thing.

1. **Robust fitting.** Replace least-squares with M-estimators (Huber/Tukey) and
   MLESAC-style scoring; estimate noise scale from the data rather than fixing a
   tolerance. Target: the r=15 cylinder survives 10⁻³ × diag, a hundredfold
   improvement on §4.4.
2. **Global model selection, not per-patch greed.** The current splitter decides
   patch by patch, which is why `TreeOfLife` invents spheres on a flat plate and
   `Schmetterling` ends with 194 faceted patches. Formulate segmentation as
   energy minimisation over the whole model — an MDL / minimum-description-length
   objective (surfaces + boundaries + residual), optimised by α-expansion graph
   cut over the triangle adjacency graph. This is the single largest quality
   lever in the plan and the least like what is there now.
3. **Constrained fitting** — Benkő/Kós/Várady, CAGD 19 (2002). Detect the
   relations first (parallel, perpendicular, coaxial, concentric, equal radius,
   symmetric), then re-fit *all* surfaces simultaneously subject to them. This is
   what turns 4.9987, 5.0013, 5.0004 into 5.0000, and it is the step that makes
   the result feel like CAD rather than like a fit.
4. **2D profile recovery**, which §2.2 shows is worth 8.2× on `Schmetterling`:
   line/arc/spline segmentation of profile loops with tangency and symmetry
   constraints, feeding both the extrusion detector of Phase 4 and the DXF import
   path `planetary.dxf` represents.
5. **Blend/fillet detection** — rolling-ball centres via a Voronoi/medial
   estimate, per DeFillet (SIGGRAPH 2025). **Read the paper, do not link the
   code: it is AGPL-3.0 and linking it would relicense the app.**

**Gate:** ground-truth face count matched exactly on models 1–4 (7, 15, 84, ~323
faces); cylinder radii and plane normals to 5 significant figures; noise
tolerance ≥ 10⁻³ × diagonal; still 100 % certified.

### Phase 4 — Features, not surfaces: the actual request (16 weeks, 3–4 engineers)

The output stops being a solid and becomes a **feature tree** the user can edit.
This is where the app beats Fusion Prismatic rather than catching up to it, and
it is only possible because `part_model.dart` already has the tree and
`recomputeAllFeatures` already replays it.

1. **Extrusion detection.** A prism is a shape whose faces are either
   perpendicular to a common axis (caps) or contain it (walls). §2 shows this is
   decidable directly from the mesh — `Part9`, `TreeOfLife` and `Schmetterling`
   are all detected by the two-distinct-Z-levels test before any fitting. Emit
   `Sketch(profile) → Extrude(depth)`.
2. **Revolve detection.** All surface axes coincident with one line ⇒ a revolve;
   recover the profile by intersecting with a half-plane.
3. **Fillet and chamfer recovery.** A constant-radius cylindrical/toroidal strip
   tangent to both neighbours is a fillet; a planar strip at equal angle to both
   is a chamfer. Delete the strip, extend and re-intersect the neighbours for the
   sharp edge, and re-apply as `Fillet(r)` / `Chamfer(d)` on the recovered edge —
   `occt_fillet_edges_ex` already exists.
4. **Hole recognition:** through / blind / counterbore / countersink / tapped,
   with depth and diameter as parameters, not as cylinders.
5. **Pattern recognition:** linear and circular repetition, recovered as one
   feature with a count. `planetary.dxf` is the canonical case — its gear teeth
   are a circular pattern of one tooth, and recovering that is the difference
   between 128 arcs and one parameter.
6. **Sketch recovery with constraints**, emitted into the existing constraint
   solver (libslvs is already linked): coincidence, tangency, horizontal/vertical,
   equal, symmetric, with driving dimensions. This is what makes the result
   *editable* rather than merely parametric-looking.
7. **Ordering and validation:** emit the tree, replay it through
   `recomputeAllFeatures`, and assert the replayed solid matches the B-Rep from
   Phase 2 within tolerance. A feature tree that does not rebuild is worse than
   no feature tree.

**Gate:** `Part9` → `Sketch(5 lines) + Extrude(2.0)`, rebuilt volume identical.
`Lampenbefestigung` → `Sketch(12 lines + 1 arc r15.000) + Extrude(50.0)`.
`TreeOfLife` → `Sketch(5 loops) + Extrude(1.0)`. `Schmetterling` → one sketch of
37 loops + one extrude. Every one of them editable: change the depth, get the
right solid.

### Phase 5 — Organic (12 weeks, 2 engineers, parallel with 4)

For `whale` and `Bunny`, where analytic recognition is meaningless and the
correct answer is a NURBS quilt. Per M232 §2.4, the whole path is permissively
licensed:

**QuadriFlow (MIT) or Instant Meshes (BSD) → field-aligned quad mesh →
OpenSubdiv (Apache 2.0) `Far::PatchTable` → regular faces become
`Geom_BSplineSurface` directly, extraordinary vertices approximated from Gregory
patches → sew in OCCT.**

The key fact that makes this cheap: a regular OpenSubdiv patch *is* a bicubic
B-spline patch, so the hand-off to OCCT is lossless and needs no approximation.

**Gate:** `whale` → one closed body per component (3), ≤ 500 G1-continuous NURBS
patches, Hausdorff ≤ 10⁻⁴ × diagonal, certified. `Bunny` likewise after Phase 1
repair.

### Phase 6 — Scale, and the device (continuous, 1–2 engineers)

- **Kill the super-linearity of §4.7.** Profile `Schmetterling` (2 040 µs/triangle)
  and `Bunny` first; the repair of Phase 1 should remove most of `Bunny`'s.
  Target ≤ 10 µs/triangle at 10⁶ triangles.
- **Get it off the UI thread.** The kernel is single-threaded by contract and the
  conversion currently blocks the isolate; that is why `kMaxMeshTriangles` is
  2 000 000 and why 21.9 s of butterfly is dangerous. A worker isolate with the
  existing `RequestCancel`/`Progress` plumbing is the fix.
- Parallelise per-patch fitting (embarrassingly parallel) and per-component
  repair.
- Decimation with feature preservation ahead of segmentation for very large
  scans, and an iPad memory budget that is measured rather than assumed.

### 6.1 Sequencing, and why this order

```
Phase 0  ██                          weeks 1–2      1 eng
Phase 1    ██████                    weeks 3–8      2 eng
Phase 2          ████████            weeks 9–16     2–3 eng
Phase 3                  ████████████ weeks 17–28   3 eng
Phase 4                              ████████████████ weeks 29–44  3–4 eng
Phase 5                              ████████████     weeks 29–40  2 eng
Phase 6  ════════════════════════════════════════════ throughout   1–2 eng
```

Roughly **11 months** to the end of Phase 4 with a team of 4–6, and each phase
ships something: Phase 2 alone converts *"always delivers broken stuff"* into a
converter whose every output a kernel will accept, which is most of the reported
problem. Phase 3 makes the models *right*. Phase 4 makes them *editable*.

The order is not negotiable in one place: **validity before recognition.**
Improving recognition first adds surfaces to a body that is already
self-intersecting, and every measurement in §3 says more surfaces currently means
more defects (`Part9` 7 faces → 0 self-intersections; `Schmetterling` 2 403 faces
→ 235). Phase 2 must land first or Phase 3's gains are invisible.

### 6.2 Risks, stated honestly

- **Phase 3.2 (global MDL segmentation) is the research risk.** It is the largest
  quality lever and the least certain schedule. Mitigation: it is an *alternative*
  to the current greedy splitter, not a replacement of the surrounding pipeline —
  it can be developed behind a flag against the Phase 0 scoreboard and adopted
  only if it beats the incumbent on the corpus.
- **Phase 4 has no complete published method.** Feature recovery is genuinely
  ahead of the literature for the general case. Mitigation: the phase is ordered
  by decreasing certainty — extrusion and revolve detection are nearly mechanical
  and cover models 1–4; fillet/chamfer recovery is well-described; full
  constrained sketch recovery is the ambitious end and can ship incrementally.
- **Licensing.** DeFillet is AGPL — paper only. CGAL is GPLv3, which per M232 §3
  costs nothing because the app is already GPLv3 via QCAD and libslvs, but the
  GPL/App Store tension is a pre-existing condition that this work does not
  change and should not be discovered late.
- **iPad performance is a hard constraint, not a tuning exercise.** Phase 6 is
  listed as continuous for that reason; a converter that is perfect on a
  workstation and kills the app on device has not shipped.

---

## 7. What is already true, and worth keeping

It would be wrong to read §3 as "it does not work". The architecture is right and
a large part of the hard work is done:

- Every failure degrades rather than crashes. Closure is maintained on six of
  seven models; the faceted fallback is real and works.
- `Part9` is exactly correct, and the `whale` — 83 178 triangles, three
  components — comes back as three closed solids and 286 faces with the
  components correctly separated.
- Volume accuracy is good where the geometry is recognised at all: 0.000 %,
  0.18 %, −0.55 %, +0.90 %.
- The pipeline is the right one (Benkő/Martin/Várady), on the right kernel, in
  the right process, feeding a feature tree that already exists.

The defects in §4 are not architectural. They are **one missing call**, **one
missing bound**, **one missing gate**, **one missing stage**, and **one missing
capability** — in that order of cost.

---

## 8. What to decide

1. Approve the definition of "certified" in §5. If that is not the bar, the rest
   of the plan is measuring the wrong thing.
2. Approve **validity before recognition** (§6.1) — Phase 2 before Phase 3 —
   even though Phase 3 is the one that makes the pictures look better.
3. Approve the component policy question in Phase 1.7 being **asked of the user**
   rather than guessed.
4. Confirm the target: is the deliverable a certified B-Rep (Phase 2, ~4 months)
   or an editable feature tree (Phase 4, ~11 months)? Both are defensible. The
   request in this conversation is Phase 4.

---

## 9. What was built

Phases 0–2 of §6, against the corpus in §2. Every number below is from
`occt_mesh_cli` and `occt_cad_audit` on this machine, at default parameters.

### 9.1 The reference part, which is the whole argument

80 triangles, a 13-segment profile extruded 50 mm, ground truth of 15 faces
known exactly from the STEP file it was tessellated from.

| | before | after | ground truth |
|---|---|---|---|
| faces | 19 | **15** | **15** |
| surface mix | 18 planes + 1 cylinder | **14 planes + 1 cylinder** | **14 + 1** |
| `BRepCheck` valid | **0** | **1** | 1 |
| self-intersections | **6** | **0** | 0 |
| G0 max gap | **2.159 mm** | **8.8 × 10⁻⁶ mm** | 0 |
| volume error | 0.337 % | **3.2 × 10⁻⁵ %** | 0 |
| cylinder U span | **123.6902°** | **90.0001°** | **90.0000°** |
| bbox / mesh | 1.1146 | **1.0001** | 1.0 |
| verdict | NOT CLEAN | **CLEAN** | — |

### 9.2 The bug, which was not the one §4.2 named

§4.2 called the over-wrapped cylinder a trimming failure, on the evidence that
the mesh's own triangles span 89.9997° and the face spans 123.6902°. That was
half right — the face is wrong — and wrong about the cause, which the fix had
to find before it could work.

The cylinder's patch holds **nineteen triangles: eighteen on the barrel and one
reaching 18.03 mm from a 15 mm axis.** Three millimetres off a surface fitted to
0.19, in a patch whose recorded `rms` is 0.000000 — because the fit was made
before that triangle arrived. `MeasureUv` then projects every vertex of the
patch onto the surface to find how far it reaches, the stray's vertices land far
round the barrel, and the extent it reports is 123.6902°. **The face is built
faithfully on a patch that is wrong.** Segmentation, not trimming.

The invariant nobody was enforcing: *every triangle in a patch lies on that
patch's surface*. `TrimStrays` exists but only inspects patches whose recorded
fit is poor, and this one's is perfect.

### 9.3 The four changes

**`EvictOffSurface`** releases a triangle that is grossly off its patch's
surface into a faceted patch of its own. Placed after `AbsorbStrays`, which is
the last thing that moves a triangle into a patch and is exactly how the stray
arrived. Two bounds, both learned by measurement:

- **Four times the tolerance, not one.** A triangle a little over is a boundary
  facet the fit did not quite reach, and evicting it cuts a notch the
  neighbouring wires cannot follow. Measured: evicting four such on the
  butterfly took the shell from closed to **sixteen free edges**. The reference
  part's stray is sixteen times over.
- **A quarter of the patch at most.** If a third of a patch is off its surface,
  the surface is what is in doubt.

**The same-surface merge now runs on the fit path.** It only ever ran on the
faceted one. Kept only if the body is no worse for it — on the TOKA base
unifying leaves a `SelfIntersectingWire` behind, and that is now refused rather
than shipped.

**The body is certified.** `BRepCheck` with geometric controls, `BOPAlgo_CheckerSI`,
and the bounding box against the mesh's, recorded in `Report` and out through
the C ABI as `OCCT_MR_VALID`, `OCCT_MR_SELF_INTERSECTIONS`, `OCCT_MR_MERGED_FACES`,
`OCCT_MR_BBOX_RATIO`. Closure was never the whole verdict: every model in §3 that
came back broken reported `closed=1`. Where self-intersections remain,
`ShapeFix_FixSmallFace` is tried at the build tolerance and kept only while it
reduces them — that is what takes the TOKA base from 13 to 1.

**`RepairMesh`** runs between `BuildMesh` and `BuildAdjacency`: duplicate faces
removed (a pair of *opposite* winding takes both sides — a zero-thickness sheet
encloses nothing), non-manifold fans cut into sheets by duplicating the vertices
along the edge and pairing by dihedral agreement, boundary loops filled from
their own centroid up to a quarter of the total boundary. Every repair counted
into the report, so a caller can say the file was mended rather than silently
converting something else.

### 9.4 Two things that were tried and are wrong

Recorded because both looked obviously right and the measurement said otherwise.

**Rebuilding an over-wrapping face on its patch's parameter rectangle.** The
replacement is trimmed by the rectangle instead of by the wires its neighbours
were built against, so the shared edges stop being shared. On the butterfly it
turned one refused cone into a built one and opened the shell. The overrun check
now *refuses*; with the eviction upstream it fires on nothing in the corpus,
and stays as the check that says so.

**Budgeting the self-intersection check by face count alone.** `CheckerSI` has
closed forms for planes and quadrics and none for trimmed B-splines. The whale
is 192 faces after the merge — well inside a 600-face budget — and 87 of them
are freeform: checking it cost **six and a half minutes** against a 25-second
conversion. There is now a second budget of 16 freeform faces. A body that is
not checked reports **−1, never 0**.

### 9.5 The corpus, before and after

| model | faces | valid | self-int | free edges | time | verdict |
|---|---|---|---|---|---|---|
| `Part9` | 7 → **7** | 1 → 1 | 0 → **0** | 0 → 0 | 2 → 8 ms | **CLEAN** |
| reference part | 19 → **15** | **0 → 1** | **6 → 0** | 0 → 0 | 42 → 58 ms | **CLEAN** |
| `TreeOfLife` | 117 → **93** | 1 → 1 | 0 → **0** | 0 → 0 | 71 → 250 ms | **CLEAN** |
| `TOKA_Base` | 48 → **41** | 1 → 1 | **13 → 1** | 0 → 0 | 2.7 → 3.2 s | not clean |
| `Schmetterling` | 2403 → **1416** | **0 → 1** | 235 → 162 | **1 → 0** | 21.9 → 27.3 s | not clean |
| `whale` | 286 → **196** | 1 → 1 | 151 → *n/m* | 0 → 0 | 25.2 → 25.5 s | not measured |

**Three of six certify clean, against one before.** The two that do not are
improved on every axis and are honest about it. No model regressed, and no model
costs materially more time.

### 9.6 The Bunny, which is repaired but still does not close

The file the repair stage was written for. Measured end to end, at default
parameters:

| | baseline | after repair |
|---|---|---|
| non-manifold edges entering segmentation | **465** | **3** |
| inconsistently wound triangles | **6 935** | **111** |
| boundary edges | 64 | 70 |
| shells / solids out | 536 / 77 | **49 / 39** |
| free edges in the result | 421 | **321** |
| edges on more than two faces in the result | 465 | **14** |
| closed | 0 | **0** |
| time | 938 s | 862 s |

**Non-manifold edges are down 99.4 % and inconsistent winding 98.4 %**, and the
mesh handed to the segmentation is very nearly a manifold. The order is what
did it: removing the 264 zero-thickness sheets *first* takes the non-manifold
count from 442 to 19 on its own, because those sheets were what made most of
those edges non-manifold. Confirmed twice — once by the shim, once
independently in NumPy against the raw STL.

**It still does not close**, and the reason is the 70 boundary edges that
survive. `FillHoles` traces 61 loops and fills them, and the greedy walk it
uses fails on boundary vertices where several loops meet — which is exactly
what cutting 45 non-manifold fans produces. A proper loop extraction (sort the
boundary half-edges around each vertex and walk them as a permutation, rather
than taking the first unused successor) is the fix, and it is not written.

**And it still takes fourteen minutes**, which is the Phase 6 problem and
untouched. This is honest remaining work, not a claim.

### 9.7 What this does not do

- **TOKA_Base still has one self-intersection.** It is a genuinely mixed
  prismatic/freeform part and the remaining defect is a sliver at a boundary
  between recognised surfaces. That is Phase 3 (better segmentation), not
  Phase 2 healing.
- **The whale and the butterfly are not certified, only improved.** Both are
  past the freeform budget, so the check reports *not measured* rather than a
  number. Making organic bodies checkable at all is Phase 5.
- **Nothing here is feature recovery.** `Part9` still converts into seven
  planar faces rather than `Sketch(5 lines) + Extrude(2.0)`. That is Phase 4 and
  it is untouched.
