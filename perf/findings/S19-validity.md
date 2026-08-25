# S19 — what a validity gate costs, and what is invalid today

Branch `claude/finish-pipe-validation-blnp1n`. Owns `backend/occt/**` —
shim, tests, and `backend/bench/**` for the instrument. Shim version **v29**
and smoke scenario **[43]** were handed out with the brief.

S18 §5.2 found that `finish_pipe` returns whatever `MakeSolid` produced
without ever asking `BRepCheck_Analyzer`, called adding the gate "a one-line
change and a MUCH larger behaviour change than this session's", and routed the
decision to the integrator. A decision needs two numbers S18 did not have:

1. **what the check costs**, in the regime the field actually reaches. S15 §2.2
   measured `occt_shape_valid` at **8 817.1 ms** on a 2 402-face solid, against
   a construction of 7 952.7 ms for the same shape — so "one line" is true of
   the diff and false of the consequence;
2. **which producible sweep configurations are invalid today**, because that is
   the list of parts that would stop building the day the gate lands.

And one loose end: S18 §5.1 recorded an off-centre section going INVALID on a
many-jointed path *with no taper involved*, guessed at a mechanism, and
labelled the guess unconfirmed. This session chases it.

---

## 1. Pre-registration

Committed before a line of instrument, shim or test was written, per
`OPTIMIZATION_PLAN.md` §2. Every number below is derived from OCCT's own
source or from an earlier session's published measurement; nothing is fitted.

### 1.0 The fixtures, in exact numbers

**The path.** `bench_sweep.h`'s `arcPathXYZ(n, 60)` — the device fixture, and
S14's, S15's and S18's. It is a helix: a quarter turn of radius 18 in XY while
z rises to 60, at constant speed. Its arc length is 66.33 and its radius of
curvature is **ρ = 99.06 everywhere**. Sampled at `spans + 1` points and taken
as a POLYLINE it has `spans` legs of equal length `L` and `spans − 1` interior
joints of equal angle θ:

| spans | L | θ (deg) | tan(θ/2) | L / (2·tan(θ/2)) |
| ---: | ---: | ---: | ---: | ---: |
| 2 | 33.0120 | 18.3792 | 0.161778 | 102.03 |
| 4 | 16.5628 | 9.4905 | 0.083010 | 99.76 |
| 8 | 8.2886 | 4.7830 | 0.041764 | 99.23 |
| 16 | 4.1452 | 2.3962 | 0.020914 | **99.10** |
| 32 | 2.0727 | 1.1987 | 0.010461 | 99.07 |
| 128 | 0.5182 | 0.2997 | 0.002615 | 99.06 |

The last column converges to ρ, which is the point of printing it — see P6.

**Which mode the app sends.** `part_model.dart:7411 sweepPathModeOf` maps a
*drawn straight-segment polyline* to `SweepPathMode.polyline`, i.e.
`OCCT_SWEEP_PATH_POLY`, and a drawn polyline is what a user draws and what a
DXF import produces. At 16 spans every joint is 2.3962° — under
`kSampledJointDeg` = 5.625°, so AUTO would smooth the whole path into one
B-spline edge with no joints at all. **The many-jointed regime is reached by
POLY, and POLY is reached by drawing a path rather than tracing an arc.** This
is not an exotic configuration.

**The sections.** A 10×10 square, placed by the profile sketch's own frame:
`_recomputeSweep` hands the kernel `frame.mat34(0)` and nothing anywhere
re-centres the profile on the path. So the offset between section and spine is
whatever the user drew.

| name | corners | centroid offset c_t | max reach d |
| --- | --- | ---: | ---: |
| centred | [−5,5]² | 0 | 7.071 |
| small off-centre | [0,2]² | 1.414 | 2.828 |
| corner-on-spine | [0,10]² | 7.071 | 14.142 |

S18 §5.1 measured the first VALID (6000.000000, and `A·dz` exactly), the second
VALID, the third **INVALID** (66 faces, 6553.070936), all on `spans = 16`,
where **L = 4.1452**.

### 1.1 What `BRepCheck_Analyzer` actually does, from its own header

`BRepCheck_Analyzer(S, GeomControls, theIsParallel, theIsExact)`. Its header
(`src/BRepCheck/BRepCheck_Analyzer.hxx:41`) lists exactly what `GeomControls`
switches on, and every entry is a *geometric* test:
`BRepCheck_InvalidCurveOnSurface` and `InvalidSameParameterFlag` per edge,
`BRepCheck_IntersectingWires` per face, `BRepCheck_SelfIntersectingWire` per
wire. With `GeomControls = Standard_False` "only topological informations are
checked". The shim's `occt_shape_valid` uses the default, i.e. all of it,
single-threaded.

For a sweep of an n-segment profile over an s-leg polyline spine the shape has
`n·s` four-edge lateral faces and 2 cap faces whose single wire has n edges.
So the check's work splits into

* a term **linear in faces**, `a·(n·s + 2)`, for the per-face and per-edge
  controls; and
* a term **quadratic in n**, `b·2·n(n−1)/2`, for the two cap wires'
  self-intersection, which is the only O(n²) thing in the check.

S15 §2.2's unholed 1 202-face row (n = 1200, SMOOTH spine, so s = 1) puts
`valid` at 821.8 ms for 2 · 1200·1199/2 = 1 438 800 cap pairs plus 1 200
lateral faces, i.e. **b ≈ 0.571 µs per edge pair** if the caps dominate.

### Prediction P1 — the gate's cost is quadratic in profile segments

Target: `BRepCheck_Analyzer(shape, true, false, false)` on a sweep of an
n-segment ring over a STRAIGHT one-leg path, n ∈ {128, 256, 512, 1024}.

Predicted: the fitted exponent in n is **2.00 ± 0.20**. Secondary, and read as
an order-of-magnitude claim only: at n = 1024 the check is
0.571 µs × 2·1024·1023/2 = **599 ms**, and the measurement lands within 3× of
that.

Falsifiable by: an exponent outside [1.80, 2.20]. That would mean the cap
wire's self-intersection is not what the check spends its time on, and every
extrapolation below is built on the wrong term.

### Prediction P2 — and only linear in path legs

Target: the same check, n = 256 fixed, spans ∈ {1, 4, 16, 64}, POLY.

Predicted: exponent in spans **1.00 ± 0.20**. Derivation: the O(n²) cap term
does not move with spans at all; only the `n·s` lateral faces do, and each is a
4-edge face whose controls are O(1).

Falsifiable by: an exponent above 1.20 — which would make the gate's cost grow
with path complexity as well, and change the answer for drawn paths.

### Prediction P3 — the topology-only check is cheap

Target: `GeomControls = Standard_False` against the default, same ladder as P1.

Predicted: **≥ 10× cheaper at n = 512**, and its own exponent in n is
1.00 ± 0.20. Derivation: dropping the geometric controls removes the only
quadratic term; what is left is per-subshape constant work.

### Prediction P4 — and it does not catch anything, which is the whole answer

Target: the two shapes that are known-INVALID today — S18 §4.1's tapered drawn
corner (θ = 15°, taper 10°, 10 faces, 8688.921317) and S18 §5.1's off-centre
16-leg helix — checked BOTH ways.

Predicted: `GeomControls = Standard_False` reports **VALID** on both, where the
default reports INVALID. Derivation: in both cases OCCT leaves the
`EvalExtrapol` extensions in and hands back two shells that pass through each
other. Passing *through* another face is not a topological defect — the shell
is closed, the faces are oriented, every edge is shared by two faces. What
BRepCheck can see is the geometric consequence, and the geometric consequence
is the geometric controls' business.

Falsifiable by: either shape coming out INVALID with the geometric controls
off. **That would be the best possible outcome of this session** — it would
make the gate cost linear instead of quadratic — so it is registered as the
prediction I would most like to be wrong about.

### Prediction P5 — parallel buys between 1.5× and 3.5× on four cores

Target: `theIsParallel = Standard_True`, n = 512, straight path, this
container's 4 cores.

Predicted: speed-up in [1.5, 3.5]. The per-face controls are independent; the
cap wires are two units of work out of `n·s + 2`, and the two biggest units are
exactly the two that cannot be split, so Amdahl bounds this well under 4.

### 1.2 S18 §5.1 — the guess, and the arithmetic that decides it

S18's recorded guess, verbatim: *"the mitre wedges of adjacent joints collide
once the section reaches far enough outside the path's curvature, which would
make it geometry rather than a kernel defect — but I did not confirm that and
it is a guess."*

That guess has a closed form. At a mitred joint of angle θ the section is cut
by the bisector plane, so a point of the section at signed lateral offset d
starts its second leg at arc length ∓ d·tan(θ/2) relative to the spine's own
vertex. Between two consecutive joints separated by a leg of length L, a point
on the inside of the turn loses `d·(tan(θ_i/2) + tan(θ_{i+1}/2))`, and the two
wedges meet — the surface folds back through itself — when that reaches L:

```
    d · (tan(θ_i/2) + tan(θ_{i+1}/2))  >  L                        (I)
```

On the equal-angle fixture (I) is `d > L / (2·tan(θ/2))`, which is the last
column of §1.0's table, and it converges to the **radius of curvature ρ =
99.06**. That is not a coincidence and it is the classic offset-past-the-centre-
of-curvature condition: a section reaching past the centre of curvature folds,
and one that does not, does not.

### Prediction P6 — the collision guess is refuted, by two orders of magnitude

Target: the exact S18 §5.1 fixture — `spans = 16` POLY, `[0,10]²`.

Predicted: it is INVALID at d = 14.142 against a fold threshold of **99.10**,
a factor of 7.0 below it, and sweeping d upward finds the validity boundary
**far below 99**. So the wedges are not colliding, and the answer is a kernel
defect rather than geometry.

Falsifiable by: validity flipping at d ≈ 99. That is S18's guess being right
and this prediction being wrong, and (I) is exactly the arithmetic that would
say so.

### Prediction P7 — the mechanism is the taper's mechanism, without the taper

Predicted: `BRepFill_TrimShellCorner::Perform()` returns not-done, and
`BRepFill_Sweep::PerformCorner` takes its

```cpp
else if ((TheTransition == BRepFill_Right) || aTrim.HasSection())
  return Standard_True;   // Nothing is touched
```

branch (`BRepFill_Sweep.cxx:3562`), leaving the `EvalExtrapol` extensions in the
result — the same silent success S18 §4.2 pinned for the taper. The tell is the
bounding box, and `EvalExtrapol` (`BRepFill_Sweep.cxx:3690`) gives it exactly:

```
    R      = 2 · max(|Xmin|, |Xmax|, |Ymin|, |Ymax|)          (section frame)
    Extrap = max(|Zmin|, |Zmax|) + 100 · myTol3d + R · tan(α/2)
```

Predicted: the result's bounding box overshoots the swept body's own extent, at
the first joint's end, by `Extrap` to **three significant figures**.

Secondary, and the reason this session can close what S18 §7.3 could not: OCCT
is a submodule and its source is here, so `TrimShellCorner::Perform()`'s four
failure returns will be instrumented in a THROWAWAY build and the one that
fires will be named. The submodule is not edited in the repository; the patch
is applied, measured and reverted, and `git submodule status` is shown clean
afterwards.

### Prediction P8 — the deadband is the decisive control

Derivation: `EvalExtrapol` returns 0.0 — nothing is extended, nothing needs
trimming — when `alpha < myAngMin`, and `BRepOffsetAPI_MakePipeShell` hard-codes
`myAngMin = 1.0e-2` rad = **0.5730°** (S18 §4.4, `bench_sweep.h`). So if P7 is
right, subdividing the SAME path finely enough that every joint falls under the
deadband must make the SAME off-centre section VALID.

From §1.0's table θ crosses 0.5730° between spans = 64 (θ = 0.5992°) and
spans = 128 (θ = 0.2997°).

Predicted: `[0,10]²` over the helix, POLY, is **INVALID at spans = 64 and VALID
at spans = 128** — more legs, more joints, more faces, and it becomes valid.
The fold condition (I) says the opposite direction is the dangerous one (finer
legs mean smaller L, so (I) is *easier* to satisfy), so this single row
separates P6's two mechanisms with no fitting at all.

Falsifiable by: spans = 128 still INVALID, which would refute the extension
mechanism and put the taper's diagnosis back in doubt too.

### Prediction P9 — the boundary is the leg, not the curvature

S18's three §5.1 rows at `spans = 16`, `L = 4.1452`, are the only data:

| section | c_t | d | verdict |
| --- | ---: | ---: | --- |
| [−5,5]² | 0 | 7.071 | valid |
| [0,2]² | 1.414 | 2.828 | valid |
| [0,10]² | 7.071 | 14.142 | **INVALID** |

The centred square reaches d = 7.071 > L and is valid, so the boundary is not
in the reach d. It is bracketed in the CENTROID offset by 1.414 < c_t\* ≤ 7.071,
and L = 4.1452 sits inside that bracket.

Predicted: the validity boundary at fixed θ is at **c_t ≈ L**, within a factor
of 2, and it moves with L when L is varied at fixed θ. Registered as the
weakest prediction here: three points and a coincidence are what it rests on,
and the two-way test (vary c_t at fixed L; vary L at fixed c_t) is what
decides it.

### 1.3 The census — what is being enumerated, and what it is not

The census is over the configuration space the SHIM's sweep entry point
exposes, restricted to what `_recomputeSweep` can send: `orientation` ∈ {0,1,2}
(Inventor's three Orientation buttons), `taper_deg` any double, `twist_deg` = 0
(anything else is refused already), `path_mode` ∈ {AUTO, POLY, SMOOTH} as
`sweepPathModeOf` assigns it, one or more profile loops placed by the sketch's
own frame, and an arbitrary path polyline.

It is a census of CLASSES, not a proof of coverage: it says which classes
contain an invalid producible part, and it cannot say that the classes it finds
clean contain none.

### 1.4 What would make me stop

* If P4 is refuted — the topology-only check catches these — the cost question
  collapses and the rest of §1.1's ladder is reported and not pursued.
* If the shipped `occt_sweep_profile_ex` cannot reproduce S18 §5.1's
  6553.070936 to the last digit, nothing downstream of it is trustworthy and
  that becomes the finding.
* **No gate ships from this session.** S18 routed that decision to the
  integrator and this session is the evidence for it, not the execution of it.
  Anything this session ships must be additive and must leave every existing
  call bit-identical.

### Prediction P10 — an amendment, still before the instrument exists

Added after reading `EvalExtrapol` and `Box()` in OCCT's source and before a
single measurement — the probe binary does not exist yet, because the kernel it
links against is still compiling. It is registered as a prediction rather than
folded into P7 because it changes what P7 says the tell should be.

`Box(Sec, U, box)` (`BRepFill_Sweep.cxx:199`) boxes the poles that
`GeomFill_SectionLaw::D0` returns, and for a wire section that law is
`BRepFill_ShapeLaw`, whose curves come from `BRep_Tool::Curve` — the section
wire's own placed 3D curves. So `R = 2·max(|Xmin|,|Xmax|,|Ymin|,|Ymax|)` is
measured **from the world origin, which this fixture puts on the spine's first
point**, not from the section's centroid. That makes `Extrap` computable for
S18 §5.1's three rows without running anything:

| section | R | Extrap at spans = 16 | Extrap / L |
| --- | ---: | ---: | ---: |
| [−5,5]² (valid) | 10 | 0.2191 | 0.053 |
| [0,2]² (valid) | 4 | 0.0937 | 0.023 |
| [0,10]² (**INVALID**) | 20 | 0.4283 | 0.103 |

Predicted: **`Extrap > L` is not the discriminator.** The extension is a tenth
of a leg in the failing row and a twentieth in a passing one — a factor of 2
between them and an order of magnitude of headroom in both. So if P7 is right
about the corner being left untrimmed, the trim is failing for a reason other
than the extension overrunning the neighbouring leg, and naming that reason is
what the instrumented build is for.

Consequence for P7's tell: the bounding-box overshoot on this fixture is
predicted at **0.428 in the extension's own direction**, not at the multiple
legs an "extensions collide" picture would need — small, and measurable only
because it is exactly computable.

Also predicted, and this is the one that would embarrass the arithmetic above:
the boundary in the offset ladder (P9a) does NOT sit where `Extrap = L` would
put it, which on this fixture is R = 396, i.e. a section reaching 198 — four
times past the fold threshold and off the end of the ladder.
