# S17 — three defects, named at their line and then repaired

Branch `claude/occt-shim-three-defects-rxejqx`. Owns `backend/occt/shim/**`,
`backend/occt/tests/**`, this file. Scenario numbers: **[41]** was handed out
with the brief; [41a]–[41c] below. [40a]–[40l] are S16's and three of them are
*converted* here rather than added to.

S16 audited eight parameters that had never been passed anything but their
trivial value, found three wrong away from it, and deliberately did not fix
them. This session fixes exactly those three. S16's §1.4 inventory is the map;
this file is what happened when the three DEFECT rows were made to say
*correct*.

---

## 0. MECHANISM, from OCCT's own source, before any fix

The brief's first method rule: *"It works now" is not a finding; "it called the
wrong law, here is the line" is.* S16 found all three by measurement and chased
the cause only part of the way. Here is the rest of the way, for each.

### 0.1 The coil's `clockwise` — the cylinder's parametrisation says which sign pair is left-handed

`occt_capi.cpp` builds the helix as a straight line in a
`Geom_CylindricalSurface`'s `(u, v)` space:

```c
const double slope = height / turns;
const gp_Dir2d d2(clockwise != 0 ? -1.0 : 1.0,
                  clockwise != 0 ? -slope : slope);
```

What `(u, v)` *mean* is not a matter of opinion. `Geom_CylindricalSurface::D0`
delegates to `ElSLib::CylinderD0`, and that function is four lines of
arithmetic (`src/ElSLib/ElSLib.cxx`):

```cpp
Standard_Real A1 = Radius * cos(U);
Standard_Real A2 = Radius * sin(U);
P.SetX(A1 * XDir.X() + A2 * YDir.X() + V * ZDir.X() + PLoc.X());
```

so

```
    P(u, v) = Loc + R·cos u · XDir + R·sin u · YDir + v · ZDir
```

`u` turns from `XDir` toward `YDir`; `v` climbs `ZDir`. Whether that turn is
counterclockwise *about* `ZDir` depends on the frame's handedness, and the
shim builds its frame with the three-argument `gp_Ax3` constructor, which is
inline in `src/gp/gp_Ax3.hxx:83`:

```cpp
gp_Ax3(const gp_Pnt& theP, const gp_Dir& theN, const gp_Dir& theVx)
    : axis(theP, theN), vydir(theN), vxdir(theN)
{
    vxdir.CrossCross(theVx, theN);   // theN × (theVx × theN)
    vydir.Cross(vxdir);              // vydir = theN × vxdir
}
```

`YDir = N × XDir`, so `(XDir, YDir, ZDir)` is right-handed —
`Direct()` returns `(vxdir × vydir)·N = N·N = 1 > 0`. Therefore:

> **increasing `u` turns counterclockwise about the axis, increasing `v`
> advances along it.** `du > 0, dv > 0` is a right-handed screw. The
> *left-handed* one is `du < 0, dv > 0`.

The flag negates both components, giving `(−1, −slope)`. That direction is
antiparallel to `(1, slope)` — the **same line through the origin in `(u,v)`**,
hence the same point set, hence the **same right-handed helix**, traversed
backwards and occupying `v ∈ [−height, 0]`.

**The wrong law: it negated the direction of travel where it needed to negate
one component of it.** One line, `occt_capi.cpp:4645`.

### 0.2 `occt_move_faces` — the loop contradicts itself, six lines apart

The mechanism here is not in OCCT at all; it is that `occt_move_faces` holds
two incompatible ideas in one loop body. First it declares tangential motion
unobservable, and skips it:

```c
const double along = delta.Dot(gp_Vec(outward));
if (std::fabs(along) < 1e-12) {
    /* Sliding a face along its own plane changes nothing about the
     * solid. Skipping it is right; ... */
    continue;
}
```

Six lines later it sweeps the **whole** delta, tangential part included:

```c
BRepPrimAPI_MakePrism prism(f, delta);
```

and `BRepPrimAPI_MakePrism` is a pure translational sweep along the vector it
is handed — `BRepSweep_Prism`'s constructor passes `V` to
`BRepSweep_Translation`, which does `gpt.SetTranslation(V)`
(`src/BRepSweep/BRepSweep_Prism.cxx:34,128`). So the prism leans by exactly the
component the guard above calls a no-op.

Both cannot be right. If sliding a planar face in its own plane changes
nothing — and it does not, provided the neighbouring walls stay where they are,
because the face's *plane* is carried onto itself — then the tangential part of
an oblique delta changes nothing either, and sweeping it produces an overhang
on one side and a notch on the other that belong to no reading of "move this
face".

**The wrong law: the prism is built from `delta` where the operation's own
stated semantics is `(delta·n)·n`.** One line, `occt_capi.cpp:4666`
(pre-fix `1966`).

**This is where I part company with S16, and it matters.** §5.2 and [40i] name
the correct answer as "the walls follow the face", ray exit at
`z = 25·(2/5) = 10`. I claim the correct answer is **25** — the face's plane
moved by the normal component, walls unchanged — and that 10 is a *different
operation*, for three reasons:

1. **The walls-follow reading contradicts the skip that is already there.** A
   purely tangential move of a cube's top face by `(5,0,0)` shears the box into
   a parallelepiped under the walls-follow reading. The shim returns the box
   untouched, on purpose, with a comment saying why. Walls-follow would require
   deleting that skip.
2. **Walls-follow moves surfaces the caller did not select.** The wall `x = 0`
   would stop being the plane `x = 0` and become `z = 5x`. That is
   surface-sliding with neighbour re-trimming, and `part_model.dart:3321`
   records the repo's decision about exactly that class of operation: *"ROTATE
   IS NOT HERE. Rotating a face means sliding its surface and re-trimming its
   neighbours — a BRepTools_Modification subclass whose failure modes only
   appear on real shapes. Shipping it unverified would be exactly the
   dead-looking-alive control this milestone's ribbon pass removed."*
3. **Walls-follow is not well-defined in general and the projection is.** Ruling
   a new surface for each neighbour needs a rule per surface type; there is no
   such rule for a cylindrical neighbour, and none is written anywhere in this
   repo. "Translate the selected face's plane, leave every other face alone" is
   defined for every planar face on every solid.

S16's own §7.1 says it "did **not** establish that the second reading is
Inventor's" and that the choice "is the integrator's call". I am not appealing
to Inventor either; I am appealing to the shim's own two lines, which
contradict each other, and choosing the side that the surviving line and the
Dart model already commit to. **The defect S16 found is real — the leaning
prism is nobody's answer. Its proposed ground truth is the one I am not
adopting, and §5.2 below says so at the top rather than in a footnote.**

### 0.3 The chamfer guard — OCCT's plane/plane chamfer prints the admissible range

```c
if (modes[i] == 2 && (!angle_deg || !(angle_deg[i] > 0.0) || angle_deg[i] >= 90.0))
```

S16 derived `α < 180° − θ` from a cross-section triangle. That derivation is
correct, and OCCT states the same thing in arithmetic. `AddDA` stores the pair
(`ChFi3d_ChBuilder::AddDA` → `ChFiDS_ChamfSpine::SetDistAngle`, which validates
**nothing**), and the plane/plane case computes the second distance in
`src/ChFiKPart/ChFiKPart_ComputeData_ChAsymPlnPln.cxx`:

```cpp
gp_Dir VecTransl1 = LinAx1.Crossed(D1);      // in Pl1, ⟂ edge, toward Pl2
gp_Dir VecTransl2 = LinAx1.Crossed(D2);      // in Pl2, ⟂ edge, toward Pl1
cosP = VecTransl1.Dot(VecTransl2);
sinP = sqrt(1. - cosP * cosP);
...
dis2 = Dis / (cosP + sinP / Tan(Angle));
```

`VecTransl1` and `VecTransl2` are the two **into-face directions** at the edge,
so `P` is the **interior dihedral θ** — the same quantity the shim's own
`edge_info` builds its convexity sign from. Expand:

```
    dis2 = d1 / (cos θ + sin θ · cot α)
         = d1 · sin α / (sin α cos θ + cos α sin θ)
         = d1 · sin α / sin(α + θ)
```

which is the law of sines in S16's triangle with the apex angle `θ` and the
angle at the reference-face tangent point `α`. Two things follow, and neither
is a matter of taste:

* **`α` is measured from the reference face** — the shim's comment is right,
  and now it is right *for a reason*: `dis2` is the distance on the *other*
  face, so `Dis` and `Angle` are both anchored on `Pl1`, the face handed to
  `AddDA`.
* **`dis2` blows up at `α + θ = 180°` and goes NEGATIVE past it.** The
  admissible range is `0 < α < 180° − θ`, exactly. It equals `α < 90°` if and
  only if `θ = 90°`.

`180° − θ` is the angle between the two **outward normals**, which is precisely
`occt_shape_edge_info` field `[10]` (S16's recorded trap: field [10] is
`acos(n1·n2)`, and `θ = 180° − info[10]`). So the guard's correct form is

> **`0 < angle_deg < info[10]`** — the bound the shim already computes
> elsewhere and never consulted here.

**The wrong law: a literal `90.0` where the edge's own turn angle belongs.**
One line, `occt_capi.cpp:3288`.

And note it is wrong in *both* directions, which S16 derived but did not
measure: too strict on an acute edge (θ=60 → refuses a legal α=100), too
**permissive** on an obtuse one (θ=135 → accepts α=60, for which `dis2` is
`−6.692130`, a negative distance handed to OCCT). [41a] measures the second
half.

---

## 1. PRE-REGISTRATION

Committed **before** the fix and before the fixtures. Every number is
arithmetic done above, not a reading taken from a build.

### R1 — the coil, [40d] converted

The fix is `gp_Dir2d d2(clockwise != 0 ? -1.0 : 1.0, slope)`. `plen = turns /
|d2.X()|` is unchanged and still correct: `gp_Dir2d` normalises, so
`|d2.X()| = 1/√(1+slope²)`, `plen = turns·√(1+slope²)`, and at `t = plen` the
line has reached `u = ∓turns`, `v = +height`.

[40d]'s fixture: a 2×2 square at radius 20 in the XZ plane, axis `+Z` through
the origin, 5 revolutions, 50 mm rise. `slope = 50/10π = 1.5915494309`, rise
per turn exactly **10**. The frame has `XDir = +X` (foot→centroid), so
`YDir = Z × X = +Y` and `u = 0` sits at `+X`.

The fixed clockwise coil is the **exact mirror image of the counterclockwise
one through the plane `y = 0`**: `u → −u` maps `(20cos u, 20 sin u, u·slope)`
to `(20 cos u, −20 sin u, u·slope)`, and the starting section lies in the XZ
plane, which that mirror fixes. Mirroring in `y` preserves `z` exactly.

**Predictions.**

* **Rise.** `cw` bbox `z` equals `ccw` bbox `z` **to 1e-9 relative**, both ends.
  S16 measured `ccw z[−0.9968, 50.9969]`; the fix must reproduce those two
  doubles, not merely land near 0 and 50. Today: `z[−50.9969, 0.9968]`.
* **Handedness, by ray.** Cast `+Z` up the line `x = 0, y = 20`, which passes
  through the helix point at azimuth `u = π/2`. Material crosses that line
  wherever `u ≡ π/2 (mod 2π)`:
  * `ccw` (`u ∈ [0, 10π]`): `u = π/2 + 2πk`, `k = 0..4` → centres at
    `z = 2.5, 12.5, 22.5, 32.5, 42.5`;
  * `cw` **fixed** (`u ∈ [−10π, 0]`): `u = π/2 − 2πm`, `m = 1..5` → centres at
    `z = 7.5, 17.5, 27.5, 37.5, 47.5`;
  * `cw` **today**: `u = π/2 − 2πm` with `v = u·slope` → centres at
    `z = −7.5, −17.5, −27.5, −37.5, −47.5`.

  **10 hits** each (five 2 mm passes, entry and exit). The ray passes through
  the section's centre and the section is centrally symmetric, so each **hit
  pair's midpoint** is the centre crossing; I predict each to **5e-2** (the
  slack is for the tube's curvature across a 2 mm chord, which is the only
  reason this is not exact).

  The two coils interleave at a 5 mm offset, which no volume and no bounding
  box can see, and which is what "opposite handedness, same rise" means.
* Volume unchanged at `4·5·√((40π)² + 100) = 2521.2193115` to 2e-2 relative,
  and `cw` volume equals `ccw` volume to 1e-9 (already S16's check; it must
  keep holding, since the mirror is an isometry).

**Falsified if** the fixed `cw` coil's `z` range is not the `ccw` one, or its
azimuth-90° crossings are not offset by half a turn (5 mm) from the `ccw`
coil's.

**`finish_pipe` is not touched.** The change is in the spine's `(u,v)`
direction, upstream of `BRepOffsetAPI_MakePipeShell`. The brief's caution about
shared infrastructure carrying S14's and S15's work does not fire; if it had, I
would have stopped and written it up instead.

### R2 — `occt_move_faces`, [40i] converted

The fix is to sweep the **observable** part of the delta:
`gp_Vec push = gp_Vec(outward) * along;` and `MakePrism(f, push)`.

20-cube, top face, `delta = (5, 0, 5)`, `along = 5`:

* **Volume stays 10 000** — `A·|delta·n| = 400·5 = 2000` either way. Volume
  could not see the defect and cannot see the fix; the fixture must say so
  rather than resting on it.
* **The ray moves from 22 to 25.** Up `x = 2, y = 10`: today the leaning prism
  reaches `z = 20 + 5·(2/5) = 22`; after the fix the slab is `z ∈ [20, 25]`
  across the whole face, so the exit is **25.0** exactly. (S16's [40i] predicts
  10 here for the fix; §0.2 is why I predict 25.)
* **The bounding box is the cheapest witness and nobody looked at it.** Today
  the prism carries material out to `x = 25`. After the fix the solid is
  `[0,20]×[0,20]×[0,25]` — `x`-max **20**, not 25. Exact integers.
* **Equivalence, which is the ground truth itself.** `move(5,0,5)` and
  `move(0,0,5)` must return **the same solid**: equal volume to 1e-9, equal
  bbox to 1e-9, equal ray exits at `x = 2` and `x = 18`. That is the assertion
  the converted fixture exists for — the tangential component is unobservable,
  stated as a test rather than as a comment.
* **Continuity at `δ = 0`, the sharpest form of the defect.** `move(5,0,0)` is
  skipped today and after the fix: the box comes back untouched, volume 8000,
  bbox `x`-max 20. Now take `δ = 0.001`:
  * today `move(5,0,0.001)` has bbox `x`-max **25** — a 5 mm overhang appears
    from nothing as `δ` leaves 0, while volume moves by 0.4;
  * after the fix `x`-max is **20** and volume is **8000.4**, continuous in `δ`.

  A 5 mm jump in the answer for a 0.001 mm change in the input is not a
  scoping question about tapered neighbours. It is the defect, stated so that
  no reading of "move a face" can defend it.

**Falsified if** the projected move is refused, or invalid, or its bbox is not
`[0,20]×[0,20]×[0,25]`, or it differs from `move(0,0,5)`.

**Registered limit, so it cannot be quietly widened later:** this repairs the
**planar** case, which is every face the argument in §0.2 covers. For a
**non-planar** face `face_outward` samples the mid-parameter normal and the
prism-and-fuse model is ill-posed *before* my change and ill-posed after it —
projecting onto one representative normal of a cylinder is as arbitrary as
sweeping the whole delta was. I am not fixing that, not testing it, and not
claiming it. §7.

### R3 — the chamfer guard, [40j] converted, [41a]–[41c] new

The fix computes the edge's own bound instead of hardcoding one: take the two
adjacent faces' outward normals at the edge's arc-length midpoint (the same
`face_outward_normal` and the same midpoint `edge_info` uses, so the guard and
field [10] cannot drift apart), and require

```
    0 < angle_deg[i] < acos(n1·n2) in degrees        ( = 180° − θ )
```

falling back to the historical `90.0` when the bound cannot be measured — an
edge without exactly two faces, or normals that will not evaluate. Refusing
there would be a second behaviour change nobody asked for.

**Predictions.** `d2 = d1·sin α / sin(α+θ)`, and the wedge removed by a chamfer
on a straight edge of length `L` with no run-out is
`½·d1·d2·sin θ·L`.

* **[40j], θ = 60 (equilateral prism, `info[10] = 120`, base volume
  7794.228634, L = 20, d1 = 2).** Bound becomes **120**.
  * `α = 80` builds (it did before) — the control.
  * `α = 100`, refused today, **builds**, and removes **99.744831**
    (`d2 = 5.758770`). That number is not new: it is the one S16 already
    measured for the *mode-1* spelling of this chamfer. So the converted
    fixture asserts what S16's log printed as a divergence — **two spellings of
    one chamfer, now both building and agreeing to 1e-9.**
  * `α = 110` also builds and removes **187.458963** (`d2 = 10.822948`).
  * `α = 125` is **still refused**, and the message names 120. That pins the
    new bound as a *bound* rather than as "more permissive than before".
    `d2` there would be `−18.797431`.
* **[41a], θ = 135 — the permissive half, which S16 derived and did not
  measure.** Chamfer a 20-cube's vertical edge with `d1 = 4, mode 0`
  ([40k]'s construction, base volume **7840**), leaving two edges with
  `info[10] = 45`, each running the full 20 mm.
  * `α = 30` builds and removes **54.641016** (`d2 = 3.863703`).
  * `α = 60` is **accepted by today's guard** — `60 < 90` — and hands OCCT
    `dis2 = −6.692130`, a negative distance. After the fix the **guard**
    refuses it and says 45. I predict today's outcome is a NULL from OCCT
    rather than a wrong solid, i.e. the user's loss is a bad error message
    rather than a bad part; **I have not measured this and will report what it
    actually does**, because "probably NULL" is not a finding.
* **[41b], the law itself.** `removed = ½·d1·d2·sin θ·L` with
  `d2 = d1·sin α/sin(α+θ)` holds at (θ=90, α=45, d2=2 — the cube case the old
  guard was tuned for), (θ=60, α=100), (θ=135, α=30). Three dihedrals, one
  formula, taken from `ChFiKPart_ComputeData_ChAsymPlnPln.cxx:115` rather than
  from a fixture. This is what makes the new bound *the* bound and not just a
  looser number.
* **[41c], the fallback.** A chamfer on an edge whose bound cannot be measured
  keeps the 90° rule. Asserted on a cube, where `info[10] = 90` and the two
  rules coincide — so this scenario is a *regression pin*, not a discovery: it
  is what says the fix did not disturb the case every existing fixture uses.

**Falsified if** `α = 100` on the θ=60 edge still fails after the fix (then
OCCT will not build it and the guard was defensible — S16's registered
falsifier, still live), or if the removed volumes miss the formula by more
than 1e-6 relative, or if `α = 125` builds.

### R4 — version, and what a caller learns

All three change observable behaviour, so `occt_shim_version()` goes **27 → 28**
and the note in `occt_capi.cpp` says what a caller who tests for `>= 28` knows.
Recorded here before the fix so the number cannot drift: 28 is taken by *this*
session, which owns `backend/occt/shim/**`, per the v17 and v21/v23 collision
notes already in that file and the brief's warning that this project has had
three identifier collisions.

### R5 — what I expect to stay still

`occt_mesh_recon_test`, every scenario [1]–[39] and [40a]–[40c], [40e]–[40h],
[40k], [40l]. The coil change is one line in the spine direction; the
move-faces change one vector; the chamfer change is a guard. If anything else
moves, the mechanism in §0 is wrong and I would rather find out from a red
smoke test than from a device.

`analyze` delta is **structurally zero**: the diff touches no Dart file. Stated,
not measured — Flutter is not installed in this environment (§7).
