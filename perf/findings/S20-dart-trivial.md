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

## 4. RESULTS

### 4.1 The whole defect in one table, computed by the shipped code

Every number below came out of `ChamferFeature` itself, run under Flutter
3.47.1 on this machine, next to the face distances OCCT's own formula gives
for what it sent — old path and new path in the same run, no golden, which is
what `OPTIMIZATION_PLAN_2.md` §1.4 asks for. `theta` is the interior dihedral
the material makes at the edge; `D = 180 - theta` is `dihedralDeg`, field [10],
and the shim's v28 bound. `d1 = 2 mm` throughout. "cuts" is the pair of
distances taken off the two adjacent faces.

| theta | D | alpha | unflipped cuts | OLD flip sent | OLD cuts | NEW flip sends | NEW cuts |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 90 | 90 | 30 | (2.0000, 1.1547) | (2.0000, 60) | **(2.0000, 3.4641)** | (1.1547, 60) | **(1.1547, 2.0000)** |
| 90 | 90 | **45** | (2.0000, 2.0000) | (2.0000, 45) | (2.0000, 2.0000) | (2.0000, 45) | (2.0000, 2.0000) |
| 120 | 60 | 30 | (2.0000, 2.0000) | (2.0000, 60) | **REFUSED — 60 is the bound** | (2.0000, 30) | (2.0000, 2.0000) |
| 120 | 60 | 45 | (2.0000, 5.4641) | (2.0000, 45) | **(2.0000, 5.4641) — Flip did NOTHING** | (5.4641, 15) | (5.4641, 2.0000) |
| 60 | 120 | 30 | (2.0000, 1.0000) | (2.0000, 60) | **(2.0000, 2.0000)** | (1.0000, 90) | (1.0000, 2.0000) |
| 60 | 120 | 45 | (2.0000, 1.4641) | (2.0000, 45) | **(2.0000, 1.4641) — Flip did NOTHING** | (1.4641, 75) | (1.4641, 2.0000) |
| 135 | 45 | 30 | (2.0000, 3.8637) | (2.0000, 60) | **REFUSED — 45 is the bound** | (3.8637, 15) | (3.8637, 2.0000) |
| 135 | 45 | 45 | (2.0000, ∞) | (2.0000, 45) | REFUSED | (2.0000, 0) | REFUSED — §4.4 |

**In the NEW column every "cuts" pair is the unflipped pair reversed.** That is
the whole claim, and it is the assertion `m131` now makes.

Three things the table says that neither S17 nor the pre-registration had:

1. **Row 4 and row 6 are the sharpest finding in this session.** `90 - 45 = 45`,
   so on an edge that is not square a 45 deg flipped chamfer sent *exactly the
   unflipped arguments*: the Flip button did **nothing at all**, on a chamfer
   that is not symmetric and does have a mirror. Not a wrong chamfer, not a
   refusal — a dead control, and one whose deadness depended on the shape of
   the part.
2. **Rows 3 and 7 are S17's improvement doing its job.** Those two used to be
   silent wrong chamfers and became clear refusals at shim v28. The audit's
   own P1 prediction — that a 30 deg flip on a 120 deg edge is refused at the
   bound of 60 — is confirmed by arithmetic here and would be confirmed by
   OCCT on any machine with the shim built.
3. **Row 2 is why this survived nine months.** The panel's default angle is
   45 deg, and every edge anyone has chamfered in a test here is square, and
   there the old code is exactly right.

### 4.2 The differential, and why it needs no kernel

`m131_feature_polymorphism_test.dart` now carries `faces(d, alpha, D)`,
transcribed from OCCT's `dis2 = d1 sin(alpha)/sin(alpha + theta)` as the shim's
own source note states it, and **not** from the Dart under test. The test then
asserts, over a grid of five dihedrals × four angles:

```
    faces(flip(x))  ==  reverse(faces(x))
```

Both sides are computed in the same run on the same machine from two
independently written expressions. That is a differential equivalence, it is
platform-independent, and it would have failed on the old code at every grid
point except `alpha = D/2` — including at `alpha = 45, D = 90`, where it passes
because the answer really is the identity there.

Three more assertions carry the properties: the symmetric chamfer is its own
mirror at three dihedrals; flipping twice is the identity (a **regression pin**,
not evidence — the old angle-only form had this property too); and the flipped
angle stays inside `(0, D)` over a grid, which `90 - angleDeg` does not.

### 4.3 What a user sees differently

**Nothing at all** for: any equal-distance chamfer, any two-distance chamfer,
any unflipped chamfer, and a flipped distance-and-angle chamfer at exactly
`D/2` — which on a square edge is the panel's own default of 45 deg. That is
most of what exists.

**A different solid** for a flipped distance-and-angle chamfer at any other
angle. On a square edge the reference-face distance becomes
`distance1 * tan(angleDeg)` instead of `distance1`. Said the other way round:
Flip now produces the mirror of the chamfer you had, which is what the button
has always claimed.

**A chamfer that used to build may now fail to fit**, and this is not a
regression: the mirror of a steep chamfer is a large one. An 80 deg 2 mm
chamfer on a square edge really does cut 11.34 mm off the other face, and if
the face is 10 mm wide, OCCT refuses — correctly, and with its own message. The
old code hid that by not actually swapping.

**Two refusals become chamfers.** Rows 3 and 7: on a 120 deg or 135 deg edge a
flipped chamfer that shim v28 refused now builds, at the right angle.

**A saved part rebuilds differently** in exactly the cases above. There is no
migration and I did not add one: the stored `flip`, `d1` and `angle` are
unchanged and still mean what the panel says they mean; it is the arguments
derived from them that were wrong.

### 4.4 The one row I am not happy with

`theta = 135, alpha = 45` (D = 45, `alpha == D`). The chamfer is degenerate
unflipped — `dis2` is infinite — and shim v28 refuses it either way, so nothing
is built wrongly. But the flipped path reaches the shim with an angle of 0 and
draws *"chamfer angle must be greater than 0 deg"* instead of the sentence that
names the edge's bound, which is the message the same input gets with Flip off.
The trade is stated in the code: handing the typed angle through instead would
draw the better message and would build the UNFLIPPED chamfer if this layer's D
and the shim's limit ever disagreed. Failing closed with a vaguer sentence is
the choice this file makes everywhere else, so it is the choice here.

### 4.5 The inventory, after

| Op | Parameter | Non-trivial coverage now | Verdict |
| --- | --- | --- | --- |
| `ChamferFeature` | mode-2 `angleDeg` + `flip` | `m131` asserts the face swap over D ∈ {45,60,90,120,150} × four angles, the symmetric identity, the involution, and the guard range | **correct — both defects repaired, §4.1** |
| `ChamferFeature` | per-edge binding | `kernelArgsFor` reads each edge's own `dihedralDeg` from `live` | **correct — the scalar collapse is gone** |
| `ChamferFeature` | unmeasurable / tangent edge | `m131` pins `dihedralDeg = 0` → the historical 90 | correct, but **untested against a real such edge**, §6.3 |
| everything else in §1 | — | unchanged | **recorded, not touched** — §5 |

---

## 5. Findings I am routing rather than fixing

### 5.1 `ChamferFeature.edgeChain` is inert, and its default is the wrong one

Confirmed as predicted (P5). It is serialised, it is in `ownSig()` — so toggling
it forces a rebuild that produces a byte-identical solid — and **nothing reads
it**. `setEdgeFeature`'s `edgeChain:` parameter has no caller in any widget, so
it cannot even be toggled; `edge_feature_dialog.dart` offers Method, the
distances, the angle and Flip, and no chain control.

The part that matters is the default. It is `true`, it is named for Inventor's
"All Tangentially Connected Edges", and `BRepFilletAPI_MakeChamfer` chamfers
the edges it is handed and does not propagate along tangencies. So every saved
part in existence carries a stored claim about its geometry that the build does
not honour, and the day someone wires the toggle up, **those parts change
shape**. The fix is either a real control or a default of `false` plus a
migration; both live in `app_state.dart` and neither is mine.

### 5.2 Direct Move / Size / Scale are inert from the ribbon

Confirmed as predicted (P6), and by grep over every `.dart` file in
`frontend/`, not by inheriting S16's claim. `FaceEditSession` starts at
`dx = dy = dz = 0` and `factor = 1`; the only mutator, `setFaceEditValue`
(`app_state.dart:6383`), has **no caller anywhere**; `openDirectMove` is on a
live ribbon button. So the command opens, takes face picks, and commits a
`DirectEditFeature` that moves nothing — the timeline gains a row that does
nothing, and Direct Scale likewise scales by 1.

This **closes S17 §7.2 in S17's favour and for a stronger reason.** S16 said the
oblique face-move defect was latent because no UI offered a free direction; S17
recorded that it had taken that on trust and that "if S16 was wrong about that,
defect 2 was shipping". S16 was right, and more so: not merely is there no
oblique direction, there is no direction at all. Shim v28's defect 2 was never
shipping.

`app_state.dart` and `lib/widgets/**` are not this session's, so this is
recorded and not patched.

### 5.3 The shim header's "KNOWN, NOT FIXED HERE" paragraph is now stale

`occt_capi.h`, above `occt_chamfer_edges`, still says Dart's Flip sends
`90-angle` and points at `S17-oblique.md` §5.1 for why it was not fixed there.
That is closed as of this session. `backend/occt/shim/**` is not mine to edit —
S17 owned it and no session owns it now — so the correction is routed rather
than made. Whoever next opens that file should replace the paragraph with a
pointer here.

### 5.4 Three untested regions, named so nobody re-derives them

* **The countersink's `csAngle`** (P9). Only ever 90 and 180 in the suite, and
  90 is precisely the value that cannot discriminate `taper = half` from
  `taper = 90 - half`, because `tan 45 = 1`. Derived correct in P9; a single
  `csAngle = 120` case would close it (`dz = 1.7321`, growth 3.0000 against
  1.0000). `_recomputeHole` is not the chamfer path.
* **Pattern directions and mirror-plane normals** (P8). Every one in the suite
  is a coordinate axis. Predicted and left as correct — the occurrence maths
  composes no frame of its own and rotates through the shared Rodrigues helper
  — but an oblique `AxisRef` has never been built.
* **The coil's `taperDeg` and the sweep's `twistDeg`** (P7). Zero in every
  compute test. `taperDeg` is the same row S16 left open on the shim side, so
  it is untested on both sides of the FFI boundary at once.

---

## 6. What I deliberately did not do

* **Did not touch the shim, its tests, or its version.** No C ABI surface is
  added, so `occt_shim_version()` stays at **28** and no `[42x]` scenario is
  claimed. §5.3 is routed for the same reason.
* **Did not touch `app_state.dart`, any widget, or any `.arb`.** §5.1 and §5.2
  both live there.
* **Did not touch `lib/ffi/occt_engine.dart`.** The per-edge binding it already
  exposes is what this session started using; it needed no change, which is the
  point.
* **Did not touch `perf*.dart` or `perf/baseline.json`.** The frozen zone is
  closed to this session and nothing here needs it.
* **Did not add a migration for `edgeChain`** (§5.1) or change its default. That
  would silently reshape saved parts to fix a control nobody can reach.
* **Did not remove `edgeChain`.** It is in the file format.
* **Did not widen the fix to mode 1.** Its flip is already the true face swap.

---

## 7. What I am unsure of

1. **Whether Flip means (A) or (B) — the one that matters.** §0.3 lays out both
   readings and §3 P2 decides for (A) on four grounds: the field's own comment,
   the button's label, mode 1's existing behaviour, and Inventor. None of those
   is a reference implementation running in front of me — there is no Inventor
   here, exactly as there was none for S16 or S17 — and the getter's own comment
   argues the other way. That is why defect 2 is **its own commit**: an
   integrator who decides for (B) reverts `S20 defect 2` and keeps defect 1's
   fix, and I have verified that revert applies cleanly and leaves the suite
   green at 2560. It is the strongest form in which I can state this, and it is
   deliberately weaker than "this is what a CAD system does".
2. **The 90 fallback is untested code, by construction.** Every `OcctEdgeInfo`
   in every fake here has two faces and `dihedralDeg = 90`, so the branch that
   substitutes 90 for an unmeasurable or tangent edge is exercised by exactly
   one unit assertion passing a literal 0 — never by an edge that really is
   tangent. S17 said the same about the shim's half of this fallback (§7.3) and
   it is still true on both sides.
3. **Whether Dart's D and the shim's limit can ever disagree.** They are the
   same helper at the same arc-length midpoint today, and S17 §7.4 already
   recorded that nothing tests the agreement — two call sites, not one
   function. This session now makes Dart *act* on that number rather than
   merely display it, which raises the stakes the same way v28 raised them for
   the guard. A test asserting `limit == info[10]` is still five lines and still
   unwritten, and it is on the C side.
4. **Curved edges.** D is measured at the arc-length midpoint and varies along a
   curved edge, so a flip computed there is right at the midpoint and
   approximate elsewhere. This is the assumption field [10] has always made and
   I did not widen it — but, as with (3), Dart now computes a *distance* from it
   rather than reporting it, so an error in D is now an error in the geometry.
5. **Whether removing `kernelParams` was worth breaking two test groups.** It
   is a public member and three files referenced it. The argument for is in
   §0.5: a getter that answers without an edge is the defect, and a compile
   error is a better guard than a comment. The argument against is that modes 0
   and 1 genuinely have no edge dependence and now take an argument they ignore.
   I think the trade is right and I record that it is a trade.
6. **I did not build a part with a non-square chamfered edge.** Everything in
   §4.1 is the Dart layer's arithmetic checked against OCCT's formula. What no
   test here can do is confirm that OCCT, handed those arguments, produces the
   mirrored solid — that needs the shim built and a real body, which is
   `occt_smoke`'s ground and no scenario is claimed. The claim I am making is
   exactly "Dart now sends the arguments that describe the mirrored chamfer",
   not "OCCT builds it".

---

## 8. Definition of done

| | |
| --- | --- |
| Mechanism named from source | **§0.1** OCCT's `dis2` via `occt_capi.cpp`; **§0.2** the reference-face contract in `occt_capi.h`; **§0.3** the two readings, quoted from the class itself |
| Predictions committed before the code | `34c4b4a`, eleven of them, before the first line of the fix. P1–P11 all resolved in §4/§5; **P2 and the two "Flip did nothing" rows of §4.1 are more than the pre-registration predicted**, and are marked as such |
| The inventory, which is the primary deliverable | **§1**, 24 rows, with **six trivial, one inert and three "still untested"** named honestly |
| The generalisation answered | **§1.1** — the hypothesis **fails** for most of this layer, and the reason is worth more than a defect would have been: the Dart binding passes `clockwise`, `ruled`, `closedLoop`, sweep `orientation` and `taperDeg` faithfully, which is *why* S16's shim defects were reachable from the UI |
| Differential, old against new, no golden | **§4.2** — OCCT's formula transcribed from the C source, both sides computed in one run |
| One commit per defect, independently revertible | `54b2f13` and `0ed5587`. **Verified by actually reverting defect 2**: applies cleanly, suite green at 2560 |
| `flutter analyze --no-fatal-infos --no-fatal-warnings` | **no new issue.** 62 issues before and after; the one `unnecessary_cast` in `part_model.dart` is on the clean tree too |
| `flutter test` | **2564 passed, 0 failed**, Flutter **3.47.1** — the version CI runs, on this machine. Not "structurally zero": measured |
| `occt_shim_version()` | **unchanged at 28.** No C ABI surface added, no scenario claimed |
| Shim, `occt_engine.dart`, `app_state.dart`, widgets, `perf*`, baseline | **untouched** — `git diff --name-only` over the whole session is `part_model.dart`, **seven** test files, one findings file, one README row and one CROSS-SESSION entry |
| Routed, not fixed | **§5** — `edgeChain`'s inert-and-wrong default, Direct Edit's inert commands, the stale shim header, three untested regions |
