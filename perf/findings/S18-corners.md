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

---

# What was measured

Everything below ran on real **OCCT 7.9.3** (the pinned `V7_9_3` submodule,
built here with `VENDOR.md`'s exact configure line) on a shared four-core
container. Lane C's rule holds: **ratios, exponents and volumes transfer; the
milliseconds do not.**

## 3. Adjudication — item 1

| | prediction | outcome |
| --- | --- | --- |
| **P1** | the mitre closed form (I) | **HELD**, exactly |
| **P2** | the Transformed closed form (II) | **HELD**, exactly |
| **P3** | Transformed's error IS the corner | **HELD in substance, REFUTED in its one number** |
| **P4** | the crossover is `asin(2*c_t/L2)` | **HELD**, to 0.0003 deg |
| **P5** | Transformed's tilt COMPOUNDS | **HELD**, exactly |
| **P6** | S14 §2.8's identity is `A*dz` | **HELD**, and it closes S14 §7.2 |

### 3.1 P1 and P2 — both closed forms are exact, to the last bit

`L(theta, 40, 30)`, the square at `x in [0,10]` so `c_t = 5`, declared POLY:

```
theta      RightCorner        (I)          rel    | Transformed       (II)         rel
0.5000     6999.885769   6995.636649  +6.07e-04   |  6999.885769   6999.885769  -2.60e-16
2.0000     6982.544935   6982.544935  -1.30e-16   |  6998.172481   6998.172481  +2.60e-16
5.6250     6950.873150   6950.873150  -1.31e-16   |  6985.554180   6985.554180  +0.00e+00
15.000     6868.347502   6868.347502  +1.32e-16   |  6897.777479   6897.777479  -2.64e-16
19.4712    6828.427125   6828.427125  +1.33e-16   |  6828.427125   6828.427125  +2.66e-16
45.000     6585.786438   6585.786438  +0.00e+00   |  6121.320344   6121.320344  -4.46e-16
90.000     6000.000000   6000.000000  +0.00e+00   |  3200.000000   4000.000000  -2.00e-01 INVALID
```

`-1.30e-16` is one unit in the last place of a double. **Neither of these is a
fit.** Both were written down from `BRepFill_LocationLaw`'s two transform
functions before the kernel was built, and they are checked against numbers the
test computes from `A`, `L1`, `L2`, `c_t` and `theta`.

Two rows are worth reading twice.

**The 90 deg Transformed row is the prediction, not a miss.** (II) says the
leg-2 prism is degenerate at 90 deg (`cos 90 = 0`); OCCT reports the solid
INVALID; and `GProp`'s 3200.000000 — S14's number, reproduced — is the
algebraic integral over a shell that passes through itself, not a volume. P2
predicted exactly this and it is why the closed form is stated as applying
*wherever the solid is valid*.

**The 0.5 deg RightCorner row is where the mitre stops being a mitre.**
`BRepOffsetAPI_MakePipeShell` hard-codes `angmin = 1.0e-2` rad = **0.5730 deg**,
and below it `PerformCorner` says "This is not a corner" and does nothing. So at
0.5 deg RightCorner returns **6999.885769 — which is (II) to the last bit**, not
(I). The shipped mitre *becomes* Transformed below the deadband. That is an
independent confirmation of (II) through the shipped ABI, at an angle nobody
chose for it.

### 3.2 P3 — the answer to the question S14's five rows could not answer

The corner's own first-order effect is `A*c_t*theta`. What fraction of it does
`Transformed` get wrong?

```
theta      V_trans - V_mitre    A*c_t*theta    share
0.4000        +0.000000            3.490659    0.000   DEADBAND
0.5000        +0.000000            4.363323    0.000   DEADBAND
0.6000        +5.071544            5.235988    0.969   mitred
1.0000        +8.269953            8.726646    0.948   mitred
2.0000       +15.627546           17.453293    0.895   mitred
5.6250       +34.681030           49.087385    0.707   mitred
15.000       +29.429976          130.899694    0.225   mitred
```

**In the whole regime where a corner is treated at all, `Transformed` misses
between 22 % and 97 % of it — and the SHALLOWER the joint, the LARGER the
fraction it misses.** The share rises toward 1 as the angle falls to the
deadband. It does not converge on the truth; the truth converges on it, because
the corner it is failing to make is itself vanishing.

Expanding both closed forms says why in one line:

```
V_mitre = A*L - A*c_t*theta      + O(theta^3)
V_trans = A*L - A*L2*theta^2/2   + O(theta^4)
```

`Transformed` has **no first-order term at all**. The corner is first order.
There is no shallow-joint regime in which it is right, and therefore no
threshold to dispatch on. **The lever is closed.**

**P3 is refuted in one specific number and I am recording that, because the
reason is the interesting part.** I predicted a share of 0.973 at 0.5 deg. The
measurement is **0.000**, because 0.5 deg is inside OCCT's deadband, where
RightCorner does not mitre either and the two modes agree bit for bit. I had the
limit right and forgot there is a floor under it. The corrected statement is
sharper than the one I registered: the share rises to 0.969 at the deadband edge
and then falls off a cliff to zero, because below 0.5730 deg *both* modes are
Transformed.

### 3.3 P4 — the crossover is a property of the fixture, measured

Bisected on the MEASURED difference between the two modes, not on the formulae:

```
L2      predicted asin(2*c_t/L2)     measured        delta
15.0            41.8103 deg        41.8106 deg     +0.0003
30.0            19.4712 deg        19.4715 deg     +0.0003
60.0             9.5941 deg         9.5941 deg     +0.0000
```

S14's table changes sign between its 15 deg and 45 deg rows. That sign change is
**19.4712 deg = asin(1/3)**, and (III) contains `c_t` and `L2` and nothing about
corner treatment. Change the second leg and the "threshold" moves by more than
30 degrees. It is the angle at which two unrelated errors happen to cancel for
one L-shape — which is precisely the kind of number the brief says this project
has repeatedly refused to ship, and now there is a derivation showing why.

**The instrument was wrong first, and that is worth recording.** The first run
reported "no sign change bracketed" at all three leg lengths. The bracket
started at 0.25 deg — inside the deadband, where the difference is *exactly*
0.0, so the bisection saw no sign to change. The formula was right and the
measurement of it was not; `cornerCrossoverDeg` now refuses a bracket whose end
is an exact zero and says why.

### 3.4 P5 — `Transformed` never rotates the section, and it compounds

Three legs, two joints of 15 deg the same way:

```
mitre         9736.695005   (I) 9736.695005          valid
transformed   9495.853690   compounding  9495.853690  <-- measured
                            per-joint    9795.554958      (300 away)
```

`TransformInG0Law` computes each joint's transform from the **previous law's own
D0**, which already carries that law's transform. So edge 3's frame is
`F3 * F3^-1 * F1 = F1`: **every edge of a polyline spine carries edge ONE's
frame.** The section is translated along the path and never turned.

The consequence is worse than the volume error. A 64-sample arc swept in
`Transformed` mode would keep its section at the starting orientation for the
whole arc — 90 degrees out by the end of a quarter turn. The 17.5x lever is not
merely inaccurate at a drawn corner; it is unusable on exactly the sampled paths
v24 made cheap. And on this fixture it comes back **valid**, so nothing would
have caught it.

### 3.5 P6 — S14 §2.8's identity, closed

S14 could not derive why `V = A(n)*L*cos 25.2316 deg` holds with `L` the TRUE
arc length rather than the polyline's, at every span count and in three corner
modes, and put it in its §7 as the second most expensive thing it might be wrong
about. It is Cavalieri, and the right form is simpler:

```
spans   measured        A*dz            rel        A*L_poly*cos(tilt)   rel
 2      6783.115299   6783.115299   +4.02e-16      6752.008242      +4.61e-03
 4      6783.115299   6783.115299   -9.39e-16      6775.231327      +1.16e-03
16      6783.115299   6783.115299   -1.39e-14      6782.620451      +7.30e-05
```

The ring is centred on the spine, so `c_t = 0` and by (I) the mitre has **no
wedge at any span count** — which is the identity's "at every sampling density".
The section's normal starts at +Z and the path rises exactly 60, so
`V = A * dz` and the span count cannot touch it. S14's form agrees only because
that helix has a constant pitch angle, and it is wrong in the fifth figure.

Confirmed a third time, on a different section: a CENTRED 10x10 square on the
same 16-edge polyline arc gives **6000.000000** against `A*dz = 100*60`.

### 3.6 What it costs, and the bar

`sweep.corners` — an N-segment ring over a path with three DRAWN 90 degree
corners, through the shipped `occt_sweep_profile`:

```
segments      ms      fitted exponent k = 1.392  [1.314, 1.471]  R2 = 0.9983
      32    61.3
      64   152.2      local k: 32->64  1.31
     128   383.9              64->128  1.33
     256  1124.1             128->256  1.55
     512  3103.7             256->512  1.47
```

**The bar is not met, and it cannot be met by the lever that was left open.**
512 segments over three drawn corners is 3.1 s here. Applying S14's measured
desktop:device factor of 3.4 puts that near 10 s on the device, not 79 s — so
either the device's 3-corner fixture is not this one (a holed profile would do
it: S14 §4.1 measured a hole at 80x) or the factor is larger on this operation.
**I cannot resolve that without a device and I am not going to guess.** What I
can say is what scales: the exponent is ~1.4 here and rising with N, the cost is
per corner and per segment, and nothing in v24..v27 touches it.

### 3.7 The one route the derivation opens, prototyped and refuted

If the mitre is a cut at the bisector plane — and §3.1 says it is, to the last
bit — then it need not go through `BOPAlgo_PaveFiller` over two whole shells.
Each leg could be swept on its own single-edge spine (no joint, no corner cost)
and trimmed with a bisector half-space, then fused. That is the only idea the
derivation produces and it deserved a number rather than a paragraph.

Prototyped and measured, same fixture, same machine, same run:

```
N segments   shipped        bisector route     ratio
      32      69.0 ms         157.7 ms         0.44x
      64     105.6 ms         302.3 ms         0.35x
     128     327.0 ms         683.7 ms         0.48x
     256    1023.0 ms        1949.3 ms         0.52x
     512    3106.7 ms        4677.6 ms         0.66x
```

**It is 1.5x to 3x SLOWER**, and the prototype's volume is wrong as well (it
under-trims one side of each joint), so a correct version would do strictly more
work than this one. A half-space cut plus a fuse per leg costs more than the
corner boolean it replaces. Refuted, with numbers, and not built.

---

## 4. Adjudication — item 2, the taper

### 4.1 P7 — the defect is real and the brief's diagnosis of it is wrong

**"A spine of more than one edge" is not the trigger.** Two and three
**collinear** spine edges give the tapered frustum to the last digit:

```
                                  volume        A*L*(1+k+k^2/3)     valid
1 spine edge, taper 10 deg      4746.762862      4746.762862        yes
2 collinear edges               4746.762862      4746.762862        yes
3 collinear edges               4746.762862      4746.762862        yes
```

P7(1) HELD: the frustum integral is exact, so `Law_Linear` scales the section's
poles about the section's own origin, which the fixture puts on the spine.
P7(3) HELD: ray probes across the joint give 10.440377 just below and 10.441258
just above — the law is continuous, distributed across spine edges by arc
length, exactly as `BRepFill_Sweep`'s `Sweep.SetDomain(lf, ll, Vi(i), Vi(i+1))`
says it should be. **The law-restart mechanism is refuted, as pre-registered.**

The trigger is a **MITRED JOINT**:

```
joint    taper   faces  volume         BRepCheck   bbox xmin   -EvalExtrapol
 0.4       10      9    8306.740205    valid        0.0000     -0.0868  (deadband)
 0.6       10     10    8324.566702    INVALID     -0.0014     -0.1253
15.0        0.1   10    7299.701628    INVALID     -0.6848     -2.6404
15.0       10     10    8688.921317    INVALID     -0.7528     -2.9084
90.0       10     10   11136.303683    INVALID    -22.0252    -22.0252
90.0        0      8    6000.000000    valid        0.0000     -20.0100
```

### 4.2 The mechanism, and the number that proves it

Before mitring, `BRepFill_Sweep` EXTENDS both adjacent surfaces past the vertex
by `EvalExtrapol()`:

```
R      = 2 * max|section bounding box| at the joint
Extrap = R * tan(alpha/2) + 100 * myTol3d
```

then trims them back with `BRepFill_TrimShellCorner`. With an evolving section
that trim fails, and `PerformCorner`'s answer to a failed trim is:

```
else if ((TheTransition == BRepFill_Right) || aTrim.HasSection())
  return Standard_True;   // Nothing is touched
```

— **success, with the extensions left in.** `MakePipeShell` reports `IsDone()`,
`MakeSolid()` succeeds, and the caller is handed two shells passing through each
other.

The extension survives into the result and can be checked without a debugger. At
90 degrees the section's half-width at the joint is `10 * (1 + k*40/70) =
11.00758`, so `Extrap = 2*11.00758*tan(45 deg) + 100*1e-4 = 22.02517`. The
result's bounding box starts at **x = -22.0252**. Five figures, computed from
OCCT's source and confirmed by the shape.

Two faces is the other tell: eight faces when the corner is trimmed, **ten** when
the two extensions survive, nine below the deadband where nothing is extended.

### 4.3 It is not a mode choice — all three were measured

```
                      theta=15                       theta=90
RightCorner   f=10 INVALID  8688.921317      f=10 INVALID  11136.303683
Transformed   f= 9 valid    8174.277422      f=10 INVALID   3309.573273
RoundCorner   f=13 INVALID  8132.246961      f=13 INVALID   7259.306724
```

`Transformed` is "valid" at 15 degrees and is the wrong shape anyway, for every
reason in §3. No OCCT transition mode produces a correct tapered corner.

### 4.4 P8 — what shipped, and what did not

P8 was registered as a rule: *if the cause is in OCCT rather than in the shim,
the deliverable is the diagnosis and a refusal, not a workaround that makes
`BRepCheck_Analyzer` happy.* The cause is `BRepFill_TrimShellCorner`. So v27
**refuses**, on OCCT's own predicate:

* the test is the largest angle between consecutive EDGES OF THE BUILT SPINE
  WIRE, measured the way `PerformCorner` measures it — from the tangent at the
  end of one edge and the tangent at the start of the next, orientation
  respected. It is the built spine and not the input points, so a run v24 has
  already smoothed into one B-spline edge has no joint left to refuse;
* the boundary is `angmin = 1.0e-2` rad = 0.5730 deg, **OCCT's own deadband**,
  below which it never extends anything and the tapered sweep is valid.

**Nothing that built correctly stops building.** A taper on any single-edge
spine is untouched: a straight path, `occt_coil_profile`'s analytic helix, and —
because v24 interpolates it — an arc or a circle the application's own sampler
produced. Smoke [42e] pins each of those, plus the 0.4 / 0.6 degree pair across
the deadband, plus that the SAME corner without a taper still returns (I) to the
last bit.

What is now refused was returning a self-intersecting solid, and the app had no
way to see that from the result.

---

## 5. Defects found and NOT fixed

1. **A sweep whose section is far off the spine goes INVALID on a many-jointed
   path, with no taper involved.** The 16-edge polyline arc of S14's fixture,
   swept with the `[0,10]^2` square whose corner sits on the spine: 66 faces,
   volume 6553.070936, **INVALID**. The discriminator is the OFFSET, not the
   corner treatment — the same path with a CENTRED `[-5,5]^2` square is
   6000.000000 and valid (and is `A*dz` exactly, §3.5), and with a smaller
   `[0,2]^2` square it is valid too. My reading is that the mitre wedges of
   adjacent joints collide once the section reaches far enough outside the
   path's curvature, which would make it geometry rather than a kernel defect —
   but I did not confirm that and it is a guess. **Recorded, not chased.**
2. **`finish_pipe` never checks the result.** It returns whatever
   `MakeSolid` produced without asking `BRepCheck_Analyzer`, which is how the
   taper defect stayed invisible for as long as it did. Adding a validity gate
   is a one-line change and a MUCH larger behaviour change than this session's:
   defect 1 above would start failing, and so would anything else in the field
   that is quietly invalid today. **The integrator's call, not mine.**
3. **S14 §6.2's three defects are untouched** — the tilted-arc hole deficit was
   fixed by v26 and the other two stand as recorded.

## 6. Things I deliberately did not do

* **No new ABI.** `Transformed` is not exposed. It is 17.5x faster and wrong at
  every joint angle; shipping a mode that is provably wrong so that a caller can
  choose it would be the worst outcome of this session.
* **No `angmin` change.** S14 refuted it; §3.1's 0.5-degree row shows exactly
  what widening it buys — the mitre silently becomes Transformed.
* **No Dart, no `perf/baseline.json`, no `PERFORMANCE_PROFILE.md`.**
* **`CALIBRATION.txt` is NOT re-recorded**, per the integrator's 2026-08-21
  ruling that S14 records.

## 7. What I am unsure of

In order of what it would cost to be wrong.

1. **Whether refusing is the right product answer for the tapered corner.** I am
   confident about the geometry and not about the decision. A user who drew an
   L, set a draft angle, and got a part now gets an error instead. The part they
   got was self-intersecting and BRepCheck rejects it — but I have not seen it
   rendered, and it is possible that at 1 degree of taper across a 2 degree
   joint the wrongness is invisible and the refusal is more disruptive than the
   defect. The measurement that would settle it is a rendering, and I have
   neither the app nor a device. **If the integrator wants the capability back,
   §3.7's per-leg route would do it correctly — it is only refuted on SPEED, and
   for a tapered corner there is nothing to be faster than.**
2. **The 79-second rung.** §3.6 measures 3.1 s here where the brief's device
   number implies about 23 s. I do not know whether the device fixture has a
   hole in it, more corners, or longer legs. Everything in §3 is about ratios
   and volumes and is unaffected; the headline is not.
3. **Whether `EvalExtrapol` is the whole story for the taper.** I proved the
   extension survives — five figures of bounding box agreement is not a
   coincidence — and I read the "Nothing is touched" branch in the source. I did
   NOT instrument `BRepFill_TrimShellCorner::Perform()` to watch it return
   false, because that needs a patched OCCT. So "the trim fails" is an
   attribution from two independent pieces of evidence rather than a direct
   observation, in exactly the sense S14 §7.6 meant.
4. **Whether (I) survives a section that is not planar-perpendicular to leg 1.**
   Every fixture here places the profile in a plane the first leg is normal to.
   S14's arc fixture does not — its section is tilted 25.2316 degrees to the
   tangent — and (I) with `c_t = 0` still predicted it correctly (§3.5), but
   that is the easy case, since a centred section has no wedge to get wrong. A
   TILTED and OFF-CENTRE section at a drawn corner is a case I did not measure,
   and defect 1 in §5 may well live there.
5. **The `share` column's limit.** 0.969 at 0.6 degrees is the closest to the
   deadband I measured, and the algebra says it goes to 1. I did not measure at
   0.58 degrees, where floating point on the angle test starts to matter.
6. **Everything about time on a device**, as always. Desktop milliseconds on a
   shared four-core container; `backend/bench/README.md` says why.

## 8. Handover

### 8.1 The bar, answered plainly

**512 segments on a 3-corner path does not stop being expensive, and now there
is a derivation saying why it cannot.** `Transformed` is not a shallow-joint
approximation of a mitre — it supplies none of the corner's first-order effect
at any angle, it never rotates the section at all, and its error compounds down
the spine. The convergence in S14's table is the corner vanishing, not the two
treatments agreeing, and the 19.47-degree crossover is `asin(2*c_t/L2)` — a
property of the square's centroid and the second leg's length.

A drawn corner is **genuinely** expensive, not accidentally expensive. That is
the brief's stated acceptable failure and it is what this session found.

### 8.2 What the integrator has to decide

**v27 is a behaviour change and it is not mine to merge.** A tapered sweep
across a drawn corner returns NULL where it used to return a solid. The solid
was self-intersecting and OCCT-invalid, and no call site can have depended on it
being right — but a call site can certainly have depended on it being non-NULL.
The escape hatches, in increasing order of work:

* drop the taper, or straighten the path — both already work;
* declare `OCCT_SWEEP_PATH_SMOOTH`, if the corner really was a sampled curve —
  one spine edge, taper works, nothing is refused;
* build §3.7's per-leg + bisector route, which is correct and slower, and is the
  only way to have a tapered drawn corner at all.

### 8.3 For whoever picks up the sweep next

* `V = A*dz` (§3.5) is a better analytic pin than anything S14 had, and it costs
  nothing: any sweep of a section centred on its spine, in any corner mode, at
  any sampling density.
* `V = A*L - 2*A*c_t*sum(tan(theta_i/2))` is signed — a turn away from the
  centroid ADDS volume — and smoke [42d] and the staircase fixture both check
  it that way.
* The face count is the cheapest corner diagnostic in the kernel: 8 faces
  trimmed, 10 untrimmed, 9 never treated.

### 8.4 Definition of done

| | |
| --- | --- |
| Predictions committed BEFORE the code | `6371169` (P1–P8), before a line of shim or bench was touched |
| `occt_smoke` on real OCCT 7.9.3 | **OCCT SMOKE: PASS**, including new scenario [42] and all five of its arms |
| `occt_mesh_recon_test` | **ALL PASSED (132 passed, 0 failed)** |
| `python3 -m unittest discover -s ci` | **52 tests, OK** |
| `occt_bench` (Lane C) | **LANE C: PASS, HARNESS: VALIDATED** — all three calibration exponents agree with §6.5 |
| `gcc -fsyntax-only` brace guard | run before every commit, and it caught one unterminated comment |
| `flutter analyze` delta | **cannot be run: no Flutter SDK in this container.** No Dart file was touched — `git diff --stat` over `frontend/` is empty — so the delta is zero by construction, but that is an argument and not a measurement, and it is recorded as an argument. |
| `flutter test` | same — not runnable here, no Dart touched |

The OCCT install used for all of the above was built from the pinned `V7_9_3`
submodule with `backend/occt/VENDOR.md`'s exact configure line. Nothing was
mocked and no number here comes from a replica that was not checked against the
shim: §4.3's direct `BRepFill_PipeShell` runs reproduce `occt_sweep_profile`'s
6868.347502, 6000.000000 and 8688.921317 exactly, and the replica reproduces
S14's 3200.000000.
