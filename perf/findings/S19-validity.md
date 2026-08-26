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

---

# What was measured

OCCT 7.9.3 built from the pinned `V7_9_3` submodule with `VENDOR.md`'s exact
configure line, Release, on a shared four-core container. `occt_smoke` prints
**OCCT SMOKE: PASS** on this kernel before and after everything below.

Every shape classified or timed here came out of the shipped
`occt_sweep_profile_ex`. The probe reads the `TopoDS_Shape` out of the shim's
handle through a redeclaration of its one-member struct, and checks that
assumption on **every shape it builds** by comparing its own
`BRepCheck_Analyzer` against `occt_shape_valid`. Across all nine arms —
several thousand shapes — **shim/probe validity disagreements: 0**.

## 2. Adjudication — the cost

### 2.1 The two ladders

```
--- P1: n-gon profile, STRAIGHT one-leg path, 40 mm
     n   faces      build       full   full-par       topo   topo-par   valid
   128     130      159.1       19.0       13.1      15.97      12.12     yes
   256     258      102.3       47.9       31.0      38.78      27.57     yes
   512     514      275.7      124.3       80.4     102.10      56.74     yes
  1024    1026     1061.5      386.5      251.3     332.85     158.95     yes
  exponent in n: full 1.441   full-par 1.416   topo 1.454
  full/full-par mean 1.52x   full/topo mean 1.20x

--- P2: 256-gon profile, POLYLINE helix, spans varying
 spans   faces      build       full   full-par       topo   topo-par   valid
     1     258      101.4       47.6       33.0      39.35      26.66     yes
     4    1026    23754.9      114.6       76.2      94.53      68.82     yes
    16    4098    41038.6      417.4      300.1     351.86     277.42     yes
    64  BUILD FAILED: occt_sweep_profile: BRep_API: command not done
  exponent in spans: full 0.783
```

| | prediction | outcome |
| --- | --- | --- |
| **P1** | exponent in n = 2.00 ± 0.20 | **REFUTED** — 1.441. The secondary absolute claim held: 386.5 ms at n = 1024 against a derived 599 ms |
| **P2** | exponent in spans = 1.00 ± 0.20 | **REFUTED, marginally and in the safe direction** — 0.783, on three rungs only because the 64-span build does not complete |
| **P3** | topology-only is ≥ 10× cheaper | **REFUTED, and not marginally** — 1.20×, and its exponent is 1.454 against full's 1.441, i.e. the same curve |
| **P5** | parallel buys 1.5×–3.5× | **HELD**, at the bottom of the interval — 1.52× |

**P1's refutation matters more than its number.** The model behind it — that the
two cap wires' O(n²) self-intersection is what the check spends its time on —
is what §1.1 built the extrapolation on, and it is wrong for a hole-free sweep.
P3 says why: turning the geometric controls OFF removes 17 % of the cost, so
the wire self-intersection cannot have been most of it. The check is dominated
by per-subshape work that both settings pay.

### 2.2 The anchor: S15 §2.2's row, reproduced, and asked four ways

```
shape                                faces      build       full   full-par       topo   topo-par
1200-gon, 16-span arc, AUTO           1202     3653.3      640.7      437.2      468.3      259.2  valid
   as a share of the build                                 17.5%      12.0%      12.8%       7.1%
1200-gon + 1200-gon hole, AUTO        2402     9174.8    11314.5     6054.7    11264.5     5850.0  valid
   as a share of the build                                123.3%      66.0%     122.8%      63.8%
```

S15 measured 821.8 ms and 8 817.1 ms for those two `valid` stages; this run
gets 640.7 and 11 314.5 on a different container. Same regime, same 10-fold
step between them, and **the brief's headline is confirmed: on the holed
1200-segment sweep a gate costs more than the construction it is gating** —
123.3 % of it.

It is also the only regime in the session where that is true, and the reason is
the one §1.1 named and P1 refuted everywhere else: this shape's cap wires have
1 200 edges each, so here the quadratic term really does dominate. Note the
topology-only column: **122.8 %**. Even here the geometric controls are half a
percent of the bill.

### 2.3 What the gate actually costs, as one table

Shares of the operation being gated, all measured through the shipped call:

| shape | faces | build | full check | share |
| --- | ---: | ---: | ---: | ---: |
| 20-cube — the scale `blend_result_ok` already gates | 6 | 0.93 | 0.84 | 90.1 % |
| 24-gon prism, extruded | 26 | 2.06 | 4.91 | 238.5 % |
| 24-gon × 16-leg helix, POLY | 386 | 188.1 | 31.2 | 16.6 % |
| 1024-gon, straight | 1026 | 877.2 | 391.5 | 44.6 % |
| 1024-gon × 16-span helix, SMOOTH | 1026 | 3992.7 | 518.8 | 13.0 % |
| 1200-gon × 16-span arc, AUTO | 1202 | 3653.3 | 640.7 | 17.5 % |
| 256-gon × 16-leg helix, POLY | 4098 | 40583.7 | 399.1 | **1.0 %** |
| 1200-gon + hole × 16-span arc, AUTO | 2402 | 9174.8 | 11314.5 | **123.3 %** |

**The share is not monotone in size and it is not a single number.** It is
238 % on a 26-face prism that builds in two milliseconds, 1.0 % on a 4 098-face
sweep that takes forty seconds, and 123 % on the one holed shape. A percentage
is the wrong unit for the small end — 0.84 ms on a 20-cube is 90 % of its build
and nobody would notice it — and the right unit for the big end, where the
absolute is 11.3 seconds.

**The shim already ships this gate.** `blend_result_ok` (`occt_capi.cpp:2938`)
ends in `BRepCheck_Analyzer(out).IsValid()`, has since v11, and exists because
an invalid blend made the mesher emit sixty thousand triangles for a twenty-face
solid. So the policy question is not whether the shim may gate on validity. It
is whether the sweep's shapes are big enough to make the same policy cost
something different, and the answer is: **only the holed 1200-segment one, and
there it doubles the operation.**

### 2.4 P4 — the prediction I said I would most like to be wrong about

```
configuration                                        faces         volume    build  full    topo
L corner 0.4 deg, centred section, taper 10.0           10    9493.400696      3.3  valid   ok
L corner 0.6 deg, centred section, taper 10.0           10    9504.046825     14.4  INVALID BAD
L corner 15.0 deg, centred section, taper 10.0          10    9689.752753     15.4  INVALID BAD
L corner 90.0 deg, centred section, taper 10.0          10   10437.167052     17.6  INVALID BAD
helix 16 legs POLY, square at [-5,5], no taper          66    6000.000000     41.4  valid   ok
helix 16 legs POLY, square at [0,10], no taper          66    6553.070936     42.5  INVALID BAD
```

**P4 is REFUTED, and it is the most useful thing in this session.** The
topology-only check catches both known defects, and — see §3 — it catches
**136 of 136** invalid configurations in the census. The reasoning behind P4
was that OCCT leaves two shells passing through each other and that passing
through a face is not a topological defect. The first half is right (§4). The
second half is wrong about what BRepCheck ends up seeing: the dominant status
on an untrimmed corner is `BRepCheck_NotConnected` **on the shell**, which is as
topological as a status gets.

The consequence for the decision is not a cost saving — P3 killed that — but a
much better one: **the gate does not depend on the expensive half of the check
being run.** Whatever an integrator decides about `GeomControls`, the answer to
"would a gate have caught this" is yes.

---

## 3. The census — what is invalid today

405 configurations: 9 paths × 5 sections × 3 orientations × 3 tapers, each
built through `occt_sweep_profile_ex` and classified both ways.

```
--- census: 405 configurations, 0 refused, 136 INVALID (33.6% of what built),
    136 of those caught by the topology-only check
shim/probe validity disagreements: 0
```

**Nothing is refused. A third of the configuration space silently returns an
invalid solid.**

### 3.1 Which axis it is on

| axis | value | INVALID | of |
| --- | --- | ---: | ---: |
| path | straight | **0** | 45 |
| | helix16 AUTO (smoothed to one edge) | **0** | 45 |
| | helix16 SMOOTH | **0** | 45 |
| | L 15° | 20 | 45 |
| | zigzag 6×20 @5° | 20 | 45 |
| | zigzag 6×4 @5° | 20 | 45 |
| | helix4 POLY | 20 | 45 |
| | helix16 POLY | 25 | 45 |
| | L 90° | 31 | 45 |
| taper | 0 | 10 | 135 |
| | +5 | 63 | 135 |
| | −5 | 63 | 135 |
| orientation | 0 (Follow Path) | 63 | 135 |
| | 2 (Follow Path and Guide) | 62 | 135 |
| | 1 (Fixed) | 11 | 135 |
| section | square centred | 25 | 81 |
| | square c_t = 7.07 | 28 | 81 |
| | square c_t = 21.2 | 27 | 81 |
| | ring24 centred + hole | 27 | 81 |
| | ring24 c_t = 20 + hole | 29 | 81 |

**The corner is the whole story.** Every one of the 136 is on a spine with a
mitred joint. The three jointless paths — a straight line, and the two that
`spine_from_points_ex` interpolates into a single B-spline edge — are clean at
every section, orientation and taper tried, 135 for 135. On the six jointed
paths the rate is **136 of 270, 50.4 %.**

Read down the other axes and the ranking is: **a taper across any mitred joint**
(126 of the 136), then **an off-centre section across a mitred joint with no
taper at all** (the rest). Orientation 1 is not safer for a reason anybody
should rely on — its 11 failures are all on the 90° L, where "all sections
parallel" means sweeping a section along a direction lying in its own plane;
every one of them returns volume 3200.000000 identically and a
`SelfIntersectingWire`. That is a degenerate request, not the corner defect.

### 3.2 The classes, as a gate would refuse them

| class | reachable by | example |
| --- | --- | --- |
| **taper ≠ 0 across a mitred joint** | Sweep with a draft angle over a drawn polyline or L path | `L 15° \| square centred \| or0 \| tap+5` → 8892.351060, INVALID |
| **off-centre section across a mitred joint** | any sweep whose profile sketch is not centred on the path — the default, since nothing re-centres it | `helix16 POLY \| square c_t=7.07 \| or0 \| tap+0` → 6553.070936, INVALID |
| **orientation 1 on a ≥ 90° turn** | Sweep, Orientation = Fixed, over an L | `L 90° \| square centred \| or1 \| tap+0` → 3200.000000, INVALID |
| **a hole across a mitred joint** | any of the above with a holed profile | `L 90° \| ring24 centred + hole \| or0 \| tap−5` → **−933.602882**, INVALID |

The last row is worth its own line: **a negative volume**. The solid is
inside-out, `has_solid_material` passes it, and `finish_pipe` returns it.

### 3.3 What the classes are not

The census is over CLASSES and cannot prove coverage: it says which classes
contain an invalid producible part, not that the classes it found clean contain
none. In particular `twist_deg` is refused already, `path_mode` was exercised at
its three values and not at every path shape, and the profile placements were
translations — a rotated `mat34`, which S16 §1.4 would have wanted, is not here.

---

## 4. S18 §5.1 — closed

### 4.1 The reproduction, first

```
configuration                                        faces         volume    build  full    topo  what BRepCheck says
[-5,5]^2 centred, helix 16 legs POLY                    66    6000.000000     44.9  valid   ok
[0,2]^2, helix 16 legs POLY                             66     239.661209     44.1  valid   ok
[0,10]^2 corner on spine, helix 16 legs POLY            66    6553.070936     46.0  INVALID BAD   shell:NotConnectedx2
```

**66 faces, 6553.070936, INVALID — S18's row to the last digit**, and the
centred control is 6000.000000 exactly. Everything below rests on that.

The diagnosis, which `occt_shape_valid`'s bool throws away, is
`BRepCheck_NotConnected` on the shell: the solid's boundary is in more than one
connected piece.

### 4.2 P6 — the collision guess is refuted, and by more than predicted

**P6 HELD.** The validity boundary in the offset is at **c ≈ 5–6** on this
fixture, against the fold threshold (I) of **99.10**. A factor of seventeen, not
the factor of seven P6 registered.

```
--- P9a: offset ladder at spans=16 (leg 4.1452, joint 2.3962 deg)
      c_t     reach  faces         volume verdict
    0.000     7.071     66    6000.000000 valid
    5.000    12.071     66    5970.054855 valid
    6.000    13.071     66    6513.175853 INVALID
   99.000   106.071     66    9977.235403 INVALID
```

S18's guess — *"the mitre wedges of adjacent joints collide once the section
reaches far enough outside the path's curvature"* — is **not the mechanism.**
Two independent facts kill it:

* the boundary is at a seventeenth of where adjacent wedges could possibly
  meet; and
* **the joint COUNT does not enter at all.** §4.5's ladder finds the identical
  boundary, 4.3072 to five figures, at 4, 8, 16 and 32 legs. A collision
  between *adjacent* joints cannot be independent of how many joints there are.

It is a per-joint, per-leg condition.

### 4.3 P8 — refuted, and the deadband makes it worse, not better

```
--- P8: the same off-centre square, path subdivided
 spans       leg  maxjoint  faces         volume verdict
     2   33.0120   18.3792     10    5987.031548 valid
     8    8.2886    4.7830     34    5962.158560 valid
    16    4.1452    2.3962     66    6553.070936 INVALID
    64    1.0364    0.5994    258    6489.744024 INVALID
    96    0.6909    0.3996    386   31118.877656 INVALID
   128    0.5182    0.2997    514   39367.640567 INVALID
   192    0.3455    0.1998    770   39310.932086 INVALID
```

**P8 is REFUTED.** Every joint from spans = 96 up is below OCCT's `angMin`
deadband of 0.5730°, where `EvalExtrapol` returns 0.0 and nothing is extended —
and the solid is not merely still invalid, its volume goes from 6 553 to
**39 368**, six times the correct 6 000. The prediction had the direction
exactly backwards, and the fixture gets worse in the regime that was supposed to
be safe.

### 4.4 What the discriminator actually is

The zigzag fixture — six legs, section off-centre by any amount, leg from 1 to
40, turn from 0.3° to 90° — is **valid in every cell**. It differs from the
helix in one respect that matters: its first leg runs along +Z, and the section,
placed by the identity matrix, lies in the XY plane. **The section is
perpendicular to the tangent.** The helix's first tangent is 25.244° off +Z.

Two controls say that is the variable:

* **`--accumulate`.** A PLANAR polygonal arc built with the helix's own numbers
  — 15 joints of 2.3962°, legs of 4.1452, tilt 25.244° — reproduces the helix's
  verdicts cell for cell:

  ```
       c_t   0.000   5.000   7.071  10.000  15.000  21.200  40.000
    planar       .   INVAL   INVAL   INVAL   INVAL   INVAL   INVAL
     helix       .   INVAL   INVAL   INVAL   INVAL   INVAL   INVAL
  ```

  So the helix being non-planar is not it either.

* **The shipped ABI's own control.** `Add(..., WithCorrection)` is documented as
  *"the section is rotated to be orthogonal to the spine's tangent"*, and
  `occt_sweep_profile_ex` passes it `Standard_True` for orientation 2 and
  `Standard_False` for orientation 0. On the S18 §5.1 fixture:

  | orientation | WithCorrection | volume | verdict |
  | --- | --- | ---: | --- |
  | 0 | False — the tilt is kept | 6553.070936 | **INVALID** |
  | 2 | True — the tilt is removed | 6585.530029 | valid |
  | 1 | (Fixed frame) | 6000.000000 | valid |

  Removing the tilt, and nothing else, makes the same fixture valid.

### 4.5 (S19-1) — the boundary, found and then tested where it was not fitted

Bisecting for the smallest invalid offset over the planar-arc fixture:

```
 legs      leg    joint     tilt         c*       c*/L c*sin(t)/L
   16   4.1452   2.3962   25.244     4.3072     1.0391     0.4431
   16   4.1452   2.3962   10.000    16.3403     3.9420     0.6845
   16   4.1452   2.3962   45.000     0.7420     0.1790     0.1266
   16   8.2904   2.3962   25.244    13.6135     1.6421     0.7003
   16  16.5808   2.3962   25.244    32.2277     1.9437     0.8289
   16   4.1452   1.0000   25.244     4.5429     1.0959     0.4674
   16   4.1452   5.0000   25.244     3.8960     0.9399     0.4008
    4   4.1452   2.3962   25.244     4.3072     1.0391     0.4431
    8   4.1452   2.3962   25.244     4.3072     1.0391     0.4431
   32   4.1452   2.3962   25.244     4.3072     1.0391     0.4431
    6  20.0000   5.0000   25.240    37.9276     1.8964     0.8086
    6  20.0000   5.0000   45.000    22.1012     1.1051     0.7814
   16  20.0000   5.0000   25.240    37.9276     1.8964     0.8086
```

Neither `c*/L` nor `c*·sin(tilt)/L` is constant. Both terms together are:

```
    d · ( sin(phi) + tan(theta/2) )  =  L                            (S19-1)
```

with **d = c + w** the section's furthest reach from the spine toward the turn,
**phi** the tilt of the section's plane to the plane normal to the tangent,
**theta** the joint angle and **L** the leg. Every row above satisfies it to
within 1.8 %, and the two rows that report "0 already" — tilt 60°, and leg
2.0726 — are the two where (S19-1) puts the boundary at a negative offset, i.e.
predicts failure even for a centred section. Which is what they do.

**It reads as geometry, and both terms are quantities the earlier sessions
already named.** Take the section's far edge, the one at distance `d` on the
outside of the turn:

* because the section is tilted, that edge starts `d·sin(phi)` further along
  the spine than the spine's own start point;
* at the far end, the mitre at the joint cuts `d·tan(theta/2)` of arc length off
  it — S18 §8.3's own quantity, the one its signed volume law
  `V = A·L − 2·A·c_t·Σtan(θ_i/2)` is built from;
* the leg is `L` long.

When the two together reach `L`, **that edge has no leg left to sweep along.**

S18's guess is the `phi = 0` special case of (S19-1): with no tilt the condition
collapses to `d·tan(theta/2) > L`, which is the fold condition (I), whose
threshold on this fixture is 99.10 and unreachable. **The guess was not wrong so
much as missing its dominant term** — and the term it was missing is the one
S18 §7.4 had already written down as the case it had not measured: *"a TILTED
and OFF-CENTRE section at a drawn corner is a case I did not measure, and defect
1 in §5 may well live there."* It does.

**The out-of-sample test.** The half-width `w` was held at 5 for every row that
produced (S19-1). So `w` is where it was tested, along with fresh legs, joints
and tilts:

```
     w      leg    joint     tilt   c* pred    0.9 c*    1.1 c*   verdict
   2.0   4.1452   2.3962   25.244    7.2653     valid   INVALID  HELD
   2.0  20.0000   5.0000   25.244   40.5410     valid   INVALID  HELD
  10.0   4.1452   2.3962   25.244   -0.7347  (predicted invalid at every offset)
  10.0  20.0000   5.0000   25.244   32.5410     valid   INVALID  HELD
  10.0  40.0000   3.0000   15.000  130.3484     valid   INVALID  HELD
   1.0  10.0000   2.0000   30.000   18.3253     valid   INVALID  HELD
   5.0  30.0000   1.5000   20.000   79.4807     valid   INVALID  HELD
   7.5  12.0000   4.0000   35.000   12.2207     valid   INVALID  HELD

(S19-1) held on 7 of 7 out-of-sample rows
```

The one row of §4.5's ladder that (S19-1) does not fit — joint 10° — is a
bisection artefact, not a miss. Scanned rather than bisected, that fixture's
invalid set is **not an interval**: valid to c = 2, INVALID from 4 to 40, valid
again 42 to 50, INVALID from 52. The bisection reported the *last* transition
at 51.8. (S19-1) predicts the FIRST at **3.0652**, and the scan puts it between
2 and 4.

### 4.6 The mechanism, observed rather than inferred

S18 §7.3 listed as an uncertainty that it had *"NOT instrumented
`BRepFill_TrimShellCorner::Perform()` to watch it return false, because that
needs a patched OCCT."* The submodule is here, so it was patched — one
`fprintf` at each of its five failure returns and at `PerformCorner`'s
"Nothing is touched" branch, in a THROWAWAY build. On the S18 §5.1 fixture:

```
[S19] TrimShellCorner FAIL: MakeFacesSec row 1
[S19] PerformCorner index 2: NOTHING IS TOUCHED (extensions survive), alpha=2.396243 deg
```

and across the whole `--law` fixture set, 36 corners failed and the
correspondence is exactly one to one:

```
      36 [S19] TrimShellCorner FAIL: MakeFacesNonSec row R
      36 [S19] PerformCorner index N: NOTHING IS TOUCHED, alpha=A deg
```

So the chain is observed end to end:
`MakeFacesSec`/`MakeFacesNonSec` cannot rebuild the corner's paired faces →
`Perform()` leaves `myDone` false → `PerformCorner` takes
`else if ((TheTransition == BRepFill_Right) || aTrim.HasSection()) return
Standard_True; // Nothing is touched` → `MakePipeShell` reports `IsDone()`,
`MakeSolid()` succeeds, and `finish_pipe` returns it. **It is the same silent
success S18 §4.2 pinned for the taper, and it is now watched rather than
attributed.**

Two details the instrumentation adds:

* on the no-taper off-centre fixture **exactly one corner fails — index 2, the
  FIRST interior joint**, out of fifteen. Which is what (S19-1) says: the
  condition is about the leg the section is actually sitting on.
* on a tapered centred fixture **all fifteen fail**, because `Law_Linear` grows
  the section along the spine and `d` grows with it.

Across the seven `--attribute` cases, "Nothing is touched" fires on exactly the
two that come out invalid and on neither of the five that come out valid.

### 4.7 P7, P9, P10 — the scorecard

| | prediction | outcome |
| --- | --- | --- |
| **P6** | the wedge-collision guess is refuted | **HELD** — boundary at ~5, threshold 99.10, and the joint count does not enter |
| **P7** | the mechanism is `TrimShellCorner` failing and `PerformCorner` returning "Nothing is touched" | **HELD on the mechanism, observed directly (§4.6). REFUTED on the tell** — the observable is `shell:NotConnected`, not a self-intersection, and the bounding-box overshoot P7 predicted is not what distinguishes the invalid rows |
| **P8** | subdividing under the deadband makes it valid | **REFUTED**, in the opposite direction: still invalid, and the volume goes to 6× the correct one |
| **P9** | the boundary is at c ≈ L within a factor of 2 | **HELD as a bracket and superseded as a law** — c*/L runs 0.18 to 3.94 across the ladder; (S19-1) is what is constant |
| **P10** | `Extrap > L` is not the discriminator | **HELD** — it is 0.4283 against a leg of 4.1452 in the failing row, and the failure is in the trim, not the extension |

### 4.8 The one thing this does not explain

`--attribute` shows the shape is already invalid **after `MakeSolid` and before
`ShapeUpgrade_UnifySameDomain`**, with identical faces and volume on both sides,
in all seven cases. So the shim's own last line is not implicated, and the
defect is OCCT's. What (S19-1) does NOT account for is the volume EXPLOSION
below the deadband in §4.3 — 39 368 against 6 000 at spans = 128. Nothing is
extended there and nothing is trimmed, so it is a third behaviour rather than
this one continued, and it is recorded and not chased.
