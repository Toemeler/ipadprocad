# S18 — the drawn corner, and the taper that comes out invalid

Owns: `backend/occt/shim/**`, `backend/occt/tests/**`, `backend/bench/**`,
`perf/findings/S18-corners.md`. Scenario number allocated: **[42]**.
Frozen and untouched: `frontend/lib/perf*.dart`, `perf/baseline.json`,
`PERFORMANCE_PROFILE.md`.

---

## 0. What the repository actually contains, which is not what the brief says

Recorded first because every number below depends on it and because a session
that quietly worked around it would be lying by omission.

The brief says S15 (v27, holed assembly) and S17 (v28) are merged, that
`occt_shim_version()` is **28**, and that the taper defect is visible in the
smoke log today as `[39b] tapered tube, tilted arc, POLY: ... tube INVALID`.

On `main` at `2de4e97`, which is what this branch was cut from:

| the brief says | the repository says |
| --- | --- |
| `occt_shim_version()` == 28 | **26** (`occt_capi.cpp:277`), and the version log ends at the v26 note |
| S15-holes.md §4 to be read first | `perf/findings/` has no `S15-holes.md` and no `S17-*.md` |
| smoke scenario `[39b]` | the smoke file's scenario tags stop at **[38]**; there is no [39], [40], [41] |
| branch from `claude/perf-opt2` | neither `claude/perf-opt2` nor `claude/perf-opt3-corners` exists on the remote |

So S15's and S17's work is **not** in this tree. What IS in this tree is S14
complete — v24 (`occt_sweep_profile_ex`, the `OCCT_SWEEP_PATH_*` modes and the
smoothed spine), v25 (orientation 1 stops calling `GeomFill_ConstantBiNormal`)
and v26 (a hole is placed the way its own body is placed) — plus smoke [37] and
[38].

Consequences, all of them deliberate:

* This session develops on `claude/s18-corners-taper-j2cqqo`, which is the
  branch the harness assigned, and does not invent the two branches the brief
  names. Nothing is pushed anywhere else.
* The next free shim version is **27**, not 29. If ABI surface is added it
  takes 27, and the note says what a caller learns by testing for it.
* Scenario **[42]** is still used as allocated. Numbers [39]–[41] are left
  unused rather than back-filled: the brief says three identifier collisions
  have already happened here, and closing a gap is how the fourth one starts.
* **The taper defect has to be reproduced from scratch**, because the smoke
  line that is supposed to show it does not exist here. Item 2's pre-registration
  below is therefore a prediction about a defect I have read the mechanism of
  but have not yet seen fail. That is a weaker position than S15's and it is
  stated as such.

Everything the brief says about S14 checks out against the file, including the
six-lever table and the five-row convergence table, which is what §1 is built
on.

---

## 1. Pre-registration — item 1, the drawn corner

**Registered before any instrument was written and before a line of shim or
bench code was touched.** Committed in this state; the code follows in a later
commit.

The brief's step 1 is "get an analytic ground truth for a shallow drawn joint",
and its step 2 is "derive the crossover, do not fit it". Both are done here, on
paper, from `BRepFill` source rather than from the five measured rows — and
then P1..P5 stake the derivation against measurement.

### 1.0 The fixture, in exact numbers

`L(theta, L1, L2)` — smoke scenario [30]'s L-path, generalised so the joint
angle is a parameter:

```
profile : the square [0,10] x [0,10] in the z = 0 plane
          A  = 100                    (area)
          c  = (5, 5, 0)              (centroid, in the profile's own plane)
spine   : (0,0,0) -> (0,0,L1) -> (0,0,L1) + L2*(sin theta, 0, cos theta)
          u1 = +Z,  u2 = (sin theta, 0, cos theta),  joint angle = theta
call    : occt_sweep_profile(..., orientation 0, taper 0, twist 0)
          => Frenet, WithContact = False, WithCorrection = False
```

The turn is toward **+X**, so the quantity that matters is the centroid's
offset **along the turn direction**:

```
c_t = c . (+X) = 5
```

`[30]` itself is `L(90 deg, 40, 30)`. Its straight arm is `A * L1 = 4000`,
which the shipped smoke test already pins.

### 1.1 The two closed forms, derived

**RightCorner (`BRepFill_Right`).** `BRepFill_LocationLaw::TransformInCompatibleLaw`
sets, at each joint, `Trsf = rotation about the local OZ` — and the frame's
local OZ **is the tangent** (`GeomFill_CurveAndTrihedron::D0` builds
`M.SetCols(Normal, BiNormal, Tangent)`). A rotation about the tangent cannot
change the tangent, so the section stays perpendicular to whichever leg it is
on: this is parallel transport. The two legs are therefore right prisms, and
`BRepFill_Sweep::PerformCorner` mitres them at the bisector plane.

Put the vertex at the origin. The bisector plane's unit normal is

```
n = (u1 + u2)/|u1 + u2| = (sin(theta/2), 0, cos(theta/2)),
u1 . n = u2 . n = cos(theta/2)
```

A point of the section at the vertex is `x = s*u1 + p`; the cut is at
`s = -(p.n)/(u1.n)`. Integrating over the section, with `C1 = c` expressed in
leg 1's frame and `C2 = R_theta c` in leg 2's:

```
V1 = A*L1 - A*(C1.n)/(u1.n) = A*L1 - A*c_t*tan(theta/2)
V2 = A*L2 + A*(C2.n)/(u2.n) = A*L2 - A*c_t*tan(theta/2)
```

(`C2.n = -c_t*sin(theta/2)` because `R_theta` carries the offset with the
frame; the two terms are equal, which is the miter's symmetry.)

```
  V_miter(theta) = A*(L1 + L2) - 2*A*c_t*tan(theta/2)                  (I)
```

Note what (I) says when `c_t = 0`: **a mitred sweep of a section centred on its
spine has volume `A * L_polyline`, exactly, at every joint angle.** The wedge
is entirely an effect of the centroid being off the path.

**Transformed (`BRepFill_Modified`).** `BRepFill_LocationLaw::TransformInG0Law`
sets `Trsf = M2^-1 * M1` and `GeomFill_CurveAndTrihedron::D0` applies it as
`M = frame * Trsf`. On a straight edge the frame is constant, so edge 2's frame
becomes `F2 * F2^-1 * F1 = F1`: **the section keeps edge 1's orientation.** It
is not swept round the corner at all; it is translated. Leg 2 is therefore an
*oblique* prism whose base is not perpendicular to it, and an oblique prism of
base area `A` and axis `d` has volume `A*|d.m|` with `m` the base's normal:

```
  V_trans(theta) = A*L1 + A*L2*cos(theta)                              (II)
```

### 1.2 Both forms reproduce S14 §2.6's table with nothing fitted

`A = 100, L1 = 40, L2 = 30, c_t = 5`, so (I) is `7000 - 1000*tan(theta/2)` and
(II) is `4000 + 3000*cos(theta)`:

| theta | (I) predicts | S14 measured | (II) predicts | S14 measured |
| ---: | ---: | ---: | ---: | ---: |
| 2 deg | 6982.544935 | 6982.545 | 6998.172481 | 6998.172 |
| 5.625 deg | 6950.873150 | 6950.873 | 6985.554180 | 6985.554 |
| 15 deg | 6868.347502 | 6868.348 | 6897.777479 | 6897.777 |
| 45 deg | 6585.786438 | 6585.786 | 6121.320344 | 6121.320 |
| 90 deg | 6000.000000 | 6000.000 | 4000.000000 | **3200.000 INVALID** |

Nine of the ten cells agree to the last digit S14 printed. Nothing here was
tuned: `A`, `L1`, `L2` and `c_t` are read off scenario [30] and the two
formulae come out of the two OCCT transform functions. The tenth cell is the
one OCCT itself reports invalid, and (II) says why — at 90 deg the leg-2 prism
is degenerate (`cos 90 = 0`), the shell passes through itself, and `GProp`'s
number stops being a volume.

### 1.3 The answer to the question the five rows do not answer

Expand both about `theta = 0`:

```
V_miter = A*L - A*c_t*theta          + O(theta^3)
V_trans = A*L - A*L2*theta^2/2       + O(theta^4)
```

The corner's true effect is **first order** in the joint angle. `Transformed`
has **no first-order term at all**. It does not approximate the corner badly at
shallow angles; it supplies none of it, at every angle, and adds a spurious
second-order term of its own. The two converge only because the thing they
disagree about goes to zero.

So the expected answer to "at a shallow joint, which of the two is correct?" is
**RightCorner, at every joint angle**, and `Transformed` is a lever that cannot
be pulled at any threshold. P1-P5 are the attempt to refute that.

### 1.4 The crossover is derived — and it is a property of the fixture

Setting (I) = (II):

```
2*A*c_t*tan(theta/2) = A*L2*(1 - cos theta) = A*L2*2*sin^2(theta/2)
        c_t = L2*sin(theta/2)*cos(theta/2)
=>  sin(theta_cross) = 2*c_t / L2                                     (III)
```

With `c_t = 5, L2 = 30`: `sin theta = 1/3`, `theta_cross = 19.4712 deg` — which
is exactly where S14's table changes sign, between the `+0.43 %` at 15 deg and
the `-7.1 %` at 45 deg.

(III) contains `c_t` and `L2`. It does not contain anything about corner
treatment. **The crossover is where two unrelated errors happen to cancel for
one fixture, and it moves when the fixture moves** — halve the second leg and
it goes to 41.81 deg, double it and it goes to 9.59 deg. That is the whole
reason a threshold must be derived rather than read off five rows: read off,
this one looks like a property of the kernel; derived, it is a property of the
square's centroid and the length of the second leg.

### Prediction P1 — the miter closed form is exact

```
Target        : occt_sweep_profile on L(theta, 40, 30), orientation 0, no taper.
Baseline      : none. This is an analytic pin, not a recorded golden - it is
                computed in the test from A, L1, L2, c_t and theta.
Mechanism     : section 1.1 (I). Parallel transport keeps the section
                perpendicular to each leg; PerformCorner cuts at the bisector.
Predicted     : V = 100*70 - 1000*tan(theta/2) to within 1e-6 RELATIVE at
                theta in {2, 5.625, 15, 45, 90}, and the solid is VALID at all
                five.
Derivation    : 6982.544935 / 6950.873150 / 6868.347502 / 6585.786438 /
                6000.000000.
Falsifiable by: any of the five off by more than 1e-6 relative, or any invalid.
                A miss at 90 deg alone would say PerformCorner is not a
                bisector cut; a miss that grows with theta would say the
                transport is not parallel.
```

### Prediction P2 — the Transformed closed form is exact wherever the solid is valid

```
Target        : the same fixture, BRepFill_Modified, through the Lane C replica.
Predicted     : V = 4000 + 3000*cos(theta) to within 1e-6 relative at
                theta in {2, 5.625, 15, 45}, all four VALID;
                and at theta = 90 the solid is INVALID, so the closed form does
                NOT apply and the measured number is whatever GProp makes of a
                self-intersecting shell (S14 got 3200).
Derivation    : 6998.172481 / 6985.554180 / 6897.777479 / 6121.320344.
Falsifiable by: a valid solid at 90 deg (then (II) is wrong about degeneracy),
                or any of the four shallow rows off by > 1e-6 relative.
```

### Prediction P3 — Transformed's error IS the corner, at every angle

```
Target        : V_trans - V_miter on the same runs.
Mechanism     : section 1.3. (II) has no O(theta) term.
Predicted     : V_trans - V_miter = 2*A*c_t*tan(theta/2) - A*L2*(1 - cos theta)
                measured to 1e-6 relative of the miter volume:
                  theta = 2      : +15.6275
                  theta = 5.625  : +34.6810
                  theta = 15     : +29.4300
                  theta = 45     : -464.4661
                and the RATIO of Transformed's error to the corner's own
                effect (A*c_t*theta, the first-order wedge) tends to 1 as
                theta -> 0, not to 0:
                  theta = 5.625 : |34.681| / 49.127 = 0.706
                  theta = 2     : |15.628| / 17.455 = 0.895
                  theta = 0.5   : ratio 0.973 (predicted, not in S14's table)
Falsifiable by: that ratio falling toward 0 as theta shrinks. That would mean
                Transformed does converge on the truth and a threshold exists.
                This is the prediction the whole session turns on.
```

### Prediction P4 — the crossover moves with the fixture, exactly as (III) says

```
Target        : the joint angle at which V_trans - V_miter changes sign,
                measured by bisection on theta, at three second-leg lengths.
Predicted     : L2 = 15 -> 41.8103 deg
                L2 = 30 -> 19.4712 deg   (S14's fixture)
                L2 = 60 ->  9.5941 deg
                each within 0.05 deg.
Derivation    : theta = asin(2*c_t/L2) with c_t = 5.
Falsifiable by: a crossover that stays near 19.47 deg when L2 moves. That would
                make it a property of the corner treatment after all, and would
                reopen the dispatch idea.
```

### Prediction P5 — Transformed does not rotate the section ONCE, and the error compounds

```
Target        : a 3-edge staircase, L1 = 40 then L2 = 30 then L3 = 30, two
                joints of theta = 15 deg turning the same way, in both modes.
Mechanism     : TransformInG0Law computes M1 from the PREVIOUS law's D0, which
                already carries that law's own Trsf. So edge 3's frame is
                F3 * F3^-1 * F1 = F1 as well: every edge of a polyline spine
                carries edge ONE's frame. The tilt accumulates.
Predicted     : Transformed = A*(L1 + L2*cos theta + L3*cos 2*theta)
                            = 9495.8537        <- compounding
                NOT           A*(L1 + L2*cos theta + L3*cos theta)
                            = 9795.5550        <- if it re-based per joint
                RightCorner = A*(L1+L2+L3) - 2*A*c_t*(tan(t/2) + tan(t/2))
                            = 9736.6950
                The two Transformed candidates differ by 300 on 9500 (3.2 %),
                so the measurement separates them without ambiguity.
Falsifiable by: 9795.55. That would mean the mode is only ever one joint wrong
                and a shallow-joint dispatch is worth a second look.
Consequence if HELD: a 64-sample arc swept in Transformed mode never turns its
                section at all, so the mode is not merely inaccurate at a
                corner - it is unusable on exactly the paths S14 made cheap.
```

### Prediction P6 — S14 section 2.8's unexplained identity is Cavalieri, and the exponent is not the point

```
Target        : the arc fixture of S14 section 2.8 - a 128-gon of circumradius 6
                centred ON the spine, swept along arcPathXYZ(spans+1, 60).
Mechanism     : the ring's centroid is on the path, so by (I) with c_t = 0 the
                miter has NO corner correction at any span count. The section
                normal starts at +Z; the path's z rises by exactly 60.
Predicted     : V = A(128-gon) * 60 = 113.0519216503711 * 60
                  = 6783.115299, matching S14's measured 6783.1153 to every
                digit it printed - and BETTER than S14's own
                "A * L_true * cos 25.2316 deg" = 6782.86, which is off in the
                fifth figure.
                It holds at EVERY span count and in BOTH corner modes, which is
                what S14 observed and could not derive.
Falsifiable by: the identity tracking L_true rather than delta-z when the path
                is changed to one with the same length and a different rise.
                That test is the discriminator and it is cheap.
```

---

## 2. Pre-registration — item 2, the taper defect

Item 2 outranks item 1: it is a wrong part in a file this session owns.

### 2.0 What is actually claimed, and what I have read

The brief: *a tapered sweep along a spine of more than one edge produces an
INVALID solid*. The smoke line that shows it is not in this tree (section 0),
so this is a prediction about a failure I have not yet seen.

What the taper is, in the shim (`occt_capi.cpp`, `occt_sweep_profile_ex` and
`finish_pipe`):

```
Handle(Law_Linear) law = new Law_Linear();
law->Set(0.0, 1.0, 1.0, 1.0 + k);        k = tan(taper_deg)
mk.SetLaw(outer, law, Standard_False, correct);
```

The two mechanisms this could be, read from OCCT source before measuring:

**(a) the law restarts on every spine edge.** `BRepFill_ShapeLaw` wraps the
profile in a `GeomFill_EvolvedSection` per profile edge, and
`GeomFill_EvolvedSection::D0` scales the poles by `TLaw->Value(U)`. If `U` were
each spine edge's own parameter, the scale would run 1 -> 1+k on edge 1 and then
jump back to 1 at the start of edge 2. Two shells of different radius meeting at
a vertex is exactly an invalid solid.

**(b) something else.** `BRepFill_Sweep::Build` has, for the non-constant
section case only:

```
myLoc->CurvilinearBounds(myLoc->NbLaw(), SecDom, Length);
mySec->Law(1)->GetDomain(SecDeb, SecDom);  SecDom -= SecDeb;
...
Vi(ipath+1) = SecDeb + (Ll / Length) * SecDom;
Sweep.SetDomain(lf, ll, Vi(ipath), Vi(ipath+1));
```

`Ll` is the cumulative curvilinear length at the end of edge `ipath` and
`Length` the whole spine's. That is precisely the arc-length distribution of the
law across a multi-edge spine, and `constSection` is `mySec->IsConstant()`,
which is `TheLaw.IsNull()` — false whenever a law is set. So (a) *should* not
happen.

### Prediction P7 — the taper defect is real, and it is NOT a law restart

```
Target        : occt_sweep_profile with taper_deg != 0 on a 2-edge spine.
Predicted     : (1) a 1-edge (straight, 2-point) tapered sweep is VALID and its
                    volume is the analytic frustum
                      V = A * L * (1 + k + k^2/3)
                    for a square section scaled about the profile origin;
                (2) a 2-edge spine with a tapered profile produces an INVALID
                    solid - the defect reproduces;
                (3) and the scale is nevertheless CONTINUOUS across the joint:
                    an occt_ray_hits probe fired across the spine just before
                    and just after the joint gives radii whose ratio is
                    1 + O(1e-6) of the arc-length-interpolated law, NOT 1 + k.
                    So mechanism (a) is refuted and the cause is elsewhere.
Falsifiable by: a radius that drops by a factor of 1+k across the joint, which
                would make it (a) after all and the fix a one-line domain fix;
                or a 2-edge tapered sweep that is simply VALID, which would mean
                the defect needs a curved or holed spine to appear and my
                reproduction is too simple.
Note          : (1) is a genuine analytic pin. A Law_Linear on the poles scales
                the section about the PROFILE'S ORIGIN, not its centroid, so a
                square [0,10]^2 tapered by k grows to [0,10(1+k)]^2 and the
                integral of the area is A * L * (1 + k + k^2/3). If the
                measurement says A*L*(1+k)^2 or A*L*(1+k+k^2/3) is wrong by the
                cross-term, the scaling centre is not the origin and every
                number in this section moves.
```

### Prediction P8 — no fix ships that I cannot pin analytically

```
This is a rule, registered as a prediction so that breaking it is visible:
whatever the cause of P7(2) turns out to be, a repair only ships if the
repaired solid is VALID and its volume matches a closed form computed in the
test from the fixture's own numbers. If the cause is in OCCT rather than in the
shim, the deliverable is the diagnosis and a refusal, not a workaround that
makes BRepCheck_Analyzer happy.
```

---

## 3. What would make me stop

The brief names it and it is worth restating in my own words before I have any
data: if P1..P5 hold, `Transformed` is wrong at every joint angle, there is no
threshold to derive, and item 1 ends with the lever closed rather than pulled.
That is the outcome section 1.3 predicts. The bar — "512 segments on a 3-corner
path should stop being 79 seconds" — would then be **unmet**, and the honest
report is that a drawn corner is genuinely expensive, not accidentally
expensive.

Sections 4 onward are written after the measurements.
