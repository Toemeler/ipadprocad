# S20 — the same question, asked of the Dart feature layer

S16 asked one question of the C ABI:

> has this parameter ever been passed anything but its **trivial value** —
> axis-aligned, perpendicular, unrotated, identity?

Eight parameters had not. Three of the eight were wrong away from it, and S17
repaired all three in shim v28. Nobody has asked it of the layer above, which
is where the values come from. This session asks it of `frontend/lib`, and
carries S17's one routed Dart finding (`S17-oblique.md` §5.1) from "known, not
fixed here" to fixed.

**Scope.** The audit reads the whole feature layer. The **fixes** are confined
to the chamfer path — `ChamferFeature`, `PartKernel.chamferEdges`,
`OcctPartKernel.chamferEdges` and the two call sites in `part_model.dart` —
which is what this session owns. Everything the audit turns up outside that is
recorded here and routed, never patched, which is S16's rule and the reason its
inventory is still worth reading.

**Not touched, deliberately:** `backend/occt/shim/**` (no shim version is taken
— this session adds no C ABI surface), `backend/occt/tests/smoke_occt.c` (no
scenario number is claimed), `frontend/lib/ffi/occt_engine.dart`,
`frontend/lib/perf*.dart`, `perf/baseline.json`, `PERFORMANCE_PROFILE.md`.

---

## 0. MECHANISM, from source, before any fix

### 0.1 The chamfer triangle, and which angle is which

`occt_capi.cpp` (S17's note above `edge_chamfer_angle_limit`) states OCCT's own
arithmetic for a distance-and-angle chamfer:

```
    dis2 = d1 . sin(alpha) / sin(alpha + theta)
```

with `alpha` the angle at the reference face and `theta` the interior dihedral
— the angle the **material** makes at the edge. The chamfer plane, the two
adjacent faces and the edge bound a triangle: apex `theta` at the edge,
`alpha` where the chamfer meets the reference face, and the third angle

```
    beta = 180 - theta - alpha
```

`dis2` is then nothing but the law of sines, `dis2 / sin(alpha) = d1 / sin(beta)`,
since `sin(alpha + theta) = sin(180 - beta) = sin(beta)`.

Two numbers in this file are easy to confuse and the whole session turns on
telling them apart. `occt_shape_edge_info` field **[10]** — `OcctEdgeInfo.dihedralDeg`
in Dart — is `acos(n1 . n2)` between the two **OUTWARD** normals
(`occt_capi.cpp`, `edge_info_one`). That is the *exterior* turn, so

```
    D := dihedralDeg = 180 - theta        theta = 180 - D
```

and both are 90 on a square edge, which is why nothing here has ever had to
distinguish them. Rewriting the triangle in terms of D:

```
    beta = 180 - theta - alpha = D - alpha
```

and D is also, since shim v28, *exactly* the admissible bound: `0 < alpha < D`
(`occt_capi.h` at `occt_chamfer_edges`, and `edge_chamfer_angle_limit` computes
the limit from the same helper at the same arc-length midpoint as field [10],
so the two are the same number by construction).

### 0.2 What the shim will and will not let a caller say

`occt_chamfer_edges` has **no reference-face parameter**. The header:

> The reference face is the FIRST face adjacent to the edge in OCCT's ancestor
> map — deterministic for a given shape, and what Dart's "Flip" toggle swaps by
> exchanging d1/d2 (mode 1) or sending 90-angle (mode 2).

So Dart cannot swap which face the kernel measures from. It can only
**re-express the chamfer it wants in terms of the fixed reference face.** That
constraint is what makes Flip arithmetic rather than a boolean pass-through,
and it is the mechanism behind both defects below.

### 0.3 The two readings of Flip, six lines apart in one class

`part_model.dart` says both of these about the same field:

```dart
  bool flip; // swaps which adjacent face distance1 is measured on      (3676)

  /// Distances as the shim wants them, with Flip already applied. Flip is a
  /// pure presentation swap for mode 1 and the complementary angle for
  /// mode 2, so the kernel never needs to know the toggle exists.       (3700)
```

They are different operations.

* **(A) Swap the faces.** The chamfer the user gets is the MIRROR of the one
  they had: the distances cut on the two faces exchange. This is what the field
  comment says, what the button says (`lblSwapFaces`, `edge_feature_dialog.dart:313`),
  what mode 1 already does — `(distance2, distance1, 0)` is exactly the mirror
  — and what Inventor's Distance-and-Angle chamfer does, since there you pick
  the face the distance is measured on and flipping picks the other one.
* **(B) Keep the distance where it is, measure the ANGLE from the other face.**
  This is what the getter comment says and what the code does.

Under (A) the mode-2 flip is a change of BOTH arguments; under (B) it is a
change of the angle alone. They agree only when the chamfer is symmetric —
`alpha = D/2`, which on a square edge is the panel's default 45 deg. **That
coincidence is why this survived.**

### 0.4 The line

`part_model.dart:3707`:

```dart
        2 => (distance1, 0.0, flip ? 90.0 - angleDeg : angleDeg),
```

`90 - angleDeg` is `D - angleDeg` if and only if D = 90. It is a hardcoded
perpendicular edge, and it is the identical defect to the one S17 repaired in
the shim's guard, one layer up — S17 found it while reading the reference-face
paragraph and routed it here.

A mechanical check says it is the **only** one of its kind in the Dart layer:
`grep -n '90\.0 -\|90 - \|180\.0 -\|180 - '` over `lib/*.dart`, `lib/ffi/*.dart`
and `lib/widgets/*.dart` returns exactly this line and one comment about
tessellation counts.

### 0.5 The crux the brief names, and how it is answered

`kernelParams` is a **getter**. It has no edge, and it returns one scalar
triple for the whole feature. A chamfer feature carries a `List<EdgeSel>` and
one feature may legitimately span edges that meet at different angles — a
chamfer around the top of a hexagonal boss, a fillet-and-chamfer pass on a
casting. `D` is per edge, so the flipped arguments are per edge, so **there is
no single right answer for the getter to return.** That is a design decision,
not a one-liner.

It is decided here in favour of making the value per edge, on three grounds:

1. **The binding underneath is already per edge.** `OcctShape.chamferEdges`
   (`ffi/occt_engine.dart:658`) takes `List<double> d1`, `d2` and `angleDeg`,
   one entry per edge, and has since v12. `OcctPartKernel.chamferEdges`
   (`part_model.dart:6707`) throws that away — `List<double>.filled(n, d1)` —
   to satisfy a scalar interface one level up. The per-edge path is not new
   surface; it is surface that was being discarded.
2. **The alternative is a refusal, and it refuses correct chamfers.** Keeping
   one scalar means either picking one edge's answer for all of them (silently
   wrong on the others — the failure mode this repo's own logging rules exist
   to prevent) or refusing any feature whose edges disagree, which would refuse
   chamfers that build perfectly well today.
3. **It costs one map.** `_recomputeBodyModify` already holds `live`, the
   `List<OcctEdgeInfo>` the ids were resolved against. The dihedral is field
   [10] of a record that has already been read.

The decision is registered **structurally**: the no-argument `kernelParams`
getter is removed rather than left with a defaulted 90. A getter that answers
without an edge is precisely the trap this session exists to close, and leaving
it available with a comment asking callers not to use it would be an advisory
where a compile error is available.

---

## 1. THE INVENTORY

Every parameter of the Dart **feature layer** that carries a direction, an
axis, a placement, an angle or a handedness, and what the Dart suite has ever
passed it. Read call site by call site at `0e67671`.

**Legend.** ✗ TRIVIAL = every test passes the degenerate value. ~ PARTIAL =
one component varies, the direction does not. ✓ NON-TRIVIAL = at least one test
bends it. ∅ INERT = nothing downstream reads it.

| Feature | Parameter | Where the tests exercise it | Values ever passed | Trivial? |
| --- | --- | --- | --- | --- |
| `ChamferFeature` | mode-2 `angleDeg` + `flip` | `m131:180`, `m136:144` | `angleDeg` 30, `flip` both ways, **and the edge is always square** — every `OcctEdgeInfo` in every fake has `dihedralDeg = 90` (`m136:36`, `m182:70`) | **✗ TRIVIAL — DEFECT, §3 P1/P2** |
| `ChamferFeature` | `edgeChain` | `m136:85` | **always `true`**, and **nothing reads it**: no compute path, and `setEdgeFeature(edgeChain:)` has no caller in any widget | **∅ INERT, §3 P5** |
| `FilletFeature` | `allFillets` / `allRounds` | `m136` | recorded, not read at build: `app_state.dart:11807` materialises the selection into `pickedEdges` when the button is pressed | n/a — a record of a press, correctly | 
| `DirectEditFeature` | `dx, dy, dz` | `m217:201` | tests pass a free `dz`; **the shipping app passes (0,0,0)** — `setFaceEditValue` (`app_state.dart:6383`) has no caller anywhere in `frontend/` | **✗ TRIVIAL in the app, §3 P6** |
| `DirectEditFeature` | `factor` | `m217` | same: `FaceEditSession.factor` starts at 1 and nothing sets it | **✗ TRIVIAL in the app, §3 P6** |
| `RevolveFeature` | axis point + direction | `m137:132`, `m137:427` | point `(5,10)`, direction `(0,-10)` — off-origin AND reversed | ✓ NON-TRIVIAL |
| `RevolveFeature` | `direction` → `startOffsetDeg` | `m131:126–157` | all four modes, offsets 0, −90, −45, −30 | ✓ NON-TRIVIAL |
| `RevolveFeature` | mirrored-occurrence axis (`axPy`/`axDy` override) | `m212` | the mirror-in-v path exists and is exercised | ✓ NON-TRIVIAL |
| `CoilFeature` | axis point + direction | `m131b:311` | `(30,0)→(30,40)`, asserted in WORLD space | ✓ NON-TRIVIAL |
| `CoilFeature` | `clockwise` | `m131b:321` | **`true` asserted through to the kernel** | ✓ NON-TRIVIAL |
| `CoilFeature` | `taperDeg` | `m131b:346` (round trip only) | 0 in every compute test | **✗ TRIVIAL, §3 P7** |
| `SweepFeature` | `orientation`, `taperDeg` | `m131b:159` | orientation 2, taper 3 deg, asserted at the kernel | ✓ NON-TRIVIAL |
| `SweepFeature` | `twistDeg` | — | **0 in every test**, compute and round-trip alike | **✗ TRIVIAL, §3 P7** |
| `LoftFeature` | `ruled`, `closedLoop` | `m131b:232` | both `true`, asserted at the kernel | ✓ NON-TRIVIAL |
| `LoftFeature` | per-section frames (`frame.mat34(0)`) | `m131b` | sections on the same sketch plane; no test lofts across two differently-oriented planes | **✗ TRIVIAL, §3 P8** |
| `PatternFeature` | `dirA` / `dirB` direction | `m212:165,223,445,487` | **always a coordinate axis** `(1,0,0)`/`(0,1,0)`; the POINT varies (`(1,2,3)`) | **~ PARTIAL, §3 P8** |
| `PatternFeature` | circular `axis` | `m212:258,313,453,1056` | **always `(0,0,1)`**; point `(5,5,0)` and `(0,0,0)` | **~ PARTIAL, §3 P8** |
| `PatternFeature` | `mirrorPlane` normal | `m212:366,472,667…` | **always `(1,0,0)` or `(0,1,0)`** | **~ PARTIAL, §3 P8** |
| `PatternFeature` | `orientation` | `m212:262,456,970` | both `fixed` and `rotational` | ✓ NON-TRIVIAL |
| `HoleFeature` | `flip` | `m225:331` | both ways | ✓ NON-TRIVIAL |
| `HoleFeature` | `csAngle` | `m225:311,337,355` | **90 (twice) and 180 (a refusal)** — and 90 is the one value that cannot discriminate the formula, §3 P9 | **✗ TRIVIAL, §3 P9** |
| `SplitFeature` | `frame.n` + `flip` | `m228` | both flips; plane normals are the origin planes' | ~ PARTIAL |
| `ExtrudeFeature` | `direction` → `extrudeSpan` | `m131:113`, `m56` | all four modes | ✓ NON-TRIVIAL |
| `ExtrudeFeature` | `taperDeg` | `m56:632`, `m225` | 3 deg, ±45 deg via the countersink | ✓ NON-TRIVIAL |
| `PatternCompute.adjust` occurrence frame | `OccurrenceAt` | `m212` | **only `ExtrudeFeature` and `RevolveFeature` read it** — `_adjustedOccurrence` refuses the rest explicitly (`part_model.dart:8673`) rather than dropping it | n/a — guarded, §3 P10 |

### 1.1 What the table says before any measurement

**Six rows are trivial and one is inert.** The important structural difference
from S16's table is this: where S16 found the *shim* untested away from the
axis, most of the Dart rows come back **non-trivial** — `clockwise`, `ruled`,
`closedLoop`, sweep `orientation` and `taperDeg` are all asserted reaching the
kernel at a bent value in `m131b`. That is not a coincidence, and it is the
answer to a question S16 left open: those parameters were reachable from the UI
*because the Dart binding passes them faithfully*. The Dart layer was carrying
values the shim had never been given. S16's coil defect was a live bug for
exactly that reason.

So the hypothesis **fails** for most of this layer, which is a publishable
result and the one I expected least. Where it holds it holds hard: the chamfer.

---

## 2. The instrument

`OPTIMIZATION_PLAN_2.md` §1.4 forbids recorded goldens, and there is no OCCT
here to build against, so the instrument has to be a **law the code must obey,
checked against an independently derived reference in the same run**.

For the chamfer that law is available in closed form. From §0.1, a mode-2
chamfer with reference-face distance `d` and angle `alpha` on an edge of
exterior dihedral `D` cuts these two distances on the two faces:

```
    faces(d, alpha, D) = ( d ,  d * sin(alpha) / sin(D - alpha) )
```

That is OCCT's `dis2` formula, transcribed from the shim's own note and NOT
from the Dart code under test. Three properties follow, and each is a
differential assertion needing no recorded constant and no kernel:

* **(i) the swap.** `faces(flip(d, alpha), D)` must equal `faces(d, alpha, D)`
  reversed. This is what "swap which face distance1 is measured on" MEANS, and
  it is what discriminates reading (A) from reading (B).
* **(ii) the involution.** `flip(flip(x)) == x`, to floating point.
* **(iii) the guard.** `flip`'s angle lies in `(0, D)` exactly when the
  original does, so a flip never converts a chamfer the shim v28 guard accepts
  into one it refuses.

Property (i) fails for the current code on any `alpha != D/2`; (ii) passes for
the current code, so it is kept as a regression pin and not offered as
evidence.

The rest of the audit's instrument is the grep in §0.4 and the call-site
reading in §1 — for a layer with no kernel linked on the host, "what has ever
been passed" is answerable by reading and is not improved by guessing.

---

## 3. PRE-REGISTRATION

Written and committed **before** the first line of the fix. Each names its
mechanism from source.

### P1 — mode-2 Flip sends the wrong ANGLE on any edge that is not square. **DEFECT.**

`part_model.dart:3707` sends `90 - angleDeg`. §0.1 derives the flipped angle as
`D - angleDeg`. These differ by `90 - D`, which is zero only on a perpendicular
edge. Reachable in one tap: `edge_feature_dialog.dart:313`, and the panel shows
Flip for every mode but 0.

**Predicted consequence, before the fix.** On an edge whose faces meet at
`theta = 120` (so `D = 60`), a flipped 30 deg chamfer sends 60 deg, which is
past that edge's v28 bound of 60 and is **refused** — S17's improvement made
the bug loud. On `theta = 60` (`D = 120`), a flipped 30 deg sends 60 where the
answer is 90: the chamfer builds, and is wrong.

This is S17 §5.1, converted. I expect the fix to be `D - angleDeg` with the
shim's own fallback of 90 for an edge whose dihedral cannot be measured.

### P2 — mode-2 Flip does not swap the faces AT ALL, on any edge. **DEFECT, and it is not S17's.**

Under reading (A) — §0.3, the field's own comment, the button's label, mode 1's
behaviour, Inventor — flipping must produce the mirror chamfer, so the two face
distances exchange. Sending `(distance1, D - angleDeg)` keeps `distance1` on the
reference face and therefore does **not** exchange them. The correct
re-expression, from the law of sines in §0.1:

```
    d'     = distance1 * sin(angleDeg) / sin(D - angleDeg)
    angle' = D - angleDeg
```

**Prediction, arithmetic first.** Square edge, `distance1 = 2`, `angleDeg = 30`.
Unflipped cuts `(2.000, 2 sin30/sin60) = (2.000, 1.1547)`. The mirror is
`(1.1547, 2.000)`. Today's code sends `(2, 60)`, which cuts
`(2.000, 2 sin60/sin30) = (2.000, 3.4641)` — **not a mirror, and 3.46 mm off a
face the user asked to take 1.15 mm off.** The correction sends
`(2 sin30/sin60, 60) = (1.1547, 60)`, which cuts `(1.1547, 2.000)`. ✓

At the panel's default `angleDeg = 45` on a square edge, `d' = 2 tan45 = 2` and
`angle' = 45`: **the flip is exactly the identity, correctly, because a
symmetric chamfer is its own mirror.** That is why nobody has seen this. It is
the same trivial-value story as P1 with the trivial value being the *default in
the box* rather than the shape of the part.

I register the disagreement explicitly: under reading (B) P2 is not a defect
and the getter comment is right. I am deciding for (A) and shipping it as its
own commit so that an integrator who decides for (B) reverts one commit and
keeps P1.

### P3 — every existing perpendicular case stays bit-identical.

Every `OcctEdgeInfo` in every Dart fake carries `dihedralDeg = 90`
(`m136:36–39`, `m182:70`). For P1 alone, `D - angleDeg` with `D = 90.0` is the
expression `90.0 - angleDeg`, so the *bits* are identical, not merely the
value. P2 changes the distance whenever `angleDeg != 45` on such an edge; the
existing tests use `angleDeg = 30` and therefore **must** change, and I convert
them to assert the swap (§2 (i)) rather than relaxing them.

### P4 — the fallback matches the shim's, so the two layers never disagree about an edge.

`edge_chamfer_angle_limit` returns false — and the shim keeps 90 — for an edge
without exactly two faces, for normals that will not evaluate, and for a
tangent edge (`deg <= 1e-9`). Dart cannot see the first two, but it sees the
third as `dihedralDeg == 0`, and it sees "this id is not in `live`" as a fourth.
Predicted: mirroring the shim by using 90 in all of those keeps today's
behaviour exactly and cannot produce a Dart/shim disagreement about which angle
is admissible. **This is untested code by construction** — every fake edge has
two faces and a 90 — and I will say so rather than claim it works.

### P5 — `edgeChain` is inert. **NOT A DEFECT TODAY. Routed.**

`ChamferFeature.edgeChain` is serialised, is in `ownSig()`, defaults to `true`,
and is read by nothing: no compute path consults it, and `setEdgeFeature`'s
`edgeChain:` parameter has no caller in any widget. Predicted: deleting every
read of it would change no solid anywhere. It is **not** dead weight to remove —
it is in the file format — but the stored `true` is a claim about geometry
("All Tangentially Connected Edges") that the build does not honour, so the day
someone wires the toggle up, every existing part silently changes shape.
`BRepFilletAPI_MakeChamfer` chamfers the edges it is given and does not
propagate along tangencies, so `true` is the value that is wrong. Not mine to
change: the fix is either a UI control or a default flip, and both are
`app_state.dart`.

### P6 — Direct Move / Size / Scale always commit their trivial value. **Routed, not mine.**

`FaceEditSession` starts at `dx = dy = dz = 0`, `factor = 1`. The only mutator,
`setFaceEditValue` (`app_state.dart:6383`), **has no caller in `frontend/`** —
verified by grep over every `.dart` file, not taken from S16. `openDirectMove`
is wired to a live ribbon button (`ribbon.dart:874`). Predicted: opening Direct
Move, picking faces and applying adds a `DirectEditFeature` with a zero delta,
which `occt_move_faces` skips as a no-op, so the timeline gains a feature that
does nothing.

This **bounds S17 §7.2 downward and sharpens it**: S16 said the oblique face
move was latent because nothing set a free direction, and S17 took that on
trust. It is true, and the reason is stronger than "no caller" — the *whole
command* is inert, scale included. Defect 2 of shim v28 was never shipping.

### P7 — the coil's `taperDeg` and the sweep's `twistDeg` have never left zero. **NO DEFECT PREDICTED.**

Both are scalars handed straight to the shim with no frame composed around
them, which is S16 §1.2's exclusion test. `taperDeg` is the same parameter S16
left as a "still untested" row on the shim side; Dart adds nothing to it. The
sweep's `twistDeg` does not appear in `m131b`'s recorder assertions at all.
Recorded as empty regions, not predicted defective.

### P8 — the pattern directions and the loft frames are untested away from the axes, and are CORRECT anyway. **NO DEFECT PREDICTED.**

Every `AxisRef` and `PlaneRef` direction in the Dart suite is a coordinate axis.
But the occurrence arithmetic composes no frame of its own: it normalises
(`AxisRef.unit`), and rotates with `rotationMat34(point, k, ang)` over the
shared Rodrigues helper `rotateAboutAxis` — the same helper `PlaneFrame.mat34Rotated`
uses, unified precisely because it had drifted into two copies
(`part_model.dart:63`). There is no baked-in axis to be wrong about. Same
argument S16 used to predict its booleans correct (§1.2), and S16's boolean
prediction held.

### P9 — the countersink's `csAngle` is only ever 90, and 90 is the one value that proves nothing. **NO DEFECT PREDICTED.**

`_holeMouthTool` computes `half = csAngle/2`, `dz = (bigR - r)/tan(half)` and
sends `taper = ±half`. `m225` tests `csAngle = 90` (both flips) and `csAngle = 180`
(a refusal). At 90, `half = 45` and `tan 45 = 1`, so `dz = bigR - r` exactly and
an implementation that sent `taper = 90 - half` would produce **the same
number**. The test cannot discriminate. Predicted correct by derivation
instead: the shim's taper is a draft angle about the base plane
(`occt_capi.h:97`), so the radius grows by `dz * tan(taper)`, and that equals
`bigR - r` only for `taper = half`. A `csAngle = 120` case would discriminate
it (`dz = 1.7321`, growth `1.7321 * tan60 = 3`, against `tan30` giving 1). Not
mine — `_recomputeHole` is not the chamfer path — and recorded as an untested
region rather than a defect.

### P10 — `OccurrenceAt` is read by two feature kinds and refused by the rest, explicitly. **NO DEFECT.**

`_adjustedOccurrence` returns `notApplicable` for anything that is not an
extrude or a revolve, so a coil, sweep or loft occurrence is *placed* rather
than adjusted. That is a guard with a stated reason, not a silently dropped
placement. Named here so nobody re-derives it.

### P11 — what I expect to stay still

No `.arb`, no widget, no `app_state.dart`, no `perf*.dart`, no shim, no
scenario, no baseline. `occt_shim_version()` stays at **28**: this session adds
no C ABI surface and does not get to take a number. The C fixture file is not
touched, so no `[42x]` scenario is claimed.

---
