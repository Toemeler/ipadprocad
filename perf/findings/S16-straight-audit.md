# S16 — what else in this shim is only ever exercised straight?

This session exists because of one sentence S14 wrote about its own work
(`S14-sweep.md` §14.3.6):

> Three defects in one operation, all invisible on a straight path. […] Every
> one of them is exact on a straight two-point path, which is what every test
> and every capture used. **I do not know what else in this shim is only ever
> exercised straight.**

This is that audit. It is not a sweep fix — the sweep belongs to S14 (done) and
S15 (`claude/perf-opt3-holes`, in flight). It is an attempt to answer the
generalisation for the whole C ABI, and the primary deliverable is **§1, the
inventory table**: for every entry point that takes a direction, an axis or a
placement, what value its fixtures have ever passed.

---

## 0. The hypothesis, stated so it can fail

Every one of S14's three defects has the same shape:

> a parameter carrying a **direction**, an **axis** or a **placement** was only
> ever exercised at its trivial value — axis-aligned, perpendicular, unrotated,
> identity — and the code is exact there and wrong away from it.

Two of the three shipped in v15 and survived nine months of tests and three
device captures. So the hypothesis is: **any shim entry point taking a
direction, axis or placement matrix is a candidate, and its fixtures are where
to look first.**

The hypothesis fails if the non-trivial fixtures all come back correct. That
is an acceptable and publishable result, and §1 is worth having either way.

---

## 1. THE INVENTORY

What `backend/occt/tests/smoke_occt.c` (scenarios [1]–[38]) has ever passed for
each direction / axis / placement parameter. Read from the source, call site by
call site, at `1b0675c`.

**Legend for "trivial?":** ✗ TRIVIAL = every fixture passes the degenerate
value (axis-aligned, identity, perpendicular). ~ PARTIAL = one component
varies, the direction does not. ✓ NON-TRIVIAL = at least one fixture bends it.

### 1.1 Ops that take a direction, axis or placement

| Op | Parameter | Fixtures | Values ever tested | Trivial? |
| --- | --- | --- | --- | --- |
| `occt_revolve_profile` | axis `(ax_px,ax_py)`+`(ax_dx,ax_dy)` | [20] ×5 | point **always (0,0)**, direction **always (0,1)**; one `(0,0)` degenerate-direction refusal | **✗ TRIVIAL** |
| `occt_coil_profile` | axis point + direction | [32] ×4 | point **always (0,0,0)**, direction **always (0,0,1)**; one `(0,0,0)` refusal | **✗ TRIVIAL** |
| `occt_coil_profile` | `clockwise` | [32] ×4 | **always 0** | **✗ TRIVIAL** |
| `occt_coil_profile` | `mat34` | [32] ×4 | one fixed XZ frame `{1,0,0,0, 0,0,-1,0, 0,1,0,0}` (a 90° rotation about X, exact 0/±1 entries) | ~ PARTIAL |
| `occt_loft_sections` | per-section `mats` | [31] ×3 | **identity rotation in every section**, translation `(0,0,0)` and `(0,0,25)` | **✗ TRIVIAL** |
| `occt_loft_sections` | `closed` | [31] ×3 | **always 0** | **✗ TRIVIAL** |
| `occt_loft_sections` | `ruled` | [31] ×3 | **always 1** | **✗ TRIVIAL** |
| `occt_mirror` | plane normal | [13b] ×4 | normal **always (1,0,0)**; one zero-normal refusal. Plane POINT varies: `(0,0,0)` and `(15,0,0)` | ~ PARTIAL — point yes, direction no |
| `occt_move_faces` | `(dx,dy,dz)` | [34] ×2 | **always (0,0,5)** — exactly along the selected face's outward normal; one NULL refusal | **✗ TRIVIAL** |
| `occt_transform` | `mat34` rotation | 16 sites | 12 pure translations; **one** rotation, `{0,-1,0, 1,0,0, 0,0,1}` = 90° about +Z, entries exactly 0/±1; three refusals (scale, mirror, shear) | **✗ TRIVIAL** — no rotation with irrational entries has ever reached `trsf_from_mat34` |
| `occt_scale_shape` | centre `(cx,cy,cz)` | [34] ×3 | `(10,10,10)` (the body's own centre) and `(0,0,0)`; factor 2 | ~ PARTIAL (no direction to bend; see §2) |
| `occt_fillet_edges` (+`_ex`) | edge frame | [21] [21c] [21d] [26] [29] [35] ×10 | **every fillet is on a 20-cube's vertical edge**: dihedral exactly 90°, tangent exactly ±Z, both faces axis-aligned planes | **✗ TRIVIAL** |
| `occt_chamfer_edges` | edge frame + ref face | [22] ×3 | same 20-cube vertical edge. Modes **0** and **2** only | **✗ TRIVIAL** |
| `occt_chamfer_edges` | `modes[i] == 1` (two distances) | — | **NEVER CALLED. `d2` is NULL at every call site in the suite.** | **✗ UNTESTED** |
| `occt_chamfer_edges_ex` | `out_dropped` / `out_scale` | — | **NEVER CALLED DIRECTLY** (only via the plain form, which passes NULL for both) | **✗ UNTESTED** |
| `occt_fuse` / `occt_cut` / `occt_common` | relative placement of operands | [4] [13b] [17] [18] [34] [36] ×13 | every operand pair is separated by an **axis-aligned translation only** (`{5,0,0}`, `{5,5,-5}`, `{10,10,10}`, `{100,0,0}`, …). **No boolean in the suite has ever had a rotated operand.** | **✗ TRIVIAL** |
| `occt_sweep_profile` (+`_ex`) | path, `mat34`, `orientation` | [30] [37] [38] ×24 | **S14's territory — audited there, and S15 owns it now. Excluded, see §2.** | (done elsewhere) |

### 1.2 Ops excluded, with the reason

| Op | Why it is not a candidate |
| --- | --- |
| `occt_extrude_profile`, `_arcs`, `occt_extrude_polygon` | **No direction parameter exists.** The header fixes extrusion along +Z from z=0 by contract; a feature on an angled plane is extruded in its sketch-local frame and then placed with `occt_transform`. There is no trivial value to bend because there is no value. The composition risk lives in `occt_transform`, which IS audited (§1.1). `taper_deg` is an angle, not a direction, and [9]/[10] already exercise it non-zero in both signs. |
| `occt_scale_shape` | Takes a POINT and a scalar, not a direction. A uniform scale has no axis to be wrong about, and the fixture already uses a non-origin centre. Kept in §1.1 for completeness, not predicted against. |
| `occt_fuse` / `occt_cut` / `occt_common` | Candidates on the letter of the hypothesis (§1.1 records the gap honestly) but **weak on its mechanism**: these are three-line wrappers over `BRepAlgoAPI_*`, and the shim composes no frame of its own. The defect class S14 found is "the shim builds a frame in one place and not another"; there is no frame here to build. Predicted-correct and tested as such (P7), not predicted-defective. |
| `occt_sweep_profile` / `_ex` | S14 bent this path on purpose and found three defects; S15 is working on `finish_pipe` and holed sweeps on `claude/perf-opt3-holes` **right now**. Re-auditing it would collide. Anything this audit turns up in the sweep path is written to `CROSS-SESSION.md` for S15, not fixed here. |
| `occt_mesh_*`, `occt_shape_edge*`, `occt_ray_hits`, `occt_revolve_hits*`, STEP, `occt_brep_from_mesh` | Queries and converters, not placements. `occt_ray_hits` does take a direction — but [23] and [24] already cast rays along several directions, and it reads geometry rather than composing a frame. |

### 1.3 What the table says, before any measurement

**Eight parameters have never been anything but trivial**, and three of those
are reachable from the UI with a value the suite has never produced:

* the **revolve axis** — `RevolveFeature.axPx/axPy/axDx/axDy` are user-picked
  in sketch coordinates (`part_model.dart:2582`), default `(0,0)`+`(0,1)`,
  which is exactly and only what [20] tests;
* the **coil axis and `clockwise`** — `CoilFeature` (`part_model.dart:2892`)
  has the same user-picked axis, and `coilClockwise` is a checkbox
  (`app_state.dart:7277` → `part_model.dart:7947`) that **no test has ever
  set to true**;
* the **loft section placements** — `frame.mat34(0)` per section, i.e. a real
  rotation as soon as two sections are on different work planes, where the
  fixture only ever passes identity.

That is the map. §4 is what I think it means; §5 is what happened when I bent
each one.

---

## 2. The instrument, and why it is not a golden

`OPTIMIZATION_PLAN_2.md` §1.4 forbids recorded goldens, and S14 §2.8 showed
that volume alone is not a discriminating invariant for a sweep. So this audit
uses three instruments, in order of strength:

**(a) Analytic pins.** A prism is area × rise; a full revolve obeys **Pappus's
theorem**, `V = 2π · d(centroid, axis) · A`, *for any axis in the profile
plane* — which is precisely a formula that stays exact as the axis is bent, and
therefore the right pin for a revolve audit.

**(b) Rigid equivariance — the instrument this audit turns on.** For every op
that takes a direction, axis or placement, applying one rigid motion `R` to
*all* of its geometric inputs must yield exactly `R` applied to its output:

```
    op(R · inputs)  ≡  R · op(inputs)
```

Volume is invariant under `R`, so **volume equality under a global rotation is
a necessary condition that needs no closed form for the shape at all.** It
therefore works where no analytic volume exists — a lofted frustum, a tapered
coil, a filleted corner — and it fails *precisely* when the code has an axis
baked in that the caller thinks is a parameter. It is differential (both sides
in one run on one machine), which is what §1.4 requires.

**(c) `BRepCheck_Analyzer`.** S14 found a solid that was 10.6 % too large AND
invalid, silently. Every new fixture asserts validity, not just volume.

---

## 3. PRE-REGISTRATION

Written and committed **before** the fixtures exist. Each prediction names the
mechanism from source, not a hunch.

### P1 — the coil's `clockwise` flag does not reverse the handedness; it makes the coil descend. **DEFECT.**

`occt_capi.cpp` builds the helix as a straight line in the cylinder's `(u,v)`
parameter space, `u` winding and `v` climbing:

```c
const double slope = height / turns;
const gp_Dir2d d2(clockwise != 0 ? -1.0 : 1.0,
                  clockwise != 0 ? -slope : slope);
```

`clockwise` negates **both** components. The point set of `{(-t, -t·slope)}`
for `t ∈ [0, plen]` is the same helix as `{(s, s·slope)}` for `s ∈ [-plen, 0]`
— **the same right-handed helix, run backwards and downwards.** A left-handed
helix needs the components to have *opposite* signs, `(-1, +slope)`.

**Prediction.** A coil with `clockwise = 1`, revolutions 5, height 50, on the
[32] fixture, comes back with its material at **z ∈ [-50, 0]** rather than
`z ∈ [0, 50]`, and has the **same handedness** as the `clockwise = 0` coil.
Volume will NOT discriminate (same helix length, `4 × 628.71 = 2514.8` either
way) — the bounding box will. Inventor's Rotation flag flips the winding while
the coil still rises, so this is a wrong part, not a cosmetic miss.

**Falsified if** `clockwise = 1` gives `z ∈ [0, 50]`, or if the two coils are
mirror images rather than the same curve traversed oppositely.

### P2 — the coil is otherwise CORRECT on an oblique axis. **NO DEFECT.**

The frame is built from the arguments, not from `+Z`:

```c
const gp_Dir adir(axis);
const gp_Pnt foot = apt.Translated(gp_Vec(adir) * w.Dot(gp_Vec(adir)));
const gp_Ax3 frame(foot, adir, gp_Dir(gp_Vec(foot, c)));
```

`adir` is the caller's direction, `foot` the true perpendicular foot of the
centroid, and the reference direction is the true radius vector. Nothing
here degenerates when the axis leaves `+Z`.

**Prediction.** Coil the [32] fixture about an axis rotated 35° about X
through a non-origin point, with the profile frame rotated by the *same*
rigid motion, and the volume matches the `+Z` coil to **1e-9 relative**
(equivariance, §2b) and `BRepCheck_Analyzer` passes.

**Falsified if** the volumes differ by more than 1e-9 relative, or the oblique
coil is invalid or NULL.

### P3 — the revolve is CORRECT on an oblique, off-origin axis. **NO DEFECT.**

`axis_side()` is a genuine 2D cross product, `dx·(y−py) − dy·(x−px)`, general
in both point and direction; the guard tolerance scales with the profile
(`1e-7 · (scale + 1)`), and the *same* `gp_Ax1` is used for the body and for
every hole. There is no second frame to disagree with the first — which is
exactly the defect shape S14 found in the holed sweep, and it is absent here.

**Prediction.** A 360° revolve of the [20] rectangle about an axis through
`(-4, 1)` along `(3, 4)/5` returns **Pappus's volume**,
`V = 2π · d · A` where `d` is the perpendicular distance from the rectangle's
centroid `(7.5, 1.5)` to that axis and `A = 15`, to 1e-6 relative; the solid
is valid; and the same profile+axis pair rotated bodily in the sketch plane
gives the identical volume.

**Falsified if** the volume misses Pappus by more than 1e-6 relative, or the
oblique revolve fails or comes back invalid.

### P4 — the revolve's HOLE is placed against the same axis as its body. **NO DEFECT — the control for S14's item 2.**

S14 item 2 was "a hole placed against a different frame from its body". The
revolve is the other op in the shim that cuts holes as separate solids, so it
is the natural place for the same defect to hide. It does not: `axis` is one
`const gp_Ax1` computed before the loop and used unchanged by
`BRepPrimAPI_MakeRevol` for the outer face and for every hole.

**Prediction.** A rectangle with a rectangular hole, revolved 360° about an
oblique axis, has volume `2π · (d_outer · A_outer − d_hole · A_hole)` by
Pappus applied twice, to 1e-6 relative, and is valid.

**Falsified if** the hole lands anywhere but concentric with the body — which
Pappus would catch as a volume miss.

### P5 — `occt_transform` ACCEPTS a real rotation with irrational entries. **NO DEFECT.**

`trsf_from_mat34` checks column orthonormality and `det` against an **absolute
`tol = 1e-9`**. A rotation matrix assembled in IEEE double from `sin`/`cos`
carries orthonormality error of order 1e-16, and a few compositions keep it
below 1e-15 — six orders of headroom. The fixture's only rotation has entries
exactly `0`/`±1`, so this tolerance **has never been tested against a matrix
that is merely nearly orthonormal**, which is the whole population the app
actually sends.

**Prediction.** A 37° rotation about the normalised axis `(1,2,3)/√14`,
composed in double precision, is accepted; volume is invariant to 1e-12
relative; and the round trip `R⁻¹(R(box))` returns the box's bbox to 1e-9.
I expect the measured orthonormality residual to be below **1e-15**, i.e.
1e6× inside the guard.

**Falsified if** the rotation is refused, or the residual exceeds 1e-12
(which would mean the guard has far less headroom than claimed and a longer
composition chain in Dart could trip it).

### P6 — `occt_mirror` is CORRECT about an oblique plane. **NO DEFECT.**

The normal is normalised from the arguments and handed straight to
`gp_Trsf::SetMirror(gp_Ax2)`; the orientation repair measures the volume and
reverses on negative, which is direction-agnostic.

**Prediction.** A 10×20×30 box mirrored about the plane through `(0,0,0)` with
normal `(1,1,0)/√2` has volume 6000 to 1e-9, is valid, and **fuses with the
original to a strictly larger volume** — the fuse being the real test, because
that is what the orientation repair exists for and a silently inside-out mirror
passes a volume check and fails a boolean. The un-normalised normal `(3,3,0)`
must give the identical solid.

**Falsified if** the fuse fails, or the mirrored solid is invalid, or the
normalisation is not scale-invariant.

### P7 — booleans are CORRECT with a rotated operand. **NO DEFECT.**

Three-line wrappers over `BRepAlgoAPI_*`; the shim composes no frame.

**Prediction.** Cutting a 6×6×40 bar, rotated 30° about Z and placed obliquely,
out of a 20-cube gives a volume that agrees with the same cut performed in a
globally rotated frame to 1e-6 relative (equivariance, §2b), and the result is
valid. This is the honest "checked and it is fine" entry the table needs.

**Falsified if** the two disagree by more than 1e-6 relative.

### P8 — `occt_loft_sections` is CORRECT with rotated section placements. **NO DEFECT.**

Each section gets its own `trsf_from_mat34` and `BRepBuilderAPI_Transform`;
nothing assumes the sections are parallel or that their normals point along
`+Z`.

**Prediction.** The [31] two-square loft, with the identical rigid motion `R`
(37° about `(1,2,3)/√14`, plus a translation) applied to **both** section
matrices, has volume 2500 to 1e-9 relative and is valid. Additionally a loft
whose second section is *tilted* 20° about X relative to the first builds, is
valid, and has volume strictly between the untilted prism and its own
bounding slab — a weaker claim, made because no closed form exists there and I
would rather register a weak true claim than a strong invented one.

**Falsified if** the equivariant loft's volume moves at all.

### P9 — `occt_move_faces` on an OBLIQUE delta returns a solid that is not the moved face. **DEFECT, of a documented-but-unenforced kind.**

The implementation sweeps the face along the *whole* delta and fuses:

```c
BRepPrimAPI_MakePrism prism(f, delta);
const double along = delta.Dot(gp_Vec(outward));
... along > 0 ? Fuse(acc, tool) : Cut(acc, tool)
```

When `delta` is parallel to the outward normal, the prism is the slab between
the old and new face and the fuse is exact. When `delta` is **oblique**, the
prism *leans*: the union carries an **unsupported overhang** on one side and
leaves a **re-entrant notch** on the other, instead of the neighbouring walls
following the face. The header scopes the guarantee — "exact whenever the
neighbouring walls are parallel to the motion" — but nothing **enforces** it,
and an oblique delta returns a plausible, valid, positive-volume solid.

**Volume will not catch this.** A leaning prism has volume `A · |delta·n|`,
identical to the perpendicular move, and shearing the top face is Cavalieri-
neutral — so both readings give 10 000 on a 20-cube. **The discriminator is a
ray cast.** Move the top face of a 20-cube by `(5,0,5)`; a ray up the line
`x = 2, y = 10`:

* if the walls followed the face (the moved-face reading), the solid's top at
  `x = 2` is at **z ≈ 10**;
* if the shim unions a leaning prism, material continues to
  `z = 20 + 5·(2/5) =` **22**.

**Prediction.** `occt_ray_hits` reports the exit at ≈22, not ≈10; the solid is
nevertheless *valid* and its volume is 10 000 — i.e. this is invisible to
every instrument the suite currently owns. I predict the volume lands within
1e-6 of 10 000 and the exit within 1e-6 of 22.0.

**Falsified if** the exit is at ≈10 (the walls do follow), or the call is
refused, or the volume is not 10 000.

**Note on severity, registered now so it cannot be inflated later:** I have not
yet established that the app ever *sends* an oblique delta. If `part_model.dart`
only ever moves a face along its own normal, this is a latent gap in an
undocumented corner, not a live defect, and I will say so in exactly those
words.

### P10 — the chamfer's `angle_deg >= 90` refusal assumes a perpendicular edge. **DEFECT (a guard, not the geometry).**

```c
if (modes[i] == 2 && (!angle_deg || !(angle_deg[i] > 0.0) || angle_deg[i] >= 90.0))
```

The angle is measured **from the reference face**, and the legal range depends
on the edge's own dihedral, which for every fixture is exactly 90°. On an
obtuse edge — say the 135° edge of a chamfered corner — an angle at or above
90° is geometrically constructible and OCCT will build it, and the shim refuses
it categorically.

**Prediction.** On a 20-cube first chamfered at 45° (producing 135° edges), a
mode-2 chamfer of `d1 = 2`, `angle = 100°` on one of those edges is **refused
by the shim**, and the same cut expressed as mode 1 (two distances,
`d2 = d1·tan(100°)`… i.e. the equivalent asymmetric pair) **builds**. That
asymmetry is the finding: two spellings of one chamfer, one refused.

**Falsified if** OCCT itself refuses the mode-1 equivalent, in which case the
shim's guard is defensible and I will record it as correct.

**Registered caveat:** P10 is the prediction I am least sure of, because I have
not read `ChFi3d`'s own admissible range. If the mode-1 form also fails, the
honest answer is "the guard is conservative but not demonstrably wrong", and
that is what I will write.

#### P10 restated — the claim stands, the witness was wrong

*Written while building the fixture, before running it. The original text above
is left exactly as committed at `ed46cc6`; this is what changed and why.*

I worked out the admissible range instead of guessing it. In the cross-section
triangle — apex `O` on the edge, tangent point `A` on the reference face,
tangent point `B` on the other — the interior dihedral is the angle at `O`, and
the chamfer angle `α` (OCCT's `AddDA`, measured from the reference face) is the
angle at `A`. The three angles sum to 180°, so

```
    α  <  180° − θ
```

which is `α < 90°` **if and only if θ = 90°.** The guard is not merely tuned to
a perpendicular edge; it is the *exactly correct* rule for one, and wrong in
**both directions** away from it:

* on an **obtuse** edge (θ = 135°) the legal range is `α < 45°`, so the guard is
  too **permissive** — it accepts 60°, which is geometrically impossible, and
  the user gets OCCT's failure instead of the guard's clear message;
* on an **acute** edge (θ = 60°) the legal range is `α < 120°`, so the guard is
  too **strict** — it refuses 100°, which builds perfectly well.

My registered witness was a 135° edge, which demonstrates the *permissive*
half, not the *strict* half I claimed. **The claim — "the guard assumes a
perpendicular edge and refuses legal input away from it" — is unchanged; the
fixture that demonstrates it is not.** [39j] now uses an **equilateral
triangular prism** (θ = 60° at every vertical edge) and asks for α = 100°,
with two controls: α = 80° on the same edge must build (so the refusal is the
guard and not the geometry), and the *same chamfer* spelled as mode 1 with
`d2 = d1·sin(100°)/sin(20°) = 5.758770` must build and remove
`½·d1·d2·sin 60° · 20 = 99.7446`.

**P10 is falsified if** the mode-1 spelling is also refused — then OCCT itself
will not build that chamfer, the guard costs nothing, and I will say the guard
is conservative but not demonstrably wrong.

**A trap worth recording on its own**, because it is what sent me back to the
arithmetic: `occt_shape_edge_info` field [10] is `acos(n1 · n2)`, the angle
between the two **outward normals**, not the interior dihedral. They coincide
at a cube edge — 90 either way — which is why every fixture in the file reads
naturally and why the distinction has never mattered. Away from 90 they are
supplements: `θ = 180° − info[10]`. A 135° edge reports **45**. The header says
"90 = square corner" and is not wrong, but it is the one reading that cannot
tell you which convention it is.

### P11 — the fillet is CORRECT away from a 90° edge. **NO DEFECT.**

Nothing in `blend_edges_subset` composes a frame; edges are selected by index
and handed to `BRepFilletAPI`.

**Prediction.** A fillet of r = 2 on a 135° edge (a 20-cube chamfered at 45°,
then rounded) builds, is valid, and removes a volume equal to the analytic
corner-round of a 135° dihedral: for a dihedral θ, a constant-radius round of
radius r removes, per unit length, `r²·(cot(θ/2) − (π−θ)/2)`. For θ = 135° =
3π/4 and r = 2: `4·(cot(67.5°) − π/8) = 4·(0.414214 − 0.392699) = 0.086058`
per unit length. The edge is the chamfer's own 45° face edge on a 20-cube
chamfered at d = 4, of length 20, so the predicted removal is
**1.72116**, to **1e-6 relative**.

The tolerance is tight on purpose. The edge runs the full height of the cube,
so the fillet is a genuine prism with no run-out at either end — which is
exactly why [21]'s 90° version holds to 1e-6, and there is no reason a 135°
edge should be looser. Registering 1e-3 here "to be safe" would make the
prediction unfalsifiable, which is the failure mode `OPTIMIZATION_PLAN.md` §2
is written against.

**Falsified if** the fillet fails on a non-90° edge, or the removal misses
1.72116 by more than 1e-6 relative.

### P12 — chamfer mode 1 (two distances) works and is not symmetric. **NO DEFECT, but it is untested surface.**

Mode 1 has **no fixture anywhere in the suite** and `d2` is NULL at every call
site.

**Prediction.** On the 20-cube's vertical edge, mode 1 with `d1 = 4, d2 = 2`
removes `½·4·2·20 = 80`, i.e. volume 7920, to 1e-9. Swapping to `d1 = 2,
d2 = 4` removes the same 80.

**Volume therefore cannot tell the two apart, and neither can the bbox of the
result** — a chamfer cuts a corner off, so the solid still spans [0,20]³ either
way. The discriminator is the bbox of the **cut-away wedge**,
`occt_cut(box, chamfered)`: its three extents are `{d1, d2, 20}` with `d1` and
`d2` on the two axes normal to the two chamfered faces. Swapping the distances
**transposes** those two extents. This needs no knowledge of which face OCCT's
ancestor map picked as the reference, which is the point — the reference face
is deterministic but opaque, and a test that had to name it would be pinning
OCCT's map order rather than the shim's behaviour.

**Prediction, precisely:** both wedges have sorted extents `{2, 4, 20}` to
1e-9, both results are valid, and the two unsorted extent triples are **not**
equal.

**Falsified if** the two orderings give identical unsorted extents (the
distances are being averaged, symmetrised or silently swapped), or either
call fails.

---

## 4. What I will do with a defect

`OPTIMIZATION_PLAN_2.md` §0.6 and the brief both bind: **record it, finish the
sweep, decide afterwards.** An audit that turns into a bug-fix on the third
entry point stops being an audit. Anything in the sweep path goes to
`CROSS-SESSION.md` for S15, not into `occt_capi.cpp` here.

---

*§5 onward — results — is written after the fixtures run. Nothing below this
line existed when the predictions above were committed.*
