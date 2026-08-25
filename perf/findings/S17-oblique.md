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

**This is where I part company with S16, and it matters.** S16 §5.2 and [40i] name
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
adopting, and S16 §5.2 is cited by name wherever this file relies on it.**

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

---

## 2. RESULTS

Everything below is from `backend/occt/build/occt_smoke`, built against real
OCCT **7.9.3** from the pinned submodule (`a016080`) on this machine, in one
run. `occt_smoke` reports **PASS** and `occt_mesh_recon_test` **86 passed, 0
failed**.

| | Prediction | Verdict | The number that settled it |
| --- | --- | --- | --- |
| R1 | the coil rises and reverses handedness | **HELD, every number** | `cw z[-0.9968, 50.9969]` = `ccw z[-0.9968, 50.9969]`; azimuth-90 crossings `ccw 2.5/12.5/22.5/32.5/42.5`, `cw 7.5/17.5/27.5/37.5/47.5` — every one on its predicted value |
| R2 | the oblique move is the moved plane | **HELD** | ray exit **25.000000** at both `x = 2` and `x = 18`; bbox x-max **20**; oblique ≡ perpendicular on volume, all six extents and both rays |
| R2c | continuity at `δ = 0` | **HELD** | `(5,0,0)` → 8000.000000, x-max 20; `(5,0,0.001)` → 8000.400000, x-max 20 |
| R3a | θ=60: α=100 and 110 build | **HELD** | removed **99.744831** and **187.458963**, both analytic |
| R3b | the two spellings agree | **HELD** | mode 2 α=100 and mode 1 (d1=2, d2=5.758770) both remove **99.744831**, to 1e-9 |
| R3c | θ=60: α=125 still refused, naming 120 | **HELD** | refused; message names 120 |
| R3d | θ=135: α=30 builds, α=60 now refused | **HELD** | removed **54.641016** (analytic 54.641016); α=60 refused, message names 45 |
| R3e | one formula, three dihedrals | **HELD** | d2 = 2.000000000 / 5.758770483 / 3.863703305, law of sines and OCCT's expression agreeing to 1e-12 |
| R3f | θ=90: α=89.9 builds | **REFUTED — and the refutation is a finding** | α=89.9 puts d2 at **1145.9144** on a 20 mm face. §2.2 |
| R5 | nothing else moves | **HELD, measured not assumed** | §2.1 |

### 2.1 The differential, which is the whole proof

`OPTIMIZATION_PLAN_2.md` §1.4 forbids recorded goldens, so R5 is not "the
numbers look like last time". The pre-S17 tree (`9f34312`) was **built and run
on this machine, against this OCCT install, in this session** — old shim, old
fixtures — and its smoke output diffed against the new one:

```
$ diff <(grep -v '^\[40d\]\|^\[40i\]\|^\[40j\]\|^\[41' smoke-old.log) \
       <(grep -v '^\[40d\]\|^\[40i\]\|^\[40j\]\|^\[41' smoke-final.log)
$ echo $?
0
```

**Every line of smoke output outside the three converted fixtures and the three
new ones is identical, including the version banner.** Not a golden, not a
recollection: two binaries, one machine, one afternoon. The first run of this
diff returned one line — `shim v27 … (shim ABI v28)` — which is how the version
string's drift was found (§4).

### 2.2 The prediction that was wrong, and why it is worth more than the fixture it broke

R3 predicted α = 89.9 would build on a cube edge, since 89.9 < 90. It does not:

```
alpha=60.0 d2=3.4641   -> built
alpha=80.0 d2=11.3426  -> built
alpha=85.0 d2=22.8601  -> REFUSED
    err: no distance in this size range builds on these edges
         (too large for the faces meeting at the edge?)
alpha=89.9 d2=1145.9144 -> REFUSED  (same message)
```

**The guard's bound and the fits-on-the-face limit are different limits, and
the guard only owns the first.** `d2 = d1·sin α / sin(α+θ)` *diverges* as α
approaches `180° − θ`, so the buildable range is strictly inside the admissible
one, and the outer part is refused by `blend_edges_subset`'s size retry with
its own, already-correct message. [41c] now asserts that distinction — α = 85
refused with the **size** message and not the angle one — which is a better
scenario than the one predicted.

It also **bounds the severity of defect 3**, in the direction that makes it
smaller: relaxing the guard on an acute edge does not mean every angle below
the new bound builds. It means the angle is no longer what stops it.

### 2.3 Defect 1 — the coil, repaired

One line. `gp_Dir2d d2(clockwise != 0 ? -1.0 : 1.0, slope)`.

```
[40d] ccw vol 2521.2203 z[-0.9968,50.9969] | cw vol 2521.2203 z[-0.9968,50.9969]
[40d] azimuth-90 ray: ccw 10 hits, cw 10 hits
[40d]   pass 0: ccw z 2.5000 (want 2.5) | cw z 7.5000 (want 7.5)
[40d]   pass 4: ccw z 42.5000 (want 42.5) | cw z 47.5000 (want 47.5)
```

The z ranges are now **the same two doubles**, which is what a mirror image
must give. The ray is the part no previous instrument in this repo could have
produced: the two coils' material interleaves at exactly half a turn, 5 mm,
which is what "opposite handedness, same rise" means. Volume is 2521.2203 for
both, before and after, and always was — the helix length does not care which
way it winds, which is why nine months of volume checks were blind to this.

`finish_pipe` was not touched. The brief's stop-and-write-it-up condition did
not fire.

### 2.4 Defect 2 — the oblique face move, repaired

One vector. `MakePrism(f, gp_Vec(outward) * along)`.

```
[40i] oblique move volume 10000.000000, valid=1, x-max 20.0000,
      ray x=2 hits=2 0.0000 25.0000
[40i]   x=2:  oblique exits 25.000000, perpendicular exits 25.000000
[40i]   x=18: oblique exits 25.000000, perpendicular exits 25.000000
[40i] continuity: (5,0,0) vol 8000.000000 x-max 20.0000 |
                  (5,0,0.001) vol 8000.400000 x-max 20.0000
```

Volume is 10 000 and the solid valid **both before and after** — that is the
point, and the fixture says so out loud rather than resting on it. What moved:
the ray exit from 22 to 25, and the bounding box's x-max from 25 to 20. The
overhang is gone.

The equivalence is the ground truth stated as a test: an oblique move and its
normal component now return the same solid on volume, on all six extents, and
on two rays. And the continuity probe is the sentence I would put to anyone who
thinks the old behaviour was defensible: **a 5 mm change in the answer for a
0.001 mm change in the input.**

### 2.5 Defect 3 — the chamfer guard, repaired

`angle_deg[i] >= limit`, where `limit` is the edge's own turn angle.

```
[40j] theta=60 edge (bound 120): alpha=80 -> built | alpha=100 -> built |
      alpha=110 -> built | alpha=125 -> refused | mode1 (d2=5.758770) -> built
[40j] mode1 removed 99.744831 (analytic 99.744831)
[40j] mode2 alpha=100 removed 99.744831 — the same chamfer, the spelling that
      used to be REFUSED
[41a] theta=135 edge (bound 45): alpha=30 -> built | alpha=60 -> refused
      (chamfer angle must be in (0, 45) deg on this edge: its faces meet at
       135 deg …)
[41a] alpha=30 removed 54.641016 (analytic 54.641016, d2 = 3.863703)
```

The strongest line in this session's output is the third one. S16 could only
*print* that divergence, because one of the two spellings of that chamfer was
refused; now both build and remove **the same 99.744831**, to 1e-9. Two
spellings of one chamfer, agreeing.

[41a] is the half S16 derived and did not measure, and it comes out as derived:
on a 135° edge the old guard passed α = 60 through to OCCT, which would have
been handed `dis2 = −6.692130`. It is now refused by the guard, naming 45.

---

## 3. What a caller sees differently — `occt_shim_version()` 27 → 28

The note in `occt_capi.cpp` is the normative version; this is the summary.

| | What changed | What can see it | What cannot |
| --- | --- | --- | --- |
| coil `clockwise = 1` | rises by `height` and is left-handed, instead of descending to `[-height, 0]` right-handed | the bounding box; a ray at a fixed azimuth | **volume — identical to the last bit, before and after** |
| `occt_move_faces`, oblique delta | returns the same solid as the delta's normal component; no overhang, no notch | the bounding box (x-max 25 → 20); a ray (22 → 25) | **volume (10 000 both ways) and `BRepCheck_Analyzer` (valid both ways)** |
| `occt_chamfer_edges` mode 2 | accepts `0 < angle < 180° − θ` = `edge_info[10]`, instead of `< 90` | whether the call is refused, and the message | a solid that was already building — **every perpendicular edge is bit-identical** |

The third cuts **both ways** and a caller should know which half it depends on:
an acute edge now accepts angles that used to be refused, and an **obtuse** edge
now refuses angles that used to be passed to OCCT and to fail there. If your
part is prismatic and every chamfered edge is square, nothing changes at all.

---

## 4. What I changed that was not one of the three

`occt_version()`'s string now **asks** `occt_shim_version()` instead of
repeating it. The comment there already recorded that it had said `"v21"` while
the number went 22, 23 — and it had drifted again: this session's first green
run printed `Prototype OCCT shim v27 (OCCT 7.9.3) (shim ABI v28)`, and the
differential in §2.1 is what surfaced it, since it was the one line that
differed. "Kept in step" is a promise a literal cannot make. The CI link
check's grep marker `"Prototype OCCT shim"` is still a single literal, which is
all it needs.

This is inside `backend/occt/shim/**` and it is three lines. I would not have
gone looking for it; the differential handed it to me.

---

## 5. Findings I am routing rather than fixing

### 5.1 Dart's chamfer "Flip" has the same hardcoded 90

`part_model.dart:3707`:

```dart
2 => (distance1, 0.0, flip ? 90.0 - angleDeg : angleDeg),
```

Flip swaps which face the chamfer is measured from, so the flipped angle is the
triangle's **third** angle, `180° − θ − α`. `90 − α` is that only when θ = 90.
It is the identical defect to §0.3, one layer up, and it follows directly from
the same triangle — I would not have looked for it if the header had not
mentioned Flip while I was reading the reference-face paragraph.

**Not mine.** The brief freezes the Dart side and the delta is meant to be
structurally zero. Consequence of v28, which is an improvement and should be
said plainly: on a non-perpendicular edge a flipped mode-2 chamfer now draws a
**clear refusal from the shim's guard** — naming the edge's real bound —
instead of a wrong chamfer or a bare OCCT failure. So the Dart bug is now
loud rather than silent, which is the right order to fix things in.

### 5.2 `occt_move_faces` on a non-planar face is still ill-posed

Stated in R2 before the fix and unchanged by it. `face_outward` samples the
mid-parameter normal; projecting an oblique delta onto one representative
normal of a cylinder is exactly as arbitrary as sweeping the whole delta was.
I did not fix it, test it, or claim it, and both the header and the `.cpp` now
say so where a reader will hit them. It is a real empty region on S16's map
that S16 did not name because it was auditing directions, not face types.

---

## 6. What I deliberately did not do

* **Did not touch `finish_pipe`.** The coil fix is in the spine's `(u,v)`
  direction, upstream of `BRepOffsetAPI_MakePipeShell`. The brief's
  stop-and-write-it-up condition for shared infrastructure never fired.
* **Did not touch any Dart file**, including the Flip bug above.
* **Did not implement the walls-follow face move.** §0.2 argues it is a
  different operation; §7.1 is my honest residual doubt about that.
* **Did not close S16's three "still untested" rows** (`closed`, `taper_deg`,
  `out_dropped`/`out_scale`). They are outside the three defects and the brief
  said those three and only those three.
* **Did not add a planarity guard to `occt_move_faces`** (§5.2). It would be a
  fourth behaviour change nobody asked for.

---

## 7. What I am unsure of

1. **Whether 25 is right and 10 is wrong — the one that matters.** §0.2 makes
   three arguments and I believe all three, but they are arguments from *this
   repository's* commitments — the skip already in the loop, the Dart model's
   refusal to ship surface-sliding, and the well-definedness of the projection
   — and not from a reference implementation. I have no Inventor here, exactly
   as S16 did not. If someone establishes that Inventor's Direct > Move tilts
   the neighbouring walls, then the right answer is that this app's
   `occt_move_faces` is a *different operation from Inventor's* and should
   probably be renamed, **not** that v28 is wrong: the leaning prism would
   still be nobody's answer, and the projection is still what the loop's own
   skip commits it to. That is the strongest form in which I can state my
   confidence, and it is deliberately weaker than "this is what a CAD system
   does".
2. **The severity of defect 2 is still latent, and I did not re-check it.**
   S16 established that `setFaceEditValue` has no caller and the UI does not
   yet offer a free direction. I took that at face value rather than
   re-deriving it. If S16 was wrong about that, defect 2 was shipping.
3. **Whether the fallback in the chamfer guard is the right fallback.** An edge
   whose bound cannot be measured keeps the historical 90. That is the
   conservative choice and it preserves today's behaviour exactly, but I could
   not construct a case that takes it — every edge in every fixture has two
   faces and evaluable normals. **It is therefore untested code**, and the one
   piece of this session's diff I cannot show working. A tangent-face edge
   (`deg <= 1e-9`) is the case I expect would take it, and I did not build one.
4. **Whether `edge_info[10]` and the chamfer bound stay the same number.** They
   are computed by the same helper at the same arc-length midpoint *today*,
   which is why I wrote it that way. But they are two call sites, not one
   function, and nothing tests that they agree — [40j] and [41a] select their
   edges by `info[10]` and then rely on the guard computing the same thing, so
   a divergence would show up as a mysterious refusal rather than as a clear
   failure. A test that asserts `limit == info[10]` directly would cost five
   lines and I did not write it.
5. **Curved edges.** Every edge in every fixture here is straight, so the
   dihedral is constant along it. On a curved edge θ varies and the guard
   measures it at one point — the arc-length midpoint. An angle legal at the
   midpoint and illegal at one end would pass the guard and fail in OCCT. This
   is the same shape of assumption `edge_info[10]` has always made and I did
   not widen it, but the guard now *acts* on that number where before it only
   reported it, which raises the stakes.
6. **The Dart side is unverified in this environment.** Flutter is not
   installed here, so `flutter analyze` and `flutter test` could not be run.
   The diff touches **no `.dart` file at all** (`git diff --name-only`: five
   files, three C/C++, two Markdown), so the analyze delta is **structurally
   zero rather than measured zero**. I would rather say that than claim a green
   I did not see — the same words S16 used, for the same reason.

---

## 8. Definition of done

| | |
| --- | --- |
| Mechanism named for each of the three, from source | **§0.1** `ElSLib::CylinderD0` + `gp_Ax3.hxx:83`; **§0.2** the loop's own skip vs `BRepSweep_Prism.cxx:34,128`; **§0.3** `ChFiKPart_ComputeData_ChAsymPlnPln.cxx:115` |
| Predictions committed before the code | `a9d7ddd` (§0–§1), before the first line of the fix. One was **refuted** — §2.2 — and the refutation is recorded, not quietly dropped |
| Each fixture converted to assert ground truth | **[40d] [40i] [40j]**, plus **[41a] [41b] [41c]** new. Each would now fail if its defect returned |
| `occt_smoke` on real OCCT 7.9.3 | **PASS**, built from the pinned submodule `a016080` on this machine |
| `gcc -fsyntax-only -I backend/occt/shim backend/occt/tests/smoke_occt.c` | run before every commit that touched `smoke_occt.c`, and again before the push. It never caught anything, which is the point of a check that costs one second — and note it checks the C fixture only, not the C++ shim, so it is a brace guard and not a build |
| `occt_mesh_recon_test` | **86 passed, 0 failed** |
| `python3 -m unittest discover -s ci` | **52 tests, OK** |
| Differential, old against new, no golden | **§2.1** — pre-S17 tree built and run here; every line outside the six fixtures identical |
| One commit per defect, independently revertible | **verified by actually reverting each one** — all three apply cleanly on their own |
| `occt_shim_version()` | **27 → 28**, its own commit, with what a caller learns in §3 and in the source note |
| `analyze` delta | **structurally zero — no `.dart` file in the diff.** Stated, not measured; Flutter is absent here (§7.6) |
| S16's inventory table | three rows now read **correct**, with the disagreement carried forward rather than erased |
